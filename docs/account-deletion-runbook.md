# 계정 삭제 요청 처리 절차 (off-app)

작성 기준 HEAD: `62507e1` · 최종 수정 2026-09-26

웹(`/account-deletion`)으로 접수된 계정 삭제 요청을 운영자가 처리하는 절차다.
앱에서 직접 탈퇴하는 경우와 **같은 삭제·보존 기준**을 적용한다.

---

## 0. 이 문서가 필요한 이유

앱 내 탈퇴는 본인이 비밀번호로 재인증한 뒤 `callableDeleteAccountFinal`이
실행한다. 이 함수는 `request.auth.uid` 본인만 대상으로 하고 재인증 후 10분
이내만 허용한다. 즉 **운영자가 다른 사람의 계정을 대신 삭제 실행하는 경로는
현재 없다.**

그래서 off-app 요청은 아래 절차로 처리한다. 절차의 목표는 두 가지다.
누락 없이 지울 것, 그리고 지운 사실을 남길 것.

---

## 1. 접수

- 접수 채널: `corebridge87@gmail.com`
- 요청 메일에 있어야 할 것: 가입 휴대폰 번호, 가입자 이름, 회신 연락처
- 주민등록번호·외국인등록번호·신분증·통장 사본이 함께 왔다면 **즉시 폐기**하고,
  폐기했다는 사실을 회신에 적는다. 계정 확인에 필요하지 않다.

## 2. 본인 확인

다음 중 하나로 확인한다. 확인되지 않으면 삭제하지 않고 그 사실을 회신한다.

- 가입 시 본인인증한 휴대폰 번호로 연락해 확인
- 계정 기록 중 본인만 알 수 있는 항목 일부 확인 (가입 시점, 최근 이용 사업장 등)

> 이 단계를 건너뛰면 타인의 계정을 지우게 된다. 기록을 남긴다 — 언제,
> 어떤 방법으로 확인했는지.

## 3. 계정 조회

`users` 컬렉션에서 휴대폰 번호로 대상 uid를 찾는다. 동명이인·번호 변경으로
후보가 둘 이상이면 삭제하지 않고 추가 확인을 요청한다.

## 4. 삭제 차단 사유 확인

아래에 해당하면 먼저 해소해야 한다. 앱 탈퇴 흐름이 막는 것과 같은 조건이다.

- `users/{uid}.subAdminBusinessIds`가 비어 있지 않음 → 서브관리자 직책 해제 필요
- 미서명 근로계약(`employment_contracts`에서 `workerSignedAt == null`,
  상태가 VOID/EXPIRED가 아닌 건)이 남아 있음

차단 사유가 있으면 그 사실과 해소 방법을 회신한다.

## 5. 삭제 실행

**원칙: canonical 경로를 먼저 쓴다.**

### 5-A. 본인이 앱을 쓸 수 있는 경우 (권장)

본인 확인 후, 앱 `설정 > 회원탈퇴`로 직접 진행하도록 안내한다. 이 경로가
누락 없는 유일한 자동 경로다. 안내 후 완료 여부를 확인하고 회신한다.

### 5-B. 본인이 앱을 쓸 수 없는 경우

현재 운영자 실행용 서버 경로가 없다. 아래 순서를 **그대로** 따른다. 순서를
바꾸면 중간 실패 시 복구가 어려워진다.

1. `callableDeleteAccountPreData` 가 하는 일을 동일하게 수행
   - `deleted_accounts`에 기록 추가:
     `ciHash` / `phoneHash` / `foreignIdentityFingerprint`(있는 것만),
     `role`, 탈퇴 시각, `canReregisterAt = 탈퇴일 + 30일`, `isBlacklisted`
   - `nativeIdentityFingerprints/{ciHash}_{role}` 삭제
   - `foreignIdFingerprints/{fingerprint}_{role}` 삭제
   - `taxIdentities/{uid}` 삭제
   - `idCardAccessRequests` 중 해당 사용자 건 삭제
   - `member_invitations` 중 수신 건 삭제, 발신 건은 `invitedBy` 익명화
   - `review_requests.workerId`, `monthly_reviews.targetUserId`/`reviewerId`,
     `trust_score_history.userId` 익명화
2. `callableDeleteAccountApplications` 가 하는 일을 동일하게 수행
   - 활성 `applications`(CONFIRMED / CONTRACT_PENDING / PENDING) → `CANCELED`
   - 예정 `attendance`(`status == scheduled`) → `absent`
3. Storage 문서 삭제 — 신분증·외국인등록증·통장 사본·서명·날인 등
   해당 사용자 경로 하위 전체
4. `users/{uid}` 삭제
5. Firebase Authentication 사용자 삭제

> **순서 근거**: `deleted_accounts` 기록이 sentinel 삭제보다 **먼저**다.
> 그래야 30일 재가입 게이트가 켜진 뒤에 sentinel이 풀린다. 반대로 하면
> 그 사이에 재가입이 가능해진다.
>
> **중단 시**: 1~3 중 실패하면 4·5로 넘어가지 않는다. `users` 문서와 Auth가
> 남아 있어야 같은 절차를 다시 실행할 수 있다.

## 6. 보존되는 것

지우지 않는다. 요청자에게도 그렇게 회신한다.

- 관계 법령이 보존을 요구하는 근로·급여·계약 기록
- 식별자를 제거한 평가·신뢰도·초대 발송 기록
- 재가입 제한용 `deleted_accounts` 기록 (30일)

## 7. 완료 회신

접수 후 3일 이내에 결과를 회신한다. 회신에 포함할 것:

- 삭제 완료 시각
- 삭제된 범위 (계정·문서·세무 식별정보)
- 보존되는 항목과 그 이유
- 30일 재가입 제한 안내

## 8. 기록

요청 1건마다 다음을 남긴다: 접수 일시, 본인 확인 방법, 대상 uid,
실행 일시, 실행자, 차단 사유(있었다면), 회신 일시.

---

## 미결 — 결정 필요

**운영자 실행용 canonical 경로가 없다.** 5-B는 수동이라 누락 위험이 있고,
이 문서가 그 위험을 절차로 막고 있을 뿐이다.

선택지는 두 가지다.

1. SUPER_ADMIN 전용 삭제 callable을 신설해 기존 단계를 그대로 재사용한다.
   누락이 사라지지만, **타인 계정을 지우는 강력한 권한**이 새로 생긴다.
   감사 기록과 요청 근거 필수화가 함께 필요하다.
2. 현행 유지 — 5-A를 기본으로 하고 5-B는 예외 처리로 둔다.

이 선택은 제품·보안 결정이므로 별도 승인 후 진행한다.
