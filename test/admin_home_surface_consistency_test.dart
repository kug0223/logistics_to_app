import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-05C HOME-SURFACE-CONSISTENCY
//
// 두 가지 drift가 있었다.
//   1. 같은 섹션이 상태에 따라 카드 깊이가 달랐다
//      (데이터 있으면 그림자, 로딩·빈·에러면 평면)
//   2. Home만 관리자 주요 화면 중 elevation을 썼다
//
// 그림자만 없앤다. 배경·radius·spacing·타이포·아이콘은 건드리지 않는다.
// ═══════════════════════════════════════════════════════════════

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';

String _src(String p) => File(p).readAsStringSync();
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') paren++;
    if (source[i] == ')') {
      paren--;
      if (paren == 0) {
        afterParams = i;
        break;
      }
    }
  }
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  fail('$signature 본문의 끝을 찾지 못함');
}

void main() {
  late String raw;
  late String home;

  setUpAll(() {
    raw = _src(_homePath);
    home = _codeOf(raw);
  });

  // ───────────────────────────────────────────────────────────
  // SURFACE-01 elevation 제거
  // ───────────────────────────────────────────────────────────
  group('SURFACE-01 Home elevation', () {
    test('Home에 그림자가 남아 있지 않다', () {
      expect('BoxShadow'.allMatches(home).length, 0);
      expect('boxShadow'.allMatches(home).length, 0);
      expect(home.contains('elevation:'), isFalse);
    });

    test('관리자 참조 화면과 같은 depth', () {
      for (final f in [
        'jobs_root_screen',
        'support_review_queue_screen',
        'unclosed_action_queue_screen',
      ]) {
        final s = _src('lib/screens/business_admin/$f.dart');
        expect('BoxShadow'.allMatches(s).length, 0, reason: f);
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  // SURFACE-02/03/04 상태별 depth 불변
  // ───────────────────────────────────────────────────────────
  group('SURFACE-02/03/04 상태가 달라도 같은 depth', () {
    test('오늘 운영 — 정상·에러·근태 에러', () {
      final t = _bodyOf(home, 'Widget _buildTodayOps(');
      expect(t.contains('boxShadow'), isFalse);
      // 세 상태가 모두 같은 컨테이너 안에서 그려진다
      expect(t.contains('_buildTodayStaffingSummary(s, theme)'), isTrue);
      expect(t.contains('_buildTodayAttendanceLine(s, theme)'), isTrue);
      expect(t.contains('_buildTodayIssueRows(context, s, up,'), isTrue);
      final m = _bodyOf(home, 'Widget? _buildTodayStaffingSummary(');
      expect(m.contains('인력 정보를 불러오지 못했습니다'), isTrue);
      expect(m.contains('boxShadow'), isFalse);
      final a = _bodyOf(home, 'Widget? _buildTodayAttendanceLine(');
      expect(a.contains('출근 현황을 불러오지 못했습니다'), isTrue);
      expect(a.contains('boxShadow'), isFalse);
    });

    test('다가오는 인력 부족 — 6개 상태 전부 평면', () {
      final f = _bodyOf(home, 'Widget _buildFutureStaffing(');
      expect(f.contains('boxShadow'), isFalse);
      // 상태 분기가 모두 살아 있는지 확인 (없애지 않았다)
      for (final marker in [
        '향후 인력 현황을 불러오지 못했습니다', // error
        // [HOME-V2-08D.2] no-target 분기는 제거됐다 — gate가 섹션 자체를
        //   숨기고 그 상태는 Hero가 설명한다.
        '향후 7일 인원이 모두 충원됐어요', // fully staffed
        '_buildFutureShortageRow(', // shortage
        '_partialStaffingNotice(s)', // partial
      ]) {
        expect(f.contains(marker), isTrue, reason: marker);
      }
      // [HOME-V2-08D.1] 컨테이너 decoration이 상태마다 동일 — 이제 같은
      //   토큰 하나를 공유하므로 "동일"이 값 비교가 아니라 참조로 보장된다.
      expect('decoration: _groupSurface,'.allMatches(f).length, 4,
          reason: '로딩 · 에러 · 전부충원 · 부족목록');
    });

    test('처리할 일 — 로딩·빈 상태·행 목록 전부 평면', () {
      final d = _bodyOf(home, 'Widget _buildActionDashboard(');
      expect(d.contains('boxShadow'), isFalse);
      expect(d.contains('_canonicalSummaryLoading'), isTrue);
      expect(d.contains('처리할 업무가 없어요'), isTrue);
      expect(d.contains('_buildActionRowWidget('), isTrue);
    });

    test('조회 실패 행도 같은 표면 안에 있다', () {
      final w = _bodyOf(home, 'Widget _buildActionRowWidget(');
      expect(w.contains('조회 실패'), isTrue);
      expect(w.contains('boxShadow'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  // SURFACE-05 다른 토큰 불변
  // ───────────────────────────────────────────────────────────
  group('SURFACE-05 시각 토큰 불변', () {
    // [HOME-V2-08D.1] 아래 셋은 원래 AH-V2-05C의 **범위 밖 표시**였다.
    //   "이번엔 배경·radius·border를 건드리지 않았다"는 scope guard였고,
    //   08D.1이 바로 그것들을 admin card 언어로 정렬하는 Phase다.
    //   AH-V2-05C가 지키려던 것 — 상태가 달라도 같은 depth, shadow 없음 —
    //   은 그대로 살아 있으므로 그쪽으로 다시 겨눈다.
    test('§10 surface가 토큰을 쓴다', () {
      expect(home.contains('color: AppColors.surface'), isTrue);
      // 남은 Colors.white는 surface가 아니라 전경(버튼 글자·선택된 토글 글자)이다
      expect('color: Colors.white'.allMatches(home).length, 0);
      expect('foregroundColor: Colors.white'.allMatches(home).length, 1);
    });

    test('§9 grouped surface가 단일 데코레이션을 공유한다', () {
      expect(
        home.contains('static final BoxDecoration _groupSurface = BoxDecoration('),
        isTrue,
      );
      // [HOME-V2-08D.2] Hero shell·skeleton이 같은 토큰을 재사용해 11곳.
      expect('decoration: _groupSurface,'.allMatches(home).length, 11,
          reason: 'Hero(2)·오늘·처리할 일(3)·다가오는(4)·공고 준비');
      // radius가 s에 곱해져 기기마다 달라지던 것이 사라졌다
      expect(home.contains('BorderRadius.circular(12 * s)'), isFalse);
    });

    test('§11 flat은 유지하되 경계는 border로 준다', () {
      // shadow는 여전히 0 — 이것이 AH-V2-05C의 본래 의도다
      expect('boxShadow'.allMatches(home).length, 0);
      final deco = _bodyOf(home, 'static final BoxDecoration _groupSurface');
      expect(deco.contains('border: Border.all(color: AppColors.grey200, width: 1)'),
          isTrue);
      expect(deco.contains('boxShadow'), isFalse);
    });

    test('§12 spacing 불변', () {
      // [HOME-V2-08D.2] Hero shell·skeleton·섹션 조립이 같은 gutter를 쓴다.
      expect('EdgeInsets.symmetric(horizontal: 16 * s)'.allMatches(home).length, 13);
      // 섹션 사이 16은 이제 _buildSections 한 곳이 소유한다
      expect('SizedBox(height: 16 * s)'.allMatches(home).length, 1);
      expect('SizedBox(height: 20 * s)'.allMatches(home).length, 1);
    });

    test('§13 typography', () {
      // [HOME-V2-08D.3] 18px w800 KPI 5개가 사라졌다 — 화면 최대 텍스트는
      //   이제 Hero(17)이고, Today는 issue 15 > 보조 13 > scope 12로 읽힌다.
      expect(home.contains('fontSize: 18'), isFalse, reason: 'KPI 수치 폐기');
      expect('fontSize: 15'.allMatches(home).length, 2, reason: 'Hero 이름 + issue row');
      expect('fontSize: 13'.allMatches(home).length, 11);
      expect('fontSize: 12'.allMatches(home).length, 22);
      expect(home.contains('fontSize: 11'), isFalse, reason: 'TYPO-50 하한 유지');
    });

    test('§14 상태 색·아이콘 불변', () {
      for (final t in [
        'AppColors.error', 'AppColors.warning', 'AppColors.grey400',
        'Icons.event_available_outlined',
        'Icons.account_balance_wallet_outlined',
      ]) {
        expect(home.contains(t), isTrue, reason: t);
      }
      // [HOME-V2-08D.3] 부족 위치 전용 `Icons.place_outlined` 행은 사라지고
      //   위치가 issue row 문장 안으로 들어갔다. 대신 두 issue의 semantic icon이 있다.
      expect(home.contains('Icons.place_outlined'), isFalse);
      final i = _bodyOf(home, 'List<Widget> _buildTodayIssueRows(');
      expect(i.contains('Icons.error_outline'), isTrue);
      expect(i.contains('Icons.schedule_outlined'), isTrue);
    });

    test('§19 헤더·배너·공고준비는 원래 평면이었고 그대로다', () {
      for (final sig in [
        'Widget _buildHeader(',
        'Widget _buildStateBanner(',
        'Widget _buildPostingSetupCard(',
      ]) {
        expect(_bodyOf(home, sig).contains('boxShadow'), isFalse, reason: sig);
      }
      // [HOME-V2-08D.1] 공고 준비 카드는 원래도 border를 가졌지만 값이 혼자
      //   달랐다(radius 12*s · border 0.8px). 이제 다른 섹션과 같은 것을 쓴다.
      final setup = _bodyOf(home, 'Widget _buildPostingSetupCard(');
      expect(setup.contains('decoration: _groupSurface,'), isTrue);
      expect(setup.contains('AppColors.border'), isFalse);
      expect(setup.contains('BorderRadius.circular(12 * s)'), isFalse);
    });

    test('§22 새 카드 컴포넌트를 만들지 않았다', () {
      for (final t in ['class CommonCard', 'class AdminSurface', 'class HomeCard']) {
        expect(raw.contains(t), isFalse, reason: t);
      }
      expect(home.contains('CommonWidgets.compactCardDecoration('), isFalse,
          reason: '이번 범위는 depth만 — 공통 데코 전환은 별도 판단');
    });

    test('§21 Scaffold를 바꾸지 않았다', () {
      expect(home.contains('Scaffold('), isTrue);
      expect(home.contains('AppPageScaffold'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  // SURFACE-30 상호작용 회귀
  // ───────────────────────────────────────────────────────────
  group('SURFACE-30 상호작용 불변', () {
    test('오늘 부족·근태 tap 유지', () {
      // [HOME-V2-08D.3] 두 tap 모두 issue row로 옮겨졌다 — destination은 그대로.
      final issues = _bodyOf(home, 'List<Widget> _buildTodayIssueRows(');
      expect(issues.contains('_navigateToDayApplicantsForDate(context, day)'), isTrue);
      expect(issues.contains('_openTodayAttendanceDialog(context)'), isTrue);
    });

    test('향후 부족 tap·충원하기 유지', () {
      final f = _bodyOf(home, 'Widget _buildFutureShortageRow(');
      expect(f.contains('_navigateToDayApplicantsForDate(context, day)'), isTrue);
      expect(f.contains('충원하기'), isTrue);
      expect(f.contains('InkWell('), isTrue);
    });

    test('재시도 버튼 유지', () {
      expect('재시도'.allMatches(home).length >= 2, isTrue);
      final e = _bodyOf(home, 'Widget _todayOpsErrorRow(');
      expect(e.contains('onRetry'), isTrue);
      expect(home.contains('onRefresh: _refresh'), isTrue);
    });

    test('행 tap·InkWell 유지', () {
      final w = _bodyOf(home, 'Widget _buildActionRowWidget(');
      expect(w.contains('onTap: item.onTap'), isTrue);
      expect(w.contains('InkWell('), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // SURFACE-31/32 IA·성능 회귀
  // ───────────────────────────────────────────────────────────
  group('SURFACE-31/32 이전 Phase 회귀', () {
    test('§15 TODAY → TASK → NEXT', () {
      // [HOME-V2-08D.2] 섹션 조립이 _buildSections로 옮겨졌다 — 순서는 그대로.
      final b = _bodyOf(home, 'List<Widget> _buildSections(');
      expect(b.indexOf('_buildTodayOps('),
          lessThan(b.indexOf('_buildActionDashboard(')));
      expect(b.indexOf('_buildActionDashboard('),
          lessThan(b.indexOf('_buildFutureStaffing(')));
    });

    test('섹션 집합 그대로', () {
      final titles = RegExp(r"_sectionHeader\(context, s, '([^']+)'")
          .allMatches(home)
          .map((m) => m.group(1))
          .toSet();
      expect(titles, {'오늘 운영', '다가오는 인력 부족', '처리할 일'});
    });

    test('§16 05B.3 연체 우선순위 유지', () {
      final rows = _bodyOf(home, '_makeActionRows(BuildContext context');
      expect(
        rows.contains(
            'final wageOverdue = wage?.available == true && (wage?.overdueCount ?? 0) > 0;'),
        isTrue,
      );
      expect(rows.contains('atIndex: wageOverdue ? overdueWageSlot : null,'), isTrue);
      expect(rows.contains('final overdueWageSlot = result.length;'), isTrue);
      expect(rows.contains('.sort('), isFalse);
    });

    test('처리할 일 9종 + 05B 순서 유지', () {
      final rows = _bodyOf(home, '_makeActionRows(BuildContext context');
      const order = [
        '퇴사 요청', '지원 검토', '스케줄 변경 요청', '계약 미발송', '마감 필요',
        '중간정산 요청', '급여 변경 요청', '이체 대기', '계약 종료 예정',
      ];
      var prev = -1;
      for (final label in order) {
        final at = rows.indexOf("label: '$label'");
        expect(at, greaterThan(prev), reason: label);
        prev = at;
      }
    });

    test('§32 05A dead loader 재도입 없음', () {
      for (final sym in [
        '_loadSummaryCounts', '_summaryActiveTO', '_summaryLoading',
        'getTOsByBusiness', 'callableGetTOsByBiz',
      ]) {
        expect(home.contains(sym), isFalse, reason: sym);
      }
    });

    test('§23 로더·네트워크 불변', () {
      final loaders = RegExp(r'Future<void> (_load[A-Za-z]*)\(')
          .allMatches(raw)
          .map((m) => m.group(1))
          .toSet();
      expect(loaders, {
        '_loadApprovedBusinessStatus', '_loadCanonicalSummary',
        '_loadPostingReadiness', '_loadStaffingReadiness', '_loadTodayAttendance',
      });
      expect(home.contains('httpsCallable'), isFalse);
    });

    test('§17/§18 error·empty 문구 불변', () {
      for (final c in [
        '인력 정보를 불러오지 못했습니다',
        '출근 현황을 불러오지 못했습니다',
        '향후 인력 현황을 불러오지 못했습니다',
        '처리할 업무가 없어요',
        // [HOME-V2-08D.2] 두 no-target 문구는 Hero로 역할이 넘어갔다.
        '향후 7일 인원이 모두 충원됐어요',
        '나머지 사업장 기준으로 표시했어요',
      ]) {
        expect(home.contains(c), isTrue, reason: c);
      }
    });

    test('AH-V2-03/04 계약 유지', () {
      expect(home.contains('hasUsableData'), isTrue);
      expect(home.contains(r"'근태 확인 $needsAttention건'"), isTrue);
      expect(home.contains('AttendanceReviewHelper.requiresReviewNow('), isTrue);
      expect(home.contains('WorkDetailTimeService.load(allConfirmed)'), isTrue);
      expect(home.contains('_isMultiBusinessScope'), isTrue);
      expect(home.contains('initialFilter: (approval?.overdueCount ?? 0) > 0'), isTrue);
    });

    test('§24 Functions 미변경', () {
      final cf = _src('functions/src/index.ts');
      expect(cf.contains('const nonPayable = (st === "NO_SHOW" || st === "absent") && fw === 0;'),
          isTrue);
      expect(cf.contains('available: failedBusinessCount === 0,'), isTrue);
    });
  });
}

/// 이번에 그림자를 걷어낸 세 섹션의 컨테이너 decoration 구간
List<String> _shadowedSections(String home) => [
      _bodyOf(home, 'Widget _buildTodayOps('),
      _bodyOf(home, 'Widget _buildFutureStaffing('),
      _bodyOf(home, 'Widget _buildActionDashboard('),
    ];
