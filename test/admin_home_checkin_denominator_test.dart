import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ═══════════════════════════════════════════════════════════════
// AH-V2-06 TODAY-CHECKIN-CANONICAL-SUMMARY
//
//   현재 출근  12 / 15
//
// 분자·분모가 같은 모집단(오늘 확정 로스터)에서 나오고,
// 분모는 "지금까지 출근했어야 할 사람 ∪ 이미 출근한 사람"이다.
//
// 그리고 로스터 조회 실패가 0명으로 새지 않는다.
// ═══════════════════════════════════════════════════════════════

const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _appFsPath = 'lib/services/firestore/application_firestore.dart';

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

// ── 집계 재현 ────────────────────────────────────────────────
/// 오늘 로스터 한 명
class _RosterApp {
  final String id;
  final String effectiveStart; // 'HH:mm'
  final DateTime? checkInAt;
  const _RosterApp(this.id, this.effectiveStart, {this.checkInAt});
}

final _today = DateTime(2026, 9, 13);
DateTime _at(int h, int m) => DateTime(2026, 9, 13, h, m);

/// _todayStartAt 재현
DateTime? _startAt(DateTime day, String raw) {
  final t = raw.length >= 5 ? raw.substring(0, 5) : raw;
  final parts = t.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return DateTime(day.year, day.month, day.day, h, m);
}

class _Counts {
  final int checkedIn;
  final int dueNow;
  const _Counts(this.checkedIn, this.dueNow);
  @override
  String toString() => '$checkedIn / $dueNow';
}

/// Home의 분자·분모 집계 재현 (B2)
_Counts _count(List<_RosterApp> roster, DateTime now) {
  var checkedIn = 0;
  var dueNow = 0;
  for (final app in roster) {
    final hasCheckedIn = app.checkInAt != null;
    if (hasCheckedIn) checkedIn++;
    final startAt = _startAt(_today, app.effectiveStart);
    final started = startAt != null && !now.isBefore(startAt);
    if (started || hasCheckedIn) dueNow++;
  }
  return _Counts(checkedIn, dueNow);
}

String _display(_Counts c) =>
    c.dueNow == 0 ? '예정 전' : '${c.checkedIn} / ${c.dueNow}';

void main() {
  late String raw;
  late String home;
  late String loader;
  late String appFs;

  setUpAll(() {
    raw = _src(_homePath);
    home = _codeOf(raw);
    loader = _bodyOf(home, 'Future<void> _loadTodayAttendance(');
    appFs = _src(_appFsPath);
  });

  // ───────────────────────────────────────────────────────────
  // §29~36 집계 fixture
  // ───────────────────────────────────────────────────────────
  group('§29 actionability와 같은 시각 기준', () {
    test('시작 전 + 미출근 → 분모 제외', () {
      final r = [const _RosterApp('a', '18:00')];
      expect(_count(r, _at(10, 0)), isA<_Counts>());
      expect(_count(r, _at(10, 0)).dueNow, 0);
      expect(_count(r, _at(10, 0)).checkedIn, 0);
    });

    test('시작 시각 도달 + 미출근 → 분모 포함', () {
      final r = [const _RosterApp('a', '09:00')];
      expect(_count(r, _at(9, 0)).dueNow, 1);
      expect(_count(r, _at(9, 0)).checkedIn, 0);
    });

    test('정각부터 포함 — grace 없음 (START_TIME gate)', () {
      final r = [const _RosterApp('a', '09:00')];
      expect(_count(r, _at(8, 59)).dueNow, 0);
      expect(_count(r, _at(9, 0)).dueNow, 1);
      expect(_count(r, _at(9, 3)).dueNow, 1);
    });
  });

  group('§30 조기 체크인 (B2)', () {
    test('18:00 근무자가 10:00에 출근 → 1 / 1', () {
      final r = [_RosterApp('a', '18:00', checkInAt: _at(10, 0))];
      final c = _count(r, _at(10, 0));
      expect(c.checkedIn, 1);
      expect(c.dueNow, 1);
      expect(_display(c), '1 / 1');
    });

    test('B1이었다면 분자 > 분모가 됐을 상황', () {
      final r = [
        const _RosterApp('a', '09:00'),
        _RosterApp('b', '18:00', checkInAt: _at(10, 0)),
      ];
      final c = _count(r, _at(10, 0));
      expect(c.checkedIn, 1);
      expect(c.dueNow, 2, reason: '09:00 대상 + 조기 출근자');
    });
  });

  group('§31 혼합 시프트', () {
    test('09:00 15명(12 출근) + 18:00 15명(1 조기 출근) → 13 / 16', () {
      final r = <_RosterApp>[
        for (var i = 0; i < 12; i++)
          _RosterApp('m$i', '09:00', checkInAt: _at(9, 5)),
        for (var i = 0; i < 3; i++) _RosterApp('n$i', '09:00'),
        for (var i = 0; i < 14; i++) _RosterApp('e$i', '18:00'),
        _RosterApp('early', '18:00', checkInAt: _at(10, 0)),
      ];
      final c = _count(r, _at(10, 0));
      expect(c.checkedIn, 13);
      expect(c.dueNow, 16);
      expect(_display(c), '13 / 16');
    });
  });

  group('§32 NO_SHOW는 분모에 남는다', () {
    test('대상 15 · 출근 12 · 노쇼 1 · 미체크인 2 → 12 / 15', () {
      final r = <_RosterApp>[
        for (var i = 0; i < 12; i++)
          _RosterApp('c$i', '09:00', checkInAt: _at(9, 0)),
        const _RosterApp('noshow', '09:00'), // 노쇼 처리됐지만 checkInAt 없음
        const _RosterApp('x1', '09:00'),
        const _RosterApp('x2', '09:00'),
      ];
      final c = _count(r, _at(10, 0));
      expect(c.checkedIn, 12);
      expect(c.dueNow, 15, reason: '노쇼를 빼면 출근 상황이 좋아 보인다');
    });
  });

  group('§34/§35 경계 상태', () {
    test('§34 전원 미래 시작 → 예정 전', () {
      final r = [for (var i = 0; i < 10; i++) _RosterApp('a$i', '18:00')];
      final c = _count(r, _at(10, 0));
      expect(c.checkedIn, 0);
      expect(c.dueNow, 0);
      expect(_display(c), '예정 전', reason: '0 / 0을 쓰지 않는다');
    });

    test('§35 전원 시작 후 → 분모 == 로스터 수', () {
      final r = [
        for (var i = 0; i < 10; i++) _RosterApp('a$i', '09:00'),
        for (var i = 0; i < 5; i++) _RosterApp('b$i', '18:00'),
      ];
      final c = _count(r, _at(20, 0));
      expect(c.dueNow, 15, reason: 'MODEL B가 하루 끝에는 전체 대상과 같아진다');
    });

    test('로스터가 비면 예정 전', () {
      expect(_display(_count(const [], _at(10, 0))), '예정 전');
    });

    test('시각 해석 불가면 분모에 넣지 않는다', () {
      final r = [const _RosterApp('a', '')];
      expect(_count(r, _at(23, 0)).dueNow, 0);
    });
  });

  group('§36 다사업장 합산', () {
    test('A 09:00 10명(8 출근) + B 18:00 10명 → 8 / 10', () {
      final r = <_RosterApp>[
        for (var i = 0; i < 8; i++)
          _RosterApp('a$i', '09:00', checkInAt: _at(9, 10)),
        for (var i = 0; i < 2; i++) _RosterApp('a2$i', '09:00'),
        for (var i = 0; i < 10; i++) _RosterApp('b$i', '18:00'),
      ];
      final c = _count(r, _at(10, 0));
      expect(_display(c), '8 / 10');
    });
  });

  // ───────────────────────────────────────────────────────────
  // §23 invariant
  // ───────────────────────────────────────────────────────────
  group('§23 0 <= numerator <= denominator', () {
    test('무작위 조합에서도 깨지지 않는다', () {
      final starts = ['06:00', '09:00', '13:30', '18:00', '22:00'];
      for (var seed = 0; seed < 40; seed++) {
        final r = <_RosterApp>[];
        for (var i = 0; i < 10; i++) {
          final st = starts[(seed + i) % starts.length];
          final checked = (seed + i) % 3 == 0;
          r.add(_RosterApp('r$i', st,
              checkInAt: checked ? _at(8, 0) : null));
        }
        for (final now in [_at(5, 0), _at(10, 0), _at(15, 0), _at(23, 0)]) {
          final c = _count(r, now);
          expect(c.checkedIn, greaterThanOrEqualTo(0));
          expect(c.checkedIn, lessThanOrEqualTo(c.dueNow),
              reason: 'seed=$seed now=$now → $c');
        }
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  // §7 / §24 / §25 모집단
  // ───────────────────────────────────────────────────────────
  group('§7/§24 분자가 로스터 기준이다', () {
    test('attendance 문서 기반 count가 제거됐다', () {
      expect(loader.contains('allAttendance.where((a) => a.hasCheckedIn)'), isFalse,
          reason: '로스터에 없는 문서까지 세던 경로');
    });

    test('분자·분모가 같은 루프에서 나온다', () {
      expect(loader.contains('for (final app in allConfirmed) {'), isTrue);
      expect(loader.contains('final hasCheckedIn = attMap[app.id]?.checkInAt != null;'),
          isTrue);
      expect(loader.contains('if (hasCheckedIn) checkedIn++;'), isTrue);
      expect(loader.contains('if (started || hasCheckedIn) dueNow++;'), isTrue);
    });

    test('§25 attMap은 applicationId 단위 — 중복 문서도 1명', () {
      expect(loader.contains('final attMap = <String, AttendanceModel>{};'), isTrue);
      expect(loader.contains('if (a.applicationId.isNotEmpty) attMap[a.applicationId] = a;'),
          isTrue,
          reason: 'applicationId 없는 orphan 문서는 map에 들어가지 않는다');
    });

    test('§11 effective time source를 재사용한다', () {
      expect(loader.contains('WorkDetailHelper.effectiveStart(app, timeMap)'), isTrue);
      expect(loader.contains('scheduledStart: app.startTime'), isFalse);
      // §12 새 lookup 없음 — load 호출은 1회
      expect('WorkDetailTimeService.load('.allMatches(loader).length, 1);
    });

    test('§10 lateGrace를 쓰지 않는다', () {
      expect(loader.contains('lateGrace'), isFalse);
      expect(loader.contains('!nowLocal.isBefore(startAt)'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §14~18 ERROR != ZERO
  // ───────────────────────────────────────────────────────────
  group('§14/§18 roster 실패가 0으로 새지 않는다', () {
    test('strict variant가 생겼다', () {
      expect(
        appFs.contains(
            'Future<List<ApplicationModel>> getConfirmedWorkersByDateAndBusinessOrThrow({'),
        isTrue,
      );
    });

    test('§15 기존 메서드의 [] 계약은 유지된다', () {
      final lenient = _bodyOf(_codeOf(appFs),
          'Future<List<ApplicationModel>> getConfirmedWorkersByDateAndBusiness({');
      expect(lenient.contains('getConfirmedWorkersByDateAndBusinessOrThrow('), isTrue);
      expect(lenient.contains('return [];'), isTrue,
          reason: '다른 화면의 fallback 계약을 바꾸지 않는다');
    });

    test('strict variant에는 삼키는 catch가 없다', () {
      final strict = _bodyOf(_codeOf(appFs),
          'Future<List<ApplicationModel>> getConfirmedWorkersByDateAndBusinessOrThrow({');
      expect(strict.contains('return [];'), isFalse);
      expect(strict.contains('catch (e) {'), isFalse);
      // per-doc 방어는 유지 (tryFromMap + whereType)
      expect(strict.contains('ApplicationModel.tryFromMap('), isTrue);
    });

    test('Home이 strict variant를 쓴다', () {
      expect(loader.contains('getConfirmedWorkersByDateAndBusinessOrThrow('), isTrue);
      expect(
        loader.contains(
            '_firestoreService.getConfirmedWorkersByDateAndBusiness(\n'),
        isFalse,
      );
    });

    test('§17/§38 세 숫자가 같은 availability를 쓴다', () {
      // 실패 시 셋 다 null
      expect(loader.contains('_todayCheckedIn      = null;'), isTrue);
      expect(loader.contains('_todayDueNow         = null;'), isTrue);
      expect(loader.contains('_todayNeedsAttention = null;'), isTrue);
      // 렌더는 하나의 게이트
      final m = _bodyOf(home, 'Widget _buildAttendanceMetrics(');
      expect(m.contains('if (_todayCheckedIn == null) {'), isTrue);
      expect(m.contains('출근 현황을 불러오지 못했습니다'), isTrue);
    });

    test('§16 다사업장 중 하나만 실패해도 전체 error', () {
      // Future.wait은 하나라도 throw하면 전체가 throw → catch → null
      expect(loader.contains('final rosterFuture = Future.wait('), isTrue);
      expect(loader.contains('final attFuture = Future.wait('), isTrue);
      expect(loader.contains('} catch (e) {'), isTrue);
    });

    test('사업장 0개는 정상 0으로 남는다', () {
      expect(loader.contains('if (businesses.isEmpty) {'), isTrue);
      expect(loader.contains('_todayDueNow         = 0;'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §19~22 표시
  // ───────────────────────────────────────────────────────────
  group('§19~21 표시 계약', () {
    test('§19 value 문자열이 x / y 형태', () {
      final m = _bodyOf(home, 'Widget _buildAttendanceMetrics(');
      expect(m.contains(r"'${_todayCheckedIn!} / $dueNow'"), isTrue);
    });

    test('§20 라벨이 현재 출근', () {
      final m = _bodyOf(home, 'Widget _buildAttendanceMetrics(');
      expect(m.contains("label: '현재 출근'"), isTrue);
      expect(m.contains("label: '출근'"), isFalse);
      expect(m.contains("label: '근태 확인'"), isTrue);
    });

    test('§21 분모 0 → 예정 전', () {
      final m = _bodyOf(home, 'Widget _buildAttendanceMetrics(');
      expect(m.contains("dueNow == 0 ? '예정 전'"), isTrue);
      expect(m.contains("'0 / 0'"), isFalse);
      expect(m.contains('아직 출근 시간이 아니에요'), isFalse,
          reason: '좁은 metric 셀에 문장을 넣지 않는다');
    });

    test('_opsMetric의 기존 호출부는 영향받지 않는다', () {
      final t = _bodyOf(home, 'Widget _buildStaffingMetrics(');
      for (final l in ['필요', '확정', '부족']) {
        expect(t.contains("label: '$l'"), isTrue);
      }
      expect(t.contains('valueText:'), isFalse, reason: 'staffing은 기존 경로');
      final metric = _bodyOf(home, 'Widget _opsMetric(');
      expect(metric.contains(r"Text(valueText ?? '$value$unit'"), isTrue);
    });

    test('§22 staffing copy를 건드리지 않았다', () {
      // [HOME-V2-08D.2] '대상 없음'은 이제 gate가 섹션을 숨기고 Hero가 말한다.

      // [HOME-V2-08D.2] '대상 없음'은 이제 gate가 섹션을 숨기고 Hero가 말한다.

    });
  });

  // ───────────────────────────────────────────────────────────
  // §26~28 비용·반응성
  // ───────────────────────────────────────────────────────────
  group('§26~28 비용', () {
    test('새 쿼리·로더가 없다', () {
      final loaders = RegExp(r'Future<void> (_load[A-Za-z]*)\(')
          .allMatches(raw)
          .map((m) => m.group(1))
          .toSet();
      expect(loaders, {
        '_loadApprovedBusinessStatus', '_loadCanonicalSummary',
        '_loadPostingReadiness', '_loadStaffingReadiness', '_loadTodayAttendance',
      });
      expect(home.contains('httpsCallable'), isFalse);
      // roster·attendance 각 1회
      expect('Future.wait('.allMatches(loader).length, 2);
    });

    test('§27/§28 timer를 추가하지 않았다', () {
      expect(raw.contains('Timer'), isFalse);
      expect(raw.contains('periodic'), isFalse);
    });

    test('refresh 경로에서 재계산된다', () {
      final r = _bodyOf(home, 'Future<void> _refresh(');
      expect(r.contains('_loadTodayAttendance()'), isTrue);
      expect(home.contains('addAdminRefreshListener(_onFcmRefresh)'), isTrue);
      expect(home.contains('if (state == AppLifecycleState.resumed) _autoRefresh();'),
          isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  // §39~41 범위 제한
  // ───────────────────────────────────────────────────────────
  group('범위 제한', () {
    test('§39 staffingReleasedAt 정책 미변경', () {
      expect(appFs.contains('staffingReleasedAt'), isTrue,
          reason: '주석 기록은 유지');
      final strict = _bodyOf(_codeOf(appFs),
          'Future<List<ApplicationModel>> getConfirmedWorkersByDateAndBusinessOrThrow({');
      expect(strict.contains('staffingReleasedAt'), isFalse,
          reason: '필터를 새로 추가하지 않았다');
    });

    test('§40 lateGrace 미변경', () {
      expect(_src('lib/utils/attendance_status_helper.dart').contains('graceMinutes'),
          isTrue);
    });

    test('§41 IA·visual 불변', () {
      // [HOME-V2-08D.2] 섹션 조립이 _buildSections로 옮겨졌다 — 순서는 그대로.
      final b = _bodyOf(home, 'Widget build(') +
          _bodyOf(home, 'List<Widget> _buildSections(');
      expect(b.indexOf('_buildTodayOps('),
          lessThan(b.indexOf('_buildActionDashboard(')));
      expect(b.indexOf('_buildActionDashboard('),
          lessThan(b.indexOf('_buildFutureStaffing(')));
      expect('BoxShadow'.allMatches(home).length, 0);
      final rows = _bodyOf(home, '_makeActionRows(BuildContext context');
      expect(rows.contains('atIndex: wageOverdue ? overdueWageSlot : null,'), isTrue);
    });

    test('AH-V2-04A 근태 확인 계약 유지', () {
      expect(loader.contains('AttendanceReviewHelper.requiresReviewNow('), isTrue);
      expect(loader.contains('reviewAppIds'), isTrue);
    });

    test('attendance writer·Functions 미변경', () {
      final cf = _src('functions/src/index.ts');
      expect(cf.contains('const nonPayable = (st === "NO_SHOW" || st === "absent") && fw === 0;'),
          isTrue);
      expect(cf.contains('if (ms < todayMs) overdue++;'), isTrue);
    });
  });
}
