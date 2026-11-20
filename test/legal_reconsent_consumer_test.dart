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
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

import 'package:crypto/crypto.dart';
import 'package:ALfit/models/core/legal_readiness.dart';
import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/screens/legal/legal_consent_reads.dart';
import 'package:ALfit/screens/legal/legal_consent_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
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
    expect(findVisibleText('이용약관이 변경되었습니다'), findsOneWidget);
    expect(findVisibleText('약관 동의 정보 확인이 필요해요'), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('T3 옛 기록은 **다른 문장**으로 말한다', (t) async {
    await _pumpCard(t,
        _r(LegalReadinessStatus.legacyConsentUnknown, legacy: ['service_terms']));
    expect(findVisibleText('약관 동의 정보 확인이 필요해요'), findsOneWidget);
    // 우리가 약관을 바꿨다는 뜻이 아니다.
    expect(findVisibleText('이용약관이 변경되었습니다'), findsNothing);
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
    expect(findVisibleTextContaining('약관'), findsNothing);
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
    expect(findVisibleTextContaining('약관'), findsNothing);
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

    expect(findVisibleText('이용약관이 변경되었습니다'), findsOneWidget);
    expect(findVisibleTextContaining('(변경됨)'), findsOneWidget);
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
            of: findVisibleTextContaining('서비스 이용약관'), matching: find.byType(Row)),
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
            of: findVisibleTextContaining('서비스 이용약관'), matching: find.byType(Row)),
        matching: find.widgetWithText(TextButton, '보기')));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ElevatedButton, '동의하고 닫기'));
    await t.pumpAndSettle();
    await t.tap(find.widgetWithText(ElevatedButton, '동의하고 계속하기'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));

    expect(findVisibleTextContaining('저장에 실패'), findsOneWidget);
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
    expect(findVisibleText('약관 상태를 확인하지 못했어요'), findsOneWidget);
    expect(findVisibleText('동의하지 않았다는 뜻이 아닙니다.'), findsOneWidget);
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

  // [DU-S005-LOCKED-LABEL-176] 공유 재동의 화면의 잠긴 동의 제목 관측 — 아래 _lckUCases(D176_PHASE 없으면 skip)
  _lckUCases();
}

// ── [DU-S005-LOCKED-LABEL-176 r1] C0-LCK-UN / C0-LCK-UB — 공유 재동의 화면의 잠긴 동의 제목 관측 ──
// 후속175 §5: T6 의 readiness(reconsentRequired · req service_terms) · _terms() 그대로, storedConsent 에
//   marketing_consent={agreed:true, version:_v} 만 넣는 **새 저장 동의 데이터 변형 1개**(허용 범위). 다른 새 데이터 0.
//   서비스 약관 = 미동의 · 변경됨 · 편집 가능, 선택 마케팅 = 이미 동의함 · 잠김. 화면 바탕은 Scaffold Colors.white 고정.
// tap · 제출 · 뷰어 진입 0. 진입 guard · 동결 · 중단은 아래 공통 절차(recovery_consent_truth_test.dart 와 같은 바이트).
const _lckLockedU = <String>['마케팅 정보 수신 동의 (선택) (동의함)'];
const _lckOtherU = <String>['서비스 이용약관 (변경됨)'];

void _lckUCases() {
  _lckCase('C0-LCK-UN', 1.0, '재동의 잠긴 동의 제목 320×640@1.0 — 저장 동의 변형 1 · tap 0', _lckUBody);
  _lckCase('C0-LCK-UB', 2.0, '재동의 잠긴 동의 제목 320×640@2.0 — 저장 동의 변형 1 · tap 0', _lckUBody);
}

Future<void> _lckUBody(WidgetTester t, String id, double s, Map<String, String> inputs) async {
  await t.runAsync(vqLoadFonts);
  final overflows = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      overflows.add(m.split('\n').first);
    } else {
      prev?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = prev);
  t.view.physicalSize = const Size(320, 640);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);

  final sent = <Map<String, dynamic>>[];
  var readinessCalls = 0;
  var termCalls = 0;
  var storedCalls = 0;
  const stored = <String, dynamic>{
    'marketing_consent': {'agreed': true, 'version': _v},
  };
  final reads = LegalConsentReads(
    readiness: () async {
      readinessCalls++;
      return _r(LegalReadinessStatus.reconsentRequired, req: ['service_terms']);
    },
    terms: () async {
      termCalls++;
      return _terms();
    },
    storedConsent: () async {
      storedCalls++;
      return Map<String, dynamic>.from(stored);
    },
    recordConsent: (r) async => sent.add(r),
  );
  final key = GlobalKey();
  await t.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: RoleTheme.workerTheme,
      builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)),
          child: child!),
      home: LegalConsentScreen(reads: reads),
    ),
  ));
  void healthy(String where) {
    expect(overflows, isEmpty, reason: '$id $where: overflow ${overflows.join(' | ')}');
    expect(t.takeException(), isNull, reason: '$id $where: 예외');
  }

  healthy('pumpWidget');
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 60));
    healthy('pump');
  }
  final frames = <String>['init:12x60'];
  expect(findVisibleText('이용약관이 변경되었습니다'), findsOneWidget, reason: 'reconsentRequired 목적지');
  final screen = find.byType(LegalConsentScreen);
  final list = find.descendant(of: screen, matching: find.byType(Scrollable)).first;
  final cta = find.widgetWithText(ElevatedButton, '동의하고 계속하기');
  final scaffold = t.widget<Scaffold>(find.descendant(of: screen, matching: find.byType(Scaffold)).first);
  expect(scaffold.backgroundColor, Colors.white, reason: 'U 바탕 = Colors.white 고정');
  final bg = scaffold.backgroundColor!;

  List<bool?> boxes() => t.widgetList<Checkbox>(find.byType(Checkbox)).map((b) => b.value).toList();
  List<bool> editable() => t.widgetList<Checkbox>(find.byType(Checkbox)).map((b) => b.onChanged != null).toList();
  final views = find.widgetWithText(TextButton, '보기');
  bool viewsOn() => t.widgetList<TextButton>(views).every((b) => b.onPressed != null);
  void state(String where) {
    // [repair-TB3] 2.0 진입 직후에는 지연 목록 항목이 캐시 밖이라 아직 만들어지지 않는다(TB2 실측 QB boxes=[]).
    //   진입에서만, 체크 2개가 다 만들어지기 전이면 위젯 상태 단언을 '정착 뒤' 로 미룬다. 호출 수 단언은 항상 본다.
    if (where != '진입' || t.widgetList<Checkbox>(find.byType(Checkbox)).length == 2) {
      expect(boxes(), <bool?>[false, true], reason: '$where 체크 [서비스 미동의, 마케팅 동의함]');
      expect(editable(), <bool>[true, false], reason: '$where 서비스 편집 가능 · 마케팅 잠김');
      expect(views, findsNWidgets(2), reason: '$where 보기 2');
      expect(viewsOn(), isTrue, reason: '$where 보기 2 활성');
      expect(t.widget<ElevatedButton>(cta).onPressed, isNull, reason: '$where CTA 비활성(필수 미선택)');
    }
    expect(sent.length, 0, reason: '$where recordConsent 0');
    expect(readinessCalls, 1, reason: '$where readiness 1');
    expect(termCalls, 1, reason: '$where terms 1');
    expect(storedCalls, 1, reason: '$where stored 1');
  }

  state('진입');
  final out = await _lckObserve(t,
      id: id, s: s, key: key, list: list, healthy: healthy, state: state, overflows: overflows,
      locked: _lckLockedU, others: _lckOtherU, fixed: <String, Finder>{'cta': cta}, bg: bg,
      cond: <String, Object?>{
        'entry': 'LegalConsentScreen(reads) reconsentRequired — U T6 readiness/terms, LOCAL',
        'data': 'U _terms() 필수1/선택1 · readiness reconsentRequired req=[service_terms] · storedConsent marketing_consent={agreed:true, version:$_v}(변형 1)',
        'fixture': 'U LegalConsentReads(호출 수) · recordConsent 기록만',
      },
      counters: () => 'recordCalls=${sent.length}|readinessCalls=$readinessCalls|termCalls=$termCalls|storedCalls=$storedCalls'
          '|checkboxes=${boxes().join(',')}|editable=${editable().join(',')}|viewsOn=${viewsOn()}'
          '|ctaEnabled=${t.widget<ElevatedButton>(cta).onPressed != null}',
      inputs: inputs,
      frames: frames);
  FlutterError.onError = prev;
  _lckFinish(id, out);
}

// ── [DU-S005-LOCKED-LABEL-176 r1] 공통 관측 절차 — 두 소비처(Q · U)가 같은 바이트를 쓴다 ──
// Q 와 U 는 다른 library 라 같은 본문을 각 파일 끝에 둔다(helper 파일 신설 0 · 공통 helper 수정 0).
// 필수 env(없으면 사례를 skip — 일반 시험 실행에 영향 0. 있으면 하나라도 틀리면 진입 실패):
//   D176_PHASE=before|after · D176_DIR=<attempt 폴더(있어야 함)> · DU1_VQ_PHASE=du176-<phase> · DU1_VQ_OUT · DU1_VQ_RUN
//   D176_INPUT_SHA=<경로=sha;…>(runner 가 고정표에서 넘긴 이번 phase 기대 입력) · after 만 D176_FROZEN · D176_FROZEN_SHA.
// 첫 실패 중단(파일 순서 무관): STOP 이 있거나, 이미 시작된(.start) 사례 중 .ok 가 없는 것이 있거나, 자기 .start 가 있으면 진입 실패.
//   실패하면 STOP 에 append 한다(기록). CLI 는 --fail-fast --concurrency=1, 최종 판정은 check176 의 reporter 전수 검산이다.
// 사례 기록(.record.json)과 완료 표식(.ok)은 모든 단언 · 캡처 뒤 마지막 문장으로만 쓴다.
const _lckOrder = <String>['C0-LCK-QN', 'C0-LCK-QB', 'C0-LCK-UN', 'C0-LCK-UB'];
const _lckInputs = <String>[
  'lib/widgets/auth/legal_consent_list.dart',
  'lib/screens/auth/registration_recovery_screen.dart',
  'lib/screens/legal/legal_consent_screen.dart',
  'lib/utils/terms_consent_plan.dart',
  'lib/theme/app_colors.dart',
  'lib/theme/role_theme.dart',
  'test/recovery_consent_truth_test.dart',
  'test/legal_reconsent_consumer_test.dart',
  'test/support/du1_vq_capture.dart',
  'test/support/visible_text.dart',
  'assets/fonts/NotoSansKR-Regular.ttf',
  'assets/fonts/NotoSansKR-Bold.ttf',
];
final Map<String, String> _lckEnv = Platform.environment;
final String _lckPhase = _lckEnv['D176_PHASE'] ?? '';
final String _lckDir = _lckEnv['D176_DIR'] ?? '';
final bool _lckSkip = _lckPhase.isEmpty;

String _lckSha(String p) => sha256.convert(File(p).readAsBytesSync()).toString();
String _lckHex(Color? c) => c == null ? 'null' : '0x${c.toARGB32().toRadixString(16).padLeft(8, '0')}';
List<double> _lckRl(Rect r) => <double>[r.left, r.top, r.right, r.bottom];

void _lckStop(String id, Object e) {
  if (_lckDir.isEmpty) return;
  try {
    File('$_lckDir/STOP').writeAsStringSync('$id ${e.toString().split('\n').first}\n', mode: FileMode.append);
  } catch (_) {}
}

/// 사례 하나를 등록한다. 진입 guard → body → (실패면 STOP append 후 rethrow).
void _lckCase(String id, double s, String desc,
    Future<void> Function(WidgetTester, String, double, Map<String, String>) body) {
  testWidgets('$id $desc', (t) async {
    try {
      final shas = _lckEnter(id);
      await body(t, id, s, shas);
      // body 는 _lckFinish 를 마지막 문장으로 호출한다. 여기서는 완료 표식 존재만 본다.
      expect(File('$_lckDir/$id.ok').existsSync(), isTrue, reason: '$id 완료 표식 없음');
    } catch (e) {
      _lckStop(id, e);
      rethrow;
    }
  }, skip: _lckSkip);
}

/// 진입 guard. 실제 입력 SHA 를 계산해 기대값과 대조하고 돌려준다. .start 를 쓴다.
Map<String, String> _lckEnter(String id) {
  expect(_lckPhase == 'before' || _lckPhase == 'after', isTrue, reason: 'D176_PHASE=$_lckPhase');
  expect(_lckDir.isNotEmpty && Directory(_lckDir).existsSync(), isTrue, reason: 'D176_DIR 없음: $_lckDir');
  expect(vqEnabled && vqPhase == 'du176-$_lckPhase', isTrue, reason: 'DU1_VQ_PHASE=$vqPhase');
  expect((_lckEnv['DU1_VQ_OUT'] ?? '').isNotEmpty && (_lckEnv['DU1_VQ_RUN'] ?? '').isNotEmpty, isTrue,
      reason: 'DU1_VQ_OUT/RUN 필수');
  expect(_lckOrder.contains(id), isTrue);
  expect(File('$_lckDir/STOP').existsSync(), isFalse, reason: '$id 앞 사례 실패(STOP) — 진행하지 않는다');
  expect(File('$_lckDir/$id.start').existsSync(), isFalse, reason: '$id 이미 시작됨 — 재실행 0');
  for (final p in _lckOrder) {
    if (File('$_lckDir/$p.start').existsSync()) {
      expect(File('$_lckDir/$p.ok').existsSync(), isTrue, reason: '$id 앞서 시작한 $p 가 완료되지 않았다 — 첫 실패 중단');
    }
  }
  // 같은 파일 안 순서(QN→QB, UN→UB)
  final k = _lckOrder.indexOf(id);
  if (k.isOdd) {
    expect(File('$_lckDir/${_lckOrder[k - 1]}.ok').existsSync(), isTrue, reason: '$id 앞 배율 사례 미완료');
  }
  final want = <String, String>{};
  for (final kv in (_lckEnv['D176_INPUT_SHA'] ?? '').split(';')) {
    final i = kv.indexOf('=');
    if (i > 0) want[kv.substring(0, i)] = kv.substring(i + 1);
  }
  expect(want.keys.toSet(), _lckInputs.toSet(), reason: 'D176_INPUT_SHA 경로 집합');
  final got = <String, String>{for (final p in _lckInputs) p: _lckSha(p)};
  for (final p in _lckInputs) {
    expect(got[p], want[p], reason: '$id 입력 SHA 불일치 $p');
  }
  if (_lckPhase == 'before') {
    expect(_lckEnv['D176_FROZEN'] ?? '', isEmpty, reason: 'before 에 frozen 을 주지 않는다');
  } else {
    final fz = _lckEnv['D176_FROZEN'] ?? '';
    expect(fz.isNotEmpty && File(fz).existsSync(), isTrue, reason: 'after 는 frozen 필수(탐색으로 바꾸지 않는다)');
    expect(_lckSha(fz), _lckEnv['D176_FROZEN_SHA'], reason: 'frozen SHA 불일치(변조)');
  }
  File('$_lckDir/$id.start').writeAsStringSync('${DateTime.now().toIso8601String()} phase=$_lckPhase');
  return got;
}

Map<String, dynamic>? _lckFrozen(String id) {
  if (_lckPhase != 'after') return null;
  final all = jsonDecode(File(_lckEnv['D176_FROZEN']!).readAsStringSync()) as Map<String, dynamic>;
  final cases = all['cases'] as Map<String, dynamic>;
  expect(cases.keys.toSet(), _lckOrder.toSet(), reason: 'frozen 사례 집합 = 4');
  final m = cases[id] as Map<String, dynamic>;
  expect(m['phase'], 'before', reason: '$id frozen 은 before 기록이어야 한다');
  expect(m['id'], id);
  for (final k in const ['drags', 'geom', 'titles', 'frames', 'counters']) {
    expect(m.containsKey(k), isTrue, reason: '$id frozen 필수 키 $k');
  }
  return m;
}

/// 마지막 문장: 기록과 완료 표식을 쓴다(덮어쓰기 거부).
void _lckFinish(String id, Map<String, Object?> rec) {
  final r = File('$_lckDir/$id.record.json');
  final ok = File('$_lckDir/$id.ok');
  expect(r.existsSync() || ok.existsSync(), isFalse, reason: '$id 기록 덮어쓰기 거부');
  r.writeAsStringSync(jsonEncode(rec));
  ok.writeAsStringSync('ok');
}

Future<Map<String, Object?>> _lckObserve(
  WidgetTester t, {
  required String id,
  required double s,
  required GlobalKey key,
  required Finder list,
  required void Function(String) healthy,
  required void Function(String) state,
  required List<String> overflows,
  required List<String> locked,
  required List<String> others,
  required Map<String, Finder> fixed,
  required Color bg,
  required Map<String, Object?> cond,
  required String Function() counters,
  required Map<String, String> inputs,
  required List<String> frames,
}) async {
  void out(String l) {
    // ignore: avoid_print
    print(l);
  }

  Finder title(String label) => findVisibleText(label);
  // 잠긴 제목 + 보조행(필수/선택 배지 · 보기) = 그 항목 내용 Column
  Finder content(String label) => find.ancestor(of: title(label), matching: find.byType(Column)).first;
  Rect union() => locked.map((l) => t.getRect(content(l))).reduce((a, b) => a.expandToInclude(b));
  bool inside(Rect a, Rect b) =>
      a.left >= b.left - 0.01 && a.top >= b.top - 0.01 && a.right <= b.right + 0.01 && a.bottom <= b.bottom + 0.01;
  ScrollPosition pos() => t.state<ScrollableState>(list).position;

  const start = Offset(160, 320);
  final drags = <double>[];
  Future<void> drag(double dy) async {
    drags.add(dy);
    expect(drags.length <= 6, isTrue, reason: '$id 목록 drag 한도 6 초과');
    expect(dy >= -160 && dy <= -40, isTrue, reason: '$id dy=$dy 범위 밖');
    expect(t.getRect(list).contains(start), isTrue, reason: '$id drag 시작점이 목록 viewport 밖');
    final p0 = pos().pixels;
    out('$id drag 목록 #${drags.length} from $start dy=$dy');
    await t.dragFrom(start, Offset(0, dy));
    healthy('drag');
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 50));
      healthy('drag pump');
    }
    frames.add('drag${drags.length}:6x50');
    expect(pos().pixels > p0, isTrue, reason: '$id drag 뒤 offset 이 움직이지 않았다');
  }

  final frozen = _lckFrozen(id);
  if (_lckPhase == 'after') {
    expect(frozen, isNotNull, reason: '$id after 는 frozen 재생만 한다');
    for (final dy in (frozen!['drags'] as List)) {
      await drag((dy as num).toDouble());
    }
  } else {
    // [repair-TB4] 2.0 진입 직후 잠긴 제목이 지연 목록 캐시 밖이면 element 0(TB3 실측 QB) — 만들어질 때까지
    //   같은 drag 규칙(dy -160 · 한도 6 · drags 기록 → after 가 frozen 으로 그대로 재생)으로 끈다.
    while (locked.any((l) => title(l).evaluate().isEmpty)) {
      await drag(-160);
    }
    for (;;) {
      final vp = t.getRect(list);
      final u = union();
      if (inside(u, vp)) break;
      expect(u.height <= vp.height + 0.01, isTrue, reason: '$id 잠긴 제목·보조행 높이가 viewport 보다 크다');
      expect(u.bottom > vp.bottom + 0.01 && u.top > vp.top, isTrue, reason: '$id 위로 벗어남 — 이 harness 는 위로 끄는 drag 만 쓴다');
      // 필요한 만큼(아래 넘침+8, 위 여유 중 작은 값)만 끈다. 시험 drag 는 touch slop 만큼 덜 움직일 수 있어 |dy| 하한 40.
      var dy = -(u.bottom - vp.bottom + 8 < u.top - vp.top ? u.bottom - vp.bottom + 8 : u.top - vp.top);
      if (dy > -40) dy = -40;
      if (dy < -160) dy = -160;
      await drag(dy);
    }
  }
  expect(inside(union(), t.getRect(list)), isTrue, reason: '$id 잠긴 제목·보조행 완전 노출 실패');
  // [repair-TB4] 제목 원문 · semantics · 비잠김 grey900 단언은 도달 뒤로 옮겼다(내용 무변경).
  for (final l in [...locked, ...others]) {
    expect(title(l), findsOneWidget, reason: '$id 제목 원문 "$l"');
    expect(t.widget<Text>(title(l)).semanticsLabel, l, reason: '$id semantics "$l"');
  }
  for (final l in others) {
    expect(t.renderObject<RenderParagraph>(find.descendant(of: title(l), matching: find.byType(RichText))).text.style?.color, AppColors.grey900,
        reason: '$id 비잠김 제목 grey900 보존 "$l"');
  }

  final pos0 = pos();
  List<double> nums() {
    final p = pos();
    return <double>[
      p.pixels, p.minScrollExtent, p.maxScrollExtent, p.viewportDimension,
      ..._lckRl(t.getRect(list)),
      for (final l in [...locked, ...others]) ...[..._lckRl(t.getRect(title(l))), ..._lckRl(t.getRect(content(l)))],
      for (final f in fixed.values) ..._lckRl(t.getRect(f)),
    ];
  }

  bool flags() {
    final p = pos();
    return identical(p, pos0) && p.hasContentDimensions && !p.outOfRange &&
        !p.isScrollingNotifier.value && !t.binding.hasScheduledFrame;
  }

  double spread(List<List<double>> w) {
    var m = 0.0;
    for (var k = 0; k < w[0].length; k++) {
      var hi = w[0][k];
      var lo = w[0][k];
      for (final v in w) {
        if (v[k] > hi) hi = v[k];
        if (v[k] < lo) lo = v[k];
      }
      if (hi - lo > m) m = hi - lo;
    }
    return m;
  }

  final samples = <List<double>>[];
  final oks = <bool>[];
  var stableAt = 0;
  for (var i = 1; i <= 20; i++) {
    await t.pump(const Duration(milliseconds: 50));
    healthy('정착 표본');
    samples.add(nums());
    oks.add(flags() && samples.last.every((v) => v.isFinite));
    if (samples.length >= 3 && oks.sublist(oks.length - 3).every((ok) => ok) &&
        spread(samples.sublist(samples.length - 3)) <= 0.1) {
      stableAt = i;
      break;
    }
  }
  frames.add('settle:${samples.length}x50');
  expect(stableAt > 0, isTrue, reason: '$id 50ms×20 안에 안정 창(3표본 ≤0.1 · inRange · idle)이 없다');
  await t.pump(const Duration(milliseconds: 50));
  frames.add('hold:1x50');
  healthy('hold');
  final held = nums();
  expect(flags() && spread([samples.last, held]) <= 0.1, isTrue, reason: '$id hold 50ms 유지 실패');
  state('정착 뒤');

  final vpr = t.getRect(list);
  final scr = Rect.fromLTWH(0, 0, 320, 640);
  for (final f in fixed.entries) {
    expect(inside(t.getRect(f.value), scr), isTrue, reason: '$id ${f.key} 화면 안');
    expect(vpr.bottom <= t.getRect(f.value).top + 0.01, isTrue, reason: '$id ${f.key} footer 겹침 0');
  }
  // 차이 mask = 잠긴 제목 Text rect + 1px ∩ 목록 viewport(후속175 §5), 제목별 1개. before 좌표를 production 편집 전에 동결한다.
  final masks = <List<double>>[for (final l in locked) _lckRl(t.getRect(title(l)).inflate(1).intersect(vpr))];
  for (final m in masks) {
    expect(m[2] > m[0] && m[3] > m[1], isTrue, reason: '$id 빈 mask');
  }
  // 제목의 색 외 필드(전후 같아야 한다)와 색(phase 별 기대는 check176 이 판정).
  final titles = <String, Object?>{};
  final colors = <String, String>{};
  for (final l in [...locked, ...others]) {
    final para = t.renderObject<RenderParagraph>(find.descendant(of: title(l), matching: find.byType(RichText)));
    final plain = para.text.toPlainText();
    final tops = para
        .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: plain.length))
        .map((b) => b.top.toStringAsFixed(1))
        .toSet();
    final st = para.text.style;
    titles[l] = <String, Object?>{
      'locked': locked.contains(l), 'lines': tops.length, 'fontSize': st?.fontSize, 'fontWeight': '${st?.fontWeight}',
      'fontFamily': st?.fontFamily, 'textScaler': '${para.textScaler}', 'plain': plain,
      'semantics': t.widget<Text>(title(l)).semanticsLabel,
    };
    colors[l] = _lckHex(st?.color);
  }
  final geom = <String, Object?>{'pos': held.sublist(0, 4), 'nums': held, 'masks': masks};
  if (frozen != null) {
    final fz = frozen['geom'] as Map<String, dynamic>;
    void same(String what, List<double> a, List<dynamic> b) {
      expect(a.length, b.length, reason: '$id $what 길이');
      for (var i = 0; i < a.length; i++) {
        expect((a[i] - (b[i] as num).toDouble()).abs() <= 0.01, isTrue, reason: '$id $what[$i] ${a[i]} vs ${b[i]}');
      }
    }

    expect(drags, (frozen['drags'] as List).map((x) => (x as num).toDouble()).toList(), reason: '$id drag 열 동결과 같음');
    same('nums', held, fz['nums'] as List);
    for (var k = 0; k < masks.length; k++) {
      same('mask$k', masks[k], (fz['masks'] as List)[k] as List);
    }
    expect(jsonEncode(titles), jsonEncode(frozen['titles']), reason: '$id 제목 색 외 필드 동결과 같음');
    expect(frames, (frozen['frames'] as List).cast<String>(), reason: '$id frame 기록 동결과 같음');
    expect(counters(), frozen['counters'], reason: '$id 상태·호출 수 동결과 같음');
  }
  final mq = MediaQuery.of(t.element(list));
  final pngPath = '${vqOutDir.path}/${id}_locked.png';
  healthy('캡처 직전');
  await vqCapture(t, key, '${id}_locked', conditions: <String, Object?>{
    ...cond,
    'phase': _lckPhase, 'attempt': _lckDir, 'clock': 'wall ${DateTime.now().toIso8601String()} · 화면 시계 의존 0(terms serverNow 고정)',
    'theme': 'RoleTheme.workerTheme · light', 'viewport': '320x640', 'dpr': 1.0, 'textScaler': s,
    'mq': 'padding=${mq.padding} viewInsets=${mq.viewInsets}', 'keyboard': '닫힘(inset 0)',
    'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK)',
    'capture': 'RepaintBoundary(MaterialApp) 320x640 전체', 'state': '잠긴 제목·보조행 완전 노출 정착 뒤',
    'bg': _lckHex(bg), 'drags': drags.join(','), 'frozen': frozen != null, 'stableAt': stableAt,
    'offset': held.sublist(0, 4).map((x) => x.toStringAsFixed(4)).join(','), 'frames': frames.join(' '),
    'masks': masks.map((m) => m.map((x) => x.toStringAsFixed(4)).join(',')).join(';'),
    'inputs': inputs.entries.map((e) => '${e.key}=${e.value}').join(';'),
    for (final l in [...locked, ...others]) 'title $l': '${jsonEncode(titles[l])} color=${colors[l]}',
  });
  expect(File(pngPath).existsSync(), isTrue, reason: '$id PNG 없음 $pngPath');
  final afterCap = nums();
  expect(flags() && spread([held, afterCap]) <= 0.1, isTrue, reason: '$id 캡처 전후 유지 실패');
  expect(overflows, isEmpty, reason: '$id overflow 0');
  expect(t.takeException(), isNull);
  String j(List<double> v) => v.map((x) => x.toStringAsFixed(4)).join(',');
  out('LCK|$id|phase=$_lckPhase|scaler=$s|frozen=${frozen != null}|drags=${drags.join(',')}|stableAt=$stableAt'
      '|bg=${_lckHex(bg)}|${counters()}|overflows=${overflows.length}|pos=${j(held.sublist(0, 4))}|viewport=${j(_lckRl(vpr))}'
      '|holdDelta=${spread([samples.last, held])}|captureDelta=${spread([held, afterCap])}');
  return <String, Object?>{
    'id': id, 'phase': _lckPhase, 'scaler': s, 'drags': drags, 'geom': geom, 'titles': titles, 'colors': colors,
    'locked': locked, 'others': others, 'bg': _lckHex(bg), 'frames': frames, 'counters': counters(), 'stableAt': stableAt,
    'png': pngPath, 'sidecar': '${vqOutDir.path}/${id}_locked.run.txt', 'inputs': inputs,
  };
}
