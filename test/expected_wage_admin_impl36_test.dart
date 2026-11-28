// [F294-WAGE-01 · impl_36 · 2026-11-27] 관리자 4곳 소비처 — 알려진 비시급 누락 단가 · 유형 모름(helper 569f7dd5 그대로).
//
//   W1  초대 업무 줄 — 일급/월급 단가 누락 = '일급 급여 확인 필요'(0원 0) · 정상 일급 그대로 · 유형 모름 = '급여 확인 필요'
//   W2  관리자 공고 카드 업무 줄(_wageLine) — 같은 규칙 · 320·2.0/360·1.3/411·1.0 넘침 0
//   W3  업무 지원자 머리 — 보이는 글 = 읽는 이름 · 320·1.3/320·2.0/392·2.0 넘침 0 · 정상 일급 회귀 0
//   W4  공고 업무 카드 유형 모름 — 라벨 '급여' · '예상·세전' 0 · 시급 보조 0 · 320/360/411 × 1.0/1.3/2.0 넘침·말줄임 0
//   W5  공고 업무 카드 — 폼의 모르는 유형 값 · 일급 0 단가 · 정상 일급 · 시급 회귀
//   W6  소스 — rawWage 만 · 0원 fallback 0 · 업무 묶음 줄(_buildWorkSection) 포함 · 유형 모름 분기 순서
//   하네스(가짜 Firebase · 관리자 Provider · WorkApplicantsReads)는 expected_wage_admin_impl31b_test 와 같다.
// 플러그인 플랫폼 인터페이스(전이 의존)는 가짜 Firebase 를 끼우는 데만 쓴다 — 같은 하네스의 기존 시험과 같다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
import 'package:ALfit/screens/business_admin/to_management/widgets/to_work_detail_card.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/utils/posting_presentation_mode.dart';
import 'package:ALfit/widgets/admin/cards/admin_work_detail.dart';

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

WorkDetailData _unknownType({int wage = 11000}) => WorkDetailData.fromMap({
      'wdId': 'wd1',
      'workType': '분류',
      'startTime': '09:00',
      'endTime': '18:00',
      'breakMinutes': 60,
      'wage': wage,
      'requiredCount': 1,
      // wageType 없음 — 모델 기본 'hourly' 가 채워지지만 원문 유형은 모른다(wageTypeFromSource=false).
    });

Future<String> _row(WidgetTester t, WorkDetailData wd, {double width = 411, double scale = 1.0}) async {
  t.view.physicalSize = Size(width, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (ctx, c) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
      child: c!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: WorkDetailRow(
          work: wd,
          confirmedCount: 0,
          pendingCount: 0,
          toItem: _item(wd),
          firestoreService: FirestoreService(),
          onChanged: () {},
          mode: PostingPresentationMode.active,
        ),
      ),
    ),
  ));
  await t.pump();
  return t
      .widgetList<RichText>(find.byType(RichText))
      .map((w) => _visible(w.text.toPlainText(includeSemanticsLabels: false)))
      .join(' | ');
}

Future<void> _card(WidgetTester t, Widget card, {double width = 411, double scale = 1.0}) async {
  t.view.physicalSize = Size(width, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (ctx, c) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
      child: c!,
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: card),
      ),
    ),
  ));
  await t.pump();
}

/// 0원 표기(단독 · 범위 끝이 아닌 것) — '10,000원' 의 꼬리는 잡지 않는다.
final _zeroWon = RegExp(r'(^|[^0-9,])0원');

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

  test('W1 초대 업무 줄 — 알려진 비시급 단가 누락은 0원 대신 확인 필요 · 정상 일급·유형 모름은 그대로', () {
    expect(_visible(inviteWorkWageLine(_wd(wageType: 'daily', wage: 0))), '일급 ${ExpectedWageText.wageUnknown}');
    expect(_visible(inviteWorkWageLine(_wd(wageType: 'monthly', wage: -1))), contains(ExpectedWageText.wageUnknown));
    expect(_zeroWon.hasMatch(_visible(inviteWorkWageLine(_wd(wageType: 'daily', wage: 0)))), isFalse);
    expect(_visible(inviteWorkWageLine(_wd(wageType: 'daily', wage: 120000))), '일급 120,000원', reason: '정상 값 예전 그대로');
    final u = _visible(inviteWorkWageLine(_unknownType()));
    expect(u, ExpectedWageText.wageUnknown, reason: '유형 모름 = helper 로 해소(시급이라 부르지 않는다)');
  });

  testWidgets('W2 관리자 공고 카드 업무 줄 — 일급 0 단가 = 확인 필요 · 정상 일급 그대로', (t) async {
    var text = await _row(t, _wd(wageType: 'daily', wage: 0));
    expect(text, contains('일급 ${ExpectedWageText.wageUnknown}'), reason: text);
    expect(_zeroWon.hasMatch(text), isFalse, reason: text);
    text = await _row(t, _wd(wageType: 'daily', wage: 120000));
    expect(text, contains('일급 120,000원'), reason: text);
  });

  for (final (w, sc) in const [(320.0, 2.0), (360.0, 1.3), (411.0, 1.0)]) {
    testWidgets('W2b 공고 카드 업무 줄 ${w.toInt()}·$sc — 일급 0 단가 넘침 0', (t) async {
      final text = await _row(t, _wd(wageType: 'daily', wage: 0), width: w, scale: sc);
      expect(_overflows(t), isEmpty);
      expect(text, contains(ExpectedWageText.wageUnknown));
    });
  }

  for (final (w, sc) in const [(320.0, 1.3), (320.0, 2.0), (392.0, 2.0)]) {
    testWidgets('W3 업무 지원자 머리 ${w.toInt()}·$sc — 일급 0 단가 = 확인 필요(보이는 글 = 읽는 이름) · 넘침 0', (t) async {
      await _pumpDialog(t, _wd(wageType: 'daily', wage: 0, start: '09:00', end: '18:00'), width: w, scale: sc);
      expect(_overflows(t), isEmpty);
      final h = _headerLine(t);
      expect(h, contains('| 일급 ${ExpectedWageText.wageUnknown}'), reason: h);
      expect(_zeroWon.hasMatch(h), isFalse, reason: h);
      final sem = t
          .widgetList<RichText>(find.byType(RichText))
          .map((r) => r.text.toPlainText(includeSemanticsLabels: true))
          .firstWhere((s) => s.contains('09:00~18:00'), orElse: () => '');
      expect(sem, contains('| 일급 ${ExpectedWageText.wageUnknown}'), reason: sem);
    });
  }

  testWidgets('W3b 머리 — 정상 일급 그대로(회귀)', (t) async {
    await _pumpDialog(t, _wd(wageType: 'daily', wage: 120000, start: '09:00', end: '18:00'));
    expect(_headerLine(t), contains('| 일급 120,000원'));
  });

  for (final w in const [320.0, 360.0, 411.0]) {
    for (final sc in const [1.0, 1.3, 2.0]) {
      testWidgets('W4 공고 업무 카드 유형 모름 ${w.toInt()}·$sc — 라벨 급여 · 예상·세전 0 · 보조 0 · 넘침·말줄임 0', (t) async {
        await _card(t, TOWorkDetailCard.fromData(work: _unknownType(), onEdit: () {}, onDelete: () {}), width: w, scale: sc);
        expect(t.takeException(), isNull);
        final badge = find.byKey(const ValueKey('to-work-wage-unknown'));
        expect(badge, findsOneWidget);
        expect(find.descendant(of: badge, matching: find.text('급여')), findsOneWidget);
        final v = find.descendant(of: badge, matching: find.text(ExpectedWageText.wageUnknown));
        expect(v, findsOneWidget);
        final p = t.renderObject<RenderParagraph>(find.descendant(of: v, matching: find.byType(RichText)));
        expect(p.didExceedMaxLines, isFalse, reason: '확인 필요 문구가 말줄임으로 잘렸다');
        expect(find.descendant(of: badge, matching: find.text(ExpectedWageText.shortNote)), findsNothing);
        expect(find.descendant(of: badge, matching: find.textContaining('시급')), findsNothing);
        expect(find.byKey(const ValueKey('to-work-expected-wage')), findsNothing);
        final viewport = t.getSize(find.byType(MaterialApp)).width;
        final box = t.renderObject<RenderBox>(badge);
        expect(box.localToGlobal(Offset(box.size.width, 0)).dx, lessThanOrEqualTo(viewport + 0.5));
      });
    }
  }

  testWidgets('W5 공고 업무 카드 — 폼의 모르는 유형 값도 유형 모름 · 일급 0 단가 = 확인 필요 · 정상 일급 그대로', (t) async {
    await _card(t, TOWorkDetailCard(
        workType: '분류', workTypeIcon: 'local_shipping', workTypeColor: '#2E7D32',
        wage: 11000, requiredCount: 1, startTime: '09:00', endTime: '18:00', wageType: 'weekly'));
    expect(find.byKey(const ValueKey('to-work-wage-unknown')), findsOneWidget);
    await _card(t, TOWorkDetailCard.fromData(work: _wd(wageType: 'daily', wage: 0)));
    expect(find.text('일급'), findsOneWidget);
    expect(find.text(ExpectedWageText.wageUnknown), findsOneWidget);
    expect(find.text('0원'), findsNothing);
    expect(find.byKey(const ValueKey('to-work-wage-unknown')), findsNothing, reason: '유형은 안다(일급)');
    await _card(t, TOWorkDetailCard.fromData(work: _wd(wageType: 'daily', wage: 120000)));
    expect(find.text('일급'), findsOneWidget);
    expect(find.text('120,000원'), findsOneWidget);
    await _card(t, TOWorkDetailCard.fromData(work: _wd(wage: 11000, start: '09:00', end: '11:00')));
    expect(find.byKey(const ValueKey('to-work-expected-wage')), findsOneWidget, reason: '시급 경로 회귀 0');
  });

  test('W6 소스 — 관리자 4곳 원시 단가는 rawWage 로만 · 0원 fallback 0 · 유형 모름 분기가 일급 분기보다 먼저', () {
    final inv = _code('lib/screens/business_admin/dialogs/invite_worker_dialog.dart');
    final wa = _code('lib/screens/business_admin/dialogs/work_applicants_dialog.dart');
    final ad = _code('lib/widgets/admin/cards/admin_work_detail.dart');
    final card = _code('lib/screens/business_admin/to_management/widgets/to_work_detail_card.dart');
    expect(inv.contains('ExpectedWageText.rawWage(wd.wage)'), isTrue);
    expect(inv.contains('FormatHelper.formatWage(wd.wage)'), isFalse);
    expect(wa.contains('formattedWage'), isFalse, reason: '머리·읽는 이름·업무 묶음 줄 모두');
    expect('ExpectedWageText.rawWage('.allMatches(wa).length, 3);
    expect(ad.contains('ExpectedWageText.rawWage(widget.work.wage)'), isTrue);
    expect(ad.contains('FormatHelper.formatWage(widget.work.wage)'), isFalse);
    expect(card.contains(r"'$_formattedWage원'"), isFalse);
    final unk = card.indexOf('if (e.typeUnknown) {');
    final daily = card.indexOf('final daily = ExpectedWageText.daily(e);');
    expect(unk > 0 && daily > unk, isTrue);
    expect(card.contains('value: ExpectedWageText.rawWage(wage),'), isTrue);
    final helper = File('lib/utils/expected_daily_wage.dart').readAsStringSync();
    expect(helper.isNotEmpty, isTrue);
  });
}
