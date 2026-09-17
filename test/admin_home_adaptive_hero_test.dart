// [HOME-V2-08D.2] Adaptive Hero + section gate
//
// Hero는 **지금 가장 먼저 알아야 하는 한 가지 상태**를 해석한다.
// 운영 action list가 아니다 — 행동 경로는 각 섹션이 갖는다.
//
// 이번 Phase의 가장 중요한 계약:
//   empty section을 없애는 순간, 그 의미를 Hero가 대신 설명해야 한다.
//   둘은 같은 commit에서만 성립한다.
//
// 그리고 섞이면 안 되는 두 truth:
//   공고 없음  ≠  처리할 업무 없음

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) throw StateError('$signature 를 찾지 못함');
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
  throw StateError('$signature 본문의 끝을 찾지 못함');
}

// ═══════════════════════════════════════════════════════════════
// Hero state derivation replica — `_heroStateOf`와 같은 순서
// ═══════════════════════════════════════════════════════════════

enum Hero {
  loading,
  error,
  partialInfo,
  setup,
  draftOnly,
  noPosting,
  shortage,
  attention,
  noToday,
  beforeStart,
  normalToday,
}

class HomeState {
  final bool staffingLoading;
  final bool attendanceLoading;
  final bool readinessLoaded;
  final bool isSubAdmin;

  /// null = staffing 전체 실패
  final bool? hasUsableData;
  final bool partial;
  final int publishedPostingCount;
  final bool hasDraftPosting;
  final bool hasTodayTarget;
  final bool hasFutureTarget;
  final int futureShortageTotal;
  final int todayShortage;

  /// null = readiness 미로드
  final bool? readinessAllReady;

  /// null = 출근 조회 실패
  final int? todayNeedsAttention;
  final int? todayDueNow;
  final bool? hasTodayRoster;

  const HomeState({
    this.staffingLoading = false,
    this.attendanceLoading = false,
    this.readinessLoaded = true,
    this.isSubAdmin = false,
    this.hasUsableData = true,
    this.partial = false,
    this.publishedPostingCount = 1,
    this.hasDraftPosting = false,
    this.hasTodayTarget = true,
    this.hasFutureTarget = false,
    this.futureShortageTotal = 0,
    this.todayShortage = 0,
    this.readinessAllReady = true,
    this.todayNeedsAttention = 0,
    this.todayDueNow = 5,
    this.hasTodayRoster = true,
  });
}

Hero heroOf(HomeState s) {
  if (s.staffingLoading || s.attendanceLoading || !s.readinessLoaded) {
    return Hero.loading;
  }
  if (s.hasUsableData != true) return Hero.error;
  if (!s.isSubAdmin && s.readinessAllReady == false) return Hero.setup;
  if (!s.partial && s.publishedPostingCount == 0) {
    return s.hasDraftPosting ? Hero.draftOnly : Hero.noPosting;
  }
  if (s.todayShortage > 0) return Hero.shortage;
  if ((s.todayNeedsAttention ?? 0) > 0) return Hero.attention;
  if (s.partial) return Hero.partialInfo;
  if (!s.hasTodayTarget && s.hasTodayRoster != true) return Hero.noToday;
  if (s.todayDueNow == 0) return Hero.beforeStart;
  return Hero.normalToday;
}

/// Hero가 CTA를 갖는 상태 — lifecycle과 error뿐이다.
bool heroHasCta(Hero h) =>
    h == Hero.setup ||
    h == Hero.noPosting ||
    h == Hero.draftOnly ||
    h == Hero.error ||
    h == Hero.partialInfo;

bool isLifecycle(Hero h) =>
    h == Hero.setup || h == Hero.noPosting || h == Hero.draftOnly;

// ── section gate replica ─────────────────────────────────────────

bool showToday(HomeState s) {
  if (s.staffingLoading || s.attendanceLoading) return true;
  if (s.hasUsableData != true) return true;
  // [HOME-V2-08D.3.1] 출근 조회 실패는 더 이상 단독 존재 근거가 아니다.
  //   오늘 운영 대상이 실재할 때만 섹션이 있고, 그때만 그 대상의 출근 실패가
  //   의미를 갖는다.
  if (s.hasTodayTarget) return true;
  return s.hasTodayRoster == true;
}

bool showUpcoming(HomeState s) {
  if (s.staffingLoading) return true;
  if (s.hasUsableData != true) return true;
  return s.hasFutureTarget;
}

bool showTasks(HomeState s, {required bool hasRows, bool summaryLoading = false}) {
  if (summaryLoading) return true;
  if (hasRows) return true;
  return !isLifecycle(heroOf(s));
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // §34 — 상태 matrix
  // ══════════════════════════════════════════════════════════════
  group('01. Hero state matrix', () {
    test('01-a A 준비 미완료', () {
      expect(heroOf(const HomeState(readinessAllReady: false)), Hero.setup);
    });

    test('01-b B 공고 0', () {
      expect(
        heroOf(const HomeState(publishedPostingCount: 0, hasDraftPosting: false)),
        Hero.noPosting,
      );
    });

    test('01-c B2 draft only', () {
      expect(
        heroOf(const HomeState(publishedPostingCount: 0, hasDraftPosting: true)),
        Hero.draftOnly,
      );
    });

    test('01-d E 오늘 정상', () {
      expect(heroOf(const HomeState()), Hero.normalToday);
    });

    test('01-e E′ 시작 전', () {
      expect(heroOf(const HomeState(todayDueNow: 0)), Hero.beforeStart);
    });

    test('01-f F 부족', () {
      expect(heroOf(const HomeState(todayShortage: 3)), Hero.shortage);
    });

    test('01-g G 근태 확인', () {
      expect(heroOf(const HomeState(todayNeedsAttention: 2)), Hero.attention);
    });

    test('01-h F+G 동시 → 부족 우선', () {
      expect(
        heroOf(const HomeState(todayShortage: 3, todayNeedsAttention: 2)),
        Hero.shortage,
        reason: '당일 충원은 마감 시각이 있어 회복 불가 구간이 있다',
      );
    });

    test('01-i H 오늘 없음 + 미래 있음', () {
      expect(
        heroOf(const HomeState(
            hasTodayTarget: false,
            hasTodayRoster: false,
            hasFutureTarget: true)),
        Hero.noToday,
      );
    });

    test('01-j D 미래 전부 충원 — 같은 noToday 분기, 문구만 다르다', () {
      final s = const HomeState(
          hasTodayTarget: false,
          hasTodayRoster: false,
          hasFutureTarget: true,
          futureShortageTotal: 0);
      expect(heroOf(s), Hero.noToday);
      expect(s.hasFutureTarget && s.futureShortageTotal == 0, true);
    });

    test('01-k D+8 only — 미래 target도 없다', () {
      expect(
        heroOf(const HomeState(
            hasTodayTarget: false,
            hasTodayRoster: false,
            hasFutureTarget: false,
            publishedPostingCount: 3)),
        Hero.noToday,
        reason: '공고는 있으므로 공고 없음으로 내려가면 안 된다',
      );
    });

    test('01-l partial', () {
      expect(heroOf(const HomeState(partial: true)), Hero.partialInfo);
    });

    test('01-m error', () {
      expect(heroOf(const HomeState(hasUsableData: false)), Hero.error);
    });

    test('01-n loading', () {
      expect(heroOf(const HomeState(staffingLoading: true)), Hero.loading);
      expect(heroOf(const HomeState(attendanceLoading: true)), Hero.loading);
      expect(heroOf(const HomeState(readinessLoaded: false)), Hero.loading);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §3 §21 §25 — ERROR ≠ ZERO
  // ══════════════════════════════════════════════════════════════
  group('02. partial / error가 없음을 주장하지 않는다', () {
    test('02-a partial + published 0 → 공고 없음 금지', () {
      final h = heroOf(const HomeState(partial: true, publishedPostingCount: 0));
      expect(h, isNot(Hero.noPosting));
      expect(h, isNot(Hero.draftOnly));
      expect(h, Hero.partialInfo);
    });

    test('02-b partial + 오늘 target 없음 → 오늘 없음 금지', () {
      final h = heroOf(const HomeState(
          partial: true, hasTodayTarget: false, hasTodayRoster: false));
      expect(h, isNot(Hero.noToday));
      expect(h, Hero.partialInfo);
    });

    test('02-c partial이어도 긍정 주장은 그대로 한다', () {
      // 부분합에서도 "3명 부족"은 참이다
      expect(heroOf(const HomeState(partial: true, todayShortage: 3)),
          Hero.shortage);
      expect(heroOf(const HomeState(partial: true, todayNeedsAttention: 2)),
          Hero.attention);
    });

    test('02-d 전체 실패는 lifecycle 분기보다 앞이다', () {
      expect(
        heroOf(const HomeState(hasUsableData: false, publishedPostingCount: 0)),
        Hero.error,
      );
    });

    test('02-e 로딩 중에는 아무 상태도 확정하지 않는다', () {
      expect(
        heroOf(const HomeState(staffingLoading: true, publishedPostingCount: 0)),
        Hero.loading,
      );
    });

    test('02-f readiness는 staffing과 다른 데이터라 partial과 무관', () {
      expect(heroOf(const HomeState(partial: true, readinessAllReady: false)),
          Hero.setup);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §5 §6 — CTA 계약
  // ══════════════════════════════════════════════════════════════
  group('03. Hero CTA', () {
    test('03-a lifecycle + error에만 CTA가 있다', () {
      for (final h in [Hero.setup, Hero.noPosting, Hero.draftOnly]) {
        expect(heroHasCta(h), true, reason: '$h');
      }
      expect(heroHasCta(Hero.error), true);
      expect(heroHasCta(Hero.partialInfo), true);
    });

    test('03-b 운영 상태에는 CTA가 없다 (08C.2)', () {
      for (final h in [
        Hero.normalToday,
        Hero.beforeStart,
        Hero.shortage,
        Hero.attention,
        Hero.noToday,
      ]) {
        expect(heroHasCta(h), false, reason: '$h');
      }
    });

    test('03-c broad boolean으로 결정하지 않는다 (§6)', () {
      // published==0 이어도 partial이면 CTA 상태가 아니다
      final partialZero =
          heroOf(const HomeState(partial: true, publishedPostingCount: 0));
      expect(isLifecycle(partialZero), false);
      // readiness 미완료가 아니어도 published>0이면 lifecycle이 아니다
      final operating = heroOf(const HomeState(publishedPostingCount: 5));
      expect(isLifecycle(operating), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §18 §19 §20 §22 §23 — section gate
  // ══════════════════════════════════════════════════════════════
  group('04. section gate', () {
    test('04-a 오늘 — target도 로스터도 없으면 숨긴다', () {
      expect(
        showToday(const HomeState(hasTodayTarget: false, hasTodayRoster: false)),
        false,
      );
    });

    test('04-b 오늘 — 로스터가 있으면 target이 없어도 렌더', () {
      expect(
        showToday(const HomeState(hasTodayTarget: false, hasTodayRoster: true)),
        true,
        reason: 'FULL 교정 지연 등으로 두 값이 어긋나도 근무자는 실재한다',
      );
    });

    test('04-c 오늘 — 로딩·staffing 실패에서는 숨기지 않는다', () {
      expect(showToday(const HomeState(staffingLoading: true, hasTodayTarget: false, hasTodayRoster: false)), true);
      expect(showToday(const HomeState(hasUsableData: false)), true);
      // [HOME-V2-08D.3.1] attendance 실패는 예외다 — staffing이 "오늘 대상 없음"을
      //   정상적으로 알려준 상태에서 출근만 못 읽은 것은 섹션의 존재 근거가 아니다.
      expect(
        showToday(const HomeState(
            todayNeedsAttention: null, hasTodayTarget: false, hasTodayRoster: false)),
        false,
      );
    });

    test('04-d 다가오는 — 미래 target 없으면 숨긴다', () {
      expect(showUpcoming(const HomeState(hasFutureTarget: false)), false);
      expect(showUpcoming(const HomeState(hasFutureTarget: true)), true);
    });

    test('04-e 다가오는 — 로딩·실패에서는 숨기지 않는다', () {
      expect(showUpcoming(const HomeState(staffingLoading: true, hasFutureTarget: false)), true);
      expect(showUpcoming(const HomeState(hasUsableData: false, hasFutureTarget: false)), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §20 §22 §23 — task truth 독립
  // ══════════════════════════════════════════════════════════════
  group('05. 처리할 일은 posting lifecycle과 독립', () {
    test('05-a 공고 0 + 미이체 있음 → task 섹션 렌더', () {
      final s = const HomeState(publishedPostingCount: 0);
      expect(heroOf(s), Hero.noPosting);
      expect(showTasks(s, hasRows: true), true);
    });

    test('05-b draft only + task 있음 → 렌더', () {
      final s =
          const HomeState(publishedPostingCount: 0, hasDraftPosting: true);
      expect(heroOf(s), Hero.draftOnly);
      expect(showTasks(s, hasRows: true), true);
    });

    test('05-c 준비 미완료 + 과거 task 있음 → 렌더 (§22)', () {
      final s = const HomeState(readinessAllReady: false);
      expect(heroOf(s), Hero.setup);
      expect(showTasks(s, hasRows: true), true);
    });

    test('05-d lifecycle + task 0 → 숨김', () {
      for (final s in [
        const HomeState(publishedPostingCount: 0),
        const HomeState(publishedPostingCount: 0, hasDraftPosting: true),
        const HomeState(readinessAllReady: false),
      ]) {
        expect(showTasks(s, hasRows: false), false);
      }
    });

    test('05-e 운영 상태 + task 0 → 한 줄 안내 렌더', () {
      for (final s in [
        const HomeState(),
        const HomeState(todayShortage: 3),
        const HomeState(todayNeedsAttention: 2),
        const HomeState(hasTodayTarget: false, hasTodayRoster: false),
      ]) {
        expect(showTasks(s, hasRows: false), true);
      }
    });

    test('05-f summary 로딩 중에는 숨기지 않는다 (§21)', () {
      expect(
        showTasks(const HomeState(publishedPostingCount: 0),
            hasRows: false, summaryLoading: true),
        true,
      );
    });

    test('05-g publishedPostingCount를 task gate에 쓰지 않는다 (§23)', () {
      final gate = _codeOf(_bodyOf(_src(_homePath), 'bool _showTaskSection('));
      expect(gate.contains('publishedPostingCount'), false);
      expect(gate.contains('hasDraftPosting'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 소스 고정
  // ══════════════════════════════════════════════════════════════
  group('06. 구현 소스', () {
    final home = _src(_homePath);
    final code = _codeOf(home);
    final derive = _codeOf(_bodyOf(home, '_HeroState _heroStateOf('));

    test('06-a 상태를 한 곳에서만 derive한다 (§2)', () {
      expect(code.contains('_HeroState _heroStateOf(UserProvider up)'), true);
      expect(RegExp(r'_heroStateOf\(').allMatches(code).length, 3,
          reason: '정의 1 + _buildAdaptiveHero + _buildSections');
    });

    test('06-b 우선순위가 계약대로다 (§3)', () {
      final order = [
        '_HeroState.loading',
        '_HeroState.error',
        '_HeroState.setup',
        '_HeroState.draftOnly',
        '_HeroState.shortage',
        '_HeroState.attention',
        '_HeroState.partialInfo',
        '_HeroState.noToday',
        '_HeroState.beforeStart',
        '_HeroState.normalToday',
      ];
      var prev = -1;
      for (final o in order) {
        final at = derive.indexOf(o);
        expect(at, greaterThan(prev), reason: o);
        prev = at;
      }
    });

    test('06-c partial이 lifecycle·noToday를 막는다', () {
      expect(derive.contains('if (!sr.partial && sr.publishedPostingCount == 0)'),
          true);
      expect(derive.contains('if (sr.partial) return _HeroState.partialInfo;'),
          true);
    });

    test('06-d Hero shell이 grouped surface를 재사용한다 (§4)', () {
      final shell = _codeOf(_bodyOf(home, 'Widget _heroShell('));
      expect(shell.contains('decoration: _groupSurface'), true);
      expect(shell.contains('fontSize: 17'), true);
      expect(shell.contains('fontSize: 13'), true);
      expect(shell.contains('BoxDecoration('), true); // 아이콘 원형만
      expect(shell.contains('boxShadow'), false);
    });

    test('06-e CTA는 optional이고 운영 상태에 없다 (§5)', () {
      final shell = _codeOf(_bodyOf(home, 'Widget _heroShell('));
      expect(shell.contains('if (ctaLabel != null && onCta != null)'), true);
      final hero = _codeOf(_bodyOf(home, 'Widget _buildAdaptiveHero('));
      // ctaLabel을 넘기는 분기 수 = error · partialInfo · noPosting · draftOnly
      expect(RegExp(r'ctaLabel:').allMatches(hero).length, 4);
    });

    test('06-f 권한 없으면 CTA를 숨긴다 — disabled teaser 아님 (§31)', () {
      final hero = _flat(_codeOf(_bodyOf(home, 'Widget _buildAdaptiveHero(')));
      expect(hero.contains("ctaLabel: _canCreatePosting(up) ? '공고 등록' : null"),
          true);
      expect(hero.contains("ctaLabel: _canCreatePosting(up) ? '작성 계속하기' : null"),
          true);
      final can = _codeOf(_bodyOf(home, 'bool _canCreatePosting('));
      expect(can.contains("_verified(up, (p) => p.canManageTo)"), true);
    });

    test('06-g 로딩 skeleton에 shimmer가 없다 (§24)', () {
      final sk = _codeOf(_bodyOf(home, 'Widget _heroSkeleton('));
      expect(sk.contains('AnimationController'), false);
      expect(sk.contains('Shimmer'), false);
      expect(sk.contains('shimmer'), false);
      expect(sk.contains('decoration: _groupSurface'), true);
    });

    test('06-h CTA destination은 기존 경로를 재사용한다 (§8, §9)', () {
      final create = _codeOf(_bodyOf(home, 'void _openCreatePosting('));
      expect(create.contains('AdminCreateTOScreen(initialBusinessId: initBizId)'),
          true);
      expect(create.contains('_requireApprovedBusiness('), true);
      expect(create.contains('_safeNavigate('), true);
      final draft = _codeOf(_bodyOf(home, 'void _openDraftPostings('));
      expect(
        draft.contains(
            'AdminTabSwitcher.instance.switchToTab(AdminTabSwitcher.jobsTab)'),
        true,
      );
      // 새 화면을 만들지 않았다
      expect(code.contains('class _DraftPostingsScreen'), false);
    });

    test('06-i error/partial CTA는 기존 retry를 쓴다 (§25)', () {
      final hero = _flat(_codeOf(_bodyOf(home, 'Widget _buildAdaptiveHero(')));
      expect(
        'onCta: () => unawaited(_loadStaffingReadiness())'
            .allMatches(hero)
            .length,
        2,
      );
    });

    test('06-j 기존 error 표면을 삭제하지 않았다 (§26)', () {
      expect(code.contains('_todayOpsErrorRow('), true);
      expect(code.contains('_partialStaffingNotice('), true);
      expect(code.contains('인력 정보를 불러오지 못했습니다'), true);
      expect(code.contains('출근 현황을 불러오지 못했습니다'), true);
      expect(code.contains('향후 인력 현황을 불러오지 못했습니다'), true);
    });

    test('06-k 오늘/다가오는 구조를 바꾸지 않았다 (§29, §30)', () {
      // [HOME-V2-08D.3] Today의 3-column KPI는 이 Phase에서 재구성됐다.
      //   §29가 지키려던 것은 "08D.2에서 Today를 건드리지 않는다"였고,
      //   재구성은 08D.3의 명시적 범위다. 남는 주장은 두 가지다:
      //   Today가 여전히 staffing·attendance·issue를 한 그룹에서 말하고,
      //   다가오는 7일은 **아직** 손대지 않았다(08D.4).
      for (final t in [
        '_buildTodayStaffingSummary(',
        '_buildTodayIssueRows(',
        '_buildTodayAttendanceLine(',
        '_buildFutureShortageRow(',
      ]) {
        expect(code.contains(t), true, reason: t);
      }
      final f = _codeOf(_bodyOf(home, 'Widget _buildFutureShortageRow('));
      expect(f.contains('_navigateToDayApplicantsForDate(context, day)'), true);
    });

    test('06-l section rename을 하지 않았다 (§28)', () {
      for (final t in ["'오늘'", "'처리할 일'", "'다가오는 7일'"]) {
        expect(home.contains(t), true, reason: t);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §33 §35 — read / 무회귀
  // ══════════════════════════════════════════════════════════════
  group('07. read · 무회귀', () {
    final home = _src(_homePath);
    final code = _codeOf(home);

    test('07-a 새 조회를 추가하지 않았다 (§33)', () {
      expect(
        RegExp(r'Future<void> _load\w+\(').allMatches(code).length,
        5,
      );
      for (final sig in [
        '_HeroState _heroStateOf(',
        'Widget _buildAdaptiveHero(',
        'List<Widget> _buildSections(',
        'bool get _showTodaySection',
        'bool get _showUpcomingSection',
        'bool _showTaskSection(',
      ]) {
        final body = _codeOf(_bodyOf(home, sig));
        expect(body.contains('await '), false, reason: sig);
        expect(body.contains('_firestoreService'), false, reason: sig);
        expect(body.contains('httpsCallable'), false, reason: sig);
      }
    });

    test('07-b lifecycle signal parsing 유지 (08B.2)', () {
      final model = _src('lib/models/ui/staffing_readiness_model.dart');
      expect(model.contains('final int publishedPostingCount;'), true);
      expect(model.contains('final bool hasDraftPosting;'), true);
    });

    test('07-c FULL staffing correction 유지 (08B.2)', () {
      final fn = _src('functions/src/index.ts');
      expect(
        _flat(fn).contains('.where("status", "in", ["ACTIVE", "SCHEDULED", "FULL"])'),
        true,
      );
    });

    test('07-d destination 무회귀 (§35)', () {
      expect(code.contains('_navigateToDayApplicantsForDate(context, day)'),
          true);
      expect(code.contains('_openTodayAttendanceDialog(context)'), true);
      expect(code.contains('_makeActionRows(context, s, up, cs)'), true);
      expect(code.contains('_setupTaskTile('), true);
    });

    test('07-e mutation freshness · self-origin skip 유지 (§35)', () {
      final att = _flat(
          _codeOf(_bodyOf(home, 'Future<void> _openTodayAttendanceDialog(')));
      expect(att.contains('unawaited(_loadTodayAttendance());'), true);
      expect(att.contains('unawaited(_loadStaffingReadiness());'), true);
      final onMut = _flat(_codeOf(_bodyOf(home, 'void _onAdminMutation(')));
      expect(
        onMut.contains(
            'if (WorkforceController.lastMutationOrigin == AdminMutationOrigin.home) { return; }'),
        true,
      );
    });

    test('07-f ERROR ≠ ZERO 유지 (§35)', () {
      final loader = _codeOf(_bodyOf(home, 'Future<void> _loadTodayAttendance('));
      final catchAt = loader.lastIndexOf('} catch (e) {');
      expect(loader.substring(catchAt).contains('_todayCheckedIn      = null;'),
          true);
      expect(code.contains('hasUsableData'), true);
    });
  });
}
