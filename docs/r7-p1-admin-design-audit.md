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

---

## R7-P1-3 — P13-R-RELATION-CONTEXT (2026-09-28)

기준 `07fb1e9`. branch `main`, 시작 시 tracked 변경 없음, 사용자 소유 untracked 8건 보존.
T/W 날짜 계약·저장 체인·근무 탭 마커, 숫자 단위 `건`, 분자/분모 동일 단위, 두 관계 보존,
정상 렌더, `AppTabLabel` 수정은 재조사하지 않았다.
Staffing 보정 **DEFERRED**, O08 **PENDING** 유지. 공유 DEV 쓰기·보정·migration·fixture 생성·
배포·Rules·APK·PROD·P1-4 **없음**.

| 항목 | 표시 수정 / NO PATCH 근거 | 재사용 증거 | 이번 실행 | 남은 조건 |
|---|---|---|---|---|
| 혼합 그룹 행이 구별되지 않음 | **수정** — 혼합 그룹의 행에만 `업무명 · 예정 시간` 한 줄 | ACR-5 사례(구 문서 L1·L2) | ACR-5·6·7 | 없음 |
| 헤더가 첫 업무만 대표 | **수정** — 혼합이면 `여러 업무 N종` / `시간 N종 — 행에서 확인` | 같은 사례 | ACR-5 | 없음 |
| 파트별 일괄 처리 헤더 | **수정** — 같은 판정으로 혼합 파트 표기 | 기존 단위 계약 | 소스+분석 | 실제 렌더는 권한 있는 경로 필요(DEVICE) |
| 동질 그룹 표현 | **NO PATCH** — 기존 표현 유지 | ACR-2 | ACR-2 에 `여러 업무` 미표시 단언 추가 | 없음 |
| 기존 확인 단계(개별 선택) | **NO PATCH** — 선택이 이미 `applicationId` 단위 | 기존 `_toggleSelection(app.id)` | ACR-7 | 없음 |

### 무엇을 고쳤나

이전 관찰: `workDetailId` 없는 구 관계 2건이 한 그룹에 들어가고, 두 행이
`이름 · 미출근` 으로만 보여 구별되지 않았다(미출근 행은 `timeText` 가 null 이라 시간 줄이
아예 그려지지 않는다). 헤더는 `workers.first` 의 업무명·시간을 썼다.

**혼합 판정은 그 그룹이 실제로 들고 있는 값으로만 한다** — `_isMixedRelationGroup`:
서로 다른 `selectedWorkType` 이 2종 이상이거나, 예정 시간 범위가 2종 이상이면 혼합.
2건 미만이면 판정하지 않는다.

- **행 문맥**(혼합 그룹에서만): `업무명 · 예정 시간` 한 줄.
  예정 시간은 `WorkDetailHelper.resolve` → 없으면 `app.startTime/endTime`,
  **그래도 없으면 비운다.** `effectiveStart/End` 는 값이 없을 때 `09:00`·`18:00` 을
  돌려주는 **입력 기본값** 이라 사실 표시에 쓰지 않았다 — 모르는 것을 시간처럼 보여주지 않는다.
  없는 경우 문구는 `업무 정보 없음` · `예정 시간 정보 없음` 이다(추정 생성 0).
- **헤더**(혼합일 때만): 제목 `여러 업무 N종`, 부제 `시간 N종 — 행에서 확인`.
  동질 그룹은 **기존 표현 그대로**(`업무명` + `09:00 ~ 13:00`).
- **파트별 일괄 처리 다이얼로그**의 파트 라벨도 같은 판정으로 `여러 업무 N종`.

하지 않은 것: 그룹 키·도메인 상태·좌석·정원·급여·권한·action gate 변경 0 ·
행/관계 삭제·통합·uid 중복 제거 0 · 새 조회 경로 0 · 구 문서 보정/migration 0 ·
무관한 정상 행 디자인 변경 0.

### 검증 — 기존 ACR-5 사례 그대로

`AttendanceReads` 주입 + production `AttendanceStatusDialog`.
같은 uid 의 구 관계 2건(`L1 홀서빙 09:00~13:00`, `L2 주방 보조 14:00~18:00`, 같은 슬롯,
`workDetailId` 없음). 테스트 전용 그룹/카드 복제 없음 — 그룹은 화면이 만든다.

| 확인 | 결과 |
|---|---|
| L1·L2 를 각각 식별 | ✔ 행에 `홀서빙 · 09:00 ~ 13:00` / `주방 보조 · 14:00 ~ 18:00` |
| 헤더가 첫 업무로 대표하지 않음 | ✔ `여러 업무 2종` · `시간 2종 — 행에서 확인` |
| 두 행·두 관계 보존 + 기존 수치 계약 | ✔ 행 2개(다른 id) · 상단 `2건` · `0/2건` · 그룹 `출근 0/2` |
| 개별 선택이 그 관계에 연결 | ✔ L2 체크박스만 눌렀을 때 선택된 체크박스 **1개**, 그 행이 주방 보조(ACR-7). 기존 `_toggleSelection(app.id)` 경로 그대로, 공유 DEV writer 미실행 |
| 동질 그룹은 그대로 | ✔ ACR-2 에서 `여러 업무` 문구 없음 |
| 좁은 폭·큰 글자(320dp·배율 1.3) | ✔ 두 문맥 줄이 **모두 보이고**(축약이 필수 정보를 지우지 않음) 예외 0 · 행동 버튼 접근 · 스크롤 가능(ACR-6) |

**범위 메모:** 테스트의 `UserProvider` 는 권한이 비어 있어 action 버튼이 비활성으로
그려진다(각 `0건`). 그래서 ACR-7 은 **선택이 어느 관계에 붙는지**만 확인했고,
권한이 있는 상태의 실제 실행은 DEVICE 로 남긴다.

### 회귀

영향 테스트만 이름 기준으로: **21파일 `+664 -2` — 새 실패 0**
(남은 2건은 9차 기준선의 `noshow_replacement_cross_slice_contract`).
`flutter analyze` 변경 파일 No issues. 전체 render matrix·Staffing 전수 회귀는 돌리지 않았다.

### P1-3 개발·렌더 종료 자료 (검증된 범위)

| 항목 | 상태 |
|---|---|
| 날짜 입력 계약(진입 4곳 civil day) + 조회창 → `workDateMs` → 저장·문서 id 체인 | CLOSED |
| 근무 탭 날짜창·마커·명단 진입이 같은 선택일 | CLOSED |
| 집계 단위 — 화면의 모든 수치 `건`, 분자/분모 동일 단위 | CLOSED |
| 정상·구 문서 명단/행/그룹/액션 렌더 | CLOSED |
| **혼합 그룹 관계 식별(행 문맥·헤더)** | **CLOSED** |
| 좁은 폭·큰 글자 overflow(`AppTabLabel` 포함) | CLOSED |
| 조회 실패·탭 0건·조회 0건 세 문구 구분 | CLOSED |
| 늦은 응답·연타·권한 게이트 | 유지(기존 증거) |
| 키보드 입력 경로 | 없음 |
| 대비·터치영역 수치 | P4 owner · **이번에 미측정**(PASS 아님) |
| radius 혼재(V4) | POLISH 유지(미수정) |
| 권한 있는 상태의 실제 action 실행 | **DEVICE** |

**P1-3 CODE / RENDER 종료.** DEVICE 는 별도다 — 기기 미실행을 실행 완료로 바꾸지 않는다.

#### 최소 DEVICE 확인안 (이번에 바뀐 문구·행 식별만)

1. 근무 탭에서 **과거 날짜** 선택 → 점·그날 명단(기존 항목 유지).
2. 당일명단: 머리말 날짜 = 고른 날짜, 상단·탭·처리현황·파트 일괄이 **`건`**(화면에 `명` 없음).
3. **혼합 그룹이 보이면**(같은 슬롯에 업무가 섞인 구 공고) 헤더가 `여러 업무 N종` 이고
   각 행에 `업무명 · 예정 시간` 이 보인다. 그 행 하나만 선택해 출근 처리하면 그 관계만 바뀐다.
4. 좁은 폭/큰 글자에서 탭 배지가 보이고 탭이 눌리며, 행 문맥이 잘려도 업무명이 남는다.

**구 문서 자연 표본이 DEV 에 없으면 3번은 넘어간다** — 그 경우 개발 fixture 증거(ACR-5·6·7)로
남기고 **실DEV 데이터를 만들거나 고치지 않는다.**

---

## R7-P1-4 — 관리자 홈·할 일·요약 (2026-09-28)

기준 `6135916`. branch `main`, 시작 시 tracked 변경 없음, 사용자 소유 untracked 8건 보존.
Staffing 보정 **DEFERRED**, O08 **PENDING** 유지. 공유 DEV 쓰기·보정·migration·fixture 생성·
CF 배포·Rules·APK·PROD·P1-5 **없음**.

### 실제 영역별 표 (홈 화면 = `business_admin_home_screen.dart`)

| 홈 영역 | 수치 source / 계산 owner | 사업장·날짜·모집단·단위 | 표시 문구 | action · 목적지 문맥 | loading / error / 권한 | 판정 |
|---|---|---|---|---|---|---|
| 헤더(ALfit·이름·사업장) | `UserProvider` | 선택 사업장 | 이름·사업장명 | 없음 | 권한 변경은 `Selector` 로 재구독 | NO PATCH |
| 상태 배너 | `_hasApprovedBusiness`(조회 성공 여부) | 관리 사업장 전체 | 승인 대기·미등록 | 사업장 등록 | 조회 실패는 `null` 유지 → 배너 미표시(AHV2-01) | NO PATCH |
| Hero | `_heroStateOf` (staffing + roster + readiness) | 오늘 | 상태 1종 | 상태별 CTA | 로딩·실패가 각자 상태 | NO PATCH |
| 권한 요약 줄 | `checkCurrentBusiness` | 선택 사업장 | 권한 목록 | 없음 | `PermissionWatchState.error` 를 별도 표시 | NO PATCH |
| 공고 준비 카드 | `FirstPostingReadiness`(4단계) | 사업장별 | `N / 4 완료` = 단계 | 단계별 CTA | 템플릿 조회 실패 시 "준비됨"으로 올리지 않음 | NO PATCH |
| **오늘 — 인력 요약** | CF `callableGetStaffingReadiness` `requiredCount`/`confirmedCount` | 오늘(KST) · 좌석(정원) · `명` | ~~`N명 필요 · M명 확정`~~ → **`N명 중 M명 확정`** | 없음(context) | 로딩 spinner · 실패 행 · `hasTodayTarget` 없으면 null | **수정** |
| 오늘 — 부족 행 | 같은 CF `shortageCount`(종료 단위 제외) | 오늘 · 충원 가능 좌석 · `명` | `N명 부족 [· 사업장]` | `DayApplicantsDialog`(그날 · 부족 사업장 우선) | 로딩·실패면 숫자 주장 안 함 | NO PATCH |
| 오늘 — 근태 확인 행 | roster 파생 `AttendanceReviewHelper` | 오늘 · **지원서(근무 건)** · `건` | `근태 확인 N건` | `AttendanceStatusDialog`(오늘·사업장 목록) | `_todayCheckedIn == null` 이면 행 없음 | NO PATCH (주석 근거 정정) |
| 오늘 — 출근 줄 | 같은 roster + `attendance` | 오늘 · 같은 모집단 | `출근 x/y` · 분모 0 → `출근 예정 전` | 없음 | 실패 → 실패 행(ERROR≠ZERO) | NO PATCH |
| 오늘 — 부분합 고지 | CF `partial`/`failedBusinessCount` | 성공 사업장 합 | `사업장 N곳 … 나머지 기준` + 재시도 | 재시도 | partial 이면 scope 라벨 숨김 | NO PATCH |
| 다가오는 7일 | 같은 CF `days[1..7]` | D+1~D+7 · 좌석 · `명`, 대기 `건` | `N명 중 M명 확정` / `N명 전원 확정` · `N명 부족` · `지원 대기 N건` | 행 전체 → 그날 지원자 | 로딩·실패·빈 목록 3분기 | NO PATCH (오늘 요약이 여기에 맞춰졌다) |
| 처리할 일 — 퇴사 요청 | CF `actions.resignRequest` | 사업장별 요청 · `건` | `N건` + `내일 자동 승인 N건` | 사업장 선택 시트(건수 동반) → 기존 관리 다이얼로그 | UNKNOWN 은 행 없음 + section notice | NO PATCH |
| 처리할 일 — **지원 검토** | CF `srvHomeApproval` = `applications where status==PENDING` | 사업장 · **지원서** | ~~`N명`~~ → **`N건`** (배지는 이미 `긴급 N건`) | `SupportReviewQueueScreen`(긴급>0 이면 overdue 필터) | 같음 | **수정** |
| 처리할 일 — 스케줄 변경 | CF `scheduleChangeRequest` | 요청 · `건` | `N건` | 사업장 선택 → 관리 다이얼로그 | 같음 | NO PATCH |
| 처리할 일 — **계약 미발송** | CF: 좌석 보유 지원서 중 미발송 계약서 | **계약서(건)** | ~~`N명`~~ → **`N건`** | 계약 관리 화면 `initialTab: 1` | 같음 | **수정** |
| 처리할 일 — 마감 필요 | CF `unclosedDates.size` | **고유 날짜** | `N일` + `가장 오래된: date` | `UnclosedActionQueueScreen` | 같음 | NO PATCH (단위 정확) |
| 처리할 일 — 중간정산·급여변경 | CF 각 요청 수 | 요청 · `건` | `N건` | 급여 탭 drilldown(탭 지정) | 같음 | NO PATCH |
| 처리할 일 — 이체 대기 | CF `groups.size`(근로자×지급일) + `missingUserIds.size` | 처리 카드(이체 묶음) | `N건` · 배지 `연체 N건 · 지급일 확인 필요 ~~N명~~ → N건` | 급여 탭 drilldown | 연체>0 이면 자리만 상향 | **수정(배지 단위)** |
| 처리할 일 — **계약 확인 필요** | CF `srvHomeExpiringContract` = 갱신 결정 대상 장기 지원서 | **관계(건)** | ~~`N명 · 만료 N`~~ → **`N건 · 만료 N`** | 만료 계약 화면 | 같음 | **수정** |
| 처리할 일 — health notice | `cs == null` 또는 `_unknownTaskCount > 0` | — | `확인하지 못한 …` | 재시도 | **미조회를 `할 일 없어요` 로 바꾸지 않음** | NO PATCH |

### H1 — 숫자·모집단·문구

**carry `[CORRECTION-R7-HOME-REQUIRED-VS-RECRUITABLE-SHORTAGE-COPY]` RESOLVED.**

서버는 `required += wd.required`(종료 단위 포함), `shortage += wd.closed ? 0 : max(0, req-conf)`
로 **다른 모집단**을 센다. 그래서 `5명 필요 · 0명 확정` 옆의 `2명 부족` 은 데이터로는 정상인데,
두 축이 같은 단어(`필요`/`더 필요`)를 써서 `5-0=5` 를 기대한 사람에게 어긋난 산술로 읽혔다.

→ **정원 축에서 `필요` 를 뺀다.** 근거는 **같은 화면 안에 이미 있던 표현**이다 —
`_buildFutureShortageRow`(D+1~D+7)가 **같은 서버 세 필드**로 `N명 중 M명 확정` +
`N명 부족` 을 쓴다. 오늘 카드만 다른 단어였다. 새 라벨을 만들지 않고 그 계약에 합쳤다.
`전원 확정` 문구·Hero `오늘 N명이 더 필요해요`·서버 산술·모집단·지표는 **그대로**다.

**단위를 원천에 맞춘 3곳**(위 표의 `수정`): 지원 검토·계약 미발송·계약 확인 필요는 모두
서버가 **지원서/계약서/관계**를 세는데 홈만 `명` 이라 없는 사람을 셌다. 목적지 drill-down
시트는 이미 `총 N건` 이고, 지원 검토 행은 한 행 안에서 `N명 · 긴급 M건` 으로 갈라져 있었다.
`이체 대기` 배지도 합계(`건`)와 같은 단위로 맞췄다.

**정원 축은 `명` 을 유지한다** — `confirmed` 는 업무단위 좌석 카운터의 합이라 한 사람이
겹치지 않는 두 자리를 채우면 2 가 되지만, 관리자가 채우는 대상은 **자리**이고 제품 전반이
모집 인원을 `명` 으로 쓴다. 분자·분모가 같은 축(좌석)이라 단위도 어긋나지 않는다.
**고유 인원 지표는 만들지 않았다.** 단, `근태 확인` 의 코드 주석이 "지원서 Set 이라 한 사람은
1 로 센다(`N명` 보장)" 라고 잘못 말하고 있었다 — Set 원소는 `uid` 가 아니라 `applicationId`
이므로 그 근거를 정정했다(표시는 이미 `건`).

### H2 — 할 일·권한·목적지·복귀

분류 owner 는 CF canonical summary 하나다(`AdminHomeSummaryService`). 홈은
`available && count > 0` 만 행으로 만들고(`KNOWN_ZERO`/`UNKNOWN` 은 행 없음),
UNKNOWN 은 section notice 가 말한다 — **미조회·권한없음·실패를 `0` 이나 `할 일 없음` 으로
바꾸지 않는다.** icon 은 중립 grey, 긴급은 배지 한 채널, count 는 전부 같은 무게 →
**정상 0 을 위험으로 칠하는 자리가 없다.** 목적지는 사업장 선택 시트(사업장별 건수 동반)·
`initialFilter: overdue`·`initialTab` 로 문맥을 넘기고, 복귀 시 각 행이
`_loadCanonicalSummary()` 를 다시 돌리며 다른 탭에는 `WorkforceController` 로 알린다.
권한은 행 생성 시점(`_verified`) + onTap 재확인 + `sec.available` + CF 재검증의 4중이다.

**수정 — 늦은 응답 가드가 없었다.** 같은 loader 를 동시에 깨우는 경로가 6개다(initState ·
FCM `_onFcmRefresh` · 앱 복귀 · 당겨서 새로고침 · 사업장 전환 `_onBusinessSwitchCheck` ·
각 목적지 복귀). `_isRefreshing` 은 **전체 refresh 끼리만** 막아서, 먼저 보낸 응답이 늦게
도착하면 **방금 처리한 결과를 덮었다**(처리한 할 일이 다시 대기로 보이고 눌러도
`count == 0` 으로 조용히 닫힌다). 사업장 전환에서는 더 나쁘다 — 이전 사업장 수치가 새
사업장 화면에 앉는다. → 세 loader 에 단조 증가 seq 를 넣어 **마지막에 시작한 호출만**
state·로딩 플래그를 쓴다(P1-3 `_attRefreshSeq` 와 같은 패턴).

### H3 — 위계·공용 책임·반응형

**`_s()` 와 `ResponsiveHelper.getScale` 은 같은 책임이다** — 둘 다 화면 폭으로 정하는
**레이아웃 치수 전용** 배율이고, 폰트는 [TYPO-01] 로 양쪽 다 건드리지 않는다(글자 크기는
base × OS TextScaler). 홈의 `_s()` 는 사설 사본이었고(`0.82/0.92/1.0/1.08`), 같은 곡선이
`user_home_screen`·`income_detail_screen`·`wage_detail_screen` 에도 있어 **총 4벌**이었다.
→ 홈은 공용 owner 에 위임했다. 값이 바뀌는 구간(`<360` 0.82→0.85, `<400` 0.92→0.90,
`>=480` 1.08→1.0)에서 정보가 숨거나 줄지 않는지 **320/360/390/480/600dp 렌더로 확인**했다.
남은 사설 3벌은 사용자 화면이라 **이 Phase 소유가 아니다**(별도 항목).
radius 16·flat surface·중립 icon 은 현행 관리자 기준 그대로 — 새 컴포넌트·새 기준 도입 0.
탭 본문에 Scaffold 를 덧붙이는 기계적 변경도 하지 않았다.

### H4 — 실제 콘텐츠 렌더 (production 위젯)

지금까지 홈을 pump 하는 테스트는 shell 하나뿐이었고(`shell_lazy_tab_contract`) 숫자·할 일·
문구는 전부 소스 문자열 검증이었다. → 원시 외부 읽기 **7개만** 주입하는 경계
`lib/screens/business_admin/admin_home_reads.dart` 를 넣고(파싱 이전에서 끊어 파생·수치·
문구·권한 판정·게이트는 화면에 남긴다) 실제 `BusinessAdminHomeScreen` 을 렌더했다.
권한은 provider 경계에서 BUSINESS_ADMIN 으로 준다 — **권한 없는 provider 가 숨긴 버튼을
확인했다고 세지 않는다.**

`admin_home_content_render_test` 10건:

| 증거 | 확인 |
|---|---|
| AHR-1 | 오늘 요약 `5명 중 0명 확정` · `5명 필요` **없음** · `2명 부족` 별도 행 |
| AHR-2 | `4명 전원 확정` · 부족 문구 없음 |
| AHR-3 | 할 일 `3건`·`긴급 1건`·`2건`·`4건 · 만료 1` · `3명`/`2명`/`4명 · 만료 1` **없음** |
| AHR-4 | 0건이면 행 없음 + 전부 성공일 때만 `처리할 업무가 없어요` |
| AHR-5 | 할 일 CF 실패 → `처리할 업무가 없어요` **아님**, `확인하지 못…` 표시 |
| AHR-6 | 인력·출근 실패 → 각 실패 문구 + 재시도, `0명 중 0명`·`출근 0/0` 없음 |
| AHR-7 | partial → `사업장 1곳 …` 고지, `전체 2개 사업장 합계` 주장 안 함 |
| AHR-8 | 320dp·배율 1.3 + 긴 사업장명 + 큰 수(128/96/32·147) 예외 0, 수치 유지 |
| AHR-9 | 다사업장 scope 라벨 + 합계 |
| AHR-10 | 320/360/390/480/600dp 전 폭 예외 0 · 핵심 수치·섹션 유지 |

렌더가 드러낸 사실 하나: 투어 게이트(`TourHelper.isCompleted`)가 끝나지 않으면
`initState` 의 `Future.wait` 가 멈춰 **네 loader 가 아예 시작하지 않는다**(영구 spinner).
테스트에서는 SharedPreferences mock 으로 완료 상태를 준다. production 경로에서는
SharedPreferences 가 실패할 때 같은 정지가 가능하다 — **관측·수정 안 했고 이번 범위 밖**
(`[R7-P1-4-RESIDUAL-TOUR-GATE-BLOCKS-LOADERS]`).

### 회귀

- `admin_home_*` 전체 + shell: **1022 passed**
- 전체 스위트: `13738 passed / 41 실패` — **기준선과 동일**. 샘플 10파일을 HEAD(`6135916`)에
  `git stash` 로 되돌려 재실행해 **같은 19건**이 실패함을 확인했다(날짜·시각 의존 다수:
  `payroll_simulation_extended` D2, `longterm_renewal_boundary`, `my_applications_simulation` 등).
- 내 변경이 만든 실패 **1건**: `active_reader_error_not_empty` AR-7(홈이 OrThrow 를 쓰는지) —
  경계 이전으로 앵커가 옮겨진 것이라 **화면은 경계를 부르고 경계가 OrThrow 로 매핑한다**
  두 단언으로 재앵커(요구는 낮추지 않았다).
- **P1-3 증거 결함을 발견해 고쳤다**: `attendance_dialog_content_render`(ACR-1~7)가
  고정 날짜 `2026-09-28` + 고정 시각(09:00~13:00)을 써서 **실행 시각에 따라 탭 분류가
  갈렸다**(오전 `정상`, 저녁 `확인필요`). HEAD 에서도 3건 실패 상태였다 — 선택일을 **내일**로
  바꿔(항상 '출근 전') 시계 의존을 없앴고 7/7 PASS. 이 테스트들이 보는 것은 그룹·문맥·수치다.
- `flutter analyze lib test`: No issues.
- 재앵커한 기존 계약 파일 13개 — 읽기 배선 단언은 **화면 + 경계**를 함께 읽게 바꿨고,
  `getBusinessesByIdsOrThrow` 같은 문자열은 `_reads.X(` + 경계의 `svc.X` **쌍**으로 요구한다.

### 남은 것 / 이관

| 항목 | 상태 |
|---|---|
| H1 문구·단위 (오늘 요약 + 할 일 4곳) | CLOSED (CODE·RENDER) |
| H2 분류 owner·권한 4중·목적지 문맥·복귀 갱신 | CLOSED (CODE, 기존 증거 연결) |
| H2 늦은 응답 가드 | CLOSED (수정) |
| H3 배율 공용 위임 | CLOSED (폭 5종 렌더) |
| H4 production 콘텐츠·실패·부분실패·좁은 폭 렌더 | CLOSED |
| 권한 있는 상태의 **실제 목적지 이동·처리 실행** | **DEVICE** |
| 사용자 화면 사설 `_s()` 3벌 | 이관(P1-4 소유 아님) |
| 투어 게이트 정지 가능성 | `[R7-P1-4-RESIDUAL-TOUR-GATE-BLOCKS-LOADERS]` 미수정 |
| 대비·터치영역 수치 | P4 owner · **이번에 미측정**(PASS 아님) |
| 기존 전체 스위트 실패 41건 | 기준선 — 이번 범위 아님 |

#### 최소 DEVICE 확인안 (이번에 바뀐 화면만)

1. 홈 `오늘`: 요약이 `N명 중 M명 확정`(또는 `N명 전원 확정`)이고 그 아래 `N명 부족`.
   화면에 `N명 필요` 가 없다.
2. `처리할 일`: 지원 검토·계약 미발송·계약 확인 필요가 **`건`**, 이체 대기 배지도 `건`.
   각 행을 눌러 사업장 선택 시트의 건수와 목적지 목록 건수가 홈 수치와 같은지.
3. 처리 후 돌아와 그 행의 수치가 줄어드는지(복귀 갱신).
4. 좁은 폭/큰 글자에서 요약·부족·할 일 수치가 잘리지 않는지.
5. SubAdmin 사업장 전환 직후 수치가 **이전 사업장 값으로 되돌아가지 않는지**(seq 가드).

---

## R7-P1-4 후속 — 홈 계약·초기 로드·이동 검증 (2026-09-28)

기준 `4b6804f`(그 전 `6135916`). branch `main`, 시작 시 tracked 변경 없음, 사용자 소유
untracked 8건 보존. 수용된 단위·`_s` 위임·렌더 10건 증거는 **재사용**했고 재조사하지
않았다. 사용자 화면 배율 사본 3곳 = P2/P3, 대비·터치영역 = P4 그대로.
Staffing 보정 **DEFERRED**, O08 **PENDING**. 공유 DEV 쓰기·fixture·보정·배포·Rules·
PROD·APK·P1-5 **없음**.

### 1. H1 — 실제 문구 조합과 부족의 범위 → **수정**

production 홈을 그려 얻은 **실제 순서**(단일 사업장·정원 5·확정 0·부족 2):

```
ALfit · 김관리님 · 관리자 · 강남 물류센터
[Hero]    오늘 2명이 더 필요해요
[섹션]    오늘                                  · 당일 명단
          5명 중 0명 확정
        ⚠ 2명 부족
          출근 예정 전
[섹션]    처리할 일   → 지원 검토 3건 · 계약 미발송 2건
```

계약은 그대로다 — `required` 는 종료된 모집 단위까지 포함하고, `shortage` 는 모집
가능한 단위만 반영한다(`wd.closed ? 0 : max(0, req-conf)`). 목적지도 **같은 술어**를
쓴다: `DayApplicantsDialog` 의 `_GroupData.shortage` → `staffingShortageOf` 가
`closed` 에서 0 을 돌려준다. 즉 홈의 `2명 부족` 과 목적지 총 부족은 같은 정의다.

**그러나 화면 어디에도 부족의 범위를 말하는 문장이 없었다.** `N명 중 M명 확정` 은
정원 축을 정확히 말하지만 그것만으로 `5 - 0 ≠ 2` 를 설명하지 않는다 → NO PATCH 로
닫지 않고 **보조 한 줄**을 부족 행에만 붙였다.

- 문구: `지금 모집 중인 업무만 센 숫자예요` (12px grey, 배지·색 추가 없음 → D0 의
  "행당 강한 강조 제한" 유지)
- 조건: `(정원 - 확정) != 부족` 인 날만. **비교일 뿐이고 그 차이를 화면에 쓰지 않는다** —
  정원-확정=부족 공식을 강제하지도, 새 지표·통계 모델을 만들지도 않았다.
- **원인을 단정하지 않는다.** 어긋남의 원인이 하나가 아니다 — 모집이 끝난 단위가
  정원에 남아 있거나(`closed`), 어떤 단위의 과충원이 다른 단위의 부족을 상쇄하지
  못하기 때문이다(부족은 단위별 `max(0,·)` 합산). 그래서 "모집이 끝난 자리" 같은
  단정 문구를 쓰지 않고 부족이 세는 **범위**만 말한다.
- 다가오는 7일 행은 `부족` 이 오른쪽 배지로 분리돼 같은 오해가 약하고, 이 후속의
  범위가 오늘 요약이므로 **바꾸지 않았다**(판단 기록).

증거(모두 production 위젯): AHR-11 어긋나는 날 → 보조 줄 표시 + 원인 단정 문구 없음 +
새 숫자 없음 / AHR-12 맞아떨어지는 날 → 보조 줄 없음 / AHR-13 과충원 상쇄로 부족이
더 큰 날 → 같은 보조 줄 / AHR-14 320dp·배율 1.3 + 긴 사업장명 + 128·32 에서 라벨과
보조 줄이 **둘 다 남고** 예외 0. 전체 render matrix 는 다시 돌리지 않았다.

### 2. H2 — 투어 판정과 초기 데이터 로드 → **수정**

**실제 의존관계(수정 전):**

```
addPostFrameCallback
  └ await Future.wait([ _loadApprovedBusinessStatus(), TourHelper.isCompleted(adminHome) ])
      └ (투어 미완료면) pushTourScreen → markCompleted
          └ if (mounted) { 4 loader 시작 }        ← 투어 future 뒤에 있었다
```

`TourHelper.isCompleted` 는 SharedPreferences 한 줄이고 **권한·사업장·수치 어디에도
쓰이지 않는다**(증거: `admin_home_dead_loader_test` 의 새 group — 네 loader 본문과
`_verified` 에 `tour` 문자열 0건). 즉 **데이터·권한 준비의 전제가 아니다.**
그런데 `await` 가 그 future 를 함께 기다려서, 그것이 늦거나 던지면 네 loader 가
**시작조차 하지 않았다** — 화면 전체가 끝나지 않는 spinner 로 남고, 각 영역의 재시도
행조차 나오지 않는다(재시도는 loader 가 한 번 돌아 error 상태가 돼야 그려진다).

**수정:** 순서를 데이터 의존만으로 정한다 — `await _loadApprovedBusinessStatus()`
(→ `_loadPostingReadiness` 가 `_businesses` 를 읽으므로 필요) → 네 loader 시작 →
그 뒤에 투어를 **독립적으로** 확인하고 실패는 삼킨다. 투어 실패·timeout 을 완료로
저장하지 않고(`markCompleted` 는 `pushTourScreen` 뒤에만), 투어 기록을 지우지 않으며
(`TourHelper.reset` 경로 0건), 새 고정 timeout 정책도 넣지 않았다.

좁은 투어 상태 주입은 기존 읽기 경계에 한 칸을 더해서 했다 —
`AdminHomeReads.tourCompleted`(기본값 `TourHelper.isCompleted(adminHome)`).

| 시나리오 | 결과 |
|---|---|
| AHR-15 투어 future 영구 pending | 인력·출근·할 일 수치 **모두 표시**, spinner 0 |
| AHR-16 투어 판정 실패(throw) | 수치 표시 + 화면 예외 0, 완료로 저장하지 않음 |
| AHR-17 화면 파기 후 늦게 `미완료` 도착 | 투어를 열지 않고 예외 0 (`if (!tourDone && mounted)`) |
| 정상 완료(true) | 기존 동작 — 나머지 render 증거 22건이 이 경로다 |

production 영구 spinner 는 여전히 **미관측**이다(재현은 주입 경로에서만 했다).

### 3. H2 — 늦은 응답 · 실제 목적지 · 복귀 갱신

**seq 가드는 소스만 있었다 → 실제 순서를 실행했다.** 두 번째 로드는 테스트용 훅이
아니라 production 회수 신호(`WorkforceController.notifyDataChanged` → `_onAdminMutation`
→ `_autoRefresh`)로 일으켰다.

| 증거 | 순서 | 기대 |
|---|---|---|
| AHR-18 동일 scope 역전 | staffing#1 늦게(9/0/9) · #2 먼저(5/3/2) | 화면은 `5명 중 3명 확정` 유지, `9명…` 미표시 |
| AHR-19 늦은 **실패** | staffing#1 늦게 throw · #2 성공(4/4/0) | `4명 전원 확정` 유지, 에러 행 미표시 |
| AHR-20 처리 후 옛 응답 | summary#1 늦게(지원 3·퇴사 1) · #2 전부 0 | 처리한 행이 되살아나지 않음 |
| AHR-21 파기 후 도착 | 홈 dispose 후 완료 | 예외 0, 다른 화면 유지 |

**가드가 그 결함을 막는지 확인했다** — `seq != _staffingSeq` 를 일시 제거하면
AHR-18 이 `5명 중 3명 확정` 을 찾지 못하고 실패한다(원복 후 25건 PASS).
사업장/날짜 변경과 동일 scope 역전은 구분했다 — 위 넷은 **동일 scope** 이고,
사업장 전환 경로(`_onBusinessSwitchCheck`)는 같은 가드가 덮는다(소스 계약).
모든 loader·앱 전체 race 감사로 확장하지 않았다.

**실제 이동은 실행했다 — DEVICE 로 미루지 않았다.** 서로 다른 context 형태의 대표
진입 셋을 골랐다(모두 기존 영역 표의 입력만 사용).

| 진입 | 전달된 context | 복귀 |
|---|---|---|
| AHR-22 `당일 명단` | `AttendanceStatusDialog(date = 오늘 KST 달력일, businessIds = 홈 scope 2곳, businesses 동일 순서)` | `pop(true)` → **인력·출근 재조회**(호출 수 증가로 확인) |
| AHR-23 부족 행 | `DayApplicantsDialog(date = 그 날, businessIds = 부족 사업장만 `[biz2]`)` | `pop(true)` → **인력 재조회** |
| AHR-24 할 일(퇴사 요청, 2사업장) | 사업장 선택 시트에 `총 3건` + 두 사업장 이름 — 홈 수치와 같은 단위 | 시트에서 멈춤(관리 다이얼로그 진입 없음) |
| AHR-25 권한 없는 SubAdmin | `당일 명단`·`지원 검토`·`퇴사 요청`·`계약 미발송` **전부 비노출** | — |

목적지 내부 계산·렌더는 P1-2/P1-3 증거를 재사용한다 — 이 테스트들은 **문맥 전달과
복귀 갱신만** 본다(목적지가 자기 조회로 내는 예외는 대상 밖으로 명시해 흘려보냈다).
공유 DEV 근태·급여 처리·초대 발송·확정 취소는 **실행하지 않았다** — 실제 도메인
쓰기의 검증은 DEVICE 로 남는다.

### 4. H4 — 회귀 비교의 정확한 범위

| 항목 | 값 |
|---|---|
| 기준 SHA(수정 전) | `6135916` |
| 비교 시점의 수정 | **working tree 의 uncommitted 변경** — `git stash push -- lib test` 로 되돌린 뒤 tree 가 정확히 `6135916` 이었다(그래서 "이미 commit 된 같은 코드"를 대조로 세지 않았다) |
| 수정 SHA | `4b6804f`(+ `9f45090`), 이번 후속은 그 위 |
| 테스트 집합 | **10파일**(attendance_dialog_content_render · payroll_simulation_extended · my_applications_simulation · longterm_renewal_boundary · posting_close_reopen_contract · invitation_detail_projection · mixed_staffing_parity · noshow_replacement_cross_slice_contract · longterm_seat_counter_contract · active_reader_error_not_empty) |
| 환경·날짜 | 같은 기기·같은 flutter, 2026-09-28 |
| 결과 | 기준 **19 실패** → 현재 **16 실패**. 사라진 3건 = ACR-5·6·7(시계 의존 제거). `active_reader` AR-7 은 기준에서 PASS 였고 내 seam 이 깨뜨렸다가 재앵커로 PASS |

**정정:** 첫 P1-4 보고와 commit 메시지의 "전체 스위트 실패 41건은 기준선과 동일" 은
**측정 범위를 넘은 주장이었다.** 기준선을 잰 것은 위 10파일뿐이고, 전체 스위트는
수정 후 한 번만 돌렸다. 전체에 대한 "신규 실패 0" 은 주장하지 않는다.
기존 실패 다수는 날짜·시각 의존(`payroll_simulation_extended` D2 등)이지만 이번
범위에서 고치지 않았고, CRLF·고정시각 차이를 제품 수정 성과로 세지 않는다.

**`attendance_dialog_content_render` 의 검증 목적:** ACR-1~7 은 **탭 전환·업무 그룹·
행·관계 문맥·수치 단위**를 본다. 탭을 여는 것은 행에 도달하기 위한 수단이고,
`정상`/`확인필요` **분류 경계 자체의 계약은 owner 가 따로 있다** —
`admin_home_attendance_actionability_test` 가 `AttendanceReviewHelper.requiresReviewNow`
에 **고정 now**(`_t(8,59)` false / `_t(9,0)` true …)를 주입해 경계를 직접 검증한다.
그래서 내일 fixture 로 안정화한 것은 경계를 피한 것이 아니라 **다른 계약의 시계
의존을 없앤 것**이다. 변경은 두 줄뿐이고(`_day` 정의 + 머리말 날짜 파생) **원래
assert 는 전부 그대로다**(`git show 9f45090` 로 확인: 15 insert / 2 delete).
같은 기준으로 홈 렌더 테스트의 고정 날짜 `'2026-09-28'` 도 없앴다 — 이 파일의
날짜 기준은 `_todayStr`(오늘 KST) 하나다.

#### 4-1. 전체 스위트를 처음 제대로 읽고 나온 정정 (중요)

이번 후속에서 **전체 스위트를 돌려 이름별로 확인**했더니, 첫 P1-4 보고가 놓친
**내 변경 탓의 실패 5건**이 있었다. `admin_home_*` 만 돌려서 생긴 누락이다 —
첫 보고의 "전체 실패는 기준선과 동일" 이 왜 잘못된 주장이었는지가 이것으로 드러난다.

| 실패 | 원인 | 조치 |
|---|---|---|
| `admin_home_surface_consistency` SURFACE-05 §13 typography | 새 보조 줄이 `fontSize: 12` 개수를 17→18 로 | 개수 갱신(위계 규칙 18 금지·11 금지·15=5 는 그대로) |
| `home_readiness_refresh` HRR-42 | `Future.wait` 목록 형태를 앵커로 쓰고 있었다 | `await _loadApprovedBusinessStatus();` 로 재앵커 + **투어가 그 사이에 끼지 않는다**는 단언 추가 |
| `posting_home_readiness_identity` READINESS-09-b | `forBusinesses(`·`getTemplates(` 가 경계로 이동(4b6804f) | 화면 호출 1회 + 경계의 owner 매핑 1회 **쌍**으로 요구 |
| `staffing_applicant_read_purpose` SAP-H3 | 홈의 원시 reader 가 경계로 이동(4b6804f) | 경계 파일을 같은 목적으로 검사 |
| `renewal_decision_surface` 06-b | `명`→`건` 단위 변경(4b6804f) | 건으로 갱신 + 근거 주석 |

최종 전체 스위트(수정 후): **13763 passed / 67 실패**. 위 5건을 고친 뒤 재실행한 값이고,
잔존 실패는 아래 "무관" 분류에 해당한다. **전체 기준선은 여전히 미측정**이므로 이 숫자로
"신규 실패 0" 을 주장하지 않는다.

**내 변경과 무관한 것으로 확인한 것:**
- `renewal_decision_surface` 07-a·07-b·07-d — `fixed_worker_management_dialog.dart` 를
  `'\n'` 로 이어붙인 여러 줄 코드로 대조하는데 그 파일이 작업트리에서 **전부 CRLF** 다.
  내 diff 는 그 파일을 0줄 건드렸고, `git stash` 로 되돌린 HEAD 에서도 같은 3건이 실패한다.
  **CRLF 차이를 제품 수정 성과로 세지 않는다** — 고치지 않고 사실만 기록한다.
- `typography_device_scaling` TYPO-42 — `FittedBox` 개수 6 기대 / 현재 7. 내 diff 의
  `FittedBox` 추가는 **0건**이다(기존 실패).
- 날짜·시각 의존 다수(`payroll_simulation_extended` D2 · `unit/to_model` ·
  `models/application_model_test` · `weekly_work_count` · `my_applications_simulation` 등).

#### 4-2. 줄바꿈이 검증을 좌우하고 있었다 (기록)

`git stash` 로 기준선을 잰 뒤 `pop` 하면 `core.autocrlf=true` 때문에 되돌아온 파일이
**CRLF 로 다시 쓰인다.** 그런데 소스를 `'\n'` 으로 이어 붙여 대조하는 앵커가 몇 개 있어서,
**내용이 같아도** 그 순간 실패한다 — 실제로 `admin_home_expiring_permission` 02-a 가
그렇게 한 번 빨간색이 됐다(내 편집이 LF 로 써 두는 동안에는 통과했다).

조치: **읽는 자리에서 정규화**했다(`_src` 에서 `\r\n → \n`) — 대조 방식의 문제이므로
제품 수정 성과로 세지 않는다. 적용은 이번 변경 경로의 두 파일뿐이다
(`admin_home_expiring_permission_test`, `renewal_decision_surface_test`).
그 결과 `renewal_decision_surface` 07-b·07-d 도 함께 통과한다.

**남긴 것:** `renewal_decision_surface` 07-a 는 줄바꿈 문제가 아니라 **낡은 앵커**다 —
`'w.application.resignStatus == null && !isExpiredUndecided(w)'` 를 한 줄로 기대하는데
소스는 두 줄로 포매팅돼 있다(`fixed_worker_management_dialog.dart:919-920`).
**계약 자체는 소스가 만족한다**(정상 집계가 `isExpiredUndecided` 를 제외한다).
그 화면은 이번 변경 경로가 아니므로 고치지 않고 기록한다.
`typography_device_scaling` TYPO-42(FittedBox 6 기대 / 현재 7)도 내 diff 와 무관하다.

### 5. 종료 자료

| ID | 이전 → 현재 | 수정 / NO PATCH | 재사용 증거 | 이번 실행 | 남은 조건 |
|---|---|---|---|---|---|
| H1 정원/부족 문구 | 단어 충돌 해소 → **범위 설명 추가** | **수정**(보조 한 줄, 조건부) | AHR-1·2, 서버 두 줄, 목적지 동일 술어 | AHR-11·12·13·14 | 없음 |
| H1 할 일 단위 | `명`→`건` 4곳 | 수정(완료) | AHR-3 | 재사용 | 없음 |
| H2 투어 게이트 | RESIDUAL → **판정 완료** | **수정**(독립 로드) | — | AHR-15·16·17 + 소스 계약 4건 | production 영구 spinner 는 미관측 |
| H2 늦은 응답 | 소스만 → **순서 실행** | 수정(완료) | — | AHR-18·19·20·21 + 가드 제거 대조 | 없음 |
| H2 목적지 context·복귀 | 미실행 → **실행** | NO PATCH(계약 성립) | P1-2/P1-3 목적지 내부 | AHR-22·23·24·25 | 실제 도메인 쓰기 = DEVICE |
| H3 공용 배율 | 위임 완료 | 수정(완료) | AHR-10(폭 5종) | 재사용 | 사용자 화면 사본 3곳 = P2/P3 |
| H4 회귀 범위 | 과대 주장 → **정정** | — | 10파일 기준선 | 10파일 재측정(19→16) | 전체 기준선은 미측정(주장 안 함) |
| H4 시간 fixture | 3건 실패 → **의미 정리** | 수정(완료) | 분류 owner 고정 now | diff 확인 | 없음 |
| 대비·터치영역 | — | — | — | **미측정** | P4 owner |

**필수 결론**
1. **정원/모집 가능 부족의 의미는 이제 화면에서 구분된다** — 정원 축은 `N명 중 M명 확정`,
   부족 축은 `N명 부족` + 어긋나는 날에만 `지금 모집 중인 업무만 센 숫자예요`.
2. **투어 지연·실패는 홈 데이터를 영구 차단하지 않는다** — pending·throw 두 경우 모두
   수치가 그려진다(AHR-15·16). 투어는 데이터·권한의 전제가 아니라는 것도 소스로 확인했다.
3. **실제 목적지 context 와 복귀 갱신을 실행했다** — 날짜·사업장·부족 사업장·건수 context
   전달과 `pop(true)` 후 재조회를 production 경로에서 확인했다(AHR-22·23·24), 권한 없는
   경로의 기존 차단도 함께(AHR-25).
4. **비교 범위는 10파일이고 시간 fixture 수정은 분류 계약을 피한 것이 아니다** — 전체
   스위트 기준선은 측정하지 않았음을 명시한다.

#### 최소 DEVICE 안 (이번에 바뀐 화면만)

1. 홈 `오늘`: 정원과 확정이 부족과 이어지지 않는 날에 부족 아래 보조 줄이 보이고,
   맞아떨어지는 날에는 보이지 않는다.
2. 앱을 처음 설치한 계정(투어 미완료)으로 홈 진입 → 투어를 닫은 뒤 수치가 있고,
   비행기 모드/저장소 이상에서도 홈이 끝나지 않는 spinner 로 남지 않는다.
3. `당일 명단`·부족 행·할 일 행에서 목적지의 날짜·사업장·건수가 홈과 같고,
   처리 후 돌아오면 그 수치가 줄어든다.
4. SubAdmin 사업장 전환 직후 수치가 이전 사업장 값으로 되돌아가지 않는다.
5. 권한 없는 SubAdmin 계정에서 같은 자리들이 아예 보이지 않는다.

---

## R7-P1-5 — 관리자 급여 화면군 (2026-09-28)

**기준 SHA 차이:** 요청서는 `ebcd16a`(P1-4 후속 보고)를 기준으로 적었고 **실제 HEAD 도
`ebcd16a`** 였다 — 차이 없음. branch `main`, 시작 시 tracked 변경 0, 사용자 소유
untracked 8건 보존. Staffing 11TO/21업무 보정 **DEFERRED**, O08 **PENDING** 유지.
공유 DEV 쓰기·fixture·CF 배포·Rules·PROD·APK **없음**. 실제 은행 이체 **없음**.

### 0. 도달 가능한 surface 목록 (실제 확인)

인벤토리 문서(`functional_test_Q_payroll_screens.md`)는 `today_payment_screen.dart` 를
대상으로 적고 있으나 **그 파일은 존재하지 않는다**(삭제됨). Q-01 로 적힌
`payroll_worker_detail_screen` 의 `limit(500)` 도 지금은 없다 — 조회가 CF 로 옮겨졌다.
실제 도달 경로는 다섯이다.

| surface | 진입 | 진입 파라미터 |
|---|---|---|
| `PayrollOverviewScreen` | 관리자 shell 탭 3 | 사업장(picker, 1곳이면 자동) · 연도 |
| `PayrollMonthScreen` | 개요의 월 카드 | `PayrollSummaryModel`(사업장×YYYY-MM) + 건수 모름 여부 |
| `PayrollWorkerDetailScreen` | 월 상세의 근무자 행 | businessId · year · month · workerId |
| `PayrollPaymentDashboardScreen` | 개요 `지급 현황` · 홈 `이체 대기` · 알림 · 설정 · FCM | businessId · year · month · initialTab(0~3) · showAllOutstanding |
| `WageConfirmDialog` | 근태·급여 확정 경로 | (이번 감사에서 재판정하지 않음 — 기존 계약 재사용) |

대시보드 탭은 실제로 네 개다: **미이체 · 이체현황 · 변경요청 · 중간정산**
(+ 필터 전체/월급/주급/일급, 주차·일자 필터).

### 1. surface × 계약 표

| surface | source → 계산 owner → 표시 | 단위·범위 | loading/empty/partial/error/권한 | action · 복귀 refresh |
|---|---|---|---|---|
| 개요 월 그리드 | `payroll_summaries` projection(CF) → 화면이 12개월 구성 → 금액·`N명 · M건` | 금액 원 · 인원 명 · **확정+이체 건** | 로딩 skeleton · `데이터 없음` · **출근 집계 실패 → 이제 `미이체 확인 못함`** · 진입 전 `canManageWage` 확인 | 카드 탭 → 월 상세, 복귀 시 `_loadYear` |
| 개요 월 카드 `미이체 N` | **`callableGetAdminAttendances` 만**(projection 값을 덮어쓴다) | 건 | 실패 시 예전에는 0 → 줄 사라짐 → **수정** | — |
| 월 상세 헤더 금액 | projection `totalPayout` | 원 | — | `지급 현황` → 대시보드 |
| 월 상세 `이체 완료 / 미이체` | `confirmedCount − notTransferredCount`(clamp) / `notTransferredCount` | 건 | **모르면 이제 `확인 못함`** (예전엔 전부 이체된 것처럼) | — |
| 월 상세 근무자 목록 | `payroll_summaries/{id}/workers` 직접 읽기 → 정렬·검색 | 금액 원 · **확정 근무 건** | **조회 실패 ↔ 집계 없음 분리(수정)** · 검색 0건 · `확정된 급여가 없습니다` | 행 → 근무자 상세 |
| 근무자 상세 상단 | `callableGetAdminAttendances`(userId·월) → 확정·이체만 필터 | **확정 근무 건** · 총 근무시간 | `_loadError` 분리(유지) | 정산·명세 경로 |
| 대시보드 미이체/이체현황 | `PayrollPaymentService.getPayrollRecords`(월×wageStatus) | 건 · 원 | `_loadError` 로 남김(0원 위장 금지, 유지) · 요청 탭은 배지 전 미표시 | 이체 완료 처리/취소 → write-set 기준 scoped refresh(유지) |
| 대시보드 연체/당일 | `attendance.paymentDueDate` → `toKstDate` 비교 | 날짜 | — | — |
| 대시보드 계좌 줄 | **Attendance 스냅샷**(`buildTransferExportPlan`) — users 에서는 이름만 | — | — | — |

### 2. PAY-1 — 돈과 근무의 의미

**수정 3건.**

1. **출근 집계 실패를 0 으로 렌더했다.** 월별 `미확정`·`미이체` 는
   `callableGetAdminAttendances` 하나에서만 온다. 그 호출이 실패하면 12개월 전부 0 이
   되어 월 카드의 미이체 줄이 **사라지고**(줄이 없는 것과 0 은 관리자에게 같은 뜻이다),
   월 상세는 `이체 완료 = 확정 − 미이체` 를 계산해 **전부 이체된 달**이라고 말했다.
   → 실패를 `_attCountsUnknown` 으로 들고 다니며 `미이체 확인 못함` / `확인 못함` ×2 로
   말한다. 집계 문서를 실제로 받으면(`_refreshSummary`) 해제된다.
   토스트만으로는 부족했다 — 숫자가 남아 있는 화면이 사실을 말해야 한다.
2. **근무자 목록 조회 실패를 `집계 데이터가 없습니다` + 복원 버튼으로 말했다.**
   조회 실패에 **서버 재집계(쓰기)** 를 권하는 것은 원인을 틀리게 말하는 것이다.
   → `_workersLoadFailed` 를 분리하고 `근무자 목록을 불러오지 못했습니다` + `다시 시도`.
3. **`N일 근무` / `근무일수` 는 날짜가 아니라 기록 수였다.** 서버
   `srvPayrollContribution` 은 attendance **1건당 `workDays: 1`** 을 더하고, 근무자
   상세는 `_records.length` 를 그대로 `일` 로 불렀다. 한 사람이 같은 날 겹치지 않는 두
   근무를 확정받을 수 있으므로(P1-3 확정) 없는 날을 센다. 또 이 모집단은 **확정·이체된
   기록만**이라, 실제로 4일 일했는데 2건만 확정돼 있으면 `2일` 로 보였다 —
   **이것이 "실제 4일/8시간인데 2일/4시간" 으로 보고된 경험의 원인이다**(reader 는
   `allowedStatuses = {confirmed, transferred}` 로 좁힌다). 금액 owner 를 다시 계산하지
   않고 **세는 대상을 이름에 넣었다**: `확정 근무 N건`.

**판정 기록(미수정):** 같은 `notTransferredCount` 를 개요는 **출근 집계**에서,
월 상세는 새로고침 후 **projection** 에서 읽는다. 값이 어긋날 수 있어 화면에 clamp 가
들어 있다(`confirmedCount < notTransferredCount 가능`). owner 를 하나로 정하는 것은
어느 숫자를 보여줄지 바꾸는 제품 결정이고, projection 은 존재 여부 oracle 때문에 CF 로
옮긴 경로다 — **작은 패치로 고칠 문제가 아니므로 이번에 바꾸지 않았다.**
[R7-P1-5-RESIDUAL-NOTTRANSFERRED-OWNER]

주휴수당·세금·과거 snapshot 정책은 이번 감사에서 새로 정하지 않았다.

### 3. PAY-2 — 처리 상태와 행동

**수정 2건.**

1. **낡은 in-flight 결과가 현재 월 아래에 앉았다.** `_load()` 에는 직렬화 가드가
   있다(`_fetchInProgress` + `_pendingReload`) — **첫 판단을 정정한다.** 문제는 다른
   곳이었다: 월을 바꾸면 이미 떠 있는 요청은 **이전 달** 것인데 그 결과를 그대로
   `_allRecords` 에 앉히고 `_isLoading = false` 로 내렸다. 그래서 새 요청이 끝나기
   전까지 **다른 달 기록이 현재 달 제목 아래에 로딩이 끝난 모습으로** 보였다.
   → 밀려 있는 로드가 있으면 적용하지 않고 로딩을 유지한다(`finally` 가 최신 범위로
   다시 읽는다). 선택은 어차피 적용 시점에 비워지므로 금전 action 위험은 낮았지만,
   표시가 사실과 달랐다.
2. **지급 예정일이 기기 시간대에 좌우됐다.** `PaymentDueDateCalculator` 의 기준값은
   `toKstDate` 가 만든 UTC 플래그 달력일인데 **월별 분기만** `DateTime(...)` 로 기기
   local 날짜를 만들었다(그래서 D2-07·08 은 통과하고 나머지는 실패했다). 서버
   `srvCalculatePaymentDueDate` 는 UTC 런타임에서 `new Date(y,m,d)` → `00:00Z` 를
   쓰므로, 한국 기기에서 두 값이 **9시간** 어긋났고 다른 시간대에서는 **하루**가
   밀린다. → 계산기 전부 `DateTime.utc`. 지금 `calculate()` 의 production caller 는
   없다(서버가 writer이고 화면은 `label` 만 쓴다) — **사용자에게 보이는 변화는 없고**,
   서버와 같은 모양으로 맞춰 다음 caller 가 같은 함정을 다시 밟지 않게 한 것이다.
   저장 shape 자체(`00:00Z` vs KST 자정)는 소비자가 모두 KST 달력일로 정규화하므로
   (`isDueToday`·`isDueOnOrBefore`·`_earliestDue`·CF 연체 비교) **바꾸지 않았다.**

**NO PATCH (재사용):**
- 이체 처리/취소가 **앱 내부 기록**이라는 계약이 문구에 있다 —
  `실제 은행 이체를 완료한 건만 처리해 주세요.` / `실제 은행 이체는 취소되지 않습니다`.
  실제 송금으로 오인시키는 문구는 없다(`송금` 은 코드 주석에만 있다).
- 서버 write-set 기준 scoped refresh, 멱등(`이미 이체된 건을 processed 로 세지 않는다`),
  `화면이 새로 처리한 건수만 성공으로 말한다`, NO_SHOW·결근 0원 skip —
  `payroll_mutation_scoped_refresh_contract_test` · `transfer_money_state_contract_test`
  가 이미 고정한다. 이번 화면에서 그 계약을 우회하는 새 경로는 찾지 못했다.
- 연체·당일 판정은 저장값과 화면이 **같은 정규화**(`toKstDate`)를 쓴다.

미이체 / 이체현황 / 변경요청 / 중간정산 네 라벨은 실제 상태·대상과 일치하며
전역 rename 은 하지 않았다.

### 4. PAY-3 — 권한·문서·개인정보 (NO PATCH, 재사용)

- 진입: `checkCurrentBusiness(canManageWage)`, **확인된 허용에서만** 조회하고
  `error/unknown` 을 `denied` 로 바꾸지 않는다.
- 취소: `canManageWage && canCancelTransfer`, 다이얼로그를 띄운 사이 권한이 회수됐을
  수 있어 **전송 직전 재검증**, 확인 못한 상태는 거부. 서버도 두 권한을 차례로 본다.
- 개인정보: 카드의 계좌 줄은 **Attendance 스냅샷**을 읽는다(`buildTransferExportPlan`).
  users 문서에서 가져오는 것은 **이름뿐**이다 — 화면이 보여주는 계좌와 실제로 돈이
  가는 계좌가 달라질 수 있던 문제는 이미 닫혀 있다. 현재 이름과 확정 당시 예금주
  snapshot 을 덮어쓰지 않는다.
- 테스트·로그에 실제 계좌·식별번호를 쓰지 않았다(fixture 는 `u1`·`김근로` 수준).

새로운 우회는 발견하지 못했다 — 목록·건수·직접 읽기 모두 기존 종료 근거가 유효하다.

### 5. PAY-4 — 제품 화면과 반응형 (수정 3건)

실제 위젯을 그려 보니 **두 곳이 잘리고 있었다.** 둘 다 이번 문구 추가와 무관하게
기존 콘텐츠에서 먼저 터지고, 새 문구가 폭을 더 먹어 커졌다.

1. **월 카드 높이가 100dp 고정**이었다. 기기 폭과 무관한 것은 맞지만 **OS 글자 배율을
   반영하지 않아** 기본 배율에서 1px, 1.3 배에서 20px 이 아래로 잘렸다.
   → 네 줄의 base font 합이 배율을 받는 만큼(줄 높이 ≈1.25배) 높이를 늘렸다.
   **글자 축소·배율 무효화·FittedBox 로 덮지 않았다.**
2. **월 상세 1행(총 지급액 + 지급 현황 버튼)** 에 flex 가 없어 7자리 금액과 함께
   가로 18px 이 넘쳤다 → 금액 묶음을 `Expanded` 로, 모자라면 **라벨부터** 줄인다.
3. **월 상세 2행(이체 완료 · 미이체 · 인원/건수)** 이 flex 없는 Row + `Spacer` 여서
   값이 길어지면 오른쪽 칩이 잘렸다 → 프로젝트 규칙대로 `Wrap`(줄바꿈 허용),
   세로 구분선은 제거(줄바꿈되면 선이 줄 앞에 남는다).

radius 16 · `AppPageScaffold` · 색·타이포 체계는 그대로다. 새 색 체계·대시보드 재설계·
컴포넌트 채택률 목표는 만들지 않았다. 대비·터치 영역 수치는 **P4**, 전 기기 확인은 DEVICE.

### 6. 이번에 실행한 증거

**RENDER·행동 (production 위젯 + 주입 경계)** — `payroll_overview_unknown_render_test` 6건:

| 증거 | 확인 |
|---|---|
| POV-1 | 정상 → `미이체 3` 표시 |
| POV-2 | 출근 집계 실패 → 금액(4,800,000)은 남고 `미이체 확인 못함`, `미이체 0` 없음 |
| POV-3 | 월 상세 진입 → `이체 완료`/`미이체` 둘 다 `확인 못함`, 파생 `5건` 미주장 |
| POV-4 | 근무자 조회 실패 → `근무자 목록을 불러오지 못했습니다` + `다시 시도`, `집계 데이터 복원` **없음** |
| POV-5 | 근무자 행 `확정 근무 2건`, `2일 근무` 없음 |
| POV-6 | 320dp·배율 1.3 + 128,400,000원 → 예외 0 |

**CODE (소스 배선)** — `payroll_unknown_and_scope_contract_test` 16건:
모름 분기 순서(U-1~U-4) · 서버 `workDays: 1` 과 화면 단위 일치(U-5~U-7) ·
낡은 결과 미적용과 직렬화 유지(S-1) · 연체 정규화(S-2) · 계산기 UTC 와 서버 정책 일치
(D-1·D-2) · 반응형 우회 금지(R-1·R-2) · 권한·문구 계약 유지(P-1~P-3).

**읽기 경계 신설:** `lib/screens/business_admin/payroll/payroll_overview_reads.dart`
— 원시 외부 읽기 6개만(사업장·집계 projection·출근 집계·근무자 집계·집계 복원·오늘 건수).
합계 구성·판정·문구는 화면에 남는다. 화면에서 Firestore 직접 접근은 **0** 이 됐다.

**DEV READ:** 없음. **DEVICE/PRODUCT:** 아래 최소안.

### 7. 회귀

같은 SHA·같은 환경·이름별. **영향 세트 전부 초록:**
- 급여·이체·임금·지급예정일·홈 급여 행: **746 PASS**
- 변경 파일을 참조하는 나머지 테스트(권한·부분실패·신원·CF 마이그레이션 등): **308 PASS**
- 새 렌더 6 + 새 계약 16
- `flutter analyze lib test`: No issues

**되살린 기존 실패 23건:** `unit/payment_due_date_calculator_test` 17건 +
`payroll_simulation_extended` D2 6건은 계속 빨간색이었다. 원인은 둘이었다 —
기대값이 local `DateTime` 이라 **같은 날짜인데도** 실패(UTC 플래그), 그리고 `weekly`
같은 요일 정책을 **반대로** 기대(서버 `[CF-MED-4-FIX]` 는 +7). 규약을 표현하도록
기대값을 고쳤고, 월별 분기의 local 생성은 제품 쪽에서 고쳤다.
전체 suite 총 실패 수만으로 완료를 선언하지 않는다 — 위 두 세트가 이번 판정의 범위다.

### 8. 종료 자료

| ID | 이전 → 현재 | 수정/NO PATCH/이관 | source · owner | 재사용 근거 | 이번 CODE/실행/RENDER/DEV READ | DEVICE 조건 |
|---|---|---|---|---|---|---|
| PAY-1 출근 집계 실패 | 0·줄 사라짐 → **모름 표시** | 수정 | `callableGetAdminAttendances` · 개요 화면 | — | CODE U-1·U-2, RENDER POV-2 | 실제 CF 실패 재현 |
| PAY-1 월 상세 파생 | `이체 완료 = 확정−미이체` → 모르면 미주장 | 수정 | 화면 계산 | — | CODE U-3, RENDER POV-3 | 같음 |
| PAY-1 근무자 조회 실패 | `집계 없음`+복원 → **재시도** | 수정 | `workers` 서브컬렉션 | 존재 oracle(O-3x) | CODE U-4, RENDER POV-4 | 권한 거부 계정 |
| PAY-1 근무일 단위·모집단 | `N일`·`근무일수` → `확정 근무 N건` | 수정 | 서버 `srvPayrollContribution` · 상세 `allowedStatuses` | P1-3 관계 건수 | CODE U-5~U-7, RENDER POV-5 | 같은 날 2건 표본 |
| PAY-1 notTransferred owner | 경로마다 다름 | **이관**(RESIDUAL) | 출근 집계 ↔ projection | clamp 주석 | 기록만 | 제품 결정 필요 |
| PAY-2 낡은 결과 적용 | 다른 달이 현재 달로 → 미적용 | 수정 | 대시보드 `_load` | R8 scoped refresh | CODE S-1 | 느린 망에서 월 연타 |
| PAY-2 지급 예정일 | 월별만 local → 전부 UTC | 수정 | `PaymentDueDateCalculator` / 서버 writer | CF `srvCalculatePaymentDueDate` | CODE D-1·D-2 + 23건 복구 | 비KST 기기 |
| PAY-2 이체 문구·write-set·멱등 | — | NO PATCH | 서버 + 대시보드 | transfer_money_state · scoped_refresh | CODE P-1 | 실제 처리 = DEVICE |
| PAY-3 권한·스냅샷·PII | — | NO PATCH | provider + Attendance 스냅샷 | bankbook·export truth | CODE P-2·P-3 | 권한 회수 시나리오 |
| PAY-4 카드 높이 배율 | 1px·20px 잘림 → 배율 반영 | 수정 | 개요 그리드 | — | RENDER POV-1·POV-6 | 배율 2.0 실기기 |
| PAY-4 1행·2행 가로 넘침 | 18px·13px → Expanded·Wrap | 수정 | 월 상세 헤더 | 프로젝트 Row 규칙 | CODE R-2, RENDER POV-3 | 긴 사업장명 실기기 |
| 대비·터치 영역 | — | **P4 유지** | — | — | **미측정** | P4 |

#### 최소 DEVICE/조작안 (변경 화면만)

1. 급여 탭 진입 → 월 그리드에서 **글자 크게(1.3·2.0)** 설정으로 카드 아래가 잘리지 않는지.
2. 비행기 모드 등으로 출근 집계만 실패시켜 월 카드가 `미이체 확인 못함` 이 되는지,
   그 달을 열었을 때 `이체 완료`·`미이체` 가 둘 다 `확인 못함` 인지.
3. 월 상세에서 7자리 이상 금액 + 긴 사업장명으로 1행·2행이 잘리지 않는지(줄바꿈 허용).
4. 근무자 상세 상단이 `확정 근무 N건` 이고, 확정되지 않은 근무는 포함되지 않는다는 것이
   그 라벨로 읽히는지.
5. 대시보드에서 느린 망으로 월을 연타했을 때 **다른 달 기록이 현재 달로 보이지 않는지**.
6. (권한) 급여 권한 없는 SubAdmin 진입 차단, 이체 취소 권한만 회수했을 때 취소 거부.

**PRODUCT 판단 대기:** `[R7-P1-5-RESIDUAL-NOTTRANSFERRED-OWNER]` — 미이체 건수의
owner 를 출근 집계와 projection 중 하나로 정할지.

---

## R7-P1-5 후속 — 미이체 건수의 owner (2026-09-28)

기준 `ba9305e`(직전 `ebcd16a`). branch `main`, 시작 시 tracked 변경 0, 사용자 소유
untracked 8건 보존. 고정 ID **하나**: `[R7-P1-5-RESIDUAL-NOTTRANSFERRED-OWNER]`.
P1-5 의 다른 판정(PAY-1 실패≠0·확정 근무 N건, PAY-2 월 응답 순서·지급 예정일,
PAY-3 권한/문서, PAY-4 clipping)은 재조사하지 않았고 그 증거를 그대로 재사용한다.
Staffing 보정 **DEFERRED**, O08 **PENDING**. 공유 DEV 쓰기·CF 배포·Rules·PROD·APK·
실제 은행 이체 **없음**.

### 1. 원장 → 두(세) 계산 → 실제 소비자

| 경로 | 원장/문서·identity | 날짜/월 기준(KST) | 포함/제외 상태 및 중복 단위 | 계산 owner/캐시 | 사용 화면·라벨 | 행동 gate? | 실패/부분/권한 |
|---|---|---|---|---|---|---|---|
| **A 출근 집계 CF** `callableGetAdminAttendances(yearMonthGte/Lte)` | `attendance` 문서 · `businessId` | 저장된 `yearMonth` 필드 = `formatYearMonthISO(workDate)`(KST) — 서버 `srvWorkDateParts` 와 **같은 식** | `wageStatus=='confirmed'` 만 미이체, `transferred` 는 별도 칸, `pending/calculated` 는 미확정, `isNonPayableZeroOf`(노쇼·결근 0원) 제외 · 단위 **attendance 문서 수**(같은 사람의 여러 근무는 각각 1) | 화면이 월별 합산(캐시 없음, `_loadYear`·`_refreshSummary` 마다) | 개요 월 카드 `미이체 N` · 월 상세 `미이체`/`이체 완료`(파생) | **아니오** | 실패→모름, **10,000건 `limitReached`**(이번에 반영), 권한은 CF 가 검증 |
| **B payroll projection** `payroll_summaries.notTransferredCount` | 같은 attendance 에서 트리거가 delta 누적 | `srvWorkDateParts(workDate).yearMonth` | `srvPayrollContribution`: confirmed→notTransferred 1, transferred→0, `srvIsNonPayableZero` 제외 · **단위 동일** | `onAttendanceWageChanged` 트랜잭션 + `_processedWageEvents` 멱등, 누락 시 복구 CF | (이전) 월 상세 **새로고침 후** 같은 자리 → **이번에 제거** | 아니오 | 트리거 지연·누락 시 낡음. 존재 여부는 CF oracle |
| **C 전용 count callable** `callableGetNotTransferredCount` | attendance · businessId | **월 필터 없음 = 전 기간** | confirmed + `srvPayableForTransfer` · 단위 문서 수 | 서버 즉시 계산 | **소비자 0** — Dart 래퍼 `getTotalNotTransferredCount` 는 호출부가 없었다(홈 배지는 canonical summary 의 `unpaidWage` 로 옮겨간 뒤) → **래퍼 제거** | 아니오 | `srvAssertWageAuthority` |

`notTransferredCount` 를 읽는 활성 consumer는 **개요 화면 두 자리뿐**이다(월 카드 줄,
월 상세 상태 줄). 대시보드·홈·근로자 상세는 이 필드를 참조하지 않는다(OWN-7).
`PayrollSummaryModel.isEmpty` 가 이 값을 쓰지만 그것은 월 카드 탭 가능 여부이고,
금전 mutation gate 가 아니다.

### 2. 판정 — 같은 계약, 두 계산 (A·B) / 정당한 다른 계약 (C)

A 와 B 는 **모집단·기간·단위가 모두 같다**: 같은 KST 월의 attendance 문서 중
`wageStatus=='confirmed'` 이고 노쇼·결근 0원이 아닌 것의 **개수**. 술어를 직접 대조했고
월 기준 함수도 양쪽이 같은 규칙이다. 그러므로 **두 계산이 존재할 이유가 없다** —
갈리는 원인은 정의가 아니라 **트리거의 지연·누락**이다.
C 는 `월 필터 없음`이라 **다른 계약**(전 기간 합계)이고, 같은 단어로 다른 수를 보여줄
위험만 남아 있었다 — 소비자가 0 이어서 **경로를 없애는 것이 맞다**.

### 3. 가장 작은 차이 사례 (원장 → 계산 → UI, before/after)

**사례 1 — 이체 취소 후 복귀** (동일 사업장·월·같은 근로자)

| | 원장(A) | 집계 문서(B, 트리거 지연) | 화면 before | 화면 after |
|---|---|---|---|---|
| 미이체 | `confirmed` 2건 | `notTransferredCount: 1` | 개요 `미이체 2` → 상세 진입 `2건` → **지급 현황 왕복 후 `1건`** (확정 사실로) | 왕복 후에도 **`2건`** |

`_refreshSummary` 가 집계 문서만 다시 읽어 건수까지 그 값으로 덮었기 때문이다.
P1-5 에서 모름 해제 로직이 들어간 뒤로는 그 낡은 값이 `확인 못함` 도 아닌 **확정된
사실**로 보였다. 실행 증거 **PNT-1**: 복귀 시 집계 문서와 **원장 둘 다** 다시 읽는 것을
호출 수로 증명하고(`summaries`·`ledger` 각각 증가) 표시가 `2건` 으로 남는 것을 단언한다.
**before 재현**: 복귀 갱신을 집계 문서 값으로 되돌리면 PNT-1 이 `1건` 을 찾아 실패한다
(확인 후 원복).

**사례 2 — 파생 `이체 완료`가 두 owner 를 섞는다**

| | 원장(A) | 집계 문서(B, 낡음) | 화면 before | 화면 after |
|---|---|---|---|---|
| 확정 건수 | 2 (confirmed 1 + transferred 1) | `confirmedCount: 5` | `이체 완료 = 5 - 1 = 4건` | `이체 완료 = 2 - 1 = 1건` |

네 상태(pending/calculated/confirmed/transferred) + 같은 사람 복수 근무 + 노쇼 0원 1건의
fixture 로 실행했다(**PNT-2**). 원장을 쓸 수 있으면 확정 건수도 원장에서 가져와
파생이 **한 owner 안에서 정확히** 이체완료 건수가 되게 했다 — 새 필드·새 지표 없음.

**사례 3 — 상한(10,000건)**: A 는 `limitReached` 를 함께 주는데 개요는 읽지 않아
**실제보다 작은 합계를 사실처럼** 보여줄 수 있었다(통계 서비스는 같은 신호를
fail-closed 로 쓴다). 이제 상한 도달은 실패와 같은 **모름**이다(**PNT-3**).

**사례 4 — 집계 문서도 없고 원장도 실패**한 달이 `데이터 없음`(= 근무 없음)으로
보였다 → `확인 못함`(**PNT-4**).

### 4. 행동 영향 판정 (별도)

- **화면 영향:** 있었다 — 위 네 사례.
- **잘못된 지급 판단 가능성:** **없다.** 이 값은 표시 전용이다. 이체/취소/전체선택은
  대시보드가 자기 원장 목록(`_allRecords`)에서 만들고, 대상은 attendance id 로 서버가
  다시 검증한다. 대시보드 소스에 `notTransferredCount` 는 **0회** 등장한다(OWN-7).
- **저장값 문제:** **없다.** 원장(attendance)은 손상되지 않았고 트리거의 delta 도
  멱등이다. 갈림은 **읽는 쪽의 두 계산** 때문이며, 증거 없이 심각도를 올리지 않는다.

### 5. 최종 owner와 제거한 구 경로

**owner = 원장(attendance)** — 미이체·미확정·이체완료·(파생의 분모인) 확정 건수.
집계 문서는 **금액·인원의 owner** 로 남는다(트랜잭션 delta + 복구 CF, 개요가 그 값을
그대로 표시). 원장을 못 읽으면(실패·상한) 건수는 **모름**이고 금액·인원은 문서 값을 쓴다.

- 계산을 **한 곳**으로: `_LedgerMonthCounts`(공유 reading) — 로더와 복귀 갱신이 같이 쓴다.
  화면에서 월별 판정 루프 중복 0(OWN-1).
- 제거: `PayrollPaymentService.getTotalNotTransferredCount`(전 기간 세 번째 정의,
  호출부 0). 서버 `callableGetNotTransferredCount` 는 **배포 범위라 남겨 두고** 사용 0을
  기록한다 — 삭제는 CF 배포가 필요하다.
- `?? 0` 폴백·목록 길이 대체·과거 snapshot 재사용은 쓰지 않았다.

### 6. 증거와 회귀

| 구분 | 내용 |
|---|---|
| **행동 실행·RENDER** | `payroll_overview_unknown_render_test` **10건**(POV-1~6 재사용 + PNT-1~4). 경계 주입 + production 위젯, `tester.view` 390×900 / 320×900(배율 1.3) |
| **CODE** | `payroll_unknown_and_scope_contract_test` **23건**(기존 16 + OWN-1~7) |
| **before/after** | PNT-1 을 수정 전 상태로 되돌려 실패 확인 후 원복 |
| **회귀(같은 SHA·같은 환경, 이름별)** | 급여·이체·임금·지급예정일·모집단·시뮬레이션 **848 PASS** / 변경 파일을 참조하는 나머지 **251 PASS** / `active_reader` 10 PASS / `flutter analyze lib test` No issues |
| **DEV READ** | 없음 |
| **미검증** | 복귀 갱신의 **실기기 왕복**(테스트에서는 권한 gate 가 스스로 닫는 경로로 왕복했다) · 배율 2.0 · 대비·터치(P4) |

전체 suite 총 실패 수는 이번 판정에 쓰지 않았다(범위가 다르다).

### 7. 종료 판단

| 항목 | 실제 결론 |
|---|---|
| 두 계산의 모집단·기간·단위 | **A·B 는 같은 계약**(같은 KST 월·confirmed·0원 제외·문서 수) → 두 계산이 존재할 이유 없음. C 는 **정당한 다른 계약**(전 기간)이나 소비자 0 |
| 영향을 받는 활성 consumer·action | `payroll_overview_screen.dart` 두 자리(월 카드 줄 `_buildMonthCard`, 월 상세 상태 줄 `_buildSummaryHeader`). **action gate 없음** — 대시보드는 자기 원장 목록을 쓴다 |
| 최종 owner 및 제거한 구 경로 | **수정** — owner = 원장, 공유 reading `_LedgerMonthCounts`, 복귀 갱신도 원장 사용. 제거: 전 기간 count 의 Dart 래퍼(서버 함수는 배포 범위로 유지, 사용 0) |
| 가장 작은 차이 사례 | 이체 취소 후 복귀(2→1로 덮임) · 낡은 확정 건수가 파생에 섞임(이체완료 4→1) · 상한 도달 · 문서+원장 모두 실패 |
| CODE·행동 실행·RENDER·DEV READ·DEVICE | CODE 23 · 행동/RENDER 10 · DEV READ 0 · DEVICE = 실기기 왕복·배율 2.0 |
| P1-5 잔여 | **PRODUCT 보류 해제됨**(이 항목 종료). DEVICE 최소안은 아래. P4 대비·터치는 **미측정** 유지 |

#### 최소 캡처·조작안 (이번에 실제로 바뀐 자리만, 기존 검증과 겹치지 않게)

1. 지급 현황에서 **이체를 하나 취소**하고 뒤로 → 월 상세의 `미이체` 가 **늘어난 값**으로
   남는지(집계 문서가 아직 반영되지 않았을 때도).
2. 같은 달에 **확정 1 · 이체완료 1** 이 섞여 있을 때 `이체 완료` 건수가 1 인지
   (5 같은 큰 수가 아닌지).
3. 집계 문서가 없는 과거 달에서 `데이터 없음` 과 `확인 못함` 이 구분되는지.

오류·상한·권한 회수는 **테스트에서 주입해 이미 확인했다** — 실기기에서 망 장애를
만들어 달라고 요청하지 않는다. 월 응답 역전·처리 성공은 정적 캡처로 증명하지 않는다.

---

## R7-P1-6 — 관리자 계약·관리·통계 (2026-09-28)

기준 `49ca49e`(직전 `ba9305e`) — 요청서 SHA 와 **실제 HEAD 일치**. branch `main`,
시작 시 tracked 변경 0, 사용자 소유 untracked 8건 보존. 인벤토리를 새로 만들지 않고
현행 HEAD 의 도달 경로로 확인했다. P1-2/P1-3/P1-4/P1-5 의 종료 증거와 계약서 서명 흐름·
문서 승인·R5 권한 검증은 재사용했고 다시 감사하지 않았다. P1-5 PRODUCT/DEVICE·
Staffing O08 대기, 11TO/21업무 보정 **DEFERRED**. 공유 DEV 쓰기·CF 배포·Rules·PROD·
APK **없음**.

### 0. 먼저 정정한 두 가지 (이전 보고의 후보 수치)

1. **관리자 트리에 남은 `GradientScaffold` 는 이미 0 이었다.** 이전 보고가 후보로 적은
   `admin_stats`·`admin_month_detail`·`business_detail`·`member_management`·
   `payroll_overview`·`payroll_worker_detail` 여섯은 **주석에만** 이름이 남아 있고
   실제 호출은 없다(`GradientScaffold(` 0건). 실제 대상은 역할을 공유하는
   `common/settings_screen` **하나**였다.
2. **`settings_screen` 에 USER 진입 경로가 있다.** 이전 메모는 "USER 진입 없음 →
   shell 교체에 역할 공유 제약 없음"이라고 적었는데 현행 HEAD 에서는 사실이 아니다 —
   `role == USER` 이면 `showUserItems` 로 '설정' 을 보고, `contract_sign_screen`·
   `job_posting_screen`·`notification_screen` 이 그 화면을 연다. SubAdmin 은 모드
   전환으로 양쪽에서 쓴다. 그래서 shell 을 통째로 바꾸면 **지원자 공통 레이아웃까지**
   바뀐다. 지원자 쪽은 **P2 소유**이므로 건드리지 않았다.
   super_admin 의 **11** 이라는 수치는 HEAD 에서도 성립한다(12개 중 home 만 예외).

### 1. 실제 도달 화면 × 계약 표

| 화면 | 진입/역할 | source·계산 owner | 상태·단위·기간 | loading/empty/error/partial/권한 | action·서버 guard | shell/D0 |
|---|---|---|---|---|---|---|
| `settings_screen`(관리/설정) | shell 탭4(ADMIN·SubAdmin admin) · super_admin_home(SUPER) · contract_sign·job_posting·notification(USER) | provider(역할·권한) + 각 메뉴 목적지 | — | 메뉴는 권한별 분기, 탈퇴 사전 점검은 차단/경고/가능 3분기 | 목적지별 기존 guard(재사용) | **수정** — 관리자 역할만 `AppPageScaffold` |
| `admin_contract_management` | 홈 `계약 미발송` · 공고/인력 · 관리 탭 | `contractsPaged`(상태 필터) + `unsentApplications` | 5탭: 전체/미발송/근무자 대기/완료/무효 · 건 | 권한 회수 = `접근 권한이 없습니다`(유지) · **실패 = 이번에 분리** | 계약 생성/발송/서명 — 기존 CF guard | 이미 flat |
| `admin_stats_screen` | 관리 탭 → 분석 | `AdminStatsService`(엄격 envelope) | 총 인건비(원) · 근무 건수(건) · 출근율·노쇼율(%) · 연/월 | 실패 → `확인 불가`/`조회 실패`, `limitReached` fail-closed | 월 카드 → 월 상세(범위 동반) | 이미 flat |
| `admin_month_detail` | 통계 월 카드 | 같은 서비스 | 근무일(**고유 날짜**) · 정상/지각/결근(건, 단위어 없음) · 임금(원) | `다시 시도` 있음 | 근무자 행 → 상세 | 이미 flat |
| super_admin 11화면 | `settings_screen`(SUPER) · `super_admin_home` · `system_settings` | 각 화면 자체 | 설정값·목록 | 각 화면 유지 | 각 화면 유지 | **6 수정 / 5 이관** |
| `user_my_tab` | USER MY | — | — | — | — | **P2** (이번 대상 아님) |

`today_payment_screen` 은 존재하지 않는다(P1-5 에서 확인) — 패치 대상에서 제외.

### 2. P16-C — 계약·문서의 진실 → **수정**

**확인된 결함:** 두 로더(`_load`·`_loadUnsentContracts`)가 실패를 **토스트 한 번**으로
흘리고 목록을 빈 채로 뒀다. 그래서 미발송 탭이

> ✅ `미발송 계약서 없음` / "확정된 모든 지원자에게 계약서를 …"

로 그려졌다 — **조회가 실패했을 뿐인데 해야 할 일을 완료 이력처럼** 말한 것이다
(체크 아이콘까지 붙는다). 계약서 목록 탭도 같은 모양으로 `계약서가 없습니다` 였다.
`_load` 는 fetch 전에 `_items = []` 를 먼저 세팅하므로 실패가 곧 "없음"이 된다.

→ `_listLoadFailed`/`_unsentLoadFailed` 를 상태로 들고, 빈 상태에서 **실패 분기를
먼저** 가른다: `미발송 계약서를 확인하지 못했습니다` / `계약서 목록을 불러오지
못했습니다` + `다시 시도`. 권한 회수(`접근 권한이 없습니다`)는 기존 계약 그대로다.

**경계 신설:** `admin_contract_reads.dart`(원시 읽기 **2개**) — 실패/정상을 골라 넣어
production 화면을 그릴 수 있게 했다. 경계가 숨은 요구도 드러냈다: 화면이 읽어 온 목록을
**제자리에서 정렬**(`..sort`)하고 있었다 → 불변 목록을 돌려주면 던진다. 복사본을 정렬한다.

**NO PATCH (재사용):** 서명 단계(pending_employer → pending_worker → completed)와 탭
분류, 종료 관계 제외(`CONTRACT_ENDED_STATUSES`), 문서 버전·권한·민감정보, 계약 생성/발송
CF guard 는 기존 종료 증거를 연결한다. 법률상 사후 계약 정비 정책은 **OPEN 유지** —
자동 과거 계약을 만들지 않았다.

### 3. P16-M / P16-A — 관리자 화면 틀

**P16-M 수정.** `settings_screen` 은 역할이 공유하므로 **관리자 역할만**
`AppPageScaffold`(D0 flat admin)로 바꿨다(`showAdminSection || SUPER_ADMIN`).
USER·SubAdmin(사용자 모드)는 `GradientScaffold` 그대로다. 프로필 블록은 흰 글자로
그려져 있어 grey100 위에 그대로 내리면 보이지 않으므로 **brand 색 카드(radius 16)**
안에 담아 대비를 유지했다 — 내용·문구·정보량은 그대로다.
하드코딩 색 **6종 7곳**(amber/green 계열)을 `AppColors.warningDark/warningBg/
successBg/successLight/success/successDark` 로 바꿨다. 바로 위 hardBlocks 는 이미
`error/errorBg` 를 쓰고 있었으므로 같은 계약 안으로 들어온 것이다.

**P16-A: 11화면을 기계적으로 바꾸지 않았다.** 축으로 분류했다(전부 `headerContent` 미사용):

| 분류 | 화면 | 근거 | 조치 |
|---|---|---|---|
| 순수 shell 교체 | `system_settings` · `business_approval_settings` · `insurance_rate_settings` · `minimum_wage_settings` · `legal_terms_management` · `badge_settings` | headerContent 0 · 헤더 TabBar 없음 · 가로 표 없음 · `title`/`body`/`actions`/`floatingActionButton` 인자명 동일 | **6 전환** |
| 헤더 TabBar | `help_faq_management` · `review_tags_settings` · `to_limit_settings` | `labelColor: Colors.white` — 그라디언트 위 흰 라벨이라 flat app bar 에서 **보이지 않는다**. 라벨 색까지 함께 고쳐야 한다 | **이관**(owner P16-A, 남은 조건: 탭 라벨 색 + 렌더 증거) |
| 넓은 표·관리 도구 | `all_businesses` · `all_users` | `Axis.horizontal` 가로 스크롤 표 + 입력 | **이관**(owner P16-A, 남은 조건: 표 레이아웃 위험 확인) |

`direct AlertDialog/showModalBottomSheet` 는 이번에 잘림·safe-area·닫기 결함을 확인한
호출이 없어 **사용 자체를 결함으로 분류하지 않았다**(NO PATCH).
`bool can()` collapse 는 기존 종료 근거를 확인했고 새 bypass 를 찾지 못했다 — 권한 설계를
새로 열지 않았다.

**이 단계로 앱 전체 관리자 디자인이 끝난 것이 아니다**: super_admin 5화면 이관,
`document_management_screen` 하드코딩 색 10곳(P1-7), `AppSummaryHeader`/`AppStatusCard`
채택 0(P1-7), radius 혼재(POLISH)가 남아 있다.

### 4. P16-S — 통계의 분자·분모 → **NO PATCH (근거 제출)**

| 지표 | 이름/단위 | 모집단 | source·owner | freshness | 목적지 |
|---|---|---|---|---|---|
| 총 인건비 | 원 | 선택 연/월 · 사업장(필터) | `AdminStatsService` | 실패 시 `확인 불가` | — |
| 근무 건수 | **건** | 같은 범위의 attendance | 같음 | 같음 | — |
| 출근율·노쇼율 | % | 같음 | 같음 | 같음 | — |
| 월별 인건비(막대) | 원 | 12개월 | 같음 | 실패 월은 `조회 실패` | 월 카드 → 월 상세 |
| 근무일 | **일 = 고유 날짜 수** | 근로자×월 | `WorkerMonthSummary.totalDays` = `workDate` 집합 크기 | — | 근무자 행 |
| 정상/지각/결근 | **건**(단위어 없음) | 같음 | 같음 | — | — |
| 임금 | 원 | 확정 기준 · 미확정은 `미확정` | 같음 | — | — |

- 실패·부분·상한을 0/데이터 없음으로 숨기지 않는다 — `확인 불가`·`조회 실패`,
  서비스가 `limitReached` 를 **fail-closed(UNAVAILABLE)** 로 읽는다.
- 숫자를 누르면 `businessIds`·`filterBusinessId`·`year`·`month` 가 함께 간다 →
  대상 목록의 범위가 현재 선택과 일치한다.
- **근무일은 고유 날짜**로 세고(P1-5 에서 고친 것과 같은 함정을 이미 피하고 있다),
  건 단위 지표에는 `일` 을 붙이지 않는다.
- **기록만:** 필드 이름이 `presentDays/lateDays/absentDays` 인데 값은 **건**이다
  (주석이 그렇게 말한다). 표시에는 단위어가 없어 사용자에게 보이는 결함은 없다 —
  다음 소비자가 `일` 로 읽을 위험만 남는다. 이름 변경은 이번 범위 밖으로 기록한다.
  `[R7-P1-6-RESIDUAL-DAYS-FIELD-NAMING]`

### 5. 이번에 실행한 증거

**RENDER·행동** `admin_shell_flat_render_test` **10건** (production 위젯, `tester.view`):

| 증거 | 확인 |
|---|---|
| ASF-1 | BUSINESS_ADMIN → `AppPageScaffold`, Gradient 0, '관리', 프로필 유지 |
| ASF-2 | USER → `GradientScaffold` 유지, `AppPageScaffold` 0, '설정' |
| ASF-3 | SubAdmin 모드 전환에 따라 두 shell 을 오간다 |
| ASF-4 | 320dp·배율 1.3 — 프로필 카드 + 목록, 스크롤 가능, 예외 0 |
| ASF-5 | super-admin `시스템 설정` → flat shell (**shell 범위**) |
| ASF-6 | 같은 화면 320dp·**배율 2.0** 예외 0 |
| ACM-1 | 계약 목록 실패 → `불러오지 못했습니다` + 재시도, `계약서가 없습니다` **없음** |
| ACM-2 | 미발송 실패 → `확인하지 못했습니다`, `미발송 계약서 없음`·체크 아이콘 **없음** |
| ACM-3 | 320dp·배율 1.3 에서 실패 상태·재시도 접근 가능 |
| ACM-4 | **정상 0건**은 `미발송 계약서 없음` — 실패와 다른 문구 |

**CODE** `admin_p16_shell_and_truth_contract_test` **16건**: 역할 경계(M-1~3) ·
super_admin 전환/이관 근거(A-1~4) · 계약 실패 분기·경계·비파괴 정렬(C-1~5) ·
통계 단위·모집단·목적지 범위(S-1~4).

**DEV READ** 없음. **Emulator** 사용 없음(상태 변경 검증이 필요한 수정이 없었다).

### 6. 회귀 (같은 SHA·같은 환경·이름별)

- 변경 파일을 참조하는 테스트 13파일 **367 PASS**
- 시뮬레이션 2파일 **957 PASS**
- 새 렌더 10 + 새 계약 16
- `flutter analyze lib test` **No issues**

전체 suite 총 실패 수로 완료를 주장하지 않는다.

### 7. 종료 판단

| ID | 이전 → 현재 | 실제 진입 화면 | 수정/NO PATCH/이관 | 기존/이번 증거 | CODE/행동/RENDER/DEV READ/DEVICE | 남은 조건 |
|---|---|---|---|---|---|---|
| **P16-C** | 실패가 "없음/완료" → 분리 | `admin_contract_management`(홈·공고·관리 진입) | **수정** + 경계 신설 | 서명 흐름·문서 권한(기존) / ACM-1~4·C-1~5 | CODE 5 · RENDER 4 · DEV READ 0 | 실기기 실패 유도 불필요(주입으로 확인) · 법률 사후 정비 **OPEN** |
| **P16-M** | 파란 구형 shell + 하드코딩 색 | `settings_screen`(역할 공유) | **수정**(관리자 역할만) | — / ASF-1~4·M-1~3 | CODE 3 · RENDER 4 | 지원자 경로는 **P2** |
| **P16-S** | — | `admin_stats`·`admin_month_detail` | **NO PATCH**(근거) | 엄격 envelope·fail-closed / S-1~4 | CODE 4 | 필드 이름 `...Days` 기록 |
| **P16-A** | 구형 11화면 | super_admin 11 | **6 수정 / 5 이관** | — / ASF-5·6·A-1~4 | CODE 4 · RENDER 2(shell 범위) | 헤더 TabBar 3 · 넓은 표 2 |
| 대비·터치 | — | — | — | — | **미측정** | P4 |

#### 최소 DEVICE 캡처·조작안 (바뀐 화면만)

1. **관리 탭**: 관리자 계정에서 상단이 흰 app bar + 프로필 카드인지, 목록이 스크롤되고
   하단 safe area 가 가려지지 않는지. 배율 1.3/2.0 에서 프로필 카드의 글자가 보이는지.
2. **관리 탭(사용자 계정)**: USER 로 들어가면 예전 파란 헤더 그대로인지(바뀌지 않았음).
3. **SubAdmin 모드 전환**: 사용자 모드 ↔ 관리 모드에서 두 shell 이 바뀌는지, 뒤로·탭
   상태가 유지되는지.
4. **계약 관리**: 정상 0건일 때 `미발송 계약서 없음` 이 그대로인지(실패 문구가 잘못
   뜨지 않는지). 실패 유도는 요청하지 않는다 — 주입으로 이미 확인했다.
5. **super-admin 시스템 설정**: 흰 app bar + 목록, 하위 설정 화면 6개 진입/뒤로.
6. 탈퇴 사전 점검 화면에서 경고(주황)·가능(초록) 블록의 색이 앱의 다른 경고/성공과
   같은 색인지.

---

## R7-P1-7 — 관리자 화면 간 일관성 · P1-6 잔여 종료 (2026-09-28)

기준 `8712c6e`. branch `main`, 시작 시 tracked 변경 0, 사용자 소유 untracked 8건 보존.
P16-C ERROR→EMPTY, P16-M 역할 shell, P16-S 집계 의미, P16-A 6화면 전환은 반례 없이
반복하지 않았다. P1-5 DEVICE/PRODUCT · Staffing O08 · 11TO/21업무 DEFERRED ·
계약 법률 사후 정비 OPEN 은 각 owner 에 그대로 둔다 — **이 보고는 그 항목들의 완료
선언이 아니다.** 공유 DEV 쓰기·CF 배포·Rules·PROD·APK **없음**.

### P17-A — 남겼던 5화면 (이름별 결산) → **5/5 수정**

| # | 파일 | 역할·진입 | 제약(P1-6 판정) | 이번 조치 | 결과 |
|---|---|---|---|---|---|
| 1 | `super_admin/help_faq_management_screen.dart` | SUPER · `settings_screen` | 헤더 TabBar 흰 라벨 **+ actions 흰 아이콘·스피너** | shell 전환 + 라벨/인디케이터 → `theme.primaryColor`·`grey500`, 아이콘 → `textSecondary` | **수정** |
| 2 | `super_admin/review_tags_settings_screen.dart` | SUPER · `system_settings_screen` | 헤더 TabBar 흰 라벨 | 위와 동일 | **수정** |
| 3 | `super_admin/to_limit_settings_screen.dart` | SUPER · `system_settings_screen` | 헤더 TabBar 흰 라벨 | 위와 동일 | **수정** |
| 4 | `super_admin/all_businesses_screen.dart` | SUPER · `settings_screen`·`super_admin_home` | 가로 스크롤 표 | shell 전환(헤더 의존 흰색 **0**) + 헤더 새로고침 → `actions` | **수정** |
| 5 | `super_admin/all_users_screen.dart` | SUPER · `settings_screen`·`super_admin_home` | 가로 스크롤 표 | 위와 동일 | **수정** |

**P1-6 의 이관 사유를 실측으로 좁혔다.** 두 표 화면의 `Colors.white` 는 전부 **본문**
이었다(버튼 전경색·전체화면 이미지 뷰어 오버레이) — 헤더에 의존하는 색이 없어 shell 만
바뀐다. 남은 위험은 **표 자체의 접근성**이고 그건 좁은 폭 렌더로 확인했다.
탭 3화면은 P1-6 이 본 라벨 외에 **`actions` 의 흰 아이콘**도 같은 문제였다(help_faq).

`AppPageScaffold` 에는 `onRefresh` 가 없어 헤더 새로고침을 `actions` 로 옮겼다 —
행동과 위치(우상단)는 같다. `all_businesses` 는 예전에 `GradientScaffold.onRefresh` 와
겹친다는 이유로 `RefreshIndicator` 를 **의도적으로 뺐으므로**, 새로고침 수단은 여전히
화면당 하나다(손실 없음).

**결과: `lib/screens/super_admin/` 의 실제 `GradientScaffold(` 호출 = 0.**

### P17-D — 문서 관리 색 후보 10곳 → **1곳 수정 · 9곳 NO PATCH**

`lib/screens/common/document_management_screen.dart` (USER 공용 경로 — 보존 대상).

| 줄 | 색 | 의미 | 판정 |
|---|---|---|---|
| 1084 | `0xFF22C55E` | `MANUAL_APPROVED` = **확인 완료** | **수정 → `AppColors.success`**. 같은 함수의 다른 분기는 `error`·`warning`·`infoDark` 를 쓴다 — 이 한 줄만 raw 초록이라 **같은 화면에서 '완료'가 두 색**이었다 |
| 769 · 771 | 빨강·앰버 | `bankVerificationStatus == mismatch / review_required` | **NO PATCH — 도달 불가**. 그 상태는 폐기됐고(서버가 값을 만들지 않음) 호출부도 `isPending/isError` 를 넘기지 않는다(`isComplete:` 만). 코드 주석이 이미 그 사실을 적고 있다 |
| 115 · 122 · 131 · 1389 · 1391 · 1501 · 1502 | 중립 회색(text/divider/secondary) | 상태·행동 의미 없음 | **NO PATCH**. 색 상수 개수 자체는 결함 근거가 아니고, 사용자가 상태를 오해할 자리가 아니다 |

의미색과 USER 공용 경로를 보존하면서 **실제 위반 1곳만** 고쳤다.

### P17-H — 공통 헤더·위계 → **NO PATCH (정정 포함)**

- **정정:** 감사표의 "`AppSummaryHeader`/`AppStatusCard` 채택 0" 중 `AppStatusCard` 는
  **컴포넌트 자체가 존재하지 않는다**(`lib/widgets/common/` 에 파일 없음).
  "미사용"이 아니라 "미존재"다. `AppSummaryHeader` 는 존재하고 사용 0.
- 채택률은 결함 근거가 아니므로 일괄 교체하지 않았다. 실제 **혼동·잘림**만 보았고,
  이번 단계에서 바뀐 화면들의 렌더에서 새 잘림은 나오지 않았다(아래 증거, 예외 0).
  이전 단계에서 발견된 잘림(`AppTabLabel` overflow · 월 카드 높이 · 월 상세 1·2행)은
  이미 각 owner 에서 고쳤다.
- 카드 radius 혼재는 **POLISH 유지**(미수정).

### P17-S — 통계 production 콘텐츠 → **NO PATCH · 렌더는 범위 명시**

P16-S 의 CODE 근거(단위·모집단·fail-closed·드릴다운 범위)를 재사용한다.
이번에 실행한 렌더는 **오류 경로**뿐이다 — 실패 시 `0원` 이 화면에 없다는 것을 확인했다.

**콘텐츠 렌더는 미실행이고 그 이유가 구조적이다:** `AdminStatsScreen` 은
`AdminStatsService()` 를 내부에서 만들고 CF 타임아웃 타이머를 남겨, 주입 없이는
위젯 테스트가 타이머 pending 으로 끝난다(90초 fake 시간을 흘려보내야 통과).
큰 수·긴 라벨·부분/상한 상태를 실제로 그리려면 **읽기 seam** 이 필요하고, 그것은
이번 최소 diff 범위를 넘는다.
→ `[R7-P1-7-RESIDUAL-STATS-CONTENT-RENDER]` · owner **P17-S** ·
종료 조건: 통계 읽기 seam + 큰 수/긴 라벨/부분·상한 렌더.

### P17-X — 화면 간 이동·복귀 → **NO PATCH (기존 증거 재사용)**

| 대표 이동 | 전달되는 context | 복귀 갱신 | 증거 |
|---|---|---|---|
| 홈 → 당일명단 | 오늘(KST 달력일) · 홈 scope 사업장 목록 | `pop(true)` → 인력·출근 재조회 | P1-4 AHR-22(실행) |
| 홈 → 부족 행 → 그날 지원자 | 그 날짜 · **부족 사업장만**(부족 큰 순) | `pop(true)` → 인력 재조회 | P1-4 AHR-23(실행) |
| 홈 → 할 일 행 | 사업장 선택 시트에 **사업장별 건수** | 처리 후 canonical summary 재조회 | P1-4 AHR-24(실행) |
| 급여 개요 → 월 상세 → 지급 현황 | 사업장·연·월 | 왕복 후 **원장 + 집계 문서 둘 다** 재조회 | P1-5 PNT-1(실행, 호출 수 증명) |
| 통계 → 월 상세 | `businessIds` · `filterBusinessId` · `year` · `month` | — | P16-S S-4(**CODE only**) |
| 권한 없는 역할 | 같은 자리에서 **진입 자체가 없다** | — | P1-4 AHR-25(실행) |

읽기 실패를 성공 0건으로 바꾸는 반례(P1-5 #8·#9, P1-6 #14)와 권한 없는 역할에서 행동이
노출되는 반례(AHR-25)를 우선 확인했고, 이번 단계에서 새 반례는 나오지 않았다.
도메인 writer 는 다시 감사하지 않았다. **DEV READ: 없음.**

### 실행 증거 (이번 단계)

`admin_shell_flat_render_test` **14건**(기존 10 + P17 신규 4):

| 증거 | 확인 |
|---|---|
| P17A-1 | 탭 3화면 — `AppPageScaffold`, Gradient 0, TabBar 의 label/unselected/indicator 가 **흰색이 아님** |
| P17A-2 | 320dp·배율 1.3 에서 **탭 전환 실행**, 라벨 유지, 예외 0 |
| P17A-3 | 표 2화면 320dp — flat shell + `actions` 새로고침 **실제 탭 실행** |
| P17S-1 | 통계 조회 실패에서 `0원` 이 화면에 없다 |

`admin_p16_shell_and_truth_contract_test` **20건**(기존 16 + P17-D 3 + A-5):
A-3 은 "남겼다"에서 **"전환됐고 제약이 함께 처리됐다"**로 갱신, A-5 는 super_admin
실제 호출 0 을 못박는다.

**회귀(같은 SHA·같은 환경·이름별):** 변경 파일을 참조하는 18파일 **476 PASS**,
`flutter analyze lib test` **No issues**. 전체 suite 총수로 결론내지 않았다.

### 결산 — P1-6 에서 남긴 조건을 실제로 닫았는가

| P1-6 잔여 | 상태 |
|---|---|
| super_admin 헤더 TabBar 3화면 | **닫힘**(전환 + 대비 이동 + 탭 전환 실행) |
| super_admin 가로 표 2화면 | **닫힘**(전환 + 좁은 폭 렌더 + 새로고침 행동 유지) |
| `document_management_screen` 색 10곳 | **닫힘**(1 수정 · 9 근거 있는 NO PATCH) |
| `AppSummaryHeader`/`AppStatusCard` 채택 0 | **닫힘**(NO PATCH · `AppStatusCard` 미존재로 정정) |
| radius 혼재 | POLISH 유지 |
| 통계 콘텐츠 렌더 | **이관** `[R7-P1-7-RESIDUAL-STATS-CONTENT-RENDER]` |

**P1-7 CODE·RENDER 종료.** 관리자 화면군의 PRODUCT/DEVICE 종료는 **별개**이며
각 단계의 DEVICE 항목이 남아 있다.

#### 최소 실기기 확인안 (이번에 바뀐 자리만)

1. super-admin → 도움말 FAQ / 리뷰 태그 / TO 등록 제한: 흰 app bar에서 **탭 라벨이 보이고**
   탭 전환이 되는지(배율 1.3).
2. super-admin → 전체 사업장 / 전체 사용자: 우상단 **새로고침**이 보이고 눌리는지,
   좁은 폭에서 표를 가로로 밀 수 있고 행 행동에 닿는지.
3. 문서 관리에서 `확인 완료` 배지의 초록이 앱의 다른 완료 초록과 같은지.

---

## R7-P1-7 후속 — 통계 콘텐츠 렌더 · 통계 hop (2026-09-28)

기준 `8b2bf34`. branch `main`, 시작 시 tracked 변경 0, untracked 8건 보존.
P17-A 5화면 · P17-D 1수정9유지 · P17-H NO PATCH · P16-S CODE 계약 · P17-X 기존 다섯
이동 실행은 **재사용**한다. 공유 DEV 쓰기·CF 배포·Rules·PROD·APK **없음**.

### 1. 타이머 원인 — production 결함이 아니다

보고했던 "CF 타임아웃 타이머"의 실제 위치는 화면이 아니라 **서비스**였다:
`AdminStatsService.getBusinessOptions` 가 각 문서 조회에 `.timeout(const Duration(seconds: 15))`
를 건다. 가짜 Firebase 에서는 그 future 가 끝나지 않으므로 타이머가 남아 하네스가 실패한다.

**production 흐름을 따라가 분리했다:**
- 화면은 `_statsRequestId` 로 늦은 응답을 버리고(`requestId != _statsRequestId` → 무시),
  모든 `setState` 앞에 `mounted` 를 본다. `dispose()` 는 자기 `ValueNotifier` 를 정리한다.
- 타임아웃 타이머는 **SDK/Future 소유**이고 조회가 끝나거나 15초에 풀린다.
  화면 이탈 후 남는 요청·타이머가 아니다.
→ **dispose 결함 없음. 테스트 주입 불가가 원인이다.**
그래서 timeout 을 줄이거나 로딩을 강제 완료하지 않고 **reader 한 칸만 주입**했다:
`AdminStatsScreen({... AdminStatsService? service})` ·
`AdminMonthDetailScreen({... AdminStatsService? service})` — production 은 null →
기존 인스턴스 그대로. 파싱·파생·문구·필터는 화면의 기존 경로를 그대로 지난다.

### 2. P17-S 실제 콘텐츠 렌더 — 결함 4건 발견·수정

| 시나리오 | 결과 |
|---|---|
| 큰 수·긴 라벨, 320dp·배율 1.3 (**ASC-1**) | `총 인건비 1.3억` · `근무 건수 1472건` · `출근율 97.4%` · 범위 `2026년 전체`·`전체 사업장` — 금액/건/% 단위가 서로 바뀌지 않는다 |
| 배율 **2.0** 스크롤 (**ASC-2**) | 예외 0 · 스크롤 접근 가능 |
| 정상 0 ≠ 전체 실패 (**ASC-3**) | 정상 0 → `0건`. 전체 실패 → `통계를 불러오지 못했습니다` 로 **수치를 아예 내지 않는다**(`0건`·`근무 건수` 자체가 없다, "데이터가 없습니다" 아님) |
| 부분·상한 (**ASC-4**) | `AttendanceStatsState.unavailable` → `확인 불가`, `1472건`·`1.3억` 미표시 |
| 사업장 전환 중 늦은 응답 (**ASC-5**) | 전환 후 `7건` 유지, 늦게 온 `9999건` 미표시 |
| 사업장 선택 반영 (**ASC-6**) | 선택이 **조회 범위**(`filterBusinessId='biz2'`)와 머리말에 반영 |
| 월 상세 콘텐츠 320dp·1.3 (**ASC-7**) | `김근로` · `12일`(고유 날짜) · `지각 2`(건, 단위어 없음) |

**렌더가 잡은 잘림 4건(전부 flex 없는 Row — 프로젝트 규칙 위반):**

| 위치 | 증상 | 수정 |
|---|---|---|
| `admin_stats_screen` 총 인건비 머리 Row | 320dp·1.3 에서 **53px** | 라벨·기간을 `Flexible`+ellipsis(금액은 줄이지 않음) |
| `_DeltaBadge` 내부 Row | 부모가 좁아지면 **42/26px** | 퍼센트 텍스트 `Flexible`+ellipsis |
| `admin_stats_screen` 월별 인건비 제목+범례 Row | 배율 2.0 에서 **4.7px** | 제목 `Flexible`+ellipsis(범례 유지) |
| `admin_month_detail` 출결 통계 행 | 320dp·1.3 에서 **275px** | `Wrap` 으로 줄바꿈 허용 |
| `admin_month_detail` 직원별 요약 헤더 | **110px** | 제목 `Flexible`+ellipsis(정렬 칩 유지) |

글자를 숨기거나 배율을 끄지 않았고, 수치·범례·정렬 칩을 없애지 않았다.

**하네스 메모:** 같은 타입 화면을 연달아 pump 하면 State 가 재사용돼 시나리오가 섞인다
(첫 성공값이 두 번째 실패 화면에 남아 보였다) → `KeyedSubtree(key: UniqueKey())` 로 격리.

### 3. P17-X 통계 hop — **부분 실행 · 제스처는 NOT SEEN**

| 구간 | 결과 |
|---|---|
| 사업장 선택 → **조회 범위·머리말** | **실행**(ASC-6) — `filterBusinessId` 가 실제 조회로 간다 |
| 월 카드 → 월 상세 **생성 인자** | **CODE only**(P16-S S-4: `businessIds`·`filterBusinessId`·`year`·`month`) |
| 월 상세 **화면 자체** | **실행**(ASC-7) |
| 월 카드 **탭 제스처** | **NOT SEEN** — 드릴다운이 `fl_chart` `BarTouchData.touchCallback` 안에 있어 위젯 테스트로 누를 수 없다(차트 내부 히트테스트) |

→ `[R7-P1-7-RESIDUAL-STATS-HOP-GESTURE]` · owner **P17-X** ·
종료 조건: 실기기에서 월 막대 탭 → 월 상세의 월·사업장 일치 확인(DEVICE).
권한 경로는 기존 guard 를 재사용한다(통계 진입은 `canManageWage` 가 아닌 관리자 진입
경로이며 이번에 새 bypass 를 찾지 못했다).

### 4. 용어 정정과 기존 증거 매핑

**`AppSummaryHeader` 와 `AppStatusCard` 는 서로 다른 대상이다** —
`lib/widgets/common/app_summary_header.dart` 에 `AppSummaryHeader` 가 **존재**하고
호출부는 **0**이다. `AppStatusCard` 는 **클래스·파일이 없다**. 감사표의
"`AppSummaryHeader`/`AppStatusCard` 채택 0" 은 한 덩어리로 읽히지만 **하나는 미사용,
하나는 미존재**다 — 표현만 바로잡고 UI 는 교체하지 않았다(사용 횟수는 결함 근거가 아니다).

**P17-A 증거 ↔ 화면 매핑**(기존 14건 중 super-admin 관련):

| 증거 | 대응 화면 | 범위 |
|---|---|---|
| P17A-1 | `help_faq_management` · `review_tags_settings` · `to_limit_settings` | shell + TabBar 색 계약(3화면 반복) |
| P17A-2 | `help_faq_management` | **탭 전환 행동**(320dp·1.3) |
| P17A-3 | `all_businesses` · `all_users` | shell + `actions` 새로고침 **탭 실행**(320dp) |
| ASF-5 · ASF-6 | `system_settings` | **shell 범위**(배율 2.0 포함) |
| (증거 없음) | `business_approval_settings` · `insurance_rate_settings` · `minimum_wage_settings` · `legal_terms_management` · `badge_settings` | **CODE only** — A-1·A-2 계약으로만 확인 |

즉 super-admin 11화면 중 **렌더로 확인한 것은 6**(탭 3 + 표 2 + system_settings)이고
나머지 5는 소스 계약뿐이다. 기존 증거로 충분한 범위는 새 테스트를 만들지 않았다.

### 5. P1-7 결론 재판정

| 구분 | 이전 주장 | 이번 판정 |
|---|---|---|
| P1-7 CODE | 종료 | **종료** |
| P1-7 RENDER | 종료 | **종료** — 통계 콘텐츠가 렌더됐고, 그 과정에서 잘림 5건을 고쳤다. 다만 **super-admin 5화면은 CODE only**, **통계 hop 제스처는 NOT SEEN** 으로 범위를 명시한다 |
| P1-7 PRODUCT/DEVICE | 미주장 | **미주장 유지**(DEV READ 없음·DEVICE 미실행) |

첫 보고의 "P1-7 전체 CODE·RENDER 종료" 는 통계 콘텐츠가 미렌더인 동안 **PARTIAL** 이었고,
이번에 그 조건을 채워 종료로 올린다.

### 6. 증거·회귀

- **행동·RENDER** `admin_stats_content_render_test` **7건**(ASC-1~7)
- **CODE** 기존 P16-S S-1~4 재사용(재구현하지 않았다)
- **DEV READ** 없음 · **DEVICE** 미실행
- **회귀(이름별)**: 통계·월상세·서비스를 참조하는 **8파일 156 PASS**,
  `flutter analyze lib test` **No issues**. 전체 suite 총수로 신규 실패를 판단하지 않았다.

#### 최소 실기기 확인안 (이번에 바뀐 자리만)

1. 통계에서 **글자 크게(1.3·2.0)** — 총 인건비 머리줄, 증감 배지, `월별 인건비` 범례가
   잘리지 않는지.
2. 월 상세 320dp — 정상/지각/결근 칩과 총 인건비가 **줄바꿈되어 모두 보이는지**,
   직원별 요약의 정렬 칩(근무일·임금·이름)을 누를 수 있는지.
3. 통계에서 **월 막대를 탭** → 월 상세의 월·사업장이 통계의 현재 선택과 같은지
   (위젯 테스트로 못 누르는 유일한 구간).

---

## [R7-P1-2 DEVICE.1H.1 후속] 확정 명단 행 잘림 — 수정 완료 (2026-09-29)

P3-2 의 IHK-5 가 320dp·배율 2.0 에서 넘침 3건(62/14/104px)을 재현해 두었다.
원인을 좁혀 보니 `ApplicantRowSurface` 자체에는 Row 가 하나도 없고(순수 표면),
넘친 것은 `day_applicants_dialog` 가 그 안에 넣는 **자식 레이아웃**이었다.
그래서 `work_applicants_dialog` 와 `IdCardHelper` 는 **한 글자도 바뀌지 않았다**.

고친 자리 다섯: 초대 상태 배지 · 계약 아이콘 칩 · 확정 행동 줄 · 대기 행동 줄 ·
묶음 머리줄 통계. 값을 지우거나 글자 배율을 무효화하지 않고 **접히게** 했다
(`Flexible` · `Wrap`, 아이콘과 그 수치는 한 덩어리로 유지).

넘침은 경고로 끝나지 않았다 — 수정 전 **대기 행의 버튼 세 개 중 하나가 잘려
사라졌다**(ARO-5). IHK-5 의 "잘림이 있어야 PASS" 기대는 지우지 않고 정상값으로 옮겼다.

상세: `docs/r7-p12-applicant-row-overflow-fix.md`. **DEVICE 는 여전히 NOT SEEN** —
P4-1 관찰표 A-1 로 실기기 재검증이 남는다.
