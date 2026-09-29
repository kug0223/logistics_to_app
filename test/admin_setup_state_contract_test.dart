// [R7-P4.2] 신규 BUSINESS_ADMIN — 다섯 root tab 이 같은 사실을 같게 말하는가.
//
// ── 무엇이 잘못됐었나 ───────────────────────────────────────────────
//   사업장 0개인 신규 관리자에게 세 탭이 **다른 사실**을 말했다.
//
//     급여  '사업장을 선택해주세요' + [선택하기]
//           → 고를 사업장이 없어 같은 화면으로 돌아온다(dead-end)
//     근무  확정 0 / 출근 0 / 미출근 0 / 노쇼 0 + '오늘 확정된 인력이 없습니다'
//           → 운영 중인데 아무도 안 온 날처럼 읽힌다
//     공고  '등록된 공고가 없습니다 / 상단 + 버튼에서 새 공고를 등록할 수 있습니다'
//           → 그 버튼을 누르면 준비 화면에서 막힌다
//
//   셋 다 **SETUP_REQUIRED 를 SUCCESS_ZERO 로** 말한 것이다.
//   "사업장이 없어서 아직 시작되지 않음" 과 "사업장이 있고 오늘 0명" 은
//   다음 행동이 다르므로 같은 문장을 쓸 수 없다.
//
//   이 파일은 소스 계약으로 그 구별을 고정한다. 위젯 전체 렌더는 Firebase
//   의존이 커서, 여기서는 **상태 분기와 문구**가 갈라져 있다는 것을 본다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // SETUP-01. 급여 — 사업장 0 != 선택 안 함
  // ══════════════════════════════════════════════════════════════
  group('SETUP-01 급여 탭', () {
    late final String src;
    setUpAll(() => src =
        _src('lib/screens/business_admin/payroll/payroll_overview_screen.dart'));

    test('SETUP-01a 두 상태가 서로 다른 플래그다', () {
      // 예전에는 `_noData` 하나가 둘을 겸했다.
      expect(src.contains('bool _noBusiness = false;'), isTrue);
      expect(src.contains('bool _noData = false;'), isTrue,
          reason: '선택 취소 상태는 그대로 남는다');
    });

    test('SETUP-01b 사업장 0 분기가 _noBusiness 를 세운다', () {
      final i = src.indexOf('if (businesses.isEmpty) {');
      expect(i, greaterThan(-1));
      final block = src.substring(i, i + 500);
      expect(block.contains('_noBusiness = true'), isTrue);
      expect(block.contains('_noData = true'), isFalse,
          reason: '사업장 0을 "선택 안 함"으로 적지 않는다');
    });

    test('SETUP-01c picker 취소는 여전히 _noData 다', () {
      final i = src.indexOf('if (picked == null) {');
      expect(i, greaterThan(-1));
      final block = src.substring(i, i + 300);
      expect(block.contains('_noData = true'), isTrue);
      expect(block.contains('_noBusiness = true'), isFalse);
    });

    test('SETUP-01d 두 문구가 다르고, 0개일 때 dead-end CTA 가 없다', () {
      expect(src.contains('아직 급여를 관리할 사업장이 없어요'), isTrue);
      expect(src.contains('사업장을 선택해주세요'), isTrue,
          reason: '선택 취소 쪽 문구는 유지');
      // 사업장 0 상태의 action 은 '선택하기'가 아니다 — 고를 것이 없다.
      // 이 분기가 끝나는 곳까지만 본다 — 고정 길이 창은 주석이 늘면 밀린다.
      final i = src.indexOf('아직 급여를 관리할 사업장이 없어요');
      final next = src.indexOf('else if (_noData)', i);
      expect(next, greaterThan(i));
      final block = src.substring(i, next);
      expect(block.contains('선택하기'), isFalse);
      // [R7-P4.2B CTA-01] 갱신. '준비 계속하기'는 어디로 가는지 말하지 않아
      //   목적지(홈)와 라벨이 어긋났다. 규칙은 그대로다 — **준비의 owner 로
      //   보낸다**. 그 owner 를 라벨이 가리키게 바꿨을 뿐이다.
      expect(block.contains('준비 단계 보기'), isTrue);
      expect(block.contains('switchToTab'), isTrue,
          reason: '준비의 owner 인 Home 으로 보낸다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // SETUP-02. 근무 — NOT_APPLICABLE 을 0 대시보드로 그리지 않는다
  // ══════════════════════════════════════════════════════════════
  group('SETUP-02 근무 탭', () {
    late final String src;
    setUpAll(() => src = _src('lib/screens/business_admin/'
        'workforce_management/workforce_operational_view.dart'));

    test('SETUP-02a 사업장 0 사실을 상태로 들고 간다', () {
      expect(src.contains('bool _noBusiness = false;'), isTrue);
      final i = src.indexOf('여기 도달했으면 조회는 성공했고 사업장이 정말 0개다');
      expect(i, greaterThan(-1));
      // 그 분기 이후에 _noBusiness = true 가 있어야 한다.
      final block = src.substring(i, i + 500);
      expect(block.contains('_noBusiness = true'), isTrue,
          reason: '예전에는 빈 목록 + _loadError = null 로만 두어 0 대시보드가 떴다');
    });

    test('SETUP-02b 운영 화면 자체를 그리지 않는다', () {
      // 날짜 스트립·확정/출근/미출근/노쇼 칩 위에 0을 얹지 않는다.
      final i = src.indexOf('if (_noBusiness) {');
      expect(i, greaterThan(-1));
      final block = src.substring(i, i + 200);
      expect(block.contains('_buildNoBusinessState()'), isTrue);
      // 이 분기가 CustomScrollView 보다 **앞**이어야 한다.
      final scroll = src.indexOf('return CustomScrollView(');
      expect(i, lessThan(scroll),
          reason: '칩 행이 먼저 그려지면 0이 먼저 보인다');
    });

    test('SETUP-02c 문구가 "오늘 확정 0명" 과 다르다', () {
      expect(src.contains('아직 근무를 관리할 사업장이 없어요'), isTrue);
      expect(src.contains('오늘 확정된 인력이 없습니다.'), isTrue,
          reason: '사업장이 있는 날의 문구는 그대로 남는다');
    });

    test('SETUP-02d 사업장이 생기면 반드시 풀린다', () {
      expect(src.contains('if (_noBusiness) _noBusiness = false;'), isTrue,
          reason: '풀지 않으면 첫 사업장 등록 후에도 운영 화면이 안 돌아온다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // SETUP-03. 공고 — 할 수 없는 행동을 권하지 않는다
  // ══════════════════════════════════════════════════════════════
  group('SETUP-03 공고 탭', () {
    late final String view;
    late final String ctrl;
    setUpAll(() {
      view = _src('lib/screens/business_admin/'
          'workforce_management/workforce_list_view.dart');
      ctrl = _src('lib/controllers/workforce_controller.dart');
    });

    test('SETUP-03a 판정은 controller 의 기존 scope 결정을 쓴다', () {
      // 새 파생 boolean 을 화면에서 만들지 않는다(canonical 복제 금지).
      expect(ctrl.contains('bool get scopeEmpty => _scopeEmpty;'), isTrue);
      final i = ctrl.indexOf('if (businessIds != null && businessIds.isEmpty) {');
      expect(i, greaterThan(-1));
      final block = ctrl.substring(i, i + 600);
      expect(block.contains('_scopeEmpty = true'), isTrue);
      expect(block.contains('_scopeEmpty = false'), isTrue,
          reason: '사업장이 생기면 풀려야 한다');
    });

    test('SETUP-03b empty 종류가 하나 늘었다', () {
      expect(view.contains('setupRequired,'), isTrue);
      expect(view.contains('_PostingEmptyKind.setupRequired'), isTrue);
      expect(view.contains('controller.scopeEmpty'), isTrue);
    });

    test('SETUP-03c 사업장 0 에서 + 버튼을 권하지 않는다', () {
      final i = view.indexOf('_PostingEmptyKind.setupRequired => (');
      expect(i, greaterThan(-1));
      // 다음 분기가 시작되기 전까지만 본다 — 창이 넓으면 옆 항목의 문구를 읽는다.
      final next = view.indexOf('_PostingEmptyKind.root => (', i);
      expect(next, greaterThan(i));
      final block = view.substring(i, next);
      expect(block.contains('상단 + 버튼'), isFalse,
          reason: '누르면 준비 화면에서 막힌다');
      expect(block.contains('아직 공고를 등록할 수 없어요'), isTrue);
      // 기존 ROOT_EMPTY 문구는 사업장이 있을 때를 위해 남는다.
      expect(view.contains('상단 + 버튼에서 새 공고를 등록할 수 있습니다'), isTrue);
    });

    test('SETUP-03d 준비 CTA 는 Home 으로 간다', () {
      final i = view.indexOf('_PostingEmptyKind.setupRequired => TextButton(');
      expect(i, greaterThan(-1));
      final block = view.substring(i, i + 300);
      expect(block.contains('switchToTab'), isTrue);
      // [R7-P4.2B CTA-01] 갱신 — 세 탭이 같은 라벨을 쓴다.
      expect(block.contains('준비 단계 보기'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // NAV-01. root tab 의 홈 버튼 중복
  // ══════════════════════════════════════════════════════════════
  group('NAV-01 app bar action', () {
    test('NAV-01a 급여 root 에는 홈 버튼이 없다', () {
      final src = _src(
          'lib/screens/business_admin/payroll/payroll_overview_screen.dart');
      final i = src.indexOf("title: '급여 관리',");
      expect(i, greaterThan(-1));
      // 이 AppPageScaffold 의 actions 범위만 본다.
      final block = src.substring(i, i + 900);
      expect(block.contains('Icons.home_outlined'), isFalse,
          reason: 'root tab 에서 goHome 은 하단 홈 탭과 같은 동작이다');
      expect(block.contains('Icons.refresh_rounded'), isTrue,
          reason: '새로고침은 이 화면 고유 action 이라 남는다');
      // [R7-P4.2B NAV-03] 갱신. P4.2-1 때는 "벨은 그대로 둔다"가 사실이었다.
      //   이번에 다섯 root 를 나란히 놓고 보니 벨이 홈과 급여 **둘에만**
      //   있었다. 알림은 이 화면의 데이터가 아니라 전역 수신함이므로
      //   canonical owner 를 홈 하나로 정했다. 기대값을 그 사실로 바꾼다.
      expect(block.contains('NotificationBadge'), isFalse,
          reason: 'root 알림 진입점은 홈 하나다');
    });

    test('NAV-01c 홈에는 알림이 남아 있다', () {
      // 위에서 뺀 것이 "알림을 없앴다"가 되지 않도록 반대편을 같이 고정한다.
      final home = _src(
          'lib/screens/business_admin/business_admin_home_screen.dart');
      expect(home.contains('NotificationBadge('), isTrue);
      expect(home.contains('Icons.notifications_outlined'), isTrue);
    });

    test('NAV-01b push 로 열리는 하위 화면은 홈 버튼을 유지한다', () {
      final src = _src(
          'lib/screens/business_admin/payroll/payroll_overview_screen.dart');
      // 월별 급여현황은 root 가 아니다 — 돌아갈 길이 필요하다.
      final i = src.indexOf("월 급여현황',");
      expect(i, greaterThan(-1));
      final block = src.substring(i, i + 500);
      expect(block.contains('Icons.home_outlined'), isTrue);
    });
  });
}
