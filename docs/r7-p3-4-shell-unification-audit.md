# R7-P3-4 — 살아 있는 하위 화면의 shell 일관성과 기능 보존

> 작성: 2026-09-28 KST · 기준 HEAD `eaa6727` (tracked dirty 0 · 사용자 untracked 8건 보존)
> 범위: **현재 `GradientScaffold` 실제 호출부만.** 79화면 전수 리디자인도,
> P3/PRODUCT 전체 종료도 아니다.

---

## 0. 착수 HEAD 에서 다시 센 실제 호출부 — **5곳**

주석·선언·테스트는 실제 호출로 세지 않았다. `super_admin` 6개 파일은 전환 완료
흔적(주석)만 남아 있고, `ApplyPrerequisitesScreen` 은 P2-2 에서 이미 전환됐다.

| # | 파일 | 위치 |
|---|---|---|
| 1 | `lib/screens/common/settings_screen.dart` | 733 (지원자 경로 분기) |
| 2 | `lib/screens/user/attendance_check_screen.dart` | 696 |
| 3 | `lib/screens/user/interim_settlement_request_screen.dart` | 202 |
| 4 | `lib/screens/user/my_reviews_screen.dart` | 114 |
| 5 | `lib/screens/user/subadmin_leave_screen.dart` | 107 |

제출 기준(common 1 + user leaf 4)과 **일치**한다.

### 전제도 확인했다

홈·일자리·일정·MY·내 지원은 전부 **흰 flat**(`Scaffold(backgroundColor: white)` /
흰 `AppBar`)이다. 즉 한 여정 안에서 상위는 흰 화면, 하위는 파란 헤더였다.

---

## 1. 화면별 계약 (전환 전 실측)

| 화면/역할 | 실제 시작→뒤로/홈 | headerContent·탭·흰 글자 | onRefresh·벨·홈·계약 바 | 같은 역할 flat 화면과의 대비 | 판정 |
|---|---|---|---|---|---|
| 출퇴근/지원자 | 홈 카드·`퇴근 기록이 남았어요` → 뒤로 | 없음 (본문은 `contentColor` grey50 위) | `_loadTodayWorks` · 벨 O · 홈 O · 계약 바 O | 홈(흰 flat)에서 파란 헤더로 | **PATCH** |
| 내 리뷰/지원자 | 알림 · FCM · 공용 Settings → 뒤로 | 없음 | `_loadReviews` · 벨 O · 홈 O · 계약 바 O | 알림(flat)에서 파란 헤더로 | **PATCH** |
| 중간정산/지원자 | 내 지원 카드 → 뒤로 | 없음 (제목에 사업장명 포함) | `_loadConfirmedAttendances` · 벨 O · 홈 O · 계약 바 O | 내 지원(흰 AppBar)에서 파란 헤더로 | **PATCH** |
| 서브관리자 탈퇴/해당 역할 | 설정 → `서브관리자 관리` → 뒤로 | 없음 | refresh **없음** · 벨 **false** · 홈 **false** · 계약 바 O | 설정에서 이어짐 | **PATCH** |
| 공용 설정/USER·관리자·서브관리자 | MY 탭 · 계약 서명 · 공고 상세 · 알림 → 뒤로 | **headerContent = 흰 글자 프로필** | 지원자 경로: refresh 없음 · 벨 O · 홈 O · 계약 바 O / **관리자 경로: 셋 다 없음** | 관리자 경로는 이미 flat, 지원자만 gradient | **PATCH(경로별)** |

**핵심:** 네 leaf 화면의 본문은 원래도 **밝은 배경 위**에 있었다
(`GradientScaffold` 는 body 를 `contentColor`(grey50) 곡선 컨테이너에 넣는다).
**흰 글자/아이콘이 파란 배경에 직접 얹힌 것은 설정의 `headerContent` 뿐**이었다 —
그래서 네 화면은 대비 문제 없이 옮길 수 있었다.

---

## 2. 무엇으로 옮겼나 — 기능 보존 설계

`AppPageScaffold` 는 refresh/벨/홈 인자가 없지만 **`actions` 로 caller 가 넘기는
구조**이고, 계약 바는 `bottomNavigationBar` 로 넘어간다. 관리자 flat 화면들이
이미 그렇게 하고 있다. **`AppPageScaffold` 자체는 한 줄도 고치지 않았다** —
기존 flat 소비자에 미치는 영향이 0 이라는 뜻이다.

신규 `lib/widgets/common/app_page_actions.dart` 한 개만 더했다
(CLAUDE.md: 신규 UI 는 공통 컴포넌트, 인라인 금지). **기존 flat 화면의 인라인
actions 는 건드리지 않았다** — 소비자 0 에서 시작하는 새 helper 다.

의미를 바꾸지 않은 것:

- **새로고침은 우상단 버튼**이다. 당겨서 새로고침으로 바꾸지 않았다
  (본문의 `RefreshIndicator` 는 원래 있던 그대로 별개로 남는다).
- 알림 → `NotificationScreen`, 홈 → `NavigationHelper.goHome` — 목적지 동일.
- 벨은 `NotificationBadge` 로 감싼다(읽지 않은 수 유지).
- 본문은 `SafeArea(top:false,left:false,right:false)` 로 감쌌다 —
  `GradientScaffold` 가 하던 것과 **같은 자리, 같은 인자**다.
  (`my_reviews` 의 `MediaQuery.paddingOf(context).bottom` 보정 sliver 가
  이중으로 더해지지 않는 이유도 이것이다.)
- **계약 바는 장식이 아니라 Task 접근**이다. 다섯 화면 모두 유지했고,
  서명할 것이 없을 때 거짓 대기를 만들지 않는 것도 확인했다(SHU-2).

역할별로 **강제 통일하지 않은 것**:

- `subadmin_leave` 는 원래 홈·알림을 껐다(되돌릴 수 없는 결정에 옆길을 만들지
  않는다). 그 선택을 **그대로** 옮겼다 — 편의상 켜지 않았다.
- 설정의 **관리자 경로에는 홈·알림·계약 바를 더하지 않았다.** 없던 것을
  만들지 않는다. 제목도 `관리`/`설정` 분기 그대로다.
- 설정 지원자 경로의 프로필 대비는 **관리자 경로가 이미 푼 방식**(brand 색 카드,
  radius 16)을 그대로 쓴다 — 내용·문구·정보량 동일.

---

## 3. 대표 여정 전후

| 여정 | 이전 | 지금 |
|---|---|---|
| 홈 → 출퇴근 | 흰 flat → **파란 헤더** | 흰 flat → 흰 flat, 우상단 새로고침·홈·알림 유지 |
| 알림 → 받은 평가 | flat → **파란 헤더** | flat → flat, 세 버튼·계약 바 유지 |
| 내 지원 → 중간정산 | 흰 AppBar → **파란 헤더** | 흰 AppBar → 흰 flat, 긴 제목 320dp×2.0 확인 |
| MY/관리자 → 설정 | 역할에 따라 **두 shell** | 한 shell, **역할 차이는 제목·액션·계약 바로 남는다** |

---

## 4. 공통 컴포넌트 정리 — **삭제하지 않는다**

실제 호출부는 **0** 이 됐다(SHU-0). 그래도 `gradient_scaffold.dart` 는 **남긴다**:

- 호출부 0 자체는 제품 성과가 아니다.
- **DEVICE 확인 전**이다. 실기기에서 되돌릴 여지를 없앨 이유가 없다.

대신 **거짓이 된 주석을 고쳤다.** 파일 머리말이
*"홈화면·내 스케줄·공고 찾기와 동일한 디자인 언어"* 라고 적고 있었는데,
그 세 화면은 이미 흰 flat 이라 **사실이 아니었다.** 현재 사실과 되살릴 때의
조건을 적어 두었다. SHU-0b 가 파일 존재를 고정한다.

---

## 5. 보고 표

| 화면 | 역할/실제 시작 | 활성 기능·대비/탭 | 전환 PATCH 또는 NO PATCH 이유 | CODE | 행동 | RENDER | 미관찰·owner |
|---|---|---|---|---|---|---|---|
| 출퇴근 | 지원자 / 홈 카드 | refresh·벨·홈·계약 바 · 흰 글자 없음 · 탭 없음 | **PATCH** — 네 기능 모두 `actions`+`bottomNavigationBar` 로 재현 가능 | 종료 | 렌더 제스처(쓰기 0) | **종료**(SHU-1·2·R×6) | 실제 출퇴근 mutation·DEVICE (VJ06) |
| 내 리뷰 | 지원자 / 알림·FCM | 동일 | **PATCH** | 종료 | 렌더(쓰기 0) | **종료**(SHU-3) | 알림→리뷰 제스처 NOT SEEN (VJ14) |
| 중간정산 | 지원자 / 내 지원 카드 | 동일 + 제목에 사업장명 | **PATCH** — 긴 제목 320dp×2.0 확인 | 종료 | 렌더(쓰기 0) | **종료**(SHU-7) | 실제 정산 요청 mutation |
| 서브관리자 탈퇴 | 서브관리자(지원자 모드) / 설정 | refresh·벨·홈 **원래 없음** · 계약 바 O | **PATCH** — 없던 버튼을 더하지 않고 그대로 옮김 | 종료 | 렌더(쓰기 0) | **종료**(SHU-4) | 실제 탈퇴 mutation |
| 공용 설정(역할별) | USER·SubAdmin(양 모드)·관리자 / MY·계약·공고·알림 | 지원자: 벨·홈·계약 바 O / 관리자: 없음 · **headerContent 흰 글자** | **PATCH(경로별)** — 대비는 관리자 경로의 기존 brand 카드 재사용, 역할 차이는 유지 | 종료 | 렌더(쓰기 0) | **종료**(SHU-5·6, ASF-2·3) | 실사용자 이해 (GAP-02) |

---

## 6. 증거

| 항목 | 값 |
|---|---|
| 신규 테스트 | `shell_unification_render_test.dart` **15건**(SHU-0·0b·1~7·R×6) |
| 전후 실제 행동 | SHU-1/3/7 세 버튼 존재 · SHU-2 계약 바가 **상태대로** 뜨고 사라짐 · SHU-4 없던 버튼 없음 · SHU-5/6 역할 차이 유지 |
| 정상 대조 | SHU-2 후반(미서명 없음 → 바 없음) · SHU-6(관리자 경로에 버튼 0) |
| 위험 조합 | 320/360/412dp × 1.3/2.0 — 출퇴근 6조합 + 중간정산 긴 제목 320×2.0, 예외 **0** |
| 기존 테스트 갱신 | `admin_p16_shell_and_truth_contract`(M-1·A-4) · `admin_shell_flat_render`(ASF-2·3) — **옛 사실을 지우지 않고 새 기대값으로 이동** |
| 회귀 | 영향집합 **346 PASS / 0 FAIL** · 기준선 같은 이름 실패 **없음** |
| 정적 분석 | `flutter analyze lib test` **No issues** |
| 변경 파일 | `app_page_actions.dart`(신규) · `gradient_scaffold.dart`(주석) · 위 5화면 |
| DEV READ | **없음** · DEVICE **미실행** · USER OBSERVATION **없음** |

## 7. 이관·미관찰

- **DESIGN CODE/RENDER 종료와 DEVICE/PRODUCT/사용자 이해는 별개다.**
  이 전환은 실기기에서 확인된 바 없다.
- GAP-02 **F1~F3/F5**(수입·받은 평가 발견성, 가능일/초대 이해, 역할 전환 깊이)는
  shell 전환으로 닫히지 않는다. 이번에 **기능 손실도 대상 혼동도 관찰되지
  않았으므로** 그 owner 들에 손대지 않았다. "처음 사용자가 찾을까"는 **P5**.
- F4·F7(P3-3 수정) · F6 단위 안내는 회귀가 필요한 소비자만 재사용했다.
- `ApplicantRowSurface` 확정 명단 overflow·IHK-5 → **P1-2 DEVICE.1H.1**.
  P2-2 A1 · VJ02 날짜 저장 · P23-N 일정 복귀 · Home CTA 9개/FCM ·
  P1-5/P1-7 DEVICE · Staffing DEFERRED/O08 · 계약 사후 정책 · 출시 gate — 그대로.
