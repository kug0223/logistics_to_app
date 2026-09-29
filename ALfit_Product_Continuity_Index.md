# ALfit Product Continuity Index

> 세션·단계가 바뀌어도 **무엇이 어디까지 닫혔고 무엇이 누구 소유인지** 한 장에서 잇는다.
> 세부 근거는 각 감사 문서에 있고 이 파일은 **포인터와 상태**만 유지한다.
> 마지막 갱신: 2026-09-29 · 기준 HEAD: **R7-P4.2C** (Home 설정 진입점 · readiness owner)

## 0. CURRENT SNAPSHOT — 2026-09-29 / R7-P4.2C

> 아래 절들은 누적 기록이다. **지금 어디 있는지**는 이 절만 읽으면 된다.

**기준 → 종료:** `6b77dc6` → `7a5e804`(P4.2-1) → `3a7fde8`(P4.2B) → **P4.2C**

| 회차 | 범위 | CODE | RENDER | DEV | DEVICE | PRODUCT |
|---|---|---|---|---|---|---|
| R7-P4.2-1 | Home 온보딩 네비 · 세 탭 SETUP_REQUIRED · 급여 root 홈버튼 | CLOSED | 소스 계약만 | NOT SEEN | NOT SEEN | — |
| R7-P4.2B | root 이름 일치 · 알림 owner · identity 강도 · 하단바 · cold path | CLOSED | **CLOSED**(46셀, 320/360/411 × 1.0/1.3/2.0) | NOT SEEN | **NOT SEEN** | 관리 탭 정체성 OPEN |
| R7-P4.2C | Home 설정 진입점 · readiness refresh owner | **CLOSED** | **PARTIAL** — `AdminTabSwitcher` 실물 8셀. Shell 은 Firebase 없이 pump 불가 → 배선은 소스 계약 | NOT SEEN | **NOT SEEN** | — |

### R7-P4.2C 결정

**§1 product intent — `A. 관리 탭으로 이동` (확정)**
헤더 버튼은 `const SettingsScreen()` 을 push 했다. Shell 탭 4 의 root 도
`const SettingsScreen()` — **파라미터 0, 완전히 같은 위젯**. tooltip·semantic label 은
**없었다**(admin `_headerBtn` 은 label 인자를 받지 않는다). 기존 테스트 이름도
`02-c 알림 · 설정 action` 이었다. B(프로필)·C(별도 설정)·D(역할 전환) 아님 —
`person_outline` 은 이 제품에서 지원자 MY 탭의 '프로필 관리'(`ProfileEditScreen`)를 뜻한다.

| ID | 판정 | 근거 |
|---|---|---|
| `[P4.2C-NAV-01]` | **Model B — switchToTab(settingsTab)** | 같은 목적지에 두 개의 top-level 진실이 있었다. 목적지는 그대로, 가는 방법만 바꿨다. 아이콘도 `settings_outlined` 로 목적지를 따라간다. 버튼은 **지우지 않았다** |
| `[P4.2C-READY-01]` | **R1 — Home 재활성화** (R2 기각) | R3 불가: `notifyDataChanged` 17 호출부 중 **관리 탭 0곳** — 기존 버스가 Manage mutation 을 나르지 않는다. R2(4+ 화면에 mutation 신호 추가)는 blast radius 로 기각 |

**드러난 더 큰 사실:** 그 `_reloadReadiness()` 는 원래부터 **반쪽**이었다.
같은 화면에 하단 '관리' 탭으로 들어간 경우엔 아무도 갱신하지 않았다 —
owner 가 화면이 아니라 **한쪽 입구**에 붙어 있었다. 이번 수정으로 두 입구가 같아졌다.

**read 증감 (정적)**

| 전이 | 전 | 후 |
|---|---|---|
| 헤더 버튼 → 관리 → 홈 | 2 loader | 2 loader (동일) |
| 하단 관리 탭 → 홈 | **0** (stale) | 2 loader |
| 공고·근무·급여 → 홈 | 0 | **0** (`fromTab` 가드) |
| 관리 탭 진입 시 Home preload | 없음 | 없음 |

**back semantics 변화(사용자에게 보임):** 예전엔 push 라 back 이 Home 으로 돌아왔다.
이제 관리 탭 root 이므로 다른 네 root 와 **같은 규칙** — 탭 내 route 가 없으면
`SystemNavigator.pop()`. 이 규칙은 이번에 만든 것이 아니라 Shell 의 기존 계약이다.

**역할 영향:** BUSINESS_ADMIN · USER(SubAdmin 관리자 모드) 둘뿐.
SUPER_ADMIN 은 `AdminHomeScreen`(다른 화면), 지원자 Home 에는 이 버튼이 없다.
역할 전환 진입점(헤더 토글 · 관리 화면 '지원자 모드로 전환') 둘 다 무변경.

**P4.2B 에서 확정한 것**

| ID | 판정 | 근거 |
|---|---|---|
| `[P4.2B-CTA-01]` | **KEEP HOME ROUTE** + 라벨 교체 | 사업장 등록 후에도 **운영팀 검토 대기**가 남는다(`business_form_screen` 성공 토스트). 그 사실을 설명하는 화면은 홈뿐이다. 원 탭으로 되돌리면 "방금 등록했는데 또 없다고 한다"가 된다. 라벨만 목적지를 가리키게: `준비 계속하기` → `준비 단계 보기` |
| `[P4.2B-NAV-02]` | CORRECTION | 하단 탭 `근무` ↔ 화면 제목 `인력`. 다섯 중 이 하나만 어긋났다 |
| `[P4.2B-NAV-03]` | CORRECTION | 알림 벨이 홈·급여 **둘에만** 있었다. 전역 수신함이므로 owner 를 홈 하나로. 다섯 전부에 붙이는 쪽은 거부(탭 고유 action 이 묻힌다) |
| `[P4.2B-ID-01]` | MODIFY → **C(light tonal)**, 관리자 경로만 | 관리 탭에서 가장 진한 면(primary 100%)이 **탭도 안 되는 이름표**였고, 누를 수 있는 메뉴는 전부 흰 행이었다. B(흰 면)는 메뉴 행과 구별이 사라져 기각 |
| `[P4.2B-PERF-01]` | CORRECTION | 근무 탭 cold entry 에서 `getMyBusinessOrThrow` 가 **2회** 나갔다(두 로더가 같은 프레임, 캐시는 await 뒤에 채워짐) |
| 하단 NavigationBar | **NO PATCH** | 선택 탭이 색·굵기·filled/outlined **3채널**로 구별된다(VR-02s). 320dp×2.0 에서도 5라벨 전부 표시, 넘침 0 |
| 세 SETUP 표면 레이아웃 | **NO PATCH** | 27/27 조합에서 넘침 0 |

**P4.2B 가 재확인하지 않은 것(P4.2-1 수용분):** Home 4단계 destination · `_reloadReadiness()` ·
`FirstPostingReadiness ↔ CreateTO` parity · NO_BUSINESS state contract · 급여 root 홈버튼 제거.

## 1. 문서 지도

| 문서 | 역할 |
|---|---|
| `ALfit_Product_Continuity_Index.md` (이 파일) | 단계·소유·상태의 연속성 색인 |
| `ALfit_Product_Integrity_Master_Ledger.md` | 제품 진실성 원장 — 결함/판정/미결의 누적 장부 |
| `docs/r7-p1-admin-design-audit.md` | R7-P1 감사 본문(단계별 표·근거·증거) |
| `docs/r7-p2-user-design-audit.md` | R7-P2 지원자(USER) 감사 본문 |
| `docs/r7-gap02-product-value-criteria.md` | **GAP-02 제품 가치·사용성 기준** — VJ01~14 레지스트리, 증거 등급 규칙, 역할별 PRODUCT 상태 |
| `docs/r7-staffing-count-lineage-audit.md` | Staffing 카운터 계보 감사 |
| `docs/functional_test_*.md` | 기능별 시나리오 인벤토리(일부 낡음 — 아래 주의) |
| `CLAUDE.md` | 작업 지침·설계 확정 항목·금지 사항 |

**인벤토리 주의:** `functional_test_Q_payroll_screens.md` 는 존재하지 않는
`today_payment_screen.dart` 를 대상으로 적고 있고 Q-01 의 `limit(500)` 도 이미 CF 로
옮겨졌다. 인벤토리는 **현행 HEAD 의 도달 경로로 재확인한 뒤** 쓴다.

## 2. R7-P1 단계별 상태

| 단계 | 범위 | CODE | RENDER | DEVICE/PRODUCT |
|---|---|---|---|---|
| P1-2 | Staffing identity·좌석·UNKNOWN | CLOSED | CLOSED | O08 **PENDING** |
| P1-3 | 근태 관계·날짜 계약 | CLOSED | CLOSED | **PENDING**(권한 있는 실제 action) |
| P1-4 | 홈·할 일·요약 | CLOSED | CLOSED | **PENDING** |
| P1-5 | 급여 개요·상세·대시보드 | CLOSED | CLOSED | **PENDING** |
| P1-6 | 계약·관리·통계 | CLOSED | CLOSED | **PENDING** |
| P1-7 | 관리자 화면 간 일관성 + P1-6 잔여 | CLOSED | **CLOSED**(super-admin 5화면 CODE only · 통계 hop 제스처 NOT SEEN) | **PENDING** |
| P2-1 | 지원자 Home·4탭 진입 | **CLOSED** | **CLOSED**(P21-R 행동은 12경로 중 4 실행 · 탭 내부 화면군 범위 밖) | **PENDING** |
| P2-2 | 일자리·공고 상세·지원 흐름 | CLOSED | **CLOSED**(D2·N1 행동 실행 · **A1 제스처 격리 실행 불가 — 원인 확정**) | **PENDING** |
| P2-3 | 근무가능일↔초대 의미 | CLOSED(consumer 전수) | **CLOSED**(첫 선택 전 안내·4상태·왕복) | **PENDING** · 실사용자 이해 **NOT SEEN** |
| P2-3 후속 | 일정·출퇴근 화면군(P23-N/S/A/V/E/G) | CLOSED | **CLOSED** | **PENDING** · 저장 제스처·실제 mutation **NOT SEEN** |
| P2-4 | MY·수입·리뷰·요청(P24-N/I/R/Q/E/G) | CLOSED | **CLOSED**(월 시트 제스처·리뷰 3상태 렌더 실행 완료) | **PENDING** · 알림→리뷰 제스처 NOT SEEN · 발견성 VJ07/VJ14 |
| P3-1 | 네 역할 과업·인계·가치 후보(P31-H/W/D/X/F) | CLOSED(H·W·D) · **CODE only**(X) | **CLOSED**(서브관리자 전환 RSW-1~4) · 슈퍼관리자 **NOT SEEN** | **PENDING** · 후보 F1~F7 전부 **VERIFY** |
| P3-2 | 제안·권한·운영 판단의 내용 렌더(P32-H/D/X1/X2) | CLOSED | **CLOSED** — 네 셀 모두 내용 RENDER(IHK/WPD/SAU/TOL 22건). 수락 확인창만 CODE only | **PENDING** · F4/F6/F7 **VERIFY** 유지 |
| P3-3 | 행동 직전 판단(P33-D/X1/X2) | CLOSED | **CLOSED**(ACX-1~12) — 세 셀 **PATCH**: 무안내 pop · 확인창 대상 식별자 · 한도 단위·적용 시점 | **PENDING** · 급여 안내·사용량 표시·사람 인지는 **VERIFY/USER OPEN** |
| P3-4 | shell 일관성·기능 보존(5 호출부) | CLOSED | **CLOSED**(SHU-0~7, R×6) — 다섯 곳 전환, refresh·홈·알림·계약 바 보존 | **PENDING** · DEVICE 미실행 · F1~F3/F5 는 shell 로 닫히지 않는다 |
| P2 잔여 | Home CTA 12경로 · 일정 카드(P21-R/P23-N) | CLOSED | **CLOSED(격리)** — 12/12 실행(UHR-31~46) + 인박스 내부(MRI-0~5) + 일정 카드·다른 달(PSN-1~5) | **PENDING** · 승인·동의 writer·앱 복귀 경로 각 owner |
| P2-1 후속 | 서류 보완 확인 실패 · 목적지 대상(H6-E/H6-D) | CLOSED | **CLOSED(격리)** — 실패 표면·재시도·uid 가드 8건(UHR-45 갱신 · 47~54) + 목적지 본문 실측 5건(DDT-1~5) | **PENDING** · 목적지에 요청 문맥(사업장·사유·"외 N건") 없음 — 내 서류 화면 owner |
| FS (품질 기준선) | 전체 스위트 기존 49 실패 결산 | **TEST gate CLOSED** — 14451 PASS / 2 SKIP / **0 FAIL · 0 load error**, analyze No issues. 원인 6개 전부 오래된 테스트·하네스, **production 변경 0** | N/A(코드 수정 없음) | `[OPEN-CONTRACT-MONTHEND]` 는 아래 행으로 옮겨 재정의됨. **DEVICE·USER 는 종전대로 PENDING** — TEST green ≠ 출시 승인. 상세: `docs/r7-full-suite-baseline-closure.md` |
| MONTHEND | 계약 기간 종료일 (`[OPEN-CONTRACT-MONTHEND]`) | **CODE + 빌드 산출물 CLOSED.** 규칙 `v2-kst-civil-160`(초일산입 + 민법 160②③, KST 달력일), Dart·TS 두 구현 + 공유 벡터. 표준 빌드 재생성 후 산출물에 v2 참조 1건·v1 식 0건 확인 | **DEV DEPLOY 실행** — `callableConfirmApplication` 단일 배포 성공(소스 업로드 2026-09-21T14:03Z → **2026-09-29T07:02Z**, hash 갱신). **244개 중 1개만 변경**, 243개 gen/hash/state 불변 전수 확인. 1차 시도는 CLI 소스분석 타임아웃으로 **업로드 전** 실패(반영 0), `FUNCTIONS_DISCOVERY_TIMEOUT` 상향 후 성공 | **DEV 실제 확정 NOT SEEN** — 사용자가 테스터 데이터를 전부 정리해 `tos`/`applications`/`employment_contracts` 전부 **0**. 구 PENDING 정정·기존 서명 계약 불변은 **N/A(대상 없음, PASS 아님)**. 새 테스트 계정·TO·지원서 식별 후 재개. RENDER 는 격리 10셀만(DEV 렌더 NOT SEEN). DEVICE NOT SEEN. **지원자 기간 정정 고지는 구현 부재** — 안 1/안 2 PRODUCT OPEN. PROD 전환은 **프로젝트 없음 → 대상 없음**. 구버전 앱×CFv2 혼합은 출시 정책으로 이월. 상세: `docs/r7-contract-monthend-audit.md` |
| P4-1 | 실기기 조작·가독성(P41-S/A/R) | — | — | **전 셀 NOT SEEN** — 접근 가능한 Android 기기 0(adb 0, flutter 는 desktop/web). 관찰표 `docs/r7-p4-1-device-observation-sheet.md` 준비 완료 |
| P1-2 후속 | 확정 명단 행 잘림(DEVICE.1H.1) | CLOSED | **CLOSED**(ARO-1~7) — `day_applicants_dialog` 다섯 자리 접기. 수정 전 대기 행 버튼 1개 소실 → 복구 | **NOT SEEN** · P4-1 관찰표 A-1 로 실기기 재검증 |
| P2 나머지 | — | 지원자 화면군 여섯 묶음 결산 완료(PRODUCT 는 OPEN) | — | — |
| P4 | 대비·터치영역 정량 계측 | 미착수 | — | **미측정** |

## 2.5 네 역할 PRODUCT 결산 (GAP-02)

CODE/RENDER 종료가 제품 가치 종료가 **아니다**. 실사용자 관찰이 없으면 OPEN 이다.

| 역할 | CODE/RENDER | USER OBSERVATION | PRODUCT |
|---|---|---|---|
| 지원자 | P2-1·P2-2·P2-3 종료(잔여 명시) | **없음** | **OPEN** |
| 관리자 | P1-2~P1-7 종료(DEVICE 대기) | **없음** | **OPEN** |
| 서브관리자 | 권한 계약 CODE · 전환 RENDER 종료(P3-1) · **계약 진입 무안내 pop 수정**(P3-3) | **없음** | **OPEN** |
| 슈퍼관리자 | shell 11/11 · 내용 RENDER 종료(P3-2) · ERROR≠EMPTY 3건 + **행동 직전 식별자·단위 3건**(P3-3) 수정 | **없음** | **OPEN** |

기존 잔여는 **새 VJ 번호로 재등록하지 않는다** — 기존 ID 에 VJ 를 연결한다
(매핑표는 `docs/r7-gap02-product-value-criteria.md` §2).

## 3. 소유자별 미결 (완료 선언 금지 항목)

| 항목 | 소유 | 상태 |
|---|---|---|
| Staffing 11TO/21업무 카운터 보정 | 사용자 결정 | **DEFERRED** |
| Staffing O08 | P1-2 | DEVICE PENDING |
| 계약의 법률상 사후 정비 정책 | P16-C | **OPEN** |
| `[R7-P1-6-RESIDUAL-DAYS-FIELD-NAMING]` | P16-S | 유지보수 메모(표시 단위는 정상) |
| `[R7-P1-7-RESIDUAL-STATS-HOP-GESTURE]` | P17-X | 월 막대 탭은 fl_chart 콜백 — DEVICE 에서 확인 |
| ~~`[R7-P2-RESIDUAL-USER-SHELL-UNIFY]`~~ | P2 → **P3-4 CLOSED(CODE/RENDER)** | 네 기능은 `AppPageScaffold` 의 `actions`+`bottomNavigationBar` 로 caller 가 넘기면 된다(관리자 화면들이 이미 그 방식). 다섯 곳 전환, 기능 보존 확인(SHU-1~7). **scaffold 파일은 남겨 둔다** · DEVICE·USER 는 OPEN |
| `[R7-P2-1-RESIDUAL-TAB-DESTINATIONS]` | P2 | 일자리·일정·MY 탭 **내부** 화면군 |
| ~~`[R7-P2-1-RESIDUAL-HOME-NIGHT-SHIFT-CHECKOUT]`~~ | P2 | **CLOSED** — 퇴근 카드 신설 |
| ~~`[R7-P2-1-RESIDUAL-ATTENDANCE-SCREEN-LOCAL-MIDNIGHT]`~~ | P1-3 temporal | **CLOSED** — KST 로 통일 |
| ~~`[R7-P2-1-RESIDUAL-INCOME-MONTH-LOCAL]`~~ | P21-H | **CLOSED** — KST 로 통일 |
| `[BLOCKER-P2-HOME-INCOME-MONTH-LOCAL]` | P2 | CODE/행동/RENDER 수용 · DEVICE 대기 |
| `[BLOCKER-P2-JOBTAB-PARTIAL-AS-EMPTY]` | P2-2 | CODE/행동/RENDER 수용 · DEVICE 대기 |
| ~~`[R7-P2-2-RESIDUAL-POSTING-DETAIL-RENDER]`~~ | P2-2 후속 | **CLOSED** |
| `[BLOCKER-P2-POSTING-SLOT-DATE-LOCAL]` | P2-2 후속 | CODE/행동/RENDER 수용 · DEVICE 대기 |
| ~~`[R7-P2-2-RESIDUAL-APPLY-RESULT-RENDER]`~~ | P22-A → **A1 후속 CLOSED(격리 CODE/행동/RENDER)** | 원인 정정: 세 초기 읽기가 플랫폼 채널을 지나고 `testWidgets` 가짜 시계가 그 future 를 돌리지 않았다(제품 결함 아님). `ApplyWorkReads` 로 카드 도달(ARR-1~7), `ApplyWorkSubmit` 으로 네 결과·중복 탭 렌더(APR-1~9). **실제 서버 전이·서버 중복 방지는 NOT SEEN** · VJ01 PRODUCT **OPEN** |
| `[R7-P2-3-VERIFY-AVAILABILITY-COMPREHENSION]` | P2-3 | 발견성·이해 과제는 실제 사용자 관찰로만 닫는다 |
| ~~`[R7-P2-2-RESIDUAL-MY-APPLICATIONS-RENDER]`~~ | P2-2 후속 | **CLOSED** |
| `[R7-P2-2-RESIDUAL-POSTING-FCM-GESTURE]` | P2-2 | FCM → 공고 상세 제스처 NOT SEEN |
| `[BLOCKER-P2-HOME-DEST-DATE-MISMATCH]` | P2 | CODE/행동/RENDER 수용 · DEVICE 대기 |
| `[BLOCKER-P2-HOME-LONGTERM-TODAY-CTA]` | P2 | CODE/행동 수용 · DEVICE/PRODUCT 대기 |
| `[BLOCKER-P2-HOME-CROSS-UID-STALE-DATA]` | P2 | CODE/행동 수용 · DEVICE/PRODUCT 대기 |
| 대비·터치영역 수치 | P4 | 미측정 |
| radius 혼재(V4) | POLISH | 미수정 |

## 4. 화면 shell 전환 현황 (실측 기준)

`grep -c "GradientScaffold("` 로 **실제 호출만** 센다(파일명 grep 은 주석을 센다).

| 트리 | 실제 `GradientScaffold(` | 비고 |
|---|---|---|
| `lib/screens/business_admin/` | **0** | 주석에만 이름이 남아 있다 |
| `lib/screens/super_admin/` | **0** | P1-6 에서 6, P1-7 에서 5 전환 |
| `lib/screens/common/settings_screen.dart` | **0** | P3-4 에서 지원자 경로도 flat. 역할 차이는 제목·우상단 액션·계약 바로 남는다 |
| `lib/screens/user/` | **0** | `attendance_check` · `interim_settlement_request` · `my_reviews` · `subadmin_leave`. `apply_prerequisites` 는 **P2-2 에서 전환 완료**(3축 실측 후 순수 교체). 가운데 둘 + `attendance_check` 는 shell `onRefresh` 를 쓴다 |

**죽은 화면은 없다.** `lib/screens` 아래 화면 위젯 79개 전부 외부 참조가 있다(2026-09-28 실측).
`gradient_scaffold.dart` 는 **실제 사용처 0**(P3-4). 그래도 **삭제하지 않았다** — 호출부 0 은
제품 성과가 아니고 DEVICE 확인 전이다. 파일 머리말의 "홈·일정·일자리와 동일한 디자인 언어"는
이미 거짓이라 현재 사실로 고쳤다.

## 5. 반복 금지 (반례 없이는 재감사하지 않는다)

- 급여 네 상태 전이·write-set·scoped refresh·멱등(P1-5 + R8)
- 계약 서명 흐름 `pending_employer → pending_worker → completed`
- 문서 승인 버전·권한·민감정보(PII-DOC), R5 권한 검증
- 근태 관계 건수·날짜 계약(P1-3), 홈 목적지 context(P1-4)
- 통계 집계 의미·필터·fail-closed(P16-S)
- 지원자 홈 Hero 술어·늦은 응답 가드·4탭 뒤로 경로(P2-1)
- 홈 CTA entity key 표·상태 분류·FCM 대상 권한(P2-1 후속)
- 자정 넘긴 근무의 퇴근 자격 술어·경계 9종(P2-1 잔여)
- 홈↔출퇴근 화면의 KST 날짜 일치(P2-1 잔여) — 두 화면 모두 `toKstDate` 기준
- 수입 월의 KST 기준(P2-1 최종) — `FormatHelper.isSameKstMonth` 한 벌, 서버 KST 슬라이스와 동일
- 일자리 탭의 부분 결과≠없음·선택 날짜 전달(P2-2)
- 공고 상세의 슬롯 날짜 KST 매칭·표시, 내 지원 상태·사유·카운트(P2-2 후속)
- FULL/마감이 기존 약속을 끝내지 않음·상세 뒤로의 조건 유지(P2-2 최종, NO PATCH)
- 근무가능일은 초대의 절반이다 — `inviteEnabled`+`inviteRegionKeys` 가 없으면 후보에 잡히지 않는다(P2-3)
- 다만 날짜는 **초대 전용이 아니다** — `_dispatchToMatchNotifications` 가 초대 설정과 무관하게 공고 알림을 보낸다(P2-3 후속)
