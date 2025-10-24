import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/to_model.dart';
import '../models/application_model.dart';
import '../models/business_model.dart';
import '../models/work_type_model.dart';
import '../models/work_detail_model.dart';
import '../utils/toast_helper.dart';
import '../models/business_work_type_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== 사용자 관련 ====================
  
  Future<void> saveUser(UserModel user) async {
    await _firestore.collection('users').doc(user.uid).set(user.toMap());
  }

  Future<UserModel?> getUser(String uid) async {
    final doc = await _firestore.collection('users').doc(uid).get();
    if (doc.exists) {
      return UserModel.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
    }
    return null;
  }

  Future<void> updateLastLogin(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
  }

  // ==================== TO 관련 ====================

  /// 모든 TO 조회 (지원자용, 최고관리자용)
  Future<List<TOModel>> getAllTOs() async {
    try {
      print('🔍 [FirestoreService] 전체 TO 조회 시작...');

      final snapshot = await _firestore
          .collection('tos')
          .orderBy('date', descending: false)
          .get();

      final toList = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      // 오늘 날짜 이전 TO 제외
      final today = DateTime.now();
      final filteredList = toList.where((to) {
        return to.date.isAfter(today.subtract(const Duration(days: 1)));
      }).toList();

      print('✅ [FirestoreService] 전체 TO 조회 완료: ${filteredList.length}개 (오늘 이후)');
      return filteredList;
    } catch (e) {
      print('❌ [FirestoreService] 전체 TO 조회 실패: $e');
      return [];
    }
  }

  /// 특정 사업장의 TO 조회 (사업장 관리자용)
  Future<List<TOModel>> getTOsByBusiness(String businessId) async {
    try {
      print('🔍 [FirestoreService] 사업장 TO 조회 시작...');
      print('   businessId: $businessId');

      final snapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .orderBy('date', descending: false)
          .get();

      final toList = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      print('✅ [FirestoreService] 조회 완료: ${toList.length}개');
      return toList;
    } catch (e) {
      print('❌ [FirestoreService] 사업장 TO 조회 실패: $e');
      return [];
    }
  }

  /// 단일 TO 조회
  Future<TOModel?> getTO(String toId) async {
    try {
      final doc = await _firestore.collection('tos').doc(toId).get();
      
      if (doc.exists) {
        return TOModel.fromMap(doc.data()!, doc.id);
      }
      return null;
    } catch (e) {
      print('❌ [FirestoreService] TO 조회 실패: $e');
      return null;
    }
  }

 
  /// TO 수정 (관리자용)
  Future<void> updateTO(String toId, Map<String, dynamic> updates) async {
    try {
      await _firestore.collection('tos').doc(toId).update(updates);
      print('✅ [FirestoreService] TO 수정 완료');
    } catch (e) {
      print('❌ [FirestoreService] TO 수정 실패: $e');
      rethrow;
    }
  }

  /// TO 삭제 (관리자용)
  Future<void> deleteTO(String toId) async {
    try {
      await _firestore.collection('tos').doc(toId).delete();
      print('✅ [FirestoreService] TO 삭제 완료');
    } catch (e) {
      print('❌ [FirestoreService] TO 삭제 실패: $e');
      rethrow;
    }
  }

  // ==================== 지원서 관련 ====================

  
  /// TO별 지원자 목록 조회
  Future<List<ApplicationModel>> getApplicationsByTOId(String toId) async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 지원자 목록 조회 실패: $e');
      return [];
    }
  }

  /// 내 지원 내역 조회
  Future<List<ApplicationModel>> getMyApplications(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .orderBy('appliedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('내 지원 내역 조회 실패: $e');
      return [];
    }
  }

  /// TO별 지원자 목록 + 사용자 정보 조회 (관리자용)
  Future<List<Map<String, dynamic>>> getApplicantsWithUserInfo(String toId) async {
    try {
      QuerySnapshot appSnapshot = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .get();

      // 메모리에서 정렬
      final sortedDocs = appSnapshot.docs.toList()
        ..sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['appliedAt'] as Timestamp?;
          final bTime = bData['appliedAt'] as Timestamp?;
          
          if (aTime == null || bTime == null) return 0;
          return aTime.compareTo(bTime);
        });

      List<Map<String, dynamic>> result = [];

      for (var appDoc in sortedDocs) {
        final appData = appDoc.data() as Map<String, dynamic>;
        final uid = appData['uid'];

        final userDoc = await _firestore.collection('users').doc(uid).get();
        
        if (userDoc.exists) {
          final userData = userDoc.data() as Map<String, dynamic>;
          
          result.add({
            'applicationId': appDoc.id,
            'application': ApplicationModel.fromMap(appData, appDoc.id),
            'userName': userData['name'] ?? '(알 수 없음)',
            'userEmail': userData['email'] ?? '(알 수 없음)',
          });
        } else {
          result.add({
            'applicationId': appDoc.id,
            'application': ApplicationModel.fromMap(appData, appDoc.id),
            'userName': '(탈퇴한 사용자)',
            'userEmail': '(알 수 없음)',
          });
        }
      }

      return result;
    } catch (e) {
      print('지원자 목록 조회 실패: $e');
      return [];
    }
  }

  /// 지원자 승인 (관리자용)
  Future<bool> confirmApplicant(String applicationId, String adminUID) async {
    try {
      DocumentSnapshot appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data() as Map<String, dynamic>;

      if (appData['status'] == 'CONFIRMED') {
        ToastHelper.showError('이미 확정된 지원자입니다.');
        return false;
      }

      if (appData['status'] == 'CANCELED') {
        ToastHelper.showError('취소된 지원자는 확정할 수 없습니다.');
        return false;
      }

      await _firestore.collection('applications').doc(applicationId).update({
        'status': 'CONFIRMED',
        'confirmedAt': FieldValue.serverTimestamp(),
        'confirmedBy': adminUID,
      });

      ToastHelper.showSuccess('지원자가 확정되었습니다.');
      return true;
    } catch (e) {
      print('지원자 승인 실패: $e');
      ToastHelper.showError('승인 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// 지원자 거절 (관리자용)
  Future<bool> rejectApplicant(String applicationId, String adminUID) async {
    try {
      DocumentSnapshot appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data() as Map<String, dynamic>;

      if (appData['status'] == 'CANCELED') {
        ToastHelper.showError('이미 취소된 지원자입니다.');
        return false;
      }

      await _firestore.collection('applications').doc(applicationId).update({
        'status': 'REJECTED',
        'confirmedAt': FieldValue.serverTimestamp(),
        'confirmedBy': adminUID,
      });

      ToastHelper.showSuccess('지원자가 거절되었습니다.');
      return true;
    } catch (e) {
      print('지원자 거절 실패: $e');
      ToastHelper.showError('거절 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// 지원 취소 (사용자용)
  Future<bool> cancelApplication(String applicationId, String uid) async {
    try {
      DocumentSnapshot appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      ApplicationModel app = ApplicationModel.fromMap(
        appDoc.data() as Map<String, dynamic>,
        appDoc.id,
      );

      if (app.uid != uid) {
        ToastHelper.showError('본인의 지원서만 취소할 수 있습니다.');
        return false;
      }

      if (app.status == 'CONFIRMED') {
        ToastHelper.showError('확정된 TO는 취소할 수 없습니다.\n관리자에게 문의해주세요.');
        return false;
      }

      await _firestore.collection('applications').doc(applicationId).update({
        'status': 'CANCELED',
      });

      ToastHelper.showSuccess('지원이 취소되었습니다.');
      return true;
    } catch (e) {
      print('지원 취소 실패: $e');
      ToastHelper.showError('지원 취소 중 오류가 발생했습니다.');
      return false;
    }
  }

  // ==================== 사업장 관리 ====================

  /// 내 사업장 목록 조회
  Future<List<BusinessModel>> getMyBusiness(String ownerId) async {
    try {
      print('🔍 [FirestoreService] 내 사업장 조회 시작...');
      print('   ownerId: $ownerId');

      final snapshot = await _firestore
          .collection('businesses')
          .where('ownerId', isEqualTo: ownerId)
          .where('isApproved', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .get();

      final businesses = snapshot.docs
          .map((doc) => BusinessModel.fromMap(doc.data(), doc.id))
          .toList();

      print('✅ [FirestoreService] 조회 완료: ${businesses.length}개');
      return businesses;
    } catch (e) {
      print('❌ [FirestoreService] 내 사업장 조회 실패: $e');
      return [];
    }
  }

  /// 사업장 생성
  Future<String?> createBusiness(BusinessModel business) async {
    try {
      DocumentReference docRef = await _firestore
          .collection('businesses')
          .add(business.toMap());
      return docRef.id;
    } catch (e) {
      print('사업장 생성 실패: $e');
      return null;
    }
  }

  // ==================== 업무 유형 관리 ====================

  /// 모든 업무 유형 조회
  Future<List<WorkTypeModel>> getWorkTypes({bool activeOnly = false}) async {
    try {
      Query query = _firestore.collection('work_types');
      
      if (activeOnly) {
        query = query.where('isActive', isEqualTo: true);
      }
      
      query = query.orderBy('displayOrder', descending: false);
      
      QuerySnapshot snapshot = await query.get();
      
      return snapshot.docs
          .map((doc) => WorkTypeModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 업무 유형 목록 조회 실패: $e');
      return [];
    }
  }

  /// 특정 업무 유형 조회
  Future<WorkTypeModel?> getWorkType(String workTypeId) async {
    try {
      DocumentSnapshot doc = await _firestore
          .collection('work_types')
          .doc(workTypeId)
          .get();
      
      if (doc.exists) {
        return WorkTypeModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('❌ 업무 유형 조회 실패: $e');
      return null;
    }
  }

  /// 업무 유형 생성
  Future<String?> createWorkType(WorkTypeModel workType) async {
    try {
      final docRef = await _firestore.collection('work_types').add(workType.toMap());
      
      ToastHelper.showSuccess('업무 유형이 등록되었습니다.');
      return docRef.id;
    } catch (e) {
      print('❌ 업무 유형 생성 실패: $e');
      ToastHelper.showError('업무 등록에 실패했습니다.');
      return null;
    }
  }

  /// 업무 유형 수정
  Future<bool> updateWorkType(String workTypeId, WorkTypeModel workType) async {
    try {
      await _firestore.collection('work_types').doc(workTypeId).update(
        workType.copyWith(updatedAt: DateTime.now()).toMap(),
      );
      
      ToastHelper.showSuccess('업무 정보가 수정되었습니다.');
      return true;
    } catch (e) {
      print('❌ 업무 유형 수정 실패: $e');
      ToastHelper.showError('업무 수정에 실패했습니다.');
      return false;
    }
  }

  /// 업무 유형 삭제 (소프트 삭제)
  Future<bool> deleteWorkType(String workTypeId) async {
    try {
      await _firestore.collection('work_types').doc(workTypeId).update({
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      ToastHelper.showSuccess('업무 유형이 비활성화되었습니다.');
      return true;
    } catch (e) {
      print('❌ 업무 유형 삭제 실패: $e');
      ToastHelper.showError('업무 삭제에 실패했습니다.');
      return false;
    }
  }
  // ==================== 사업장별 업무 유형 관리 ====================

  /// 특정 사업장의 업무 유형 목록 조회
  Future<List<BusinessWorkTypeModel>> getBusinessWorkTypes(String businessId) async {
    try {
      print('🔍 [FirestoreService] 사업장 업무 유형 조회...');
      print('   businessId: $businessId');

      final snapshot = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .where('isActive', isEqualTo: true)
          .orderBy('displayOrder')
          .get();

      final workTypes = snapshot.docs
          .map((doc) => BusinessWorkTypeModel.fromFirestore(doc))
          .toList();

      print('✅ [FirestoreService] 조회 완료: ${workTypes.length}개');
      return workTypes;
    } catch (e) {
      print('❌ [FirestoreService] 업무 유형 조회 실패: $e');
      return [];
    }
  }

  /// 업무 유형 추가
  Future<String?> addBusinessWorkType({
    required String businessId,
    required String name,
    required String icon,
    required String color,
    int? displayOrder,
  }) async {
    try {
      print('🔍 [FirestoreService] 업무 유형 추가...');

      // displayOrder 자동 설정 (기존 개수 + 1)
      final existingTypes = await getBusinessWorkTypes(businessId);
      final order = displayOrder ?? existingTypes.length;

      final workType = BusinessWorkTypeModel(
        id: '',
        businessId: businessId,
        name: name,
        icon: icon,
        color: color,
        displayOrder: order,
        isActive: true,
        createdAt: DateTime.now(),
      );

      final docRef = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .add(workType.toMap());

      print('✅ [FirestoreService] 업무 유형 추가 완료: ${docRef.id}');
      ToastHelper.showSuccess('업무 유형이 추가되었습니다');
      return docRef.id;
    } catch (e) {
      print('❌ [FirestoreService] 업무 유형 추가 실패: $e');
      ToastHelper.showError('업무 유형 추가에 실패했습니다');
      return null;
    }
  }

  /// 업무 유형 수정
  /// 업무 유형 수정
  Future<bool> updateBusinessWorkType({
    required String businessId,
    required String workTypeId,
    String? name,
    String? icon,
    String? color,
    int? displayOrder,
    bool showToast = true,  // ✅ 이 줄 추가!
  }) async {
    try {
      print('🔍 [FirestoreService] 업무 유형 수정...');

      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (icon != null) updates['icon'] = icon;
      if (color != null) updates['color'] = color;
      if (displayOrder != null) updates['displayOrder'] = displayOrder;

      if (updates.isEmpty) {
        print('⚠️ 수정할 내용이 없습니다');
        return false;
      }

      await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .doc(workTypeId)
          .update(updates);

      print('✅ [FirestoreService] 업무 유형 수정 완료');
      
      if (showToast) {  // ✅ 이 부분 수정!
        ToastHelper.showSuccess('업무 유형이 수정되었습니다');
      }
      
      return true;
    } catch (e) {
      print('❌ [FirestoreService] 업무 유형 수정 실패: $e');
      
      if (showToast) {  // ✅ 이 부분 수정!
        ToastHelper.showError('업무 유형 수정에 실패했습니다');
      }
      
      return false;
    }
  }

  /// 업무 유형 삭제 (소프트 삭제)
  Future<bool> deleteBusinessWorkType({
    required String businessId,
    required String workTypeId,
  }) async {
    try {
      print('🔍 [FirestoreService] 업무 유형 삭제...');

      await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .doc(workTypeId)
          .update({'isActive': false});

      print('✅ [FirestoreService] 업무 유형 삭제 완료');
      ToastHelper.showSuccess('업무 유형이 삭제되었습니다');
      return true;
    } catch (e) {
      print('❌ [FirestoreService] 업무 유형 삭제 실패: $e');
      ToastHelper.showError('업무 유형 삭제에 실패했습니다');
      return false;
    }
  }

  /// 업무 유형 순서 변경 (여러 개 일괄 업데이트)
  Future<bool> reorderBusinessWorkTypes({
    required String businessId,
    required List<String> workTypeIds,
  }) async {
    try {
      print('🔍 [FirestoreService] 업무 유형 순서 변경...');

      final batch = _firestore.batch();

      for (int i = 0; i < workTypeIds.length; i++) {
        final docRef = _firestore
            .collection('businesses')
            .doc(businessId)
            .collection('workTypes')
            .doc(workTypeIds[i]);

        batch.update(docRef, {'displayOrder': i});
      }

      await batch.commit();

      print('✅ [FirestoreService] 순서 변경 완료');
      ToastHelper.showSuccess('순서가 변경되었습니다');
      return true;
    } catch (e) {
      print('❌ [FirestoreService] 순서 변경 실패: $e');
      ToastHelper.showError('순서 변경에 실패했습니다');
      return false;
    }
  }
  /// WorkDetail 생성 (TO 생성 시 함께 호출)
Future<bool> createWorkDetails({
  required String toId,
  required List<Map<String, dynamic>> workDetailsData,
}) async {
  try {
    final batch = _firestore.batch();

    for (int i = 0; i < workDetailsData.length; i++) {
      final data = workDetailsData[i];
      final docRef = _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc();

      batch.set(docRef, {
        'workType': data['workType'],
        'wage': data['wage'],
        'requiredCount': data['requiredCount'],
        'currentCount': 0,
        'order': i,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    print('✅ WorkDetails 생성 완료: ${workDetailsData.length}개');
    return true;
  } catch (e) {
    print('❌ WorkDetails 생성 실패: $e');
    ToastHelper.showError('업무 상세 정보 저장에 실패했습니다.');
    return false;
  }
}

/// 특정 TO의 WorkDetails 조회
Future<List<WorkDetailModel>> getWorkDetails(String toId) async {
  try {
    final snapshot = await _firestore
        .collection('tos')
        .doc(toId)
        .collection('workDetails')
        .orderBy('order')
        .get();

    final workDetails = snapshot.docs
        .map((doc) => WorkDetailModel.fromMap(doc.data(), doc.id))
        .toList();

    print('✅ WorkDetails 조회 완료: ${workDetails.length}개');
    return workDetails;
  } catch (e) {
    print('❌ WorkDetails 조회 실패: $e');
    return [];
  }
}

/// 특정 WorkDetail의 currentCount 증가 (지원 확정 시)
Future<bool> incrementWorkDetailCount(String toId, String workDetailId) async {
  try {
    await _firestore
        .collection('tos')
        .doc(toId)
        .collection('workDetails')
        .doc(workDetailId)
        .update({
      'currentCount': FieldValue.increment(1),
    });

    print('✅ WorkDetail currentCount 증가');
    return true;
  } catch (e) {
    print('❌ WorkDetail currentCount 증가 실패: $e');
    return false;
  }
}

/// 특정 WorkDetail의 currentCount 감소 (지원 취소/거절 시)
Future<bool> decrementWorkDetailCount(String toId, String workDetailId) async {
  try {
    await _firestore
        .collection('tos')
        .doc(toId)
        .collection('workDetails')
        .doc(workDetailId)
        .update({
      'currentCount': FieldValue.increment(-1),
    });

    print('✅ WorkDetail currentCount 감소');
    return true;
  } catch (e) {
    print('❌ WorkDetail currentCount 감소 실패: $e');
    return false;
  }
}

/// WorkDetail ID 찾기 (workType으로 검색)
Future<String?> findWorkDetailIdByType(String toId, String workType) async {
  try {
    final snapshot = await _firestore
        .collection('tos')
        .doc(toId)
        .collection('workDetails')
        .where('workType', isEqualTo: workType)
        .limit(1)
        .get();

    if (snapshot.docs.isEmpty) {
      print('⚠️ WorkDetail을 찾을 수 없음: $workType');
      return null;
    }

    return snapshot.docs.first.id;
  } catch (e) {
    print('❌ WorkDetail 검색 실패: $e');
    return null;
  }
}

/// TO 생성 (WorkDetails 포함) - 기존 createTO 메서드 대체
Future<String?> createTOWithDetails({
  required String businessId,
  required String businessName,
  required String title,
  required DateTime date,
  required String startTime,
  required String endTime,
  required DateTime applicationDeadline,
  required List<Map<String, dynamic>> workDetailsData, // [{workType, wage, requiredCount}, ...]
  String? description,
  required String creatorUID,
}) async {
  try {
    // 1. 전체 필요 인원 계산
    int totalRequired = 0;
    for (var detail in workDetailsData) {
      totalRequired += (detail['requiredCount'] as int);
    }

    // 2. TO 메인 문서 생성
    final toRef = _firestore.collection('tos').doc();
    
    await toRef.set({
      'businessId': businessId,
      'businessName': businessName,
      'title': title,
      'date': Timestamp.fromDate(date),
      'startTime': startTime,
      'endTime': endTime,
      'applicationDeadline': Timestamp.fromDate(applicationDeadline),
      'totalRequired': totalRequired,
      'totalConfirmed': 0,
      'description': description,
      'creatorUID': creatorUID,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // 3. WorkDetails 하위 컬렉션 생성
    final success = await createWorkDetails(
      toId: toRef.id,
      workDetailsData: workDetailsData,
    );

    if (!success) {
      // WorkDetails 생성 실패 시 TO 삭제
      await toRef.delete();
      return null;
    }

    print('✅ TO 생성 완료: ${toRef.id}');
    ToastHelper.showSuccess('TO가 생성되었습니다.');
    return toRef.id;
  } catch (e) {
    print('❌ TO 생성 실패: $e');
    ToastHelper.showError('TO 생성에 실패했습니다.');
    return null;
  }
}

/// 지원하기 (업무유형 선택) - 기존 applyToTO 메서드 대체
Future<bool> applyToTOWithWorkType({
  required String toId,
  required String uid,
  required String selectedWorkType,
  required int wage,
}) async {
  try {
    // 1. 중복 지원 확인
    final existingApp = await _firestore
        .collection('applications')
        .where('toId', isEqualTo: toId)
        .where('uid', isEqualTo: uid)
        .limit(1)
        .get();

    if (existingApp.docs.isNotEmpty) {
      ToastHelper.showWarning('이미 지원한 TO입니다.');
      return false;
    }

    // 2. 지원서 생성
    await _firestore.collection('applications').add({
      'toId': toId,
      'uid': uid,
      'selectedWorkType': selectedWorkType,
      'wage': wage,
      'status': 'PENDING',
      'appliedAt': FieldValue.serverTimestamp(),
    });

    print('✅ 지원 완료: TO=$toId, WorkType=$selectedWorkType');
    ToastHelper.showSuccess('지원이 완료되었습니다!');
    return true;
  } catch (e) {
    print('❌ 지원 실패: $e');
    ToastHelper.showError('지원 중 오류가 발생했습니다.');
    return false;
  }
}

/// 지원자 업무유형 변경 (관리자용)
Future<bool> changeApplicationWorkType({
  required String applicationId,
  required String newWorkType,
  required int newWage,
  required String adminUID,
}) async {
  try {
    // 1. 기존 지원서 조회
    final appDoc = await _firestore
        .collection('applications')
        .doc(applicationId)
        .get();

    if (!appDoc.exists) {
      ToastHelper.showError('지원서를 찾을 수 없습니다.');
      return false;
    }

    final appData = appDoc.data()!;
    final currentWorkType = appData['selectedWorkType'];
    final currentWage = appData['wage'];

    // 2. 업무유형 변경
    await _firestore.collection('applications').doc(applicationId).update({
      'selectedWorkType': newWorkType,
      'wage': newWage,
      'originalWorkType': appData['originalWorkType'] ?? currentWorkType, // 최초값 저장
      'originalWage': appData['originalWage'] ?? currentWage,
      'changedAt': FieldValue.serverTimestamp(),
      'changedBy': adminUID,
    });

    print('✅ 업무유형 변경 완료: $currentWorkType → $newWorkType');
    ToastHelper.showSuccess('업무유형이 변경되었습니다.');
    return true;
  } catch (e) {
    print('❌ 업무유형 변경 실패: $e');
    ToastHelper.showError('업무유형 변경에 실패했습니다.');
    return false;
  }
}

/// 지원자 확정 (WorkDetail count 업데이트 포함)
Future<bool> confirmApplicantWithWorkDetail({
  required String applicationId,
  required String toId,
  required String adminUID,
}) async {
  try {
    // 1. 지원서 조회
    final appDoc = await _firestore
        .collection('applications')
        .doc(applicationId)
        .get();

    if (!appDoc.exists) {
      ToastHelper.showError('지원서를 찾을 수 없습니다.');
      return false;
    }

    final appData = appDoc.data()!;
    final selectedWorkType = appData['selectedWorkType'];

    // 2. WorkDetail ID 찾기
    final workDetailId = await findWorkDetailIdByType(toId, selectedWorkType);
    if (workDetailId == null) {
      ToastHelper.showError('업무유형 정보를 찾을 수 없습니다.');
      return false;
    }

    // 3. Batch 업데이트
    final batch = _firestore.batch();

    // 지원서 확정
    batch.update(_firestore.collection('applications').doc(applicationId), {
      'status': 'CONFIRMED',
      'confirmedAt': FieldValue.serverTimestamp(),
      'confirmedBy': adminUID,
    });

    // WorkDetail currentCount 증가
    batch.update(
      _firestore.collection('tos').doc(toId).collection('workDetails').doc(workDetailId),
      {'currentCount': FieldValue.increment(1)},
    );

    // TO totalConfirmed 증가
    batch.update(_firestore.collection('tos').doc(toId), {
      'totalConfirmed': FieldValue.increment(1),
    });

    await batch.commit();

    print('✅ 지원자 확정 완료');
    ToastHelper.showSuccess('지원자가 확정되었습니다.');
    return true;
  } catch (e) {
    print('❌ 지원자 확정 실패: $e');
    ToastHelper.showError('확정 중 오류가 발생했습니다.');
    return false;
  }
}
}