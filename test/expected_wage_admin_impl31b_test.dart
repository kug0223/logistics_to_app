// [F293-WAGE-01 · impl_31 §추가 · 2026-11-27] 관리자 초대 다이얼로그 업무 줄 · 업무 지원자 다이얼로그 머리 — 하루 예상 금액.
//
//   EB-1  초대 업무 줄 = 제안 업무 자체의 시간·조건(`forWorkDetail`) — 주금액 먼저 · 시급 보조 · 예상·세전 · 확인 필요 · 일급 그대로
//   EB-2  초대 업무 줄은 금액을 말줄임하지 않는다(소스) · 공용 helper 만
//   EB-3  업무 지원자 다이얼로그 머리 — 그 머리가 보여 주는 업무 시간으로 계산(14:00–15:00 · 12,000 → 12,000) ·
//         읽는 이름도 같은 문구 · 320/360/411 × 1.0/1.3/2.0 넘침 0
//   EB-4  머리 — 일급은 예전 '| 일급 N원' 그대로 · 확인 필요
// 플러그인 플랫폼 인터페이스(전이 의존)는 가짜 Firebase 를 끼우는 데만 쓴다 — 같은 하네스의 기존 시험과 같다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/invite_worker_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/work_applicants_reads.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/utils/expected_daily_wage.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'owner1', username: 'owner1', name: '관리자', email: 'owner1@test.local', role: UserRole.BUSINESS_ADMIN);
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

/// 보이는 글자(붙임 공백 → 공백 · 낱말 묶음 표지 제거).
String _visible(String s) => s.replaceAll('⁠', '').replaceAll(' ', ' ');

WorkDetailData _wd({String wageType = 'hourly', int wage = 12000, String start = '14:00', String end = '15:00', int breakMinutes = 0}) =>
    WorkDetailData(
      wdId: 'wd1',
      workType: 'QA 분류',
      startTime: start,
      endTime: end,
      requiredCount: 1,
      wage: wage,
      wageType: wageType,
      breakMinutes: breakMinutes,
      applicationDeadline: DateTime.now().add(const Duration(days: 2)),
    );

TOItem _item(WorkDetailData wd) {
  final k = DateTime.now().toUtc().add(const Duration(hours: 9));
  final day = DateTime.utc(k.year, k.month, k.day + 3).subtract(const Duration(hours: 9));
  return TOItem(
    to: TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '테스트 사업장',
      type: 'flex',
      title: '공고',
      creatorUID: 'owner1',
      status: 'ACTIVE',
      workDetails: const [],
      totalRequired: 1,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      statusUpdatedAt: DateTime.now().subtract(const Duration(days: 3)),
    ),
    slot: SlotModel(id: 's1', toId: 'to1', date: day, status: SlotStatus.open, workDetails: [wd]),
    confirmedCount: 0,
    pendingCount: 0,
    totalRequired: 1,
  );
}

WorkApplicantsReads _reads(WorkDetailData wd) => WorkApplicantsReads(
      applications: (to, {slotId, required purpose}) async => const [],
      usersBatch: (uids, {required businessId, purpose}) async => const {},
      weeklyAttendance: ({required businessId, required weekStart, required weekEnd}) async =>
          <String, List<AttendanceModel>>{},
      contractStatusBatch: (ids, {required businessId}) async => const ContractStatusBatch(),
      hasWorkedMap: ({required businessId, required date}) async => const {},
      idCardStatusBatch: ({required requesterId, required targetUserIds}) async => const {},
      capacity: (to, {slotId, slotWorkDetails}) async => {
            'workDetails': [wd],
            'workStats': {wd.canonicalId: {'confirmed': 0, 'pending': 0}},
            'statsFailed': false,
          },
      reassignProposals: (bizId) async => const [],
    );

Future<void> _pumpDialog(WidgetTester t, WorkDetailData wd, {double width = 411, double scale = 1.0}) async {
  t.view.physicalSize = Size(width, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  WorkApplicantsReads.debugOverride = _reads(wd);
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _AdminP(),
    child: MaterialApp(
      builder: (ctx, c) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: c!,
      ),
      home: Scaffold(body: WorkApplicantsDialog(toItem: _item(wd), work: wd, onChanged: () {})),
    ),
  ));
  for (var i = 0; i < 20; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// 머리 보조 줄(시간 · 임금) — '~' 와 시각이 들어 있는 RichText.
String _headerLine(WidgetTester t) => t
    .widgetList<RichText>(find.byType(RichText))
    .map((r) => _visible(r.text.toPlainText(includeSemanticsLabels: false)))
    .firstWhere((s) => s.contains('14:00~15:00') || s.contains('09:00~09:00') || s.contains('09:00~18:00'), orElse: () => '');

List<String> _overflows(WidgetTester t) {
  final out = <String>[];
  Object? e;
  while ((e = t.takeException()) != null) {
    if (e.toString().contains('overflowed')) out.add(e.toString().split('\n').first);
  }
  return out;
}

String _code(String p) => File(p)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
        (data) async => const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'test harness', null]));
  });
  tearDown(() => WorkApplicantsReads.debugOverride = null);

  test('EB-1 초대 업무 줄 — 제안 업무 자체 · 주금액 먼저 · 시급 보조 · 예상·세전 · 확인 필요 · 일급 그대로', () {
    expect(_visible(inviteWorkWageLine(_wd(wage: 11000, start: '09:00', end: '11:00'))),
        '하루 예상 22,000원 · 시급 11,000원 ${ExpectedWageText.shortNote}');
    expect(_visible(inviteWorkWageLine(_wd(wage: 11000, start: '09:00', end: '18:00', breakMinutes: 60))),
        '하루 예상 88,000원 · 시급 11,000원 ${ExpectedWageText.shortNote}');
    expect(_visible(inviteWorkWageLine(_wd(wage: 11000, start: '09:00', end: '09:00'))),
        '시급 11,000원 · ${ExpectedWageText.needsCheck}');
    expect(_visible(inviteWorkWageLine(_wd(wageType: 'daily', wage: 120000))), '일급 120,000원');
    final noSchedule = WorkDetailData.fromMap({'workType': '분류', 'wage': 11000, 'wageType': 'hourly', 'requiredCount': 1});
    expect(_visible(inviteWorkWageLine(noSchedule)), contains(ExpectedWageText.needsCheck),
        reason: '원문에 없는 시각으로 금액을 만들지 않는다');
    // 조각 안은 붙임 공백(줄은 구분점 옆에서만)
    expect(inviteWorkWageLine(_wd(wage: 11000, start: '09:00', end: '11:00')), contains('시급 11,000원'));
  });

  test('EB-2 초대 업무 줄 — 금액 말줄임 0 · 공용 helper 만(소스)', () {
    final c = _code('lib/screens/business_admin/dialogs/invite_worker_dialog.dart');
    final at = c.indexOf("'  ·  \${inviteWorkWageLine(wd)}'");
    expect(at, greaterThan(-1));
    // 이 Text 위젯이 끝나는 곳까지(다음 형제 목록 끝 `],`) — key 줄의 `'),` 에서 멈추지 않는다.
    final tail = c.substring(at, c.indexOf('],', at));
    expect(tail.contains('maxLines: 1'), isFalse, reason: '금액이 한 줄 말줄임으로 잘린다');
    expect(tail.contains('TextOverflow.ellipsis'), isFalse);
    expect(c.contains('ExpectedDailyWage.forWorkDetail(wd)'), isTrue, reason: '초대 = 제안 업무 자체의 시간·조건');
    final wa = _code('lib/screens/business_admin/dialogs/work_applicants_dialog.dart');
    expect(wa.contains('ExpectedDailyWage.forWorkDetail(w)'), isTrue, reason: '머리 = 머리가 보여 주는 업무 시간 원천');
    for (final s in [c, wa]) {
      expect(s.contains("'하루 예상"), isFalse, reason: '문구는 ExpectedWageText 에서만');
    }
  });

  for (final w in const [320.0, 360.0, 411.0]) {
    for (final sc in const [1.0, 1.3, 2.0]) {
      testWidgets('EB-3 업무 지원자 머리 ${w.toInt()}·$sc — 하루 예상 · 시급 · 예상·세전 · 넘침 0', (t) async {
        await _pumpDialog(t, _wd(), width: w, scale: sc);
        expect(_overflows(t), isEmpty);
        final h = _headerLine(t);
        expect(h, contains('| 하루 예상 12,000원 · 시급 12,000원'), reason: h);
        expect(h, contains(ExpectedWageText.shortNote), reason: h);
        // 읽는 이름 = semanticsLabel 이 있는 조각은 그 값으로(Text.rich 는 바깥 span 의 자식으로 싼다).
        final sem = t
            .widgetList<RichText>(find.byType(RichText))
            .map((r) => r.text.toPlainText(includeSemanticsLabels: true))
            .firstWhere((s) => s.contains('14:00~15:00'), orElse: () => '');
        expect(sem, contains('| 하루 예상 12,000원 · 시급 12,000원 ${ExpectedWageText.shortNote}'), reason: '읽는 이름도 같은 문구');
      });
    }
  }

  testWidgets('EB-4 머리 — 일급 그대로 · 계산할 수 없으면 확인 필요', (t) async {
    await _pumpDialog(t, _wd(wageType: 'daily', wage: 120000, start: '09:00', end: '18:00'));
    var h = _headerLine(t);
    expect(h, contains('| 일급 120,000원'), reason: h);
    expect(h.contains('하루 예상'), isFalse);
    await _pumpDialog(t, _wd(start: '09:00', end: '09:00'));
    h = _headerLine(t);
    expect(h, contains('| 시급 12,000원 · ${ExpectedWageText.needsCheck}'), reason: h);
    expect(h.contains(ExpectedWageText.shortNote), isFalse);
  });
}
