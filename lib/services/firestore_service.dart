import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/to_model.dart';
import '../models/application_model.dart';
import '../utils/toast_helper.dart';
import '../models/center_model.dart';        // ✅ 추가!
import '../models/work_type_model.dart';     // ✅ 추가!
import '../models/business_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ==================== 사용자 관련 (기존 코드 유지) ====================
  
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

  // ==================== TO 관련 (기존 코드 유지) ====================

  Future<List<TOModel>> getTOsByCenter(String centerId, {DateTime? date}) async {
    try {
      Query query = _firestore
          .collection('tos')
          .where('centerId', isEqualTo: centerId)
          .orderBy('date', descending: false);

      if (date != null) {
        DateTime startOfDay = DateTime(date.year, date.month, date.day);
        DateTime endOfDay = DateTime(date.year, date.month, date.day, 23, 59, 59);
        
        query = query
            .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
            .where('date', isLessThanOrEqualTo: Timestamp.fromDate(endOfDay));
      }

      QuerySnapshot snapshot = await query.get();

      return snapshot.docs
          .map((doc) => TOModel.fromMap(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ))
          .toList();
    } catch (e) {
      print('TO 목록 가져오기 실패: $e');
      return [];
    }
  }

  Future<List<TOModel>> getAllTOs() async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('tos')
          .orderBy('date', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => TOModel.fromMap(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ))
          .toList();
    } catch (e) {
      print('전체 TO 목록 가져오기 실패: $e');
      return [];
    }
  }

  Future<TOModel?> getTO(String toId) async {
    final doc = await _firestore.collection('tos').doc(toId).get();
    if (doc.exists) {
      return TOModel.fromMap(
        doc.data() as Map<String, dynamic>,
        doc.id,
      );
    }
    return null;
  }

  Future<void> deleteTO(String toId) async {
    await _firestore.collection('tos').doc(toId).delete();
  }

  Future<void> updateTOCurrentCount(String toId, int newCount) async {
    await _firestore.collection('tos').doc(toId).update({
      'currentCount': newCount,
    });
  }

  // ==================== 지원서 관련 (새로 추가!) ====================

  /// TO에 지원하기 (무조건 PENDING 상태)
  Future<bool> applyToTO(String toId, String uid) async {
    try {
      // 1. 중복 지원 체크 (같은 TO에 이미 지원했는지)
      QuerySnapshot existingApps = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .where('uid', isEqualTo: uid)
          .where('status', whereIn: ['PENDING', 'CONFIRMED'])
          .get();

      if (existingApps.docs.isNotEmpty) {
        ToastHelper.showError('이미 해당 TO에 지원했습니다.');
        return false;
      }

      // 2. 지원서 생성 (무조건 PENDING)
      await _firestore.collection('applications').add({
        'toId': toId,
        'uid': uid,
        'status': 'PENDING',
        'appliedAt': FieldValue.serverTimestamp(),
        'confirmedAt': null,
        'confirmedBy': null,
      });

      ToastHelper.showSuccess('지원이 완료되었습니다!\n관리자 승인을 기다려주세요.');
      return true;
    } catch (e) {
      print('지원 실패: $e');
      ToastHelper.showError('지원 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// 내 지원 내역 조회
  Future<List<ApplicationModel>> getMyApplications(String uid) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .orderBy('appliedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromMap(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ))
          .toList();
    } catch (e) {
      print('지원 내역 조회 실패: $e');
      return [];
    }
  }

  /// 특정 TO의 지원자 목록 조회 (관리자용)
  Future<List<ApplicationModel>> getApplicationsByTO(String toId) async {
    try {
      QuerySnapshot snapshot = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .orderBy('appliedAt', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromMap(
                doc.data() as Map<String, dynamic>,
                doc.id,
              ))
          .toList();
    } catch (e) {
      print('지원자 목록 조회 실패: $e');
      return [];
    }
  }

  /// 지원 취소 (사용자가 직접)
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

      // 본인 확인
      if (app.uid != uid) {
        ToastHelper.showError('본인의 지원서만 취소할 수 있습니다.');
        return false;
      }

      // 이미 확정된 경우 취소 불가
      if (app.status == 'CONFIRMED') {
        ToastHelper.showError('확정된 TO는 취소할 수 없습니다.\n관리자에게 문의해주세요.');
        return false;
      }

      // 상태 변경
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
  /// TO별 지원자 목록 + 사용자 정보 조회 (관리자용)
  Future<List<Map<String, dynamic>>> getApplicantsWithUserInfo(String toId) async {
    try {
      // 1. 지원서 조회 (orderBy 제거!)
      QuerySnapshot appSnapshot = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .get(); // orderBy 제거!

      // 2. 메모리에서 정렬
      final sortedDocs = appSnapshot.docs.toList()
        ..sort((a, b) {
          final aData = a.data() as Map<String, dynamic>;
          final bData = b.data() as Map<String, dynamic>;
          final aTime = aData['appliedAt'] as Timestamp?;
          final bTime = bData['appliedAt'] as Timestamp?;
          
          if (aTime == null || bTime == null) return 0;
          return aTime.compareTo(bTime); // 오름차순 정렬
        });

      List<Map<String, dynamic>> result = [];

      // 3. 각 지원서에 대한 사용자 정보 가져오기
      for (var appDoc in sortedDocs) {
        final appData = appDoc.data() as Map<String, dynamic>;
        final uid = appData['uid'];

        // 사용자 정보 조회
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
          // 사용자 정보가 없는 경우 (탈퇴한 사용자)
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
      // 1. 지원서 확인
      DocumentSnapshot appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data() as Map<String, dynamic>;

      // 2. 이미 확정된 경우
      if (appData['status'] == 'CONFIRMED') {
        ToastHelper.showError('이미 확정된 지원자입니다.');
        return false;
      }

      // 3. 취소된 경우
      if (appData['status'] == 'CANCELED') {
        ToastHelper.showError('취소된 지원자는 확정할 수 없습니다.');
        return false;
      }

      // 4. 상태 업데이트
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
      // 1. 지원서 확인
      DocumentSnapshot appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data() as Map<String, dynamic>;

      // 2. 취소된 경우
      if (appData['status'] == 'CANCELED') {
        ToastHelper.showError('이미 취소된 지원자입니다.');
        return false;
      }

      // 3. 상태 업데이트
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
  /// TO 생성 (관리자 전용)
  Future<String> createTO({
    required String centerId,
    required String centerName,
    required DateTime date,
    required String startTime,
    required String endTime,
    required String workType,
    required int requiredCount,
    required String description,
    required String creatorUID,
  }) async {
    try {
      print('📝 TO 생성 시작...');
      print('센터: $centerName ($centerId)');
      print('날짜: $date');
      print('시간: $startTime ~ $endTime');
      print('업무: $workType');
      print('인원: $requiredCount명');

      final docRef = await _firestore.collection('tos').add({
        'centerId': centerId,
        'centerName': centerName,
        'date': Timestamp.fromDate(date),
        'startTime': startTime,
        'endTime': endTime,
        'requiredCount': requiredCount,
        'currentCount': 0, // 초기값 0
        'workType': workType,
        'description': description,
        'creatorUID': creatorUID,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('✅ TO 생성 완료! 문서 ID: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ TO 생성 실패: $e');
      rethrow;
    }
  }
  
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

 // ==================== 센터 관리 (사업장 관리) ✨ NEW! ====================

/// 모든 센터 조회 (활성화된 센터만 또는 전체)
Future<List<CenterModel>> getCenters({bool activeOnly = false}) async {
  try {
    Query query = _firestore.collection('centers');
    
    if (activeOnly) {
      query = query.where('isActive', isEqualTo: true);
    }
    
    query = query.orderBy('code', descending: false);
    
    QuerySnapshot snapshot = await query.get();
    
    return snapshot.docs
        .map((doc) => CenterModel.fromFirestore(doc))
        .toList();
  } catch (e) {
    print('❌ 센터 목록 조회 실패: $e');
    return [];
  }
}

/// 특정 센터 조회
Future<CenterModel?> getCenter(String centerId) async {
  try {
    DocumentSnapshot doc = await _firestore
        .collection('centers')
        .doc(centerId)
        .get();
    
    if (doc.exists) {
      return CenterModel.fromFirestore(doc);
    }
    return null;
  } catch (e) {
    print('❌ 센터 조회 실패: $e');
    return null;
  }
}

/// 센터 코드로 조회
Future<CenterModel?> getCenterByCode(String code) async {
  try {
    QuerySnapshot snapshot = await _firestore
        .collection('centers')
        .where('code', isEqualTo: code)
        .limit(1)
        .get();
    
    if (snapshot.docs.isNotEmpty) {
      return CenterModel.fromFirestore(snapshot.docs.first);
    }
    return null;
  } catch (e) {
    print('❌ 센터 코드 조회 실패: $e');
    return null;
  }
}

/// 센터 생성
Future<String?> createCenter(CenterModel center) async {
  try {
    // 코드 중복 체크
    final existing = await getCenterByCode(center.code);
    if (existing != null) {
      ToastHelper.showError('이미 사용 중인 센터 코드입니다.');
      return null;
    }
    
    final docRef = await _firestore.collection('centers').add(center.toMap());
    
    ToastHelper.showSuccess('센터가 등록되었습니다.');
    return docRef.id;
  } catch (e) {
    print('❌ 센터 생성 실패: $e');
    ToastHelper.showError('센터 등록에 실패했습니다.');
    return null;
  }
}

/// 센터 수정
Future<bool> updateCenter(String centerId, CenterModel center) async {
  try {
    await _firestore.collection('centers').doc(centerId).update(
      center.copyWith(updatedAt: DateTime.now()).toMap(),
    );
    
    ToastHelper.showSuccess('센터 정보가 수정되었습니다.');
    return true;
  } catch (e) {
    print('❌ 센터 수정 실패: $e');
    ToastHelper.showError('센터 수정에 실패했습니다.');
    return false;
  }
}

/// 센터 삭제 (소프트 삭제 - isActive를 false로)
Future<bool> deleteCenter(String centerId) async {
  try {
    await _firestore.collection('centers').doc(centerId).update({
      'isActive': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    
    ToastHelper.showSuccess('센터가 비활성화되었습니다.');
    return true;
  } catch (e) {
    print('❌ 센터 삭제 실패: $e');
    ToastHelper.showError('센터 삭제에 실패했습니다.');
    return false;
  }
}

/// 센터 완전 삭제 (하드 삭제)
Future<bool> hardDeleteCenter(String centerId) async {
  try {
    // 해당 센터의 TO가 있는지 확인
    QuerySnapshot toSnapshot = await _firestore
        .collection('tos')
        .where('centerRef', isEqualTo: _firestore.collection('centers').doc(centerId))
        .limit(1)
        .get();
    
    if (toSnapshot.docs.isNotEmpty) {
      ToastHelper.showError('이 센터에 등록된 TO가 있어 삭제할 수 없습니다.');
      return false;
    }
    
    await _firestore.collection('centers').doc(centerId).delete();
    
    ToastHelper.showSuccess('센터가 완전히 삭제되었습니다.');
    return true;
  } catch (e) {
    print('❌ 센터 완전 삭제 실패: $e');
    ToastHelper.showError('센터 삭제에 실패했습니다.');
    return false;
  }
}

// ==================== 업무 유형 관리 (파트 관리) ✨ NEW! ====================

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

/// 업무 유형 코드로 조회
Future<WorkTypeModel?> getWorkTypeByCode(String code) async {
  try {
    QuerySnapshot snapshot = await _firestore
        .collection('work_types')
        .where('code', isEqualTo: code)
        .limit(1)
        .get();
    
    if (snapshot.docs.isNotEmpty) {
      return WorkTypeModel.fromFirestore(snapshot.docs.first);
    }
    return null;
  } catch (e) {
    print('❌ 업무 유형 코드 조회 실패: $e');
    return null;
  }
}

/// 업무 유형 생성
Future<String?> createWorkType(WorkTypeModel workType) async {
  try {
    // 코드 중복 체크
    final existing = await getWorkTypeByCode(workType.code);
    if (existing != null) {
      ToastHelper.showError('이미 사용 중인 업무 코드입니다.');
      return null;
    }
    
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

/// 업무 유형 완전 삭제 (하드 삭제)
Future<bool> hardDeleteWorkType(String workTypeId) async {
  try {
    // 해당 업무 유형의 TO가 있는지 확인
    QuerySnapshot toSnapshot = await _firestore
        .collection('tos')
        .where('workTypeRef', isEqualTo: _firestore.collection('work_types').doc(workTypeId))
        .limit(1)
        .get();
    
    if (toSnapshot.docs.isNotEmpty) {
      ToastHelper.showError('이 업무 유형에 등록된 TO가 있어 삭제할 수 없습니다.');
      return false;
    }
    
    await _firestore.collection('work_types').doc(workTypeId).delete();
    
    ToastHelper.showSuccess('업무 유형이 완전히 삭제되었습니다.');
    return true;
  } catch (e) {
    print('❌ 업무 유형 완전 삭제 실패: $e');
    ToastHelper.showError('업무 삭제에 실패했습니다.');
    return false;
  }
}

  /// 센터 ID로 센터 정보 조회
  Future<CenterModel?> getCenterById(String centerId) async {
    try {
      final doc = await _firestore.collection('centers').doc(centerId).get();
      if (doc.exists) {
        return CenterModel.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      print('센터 조회 실패: $e');
      rethrow;
    }
  }

  /// 활성화된 센터만 조회
  Future<List<CenterModel>> getActiveCenters() async {
    try {
      final snapshot = await _firestore
          .collection('centers')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => CenterModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('활성 센터 목록 조회 실패: $e');
      rethrow;
    }
  }

  // ✅ 🆕 firestore_service.dart에 추가할 메서드
// 기존 FirestoreService 클래스에 아래 메서드를 추가하세요

/// ✅ 🆕 특정 사용자가 생성한 사업장 목록 가져오기
Future<List<CenterModel>> getCentersByOwnerId(String ownerId) async {
  try {
    final querySnapshot = await _firestore
        .collection('centers')
        .where('ownerId', isEqualTo: ownerId)
        .orderBy('createdAt', descending: true)
        .get();

    return querySnapshot.docs
        .map((doc) => CenterModel.fromFirestore(doc))
        .toList();
  } catch (e) {
    print('Error getting centers by ownerId: $e');
    return [];
  }
}

/// ✅ 🆕 특정 사용자가 생성한 사업장 스트림 (실시간)
Stream<List<CenterModel>> getCentersByOwnerIdStream(String ownerId) {
  return _firestore
      .collection('centers')
      .where('ownerId', isEqualTo: ownerId)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snapshot) => snapshot.docs
          .map((doc) => CenterModel.fromFirestore(doc))
          .toList());
}

Future<String?> createBusiness(BusinessModel business) async {
  try {
    DocumentReference docRef = await _firestore.collection('businesses').add(business.toMap());
    return docRef.id;
  } catch (e) {
    print('사업장 생성 실패: $e');
    return null;
  }
}


}