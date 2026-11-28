// [F293-WAGE-01 · impl_31 · 2026-11-27] 관리자 화면 — 하루 예상 금액(공용 helper `ExpectedDailyWage` 그대로).
//
//   EA-1  공고 등록 미리보기(폼 값) — '하루 예상 22,000원' 주표시 · '시급 11,000원' 보조 · 짧은 말 '예상·세전'
//   EA-2  계산 규칙이 화면에 그대로 — 무급 휴게 · 익일 종료 · 종료=시작/휴게 이상 = '예상 금액 확인 필요'(0원 0)
//   EA-3  저장된 업무(수정 화면) — 원문에 없는 시각은 임의 09–18 로 금액을 만들지 않는다 · 수정 경로도 휴게를 쓴다
//   EA-4  일급은 예전 그대로('일급' · 'N원' · 하루 예상 0)
//   EA-5  좁은 폭 · 큰 글자(320/360/411 × 1.0/1.3/2.0) — 넘침 0 · 금액 말줄임 0 · 시급 보조 보임
//   EA-6  등록/수정 업무 목록 — 시급 업무가 있으면 고지 정본 1회 · 일급만이면 0
//   EA-7  관리자 공고 카드 업무 줄 — '하루 예상 22,000원 · 시급 11,000원' + '예상·세전' · 확인 필요 · 일급 그대로
//   EA-8  소스 — 공용 helper 만 쓴다(복제식 0) · 시급 원금 · 유형 · 저장값 쓰기 0
// 플러그인 플랫폼 인터페이스(전이 의존)는 가짜 Firebase 를 끼우는 데만 쓴다 — 같은 하네스의 기존 시험과 같다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/models/work_detail_input.dart';
import 'package:ALfit/screens/business_admin/to_management/widgets/to_work_detail_card.dart';
import 'package:ALfit/screens/business_admin/to_management/widgets/to_work_details_section.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/utils/expected_daily_wage.dart';
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

/// 보이는 글자(붙임 공백 → 공백 · 낱말 묶음 표지 제거).
String _visible(String s) => s.replaceAll('⁠', '').replaceAll(' ', ' ');

String _allText(WidgetTester t) => [
      ...t.widgetList<RichText>(find.byType(RichText)).map((w) => _visible(w.text.toPlainText())),
    ].join(' | ');

WorkDetailInput _input({
  String wageType = 'hourly',
  int wage = 11000,
  String start = '09:00',
  String end = '11:00',
  int breakMinutes = 0,
}) =>
    WorkDetailInput(
      workType: '분류',
      workTypeIcon: 'local_shipping',
      workTypeColor: '#2E7D32',
      wage: wage,
      requiredCount: 2,
      startTime: start,
      endTime: end,
      wageType: wageType,
      breakMinutes: breakMinutes,
    );

Future<void> _pump(WidgetTester t, Widget child, {double width = 411, double scale = 1.0}) async {
  t.view.physicalSize = Size(width, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: child),
          ),
        ),
      ),
    ),
  ));
  await t.pump();
}

DateTime _day(int plus) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: plus));
}

TOItem _slot(WorkDetailData wd) => TOItem(
      to: TOModel(
        id: 'to1',
        businessId: 'biz1',
        businessName: '테스트 사업장',
        type: 'flex',
        title: '공고',
        creatorUID: 'uid1',
        status: 'OPEN',
        workDetails: const [],
        totalRequired: 3,
        totalConfirmed: 0,
        totalPending: 0,
        isPublished: true,
        publishMode: 'immediate',
        createdAt: _day(-3),
        statusUpdatedAt: _day(-3),
      ),
      slot: SlotModel(id: 's1', toId: 'to1', date: _day(2), status: SlotStatus.open, workDetails: [wd]),
      confirmedCount: 0,
      pendingCount: 0,
      totalRequired: 3,
    );

WorkDetailData _wd({String wageType = 'hourly', int wage = 11000, String start = '09:00', String end = '11:00', int breakMinutes = 0}) =>
    WorkDetailData(
      wdId: 'wd1',
      workType: '분류',
      startTime: start,
      endTime: end,
      requiredCount: 3,
      wage: wage,
      wageType: wageType,
      breakMinutes: breakMinutes,
      applicationDeadline: _day(1),
    );

Future<String> _row(WidgetTester t, WorkDetailData wd) async {
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  final slot = _slot(wd);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: WorkDetailRow(
        work: wd,
        confirmedCount: 0,
        pendingCount: 0,
        toItem: slot,
        firestoreService: FirestoreService(),
        onChanged: () {},
        mode: PostingPresentationMode.active,
      ),
    ),
  ));
  await t.pump();
  return _allText(t);
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

  testWidgets('EA-1 등록 미리보기(폼 값) — 하루 예상 22,000원 · 시급 11,000원 · 예상·세전', (t) async {
    await _pump(t, TOWorkDetailCard.fromInput(detail: _input()));
    expect(find.text('하루 예상 22,000원'), findsOneWidget);
    expect(find.text('시급 11,000원'), findsOneWidget);
    expect(find.text(ExpectedWageText.shortNote), findsOneWidget);
    expect(find.text('11,000원'), findsNothing, reason: '시급 원금만 주금액으로 남지 않는다');
  });

  testWidgets('EA-2 계산 규칙 그대로 — 무급 휴게 · 익일 · 확인 필요(0원 0)', (t) async {
    await _pump(t, TOWorkDetailCard.fromInput(detail: _input(start: '09:00', end: '18:00', breakMinutes: 60)));
    expect(find.text('하루 예상 88,000원'), findsOneWidget, reason: '9시간 − 휴게 1시간 = 8시간 × 11,000');
    await _pump(t, TOWorkDetailCard.fromInput(detail: _input(start: '22:00', end: '06:00', breakMinutes: 60)));
    expect(find.text('하루 예상 77,000원'), findsOneWidget, reason: '익일 종료 +1,440 · 7시간 · 야간 가산 자동 주입 0');
    await _pump(t, TOWorkDetailCard.fromInput(detail: _input(start: '09:00', end: '09:00')));
    expect(find.text(ExpectedWageText.needsCheck), findsOneWidget, reason: '종료 = 시작은 24시간으로 만들지 않는다');
    expect(find.text('시급 11,000원'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is Text && RegExp(r'(^|\s)0원').hasMatch(w.data ?? '')), findsNothing,
        reason: '계산할 수 없을 때 0원을 보이지 않는다');
    expect(find.textContaining('실근무'), findsNothing, reason: '종료 = 시작을 24시간 실근무로 말하지 않는다(금액 확인 필요와 같은 판단)');
    await _pump(t, TOWorkDetailCard.fromInput(detail: _input(start: '09:00', end: '10:00', breakMinutes: 60)));
    expect(find.text(ExpectedWageText.needsCheck), findsOneWidget, reason: '휴게 ≥ 체류');
    await _pump(t, TOWorkDetailCard.fromInput(detail: _input(start: '09:00', end: '09:20', wage: 11000)));
    expect(find.text('하루 예상 3,667원'), findsOneWidget, reason: '분 단위 · 원 단위 반올림(11,000×20/60=3,666.7)');
  });

  testWidgets('EA-3 저장된 업무 — 원문에 없는 시각은 금액을 만들지 않는다 · 수정 경로도 휴게를 쓴다', (t) async {
    final noSchedule = WorkDetailData.fromMap({'workType': '분류', 'wage': 11000, 'wageType': 'hourly', 'requiredCount': 1});
    expect(noSchedule.scheduleFromSource, isFalse);
    await _pump(t, TOWorkDetailCard.fromData(work: noSchedule));
    expect(find.text(ExpectedWageText.needsCheck), findsOneWidget, reason: '임의 09:00–18:00 으로 금액을 만들지 않는다');
    expect(find.textContaining('하루 예상'), findsNothing);

    final withBreak = _wd(start: '09:00', end: '18:00', breakMinutes: 60);
    await _pump(t, TOWorkDetailCard.fromModel(work: withBreak));
    expect(find.text('하루 예상 88,000원'), findsOneWidget, reason: '수정(fromModel) 경로가 휴게를 빠뜨리면 99,000 이 된다');
    expect(find.text('(실근무 8h)'), findsOneWidget, reason: '실근무 표시와 계산 입력이 같은 휴게(예전 서식 그대로)');
  });

  testWidgets('EA-4 일급은 예전 그대로', (t) async {
    await _pump(t, TOWorkDetailCard.fromInput(detail: _input(wageType: 'daily', wage: 120000)));
    expect(find.text('일급'), findsOneWidget);
    expect(find.text('120,000원'), findsOneWidget);
    expect(find.textContaining('하루 예상'), findsNothing);
    expect(find.text(ExpectedWageText.shortNote), findsNothing);
  });

  for (final w in const [320.0, 360.0, 411.0]) {
    for (final sc in const [1.0, 1.3, 2.0]) {
      testWidgets('EA-5 좁은 폭·큰 글자 ${w.toInt()}·$sc — 넘침 0 · 금액 말줄임 0 · 시급 보조 보임', (t) async {
        await _pump(
            t,
            TOWorkDetailCard.fromInput(
                detail: _input(start: '09:00', end: '18:00', breakMinutes: 60, wage: 11000),
                onEdit: () {},
                onDelete: () {}),
            width: w,
            scale: sc);
        expect(t.takeException(), isNull);
        final amount = find.text('하루 예상 88,000원');
        expect(amount, findsOneWidget);
        final p = t.renderObject<RenderParagraph>(find.descendant(of: amount, matching: find.byType(RichText)));
        expect(p.didExceedMaxLines, isFalse, reason: '금액이 말줄임으로 잘렸다');
        expect(find.text('시급 11,000원'), findsOneWidget);
        final viewport = t.getSize(find.byType(MaterialApp)).width;
        final box = t.renderObject<RenderBox>(find.byKey(const ValueKey('to-work-expected-wage')));
        final right = box.localToGlobal(Offset(box.size.width, 0)).dx;
        expect(right, lessThanOrEqualTo(viewport + 0.5));
      });
    }
  }

  testWidgets('EA-6 업무 목록 — 시급이 있으면 고지 정본 1회 · 일급만이면 0', (t) async {
    await _pump(
        t,
        TOWorkDetailsSection(
          workDetailInputs: [_input(), _input(start: '13:00', end: '17:00')],
          onAddWork: () {},
        ));
    expect(find.byKey(const ValueKey('to-work-expected-wage-disclosure')), findsOneWidget);
    final s = t.widget<Text>(find.byKey(const ValueKey('to-work-expected-wage-disclosure')));
    expect(s.semanticsLabel, ExpectedWageText.disclosure, reason: '고지 정본 그대로');
    await _pump(
        t,
        TOWorkDetailsSection(
          workDetailInputs: [_input(wageType: 'daily', wage: 120000)],
          onAddWork: () {},
        ));
    expect(find.byKey(const ValueKey('to-work-expected-wage-disclosure')), findsNothing);
  });

  testWidgets('EA-7 관리자 공고 카드 업무 줄 — 주금액 먼저 · 시급 보조 · 예상·세전 · 확인 필요 · 일급 그대로', (t) async {
    var text = await _row(t, _wd());
    expect(text, contains('하루 예상 22,000원 · 시급 11,000원'), reason: text);
    expect(text, contains(ExpectedWageText.shortNote));
    text = await _row(t, _wd(start: '09:00', end: '09:00'));
    expect(text, contains('시급 11,000원 · ${ExpectedWageText.needsCheck}'), reason: text);
    expect(text.contains(ExpectedWageText.shortNote), isFalse);
    text = await _row(t, _wd(wageType: 'daily', wage: 120000));
    expect(text, contains('일급 120,000원'), reason: text);
    expect(text.contains('하루 예상'), isFalse);
  });

  test('EA-8 소스 — 공용 helper 만 · 복제식 0 · 저장값 쓰기 0', () {
    for (final p in [
      'lib/screens/business_admin/to_management/widgets/to_work_detail_card.dart',
      'lib/screens/business_admin/to_management/widgets/to_work_details_section.dart',
      'lib/widgets/admin/cards/admin_work_detail.dart',
    ]) {
      final c = _code(p);
      expect(c.contains("import '../../../../utils/expected_daily_wage.dart';") || c.contains("import '../../../utils/expected_daily_wage.dart';"),
          isTrue,
          reason: p);
      expect(RegExp(r'\* *[a-zA-Z_.]*[Mm]inutes *\/ *60').hasMatch(c), isFalse, reason: '$p — 금액 식을 화면에서 다시 쓰지 않는다');
      expect(c.contains("'하루 예상"), isFalse, reason: '$p — 문구는 ExpectedWageText 에서만');
      expect(RegExp(r'\.(set|update|add)\(').hasMatch(c.replaceAll('setState(', '')), isFalse, reason: '$p — 표시만(저장 0)');
    }
    final card = _code('lib/screens/business_admin/to_management/widgets/to_work_detail_card.dart');
    expect(card.contains('ExpectedDailyWage.forWorkDetail(work)'), isTrue, reason: '저장된 업무는 원문 여부를 아는 경로');
    expect(card.contains('breakMinutes: work.breakMinutes,'), isTrue);
  });
}
