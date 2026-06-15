# Category B: 지원자 관리 기능 테스트 시나리오 100개

> 감사 기준일: 2026-06-12  
> 대상 파일: `application_firestore.dart`, `application_model.dart`, `work_applicants_dialog.dart`  
> 발견 버그: **BUG-B-01**, **BUG-B-02** (아래 표 내 🔴 표시)

---

## 버그 요약

| ID | 심각도 | 위치 | 설명 | 상태 |
|----|--------|------|------|------|
| BUG-B-01 | MEDIUM | `application_firestore.dart:830` | `cancelApplication()` — REJECTED 지원서 취소 시 "이미 취소됨" 메시지 부정확 | **수정 완료** |
| BUG-B-02 | MEDIUM | `application_firestore.dart:1467` | `_confirmWithConflictCheck` — 동시 확정 CONTRACT_PENDING 충돌 미자동 해결, 수동 처리 위임 | 설계 결정 (경고 로그로 처리) |

---

## B-001~020: 지원하기 — 정상 흐름 및 사전 체크

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| B-001 | 정상 | Flex TO 슬롯에 업무유형 선택 후 지원 | 서류 체크 → 상태 체크 → TOCTOU → PENDING 지원서 생성, totalPending+1 | `applyToTO():210-686` | ✅ |
| B-002 | 정상 | Contract TO 지원 (slotId=null) | TO 레벨 마감/정원 체크 → 지원서 생성 | `applyToTO():324-336` | ✅ |
| B-003 | 경계값 | 신분증 미등록 사용자 지원 | "신분증 등록이 필요합니다" 에러, 차단 | `applyToTO():218-219` | ✅ |
| B-004 | 경계값 | 통장 미등록 사용자 지원 | "통장 정보 등록이 필요합니다" 에러, 차단 | `applyToTO():222-225` | ✅ |
| B-005 | 경계값 | 통장사본 미등록 사용자 지원 | "통장사본 등록이 필요합니다" 에러, 차단 | `applyToTO():226-229` | ✅ |
| B-006 | 경계값 | 블랙리스트 사용자 지원 | "이용 제한된 계정입니다" 에러, 사유 표시 | `applyToTO():232-236` | ✅ |
| B-007 | 경계값 | 이메일 미인증 사용자 지원 | "이메일 인증이 필요합니다" 에러, 차단 | `applyToTO():239-242` | ✅ |
| B-008 | 경계값 | 신분증 미인증(isIdVerified=false) 사용자 지원 | "신분증 인증 후 지원할 수 있습니다" 에러 | `applyToTO():246-249` | ✅ |
| B-009 | 경계값 | 제재 중인 사용자(restrictedUntil 미래) 지원 | "X일 동안 지원 제한" 에러, 잔여 일수 표시 | `applyToTO():252-258` | ✅ |
| B-010 | 경계값 | 제재 만료 사용자 지원 | 정상 지원 허용 | `applyToTO():253` `.isAfter(DateTime.now())` | ✅ |
| B-011 | 경계값 | CLOSED TO에 지원 | "마감된 공고입니다" 에러, 차단 | `applyToTO():271-274` | ✅ |
| B-012 | 경계값 | draft(비공개) TO에 지원 | "비공개 공고에는 지원할 수 없습니다" 에러 | `applyToTO():267-270` | ✅ |
| B-013 | 경계값 | 게시 기간 만료 TO에 지원 | "지원 마감된 공고입니다" 에러 | `applyToTO():277-280` `isPostingExpired` | ✅ |
| B-014 | 경계값 | 마감된 슬롯에 지원 (isManualClosed=true) | "해당 날짜는 마감되었습니다" 에러 | `applyToTO():294-297` | ✅ |
| B-015 | 경계값 | 업무 마감시간 지난 슬롯 지원 | "해당 업무의 지원 마감 시간이 지났습니다" 에러 | `applyToTO():308-312` | ✅ |
| B-016 | 경계값 | 정원 다 찬 업무유형에 지원 (workTypeCounts) | "해당 업무의 모집 인원이 마감되었습니다" 에러 | `applyToTO():320-323` | ✅ |
| B-017 | 경계값 | 이미 PENDING 지원서 있는 동일 슬롯+업무 재지원 | "이미 지원한 업무입니다" 경고, 차단 | `applyToTO():383-386` | ✅ |
| B-018 | 경계값 | 같은 날/시간대 확정 근무 있는 단기 TO 지원 | 시간 충돌 에러, 사업장명+시간 표시 | `applyToTO():440-449` | ✅ |
| B-019 | 경계값 | 장기 TO 지원 시 기존 장기 확정 근무와 요일 충돌 | 요일 충돌 에러 | `applyToTO():406-438` | ✅ |
| B-020 | 오류복구 | TOCTOU 트랜잭션 직전 슬롯 마감 | "방금 마감된 날짜입니다" 에러, 지원서 미생성 | `applyToTO():608-628` 트랜잭션 | ✅ |

---

## B-021~040: 지원서 상태 관리 — 확정 / 거절

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| B-021 | 정상 | PENDING 지원서 확정 | 트랜잭션으로 CONTRACT_PENDING 선점 → 충돌 자동 취소 → 배치 커밋 → totalPending-1, totalConfirmed+1 | `_confirmWithConflictCheck` | ✅ |
| B-022 | 정상 | PENDING 지원서 거절 + 메시지 | `status=REJECTED`, `rejectMessage` 저장, totalPending-1, 알림 전송 | `updateApplicationStatus():737-757` | ✅ |
| B-023 | 경계값 | 이미 CONFIRMED 지원서 재확정 시도 | `alreadyConfirmed=true` → 빈 배열 반환, 중복 확정 방지 | `_confirmWithConflictCheck:1307-1309` | ✅ |
| B-024 | 경계값 | CANCELED 지원서 확정 시도 | "취소된 지원서는 확정할 수 없습니다" 예외 | `_confirmWithConflictCheck:1311-1313` | ✅ |
| B-025 | 경계값 | AUTO_CANCELED 지원서 확정 시도 | "자동 취소된 지원서는 확정할 수 없습니다" 예외 | `_confirmWithConflictCheck:1314-1316` | ✅ |
| B-026 | 경계값 | REJECTED 지원서 확정 시도 | "거절된 지원서는 확정할 수 없습니다" 예외 | `_confirmWithConflictCheck:1317-1319` | ✅ |
| B-027 | 경계값 | CONFIRMED 지원서 거절 시도 | "확정된 지원서는 거절할 수 없습니다" 에러, 취소 경로 안내 | `updateApplicationStatus():723-727` | ✅ |
| B-028 | 경계값 | REJECTED → PENDING 관리자 직접 전환 시도 | "거절된 지원서는 재활성화할 수 없습니다" 에러 | `updateApplicationStatus():731-734` | ✅ |
| B-029 | 경계값 | CONFIRMED → PENDING 롤백 | `confirmedCount-1`, `pendingCount+1`, 알림 | `updateApplicationStatus():763-771` | ✅ |
| B-030 | 경계값 | 확정 시 슬롯 정원 초과 (관리자 의도) | "모집인원이 이미 찼습니다. 초과 확정됩니다" 경고 토스트, 확정은 진행 | `_confirmWithConflictCheck:1392-1395` | ✅ |
| B-031 | 경계값 | 마감된 슬롯 지원자 확정 시도 | "이미 마감된 슬롯입니다" → CONTRACT_PENDING 롤백 | `_confirmWithConflictCheck:1373-1381` | ✅ |
| B-032 | 경계값 | 배치 커밋 실패 시 CONTRACT_PENDING 롤백 | `appRef.update({status: PENDING, ...})` 롤백 | `_confirmWithConflictCheck:1499-1509` | ✅ |
| B-033 | 경계값 | 배치 커밋 실패 + 롤백도 실패 | 영구 limbo 상태 → 에러 로그 출력, 수동 해제 필요 | `_confirmWithConflictCheck:1506-1508` | ⚠️ 수동 처리 필요 |
| B-034 | 경계값 | 확정 후 슬롯 full 여부 재계산 | `_recalculateSlotStatus` 호출, confirmed≥required → status='full' | `_confirmWithConflictCheck:1514-1516` | ✅ |
| B-035 | 경계값 | 장기 TO 확정 시 workEndDate 자동 계산 (contractPeriodType != null) | TO의 contractPeriodType으로 종료일 계산 | `_confirmWithConflictCheck:1350-1357` | ✅ |
| B-036 | 경계값 | 장기 TO 확정 시 workDays를 TO에서 보완 | `app.workDays=null` → `toModel.workDays`로 대체 | `_confirmWithConflictCheck:1358-1362` | ✅ |
| B-037 | 경계값 | 거절 메시지 없이 거절 | `rejectMessage=null`, 상태만 REJECTED로 변경 | `updateApplicationStatus():737` `if (message != null)` | ✅ |
| B-038 | 경계값 | 관리자 A, B 동시에 같은 지원서 확정 시도 | 첫 트랜잭션만 CONTRACT_PENDING 선점, 두 번째는 `alreadyConfirmed=true` 반환 | 트랜잭션 선점 패턴 | ✅ |
| B-039 | 경계값 | 한 근무자의 두 충돌 PENDING 지원서 동시 확정 (관리자 A, B) | `concurrentConflicts` 감지 → 경고 로그, 수동 처리 필요 | `_confirmWithConflictCheck:1464-1470` | ⚠️ BUG-B-02 |
| B-040 | 정상 | Contract TO 확정 시 `workTypeConfirmedCounts` 증가 | `workTypeConfirmedCounts.workType += 1`, totalConfirmed+1 | `_incrementTOConfirmed:1666-1668` | ✅ |

---

## B-041~060: 취소 처리

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| B-041 | 정상 | 사용자 PENDING 지원서 취소 | `status=CANCELED`, pendingCount-1, 알림, 연관 데이터 정리 | `cancelApplication():807-878` | ✅ |
| B-042 | 경계값 | 사용자 CONFIRMED 지원서 직접 취소 시도 | "확정된 TO는 취소할 수 없습니다. 관리자에게 문의" 에러, 차단 | `cancelApplication():825-828` | ✅ |
| B-043 | **🔴 BUG-B-01** | 사용자가 REJECTED 지원서 취소 시도 | 실제: "이미 취소된 지원서입니다" 토스트(오탐) / 기대: "이미 거절된 지원서입니다" | `cancelApplication():830-833` | ❌ BUG-B-01 |
| B-044 | 경계값 | 사용자가 AUTO_CANCELED 지원서 취소 시도 | "이미 취소된 지원서입니다" 토스트, return true (멱등 처리) | `cancelApplication():830-833` | ✅ |
| B-045 | 경계값 | 타인의 지원서 취소 시도 | "본인의 지원서만 취소할 수 있습니다" 에러 | `cancelApplication():820-823` | ✅ |
| B-046 | 정상 | 관리자 CONFIRMED 지원서 취소 (노쇼 패널티 없음) | `status=CANCELED`, `cancelReason=ADMIN_CANCELED`, confirmedCount-1, 슬롯 재계산 | `cancelConfirmedApplication()` | ✅ |
| B-047 | 정상 | 관리자 CONFIRMED 지원서 취소 + 노쇼 패널티 | 위와 동일 + `_applyNoShowPenaltyTransactional` 호출 | `cancelConfirmedApplication():940-942` | ✅ |
| B-048 | 경계값 | 노쇼 카운트 2회 → 3회 도달 | 트랜잭션으로 `noShowCount=0`, `restrictedUntil=now+3days` | `_applyNoShowPenaltyTransactional:1708-1715` | ✅ |
| B-049 | 경계값 | PENDING 지원서에 노쇼 패널티 취소 시도 | "확정된 지원만 취소할 수 있습니다" 에러 | `cancelConfirmedApplication():899-902` | ✅ |
| B-050 | 경계값 | 확정 취소 후 슬롯 상태 full→open 재계산 | `_recalculateSlotStatus` 호출, confirmed < required → status='open' | `cancelConfirmedApplication():944-947` | ✅ |
| B-051 | 경계값 | Contract TO 확정 취소 (slotId=null) | `_recalculateSlotStatus` 미호출 (slotId null 체크) | `cancelConfirmedApplication():944-947` `if (slotId != null)` | ✅ |
| B-052 | 경계값 | 취소 시 관련 idCardAccessRequests 정리 | status='pending' 요청 → status='canceled' 업데이트 | `_cleanupApplicationRelatedData:1784-1799` | ✅ |
| B-053 | 경계값 | 취소 시 PENDING schedule_change_requests 정리 | status='PENDING' 요청 → status='CANCELED' | `_cleanupApplicationRelatedData:1800-1807` | ✅ |
| B-054 | 경계값 | 취소 시 급여 미처리 출근 기록 무효화 | wageStatus='pending' 기록 → `canceledWithApplication=true` | `_cleanupApplicationRelatedData:1808-1816` | ✅ |
| B-055 | 경계값 | 관리자 취소 시 businessId 없는 지원서 | `cleanupBusinessId=null` → USER 경로 fallback | `cancelConfirmedApplication():952-956` | ⚠️ 관리자 idCard 요청 미정리 가능 |
| B-056 | 오류복구 | 취소 성공 후 알림 전송 실패 | 취소 자체는 성공, 에러 로그만 출력 | `cancelApplication():856-870` try/catch | ✅ |
| B-057 | 오류복구 | 취소 배치 커밋 실패 | `false` 반환, 에러 토스트 | `cancelApplication():873-877` catch | ✅ |
| B-058 | 경계값 | CONTRACT_PENDING 상태 사용자 직접 취소 | "확정된 TO는 취소할 수 없습니다" 에러 (CONTRACT_PENDING은 confirmedStatuses에 포함) | `cancelApplication():825` | ✅ |
| B-059 | 경계값 | 오프라인 상태에서 취소 시도 | "지원 취소를 하려면 인터넷 연결이 필요합니다" 에러 | `cancelApplication():809` NetworkChecker | ✅ |
| B-060 | 정상 | 확정 취소 후 `cancelReason` = 'SAME_DAY_CANCEL' (노쇼) | `cancelReason='SAME_DAY_CANCEL'`, 배지 표시 | `cancelConfirmedApplication():912-913` | ✅ |

---

## B-061~075: 충돌 감지 및 자동 취소

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| B-061 | 정상 | 확정 시 같은 날 같은 시간대 PENDING 지원서 자동 취소 | `status=AUTO_CANCELED`, `cancelReason=SCHEDULE_CONFLICT`, AUTO_CANCELED 알림 | `_confirmWithConflictCheck:1473-1492` | ✅ |
| B-062 | 정상 | 확정 시 타 사업장 PENDING 지원서도 자동 취소 | `businessId` 필터 없이 전체 검색 → 충돌 시 취소 | `findConflictingApplications:1155-1162` | ✅ |
| B-063 | 경계값 | 확정 시 충돌 지원서의 TO pendingCount 감소 (statsBatch) | `totalPending-1` 감소, 분리 배치 커밋 | `_confirmWithConflictCheck:1521-1540` | ✅ |
| B-064 | 경계값 | 확정 시 statsBatch 커밋 실패 | 충돌 지원서 AUTO_CANCELED 유지, TO pendingCount 불일치 → 수동 보정 필요 | `_confirmWithConflictCheck:1535-1540` | ⚠️ 원자성 부재 |
| B-065 | 경계값 | 야간 근무 시간대 충돌 (22:00~02:00) | 24h 정규화 후 정확한 겹침 판단 | `ApplicationModel.hasTimeOverlap:709-710` | ✅ |
| B-066 | 경계값 | 시간 겹침 없는 연속 시프트 (08:00~12:00 / 12:00~18:00) | 겹침 없음 — `x1 < y2 && x2 < y1` | `ApplicationModel.hasTimeOverlap:712` | ✅ |
| B-067 | 경계값 | 장기 지원 충돌 — 같은 요일, 기간 겹침 | `_findConflictingForLongTerm` 요일 교차 확인 | `application_firestore.dart:1562-1624` | ✅ |
| B-068 | 경계값 | 장기 지원 충돌 — 기간 겹치지 않음 | 충돌 없음 (기간 범위 이탈 → continue) | `_findConflictingForLongTerm:1602` | ✅ |
| B-069 | 경계값 | 장기 지원 시 기존 단기 확정과 요일 충돌 | 단기 확정 포함 충돌 탐색 (CONFIRMED 포함) | `_findConflictingForLongTerm:1574-1577` | ✅ |
| B-070 | 경계값 | 장기 지원 시 workDays=null → 단기 충돌 체크 폴백 | `workDays=null` → 단기 날짜 기준 충돌만 체크 → 이후 요일 충돌 미탐지 | `applyToTO():400-450` | ⚠️ 단기 폴백 시 충돌 누락 가능 |
| B-071 | **🔴 BUG-B-02** | 관리자 A, B 동시에 같은 근무자 두 충돌 PENDING 지원서 확정 | 두 지원서 모두 CONTRACT_PENDING 선점 → concurrentConflicts 로그만 → 자동 해결 없음 | `_confirmWithConflictCheck:1467-1470` | ❌ BUG-B-02 (설계 결정) |
| B-072 | 경계값 | 확정된 CONFIRMED 지원서와 장기 지원 충돌 | `_findConflictingForLongTerm` CONFIRMED 포함 탐색 → 차단 | `applyToTO():394-396` | ✅ |
| B-073 | 경계값 | 실제 퇴사일(actualResignDate)이 설정된 장기 근무와 충돌 | `actualResignDate ?? workEndDate` 기준 종료일 | `isWorkingOnDate:631-632` | ✅ |
| B-074 | 경계값 | 휴무일(leaveDates)에 대한 충돌 | `isWorkingOnDate:647` → 휴무일 false → 충돌 없음 | `isWorkingOnDate:647` | ✅ |
| B-075 | 경계값 | 추가근무일(extraWorkDates)에 대한 충돌 | 요일 무관 근무 → 충돌 체크 포함 | `isWorkingOnDate:646` | ✅ |

---

## B-076~085: 업무유형 변경

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| B-076 | 정상 | PENDING 지원서 업무유형 변경 | `selectedWorkType`, `wage` 업데이트, `workTypeCounts.pendingCount` 교환, 알림 | `changeApplicationWorkType():985-1113` | ✅ |
| B-077 | 정상 | CONFIRMED 지원서 업무유형 변경 | `confirmedCount` 교환, `originalWorkType/Wage` 이력 보존 | `changeApplicationWorkType:1072-1076` | ✅ |
| B-078 | 경계값 | 동일한 업무유형으로 변경 | "동일한 업무유형입니다" 에러, 차단 | `changeApplicationWorkType:1013-1016` | ✅ |
| B-079 | 경계값 | 정원 다 찬 업무유형으로 변경 | "모집인원이 이미 찼습니다. 그래도 변경됩니다" 경고 토스트, 변경 진행 | `changeApplicationWorkType:1033-1035` | ✅ |
| B-080 | 경계값 | CONTRACT_PENDING 지원서 업무유형 변경 | confirmedCount 교환 (CONTRACT_PENDING은 confirmedStatuses 포함) | `changeApplicationWorkType:1072` | ✅ |
| B-081 | 경계값 | Contract TO(slotId=null) CONFIRMED 업무유형 변경 | `workTypeConfirmedCounts` 교환 | `changeApplicationWorkType:1086-1091` | ✅ |
| B-082 | 경계값 | 슬롯에 존재하지 않는 업무유형으로 변경 | `workDetails.firstWhere` → empty {} → required=0 → 경고 없이 진행 | `changeApplicationWorkType:1027-1028` | ⚠️ 부재 업무유형 변경 차단 없음 |
| B-083 | 오류복구 | 업무유형 변경 배치 커밋 실패 | `false` 반환, 에러 토스트 | `changeApplicationWorkType:1108-1112` | ✅ |
| B-084 | 경계값 | 업무유형 변경 후 originalWorkType 중복 설정 | `original.originalWorkType ?? currentWorkType` → 최초 원본 보존 | `changeApplicationWorkType:1062` | ✅ |
| B-085 | 경계값 | REJECTED 지원서 업무유형 변경 | 상태 체크 없음 — REJECTED 지원서도 workType/wage 필드 변경됨 | `changeApplicationWorkType` 상태 검증 없음 | ⚠️ 비활성 지원서 변경 차단 없음 |

---

## B-086~100: 일괄 처리 / 재지원 / 계약 갱신 / 통계

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| B-086 | 정상 | 일괄 확정 3명 — 모두 성공 | `BatchResult(success:3, failed:0)` | `batchConfirmApplications:1120-1138` | ✅ |
| B-087 | 경계값 | 일괄 확정 중 1명 실패 | `BatchResult(success:2, failed:1)`, 실패 건 로그 | `batchConfirmApplications:1130-1133` | ✅ |
| B-088 | 경계값 | 일괄 확정 — 병렬 처리로 같은 슬롯 동시 확정 | 트랜잭션 선점으로 중복 확정 방지, 정원 초과 시 경고만 | `Future.wait` + 트랜잭션 선점 | ✅ |
| B-089 | 정상 | 재지원 — REJECTED 지원서 재사용 경로 | 기존 문서 reactivate (`status=PENDING`), TOCTOU 재검증 후 커밋 | `applyToTO():455-568` reactivatableApp | ✅ |
| B-090 | 경계값 | 재지원 시 TOCTOU 트랜잭션 실패 (방금 마감) | Exception throw → batch 미커밋 → `false` 반환 | `applyToTO`:498-550 트랜잭션 | ✅ |
| B-091 | 경계값 | 재지원 시 이전 퇴사/해지 완료 지원서 재사용 제외 | `isResignDone || isTermDone → continue` | `applyToTO:369-373` | ✅ |
| B-092 | 정상 | 계약 갱신 (createRenewedApplication) | 신규 CONTRACT_PENDING 지원서 생성, 원본 renewalDecision=EXTEND, totalConfirmed+1 | `createRenewedApplication:1958-2006` | ✅ |
| B-093 | 경계값 | 갱신 시 leaveDates/extraWorkDates 초기화 | 신규 계약에는 이전 특수 근무 일정 미승계 | `createRenewedApplication:1991-1992` | ✅ |
| B-094 | 경계값 | `statusHistory` 20개 초과 | 최근 20개만 유지 (`_appendHistory:2017-2019`) | `_appendHistory` | ✅ |
| B-095 | 경계값 | 내 지원 내역 TTL 캐시 히트 (1분 이내 재조회) | 서버 재조회 없이 캐시 반환 | `getMyApplications:120-124` | ✅ |
| B-096 | 경계값 | 내 지원 내역 캐시 만료 후 재조회 실패 | 만료된 기존 캐시 반환 | `getMyApplications:141` `cached ?? []` | ✅ |
| B-097 | 경계값 | `getApplicationsBySlotId` 지원자 500명 초과 | 501번째 이후 지원서 목록에서 누락 (limit 500) | `getApplicationsBySlotId:66` `.limit(500)` | ⚠️ 고트래픽 시 데이터 누락 |
| B-098 | 경계값 | 재지원 시 이전 conflictingAppId 등 초기화 | null로 초기화 | `applyToTO:476-479` | ✅ |
| B-099 | 경계값 | `workDate` 필드 누락된 Firestore 문서 파싱 | `ArgumentError` throw (throw 명시) | `ApplicationModel.fromMap:171` | ✅ |
| B-100 | 경계값 | `appliedAt` 필드 누락된 Firestore 문서 파싱 | `ArgumentError` throw (throw 명시) | `ApplicationModel.fromMap:201` | ✅ |

---

## 발견된 버그 상세

### BUG-B-01 (MEDIUM): cancelApplication — REJECTED 상태 메시지 오탐

**파일**: [application_firestore.dart:830](lib/services/firestore/application_firestore.dart#L830)

**현상**:
```dart
if (AppStatus.inactiveStates.contains(currentStatus)) {
  ToastHelper.showInfo('이미 취소된 지원서입니다.');
  return true;
}
```
`inactiveStates = [rejected, canceled, autoCanceled]` 이므로 REJECTED 상태에서도 "이미 취소된 지원서입니다" 메시지가 표시됨. 거절(Rejected)과 취소(Canceled)는 다른 개념이므로 사용자 혼란.

**수정**:
```dart
if (currentStatus == AppStatus.rejected) {
  ToastHelper.showInfo('이미 거절된 지원서입니다.');
  return true;
}
if (AppStatus.inactiveStates.contains(currentStatus)) {
  ToastHelper.showInfo('이미 취소된 지원서입니다.');
  return true;
}
```

---

### BUG-B-02 (MEDIUM): 동시 확정 CONTRACT_PENDING 충돌 미자동 해결

**파일**: [application_firestore.dart:1464](lib/services/firestore/application_firestore.dart#L1464)

**현상**: 관리자 A, B가 동시에 같은 근무자의 시간 충돌 PENDING 지원서 각각을 확정하면:
1. App X: 트랜잭션 → CONTRACT_PENDING
2. App Y: 트랜잭션 → CONTRACT_PENDING
3. App X 충돌 탐색 → App Y = concurrentConflict → 경고 로그만
4. App Y 충돌 탐색 → App X = concurrentConflict → 경고 로그만
5. 결과: 같은 근무자에게 시간 충돌하는 두 CONTRACT_PENDING 계약이 공존

**현재 처리**: `[186]` 코드로 알려진 기술적 부채, "수동 확인 필요" 로그 출력.

**권고**: 낮은 발생 빈도(동시 확정 레이스)이나, 알림 시스템 또는 관리자 화면에서 CONTRACT_PENDING 상태 근무자의 시간 충돌 감지 배너 추가 권장.

---

## 추가 검증 필요 (⚠️) 요약

| # | 시나리오 | 내용 |
|---|----------|------|
| B-033 | 배치 커밋 실패 + 롤백 실패 | CONTRACT_PENDING limbo → 관리자 수동 처리 필요, 알림 부재 |
| B-055 | 관리자 취소 + businessId 없음 | idCardAccessRequests 미정리 가능 |
| B-064 | statsBatch 실패 | TO pendingCount 불일치 발생 → 수동 보정 필요 |
| B-070 | 장기 지원 workDays=null | 이후 요일 충돌 미탐지 — TO 생성 시 workDays 필수로 방지 가능 |
| B-082 | 존재하지 않는 업무유형으로 변경 | 차단 없음 — UI에서 TO workDetails 기준 선택지 제한으로 방어 |
| B-085 | 비활성 지원서 업무유형 변경 | REJECTED/CANCELED 지원서 변경 허용 — UI 진입점에서 필터링으로 방어 |
| B-097 | 슬롯당 지원자 500명 초과 | limit(500) 페이지네이션 없음 — 실운영 threshold 낮음 |
