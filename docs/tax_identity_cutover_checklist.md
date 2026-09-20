# 세무 identity 수집 개시 체크리스트 (PII-B4-R1.4 cutover)

작성: PII-B4-R1.3B / 선행 커밋 `40ae2be`

이 문서는 **주민등록번호·외국인등록번호 전체를 세무 목적으로 수집·저장하기 시작하는 릴리스**에만 적용된다.
코드가 준비되는 것과 수집을 켜는 것은 다른 사건이며, 이 문서는 후자의 순서를 고정한다.

---

## 0. 왜 이 문서가 있는가

지키려는 불변식은 하나다.

```
새 민감정보 writer 활성  +  옛 고지  =  BLOCKER
```

수집을 먼저 켜고 고지를 나중에 맞추는 순서는 허용하지 않는다.
개정 고지 없이 수집된 데이터는 사후에 동의를 받아도 수집 시점의 하자가 남는다.

---

## 1. CODE READY ≠ LEGALLY ACTIVE

| 상태 | 의미 |
|---|---|
| **CODE READY** | writer/UI/OCR/gate가 DEV에서 동작하고 테스트가 통과한다 |
| **LEGALLY ACTIVE** | 개정 처리방침이 게시되고 시행일이 도래했으며 런타임이 그 버전을 내려준다 |

R1.4 코드가 DEV에 있어도 LEGALLY ACTIVE가 아니면 **PROD 수집을 켜지 않는다.**
두 상태를 한 문장으로 합쳐 보고하지 않는다.

---

## 2. 활성화 guard (§7)

이 프로젝트에는 이미 **Firebase Remote Config**가 있다
([app_version_service.dart](../lib/services/app_version_service.dart) — `min_version` 등).
새 feature-flag 아키텍처를 만들지 않고 이것을 쓴다.

```
키      tax_identity_collection_enabled
기본값  false            ← setDefaults 에 반드시 포함 (fail closed)
읽는 곳 세무정보 입력 진입점 1곳
```

규칙:

- **기본값 false가 핵심이다.** Remote Config fetch가 실패하면 기본값이 쓰인다.
  기본값이 true면 네트워크 장애가 곧 무단 수집이 된다.
- 서버 writer(`callableRegisterTaxIdentity` 등)는 flag와 **무관하게 존재해도 된다** —
  클라이언트가 호출하지 않으면 데이터는 생기지 않는다.
  단 UI 진입점은 반드시 flag 뒤에 둔다.
- flag를 켜는 시점이 §4의 9번 단계다. 그 이전 단계가 하나라도 미완이면 켜지 않는다.

---

## 3. 법적 근거 체크리스트 (§15)

각 항목은 **확인됨 / LEGAL REVIEW REQUIRED** 로만 표시한다. 추정으로 채우지 않는다.

| # | 항목 | 현재 상태 |
|---|---|---|
| 1 | 내국인 주민등록번호 처리의 법령 근거 식별 | **LEGAL REVIEW REQUIRED** ⚖️ |
| 2 | 수집 목적 확정 (소득신고·원천징수·지급명세서 범위) | **LEGAL REVIEW REQUIRED** ⚖️ |
| 3 | 처리자/수탁자 관계 확정 (AlFit vs 사업주 중 누가 개인정보처리자인가) | **LEGAL REVIEW REQUIRED** ⚖️ |
| 4 | 보유기간 확정 및 경과 후 파기 절차 | **미확정** — 자동 파기 Scheduler 미구현 |
| 5 | 열람 가능 주체 확정 (관리자 검토 범위) | 설계 완료 (B4 review 4조건), 법적 확인 ⚖️ |
| 6 | 개정 처리방침 게시 | 미실시 |
| 7 | 시행일 도래 | 미실시 |
| 8 | 런타임 정책 버전 검증 | 미실시 |
| 9 | 민감정보 writer 활성화 | 미실시 |

> ⚖️ **개인정보보호법 제24조의2** — 주민등록번호는 법령에 구체적 근거가 있는 경우에만
> 처리할 수 있다. 소득세법상 원천징수 의무를 근거로 삼는 경우, 그 의무가 언제 성립하는지
> (지원 시점인가 / 소득 발생 시점인가)가 수집 시점 설계를 좌우한다. 이 판단은 법률 자문 영역이다.
>
> 현재 제품 정책(PII-B4-R1.3 §1)은 **지원자 서류 등록 단계** 수집이다. 이는 소득 발생 전이므로
> 1·2번 항목의 결론이 이 정책을 바꿀 수 있다.

---

## 4. PROD 릴리스 순서 (§23)

순서를 바꾸지 않는다. 각 단계는 앞 단계의 완료를 전제한다.

1. **문구 확정** — 개정 처리방침·동의문 최종본 법무 승인 (§3의 1~5번 해소)
2. **게시** — `app_settings/legal_terms` 의 `privacy_policy` 항목을
   SUPER_ADMIN 약관 관리 화면에서 개정본으로 교체하고 `version` 을 올린다
3. **시행일 확인** — 본문의 시행일이 도래했는지 확인. 도래 전이면 5번으로 가지 않는다
4. **런타임 readback** — 실제 reader가 새 버전을 내려주는지 확인 (§5)
5. **수집 활성화** — Remote Config `tax_identity_collection_enabled = true`
6. **모니터링** — 최초 24시간 등록 건수·실패율·correction 발생량 관찰

**금지**: 5번을 2~4번보다 먼저 하는 것.

---

## 5. 런타임 readback 방법 (§10·§27)

Firestore에 썼다는 사실만으로 VERIFIED 로 적지 않는다. **실제 reader가 무엇을 내려주는지**를 본다.

검증 대상 reader는 [`LegalTermsService.getTerms()`](../lib/services/legal_terms_service.dart) 하나이며,
소비자는 다음 6곳이다.

```
register_screen               가입 동의
foreign_register_screen       외국인 가입 동의
registration_recovery_screen  가입 복구 동의
settings_screen               약관 열람
user_settings_screen          약관 열람
legal_terms_management_screen 관리자 편집
```

검증 절차:

```
1. 저장된 문서를 덤프한다
2. ALFIT_LEGAL_DUMP=<덤프경로> flutter test \
     test/legal_terms_current_truth_contract_test.dart
```

이 테스트는 덤프를 **실제 모델 파서**(`LegalTermsItem.fromMap` → `LegalTerms.activeItems`)에
통과시켜 현재 진실 문구를 검사한다. 환경변수가 없으면 런타임 그룹만 skip 된다.

---

## 6. 알려진 제약

### 재동의 gate가 없다

`version` 은 **표시용 + 동의 시점 기록용**이다. 저장된 동의 버전과 현재 버전을 비교해
재동의를 요구하는 코드는 존재하지 않는다 (PII-B4-R1.3B에서 전수 확인).

따라서 처리방침을 개정해도 **기존 사용자는 새 문구에 동의한 적이 없다.**
세무 identity 수집처럼 수집 항목이 늘어나는 개정에서 이것이 충분한지는 ⚖️ 법률 판단이다.
임의로 전체 재동의를 구현하지 않는다 — 정책 결정이 선행되어야 한다.

참고: 서류 접근 동의(`documentAccessConsentVersion`)는 **별개 축**이며 지원 시점에 매번 기록된다.

### 정책 fetch 실패가 조용하다

`getTerms()` 는 Firestore 조회 실패 시 `debugPrint` 후 **내장 기본값을 조용히 반환**한다.
사용자에게는 오류가 아니라 정상 문구로 보인다.
현재는 런타임 문서와 내장 기본값이 동일해 실해가 없으나, 다음 개정 직후 이 둘이 갈라진 상태에서
장애가 나면 **옛 문구가 현재 문구인 것처럼 표시된다.**

→ `[CORRECTION-B4R13B-LEGAL-FETCH-SILENT-FALLBACK]`

### 내장 기본값은 최초 1회만 쓰인다

`app_settings/legal_terms` 문서가 이미 있으면 코드의 기본값은 **영원히 사용되지 않는다**
(오류 fallback 제외). 코드만 고치고 배포하는 것으로 고지가 바뀌지 않는다.
2번 단계(게시)를 건너뛸 수 없는 이유다.

---

## 7. 완료 판정

아래가 모두 참일 때만 "세무 identity 수집 개시"를 완료로 적는다.

- [ ] §3의 1~5번이 **확인됨**으로 바뀌었다
- [ ] 개정 처리방침이 게시되고 version이 올라갔다
- [ ] 시행일이 도래했다
- [ ] §5 절차로 런타임 readback이 통과했다
- [ ] Remote Config flag가 true이고, 기본값은 여전히 false다
- [ ] 수집 개시 후 24시간 모니터링 결과를 기록했다
