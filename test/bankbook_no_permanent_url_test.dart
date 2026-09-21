// [R8-P5] 통장사본만 영구 다운로드 URL을 계속 만들고 있었다.
//
//   신분증은 [BUG-ID-01]에서 getDownloadURL()을 끊고 storagePath만 저장하도록
//   바꿨다. 통장사본은 그대로였다 — uploadImage()가 업로드 뒤 getDownloadURL()을
//   한 번 더 부르고(DEV 실측 warm 약 250ms), 그렇게 만든 **영구 토큰 URL**이
//   Firestore에 저장됐다.
//
//   그 URL로 하는 일은 없다:
//     · 열람은 callableGetBankbookSignedUrl(1시간 Signed URL) 전용
//     · callableGetUsersBatch는 응답에서 이 필드를 지워서 보낸다
//     · 제출 여부는 bankbookImagePath로 판단한다
//   재업로드 때 옛 파일은 지워지므로, 남은 URL은 없는 파일을 가리키는 토큰이었다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _screenPath = 'lib/screens/common/document_management_screen.dart';
const _fnPath = 'functions/src/index.ts';
const _storagePath = 'lib/services/storage_service.dart';

String _read(String p) => File(p).readAsStringSync();

/// 주석으로 시작하는 줄(`//`·`///`)을 지운다 — 표지는 코드에서만 찾는다.
String _codeOf(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 그룹 수집 시점에도 불리므로 expect 대신 예외로 실패시킨다.
String _sliceOf(String raw, String from, String to) {
  final i = raw.indexOf(from);
  if (i < 0) throw StateError('시작 표지를 찾지 못함: $from');
  final j = raw.indexOf(to, i + from.length);
  if (j < 0) throw StateError('끝 표지를 찾지 못함: $to');
  return raw.substring(i, j);
}

void main() {
  final screen = _codeOf(_read(_screenPath));
  final fn = _read(_fnPath);
  final bankbook = _sliceOf(screen,
      'Future<void> _uploadBankbookImage() async {',
      'Widget _flatPrimaryButton(');
  final idCard = _sliceOf(screen,
      'DocumentUploadHelper.pickAndVerifyIdCard(',
      'Future<void> _uploadBankbookImage() async {');
  final bbCf = _codeOf(_sliceOf(fn,
      'export const callableMarkBankbookVerified',
      'export const callableReviewUserDocument'));

  group('BBU-1 업로드가 영구 URL을 만들지 않는다', () {
    test('BBU-10 통장사본은 uploadImageNoUrl을 쓴다', () {
      expect(_flat(bankbook).contains(
          'uploadOk = await _storageService.uploadImageNoUrl(imagePath, storagePath);'),
          true);
      expect(bankbook.contains('_storageService.uploadImage('), false,
          reason: 'uploadImage는 getDownloadURL()을 부른다');
    });

    test('BBU-11 신분증과 같은 방식이다 (선례 유지)', () {
      expect(idCard.contains('uploadImageNoUrl'), true);
    });

    test('BBU-12 uploadImageNoUrl은 실제로 URL을 만들지 않는다', () {
      final body = _sliceOf(_codeOf(_read(_storagePath)),
          'Future<bool> uploadImageNoUrl(', 'Future<String?> uploadBusinessImage(');
      expect(body.contains('getDownloadURL()'), false);
    });
  });

  group('BBU-2 등록 호출이 URL을 보내지 않는다', () {
    test('BBU-20 payload는 storagePath와 selfCheck뿐이다', () {
      final call = _flat(_sliceOf(bankbook,
          "httpsCallable('callableMarkBankbookVerified')", '});'));
      expect(call.contains("'storagePath': storagePath,"), true);
      expect(call.contains("'selfCheck': picked.selfCheck,"), true);
      expect(call.contains("'imageUrl'"), false);
    });
  });

  group('BBU-3 서버가 남은 URL을 지운다', () {
    test('BBU-30 등록 시 bankbookImageUrl을 삭제한다', () {
      expect(_flat(bbCf).contains(
          'bankbookImageUrl: admin.firestore.FieldValue.delete(),'), true);
      expect(bbCf.contains('...(imageUrl ? {bankbookImageUrl: imageUrl} : {})'), false);
    });

    test('BBU-31 canonical 경로는 storagePath다', () {
      expect(_flat(bbCf).contains('bankbookImagePath: storagePath,'), true);
    });

    test('BBU-32 legacy imageUrl 입력 자체는 계속 받는다 (구버전 앱 호환)', () {
      // 구버전 앱이 URL만 보내도 경로를 뽑아 등록은 된다.
      expect(bbCf.contains('const pathMatch = imageUrl.match'), true);
    });

    test('BBU-33 경로 소유권 검증은 그대로다', () {
      expect(bbCf.contains('srvIsOwnedStoragePath(storagePath, callerUid)'), true);
    });

    test('BBU-34 Storage 파일 존재 확인도 그대로다', () {
      expect(_flat(bbCf).contains(
          'await admin.storage().bucket().file(storagePath).exists();'), true);
    });
  });

  group('BBU-4 실패·정리 경로가 경로 기반이 됐다', () {
    test('BBU-40 orphan 추적이 URL이 아니라 경로다', () {
      expect(bankbook.contains('String? newBankbookPath;'), true);
      expect(bankbook.contains('newBankbookPath = storagePath;'), true);
      expect(bankbook.contains('newBankbookPath = null;'), true);
    });

    test('BBU-41 CF 실패 시 경로로 지운다', () {
      // 표지는 코드로 잡는다 — 앞쪽 catch(기존 파일 삭제 폴백)와 섞이지 않게.
      final c = _flat(_sliceOf(bankbook, 'if (newBankbookPath != null) {', 'finally'));
      expect(c.contains('await _storageService.deleteImage(newBankbookPath);'), true);
      expect(c.contains('deleteImageByUrl'), false);
    });

    test('BBU-42 기존 파일 삭제는 path 우선 + URL 폴백 (신분증과 같은 순서)', () {
      final f = _flat(bankbook);
      expect(f.contains('final oldPath = user.bankbookImagePath;'), true);
      expect(f.contains('if (oldPath != null) { try { await _storageService.deleteImage(oldPath);'),
          true);
      expect(f.contains('} else if (oldUrl != null) {'), true,
          reason: '레거시 사용자는 URL만 갖고 있다');
    });
  });

  group('BBU-5 열람 계약 무변경', () {
    test('BBU-50 통장사본 열람은 Signed URL 전용 그대로다', () {
      final dialog = _read('lib/widgets/admin/../dialogs/worker_detail_dialog.dart');
      expect(dialog.contains("callableGetBankbookSignedUrl"), true);
    });

    test('BBU-51 제출 여부는 path 우선 판정 그대로다', () {
      final model = _flat(_codeOf(_read('lib/models/core/user_model.dart')));
      expect(
        model.contains('bool get hasBankbookDocument => '
            '(bankbookImagePath != null && bankbookImagePath!.isNotEmpty) || '
            '(bankbookImageUrl != null && bankbookImageUrl!.isNotEmpty);'),
        true,
        reason: '레거시 사용자 폴백을 없애지 않았다',
      );
    });
  });
}
