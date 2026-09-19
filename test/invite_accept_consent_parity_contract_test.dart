// [CROSS-DOMAIN-R5.2] 초대 수락 = 근무 확정 = 같은 서류 문턱
//
// [BLOCKER-INVITE-ACCEPT-DOCUMENT-CONSENT-PARITY]
//
// 직접 지원과 초대 수락은 똑같이 CONFIRMED·좌석·계약 의무를 만든다. 그런데
// 수락 경로에는 계정 상태 검사만 있었다. 실측으로 확인한 결과:
//
//   · 신분증·계좌·통장사본이 하나도 없어도 수락되어 좌석이 잡혔고,
//   · 서류 접근 동의가 없으니 통장사본 Signed URL은 거부되는데,
//   · 관리자 Home에는 "계약 미발송" 할 일이 생겼다.
//     (= 보낼 계약은 있는데 급여·신분 서류는 못 여는 상태)
//   · 신분증 pre-consent grant도 만들어지지 않았다.
//
// 고친 것:
//   1. 수락 시 **좌석을 잡기 전에** 지원 경로와 같은 readiness를 재검증한다
//      (블랙리스트·본인인증·신분증·슬롯공고 isIdVerified·계좌·통장사본).
//   2. 동의를 **이 Application에 대해** 지금 받는다. 다른 지원서의 동의를
//      복사하지 않는다. 문구·버전은 지원 경로의 canonical 카드를 재사용한다.
//   3. 동의 기록은 CONFIRMED와 **같은 트랜잭션**에 쓴다.
//   4. 신분증 grant는 확정 경로와 같은 공용 헬퍼가 만든다.
//
// grant 쓰기 위치: **POST_COMMIT_IDEMPOTENT_RECONCILABLE**.
//   좌석 트랜잭션 밖이다(기존 정책 — grant 실패로 확정을 되돌리지 않는다).
//   결정적 id `auto_${applicationId}` + approved면 덮어쓰지 않음 → 재시도 안전.
//   실패분은 callableMarkIdCardVerified의 소급 생성(pre_consent_retroactive)이 메운다.
//
// DEV 실측 요약:
//   B 통장사본 없음 / C 신분증 없음 / D 동의 없음 → 전부 400, INVITED 유지,
//     좌석·카운터·계약·grant 변화 0
//   A 정상 → CONFIRMED, 좌석 +1, 대기 -1, 동의 저장(consentAt == confirmedAt),
//     grant approved/pre_consent 생성
//   E 재시도 → alreadyConfirmed, 좌석·grant 중복 0, grant 문서 1개
//   G/H 접근 → 인가 게이트 통과(남은 404는 DEV Storage 파일 부재)
//   pre-patch 모양 INVITED → 마이그레이션 없이 같은 초대로 수락 성공

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _load(String p) => _flat(_codeOf(_src(p)));

String _callableBody(String raw, String name) {
  final start = raw.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final end = raw.indexOf('\n);', start);
  if (end < 0) throw StateError('$name 본문 끝을 찾지 못함');
  return raw.substring(start, end);
}

const _cf = 'functions/src/index.ts';
const _myApps = 'lib/screens/user/my_applications_screen.dart';
const _consent = 'lib/widgets/dialogs/apply/document_access_consent.dart';

void main() {
  final rawCf = _codeOf(_src(_cf));
  final cf = _flat(rawCf);
  final accept = _flat(_callableBody(rawCf, 'callableAcceptTOInvitation'));
  final invite = _flat(_callableBody(rawCf, 'callableInviteWorker'));
  final myApps = _load(_myApps);

  // ── PART C/D. 수락 시 readiness 재검증 ────────────────────────────

  group('초대 수락은 좌석 전에 서류를 본다', () {
    // [PII-DOC-R1.5.1] 아래 두 테스트는 원래 "통장사본을 요구한다" /
    //   "계좌 3필드를 요구한다"였다. R1.5가 직접 확정의 게이트를 신분 확인으로
    //   좁혔을 때 초대 수락만 옛 지급 prerequisite를 들고 남았고, 그래서 같은
    //   사람이 어느 버튼을 눌렀느냐로 결과가 갈렸다. 이 group이 지키려던 것은
    //   "좌석을 잡기 전에 확인한다"이지 "계좌를 확인한다"가 아니므로,
    //   요구 대상을 신분 축으로 옮기고 지급 요구가 없음을 고정한다.
    // [PII-DOC-R1.5.4] 이 두 테스트는 원래 계좌·통장사본을 요구한다는
    //   사실을 인라인 조건문으로 고정했고, R1.5.1 이 요구를 없애면서
    //   반대로 뒤집었다. 지금은 요구가 돌아왔지만 인라인이 아니라 지원과
    //   공유하는 canonical helper 로 판정한다.
    test('통장사본을 요구한다 — canonical helper 경유', () {
      expect(accept.contains('srvMissingApplicantPayoutRegistration'), true);
      expect(accept.contains('freshUserData.bankbookImagePath'), false,
          reason: '지원과 다른 자리에서 같은 질문에 답하지 않는다');
    });

    test('계좌 3필드를 요구한다 — 같은 helper', () {
      final at = rawCf.indexOf('function srvMissingApplicantPayoutRegistration(');
      expect(at, greaterThan(-1));
      final onb = _flat(rawCf.substring(at, rawCf.indexOf('\n}', at)));
      for (final f in ['bankName', 'accountNumber', 'accountHolder']) {
        expect(onb.contains(f), true, reason: f);
      }
      expect(accept.contains('freshUserData.bankName'), false);
    });

    test('신분증을 요구하고, 슬롯 공고는 인증 완료까지 요구한다', () {
      expect(
          accept.contains('if (!freshUserData.idCardImagePath && '
              '!freshUserData.idCardImageUrl) { throw new HttpsError('
              '"failed-precondition", "신분증 등록이 필요합니다."); }'),
          true);
      expect(
          accept.contains('if (appData.slotId && freshUserData.isIdVerified !== true) {'),
          true,
          reason: '지원 경로의 slotId 조건과 같다');
    });

    test('블랙리스트·본인인증도 지원 경로와 같은 조건이다', () {
      expect(accept.contains('if (freshUserData.isBlacklisted === true) {'), true);
      expect(
          accept.contains('if (!acceptIsForeign && !freshUserData.passVerifiedAt) {'),
          true,
          reason: '내국인만 PASS 필수 — 지원 경로와 동일');
    });

    test('이 검사가 좌석 커밋보다 먼저다', () {
      // [PII-DOC-R1.5.1] 기준점을 통장사본에서 신분 확인으로 옮겼다.
      final readiness = accept.indexOf('"신분증 등록이 필요합니다."');
      final matching = accept.indexOf('srvResolveMatchingReadiness(freshUserData,');
      final seat = accept.indexOf('totalConfirmed: admin.firestore.FieldValue.increment(1)');
      expect(readiness, greaterThan(-1));
      expect(matching, greaterThan(-1));
      expect(seat, greaterThan(-1));
      expect(readiness < seat, true, reason: '신분이 확인되지 않았는데 좌석을 먼저 잡지 않는다');
      expect(matching < seat, true);
    });

    test('트랜잭션 안에서 현재 사용자 문서를 다시 읽는다', () {
      expect(accept.contains('const freshUserSnap = await tx.get('
          'db.collection("users").doc(callerUid));'), true,
          reason: '초대 발송 이후 상태가 바뀔 수 있다');
    });
  });

  group('동의는 이 Application에 대해 지금 받는다', () {
    test('수락 payload가 동의를 받는다', () {
      expect(
          accept.contains('documentAccessConsentGiven: acceptDocConsentRaw, '
              'documentAccessConsentVersion: acceptDocConsentVersionRaw,'),
          true);
    });

    test('동의 없으면 수락할 수 없다', () {
      expect(
          accept.contains('if (!acceptDocConsentGiven) { throw new HttpsError( '
              '"invalid-argument", "소득신고·급여처리 목적 서류 접근에 동의해야 '
              '초대를 수락할 수 있습니다." ); }'),
          true);
    });

    test('버전은 지원 경로와 같은 resolver로 검증한다', () {
      expect(
          accept.contains('const acceptConsentVersion = '
              'resolveDocumentAccessConsentVersion( acceptDocConsentVersionRaw, '
              'acceptDocConsentGiven);'),
          true,
          reason: '미지원 버전을 조용히 최신으로 치환하지 않는다');
    });

    test('동의를 CONFIRMED와 같은 트랜잭션에 쓴다', () {
      expect(
          accept.contains('const acceptUpdate: Record<string, unknown> = { '
              'status: "CONFIRMED", confirmedAt,'),
          true);
      expect(accept.contains('documentAccessConsentGiven: true, '
          'documentAccessConsentAt: confirmedAt,'), true);
      expect(accept.contains('tx.update(appRef, acceptUpdate);'), true,
          reason: '좌석은 잡혔는데 동의 기록만 없는 상태가 생기지 않는다');
    });

    test('다른 Application의 동의를 복사하지 않는다', () {
      expect(accept.contains('.where("uid", "==", callerUid) '
          '.where("documentAccessConsentGiven", "==", true)'), false);
      expect(accept.contains('documentAccessConsentVersion: appData['), false);
    });

    test('버전은 사용자가 본 문구가 있을 때만 기록한다', () {
      expect(
          accept.contains('if (acceptConsentVersion !== null) { '
              'acceptUpdate["documentAccessConsentVersion"] = acceptConsentVersion; }'),
          true);
    });
  });

  // ── PART D 금지. 초대 발송에는 동의를 요구하지 않는다 ──────────────

  group('초대 발송은 제안일 뿐이다', () {
    test('초대 writer는 동의를 요구하지 않는다', () {
      expect(invite.contains('documentAccessConsentGiven'), false,
          reason: '초대 발송 시 consent 강제 금지');
    });

    test('초대 writer는 서류 준비도 요구하지 않는다', () {
      expect(invite.contains('"통장사본 등록이 필요합니다."'), false);
      expect(invite.contains('"신분증 등록이 필요합니다."'), false);
    });
  });

  // ── PART G. ID grant canonical helper ─────────────────────────────

  group('신분증 grant는 한 곳에서 만든다', () {
    test('공용 헬퍼가 있다', () {
      // [PII-B4-R1] 공용 grant 헬퍼가 제거됐다.
      //   확정 auto-grant 와 그 만료 공식(calcPreConsentIdCardExpiryMs,
      //   isDocumentAccessConsentV2)이 함께 제거됐다. 계산할 접근 창이
      //   없다. 지금의 계약은 test/tax_identity_review_contract_test.dart.
      expect(cf.contains('ensureIdCardGrantForConfirmedApplication'),
          isFalse);
    });

    // [CROSS-DOMAIN-R5.3E.2] 호출 수(4)로 고정하던 것을 경로 이름으로 바꾼다.
    //   그 숫자는 "확정을 만드는 경로가 전부 grant를 만든다"의 대리값이었고,
    //   경로가 정당하게 늘면(확정 재배치 수락) 계약은 같은데 숫자만 틀렸다.
    test('확정을 만드는 모든 경로가 같은 grant 헬퍼를 쓴다', () {
      // [PII-B4-R1] 모든 확정 경로에서 grant 생성이 사라졌다.
      //   확정·초대수락·재배치·계약서명·자동갱신이 만들던 신분증
      //   auto-grant를 전부 제거했다. 확정은 근무 약속이지 신분증
      //   열람 사유가 아니다. 지금의 계약은
      //   test/tax_identity_review_contract_test.dart.
      for (final n in ['callableConfirmApplication',
        'callableAcceptTOInvitation']) {
        expect(_flat(_callableBody(rawCf, n))
            .contains('idCardAccessRequests'), false, reason: n);
      }
    });

    test('결정적 id와 멱등 조건이 헬퍼 안에 있다', () {
      // [PII-B4-R1] 공용 grant 헬퍼가 제거됐다.
      //   확정 auto-grant 와 그 만료 공식(calcPreConsentIdCardExpiryMs,
      //   isDocumentAccessConsentV2)이 함께 제거됐다. 계산할 접근 창이
      //   없다. 지금의 계약은 test/tax_identity_review_contract_test.dart.
      expect(cf.contains('ensureIdCardGrantForConfirmedApplication'),
          isFalse);
    });

    test('동의·신분증이 없으면 grant를 만들지 않는다', () {
      // [PII-B4-R1] 공용 grant 헬퍼가 제거됐다.
      //   확정 auto-grant 와 그 만료 공식(calcPreConsentIdCardExpiryMs,
      //   isDocumentAccessConsentV2)이 함께 제거됐다. 계산할 접근 창이
      //   없다. 지금의 계약은 test/tax_identity_review_contract_test.dart.
      expect(cf.contains('ensureIdCardGrantForConfirmedApplication'),
          isFalse);
    });

    test('grant 실패가 확정을 되돌리지 않는다 (POST_COMMIT)', () {
      // [PII-B4-R1] 되돌릴 grant 자체가 없다. 확정 mutation 은 그대로다.
      //   확정·초대수락·재배치·계약서명·자동갱신이 만들던 신분증
      //   auto-grant를 전부 제거했다. 확정은 근무 약속이지 신분증
      //   열람 사유가 아니다. 지금의 계약은
      //   test/tax_identity_review_contract_test.dart.
      expect(_flat(_callableBody(rawCf, 'callableConfirmApplication'))
          .contains('FieldValue.increment(1)'), true);
    });

    test('실패분을 메우는 소급 경로가 남아 있다 (RECONCILABLE)', () {
      // [PII-B4-R1] 메울 grant 가 없으므로 소급 경로도 제거됐다.
      //   확정 auto-grant 와 그 만료 공식(calcPreConsentIdCardExpiryMs,
      //   isDocumentAccessConsentV2)이 함께 제거됐다. 계산할 접근 창이
      //   없다. 지금의 계약은 test/tax_identity_review_contract_test.dart.
      expect(cf.contains('pre_consent_retroactive'), isFalse);
    });
  });

  // ── PART E. 수락 UI ───────────────────────────────────────────────

  group('수락 UI는 지원 경로의 canonical 요소를 재사용한다', () {
    test('서류가 없으면 등록으로 보낸다', () {
      expect(myApps.contains('if (!meetsApplyPrerequisites(user, isFlexType: isFlex)) {'), true);
      expect(myApps.contains("ToastHelper.showWarning('근무 확정을 위해 서류 등록이 필요합니다.');"),
          true);
      expect(myApps.contains('await ApplyPrerequisitesScreen.show(context, isFlexType: isFlex);'),
          true);
    });

    test('동의 문구를 복제하지 않고 canonical 카드를 쓴다', () {
      expect(myApps.contains('DocumentAccessConsent.card(item.application.businessName),'),
          true);
      // 문구·버전의 단일 소유자는 그대로다.
      //   [R1.2] 버전 문자열을 여기서 다시 고정하지 않는다 — 그러면 문구를
      //   개정할 때마다 관계없는 테스트가 깨지고, 고정하려던 불변식
      //   (복제하지 않고 canonical 카드를 쓴다)은 그대로다.
      final c = _load(_consent);
      expect(c.contains('static const String version ='), true);
    });

    test('CTA가 동의를 명시한다', () {
      // [R5.3B] 초대 수락과 제안 수락으로 갈렸다 — 두 문구 모두 동의를 말한다.
      expect(
          myApps.contains(
              "child: Text(isOfferAccept ? '동의하고 제안 수락' : '동의하고 초대 수락',"),
          true);
      for (final label in ['동의하고 초대 수락', '동의하고 제안 수락']) {
        expect(myApps.contains(label), true, reason: 'CTA 누락: $label');
      }
    });

    test('수락 호출에 동의와 버전을 함께 보낸다', () {
      expect(
          myApps.contains("'documentAccessConsentGiven': true, "
              "'documentAccessConsentVersion': DocumentAccessConsent.version,"),
          true,
          reason: '사용자가 방금 본 문구의 버전을 보낸다');
    });
  });

  // ── PART B 회귀. 직접 지원 경로는 그대로다 ─────────────────────────

  group('직접 지원 경로는 바뀌지 않았다', () {
    final apply = _flat(_callableBody(rawCf, 'callableApplyToTO'));

    test('지원의 동의 게이트가 그대로다', () {
      expect(
          apply.contains('if (!idCardConsentGiven) { throw new HttpsError( '
              '"invalid-argument", "소득신고 목적 신분증 열람에 동의해야 지원할 수 있습니다." ); }'),
          true);
    });

    test('지원의 신원 전제조건이 그대로다', () {
      // [PII-DOC-R1.5.2] 원래는 계좌·통장사본도 함께 고정하고 있었다.
      //   이 group이 지키려는 것은 "초대 수락을 고치면서 지원 경로를 몰래
      //   바꾸지 않았다"이고, 지원의 지급 요구는 R1.5.2가 의도적으로
      //   제거했다. 신원 축만 남긴다.
      expect(apply.contains('"신분증 등록이 필요합니다."'), true);
      for (final gone in [
        '"통장 정보 등록이 필요합니다."',
        '"통장사본 등록이 필요합니다."',
      ]) {
        expect(apply.contains(gone), false, reason: gone);
      }
      // [DOCUMENT-VERIFICATION-INTEGRITY-R0] 단기 신분증 gate는 **조건**으로 고정한다.
      //   예전에는 문구('신분증 인증 후 지원할 수 있습니다')로 셌는데, 그 문장은
      //   사실과 달랐다 — isIdVerified가 뜻한 것은 업로드였다. 문구는 이제
      //   반려·재등록 상태에 따라 갈리고, 지켜야 할 것은 게이트 자체다.
      expect(apply.contains('slotId && userData["isIdVerified"] !== true'), true,
          reason: '단기(슬롯) 공고의 신분증 gate는 그대로여야 한다');
    });

    test('확정 경로의 grant 조건이 그대로다 (헬퍼로 이동만)', () {
      // [PII-B4-R1] 확정의 grant 조건 자체가 사라졌다.
      //   확정·초대수락·재배치·계약서명·자동갱신이 만들던 신분증
      //   auto-grant를 전부 제거했다. 확정은 근무 약속이지 신분증
      //   열람 사유가 아니다. 지금의 계약은
      //   test/tax_identity_review_contract_test.dart.
      expect(_flat(_callableBody(rawCf, 'callableConfirmApplication'))
          .contains('idCardAccessRequests'), false);
    });
  });
}
