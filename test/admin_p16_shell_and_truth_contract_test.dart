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

/// P16-A 에서 남겼다가 **P1-7(P17-A)에서 전환한** super_admin 화면과 그 제약.
///   headerTab: 헤더 TabBar 라벨이 흰색이었다 → 전환과 함께 대비를 옮겼다.
///   wideTable: 가로 스크롤 표/도구 → 헤더 의존 색이 없어 shell 만 바뀌었고,
///             표 접근성은 좁은 폭 렌더로 확인했다.
const _formerlyDeferred = <String, String>{
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

    test('A-3 [P1-7] 남겼던 5화면도 전환됐고 제약이 함께 처리됐다', () {
      for (final e in _formerlyDeferred.entries) {
        final src = _superSrc(e.key);
        expect(src.contains('GradientScaffold('), isFalse, reason: e.key);
        expect(src.contains('AppPageScaffold('), isTrue, reason: e.key);
        if (e.value == 'headerTab') {
          // 흰 라벨을 밝은 배경에 그대로 두지 않았다.
          expect(src.contains('labelColor: Colors.white'), isFalse, reason: e.key);
          expect(src.contains('unselectedLabelColor: Colors.white70'), isFalse,
              reason: e.key);
          expect(src.contains('headerBottom: TabBar('), isFalse, reason: e.key);
          expect(src.contains('bottom: TabBar('), isTrue, reason: e.key);
        } else {
          // 표는 그대로 가로 스크롤이고, 헤더가 그려 주던 새로고침은 actions 로 옮겼다.
          expect(src.contains('Axis.horizontal'), isTrue, reason: e.key);
          // scaffold 인자로서의 onRefresh 만 사라졌다 — 목록의 RefreshIndicator 는 그대로다.
          final at = src.indexOf('AppPageScaffold(');
          expect(src.substring(at, at + 400).contains('onRefresh:'), isFalse,
              reason: e.key);
          // all_businesses 는 예전에 GradientScaffold.onRefresh 와 겹친다는 이유로
          //   RefreshIndicator 를 **의도적으로 뺐다** — 그래서 새로고침 수단은
          //   화면마다 하나이고, 그 하나가 actions 로 옮겨졌다(위 단언).
          expect(src.contains('Icons.refresh_rounded'), isTrue, reason: e.key);
        }
      }
    });

    test('A-5 [P1-7] super_admin 에 실제 GradientScaffold 호출이 0 이다', () {
      final dir = Directory('lib/screens/super_admin');
      final offenders = <String>[];
      for (final f in dir.listSync()) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        if (_codeOf(_src(f.path)).contains('GradientScaffold(')) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty);
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
// ══════════════════════════════════════════════════════════
  group('P17-D 문서 관리 색 — 실제 위반만 고쳤다', () {
    late String d;
    setUpAll(() => d = _src('lib/screens/common/document_management_screen.dart'));

    test('D-1 확인 완료가 앱의 success 색을 쓴다', () {
      expect(d.contains('0xFF22C55E'), isFalse,
          reason: '같은 함수의 다른 분기는 error/warning/infoDark 를 쓴다');
      final i = d.indexOf("label: '확인 완료',");
      expect(i, greaterThan(-1));
      expect(d.substring(i, i + 400).contains('color: AppColors.success'), isTrue);
    });

    test('D-2 도달 불가 분기의 색은 건드리지 않았다 (근거 보존)', () {
      // bankVerificationStatus 는 폐기됐고 서버가 그 값을 만들지 않는다.
      //   호출부가 isPending/isError 를 넘기지 않으므로 그 색은 화면에 나오지 않는다.
      expect(d.contains("bool isPending = false,"), isTrue);
      expect(d.contains("bool isError   = false,"), isTrue);
      expect(d.contains('isPending: '), isFalse);
      expect(d.contains('isError: '), isFalse);
    });

    test('D-3 중립 회색은 상태·행동 의미가 없어 그대로 둔다', () {
      // 개수 자체는 결함 근거가 아니다 — 판정을 기록으로 남긴다.
      for (final hex in const ['0xFF1F2937', '0xFF111827', '0xFFE5E7EB', '0xFF9CA3AF']) {
        expect(d.contains(hex), isTrue, reason: '$hex 는 이번 판정에서 유지');
      }
    });
  });
}
