import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../models/user_model.dart';
import '../models/to_model.dart';
import '../models/application_model.dart';
import '../models/business_model.dart';
import '../models/work_type_model.dart';
import '../models/work_detail_model.dart';
import '../utils/toast_helper.dart';
import '../models/business_work_type_model.dart';
import '../models/application_model.dart';
import '../models/work_detail_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // ✅ 캐시 추가
  final Map<String, List<ApplicationModel>> _applicationCache = {};
  final Map<String, List<WorkDetailModel>> _workDetailCache = {};
  final Map<String, Map<String, String>> _timeRangeCache = {};
  
  // 캐시 유효 시간 (5분)
  final Duration _cacheValidDuration = const Duration(minutes: 5);
  final Map<String, DateTime> _cacheTimestamps = {};

  // ═══════════════════════════════════════════════════════════
  // 사용자 관리 (User Management)
  // ═══════════════════════════════════════════════════════════
  
  /// 사용자 정보 저장
  Future<void> saveUser(UserModel user) async {
    await _firestore.collection('users').doc(user.uid).set(user.toMap());
  }

  /// 사용자 정보 조회
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

  /// 마지막 로그인 시간 업데이트
  Future<void> updateLastLogin(String uid) async {
    await _firestore.collection('users').doc(uid).update({
      'lastLoginAt': FieldValue.serverTimestamp(),
    });
  }

  // ═══════════════════════════════════════════════════════════
  // TO 관리 - 기본 CRUD (TO Basic Operations)
  // ═══════════════════════════════════════════════════════════

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

  /// TO 수정
  Future<void> updateTO(String toId, Map<String, dynamic> updates) async {
    try {
      await _firestore.collection('tos').doc(toId).update(updates);
      clearCache(toId: toId);  // ✅ 캐시 초기화
      print('✅ [FirestoreService] TO 수정 완료');
    } catch (e) {
      print('❌ [FirestoreService] TO 수정 실패: $e');
      rethrow;
    }
  }

  /// TO 삭제 전 확인 (지원자 수 체크)
  Future<Map<String, dynamic>> checkTOBeforeDelete(String toId) async {
    try {
      final applications = await getApplicationsByTOId(toId);
      final confirmedCount = applications.where((app) => app.status == 'CONFIRMED').length;
      final totalCount = applications.length;
      
      return {
        'hasApplicants': totalCount > 0,
        'confirmedCount': confirmedCount,
        'totalCount': totalCount,
      };
    } catch (e) {
      print('❌ TO 삭제 전 체크 실패: $e');
      return {'hasApplicants': false, 'confirmedCount': 0, 'totalCount': 0};
    }
  }

  /// TO 삭제 (단일 또는 그룹 TO 하나)
  Future<bool> deleteTO(String toId) async {
    try {
      final toDoc = await getTO(toId);
      if (toDoc == null) {
        ToastHelper.showError('TO를 찾을 수 없습니다.');
        return false;
      }
      
      // 1. WorkDetails 하위 컬렉션 삭제
      final workDetailsSnapshot = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();
      
      for (var doc in workDetailsSnapshot.docs) {
        await doc.reference.delete();
      }
      
      // 2. Applications 삭제
      final applicationsSnapshot = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .get();
      
      for (var doc in applicationsSnapshot.docs) {
        await doc.reference.delete();
      }
      
      // 3. 그룹 TO인 경우 처리
      if (toDoc.groupId != null) {
        final groupTOs = await getTOsByGroup(toDoc.groupId!);
        
        // 대표 TO 삭제인 경우
        if (toDoc.isGroupMaster && groupTOs.length > 1) {
          // 다음 TO를 대표로 지정
          final nextTO = groupTOs.firstWhere((to) => to.id != toId);
          await _firestore.collection('tos').doc(nextTO.id).update({
            'isGroupMaster': true,
          });
          
          // 날짜 범위 재계산
          await _updateGroupDateRange(toDoc.groupId!);
        }
      }
      
      // 4. TO 문서 삭제
      await _firestore.collection('tos').doc(toId).delete();

      clearCache(toId: toId);  // ✅ 캐시 초기화

      print('✅ TO 삭제 완료: $toId');
      ToastHelper.showSuccess('TO가 삭제되었습니다.');
      return true;
    } catch (e) {
      print('❌ TO 삭제 실패: $e');
      ToastHelper.showError('TO 삭제에 실패했습니다.');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // TO 조회 - 다양한 조건별 (TO Query Operations)
  // ═══════════════════════════════════════════════════════════

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

  /// 대표 TO만 조회 (그룹 TO는 대표만, 일반 TO는 전체)
  Future<List<TOModel>> getMasterTOsOnly() async {
    try {
      print('🔍 [FirestoreService] 대표 TO 조회 시작...');

      final snapshot = await _firestore
          .collection('tos')
          .orderBy('date', descending: false)
          .get();

      final allTOs = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      // 필터링: isGroupMaster == true OR groupId == null
      final filteredTOs = allTOs.where((to) {
        return to.isGroupMaster || to.groupId == null;
      }).toList();

      // 오늘 이전 TO 제외
      final today = DateTime.now();
      final result = filteredTOs.where((to) {
        return to.date.isAfter(today.subtract(const Duration(days: 1)));
      }).toList();

      print('✅ [FirestoreService] 대표 TO 조회 완료: ${result.length}개');
      return result;
    } catch (e) {
      print('❌ [FirestoreService] 대표 TO 조회 실패: $e');
      return [];
    }
  }

  /// 대표 TO만 조회 (별칭)
  Future<List<TOModel>> getGroupMasterTOs() async {
    return getMasterTOsOnly();
  }

  /// 사용자의 최근 TO 목록 조회 (그룹 연결용)
  Future<List<TOModel>> getRecentTOsByUser(String uid, {int days = 30}) async {
    try {
      final cutoffDate = DateTime.now().subtract(Duration(days: days));
      
      print('🔍 [FirestoreService] 최근 TO 조회 시작...');
      print('   사용자 UID: $uid');
      print('   조회 기간: 최근 $days일');

      final snapshot = await _firestore
          .collection('tos')
          .where('creatorUID', isEqualTo: uid)
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoffDate))
          .orderBy('date', descending: false)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      final toList = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      print('✅ [FirestoreService] 최근 TO 조회 완료: ${toList.length}개');
      return toList;
    } catch (e) {
      print('❌ [FirestoreService] 최근 TO 조회 실패: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // TO 생성 (TO Creation)
  // ═══════════════════════════════════════════════════════════

  /// TO 생성 (WorkDetails 포함) - 업무별 시간 정보 포함
  Future<String?> createTOWithDetails({
    required String businessId,
    required String businessName,
    required String title,
    required DateTime date,
    required DateTime applicationDeadline,
    required List<Map<String, dynamic>> workDetailsData,
    String? description,
    required String creatorUID,
    // ✅ NEW: 지원 마감 규칙
    String deadlineType = 'HOURS_BEFORE',
    int? hoursBeforeStart = 2,
    String? groupId,
    String? groupName,

    // ✅ NEW: 그룹 TO용 파라미터
    DateTime? startDate,
    DateTime? endDate,
    bool isGroupMaster = false,
  }) async {
    try {
      print('🔧 [FirestoreService] TO 생성 시작...');

      // 1. 전체 필요 인원 계산
      int totalRequired = 0;
      for (var detail in workDetailsData) {
        totalRequired += (detail['requiredCount'] as int);
      }

      // 2. TO 기본 정보 생성
      final toData = {
        'businessId': businessId,
        'businessName': businessName,
        'jobType': 'short',
        'groupId': groupId,
        'groupName': groupName,
        'startDate': startDate != null ? Timestamp.fromDate(startDate) : null,
        'endDate': endDate != null ? Timestamp.fromDate(endDate) : null,
        'isGroupMaster': isGroupMaster,
        'title': title,
        'date': Timestamp.fromDate(date),
        'applicationDeadline': Timestamp.fromDate(applicationDeadline),
        'deadlineType': deadlineType,
        'hoursBeforeStart': hoursBeforeStart,
        'totalRequired': totalRequired,
        'totalConfirmed': 0,
        'totalPending': 0,        // ✅ 추가
        'totalApplications': 0,   // ✅ 추가
        'description': description ?? '',
        'creatorUID': creatorUID,
        'createdAt': FieldValue.serverTimestamp(),
      };

      // 3. TO 문서 생성
      final toDoc = await _firestore.collection('tos').add(toData);
      print('✅ TO 문서 생성 완료: ${toDoc.id}');

      // 4. WorkDetails 하위 컬렉션에 업무 추가
      final batch = _firestore.batch();
      
      for (int i = 0; i < workDetailsData.length; i++) {
        final data = workDetailsData[i];
        final docRef = toDoc.collection('workDetails').doc();
        
        batch.set(docRef, {
          'workType': data['workType'],
          'workTypeIcon': data['workTypeIcon'],  // ✅ 추가
          'workTypeColor': data['workTypeColor'],  // ✅ 추가
          'wage': data['wage'],
          'requiredCount': data['requiredCount'],
          'currentCount': 0,
          'pendingCount': 0,      
          'startTime': data['startTime'],
          'endTime': data['endTime'],
          'order': i,
          'createdAt': FieldValue.serverTimestamp(),
        });
        
        print('  - 업무 추가: ${data['workType']} (${data['startTime']} ~ ${data['endTime']})');
      }
      
      await batch.commit();
      print('✅ WorkDetails 생성 완료: ${workDetailsData.length}개');

      //ToastHelper.showSuccess('TO가 생성되었습니다!');
      return toDoc.id;
    } catch (e) {
      print('❌ [FirestoreService] TO 생성 실패: $e');
      ToastHelper.showError('TO 생성에 실패했습니다.');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // TO 그룹 관리 (TO Group Management)
  // ═══════════════════════════════════════════════════════════

  /// 그룹 ID 생성
  String generateGroupId() {
    return 'group_${DateTime.now().millisecondsSinceEpoch}';
  }

  /// 그룹별 TO 조회
  Future<List<TOModel>> getTOsByGroup(String groupId) async {
    try {
      print('🔍 [FirestoreService] 그룹 TO 조회 시작...');
      print('   그룹 ID: $groupId');

      final snapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .orderBy('date', descending: false)
          .get();

      final toList = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      print('✅ [FirestoreService] 그룹 TO 조회 완료: ${toList.length}개');
      return toList;
    } catch (e) {
      print('❌ [FirestoreService] 그룹 TO 조회 실패: $e');
      return [];
    }
  }

  /// 그룹 TO 일괄 생성 (날짜 범위)
  Future<bool> createTOGroup({
    required String businessId,
    required String businessName,
    required String groupName,
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    required List<Map<String, dynamic>> workDetails,
    required DateTime applicationDeadline,
    String? description,
    required String creatorUID,
  }) async {
    try {
      print('🔨 [FirestoreService] 그룹 TO 생성 시작...');
      print('   기간: ${startDate.toString().split(' ')[0]} ~ ${endDate.toString().split(' ')[0]}');
      
      final groupId = generateGroupId();
      print('   생성된 그룹 ID: $groupId');
      
      // 시작일~종료일 사이의 모든 날짜 계산
      List<DateTime> dates = [];
      DateTime currentDate = startDate;
      
      while (currentDate.isBefore(endDate.add(Duration(days: 1)))) {
        dates.add(DateTime(currentDate.year, currentDate.month, currentDate.day));
        currentDate = currentDate.add(Duration(days: 1));
      }
      
      print('   생성할 TO 개수: ${dates.length}개');
      
      // 총 필요 인원 계산
      int totalRequired = 0;
      for (var work in workDetails) {
        totalRequired += (work['requiredCount'] as int?) ?? 0;
      }
      
      // 각 날짜별 TO 생성
      for (int i = 0; i < dates.length; i++) {
        final toData = {
          'businessId': businessId,
          'businessName': businessName,
          'groupId': groupId,
          'groupName': groupName,
          'startDate': Timestamp.fromDate(startDate),
          'endDate': Timestamp.fromDate(endDate),
          'isGroupMaster': i == 0,
          'title': title,
          'date': Timestamp.fromDate(dates[i]),
          'startTime': workDetails.isNotEmpty ? workDetails[0]['startTime'] ?? '' : '',
          'endTime': workDetails.isNotEmpty ? workDetails[0]['endTime'] ?? '' : '',
          'applicationDeadline': Timestamp.fromDate(applicationDeadline),
          'totalRequired': totalRequired,
          'totalConfirmed': 0,
          'description': description,
          'creatorUID': creatorUID,
          'createdAt': FieldValue.serverTimestamp(),
        };
        
        // TO 문서 생성
        final toDoc = await _firestore.collection('tos').add(toData);
        print('   ✅ ${dates[i].toString().split(' ')[0]} TO 생성 완료 (ID: ${toDoc.id})');
        
        // WorkDetails 하위 컬렉션 생성
        for (int j = 0; j < workDetails.length; j++) {
          await _firestore
              .collection('tos')
              .doc(toDoc.id)
              .collection('workDetails')
              .add({
            'workType': workDetails[j]['workType'],
            'workTypeIcon': workDetails[j]['workTypeIcon'],
            'workTypeColor': workDetails[j]['workTypeColor'],
            'wage': workDetails[j]['wage'],
            'requiredCount': workDetails[j]['requiredCount'],
            'currentCount': 0,
            'pendingCount': 0, 
            'startTime': workDetails[j]['startTime'],
            'endTime': workDetails[j]['endTime'],
            'order': j,
          });
        }
      }
      
      print('✅ [FirestoreService] 그룹 TO 생성 완료: ${dates.length}개');
      //ToastHelper.showSuccess('${dates.length}개의 TO가 생성되었습니다!');
      return true;
      
    } catch (e) {
      print('❌ [FirestoreService] 그룹 TO 생성 실패: $e');
      ToastHelper.showError('TO 생성 중 오류가 발생했습니다.');
      return false;
    }
  }
  /// TO를 다른 그룹에 재연결
  Future<bool> reconnectToGroup({
    required String toId,
    required String targetGroupId,
  }) async {
    try {
      // 대상 그룹의 정보 가져오기
      final targetGroupTOs = await getTOsByGroup(targetGroupId);
      if (targetGroupTOs.isEmpty) {
        ToastHelper.showError('대상 그룹을 찾을 수 없습니다.');
        return false;
      }
      
      final targetMasterTO = targetGroupTOs.firstWhere((to) => to.isGroupMaster);
      
      // TO를 새 그룹에 연결
      await _firestore.collection('tos').doc(toId).update({
        'groupId': targetGroupId,
        'groupName': targetMasterTO.groupName,
        'isGroupMaster': false,
        'startDate': targetMasterTO.startDate,
        'endDate': targetMasterTO.endDate,
      });
      
      // 대상 그룹의 날짜 범위 재계산
      await _updateGroupDateRange(targetGroupId);
      
      print('✅ TO 그룹 재연결 완료: $toId → $targetGroupId');
      ToastHelper.showSuccess('그룹에 연결되었습니다.');
      return true;
    } catch (e) {
      print('❌ TO 그룹 재연결 실패: $e');
      ToastHelper.showError('그룹 연결에 실패했습니다.');
      return false;
    }
  }
  /// 단일 TO로 새 그룹 생성
  Future<bool> createNewGroupFromTO({
    required String toId,
    required String groupName,
  }) async {
    try {
      final to = await getTO(toId);
      if (to == null) {
        ToastHelper.showError('TO를 찾을 수 없습니다.');
        return false;
      }
      
      // 새 그룹 ID 생성
      final groupId = 'group_${DateTime.now().millisecondsSinceEpoch}';
      
      // TO를 그룹으로 변경
      await _firestore.collection('tos').doc(toId).update({
        'groupId': groupId,
        'groupName': groupName,
        'isGroupMaster': true,  // 대표 TO로 지정
        'startDate': Timestamp.fromDate(to.date),
        'endDate': Timestamp.fromDate(to.date),
      });
      
      print('✅ 새 그룹 생성 완료');
      print('   그룹 ID: $groupId');
      print('   그룹명: $groupName');
      print('   대표 TO: $toId');
      
      ToastHelper.showSuccess('새 그룹이 생성되었습니다.');
      return true;
    } catch (e) {
      print('❌ 새 그룹 생성 실패: $e');
      ToastHelper.showError('그룹 생성에 실패했습니다.');
      return false;
    }
  }

  /// 기존 그룹에 TO 추가
  Future<bool> createTOGroupWithExistingGroup({
    required String businessId,
    required String businessName,
    required String groupId,
    required String groupName,
    required String title,
    required DateTime startDate,
    required DateTime endDate,
    required List<Map<String, dynamic>> workDetails,
    required DateTime applicationDeadline,
    String? description,
    required String creatorUID,
  }) async {
    try {
      print('🔧 [FirestoreService] 기존 그룹에 TO 추가 시작...');
      print('   그룹 ID: $groupId');
      print('   그룹명: $groupName');
      print('   기간: ${startDate.month}/${startDate.day} ~ ${endDate.month}/${endDate.day}');

      final batch = _firestore.batch();
      
      // 날짜 범위 내 모든 날짜 생성
      List<DateTime> dates = [];
      DateTime currentDate = startDate;
      
      while (currentDate.isBefore(endDate) || currentDate.isAtSameMomentAs(endDate)) {
        dates.add(currentDate);
        currentDate = currentDate.add(const Duration(days: 1));
      }

      print('   생성할 TO 개수: ${dates.length}일');

      // 전체 필요 인원 계산
      int totalRequired = 0;
      for (var detail in workDetails) {
        totalRequired += (detail['requiredCount'] as int);
      }

      // 각 날짜별 TO 생성
      for (int i = 0; i < dates.length; i++) {
        final date = dates[i];
        
        // TO 기본 정보
        final toData = {
          'businessId': businessId,
          'businessName': businessName,
          'groupId': groupId,
          'groupName': groupName,
          'startDate': Timestamp.fromDate(startDate),
          'endDate': Timestamp.fromDate(endDate),
          'isGroupMaster': false,
          'title': title,
          'date': Timestamp.fromDate(date),
          'applicationDeadline': Timestamp.fromDate(applicationDeadline),
          'totalRequired': totalRequired,
          'totalConfirmed': 0,
          'description': description ?? '',
          'creatorUID': creatorUID,
          'createdAt': FieldValue.serverTimestamp(),
        };

        final toDoc = _firestore.collection('tos').doc();
        batch.set(toDoc, toData);

        // WorkDetails 추가
        for (int j = 0; j < workDetails.length; j++) {
          final detail = workDetails[j];
          final workDetailDoc = toDoc.collection('workDetails').doc();
          
          batch.set(workDetailDoc, {
            'workType': detail['workType'],
            'workTypeIcon': detail['workTypeIcon'],
            'workTypeColor': detail['workTypeColor'],
            'wage': detail['wage'],
            'requiredCount': detail['requiredCount'],
            'currentCount': 0,
            'pendingCount': 0, 
            'startTime': detail['startTime'],
            'endTime': detail['endTime'],
            'order': j,
            'createdAt': FieldValue.serverTimestamp(),
          });
        }

        print('  ✅ ${date.month}/${date.day} TO 준비 완료');
      }
      // 대표 TO의 날짜 범위 업데이트
      final masterTOSnapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .where('isGroupMaster', isEqualTo: true)
          .limit(1)
          .get();

      if (masterTOSnapshot.docs.isNotEmpty) {
        final masterTODoc = masterTOSnapshot.docs.first;
        final currentStartDate = (masterTODoc.data()['startDate'] as Timestamp).toDate();
        final currentEndDate = (masterTODoc.data()['endDate'] as Timestamp).toDate();
        
        // 새로운 날짜 범위 계산
        final newStartDate = startDate.isBefore(currentStartDate) ? startDate : currentStartDate;
        final newEndDate = endDate.isAfter(currentEndDate) ? endDate : currentEndDate;
        
        // 대표 TO 업데이트
        batch.update(masterTODoc.reference, {
          'startDate': Timestamp.fromDate(newStartDate),
          'endDate': Timestamp.fromDate(newEndDate),
        });
        
        print('✅ 대표 TO 날짜 범위 업데이트: ${newStartDate.month}/${newStartDate.day} ~ ${newEndDate.month}/${newEndDate.day}');
      }

      await batch.commit();
      
      print('✅ [FirestoreService] 기존 그룹에 TO 추가 완료!');
      print('   추가된 TO: ${dates.length}개');
      print('   그룹 ID: $groupId');
      
      ToastHelper.showSuccess('${dates.length}개 TO가 그룹에 추가되었습니다!');
      return true;
      
    } catch (e) {
      print('❌ [FirestoreService] 기존 그룹 TO 추가 실패: $e');
      ToastHelper.showError('TO 추가 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// TO의 그룹 정보 업데이트
  Future<bool> updateTOGroup({
    required String toId,
    required String groupId,
    required String groupName,
  }) async {
    try {
      await _firestore.collection('tos').doc(toId).update({
        'groupId': groupId,
        'groupName': groupName,
      });
      
      print('✅ [FirestoreService] TO 그룹 정보 업데이트 완료');
      print('   TO ID: $toId');
      print('   Group ID: $groupId');
      print('   Group Name: $groupName');
      
      return true;
    } catch (e) {
      print('❌ [FirestoreService] TO 그룹 정보 업데이트 실패: $e');
      return false;
    }
  }

  /// 그룹명 일괄 수정
  Future<bool> updateGroupName(String groupId, String newGroupName) async {
    try {
      print('🔧 [FirestoreService] 그룹명 수정 시작...');
      print('   그룹 ID: $groupId');
      print('   새 그룹명: $newGroupName');

      // 같은 groupId를 가진 모든 TO 조회
      final snapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();

      if (snapshot.docs.isEmpty) {
        ToastHelper.showError('그룹을 찾을 수 없습니다.');
        return false;
      }

      // Batch 업데이트
      final batch = _firestore.batch();
      
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'groupName': newGroupName});
      }

      await batch.commit();

      print('✅ [FirestoreService] 그룹명 수정 완료: ${snapshot.docs.length}개 TO 업데이트');
      ToastHelper.showSuccess('그룹명이 수정되었습니다.');
      return true;
    } catch (e) {
      print('❌ [FirestoreService] 그룹명 수정 실패: $e');
      ToastHelper.showError('그룹명 수정에 실패했습니다.');
      return false;
    }
  }

  /// 그룹 전체 삭제
  Future<bool> deleteGroupTOs(String groupId) async {
    try {
      final groupTOs = await getTOsByGroup(groupId);
      
      if (groupTOs.isEmpty) {
        ToastHelper.showError('그룹을 찾을 수 없습니다.');
        return false;
      }
      
      // 모든 TO 삭제
      for (var to in groupTOs) {
        await deleteTO(to.id);
      }
      
      print('✅ 그룹 전체 삭제 완료: $groupId');
      ToastHelper.showSuccess('그룹이 삭제되었습니다.');
      return true;
    } catch (e) {
      print('❌ 그룹 삭제 실패: $e');
      ToastHelper.showError('그룹 삭제에 실패했습니다.');
      return false;
    }
  }

  /// 특정 날짜 TO만 삭제 (그룹 내 단일 삭제)
  Future<bool> deleteSingleTOFromGroup(String toId, String? groupId) async {
    try {
      print('🗑️ [FirestoreService] 단일 TO 삭제 시작...');
      print('   TO ID: $toId');

      // 1. 삭제할 TO 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        ToastHelper.showError('TO를 찾을 수 없습니다.');
        return false;
      }

      final to = TOModel.fromMap(toDoc.data()!, toDoc.id);
      
      // 2. WorkDetails 삭제
      final workDetailsSnapshot = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();
      
      final batch = _firestore.batch();
      for (var doc in workDetailsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      
      // 3. 지원서 삭제
      final applicationsSnapshot = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .get();
      
      for (var doc in applicationsSnapshot.docs) {
        batch.delete(doc.reference);
      }
      
      // 4. TO 문서 삭제
      batch.delete(_firestore.collection('tos').doc(toId));
      
      await batch.commit();
      
      // 5. 대표 TO였다면 다음 TO를 대표로 변경
      if (to.isGroupMaster && groupId != null) {
        final groupTOs = await getTOsByGroup(groupId);
        if (groupTOs.isNotEmpty) {
          // 남은 TO 중 첫 번째를 대표로
          await _firestore.collection('tos').doc(groupTOs[0].id).update({
            'isGroupMaster': true,
          });
          print('   ✅ 새 대표 TO 지정: ${groupTOs[0].id}');
        }
      }
      
      print('✅ [FirestoreService] TO 삭제 완료');
      ToastHelper.showSuccess('TO가 삭제되었습니다.');
      return true;
      
    } catch (e) {
      print('❌ [FirestoreService] TO 삭제 실패: $e');
      ToastHelper.showError('삭제 중 오류가 발생했습니다.');
      return false;
    }
  }

  /// TO를 그룹에서 해제하여 독립 TO로 변경
  Future<bool> removeFromGroup(String toId) async {
    try {
      final to = await getTO(toId);
      if (to == null || to.groupId == null) {
        ToastHelper.showError('그룹 TO가 아닙니다.');
        return false;
      }
      
      final groupId = to.groupId!;
      
      // 1. TO를 독립 TO로 변경
      await _firestore.collection('tos').doc(toId).update({
        'groupId': FieldValue.delete(),
        'groupName': FieldValue.delete(),
        'isGroupMaster': false,
        'startDate': FieldValue.delete(),
        'endDate': FieldValue.delete(),
      });
      
      // 2. 남은 그룹 TO 확인
      final remainingTOs = await getTOsByGroup(groupId);
      
      if (remainingTOs.length == 1) {
        // 마지막 TO도 독립 TO로 변경
        final lastTO = remainingTOs.first;
        await _firestore.collection('tos').doc(lastTO.id).update({
          'groupId': FieldValue.delete(),
          'groupName': FieldValue.delete(),
          'isGroupMaster': false,
          'startDate': FieldValue.delete(),
          'endDate': FieldValue.delete(),
        });
        print('✅ 마지막 TO도 독립 TO로 변경');
      } else if (remainingTOs.isNotEmpty) {
        // 해제된 TO가 대표였다면 다음 TO를 대표로 지정
        if (to.isGroupMaster) {
          final newMasterTO = remainingTOs.first;
          await _firestore.collection('tos').doc(newMasterTO.id).update({
            'isGroupMaster': true,
          });
          print('✅ 새 대표 TO 지정: ${newMasterTO.id}');
        }
        
        // 그룹 날짜 범위 재계산
        await _updateGroupDateRange(groupId);
      }
      
      print('✅ TO 그룹 해제 완료: $toId');
      ToastHelper.showSuccess('그룹에서 해제되었습니다.');
      return true;
    } catch (e) {
      print('❌ TO 그룹 해제 실패: $e');
      ToastHelper.showError('그룹 해제에 실패했습니다.');
      return false;
    }
  }
  /// 시간 문자열 비교 (HH:mm 형식)
  int _compareTime(String time1, String time2) {
    final parts1 = time1.split(':');
    final parts2 = time2.split(':');
    
    final hour1 = int.parse(parts1[0]);
    final minute1 = int.parse(parts1[1]);
    final hour2 = int.parse(parts2[0]);
    final minute2 = int.parse(parts2[1]);
    
    if (hour1 != hour2) return hour1 - hour2;
    return minute1 - minute2;
  }

  /// 그룹 날짜 범위 재계산 (내부 헬퍼 함수)
  Future<void> _updateGroupDateRange(String groupId) async {
    try {
      final groupTOs = await getTOsByGroup(groupId);
      if (groupTOs.isEmpty) return;
      
      // 최소/최대 날짜 계산
      DateTime minDate = groupTOs.first.date;
      DateTime maxDate = groupTOs.first.date;
      
      for (var to in groupTOs) {
        if (to.date.isBefore(minDate)) minDate = to.date;
        if (to.date.isAfter(maxDate)) maxDate = to.date;
      }
      
      // 대표 TO 업데이트
      final masterTO = groupTOs.firstWhere((to) => to.isGroupMaster);
      await _firestore.collection('tos').doc(masterTO.id).update({
        'startDate': Timestamp.fromDate(minDate),
        'endDate': Timestamp.fromDate(maxDate),
      });
      
      print('✅ 그룹 날짜 범위 업데이트: ${minDate} ~ ${maxDate}');
    } catch (e) {
      print('❌ 그룹 날짜 범위 업데이트 실패: $e');
    }
  }

  /// 그룹 TO의 전체 시간 범위 계산 (최적화 - 병렬 처리)
  Future<Map<String, String>> calculateGroupTimeRange(String groupId, {bool forceRefresh = false}) async {
    try {
      print('🕐 [FirestoreService] 그룹 시간 범위 계산 시작...');
      print('   그룹 ID: $groupId');

      // 1. 그룹의 모든 TO 조회
      final snapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();

      if (snapshot.docs.isEmpty) {
        return {'minStart': '~', 'maxEnd': '~'};
      }

      final toIds = snapshot.docs.map((doc) => doc.id).toList();

      // 2. ✅ 병렬로 모든 WorkDetails 조회
      final workDetailsFutures = toIds.map((toId) => getWorkDetails(toId, forceRefresh: forceRefresh)).toList();
      final allWorkDetailsLists = await Future.wait(workDetailsFutures);

      String? minStart;
      String? maxEnd;

      // 3. 시간 범위 계산
      for (var workDetailsList in allWorkDetailsLists) {
        for (var work in workDetailsList) {
          // 최소 시작 시간
          if (minStart == null || work.startTime.compareTo(minStart) < 0) {
            minStart = work.startTime;
          }
          
          // 최대 종료 시간
          if (maxEnd == null || work.endTime.compareTo(maxEnd) > 0) {
            maxEnd = work.endTime;
          }
        }
      }

      print('✅ [FirestoreService] 시간 범위 계산 완료');
      print('   최소 시작: $minStart, 최대 종료: $maxEnd');

      return {
        'minStart': minStart ?? '~',
        'maxEnd': maxEnd ?? '~',
      };
    } catch (e) {
      print('❌ [FirestoreService] 시간 범위 계산 실패: $e');
      return {'minStart': '~', 'maxEnd': '~'};
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 지원서 관리 (Application Management)
  // ═══════════════════════════════════════════════════════════

  /// TO별 지원자 목록 조회
  Future<List<ApplicationModel>> getApplicationsByTOId(String toId) async {
    try {
      // 1. TO 정보 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return [];
      }

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      // 2. businessId, toTitle, workDate로 지원서 조회
      final snapshot = await _firestore
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

  /// 여러 TO의 지원자를 한 번에 조회 (배치)
  Future<Map<String, List<ApplicationModel>>> getApplicationsByTOIds(List<String> toIds) async {
    try {
      if (toIds.isEmpty) return {};
      
      Map<String, List<ApplicationModel>> result = {};
      
      // 각 TO별로 빈 리스트 초기화
      for (var toId in toIds) {
        result[toId] = [];
      }
      
      // ✅ 각 TO별로 조회 (toId로는 직접 조회 불가능)
      for (var toId in toIds) {
        // TO 정보 조회
        final toDoc = await _firestore.collection('tos').doc(toId).get();
        if (!toDoc.exists) continue;

        final toData = toDoc.data()!;
        final businessId = toData['businessId'];
        final toTitle = toData['title'];
        final workDate = toData['date'] as Timestamp;

        // 지원서 조회
        final snapshot = await _firestore
            .collection('applications')
            .where('businessId', isEqualTo: businessId)
            .where('toTitle', isEqualTo: toTitle)
            .where('workDate', isEqualTo: workDate)
            .get();

        // 결과에 추가
        result[toId] = snapshot.docs
            .map((doc) => ApplicationModel.fromFirestore(doc))
            .toList();
      }
      
      print('✅ 배치 지원자 조회 완료: ${toIds.length}개 TO, ${result.values.fold(0, (sum, list) => sum + list.length)}명');
      return result;
    } catch (e) {
      print('❌ 배치 지원자 조회 실패: $e');
      return {};
    }
  }

  /// 여러 TO의 WorkDetails를 한 번에 조회 (병렬)
  Future<Map<String, List<WorkDetailModel>>> getWorkDetailsBatch(
    List<String> toIds, 
    {bool forceRefresh = false}  // 🔥 추가!
  ) async {
    try {
      if (toIds.isEmpty) return {};
      
      // 병렬로 모든 WorkDetails 조회
      final futures = toIds.map((toId) async {
        final workDetails = await getWorkDetails(toId, forceRefresh: forceRefresh);
        return MapEntry(toId, workDetails);
      }).toList();
      
      final results = await Future.wait(futures);
      
      final map = Map.fromEntries(results);
      print('✅ 배치 WorkDetails 조회 완료: ${toIds.length}개 TO');
      return map;
    } catch (e) {
      print('❌ 배치 WorkDetails 조회 실패: $e');
      return {};
    }
  }
  /// 특정 TO의 특정 업무 유형에 대한 지원서 조회
  Future<List<ApplicationModel>> getApplicationsByWorkDetail(
    String toId,
    String workType,
  ) async {
    try {
      // ✅ TO 정보 먼저 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return [];
      }

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      // ✅ businessId, toTitle, workDate, workType으로 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .where('selectedWorkType', isEqualTo: workType)
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 업무별 지원서 조회 실패: $e');
      return [];
    }
  }
  /// TO의 모든 지원서 조회 (businessId, title, date 기준)
  Future<List<ApplicationModel>> getApplicationsByTO(
    String businessId,
    String title,
    DateTime date,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: title)
          .where('workDate', isEqualTo: Timestamp.fromDate(date))
          .get();

      final apps = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();

      print('✅ TO 지원서 조회: ${apps.length}개');
      return apps;
    } catch (e) {
      print('❌ TO 지원서 조회 실패: $e');
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
      // ✅ TO 정보 먼저 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return [];
      }

      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;

      print('🔍 지원자 조회: businessId=$businessId, toTitle=$toTitle');

      // ✅ businessId, toTitle, workDate로 조회
      QuerySnapshot appSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .get();

      print('✅ 조회된 지원서: ${appSnapshot.docs.length}개');

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
            'userEmail': userData['email'] ?? '',
            'userPhone': userData['phone'] ?? '',
          });
        }
      }

      print('✅ 사용자 정보 포함 지원자: ${result.length}명');
      return result;
    } catch (e) {
      print('❌ 지원자 조회 실패: $e');
      return [];
    }
  }

  /// 지원하기 (업무유형 선택)
  Future<bool> applyToTOWithWorkType({
    required String businessId,
    required String businessName,
    required String toTitle,
    required DateTime workDate,
    required String uid,
    required String selectedWorkType,
    required int wage,
    required String startTime,
    required String endTime,
  }) async {
    try {
      // 1. 중복 지원 확인
      final existingApp = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: Timestamp.fromDate(workDate))
          .where('uid', isEqualTo: uid)
          .limit(1)
          .get();

      if (existingApp.docs.isNotEmpty) {
        ToastHelper.showWarning('이미 지원한 TO입니다.');
        return false;
      }

      // 2. TO 문서 찾기
      final toSnapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('title', isEqualTo: toTitle)
          .where('date', isEqualTo: Timestamp.fromDate(workDate))
          .limit(1)
          .get();

      if (toSnapshot.docs.isEmpty) {
        ToastHelper.showError('TO를 찾을 수 없습니다.');
        return false;
      }

      final toId = toSnapshot.docs.first.id;

      // 3. WorkDetail ID 찾기
      final workDetailId = await findWorkDetailIdByType(toId, selectedWorkType);
      if (workDetailId == null) {
        ToastHelper.showError('업무유형 정보를 찾을 수 없습니다.');
        return false;
      }

      // 4. Batch로 한번에 처리
      final batch = _firestore.batch();

      // 4-1. 지원서 생성
      final appRef = _firestore.collection('applications').doc();
      batch.set(appRef, {
        'uid': uid,
        'businessId': businessId,
        'businessName': businessName,
        'toTitle': toTitle,
        'selectedWorkType': selectedWorkType,
        'wage': wage,
        'workDate': Timestamp.fromDate(workDate),
        'startTime': startTime,
        'endTime': endTime,
        'status': 'PENDING',
        'appliedAt': FieldValue.serverTimestamp(),
      });

      // 4-2. TO 통계 업데이트
      batch.update(_firestore.collection('tos').doc(toId), {
        'totalApplications': FieldValue.increment(1),
        'totalPending': FieldValue.increment(1),
      });

      // 4-3. WorkDetail pendingCount 증가
      batch.update(
        _firestore
            .collection('tos')
            .doc(toId)
            .collection('workDetails')
            .doc(workDetailId),
        {
          'pendingCount': FieldValue.increment(1),
        },
      );

      // ✅ 통계 재계산 (통합 로직 사용)
      print('📊 지원 생성 후 통계 재계산...');
      await recalculateTOStats(toId);

      print('✅ 지원 완료: businessId=$businessId, toTitle=$toTitle, WorkType=$selectedWorkType');
      ToastHelper.showSuccess('지원이 완료되었습니다!');
      return true;
    } catch (e) {
      print('❌ 지원 실패: $e');
      ToastHelper.showError('지원 중 오류가 발생했습니다.');
      return false;
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

  /// 지원자 확정 (WorkDetail count + TO 통계 업데이트 포함)
  Future<bool> confirmApplicantWithWorkDetail({
    required String applicationId,
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
      
      // 이미 확정된 경우
      if (appData['status'] == 'CONFIRMED') {
        ToastHelper.showError('이미 확정된 지원자입니다.');
        return false;
      }

      // 취소된 경우
      if (appData['status'] == 'CANCELED') {
        ToastHelper.showError('취소된 지원자는 확정할 수 없습니다.');
        return false;
      }

      // ✅ TO 식별 정보 추출
      final businessId = appData['businessId'];
      final toTitle = appData['toTitle'];
      final workDate = appData['workDate'] as Timestamp;
      final selectedWorkType = appData['selectedWorkType'];
      final uid = appData['uid'];

      // 2. TO 문서 찾기
      final toSnapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('title', isEqualTo: toTitle)
          .where('date', isEqualTo: workDate)
          .limit(1)
          .get();

      if (toSnapshot.docs.isEmpty) {
        ToastHelper.showError('TO를 찾을 수 없습니다.');
        return false;
      }

      final toId = toSnapshot.docs.first.id;

      // 3. WorkDetail ID 찾기
      final workDetailId = await findWorkDetailIdByType(toId, selectedWorkType);
      if (workDetailId == null) {
        ToastHelper.showError('업무유형 정보를 찾을 수 없습니다.');
        return false;
      }

      // 4. 정원 체크
      final workDetailDoc = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .get();
      
      if (!workDetailDoc.exists) {
        ToastHelper.showError('업무 정보를 찾을 수 없습니다.');
        return false;
      }
      
      final workDetailData = workDetailDoc.data()!;
      final currentCount = workDetailData['currentCount'] ?? 0;
      final requiredCount = workDetailData['requiredCount'] ?? 0;
      
      // 정원 초과 체크
      if (currentCount >= requiredCount) {
        ToastHelper.showError('이미 정원이 충족되었습니다. ($currentCount/$requiredCount명)');
        return false;
      }

      // 5. Batch 업데이트
      final batch = _firestore.batch();
      final now = Timestamp.now();

      // 5-1. 지원서 확정
      batch.update(_firestore.collection('applications').doc(applicationId), {
        'status': 'CONFIRMED',
        'confirmedAt': now,
        'confirmedBy': adminUID,
      });

      // 5-2. confirmed_applications 서브컬렉션에 추가
      final confirmedRef = _firestore
          .collection('tos')
          .doc(toId)
          .collection('confirmed_applications')
          .doc(applicationId);
      
      batch.set(confirmedRef, {
        'uid': uid,
        'workDetailId': workDetailId,
        'confirmedAt': now,
        'confirmedBy': adminUID,
      });

      await batch.commit();

      // ✅ 통계 재계산 (통합 함수 사용)
      print('📊 지원자 확정 후 통계 재계산...');
      await recalculateTOStats(toId);
      clearCache(toId: toId);

      print('✅ 지원자 확정 완료');
      ToastHelper.showSuccess('지원자가 확정되었습니다.');
      return true;
    } catch (e) {
      print('❌ 지원자 확정 실패: $e');
      ToastHelper.showError('확정 중 오류가 발생했습니다.');
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

      // ✅ TO 식별 정보 추출
      final businessId = appData['businessId'];
      final toTitle = appData['toTitle'];
      final workDate = appData['workDate'] as Timestamp;

      // 지원서 거절 처리
      await _firestore.collection('applications').doc(applicationId).update({
        'status': 'REJECTED',
      });

      // ✅ 통계 재계산
      print('📊 지원자 거절 후 통계 재계산...');
      final toSnapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('title', isEqualTo: toTitle)
          .where('date', isEqualTo: workDate)
          .limit(1)
          .get();

      if (toSnapshot.docs.isNotEmpty) {
        await recalculateTOStats(toSnapshot.docs.first.id);
        clearCache(toId: toSnapshot.docs.first.id);
      }

      print('✅ 지원자 거절 완료');
      ToastHelper.showSuccess('지원자가 거절되었습니다.');
      return true;
    } catch (e) {
      print('❌ 지원자 거절 실패: $e');
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

      final appData = appDoc.data() as Map<String, dynamic>;

      if (appData['uid'] != uid) {
        ToastHelper.showError('본인의 지원서만 취소할 수 있습니다.');
        return false;
      }

      if (appData['status'] == 'CONFIRMED') {
        ToastHelper.showError('확정된 TO는 취소할 수 없습니다.\n관리자에게 문의해주세요.');
        return false;
      }

      // ✅ TO 식별 정보 추출
      final businessId = appData['businessId'];
      final toTitle = appData['toTitle'];
      final workDate = appData['workDate'] as Timestamp;

      // 지원서 취소 처리
      await _firestore.collection('applications').doc(applicationId).update({
        'status': 'CANCELED',
      });

      // ✅ 통계 재계산
      print('📊 지원 취소 후 통계 재계산...');
      final toSnapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('title', isEqualTo: toTitle)
          .where('date', isEqualTo: workDate)
          .limit(1)
          .get();

      if (toSnapshot.docs.isNotEmpty) {
        await recalculateTOStats(toSnapshot.docs.first.id);
      }

      ToastHelper.showSuccess('지원이 취소되었습니다.');
      return true;
    } catch (e) {
      print('❌ 지원 취소 실패: $e');
      ToastHelper.showError('지원 취소에 실패했습니다.');
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
        'originalWorkType': appData['originalWorkType'] ?? currentWorkType,
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

  // ═══════════════════════════════════════════════════════════
  // 업무 상세 정보 관리 (Work Details Management)
  // ═══════════════════════════════════════════════════════════

  /// 업무 상세 정보 조회 (캐싱 적용)
  Future<List<WorkDetailModel>> getWorkDetails(String toId, {bool forceRefresh = false}) async {
    try {
      print('🔍 getWorkDetails 호출: $toId, forceRefresh=$forceRefresh');
      // 🔥 강제 새로고침이 아닐 때만 캐시 확인
      if (!forceRefresh && _workDetailCache.containsKey(toId)) {
        final cacheTime = _cacheTimestamps['workDetail_$toId'];
        if (cacheTime != null && DateTime.now().difference(cacheTime) < _cacheValidDuration) {
          print('📦 WorkDetails 캐시 사용: $toId');
          return _workDetailCache[toId]!;
        }
      }
      
      print('🔄 WorkDetails Firestore 조회: $toId');
      
      final snapshot = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .orderBy('order')
          .get();

      final workDetails = snapshot.docs
          .map((doc) => WorkDetailModel.fromMap(doc.data(), doc.id))
          .toList();

      // ✅ 캐시 저장
      _workDetailCache[toId] = workDetails;
      _cacheTimestamps['workDetail_$toId'] = DateTime.now();

      print('✅ WorkDetails 조회 완료: ${workDetails.length}개');
      return workDetails;
    } catch (e) {
      print('❌ WorkDetails 조회 실패: $e');
      return [];
    }
  }
  /// 캐시 초기화 (TO 수정/삭제 시 호출)
  void clearCache({String? toId}) {
    if (toId != null) {
      print('🗑️ 캐시 삭제: $toId');
      _applicationCache.remove(toId);
      _workDetailCache.remove(toId);
      _timeRangeCache.remove(toId);
      
      // 🔥🔥🔥 타임스탬프도 삭제! (이게 핵심!)
      _cacheTimestamps.remove('application_$toId');
      _cacheTimestamps.remove('workDetail_$toId');
      _cacheTimestamps.remove('timeRange_$toId');
      
      print('🗑️ 타임스탬프도 삭제 완료');
    } else {
      print('🗑️ 전체 캐시 삭제');
      _applicationCache.clear();
      _workDetailCache.clear();
      _timeRangeCache.clear();
      _cacheTimestamps.clear();
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
          'pendingCount': 0, 
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

  /// WorkDetail 추가
  Future<String> addWorkDetail({  // ✅ void → String
    required String toId,
    required WorkDetailModel workDetail,
  }) async {
    try {
      final docRef = await _firestore  // ✅ await 추가하고 변수에 저장
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .add({
        'workType': workDetail.workType,
        'workTypeIcon': workDetail.workTypeIcon,
        'workTypeColor': workDetail.workTypeColor,
        'wage': workDetail.wage,
        'requiredCount': workDetail.requiredCount,
        'currentCount': 0,
        'pendingCount': 0,
        'startTime': workDetail.startTime,
        'endTime': workDetail.endTime,
        'order': workDetail.order,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('✅ [FirestoreService] WorkDetail 추가 완료: ${docRef.id}');
      return docRef.id;  // ✅ ID 반환
    } catch (e) {
      print('❌ [FirestoreService] WorkDetail 추가 실패: $e');
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
      await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .update(updates);

      print('✅ [FirestoreService] WorkDetail 수정 완료');
    } catch (e) {
      print('❌ [FirestoreService] WorkDetail 수정 실패: $e');
      rethrow;
    }
  }

  /// WorkDetail 삭제
  Future<void> deleteWorkDetail({
    required String toId,
    required String workDetailId,
  }) async {
    try {
      await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .delete();

      print('✅ [FirestoreService] WorkDetail 삭제 완료');
    } catch (e) {
      print('❌ [FirestoreService] WorkDetail 삭제 실패: $e');
      rethrow;
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

  /// WorkDetail의 currentCount 증가 (지원 확정 시)
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

  /// WorkDetail의 currentCount 감소 (지원 취소/거절 시)
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

  // ═══════════════════════════════════════════════════════════
  // 사업장 관리 (Business Management)
  // ═══════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════
  // 업무 유형 관리 (Work Type Management)
  // ═══════════════════════════════════════════════════════════

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

  // ═══════════════════════════════════════════════════════════
  // 사업장별 업무 유형 관리 (Business Work Type Management)
  // ═══════════════════════════════════════════════════════════

  /// 특정 사업장의 업무 유형 목록 조회
  Future<List<BusinessWorkTypeModel>> getBusinessWorkTypes(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .where('isActive', isEqualTo: true)
          .orderBy('displayOrder')
          .get();

      final workTypes = snapshot.docs
          .map((doc) => BusinessWorkTypeModel.fromMap(doc.data(), doc.id))
          .toList();

      print('🔍 Firestore 조회: ${workTypes.length}개');
      return workTypes;
    } catch (e) {
      print('❌ getBusinessWorkTypes 오류: $e');
      return [];
    }
  }

  /// 업무 유형 추가
  Future<String?> addBusinessWorkType({
    required String businessId,
    required String name,
    required String icon,
    String? color,
    String? backgroundColor,
    String wageType = 'hourly',
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
        backgroundColor: backgroundColor, 
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
  Future<bool> updateBusinessWorkType({
    required String businessId,
    required String workTypeId,
    String? name,
    String? icon,
    String? color,
    String? backgroundColor,
    String? wageType,
    int? displayOrder,
    bool showToast = true,
  }) async {
    try {
      print('🔍 [FirestoreService] 업무 유형 수정...');

      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (icon != null) updates['icon'] = icon;
      if (color != null) updates['color'] = color;
      if (backgroundColor != null) updates['backgroundColor'] = backgroundColor;
      if (displayOrder != null) updates['displayOrder'] = displayOrder;
      if (wageType != null) updates['wageType'] = wageType;

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
      
      if (showToast) {
        ToastHelper.showSuccess('업무 유형이 수정되었습니다');
      }
      
      return true;
    } catch (e) {
      print('❌ [FirestoreService] 업무 유형 수정 실패: $e');
      
      if (showToast) {
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
  // ═══════════════════════════════════════════════════════════
  // ✅ Phase 4: TO 마감 관리 (TO Status Management)
  // ═══════════════════════════════════════════════════════════

  /// 진행중인 TO 목록 조회 (대표 TO + 단일 TO)
  Future<List<TOModel>> getActiveTOs() async {
    try {
      // ✅ 모든 TO 조회
      final snapshot = await _firestore
          .collection('tos')
          .orderBy('date', descending: false)
          .get();

      final allTOs = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      // ✅ 1. 대표 TO 또는 단일 TO만 필터링
      final masterOrSingleTOs = allTOs.where((to) {
        if (to.groupId != null) {
          return to.isGroupMaster;
        }
        return true;
      }).toList();

      // 🔥 2. 진행중인 것만 필터링 (수동 마감 + 시간 체크)
      List<TOModel> activeTOs = [];
      
      for (var masterTO in masterOrSingleTOs) {
        if (masterTO.isClosed) continue; // 수동 마감 제외
        
        // 🔥 그룹 TO인 경우: 전체 TO 체크
        if (masterTO.groupId != null) {
          final groupTOs = allTOs.where((to) => to.groupId == masterTO.groupId).toList();
          print('🔍 [그룹체크] ${masterTO.groupName}');
          print('   그룹 내 TO 개수: ${groupTOs.length}개');
  
          
          // 하나라도 진행중이면 포함
          bool hasActive = false;
          for (var to in groupTOs) {
            if (!_isTimeExpired(to)) {
              hasActive = true;
              break;
            }
          }
          
          if (hasActive) {
            activeTOs.add(masterTO);
          }
        } 
        // 🔥 단일 TO인 경우: 바로 시간 체크
        else {
          if (!_isTimeExpired(masterTO)) {
            activeTOs.add(masterTO);
          }
        }
      }

      print('✅ 진행중 TO 조회: ${activeTOs.length}개 (그룹 대표 + 단일 TO)');
      return activeTOs;
    } catch (e) {
      print('❌ 진행중 TO 조회 실패: $e');
      return [];
    }
  }

  // 🔥 시간 초과 체크 헬퍼 함수
  bool _isTimeExpired(TOModel to) {
    final now = DateTime.now();
    final workDate = DateTime(to.date.year, to.date.month, to.date.day);
    final today = DateTime(now.year, now.month, now.day);
    
    print('🔍 [시간체크] ${DateFormat('MM/dd').format(to.date)}');
    print('   workDate: $workDate');
    print('   today: $today');
    // 1. 근무일이 오늘보다 이전이면 무조건 종료
    if (workDate.isBefore(today)) {
      print('   → 과거 날짜, 종료됨');
      return true;
    }
    
    // 2. 근무일이 오늘인 경우 시간 체크
    if (workDate == today) {
      final startTime = to.displayStartTime; // "HH:mm" 형식
      if (startTime == null || startTime.isEmpty || startTime == '--:--') {
        print('   → 오늘, startTime: $startTime');
        return false; // 시간 정보 없으면 진행중으로 간주
      }
      
      try {
        final parts = startTime.split(':');
        final startHour = int.parse(parts[0]);
        final startMinute = int.parse(parts[1]);
        
        final startDateTime = DateTime(
          now.year, now.month, now.day,
          startHour, startMinute,
        );
        
        // 시작 시간이 지났으면 종료
        return now.isAfter(startDateTime);
      } catch (e) {
        return false;
      }
    }
    
    // 3. 근무일이 미래면 진행중
    print('   → 미래 날짜, 진행중');
    return false;
  }

  /// 마감된 TO 목록 조회 (대표 TO + 단일 TO)
  Future<List<TOModel>> getClosedTOs() async {
    try {
      // ✅ 1. 수동 마감된 TO (모든 TO 조회)
      List<TOModel> manualClosed = [];
      try {
        final manualClosedSnapshot = await _firestore
            .collection('tos')
            .where('isManualClosed', isEqualTo: true)
            .orderBy('closedAt', descending: true)
            .get();

        final allManualClosed = manualClosedSnapshot.docs
            .map((doc) => TOModel.fromMap(doc.data(), doc.id))
            .toList();

        // 대표 TO 또는 단일 TO만 필터링
        manualClosed = allManualClosed.where((to) {
          if (to.groupId != null) {
            return to.isGroupMaster;
          }
          return true;
        }).toList();
      } catch (e) {
        print('⚠️ 수동 마감 TO 조회 실패 (필드 없을 수 있음): $e');
      }

      // ✅ 2. 모든 TO 가져와서 자동 마감 체크
      final allSnapshot = await _firestore
          .collection('tos')
          .get();

      final allTOs = allSnapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      // 대표 TO 또는 단일 TO만 필터링
      final masterOrSingleTOs = allTOs.where((to) {
        if (to.groupId != null) {
          return to.isGroupMaster;
        }
        return true;
      }).toList();

      // 자동 마감된 TO (시간 초과 또는 인원 충족) - 수동 마감 제외
      final autoClosed = masterOrSingleTOs
          .where((to) => !to.isManualClosed && to.isClosed)
          .toList();

      // ✅ 3. 합치고 정렬 (최근 마감 순)
      final allClosed = [...manualClosed, ...autoClosed];
      allClosed.sort((a, b) {
        final aDate = a.closedAt ?? a.date;
        final bDate = b.closedAt ?? b.date;
        return bDate.compareTo(aDate);
      });

      print('✅ 마감된 TO 조회: ${allClosed.length}개 (수동: ${manualClosed.length}, 자동: ${autoClosed.length})');
      return allClosed;
    } catch (e) {
      print('❌ 마감된 TO 조회 실패: $e');
      return [];
    }
  }

  /// TO 수동 마감
  Future<bool> closeTOManually(String toId, String adminUID) async {
    try {
      await _firestore.collection('tos').doc(toId).update({
        'isManualClosed': true,
        'closedAt': FieldValue.serverTimestamp(),
        'closedBy': adminUID,
      });

      print('✅ TO 수동 마감 완료: $toId');
      return true;
    } catch (e) {
      print('❌ TO 수동 마감 실패: $e');
      return false;
    }
  }

  /// TO 재오픈 (마감 취소)
  Future<bool> reopenTO(String toId, String adminUID) async {
    try {
      await _firestore.collection('tos').doc(toId).update({
        'isManualClosed': false,
        'reopenedAt': FieldValue.serverTimestamp(),
        'reopenedBy': adminUID,
      });

      print('✅ TO 재오픈 완료: $toId');
      return true;
    } catch (e) {
      print('❌ TO 재오픈 실패: $e');
      return false;
    }
  }

  /// 그룹 TO 전체 마감
  Future<bool> closeGroupTOs(String groupId, String adminUID) async {
    try {
      final snapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isManualClosed': true,
          'closedAt': FieldValue.serverTimestamp(),
          'closedBy': adminUID,
        });
      }

      await batch.commit();
      print('✅ 그룹 TO 전체 마감 완료: $groupId (${snapshot.docs.length}개)');
      return true;
    } catch (e) {
      print('❌ 그룹 TO 전체 마감 실패: $e');
      return false;
    }
  }

  /// 그룹 TO 전체 재오픈
  Future<bool> reopenGroupTOs(String groupId, String adminUID) async {
    try {
      final snapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();

      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isManualClosed': false,
          'reopenedAt': FieldValue.serverTimestamp(),
          'reopenedBy': adminUID,
        });
      }

      await batch.commit();
      print('✅ 그룹 TO 전체 재오픈 완료: $groupId (${snapshot.docs.length}개)');
      return true;
    } catch (e) {
      print('❌ 그룹 TO 전체 재오픈 실패: $e');
      return false;
    }
  }
  // ═══════════════════════════════════════════════════════════
  // 통계 재계산 함수들 (Statistics Recalculation)
  // ═══════════════════════════════════════════════════════════

  /// ✅ WorkDetail 통계 재계산 (TO별)
  Future<bool> recalculateWorkDetailStats(String toId) async {
    try {
      print('📊 WorkDetail 통계 재계산 시작: $toId');
      
      // 1. TO 정보 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return false;
      }
      
      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;
      
      // 2. 이 TO의 모든 지원서 조회
      final appsSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .get();
      
      print('   전체 지원서: ${appsSnapshot.docs.length}개');
      
      // 3. WorkDetails 조회
      final workDetailsSnapshot = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();
      
      if (workDetailsSnapshot.docs.isEmpty) {
        print('   ⚠️ WorkDetails가 없습니다');
        return true;
      }
      
      // 4. 각 WorkDetail별 통계 계산 및 업데이트
      final batch = _firestore.batch();
      int updatedCount = 0;
      
      for (var workDetailDoc in workDetailsSnapshot.docs) {
        final workDetailId = workDetailDoc.id;
        final workType = workDetailDoc.data()['workType'];
        
        // 해당 workType의 지원자 수 계산
        int confirmedCount = 0;
        int pendingCount = 0;
        
        for (var appDoc in appsSnapshot.docs) {
          final appData = appDoc.data();
          final selectedWorkType = appData['selectedWorkType'];
          final status = appData['status'];
          
          // 더미 데이터 제외 (옵션)
          //final isDummy = appData['isDummy'] ?? false;
          //if (isDummy) continue;
          
          if (selectedWorkType == workType) {
            if (status == 'CONFIRMED') confirmedCount++;
            if (status == 'PENDING') pendingCount++;
          }
        }
        
        // 업데이트
        batch.update(
          _firestore
              .collection('tos')
              .doc(toId)
              .collection('workDetails')
              .doc(workDetailId),
          {
            'currentCount': confirmedCount,
            'pendingCount': pendingCount,
          },
        );
        
        print('   ✅ $workType: 확정 $confirmedCount, 대기 $pendingCount');
        updatedCount++;
      }
      
      // 5. 배치 커밋
      await batch.commit();
      
      // 6. 캐시 초기화
      clearCache(toId: toId);
      
      print('✅ WorkDetail 통계 재계산 완료: ${updatedCount}개 업무');
      return true;
    } catch (e) {
      print('❌ WorkDetail 통계 재계산 실패: $e');
      return false;
    }
  }
  
  /// ✅ TO 전체 통계 재계산 (TO + WorkDetails)
  Future<bool> recalculateTOStats(String toId) async {
    try {
      print('📊 TO 전체 통계 재계산 시작: $toId');
      
      // 1. TO 정보 조회
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        print('❌ TO를 찾을 수 없습니다: $toId');
        return false;
      }
      
      final toData = toDoc.data()!;
      final businessId = toData['businessId'];
      final toTitle = toData['title'];
      final workDate = toData['date'] as Timestamp;
      
      // 2. 모든 지원서 조회
      final appsSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: workDate)
          .get();
      
      // 3. TO 레벨 통계 계산
      int totalPending = 0;
      int totalConfirmed = 0;
      
      for (var doc in appsSnapshot.docs) {
        final data = doc.data();
        final status = data['status'];
        
        // 더미 데이터 제외
        //final isDummy = data['isDummy'] ?? false;
        //if (isDummy) continue;
        
        if (status == 'PENDING') totalPending++;
        if (status == 'CONFIRMED') totalConfirmed++;
      }
      
      // 4. TO 문서 업데이트
      await _firestore.collection('tos').doc(toId).update({
        'totalPending': totalPending,
        'totalConfirmed': totalConfirmed,
        'updatedAt': Timestamp.now(),
      });
      
      print('   ✅ TO 통계: 대기 $totalPending, 확정 $totalConfirmed');
      
      // 5. WorkDetails 통계 재계산
      await recalculateWorkDetailStats(toId);
      
      print('✅ TO 전체 통계 재계산 완료');
      return true;
    } catch (e) {
      print('❌ TO 전체 통계 재계산 실패: $e');
      return false;
    }
  }
  
  /// ✅ 그룹 전체 통계 재계산
  Future<bool> recalculateGroupStats(String groupId) async {
    try {
      print('📊 그룹 전체 통계 재계산 시작: $groupId');
      
      // 1. 그룹의 모든 TO 조회
      final groupTOs = await getTOsByGroup(groupId);
      
      if (groupTOs.isEmpty) {
        print('❌ 그룹 TO를 찾을 수 없습니다: $groupId');
        return false;
      }
      
      print('   그룹 TO: ${groupTOs.length}개');
      
      // 2. 각 TO의 통계 재계산
      int successCount = 0;
      for (var to in groupTOs) {
        final success = await recalculateTOStats(to.id);
        if (success) successCount++;
      }
      
      print('✅ 그룹 통계 재계산 완료: ${successCount}/${groupTOs.length}개 성공');
      return successCount == groupTOs.length;
    } catch (e) {
      print('❌ 그룹 통계 재계산 실패: $e');
      return false;
    }
  }
  /// ApplicationModel에서 TO 찾기
  Future<TOModel?> getTOByApplication(ApplicationModel app) async {
    try {
      final snapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: app.businessId)
          .where('title', isEqualTo: app.toTitle)
          .where('date', isEqualTo: Timestamp.fromDate(
            DateTime(app.workDate.year, app.workDate.month, app.workDate.day)
          ))
          .limit(1)
          .get();
      
      if (snapshot.docs.isEmpty) {
        print('⚠️ TO를 찾을 수 없음: ${app.businessId} / ${app.toTitle} / ${app.workDate}');
        return null;
      }
      
      final doc = snapshot.docs.first;
      return TOModel.fromMap(doc.data(), doc.id);
    } catch (e) {
      print('❌ TO 조회 실패: $e');
      return null;
    }
  }
}