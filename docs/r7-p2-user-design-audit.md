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
