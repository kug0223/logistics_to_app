# R7-P1-2 후속 — 확정 명단 행 320dp·큰 글자 잘림 수정

> 작성: 2026-09-29 KST · 기준 HEAD `ea77b46` (tracked dirty 0 · 사용자 untracked 8건 보존)
> owner: `[R7-P1-2 DEVICE.1H.1]` · 재현 테스트 P3-2 `IHK-5`
> 실기기 P4-1 은 보류. **이미 재현된 CODE·RENDER 결함만** 처리한다.

---

## 1. 좁은 READ — 무엇이 어디서 넘쳤나

### 공용 행의 실제 사용처

| 사용처 | 파일 |
|---|---|
| 일자별 인력 현황 | `dialogs/day_applicants_dialog.dart:1720` |
| 업무별 지원자 | `dialogs/work_applicants_dialog.dart:2143` |

**중요:** `ApplicantRowSurface` 자체는 **112줄짜리 표면 래퍼이고 Row 가 하나도 없다.**
넘친 것은 이 화면이 그 안에 넣는 **자식 레이아웃**이다. 그래서 이번 수정은
**전부 `day_applicants_dialog.dart` 안**이고, `work_applicants_dialog` 는
**한 글자도 바뀌지 않았다**(공용 소비자 영향 0).

### 재현 — production 부모 그대로

테스트 단독 320px 박스를 쓰지 않았다. `DayApplicantsDialog` 를 세우고
물리 폭 320dp·배율 2.0 을 주어 화면이 스스로 만드는 제약을 그대로 썼다.
넘친 Row 의 실제 제약은 `0<=w<=215.7 ~ 226.2` 로, 320dp 화면 안에서
다이얼로그 패딩·좌측 rail 을 뺀 값이다.

fixture 를 갈라 각 넘침의 소속을 특정했다(슬롯행만 → 0건).

| 행/상태 | 표시해야 할 것 | 넘침 위치·크기 | 실제 CTA | 부모/스크롤 제약 |
|---|---|---|---|---|
| **표본1** 확정(초대 수락) | 이름 · `초대 수락 · 확정` · 계약 배지 | ① 초대 응답 줄 **62px** ② 계약 배지 칩 **14px** ③ 확정 행동 줄 **104px** | `계약서 작성` · `확정취소` | 그룹 카드 Column → `ApplicantRowSurface` → ListView |
| **표본2** 확정(직접 지원) | 이름 · 계약 배지 | ② **14px** ③ **104px** (초대 구역 없음) | 동일 | 동일 |
| **표본3** 대기(PENDING) | 이름 · 묶음 머리줄 수치 | ④ 묶음 머리줄 **6px** ⑤ 대기 행동 줄 **195px** | `다른 업무 제안`·`거절`·`확정` | 동일 |
| **정상 대조** 초대 응답만(확정 0) | `초대 거절`·`초대 철회` | **0건** — 라벨이 짧아 넘치지 않는다 | — | 동일 |

**표본3 은 IHK-5 의 세 표본이 아니다.** 원인을 좁히다 같은 카드에서 함께 나온
것이라 범위를 정확히 적어 둔다(아래 §2 에서 같은 고침으로 해결됐다).

### 넘침이 경고로 끝나지 않았다

수정 전 `ARO-5` 가 FAIL 했다 — **대기 행의 버튼 세 개 중 하나가 잘려 사라졌다.**
관리자가 그 자리에서 할 수 있는 일이 하나 줄어 있었다는 뜻이다.

---

## 2. 최소 PATCH — 값을 지우지 않고 접는다

모두 `day_applicants_dialog.dart`. **확정 상태·정원·권한·시간 계산은 건드리지
않았다** — 레이아웃만 바꿨다.

| # | 자리 | 무엇이 문제였나 | 고침 |
|---|---|---|---|
| ① | `_buildInviteRow` 상태 배지 | 고정 폭 `Container`. `초대 수락 · 확정` 이 길어 행 밖으로 | `Flexible` 로 감싸 **남은 폭 안에서 두 줄로 흐르게**. 라벨을 줄이지 않는다 |
| ② | `_iconChip` (계약 배지) | `Row(min)` 안의 `Text` 가 Wrap 남은 폭 초과 | `Flexible(child: Text)` — `계약서 작성 필요` 전체가 남는다 |
| ③ | 확정 행동 줄 | `Row(mainAxisAlignment: end)` 고정 | `Wrap(alignment: end, spacing 8, runSpacing 6)` + 인라인 `SizedBox(width: 8)` 제거 |
| ⑤ | 대기 행동 줄 | 같은 구조 | 같은 `Wrap` 전환 |
| ④ | 묶음 머리줄 통계 | `Row(min)` 고정. 아이콘+수치 세 쌍 | `Flexible(child: _buildGroupStats)` + `_buildGroupStats` 를 **`Wrap`** 으로. 아이콘과 그 수치는 `_statGroup` 으로 **한 덩어리 유지**(떨어지면 뜻을 잃는다). 수치를 합치거나 지우지 않는다 — `지원`과 `초대`는 다른 사실이다 |

**하지 않은 것:** 핵심 이름·상태·행동 숨기기, `textScaler` 무효화, 의미 있는
값에 ellipsis 붙이기, 버튼을 행 밖으로 밀기, 인접 표적 겹치기.
`IdCardHelper.buildStatusBadge`(공용)는 이번 표본에서 넘치지 않아 **건드리지 않았다** —
공용 소비자 영향을 0으로 유지한다.

---

## 3. 수정 후 — 같은 부모·같은 폭·같은 배율

| 셀 | 확인한 것 |
|---|---|
| **ARO-1** | 표본1 320dp×2.0 — **넘침 0** |
| **ARO-2** | 표본2 320dp×2.0 — **넘침 0** |
| **ARO-3** | 표본3 320dp×2.0 — **넘침 0** |
| **ARO-4** | 이름 `근로자 u1` · `초대 수락 · 확정` · `초대 거절` · `초대 철회` · `계약서 작성` · `확정취소` · `계약서 작성 필요` 가 **그대로 읽힌다** |
| **ARO-5** | 대기 행 버튼 **셋 모두** 남는다(`다른 업무 제안`·`거절`·`확정`) — 버튼만 세도록 `widgetWithText(InkWell, …)` 로 좁혔다(머리줄에도 `확정` 라벨이 있다) |
| **ARO-6** | `확정취소` 를 **실제로 탭** → 확인 단계까지. **실제 writer 미실행** |
| **ARO-7** | 높이 640 으로 좁혀도 `ensureVisible` 로 마지막 행동에 **닿는다** |
| **ARO-C** | 360dp·412dp × 1.3 — 넘침 0 (정상 대조) |
| **ARO-C0** | 390dp × 기본 배율 — 넘침 0 (정상 대조) |

### 전후 대조

| | 결과 |
|---|---|
| 수정 전 | **ARO-1·2·3 FAIL**(62/14/104 · 14/104 · 6/195) + **ARO-5 FAIL**(버튼 하나 소실) |
| 수정 후 | **ARO 10/10 PASS** |

### IHK-5 갱신

P3-2 의 IHK-5 는 `expect(tester.takeException(), isNotNull)` 로 **잘림이 있는
상태를 사실로 고정**하고 있었다. 지우지 않고 **정상 기대값으로 옮겼다**
(`isNull` + 이름도 `…예외 없이 그려진다` → `…확정 명단 행이 넘치지 않는다`).
**옛 테스트의 PASS 를 결함 해결로 세지 않았다** — 해결의 증거는 ARO 쪽이다.

---

## 4. 판정

| 축 | 결과 |
|---|---|
| **CODE** | production 사용처 2곳 중 `day_applicants` 만 수정. domain/callback 계약 유지(버튼 라벨·onTap·표시 조건 동일) |
| **RENDER** | 세 표본 + 정상 대조에서 **예외 0**, 핵심 정보·CTA 보임, 목록 스크롤로 도달 |
| **행동** | `확정취소` 실제 탭 → 확인 단계. **초대·확정취소·거절 등 운영 writer 미실행** |
| **DEVICE** | **NOT SEEN 유지.** P4-1 관찰표(A-1)로 실기기·계정·자료 준비 후 같은 표본 재검증 |
| **USER/PRODUCT** | 관찰 없음. **관리자 업무가 편해졌다고 말하지 않는다** |

---

## 5. 증거

| 항목 | 값 |
|---|---|
| 기준 HEAD → 종료 HEAD | `ea77b46` → 이 커밋 |
| 변경 파일 | `lib/screens/business_admin/dialogs/day_applicants_dialog.dart` (유일한 production 파일) |
| 신규 테스트 | `test/applicant_row_overflow_test.dart` **10건**(ARO-1~7, C×2, C0) |
| 갱신 테스트 | `test/invite_handoff_same_key_truth_test.dart` — IHK-5 기대값 이동 |
| 영향집합 | **1264건 실행 / 실패 3건 — 전부 기준선 같은 이름 실패** |
| 기준선 실패 대조 | `mixed_staffing_parity 14-d`(소스 문자열 닻, HEAD 에서도 FAIL) · `noshow_replacement_cross_slice` 2건(오늘/과거 시각 의존, HEAD 에서도 FAIL) — 세 건 모두 **수정 전 파일로 되돌려 같은 이름으로 FAIL 함을 확인** |
| 정적 분석 | `flutter analyze lib test` **No issues** |
| 공용 소비자 | `work_applicants_dialog` **무수정** · `ApplicantRowSurface` **무수정** · `IdCardHelper` **무수정** |

### 덤으로 고친 시한부 fixture

`invite_handoff_same_key_truth_test` 의 `kDate` 가 `2026-09-29` 로 못박혀 있었는데,
**그날이 오늘이 되자** IHK-4 의 `출근 예정이에요` 분기를 벗어나 깨졌다.
제품 결함이 아니라 테스트가 시한부였다. HEAD 로 되돌려 같은 실패를 확인한 뒤
날짜를 **오늘 기준 +3일**로 밀고, 날짜 문자열을 못박던 IHK-2 의 기대도
시간대만 확인하도록 좁혔다.

---

## 6. 그대로 둔 것

P4-1 의 shell·통계·권한 **DEVICE NOT SEEN**, P1-5 급여 DEVICE,
P2-2 A1 초기 읽기/지원 결과, VJ02 날짜 저장, P23-N 일정 복귀,
Home CTA 9개·FCM, 실제 mutation, Staffing DEFERRED/O08, 계약 사후 정책,
네 역할 USER/PRODUCT·출시 gate — **전부 기존 owner**.
