// [HOME-V2-07.1] 좌석 반납 후 Home 인력 현황 신선도
//
// HOME-V2-07 READ에서 확인된 것:
//   · Home `근태 확인` → AttendanceStatusDialog 안에는 NO_SHOW 좌석 반납
//     (_releaseNoshowSeat → releaseNoshowSeat CF) 경로가 함께 있다.
//   · 좌석을 반납하면 slot confirmed가 줄어 staffing shortage가 바뀐다.
//   · 그런데 Home은 _loadTodayAttendance()만 다시 돌렸다. 그래서 같은 카드
//     안에서 `근태 확인`은 갱신되고 바로 옆 `부족`은 낡은 채로 남았고,
//     공고·근무 탭에도 아무 신호가 가지 않았다.
//
// 이것은 근태 mutation이 아니라 staffing mutation이다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _dialogPath =
    'lib/screens/business_admin/dialogs/attendance_status_dialog.dart';

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
// caller replica — dialog 결과 처리
// ═══════════════════════════════════════════════════════════════

class HomeRefreshLog {
  bool attendance = false;
  bool staffing = false;
  bool notified = false;
  int notifyCount = 0;
}

/// `_openTodayAttendanceDialog`의 결과 처리 재현.
HomeRefreshLog onAttendanceDialogClosed(bool? changed, {bool mounted = true}) {
  final log = HomeRefreshLog();
  if ((changed ?? false) && mounted) {
    log.attendance = true;
    log.staffing = true;
    log.notified = true;
    log.notifyCount++;
  }
  return log;
}

/// self-origin skip 계약 재현 (`_onAdminMutation`).
bool homeRebuildsOnOwnMutation({required String origin}) {
  if (origin == 'home') return false;
  return true;
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // §6 A~D — caller 동작
  // ══════════════════════════════════════════════════════════════
  group('01. dialog 결과 처리', () {
    test('01-a 변경 없음(null) → 아무 reload도 없다', () {
      final log = onAttendanceDialogClosed(null);
      expect(log.attendance, false);
      expect(log.staffing, false);
      expect(log.notified, false);
    });

    test('01-b 변경 없음(false) → 아무 reload도 없다', () {
      final log = onAttendanceDialogClosed(false);
      expect(log.attendance, false);
      expect(log.staffing, false);
      expect(log.notified, false);
    });

    test('01-c 변경 있음 → 근태 재조회', () {
      expect(onAttendanceDialogClosed(true).attendance, true);
    });

    test('01-d 변경 있음 → 인력 현황도 재조회', () {
      expect(onAttendanceDialogClosed(true).staffing, true,
          reason: '좌석 반납이 shortage를 바꾼다');
    });

    test('01-e 변경 있음 → home origin으로 1회만 알린다', () {
      final log = onAttendanceDialogClosed(true);
      expect(log.notified, true);
      expect(log.notifyCount, 1);
    });

    test('01-f unmounted면 아무것도 하지 않는다', () {
      final log = onAttendanceDialogClosed(true, mounted: false);
      expect(log.attendance, false);
      expect(log.staffing, false);
      expect(log.notified, false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §4 §6-D — self-origin
  // ══════════════════════════════════════════════════════════════
  group('02. self-origin 중복 방지', () {
    test('02-a Home이 낸 mutation은 Home을 다시 refresh하지 않는다', () {
      expect(homeRebuildsOnOwnMutation(origin: 'home'), false);
    });

    test('02-b 다른 탭이 낸 mutation은 Home을 refresh한다', () {
      expect(homeRebuildsOnOwnMutation(origin: 'jobs'), true);
      expect(homeRebuildsOnOwnMutation(origin: 'workforce'), true);
    });

    test('02-c Home은 loader 두 개로 이미 갱신됐다 — 전체 refresh 불필요', () {
      final log = onAttendanceDialogClosed(true);
      expect(log.attendance && log.staffing, true);
      expect(homeRebuildsOnOwnMutation(origin: 'home'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 소스 고정
  // ══════════════════════════════════════════════════════════════
  group('03. Home caller 소스', () {
    final home = _src(_homePath);
    final body = _flat(
        _codeOf(_bodyOf(home, 'Future<void> _openTodayAttendanceDialog(')));

    test('03-a 성공 분기에서 세 가지를 모두 한다', () {
      expect(body.contains('if ((changed ?? false) && mounted) {'), true);
      expect(body.contains('unawaited(_loadTodayAttendance());'), true);
      expect(body.contains('unawaited(_loadStaffingReadiness());'), true);
      expect(
        body.contains('WorkforceController.notifyDataChanged( '
            'origin: AdminMutationOrigin.home, );'),
        true,
      );
    });

    test('03-b 성공 분기 밖에는 아무것도 없다 (§7 열기/닫기 read 0)', () {
      final open = body.indexOf('if ((changed ?? false) && mounted) {');
      final before = body.substring(0, open);
      expect(before.contains('_loadStaffingReadiness'), false);
      expect(before.contains('_loadTodayAttendance'), false);
      expect(before.contains('notifyDataChanged'), false);
    });

    test('03-c notifyDataChanged는 이 경로에 1회뿐이다', () {
      expect('notifyDataChanged'.allMatches(body).length, 1);
    });

    test('03-d dialog 인자 계약 무변경', () {
      expect(body.contains('date: today,'), true);
      expect(body.contains('businessIds: businesses.map((b) => b.id).toList(),'),
          true);
      expect(body.contains('businesses: businesses,'), true);
      expect(body.contains('barrierDismissible: false,'), true);
    });

    test('03-e self-origin skip 계약이 그대로다', () {
      final onMut = _codeOf(_bodyOf(home, 'void _onAdminMutation('));
      expect(
        _flat(onMut).contains(
            'if (WorkforceController.lastMutationOrigin == AdminMutationOrigin.home) { return; }'),
        true,
      );
    });
  });

  group('04. 좌석 반납 경로 전제', () {
    final dialog = _src(_dialogPath);

    test('04-a 좌석 반납이 이 다이얼로그 안에 있다', () {
      final body =
          _codeOf(_bodyOf(dialog, 'Future<void> _releaseNoshowSeat('));
      expect(body.contains('releaseNoshowSeat(') , true);
      expect(body.contains('_hasChanges = true;'), true,
          reason: 'dialog가 true를 반환해야 Home이 알 수 있다');
    });

    test('04-b 반납 성공 시에만 변경으로 기록한다', () {
      final body =
          _codeOf(_bodyOf(dialog, 'Future<void> _releaseNoshowSeat('));
      final fail = body.indexOf('if (!success) return;');
      final mark = body.indexOf('_hasChanges = true;');
      expect(fail, greaterThan(-1));
      expect(fail, lessThan(mark));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // §5 §6-E — 범위 / 무회귀
  // ══════════════════════════════════════════════════════════════
  group('05. 무회귀', () {
    final home = _src(_homePath);

    test('05-a 부족 tap 경로의 기존 refresh 계약 유지', () {
      final body = _flat(_codeOf(
          _bodyOf(home, 'Future<void> _navigateToDayApplicantsForDate(')));
      expect(body.contains('unawaited(_loadStaffingReadiness());'), true);
      expect(
        body.contains('WorkforceController.notifyDataChanged( '
            'origin: AdminMutationOrigin.home, );'),
        true,
      );
      expect(body.contains('if ((changed ?? false) && mounted) {'), true);
    });

    test('05-b Today UI를 건드리지 않았다 (§5)', () {
      final ops = _codeOf(_bodyOf(home, 'Widget _buildTodayOps('));
      expect(ops.contains("'오늘 운영'"), true);
      expect(ops.contains('_buildStaffingMetrics('), true);
      expect(ops.contains('_buildAttendanceMetrics('), true);
      // 당일 명단 CTA·Hero를 추가하지 않았다
      expect(ops.contains('당일 명단'), false);
      expect(ops.contains('action:'), false);
    });

    test('05-c 수치 셀 구성 무변경', () {
      final att = _codeOf(_bodyOf(home, 'Widget _buildAttendanceMetrics('));
      expect(att.contains("label: '현재 출근'"), true);
      expect(att.contains("label: '근태 확인'"), true);
      final st = _codeOf(_bodyOf(home, 'Widget _buildStaffingMetrics('));
      for (final label in ["label: '필요'", "label: '확정'", "label: '부족'"]) {
        expect(st.contains(label), true, reason: label);
      }
    });

    test('05-d section name 무변경', () {
      for (final name in ["'오늘 운영'", "'처리할 일'", "'다가오는 인력 부족'"]) {
        expect(home.contains(name), true, reason: name);
      }
    });

    test('05-e Home 초기 로드에 read를 더하지 않았다 (§7)', () {
      final refresh = _codeOf(_bodyOf(home, 'Future<void> _refresh('));
      expect(refresh.contains('_loadCanonicalSummary()'), true);
      expect(refresh.contains('_loadStaffingReadiness()'), true);
      expect(refresh.contains('_loadTodayAttendance()'), true);
      // loader 자체는 늘지 않았다
      final loaders = RegExp(r'Future<void> _load\w+\(')
          .allMatches(_codeOf(home))
          .length;
      expect(loaders, 5,
          reason:
              'canonicalSummary · staffingReadiness · todayAttendance · readiness · businesses');
    });

    test('05-f 새 refresh architecture를 만들지 않았다 (§1)', () {
      final code = _codeOf(home);
      expect(code.contains('typedInvalidation'), false);
      expect(code.contains('MutationKind'), false);
      expect(
        RegExp(r'AdminMutationOrigin\.\w+').allMatches(code).every(
            (m) => m.group(0) == 'AdminMutationOrigin.home'),
        true,
        reason: 'Home은 home origin만 발행한다',
      );
    });
  });
}
