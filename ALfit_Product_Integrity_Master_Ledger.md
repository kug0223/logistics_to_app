# ALfit Product Integrity Master Ledger

> **제품이 사용자에게 거짓을 말하지 않는가**를 기준으로 누적하는 장부.
> 각 줄은 단계(ID) · 무엇이 틀렸는가 · 무엇으로 고쳤는가 · 증거 종류를 담는다.
> 세부 근거는 `docs/r7-p1-admin-design-audit.md`, 연속성·소유는
> `ALfit_Product_Continuity_Index.md`.
> 마지막 갱신: 2026-09-28 (R7-P2-1 잔여)

## 0. 이 장부가 지키는 불변식

| 불변식 | 뜻 |
|---|---|
| **ERROR ≠ ZERO** | 조회 실패를 0건·0원으로 말하지 않는다 |
| **UNKNOWN ≠ EMPTY** | 모르는 것을 "없다"로 말하지 않는다 |
| **NO_PERMISSION ≠ ERROR** | 권한 없음과 실패를 섞지 않는다 |
| **FULL ≠ DONE** | 정원 충족과 처리 완료를 섞지 않는다 |
| **단위는 원천이 정한다** | 건·명·일·원·회를 화면이 임의로 바꾸지 않는다 |
| **하나의 owner** | 같은 계약의 수치를 두 곳에서 계산하지 않는다 |

## 1. 확정 판정 원장

| # | 단계 | 무엇이 틀렸는가 | 고친 방식 | 증거 |
|---|---|---|---|---|
| 1 | P1-3 | 당일명단 4개 진입이 달력일/기기 자정을 섞어 `workDateMs`·문서 id 가 흔들렸다 | `kstDayKeyOfCivil` 도입, 37곳 치환, 저장은 KST 자정 instant | CODE 10 · RENDER 7 |
| 2 | P1-3 | 근무 건수를 `명` 으로 불렀다(한 사람이 같은 날 두 근무 가능) | 화면의 모든 수치를 `건` 으로 | CODE 6 |
| 3 | P1-3 | 합쳐진 구 문서 그룹에서 한 사람의 두 관계가 구별되지 않았다 | 혼합 그룹에만 `업무명 · 예정 시간` 행 문맥 | RENDER 3 |
| 4 | P1-4 | `필요`(정원)와 `더 필요`(모집 가능 부족)가 같은 단어라 `5-0=5` 로 읽혔다 | 정원 축을 `N명 중 M명 확정` 으로(같은 화면의 기존 표현) + 조건부 범위 보조 줄 | CODE · RENDER 4 |
| 5 | P1-4 | 할 일 4곳이 지원서·계약서·관계 수를 `명` 으로 불렀다 | 원천 단위 `건` 으로 | CODE · RENDER |
| 6 | P1-4 | 늦은 응답 가드가 없어 낡은 값이 현재 값을 덮었다(사업장 전환 포함) | loader 별 단조 seq | 순서 실행 4 + 가드 제거 대조 |
| 7 | P1-4 | 투어 판정 future 가 데이터 loader 를 막아 영구 spinner 가 가능했다 | 사업장 → loader → 투어(독립·실패 삼킴) | 시나리오 3 + 소스 4 |
| 8 | P1-5 | 출근 집계 실패가 미이체를 0/줄 삭제로 만들어 **다 이체된 달**처럼 보였다 | 실패를 상태로 → `확인 못함` | RENDER 6 |
| 9 | P1-5 | 근무자 목록 **조회 실패**를 `집계 없음` + 서버 재집계 권유로 말했다 | 실패 분리 + `다시 시도` | RENDER |
| 10 | P1-5 | `N일 근무`·`근무일수` 가 확정된 **근무 건수**였다 | `확정 근무 N건` | CODE · RENDER |
| 11 | P1-5 | 지급 예정일 월별 분기가 기기 local 날짜를 만들어 서버와 9시간·비KST 기기에서 하루 어긋났다 | 전부 `DateTime.utc` (서버와 동일 모양) | CODE + 기존 실패 23건 복구 |
| 12 | P1-5 | 월 카드 높이 고정·헤더 Row flex 부재로 배율·긴 금액에서 잘렸다 | 배율 반영 높이 · `Expanded`/`Wrap` | RENDER |
| 13 | P1-5 후속 | 같은 `미이체` 를 원장과 projection 두 곳이 계산해, 이체 취소 후 복귀 시 낡은 값이 확정 사실로 앉았다 | **owner = 원장**, 공유 reading 하나, 상한 도달은 fail-closed | RENDER 4 + 수정 전 재현 |
| 14 | P1-6 | 계약 조회 실패가 `미발송 계약서 없음`(체크 아이콘) = **완료 주장**이 됐다 | 실패 상태 분리 + 재시도, 경계 신설 | RENDER 4 · CODE 5 |
| 15 | P1-6 | 관리 탭이 파란 구형 shell 이었다(역할 공유 화면) | 관리자 역할만 flat shell, 프로필은 대비 유지 카드로 | RENDER 4 |
| 16 | P1-6 | 탈퇴 점검 블록이 상태색을 하드코딩했다 | `AppColors` warning/success 로 | CODE |
| 17 | P1-7 | super-admin 5화면의 흰 탭 라벨·흰 헤더 아이콘이 밝은 배경에서 사라질 수 있었다 | 전환과 함께 대비를 옮김(flat TabBar 계약), 헤더 새로고침 → `actions` | RENDER 3 · CODE |
| 18 | P1-7 | 문서 관리의 `확인 완료` 만 raw 초록이라 같은 화면에서 완료가 두 색이었다 | `AppColors.success` | CODE |
| 19 | P1-7 후속 | 통계·월상세의 flex 없는 Row 5곳이 큰 수·긴 라벨·배율에서 잘렸다(53·42·26·4.7·275·110px) | Flexible/Wrap — 수치·범례·칩을 없애지 않음 | RENDER 7 |
| 20 | P2-1 | 지원자 홈 Hero 가 `workDate == today` 로 오늘 근무를 판정해, **계약 시작일이 아닌 날 일하는 장기 근무자에게 출퇴근 CTA 가 사라졌다** | 같은 화면·출근 화면과 같은 canonical 술어 `isWorkingOnDate` | RENDER 4 + 수정 전 대조 |
| 21 | P2-1 (후속 정정) | 홈 로드가 늦은 응답을 그대로 반영했다. **실제 도달 경로는 `unawaited` 꼬리(연장 제안·보완 요청)** — 사라진 제안이 낡은 응답으로 되살아났다. 계정 전환은 `AuthWrapper` 가 State 를 파괴하므로 production 재현 경로가 **아니다**(첫 보고 문장 정정) | seq + uid 가드를 state 반영 3곳에 | UHR-15 + seq 제거 대조 |
| 22 | P2-1 | 수입 행·지원 준비 진행도·`SectionHeader` 액션에 flex·상한이 없어 좁은 화면·큰 배율에서 잘렸다(17·36·83·57·31px) | 금액·진행도·목적지 문구를 **줄이지 않고** 줄바꿈 | RENDER 6조합 |
| 24 | P2-1 잔여 | 자정을 넘겨 계속되는 근무의 **퇴근 진입점이 Home 에 없었다** — 출퇴근 화면은 그 기록을 들고 있는데 홈 Hero 는 오늘만 봤다. 응답이 없으면 `missed_checkout` 으로 자동 처리된다 | 목적지와 **같은 제외 술어**로 판정하는 독립 카드(Hero 앞, 둘 다 표시). 자격은 "어제 확정"이 아니라 **출근했고 퇴근이 남은 진행 중 기록** | 경계 9종 + 6조합 + 카드 제거 대조 |
| 23 | P2-1 후속 | 근태 조회 실패가 `_homeLoadFailed` 에 잡히지 않아 수입이 **`0원` · "아직 이번 달 수입이 없어요"** 로 보였다 — 못 읽은 달을 번 돈이 없다고 말했다 | `_attendancesFailed` → 두 금액 `확인 못함` + 재시도, 빈 상태 문구 차단 | UHR-12 + 제거 대조 |

## 2. NO PATCH — 근거를 남긴 판정

| 단계 | 항목 | 근거 |
|---|---|---|
| P1-5 | 이체/취소가 실제 송금으로 오인되는 문구 | 두 다이얼로그가 "실제 은행 이체를 완료한 건만" · "실제 은행 이체는 취소되지 않습니다" 를 명시 |
| P1-5 | 연체·당일 판정 | 저장값과 화면이 같은 `toKstDate` 정규화를 쓴다 |
| P1-6 | 통계 단위·모집단·실패 | `확인 불가`/`조회 실패`, `limitReached` fail-closed, 드릴다운에 사업장·필터·연·월 동반, 근무일 = 고유 날짜 |
| P1-7 | `AppSummaryHeader` 채택 0 | 채택 횟수는 결함 근거가 아니다. `AppStatusCard` 는 **컴포넌트 자체가 없다**(감사표의 "채택 0" 표현 정정) |
| P1-7 | 문서 관리 중립 회색 7곳 | 상태·행동 의미가 없다. 색 상수 개수는 결함 근거가 아니다 |
| P1-7 | 문서 관리 `mismatch`/`review_required` 색 | 폐기된 상태라 서버가 값을 만들지 않고 호출부도 넘기지 않는다 — **도달 불가 분기** |
| P2-1 | 지원자 화면에 관리자 capability 덧씌움 | `lib/screens/user/` 에 `canManage*`·`MemberPermissions` 0건. 남은 `isSubAdmin` 은 역할 전환 토글이다 |
| P2-1 | 수입 "월 선택 bottom sheet" 미구현 주장 | 시트는 `IncomeDetailScreen` 안에 있다(`DialogHelper.showSheet`, 즉시 적용). 홈 헤더는 그 진입이다 |
| P2-1 | 홈 Hero 와 날짜 탐색 동시 노출 | 설계상 독립 상시 섹션(소스 주석 명시) |
| P2-1 후속 | 홈 로드 **본문**의 같은 계정 순서 역전 | `_isLoadingHomeData` 가 재진입을 막아 본문은 겹치지 않는다(앱 복귀 경로로 재측정). 겹치는 것은 `unawaited` 꼬리뿐이고 그쪽은 결함 #21 로 고쳤다 |
| P2-1 후속 | 홈의 NO_PERMISSION 상태 | 홈의 읽기가 전부 **자기 uid 스코프**+공개 데이터라 도달 불가. 억지 fixture 를 만들지 않았다 |
| P2-1 후속 | CTA 가 다른 사람/근무를 여는가 | 12경로 중 스냅샷을 넘기는 것은 추천 카드 하나뿐, 나머지는 키·계정 스코프라 목적지가 다시 읽는다. `출근하기` 는 인자 없이 **같은 canonical 술어**로 대상을 맞춘다 |
| P2-1 잔여 | 달 경계(1일)의 어제 근태 | 이번 달 조회에 안 들어온다 → 그날만 **같은 CF·같은 self-uid 계약**으로 지난달을 한 번 더 읽는다(기존 `Future.wait` 에 합류, 왕복 증가 없음). polling·listener·새 권한 없음 |
| P2-1 잔여 | 오늘 진행 중인 근무에도 퇴근 카드를 띄울 것인가 | 아니다 — 오늘은 Hero 의 몫이다. 자정 전 Hero / 자정 후 카드로 **빈틈도 중복도 없다**(UHR-26) |
| P2-1 후속 | FCM payload 가 타인 데이터를 여는가 | 근로자 목적지 4종이 인자를 받지 않는다(현재 계정으로 재조회). 권한 타입은 canonical dispatcher 경유 — 기존 R5.1 증거 |

## 3. 미결 (이 장부에서 닫히지 않은 것)

| 항목 | 소유 | 종료 조건 |
|---|---|---|
| Staffing 11TO/21업무 보정 | 사용자 | 결정(현재 DEFERRED) |
| Staffing O08 | P1-2 | DEVICE |
| 계약 법률 사후 정비 | P16-C | 정책 결정 |
| `[R7-P2-RESIDUAL-USER-SHELL-UNIFY]` | P2 | 3축 실측 **완료** → 전환(셋은 `onRefresh` 설계 먼저) → `gradient_scaffold` 폐기 판단 |
| `[R7-P2-1-RESIDUAL-TAB-DESTINATIONS]` | P2 | 일자리·일정·MY 탭 **내부** 화면군 |
| ~~`[R7-P2-1-RESIDUAL-HOME-NIGHT-SHIFT-CHECKOUT]`~~ | P2 | **CLOSED** — 퇴근 카드 신설(결함 #24). `[BLOCKER-P2-HOME-NIGHT-SHIFT-CHECKOUT-MISSING]` 은 CODE/행동/RENDER 수용 · DEVICE 대기 |
| `[R7-P2-1-RESIDUAL-ATTENDANCE-SCREEN-LOCAL-MIDNIGHT]` | P1-3 temporal | 목적지가 `todayStart`/`yesterday` 를 **기기 로컬 자정**으로 만든다. 홈은 KST 정규화 — 비-KST 기기에서 하루 어긋날 수 있다. 이번에 건드리지 않았다 |
| `[BLOCKER-P2-HOME-LONGTERM-TODAY-CTA]` | P2 | CODE/행동 수용 — DEVICE/PRODUCT |
| `[BLOCKER-P2-HOME-CROSS-UID-STALE-DATA]` | P2 | production cross-uid 재현 주장 **철회**(AuthWrapper 가 State 파괴). 같은 uid `unawaited` 꼬리 역전(UHR-15)은 별도 CODE 수정으로 재분류 |
| `[BLOCKER-P2-HOME-ATTENDANCE-FAILURE-AS-ZERO-INCOME]` | P2 | UHR-12 범위 CODE/RENDER 수용 — DEVICE 대기 |
| `[BLOCKER-P2-HOME-NIGHT-SHIFT-CHECKOUT-MISSING]` | P2 | CODE/행동/RENDER 수용 — DEVICE/PRODUCT |
| `[R7-P1-6-RESIDUAL-DAYS-FIELD-NAMING]` | P16-S | 내부 필드명(표시 단위는 정상) |
| ~~`[R7-P1-7-RESIDUAL-STATS-CONTENT-RENDER]`~~ | P17-S | **CLOSED** — 원인은 서비스의 `Future.timeout(15s)`(production dispose 결함 아님). reader 주입으로 7건 렌더 |
| `[R7-P1-7-RESIDUAL-STATS-HOP-GESTURE]` | P17-X | 월 막대 탭이 fl_chart 터치 콜백이라 위젯 테스트로 누를 수 없다 → DEVICE |
| 대비·터치영역 수치 | P4 | 정량 계측 |
| 각 단계 DEVICE | 각 owner | 실기기 확인 |
