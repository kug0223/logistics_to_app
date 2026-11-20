// [.82] 근로자 일정 달력·목록의 날짜 — 단기 근무의 workDate 는 KST 자정 instant 다.
//
//   근거: Pixel5 DEV 통합 여정(perf-20261028/c82/shots/j34·j35) — 기기 시간대 GMT 에서 11/4 확정 근무가
//   달력 11/3 칸에 찍히고 목록도 '11월 3일 (화)' 로 묶였다. 요약(확정 1건·12,000원)은 맞았다.
//   UTC 로 만든 instant 는 호스트 시간대와 무관하게 GMT 기기와 같은 성분을 갖는다.
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/utils/calendar_helper.dart';

ApplicationModel _app(String id, DateTime workDate) => ApplicationModel(
      id: id,
      toId: 'to_$id',
      uid: 'u1',
      businessId: 'biz1',
      businessName: 'QA',
      toTitle: 'QA',
      status: AppStatus.confirmed,
      selectedWorkType: 'QA 분류',
      startTime: '15:30',
      endTime: '16:30',
      wage: 12000,
      wageType: 'hourly',
      workDate: workDate,
      appliedAt: workDate.subtract(const Duration(days: 1)),
    );

void main() {
  test('S82-1 KST 11/4 0시(= UTC 11/3 15:00) 근무는 11/4 칸에 들어간다', () {
    final idx = CalendarHelper.buildDateIndex([_app('a', DateTime.utc(2026, 11, 3, 15))], AppStatus.confirmed);
    expect(CalendarHelper.getEventsForDayFromIndex(DateTime(2026, 11, 4), idx).map((a) => a.id), ['a']);
    expect(CalendarHelper.getEventsForDayFromIndex(DateTime(2026, 11, 3), idx), isEmpty);
  });

  test('S82-2 KST 기기와 같은 결과 — 월말 경계(KST 12/1 0시 = UTC 11/30 15:00)', () {
    final idx = CalendarHelper.buildDateIndex([_app('b', DateTime.utc(2026, 11, 30, 15))], AppStatus.confirmed);
    expect(CalendarHelper.getEventsForDayFromIndex(DateTime(2026, 12, 1), idx).map((a) => a.id), ['b']);
    expect(CalendarHelper.getEventsForDayFromIndex(DateTime(2026, 11, 30), idx), isEmpty);
  });
}
