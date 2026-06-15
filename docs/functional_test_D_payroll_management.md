# Category D: 급여/정산 관리 기능 테스트 시나리오 100개

> 감사 기준일: 2026-06-12  
> 대상 파일: `wage_confirm_dialog.dart`, `payroll_payment_service.dart`, `wage_calculator.dart`, `payment_due_date_calculator.dart`  
> 발견 버그: **BUG-D-01**, **BUG-D-02** (아래 표 내 🔴 표시)

---

## 버그 요약

| ID | 심각도 | 위치 | 설명 | 상태 |
|----|--------|------|------|------|
| BUG-D-01 | MEDIUM | `wage_confirm_dialog.dart:842` | `_processIndividualConfirm()` 트랜잭션 없이 직접 update → 동시 확정 시 급여 덮어쓰기 가능 | **수정 완료** |
| BUG-D-02 | LOW | `payroll_payment_service.dart:40` | `markTransferred()` wageStatus 검증 없음 → 비확정 기록도 transferred 설정 가능 | **수정 완료** |

---

## D-001~020: 급여 계산 (WageCalculator)

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| D-001 | 정상 | 시급제 8시간 정시 근무 계산 | baseAmount = 8h × 시급, overtimeAmount=0, nightAmount=0 | `_calculateHourlyWage()` | ✅ |
| D-002 | 정상 | 시급제 9시간 근무 (1시간 연장) | baseAmount = 8h × 시급, overtimeAmount = 1h × 시급 × 1.5 | `_calculateHourlyWage:273-278` | ✅ |
| D-003 | 정상 | 시급제 야간(22:00~06:00) 8시간 | nightMinutes=480, nightAmount = 480 × 시급 × 0.5 / 60 | `_calculateNightMinutes` + `nightRate=0.5` | ✅ |
| D-004 | 정상 | 일급제 정시 근무 | baseAmount = 일급 전액 | `_calculateDailyWage:319-321` | ✅ |
| D-005 | 정상 | 일급제 근무 미달 (4h/8h 계약 중 4h만 근무) | `baseAmount = 일급 × (4/8)` 비율 계산 | `_calculateDailyWage:323-325` | ✅ |
| D-006 | 정상 | 일급제 연장 1시간 (계약 8h 초과) — 총 9시간 | `over8Hours=60`, `amount15x = 60 × 통상시급 × 1.5 / 60` | `_calculateDailyWage:335-341` | ✅ |
| D-007 | 정상 | 일급제 연장 1시간 — 총 7.5시간 이내 (계약 6h 초과) | 연장분 전체 1배 (8시간 이하이므로 1.5배 미적용) | `_calculateDailyWage:331-333` | ✅ |
| D-008 | 경계값 | 시급제 최저시급 미만 입력 | 계산은 진행 (UI에서 경고만), 법적 강제 차단 없음 | `_calculateHourlyWage:270` 주석 | ✅ |
| D-009 | 경계값 | 시급 0원 입력 | baseAmount=0, overtimeAmount=0 → totalAmount=0 | `_calculateHourlyWage:273` | ✅ |
| D-010 | 경계값 | breakMinutes가 actualMinutes 초과 | `workMinutes = (actualMinutes - breakMinutes).clamp(0, 9999) → 0` → baseAmount=0 | `calculate():162` | ✅ |
| D-011 | 경계값 | 야간 근무 자정 넘김 (22:00~02:00) 야간시간 계산 | s=1320, e=120 → e+=1440=1560. overlap(1320,1440)=120, overlap(1440,1800)=120 → 240분 | `_calculateNightMinutes():412-424` | ✅ |
| D-012 | 경계값 | 야간 근무 start=end=22:00 (0분) | s=e=1320, e<s 불성립 → e-s=0 → 야간시간=0 | `_calculateNightMinutes():373` | ✅ |
| D-013 | 경계값 | scheduledBreakMinutes와 breakMinutes 다를 때 일급제 연장 계산 | scheduledBreakMinutes=0 (기본), breakMinutes=30 (추가공제) → `schedBreak=0` 기준으로 연장시간 계산 | `calculate():146-146` `schedBreak = scheduledBreakMinutes ?? breakMinutes` | ✅ |
| D-014 | 경계값 | nightIncluded=true 일급제 + 연장 야간 | 계약 내 야간분 제외, 초과분만 nightAmount 계산 | `calculate():180-182` | ✅ |
| D-015 | 경계값 | nightIncluded=true 일급제 + 연장 없음 | `overtimeMinutes=0 → nightMinutes=0` → nightAmount=0 | `calculate():178-181` | ✅ |
| D-016 | 경계값 | 2024년 근무 → 최저시급 9,860원 적용 | `getMinimumWage(2024) = 9860` (로컬 백업) | `_minimumWageByYear:24` | ✅ |
| D-017 | 경계값 | 2030년 근무 (정의 없는 연도) → 최신 연도 시급 적용 | `latestYear = 2026 → 10320` 폴백 | `getMinimumWage():68-71` | ✅ |
| D-018 | 경계값 | baseHourlyWage 설정 시 통상시급 계산 대신 사용 | `supplementWage = baseHourlyWage` (우선) | `calculate():149-157` | ✅ |
| D-019 | 경계값 | 파싱 불가 시간 문자열 입력 ("25:70") | `_parseTime()` null 반환 → `_calculateMinutesBetween()` 0 반환 | `_parseTime():381-387` | ✅ |
| D-020 | 경계값 | additionalAmount 음수 입력 | `totalAmount = base + overtime + night + negative → 감소` (검증 없음) | `calculate():232` | ⚠️ 음수 추가수당 차단 없음 |

---

## D-021~040: 급여 확정 (pending → calculated)

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| D-021 | 정상 | 미확정 근무자 선택 후 일괄 급여 확정 | 트랜잭션으로 wageStatus=calculated, finalWage, wageDetail, yearMonth 저장 | `_confirmWages():489-504` | ✅ |
| D-022 | 정상 | 개별 급여 상세 다이얼로그에서 단건 확정 | wageStatus=calculated 직접 update | `_processIndividualConfirm():842-851` | ✅ |
| D-023 | 경계값 | 이미 calculated 기록 재확정 시도 (일괄) | 트랜잭션에서 "이미 처리된 급여" 예외, failCount++ | `_confirmWages():492-495` | ✅ |
| D-024 | 경계값 | 이미 confirmed 기록 재확정 시도 (일괄) | 트랜잭션에서 "이미 처리된 급여" 예외 | `_confirmWages():493-495` | ✅ |
| D-025 | 경계값 | 이미 transferred 기록 재확정 시도 (일괄) | 트랜잭션에서 "이미 처리된 급여" 예외 | `_confirmWages():494` | ✅ |
| D-026 | **🔴 BUG-D-01** | 두 관리자 동시에 동일 근무자 개별 확정 | 실제: 마지막 write가 이기며 급여 덮어쓰기 / 기대: 트랜잭션 중복 방지 | `_processIndividualConfirm():842` 트랜잭션 없음 | ❌ BUG-D-01 |
| D-027 | 경계값 | 퇴근 미완료 근무자 급여 확정 시도 | WageConfirmDialog 초기화 시 checkOut=null → `_pendingWorkers`에서 제외 → 목록 미표시 | `_initData():117` | ✅ |
| D-028 | 경계값 | 선택 인원 없이 일괄 확정 버튼 클릭 | "급여 확정할 인원을 선택해주세요" 경고 | `_confirmWages():365-367` | ✅ |
| D-029 | 경계값 | 5명 중 3명 성공, 2명 실패 | successCount=3, failCount=2, 부분 확정 (의도된 설계) | `_confirmWages():419-528` | ✅ |
| D-030 | 경계값 | TO 수정 후 미확정 급여 재계산 | effectiveStart/End 변경 감지 → 캐시 무효화 → 재계산 | `_calculateWageForWorker():237-242` | ✅ |
| D-031 | 경계값 | 이미 calculated 급여는 TO 수정 무관하게 보존 | `attendance.wageDetail.isCalculated=true → 캐시 사용` | `_calculateWageForWorker():233-235` | ✅ |
| D-032 | 경계값 | workDetailTimeMap 캐시 없을 때 Firestore 폴백 | 슬롯 문서 조회 → 없으면 TO 문서 조회 | `_calculateWageForWorker():272-320` | ✅ |
| D-033 | 경계값 | payScheduleType 캐시 없을 때 Firestore 폴백 | 슬롯 → TO 순서로 payScheduleType 조회 | `_confirmWages():447-475` | ✅ |
| D-034 | 경계값 | payScheduleType 미설정 → paymentDueDate=null | `PaymentDueDateCalculator.calculate()` null 반환 → paymentDueDate 미저장 | `PaymentDueDateCalculator.calculate():41` | ✅ |
| D-035 | 정상 | 석식/야식공제 30분 선택 후 급여 확정 | `effectiveBreak = breakMinutes + 30`, workMinutes 재계산 | `_calculateWageForWorker():330` | ✅ |
| D-036 | 경계값 | 연장 없는 근무자에게 석식공제 선택 | extraBreakMinutes 설정은 되나 `_workerHasOvertime=false` → UI 표시 안됨 | `_buildWorkerCard():1321` `hasOvertime ? extraApplied : 0` | ✅ |
| D-037 | 경계값 | 그룹 공제 변경 후 선택되지 않은 근무자 재계산 제외 | 선택된 근무자만 재계산 (`selectedInGroup`) | `_setGroupBreak():171-195` | ✅ |
| D-038 | 경계값 | 동일 wageDetail 중복 저장 (캐시 재사용) | `forceRecalculate=false` + `wageDetail.isCalculated → 캐시 반환` | `_calculateWageForWorker():233-235` | ✅ |
| D-039 | 경계값 | daily_auto_8 근무자 8일차 소급 확인 경고 | `_showDay8RetroactiveWarning` 다이얼로그 표시 후 확인 필요 | `_confirmWages():397-414` | ✅ |
| D-040 | 경계값 | daily_auto_8 근무자 9일차 이상 → 4대보험 풀 공제 | `prevDays + 1 > 8 → typeFourInsuranceFixed 적용` | `_checkAndApplyRetroactive():588-607` | ✅ |

---

## D-041~060: 급여 취소/수정 (calculated → pending / update)

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| D-041 | 정상 | calculated 급여 취소 → pending 복귀 | wageStatus=pending, finalWage/wageDetail 삭제 | `_processWageCancel():933-938` | ✅ |
| D-042 | 경계값 | 급여 취소 후 yearMonth 필드 잔존 | yearMonth 미삭제, 但 pending 상태이므로 `_getPrevGrossTotal` 쿼리에 미포함 (wageStatus 필터로 배제) | `_processWageCancel():933-938` yearMonth 없음 | ⚠️ 필드 잔존 (기능적 무해) |
| D-043 | 정상 | calculated 급여 수정 (추가수당 변경) | finalWage/wageDetail 업데이트, wageStatus 유지(calculated) | `_processWageUpdate():888-921` | ✅ |
| D-044 | 경계값 | 급여 수정 후 wageStatus 변경 없음 | calculated → calculated 유지 (의도된 동작) | `_processWageUpdate()` wageStatus 없음 | ✅ |
| D-045 | 경계값 | 일괄 급여 취소 — 루프 중 _calculatedWorkers 변경 | 루프 전 appSnapshots로 스냅샷 확보 → 변경 충돌 없음 | `_cancelSelectedWages():980-986` | ✅ |
| D-046 | 경계값 | 최종확정(confirmed) 급여 취소 시도 | WageConfirmDialog가 confirmed 상태 목록 미표시 (initData에서 제외) → 취소 경로 없음 | `_initData():125` 주석 | ✅ |
| D-047 | 경계값 | 이체완료(transferred) 급여 취소 시도 | WageConfirmDialog에서 표시 안 됨 (pending/calculated만 표시) | `_initData():120-126` | ✅ |
| D-048 | 정상 | 급여 취소 후 재계산 (워커 추가공제 유지) | `_calculateWageForWorker(app, extraBreakMinutes: extra)` 재호출 | `_processWageCancel():944-945` | ✅ |
| D-049 | 경계값 | calculated 급여 수정 시 트랜잭션 없음 | 동시 수정 시 last-write-wins. 실용적으로 한 관리자만 수정 | `_processWageUpdate():899-906` | ⚠️ |
| D-050 | 경계값 | 급여 수정 후 선택된 합계 즉시 갱신 | `_calculatedWages[app.id] = updatedWage` → `_getSelectedTotal` 재계산 | `_processWageUpdate():913` | ✅ |
| D-051 | 경계값 | 급여 확정 취소 시 wageDetail 없는 기록 | `_calculateWageForWorker` → attendance.wageDetail=null → Firestore 폴백 | `_calculateWageForWorker():233` | ✅ |
| D-052 | 경계값 | `_getPrevGrossTotal` — 이전 확정 급여 조회 시 excludeId 필터 | 현재 처리 중인 attendance 제외 | `_getPrevGrossTotal():627` | ✅ |
| D-053 | 경계값 | 8일차 소급 경고 취소 시 확정 중단 | `day8Confirmed=false → return` | `_confirmWages():413-414` | ✅ |
| D-054 | 경계값 | 8일차 소급 중 retroactiveDeduction=0 → 경고 없이 진행 | `if (preview.retroactiveDeduction > 0)` → 0이면 day8Previews에 미추가 | `_confirmWages():392-394` | ✅ |
| D-055 | 오류복구 | Firestore 업데이트 실패 시 에러 토스트 | failCount++, "처리 실패" 토스트 | `_confirmWages():526-528` | ✅ |
| D-056 | 정상 | 소급 공제 알림 → 근무자에게 Notification 발송 | `createNotification(RetroactiveDeductionAlert)` | `_confirmWages():507-519` | ✅ |
| D-057 | 경계값 | toId=null인 지원서 급여 계산 | WorkDetail 조회 불가 → wageType='hourly', breakMinutes=0 기본값 사용 | `_calculateWageForWorker():324-326` | ⚠️ 기본값 폴백 |
| D-058 | 경계값 | slotId 없는 지원서 → TO 문서에서 workDetails 조회 | 슬롯 조회 skip → TO 직접 조회 | `_calculateWageForWorker():292-303` | ✅ |
| D-059 | 경계값 | 같은 그룹(파트+시간대)의 근무자 bulk 선택 | `allGroupSelected → selectedIds.addAll` | `_buildGroupHeader():1745-1752` | ✅ |
| D-060 | 경계값 | `isProcessing=true` 상태에서 버튼 재클릭 | `if (_isProcessing) return;` 가드 | `_confirmWages():362-363` | ✅ |

---

## D-061~075: 이체 처리 (confirmed → transferred)

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| D-061 | 정상 | 단건 이체 완료 처리 | wageStatus=transferred, transferDate, transferredBy 저장 | `markTransferred():35-48` | ✅ |
| D-062 | 정상 | 일괄 이체 완료 처리 (450건 단위 분할) | 450건씩 WriteBatch로 커밋 | `markTransferredBatch():57-71` | ✅ |
| D-063 | 정상 | 이체 완료 취소 (transferred → confirmed) | wageStatus=confirmed, transferDate/Note/By 삭제 | `cancelTransfer():74-87` | ✅ |
| D-064 | **🔴 BUG-D-02** | wageStatus='pending' 기록에 markTransferred 호출 | wageStatus가 transferred로 강제 변경됨 — 급여 미계산 기록이 이체완료 상태가 됨 | `markTransferred():40` 상태 검증 없음 | ❌ BUG-D-02 |
| D-065 | 경계값 | transferNote 빈 문자열 → 미저장 | `if (transferNote != null && transferNote.isNotEmpty)` → 빈 문자열 skip | `markTransferred():43` | ✅ |
| D-066 | 경계값 | 500건 초과 일괄 이체 | 450건 + 나머지 두 번의 batch.commit() | `markTransferredBatch():57` `i += 450` | ✅ |
| D-067 | 경계값 | 일괄 이체 중 1번째 batch 성공, 2번째 실패 | 1번째 450건만 transferred, 나머지는 confirmed 유지 | `markTransferredBatch():69` await 실패 시 throw | ⚠️ 부분 이체 가능 |
| D-068 | 경계값 | 이체 완료 후 wageStatus 변경 시도 (당일명단에서) | "이체 완료된 급여는 수정할 수 없습니다" 에러 | `_updateAttendanceTime:4172-4175` | ✅ |
| D-069 | 정상 | CSV 이체 목록 생성 | `generateTransferCsv()` — 이름, 은행, 계좌, 금액, 메모 형식 | `generateTransferCsv():187-196` | ✅ |
| D-070 | 경계값 | buildTransferRows — 계좌정보 없는 근무자 | 해당 근무자 이체 목록 제외, 경고 로그 출력 | `buildTransferRows():395-399` | ✅ |
| D-071 | 경계값 | buildTransferRows — netWage ≤ 0 행 제외 | `if (totalNet <= 0) continue` | `buildTransferRows():407` | ✅ |
| D-072 | 경계값 | buildTransferRows — 같은 근무자 복수 기간 → 합산 | `grouped[userId]` 리스트로 합산 | `buildTransferRows():384-404` | ✅ |
| D-073 | 경계값 | 이체 취소 후 다시 이체 처리 | cancelTransfer → confirmed 복귀 → markTransferred → transferred | `cancelTransfer():74-87` + `markTransferred()` | ✅ |
| D-074 | 경계값 | 오늘 지급 예정 기록 조회 — paymentDueDate=null인 기록 | `paymentDueDate <= today` 쿼리 → null인 기록 제외 (null comparator skip) | `getTodayPayments():146-148` | ✅ |
| D-075 | 경계값 | `getTodayPayments()` referenceDate 매개변수 (테스트용) | referenceDate 전달 시 해당 날짜 기준 조회 | `getTodayPayments():140-141` | ✅ |

---

## D-076~085: 지급 예정일 계산 (PaymentDueDateCalculator)

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| D-076 | 정상 | same_day 지급 — workDate = 지급일 | `return base` (workDate 당일) | `calculate():26` | ✅ |
| D-077 | 정상 | next_day 지급 — workDate + 1일 | `return base.add(Duration(days: 1))` | `calculate():29` | ✅ |
| D-078 | 정상 | weekly 지급 — 금요일(5) 설정, workDate=월요일 | diff=(5-1)%7=4 → workDate+4일(금요일) | `_nextWeekday():71` | ✅ |
| D-079 | 경계값 | weekly 지급 — workDate가 이미 금요일 | diff=(5-5)%7=0 → workDate 당일 반환 | `_nextWeekday():71` | ✅ |
| D-080 | 경계값 | weekly 지급 — workDate=토요일(6), 지급일=금요일(5) | diff=(5-6)%7 → Dart: -1%7=6 → workDate+6일(다음 금요일) | `_nextWeekday():71` Dart 모듈로 | ✅ |
| D-081 | 정상 | monthly 지급 — workDate=1월 5일, 지급일=25일 | thisMonthDue=Jan 25, !Jan25.isBefore(Jan5)=true → Jan 25 | `_nextMonthlyDay():77-84` | ✅ |
| D-082 | 경계값 | monthly 지급 — workDate=1월 26일, 지급일=25일 | Jan 25는 이미 지남 → nextMonth=Feb → Feb 25 | `_nextMonthlyDay():87-93` | ✅ |
| D-083 | 경계값 | monthly 지급 — 2월 30일 (존재하지 않는 날) | clampedDay=min(30, 28)=28 → Feb 28 | `_nextMonthlyDay():80` `.clamp` | ✅ |
| D-084 | 경계값 | payScheduleType=null → paymentDueDate=null | `default: return null` | `calculate():41` | ✅ |
| D-085 | 경계값 | isDueOnOrBefore — 오늘이 지급일보다 미래 | `!dueDate.isAfter(refDate)` → true | `isDueOnOrBefore():62` | ✅ |

---

## D-086~100: 정산 요청 (지급방식 변경 / 중간정산)

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| D-086 | 정상 | 지급방식 변경 요청 생성 | `payment_change_requests` 컬렉션에 추가 | `createPaymentChangeRequest():205-209` | ✅ |
| D-087 | 정상 | 지급방식 변경 요청 승인 | status=approved, processedBy, processedAt 저장 | `approveChangeRequest():234-244` | ✅ |
| D-088 | 정상 | 지급방식 변경 요청 거절 | status=rejected, rejectReason 저장 | `rejectChangeRequest():247-258` | ✅ |
| D-089 | 경계값 | 미처리 변경 요청 50건 초과 조회 | limit(50)으로 클리핑 | `getPendingChangeRequests():222` | ⚠️ 50건 이상 시 누락 |
| D-090 | 정상 | 중간정산 요청 생성 | `interim_settlement_requests` 컬렉션에 추가 | `createInterimSettlementRequest():267-272` | ✅ |
| D-091 | 정상 | 중간정산 요청 승인 → 해당 출근기록 일괄 이체 | `markTransferredBatch(req.attendanceIds)` → `status=processed` | `approveInterimSettlement():321-337` | ✅ |
| D-092 | 경계값 | 이미 처리된 중간정산 재승인 시도 | `statusProcessed` 체크 → Exception throw | `approveInterimSettlement():310-313` | ✅ |
| D-093 | 경계값 | 중간정산 attendanceIds 빈 배열 | `throw Exception('출근기록이 없습니다')` | `approveInterimSettlement():315-317` | ✅ |
| D-094 | 오류복구 | 중간정산 1단계(이체) 성공, 2단계(상태변경) 실패 | attendances=transferred, 요청=pending/approved 유지 → 재호출 시 멱등 처리 | `approveInterimSettlement():319-337` 2단계 분리 | ⚠️ 원자성 부재 |
| D-095 | 정상 | 중간정산 거절 | status=rejected, rejectReason 저장 | `rejectInterimSettlement():341-356` | ✅ |
| D-096 | 정상 | 급여 현황 조회 (confirmed + transferred 전체) | `wageStatus whereIn [confirmed, transferred]` | `getPayrollRecords():115-116` | ✅ |
| D-097 | 정상 | 급여 현황 조회 (wageStatus 필터 지정) | `wageStatus = 지정값` | `getPayrollRecords():111-113` | ✅ |
| D-098 | 경계값 | 월 단위 최대 2,000건 제한 조회 | `.limit(2000)` | `getPayrollRecords():120` | ⚠️ 2000건 초과 시 누락 |
| D-099 | 경계값 | `getTodayPaymentCount()` — count() 쿼리 | Firestore count 집계 반환 | `getTodayPaymentCount():172` `.count().get()` | ✅ |
| D-100 | 정상 | 급여 현황 월 경계값 — 12월 조회 | `monthEnd = DateTime(year, 13, 1)` → Dart가 자동으로 Jan 1 다음 해로 계산 | `getPayrollRecords():102` | ✅ |

---

## 발견된 버그 상세

### BUG-D-01 (MEDIUM): 개별 확정 — 트랜잭션 없이 직접 update

**파일**: [wage_confirm_dialog.dart:842](lib/screens/business_admin/dialogs/wage_confirm_dialog.dart#L842)

**현상**: `_processIndividualConfirm()`는 트랜잭션 없이 직접 `update()` 사용. 두 관리자가 동시에 같은 근무자를 개별 확정하면 마지막 write가 이기며 급여 덮어쓰기 발생. `_confirmWages()` (일괄)는 트랜잭션으로 방지하는 것과 불일치.

**수정**:
```dart
// _processIndividualConfirm() 내부 — 직접 update 대신 트랜잭션 사용
final attRef = FirebaseFirestore.instance.collection('attendance').doc(attendance.id);
await FirebaseFirestore.instance.runTransaction((tx) async {
  final snap = await tx.get(attRef);
  final currentStatus = snap.data()?['wageStatus'] as String?;
  if (currentStatus == AttendanceModel.wageCalculated ||
      currentStatus == AttendanceModel.wageConfirmed ||
      currentStatus == AttendanceModel.wageTransferred) {
    throw Exception('이미 처리된 급여입니다 ($currentStatus)');
  }
  tx.update(attRef, {
    'wageStatus': 'calculated',
    'finalWage': calculatedWage.netWage,
    'wageDetail': calculatedWage.toMap(),
    'yearMonth': yearMonth,
    'updatedAt': FieldValue.serverTimestamp(),
  });
});
```

---

### BUG-D-02 (LOW): markTransferred — wageStatus 검증 없음

**파일**: [payroll_payment_service.dart:40](lib/services/payroll_payment_service.dart#L40)

**현상**: `markTransferred()`가 wageStatus 검증 없이 호출되면 `pending` 또는 `calculated` 상태 기록도 `transferred`로 변경. UI는 `confirmed` 기록만 노출하지만 서비스 레이어 자체에 가드 없음.

**수정**:
```dart
Future<void> markTransferred({...}) async {
  await _db.runTransaction((tx) async {
    final snap = await tx.get(_db.collection('attendance').doc(attendanceId));
    if (snap.data()?['wageStatus'] != AttendanceModel.wageConfirmed) {
      throw Exception('확정된 급여만 이체 처리할 수 있습니다.');
    }
    tx.update(_db.collection('attendance').doc(attendanceId), {
      'wageStatus':    AttendanceModel.wageTransferred,
      'transferDate':  FieldValue.serverTimestamp(),
      if (transferNote != null && transferNote.isNotEmpty)
        'transferNote': transferNote,
      'transferredBy': processedBy,
      'updatedAt':     FieldValue.serverTimestamp(),
    });
  });
}
```

---

## 추가 검증 필요 (⚠️) 요약

| # | 시나리오 | 내용 |
|---|----------|------|
| D-020 | 음수 추가수당 | additionalAmount 음수 허용 → totalAmount 감소 가능 — UI 입력 검증 권고 | **주석 추가** (`wage_calculator.dart:232`) |
| D-042 | 급여 취소 후 yearMonth 잔존 | pending 복귀 시 yearMonth 미삭제 — DB 정합성 | **수정 완료** (`wage_confirm_dialog.dart` `_processWageCancel`) |
| D-049 | 개별 급여 수정 동시성 | last-write-wins, 실용적으로 충돌 빈도 낮음 — 의도적 허용 | **주석 추가** (`wage_confirm_dialog.dart` `_processWageUpdate`) |
| D-057 | toId=null 기본값 폴백 | 계약 TO 없는 지원서 → wageType='hourly', break=0 — 의도된 폴백 | **주석 추가** (`wage_confirm_dialog.dart` `_calculateWageForWorker`) |
| D-067 | 일괄 이체 부분 실패 | 450건 단위 batch 중 2번째 실패 시 첫 450건만 이체 완료 — 재시도 멱등 | **주석 추가** (`payroll_payment_service.dart` `markTransferredBatch`) |
| D-089 | 변경 요청 limit(50) | 50건 초과 시 누락 — 적체 시 처리 속도 증가 필요 | **주석 추가** (`payroll_payment_service.dart` `getPendingChangeRequests`) |
| D-094 | 중간정산 원자성 부재 | 이체 성공 + 상태 변경 실패 → 재승인 시 멱등 처리로 복구 가능 | **주석 추가** (`payroll_payment_service.dart` `approveInterimSettlement`) |
| D-098 | 급여 현황 limit(2000) | 월 2000건 초과 사업장에서 데이터 누락 — 대형 사업장 페이지네이션 필요 | **주석 추가** (`payroll_payment_service.dart` `getPayrollRecords`) |
