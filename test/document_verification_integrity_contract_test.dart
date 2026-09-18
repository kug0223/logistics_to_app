// [DOCUMENT-VERIFICATION-INTEGRITY-R0] 제출 문서 무결성
//
// 이 파일이 고정하는 것:
//
//   1. 검증 판단은 기기 안에서 끝나지 않는다. 기기가 본 것은 **근거**로
//      서버에 건너가고, 상태는 서버가 정한다. 예전에는 OCR 결과가 경계를
//      넘지 않아서 무엇을 올렸든 결과가 같았다.
//
//   2. 기기 확인 통과는 '검증됨'이 아니다. 이름을 SELF_CHECK_PASSED로 둔다 —
//      AUTO_VERIFIED라고 부르면 지금 고치는 conflation을 이름만 바꿔 되만든다.
//      권위 있는 통과는 사람이 확인한 MANUAL_APPROVED 하나다.
//
//   3. OCR 실패·불일치 강행은 통과로 올라가지 않는다. 막지는 않는다 —
//      정상 사용자가 조명·카드 세대 차이로 걸리기 때문이다. 대신 기록한다.
//
//   4. 문서 경로는 그 사람의 것이어야 서명된다. rules로 막는 것만으로는
//      이미 심어진 값이 남는다 — 읽는 쪽에서 매번 본다.
//
//   5. 재업로드는 이전 판정을 물려받지 않는다.
//
//   6. 화면은 '업로드됨'을 '확인 완료'로 말하지 않는다.

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

String _callableBody(String raw, String name) {
  final start = raw.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final end = raw.indexOf('\n);', start);
  if (end < 0) throw StateError('$name 본문 끝을 찾지 못함');
  return raw.substring(start, end);
}

/// 선언 [from]부터 다음 선언 [to] 직전까지.
///
/// 중괄호 매칭을 쓰지 않는다 — 반환 타입이 객체 리터럴(`: {state: string; ...}`)
/// 이면 시그니처 안의 `{}`에서 먼저 닫혀 본문을 하나도 보지 못한다.
String _sliceOf(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _cf = 'functions/src/index.ts';
const _rules = 'firestore.rules';
const _pickHelper = 'lib/utils/document_upload_helper.dart';
const _docScreen = 'lib/screens/common/document_management_screen.dart';
const _userModel = 'lib/models/core/user_model.dart';

void main() {
  final rawCf = _codeOf(_src(_cf));
  final cf = _flat(rawCf);
  final computeState = _flat(_sliceOf(rawCf,
      'function srvComputeDocumentState(', 'function srvIsOwnedStoragePath('));
  final ownedPath = _flat(_sliceOf(rawCf,
      'function srvIsOwnedStoragePath(', 'export const sendPasswordResetCode'));
  final markId = _flat(_callableBody(rawCf, 'callableMarkIdCardVerified'));
  final markBank = _flat(_callableBody(rawCf, 'callableMarkBankbookVerified'));
  final idUrl = _flat(_callableBody(rawCf, 'callableGetIdCardSignedUrl'));
  final bankUrl = _flat(_callableBody(rawCf, 'callableGetBankbookSignedUrl'));
  final review = _flat(_callableBody(rawCf, 'callableReviewUserDocument'));
  final apply = _flat(_callableBody(rawCf, 'callableApplyToTO'));
  final rules = _flat(_src(_rules));
  final pick = _flat(_codeOf(_src(_pickHelper)));
  final screen = _flat(_codeOf(_src(_docScreen)));
  final model = _flat(_codeOf(_src(_userModel)));

  group('R0 — 상태는 서버가 정한다', () {
    test('상태 집합이 상수로 고정돼 있다', () {
      for (final s in [
        'DOC_SUBMITTED = "SUBMITTED"',
        'DOC_SELF_CHECK_PASSED = "SELF_CHECK_PASSED"',
        'DOC_SELF_CHECK_OVERRIDDEN = "SELF_CHECK_OVERRIDDEN"',
        'DOC_MANUAL_REVIEW_REQUIRED = "MANUAL_REVIEW_REQUIRED"',
        'DOC_MANUAL_APPROVED = "MANUAL_APPROVED"',
        'DOC_MANUAL_REJECTED = "MANUAL_REJECTED"',
        'DOC_REUPLOAD_REQUIRED = "REUPLOAD_REQUIRED"',
      ]) {
        expect(cf, contains(s), reason: s);
      }
    });

    test("AUTO_VERIFIED라는 상태를 만들지 않는다", () {
      expect(cf.contains('"AUTO_VERIFIED"'), isFalse,
          reason: '기기 OCR은 서버가 확인할 수 없다 — 그 값에 검증이라는 이름을 붙이면 '
              '고치려는 conflation을 이름만 바꿔 되만든다');
    });

    test('매핑 지점이 하나다', () {
      expect(cf, contains('function srvComputeDocumentState('));
      expect(markId, contains('srvComputeDocumentState(selfCheck)'));
      expect(markBank, contains('srvComputeDocumentState(selfCheck)'));
    });

    test('근거가 없으면 SUBMITTED — 없음을 통과로 읽지 않는다', () {
      expect(computeState,
          contains('return {state: DOC_SUBMITTED, evidence: null};'));
    });

    test('OCR 실패·override는 통과로 올라가지 않는다', () {
      expect(
        computeState,
        contains('if (evidence.overridden || evidence.ocrFailed) { '
            'return {state: DOC_SELF_CHECK_OVERRIDDEN, evidence}; }'),
      );
    });

    test('부분 일치도 통과가 아니다', () {
      final iPassed = computeState.indexOf('DOC_SELF_CHECK_PASSED');
      final iTail = computeState.lastIndexOf('DOC_SELF_CHECK_OVERRIDDEN');
      expect(iPassed, greaterThan(0));
      expect(iTail, greaterThan(iPassed),
          reason: '마지막 분기가 OVERRIDDEN이어야 일부만 맞은 경우가 통과로 새지 않는다');
      expect(computeState,
          contains('if (evidence.nameMatched && evidence.identifierMatched)'));
    });

    test('클라이언트가 보낸 상태 문자열을 쓰지 않는다', () {
      // request.data 구조분해에 state 계열 필드가 없어야 한다.
      for (final body in [markId, markBank]) {
        final d = body.substring(body.indexOf('request.data as {'),
            body.indexOf('};', body.indexOf('request.data as {')));
        expect(d.toLowerCase().contains('documentstate'), isFalse);
        expect(d.toLowerCase().contains('verified'), isFalse);
      }
    });
  });

  group('R0 — 기기는 판정하지 않고 근거만 만든다', () {
    test('선택 결과가 경로가 아니라 근거를 담는다', () {
      expect(pick, contains('class DocumentPickResult'));
      expect(pick, contains('final bool nameMatched;'));
      expect(pick, contains('final bool identifierMatched;'));
      expect(pick, contains('final bool ocrFailed;'));
      expect(pick, contains('final bool overridden;'));
      expect(pick, contains('Future<DocumentPickResult?> pickAndVerifyIdCard('));
      expect(pick, contains('Future<DocumentPickResult?> pickAndVerifyBankbook('));
    });

    test('OCR 실패 경로가 ocrFailed를 들고 간다', () {
      expect(pick, contains('path: image.path, ocrFailed: true, overridden: true'));
    });

    test('불일치 강행 경로가 overridden을 들고 간다', () {
      expect('overridden: true,'.allMatches(pick).length, greaterThanOrEqualTo(2),
          reason: '신분증·통장사본 두 경고 분기 모두');
    });

    test('예금주 검증을 skip한 경우를 일치로 부풀리지 않는다', () {
      expect(pick,
          contains('nameMatched: expectedName != null && '
              "result['isNameValid'] == true"));
    });

    test('호출부가 근거를 CF로 보낸다', () {
      expect(screen, contains("'selfCheck': picked.selfCheck"));
      expect('picked.selfCheck'.allMatches(screen).length, 2,
          reason: '신분증·통장사본 두 경로');
    });
  });

  group('R0 — 경로 소유권', () {
    test('소유 판정이 한 곳에 있다', () {
      expect(cf, contains('function srvIsOwnedStoragePath('));
      expect(ownedPath, contains(r'return path.startsWith(`users/${ownerUid}/`);'));
      expect(ownedPath, contains('if (path.includes("..")) return false;'),
          reason: '경로 상위 탈출 차단');
    });

    test('두 Signed URL 모두 서명 직전에 확인한다', () {
      expect(idUrl, contains('srvIsOwnedStoragePath(storagePath, targetUserId)'));
      expect(bankUrl, contains('srvIsOwnedStoragePath(storagePath, appUid)'));
    });

    test('제출 경로도 같은 판정을 쓴다', () {
      expect(markBank, contains('srvIsOwnedStoragePath(storagePath, callerUid)'));
    });

    test('rules가 통장사본 경로 필드를 클라이언트에서 막는다', () {
      expect(rules, contains("'bankbookImagePath', 'bankbookImageUrl',"));
      expect(rules,
          contains("request.resource.data.get('bankbookImagePath', null) == null"));
    });

    test('rules가 문서 상태 필드도 막는다', () {
      expect(rules, contains("'idCardDocumentState', 'idCardSelfCheck'"));
      expect(rules, contains("'bankbookDocumentState', 'bankbookSelfCheck',"));
    });
  });

  group('R0 — 재업로드는 이전 판정을 버린다', () {
    test('신분증 재업로드가 검토 결과를 지운다', () {
      expect(markId, contains('idCardReviewedBy: admin.firestore.FieldValue.delete()'));
      expect(markId, contains('idCardReviewedAt: admin.firestore.FieldValue.delete()'));
      expect(markId, contains('idCardReviewNote: admin.firestore.FieldValue.delete()'));
    });

    test('통장사본 재업로드도 동일', () {
      expect(markBank,
          contains('bankbookReviewedBy: admin.firestore.FieldValue.delete()'));
      expect(markBank,
          contains('bankbookReviewedAt: admin.firestore.FieldValue.delete()'));
    });

    test('상태는 늘 새로 계산된 값이 들어간다', () {
      expect(markId, contains('idCardDocumentState: idDoc.state'));
      expect(markBank, contains('bankbookDocumentState: bbDoc.state'));
    });
  });

  group('R0 — 사람의 판정', () {
    test('검토는 SUPER_ADMIN만', () {
      expect(review, contains('!== "SUPER_ADMIN"'));
      expect(review, contains('문서 검토 권한이 없습니다'));
    });

    test('반려·재등록 요구는 지원 자격도 내린다', () {
      expect(review, contains('patch["isIdVerified"] = false;'),
          reason: '상태만 바꾸고 지원이 계속 가능하면 반려가 아무 뜻도 갖지 못한다');
    });

    test('제출된 문서가 있어야 검토한다', () {
      expect(review, contains('제출된 문서가 없습니다'));
    });

    test('근로자에게 다음에 할 일을 알린다', () {
      expect(review, contains('다시 등록해주세요'));
      expect(review, contains('type: "documentReviewed"'));
    });
  });

  group('R0 — 막힌 이유를 말한다', () {
    test('지원 차단 문구가 상태별로 갈린다', () {
      expect(apply, contains('신분증 확인이 반려되었습니다'));
      expect(apply, contains('신분증을 다시 등록해야 지원할 수 있습니다'));
      expect(apply.contains('신분증 인증 후 지원할 수 있습니다'), isFalse,
          reason: '이 값은 인증이 아니라 업로드를 뜻했다');
    });
  });

  group('R0 — 화면', () {
    test("'확인 완료'는 사람이 확인한 상태에만 쓴다", () {
      final i = screen.indexOf("case 'MANUAL_APPROVED':");
      expect(i, greaterThan(0));
      final approvedArm = screen.substring(i, i + 160);
      expect(approvedArm, contains("label: '확인 완료'"));
      // 기본 분기는 '제출 완료'다.
      expect(screen, contains("label: '제출 완료'"));
    });

    test('관리자 확인 중 / 다시 등록 필요 상태가 표현된다', () {
      expect(screen, contains("label: '관리자 확인 중'"));
      expect(screen, contains("label: '다시 등록 필요'"));
    });

    test("업로드만으로 '등록완료' 초록 체크를 띄우지 않는다", () {
      expect(screen.contains("Text('등록완료',"), isFalse);
    });

    test('모델이 서버 상태를 그대로 읽는다 — 다시 계산하지 않는다', () {
      expect(model, contains('String? get idCardDocumentState =>'));
      expect(model, contains('String? get bankbookDocumentState =>'));
      expect(model, contains('bool get idCardNeedsReupload =>'));
      expect(model, contains('bool get idCardAwaitsReview =>'));
    });
  });

  group('R0 — 민감정보', () {
    test('selfCheck 원문을 로그에 남기지 않는다', () {
      expect(
        RegExp(r'console\.(info|log|warn|error)\([^)]*selfCheck\b').hasMatch(markId),
        isFalse,
      );
      expect(markId, contains('evidence=\${idDoc.evidence ? "present" : "none"}'));
    });
  });
}
