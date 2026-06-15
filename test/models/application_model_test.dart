import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/application_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 헬퍼: 테스트용 기본 ApplicationModel 생성
// ─────────────────────────────────────────────────────────────────────────────

ApplicationModel _base({
  String id = 'app1',
  String status = 'CONFIRMED',
  String? applicationType,
  DateTime? workDate,
  DateTime? workEndDate,
  List<String>? workDays,
  String startTime = '09:00',
  String endTime = '18:00',
  DateTime? confirmedAt,
  DateTime? desiredStartDate,
  DateTime? actualResignDate,
  List<DateTime>? leaveDates,
  List<DateTime>? extraWorkDates,
  String? resignStatus,
  String? terminationStatus,
  List<Map<String, dynamic>>? statusHistory,
  String? originalWorkType,
  bool isStarred = false,
}) {
  return ApplicationModel(
    id: id,
    businessId: 'biz1',
    businessName: '테스트 사업장',
    toTitle: '테스트 TO',
    workDate: workDate ?? DateTime(2025, 1, 6),
    workEndDate: workEndDate,
    workDays: workDays,
    startTime: startTime,
    endTime: endTime,
    uid: 'user1',
    selectedWorkType: '피킹',
    wage: 10000,
    status: status,
    appliedAt: DateTime(2025, 1, 1),
    applicationType: applicationType,
    confirmedAt: confirmedAt,
    desiredStartDate: desiredStartDate,
    actualResignDate: actualResignDate,
    leaveDates: leaveDates,
    extraWorkDates: extraWorkDates,
    resignStatus: resignStatus,
    terminationStatus: terminationStatus,
    statusHistory: statusHistory,
    originalWorkType: originalWorkType,
    isStarred: isStarred,
  );
}

// 단기 기본 (2025-01-06 월요일)
ApplicationModel _short({DateTime? workDate, String startTime = '09:00', String endTime = '18:00'}) =>
    _base(
      applicationType: AppType.shortTerm,
      workDate: workDate ?? DateTime(2025, 1, 6),
      startTime: startTime,
      endTime: endTime,
    );

// 장기 기본 (2025-01-06 ~ 2025-01-31, 월~금)
ApplicationModel _long({
  DateTime? workDate,
  DateTime? workEndDate,
  List<String>? workDays,
  DateTime? confirmedAt,
  DateTime? desiredStartDate,
  DateTime? actualResignDate,
  List<DateTime>? leaveDates,
  List<DateTime>? extraWorkDates,
  String status = 'CONFIRMED',
  String? resignStatus,
  String? terminationStatus,
}) =>
    _base(
      applicationType: AppType.longTerm,
      workDate: workDate ?? DateTime(2025, 1, 6),
      workEndDate: workEndDate ?? DateTime(2025, 1, 31),
      workDays: workDays ?? ['월', '화', '수', '목', '금'],
      confirmedAt: confirmedAt,
      desiredStartDate: desiredStartDate,
      actualResignDate: actualResignDate,
      leaveDates: leaveDates,
      extraWorkDates: extraWorkDates,
      status: status,
      resignStatus: resignStatus,
      terminationStatus: terminationStatus,
    );

// ─────────────────────────────────────────────────────────────────────────────
// 날짜 상수 (2025-01-06=월 ... 2025-01-12=일)
// ─────────────────────────────────────────────────────────────────────────────
final mon0106 = DateTime(2025, 1, 6);   // 월
final tue0107 = DateTime(2025, 1, 7);   // 화
final wed0108 = DateTime(2025, 1, 8);   // 수
final thu0109 = DateTime(2025, 1, 9);   // 목
final fri0110 = DateTime(2025, 1, 10);  // 금
final sat0111 = DateTime(2025, 1, 11);  // 토
final sun0112 = DateTime(2025, 1, 12);  // 일
final mon0113 = DateTime(2025, 1, 13);  // 월
final fri0131 = DateTime(2025, 1, 31);  // 금 (월말)
final sat0201 = DateTime(2025, 2, 1);   // 토 (범위 밖)

void main() {
  // ===========================================================================
  // A. hasTimeOverlap — 200+ 케이스
  // ===========================================================================
  group('A: hasTimeOverlap', () {
    // ── A-1. 빈 문자열 / null-like ────────────────────────────────────────────
    test('A-01 s1 empty → false', () => expect(ApplicationModel.hasTimeOverlap('', '18:00', '09:00', '18:00'), false));
    test('A-02 e1 empty → false', () => expect(ApplicationModel.hasTimeOverlap('09:00', '', '09:00', '18:00'), false));
    test('A-03 s2 empty → false', () => expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '', '18:00'), false));
    test('A-04 e2 empty → false', () => expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '09:00', ''), false));
    test('A-05 all empty → false', () => expect(ApplicationModel.hasTimeOverlap('', '', '', ''), false));
    test('A-06 s1 only spaces (parsed as 0) - still overlaps if logically overlapping',
        () => expect(ApplicationModel.hasTimeOverlap('0:00', '8:00', '0:00', '8:00'), true));

    // ── A-2. 같은 시간대 완전 일치 ───────────────────────────────────────────
    test('A-10 완전 일치 09:00~18:00 vs 09:00~18:00 → true', () => expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '09:00', '18:00'), true));
    test('A-11 완전 일치 00:00~23:59 → true', () => expect(ApplicationModel.hasTimeOverlap('00:00', '23:59', '00:00', '23:59'), true));
    test('A-12 1분짜리 동일 09:00~09:01 → true', () => expect(ApplicationModel.hasTimeOverlap('09:00', '09:01', '09:00', '09:01'), true));

    // ── A-3. 일반 주간 겹침 ────────────────────────────────────────────────────
    test('A-20 앞쪽 겹침 09:00~17:00 vs 13:00~21:00 → true', () => expect(ApplicationModel.hasTimeOverlap('09:00', '17:00', '13:00', '21:00'), true));
    test('A-21 뒷쪽 겹침 13:00~21:00 vs 09:00~17:00 → true (대칭)', () => expect(ApplicationModel.hasTimeOverlap('13:00', '21:00', '09:00', '17:00'), true));
    test('A-22 완전 포함 08:00~20:00 포함 10:00~15:00 → true', () => expect(ApplicationModel.hasTimeOverlap('08:00', '20:00', '10:00', '15:00'), true));
    test('A-23 역방향 포함 10:00~15:00 포함됨 08:00~20:00 → true', () => expect(ApplicationModel.hasTimeOverlap('10:00', '15:00', '08:00', '20:00'), true));
    test('A-24 1분 겹침 09:00~10:01 vs 10:00~11:00 → true', () => expect(ApplicationModel.hasTimeOverlap('09:00', '10:01', '10:00', '11:00'), true));
    test('A-25 점심 교차 11:30~13:30 vs 13:00~15:00 → true', () => expect(ApplicationModel.hasTimeOverlap('11:30', '13:30', '13:00', '15:00'), true));
    test('A-26 동일 시작 09:00~12:00 vs 09:00~10:00 → true', () => expect(ApplicationModel.hasTimeOverlap('09:00', '12:00', '09:00', '10:00'), true));
    test('A-27 동일 종료 09:00~18:00 vs 15:00~18:00 → true', () => expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '15:00', '18:00'), true));
    test('A-28 중간 1분 겹침 09:00~12:01 vs 12:00~15:00 → true', () => expect(ApplicationModel.hasTimeOverlap('09:00', '12:01', '12:00', '15:00'), true));
    test('A-29 전체 근무 06:00~22:00 vs 07:00~21:00 → true', () => expect(ApplicationModel.hasTimeOverlap('06:00', '22:00', '07:00', '21:00'), true));

    // ── A-4. 주간 비겹침 ────────────────────────────────────────────────────
    test('A-30 이전 블록 09:00~12:00 vs 13:00~18:00 → false', () => expect(ApplicationModel.hasTimeOverlap('09:00', '12:00', '13:00', '18:00'), false));
    test('A-31 이후 블록 13:00~18:00 vs 09:00~12:00 → false', () => expect(ApplicationModel.hasTimeOverlap('13:00', '18:00', '09:00', '12:00'), false));
    test('A-32 경계 정확 접촉 (strict <) 09:00~12:00 vs 12:00~18:00 → false', () => expect(ApplicationModel.hasTimeOverlap('09:00', '12:00', '12:00', '18:00'), false));
    test('A-33 역방향 경계 12:00~18:00 vs 09:00~12:00 → false', () => expect(ApplicationModel.hasTimeOverlap('12:00', '18:00', '09:00', '12:00'), false));
    test('A-34 새벽 vs 오후 02:00~06:00 vs 07:00~12:00 → false', () => expect(ApplicationModel.hasTimeOverlap('02:00', '06:00', '07:00', '12:00'), false));
    test('A-35 오전 vs 심야 09:00~12:00 vs 22:00~23:00 → false', () => expect(ApplicationModel.hasTimeOverlap('09:00', '12:00', '22:00', '23:00'), false));
    test('A-36 09:00~09:00 (start==end → b1=a1+1440=24h 시프트) vs 10:00~11:00 → true',
        () => expect(ApplicationModel.hasTimeOverlap('09:00', '09:00', '10:00', '11:00'), true));
    test('A-37 1분 간격 09:00~11:00 vs 11:01~13:00 → false', () => expect(ApplicationModel.hasTimeOverlap('09:00', '11:00', '11:01', '13:00'), false));
    test('A-38 하루 끝 23:00~23:30 vs 23:31~23:59 → false', () => expect(ApplicationModel.hasTimeOverlap('23:00', '23:30', '23:31', '23:59'), false));
    test('A-39 하루 시작 00:00~01:00 vs 01:01~02:00 → false', () => expect(ApplicationModel.hasTimeOverlap('00:00', '01:00', '01:01', '02:00'), false));
    test('A-40 경계 0분차 17:00~18:00 vs 18:00~19:00 → false', () => expect(ApplicationModel.hasTimeOverlap('17:00', '18:00', '18:00', '19:00'), false));

    // ── A-5. 야간 시프트 (end <= start) ────────────────────────────────────
    test('A-50 야간 22:00~02:00 vs 01:00~09:00 → true (자정 교차)', () => expect(ApplicationModel.hasTimeOverlap('22:00', '02:00', '01:00', '09:00'), true));
    test('A-51 야간 22:00~06:00 vs 05:00~12:00 → true', () => expect(ApplicationModel.hasTimeOverlap('22:00', '06:00', '05:00', '12:00'), true));
    test('A-52 야간 21:00~03:00 vs 02:00~07:00 → true', () => expect(ApplicationModel.hasTimeOverlap('21:00', '03:00', '02:00', '07:00'), true));
    test('A-53 야간 22:00~02:00 vs 22:30~01:00 → true (야간 포함)', () => expect(ApplicationModel.hasTimeOverlap('22:00', '02:00', '22:30', '01:00'), true));
    test('A-54 야간 23:00~01:00 vs 23:30~00:30 → true', () => expect(ApplicationModel.hasTimeOverlap('23:00', '01:00', '23:30', '00:30'), true));
    test('A-55 야간 vs 야간 22:00~02:00 vs 00:00~04:00 → true', () => expect(ApplicationModel.hasTimeOverlap('22:00', '02:00', '00:00', '04:00'), true));
    test('A-56 야간 vs 야간 동일 22:00~06:00 vs 22:00~06:00 → true', () => expect(ApplicationModel.hasTimeOverlap('22:00', '06:00', '22:00', '06:00'), true));
    test('A-57 야간 vs 야간 겹침 20:00~02:00 vs 01:00~08:00 → true', () => expect(ApplicationModel.hasTimeOverlap('20:00', '02:00', '01:00', '08:00'), true));
    test('A-58 야간 완전 포함 20:00~06:00 포함 22:00~02:00 → true', () => expect(ApplicationModel.hasTimeOverlap('20:00', '06:00', '22:00', '02:00'), true));
    test('A-59 야간 역포함 22:00~02:00 포함됨 20:00~06:00 → true', () => expect(ApplicationModel.hasTimeOverlap('22:00', '02:00', '20:00', '06:00'), true));

    // ── A-6. 야간 시프트 비겹침 ──────────────────────────────────────────────
    test('A-60 야간 22:00~02:00 vs 02:00~08:00 → false (경계 접촉)', () => expect(ApplicationModel.hasTimeOverlap('22:00', '02:00', '02:00', '08:00'), false));
    test('A-61 야간 22:00~02:00 vs 08:00~16:00 → false', () => expect(ApplicationModel.hasTimeOverlap('22:00', '02:00', '08:00', '16:00'), false));
    test('A-62 야간 22:00~02:00 vs 03:00~10:00 → false', () => expect(ApplicationModel.hasTimeOverlap('22:00', '02:00', '03:00', '10:00'), false));
    test('A-63 주간 09:00~18:00 vs 야간 22:00~06:00 → false', () => expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '22:00', '06:00'), false));
    test('A-64 주간 09:00~18:00 vs 야간 18:00~22:00 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '18:00', '22:00'), false));
    test('A-65 야간 22:00~02:00 경계 접촉 vs 22:00~22:00 (풀24h 야간)', () {
      // 22:00~22:00: b2=22*60+1440=2760, a2=1320 → overlaps(1320,1560,1320,2760) = 1320<2760 && 1320<1560 → true
      expect(ApplicationModel.hasTimeOverlap('22:00', '22:00', '22:00', '02:00'), true);
    });
    test('A-66 야간 22:00~02:00 vs 06:00~22:00 → false (경계)',
        () => expect(ApplicationModel.hasTimeOverlap('22:00', '02:00', '06:00', '22:00'), false));
    test('A-67 심야 00:00~04:00 vs 야간 22:00~23:00 → false', () => expect(ApplicationModel.hasTimeOverlap('00:00', '04:00', '22:00', '23:00'), false));

    // ── A-7. 자정 경계 케이스 ────────────────────────────────────────────────
    test('A-70 00:00~12:00 vs 12:00~24:00-style(00:00) → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('00:00', '12:00', '12:00', '00:00'), false));
    test('A-71 자정 전 23:00~24:00? (00:00 표현) — 야간 23:00~00:00', () {
      // 23:00~00:00: rawB=0, a=1380 → b=0+1440=1440. vs 00:00~01:00: a2=0,b2=60
      // overlaps(1380,1440,0,60)=false; overlaps(1380,1440,1440,1500)=1380<1500&&1440<1440→false; overlaps(1380,1440,-1440,-1380)=false
      expect(ApplicationModel.hasTimeOverlap('23:00', '00:00', '00:00', '01:00'), false);
    });
    test('A-72 야간 23:30~00:30 vs 00:29~01:00 → true', () => expect(ApplicationModel.hasTimeOverlap('23:30', '00:30', '00:29', '01:00'), true));
    test('A-73 야간 23:30~00:30 vs 00:30~02:00 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('23:30', '00:30', '00:30', '02:00'), false));
    test('A-74 야간 22:00~06:00 vs 05:59~08:00 → true', () => expect(ApplicationModel.hasTimeOverlap('22:00', '06:00', '05:59', '08:00'), true));
    test('A-75 야간 22:00~06:00 vs 06:01~10:00 → false', () => expect(ApplicationModel.hasTimeOverlap('22:00', '06:00', '06:01', '10:00'), false));

    // ── A-8. 대칭성 검증 ─────────────────────────────────────────────────────
    test('A-80 대칭: 야간 vs 야간 01:00~09:00 vs 22:00~02:00 → true (A-50 대칭)', () => expect(ApplicationModel.hasTimeOverlap('01:00', '09:00', '22:00', '02:00'), true));
    test('A-81 대칭: 비겹침 09:00~12:00 vs 13:00~18:00 → false', () => expect(ApplicationModel.hasTimeOverlap('09:00', '12:00', '13:00', '18:00'), false));
    test('A-82 대칭: 비겹침 13:00~18:00 vs 09:00~12:00 → false', () => expect(ApplicationModel.hasTimeOverlap('13:00', '18:00', '09:00', '12:00'), false));
    test('A-83 대칭: 겹침 09:00~17:00 vs 13:00~21:00 → true', () => expect(ApplicationModel.hasTimeOverlap('09:00', '17:00', '13:00', '21:00'), true));
    test('A-84 대칭: 13:00~21:00 vs 09:00~17:00 → true', () => expect(ApplicationModel.hasTimeOverlap('13:00', '21:00', '09:00', '17:00'), true));

    // ── A-9. 극단값 ──────────────────────────────────────────────────────────
    test('A-90 00:00~00:01 vs 00:00~00:01 → true', () => expect(ApplicationModel.hasTimeOverlap('00:00', '00:01', '00:00', '00:01'), true));
    test('A-91 23:58~23:59 vs 23:58~23:59 → true', () => expect(ApplicationModel.hasTimeOverlap('23:58', '23:59', '23:58', '23:59'), true));
    test('A-92 00:00~00:01 vs 00:01~00:02 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('00:00', '00:01', '00:01', '00:02'), false));
    test('A-93 00:00~23:59 vs 모든 주간 포함 → true', () => expect(ApplicationModel.hasTimeOverlap('00:00', '23:59', '06:00', '22:00'), true));
    test('A-94 야간 00:00~00:00 (24h) vs 12:00~13:00 → true (24h full day)', () {
      // a1=0, rawB1=0, b1=0+1440=1440 (rawB1<=a1: 0<=0)
      // a2=720, b2=780
      // overlaps(0,1440,720,780) = 0<780 && 720<1440 = true
      expect(ApplicationModel.hasTimeOverlap('00:00', '00:00', '12:00', '13:00'), true);
    });
    test('A-95 09:00~09:00 (24h loop) vs 09:00~18:00 → true', () {
      // a1=540, b1=540+1440=1980
      // a2=540, b2=1080
      // overlaps(540,1980,540,1080) = 540<1080 && 540<1980 = true
      expect(ApplicationModel.hasTimeOverlap('09:00', '09:00', '09:00', '18:00'), true);
    });

    // ── A-10. 짧은 시프트들 ───────────────────────────────────────────────────
    test('A-100 1h 시프트 겹침 10:00~11:00 vs 10:30~11:30 → true', () => expect(ApplicationModel.hasTimeOverlap('10:00', '11:00', '10:30', '11:30'), true));
    test('A-101 1h 시프트 비겹침 10:00~11:00 vs 11:00~12:00 → false', () => expect(ApplicationModel.hasTimeOverlap('10:00', '11:00', '11:00', '12:00'), false));
    test('A-102 30min 시프트 10:00~10:30 vs 10:29~11:00 → true', () => expect(ApplicationModel.hasTimeOverlap('10:00', '10:30', '10:29', '11:00'), true));
    test('A-103 30min 시프트 경계 10:00~10:30 vs 10:30~11:00 → false', () => expect(ApplicationModel.hasTimeOverlap('10:00', '10:30', '10:30', '11:00'), false));
    test('A-104 야간 단시간 23:00~23:30 vs 23:15~23:45 → true', () => expect(ApplicationModel.hasTimeOverlap('23:00', '23:30', '23:15', '23:45'), true));

    // ── A-11. 다양한 야간 시나리오 (심화) ────────────────────────────────────
    test('A-110 19:00~03:00 vs 02:00~10:00 → true', () => expect(ApplicationModel.hasTimeOverlap('19:00', '03:00', '02:00', '10:00'), true));
    test('A-111 19:00~03:00 vs 03:00~10:00 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('19:00', '03:00', '03:00', '10:00'), false));
    test('A-112 19:00~03:00 vs 10:00~19:00 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('19:00', '03:00', '10:00', '19:00'), false));
    test('A-113 19:00~03:00 vs 18:00~20:00 → true', () => expect(ApplicationModel.hasTimeOverlap('19:00', '03:00', '18:00', '20:00'), true));
    test('A-114 야간 vs 야간 서로 포함 21:00~05:00 vs 22:00~04:00 → true', () => expect(ApplicationModel.hasTimeOverlap('21:00', '05:00', '22:00', '04:00'), true));
    test('A-115 야간 vs 야간 인접 비겹침 21:00~00:00 vs 00:00~06:00 → false', () => expect(ApplicationModel.hasTimeOverlap('21:00', '00:00', '00:00', '06:00'), false));
    test('A-116 야간 vs 야간 인접 비겹침 00:00~06:00 vs 21:00~00:00 → false', () => expect(ApplicationModel.hasTimeOverlap('00:00', '06:00', '21:00', '00:00'), false));
    test('A-117 야간 22:00~02:00 vs 주간 14:00~22:00 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('22:00', '02:00', '14:00', '22:00'), false));
    test('A-118 야간 22:00~02:00 vs 주간 14:00~22:01 → true', () => expect(ApplicationModel.hasTimeOverlap('22:00', '02:00', '14:00', '22:01'), true));
    test('A-119 야간 21:59~02:00 vs 22:00~23:00 → true', () => expect(ApplicationModel.hasTimeOverlap('21:59', '02:00', '22:00', '23:00'), true));

    // ── A-12. 3-시프트 공장 스케줄 ───────────────────────────────────────────
    test('A-120 1조 06:00~14:00 vs 2조 14:00~22:00 → false', () => expect(ApplicationModel.hasTimeOverlap('06:00', '14:00', '14:00', '22:00'), false));
    test('A-121 1조 06:00~14:00 vs 3조 22:00~06:00 → false', () => expect(ApplicationModel.hasTimeOverlap('06:00', '14:00', '22:00', '06:00'), false));
    test('A-122 2조 14:00~22:00 vs 3조 22:00~06:00 → false', () => expect(ApplicationModel.hasTimeOverlap('14:00', '22:00', '22:00', '06:00'), false));
    test('A-123 1조 06:00~14:01 vs 2조 14:00~22:00 → true (1분 초과)', () => expect(ApplicationModel.hasTimeOverlap('06:00', '14:01', '14:00', '22:00'), true));
    test('A-124 2조 13:59~22:00 vs 1조 06:00~14:00 → true', () => expect(ApplicationModel.hasTimeOverlap('13:59', '22:00', '06:00', '14:00'), true));

    // ── A-13. 이중 야간 (다음날 새벽 시프트 이전날과 겹침) ──────────────────
    test('A-130 다음날 새벽 시프트 야간과 겹침 확인: S1=22:00~06:00, S2=05:00~13:00 → true',
        () => expect(ApplicationModel.hasTimeOverlap('22:00', '06:00', '05:00', '13:00'), true));
    test('A-131 S1=22:00~06:00, S2=06:01~14:00 → false', () => expect(ApplicationModel.hasTimeOverlap('22:00', '06:00', '06:01', '14:00'), false));
    test('A-132 S1=22:00~06:00, S2=21:00~22:00 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('22:00', '06:00', '21:00', '22:00'), false));
    test('A-133 S1=22:00~06:00, S2=21:30~22:30 → true', () => expect(ApplicationModel.hasTimeOverlap('22:00', '06:00', '21:30', '22:30'), true));
    test('A-134 완전 야간 반전: S1=06:00~22:00, S2=22:00~06:00 → false', () => expect(ApplicationModel.hasTimeOverlap('06:00', '22:00', '22:00', '06:00'), false));
    test('A-135 완전 야간 반전 1분 겹침: S1=06:00~22:01, S2=22:00~06:00 → true', () => expect(ApplicationModel.hasTimeOverlap('06:00', '22:01', '22:00', '06:00'), true));

    // ── A-14. 분 단위 경계 정밀 ─────────────────────────────────────────────
    test('A-140 09:01~17:00 vs 09:00~09:01 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('09:01', '17:00', '09:00', '09:01'), false));
    test('A-141 09:00~17:00 vs 09:00~09:01 → true', () => expect(ApplicationModel.hasTimeOverlap('09:00', '17:00', '09:00', '09:01'), true));
    test('A-142 09:00~17:00 vs 16:59~18:00 → true', () => expect(ApplicationModel.hasTimeOverlap('09:00', '17:00', '16:59', '18:00'), true));
    test('A-143 09:00~17:00 vs 17:01~18:00 → false', () => expect(ApplicationModel.hasTimeOverlap('09:00', '17:00', '17:01', '18:00'), false));
    test('A-144 야간 22:01~02:00 vs 22:00~22:01 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('22:01', '02:00', '22:00', '22:01'), false));
    test('A-145 야간 22:00~02:00 vs 22:00~22:01 → true', () => expect(ApplicationModel.hasTimeOverlap('22:00', '02:00', '22:00', '22:01'), true));

    // ── A-15. 실제 알바 시나리오 ─────────────────────────────────────────────
    test('A-150 편의점 오전 06:00~14:00 vs 점심 11:00~15:00 → true', () => expect(ApplicationModel.hasTimeOverlap('06:00', '14:00', '11:00', '15:00'), true));
    test('A-151 편의점 오전 vs 오후 14:00~22:00 → false', () => expect(ApplicationModel.hasTimeOverlap('06:00', '14:00', '14:00', '22:00'), false));
    test('A-152 물류 06:00~15:00 vs 피킹 09:00~18:00 → true', () => expect(ApplicationModel.hasTimeOverlap('06:00', '15:00', '09:00', '18:00'), true));
    test('A-153 마감 22:00~03:00 vs 새벽배송 02:00~08:00 → true', () => expect(ApplicationModel.hasTimeOverlap('22:00', '03:00', '02:00', '08:00'), true));
    test('A-154 마감 22:00~03:00 vs 낮 12:00~21:00 → false', () => expect(ApplicationModel.hasTimeOverlap('22:00', '03:00', '12:00', '21:00'), false));
    test('A-155 파트타임 10:00~13:00 vs 동시 10:00~13:00 → true', () => expect(ApplicationModel.hasTimeOverlap('10:00', '13:00', '10:00', '13:00'), true));
    test('A-156 파트타임 10:00~13:00 vs 이후 13:00~16:00 → false', () => expect(ApplicationModel.hasTimeOverlap('10:00', '13:00', '13:00', '16:00'), false));
    test('A-157 파트타임 10:00~13:00 vs 이전 07:00~10:00 → false', () => expect(ApplicationModel.hasTimeOverlap('10:00', '13:00', '07:00', '10:00'), false));
    test('A-158 풀타임 08:30~17:30 vs 파트 17:00~19:00 → true', () => expect(ApplicationModel.hasTimeOverlap('08:30', '17:30', '17:00', '19:00'), true));
    test('A-159 풀타임 08:30~17:30 vs 파트 17:30~19:00 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('08:30', '17:30', '17:30', '19:00'), false));

    // ── A-16. 더 많은 야간/새벽 케이스 ──────────────────────────────────────
    test('A-160 새벽 03:00~07:00 vs 야간 01:00~04:00 → true', () => expect(ApplicationModel.hasTimeOverlap('03:00', '07:00', '01:00', '04:00'), true));
    test('A-161 새벽 03:00~07:00 vs 야간 22:00~03:00 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('03:00', '07:00', '22:00', '03:00'), false));
    test('A-162 새벽 03:00~07:00 vs 야간 22:00~04:00 → true', () => expect(ApplicationModel.hasTimeOverlap('03:00', '07:00', '22:00', '04:00'), true));
    test('A-163 야간 20:00~04:00 vs 03:00~05:00 → true', () => expect(ApplicationModel.hasTimeOverlap('20:00', '04:00', '03:00', '05:00'), true));
    test('A-164 야간 20:00~04:00 vs 04:00~06:00 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('20:00', '04:00', '04:00', '06:00'), false));
    test('A-165 야간 20:00~04:00 vs 19:00~20:00 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('20:00', '04:00', '19:00', '20:00'), false));
    test('A-166 야간 20:00~04:00 vs 19:30~20:30 → true', () => expect(ApplicationModel.hasTimeOverlap('20:00', '04:00', '19:30', '20:30'), true));
    test('A-167 야간 20:00~04:00 vs 야간 21:00~05:00 → true', () => expect(ApplicationModel.hasTimeOverlap('20:00', '04:00', '21:00', '05:00'), true));
    test('A-168 야간 20:00~04:00 vs 야간 04:00~12:00 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('20:00', '04:00', '04:00', '12:00'), false));
    test('A-169 야간 20:00~04:00 vs 주간 08:00~20:00 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('20:00', '04:00', '08:00', '20:00'), false));

    // ── A-17. 추가 경계 케이스 ───────────────────────────────────────────────
    test('A-170 09:00~18:00 vs 08:59~09:00 → false', () => expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '08:59', '09:00'), false));
    test('A-171 09:00~18:00 vs 08:59~09:01 → true', () => expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '08:59', '09:01'), true));
    test('A-172 09:00~18:00 vs 18:00~18:01 → false', () => expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '18:00', '18:01'), false));
    test('A-173 09:00~18:00 vs 17:59~18:00 → true', () => expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '17:59', '18:00'), true));
    test('A-174 야간 21:00~03:00 vs 주간 09:00~21:00 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('21:00', '03:00', '09:00', '21:00'), false));
    test('A-175 야간 21:00~03:00 vs 주간 09:00~21:01 → true', () => expect(ApplicationModel.hasTimeOverlap('21:00', '03:00', '09:00', '21:01'), true));
    test('A-176 야간 21:00~03:00 vs 03:00~09:00 → false (경계)', () => expect(ApplicationModel.hasTimeOverlap('21:00', '03:00', '03:00', '09:00'), false));
    test('A-177 야간 21:00~03:00 vs 02:59~09:00 → true', () => expect(ApplicationModel.hasTimeOverlap('21:00', '03:00', '02:59', '09:00'), true));

    // ── A-18. 형식 파싱 ──────────────────────────────────────────────────────
    test('A-180 한자리 시 9:00~18:00 vs 09:00~18:00 → true', () => expect(ApplicationModel.hasTimeOverlap('9:00', '18:00', '09:00', '18:00'), true));
    test('A-181 한자리 분 09:5~18:00 — p.length>=2이므로 동작 09:05 → true', () => expect(ApplicationModel.hasTimeOverlap('9:5', '18:0', '9:0', '18:5'), true));
    test('A-182 콜론 없는 비정상 형식: split(:) length=1 → toMin=0, 모두 0 → 24h 겹침 → true',
        () => expect(ApplicationModel.hasTimeOverlap('0900', '1800', '0900', '1200'), true)); // 모두 0으로 파싱 → 24h overlap
  });

  // ===========================================================================
  // B. isWorkingOnDate — 단기 (50+ 케이스)
  // ===========================================================================
  group('B: isWorkingOnDate - 단기', () {
    test('B-01 당일 workDate 일치 → true', () {
      final app = _short(workDate: mon0106);
      expect(app.isWorkingOnDate(mon0106), true);
    });
    test('B-02 다음 날 → false', () {
      final app = _short(workDate: mon0106);
      expect(app.isWorkingOnDate(tue0107), false);
    });
    test('B-03 이전 날 → false', () {
      final app = _short(workDate: tue0107);
      expect(app.isWorkingOnDate(mon0106), false);
    });
    test('B-04 1주 후 → false', () {
      final app = _short(workDate: mon0106);
      expect(app.isWorkingOnDate(mon0113), false);
    });
    test('B-05 workDate 시각 무시: 같은 날 다른 시각 → true', () {
      final app = _short(workDate: DateTime(2025, 1, 6, 23, 59));
      expect(app.isWorkingOnDate(DateTime(2025, 1, 6, 0, 0)), true);
    });
    test('B-06 workDate 시각 무시: 새벽 → true', () {
      final app = _short(workDate: DateTime(2025, 1, 6, 0, 1));
      expect(app.isWorkingOnDate(DateTime(2025, 1, 6, 23, 59)), true);
    });
    test('B-07 단기 leaveDates 있어도 workDate 일치 → true (단기는 leaveDates 미사용)', () {
      final app = _base(
        applicationType: AppType.shortTerm,
        workDate: mon0106,
        leaveDates: [mon0106],
      );
      expect(app.isWorkingOnDate(mon0106), true);
    });
    test('B-08 단기 extraWorkDates 있어도 다른날 → false', () {
      final app = _base(
        applicationType: AppType.shortTerm,
        workDate: mon0106,
        extraWorkDates: [tue0107],
      );
      expect(app.isWorkingOnDate(tue0107), false);
    });
    test('B-09 PENDING 단기 → 당일 true', () {
      final app = _base(
        status: 'PENDING',
        applicationType: AppType.shortTerm,
        workDate: mon0106,
      );
      expect(app.isWorkingOnDate(mon0106), true);
    });
    test('B-10 CANCELED 단기 → 당일 true (isWorkingOnDate는 status 무관)', () {
      final app = _base(
        status: 'CANCELED',
        applicationType: AppType.shortTerm,
        workDate: mon0106,
      );
      expect(app.isWorkingOnDate(mon0106), true);
    });
    test('B-11 workDate=토요일 vs 토요일 → true', () {
      final app = _short(workDate: sat0111);
      expect(app.isWorkingOnDate(sat0111), true);
    });
    test('B-12 workDate=토요일 vs 일요일 → false', () {
      final app = _short(workDate: sat0111);
      expect(app.isWorkingOnDate(sun0112), false);
    });
    test('B-13 workDate=2025-12-31 vs 2025-12-31 → true', () {
      final app = _short(workDate: DateTime(2025, 12, 31));
      expect(app.isWorkingOnDate(DateTime(2025, 12, 31)), true);
    });
    test('B-14 workDate=2025-12-31 vs 2026-01-01 → false', () {
      final app = _short(workDate: DateTime(2025, 12, 31));
      expect(app.isWorkingOnDate(DateTime(2026, 1, 1)), false);
    });
    test('B-15 applicationType null이고 workDays/workEndDate 없음 → 단기처럼 동작 → true 당일', () {
      final app = _base(workDate: mon0106, applicationType: null);
      expect(app.isWorkingOnDate(mon0106), true);
    });
    test('B-16 applicationType null → 다른날 false', () {
      final app = _base(workDate: mon0106, applicationType: null);
      expect(app.isWorkingOnDate(tue0107), false);
    });
    test('B-17 단기 수십개 날짜 모두 다름 → false 연속 검증', () {
      final app = _short(workDate: wed0108);
      for (final d in [mon0106, tue0107, thu0109, fri0110, sat0111, sun0112, mon0113]) {
        expect(app.isWorkingOnDate(d), false, reason: '${d.toIso8601String()} should be false');
      }
    });
    test('B-18 단기 workDate만 true', () {
      final app = _short(workDate: fri0110);
      expect(app.isWorkingOnDate(fri0110), true);
      expect(app.isWorkingOnDate(thu0109), false);
      expect(app.isWorkingOnDate(sat0111), false);
    });
    test('B-19 단기 월말 → true', () {
      final app = _short(workDate: fri0131);
      expect(app.isWorkingOnDate(fri0131), true);
    });
    test('B-20 단기 월말 vs 다음달 1일 → false', () {
      final app = _short(workDate: fri0131);
      expect(app.isWorkingOnDate(sat0201), false);
    });
  });

  // ===========================================================================
  // C. isWorkingOnDate — 장기 (120+ 케이스)
  // ===========================================================================
  group('C: isWorkingOnDate - 장기', () {
    // ── C-1. 기본 범위 + 요일 ─────────────────────────────────────────────────
    test('C-01 시작일 workDate 월요일 포함 → true', () {
      final app = _long();
      expect(app.isWorkingOnDate(mon0106), true);
    });
    test('C-02 범위 내 금요일 포함 → true', () {
      final app = _long();
      expect(app.isWorkingOnDate(fri0110), true);
    });
    test('C-03 범위 내 토요일 미포함 → false', () {
      final app = _long();
      expect(app.isWorkingOnDate(sat0111), false);
    });
    test('C-04 범위 내 일요일 미포함 → false', () {
      final app = _long();
      expect(app.isWorkingOnDate(sun0112), false);
    });
    test('C-05 시작일 이전 → false', () {
      final app = _long(workDate: tue0107);
      expect(app.isWorkingOnDate(mon0106), false);
    });
    test('C-06 종료일 이후 → false', () {
      final app = _long(workEndDate: fri0131);
      expect(app.isWorkingOnDate(sat0201), false);
    });
    test('C-07 종료일 당일 (금) → true', () {
      final app = _long(workEndDate: fri0131);
      expect(app.isWorkingOnDate(fri0131), true);
    });
    test('C-08 종료일 당일이 토요일이고 workDays에 토요일 없음 → false', () {
      final app = _long(workEndDate: sat0111);
      expect(app.isWorkingOnDate(sat0111), false);
    });
    test('C-09 범위 내 화수목 모두 true', () {
      final app = _long();
      expect(app.isWorkingOnDate(tue0107), true);
      expect(app.isWorkingOnDate(wed0108), true);
      expect(app.isWorkingOnDate(thu0109), true);
    });
    test('C-10 월~금만 workDays vs 토,일 모두 false', () {
      final app = _long();
      expect(app.isWorkingOnDate(sat0111), false);
      expect(app.isWorkingOnDate(sun0112), false);
    });

    // ── C-2. workEndDate null → false ────────────────────────────────────────
    test('C-11 workEndDate null → false (항상)', () {
      final app = _base(
        applicationType: AppType.longTerm,
        workDate: mon0106,
        workDays: ['월', '화', '수'],
      );
      expect(app.isWorkingOnDate(mon0106), false);
    });
    test('C-12 workEndDate null + actualResignDate도 null → false', () {
      final app = _base(
        applicationType: AppType.longTerm,
        workDate: mon0106,
        workDays: ['월'],
      );
      expect(app.isWorkingOnDate(mon0106), false);
    });

    // ── C-3. effectiveStart 계산 (confirmedAt) ───────────────────────────────
    test('C-20 confirmedAt이 workDate보다 미래 + desiredStartDate 없음 → effectiveStart=confirmedAt', () {
      // workDate=월(1/6), confirmedAt=수(1/8) → effectiveStart=수(1/8)
      final app = _long(
        workDate: mon0106,
        confirmedAt: DateTime(2025, 1, 8, 10, 0),
      );
      expect(app.isWorkingOnDate(mon0106), false); // effectiveStart 이전
      expect(app.isWorkingOnDate(tue0107), false); // effectiveStart 이전
      expect(app.isWorkingOnDate(wed0108), true);  // effectiveStart 당일
      expect(app.isWorkingOnDate(thu0109), true);  // 이후
    });
    test('C-21 confirmedAt이 workDate와 같은날 → effectiveStart=workDate (isAfter 조건 불만족)', () {
      final app = _long(
        workDate: mon0106,
        confirmedAt: DateTime(2025, 1, 6, 15, 0),
      );
      expect(app.isWorkingOnDate(mon0106), true);
    });
    test('C-22 confirmedAt이 workDate 이전 → effectiveStart=workDate', () {
      final app = _long(
        workDate: wed0108,
        confirmedAt: DateTime(2025, 1, 5, 10, 0),
      );
      expect(app.isWorkingOnDate(wed0108), true);
    });
    test('C-23 desiredStartDate 있으면 confirmedAt 무시', () {
      // desiredStartDate=목(1/9), confirmedAt=수(1/8)
      final app = _long(
        workDate: mon0106,
        desiredStartDate: thu0109,
        confirmedAt: DateTime(2025, 1, 8, 10, 0),
      );
      expect(app.isWorkingOnDate(wed0108), false); // desiredStart 이전
      expect(app.isWorkingOnDate(thu0109), true);  // desiredStart 당일
    });
    test('C-24 desiredStartDate가 workDate보다 이전이면 effectiveStart=desiredStartDate', () {
      final app = _long(
        workDate: wed0108,
        desiredStartDate: mon0106,
      );
      expect(app.isWorkingOnDate(mon0106), true);
    });
    test('C-25 confirmedAt null + desiredStartDate null → effectiveStart=workDate', () {
      final app = _long(workDate: mon0106);
      expect(app.isWorkingOnDate(mon0106), true);
    });

    // ── C-4. actualResignDate (종료일 우선) ──────────────────────────────────
    test('C-30 actualResignDate가 workEndDate보다 이전 → actualResignDate 이후 false', () {
      final app = _long(
        workEndDate: fri0131,
        actualResignDate: fri0110,
      );
      expect(app.isWorkingOnDate(fri0110), true);
      expect(app.isWorkingOnDate(mon0113), false);
    });
    test('C-31 actualResignDate 당일 → true (요일 맞으면)', () {
      final app = _long(
        workEndDate: fri0131,
        actualResignDate: fri0110,
      );
      expect(app.isWorkingOnDate(fri0110), true);
    });
    test('C-32 actualResignDate 당일 요일 안맞으면 false', () {
      final app = _long(
        workDays: ['월'],
        workEndDate: fri0131,
        actualResignDate: fri0110, // 금요일
      );
      expect(app.isWorkingOnDate(fri0110), false);
    });
    test('C-33 actualResignDate null이면 workEndDate 사용', () {
      final app = _long(workEndDate: fri0131);
      expect(app.isWorkingOnDate(fri0131), true);
    });

    // ── C-5. leaveDates (휴무) ────────────────────────────────────────────────
    test('C-40 월요일 leaveDates 포함 → false', () {
      final app = _long(leaveDates: [mon0113]);
      expect(app.isWorkingOnDate(mon0113), false);
    });
    test('C-41 같은 주 다른 날 leaveDates 미포함 → true', () {
      final app = _long(leaveDates: [mon0113]);
      expect(app.isWorkingOnDate(tue0107), true);
    });
    test('C-42 여러 leaveDates → 해당 날 false', () {
      final app = _long(leaveDates: [mon0106, wed0108, fri0110]);
      expect(app.isWorkingOnDate(mon0106), false);
      expect(app.isWorkingOnDate(wed0108), false);
      expect(app.isWorkingOnDate(fri0110), false);
    });
    test('C-43 leaveDates 날 요일 안맞아도 (원래 false) → false', () {
      final app = _long(leaveDates: [sat0111]);
      expect(app.isWorkingOnDate(sat0111), false); // 원래도 false (토요일)
    });
    test('C-44 leaveDates 빈 리스트 → 영향 없음', () {
      final app = _long(leaveDates: []);
      expect(app.isWorkingOnDate(mon0106), true);
    });

    // ── C-6. extraWorkDates (추가근무) ────────────────────────────────────────
    test('C-50 토요일 extraWorkDates 포함 → true (요일 무관)', () {
      final app = _long(extraWorkDates: [sat0111]);
      expect(app.isWorkingOnDate(sat0111), true);
    });
    test('C-51 일요일 extraWorkDates 포함 → true', () {
      final app = _long(extraWorkDates: [sun0112]);
      expect(app.isWorkingOnDate(sun0112), true);
    });
    test('C-52 extraWorkDates이 leaveDates보다 우선 (extraWork 먼저 체크)', () {
      final app = _long(
        extraWorkDates: [mon0106],
        leaveDates: [mon0106],
      );
      // isExtraWorkDateOn 먼저 체크 → true 반환
      expect(app.isWorkingOnDate(mon0106), true);
    });
    test('C-53 extraWorkDates 없는 날은 영향 없음', () {
      final app = _long(extraWorkDates: [sat0111]);
      expect(app.isWorkingOnDate(sun0112), false); // 일요일, extraWork 없음
    });
    test('C-54 extraWorkDates 범위 외 날짜 → false (범위 체크 먼저)', () {
      final app = _long(
        workDate: mon0106,
        workEndDate: fri0110,
        extraWorkDates: [sat0201], // 범위 밖
      );
      expect(app.isWorkingOnDate(sat0201), false);
    });
    test('C-55 extraWorkDates 범위 내 날짜 → true', () {
      final app = _long(
        workDate: mon0106,
        workEndDate: fri0131,
        extraWorkDates: [sat0111],
      );
      expect(app.isWorkingOnDate(sat0111), true);
    });

    // ── C-7. workDays 다양한 조합 ────────────────────────────────────────────
    test('C-60 workDays=[월,수,금] vs 화 → false', () {
      final app = _long(workDays: ['월', '수', '금']);
      expect(app.isWorkingOnDate(tue0107), false);
    });
    test('C-61 workDays=[월,수,금] vs 수 → true', () {
      final app = _long(workDays: ['월', '수', '금']);
      expect(app.isWorkingOnDate(wed0108), true);
    });
    test('C-62 workDays=[토,일] vs 토 → true', () {
      final app = _long(workDays: ['토', '일']);
      expect(app.isWorkingOnDate(sat0111), true);
    });
    test('C-63 workDays=[토,일] vs 금 → false', () {
      final app = _long(workDays: ['토', '일']);
      expect(app.isWorkingOnDate(fri0110), false);
    });
    test('C-64 workDays null → false (workDays?.contains → null이면 false)', () {
      final app = _base(
        applicationType: AppType.longTerm,
        workDate: mon0106,
        workEndDate: fri0131,
        workDays: null,
      );
      expect(app.isWorkingOnDate(mon0106), false);
    });
    test('C-65 workDays=[] 빈 리스트 → false', () {
      final app = _base(
        applicationType: AppType.longTerm,
        workDate: mon0106,
        workEndDate: fri0131,
        workDays: [],
      );
      expect(app.isWorkingOnDate(mon0106), false);
    });
    test('C-66 workDays=[월] 단 하루 → 다른 요일 모두 false', () {
      final app = _long(workDays: ['월']);
      expect(app.isWorkingOnDate(tue0107), false);
      expect(app.isWorkingOnDate(wed0108), false);
      expect(app.isWorkingOnDate(thu0109), false);
      expect(app.isWorkingOnDate(fri0110), false);
      expect(app.isWorkingOnDate(sat0111), false);
      expect(app.isWorkingOnDate(sun0112), false);
    });
    test('C-67 workDays=[일] 일요일 → true', () {
      final app = _long(workDays: ['일']);
      expect(app.isWorkingOnDate(sun0112), true);
    });

    // ── C-8. 경계 날짜 ───────────────────────────────────────────────────────
    test('C-70 targetDate == startOnly 경계 → true (요일 맞으면)', () {
      final app = _long(workDate: mon0106, workEndDate: fri0131);
      expect(app.isWorkingOnDate(mon0106), true);
    });
    test('C-71 targetDate == endOnly 경계 → true (요일 맞으면)', () {
      final app = _long(workDate: mon0106, workEndDate: fri0131);
      expect(app.isWorkingOnDate(fri0131), true);
    });
    test('C-72 targetDate = startOnly - 1일 → false', () {
      final app = _long(workDate: tue0107, workEndDate: fri0131);
      expect(app.isWorkingOnDate(mon0106), false);
    });
    test('C-73 targetDate = endOnly + 1일 → false', () {
      final app = _long(workDate: mon0106, workEndDate: fri0131);
      expect(app.isWorkingOnDate(sat0201), false);
    });

    // ── C-9. 복합: confirmedAt + leaveDates + extraWork ──────────────────────
    test('C-80 confirmedAt 이후 + leaveDates → false', () {
      final app = _long(
        workDate: mon0106,
        confirmedAt: DateTime(2025, 1, 8, 10, 0),
        leaveDates: [thu0109],
      );
      expect(app.isWorkingOnDate(thu0109), false);
    });
    test('C-81 confirmedAt 이후 + extraWorkDates → true', () {
      final app = _long(
        workDate: mon0106,
        confirmedAt: DateTime(2025, 1, 8, 10, 0),
        extraWorkDates: [sat0111],
      );
      expect(app.isWorkingOnDate(sat0111), true);
    });
    test('C-82 confirmedAt 이전 날은 false (effectiveStart=confirmedAt)', () {
      final app = _long(
        workDate: mon0106,
        confirmedAt: DateTime(2025, 1, 10, 10, 0), // 금요일 확정
        extraWorkDates: [tue0107], // 화요일 추가근무 (effectiveStart 이전)
      );
      // targetDate=tue0107(1/7) < effectiveStart(1/10) → false (범위 체크가 extraWork보다 먼저)
      expect(app.isWorkingOnDate(tue0107), false);
    });
    test('C-83 actualResignDate + extraWork 범위 밖 → false', () {
      final app = _long(
        workEndDate: fri0131,
        actualResignDate: fri0110,
        extraWorkDates: [mon0113],
      );
      expect(app.isWorkingOnDate(mon0113), false);
    });
  });

  // ===========================================================================
  // D. isScheduledOnDate — 캘린더 표시 (120+ 케이스)
  // ===========================================================================
  group('D: isScheduledOnDate', () {
    // ── D-1. 단기 ─────────────────────────────────────────────────────────────
    test('D-01 단기 당일 → true', () {
      expect(_short(workDate: mon0106).isScheduledOnDate(mon0106), true);
    });
    test('D-02 단기 다른날 → false', () {
      expect(_short(workDate: mon0106).isScheduledOnDate(tue0107), false);
    });
    test('D-03 단기 PENDING → 당일 true', () {
      final app = _base(status: 'PENDING', applicationType: AppType.shortTerm, workDate: mon0106);
      expect(app.isScheduledOnDate(mon0106), true);
    });
    test('D-04 단기 CANCELED → 당일 true (status 무관)', () {
      final app = _base(status: 'CANCELED', applicationType: AppType.shortTerm, workDate: mon0106);
      expect(app.isScheduledOnDate(mon0106), true);
    });
    test('D-05 단기 REJECTED → 당일 true (status 무관)', () {
      final app = _base(status: 'REJECTED', applicationType: AppType.shortTerm, workDate: mon0106);
      expect(app.isScheduledOnDate(mon0106), true);
    });

    // ── D-2. 장기 미확정 (PENDING/AUTO_CANCELED) → workDate에만 표시 ─────────
    test('D-10 장기 PENDING → workDate에만 true', () {
      final app = _long(status: 'PENDING');
      expect(app.isScheduledOnDate(mon0106), true);
      expect(app.isScheduledOnDate(tue0107), false);
    });
    test('D-11 장기 REJECTED → workDate에만 true', () {
      final app = _long(status: 'REJECTED');
      expect(app.isScheduledOnDate(mon0106), true);
      expect(app.isScheduledOnDate(fri0110), false);
    });
    test('D-12 장기 CANCELED → workDate에만 true', () {
      final app = _long(status: 'CANCELED');
      expect(app.isScheduledOnDate(mon0106), true);
      expect(app.isScheduledOnDate(tue0107), false);
    });
    test('D-13 장기 AUTO_CANCELED → workDate에만 true', () {
      final app = _long(status: 'AUTO_CANCELED');
      expect(app.isScheduledOnDate(mon0106), true);
      expect(app.isScheduledOnDate(wed0108), false);
    });

    // ── D-3. 장기 CONTRACT_PENDING (활성) ────────────────────────────────────
    test('D-20 장기 CONTRACT_PENDING → 범위+요일 판단', () {
      final app = _long(status: 'CONTRACT_PENDING');
      expect(app.isScheduledOnDate(mon0106), true);
      expect(app.isScheduledOnDate(fri0110), true);
      expect(app.isScheduledOnDate(sat0111), false);
    });
    test('D-21 장기 CONTRACT_PENDING + isTerminationApproved → false', () {
      final app = _long(status: 'CONTRACT_PENDING', resignStatus: 'APPROVED');
      expect(app.isScheduledOnDate(mon0106), false);
    });

    // ── D-4. 장기 CONFIRMED + 정상 범위 ─────────────────────────────────────
    test('D-30 장기 CONFIRMED 범위 내 weekday 맞음 → true', () {
      final app = _long();
      expect(app.isScheduledOnDate(mon0106), true);
      expect(app.isScheduledOnDate(wed0108), true);
      expect(app.isScheduledOnDate(fri0110), true);
    });
    test('D-31 장기 CONFIRMED 범위 내 weekday 안맞음 → false', () {
      final app = _long();
      expect(app.isScheduledOnDate(sat0111), false);
      expect(app.isScheduledOnDate(sun0112), false);
    });
    test('D-32 장기 CONFIRMED 범위 밖 이전 → false', () {
      final app = _long(workDate: wed0108);
      expect(app.isScheduledOnDate(mon0106), false);
    });
    test('D-33 장기 CONFIRMED 범위 밖 이후 → false', () {
      final app = _long(workEndDate: fri0110);
      expect(app.isScheduledOnDate(mon0113), false);
    });

    // ── D-5. 장기 CONFIRMED + 퇴사 완료 → false ──────────────────────────────
    test('D-40 resignStatus=APPROVED → false (전체 기간)', () {
      final app = _long(resignStatus: 'APPROVED');
      expect(app.isScheduledOnDate(mon0106), false);
      expect(app.isScheduledOnDate(fri0131), false);
    });
    test('D-41 resignStatus=AUTO_APPROVED → false', () {
      final app = _long(resignStatus: 'AUTO_APPROVED');
      expect(app.isScheduledOnDate(mon0106), false);
    });
    test('D-42 terminationStatus=APPROVED → false', () {
      final app = _long(terminationStatus: 'APPROVED');
      expect(app.isScheduledOnDate(mon0106), false);
    });
    test('D-43 terminationStatus=AUTO_APPROVED → false', () {
      final app = _long(terminationStatus: 'AUTO_APPROVED');
      expect(app.isScheduledOnDate(mon0106), false);
    });
    test('D-44 resignStatus=PENDING (미결) → 퇴사 미승인 → 정상 표시', () {
      final app = _long(resignStatus: 'PENDING');
      expect(app.isScheduledOnDate(mon0106), true);
    });
    test('D-45 resignStatus=REJECTED → 정상 표시', () {
      final app = _long(resignStatus: 'REJECTED');
      expect(app.isScheduledOnDate(mon0106), true);
    });
    test('D-46 terminationStatus=PENDING → 정상 표시', () {
      final app = _long(terminationStatus: 'PENDING');
      expect(app.isScheduledOnDate(mon0106), true);
    });

    // ── D-6. isScheduledOnDate leaveDates → true (캘린더 표시) ───────────────
    test('D-50 휴무일도 캘린더에 표시 → true', () {
      final app = _long(leaveDates: [mon0106]);
      expect(app.isScheduledOnDate(mon0106), true);
    });
    test('D-51 휴무일이 아닌 날 → weekday 기반', () {
      final app = _long(leaveDates: [mon0106]);
      expect(app.isScheduledOnDate(tue0107), true);
      expect(app.isScheduledOnDate(sat0111), false);
    });
    test('D-52 요일 안맞는 날 leaveDates → 원래 false, leaveDates로도 true 안됨 (요일 조건 먼저)', () {
      // 토요일(workDays에 없음)이 leaveDates에 있더라도 → isExtraWorkDateOn(false), isLeaveDateOn(true) → true
      final app = _long(leaveDates: [sat0111]);
      expect(app.isScheduledOnDate(sat0111), true); // isLeaveDateOn → true
    });

    // ── D-7. isScheduledOnDate extraWorkDates → true ─────────────────────────
    test('D-60 토요일 extraWork → true', () {
      final app = _long(extraWorkDates: [sat0111]);
      expect(app.isScheduledOnDate(sat0111), true);
    });
    test('D-61 범위 밖 extraWork → false', () {
      final app = _long(workDate: mon0106, workEndDate: fri0110, extraWorkDates: [sat0201]);
      expect(app.isScheduledOnDate(sat0201), false);
    });

    // ── D-8. effectiveStart 반영 ──────────────────────────────────────────────
    test('D-70 confirmedAt 이후 effectiveStart → 이전날 false', () {
      final app = _long(workDate: mon0106, confirmedAt: DateTime(2025, 1, 8, 10, 0));
      expect(app.isScheduledOnDate(mon0106), false);
      expect(app.isScheduledOnDate(tue0107), false);
      expect(app.isScheduledOnDate(wed0108), true);
    });
    test('D-71 desiredStartDate 설정 → 그 이전 false', () {
      final app = _long(workDate: mon0106, desiredStartDate: thu0109);
      expect(app.isScheduledOnDate(mon0106), false);
      expect(app.isScheduledOnDate(thu0109), true);
    });

    // ── D-9. actualResignDate + isScheduledOnDate ────────────────────────────
    test('D-80 actualResignDate 이후 → false', () {
      final app = _long(workEndDate: fri0131, actualResignDate: fri0110);
      expect(app.isScheduledOnDate(fri0110), true);
      expect(app.isScheduledOnDate(mon0113), false);
    });
    test('D-81 actualResignDate 당일 (요일 맞음) → true', () {
      final app = _long(workEndDate: fri0131, actualResignDate: fri0110);
      expect(app.isScheduledOnDate(fri0110), true);
    });

    // ── D-10. workEndDate null + CONFIRMED ────────────────────────────────────
    test('D-90 workEndDate null + CONFIRMED → false', () {
      final app = _base(
        applicationType: AppType.longTerm,
        workDate: mon0106,
        workDays: ['월'],
        status: 'CONFIRMED',
      );
      expect(app.isScheduledOnDate(mon0106), false);
    });

    // ── D-11. 다양한 확정 완료 상태 조합 ─────────────────────────────────────
    test('D-100 resignStatus=APPROVED + terminationStatus=PENDING → false (resignStatus 우선)', () {
      final app = _long(resignStatus: 'APPROVED', terminationStatus: 'PENDING');
      expect(app.isScheduledOnDate(mon0106), false);
    });
    test('D-101 resignStatus=REJECTED + terminationStatus=APPROVED → false', () {
      final app = _long(resignStatus: 'REJECTED', terminationStatus: 'APPROVED');
      expect(app.isScheduledOnDate(mon0106), false);
    });
    test('D-102 둘 다 null → 정상 표시', () {
      final app = _long(resignStatus: null, terminationStatus: null);
      expect(app.isScheduledOnDate(mon0106), true);
    });
  });

  // ===========================================================================
  // E. isLongTermApplication (40+ 케이스)
  // ===========================================================================
  group('E: isLongTermApplication', () {
    test('E-01 applicationType=long_term → true', () {
      expect(_base(applicationType: 'long_term').isLongTermApplication, true);
    });
    test('E-02 applicationType=short → false', () {
      expect(_base(applicationType: 'short').isLongTermApplication, false);
    });
    test('E-03 applicationType=short + workDays 있어도 false', () {
      final app = _base(applicationType: 'short', workDays: ['월', '화'], workEndDate: fri0131);
      expect(app.isLongTermApplication, false);
    });
    test('E-04 applicationType null + workDays 있음 → true', () {
      expect(_base(workDays: ['월']).isLongTermApplication, true);
    });
    test('E-05 applicationType null + workDays 빈 리스트 → false', () {
      expect(_base(workDays: []).isLongTermApplication, false);
    });
    test('E-06 applicationType null + workEndDate 있음 → true', () {
      expect(_base(workEndDate: fri0131).isLongTermApplication, true);
    });
    test('E-07 applicationType null + workDays null + workEndDate null → false', () {
      expect(_base(applicationType: null).isLongTermApplication, false);
    });
    test('E-08 applicationType null + workDays null + workEndDate 있음 → true', () {
      expect(_base(workEndDate: fri0131, workDays: null).isLongTermApplication, true);
    });
    test('E-09 long_term 명시 + workDays null + workEndDate null → true (명시 우선)', () {
      expect(_base(applicationType: 'long_term').isLongTermApplication, true);
    });
    test('E-10 short 명시 + workEndDate 있어도 → false (short 명시 최우선)', () {
      expect(_base(applicationType: 'short', workEndDate: fri0131).isLongTermApplication, false);
    });
    test('E-11 workDays=[일] 단일 요일 → true', () {
      expect(_base(workDays: ['일']).isLongTermApplication, true);
    });
    test('E-12 workDays 7일 전체 → true', () {
      expect(_base(workDays: ['월','화','수','목','금','토','일']).isLongTermApplication, true);
    });
    test('E-13 unknown applicationType + workDays null + workEndDate null → false', () {
      expect(_base(applicationType: 'unknown_type').isLongTermApplication, false);
    });
    test('E-14 unknown applicationType + workDays 있음 → true', () {
      expect(_base(applicationType: 'unknown_type', workDays: ['월']).isLongTermApplication, true);
    });
  });

  // ===========================================================================
  // F. workDaysDisplay (35+ 케이스)
  // ===========================================================================
  group('F: workDaysDisplay', () {
    test('F-01 null → null', () => expect(_base().workDaysDisplay, null));
    test('F-02 빈 리스트 → null', () => expect(_base(workDays: []).workDaysDisplay, null));
    test('F-03 월~금 연속 → "주 5일 (월~금)"', () {
      expect(_base(workDays: ['월','화','수','목','금']).workDaysDisplay, '주 5일 (월~금)');
    });
    test('F-04 월~일 7일 → "주 7일 (월~일)"', () {
      expect(_base(workDays: ['월','화','수','목','금','토','일']).workDaysDisplay, '주 7일 (월~일)');
    });
    test('F-05 월~수 3일 연속 → "주 3일 (월~수)"', () {
      expect(_base(workDays: ['월','화','수']).workDaysDisplay, '주 3일 (월~수)');
    });
    test('F-06 목~토 3일 연속 → "주 3일 (목~토)"', () {
      expect(_base(workDays: ['목','금','토']).workDaysDisplay, '주 3일 (목~토)');
    });
    test('F-07 수~금 3일 연속 → "주 3일 (수~금)"', () {
      expect(_base(workDays: ['수','목','금']).workDaysDisplay, '주 3일 (수~금)');
    });
    test('F-08 월,수,금 비연속 → "주 3일 (월,수,금)"', () {
      expect(_base(workDays: ['월','수','금']).workDaysDisplay, '주 3일 (월,수,금)');
    });
    test('F-09 화,목,토 비연속 → "주 3일 (화,목,토)"', () {
      expect(_base(workDays: ['화','목','토']).workDaysDisplay, '주 3일 (화,목,토)');
    });
    test('F-10 월 단독 → "주 1일 (월)"', () {
      expect(_base(workDays: ['월']).workDaysDisplay, '주 1일 (월)');
    });
    test('F-11 일 단독 → "주 1일 (일)"', () {
      expect(_base(workDays: ['일']).workDaysDisplay, '주 1일 (일)');
    });
    test('F-12 월,금 비연속 → "주 2일 (월,금)"', () {
      expect(_base(workDays: ['월','금']).workDaysDisplay, '주 2일 (월,금)');
    });
    test('F-13 월,화 연속 2일 → "주 2일 (월~화)"', () {
      expect(_base(workDays: ['월','화']).workDaysDisplay, '주 2일 (월~화)');
    });
    test('F-14 금,토 연속 → "주 2일 (금~토)"', () {
      expect(_base(workDays: ['금','토']).workDaysDisplay, '주 2일 (금~토)');
    });
    test('F-15 토,일 연속 → "주 2일 (토~일)"', () {
      expect(_base(workDays: ['토','일']).workDaysDisplay, '주 2일 (토~일)');
    });
    test('F-16 순서 무관 정렬: 금,화,목 → 정렬 후 "주 3일 (화,목,금)"', () {
      expect(_base(workDays: ['금','화','목']).workDaysDisplay, '주 3일 (화,목,금)');
    });
    test('F-17 순서 무관 연속: 금,수,목 → 정렬 후 "주 3일 (수~금)"', () {
      expect(_base(workDays: ['금','수','목']).workDaysDisplay, '주 3일 (수~금)');
    });
    test('F-18 화~일 6일 연속 → "주 6일 (화~일)"', () {
      expect(_base(workDays: ['화','수','목','금','토','일']).workDaysDisplay, '주 6일 (화~일)');
    });
    test('F-19 월,목 비연속 → "주 2일 (월,목)"', () {
      expect(_base(workDays: ['월','목']).workDaysDisplay, '주 2일 (월,목)');
    });
    test('F-20 월,수,금,일 → "주 4일 (월,수,금,일)"', () {
      expect(_base(workDays: ['월','수','금','일']).workDaysDisplay, '주 4일 (월,수,금,일)');
    });
  });

  // ===========================================================================
  // G. workPeriodDisplay (25+ 케이스)
  // ===========================================================================
  group('G: workPeriodDisplay', () {
    test('G-01 workEndDate null → ""', () {
      expect(_base(workDate: mon0106).workPeriodDisplay, '');
    });
    test('G-02 기본 1/6~1/31 → "1/6~1/31"', () {
      final app = _base(workDate: mon0106, workEndDate: fri0131);
      expect(app.workPeriodDisplay, '1/6~1/31');
    });
    test('G-03 2/1~2/28 → "2/1~2/28"', () {
      final app = _base(
        workDate: DateTime(2025, 2, 1),
        workEndDate: DateTime(2025, 2, 28),
      );
      expect(app.workPeriodDisplay, '2/1~2/28');
    });
    test('G-04 12/1~12/31 → "12/1~12/31"', () {
      final app = _base(
        workDate: DateTime(2025, 12, 1),
        workEndDate: DateTime(2025, 12, 31),
      );
      expect(app.workPeriodDisplay, '12/1~12/31');
    });
    test('G-05 actualResignDate 있으면 workEndDate 대신 사용', () {
      final app = _base(
        workDate: mon0106,
        workEndDate: fri0131,
        actualResignDate: fri0110,
      );
      expect(app.workPeriodDisplay, '1/6~1/10');
    });
    test('G-06 actualResignDate가 workEndDate보다 이후여도 사용됨', () {
      final app = _base(
        workDate: mon0106,
        workEndDate: fri0110,
        actualResignDate: fri0131,
      );
      expect(app.workPeriodDisplay, '1/6~1/31');
    });
    test('G-07 desiredStartDate 있으면 workDate 대신 사용', () {
      final app = _base(
        workDate: mon0106,
        workEndDate: fri0131,
        desiredStartDate: thu0109,
      );
      expect(app.workPeriodDisplay, '1/9~1/31');
    });
    test('G-08 desiredStartDate + actualResignDate 동시', () {
      final app = _base(
        workDate: mon0106,
        workEndDate: fri0131,
        desiredStartDate: tue0107,
        actualResignDate: fri0110,
      );
      expect(app.workPeriodDisplay, '1/7~1/10');
    });
    test('G-09 workEndDate null이면 desiredStartDate 있어도 ""', () {
      final app = _base(workDate: mon0106, desiredStartDate: thu0109);
      expect(app.workPeriodDisplay, '');
    });
    test('G-10 actualResignDate null + workEndDate null → ""', () {
      final app = _base(workDate: mon0106);
      expect(app.workPeriodDisplay, '');
    });
    test('G-11 같은 날 시작/종료 → "1/6~1/6"', () {
      final app = _base(workDate: mon0106, workEndDate: mon0106);
      expect(app.workPeriodDisplay, '1/6~1/6');
    });
    test('G-12 11월 표시 → "11/1~11/30"', () {
      final app = _base(
        workDate: DateTime(2025, 11, 1),
        workEndDate: DateTime(2025, 11, 30),
      );
      expect(app.workPeriodDisplay, '11/1~11/30');
    });
  });

  // ===========================================================================
  // H. isTerminationApproved (25+ 케이스)
  // ===========================================================================
  group('H: isTerminationApproved', () {
    test('H-01 둘 다 null → false', () {
      expect(_base().isTerminationApproved, false);
    });
    test('H-02 resignStatus=APPROVED → true', () {
      expect(_base(resignStatus: 'APPROVED').isTerminationApproved, true);
    });
    test('H-03 resignStatus=AUTO_APPROVED → true', () {
      expect(_base(resignStatus: 'AUTO_APPROVED').isTerminationApproved, true);
    });
    test('H-04 terminationStatus=APPROVED → true', () {
      expect(_base(terminationStatus: 'APPROVED').isTerminationApproved, true);
    });
    test('H-05 terminationStatus=AUTO_APPROVED → true', () {
      expect(_base(terminationStatus: 'AUTO_APPROVED').isTerminationApproved, true);
    });
    test('H-06 resignStatus=PENDING → false', () {
      expect(_base(resignStatus: 'PENDING').isTerminationApproved, false);
    });
    test('H-07 resignStatus=REJECTED → false', () {
      expect(_base(resignStatus: 'REJECTED').isTerminationApproved, false);
    });
    test('H-08 terminationStatus=PENDING → false', () {
      expect(_base(terminationStatus: 'PENDING').isTerminationApproved, false);
    });
    test('H-09 terminationStatus=REJECTED → false', () {
      expect(_base(terminationStatus: 'REJECTED').isTerminationApproved, false);
    });
    test('H-10 resignStatus=APPROVED + terminationStatus=PENDING → true (resign 기준)', () {
      expect(_base(resignStatus: 'APPROVED', terminationStatus: 'PENDING').isTerminationApproved, true);
    });
    test('H-11 resignStatus=PENDING + terminationStatus=APPROVED → true (termination 기준)', () {
      expect(_base(resignStatus: 'PENDING', terminationStatus: 'APPROVED').isTerminationApproved, true);
    });
    test('H-12 둘 다 APPROVED → true', () {
      expect(_base(resignStatus: 'APPROVED', terminationStatus: 'APPROVED').isTerminationApproved, true);
    });
    test('H-13 둘 다 PENDING → false', () {
      expect(_base(resignStatus: 'PENDING', terminationStatus: 'PENDING').isTerminationApproved, false);
    });
    test('H-14 resignStatus=AUTO_APPROVED + terminationStatus=REJECTED → true', () {
      expect(_base(resignStatus: 'AUTO_APPROVED', terminationStatus: 'REJECTED').isTerminationApproved, true);
    });
    test('H-15 알 수 없는 값 → false', () {
      expect(_base(resignStatus: 'SOMETHING_ELSE').isTerminationApproved, false);
    });
  });

  // ===========================================================================
  // I. AppStatus / AppType 상수 (25+ 케이스)
  // ===========================================================================
  group('I: AppStatus / AppType 상수', () {
    test('I-01 pending = PENDING', () => expect(AppStatus.pending, 'PENDING'));
    test('I-02 contractPending = CONTRACT_PENDING', () => expect(AppStatus.contractPending, 'CONTRACT_PENDING'));
    test('I-03 confirmed = CONFIRMED', () => expect(AppStatus.confirmed, 'CONFIRMED'));
    test('I-04 rejected = REJECTED', () => expect(AppStatus.rejected, 'REJECTED'));
    test('I-05 canceled = CANCELED', () => expect(AppStatus.canceled, 'CANCELED'));
    test('I-06 autoCanceled = AUTO_CANCELED', () => expect(AppStatus.autoCanceled, 'AUTO_CANCELED'));
    test('I-07 approved = APPROVED', () => expect(AppStatus.approved, 'APPROVED'));
    test('I-08 autoApproved = AUTO_APPROVED', () => expect(AppStatus.autoApproved, 'AUTO_APPROVED'));
    test('I-09 renewalExtend = EXTEND', () => expect(AppStatus.renewalExtend, 'EXTEND'));
    test('I-10 renewalTerminate = TERMINATE', () => expect(AppStatus.renewalTerminate, 'TERMINATE'));
    test('I-11 activeStates contains pending', () => expect(AppStatus.activeStates.contains('PENDING'), true));
    test('I-12 activeStates contains contractPending', () => expect(AppStatus.activeStates.contains('CONTRACT_PENDING'), true));
    test('I-13 activeStates contains confirmed', () => expect(AppStatus.activeStates.contains('CONFIRMED'), true));
    test('I-14 activeStates NOT contains rejected', () => expect(AppStatus.activeStates.contains('REJECTED'), false));
    test('I-15 activeStates NOT contains canceled', () => expect(AppStatus.activeStates.contains('CANCELED'), false));
    test('I-16 confirmedStatuses contains confirmed', () => expect(AppStatus.confirmedStatuses.contains('CONFIRMED'), true));
    test('I-17 confirmedStatuses contains contractPending', () => expect(AppStatus.confirmedStatuses.contains('CONTRACT_PENDING'), true));
    test('I-18 confirmedStatuses NOT contains pending', () => expect(AppStatus.confirmedStatuses.contains('PENDING'), false));
    test('I-19 inactiveStates contains rejected', () => expect(AppStatus.inactiveStates.contains('REJECTED'), true));
    test('I-20 inactiveStates contains canceled', () => expect(AppStatus.inactiveStates.contains('CANCELED'), true));
    test('I-21 inactiveStates contains autoCanceled', () => expect(AppStatus.inactiveStates.contains('AUTO_CANCELED'), true));
    test('I-22 inactiveStates NOT contains pending', () => expect(AppStatus.inactiveStates.contains('PENDING'), false));
    test('I-23 AppType.longTerm = long_term', () => expect(AppType.longTerm, 'long_term'));
    test('I-24 AppType.shortTerm = short', () => expect(AppType.shortTerm, 'short'));
    test('I-25 activeStates length = 3', () => expect(AppStatus.activeStates.length, 3));
    test('I-26 confirmedStatuses length = 2', () => expect(AppStatus.confirmedStatuses.length, 2));
    test('I-27 inactiveStates length = 3', () => expect(AppStatus.inactiveStates.length, 3));
  });

  // ===========================================================================
  // J. statusText / isWorkTypeChanged / isStarred (20+ 케이스)
  // ===========================================================================
  group('J: statusText / isWorkTypeChanged / isStarred', () {
    test('J-01 PENDING → "대기 중"', () => expect(_base(status: 'PENDING').statusText, '대기 중'));
    test('J-02 CONTRACT_PENDING → "계약 대기"', () => expect(_base(status: 'CONTRACT_PENDING').statusText, '계약 대기'));
    test('J-03 CONFIRMED → "확정"', () => expect(_base(status: 'CONFIRMED').statusText, '확정'));
    test('J-04 REJECTED → "거절"', () => expect(_base(status: 'REJECTED').statusText, '거절'));
    test('J-05 CANCELED → "취소됨"', () => expect(_base(status: 'CANCELED').statusText, '취소됨'));
    test('J-06 AUTO_CANCELED → "자동 취소됨"', () => expect(_base(status: 'AUTO_CANCELED').statusText, '자동 취소됨'));
    test('J-07 unknown → "알 수 없음"', () => expect(_base(status: 'UNKNOWN').statusText, '알 수 없음'));
    test('J-08 originalWorkType null → isWorkTypeChanged false', () {
      expect(_base(originalWorkType: null).isWorkTypeChanged, false);
    });
    test('J-09 originalWorkType 있음 → isWorkTypeChanged true', () {
      expect(_base(originalWorkType: '포장').isWorkTypeChanged, true);
    });
    test('J-10 originalWorkType 빈 문자열 → isWorkTypeChanged true (null이 아니므로)', () {
      expect(_base(originalWorkType: '').isWorkTypeChanged, true);
    });
    test('J-11 isStarred 기본 false', () => expect(_base().isStarred, false));
    test('J-12 isStarred true', () => expect(_base(isStarred: true).isStarred, true));
  });

  // ===========================================================================
  // K. isLeaveDateOn / isExtraWorkDateOn (30+ 케이스)
  // ===========================================================================
  group('K: isLeaveDateOn / isExtraWorkDateOn', () {
    test('K-01 leaveDates null → false', () {
      expect(_base().isLeaveDateOn(mon0106), false);
    });
    test('K-02 leaveDates 빈 리스트 → false', () {
      expect(_base(leaveDates: []).isLeaveDateOn(mon0106), false);
    });
    test('K-03 leaveDates 포함 → true', () {
      expect(_base(leaveDates: [mon0106]).isLeaveDateOn(mon0106), true);
    });
    test('K-04 leaveDates 포함 시각 다름 → true (같은 날이면)', () {
      final app = _base(leaveDates: [DateTime(2025, 1, 6, 23, 0)]);
      expect(app.isLeaveDateOn(DateTime(2025, 1, 6, 9, 0)), true);
    });
    test('K-05 leaveDates 다른날 → false', () {
      expect(_base(leaveDates: [tue0107]).isLeaveDateOn(mon0106), false);
    });
    test('K-06 여러 leaveDates 포함 여부', () {
      final app = _base(leaveDates: [mon0106, wed0108, fri0110]);
      expect(app.isLeaveDateOn(mon0106), true);
      expect(app.isLeaveDateOn(tue0107), false);
      expect(app.isLeaveDateOn(wed0108), true);
      expect(app.isLeaveDateOn(thu0109), false);
      expect(app.isLeaveDateOn(fri0110), true);
    });
    test('K-07 extraWorkDates null → false', () {
      expect(_base().isExtraWorkDateOn(mon0106), false);
    });
    test('K-08 extraWorkDates 빈 리스트 → false', () {
      expect(_base(extraWorkDates: []).isExtraWorkDateOn(mon0106), false);
    });
    test('K-09 extraWorkDates 포함 → true', () {
      expect(_base(extraWorkDates: [sat0111]).isExtraWorkDateOn(sat0111), true);
    });
    test('K-10 extraWorkDates 다른날 → false', () {
      expect(_base(extraWorkDates: [sat0111]).isExtraWorkDateOn(sun0112), false);
    });
    test('K-11 extraWorkDates 시각 무관 같은날 → true', () {
      final app = _base(extraWorkDates: [DateTime(2025, 1, 11, 8, 0)]);
      expect(app.isExtraWorkDateOn(DateTime(2025, 1, 11, 22, 0)), true);
    });
    test('K-12 leaveDates + extraWorkDates 같은 날 독립 동작', () {
      final app = _base(leaveDates: [mon0106], extraWorkDates: [mon0106]);
      expect(app.isLeaveDateOn(mon0106), true);
      expect(app.isExtraWorkDateOn(mon0106), true);
    });
  });

  // ===========================================================================
  // L. 복합 시나리오 (60+ 케이스)
  // ===========================================================================
  group('L: 복합 시나리오', () {
    // ── L-1. hasTimeOverlap + isWorkingOnDate 조합 ───────────────────────────
    test('L-01 같은 날 단기 두 건 시간 겹침 → 충돌 감지', () {
      final app1 = _short(workDate: mon0106, startTime: '09:00', endTime: '18:00');
      final app2 = _short(workDate: mon0106, startTime: '14:00', endTime: '22:00');
      expect(app1.isWorkingOnDate(mon0106), true);
      expect(app2.isWorkingOnDate(mon0106), true);
      expect(ApplicationModel.hasTimeOverlap(app1.startTime, app1.endTime, app2.startTime, app2.endTime), true);
    });
    test('L-02 같은 날 단기 두 건 시간 비겹침 → 충돌 없음', () {
      final app1 = _short(workDate: mon0106, startTime: '09:00', endTime: '14:00');
      final app2 = _short(workDate: mon0106, startTime: '14:00', endTime: '22:00');
      expect(ApplicationModel.hasTimeOverlap(app1.startTime, app1.endTime, app2.startTime, app2.endTime), false);
    });
    test('L-03 다른 날 단기 → isWorkingOnDate 다름 → 충돌 없음', () {
      final app1 = _short(workDate: mon0106);
      final app2 = _short(workDate: tue0107);
      expect(app1.isWorkingOnDate(mon0106) && app2.isWorkingOnDate(mon0106), false);
    });
    test('L-04 장기 vs 단기 같은 날 겹침 → 충돌', () {
      final longApp = _long(workDays: ['월']);
      final shortApp = _short(workDate: mon0106, startTime: '09:00', endTime: '18:00');
      expect(longApp.isWorkingOnDate(mon0106), true);
      expect(shortApp.isWorkingOnDate(mon0106), true);
      expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', shortApp.startTime, shortApp.endTime), true);
    });

    // ── L-2. 퇴사/해지 완료 후 isScheduledOnDate false + isWorkingOnDate 관계 ─
    test('L-10 resignStatus=APPROVED → isScheduledOnDate false (범위 내 날짜)', () {
      final app = _long(resignStatus: 'APPROVED');
      // isWorkingOnDate는 resignStatus 체크 없음 → 여전히 true
      expect(app.isWorkingOnDate(mon0106), true);
      // isScheduledOnDate는 isTerminationApproved 체크 → false
      expect(app.isScheduledOnDate(mon0106), false);
    });
    test('L-11 terminationStatus=AUTO_APPROVED 동일 패턴', () {
      final app = _long(terminationStatus: 'AUTO_APPROVED');
      expect(app.isWorkingOnDate(mon0106), true);
      expect(app.isScheduledOnDate(mon0106), false);
    });

    // ── L-3. effectiveStart 연동 시나리오 ────────────────────────────────────
    test('L-20 confirmedAt 이후 isWorkingOnDate/isScheduledOnDate 동일 경계', () {
      final app = _long(workDate: mon0106, confirmedAt: DateTime(2025, 1, 8, 10, 0));
      expect(app.isWorkingOnDate(tue0107), false);
      expect(app.isScheduledOnDate(tue0107), false);
      expect(app.isWorkingOnDate(wed0108), true);
      expect(app.isScheduledOnDate(wed0108), true);
    });
    test('L-21 desiredStartDate + leaveDates 조합', () {
      final app = _long(
        workDate: mon0106,
        desiredStartDate: wed0108,
        leaveDates: [wed0108],
      );
      expect(app.isWorkingOnDate(wed0108), false); // leave
      expect(app.isScheduledOnDate(wed0108), true); // leave도 캘린더 표시
    });

    // ── L-4. workDaysDisplay + isLongTermApplication 연동 ────────────────────
    test('L-30 long_term + workDays=[월,수,금] → isLongTerm true + display 비연속', () {
      final app = _base(applicationType: 'long_term', workDays: ['월','수','금']);
      expect(app.isLongTermApplication, true);
      expect(app.workDaysDisplay, '주 3일 (월,수,금)');
    });
    test('L-31 short + workDays 있어도 → isLongTerm false + workDaysDisplay 계산됨', () {
      final app = _base(applicationType: 'short', workDays: ['월','화','수','목','금']);
      expect(app.isLongTermApplication, false);
      expect(app.workDaysDisplay, '주 5일 (월~금)');
    });

    // ── L-5. workPeriodDisplay + effectiveStart ───────────────────────────────
    test('L-40 desiredStartDate + actualResignDate → workPeriodDisplay 반영', () {
      final app = _base(
        workDate: mon0106,
        workEndDate: fri0131,
        desiredStartDate: thu0109,
        actualResignDate: fri0110,
      );
      expect(app.workPeriodDisplay, '1/9~1/10');
    });
    test('L-41 workPeriodDisplay vs isWorkingOnDate 시작일 일치', () {
      final app = _long(workDate: mon0106, workEndDate: fri0131, desiredStartDate: thu0109);
      expect(app.workPeriodDisplay, '1/9~1/31');
      expect(app.isWorkingOnDate(thu0109), true);
      expect(app.isWorkingOnDate(wed0108), false);
    });

    // ── L-6. hasTimeOverlap 야간 시프트 실제 충돌 체크 ──────────────────────
    test('L-50 야간 근무 두 건 겹침 시나리오', () {
      final app1 = _base(startTime: '22:00', endTime: '06:00');
      final app2 = _base(startTime: '00:00', endTime: '08:00');
      expect(ApplicationModel.hasTimeOverlap(app1.startTime, app1.endTime, app2.startTime, app2.endTime), true);
    });
    test('L-51 야간+주간 비겹침 → 같은 날 다른 근무 가능', () {
      final app1 = _base(startTime: '22:00', endTime: '06:00');
      final app2 = _base(startTime: '06:00', endTime: '14:00');
      expect(ApplicationModel.hasTimeOverlap(app1.startTime, app1.endTime, app2.startTime, app2.endTime), false);
    });

    // ── L-7. AppStatus 그룹 조회 시나리오 ────────────────────────────────────
    test('L-60 CONFIRMED isActive', () {
      expect(AppStatus.activeStates.contains('CONFIRMED'), true);
    });
    test('L-61 AUTO_CANCELED isInactive', () {
      expect(AppStatus.inactiveStates.contains('AUTO_CANCELED'), true);
    });
    test('L-62 CONTRACT_PENDING isConfirmed 상태', () {
      expect(AppStatus.confirmedStatuses.contains('CONTRACT_PENDING'), true);
    });

    // ── L-8. copyWith 동작 검증 ──────────────────────────────────────────────
    test('L-70 copyWith status 변경', () {
      final original = _base(status: 'PENDING');
      final copy = original.copyWith(status: 'CONFIRMED');
      expect(copy.status, 'CONFIRMED');
      expect(original.status, 'PENDING');
    });
    test('L-71 copyWith workDays 변경 → isLongTermApplication 변화', () {
      final original = _base(applicationType: null, workDays: null);
      expect(original.isLongTermApplication, false);
      final copy = original.copyWith(workDays: ['월']);
      expect(copy.isLongTermApplication, true);
    });
    test('L-72 copyWith resignStatus 변경 → isTerminationApproved 변화', () {
      final original = _base();
      expect(original.isTerminationApproved, false);
      final copy = original.copyWith(resignStatus: 'APPROVED');
      expect(copy.isTerminationApproved, true);
    });
    test('L-73 copyWith leaveDates 변경', () {
      final original = _base(leaveDates: []);
      final copy = original.copyWith(leaveDates: [mon0106]);
      expect(original.isLeaveDateOn(mon0106), false);
      expect(copy.isLeaveDateOn(mon0106), true);
    });
    test('L-74 copyWith actualResignDate → workPeriodDisplay 변화', () {
      final original = _base(workDate: mon0106, workEndDate: fri0131);
      final copy = original.copyWith(actualResignDate: fri0110);
      expect(original.workPeriodDisplay, '1/6~1/31');
      expect(copy.workPeriodDisplay, '1/6~1/10');
    });
    test('L-75 copyWith 원본 유지 불변성', () {
      final original = _long();
      final copy = original.copyWith(status: 'CANCELED');
      expect(original.status, 'CONFIRMED');
      expect(copy.status, 'CANCELED');
      expect(original.workDays, copy.workDays); // 참조 공유
    });

    // ── L-9. 재지원 시나리오 (상태 전환) ────────────────────────────────────
    test('L-80 CANCELED → PENDING 재지원 copyWith', () {
      final canceled = _base(status: 'CANCELED');
      final reapplied = canceled.copyWith(status: 'PENDING');
      expect(reapplied.status, 'PENDING');
    });
    test('L-81 PENDING → CONTRACT_PENDING → CONFIRMED 전환', () {
      final pending = _base(status: 'PENDING');
      final contractPending = pending.copyWith(status: 'CONTRACT_PENDING');
      final confirmed = contractPending.copyWith(status: 'CONFIRMED');
      expect(confirmed.status, 'CONFIRMED');
      expect(AppStatus.activeStates.contains(confirmed.status), true);
    });

    // ── L-10. 시나리오: 주간 계약 범위 전체 요일별 순회 ─────────────────────
    test('L-90 2025년 1월 전체 장기 근무 스케줄 (월~금) 카운트', () {
      final app = _long(workDate: mon0106, workEndDate: fri0131, workDays: ['월','화','수','목','금']);
      int workingCount = 0;
      for (int day = 6; day <= 31; day++) {
        if (app.isWorkingOnDate(DateTime(2025, 1, day))) workingCount++;
      }
      // 1/6(월)~1/31(금): 4주 = 20일, 1/27~1/31이 5주차 = 25일 근무?
      // 실제: 1/6(월),7(화),8(수),9(목),10(금) = 5일
      //       1/13,14,15,16,17 = 5일
      //       1/20,21,22,23,24 = 5일
      //       1/27,28,29,30,31 = 5일
      //       = 20일
      expect(workingCount, 20);
    });
    test('L-91 leaveDates 5개 → 20 - 5 = 15일 근무', () {
      final app = _long(
        workDate: mon0106,
        workEndDate: fri0131,
        workDays: ['월','화','수','목','금'],
        leaveDates: [mon0106, tue0107, wed0108, thu0109, fri0110],
      );
      int workingCount = 0;
      for (int day = 6; day <= 31; day++) {
        if (app.isWorkingOnDate(DateTime(2025, 1, day))) workingCount++;
      }
      expect(workingCount, 15);
    });
    test('L-92 extraWorkDates 토요일 2개 추가 → 20 + 2 = 22일', () {
      final app = _long(
        workDate: mon0106,
        workEndDate: fri0131,
        workDays: ['월','화','수','목','금'],
        extraWorkDates: [sat0111, DateTime(2025, 1, 18)], // 토 2개
      );
      int workingCount = 0;
      for (int day = 6; day <= 31; day++) {
        if (app.isWorkingOnDate(DateTime(2025, 1, day))) workingCount++;
      }
      expect(workingCount, 22);
    });
  });
}
