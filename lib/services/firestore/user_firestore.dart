part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 사용자 관리 (User Management)
// ═══════════════════════════════════════════════════════════

extension UserFirestore on FirestoreService {
  
  /// 사용자 정보 저장
  Future<void> saveUser(UserModel user) async {
    await _firestore.collection('users').doc(user.uid).set(user.toMap());
    _userCache.remove(user.uid);
    _userCacheTimestamps.remove(user.uid);
  }

  /// 사용자 정보 조회 (캐싱 적용!)
  Future<UserModel?> getUser(String uid, {bool forceRefresh = false}) async {
    try {
      debugPrint('🔍 getUser 호출: $uid, forceRefresh=$forceRefresh');
      
      // 🔥 강제 새로고침이 아닐 때만 캐시 확인
      if (!forceRefresh && _userCache.containsKey(uid)) {
        final cacheTime = _userCacheTimestamps[uid];
        if (cacheTime != null && DateTime.now().difference(cacheTime) < FirestoreService._userCacheTTL) {
          debugPrint('📦 User 캐시 사용: $uid');
          return _userCache[uid];
        }
      }
      
      debugPrint('🔄 User Firestore 조회: $uid');
      final doc = await _firestore.collection('users').doc(uid).get();
      
      if (!doc.exists) {
        debugPrint('❌ 사용자를 찾을 수 없습니다: $uid');
        return null;
      }
      
      final user = UserModel.fromMap(doc.data()!, doc.id);
      
      // ✅ 캐시 저장
      _userCache[uid] = user;
      _userCacheTimestamps[uid] = DateTime.now();
      
      debugPrint('✅ User 조회 완료: ${user.name}');
      return user;
    } catch (e) {
      debugPrint('❌ 사용자 조회 실패: $e');
      return null;
    }
  }

  /// 마지막 로그인 시간 업데이트
  Future<void> updateLastLogin(String uid) async {
    try {
      await _firestore.collection('users').doc(uid).update({
        'lastLoginAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('⚠️ updateLastLogin 실패 ($uid): $e');
    }
  }

  Future<void> updateUserDocument(String uid, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('users').doc(uid).update(data);
      
      // 캐시 무효화
      _userCache.remove(uid);
      _userCacheTimestamps.remove(uid);
      
      debugPrint('✅ 사용자 정보 업데이트 완료: $uid');
    } catch (e) {
      debugPrint('❌ 사용자 정보 업데이트 실패: $e');
      rethrow;
    }
  }
  
}