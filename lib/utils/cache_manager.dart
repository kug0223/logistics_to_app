import 'package:cloud_firestore/cloud_firestore.dart';

/// Firestore 캐시 관리 헬퍼
/// 
/// 데이터 변경 후 최신 데이터를 서버에서 직접 조회할 때 사용
class CacheManager {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 단일 문서 서버 직접 조회
  static Future<DocumentSnapshot<Map<String, dynamic>>> getDocument(
    String collection,
    String docId,
  ) async {
    return _firestore
        .collection(collection)
        .doc(docId)
        .get(const GetOptions(source: Source.server));
  }

  /// 컬렉션 서버 직접 조회 (조건 없음)
  static Future<QuerySnapshot<Map<String, dynamic>>> getCollection(
    String collection,
  ) async {
    return _firestore
        .collection(collection)
        .get(const GetOptions(source: Source.server));
  }

  /// 컬렉션 서버 직접 조회 (조건 있음)
  static Future<QuerySnapshot<Map<String, dynamic>>> getCollectionWhere(
    String collection, {
    required String field,
    required dynamic isEqualTo,
  }) async {
    return _firestore
        .collection(collection)
        .where(field, isEqualTo: isEqualTo)
        .get(const GetOptions(source: Source.server));
  }

  /// 서브컬렉션 서버 직접 조회
  static Future<QuerySnapshot<Map<String, dynamic>>> getSubCollection(
    String parentCollection,
    String parentDocId,
    String subCollection,
  ) async {
    return _firestore
        .collection(parentCollection)
        .doc(parentDocId)
        .collection(subCollection)
        .get(const GetOptions(source: Source.server));
  }

  /// Firestore 캐시 완전 클리어
  static Future<void> clearAllCache() async {
    await _firestore.clearPersistence();
  }
}