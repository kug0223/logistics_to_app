# R7 — Staffing 숫자 lineage / 상태 전이 / 집계 정합성 감사

- **감사 시작 HEAD:** `9391e30` · branch `main`
- **작성:** 2026-09-27 KST
- **성격:** 사용자 지시에 따른 **체계적 감사**. 한 경로씩 고치는 방식을 중단하고
  수집→검증→계산→저장→조회→출력 전체를 지도로 만든다.
- **이 문서는 `R7_Staffing_Count_Transition_Recovery_Request.md` 를 대체한다.**

> ## ⛔ 이 감사는 **CLOSED 가 아니다**
>
> §11 기준 중 충족한 것과 못 한 것을 §9 에 정확히 적었다.
> 이번 차수에서 한 것은 **(A) 재현 사례의 원장 대조 · (B) 공통 root cause 1건의
> 식별과 수정 · (C) 전이표/사전의 1차 골격**이다.
> 전체 writer×consumer matrix 실행과 Emulator 통합 검증은 **미실시**다.

---

## 1. 재현 사례 — 원장이 진실이고 화면이 거짓이었다

사용자 재현: `[R7FIX] 한 날짜만 마감` 9/29 tile **1/1** → 날짜 선택 후 **0/1**,
상세 `충원 0 · 미충원 1`, 상단은 `충원 1` 유지.

### DEV READ (쓰기 0)

```
toId  EKICbhyyNlGtLRrEMLwc   type=flex  status=ACTIVE
      totalRequired=2 totalConfirmed=1 totalPending=0
      to.workDetails = [{사무업무 10:00~16:00, req 1}]        ← wdId 없음

slot  N2UxClhaBW7zhc6ThXKs (2026-09-29)  status=full  confirmedCount=1
      slot.workDetails  = [{wdId: "xyhBqRBwnNRuLovGIYsL", req 1}]
      workDetailCounts  = {"xyhBqRBwnNRuLovGIYsL": {confirmedCount: 1, pendingCount: 0}}

app   status=CONTRACT_PENDING  slotId=N2UxClha  wdId="xyhBqRBwnNRuLovGIYsL"
      workDate=2026-09-29  staffingReleasedAt=null  type=short
```

**원장은 정합하다** — slot 카운터 1 = `workDetailCounts` 1 = 지원서 1건.
**1/1 이 진실이고 `충원 0` 이 거짓이다.** 저장 손상 아님.

---

## 2. Root cause — 업무 정의의 **identity 원천이 둘**이다 (FLEX)

| 원천 | 키 | 누가 쓰는가 |
|---|---|---|
| `slot.workDetails[].wdId` | `xyhBqRBwnNRuLovGIYsL` | **원장** `slot.workDetailCounts` · **지원서** `app.wdId` |
| `to.workDetails[].wdId` | **없음**(→ composite) 또는 **다른 값** | master 정의로 조회하는 consumer |

### DEV 전수 대조 — `scripts/r7-staffing-identity-reconcile.js` (READ ONLY)

`businessId fLmSOHVKUwmBHcbwQE0I` · **TO 93 · slot 172**

| | |
|---|---|
| slot 정의에 `wdId` 있음 | **172 / 172 (전부)** |
| master 정의에 `wdId` 가 전혀 없음 | **25 TO** |
| **원천에 따라 값이 갈리는 자리** | **17건** |
| 그 17건의 값 | `viaSlot = 원장값` · **`viaMaster = 0`** |

`[R6.1] Clean Golden Path` · `[R8P2] p3b sign` · `chain-32` · `p3b2 wage` ·
`p3b1 void` · `chain2` 는 **양쪽 다 wdId 가 있는데 값이 다르다**
(slot `xw87EbAh…` vs master `rBnNxCMg…`) — **slot 생성 시 wdId 를 새로 만든다.**
따라서 master 정의로는 원장/지원서와 **절대 만나지 못한다.**

### 왜 기존 검증이 놓쳤나

1. **DEVICE.1D/1E 가 넣은 `to.workDetails` 폴백이 원인 경로였다.**
   "정의가 비어 있으면 master 로 폴백" 은 장기(slot 없음)에서는 맞지만,
   slot 이 있는 TOItem 에서는 **identity 가 다른 정의로 갈아타는 것**이다.
2. **`loadTOWorkDetails` 의 seed 키가 composite 였다.**
   `workStats[w.id]`(composite) + 지원서 `app.wdId` → wdId 를 가진 정의에서
   composite seed 는 **영원히 0 인 유령 항목**이 되고,
   `lookupByIdentity`(`map[canonicalId] ?? map[id]`)의 composite 폴백이 그것을
   집어 **조회 실패를 `0` 으로** 바꿨다. 그래서 UNKNOWN 표면이 서지 못했다.
3. 기존 테스트는 그 seed 표현을 **literal 로 고정**하고 있어(3개 파일),
   키가 틀렸다는 사실 자체를 보호하고 있었다.

### 수정 (3곳, 작은 단위)

| 위치 | 변경 |
|---|---|
| `firestore_service.loadTOWorkDetails` | seed 키 `w.id` → **`w.canonicalId`** |
| `TOItem.statsAlignedWorkDetails` (신규) | 정의 폴백을 **slot == null 일 때로 좁힘**. `resolveStats`·`hasLoadedStats` 가 사용 |
| `TOItem.resolveStats` | 업무 하나라도 조회 miss 면 **집계를 버리고 카운터 폴백** (`?? 0` 제거) |
| `work_applicants_dialog._updateLocalStats` | 같은 폴백 축소 + 쓰기 키 canonicalId |

`getSlotWorkDetailCapacities` 는 **이미 wdId 우선**이라 변경 없음(일관 확인).

### 계약 변화

| | 이전 | 이후 |
|---|---|---|
| wdId 있는 정의 | seed=composite, 지원서=wdId → **만나지 못함** | 둘 다 canonicalId → **만남** |
| wdId 없는 정의 | seed=composite, 지원서 폴백=composite → 만남 | 동일 (유지) |
| identity 가 다른 정의 | composite 유령 0 → **거짓 0** | **null = UNKNOWN** |
| 부분 miss | 일부만 세어 합계 주장 | **카운터 폴백** |

`0` 은 여전히 "seed 됐고 지원서가 없다" = **정상 0** 이다. null/0 구분은 강화됐다.

---

## 3. 식별자 계약 (1차)

| key | 형태 | 주의 |
|---|---|---|
| `toId` | 문서 id | — |
| `slotId` | `tos/{toId}/slots/{id}` | FLEX 만 존재 |
| **`wdId`** | 문서형 id | **slot 과 master 가 다른 값일 수 있다** ← 이번 root cause |
| `workDetailId` | legacy | wdId 없던 시절 |
| composite | `workType_start_end` | wdId 없을 때의 fallback identity |
| `canonicalId` | `wdId ?? composite` | **모든 stats/capacity 맵의 키** |
| business-date | KST 달력일 | DATE_ONLY / INSTANT / 업무 wall-clock 구분 (DEVICE.1F·1H.1) |

**같은 이름·시간만으로 identity 를 추정하지 않는다.** 서로 다른 공고가 같은
wdId 를 가질 가능성에 기대지 않는다(DEVICE.1H.1 에서 범위 count 를 toId 로 scope).

---

## 4. 숫자 계약 표 (이번 차수 확정분)

| 지표 | 단위 | 포함 | 제외 | 기준 | 권위 원천 | UNKNOWN |
|---|---|---|---|---|---|---|
| 지원(대기) | 관계 건수 | PENDING | — | 해당 날짜/업무 | 지원서 | 조회 실패 → ERROR |
| 확정 | 관계 건수 | CONFIRMED·CONTRACT_PENDING | — | 동일 | 지원서 | 동일 |
| 현재 충원 좌석 | 좌석 | 위 + `!isStaffingReleased` + `occupiesSeatOn` | 반납·종료된 장기 | 관측일 | `slot.workDetailCounts` / 지원서 집계 | null (거짓 0 금지) |
| 필요 자리 | 좌석 | 모든 업무 단위 | — | — | `workDetails[].requiredCount` | — |
| 부족 | 좌석 | **채울 수 있는** 단위만 | **종료 단위** | 관측일 | per-wdId Σ clamp | null |
| 공고·업무 수 | 개 | **본문이 그리는 그룹** | 종료 단위(지원 없으면) | 날짜 | `_cachedGroups` | 수 미표시 |
| Home 필요 | 좌석 | **종료 포함 전체** | — | 오늘 | CF `required` | ERROR 표면 |
| Home 부족 | 좌석 | 모집 가능분 | 종료 단위 | 오늘 | CF `shortage` | 동일 |

**모든 숫자가 같아야 한다고 가정하지 않는다.** `모집 마감 ≠ 공고 운영 종료 ≠
근로관계 종료 ≠ 좌석 반납 ≠ 근태 완료` 는 분리 유지. `지원=관심 / 확정=약속` 유지.

---

## 5. 검증 (이번 차수)

| 종류 | 내용 | 결과 |
|---|---|---|
| **DEV READ 대조** | `r7-staffing-identity-reconcile.js`, TO 93 · slot 172 | **mismatch 17건 식별**, 원장은 전부 정합 |
| **CODE 실행** | `staffing_identity_source_test.dart` (원장 사례 기반) | **9 PASS** |
| 변경 경로 회귀 | 63 파일 | **새 실패 0** (clean HEAD −5 / 현재 −5) |
| `flutter analyze` | | No issues |

앵커 4건(`w.id` seed literal ×3 · `to.workDetails` 폴백 ×1)은 **계약이 유지·강화**
되므로 새 계약을 표현하도록 다시 썼다.

---

## 6. 저장 불일치 / repair

**저장 mismatch 없음.** 17건은 전부 **reader 결함**이고 원장
(`slot.workDetailCounts` · `slot.confirmedCount` · 지원서)은 서로 일치했다.
→ **backfill·counter repair 불필요.** 실행하지 않았다.

단, `slot.wdId ≠ master.wdId` 라는 **구조적 사실**은 남는다. 이번에는 reader 를
정합하게 만들어 해소했고, 데이터 모델 통합(master 정의에 slot wdId 를 심는 등)은
**migration 이므로 별도 안이 필요하다** — 이번에 하지 않았다.

---

## 7. 상태 전이표 — **골격만 작성됨 (미완)**

이번 차수에서 원장 대조로 확인한 행만 적는다. 나머지는 §9 미검증.

| 전이 | writer | 원장 후상태 | counter/aggregate | 확인 |
|---|---|---|---|---|
| 관리자 확정 | `callableConfirmApplication` | `CONTRACT_PENDING`/`CONFIRMED` | `syncTOStats` → `slot.workDetailCounts[wdId]` | 원장 대조로 **정합 확인** |
| 좌석 반납(NO_SHOW 대체) | `staffingReleasedAt` writer | status 유지 | 좌석에서 제외 | 계약 확인, 전이 미실행 |
| 장기 종료(날짜) | 전이 없음 | status 그대로 | `occupiesSeatOn` 으로 제외 | DEVICE.1B/1C |
| 슬롯 마감 | `status=closed`/`closedBy` | — | 부족에서 제외 | DEVICE.1I |

---

## 8. 산출물 상태

| | |
|---|---|
| A 전체 lineage 다이어그램 | **부분** — FLEX 정의/집계 축만 |
| B entity/field/metric dictionary | **부분** — §3·§4 |
| C 전이표 | **골격** (§7) |
| D root cause register | **1건 완료** (§2) |
| E 코드 변경 | 완료 (§2 수정) |
| F 전이×소비자 검증표 | **미완** |
| G DEV READ 대조 | **완료** (§5·§6) |
| H 사용자 확인 묶음 | §9 |
| I canonical 기록 갱신 | 이 문서 + 감사표 |

---

## 9. 미검증 / CLOSED 금지 사유

- **Emulator 통합 검증 미실시.** 확정/취소/재시도/동시성(§9 matrix 1·3·4)을
  production callable·transaction 으로 실행하지 않았다. → `EMULATOR-INTEGRATION = 미실시`
- **writer 전수 감사 미완.** trigger 재실행·순서 역전·scheduled 재처리가 중복
  증감을 만드는지 코드로 확인하지 않았다(§5 항목 다수).
- **consumer matrix 미완.** 17 mismatch 자리 중 **어느 화면이 master 정의로
  조회하고 있었는지**를 화면별로 열거하지 않았다. 수정은 공통 owner
  (`resolveStats`/`loadTOWorkDetails`)에서 했으므로 그 경로를 지나는 소비자는
  함께 고쳐지지만, **화면별 실측은 남아 있다.**
- **DEVICE 없음.**

### 기존 closure 상태

- **유지:** DEVICE.1B/1C 좌석 규칙 · 1E.2A capacity authority/display ·
  1F 날짜(instant) · 1H.1 instant vs 성분 판정 · 1I 범위 projection
- **부분 취소:** DEVICE.1D/1E 의 **`to.workDetails` 무조건 폴백** — slot 맥락에서
  잘못된 identity 를 쓰게 만들었다. 폴백은 `slot == null` 로 좁혀 유지.
  DEVICE.1D 가 고친 장기 parity 는 그대로다(IDS-B1 이 고정).

## 10. 사용자 확인 (최소)

1. **`[R7FIX] 한 날짜만 마감`** — 날짜 **9/29** 선택 후 상세가 **`충원 1 · 0 미충원`**
   / `1/1` 인지, 상단과 같은지
2. 같은 카드에서 **9/30** 선택 시 `충원 0 / 필요 1 · 부족 1`
3. `[R7FIX] 부족 남은 공고` **9/26·9/28** 선택 시 각각 `충원 1`

그 외는 개발 검증으로 대체했다.
