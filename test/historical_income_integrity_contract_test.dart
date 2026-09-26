// [.6-P2] 과거 수입 이력 계약.
//
//   지키는 문장은 둘이다.
//
//     실제로 일한 사실은 지금의 지원서 상태가 지우지 못한다.
//     모르는 것과 없는 것을 같은 화면으로 그리지 않는다.
//
//   줄 선택 규칙은 Dart 로 재구현해 경계를 직접 고정하고(순수 함수),
//   화면 배선은 소스 문자열로 고정한다. 둘 다 없으면 한쪽만 고쳐도 통과한다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _fnOf(String src, String name, int chars) {
  final i = src.indexOf(name);
  expect(i, greaterThan(-1), reason: '$name 을 찾지 못했다');
  final e = (i + chars) > src.length ? src.length : i + chars;
  return src.substring(i, e);
}

// ─────────────────────────────────────────────────────────────
// 줄 선택 — 화면 _incomeRows 와 같은 규칙
// ─────────────────────────────────────────────────────────────

/// 서버 ACTUAL_WORK_STATUSES 와 같은 집합.
const actualWorkStatuses = {'present', 'late', 'early_leave'};

class App {
  const App(this.id, this.status, this.month);
  final String id;
  final String status;
  final int month;
}

class Att {
  const Att(this.applicationId, this.status, this.month, this.day);
  final String applicationId;
  final String status;
  final int month;
  final int day;
}

class Row {
  const Row(this.key, this.hasApp, this.historical);
  final String key;
  final bool hasApp;
  final bool historical;

  @override
  bool operator ==(Object o) =>
      o is Row && o.key == key && o.hasApp == hasApp &&
      o.historical == historical;

  @override
  int get hashCode => Object.hash(key, hasApp, historical);

  @override
  String toString() => '$key(app=$hasApp,hist=$historical)';
}

const confirmedStatuses = {'CONFIRMED', 'CONTRACT_PENDING'};
const pendingStatus = 'PENDING';

/// 화면이 그리는 줄 집합. 지원서 상태는 **앞으로의 약속**에만 쓰인다.
List<Row> incomeRows(List<App> apps, List<Att> atts, int month) {
  final rows = <Row>[];
  final seen = <String>{};

  // 1) 지금 유효한 약속
  for (final a in apps) {
    if (a.month != month) continue;
    if (!confirmedStatuses.contains(a.status) && a.status != pendingStatus) {
      continue;
    }
    rows.add(Row(a.id, true, false));
    seen.add(a.id);
  }

  // 2) 실제로 일한 기록 — 지원서 상태와 무관
  final byApp = <String, Att>{};
  for (final t in atts) {
    if (t.month != month) continue;
    if (!actualWorkStatuses.contains(t.status)) continue;
    if (seen.contains(t.applicationId)) continue;
    final prev = byApp[t.applicationId];
    if (prev == null || t.day < prev.day) byApp[t.applicationId] = t;
  }
  for (final e in byApp.entries) {
    final hasApp = apps.any((a) => a.id == e.key);
    rows.add(Row(e.key, hasApp, true));
  }
  return rows;
}

void main() {
  late String screen;
  late String cf;

  setUpAll(() {
    screen = _codeOf(
        File('lib/screens/user/income_detail_screen.dart').readAsStringSync());
    cf = _codeOf(File('functions/src/index.ts').readAsStringSync());
  });

  // ───────────────────────────────────────────────────────────
  group('P2-1x 과거 근무는 지원서 상태가 지우지 못한다 (§13)', () {
    test('1 실근무 + 유효 지원서 → 줄이 보인다', () {
      final r = incomeRows(
        const [App('a1', 'CONFIRMED', 9)],
        const [Att('a1', 'present', 9, 3)],
        9,
      );
      expect(r, [const Row('a1', true, false)]);
    });

    test('2 같은 근태 + 지원서 CANCELED → 줄이 그대로 보인다', () {
      final r = incomeRows(
        const [App('a1', 'CANCELED', 9)],
        const [Att('a1', 'present', 9, 3)],
        9,
      );
      expect(r, [const Row('a1', true, true)],
          reason: '일한 사실은 관계가 끝나도 남는다');
    });

    test('2b 지원서가 이전 달로 시작한 장기라도 근무한 달에 보인다', () {
      // 장기 지원서는 workDate 가 시작일이라 이 달의 _monthApps 에 없다.
      //   그래도 이 달에 일했으면 줄이 서야 한다.
      final r = incomeRows(
        const [App('a1', 'CANCELED', 6)],
        const [Att('a1', 'late', 9, 12)],
        9,
      );
      expect(r, [const Row('a1', true, true)]);
    });

    test('3 NO_SHOW 만 있으면 일반 근무 줄이 아니다', () {
      final r = incomeRows(
        const [App('a1', 'CANCELED', 9)],
        const [Att('a1', 'NO_SHOW', 9, 3)],
        9,
      );
      expect(r, isEmpty);
    });

    test('4 결근만 있으면 일반 근무 줄이 아니다', () {
      final r = incomeRows(
        const [App('a1', 'CANCELED', 9)],
        const [Att('a1', 'absent', 9, 3)],
        9,
      );
      expect(r, isEmpty);
    });

    test('5 지원서가 없어도 실근무는 조용히 사라지지 않는다', () {
      final r = incomeRows(
        const [],
        const [Att('gone', 'present', 9, 7)],
        9,
      );
      expect(r, [const Row('gone', false, true)],
          reason: '지원서 조회 실패·200건 밖 이탈이 근무를 지우면 안 된다');
    });

    test('5b 조퇴도 실근무다 — 서버 canonical 표기를 쓴다', () {
      final r = incomeRows(
        const [App('a1', 'CANCELED', 9)],
        const [Att('a1', 'early_leave', 9, 3)],
        9,
      );
      expect(r, [const Row('a1', true, true)]);
      expect(actualWorkStatuses.contains('early_leave'), isTrue);
    });

    test('중복 없음 — 유효 지원서가 근태도 가지면 한 줄이다', () {
      final r = incomeRows(
        const [App('a1', 'CONFIRMED', 9)],
        const [Att('a1', 'present', 9, 3), Att('a1', 'present', 9, 4)],
        9,
      );
      expect(r.length, 1, reason: '장기 달-한-줄 구조를 바꾸지 않는다');
    });

    test('같은 지원서의 여러 근무일도 한 줄로 묶인다', () {
      final r = incomeRows(
        const [App('a1', 'CANCELED', 9)],
        const [Att('a1', 'present', 9, 20), Att('a1', 'present', 9, 5)],
        9,
      );
      expect(r.length, 1, reason: '날짜별로 펼치는 것은 이번 범위가 아니다');
    });

    test('다른 달 근무는 이 달 줄이 아니다', () {
      final r = incomeRows(
        const [App('a1', 'CANCELED', 9)],
        const [Att('a1', 'present', 8, 3)],
        9,
      );
      expect(r, isEmpty);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('P2-2x 월 합계 (§7)', () {
    test('7 합계는 근태에서 나오므로 종료 전후가 같다', () {
      // getConfirmedIncome 은 attendance 만 본다 — 지원서 상태를 보지 않는다.
      final helper = _codeOf(
          File('lib/utils/calendar_helper.dart').readAsStringSync());
      final f = _fnOf(helper, 'static int getConfirmedIncome(', 700);
      expect(f.contains('attendances.where'), isTrue);
      expect(f.contains('app.status'), isFalse,
          reason: '합계가 지원서 상태를 보면 종료로 금액이 사라진다');
      expect(f.contains("att.wageStatus == 'confirmed'"), isTrue);
    });

    test('7b 줄 합계 == 월 합계 라는 불변식을 만들지 않는다', () {
      // 장기는 달에 한 줄이므로 줄에 찍힌 금액의 합이 월 합계와 다를 수 있다.
      //   화면이 둘을 같다고 주장하는 코드가 없어야 한다.
      expect(screen.contains('_wageCompleted =='), isFalse);
      expect(screen.contains('assert(') && screen.contains('_wageCompleted'),
          isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('P2-3x 스냅샷 (§6)', () {
    test('6 과거 줄이 공고를 다시 읽지 않는다', () {
      for (final forbidden in <String>[
        "collection('tos')", 'TOModel', 'getTOById', 'posting',
      ]) {
        expect(screen.contains(forbidden), isFalse, reason: forbidden);
      }
    });

    test('6b 금액·상태는 근태 스냅샷에서 온다', () {
      final f = _fnOf(screen, 'Widget _buildWorkRecord(', 2600);
      expect(f.contains('att.finalWage'), isTrue);
      expect(f.contains('att.wageStatus == AttendanceModel.wageTransferred'),
          isTrue);
    });

    test('6c 서버 근태 조회가 지원서를 조인하지 않는다', () {
      final f = _fnOf(cf, 'export const getMyMonthlyAttendances', 1600);
      expect(f.contains('.where("userId", "==", uid)'), isTrue);
      expect(f.contains('applications'), isFalse,
          reason: '서버가 지원서로 거르면 클라이언트를 고쳐도 소용없다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('P2-4x ERROR != EMPTY (§11)', () {
    test('8 성공 + 0건 → 없다고 말한다', () {
      expect(screen.contains("'아직 이번 달 수입이 없어요'"), isTrue);
      // 그 문구는 실패가 아닌 갈래에만 있어야 한다.
      final i = screen.indexOf("'아직 이번 달 수입이 없어요'");
      final before = screen.substring(0, i);
      final lastEmptyGate = before.lastIndexOf('_incomeRows.isEmpty');
      final lastFailGate = before.lastIndexOf('_loadFailed && _incomeRows.isEmpty');
      expect(lastEmptyGate, greaterThan(lastFailGate),
          reason: '실패 갈래가 빈 문구로 떨어지면 안 된다');
    });

    test('9 실패 + 0건 → 오류 상태와 재시도', () {
      expect(screen.contains('_loadFailed && _incomeRows.isEmpty'), isTrue);
      expect(screen.contains('_buildLoadErrorState('), isTrue);
      final f = _fnOf(screen, 'Widget _buildLoadErrorState(', 1200);
      expect(f.contains('불러오지 못했'), isTrue);
      expect(f.contains('수입이 없는 것이 아니라'), isTrue);
      expect(f.contains('onPressed: _isLoading ? null : _loadAll'), isTrue,
          reason: '재시도 경로가 있어야 한다');
      expect(f.contains('수입이 없어요'), isFalse);
    });

    test('10 이전 데이터가 있으면 유지하고 오류를 표시한다', () {
      expect(screen.contains('if (_loadFailed) _buildStaleBanner(s)'), isTrue);
      final f = _fnOf(screen, 'Widget _buildStaleBanner(', 1200);
      expect(f.contains('마지막으로 확인된 내역'), isTrue);
      expect(f.contains('_loadAll'), isTrue);
    });

    test('10b 금액도 모를 때는 0원이라고 말하지 않는다', () {
      expect(screen.contains("_loadFailed ? '확인 불가'"), isTrue);
    });

    test('10c 리더가 실패를 빈 목록으로 바꾸지 않는다', () {
      final att = _codeOf(File(
          'lib/services/firestore/attendance_firestore.dart').readAsStringSync());
      final f = _fnOf(att, 'Future<List<AttendanceModel>> getMyMonthlyAttendances(', 2000);
      expect(f.contains('rethrow'), isTrue,
          reason: '빈 목록을 돌려주면 화면은 실패를 알 수 없다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('P2-5x 화면 배선', () {
    test('줄 선택이 근태 기반이다', () {
      expect(screen.contains('List<_IncomeRow> get _incomeRows'), isTrue);
      final f = _fnOf(screen, 'List<_IncomeRow> get _incomeRows', 1800);
      expect(f.contains('_workedThisMonth'), isTrue);
      expect(f.contains('seenAppIds'), isTrue);
    });

    test('실근무 판정이 서버 canonical 집합과 같다', () {
      final f = _fnOf(screen, 'static bool _isActualWork(', 400);
      expect(f.contains('statusPresent'), isTrue);
      expect(f.contains('statusLate'), isTrue);
      expect(f.contains('statusEarlyLeave'), isTrue);
      expect(f.contains('statusNoShow'), isFalse);
      expect(f.contains('statusAbsent'), isFalse);
      // 서버 쪽 canonical 상수도 같은 세 값이다.
      expect(
        cf.contains(
            'const ACTUAL_WORK_STATUSES = ["present", "late", "early_leave"];'),
        isTrue,
      );
    });

    test('옛 지원서-기반 목록이 남아 있지 않다', () {
      expect(screen.contains('List<ApplicationModel> get _workRecords'), isFalse,
          reason: '지원서 상태로 과거를 거르던 목록이 사라져야 한다');
    });

    test('지원서 없는 줄은 상세를 열지 않고 이름을 지어내지 않는다', () {
      final f = _fnOf(screen, 'Widget _buildWorkRecord(', 3600);
      expect(f.contains('onTap: app == null'), isTrue);
      expect(f.contains("'사업장 정보 없음'"), isTrue);
      expect(f.contains("'근무 기록 · 상세 확인 필요'"), isTrue);
    });
  });
}
