// [PREDEVICE] 근로자 수입 — 상태별 포함 매트릭스
//
// READ에서 확인된 것:
//   · 예상수입(getTotalIncome, 근무 예정)은 지원서만 보고 셌다.
//   · NO_SHOW는 이력 보존을 위해 application.status를 CONFIRMED로 그대로 둔다
//     (index.ts: "status 변경 금지 — NO_SHOW 이력 보존").
//   · 그래서 무단결근한 날이 계속 "벌 예정"으로 집계됐다. 관리자는 그 날을
//     finalWage 0으로 이미 마감했는데 근로자 화면에는 벌 돈이 남아 있었다.
//
// 매트릭스 (예상수입 / 실수입):
//   future confirmed        포함 / 미포함
//   worked + wage pending   미포함(출근함) / 미포함(아직 확정 전)
//   worked + wage confirmed 미포함(출근함) / 포함
//   transferred             미포함(출근함) / 포함
//   NO_SHOW                 미포함 / 미포함
//   ABSENT                  미포함 / 미포함
//   pre-shift canceled      미포함(상태가 confirmedStatuses 아님) / 미포함(기록 없음)
//
// 실수입(getConfirmedIncome)은 wageStatus confirmed·transferred만 센다.
// NO_SHOW·결근은 finalWage 0이라 더해도 0이지만, 예상수입 쪽이 문제였다.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/utils/calendar_helper.dart';
import 'package:flutter_test/flutter_test.dart';

AttendanceModel _att({
  required String appId,
  required DateTime workDate,
  DateTime? checkIn,
  String status = AttendanceModel.statusPresent,
  String wageStatus = AttendanceModel.wagePending,
  int? finalWage,
}) {
  return AttendanceModel.fromMap({
    'applicationId': appId,
    'userId': 'w1',
    'businessId': 'b1',
    'businessName': '테스트',
    'workDate': Timestamp.fromDate(workDate),
    'checkIn': checkIn == null ? null : Timestamp.fromDate(checkIn),
    'status': status,
    'wageStatus': wageStatus,
    'finalWage': finalWage,
    'createdAt': Timestamp.fromDate(workDate),
  }, '${appId}_x');
}

void main() {
  final month = DateTime(2026, 7, 15);
  final day = DateTime(2026, 7, 10);

  group('isNonEarning — 벌 돈이 0으로 마감된 날', () {
    test('NO_SHOW와 결근만 해당한다', () {
      expect(
        CalendarHelper.isNonEarning(
            _att(appId: 'a', workDate: day, status: AttendanceModel.statusNoShow)),
        true,
      );
      expect(
        CalendarHelper.isNonEarning(
            _att(appId: 'a', workDate: day, status: AttendanceModel.statusAbsent)),
        true,
      );
      for (final s in [
        AttendanceModel.statusPresent,
        AttendanceModel.statusLate,
        AttendanceModel.statusEarlyLeave,
      ]) {
        expect(
          CalendarHelper.isNonEarning(
              _att(appId: 'a', workDate: day, status: s)),
          false,
          reason: '$s 는 실제 근무다',
        );
      }
    });
  });

  group('isScheduledIncome — 아직 벌 예정인가', () {
    test('근태 기록이 없으면 벌 예정이다 (future confirmed)', () {
      final app = _fakeApp('a1');
      expect(CalendarHelper.isScheduledIncome(app, const []), true);
    });

    test('이미 출근했으면 벌 예정이 아니다 — 확정수입 쪽에서 센다', () {
      final app = _fakeApp('a1');
      final atts = [
        _att(appId: 'a1', workDate: day, checkIn: day.add(const Duration(hours: 9))),
      ];
      expect(CalendarHelper.isScheduledIncome(app, atts), false);
    });

    test('NO_SHOW면 벌 예정이 아니다 — 지원서는 CONFIRMED로 남아 있어도', () {
      final app = _fakeApp('a1');
      final atts = [
        _att(
            appId: 'a1',
            workDate: day,
            status: AttendanceModel.statusNoShow,
            wageStatus: AttendanceModel.wageConfirmed,
            finalWage: 0),
      ];
      expect(CalendarHelper.isScheduledIncome(app, atts), false,
          reason: '벌 돈이 0으로 마감된 날을 벌 예정으로 세면 안 된다');
    });

    test('결근도 벌 예정이 아니다', () {
      final app = _fakeApp('a1');
      final atts = [
        _att(
            appId: 'a1',
            workDate: day,
            status: AttendanceModel.statusAbsent,
            wageStatus: AttendanceModel.wageConfirmed,
            finalWage: 0),
      ];
      expect(CalendarHelper.isScheduledIncome(app, atts), false);
    });

    test('다른 지원서의 근태는 영향을 주지 않는다', () {
      final app = _fakeApp('a1');
      final atts = [
        _att(appId: 'OTHER', workDate: day, status: AttendanceModel.statusNoShow),
      ];
      expect(CalendarHelper.isScheduledIncome(app, atts), true);
    });
  });

  group('getTotalIncome — 예상수입', () {
    test('근태를 주지 않으면 지원서만으로 센다 (기존 동작 보존)', () {
      final app = _fakeApp('a1', wage: 100000, wageType: 'daily');
      expect(CalendarHelper.getTotalIncome([app], month), 100000);
    });

    test('NO_SHOW 날은 예상수입에서 빠진다', () {
      final app = _fakeApp('a1', wage: 100000, wageType: 'daily');
      final atts = [
        _att(
            appId: 'a1',
            workDate: day,
            status: AttendanceModel.statusNoShow,
            wageStatus: AttendanceModel.wageConfirmed,
            finalWage: 0),
      ];
      expect(
        CalendarHelper.getTotalIncome([app], month, attendances: atts),
        0,
        reason: '결근한 날의 돈이 예상수입에 남아 있으면 안 된다',
      );
    });

    test('출근한 날도 예상수입에서 빠진다 — 실수입과 이중 계상 금지', () {
      final app = _fakeApp('a1', wage: 100000, wageType: 'daily');
      final atts = [
        _att(
            appId: 'a1',
            workDate: day,
            checkIn: day.add(const Duration(hours: 9)),
            wageStatus: AttendanceModel.wageConfirmed,
            finalWage: 95000),
      ];
      expect(CalendarHelper.getTotalIncome([app], month, attendances: atts), 0);
    });
  });

  group('getConfirmedIncome — 실수입', () {
    test('confirmed와 transferred만 센다', () {
      final atts = [
        _att(
            appId: 'a1',
            workDate: day,
            checkIn: day,
            wageStatus: AttendanceModel.wageConfirmed,
            finalWage: 50000),
        _att(
            appId: 'a2',
            workDate: day,
            checkIn: day,
            wageStatus: AttendanceModel.wageTransferred,
            finalWage: 30000),
        // calculated — 아직 확정 전이므로 제외
        _att(
            appId: 'a3',
            workDate: day,
            checkIn: day,
            wageStatus: AttendanceModel.wageCalculated,
            finalWage: 70000),
        // pending — 제외
        _att(appId: 'a4', workDate: day, checkIn: day, finalWage: 70000),
      ];
      expect(CalendarHelper.getConfirmedIncome(atts, month), 80000);
    });

    test('NO_SHOW는 finalWage 0이라 실수입을 늘리지 않는다', () {
      final atts = [
        _att(
            appId: 'a1',
            workDate: day,
            status: AttendanceModel.statusNoShow,
            wageStatus: AttendanceModel.wageConfirmed,
            finalWage: 0),
      ];
      expect(CalendarHelper.getConfirmedIncome(atts, month), 0);
    });
  });
}

/// 테스트용 최소 지원서 — 단기 확정, 2026-07-10 근무.
ApplicationModel _fakeApp(
  String id, {
  int wage = 10000,
  String wageType = 'daily',
}) {
  final d = DateTime(2026, 7, 10);
  return ApplicationModel.fromMap({
    'uid': 'w1',
    'businessId': 'b1',
    'status': AppStatus.confirmed,
    'type': AppType.shortTerm,
    'workDate': Timestamp.fromDate(d),
    'appliedAt': Timestamp.fromDate(d),
    'startTime': '09:00',
    'endTime': '18:00',
    'wage': wage,
    'wageType': wageType,
    'selectedWorkType': '사무업무',
  }, id);
}
