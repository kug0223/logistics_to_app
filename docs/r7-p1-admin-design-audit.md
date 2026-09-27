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
| `dialogs/to_detail_dialogs.dart` | 2 | **0** | **DEAD → NO PATCH** (DEVICE.1H) — `TODetailDialogs` 가 어디서도 인스턴스화되지 않는다 |
| `dialogs/to_list_dialogs.dart` | 1 | **0** | **FIXED** (DEVICE.1H) — `to.date` DATE_ONLY → `toKstDateKey`+`weekday`. 증거 RENDER(DH-B) |
| `unclosed_action_queue_screen.dart` | 1 | **0** | **NO PATCH — 원래 정상** (DEVICE.1H.1 정정). `UnclosedQueueItem.workDate` 는 CF 의 `workDateStr`('YYYY-MM-DD')을 `DateTime(y,m,d)` 로 만든 값이라 **성분이 KST 달력일인 로컬 DateTime** 이다. `DateFormat.format` 과 성분 기반 `_daysAgo` 가 모든 TZ 에서 정확하다. DEVICE.1H 가 `toKstDate` 로 바꿨는데 그것은 KST 보다 동쪽 기기(UTC+13)에서 하루 밀리는 **없던 결함을 만드는 변경**이었고 되돌렸다. 증거 RENDER(DH-A1~A5, TZ 3종) |
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
1. ~~**V6 업무 날짜 `DateFormat`**~~ → **DEVICE.1H 에서 해소.**
   active 2건(`to_list_dialogs` · `unclosed_action_queue_screen`) 수정,
   dead 2건(`to_detail_dialogs`) NO PATCH. CODE CLOSED · RENDER 검증 완료.
2. ~~**4-1 홈 일자별 범위 미표시**~~ → **DEVICE.1H 에서 해소(CORRECTION 수준).**
   머리말에 `· 공고 N개 · 업무 M개`(canonical identity 기준, 완전 결과일 때만).
   실제 잘못된 대상 action 증거는 없어 BLOCKER 승격하지 않았다.

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

### DEVICE.1I 에서 넘기는 항목

**`[CORRECTION-R7-HOME-REQUIRED-VS-RECRUITABLE-SHORTAGE-COPY]` → owner P1-4**

`오늘 5명 필요 · 0명 확정` 옆에 `오늘 2명이 더 필요해요` 가 서는 것은
**정상이다.** 서버가 두 축을 다르게 센다(`functions/src/index.ts` per-wdId 루프):

```ts
// 종료된 단위는 채울 수 없으므로 부족이 아니다.
const shortage = wd.closed ? 0 : Math.max(0, wd.required - confirmed);
dayAcc[dayIdx].required += wd.required;   // 종료 포함, 전부
dayAcc[dayIdx].shortage += shortage;      // 종료 단위는 0
```

즉 `필요` = 전체 정원, `부족` = **모집 가능분**. 같은 계약을 일자별 인력 현황이
`DayStaffingRow.seedsGroup` 으로 쓴다. 문제는 두 줄이 같은 단어(`필요`/`더 필요`)를
써서 `5 − 0 = 5` 로 읽히는 것이고, **copy·grouping 으로 해결된다**(새 지표·정책
변경 불필요).

DEVICE.1I 에서 문구를 바꿔 봤으나 그 한 단어에 **Home contract 8건**이 걸려 있어
P1-2 의 좁은 경계를 넘는다 — **되돌리고 근거만 남겼다.** 코드에도 같은 주석이 있다.

---

## 5-1. DEVICE.1H 실행 결과 (P1-2 적용분)

> **DEVICE.1H.1 정정:** 날짜 4지점 중 **고칠 것은 1건**이었다.
> `to_list_dialogs`(instant) FIXED · `unclosed_action_queue`(로컬 성분) **NO PATCH
> — 원래 정상, 1H 의 변경을 되돌림** · `to_detail_dialogs` 2건 DEAD.
> 판정 기준은 **필드가 instant 인가 성분 값인가** 다. instant(Firestore
> Timestamp)면 KST helper 가 필요하고, 성분 값이면 성분을 그대로 읽는 것이 옳다.

| 항목 | CODE | RENDER | DEVICE |
|---|---|---|---|
| 날짜 `to_list_dialogs` (instant) | **CLOSED** | **DH-B** | 재촬영 대상 |
| 날짜 `unclosed_action_queue` (성분) | **NO PATCH** (1H 변경 revert) | **DH-A1~A5 · TZ 3종** | — |
| 날짜 dead 2건 | **NO PATCH** | — | — |
| 사람 행 표면 (`ApplicantRowSurface`) | **CLOSED** | **ARS-A/B 실행** | 재촬영 대상 |
| 지원시각 라벨 overflow | **CLOSED** (1H 가 키운 폭) | **ARS-B (320dp·배율 2.0)** | 재촬영 대상 |
| 홈 일자별 범위 문구 | **CLOSED** (1H 는 filter 이전 rows 를 셌다 → 1I 에서 본문 projection 으로 정정) | **DH-C 렌더 · SCOPE 11** | 재촬영 대상 |
| 일자별 하단 빈 공간 (`Expanded`→`Flexible`) | **CLOSED** (1I — 이 진입에는 1H 수정이 적용돼 있지 않았다) | WCP-C2 가 차이를 고정 | 재촬영 대상 |
| 지원·확정 단위 `건` (관계 건수) | **CLOSED** | — | 재촬영 대상 |
| 확정 카드 tint → 테두리 | **CLOSED** | — | 재촬영 대상 |
| `지원 N일 전` 라벨 | **CLOSED** | — | 재촬영 대상 |
| 실제 콘텐츠 matrix (viewport 4 × 배율 3 × 행수 3 + 키보드 + safe area) | — | **48 PASS** | — |

**DEVICE.1H.1 에서 해소:** 사람 행의 **표면**을 `ApplicantRowSurface` 로 떼어
production 두 화면이 쓰게 했고(`day`·`work`), 실제 렌더로 검증했다.
그 과정에서 **두 가지를 잡았다.**

1. **1H 의 렌더 matrix 가 실제로 폭을 제약하지 않았다.** `MediaQuery` 만
   덮으면 위젯이 *믿는* 크기만 바뀌고 캔버스는 기본 800x600 이다. 320dp 에서
   버튼이 오른쪽으로 밀려도 통과했다(`right=583 > 320` 으로 드러남).
   `tester.view.physicalSize` 로 실제 표면을 설정하도록 세 suite 를 모두 고쳤다.
2. 그 결과 **진짜 overflow 를 찾았다** — 이름 줄의 지원시각 칸이 맨 `Text` 라
   줄지 못해 320dp·배율 2.0 에서 Row 가 넘쳤다(36px). 1H 가 `지원 ` 접두를
   붙여 더 길어진 자리다. 두 화면 모두 `Flexible` + ellipsis 로 고쳤다 —
   글자를 줄이거나 라벨을 숨기지 않았다.

**여전히 미검증:** 권한 게이팅·capacity 계산·어떤 action 이 뜰지 결정하는 규칙은
여전히 Firebase 의존 State 안에 있다. 표면과 배지는 검증됐고, **그 PASS 를
카드 전체 로직 PASS 로 읽지 않는다.**

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

---

# R7-P1-3 — 관리자 오늘·근태 화면군 (2026-09-28)

기준 `574cccd`. branch `main`, tracked 변경 없음(패치 전), 사용자 소유 untracked 8건 보존.
Staffing O01~O06 개발 검증과 DEV 6함수 배포(VERIFIED)는 유지한다.
**기존 11TO/21 업무카운터 보정은 DEFERRED, Staffing O08 은 PENDING** — 이 절이 그것을
끝냈다고 적지 않는다. 알려진 DEV 불일치를 새 결함으로 다시 세지 않았다.

## P1-3.1 검토한 surface 와 도달 경로

| 화면/진입 | 대상(사업장·날짜·사람) | source | 계산 owner | loading/empty/error/권한 | action |
|---|---|---|---|---|---|
| **`AttendanceStatusDialog`** ("당일명단") ← 홈 `오늘 확인 필요` | `businessIds`(다중 시 선택 드롭다운) · `date` 1일 · 그날 확정 지원서 | `_getConfirmedWorkersForDate` + `_getAttendanceRecords` + `getUsersBatch(purposeWorkerDirectory)` + `getContractStatusBatch` + `getDayStaffingDetail`(모집단위 종료) | `AttendanceStatusHelper` · `AttendanceReviewHelper` · `WorkDetailTimeService` · `AttendanceRoundingHelper` | `_isLoading` / 성공 0건만 빈 상태 / `_loadError` 별도 / `canManageWorkers`·`canManageWage` | 출근·퇴근·시간정정·노쇼·노쇼해제·근태확인·확인취소·좌석반납(대체충원)·명단 PDF·급여확정 진입 |
| 같은 화면 ← **미처리 큐**(`unclosed_action_queue_screen`) | 그 큐 행의 `business × workDate` | 위와 같음 | 위와 같음 | 위와 같음 | 위와 같음 |
| 같은 화면 ← **근무 탭**(`workforce_operational_view`) ×2 (일괄 / 개인 focus) | `_selectedDay` · `initialApplicationId` | 위와 같음 | 위와 같음 | 위와 같음 | 위와 같음 |
| **미처리 큐 화면** ← 홈 | 사업장×근무일 미마감 목록 | `UnclosedActionQueueService`(CF) | 화면 내 `unclosedDaysAgo`/`formatUnclosedWorkDate` | 자체 | 근태 화면 열기 |

연결한 기존 계약(재검증하지 않음): 좌석·UNKNOWN·집계 fence·identity 는 Staffing(P1-2/O01~O05),
`ACTION_REQUIRED` 정의는 `admin_home_attendance_actionability_test`,
근무일 판정 parity 는 `unclosed_effective_start_parity_test`,
scoped refresh 는 `attendance_scoped_refresh_contract_test`,
오늘/어제 폴백은 `attendance_today_truth_contract_test`.
홈 요약·타이포는 P1-4, 급여 전체는 P1-5, 교차는 P1-7 유지.

## P1-3.2 고정 검토 목록과 판정

| # | 항목 | 판정 | 근거 |
|---|---|---|---|
| 1 | **화면이 쓰는 날짜의 계약** | **수정** | 아래 §P1-3.3 |
| 2 | **집계 단위(건수 vs 인원수)** | **수정** | 아래 §P1-3.4 |
| 3 | 조회 실패를 "근무자 0명"으로 말하지 않음 | 유지 | `_loadError` 분리 + 빈 상태 주석("성공했고 결과가 0명일 때만"), 실패 시 하단 바(명단 출력·급여)도 닫힘 — `[R5-ERROR-PARTIAL-R0 §16]`·`[R5-R0 §18]` |
| 4 | 모집단위 종료 여부 모름을 "종료됨"으로 바꾸지 않음 | 유지 | `closedByUnit` 실패 시 `null` 유지, 서버가 최종 권위 |
| 5 | 늦은 응답이 최신 화면을 덮지 않음 | 유지 | `_attRefreshSeq`(R8-P1C) |
| 6 | 중복 입력(연타) 방어 | 유지 | 모든 mutation 진입에 `if (_isLoading) return;` — 8곳 |
| 7 | 권한별 action 노출 ↔ 서버 재검증 | 유지 | `canManageWorkers`(조작 전체)·`canManageWage`(마감취소), CF 에서 권한 재검증 |
| 8 | 예정 근무 vs 실제 기록 구분 | 유지 | `WorkDetailHelper.effectiveStart`(예정) ↔ `attendance.checkInAt`(실제)를 분리해 읽고, 4탭(확인필요·정상·확인완료·처리완료)이 그 구분을 표현 |
| 9 | 한 사람이 여러 업무일 때 행 분리 | 유지 | 그룹 키 `businessId\|toId\|slotId\|wdId`, 행은 지원서 단위 — 근무 건마다 따로 출퇴근이 필요하므로 맞다 |
| 10 | RENDER(제약 폭) | **부분 검증** | §P1-3.5 — 에러 경로 360/320dp 통과, **행·액션 렌더는 미검증** |
| 11 | 근무 탭 자체의 day 창 | **기존 owner 이관(미수정)** | §P1-3.6 |
| 12 | radius 혼재(V4) | 미수정(POLISH 유지) | 이 파일 `4,6,8,10,12,14,20,24` — 의미·행동 무해. 근거 없는 일괄 변경을 하지 않았다 |
| 13 | 근태 → 급여 경계 | 경계만 확인 | 급여 확정은 `wage_confirm_dialog` 로 넘기고 이 화면은 근태 사실만 쓴다. 급여 전체는 P1-5 |
| 14 | scheduler 리컨펌 인덱스 부재 | 별건 유지 | 이 화면군과 직접 연결되지 않는다(해당 owner) |

## P1-3.3 [수정] 화면이 쓰는 날짜 — 호출부마다 다른 달력이었다

**사용자 영향.** KST 가 아닌 기기에서 이 화면을 **미처리 큐**나 **근무 탭**으로 열면
그 날짜가 아니라 **다른 KST 날짜**의 명단이 조회되고, 그 상태에서 누른 출근·퇴근·노쇼가
**다른 날짜의 근태 문서**로 기록될 수 있었다.

**root cause.** 이 화면은 받은 `date` 를 **instant** 로 쓴다 —
`FormatHelper.kstDayRange`(조회 창 3곳), `toKstDate`(비교 키), 그리고 서버로 보내는
`workDateMs`. 그런데 호출부가 넘기는 값이 두 종류였다.

| 호출부 | 넘기는 값 | 성격 |
|---|---|---|
| 홈 `_openTodayAttendanceDialog` | `FormatHelper.toKstDate(DateTime.now())` | `DateTime.utc(y,m,d)` — KST 달력일 ✔ |
| 미처리 큐 `_openAttendance` | `item.workDate` | **기기 local 자정** (그 화면 주석이 "instant 가 아니다"라고 직접 적어 두었다) |
| 근무 탭 ×2 | `_selectedDay` | **기기 local 자정**(`DateTime(y,m,d)`) |

`kstDayRange` 문서가 이 경우를 직접 경고한다: *"`DateTime(d.year, d.month, d.day)` 로 만든
기기 local 자정을 쓰면 KST가 아닌 기기에서 창이 통째로 어긋난다."*
서버는 한 걸음 더 간다 — `callableBatchSetNoShow` 가 `workDateMs` 를 KST 로 바꿔
**근태 문서 id**(`${applicationId}_${dateStr}`)를 만든다. 즉 표시가 아니라 **데이터**다.

**owner·수정.** 화면 하나로 모았다(호출부 4곳을 각각 고치면 5번째 호출부가 같은 실수를 한다).
들어온 값의 **달력 성분**을 KST 달력일로 못박아 한 번만 정규화하고, 그 뒤로는 그것만 쓴다.

- `_kstDay = DateTime.utc(widget.date.year, widget.date.month, widget.date.day)` 추가
- `widget.date` 37곳 → `_kstDay`
- 과거/미래 판정의 기준이던 **기기 local 오늘 자정** 3곳 → `_todayKst`(= `toKstDate(now)`)
- 시간 계산 helper 들은 모두 성분 기반(`DateTime(workDate.year, …)`)이라 **KST 기기에서의
  동작은 그대로다** — 바뀌는 것은 instant 가 의미를 갖는 지점뿐이다

**수정 전/후 실행 근거** — `test/attendance_dialog_day_key_contract_test.dart` 10건 통과:

| 사례 | 수치 |
|---|---|
| UTC+13 기기가 만든 `DateTime(2026,9,28)` | KST 로 **2026-09-27** (`toKstDateKey`) |
| 그 값의 조회 창 | 정상 창보다 **정확히 하루 이르다**. 관리자가 고른 9/28 의 KST 자정이 그 창의 **끝** — 그 날 근무가 빠진다 |
| 정규화 키 `DateTime.utc(2026,9,28)` | KST **2026-09-28**, 창도 그 하루 |
| KST·UTC−7 기기 | 기존 값도 같은 날을 고른다 → **회귀 범위: 한국 기기는 동작 불변** |
| 서버 문서 id 기준 | 같은 두 값이 `2026-09-27` / `2026-09-28` 로 갈린다 |

기존 계약 테스트 `attendance_business_date_contract_test` 의 앵커는 새 표현으로 다시 썼다
(`kstDayRange(widget.date)` → `kstDayRange(_kstDay)` + 정규화 지점 존재 + 원본 재사용 0).
**기준을 낮추지 않았다** — "기기 local 자정 금지"는 그대로 두고 조건을 하나 늘렸다.

## P1-3.4 [수정] 숫자가 무엇을 세는지 — "명"이 아니라 "건"이었다

**사용자 영향.** 한 사람이 같은 날 겹치지 않는 두 업무를 확정받을 수 있다(지원 게이트는
**겹치는** 확정만 막는다). 그때 `미출근 2명`은 실제로 **1명·2건**이다. 관리자가 인원을
잘못 읽고 대체 인력을 과하게 부른다.

**root cause.** 이 화면의 모든 집계가 `List<ApplicationModel>` 위에서 돈다
(`_calculateStats`, 탭별 목록, 선택 목록) — 단위는 근무 건인데 라벨이 전부 `명` 이었다.

**수정.** 업무 그룹을 **넘는** 수치 10곳을 `건` 으로 바꿨다(통계 셀·칩·미출근/지각/퇴근미기록·
선택 바·근태확인/취소 버튼·처리현황·확인완료). 이웃 화면의 canonical 과 같은 표기다
(`DayApplicantsDialog`: `지원 N건 · 확정 N건`).

**업무 그룹 헤더의 `명` 은 그대로 두었다** — 그룹 키가 `…|slotId|wdId` 까지 좁혀져 있고
지원서 docId 가 `{toId}_{slotId}_{wdId}_{uid}` 로 uid 당 유일하므로(CLAUDE.md complexId 계약)
그룹 안에서 한 사람은 한 번만 나온다. 즉 그 자리에서는 건수 = 인원수다.

증거: `test/attendance_count_unit_contract_test.dart` 4건 통과(U-3 은 UI 문구에 남은 `명` 이
그룹 헤더 하나임을 세고, U-4 는 그 예외의 근거인 그룹 키를 고정한다).

## P1-3.5 RENDER — 범위를 밝힌 부분 검증

`test/attendance_dialog_render_test.dart` 3건 통과. **production `AttendanceStatusDialog`** 를
`tester.view` 로 폭을 제약해 띄웠다(MediaQuery 만 바꾼 검사가 아니다).

| 확인한 것 | 결과 |
|---|---|
| 360×640 에서 예외·overflow 없음 | ✔ |
| 320×568(좁은 폭)에서도 없음 | ✔ |
| 실패를 "확정된 근무자가 없습니다"로 말하지 않음 | ✔ (그 문구가 나오지 않는다) |
| 명단을 모르는 상태에서 `명단 출력` 을 열지 않음 | ✔ |
| 머리말 날짜가 넘어온 값의 성분대로 찍힘(기기 local 자정 입력에서도 `09월 28일`) | ✔ |

**이 테스트가 그린 것은 조회 실패 경로다.** 이 화면은 읽기를 `FirestoreService()` 로 직접
하고 주입 경계가 없어서, 백엔드 없는 환경에서는 `_loadError` 상태가 된다.
**production 행·액션(탭 4종·그룹 카드·긴 이름/업무명·다중 배지·큰 글자) 렌더는 미검증이다.**
다음 조치는 8차의 `DayApplicantsReads` 와 같은 읽기 경계를 이 화면에도 두는 것이다
(읽기 5종: 확정자·근태·사용자·업무시간·계약상태 + 모집단위 종료). 그 작업은 이 절에서 하지 않았다.

대비·터치영역은 기존 P4 owner 기록을 연결만 한다 — **이번에 측정하지 않았고 PASS 로 쓰지 않는다.**

## P1-3.6 [이관] 근무 탭 자체의 day 창 — 같은 root cause, 이번에 고치지 않음

`workforce_operational_view` 는 자기 조회에도 같은 값을 쓴다.

| 지점 | 내용 |
|---|---|
| `_loadDayData(_selectedDay)` → `getConfirmedWorkersByDateAndBusinessOrThrow(date:)` | 그 안에서 `FormatHelper.kstDayRange(date)` — **기기 local 자정 입력** → 비KST 기기에서 하루 어긋난 명단 |
| `_today()` / `_selectDay` | `DateTime(y,m,d)` 로 만든다 |
| 마커 점 판정(`dates.contains(FormatHelper.toKstDate(day))`, 2곳) | 달력 위젯이 준 local 자정을 `toKstDate` 에 넣는다 → 비KST 기기에서 점이 다른 날에 찍힌다 |

다이얼로그 경계는 이번 정규화로 막혔다(그 화면이 무엇을 넘기든 KST 달력일로 해석한다).
남은 것은 **그 화면 자신의 조회·마커**다. 최소 조치는 같은 규칙 한 줄 —
`_selectedDay`/`_today()` 를 `DateTime.utc(y,m,d)` 기준으로 통일하고 마커 판정도 그 값을 쓰는 것.
그 화면은 P1-2(staffing) 소유이고 자체 회귀 묶음이 따로 있어, **승인 없이 건드리지 않았다.**
`UnclosedQueueItem.workDate` 는 그대로 둔다 — 그 화면의 표시 계약(성분 기반)은 정상이고,
경계 문제는 위 정규화로 해결됐다.

## P1-3.7 변경 파일 · 회귀

| 파일 | 변경 |
|---|---|
| `lib/screens/business_admin/dialogs/attendance_status_dialog.dart` | 날짜 정규화(`_kstDay`·`_todayKst`) + 단위 10곳 `명→건` |
| `test/attendance_dialog_day_key_contract_test.dart` | 신규 10건(A 실행 5 · B 소스 5) |
| `test/attendance_count_unit_contract_test.dart` | 신규 4건 |
| `test/attendance_dialog_render_test.dart` | 신규 3건(production 위젯·제약 폭) |
| `test/attendance_business_date_contract_test.dart` | 앵커 재작성(기준 유지 + 조건 추가) |

`flutter analyze` 대상 파일 No issues. 이 화면을 참조하는 테스트 **20파일 + 신규 3파일**을
같은 환경에서 돌려 이름 단위로 비교했다 — **새 실패 0**,
남은 2건은 9차에 기록한 기준선의 기존 실패(`noshow_replacement_cross_slice_contract`)다.

## P1-3.8 상태와 다음

| 구분 | 상태 |
|---|---|
| P1-3 CODE | **수정 2건 완료 · 유지 8건 · 이관 1건** |
| P1-3 RENDER | **부분** — 에러 경로/제약 폭 통과, 행·액션 렌더 미검증(읽기 경계 도입 후) |
| P1-3 DEVICE | **PENDING** — 아래 최소 확인안 |
| Staffing 보정(11TO/21건) | **DEFERRED**(사용자 결정) |
| Staffing O08 | **PENDING** |
| P1-4 / P1-5 / P1-6 / P1-7 / P2 | 각 owner 유지 — 이번에 시작하지 않았다 |

### 바뀐 화면에 한정한 최소 확인안 (기기)

이번 변경은 **한국 기기에서 동작이 같다**(회귀 범위 A-3). 그래서 기기 확인은 두 가지만이다.

1. 홈 `오늘 확인 필요` → 당일명단: 머리말 날짜가 오늘이고, 탭 숫자 라벨이 `건` 으로 보인다.
   업무 그룹 헤더만 `명` 이다.
2. 근무 탭에서 **과거 날짜** 하나를 골라 당일명단 열기: 머리말 날짜 = 고른 날짜,
   그 날의 명단이 뜬다(빈 날이면 "확정된 근무자가 없습니다", 조회 실패면 그 문구가 **아니라**
   실패 안내가 뜬다).

기존에 이미 확인한 같은 화면의 다른 항목은 다시 요청하지 않는다.

---

## R7-P1-3 후속 — P13-T / P13-W / P13-R (2026-09-28)

기준 `1edcac2`. branch `main`, 시작 시 tracked 변경 없음, 사용자 소유 untracked 8건 보존.
Staffing 보정 **DEFERRED**, O08 **PENDING** 유지. 첫 보고의 증거(날짜 실행 10건·집계 단위·
유지 8건·실패 경로 320/360 렌더·회귀 23파일)는 재사용하고 다시 만들지 않았다.

| ID | 이전→현재 | owner/변경 또는 NO PATCH | 재사용/신규 증거 | 남은 조건 |
|---|---|---|---|---|
| **P13-T** | 입력 계약 미확정 → **확정(+체인 1건 수정)** | 화면(`AttendanceStatusDialog`). `date` 는 **civil day** 계약임을 코드로 확정. `workDateMs` 를 KST 자정 instant 로 정정 | 재사용: 첫 보고 실행 10건 · 신규: `attendance_dialog_day_key_contract_test` 갱신(A 실행 5 · B 소스 5) | 없음 |
| **P13-W** | 이관(미수정) → **수정** | 근무 탭(`workforce_operational_view`) — 날짜 입력·조회창·마커 3지점. 경계 변환은 새 공용 owner `FormatHelper.kstDayKeyOfCivil` | 신규: `work_calendar_marker_contract_test` 재앵커 · 기존 marker/parity 회귀 유지 | 없음(그 화면의 집계·정원은 손대지 않았다) |
| **P13-R** | 오류 경로만 → **정상 명단 렌더 검증** | 화면에 좁은 읽기 경계 `AttendanceReads` 주입(8차 `DayApplicantsReads` 패턴) | 신규: `attendance_dialog_content_render_test` 4건(production 위젯·실제 행/그룹/액션) | 키보드 경로 없음 · 대비·터치영역은 P4 유지 |

### P13-T. 날짜 입력 계약 — 네 진입 모두 **civil day** 다

| 진입 / 실제 caller | 날짜 생성식 | civil 성분? | 고른 KST 날짜 | `_kstDay` 결과 | 조회창 / `workDateMs` 의미 |
|---|---|---|---|---|---|
| 홈 `_openTodayAttendanceDialog` | `FormatHelper.toKstDate(DateTime.now())` | **성분**(`DateTime.utc(y,m,d)`, 실제 시각을 KST 달력일로 바꾼 결과) | 오늘(KST) | 같은 y/m/d | `kstDayRange` → 그 날 KST 00:00~다음날 00:00 · `workDateMs` = 그 날 KST 자정 |
| 미처리 큐 `_openAttendance` | `item.workDate` = `DateTime(y,m,d)` ← CF `workDateStr('YYYY-MM-DD')` | **성분**(기기 local 자정, 그 화면 주석이 "instant 아님" 명시) | 큐 행의 근무일 | 같은 y/m/d | 같음 |
| 근무 탭 일괄 | `_selectedDay` = `DateTime(y,m,d)` (달력 선택 / `_today()`) | **성분** | 고른 날 | 같은 y/m/d | 같음 |
| 근무 탭 개인 focus | 같음 + `initialApplicationId` | **성분** | 같음 | 같음 | 같음 |

**실제 instant 를 넘기는 caller 는 없다.** 그래서 성분 추출(`kstDayKeyOfCivil`)이 네 경우 모두
맞는 변환이고, 범용 API 나 새 날짜 모델을 만들지 않았다. 두 변환을 코드에서 분리해 두었다.

- `_kstDay = FormatHelper.kstDayKeyOfCivil(widget.date)` — **성분 → 키**(달력에서 고른 날 보존)
- `_todayKst = FormatHelper.toKstDate(DateTime.now())` — **실제 시각 → KST 달력일**('오늘' 판정)
- 두 값은 같은 달력(UTC 성분 키)이라 `isBefore/isAfter` 비교가 성립한다. 선택 날짜와 오늘을
  섞지 않는다 — 과거/미래 판정에만 `_todayKst` 를 쓴다.
- 지적된 예시(`2026-09-27T15:00Z` 는 KST 9/28 인데 UTC 성분은 9/27)는 **instant 를 성분
  추출했을 때** 생기는 문제다. 이 화면에는 그 입력이 오지 않으므로 해당 사례가 없다 —
  그 전제를 주석과 테스트(B-1)로 못박았다. 새 caller 가 instant 를 넘기기 시작하면
  `kstDayKeyOfCivil` 의 문서가 그것이 틀린 입력임을 말한다.

**체인 1건 수정.** 선택값 → 정규화 → `kstDayRange` → `workDateMs` → 서버까지 따라가 보니
마지막 칸이 어긋나 있었다. 서버는 `workDateMs` 로 두 가지를 정한다:

- 근태 문서 id `${applicationId}_${KST(workDateMs) 날짜}` — **날짜는 두 형태 모두 같다**
- 저장되는 `attendance.workDate` = `Timestamp.fromDate(new Date(workDateMs))`
  — 이 프로젝트의 **DATE_ONLY canonical 은 KST 자정 instant** 다(`kstDayRange` 문서)

`_kstDay.millisecondsSinceEpoch`(= 00:00Z, KST 09:00)를 보내면 날짜는 맞아도 저장 형태가
canonical 을 벗어난다. **이건 첫 보고 이전부터 홈 경로가 그랬다**(홈은 처음부터
`toKstDate` 값을 넘겼다). 그래서 `_kstDayStartMs = kstDayRange(_kstDay).$1.millisecondsSinceEpoch`
로 바꿨다 — 조회창·저장값·문서 id 가 **한 하루**에서 나온다.
`attendance.workDate` 를 정확 instant 로 비교하는 소비자는 없음을 확인했다(전수 grep).

### P13-W. 근무 탭 — 날짜창·마커를 선택일과 맞췄다

| 지점 | 이전 | 현재 |
|---|---|---|
| `_loadDayData` → `getConfirmedWorkersByDateAndBusinessOrThrow` / `getAttendanceByDate` | `_selectedDay`(기기 local 자정)를 `kstDayRange` 에 넣었다 | 경계에서 `dayKey = kstDayKeyOfCivil(day)` 로 바꿔 넘긴다 |
| 주간 strip 판정 `_hasWorkOn` | `dates.contains(toKstDate(day))` — civil 을 instant 변환에 넣었다 | `dates.contains(kstDayKeyOfCivil(day))` |
| 월 달력 `eventLoader` | 같음 | 같음 |
| 마커 범위 `_loadMarkerRange` 의 `start`/`end` | 달력 연산 결과(local)를 그대로 | 양 끝을 `kstDayKeyOfCivil` 로 |
| `_today()` · `_selectDay` · `_isFuture` | civil 끼리 비교 | **그대로**(의미가 일관돼 결함이 아니다 — 기계적으로 바꾸지 않았다) |
| `anchor`(캐시 키) | local | **그대로**(내부 비교 전용) |

마커 집합의 원소는 `FormatHelper.toKstDate(app.workDate)`(= `DateTime.utc(y,m,d)`)이므로
이제 판정 키와 집합 키가 같은 형태다. 명단 진입은 `_selectedDay` 를 그대로 넘기고
다이얼로그가 같은 규칙으로 정규화하므로 **머리말·요청 날짜가 선택일과 같다**(ACR/ADR 증거).

**공통화와 제거.** 성분→키 변환을 `FormatHelper.kstDayKeyOfCivil` 하나로 두고,
다이얼로그의 인라인 `DateTime.utc(widget.date...)` 도 그 owner 로 위임했다(옛 계산 제거).
`UnclosedQueueItem.workDate` 는 그대로 — 그 화면의 표시 계약(성분 기반)은 정상이고
경계 문제는 다이얼로그 정규화로 해결됐다.

### P13-R. 정상 명단·행·액션 렌더

`AttendanceReads`(신규, `lib/screens/business_admin/dialogs/attendance_reads.dart`) —
**원시 외부 호출 9개만** 주입한다. 파싱·병합·중복 제거·상태 계산·탭 분류·업무 그룹·수치는
production State 에 그대로 남겼다(경계를 파싱 이전에서 끊었다).

| 이전한 caller | 이전 위치 → 현재 |
|---|---|
| 확정 근무자(단기·장기) | `fetchApplicationsByBizPaged(...)` ×2 → `_reads.applicationsPaged` |
| 업무유형 | `FirebaseFirestore.instance…workTypes.get()` → `_reads.workTypeDocs` |
| 근태 기록 | `httpsCallable('callableGetAdminAttendances')` → `_reads.adminAttendances` |
| 업무시간 | `WorkDetailTimeService.load` → `_reads.workDetailTimes` |
| 사용자 | `getUsersBatch(purposeWorkerDirectory)` → `_reads.usersBatch` |
| 계약 상태 | `ContractService().getContractStatusBatch` → `_reads.contractStatus` |
| 모집단위 종료 | `getDayStaffingDetail` → `_reads.dayStaffing` |
| 반올림 정책 | `getBusinessById` → `_reads.businessById` |
| 사업장 이름 | `getBusinessNames` → `_reads.businessNames` |

제거: 위 호출로만 쓰던 import 3개(`cloud_firestore` · `contract_service` ·
`work_detail_time_service`). 화면에는 우회 경로가 남지 않았다(`grep` 0건).

**실행 결과** — `attendance_dialog_content_render_test` 4건 통과. fixture 는 대표 혼합:
같은 사람이 **다른 업무 2건**(`workDetailId` 다름) + 미출근/지각 출근/퇴근 3행 + 긴 업무명·긴 이름.

| 사례 | 확인한 것 |
|---|---|
| ACR-1 390×780 | 머리말 `당일명단`·`09월 28일 (월)` · 상단 통계가 **건**(`3건`·`2건`·`1건`·`0/3건`) · 조회 0건 문구 아님 · `명단 출력` 열림 |
| ACR-2 | 기본 탭 `확인필요`(0건)의 빈 문구는 **조회 0건과 다른 말**(`해당 근무자가 없습니다`) · `정상` 탭 탭하면 실제 행(긴 이름 포함) · 첫 업무 그룹 `출근 2/2` · 스크롤 후 두 번째 업무 그룹(`주방 보조`) — 같은 사람이 두 그룹에 나뉜다 |
| ACR-3 320×640 · 글자배율 **1.3** | 예외 0 · 행 그려짐 · 드래그로 아래 행 접근 |
| ACR-4 | 실패 시 `명단 출력` 닫힘 + `다시 시도` → 탭 → **정상 목록** + `명단 출력` 열림 |

글자 축소나 배율 무효화로 덮지 않았다. 키보드 입력 경로는 이 화면에 없어 확인하지 않았다.

**렌더에서 찾은 결함 1건 — 공용 컴포넌트.** 320dp·배율 1.3 에서 `AppTabLabel` 의 Row 가
**4.9px 넘쳤다**(탭 3개 동시, `RenderFlex overflowed` 실측). 배지는 이미 `Flexible`+`FittedBox`
였지만 **라벨 `Text` 가 고정**이었다. 프로젝트 규칙(Row 안 두 위젯 이상 → `Flexible`)대로
라벨을 `Flexible`+`ellipsis` 로 바꿨다 — 숫자 배지는 그대로 보여 눌러야 할 것이 가려지지 않는다.
수정 후 같은 조건에서 예외 0.

### 첫 보고의 잘못된 근거 1건 — 정정

첫 보고에 "그룹 키가 `businessId|toId|slotId|**wdId**`" 라고 적었다. 실제 코드는
`wdSeg = app.workDetailId ?? ''` 다 — **`workDetailId`** 이고 `wdId` 가 아니다(1676행).
그룹 헤더 `명` 의 근거는 여전히 성립한다(docId discriminator 가 `workDetailId ?? selectedWorkType`
이라 같은 그룹에서 한 uid 가 두 번 나오면 docId 가 충돌한다). 다만 **남는 예외**가 있다:
`workDetailId` 가 없는 legacy 문서는 `wdSeg` 가 빈 문자열이 되어 같은 슬롯의 다른 업무가
한 그룹으로 합쳐지고, 그때 한 사람이 두 번 나올 수 있다. 드물고(구 문서 한정) 행 자체는
정상이므로 표기를 바꾸지 않고 **한계로 적는다**(`attendance_count_unit_contract_test` U-4 주석).

### ALfit 디자인 판정 (D0 기준)

| 항목 | 판정 | 근거 |
|---|---|---|
| 제목·날짜·사업장/필터 맥락 | 유지 | `AppModalHeader(당일명단 / MM월 dd일 (E))` + 다중 사업장일 때만 선택 필드 — 대상이 하나면 늘리지 않는다 |
| 상태색·정보 위계 | 유지 | 4탭(확인필요→정상→확인완료→처리완료) + 상단 통계 + 상태 배지. `urgent` 배지는 확인필요에만 |
| 사람 identity·배지 | 유지 | 이름 + 시간 + 상태 배지(지각/연장 등), 행은 근무 건 단위 |
| 주요 행동·정정 대상 | 유지 | 하단 고정 바(명단 출력·급여관리) + 행별 출근/조정/퇴근/리셋. 명단을 모르면 하단 바를 열지 않는다 |
| 카드 밀도·공백 | 유지 | 업무 그룹 카드(radius 14) — V4 의 radius 혼재는 POLISH 로 유지(근거 없는 일괄 변경 금지) |
| empty / error | 유지 | 조회 0건(`확정된 근무자가 없습니다`) ↔ 탭 0건(`해당 근무자가 없습니다`) ↔ 실패(`명단을 확인하지 못했습니다`) **세 문구가 갈라져 있다** |
| **공용 탭 라벨** | **수정** | 위 overflow |

### 회귀

같은 환경·이름 단위. 영향면 **45파일**(화면·경계·`app_tab_label`·`format_helper`·근무 탭 참조).
`+1564 -3` — **새 실패 0**, 남은 3건은 9차 기준선의 기존 실패
(`noshow_replacement_cross_slice_contract` ×2 · `mixed_staffing_parity` ×1).
`flutter analyze` 변경 5파일 No issues.

seam 이전으로 앵커가 옮겨간 **기존 계약 5건을 재작성**했다(기준을 낮추지 않았다):

| 테스트 | 무엇을 다시 앵커했나 |
|---|---|
| `attendance_business_date_contract_test` | 창 입력이 `_kstDay` 이고 원본 재사용 0 + 정규화 지점 존재 |
| `attendance_scoped_refresh_contract_test` | 재조회가 `_reads.adminAttendances` 를 쓰고, **그 CF 이름은 경계 파일에** 있다 |
| `admin_home_attendance_effective_time_test` | 화면+경계를 합쳐 시간 source 계약 확인 |
| `transfer_export_truth_contract_test` | `viaReads` 를 map 으로 — 화면이 `_reads.usersBatch` 를 쓰고, 목적은 화면이나 경계 중 한쪽에 있어야 한다 |
| `work_calendar_marker_contract_test` | 두 표면이 `kstDayKeyOfCivil` 을 **2회** 쓰고 `toKstDate(day)` 는 **0회** |

### 상태와 다음

| 구분 | 상태 |
|---|---|
| P13-T | **CLOSED** — 계약 확정 + 체인 1건 수정 |
| P13-W | **CLOSED** — 날짜창·마커·명단 진입이 같은 선택일 |
| P13-R | **CLOSED** — 정상 명단/행/액션 렌더 + D0 위반 1건 수정 |
| P1-3 CODE | 수정 누적 5건(날짜 정규화 · 단위 · workDateMs · 근무 탭 경계 · AppTabLabel) |
| P1-3 RENDER | **정상 콘텐츠 포함** (오류 경로 + 정상 명단, 320/390dp, 배율 1.3) |
| P1-3 DEVICE | **PENDING** — 아래 최소안 |
| Staffing 보정 / O08 | **DEFERRED / PENDING** (사용자 결정 유지) |
| P1-4·5·6·7·P2 | 각 owner 유지 — 시작하지 않았다 |

#### 바뀐 화면에 한정한 최소 DEVICE 확인안

한국 기기에서는 날짜 동작이 **불변**이다(회귀 범위 A-3). 그래서 세 가지만이다.

1. 근무 탭에서 **과거 날짜** 하나 선택 → 그 날 명단이 뜨고, 달력/주간 strip 의 점이 그 날에 있다.
2. 그 상태에서 당일명단 열기 → 머리말 날짜 = 고른 날짜, 탭 숫자는 `건`, 업무 그룹 헤더만 `명`.
3. 좁은 기기(또는 글자 크게) 에서 탭 라벨이 잘려도 **숫자 배지가 보이고 탭이 눌린다**.

첫 보고에서 이미 확인한 항목은 다시 요청하지 않는다.

---

## R7-P1-3 — 그룹 집계 단위 마무리 및 개발 종료 (2026-09-28)

기준 `1bad2ce`. branch `main`, 시작 시 tracked 변경 없음, 사용자 소유 untracked 8건 보존.
P13-T · P13-W · AttendanceReads 정상 콘텐츠 렌더 · AppTabLabel overflow 는 재조사하지 않았다.
Staffing 보정 **DEFERRED**, Staffing O08 **PENDING** 유지.

| P13-R 잔여 | 수정 owner·문구 | 관계 보존 증거 | 영향 회귀 | CODE / RENDER / DEVICE |
|---|---|---|---|---|
| 그룹·일괄 수치가 `명` | `_showBatchByGroupDialog`(같은 화면) — `$totalCount명 선택` → **`건 선택`**, 파트 배지 `${workers.length}명` → **`건`**, 주석 `파트명 + 인원` → `파트명 + 근무 건수` | `attendance_dialog_content_render_test` **ACR-5**(구 문서 형태, production 경로) | 좁은 회귀 21파일 `+662 -2` — **새 실패 0**(남은 2건은 9차 기준선) | CODE **CLOSED** / RENDER **CLOSED** / DEVICE **PENDING** |

### 왜 `명` 이 틀렸는가 — 최종 계약

그룹 키는 `businessId|toId|slotId|workDetailId` 이고 조각은 **`workDetailId`** 다
(`wdSeg = app.workDetailId ?? ''`). `workDetailId` 가 **없는** 구 문서는 `wdSeg` 가 빈
문자열이 되어 **같은 슬롯의 서로 다른 업무가 한 그룹으로 합쳐진다.** 그때 한 사람의
두 관계가 한 그룹 안에 함께 들어온다 — 지원서 docId 의 discriminator 는
`workDetailId ?? selectedWorkType` 이라 서로 충돌하지 않기 때문이다.

**그래서 "그룹 안에서는 건수=인원수" 라는 이전 근거는 성립하지 않는다.**
첫 보고와 후속 보고의 "그룹 헤더 `명` 의 근거는 유지된다" 문장을 이 문단으로 **정정한다.**
이 화면의 최종 계약은 하나다: **행/관계 길이를 보여주는 모든 자리는 `건` 으로 말한다.**

고유 인원을 표시해야 한다는 기존 요구는 없다. 이 화면의 action 단위(출근·퇴근·시간정정·
노쇼)가 근무 건이므로 **별도 unique uid 지표를 만들지 않았다** — 라벨 정정으로 충분하다.

### 수정 범위

| 대상 | 이전 | 현재 | 근거 |
|---|---|---|---|
| 파트별 일괄 처리 머리말 | `$totalCount명 선택 · N개 파트` | `$totalCount건 선택 · N개 파트` | `totalCount = groups.values.fold(0, (s, l) => s + l.length)` — 관계 수의 합 |
| 파트 배지 | `${workers.length}명` | `${workers.length}건` | 그 파트의 행(관계) 수 |
| 주 목록 그룹 헤더 | `출근 $checkedInCount/${workers.length - noShowCount}` | **그대로** | 분자·분모가 **둘 다 그 그룹의 행**이고 단위어가 없다 — 같은 단위임을 테스트로 고정(U-6) |
| 상단 통계·탭·처리현황 | 이미 `건`(첫 보고) | 그대로 | 상단과 그룹이 같은 뜻으로 읽힌다 |

하지 않은 것: 정원·좌석·노쇼·출퇴근·급여·권한·action gate 계산 변경 0 ·
행/관계 삭제·병합 0 · 무관한 실제 인원 `명` 전역 치환 0 ·
공유 DEV 문서 보정/ID backfill 0 · 없는 identity 생성 0.

### 검증 — 한 대표 사례, 기존 production 경로

`AttendanceReads` 주입 + production `AttendanceStatusDialog`.
fixture 는 **`workDetailId` 가 없는 구 문서 형태**로 같은 uid 의 관계 2건
(`홀서빙 09:00~13:00` · `주방 보조 14:00~18:00`, 같은 슬롯).
테스트 전용 그룹 계산은 만들지 않았다 — 그룹은 화면의 `_buildWorkTypeGroups` 가 만든다.

실제 렌더 결과(ACR-5):

| 확인 | 결과 |
|---|---|
| 두 관계가 **한 그룹**에 들어오는가 | ✔ 그룹 헤더 1개(`홀서빙 · 09:00 ~ 13:00`) 아래 행 2개 |
| 헤더가 관계 2건을 건으로 말하는가 | ✔ 상단 `2건`·`0/2건`, 그룹 `출근 0/2` |
| 분자/분모가 같은 단위인가 | ✔ 둘 다 그 그룹의 행 수(0/2) |
| 두 관계의 행이 보존되는가 | ✔ 같은 이름 행이 **2개**(id `L1`·`L2`) — 지우거나 합치지 않았다 |
| 상태 분류·action 대상이 바뀌었는가 | ✖ 그대로 — 둘 다 `미출근`, `정상` 탭, 하단 액션(출근/시간 조정/퇴근/리셋) 동일 |

기존 정상 문서·작은 화면 렌더 증거(ACR-1~4)는 그대로 재사용했다.

### 남은 한계 — 이번 범위 밖(기록)

구 문서가 합쳐진 그룹에서는 **행 두 개가 화면상 구분되지 않는다**
(둘 다 `한사람두관계 · 미출근`; 미출근 행에는 시간이 표시되지 않는다). 헤더도 그 그룹
**첫 관계**의 업무명·시간만 쓴다(`홀서빙 · 09:00~13:00`) — 두 번째 업무명은 헤더에 없다.

숫자 단위는 이번에 맞췄고 **데이터는 보존된다**(행 2개·서로 다른 id). 행에 업무명·시간을
더 보여주거나 그룹을 나누는 것은 **행 내용/그룹 규칙 변경**이라 이번 최소 수정 범위를
넘는다. owner 는 이 화면(P1-3), 영향은 `workDetailId` 가 없는 구 문서에 한정된다.
`workDetailId` 가 있는 문서는 업무별로 그룹이 갈리므로 해당하지 않는다.

### 보고 정정 2건

1. **"그룹 헤더 `명` 의 근거 유지"** → 위 최종 계약으로 정정(근거 불성립, 전부 `건`).
2. **"한국 기기 동작 불변"** → **표시되는 선택일 유지에 한정**한다.
   `workDateMs` / `attendance.workDate` 의 **저장 표현은 바뀌었다** —
   이전에는 진입 경로에 따라 KST 자정 instant(근무 탭·미처리 큐, 한국 기기) 또는
   `00:00Z`(홈)였고, 지금은 **항상 KST 자정 instant** 다(DATE_ONLY canonical).
   그 저장은 앞으로 실제 출퇴근·노쇼 처리에서 일어난다 — 이번에 공유 DEV 에 쓴 것은 없다.

### P1-3 개발/렌더 종료 자료 (검증된 범위)

| 항목 | 상태 | 증거 |
|---|---|---|
| 날짜 입력 계약(진입 4곳 civil day) + 체인(조회창→`workDateMs`→저장·문서 id) | CLOSED | `attendance_dialog_day_key_contract_test` 10건(실행 5·소스 5) |
| 근무 탭 날짜창·마커·명단 진입이 같은 선택일 | CLOSED | `work_calendar_marker_contract_test` 재앵커 · 기존 parity 회귀 |
| 집계 단위(상단·탭·처리현황·그룹·일괄) 전부 `건` | CLOSED | `attendance_count_unit_contract_test` 6건 + ACR-1·5 렌더 |
| 정상 명단·행·그룹·액션 렌더(정상/구 문서) | CLOSED | `attendance_dialog_content_render_test` 5건 |
| 좁은 폭·큰 글자 overflow | CLOSED | ACR-3 + `AppTabLabel` 수정 |
| 조회 실패·탭 0건·조회 0건 세 문구 구분 | CLOSED | ACR-2·4 · 기존 `[R5-ERROR-PARTIAL-R0 §16]` |
| 늦은 응답·연타·권한 게이트 | 유지(기존 증거) | `_attRefreshSeq` · `if (_isLoading) return` ×8 · `canManageWorkers`/`canManageWage` + CF 재검증 |
| 키보드 입력 경로 | **없음**(확인 대상 아님) | — |
| 대비·터치영역 수치 | **P4 owner 유지 · 이번에 미측정** | PASS 로 쓰지 않는다 |
| 구 문서 병합 그룹의 행 구분·헤더 업무명 | **한계 기록**(미수정) | 위 문단 |
| radius 혼재(V4) | POLISH 유지(미수정) | 근거 없는 일괄 변경 금지 |

**P1-3 CODE / RENDER 는 위 범위에서 종료.** DEVICE 는 별도로 남긴다 —
기기에서 실행하지 않은 것을 실행 완료로 바꾸지 않는다.

#### 최소 DEVICE 확인안 (최종 단위 반영)

1. 근무 탭에서 **과거 날짜** 선택 → 주간 strip·월 달력의 점이 그 날에 있고, 그 날 명단이 뜬다.
2. 당일명단 머리말 날짜 = 고른 날짜. 상단 통계·탭·처리현황이 **`건`**,
   파트별 일괄 처리 화면의 `N건 선택`·파트 배지도 **`건`**. 그룹 헤더는 `출근 n/m`.
   (화면 어디에도 `명` 은 없다.)
3. 좁은 폭 또는 큰 글자에서 탭 라벨이 잘려도 **숫자 배지가 보이고 탭이 눌린다**.

이전에 완료한 캡처는 다시 요청하지 않는다.
