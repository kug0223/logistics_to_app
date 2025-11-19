import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/core/application_model.dart';
import 'base_repository.dart';

/// 지원서 관련 DB 작업
class ApplicationRepository extends BaseRepository {
  
  /// 내 지원 내역 조회
  Future<List<ApplicationModel>> getMyApplications(String uid) async {
    try {
      final snapshot = await firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .orderBy('appliedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 내 지원 내역 조회 실패: $e');
      return [];
    }
  }

  /// TO별 지원자 조회
  Future<List<ApplicationModel>> getApplicationsByTOId(String toId) async {
    try {
      // 1. TO 정보 조회
      final toDoc = await firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return [];
      }

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      // 2. 지원서 조회
      final snapshot = await firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 지원자 목록 조회 실패: $e');
      return [];
    }
  }

  /// 사업장별 지원서 조회
  Future<List<ApplicationModel>> getApplicationsByBusinessId(String businessId) async {
    try {
      final snapshot = await firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 사업장별 지원서 조회 실패: $e');
      return [];
    }
  }

  /// 지원서 업데이트
  Future<bool> updateApplication(
    String applicationId,
    Map<String, dynamic> data,
  ) async {
    try {
      await firestore
          .collection('applications')
          .doc(applicationId)
          .update(data);
      
      print('✅ 지원서 업데이트 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 지원서 업데이트 실패: $e');
      return false;
    }
  }

  /// 지원서 삭제
  Future<bool> deleteApplication(String applicationId) async {
    try {
      await firestore
          .collection('applications')
          .doc(applicationId)
          .delete();
      
      print('✅ 지원서 삭제 완료');
      return true;
    } catch (e) {
      print('❌ 지원서 삭제 실패: $e');
      return false;
    }
  }
}