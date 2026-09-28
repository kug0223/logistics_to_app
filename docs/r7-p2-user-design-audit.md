# R7-P2 지원자(USER) 화면군 감사

> 관리자 쪽 본문은 `docs/r7-p1-admin-design-audit.md`.
> 연속성·소유는 `ALfit_Product_Continuity_Index.md`, 판정 원장은
> `ALfit_Product_Integrity_Master_Ledger.md`.

---

## R7-P2-1 — 지원자 Home·4탭 진입과 하위 화면 연결 (2026-09-28)

기준 `7f6d32b`. branch `main`, 시작 시 tracked 변경 1건(`user_home_screen.dart`,
이전 세션의 진행분), untracked 9건(`scripts/r7-*.js` 8 + `user_home_reads.dart`) 보존.
공유 DEV 쓰기·CF 배포·Rules·PROD·APK **없음**. 실기기 미실행.

### 0. 진입 구조 (실측)

| 탭 | 루트 화면 | 진입 방식 |
|---|---|---|
| 0 홈 | `UserHomeScreen` | `UserRootScreen` 기본 선택 |
| 1 일자리 | `UserJobTab` | 하단 탭 · 홈 날짜 CTA(`switchToTabWithDate`) |
| 2 일정 | `MyScheduleScreen` | 하단 탭 · 홈 `근무 기록 보기`(`switchToScheduleNow`) |
| 3 MY | `UserMyTab` | 하단 탭 |

네 탭은 각자 `GlobalKey<NavigatorState>` 를 가진 독립 `Navigator` 이고
`IndexedStack` 이 상태를 유지한다. 시스템 뒤로는 `PopScope(canPop:false)` 가
받아 **현재 탭 안쪽 스택을 먼저 pop** 하고, 루트일 때만 `SystemNavigator.pop()`.
하단 바는 Flutter `BottomNavigationBar` 이므로 홈버튼/제스처 영역 패딩은
프레임워크가 처리한다(별도 `SafeArea` 불필요 — CLAUDE.md 의 "커스텀 하단 바"
규칙 대상이 아니다).

### 1. 확정 결함과 수정

| # | ID | 무엇이 틀렸는가 | 사용자에게 무슨 일이 | 고친 방식 | 증거 |
|---|---|---|---|---|---|
| 1 | P21-H | Hero STATE B 가 `toKstDate(workDate) == today` 로 오늘 근무를 판정했다. 장기 근무의 `workDate` 는 **계약 시작일(고정값)** 이다 | 계약 시작일이 아닌 날 출근하는 **장기 근무자의 홈에서 출퇴근 CTA 가 사라진다** | 같은 화면의 주간 7일·출근 화면과 같은 canonical 술어 `isWorkingOnDate(today)` 로 통일 | UHR-1·2·3·4 + 수정 전 되돌림 대조 |
| 2 | P21-E | `_loadHomeData` 가 `uid` 를 await 이전에 잡아 두고 늦은 응답을 그대로 반영했다 | 계정이 바뀐 뒤 **이전 사용자의 지원·근태가 새 계정 홈에 앉는다** | `_homeLoadSeq` + `superseded()`(seq **와** uid) 를 state 반영 3곳에 | UHR-11 + 가드 제거 대조 |
| 3 | P21-H | 수입 행(`_incomeRow`)에 flex 가 없었다 | 큰 금액의 **끝자리가 잘려 다른 금액으로 읽힌다**(320dp·1.3 에서 17px, 320dp·2.0 에서 36px) | 금액을 줄이지 않고 자리가 모자라면 다음 줄로(`Wrap`) | UHR-R 6조합 |
| 4 | P21-H | 지원 준비 카드의 `지원 준비 · 0 / 2` Row 에 flex 가 없었다 | 배율 2.0 에서 **진행도가 잘려 몇 개 남았는지 잃는다**(320dp 83px · 360dp 57px · 412dp 17px) | `Wrap` 으로 줄바꿈 | UHR-R 6조합 |
| 5 | P21-H | 공통 `SectionHeader` 의 액션에 상한이 없었다 | 긴 액션(`2026년 9월 ›`)이 320dp·2.0 에서 31px 넘쳐 **어디로 가는 버튼인지 잘린다** | 자르지 않고 폭의 60% 를 넘을 때만 줄바꿈(`LayoutBuilder` 로 행 자신의 폭을 잰다) | UHR-R + 59 사용처 회귀 |

**5번의 범위 주의:** `SectionHeader` 는 14파일 59곳이 쓴다. 상한은 **넘칠 때만**
걸리므로 들어가는 평소에는 기존 배치와 같고, 그 가정을 아래 회귀로 확인했다.

### 2. NO PATCH — 근거를 남긴 판정

| ID | 항목 | 근거 |
|---|---|---|
| P21-R | 지원자 행동에 관리자 capability 가 덧씌워졌는가 | `lib/screens/user/` 전체에 `canManage*`·`MemberPermissions` **0건**. 남은 `isSubAdmin` 3곳은 **역할 전환 토글**(모드 스위치)이지 지원자 행동의 권한 게이트가 아니다 |
| P21-H | 정책 "수입 월 선택 bottom sheet" 와 현행 구현 | 홈 헤더는 `N년 N월 ›` 로 `IncomeDetailScreen` 진입이고, **월 선택 bottom sheet 는 그 화면 안에 있다**(`DialogHelper.showSheet`, 즉시 적용, 미래 월은 확정 근무가 있는 월만 활성). 정책이 요구하는 선택 수단이 한 홉 뒤에 그대로 있으므로 홈에 시트를 새로 만들지 않았다 |
| P21-H | 정책 "추천 2개 · homeRegion 동일 city 우선" | 현행이 그대로다 — city 2건 이상이면 city 2건(+`{city} 일자리를 먼저 보여드려요.` 부제), 1건이면 city 1 + 타지역 1, 0건이면 타지역 2 + 지역 안내. 새 정책을 만들지 않았다 |
| P21-H | Hero 와 날짜 탐색이 동시에 보인다 | 설계상 **독립 섹션**이다(소스 주석 명시: "확정/출근 유무와 무관하게 항상 표시"). 배타 조건으로 읽지 않는다 |
| P21-E | 같은 계정의 홈 로드 순서 역전 | `_isLoadingHomeData` 가 진행 중 재진입을 막아 **같은 uid 의 두 로드는 겹치지 않는다**(UHR-10 으로 측정: 진행 중 새로고침 → 호출 1회). 그래서 seq 카운터는 관측된 사건을 고친 것이 아니라 uid 가드와 함께 두는 이중 방어다 — 이 구분을 적어 둔다 |

### 3. P21-G — 남은 `GradientScaffold` 6곳 3축 실측 (READ only · 전환 없음)

| 화면 | headerContent | 헤더 TabBar | shell `onRefresh` | 흰색 상수 | 전환 난이도 |
|---|---|---|---|---|---|
| `user/apply_prerequisites_screen` | 0 | 0 | 0 | 1(버튼 전경) | **순수 교체** |
| `user/subadmin_leave_screen` | 0 | 0 | 0 | 1(버튼 전경) | **순수 교체**(SubAdmin 역할 소유) |
| `user/attendance_check_screen` | 0 | 0 | **1** | 1 | shell `onRefresh` 제거 — **body 에 `RefreshIndicator` 가 이미 있다**(중복) |
| `user/interim_settlement_request_screen` | 0 | 0 | **1** | 1 | body `RefreshIndicator` 신설 필요 |
| `user/my_reviews_screen` | 0 | 0 | **1** | 4 | body `RefreshIndicator` 신설 필요 |
| `common/settings_screen` | **1** | 0 | 0 | 19 | 단순 교체 아님 — 이미 **USER 경로 전용**이고 관리자 역할은 `AppPageScaffold`(P1-6) |

**정정:** 이전 보고에서 다섯을 "순수 교체 후보"라고 적었는데, 셋이
`GradientScaffold(onRefresh:)` 를 쓴다. `AppPageScaffold` 에는 `onRefresh` 가
없으므로 그 셋은 교체 = 당겨서 새로고침 경로를 옮기는 일이다. **이번에는
전환하지 않았다**(일괄 전환 금지).

**진입 경로(누가 이 화면을 여는가):**

| 화면 | 진입 |
|---|---|
| ApplyPrerequisites | 공고 상세 · 내 지원 · 지원 다이얼로그(`.show()`) |
| AttendanceCheck | 홈 Hero `출근하기` · 알림 · **FCM** |
| InterimSettlementRequest | 내 지원 |
| MyReviews | 알림 · 설정 · **FCM** |
| SubadminLeave | 설정 ×2 (SubAdmin 역할) |

### 4. 증거

| 구분 | 내용 |
|---|---|
| **RENDER/행동** | `user_home_content_render_test` **17건**(UHR-1~11 + 320/360/412dp × 1.3/2.0 6조합) — 실제 Home production 위젯, 경계 한 칸만 주입 |
| **행동** | `user_root_tab_navigation_test` **3건**(URN-1~3) — 네 탭 루트·선택·시스템 뒤로 |
| **수정 전 대조** | Hero 술어 되돌림 → UHR-1 FAIL / uid 가드 제거 → UHR-11 FAIL / 두 경우 모두 복원 후 PASS |
| **오버플로 실측** | 6조합 sweep 으로 5건 확인 → 수정 후 6조합 0건 |
| **회귀(이름별)** | 영향 집합(`SectionHeader`·홈·수입·문서·알림·설정 등 참조) **95파일 3882 PASS / 6 FAIL** — 6건은 **기준선(HEAD)에서도 같은 이름으로 실패**하는 기존 항목(아래) |
| **정적 분석** | `flutter analyze lib test` **No issues** |
| **DEV READ** | 없음 · **DEVICE** 미실행 |

**기준선 대조 방법:** 바꾼 두 파일을 따로 보관 → `git checkout --` 로 HEAD 상태로
되돌려 같은 8파일 실행 → 복원. (`git stash` 는 이 저장소에서 줄끝을 CRLF 로
바꿔 놓으므로 쓰지 않았다.)

**기준선에서도 실패하는 6건(이번 변경과 무관):**
`invitation_detail_projection` 1 · `mixed_staffing_parity` 14-d ·
`weekly_work_count` W-D 3(`DateTime` vs `DateTime…Z`) ·
`typography_device_scaling` TYPO-42.

**이번 변경이 깬 뒤 다시 맞춘 6건(닻 이동, 계약 불변):**
`pending_id_request_surface` 3 · `id_card_access_window` 1 ·
`renewal_proposal_commitment` 1 · `worker_contract_expiry_notice` 1 —
홈이 `UserHomeReads` 경계를 타면서 호출 이름이 바뀐 **소스 문자열 닻**이다.
계약(알림이 아니라 요청·제안 문서를 읽는다 · 홈 로드 1회 · uid 없으면 조회 없음)은
그대로이므로 닻을 경계 이름으로 옮기고, **경계가 실제 서비스 메서드로 이어지는지**를
짝 assertion 으로 함께 걸었다(이름만 바꾸고 다른 곳을 읽는 것을 막는다).

### 5. 남은 것

| 항목 | 소유 | 종료 조건 |
|---|---|---|
| `[R7-P2-RESIDUAL-USER-SHELL-UNIFY]` | P2 | 위 6화면 전환 — 셋은 `onRefresh` 이전 설계가 먼저다 |
| `[R7-P2-1-RESIDUAL-TAB-DESTINATIONS]` | P2 | 일자리·일정·MY **탭 내부 화면군**은 이번 범위가 아니다(루트 선택·뒤로만 봤다) |
| P21 DEVICE | P2 | 실기기: ① 장기 근무자 계정으로 근무일 홈에 `출근하기` 가 뜨는지 ② 글자 크게(2.0)에서 수입 행·지원 준비 진행도·`수입 현황` 액션이 모두 보이는지 ③ 계정 전환 직후 이전 계정 근무가 남지 않는지 |

#### 최소 실기기 확인안 (이번에 바뀐 자리만)

1. 장기 확정 근무가 **오늘 근무 요일**인 계정으로 홈 → `오늘의 근무` Hero 와
   `출근하기` 가 보이는지. 휴무일로 지정된 날에는 **보이지 않아야** 한다.
2. 글자 크게 1.3·2.0 → `수입 현황` 의 금액 줄, `지원 준비 0 / 2`,
   섹션 액션(`2026년 9월 ›`)이 잘리지 않고 모두 보이는지.
3. 계정 전환(로그아웃 → 다른 계정) 직후 홈에 이전 계정의 오늘 근무가
   잠깐이라도 나타나지 않는지.

---

## R7-P2-1 후속 — Home 행동·상태 증거 결산 (2026-09-28)

기준 제출 `7fe1ce3`(기준 `7f6d32b`). 실제 HEAD 확인, tracked dirty 0,
untracked 8건(`scripts/r7-*.js`) 보존. 공유 DEV READ ONLY, CF·Rules·PROD·APK 없음.
첫 보고의 수용 결과(UHR-1~11·URN-1~3·6조합 렌더·NO PATCH 4건)는 **재사용**했고
다시 테스트하거나 재설계하지 않았다.

### A. P21-R — CTA → entity key → 목적지 → 뒤로

| # | domain event / state | entity key | 보이는 문구·대상 | route | 목적지에서 같은 대상 | 뒤로 | 근거 |
|---|---|---|---|---|---|---|---|
| 1 | 오늘 확정 근무(`isWorkingOnDate`) | **없음(계정 스코프)** | `오늘의 근무` · `출근하기` | `AttendanceCheckScreen()` | **같은 canonical 술어**로 재도출 — 인자 대신 술어가 대상을 정한다 | tab0 스택 pop | **실행** UHR-17 |
| 2 | 72h 내 미확인 신규 확정 | `app.id`(seen 마킹만) | `새로운 소식` 카드 | `MyApplicationsScreen()` (rootNavigator) | 목록 — **focus 인자 없음** | pop 후 `_rebuildCaches()` | CODE(1224행) |
| 3 | 연장 제안 PENDING | **`first.id`** | `계약 연장 제안` · `확인하기` | `RenewalProposalScreen(focusProposalId:)` | **키 전달됨** | pop 후 `_loadHomeData()` | CODE + UHR-16 |
| 4 | 신분증 열람 요청 PENDING | `uid` | `신분증 열람 요청` | `MyRequestsDialog.show(applicantUid:)` | 같은 uid 의 요청 인박스 | 닫은 뒤 `_reloadPendingIdRequests()` | CODE |
| 5 | 계약해지 요청 PENDING | `uid` | `계약해지 응답` | 같은 `MyRequestsDialog` | 같은 인박스가 **신분증·해지 두 종류를 각각의 카드로** 렌더 — 홈의 두 카드를 합치지 말라는 주석과 모순 아님 | 위와 같음 | CODE(dialog 98~141행) |
| 6 | 급여 보완 요청 | `uid` | 서류 보완 카드 | `DocumentManagementScreen()` | 내 문서 | pop | CODE |
| 7 | 추천 공고 | **`to`(모델 전체)** | 추천 카드 | `JobPostingScreen(to:, workDetails:)` | **스냅샷 전달** — 목록이 낡아도 연 대상은 그 TO | 결과 true 면 `_loadHomeData()` | CODE |
| 8 | 초대 INVITED N건 | 탭 index 6 | 초대 배너 | `MyApplicationsScreen(initialTabIndex: 6)` | 초대 탭 | pop 후 `_loadHomeData()` | CODE |
| 9 | 수입(월) | `year`·`month` | `N년 N월 ›` | `IncomeDetailScreen(initialYear:, initialMonth:)` | **키 전달됨** | pop | CODE |
| 10 | 주간 일정 | 없음 | `일정 ›` | `switchToTab(2)` | 일정 탭 루트 | 탭 뒤로 | URN-2 |
| 11 | 근무 기록 | 현재 달 | `근무 기록 보기` | `switchToScheduleNow()` | 일정 탭 + 현재 달 리셋 | 탭 뒤로 | CODE |
| 12 | 날짜 선택 | 선택 날짜 | `N월 N일 일자리 보기` | `switchToTabWithDate(1, date)` | 일자리 탭이 소비 후 clear | 탭 뒤로 | CODE |
| — | 급여 이체·리뷰 작성 CTA | — | **N/A** — Home 에 없다 | — | — | — | grep 0건 |

**지원=관심 / 확정=약속:** 홈의 카운트는 `pending`(검토중) · `confirmedStatuses`(확정) ·
`contractPending`(결과 대기)로 **상태별로 따로** 센다(`_rebuildCaches`). 지원 카드가
약속으로 승격되는 순간은 `confirmedStatuses` 진입이고, 그때만 Hero·주간 dot·
`근무 예정` 수입에 들어간다. FULL(정원 충족) 뒤에도 기존 확정은 그대로 남는다 —
홈은 TO 정원을 보지 않고 **내 Application 상태**만 본다.

**snapshot 경계:** 7번 추천 카드만 모델 스냅샷을 넘긴다. 나머지는 키(또는 계정
스코프)만 넘기고 목적지가 다시 읽는다 — 낡은 스냅샷이 목적지 판단을 만들지 않는다.

**발견한 반례 1건 (수정하지 않음, 이유 기록):**
`AttendanceCheckScreen` 은 단기의 **어제** `workDate` 도 목록에 넣는다(자정 넘겨
퇴근하는 야간 근무). Home Hero 는 오늘만 본다 → **퇴근만 남은 사람에게 Home 진입점이
없다**(UHR-18 로 고정). 고치려면 "어제 근무 퇴근 미완료" 라는 **새 상태와 새 문구**가
필요하고 이는 이번 결산 범위(기존 증거 연결·최소 수정) 밖이다 →
`[R7-P2-1-RESIDUAL-HOME-NIGHT-SHIFT-CHECKOUT]`.

### B. P21-E — 지원자 reader 가 낼 수 있는 상태

| 상태 | 지원자 Home 에서 가능한가 | 근거 / 문구 |
|---|---|---|
| LOADING | 가능 | Hero skeleton · 수입 행 progress placeholder(`value: null`) |
| SUCCESS_ZERO | 가능 | `아직 지원한 일자리가 없어요` · `아직 이번 달 수입이 없어요` (UHR-8·13) |
| ERROR | 가능 | `지원 현황을 불러오지 못했어요` + `다시 시도`, 0건으로 말하지 않는다 (UHR-7) |
| PARTIAL | 가능 | 공고만 실패해도 지원 현황·Hero 유지 (UHR-9) |
| UNKNOWN | 가능 | 근태 실패 → `확인 못함` + 재시도 (UHR-12) · 계약해지 → `계약해지 요청이 있는지 확인하지 못했어요` (UHR-14) |
| NO_PERMISSION | **불가능(canonical)** | 홈의 여섯 읽기는 전부 **자기 uid 스코프**다(`getMyApplications`·`getMyMonthlyAttendances`·`getPendingIdCardRequestsForUser`·`getMyRenewalProposals`)와 공개 공고·사업장 공개 정보. rules 가 본인 문서를 거절하면 그것은 권한 없음이 아니라 장애이고 ERROR 로 떨어진다. **억지 fixture 를 만들지 않았다.** |

**이번에 고친 것 — 돈이 0으로 보였다:** 근태 조회 실패가 `_homeLoadFailed` 에
잡히지 않아 `_attendances = []` 로 계산됐다. 결과는 `근무 완료 0원` ·
`예상 수입 0원` · `아직 이번 달 수입이 없어요` — **못 읽은 달을 "번 돈이 없다"고
말한 것**이다. `_attendancesFailed` 를 도입해 두 금액을 `확인 못함` 으로, 빈 상태
문구를 차단하고 재시도 줄을 붙였다(UHR-12 · 제거 대조 FAIL 확인).

**계정 전환 시 화면에 남은 기존 state — 정정:**
production 의 계정 전환은 `AuthWrapper` 가 `currentUser == null` 구간에서
`LoginScreen` 을 그리므로 `UserHomeScreen` 의 State 가 **파괴된다.** 즉 이전
사용자의 **이미 그려진** 값이 새 계정 화면에 남지는 않는다. 첫 보고의
"계정 전환 후 이전 사용자의 근무가 새 계정 홈에 앉았다" 는 **위젯 수준 재현
(UHR-11)** 에서는 참이지만 **production 경로로는 입증되지 않았다** — 이 문장을
정정한다. uid 가드는 그 위험군에 대한 이중 방어로 유지한다.

**대신 같은 uid 에서 실제로 도달하는 순서 역전을 찾았다:**
`_loadHomeData` 의 `unawaited` 꼬리(연장 제안 · 급여 보완)는 `_isLoadingHomeData`
직렬화 **밖**이다. 1번 로드의 꼬리가 2번 로드 완료 뒤 도착하면 사라진 제안이
되살아난다 → **seq 가드가 고치는 실제 사건**(UHR-15, seq 제거 시 FAIL).
본문은 겹치지 않는다(UHR-10 을 실제 경로 `앱 복귀` 로 다시 측정 — 이전 측정에
쓴 fling 은 RefreshIndicator 를 깨우지 못해 근거가 되지 못했다. 그 측정 방법을 교체했다).

### C. P21-N/G — 알림·FCM 진입과 leaf 6

**payload 대상·권한(기존 R5.1 증거에 연결):** 권한이 걸린 타입은 `type` 기준으로
canonical dispatcher 에 넘어가고, 근로자 목적지(`attendance_check`·`my_reviews`·
`my_applications`·`my_schedule`)는 **인자를 받지 않는다** — 목적지가 현재 계정으로
다시 읽으므로 payload 가 다른 사람의 데이터를 열 수 없다. **stale:** 알림 화면의
재확인 경로는 `reconfirmRespondedAt` 를 먼저 보고 이미 처리됐으면 안내 후
일정 화면으로 보낸다. **뒤로:** `_pushFcmScreen` 은 root Navigator 에
`RouteSettings(name:'fcm:<key>')` 로 push 하고 같은 key 가 top 이면 중복 push 를
건너뛴다 → 뒤로는 탭 루트로 돌아온다. 새 경로를 만들지 않았다(EVIDENCE LINK).

| leaf | 역할 | 시작점 | 뒤로 | headerContent | 헤더 TabBar | shell `onRefresh` | 판정 |
|---|---|---|---|---|---|---|---|
| `apply_prerequisites` | 지원자 | 공고 상세 · 내 지원 · 지원 다이얼로그 | 호출 화면 | 0 | 0 | 0 | 순수 교체 가능 |
| `subadmin_leave` | **SubAdmin** | 설정 ×2 | 설정 | 0 | 0 | 0 | 순수 교체 가능 |
| `attendance_check` | 지원자 | 홈 Hero · 알림 · **FCM** | 탭 루트/호출 화면 | 0 | 0 | **1** | body 에 `RefreshIndicator` 중복 — shell 인자만 제거하면 교체 가능 |
| `interim_settlement_request` | 지원자 | 내 지원 | 호출 화면 | 0 | 0 | **1** | body `RefreshIndicator` 신설 필요 |
| `my_reviews` | 지원자 | 알림 · 설정 · **FCM** | 탭 루트/설정 | 0 | 0 | **1** | body `RefreshIndicator` 신설 필요 |
| `common/settings` | 역할 공유 | MY 탭 · 관리 탭 | 탭 루트 | **1** | 0 | 0 | 단순 교체 아님(P1-6 에서 역할 분기 완료) |

전환은 하지 않았다.

### D. 범위 판정

| ID | CODE | 행동 | RENDER | DEV READ | DEVICE | NOT SEEN |
|---|---|---|---|---|---|---|
| P21-N | 종료 | 종료(URN-1~3) | 종료 | 없음 | 대기 | 실기기 FCM cold-start |
| P21-H | 종료 | 종료 | 종료(6조합) | 없음 | 대기 | — |
| P21-R | 종료(표 A) | **부분** — 12경로 중 1·10 실행, 나머지는 CODE | 종료 | 없음 | 대기 | 2·3·4·5·6·7·8·9·11·12 의 제스처 |
| P21-E | 종료 | 종료(UHR-10·12·14·15) | 종료 | 없음 | 대기 | NO_PERMISSION(도달 불가) |
| P21-G | 종료(실측표) | N/A(전환 안 함) | N/A | 없음 | 대기 | — |

**BLOCKER 기록**
- `[BLOCKER-P2-HOME-LONGTERM-TODAY-CTA]` — CODE/행동 **수용**, DEVICE/PRODUCT **대기**.
- `[BLOCKER-P2-HOME-CROSS-UID-STALE-DATA]` — CODE/행동 **수용**(가드 유지), 단
  **production 재현 경로는 계정 전환이 아니라 같은 uid 의 `unawaited` 꼬리**다(위 B).
  DEVICE/PRODUCT 대기.
- 새 BLOCKER 는 열지 않았다. 야간 근무 퇴근 진입점은 **RESIDUAL** 로 남긴다.

**P2-1 판정:** CODE **종료** · RENDER **종료**(P21-R 행동은 부분, 범위 명시) ·
DEVICE/PRODUCT **대기**. P2 전체와 실기기는 계속 대기.

### E. 증거·회귀 (이번 결산분)

- `user_home_content_render_test` **24건**(UHR-1~18 + 6조합) · `user_root_tab_navigation_test` **3건**
- 제거 대조 3종: Hero 술어 · seq 가드 · `_attendancesFailed` — 각각 해당 테스트 FAIL 후 복원 PASS
- 영향집합 **3966 PASS / 6 FAIL** — 6건 전부 기준선(HEAD)에서도 같은 이름으로 실패하는 기존 항목
- `flutter analyze lib test` **No issues** · DEV READ 없음 · DEVICE 미실행

---

## R7-P2-1 잔여 — 자정 넘긴 근무의 Home 퇴근 진입점 (2026-09-28)

기준 제출 `6a96276`(기준 `7fe1ce3`). 수행 전 HEAD·dirty 확인(tracked 0, untracked 8).
owner P21-R/P21-H. 공유 DEV READ ONLY — 출퇴근/지원/확정/급여 쓰기·fixture·CF·Rules·
PROD·APK 없음. 상태 전이는 **주입된 읽기 경계**에서만 확인했다.

### 1. READ — 같은 근무의 정확한 자격

목적지 `attendance_check_screen` 의 어제 기록 **제외** 조건(`visibleWorks`)과
홈 술어를 같은 벌로 맞췄다.

| 축 | 목적지(`attendance_check_screen`) | 홈(`_openOvernightAttendance`) |
|---|---|---|
| 대상 | `confirmedStatuses` + 단기 `workDate ∈ {오늘, 어제}` / 장기 `isWorkingOnDate(오늘)` | 어제 **근태 기록**에서 출발한다 |
| 이미 퇴근 | `att.checkOut != null` → 숨김 | `att.checkOutAt != null` → 제외 |
| 자동 처리 | `status == 'missed_checkout'` → 숨김 | 동일 |
| 미출근 | `NO_SHOW` · `absent` → 숨김 | 동일 **+ `checkInAt == null` 도 제외** |
| 취소·해지 | — | 지원서가 `confirmedStatuses` 아니면 제외 |
| 소유 | 서버 self-uid | `att.userId != uid` 재확인 |

**"workDate == 어제" 만으로 CTA 를 만들지 않는다.** 자격은 *실제로 출근했고
퇴근이 남은 진행 중인 기록*이다. 목적지는 `att == null` 인 어제 근무도 목록에
남기지만(미출근), 홈은 `checkInAt == null` 에서 잘라 **거짓 퇴근 CTA 를 만들지
않는다** — 두 화면의 차이를 의도적으로 좁힌 쪽이다.

**entity key:** `attendance.id` ↔ `attendance.applicationId` ↔ `application.id`.
날짜는 `attendance.workDate`(= 출근한 날의 KST 자정), 시각은 `att.checkIn`(반올림
적용 후 최종 출근 시각). 약속 시각(`app.startTime/endTime`)은 판정에 쓰지 않는다 —
예정 시간이 지났다는 사실은 퇴근 자격이 아니다.

**오류·부분 자료**

| 상황 | 처리 |
|---|---|
| 이번 달 근태 조회 실패 | `_overnightUnknown` → **`어제 근무의 퇴근 여부를 확인하지 못했어요` + 다시 시도**. 침묵하지 않는다(미퇴근은 `missed_checkout` 으로 자동 처리된다) |
| 지난달 꼬리 조회 실패(1일) | 위와 동일 표면 |
| 지원 내역 조회 실패 | 확정 여부를 확인할 수 없으므로 **CTA 를 만들지 않는다**. 사용자는 같은 화면의 `지원 현황을 불러오지 못했어요` + 재시도를 본다 |
| 로딩 중 | 카드 없음(자리 차지 없음) |

### 2. PATCH — 현재 reader 로 판정, 달 경계만 같은 entity 보완

판정에 필요한 자료는 **이미 홈 reader 에 있다**(`myApplications` + 이번 달
`myMonthlyAttendances`). 단 하나의 구멍은 **달의 1일**이다 — 그날의 "어제" 는
지난달이라 이번 달 조회에 들어오지 않는다. 그래서 `now.day == 1` 일 때만
**같은 CF·같은 self-uid 계약**으로 지난달을 한 번 더 읽어 `_prevMonthTail` 에
담는다. 기존 `Future.wait` 에 합류시켜 **왕복이 늘지 않는다**. polling·listener·
full reload·새 query·새 권한 **없음**.

**Hero 우선순위와 충돌하지 않는다.** 퇴근은 Hero 의 새 상태가 아니라
**별도 카드**다(`_buildOvernightCheckoutCard`, Priority Hero **앞**). 이유는
이미 시작된 일이 앞으로의 약속보다 먼저이고, 무엇보다 **둘 다 보여야** 하기
때문이다. 오늘 확정 근무가 함께 있으면 퇴근 카드와 `오늘의 근무` Hero 가
동시에 렌더된다(UHR-23). 알림으로 대체하지 않았다 — 카드 자체가 행동이다.

문구: `퇴근 기록이 남았어요` / `M/D 근무 · 사업장 · HH:mm 출근` / `퇴근하기`.
어제 근무를 "오늘 출근"으로 부르지 않는다.

### 3. 경계 사례 결과

| 사례 | 결과 | 증거 |
|---|---|---|
| (A) 23시 출근 → 익일 미퇴근 | 카드 표시 · `퇴근하기` → **실제로 `AttendanceCheckScreen` 열림** | UHR-18 · UHR-19(행동) |
| (B) 자정 전 정상 퇴근 완료 | 카드 없음 | UHR-20 |
| (C) 미출근 / NO_SHOW / `missed_checkout` / `absent` | 전부 카드 없음 (+ **양성 대조** 1건으로 반복 장치가 공허하지 않음을 고정) | UHR-21 |
| (C2) 취소된 지원서의 어제 기록 | 카드 없음 | UHR-22 |
| (D) 어제 진행 중 + 오늘 또 다른 확정 | **둘 다** 표시(`퇴근하기` + `출근하기`) | UHR-23 |
| (E) 근태 읽기 실패 | `확인하지 못했어요` + 재시도, CTA 없음 | UHR-24 |
| (E2) 지원 내역 읽기 실패 | CTA 없음 + 기존 실패 문구 | UHR-25 |
| (F) 23:59 → 00:00 KST | 자정 전 = Hero(카드 없음) · 자정 후 = 카드 — **빈틈도 중복도 없다** | UHR-26 |
| 타인 기록 | 카드 없음(`userId` 재확인) | UHR-27 |
| 시간대 | 비교 양쪽을 `FormatHelper.toKstDate` 로 정규화 — 기기 로컬 자정을 쓰지 않는다 | UHR-28 (temporal owner P1-3 재사용) |
| 320/360/412dp × 1.3/2.0 | 퇴근 카드 + 오늘 Hero 동시 렌더, 예외 0 | UHR-R 6조합 |
| 복귀 갱신 | 목적지에서 돌아오면 `_loadHomeData()` 재호출 → 퇴근 후 카드가 사라진다 | CODE(카드 `onTap`) · 행동 미실행 |

**수정 전/후:** UHR-18 은 수정 전 "진입점 없음"을 고정한 반례였다. 이번에
**같은 fixture 에서 진입점이 있어야 한다**로 뒤집었고, 카드를 제거한 대조에서
FAIL 하는 것을 확인했다(복원 후 PASS).

**기존 오늘 근무 회귀:** UHR-1~4·UHR-23·UHR-26 전반부에서 `오늘의 근무` Hero 가
그대로다. 오늘 진행 중인 근무는 카드가 **가져가지 않는다**(중복 방지).

### 4. writer → reader → 술어 → 행동 → 목적지 → 복귀

| 단계 | 내용 |
|---|---|
| writer / state | 출퇴근 화면의 체크인이 `attendances/{id}` 에 `checkIn`·`workDate`(KST 자정)·`status` 를 쓴다. 미퇴근은 배치가 `missed_checkout` 으로 전이시킨다 |
| Home reader | `myApplications(uid)` + `myMonthlyAttendances(년,월)` (+ 1일에만 지난달 1회) — 전부 기존 self-uid CF |
| 술어 | 어제(KST) · `checkIn != null` · `checkOut == null` · status ∉ {missed_checkout, NO_SHOW, absent} · app ∈ confirmedStatuses · `userId == uid` |
| Hero/행동 | Priority Hero **앞**의 독립 카드, `퇴근 기록이 남았어요` / `퇴근하기` |
| 목적지 | `AttendanceCheckScreen()` (인자 없음) — 같은 제외 술어를 쓰므로 그 근무가 목록에 남는다(UHR-19 가 두 소스의 술어를 함께 고정) |
| 복귀 | pop 후 `_loadHomeData()` → 퇴근이 기록되면 카드가 사라진다 |

### 5. 범위·잔여

| 구분 | 결과 |
|---|---|
| CODE | 종료 |
| 행동 | 종료 — 카드 탭 → 목적지 도달 실행(UHR-19). 퇴근 **버튼 누름**은 미실행(공유 DEV 쓰기 금지) |
| RENDER | 종료 — 경계 9종 + 6조합 |
| DEV READ | 없음 |
| DEVICE | **대기** |

- `[BLOCKER-P2-HOME-NIGHT-SHIFT-CHECKOUT-MISSING]` → **CODE/행동/RENDER 수용**,
  DEVICE/PRODUCT 대기. RESIDUAL `[R7-P2-1-RESIDUAL-HOME-NIGHT-SHIFT-CHECKOUT]` 는 닫는다.
- 새 RESIDUAL `[R7-P2-1-RESIDUAL-ATTENDANCE-SCREEN-LOCAL-MIDNIGHT]` — 목적지는
  `todayStart`/`yesterday` 를 **기기 로컬 자정**으로 만든다(`DateTime(y,m,d)`).
  홈은 KST 정규화다. KST 기기에서는 일치하지만 비-KST 기기에서 하루 어긋날 수 있다.
  **이번에 건드리지 않았다**(근태 화면 재감사 금지) — owner P1-3 temporal.
- `[BLOCKER-P2-HOME-CROSS-UID-STALE-DATA]` — production cross-uid 재현 주장 **철회**
  (AuthWrapper 가 계정 변경 시 State 를 파괴한다). 같은 uid 의 `unawaited` 꼬리
  응답 역전(UHR-15)은 **별도 CODE 수정 증거로 재분류**한다.
- `[BLOCKER-P2-HOME-ATTENDANCE-FAILURE-AS-ZERO-INCOME]` — UHR-12 범위에서
  CODE/RENDER 수용 · DEVICE 대기 유지.
- 12 CTA 중 나머지 10 제스처와 FCM cold-start 는 **DEVICE/P4·P5** 로 남긴다 —
  코드 매핑을 사용자 행동 실행으로 쓰지 않는다.

**P2-1 판정:** CODE **종료** · RENDER **종료** · 행동 종료(위 단서) ·
DEVICE/PRODUCT **대기**.

#### 최소 실기기 확인안 (이번에 바뀐 자리만)

1. 자정을 넘겨 근무 중인 계정으로 00:00 이후 홈 → `퇴근 기록이 남았어요` 가 보이고
   탭하면 그 근무가 출퇴근 화면 목록에 있는지. 퇴근 후 홈 복귀 시 카드가 사라지는지.
2. 매월 **1일** 00:00 이후 같은 확인(지난달 꼬리 경로).
3. 어제 `NO_SHOW`/미출근 계정에서 카드가 **뜨지 않는지**.

---

## R7-P2-1 잔여 — Home→출퇴근 화면 KST 날짜 일치 (2026-09-28)

기준 제출 `d6a7274`(기준 `6a96276`). 수행 전 HEAD·dirty 확인(tracked 0, untracked 8).
`[VERIFY-R7-P2-1-ATTENDANCE-LOCAL-MIDNIGHT]`. 공유 DEV READ ONLY — 쓰기·fixture·CF·
Rules·PROD·APK 없음. **사용자에게 기기 시간대 조작을 요구하지 않았다.**
수용된 UHR-18~28·UHR-R 은 재실행하지 않았고(회귀로만 통과 확인), 실제 퇴근 mutation 은
여전히 미검증이다.

### 1. 판정 — **실제 불일치가 있다. NO PATCH 아님.**

현재 HEAD 에서 확인한 두 기준:

| 화면 | 오늘/어제를 만드는 식 | 성질 |
|---|---|---|
| Home | `FormatHelper.toKstDate(now)` · `toKstDate(att.workDate)` | **instant 기반** — 기기 시간대와 무관 |
| 출퇴근(수정 전) | `DateTime(now.y, now.m, now.d)` · `DateUtils.isSameDay(workDate, …)` | **필드 기반** — `Timestamp.toDate().toLocal()` 이 만든 기기 로컬 필드 |

저장된 근무일은 KST 자정 instant 다. 비-KST 기기에서는 그 instant 의 **로컬 필드**가
KST 날짜와 다르므로 두 화면이 같은 근무를 다른 날로 부른다.

**도달 가능성:** `processMissedCheckouts` 는 자정 실행이면서 `createdAt` 이 **24시간
이상** 지난 문서만 `missed_checkout` 으로 바꾼다. 09-28 23:00 KST 체크인 건은
09-29 자정에 1시간밖에 안 됐으므로 마킹되지 않는다 → **09-29 하루 종일 퇴근 가능
상태**다. 따라서 아래 사례는 "이미 자동 처리돼 도달 불가"가 아니다.

| 기기 TZ / KST 시각 | canonical workDate·상태 | Home 카드 | 목적지 같은 근무 | 판정 |
|---|---|---|---|---|
| KST(+9) · 09-29 01:00 | 09-28 · checkIn 23:00, checkOut null, present | 표시 | **있음** | 일치(수정 전에도) |
| KST(+9) · 09-29 10:00 | 동일 | 표시 | **있음** | 일치(수정 전에도) |
| **UTC(+0) · 09-29 10:00** | 동일 | 표시 | **없음 → 수정 후 있음** | **불일치(방향 A)** |
| UTC(+0) · 09-29 01:00 | 동일 | 표시 | 있음 | 일치(정렬 구간) |
| **UTC(+0) · 09-29 20:00** | **09-29**(오늘) · checkIn 09:00, checkOut 18:00 | 없음(오늘=Hero) | **없음 → 수정 후 있음** | **불일치(방향 B)** — 오늘 끝낸 근무가 "어제 기록" 규칙에 걸려 사라졌다 |
| UTC(+0) · 09-29 10:00 | 09-28 · checkOut 06:00 | 없음 | 없음 | 일치(제외가 같이 움직인다) |
| UTC(+0) · 09-29 10:00 | 09-28 · 미출근 | 없음 | 있음(출근 후보) | **의도된 차이** — 퇴근 CTA 가 아니다 |
| UTC(+0) · 09-29 10:00 | 09-28 · NO_SHOW | 없음 | 없음 | 일치 |
| **UTC(+0) · 10-01 10:00** | 09-30 · checkIn 23:00 | 표시 | **없음 → 수정 후 있음** | **불일치(월말→1일)** |
| **UTC(+0) · 09-29 10:00** | 어제 진행 중 + 오늘 확정 2건 | 퇴근 카드 + 오늘 Hero | **1건만 → 수정 후 2건** | **불일치(같은 날 또 다른 근무)** |

**방향 두 가지:** 기기가 KST 보다 **뒤처진** 구간에서는 어제 근무가 사라지고(A),
같은 기기의 다른 시각대에서는 **오늘** 근무가 어제로 읽혀 사라진다(B). 기기가
KST 보다 **앞선** 경우는 같은 식의 부호만 반대인 대칭 사례다 — 이번 수정은
필드 의존 자체를 없애므로 두 방향이 함께 닫힌다.

**흉내 낸 방법(기기 조작 없음):** Dart 의 `DateTime` 은 instant 와 wall-clock 필드가
묶여 있어, "필드는 그 기기 것 · instant 는 그대로"를 만들 수 있는 것은 호스트
시간대(KST)와 UTC 두 가지뿐이다. 그래서 **UTC 기기**로 비-KST 기기를 대표했다.
시계는 `clock` 주입으로 제어하고, 근무일은 그 기기의 `Timestamp.toDate().toLocal()`
이 내놓을 값으로 준다 — production parser·필터를 그대로 지난다.

### 2. 최소 수정

`attendance_check_screen` 의 날짜 기준을 **날짜 owner(P1-3)의 KST** 로 옮겼다.
Home 에 local 시계 예외를 덧대지 않았다.

| 위치 | 전 | 후 |
|---|---|---|
| `todayStart` | `DateTime(today.y, today.m, today.d)` | `FormatHelper.toKstDate(today)` |
| 단기 후보 | `DateUtils.isSameDay(app.workDate, …)` ×2 | `toKstDate(app.workDate) == todayStart \|\| == yesterday` |
| 어제 기록 제외 | `DateUtils.isSameDay(att.workDate, yesterday)` | `toKstDate(att.workDate) == yesterday` |
| 장기 체크인 근무일 | `DateTime(todayDate.y,m,d)` | `FormatHelper.toKstDate(_now())` — 서버 docId 가 KST 다 |
| 홈 꼬리 판정 | `now.day == 1`(기기 로컬) | `toKstDate(_now()).day == 1` |

경계 두 칸을 새로 냈다: `AttendanceCheckReads`(읽기 2개) · `clock`(두 화면 모두,
production 은 null). **체크인·체크아웃 mutation 은 경계에 넣지 않았다.**
서비스 계층(`getTodayAttendance`)은 이미 `[PREDEVICE-ATTENDANCE-KST]` 로 KST 였다 —
남아 있던 것은 화면의 후보 필터뿐이다.

### 3. 보고 정밀도 정정 — 지난달 꼬리 읽기

앞 보고의 "왕복 증가 없음"은 **순차 대기 단계** 기준으로만 맞다. 정정한다:

| 축 | 사실 | 근거 |
|---|---|---|
| 순차 대기 단계 | 늘지 않는다 — 기존 `Future.wait` 의 5번째 원소로 **병렬** 합류 | 코드(`Future.wait([...4개, if (needsTail) ... else Future.value([])])`) |
| 원격 요청 수 | **매월 1일에 1회 증가**(4→5). 그 외의 날은 증가 0 | 계측 KDP-C1: `['2026-9']` 1회 · KDP-C2: 2회(`2026-10`+`2026-9`) |
| 실행 조건 | `toKstDate(_now()).day == 1` — **KST 1일에만** | 계측 KDP-C3: 기기(UTC)로는 9/30 21:00 이어도 KST 10/1 이면 읽는다 |
| 캐시 | `getMyMonthlyAttendances` 는 `{uid}_{y}_{m}` TTL 캐시를 쓴다 — 같은 날 반복 로드는 재요청이 아니다 | 서비스 코드 |

R8 전체 성능 재감사는 하지 않았다.

### 4. 범위

| 구분 | 결과 |
|---|---|
| CODE | 종료 — 두 화면이 같은 KST 기준을 쓴다 |
| 행동 | 종료 — **같은 fixture 로 두 production 화면을 돌려** 목록 포함 여부를 비교(13건). 목적지가 열렸다는 사실만으로 판단하지 않았다 |
| RENDER | 종료 — 기존 UHR-R 6조합 회귀 |
| DEV READ | 없음 |
| DEVICE / PRODUCT | **대기** — 실제 퇴근 버튼 mutation 미검증 |

- `[VERIFY-R7-P2-1-ATTENDANCE-LOCAL-MIDNIGHT]` → **불일치 입증 → 수정 → 종료.**
  `[R7-P2-1-RESIDUAL-ATTENDANCE-SCREEN-LOCAL-MIDNIGHT]` 는 닫는다.
- 실제 오판이 입증됐으므로 `[BLOCKER-P2-HOME-DEST-DATE-MISMATCH]` 로 분류하고
  **수정 전 5건 FAIL → 수정 후 13건 PASS** 로 전후를 남긴다.
- 남은 관찰: 수입의 월 조회는 여전히 기기 로컬 `now.year/now.month` 를 쓴다.
  이번 범위(Home→출퇴근 날짜 일치)가 아니고 급여 정책 재감사도 하지 않으므로
  `[R7-P2-1-RESIDUAL-INCOME-MONTH-LOCAL]` 로만 남긴다 — owner P1-5/P1-3.
- 12 CTA 중 나머지 9 제스처·FCM cold-start 는 DEVICE/P4·P5 로 유지.

**P2-1 판정:** CODE **종료** · RENDER **종료** · 행동 종료(퇴근 mutation 제외) ·
DEVICE/PRODUCT **대기**. P2 전체는 별도.

#### 최소 실기기 확인안

1. 기기 시간대를 **KST 가 아닌 곳**(예: UTC)으로 둔 단말에서, 자정을 넘겨 근무 중인
   계정으로 홈 → 퇴근 카드 탭 → **그 근무가 목록에 있는지**.
2. 같은 단말에서 **오늘 퇴근까지 끝낸 근무**가 목록에서 사라지지 않는지.
3. 매월 1일 KST 기준으로 꼬리 경로가 동작하는지.

---

## R7-P2-1 최종 경계 — Home 수입 월의 KST 기준 (2026-09-28)

기준 제출 `61c139a`(기준 `d6a7274`). 수행 전 HEAD·dirty 확인(tracked 0, untracked 8).
`[VERIFY-R7-P2-1-INCOME-MONTH-LOCAL]`. 공유 DEV READ ONLY — 급여·이체·지원·출퇴근
쓰기·fixture·CF·Rules·PROD·APK 없음. **기기 TZ 조작을 요구하지 않았다.**
수용된 Home→AttendanceCheck 결과·야간 카드·CTA·P1-3 기준은 재감사하지 않았다.
급여 계산·지급 상태·주휴·계약 snapshot 은 열지 않았다.

### 1. READ — 월 기준이 무엇을 말하고 있었나

| 소비자 | 라벨/선택 월 | 실제 조회 월 | 금액 모집단 | 기준(수정 전) |
|---|---|---|---|---|
| Home 수입 요약 | `'${now.year}년 ${now.month}월 ›'` | `myMonthlyAttendances(now.year, now.month)` | `CalendarHelper.getConfirmedIncome/settlementPendingCount(_attendances, now)` | **기기 로컬** |
| Home → 상세 | `IncomeDetailScreen(initialYear: now.year, initialMonth: now.month)` | 상세가 `_year/_month` 로 재조회 | 상세의 자체 필터 | **기기 로컬**(홈에서 넘어온 값) |
| IncomeDetail 기본 선택 | `initState` 에서 `widget.initial*` 1회 — 이후 "지금"으로 덮지 않는다 | `getMyMonthlyAttendances(_year, _month)` | `a.workDate.year == _year …` | 선택 월은 **유지**(정상) |
| 월 시트 활성 규칙 | `_confirmedFutureYearMonths` · `_maxAccessibleYear` | — | `app.workDate.year/month` vs `DateTime.now()` | **기기 로컬** |
| 서비스 캐시 key | `{uid}_{year}_{month}` | — | — | 요청 연월 그대로 |
| 서버 원장 | — | `getMyMonthlyAttendances` 는 `Date.UTC(y,m-1,1) − 9h` ~ `Date.UTC(y,m,1) − 9h` | — | **KST 달력월** |

**핵심 어긋남:** 서버는 **KST 달력월**로 잘라 주는데, 클라이언트는 요청 연월도
필터도 **기기 로컬 필드**로 만들었다. `workDate` 는 KST 자정 instant 이고
`Timestamp.toDate().toLocal()` 로 읽히므로 비-KST 기기에서 두 자가 다르다.

### 2. 사용자에게 보인 것 — 경계 실행 결과

표본은 **월별로 다른 액수**다: KST 9/30 근무 90,000원 · KST 10/1 근무 10,000원.
시각은 **KST 10/1 05:00**(UTC 기기 달력으로는 아직 9/30 20:00).

| 기기 | 보이는 월 라벨 | 조회 연월 | 반환 금액 | 상세 첫 선택 | 수정 전 |
|---|---|---|---|---|---|
| KST | `2026년 10월` | `2026-10` | `10,000원` | 10월 | 이미 정상 |
| **UTC** | `2026년 10월` | `2026-10` | `10,000원` | 10월 | **수정 후**. 수정 전에는 `2026년 9월` · `2026-9` · 10/1 금액 누락 · 상세도 9월 |

즉 수정 전 UTC 기기에서는 **① 라벨이 지난달을 말하고 ② 지난달 원장을 읽고
③ KST 1일에 번 돈이 이번 달에서 사라지고 ④ 상세까지 지난달로 열렸다.**
같은 entity·같은 event 의 돈과 기간이 서로 다른 이름을 갖고 있었다.

**전후 대조:** 월 기준을 기기 로컬로 되돌리면 **5건 FAIL**(IMK-1·2·3·4·6, 전부
UTC 기기), 복원하면 **11건 PASS**. KST 기기 케이스는 전후 모두 PASS —
결함이 기기 시간대 의존임을 같은 파일이 보여 준다. 월 중간(10/15)은
전후 모두 두 기기가 같은 달을 말한다(IMK-5, 경계 한정 회귀).

### 3. 최소 조치 (branch 1 — 수정)

기존 KST owner(P1-3 `FormatHelper`)를 재사용했다. 새 poll·listener·full reload 없다.

| 위치 | 전 | 후 |
|---|---|---|
| `FormatHelper` | — | `isSameKstMonth(workDate, month)` 신설 — **기록 쪽만** KST 로 정규화하고 월 표식은 호출부의 civil 연월을 그대로 쓴다 |
| `CalendarHelper` 월 필터 6곳 | `workDate.year/month == focusedDay.year/month` | `isSameKstMonth(...)` |
| Home 수입 섹션 | `DateTime.now()` | `toKstDate(_now())` — 라벨·금액·상세 인자가 한 값에서 나온다 |
| Home 원장 조회 | `now.year/month` | `kstNow.year/month`(= 서버가 자르는 자) |
| IncomeDetail 자체 필터 | `a.workDate.year == _year …` | `isSameKstMonth(a.workDate, DateTime(_year,_month))` |
| IncomeDetail "지금" 5곳 | `DateTime.now()` | `toKstDate(DateTime.now())` — 미래 이동 방지·시트 활성 규칙 |
| MySchedule 확정임금 필터 | 필드 비교 | `isSameKstMonth(...)` |

**건드리지 않은 것:** `_year/_month` 자체(명시 선택 월). 상세는 `initState` 에서
한 번만 읽고 이후 "지금"으로 덮지 않는다 — 자정이나 재조회가 선택 월을 현재
월로 바꾸지 않는 것을 렌더로 고정했다(IMK-7).

**월 시트 활성 규칙·캐시 key 영향:** 시트의 "미래 월 활성" 판정과
`_maxAccessibleYear` 가 KST 연월로 바뀌었다. 활성/비활성이 달라지는 지점은
기기 로컬과 KST 가 갈리는 **경계 시각**뿐이고, 그때의 정답은 KST 다.
서비스 캐시 key(`{uid}_{y}_{m}`)는 **요청 연월을 그대로 쓰므로 형식이 바뀌지
않았다** — 다만 경계 시각에 요청하는 연월이 달라지므로 그 시각에는 다른 키를
채운다(캐시 무효화나 마이그레이션 불필요).

**ERROR/UNKNOWN 은 0원이 되지 않는다:** 원장 조회가 실패하면 `확인 못함` +
재시도이고(기존 `_attendancesFailed`), 그 상태에서도 **말하는 달은 흔들리지
않는다**(IMK-6).

### 4. 범위·종료

| 구분 | 결과 |
|---|---|
| CODE | 종료 |
| 행동 | 종료 — 홈 헤더 탭 → `IncomeDetailScreen` 인자 확인까지 production 경로로 실행(IMK-4). 상세 내부 월 시트 **제스처**는 미실행 |
| RENDER | 종료 — 두 기기 × 경계/월중간, 정상 금액·0·조회 실패 |
| DEV READ | 없음 |
| DEVICE / PRODUCT | **대기** |

- `[VERIFY-R7-P2-1-INCOME-MONTH-LOCAL]` → **불일치 입증 → 수정 → 종료.**
  `[R7-P2-1-RESIDUAL-INCOME-MONTH-LOCAL]` 를 닫고
  `[BLOCKER-P2-HOME-INCOME-MONTH-LOCAL]` 로 분류(CODE/행동/RENDER 수용 · DEVICE 대기).
- 이름만 적어 이관하지 않았다 — 소비자 5곳(Home 요약 · Home→상세 인자 ·
  IncomeDetail 필터/시트 · MySchedule 확정임금 · MonthlyStatsCard)을 모두
  같은 자로 맞췄다. `MonthlyStatsCard` 는 `CalendarHelper` 를 통해 함께 닫힌다.
- 남은 별도 항목: **P2 전체 · 실기기/PRODUCT · 출퇴근 실제 mutation ·
  12 CTA 중 9 제스처 · FCM cold-start · 상세 월 시트 제스처.**

**P2-1 판정:** CODE **종료** · RENDER **종료** · 행동 종료(위 단서) ·
DEVICE/PRODUCT **대기**.

#### 최소 실기기 확인안

1. 기기 시간대를 **KST 가 아닌 곳**으로 둔 단말에서 **매월 1일 KST 새벽**에 홈 →
   수입 라벨이 그 달인지, 1일 근무 금액이 들어와 있는지.
2. 같은 단말에서 `N년 M월 ›` → 상세가 **같은 달**로 열리는지.
3. 상세에서 과거 월을 고른 뒤 자정을 넘겨도 그 월이 유지되는지.

---

## R7-P2-2 — 지원자 일자리·공고 상세·지원 흐름 (2026-09-28)

기준 제출 `95a67c8`. 수행 전 HEAD·tracked dirty 0·untracked 8건 확인·보존.
공유 DEV READ ONLY — 지원/확정/급여/계약 쓰기·fixture·CF·Rules·PROD·APK 없음.
P2-1 결과와 R1~R6 Golden Path·R5 권한 계약은 재감사하지 않았다.

### 0. 실제 도달 경로 (코드로 확정)

| 진입 | 목적지 | entity key | 판정 근거 |
|---|---|---|---|
| 하단 일자리 탭 | `UserJobTab` | — | `UserRootScreen` index 1 |
| 홈 날짜 CTA | `UserJobTab` | `pendingJobDate` → `didChangeDependencies` 에서 **1회 소비 후 clear** → `_filter.dateRange` | 소스 + 실행(UJT-2·5) |
| 목록 카드 탭 | `JobPostingScreen(to:, workDetails:, slotDate:)` | `to.id` + **선택한 하루** | 실행(UJT-6·7) |
| 홈 추천 카드 | `JobPostingScreen(to:, workDetails:)` | `to.id` | P2-1 표 재사용 |
| 알림 · **FCM** | `JobPostingScreen(toId:)` | `toId` 만 — 목적지가 재조회 | 소스(`fcm_service:541`·`notification_screen:1472`) · 제스처 **NOT SEEN** |
| 상세 → 지원 준비 | `ApplyPrerequisitesScreen.show(isFlexType:)` | 없음(계정 스코프) | 실행(APS-1) |
| 지원 후 | `MyApplicationsScreen` | `application.id` | 소스 |

**스냅샷 vs 재조회:** 카드가 넘기는 `to`·`workDetails` 는 **첫 화면용 seed** 이고,
상세는 `_loadData()` 로 다시 읽어 `_slot` 을 만든다 — 정원·확정 수는 `_slot` 이
전달값보다 **우선**한다(`_slot?.… ?? widget.slot… ?? _to!.…`). 즉 **판정 근거는
목적지의 재조회**이고, 전달값은 낡아도 수치를 만들지 않는다.

### 1. 확정 결함과 수정

| # | ID | 무엇이 틀렸는가 | 사용자에게 무슨 일이 | 고친 방식 | 증거 |
|---|---|---|---|---|---|
| 1 | P22-L | 날짜 같은 **클라이언트 조건**이 첫 페이지를 다 걸러 내면 목록이 비는데, 그때 화면은 `필터 조건에 맞는 공고가 없습니다` 라고 말했다. 같은 화면 머리말은 `N개 이상` 이라고 말하는 중이었다 | **읽지 않은 페이지가 남아 있는데 "없다"** — 게다가 `더 많은 공고 보기` 버튼은 ListView 안에 있어 빈 화면에서는 **길까지 닫혔다** | 남은 페이지가 있으면 `아직 이 조건의 공고를 찾지 못했어요` + 더 보기, 그리고 이어 읽기 기준을 **서버 페이지**에서 **화면에 남은 것**으로 | UJT-1·3(양성 대조) |
| 2 | P22-N | 홈에서 고른 하루로 걸러 놓고 **첫 페이지에 그 날이 없으면 거기서 멈췄다** | 홈이 보낸 날짜의 공고를 영영 못 본다 | `_loadAllTOs` 의 이어 읽기 조건을 `displayList.isEmpty` 로 | UJT-2 |
| 3 | P22-N | 카드 → 상세에서 **선택한 하루가 사라졌다** | 이미 고른 날짜를 상세에서 다시 찾아야 한다 | 목록이 **하루**를 가리킬 때만 `slotDate` 로 전달(범위·미선택은 null) | UJT-6·7 |
| 4 | P22-G | 지원 준비 항목 행의 액션 버튼에 상한이 없었다 | 320dp·배율 2.0 에서 **4개 항목 전부 15px 잘림** | 넘칠 때만 폭 40% 로 묶고 라벨을 줄바꿈 — 항목 이름도 행동 이름도 지우지 않는다 | APS-R 4조합 |
| 5 | P22-G | `ApplyPrerequisitesScreen` 이 Gradient shell | (디자인 일관성) | **3축 실측 후 순수 교체** — `AppPageScaffold(title:, body:)` | APS-1·2·3 |

**전후 대조:** 1~3을 되돌리면 **7 FAIL**, 복원하면 **11 PASS**. UJT-3·4·5·7 은
전후 모두 PASS — 양성 대조가 붙어 있어 공허하지 않다.

### 2. NO PATCH — 근거를 남긴 판정

| ID | 항목 | 근거 |
|---|---|---|
| P22-A | 지원 실패·마감·정원 변경·자격 미충족이 성공처럼 보이는가 | `ApplyResult` 가 success / alreadyApplied / failed / **unknown** 네 갈래이고, UNKNOWN 은 실패로 말하지 않고 `getMyApplicationsForTOFresh` 로 **canonical 재확인** 후 `reconciledAsApplied` 한다. 확인 못 하면 "내 지원 목록에서 확인해주세요"(경고)로 남는다 — 이미 R8-P3A.1 이 세운 계약 |
| P22-A | 겹치는 지원을 apply 단계에서 막는가 | 막지 않는다 — 지원=관심. 정책 그대로(`CLAUDE.md` §6) |
| P22-M | 자동취소가 generic 배지로 뭉개지는가 | 사유 코드별 문구가 있다(`SCHEDULE_CONFLICT` → `다른 업무가 확정되어 자동 취소되었어요`, `TO_EXPIRED`, `TO_DELETED` …). 자동취소 writer 는 기존 증거 재사용, 화면 projection 만 확인 |
| P22-M | 남의 지원서가 열리는가 | 단건 조회에 `one.uid != uid` 소유 검증이 있다(`my_applications_screen:300`) |
| P22-E | 목록의 늦은 응답 | `_generation` + `_fetchInProgress` 로 `_loadAllTOs`↔`_loadMoreTOs` 가 서로를 버린다. 같은 uid 의 `_loadAllTOs` 본문은 겹치지 않는다 |
| P22-E | 조회 실패를 "공고 없음"으로 캐시하는가 | `_loadFailed` 가 먼저 갈린다(`공고를 불러오지 못했습니다` + 다시 시도) — UJT-4 로 실행 확인 |
| P22-L | 추천 2개·homeRegion city 우선·거리 V2 | 이번에 건드리지 않았다(P2-1 판정 유지) |

### 3. 남은 관찰 · owner

| 항목 | 상태 | owner / 닫는 조건 |
|---|---|---|
| FCM·알림 → 공고 상세 **제스처** | **NOT SEEN** | DEVICE (`[R7-P2-2-RESIDUAL-POSTING-FCM-GESTURE]`) |
| 실제 **지원 쓰기**(`callableApplyToTO`) 와 자동취소 전이 | **미실행** — 공유 DEV READ ONLY | 격리 Emulator / DEVICE |
| 상세 화면 내부(날짜·업무슬롯 선택, FULL/마감 배지)의 렌더 | **미관찰** — 이번은 목록→상세 **전달**까지 | `[R7-P2-2-RESIDUAL-POSTING-DETAIL-RENDER]` · P2-2 후속 |
| `MyApplicationsScreen` 렌더·필터 | **미관찰**(소스 계약만) | `[R7-P2-2-RESIDUAL-MY-APPLICATIONS-RENDER]` |
| 계정 전환 중 목록 late 응답 | uid 가드 없음. AuthWrapper 가 State 를 파괴하므로 production 재현 미입증(P2-1 정정과 동일) | 관찰 기록 |
| Gradient 나머지 4곳 | **전환하지 않음** — 묶지 않는다 | `[R7-P2-RESIDUAL-USER-SHELL-UNIFY]` |

### 4. 증거

| 구분 | 내용 |
|---|---|
| CODE | 진입 경로표 · 스냅샷/재조회 우선순위 · ApplyResult 네 갈래 |
| 행동 | `user_job_tab_partial_truth_test` **11건**(홈 날짜 CTA 소비 → 조건 적용 → 이어 읽기 → 카드 탭 → 상세 인자) · `apply_prerequisites_shell_render_test` **7건**(열기·뒤로·CTA·4조합) |
| RENDER | 320/412dp × 1.3/2.0 두 화면 |
| 수정 전 대조 | 7 FAIL → 복원 11 PASS |
| DEV READ | 없음 |
| DEVICE | **미실행** |

새 경계: `lib/screens/user/tabs/user_job_tab_reads.dart`(읽기 3개, production 은 null).
지원(쓰기)은 경계에 넣지 않았다.

#### 최소 실기기 확인안

1. 홈에서 **며칠 뒤 날짜**를 골라 일자리 탭 진입 → 첫 화면에 결과가 없더라도
   "없습니다"가 아니라 더 찾는 중/더 보기가 보이고, 실제로 그 날 공고가 나타나는지.
2. 목록에서 날짜를 고른 채 카드를 눌러 상세가 **그 날짜로** 열리는지.
3. 지원 준비 화면을 **글자 크게(2.0)** 로 열어 4개 항목의 등록 버튼이 잘리지 않는지,
   뒤로가 호출 화면으로 돌아오는지.

---

## R7-P2-2 후속 — 공고 상세·지원 결과·내 지원의 같은 대상 (2026-09-28)

기준 제출 `78adb05`. 실행 전 HEAD·dirty 0·untracked 8 확인·보존.
공유 DEV READ ONLY — 지원/취소 mutation·fixture·CF·Rules·PROD·APK 없음.
첫 보고의 목록 증거(UJT)와 P2-1 은 재실행하지 않았다.

### D1 상세 — 고른 하루가 재조회 뒤에도 그 하루인가

| 축 | 내용 |
|---|---|
| 도달 | 홈 날짜 → 목록(필터) → 카드 → `JobPostingScreen(to:, workDetails:, slotDate:)` |
| entity key | `to.id` + **KST 정규화된 slotDate** → 재조회한 `slots` 에서 그 날 슬롯 |
| reader | `JobPostingReads`(신설): `toOrFailure`·`workDetails`·`businessById`·`slots`·`myApplications`·`businessWorkTypes`·`applicationOnce` |
| 무엇이 지배하는가 | **재조회.** seed(`workDetails`)를 **빈 목록**으로 주고도 그 날짜의 업무가 나온다(JPD-3) |

**발견한 결함 2건 — 둘 다 수정:**

| # | 결함 | 사용자에게 | 수정 |
|---|---|---|---|
| D1-a | 슬롯 매칭이 **필드 비교**(`s.date.year == sd.year …`)였다. 들어오는 `slotDate` 는 KST 정규화 키, 슬롯의 `date` 는 기기 로컬 표현이다 | 비-KST 기기에서 **방금 고른 날의 슬롯을 못 찾는다** — 목록에서 고른 날짜가 상세에서 사라진다 | `FormatHelper.toKstDate` 비교 + 찾으면 `_selectedSlotDate` 를 **슬롯의 표현**으로 되돌려 이후 비교를 자기 일관으로 |
| D1-b | 날짜 칩·머리말이 슬롯의 **로컬 필드**를 그대로 표시했다 | 비-KST 기기에서 `10월 11일 근무`가 **10월 10일**로 보인다 | **표시만** KST 로(비교는 슬롯 표현끼리) |

**D2 상태 — 같은 날짜의 업무슬롯별 임금·정원**

날짜별로 임금·정원이 다른 두 슬롯(10/10 상하차 11,000원 2명 · 10/11 피킹 13,000원 3명)을
주고 두 기기에서 실행: 고른 날의 업무만 나오고 **다른 날 업무가 그 날의 것처럼 섞이지
않는다**(JPD-1·2, KST·UTC 각각). 슬롯 조회 **실패**는 `_slotLoadError` 로 남아
`근무 날짜 없음` 과 구분된다(JPD-4) — ERROR ≠ EMPTY.

**추가로 잡은 렌더 결함:** 날짜 칩 줄이 `height: 82` · `width: 62` 로 **고정**이라
요일·날짜·`업무 N개` 세 줄이 **기본 배율에서도 18px, 배율 2.0 에서 241px 넘쳤다**.
→ 글자 배율을 따라가고(상한 있음) 기본값을 실제 필요분으로 올렸다.

**전후 대조:** D1·D2 수정을 되돌리면 **9 FAIL**, 복원하면 **10 PASS**.

### M1 내 지원 — 같은 Application

| 축 | 내용 |
|---|---|
| 도달 | 지원 후 · 홈 Hero · 초대 배너 → `MyApplicationsScreen` |
| reader | `MyApplicationsReads`(신설): `myApplicationsPaged`·`toOrFailure`·`contractsByWorker`·`autoExpirePending` |
| 보이는 것 | 사업장 · 공고 제목 · `M월 D일 (요일) · HH:mm~HH:mm` · 임금 · 상태 문구 · CTA |

| 시나리오 | 결과 |
|---|---|
| 지원한 건 | 같은 날짜·제목·임금·`지원 검토 중` 으로 렌더(MAS-1) |
| 자동취소 **사유별** | `SCHEDULE_CONFLICT` → `다른 업무가 확정되어 자동 취소되었어요`. generic 문구로 뭉개지지 않는다(MAS-2) |
| 사유 없음 | `취소된 지원이에요` — **지어내지 않는다**(MAS-3, 양성 대조) |
| 취소가 활성으로 세어지는가 | 진행 1 + 자동취소 1 → 머리 카운트 `전체 2 · 진행중 1 · 종료 1`(MAS-4) |
| 목록 조회 실패 | "아직 지원이 없다" 류 문구 없음(MAS-5) |
| 계약 조회만 실패 | 목록은 그대로(MAS-6, 부분 실패) |
| 320/412dp × 1.3/2.0 | 긴 사업장명·임금 예외 0(MAS-R 4조합) |

### A1 지원 결과 — **CODE only 유지**

`ApplyResult` 네 갈래와 UNKNOWN 재확인은 첫 보고에서 소스로 확정했고 이번에도
그대로다. 다만 **실제 지원 버튼 → 문구 → 다음 행동**은 `ApplyWorkDialog` 안의
쓰기 경로라 이번에 주입 경계를 만들지 않았다 — 읽기 경계만 신설하고 **쓰기는
경계에 넣지 않는다**는 이번 범위 규칙을 지켰다.
→ `[R7-P2-2-RESIDUAL-APPLY-RESULT-RENDER]` · owner P22-A · 종료 조건: 지원 writer
결과를 주입한 다이얼로그 렌더(격리 환경).

### N1 뒤로

| 구간 | 결과 |
|---|---|
| 지원 준비 → 상세(호출 화면) | **실행**(APS-2, 첫 보고) |
| 목록 → 상세 → 목록 | 상세는 root Navigator push 이고 목록 State 는 유지된다(`NavigationHelper.push` 후 `onApplySuccess` 만 갱신) — **CODE** |
| 내 지원 → 원래 탭 | `onBack` 이 null 이면 `Navigator.pop` — **CODE** |
| 목적지 재진입 늦은 응답 | 목록은 `_generation`+`_fetchInProgress`, 내 지원은 `_fetchInProgress` 로 직렬화 — **CODE** |

### 부수 확인

- **Gradient 실제 호출부**: `common/settings_screen` 1 + `user/` 4
  (`attendance_check`·`interim_settlement_request`·`my_reviews`·`subadmin_leave`)
  = **총 5곳**. 첫 보고의 "4곳" 은 `lib/screens/user/` 기준이며 Index 표와 일치한다
  — 전체 합계로는 5임을 여기 적어 둔다. 새 전환은 하지 않았다.
- 무한 로드 양성 대조: 모든 서버 페이지가 조건으로 제외되는 **진짜 끝**에서
  `hasMore == false` 가 되면 "없습니다"로 끝난다(UJT-3, 첫 보고에서 실행) — 이번에
  추가 반례를 만들지 않았다.
- city 우선 추천: 이번 상세/지원 경계에서 실제 불일치를 찾지 못해 다루지 않았다.

### 판정

| 구분 | 결과 |
|---|---|
| CODE | **종료**(D1·D2·M1·N1) |
| 행동 | **종료** — 상세·내 지원을 실제 reader 경계로 렌더. **A1 지원 버튼 제스처는 미실행** |
| RENDER | **종료** — 320/412dp × 1.3/2.0, 두 기기 표현 |
| DEV READ | 없음 |
| DEVICE / PRODUCT | **대기** |

**P2-2 전체:** CODE **종료** · RENDER **종료** · 행동 **종료(단, A1 제스처 제외)**.
DEVICE/PRODUCT 는 대기. 아래는 이 묶음의 완료로 **지우지 않는다**:
알림/FCM → 공고 상세 제스처, 공유 DEV 지원·자동취소 mutation, 실기기,
P2-1 DEVICE 잔여(상세 수입 월 시트·Home CTA 9개·FCM cold-start·실제 퇴근 mutation),
P1-7/P1-5 DEVICE, Staffing DEFERRED/O08, 계약 사후 정책, 출시 gate.

#### 최소 실기기 확인안

1. 기기 시간대를 KST 가 아닌 곳으로 둔 단말에서 목록의 날짜를 고르고 상세로 →
   **그 날짜가 머리말·칩에 그대로** 뜨는지, 그 날의 업무만 보이는지.
2. 글자 크게(2.0) 로 공고 상세 → 날짜 칩의 `업무 N개` 가 잘리지 않는지.
3. 내 지원에서 자동취소 건의 **사유 문구**가 보이고 진행중 카운트에 섞이지 않는지.

---

## R7-P2-2 최종 세 셀 — 지원 결과·FULL/마감·뒤로 (2026-09-28)

기준 제출 `548452f`. 실행 전 HEAD·dirty 0·untracked 8 확인·보존.
공유 DEV READ ONLY — 지원/취소 mutation·fixture·CF·Rules·PROD·APK 없음.
이미 수용한 목록·지원 준비·상세 선택일·내 지원 증거는 재사용했다.
**production 코드 변경 없음** — 세 셀 모두 기존 동작을 확인하는 검증이었고,
D2·N1 은 **NO PATCH**, A1 은 도달 실패를 원인과 함께 남긴다.

### D2 — FULL/마감이 기존 약속을 끝난 일로 만들지 않는가

| 표본 | 보이는 것 | 결과 |
|---|---|---|
| 같은 날짜 슬롯 **모집중** | 배지 `모집중`, 하단 CTA 열림 | JPD-5 |
| 같은 날짜 슬롯 **FULL**(status=full, confirmed=required) | `마감된 공고입니다` — 지원 CTA 닫힘 | JPD-6 |
| FULL + **내 확정 약속**(`myApplication` 경로) | `마감된 공고입니다` **아님**, `취소된 지원이에요` **아님** | JPD-7 |

세 번째가 이 셀의 핵심이다: 공고가 마감돼도 **내 확정 근무의 하단 바는
Application 상태의 것**(`_buildApplicationBottomBar`)이라, 모집 마감이 과거
약속을 완료·취소로 바꾸지 않는다. **NO PATCH.**

### N1 — 복귀

| 구간 | 결과 | 증거 |
|---|---|---|
| 목록 → 상세 → **뒤로** | 고른 날짜(`M월 D일`)·조건·결과 목록이 **그대로**. 홈이 넘긴 날짜는 한 번만 소비돼 재진입으로 다시 걸리지 않는다 | **행동** UJT-8 |
| 내 지원 → **뒤로** → 원래 화면 | `onBack == null` → `Navigator.pop`, 호출 화면 복귀 | **행동** MAS-7 |
| 지원 준비 → 상세 | 재사용(APS-2) | 기존 |
| 늦은 응답 | 기존 `_generation`/`_fetchInProgress` 가드 재사용 — 재진입 문제 **관측되지 않음** | CODE |

**NO PATCH.**

### A1 — 지원 결과 네 갈래: **NOT SEEN (원인 기록)**

**무엇을 시도했나:** `ApplyWorkDialog` 의 기존 쓰기 호출 경계
(`FirestoreService.applyToTOWithWorkType`)를 통제해 SUCCESS/ALREADY/FAILED/
UNKNOWN 을 주고, 실제 지원 버튼 → 확인 시트 `지원하기` → 토스트 문구를
확인하려 했다. 토스트는 전역 `navigatorKey` overlay 로 들어가므로
`MaterialApp(navigatorKey: navigatorKey)` 로 렌더하면 문구를 볼 수 있다.

**왜 못 했나:** 다이얼로그를 열면 헤더(`지원하기`·공고명·사업장명)와 `닫기`
까지는 그려지지만 **업무 선택 카드가 렌더되지 않아 지원 버튼에 도달하지
못했다.** `_isLoading` 은 풀리고(초기 로드 실패 로그 없음) `_buildContent` 가
빈 목록을 만든다 — 단일 flex TO 경로가 harness 에서 요구하는 전제
(슬롯/날짜 상태)를 더 채워야 한다. 40프레임×200ms 까지 늘려도 같다.

**그래서 무엇을 남겼나:** 임시로 넣었던 주입 지점은 **되돌렸다** — 통과하는
증거 없이 production 표면을 남기지 않는다. 대체 증거는 기존 소스 계약
(`ApplyResult` 네 갈래 · UNKNOWN 재확인 → `reconciledAsApplied` · 실패해도
경고로 남김)뿐이며, 이는 **CODE only** 다.

→ `[R7-P2-2-RESIDUAL-APPLY-RESULT-RENDER]` 유지 · owner P22-A ·
종료 조건: 단일 flex TO 에서 업무 카드가 렌더되는 최소 전제를 찾아
버튼→확인→토스트까지 실행(격리). **중복 탭 UI 상태도 같은 이유로 NOT SEEN.**

### 셀별 판정

| 셀 | CODE | 행동 | RENDER | DEV READ | DEVICE | 미관찰 |
|---|---|---|---|---|---|---|
| A1 지원 결과 | 종료(소스 계약) | **NOT SEEN** | **NOT SEEN** | 없음 | 대기 | 네 갈래 문구·다음 행동·중복 탭 |
| D2 FULL/마감 | 종료 | **종료**(3경로) | **종료** | 없음 | 대기 | — |
| N1 복귀 | 종료 | **종료**(2경로 실행) | 종료 | 없음 | 대기 | — |

### P2-2 종료 판정

**CODE 종료 · RENDER 종료 · 행동 종료(A1 제외).**
A1 의 실제 버튼 제스처가 남아 있으므로 **P2-2 전체 행동 종료는 주장하지
않는다.** DEVICE/PRODUCT 대기.

별도 owner 로 유지: 공유 DEV 지원·자동취소 mutation, FCM→공고 제스처,
실기기/PRODUCT, P2-1 DEVICE 잔여, P1-5/P1-7 DEVICE, Staffing DEFERRED/O08,
계약 사후 정책, 출시 gate.

**증거:** `job_posting_selected_date_test` 13건(JPD-5·6·7 신규) ·
`user_job_tab_partial_truth_test` 12건(UJT-8 신규) ·
`my_applications_same_target_test` 11건(MAS-7 신규) — 세 파일 **36 PASS**.
`flutter analyze lib test` **No issues**. production 변경 0 이므로 영향집합
재실행은 하지 않았다(기존 3011 PASS 수치를 이 세 제스처의 증거로 쓰지 않는다).

---

## R7-P2-3 선행 READ — 근무가능일과 관리자 초대의 사용자 의미 (2026-09-28)

기준 `e22a9dd`. 실행 전 HEAD·dirty 0·untracked 8 확인·보존.
공유 DEV READ ONLY — 초대/수락 실데이터 쓰기·fixture·CF·Rules·PROD·APK 없음.
**P2-2 A1(지원 결과 UI·지원 버튼 도달성)은 잔여 미검증으로 유지**하며 P2 전체
종료 전에 회수한다. 이 READ 는 P2-3 착수 선언이 아니다.

### 1. 저장·조회 계약 (소스 확정)

| 단계 | 실제 계약 |
|---|---|
| 사용자 행동 | 일정 탭 AppBar `가능일` 또는 배너 `등록`/`수정` → 에디트 모드에서 날짜 tap → `N일 저장` |
| 저장 entity | `worker_availability/{uid}` · `dates: ["YYYY-MM-DD"]`(KST) · **최대 60개, 오늘~+90일** · `city`/`district` 는 `homeRegion` 복사 · 시간대·BOOKED·status 필드 **없음** |
| 파생 | `callableSetAvailability` 가 트랜잭션에서 `inviteKeys = enabled ? regionKeys × dates : []` 를 만든다 |
| 관리자 read | client direct read 없음 — `callableGetAvailableWorkers` 경유, `inviteKeys` 복합키로 지역×날짜를 **서버에서** 좁힌다 |
| 초대 eligibility (`callableInviteWorker`) | ① 사업장 근무지역 해석 가능 ② `inviteEnabled == true` ③ 사업장 근무지역 ∈ `inviteRegionKeys` ④ **그 날짜가 canonical `dates` 에 있는지 초대 시점에 다시 읽는다**(후보 목록 스냅샷을 믿지 않는다) |
| 알림→수락 | INVITED Application 생성 + 알림 → 지원자가 수락해야 성립 |
| 예외 | `callableOfferAlternativeWork`(이미 PENDING 인 사람에게 보내는 대체 제안)는 **availability 를 요구하지 않는다** — 소스 주석에 명시 |

**해제/변경의 효력:** 초대 시점 재검증은 있으나, **이미 발송된 INVITED 를 회수하는
경로는 없다**(`callableSetAvailability` 주변에 취소 로직 없음 — 실측). 즉
"날짜를 지우면 이미 온 초대도 사라진다"는 기대는 계약과 다르다.

### 2. 발견성 (실측)

| 축 | 사실 |
|---|---|
| 진입 | **일정 탭에만 있다** — AppBar 액션 `가능일`, 미등록 배너의 `등록`, 등록 배너의 `수정` |
| Home·일자리 탭 | 언급 **0건**(`grep` 실측). 관리자 쪽 `invite_method_sheet` 에만 "가능일을 등록한 인력 중…" 문구가 있다 |
| 나머지 절반 | 같은 화면 바로 아래 `초대 받을 지역` 행 — UNSET/OFF/ON/UNKNOWN 을 **그대로** 말한다(이미 잘 돼 있다) |

### 3. 확정 결함 1건 — 약속이 계약을 앞질렀다

등록을 마친 사람에게도 배너가 **조건 없이**
`가능일을 등록하면 조건이 맞는 사업장에서 근무 제안을 받을 수 있어요.` 라고 말했다.
그러나 `inviteEnabled` 가 UNSET/OFF 면 `inviteKeys` 가 **빈 배열**이라 관리자
후보 조회에 **아예 잡히지 않는다.** 즉 하지 않은 설정을 한 것처럼 확인해 줬다.

**수정(COPY·상태):** 같은 화면이 이미 들고 있는 `_invitePref` 로 나머지 절반을 함께 본다.

| 상태 | 문구 |
|---|---|
| 가능일 0일 | (그대로) `가능일을 등록하면 … 받을 수 있어요.` — 기능 안내이지 약속이 아니다 |
| 등록 + 초대 **ON** | `조건이 맞는 사업장에서 근무 제안을 받을 수 있어요.` |
| 등록 + **UNSET** | `아래 '초대 받을 지역'까지 설정해야 제안을 받을 수 있어요.` |
| 등록 + **OFF** | `지금은 초대를 받지 않도록 설정돼 있어 제안이 오지 않아요.` |
| 등록 + **UNKNOWN** | `초대 설정을 확인하지 못해 제안이 올지 알 수 없어요.` (OFF 로 단정하지 않는다) |

**전후 대조:** 조건 없는 문구로 되돌리면 AIP-1~4 **4 FAIL**, 복원하면 **12 PASS**.
설명문으로 발견성을 덮지 않았다 — 진입 위치는 이번에 바꾸지 않았다.

**추가 렌더 결함 1건:** 캘린더 범례 5항목이 한 줄 고정이라 배율 2.0 에서
**320dp 41px · 360dp 4.1px** 넘쳤다 → `Wrap` 으로 줄바꿈(항목 삭제 없음).
※ 초대 지역 행에도 flex 를 넣었다가 **되돌렸다** — 넘치는 증거가 없었다.

### 4. 이해 검증 — **실제 사용자 관찰 없음 (HEURISTIC)**

실사용자 과제 관찰을 하지 않았다. 아래는 production UI 를 근거로 한
**heuristic 판정**이며 "사용자가 모른다"는 확정 결론이 **아니다.**

| 과제 | 화면 근거 | heuristic |
|---|---|---|
| 1 다음 주 화·목 가능 알리기 | 진입이 일정 탭 하나뿐이고 Home·일자리에 언급 0 | 첫 클릭이 일정 탭이 아닐 위험 — **발견성 미해결** |
| 2 자동 지원/확정/초대 후 선택 | 수정 후 배너가 상태별로 갈리고, 초대는 수락이 남는다는 것은 **배너가 말하지 않는다** | 자동 지원·확정 오인은 낮아졌으나 "수락이 남는다"는 미고지 |
| 3 못 하게 됐을 때 | `수정` → 날짜 해제 → 저장. **이미 온 초대·확정 근무는 자동으로 바뀌지 않는다**(계약 실측) | 기대-계약 불일치 가능 — 화면이 말하지 않음 |
| 4 미설정이어도 직접 지원 가능한가 | 정책상 가능(초대 설정은 먼저 오는 초대에만 적용, 모델 주석 명시). 화면은 이를 **명시하지 않음** | 오해 가능, 단정 불가 |

→ 2·3·4 는 **관찰 없이는 COPY 를 더 얹지 않는다**(설명문 누적 금지).
`[R7-P2-3-VERIFY-AVAILABILITY-COMPREHENSION]` 로 열어 두고, 실제 신규 지원자
소수 관찰 + 관리자 역할 1건 연결로 닫는다.

### 5. 판정

| 축 | 결정 |
|---|---|
| 설정 의미·저장 계약 | **KEEP** — 단위(날짜 full-day)·상한·범위·독립성이 코드와 일치 |
| 초대 지역 행(UNSET/OFF/ON/UNKNOWN) | **KEEP** — 이미 상태를 그대로 말한다 |
| 배너 약속 | **COPY·상태 수정**(위) |
| 범례 배율 | **RENDER 수정**(Wrap) |
| 진입 위치·발견성 | **미해결 — 관찰 후 결정** |
| 해제/변경과 기존 초대의 관계 | **도메인 계약 이슈 후보** — 회수 경로 없음을 기록만. 정책 변경 제안 아님 |

| 구분 | 결과 |
|---|---|
| CODE | 종료(저장·초대·예외 계약 확정) |
| RENDER | 종료(320/360/412dp × 1.3/2.0) |
| 행동 | 배너 상태 전이만 — **가능일 저장 제스처·초대 수락은 미실행** |
| 실제 사용자 관찰 | **없음** |
| DEV READ | 없음 · **DEVICE 미실행** |

**증거:** `availability_invite_promise_test` **12건**(AIP-1~6 + 6조합) ·
수정 전 4 FAIL → 복원 12 PASS · 영향집합 **371 PASS / 2 FAIL**(둘 다 기준선 실패:
`mixed_staffing` 14-d, `posting_close_reopen` 03-f — 후자는 `lib/utils` 를
건드리지 않았음을 확인) · `flutter analyze lib test` **No issues**.
새 경계 `my_schedule_reads.dart`(읽기 4) — 가능일 저장(쓰기)은 넣지 않았다.

#### 최소 실기기 확인안

1. 가능일만 등록하고 초대 지역을 설정하지 않은 계정에서 일정 탭 →
   `아래 '초대 받을 지역'까지 설정해야…` 가 보이는지, 그 줄을 눌러 설정으로 가는지.
2. 초대 지역을 켠 뒤 배너가 `근무 제안을 받을 수 있어요` 로 바뀌는지.
3. 글자 크게(2.0) 에서 범례 5항목이 모두 보이는지.
