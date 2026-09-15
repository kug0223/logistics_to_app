// [HOME-V2-08D.5.1] `계약 종료 예정` permission truth
//
// 08D.5 Task Truth 감사에서 발견한 결함:
//
//   if (canManageWage) {
//     ...
//     // 이체 대기
//     if (canManageContract) {
//       // 계약 종료 예정      ← 여기 중첩돼 있었다
//     }
//   }
//
// 결과적으로 `canManageWage && canManageContract`를 요구했다. 계약서 권한만
// 가진 SubAdmin은 실제 종료 예정 계약이 있어도 행을 볼 수 없었다.
//
// 08D.5가 고친 것이 "없는 업무를 보여주는" 방향이었다면 이것은 그 반대다:
//   **있는 업무를 감추는** 방향의 task truth 결함.

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
// _makeActionRows replica — 권한 게이트 + 08D.5 task truth
// ═══════════════════════════════════════════════════════════════

/// 9종의 canonical 권한 (라벨 → permission key)
const rowPermission = <String, String>{
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

const canonicalOrder = <String>[
  '퇴사 요청', '지원 검토', '스케줄 변경 요청', '계약 미발송', '마감 필요',
  '중간정산 요청', '급여 변경 요청', '이체 대기', '계약 종료 예정',
];

class Section {
  final bool available;
  final int count;
  const Section({this.available = true, this.count = 0});
}

/// 각 행의 생성 규칙. 권한 → 08D.5 task truth → append.
List<String> buildRows({
  required Set<String> perms,
  Map<String, Section> sections = const {},
  bool wageOverdue = false,
}) {
  final result = <String>[];
  var slot = -1;

  void add(String label, {int? atIndex}) {
    // [08D.5.1] 각 행은 **자기 권한 하나만** 본다
    if (!perms.contains(rowPermission[label])) return;
    final s = sections[label] ?? const Section(available: true, count: 1);
    // [08D.5] KNOWN_NONZERO에서만 행이 된다
    if (!s.available || s.count == 0) return;
    if (atIndex != null) {
      result.insert(atIndex, label);
    } else {
      result.add(label);
    }
  }

  add('퇴사 요청');
  slot = result.length;
  add('지원 검토');
  add('스케줄 변경 요청');
  add('계약 미발송');
  add('마감 필요');
  add('중간정산 요청');
  add('급여 변경 요청');
  add('이체 대기', atIndex: wageOverdue ? slot : null);
  add('계약 종료 예정');
  return result;
}

/// `_unknownTaskCount` — 권한 있는 항목 중 확인하지 못한 수.
int unknownCount({
  required Set<String> perms,
  Map<String, Section> sections = const {},
}) {
  var n = 0;
  for (final label in canonicalOrder) {
    if (!perms.contains(rowPermission[label])) continue;
    final s = sections[label] ?? const Section(available: true, count: 0);
    if (!s.available) n++;
  }
  return n;
}

void main() {
  final home = _src(_homePath);
  final cf = _src(_cfPath);
  final make = _bodyOf(home, '_makeActionRows(BuildContext context');
  final makeCode = _codeOf(make);
  final unknownFn = _codeOf(_bodyOf(home, 'int _unknownTaskCount('));

  // ═══════════════════════════════════════════════════════════════
  // 01. canonical permission proof — §2
  // ═══════════════════════════════════════════════════════════════
  group('[08D.5.1-01] canonical permission', () {
    test('01-a 서버 per-business gate가 canManageContract다', () {
      expect(cf, contains('const canContr = !isSubAdmin || perms["canManageContract"] === true;'));
      expect(cf, contains('canContr ? srvHomeExpiringContract(bizId, todayMs)'));
    });

    test('01-b 서버 집계 permKey가 canManageContract다', () {
      expect(cf,
          contains('expiringContract: aggSimple("canManageContract", (r) => r.expiringContract?.count)'));
    });

    test('01-c 행 onTap 가드가 canManageContract다', () {
      final seg = makeCode.substring(makeCode.indexOf("label: '계약 종료 예정'"));
      expect(seg, contains("if (!up.can((p) => p.canManageContract)) {"));
      expect(seg, contains("ToastHelper.showWarning('계약서 관리 권한이 없습니다.')"));
    });

    test('01-d 같은 도메인 알림도 canManageContract다', () {
      final notif = _src('lib/screens/common/notification_screen.dart');
      final at = notif.indexOf('case NotificationType.contractExpiringReminder:');
      expect(at, isNot(-1));
      expect(notif.substring(at, at + 500),
          contains('requiredPermission: (p) => p.canManageContract'));
    });

    test('01-e 네 곳 어디에도 canManageWage가 없다', () {
      final notif = _src('lib/screens/common/notification_screen.dart');
      final at = notif.indexOf('case NotificationType.contractExpiringReminder:');
      expect(notif.substring(at, at + 500).contains('canManageWage'), isFalse);
      final srv = cf.substring(cf.indexOf('async function srvHomeExpiringContract('));
      expect(srv.substring(0, 800).contains('canManageWage'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 02. root cause 제거 — §3, §4
  // ═══════════════════════════════════════════════════════════════
  group('[08D.5.1-02] nesting 제거', () {
    test('02-a 계약 종료 예정 블록이 canManageWage 밖에 있다', () {
      // block gate(`!isSub ||` 로 시작)만 본다 — onTap 안의 재검증 가드와 구분한다
      const wageGate = 'if (!isSub || up.can((p) => p.canManageWage))';
      const contractGate = 'if (!isSub || up.can((p) => p.canManageContract))';
      final wageGateAt = makeCode.lastIndexOf(wageGate);
      final expiringGateAt = makeCode.lastIndexOf(contractGate);
      final labelAt = makeCode.indexOf("label: '계약 종료 예정'");
      expect(wageGateAt, isNot(-1));
      expect(wageGateAt, lessThan(expiringGateAt));
      expect(expiringGateAt, lessThan(labelAt));
      // 이체 대기 블록이 계약 종료 예정 게이트 전에 닫힌다
      final wageRowAt = makeCode.indexOf("label: '이체 대기'");
      final seg = makeCode.substring(wageRowAt, expiringGateAt);
      expect(seg, contains('\n    }\n'), reason: 'wage if 블록이 먼저 닫혀야 한다');
    });

    test('02-b 두 게이트가 형제 관계다 — 같은 들여쓰기', () {
      final lines = makeCode.split('\n');
      final gateLines =
          lines.where((l) => l.contains('if (!isSub || up.can((p) => p.'));
      expect(gateLines.length, 9);
      for (final l in gateLines) {
        expect(l.length - l.trimLeft().length, 4,
            reason: '모든 task 게이트는 최상위 형제다: "$l"');
      }
    });

    test('02-c 9종 게이트가 정확히 9개다', () {
      expect(RegExp(r'if \(!isSub \|\| up\.can\(').allMatches(makeCode).length, 9);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 03. permission matrix — §7
  // ═══════════════════════════════════════════════════════════════
  group('[08D.5.1-03] permission matrix', () {
    test('03-a contract=true, wage=false, count>0 → 표시', () {
      final r = buildRows(perms: {'canManageContract'});
      expect(r.contains('계약 종료 예정'), isTrue,
          reason: '이것이 이번 Phase가 고친 칸이다');
      expect(r, ['계약 미발송', '계약 종료 예정']);
    });

    test('03-b contract=false, wage=true, count>0 → 미표시', () {
      final r = buildRows(perms: {'canManageWage'});
      expect(r.contains('계약 종료 예정'), isFalse);
      expect(r, ['마감 필요', '중간정산 요청', '급여 변경 요청', '이체 대기']);
    });

    test('03-c contract=true, wage=true, count>0 → 정확히 1개', () {
      final r = buildRows(perms: {'canManageContract', 'canManageWage'});
      expect(r.where((l) => l == '계약 종료 예정').length, 1);
    });

    test('03-d 둘 다 없으면 미표시', () {
      final r = buildRows(perms: {'canManageWorkers'});
      expect(r.contains('계약 종료 예정'), isFalse);
    });

    test('03-e 전권 관리자는 9종 전부', () {
      final r = buildRows(perms: rowPermission.values.toSet());
      expect(r, canonicalOrder);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 04. task truth 유지 — §5
  // ═══════════════════════════════════════════════════════════════
  group('[08D.5.1-04] 계약 종료 예정도 예외가 아니다', () {
    test('04-a count == 0이면 행 없음', () {
      final r = buildRows(
        perms: {'canManageContract'},
        sections: {'계약 종료 예정': const Section(available: true, count: 0)},
      );
      expect(r.contains('계약 종료 예정'), isFalse);
    });

    test('04-b available == false면 named row 없음', () {
      final r = buildRows(
        perms: {'canManageContract'},
        sections: {'계약 종료 예정': const Section(available: false, count: 3)},
      );
      expect(r.contains('계약 종료 예정'), isFalse);
    });

    test('04-c available == false는 data-health로 센다', () {
      expect(
        unknownCount(
          perms: {'canManageContract'},
          sections: {'계약 종료 예정': const Section(available: false)},
        ),
        1,
      );
    });

    test('04-d 권한이 없으면 unknown으로 세지 않는다', () {
      expect(
        unknownCount(
          perms: {'canManageWage'},
          sections: {'계약 종료 예정': const Section(available: false)},
        ),
        0,
        reason: '권한 없음을 장애로 말하면 안 된다',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 05. _unknownTaskCount 정렬 — §6
  // ═══════════════════════════════════════════════════════════════
  group('[08D.5.1-05] 두 곳의 권한이 같다', () {
    test('05-a _unknownTaskCount가 expiringContract를 canContract로 센다', () {
      expect(unknownFn,
          contains('chk(permitted: canContract, available: cs.upcoming.expiringContract.available)'));
    });

    test('05-b canManageWage와 엮이지 않았다', () {
      final at = unknownFn.indexOf('expiringContract');
      final line = unknownFn.substring(
          unknownFn.lastIndexOf('\n', at) + 1, unknownFn.indexOf('\n', at));
      expect(line.contains('canWage'), isFalse);
    });

    test('05-c 9종 권한 배정이 두 곳에서 일치한다', () {
      for (final e in rowPermission.entries) {
        final rowAt = makeCode.indexOf("label: '${e.key}'");
        expect(rowAt, isNot(-1), reason: e.key);
        // 라벨 직전 게이트가 그 권한이어야 한다
        final gateAt = makeCode.lastIndexOf('up.can((p) => p.${e.value})', rowAt);
        expect(gateAt, isNot(-1), reason: '${e.key} → ${e.value}');
      }
      // _unknownTaskCount 쪽 개수
      expect(RegExp(r'chk\(permitted:').allMatches(unknownFn).length, 9);
      expect(RegExp(r'permitted: canContract').allMatches(unknownFn).length, 2,
          reason: '계약 미발송 + 계약 종료 예정');
      expect(RegExp(r'permitted: canWage').allMatches(unknownFn).length, 4,
          reason: '마감·중간정산·급여변경·이체');
      expect(RegExp(r'permitted: canWorkers').allMatches(unknownFn).length, 2);
      expect(RegExp(r'permitted: canTo').allMatches(unknownFn).length, 1);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 06. ordering — §8
  // ═══════════════════════════════════════════════════════════════
  group('[08D.5.1-06] 순서 불변', () {
    test('06-a 소스 라벨 순서가 canonical order 그대로다', () {
      var prev = -1;
      for (final label in canonicalOrder) {
        final at = makeCode.indexOf("label: '$label'");
        expect(at, greaterThan(prev), reason: label);
        prev = at;
      }
    });

    test('06-b 계약 종료 예정은 여전히 마지막에 append된다', () {
      final r = buildRows(perms: rowPermission.values.toSet());
      expect(r.last, '계약 종료 예정');
    });

    test('06-c 연체 승격이 있어도 계약 종료 예정은 마지막', () {
      final r =
          buildRows(perms: rowPermission.values.toSet(), wageOverdue: true);
      expect(r.first, '퇴사 요청');
      expect(r[1], '이체 대기', reason: '퇴사 요청 바로 뒤로 승격');
      expect(r.last, '계약 종료 예정');
    });

    test('06-d 부분 권한에서도 canonical 부분수열', () {
      for (final perms in [
        {'canManageContract'},
        {'canManageContract', 'canManageWage'},
        {'canManageContract', 'canManageWorkers'},
        {'canManageWage', 'canManageTo'},
      ]) {
        final r = buildRows(perms: perms);
        final expected =
            canonicalOrder.where((l) => perms.contains(rowPermission[l])).toList();
        expect(r, expected, reason: perms.toString());
      }
    });

    test('06-e 재정렬 구조가 없다', () {
      expect(makeCode.contains('.sort('), isFalse);
      expect(makeCode, contains('atIndex: wageOverdue ? overdueWageSlot : null,'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 07. 무회귀 — §9, §10, §11
  // ═══════════════════════════════════════════════════════════════
  group('[08D.5.1-07] 무회귀', () {
    test('07-a task 종류·라벨·count·destination 무변경', () {
      expect("label: '".allMatches(makeCode).length, 9);
      final seg = makeCode.substring(makeCode.indexOf("label: '계약 종료 예정'"));
      expect(seg, contains("countStr: '\${expiring?.count ?? 0}명'"));
      expect(seg, contains('ExpiringContractsScreen('));
      // source 바인딩은 라벨 앞줄에 있다
      expect(makeCode, contains('final expiring = cs?.upcoming.expiringContract;'));
    });

    test('07-b scope / businessIds 계약 무변경', () {
      final seg = makeCode.substring(makeCode.indexOf("label: '계약 종료 예정'"));
      expect(seg, contains('sec.byBusiness'));
      expect(seg, contains('await _getBusinesses()'));
      expect(seg.contains('managedBusinessIds'), isFalse);
    });

    test('07-c 08D.5 task truth 게이트 유지', () {
      expect(makeCode, contains('if (!available || count == 0) return;'));
      expect(makeCode.contains('조회 실패'), isFalse);
    });

    test('07-d data-health notice 유지', () {
      final dash = _codeOf(_bodyOf(home, 'Widget _buildActionDashboard('));
      expect(dash, contains('final showNotice = summaryFailed || unknownCount > 0;'));
      expect(dash, contains('_taskHealthNotice(s, total: summaryFailed)'));
    });

    test('07-e Hero / Today / Upcoming 무변경', () {
      expect(home, contains('_HeroState _heroStateOf('));
      expect(home, contains('Widget? _buildTodayStaffingSummary('));
      expect(home, contains('Widget _buildFutureShortageRow('));
      final hero = _codeOf(_bodyOf(home, 'Widget _buildAdaptiveHero('));
      expect(RegExp(r'ctaLabel:').allMatches(hero).length, 4);
    });

    test('07-f section gate 무변경', () {
      final gate = _codeOf(_bodyOf(home, 'bool _showTaskSection('));
      expect(gate, contains('if (hasHealthNotice) return true;'));
      expect(_codeOf(_bodyOf(home, 'bool get _showTodaySection')),
          contains('_hasTodayRoster == true'));
    });

    test('07-g read / callable / listener 0, Functions 무변경', () {
      expect(RegExp(r'Future<void> _load\w+\(').allMatches(home).length, 5);
      expect(makeCode.contains('httpsCallable'), isFalse);
      // 08D.6의 index correction도 그대로다
      final idx = _src('firestore.indexes.json');
      expect(idx, contains('"fieldPath": "resignRequestedAt", "order": "ASCENDING"'));
    });

    test('07-h visual 무변경', () {
      final w = _codeOf(_bodyOf(home, 'Widget _buildActionRowWidget('));
      expect(w, contains('color: AppColors.grey600'));
      expect(w, contains('Divider(height: 1, color: AppColors.grey100)'));
    });
  });
}
