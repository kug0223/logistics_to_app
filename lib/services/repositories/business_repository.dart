import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/core/business_model.dart';
import '../../models/core/business_work_type_model.dart';
import 'base_repository.dart';

/// 사업장 관련 DB 작업
class BusinessRepository extends BaseRepository {
  
  /// 사업장 ID로 조회
  Future<BusinessModel?> getBusinessById(String businessId) async {
    try {
      final doc = await firestore.collection('businesses').doc(businessId).get();
      
      if (!doc.exists) {
        print('⚠️ 사업장을 찾을 수 없습니다: $businessId');
        return null;
      }
      
      return BusinessModel.fromFirestore(doc);
    } catch (e) {
      print('❌ 사업장 조회 실패: $e');
      return null;
    }
  }

  /// 내 사업장 목록 조회
  Future<List<BusinessModel>> getMyBusinesses(String ownerId) async {
    try {
      final snapshot = await firestore
          .collection('businesses')
          .where('ownerId', isEqualTo: ownerId)
          .where('isApproved', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => BusinessModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 내 사업장 조회 실패: $e');
      return [];
    }
  }

  /// 사업장 생성
  Future<String?> createBusiness(BusinessModel business) async {
    try {
      final docRef = await firestore
          .collection('businesses')
          .add(business.toMap());
      return docRef.id;
    } catch (e) {
      print('❌ 사업장 생성 실패: $e');
      return null;
    }
  }

  // ========== 업무 유형 관리 ==========
  
  /// 사업장의 업무 유형 조회
  Future<List<BusinessWorkTypeModel>> getBusinessWorkTypes(String businessId) async {
    try {
      final snapshot = await firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .where('isActive', isEqualTo: true)
          .orderBy('displayOrder')
          .get();

      return snapshot.docs
          .map((doc) => BusinessWorkTypeModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 업무 유형 조회 실패: $e');
      return [];
    }
  }

  /// 업무 유형 생성
  Future<String?> createBusinessWorkType({
    required String businessId,
    required BusinessWorkTypeModel workType,
  }) async {
    try {
      final docRef = await firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .add(workType.toMap());

      print('✅ 업무 유형 생성 완료: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ 업무 유형 생성 실패: $e');
      return null;
    }
  }

  /// 업무 유형 수정
  Future<bool> updateBusinessWorkType({
    required String businessId,
    required String workTypeId,
    String? name,
    String? icon,
    String? color,
    String? backgroundColor,
    int? displayOrder,
    bool showToast = true,  // ⭐ 파라미터는 유지 (호환성)
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (icon != null) updates['icon'] = icon;
      if (color != null) updates['color'] = color;
      if (backgroundColor != null) updates['backgroundColor'] = backgroundColor;
      if (displayOrder != null) updates['displayOrder'] = displayOrder;

      if (updates.isEmpty) return false;

      await firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .doc(workTypeId)
          .update(updates);

      print('✅ 업무 유형 수정 완료');
      return true;
    } catch (e) {
      print('❌ 업무 유형 수정 실패: $e');
      return false;
    }
  }

  /// 업무 유형 삭제 (소프트 삭제)
  Future<bool> deleteBusinessWorkType({
    required String businessId,
    required String workTypeId,
  }) async {
    try {
      await firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .doc(workTypeId)
          .update({'isActive': false});

      print('✅ 업무 유형 삭제 완료');
      return true;
    } catch (e) {
      print('❌ 업무 유형 삭제 실패: $e');
      return false;
    }
  }

  /// 업무 유형 순서 변경 (배치 업데이트)
  Future<bool> reorderBusinessWorkTypes({
    required String businessId,
    required List<String> workTypeIds,
  }) async {
    try {
      final batch = firestore.batch();

      for (int i = 0; i < workTypeIds.length; i++) {
        final docRef = firestore
            .collection('businesses')
            .doc(businessId)
            .collection('workTypes')
            .doc(workTypeIds[i]);

        batch.update(docRef, {'displayOrder': i});
      }

      await batch.commit();

      print('✅ 순서 변경 완료');
      return true;
    } catch (e) {
      print('❌ 순서 변경 실패: $e');
      return false;
    }
  }
}