# ALfit Product Continuity Index

> 세션·단계가 바뀌어도 **무엇이 어디까지 닫혔고 무엇이 누구 소유인지** 한 장에서 잇는다.
> 세부 근거는 각 감사 문서에 있고 이 파일은 **포인터와 상태**만 유지한다.
> 마지막 갱신: 2026-09-28 · 기준 HEAD: R7-P2-2 A1 잔여(지원 버튼 도달) 커밋

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
| P2 나머지 | — | 지원자 화면군 여섯 묶음 결산 완료(PRODUCT 는 OPEN) | — | — |
| P4 | 대비·터치영역 정량 계측 | 미착수 | — | **미측정** |

## 2.5 네 역할 PRODUCT 결산 (GAP-02)

CODE/RENDER 종료가 제품 가치 종료가 **아니다**. 실사용자 관찰이 없으면 OPEN 이다.

| 역할 | CODE/RENDER | USER OBSERVATION | PRODUCT |
|---|---|---|---|
| 지원자 | P2-1·P2-2·P2-3 종료(잔여 명시) | **없음** | **OPEN** |
| 관리자 | P1-2~P1-7 종료(DEVICE 대기) | **없음** | **OPEN** |
| 서브관리자 | 권한 계약 CODE | **없음** | **OPEN** |
| 슈퍼관리자 | shell 11/11 · 일부 CODE only | **없음** | **OPEN** |

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
| `[R7-P2-RESIDUAL-USER-SHELL-UNIFY]` | P2 | **실측 정정** — `GradientScaffold` 는 `onRefresh` 외에 알림 벨·홈 버튼·미서명 계약 바를 더 준다. `AppPageScaffold` 에 없으므로 최소 전환 불가. 실제 사용처 0 전 공통 scaffold 삭제 금지 |
| `[R7-P2-1-RESIDUAL-TAB-DESTINATIONS]` | P2 | 일자리·일정·MY 탭 **내부** 화면군 |
| ~~`[R7-P2-1-RESIDUAL-HOME-NIGHT-SHIFT-CHECKOUT]`~~ | P2 | **CLOSED** — 퇴근 카드 신설 |
| ~~`[R7-P2-1-RESIDUAL-ATTENDANCE-SCREEN-LOCAL-MIDNIGHT]`~~ | P1-3 temporal | **CLOSED** — KST 로 통일 |
| ~~`[R7-P2-1-RESIDUAL-INCOME-MONTH-LOCAL]`~~ | P21-H | **CLOSED** — KST 로 통일 |
| `[BLOCKER-P2-HOME-INCOME-MONTH-LOCAL]` | P2 | CODE/행동/RENDER 수용 · DEVICE 대기 |
| `[BLOCKER-P2-JOBTAB-PARTIAL-AS-EMPTY]` | P2-2 | CODE/행동/RENDER 수용 · DEVICE 대기 |
| ~~`[R7-P2-2-RESIDUAL-POSTING-DETAIL-RENDER]`~~ | P2-2 후속 | **CLOSED** |
| `[BLOCKER-P2-POSTING-SLOT-DATE-LOCAL]` | P2-2 후속 | CODE/행동/RENDER 수용 · DEVICE 대기 |
| `[R7-P2-2-RESIDUAL-APPLY-RESULT-RENDER]` | P22-A | **NOT SEEN** — 원인 확정: `FirestoreService` 하드 싱글턴 + extension 정적 디스패치로 초기 조회가 격리에서 끝나지 않아 로딩 고착(ABR-2). **격리 실행 불가**, production 경로 결함 아님. 종료 조건 = 주입점/읽기 경계 분리 |
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
| `lib/screens/common/settings_screen.dart` | 1 | **USER 경로용** — 관리자 역할은 `AppPageScaffold` |
| `lib/screens/user/` | **4** | `attendance_check` · `interim_settlement_request` · `my_reviews` · `subadmin_leave`. `apply_prerequisites` 는 **P2-2 에서 전환 완료**(3축 실측 후 순수 교체). 가운데 둘 + `attendance_check` 는 shell `onRefresh` 를 쓴다 |

**죽은 화면은 없다.** `lib/screens` 아래 화면 위젯 79개 전부 외부 참조가 있다(2026-09-28 실측).
`gradient_scaffold.dart` 는 남은 6화면이 전환되면 사용처 0이 되어 폐기 대상이 된다.

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
