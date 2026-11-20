// [REVIEW-WORKER-SUMMARY] 근로자 상세 → 관리자 리뷰 작성창 근태 수치 계약.
//
// 수정 전(DEV callableGetWorkerReviewSummary rev 00002, 에뮬레이터 실행):
//   근태 present·late·early_leave·NO_SHOW·absent(모두 확정) + present(미확정) 에서
//   응답 {confirmedWorkDayCount: 5} — 노쇼·결근까지 셌다. 앱은 그 5 를 근무일로,
//   그리고 **정시 출근으로도** 넘겼다(normalAttendanceDays: workDaysInMonth, lateDays: 0).
//   목록·알림의 실근무 기준(isActualFinalizedWork)으로는 근무 3 · 정시 2 · 지각 1 이다.
//
// 수정 후:
//   서버 v2 = confirmedWorkDayCount(구 앱 호환, 뜻 그대로) + summaryVersion 2 +
//            actualWorkDayCount·onTimeCount·lateCount(같은 실근무 기준, 건수만)
//   앱    = v2 면 그 값을, 구 서버면 근무일만 쓰고 정시·지각은 **모름(null)** — 추측 금지.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/widgets/dialogs/monthly_review_dialog.dart';

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// 에뮬레이터에서 실제로 받은 응답 모양(합성 6행).
const kOldServer = <String, Object?>{'confirmedWorkDayCount': 5};
const kNewServer = <String, Object?>{
  'confirmedWorkDayCount': 5,
  'summaryVersion': 2,
  'actualWorkDayCount': 3,
  'onTimeCount': 2,
  'lateCount': 1,
};

String _code(String p) => File(p)
    .readAsStringSync()
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

Future<void> _openDialog(WidgetTester t, ({int workDays, int? onTime, int? late}) s) async {
  t.view.physicalSize = const Size(420, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => Scaffold(
    body: ElevatedButton(
      onPressed: () => showMonthlyReviewDialog(ctx,
          reviewerId: 'OWNER', reviewerName: '관리자', businessId: 'BIZ',
          businessName: 'QA', targetUserId: 'W1', targetUserName: 'QA 근로자',
          reviewYear: 2026, reviewMonth: 10,
          workDaysInMonth: s.workDays,
          normalAttendanceDays: s.onTime, lateDays: s.late, requestId: 'REQ'),
      child: const Text('open'),
    ),
  ))));
  await t.tap(find.text('open'));
  for (var i = 0; i < 40 && find.byType(MonthlyReviewDialog).evaluate().isEmpty; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await t.pump();
  }
  await t.pump(const Duration(milliseconds: 300));
}

String _statsText(WidgetTester t) {
  final dlg = find.byType(MonthlyReviewDialog);
  return t.widgetList<Text>(find.descendant(of: dlg, matching: find.byType(Text)))
      .map((w) => w.data ?? '').where((x) => x.isNotEmpty).join(' | ');
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  group('WRS-PARSE 응답 해석', () {
    test('P-1 v2 응답은 서버의 실근무·정시·지각을 그대로 쓴다', () {
      final s = AttendanceModel.parseWorkerReviewSummary(kNewServer);
      expect((s.workDays, s.onTime, s.late), (3, 2, 1));
    });

    test('P-2 구 서버 응답은 근무일만 — 정시·지각은 null(근무일 전체로 추측하지 않는다)', () {
      final s = AttendanceModel.parseWorkerReviewSummary(kOldServer);
      expect(s.workDays, 5);
      expect(s.onTime, isNull);
      expect(s.late, isNull);
    });

    test('P-3 버전만 있고 필드가 빠졌거나 모양이 틀리면 구 서버처럼 다룬다', () {
      for (final d in <Map?>[
        null,
        const {},
        const {'summaryVersion': 2, 'confirmedWorkDayCount': 4},
        const {'summaryVersion': 2, 'actualWorkDayCount': '3', 'onTimeCount': 2, 'lateCount': 1, 'confirmedWorkDayCount': 4},
        const {'summaryVersion': 1, 'actualWorkDayCount': 3, 'onTimeCount': 2, 'lateCount': 1},
      ]) {
        final s = AttendanceModel.parseWorkerReviewSummary(d);
        expect(s.onTime, isNull, reason: '$d');
        expect(s.late, isNull, reason: '$d');
      }
    });

    test('P-4 서버 v2 와 목록·알림(reviewAttendanceSummary)이 같은 기준이다 — 같은 6행 → 같은 수', () {
      final rows = [
        {'status': 'present', 'wageStatus': 'confirmed'},
        {'status': 'late', 'wageStatus': 'confirmed'},
        {'status': 'early_leave', 'wageStatus': 'transferred'},
        {'status': 'NO_SHOW', 'wageStatus': 'confirmed'},
        {'status': 'absent', 'wageStatus': 'confirmed'},
        {'status': 'present', 'wageStatus': 'pending'},
      ];
      final client = AttendanceModel.reviewAttendanceSummary(rows);
      final server = AttendanceModel.parseWorkerReviewSummary(kNewServer);
      expect((client.workDays, client.onTime, client.late),
          (server.workDays, server.onTime, server.late));
    });
  });

  group('WRS-UI 작성창 표시 — 혼합 버전', () {
    testWidgets('U-1 새 앱 + 새 서버: 근무 3 · 정시 2 · 지각 1, 결근 칸 없음', (t) async {
      await _openDialog(t, AttendanceModel.parseWorkerReviewSummary(kNewServer));
      final s = _statsText(t);
      expect(s, contains('3일'));
      expect(s, contains('2일'));
      expect(s, contains('1회'));
      expect(s, isNot(contains('결근')));
      expect(s, isNot(contains('확인 불가')));
    });

    testWidgets('U-2 새 앱 + 구 서버: 근무일만 보이고 정시·지각은 `확인 불가`, 결근 칸 없음', (t) async {
      await _openDialog(t, AttendanceModel.parseWorkerReviewSummary(kOldServer));
      final s = _statsText(t);
      expect(s, contains('5일'));
      expect('확인 불가'.allMatches(s).length, 2, reason: '정시·지각');
      expect(s, isNot(contains('결근')), reason: '모르는 값으로 결근을 계산하지 않는다');
    });

    testWidgets('U-3 조회 실패(응답 없음): 근무 0 · 정시·지각 `확인 불가`', (t) async {
      await _openDialog(t, AttendanceModel.parseWorkerReviewSummary(null));
      final s = _statsText(t);
      expect('확인 불가'.allMatches(s).length, 2);
      expect(s, isNot(contains('결근')));
    });

    testWidgets('U-4 목록·알림처럼 정시·지각을 모두 넘기면 그대로 숫자다(기존 경로 보존)', (t) async {
      await _openDialog(t, (workDays: 2, onTime: 1, late: 1));
      final s = _statsText(t);
      expect(s, isNot(contains('확인 불가')));
      expect(s, isNot(contains('결근')));
    });
  });

  group('WRS-WIRE 배선', () {
    test('W-1 근로자 상세는 서버 요약을 해석기로 읽고, 근무일을 정시로 넘기지 않는다', () {
      final s = _code('lib/widgets/dialogs/worker_detail_dialog.dart');
      expect(s, contains('AttendanceModel.parseWorkerReviewSummary(cfResult.data)'));
      expect(s, isNot(contains('normalAttendanceDays: workDaysInMonth')));
      expect(s, isNot(contains("cfResult.data['confirmedWorkDayCount']")));
      // 권한 경로는 그대로 — 요약 함수만 부른다(raw 근태 callable 로 우회하지 않는다)
      final start = s.indexOf("httpsCallable('callableGetWorkerReviewSummary'");
      expect(start, greaterThan(0));
      final around = s.substring(start - 1500, start + 1500);
      expect(around, isNot(contains('callableGetAdminAttendances')));
    });

    test('W-2 저장 — 모르는 정시·지각은 0 이 아니라 null 로 쓴다', () {
      final s = _code('lib/services/monthly_review_service.dart');
      expect(s, contains('required int? normalAttendanceDays,'));
      expect(s, contains("if (normalAttendanceDays == null) 'normalAttendanceDays': null,"));
      expect(s, contains("if (lateDays == null) 'lateDays': null,"));
    });

    test('W-3 서버 — 구 필드 뜻 유지 + v2 필드는 canonical 판정 + 권한 분기 그대로', () {
      final s = _code('functions/src/index.ts');
      final a = s.indexOf('export const callableGetWorkerReviewSummary');
      final body = s.substring(a, s.indexOf('\n);', a));
      expect(body, contains('return ws === "confirmed" || ws === "transferred";'),
          reason: '구 앱이 읽는 confirmedWorkDayCount 의 뜻은 바꾸지 않는다');
      expect(body, contains('srvIsActualFinalizedWork(st, d.get("wageStatus"))'));
      expect(body, contains('summaryVersion: 2'));
      expect(body, contains('perms?.canManageTo !== true && perms?.canManageWorkers !== true'));
      expect(body, isNot(contains('...d.data()')), reason: 'raw 근태를 돌려주지 않는다');
    });
  });
}
