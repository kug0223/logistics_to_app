# ALfit Product Continuity Index

> 세션·단계가 바뀌어도 **무엇이 어디까지 닫혔고 무엇이 누구 소유인지** 한 장에서 잇는다.
> 세부 근거는 각 감사 문서에 있고 이 파일은 **포인터와 상태**만 유지한다.
> 마지막 갱신: 2026-09-30 · 기준 HEAD: **R7-P4.4E.2A** (readiness authority)

## 0-AAAAAAAAAAA. CURRENT SNAPSHOT — 2026-09-30 / R7-P4.4E.2A

기준 `5011408`. **CODE CLOSED · CF 변경 0 · DEVICE RETRY PENDING.**

### §3 핵심 질문의 답 — **NO**

"Home 을 한 번도 그리지 않고 공고 탭으로 바로 들어가도 Posting 이 스스로
readiness 를 얻을 수 있는가?" → **얻을 수 없었다.**

`FirstPostingReadinessBroadcast` 의 producer 는 **Home 하나**였다
(`business_admin_home_screen:546` 의 publish). 공고 root·CreateTO 는 소비자였고,
`clear()` 는 **아무도 부르지 않았다**. 즉 Home 위젯 생명주기에 의존하는
전달값이지 앱 전역 projection 이 아니었다. **구조 결함**이다.

동시에 §6 위반도 있었다 — `null`(모름)일 때 정상 운영 UI(목록 + `+`)를
그렸다. UNKNOWN 을 READY 처럼 보여준 것이다.

### 고친 구조 (§10)

```
FirstPostingReadinessResolver   ← 판정 한 벌 (화면 밖)
        ↓
FirstPostingReadinessStore      ← uid · scopeKey 가 붙은 projection
        ↓
Home (setup UX owner) · 공고 root · CreateTO
```

- **Home 은 계속 setup UX 의 owner** 다. 전체 체크리스트와 각 단계로 가는 길은 Home 에만 있다. 바뀐 것은 **사실을 누가 계산하는가** 뿐이다.
- 공고 root 가 `_ensureReadiness()` 로 **스스로 묻는다**. 입력(어느 사업장·호출자 날인)만 모으고 술어는 resolver 를 쓴다 — §11 의 재계산 복제 없음.
- 같은 scope 면 다시 세지 않고, 동시에 여러 화면이 물어도 한 번만 센다.

### 상태 의미 분리 (§5·§6)

`null` 하나에 섞여 있던 뜻을 나눴다.

| status | 뜻 | 공고 root |
|---|---|---|
| `idle` | 아무도 아직 묻지 않았다 | 로딩 |
| `loading` | 세고 있다 | 로딩(이전 값 유지 — 깜빡이지 않음) |
| `resolved` + `!allReady` | 준비 미완료 | setup surface, `+` 없음 |
| `resolved` + `allReady` | 준비 완료 | 정상 목록/empty, `+` 있음 |
| `failed` | 세다가 실패 | "확인하지 못했어요" + 다시 확인, `+` 없음 |

**실패는 준비 미완료가 아니다.** 모름도 0건이 아니다.

### scope (§8·§9)

판정에 **누구의·어느 사업장 집합** 인지를 함께 남긴다(`uid` + `scopeKey`).
`matches()` 가 아니면 값을 쓰지 않고 다시 센다.

**§9 BLOCKER 였다** — `reset()` 을 부르는 곳이 코드 전체에 **0곳**이었다.
`UserProvider.signOut()` 에 연결했다. 남의 사업장 판정으로 내 `+` 버튼이
정해지면 안 된다.

### lifecycle 판정 (§4)

| 경우 | 결과 |
|---|---|
| A. cold start → 공고 직행 | **안전** — `_ensureReadiness()` 가 스스로 묻는다 |
| B. 복원 시 공고 탭 선택 | **안전** — 동일 + 앱 복귀 시 `force: true` 재조회 |
| C. Home 미방문 | **안전** — A 와 같다 |
| D. 사업장 A→B 전환 | **안전** — `scopeKey` 불일치 → 재계산 |
| E. logout → 다른 관리자 login | **안전** — `signOut` 에서 `reset()` |
| F. 선행 완료 후 Home 없이 복귀 | **부분** — Home 이 owner 라 그 경로로 돌아오면 갱신된다. 앱 복귀 시에도 강제 재조회. 포그라운드에서 Home 을 거치지 않고 바뀌는 경로는 남는다 |

### 갱신한 오래된 테스트 12건 (삭제·skip 0)

전부 **판정 코드가 Home 파일 안에 있다**고 고정하던 것이다. 로직은 한 글자도
바뀌지 않았고 위치만 옮겼다. `home` 소스를 볼 때 resolver 를 함께 보도록
했고, 지역 변수명은 도메인 이름(`readinessMap`)으로 통일해 기존 needle 을
살렸다. `_reads.postingReadiness(` → tear-off 로 넘기는 모양이 된 것만
needle 을 고쳤다(조회 지점 1개라는 계약은 그대로).

### 증거

- **CODE**: `flutter analyze` No issues · **CF 변경 0**
- **RENDER**: 신규 **29/29**(SETUP-ROOT-01~07 · LICENSE-PARITY · READINESS-TASKS · NAV/REFRESH · **BROADCAST-01~07**)
- **DEVICE**: **RETRY PENDING**



## 0-AAAAAAAAAA. CURRENT SNAPSHOT — 2026-09-30 / R7-P4.4E.2

기준 `a841c40`. **CODE CLOSED · CF 변경 0 · DEVICE RETRY PENDING.**

### 한 사업장, 세 가지 다른 말

실기기에서 같은 사업장을 두고 세 화면이 서로 다른 말을 했다.

| 화면 | 말한 것 | 실제 |
|---|---|---|
| Home | "공고 등록까지 3단계 남았어요" (1/4) | 맞음 |
| 공고 root | "등록된 공고가 없습니다" + `+ 새 공고 등록` | **할 수 없는 행동으로 안내** |
| CreateTO | 카드 5개 · **사업자등록증 미등록** | **틀림 — 서버는 READY** |

### BLOCKER — 같은 등록증을 두고 다른 진실 (§33)

`create_to_screen` 이 license 를 **인라인으로 다시 판정**하고 있었다. 그 술어는
owner 문서의 `businessLicenseImageUrl`(레거시 URL)만 봤는데, 서버가 기록하는
canonical 은 `businessLicenseImagePath` 이고 `callableRegisterBusinessLicense`
는 등록 시 레거시 URL 을 **지운다**(R8-P5.1). 그래서 신규 등록 사업장은
Home·서버가 READY 인데 이 화면만 NOT_READY 였다.

같은 파일 안 다른 자리는 이미 공용 resolver(`hasLicenseForBusiness`,
path 우선 → URL 폴백, 서버와 같은 순서)를 쓰고 있었다 — **술어를 한 벌로
합쳤다.** E.1A 가 등록증을 owner 경로로 옮기면서 이 중복이 드러난 것이다.

### CORRECTION — 공고 root 가 setup 을 몰랐다 (§34)

`JobsRootScreen` 에는 readiness 분기가 **하나도 없었다.** 사업장이 생기는
순간 정상 운영 empty state 로 들어갔고 `+` 는 권한만 봤다.

§6 대로 **새 술어를 만들지 않았다.** Home 이 계산한 `FirstPostingReadiness`
를 `FirstPostingReadinessBroadcast` 로 흘려 공고 root 가 같은 값을 본다.
계산은 여전히 Home 한 곳에서만 한다.

- `!allReady` → setup surface + `+` **제거**(§11: disabled 는 이유를 말하지 못하고, 같은 화면에 이미 recovery CTA 가 있다)
- `null`(아직 모름) → **화면을 바꾸지 않는다**(§25 — UNKNOWN ≠ SETUP_REQUIRED)
- 탭 자체는 유지(§8)

### §15 — CreateTO 가 두 번째 task owner 였다

큰 카드 5개 + 긴 설명을 **compact blocker** 로 바꿨다(186줄 → 67줄).
남은 개수는 Home 이 센 값을 그대로 쓴다 — 여기서 다시 세면 4 vs 5 가 된다.
`사업자등록증` 을 사용자 task 로 다시 세우지 않는다(§24).
**§16 은 이미 구현돼 있었다** — `_allPrerequisitesMet` 이면 자동 unlock(452줄).

안내 문구의 **소유자 이동**도 같이 처리했다: 제거한 카드에만 있던
"한 번 만들면 이후 계약에도 계속 사용할 수 있어요" 를 Home 의 템플릿 행으로
옮겼다. 소유자가 바뀐 것이지 안내가 필요 없어진 것이 아니다.

### §19~§22 Workforce / Payroll — **POLICY UNVERIFIED (PATCH 없음)**

두 root 모두 이미 UNKNOWN 과 ZERO 를 구분한다(`_attCountsUnknown ? '확인 못함' : '데이터 없음'`).
setup gate 를 붙이려면 "운영 이력이 있었는가" 라는 새 술어가 필요한데,
§21 의 반례(운영 중 사업장 + 템플릿 삭제 → posting NOT_READY 지만 기존 약속은
살아 있어야 한다)가 `FirstPostingReadiness` 를 그 입력으로 쓸 수 없음을 보인다.
§22 대로 근거가 불충분하므로 **POLICY UNVERIFIED 로 남기고 patch 하지 않았다.**

### 갱신한 오래된 테스트 8건 (삭제·skip 0)

제거한 구조를 고정하던 불변식들이다. 성질은 살리고 자리만 옮겼다.

| 테스트 | 무엇이 깨졌나 | 어떻게 갱신했나 |
|---|---|---|
| BAR-70 · FPR-50 · HRR-52 | `cardCount = isSubAdmin ? 4 : 5` | gate 판정은 유지, 카드 수 대신 "CreateTO 는 task owner 가 아니다" |
| FUG-20 · FUG-22 | 제거한 카드의 안내 문구 | 소유자를 Home 으로 이동(문구도 실제로 옮김) |
| FPR-24 | `_templateTargetBusinessId` | Home 의 `_templateCtaBusiness` 가 미승인까지 폴백 = 승인 종속 아님 |
| HRR-52 | `onAction: _businessApproved` | CreateTO 는 더 이상 task CTA 를 소유하지 않는다 |
| permission ×2 | `PermissionCheck.allowed)` 의 **닫는 괄호** | 조건이 하나 더 붙어도 "select 로 구독한다" 성질을 본다 |

### 증거

- **CODE**: `flutter analyze` No issues · **CF 변경 0**
- **RENDER**: 신규 **18/18**(SETUP-ROOT-01~06 · LICENSE-PARITY-01~04 · READINESS-TASKS-01~04 · NAV/REFRESH)
- **DEVICE**: **RETRY PENDING**



## 0-AAAAAAAAA. CURRENT SNAPSHOT — 2026-09-30 / R7-P4.4E.1A

기준 `3748c62`. **CODE CLOSED · CF 변경 0(배포 불필요) · DEVICE RETRY PENDING.**

### 찾은 것 — 신규 사업장 등록이 구조적으로 불가능했다

실기기 로그가 직접 말했다:
`[firebase_functions/not-found] 사업장을 찾을 수 없습니다.`

`callableUploadBusinessImage` 는 `assertBizAdmin` 으로 **사업장 문서 존재**를
요구한다(`if (!bizSnap.exists) throw not-found`). 그런데 신규 등록은 그 문서를
**업로드 뒤에** 만들었다(`uploadBizId = .doc().id` → 업로드 → `batch.set`).
등록증이 신규 필수라 업로드는 반드시 실행됐다 → **항상 실패**.

`af1a6f5`(2026-07-17, "businesses/ 직접 업로드 CF 이전") 부터다. 그 전에는
클라이언트가 Storage 에 직접 썼기에 사업장 없이도 올라갔다. 보안 수정 자체는
옳았고, **신규 생성이라는 한 경우를 빠뜨린 것**이다. P4.4E 배포와 무관하다.

### 기각한 안 — §6 negative control

내가 먼저 제안했던 "역할 + `managedBusinessIds < 5` 만 보고 pre-create 허용"은
**기각한다.** 그 조건에는 호출자를 특정 id 에 묶는 것이 없고, 사업장이 끝내
만들어지지 않으면 quota 는 영원히 0 이다 → 임의 id A·B·C… **무제한 업로드**가
전부 통과한다. Business quota 를 Storage abuse quota 로 재사용할 수 없다(§7).

### 채택 — 기존 primitive 재사용 (새 entity 0, 새 업로드 표면 0)

§4 가 요구한 "이미 있는 구조"가 실제로 있었다. 서류 관리 화면은 **사업장 없이**
등록증을 처리한다: `users/{uid}/businessLicense_*` 직접 업로드(Storage rules 가
본인 경로·5MB·이미지 MIME 로 이미 제한) → `callableRegisterBusinessLicense` 가
소유권·존재 확인 후 `businessLicenseImagePath` 를 **서버가** 기록.
`checkBusinessLicense` 의 owner 분기가 이미 인정하는 값이다.

신규 등록 순서를 그 위에 맞췄다:

| 순서 | 내용 | 사업장 필요? |
|---|---|---|
| ① 등록증 | `users/{uid}/businessLicense_*` → `callableRegisterBusinessLicense` | 아니오 |
| ② 사업장 생성 | `batch.set(businesses) + users.managedBusinessIds` | — |
| ③ 표시용 이미지 | 기존 `callableUploadBusinessImage` → `businesses/{id}.update` | 예(이미 있음) |

①이 ②보다 먼저인 것이 중요하다 — `onBusinessCreated` 의 자동승인이 등록증을
본다. 나중이면 놓친다.

**`callableUploadBusinessImage`·`assertBizAdmin`(83개 호출처)은 건드리지 않았다(§3).**
수정 모드는 무변경.

### 부분 상태 정책

③ 실패는 등록을 되돌리지 않는다. 대표·추가·교통 사진은 **선택 항목**이고
등록의 본체(사업장 + 등록증)는 이미 성립했다. 되돌리면 사용자가 처음부터
다시 입력해야 한다 — 잃는 것이 크다. 대신 "사업장은 등록됐지만 사진을 올리지
못했습니다" 로 **따로** 말한다.

### §12 — 원인이 세 번 삼켜지던 자리

`StorageService → null` / 폼 `throw '이미지 업로드에 실패…'` / 최종 catch
`'저장하지 못했습니다'`. 이제 **할 일이 다른 것만** 구분한다: 재선택 /
재시도 / 권한 / 네트워크 / 마무리 미완. 내부 코드·경로는 여전히 노출하지 않는다.

### 증거

- **CODE**: `flutter analyze` No issues · Functions `tsc` 통과 · eslint **4973**(기준선 동일, **CF 변경 0**)
- **RENDER**: 신규 **18/18**(PRECREATE-01~10 + R8-P5.1 회귀 3) · 전체 스위트 **14859 통과 / 실패 0 / skip 2**
- **DEV DEPLOY**: **불필요** — `functions/` 변경 0건
- **DEVICE**: **RETRY PENDING** — 실기기 재시도로만 닫힌다

### 남긴 것

`[R7-P4.4E.1A-STAGING-ORPHAN-TTL]` — ①에서 업로드는 됐는데 CF 등록이 실패하면
즉시 지운다. 다만 그 사이 앱이 강제 종료되면 `users/{uid}/` 에 객체가 남는다.
새로 생긴 위험은 아니다(서류 관리 화면이 같은 성질을 이미 갖는다) — 서버 TTL
정리는 별도 owner.



## 0-AAAAAAAA. CURRENT SNAPSHOT — 2026-09-30 / R7-P4.4E

기준 `edb22fc`. **E1 = DEV DEPLOY VERIFIED · E2 = FIRST-RUN RUNTIME PENDING USER FLOW.**

### 배포된 exports (9개, 명시 target 만)

commit range 를 배포 대상으로 쓰지 않았다. 마지막 배포 기록 이후 코드 커밋
(`e0c620c` → `edb22fc`)의 **변경 라인 404줄**을 감싸는 top-level 심볼을 찾고,
helper 면 호출자를 따라 올라가 export 집합을 계산했다.

| export | 배포 근거 |
|---|---|
| `callableCreateTO` | `assertBusinessPostingReady` + `delete finalData.dates` |
| `callablePublishTO` | `assertBusinessPostingReady` |
| `callableUpdateTO` | `assertBusinessPostingReady` (reopen `txReopenUpdates` 포함) |
| `masterScheduler` | `processScheduledPublish` — 판정이 TX read-set 으로 |
| `callableApplyToTO` | `assertBusinessCanAcceptApplications` |
| `callableConfirmApplication` | `evaluateContractCapability` + `txReadinessReader` |
| `callableAcceptTOInvitation` | 동일 |
| `callableCreateFlexSlots` | `dates: arrayUnion(...uniqueDates)` |
| `callableDeleteSlots` | `dates: remainingDateKeys` |

**오탐 2건 제거** — `hasValidBusinessLicense` 경유로 올라온
`callableManageBusiness`·`onBusinessCreated` 는 변경 라인이 그 함수 본문
(22552~22642)에 **없음**을 확인해 제외했다. 원인은 심볼 끝을 "다음 선언
직전" 으로 잡아 함수 사이 주석 블록을 창에 넣은 것 — 중괄호 균형으로
고쳤다. 후보 11 → **9개**.

### §7 slot-date mutation writer 전수

코드 전체에서 slot 문서 생성·삭제 writer 는 **2개뿐**이다 —
`batch.set(slotRef, slotData)`(13906, createFlexSlots),
`txDel.delete(slotsRefForDelete.doc(slotId))`(26221, deleteSlots).
Dart 쪽 `collection('slots')` 접근 18곳은 **전부 `batch.update`** 로
생성·삭제 writer 가 0건이다. 새 writer 없음 → STOP 불필요.

### 배포 증거

| 축 | 결과 |
|---|---|
| HEAD | `edb22fce00f4a61cfc0bd837b086d7d0dd5b7b1b` == 지시 기준 |
| 작업 트리 | `functions/`·`lib/`·`test/` 추적 변경 **0건**. `.dart_tool/package_graph.json`·`android/local.properties`(빌드 산출물)만 수정 상태 — 배포 artifact 에 들어가지 않으므로 임의 정리하지 않았다 |
| 재빌드 | 기존 `lib/index.js` 는 **9/29 16:02** stale 이었다 → 제거 후 `npm run build` 재생성. 배포 predeploy 가 다시 빌드(15:35:56) |
| tsc | 통과 |
| eslint | `src/index.ts` **4973**(기준선 동일). 전체 4977 의 차이 4건은 기존 seed/benchmark 스크립트 |
| gate 테스트 | 7파일 **148/148** 통과 |
| 전체 스위트 | `edb22fc` 이후 코드 변경 0 → 기존 CODE 근거 재사용(14841 PASS / 2 SKIP / 0 FAIL, analyze clean) |
| 배포 명령 | `FUNCTIONS_DISCOVERY_TIMEOUT=120 npx firebase deploy --only functions:<9개> --project alfit-89567` |
| 배포 결과 | `updating` 9줄 · `Successful update operation` 9줄 · exit 0 |
| 금지 대상 | `deleting/creating function` 0 · firestore/storage/hosting/database/remoteconfig 줄 **0** |
| 함수 상태 | 244개 전부 `ACTIVE`, 집합 동일, runtime/platform 변동 0 |

### 배포 검증의 한계 (기록)

`firebase functions:list` 는 **updateTime·buildId·sourceGen 을 주지 않고**
이 환경에 gcloud 가 없다. 그래서 "어느 함수의 갱신시각이 바뀌었나" 축은
**NOT SEEN** 이다. null==null 을 "그대로" 로 읽으면 근거 없는 PASS 가 되므로
inventory 스크립트가 그 경우 UNKNOWN 을 출력하게 고쳤다. §19 non-target
immutability 는 **배포 로그(9줄 updating, 0 creating/deleting) + 집합·상태
동일** 로만 뒷받침된다.

### DEV 데이터 preflight (`count()` 집계)

`tos = 0` · `businesses = 0` · `applications = 0` · `users = 8`.
→ `[R7-P4.4D-LEGACY-DATES-BACKFILL]` = **N/A**. migration 만들지 않았다.
데이터 mutation·seed·cleanup **0**.

### E2 상태

first-run 실제 데이터가 없어 §23~§32 를 시작할 수 없다 →
**RUNTIME PENDING USER FLOW.** fixture 로 대체하지 않았다.
사용자가 앱에서 신규가입 → 사업장 → 승인 → 업무 → 템플릿 → 인감 → 첫 공고를
진행한 뒤 이어간다.

### 최종 상태표

| 항목 | CODE | DEV DEPLOY | RUNTIME | DEVICE | PRODUCT |
|---|---|---|---|---|---|
| CP7 server authority | CLOSED | **VERIFIED** | NOT SEEN | NOT SEEN | PENDING |
| CP8 writer | CLOSED | **VERIFIED** | NOT SEEN | NOT SEEN | PENDING |
| CP9 projection | CLOSED | **VERIFIED**(reader 는 클라이언트) | NOT SEEN | NOT SEEN | PENDING |
| FLEX dates projection | CLOSED | **VERIFIED** | NOT SEEN | NOT SEEN | PENDING |
| first-run onboarding→posting | PARTIAL | **VERIFIED**(서버 축) | NOT SEEN | NOT SEEN | PENDING |

**next owner**: E2 — first-run writer runtime 증거 회수(사용자 실제 흐름 이후)

## 0-AAAAAAA. CURRENT SNAPSHOT — 2026-09-30 / R7-P4.4D

기준 `1a19bbf`. **CODE CLOSED / CF DEV DEPLOY PENDING.**

### 이번에 찾은 것 — 읽기만 하는 필드

지원자 목록은 `tos.dates` 로 "이 공고는 지난 날짜뿐인가" 를 판정한다
(`TOModel.slotDateKeys` → `slotDatesLookComplete` → `isVisibleToWorkerFlex`).
그런데 **그 필드를 쓰는 writer 가 코드 어디에도 없었다.** 클라이언트는
`dates` 를 CF 호출 payload 로만 넘기고(`to_firestore.dart` `_callCreateFlexSlots`)
문서에는 남기지 않았고, CF 도 쓰지 않았다.

결과: `slotDatesLookComplete` 가 **항상 false** 여서 판정이 늘 "모른다" 로
떨어졌다. 세 소비자(`isVisibleToWorkerFlex`, `user_job_tab:401`,
`user_home_screen:3967`)가 전부 fail-open 분기만 타고 있었고, **지난 날짜만
남은 슬롯 공고가 계속 일자리 목록에 떠 있었다.** 근로자는 눌러 들어가서야
고를 날짜가 없다는 것을 알게 된다.

동시에, 그 분기를 검증한다고 믿었던 기존 테스트 두 벌
(`worker_flex_exposure_contract_test`, `flex_date_reachability_contract_test`)은
`slotDateKeys` 를 **생성자에 직접 주입**해 통과하고 있었다 — writer 가 만들 수
없는 형상이다(§40 위반). 초록이 제품 동작을 증명하지 못한 자리다.

### 고친 방식 — 날짜는 슬롯에서 파생된다

슬롯 1건 = 날짜 1건이다(`for (const dateStr of uniqueDates)` + `totalNewSlots++`),
그래서 `totalSlots` 가 곧 날짜 수다. 소유권을 그 writer 에게 준다:

| 지점 | 변경 |
|---|---|
| TO 생성 | `delete finalData.dates` — 클라이언트 씨앗 제거(`totalSlots`/`totalRequired` 0 강제와 같은 구간) |
| 슬롯 생성 커밋 | `dates: arrayUnion(...uniqueDates)` — `totalSlots` increment 와 **같은 커밋** |
| 슬롯 삭제 TX | `dates: remainingDateKeys` — 이미 읽은 `allSlotSnap` 에서 재계산(추가 읽기 0), `totalSlots: remainingSlotCount` 와 같은 근거 |

drift 방향을 전수 확인했다: `dates` 가 뒤처지면 `totalSlots > 길이` → 판정
불가 → **노출**(fail-open). `dates` 가 앞서면 남은 미래 날짜가 매칭 → **노출**.
숨는 경우는 "날짜가 완비되고 전부 과거" 하나뿐이다 — 의도한 동작이다.

### 상태 delta

| ID | 이전 | 지금 |
|---|---|---|
| `[R7-P4.4D-DATE-TRUTH-NO-WRITER]` | (미발견) | **CLOSED(CODE)** — writer 3지점 + 계약 테스트 21건 |
| `[R7-P4.4D-EXPOSURE-FIXTURE-BYPASS]` | (미발견) | **CLOSED(CODE)** — 공유 canonical factory 로 writer→reader 계약화 |
| `[R7-P4.4D-WDID-CANONICAL]` | PREVIOUSLY VERIFIED | **유지** — `wdId: generateWdId()` 단독 writer, reader 는 `canonicalId` 정규화 1지점 |
| `[R7-P4.4D-TOTALSLOTS-DOUBLE-COUNT]` | 이전 단계에서 수정 | **유지** — 생성 시 0 강제(이중 전송 2배 문제) |
| `[R7-P4.4D-SOFT-DELETE-EXPOSURE]` | 의심 | **DRIFT 없음** — soft delete 가 `isPublished:false` 를 함께 써서 노출 쿼리가 이미 제외 |

### 증거 등급

- **CODE**: writer 3지점 + tsc 통과 + eslint 4973(기준선 동일, 새 문제 0)
- **RENDER**: 신규 21건 + 전체 스위트 **14841 통과 / 실패 0 / skip 2**, analyze `No issues found`
- **DEV**: **NOT SEEN** — `tos`/`businesses`/`applications` 표본 **0건**(기록된 "데이터 정리" 이후). DEV 0 을 PROD 0 으로 읽지 않는다. `users` 는 읽혀 연결 자체는 정상.
- **DEVICE**: NOT SEEN (실기기 없음)
- **CF DEV 배포**: **PENDING** — 승인 없이 실행하지 않았다

## 0-AAAAAA. SNAPSHOT — 2026-09-30 / R7-P4.4C.1

기준 `333ad2b`. **CODE CLOSED / CF DEV DEPLOY PENDING.**

### 내 P4.4C 보고 정정

"scheduler 가 gate 를 부르지 않았다" 는 **부분적으로 틀렸다.** scheduler 에는
자기 손으로 쓴 **부분** readiness 검사가 있었다 — 승인 + 등록증(**필드 truthy
만**, Storage provenance 없음) + 활성 업무. 빠진 것은 **템플릿·고용주 날인**이고,
게다가 canonical gate 와 **다른 판정 코드**였다. P4.4C 가 그 위에 두 번째 사전
검사를 얹어 N+1 이 됐다. 이번에 **하나로 합쳤다**.

### 상태 delta

| ID | 이전 | 지금 |
|---|---|---|
| `[P4.4C-GATE-02]` | scheduler 사전 검사 추가(TX 밖) | **CLOSED** — 판정이 TX 안으로 |
| `[P4.4C-GATE-03-SCHEDULED-PUBLISH-ATOMICITY]` | OPEN | **CLOSED** — read-set 방식 |
| `[P4.4C-SCHEDULED-PUBLISH-BLOCKED-VISIBILITY]` | OPEN (소비자 0) | **CLOSED(최소)** — `tos.publishBlockedReason` + 공고 수정 화면 안내 |

### §1 transaction 경계

| 단계 | TX |
|---|---|
| due TO 조회 (`publishMode==scheduled && !isPublished && publishAt<=now`, limit 500) | 밖 |
| ownerId 수집(scope 그룹핑용) | 밖 |
| **등록증**(Storage `bucket.file().exists()`) | **밖 — read-set 불가** |
| 사업장 문서 재읽기 + scope drift | **안** |
| **승인·활성업무·계약서 템플릿·고용주 날인** | **안 (read-set)** |
| capacity | 안 |
| `ACTIVE`/`isPublished:true` write · blocked 이유 write | 안 |

### §2 TOCTOU 판정

| race | 이전 | 지금 |
|---|---|---|
| RACE-A 템플릿 삭제 | **ACTIVE 가능** | 문서가 read-set → TX 재시도 → 차단 |
| RACE-B 날인 삭제 | **ACTIVE 가능** | 〃 |
| RACE-C 승인 해제 | 사업장 문서는 이미 read-set | 차단(유지) |
| 등록증 Storage 객체 삭제 | 가능 | **여전히 창 있음** — Storage 는 Firestore read-set 에 못 들어간다(필드 값은 들어간다) |

### §4~§11

- **per-business fail closed 유지** — A 미충족이 B 공개를 막지 않는다. readiness
  미충족으로 `throw` 하지 않는다(그룹 TX 를 깨지 않는다).
- 실패 상태: `SCHEDULED` / `isPublished:false` 유지. **자동 마감·취소 없음.**
- 기존 필드 없음을 확인한 뒤 `publishBlockedReason`·`publishBlockedAt` 신설.
  같은 이유면 다시 쓰지 않고, 공개 성공 시 서버가 `FieldValue.delete()`.
- **§10 자동 재시도: 있다.** 조회 조건이 그대로라 매 실행마다 다시 잡힌다 →
  안내 문구가 "준비를 완료하면 다음 예약 처리에서 다시 공개됩니다" 로 그 사실을 말한다.
- **§11 예약시각 경과 후:** scheduler 에 만료 가드가 없어 `publishAt` 이 한참
  지난 것도 공개된다. **기존 동작이고 이번에 바꾸지 않았다**(임의 만료 정책 금지).
- **§12:** 사업장당 1회 판정(`groupBizIds` 루프) — TO 수와 무관. N+1 만들지 않았다.
- **§6 visibility 이전 상태: 소비자 0개.** Posting·Home·Notification·Task·공고
  상세 어디에도 예약 공개 실패가 보이지 않았다. 이번에 공고 수정 화면에만 붙였다.
- **§7 Task 는 만들지 않았다** — 별도 제품 결정.
- **§8 책임 owner:** SubAdmin 에게 "인감을 등록하세요" 라고 하지 않는다.
  `canSetUp:false` → "사업장 관리자에게 확인해 주세요".

> 마지막 갱신: 2026-09-30 · 기준 HEAD: **R7-P4.4C** (server authority + canonical signer)

## 0-AAAAA. CURRENT SNAPSHOT — 2026-09-30 / R7-P4.4C

기준 `9073ac8`. **CODE + tests. CF DEV 배포는 사용자 승인 대기.**

### B. Posting state machine (실제 schema)

| writer | before | after | worker-visible | readiness gate |
|---|---|---|---|---|
| `callableCreateTO` immediate | — | `ACTIVE` / `isPublished:true` | **✔** | ✔ |
| `callableCreateTO` draft | — | `DRAFT` / false | ✗ | ✔ (네 모드 공통) |
| `callableCreateTO` scheduled·deferred | — | `SCHEDULED` / false | ✗ | ✔ |
| `callablePublishTO` | SCHEDULED | `ACTIVE` / true | **✔** | ✔ (공개 시점 재검증) |
| `callableUpdateTO` reopen | CLOSED | `ACTIVE` / true | **✔** | ✔ (`wantsReopen` 분기 안에만) |
| `callableUpdateTO` 일반 수정 | — | — | ✗ | 없음 (의도) |
| **`processScheduledPublish`** | SCHEDULED | `ACTIVE` / true | **✔** | **없었음 → 추가** |

지원자 노출 술어: `isPublished && !isClosed && !isSoftDeleted`.

### C. canonical readiness parity (§14)

| prerequisite | Home | CreateTO | server | same business? |
|---|---|---|---|---|
| 승인 | `r.isApproved` | `_businessApproved` | `bizData.isApproved` | ✔ |
| 등록증 | `r.hasLicense` | `sel.licenseReady` | `hasValidBusinessLicense(bizId,…)` | ✔ |
| 업무 | `hasReadyBusiness(map)` | `sel.workTypes` | `businesses/{id}/workTypes isActive` | ✔ |
| 템플릿 | 사업장별 | `sel.templates` | `businesses/{id}/contract_templates` `templateType in [daily,period]` | ✔ |
| **고용주 날인** | `any(r.hasEmployerSeal)` | `sel.employerSeal` | `users/{bizData.ownerId}.sealBase64` | ✔ |

SubAdmin: **면제 아님.** 개인 날인은 요구하지 않지만 **owner 날인은 있어야 한다**.

### D. Signer ownership

| case | caller | 계약 날인 (수정 후) |
|---|---|---|
| A owner 직접 | ownerId | owner ✔ (변화 없음) |
| B SubAdmin | 배정 SubAdmin | owner ✔ (변화 없음) |
| **C co-admin** (`adminIds`, owner 아님) | co-admin | ~~co-admin 개인 날인~~ → **owner** |

Case C 는 `adminIds` 에 BUSINESS_ADMIN 을 넣는 **사용자 경로가 없다**(모든 writer 가
`arrayUnion([ownerId])`) — SUPER_ADMIN 개입으로만 도달. 잠재 결함이었고 이제 닫혔다.
계약 서명 화면(`contract_sign_screen`)은 **원래부터** owner 기준이었다 — 발송 경로가
그 canonical 을 따라간 것이다.

### E. Reference review (§7)

| 레퍼런스 | 관찰한 원리 | 판정 |
|---|---|---|
| **모두싸인** 도장/사인 공유 | 도장·사인은 **조직 소유물**이고 멤버에게 **이용 권한을 공유**한다. 담당자 계정으로 발송해도 서명 주체는 회사/대표 | **채택** — ALfit 에 조직 entity 가 없으므로 그 자리를 `business.ownerId` 가 맡는다 |
| **모두싸인** 대표 명의 + 법인 명의 | 둘을 **각각 서명자로** 설정 | **거부(현 범위)** — ALfit 근로계약은 사업주 날인 1개 구조. 분리는 별도 제품 결정 |
| **모두싸인** 멀티 워크스페이스 | **법인**·브랜드·목적별로 흐름 분리 | **수정하여 채택(부분)** — 같은 결론은 "법적 사업자별 seal scope" 인데 ALfit 은 그것을 표현할 entity 가 없다 → 잔여 |
| **DocuSign** delegation | 대신 서명하면 **본인 서명이 찍힌다**(남의 서명을 쓰지 않음) | **거부** — 개인 서명자 모델이다. 한국 근로계약의 사용자(고용주) 날인은 개인이 아니라 사업주 identity |

### 수정

| ID | 등급 | 내용 |
|---|---|---|
| `[P4.4C-GATE-01]` | **BLOCKER** | 서버 gate 가 3축만 봤다 → 템플릿·고용주 날인 추가(사업장 단위) |
| `[P4.4C-GATE-02]` | **BLOCKER** | **예약 공개 scheduler 가 gate 를 안 불렀다** — 만든 뒤 템플릿·날인이 지워지면 "확정해도 계약 못 만드는 공고" 가 열린다. 준비 미충족 사업장의 TO 만 SCHEDULED 로 남긴다(그룹 transaction 은 깨지 않는다) |
| `[P4.4C-SIGNER-01]` | **BLOCKER(잠재)** | 발송 3경로가 `isSubAdmin ? owner : caller` → **항상 owner** |
| `[P4.4C-SEAL-02]` | **BLOCKER** | Home·CreateTO 가 **호출자 자신의** 날인을 보고 SubAdmin 은 무조건 면제 → 사업장별 **owner 날인** |
| `[P4.4C-ERR-01]` | CORRECTION | `POSTING_NOT_READY:<REASON>` 5종 + `PostingNotReady` 매퍼. 서버 문장을 그대로 띄우던 두 화면 교체 |
| §17 날인 교체 | **NO PATCH** | 이미 안전 — 계약은 `employerSignatureUrl`(서명 시점 Storage URL)을 들고 렌더가 **URL 우선**, base64 는 미서명 미리보기 폴백 |

> 마지막 갱신: 2026-09-30 · 기준 HEAD: **R7-P4.4B** (CP7 authority + CP4~6 writer)

## 0-AAAA. CURRENT SNAPSHOT — 2026-09-30 / R7-P4.4B

기준 `834348d`. **CODE/contract 감사만** — 실기기 미실행, DEVICE 승격 없음.

### A. CP7 authoritative policy — **A 로 확정**

템플릿·인감은 **공고 prerequisite** 다. 근거: 없으면 지원자가 **확정된 뒤에**
계약 dead-end 가 되고, 그 비용은 근로자가 치른다. 계약 발송 경로가 두 조건을
이미 강제한다(`ContractTemplateSelectorDialog` → 인감 확인 → `설정으로 이동`).

| prerequisite | Home | CreateTO client | server writer | 최종 정책 |
|---|---|---|---|---|
| 승인 | ✔ | ✔ | ✔ | 필수 |
| 등록증 | ✔ | ✔(선택 사업장) | ✔ | 필수 |
| 업무 | ✔(identity 보존) | ✔(선택 사업장) | ✔ | 필수 |
| 템플릿 | ✔ **사업장별로 수정** | ✔ **사업장별로 수정** | **없음** | 필수 — 서버 확장 잔여 |
| 인감/서명 | ✔ | ✔(SubAdmin 면제) | **없음** | 필수 — 서버 확장 잔여 |

서버 확장은 `callableCreateTO`·`callablePublishTO` 두 곳이고 `callableUpdateTO` 는
**제외**해야 한다(legacy TO 수정까지 막힌다). CF 배포가 사용자 승인 사항이라
이번에 코드를 바꾸지 않고 `[R7-P4.4B-RESIDUAL-SERVER-POSTING-PARITY]` 로 남겼다.
현재 서버가 보는 것은 `CP7-01` 셀이 사실로 고정한다.

### B. CP4 업무 — `[P4.4B-WT-01]` CORRECTION 수정

writer `businesses/{id}/workTypes.add()` · `isActive:true` · `displayOrder=기존 수` ·
`createdAt` serverTimestamp. **사업장 binding 은 구조적으로 보장**(서브컬렉션).
읽기 실패는 `rethrow`(ERROR≠ZERO 유지).

**같은 이름 활성 업무 중복이 막혀 있지 않았다.** 새 정책이 아니라 이미 시스템이
깐 전제다 — 서버 `assertWorkTypesInBusiness` 가 **이름으로** 대조하고
공고·지원 snapshot 도 이름을 저장하므로 같은 이름 문서 둘은 downstream 에서
구별할 수 없다. → 등록 차단 + 중복은 "실패" 가 아니라 고칠 수 있는 입력 문제로 안내.

### C. CP5 템플릿 — `[P4.4B-TPL-01]` **BLOCKER 수정**

템플릿은 `businesses/{id}/contract_templates` **서브컬렉션**이고 계약 발송도
`businessId` 로 그 사업장 것만 고른다. 그런데 readiness 판정만 **전 사업장 합산**
이었다(Home·CreateTO 둘 다). → A 에만 템플릿이 있는데 **B 로 공고를 낼 수 있고,
지원자가 확정된 뒤에** 고를 템플릿이 0개인 dead-end 를 만난다.
같은 파일 주석이 바로 그 상황을 경고했는데, legacy 분류 축만 막고 **사업장 축은
열려 있었다.** → 양쪽 다 사업장별 판정.

`selectableForNewContract` = `templateType ∈ {daily, period}` — **active/deleted/
version 축은 이 모델에 없다.** 템플릿 수정은 기존 계약을 소급 변경하지 않는다
(계약이 `articles` 를 **복사해 동결**, `templateId` 참조 아님) → NO PATCH.

### D. CP6 인감/서명 — `[P4.4B-SEAL-01]` CORRECTION 수정

**authority 는 `users/{uid}.sealBase64` 하나다.** Home readiness 와 계약 생성이
같은 필드를 읽는다(§14 의심 해소 — `businesses.sealUrl` 같은 분리 없음).
`business_model.dart` 에 "`sealBase64` 는 `users/{uid}` 문서에만 저장한다" 는
분리 완료 결정이 남아 있다. **사업자 계정 단위**이고 사업장 단위가 아니다.

**P4.3B 의 cache-path 구조가 아니다** — 도장은 picker 를 쓰지만 **즉시
`readAsBytes()`** 로 읽어 base64 로 넘기고, 서명은 캔버스 → bytes 다.
파일 경로를 화면 사이로 들고 다니지 않는다 → **staging 불필요, NO PATCH.**

고친 것: 저장·삭제 실패가 원인 구별 없이 한 문장이었고 **로그도 남지 않았다.**
→ `FirebaseFunctionsException.code` 별 안내 + 세 경로 모두 로그.

### 잔여

- `[P4.4-BUSINESS-IDENTITY-AUTHORITY]` — **사용자 결정 반영됨**(전역 unique 금지)
- `[R7-P4.4B-RESIDUAL-SERVER-POSTING-PARITY]` — 서버 gate 확장(배포 승인 필요)
- CP8/9 첫 공고 writer·projection — **미착수**

> 마지막 갱신: 2026-09-29 · 기준 HEAD: **R7-P4.4 CP0/1/7** (first-run golden path)

## 0-AAA. IN PROGRESS — R7-P4.4 first-run golden path

기준 `849a54a`. **기기 단계는 사용자와 함께 진행 중** — 아래는 기기가 필요 없는
checkpoint 만 먼저 닫은 것이다(§24·§33).

**DEV 현재 위치(실측):** BUSINESS_ADMIN **1건**(`managedBusinessIds=0` ·
`seal=N` · `license=N` · `businessNumber=null`) · `businesses` **0건** ·
`tos` **0건** · `Storage businesses/*` **0개**. → 사용자는 **CHECKPOINT 0/1 지점**.

| CP | 범위 | CODE | DEV | DEVICE |
|---|---|---|---|---|
| 0 회원가입 | role·초기값 | **READ 완료** | 실측 1건 | 기존 계정 |
| 1 Home 준비 | 4칸 ↔ CreateTO | **READ 완료** | — | NOT SEEN |
| 2 사업장 | P4.3A/B 재사용 | CLOSED(직전) | 0건 | **대기** |
| 3 승인 | 상태 매핑 | READ 완료 | 표본 0 | 대기 |
| 4~6 업무·템플릿·인감 | — | 미착수 | — | 대기 |
| 7 readiness parity | Home↔CreateTO↔서버 | **CLOSED** | — | NOT SEEN |
| 8~9 첫 공고·투영 | — | 미착수 | — | 대기 |

### CHECKPOINT 7 — parity 표 (§11)

| 준비 항목 | Home predicate | CreateTO predicate | same truth |
|---|---|---|---|
| 사업장 | `any(r.isApproved && r.hasLicense)` | `_businessApproved && _hasLicense` | **✔** |
| 업무 | `hasReadyBusiness(map)` (같은 사업장에서 승인·등록증·업무) | `_workTypesReady` (선택 사업장) | **✔** |
| 계약서 템플릿 | `ContractTemplateModel.selectableForNewContract` | **같은 함수** | **✔** |
| 인감/서명 | `isSubAdmin \|\| sealBase64.isNotEmpty` | `_hasSeal` (SubAdmin 면제) | **✔** |

**§11-1 승인 포함: 예.** `businessReady` 가 `isApproved` 를 요구하므로
"업무·템플릿·인감 다 있는데 승인 대기" 상태가 READY 로 보이지 않는다.

**서버 gate(`assertBusinessPostingReady`)는 3조건**(승인·등록증·활성업무) —
템플릿·인감은 없다. 클라이언트가 **더 엄격**한 방향이라 "가능하다고 해 놓고
서버가 거절" 하는 오류는 없다. 반대 방향 gap 은 아래 잔여로 기록.

### 발견 (CP7) — `[P4.4-CP7-01]` CORRECTION · 수정함

`_loadPostingReadiness` 는 **승인된 사업장만** 조회한다(`approvedBizs`).
그래서 **미승인 사업장에 업무를 등록해도 '업무 등록' 칸이 완료로 바뀌지 않는다.**
그런데 그 이유를 어디서도 말하지 않아(`pendingHint: null`), 신규 관리자는
업무를 등록하고 돌아와도 같은 줄이 미완료인 것을 보고 같은 화면을 다시 연다.
→ `'사업장 승인 후 반영돼요'`. **완료로 올려서 해결하지 않았다** — 그러면
공고를 낼 수 없는 상태가 "준비 완료" 가 된다.

### 발견 (CP0) — 기록만, 수정 안 함

회원가입이 `signUp(...)` 에 **`businessNumber` 를 넘기지 않는다**(화면에 필드 없음).
DEV 실측 `businessNumber=null` 과 일치. 그 결과
`callableCheckBusinessNumberDuplicate` 는 `users.businessNumber` 로 조회하므로
**신규 계정에서는 항상 빈 결과** — 중복 체크가 사실상 동작하지 않는다.
→ `[OPEN-BUSINESS-REGISTRATION-VERIFICATION-INTEGRITY]` 에 병합.

> 마지막 갱신: 2026-09-29 · 기준 HEAD: **R7-P4.3B** (사업장 서류 precheck · 첨부 수명)

## 0-AA. CURRENT SNAPSHOT — 2026-09-29 / R7-P4.3B

기준 `af8fed3`. 실기기 발견 2건 + 직전 수정의 **첫 정상 증거**.

**DEVICE 성과:** 주소 선택 → `사업장 위치 확인됨` **관찰됨**.
→ `[R7-P4.3A-BUSINESS-ADDRESS-LOCATION-VERIFY]` 의 기기 원인 후보 3개 중
①(키 없는 빌드)·③(네트워크) **기각**, 경로 정상 확인. 이 축은 다시 열지 않는다.

| ID | 등급 | 내용 |
|---|---|---|
| `[R7-P4.3B-BUSINESS-SAVE-TEMP-FILE]` | **BLOCKER** | `ImageHelper.compressImage` 가 **세 경로**(200KB 이하 · 압축 null · 예외)에서 **image_picker 소유 cache 파일**(`cache/scaled_*`)을 그대로 반환. 폼은 그 File 을 3단계 마법사 내내 들고 다니다 맨 마지막에야 연다 → `PathNotFoundException errno=2`. **Golden Path 전면 차단** |
| `[R7-P4.3B-BUSINESS-DOC-PRECHECK]` | **BLOCKER** | 완료 조건이 `File != null` 하나 → **풍경 사진도 통과**. `FILE_SELECTED` 를 `DOCUMENT_READY` 로 썼다 |
| `[R7-P4.3B-RAW-EXCEPTION-UX]` | CORRECTION | `저장에 실패했습니다: PathNotFoundException … errno = 2` 를 그대로 노출 |
| (추가 발견) | CORRECTION | `_uploadImage` 가 `finally` 에서 **성공·실패 무관하게** 첨부를 삭제 → 네트워크 실패 후 "다시 저장" 이 영구 불가 |

**§16 partial write — 없음(실측).** DEV: `businesses` 0건 · `managedBusinessIds` 0 ·
`Storage businesses/*` **0개**. `_uploadImage` 가 `readAsBytes()` 에서 먼저 던져
네트워크 write 이전에 끝났다. 사업장 문서 + 소유 관계는 **WriteBatch** 로 원자적.

**§5 재사용:** 새 OCR SDK 를 추가하지 않았다. `google_mlkit_text_recognition` 과
`OcrVerificationHelper.verifyBusinessLicense`(번호·대표자 추출)가 **이미 있었고
폼에 연결돼 있지 않았다.** 거기에 **문서 판별**(`looksLikeBusinessLicense`)만 더했다 —
영수증에도 사업자등록번호가 찍히므로 번호 일치만으로는 서류를 구별할 수 없다.

**§10 상태:** `checking` / `passed` / `not_document` / `unreadable` /
`number_unread` / `number_mismatch`. **precheck ≠ 공식 검증** — 문구에
`인증`·`진위`·`검증 완료` 를 쓰지 않는다. `official verification` 은 미구현으로 잔여.

| 등급 | 상태 |
|---|---|
| CODE | **CLOSED** — 29셀 |
| RENDER | **NOT SEEN** — 폼은 Firebase·Provider 없이 pump 불가. OCR 원문→판정은 순수 로직 13셀 |
| DEV | **N/A** — businesses 0건 (부분 write 부재는 실측) |
| DEVICE | **부분** — 위치 확인됨 관찰. 서류 precheck·저장 성공은 재빌드 후 **NOT SEEN** |
| PRODUCT | **OPEN** — 공식 사업상태 검증 범위 |

## 0-A. CURRENT SNAPSHOT — 2026-09-29 / R7-P4.3A

**`[R7-P4.3A-BUSINESS-ADDRESS-LOCATION-VERIFY]`** — 실기기 발견.
기준 `db5313b`. BUSINESS_ADMIN 신규 사업장 등록에서 주소를 골라도
`GPS 위치 미확인` 이 계속 남았다.

**predicate:** `_latitude == null` **하나뿐**이었다. 기기 GPS·권한과 무관하다 —
이 폼은 기기 위치를 한 번도 읽지 않는다(등록에 현장 임장 불요, §4 정상).

**chain:** Daum 우편번호 WebView(좌표 없음) → `fullAddress` →
`GeocodingService` (Kakao Local `address.json`) → `_latitude/_longitude` →
`businesses/{id}.latitude/longitude` → `attendance_check_screen` 반경 판정.
writer·consumer **같은 키**(`latitude`/`longitude`) — schema mismatch 없음.

| 판정 | 내용 |
|---|---|
| **BLOCKER** `[P4.3A-LOC-03]` | 세 단계 검증 어디도 좌표를 보지 않았고 payload 는 `'latitude': _latitude` 를 **null 인 채로** 보냈다 → **§6 Case C**. 좌표 없는 사업장이 만들어질 수 있고, 대가는 근무 당일 출근이 막히는 **근로자**가 치른다 |
| **CORRECTION** `[P4.3A-LOC-01]` | `GeocodingService` 가 **여섯 실패를 전부 `null`** 로 뭉갰고 이유 로그는 전부 `kDebugMode` 뒤 → 릴리스 기기에서 완전 침묵. 화면 문구도 하나뿐이라 되지 않을 재검색만 반복하게 했다 |
| **CORRECTION** `[P4.3A-LOC-02]` | 좌표 조회를 주소 다이얼로그 콜백 안에서 `await` 하고 그 뒤에 닫았다 — 최대 10초 무표시 정지. 폼으로 옮기며 request-id 경쟁 가드 추가 |
| **NO PATCH** | consumer 는 **fail-closed** 다 — 0,0 폴백·null 허용 없음(`attendance_check_screen:446` → `return null`). 기기 GPS 요구 없음 |

**외부 확인(읽기):** DEV 키로 Kakao `address.json` 직접 호출 —
도로명·지번·상세주소 포함 전부 `200 / docs=1 / 좌표 반환`, 없는 주소만 `docs=0`.
**키·엔드포인트·주소 포맷은 정상.** 남은 기기측 후보 3개는 아래 잔여 참조.

**DEV 실측:** `businesses` **0건** → 저장 단계 **N/A(대상 없음)**, PASS 아님.

| 등급 | 상태 |
|---|---|
| CODE | **CLOSED** — 25셀 |
| RENDER | **NOT SEEN** — `BusinessFormScreen` 은 Firebase·Provider 없이 pump 불가. 문구·행동 로직은 순수 함수로 분리해 11셀로 검증 |
| DEV | **N/A** — businesses 0건 |
| DEVICE | **NOT SEEN** — 재빌드·재설치 필요 |
| PRODUCT | **OPEN** — 기기 원인 확정 대기 |

## 0. CURRENT SNAPSHOT — 2026-09-29 / R7-P4.2C

> 아래 절들은 누적 기록이다. **지금 어디 있는지**는 이 절만 읽으면 된다.

**기준 → 종료:** `6b77dc6` → `7a5e804`(P4.2-1) → `3a7fde8`(P4.2B) → **P4.2C**

| 회차 | 범위 | CODE | RENDER | DEV | DEVICE | PRODUCT |
|---|---|---|---|---|---|---|
| R7-P4.2-1 | Home 온보딩 네비 · 세 탭 SETUP_REQUIRED · 급여 root 홈버튼 | CLOSED | 소스 계약만 | NOT SEEN | NOT SEEN | — |
| R7-P4.2B | root 이름 일치 · 알림 owner · identity 강도 · 하단바 · cold path | CLOSED | **CLOSED**(46셀, 320/360/411 × 1.0/1.3/2.0) | NOT SEEN | **NOT SEEN** | 관리 탭 정체성 OPEN |
| R7-P4.2C | Home 설정 진입점 · readiness refresh owner | **CLOSED** | **PARTIAL** — `AdminTabSwitcher` 실물 8셀. Shell 은 Firebase 없이 pump 불가 → 배선은 소스 계약 | NOT SEEN | **NOT SEEN** | — |

### R7-P4.2C 결정

**§1 product intent — `A. 관리 탭으로 이동` (확정)**
헤더 버튼은 `const SettingsScreen()` 을 push 했다. Shell 탭 4 의 root 도
`const SettingsScreen()` — **파라미터 0, 완전히 같은 위젯**. tooltip·semantic label 은
**없었다**(admin `_headerBtn` 은 label 인자를 받지 않는다). 기존 테스트 이름도
`02-c 알림 · 설정 action` 이었다. B(프로필)·C(별도 설정)·D(역할 전환) 아님 —
`person_outline` 은 이 제품에서 지원자 MY 탭의 '프로필 관리'(`ProfileEditScreen`)를 뜻한다.

| ID | 판정 | 근거 |
|---|---|---|
| `[P4.2C-NAV-01]` | **Model B — switchToTab(settingsTab)** | 같은 목적지에 두 개의 top-level 진실이 있었다. 목적지는 그대로, 가는 방법만 바꿨다. 아이콘도 `settings_outlined` 로 목적지를 따라간다. 버튼은 **지우지 않았다** |
| `[P4.2C-READY-01]` | **R1 — Home 재활성화** (R2 기각) | R3 불가: `notifyDataChanged` 17 호출부 중 **관리 탭 0곳** — 기존 버스가 Manage mutation 을 나르지 않는다. R2(4+ 화면에 mutation 신호 추가)는 blast radius 로 기각 |

**드러난 더 큰 사실:** 그 `_reloadReadiness()` 는 원래부터 **반쪽**이었다.
같은 화면에 하단 '관리' 탭으로 들어간 경우엔 아무도 갱신하지 않았다 —
owner 가 화면이 아니라 **한쪽 입구**에 붙어 있었다. 이번 수정으로 두 입구가 같아졌다.

**read 증감 (정적)**

| 전이 | 전 | 후 |
|---|---|---|
| 헤더 버튼 → 관리 → 홈 | 2 loader | 2 loader (동일) |
| 하단 관리 탭 → 홈 | **0** (stale) | 2 loader |
| 공고·근무·급여 → 홈 | 0 | **0** (`fromTab` 가드) |
| 관리 탭 진입 시 Home preload | 없음 | 없음 |

**back semantics 변화(사용자에게 보임):** 예전엔 push 라 back 이 Home 으로 돌아왔다.
이제 관리 탭 root 이므로 다른 네 root 와 **같은 규칙** — 탭 내 route 가 없으면
`SystemNavigator.pop()`. 이 규칙은 이번에 만든 것이 아니라 Shell 의 기존 계약이다.

**역할 영향:** BUSINESS_ADMIN · USER(SubAdmin 관리자 모드) 둘뿐.
SUPER_ADMIN 은 `AdminHomeScreen`(다른 화면), 지원자 Home 에는 이 버튼이 없다.
역할 전환 진입점(헤더 토글 · 관리 화면 '지원자 모드로 전환') 둘 다 무변경.

**P4.2B 에서 확정한 것**

| ID | 판정 | 근거 |
|---|---|---|
| `[P4.2B-CTA-01]` | **KEEP HOME ROUTE** + 라벨 교체 | 사업장 등록 후에도 **운영팀 검토 대기**가 남는다(`business_form_screen` 성공 토스트). 그 사실을 설명하는 화면은 홈뿐이다. 원 탭으로 되돌리면 "방금 등록했는데 또 없다고 한다"가 된다. 라벨만 목적지를 가리키게: `준비 계속하기` → `준비 단계 보기` |
| `[P4.2B-NAV-02]` | CORRECTION | 하단 탭 `근무` ↔ 화면 제목 `인력`. 다섯 중 이 하나만 어긋났다 |
| `[P4.2B-NAV-03]` | CORRECTION | 알림 벨이 홈·급여 **둘에만** 있었다. 전역 수신함이므로 owner 를 홈 하나로. 다섯 전부에 붙이는 쪽은 거부(탭 고유 action 이 묻힌다) |
| `[P4.2B-ID-01]` | MODIFY → **C(light tonal)**, 관리자 경로만 | 관리 탭에서 가장 진한 면(primary 100%)이 **탭도 안 되는 이름표**였고, 누를 수 있는 메뉴는 전부 흰 행이었다. B(흰 면)는 메뉴 행과 구별이 사라져 기각 |
| `[P4.2B-PERF-01]` | CORRECTION | 근무 탭 cold entry 에서 `getMyBusinessOrThrow` 가 **2회** 나갔다(두 로더가 같은 프레임, 캐시는 await 뒤에 채워짐) |
| 하단 NavigationBar | **NO PATCH** | 선택 탭이 색·굵기·filled/outlined **3채널**로 구별된다(VR-02s). 320dp×2.0 에서도 5라벨 전부 표시, 넘침 0 |
| 세 SETUP 표면 레이아웃 | **NO PATCH** | 27/27 조합에서 넘침 0 |

**P4.2B 가 재확인하지 않은 것(P4.2-1 수용분):** Home 4단계 destination · `_reloadReadiness()` ·
`FirstPostingReadiness ↔ CreateTO` parity · NO_BUSINESS state contract · 급여 root 홈버튼 제거.

## 1. 문서 지도

| 문서 | 역할 |
|---|---|
| `ALfit_Product_Continuity_Index.md` (이 파일) | 단계·소유·상태의 연속성 색인 |
| `ALfit_Product_Integrity_Master_Ledger.md` | 제품 진실성 원장 — 결함/판정/미결의 누적 장부 |
| `docs/r7-p1-admin-design-audit.md` | R7-P1 감사 본문(단계별 표·근거·증거) |
| `docs/r7-p2-user-design-audit.md` | R7-P2 지원자(USER) 감사 본문 |
| `docs/r7-gap02-product-value-criteria.md` | **GAP-02 제품 가치·사용성 기준** — VJ01~14 레지스트리, 증거 등급 규칙, 역할별 PRODUCT 상태 |
| `docs/r7-staffing-count-lineage-audit.md` | Staffing 카운터 계보 감사 |
| `docs/functional_test_*.md` | 기능별 시나리오 인벤토리(일부 낡음 — 아래 주의) |
| `CLAUDE.md` | 작업 지침·설계 확정 항목·금지 사항 |

**인벤토리 주의:** `functional_test_Q_payroll_screens.md` 는 존재하지 않는
`today_payment_screen.dart` 를 대상으로 적고 있고 Q-01 의 `limit(500)` 도 이미 CF 로
옮겨졌다. 인벤토리는 **현행 HEAD 의 도달 경로로 재확인한 뒤** 쓴다.

## 2. R7-P1 단계별 상태

| 단계 | 범위 | CODE | RENDER | DEVICE/PRODUCT |
|---|---|---|---|---|
| P1-2 | Staffing identity·좌석·UNKNOWN | CLOSED | CLOSED | O08 **PENDING** |
| P1-3 | 근태 관계·날짜 계약 | CLOSED | CLOSED | **PENDING**(권한 있는 실제 action) |
| P1-4 | 홈·할 일·요약 | CLOSED | CLOSED | **PENDING** |
| P1-5 | 급여 개요·상세·대시보드 | CLOSED | CLOSED | **PENDING** |
| P1-6 | 계약·관리·통계 | CLOSED | CLOSED | **PENDING** |
| P1-7 | 관리자 화면 간 일관성 + P1-6 잔여 | CLOSED | **CLOSED**(super-admin 5화면 CODE only · 통계 hop 제스처 NOT SEEN) | **PENDING** |
| P2-1 | 지원자 Home·4탭 진입 | **CLOSED** | **CLOSED**(P21-R 행동은 12경로 중 4 실행 · 탭 내부 화면군 범위 밖) | **PENDING** |
| P2-2 | 일자리·공고 상세·지원 흐름 | CLOSED | **CLOSED**(D2·N1 행동 실행 · **A1 제스처 격리 실행 불가 — 원인 확정**) | **PENDING** |
| P2-3 | 근무가능일↔초대 의미 | CLOSED(consumer 전수) | **CLOSED**(첫 선택 전 안내·4상태·왕복) | **PENDING** · 실사용자 이해 **NOT SEEN** |
| P2-3 후속 | 일정·출퇴근 화면군(P23-N/S/A/V/E/G) | CLOSED | **CLOSED** | **PENDING** · 저장 제스처·실제 mutation **NOT SEEN** |
| P2-4 | MY·수입·리뷰·요청(P24-N/I/R/Q/E/G) | CLOSED | **CLOSED**(월 시트 제스처·리뷰 3상태 렌더 실행 완료) | **PENDING** · 알림→리뷰 제스처 NOT SEEN · 발견성 VJ07/VJ14 |
| P3-1 | 네 역할 과업·인계·가치 후보(P31-H/W/D/X/F) | CLOSED(H·W·D) · **CODE only**(X) | **CLOSED**(서브관리자 전환 RSW-1~4) · 슈퍼관리자 **NOT SEEN** | **PENDING** · 후보 F1~F7 전부 **VERIFY** |
| P3-2 | 제안·권한·운영 판단의 내용 렌더(P32-H/D/X1/X2) | CLOSED | **CLOSED** — 네 셀 모두 내용 RENDER(IHK/WPD/SAU/TOL 22건). 수락 확인창만 CODE only | **PENDING** · F4/F6/F7 **VERIFY** 유지 |
| P3-3 | 행동 직전 판단(P33-D/X1/X2) | CLOSED | **CLOSED**(ACX-1~12) — 세 셀 **PATCH**: 무안내 pop · 확인창 대상 식별자 · 한도 단위·적용 시점 | **PENDING** · 급여 안내·사용량 표시·사람 인지는 **VERIFY/USER OPEN** |
| P3-4 | shell 일관성·기능 보존(5 호출부) | CLOSED | **CLOSED**(SHU-0~7, R×6) — 다섯 곳 전환, refresh·홈·알림·계약 바 보존 | **PENDING** · DEVICE 미실행 · F1~F3/F5 는 shell 로 닫히지 않는다 |
| P2 잔여 | Home CTA 12경로 · 일정 카드(P21-R/P23-N) | CLOSED | **CLOSED(격리)** — 12/12 실행(UHR-31~46) + 인박스 내부(MRI-0~5) + 일정 카드·다른 달(PSN-1~5) | **PENDING** · 승인·동의 writer·앱 복귀 경로 각 owner |
| P2-1 후속 | 서류 보완 확인 실패 · 목적지 대상(H6-E/H6-D) | CLOSED | **CLOSED(격리)** — 실패 표면·재시도·uid 가드 8건(UHR-45 갱신 · 47~54) + 목적지 본문 실측 5건(DDT-1~5) | **PENDING** · 목적지에 요청 문맥(사업장·사유·"외 N건") 없음 — 내 서류 화면 owner |
| FS (품질 기준선) | 전체 스위트 기존 49 실패 결산 | **TEST gate CLOSED** — 14451 PASS / 2 SKIP / **0 FAIL · 0 load error**, analyze No issues. 원인 6개 전부 오래된 테스트·하네스, **production 변경 0** | N/A(코드 수정 없음) | `[OPEN-CONTRACT-MONTHEND]` 는 아래 행으로 옮겨 재정의됨. **DEVICE·USER 는 종전대로 PENDING** — TEST green ≠ 출시 승인. 상세: `docs/r7-full-suite-baseline-closure.md` |
| MONTHEND | 계약 기간 종료일 (`[OPEN-CONTRACT-MONTHEND]`) | **CODE + 빌드 산출물 CLOSED.** 규칙 `v2-kst-civil-160`(초일산입 + 민법 160②③, KST 달력일), Dart·TS 두 구현 + 공유 벡터. 표준 빌드 재생성 후 산출물에 v2 참조 1건·v1 식 0건 확인 | **DEV DEPLOY 실행** — `callableConfirmApplication` 단일 배포 성공(소스 업로드 2026-09-21T14:03Z → **2026-09-29T07:02Z**, hash 갱신). **244개 중 1개만 변경**, 243개 gen/hash/state 불변 전수 확인. 1차 시도는 CLI 소스분석 타임아웃으로 **업로드 전** 실패(반영 0), `FUNCTIONS_DISCOVERY_TIMEOUT` 상향 후 성공 | **DEV 실제 확정 NOT SEEN** — 사용자가 테스터 데이터를 전부 정리해 `tos`/`applications`/`employment_contracts` 전부 **0**. 구 PENDING 정정·기존 서명 계약 불변은 **N/A(대상 없음, PASS 아님)**. 새 테스트 계정·TO·지원서 식별 후 재개. RENDER 는 격리 10셀만(DEV 렌더 NOT SEEN). DEVICE NOT SEEN. **지원자 기간 정정 고지는 구현 부재** — 안 1/안 2 PRODUCT OPEN. PROD 전환은 **프로젝트 없음 → 대상 없음**. 구버전 앱×CFv2 혼합은 출시 정책으로 이월. 상세: `docs/r7-contract-monthend-audit.md` |
| P4-1 | 실기기 조작·가독성(P41-S/A/R) | — | — | **전 셀 NOT SEEN** — 접근 가능한 Android 기기 0(adb 0, flutter 는 desktop/web). 관찰표 `docs/r7-p4-1-device-observation-sheet.md` 준비 완료 |
| P1-2 후속 | 확정 명단 행 잘림(DEVICE.1H.1) | CLOSED | **CLOSED**(ARO-1~7) — `day_applicants_dialog` 다섯 자리 접기. 수정 전 대기 행 버튼 1개 소실 → 복구 | **NOT SEEN** · P4-1 관찰표 A-1 로 실기기 재검증 |
| P2 나머지 | — | 지원자 화면군 여섯 묶음 결산 완료(PRODUCT 는 OPEN) | — | — |
| P4 | 대비·터치영역 정량 계측 | 미착수 | — | **미측정** |

## 2.5 네 역할 PRODUCT 결산 (GAP-02)

CODE/RENDER 종료가 제품 가치 종료가 **아니다**. 실사용자 관찰이 없으면 OPEN 이다.

| 역할 | CODE/RENDER | USER OBSERVATION | PRODUCT |
|---|---|---|---|
| 지원자 | P2-1·P2-2·P2-3 종료(잔여 명시) | **없음** | **OPEN** |
| 관리자 | P1-2~P1-7 종료(DEVICE 대기) | **없음** | **OPEN** |
| 서브관리자 | 권한 계약 CODE · 전환 RENDER 종료(P3-1) · **계약 진입 무안내 pop 수정**(P3-3) | **없음** | **OPEN** |
| 슈퍼관리자 | shell 11/11 · 내용 RENDER 종료(P3-2) · ERROR≠EMPTY 3건 + **행동 직전 식별자·단위 3건**(P3-3) 수정 | **없음** | **OPEN** |

기존 잔여는 **새 VJ 번호로 재등록하지 않는다** — 기존 ID 에 VJ 를 연결한다
(매핑표는 `docs/r7-gap02-product-value-criteria.md` §2).

## 3. 소유자별 미결 (완료 선언 금지 항목)

| 항목 | 소유 | 상태 |
|---|---|---|
| Staffing 11TO/21업무 카운터 보정 | 사용자 결정 | **DEFERRED** |
| Staffing O08 | P1-2 | DEVICE PENDING |
| 계약의 법률상 사후 정비 정책 | P16-C | **OPEN** |
| `[R7-P1-6-RESIDUAL-DAYS-FIELD-NAMING]` | P16-S | 유지보수 메모(표시 단위는 정상) |
| `[R7-P1-7-RESIDUAL-STATS-HOP-GESTURE]` | P17-X | 월 막대 탭은 fl_chart 콜백 — DEVICE 에서 확인 |
| ~~`[R7-P2-RESIDUAL-USER-SHELL-UNIFY]`~~ | P2 → **P3-4 CLOSED(CODE/RENDER)** | 네 기능은 `AppPageScaffold` 의 `actions`+`bottomNavigationBar` 로 caller 가 넘기면 된다(관리자 화면들이 이미 그 방식). 다섯 곳 전환, 기능 보존 확인(SHU-1~7). **scaffold 파일은 남겨 둔다** · DEVICE·USER 는 OPEN |
| `[R7-P2-1-RESIDUAL-TAB-DESTINATIONS]` | P2 | 일자리·일정·MY 탭 **내부** 화면군 |
| ~~`[R7-P2-1-RESIDUAL-HOME-NIGHT-SHIFT-CHECKOUT]`~~ | P2 | **CLOSED** — 퇴근 카드 신설 |
| ~~`[R7-P2-1-RESIDUAL-ATTENDANCE-SCREEN-LOCAL-MIDNIGHT]`~~ | P1-3 temporal | **CLOSED** — KST 로 통일 |
| ~~`[R7-P2-1-RESIDUAL-INCOME-MONTH-LOCAL]`~~ | P21-H | **CLOSED** — KST 로 통일 |
| `[BLOCKER-P2-HOME-INCOME-MONTH-LOCAL]` | P2 | CODE/행동/RENDER 수용 · DEVICE 대기 |
| `[BLOCKER-P2-JOBTAB-PARTIAL-AS-EMPTY]` | P2-2 | CODE/행동/RENDER 수용 · DEVICE 대기 |
| ~~`[R7-P2-2-RESIDUAL-POSTING-DETAIL-RENDER]`~~ | P2-2 후속 | **CLOSED** |
| `[BLOCKER-P2-POSTING-SLOT-DATE-LOCAL]` | P2-2 후속 | CODE/행동/RENDER 수용 · DEVICE 대기 |
| ~~`[R7-P2-2-RESIDUAL-APPLY-RESULT-RENDER]`~~ | P22-A → **A1 후속 CLOSED(격리 CODE/행동/RENDER)** | 원인 정정: 세 초기 읽기가 플랫폼 채널을 지나고 `testWidgets` 가짜 시계가 그 future 를 돌리지 않았다(제품 결함 아님). `ApplyWorkReads` 로 카드 도달(ARR-1~7), `ApplyWorkSubmit` 으로 네 결과·중복 탭 렌더(APR-1~9). **실제 서버 전이·서버 중복 방지는 NOT SEEN** · VJ01 PRODUCT **OPEN** |
| `[R7-P2-3-VERIFY-AVAILABILITY-COMPREHENSION]` | P2-3 | 발견성·이해 과제는 실제 사용자 관찰로만 닫는다 |
| ~~`[R7-P2-2-RESIDUAL-MY-APPLICATIONS-RENDER]`~~ | P2-2 후속 | **CLOSED** |
| `[R7-P2-2-RESIDUAL-POSTING-FCM-GESTURE]` | P2-2 | FCM → 공고 상세 제스처 NOT SEEN |
| `[BLOCKER-P2-HOME-DEST-DATE-MISMATCH]` | P2 | CODE/행동/RENDER 수용 · DEVICE 대기 |
| `[BLOCKER-P2-HOME-LONGTERM-TODAY-CTA]` | P2 | CODE/행동 수용 · DEVICE/PRODUCT 대기 |
| `[BLOCKER-P2-HOME-CROSS-UID-STALE-DATA]` | P2 | CODE/행동 수용 · DEVICE/PRODUCT 대기 |
| 대비·터치영역 수치 | P4 | 미측정 |
| radius 혼재(V4) | POLISH | 미수정 |

## 4. 화면 shell 전환 현황 (실측 기준)

`grep -c "GradientScaffold("` 로 **실제 호출만** 센다(파일명 grep 은 주석을 센다).

| 트리 | 실제 `GradientScaffold(` | 비고 |
|---|---|---|
| `lib/screens/business_admin/` | **0** | 주석에만 이름이 남아 있다 |
| `lib/screens/super_admin/` | **0** | P1-6 에서 6, P1-7 에서 5 전환 |
| `lib/screens/common/settings_screen.dart` | **0** | P3-4 에서 지원자 경로도 flat. 역할 차이는 제목·우상단 액션·계약 바로 남는다 |
| `lib/screens/user/` | **0** | `attendance_check` · `interim_settlement_request` · `my_reviews` · `subadmin_leave`. `apply_prerequisites` 는 **P2-2 에서 전환 완료**(3축 실측 후 순수 교체). 가운데 둘 + `attendance_check` 는 shell `onRefresh` 를 쓴다 |

**죽은 화면은 없다.** `lib/screens` 아래 화면 위젯 79개 전부 외부 참조가 있다(2026-09-28 실측).
`gradient_scaffold.dart` 는 **실제 사용처 0**(P3-4). 그래도 **삭제하지 않았다** — 호출부 0 은
제품 성과가 아니고 DEVICE 확인 전이다. 파일 머리말의 "홈·일정·일자리와 동일한 디자인 언어"는
이미 거짓이라 현재 사실로 고쳤다.

## 5. 반복 금지 (반례 없이는 재감사하지 않는다)

- 급여 네 상태 전이·write-set·scoped refresh·멱등(P1-5 + R8)
- 계약 서명 흐름 `pending_employer → pending_worker → completed`
- 문서 승인 버전·권한·민감정보(PII-DOC), R5 권한 검증
- 근태 관계 건수·날짜 계약(P1-3), 홈 목적지 context(P1-4)
- 통계 집계 의미·필터·fail-closed(P16-S)
- 지원자 홈 Hero 술어·늦은 응답 가드·4탭 뒤로 경로(P2-1)
- 홈 CTA entity key 표·상태 분류·FCM 대상 권한(P2-1 후속)
- 자정 넘긴 근무의 퇴근 자격 술어·경계 9종(P2-1 잔여)
- 홈↔출퇴근 화면의 KST 날짜 일치(P2-1 잔여) — 두 화면 모두 `toKstDate` 기준
- 수입 월의 KST 기준(P2-1 최종) — `FormatHelper.isSameKstMonth` 한 벌, 서버 KST 슬라이스와 동일
- 일자리 탭의 부분 결과≠없음·선택 날짜 전달(P2-2)
- 공고 상세의 슬롯 날짜 KST 매칭·표시, 내 지원 상태·사유·카운트(P2-2 후속)
- FULL/마감이 기존 약속을 끝내지 않음·상세 뒤로의 조건 유지(P2-2 최종, NO PATCH)
- 근무가능일은 초대의 절반이다 — `inviteEnabled`+`inviteRegionKeys` 가 없으면 후보에 잡히지 않는다(P2-3)
- 다만 날짜는 **초대 전용이 아니다** — `_dispatchToMatchNotifications` 가 초대 설정과 무관하게 공고 알림을 보낸다(P2-3 후속)
