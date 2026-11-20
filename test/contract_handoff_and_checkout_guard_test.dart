// [CONTRACT-HANDOFF.5] B2 앱 일괄 퇴근 · B3 계약 권한 없는 확정/승인 담당자 안내 (2026-10-25)
//
//   B2  출근 기록이 없는 근태를 일괄 퇴근에 실어 보내지 않는다 — 예전에는 `checkIn ?? 예정 시작`으로
//       근무시간을 만들어 보냈다(일하지 않은 사람에게 근무시간). 서버(후보)도 notCheckedIn 으로 건너뛰고,
//       결과 문구는 그 근무 건수를 말한다.
//   B3  계약 권한이 없는 담당자에게 "계약서를 작성해 주세요"라고 하지 않는다 — 발송 대기와 인계처
//       (계약 권한자가 홈 '계약 미발송'에서 보냄)를 말한다. 권한을 넓히지 않는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/screens/business_admin/dialogs/attendance_status_dialog.dart';

String _src(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');
String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

void main() {
  group('B2 결과 문구 — 서버가 건너뛴 이유를 말한다', () {
    test('notCheckedIn 건수를 붙인다', () {
      final note = AttendanceStatusDialog.checkoutFailureNote({
        'processed': 1,
        'failed': 2,
        'failures': [
          {'attendanceId': 'a', 'reason': 'notCheckedIn'},
          {'attendanceId': 'b', 'reason': 'wageAlreadySettled'},
        ],
      });
      // 이 화면의 수치 단위는 근무 건이다(attendance_count_unit_contract_test ACU).
      expect(note, contains('출근 기록이 없어 건너뛴 근무 1건'));
    });
    test('다른 사유만 있으면 붙이지 않는다 · 모양이 다르면 지어내지 않는다', () {
      expect(AttendanceStatusDialog.checkoutFailureNote({'failures': [{'reason': 'futureDate'}]}), '');
      expect(AttendanceStatusDialog.checkoutFailureNote(null), '');
      expect(AttendanceStatusDialog.checkoutFailureNote({'failures': 'x'}), '');
    });
  });

  group('B2 일괄 퇴근 두 경로 — 출근 기록 없음을 예정 시작으로 메우지 않는다', () {
    final s = _src('lib/screens/business_admin/dialogs/attendance_status_dialog.dart');
    String body(String decl) {
      final i = s.indexOf(decl);
      expect(i, greaterThan(-1), reason: decl);
      return s.substring(i, s.indexOf('\n  }\n', i));
    }

    for (final decl in [
      'Future<void> _processBatchCheckOut(String time,',
      'Future<void> _processBatchCheckOutByGroup(',
    ]) {
      test(decl, () {
        final b = _flat(body(decl));
        expect(b.contains('if (attendance.checkIn == null) {'), isTrue);
        expect(b.contains('attendance.checkIn ?? WorkDetailHelper.effectiveStart'), isFalse,
            reason: '예정 시작 대입이 남아 있으면 일하지 않은 사람에게 근무시간이 생긴다');
        expect(b.contains('_checkoutFailureNote(result.data)'), isTrue);
      });
    }
  });

  group('B3 계약 권한 없는 담당자 — 발송 대기·인계처를 말한다', () {
    test('일별 지원자 확정(개별·일괄)', () {
      final s = _flat(_src('lib/screens/business_admin/dialogs/day_applicants_dialog.dart'));
      expect(s.contains("if (_canForSelectedBiz((p) => p.canManageContract)) { ToastHelper.showSuccess('확정되었습니다. 계약서를 작성해 주세요.');"), isTrue);
      expect(s.contains("계약 권한이 있는 관리자가 홈 '계약 미발송'에서 보낼 수 있어요."), isTrue);
    });
    test('업무별 지원자 확정', () {
      final s = _flat(_src('lib/screens/business_admin/dialogs/work_applicants_dialog.dart'));
      expect(s.contains('if (_canManageContract()) {'), isTrue);
      expect(s.contains("계약서 발송 대기예요. 계약 권한이 있는 관리자가 홈 '계약 미발송'에서 보낼 수 있어요."), isTrue);
    });
    test('지원 검토 승인 — 권한이 없으면 발송 흐름을 열지 않고 인계처를 말한다', () {
      final s = _flat(_src('lib/screens/business_admin/support_review_queue_screen.dart'));
      expect(s.contains('if (worker != null && canContract) {'), isTrue);
      expect(s.contains("} else if (!canContract) {"), isTrue);
      expect(s.contains("확정 완료 — 계약서 발송 대기예요."), isTrue);
    });
    test('인계 목적지(홈 계약 미발송)는 계약 권한자에게만 열린다 — 기존 그대로', () {
      final s = _flat(_src('lib/screens/business_admin/business_admin_home_screen.dart'));
      expect(s.contains("// 4. 계약 미발송 — canManageContract if (_verified(up, (p) => p.canManageContract)) {"), isTrue);
    });
  });
}
