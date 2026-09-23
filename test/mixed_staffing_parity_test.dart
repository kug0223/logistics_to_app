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
import 'package:ALfit/utils/format_helper.dart';

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
  _extra();
  _workDays();
  _vocabulary();
  _shortageSummary();
  _deadlineColor();
  _weeklyBadge();
}

// ════════════════════════════════════════════════════════════════════════
// [R7-P1-PRODUCT §10 §17 §18] 실기기에서 관찰된 나머지 두 가지.
// ════════════════════════════════════════════════════════════════════════

void _extra() {
  const workPath =
      'lib/screens/business_admin/dialogs/work_applicants_dialog.dart';
  const detailPath = 'lib/widgets/admin/cards/admin_work_detail.dart';

  group('05. §10 지원자 N semantics', () {
    final detail = _codeOf(_src(detailPath));

    test('05-a 확정자를 지원자라고 부르던 칩이 사라졌다', () {
      // `_confirmedCount + _pendingCount`를 `지원자 N`으로 표시하고 있었다.
      expect(detail.contains('지원자 \$totalApplicants'), false);
      expect(detail.contains('final totalApplicants ='), false);
    });

    test('05-b 확정과 대기를 합치는 표시가 남아 있지 않다', () {
      // 이 불변식은 admin_to_group_card의 staffing line이 이미 선언했다.
      final card = _codeOf(
          _src('lib/widgets/admin/cards/admin_to_group_card.dart'));
      expect(card.contains('확정과 대기를 합치지 않는다') ||
          _src('lib/widgets/admin/cards/admin_to_group_card.dart')
              .contains('확정`과 `대기`를 합치지 않는다'), true,
          reason: '불변식 선언이 사라지면 이 테스트의 근거가 없어진다');
      // 합계가 **화면 문구**로 나오지 않는다. progress bar는 같은 식으로
      // 비율을 계산하지만 그것은 숫자를 주장하지 않는 시각 보조다.
      expect(detail.contains('지원자'), false,
          reason: '이 위젯에서 지원자라는 낱말이 쓰일 자리가 없다');
    });

    test('05-c 확정·대기·미충원은 여전히 각각 말한다', () {
      expect(detail.contains("'확정 \$_confirmedCount'"), true);
      expect(detail.contains("'대기 \$_pendingCount'"), true);
      expect(detail.contains("'미충원 \$missing'"), true);
    });
  });

  group('06. §17 bulk 1명', () {
    test('06-a 업무별 명단: PENDING 2명 이상에서만 일괄선택', () {
      final s = _codeOf(_src(workPath));
      expect(s.contains('pending.length >= 2 || _isBatchMode'), true);
      expect(s.contains('if (pending.isNotEmpty && widget.work != null)'), false);
    });

    test('06-b 당일 명단: 게이트가 생겼다', () {
      final s = _codeOf(_src(_dayPath));
      expect(s.contains('_pendingApps.length >= 2 || _isBatchMode'), true);
    });

    test('06-c bulk 모드 중에는 대상이 줄어도 사라지지 않는다 — 취소가 거기 있다', () {
      for (final p in [workPath, _dayPath]) {
        expect(_codeOf(_src(p)).contains('|| _isBatchMode'), true, reason: p);
      }
    });
  });

  group('07. §18 mixed 단기+장기 bulk', () {
    test('07-a 일괄 확정은 건별 callable — 한 batch로 묶지 않는다', () {
      final s = _codeOf(_src(_dayPath));
      // 지원서 하나씩 순차 처리하므로 단기/장기가 섞여도 각자 자기 규칙으로 간다.
      expect(s.contains('for (final appId in ids)'), true);
      expect(s.contains('applicationId: appId'), true);
      // 병렬로 바꾸면 동일 슬롯 중복 확정이 생긴다 — 계약 유지.
      expect(s.contains('Future.wait(ids'), false);
    });

    test('07-b 부분 실패를 전체 성공으로 말하지 않는다', () {
      final s = _codeOf(_src(_dayPath));
      expect(s.contains('successCount < total'), true);
      expect(s.contains('successCount == 0'), true);
    });
  });
}

// ════════════════════════════════════════════════════════════════════════
// [R7-P1-PRODUCT §6] 장기 근무요일 압축.
//
// 실기기에서 `9/9 ~ 10/23 · 월,화,수,목,금,토,일 · 06:00~0…`로 시간이
// 잘렸다. 글자 크기가 아니라 정보 선택 문제다.
//
// 레퍼런스: 알바몬은 `주5일`·`요일협의`로 요약한다 — 일곱 개를 나열하지
// 않는다. 다만 `주N일`은 어느 요일인지를 잃으므로 그대로 쓰지 않았다.
// 패턴에 이름이 있을 때만 그 이름을 쓰고, 없으면 나열한다.
// ════════════════════════════════════════════════════════════════════════

void _workDays() {
  group('08. §6 근무요일 압축', () {
    test('08-a 이름이 있는 패턴은 그 이름으로', () {
      expect(FormatHelper.compactWorkDays(['월', '화', '수', '목', '금', '토', '일']),
          '매일');
      expect(FormatHelper.compactWorkDays(['월', '화', '수', '목', '금']), '평일');
      expect(FormatHelper.compactWorkDays(['토', '일']), '주말');
    });

    test('08-b 이름이 없으면 나열한다 — 숫자로만 줄이지 않는다', () {
      expect(FormatHelper.compactWorkDays(['월', '수', '금']), '월·수·금');
      // `주3일`처럼 어느 요일인지 잃는 표기를 쓰지 않는다.
      expect(FormatHelper.compactWorkDays(['월', '수', '금']).contains('주'), false);
    });

    test('08-c 요일 순서로 정렬한다', () {
      expect(FormatHelper.compactWorkDays(['금', '월', '수']), '월·수·금');
    });

    test('08-d 비어 있으면 아무 말도 하지 않는다 — UNKNOWN != 매일', () {
      expect(FormatHelper.compactWorkDays(null), '');
      expect(FormatHelper.compactWorkDays([]), '');
    });

    test('08-e 중복이 들어와도 흔들리지 않는다', () {
      expect(FormatHelper.compactWorkDays(['월', '월', '화', '수', '목', '금']),
          '평일');
    });

    test('08-f 장기 기간 문구가 실제로 짧아졌다', () {
      final s = FormatHelper.formatWorkPeriod(
        startDate: DateTime(2026, 9, 9),
        endDate: DateTime(2026, 10, 23),
        isLongTerm: true,
        workDays: const ['월', '화', '수', '목', '금', '토', '일'],
      );
      expect(s.contains('매일'), true);
      expect(s.contains('월,화,수,목,금,토,일'), false);
      // 잘리던 원인이 11자 줄었다 (월,화,수,목,금,토,일 13자 → 매일 2자).
      final before = s.replaceAll('매일', '월,화,수,목,금,토,일');
      expect(before.length - s.length, 11);
    });

    test('08-g 토요일만 일하는 공고를 주말이라고 하지 않는다', () {
      expect(FormatHelper.compactWorkDays(['토']), '토');
    });
  });
}

// ════════════════════════════════════════════════════════════════════════
// [R7-P1-PRODUCT §8] 고정 / 장기 vocabulary.
//
// 같은 isLongTerm 타입이 공고 카드에서는 `고정`, 인력 현황에서는 `장기`로
// 보였다. 코드베이스에서도 11곳 `장기` / 6곳 `고정`으로 갈려 있었다.
// ════════════════════════════════════════════════════════════════════════

void _vocabulary() {
  /// 사용자에게 보이는 문자열 리터럴만 센다.
  int _count(String needle, List<String> paths) {
    var n = 0;
    for (final p in paths) {
      n += RegExp(RegExp.escape(needle)).allMatches(_codeOf(_src(p))).length;
    }
    return n;
  }

  const surfaces = [
    'lib/widgets/admin/cards/admin_to_group_card.dart',
    'lib/widgets/admin/cards/admin_to_item_card.dart',
    'lib/widgets/inputs/filter_dialog.dart',
    'lib/widgets/user/cards/user_to_card.dart',
    'lib/screens/user/my_schedule_screen.dart',
    'lib/screens/business_admin/to_management/create_to_screen.dart',
  ];

  group('09. §8 장기 vocabulary', () {
    test('09-a 공고 타입 배지에 `고정`이 남아 있지 않다', () {
      expect(_count("'고정'", surfaces), 0);
    });

    test('09-b 공고 타입 라벨이 장기다', () {
      final to = _codeOf(_src('lib/models/core/to_model.dart'));
      expect(to.contains("isFlexType ? '단기 근무' : '장기 근무'"), true);
    });

    test('09-c `고정 근무자`(상시 인력 명부)는 그대로다 — 다른 개념이다', () {
      // 이것까지 바꾸면 공고 타입과 인력 명부가 다시 같은 말이 된다.
      final help = _codeOf(_src('lib/screens/common/help_screen.dart'));
      expect(help.contains('고정 근무자'), true);
    });

    test('09-d enum/state 이름은 건드리지 않았다', () {
      final to = _src('lib/models/core/to_model.dart');
      expect(to.contains("contract = 'contract'"), true);
      expect(to.contains('isContractType'), true);
    });
  });
}

// ════════════════════════════════════════════════════════════════════════
// [R7-P1-PRODUCT §9] staffing summary가 부족을 직접 말한다.
//
// `확정 2 / 필요 9 · 대기 1`은 관리자에게 9−2를 시킨다.
// 단, 집계 뺄셈으로 세면 과충원된 업무가 다른 업무의 부족을 상쇄한다.
// ════════════════════════════════════════════════════════════════════════

void _shortageSummary() {
  const cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
  const modelPath = 'lib/models/ui/admin_to_list_ui_models.dart';

  group('10. §9 카드 부족 노출', () {
    final card = _codeOf(_src(cardPath));
    final model = _codeOf(_src(modelPath));

    test('10-a 부족을 직접 말한다', () {
      expect(card.contains("'부족 \$shortage'"), true);
    });

    test('10-b 업무별로 clamp해 더한다 — 과충원이 부족을 상쇄하지 않는다', () {
      expect(model.contains('int shortage'), true);
      final i = model.indexOf('resolveStats()');
      final body = model.substring(i, (i + 1400).clamp(0, model.length));
      // 업무 루프 안에서 clamp한 뒤 누적한다.
      expect(body.contains('s += clamp(work.requiredCount - wc)'), true);
      // 집계 뺄셈을 루프 밖에서 하지 않는다.
      expect(body.contains('shortage: r - c'), false);
    });

    test('10-c 정원을 모르면 부족을 주장하지 않는다', () {
      final i = card.indexOf('final showShortage =');
      expect(card.substring(i, i + 120).contains('required > 0'), true);
    });

    test('10-d 다 찼으면 `부족 0`을 덧붙이지 않는다', () {
      final i = card.indexOf('final showShortage =');
      final seg = card.substring(i, i + 120);
      expect(seg.contains('!isFull'), true);
      expect(seg.contains('shortage > 0'), true);
    });

    test('10-e 기존 계약 유지 — 미충원/충원은 여전히 쓰지 않는다', () {
      // 부족은 대기를 빼지 않는다. 미충원(required−confirmed−pending)과 다르다.
      final i = card.indexOf('Widget _buildStaffingLine(');
      final body = card.substring(i, i + 2000);
      expect(body.contains('미충원'), false);
      expect(body.contains('충원'), false);
      expect(body.contains('- pending'), false);
    });

    test('10-f 부족은 orange — red는 실패에 남긴다', () {
      final i = card.indexOf("'부족 \$shortage'");
      expect(card.substring(i, i + 200).contains('AppColors.warningDark'), true);
    });
  });
}

// ════════════════════════════════════════════════════════════════════════
// [R7-P1-PRODUCT §20] 마감 색 — orange는 지금 처리할 것에만.
//
// 한 달 남은 `지원 마감 10/22`가 orange로 떴다. 새 D-N 기준을 만들지
// 않고, 이미 있는 canonical 상태만 쓴다.
// ════════════════════════════════════════════════════════════════════════

void _deadlineColor() {
  const cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';

  group('11. §20 마감 색', () {
    final card = _codeOf(_src(cardPath));

    test('11-a 장기 게시 만료일은 참고 정보 — 미래인데 orange가 아니다', () {
      final i = card.indexOf('Widget _buildLongTermMeta(');
      final body = card.substring(i, (i + 900).clamp(0, card.length));
      expect(body.contains('isPast ? AppColors.grey500 : AppColors.grey600'),
          true);
      expect(body.contains('AppColors.warningDark'), false);
    });

    test('11-b 장기에 없는 임박 기준을 지어내지 않았다', () {
      final i = card.indexOf('Widget _buildLongTermMeta(');
      final body = card.substring(i, (i + 900).clamp(0, card.length));
      // applicationDeadline 기준을 게시 만료일에 섞어 쓰지 않는다.
      expect(body.contains('isDeadlineUrgent'), false);
      expect(body.contains('inDays'), false);
      expect(body.contains('Duration(days:'), false);
    });

    test('11-c 단기 마감은 임박할 때만 orange — 기존 isSoon을 그대로 쓴다', () {
      final i = card.indexOf('Widget _buildDeadlineMeta(');
      final body = card.substring(i, (i + 2200).clamp(0, card.length));
      expect(body.contains('isSoon ? AppColors.warningDark : AppColors.grey600'),
          true);
      // isSoon 정의는 건드리지 않았다.
      expect(body.contains('remaining.inHours < 2'), true);
    });

    test('11-d 지난 마감은 회색 — 상태가 바뀌지 않았다', () {
      final i = card.indexOf('Widget _buildDeadlineMeta(');
      final body = card.substring(i, (i + 2200).clamp(0, card.length));
      expect(body.contains('isPast'), true);
      expect(body.contains('AppColors.grey500'), true);
    });
  });
}

// ════════════════════════════════════════════════════════════════════════
// [R7-P1-PRODUCT §13] 주N회는 상태가 아니다.
// ════════════════════════════════════════════════════════════════════════

void _weeklyBadge() {
  const workPath =
      'lib/screens/business_admin/dialogs/work_applicants_dialog.dart';

  group('12. §13 주N회 배지', () {
    test('12-a 빈도에 의미색을 쓰지 않는다', () {
      for (final p in [workPath, _dayPath]) {
        final s = _codeOf(_src(p));
        // **정의**를 기준으로 잡는다 — 호출부가 먼저 나온다.
        final i = s.contains('Widget _buildWeeklyCountBadge(')
            ? s.indexOf('Widget _buildWeeklyCountBadge(')
            : s.indexOf('Widget _weeklyCountBadge(');
        expect(i, greaterThan(-1), reason: p);
        final body = s.substring(i, (i + 900).clamp(0, s.length));
        for (final banned in [
          'AppColors.successDark',
          'AppColors.infoDark',
          'AppColors.warningDark',
        ]) {
          expect(body.contains(banned), false, reason: '$p / $banned');
        }
        expect(body.contains('AppColors.grey600'), true, reason: p);
      }
    });

    test('12-b 숫자 자체는 그대로 보여 준다 — 정보를 숨기지 않았다', () {
      expect(_codeOf(_src(workPath)).contains("'주\$count회'"), true);
    });
  });
}
