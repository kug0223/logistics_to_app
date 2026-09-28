# R7-P2-2 A1 후속 — 지원창 초기 읽기 제어와 결과 UI 격리 검증

> 작성: 2026-09-29 KST · 기준 HEAD `fe566ee` (tracked dirty 0 · 사용자 untracked 8건 보존)
> owner: `[R7-P2-2-RESIDUAL-APPLY-RESULT-RENDER]` / P22-A · VJ01
> 실기기 P4 와 실제 지원 쓰기는 보류. **지난 하네스를 대기 시간만 늘려 재시도하지 않았다.**

---

## 0. 막힘의 원인을 한 칸 더 좁혔다

ABR-2 는 "로그인해도 로딩이 안 풀린다" 를 고정하고 있었고, 원인을
*"세 future 가 거부도 완료도 되지 않는다"* 로 적어 두었다. 그 서술은 맞았지만
**왜** 그런지가 빠져 있었다. 이번에 계측해서 확정한 것:

- 세 읽기는 `FirestoreService` 하드 싱글턴 + extension **정적 디스패치** 뒤에 있어
  하위 클래스로 바꿀 수 없다(기존 진단 그대로).
- 그리고 그 future 들은 **실제 플랫폼 채널**을 지난다. `testWidgets` 의 **가짜
  시계는 그 future 를 돌리지 않는다** — `tester.runAsync` 로 진짜 async 를 한 틱
  줘야 움직인다. 같은 성질을 `TaxIdentityService.loadStatus()` 에서 직접 확인했다:
  plain `test` 에서는 `loadFailed: true` 로 **즉시 완료**되는데,
  `testWidgets` 안에서는 pump 를 아무리 돌려도 끝나지 않았다.

→ **제품 결함이 아니라 하네스 성질이다.** 실기기에서는 응답이 오거나 오류가 온다.

---

## 1. A1-R — 세 초기 읽기와 카드 도달 (**종료**)

### 세 원소

| # | production 메서드 · key | 정상/실패/대기 | 카드·자격·표시 소비 | 경계/테스트 |
|---|---|---|---|---|
| 1 | `FirestoreService.getApplicationsForTO(toId, uid)` — key `to1/u1` | 실패 시 자체 `catch` 로 로그만(로딩은 `finally` 가 내린다) | `_applicationsByDate` → 카드의 지원 상태(`지원`/`취소`/`확정취소`) | `ApplyWorkReads.applicationsForTO` / ARR-1~5 |
| 2 | `FirestoreService.getConfirmedSchedules(uid, workDate)` — key `u1/그 날짜` | 동일 | `_myConfirmedSchedules` → 같은 날 확정 근무 안내 | `.confirmedSchedules` / ARR-1~4, **ARR-7** |
| 3 | `ScheduleConflictService.checkConflictsForWorkDetails(workDate, workDetails)` — key `그 날짜/wd1` | 동일 | `_conflictCache` → 카드의 `시간충돌`·`불가` | `.conflictsForWorkDetails` / ARR-1~4 |

세 결과가 끝나는 조건은 `Future.wait` **셋 모두**이고, 그때 `finally` 가
`_isLoading` 을 내린다. 업무 카드는 reader 가 아니라 **생성자 인자
`widget.workDetails`** 에서 나오고, 그 카드가 `slotId: slot1` · `wdId: wd1` ·
`상하차` 로 실제 슬롯/업무와 이어진다(ARR-4 가 key 를 확인한다).

### 경계

`lib/widgets/dialogs/apply/apply_work_reads.dart` — **읽기 네 개뿐**
(초기 셋 + UNKNOWN 재확인). `production` 은 `reads: null` 이라 같은 uid/key 로
지금 쓰는 서비스 메서드를 그대로 부른다. **mutation 은 넣지 않았다.**
장기공고 전용 추가 읽기는 이 경계에 없다(범위 밖).

**ARR-0** 이 짝을 고정한다: 경계 기본값 → 실제 메서드 세 짝, 화면 기본값이 그
경계인지, 세 호출이 전부 경계를 지나는지, 그리고 **경계에 `applyToTO`·
`cancelApplication`·`confirmApplication` 문자열이 없는지**.

### 결과

| 셀 | 확인한 것 |
|---|---|
| **ARR-1** | 세 읽기 미완료 → **스피너 유지**, `업무 선택`·`상하차` 없음. 껍데기(제목·닫기)는 로딩 분기 밖이라 생존 |
| **ARR-2** | **하나만** 미완료여도 스피너 — `Future.wait` 계약. 그래도 세 호출은 모두 나갔다(1/1/1) |
| **ARR-3** | 세 읽기 완료 → `업무 선택` · `상하차` · 근무 날짜 · **지원 버튼** 등장 |
| **ARR-4** | key 가 `apps:to1/u1` · `sched:u1/{그 날짜}` · `conf:wd1` 로 나갔다 |
| **ARR-5** | 한 읽기 **실패**해도 로딩에 갇히지 않고 카드가 그려진다(각 loader 의 자체 catch + `finally`) |
| **ARR-6** | 정원이 찬 업무는 카드가 있어도 `지원 완료` 라고 말하지 않는다(음성 대조) |
| **ARR-7** | 그 날짜에 확정 근무가 있으면 화면이 **먼저 그것을 말한다**(다른 사업장명이 뜬다) |

**강제 `_isLoading=false` · 자격 bypass · 하드코딩 카드 없음.**
ABR-1(로그인 없음 → pop)은 **그대로 보존**했다.

---

## 2. A1-U — 버튼 이후 네 결과 (**종료**)

### 주입점의 필요성 — 먼저 적고 최소로 넣었다

네 결과는 `applyToTOWithWorkType` 이 돌려주는 `ApplyResult` **하나**로 갈린다.
그 호출은 A1-R 에서 확인한 그 싱글턴 뒤에 있다. 그래서 **그 호출 한 곳만** 받는
`lib/widgets/dialogs/apply/apply_work_submit.dart` 를 넣었다.

- `production` 은 `submit: null` → 지금과 **똑같이** 서비스를 부른다.
- 그 앞의 선행 검사는 **전부 화면에 남는다**: 로그인 · `_isSubmitting` 잠금 ·
  `TaxIdentityService` + `meetsApplyPrerequisites` 서류 게이트 · 장기 희망시작일 ·
  충돌 날짜 · **확인 시트 승인**. 주입점은 그것들을 지나온 뒤에만 불린다.
- 범용 Firestore 쓰기 fake 도, 공유 DEV 쓰기도 아니다.
- **아무 테스트도 통과하지 않는 추상화가 아니다** — APR-3~9 가 쓴다.

**게이트를 바꾸지 않았다.** 대신 fixture 를 **요건을 실제로 충족한** 사용자로
만들었다(PASS 인증 · 신분증 업로드·확인 · 계좌 · 통장사본). 그 사용자가 게이트를
통과하는지 별도로 확인한 뒤 진행했다.

### 결과

| 결과 | 실제 버튼/확인 → 보이는 문구 | 증거 |
|---|---|---|
| — | `지원` 탭 → **곧바로 접수하지 않고** 확인 시트가 뜬다(주입 호출 0) | **APR-1** |
| — | 확인에서 **취소** → 보내지 않고 카드로 돌아온다 | **APR-2** |
| **SUCCESS** | `지원이 완료되었습니다` · key `u1/to1/slot1/상하차` 로 1회 · `확정되었습니다` 류 문구 **없음**(첫 지원 툴팁은 "관리자가 확정하면" 이라고 **아직 남았음**을 말한다) | **APR-3** |
| **ALREADY_APPLIED** | `이미 지원한 업무예요` · `지원이 완료되었습니다` **아님** | **APR-4** |
| **FAILED** | 서버가 준 사유 그대로(`정원이 이미 찼습니다`) · 접수로 보이지 않음 · **재확인 읽기 0**(모르는 것이 아니다) | **APR-5** |
| **UNKNOWN → 발견** | 재확인 읽기 1회 **읽기만** → `지원이 완료되었습니다` 로 정정 | **APR-6** |
| **UNKNOWN → 여전히 모름** | `… 내 지원 목록에서 확인해주세요.` · 성공/실패 단정 없음 · **자동 재전송 없음**(주입 호출 여전히 1) | **APR-7** |
| 예외 | 주입점이 던지면 `지원에 실패했습니다` | **APR-8** |

UNKNOWN 재확인은 같은 entity key(`to1`/`slot1`/`상하차`)의 지원서로 갈랐다.

### 빠른 중복 탭

**APR-9**: 확인 시트가 뜨기 전 두 번 탭 → 주입 호출 **1회**, 성공 알림 **1개**.
`_isSubmitting` 잠금이 두 번째 탭을 받았고, 탭 후 카드 버튼의 `onTap` 이
`null` 로 바뀌는 것도 계측했다.

> **이것은 로컬 잠금의 증거다. 서버 중복 적용 방지의 증거가 아니다.**
> UI 성공만으로 서버 전이 성공을 주장하지 않는다 — 주입점은 로컬 값을 돌려줄 뿐이다.

---

## 3. 판정

| 층 | CODE | 격리 행동 | RENDER | 미관찰/owner |
|---|---|---|---|---|
| **A1-R** 세 읽기 → 업무 카드·지원 버튼 | **종료** — 경계 4읽기, mutation 없음, 짝 고정(ARR-0) | **종료** — 대기/완료/실패 세 갈래 실제 렌더 | **종료** — 카드·날짜·업무·지원 버튼 | 실기기 DEVICE · 실제 Firestore 응답 |
| **A1-U** 확인 시트/네 결과·중복 탭 | **종료** — 주입점 1개, 선행 검사 보존 | **종료** — 탭·취소·승인 제스처 | **종료** — 네 결과 문구 + 예외 | **실제 서버 전이·자동취소 mutation 미실행** · 서버 중복 방지 **NOT SEEN** |

**VJ01 PRODUCT 는 열려 있다.** 테스트 수로 완료를 선언하지 않는다 —
실제 사용자가 이 문구들을 어떻게 읽는지에 대한 관찰은 **없다**.

### 뒤로·재진입·늦은 응답 (도달한 범위만)

이번 하네스는 다이얼로그를 `Scaffold(body:)` 로 직접 세우므로 **뒤로/재진입은
실행 범위 밖**이다. 다만 `_isSubmitting` 잠금과 `if (!mounted) return` 가드가
결과 처리 전후에 걸려 있는 것은 APR-9 에서 확인했다.
**옛 지원 대상이 남는지는 NOT SEEN** 으로 둔다.

---

## 4. 증거

| 항목 | 값 |
|---|---|
| 기준 HEAD → 종료 HEAD | `fe566ee` → 이 커밋 |
| 변경 production 파일 | `apply_work_dialog.dart` · **신규** `apply_work_reads.dart` · **신규** `apply_work_submit.dart` |
| 신규 테스트 | `apply_dialog_initial_reads_test.dart` **8건**(ARR-0~7) · `apply_result_render_test.dart` **9건**(APR-1~9) |
| 수정 전 → 후 | 수정 전 ABR-2 의 pending 위치 = `_loadInitialData()` 의 `Future.wait` 세 원소(가짜 시계). 경계 없이는 카드 0 — 새 테스트 ARR-3/APR-3 은 경계 없이 **성립하지 않는다**(그 자체가 전후 대조다) |
| 갱신 테스트 | `ABR-2` 이름·주석을 **하네스 사실**로 옮김(삭제 아님, ABR-1 보존) · `AR-72` 를 seam 닻 + **실제 메서드 짝**으로 재고정 |
| 회귀 | 영향집합 **280 PASS / 0 FAIL** — 기준선 같은 이름 실패 **없음** |
| 정적 분석 | `flutter analyze lib test` **No issues** |
| 공유 DEV | **쓰기 0** — 실제 지원/자동취소/확정·fixture 원장 쓰기·CF/Rules/PROD·APK 없음 |

## 5. 닫히지 않는 것

**A1-R 이 끝났다고 A1-U 를 새 완료로 포장하지 않는다** — 둘 다 격리 층이고,
남은 하나의 조건은 **실제 서버 전이**다(로컬 격리 결과와 서버 상태는 다르다).

VJ02 가능일 저장 · P23-N 일정 자체 복귀 · Home CTA 9개 · FCM cold-start ·
P1-5 급여 DEVICE · P4-1 실기기 전 셀 · 실제 지원·자동취소 mutation ·
Staffing DEFERRED/O08 · 계약 정책 · 네 역할 USER/PRODUCT/출시 gate — **그대로**.
