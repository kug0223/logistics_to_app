part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 사용자 관리 (User Management)
// ═══════════════════════════════════════════════════════════

extension UserFirestore on FirestoreService {
  
  /// 사용자 정보 저장
  Future<void> saveUser(UserModel user) async {
    try {
      // [SEC-UF01] _protectedUserFields 전체 제거 — role 포함 모든 서버 전용 필드를
      //   클라이언트 기본값으로 덮어쓰지 않도록 방어 (merge:true여도 기존 값 덮어씀).
      //   Firestore rules가 1차 차단, 코드에서 2차 차단. rules denylist와 반드시 동기화.
      //   회원가입(신규 문서) 시 trustScore 등 초기값은 CF(callableRegister)가 별도 설정.
      final data = user.toMap()..removeWhere((k, _) => _protectedUserFields.contains(k));
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
      if (kDebugMode) debugPrint('🔍 getUser 호출: $uid, forceRefresh=$forceRefresh');

      // 🔥 강제 새로고침이 아닐 때만 캐시 확인
      if (!forceRefresh && _userCache.containsKey(uid)) {
        final cacheTime = _userCacheTimestamps[uid];
        if (cacheTime != null && DateTime.now().difference(cacheTime) < FirestoreService._userCacheTTL) {
          if (kDebugMode) debugPrint('📦 User 캐시 사용: $uid');
          return _userCache[uid];
        }
      }

      if (kDebugMode) debugPrint('🔄 User Firestore 조회: $uid');
      final doc = await _firestore.collection('users').doc(uid).get();

      if (!doc.exists) {
        if (kDebugMode) debugPrint('❌ 사용자를 찾을 수 없습니다: $uid');
        return null;
      }

      final user = UserModel.fromMap(doc.data()!, doc.id);

      // ✅ 캐시 저장
      _userCache[uid] = user;
      _userCacheTimestamps[uid] = DateTime.now();

      if (kDebugMode) debugPrint('✅ User 조회 완료: uid=$uid');
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

  // CF/보안 규칙이 차단해야 하는 민감 필드 목록 (코드 레벨 2차 방어)
  // Firestore rules owner-update denylist와 반드시 동기화 유지
  static const _protectedUserFields = {
    'role', 'isBlacklisted', 'subAdminBusinessIds', 'subAdminOf', 'businessId',
    'blacklistReason', 'blacklistedBy', 'blacklistedAt',
    'unblacklistedBy', 'unblacklistedAt',
    'trustScore', 'noShowCount', 'recentNoShowCount', 'noShowDates',
    'lateCount', 'recentLateCount', 'lateDates', 'totalWorkDays', 'lastRestartAt',
    'restrictedUntil', 'isAdmin', 'sealBase64',
    'accountStatus', 'rejectionReason', 'approvedBy', 'approvedAt',
    'rejectedBy', 'rejectedAt',
    'ci', 'ciHash', 'passVerifiedAt',
    'averageRating', 'reviewCount', 'rehireRate', 'totalWorkHours',
    'passwordHistory', 'badges',
    'termsConsentAt', 'termsConsent',
    'isIdVerified', 'idCardVerifiedAt',
    'isDummy', // [RULE-FIX-H2] 계정 영구 삭제 유도 방지
  };

  Future<void> updateUserDocument(String uid, Map<String, dynamic> data) async {
    NetworkChecker.instance.assertOnline('프로필 수정을 하려면 인터넷 연결이 필요합니다.');
    // 민감 필드 방어적 제거 (Firestore 규칙이 1차 차단, 코드에서 2차 차단)
    final sanitized = Map<String, dynamic>.from(data)
      ..removeWhere((k, _) => _protectedUserFields.contains(k));
    if (sanitized.isEmpty) return;
    try {
      await _firestore.collection('users').doc(uid).update(sanitized);
      _userCache.remove(uid);
      _userCacheTimestamps.remove(uid);
      if (kDebugMode) debugPrint('✅ 사용자 정보 업데이트 완료: $uid');
    } catch (e) {
      debugPrint('❌ 사용자 정보 업데이트 실패: $e');
      rethrow;
    }
  }
  
}