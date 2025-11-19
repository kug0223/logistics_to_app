import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/core/to_model.dart';
import '../../models/core/work_detail_model.dart';
import '../../utils/toast_helper.dart';
import 'base_repository.dart';

/// TO(Task Order) 관련 DB 작업
class TORepository extends BaseRepository {
  
  // ========== 기본 CRUD ==========
  
  /// 단일 TO 조회
  Future<TOModel?> getTO(String toId) async {
    try {
      final doc = await firestore.collection('tos').doc(toId).get();
      
      if (doc.exists) {
        return TOModel.fromMap(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      print('❌ TO 조회 실패: $e');
      return null;
    }
  }

  /// TO 수정
  Future<void> updateTO(String toId, Map<String, dynamic> updates) async {
    try {
      await firestore.collection('tos').doc(toId).update(updates);
      clearCache(key: 'to_$toId');
      print('✅ TO 수정 완료');
    } catch (e) {
      print('❌ TO 수정 실패: $e');
      rethrow;
    }
  }

  /// TO 삭제
  Future<bool> deleteTO(String toId) async {
    try {
      // 1. WorkDetails 삭제
      final workDetailsSnapshot = await firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();
      
      for (var doc in workDetailsSnapshot.docs) {
        await doc.reference.delete();
      }
      
      // 2. TO 문서 삭제
      await firestore.collection('tos').doc(toId).delete();
      
      clearCache(key: 'to_$toId');
      print('✅ TO 삭제 완료');
      ToastHelper.showSuccess('TO가 삭제되었습니다');
      return true;
    } catch (e) {
      print('❌ TO 삭제 실패: $e');
      ToastHelper.showError('TO 삭제에 실패했습니다');
      return false;
    }
  }

  // ========== 조회 메서드 ==========
  
  /// 모든 TO 조회
  Future<List<TOModel>> getAllTOs() async {
    try {
      final snapshot = await firestore
          .collection('tos')
          .orderBy('date', descending: false)
          .get();

      final toList = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      // 오늘 이후만 필터링
      final today = DateTime.now();
      return toList.where((to) {
        return to.date.isAfter(today.subtract(const Duration(days: 1)));
      }).toList();
    } catch (e) {
      print('❌ 전체 TO 조회 실패: $e');
      return [];
    }
  }

  /// 사업장별 TO 조회
  Future<List<TOModel>> getTOsByBusiness(String businessId) async {
    try {
      final snapshot = await firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .orderBy('date', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 사업장 TO 조회 실패: $e');
      return [];
    }
  }

  /// 그룹별 TO 조회
  Future<List<TOModel>> getTOsByGroup(String groupId) async {
    try {
      final snapshot = await firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .orderBy('date')
          .get();

      return snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 그룹 TO 조회 실패: $e');
      return [];
    }
  }

  /// 진행중인 TO 조회
  Future<List<TOModel>> getActiveTOs() async {
    try {
      final snapshot = await firestore
          .collection('tos')
          .orderBy('date', descending: false)
          .get();

      final allTOs = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      // 대표 TO 또는 단일 TO만 필터링
      final masterOrSingleTOs = allTOs.where((to) {
        if (to.groupId != null) {
          return to.isGroupMaster;
        }
        return true;
      }).toList();

      // 마감되지 않은 TO만
      return masterOrSingleTOs.where((to) => !to.isManualClosed).toList();
    } catch (e) {
      print('❌ 활성 TO 조회 실패: $e');
      return [];
    }
  }

  /// 마감된 TO 조회
  Future<List<TOModel>> getClosedTOs() async {
    try {
      final snapshot = await firestore
          .collection('tos')
          .where('isManualClosed', isEqualTo: true)
          .get();

      return snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 마감 TO 조회 실패: $e');
      return [];
    }
  }

  // ========== WorkDetail 관리 ==========
  
  /// WorkDetail 조회
  Future<List<WorkDetailModel>> getWorkDetails(String toId) async {
    try {
      final snapshot = await firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .orderBy('order')
          .get();

      return snapshot.docs
          .map((doc) => WorkDetailModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ WorkDetail 조회 실패: $e');
      return [];
    }
  }

  /// WorkDetail 추가
  Future<String> addWorkDetail({
    required String toId,
    required WorkDetailModel workDetail,
  }) async {
    try {
      final docRef = await firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .add({
        'workType': workDetail.workType,
        'workTypeIcon': workDetail.workTypeIcon,
        'workTypeColor': workDetail.workTypeColor,
        'workTypeBackgroundColor': workDetail.workTypeBackgroundColor,
        'wage': workDetail.wage,
        'requiredCount': workDetail.requiredCount,
        'currentCount': 0,
        'pendingCount': 0,
        'startTime': workDetail.startTime,
        'endTime': workDetail.endTime,
        'order': workDetail.order,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('✅ WorkDetail 추가 완료: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ WorkDetail 추가 실패: $e');
      rethrow;
    }
  }

  /// WorkDetail 수정
  Future<void> updateWorkDetail({
    required String toId,
    required String workDetailId,
    required Map<String, dynamic> updates,
  }) async {
    try {
      await firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .update(updates);

      print('✅ WorkDetail 수정 완료');
    } catch (e) {
      print('❌ WorkDetail 수정 실패: $e');
      rethrow;
    }
  }

  /// WorkDetail 삭제
  Future<void> deleteWorkDetail({
    required String toId,
    required String workDetailId,
  }) async {
    try {
      await firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .delete();

      print('✅ WorkDetail 삭제 완료');
    } catch (e) {
      print('❌ WorkDetail 삭제 실패: $e');
      rethrow;
    }
  }
}