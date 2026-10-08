// [R7-LEGAL.1B.1] 계산된 상태가 제품 행동으로 이어지는가.
//
// 1B 는 "다시 받아야 하는가" 를 판정할 수 있게 만들었지만, 그것을 읽는
// 곳이 하나도 없었다. 상태는 소비되지 않으면 없는 것과 같다.
//
// 여기서 고정하는 것
//   · 홈 할 일이 canonical 판정만 보고 뜬다 — UI 가 버전을 비교하지 않는다
//   · 새 판과 옛 기록을 **다른 문장**으로 말한다
//   · 선택만 남았거나 조회 실패면 할 일을 만들지 않는다
//   · 동의 목적지는 하나이고, 완료 뒤 canonical 상태를 다시 묻는다
//   · 조회 실패를 "동의하지 않았다" 로 그리지 않는다
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/screens/legal/legal_consent_reads.dart';
import 'package:ALfit/screens/legal/legal_consent_screen.dart';
import 'package:ALfit/widgets/common/legal_task_card.dart';

const _v = '2026.08';

LegalTermsItem _item(String id, String title, bool required_,
        {String version = _v}) =>
    LegalTermsItem(
      id: id,
      title: title,
      content: '$title 본문입니다.\n' * 3,
      isRequired: required_,
      version: version,
      order: 1,
    );

// [R7-PAYROLL-POLICY.5B] 경계는 LegalTerms 가 아니라 서버가 판정한
//   EffectiveLegalTerms 다 — 화면이 base 를 스스로 해석하지 않는다.
EffectiveLegalTerms _terms() => EffectiveLegalTerms(
      serverNow: DateTime.utc(2026, 10, 8),
      upcoming: const [],
      items: [
      _item('service_terms', '서비스 이용약관', true),
      _item('marketing_consent', '마케팅 정보 수신 동의 (선택)', false),
      ],
    );

LegalReadiness _r(LegalReadinessStatus s,
        {List<String> req = const [], List<String> legacy = const []}) =>
    LegalReadiness(
        status: s, reconsentRequired: req, legacyUnknown: legacy);

Future<void> _pumpCard(WidgetTester t, LegalReadiness r) async {
  t.view.physicalSize = const Size(400, 900);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: LegalTaskCard(loadReadiness: () async => r),
    ),
  ));
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  // ── 홈 할 일 ───────────────────────────────────────────────────────

  testWidgets('T1 현재 상태면 할 일이 없다', (t) async {
    await _pumpCard(t, _r(LegalReadinessStatus.current));
    expect(find.byType(InkWell), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('T2 새 판이 발행되면 할 일이 뜬다 — "변경되었습니다"', (t) async {
    await _pumpCard(t,
        _r(LegalReadinessStatus.reconsentRequired, req: ['service_terms']));
    expect(find.text('이용약관이 변경되었습니다'), findsOneWidget);
    expect(find.text('약관 동의 정보 확인이 필요해요'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('T3 옛 기록은 **다른 문장**으로 말한다', (t) async {
    await _pumpCard(t,
        _r(LegalReadinessStatus.legacyConsentUnknown, legacy: ['service_terms']));
    expect(find.text('약관 동의 정보 확인이 필요해요'), findsOneWidget);
    // 우리가 약관을 바꿨다는 뜻이 아니다.
    expect(find.text('이용약관이 변경되었습니다'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('T4 선택만 미응답이면 할 일로 만들지 않는다', (t) async {
    await _pumpCard(t, _r(LegalReadinessStatus.optionalUnanswered));
    expect(find.byType(InkWell), findsNothing,
        reason: '선택을 할 일로 띄우면 사실상 강요가 된다');
    expect(t.takeException(), isNull);
  });

  testWidgets('T5 조회 실패는 할 일이 아니다 — 미동의로 그리지 않는다', (t) async {
    await _pumpCard(t, LegalReadiness.error);
    expect(find.textContaining('약관'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('T5b 조회가 throw 해도 미동의로 바뀌지 않는다', (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: LegalTaskCard(
            loadReadiness: () async => throw Exception('network')),
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    expect(find.textContaining('약관'), findsNothing);
    expect(t.takeException(), isNull);
  });

  // ── 동의 목적지 ────────────────────────────────────────────────────

  Future<void> pumpScreen(
    WidgetTester t, {
    required LegalReadiness first,
    LegalReadiness? afterSubmit,
    required List<Map<String, dynamic>> sent,
    List<int>? readinessCalls,
    bool failRecord = false,
    Map<String, dynamic> stored = const {},
  }) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    var calls = 0;
    final reads = LegalConsentReads(
      readiness: () async {
        calls++;
        readinessCalls?..clear()..add(calls);
        return calls == 1 ? first : (afterSubmit ?? first);
      },
      terms: () async => _terms(),
      storedConsent: () async => Map<String, dynamic>.from(stored),
      recordConsent: (r) async {
        sent.add(r);
        if (failRecord) throw Exception('network');
      },
    );
    await t.pumpWidget(MaterialApp(home: LegalConsentScreen(reads: reads)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
  }

  testWidgets('T6 목적지는 무엇이 달라졌는지 말하고 본문을 열 수 있다', (t) async {
    final sent = <Map<String, dynamic>>[];
    await pumpScreen(t,
        first: _r(LegalReadinessStatus.reconsentRequired,
            req: ['service_terms']),
        sent: sent);

    expect(find.text('이용약관이 변경되었습니다'), findsOneWidget);
    expect(find.textContaining('(변경됨)'), findsOneWidget);
    expect(find.widgetWithText(TextButton, '보기'), findsNWidgets(2));
    // 필수를 고르기 전에는 진행할 수 없다.
    final btn = find.widgetWithText(ElevatedButton, '동의하고 계속하기');
    expect(t.widget<ElevatedButton>(btn).onPressed, isNull);
    expect(t.takeException(), isNull);
  });

  testWidgets('T7 동의하면 보내고, 끝난 뒤 canonical 상태를 다시 묻는다', (t) async {
    final sent = <Map<String, dynamic>>[];
    final calls = <int>[];
    await pumpScreen(t,
        first: _r(LegalReadinessStatus.reconsentRequired,
            req: ['service_terms']),
        afterSubmit: _r(LegalReadinessStatus.current),
        sent: sent,
        readinessCalls: calls);

    await t.tap(find.descendant(
        of: find.ancestor(
            of: find.textContaining('서비스 이용약관'), matching: find.byType(Row)),
        matching: find.widgetWithText(TextButton, '보기')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ElevatedButton, '동의하고 닫기'));
    await t.pumpAndSettle();

    await t.tap(find.widgetWithText(ElevatedButton, '동의하고 계속하기'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    expect(sent.length, 1);
    expect(sent.single['service_terms']['agreed'], true);
    // 선택은 거부 그대로 전송된다 — 자동 true 가 아니다.
    expect(sent.single['marketing_consent']['agreed'], false);
    // 화면이 스스로 "이제 됐다" 고 판단하지 않는다 — 서버에 다시 묻는다.
    expect(calls.single, 2,
        reason: '동의 뒤 canonical 상태를 다시 묻지 않았다');
    expect(t.takeException(), isNull);
  });

  testWidgets('T8 저장이 실패하면 화면에 남는다 — 성공으로 넘기지 않는다', (t) async {
    final sent = <Map<String, dynamic>>[];
    await pumpScreen(t,
        first: _r(LegalReadinessStatus.reconsentRequired,
            req: ['service_terms']),
        sent: sent,
        failRecord: true);

    await t.tap(find.descendant(
        of: find.ancestor(
            of: find.textContaining('서비스 이용약관'), matching: find.byType(Row)),
        matching: find.widgetWithText(TextButton, '보기')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ElevatedButton, '동의하고 닫기'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ElevatedButton, '동의하고 계속하기'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    expect(find.textContaining('저장에 실패'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '동의하고 계속하기'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('T9 조회 실패 화면은 "동의하지 않았다" 고 말하지 않는다', (t) async {
    t.view.physicalSize = const Size(400, 900);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final reads = LegalConsentReads(
      readiness: () async => throw Exception('network'),
      terms: () async => _terms(),
      storedConsent: () async => <String, dynamic>{},
      recordConsent: (_) async {},
    );
    await t.pumpWidget(MaterialApp(home: LegalConsentScreen(reads: reads)));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 60));
    }
    expect(find.text('약관 상태를 확인하지 못했어요'), findsOneWidget);
    expect(find.text('동의하지 않았다는 뜻이 아닙니다.'), findsOneWidget);
    expect(find.widgetWithText(ElevatedButton, '동의하고 계속하기'), findsNothing);
    expect(t.takeException(), isNull);
  });

  // ── 모델 해석 ──────────────────────────────────────────────────────

  test('T10 모르는 응답은 error 다 — 조용히 "준비됨" 이 되지 않는다', () {
    expect(LegalReadiness.fromServer(null).status, LegalReadinessStatus.error);
    expect(LegalReadiness.fromServer({'status': 'WAT'}).status,
        LegalReadinessStatus.error);
    expect(LegalReadiness.fromServer({'status': 'CURRENT'}).status,
        LegalReadinessStatus.current);
  });

  test('T11 막는 것은 새 판 하나다', () {
    expect(_r(LegalReadinessStatus.reconsentRequired).blocksNewCommitment,
        isTrue);
    expect(_r(LegalReadinessStatus.legacyConsentUnknown).blocksNewCommitment,
        isFalse, reason: '옛 기록으로 앱을 잠그면 제품이 멈춘다');
    expect(_r(LegalReadinessStatus.optionalUnanswered).blocksNewCommitment,
        isFalse);
    expect(LegalReadiness.error.blocksNewCommitment, isFalse,
        reason: '조회 실패가 차단이 되면 서버 장애가 전원 차단이 된다');
  });

  // ── 소스 계약 ──────────────────────────────────────────────────────

  String _code(String p) => File(p)
      .readAsStringSync()
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('//'))
      .join('\n');

  test('T12 UI 가 버전 비교 정책을 복제하지 않는다', () {
    for (final p in const [
      'lib/widgets/common/legal_task_card.dart',
      'lib/screens/legal/legal_consent_screen.dart',
      'lib/models/core/legal_readiness.dart',
    ]) {
      final c = _code(p);
      expect(c.contains('.version =='), isFalse, reason: '$p 가 버전을 비교한다');
      expect(c.contains('.version !='), isFalse, reason: '$p 가 버전을 비교한다');
      expect(c.contains('revisionId =='), isFalse, reason: '$p 가 발행본을 비교한다');
    }
  });

  test('T13 홈 두 곳이 같은 할 일 카드를 쓴다 — 역할별 의미가 같다', () {
    for (final p in const [
      'lib/screens/user/user_home_screen.dart',
      'lib/screens/business_admin/business_admin_home_screen.dart',
    ]) {
      final c = _code(p);
      expect(c.contains('LegalTaskCard('), isTrue, reason: '$p 에 할 일이 없다');
    }
  });

  test('T14 AuthWrapper 가 약관으로 전체를 잠그지 않는다', () {
    final c = _code('lib/main.dart');
    expect(c.contains('LegalConsentScreen'), isFalse,
        reason: '로그인 경로 전체 차단은 기존 사용자를 가둔다');
    expect(c.contains('legalReadiness'), isFalse);
    expect(c.contains('reconsent'), isFalse);
  });

  test('T15 동의 목적지는 하나다', () {
    final dir = Directory('lib');
    final users = <String>[];
    for (final f in dir.listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      if (f.path.endsWith('legal_consent_screen.dart')) continue;
      if (_code(f.path).contains('LegalConsentScreen(')) users.add(f.path);
    }
    // 진입점은 할 일 카드 하나다. 화면마다 자기 동의 다이얼로그를 만들지
    // 않는다 — 같은 사건은 같은 자리로 가야 한다.
    expect(users.length, 1, reason: '동의 진입점이 여러 곳이다: $users');
    expect(users.single.replaceAll('\\', '/'),
        contains('widgets/common/legal_task_card.dart'));
  });
}
