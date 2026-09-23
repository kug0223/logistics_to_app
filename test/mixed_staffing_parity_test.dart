// [R7-P1-PRODUCT] 단기 + 장기가 섞인 날짜의 staffing truth.
//
//   Same entity + Same event = Same business truth across every surface.
//
// 실기기에서 관찰된 것: Home이 `부족 1 ›`이라고 보낸 화면에 그 부족을 만든
// 대상이 없었다. 원인은 callableGetDayStaffingDetail이 `type !== "flex"`
// 한 줄로 장기 공고를 통째로 건너뛴 것이었다. Home(readiness)은 장기를
// 세고 있었으므로, 두 reader가 같은 날짜를 다르게 말했다.
//
// DEV 실측(수정 전, 2026-09-23~30): 8일 **전부** 정확히 1 차이 —
// 장기 공고의 부족(필요 2 − 확정 1)과 같았다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';

const _cfPath = 'functions/src/index.ts';
const _dayPath =
    'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String s) =>
    s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// [name]으로 시작하는 TS 선언 이후 [span]줄.
String _tsAfter(String src, String name, int span) {
  final i = src.indexOf(name);
  if (i < 0) throw StateError('$name 를 찾지 못함');
  return src.substring(i, (i + span).clamp(0, src.length));
}

DayStaffingRow _row({
  required int required,
  required int confirmed,
  bool closed = false,
  bool longTerm = false,
  String slotId = 'slot1',
}) =>
    DayStaffingRow(
      toId: 'to1',
      toTitle: 't',
      slotId: longTerm ? '' : slotId,
      wdId: 'wd1',
      workType: '사무업무',
      startTime: '09:00',
      endTime: '18:00',
      requiredCount: required,
      confirmedCount: confirmed,
      pendingCount: 0,
      isClosed: closed,
      isLongTerm: longTerm,
    );

void main() {
  // ══════════════════════════════════════════════════════════════
  // 01. mixed 집계 — 단기 부족 2 + 장기 부족 1 = 3
  // ══════════════════════════════════════════════════════════════
  group('01. mixed staffing 집계', () {
    test('01-a 단기 shortage 2 + 장기 shortage 1 → 합계 3', () {
      final rows = [
        _row(required: 3, confirmed: 1), // 단기 → 부족 2
        _row(required: 2, confirmed: 1, longTerm: true), // 장기 → 부족 1
      ];
      final total = rows.fold<int>(0, (a, r) => a + r.shortage);
      expect(total, 3);
    });

    test('01-b 장기를 빼면 실기기에서 본 그 숫자가 된다 — 회귀 고정', () {
      final rows = [
        _row(required: 3, confirmed: 1),
        _row(required: 2, confirmed: 1, longTerm: true),
      ];
      final flexOnly = rows.where((r) => !r.isLongTerm);
      expect(flexOnly.fold<int>(0, (a, r) => a + r.shortage), 2,
          reason: '이것이 수정 전 다이얼로그가 말하던 값이다');
    });

    test('01-c 장기만 있는 날도 대상이 사라지지 않는다', () {
      // 2026-09-23~25가 이 경우였다 — rows 0, 화면이 통째로 비었다.
      final rows = [_row(required: 2, confirmed: 1, longTerm: true)];
      expect(rows.length, 1);
      expect(rows.first.shortage, 1);
    });

    test('01-d 장기 row는 slotId가 없어도 버려지지 않는다', () {
      // tryFromMap이 slotId 빈 문자열을 거르고 있었다 — 서버가 보내도
      // 클라이언트에서 전부 사라졌을 것이다.
      final parsed = DayStaffingRow.tryFromMap({
        'toId': 'to1',
        'toTitle': 't',
        'slotId': '',
        'wdId': 'wd1',
        'workType': '사무업무',
        'requiredCount': 2,
        'confirmedCount': 1,
        'isLongTerm': true,
      });
      expect(parsed, isNotNull);
      expect(parsed!.isLongTerm, true);
      expect(parsed.shortage, 1);
    });

    test('01-e 단기는 여전히 slotId가 필요하다 — 깨진 데이터를 통과시키지 않는다', () {
      final parsed = DayStaffingRow.tryFromMap({
        'toId': 'to1',
        'slotId': '',
        'wdId': 'wd1',
        'requiredCount': 2,
        'confirmedCount': 1,
      });
      expect(parsed, isNull,
          reason: '단기에 슬롯이 없으면 그 날짜의 모집 단위를 특정할 수 없다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. 장기 날짜 자격 — 기간 안이라고 근무일이 아니다
  // ══════════════════════════════════════════════════════════════
  group('02. 장기 date eligibility', () {
    final cf = _codeOf(_src(_cfPath));

    test('02-a 판정이 공용 함수로 올라갔다 — 두 reader가 같은 규칙을 쓴다', () {
      expect(cf.contains('function srvContractActiveOnDay('), true);
      expect(cf.contains('function srvContractConfirmedOnDay('), true);
      // readiness는 지역 사본 대신 공용 함수에 위임한다.
      expect(cf.contains('const srfKstDateNum = srvKstDateNum;'), true);
      expect(cf.contains('const srfKstWeekdayKo = srvKstWeekdayKo;'), true);
    });

    test('02-b workDays에 없는 요일은 대상이 아니다', () {
      final body = _tsAfter(cf, 'function srvContractActiveOnDay(', 900);
      expect(body.contains('rangeStart'), true);
      expect(body.contains('rangeEnd'), true);
      // 기간 안이라는 이유만으로 근무일이라고 추정하지 않는다.
      expect(body.contains('wd.includes(dayWkd)'), true);
    });

    test('02-c 확정 수는 지원서별 기간·요일·휴무를 전부 본다', () {
      final body = _tsAfter(cf, 'function srvContractConfirmedOnDay(', 1600);
      expect(body.contains('workDate'), true);
      expect(body.contains('workEndDate'), true);
      expect(body.contains('extraWorkDates'), true);
      expect(body.contains('leaveDates'), true);
      expect(body.contains('appWorkDays'), true);
    });

    test('02-d detail이 더 이상 장기를 건너뛰지 않는다', () {
      final body = _tsAfter(cf, 'export const callableGetDayStaffingDetail', 12000);
      expect(body.contains('contractTOs'), true);
      expect(body.contains('srvContractActiveOnDay('), true);
      expect(body.contains('isLongTerm: true'), true);
      // 버리던 한 줄이 사라졌다.
      expect(body.contains('!== "flex") continue'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. capacity 계약 — mixed에서도 그대로
  // ══════════════════════════════════════════════════════════════
  group('03. capacity regression', () {
    test('03-a FULL → 부족 0', () {
      expect(_row(required: 2, confirmed: 2, longTerm: true).shortage, 0);
      expect(
        inviteCapacityStateOf(
            canonicalConfirmed: 2, requiredCount: 2, isClosed: false),
        InviteCapacityState.full,
      );
    });

    test('03-b CLOSED → 부족 0, 자리가 남아 있어도', () {
      expect(
          _row(required: 5, confirmed: 1, closed: true, longTerm: true).shortage,
          0);
      expect(
        inviteCapacityStateOf(
            canonicalConfirmed: 1, requiredCount: 5, isClosed: true),
        InviteCapacityState.closed,
      );
    });

    test('03-c UNKNOWN → 부족을 주장하지 않는다', () {
      expect(
        staffingShortageOf(
            capacity: InviteCapacityState.unknown,
            requiredCount: 2,
            seatedConfirmed: 0),
        isNull,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. 화면 계약
  // ══════════════════════════════════════════════════════════════
  group('04. 다이얼로그 계약', () {
    final day = _codeOf(_src(_dayPath));

    test('04-a 그룹의 장기 여부는 canonical row가 정한다', () {
      expect(day.contains('isLongTerm: row.isLongTerm'), true);
      expect(day.contains('isLongTerm: false,\n        wdId: row.wdId'), false,
          reason: '하드코딩된 false가 남아 있으면 장기가 단기로 표시된다');
      expect(day.contains('existing.isLongTerm = row.isLongTerm;'), true);
    });

    test('04-b 장기 초대 CTA는 아직 세우지 않는다 — 경로가 하루짜리를 만든다', () {
      // InviteWorkerDialog.contextual은 groupItem이 null이라
      // isLongTerm이 false로 계산되고 workEndDate/workDays를 싣지 못한다.
      final invite = _codeOf(
          _src('lib/screens/business_admin/dialogs/invite_worker_dialog.dart'));
      expect(invite.contains('widget.groupItem?.isLongTerm ?? false'), true,
          reason: '이 사실이 바뀌면 CTA 판단을 다시 해야 한다');
      expect(day.contains('if (!g.isLongTerm && g.toId != null &&'), true);
      // 대신 막다른 길로 두지 않는다.
      expect(day.contains('_buildLongTermInviteHint('), true);
    });

    test('04-c 장기 부족도 UNKNOWN 안내 대상이다', () {
      expect(day.contains('(g.isLongTerm || g.slotId != null)'), true);
    });
  });
}
