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
