import 'dart:io';

import 'package:ALfit/screens/business_admin/support_review_queue_screen.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-04C APPROVAL-INITIAL-FILTER
//
// Home이 '긴급 M건'을 강조해 놓고 tap하면 전체 목록으로 보내던 것을
// 같은 집합으로 착지시킨다.
//
//   overdueCount > 0  → 기한 지남
//   overdueCount == 0 → 전체
//
// 새 화면·새 query 없음. 기존 Queue의 초기 상태만 연결한다.
// ═══════════════════════════════════════════════════════════════

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _queuePath = 'lib/screens/business_admin/support_review_queue_screen.dart';

String _src(String p) => File(p).readAsStringSync();
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _dartBody(String source, String signature) {
  final start = source.indexOf(signature);
  expect(start, isNot(-1), reason: '$signature 를 찾지 못함');
  final open = source.indexOf('{', start);
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

/// Home이 canonical overdueCount로 초기 필터를 정하는 규칙 (§4).
SupportReviewFilter _initialFilterFor(int overdueCount) =>
    overdueCount > 0 ? SupportReviewFilter.overdue : SupportReviewFilter.all;

// ── KST 시각 조립 (기기 timezone 무관) ─────────────────────────
DateTime _kstDay(int y, int m, int d) =>
    DateTime.utc(y, m, d).subtract(const Duration(hours: 9));

final _todayKst = _kstDay(2026, 9, 13);
final _nowKst = DateTime.utc(2026, 9, 13, 10, 0).subtract(const Duration(hours: 9));
final _yesterday = _kstDay(2026, 9, 12);
final _tomorrow = _kstDay(2026, 9, 14);

/// Queue의 _priorityOf overdue 분기 재현 (private이라 동일 식 + 소스 단정)
bool _queueOverdue(DateTime workDate, DateTime now) =>
    FormatHelper.toKstDate(workDate).isBefore(FormatHelper.toKstDate(now));

/// Queue가 initialFilter로 열렸을 때 첫 렌더에 보일 건수
int _visibleUnder(
    SupportReviewFilter filter, List<DateTime> pendingWorkDates, DateTime now) {
  return pendingWorkDates.where((wd) {
    final overdue = _queueOverdue(wd, now);
    final same = FormatHelper.toKstDate(wd)
        .isAtSameMomentAs(FormatHelper.toKstDate(now));
    switch (filter) {
      case SupportReviewFilter.all:
        return true;
      case SupportReviewFilter.overdue:
        return overdue;
      case SupportReviewFilter.today:
        return same;
      case SupportReviewFilter.upcoming:
        return !overdue && !same;
    }
  }).length;
}

void main() {
  late String home;
  late String queue;

  setUpAll(() {
    home = _codeOf(_src(_homePath));
    queue = _codeOf(_src(_queuePath));
  });

  // ───────────────────────────────────────────────────────────
  // §21 정책
  // ───────────────────────────────────────────────────────────
  group('APPROVAL-FILTER-01/02 초기 필터 결정', () {
    test('01 overdueCount == 0 → all', () {
      expect(_initialFilterFor(0), SupportReviewFilter.all);
    });

    test('02 count 7 / overdueCount 3 → overdue', () {
      expect(_initialFilterFor(3), SupportReviewFilter.overdue);
    });

    test('overdue 1건만 있어도 overdue', () {
      expect(_initialFilterFor(1), SupportReviewFilter.overdue);
    });

    test('§4 — overdue 0이면 today/upcoming으로 보내지 않는다', () {
      expect(_initialFilterFor(0), isNot(SupportReviewFilter.today));
      expect(_initialFilterFor(0), isNot(SupportReviewFilter.upcoming));
    });

    test('Home 배선이 같은 규칙을 쓴다', () {
      final rows = _dartBody(home, '_makeActionRows(BuildContext context');
      expect(
        rows.contains("initialFilter: (approval?.overdueCount ?? 0) > 0"),
        isTrue,
      );
      expect(rows.contains('? SupportReviewFilter.overdue'), isTrue);
      expect(rows.contains(': SupportReviewFilter.all,'), isTrue);
    });

    test('배지 조건과 초기 필터 조건이 같은 값을 본다', () {
      final rows = _dartBody(home, '_makeActionRows(BuildContext context');
      // 배지: (approval?.overdueCount ?? 0) > 0
      expect(rows.contains("badge: (approval?.overdueCount ?? 0) > 0"), isTrue);
      expect(
        "(approval?.overdueCount ?? 0) > 0".allMatches(rows).length,
        2,
        reason: '배지를 띄우는 조건과 overdue로 보내는 조건이 어긋나면 안 된다',
      );
    });
  });

  // ───────────────────────────────────────────────────────────
  // §15 단기/장기 혼합
  // ───────────────────────────────────────────────────────────
  group('APPROVAL-FILTER-03 단기 + 장기 혼합', () {
    test('short 2 + long 1 → Home 3, overdue 필터 3건', () {
      // 04C.1 이후 overdue predicate에 type 조건이 없다
      final pending = [
        _yesterday, _kstDay(2026, 9, 10),          // short overdue 2
        _kstDay(2026, 9, 1),                        // long_term overdue 1
        _todayKst,                                  // today
        _tomorrow,                                  // upcoming
      ];
      final homeOverdue =
          pending.where((wd) => _queueOverdue(wd, _nowKst)).length;
      expect(homeOverdue, 3);
      expect(_initialFilterFor(homeOverdue), SupportReviewFilter.overdue);
      expect(
          _visibleUnder(SupportReviewFilter.overdue, pending, _nowKst), 3);
    });

    test('장기만 기한 지남이어도 overdue로 착지', () {
      final pending = [_kstDay(2026, 9, 5), _tomorrow];
      final homeOverdue =
          pending.where((wd) => _queueOverdue(wd, _nowKst)).length;
      expect(homeOverdue, 1);
      expect(_initialFilterFor(homeOverdue), SupportReviewFilter.overdue);
      expect(_visibleUnder(SupportReviewFilter.overdue, pending, _nowKst), 1);
    });

    test('Home 숫자와 첫 렌더 건수가 같다', () {
      final pending = [_yesterday, _yesterday, _todayKst, _tomorrow];
      final n = pending.where((wd) => _queueOverdue(wd, _nowKst)).length;
      expect(_visibleUnder(_initialFilterFor(n), pending, _nowKst), n);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §5 / §7 API 하위호환
  // ───────────────────────────────────────────────────────────
  group('APPROVAL-FILTER-04 initialFilter 미지정 → all', () {
    test('생성자 기본값이 all', () {
      const s = SupportReviewQueueScreen(businessIds: ['b1'], businesses: []);
      expect(s.initialFilter, SupportReviewFilter.all);
    });

    test('route 기본값이 all', () {
      final r = SupportReviewQueueScreen.route(
          businessIds: ['b1'], businesses: []);
      expect(r, isA<Object>());
      expect(queue.contains('SupportReviewFilter initialFilter = SupportReviewFilter.all,'),
          isTrue, reason: 'route 파라미터 기본값');
    });

    test('명시 지정도 반영된다', () {
      const s = SupportReviewQueueScreen(
          businessIds: ['b1'],
          businesses: [],
          initialFilter: SupportReviewFilter.overdue);
      expect(s.initialFilter, SupportReviewFilter.overdue);
    });

    test('enum이 공개 API로 승격됐고 값이 4종 그대로', () {
      expect(SupportReviewFilter.values.length, 4);
      expect(SupportReviewFilter.values, [
        SupportReviewFilter.all,
        SupportReviewFilter.overdue,
        SupportReviewFilter.today,
        SupportReviewFilter.upcoming,
      ]);
      expect(queue.contains('enum _Filter'), isFalse);
    });

    test('필터 라벨 4종 유지', () {
      expect(SupportReviewFilter.all.label, '전체');
      expect(SupportReviewFilter.overdue.label, '기한 지남');
      expect(SupportReviewFilter.today.label, '오늘');
      expect(SupportReviewFilter.upcoming.label, '예정');
    });
  });

  // ───────────────────────────────────────────────────────────
  // §12 race
  // ───────────────────────────────────────────────────────────
  group('APPROVAL-FILTER-05 race — overdue로 열었는데 0건', () {
    test('overdue 필터의 빈 상태가 보인다 (0건)', () {
      final pending = [_todayKst, _tomorrow]; // 이미 다 처리돼 overdue 없음
      expect(_visibleUnder(SupportReviewFilter.overdue, pending, _nowKst), 0);
    });

    test('자동으로 all로 되돌리지 않는다', () {
      final init = _dartBody(queue, 'void initState(');
      expect(init.contains('_filter = widget.initialFilter;'), isTrue);
      // 로드 후 필터를 바꾸는 코드가 없어야 한다
      final load = _dartBody(queue, 'Future<void> _load(');
      expect(load.contains('_filter'), isFalse,
          reason: '로드 결과에 따라 필터를 몰래 바꾸면 무엇을 보는지 알 수 없다');
    });

    test('stale 데이터를 보여주지 않는다 — 실패 시 목록 클리어', () {
      final load = _dartBody(queue, 'Future<void> _load(');
      expect(load.contains('_apps         = [];'), isTrue);
      expect(load.contains('_hasLoadError = true;'), isTrue);
    });

    test('사용자가 직접 전체로 넓힐 수 있다 (자동 아님)', () {
      final e = _dartBody(queue, 'Widget _buildEmptyStateFiltered(');
      expect(e.contains('해당 조건의 지원이 없어요'), isTrue);
      expect(e.contains('onPressed: () => setState(() => _filter = SupportReviewFilter.all)'),
          isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §13 / §14 처리 후
  // ───────────────────────────────────────────────────────────
  group('APPROVAL-FILTER-06 처리 후 다음 진입', () {
    test('마지막 overdue 처리 → 다음 tap은 all', () {
      expect(_initialFilterFor(1), SupportReviewFilter.overdue);
      expect(_initialFilterFor(0), SupportReviewFilter.all,
          reason: '매 진입 시 최신 canonical summary 기준으로 재판단');
    });

    test('Home 복귀 시 summary를 다시 불러온다', () {
      final rows = _dartBody(home, '_makeActionRows(BuildContext context');
      expect(
        rows.contains('if (changed == true && mounted) unawaited(_loadCanonicalSummary());'),
        isTrue,
      );
    });

    test('초기 필터가 상수로 굳어 있지 않다 (매번 계산)', () {
      final rows = _dartBody(home, '_makeActionRows(BuildContext context');
      // onTap 클로저 안에서 approval을 읽는다 → 최신 summary 반영
      final at = rows.indexOf('initialFilter:');
      final onTapAt = rows.indexOf('onTap: () => _safeNavigate');
      expect(onTapAt, lessThan(at), reason: 'onTap 내부에서 결정');
    });
  });

  // ───────────────────────────────────────────────────────────
  // §8 / §16 / §19 비용·계약
  // ───────────────────────────────────────────────────────────
  group('비용과 계약', () {
    test('§8 client-side 필터링 유지 — 필터별 query 없음', () {
      final g = _dartBody(queue, 'List<_DateGroup> _buildGroups(');
      expect(g.contains('_apps.where('), isTrue);
      expect(g.contains('FirebaseFirestore'), isFalse);
      expect(g.contains('httpsCallable'), isFalse);
      // 로드는 여전히 1회
      expect('loadPendingApplications('.allMatches(queue).length, 1);
    });

    test('§8 Home에 loader를 추가하지 않았다', () {
      final r = _dartBody(home, 'Future<void> _refresh(');
      for (final l in [
        '_loadCanonicalSummary()',
        '_loadStaffingReadiness()', '_loadTodayAttendance()', '_reloadReadiness()',
      ]) {
        expect(r.contains(l), isTrue);
      }
      // 로더 정의 자체가 늘지 않았는지 — 호출 횟수가 아니라 메서드 집합으로 본다
      final loaders = RegExp(r'Future<void> (_load[A-Za-z]*)\(')
          .allMatches(_src(_homePath))
          .map((m) => m.group(1))
          .toSet();
      // [AH-V2-05A 갱신] _loadSummaryCounts는 dead loader라 제거됐다.
      expect(loaders, {
        '_loadApprovedBusinessStatus',
        '_loadCanonicalSummary',
        '_loadPostingReadiness',
        '_loadStaffingReadiness',
        '_loadTodayAttendance',
      });
    });

    test('§16 KST classifier를 되돌리지 않았다', () {
      final f = _dartBody(queue, '_Priority _priorityOf(');
      expect(f.contains('FormatHelper.toKstDate(DateTime.now())'), isTrue);
      expect(f.contains('DateTime(now.year, now.month, now.day)'), isFalse);
    });

    test('§19 business scope 그대로', () {
      final rows = _dartBody(home, '_makeActionRows(BuildContext context');
      expect(rows.contains('businessIds: businesses.map((b) => b.id).toList()'),
          isTrue);
      expect(rows.contains('businesses: businesses,'), isTrue);
      // 사업장/공고/날짜 강제 필터를 추가하지 않았다
      final q = _dartBody(queue, 'List<_DateGroup> _buildGroups(');
      expect(q.contains('toId'), isFalse);
    });

    test('§18 notification 기반 판단이 없다', () {
      final rows = _dartBody(home, '_makeActionRows(BuildContext context');
      final at = rows.indexOf('initialFilter:');
      final seg = rows.substring(at, at + 200);
      expect(seg.contains('notification'), isFalse);
      expect(seg.contains('unread'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §22 회귀
  // ───────────────────────────────────────────────────────────
  group('AH-V2-04C 범위 제한', () {
    test('필터 칩 UI 유지', () {
      expect(queue.contains('SupportReviewFilter.values.map((f) {'), isTrue);
    });

    test('날짜 grouping · priority 섹션 유지', () {
      expect(queue.contains('_buildGroups()'), isTrue);
      expect(queue.contains('_PrioritySectionHeader('), isTrue);
      expect(queue.contains('_DateGroupHeader('), isTrue);
      expect(queue.contains('group.priority != lastPriority && _filter == SupportReviewFilter.all'),
          isTrue, reason: 'priority 구분선은 전체 필터에서만 — 기존 동작');
    });

    test('사업장 summary 유지', () {
      expect(queue.contains('개 사업장'), isTrue);
    });

    test('Functions를 건드리지 않았다 — overdue 계약 그대로', () {
      final cf = _src('functions/src/index.ts');
      expect(cf.contains('if (wdTs && wdTs.toMillis() < todayMs) overdue++;'),
          isTrue);
      expect(cf.contains('.select("workDate")'), isTrue);
    });

    test('permission 불변 — approval = canManageTo', () {
      expect(home.contains('if (!isSub || up.can((p) => p.canManageTo)) {'), isTrue);
    });

    test('마감 필요 destination 불변', () {
      final rows = _dartBody(home, '_makeActionRows(BuildContext context');
      expect(rows.contains('UnclosedActionQueueScreen.route()'), isTrue,
          reason: '파라미터 없는 기존 호출 유지');
    });

    test('staffing · attendance 불변', () {
      expect(home.contains('_isMultiBusinessScope'), isTrue);
      expect(home.contains('shortageScopeLabel()'), isTrue);
      expect(home.contains("label: '근태 확인'"), isTrue);
      expect(home.contains('AttendanceReviewHelper.requiresReviewNow('), isTrue);
    });

    test('처리할 일 9종 유지', () {
      final rows = _dartBody(home, '_makeActionRows(BuildContext context');
      for (final label in [
        '퇴사 요청', '지원 검토', '마감 필요', '급여 변경 요청', '중간정산 요청',
        '스케줄 변경 요청', '계약 미발송', '계약 종료 예정', '이체 대기',
      ]) {
        expect(rows.contains("label: '$label'"), isTrue);
      }
    });

    test('Home section 순서 유지', () {
      // [HOME-V2-08D.2] 섹션 조립이 _buildSections로 옮겨졌다 — 순서는 그대로.
      final b = _dartBody(home, 'Widget build(') +
          _dartBody(home, 'List<Widget> _buildSections(');
      var prev = -1;
      for (final m in [
        '_buildHeader(', '_buildStateBanner(', '_buildAdaptiveHero(',
        // [AH-V2-05B] TODAY → TASK → NEXT
        '_buildTodayOps(', '_buildActionDashboard(', '_buildFutureStaffing(',
      ]) {
        final at = b.indexOf(m);
        expect(at, greaterThan(prev));
        prev = at;
      }
    });
  });
}
