// [R7-P4.4E.1A] 사업장이 아직 없을 때 첨부를 올릴 권한.
//
//   실기기에서 신규 사업장 등록이 항상 이렇게 끝났다:
//     [firebase_functions/not-found] 사업장을 찾을 수 없습니다.
//   `callableUploadBusinessImage` 가 `assertBizAdmin` 으로 사업장 문서 존재를
//   요구하는데, 신규 등록은 그 문서를 **업로드 뒤에** 만들었다. 등록증이 신규
//   필수라 업로드는 반드시 실행됐고, 결과적으로 신규 등록은 구조적으로
//   불가능했다(af1a6f5, 2026-07-17 이후).
//
//   이 파일의 계약: 그 막힘을 푸는 대가로 **새 권한 구멍을 내지 않았다**는 것.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _cf() => File('functions/src/index.ts').readAsStringSync();
String _form() => File(
    'lib/screens/business_admin/business_form_screen.dart').readAsStringSync();
String _docs() => File(
    'lib/screens/common/document_management_screen.dart').readAsStringSync();
String _storageRules() => File('storage.rules').readAsStringSync();
String _firestoreRules() => File('firestore.rules').readAsStringSync();

/// CF 소스에서 한 export 의 본문만 잘라낸다 — **다음 top-level 선언 직전까지.**
///
///   중괄호 균형으로 자르려 했더니 `onCall({region: ...})` 의 **옵션 객체**에서
///   depth 가 먼저 0 이 되어 본문을 통째로 잘라먹었다. 고정 길이 창도 쓰지
///   않는다(코드가 옮겨가면 규칙과 무관하게 깨진다) — 선언 경계로 자른다.
String _exportBody(String src, String name) {
  final start = src.indexOf('export const $name = onCall');
  expect(start, greaterThan(-1), reason: '$name 을 찾지 못했다');
  // 옵션 객체를 건너뛰고 **핸들러 본문**부터 균형을 센다. 다음 export 까지
  // 통째로 자르면 사이에 있는 helper 들이 창 안으로 들어와 판정이 섞인다.
  final handler = src.indexOf('async (request', start);
  expect(handler, greaterThan(start), reason: '$name 의 핸들러를 찾지 못했다');
  final open = src.indexOf('{', handler);
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    final c = src[i];
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return src.substring(open, i + 1);
    }
  }
  return src.substring(open);
}

/// Dart 소스에서 `name` 선언을 감싸는 구간 — **doc 주석까지 포함**해서 준다.
/// 주석이 선언 위에 있어서 선언 위치부터 자르면 근거가 창 밖으로 나간다.
String _dartMember(String src, String declaration) {
  final decl = src.indexOf(declaration);
  expect(decl, greaterThan(-1), reason: '$declaration 을 찾지 못했다');
  final from = decl > 2500 ? decl - 2500 : 0;
  return src.substring(from, (decl + 3000).clamp(0, src.length));
}

void main() {
  group('[R7-P4.4E.1A] 기존 사업장 — 계약 무변경', () {
    test('PRECREATE-01 기존 사업장 업로드는 여전히 assertBizAdmin 을 통과해야 한다', () {
      final body = _exportBody(_cf(), 'callableUploadBusinessImage');
      expect(body.contains('await assertBizAdmin(callerUid, businessId);'), isTrue,
          reason: '83개 호출처가 공유하는 검증기다 — 이 경로에서 빼면 안 된다');
    });

    test('PRECREATE-02 타 사업장 접근은 소속 검증에서 막힌다', () {
      final src = _cf();
      final i = src.indexOf('async function assertBizAdmin');
      expect(i, greaterThan(-1));
      final body = src.substring(i, i + 3000);
      expect(body.contains('adminIds'), isTrue);
      expect(body.contains('subAdminBusinessIds'), isTrue,
          reason: '소속으로 판정한다 — 역할만으로 통과시키지 않는다');
      expect(body.contains('"not-found", "사업장을 찾을 수 없습니다."'), isTrue,
          reason: '존재하지 않는 사업장은 여전히 거부된다');
    });

    test('PRECREATE-05 임의의 존재하지 않는 businessId 는 그대로 거부된다', () {
      final body = _exportBody(_cf(), 'callableUploadBusinessImage');
      // 우회 분기를 넣지 않았다 — role/quota 만 보고 통과시키는 코드가 없다.
      expect(body.contains('bizSnap.exists'), isFalse,
          reason: 'upload callable 이 스스로 존재 판정을 재구현하면 계약이 갈라진다');
      expect(body.contains('managedBusinessIds'), isFalse,
          reason: '§6 negative control — quota 만으로 pre-create 를 허용하지 않았다');
    });
  });

  group('[R7-P4.4E.1A] pre-create 권한 — 기존 primitive 재사용', () {
    test('PRECREATE-03 신규 등록 등록증은 호출자 소유 경로로 간다', () {
      final form = _form();
      expect(form.contains("'users/\$ownerId/businessLicense_"), isTrue,
          reason: '사업장이 필요 없는 경로여야 신규 등록이 성립한다');
      expect(form.contains("httpsCallable('callableRegisterBusinessLicense')"),
          isTrue,
          reason: '경로 기록은 서버가 한다 — 클라이언트가 쓰는 값이 아니다');
    });

    test('PRECREATE-03b 서류 관리 화면과 같은 primitive 다 (새 경로를 만들지 않았다)', () {
      expect(_docs().contains("users/\${user.uid}/businessLicense_"), isTrue);
      final cf = _cf();
      // 새 callable 을 만들지 않았다.
      expect(cf.contains('callableBeginBusinessRegistration'), isFalse);
      expect(cf.contains('business_registration_staging'), isFalse);
      expect(cf.contains('pendingBusinessId'), isFalse,
          reason: '§4 — 이미 있는 구조를 재사용한다. 새 entity/lifecycle 금지');
    });

    test('PRECREATE-04 다른 uid 경로는 서버가 거부한다', () {
      final body = _exportBody(_cf(), 'callableRegisterBusinessLicense');
      expect(body.contains('srvIsOwnedStoragePath(storagePath, callerUid)'), isTrue);
      expect(body.contains('users/\${callerUid}/businessLicense_'), isTrue,
          reason: '본인 경로 + 정해진 prefix 두 가지를 모두 본다');
      expect(body.contains('.exists()'), isTrue,
          reason: '임의 문자열 등록 차단 — Storage 에 실제로 있어야 한다');
    });

    test('PRECREATE-06 만료 개념이 필요한 reservation 을 만들지 않았다', () {
      // 경로 자체가 소유권을 증명하므로 TTL 토큰이 필요 없다.
      // 만들지 않은 것을 만들었다고 기록하지 않기 위해 명시적으로 고정한다.
      final cf = _cf();
      expect(cf.contains('uploadReservation'), isFalse);
      expect(cf.contains('draftToken'), isFalse);
    });

    test('PRECREATE-07 pre-create 업로드 범위는 Storage 규칙이 이미 묶는다', () {
      final rules = _storageRules();
      final i = rules.indexOf('match /users/{uid}/{allPaths=**}');
      expect(i, greaterThan(-1));
      // [R7-P4.4E.11C.0B 갱신] 고정폭 400자 창을 쓰고 있었다. 계정 삭제
      //   write barrier(`!accountDeletionBarrierExists(uid)`)와 그 설명이
      //   들어가며 블록이 길어지자 `isUnder5MB()` 가 창 밖으로 밀려 이 셀이
      //   깨졌다 — 계약은 그대로다. 블록 **경계**까지 읽는다.
      final blockEnd = rules.indexOf('\n    }', i);
      expect(blockEnd, greaterThan(i), reason: 'users 블록의 끝을 찾지 못했다');
      final block = rules.substring(i, blockEnd);
      expect(block.contains('request.auth.uid == uid'), isTrue,
          reason: '소유권 — Firestore 읽기 없이 경로로 증명된다');
      expect(block.contains('isUnder5MB()'), isTrue, reason: '크기 상한');
      expect(block.contains('isImageType()'), isTrue, reason: '종류 상한');
    });

    test('PRECREATE-07b businesses/ 는 여전히 클라이언트가 쓸 수 없다', () {
      final rules = _storageRules();
      final i = rules.indexOf('match /businesses/{businessId}/license/');
      expect(i, greaterThan(-1));
      expect(rules.substring(i, i + 300).contains('allow create, update: if false'),
          isTrue, reason: '등록증 경로는 CF Admin SDK 전용 그대로다');
      final j = rules.indexOf('match /businesses/{businessId}/{fileName}');
      expect(rules.substring(j, j + 300).contains('allow create, update: if false'),
          isTrue, reason: '표시용 이미지도 CF 경유 그대로다');
    });
  });

  group('[R7-P4.4E.1A] 순서·마무리·재시도', () {
    test('PRECREATE-08 사업장 생성 뒤에 표시용 이미지를 올린다', () {
      final form = _form();
      final commit = form.indexOf('await batch.commit();');
      final finalize = form.indexOf('_uploadDeferredImages(uploadBizId)');
      expect(commit, greaterThan(-1));
      expect(finalize, greaterThan(commit),
          reason: '사업장이 생긴 뒤여야 assertBizAdmin 이 통과한다');
    });

    test('PRECREATE-08b 등록증 확정은 사업장 생성보다 먼저다', () {
      final form = _form();
      final license = form.indexOf('_registerOwnerBusinessLicense(ownerId');
      final commit = form.indexOf('await batch.commit();');
      expect(license, greaterThan(-1));
      expect(license, lessThan(commit),
          reason: 'onBusinessCreated 의 자동승인이 등록증을 본다 — 나중이면 놓친다');
    });

    test('PRECREATE-09 CF 가 거부하면 방금 올린 객체를 바로 지운다', () {
      final form = _form();
      final body = _dartMember(form, 'Future<void> _registerOwnerBusinessLicense');
      expect(body.contains('_storageService.deleteImage(path)'), isTrue,
          reason: '주인이 생기지 않은 객체를 남기지 않는다');
      expect(body.contains('orphan'), isTrue, reason: '남을 수 있는 경우를 기록한다');
    });

    test('PRECREATE-09b 업로드가 확인된 뒤에만 임시 파일을 치운다', () {
      final form = _form();
      final body = _dartMember(form, 'Future<void> _registerOwnerBusinessLicense');
      final upload = body.indexOf('uploadImageNoUrl');
      final del = body.indexOf('await image.delete()');
      expect(del, greaterThan(upload),
          reason: '먼저 지우면 실패 후 재시도할 첨부가 사라진다');
    });

    test('PRECREATE-10 재시도가 사업장을 두 번 만들지 않는다', () {
      final form = _form();
      // 저장은 진행 중이면 재진입하지 않는다.
      expect(form.contains('if (_isLoading || !mounted) return;'), isTrue);
      // 등록증 재등록은 서버가 같은 필드를 덮어쓴다 — 중복 canonical 이 없다.
      final body = _exportBody(_cf(), 'callableRegisterBusinessLicense');
      expect(body.contains('businessLicenseImagePath: storagePath'), isTrue);
    });

    test('PRECREATE-10b 마무리 실패가 등록을 되돌리지 않는다', () {
      final form = _form();
      final body = _dartMember(form, 'Future<bool> _uploadDeferredImages');
      expect(body.contains('부분 성공을 지우지 않는다'), isTrue);
      expect(form.contains('_SaveFailureKind.finalizeIncomplete'), isTrue,
          reason: '등록은 됐고 사진만 남았다는 것을 따로 말한다');
    });
  });

  group('[R8-P5.1] 회귀 — 위조로 readiness 를 열 수 없다', () {
    test('R8P51-01 클라이언트는 businessLicenseImagePath 를 쓸 수 없다', () {
      final rules = _firestoreRules();
      final i = rules.indexOf("'businessLicenseImageUrl', 'businessLicenseImagePath'");
      expect(i, greaterThan(-1),
          reason: 'users 문서 denylist 에 두 필드가 함께 있어야 한다');
    });

    test('R8P51-02 임의 경로로는 readiness 가 열리지 않는다', () {
      final src = _cf();
      final i = src.indexOf('async function checkBusinessLicense');
      final body = src.substring(i, i + 3500);
      expect(body.contains('users/\${ownerId}/businessLicense_'), isTrue,
          reason: 'owner 분기는 prefix 를 강제한다');
      expect(body.contains('p.includes("..")'), isTrue, reason: '경로 탈출 차단');
      expect(body.contains('parseBusinessLicensePath'), isTrue,
          reason: 'canonical 분기는 businesses/{id}/license/ 를 강제한다');
    });

    test('R8P51-03 신규 등록이 사업장 문서에 등록증 URL 을 심지 않는다', () {
      final form = _form();
      expect(form.contains('businessLicenseImageUrl = null;'), isTrue,
          reason: 'owner 경로가 진실이다 — 두 곳에 서로 다른 값을 두지 않는다');
    });
  });
}
