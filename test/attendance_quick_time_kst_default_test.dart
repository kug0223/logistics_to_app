// [UI-4] 일괄 출퇴근 '현재' 기본 시각은 KST 벽시계다 — 기기 시간대와 무관.
//
// 재현(LOCAL 에뮬레이터, 기기 GMT): 실제 순간 2026-10-28T17:17Z(KST 10-29 02:17)에
//   퇴근 시트 기본값이 `현재 17:20` 이었고, 그대로 처리하자 서버(callableBatchCheckOut 실핸들러)가
//   checkOut = 2026-10-29T08:20Z(KST 17:20, 15시간 뒤)를 저장했다. 급여 확정 화면은 그 근무를
//   `01:22 ~ 17:20 (실근무 16.0h)` 로 읽었다.
// 아래 순간들은 UTC 로 만들어 기기·호스트 시간대와 무관하게 같은 답을 기대한다.
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/widgets/pickers/attendance_quick_time_sheet.dart';

void main() {
  ({int hour, int minute}) at(String iso) =>
      AttendanceQuickTimeSheet.roundedKstNow(DateTime.parse(iso));

  test('QK-1 재현 순간 17:17Z → KST 02:20 (예전 기기 GMT 기본값 17:20 이 아니다)', () {
    expect(at('2026-10-28T17:17:00Z'), (hour: 2, minute: 20));
  });

  test('QK-2 KST 자정 직전 23:56 → 00:00 (기존 반올림 규칙, 날짜 귀속은 호출자 몫)', () {
    // 14:56Z = KST 23:56. 23:54 는 23:50(반올림 5.4 → 5).
    expect(at('2026-10-29T14:56:00Z'), (hour: 0, minute: 0));
    expect(at('2026-10-29T14:54:00Z'), (hour: 23, minute: 50));
  });

  test('QK-3 KST 자정 직후 00:04 → 00:00', () {
    // 15:04Z = KST 00:04 (다음 날)
    expect(at('2026-10-29T15:04:00Z'), (hour: 0, minute: 0));
  });

  test('QK-4 야간 퇴근 시각 KST 05:36 → 05:40', () {
    // 20:36Z = KST 05:36
    expect(at('2026-10-29T20:36:00Z'), (hour: 5, minute: 40));
  });

  test('QK-5 같은 순간을 지역 시각 객체로 줘도 같은 답(시간대 독립)', () {
    final utc = DateTime.parse('2026-10-28T17:17:00Z');
    expect(AttendanceQuickTimeSheet.roundedKstNow(utc.toLocal()),
        (hour: 2, minute: 20));
  });
}
