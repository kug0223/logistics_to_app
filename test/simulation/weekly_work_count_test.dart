// test/simulation/weekly_work_count_test.dart
//
// 이번 주 근무 횟수 계산 로직 검증
// work_applicants_dialog._loadApplicants의 weeklyCountMap 로직을 순수 함수로 추출해 테스트.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/utils/week_helper.dart';

// ── 테스트용 AttendanceModel 생성 헬퍼 ──────────────────────────────
AttendanceModel _att({
  required String userId,
  required String businessId,
  required DateTime workDate,
  required String status,
  String? checkIn,
  String? checkOut,
}) =>
    AttendanceModel(
      id: '${userId}_${workDate.millisecondsSinceEpoch}',
      applicationId: 'app_$userId',
      userId: userId,
      businessId: businessId,
      businessName: '테스트 사업장',
      workDate: workDate,
      workType: 'PICK',
      checkIn: checkIn,
      checkOut: checkOut,
      status: status,
      createdAt: DateTime.now(),
    );

// ── 실제 다이얼로그와 동일한 카운트 계산 로직 ─────────────────────
// work_applicants_dialog.dart _loadApplicants 내 weeklyCountMap 빌드 로직 복제
// [uniqueUids] 모든 지원자 uid — 기록 없는 uid도 0으로 초기화
Map<String, int> _computeWeeklyCount(
  Map<String, List<AttendanceModel>> weeklyMap, {
  List<String> uniqueUids = const [],
}) {
  // 모든 지원자를 0으로 초기화 (기록 없는 지원자도 0회 배지 표시)
  final result = <String, int>{for (final uid in uniqueUids) uid: 0};
  for (final entry in weeklyMap.entries) {
    result[entry.key] = entry.value
        .where((a) =>
            a.checkIn != null &&
            a.status != AttendanceModel.statusAbsent &&
            a.status != AttendanceModel.statusNoShow)
        .length;
  }
  return result;
}

// ── 주간 필터 (getWeeklyAttendanceByBusiness의 날짜 필터 복제) ──────
List<AttendanceModel> _filterByWeek(
  List<AttendanceModel> records,
  String businessId,
  DateTime weekStart,
  DateTime weekEnd,
) {
  final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
  final end   = DateTime(weekEnd.year,   weekEnd.month,   weekEnd.day)
      .add(const Duration(days: 1));
  return records
      .where((a) =>
          a.businessId == businessId &&
          a.workDate.isAfter(start.subtract(const Duration(milliseconds: 1))) &&
          a.workDate.isBefore(end))
      .toList();
}

void main() {
  // 기준 날짜: 2026-06-08(월) ~ 2026-06-14(일)
  final monday   = DateTime(2026, 6, 8);
  final tuesday  = DateTime(2026, 6, 9);
  final wednesday= DateTime(2026, 6, 10);
  final thursday = DateTime(2026, 6, 11);
  final friday   = DateTime(2026, 6, 12);
  final sunday   = DateTime(2026, 6, 14);
  final nextWeek = DateTime(2026, 6, 15);  // 다음 주 월요일

  const bizId  = 'biz_001';
  const userId = 'user_A';

  // ═══════════════════════════════════════════════════════════
  // W-A: 기본 카운트 정확성 검증
  // ═══════════════════════════════════════════════════════════
  group('W-A. 기본 카운트 정확성', () {
    test('A-01: 근무 기록 없음 → 0', () {
      final count = _computeWeeklyCount({userId: []});
      expect(count[userId], 0);
    });

    test('A-02: present 1일 → 1', () {
      final count = _computeWeeklyCount({
        userId: [_att(userId: userId, businessId: bizId, workDate: monday,
            status: AttendanceModel.statusPresent, checkIn: '09:00:00')],
      });
      expect(count[userId], 1);
    });

    test('A-03: late 1일 → 1 (지각도 출근한 날)', () {
      final count = _computeWeeklyCount({
        userId: [_att(userId: userId, businessId: bizId, workDate: monday,
            status: AttendanceModel.statusLate, checkIn: '09:30:00')],
      });
      expect(count[userId], 1);
    });

    test('A-04: early_leave 1일 → 1 (조퇴도 출근한 날)', () {
      final count = _computeWeeklyCount({
        userId: [_att(userId: userId, businessId: bizId, workDate: monday,
            status: AttendanceModel.statusEarlyLeave, checkIn: '09:00:00')],
      });
      expect(count[userId], 1);
    });

    test('A-05: absent → 제외 (결근)', () {
      final count = _computeWeeklyCount({
        userId: [_att(userId: userId, businessId: bizId, workDate: monday,
            status: AttendanceModel.statusAbsent, checkIn: null)],
      });
      expect(count[userId], 0);
    });

    test('A-06: NO_SHOW → 제외 (무단 결근)', () {
      final count = _computeWeeklyCount({
        userId: [_att(userId: userId, businessId: bizId, workDate: monday,
            status: AttendanceModel.statusNoShow, checkIn: null)],
      });
      expect(count[userId], 0);
    });

    test('A-07: checkIn=null이면 status 무관하게 제외', () {
      // status=present여도 실제 출근 기록 없으면 카운트 안 함
      final count = _computeWeeklyCount({
        userId: [_att(userId: userId, businessId: bizId, workDate: monday,
            status: AttendanceModel.statusPresent, checkIn: null)],
      });
      expect(count[userId], 0);
    });

    test('A-08: 5일 모두 출근 → 5', () {
      final count = _computeWeeklyCount({
        userId: [
          _att(userId: userId, businessId: bizId, workDate: monday,    status: AttendanceModel.statusPresent,   checkIn: '09:00'),
          _att(userId: userId, businessId: bizId, workDate: tuesday,   status: AttendanceModel.statusLate,      checkIn: '09:30'),
          _att(userId: userId, businessId: bizId, workDate: wednesday, status: AttendanceModel.statusPresent,   checkIn: '09:00'),
          _att(userId: userId, businessId: bizId, workDate: thursday,  status: AttendanceModel.statusEarlyLeave,checkIn: '09:00'),
          _att(userId: userId, businessId: bizId, workDate: friday,    status: AttendanceModel.statusPresent,   checkIn: '09:00'),
        ],
      });
      expect(count[userId], 5);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // W-B: 노쇼/결근 혼합 시나리오
  // ═══════════════════════════════════════════════════════════
  group('W-B. 노쇼·결근 혼합', () {
    test('B-01: 출근3 + 노쇼1 + 결근1 → 3', () {
      final count = _computeWeeklyCount({
        userId: [
          _att(userId: userId, businessId: bizId, workDate: monday,    status: AttendanceModel.statusPresent, checkIn: '09:00'),
          _att(userId: userId, businessId: bizId, workDate: tuesday,   status: AttendanceModel.statusPresent, checkIn: '09:00'),
          _att(userId: userId, businessId: bizId, workDate: wednesday, status: AttendanceModel.statusNoShow,  checkIn: null),
          _att(userId: userId, businessId: bizId, workDate: thursday,  status: AttendanceModel.statusAbsent,  checkIn: null),
          _att(userId: userId, businessId: bizId, workDate: friday,    status: AttendanceModel.statusPresent, checkIn: '09:00'),
        ],
      });
      expect(count[userId], 3);
    });

    test('B-02: 전부 노쇼 → 0', () {
      final count = _computeWeeklyCount({
        userId: List.generate(5, (i) =>
          _att(userId: userId, businessId: bizId,
              workDate: monday.add(Duration(days: i)),
              status: AttendanceModel.statusNoShow, checkIn: null)),
      });
      expect(count[userId], 0);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // W-C: 사업장 필터 검증 (해당 사업장만 집계)
  // ═══════════════════════════════════════════════════════════
  group('W-C. 사업장 필터', () {
    const otherBizId = 'biz_OTHER';

    test('C-01: 다른 사업장 근무는 카운트에 포함되지 않음', () {
      final allRecords = [
        _att(userId: userId, businessId: bizId,      workDate: monday,   status: AttendanceModel.statusPresent, checkIn: '09:00'),
        _att(userId: userId, businessId: otherBizId, workDate: tuesday,  status: AttendanceModel.statusPresent, checkIn: '09:00'),
        _att(userId: userId, businessId: otherBizId, workDate: wednesday,status: AttendanceModel.statusPresent, checkIn: '09:00'),
      ];

      // bizId만 필터
      final ws = WeekHelper.weekStart(monday);
      final we = WeekHelper.weekEnd(monday);
      final filtered = _filterByWeek(allRecords, bizId, ws, we);
      final grouped = <String, List<AttendanceModel>>{userId: filtered};
      final count = _computeWeeklyCount(grouped);

      expect(count[userId], 1, reason: '해당 사업장 근무 1일만 카운트');
    });

    test('C-02: 완전 타 사업장 근무자 → 해당 사업장에서 0', () {
      final allRecords = [
        _att(userId: userId, businessId: otherBizId, workDate: monday,  status: AttendanceModel.statusPresent, checkIn: '09:00'),
        _att(userId: userId, businessId: otherBizId, workDate: tuesday, status: AttendanceModel.statusPresent, checkIn: '09:00'),
      ];

      final ws = WeekHelper.weekStart(monday);
      final we = WeekHelper.weekEnd(monday);
      final filtered = _filterByWeek(allRecords, bizId, ws, we);
      final grouped = <String, List<AttendanceModel>>{userId: filtered};
      final count = _computeWeeklyCount(grouped);

      expect(count[userId] ?? 0, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // W-D: 주간 범위 필터 검증
  // ═══════════════════════════════════════════════════════════
  group('W-D. 주간 범위 필터', () {
    test('D-01: WeekHelper.weekStart(월요일) → 같은 월요일', () {
      final ws = WeekHelper.weekStart(monday);
      expect(ws, DateTime(2026, 6, 8));
    });

    test('D-02: WeekHelper.weekEnd(월요일) → 같은 주 일요일', () {
      final we = WeekHelper.weekEnd(monday);
      expect(we, DateTime(2026, 6, 14));
    });

    test('D-03: 이번 주 기록만 포함 (다음 주 제외)', () {
      final allRecords = [
        _att(userId: userId, businessId: bizId, workDate: friday,    status: AttendanceModel.statusPresent, checkIn: '09:00'),
        _att(userId: userId, businessId: bizId, workDate: sunday,    status: AttendanceModel.statusPresent, checkIn: '09:00'),
        _att(userId: userId, businessId: bizId, workDate: nextWeek,  status: AttendanceModel.statusPresent, checkIn: '09:00'),
      ];

      final ws = WeekHelper.weekStart(monday);
      final we = WeekHelper.weekEnd(monday);
      final filtered = _filterByWeek(allRecords, bizId, ws, we);

      expect(filtered.length, 2, reason: '이번 주(금·일)만, 다음 주 월요일 제외');
    });

    test('D-04: 지난 주 기록 제외', () {
      final lastSunday = DateTime(2026, 6, 7); // 저번 주 일요일
      final allRecords = [
        _att(userId: userId, businessId: bizId, workDate: lastSunday, status: AttendanceModel.statusPresent, checkIn: '09:00'),
        _att(userId: userId, businessId: bizId, workDate: monday,     status: AttendanceModel.statusPresent, checkIn: '09:00'),
      ];

      final ws = WeekHelper.weekStart(monday);
      final we = WeekHelper.weekEnd(monday);
      final filtered = _filterByWeek(allRecords, bizId, ws, we);

      expect(filtered.length, 1, reason: '이번 주 월요일만');
    });

    test('D-05: 기준일이 금요일이어도 같은 주(월~일) 범위 조회', () {
      final ws = WeekHelper.weekStart(friday);
      final we = WeekHelper.weekEnd(friday);
      // 금요일이 포함된 주: 2026-06-08(월) ~ 2026-06-14(일)
      expect(ws, DateTime(2026, 6, 8));
      expect(we, DateTime(2026, 6, 14));
    });

    test('D-06: 슬롯 날짜 기준 주 계산 (미래 슬롯)', () {
      final futureSlot = DateTime(2026, 7, 15); // 수요일
      final ws = WeekHelper.weekStart(futureSlot);
      final we = WeekHelper.weekEnd(futureSlot);
      // 2026-07-13(월) ~ 2026-07-19(일)
      expect(ws.weekday, 1, reason: '월요일');
      expect(we.weekday, 7, reason: '일요일');
      expect(we.difference(ws).inDays, 6);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // W-E: 복수 지원자 동시 집계
  // ═══════════════════════════════════════════════════════════
  group('W-E. 복수 지원자 집계', () {
    const userB = 'user_B';
    const userC = 'user_C';

    test('E-01: 3명 각각 근무 횟수 독립 계산', () {
      final weeklyMap = {
        userId: [
          _att(userId: userId, businessId: bizId, workDate: monday,   status: AttendanceModel.statusPresent, checkIn: '09:00'),
          _att(userId: userId, businessId: bizId, workDate: tuesday,  status: AttendanceModel.statusPresent, checkIn: '09:00'),
          _att(userId: userId, businessId: bizId, workDate: wednesday,status: AttendanceModel.statusPresent, checkIn: '09:00'),
        ],
        userB: [
          _att(userId: userB, businessId: bizId, workDate: monday,  status: AttendanceModel.statusLate,    checkIn: '09:35'),
          _att(userId: userB, businessId: bizId, workDate: tuesday, status: AttendanceModel.statusNoShow,  checkIn: null),
        ],
        userC: <AttendanceModel>[],
      };

      final count = _computeWeeklyCount(weeklyMap);
      expect(count[userId], 3, reason: 'user_A: 3일 출근');
      expect(count[userB],  1, reason: 'user_B: 지각 1일 출근, 노쇼 1일 제외');
      expect(count[userC],  0, reason: 'user_C: 이번 주 미근무');
    });

    test('E-02: 동일 날짜 같은 사업장 다른 슬롯 2회 출근 → 2 카운트', () {
      // 하루에 오전/오후 두 슬롯 모두 근무한 경우
      final count = _computeWeeklyCount({
        userId: [
          _att(userId: userId, businessId: bizId, workDate: monday,
              status: AttendanceModel.statusPresent, checkIn: '09:00'),
          _att(userId: userId, businessId: bizId, workDate: monday,
              status: AttendanceModel.statusPresent, checkIn: '14:00'),
        ],
      });
      // 날짜 기준이 아닌 출근 기록 기준이므로 2
      expect(count[userId], 2);
    });

    test('E-03: 지원자 uid가 맵에 없으면 0 반환 (null safe)', () {
      final count = _computeWeeklyCount({});
      expect(count['unknown_user'] ?? 0, 0);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // W-F: 기회 안배 시나리오 (관리자 의사결정 지원)
  // ═══════════════════════════════════════════════════════════
  group('W-F. 기회 안배 시나리오', () {
    test('F-01: 0회 지원자 vs 5회 지원자 → 순위 비교 가능', () {
      final newbie = 'user_new';
      final busy   = 'user_busy';
      final map = {
        newbie: <AttendanceModel>[],
        busy: List.generate(5, (i) =>
          _att(userId: busy, businessId: bizId,
              workDate: monday.add(Duration(days: i)),
              status: AttendanceModel.statusPresent, checkIn: '09:00')),
      };
      final count = _computeWeeklyCount(map);
      expect(count[newbie] ?? 0, lessThan(count[busy]!));
      expect(count[newbie] ?? 0, 0);
      expect(count[busy], 5);
    });

    test('F-02: 조퇴자도 근무 횟수에 포함 (기회 계산 공정성)', () {
      // 조퇴를 present 대신 early_leave로 기록해도 동일하게 카운트
      final earlyLeaver = 'user_early';
      final normalWorker = 'user_normal';
      final map = {
        earlyLeaver: [
          _att(userId: earlyLeaver, businessId: bizId, workDate: monday,
              status: AttendanceModel.statusEarlyLeave, checkIn: '09:00', checkOut: '14:00'),
        ],
        normalWorker: [
          _att(userId: normalWorker, businessId: bizId, workDate: monday,
              status: AttendanceModel.statusPresent, checkIn: '09:00', checkOut: '18:00'),
        ],
      };
      final count = _computeWeeklyCount(map);
      expect(count[earlyLeaver],  1, reason: '조퇴도 출근한 날이므로 1');
      expect(count[normalWorker], 1);
    });

    test('F-03: 배지 색상 기준 검증 (0회=회색, 1~2=초록, 3~4=파랑, 5+=주황)', () {
      // 실제 Color 객체가 아닌 임계값만 검증
      String _badgeLevel(int count) {
        if (count == 0) return 'grey';
        if (count <= 2)  return 'green';
        if (count <= 4)  return 'blue';
        return 'orange';
      }

      expect(_badgeLevel(0), 'grey');
      expect(_badgeLevel(1), 'green');
      expect(_badgeLevel(2), 'green');
      expect(_badgeLevel(3), 'blue');
      expect(_badgeLevel(4), 'blue');
      expect(_badgeLevel(5), 'orange');
      expect(_badgeLevel(7), 'orange');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // W-G: 엣지케이스
  // ═══════════════════════════════════════════════════════════
  group('W-G. 엣지케이스', () {
    test('G-01: 빈 weeklyMap → 빈 결과', () {
      expect(_computeWeeklyCount({}), isEmpty);
    });

    test('G-02: checkIn=null, status=present → 제외 (이상 데이터 방어)', () {
      // 실수로 status=present이지만 checkIn이 없는 레코드
      final count = _computeWeeklyCount({
        userId: [_att(userId: userId, businessId: bizId, workDate: monday,
            status: AttendanceModel.statusPresent, checkIn: null)],
      });
      expect(count[userId], 0);
    });

    test('G-03: checkIn 있음, status=absent → 제외 (이상 데이터 방어)', () {
      // 결근 처리됐지만 checkIn이 남아있는 레코드
      final count = _computeWeeklyCount({
        userId: [_att(userId: userId, businessId: bizId, workDate: monday,
            status: AttendanceModel.statusAbsent, checkIn: '09:00')],
      });
      expect(count[userId], 0);
    });

    test('G-04: 결과값은 항상 0 이상', () {
      final count = _computeWeeklyCount({userId: []});
      expect(count[userId]! >= 0, isTrue);
    });

    test('G-05: 주간 경계 — 월요일 00:00 포함, 다음 월요일 00:00 제외', () {
      final ws = WeekHelper.weekStart(monday);
      final we = WeekHelper.weekEnd(monday);
      final allRecords = [
        _att(userId: userId, businessId: bizId, workDate: ws,       status: AttendanceModel.statusPresent, checkIn: '09:00'),  // 월요일 — 포함
        _att(userId: userId, businessId: bizId, workDate: we,       status: AttendanceModel.statusPresent, checkIn: '09:00'),  // 일요일 — 포함
        _att(userId: userId, businessId: bizId, workDate: nextWeek, status: AttendanceModel.statusPresent, checkIn: '09:00'),  // 다음 월 — 제외
      ];
      final filtered = _filterByWeek(allRecords, bizId, ws, we);
      expect(filtered.length, 2);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // W-H: 버그 수정 검증 (3가지 버그 회귀 방지)
  // ═══════════════════════════════════════════════════════════
  group('W-H. 버그 수정 회귀 방지', () {
    const userB = 'user_B';

    // Bug 1: 이번 주 미근무 지원자에게 0회 배지가 표시되지 않던 문제
    test('H-01: 기록 없는 지원자도 0으로 초기화됨 (uniqueUids 시드)', () {
      // weeklyMap에 userB 기록 전혀 없음 → 이전 코드: null, 수정 후: 0
      final count = _computeWeeklyCount(
        {userId: [_att(userId: userId, businessId: bizId, workDate: monday,
            status: AttendanceModel.statusPresent, checkIn: '09:00')]},
        uniqueUids: [userId, userB],
      );
      expect(count[userId], 1);
      expect(count[userB],  0, reason: '기록 없어도 0으로 초기화됨');
    });

    test('H-02: 모든 지원자 기록 없음 → 전원 0 (not null)', () {
      final uids = [userId, userB, 'user_C'];
      final count = _computeWeeklyCount({}, uniqueUids: uids);
      for (final uid in uids) {
        expect(count[uid], 0, reason: '$uid: null 아닌 0');
      }
    });

    test('H-03: weeklyMap에 있는 uid만 덮어씀, 나머지는 0 유지', () {
      // userB만 근무 기록 있음 → userId는 0 유지
      final count = _computeWeeklyCount(
        {userB: [
          _att(userId: userB, businessId: bizId, workDate: monday,
              status: AttendanceModel.statusPresent, checkIn: '09:00'),
          _att(userId: userB, businessId: bizId, workDate: tuesday,
              status: AttendanceModel.statusPresent, checkIn: '09:00'),
        ]},
        uniqueUids: [userId, userB],
      );
      expect(count[userId], 0);
      expect(count[userB],  2);
    });

    // Bug 2: SizedBox.shrink() 간격 아티팩트 — UI 로직 검증 (null vs 0 구분)
    test('H-04: null과 0은 의미가 다름 (null=로딩 전, 0=로딩 후 미근무)', () {
      // 로딩 전: _weeklyWorkCountMap에 uid 없음 → null → 배지 미표시
      final emptyMap = <String, int>{};
      expect(emptyMap[userId], isNull, reason: '로딩 전: null → 배지 숨김');

      // 로딩 후: 0으로 초기화됨 → 0 → 회색 0회 배지 표시
      final loadedMap = _computeWeeklyCount({}, uniqueUids: [userId]);
      expect(loadedMap[userId], 0, reason: '로딩 후: 0 → 배지 표시');
    });

    // Bug 3: 재로딩 시 stale 데이터 잔존
    test('H-05: 재로딩 후 이전 지원자 데이터가 덮어써짐 (clear+addAll)', () {
      // 1차 로딩: userA 3회
      final firstLoad = _computeWeeklyCount(
        {userId: List.generate(3, (i) =>
          _att(userId: userId, businessId: bizId,
              workDate: monday.add(Duration(days: i)),
              status: AttendanceModel.statusPresent, checkIn: '09:00'))},
        uniqueUids: [userId],
      );

      // 2차 로딩(재로딩): userA 기록 없음 → 0으로 초기화
      final secondLoad = _computeWeeklyCount({}, uniqueUids: [userId]);

      // clear() 후 addAll() 시뮬레이션
      final stateMap = <String, int>{}
        ..addAll(firstLoad);         // 1차 로딩
      expect(stateMap[userId], 3);

      stateMap
        ..clear()                    // clear() — 핵심 수정
        ..addAll(secondLoad);        // 2차 로딩
      expect(stateMap[userId], 0, reason: 'clear 후 재로딩: 0으로 갱신됨');
    });

    test('H-06: clear 없이 addAll만 하면 stale 잔존 (수정 전 동작 재현)', () {
      final firstLoad  = {userId: 3};
      final secondLoad = <String, int>{};  // 2차 로딩에 userId 없음

      final stateMap = <String, int>{}..addAll(firstLoad);
      stateMap.addAll(secondLoad);  // clear 없이 addAll만
      expect(stateMap[userId], 3,  reason: 'stale 잔존 확인 (수정 전 버그)');
    });

    test('H-07: 0회 배지 색상은 회색 (기회 여유 신호)', () {
      String level(int c) => c == 0 ? 'grey' : c <= 2 ? 'green' : c <= 4 ? 'blue' : 'orange';
      expect(level(0), 'grey',   reason: '미근무자: 회색 배지');
      expect(level(1), 'green',  reason: '1회: 초록 (여유)');
      expect(level(5), 'orange', reason: '5회+: 주황 (다른 지원자 고려 신호)');
    });
  });
}
