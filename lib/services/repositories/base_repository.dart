import 'package:cloud_firestore/cloud_firestore.dart';

/// Repository 기본 클래스
abstract class BaseRepository {
  final FirebaseFirestore firestore = FirebaseFirestore.instance;
  
  // 공통 캐시 기능
  final Map<String, dynamic> _cache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  final Duration cacheValidDuration = const Duration(minutes: 5);
  
  /// 캐시 확인
  T? getCache<T>(String key) {
    if (_cache.containsKey(key)) {
      final cacheTime = _cacheTimestamps[key];
      if (cacheTime != null && 
          DateTime.now().difference(cacheTime) < cacheValidDuration) {
        print('📦 캐시 사용: $key');
        return _cache[key] as T;
      }
    }
    return null;
  }
  
  /// 캐시 저장
  void setCache<T>(String key, T value) {
    _cache[key] = value;
    _cacheTimestamps[key] = DateTime.now();
    print('💾 캐시 저장: $key');
  }
  
  /// 캐시 삭제
  void clearCache({String? key}) {
    if (key != null) {
      _cache.remove(key);
      _cacheTimestamps.remove(key);
      print('🗑️ 캐시 삭제: $key');
    } else {
      _cache.clear();
      _cacheTimestamps.clear();
      print('🗑️ 전체 캐시 삭제');
    }
  }
}