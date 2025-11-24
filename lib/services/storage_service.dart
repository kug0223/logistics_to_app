import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
        // 웹은 별도 처리 필요 (일단 패스)
        print('⚠️ 웹 환경에서는 Storage 업로드 미지원');
        return null;
      }

      final file = File(filePath);
      if (!await file.exists()) {
        print('❌ 파일이 존재하지 않음: $filePath');
        return null;
      }

      final ref = _storage.ref().child(storagePath);
      final uploadTask = await ref.putFile(file);
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      print('✅ Storage 업로드 성공: $downloadUrl');
      return downloadUrl;
    } catch (e) {
      print('❌ Storage 업로드 실패: $e');
      return null;
    }
  }

  /// 이미지 삭제
  Future<bool> deleteImage(String storagePath) async {
    try {
      final ref = _storage.ref().child(storagePath);
      await ref.delete();
      print('✅ Storage 삭제 성공: $storagePath');
      return true;
    } catch (e) {
      print('❌ Storage 삭제 실패: $e');
      return false;
    }
  }
}