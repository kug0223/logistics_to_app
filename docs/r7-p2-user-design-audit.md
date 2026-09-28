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
