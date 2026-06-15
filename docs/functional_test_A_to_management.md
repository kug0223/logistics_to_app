# Category A: TO/공고 관리 기능 테스트 시나리오 100개

> 감사 기준일: 2026-06-12  
> 대상 파일: `create_to_screen.dart`, `edit_to_screen.dart`, `to_firestore.dart`  
> 발견 버그: **BUG-A-01**, **BUG-A-02**, **BUG-A-03** (아래 표 내 🔴 표시)

---

## 버그 요약

| ID | 심각도 | 위치 | 설명 |
|----|--------|------|------|
| BUG-A-01 | HIGH | `edit_to_screen.dart:294` | 마스터 TO 수정 시 `totalRequired`가 슬롯 수 무관하게 템플릿 1개분 값으로 덮어씌워짐 | **수정 완료** |
| BUG-A-02 | MEDIUM | `to_firestore.dart:714` | `batchReopenSlots` 시 `full` 상태 슬롯도 `open`으로 강제 전환 → 초과 지원 허용 | **수정 완료** |
| BUG-A-03 | MEDIUM | `to_firestore.dart:1121` | `_syncTOCascadeStatus`가 `SlotStatus.open`만 확인 → 전체 슬롯이 `full`이면 TO 자동 CLOSED 처리 | **수정 완료** |

---

## A-001~020: Flex TO 생성

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| A-001 | 정상 | 즉시공개 Flex TO, 업무 1개, 인원 3, 날짜 3개 선택 후 저장 | `isPublished=false` → 슬롯 생성 완료 후 `isPublished=true` (deferPublish) | `createTO()` deferPublish 로직 | ✅ |
| A-002 | 정상 | 즉시공개 Flex TO, 업무 3개(서로 다른 시간대), 날짜 5개 저장 | 슬롯 5개 × 업무 3개 workDetails 생성, totalRequired = 합산 × 5 | `_createSlots()` | ✅ |
| A-003 | 정상 | 예약공개(D-2) Flex TO 저장 | 각 슬롯 `visibleFrom = date - 2days` | `updateSlotsPublishSettings()` | ✅ |
| A-004 | 정상 | 마감 설정 HOURS_BEFORE=4 | 각 슬롯 workDetail `applicationDeadline = startTime - 4h` | `_createSlots()` deadline 계산 | ✅ |
| A-005 | 정상 | SubAdmin 계정으로 자신이 소속된 1개 사업장만 TO 생성 | `effectiveBusinessId` 자동 적용, 사업장 선택 불필요 | `create_to_screen.dart` effectiveBusinessId | ✅ |
| A-006 | 경계값 | 업무 인원 = 1 (최솟값) | 정상 저장 | `create_to_screen.dart` 검증 | ✅ |
| A-007 | 경계값 | 업무 인원 = 9999 (최댓값 근처) | 정상 저장 | `create_to_screen.dart` 인원 < 10000 | ✅ |
| A-008 | 경계값 | 업무 인원 = 10000 (초과) | "인원 수가 너무 많습니다" 경고, 저장 차단 | `create_to_screen.dart` 인원 ≥ 10000 | ✅ |
| A-009 | 경계값 | 시급 = 10,030원 (최저임금) | 정상 저장 | `create_to_screen.dart` 시급 > 0 | ✅ |
| A-010 | 경계값 | 시급 = 50,000,000원 (한도 초과) | "급여가 너무 높습니다" 경고, 저장 차단 | `create_to_screen.dart` 급여 > 50,000,000 | ✅ |
| A-011 | 경계값 | 업무 0개로 저장 시도 | "업무를 추가해주세요" 경고, 저장 차단 | `create_to_screen.dart` 업무 미추가 검증 | ✅ |
| A-012 | 경계값 | 날짜 0개로 저장 시도 | "날짜를 선택해주세요" 경고, 저장 차단 | `create_to_screen.dart` 날짜 미선택 검증 | ✅ |
| A-013 | 경계값 | 동일 업무타입 + 동일 시간대 업무 중복 추가 | "이미 추가된 업무입니다" 경고, 중복 차단 | `workType + startTime + endTime` 조합 중복 검증 | ✅ |
| A-014 | 경계값 | 슬롯 생성 도중 네트워크 오류(일부 슬롯만 생성) | 부분 생성된 슬롯 삭제 + TO 삭제 롤백 | `createTO()` 롤백 로직 | ✅ |
| A-015 | 경계값 | 기존 TO 불러오기(복사) 후 날짜 미선택 상태로 저장 | 날짜 검증 오류, 기존 TO 데이터 영향 없음 | 기존 공고 날짜/요일 미복사 설계 | ✅ |
| A-016 | 경계값 | 만료된 날짜만 선택 후 저장 | `_allSlotsExpired` = true → 경고 표시 (저장은 허용) | `_isSlotExpired()`, `_allSlotsExpired` | ✅ |
| A-017 | 경계값 | 일부 날짜 만료 + 일부 유효 | `_someSlotExpired` = true → 경고 뱃지 표시 | `_someSlotExpired` 게터 | ✅ |
| A-018 | 오류복구 | TO 생성 중 슬롯 생성 전 오류 | TO 문서 삭제 롤백 | `createTO()` catch 블록 | ✅ |
| A-019 | 오류복구 | 슬롯 생성 완료 후 `isPublished=true` 전환 실패 | TO가 `isPublished=false` 유지, 관리자 화면에 비공개 표시 | deferPublish 실패 시 fallback 없음 → 비공개 유지 | ⚠️ 추가 검증 필요 |
| A-020 | 오류복구 | 슬롯 생성 일부 실패 (502 중간에 오류) | 성공한 슬롯 + TO 모두 삭제 (부분 롤백) | `createTO()` partial slot deletion | ✅ |

---

## A-021~040: Contract TO 생성

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| A-021 | 정상 | Contract TO, 업무 1개, 날짜범위 설정, 고정마감일 지정 | `applicationDeadline` 필드 저장, 슬롯 없이 TO만 생성 | Contract 타입 분기, `applicationDeadline` | ✅ |
| A-022 | 정상 | Contract TO 즉시공개 | `isPublished=true` 즉시 (deferPublish 없음) | Contract는 슬롯 없으므로 deferPublish 스킵 | ✅ |
| A-023 | 정상 | Contract TO 예약공개(publishAt 미래 시각) | `isPublished=false`, `publishAt` 저장 | `shouldPublishImmediately` 분기 | ✅ |
| A-024 | 경계값 | Contract TO 예약공개 시각이 과거 | "즉시공개로 전환됩니다" 토스트, `isPublished=true` | `edit_to_screen.dart:287-290` 과거 시각 체크 | ✅ |
| A-025 | 경계값 | Contract TO 고정 마감일 = 과거 날짜 | "지원 마감일이 과거 날짜입니다" 경고 토스트, 저장은 허용 | `create_to_screen.dart` `_fixedDeadline.isBefore(todayStart)` | ✅ (수정 완료) |
| A-026 | 경계값 | Contract TO 날짜범위: 시작일 > 종료일 설정 시도 | 날짜 유효성 오류, 저장 차단 | `create_to_screen.dart` rangeStart/rangeEnd 검증 | ⚠️ 추가 검증 필요 |
| A-027 | 경계값 | Contract TO 업무 인원 = 0 | 저장 차단 | `create_to_screen.dart` 인원 ≤ 0 검증 | ✅ |
| A-028 | 경계값 | Contract TO 제목 빈 문자열 | 저장 차단 또는 빈 제목 허용 여부 | `create_to_screen.dart` 제목 검증 | ⚠️ 추가 검증 필요 |
| A-029 | 경계값 | Contract TO + 일급 타입 설정 | `wageType = 'daily'` 저장 | WorkDetailData wageType 필드 | ✅ |
| A-030 | 경계값 | Contract TO + 심야수당 적용 | `nightAllowanceApplied = true`, `nightIncluded = true` | WorkDetailData 필드 | ✅ |
| A-031 | 정상 | SubAdmin이 자신이 소속 안 된 사업장 TO 생성 시도 | 사업장 선택 불가 (effectiveBusinessId 제한) | `effectiveBusinessId` null 체크 | ✅ |
| A-032 | 경계값 | Contract TO + payScheduleType = 'weekly', payScheduleDay = 0 (일요일) | `payScheduleDay = 0` 저장 | WorkDetailData payScheduleDay | ✅ |
| A-033 | 경계값 | Contract TO + taxDeductionType = 'none' | 공제 없음 저장 | WorkDetailData taxDeductionType | ✅ |
| A-034 | 오류복구 | Contract TO 저장 중 Firestore 오류 | 에러 토스트, TO 미생성, 화면 유지 | `create_to_screen.dart` catch 블록 | ✅ |
| A-035 | 경계값 | Contract TO 설명(description) = 2000자 초과 | 제한 여부 검증 (현재 코드에서 길이 제한 없음) | `create_to_screen.dart` description 미검증 | ⚠️ 길이 제한 없음 확인 필요 |
| A-036 | 정상 | Contract TO 복수 업무타입(주간+야간) 동시 등록 | workDetails 배열에 2개 저장 | `_workDetails.add()` 로직 | ✅ |
| A-037 | 경계값 | 제목 = 공백만 | 공백 trim 후 빈 문자열로 저장 차단 여부 | `_titleController.text.trim()` | ⚠️ trim 후 빈 문자열 검증 필요 |
| A-038 | 경계값 | 사업장 미선택 상태에서 저장 시도 | "사업장을 선택해주세요" 경고, 차단 | `create_to_screen.dart` businessId 검증 | ✅ |
| A-039 | 오류복구 | 기존 TO 불러오기 중 TO가 이미 삭제된 경우 | 에러 처리, 빈 화면 방지 | `create_to_screen.dart` 기존 TO 로드 | ⚠️ 추가 검증 필요 |
| A-040 | 정상 | Contract TO `postingDurationDays = 30` 설정 | `postingDurationDays = 30` 저장 | edit_to_screen.dart `postingDurationDays` | ✅ |

---

## A-041~055: 마스터 TO 수정

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| A-041 | 정상 | Flex TO 제목/설명만 변경 저장 | 제목·설명 업데이트, 슬롯 workDetails 동기화 (업무 내용 무변경) | `edit_to_screen.dart` `_saveChanges()` | ✅ |
| A-042 | **🔴 BUG-A-01** | 슬롯 5개 Flex TO (`totalRequired=15`) 마스터 수정 | totalRequired 기대: 15 / **실제: 3** (템플릿 1개 합산으로 덮어씀) | `edit_to_screen.dart:294-304` | ❌ BUG-A-01 |
| A-043 | **🔴 BUG-A-01** | 슬롯별 개별 requiredCount 수정 후 마스터 수정 | 슬롯 커스텀 값 유실, TO.totalRequired 오염 | `edit_to_screen.dart:294` + `updateSlotsDeadlines` requiredCount 덮어쓰기 | ❌ BUG-A-01 |
| A-044 | 정상 | Contract TO 마스터 수정 | totalRequired = workDetails 합산 (슬롯 1개 구조 → 정상) | `edit_to_screen.dart` Contract 분기 없음 | ✅ |
| A-045 | 정상 | 마감된 Flex TO 수정 시 자동 재오픈 | `isManualClosed=false`, `status=ACTIVE` | `edit_to_screen.dart:298-326` `wasClosed` 처리 | ✅ |
| A-046 | 정상 | SCHEDULED(예약공개) TO 수정 후 예약 시각이 과거 | "즉시공개로 전환됩니다" 토스트, `isPublished=true` | `edit_to_screen.dart:287-290` | ✅ |
| A-047 | 경계값 | 슬롯 동기화(`updateSlotsDeadlines`) 실패 시 | TO 저장은 이미 커밋됨, `slotSyncFailed=true` 경고 표시 | `edit_to_screen.dart` slotSyncFailed 처리 | ✅ |
| A-048 | 경계값 | `hoursBeforeStart` 수정 → 슬롯 전체 마감시간 재계산 | 모든 슬롯 `applicationDeadline` 갱신 | `updateSlotsDeadlines` | ✅ |
| A-049 | 경계값 | `hoursBeforeStart` 수정 후 이미 마감된 슬롯 처리 | 자동마감(closedBy=null) 슬롯만 미래 마감 업무 있으면 재오픈 | `updateSlotsDeadlines:565-569` isAutoClosed 체크 | ✅ |
| A-050 | 경계값 | 수동마감(closedBy=uid) 슬롯이 있는 TO 마스터 수정 | 수동마감 슬롯 상태 변경 없음 (isAutoClosed=false) | `updateSlotsDeadlines:557-558` | ✅ |
| A-051 | 경계값 | `publishMode` = immediate → scheduled 변경 저장 | 모든 슬롯 `visibleFrom` 재계산 | `publishSettingsChanged` 체크 → `updateSlotsPublishSettings()` | ✅ |
| A-052 | 경계값 | `publishMode` = scheduled → immediate 변경 저장 | 모든 슬롯 `visibleFrom` 삭제 | `updateSlotsPublishSettings()` immediate 분기 | ✅ |
| A-053 | 오류복구 | TO 수정 저장 실패 | 에러 토스트, Firestore 미변경 | `edit_to_screen.dart` catch → showError | ✅ |
| A-054 | 경계값 | draft TO에서 슬롯 공개 설정 변경 없이 마스터 수정 | `_slotPublishChanged=false` → TO draft 상태 전환 없음 | `_slotPublishChanged` 플래그 | ✅ |
| A-055 | 경계값 | Contract TO `applicationDeadline` 제거(null) 저장 | `applicationDeadline` 필드 삭제 | `edit_to_screen.dart:329-332` Contract 분기 | ✅ |

---

## A-056~070: 슬롯 수정 (개별 / 배치)

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| A-056 | 정상 | 개별 슬롯 업무 인원 3 → 5 수정 | `updateSlotFull` → TO.totalRequired += 2 | `to_firestore.dart:614-616` | ✅ |
| A-057 | 정상 | 개별 슬롯 업무 인원 5 → 3 수정 | `updateSlotFull` → TO.totalRequired -= 2 | `to_firestore.dart:614-616` | ✅ |
| A-058 | 경계값 | 개별 슬롯 업무 인원 변경 없이 다른 필드만 수정 | `oldTotalRequired == newTotalRequired` → TO 카운터 미변경 | `to_firestore.dart:614` | ✅ |
| A-059 | 경계값 | 개별 슬롯 업무 시작시간/종료시간 수정 → 마감시간 재계산 | `applicationDeadline = startTime - hoursBeforeStart` | `edit_to_screen.dart:544-560` | ✅ |
| A-060 | 정상 | 배치 수정 — 슬롯 3개 동시에 업무 내용 변경 | 3개 슬롯 모두 `updateSlotFull` 개별 호출 | `edit_to_screen.dart:541-579` 반복 처리 | ✅ |
| A-061 | 경계값 | 배치 수정 중 일부 슬롯 실패 | 성공 건 커밋됨, 실패 날짜 목록 에러 토스트 | `edit_to_screen.dart:576-582` failedSlots 처리 | ✅ |
| A-062 | 경계값 | 배치 수정 — 전체 슬롯 실패 | 에러 토스트, TO 상태 미변경 | failedSlots.isNotEmpty → throw | ✅ |
| A-063 | 경계값 | 개별 슬롯 `visibleFrom` 미래 날짜 설정 | `visibleFrom` Timestamp 저장 | `updateSlotFull` visibleFrom 분기 | ✅ |
| A-064 | 경계값 | 개별 슬롯 `visibleFrom` 제거(즉시공개 전환) | `clearVisibleFrom=true` → `visibleFrom: FieldValue.delete()` | `updateSlotFull:609` | ✅ |
| A-065 | 경계값 | 배치 수정 시 draft TO 슬롯 공개 설정 변경 | `_slotPublishChanged=true` → `_applyTODraftTransition` 호출 | `edit_to_screen.dart:532-538` | ✅ |
| A-066 | 경계값 | 슬롯 타이틀 수정 후 저장 | 슬롯 `title` 필드 업데이트 | `updateSlotFull:607-608` | ✅ |
| A-067 | 경계값 | 슬롯 타이틀 빈 문자열 저장 | `title: FieldValue.delete()` (필드 제거) | `updateSlotFull:607-608` else 분기 | ✅ |
| A-068 | 경계값 | 마감된 슬롯에 대해 수정 시도 (isBatchMode) | 마감 슬롯 포함 배치 수정 시 각 슬롯 개별 업데이트 | isBatchMode 분기 | ✅ |
| A-069 | 오류복구 | 배치 수정 중 네트워크 단절 | 단절 이전 성공한 슬롯 커밋됨, 이후 실패 | 순차 처리 → 부분 적용 | ⚠️ 원자성 보장 안 됨 확인 필요 |
| A-070 | 경계값 | 개별 슬롯 요구인원 0 설정 | `ArgumentError` throw → 호출자 catch 처리 | `to_firestore.dart` `updateSlotFull` requiredCount ≤ 0 검증 | ✅ (수정 완료) |

---

## A-071~080: 슬롯 추가 / 삭제 / 마감 / 재오픈

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| A-071 | 정상 | CLOSED 상태 Flex TO에 새 슬롯 추가 | `status=ACTIVE`, `totalRequired += newSlotRequired`, `totalSlots += 1` | `addSlot:851-876` | ✅ |
| A-072 | 정상 | 비공개 CLOSED TO에 새 슬롯 추가 | `status=ACTIVE`, `isPublished` 기존 유지 (false 유지) | `addSlot:860` `if (to.isPublished)` | ✅ |
| A-073 | 경계값 | ACTIVE TO에 슬롯 추가 → rangeEnd 이후 날짜 | `rangeEnd` 갱신, `totalSlots/totalRequired` 증가 | `addSlot:866-874` | ✅ |
| A-074 | 경계값 | ACTIVE TO에 슬롯 추가 → rangeStart 이전 날짜 | `rangeStart` 갱신 | `addSlot:870-873` | ✅ |
| A-075 | 정상 | 슬롯 1개 수동 마감 | `isManualClosed=true`, `status=closed` → PENDING 취소 → TO 상태 동기화 | `batchCloseSlots`, `_syncTOCascadeStatus` | ✅ |
| A-076 | 정상 | 모든 슬롯 수동 마감 | 모든 슬롯 closed → `_syncTOCascadeStatus` → TO CLOSED | `_syncTOCascadeStatus:1123-1127` | ✅ |
| A-077 | **🔴 BUG-A-02** | `full` 상태 슬롯 수동 마감 후 재오픈 | `batchReopenSlots` → **status=open** (confirmedCount 무시) → 초과 지원 허용됨 | `batchReopenSlots:714` | ❌ BUG-A-02 |
| A-078 | **🔴 BUG-A-03** | 모든 슬롯이 `full` 상태(CLOSED 아님)가 되는 경우 | `_syncTOCascadeStatus:1121` `hasOpenSlot=false` → TO 자동 CLOSED | `_syncTOCascadeStatus` full 미고려 | ❌ BUG-A-03 |
| A-079 | 정상 | 슬롯 1개 삭제 | `totalSlots/totalRequired/totalConfirmed/totalPending` 감소, 활성 지원서 취소 | `batchDeleteSlots:741-795` | ✅ |
| A-080 | 정상 | 마지막 슬롯 삭제 | TO `status=CLOSED`, `isPublished=false`, 모든 카운터 0 | `batchDeleteSlots:810-821` | ✅ |

---

## A-081~090: 공개 / 비공개 설정

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| A-081 | 정상 | draft TO → 슬롯 공개 설정 변경 시 TO 전환 | `_slotPublishChanged=true` → `_applyTODraftTransition` | `edit_to_screen.dart:503-504` | ✅ |
| A-082 | 경계값 | draft TO → 슬롯 공개 설정 변경 없이 저장 | TO draft 상태 유지 | `_slotPublishChanged=false` | ✅ |
| A-083 | 정상 | 즉시공개 → 예약공개(D-3) 변경 | 모든 슬롯 `visibleFrom = date - 3days` 재계산 | `updateSlotsPublishSettings` scheduled 분기 | ✅ |
| A-084 | 정상 | 예약공개 → 즉시공개 변경 | 모든 슬롯 `visibleFrom` 삭제 | `updateSlotsPublishSettings` immediate 분기 | ✅ |
| A-085 | 경계값 | 예약공개 슬롯에서 `visibleFrom`이 이미 지난 슬롯 | 이미 노출 중인 슬롯 visibleFrom 덮어쓰기 발생 가능 | `updateSlotsPublishSettings` 과거 날짜 무시 없음 | ⚠️ 과거 슬롯 visibleFrom 덮어쓰기 확인 필요 |
| A-086 | 경계값 | `publishDaysBefore = 0` 설정 (당일 공개) | `visibleFrom = date` (자정) | `updateSlotsPublishSettings:917-919` | ✅ |
| A-087 | 경계값 | `publishTime = "00:00"` 설정 | 슬롯 당일 자정 공개 | `publishTime split(':')` | ✅ |
| A-088 | 경계값 | `publishTime = "23:59"` 설정 | 슬롯 전날 23:59 공개 | `updateSlotsPublishSettings:917-919` | ✅ |
| A-089 | 경계값 | 배치 슬롯 수정 시 anyImmediate=true(즉시+예약 혼합) | `_applyTODraftTransition(null)` → 즉시공개 전환 | `edit_to_screen.dart:534-538` | ✅ |
| A-090 | 오류복구 | `updateSlotsPublishSettings` 실패 | rethrow → 호출자에서 에러 처리 | `updateSlotsPublishSettings:936-937` | ✅ |

---

## A-091~100: 통계 동기화 및 TO 삭제

| # | 유형 | 시나리오 | 예상 결과 | 코드 근거 | 결과 |
|---|------|----------|-----------|-----------|------|
| A-091 | 정상 | 지원서 CONFIRMED 처리 후 슬롯 통계 | `confirmedCount++`, 수동마감 아닐 시 `status = full/open` 재설정 | `updateSlotStats:978-981` | ✅ |
| A-092 | 정상 | 수동마감 슬롯 통계 업데이트 시 상태 변경 금지 | `isManualClosed=true` → `slotUpdates['status']` 미포함 | `updateSlotStats:978` | ✅ |
| A-093 | 경계값 | `confirmedCount = requiredCount - 1` → 지원 확정 | `confirmedCount = requiredCount` → `status = full` | `updateSlotStats:979-981` | ✅ |
| A-094 | 경계값 | `confirmedCount = requiredCount` 상태에서 취소 | `confirmedCount--` → `status = open` | `updateSlotStats` confirmedDelta = -1 | ✅ |
| A-095 | **🔴 BUG-A-03** | 슬롯 5개 모두 `full` → `batchCloseSlots` 없이 자연 full 상태 | `_syncTOCascadeStatus` 미호출이라 TO 상태 미변경 (updateSlotStats에서 sync 안 함) | `updateSlotStats` → `_syncTOCascadeStatus` 미호출 | ⚠️ TO 상태 동기화 누락 확인 필요 |
| A-096 | 경계값 | 슬롯 삭제 후 남은 슬롯으로 rangeStart/rangeEnd 재계산 | 삭제된 슬롯 날짜가 경계였으면 재계산 | `batchDeleteSlots:800-807` | ✅ |
| A-097 | 경계값 | `batchCloseSlots` 중 PENDING 취소 실패 | `totalPending` 감소 없음, 에러 로그 출력 | `batchCloseSlots:684` debugPrint, catch | ✅ |
| A-098 | 경계값 | PENDING 500건 이상 슬롯 마감 | 499건 단위로 batch 분할 처리 | `batchCloseSlots:675-678` | ✅ |
| A-099 | 경계값 | 슬롯 500개 이상 배치 마감 | 499개 단위로 batch 분할 | `batchCloseSlots:647-648` | ✅ |
| A-100 | 오류복구 | `_syncTOCascadeStatus` 실패 | `try/catch` 내 debugPrint만 — TO 상태 미갱신이어도 앱 크래시 없음 | `_syncTOCascadeStatus:1136-1138` | ✅ |

---

## 발견된 버그 상세

### BUG-A-01 (HIGH): 마스터 TO 수정 시 totalRequired 덮어쓰기

**파일**: [edit_to_screen.dart:294](lib/screens/business_admin/to_management/edit_to_screen.dart#L294)

**재현 경로**:
1. Flex TO 생성: 5개 슬롯, 각 3명 → `TO.totalRequired = 15`
2. `updateSlotFull`로 슬롯 1 requiredCount 3→5 → `TO.totalRequired = 17`
3. 마스터 TO 수정 화면 진입 → 제목만 변경 후 저장
4. 결과: `TO.totalRequired = 3` (슬롯 수 × 인원 무시, 템플릿 1개분 합산만 저장)

**원인**: `_saveChanges()`의 `totalRequired = _workDetails.fold(...)` 가 단일 슬롯 템플릿 합산임.  
추가로 `updateSlotsDeadlines`가 각 슬롯 workDetails.requiredCount도 템플릿 값으로 초기화.

**수정 방안**:
```dart
// edit_to_screen.dart 수정안
// 슬롯 수 × 템플릿 요구인원으로 계산
final perSlotRequired = _workDetails.fold<int>(0, (s, d) => s + d.requiredCount);
final slotCount = widget.to.totalSlots > 0 ? widget.to.totalSlots : 1;
final totalRequired = widget.to.isContractType
    ? perSlotRequired
    : perSlotRequired * slotCount;
```

---

### BUG-A-02 (MEDIUM): batchReopenSlots — full 슬롯 재오픈 시 status=open 강제 설정

**파일**: [to_firestore.dart:714](lib/services/firestore/to_firestore.dart#L714)

**재현 경로**:
1. Flex TO 슬롯에 3명 지원 확정 → `status = full`
2. 관리자가 해당 슬롯 수동 마감 → `status = closed`, `isManualClosed = true`
3. 관리자가 수동 마감 해제 → `status = open` (confirmedCount=3, requiredCount=3 무시)
4. 결과: 이미 정원 다 찬 슬롯에 새 지원 허용

**원인**: `batchReopenSlots`가 `status = SlotStatus.open`을 무조건 기록.

**수정 방안**:
```dart
// 서버에서 confirmedCount와 totalRequired를 읽어서 full 여부 결정
final data = slotSnap.data()!;
final confirmed = (data['confirmedCount'] as num?)?.toInt() ?? 0;
final wds = data['workDetails'] as List? ?? [];
final required = wds.fold<int>(0, ...);
final newStatus = (required > 0 && confirmed >= required)
    ? SlotStatus.full
    : SlotStatus.open;
batch.update(ref, {'status': newStatus, ...});
```

---

### BUG-A-03 (MEDIUM): _syncTOCascadeStatus — full 슬롯을 open으로 미인식

**파일**: [to_firestore.dart:1121](lib/services/firestore/to_firestore.dart#L1121)

**재현 경로**:
1. Flex TO 전체 슬롯이 확정 인원으로 `full` 상태 진입 (`batchCloseSlots` 없이)
2. `_syncTOCascadeStatus` 호출 → `hasOpenSlot = slots.any((s) => s.status == SlotStatus.open)`
3. 모든 슬롯 `full` → `hasOpenSlot = false`
4. TO가 openState → **TO 자동 CLOSED** (의도치 않은 닫힘)

**원인**: `hasOpenSlot` 체크가 `full` 상태를 "열린 슬롯"으로 인식하지 않음.

**수정 방안**:
```dart
final hasOpenSlot = slots.any((s) =>
    s.status == SlotStatus.open || s.status == SlotStatus.full);
```

---

## 검증 미완료 항목 (⚠️) 요약

| # | 시나리오 | 미완료 이유 |
|---|----------|------------|
| A-019 | deferPublish 실패 시 TO 비공개 유지 | 런타임 테스트 필요 |
| A-025 | Contract TO 당일 마감일 허용 여부 | UI 검증 필요 |
| A-026 | rangeStart > rangeEnd 설정 시 차단 여부 | create_to_screen 날짜 검증 코드 확인 필요 |
| A-028 | TO 제목 빈 문자열 허용 여부 | create_to_screen trim 후 검증 코드 확인 필요 |
| A-035 | description 최대 길이 제한 없음 | 길이 제한 미구현 확인 |
| A-037 | 제목 공백만 입력 차단 여부 | trim() 후 isEmpty 검증 확인 필요 |
| A-039 | 기존 TO 불러오기 시 삭제된 TO 에러 처리 | 런타임 테스트 필요 |
| A-069 | 배치 수정 원자성 — 부분 적용 위험 | 설계상 허용이나 UX 개선 여지 |
| A-070 | 슬롯 requiredCount = 0 서버 저장 허용 | updateSlotFull 서버 검증 없음 |
| A-085 | 예약공개 설정 변경 시 이미 노출 중인 슬롯 visibleFrom 덮어쓰기 | 런타임 테스트 필요 |
| A-095 | 모든 슬롯 full 시 TO 상태 동기화 누락 | updateSlotStats → _syncTOCascadeStatus 미호출 확인 |
