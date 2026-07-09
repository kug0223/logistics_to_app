part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 사용자 관리 (User Management)
// ═══════════════════════════════════════════════════════════

extension UserFirestore on FirestoreService {
  
  /// 사용자 정보 저장
  Future<void> saveUser(UserModel user) async {
    try {
      // [M-3] role 제거 — 권한 상승 경로 차단 (role 변경은 CF/SUPER_ADMIN 전용)
      // [SEC-UF01] merge: true — CF가 설정한 trustScore/noShowCount/isBlacklisted/badges/restrictedUntil
      //   등 서버 전용 필드를 로컬 캐시 기본값으로 덮어쓰지 않도록 방어.
      //   회원가입(신규 문서) 시에는 merge 여부와 무관하게 모든 필드 초기값 설정됨.
      final data = user.toMap()..remove('role');
      await _firestore.collection('users').doc(user.uid).set(data, SetOptions(merge: true));
      _userCache.remove(user.uid);
      _userCacheTimestamps.remove(user.uid);
    } catch (e) {
      debugPrint('❌ 사용자 저장 실패: $e');
      rethrow;
    }
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
      
      debugPrint('✅ User 조회 완료: uid=$uid');
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
    NetworkChecker.instance.assertOnline('프로필 수정을 하려면 인터넷 연결이 필요합니다.');
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