// [R7-P4.2B] 다섯 root 가 한 제품처럼 보이는가 — 소스 계약.
//
//   렌더로 잴 수 있는 것(넘침·잘림·대비)은 admin_root_visual_render_test 가
//   본다. 여기서는 **규칙**을 본다: 탭 이름과 목적지 이름이 같은가,
//   전역 action 의 owner 가 하나인가, 첫 화면을 막는 조회가 중복되지 않는가.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

const _shell = 'lib/screens/business_admin/business_admin_shell.dart';
const _home = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _jobs = 'lib/screens/business_admin/jobs_root_screen.dart';
const _workforce =
    'lib/screens/business_admin/workforce_management/workforce_root_screen.dart';
const _payroll =
    'lib/screens/business_admin/payroll/payroll_overview_screen.dart';
const _settings = 'lib/screens/common/settings_screen.dart';
const _opView = 'lib/screens/business_admin/'
    'workforce_management/workforce_operational_view.dart';

void main() {
  // ══════════════════════════════════════════════════════════════
  // RS-01. 탭 라벨 == 도착한 화면의 이름
  // ══════════════════════════════════════════════════════════════
  group('RS-01 탭 이름과 목적지 이름', () {
    test('RS-01a 하단 5탭 라벨은 이 다섯 개다', () {
      final s = _src(_shell);
      for (final label in const ['홈', '공고', '근무', '급여', '관리']) {
        expect(s.contains("label: '$label'"), isTrue, reason: label);
      }
    });

    test('RS-01b 근무 탭을 열면 화면 제목도 근무다', () {
      // 예전에는 탭이 '근무'인데 헤더가 '인력'이었다. 다섯 중 이 하나만
      // 어긋나 있었고, 그러면 관리자는 자기 위치를 화면으로 확인할 수 없다.
      final s = _src(_workforce);
      expect(s.contains("                '근무',"), isTrue);
      expect(s.contains("Text(\n                '인력',"), isFalse,
          reason: '헤더 제목으로 돌아가면 안 된다');
    });

    test('RS-01c 나머지 넷도 라벨과 제목이 이어진다', () {
      expect(_src(_jobs).contains("'공고',"), isTrue);
      expect(_src(_payroll).contains("title: '급여 관리',"), isTrue);
      // 관리 탭 제목은 권한에 따라 '관리'/'설정' 으로 갈린다 — 둘 다 남긴다.
      expect(_src(_settings).contains("? (showAdminSection ? '관리' : '설정')"),
          isTrue);
      // 홈은 제목 대신 제품 이름(로고 + 워드마크)을 쓴다 — 의도된 예외다.
      expect(_src(_home).contains("Text('ALfit',"), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // RS-02. 전역 action 은 owner 가 하나다
  // ══════════════════════════════════════════════════════════════
  group('RS-02 root app bar action', () {
    test('RS-02a 알림 진입점은 홈 하나다', () {
      // 알림은 특정 탭의 데이터가 아니라 전역 수신함이다. 다섯 중 둘에만
      // 있으면 규칙을 배울 수 없고, 다섯 전부에 붙이면 각 탭 고유 action 이
      // 묻힌다. owner 를 홈으로 둔다.
      expect(_src(_home).contains('NotificationBadge('), isTrue);

      // 급여 root 의 actions 범위 안에는 없어야 한다.
      final pay = _src(_payroll);
      final i = pay.indexOf("title: '급여 관리',");
      expect(i, greaterThan(-1));
      final block = pay.substring(i, i + 700);
      expect(block.contains('NotificationBadge'), isFalse);

      // 공고·근무·관리(admin shell)에는 원래 없었다 — 새로 붙이지 않았다.
      expect(_src(_jobs).contains('NotificationBadge'), isFalse);
      expect(_src(_workforce).contains('NotificationBadge'), isFalse);
      expect(_src(_settings).contains('actions: useAdminShell ? const [] :'),
          isTrue);
    });

    test('RS-02b 탭 고유 action 은 남는다', () {
      // 일관성을 이유로 기능까지 지우지 않는다. 각 action 이 그 화면에서만
      // 의미가 있는지로 판단한다.
      final pay = _src(_payroll);
      final i = pay.indexOf("title: '급여 관리',");
      expect(pay.substring(i, i + 700).contains('Icons.refresh_rounded'),
          isTrue, reason: '연도 재조회는 이 화면만의 동작');

      final jobs = _src(_jobs);
      expect(jobs.contains('Icons.filter_list_rounded'), isTrue);
      expect(jobs.contains('Icons.add_rounded'), isTrue);
    });

    test('RS-02c push 로 열린 하위 화면은 root 규칙을 따르지 않는다', () {
      // 하단 탭이 닿지 않는 화면에는 돌아갈 길과 알림이 그대로 필요하다.
      final pay = _src(_payroll);
      final i = pay.indexOf("월 급여현황',");
      expect(i, greaterThan(-1));
      final block = pay.substring(i, i + 500);
      expect(block.contains('Icons.home_outlined'), isTrue);
      expect(block.contains('NotificationBadge'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // RS-03. 관리 탭 identity — 만질 수 없는 것이 가장 강하지 않다
  // ══════════════════════════════════════════════════════════════
  group('RS-03 관리 identity 블록', () {
    late final String s;
    setUpAll(() => s = _src(_settings));

    test('RS-03a 여전히 탭 대상이 아니다', () {
      // 강도를 내린 이유가 "누를 수 있게 만들 것"이 아니다. 이번 Phase 는
      // 새 진입점을 만들지 않는다 — 그 사실을 같이 고정한다.
      final i = s.indexOf('Widget _buildHeaderProfile(');
      final end = s.indexOf('Widget _miniStat(', i);
      expect(end, greaterThan(i));
      final block = s.substring(i, end);
      expect(block.contains('InkWell('), isFalse);
      expect(block.contains('GestureDetector('), isFalse);
      expect(block.contains('onTap:'), isFalse);
    });

    test('RS-03b 관리자만 tonal, 지원자는 기존 면 유지', () {
      expect(s.contains('theme.primaryColor.withValues(alpha: 0.06)'), isTrue);
      expect(s.contains('tonal: useAdminShell'), isTrue);
    });

    test('RS-03c 내용은 하나도 줄이지 않았다', () {
      expect(s.contains("user?.name ?? '사용자'"), isTrue);
      expect(s.contains("'@\${user?.username ?? 'username'}'"), isTrue);
      expect(s.contains('CommonWidgets.getRoleName('), isTrue);
      // 지원자 통계·배지도 그대로다.
      expect(s.contains("_miniStat(context, '근무',"), isTrue);
      expect(s.contains('BadgeDisplayWidget('), isTrue);
    });

    test('RS-03d 빈 자리에 새 KPI·Quick Menu 를 넣지 않았다', () {
      final i = s.indexOf('Widget _buildHeaderProfile(');
      final end = s.indexOf('Widget _miniStat(', i);
      final block = s.substring(i, end);
      for (final banned in const ['Quick', 'KPI', 'LinearGradient']) {
        expect(block.contains(banned), isFalse, reason: banned);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // RS-04. 첫 화면을 막는 조회가 중복되지 않는다
  // ══════════════════════════════════════════════════════════════
  group('RS-04 근무 탭 cold path', () {
    late final String s;
    setUpAll(() => s = _src(_opView));

    test('RS-04a 두 로더가 같은 프레임에서 깨어난다 (전제)', () {
      final i = s.indexOf('void initState() {');
      final block = s.substring(i, i + 400);
      expect(block.contains('_loadDayData(_selectedDay);'), isTrue);
      expect(block.contains('_loadMarkerRange(_selectedDay);'), isTrue);
    });

    test('RS-04b 둘 다 사업장 조회로 들어간다 (전제)', () {
      expect('_ensureBusinesses()'.allMatches(s).length, greaterThanOrEqualTo(2));
    });

    test('RS-04c 같은 scope 의 진행 중 조회에 올라탄다', () {
      // 캐시는 await 가 끝난 뒤에 채워지므로, 캐시만으로는 같은 프레임의
      // 두 번째 호출을 막지 못한다 — 그래서 in-flight 를 따로 들고 있다.
      expect(s.contains('Future<List<BusinessModel>>? _inFlightBusinesses;'),
          isTrue);
      final i = s.indexOf('Future<List<BusinessModel>> _ensureBusinesses()');
      final end = s.indexOf('Future<List<BusinessModel>> _fetchBusinesses(', i);
      expect(end, greaterThan(i));
      final block = s.substring(i, end);
      expect(block.contains('if (inFlight != null) return inFlight;'), isTrue);
      // 캐시 경로가 먼저다 — in-flight 가 캐시를 대체하지 않는다.
      expect(block.indexOf('if (cached != null && !_businessesStale)'),
          lessThan(block.indexOf('final inFlight =')));
    });

    test('RS-04d 늦게 끝난 옛 요청이 새 요청을 지우지 않는다', () {
      expect(s.contains('if (identical(_inFlightBusinesses, future))'), isTrue);
    });

    test('RS-04e 사업장 0 을 알았으면 운영 조회로 내려가지 않는다', () {
      // setup state 가 확정된 시점에서 무거운 조회를 건너뛴다.
      for (final loader in const ['_loadMarkerRange', '_loadDayData']) {
        final i = s.indexOf('Future<void> $loader(');
        expect(i, greaterThan(-1), reason: loader);
        final block = s.substring(i, i + 2200);
        final empty = block.indexOf('if (businesses.isEmpty) {');
        final heavy = block.indexOf('await Future.wait(');
        expect(empty, greaterThan(-1), reason: loader);
        expect(heavy, greaterThan(empty),
            reason: '$loader: 빈 사업장 분기가 병렬 조회보다 앞서야 한다');
        expect(block.substring(empty, heavy).contains('return;'), isTrue,
            reason: '$loader: 빈 분기가 실제로 빠져나가야 한다');
      }
    });
  });
}
