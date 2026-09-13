import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-05B HOME-INFORMATION-PRIORITY
//
//   TODAY → TASK → NEXT
//
// 오늘 상황을 본 다음 바로 지금 처리할 일이 오고,
// 다음 운영 준비가 마지막이다.
//
// 순서만 바꾼다. 데이터·permission·destination·쿼리는 그대로다.
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

/// §5 확정 순서
const _canonicalRowOrder = [
  '퇴사 요청',
  '지원 검토',
  '스케줄 변경 요청',
  '계약 미발송',
  '마감 필요',
  '중간정산 요청',
  '급여 변경 요청',
  '이체 대기',
  '계약 종료 예정',
];

/// 각 행이 걸린 permission (§12 부분 권한 검증용)
const _rowPermission = {
  '퇴사 요청': 'canManageWorkers',
  '지원 검토': 'canManageTo',
  '스케줄 변경 요청': 'canManageWorkers',
  '계약 미발송': 'canManageContract',
  '마감 필요': 'canManageWage',
  '중간정산 요청': 'canManageWage',
  '급여 변경 요청': 'canManageWage',
  '이체 대기': 'canManageWage',
  '계약 종료 예정': 'canManageContract',
};

void main() {
  late String raw;
  late String home;
  late String rows;

  setUpAll(() {
    raw = _src(_homePath);
    home = _codeOf(raw);
    rows = _bodyOf(home, '_makeActionRows(BuildContext context');
  });

  /// 소스에서 라벨 등장 순서를 뽑는다 (= 배열 추가 순서 = 렌더 순서)
  List<String> renderedRowOrder() {
    final hits = <MapEntry<int, String>>[];
    for (final label in _canonicalRowOrder) {
      final at = rows.indexOf("label: '$label'");
      expect(at, isNot(-1), reason: '$label 행이 사라졌다');
      hits.add(MapEntry(at, label));
    }
    hits.sort((a, b) => a.key.compareTo(b.key));
    return hits.map((e) => e.value).toList();
  }

  // ───────────────────────────────────────────────────────────
  // PRIORITY-01 섹션 순서
  // ───────────────────────────────────────────────────────────
  group('PRIORITY-01 TODAY → TASK → NEXT', () {
    test('오늘 운영 < 처리할 일 < 다가오는 인력 부족', () {
      final b = _bodyOf(home, 'Widget build(');
      final today = b.indexOf('_buildTodayOps(');
      final task = b.indexOf('_buildActionDashboard(');
      final next = b.indexOf('_buildFutureStaffing(');
      expect(today, isNot(-1));
      expect(today, lessThan(task), reason: '오늘 운영이 처리할 일보다 먼저');
      expect(task, lessThan(next), reason: '처리할 일이 향후 인력보다 먼저');
    });

    test('§2 선행 상태 섹션은 상단 유지', () {
      final b = _bodyOf(home, 'Widget build(');
      var prev = -1;
      for (final m in [
        '_buildHeader(',
        '_buildStateBanner(',
        '_buildPostingSetupCard(',
        '_buildTodayOps(',
      ]) {
        final at = b.indexOf(m);
        expect(at, greaterThan(prev), reason: m);
        prev = at;
      }
    });

    test('섹션 집합이 그대로 (추가·제거 없음)', () {
      final titles = RegExp(r"_sectionHeader\(context, s, '([^']+)'\)")
          .allMatches(home)
          .map((m) => m.group(1))
          .toSet();
      expect(titles, {'오늘 운영', '다가오는 인력 부족', '처리할 일'});
    });

    test('§3 처리할 일이 0건이어도 위치가 고정이다', () {
      // 섹션 배치는 build()의 정적 목록이며 count에 따른 분기가 없다
      final b = _bodyOf(home, 'Widget build(');
      final seg = b.substring(
          b.indexOf('_buildTodayOps('), b.indexOf('_buildFutureStaffing('));
      expect(seg.contains('if ('), isFalse,
          reason: '섹션 사이에 조건부 배치가 들어가면 순서가 흔들린다');
      // 빈 상태 문구는 대시보드 내부에서 처리된다
      expect(home.contains('처리할 업무가 없어요'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // PRIORITY-02 행 순서
  // ───────────────────────────────────────────────────────────
  group('PRIORITY-02 전권 관리자 행 순서', () {
    test('§5 확정 순서와 일치한다', () {
      expect(renderedRowOrder(), _canonicalRowOrder);
    });

    test('주석 번호도 새 순서를 따른다', () {
      final nums = RegExp(r'^    // (\d)\. (.+?) —', multiLine: true)
          .allMatches(raw)
          .where((m) => rows.contains("label: '${m.group(2)}'"))
          .toList();
      expect(nums.length, 9);
      for (var i = 0; i < nums.length; i++) {
        expect(nums[i].group(1), '${i + 1}');
        expect(nums[i].group(2), _canonicalRowOrder[i]);
      }
    });

    test('9종이 모두 살아 있다', () {
      expect(renderedRowOrder().toSet(), _canonicalRowOrder.toSet());
      expect("label: '".allMatches(rows).length, 9);
    });

    test('deadline 있는 일이 예고성 정보보다 앞선다', () {
      final o = renderedRowOrder();
      // 퇴사 요청(D+3 자동승인) < 계약 종료 예정(예고)
      expect(o.indexOf('퇴사 요청'), lessThan(o.indexOf('계약 종료 예정')));
      // 근무일 지나면 의미 없어지는 요청들이 사후 처리보다 앞
      expect(o.indexOf('지원 검토'), lessThan(o.indexOf('마감 필요')));
      expect(o.indexOf('스케줄 변경 요청'), lessThan(o.indexOf('마감 필요')));
      // 근무 전 계약 발송이 근무 후 정산보다 앞
      expect(o.indexOf('계약 미발송'), lessThan(o.indexOf('중간정산 요청')));
    });

    test('§6-8 이체 대기를 최상단으로 올리지 않았다', () {
      final o = renderedRowOrder();
      expect(o.indexOf('이체 대기'), greaterThan(o.indexOf('퇴사 요청')));
      expect(o.indexOf('이체 대기'), greaterThan(o.indexOf('마감 필요')));
      expect(o.first, '퇴사 요청');
    });
  });

  // ───────────────────────────────────────────────────────────
  // PRIORITY-03 부분 권한
  // ───────────────────────────────────────────────────────────
  group('PRIORITY-03 부분 권한에서도 상대 순서 유지', () {
    /// 주어진 permission 집합에서 보이는 행만 추린다
    List<String> visibleUnder(Set<String> perms) => renderedRowOrder()
        .where((r) => perms.contains(_rowPermission[r]))
        .toList();

    test('canManageWorkers만', () {
      expect(visibleUnder({'canManageWorkers'}), ['퇴사 요청', '스케줄 변경 요청']);
    });

    test('canManageWage만', () {
      expect(visibleUnder({'canManageWage'}),
          ['마감 필요', '중간정산 요청', '급여 변경 요청', '이체 대기']);
    });

    test('canManageContract만', () {
      expect(visibleUnder({'canManageContract'}), ['계약 미발송', '계약 종료 예정']);
    });

    test('canManageTo만', () {
      expect(visibleUnder({'canManageTo'}), ['지원 검토']);
    });

    test('혼합 — workers + contract', () {
      expect(visibleUnder({'canManageWorkers', 'canManageContract'}),
          ['퇴사 요청', '스케줄 변경 요청', '계약 미발송', '계약 종료 예정']);
    });

    test('부분 권한이 다른 행의 상대 순서를 바꾸지 않는다', () {
      final full = renderedRowOrder();
      for (final perms in [
        {'canManageWage'},
        {'canManageWorkers', 'canManageTo'},
        {'canManageTo', 'canManageWage', 'canManageContract'},
      ]) {
        final vis = visibleUnder(perms);
        final expected = full.where(vis.contains).toList();
        expect(vis, expected, reason: perms.toString());
      }
    });

    test('각 행의 permission 게이트가 그대로다', () {
      // 각 블록은 '// N. <라벨> — <permission>' 주석으로 시작한다.
      // 재배열 과정에서 라벨과 가드가 어긋나지 않았는지 확인한다.
      final raw = _src(_homePath);
      final blocks = RegExp(r'^    // \d\. (.+?) — (canManage\w+)$', multiLine: true)
          .allMatches(raw);
      final mapped = {
        for (final m in blocks) m.group(1)!: m.group(2)!,
      };
      expect(mapped, _rowPermission);

      // 주석뿐 아니라 실제 가드도 라벨보다 앞에 있어야 한다
      _rowPermission.forEach((label, perm) {
        final at = rows.indexOf("label: '$label'");
        final guardAt = rows.lastIndexOf('up.can((p) => p.$perm)', at);
        expect(guardAt, isNot(-1), reason: '$label → $perm 가드 없음');
      });
    });
  });

  // ───────────────────────────────────────────────────────────
  // §11 동적 정렬 금지
  // ───────────────────────────────────────────────────────────
  group('§11 DYNAMIC_SORTING_ADDED = NO', () {
    test('행 목록을 count/badge로 재정렬하지 않는다', () {
      expect(rows.contains('.sort('), isFalse);
      expect(rows.contains('compareTo'), isFalse);
      final dash = _bodyOf(home, 'Widget _buildActionDashboard(');
      expect(dash.contains('.sort('), isFalse);
      expect(dash.contains('compareTo'), isFalse);
    });

    test('ZERO_COUNT_ACTION_VISIBILITY 기존 정책 유지', () {
      // valid 0 → 숨김. 이건 숨김이지 재정렬이 아니다.
      expect(rows.contains('if (available && count == 0) return;'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §7 / §22 / §23 내용 불변
  // ───────────────────────────────────────────────────────────
  group('행 내용·destination·source 불변', () {
    test('§22 destination이 그대로다', () {
      expect(rows.contains('SupportReviewQueueScreen.route('), isTrue);
      expect(rows.contains('UnclosedActionQueueScreen.route()'), isTrue);
      expect('_toPayrollTabDrilldown('.allMatches(rows).length, 3);
    });

    test('§9 지원 검토 initialFilter 계약 유지', () {
      expect(rows.contains('initialFilter: (approval?.overdueCount ?? 0) > 0'),
          isTrue);
      expect(rows.contains('? SupportReviewFilter.overdue'), isTrue);
      expect(rows.contains(': SupportReviewFilter.all,'), isTrue);
    });

    test('§23 canonical count source가 그대로다', () {
      for (final sec in [
        'cs?.actions.resignRequest',
        'cs?.actions.approval',
        'cs?.actions.unclosed',
        'cs?.actions.wageChangeRequest',
        'cs?.actions.settlementRequest',
        'cs?.actions.scheduleChangeRequest',
        'cs?.actions.unsentContract',
        'cs?.actions.unpaidWage',
      ]) {
        expect(rows.contains(sec), isTrue, reason: sec);
      }
      expect(rows.contains('upcoming.expiringContract'), isTrue);
    });

    test('§8 퇴사 urgency badge 유지', () {
      expect(rows.contains('자동 승인'), isTrue);
    });

    test('§23 badge source 불변', () {
      expect(rows.contains("'긴급 \${approval!.overdueCount}건'"), isTrue);
      expect(rows.contains('가장 오래된:'), isTrue);
    });

    test('§10 이체 대기 의미를 확대하지 않았다', () {
      expect(rows.contains("label: '이체 대기'"), isTrue);
      expect(rows.contains('임금체불'), isFalse);
      // '연체 N건' 배지는 이번 Phase 이전부터 있던 것이고 서버
      // unpaidWage.overdueCount에서 온다. 라벨과 count 의미는 그대로다.
      expect(rows.contains("wageParts.add('연체 \${wage!.overdueCount}건')"), isTrue);
      expect(
        rows.contains('final wageTotal = (wage?.count ?? 0) + (wage?.missingDueDateCount ?? 0);'),
        isTrue,
        reason: 'count 산식 불변',
      );
    });

    test('에러 처리 경로 유지', () {
      expect(rows.contains('_showCanonicalError(context)'), isTrue);
      expect(rows.contains('_ensureCanonicalSummary(context)'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §13~15 성능·회귀
  // ───────────────────────────────────────────────────────────
  group('성능·이전 Phase 회귀', () {
    test('§14 loader 병렬 구조를 건드리지 않았다', () {
      final r = _bodyOf(home, 'Future<void> _refresh(');
      expect(r.contains('await Future.wait(['), isTrue);
      for (final l in [
        '_loadCanonicalSummary()',
        '_loadStaffingReadiness()',
        '_loadTodayAttendance()',
        '_reloadReadiness()',
      ]) {
        expect(r.contains(l), isTrue, reason: l);
      }
    });

    test('§13 loader 정의가 늘지 않았다', () {
      final loaders = RegExp(r'Future<void> (_load[A-Za-z]*)\(')
          .allMatches(raw)
          .map((m) => m.group(1))
          .toSet();
      expect(loaders, {
        '_loadApprovedBusinessStatus',
        '_loadCanonicalSummary',
        '_loadPostingReadiness',
        '_loadStaffingReadiness',
        '_loadTodayAttendance',
      });
    });

    test('§15 AH-V2-05A dead loader가 되살아나지 않았다', () {
      for (final sym in [
        '_loadSummaryCounts',
        '_summaryActiveTO',
        '_summaryLoading',
        '_summaryRequestGeneration',
        'getTOsByBusiness',
        'callableGetTOsByBiz',
      ]) {
        expect(home.contains(sym), isFalse, reason: sym);
      }
    });

    // [AH-V2-05C 갱신] Home의 elevation은 05C에서 전부 제거됐다.
    test('visual 미변경 — Home은 flat surface', () {
      expect('BoxShadow'.allMatches(home).length, 0);
    });

    test('AH-V2-01 ERROR != ZERO 유지', () {
      expect(home.contains('getBusinessesByIdsOrThrow('), isTrue);
      final att = _bodyOf(home, 'Future<void> _loadTodayAttendance(');
      expect(att.contains('_todayCheckedIn      = null'), isTrue);
    });

    test('AH-V2-03 staffing 상태 유지', () {
      expect(home.contains('hasUsableData'), isTrue);
      expect(home.contains('오늘 예정된 인력 운영이 없어요'), isTrue);
      expect(home.contains('향후 7일 예정된 인력 운영이 없어요'), isTrue);
      expect(home.contains('향후 7일 인원이 모두 충원됐어요'), isTrue);
    });

    test('AH-V2-04 근태·scope 유지', () {
      expect(home.contains("label: '근태 확인'"), isTrue);
      expect(home.contains('AttendanceReviewHelper.requiresReviewNow('), isTrue);
      expect(home.contains('WorkDetailTimeService.load(allConfirmed)'), isTrue);
      expect(home.contains('_isMultiBusinessScope'), isTrue);
      expect(home.contains('shortageScopeLabel()'), isTrue);
    });

    test('§17 check-in denominator를 건드리지 않았다', () {
      final m = _bodyOf(home, 'Widget _buildAttendanceMetrics(');
      expect(m.contains("label: '출근'"), isTrue);
      expect(m.contains('/'), isFalse, reason: '분모 표기를 추가하지 않았다');
    });
  });
}
