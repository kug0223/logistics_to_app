import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// Firebase Storage 서비스
///
/// [SIGNED-URL-AUDIT] 파일 유형별 Signed URL 적용 현황 — 재탐색 금지.
///
/// ① 신분증(idCardImageUrl): callableGetIdCardSignedUrl CF로 1시간 만료 Signed URL 발급.
///    idCardAccessRequests 승인 확인 후 반환. 이미 완전 구현됨.
///
/// ② 계약서(signature_*.png, contract.pdf): Storage rules allow read: if false
///    → SDK 직접 경로 접근 차단. 다운로드 URL 토큰 방식이 실질 보호막.
///    계약 당사자 공유 파일이므로 추가 Signed URL 불필요.
///
/// ③ 통장사본/사업자등록증(bankbookImageUrl 등): users/{uid}/... 경로,
///    Storage rules에서 본인(uid)만 읽기 허용.
///    callableGetUsersBatch CF가 배치 응답에서 bankbookImageUrl 필드 제거.
///    Firestore rules도 users/{uid} 문서 접근을 본인·소속 관리자로 제한.
///    → 추가 Signed URL 불필요.
///
/// ④ 프로필 사진/사업장 이미지: 민감 데이터 아님. 공개 URL 적합.
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  static const _validImageExtensions = {
    '.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.heif'
  };

  static const _extensionToMime = {
    '.jpg': 'image/jpeg',
    '.jpeg': 'image/jpeg',
    '.png': 'image/png',
    '.gif': 'image/gif',
    '.webp': 'image/webp',
    '.heic': 'image/heic',
    '.heif': 'image/heif',
  };

  String? _mimeFromPath(String filePath) {
    final lower = filePath.toLowerCase();
    for (final entry in _extensionToMime.entries) {
      if (lower.endsWith(entry.key)) return entry.value;
    }
    return null;
  }

  bool _isValidImagePath(String filePath) {
    final lower = filePath.toLowerCase();
    return _validImageExtensions.any((ext) => lower.endsWith(ext));
  }

  /// 이미지 업로드 후 다운로드 URL 반환
  ///
  /// 웹: XFile로 bytes를 읽어 putData 사용
  /// 모바일: putFile 사용
  Future<String?> uploadImage(String filePath, String storagePath) async {
    if (!_isValidImagePath(filePath)) {
      debugPrint('❌ 유효하지 않은 이미지 형식: $filePath');
      return null;
    }
    try {
      final ref = _storage.ref().child(storagePath);
      final contentType = _mimeFromPath(filePath) ?? 'image/jpeg';
      final metadata = SettableMetadata(contentType: contentType);

      if (kIsWeb) {
        final bytes = await XFile(filePath).readAsBytes();
        await ref.putData(bytes, metadata);
      } else {
        final file = File(filePath);
        if (!await file.exists()) {
          debugPrint('❌ 파일이 존재하지 않음: $filePath');
          return null;
        }
        await ref.putFile(file, metadata);
      }

      final downloadUrl = await ref.getDownloadURL();
      debugPrint('✅ Storage 업로드 성공: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('❌ Storage 업로드 실패: $e');
      return null;
    }
  }

  /// bytes 직접 업로드 (웹에서 XFile.readAsBytes() 결과 전달 시 사용)
  Future<String?> uploadImageBytes(
    Uint8List bytes,
    String storagePath, {
    String contentType = 'image/jpeg',
  }) async {
    try {
      final ref = _storage.ref().child(storagePath);
      await ref.putData(bytes, SettableMetadata(contentType: contentType));
      final downloadUrl = await ref.getDownloadURL();
      debugPrint('✅ Storage 바이트 업로드 성공: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('❌ Storage 바이트 업로드 실패: $e');
      return null;
    }
  }

  /// 이미지 삭제 (경로 기반)
  Future<bool> deleteImage(String storagePath) async {
    try {
      // 빈 경로 체크
      if (storagePath.isEmpty) {
        debugPrint('⚠️ 빈 경로 (무시)');
        return true;
      }

      final ref = _storage.ref().child(storagePath);

      // 파일 존재 여부 확인
      try {
        await ref.getMetadata();
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found') {
          debugPrint('⚠️ 파일이 이미 없음 (무시): $storagePath');
          return true;
        }
        rethrow;
      }

      await ref.delete();
      debugPrint('✅ Storage 삭제 성공: $storagePath');
      return true;
    } catch (e) {
      debugPrint('❌ Storage 삭제 실패: $e');
      return false;
    }
  }

  /// URL로 이미지 삭제 (다운로드 URL → Storage Path 변환)
  Future<bool> deleteImageByUrl(String downloadUrl) async {
    try {
      // 1. Firebase Storage URL인지 확인
      if (!_isFirebaseStorageUrl(downloadUrl)) {
        debugPrint('⚠️ Firebase Storage URL이 아님 (무시): $downloadUrl');
        return true;
      }

      // 2. URL에서 Storage Reference 생성
      final ref = _storage.refFromURL(downloadUrl);

      // 3. 파일 존재 여부 확인
      try {
        await ref.getMetadata();
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found') {
          debugPrint('⚠️ 파일이 이미 없음 (무시): ${ref.fullPath}');
          return true;
        }
        rethrow;
      }

      // 4. 파일 삭제
      await ref.delete();
      debugPrint('✅ Storage 삭제 성공 (URL): ${ref.fullPath}');
      return true;
    } catch (e) {
      debugPrint('❌ Storage 삭제 실패 (URL): $e');
      return false;
    }
  }

  /// 파일 존재 여부 확인
  Future<bool> exists(String storagePath) async {
    try {
      final ref = _storage.ref().child(storagePath);
      await ref.getMetadata();
      return true;
    } on FirebaseException catch (e) {
      if (e.code == 'object-not-found') {
        return false;
      }
      rethrow;
    }
  }

  /// 여러 이미지 일괄 삭제 (병렬) — 개별 실패 시 나머지 계속 진행
  Future<void> deleteMultipleByUrls(List<String> urls) async {
    await Future.wait(
      urls.map((url) => deleteImageByUrl(url).catchError((e) {
        debugPrint('⚠️ 이미지 삭제 실패 (계속 진행): $url — $e');
        return false;
      })),
    );
  }

  /// Firebase Storage URL인지 확인
  bool _isFirebaseStorageUrl(String url) {
    return url.contains('firebasestorage.googleapis.com') ||
           url.contains('storage.googleapis.com');
  }
}