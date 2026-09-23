// [HOME-V2-08D.5] Task truth + data-health 분리
//
// 실기기 SCREEN A에서 확인된 것:
//
//   현재 등록된 공고가 없어요
//
//   처리할 일
//   퇴사 요청                    조회 실패 >
//   이체 대기                         1건 >
//
// 이 관리자는 퇴사 요청을 받은 적이 없다. 그런데도 `퇴사 요청` 행이 존재했고,
// 행의 존재 자체가 "처리할 퇴사 요청이 있다"고 말하고 있었다.
//
// 추가한 계약:
//   Notification ≠ Task
//   Data Error   ≠ Task
//
// ERROR ≠ ZERO는 유지된다. 다만 그 뜻은
//   "조회 실패를 0건이라고 거짓말하지 않는다"
// 이지
//   "조회 실패마다 task row를 만든다"
// 가 아니다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _cfPath = 'functions/src/index.ts';

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
// truth model replica — §18
// ═══════════════════════════════════════════════════════════════

enum Truth { knownZero, knownNonZero, unknown }

/// 서버 section(available, count) → 클라이언트가 믿을 수 있는 상태.
Truth truthOf({required bool available, required int count}) {
  if (!available) return Truth.unknown;
  return count > 0 ? Truth.knownNonZero : Truth.knownZero;
}

/// `add()`의 행 생성 규칙 — KNOWN_NONZERO에서만 행이 된다.
bool makesRow({required bool permitted, required bool available, required int count}) {
  if (!permitted) return false; // 권한 없음 → 목록에서 제외 (에러 아님)
  return truthOf(available: available, count: count) == Truth.knownNonZero;
}

class _Task {
  final String label;
  final bool permitted;
  final bool available;
  final int count;
  const _Task(this.label,
      {this.permitted = true, this.available = true, this.count = 0});
}

List<String> rowsOf(List<_Task> tasks) => tasks
    .where((t) =>
        makesRow(permitted: t.permitted, available: t.available, count: t.count))
    .map((t) => t.label)
    .toList();

/// `_unknownTaskCount` — 권한이 있는 항목 중 확인하지 못한 수.
int unknownCount(List<_Task> tasks, {bool summaryLoaded = true}) {
  if (!summaryLoaded) return 0; // 전체 실패는 별도 상태
  return tasks.where((t) => t.permitted && !t.available).length;
}

/// 섹션이 낼 수 있는 상태.
enum Section { rows, rowsPlusNotice, noticeOnly, reassurance, totalError }

Section sectionOf(List<_Task> tasks, {bool summaryLoaded = true}) {
  if (!summaryLoaded) return Section.totalError;
  final rows = rowsOf(tasks);
  final unknown = unknownCount(tasks);
  if (rows.isNotEmpty) return unknown > 0 ? Section.rowsPlusNotice : Section.rows;
  return unknown > 0 ? Section.noticeOnly : Section.reassurance;
}

void main() {
  final home = _src(_homePath);
  final homeCode = _codeOf(home);
  final make = _bodyOf(home, '_makeActionRows(BuildContext context');
  final makeCode = _codeOf(make);
  final dash = _bodyOf(home, 'Widget _buildActionDashboard(');
  final dashCode = _codeOf(dash);
  final rowWidget = _bodyOf(home, 'Widget _buildActionRowWidget(');
  final unknownFn = _bodyOf(home, 'int _unknownTaskCount(');
  final notice = _bodyOf(home, 'Widget _taskHealthNotice(');
  final gate = _bodyOf(home, 'bool _showTaskSection(');

  /// 9종 canonical inventory — 라벨 / 권한키 / summary source
  const inventory = <List<String>>[
    ['퇴사 요청',      'canManageWorkers',  'actions.resignRequest'],
    ['지원 검토',      'canManageTo',       'actions.approval'],
    ['스케줄 변경 요청', 'canManageWorkers',  'actions.scheduleChangeRequest'],
    ['계약 미발송',     'canManageContract', 'actions.unsentContract'],
    ['마감 필요',      'canManageWage',     'actions.unclosed'],
    ['중간정산 요청',   'canManageWage',     'actions.settlementRequest'],
    ['급여 변경 요청',  'canManageWage',     'actions.wageChangeRequest'],
    ['이체 대기',      'canManageWage',     'actions.unpaidWage'],
    ['계약 확인 필요',  'canManageContract', 'upcoming.expiringContract'],
  ];

  // ═══════════════════════════════════════════════════════════════
  // 01. 실기기 regression — §20, §21
  // ═══════════════════════════════════════════════════════════════
  group('[08D.5-01] SCREEN A regression', () {
    test('01-a 퇴사 0 · 이체 1 · 퇴사 source unavailable → 이체 행만', () {
      final tasks = [
        const _Task('퇴사 요청', available: false, count: 0),
        const _Task('이체 대기', available: true, count: 1),
      ];
      expect(rowsOf(tasks), ['이체 대기']);
      expect(rowsOf(tasks).contains('퇴사 요청'), isFalse,
          reason: '없는 업무를 만들어 보여주지 않는다');
    });

    test('01-b 그 상태에서 section은 rows + notice', () {
      final tasks = [
        const _Task('퇴사 요청', available: false),
        const _Task('이체 대기', count: 1),
      ];
      expect(sectionOf(tasks), Section.rowsPlusNotice);
    });

    test('01-c 전부 성공이면 notice가 붙지 않는다', () {
      final tasks = [
        const _Task('퇴사 요청', count: 0),
        const _Task('이체 대기', count: 1),
      ];
      expect(sectionOf(tasks), Section.rows);
    });

    test('01-d `조회 실패` 칩이 task 표면에서 사라졌다', () {
      // (Home 전체에는 debugPrint 로그 문자열로 남아 있다 — 사용자 표면이 아니다)
      for (final body in [_codeOf(rowWidget), dashCode, makeCode]) {
        expect(body.contains('조회 실패'), isFalse);
      }
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 02. task truth model — §7, §18, §24
  // ═══════════════════════════════════════════════════════════════
  group('[08D.5-02] task truth', () {
    test('02-a 성공 + N > 0 → 행', () {
      expect(makesRow(permitted: true, available: true, count: 2), isTrue);
    });

    test('02-b 성공 + 0 → 행 없음', () {
      expect(makesRow(permitted: true, available: true, count: 0), isFalse);
    });

    test('02-c 조회 실패 → 행 없음', () {
      expect(makesRow(permitted: true, available: false, count: 0), isFalse);
      // count가 붙어 있어도 신뢰할 수 없으므로 행이 되지 않는다
      expect(makesRow(permitted: true, available: false, count: 3), isFalse);
    });

    test('02-d 권한 없음 → 행 없음 (에러 아님)', () {
      expect(makesRow(permitted: false, available: true, count: 5), isFalse);
      expect(makesRow(permitted: false, available: false, count: 0), isFalse);
    });

    test('02-e 세 상태가 실제로 구분된다', () {
      expect(truthOf(available: true, count: 3), Truth.knownNonZero);
      expect(truthOf(available: true, count: 0), Truth.knownZero);
      expect(truthOf(available: false, count: 0), Truth.unknown);
    });

    test('02-f 행은 KNOWN_NONZERO에서만 생긴다', () {
      for (final t in Truth.values) {
        final makes = t == Truth.knownNonZero;
        expect(
          makesRow(
              permitted: true,
              available: t != Truth.unknown,
              count: t == Truth.knownNonZero ? 1 : 0),
          makes,
          reason: '$t',
        );
      }
    });

    test('02-g 구현의 게이트가 !available를 포함한다', () {
      expect(makeCode, contains('if (!available || count == 0) return;'));
      expect(makeCode.contains('if (available && count == 0) return;'), isFalse,
          reason: '옛 게이트는 !available을 통과시켰다');
    });

    test('02-h 행 record에 available이 남아 있지 않다', () {
      // widget이 available을 읽을 수 있으면 `조회 실패` 행이 다시 생길 수 있다
      expect(rowWidget.contains('item.available'), isFalse);
      expect(_flat(makeCode),
          contains('color: color, count: count, onTap: onTap)'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 03. data-health model — §3, §8, §9, §13, §14
  // ═══════════════════════════════════════════════════════════════
  group('[08D.5-03] data health', () {
    test('03-a unknown + known row 0 → 안심 문구 금지', () {
      final tasks = [
        const _Task('퇴사 요청', available: false),
        const _Task('이체 대기', count: 0),
      ];
      expect(sectionOf(tasks), Section.noticeOnly);
      expect(sectionOf(tasks), isNot(Section.reassurance));
    });

    test('03-b 전부 성공 + 전부 0 → 기존 안심 문구', () {
      final tasks = [
        const _Task('퇴사 요청', count: 0),
        const _Task('이체 대기', count: 0),
      ];
      expect(sectionOf(tasks), Section.reassurance);
    });

    test('03-c summary 전체 실패 → 안심 문구 금지, 전용 상태', () {
      expect(sectionOf(const [], summaryLoaded: false), Section.totalError);
    });

    test('03-d 권한 없음은 unknown으로 세지 않는다', () {
      final tasks = [
        const _Task('퇴사 요청', permitted: false, available: false),
        const _Task('이체 대기', count: 1),
      ];
      expect(unknownCount(tasks), 0);
      expect(sectionOf(tasks), Section.rows);
    });

    test('03-e notice가 업무 이름을 말하지 않는다 (§9)', () {
      final n = _codeOf(notice);
      expect(n, contains("'일부 업무 상태를 확인하지 못했어요'"));
      expect(n, contains("'처리할 업무 상태를 확인하지 못했어요'"));
      for (final label in inventory.map((e) => e.first)) {
        expect(n.contains(label), isFalse, reason: '$label 을 암시하면 안 된다');
      }
    });

    test('03-f 전체 실패와 일부 실패가 다른 문구를 쓴다', () {
      expect(_codeOf(notice), contains('required bool total'));
      expect(_flat(dashCode), contains('final summaryFailed = cs == null'));
      expect(_flat(dashCode), contains('_taskHealthNotice(s, total: summaryFailed)'));
    });

    test('03-g 안심 문구 조건에 notice 부재가 들어간다', () {
      expect(_flat(dashCode),
          contains('final showReassurance = rows.isEmpty && !showNotice'));
    });

    test('03-h retry가 기존 로더를 쓴다 — 새 API 없음 (§10)', () {
      expect(_codeOf(notice), contains('_loadCanonicalSummary()'));
      expect(_codeOf(notice).contains('httpsCallable'), isFalse);
    });

    test('03-i notice는 기존 error surface를 재사용한다 (§8)', () {
      expect(_codeOf(notice), contains('_todayOpsErrorRow(s,'));
    });

    test('03-j data-health가 _makeActionRows 밖에 있다 (§19)', () {
      expect(makeCode.contains('_taskHealthNotice'), isFalse);
      expect(makeCode.contains('unknown'), isFalse);
      expect(home, contains('int _unknownTaskCount('));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 04. 9종 producer inventory — §5, §24
  // ═══════════════════════════════════════════════════════════════
  group('[08D.5-04] 9종 producer semantics', () {
    test('04-a 9종 라벨·권한·source가 그대로다', () {
      for (final row in inventory) {
        final label = row[0];
        final perm = row[1];
        final source = row[2];
        expect(makeCode.contains("label: '$label'"), isTrue, reason: label);
        expect(makeCode.contains(perm), isTrue, reason: '$label → $perm');
        expect(makeCode.contains('cs?.$source'), isTrue,
            reason: '$label → $source');
      }
      expect("label: '".allMatches(makeCode).length, 9);
    });

    test('04-b 9종 전부 available을 add()에 넘긴다', () {
      expect(RegExp(r'available: ').allMatches(makeCode).length, 9);
      // 기본값은 false — 못 받은 값을 성공으로 읽지 않는다
      expect(RegExp(r'\?\.available \?\? false').allMatches(makeCode).length, 9);
    });

    test('04-c _unknownTaskCount가 9종 전부를 같은 권한으로 센다', () {
      final u = _codeOf(unknownFn);
      for (final row in inventory) {
        final source = row[2].split('.').last;
        expect(u.contains('$source.available'), isTrue, reason: source);
      }
      expect(RegExp(r'chk\(permitted:').allMatches(u).length, 9);
    });

    test('04-d _unknownTaskCount의 권한 게이트가 _makeActionRows와 같다', () {
      final u = _codeOf(unknownFn);
      for (final perm in [
        'canManageWorkers', 'canManageTo', 'canManageContract', 'canManageWage',
      ]) {
        expect(u.contains('_verified(up, (p) => p.$perm)'), isTrue,
            reason: perm);
      }
    });

    test('04-e 전체 실패는 _unknownTaskCount가 세지 않는다', () {
      expect(_codeOf(unknownFn), contains('if (cs == null) return 0;'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 05. 서버 available semantics — §6, §16
  // ═══════════════════════════════════════════════════════════════
  group('[08D.5-05] available semantics', () {
    final cf = _src(_cfPath);

    test('05-a available은 두 가지 의미를 겸한다 — 단독으로 오류를 주장할 수 없다', () {
      // permCount == 0(권한 없음)과 successCount < permCount(쿼리 실패)가
      // 같은 false로 내려온다
      expect(cf, contains('available: permCount > 0 && successCount === permCount'));
    });

    test('05-b 그래서 클라이언트가 권한 게이트를 먼저 건다', () {
      // [CROSS-DOMAIN-R5.1F.5] isSub 분기는 _verified 안으로 들어갔다 —
      //   소유자 판정과 신선도 판정을 한 자리에서 한다.
      expect(makeCode, contains('_verified(up, (p) => p.'));
      expect(_codeOf(unknownFn), contains('_verified(up, (p) => p.'));
    });

    test('05-c 사업장 0개는 오류가 아니라 정상 0이다 (FP-02)', () {
      expect(cf, contains('const emptySimple = {available: true, count: 0,'));
    });

    test('05-d 서버는 실패를 0으로 합산하지 않는다 (ERROR≠ZERO 유지)', () {
      expect(cf, contains('if (v !== undefined) {'));
      expect(cf, contains('Promise.allSettled'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 06. gate — §12, §13
  // ═══════════════════════════════════════════════════════════════
  group('[08D.5-06] section gate', () {
    test('06-a unknown이면 lifecycle Hero에서도 섹션을 숨기지 않는다', () {
      final g = _codeOf(gate);
      expect(g, contains('if (hasHealthNotice) return true;'));
      final noticeAt = g.indexOf('hasHealthNotice');
      final lifecycleAt = g.indexOf('_isLifecycleHero');
      expect(noticeAt, lessThan(lifecycleAt),
          reason: 'lifecycle 숨김보다 먼저 판단해야 한다');
    });

    test('06-b 호출부가 unknown을 함께 넘긴다', () {
      final sec = _codeOf(_bodyOf(home, 'List<Widget> _buildSections('));
      expect(sec, contains('_showTaskSection(hero, hasRows, hasHealthNotice)'));
      expect(sec, contains('cs == null || _unknownTaskCount(up, cs) > 0'));
    });

    test('06-c posting lifecycle과 독립이라는 계약은 그대로다', () {
      final g = _codeOf(gate);
      expect(g.contains('publishedPostingCount'), isFalse);
      expect(g.contains('hasDraftPosting'), isFalse);
      expect(g, contains('if (hasRows) return true;'));
    });

    test('06-d 로딩 중에는 여전히 섹션을 낸다', () {
      expect(_codeOf(gate), contains('if (_canonicalSummaryLoading) return true;'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 07. 무회귀 — §18, §22
  // ═══════════════════════════════════════════════════════════════
  group('[08D.5-07] 무회귀', () {
    test('07-a 순서·재정렬 계약 유지', () {
      const order = [
        '퇴사 요청', '지원 검토', '스케줄 변경 요청', '계약 미발송', '마감 필요',
        '중간정산 요청', '급여 변경 요청', '이체 대기', '계약 확인 필요',
      ];
      var prev = -1;
      for (final label in order) {
        final at = makeCode.indexOf("label: '$label'");
        expect(at, greaterThan(prev), reason: label);
        prev = at;
      }
      expect(makeCode.contains('.sort('), isFalse);
      expect(makeCode, contains('atIndex: wageOverdue ? overdueWageSlot : null,'));
    });

    test('07-b 08D.4 task visual이 그대로다 (§22)', () {
      final flat = _flat(_codeOf(rowWidget));
      expect(flat, contains('Icon(item.icon, size: 18 * s, color: AppColors.grey600)'));
      expect(flat, contains('fontSize: 15, fontWeight: FontWeight.w600'));
      expect(flat, contains('Divider(height: 1, color: AppColors.grey100)'));
      expect(RegExp(r'item\.color').allMatches(rowWidget).length, 1);
    });

    test('07-c divider를 건드리지 않았다', () {
      expect(homeCode.contains('AppColors.grey100'), isTrue);
      expect(_codeOf(rowWidget).contains('AppColors.border'), isFalse);
    });

    test('07-d notice가 붙으면 마지막 행에도 divider가 생긴다', () {
      expect(_flat(dashCode),
          contains('isLast: e.key == rows.length - 1 && !showNotice'));
    });

    test('07-e drilldown의 available 방어가 그대로다', () {
      // 행이 안 생겨도 진입 경로는 남아 있으므로 방어를 지운다
      expect(RegExp(r'if \(!sec\.available\) \{ _showCanonicalError\(context\); return; \}')
          .allMatches(makeCode).length, greaterThanOrEqualTo(5));
    });

    test('07-f Hero / Today / Upcoming을 건드리지 않았다', () {
      expect(home, contains('_HeroState _heroStateOf('));
      expect(home, contains('Widget? _buildTodayStaffingSummary('));
      expect(home, contains('Widget _buildFutureShortageRow('));
      final heroBody = _codeOf(_bodyOf(home, 'Widget _buildAdaptiveHero('));
      expect(RegExp(r'ctaLabel:').allMatches(heroBody).length, 4);
    });

    test('07-g 새 read / callable / listener 0', () {
      for (final body in [_codeOf(unknownFn), _codeOf(notice), dashCode]) {
        for (final t in [
          'httpsCallable', '_firestoreService', 'FirebaseFirestore', 'snapshots(',
        ]) {
          expect(body.contains(t), isFalse, reason: t);
        }
      }
      expect(RegExp(r'Future<void> _load\w+\(').allMatches(home).length, 5);
    });

    test('07-h 섹션 제목이 그대로다', () {
      expect(dashCode, contains("_sectionHeader(context, s, '처리할 일')"));
    });
  });
}
