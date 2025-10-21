import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/to_model.dart';
import '../models/application_model.dart';
import '../utils/toast_helper.dart';

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

  Future<String> createTO(TOModel to) async {
    final docRef = await _firestore.collection('tos').add(to.toMap());
    return docRef.id;
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
}