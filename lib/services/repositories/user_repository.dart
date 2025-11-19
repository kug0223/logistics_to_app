import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/core/user_model.dart';
import 'base_repository.dart';

/// 사용자 관련 DB 작업
class UserRepository extends BaseRepository {
  
  /// 사용자 정보 저장
  Future<void> saveUser(UserModel user) async {
    await firestore.collection('users').doc(user.uid).set(user.toMap());
    clearCache(key: 'user_${user.uid}');
  }

  /// 사용자 정보 조회 (캐싱)
  Future<UserModel?> getUser(String uid, {bool forceRefresh = false}) async {
    try {
      // 캐시 확인
      if (!forceRefresh) {
        final cached = getCache<UserModel>('user_$uid');
        if (cached != null) return cached;
      }
      
      final doc = await firestore.collection('users').doc(uid).get();
      
      if (!doc.exists) {
        print('❌ 사용자를 찾을 수 없습니다: $uid');
        return null;
      }
      
      final user = UserModel.fromMap(doc.data()!, doc.id);
      setCache('user_$uid', user);
      
      return user;
    } catch (e) {
      print('❌ 사용자 조회 실패: $e');
      return null;
    }
  }

  /// 마지막 로그인 시간 업데이트
  Future<void> updateLastLogin(String uid) async {
    await firestore.collection('users').doc(uid).update({
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
    clearCache(key: 'user_$uid');
  }
}