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

---

# 7차 — 종료 정리 (2026-09-27)

## 40. Closure matrix

`CODE` = 로컬 코드 · `EMU` = 격리 에뮬레이터 실행 · `CONS` = consumer/위젯 실행 ·
`DEVR` = 실DEV 읽기 대조 · `DEVICE` = 실기기 · `DEPL` = 배포.
`—` 는 해당 없음, `✗` 는 아직 아님.

| 항목 | 원래 결함/요구 | 수정 owner | 제거된 구 경로 | CODE | EMU/CONS | DEVR | DEVICE | DEPL | 미결·근거 |
|---|---|---|---|---|---|---|---|---|---|
| 업무 identity | 정의 원천이 둘(slot wdId vs master) | `WorkDetailData.lookupByIdentity` · `srvResolveAppWdId` | 소비자별 개별 키 해석, 재집계 인라인 해석 | ✓ | ✓ | ✓(해석 18건 전부 `wdId`, ambiguous 0) | ✗ | ✗ | — |
| UNKNOWN ≠ 0 | miss 를 0 으로 접어 표시·판단 | `WorkCapacityReading` · `capacityBlockReason` | C3~C7 의 `?? 0`, map 존재 판정 | ✓ | ✓ 21+4 | — | ✗ | ✗ | — |
| 카운터 drift | `workDetailCounts` 보정자 부재 | `syncTOStats`→`srvSyncSlotCountersTx` | 클라이언트 증감 helper 3개 | ✓ | ✓ 29 | ✓ **21건 발견** | ✗ | ✗ | 기존 데이터 보정 미실행(§43) |
| F1 내구성 | 원장 성공 후 command 미도달 | 트리거(원장 이벤트가 깨움) | 2단계 의존 | ✓ | ✓ 수정 전 11건 실패 | ✓ | ✗ | ✗ | — |
| F2 주기 간 | 플래그 reset 만으로 부족 | `callableIncrementSlotPending` status precondition | — | ✓ | ✓ 3주기·replay | ✓ | ✗ | ✗ | 주기 범위 §42 |
| F3 경합 | 낡은 절대 재계산이 최신을 덮음 | `srvSyncSlotCountersTx`(transaction) | 슬롯 batch 무조건 쓰기 | ✓ | ✓ **재현→차단** | — | ✗ | ✗ | 공고 합계 축은 창 잔존(§41) |
| loader 통합 | 같은 로딩 3벌 | `WorkforceController` | 카드 `_retryWorkDetailStats` 본문, 카드 그룹 통계 로딩 | ✓ | ✓ | — | ✗ | ✗ | — |
| 공고 날짜 클릭 | 선택 후 머리말이 옛 값 | `projectGroupHeaderTotals` + 무조건 재계산 | `identical` 캐시 가드 | ✓ | ✓ **실제 위젯 3건** | — | ✗ | ✗ | — |
| Day `_cachedGroups` 왕복 | 선택·무효화·표시 | — | — | — | ✗ | — | ✗ | ✗ | **미착수**(§44) |
| writer/consumer 전수 | 34 writer · 소비자 분류 | — | — | ✓ | 실행 9 · 구조 커버 21 · N/A 1 · 미검증 3 | ✓ | — | — | §42 |
| 후보 조회 identity | 날짜 창 · 폴백 · 모호성 | `srvKstDayStartMs` · exact/unique 규칙 | first-match 폴백 | ✓ | ✓ 17 | — | ✗ | ✗ | — |
| 배포 호환 | 방향별 안전성 | — | — | — | ✓ 4조합 | — | — | ✗ | **6차 주장 철회**(§41) |

## 41. 6차 주장 보정

### 41-1. "한쪽만 되돌려도 안전" — **철회한다**

6차에는 `functions/src` 를 stash 해 비교했는데, 그것은 **6차 CF** 로 돌아간 것이지
배포 기준의 old CF 가 아니었다. 실제 production 기준(`adb6cbb`, 아직 아무것도
배포되지 않음)으로 다시 재면 **11건 실패**이고, 그중 하나는 상위 카운터까지 망가뜨린다.

| 방향 | 결과 | 판정 |
|---|---|---|
| **CF 먼저 교체, 아직 old client** | 12/12 일치. 구버전이 상위 두 카운터를 직접 내려도 트리거가 업무 단위를 원장에서 다시 센다. 구버전은 command 를 부르지 않아 이중 차감 없음 | **권장 순서** |
| **new client 배포 후 CF 만 old 로 rollback** | 11건 실패. 특히 지난 주기 감소가 `slot.pendingCount`·`to.totalPending` 을 **0 으로 만들고 원장에는 대기 1이 남는다**. 그 상태는 다음 원장 이벤트 전까지 **스스로 낫지 않고 관리자에게 보인다** | **금지** |
| **CF new 유지, client 만 old 로 rollback** | old client × new CF 와 같다 — 12/12 | 안전 |
| **양쪽 rollback** | 현행 기준선으로 복귀(기존 drift 유지) | 안전(개선 없음) |

**결론:** CF 를 먼저, 클라이언트를 나중에. **클라이언트가 나간 뒤에는 CF 만 되돌리지 않는다.**
되돌려야 하면 클라이언트도 함께 되돌리거나, forward-fix(§43 재집계)로 간다.

### 41-2. "trigger 가 writer 34 전부를 덮는다" — 연결 구조 주장으로 한정

트리거는 `applications/{applicationId}` 쓰기에 붙는다. 그래서 **원장을 건드리는
writer 만** 덮는다. 미검증 10건을 그 근거로 실행 완료로 세지 않는다(§42).

### 41-3. F3 "반례를 찾지 못했다" → **반례를 찾았고 고쳤다**

부하로 창을 만들어 재현했다(§34 의 후속). 아래 §41-4.

### 41-4. F3 — 재현과 수정

| 단계 | 관측 |
|---|---|
| 경계 | 절대 재계산이 원장을 **transaction 밖**에서 읽고 `batch` 로 **무조건** 쓴다. conflict detection·precondition 없음 |
| 재현 | 지원서 482건으로 재집계를 6.9초로 늘린 뒤 그 사이 1명 취소 → 원장 대기 1인데 슬롯·업무 카운터 **2** 로 남고, 후속 이벤트가 없어 3초간 그대로 |
| 수정 | 슬롯 범위 재계산을 `srvSyncSlotCountersTx` 로 옮겨 **쓰기 시점에 다시 센다**. Firestore transaction 이 읽은 결과의 변경을 잡아 재시도한다 |
| 수정 후 | 같은 시나리오 통과. 트리거·재집계가 같은 writer 를 쓴다 |
| **남는 창** | **공고 단위 합계**(`to.totalPending`/`totalConfirmed`)는 여전히 밖에서 읽고 쓴다. 이 축의 stale 창은 **닫지 않았다** — 범위가 공고 전체라 비용이 다르고, 이번에 재현한 결함은 슬롯·업무 축이다. **미결로 유지한다** |

**비용(실측)**: 평범한 취소 1건의 수렴 3.8초 → **2.0초**(오히려 단축).
13슬롯·482건 전체 재집계와 **동시에** 돌면 경합으로 **71.8초**까지 늘어난다.
재집계는 사람이 의도해 부르는 복구 경로이므로 그대로 두되 숫자를 남긴다.

**replay/0-reset**: 같은 상태에서 재집계를 3회 반복해도 값이 바뀌지 않는다.
모든 wdId 를 0 으로 깔고 시작하지만 그것이 최신 값을 지우지 않는다(같은 transaction 에서 다시 세므로).

## 42. writer coverage · consumer 분류

### 42-1. writer 34 coverage (watched path 기준)

| 분류 | 수 | 근거 |
|---|---|---|
| 실행 검증 | 9 | apply · confirm · cancelConfirmed · incrementSlotPending · recalculate · inviteWorker · acceptTOInvitation · declineTOInvitation · cancelTOInvitation (트리거는 전 단계에서 함께 실행) |
| 대상 0건 실행 | 1 | `callableExpireApplications` (`expired: 0`) |
| **구조 커버(원장 이벤트 발생 확인)** | 21 | 좌석·대기 전이 12(6차) + 미검증이던 10 중 **8**(아래) + `callableCloseSlots` |
| N/A | 1 | `migrateAddressFields` — `applications` 미접근, 카운터 무관 |
| **미검증(구조 커버로도 못 닫음)** | 3 | `callableCreateFlexSlots`(슬롯 생성 시 wdCounts seed, 원장 이벤트 없음) · `callableUpdateSlotWorkDetails`(**wdCounts 직접 쓰기 8곳 + 업무 정의 변경**) · `callableRecalcToTotalRequired`(단일 write, totalRequired 전용) |

6차에 "미검증 10" 이라 적은 것 중 8건(`callableDeleteSlots` · `callableDeleteTO` ·
`callableDeleteAccountApplications` · `callableCleanupApplicationData` ·
`backfillReviewRequests` · `onAttendanceWageStatusChanged` · `callableApplyNoShowPenalty` ·
그리고 `callableCloseSlots`)은 `applications` 문서를 쓴다 → 트리거가 깨어나
슬롯 범위가 다시 계산된다. **구조 커버이지 개별 실행은 아니다.**

> **남은 위험 하나:** `srvBuildWdCountsUpdate` 는 슬롯의 **현재** wdId 를 모두 0 으로
> 깔지만, 정의에서 **사라진** wdId 의 옛 키는 지우지 않는다.
> `callableUpdateSlotWorkDetails` 가 wdId 를 교체하면 옛 키가 남는다.
> 읽는 쪽은 현재 정의로 `lookupByIdentity` 하므로 화면에 나오지는 않지만
> 저장 찌꺼기다. DEV 대조에서는 해당 사례가 없었다(§43). **미결.**

### 42-2. consumer 분류 (5차의 grep 수치 정돈 완료)

| 분류 | 판정 |
|---|---|
| 화면 수치 소비자 | `WorkCapacityReading`(5) · `capacityBlockReason`(4) · `confirmedFor`(2) · `resolveStats`(10) · `projectGroupHeaderTotals`(1) — **전환 완료, 실행 검증됨** |
| `lookupByIdentity` 13 | 4차 전수 판정(정상 6 / 수정 7) |
| raw 카운터 grep 48·56·16 | **비화면·N/A**: 모델 필드 정의·`toMap`/`fromMap` 직렬화·CF 소스 문자열·주석. 화면 수치 경로는 위 항목으로 수렴 |
| 리스트 `.length` 12 | **비-카운터**: 목록 길이·반복 인덱스·빈 목록 판정. 정원/대기 수치로 쓰는 곳은 없다 |

각 active 숫자의 source/모집단/freshness/실패/action 연결은 §16(4차)·§26(5차)·
§36(6차) 표에 있고 이번에 바뀐 것은 없다.

## 43. 실DEV READ 대조 (실행함 · 읽기 전용)

`scripts/r7-dev-read-reconcile.js` — `.get()` 만 사용. **쓰기·보정 없음.**

- 프로젝트 `alfit-89567` · 기준시점 **2026-09-27T11:35:38Z**
- 범위: 전체 공고 96 중 **flex 92** · 슬롯 **246** · 업무키 **266**
- identity 해석: **`wdId` 18건**, ambiguous/unresolved **0** → fail-closed 슬롯 없음

| 축 | mismatch |
|---|---|
| `to.totalPending` / `to.totalConfirmed` | **0** |
| `slot.pendingCount` / `slot.confirmedCount` | **0** |
| **`workDetailCounts.pendingCount`** | **9** |
| **`workDetailCounts.confirmedCount`** | **12** |

**진단이 실데이터로 확인됐다.** 상위 두 축은 트리거가 계속 맞춰 왔고,
보정자가 없던 업무 단위 축에만 어긋남이 남아 있다.

원인 분류:
- **과다 저장(저장 > 기대)** — 대부분. `저장=1·2`, `기대=0`.
  `wd.confirmedCount` 과다는 **지원 차단**으로 이어질 수 있다
  (`getWorkDetailCount` 가 `confirmedCount >= required` 로 막는다).
- **음수 저장** — `-6` · `-3` · `-2`(`wd.pendingCount`). 가드 없이 감소된 이력.
  현재 이 필드의 화면 소비자는 없다.
- 영향 공고 **11개**, 슬롯 11개.

### repair dry-run 계획 (실행하지 않음)

1. 수단: `callableRecalculateTOStats(toId)` — 원장 기준 멱등, identity 불확실 슬롯은
   fail-closed. **7차 수정 후에는 슬롯 범위를 transaction 안에서 다시 센다.**
2. dry-run: 이 대조 스크립트가 곧 dry-run 이다. 대상 11개 공고에 대해
   `저장 → 기대` 변화표를 먼저 출력하고, 그 차이만큼만 바뀌는지 확인한다.
3. 재실행성: 같은 command 를 반복해도 결과가 같다(에뮬레이터 확인).
4. 순서: **CF 배포 후**에 돌린다. 배포 전에 돌리면 옛 재집계의
   "인원 0 인 wdId 를 건너뛰는" 결함 때문에 일부가 그대로 남는다.
5. 실행은 **별도 검토**. 이번에 하지 않았다.

> 발견 21건은 **이 범위·이 시점** 의 결과다. 신규 write-path 안전성의 근거로
> 확대하지 않는다.

## 44. 아직 끝나지 않은 것 (D)

| 항목 | 왜 남았나 |
|---|---|
| Day `_cachedGroups` 왕복 | `day_applicants_dialog` 의 한 번 로드에 서비스 호출이 **10개**다. 단일 주입점이 없어 "최소 seam" 으로 덮이지 않는다. 그룹 생성·무효화·표시 경로를 **실행하지 못했다** |
| 공고 합계 축의 stale 창 | `to.totalPending`/`totalConfirmed` 는 여전히 transaction 밖 읽기 + 무조건 쓰기. 슬롯 축은 닫았고 이 축은 **열려 있다** |
| 사라진 wdId 의 옛 키 | `srvBuildWdCountsUpdate` 가 지우지 않는다. `callableUpdateSlotWorkDetails` 와 함께 **미검증** |
| writer 3건 | `callableCreateFlexSlots` · `callableUpdateSlotWorkDetails` · `callableRecalcToTotalRequired` |

## 45. 최종 결론

### A. 개발 검증 완료 (CODE + EMU/CONS)

업무 identity · UNKNOWN≠0 · 카운터 drift(신규 전이) · F1 내구성 · F2 주기 간 멱등 ·
F3 **슬롯/업무 축** 경합 · loader 통합 · 공고 날짜 클릭(실제 위젯) ·
후보 조회 날짜창·폴백·모호성 · 초대 전이 · 겹침 자동취소 · rules 경로.
에뮬레이터 실행 **118건**, Dart 신규 실패 **0**(기존 63 유지).

### B. DEVICE 로만 남은 것

위 A 항목들의 실기기 확인. 최소 묶음으로 한 번:
**공고 탭 → 다중 날짜 카드에서 날짜 하나 선택 → 머리말과 업무 행 숫자가 같은지 →
다른 날짜 → 원래 날짜 복귀 → 상세 열고 닫고 탭 복귀.**
(개발 검증이 끝난 범위이므로 이 한 묶음이면 된다.)

### C. 별도 실행 결정이 필요한 것

- **DEV 배포** — 순서는 CF 먼저. 클라이언트 배포 후 CF 단독 rollback 금지(§41-1).
- **기존 데이터 보정** — 21건, 배포 후, dry-run 먼저(§43).
- **Rules 축소** — pending ±1 허용 제거는 구버전 클라이언트 하한선 결정 후.

### D. 아직 개발 검증·수정이 안 끝난 critical

§44 의 4건. **따라서 전체 개발 감사는 CLOSED 가 아니다.**
B 와 C 는 개발 완료로 세지 않으며 서로 다른 gate 로 관리한다.

---

# 8차 — 고정 미결 항목 종료 (2026-09-27)

BASE `ce3b0d6`(7차 종료 시점) → 8차 커밋 `1825b72`(O01) · `ee69e60`(O03) ·
`a56ad70`(O05) · `8617663`(하루 경계 helper 통일).
branch `main`. 사용자 소유 untracked 스크립트 8개는 손대지 않았다.
체크리스트 파일(`ALfit_Staffing_Integrity_Closure_Checklist.md`)은 저장소에 없다 —
요청 본문의 O01~O08 정의를 기준으로 적는다.

## 46. 종료 표

| ID | 이전→현재 | owner/변경 | 제거한 구 경로 | 증거(테스트·SHA·환경) | 남은 조건 |
|---|---|---|---|---|---|
| **O01** 공고 합계 경합 | 열림 → **구조 근거로 닫음** | 변경 없음(배치가 이미 안전). 계약 고정 테스트 추가 | — | `scripts/r8-emu-to-total-race.js` T2·T3·T4·T5 / `test/to_total_write_contract_test.dart` 7건 / `1825b72` / Emulator | 반례 부재는 증명이 아님 — 시도한 순서 3종을 명시 |
| **O02** 로더 통합 | 완료 유지 | `WorkforceController` | 카드 `_retryWorkDetailStats` 본문·카드 그룹 통계 로딩 | 7차 `fa65d3c` 재사용. 이번 회귀만 재실행 | 없음 |
| **O03** Day 실제 왕복 | 미착수 → **실행 완료** | `DayApplicantsReads` 주입 경계 + production `DayApplicantsDialog` | 화면 안의 `_svc.*` 읽기 12개·`_contractSvc` 필드 | `test/day_applicants_roundtrip_test.dart` 4건 / `ee69e60` / production widget | 실기기는 O08 |
| **O03b** 공고 카드 날짜 전환 | 완료 유지 | `projectGroupHeaderTotals` + 무조건 재계산 | `identical` 캐시 가드 | 7차 `test/posting_card_render_pipeline_test.dart` 재사용 | dialog 닫기·탭 복귀는 그 테스트에 없음 → O03 에서 별도 확인 |
| **O04-a** 남은 writer 3 | 미검증 → **전부 판정** | — | — | 정적 근거 + 기존 Emulator | 없음 |
| **O04-b** raw 카운터·length | 미판정 → **행 단위 판정** | — | — | 아래 §49 | 없음 |
| **O04-c** 사라진 wdId 옛 키 | 미결 → **계약으로 닫음(수정 불필요)** | — | — | §50 | 없음 |
| **O05** 후보 조회 두 계약 | 1 연결 / 2 **결손 보완** | `available_workers_bottom_sheet` 오류 처리 | 일반 문구 덮기·무한 재시도 버튼 | `test/available_workers_error_recovery_test.dart` 6건 + `scripts/r7-emu-c7-fallback.js` C7-3·C7-7 / `a56ad70` | 없음 |
| **O06** DEV READ 대조 | 완료 유지 | — | — | 7차 §43 (flex 92TO·246slot·266키, mismatch 21) | 반복하지 않음 |
| **O07** 배포·복구 준비 | 계획 갱신 | — | — | §51·§52 (미실행) | 실행은 별도 결정 |

## 47. O01 — 공고 합계 축

### 47-1. owner 와 경계

| 주체 | 원장 읽기 | TO 합계 쓰기 | 경계 |
|---|---|---|---|
| `_syncTOCounters` flex (index.ts:17787) | `countCommittedSeats()`(페이지네이션) + `.count()` | `toRef.update` **절대값** | transaction 밖 |
| `_syncTOCounters` 비슬롯 (17747) | 같음 | 같음 | transaction 밖 |
| `callableRecalculateTOStats` (24501) | `while` 페이지네이션 | `update(toUpdate)` **절대값** | transaction 밖 |
| apply·confirm·cancel·increment 등 | — | `FieldValue.increment` **delta** | **transaction 안** |

### 47-2. 통제한 순서와 결과

| 시도 | 만든 순서 | 결과 |
|---|---|---|
| T2 | 느린 재집계(61슬롯, 9.1초)가 원장을 읽은 뒤 취소를 끼워 넣고, 후속 이벤트 없이 4초 대기 | 원장과 **일치** |
| T3 | 같은 창에 좌석 delta(transaction)를 겹침 | 원장과 **일치** |
| T4 | 재집계 2개를 띄운 채 36건 변경 burst → 정적 상태에서 대조 | 원장과 **일치** |
| T5 | 재집계 경합 중 정상 지원 5회 | 아래 47-4 |

**재현하지 못했다.** 이유는 코드 배치다:

- 트리거는 **느린 일(슬롯 transaction)이 읽기 앞**에 있고, 원장 읽기 직후 TO 를 쓴다.
- 재집계는 **스캔 직후 TO 를 쓰고**, 느린 일(슬롯별 transaction)이 쓰기 뒤에 있다.

즉 두 절대 writer 모두 **읽기→쓰기 간격이 짧다.** 모든 원장 변경이 트리거를
깨우고 그 트리거의 읽기는 그 변경 이후이므로, 마지막 쓰기의 스냅샷은 마지막
변경을 포함한다. 낡은 쓰기가 마지막이 되려면 **먼저 읽은 쪽이 나중에 써야**
하는데 그 간격이 거의 없다.

> `transaction API 를 썼다`로 대신하지 않았다. 그 배치가 깨지면 실패하는 테스트를
> 두었다(`to_total_write_contract_test.dart`): 읽기와 쓰기 사이에 `await` 이
> 들어오면, 느린 일이 읽기 뒤로 가면, 슬롯 구간이 TO 쓰기 앞으로 오면 깨진다.
> 슬롯·업무 축의 transaction(읽기가 tx 안, 쓰기도 tx 안)도 같은 파일에서 고정했다.

**남는 한계:** 반례를 찾지 못한 것은 없다는 증명이 아니다. 시도한 순서는 위 3종이고,
그 밖의 interleaving(예: 트리거 재시도가 길어져 먼저 읽은 쪽이 나중에 쓰는 경우)은
재현하지도 반증하지도 못했다. **슬롯·업무 축은 transaction 으로 닫혔고, TO 축은
배치 근거로만 안전하다** — 두 상태를 분리해 기록한다.

### 47-3. 슬롯축/TO축 완료 상태

| 축 | 방식 | 상태 |
|---|---|---|
| `slot.workDetailCounts` · `slot.pendingCount/confirmedCount` | 쓰기 시점 재계산(transaction) | **닫힘** (7차 재현→수정) |
| `to.totalPending/totalConfirmed` | 절대 쓰기, 읽기→쓰기 인접 | **배치 근거로 안전**, 구조 변경 시 테스트가 잡음 |

### 47-4. 71.8초의 영향 (7차 수치 후속)

| 항목 | 실측 |
|---|---|
| 데이터 규모 | 슬롯 61 · 지원서 483 |
| 동시 작업 | 전체 재집계 1개 + 정상 지원 5회 |
| 재집계 소요 | **9.2초** |
| 경합 중 첫 지원 | **성공(200), 4.5초** |
| 이후 지원 4회 | 409 `이미 지원한 업무입니다.` (103~115ms) |
| 정원 오판 | **없음** — `모집 인원이 마감` 거절 0건 |
| timeout·재시도 소진 | 관측되지 않음 |
| 경합 후 정합 | TO 축·슬롯 축 모두 원장과 일치 |

그 시간 동안 원장은 정상이고, 슬롯·업무 카운터는 매 커밋 시점에 재계산된 값이며,
TO 합계는 트리거가 곧 맞춘다. **사용자에게 과거 숫자를 현재값으로 보여주거나
잘못된 action 을 허용·차단한 경로는 확인되지 않았다.** 7차의 71.8초는
하네스의 수렴 관측 지연이고 사용자 정지 시간이 아니다.
새 성능 SLA 는 만들지 않는다 — 관측값과 이 제약만 남긴다.

## 48. O03 — Day 실제 왕복

7차에 "한 번 로드에 서비스 호출 10개라 최소 seam 불가"라고 적은 것은 **의존성
규모의 설명**이었다. 읽는 경계를 한 곳에 모으면 화면은 그대로 돌아간다.

- `DayApplicantsReads` — 읽기 12개(지원자·확정자·충원행·초대·근무이력·노쇼·
  사용자·주간근태·슬롯정원·슬롯업무·공고·계약상태). 주지 않으면 기존 서비스로 간다.
  `WorkforceController` 가 이미 쓰는 패턴이고 새 프레임워크를 만들지 않았다.
  **도메인 계산은 넣지 않았다** — 그룹 구성·캐시·머리말 수치·scope label 은 화면이 한다.
- `_contractSvc` 필드는 제거했다(그 읽기도 경계로 옮겼으므로 두 경로를 남기지 않는다).

실행한 것 (production `DayApplicantsDialog`, 복제품 아님):

| # | 시퀀스 | assert |
|---|---|---|
| DAY-1 | 9/29 → 9/30 → 9/29 → 날짜 해제 (날짜마다 새 인스턴스 = 실제 navigation) | scope label 날짜·`공고 1개 · 업무 1개`·`지원 1건`·`확정 1건` / 9/30 은 `0건` / 날짜별 읽기 호출 순서 |
| DAY-2 | 진입점 → 열기 → 닫기 → 진입점 복귀 → 다시 열기 | 닫힌 뒤 본문 사라짐 · 다시 열면 **다시 읽고** 같은 값 |
| DAY-3 | A 응답을 붙잡은 채 B 로 이동 → A 의 늦은 응답 도착 | B 화면이 덮이지 않음(`9월 30일` 유지) |
| DAY-4 | 충원 읽기 실패 → 성공 경계로 재시도 | 지원자 명단 유지(전체 ERROR 아님) · 못 읽은 충원을 0 으로 적지 않음 · 재시도 후 값 표시 |

> 렌더된 실제 문구 예: `인력 현황 | 2026년 9월 30일 (수) · 공고 1개 · 업무 1개 |
> 0명 | 부족 | 1건 | 지원 | 1건 | 확정 | 단기 | 테스트 공고 …`
>
> **공고 카드의 날짜 전환 테스트(7차)와의 구분:** 그 테스트에는 dialog 닫기·탭
> 복귀가 없다. 그 시퀀스는 위 DAY-2 가 담당한다. 실기기 조작은 O08 로 남긴다.

## 49. O04 — 고정 인벤토리 종료

### 49-1. 남은 writer 3

| 함수 | 호출자 | 전이 | 쓰는 필드 | 집계 owner | 판정 |
|---|---|---|---|---|---|
| `callableCreateFlexSlots` | 공고 생성 화면 | 슬롯 **생성**(원장 전이 없음) | `slot.workDetailCounts[wdId]={0,0}` 전량 · `slot.confirmedCount/pendingCount=0` | 자신(초기화) | **N/A — 초기화**. 생성 시점에 지원서가 없어 어긋날 대상이 없다. 모든 wdId 를 0 으로 깔아 `getWorkDetailCount` fail-closed 도 막는다 |
| `callableUpdateSlotWorkDetails` | 공고 수정 | 업무 정의 변경 | **신규 wdId 에만** `workDetailCounts.{wdId}` dot-notation 초기화(기존 카운터 보존) | 자신 + 트리거 | **정적 확인 + 구조 보호**. identity 가 바뀌는 수정은 활성 지원자가 있으면 `failed-precondition` 으로 **거부**된다(`해당 업무 시간대에 활성 지원자가 있어…`). 따라서 원장/카운터 불일치를 만들 수 없다 |
| `callableRecalcToTotalRequired` | 공고 관리 | 정원 재합산 | `to.totalRequired` 단일 | 자신 | **N/A — 다른 축**. 원장이 아니라 **정의**에서 합산하므로 대기/확정 축이 아니고 stale 창 개념이 없다 |

> "같은 sync owner 를 부른다"는 사실만으로 세지 않았다 — 위 세 건은 각각
> 쓰는 필드와 전이를 보고 판정했다.

### 49-2. raw 카운터·`.length` 소비자 — 행 단위

| 위치 | source·identity | 모집단·단위 | canonical 0 vs UNKNOWN | 표시/gate | owner·근거 |
|---|---|---|---|---|---|
| `business_admin_home_screen:1443` | 서버 staffing readiness | 그날 모집 단위 · 명 | 대상 없음은 상위 gate 에서 걸러짐 | 표시 | 기존 Home 계약 |
| `:2201` (`day?.confirmedCount ?? 0`) | 같음 | 오늘 · 명 | `if (!_staffingReadiness!.hasTodayTarget) return null;` 가 앞에서 UNKNOWN 차단 | 표시 | 같음 |
| `:2592` | 같음 | 예정일 · 명 | 같은 gate | 표시 | 같음 |
| `:2614–2615` | 같음 | 오늘 · **건** | `pendingCount != null && > 0` — `null(실패)·0 → 숨김` 명시 | 표시 | 같음 |
| `available_workers_bottom_sheet:526` | `_canonicalConfirmed`(canonical gate) | 그 업무 · 명 | `int?` — 모르면 `확정 인원 확인 불가` | 표시 | 4차 C7 |
| `day_applicants_dialog:803·829` | `DayStaffingRow.confirmedCount`(서버 canonical) | 그 업무 · 명 | 행이 없으면 `_capacityUnknown` | 표시 + 초대 CTA | O03 DAY-4 |
| `slot_batch_select_dialog:492` | **슬롯 문서 카운터** | 그 슬롯 · 명 | 문서 필드(항상 존재, 초기값 0) — UNKNOWN 개념 없음 | 표시만(선택 목록) | 슬롯 축은 transaction 으로 보장(§47-3) |
| `payroll_summary_model` · `payroll_overview_screen`(4곳) | 급여 요약 | **급여 건수** | 해당 없음 | 표시 | **N/A — 다른 도메인**(정원 아님) |
| `staffing_readiness_model:32/34/72/74`, `payroll_summary_model:65/67`, `available_workers_bottom_sheet:53` | — | — | — | — | **N/A — 선언/생성자** |
| 리스트 `.length` 12곳 | 목록 길이 | — | — | 표시·반복·빈 목록 판정 | **N/A — 정원/대기 수치로 쓰이지 않는다** |

미판정 행 없음. 정상 경로는 패치하지 않았다.

### 49-3. 사라진 wdId 의 옛 키 — 수정하지 않는다(계약으로 닫음)

키를 세 종류로 나눴다.

| 종류 | 현재 동작 | 판정 |
|---|---|---|
| ① 현재 정의에 있고 지원서가 0 | `srvBuildWdCountsUpdate` 가 **0 으로 깐다** | 6차에 닫힘 |
| ② 현재 정의에서 사라진 키 | 맵에 남지만 **아무도 읽지 않는다** | 저장 찌꺼기 |
| ③ 지원서가 옛 wdId 를 들고 있는 경우 | `callableUpdateSlotWorkDetails` 가 **활성 지원자 있으면 수정을 거부**한다 | 생성 경로 없음 |

②의 근거: `workDetailCounts` 를 **순회·합산하는 코드가 없다**(CF·클라이언트 전수
확인). 모든 읽기는 현재 업무 정의의 키로 하는 조회다 —
CF `getWorkDetailCount` 는 `wdc[wd.wdId]`, 클라이언트는 `lookupByIdentity` /
`countForDetail(canonicalId)`. 따라서 옛 키는 합계·gate·표시에 들어가지 않는다.

재집계는 dot-notation **부분 merge** 다(맵 전체 교체가 아니다). 그래서 옛 키가
남는다. 원장·이력 보존 계약상 그것이 맞다 — 과거 관계를 지우지 않는다.
**모든 옛 키 삭제·0 처리·새 migration 을 기본 해법으로 삼지 않는다.**

## 50. O05 — 증거 연결과 결손 보완

### 50-1. 계약 1 — 모호한 workType 단독 (이미 수행, 재실행 없음)

| 항목 | 값 |
|---|---|
| 테스트 | `scripts/r7-emu-c7-fallback.js` C7-7 |
| 입력 | 같은 workType 정의 2개 슬롯 + `workDetailId: '홀서빙'` |
| 기대 | 거부 |
| 결과 | `400` (`같은 업무 이름이 여러 개입니다. 목록에서 근무 시간을 골라 다시 시도해주세요.`) |
| 비공허 근거 | C7-1 pool 비어 있지 않음 · C7-2 업무별 후보가 **다름**(wd1 `[free]` / wd2 `[busy, free]`) |
| SHA | `57663a3` (regexp/unique 규칙), 8차 확인 재실행 |
| legacy 호환 | workType 단독은 **유일할 때만** 허용(C7-4 통과) — 기존 `srvResolveAppWdId` 계약과 동일 |

### 50-2. 계약 2 — unresolvable 400 의 caller 처리 (**결손 보완**)

서버 거부는 7차에 있었지만 **받는 쪽이 비어 있었다**:
`_parseError` 가 일반 문구(`인력 조회에 실패했습니다.`)로 떨어뜨려 서버가 넣어 둔
복구 안내를 지웠고, 오류 화면은 `다시 시도` 를 줬다 — 같은 식별자를 다시 보내므로
**무한히 같은 실패**가 된다.

| 변경 | 내용 |
|---|---|
| 안내 | `invalid-argument` 면 서버 message 를 그대로 보여준다(`목록을 새로고침한 뒤…` / `근무 시간을 골라…`) |
| 복구 | 그 경우에만 `다시 시도` → **`닫기`**. 복구 가능한 실패(권한·지역 미설정)는 `다시 시도` 유지 |
| 상태 | `_staleRequest` — 성공 시 해제 |
| 증거 | `test/available_workers_error_recovery_test.dart` 6건 / `a56ad70` |

빈 후보와 오류를 같은 화면으로 말하지 않는다(별도 블록) — 확인했다.

## 51. O07 — 배포 준비 (실행하지 않음)

### 51-1. 기준 산출물

| 구분 | 식별 |
|---|---|
| **old CF (실제 배포 기준)** | `adb6cbb` 의 `functions/src/index.ts` — 감사 변경 전. **아직 아무것도 배포되지 않았다** |
| **new CF** | `HEAD` = `8617663` — `functions/src/index.ts` 1파일 |
| old/new client | 같은 커밋 범위의 `lib/` 8파일 |

### 51-2. 배포 대상 전체 목록

변경 hunk 가 속한 export 를 추적한 결과:

| 대상 | 종류 | 변경 |
|---|---|---|
| `callableApplyToTO` | callable | 재활성화 시 대기 카운터 멱등 플래그 삭제 · 하루 경계 helper 통일 |
| `callableIncrementSlotPending` | callable | 카운터별 자기-값 음수 가드 · 주기 precondition |
| `callableRecalculateTOStats` | callable | 쓰기 모양 공유 · 슬롯별 transactional writer |
| `callableGetAvailableWorkers` | callable | KST 하루 경계 · unresolvable 거부 · 모호 workType 거부 |
| **`syncTOStats`** | **trigger** | 슬롯·업무 카운터 재계산(transaction) |

공유 helper(`srvResolveAppWdId`·`srvBuildWdCountsUpdate`·`srvSyncSlotCountersTx`·
`srvKstDayStartMs`·`srvOccupiesSeatToday`)는 같은 번들이므로 위 5개와 **함께** 나간다.
**함수 2개만 배포 대상으로 고정하지 않는다.**

### 51-3. 순서·중단·복구

| 단계 | 내용 |
|---|---|
| 1 | **CF 5개 배포**(callable 4 + trigger 1). client 는 아직 그대로 |
| 2 | 검증: 지원→취소→재지원 1주기에서 원장·`slot.pendingCount`·`totalPending`·`workDetailCounts` 4값 일치 / 후보 목록에서 같은 시간 확정자 제외 / 없는 workDetailId → 400 |
| 3 | client 배포 |
| 중단 기준 | `syncTOStats` 오류율 상승, `fail-closed` 경고 급증, `stale decrement 무시` 경고 급증, `callableGetAvailableWorkers` 400 비율 급증 |
| 복구 | **CF 만 되돌리는 것은 client 배포 후 금지**(§51-4). 되돌려야 하면 client 도 함께. forward-fix 는 §52 재집계 |

### 51-4. 방향별 호환 — 7차 실측 재사용

| 방향 | 지원 | 확정 | 취소 | 조회 | 재시도 | 최종 수렴 | 판정 |
|---|---|---|---|---|---|---|---|
| CF 먼저 교체, 아직 old client | 정상 | 정상 | 정상 | 정상 | 멱등 | **일치 12/12** | **권장** |
| new client 배포 후 **CF 만 old 로 rollback** | 정상 | 정상 | **주기 간 감소가 상위 카운터를 0 으로** | 원장 1인데 `대기 0` 표시 | 스스로 낫지 않음 | **11 FAIL** | **금지** |
| CF new 유지, client 만 old | 정상 | 정상 | 정상 | 정상 | 멱등 | 일치 | 안전 |
| 양쪽 rollback | 현행 | 현행 | 현행 drift | 현행 | — | 기준선 | 안전(개선 없음) |

`이중 차감·음수 없음`은 **일부 불변식**일 뿐이다. 금지 판정의 근거는
`to.totalPending`/`slot.pendingCount` 가 원장과 어긋난 값으로 **사용자에게 보이고
다음 원장 이벤트까지 자가 복구되지 않는다`는 사실이다.

**혼합 버전의 통제:** client 를 나중에 배포하므로 위험 구간은 "CF new × old client"
하나뿐이고 그 조합은 12/12 일치다. client 배포 후에는 CF 단독 rollback 을 막는 것이
통제 수단이다.

**사용자에게 보이는 동작 변경 1건:** 후보 조회가 맞출 수 없는/모호한 식별자에
`400` 을 준다. 구버전 client 는 일반 문구로 보여주고 `다시 시도` 를 준다
(8차 개선은 client 쪽이므로 CF 먼저 단계에서는 적용되지 않는다). 조용히 다른
업무의 후보를 보여주던 것보다 낫지만 **배포 노트에 적는다.**

## 52. O07 — 기존 21건 보정 준비 (실행하지 않음)

O06 진단을 반복하지 않는다. 7차 §43 결과를 기준으로 절차만 확정한다.

| 항목 | 내용 |
|---|---|
| 범위 | 영향 공고 **11개** / 업무키 mismatch **21건**(`wd.pendingCount` 9 · `wd.confirmedCount` 12) |
| 수단 | `callableRecalculateTOStats(toId)` — 7차 수정 후 슬롯 범위를 transaction 안에서 다시 센다 |
| dry-run | `scripts/r7-dev-read-reconcile.js` 가 곧 dry-run 이다(읽기 전용). `저장 → 기대` 표를 먼저 출력하고 그 차이만 바뀌는지 확인 |
| 기대 변경 | 과다 저장은 기대값으로 내려가고, 음수(`-6`·`-3`·`-2`)는 0 이상으로 교정된다. **원장은 건드리지 않는다** |
| 이력 보존 | 원장(`applications`)·`statusHistory` 미변경. 옛 wdId 키는 지우지 않는다(§49-3) |
| 멱등성 | 반복해도 같은 결과 — Emulator 확인(`r7-emu-f3-stale.js` S4, `r8-emu-to-total-race.js` T4) |
| 실패 후 재실행 | 슬롯 단위 transaction 이므로 부분 실패 시 그 슬롯만 다시 돌면 된다. 7차 수정에서 실패 슬롯이 있으면 `internal` 로 던져 조용히 넘어가지 않는다 |
| **실행 직전 절차** | 보정 직전에 **최신 원장을 다시 읽어** 대조표를 재산출한다. 이번 표는 2026-09-27T11:35Z 기준이다 |
| 이번 실행 | **없음.** 공유 DEV 보정은 하지 않았다 |

> **CF 반영만으로 21건이 복구된다고 표시하지 않는다.** 트리거는 그 슬롯에
> **다음 원장 이벤트가 올 때** 다시 센다. 이벤트가 오지 않는 슬롯은 그대로 남으므로
> 보정이 필요하다.
>
> 계약형(슬롯 없는) 공고 등 이번 조사 밖 범위를 전체 정상으로 확대하지 않는다.

Rules 축소와 `onBusinessDeleted` 는 기존 owner 에 그대로 둔다(변경 없음).

## 53. 최종 결론

### A. 개발 검증 완료 (CODE + Emulator/production-widget)

O01(슬롯축 닫힘·TO축 배치 근거+가드 테스트) · O02 · O03 · O03b · O04(a·b·c) · O05.
Emulator 하네스 **6개 전부 통과**(durability 29 · matrix3 25 · invitations 19 ·
c7 17 · compat 12 · to-total-race 11). Dart 스위트 **신규 실패 0**, 기존 실패 63건
동일(이름 기준 비교).

### B. DEVICE 로만 남은 것 (O08)

최소 한 묶음: **공고 탭 → 다중 날짜 카드에서 날짜 선택 → 머리말과 업무 행 숫자
일치 → 다른 날짜 → 원래 날짜 복귀 → 명단(일자별) 열기 → 닫기 → 탭 복귀.**

### C. 별도 실행 결정 (미실행)

DEV 배포(§51) · 과거 데이터 21건 보정(§52) · Rules 축소.

### D. 아직 개발 검증·수정이 안 끝난 critical

**없음.** O01 의 TO 축은 "미결"이 아니라 **배치 근거 + 계약 고정 테스트**로
관리되는 상태이며, 그 한계(반례 부재 ≠ 증명)를 §47-2 에 적었다.

따라서 **개발 감사 범위는 종료**한다. B·C 는 개발 완료로 세지 않으며 서로 다른
gate 로 관리한다.

---

# 9차 — O01 공고 합계 저장 순서 (2026-09-27)

기준: HEAD `48c93df`, 제품 코드 `8617663`(확인). 이번 대상은 **O01 하나**다.
O02~O06 은 **변경 없음, 기존 증거 재사용**. 71.8초는 8차의 정정(하네스 관측 지연)을
그대로 유지하고 성능 감사를 재개하지 않는다.

## 54. O01 세부축 종료 표

| O01 세부축 | 이전→현재 | 실제 보호 장치 | 변경/NO PATCH | 증거(SHA·테스트·read/commit 순서) | 남은 조건 |
|---|---|---|---|---|---|
| **TO 합계 · 절대 writer 간 저장 순서** | "배치 근거로 안전" → **결함 재현 → 수정** | 없었다(transaction 밖 읽기 + 무조건 update). 지금은 `srvCommitToTotals` 가 **읽기 시각 fence** | **변경** | 재현 `r9-run(pre)`: B +269ms(대기5) → A +923ms(대기6), 8초 무이벤트 후 원장5/저장6 · 수정 후 같은 순서 3/3 정합 · `test/to_total_write_contract_test.dart` 10건 | 없음 |
| **TO 합계 · delta writer(≈35곳)** | 미판정 → 판정 | `FieldValue.increment` + transaction/batch. 상대 연산이라 스냅샷 덮어쓰기의 주체가 아니다 | **NO PATCH** | 아래 §56-2 | 절대 쓰기에 지워질 수 있는 구조는 이전과 동일 — fence 로 복구가 더 확실해졌다 |
| **TO status(FULL/ACTIVE) 동반 쓰기** | 미판정 → 판정 | 합계를 건너뛰면 status 도 쓰지 않는다(같은 스냅샷의 판단) | **변경** | `to_total_write_contract_test.dart` B-4 | 없음 |
| **슬롯·업무 축** | 7차에 닫힘 | `srvSyncSlotCountersTx` — 읽기·쓰기 모두 transaction 안 | 변경 없음 | `r7-emu-f3-stale` · `to_total_write_contract_test.dart` C-1·C-2 | 없음 |

## 55. 8차 종료 근거의 정정

8차는 이렇게 적었다: "느린 일이 읽기 앞/쓰기 뒤에 있어 읽기→쓰기 간격이 짧다."
그건 **창을 줄이는 설명**이고, 서로 다른 invocation 의 저장 순서를 직렬화하지 않는다.
그리고 8차의 시도는 그 순서를 시험하지 못했다 — 이유가 코드에 있다:

| 8차 T2 | 값 | 왜 시험이 안 됐는가 |
|---|---|---|
| fixture | 지원서 483건 | 스캔 질의가 `limit(499)` 라 **1페이지**. 읽기→쓰기 사이에 남은 페이지가 없다 |
| 취소 시점 | 호출 +700ms | 그때 이미 TO 쓰기가 끝나 있었다(그 뒤는 슬롯 transaction 구간) |

그래서 8차의 세 순서 PASS 와 배치 guard 는 **그 범위의 회귀 증거로만** 유지하고,
TO 경합 전체 CLOSED 의 근거로 쓰지 않는다. 9차에 그 창 안쪽에 B 를 넣었다.

## 56. 실제 보호 장치 조사 (수정 전)

### 56-1. 절대 writer 3곳 — 무엇을 읽고 언제 쓰는가

| writer | 읽는 데이터·범위 | 스냅샷 취득 지점 | TO commit 지점 | transaction read set | revision/precondition | 공유 직렬화 |
|---|---|---|---|---|---|---|
| `_syncTOCounters` 비슬롯 (17747) | 공고 전체 확정 지원서(페이지네이션) + 대기 `count()` | `Promise.all` 시작 | 그 직후 `toRef.update` | **없음** (transaction 밖) | **없음** | **없음** |
| `_syncTOCounters` flex (17787) | 같음 + 슬롯 문서 1건 | `Promise.all` 시작 | 그 직후 `toRef.update` | **없음** | **없음** | **없음** |
| `callableRecalculateTOStats` (24501) | 공고 전체 지원서 **while 페이지네이션** | **첫 페이지** 읽는 순간 | 스캔이 전부 끝난 뒤 `update` | **없음** | **없음** | **없음** |

세 번째가 핵심이다. 값의 신선도는 **첫 페이지**가 정하고 쓰기는 **마지막 페이지 뒤**다.
한 공고의 지원서가 499건을 넘으면 그 사이에 페이지 읽기가 들어간다 — 그게 창이다.
`tos` 문서만 transaction 으로 읽고 원장은 밖에서 읽는 구조였으므로,
"TO 문서의 변경 조건"으로는 원장 변경을 알 수 없었다.

### 56-2. delta writer ≈35곳 — 같은 보호 계약인가

전수 위치: 3770 · 20350 · 20627 · 20826 · 23464~23482 · 25236 · 25861~25863 ·
26792 · 26978 · 28371 · 28741~28749 · 28864~28986 · 32292 · 32306 · 35478 ·
36210 · 36709 · 37225 · 37330 · 37833 · 38004 · 40930 · 41016.

전부 `FieldValue.increment` 이고 transaction 또는 batch 안이다. 상대 연산이라
"먼저 읽은 값으로 덮는" 주체가 될 수 없다. 반대 방향(절대 쓰기가 delta 를 지우는 것)은
이전에도 있었고 복구 경로는 그대로다 — 원장 변경이 트리거를 깨우고, 그 트리거의
읽기 시각이 더 최신이므로 fence 아래에서 **그 값이 이긴다**. 즉 delta 는
패치 대상이 아니고, 이번 수정으로 delta 의 복구가 더 확실해졌다.

## 57. 순서를 만든 방법 (제품에 주입 없음)

`scripts/r9-emu-to-order.js`. 제품 코드에 sleep·테스트 분기·별도 정책을 넣지 않았고,
재집계/트리거 owner 를 복제하지도 않았다. 제어는 fixture 와 사후 검증으로 한다.

1. **대상 지원서의 docId 를 가장 앞에 둔다.** 스캔 질의(`toId==`·`businessId==`·
   `limit(499)`)에 orderBy 가 없으므로 Firestore 가 `__name__` 오름차순을 붙인다
   → 대상은 **1페이지**에서 읽힌다.
2. **ballast 4000건**으로 스캔을 9페이지로 만든다. 1페이지 읽기와 TO 쓰기 사이에
   남은 8페이지가 들어간다.
   ballast 는 `status` 필드가 없다 — 제품 트리거가 스스로 건너뛰는 모양이라
   (`beforeStatus === afterStatus` → return, 17380) seeding 이 트리거 폭풍을 만들지 않고,
   카운터에는 0 을 기여한다. 스캔 루프의 분기는 `status` 없음과 `CANCELED` 가 **같다**
   (24427~: `isPending` false, `CONFIRMED_STATUSES.includes` false) — 재현은 ballast 의
   status 에 의존하지 않는다. **제품 전제조건은 "한 공고의 전체 지원서 > 499" 하나다.**
3. **트리거 큐를 먼저 비운다.** 이것이 1차 시도에서 틀렸던 부분이다 — 큐가 밀린 상태의
   실패는 "B 가 아직 실행되지 않음"이지 요청된 순서가 아니다.
   canary 지원서의 status 를 `CANCELED ↔ AUTO_CANCELED` 로 번갈아 쓰고
   (둘 다 대기도 좌석도 아니라 기대값이 변하지 않는다) 트리거 왕복이
   1500ms 아래로 내려올 때까지 기다린다. 실측 배수 60~65초, 이후 왕복 **212~220ms**.
4. **창 안에서 원장만 바꾼다**(취소). 파생값은 건드리지 않는다.
5. **순서는 기록으로 판정한다.** TO 문서 listener + 100ms polling 으로 서버 커밋 시각
   (`snapshot.updateTime`)을 전부 남긴다. 누가 썼는지는 `statsUpdatedAt` 으로 갈린다 —
   **트리거만** 쓰는 필드이고 재집계는 쓰지 않는다.
   A 가 무엇을 계산했는지는 callable 응답값으로 확인한다.

적용한 지연은 제품의 읽기·쓰기 의미를 바꾸지 않는다. ballast 는 읽는 **양**만 늘리고,
canary 는 트리거를 한 번 더 깨우는 것뿐이며, 취소는 실제 도메인 전이다.
순서 성립 여부는 매 시도마다 사후 검증한다(A 가 취소 전 값을 계산했는가 ·
B 가 최신값을 먼저 커밋했는가 · A 의 쓰기가 그 뒤에 왔는가). 하나라도 아니면
PASS 가 아니라 **INCONCLUSIVE** 로 남긴다.

## 58. 재현 (수정 전 `cef98de~1`)

같은 스크립트를 수정 전 코드에 다시 돌린 기록이다(`r9-before-final`, 시도 k=1).

| 시각(호출 기준) | TO 커밋 | `statsUpdatedAt` | fence skip | 누가 |
|---|---|---|---|---|
| −710ms | 대기 5 | …835834 | — | 취소 전 상태 |
| +259ms | — | — | — | **취소 커밋** (원장 대기 4) |
| **+396ms** | **대기 4** | …836996 **전진** | — | **B = 트리거** (취소 후 원장) |
| **+890ms** | **대기 5** | …836996 **그대로** | **0건** | **A = 재집계** (취소 전 스냅샷) |
| 이후 8초 | 커밋 없음 | — | — | 후속 도메인 이벤트 없음 |

A 의 응답값도 `{totalPending: 5}` = 취소 전 원장이었다.
최종: **원장 대기 4 / 저장 5.** 자가 복구되지 않았다.

같은 실행의 시도 k=0 은 A 가 B 보다 **먼저** 썼다 — 그건 요청된 순서가 아니므로
PASS 도 FAIL 도 아닌 INCONCLUSIVE 로 분류됐다(판정 기준이 두 경우를 가른다).

1차 재현(첫 실행)도 같은 모양이었다: B 대기5 @+269ms → A 대기6 @+923ms,
원장 5 / 저장 6.

대조(R9-3): 새 원장 이벤트를 하나 주면 **626ms 에 정정**됐다.
→ 트리거 고장이 아니라 **저장 순서** 문제다.

### 잘못 닫을 수 있었던 지점 — 기록으로 남긴다

첫 시도에서 하네스는 "원장 5 / 저장 6" 을 만들었지만 그때 **트리거는 실행조차
되지 않았다**(`statsUpdatedAt` 이 전 구간 null). ballast 4000건 생성이 만든
no-op 트리거 이벤트가 큐에 밀려 있었기 때문이다. 그 실패는 "B 가 아직 실행되지
않음"이고 요청된 순서가 아니다 — 그것으로 결함을 주장하지 않았고, 큐 배수
장치를 넣은 뒤 다시 만들었다.

**결론 1: 이전 snapshot 의 마지막 commit 은 가능하다 — 추론이 아니라 확인된 사실이다.**
(커밋 시각·작성자 지문·A 의 응답값이 모두 기록으로 남아 있다.)

## 59. 수정 — 읽기 시각 fence

무엇이 막지 못했는가: 아무것도. 그래서 고쳤다. 선택안을 비교했다.

| 선택안 | 정확성 | 기존 writer 호환 | 비용 | 판정 |
|---|---|---|---|---|
| 원장 읽기를 transaction 안으로 | 정확 | delta 와 무관 | 공고 전체(수천 건) 읽기를 tx read set 에 넣는다 → 모든 지원서 쓰기가 이 tx 와 경합·재시도 | **기각** — 트리거는 상태 변경마다 돈다 |
| `lastUpdateTime` precondition(문서가 바뀌었으면 거부) | **부정확** | — | 저렴 | **기각** — 나중에 쓴 낡은 writer 때문에 **더 최신 쪽이** 거부되어 틀린 값이 남는 경우가 생긴다 |
| **읽기 시각 fence**(값과 함께 그 값을 만든 서버 읽기 시각을 적고, 더 낡으면 쓰지 않는다) | 정확 | delta 불변 · 구버전은 필드를 무시 | TO 문서 tx 1회(읽기1·쓰기1) 추가 | **채택** |

기준은 누가 먼저 썼는지가 아니라 **누가 더 최신 원장을 보았는지**다.

- `srvCommitToTotals(toRef, sourceReadAt, totals)` — transaction 안에서
  저장된 `statsSourceReadAt` 과 비교해 더 낡거나 같으면 쓰지 않고 로그를 남긴다.
- `srvEarliestReadAt([...])` — 값의 신선도는 **가장 오래된 입력**이 정한다.
  페이지네이션은 **첫 페이지**의 `readTime` 만 기억한다(`page.readTime`,
  `AggregateQuerySnapshot.readTime` — 서버 읽기 시각이다).
- 절대 writer **3곳 전부** 이 하나를 지나간다. 우회 쓰기는 남기지 않았다.
- 합계를 건너뛰면 **status 도 쓰지 않는다** — 같은 낡은 스냅샷에서 나온 판단이다.
- 재집계 응답에 `applied` 를 넣었다. `false` 는 실패가 아니라 "더 최신 값이 이미
  저장돼 있다". 클라이언트 두 호출부는 응답값을 쓰지 않으므로 변경 없다
  (`application_firestore.dart:814`, `firestore_service.dart:519`).
- 슬롯·업무 카운터는 fence 와 무관하게 쓰기 시점에 다시 센다 — 그대로 둔다.

원장의 identity·좌석 정책·모집단은 바꾸지 않았다.

## 60. 수정 후 (`cef98de`) — 같은 스크립트·같은 제어 순서

| 시도 | 취소 시점 | A 계산(취소 전) | B 먼저 최신 커밋 | A 가 그 뒤에 씀 | 저장 = 원장 |
|---|---|---|---|---|---|
| R9-2.0 | +154ms | 대기 6 | 대기 5 @+321ms | **skip 1건**(쓰기 사라짐) | ✔ 5 |
| R9-2.1 | +255ms | 대기 5 | 대기 4 @+421ms | **skip 1건** | ✔ 4 |
| R9-2.2 | +384ms | 대기 4 | 대기 3 @+660ms | **skip 1건** | ✔ 3 |

`failures=0`. 수정 후에는 A 의 커밋이 **아예 나타나지 않는다** — fence 가 막고
CF 가 `[srvCommitToTotals] 낡은 스냅샷 — 건너뜀` 을 남긴다. 그 로그 증가분이
"A 가 B 뒤에 쓰려 했다"의 증거다(문서만 보면 사라진 쓰기는 보이지 않는다).
수정 전 같은 위치의 skip 은 **0건**이다 — 같은 지표가 두 경우를 가른다.

보호 장치 때문에 A 가 충돌·재시도·거부된 결과는 이렇다: **A 는 거부되지 않고
성공(200)으로 끝나며, 합계만 쓰지 않는다.** 응답의 `applied=false` 가 그 사실이고
슬롯·업무 카운터는 그대로 다시 센다. 보호 장치를 우회해 결함을 만들지 않았다.

**결론 2: 무엇이 막는가 — `srvCommitToTotals` 의 읽기 시각 비교다.**
코드 위치를 지목할 수 있고, 그 비교가 없으면 §58 이 재현된다.

**결론 3: 기존 TO 합계 writer 는 모두 보호 계약에 연결됐다.**
절대 3곳은 fence 를 지나가고(테스트가 개수까지 고정), delta ≈35곳은 상대 연산으로
계약 밖이며 그 복구 경로가 fence 아래에서 더 확실해졌다.

## 61. 회귀 — 영향 경로의 기존 하네스 재사용

이유 없는 전 테스트 재조사는 하지 않았다. 카운터 쓰기 경로에 닿는 것만 돌렸다.

| 하네스 | 무엇을 지키는가 | 결과 |
|---|---|---|
| `r7-emu-durability` (F1) | 두 단계 취소의 내구성 | `failures=0` |
| `r7-emu-matrix3` (F2·전이) | 상태 전이 25건 | `failures=0` |
| `r7-emu-f3-stale` | 슬롯 축 stale overwrite | `failures=0` |
| `r8-emu-to-total-race` | 8차가 만든 세 순서 | `failures=0` |
| `r7-emu-compat` | 방향별 호환 12건 | 1차 `failures=1` → 원인 규명 후 재실행 `failures=0` (아래) |
| `r7-emu-invitations` | 초대 경로 19건 | `failures=0` |
| `test/to_total_write_contract_test.dart` | 새 계약(fence) 10건 | 통과 |
| `r7-emu-c7-fallback` | 후보 조회 | **미실행 — 이번 변경과 무관한 경로** |

fence 는 이 회귀들 안에서도 실제로 작동했다: `[srvCommitToTotals]` skip 로그 7건,
transaction 오류 0건. 즉 낡은 쓰기를 막으면서 어느 시나리오도 굶기지 않았다.

### Dart 전체 스위트 — 65건 실패, 이번 변경과 무관함을 확인한 방법

`+13706 ~2 -65`. 8차 기록은 63 이었다. **2건 차이를 이름으로 특정하지는 못했다**
(8차의 실패 이름 목록을 보관하지 않았다). 대신 이번 변경의 영향 범위로 가렸다:

1. 이 변경이 닿을 수 있는 유일한 경로는 "CF 소스 문자열을 읽는 테스트"다.
   실패 파일 중 그런 것은 7개(10건)였고, **`functions/src/index.ts` 만 수정 전으로
   되돌려 같은 7파일을 다시 돌렸더니 결과가 동일했다**(둘 다 `+294 -10`).
2. 나머지 실패 파일은 CF 소스를 읽지 않으므로 CF 전용 변경의 영향 밖이다.
3. 이번에 계약을 다시 쓴 `to_total_write_contract_test.dart` 는 10/10 통과한다.

다음 비교를 위한 **기준선을 여기 남긴다**(파일(건수), 총 65건/19파일):
`unit/week_helper(11)` `unit/payment_due_date_calculator(11)`
`models/application_model(10)` `unit/to_model(6)` `payroll_simulation_extended(6)`
`simulation/weekly_work_count(3)` `renewal_decision_surface(3)`
`my_applications_simulation(3)` `noshow_replacement_cross_slice_contract(2)`
`utils/trust_score_helper(1)` `unit/user_model(1)` `simulation/trust_noshow_simulation(1)`
`simulation/super_admin_settings_simulation(1)`
`simulation/admin_setup_worktype_wage_simulation(1)` `posting_close_reopen_contract(1)`
`mixed_staffing_parity(1)` `longterm_renewal_boundary(1)`
`invitation_detail_projection(1)` `admin_home_expiring_permission(1)`

### compat 1차 실패의 원인 — 제품이 아니다

어긋난 값은 `workDetailCounts.pendingCount`(업무 축) 1건이고, **fence 가 건드리지
않는 축**이다(그 축은 `srvSyncSlotCountersTx` 가 쓰고 트리거의 fence 앞에 있다).
원인은 실행 순서였다: 바로 앞 `r9-emu-to-order` 의 cleanup 이 ballast 4008건을
삭제하면서 no-op 트리거 이벤트를 수천 건 남겼고, compat 의 첫 취소 트리거가
25초 대기 안에 실행되지 않았다. **트리거 실행 수가 멎을 때까지 기다린 뒤
같은 하네스를 다시 돌려 `failures=0`** 을 확인했다.
`r9-emu-to-order.js` 헤더에 "같은 세션에서는 마지막에 두거나 에뮬레이터를 다시
띄운다"를 적어 두었다 — 같은 착시를 다음에 또 겪지 않기 위해서다.

## 62. O07 문서 갱신 — 달라진 부분만

배포 대상 목록은 **그대로다**(8차 §51-2: callable 4 + 트리거 `syncTOStats` +
같은 번들의 `srv*`). 이번 수정은 그 중 트리거와 재집계 **내부**에 있다.

| 항목 | 갱신 |
|---|---|
| new CF | `8617663` → **`cef98de`** |
| 새 필드 | `tos/{id}.statsSourceReadAt` — CF 만 쓴다. 클라이언트·rules 는 읽지도 쓰지도 않는다(`lib/` 전수 확인) |
| 클라이언트 변경 | **없음.** 재집계 응답에 `applied` 가 추가됐지만 두 호출부 모두 응답값을 쓰지 않는다 |
| 혼합 구간(CF 먼저) | 구 CF 는 `statsSourceReadAt` 을 갱신하지 않는다 → 그 구간에서는 보호가 부분적으로만 작동한다(= **현행 동작**). 새로운 위험은 없다 |
| rollback 제약 | **변하지 않는다.** client 배포 후 CF 단독 rollback 금지(8차 §51-4) |
| 비용 | 절대 쓰기마다 TO 문서 transaction 1회(읽기1·쓰기1) 추가 |
| 기존 21건 보정 | **영향 없다.** 그 21건은 `workDetailCounts`(슬롯 축)이고 `srvSyncSlotCountersTx` 가 쓴다 — fence 와 무관하다. 재집계 응답의 `applied=false` 는 실패가 아니다 |

## 63. O02~O06 — 변경 없음

| ID | 상태 |
|---|---|
| O02 로더 통합 | 변경 없음, 기존 증거 재사용(7차 `fa65d3c`) |
| O03 production 화면 왕복 | 변경 없음, 기존 증거 재사용(8차 `ee69e60`) |
| O04 writer·consumer 판정 | 변경 없음. TO 합계 writer 판정만 9차에서 **강화**됐다(§56) |
| O05 후보 오류 복구 | 변경 없음, 기존 증거 재사용(8차 `a56ad70`) |
| O06 DEV READ | 변경 없음, 재실행하지 않음(7차 §43) |

71.8초는 8차의 정정(하네스 관측 지연)을 유지한다. 성능 감사를 재개하지 않았다.

## 64. O01 종료 판단

**결론 4: CODE/Emulator 수준에서 O01 을 닫을 근거가 충족됐다.**
재현 → 수정 → 같은 순서 재실행으로 통과 → 보호 장치를 코드로 지목 →
writer 전수 연결 → 영향 경로 회귀 재사용.

O01 의 남은 것은 없다. 배포·기존 데이터 보정·DEVICE(O08)는 별도 실행 단계다.
