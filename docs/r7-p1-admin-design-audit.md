# R7-P1 — 관리자 전체 디자인 감사 (READ)

- **감사 HEAD:** `01908f6`
- **작성:** 2026-09-27 KST
- **성격:** 전역 READ 감사. 전 화면 일괄 PATCH·새 navigation·도메인 정책 변경 없음.
- **기준:** 코드에 명시된 현행 ALfit 문법 —
  `AppPageScaffold`("ALfit flat screen foundation · **ADMIN flat header 표준** ·
  GradientScaffold 의 신규 ADMIN 화면 대안") ·
  `HOME-V2-08D.1` admin card 언어(grey50 배경 · surface 카드 · **radius 16** ·
  grey200 1px · **shadow 없음**) ·
  `AppModalShell`/`AppModalHeader`(flat white + grey200 divider + 3px brand accent) ·
  `AppColors` · `ResponsiveHelper` · `StyledDialog` · `DialogHelper`.
  새 디자인 체계를 만들지 않았다.

> ## ⚠️ 정정 (2026-09-27, 사용자 지적 반영)
>
> **이 문서의 첫 판은 기준을 거꾸로 잡았다.** 세 가지가 틀렸다.
>
> 1. **`GradientScaffold` 채택률을 "준수"로 셌다 — 반대다.**
>    그 파일은 스스로 *"지원자 화면 공통 레이아웃 / 파란 그라디언트 헤더 +
>    32px 곡선"* 이라고 적는다. 관리자 화면의 `GradientScaffold` 는
>    **구디자인(지원자 언어) 유입**이다. canonical 관리자 shell 은
>    **`AppPageScaffold`** 이고 **이미 25개 화면이 채택**했다. 저장소에
>    `[DESIGN-PATCH-1]~[DESIGN-PATCH-5] GradientScaffold → AppPageScaffold —
>    관리자 Shell 정규화 / flat admin 정렬` 마커로 **진행 중인 마이그레이션이
>    이미 존재한다.**
> 2. **radius 기준을 12 로 봤다 — admin 카드는 16 이다**(`HOME-V2-08D.1`,
>    공고 카드 `03S.1`). 12 는 아이콘 버튼·작은 요소다. 내가 근거로 쓴
>    프로젝트 메모리 기록(카드 12 · 그림자 alpha .04 blur 6 ·
>    "GradientScaffold 적용 확대")은 **2026-06 자, R7 리디자인 이전 값**이다.
> 3. **"홈이 글자 확대를 따르지 않는다" 는 틀렸다.** `fontSize: 14` 도
>    Flutter `textScaler` 가 적용된다. `ResponsiveHelper.getScale` 은 주석이
>    **"(폰트 제외)"** 이고 레이아웃 전용이다. 하드코딩 `fontSize` 의 실제
>    비용은 접근성이 아니라 **타이포 위계 불일치**이며, 별개로 홈의 `_s()` 가
>    `ResponsiveHelper.getScale` 의 **값이 다른 사본**(0.82/0.92/1.0/1.08 vs
>    0.85/0.9/1.0)인 것이 실제 문제다.
>
> 아래 §1·§2·§3-V3/V4·§5 는 정정된 기준으로 다시 쓴 것이다.
- **재현:** `node scripts/r7-p1-admin-design-audit.js` (SOURCE READ ONLY, 쓰기 0)

> **감사 완료 ≠ 수정 완료 ≠ DEVICE 검증 완료.** 이 문서는 첫째만 기록한다.

---

## 0. 커버리지 (동일 단위로 집계)

| 단위 | 수 |
|---|---|
| 관리자 도달 트리의 Dart 파일 | **87** |
| 그중 화면/다이얼로그 성격 surface | **68** |
| **SOURCE 검토** | **87 / 87** |
| **RENDER 검증** | **2** (`AppModalShell` + `AppModalHeader`, DEVICE.1G) |
| **DEVICE 검증** | **0** (이번 감사에서) |

수집 범위: `screens/business_admin/**`, `screens/super_admin/**`(ADMIN) +
`screens/common/**`, `screens/contract/**`, `widgets/admin/**`(SHARED).
지원자 전용 화면은 P2 소유로 두고, 공유 컴포넌트는 SHARED로 표시했다.

**정규화된 surface 단위이며 독립 화면 68개를 뜻하지 않는다.** 기존 R7-P0
인벤토리의 116은 같은 성격의 정규화 수치이며, 이 감사는 그것을 재시작하지 않았다.

**SOURCE 검토 수를 RENDER 검증 수로 바꾸지 않는다.** 아래 모든 판정의 증거
등급은 각 행에 명시했다.

---

## 1. 가장 큰 불일치 — 관리 탭이 홀로 구디자인이다

사용자 지적: **「리디자인하면서 MY 탭 파란색 디자인은 구디자인인데」 — 맞다.**

### 관리자 5탭의 shell

| 탭 | 화면 | shell | 문법 |
|---|---|---|---|
| 홈 | `business_admin_home_screen.dart` | 탭 body (AppBar 없음) | grey50 + surface/radius16 → **flat admin** |
| 공고 | `jobs_root_screen.dart` | 탭 body | flat |
| 근무 | `workforce_root_screen.dart` | 탭 body | flat |
| 급여 | `payroll/payroll_overview_screen.dart` | **`AppPageScaffold`** | **flat admin** (`[DESIGN-PATCH-1]` 완료) |
| **관리**(=관리자 MY) | `common/settings_screen.dart` | **`GradientScaffold`** | **파란 그라디언트 = 구디자인 / 지원자 언어** |

**관리 탭만 지원자용 파란 shell을 입고 있다.** 파란 그라디언트 헤더 + 상단
32px 곡선 + 흰 반투명 아이콘 버튼은 `gradient_scaffold.dart` 가 스스로
*"지원자 화면 공통 레이아웃"* 이라고 적은 것이다. 나머지 관리자 화면은
`AppPageScaffold`(AppBar elevation 0, white + 1px grey200 divider, 배경 grey100)
또는 동등한 flat 구성이다.

### 이미 진행 중인 마이그레이션 (내가 처음에 놓친 사실)

| 마커 | 화면 |
|---|---|
| `[DESIGN-PATCH-1]` | `payroll_overview_screen` · `payroll_worker_detail_screen` |
| `[DESIGN-PATCH-2]` | `admin_month_detail_screen` |
| `[DESIGN-PATCH-3]` | `admin_stats_screen` |
| `[DESIGN-PATCH-5]` | `business_detail_screen` |
| (동일 방향) | `member_management_screen` |

`AppPageScaffold` 채택 = **관리자 화면 25개.** 방향은 이미 정해져 있고
관리 탭이 남은 쪽이다.

### 남은 파란 구디자인 12곳

| scope | 화면 | 비고 |
|---|---|---|
| **SHARED** | **`common/settings_screen.dart`** (2583줄) | **관리자 관리(MY) 탭 — 사용자 지적 대상** |
| ADMIN | `super_admin/` 11개 (`all_users` · `all_businesses` · `badge_settings` · `help_faq_management` · `review_tags_settings` · `to_limit_settings` · `legal_terms_management` · `insurance_rate_settings` · `minimum_wage_settings` · `system_settings` · `business_approval_settings`) | SUPER_ADMIN 범위 |

**`settings_screen` 은 `screens/common/` 에 있지만 실제 진입은 전부 관리자다** —
`business_admin_shell`(탭4) · `business_admin_home_screen` ·
`work_applicants_dialog` · `day_applicants_dialog` · `create_to_screen` ·
`contract_sign_screen`. **USER 진입 경로가 없다**(USER 의 MY 는
`user/tabs/user_my_tab.dart`). 따라서 shell 교체에 역할 공유 제약이 없다.

- **severity:** **CORRECTION** (행동 불가·정보 왜곡은 아니다. 다만 관리자가
  가장 자주 여는 탭 하나가 다른 제품처럼 보인다)
- **수정 방향:** `settings_screen` 의 `GradientScaffold` → **`AppPageScaffold`**.
  이미 있는 `[DESIGN-PATCH-*]` 와 **같은 전환**이며 새 컴포넌트를 만들지 않는다.
  헤더의 홈·알림 버튼은 `AppPageScaffold.actions` 로 넘긴다(그 컴포넌트가
  그렇게 설계돼 있다). `headerContent`(프로필 영역)는 body 최상단 카드로 내린다.
- **owner:** **R7-P1-6**(관리/설정군) · super_admin 11개는 동일 root cause 로 묶되
  별도 배치

### `관리` 탭의 두 번째 이탈

`settings_screen.dart` 1553–1582 에 **`AppColors` 밖 하드코딩 색 7곳**
(`0xFFB45309` · `0xFFFFFBEB` · `0xFFF0FDF4` · `0xFFBBF7D0` · `0xFF16A34A` ·
`0xFF166534`) — amber/green 계열을 직접 적어 상태색 계약 밖에 있다.
→ **CORRECTION**, owner **R7-P1-6**, 증거 SOURCE.

### 홈의 실제 문제 (정정됨)

하드코딩 `fontSize` 36개는 **접근성 문제가 아니다**(textScaler 적용됨).
실제 문제는 두 가지다.
1. **타이포 위계 불일치** — `ResponsiveHelper.bodyStyle()` 등 공용 style 대신
   raw `TextStyle(fontSize:)` 를 쓰므로 다른 탭과 글자 크기 단계가 어긋난다.
2. **`_s()` 가 `ResponsiveHelper.getScale` 의 값 다른 사본** —
   `0.82/0.92/1.0/1.08` vs `0.85/0.9/1.0`. 같은 기기에서 홈과 다른 화면의
   여백이 다르게 계산된다.
→ **CORRECTION**, owner **R7-P1-4**, 증거 SOURCE.

---

## 2. 공용 컴포넌트 채택률 (68 surface 기준)

| 컴포넌트 | 채택 | 비고 |
|---|---|---|
| **`AppPageScaffold`** (canonical admin shell) | **25 화면** | 정착됨 — 이것이 기준이다 |
| `StyledDialog` / `DialogHelper` | **42/68** | 가장 정착됨 |
| `AppEmptyState` | 23/68 | |
| `AppModalShell` | 10/68 | 다이얼로그 shell |
| `AppSearchBar` | 5/68 | |
| `AppBatchActionBar` | 1/68 | |
| **`AppSummaryHeader`** | **0/68** | 추출했으나 **아무도 안 쓴다** |
| **`AppStatusCard`** | **0/68** | 추출했으나 **아무도 안 쓴다** |
| ~~`GradientScaffold`~~ | **12 (잔존)** | **구디자인 — 낮을수록 좋다.** 채택률 아님 |

`AppSummaryHeader`·`AppStatusCard` 는 D0 계획에 "추출 완료/예정"으로 적혀
있는데 실사용 0 이다. 요약 헤더와 좌측 인디케이터 카드가 **화면마다 인라인**
이라는 뜻이고, 이것이 밀도·여백 불일치의 구조적 원인이다.
→ **CORRECTION**, owner **P1-7**(교차 통합), 증거 SOURCE.

---

## 3. D0 계약 위반 목록 (증거 = SOURCE)

### V1. `AlertDialog` / `showModalBottomSheet` 직접 사용 — 12건

D0 은 `StyledDialog` / `DialogHelper.showSheet()` 를 **필수**로 규정한다.
직접 호출은 shape·`useSafeArea` 누락으로 하단 홈버튼 영역이 깨진다
(CLAUDE.md 의 명시 금지 항목).

| scope | 파일 | 위반 |
|---|---|---|
| ADMIN | `admin_review_list_screen.dart` | AlertDialog 1 |
| ADMIN | `contract_template_edit_screen.dart` | AlertDialog 1 |
| ADMIN | `dialogs/attendance_status_dialog.dart` | AlertDialog 1 |
| ADMIN | `dialogs/available_workers_bottom_sheet.dart` | AlertDialog 1 |
| ADMIN | `dialogs/invite_worker_dialog.dart` | AlertDialog 1 |
| ADMIN | `dialogs/wage_confirm_dialog.dart` | AlertDialog 1 |
| ADMIN | `work_type_detail_screen.dart` | AlertDialog 1 |
| ADMIN | `work_type_management_screen.dart` | AlertDialog 1 |
| ADMIN | `super_admin/all_users_screen.dart` | showModalBottomSheet 1 |
| SHARED | `common/job_posting_screen.dart` | showModalBottomSheet 1 |
| SHARED | `common/profile_edit_screen.dart` | AlertDialog 1 |
| SHARED | `common/splash_screen.dart` | AlertDialog 2 |

**severity:** CORRECTION (SafeArea 파손 시 CORRECTION→BLOCKER 승격 가능 — 기기 확인 필요)
**owner:** attendance/wage → P1-3·P1-5 · invite/available_workers → **P1-2** ·
work_type/template/review → P1-6 · common → P1-7

### V4. radius 계약 이탈

D0 상수는 카드 12 / 배지 20 / 버튼 10 / 검색바 10 이다. 실측에서
`2, 6, 7, 9, 14, 24` 가 섞여 나온다.

| 파일 | radii |
|---|---|
| `contract_template_list_screen.dart` | 2,4,8,10,12,14,16,**24** |
| `dialogs/attendance_status_dialog.dart` | 4,6,8,10,12,14,20,**24** |
| `business_admin_home_screen.dart` | 4,**9**,10,12,14,16,20 |
| `admin_stats_screen.dart` | **2**,4,**6**,10,12,**14** |
| `dialogs/day_applicants_dialog.dart` | **2**,4,**6**,8,10,12,16 |
| `admin_contract_management_screen.dart` | **6**,**7**,8,10,**14** |

**severity:** POLISH (의미·행동 무해) — 단 같은 화면 안에서 3종 이상 섞이면
카드 depth 가 불규칙해 보이므로 CORRECTION.
**owner:** 화면군별 (P1-2 ~ P1-6)

### V6. 업무 날짜에 `DateFormat` — KST 계약 확인 대상 11건

DEVICE.1F 에서 확인했듯 `DateFormat.format` 은 **DateTime 자신의 zone** 으로
찍으므로 KST 업무 날짜에 쓰면 기기에서 하루가 밀린다.

| 파일 | DateFormat | FormatHelper | 판정 |
|---|---|---|---|
| `dialogs/to_detail_dialogs.dart` | 2 | **0** | **확인 필요 — FormatHelper 미사용** |
| `dialogs/to_list_dialogs.dart` | 1 | **0** | **확인 필요** |
| `unclosed_action_queue_screen.dart` | 1 | **0** | **확인 필요** |
| `common/profile_edit_screen.dart` | 1 | **0** | 확인 필요 |
| `dialogs/resign_request_management_dialog.dart` | 3 | 2 | 혼재 |
| `dialogs/schedule_request_management_dialog.dart` | 2 | 1 | 혼재 |
| `dialogs/expiring_contracts_dialog.dart` | 1 | 2 | 혼재 |
| `dialogs/pending_approval_calendar_dialog.dart` | 1 | 4 | 혼재 |
| `dialogs/attendance_status_dialog.dart` | 1 | 16 | 혼재 |
| `to_management/widgets/to_publish_section.dart` | 1 | 1 | 혼재 |
| `widgets/admin/cards/admin_to_group_card.dart` | 1 | 13 | **초대 만료 INSTANT** — 별건 |

**severity:** 각 건이 **업무 날짜**를 찍는지 확인 후 결정. 업무 날짜면
**BLOCKER 계열**(DEVICE.1F 와 같은 root cause — 관리자가 읽는 계약 사실이 틀림).
INSTANT 표시면 CORRECTION.
`[CORRECTION-R7-SENT-INVITE-EXPIRY-DEVICE-TZ]` 는 이미 등록된 carry.
**owner:** 날짜 root cause 는 **P1-2 가 소유**(1F 와 동일 계열), 화면 배선은 각 군

### V5. `AppColors` 밖 색

| 파일 | `Color(0x..)` | `Colors.*` | `AppColors` |
|---|---|---|---|
| `common/document_management_screen.dart` | **10** | 0 | 72 |
| `common/settings_screen.dart` | **7** | 0 | 94 |
| `super_admin/all_businesses_screen.dart` | 0 | 4 | 24 |
| `common/notification_screen.dart` | 3 | 0 | 18 |
| `common/splash_screen.dart` | 1 | 0 | **0** |

**severity:** CORRECTION · **owner:** 화면군별

---

## 4. 현재 Staffing(P1-2) 구체 개선안

DEVICE.1G 에서 **보류**로 남긴 항목을 P1-2 소유로 되돌린다 — P1-7 은 교차
확인이고 모든 디자인 결정을 미루는 곳이 아니다.

### 4-1. 화면 범위 설명 (BLOCKER 계열 — 대상 혼동)

두 화면의 머리말이 같은 날짜만 말해 "1 공고" 와 "날짜 전체" 를 구분하지 못한다.

- **인력 현황(공고탭):** 현행 `사무업무 · 인력 현황` / `장기 9/9~10/23 · …`
  → **유지** (이미 대상이 하나로 좁혀져 있다)
- **일자별 현황(홈):** 현행 `인력 현황` / `2026-09-28`
  → **개선:** 부제에 모집단을 적는다 — `2026-09-28 (월) · 공고 2개 · 업무 2종`
  `전체` 라는 말은 쓰지 않는다(사업장 전체인지 필터 결과인지 모호).
  필터가 걸려 있으면 `필터 적용 · 공고 2개` 로 그 사실을 적는다.

`confirmed.length` 의 **무조건 전역 rename 금지**는 유효하나, **모집단 라벨과
범위 설명 개선은 금지가 아니다.** 상단 수치에 모집단을 붙인다:

| 현행 | 개선안 |
|---|---|
| `지원 0 · 확정 1 · 부족 2 · 필요 3명` | `이 업무 · 지원 0 · 확정 1명 · 부족 2 / 필요 3` |
| (홈) 같은 형태 | `이 날짜 · 지원 0 · 확정 1명 · 부족 4 / 필요 5` |

### 4-2. 카드 위계 (CORRECTION — D0 "얕은 카드")

현행: 공고 카드 → 회색 영역 → 업무 카드 → 사람 카드가 각각 배경+테두리를
가져 4중첩이다. 확정 카드는 `successBg@0.35` **전체 tint + 초록 테두리 +
초록 배지**가 겹친다.

D0 은 반복 강조 축소·행당 강한 강조 제한·완료 정보 낮은 강조를 규정한다.
**색 의미가 맞다는 것만으로 전체 tint 를 정상 판정하지 않는다.**

개선안 (의미 유지, 강조만 정리):
1. 확정 카드의 **전체 배경 tint 제거**, 좌측 인디케이터 4px(초록)만 남긴다 →
   `AppStatusCard` 계약과 일치하고 미사용 컴포넌트를 실제로 쓰게 된다.
2. 사람 카드는 테두리 **또는** 배경 하나만. 둘 다 쓰지 않는다.
3. 업무 구획은 배경 대신 상단 구분선 + 라벨로.
4. 완료 정보(`계약완료` 등)는 grey 유지(이미 적용됨).

### 4-3. 행당 배지 수 (CORRECTION)

한 행에 `노쇼 7회`(빨강) · `신분증 재요청 필요`(주황) · `계약서 작성 필요`(주황) ·
`주3회`(회색) · `계약 종료`(회색) 가 동시에 설 수 있다. 문제/할 일/기록이
같은 크기로 경쟁한다.

개선안: 3층으로 나눈다.
- **문제**(노쇼) — 빨강, 최대 1개, 이름 줄 옆
- **할 일**(계약서·신분증) — 주황, 액션 줄로 이동
- **기록**(주N회·계약 종료·계약완료) — 회색, 보조 줄

### 4-4. `4일 전` 라벨 (CORRECTION — 의미)

`appliedAt`(지원 시각)이며 DEVICE.1E 에서 7일 경과 시 `지원 MM/DD HH:mm` 로
라벨을 붙였다. **상대 표기(`4일 전`)에도 같은 이름을 붙인다** → `지원 4일 전`.
대비·접근성은 별개이며 **P4** 로 연결한다.

---

## 5. 우선순위 요약

### BLOCKER (필수 행동 불가 / 대상 혼동 / 정보 왜곡)
1. **V6 업무 날짜 `DateFormat`** — `to_detail_dialogs` · `to_list_dialogs` ·
   `unclosed_action_queue_screen` (FormatHelper 0). 1F 와 같은 root cause. → **P1-2**
2. **4-1 홈 일자별 범위 미표시** — 어느 모집단인지 화면에서 알 수 없다. → **P1-2**

### CORRECTION
3. **§1 관리 탭(`settings_screen`)이 파란 구디자인** — `GradientScaffold` →
   `AppPageScaffold`. 이미 `[DESIGN-PATCH-*]` 로 6화면 전환 완료, 25화면 채택.
   USER 진입 없음 → 제약 없음. **사용자가 직접 지적한 항목** → **P1-6**
4. super_admin 11화면 동일 전환 (3 과 같은 root cause, 별도 배치) → **P1-6**
5. 홈 타이포 위계(공용 style 미사용) + `_s()` 가 `ResponsiveHelper.getScale` 의
   값 다른 사본 → **P1-4**
6. V1 `AlertDialog`/`showModalBottomSheet` 12건 (SafeArea 위험) → 각 군
7. 4-2 카드 tint/테두리 4중첩 · 4-3 행당 배지 3종 경쟁 → **P1-2**
8. `AppSummaryHeader`/`AppStatusCard` 채택 0 → **P1-7**
9. V5 하드코딩 색 (`settings_screen` 7 · `document_management_screen` 10) → P1-6 / P1-7
10. 4-4 `지원 4일 전` 라벨 → **P1-2**

### POLISH / BACKLOG
11. V4 radius 이탈 (같은 화면 3종 이상은 CORRECTION) → 각 군
12. `splash_screen` `AppColors` 0 · 하드코딩 색 → P1-7

---

## 6. 미검증 / NOT SEEN (전체 안전을 선언하지 않는다)

- **RENDER 검증은 2 surface 뿐이다** (`AppModalShell`·`AppModalHeader`).
  DEVICE.1G 의 viewport 24조합은 **shell+header** 만 그렸고, **사람 카드·배지·
  액션 행의 overflow 안전성은 증명하지 않는다.** shell PASS ≠ 화면 PASS.
- Firebase 의존으로 전체 화면을 pump 하지 못한 surface: 위 68개 중 **66개**.
  필요한 test seam 은 §7 최소 후속안으로만 제출한다(이번 감사에서 architecture
  변경 없음).
- 대비·터치영역 수치, 실기기 safe area·키보드·회전 — **NOT SEEN** → **P4**
- 지원 플랫폼·회전 정책 — 저장소가 선언한 것은 `ResponsiveHelper` 폭 계층
  (`<360 / <400 / <600 / ≥600`, 주석의 실사용 폭 `360~412dp`) 뿐이다.
  **임의의 전 기기 지원을 선언하지 않는다.**

## 7. 최소 후속 test seam 제안 (구현하지 않음)

실제 콘텐츠 widget 을 Firebase 없이 그리려면, 사람 카드 한 행을
`ApplicationModel` + `UserModel` + 배지 상태만 받는 StatelessWidget 으로
분리하면 된다(DEVICE.1E.2A 의 `CapacitySummaryText` 와 같은 크기의 분리).
그 단위라면 긴 이름·다중 배지·큰 금액을 viewport × 배율 matrix 로 실제 렌더할
수 있다. **이번에는 제안만 남긴다.**
