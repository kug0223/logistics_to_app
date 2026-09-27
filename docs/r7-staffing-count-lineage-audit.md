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

---

# 5차 — 업무별 카운터 무결성 복구 (2026-09-27)

## 22. 4차 커밋 SHA (§0)

| SHA | 구분 | 내용 |
|---|---|---|
| `4ec5a10` | CODE | C3~C7 소비자 수정 + `WorkCapacityReading` |
| `c55b025` | TOOLING | `scripts/r7-audit/`, harness, audit config, CLI patch |
| `7fd8313` | SEAM/TEST | `WorkforceController` 읽기 주입 + 전이 12건 |
| `adb6cbb` | DOCS | 3차 정정 + CLAUDE.md complexId |

5차 시작 시 HEAD `adb6cbb`, tracked 변경 없음(이전 phase 의 untracked 스크립트만 잔존).

## 23. §2 — 수리 방침을 근거로 선택했다

추상적 양자택일로 넘기지 않고 writer 구조를 먼저 읽었다. 결정적 사실:

**`callableIncrementSlotPending` 이 이미 정확히 그 일을 한다.**
`totalPending` · `slot.pendingCount` · `workDetailCounts[wdId].pendingCount` 를
한 transaction 에서 함께 쓰고, 지원서 문서의 `pendingIncrementedAt` /
`pendingDecrementedAt` 로 멱등하고, 음수 가드와 new-schema wdId fail-closed 까지 있다.

**그런데 앱 어디에서도 호출하지 않았다.** 전수 확인 결과 주석만 다섯 곳에 있었다.
클라이언트 취소 코드 자신이 경고까지 적어 두었다 — *"CF 호출 코드가 추가되면
`_incrementTOPending` 의 totalPending/pendingCount 업데이트를 반드시 제거해야 한다.
제거 없이 CF까지 호출하면 … 이중 카운트 버그 발생."*

| 안 | 판정 | 근거 |
|---|---|---|
| **A. 권위 server command 가 원장+집계를 원자적으로** | **선택** | 이미 존재·멱등·음수가드·fail-closed. 새 command·정책·모델 변경 0. |
| B. sync owner 가 파생 집계 전체를 재계산 | 부분 채택 | `_syncTOCounters` 에 `workDetailCounts` 를 넣으면 모든 writer 를 덮지만, 상태 변경마다 슬롯 전량 재계산이 붙는다. **드문 경로(확정 롤백)에만** 기존 `callableRecalculateTOStats` 로 채택. |
| C. 즉시 일관성 + 비동기 복구 | 결과적으로 성립 | command 가 즉시 세 값을 맞추고, 실패 시 `syncTOStats` 가 상위 두 값을 원장에서 다시 센다. 업무 단위만 남고 같은 호출 재시도로 복구(멱등). 역할이 겹쳐 이중 증감하지 않는다 — command 는 delta, trigger 는 절대 재계산이고 command 의 음수 가드가 순서 역전을 흡수한다. |

## 24. §3 — 세 겹의 원인과 event timeline

### 24-1. 불변식 정의

| 값 | 포함 status | 범위 | identity |
|---|---|---|---|
| `slot.workDetailCounts[wdId].pendingCount` | `PENDING` | 슬롯 × 업무정의 | `wdId`(slot 의 것) |
| `slot.workDetailCounts[wdId].confirmedCount` | `CONFIRMED`, `CONTRACT_PENDING` | 슬롯 × 업무정의 | 같음 |
| `slot.pendingCount` / `confirmedCount` | 같음 | 슬롯 전체 | — |
| `to.totalPending` / `totalConfirmed` | 같음 | 공고 전체 | — |

합계 관계는 **범위가 같을 때만** 정의된다. 장기(슬롯 없음) 공고는 슬롯 축이 없어
업무 단위 카운터를 쓰지 않는다 — 누계와 혼동하지 않는다.

### 24-2. 지원취소 event timeline (수리 전)

```
t0  클라이언트 transaction
      applications.status = CANCELED
      tos.totalPending      -1        ← rules 가 ±1 허용
      slot.pendingCount     -1        ← rules 가 ±1 허용
      slot.workDetailCounts  손대지 못함 ← rules 403 (실측)
t1  syncTOStats 트리거
      totalPending / slot.pendingCount / slot.confirmedCount 를 원장에서 재계산
      workDetailCounts 는 재계산 대상이 아니다
결과  원장 0 · 상위 카운터 0 · **업무 단위 1**  (영구)
재지원 반복 → 1, 2, 3 … 누적 (실측)
```

### 24-3. 세 겹

1. **호출이 없다.** 담당한다던 command 를 아무도 부르지 않았다.
2. **불러도 걸린다.** command 의 슬롯 합계 zero-guard 가 `return` 이라,
   클라이언트가 이미 슬롯 합계를 0 으로 내린 뒤면 업무 단위와 TO 합계까지
   한 번도 손대지 못한 채 멱등 플래그만 찍고 끝났다. **세 값은 범위가 다르다.**
3. **두 번째 주기부터 다시 걸린다.** 멱등 플래그를 지우지 않는데 재지원은
   **같은 문서를 되살린다**. 가드가 문서 수명에 걸려 있었다.

### 24-4. 수리

| 지점 | 변경 |
|---|---|
| `callableIncrementSlotPending` | 음수 방지를 **각 카운터가 자기 값으로**. 읽기를 쓰기 앞으로 모아 TO 합계도 자기 값으로 판단. |
| `callableApplyToTO` 재활성화 | `pendingIncrementedAt`/`pendingDecrementedAt` 를 `FieldValue.delete()`. 가드가 **이번 전이 한 번**에 걸린다. |
| `ApplicationFirestore.cancelApplication` | 원장만 바꾸고 그 command 를 호출. 실패는 취소 실패로 말하지 않는다. |
| `ApplicationFirestore.updateApplicationStatus` | 클라이언트 낙관적 증감 제거 → `callableRecalculateTOStats`. |
| 제거 | `_incrementTOPending` · `_incrementTOConfirmed` · `_decrementTOConfirmed` (절반만 맞는 상태를 만들던 helper) |

### 24-5. `confirmedCount` drift — 검색으로 닫지 않았다

호출부를 전수로 열어 확인했다. `updateApplicationStatus` 의 직접 write 분기가
좌석 상태를 바꾸는데 `workDetailCounts` 를 쓸 수 없었다(rules 403, 실측).
live 호출부를 12곳 열어 보니 대부분 `confirmed`/`rejected`(→ CF)였고,
**`work_applicants_dialog.dart:3590` 하나가 `pending` 을 넘긴다** —
계약서 생성 실패 시 `CONTRACT_PENDING → PENDING` 롤백이다. 드물지만 live 다.
→ 재집계 command 로 닫았고, 에뮬레이터에서 확인했다(S7).

## 25. §4 — rules 경로 (실측 11건)

Admin SDK 는 rules 를 우회하므로 **ID 토큰 + Firestore REST** 로 직접 쳤다.

| # | 시도 | 결과 |
|---|---|---|
| R1 | 본인 지원서 `PENDING → CANCELED` | **허용** |
| R2 | 타인 지원서 상태 변경 | 거부 |
| R3 / R3b | 본인 스스로 `CONFIRMED` / `CONTRACT_PENDING` 승격 | 거부 |
| R4 | `slot.workDetailCounts` 직접 쓰기 | **거부** |
| R5 / R5b | `slot.pendingCount` −1 / 임의값 | 허용 / 거부 |
| R6 / R6b | `slot.confirmedCount` / `to.totalConfirmed` | 거부 / 거부 |
| R7 / R7b | `to.totalPending` −1 / 임의값 | 허용 / 거부 |
| R8 | 사업장 문서 변경 | 거부 |

**원장 상태 쓰기 권한과 파생 counter 쓰기 권한이 분리되어 있다.**
새 취소 경로는 ±1 허용을 **더 쓰지 않는다** — 그 허용을 좁히는 것은
구버전 클라이언트가 남아 있는 동안은 하지 않는다(전환 계획으로만 기록).

> 자기 정정: 첫 rules 테스트는 고정 숫자를 넣어 `-1` 거부 / `-2` 허용처럼
> 보였고 rules 결함으로 보고할 뻔했다. 앞 단계 취소가 트리거를 깨워 값을 이미
> 재계산한 뒤였다. 현재값을 읽고 ±1 을 만들도록 고쳤다. **rule 을 완화해
> 통과시키지 않았다.**

## 26. §6 — 전이 매트릭스 (기대값 판정, 25건)

`scripts/r7-emu-matrix3.js`. 판정은 **원장에서 계산한 기대값**과 파생 집계 셋의
일치다. 수렴을 기다리되 수렴한 값이 틀리면 FAIL 이다("4회 동일"은 판정 근거가 아니다).

| 시나리오 | 결과 |
|---|---|
| S1 지원 | 원장=파생 |
| S2.1 / S2.2 취소 → 재지원 **2주기** | 매 단계 원장=파생 |
| S3 같은 감소 command replay | 이중감소·음수 없음 |
| S4 정원 1에서 동시 확정 2건 | 성공 1건, 원장=파생 |
| S5 확정취소 → 재확정 | 원장=파생 |
| S6 무인증 401 / 근로자 토큰 확정 거부 / 타인 카운터 조작 거부 | 분리 확인 |
| S7 확정 롤백(`CONTRACT_PENDING → PENDING`) | 원장=파생 |

**before/after:** 수정 없이 같은 harness 를 돌리면 **9건 FAIL** 이고 업무 카운터가
1 → 2 → 3 으로 누적된다. 수정 후 **25/25 PASS**.

> harness 자기 결함 정정: 처음엔 고정 id 를 써서 직전 실행 cleanup 의
> `onTODeleted`/`onBusinessDeleted` cascade(각 ~900ms)가 새 실행이 막 seed 한
> 문서를 지웠다. 제품 결함이 아니라 간섭이다 — id 를 실행마다 유일하게 바꿨다.

## 27. §7 — 날짜 선택 재현

두 축 중 하나가 아직 열려 있었다.

카드는 머리말 수치를 `_updateGroupCache()` 에서 **캐시**하고, 같은 카드의 업무
행은 `resolveStats()` 를 매 build 에 다시 읽는다. 그런데 재계산 조건이
`!identical(widget.groupItem, old.groupItem)` 이었다. 정원 집계는
`setWorkDetails()` 로 **같은 인스턴스 안에** 채워진다 — 제자리 수정이다.
그래서 집계 도착 후 부모가 setState 해도 머리말은 갱신되지 않았다.
날짜를 고르는 순간엔 `calendarSlot` 변화로 갱신되지만, **그 뒤 도착한 집계는
다시 갱신을 만들지 못한다.** 머리말이 이전 값을 붙들고 있던 자리다.

- 수리: 부모가 다시 그릴 때마다 재계산한다(슬롯 수만큼의 덧셈, 프레임마다 아님).
- 계산을 `projectGroupHeaderTotals` 로 분리해 화면 없이 실행(11건):
  집계 있으면 집계 / identity miss 면 카운터 / 실패면 카운터 / 한 날짜라도 비면
  FULL 아님 / **같은 인스턴스에 집계를 채운 뒤 다시 부르면 새 값** / 쓰지 않을
  합성 item 은 만들지 않음.

**미검증(NOT TESTED):** 실제 위젯 렌더. `TOGroupCard` 는 Provider 와
`FirestoreService`(→ Firebase) 를 타서 단위 테스트에서 pump 할 수 없다.
`WorkforceController` 12건은 controller 경로만 덮고, Day `_cachedGroups` 왕복과
공고 date tile 선택의 **actual entry** 는 각각 별도다. 이 항목은 여전히 OPEN.

## 28. §5 — 소비자 범위 (grep 분류 실측)

`lookupByIdentity` 13개를 전체 수치 소비자 수로 말하지 않는다.

| 분류 | 지점 수 | 비고 |
|---|---|---|
| `lookupByIdentity` | 13 | 정의 파일 제외 |
| `resolveStats()` | 10 | 정의 파일 제외 |
| `WorkCapacityReading.read` | 5 | 이번·4차에 전환한 owner |
| `capacityBlockReason` | 4 | 승인 관문 공통 |
| `confirmedFor(` | 2 | canonical gate |
| raw `.confirmedCount`/`.pendingCount` 읽기 | 48 | 모델·주석 포함 grep 분류 |
| `totalConfirmed`/`totalPending` 읽기 | 56 | 같음 |
| `workDetailCounts` 읽기 | 16 | 같음 |
| 지원서 리스트 `.length` 를 수치로 | 12 | 부분집합 위험 표면 |

> 이 숫자는 **grep 분류 건수**이고 중복 제거한 "화면 표면 수"가 아니다.
> 감사·전환한 부분집합은 §16·§24 에 명시했고, raw 카운터 읽기 48/56/16 의
> 개별 판정은 **미완료**다.

### C7 서버 폴백 — 후보 유지, 판정 보류

`callableGetAvailableWorkers` 는 `workDetailId` 를 composite 또는 workType 으로
맞추고, 못 맞추면 **첫 번째 workDetail 로 폴백**한다. 좁은 실행을 시도해
도시·주소 전제까지 채워 200 을 받았지만 **세 호출 모두 후보 pool 이 비어** 나왔다.
빈 결과끼리 같다고 해서 폴백이 안전하다는 뜻이 아니므로 harness 가 그 경우를
PASS 로 읽지 않게 가드를 넣고 **보류**로 남겼다. pool 진입 조건
(`inviteKeys`/availability)을 채우는 것이 남은 일이다.
`work.id` 를 바꾸지 않았다는 사실로 이 항목을 닫지 않는다.

## 29. §8 — 환경·부수 결함

- 수정 CLI / 7키 override / 재현 자료 유지. 실키 값은 로그·commit 에 없다.
- 외부 발송 0 의 근거 범위는 **이번 test 의 관측**이다. 발송 실패가 원장 commit 에
  영향 없다는 주장은 **해당 비동기 경로(`onNotificationCreated` 트리거)** 로 한정한다.
- **`onBusinessDeleted`:** 정상 순서(사용자 문서 존재) 삭제에서는 cascade 가
  `완료` 로 끝난다(850ms, 에러 없음). **사용자 문서를 먼저 지운 경우에만**
  `5 NOT_FOUND: no entity to update` + unhandled error 로 cascade 가 끊긴다.
  존재 확인 없는 `.update()` 는 사실이고, 탈퇴한 관리자가 있는 사업장 삭제에서
  같은 일이 가능하다 — **별건 owner** 로 분리. 삭제 시스템을 재작성하지 않는다.
- 에뮬레이터는 작업 중 재사용했고, 재시작 절차는 `scripts/r7-audit/README.md` 에 있다.

## 30. 5차 상태

- 제품 코드: CF 2곳(`callableIncrementSlotPending`, `callableApplyToTO` 재활성화),
  클라이언트 3곳(취소·상태변경·카드 캐시), helper 3개 제거, projection 1개 분리.
- 저장 drift 복구와 UI 증상은 **별개 상태**로 관리한다:
  - 저장 불변식: 신규 전이에 대해 **복구 완료**(에뮬레이터 25건).
  - 기존 데이터: **손대지 않았다.** 실DEV 과거 데이터 backfill 은 READ 대조·필요성
    계획까지만이고 이번에 하지 않았다.
- shared DEV write **0** · PROD **0** · 외부 발송 **0** · 모델 migration **0**.
- **OPEN.** 남은 것: 날짜 선택 실제 렌더(§27), C7 pool 폴백(§28),
  raw 카운터 소비자 48/56/16 개별 판정, 초대/자동취소/trigger replay 전이,
  `onBusinessDeleted` 별건, 기존 데이터 backfill 필요성 판단.

---

# 6차 — 실패 구간·주기 간 요청·경합, 그리고 후보 목록의 날짜 (2026-09-27)

## 31. SHA (§0)

BASE `5b358d2`. branch `main`. tracked 변경 없음(이전 phase 의 user-owned untracked 8개만).

| SHA | 구분 | 내용 |
|---|---|---|
| `ed6dfd5` | CODE + TEST | F1/F2 — 트리거가 업무 단위 카운터까지 재계산, 주기 precondition, 공유 helper 2개, durability 하네스 |
| `f89cc0b` | CODE + TEST | 후보 목록 KST 하루 경계, unresolvable workDetailId 거부, controller 읽기 seam·재시도, 날짜 타일 파이프라인 테스트 |
| `4e08e26` | TEST | 초대 전이 하네스, C7 하네스, 하네스 cleanup 순서·타임아웃 |

## 32. F1 — 원장은 성공했고 command 는 오지 않았다

### 32-1. transaction 경계 (제출)

```
[경계 1] 클라이언트 Firestore transaction
           applications.status = CANCELED     (rules 허용: 본인 PENDING→CANCELED)
[경계 밖]  ── 여기서 프로세스가 죽으면 아래는 실행되지 않는다 ──
[경계 2] callableIncrementSlotPending(delta:-1)  (CF 내부 transaction)
           to.totalPending / slot.pendingCount / slot.workDetailCounts[wdId].pendingCount
```

두 동작은 **별개**다. 5차의 "실패해도 재시도하면 복구된다"는 **메모리 안의 재시도**였고,
호출자가 죽으면 아무도 재시도하지 않는다. 트리거는 상위 두 카운터만 되돌리므로
그 사실로 업무 단위 복구를 주장할 수 없다.

### 32-2. 선택한 설계와 대안

| 안 | 판정 | 근거 |
|---|---|---|
| **기존 authoritative sync 책임 완성** (`syncTOStats` 가 `workDetailCounts` 도 재계산) | **선택** | 원장 변경 자체가 트리거를 깨운다 → **호출자가 죽어도** 복구된다. writer 34개 전부를 덮는다. 새 command·필드·모델 없음. 확정 지원서는 이미 문서로 읽고 있어 `wdId` 그룹핑에 추가 읽기가 거의 없다(슬롯 대기만 `.count()` → 문서). |
| 취소를 CF 로 이전(원장+집계 원자적) | 미채택 | 새 callable + rules 전환 + 구버전 클라이언트 잔존 처리. 위 안이 같은 문제를 더 적은 변경으로 덮는다. |
| 스케줄 재처리 | 미채택 | 지연이 크고, 트리거가 이미 같은 이벤트에 붙어 있다. |

**새 helper 로 집계 책임을 늘리지 않았다.** 대신 `callableRecalculateTOStats` 안에만
있던 두 조각을 공유 함수로 꺼냈다 — `srvResolveAppWdId`(identity 4단계 + fail-closed),
`srvBuildWdCountsUpdate`(쓰기 모양). 트리거와 재집계가 같은 것을 쓴다.

### 32-3. 덤으로 찾은 것 — 절대 재계산이 절대가 아니었다

`callableRecalculateTOStats` 는 **집계에 나타난 wdId 만** dot-update 했다.
취소로 인원이 0 이 된 업무는 집계에서 사라지므로 **옛 값이 그대로 남았다**.
이제 슬롯이 가진 모든 wdId 를 0 으로 깔고 시작한다 —
`getWorkDetailCount` 가 항목 없음을 fail-closed 로 막는 계약과도 맞다.

## 33. F2 — 같은 문서의 다음 주기와 지난 주기의 요청

플래그 reset 만으로는 부족했다. 재지원이 같은 문서를 되살리며 플래그를 지우니,
**지난 주기의 감소 요청이 늦게 도착하면 막을 것이 없다.**

실측(수정 전): 원장은 `PENDING 1` 인데 `slot.pendingCount` 와 `to.totalPending` 이 0.

해법은 **상태 전이 precondition** 이다 — 새 필드도 저장 모델도 만들지 않고 이미 있는
`status` 로 본다. 감소는 대기 좌석이 사라졌을 때만, 증가는 대기 중일 때만 옳다.

| 경우 | 막는 것 |
|---|---|
| 같은 주기 replay | 멱등 플래그 |
| 주기 간(B 활성) | **status precondition** — B 가 대기 중이므로 A 의 감소를 무시 |
| B 도 취소된 뒤 A 도착 | B 의 취소가 남긴 멱등 플래그 |
| 순서 역전(A 먼저 적용) | A 가 플래그를 세워 B 가 막힌다 — 어느 쪽이든 감소는 한 번 |

## 34. F3 — 절대 재계산과 증감의 경합

| 주체 | 읽기 | 쓰기 | 경계 |
|---|---|---|---|
| `syncTOStats`/`_syncTOCounters` | 원장(공고 전체 + 슬롯), 슬롯 문서 | TO 합계, 슬롯 합계, `workDetailCounts` **절대값**, slot status | `batch` (+ status 교정만 transaction) |
| `callableRecalculateTOStats` | 원장 전량, 슬롯 전량 | 같은 필드들 **절대값** | `batch` |
| `callableIncrementSlotPending` | 지원서, 슬롯, TO | 같은 필드들 **delta ±1** | `transaction` |

**반례를 찾지 못했다.** 재집계가 원장을 읽은 뒤 커밋을 끼워 넣고, 증감과 트리거를
겹치고, 마지막 한 자리를 동시에 확정하고, 재집계를 반복해도 최종값이 원장과 맞았다.
**수정 전에도 통과했으므로 내가 고친 것이 아니다** — 원래 그랬다고 적는다.

근거: delta 쪽이 `transaction` 이라 슬롯 문서에 쓰는 절대 재계산과 겹치면 재시도되고,
재시도 후 자기 값을 다시 읽어 가드가 다시 판단한다. 절대 쪽은 마지막 이벤트의
재계산이 이기고, 모든 원장 변경이 트리거를 깨우므로 마지막 재계산이 최종 원장을 읽는다.

> 남은 이론적 창: **마지막** 트리거 실행이 stale snapshot 을 읽고, 그 뒤 아무 이벤트도
> 없으면 어긋난 채 남는다. 이번 실행으로는 재현하지 못했고 **반증하지도 못했다**.
> 이 창은 상위 두 카운터에도 이미 있던 것이고, 이번에 새로 만든 것은 아니다.

## 35. 실행 증거 (before/after)

| 하네스 | 수정 후 | 수정 없이 |
|---|---|---|
| `r7-emu-durability.js` (F1·F2·F3) | **29/29** | **8건 실패** — command 없이 복구 불가, 롤백 후 확정 카운터 잔존, 주기 간 stale 감소가 상위 카운터를 0 으로 |
| `r7-emu-matrix3.js` (5차 25건) | 25/25 | (5차 기록: 9건 실패) |
| `r7-emu-invitations.js` | **19/19** | — |
| `r7-emu-c7-fallback.js` | **16/16** | 아래 §36 |
| `r7-emu-compat.js` | **12/12** | — |
| Dart 스위트 | 신규 실패 **0** (기존 63건 유지) | — |

## 36. §4 — 초대·겹침·C7

### 36-1. 초대 전이 (ACTIVE 전이, 실행)

발송 → **관리자 취소** → 재초대 → **거절** → 다른 근로자 **수락**(대기→좌석) →
**겹침 자동취소** → 재집계 반복 → 만료. 매 단계 원장 기대값과 업무·슬롯·공고 집계 대조.

겹침 자동취소는 **두 공고 모두** 확인했다 — 확정된 쪽과 `AUTO_CANCELED` 된 쪽이 각각 일치.

> 순서 주의: 거절을 먼저 하면 재초대가 `409`(이미 초대됨)로 막혀 **관리자 취소 경로에
> 닿지 못한다**. 그래서 취소를 먼저 본다.
>
> 전제를 우회하지 않았다. 초대는 `worker_availability` 의
> `inviteEnabled` · `inviteRegionKeys` · `dates` 가 필요하고, 후보 조회는 같은 문서의
> `inviteKeys`(= `지역키#날짜`) 배열을 본다 — **서로 다른 인덱스**다.
> 실제 앱은 `callableSyncInviteKeys` 가 둘을 맞춘다.

### 36-2. C7 — 두 가지가 나왔다

후보 pool 을 실제로 채우자 **먼저 다른 것이 보였다.**

**(A) 후보 목록의 시간 충돌 배제가 하루 어긋난 창을 보고 있었다.**

`new Date(연, 월, 일)` 은 **런타임 TZ** 로 해석된다. Cloud Functions 는 UTC 로 돈다.
KST 성분으로 그 생성자를 부르면 창이 +9h 밀리고, `workDate` 가 항상 KST 자정
instant 인 이 프로젝트에서는 **다음 날** 확정을 보게 된다.

| 관측 | 수정 전 | 수정 후 |
|---|---|---|
| 같은 날 09:00–12:00 확정자를 09:00–12:00 업무 후보에서 | **포함**(틀림) | 제외 |
| **하루 뒤** 확정자를 오늘 후보에서 | **제외**(틀림) | 포함 |
| 업무 1개 슬롯에서도 | 포함(틀림) | 제외 |
| 같은 충돌로 초대 시도 | `400 동일 시간대에 이미 확정된 일정` | 동일 |

즉 증상은 **"목록이 과하게 포함되고, 누르면 거절당한다"** 였다. 데이터 무결성 문제는
아니지만 관리자가 못 뽑을 사람을 보고 판단하게 된다. `srvKstDayStartMs` 를 공유로
올려 TZ 에 기대지 않고 창을 만든다(`callableApplyToTO` 안에만 있던 계산이다).

**(B) 그 수정으로 업무별 후보가 갈라지자 C7 원래 질문이 결정됐다.**

없는 `workDetailId` 를 넘기면 응답이 **첫 번째 업무의 후보 목록과 같았다**
(물어본 업무와는 달랐다). 관리자가 09:00 근무 후보를 18:00 근무 후보로 읽는다.
지원 경로는 이미 *"composite exact match 필수 — 실패 시 REJECT, silent fallback 금지"*
라고 정해 두었다. 읽기 경로만 예외를 둘 이유가 없어 같은 규칙으로 맞췄다
(업무 정의가 하나뿐이면 가리킬 곳이 하나라 폴백 유지).

| 입력 | 결과 |
|---|---|
| 정상 composite(wd1 / wd2) | 각 업무의 후보 (서로 다르다) |
| legacy workType 단독(`주방`) | 그 업무로 맞는다 |
| **없는 식별자** | `400` — 조용히 바꾸지 않는다 |
| 미전달 + 업무 2개 | 시간 충돌 검사 불가 경로(기존 동작 유지) |
| 다른 사업장 공고로 조회 | 거부 — business isolation 유지 |

> **남은 예외:** 같은 `workType` 정의가 둘인 슬롯에 **workType 단독**을 넘기면
> 여전히 **첫 매치**로 간다(실측: wd1 의 후보가 나왔다). legacy 입력 경로의
> 기존 동작이라 이번에 바꾸지 않았다 — 별건으로 남긴다.

### 36-3. writer 34 분류

| 분류 | 수 | 근거 |
|---|---|---|
| 실행 검증 | 9 | `callableApplyToTO` · `callableConfirmApplication` · `callableCancelConfirmedApplication` · `callableIncrementSlotPending` · `callableRecalculateTOStats` · `callableInviteWorker` · `callableAcceptTOInvitation` · `callableDeclineTOInvitation` · `callableCancelTOInvitation` (+ `syncTOStats` 트리거는 모든 단계에서 함께 돌았다) |
| 실행되었으나 대상 0건 | 1 | `callableExpireApplications` (`expired: 0`) |
| 정적 확인 | 2 | `callableCloseSlots`(업무 단위 감소 anchor 있음) · `callableRecalcToTotalRequired`(single-write, totalRequired 전용) |
| **동등 경로로 묶음** | 12 | 좌석 증감 계열(`callableApproveApplicationForReview` · `callableReleaseNoshowSeat` · `callableBatchCancelNoShow` · `callableRespondToReconfirm` · `callableDecrementSlotConfirmed` · `callableRejectApplication` · `callableAcceptInvitation` · `callableOfferAlternativeWork` · `callableDeclineTOInvitation`(중복) · `callableAcceptConfirmedReassignment` · `callableCancelTOInvitation`(중복) · `onNotificationCreated`) — **모두 원장 status 를 바꾸므로 `syncTOStats` 가 같은 절대 재계산으로 덮는다.** 그 성질은 F1 에서 실행으로 확인했다(원장만 바꿔도 복구) |
| 미검증 | 10 | 삭제·정리 계열(`callableDeleteSlots` · `callableDeleteTO` · `callableDeleteAccountApplications` · `callableCleanupApplicationData` · `backfillReviewRequests` · `migrateAddressFields` 등)과 `callableUpdateSlotWorkDetails` · `callableCreateFlexSlots` · `onAttendanceWageStatusChanged` · `callableApplyNoShowPenalty` |
| 클라이언트 직접 counter writer | **0** | 5차에 helper 3개 삭제 — 이제 파생 집계를 쓰는 곳은 서버뿐이다 |

### 36-4. consumer 분류 정리 (5차의 grep 수치 정돈)

5차에 적은 48/56/16/12 는 **검색 건수**였다. 이번에 성격별로 나눴다.

| 분류 | 처리 |
|---|---|
| 판정·표시에 쓰는 소비자 | `WorkCapacityReading`(5) · `capacityBlockReason`(4) · `confirmedFor`(2) · `resolveStats`(10) · `projectGroupHeaderTotals`(1) — **전환 완료** |
| `lookupByIdentity` 13 | 4차에 전수 판정(정상 6 / 수정 7) |
| raw 카운터 grep 48·56·16 | 대부분 **모델 정의·주석·CF 문자열**이다. 화면 수치 소비는 위 항목으로 수렴했고, 남은 것은 **N/A**(정의/직렬화) 또는 미판정으로 남긴다 — 개별 판정은 **미완료** |
| 리스트 `.length` 12 | 부분집합 위험 표면. 이번에 판정하지 않았다 — **미완료** |

## 37. §5 — 날짜 선택 실제 경로

`TOGroupCard` 를 pump 할 수 없다는 말을 반복하지 않고, **실제 owner** 를 돌렸다.
타일을 고르면 `WorkforceController.loadWorkDetails(slot)` 가 집계를 읽어 **그 TOItem
인스턴스 안에** 채운다(제자리 수정). 읽기 하나만 주입 가능하게 했다.

원래 fixture 순서를 그대로 실행했다(11 + 5건):
`9/29 = 1/1` → 선택 → 상세 `1/1` → `9/30 = 0/1` → `9/29` 복귀 `1/1` →
재진입(이미 읽은 것을 다시 읽지 않음) → 요약이 날짜별 합과 일치.
빠른 전환에서 **응답 역전** 시 날짜별 값이 섞이지 않고, 실패는 0 이 아니라 카운터로
떨어지며, dispose 뒤에는 알리지 않는다.

**그 과정에서 실패 재시도가 막혀 있는 것을 찾았다.** `markWorkDetailStatsFailed()` 가
`isWorkDetailLoaded = true` 로 만드는데 `loadWorkDetails` 는 그것만 보고 돌아간다 —
화면은 `확인 필요` 를 보여 주면서 다시 읽지는 않는다. 카드의 자체 재시도 경로는
`resetWorkDetailLoad()` 를 먼저 불러 피하고 있었다.

> **남은 중복:** 같은 데이터를 읽는 **로더가 두 벌**이다 —
> `WorkforceController.loadWorkDetails` 와 카드의 `_retryWorkDetailStats`
> (후자는 `firestoreService` 를 직접 부른다). 이번에는 controller 쪽 구멍만 막았다.
> 카드가 controller 를 들고 있지 않아 통합은 별건이다.
>
> **미검증:** 위젯 렌더 자체(`TOGroupCard` — Provider·`FirestoreService`→Firebase),
> Day `_cachedGroups` 왕복(`day_applicants_dialog` private State + Firebase 직결).
> 이 두 항목은 여전히 **OPEN** 이다.

## 38. §6 — DEV 배포 준비 (실행하지 않았다)

### 38-1. 호환 조합 — 가능한 칸은 Emulator 로 돌렸다

클라이언트 세대는 **write set 으로** 재현했다(`scripts/r7-emu-compat.js`).

| 조합 | 결과 | 근거 |
|---|---|---|
| old client × old CF | 기준선(현행) | 5차에 기록한 drift 가 그대로 |
| **old client × new CF** | **일치 12/12** | 구버전이 상위 두 카운터를 직접 내려도, 트리거가 업무 단위를 원장에서 다시 센다. **이중 차감 없음**(구버전은 command 를 부르지 않는다) |
| **new client × old CF** | **실패 8건, 이중 차감·음수 없음** | `functions/src` stash 후 durability 하네스. 신버전은 상위 카운터를 미리 내리지 않으므로 구 CF 의 zero-guard 에 걸리지 않고 세 값을 내린다. 다만 주기 반복에서 옛 결함이 돌아온다 |
| **new client × new CF** | **일치 12/12** | — |

### 38-2. 배포 순서와 되돌림

- **CF 먼저, 클라이언트 나중.** `old client × new CF` 가 **더 좋아진다**(구버전 사용자도 복구된다).
- 한쪽만 되돌려도 안전하다: CF 만 되돌리면 `new client × old CF`(허용 가능),
  클라이언트만 되돌리면 `old client × new CF`(양호).
- **사용자에게 보이는 동작 변경 1건:** `callableGetAvailableWorkers` 가 맞출 수 없는
  `workDetailId` 에 `400` 을 준다. 구버전 클라이언트는 이 오류를 특별히 다루지 않아
  일반 실패 문구가 뜬다. 조용히 **다른 업무의 후보**를 보여 주던 것보다 낫지만,
  배포 노트에 적어야 한다.

### 38-3. 배포 대상·관측·중단

| 항목 | 내용 |
|---|---|
| CF | `callableIncrementSlotPending` · `callableApplyToTO` · `callableRecalculateTOStats` · `callableGetAvailableWorkers` · **trigger** `syncTOStats` |
| Rules | **변경 없음.** pending ±1 허용 축소는 **하지 않는다** — 구버전 클라이언트가 그 경로를 아직 쓴다. 서버 배포 승인과 묶지 않는다 |
| smoke | 지원 → 취소 → 재지원 1주기에서 원장·`slot.pendingCount`·`totalPending`·`workDetailCounts` 4값 일치 / 후보 목록에서 같은 시간 확정자 제외 / 없는 workDetailId → 400 |
| 관측 | `syncTOStats` 실행시간·오류율, `[syncTOStats] … fail-closed` 경고 건수, `stale decrement 무시` 경고 건수, `callableGetAvailableWorkers` 400 비율 |
| 중단·rollback | 트리거 오류율 상승 또는 fail-closed 경고 급증 시 CF만 revert. 클라이언트는 그대로 둬도 안전(위 표) |

### 38-4. 기존 데이터 — READ 대조 계획까지만

이번에 실DEV 를 **읽지도 쓰지도 않았다.** 계획만 남긴다.

1. 대조 대상: `tos/{toId}/slots/{slotId}.workDetailCounts` vs 그 슬롯의 원장 집계.
2. 산출: 기준시점(UTC), 대상 공고·슬롯 수, wdId 별 mismatch(부호·크기), 영향 표면
   (그 값을 읽는 화면이 있는지 — 현재 `pendingCount` 소비자는 없고 `confirmedFor`/
   `isWorkDetailFull` 는 `confirmedCount` 를 본다).
3. 수정 수단: `callableRecalculateTOStats`(멱등, 원장 기준, identity 불확실 슬롯은
   fail-closed). **dry-run 이 없으므로** 먼저 READ 대조로 예상 변화량을 산출한다.
4. 재실행성: 같은 command 를 여러 번 돌려도 같은 결과(§F3-e 로 확인).
5. **발견 0건이어도 신규 write-path 안전성으로 확대 해석하지 않는다.**

## 39. 6차 상태

- CODE: CF 5곳(트리거 포함), 클라이언트 1곳(controller), 공유 helper 3개 추가, 중복 구현 1개 제거.
- EMULATOR: durability 29 · matrix3 25 · invitations 19 · c7 16 · compat 12 = **101건**.
- DEV READ: **없음**. DEVICE: **없음**. DEPLOYED: **없음**.
- **OPEN.** 남은 것: 위젯 렌더(§37), Day `_cachedGroups` 왕복(§37), 로더 두 벌 통합(§37),
  ambiguous workType 후보 선택(§36-2), raw 카운터/`.length` 개별 판정(§36-4),
  writer 미검증 10(§36-3), F3 의 마지막-트리거-stale 창(§34), 기존 데이터 대조(§38-4),
  `onBusinessDeleted` 별건(5차 §29).
- "신규 전이 저장 불변식 전체 복구" 라고 말하지 않는다 — 위 목록이 남아 있다.
