// [LONGTERM-DATE-ELIGIBILITY] 장기 worker-day resolver — canonical closure.
//
// 장기의 "이 사람이 그 날 일하는가"를 서버 안에서 다섯 곳이 따로 답하고
// 있었고, 각자 규칙의 다른 부분집합만 썼다. 화면이 "근무 아님"이라고
// 말하는 날짜에 서버가 attendance를 만들어 줄 수 있었고, 그 근태가 곧
// 임금과 이체로 이어졌다.
//
// 이 파일은 두 가지를 고정한다.
//
//   1. 구조 — 서버에 resolver가 **하나**이고 모든 consumer가 그것을
//      부르며, 예전 인라인 사본이 남아 있지 않다.
//   2. 의미 — 그 resolver의 규칙이 클라이언트 canonical
//      (`ApplicationModel.isWorkingOnDate`)과 **같은 답**을 낸다.
//
// 의미 검증은 서버 규칙을 Dart로 옮긴 거울(`_serverEligible`)로 한다.
// 거울이 원본과 어긋나면 아래 구조 테스트가 먼저 깨지도록, 거울이 의존하는
// 서버 코드 줄을 함께 고정한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';

const _cfPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 주석 줄을 지운 본문. 앵커는 주석이 아니라 **코드**여야 한다.
String _codeOf(String s) =>
    s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  if (i < 0) throw StateError('$name 를 찾지 못함');
  return src.substring(i, (i + chars).clamp(0, src.length));
}

// ══════════════════════════════════════════════════════════════════
// 서버 규칙의 거울 — srvLongTermEligibleOnDay 와 같은 순서·같은 경계.
// ══════════════════════════════════════════════════════════════════

const _wkKo = ['일', '월', '화', '수', '목', '금', '토'];

int _dayNum(DateTime d) => d.year * 10000 + d.month * 100 + d.day;
String _wkd(DateTime d) => _wkKo[d.weekday % 7];

/// 서버 판정 이유 — SrvWorkerDayReason 과 같은 집합.
enum SvReason {
  eligible,
  beforeStart,
  afterResign,
  afterEnd,
  noEnd,
  leave,
  nonWorkday,
}

SvReason _serverReason(ApplicationModel a, DateTime target) {
  final day = _dayNum(target);

  // effectiveStart = desiredStartDate ?? workDate, 확정일 보정 포함
  int startNum = _dayNum(a.desiredStartDate ?? a.workDate);
  if (a.desiredStartDate == null && a.confirmedAt != null) {
    final c = _dayNum(a.confirmedAt!);
    if (c > startNum) startNum = c;
  }
  if (day < startNum) return SvReason.beforeStart;

  // effectiveEnd = actualResignDate ?? workEndDate — 둘 다 inclusive
  final resign = a.actualResignDate;
  final end = resign ?? a.workEndDate;
  if (end == null) return SvReason.noEnd;
  if (day > _dayNum(end)) {
    return resign != null ? SvReason.afterResign : SvReason.afterEnd;
  }

  // 날짜 예외 → 요일. 추가근무가 휴무보다 먼저다.
  bool has(List<DateTime>? xs) =>
      xs != null && xs.any((d) => _dayNum(d) == day);
  if (has(a.extraWorkDates)) return SvReason.eligible;
  if (has(a.leaveDates)) return SvReason.leave;

  final wd = a.workDays;
  if (wd == null || wd.isEmpty || !wd.contains(_wkd(target))) {
    return SvReason.nonWorkday;
  }
  return SvReason.eligible;
}

bool _serverEligible(ApplicationModel a, DateTime t) =>
    _serverReason(a, t) == SvReason.eligible;

DateTime _d(int y, int m, int d) => DateTime(y, m, d);

/// 2026-09-01(화) ~ 2026-09-30(수), 평일 근무.
ApplicationModel _app({
  DateTime? workDate,
  DateTime? workEndDate,
  List<String>? workDays,
  DateTime? desiredStartDate,
  DateTime? actualResignDate,
  DateTime? confirmedAt,
  List<DateTime>? leaveDates,
  List<DateTime>? extraWorkDates,
  bool openEnded = false,
}) =>
    ApplicationModel(
      id: 'app1',
      businessId: 'biz1',
      businessName: '테스트 사업장',
      toTitle: '[테스트] 장기 근무',
      workDate: workDate ?? _d(2026, 9, 1),
      workEndDate: openEnded ? null : (workEndDate ?? _d(2026, 9, 30)),
      workDays: workDays ?? const ['월', '화', '수', '목', '금'],
      startTime: '09:00',
      endTime: '18:00',
      uid: 'worker1',
      selectedWorkType: '사무업무',
      wage: 12000,
      wageType: 'hourly',
      status: AppStatus.confirmed,
      appliedAt: _d(2026, 8, 25),
      confirmedAt: confirmedAt,
      desiredStartDate: desiredStartDate,
      actualResignDate: actualResignDate,
      leaveDates: leaveDates,
      extraWorkDates: extraWorkDates,
    );

void main() {
  final cf = _codeOf(_src(_cfPath));
  final resolver = _after(cf, 'function srvLongTermEligibleOnDay(', 2200);

  // ══════════════════════════════════════════════════════════════
  // 00. 거울이 서버 원본과 같은 규칙인지 — 아래 의미 테스트의 전제
  // ══════════════════════════════════════════════════════════════
  group('00. 거울 ↔ 서버 원본', () {
    test('00-a effectiveStart = desiredStartDate ?? workDate', () {
      expect(resolver.contains('const desired = ts("desiredStartDate");'), true);
      expect(resolver.contains('const workDate = ts("workDate");'), true);
      expect(
        resolver.contains(
            'let startNum = desired ?\n    srvKstDateNum(desired.toDate()) :\n'
            '    (workDate ? srvKstDateNum(workDate.toDate()) : 0);'),
        true,
      );
    });

    test('00-b 확정일 보정은 desiredStartDate가 없을 때만 적용된다', () {
      expect(resolver.contains('if (!desired) {'), true);
      expect(resolver.contains('if (cNum > startNum) startNum = cNum;'), true);
    });

    test('00-c effectiveEnd = actualResignDate ?? workEndDate', () {
      expect(resolver.contains('const resign = ts("actualResignDate");'), true);
      expect(resolver.contains('const end = resign ?? ts("workEndDate");'), true);
    });

    test('00-d 퇴사 효력일은 inclusive — strict greater로만 막는다', () {
      expect(resolver.contains('if (dayNum > srvKstDateNum(end.toDate())) {'), true);
      // `>=` 로 막으면 마지막 근무 가능일 하루가 지워진다.
      expect(resolver.contains('dayNum >= srvKstDateNum(end.toDate())'), false);
    });

    test('00-e workEndDate 없는 계약은 근무일을 만들지 않는다', () {
      expect(resolver.contains('if (!end) return {eligible: false, reason: "NO_END"};'),
          true);
      // 무기한으로 해석하는 fail-open 상수가 없다.
      expect(resolver.contains('99991231'), false);
    });

    test('00-f 추가근무가 휴무보다 먼저 판정된다', () {
      final ex = resolver.indexOf('hasDay("extraWorkDates")');
      final lv = resolver.indexOf('hasDay("leaveDates")');
      expect(ex, greaterThan(-1));
      expect(lv, greaterThan(-1));
      expect(ex, lessThan(lv));
    });

    test('00-g 빈 workDays는 근무일이 아니다', () {
      expect(
        resolver.contains(
            'if (!Array.isArray(wd) || wd.length === 0 || !wd.includes(dayWkd)) {'),
        true,
      );
    });

    test('00-h resolver가 Firestore를 읽지 않는다', () {
      // 순수 domain resolver여야 한다 — 새 read를 만들지 않는다.
      for (final banned in ['db.collection', 'await ', '.get()', 'tx.']) {
        expect(resolver.contains(banned), false, reason: banned);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 01. helper contract A~P (§21)
  // ══════════════════════════════════════════════════════════════
  group('01. resolver contract', () {
    test('A. start 당일 → allow', () {
      expect(_serverEligible(_app(), _d(2026, 9, 1)), true);
    });

    test('B. start 이전 → reject', () {
      // 8/31은 월요일 — 요일만 보면 근무일이다.
      expect(_d(2026, 8, 31).weekday, DateTime.monday);
      expect(_serverReason(_app(), _d(2026, 8, 31)), SvReason.beforeStart);
    });

    test('C. end 당일 → allow', () {
      expect(_serverEligible(_app(), _d(2026, 9, 30)), true);
    });

    test('D. end 이후 → reject', () {
      // 10/1은 목요일 — 요일이 맞아도 계약이 끝났다.
      expect(_serverReason(_app(), _d(2026, 10, 1)), SvReason.afterEnd);
    });

    test('E. desiredStartDate가 있으면 그것이 시작이다', () {
      final a = _app(desiredStartDate: _d(2026, 9, 10));
      expect(_serverReason(a, _d(2026, 9, 9)), SvReason.beforeStart);
      expect(_serverEligible(a, _d(2026, 9, 10)), true);
    });

    test('F. desiredStartDate null → workDate fallback', () {
      // BLOCKER-2: 예전 서버에는 이 fallback이 없어 하한이 통째로 사라졌다.
      final a = _app();
      expect(a.desiredStartDate, isNull);
      expect(_serverReason(a, _d(2026, 8, 25)), SvReason.beforeStart);
      expect(_serverEligible(a, _d(2026, 9, 1)), true);
    });

    test('G. desiredStartDate null + 늦은 확정 → 확정일이 시작이다', () {
      final a = _app(confirmedAt: _d(2026, 9, 10));
      expect(_serverReason(a, _d(2026, 9, 5)), SvReason.beforeStart);
      expect(_serverReason(a, _d(2026, 9, 9)), SvReason.beforeStart);
      expect(_serverEligible(a, _d(2026, 9, 10)), true); // 목요일
    });

    test('G-b. 희망 시작일을 직접 고른 경우 확정일이 덮지 않는다', () {
      final a = _app(
        desiredStartDate: _d(2026, 9, 3),
        confirmedAt: _d(2026, 9, 10),
      );
      expect(_serverEligible(a, _d(2026, 9, 3)), true);
    });

    test('H. 퇴사 효력일 이전 → allow', () {
      final a = _app(actualResignDate: _d(2026, 9, 15));
      expect(_serverEligible(a, _d(2026, 9, 14)), true);
    });

    test('I. 퇴사 효력일 당일 → allow', () {
      // D = 마지막 근무 가능일. 하루를 지우지 않는다.
      final a = _app(actualResignDate: _d(2026, 9, 15));
      expect(_d(2026, 9, 15).weekday, DateTime.tuesday);
      expect(_serverEligible(a, _d(2026, 9, 15)), true);
    });

    test('J. 퇴사 효력일 다음날 → reject', () {
      final a = _app(actualResignDate: _d(2026, 9, 15));
      expect(_serverReason(a, _d(2026, 9, 16)), SvReason.afterResign);
    });

    test('K. 정상 근무요일 → allow', () {
      expect(_serverEligible(_app(), _d(2026, 9, 2)), true);
    });

    test('L. 비근무요일 → reject', () {
      expect(_serverReason(_app(), _d(2026, 9, 5)), SvReason.nonWorkday);
    });

    test('M. 비근무요일 + 추가근무 → allow', () {
      final a = _app(extraWorkDates: [_d(2026, 9, 5)]);
      expect(_serverEligible(a, _d(2026, 9, 5)), true);
    });

    test('N. 정상 근무일 + 휴무 → reject', () {
      final a = _app(leaveDates: [_d(2026, 9, 2)]);
      expect(_serverReason(a, _d(2026, 9, 2)), SvReason.leave);
    });

    test('O. leave ∩ extra dual-state → 추가근무 우선', () {
      final a = _app(
        leaveDates: [_d(2026, 9, 5)],
        extraWorkDates: [_d(2026, 9, 5)],
      );
      expect(_serverEligible(a, _d(2026, 9, 5)), true);
    });

    test('P. workEndDate null → 근무일 없음', () {
      final a = _app(openEnded: true);
      expect(_serverReason(a, _d(2026, 9, 2)), SvReason.noEnd);
    });

    test('Q. 추가근무도 기간 밖으로는 나가지 못한다', () {
      final a = _app(extraWorkDates: [_d(2026, 10, 3)]);
      expect(_serverReason(a, _d(2026, 10, 3)), SvReason.afterEnd);
    });

    test('R. 퇴사 효력일이 rangeEnd보다 앞서면 그쪽이 이긴다', () {
      final a = _app(actualResignDate: _d(2026, 9, 15));
      expect(_serverReason(a, _d(2026, 9, 21)), SvReason.afterResign);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. 서버 ↔ 클라이언트 canonical parity (§22)
  //
  //   같은 fixture·같은 날짜에서 두 판정이 같아야 한다. 하나라도
  //   갈리면 "화면은 근무 아님 / 서버는 허용"이 다시 생긴다.
  // ══════════════════════════════════════════════════════════════
  group('02. 서버 ↔ 화면 parity', () {
    final cases = <String, (ApplicationModel, List<DateTime>)>{
      '기본 평일 계약': (
        _app(),
        [
          _d(2026, 8, 31), _d(2026, 9, 1), _d(2026, 9, 2), _d(2026, 9, 5),
          _d(2026, 9, 30), _d(2026, 10, 1), _d(2026, 10, 2),
        ]
      ),
      '희망 시작일': (
        _app(desiredStartDate: _d(2026, 9, 10)),
        [_d(2026, 9, 8), _d(2026, 9, 9), _d(2026, 9, 10), _d(2026, 9, 11)]
      ),
      '늦은 확정': (
        _app(confirmedAt: _d(2026, 9, 10)),
        [_d(2026, 9, 1), _d(2026, 9, 9), _d(2026, 9, 10), _d(2026, 9, 11)]
      ),
      '퇴사 효력일': (
        _app(actualResignDate: _d(2026, 9, 15)),
        [_d(2026, 9, 14), _d(2026, 9, 15), _d(2026, 9, 16), _d(2026, 9, 17)]
      ),
      '휴무': (
        _app(leaveDates: [_d(2026, 9, 2), _d(2026, 9, 3)]),
        [_d(2026, 9, 1), _d(2026, 9, 2), _d(2026, 9, 3), _d(2026, 9, 4)]
      ),
      '추가근무': (
        _app(extraWorkDates: [_d(2026, 9, 5), _d(2026, 9, 6)]),
        [_d(2026, 9, 4), _d(2026, 9, 5), _d(2026, 9, 6), _d(2026, 9, 7)]
      ),
      'dual-state': (
        _app(
          leaveDates: [_d(2026, 9, 5)],
          extraWorkDates: [_d(2026, 9, 5)],
        ),
        [_d(2026, 9, 5)]
      ),
      '기간 미정': (
        _app(openEnded: true),
        [_d(2026, 9, 1), _d(2026, 9, 2), _d(2026, 9, 30)]
      ),
      '전일 근무': (
        _app(workDays: const ['월', '화', '수', '목', '금', '토', '일']),
        [_d(2026, 9, 5), _d(2026, 9, 6), _d(2026, 9, 30), _d(2026, 10, 1)]
      ),
    };

    cases.forEach((name, fixture) {
      final (app, dates) = fixture;
      test('$name — 모든 날짜에서 같은 답', () {
        for (final d in dates) {
          expect(
            _serverEligible(app, d),
            app.isWorkingOnDate(d),
            reason: '$name / ${_dayNum(d)} (${_wkd(d)}) 에서 서버와 화면이 갈린다',
          );
        }
      });
    });

    test('기간 전체를 훑어도 한 날도 갈리지 않는다', () {
      final app = _app(
        confirmedAt: _d(2026, 9, 4),
        leaveDates: [_d(2026, 9, 9), _d(2026, 9, 10)],
        extraWorkDates: [_d(2026, 9, 12), _d(2026, 9, 13)],
        actualResignDate: _d(2026, 9, 24),
      );
      var mismatched = 0;
      for (var i = -10; i <= 45; i++) {
        final d = _d(2026, 9, 1).add(Duration(days: i));
        final day = DateTime(d.year, d.month, d.day);
        if (_serverEligible(app, day) != app.isWorkingOnDate(day)) mismatched++;
      }
      expect(mismatched, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. consumer inventory — 같은 질문은 같은 함수에 묻는다 (§9·§35)
  // ══════════════════════════════════════════════════════════════
  group('03. consumer 배선', () {
    test('03-a resolver는 하나다', () {
      expect(
        RegExp(r'function srvLongTermEligibleOnDay\(').allMatches(cf).length,
        1,
      );
    });

    test('03-b callableCheckIn이 resolver를 쓴다', () {
      final ci = _after(cf, 'export const callableCheckIn', 25000);
      expect(ci.contains('srvLongTermEligibleOnDay('), true);
      // 예전 인라인 판정이 남아 있지 않다.
      expect(ci.contains('if (resignDateKSTDay <= workDateKSTDay)'), false);
      expect(ci.contains('const isExtraWorkDate = (extraWorkDates ?? []).some('),
          false);
    });

    test('03-c 관리자 배치 경로가 resolver를 쓴다', () {
      final r = _after(cf, 'async function _resolveAttendanceWorkContext(', 6000);
      expect(r.contains('srvLongTermEligibleOnDay('), true);
      expect(r.contains('_fail("after_contract_end")'), false,
          reason: '이유 매핑은 테이블로만 존재한다');
      expect(r.contains('AFTER_END: "after_contract_end"'), true);
      expect(r.contains('AFTER_RESIGN: "after_resign_date"'), true);
    });

    test('03-d 자동 NO_SHOW가 resolver를 쓴다', () {
      final seg = _after(
        cf,
        '.where("workEndDate", ">=", Timestamp.fromDate(yesterdayStartUTC))',
        1400,
      );
      expect(seg.contains('srvLongTermEligibleOnDay('), true);
      // 예전 사본이 남아 있지 않다.
      expect(seg.contains('if (!isRegularDay && !isExtraDay) continue;'), false);
      expect(seg.contains('if (isLeave) continue;'), false);
    });

    test('03-e 좌석 집계가 resolver를 쓴다', () {
      final seg = _after(cf, 'function srvContractConfirmedOnDay(', 700);
      expect(seg.contains('srvLongTermEligibleOnDay('), true);
      expect(seg.contains('99991231'), false);
    });

    test('03-f staffing readiness의 인라인 사본이 사라졌다', () {
      // 같은 판정을 따로 하던 자리 — 홈의 부족과 하루 상세가 갈릴 수 있었다.
      expect(cf.contains('srfKstDateNum(appEndTs.toDate())'), false);
      expect(cf.contains('extras.some((ts) => srfKstDateNum(ts.toDate()) === dayNum)'),
          false);
    });

    test('03-g TO 레벨 helper와 합치지 않았다', () {
      // Posting target eligibility ≠ Worker promise eligibility.
      expect(cf.contains('function srvContractActiveOnDay('), true);
      final active = _after(cf, 'function srvContractActiveOnDay(', 800);
      expect(active.contains('rangeStart'), true);
      expect(active.contains('leaveDates'), false);
      expect(active.contains('actualResignDate'), false);
    });

    test('03-h resolver가 status를 판정하지 않는다', () {
      // lifecycle gate는 caller 책임 — 여기 넣으면 정책이 두 곳이 된다.
      for (final banned in ['CONFIRMED', 'CONTRACT_PENDING', '"status"']) {
        expect(resolver.contains(banned), false, reason: banned);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. direct vs batch 불변식 (§23)
  // ══════════════════════════════════════════════════════════════
  group('04. direct ↔ batch', () {
    test('04-a 두 경로가 같은 함수·같은 입력을 쓴다', () {
      final ci = _after(cf, 'export const callableCheckIn', 25000);
      final bt = _after(cf, 'async function _resolveAttendanceWorkContext(', 6000);
      for (final seg in [ci, bt]) {
        expect(seg.contains('srvLongTermEligibleOnDay('), true);
        expect(seg.contains('srvKstDateNum('), true);
        expect(seg.contains('srvKstWeekdayKo('), true);
      }
    });

    test('04-b 단기 휴무 검사가 한쪽에만 남지 않았다', () {
      // 장기 휴무는 resolver가 보고, 단기는 각 경로가 본다.
      final bt = _after(cf, 'async function _resolveAttendanceWorkContext(', 6000);
      expect(bt.contains('!== "long_term"'), true);
      final ci = _after(cf, 'export const callableCheckIn', 25000);
      expect(ci.contains('휴무일에는 출근할 수 없습니다.'), true);
    });

    test('04-c 배치 NO_SHOW도 같은 컨텍스트 검증을 통과해야 한다', () {
      expect(cf.contains('const nsWorkCtx = await _resolveAttendanceWorkContext('),
          true);
      expect(cf.contains('if (!nsWorkCtx.valid)'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 05. 좌석 불변식 (§24)
  // ══════════════════════════════════════════════════════════════
  group('05. confirmed seat', () {
    // 9/15(화)가 퇴사 효력일. 전후 세 날 모두 정상 근무요일이다.
    int seat(ApplicationModel a, DateTime d) => _serverEligible(a, d) ? 1 : 0;

    test('05-a D-1 → seat 1', () {
      final a = _app(actualResignDate: _d(2026, 9, 15));
      expect(seat(a, _d(2026, 9, 14)), 1);
    });

    test('05-b D 당일 → seat 1', () {
      final a = _app(actualResignDate: _d(2026, 9, 15));
      expect(seat(a, _d(2026, 9, 15)), 1);
    });

    test('05-c D+1 → seat 0', () {
      final a = _app(actualResignDate: _d(2026, 9, 16));
      expect(seat(a, _d(2026, 9, 17)), 0);
    });

    test('05-d 좌석이 빠지면 그만큼 부족이 생긴다', () {
      // 필요 1명 · 확정 1명이던 날이 D+1부터 부족 1이 된다.
      final a = _app(actualResignDate: _d(2026, 9, 15));
      int shortage(DateTime d) => (1 - seat(a, d)).clamp(0, 1);
      expect(shortage(_d(2026, 9, 15)), 0);
      expect(shortage(_d(2026, 9, 16)), 1);
    });
  });
}
