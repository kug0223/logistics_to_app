# [OPEN-CONTRACT-MONTHEND] 계약 기간 월말 계산 감사

- 기준 HEAD: `10d57bb` (착수 시 tracked dirty 0, 사용자 untracked 8건 보존)
- 범위: `1/31 + 1개월` 종료일이 계약서 약정·코드 계산·저장값·화면 표시·효력
  판정에서 일치하는지. 실기기·APK 제외.
- 결과: **식은 고치지 않았다(NO PATCH).** 단 이슈의 전제와 owner 를 정정했고,
  불일치를 실행 가능한 반례로 고정했다.

---

## 0. 먼저 — 이 이슈의 전제가 좁았다 (정정)

앞 회차에 남긴 질문은 "`1/31 + 1개월` 의 만료일이 `2/27`(구현) 인가
`2/28`(민법 160③) 인가" 였다. **두 전제가 틀렸다.**

1. **`2/27` 은 계약 만료일이 아니다.** `TOModel.computeContractEndDate` 의
   결과는 ① 지원 화면 기간 카드 표시, ② `application.workEndDate` 의
   **최초(PENDING)** 저장값으로만 쓰인다. 확정 시점에 서버가 덮어쓴다.
2. **문제는 월말에 국한되지 않는다.** 클라이언트 식과 서버 식은 **모든**
   기간 유형·모든 기산일에서 어긋난다(최소 1일, 월말 2~4일).

그래서 이 이슈의 owner 는 `computeContractEndDate` 단독이 아니라
**클라이언트·서버 두 식의 parity** 다.

---

## 1. 연결표 — 같은 계약 ID 를 따라간 경로

기산일 `2026-01-31`, `contractPeriodType = '1month'` 기준.

| 단계 | 주체 | 값 | 재계산/저장값 | 증거 |
|---|---|---|---|---|
| 지원 화면 기간 카드 | 클라이언트 | **2026-02-27** | 매번 재계산 | `longterm_apply_sheet.dart:777` `_buildPeriodCard` → `_effectiveEndDate` · `apply_work_dialog.dart:1270` |
| 지원 제출 payload | 클라이언트 | 2026-02-27 | `workEndDateMs` 로 전송 | `apply_work_dialog.dart:2420` · `application_firestore.dart:572` |
| `callableApplyToTO` 저장 | 서버 | 2026-02-27 | **클라이언트 값 그대로** (preset TO 는 `rangeEnd` 가 없어 덮어쓸 원본이 없다) | `index.ts:35326` `effectiveContractWorkEndDate = workEndDate` · `to_model.dart:717` `endDate → null when hasPresetPeriod` |
| `callableConfirmApplication` | 서버 | **2026-03-03** | **덮어쓴다** | `index.ts:28828` `[M2-FIX] 클라이언트 조작값 무시, 항상 서버 TO 기준 계산` → `28831~28839` → `28934` `batchUpdate.workEndDate` |
| 계약서 제2조 (근무 기간) | 클라이언트 | 2026-03-03 | 저장값을 **그대로 찍는다** | `contract_service.dart:875` `contractEnd: … application.workEndDate` → `employment_contract_model.dart:294` `workPeriodText` → `contract_pdf_builder.dart:88` |
| 서명 후 계약 문서 | — | 2026-03-03 | **문자열로 동결** | `employment_contract_model.dart:198` `'contractEnd': contractEnd` (스냅샷 persist) |
| 관리자·지원자 화면 | 클라이언트 | 2026-03-03 | 저장값 | `workPeriodDisplay` → `schedule_card` · `worker_detail_dialog` · `work_applicants_dialog` 등 8곳 |
| 만료 알림 (D-15) | 서버 | 2026-03-03 | 저장값, 재계산 없음 | `index.ts:7426` `expiryDateKST = app.workEndDate` |
| 좌석·근무·종료 효력 | 클라이언트/서버 | 2026-03-03 | 저장값 | `occupiesSeatOn` · `isWorkingOnDate` · `isExitEffectiveOn` (모두 `actualResignDate ?? workEndDate`) |

**즉 근로자는 지원할 때 `2/27 (1개월)` 을 보고 지원하는데, 확정 뒤 계약서와
효력은 `3/3` 이다.**

### 종료일 필드의 의미 — 마지막 유효일(inclusive)

| 근거 | 내용 |
|---|---|
| `ApplicationModel.effectiveEndDate` | 주석 그대로 "이 약속의 **마지막 근무 가능일**" |
| `occupiesSeatOn(day)` | `!end.isBefore(day)` → **end 당일도 좌석을 차지** |
| `isWorkingOnDate` | `target.isAfter(end)` 이면 근무 아님 → end 당일은 근무 |
| `isExitEffectiveOn` | `toKstDate(target).isAfter(end)` → end 다음날부터 종료 효력 |

**'다음 날부터 무효인 시점' 이 아니라 '마지막 유효일' 이다.** 이 의미가
어느 식이 맞는지 판정하는 자다.

### 계약 시작 시각과 계약서의 약정

| 질문 | 답 | 증거 |
|---|---|---|
| 계약 시작이 해당 날짜 0시인가, 서명 시점인가 | **날짜 단위**다. `contractStart = desiredStartDate ?? workDate` 를 `yyyy-MM-dd` 문자열로 찍는다. 시각 성분은 계약서에 없다 | `contract_service.dart:871` · `employment_contract_model.dart:127` |
| 계약서에 기간 계산 조항이 있는가 | **없다.** 제2조는 시스템 고정 섹션이고 `'$contractStart ~ $contractEnd'` **두 날짜만** 출력한다. "N개월" 이라는 기간 단위 약정 문구도, 산식도 본문에 없다 | `employment_contract_model.dart:294` `workPeriodText` · `contract_pdf_builder.dart:84` |
| 템플릿에 만료 관련 조항이 있는가 | 업무위탁계약서 제8조에 "계약 기간 만료" 라는 **해지 사유 열거**만 있다. 기간 계산과 무관 | `contract_template_model.dart:332` |
| 기간 단위 라벨은 어디 있는가 | **화면에만** 있다 — 지원 시트 기간 카드가 `contractPeriodLabel`("1개월")을 날짜와 함께 보여준다. 계약서에는 넘어가지 않는다 | `longterm_apply_sheet.dart:780` |

→ **별도 계약 약정이 없다.** 계약서는 산식을 약정하지 않고 저장된 두 날짜를
표시한다. 따라서 종료일의 정답은 계약서가 아니라 **코드가 정한다** — 그리고
지금 코드가 두 벌이다.

---

## 2. 경계 사례 실측

### 2-A. 전 기간 유형 (기산 `2026-01-01`, 기기 달력 기준)

| 기간 | 클라이언트 | 서버 | 차이 | 실효 기간(시작일 포함) |
|---|---|---|---|---|
| 15days | 2026-01-15 | 2026-01-16 | +1일 | C 15일 / **S 16일** |
| 1month | 2026-01-31 | 2026-02-01 | +1일 | C 31일 / **S 32일** |
| 3months | 2026-03-31 | 2026-04-01 | +1일 | C 90일 / S 91일 |
| 6months | 2026-06-30 | 2026-07-01 | +1일 | C 181일 / S 182일 |
| 1year | 2026-12-31 | 2027-01-01 | +1일 | C 365일 / **S 366일** |

**서버 식에는 `- 1일` 이 없다.** inclusive 의미에서 모든 계약이 약정 기간보다
하루 길다. `15days` 는 16일, `1year` 는 366일이 된다.

### 2-B. 월말 기산 (서버는 clamp 가 없어 이월된다)

| 기산 | 기간 | 클라이언트 | 서버 | 차이 | 민법 160②③ 해석 |
|---|---|---|---|---|---|
| 2026-01-31 (평년) | 1month | 2026-02-27 | **2026-03-03** | 4일 | 2026-02-28 |
| 2028-01-31 (윤년) | 1month | 2028-02-28 | 2028-03-02 | 3일 | 2028-02-29 |
| 2026-01-30 | 1month | 2026-02-27 | 2026-03-02 | 3일 | 2026-02-28 |
| 2026-01-29 | 1month | 2026-02-27 | 2026-03-01 | 2일 | 2026-02-28 |
| 2026-03-31 | 1month | 2026-04-29 | 2026-05-01 | 2일 | 2026-04-30 |
| 2026-08-31 | 6months | 2027-02-27 | 2027-03-03 | 4일 | 2027-02-28 |
| 2028-02-29 (윤일) | 1year | 2029-02-27 | 2029-03-01 | 2일 | 2029-02-28 |
| **2026-05-15 (월중, 정상 대조)** | 1month | **2026-06-14** | 2026-06-15 | 1일 | **2026-06-14** ✔ |

읽는 법:
- **월중 기산에서는 클라이언트 식이 민법 해석과 정확히 일치한다**(해당일이
  있으므로 160② "해당일의 전일" 이 곧 `(start + N개월) - 1일`).
- **클라이언트 식의 결손은 월말 기산 한 경우로 국한된다** — 해당일이 없는
  달에서 clamp 후 `-1일` 을 또 빼서 **하루 짧아진다**(160③ 은 "그 월의
  말일" 이므로 2/28 이어야 한다).
- **서버 식은 정상 경우에도 하루 길고**, 월말에서는 clamp 가 없어 2~4일
  길어진다.

### 2-C. 시간대 축 — 서버 산술은 UTC 성분을 읽는다

클라이언트는 **기기 로컬** 달력 성분으로 계산하고 로컬 자정 instant 를
보낸다. 서버(CF, TZ=UTC)는 `Date#getMonth()/setMonth()` 를 쓰므로 저장된
instant 의 **UTC** 성분으로 계산한다.

| 기기 | 보낸 instant | 서버가 읽는 UTC일 | 클라 종료(KST) | 서버 종료(KST) |
|---|---|---|---|---|
| KST | 2026-01-30T15:00Z | 2026-01-30 | 2026-02-27 | 2026-03-03 |
| UTC | 2026-01-31T00:00Z | 2026-01-31 | 2026-02-27 | 2026-03-03 |
| UTC+13 | 2026-01-30T11:00Z | 2026-01-30 | **2026-02-26** | **2026-03-02** |

- **UTC+13 기기에서 만든 계약은 같은 공고·같은 선택일인데 하루 앞선다.**
  기산일 자체가 KST 로 1/30 이 되기 때문이다(기존 KST 계약 문제와 같은 축).
- KST 기기의 `2026-01-01` 시작은 **UTC 로는 2025-12-31** 이다. 그래서 서버의
  월 산술이 **정상 기산일에도 월말 오버플로 경로를 탄다**(위 2-A 의
  `6months` 가 그 예 — instant 기준으로 재면 2026-07-02, 2일 차).
  즉 서버 식의 오차는 입력에 따라 1~4일로 **예측하기 어렵게** 흔들린다.

증거: `test/contract_period_parity_contract_test.dart` (CPP-A~D, 18셀).

---

## 3. 판정

| 축 | 판정 | 근거 |
|---|---|---|
| 별도 계약 약정 | **없음** | 계약서 제2조는 두 날짜만 출력. 산식·기간 단위 문구 없음 |
| 종료일 의미 | **마지막 유효일(inclusive)** | `effectiveEndDate` 주석 + `occupiesSeatOn`/`isWorkingOnDate`/`isExitEffectiveOn` 세 곳 일치 |
| 클라이언트 식 | **월중 정확 · 월말 하루 짧음** | 2-B 표. 160② 와 일치, 160③ 만 어긋남 |
| 서버 식 | **전 구간 1일 이상 김 · 월말 clamp 없음 · UTC 성분 의존** | 2-A·2-B·2-C |
| 실제 계약 만료일의 주인 | **서버 식** | 확정 시 덮어쓰고, 계약서·알림·효력이 그 값을 씀 |
| 이 이슈 owner | `computeContractEndDate` 단독 → **두 식의 parity** 로 정정 | §0 |

### 왜 지금 고치지 않는가 (NO PATCH)

1. 요청서가 "만료일을 먼저 코드에서 임의 변경하지 않는다" 고 명시했다.
2. 어느 값으로 맞출지가 **법률·제품 결정**이다(아래 세 안).
3. 서버 식을 고치려면 CF 변경·배포가 필요하고 이번 범위에서 금지다.
4. 이미 확정·서명된 계약이 있다면 저장값 보정 여부가 **원장 쓰기**이고
   이번 범위에서 금지다.

---

## 4. 필요한 정책 결정 (세 안)

기준을 먼저 하나 고른다. **inclusive 마지막 유효일** 이라는 필드 의미는
세 안 모두 유지한다.

| 안 | 정의 | `1/1 + 1개월` | `1/31 + 1개월` | 성질 |
|---|---|---|---|---|
| **A. 민법 160②③** | 해당일의 전일, 해당일 없으면 **그 월의 말일** | 1/31 | **2/28** | 법정 기간 계산과 일치. 월말 시작이 하루 이득 |
| **B. 현재 클라이언트 식** | `(start + N개월, clamp) - 1일` | 1/31 | 2/27 | 월중은 A 와 동일. 월말만 하루 짧음 |
| **C. 현재 서버 식** | `start + N개월` (clamp·`-1일` 없음) | 2/1 | 3/3 | inclusive 의미와 충돌(기간이 하루 이상 길어짐). **권장하지 않음** |

세 안 중 무엇을 고르더라도 **두 식을 한 곳으로 모으는 것**이 먼저다.
서버가 canonical writer 이므로, 클라이언트는 서버와 같은 식을 쓰거나
**표시 자체를 저장값으로부터 읽어야** 한다.

### 구분해야 할 두 집단

| 집단 | 처리 | 이유 |
|---|---|---|
| **신규 계약** | 새 식을 즉시 적용 가능 | 아직 약속이 성립하지 않았다 |
| **이미 확정·서명된 계약** | **소급 변경하지 않는 것이 기본** | 계약서 `contractEnd` 는 문자열로 **동결**돼 있어 식을 바꿔도 안 바뀐다. 반면 `application.workEndDate` 는 살아 있어 효력 판정에 쓰인다 → 저장값만 보정하면 **서명된 문서와 효력이 어긋난다**. 보정한다면 문서·저장값·알림을 한 벌로 다뤄야 하고 그건 별도 결정이다 |

### 영향 범위 (읽기 수준)

| 항목 | 범위 |
|---|---|
| 대상 계약 종류 | `contractPeriodType ∈ {15days, 1month, 3months, 6months, 1year}` 인 **preset 장기 공고**. `custom` 은 `rangeEnd` 고정값이라 이 식을 지나지 않는다 |
| 코드 접점 | 클라이언트 1곳(`computeContractEndDate`, 호출부 3), 서버 1곳(`callableConfirmApplication` 인라인 식) |
| 하위 소비자 | 계약서 제2조, `workPeriodDisplay` 8화면, D-15 만료 알림, 갱신 제안, `occupiesSeatOn`/`isWorkingOnDate`/`isExitEffectiveOn`, 급여 기간 판정 |
| DEV 실제 데이터 건수 | **NOT SEEN** — 공유 DEV 원장 조회를 하지 않았다(READ 도구 미사용). 영향 건수는 별도 DEV READ 로 확인해야 한다 |

---

## 5. 이번에 한 최소 수정 (정책 무변경)

식은 한 줄도 바꾸지 않았다. 사실이 틀린 설명과 결손 미고정만 처리했다.

| 파일 | 내용 |
|---|---|
| `lib/models/core/to_model.dart` | `computeContractEndDate` 문서 주석에 **이 값이 계약 만료일로 저장되지 않는다**는 사실과 서버 식·차이를 적었다. 계산 코드 무변경 |
| `test/unit/to_model_test.dart` | 앞 회차에 내가 "구현이 명시한 현재 규칙" 이라고 적은 설명을 **정정**했다. 기대값(2/27)은 그대로 — 이 함수의 값 자체는 맞다 |
| `test/contract_period_parity_contract_test.dart` (신규) | 두 식의 차이를 **실행 가능한 반례**로 고정(18셀). 서버 식 원문 앵커(CPP-A) 포함 — 어느 쪽이든 바뀌면 먼저 깨진다 |

**기대값의 성격:** CPP-B/C 의 값은 바람직한 결과가 아니라 **지금 벌어지는
차이**다. 파일 머리말에 그렇게 적었다. 정상 대조도 함께 둔다 — CPP-B0(클라
식이 "시작일 포함 N개월" 과 일치), CPP-C0(월중 기산에서 클라 식이 민법
해석과 일치).

### 검증

- 신규 테스트 단독: **18 PASS**
- 영향집합(`contract_period_parity` · `to_model` · `longterm_renewal_boundary` ·
  `renewal_decision_surface` · `termination_effective_date` ·
  `application_model`): **630 PASS / 0 FAIL**
- 전체 스위트: **14469 PASS / 2 SKIP / 0 FAIL / 0 load error**
- `flutter analyze lib test`: **No issues found**

---

## 6. 증거 등급

| 등급 | 내용 |
|---|---|
| **CODE** | 두 식의 원문, 저장·덮어쓰기 경로, 계약서 출력 경로, 효력 판정 세 곳, 만료 알림 소스 |
| **격리 행동** | CPP-A~D 18셀 (서버 식은 Dart 로 옮겨 재현 + TS 원문 앵커) |
| **RENDER** | **NOT SEEN** — 지원 시트 기간 카드와 계약서 PDF 를 실제로 렌더해 두 값을 나란히 본 적은 없다. 소스 경로만 확인했다 |
| **DEV READ** | **NOT SEEN** — 공유 DEV 의 실제 preset 장기 계약 건수·저장된 `workEndDate` 미조회 |
| **DEVICE** | **NOT SEEN** — 이 요청의 범위 밖 |
| **법률·PRODUCT 결정** | **OPEN** — §4 의 A/B/C 선택과 기존 계약 처리 방침. owner: 계약 도메인 |

## 7. 금지 항목 준수

공유 DEV·PROD 계약/급여 원장 쓰기 **0**, 계약 서명·해지 실행 **0**,
CF/Rules 배포 **0**, 테스트 fixture 의 서버 쓰기 **0**,
APK 생성·빌드·설치 **0**, 실기기 조작 **0**.
서버 실제 전이, Staffing DEFERRED/O08, 네 역할 USER/PRODUCT, 출시 gate 는
닫지 않았다.
