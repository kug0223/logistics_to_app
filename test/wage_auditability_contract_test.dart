// [PREDEVICE-ATTENDANCE-WAGE.3] 돈을 확정하는 사람이 판단할 수 있어야 한다
//
// 이번 수정은 계산 규칙을 하나도 바꾸지 않는다. 바꾼 것은 세 가지 가시성이다.
//
//   1. 급여 확정 화면이 근무자가 실제로 누른 시각을 보여주지 않았다.
//      사업장 근태 기준이 적용되면 09:06 출근이 09:30으로, 18:30 퇴근이
//      18:00으로 계산된다. 금액을 정하는 자리에서 그 차이를 볼 수 없으면
//      관리자는 실제 근무를 확인할 근거도, 보정할 이유도 알 수 없다.
//
//   2. 근태 시간 수정은 곧 금액 변경인데 사유가 남지 않았다. 누가·언제는
//      있었지만 왜가 없어, 나중에 그 금액이 맞았는지 재구성할 수 없었다.
//      modifyReason은 이미 모델에도 있고 월별 상세 화면이 이미 읽고 있었다 —
//      writer만 비어 있었다.
//
//   3. 일을 마쳤지만 금액이 확정되기 전인 하루는 예상수입에서도(출근했으므로)
//      실수입에서도(확정 전이므로) 빠져, 근로자에게는 사라진 것처럼 보였다.
//      확정 전 금액을 확정 금액인 양 더하지 않고 건수만 말한다.
//
// DEV runtime: 사유 없는 시간 변경은 쓰기 전에 400으로 거절, 같은 값 재전송은
// 사유 없이 통과, 사유와 함께 수정하면 originalCheckIn 09:06 유지 · checkIn
// 09:00 적용 · modifyReason 저장 · wageStatus pending 복귀 · finalWage 삭제,
// 재계산 시 payable 480분 · confirmed는 skip.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';
const _wageDialogPath =
    'lib/screens/business_admin/dialogs/wage_confirm_dialog.dart';
const _attDialogPath =
    'lib/screens/business_admin/dialogs/attendance_status_dialog.dart';
const _calendarPath = 'lib/utils/calendar_helper.dart';
const _homePath = 'lib/screens/user/user_home_screen.dart';
const _incomePath = 'lib/screens/user/income_detail_screen.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  final fns = _src(_fnsPath);
  final fnsCode = _codeOf(fns);
  final fnsFlat = _flat(fnsCode);

  group('급여 확정 화면이 원본 펀치를 보여준다', () {
    final dialog = _src(_wageDialogPath);
    final code = _codeOf(dialog);
    final flat = _flat(code);

    test('원본과 적용 시각이 다를 때만 그린다', () {
      expect(flat.contains('Widget _buildPunchDivergenceRow('), true);
      expect(flat.contains('if (parts.isEmpty) return const SizedBox.shrink();'),
          true, reason: '같은 값을 두 줄로 반복하지 않는다');
      expect(flat.contains("rawIn != appliedIn"), true);
      expect(flat.contains("rawOut != appliedOut"), true,
          reason: '연장 clamp도 같은 방식으로 드러나야 한다');
    });

    test('근무자 목록의 두 표시 지점 모두에 붙는다', () {
      expect('_buildPunchDivergenceRow(context, attendance)'.allMatches(flat).length,
          2, reason: '한 곳만 고치면 다른 목록에서는 여전히 보이지 않는다');
    });

    test('적용 시각이 기준이라는 사실을 흐리지 않는다', () {
      expect(code.contains('사업장 근태 기준 시간으로 계산'), true);
      // 법적 정당성을 주장하는 문구를 쓰지 않는다.
      expect(code.contains('법적으로'), false);
      expect(code.contains('법정'), false);
      // 내부 필드명을 그대로 노출하지 않는다.
      expect(code.contains("'originalCheckIn'"), false);
    });
  });

  group('근태 수정에는 사유가 남는다', () {
    test('서버가 쓰기 전에 사유를 요구한다 — 실제로 바뀌는 건만', () {
      expect(fnsFlat.contains('const ADJUST_REASON_MAX = 200;'), true);
      expect(fnsFlat.contains('"근태 시간을 바꾸려면 수정 사유가 필요합니다."'), true);
      expect(fnsFlat.contains('if (!changesIn && !changesOut) continue;'), true,
          reason: '같은 값 재전송에 사유를 요구하면 운영만 느려진다');
    });

    test('canonical 필드를 재사용한다 — 새 이름을 만들지 않는다', () {
      expect(fnsFlat.contains('updates["modifyReason"] = adjReason'), true,
          reason: 'modifyReason은 모델과 월별 상세 화면이 이미 쓰던 필드다');
    });

    test('사유는 시각이 실제로 바뀐 건에만 저장된다', () {
      expect(fnsFlat.contains('if (didChangeTime && adjReason.length > 0)'), true);
    });

    test('클라이언트가 사유를 받아 보낸다 — 서버만 막고 끝내지 않는다', () {
      final att = _flat(_codeOf(_src(_attDialogPath)));
      expect(att.contains("title: '근태 수정 사유'"), true);
      expect(att.contains("e['reason'] = reason.trim();"), true);
      expect(att.contains('if (reason == null || reason.trim().isEmpty) {'), true,
          reason: '취소하면 아무것도 바꾸지 않아야 한다');
    });

    test('수정 불가 상태는 사유를 묻기 전에 걸러진다', () {
      final att = _flat(_codeOf(_src(_attDialogPath)));
      final filterAt = att.indexOf('attendance.wageStatus == AttendanceModel.wageConfirmed');
      final askAt = att.indexOf("title: '근태 수정 사유'");
      expect(filterAt > 0 && askAt > filterAt, true,
          reason: '사유를 다 입력한 뒤 마지막에 실패시키지 않는다');
    });
  });

  group('일했지만 확정 전인 근무를 사라지게 두지 않는다', () {
    final cal = _codeOf(_src(_calendarPath));

    test('정산 중 판정은 근태 기준이다 — 지원서 상태로 만들지 않는다', () {
      expect(cal.contains('static bool isSettlementPending(AttendanceModel att)'),
          true);
      expect(cal.contains('if (att.checkInAt == null) return false;'), true,
          reason: '실제 근무가 있어야 정산 대상이다');
      expect(cal.contains('if (isNonEarning(att)) return false;'), true,
          reason: 'NO_SHOW·결근은 정산 중이 아니다');
      expect(
        _flat(cal).contains(
            'return att.wageStatus != AttendanceModel.wageConfirmed && '
            'att.wageStatus != AttendanceModel.wageTransferred;'),
        true,
      );
    });

    test('금액을 어느 합계에도 더하지 않는다 — 건수만', () {
      final home = _flat(_codeOf(_src(_homePath)));
      expect(home.contains('final wageTotal = wageCompleted + wageScheduled;'),
          true, reason: '정산 중 금액이 합계에 섞이면 확정 금액처럼 읽힌다');
      expect(home.contains("value: '\$settlementPending건'"), true);
    });

    test('0건이면 줄을 만들지 않는다', () {
      final home = _flat(_codeOf(_src(_homePath)));
      expect(home.contains('if (!_isLoadingData && settlementPending > 0)'), true);
    });

    test('홈에서 본 사실을 수입 상세에서도 확인할 수 있다', () {
      final income = _flat(_codeOf(_src(_incomePath)));
      expect(income.contains("label: '정산 중'"), true);
      expect(income.contains('int get _settlementPending =>'), true);
    });

    test('조회 실패를 0건이라고 말하지 않는다', () {
      final income = _flat(_codeOf(_src(_incomePath)));
      expect(
        income.contains("(_loadFailed ? '확인 불가' : '\$_settlementPending건')"),
        true,
        reason: 'ERROR를 0건으로 바꾸면 앞선 수정이 무의미해진다',
      );
    });
  });
}
