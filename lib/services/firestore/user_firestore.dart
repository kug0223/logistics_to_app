part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 사용자 관리 (User Management)
// ═══════════════════════════════════════════════════════════

extension UserFirestore on FirestoreService {
  
  /// 사용자 정보 저장
  Future<void> saveUser(UserModel user) async {
    await db.collection('users').doc(user.uid).set(user.toMap());
  }

  /// 사용자 정보 조회 (캐싱 적용!)
  Future<UserModel?> getUser(String uid, {bool forceRefresh = false}) async {
    try {
      print('🔍 getUser 호출: $uid, forceRefresh=$forceRefresh');
      
      // 🔥 강제 새로고침이 아닐 때만 캐시 확인
      if (!forceRefresh && userCache.containsKey(uid)) {
        final cacheTime = userCacheTimestamps[uid];
        if (cacheTime != null && DateTime.now().difference(cacheTime) < userCacheValidDuration) {
          print('📦 User 캐시 사용: $uid');
          return userCache[uid];
        }
      }
      
      print('🔄 User Firestore 조회: $uid');
      final doc = await db.collection('users').doc(uid).get();
      
      if (!doc.exists) {
        print('❌ 사용자를 찾을 수 없습니다: $uid');
        return null;
      }
      
      final user = UserModel.fromMap(doc.data()!, doc.id);
      
      // ✅ 캐시 저장
      userCache[uid] = user;
      userCacheTimestamps[uid] = DateTime.now();
      
      print('✅ User 조회 완료: ${user.name}');
      return user;
    } catch (e) {
      print('❌ 사용자 조회 실패: $e');
      return null;
    }
  }

  /// 마지막 로그인 시간 업데이트
  Future<void> updateLastLogin(String uid) async {
    await db.collection('users').doc(uid).update({
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
  }

  /// 사용자 문서 업데이트
  Future<void> updateUserDocument(String uid, Map<String, dynamic> data) async {
    try {
      await db.collection('users').doc(uid).update(data);
      
      // 캐시 무효화
      userCache.remove(uid);
      userCacheTimestamps.remove(uid);
      
      print('✅ 사용자 정보 업데이트 완료: $uid');
    } catch (e) {
      print('❌ 사용자 정보 업데이트 실패: $e');
      rethrow;
    }
  }
}