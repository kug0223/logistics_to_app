# Category C: 근태 관리 기능 테스트 시나리오 100개

> 감사 기준일: 2026-06-12  
> 대상 파일: `attendance_firestore.dart`, `attendance_model.dart`, `attendance_status_helper.dart`, `attendance_status_dialog.dart`  
> 발견 버그: **BUG-C-01**, **BUG-C-02**, **BUG-C-03** (아래 표 내 🔴 표시)

---

## 버그 요약

| ID | 심각도 | 위치 | 설명 | 상태 |
|----|--------|------|------|------|
| BUG-C-01 | MEDIUM | `attendance_status_dialog.dart:4314` | 관리자 수동 출근 생성 시 `add()` 랜덤 docId 사용 → 워커 자기 checkIn과 중복 기록 가능 | **수정 완료** |
| BUG-C-02 | MEDIUM | `attendance_status_dialog.dart:348` | `_getConfirmedWorkersForDate()` — extraWorkDates 체크 없어 추가근무 승인된 비근무일 근무자 누락 | **수정 완료** |
| BUG-C-03 | LOW | `attendance_firestore.dart:780` | `cancelScheduleChangeRequest()` 상태 검증 없음 — REJECTED/CANCELED 요청도 재취소 가능 | **수정 완료** |

---

## C-001~020: 출근 체크 (checkIn)

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| C-001 | 정상 | GPS 방식 단기 근무 출근 체크 | `attendance/${appId}_날짜` docId 생성, status='present', wageStatus='pending' | `checkIn():118-136` | ✅ |
| C-002 | 정상 | 비콘 방식 출근 체크 (lat/lng=null) | GPS 없이도 checkIn 성공, checkInMethod='beacon' | `checkIn():21-22` `if (latitude != null)` | ✅ |
| C-003 | 정상 | 장기 근무자 출근 (workDate=오늘) | docId = `${appId}_오늘날짜`, 정상 출근 처리 | `checkIn():92-94` | ✅ |
| C-004 | 정상 | 정각 출근 (scheduledStartTime 동일) | `isLate=false` → status='present' | `isLate():actual - scheduled == 0 → false` | ✅ |
| C-005 | 정상 | 1분 지각 출근 | `isLate=true` → status='late' | `isLate():actual - scheduled = 1 > 0` | ✅ |
| C-006 | 정상 | scheduledStartTime 미전달 출근 | 지각 판단 없음, status='present' | `checkIn():103` `scheduledStartTime != null &&` | ✅ |
| C-007 | 경계값 | 야간 시프트(22:00~02:00) — 다음날 01:00 출근 | `isNextDay=true`, actual=60+1440=1500, scheduled=1320 → isLate=true | `checkIn():100-104` + `isLate():41` | ✅ |
| C-008 | 경계값 | 야간 시프트 정각(22:00) 출근 | `isNextDay=false`, actual=1320, scheduled=1320 → 차이=0 → present | `isLate():40` `actual - scheduled > 0` | ✅ |
| C-009 | 경계값 | 제재 중인 사용자(restrictedUntil 미래) 출근 | "현재 근무 제재 중입니다" 예외 | `checkIn():40-43` | ✅ |
| C-010 | 경계값 | 제재 만료 사용자 출근 | 정상 출근 허용 | `checkIn():40` `.isAfter(DateTime.now())` | ✅ |
| C-011 | 경계값 | 타인의 applicationId로 출근 시도 | "본인의 지원서만 출근 체크가 가능합니다" 예외 | `checkIn():57-60` | ✅ |
| C-012 | 경계값 | 사업장 불일치(appBusinessId ≠ businessId) 출근 | "지원서와 사업장 정보가 일치하지 않습니다" 예외 | `checkIn():63-66` | ✅ |
| C-013 | 경계값 | 승인된 휴무일 출근 시도 | "오늘은 승인된 휴무일입니다" 예외 | `checkIn():70-72` | ✅ |
| C-014 | 경계값 | 퇴사 완료 이후 날짜 출근 시도 | "퇴사 처리가 완료된 근무입니다" 예외 | `checkIn():75-78` | ✅ |
| C-015 | 경계값 | PENDING 상태 지원서 출근 시도 | "확정된 근무만 출퇴근 체크가 가능합니다" 예외 | `checkIn():84-86` | ✅ |
| C-016 | 경계값 | CONTRACT_PENDING 상태 지원서 출근 | 계약서 서명 전이어도 출근 허용 (의도된 정책) | `checkIn():81-83` 주석 | ✅ |
| C-017 | 경계값 | 이미 출근한 사용자 재출근 시도 | "오늘 이미 출근하셨습니다" 예외, 중복 방지 | `checkIn():114-116` 트랜잭션 내 체크 | ✅ |
| C-018 | 경계값 | 동시 출근 요청 2개 | 트랜잭션으로 첫 번째만 성공, 두 번째는 "이미 출근" | `checkIn():112` `runTransaction` | ✅ |
| C-019 | 오류복구 | 오프라인 상태 출근 시도 | "출근 체크를 하려면 인터넷 연결이 필요합니다" | `checkIn():26` `NetworkChecker` | ✅ |
| C-020 | 경계값 | 퇴사일 당일 출근 (`actualResignDate == workDate`) | `!workDate.isBefore(actualResignDate)` → 차단 | `checkIn():75-78` | ✅ |

---

## C-021~040: 퇴근 체크 (checkOut)

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| C-021 | 정상 | 정상 퇴근 (scheduledEndTime 미전달) | checkOut 저장, workHours 계산, status 유지 | `checkOut():187-197` | ✅ |
| C-022 | 정상 | 정각 퇴근 (scheduledEndTime 동일) | `isEarlyLeave=false` → status 유지 | `isEarlyLeave():86` `scheduled - actual == 0 → false` | ✅ |
| C-023 | 정상 | 1분 조퇴 | `isEarlyLeave=true` → status='early_leave' | `isEarlyLeave():scheduled - actual = 1 > 0` | ✅ |
| C-024 | 정상 | 야간 자정 넘김 퇴근 (출근 14:30 / 퇴근 01:00) | checkIn=14:30, checkOut=01:00 → actual보정(25:00) → scheduledEnd(23:00) 이후 → 조퇴 아님 | `isEarlyLeave():81-84` | ✅ |
| C-025 | 정상 | 최초 퇴근 시 originalCheckOut 저장 | `if (data['originalCheckOut'] == null)` → 최초에만 보존 | `checkOut():188-190` | ✅ |
| C-026 | 경계값 | 이미 퇴근한 사용자 재퇴근 시도 | "이미 퇴근하셨습니다" 예외 | `checkOut():171` | ✅ |
| C-027 | 경계값 | 출근 기록 없는 attendanceId로 퇴근 시도 | "출근 기록을 찾을 수 없습니다" 예외 | `checkOut():169` | ✅ |
| C-028 | 경계값 | checkIn 시간 필드 없는 기록에서 퇴근 시도 | "출근 기록에 시간 정보가 없습니다" 예외 | `checkOut():174` | ✅ |
| C-029 | 경계값 | workHours 계산 — 8시간 30분 근무 | `workMins = 510`, `workHours = 8.5` | `checkOut():175-176` | ✅ |
| C-030 | 경계값 | 동시 퇴근 요청 2개 | 트랜잭션으로 첫 번째만 성공 | `checkOut():167` `runTransaction` | ✅ |
| C-031 | 경계값 | 지각 출근 후 정시 퇴근 | 출근 시 status='late' → 퇴근 시 isEarlyLeave=false → updatedStatus='late' | `checkOut():183-185` `updatedStatus = isEarlyLeave ? early_leave : currentStatus` | ✅ |
| C-032 | 경계값 | 정시 출근 후 조퇴 | 출근 시 status='present' → 퇴근 시 isEarlyLeave=true → updatedStatus='early_leave' | `checkOut():183-185` | ✅ |
| C-033 | 경계값 | 지각 출근 후 조퇴 | 출근 시 status='late', 퇴근 시 isEarlyLeave=true → updatedStatus='early_leave' (조퇴 우선) | `checkOut():183` `isEarlyLeave ? early_leave : currentStatus` | ✅ |
| C-034 | 오류복구 | 오프라인 상태 퇴근 시도 | "퇴근 체크를 하려면 인터넷 연결이 필요합니다" | `checkOut():156` `NetworkChecker` | ✅ |
| C-035 | 정상 | 연장 퇴근 (scheduledEndTime 이후 퇴근) | isEarlyLeave=false → 연장 배지는 별도 `AttendanceBadgeHelper.compute()` 처리 | `isEarlyLeave()` + `AttendanceBadgeHelper` | ✅ |
| C-036 | 경계값 | 16시간 초과 근무 퇴근 시도 (관리자 수동) | `isValidWorkPeriod():minutes > maxHours*60 → false` → 에러 토스트 | `_updateAttendanceTime:4181-4184` | ✅ |
| C-037 | 경계값 | 자정 넘김 야간 근무 workHours 계산 | `minutesBetween()` 자정 보정 → e += 1440 | `minutesBetween():23` | ✅ |
| C-038 | 경계값 | 출퇴근 시간 역전 (checkIn 18:00 / checkOut 09:00) | `isValidWorkPeriod()` false → 관리자 수정 시 차단 | `_updateAttendanceTime:4181-4184` | ✅ |
| C-039 | 경계값 | 출퇴근 동일 시간 (0분 근무) | `minutesBetween()` e==s → 0분 → `isValidWorkPeriod():minutes > 0 → false` | `minutesBetween():23` 주석 | ✅ |
| C-040 | 정상 | 조출 (30분 이상 일찍 출근) | `isEarlyArrival(checkIn, scheduled, threshold=30)` → 조출 배지 표시 | `AttendanceStatusHelper.isEarlyArrival():52-62` | ✅ |

---

## C-041~060: 출근 기록 조회 / 관리자 수동 처리

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| C-041 | 정상 | 오늘 출근 기록 조회 (당일 checkIn 있음) | 오늘 docId 조회 → 존재 → 반환 | `getTodayAttendance():228-235` | ✅ |
| C-042 | 정상 | 야간 근무 퇴근 전 기록 조회 (어제 날짜 docId) | 오늘 docId 없음 → 어제 docId → 존재(checkOut null) → 반환 | `getTodayAttendance():228-235` | ✅ |
| C-043 | 경계값 | 장기 근무자 어제 완료 기록이 오늘 조회에서 반환 가능성 | 오늘 docId 없음 → 어제 docId(어제 완료) → 반환 → 화면이 workDate 검증해야 함 | `getTodayAttendance():228` fallback 로직 | ⚠️ 화면 레벨 검증 필요 |
| C-044 | 경계값 | 타인 applicationId 조회 시 소유자 검증 | `att.userId != userId → continue` | `getTodayAttendance():234` | ✅ |
| C-045 | 정상 | 사업장별 오늘 출근 현황 조회 | businessId + workDate 범위 쿼리 | `getTodayAttendanceByBusiness():257-264` | ✅ |
| C-046 | 정상 | 특정 날짜 출근 기록 조회 | workDate 범위 쿼리 | `getAttendanceByDate():337-343` | ✅ |
| C-047 | 정상 | 월별 출근 기록 조회 | userId + workDate 범위 쿼리, 오름차순 정렬 | `getMyMonthlyAttendances():367-373` | ✅ |
| C-048 | **🔴 BUG-C-01** | 관리자 수동 출근 생성 (출근 기록 없음) | 실제: `add()` 랜덤 docId / 기대: `${appId}_날짜` 결정적 docId | `_createOrUpdateAttendance:4314` | ❌ BUG-C-01 |
| C-049 | 경계값 | 관리자 수동 출근 생성 후 워커 자기 checkIn | 두 개의 출근 기록 공존 → admin dialog에서 마지막 기록만 표시 | BUG-C-01 파생 | ⚠️ |
| C-050 | 정상 | 관리자 기존 기록 있는 경우 수동 출근 수정 | `doc(existingAttendance.id).update()` → 기존 docId 유지 | `_createOrUpdateAttendance:4301-4311` | ✅ |
| C-051 | 정상 | 관리자 출퇴근 시간 수정 | `isModified=true`, originalCheckIn/Out 최초 보존, status/workHours 재계산 | `_updateAttendanceTime:4218-4253` | ✅ |
| C-052 | 경계값 | 이체완료(transferred) 기록 시간 수정 시도 | "이체 완료된 급여는 수정할 수 없습니다" 에러, 차단 | `_updateAttendanceTime:4172-4175` | ✅ |
| C-053 | 경계값 | wageConfirmed 기록 시간 수정 | 시간 수정 허용, wageStatus → pending 초기화, "급여를 다시 계산해주세요" 토스트 | `_updateAttendanceTime:4256-4261` | ✅ |
| C-054 | 경계값 | wageCalculated 기록 시간 수정 | 위와 동일 (wageStatus pending 초기화) | `_updateAttendanceTime:4256` | ✅ |
| C-055 | 정상 | 출퇴근 초기화 (미출근 상태로 되돌림) | checkIn/Out 필드 FieldValue.delete(), isModified=true, status='present' | `_updateAttendanceTime:4188-4206` | ✅ |
| C-056 | 경계값 | 출퇴근 초기화 시 status='present' 설정 (checkIn null인데 present) | 미출근 상태이나 status='present' → UI에서 checkIn null 체크로 "미출근" 표시 | `_updateAttendanceTime:4200` | ⚠️ DB 상태 불일치 (기능적 무해) |
| C-057 | 정상 | 관리자 출근 시간만 수정 (퇴근 시간 유지) | `effectiveCheckOut = attendance.checkOut` → workHours 재계산 | `_updateAttendanceTime:4209-4253` | ✅ |
| C-058 | 경계값 | originalCheckIn 이미 있는 기록 재수정 | `if (attendance.originalCheckIn == null)` → 원본 덮어쓰기 방지 | `_updateAttendanceTime:4220-4223` | ✅ |
| C-059 | 정상 | 주간 출근 기록 일괄 조회 (weekStart~weekEnd) | userId별 AttendanceModel 리스트 반환 | `getWeeklyAttendanceByBusiness():872-884` | ✅ |
| C-060 | 경계값 | 주간 조회 weekEnd+1일 미포함 | `end = weekEnd + 1day` → `workDate < end` → inclusive end 처리 | `getWeeklyAttendanceByBusiness():873-874` | ✅ |

---

## C-061~075: 노쇼 처리

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| C-061 | 정상 | 미출근 근무자 노쇼 처리 | attendance 기록 생성(status=NO_SHOW), application cancelConfirmed 호출 | `_markNoShow():4400-4440` | ✅ |
| C-062 | 정상 | 노쇼 처리 선택: 패널티 없음 취소 | `cancelConfirmedNoPenalty` 호출, noShow 기록 없음 | `_markNoShow():4383-4386` | ✅ |
| C-063 | 경계값 | 이미 출근한 근무자 노쇼 처리 | attendance 기록 update (기존 기록에 status=NO_SHOW) | `_markNoShow():4402-4409` | ✅ |
| C-064 | 경계값 | 노쇼 처리 1단계(attendance 생성) 성공, 2단계(application 취소) 실패 | attendance=NO_SHOW 유지, application=CONFIRMED 유지 → 불일치 | `_markNoShow()` 2단계 분리 | ⚠️ 원자성 부재 |
| C-065 | 정상 | 노쇼 처리 후 당일명단 상태 표시 | `_getAttendanceStatus()` → status='noshow' → 배지 표시 | `_getAttendanceStatus():444-453` | ✅ |
| C-066 | 경계값 | 노쇼 처리 후 `_processedCount` 증가 | `attendance.status == statusNoShow → count++` | `_processedCount:117-119` | ✅ |
| C-067 | 경계값 | 노쇼 처리 후 _isAllClosed 체크 | noshow 상태는 마감 완료로 인식 | `_isAllClosed:163-164` | ✅ |
| C-068 | 경계값 | 노쇼 처리 후 신뢰도 감점 | `TrustScoreService.onNoShow()` 호출 (UI 레벨) | `_markNoShow:` TrustScoreService 호출 부분 | ✅ |
| C-069 | 경계값 | 노쇼 3회 도달 → 3일 제재 | `_applyNoShowPenaltyTransactional` 호출 (B 카테고리 테스트와 동일 경로) | application_firestore `_applyNoShowPenalty` | ✅ |
| C-070 | 경계값 | 이미 노쇼 처리된 근무자 재노쇼 처리 시도 | UI에서 노쇼 상태인 경우 "노쇼 처리" 버튼 비활성화 | `_buildMoreMenu` 노쇼 처리 조건부 표시 | ✅ |
| C-071 | 정상 | 노쇼 처리된 근무자 통계에서 제외 | `_calculateStats()` — noshow 케이스 checkedIn/checkedOut 불포함 | `_calculateStats():677` | ✅ |
| C-072 | 경계값 | wageTransferred 상태에서 노쇼 처리 | 이체완료 후 노쇼 처리 가능 여부 — 명시적 차단 없음 | `_markNoShow()` transferred 체크 없음 | ⚠️ 이체완료 후 노쇼 처리 가능 |
| C-073 | 경계값 | 노쇼 처리 취소 (노쇼 해제) | status → null, isModified=true → 미출근 상태 복귀 | `_unmarkNoShow()` (UI 더보기 메뉴) | ✅ |
| C-074 | 경계값 | 노쇼 처리 후 노쇼 해제 → 출근 처리 | status 복귀 후 수동 출근 처리 가능 | 노쇼해제 → _createOrUpdateAttendance | ✅ |
| C-075 | 경계값 | 노쇼 처리 시 기존 출근 기록 보존 | `if (existingAttendance != null) update()` → checkIn 필드 유지 | `_markNoShow():4403-4409` status만 UPDATE | ✅ |

---

## C-076~085: 스케줄 변경 요청 (Schedule Change Request)

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| C-076 | 정상 | 근무자 휴무 요청 생성 (LEAVE) | Firestore add, requestedBy=APPLICANT → 관리자 알림 | `createScheduleChangeRequest():404-425` | ✅ |
| C-077 | 정상 | 관리자 휴무 요청 승인 | 트랜잭션: status=APPROVED + leaveDates 추가, 알림 전송 | `approveScheduleChangeRequest():527-630` | ✅ |
| C-078 | 정상 | 휴무 승인 후 leaveDates 추가 → 당일 출근 차단 | `checkIn():70-72` `isLeaveDateOn(workDate)` → 예외 | `checkIn():70-72` | ✅ |
| C-079 | 정상 | 관리자 추가근무 요청 승인 (EXTRA_WORK) | extraWorkDates 추가 → isExtraWorkDateOn=true → 비근무 요일 출근 허용 | `approveScheduleChangeRequest():581-586` | ✅ |
| C-080 | 정상 | 휴무 취소 승인 (CANCEL_LEAVE) | leaveDates에서 제거 → isLeaveDateOn=false → 출근 가능 | `approveScheduleChangeRequest():589-596` | ✅ |
| C-081 | 정상 | 추가근무 취소 승인 (CANCEL_EXTRA) | extraWorkDates에서 제거 → 비근무 요일에 더 이상 명단 미표시 | `approveScheduleChangeRequest():597-604` | ✅ |
| C-082 | 경계값 | 이미 처리된 요청 중복 승인 | "이미 처리된 요청" 예외, 트랜잭션 내 isPending 체크 | `approveScheduleChangeRequest():541-544` | ✅ |
| C-083 | 경계값 | 이미 처리된 요청 중복 거절 | "이미 처리된 요청" 예외 | `rejectScheduleChangeRequest():648` | ✅ |
| C-084 | 정상 | 요청 거절 시 rejectReason 저장 | `rejectReason` 필드 저장, 알림 전송 | `rejectScheduleChangeRequest():651-655` | ✅ |
| C-085 | **🔴 BUG-C-03** | REJECTED 요청에 cancelScheduleChangeRequest 호출 | status='CANCELED'로 재업데이트 (상태 검증 없음) | `cancelScheduleChangeRequest():849-853` 상태 체크 없음 | ❌ BUG-C-03 |

---

## C-086~100: 당일명단 (AdminAttendanceDialog) + 통계

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| C-086 | 정상 | 단기 근무자 당일명단 조회 | workDate 필터 + workDays=null 체크 → 단기만 포함 | `_getConfirmedWorkersForDate():276-291` | ✅ |
| C-087 | 정상 | 장기 근무자 당일명단 조회 — 정규 근무 요일 | 기간 체크 + 휴무일 제외 + 요일 체크 → 포함 | `_getConfirmedWorkersForDate():296-353` | ✅ |
| C-088 | 경계값 | 장기 근무자 비근무 요일 — 정규 명단 제외 | workDays에 해당 요일 없음 → 제외 | `_getConfirmedWorkersForDate():348-351` | ✅ |
| C-089 | **🔴 BUG-C-02** | 추가근무 승인된 비근무일 근무자 당일명단 조회 | 실제: extraWorkDates 체크 없어 누락 / 기대: 포함 | `_getConfirmedWorkersForDate():348` extraWorkDates 미체크 | ❌ BUG-C-02 |
| C-090 | 경계값 | 장기 근무자 퇴사일 이후 당일명단 제외 | `endDate = actualResignDate ?? workEndDate`, 기간 초과 → continue | `_getConfirmedWorkersForDate():308-329` | ✅ |
| C-091 | 경계값 | 장기 근무자 desiredStartDate 미설정, confirmedAt 보정 | `effectiveStartDate = confirmedAt` (workDate보다 늦은 경우) | `_getConfirmedWorkersForDate():311-320` | ✅ |
| C-092 | 경계값 | CONTRACT_PENDING 근무자 당일명단 포함 | `whereIn: [confirmed, contractPending]` → 포함 | `_getConfirmedWorkersForDate():280` | ✅ |
| C-093 | 정상 | 당일명단 통계 — 출근/미출근/노쇼/지각/조퇴 카운트 | `_calculateStats()` 상태별 정확한 집계 | `_calculateStats():639-701` | ✅ |
| C-094 | 경계값 | 당일명단 통계 — 미퇴근(missedCheckout) 카운트 | 과거 날짜 or 퇴근 예정시간 초과 + checkOut null → missedCheckout++ | `_getAttendanceStatus():522-548` + `_calculateStats():672` | ✅ |
| C-095 | 경계값 | 당일명단 통계 — 조출(earlyArrival) 카운트 | checkIn 30분 이상 이른 경우 별도 카운트 | `_calculateStats():682-688` | ✅ |
| C-096 | 경계값 | `_isAllProcessed` 체크 — 마감 버튼 활성화 | noshow + wageCalculated + wageConfirmed == total → true | `_isAllProcessed:133` | ✅ |
| C-097 | 경계값 | `_canClose` 체크 — calculated 1명이라도 있으면 마감 가능 | wageCalculated ≥ 1 → true | `_canClose:136-145` | ✅ |
| C-098 | 경계값 | `_isAllClosed` 체크 — 전원 confirmed 또는 noshow | noshow 또는 wageConfirmed이 아닌 경우 false | `_isAllClosed:156-169` | ✅ |
| C-099 | 정상 | 사업장 드롭다운 변경 → 해당 사업장 데이터 재로드 | `_selectedBusinessId` 변경 → `_loadData()` 재호출 | `_buildHeader():849-854` | ✅ |
| C-100 | 경계값 | 주휴수당 자격 판정 — 15시간 이상 + 결근 없음 | `meetsHours && meetsDays → isEligible=true` (현재 미사용) | `computeWeeklyHolidayEligibility():903-913` | ✅ (미사용) |

---

## 발견된 버그 상세

### BUG-C-01 (MEDIUM): 관리자 수동 출근 생성 시 랜덤 docId

**파일**: [attendance_status_dialog.dart:4314](lib/screens/business_admin/dialogs/attendance_status_dialog.dart#L4314)

**현상**:
```dart
// 현재
await FirebaseFirestore.instance.collection('attendance').add({
  'applicationId': app.id,
  ...
});
```
`add()`는 랜덤 docId 생성. 시스템은 `${applicationId}_yyyyMMdd` 결정적 docId를 사용. 관리자 수동 생성 후 워커 자기 checkIn 시 두 개의 기록이 공존.

**수정**:
```dart
final dateStr = '${widget.date.year}'
    '${widget.date.month.toString().padLeft(2, '0')}'
    '${widget.date.day.toString().padLeft(2, '0')}';
final docId = '${app.id}_$dateStr';
await FirebaseFirestore.instance.collection('attendance').doc(docId).set({
  ...
}, SetOptions(merge: false));
```

---

### BUG-C-02 (MEDIUM): 추가근무 승인 근무자 당일명단 누락

**파일**: [attendance_status_dialog.dart:348](lib/screens/business_admin/dialogs/attendance_status_dialog.dart#L348)

**현상**:
```dart
// 현재 — extraWorkDates 미체크
if (app.workDays == null || app.workDays!.isEmpty || app.workDays!.contains(dayWeekday)) {
  result.add(app);
}
```
비근무 요일에 추가근무 승인된 근무자는 `workDays`에 해당 요일이 없으므로 당일명단에서 누락됨. `getTodayConfirmedWorkers()`의 `isWorkingOnDate()`는 extraWorkDates를 포함하므로 두 함수 간 불일치.

**수정**:
```dart
final isExtraWorkDay = app.extraWorkDates?.any((d) =>
    d.year == dateStart.year &&
    d.month == dateStart.month &&
    d.day == dateStart.day) ?? false;

if (isExtraWorkDay ||
    app.workDays == null ||
    app.workDays!.isEmpty ||
    app.workDays!.contains(dayWeekday)) {
  result.add(app);
}
```

---

### BUG-C-03 (LOW): cancelScheduleChangeRequest 상태 검증 없음

**파일**: [attendance_firestore.dart:780](lib/services/firestore/attendance_firestore.dart#L780)

**현상**: REJECTED, CANCELED 상태의 요청에도 `cancelScheduleChangeRequest` 호출 가능. REJECTED 요청을 취소하면 status가 CANCELED로 변경되어 상태 이력이 왜곡됨.

**수정**:
```dart
final request = ScheduleChangeRequestModel.fromMap(requestDoc.data()!, requestId);

// 취소 가능 상태: PENDING (미처리) 또는 APPROVED (적용 취소)
if (!request.isPending && !request.isApproved) {
  debugPrint('⚠️ 취소 불가 상태: ${request.status}');
  return false;
}
```

---

## 추가 검증 필요 (⚠️) 요약

| # | 시나리오 | 내용 |
|---|----------|------|
| C-043 | getTodayAttendance 어제 fallback | 장기 근무자 어제 완료 기록 오인식 → 화면 레벨에서 workDate 검증 권고 |
| C-049 | BUG-C-01 파생 | 관리자 생성 + 워커 자기 checkIn 중복 → adminDialog는 마지막 기록만 표시 |
| C-056 | 초기화 후 status='present' | checkIn null인데 status='present' → DB 불일치 (UI 무해) |
| C-064 | 노쇼 처리 2단계 분리 | attendance + application 취소 원자성 없음 → 불일치 가능 |
| C-072 | 이체완료 후 노쇼 처리 | transferred 상태에서도 노쇼 처리 가능 → 명시적 차단 권고 |
