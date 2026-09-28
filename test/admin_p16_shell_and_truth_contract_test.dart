// [R7-P1-6] 관리자 계약·관리·통계 — shell 과 진실 표시 계약
//
//   실제 위젯 증거는 admin_shell_flat_render_test 가 들고 있다.
//   이 파일은 **소스 배선**만 본다(둘을 섞지 않는다).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  // 줄바꿈에 기대지 않는다 — 체크아웃 방식이 대조를 바꾸면 안 된다.
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

const _settings = 'lib/screens/common/settings_screen.dart';
const _contract = 'lib/screens/business_admin/admin_contract_management_screen.dart';
const _contractSeam = 'lib/screens/business_admin/admin_contract_reads.dart';
const _stats = 'lib/screens/business_admin/admin_stats_screen.dart';
const _statsSvc = 'lib/services/admin_stats_service.dart';
const _monthDetail = 'lib/screens/business_admin/admin_month_detail_screen.dart';

/// P16-A 에서 **전환한** super_admin 화면(순수 shell 교체가 가능했던 묶음).
const _converted = <String>[
  'system_settings_screen',
  'business_approval_settings_screen',
  'insurance_rate_settings_screen',
  'minimum_wage_settings_screen',
  'legal_terms_management_screen',
  'badge_settings_screen',
];

/// P16-A 에서 **남긴** super_admin 화면과 그 이유.
///   headerTab: 헤더 TabBar 라벨이 흰색이라 flat app bar 에서 보이지 않는다.
///   wideTable: 가로 스크롤 표/도구라 레이아웃 위험을 따로 봐야 한다.
const _deferred = <String, String>{
  'help_faq_management_screen': 'headerTab',
  'review_tags_settings_screen': 'headerTab',
  'to_limit_settings_screen': 'headerTab',
  'all_businesses_screen': 'wideTable',
  'all_users_screen': 'wideTable',
};

/// 주석 줄을 지운 본문 — 앵커는 주석이 아니라 **코드**여야 한다.
String _codeOf(String s) => s
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _superSrc(String name) =>
    _codeOf(_src('lib/screens/super_admin/$name.dart'));

void main() {
  // ══════════════════════════════════════════════════════════
  group('P16-M 관리 탭 shell — 역할 경계를 지킨다', () {
    late String s;
    setUpAll(() => s = _src(_settings));

    test('M-1 관리자 역할만 flat admin shell 을 쓴다', () {
      expect(s.contains('final useAdminShell ='), isTrue);
      expect(s.contains('showAdminSection || user?.role == UserRole.SUPER_ADMIN'),
          isTrue);
      expect(s.contains('if (!useAdminShell) {'), isTrue);
      // 두 shell 이 모두 남아 있다 — 지원자 쪽은 P2 소유다.
      expect(s.contains('return GradientScaffold('), isTrue);
      expect(s.contains('return AppPageScaffold('), isTrue);
    });

    test('M-2 프로필 블록을 지우지 않고 대비를 유지한 카드로 내렸다', () {
      expect(s.contains('child: _buildHeaderProfile(context, userProvider),'), isTrue);
      expect(s.contains('color: theme.primaryColor,'), isTrue);
      expect(s.contains('BorderRadius.circular(16)'), isTrue,
          reason: 'D0 관리자 카드 radius');
    });

    test('M-3 탈퇴 점검 블록의 하드코딩 색을 없앴다', () {
      for (final hex in const [
        '0xFFB45309', '0xFFFFFBEB', '0xFFF0FDF4',
        '0xFFBBF7D0', '0xFF16A34A', '0xFF166534',
      ]) {
        expect(s.contains(hex), isFalse, reason: hex);
      }
      expect(s.contains('color: AppColors.warningDark'), isTrue);
      expect(s.contains('bgColor: AppColors.warningBg'), isTrue);
      expect(s.contains('color: AppColors.successBg'), isTrue);
      expect(s.contains('AppColors.successLight'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  group('P16-A super-admin — 전환한 묶음과 남긴 것의 근거', () {
    test('A-1 전환한 6화면에 GradientScaffold 가 없다', () {
      for (final name in _converted) {
        final src = _superSrc(name);
        expect(src.contains('GradientScaffold('), isFalse, reason: name);
        expect(src.contains('AppPageScaffold('), isTrue, reason: name);
        expect(src.contains('gradient_scaffold.dart'), isFalse, reason: name);
      }
    });

    test('A-2 전환 조건이 실제로 성립했다 — headerContent 미사용', () {
      for (final name in _converted) {
        expect(_superSrc(name).contains('headerContent'), isFalse, reason: name);
      }
    });

    test('A-3 남긴 5화면은 그대로이고 그 이유가 소스에 있다', () {
      for (final e in _deferred.entries) {
        final src = _superSrc(e.key);
        expect(src.contains('GradientScaffold('), isTrue, reason: e.key);
        if (e.value == 'headerTab') {
          expect(src.contains('labelColor: Colors.white'), isTrue,
              reason: '${e.key}: 흰 탭 라벨이 flat app bar 에서 보이지 않는다');
        } else {
          expect(src.contains('Axis.horizontal'), isTrue,
              reason: '${e.key}: 가로 스크롤 표');
        }
      }
    });

    test('A-4 관리자 화면에 남은 GradientScaffold 는 역할 공유 화면 하나뿐이다', () {
      final dir = Directory('lib/screens/business_admin');
      final offenders = <String>[];
      for (final f in dir.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (_src(f.path).contains('GradientScaffold(')) offenders.add(f.path);
      }
      expect(offenders, isEmpty,
          reason: 'business_admin 트리에는 이미 남아 있지 않았다(주석만)');
      // 역할을 공유하는 settings_screen 은 사용자 경로용으로 유지한다.
      expect(_src(_settings).contains('GradientScaffold('), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  group('P16-C 계약 — 실패를 완료로 말하지 않는다', () {
    late String c;
    setUpAll(() => c = _src(_contract));

    test('C-1 두 로더의 실패를 상태로 들고 있다', () {
      expect(c.contains('bool _listLoadFailed = false;'), isTrue);
      expect(c.contains('bool _unsentLoadFailed = false;'), isTrue);
      expect(c.contains('setState(() => _listLoadFailed = true);'), isTrue);
      expect(c.contains('if (mounted) setState(() => _unsentLoadFailed = true);'),
          isTrue);
      // 재시도 전에 해제한다.
      expect(c.contains('_listLoadFailed = false;'), isTrue);
      expect(c.contains('_unsentLoadFailed = false;'), isTrue);
    });

    test('C-2 빈 상태에서 실패 분기가 먼저 온다', () {
      final i = c.indexOf('Widget _buildEmpty(');
      expect(i, greaterThan(-1));
      final body = c.substring(i, i + 1600);
      final failAt = body.indexOf('if (failed && !isSearching)');
      final unsentEmptyAt = body.indexOf("'미발송 계약서 없음'");
      expect(failAt, greaterThan(-1));
      expect(unsentEmptyAt, greaterThan(-1));
      expect(failAt, lessThan(unsentEmptyAt),
          reason: '미발송 없음은 "모두 보냈다"는 완료 주장이다');
      expect(body.contains("'미발송 계약서를 확인하지 못했습니다'"), isTrue);
      expect(body.contains("'계약서 목록을 불러오지 못했습니다'"), isTrue);
      expect(body.contains("label: const Text('다시 시도')"), isTrue);
    });

    test('C-3 원시 읽기는 경계에 있고 화면은 그것만 부른다', () {
      expect(c.contains('_reads.contractsPaged('), isTrue);
      expect(c.contains('_reads.unsentApplications('), isTrue);
      expect(c.contains('_contractService.getByBusinessPaged('), isFalse);
      expect(c.contains('.getUnsentApplicationsByBusiness('), isFalse);
      final seam = _src(_contractSeam);
      expect(seam.contains('contracts.getByBusinessPaged('), isTrue);
      expect(seam.contains('svc.getUnsentApplicationsByBusiness'), isTrue);
    });

    test('C-4 읽어 온 목록을 제자리에서 정렬하지 않는다', () {
      expect(c.contains('List<ApplicationModel>.of('), isTrue,
          reason: 'reader 가 불변 목록을 돌려줘도 되어야 한다');
    });

    test('C-5 권한 회수는 "계약 없음"이 아니다 (기존 계약 유지)', () {
      expect(c.contains("title: '접근 권한이 없습니다'"), isTrue);
      expect(c.contains('_accessRevoked'), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════
  group('P16-S 통계 — 단위·모집단·실패 (NO PATCH 근거)', () {
    late String st;
    late String svc;
    late String md;
    setUpAll(() {
      st = _src(_stats);
      svc = _src(_statsSvc);
      md = _src(_monthDetail);
    });

    test('S-1 실패를 0 이나 0원으로 말하지 않는다', () {
      expect(st.contains("'확인 불가'"), isTrue);
      expect(st.contains("'조회 실패'"), isTrue);
      expect(st.contains('attOk ?'), isTrue);
      // 서버 응답 봉투를 fail-closed 로 읽는다.
      expect(svc.contains('limitReached'), isTrue);
      expect(svc.contains('UNAVAILABLE'), isTrue);
    });

    test('S-2 지표 이름에 단위가 붙어 있다', () {
      expect(st.contains(r"'${data.totalWorkCount}건'"), isTrue);
      expect(st.contains("Text('총 인건비'"), isTrue);
    });

    test('S-3 근무일은 고유 날짜 수다 (건수로 대체하지 않는다)', () {
      expect(svc.contains('.map((r) => r.workDate.millisecondsSinceEpoch)'), isTrue);
      expect(svc.contains('.toSet()'), isTrue);
      expect(md.contains(r"Text('${worker.totalDays}일'"), isTrue);
      // 출결 배지는 건 단위라 '일' 을 붙이지 않는다.
      expect(md.contains(r"'지각 ${worker.lateDays}'"), isTrue);
      expect(md.contains(r"'지각 ${worker.lateDays}일'"), isFalse);
    });

    test('S-4 숫자를 눌렀을 때 선택 월·사업장 범위가 함께 간다', () {
      final i = st.indexOf('void _openMonthDetail(');
      expect(i, greaterThan(-1));
      final body = st.substring(i, i + 700);
      for (final arg in const [
        'businessIds: widget.businessIds',
        'filterBusinessId: _filterBusinessId',
        'year: _selectedYear',
        'month: month',
      ]) {
        expect(body.contains(arg), isTrue, reason: arg);
      }
    });
  });
}
