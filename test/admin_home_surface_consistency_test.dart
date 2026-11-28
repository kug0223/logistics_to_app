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
// [R7-P1-4 H4] 홈의 원시 외부 읽기는 `admin_home_reads.dart` 경계로 옮겼다.
//   배선 계약은 "홈의 읽기 경로" 전체에 대한 것이므로 화면 + 경계를 함께 읽는다.
//   판정 기준은 낮추지 않았다 — strict variant·같은 로더 재사용을 여전히 요구한다.
const _readsPath = 'lib/screens/business_admin/admin_home_reads.dart';

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
    raw = _src(_homePath) + _codeOf(_src(_readsPath));
    home = _codeOf(raw);
  });

  // ───────────────────────────────────────────────────────────
  // SURFACE-01 elevation — [impl_26 §추가] 옛 이름("그림자 0")은 CP04 정밀 §6 뒤로 실제와 달랐다.
  //   홈 소스 문자열만 세서, 토큰(`ConceptSurface.raised()`)이 그리는 그림자를 보지 못했다.
  //   지금 실제: 그림자는 오늘·처리할 일·다가오는 최상위 그룹 raised 6 곳에만, 약한 그림자 1개.
  //   Hero·공고 준비(평면 `_groupSurface`) · 안쪽 항목 · 다른 Concept 표면에는 없다.
  // ───────────────────────────────────────────────────────────
  group('SURFACE-01 Home elevation', () {
    test('홈 그림자는 최상위 그룹 raised 토큰에만 있다(직접 그림자 · elevation 0)', () {
      // 홈이 직접 그리는 그림자·elevation 은 0 — 깊이는 토큰만 만든다.
      expect('BoxShadow'.allMatches(home).length, 0);
      expect('boxShadow'.allMatches(home).length, 0);
      expect(home.contains('elevation:'), isFalse);

      final tok = _codeOf(_src('lib/theme/concept_tokens.dart'));
      String decl(String sig) {
        final at = tok.indexOf(sig);
        expect(at, greaterThan(-1), reason: sig);
        final end = tok.indexOf('static ', at + sig.length);
        return tok.substring(at, end < 0 ? tok.length : end);
      }

      // 실제 그림자의 출처: raised 가 약한 그림자 1개를 갖는다(설계값 그대로).
      expect(decl('static BoxDecoration raised()').contains('boxShadow: _shadow,'), isTrue);
      final shadow = decl('static const List<BoxShadow> _shadow');
      expect('BoxShadow('.allMatches(shadow).length, 1);
      expect(shadow.contains('offset: Offset(0, 2)'), isTrue);
      expect(shadow.contains('blurRadius: 8'), isTrue);

      // 홈에서 그 토큰을 쓰는 곳 = 최상위 그룹 6 곳뿐. 함께 쓰는 다른 Concept 표면은 그림자가 없다.
      expect('ConceptSurface.raised()'.allMatches(home).length, 6);
      final used = RegExp(r'ConceptSurface\.(\w+)\(').allMatches(home).map((m) => m.group(1)!).toSet();
      expect(used, {'raised', 'count', 'staffingNeed'});
      for (final v in ['count', 'staffingNeed']) {
        expect(decl('static BoxDecoration $v()').contains('boxShadow'), isFalse, reason: v);
      }
      // Hero·공고 준비의 평면 표면에는 그림자가 없다.
      expect(_bodyOf(home, 'static final BoxDecoration _groupSurface').contains('boxShadow'), isFalse);
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
      // [impl_26 · UX Master §150 「앱 전체 문구 정본과 두 홈 표현」(2026-11-11) · 대표 홈 정본 보충 표 · DU 0fa6948] 해요체.
      expect(m.contains('인력 정보를 불러오지 못했어요'), isTrue);
      expect(m.contains('boxShadow'), isFalse);
      final a = _bodyOf(home, 'Widget? _buildTodayAttendanceLine(');
      expect(a.contains('출근 현황을 불러오지 못했어요'), isTrue); // [impl_26 · UX Master §150] 해요체
      expect(a.contains('boxShadow'), isFalse);
    });

    test('다가오는 7일 — 남은 상태 전부 평면', () {
      final f = _bodyOf(home, 'Widget _buildFutureStaffing(');
      expect(f.contains('boxShadow'), isFalse);
      // 상태 분기가 모두 살아 있는지 확인 (없애지 않았다)
      for (final marker in [
        '향후 인력 현황을 불러오지 못했어요', // error — [impl_26 · UX Master §150 「앱 전체 문구 정본과 두 홈 표현」(2026-11-11) · 대표 홈 정본 보충 표 · DU 0fa6948] 해요체
        // [HOME-V2-08D.2] no-target 분기는 제거됐다 — gate가 섹션 자체를
        //   숨기고 그 상태는 Hero가 설명한다.
        // [HOME-V2-08D.4] 전부충원 분기도 사라졌다 — 그 날짜들이 이제
        //   목록 안에 행으로 들어오기 때문이다.
        '_buildFutureShortageRow(', // 날짜 목록 (부족 · 전원 확정 공통)
        '_partialStaffingNotice(s)', // partial
      ]) {
        expect(f.contains(marker), isTrue, reason: marker);
      }
      // [HOME-V2-08D.1] 컨테이너 decoration이 상태마다 동일 — 이제 같은
      //   토큰 하나를 공유하므로 "동일"이 값 비교가 아니라 참조로 보장된다.
      // [impl_26 · DU_concept_CP04 정밀 사양(2026-11-12) · 코드 [CP04] 표지] 정밀 §6 — 오늘/할 일/다가오는 최상위 그룹은 `ConceptSurface.raised()` 하나를 공유한다
      //   (Hero 만 평면 `_groupSurface`). 상태마다 같은 토큰 하나라는 뜻 그대로 — 개수 3 그대로.
      expect('decoration: ConceptSurface.raised(),'.allMatches(f).length, 3,
          reason: '로딩 · 에러 · 날짜목록');
      expect(f.contains('decoration: _groupSurface,'), isFalse, reason: '한 섹션 안에서 두 표면이 섞이지 않는다');
    });

    test('처리할 일 — 로딩·빈 상태·행 목록 전부 평면', () {
      final d = _bodyOf(home, 'Widget _buildActionDashboard(');
      expect(d.contains('boxShadow'), isFalse);
      expect(d.contains('_canonicalSummaryLoading'), isTrue);
      expect(d.contains('처리할 업무가 없어요'), isTrue);
      expect(d.contains('_buildActionRowWidget('), isTrue);
    });

    test('데이터 상태 notice도 같은 표면 안에 있다', () {
      // [HOME-V2-08D.5] `조회 실패` 행이 사라지고 section notice가 그 자리를 받았다.
      //   같은 카드 안에서, 같은 depth로 그려진다는 AH-V2-05C의 요지는 그대로다.
      final w = _bodyOf(home, 'Widget _buildActionRowWidget(');
      expect(w.contains('조회 실패'), isFalse);
      expect(w.contains('boxShadow'), isFalse);
      final d = _bodyOf(home, 'Widget _buildActionDashboard(');
      expect(d.contains('_taskHealthNotice(s, total: summaryFailed)'), isTrue);
      expect(d.contains('boxShadow'), isFalse);
      // [impl_26 · DU_concept_CP04 정밀 사양(2026-11-12) · 코드 [CP04] 표지] 정밀 §6 — 처리할 일 그룹 = `ConceptSurface.raised()`(개수 2 그대로).
      expect('decoration: ConceptSurface.raised(),'.allMatches(d).length, 2,
          reason: '로딩 1 + 본문 1 — 상태가 달라도 같은 토큰');
      expect(d.contains('decoration: _groupSurface,'), isFalse);
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
      // [impl_26 · DU_concept_CP04 정밀 사양(2026-11-12) · 코드 [CP04] 표지] 정밀 §6 — 표면이 두 단계로 나뉘었다: Hero·준비(평면 `_groupSurface`) 3 +
      //   오늘·처리할 일·다가오는 최상위 그룹(`ConceptSurface.raised()`) 6 = 예전과 같은 9 자리.
      //   각 단계 안에서는 토큰 하나를 공유한다(값 비교가 아니라 참조).
      expect('decoration: _groupSurface,'.allMatches(home).length, 3,
          reason: 'Hero(2) · 공고 준비');
      expect('decoration: ConceptSurface.raised(),'.allMatches(home).length, 6,
          reason: '오늘 · 처리할 일(2) · 다가오는(3)');
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
      // [impl_26 · DU_concept_CP04 정밀 사양(2026-11-12) · 코드 [CP04] 표지] 좌우 여백은 `_gutter(context)`(= ConceptSpace.gutter · 폭 360 미만 16 · 그 외 20),
      //   섹션 사이는 `ConceptSpace.sectionGap` 이다(배율 s 를 곱하던 값 폐기). 소유 위치 단언은 그대로다.
      expect('EdgeInsets.symmetric(horizontal: _gutter(context))'.allMatches(home).length, 8);
      expect(home.contains('double _gutter(BuildContext context) => ConceptSpace.gutter('), isTrue);
      // 섹션 사이 간격은 이제 _buildSections 한 곳이 소유한다
      final sections = _bodyOf(home, 'List<Widget> _buildSections(');
      expect('ConceptSpace.sectionGap'.allMatches(home).length, 2);
      expect('ConceptSpace.sectionGap'.allMatches(sections).length, 2);
      expect('SizedBox(height: 16 * s)'.allMatches(home).length, 0, reason: '옛 배율 간격 재도입 0');
    });

    test('§13 typography', () {
      // [HOME-V2-08D.3] 18px w800 KPI 5개가 사라졌다 — 화면 최대 텍스트는
      //   이제 Hero(17)이고, Today는 issue 15 > 보조 13 > scope 12로 읽힌다.
      expect(home.contains('fontSize: 18'), isFalse, reason: 'KPI 수치 폐기');
      // [impl_26 · PP-TYPOGRAPHY(DU555 · DU586b · DU639a)] 크기는 역할 스타일(AppTextStyles.role*)이 정한다 —
      //   화면이 직접 15/13 을 쓰던 자리는 모두 역할로 옮겨졌다. 위계 규칙(18 금지 · 11 금지)은 그대로다.
      expect('fontSize: 15'.allMatches(home).length, 0);
      expect('fontSize: 13'.allMatches(home).length, 0);
      expect(home.contains('AppTextStyles.roleHomeHero()'), isTrue, reason: 'Hero 26');
      expect(home.contains('AppTextStyles.roleCardTitle()'), isTrue, reason: '카드 · 목록 제목 17');
      // [R7-P1-4 후속] 17 → 18: 부족 행의 범위 보조 줄(grey 12) 한 개가 늘었다.
      //   위계 규칙은 그대로다 — 18 금지 · 11 금지 · 15 는 다섯 자리.
      // [R7-P4.4E.2] 18 → 19: 계약서 템플릿 준비 행에 목적 설명 줄이 붙었다.
      //   오른쪽 힌트 슬롯(폭을 나눠 갖는 자리)에 문장을 넣었더니 라벨이
      //   '계약 / 서 템 / 플릿' 으로 쪼개져, 라벨 아래 줄로 내렸다.
      //   새 크기를 만들지 않고 힌트와 같은 12px 를 쓴다.
      // [R7-P4.4E.4] 19 → 18: 준비 카드 헤더의 `2 / 4 완료` 를 뺐다.
      //   제목이 이미 "2단계 남았어요" 라고 말한다 — 같은 사실을 같은 무게로
      //   두 번 두면 정작 다음 행동이 늦게 보이고, 좁은 화면에서는 제목을
      //   밀어냈다. 크기 체계는 그대로다(새 scale 없음).
      // [DU-VQ-03 · 후속13 §2] 18 → 19: 부족 통합 시 오늘 확정 근무의 업무·시간 보조 줄(12) 하나. 새 크기 없음.
      // [impl_26] 19 → 4: 나머지는 역할 스타일로 옮겨졌다. 남은 직접 12 네 자리는 impl_26 보고서의 후보 목록이다
      //   (역할표 보조 14 하한과 다름 — 판정 전 고정). 새 직접 크기가 생기면 실패한다.
      expect('fontSize: 12'.allMatches(home).length, 4);
      expect('fontSize:'.allMatches(home).length, 4, reason: '직접 크기는 위 12 네 자리뿐');
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
      // [impl_26 · DU_concept_CP04 정밀 사양(2026-11-12) · 코드 [CP04] 표지] 정밀 §4 — 부족 숫자는 요약의 `N명 추가 필요` 알약이 한 번 말하고, 이 목록의 부족 행은
      //   같은 숫자를 다시 쓰지 않는 `_shortageDetailRow`(행동 · 범위 context)로 바뀌었다 — 그래서 error_outline 행이 없다.
      expect(i.contains('Icons.error_outline'), isFalse);
      expect(i.contains('_shortageDetailRow('), isTrue);
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
      expect(f.contains('Icons.chevron_right'), isTrue);
      expect(f.contains('InkWell('), isTrue);
    });

    test('재시도 버튼 유지', () {
      // [impl_26 · UX Master §150 「앱 전체 문구 정본과 두 홈 표현」(2026-11-11) · 대표 홈 정본 보충 표 · DU 0fa6948] 행동 문구 `재시도` → `다시 시도`.
      expect('다시 시도'.allMatches(home).length >= 2, isTrue);
      expect(home.contains("'재시도'"), isFalse);
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
      // [impl_26 · UX Master §150 「앱 전체 문구 정본과 두 홈 표현」(2026-11-11) · 대표 홈 정본 보충 표 · DU 0fa6948] 섹션 제목 = 「오늘의 근무 / 처리할 일 / 다가오는 근무 + 앞으로 7일」.
      //   집합 크기 3 · 순서 단언은 그대로 — 이름만 정본으로 바뀌었다.
      expect(titles, {'오늘의 근무', '다가오는 근무', '처리할 일'});
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
        // [impl_26 · UX Master §150 「앱 전체 문구 정본과 두 홈 표현」(2026-11-11) · 대표 홈 정본 보충 표 · DU 0fa6948] 할 일 제목 `스케줄 변경 요청` → `일정 변경 요청`(9종 · 순서 그대로).
        '퇴사 요청', '지원 검토', '일정 변경 요청', '계약 미발송', '마감 필요',
        '중간정산 요청', '급여 변경 요청', '이체 대기', '계약 확인 필요',
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
        // [impl_26 · UX Master §150 「앱 전체 문구 정본과 두 홈 표현」(2026-11-11) · 대표 홈 정본 보충 표 · DU 0fa6948] 해요체로 바뀐 세 문구(같은 상태 · 어미만).
        '인력 정보를 불러오지 못했어요',
        '출근 현황을 불러오지 못했어요',
        '향후 인력 현황을 불러오지 못했어요',
        '처리할 업무가 없어요',
        // [HOME-V2-08D.2] 두 no-target 문구는 Hero로 역할이 넘어갔다.
        // [HOME-V2-08D.4] `모두 충원됐어요`도 사라졌다 — 그 날짜들이 행이 됐다.
        '나머지 사업장 기준으로 표시했어요',
      ]) {
        expect(home.contains(c), isTrue, reason: c);
      }
    });

    test('AH-V2-03/04 계약 유지', () {
      expect(home.contains('hasUsableData'), isTrue);
      expect(home.contains(r"'근태 확인 $needsAttention건'"), isTrue);
      expect(home.contains('AttendanceReviewHelper.requiresReviewNow('), isTrue);
      expect(home.contains('_reads.workDetailTimes(allConfirmed)'), isTrue);
      expect(home.contains('workDetailTimes: WorkDetailTimeService.load'), isTrue);
      expect(home.contains('_isMultiBusinessScope'), isTrue);
      expect(home.contains('initialFilter: (approval?.overdueCount ?? 0) > 0'), isTrue);
    });

    test('§24 Functions 미변경', () {
      final cf = _src('functions/src/index.ts');
      // [.6-P1] 인라인 판정이 canonical helper 로 옮겨갔다. 지키려던 것은
      //   "Home 이 지급 대상을 직접 가린다"는 사실이므로 그 자리를 본다.
      expect(cf.contains('function srvPayableForTransfer('), isTrue);
      expect(cf.contains('srvPayableForTransfer('), isTrue);
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
