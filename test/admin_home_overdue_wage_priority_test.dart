import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-05B.3 OVERDUE-WAGE-PRIORITY
//
// 평상시 '이체 대기'는 8순위 그대로 — 정기 이체 물량이 많다는 것은
// 긴급이 아니다.
//
// 지급예정일이 지난 급여가 있을 때만 퇴사 요청 바로 뒤로 올린다.
// 조건은 canonical overdueCount 하나뿐이고, 움직이는 행도 이것 하나뿐이다.
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

// ── canonical 순서 ───────────────────────────────────────────
const _normalOrder = [
  '퇴사 요청', '지원 검토', '스케줄 변경 요청', '계약 미발송', '마감 필요',
  '중간정산 요청', '급여 변경 요청', '이체 대기', '계약 종료 예정',
];
const _overdueOrder = [
  '퇴사 요청', '이체 대기', '지원 검토', '스케줄 변경 요청', '계약 미발송',
  '마감 필요', '중간정산 요청', '급여 변경 요청', '계약 종료 예정',
];

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

/// 서버 unpaidWage 섹션
class _Wage {
  final bool available;
  final int count;
  final int overdueCount;
  final int missingDueDateCount;
  const _Wage({
    this.available = true,
    this.count = 0,
    this.overdueCount = 0,
    this.missingDueDateCount = 0,
  });
}

/// _makeActionRows의 배치 알고리즘 재현.
///
/// 빌드 순서는 canonical 1..9 고정이고, '이체 대기'만 조건부로
/// 퇴사 요청 직후 슬롯에 insert된다.
List<String> _buildRows({
  required _Wage wage,
  Set<String> perms = const {
    'canManageWorkers', 'canManageTo', 'canManageWage', 'canManageContract',
  },
  Map<String, int> counts = const {},
  Set<String> unavailable = const {},
}) {
  final result = <String>[];
  var slot = -1;

  void add(String label, {int? atIndex}) {
    if (!perms.contains(_rowPermission[label])) return;
    final available = !unavailable.contains(label);
    final count = counts[label] ?? 1;
    // [HOME-V2-08D.5] UNKNOWN도 행이 되지 않는다 — 없는 업무를 만들지 않는다
    if (!available || count == 0) return;
    if (atIndex != null) {
      result.insert(atIndex, label);
    } else {
      result.add(label);
    }
  }

  add('퇴사 요청');
  slot = result.length; // [AH-V2-05B.3] 퇴사 요청 바로 뒤
  add('지원 검토');
  add('스케줄 변경 요청');
  add('계약 미발송');
  add('마감 필요');
  add('중간정산 요청');
  add('급여 변경 요청');

  final wageTotal = wage.count + wage.missingDueDateCount;
  final wageOverdue = wage.available && wage.overdueCount > 0;
  if (perms.contains('canManageWage')) {
    // [HOME-V2-08D.5] 확인하지 못한 값(available=false)도 행이 되지 않는다.
    if (wage.available && wageTotal > 0) {
      if (wageOverdue) {
        result.insert(slot, '이체 대기');
      } else {
        result.add('이체 대기');
      }
    }
  }

  add('계약 종료 예정');
  return result;
}

void main() {
  late String raw;
  late String home;
  late String rows;

  setUpAll(() {
    raw = _src(_homePath);
    home = _codeOf(raw);
    rows = _bodyOf(home, '_makeActionRows(BuildContext context');
  });

  // ───────────────────────────────────────────────────────────
  // §19~22 이동 조건
  // ───────────────────────────────────────────────────────────
  group('WAGE-PRIORITY-01~04 이동 조건', () {
    test('01 overdueCount = 0 → 8순위 유지', () {
      expect(_buildRows(wage: const _Wage(count: 5)), _normalOrder);
    });

    test('02 overdueCount = 3 → 퇴사 요청 바로 뒤', () {
      expect(_buildRows(wage: const _Wage(count: 5, overdueCount: 3)),
          _overdueOrder);
    });

    test('연체 1건만 있어도 올라간다', () {
      final r = _buildRows(wage: const _Wage(count: 1, overdueCount: 1));
      expect(r.indexOf('이체 대기'), 1);
    });

    test('03 missingDueDateCount만 있으면 올라가지 않는다', () {
      expect(
        _buildRows(wage: const _Wage(missingDueDateCount: 5)),
        _normalOrder,
        reason: '데이터 확인 필요와 지급일 경과는 urgency가 다르다',
      );
    });

    test('04 count가 많아도 연체 0이면 올라가지 않는다', () {
      expect(_buildRows(wage: const _Wage(count: 100)), _normalOrder,
          reason: '정기 이체 물량은 긴급이 아니다');
    });

    test('연체 + 지급일 미설정 동시 → 연체 기준으로 상향', () {
      final r = _buildRows(
          wage: const _Wage(count: 9, overdueCount: 2, missingDueDateCount: 4));
      expect(r, _overdueOrder);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §13 available == false
  // ───────────────────────────────────────────────────────────
  group('WAGE-PRIORITY-06 조회 실패 시 이동하지 않는다', () {
    test('available=false면 overdueCount가 있어도 승격되지 않는다', () {
      // [HOME-V2-08D.5] 이제 행 자체가 생기지 않으므로 승격될 대상도 없다.
      //   "불완전한 값으로 urgency를 판단하지 않는다"는 요지는 더 강해졌다 —
      //   overdueCount 9를 믿고 자리를 옮기는 일이 구조적으로 불가능하다.
      final r = _buildRows(
        wage: const _Wage(available: false, count: 3, overdueCount: 9),
        unavailable: {'이체 대기'},
      );
      expect(r, _normalOrder.where((l) => l != '이체 대기').toList(),
          reason: '불완전한 값으로 urgency를 판단하면 안 된다');
      expect(r.contains('이체 대기'), isFalse);
    });

    test('available=false면 행 자체가 생기지 않는다 (§08D.5)', () {
      // [HOME-V2-08D.5] 이전에는 `조회 실패` 칩을 달고 제자리에 남았다.
      //   그 행의 존재가 "처리할 이체가 있다"는 뜻이라 없는 업무를 만들어냈다.
      //   확인하지 못했다는 사실은 이제 section notice가 말한다.
      final r = _buildRows(
        wage: const _Wage(available: false, count: 0, overdueCount: 0),
        unavailable: {'이체 대기'},
      );
      expect(r.contains('이체 대기'), isFalse);
      // 나머지 행의 상대 순서는 그대로다 — 연체 승격도 일어나지 않았다
      expect(r, _normalOrder.where((l) => l != '이체 대기').toList());
    });

    test('소스 조건이 available을 함께 본다', () {
      expect(
        rows.contains(
            'final wageOverdue = wage?.available == true && (wage?.overdueCount ?? 0) > 0;'),
        isTrue,
      );
    });
  });

  // ───────────────────────────────────────────────────────────
  // §10~12 권한과 상대 순서
  // ───────────────────────────────────────────────────────────
  group('WAGE-PRIORITY-05 권한·부분수열', () {
    test('05 canManageWage 없으면 연체가 있어도 행 자체가 없다', () {
      final r = _buildRows(
        wage: const _Wage(count: 5, overdueCount: 3),
        perms: {'canManageWorkers', 'canManageTo', 'canManageContract'},
      );
      expect(r.contains('이체 대기'), isFalse);
      expect(r, ['퇴사 요청', '지원 검토', '스케줄 변경 요청', '계약 미발송', '계약 종료 예정']);
    });

    test('퇴사 요청이 숨겨지면 이체 대기가 맨 앞', () {
      final r = _buildRows(
        wage: const _Wage(count: 2, overdueCount: 1),
        perms: {'canManageTo', 'canManageWage', 'canManageContract'},
      );
      expect(r.first, '이체 대기');
    });

    test('퇴사 요청이 0건으로 숨겨져도 맨 앞', () {
      final r = _buildRows(
        wage: const _Wage(count: 2, overdueCount: 1),
        counts: {'퇴사 요청': 0},
      );
      expect(r.first, '이체 대기');
    });

    test('12 부분 권한에서도 canonical 부분수열', () {
      for (final perms in [
        {'canManageWorkers', 'canManageWage'},
        {'canManageTo', 'canManageWage'},
        {'canManageWage', 'canManageContract'},
        {'canManageWorkers', 'canManageTo', 'canManageWage'},
      ]) {
        final normal = _buildRows(wage: const _Wage(count: 3), perms: perms);
        expect(normal, _normalOrder.where(normal.contains).toList(),
            reason: 'normal $perms');

        final over =
            _buildRows(wage: const _Wage(count: 3, overdueCount: 1), perms: perms);
        expect(over, _overdueOrder.where(over.contains).toList(),
            reason: 'overdue $perms');
      }
    });

    test('§10 이체 대기 외 8행의 상대 순서는 연체 여부와 무관', () {
      List<String> others(List<String> r) =>
          r.where((x) => x != '이체 대기').toList();
      final normal = _buildRows(wage: const _Wage(count: 3));
      final over = _buildRows(wage: const _Wage(count: 3, overdueCount: 2));
      expect(others(over), others(normal));
    });

    test('0건 숨김이 섞여도 상대 순서 유지', () {
      final counts = {'마감 필요': 0, '중간정산 요청': 0, '계약 종료 예정': 0};
      final normal = _buildRows(wage: const _Wage(count: 3), counts: counts);
      final over = _buildRows(
          wage: const _Wage(count: 3, overdueCount: 1), counts: counts);
      expect(normal, _normalOrder.where(normal.contains).toList());
      expect(over, _overdueOrder.where(over.contains).toList());
    });
  });

  // ───────────────────────────────────────────────────────────
  // §25 generic sorter 없음
  // ───────────────────────────────────────────────────────────
  group('WAGE-PRIORITY-07 explicit placement only', () {
    test('정렬기·점수 체계가 없다', () {
      for (final t in ['.sort(', 'compareTo', 'priorityScore', 'severity']) {
        expect(rows.contains(t), isFalse, reason: t);
      }
      final dash = _bodyOf(home, 'Widget _buildActionDashboard(');
      expect(dash.contains('.sort('), isFalse);
      expect(dash.contains('compareTo'), isFalse);
    });

    test('atIndex를 쓰는 행은 이체 대기 하나뿐', () {
      expect('atIndex:'.allMatches(rows).length, 1);
      expect(rows.contains('atIndex: wageOverdue ? overdueWageSlot : null,'), isTrue);
    });

    test('슬롯은 퇴사 요청 직후 길이로 정한다 (라벨 비교 아님)', () {
      expect(rows.contains('final overdueWageSlot = result.length;'), isTrue);
      final slotAt = rows.indexOf('final overdueWageSlot = result.length;');
      final resignAt = rows.indexOf("label: '퇴사 요청'");
      final approvalAt = rows.indexOf("label: '지원 검토'");
      expect(resignAt, lessThan(slotAt), reason: '퇴사 요청 add 이후');
      expect(slotAt, lessThan(approvalAt), reason: '지원 검토 add 이전');
    });

    test('add()가 insert/add 두 경로만 갖는다', () {
      // rows는 주석이 제거된 코드라 코드 마커로 자른다
      final addFn = rows.substring(
          rows.indexOf('void add({'), rows.indexOf('final overdueWageSlot'));
      expect(addFn.contains('result.insert(atIndex, row);'), isTrue);
      expect(addFn.contains('result.add(row);'), isTrue);
      expect(addFn.contains('if (!available || count == 0) return;'), isTrue,
          reason: 'ZERO_COUNT_ACTION_VISIBILITY 유지');
    });

    test('§6 이동 조건에 금지된 입력이 쓰이지 않는다', () {
      final at = rows.indexOf('final wageOverdue =');
      final line = rows.substring(at, rows.indexOf('\n', at));
      for (final t in [
        'missingDueDateCount', 'wageTotal', 'wageParts', 'businesses', 'notification',
      ]) {
        expect(line.contains(t), isFalse, reason: t);
      }
      expect(line.contains('overdueCount'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §8 / §26 / §27 행 내용·destination 불변
  // ───────────────────────────────────────────────────────────
  group('WAGE-PRIORITY-08 행 계약 불변', () {
    test('title·count·badge 산식 그대로', () {
      expect(rows.contains("label: '이체 대기'"), isTrue);
      expect(
        rows.contains('final wageTotal = (wage?.count ?? 0) + (wage?.missingDueDateCount ?? 0);'),
        isTrue,
      );
      expect(rows.contains(r"wageParts.add('연체 ${wage!.overdueCount}건')"), isTrue);
      expect(
        rows.contains(r"wageParts.add('지급일 확인 필요 ${wage!.missingDueDateCount}명')"),
        isTrue,
      );
      expect(rows.contains('icon: Icons.account_balance_wallet_outlined'), isTrue);
      expect(rows.contains('available: wage?.available ?? false,'), isTrue);
    });

    test('§27 destination 그대로 — 연체여도 같은 화면', () {
      expect(rows.contains("tab: 0, sheetTitle: '이체 대기'"), isTrue);
      expect(rows.contains('showAllOutstanding: true'), isTrue);
      expect(rows.contains("secondaryLabel: '지급일 확인 필요'"), isTrue);
      expect(rows.contains('secondaryCountPerBiz: missingMap'), isTrue);
      // 연체 전용 분기가 없다
      expect(rows.contains('overdueOnly'), isFalse);
    });

    test('onTap의 available 가드 유지', () {
      expect(rows.contains('if (!w.available) { _showCanonicalError(context); return; }'),
          isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §15~18 / §28 회귀
  // ───────────────────────────────────────────────────────────
  group('이전 Phase 회귀', () {
    test('§15 TODAY → TASK → NEXT 유지', () {
      // [HOME-V2-08D.2] 섹션 조립이 _buildSections로 옮겨졌다 — 순서는 그대로.
      final b = _bodyOf(home, 'Widget build(') +
          _bodyOf(home, 'List<Widget> _buildSections(');
      final today = b.indexOf('_buildTodayOps(');
      final task = b.indexOf('_buildActionDashboard(');
      final next = b.indexOf('_buildFutureStaffing(');
      expect(today, lessThan(task));
      expect(task, lessThan(next));
    });

    test('§16 처리할 일 섹션 위치는 연체와 무관하게 고정', () {
      // [HOME-V2-08D.2] 섹션 조립이 _buildSections로 옮겨졌다 — 순서는 그대로.
      final b = _bodyOf(home, 'Widget build(') +
          _bodyOf(home, 'List<Widget> _buildSections(');
      // [HOME-V2-08D.2] 섹션에 렌더 조건이 붙었지만 그것은 보이는지 여부이고,
      //   위치는 여전히 정적이다. 연체가 배치에 영향을 주지 않는 것이 요지다.
      final seg = b.substring(
          b.indexOf('_buildTodayOps('), b.indexOf('_buildFutureStaffing('));
      expect(seg.contains('overdue'), isFalse);
      expect(seg.contains('sort'), isFalse);
      expect(seg.contains('_showTaskSection(hero, hasRows, hasHealthNotice)'),
          isTrue);
    });

    test('§9 다른 8행의 source·destination 불변', () {
      for (final sec in [
        'cs?.actions.resignRequest', 'cs?.actions.approval', 'cs?.actions.unclosed',
        'cs?.actions.wageChangeRequest', 'cs?.actions.settlementRequest',
        'cs?.actions.scheduleChangeRequest', 'cs?.actions.unsentContract',
      ]) {
        expect(rows.contains(sec), isTrue, reason: sec);
      }
      expect(rows.contains('SupportReviewQueueScreen.route('), isTrue);
      expect(rows.contains('UnclosedActionQueueScreen.route()'), isTrue);
      expect('_toPayrollTabDrilldown('.allMatches(rows).length, 3);
      expect(rows.contains('initialFilter: (approval?.overdueCount ?? 0) > 0'), isTrue);
    });

    test('§18 Functions를 건드리지 않았다', () {
      final cf = _src('functions/src/index.ts');
      expect(cf.contains('const nonPayable = (st === "NO_SHOW" || st === "absent") && fw === 0;'),
          isTrue);
      expect(cf.contains('if (ms < todayMs) overdue++;'), isTrue);
      expect(cf.contains('.select("userId", "paymentDueDate", "status", "finalWage")'),
          isTrue);
    });

    test('§17 로더가 늘지 않았다', () {
      final loaders = RegExp(r'Future<void> (_load[A-Za-z]*)\(')
          .allMatches(raw)
          .map((m) => m.group(1))
          .toSet();
      expect(loaders, {
        '_loadApprovedBusinessStatus', '_loadCanonicalSummary',
        '_loadPostingReadiness', '_loadStaffingReadiness', '_loadTodayAttendance',
      });
    });

    test('AH-V2-05A dead loader 재도입 없음', () {
      for (final sym in [
        '_loadSummaryCounts', '_summaryActiveTO', 'getTOsByBusiness',
      ]) {
        expect(home.contains(sym), isFalse, reason: sym);
      }
    });

    test('AH-V2-03/04 계약 유지', () {
      expect(home.contains('hasUsableData'), isTrue);
      expect(home.contains(r"'근태 확인 $needsAttention건'"), isTrue);
      expect(home.contains('AttendanceReviewHelper.requiresReviewNow('), isTrue);
      expect(home.contains('_isMultiBusinessScope'), isTrue);
    });

    // [AH-V2-05C 갱신] Home의 elevation은 05C에서 전부 제거됐다.
    test('visual 미변경 — Home은 flat surface', () {
      expect('BoxShadow'.allMatches(home).length, 0);
    });
  });
}
