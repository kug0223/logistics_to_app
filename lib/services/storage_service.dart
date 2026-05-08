import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart' show XFile;

/// Firebase Storage 서비스
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// 이미지 업로드 후 다운로드 URL 반환
  ///
  /// 웹: XFile로 bytes를 읽어 putData 사용
  /// 모바일: putFile 사용
  Future<String?> uploadImage(String filePath, String storagePath) async {
    try {
      final ref = _storage.ref().child(storagePath);

      if (kIsWeb) {
        final bytes = await XFile(filePath).readAsBytes();
        await ref.putData(bytes);
      } else {
        final file = File(filePath);
        if (!await file.exists()) {
          debugPrint('❌ 파일이 존재하지 않음: $filePath');
          return null;
        }
        await ref.putFile(file);
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
  Future<String?> uploadImageBytes(Uint8List bytes, String storagePath) async {
    try {
      final ref = _storage.ref().child(storagePath);
      await ref.putData(bytes);
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

  /// 여러 이미지 일괄 삭제
  Future<void> deleteMultipleByUrls(List<String> urls) async {
    for (final url in urls) {
      await deleteImageByUrl(url);
    }
  }

  /// Firebase Storage URL인지 확인
  bool _isFirebaseStorageUrl(String url) {
    return url.contains('firebasestorage.googleapis.com') ||
           url.contains('storage.googleapis.com');
  }
}