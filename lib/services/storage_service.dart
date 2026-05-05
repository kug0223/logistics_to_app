import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

/// Firebase Storage 서비스
class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// 이미지 업로드 후 다운로드 URL 반환
  /// 
  /// [filePath]: 로컬 파일 경로
  /// [storagePath]: Storage 저장 경로 (예: 'users/uid/idCard.jpg')
  Future<String?> uploadImage(String filePath, String storagePath) async {
    try {
      if (kIsWeb) {
        debugPrint('⚠️ 웹 환경에서는 Storage 업로드 미지원');
        return null;
      }

      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('❌ 파일이 존재하지 않음: $filePath');
        return null;
      }

      final ref = _storage.ref().child(storagePath);
      final uploadTask = await ref.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      debugPrint('✅ Storage 업로드 성공: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      debugPrint('❌ Storage 업로드 실패: $e');
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