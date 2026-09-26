# 출시 전 개인정보 게이트

최종 수정 2026-09-26 · 기준 개정 `2026-09-26`

출시 빌드를 올리기 전에 반드시 통과해야 하는 항목이다. 하나라도 남아 있으면
`[PLAY-BLOCKER-PRIVACY-POLICY-STALE]` 는 **CLOSED 가 아니다.**

---

## 1. PROD 저장본 동기화 — RELEASE GATE

앱은 `app_settings/legal_terms` 를 먼저 읽는다. 코드와 공개 웹만 고치면
**앱 화면은 계속 옛 방침을 보여준다.** DEV 에서 실제로 그랬다.

| 대상 | 상태 |
|---|---|
| 앱 코드 원문 (`legal_terms_model.dart`) | 개정 `2026-09-26` |
| 공개 웹 (`/privacy`) | 개정 `2026-09-26` (원문에서 생성) |
| DEV `app_settings/legal_terms` | **동기화 완료** |
| PROD `app_settings/legal_terms` | **PENDING — 출시 전 필수** |

PROD 동기화 절차:

```
# 1) PROD 서비스 계정으로 전환한 뒤
node scripts/render-privacy.js --check     # 원문↔공개 웹 일치 확인
# 2) PROD app_settings/legal_terms 의 privacy_policy 항목만
#    원문 content/version 으로 갱신 (다른 약관 항목은 건드리지 않는다)
# 3) 갱신 후 version 이 2026-09-26 인지, 본문에 account-deletion 이
#    포함되는지 확인
```

> PROD 변경은 별도 승인 후 수행한다. 이 문서는 절차만 고정한다.

## 2. 공개 페이지

- `https://alfit-89567.web.app/privacy` — 200, 인증 없음
- `https://alfit-89567.web.app/account-deletion` — 200, 인증 없음
- 두 페이지가 서로 링크된다
- 방침을 고쳤다면 `node scripts/render-privacy.js` 후 hosting 재배포

## 3. Play Console 제출 항목 (이번 범위 밖)

- 개인정보처리방침 URL 등록
- 계정 삭제 URL 등록 (`/account-deletion`)
- Data Safety 선언 — `[PLAY-BLOCKER-DATA-SAFETY-NOT-DECLARED]` 미착수

## 4. 법률·세무 확인 대기 (COUNSEL / TAX)

공개 방침에 **숫자를 지어 넣지 않았다.** 아래는 확인 후 확정한다.

| 항목 | 현재 공개 문구 | 상태 |
|---|---|---|
| 근로자 명부·근로계약 중요 서류 | 3년 (근로기준법 제42조) | 근거 명시됨 |
| 임금대장·임금 결정/지급 서류 | 3년 (근로기준법 제42조) | 근거 명시됨 |
| 출퇴근 기록 | 임금 계산 근거로서 위와 같은 기간 | **COUNSEL** — 독립 법정 class 여부 |
| 세무 관련 자료 | 관계 세법이 정한 기간 | **TAX** — 구체 기간·근거 |
| 재가입 제한 식별자 | 30일 | 소스 확정 |
| 계약/청약철회·소비자 불만 | 5년 / 3년 (전자상거래법) | 기존 유지 |
| 서비스 이용 기록 | 3개월 (통신비밀보호법) | 기존 유지 |

## 5. 자동 삭제는 이 게이트에 포함되지 않는다

보존 기간을 적은 것이 **자동 삭제를 구현했다는 뜻이 아니다.**
scheduler · TTL · 일괄 정리 · 과거 급여 데이터 purge 는 만들지 않았고,
법률·세무 검토 전에는 만들지 않는다.

특히 아래는 민감 원본과 같은 묶음으로 다루지 않는다.

- 근무 사실, 임금 산정 결과(`finalWage`), 지급 여부
- 이체·취소·재이체 이력, `money_audit`
- 계약·근태와 임금의 연결 관계, 세무·회계 증빙

민감 원본(신분증·통장 사본·세무 식별번호)은 목적 종료·탈퇴 시 즉시 삭제하고,
위 지급 증빙은 보존한다.
