# R7 품질 기준선 — 전체 스위트 49 실패 결산

- 기준 HEAD: `8799e46` (착수 시 tracked dirty 0, 사용자 untracked 8건 보존)
- 실행 명령: `flutter test --reporter expanded` (foreground, 1회)
- 1차 결과: **14127 PASS / 2 SKIP / 49 FAIL**, exit=1, 약 8분 31초
- 종료 결과: **14451 PASS / 2 SKIP / 0 FAIL / 0 load error**, exit=0, 약 8분 52초
- `flutter analyze lib test` → No issues found
- **production(`lib/`, `functions/`) 변경 0.** 20개 테스트 파일만 바뀌었다.

이 문서는 "독립 결함 49개" 를 뜻하지 않는다. 49는 **실패 이름의 수**이고
원인은 **6개**다. 또한 "기준선이므로 출시해도 된다" 는 뜻도 아니다 —
테스트 green 은 서버 실제 전이·DEVICE·USER/PRODUCT 어느 것도 아니다.

---

## FS-0 — 원인별 결산표

| 묶음 | 실패 이름/파일 | 첫 원인 · 파생 | 현재 source of truth | 판정 | 수정 · 종료 증거 |
|---|---|---|---|---|---|
| **A. 폐기된 신뢰도 점수** | 5 load(=compile) · 4파일 + 1파일 별건 | `lib/utils/trust_score_helper.dart` 삭제 + `UserModel.storedTrustScore`/`trustScore`/`trustGrade`/`trustGradeEmoji` 제거([5A.2A], 커밋 `a5f1641`) — 테스트만 안 따라왔다. 별건 1: `BadgeConditionType` 이 4→9로 늘어 switch 비망라 | `noShowCount` · `recentNoShowCount` · `restrictedUntil` · `isRestricted`, `TrustSettingsModel`(살아 있음) | **오래된 테스트** | 점수/등급을 되살리지 않고 canonical 축으로 옮김. 컴파일이 풀리며 **가려져 있던 cascade 5건**이 드러나 함께 처리 |
| **B. KST 달력일 비교 키** | 14 (`week_helper` 11 · `weekly_work_count` 3) | `WeekHelper` 가 `FormatHelper.toKstDate` 를 지나고, 그 함수는 **일부러** `DateTime.utc(y,m,d)` 를 돌려준다(기기 시간대 무관 비교 키) | `FormatHelper.toKstDate` 주석이 계약을 명시 | **오래된 테스트** | 기대값을 `DateTime.utc` 로. 되돌림 방지용 양성 대조 1셀 추가 |
| **C. 계약 종료일 월 산술** | 6 (`to_model`) | 기대값이 **당시 구현의 식**(`month + N + 1`)을 옮겨 적은 것 — 사실상 N+1개월이었다. 현재 구현은 `(start + N개월) - 1일` | `TOModel.computeContractEndDate` 의 규칙 주석 | **오래된 테스트** (+ OPEN 1건) | 달력 의미로 정정, "N개월은 시작일 포함" 성질 셀 추가 |
| **D. 퇴사/해지 축 분화** | 13 (`application_model` 10 · `my_applications_simulation` 3) | `[DEFERRED-RESIGN]` — `isTerminationApproved` 가 퇴사 축에 `status == CANCELED` 를 **함께** 요구하도록 갈라졌고, "승인됐는가" 는 `isExitDecided` 로 분리됐다 | `ApplicationModel.isTerminationApproved` / `isExitDecided` / `isScheduledOnDate` | **오래된 테스트** | 두 질문을 각각 묻도록 옮김. 일정에서 빠지는 것은 **효력일**이 한다는 규칙을 명시 |
| **E. 소스 문자열 pin 표류** | 11 (10파일) | E1 CRLF 3 · E2 코드가 정당하게 바뀜 6 · E3 범위 울타리 만료 2 | 아래 상세 | **오래된 테스트 / 환경** | 앵커를 현재 코드로 옮기되 **보장은 유지·강화** |

합계 5 + 14 + 6 + 13 + 11 = **49**. 원인 **6개**(A의 별건 포함).

**production 결함 0건.** 단 하나의 제품 질문만 OPEN 으로 남는다(§OPEN).

### E 묶음 상세

| # | 셀 | 왜 깨졌나 | 판정 |
|---|---|---|---|
| E1 | `longterm_renewal 05-k` · `mixed_staffing 14-d` · `termination T-56` | 로더가 `\n` 으로 쪼개고 다시 `\n` 으로 붙이는데 작업트리가 **CRLF** 라 여러 줄 앵커가 영영 안 맞는다. 내용은 그대로 있다 | **환경/하네스.** `renewal_decision_surface_test.dart` 에 이미 있던 정규화 선례를 그대로 재사용 |
| E2 | `permission_reactive` 진입 guard | R7-P3-3 에서 bool → `_EntryAccess` 3상태로 갈랐다(거부·미확인·비소속). **내 앞 단계가 깨뜨리고 영향집합만 돌려서 못 봤다** | 오래된 테스트. 대상 사업장 기준이라는 성질로 다시 고정 |
| E2 | `invitation_detail` 수락 payload | 사전조건 게이트에 `taxStatus:` 인자가 붙었다(세무 문턱 추가) | 오래된 테스트. "수락도 같은 사전조건을 지난다" 로 고정 |
| E2 | `noshow` 당일 지원 창 ×2 | 하루 경계 helper 가 `kstDayStartOf` → **`srvKstDayStartMs` 하나로 통합** | 오래된 테스트. 날짜 단위 차단이라는 성질 유지 |
| E2 | `renewal_decision 07-a` | 정상 집계 술어에 `!isEnded(w)` 가 **한 조건 늘었다**(끝난 근무자가 `정상 1` 로 잡히던 자리) | 오래된 테스트. 세 조건을 각각 확인 |
| E2 | `seat_counter SEAT-T1` | 트리거 조건이 `&& !seatMarkChanged` 로 **넓어졌다**(반납도 재계산을 깨운다) | 오래된 테스트 |
| E3 | `posting_close 03-f` | `lib/utils` 에 `FirebaseFunctionsException` 이 등장 — 뒤 단계가 놓은 **좁은 목적 판정 함수**(`applicant_load_outcome.dart`, 소비자 1곳)이지 울타리가 막으려던 일반 framework 가 아니다 | 울타리 만료. 허용 목록으로 좁히고 그 밖은 계속 차단 |
| E3 | `typography TYPO-42` | `FittedBox` 총수 6→7. 늘린 것은 `AppTabLabel` 의 탭 라벨 잘림 수정 — 이 울타리가 막으려던 "글자를 줄여 덮는 우회" 의 반대다 | 울타리 만료. 총수 대신 **자리 목록**으로 — 새 파일에 생기면 그대로 걸린다 |

### 컴파일이 가리고 있던 cascade (신규 회귀 아님)

`A` 를 풀자 같은 원인의 실패 5건이 드러났다. 1차 목록에 이름이 없던 것은
파일이 컴파일되지 않아 **셀이 실행조차 되지 않았기 때문**이다.

| 셀 | 실측 | 처리 |
|---|---|---|
| `SA-06-02` | `BadgeConditionType` 4 → **9** | 총수·구성 재고정 |
| `SA-06-11` · `SA-06-14` | 특별 배지가 **업종(workType)** 에서 **행동 축**(야간·새벽·재고용·사업장 수·주말)으로 전환. `workType` 은 전부 null | 행동 축 다섯이 실제로 쓰이는지로 옮김 |
| `SIM-H H-04` | 경험 배지 2 → **5**(첫걸음·성장 중·경험자 추가) | 5종 + **사다리 단조 증가** 확인 |
| `SIM-H H-05` | 특별 배지 `conditionValue` 가 축마다 다름(3·5·7·15·20) — 30 고정 아님 | 한 값 대신 "0 초과·30 이하" 성질로 |

### 걷어낸 자기참조 셀

두 그룹은 **제품을 한 줄도 지나지 않았다** — 테스트가 스스로 적어 둔 표를
자기 자신에게 되물었다. 폐기된 축이라 지킬 계약이 없어 함께 걷어냈다.

- `admin_setup_worktype_wage` SCENARIO-WT-10 (10셀): 파일 안에 정의한 `_trustGrade`
- `trust_noshow` SIM-L 구버전 (5셀): 파일 안에 정의한 `_restrictionUntil`
  사다리(1회 3일 / 2회 7일 / 3회 30일 / 4회+ 영구) — **이미 제품과 달랐다.**
  현재 규칙은 CF `_compute90dRestriction` 하나다: 최근 90일 3회 미만이면
  제한 없음, 3회 이상이면 **1일 고정**. 그 규칙과 `isRestricted` 를 재도록 옮겼다.

---

## OPEN — 이 자리에서 정하지 않은 제품 질문

**`[OPEN-CONTRACT-MONTHEND]`** — 월말 시작 계약의 만료일.
`1/31 + 1개월` 을 구현은 `2/28(clamp) - 1일 = 2/27` 로 규정하고 그렇게 주석에
적어 두었다. 민법 160조 ③(최종 월에 해당일이 없으면 그 월의 말일로 만료)을
따르면 **2/28** 이다. 다른 다섯 표본은 달력 의미와 일치한다 — 이 한 경우만
갈린다. 법률 정책을 테스트 결산에서 새로 정하지 않았다. 현재 규칙을 고정하고
차이를 `test/unit/to_model_test.dart` 에 남겼다. **owner: 계약 도메인.**

## TEST gate 상태

전체 **0 FAIL · 0 load error** 이므로 **이 시점의 TEST gate 는 종료**한다.

다만 이것은 다음을 뜻하지 않는다:
- 서버 실제 전이 검증 — 이 결산에 쓰기·배포는 **0건**이다
- DEVICE — Android 실기기 검증은 사용자 별도 작업(P4)이며 **NOT SEEN**
- USER/PRODUCT — 네 역할의 사용 관찰은 여전히 OPEN
- 출시 승인

남은 2 SKIP 은 1차·2차 모두 동일하며 이번 범위와 무관하다.

## 범위 밖으로 둔 것

공유 DEV **READ ONLY**. 원장 보정·fixture 쓰기, CF/Rules/PROD 배포,
실제 신청/해지/급여 writer **없음**. APK 생성·빌드·설치 **없음**.
H6 의 "목적지에 사업장·사유 문맥이 없다" 는 그 화면 owner 의 UX 잔여로 유지한다.
