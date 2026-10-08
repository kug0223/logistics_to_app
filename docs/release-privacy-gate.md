# 출시 전 개인정보 게이트

최종 수정 2026-10-08 · 기준 개정 `2026-10-08`

출시 빌드를 올리기 전에 반드시 통과해야 하는 항목이다. 하나라도 남아 있으면
`[PLAY-BLOCKER-PRIVACY-POLICY-STALE]` 는 **CLOSED 가 아니다.**

---

## 1. PROD 저장본 동기화 — RELEASE GATE

앱은 `app_settings/legal_terms` 를 먼저 읽는다. 코드와 공개 웹만 고치면
**앱 화면은 계속 옛 방침을 보여준다.** DEV 에서 실제로 그랬다.

| 대상 | 상태 |
|---|---|
| 앱 코드 원문 (`legal_terms_model.dart`) | 개정 `2026-10-08` |
| 공개 웹 (`/privacy`, `/terms`) | 현재 발행본을 **읽는다** (사본 없음) |
| DEV `app_settings/legal_terms` | **동기화 완료** |
| PROD `app_settings/legal_terms` | **PENDING — 출시 전 필수** |

### [R7-PAYROLL-POLICY.5] 이번 개정이 건드리는 항목

`privacy_policy` 하나가 아니다. **필수 항목 네 개**가 같은 날짜로 함께
개정됐다 — `service_terms`, `privacy_policy`, `privacy_third_party`,
`location_terms`. `marketing_consent`(선택)는 본문이 바뀌지 않았다.

네 항목을 한 날짜로 묶은 이유: 필수 항목의 **시행본**이 바뀌면 그 항목을
다시 받아야 하므로, 따로 올리면 재동의가 네 번 일어난다.

### [R7-PAYROLL-POLICY.5A] 발행 ≠ 시행 — 절차가 바뀌었다

`.5` 시점에는 발행이 곧 시행이었고, 그래서 "발행 시점에 전원이 재동의
화면을 본다" 고 적었다. `.5A` 가 그 결합을 끊었다. 발행은 **고지**이고,
적용은 `effectiveAt` 부터다.

```
# 1) PROD SUPER_ADMIN 으로 전환한 뒤
# 2) 약관 관리 화면에서 네 항목을 각각 발행
#    · 변경 방향 = 이용자에게 불리할 수 있는 변경 (adverse)
#    · 시행일    = 발행일 + 30일 이후의 KST 자정
#      (service_terms 제3조 ② 의 자기약속. 서버가 강제하며, 모자라면
#       가장 이른 시행일을 알려 준다)
# 3) 발행 후 확인
#    · legal_revisions/{itemId}__2026-10-08 네 건 (effectiveAt·changeType 포함)
#    · app_settings/legal_terms 의 각 항목에서
#        base      = 아직 옛 판 (지금 적용 중)
#        upcoming  = 새 판 + effectiveAt
# 4) 시행일 이후 확인 — masterScheduler(매시 정시)의 `약관 시행 전환` 이
#    upcoming 을 base 로 올렸는지
```

**발행 당일에는 아무도 막히지 않는다.** 고지 기간 동안 `callableApplyToTO`
의 약관 gate 는 여전히 옛 판 기준이고, 재동의 요구는 시행 시각부터 생긴다.
DEV 실측(읽기 전용, 2026-10-08):

| 시계 | 시행 중 | 예정 | 지원 차단 |
|---|---|---|---|
| 고지 중(시행 1일 전) | 옛 판 | 4건 | **0 / 8** |
| 시행 1ms 전 | 옛 판 | 4건 | **0 / 8** |
| 시행 정각 | `2026-10-08` | 0건 | **1 / 8** |
| 시행 +1일 | `2026-10-08` | 0건 | **1 / 8** |

차단 1명은 동의 기록이 발행본을 가리키는 유일한 사용자다. 나머지 7명은
`LEGACY_CONSENT_UNKNOWN` 으로 남아 **막히지 않는다**(soft migration).
`.5` 가 보고한 "8/8" 은 `evaluateReconsent`(다시 받아야 하는 항목) 수치이고,
실제 gate 는 `evaluateLegalReadiness` + `allowsNewCommitment` 다.

### [R7-PAYROLL-POLICY.5B] 시행 경계 — 세 표면이 같은 판을 말한다

`.5A` 가 발행과 시행을 분리하고 나서 남은 구멍이 있었다. 앱은
`app_settings/legal_terms` 의 base 를 직접 읽었고, 비로그인 가입 화면은
서버 시각을 알 수 없어 스스로 판정할 수도 없었다. 시행 정각부터 정기
정합화까지 앱은 옛 판을, 서버는 새 판을 말했고, 가입 화면은 같은 동의
payload 로 **영원히 실패하는 재시도**를 반복했다.

이제 "어느 판이 시행 중인가" 는 서버가 답한다 —
`callableGetEffectiveLegalTerms`(비인증, App Check 강제)가
`resolveProjectionItems` 로 판정해 내려 준다. readiness·동의 writer·공개
웹과 **같은 해석기**이므로 어긋날 수 없다.

| 상태 | 공개 웹 | 앱 | 서버 readiness | 동의 writer |
|---|---|---|---|---|
| 시행 1ms 전 | A | A | A | A |
| 시행 정각 | B | B | B | B |
| 스케줄러 지연(base 아직 A) | B | B | B | B |
| 스케줄러 완료 | B | B | B | B |
| 조회 실패 | 오류 표시 | 오류 표시 + 동의 차단 | ERROR | 기록 거부 |

조회 실패는 **기본값으로 대체하지 않는다.** 예전 가입 화면은
`LegalTerms.defaultTerms()` 를 현재 약관처럼 보여 준 뒤 동의까지 받았다 —
그 동의는 사용자가 본 글을 가리키지 않는다.

고르는 사이에 약관이 시행되면 서버가 `TERMS_VERSION_STALE` 로 거절하고,
클라이언트는 **새 글을 다시 불러와 보여 주고 고른 것을 지우고 사용자가
다시 고르게** 한다. 이전 동의를 새 판 동의로 승격하지 않는다.

> PROD 변경은 별도 승인 후 수행한다. 이 문서는 절차만 고정한다.

## 1-B. [R7-PAYROLL-POLICY.5] 약관이 아직 말할 수 없는 것 — RELEASE BLOCKER

`[LEGAL-BLOCKER-BUSINESS-IDENTITY-PLACEHOLDER]`

`service_terms` 제1조와 `location_terms` 의 사업자 정보가 아직
`[... 기재 필요]` placeholder 다. 실제 상호·대표자명·소재지·사업자등록번호를
**추측해서 채우지 않았다.** 약관이 당사자를 특정하지 못하면 제11조의 관할
합의도 특정되지 않는다.

| 자리 | 현재 값 |
|---|---|
| `service_terms` 제1조 대표자 | `[대표자명 기재 필요]` |
| `service_terms` 제1조 사업장 소재지 | `[사업장 주소 기재 필요]` |
| `service_terms` 제1조 사업자등록번호 | `[사업자등록번호 기재 필요]` |
| `location_terms` 위치기반서비스사업자 | `[회사명 기재 필요]` |

사용자가 실제 값을 주면 같은 날짜 개정으로 함께 채운다. 그때까지 이 blocker
는 CLOSED 가 아니며, `payroll_policy_terms_wording_test` 가 placeholder 와 이
문서의 blocker 표기를 **함께** 고정한다 — 한쪽만 사라지지 않게.

### [R7-PAYROLL-POLICY.5A] NEEDS OWNER INPUT — 저장소 전수 조사 결과

repo 전역에서 운영주체를 찾았다(`사업자등록번호`·`대표자`·`상호`·`주식회사`
·footer·`pubspec.yaml`·`firebase.json`·공개 HTML). 나온 것은 셋뿐이다.

| 확인된 값 | 출처 |
|---|---|
| 서비스명 `AlFit` | `pubspec.yaml`, 공개 페이지 `<h1>`·footer |
| 고객센터 이메일 `corebridge87@gmail.com` | 약관·처리방침·계정삭제 페이지 |
| Firebase 프로젝트 `alfit-89567`(dev) / `alfit-prod` | `.firebaserc` |

코드에 있는 `사업자등록번호`·`대표자명`·`상호명`은 모두 **고객 사업장**의
필드다(`businesses`, `users.businessNumber`). ALfit 자신의 사업자 정보는
저장소에 없다. 이메일 앞부분에서 회사명을 유추하지 않는다 — 그것은 추측이다.

아래 값을 받아야 blocker 를 닫을 수 있다.

| 필요한 값 | 들어갈 자리 | 공식 근거(검토 필요) |
|---|---|---|
| 상호(법인명 또는 개인사업자 명칭) | `service_terms` 제1조, `location_terms` 사업자 | 전자상거래법 제10조 적용 여부는 미확인 — 약관 당사자 특정은 그와 별개로 필요 |
| 대표자 성명 | `service_terms` 제1조 | 같음 |
| 사업장 소재지 | `service_terms` 제1조 · 제11조 ② 관할 | 관할 합의가 소재지를 가리킨다 |
| 사업자등록번호 | `service_terms` 제1조 | 동일인 확인 |
| 개인정보 보호책임자 성명·직책 | `privacy_policy` 보호책임자 | 개인정보 보호법 제31조 — 현재 "AlFit 운영팀" 으로만 적혀 있다 |
| 위치기반서비스사업 신고 여부·신고번호 | `location_terms` | 위치정보법 제9조 제1항 — 신고 대상 여부 자체가 `[LEGAL-LOCATION-SERVICE-REGISTRATION]` |

개인정보처리자와 서비스 운영주체가 **같은 entity** 인지도 함께 확인해야
한다. 현재 두 문서 모두 `AlFit` 으로만 적혀 있어 구별되지 않는다.

## 2. 공개 페이지

- `https://alfit-89567.web.app/privacy` — 200, 인증 없음
- `https://alfit-89567.web.app/account-deletion` — 200, 인증 없음
- 두 페이지가 서로 링크된다
- 방침을 고쳤다면 **발행**만 하면 된다. 공개 페이지는 현재 발행본을 읽으므로
  hosting 재배포가 필요하지 않다 (옛 `scripts/render-privacy.js` 는 두 번째
  진실을 만들기 때문에 제거됐다)

## 3. Play Console 제출 항목

- 개인정보처리방침 URL 등록
- 계정 삭제 URL 등록 — **PROD 호스팅 배포 후 확정**
  (`.firebaserc` 의 prod = `alfit-prod`. 현재 배포·검증된 것은 DEV URL 뿐이다)
- Data Safety 선언 — 선언 내용은 [`play-data-safety-final.md`](play-data-safety-final.md)
  에 확정. `[PLAY-BLOCKER-DATA-SAFETY-NOT-DECLARED]` = **READY FOR PLAY CONSOLE
  SUBMISSION** (실제 Console 입력 전까지 CLOSED 아님)

## 4. 법률·세무 확인 대기 (COUNSEL / TAX)

공개 방침에 **숫자를 지어 넣지 않았다.** 아래는 확인 후 확정한다.

| RECORD | 제품상 목적 | 공개 문구 | 근거 | 상태 |
|---|---|---|---|---|
| 근로자 명부·근로계약 중요 서류 | 고용 관계 증빙 | 3년 | 근로기준법 제42조 | 근거 확인됨 |
| 임금대장·임금 결정/지급 서류 | 임금 지급 증빙 | 3년 | 근로기준법 제42조 | 근거 확인됨 |
| 출퇴근 기록 | 임금 계산 근거 | 기간 미기재(목적 기술) | 독립 class 미확정 | **COUNSEL** |
| 세무 관련 자료 | 소득신고·원천징수 | 관계 세법이 정한 기간 | 구체 조문 미확정 | **TAX** |
| 지급 증빙(`finalWage`·이체 이력·`money_audit`) | 법적·세무·분쟁 대응 | 기간 미기재 + 자동 삭제 미적용 | 미확정 | **COUNSEL / TAX** |
| 이용자 문의·분쟁 기록 | 분쟁 대응 | 기간 미기재 | 미확정 | **COUNSEL** |
| `account_deletion_records` | 삭제 요청 처리·보안·감사 | 기간 미기재, **대상 계정 식별자 포함 명시** | 미확정 | **COUNSEL** |
| 재가입 제한 식별자 | 부정가입 방지 | 30일 | 소스 확정 | 확정 |
| 서비스 접속·이용 로그 | 보안·오류 분석·부정이용 방지 | 목적만 기술(기간·법률명 없음) | 통신비밀보호법 적용 대상 미확인 | **COUNSEL** |
| ~~계약/청약철회·소비자 불만~~ | — | **삭제됨** | 전자상거래법 적용 근거 없음 | **REMOVED** |

### [R7-PAYROLL-POLICY.5] 확인한 법령 원문 (확인일 2026-10-08)

기억으로 조문 번호를 고정하지 않았다. 아래는 국가법령정보센터·고용노동부
원문을 직접 열어 확인한 것이다.

| 법령 / 조문 | 확인한 내용 | 공식 URL |
|---|---|---|
| 근로기준법 제42조 (계약 서류의 보존) | "사용자는 근로자 명부와 대통령령으로 정하는 근로계약에 관한 중요한 서류를 **3년간** 보존하여야 한다." | https://www.law.go.kr/LSW/lsLawLinkInfo.do?lsJoLnkSeq=1012792795&chrClsCd=010202 |
| 근로기준법 시행령 제22조 제1항 | 보존 대상에 **제3호 "임금의 결정·지급방법과 임금계산의 기초에 관한 서류"** 포함. 같은 조 제2항 제8호: 그 밖의 서류는 완결한 날부터 기산 | https://www.law.go.kr/LSW/lumLsLinkPop.do?lspttninfSeq=70870&chrClsCd=010202 |
| 근로기준법 제17조 (근로조건의 명시) | 명시·서면 교부 의무 주체는 **"사용자"**. 서면에 「전자문서 및 전자거래 기본법」 제2조제1호 전자문서 포함 | https://www.law.go.kr/lsLawLinkInfo.do?chrClsCd=010201&lsJoLnkSeq=1015677481 |
| 근로기준법 제43조 제1항 (임금 지급) | "임금은 통화로 직접 근로자에게 **그 전액을** 지급하여야 한다." | https://www.law.go.kr/lsLinkCommonInfo.do?lsJoLnkSeq=1007688469 |
| 근로기준법 제48조 (임금대장 및 임금명세서) | 제2항 — 사용자는 임금 지급 시 구성항목·계산방법·공제내역을 적은 임금명세서를 서면(전자문서 포함)으로 교부 | https://law.go.kr/lsLinkCommonInfo.do?lsJoLnkSeq=1012793113 |
| 약관의 규제에 관한 법률 제7조 (면책조항의 금지) | **4개 호**. 제1호 — 사업자·이행보조자·피고용자의 **고의 또는 중대한 과실**로 인한 법률상 책임을 배제하는 조항은 **무효**. 제2호 — 상당한 이유 없이 손해배상 범위를 제한하거나 사업자가 부담할 위험을 고객에게 떠넘기는 조항도 무효 | https://www.law.go.kr/lsLawLinkInfo.do?lsJoLnkSeq=1000526556&chrClsCd=010202 |
| 위치정보법 제9조 제1항 | 위치기반서비스사업(개인위치정보를 대상으로 하지 아니하는 것은 제외)을 하려는 자는 방송미디어통신위원회에 **신고** | https://www.law.go.kr/LSW//lsSideInfoP.do?lsiSeq=277359&joNo=0009&joBrNo=00&docCls=jo&urlMode=lsScJoRltInfoR |
| 직업안정법 제2조의2 (정의) | 제2호 "직업소개" = 구인·구직 신청을 받아 탐색·모집하여 **고용계약이 성립되도록 알선**. 제5호 유료직업소개사업 = 무료가 아닌 직업소개사업. 제8호 직업정보제공사업 = 간행물·방송·컴퓨터통신 등으로 구인·구직 정보를 제공하는 사업 | https://law.go.kr/LSW/lsLawLinkInfo.do?lsJoLnkSeq=1000770093&chrClsCd=010202 |
| 직업안정법 제19조 제1항 | 국내 유료직업소개사업은 주된 사업소 소재지 관할 시장·군수·구청장에게 **등록** | https://www.law.go.kr/LSW//lsSideInfoP.do?lsiSeq=259231&joNo=0019&joBrNo=00&docCls=jo&urlMode=lsScJoRltInfoR |
| 고용노동부 빠른인터넷상담 (상담 ID 201410010910037831000) | "노동관계법에는 연장근로수당을 지급할 때, 10분 단위로 계산을 해야하는지, 1분 단위로 계산을 해야 하는지에 대한 규정은 없습니다. 다만, 상기의 규정에 의하여 **1분 단위로 계산을 하는 것이 바람직**할 것으로 사료됩니다." (근거로 든 조문: 근로기준법 제43조) | https://www.moel.go.kr/minwon/fastcounsel/fastcounselView.do?inetDcssMngId=201410010910037831000 |

> 마지막 항목은 **빠른인터넷상담 답변**이다. 공식 질의회시(행정해석)나 판례가
> 아니므로 그 등급으로 쓴다. 그래도 "분 단위 절사·반올림을 허용한다"는
> 근거로는 쓸 수 없다는 점은 분명하다.

### 통신비밀보호법 3개월 제거 근거

그 3개월 보관 의무는 **전기통신사업자**가 보관하는 **통신사실확인자료**에
적용된다. ALfit 이 그 적용 대상이라는 근거를 확인하지 못했다. 법률명과
기간을 함께 빼고, 접속·이용 로그는 실제 목적(보안·오류 분석·부정이용 방지)
으로만 적었다. 적용 여부가 확인되면 그때 근거와 기간을 함께 적는다.

### `account_deletion_records` 실제 스키마

| FIELD | VALUE SOURCE | PURPOSE | SENSITIVE? | RETAINED? |
|---|---|---|---|---|
| `requestId` | 운영자 `--request` | 요청 대조 | No | Yes |
| `targetUid` | 삭제 대상 uid | 어느 계정을 처리했는지 | **계정 식별자** | **Yes** |
| `targetRole` | `users.role` | 처리 맥락 | No | Yes |
| `actor` | 운영자 `--actor` | 처리자 책임 | 운영자 식별(내부) | Yes |
| `reason` | 운영자 `--reason` | 처리 근거 | 자유 입력 — 운영 지침으로 PII 금지 | Yes |
| `executedAt` | serverTimestamp | 처리 시각 | No | Yes |
| `steps` | 수행 단계 라벨 | 수행 결과 | No | Yes |
| `source` | 상수 | 경로 구분 | No | Yes |

주민번호·외국인등록번호·전화번호 원문·계좌번호·통장사본·신분증·세무 식별
원문은 **저장하지 않는다.** 공개 방침과 삭제 페이지가 `targetUid` 보관
사실을 명시한다.

### 전자상거래법 귀속 제거 근거

ALfit 은 사업장과 구직자를 연결하는 중개 서비스이고, 앱에 소비자 결제·
통신판매 기능이 없다(`iamport_flutter` 는 본인인증용이며 결제 모듈이 아니다).
근로계약·급여·정산 기록을 전자상거래법의 소비자 거래 기록으로 묶을 근거를
확인하지 못했다. 그래서 법률명과 기간을 함께 제거하고 COUNSEL 로 남긴다.

전자상거래법이 실제로 적용되는 범위가 확인되면 그때 근거와 기간을 함께
적는다.

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
