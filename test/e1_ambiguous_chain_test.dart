// [ALFIT-E1-AMBIGUOUS-INVITE-SEND-CANARY-PREFLIGHT.1] 응답 불명확 초대 — 연결 검증.
//
//   서버 쪽 사실은 **로컬 에뮬레이터에서 실제 번들이 만든 응답**이다
//   (`scripts/e1-ambiguous-send-runtime.js` → test/fixtures/e1_emulator_ambiguous.json):
//     · 초대 1회 커밋 뒤 저장 확인 읽기(applicantReview, uid 1명)의 행
//     · 같은 시점 카드 좌석 읽기(capacity, 슬롯)의 행
//     · 원장 — 지원서 1 · 업무/슬롯/공고 대기 1/1/1
//
//   클라이언트 쪽은 실제 위젯이다:
//     WorkApplicantsDialog → `인력 초대` → InviteMethodSheet `직접 초대`
//       → InviteWorkerDialog(전화 검색·발송) → 발송이 **서버 커밋 뒤 응답 유실**
//       (debugSendInvite 가 커밋 표시 후 deadline-exceeded 를 던진다)
//       → InviteSaveVerifier 가 fixture 행으로 확인 → 창 목록 재조회 → 닫힘 결과
//
//   증거 등급: 서버 응답 = 로컬 에뮬레이터(실제 핸들러), 응답 유실 = 클라이언트 모의.
//   DEV 호출이 아니다. 가능일 시트 경로는 업무별 창이 서비스를 주입받지 않아
//   이 연결로 몰 수 없다 — 시트 단독은 invite_ambiguous_save_test IAS-18~21.
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart'; // [DU255] keepWords 문구는 보이는 글자로 찾는다
import 'package:firebase_core/firebase_core.dart';
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_model.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/invite_worker_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_reads.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/services/invite_save_verifier.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/staffing_clock.dart';

/// [E1-FIXTURE-CLOCK] 픽스처 캡처 시각(capturedAt 2026-10-16 18:20:16 KST) 1분 뒤로 고정한다.
///   초대 유효(만료 10/17 18:20:16)·근무 시작 전(10/18 14:00)·슬롯 열림 — 시나리오가 전제한 상태다.
///   실행 날짜와 무관하게 같은 판정을 받는다. 호스트·기기 시계는 바꾸지 않는다.
final DateTime _e1Now = DateTime.utc(2026, 10, 16, 9, 21, 16);


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

class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'OWNER', username: 'owner', name: '관리자',
      email: 'owner@test.local', role: UserRole.BUSINESS_ADMIN);
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      true;
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

// ── 에뮬레이터 fixture ─────────────────────────────────────────────────────
final Map<String, dynamic> _fx = jsonDecode(
        File('test/fixtures/e1_emulator_ambiguous.json').readAsStringSync())
    as Map<String, dynamic>;
List<Map<String, dynamic>> _rows(String k1, String k2) =>
    ((_fx[k1] as Map)[k2] as List).cast<Map>().map(Map<String, dynamic>.from).toList();

/// `_cfHydrate` 와 같은 변환 — callable 은 Timestamp 를 {_seconds,_nanoseconds} 로 준다.
dynamic _hydrate(dynamic v) {
  if (v is Map) {
    final m = Map<String, dynamic>.from(v);
    if (m.containsKey('_seconds')) {
      return Timestamp((m['_seconds'] as num).toInt(),
          (m['_nanoseconds'] as num? ?? 0).toInt());
    }
    return m.map((k, x) => MapEntry(k, _hydrate(x)));
  }
  if (v is List) return v.map(_hydrate).toList();
  return v;
}

List<ApplicationModel> _parse(List<Map<String, dynamic>> rows) => rows
    .map((m) {
      final raw = Map<String, dynamic>.from(_hydrate(m) as Map);
      final id = raw.remove('id') as String? ?? '';
      return ApplicationModel.tryFromMap(raw, id);
    })
    .whereType<ApplicationModel>()
    .toList();

final DateTime _workDate = () {
  final post = _parse(_rows('saved', 'post'));
  return post.single.workDate;
}();

WorkDetailData _wd() => WorkDetailData(
      wdId: 'wd1', workType: 'QA', startTime: '14:00', endTime: '15:00',
      requiredCount: 2, wage: 12000, wageType: 'hourly',
      applicationDeadline: _e1Now.add(const Duration(days: 1)),
    );

TOItem _toItem() => TOItem(
      to: TOModel(
        id: 'TO', businessId: 'BIZ', businessName: 'biz', type: 'flex',
        title: 'E1 공고', creatorUID: 'OWNER', status: 'ACTIVE',
        workDetails: const [], totalRequired: 2, totalConfirmed: 0,
        totalPending: 0, isPublished: true, publishMode: 'immediate',
        createdAt: _e1Now.subtract(const Duration(days: 2)),
        statusUpdatedAt: _e1Now.subtract(const Duration(days: 2)),
      ),
      slot: SlotModel(
        id: 'S', toId: 'TO', date: _workDate, status: SlotStatus.open,
        workDetails: [_wd()],
        createdAt: _e1Now.subtract(const Duration(days: 2)),
      ),
      confirmedCount: 0, pendingCount: 0, totalRequired: 2,
    );

WorkDetailModel _work() => WorkDetailModel(
      wdId: 'wd1', workType: 'QA', workTypeIcon: 'box',
      workTypeColor: '#000000', workTypeBackgroundColor: '#FFFFFF',
      wage: 12000, wageType: 'hourly', requiredCount: 2,
      startTime: '14:00', endTime: '15:00',
    );

/// 서버 원장 — 발송이 커밋되면 true. 읽기는 이 값에 따라 fixture 전/후 행을 준다.
class _Server {
  bool committed = false;
  int sends = 0;
  int verifyReads = 0;
  bool verifyFails = false;

  Future<Map<String, dynamic>> capacity() async {
    final stats = {'wd1': {'confirmed': 0, 'pending': 0}};
    FirestoreService.tallyWorkDetailSeats(
        stats, committed ? _parse(_rows('saved', 'capacity')) : const [],
        slotId: 'S', seatDay: _e1Now);
    return {'workDetails': [_wd()], 'workStats': stats, 'statsFailed': false};
  }

  WorkApplicantsReads reads() => WorkApplicantsReads(
        applications: (to, {slotId, required purpose}) async =>
            committed ? _parse(_rows('saved', 'post')) : const [],
        usersBatch: (uids, {required businessId, purpose}) async => {
          for (final u in uids)
            u: UserModel(uid: u, username: u, name: '큐에이근로',
                email: '$u@test.local', role: UserRole.USER),
        },
        weeklyAttendance: ({required businessId, required weekStart,
                required weekEnd}) async =>
            <String, List<AttendanceModel>>{},
        contractStatusBatch: (ids, {required businessId}) async =>
            const ContractStatusBatch(),
        hasWorkedMap: ({required businessId, required date}) async => const {},
        idCardStatusBatch: ({required requesterId, required targetUserIds}) async =>
            const {},
        capacity: (to, {slotId, slotWorkDetails}) => capacity(),
        reassignProposals: (bizId) async => const [],
      );

  /// InviteSaveVerifier 가 보내는 읽기 — 실제 응답 행(raw) 그대로.
  Future<List<Map<String, dynamic>>> verify(Map<String, dynamic> p) async {
    verifyReads++;
    if (verifyFails) {
      throw FirebaseFunctionsException(message: 'unavailable', code: 'unavailable');
    }
    expect(p['purpose'], 'applicantReview');
    expect(p['uid'], 'W');
    return committed ? _rows('saved', 'post') : _rows('saved', 'pre');
  }

  /// 발송 — 서버는 커밋했는데 응답이 사라졌다.
  Future<void> sendCommitThenLoseResponse(Map<String, dynamic> payload) async {
    sends++;
    expect(payload['targetUid'], 'W');
    expect(payload['slotId'], 'S');
    committed = true;
    throw FirebaseFunctionsException(
        message: 'deadline-exceeded', code: 'deadline-exceeded');
  }
}

Future<void> _settle(WidgetTester t, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

String _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .join(' | ');

String? _statAfter(WidgetTester t, String label) {
  final all = t.widgetList<Text>(find.byType(Text)).map((w) => w.data).toList();
  final i = all.indexOf(label);
  return i < 0 ? null : all[i + 1];
}

void main() {
  setUp(() => StaffingClock.debugOverride = () => _e1Now);
  tearDown(() => StaffingClock.debugOverride = null);
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(() {
    WorkApplicantsReads.debugOverride = null;
    InviteSaveVerifier.debugReader = null;
    InviteWorkerDialog.debugFindUser = null;
    InviteWorkerDialog.debugSendInvite = null;
  });

  group('E1-F fixture 자체 — 에뮬레이터 원장과 읽기의 짝', () {
    test('E1-F1 원장 1건 · 대기 1/1/1', () {
      final l = (_fx['saved'] as Map)['ledger'] as Map;
      expect(l['apps'], 1);
      expect([l['wdPend'], l['slotPend'], l['toPend']], [1, 1, 1]);
    });

    test('E1-F2 확인 읽기: 저장 전 → notSaved, 저장 후 → saved (실제 응답 행)', () async {
      InviteSaveVerifier.debugReader = (_) async => _rows('saved', 'pre');
      expect(await InviteSaveVerifier.check(
          businessId: 'BIZ', toId: 'TO', targetUid: 'W', slotId: 'S'),
          InviteSaveCheck.notSaved, reason: '늦게 보이는 저장의 이전');
      InviteSaveVerifier.debugReader = (_) async => _rows('saved', 'post');
      expect(await InviteSaveVerifier.check(
          businessId: 'BIZ', toId: 'TO', targetUid: 'W', slotId: 'S'),
          InviteSaveCheck.saved);
    });

    test('E1-F3 대조: 보내지 않음 · 서버 거절 → notSaved / 읽기 실패 → unknown', () async {
      InviteSaveVerifier.debugReader = (_) async => _rows('notSent', 'post');
      expect(await InviteSaveVerifier.check(
          businessId: 'BIZ', toId: 'TO', targetUid: 'W', slotId: 'S'),
          InviteSaveCheck.notSaved);
      InviteSaveVerifier.debugReader = (_) async => _rows('rejected', 'post');
      expect(await InviteSaveVerifier.check(
          businessId: 'BIZ', toId: 'TO', targetUid: 'W', slotId: 'S'),
          InviteSaveCheck.notSaved);
      expect(isAmbiguousInviteError(FirebaseFunctionsException(
          message: 'x', code: (_fx['rejected'] as Map)['code'] as String)), isFalse,
          reason: '서버 거절 코드는 명확한 실패');
      for (final code in (_fx['readFailCodes'] as List).cast<String>()) {
        InviteSaveVerifier.debugReader =
            (_) async => throw FirebaseFunctionsException(message: code, code: code);
        expect(await InviteSaveVerifier.check(
            businessId: 'BIZ', toId: 'TO', targetUid: 'W', slotId: 'S'),
            InviteSaveCheck.unknown, reason: '$code — 모름은 미저장이 아니다');
      }
    });

    test('E1-F4 카드 좌석 읽기 행 → production 집계 대기 1 = 원장', () {
      final stats = {'wd1': {'confirmed': 0, 'pending': 0}};
      FirestoreService.tallyWorkDetailSeats(
          stats, _parse(_rows('saved', 'capacity')),
          slotId: 'S', seatDay: _e1Now);
      expect(stats['wd1'], {'confirmed': 0, 'pending': 1});
      expect(stats['wd1']!['pending'],
          ((_fx['saved'] as Map)['ledger'] as Map)['wdPend']);
    });
  });

  group('E1-W 업무별 창 → 직접 초대 → 응답 유실', () {
    late _Server server;
    WorkApplicantsDialogResult? result;
    var closed = false;

    Future<void> open(WidgetTester t) async {
      t.view.physicalSize = const Size(411, 1400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      result = null;
      closed = false;
      WorkApplicantsReads.debugOverride = server.reads();
      InviteSaveVerifier.debugReader = server.verify;
      InviteWorkerDialog.debugFindUser =
          (_) async => {'uid': 'W', 'name': '큐에이근로', 'phone': '01000000000'};
      InviteWorkerDialog.debugSendInvite = server.sendCommitThenLoseResponse;
      final item = _toItem();
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => _AdminP(),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showDialog<WorkApplicantsDialogResult>(
                      context: ctx,
                      builder: (_) => WorkApplicantsDialog(
                          toItem: item, work: _work(), onChanged: () {}),
                    );
                    closed = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.text('open'));
      await _settle(t);
    }

    Future<void> sendDirect(WidgetTester t) async {
      final cta = find.textContaining('근무 초대');
      expect(cta, findsWidgets, reason: '부족 2 — 초대 CTA');
      await t.tap(cta.first);
      await _settle(t);
      await t.tap(find.text('직접 초대'));
      await _settle(t);
      expect(find.byType(InviteWorkerDialog), findsOneWidget);
      await t.enterText(find.byType(TextField), '01000000000');
      await t.tap(find.text('검색'));
      await _settle(t);
      await t.tap(find.widgetWithText(ElevatedButton, '근무 제안'));
      await _settle(t, 40);
    }

    testWidgets('E1-W1 커밋 뒤 응답 유실 → 확인 saved → 창이 `초대 1` · 닫으면 상위 갱신 신호', (t) async {
      server = _Server();
      await open(t);
      expect(_statAfter(t, '지원: '), '0명');
      expect(_texts(t), isNot(contains('초대: ')));

      await sendDirect(t);
      expect(server.sends, 1, reason: '재발송 없이 확인만');
      expect(server.committed, isTrue);
      expect(find.byType(InviteWorkerDialog), findsNothing, reason: 'sent 로 닫혔다');
      expect(_statAfter(t, '초대: '), '1명', reason: '창 목록이 저장 사실을 다시 읽었다');
      expect(find.text('큐에이근로'), findsOneWidget);

      await t.tap(find.text('닫기').last);
      await _settle(t);
      expect(closed, isTrue);
      expect(result?.hasChanges, isTrue, reason: '상위 카드가 다시 읽는 신호');
      expect(result?.homeRelevant, isFalse, reason: '초대는 Home 숫자를 바꾸지 않는다(기록된 결정)');
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('E1-W2 커밋 뒤 응답 유실 + 확인 읽기 실패 → 재발송 막힘(`다시 확인`) · 요청 1', (t) async {
      server = _Server()..verifyFails = true;
      await open(t);
      await sendDirect(t);
      expect(server.sends, 1);
      expect(find.byType(InviteWorkerDialog), findsOneWidget, reason: '모르면 창을 닫지 않는다');
      expect(find.ancestor(of: findVisibleText('다시 확인'), matching: find.byType(ElevatedButton)), findsOneWidget);
      expect(find.widgetWithText(ElevatedButton, '근무 제안'), findsNothing,
          reason: '모르는 상태에서 재발송 버튼을 열지 않는다');
      // 다시 확인 → 여전히 실패 → 발송 0 추가
      await t.tap(find.widgetWithText(ElevatedButton, '다시 확인'));
      await _settle(t);
      expect(server.sends, 1);
      // 창을 정상적으로 닫아 전역 중복 실행 가드(ActionGuard)를 풀어 둔다.
      await t.tap(find.widgetWithText(OutlinedButton, '닫기'));
      await _settle(t, 40);
      await t.tap(find.text('닫기').last);
      await _settle(t);
      await t.pump(const Duration(seconds: 5));
    });

    testWidgets('E1-W3 확인 읽기 실패한 채 닫음 → unconfirmed → 창 재조회가 그 초대를 읽으면 상위 갱신 신호',
        (t) async {
      server = _Server()..verifyFails = true;
      await open(t);
      await sendDirect(t);
      await t.tap(find.widgetWithText(OutlinedButton, '닫기'));
      await _settle(t, 40);
      expect(find.byType(InviteWorkerDialog), findsNothing);
      // 창은 목록을 다시 읽는다 — 목록 읽기는 성공해 초대가 보인다.
      expect(_statAfter(t, '초대: '), '1명');
      await t.tap(find.text('닫기').last);
      await _settle(t);
      // [E1-W3 수정] 예전에는 여기서 false 였다(창은 `초대 1`, 카드는 옛 수치).
      //   이제 성공한 재조회가 그 대상의 이 업무 INVITED 를 읽었으므로 전파한다.
      //   대조군(재조회 실패·대상 없음·다른 사람)은 e1_w3_parent_refresh_test.
      expect(result?.hasChanges, isTrue);
      expect(result?.homeRelevant, isFalse);
      expect(server.sends, 1);
      await t.pump(const Duration(seconds: 5));
    });
  });
}
