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

---

# 2차 실행 (§2 안전성 · §4 Emulator 시도)

## 2-1. §2A identity 계약 — 상태별 authoritative definition

`TOItem.statsAlignedWorkDetails` caller: `resolveStats` · `_aggregateUsable`
(`hasLoadedStats` 경유). 그 외 lib 내 caller 없음.

| 상태 | 권위 정의 | 집계 | 결과 | 고정 |
|---|---|---|---|---|
| slot + 정의 로드 성공 | `TOItem.workDetails` (= slot 정의) | canonical 키 | **known** | IDS-E1 |
| slot + 정의 미로드 | 없음 (`[]`) | `null` (둘은 `setWorkDetails` 가 함께 세운다) | 카운터, provenance false | IDS-E2 |
| **정의가 로드되면** | slot 정의 | canonical | **known 으로 회복** | **IDS-E3** |
| slot + slot 정의 문서에 없음 | loader 가 master 로 정의·seed 를 **함께** 만든다 → identity 일치 | master canonical | known | IDS-E4 |
| 정의 조회 실패 | — | flag | 카운터, provenance false | IDS-E5 |
| slot 없음(장기) | `to.workDetails` | master canonical | known | IDS-E6 |

**영구 UNKNOWN 없음** — `setWorkDetails` 가 정의와 집계를 한 호출에서 함께
세우므로 identity 가 어긋날 수 없고, 로드되면 known 으로 돌아온다(IDS-E3).
`slot 존재`만으로 loaded 를 가정하지 않는다(IDS-E2).

같은 type/time 이지만 다른 `wdId` 는 **다른 업무**다 — composite 폴백이 A 의 값을
B 에 주지 않는다(IDS-E7). 정의의 `requiredCount` 와 집계의 `confirmed` 가 같은
identity 에서 온다(IDS-E8).

## 2-2. §2C counter fallback source — 그리고 **2차에서 찾은 결함**

| source | 범위 | 의미 | writer | 실패/권한 시 |
|---|---|---|---|---|
| `TOItem.confirmedCount` | **그 slot** | 현재 좌석 | `syncTOStats` → `slot.confirmedCount` | 사용(같은 범위) |
| `TOItem.pendingCount` | 그 slot | 관계(대기) | 동일 | 사용 |
| `TOItem.totalRequired` | 그 slot | 필요 자리 | slot 문서 | 사용 |

폴백은 **같은 slot 범위**이므로 §2C 의 "같은 범위의 유효 counter" 조건을
만족한다. 부모 합계를 자식마다 복제하지 않고, 장기 누적확정을 현재 좌석으로
쓰지 않는다(`occupiesSeatOn` 은 집계 쪽 계약).

### ⚠ 2차에서 찾은 결함 — provenance 가 거짓이 될 수 있었다

1차 수정은 `resolveStats` 를 "업무 하나라도 miss → 카운터 폴백" 으로 바꿨는데
`hasLoadedStats` 는 그 조건을 몰랐다. 그래서 **실제로는 카운터를 말하면서
화면에는 "집계에서 나온 값" 이라고 보고**할 수 있었다.
→ 판정을 `_aggregateUsable` 한 곳으로 모아 두 소비자가 같은 것을 쓰게 했다.
(§2C: summary 가 counter 로 알려진 것이 child 별 분배의 증거는 아니다)
고정: IDS-C1 (부분 miss → `hasLoadedStats == false`).

## 2-3. §4 Emulator 통합 — **시도했고 막혔다 (필요조건 명시)**

| | |
|---|---|
| `firebase.json` | `emulators` 에 **`functions` 항목 없음** (firestore 6060 / storage 6061만) |
| 시도 | `firebase emulators:start --only functions,firestore --project alfit-89567` |
| 결과 | **emulator 는 떴다** — Functions `127.0.0.1:5001`, Firestore `127.0.0.1:6060` |
| 오염 방지 | Admin SDK 를 `FIRESTORE_EMULATOR_HOST` 로 고정 + **emulator 가 비어 있음을 확인한 뒤에만 write**. seed·read 성공 |
| **막힌 지점** | 모든 함수가 로드 실패: `Your function was killed because it raised an unhandled error` → `Failed to load function` (`callableApplyToTO` 포함) |
| 원인 판정 | `node -e "require('./lib/index.js')"` 는 **`load OK`** — 프로젝트 코드는 정상. CLI 런타임이 v7 에서 제거된 `functions.config()` 를 호출한다는 경고와 함께 죽는다 → **firebase-tools 14.20.0 ↔ firebase-functions 7.3.2 런타임 비호환** |
| 필요조건 | 두 버전 중 하나를 맞춰야 한다. **배포 런타임에 영향을 주는 변경이므로 이 감사에서 하지 않았다** — 별도 승인이 필요하다 |

→ **EMULATOR-INTEGRATION = 미달성.** §9 matrix 의 전이 실행(확정/취소/재시도/
동시성/trigger 재실행)은 여전히 **미검증**이다. fake server 결과로 대체하지 않았다.

## 2-4. §5 클릭 1→0 — **PARTIAL**

`TOItem` 수준의 전이(미로드 → 로드 → known 회복)는 실행으로 고정했다(IDS-E2/E3).
**날짜 전환(9/29→9/30→9/29)·dialog 열고닫기·탭 재진입은 실행하지 못했다** —
그 경로의 상태는 `_AdminTOGroupCardState._updateGroupCache` / `WorkforceController`
안에 있고 Firebase provider 에 의존한다. 필요한 최소 seam(그룹 캐시 계산을
값 입력 순수 함수로 분리)은 **제안만** 하고 이번에 만들지 않았다.

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

---

# 3차 — 실행환경 복구 및 write-path 실제 실행 (2026-09-27)

## 11. 환경 BLOCKER — ROOT CAUSE 확정 및 해소

2차에서 "모든 function 이 `Failed to load function`" 으로 멈췄다. 그때는 원인을
특정하지 못한 채 `require('./lib/index.js') 성공` 만 가지고 있었다. 그것은 import
context 성공일 뿐이라는 지적이 맞았다. 이번에 **호출자·피호출자·버전**을 모두 짚었다.

### 11-1. 첫 번째 실패 — functions.config()

| 항목 | 값 |
|---|---|
| 호출자 | `firebase-tools@14.20.0` → `lib/emulator/functionsEmulatorRuntime.js:455,458` |
| 호출 | `localFunctionsModule.config()` (가드 없음, `initializeFunctionsConfigHelper` 에서 무조건 실행) |
| 피호출자 | `firebase-functions@7.3.2` → `lib/v1/config.js:10` |
| 스택 | `Error: functions.config() has been removed in firebase-functions v7.` |

즉 **제품 코드가 아니라 CLI 런타임**이 제거된 API 를 부른다. 프로젝트의
`functions/lib/index.js` 에 있던 `functions:config` 문자열은 원인이 아니었다.

**해소:** `firebase-tools@15.31.0` 에서 `initializeFunctionsConfigHelper` 자체가
제거되었다. 전역 CLI 를 바꾸지 않고, 격리 디렉터리에 **exact version 고정**으로
설치해 사용한다(`@latest` 미사용).

### 11-2. 두 번째 실패 — admin.firestore statics 손실

| 항목 | 값 |
|---|---|
| 증상 | 모든 callable 이 `INTERNAL`. 런타임 스택: `TypeError: Cannot read properties of undefined (reading 'fromMillis')` at `functions/lib/index.js:30069` |
| 원인 | CLI `Proxied.getOriginal` 이 `value.bind(target)` 을 반환 → 함수의 own property 소실 |
| 확인 | `admin.firestore` 는 `prototype` 없음 → `isConstructor` false → bind 분기. 원본 `admin.firestore.Timestamp` = function, `.bind()` 후 `undefined` |

**CODE ≠ INFRA.** 제품의 `admin.firestore.Timestamp.fromMillis` 는 운영에서 정상이고,
같은 표현이 하네스 프로세스(비-에뮬레이터)에서도 정상 동작한다. 깨지는 곳은
에뮬레이터 런타임뿐이다.

**해소:** **격리 CLI 사본에만** `getOriginal` 이 bind 후 own property 를 복원하도록
수선했다(`node_modules/firebase-tools/.../functionsEmulatorRuntime.js`, 원본은 `.r7bak`).
이것은 호환을 가장하는 monkey patch 가 아니라 **운영과 동일한 원본 동작의 복원**이다.
제품 코드·배포 SDK·lockfile·engines·전역 CLI 는 건드리지 않았다.

### 11-3. 격리 증거

- 프로젝트: `demo-alfit-r7` — CLI 자체 출력:
  *"Detected demo project ID … attempts to access non-emulated services for this project will fail."*
- 엔드포인트: functions `127.0.0.1:5011` / firestore `6070` / storage `6071` / auth `6072` / hub `4410`
- **자격증명 부재 확인:** `GOOGLE_APPLICATION_CREDENTIALS` 미설정, gcloud ADC 파일 없음,
  `src/index.ts` 에 하드코딩 bucket 없음, `defineSecret` 0건
  → FCM 등 외부 Google API 는 **인증 실패로 전달 불가**. (빈 데이터가 아니라 자격증명 경로로 증명)
- **실자격증명 차단:** `functions/.env.demo-alfit-r7` 로 `.env` 6개 키를 전부 dummy 로 덮었다.
  CLI 로그가 로드 순서를 확인해 준다: `Loaded environment variables from functions\.env, functions\.env.demo-alfit-r7`
- 설정 분리: `firebase.r7audit.json` (별도 config, predeploy 없음). 기존 `firebase.json` 미수정.

### 11-4. discovery ≠ invocation

| 구분 | 증거 |
|---|---|
| discovery | `All emulators ready`, **241 functions initialized, `Failed to load function` 0건** |
| invocation | 인증 없이 `callableApplyToTO` 호출 → `401 {"status":"UNAUTHENTICATED"}` — 로드 실패가 아니라 **제품의 auth guard 가 실행된 결과** |
| 실제 트랜잭션 | 아래 §13 전이 매트릭스 |

## 12. §3A — count 소비자 인벤토리 (1차 결과)

집계 provenance 는 `_aggregateUsable` 로 닫았지만, **개별 업무 단위 소비자**는
별도 축이다. 같은 identity miss 를 서버와 클라이언트가 반대로 처리한다.

**서버:** `getWorkDetailCount(slotData, wd)` — `wdId` 는 있는데 `workDetailCounts`
항목이 없으면 **fail-closed** 로 `failed-precondition` throw.
주석이 이유를 명시한다: *"fail-open(0/0)은 '정원 여유 있음'으로 오판 → 정원 초과 지원 허용하는 보안 버그."*

**클라이언트:** 같은 miss 를 `?? 0` 으로 접는 자리가 남아 있다.

| # | 위치 | 표면 | miss 시 동작 | 판정 |
|---|---|---|---|---|
| C1 | `admin_to_group_card.dart:1144` | 업무 행 | `statsFailed: … \|\| stats == null` | **정상** — miss 를 실패로 표기 |
| C2 | `admin_to_item_card.dart:384` | 업무 행 | 동일 | **정상** |
| C3 | `work_detail_management_dialog.dart:76,87,121` | **업무별 마감 관리** | `confirmed = 0` → `_getWorkStatus` 로 상태 판정·선택 그룹핑 | **결함** — 미표기 fail-open, action 표면 |
| C4 | `job_posting_screen.dart:1316,1330` | **지원자 공고 상세** | `hasWorkStats = workDetailStats != null` (map 존재만) → `잔여 N명` | **결함** — provenance 를 identity hit 이 아닌 map 존재로 판단 |
| C5 | `work_applicants_dialog.dart:2948` | 개별 승인 전 인원 체크 | `confirmed 0` → `remaining = required` | **결함** — fail-open (서버가 최종 차단) |
| C6 | `work_applicants_dialog.dart:3394` | 일괄 승인 한도 | 동일 + `현재 0명 확정` 문구 | **결함** |
| C7 | `work_applicants_dialog.dart:1287` | 초대 다이얼로그 인자 | `_canonicalConfirmed ?? 0`, `workDetailId: work.id`(canonicalId 아님) | **결함 후보** — canonical gate 를 경계에서 되접음 |

C5~C7 은 같은 다이얼로그 안에서 **한쪽은 canonical gate(`confirmedFor`, miss 시 null),
다른 쪽은 `?? 0`** 을 쓴다. 1E.2A 가 만든 규칙이 일부 경로에만 적용돼 있다.

> C4 의 실제 노출 조건(master identity 로 렌더되는 경로인지)은 아직 실행으로
> 확인하지 않았다 — **NOT TESTED**. 코드 경로상 후보로만 기록한다.

## 13. §5 — 전이 매트릭스 (격리 에뮬레이터, production callable 실행)

하네스: `scripts/r7-emu-transition-matrix.js` (커밋하지 않음).
fixture: TO `r7to` / slot `r7slot` / `wdId = wd-canonical-001` / required 2.

| 단계 | 호출 | 응답 | 카운터(slot.workDetailCounts) | TO 합계 | 원장(applications) |
|---|---|---|---|---|---|
| T0 | (seed) | — | c0 / p0 | 0 / 0 / req 2 | — |
| T1 | `callableApplyToTO` | **200** | c0 / **p1** | 0 / **1** / 2 | **PENDING 1** |
| T2 | 동일 조건 재지원 | **409 ALREADY_EXISTS** | c0 / p1 (불변) | 0 / 1 / 2 | PENDING 1 (불변) |
| T3 | `callableConfirmApplication` | **200** | **c1** / p0 | **1** / 0 / 2 | **CONTRACT_PENDING 1** |
| T4 | `callableCancelConfirmedApplication` | **200** | c0 / p0 | 0 / 0 / 2 | **CANCELED 1** |

**확인된 사실 (VERIFIED — 실행):**
1. 네 단계 모두에서 **원장·카운터·TO 합계가 일치**한다. 저장 mismatch 없음.
2. **중복지원이 카운터를 올리지 않는다** — 거부와 카운터 불변이 함께 성립.
3. 확정 직후 status 는 `CONFIRMED` 가 아니라 **`CONTRACT_PENDING`** 이고,
   그 시점에 좌석 카운터가 `confirmedCount` 로 올라간다. 클라이언트의
   좌석 판정(`occupiesSeatOn` 이 CONTRACT_PENDING 을 좌석으로 셈)과 **일치**한다.
   이것은 이제 추론이 아니라 실행 결과다.
4. 확정취소는 `confirmedCount` 에서 내려오고 `pendingCount` 로 되돌아가지 않는다.
5. applicationId = `r7to_r7slot_wd-canonical-001_r7worker001` —
   complexId 의 3번째 segment 는 **workType 이 아니라 wdId** 다.
   (CLAUDE.md 의 `{toId}_{slotId}_{workType}_{uid}` 설명은 8.1E 이전 표기다.)

**아직 실행하지 않은 전이 (NOT TESTED):** 지원취소(worker), 재지원, 초대,
자동취소(겹침), 응답 유실, 동시성, trigger 재실행, 마감/재개.

## 14. 이번 차수에서 하지 않은 것

- 제품 코드 변경 **0건**. §12 의 C3~C7 은 **발견까지**이고 수정은 하지 않았다.
- shared DEV 는 이번 차수에 **쓰지 않았다**(읽기도 없음). 모든 write 는 `demo-alfit-r7`.
- §3B(writer 전수·전이표), §3C(그룹 캐시/WorkforceController seam) **미착수**.
- 감사는 **OPEN** 이다.

---

# 4차 — C3~C7 수정, writer 인벤토리, 전이 매트릭스 확장 (2026-09-27)

## 15. 3차 보고의 정정

증거를 다시 따라가 보니 내가 3차에 적은 것 중 두 가지가 틀렸다.

| # | 3차 서술 | 실제 | 근거 |
|---|---|---|---|
| 15-1 | C4 가 **지원자 공고 상세**에 잘못된 `잔여 N명` 을 낸다 | **아니다.** `workDetailStats` 를 넘기는 곳은 `admin_to_group_card`(3) 와 `admin_to_item_card`(1) 뿐이고 **전부 `adminPreview`** 다. 지원자 진입점(`user_to_card` 3곳, `my_applications`, `user_home`, `apply_work_dialog`, `notification_screen`, `fcm_service`)은 모두 `workDetailStats` 를 넘기지 않아 `잔여` 가 렌더되지 않는다 | 호출부 전수 grep |
| 15-2 | `functions/.env` 6개 키를 전부 dummy 로 덮었다 | **7개**였고 `GMAIL_USER` 가 덮이지 않은 채 실행되고 있었다 | `verify-env-isolation.js` 가 잡아냄. 이번에 막음 |

**complexId 표기 정정** (3차의 내 서술도 부정확했다):

- `discriminator` = 클라이언트가 보낸 `workDetailId`, 없으면 `selectedWorkType`
- `complexId` = slotId 있으면 `{toId}_{slotId}_{discriminator}_{uid}`, 없으면 `{toId}_{discriminator}_{uid}`
- `canonicalNewId` = (slotId && resolvedWdId) 이면 `{toId}_{slotId}_{resolvedWdId}_{uid}`, 아니면 complexId
- 최종 `applyDocId` = 관계로 찾은 기존 문서의 id → 없으면 legacy complexId 문서가 있으면 그것 → 없으면 canonicalNewId

즉 3번째 segment 는 "항상 workType"(CLAUDE.md 의 옛 표기)도 "항상 wdId"(3차의 내 말)도
아니다. **클라이언트가 보낸 `workDetailId`, 없으면 `workType`** 이고, 새 문서는 서버가
역산한 `resolvedWdId` 를 쓴다.

> **migration 하지 않는다.** CF 주석이 명시한다 — "application docId를 파싱하는
> 소비자는 없다 — 전수 확인". id 는 아무도 읽지 않는 식별자이므로 형식 통일의 이득이
> 없고, 알림·계약·근태가 참조하는 id 를 바꾸는 위험만 남는다.

## 16. §4 — C3~C7 판정과 수정

| # | 위치 | 실제 actor / scope | identity 원천 | 미확인 조건 | 수정 전 | 수정 후 | 실행 증거 |
|---|---|---|---|---|---|---|---|
| C3 | `work_detail_management_dialog:76,87,121` | 관리자 · 업무별 마감 관리(**action**) | `toItem.workDetailStats` | statsFailed / map null / **identity miss** | `confirmed = 0` → `진행중` 라벨 + `N개 마감` 버튼 | `_WDS.unknown` → `확인 필요` 라벨 · `정원 확인 필요` 버튼 + 복구 안내. 마감·재오픈 미개방 | WCR-C(2), 판독기 A-1~A-9 |
| C4 | `job_posting_screen:1316,1330` | 관리자 **미리보기** (지원자 아님 — §15-1) | `widget.workDetailStats` | 위와 같음 | `hasWorkStats = map != null` → `잔여 = required - 0` | `WorkCapacityReading` · `remaining` 이 null 이면 잔여 미표시 | WCR-C, `cross_surface` 10-a/10-c/10-d/10-e |
| C4b | `admin_to_group_card:2169` | 관리자 · 미리보기 진입 | **master 정의 + slot stats 를 짝지음** | 정의가 비어 master 로 폴백할 때 | 두 identity 원천을 짝지어 조회가 반드시 빗나감 | master 로 떨어지면 stats 를 붙이지 않는다(null) | WCR-C |
| C5 | `work_applicants_dialog:2948` | 관리자 · 단건 승인(**action**) | 같은 map, `?? 0` | 위와 같음 | `remaining = required` → fail-open | 공통 관문 `capacityBlockReason` | WCR-B(6) |
| C6 | `work_applicants_dialog:3394` | 관리자 · 일괄 승인(**action**) | 같은 map, `?? 0` | 위와 같음 | fail-open + `현재 0명 확정` 문구 | 같은 관문 | WCR-B |
| C7 | `work_applicants_dialog:1287` → `available_workers_bottom_sheet` | 관리자 · 근무 가능 인력(**초대**) | `_canonicalConfirmed ?? 0` | canonical 아님 / miss | `정원 2명 · 확정 0명 · 부족 2명` | `confirmedCount` 를 `int?` 로. 모르면 `확정 인원 확인 불가` | WCR-C |
| C7b | 같은 자리 `workDetailId: work.id` | — | — | — | — | **바꾸지 않았다** | 아래 |

**C7b — 결함이 아니다(증명).** 서버 `callableGetAvailableWorkers` 는 `workDetailId` 를
composite(`workType_startTime_endTime`) 또는 workType 과 비교해 맞춘 뒤 거기서
`targetWdId` 를 역산한다. 즉 composite 를 기대한다. `canonicalId`(wdId) 를 넘겼다면
매칭에 실패하고 **첫 번째 workDetail 로 폴백**했을 것이다 — 지금 값이 맞는 값이다.
`work.id` 를 기계적으로 `canonicalId` 로 바꾸지 않는다.

**공통 owner:** `lib/models/ui/work_capacity_reading.dart`.
새 상태 엔진이 아니라 기존 `WorkDetailData.lookupByIdentity` 위의 얇은 판정이다.
전환한 caller 에서 옛 `?? 0` · `map != null` 판정은 제거했다(테스트가 재등장을 막는다).
**합법적인 표시 0 은 남는다** — canonical 0 은 `isKnown: true, confirmed: 0` 이다(A-1).

**검증:** 21개(`work_capacity_unknown_contract_test.dart`) + `cross_surface` 재작성 4개.
`lib/` 를 HEAD 로 되돌리면 그중 **6개가 실패**한다 — 수정이 없으면 깨지고 있으면
통과하는 before/after 증거다. 전체 스위트에서 **새로 깨진 것 0건**(기존 실패 63건은 그대로).

## 17. §3B — writer 인벤토리

`scripts/r7-writer-inventory.js` (정적 분석, 에뮬레이터 불필요) 기준 **32개**.

| owner | 종류 | 원자성 | 대상 |
|---|---|---|---|
| `callableConfirmApplication` | callable | transaction+batch | wdCounts(6) · totalPending(5) · totalConfirmed(5) |
| `callableApproveApplicationForReview` | callable | transaction | wdCounts(2) · totalPending(4) · totalConfirmed(2) |
| `syncTOStats` | **trigger** | transaction+batch | totalRequired(3) · totalConfirmed(2) · totalPending(2) |
| `callableReleaseNoshowSeat` · `callableBatchCancelNoShow` · `callableAcceptTOInvitation` | callable | transaction(+batch) | 세 대상 모두 |
| `callableApplyToTO` · `callableAcceptInvitation` · `callableInviteWorker` · `callableOfferAlternativeWork` | callable | transaction | wdCounts(1) · totalPending(1) |
| `callableCloseSlots` · `callableDeclineTOInvitation` · `callableDeleteAccountApplications` · `callableExpireApplications` · `callableRecalculateTOStats` · `callableCreateFlexSlots` | callable | **batch** | 혼합 |
| `callableRecalcToTotalRequired` | callable | **single-write** | totalRequired(1) |

**CF 밖의 writer — 클라이언트 직접 write 1개 (정적 인벤토리에 잡히지 않는 경로):**
`ApplicationFirestore.cancelApplication` (근로자 본인 지원취소, PENDING 한정).
클라이언트 transaction 이 `applications.status='CANCELED'` + `tos.totalPending -1`
+ `slot.pendingCount -1` 을 원자적으로 쓴다. **`workDetailCounts` 는 쓰지 않는다.**

## 18. §5·§6 — 전이 매트릭스 2단계 (실행)

1차 T1~T4 는 기준점으로 재사용. 정착 판정은 **고정 sleep 이 아니라 수렴 관측**이다
(`settle()`: 값이 연속 4회 동일해야 정착, 아니면 `settled:false` 로 남긴다).

| 단계 | 원장 | slot.pendingCount | **workDetailCounts.pending** | to.totalPending | 정착 |
|---|---|---|---|---|---|
| T5-b 지원 | PENDING 1 | 1 | 1 | 1 | — |
| T5-c 지원취소 직후(트리거 전) | CANCELED 1 | 0 | **1** | 0 | — |
| T5-d 지원취소 정착 | CANCELED 1 | 0 | **1 (남음)** | 0 | 1.76s · 5샘플 |
| T6-b 재지원 정착 | PENDING 1 | 1 | **2 (누적)** | 1 | 1.75s · 5샘플 |
| T7-b 확정 정착 | CONTRACT_PENDING 1 | 0 | **1 (여전히 어긋남)** | 0 | 1.73s · 5샘플 |

### 18-1. ROOT CAUSE — `workDetailCounts` 에는 보정자가 없다

`syncTOStats` → `_syncTOCounters` 가 쓰는 것은 정확히 이것뿐이다:
`toRef.update({totalConfirmed, totalPending, statsUpdatedAt})`,
`slotRef.update({confirmedCount, pendingCount})`, 그리고 slot status 교정.

**`workDetailCounts` 는 재계산하지 않는다.** 그래서 그 필드를 명시적으로 쓰지 않는
경로(= 위 클라이언트 지원취소)가 지나가면 그 차이가 **영구히 남고, 취소→재지원마다
누적된다.** 상위 카운터(`slot.pendingCount`, `to.totalPending`)는 트리거가 스스로
낫게 하므로, 겉보기에는 정상인 채로 업무 단위 값만 어긋난다.

유일한 보정 경로는 **수동** `callableRecalculateTOStats` 다 — 자동이 아니다.

### 18-2. 현재 영향 범위 (과장하지 않는다)

- 입증된 drift 는 **`pendingCount`** 다. `countForDetail` 의 클라이언트 소비자는 없고,
  `isWorkDetailFull` 은 `confirmedCount` 만 본다 → **지금 UI 숫자에 도달하지 않는다.**
- 서버 정원 게이트(`getWorkDetailCount`)도 `confirmedCount` 만 본다 → 지원 차단에 영향 없음.
- `confirmedCount` 에 같은 일이 생기려면 **좌석 상태를 CF 밖에서 바꾸는 경로**가 있어야 한다.
  클라이언트 취소는 PENDING 한정이므로 그 경로는 아직 찾지 못했다 — **NOT TESTED / 미확정**.
- 따라서 이것은 **저장 불변식 위반이며, 현재 확인된 사용자 노출은 없다.** 둘 다 사실이다.

### 18-3. 부수 관측 — `onBusinessDeleted`

harness cleanup 이 사업장·사용자를 같이 지우자 `onBusinessDeleted` 가
`5 NOT_FOUND: no entity to update` (`type: "users"`) 로 **unhandled error** 를 내고 죽었다
(cascade 중단). 내 삭제 순서가 만든 상황이지만, **존재 확인 없이 `.update()`** 한다는
사실 자체는 남는다. 탈퇴한 사용자가 있는 사업장을 삭제할 때 같은 일이 가능하다.
**후보이며 제품 시나리오로 재현하지는 않았다.**

## 19. §3 — 외부 부작용 격리 (확인한 것과 못 한 것)

| 항목 | 상태 |
|---|---|
| demo 프로젝트 차단 | CLI 자체 출력으로 확인 |
| ADC 없음 / 하드코딩 bucket 없음 / `defineSecret` 0건 | 확인 |
| `.env` **7개 키 전부** 감사 전용 값으로 override | `verify-env-isolation.js`, 값 미노출 |
| 알림이 실제로 나가지 않음 | 제품 코드가 `FCM 토큰 없음` 에서 멈춤 — `sendEachForMulticast` 미도달 |
| 전송 실패가 commit 을 잘못 실패시키는가 | **구조적으로 불가** — 전송은 callable 이 아니라 `onNotificationCreated` **트리거**에서 일어난다(별도 실행). 확정 callable 은 200 + 원장 commit |
| 전송 경로 자체를 실패시켜 끝까지 관측 | **NOT TESTED** — 토큰을 주입했으나 해당 알림 수신자가 달라 경로에 닿지 못했다 |
| Firestore **rules** | **NOT TESTED** — harness 는 Admin SDK 라 rules 를 지나지 않는다. 클라이언트 경로 재현은 **write set 만** 같다 |

## 20. §3C — 그룹 갱신 seam (실행)

`WorkforceController.refreshGroup` 을 **실제 controller 로** 돌렸다.
서버 읽기 두 곳(`_readTO`/`_readSlots`)만 주입 가능하게 하고 나머지는 production 코드다.
`_service` 를 lazy 로 바꿔 주입 시 Firebase 없이 세워진다. 순수 helper 단독 테스트가 아니다.

확인(12건, `workforce_group_refresh_seam_test.dart`):
빠른 연속 갱신에서 **응답 역전** 시 늦게 온 쪽 `superseded` + 화면 값이 과거로 안 돌아감 ·
읽기 실패가 목록을 지우지 않음 · 실패→재시도 성공 · 예외도 실패로 · **부재 vs 실패 구분**
(`removed` vs `failed`) · dispose 후 무기록 · 목록 밖은 읽지도 단정하지도 않음 ·
목록 **새 인스턴스** 교체(뷰 필터 캐시 무효화) · 실패 시 미통지 · flex 만 슬롯 재조회.

**미검증:** 날짜 타일 선택 → 일자별 다이얼로그의 `_cachedGroups` 왕복(사용자 재현
`9/29 → 9/30 → 9/29 → 닫기 → 탭 복귀`)은 `day_applicants_dialog` 의 private State 이고
Firebase 에 직접 붙는다. 이번 seam 은 controller 경로만 덮는다 — **NOT TESTED**.

## 21. 이번 차수 상태

- 제품 코드 수정: C3·C4·C4b·C5·C6·C7 + controller seam.
- 환경/재현 산출물: `scripts/r7-audit/`, harness, audit config, CLI patch.
- shared DEV write **0** · PROD 접근 **0** · 외부 발송 **0** · 저장 migration **0**.
- **OPEN.** 남은 것: §18-1 보정자 부재의 수리 방침(사용자 결정 필요), `confirmedCount`
  drift 경로 존재 여부, rules 경로, 초대/자동취소/동시성/trigger replay 전이,
  일자별 다이얼로그 캐시 왕복, `onBusinessDeleted` 후보.
