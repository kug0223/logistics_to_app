import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:intl/intl.dart';
import '../models/core/user_model.dart';
import '../models/core/to_model.dart';
import '../models/core/application_model.dart';
import '../models/ui/admin_to_list_ui_models.dart'; 
import '../models/core/business_model.dart';
import '../models/core/work_type_model.dart';
import '../models/core/work_detail_model.dart';
import '../utils/toast_helper.dart';
import '../models/core/business_work_type_model.dart';
import '../models/core/attendance_model.dart';
import '../models/core/schedule_change_request_model.dart';
import '../models/core/review_model.dart';
import '../models/core/id_card_access_request_model.dart';
import '../models/core/notification_model.dart';

class FirestoreService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  // ✅ 캐시 추가
  final Map<String, List<ApplicationModel>> _applicationCache = {};
  final Map<String, List<WorkDetailModel>> _workDetailCache = {};
  final Map<String, Map<String, String>> _timeRangeCache = {};
  // 🔥 NEW: 사용자 정보 캐시 추가!
  final Map<String, UserModel> _userCache = {};
  final Map<String, DateTime> _userCacheTimestamps = {};
  final Duration _userCacheValidDuration = const Duration(hours: 1);
  // ⭐ TO 목록 캐시 추가!
  List<TOModel>? _activeTOsCache;
  List<TOModel>? _closedTOsCache;
  DateTime? _activeTOsCacheTime;
  DateTime? _closedTOsCacheTime;
  
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

  /// 사용자 정보 조회 (캐싱 적용!)
  Future<UserModel?> getUser(String uid, {bool forceRefresh = false}) async {
    try {
      print('🔍 getUser 호출: $uid, forceRefresh=$forceRefresh');
      
      // 🔥 강제 새로고침이 아닐 때만 캐시 확인
      if (!forceRefresh && _userCache.containsKey(uid)) {
        final cacheTime = _userCacheTimestamps[uid];
        if (cacheTime != null && DateTime.now().difference(cacheTime) < _userCacheValidDuration) {
          print('📦 User 캐시 사용: $uid');
          return _userCache[uid];
        }
      }
      
      print('🔄 User Firestore 조회: $uid');
      final doc = await _firestore.collection('users').doc(uid).get();
      
      if (!doc.exists) {
        print('❌ 사용자를 찾을 수 없습니다: $uid');
        return null;
      }
      
      final user = UserModel.fromMap(doc.data()!, doc.id);
      
      // ✅ 캐시 저장
      _userCache[uid] = user;
      _userCacheTimestamps[uid] = DateTime.now();
      
      print('✅ User 조회 완료: ${user.name}');
      return user;
    } catch (e) {
      print('❌ 사용자 조회 실패: $e');
      return null;
    }
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
      // ✅ 서버에서 바로 필터링 (오늘 이후만)
      final today = DateTime.now();
      final startOfToday = DateTime(today.year, today.month, today.day);

      final snapshot = await _firestore
          .collection('tos')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .orderBy('date', descending: false)
          .get();

      final toList = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      print('✅ [FirestoreService] 전체 TO 조회 완료: ${toList.length}개');
      return toList;
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
      // ✅ 서버에서 날짜 필터링
      final today = DateTime.now();
      final startOfToday = DateTime(today.year, today.month, today.day);

      final snapshot = await _firestore
          .collection('tos')
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
          .orderBy('date', descending: false)
          .get();

      final allTOs = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      // 필터링: isGroupMaster == true OR groupId == null (클라이언트 - 복합조건이라 필요)
      final result = allTOs.where((to) {
        return to.isGroupMaster || to.groupId == null;
      }).toList();

      print('✅ [FirestoreService] 대표 TO 조회 완료: ${result.length}개');
      return result;
    } catch (e) {
      print('❌ [FirestoreService] 대표 TO 조회 실패: $e');
      return [];
    }
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
    // ⭐ 추가: 장기 근무용
    String? jobType = 'short',
    List<String>? workDays,
    // ✅ 예약 공개 설정
    String publishMode = 'immediate',
    int? publishDaysBefore,
    String? publishTime,
  }) async {
    try {
      print('🔧 [FirestoreService] TO 생성 시작...');

      // 1. 전체 필요 인원 계산
      int totalRequired = 0;
      for (var detail in workDetailsData) {
        totalRequired += (detail['requiredCount'] as int);
      }
      // ✅ 사업장 주소 정보 조회
      String? businessAddress;
      String? businessCity;
      String? businessDistrict;
      try {
        final business = await getBusinessById(businessId);
        if (business != null) {
          businessAddress = business.address;
          businessCity = business.city;
          businessDistrict = business.district;
        }
      } catch (e) {
        print('⚠️ 사업장 주소 조회 실패: $e');
      }

      // ✅ 급여 정보 계산
      final wages = workDetailsData.map((d) => d['wage'] as int).toList();
      final minWage = wages.isNotEmpty ? wages.reduce((a, b) => a < b ? a : b) : 0;
      final maxWage = wages.isNotEmpty ? wages.reduce((a, b) => a > b ? a : b) : 0;
      final wageType = workDetailsData.isNotEmpty ? (workDetailsData.first['wageType'] ?? 'hourly') : 'hourly';
      final workDetailCount = workDetailsData.length;
      // 2. TO 기본 정보 생성
      // ✅ publishAt 계산 (예약 공개인 경우)
      DateTime? publishAt;
      bool shouldPublishImmediately = publishMode == 'immediate';
      
      if (publishMode == 'scheduled' && publishDaysBefore != null && publishTime != null) {
        final targetDate = date.subtract(Duration(days: publishDaysBefore));
        final timeParts = publishTime.split(':');
        publishAt = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
        
        // ✅ 과거 날짜면 즉시 공개로 전환
        if (publishAt.isBefore(DateTime.now())) {
          shouldPublishImmediately = true;
          print('⚠️ 공개 예정 시간이 과거입니다. 즉시 공개로 전환합니다.');
        }
      }
      final toData = {
        'businessId': businessId,
        'businessName': businessName,
        'businessAddress': businessAddress,
        'businessCity': businessCity,
        'businessDistrict': businessDistrict,
        'jobType': jobType ?? 'short',
        'workDays': workDays,
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
        // ✅ 급여 정보
        'minWage': minWage,
        'maxWage': maxWage,
        'wageType': wageType,
        'workDetailCount': workDetailCount,
        'description': description ?? '',
        'creatorUID': creatorUID,
        'createdAt': FieldValue.serverTimestamp(),
        // ✅ 예약 공개 설정
        'publishMode': publishMode,
        'publishAt': publishAt != null ? Timestamp.fromDate(publishAt) : null,
        'isPublished': shouldPublishImmediately,  // 즉시 공개 또는 과거 날짜면 true
        'publishDaysBefore': publishDaysBefore,
        'publishTime': publishTime,
      };

      // 3. TO 문서 생성
      final toDoc = await _firestore.collection('tos').add(toData);
      print('✅ TO 문서 생성 완료: ${toDoc.id}');

      // 4. WorkDetails 하위 컬렉션에 업무 추가
      final batch = _firestore.batch();
      
        for (int i = 0; i < workDetailsData.length; i++) {
        final data = workDetailsData[i];
        final docRef = toDoc.collection('workDetails').doc();
        
        // 🔥 장기 공고는 WorkDetail에 마감시간 설정 안 함
        DateTime? workDeadline;
        
        if (jobType != 'long_term') {
          // 단기 공고만 WorkDetail별 마감시간 계산
          if (deadlineType == 'HOURS_BEFORE') {
            final startTime = data['startTime'] as String;
            final timeParts = startTime.split(':');
            final workStartDateTime = DateTime(
              date.year,
              date.month,
              date.day,
              int.parse(timeParts[0]),
              int.parse(timeParts[1]),
            );
            workDeadline = workStartDateTime.subtract(
              Duration(hours: hoursBeforeStart ?? 2)
            );
          } else {
            workDeadline = applicationDeadline;
          }
        }
        
        batch.set(docRef, {
          'workType': data['workType'],
          'workTypeIcon': data['workTypeIcon'],
          'workTypeColor': data['workTypeColor'],
          'workTypeBackgroundColor': data['workTypeBackgroundColor'],
          'wage': data['wage'],
          'wageType': data['wageType'] ?? 'hourly',
          'requiredCount': data['requiredCount'],
          'currentCount': 0,
          'pendingCount': 0,      
          'startTime': data['startTime'],
          'endTime': data['endTime'],
          'order': i,
          'createdAt': FieldValue.serverTimestamp(),
          // 🔥 장기 공고는 WorkDetail 마감시간 없음
          if (workDeadline != null) 'applicationDeadline': Timestamp.fromDate(workDeadline),
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
      // ✅ 사업장 주소 정보 조회
      String? businessAddress;
      String? businessCity;
      String? businessDistrict;
      try {
        final business = await getBusinessById(businessId);
        if (business != null) {
          businessAddress = business.address;
          businessCity = business.city;
          businessDistrict = business.district;
        }
      } catch (e) {
        print('⚠️ 사업장 주소 조회 실패: $e');
      }
      // ✅ 급여 정보 계산
      final wages = workDetails.map((d) => d['wage'] as int).toList();
      final minWage = wages.isNotEmpty ? wages.reduce((a, b) => a < b ? a : b) : 0;
      final maxWage = wages.isNotEmpty ? wages.reduce((a, b) => a > b ? a : b) : 0;
      final wageType = workDetails.isNotEmpty ? (workDetails.first['wageType'] ?? 'hourly') : 'hourly';
      final workDetailCount = workDetails.length;

      // 각 날짜별 TO 생성
      for (int i = 0; i < dates.length; i++) {
        final toData = {
          'businessId': businessId,
          'businessName': businessName,
          'businessAddress': businessAddress,
          'businessCity': businessCity,
          'businessDistrict': businessDistrict,
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
          // ✅ 급여 정보
          'minWage': minWage,
          'maxWage': maxWage,
          'wageType': wageType,
          'workDetailCount': workDetailCount,
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
            'wageType': workDetails[j]['wageType'] ?? 'hourly',
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
      
      // ✅ 대상 그룹 마스터 통계 동기화
      await _updateGroupMasterStats(targetGroupId);
      
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
      
      // ✅ 그룹 마스터 통계 초기화
      await _updateGroupMasterStats(groupId);
      
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
      // ✅ 급여 정보 계산
      final wages = workDetails.map((d) => d['wage'] as int).toList();
      final minWage = wages.isNotEmpty ? wages.reduce((a, b) => a < b ? a : b) : 0;
      final maxWage = wages.isNotEmpty ? wages.reduce((a, b) => a > b ? a : b) : 0;
      final wageType = workDetails.isNotEmpty ? (workDetails.first['wageType'] ?? 'hourly') : 'hourly';
      final workDetailCount = workDetails.length;

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
          // ✅ 급여 정보
          'minWage': minWage,
          'maxWage': maxWage,
          'wageType': wageType,
          'workDetailCount': workDetailCount,
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
            'wageType': detail['wageType'] ?? 'hourly',
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
      
      // ✅ 그룹 마스터 통계 동기화
      await _updateGroupMasterStats(groupId);
      
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
      
      // ✅ 그룹 마스터 통계 동기화 (그룹이 남아있는 경우만)
      if (groupId != null) {
        final remainingTOs = await getTOsByGroup(groupId);
        if (remainingTOs.isNotEmpty) {
          await _updateGroupMasterStats(groupId);
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
      
      // 1. TO를 독립 TO로 변경
      await _firestore.collection('tos').doc(toId).update({
        'groupId': FieldValue.delete(),
        'groupName': FieldValue.delete(),
        'isGroupMaster': false,
        'startDate': FieldValue.delete(),
        'endDate': FieldValue.delete(),
      });

      // 2. 남은 그룹 TO 확인 (최신 데이터 다시 조회)
      final remainingSnapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();

      final remainingTOs = remainingSnapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();
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
        clearCache(toId: lastTO.id);
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
      
      clearCache(toId: toId);
      
      // ✅ 그룹 마스터 통계 동기화 (그룹이 남아있는 경우만)
      if (remainingTOs.length > 1) {
        await _updateGroupMasterStats(groupId);
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
      
      print('✅ 그룹 날짜 범위 업데이트: $minDate ~ $maxDate');
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

  /// 여러 TO의 지원자를 한 번에 조회 (병렬 최적화!)
  Future<Map<String, List<ApplicationModel>>> getApplicationsByTOIds(List<String> toIds) async {
    try {
      if (toIds.isEmpty) return {};
      
      print('🔍 배치 지원자 조회 시작: ${toIds.length}개 TO (병렬 처리)');
      
      // ✅ 병렬로 각 TO의 지원서 조회
      final futures = toIds.map((toId) async {
        // TO 정보 조회
        final toDoc = await _firestore.collection('tos').doc(toId).get();
        if (!toDoc.exists) {
          return MapEntry(toId, <ApplicationModel>[]);
        }

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

        final apps = snapshot.docs
            .map((doc) => ApplicationModel.fromFirestore(doc))
            .toList();
        
        return MapEntry(toId, apps);
      }).toList();
      
      // ✅ 병렬 실행 완료 대기
      final results = await Future.wait(futures);
      final result = Map.fromEntries(results);
      
      print('✅ 배치 지원자 조회 완료 (병렬): ${toIds.length}개 TO, ${result.values.fold(0, (sum, list) => sum + list.length)}명');
      return result;
    } catch (e) {
      print('❌ 배치 지원자 조회 실패: $e');
      return {};
    }
  }
  /// 사업장별 지원자 목록 조회
  Future<List<ApplicationModel>> getApplicationsByBusinessId(String businessId) async {
    try {
      print('📋 사업장별 지원서 조회 시작: $businessId');
      
      final snapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .get();

      final applications = snapshot.docs
          .map((doc) => ApplicationModel.fromMap(doc.data(), doc.id))
          .toList();

      print('✅ 사업장별 지원서 조회 완료: ${applications.length}개');
      return applications;
    } catch (e) {
      print('❌ 사업장별 지원서 조회 실패: $e');
      return [];
    }
  }
  /// 여러 TO의 지원자를 한 번에 조회 (TO 정보 전달 - 중복 조회 제거)
  Future<Map<String, List<ApplicationModel>>> getApplicationsByTOs(List<TOModel> tos) async {
    try {
      if (tos.isEmpty) return {};
      
      print('🔍 배치 지원자 조회 시작: ${tos.length}개 TO (TO 정보 재사용)');
      
      final futures = tos.map((to) async {
        // ✅ TO 정보는 이미 있음 - 재조회 안 함!
        final snapshot = await _firestore
            .collection('applications')
            .where('businessId', isEqualTo: to.businessId)
            .where('toTitle', isEqualTo: to.title)
            .where('workDate', isEqualTo: Timestamp.fromDate(to.date))
            .get();

        final apps = snapshot.docs
            .map((doc) => ApplicationModel.fromFirestore(doc))
            .toList();
        
        return MapEntry(to.id, apps);
      }).toList();
      
      final results = await Future.wait(futures);
      final result = Map.fromEntries(results);
      
      print('✅ 배치 지원자 조회 완료: ${tos.length}개 TO, ${result.values.fold(0, (sum, list) => sum + list.length)}명');
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
  // ═══════════════════════════════════════════════════════════
  // Phase 2: 충돌 방지 시스템
  // ═══════════════════════════════════════════════════════════
  
  /// 시간이 겹치는지 체크
  bool _hasTimeOverlap(String s1, String e1, String s2, String e2) {
    final start1 = _timeToMinutes(s1);
    final end1 = _timeToMinutes(e1);
    final start2 = _timeToMinutes(s2);
    final end2 = _timeToMinutes(e2);
    
    // 겹치지 않는 경우: end1 <= start2 || end2 <= start1
    // 겹치는 경우: 위의 반대
    return !(end1 <= start2 || end2 <= start1);
  }
  
  /// 시간을 분 단위로 변환 (예: "09:30" → 570)
  int _timeToMinutes(String time) {
    final parts = time.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
  
  /// 충돌하는 지원서 찾기 (장기 공고 날짜 확장 포함)
  Future<List<ApplicationModel>> findConflictingApplications({
    required String uid,
    required DateTime workDate,
    required String startTime,
    required String endTime,
    required String excludeId,
    String status = 'PENDING',
  }) async {
    try {
      // 1. 해당 상태의 모든 지원서 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: status)
          .get();
      
      // 2. 날짜와 시간대 겹침 필터링
      final conflicts = <ApplicationModel>[];
      
      for (var doc in snapshot.docs) {
        if (doc.id == excludeId) continue;
        
        final app = ApplicationModel.fromFirestore(doc);
        
        // 해당 날짜에 근무하는지 확인
        if (!_isWorkingOnDate(app, workDate)) continue;
        
        // 시간대 겹침 확인
        if (_hasTimeOverlap(startTime, endTime, app.startTime, app.endTime)) {
          conflicts.add(app);
        }
      }
      
      print('✅ 충돌하는 지원서 ${conflicts.length}개 발견');
      return conflicts;
    } catch (e) {
      print('❌ 충돌 지원서 조회 실패: $e');
      return [];
    }
  }
  
  /// 확정된 근무 일정 조회 (장기 공고 날짜 확장 포함)
  Future<List<ApplicationModel>> getConfirmedSchedules({
    required String uid,
    required DateTime workDate,
  }) async {
    try {
      // 1. 모든 확정된 지원서 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'CONFIRMED')
          .get();
      
      final allConfirmed = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
      
      // 2. 해당 날짜와 겹치는 근무만 필터링
      final relevantSchedules = <ApplicationModel>[];
      
      for (var app in allConfirmed) {
        if (_isWorkingOnDate(app, workDate)) {
          relevantSchedules.add(app);
        }
      }
      
      print('✅ ${workDate.month}/${workDate.day}에 확정된 근무: ${relevantSchedules.length}개');
      return relevantSchedules;
    } catch (e) {
      print('❌ 확정 일정 조회 실패: $e');
      return [];
    }
  }
  
  /// 특정 날짜에 근무하는지 확인 (장기 공고 고려)
  bool _isWorkingOnDate(ApplicationModel app, DateTime targetDate) {
    // 단기: workDate만 체크
    if (!app.isLongTermApplication) {
      return _isSameDate(app.workDate, targetDate);
    }
    
    // 장기: 시작일~종료일 범위 + 근무 요일 체크
    if (app.workEndDate == null) return false;
    
    // 날짜 범위 체크
    final isInRange = !targetDate.isBefore(app.workDate) && 
                      !targetDate.isAfter(app.workEndDate!);
    
    if (!isInRange) return false;
    
    // 근무 요일 체크
    if (app.workDays == null || app.workDays!.isEmpty) {
      return true; // 모든 날 근무
    }
    
    final targetDayKorean = _getKoreanDayOfWeek(targetDate);
    return app.workDays!.contains(targetDayKorean);
  }
  
  /// 두 날짜가 같은지 비교 (시간 제외)
  bool _isSameDate(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
           date1.month == date2.month &&
           date1.day == date2.day;
  }
  
  /// 요일을 한글로 변환
  String _getKoreanDayOfWeek(DateTime date) {
    const days = ['월', '화', '수', '목', '금', '토', '일'];
    return days[date.weekday - 1];
  }
  /// 지원서 상태 업데이트 (승인/거절) - Phase 2: 자동 취소 추가
  Future<void> updateApplicationStatus({
    required String applicationId,
    required String status,
    String? confirmedBy,
    String? rejectedBy,
    String? message,  // ⭐ Phase 2: 메시지 추가
  }) async {
    try {
      // ⭐ Phase 2: 확정 시 충돌 처리
      if (status == 'CONFIRMED') {
        await _confirmWithConflictCheck(
          applicationId: applicationId,
          confirmedBy: confirmedBy,
          message: message,
        );
        return;
      }
      
      // 기존 로직 (거절 등)
      final updates = <String, dynamic>{
        'status': status,
      };

      if (status == 'REJECTED') {
        updates['rejectedAt'] = FieldValue.serverTimestamp();
        if (rejectedBy != null) {
          updates['rejectedBy'] = rejectedBy;
        }
        if (message != null) {
          updates['rejectMessage'] = message;  // ⭐ Phase 2
        }
      }

      await _firestore
          .collection('applications')
          .doc(applicationId)
          .update(updates);

      print('✅ 지원서 상태 업데이트: $status');
      
      // ✅ TO 통계 재계산 (REJECTED 시)
      if (status == 'REJECTED') {
        final appDoc = await _firestore
            .collection('applications')
            .doc(applicationId)
            .get();
        
        if (appDoc.exists) {
          final appData = appDoc.data()!;
          final toSnapshot = await _firestore
              .collection('tos')
              .where('businessId', isEqualTo: appData['businessId'])
              .where('title', isEqualTo: appData['toTitle'])
              .where('date', isEqualTo: appData['workDate'])
              .limit(1)
              .get();
          
          if (toSnapshot.docs.isNotEmpty) {
            final toId = toSnapshot.docs.first.id;
            await recalculateTOStats(toId);
            clearCache(toId: toId);
            print('📊 TO 통계 재계산 완료: $toId');
          }
        }
      }
    } catch (e) {
      print('❌ 지원서 상태 업데이트 실패: $e');
      rethrow;
    }
  }
  
  /// 확정 처리 + 충돌하는 지원 자동 취소
  Future<void> _confirmWithConflictCheck({
    required String applicationId,
    String? confirmedBy,
    String? message,
  }) async {
    try {
      // 1. 확정할 지원서 조회
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();
      
      if (!appDoc.exists) {
        throw Exception('지원서를 찾을 수 없습니다');
      }
      
      final appData = appDoc.data()!;
      final app = ApplicationModel.fromMap(appData, appDoc.id);
      
      // 2. 충돌하는 대기중 지원서 찾기
      final conflictingApps = await findConflictingApplications(
        uid: app.uid,
        workDate: app.workDate,
        startTime: app.startTime,
        endTime: app.endTime,
        excludeId: applicationId,
        status: 'PENDING',
      );
      
      // 3. 배치로 처리
      final batch = _firestore.batch();
      
      // 3-1. 확정 처리
      final confirmUpdates = <String, dynamic>{
        'status': 'CONFIRMED',
        'confirmedAt': FieldValue.serverTimestamp(),
      };
      if (confirmedBy != null) {
        confirmUpdates['confirmedBy'] = confirmedBy;
      }
      if (message != null) {
        confirmUpdates['confirmMessage'] = message;  // ⭐ Phase 2
      }
      
      batch.update(
        _firestore.collection('applications').doc(applicationId),
        confirmUpdates,
      );
      
      // 3-2. 충돌하는 지원들 자동 취소
      for (var conflictApp in conflictingApps) {
        batch.update(
          _firestore.collection('applications').doc(conflictApp.id),
          {
            'status': 'AUTO_CANCELED',  // ⭐ 새로운 상태
            'canceledAt': FieldValue.serverTimestamp(),
            'cancelReason': 'SCHEDULE_CONFLICT',
            'conflictingAppId': applicationId,
            'conflictingBusiness': app.businessName,
            'conflictingTime': '${app.startTime}~${app.endTime}',
          },
        );
      }
      
      await batch.commit();
      
      print('✅ 확정 완료 + ${conflictingApps.length}개 자동 취소');
      
      // 4. ✅ TO 통계 재계산
      // TO 찾기
      final toSnapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: app.businessId)
          .where('title', isEqualTo: app.toTitle)
          .where('date', isEqualTo: Timestamp.fromDate(app.workDate))
          .limit(1)
          .get();
      
      if (toSnapshot.docs.isNotEmpty) {
        final toId = toSnapshot.docs.first.id;
        await recalculateTOStats(toId);
        clearCache(toId: toId);
        
        // ✅ 그룹 마스터 통계 동기화
        await syncGroupMasterStats(toId);
        print('📊 TO 통계 재계산 + 그룹 동기화 완료: $toId');
      }
      
      // 4. 알림 발송 (나중에 구현)
      // TODO: Phase 2-D에서 구현
      
    } catch (e) {
      print('❌ 확정 + 충돌 처리 실패: $e');
      rethrow;
    }
  }
  /// TO의 모든 지원서 조회 (businessId, title, date 기준)
  Future<List<ApplicationModel>> getApplicationsByTO(
    String businessId,
    String title,
    DateTime date,
  ) async {
    try {
      // ✅ 날짜 범위로 조회 (시간 무관하게 해당 날짜 전체)
      final dateStart = DateTime(date.year, date.month, date.day);
      final dateEnd = dateStart.add(const Duration(days: 1));
      
      final snapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: title)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .where('workDate', isLessThan: Timestamp.fromDate(dateEnd))
          .get();

      final apps = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();

      print('✅ TO 지원서 조회: ${apps.length}개 (businessId=$businessId, title=$title, date=$dateStart~$dateEnd)');
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
    // ⭐ Phase 1: 장기 공고 정보 추가
    DateTime? workEndDate,
    List<String>? workDays,
    String type = 'short',
  }) async {
    try {
      // ✅ 서버 레벨 서류 체크
      final userDoc = await _firestore.collection('users').doc(uid).get();
      
      if (!userDoc.exists) {
        ToastHelper.showError('사용자 정보를 찾을 수 없습니다.');
        return false;
      }
      
      final userData = userDoc.data()!;
      
      // 필수 서류 체크
      if (userData['idCardImageUrl'] == null) {
        ToastHelper.showError('신분증 등록이 필요합니다.');
        return false;
      }
      
      if (userData['bankName'] == null || userData['accountNumber'] == null) {
        ToastHelper.showError('통장 정보 등록이 필요합니다.');
        return false;
      }
      
      if (userData['bankbookImageUrl'] == null) {
        ToastHelper.showError('통장사본 등록이 필요합니다.');
        return false;
      }
      // 1. 중복 지원 확인 - ⭐ Phase 2: 취소/거절된 지원은 제외
      final existingApp = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('toTitle', isEqualTo: toTitle)
          .where('workDate', isEqualTo: Timestamp.fromDate(workDate))
          .where('uid', isEqualTo: uid)
          .where('selectedWorkType', isEqualTo: selectedWorkType)
          .limit(1)
          .get();

      if (existingApp.docs.isNotEmpty) {
        final app = ApplicationModel.fromFirestore(existingApp.docs.first);
        print('🔍 기존 지원서 발견: status = ${app.status}'); // ⭐ 디버그 로그
        
        // ⭐ 취소/거절된 지원은 다시 지원 가능
        if (app.status == 'CANCELED' || 
            app.status == 'AUTO_CANCELED' || 
            app.status == 'REJECTED') {
          print('✅ 이전 지원이 취소/거절됨 → 재지원 허용');
          // 중복 체크 통과, 아래 로직 계속 진행
        } else {
          ToastHelper.showWarning('이미 지원한 업무입니다.');
          return false;
        }
      }
      // ⭐ Phase 2-C: 확정된 근무와 충돌 체크
      final confirmedSchedules = await getConfirmedSchedules(
        uid: uid,
        workDate: workDate,
      );
      
      for (var schedule in confirmedSchedules) {
        if (_hasTimeOverlap(
          startTime,
          endTime,
          schedule.startTime,
          schedule.endTime,
        )) {
          // ⚠️ 충돌 발견!
          ToastHelper.showError(
            '이미 ${schedule.startTime}~${schedule.endTime}에\n'
            '${schedule.businessName}에서 확정된 근무가 있습니다.\n\n'
            '해당 시간대에는 추가 지원이 불가능합니다.'
          );
          return false;
        }
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
        // ⭐ Phase 1: 장기 공고 정보 추가
        'type': type,
        'workEndDate': workEndDate != null 
            ? Timestamp.fromDate(workEndDate) 
            : null,
        'workDays': workDays,
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

      // ✅ 🔥 Batch commit 추가! (이게 없어서 지원서가 저장 안 됨!)
      await batch.commit();
      print('✅ Batch commit 완료');

      /// ✅ 통계 재계산 (통합 로직 사용)
      print('📊 지원 생성 후 통계 재계산...');
      await recalculateTOStats(toId);
      clearCache(toId: toId);
      
      // ✅ 그룹 마스터 통계 동기화
      await syncGroupMasterStats(toId);
      print('🗑️ 지원 후 캐시 클리어 + 그룹 동기화 완료');

      print('✅ 지원 완료: businessId=$businessId, toTitle=$toTitle, WorkType=$selectedWorkType');
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
      
      // ✅ 그룹 마스터 통계 동기화
      await syncGroupMasterStats(toId);

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
  Future<bool> rejectApplicant(
    String applicationId, 
    String adminUID, {
    String? rejectMessage,
  }) async {
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
      final updateData = <String, dynamic>{
        'status': 'REJECTED',
        'rejectedAt': FieldValue.serverTimestamp(),
        'rejectedBy': adminUID,
      };
      
      if (rejectMessage != null && rejectMessage.isNotEmpty) {
        updateData['rejectMessage'] = rejectMessage;
      }
      
      await _firestore.collection('applications').doc(applicationId).update(updateData);

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
        final toId = toSnapshot.docs.first.id;
        await recalculateTOStats(toId);
        clearCache(toId: toId);
        
        // ✅ 그룹 마스터 통계 동기화
        await syncGroupMasterStats(toId);
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
        final toId = toSnapshot.docs.first.id;
        await recalculateTOStats(toId);
        clearCache(toId: toId);
        
        // ✅ 그룹 마스터 통계 동기화
        await syncGroupMasterStats(toId);
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
      // 🔥 강제 새로고침이 아닐 때만 캐시 확인
      if (!forceRefresh && _workDetailCache.containsKey(toId)) {
        final cacheTime = _cacheTimestamps['workDetail_$toId'];
        if (cacheTime != null && DateTime.now().difference(cacheTime) < _cacheValidDuration) {
          return _workDetailCache[toId]!;
        }
      }
      
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
      
      // 타임스탬프도 삭제
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

      // TO 목록 캐시도 삭제
      _activeTOsCache = null;
      _closedTOsCache = null;
      _activeTOsCacheTime = null;
      _closedTOsCacheTime = null;
      
      // 🔥 NEW: 사용자 캐시도 삭제
      _userCache.clear();
      _userCacheTimestamps.clear();
      
      print('🗑️ 전체 캐시 삭제 완료 (사용자 포함)');
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
          'wageType': data['wageType'] ?? 'hourly',
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
        'workTypeBackgroundColor': workDetail.workTypeBackgroundColor,
        'wage': workDetail.wage,
        'wageType': workDetail.wageType,
        'requiredCount': workDetail.requiredCount,
        'currentCount': 0,
        'pendingCount': 0,
        'startTime': workDetail.startTime,
        'endTime': workDetail.endTime,
        'order': workDetail.order,
        'createdAt': FieldValue.serverTimestamp(),
      });

      print('✅ [FirestoreService] WorkDetail 추가 완료: ${docRef.id}');
      
      // ✅ TO의 totalRequired 업데이트
      await _recalculateTotalRequired(toId);
      
      // ✅ 그룹 TO면 마스터 통계도 동기화
      await syncGroupMasterStats(toId);
      
      return docRef.id;
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
      
      // ✅ 인원 또는 급여 변경 시 TO 정보 업데이트
      if (updates.containsKey('requiredCount') || 
          updates.containsKey('wage') || 
          updates.containsKey('wageType')) {
        await _recalculateTOWorkInfo(toId);
        
        // ✅ 그룹 TO면 마스터 통계도 동기화
        await syncGroupMasterStats(toId);
      }
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
      
      // ✅ TO의 totalRequired 업데이트
      await _recalculateTotalRequired(toId);
      
      // ✅ 그룹 TO면 마스터 통계도 동기화
      await syncGroupMasterStats(toId);
      
      print('✅ [FirestoreService] WorkDetail 삭제 완료');
    } catch (e) {
      print('❌ [FirestoreService] WorkDetail 삭제 실패: $e');
      rethrow;
    }
  }
  
  /// WorkDetail 마감
  Future<bool> closeWorkDetail({
    required String toId,
    required String workDetailId,
    required String adminUID,
  }) async {
    try {
      await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .update({
        'closedAt': FieldValue.serverTimestamp(),
        'closedBy': adminUID,
      });
      
      clearCache(toId: toId);
      print('✅ WorkDetail 마감 완료: $workDetailId');
      return true;
    } catch (e) {
      print('❌ WorkDetail 마감 실패: $e');
      return false;
    }
  }
  /// WorkDetail 재오픈
  Future<bool> reopenWorkDetail({
    required String toId,
    required String workDetailId,
    required String adminUID,
  }) async {
    try {
      await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .update({
        'closedAt': FieldValue.delete(),
        'closedBy': FieldValue.delete(),
        'reopenedAt': FieldValue.serverTimestamp(),
        'reopenedBy': adminUID,
      });
      
      clearCache(toId: toId);
      print('✅ WorkDetail 재오픈 완료: $workDetailId');
      return true;
    } catch (e) {
      print('❌ WorkDetail 재오픈 실패: $e');
      return false;
    }
  }
  /// WorkDetail 긴급 모집 시작
  Future<bool> startEmergencyRecruitment({
    required String toId,
    required String workDetailId,
    required String adminUID,
  }) async {
    try {
      await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .update({
        'isEmergencyOpen': true,
        'emergencyStartedAt': FieldValue.serverTimestamp(),
        'emergencyStartedBy': adminUID,
      });
      
      clearCache(toId: toId);
      print('✅ 긴급 모집 시작: $workDetailId');
      return true;
    } catch (e) {
      print('❌ 긴급 모집 시작 실패: $e');
      return false;
    }
  }

  /// WorkDetail 긴급 모집 종료
  Future<bool> stopEmergencyRecruitment({
    required String toId,
    required String workDetailId,
    required String adminUID,
  }) async {
    try {
      await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .doc(workDetailId)
          .update({
        'isEmergencyOpen': false,
        'emergencyStoppedAt': FieldValue.serverTimestamp(),
        'emergencyStoppedBy': adminUID,
      });
      
      clearCache(toId: toId);
      print('✅ 긴급 모집 종료: $workDetailId');
      return true;
    } catch (e) {
      print('❌ 긴급 모집 종료 실패: $e');
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
  
  /// 사업장 ID로 조회
  Future<BusinessModel?> getBusinessById(String businessId) async {
    try {
      final doc = await _firestore.collection('businesses').doc(businessId).get();
      
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
  Future<List<BusinessModel>> getMyBusiness(String ownerId) async {
    try {
      print('🔍 [FirestoreService] 내 사업장 조회 시작...');
      print('   ownerId: $ownerId');

      final snapshot = await _firestore
      .collection('businesses')
      .where('ownerId', isEqualTo: ownerId)
      .orderBy('createdAt', descending: true)
      .get(const GetOptions(source: Source.server));

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

  /// 업무 유형 삭제 (소프트 삭제 + Storage 이미지 삭제)
  Future<bool> deleteBusinessWorkType({
    required String businessId,
    required String workTypeId,
  }) async {
    try {
      print('🔍 [FirestoreService] 업무 유형 삭제...');

      // ✅ 1. 업무유형 문서 조회 (이미지 URL 확인)
      final doc = await _firestore
          .collection('businesses')
          .doc(businessId)
          .collection('workTypes')
          .doc(workTypeId)
          .get();
      
      if (doc.exists) {
        final data = doc.data()!;
        final storage = FirebaseStorage.instance;
        
        // ✅ 2. 썸네일 이미지 삭제
        if (data['thumbnailUrl'] != null) {
          try {
            await storage.refFromURL(data['thumbnailUrl']).delete();
            print('✅ 썸네일 삭제: ${data['thumbnailUrl']}');
          } catch (e) {
            print('⚠️ 썸네일 삭제 실패: $e');
          }
        }
        
        // ✅ 3. 추가 이미지들 삭제
        if (data['images'] != null) {
          for (var url in List<String>.from(data['images'])) {
            try {
              await storage.refFromURL(url).delete();
              print('✅ 이미지 삭제: $url');
            } catch (e) {
              print('⚠️ 이미지 삭제 실패: $e');
            }
          }
        }
      }

      // ✅ 4. Firestore 소프트 삭제
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
  /// [publishedOnly] true면 공개된 TO만 (사용자용), false면 전체 (관리자용)
  Future<List<TOModel>> getActiveTOs({bool publishedOnly = false}) async {
    try {
      final snapshot = await _firestore
          .collection('tos')
          .orderBy('date', descending: false)
          .get();

      final allTOs = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      // 1. 대표 TO 또는 단일 TO만 필터링
      final masterOrSingleTOs = allTOs.where((to) {
        if (to.groupId != null) {
          return to.isGroupMaster;
        }
        return true;
      }).toList();

      // 2. 진행중인 것만 필터링
      List<TOModel> activeTOs = [];
      
      for (var masterTO in masterOrSingleTOs) {
        if (masterTO.isManualClosed) continue; // 🔥 수동 마감 제외
        
        // 그룹 TO인 경우
        if (masterTO.groupId != null) {
          final groupTOs = allTOs.where((to) => to.groupId == masterTO.groupId).toList();
          
          // 🔥 모든 TO의 모든 WorkDetail이 마감됐는지 확인
          bool allClosed = true;
          
          for (var to in groupTOs) {
            if (to.isManualClosed) continue; // 개별 TO가 수동 마감된 경우 스킵
            
            final workDetails = await getWorkDetails(to.id);
            
            // 하나라도 진행중이면 그룹 전체가 진행중
            for (var work in workDetails) {
              if (!work.isClosed && !work.isTimeExpired && !work.isFull) {
                allClosed = false;
                break;
              }
            }
            
            if (!allClosed) break;
          }
          
          // 하나라도 진행중이면 포함
          if (!allClosed) {
            activeTOs.add(masterTO);
          }
        } 
        // 단일 TO인 경우
        else {
          // 🔥 장기공고: TO 레벨의 applicationDeadline 기준
          if (masterTO.isLongTerm) {
            if (!masterTO.isDeadlinePassed) {
              activeTOs.add(masterTO);
            }
            continue;
          }
          
          // 단기공고: WorkDetails 기준
          final workDetails = await getWorkDetails(masterTO.id);
          
          // 🔥 모든 WorkDetail이 마감됐는지 확인
          bool allClosed = workDetails.isNotEmpty && 
            workDetails.every((work) => 
              work.isClosed || work.isTimeExpired || work.isFull
            );
          
          // 하나라도 진행중이면 포함
          if (!allClosed) {
            activeTOs.add(masterTO);
          }
        }
      }

      // ✅ 공개 필터링 (사용자용)
      if (publishedOnly) {
        final publishedTOs = activeTOs.where((to) => to.isPublished).toList();
        print('✅ 공개된 진행중 TO: ${publishedTOs.length}개 (전체 ${activeTOs.length}개 중)');
        return publishedTOs;
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
      if (startTime.isEmpty || startTime == '--:--') {
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
      // 1. 모든 TO 가져오기
      final snapshot = await _firestore
          .collection('tos')
          .orderBy('date', descending: false)
          .get();

      final allTOs = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      // 2. 대표 TO 또는 단일 TO만 필터링
      final masterOrSingleTOs = allTOs.where((to) {
        if (to.groupId != null) {
          return to.isGroupMaster;
        }
        return true;
      }).toList();

      // 3. 마감된 것만 필터링
      List<TOModel> closedTOs = [];
      
      for (var masterTO in masterOrSingleTOs) {
        // 수동 마감된 경우 무조건 포함
        if (masterTO.isManualClosed) {
          closedTOs.add(masterTO);
          continue;
        }
        
        // 그룹 TO인 경우
        if (masterTO.groupId != null) {
          final groupTOs = allTOs.where((to) => to.groupId == masterTO.groupId).toList();
          
          // 🔥 모든 TO의 모든 WorkDetail이 마감됐는지 확인
          bool allClosed = true;
          
          for (var to in groupTOs) {
            final workDetails = await getWorkDetails(to.id);
            
            // 하나라도 진행중이면 그룹은 마감 아님
            for (var work in workDetails) {
              if (!work.isClosed && !work.isTimeExpired && !work.isFull) {
                allClosed = false;
                break;
              }
            }
            
            if (!allClosed) break;
          }
          
          // 모두 마감됐으면 포함
          if (allClosed) {
            closedTOs.add(masterTO);
          }
        } 
        // 단일 TO인 경우
        else {
          // 🔥 장기공고: TO 레벨의 applicationDeadline 기준
          if (masterTO.isLongTerm) {
            if (masterTO.isDeadlinePassed) {
              closedTOs.add(masterTO);
            }
            continue;
          }
          
          // 단기공고: WorkDetails 기준
          final workDetails = await getWorkDetails(masterTO.id);
          
          // 🔥 모든 WorkDetail이 마감됐는지 확인
          bool allClosed = workDetails.isNotEmpty && 
            workDetails.every((work) => 
              work.isClosed || work.isTimeExpired || work.isFull
            );
          
          // 모두 마감됐으면 포함
          if (allClosed) {
            closedTOs.add(masterTO);
          }
        }
      }

      // 4. 최근 마감 순으로 정렬
      closedTOs.sort((a, b) {
        final aDate = a.closedAt ?? a.date;
        final bDate = b.closedAt ?? b.date;
        return bDate.compareTo(aDate);
      });
      final recentClosedTOs = closedTOs.take(5).toList();

      // ⭐ 로그 수정
      print('✅ 마감된 TO 조회: ${recentClosedTOs.length}개 (전체 ${closedTOs.length}개 중)');
      return recentClosedTOs;  // ⭐ 변경
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
      clearCache(toId: toId);

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
      clearCache(toId: toId);

      print('✅ TO 재오픈 완료: $toId');
      return true;
    } catch (e) {
      print('❌ TO 재오픈 실패: $e');
      return false;
    }
  }

  /// 그룹 TO 전체 마감 (WorkDetails 포함)
  Future<bool> closeGroupTOs(String groupId, String adminUID) async {
    try {
      print('🔒 [closeGroupTOs] 시작: $groupId');
      
      // 1. 그룹의 모든 TO 조회
      final snapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();

      if (snapshot.docs.isEmpty) {
        print('❌ 그룹 TO를 찾을 수 없음');
        return false;
      }

      final batch = _firestore.batch();
      
      // 2. 각 TO 마감
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isManualClosed': true,
          'closedAt': FieldValue.serverTimestamp(),
          'closedBy': adminUID,
        });
        
        print('   📝 TO 마감: ${doc.id}');
      }

      await batch.commit();
      print('✅ TO 마감 완료: ${snapshot.docs.length}개');

      // 3. ⭐ 각 TO의 모든 WorkDetails 마감
      for (var doc in snapshot.docs) {
        final workDetailsSnapshot = await _firestore
            .collection('tos')
            .doc(doc.id)
            .collection('workDetails')
            .get();

        if (workDetailsSnapshot.docs.isNotEmpty) {
          final workBatch = _firestore.batch();
          
          for (var workDoc in workDetailsSnapshot.docs) {
            workBatch.update(workDoc.reference, {
              'isManualClosed': true,
              'closedAt': FieldValue.serverTimestamp(),
              'closedBy': adminUID,
            });
          }
          
          await workBatch.commit();
          print('   ✅ WorkDetails 마감: ${workDetailsSnapshot.docs.length}개');
        }
        
        // 캐시 클리어
        clearCache(toId: doc.id);
      }

      print('✅ 그룹 전체 마감 완료: $groupId');
      return true;
    } catch (e) {
      print('❌ 그룹 마감 실패: $e');
      return false;
    }
  }

  /// 그룹 TO 전체 재오픈 (WorkDetails 포함)
  Future<bool> reopenGroupTOs(String groupId, String adminUID) async {
    try {
      print('🔓 [reopenGroupTOs] 시작: $groupId');
      
      // 1. 그룹의 모든 TO 조회
      final snapshot = await _firestore
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();

      if (snapshot.docs.isEmpty) {
        print('❌ 그룹 TO를 찾을 수 없음');
        return false;
      }

      final batch = _firestore.batch();
      
      // 2. 각 TO 재오픈
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isManualClosed': false,
          'reopenedAt': FieldValue.serverTimestamp(),
          'reopenedBy': adminUID,
        });
      }

      await batch.commit();
      print('✅ TO 재오픈 완료: ${snapshot.docs.length}개');

      // 3. ⭐ 각 TO의 모든 WorkDetails 재오픈
      for (var doc in snapshot.docs) {
        final workDetailsSnapshot = await _firestore
            .collection('tos')
            .doc(doc.id)
            .collection('workDetails')
            .get();

        if (workDetailsSnapshot.docs.isNotEmpty) {
          final workBatch = _firestore.batch();
          
          for (var workDoc in workDetailsSnapshot.docs) {
            workBatch.update(workDoc.reference, {
              'isManualClosed': false,
              // closedAt, closedBy 필드 삭제
              'closedAt': FieldValue.delete(),
              'closedBy': FieldValue.delete(),
            });
          }
          
          await workBatch.commit();
          print('   ✅ WorkDetails 재오픈: ${workDetailsSnapshot.docs.length}개');
        }
        
        // 캐시 클리어
        clearCache(toId: doc.id);
      }

      print('✅ 그룹 전체 재오픈 완료: $groupId');
      return true;
    } catch (e) {
      print('❌ 그룹 재오픈 실패: $e');
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
      
      print('✅ WorkDetail 통계 재계산 완료: $updatedCount개 업무');
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
      
      // 2. 각 TO의 통계 재계산 (병렬 처리)
      final results = await Future.wait(
        groupTOs.map((to) => recalculateTOStats(to.id))
      );
      final successCount = results.where((r) => r).length;
      
      print('✅ 그룹 통계 재계산 완료: $successCount/${groupTOs.length}개 성공');
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
  /// WorkDetail 마감시간 재계산
  Future<bool> recalculateWorkDetailDeadlines({
    required String toId,
    required DateTime workDate,
    required int hoursBeforeStart,
    bool resetClosedStatus = false,
  }) async {
    try {
      print('🔄 WorkDetail 마감시간 재계산 시작: $toId');
      
      // 1. 모든 WorkDetails 조회
      final workDetailsSnapshot = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();
      
      if (workDetailsSnapshot.docs.isEmpty) {
        print('⚠️ WorkDetails가 없습니다');
        return true;
      }
      
      // 2. Batch 업데이트
      final batch = _firestore.batch();
      
      for (var workDoc in workDetailsSnapshot.docs) {
        final workData = workDoc.data();
        final startTime = workData['startTime'] as String;
        
        // 🔥 각 업무 시작 N시간 전으로 마감시간 계산
        final timeParts = startTime.split(':');
        final workStartDateTime = DateTime(
          workDate.year,
          workDate.month,
          workDate.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
        final workDeadline = workStartDateTime.subtract(
          Duration(hours: hoursBeforeStart)
        );
        
        // 기본 업데이트
        final Map<String, dynamic> updates = {
          'applicationDeadline': Timestamp.fromDate(workDeadline),
        };
        
        if (resetClosedStatus) {
          updates['isManualClosed'] = false;
          updates['isEmergencyOpen'] = false;
        }
        
        batch.update(workDoc.reference, updates);
        
        // 🔥 FieldValue.delete()는 별도 처리
        if (resetClosedStatus) {
          batch.update(workDoc.reference, {
            'closedAt': FieldValue.delete(),
            'closedBy': FieldValue.delete(),
          });
        }
        
        print('   ✅ ${workData['workType']}: 마감시간 = ${DateFormat('MM/dd HH:mm').format(workDeadline)}');
      }
      
      await batch.commit();
      
      clearCache(toId: toId);
      print('✅ WorkDetail 마감시간 재계산 완료: ${workDetailsSnapshot.docs.length}개');
      return true;
    } catch (e) {
      print('❌ WorkDetail 마감시간 재계산 실패: $e');
      return false;
    }
  }
  /// 🔥 장기공고용: WorkDetails 마감 상태만 초기화 (마감시간 변경 없음)
  Future<bool> resetWorkDetailsClosedStatus(String toId) async {
    try {
      print('🔄 WorkDetails 마감 상태 초기화 시작: $toId');
      
      final workDetailsSnapshot = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();
      
      if (workDetailsSnapshot.docs.isEmpty) {
        print('⚠️ WorkDetails가 없습니다');
        return true;
      }
      
      final batch = _firestore.batch();
      
      for (var workDoc in workDetailsSnapshot.docs) {
        batch.update(workDoc.reference, {
          'isManualClosed': false,
          'isEmergencyOpen': false,
          'closedAt': FieldValue.delete(),
          'closedBy': FieldValue.delete(),
        });
      }
      
      await batch.commit();
      
      clearCache(toId: toId);
      print('✅ WorkDetails 마감 상태 초기화 완료: ${workDetailsSnapshot.docs.length}개');
      return true;
    } catch (e) {
      print('❌ WorkDetails 마감 상태 초기화 실패: $e');
      return false;
    }
  }

  /// 🔥 일회성: 기존 WorkDetails에 마감시간 추가
  Future<void> migrateWorkDetailDeadlines() async {
    try {
      print('🔄 WorkDetail 마감시간 마이그레이션 시작...');
      
      // 1. 모든 TO 조회
      final tosSnapshot = await _firestore.collection('tos').get();
      
      int totalUpdated = 0;
      
      for (var toDoc in tosSnapshot.docs) {
        final toData = toDoc.data();
        final toId = toDoc.id;
        final date = (toData['date'] as Timestamp).toDate();
        final deadlineType = toData['deadlineType'] ?? 'HOURS_BEFORE';
        final hoursBeforeStart = toData['hoursBeforeStart'] ?? 2;
        
        // 2. 이 TO의 WorkDetails 조회
        final workDetailsSnapshot = await _firestore
            .collection('tos')
            .doc(toId)
            .collection('workDetails')
            .get();
        
        final batch = _firestore.batch();
        
        for (var workDoc in workDetailsSnapshot.docs) {
          final workData = workDoc.data();
          
          // 이미 마감시간 있으면 스킵
          if (workData['applicationDeadline'] != null) continue;
          
          final startTime = workData['startTime'] as String;
          
          // 마감시간 계산
          DateTime workDeadline;
          
          if (deadlineType == 'HOURS_BEFORE') {
            final timeParts = startTime.split(':');
            final workStartDateTime = DateTime(
              date.year,
              date.month,
              date.day,
              int.parse(timeParts[0]),
              int.parse(timeParts[1]),
            );
            workDeadline = workStartDateTime.subtract(
              Duration(hours: hoursBeforeStart)
            );
          } else {
            // FIXED_TIME은 TO 마감시간 사용
            workDeadline = (toData['applicationDeadline'] as Timestamp).toDate();
          }
          
          // 배치 업데이트
          batch.update(workDoc.reference, {
            'applicationDeadline': Timestamp.fromDate(workDeadline),
          });
          
          totalUpdated++;
        }
        
        await batch.commit();
            }
      
      print('✅ 마이그레이션 완료: $totalUpdated개 WorkDetail 업데이트');
    } catch (e) {
      print('❌ 마이그레이션 실패: $e');
    }
  }
  // ═══════════════════════════════════════════════════════════
  // 🔥 Phase A: 퇴사 관리 시스템
  // ═══════════════════════════════════════════════════════════

  /// 퇴사 요청 (지원자용)
  Future<bool> requestResignation({
    required String applicationId,
    required DateTime resignDate,
  }) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'resignRequestedAt': Timestamp.fromDate(DateTime.now()),
        'resignRequestDate': Timestamp.fromDate(resignDate),
        'resignStatus': 'PENDING',
      });

      print('✅ 퇴사 요청 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 요청 실패: $e');
      return false;
    }
  }

  /// 퇴사 요청 취소 (지원자용)
  Future<bool> cancelResignRequest(String applicationId) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'resignRequestedAt': FieldValue.delete(),
        'resignRequestDate': FieldValue.delete(),
        'resignStatus': FieldValue.delete(),
      });

      print('✅ 퇴사 요청 취소 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 요청 취소 실패: $e');
      return false;
    }
  }

  /// 퇴사 승인 (관리자용)
  Future<bool> approveResignation({
    required String applicationId,
    required String adminUID,
  }) async {
    try {
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }

      final appData = appDoc.data() as Map<String, dynamic>;
      final resignDate = (appData['resignRequestDate'] as Timestamp).toDate();

      await _firestore.collection('applications').doc(applicationId).update({
        'resignStatus': 'APPROVED',
        'resignApprovedAt': Timestamp.fromDate(DateTime.now()),
        'resignApprovedBy': adminUID,
        'actualResignDate': Timestamp.fromDate(resignDate),
        'workEndDate': Timestamp.fromDate(resignDate), // 실제 종료일 업데이트
      });

      print('✅ 퇴사 승인 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 승인 실패: $e');
      return false;
    }
  }

  /// 퇴사 거절 (관리자용)
  Future<bool> rejectResignation({
    required String applicationId,
    required String adminUID,
    required String rejectReason,
  }) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'resignStatus': 'REJECTED',
        'resignApprovedAt': Timestamp.fromDate(DateTime.now()),
        'resignApprovedBy': adminUID,
        'resignRejectReason': rejectReason,
      });

      print('✅ 퇴사 거절 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 거절 실패: $e');
      return false;
    }
  }
  // ============================================================
  // 🔥 계약해지 관리 (관리자 → 근무자)
  // ============================================================

  /// 계약해지 요청 (관리자용)
  Future<bool> requestTermination({
    required String applicationId,
    required String reason,
    required String requestedByUid,
  }) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationRequestedAt': Timestamp.fromDate(DateTime.now()),
        'terminationReason': reason,
        'terminationRequestedByUid': requestedByUid,
        'terminationStatus': 'PENDING',
      });

      print('✅ 계약해지 요청 완료: $applicationId');
      
      // TODO: 근무자에게 알림 발송
      // await _sendTerminationNotification(applicationId);
      
      return true;
    } catch (e) {
      print('❌ 계약해지 요청 실패: $e');
      return false;
    }
  }

  /// 계약해지 요청 취소 (관리자용)
  Future<bool> cancelTerminationRequest(String applicationId) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationRequestedAt': FieldValue.delete(),
        'terminationReason': FieldValue.delete(),
        'terminationRequestedByUid': FieldValue.delete(),
        'terminationStatus': FieldValue.delete(),
        'terminationRespondedAt': FieldValue.delete(),
        'terminationRejectReason': FieldValue.delete(),
      });

      print('✅ 계약해지 요청 취소 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 계약해지 요청 취소 실패: $e');
      return false;
    }
  }

  /// 계약해지 승인 (근무자용)
  Future<bool> approveTermination(String applicationId) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationStatus': 'APPROVED',
        'terminationRespondedAt': Timestamp.fromDate(DateTime.now()),
        'resignStatus': 'APPROVED',  // 퇴사 상태도 함께 업데이트
        'actualResignDate': Timestamp.fromDate(DateTime.now()),
      });

      print('✅ 계약해지 승인 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 계약해지 승인 실패: $e');
      return false;
    }
  }

  /// 계약해지 거절 (근무자용)
  Future<bool> rejectTermination({
    required String applicationId,
    String? rejectReason,
  }) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationStatus': 'REJECTED',
        'terminationRespondedAt': Timestamp.fromDate(DateTime.now()),
        'terminationRejectReason': rejectReason,
      });

      print('✅ 계약해지 거절 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 계약해지 거절 실패: $e');
      return false;
    }
  }

  /// 계약해지 자동 승인 처리 (3일 경과 시)
  Future<bool> autoApproveTermination(String applicationId) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update({
        'terminationStatus': 'AUTO_APPROVED',
        'terminationRespondedAt': Timestamp.fromDate(DateTime.now()),
        'resignStatus': 'AUTO_APPROVED',
        'actualResignDate': Timestamp.fromDate(DateTime.now()),
      });

      print('✅ 계약해지 자동 승인 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 계약해지 자동 승인 실패: $e');
      return false;
    }
  }

  /// 계약해지 대기 중인 지원서 조회 (3일 경과 체크용)
  Future<List<ApplicationModel>> getPendingTerminations() async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('terminationStatus', isEqualTo: 'PENDING')
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 계약해지 대기 목록 조회 실패: $e');
      return [];
    }
  }

  /// 퇴사 자동 승인 처리 (Cloud Function에서 호출)
  Future<bool> autoApproveResignation(String applicationId) async {
    try {
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) return false;

      final appData = appDoc.data() as Map<String, dynamic>;
      
      // 이미 처리된 경우 스킵
      if (appData['resignStatus'] != 'PENDING') return false;

      final resignDate = (appData['resignRequestDate'] as Timestamp).toDate();

      await _firestore.collection('applications').doc(applicationId).update({
        'resignStatus': 'AUTO_APPROVED',
        'resignApprovedAt': Timestamp.fromDate(DateTime.now()),
        'resignApprovedBy': 'SYSTEM',
        'actualResignDate': Timestamp.fromDate(resignDate),
        'workEndDate': Timestamp.fromDate(resignDate),
      });

      print('✅ 퇴사 자동 승인 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 퇴사 자동 승인 실패: $e');
      return false;
    }
  }
  /// 퇴사 요청 목록 조회 (관리자용)
  Future<List<ApplicationModel>> getResignRequests(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .where('resignStatus', isEqualTo: 'PENDING')
          .get();

      final applications = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .where((app) => app.isLongTermApplication) // 장기 근무만
          .toList();

      print('✅ 퇴사 요청 ${applications.length}건 조회');
      return applications;
    } catch (e) {
      print('❌ 퇴사 요청 조회 실패: $e');
      return [];
    }
  }
  /// 장기 근무 지원자 조회 (사업장별)
  Future<List<ApplicationModel>> getLongTermApplicationsByBusiness(
    String businessId,
  ) async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .get();

      final applications = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .where((app) => app.isLongTermApplication)
          .toList();

      print('✅ 장기 근무 지원자 조회: ${applications.length}명');
      return applications;
    } catch (e) {
      print('❌ 장기 근무 지원자 조회 실패: $e');
      return [];
    }
  }
  /// 활성 TO 조회 (사업장별) - 캐싱 적용
  Future<List<TOModel>> getActiveTOsByBusinessId(String businessId) async {
    try {
      // 캐시 확인
      if (_activeTOsCache != null && _activeTOsCacheTime != null) {
        final cacheAge = DateTime.now().difference(_activeTOsCacheTime!);
        if (cacheAge < _cacheValidDuration) {
          print('✅ 활성 TO 캐시 사용');
          return _activeTOsCache!
              .where((to) => to.businessId == businessId)
              .toList();
        }
      }

      final snapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .get();

      final toList = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      // 캐시 저장
      _activeTOsCache = toList;
      _activeTOsCacheTime = DateTime.now();

      print('✅ 활성 TO 조회: ${toList.length}개');
      return toList;
    } catch (e) {
      print('❌ 활성 TO 조회 실패: $e');
      return [];
    }
  }

  /// 마감된 TO 조회 (사업장별) - 이미 있음, 사업장 필터 추가
  Future<List<TOModel>> getClosedTOsByBusinessId(String businessId) async {
    try {
      // 캐시 확인
      if (_closedTOsCache != null && _closedTOsCacheTime != null) {
        final cacheAge = DateTime.now().difference(_closedTOsCacheTime!);
        if (cacheAge < _cacheValidDuration) {
          print('✅ 마감 TO 캐시 사용');
          return _closedTOsCache!
              .where((to) => to.businessId == businessId)
              .toList();
        }
      }

      final snapshot = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('isManualClosed', isEqualTo: true)
          .get();

      final toList = snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();

      // 캐시 저장
      _closedTOsCache = toList;
      _closedTOsCacheTime = DateTime.now();

      print('✅ 마감 TO 조회: ${toList.length}개');
      return toList;
    } catch (e) {
      print('❌ 마감 TO 조회 실패: $e');
      return [];
    }
  }
  // ═══════════════════════════════════════════════════════════
  // 🕐 출근 관리 (Attendance Management)
  // ═══════════════════════════════════════════════════════════

  /// 출근 체크
  Future<String?> checkIn({
    required String applicationId,
    required String userId,
    required String businessId,
    required String businessName,
    required DateTime workDate,
    required String workType,
    required double latitude,
    required double longitude,
    String method = 'gps',
  }) async {
    try {
      print('🕐 [checkIn] 출근 체크 시작...');
      print('   applicationId: $applicationId');
      print('   workDate: $workDate');
      
      // 1. 오늘 이미 출근했는지 확인
      final todayStart = DateTime(workDate.year, workDate.month, workDate.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      
      final existing = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('workDate', isLessThan: Timestamp.fromDate(todayEnd))
          .where('applicationId', isEqualTo: applicationId)
          .limit(1)
          .get();
      
      if (existing.docs.isNotEmpty) {
        final existingData = existing.docs.first.data();
        if (existingData['checkIn'] != null) {
          print('⚠️ 이미 출근 완료');
          throw Exception('오늘 이미 출근하셨습니다.');
        }
      }
      
      // 2. 출근 시간
      final now = DateTime.now();
      final checkInTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      
      // 3. 출근 기록 생성
      final attendanceData = {
        'applicationId': applicationId,
        'userId': userId,
        'businessId': businessId,
        'businessName': businessName,
        'workDate': Timestamp.fromDate(workDate),
        'workType': workType,
        'checkIn': checkInTime,
        'checkInLat': latitude,
        'checkInLng': longitude,
        'checkInMethod': method,
        'checkInTime': FieldValue.serverTimestamp(),
        'status': 'present', // 기본값
        'isModified': false,
        'modifyRequested': false,
        'createdAt': FieldValue.serverTimestamp(),
      };
      
      final docRef = await _firestore.collection('attendance').add(attendanceData);
      
      print('✅ 출근 체크 완료: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ 출근 체크 실패: $e');
      rethrow;
    }
  }

  /// 퇴근 체크
  Future<bool> checkOut({
    required String attendanceId,
    required double latitude,
    required double longitude,
    String method = 'gps',
  }) async {
    try {
      print('🕐 [checkOut] 퇴근 체크 시작...');
      print('   attendanceId: $attendanceId');
      
      // 1. 출근 기록 조회
      final doc = await _firestore
          .collection('attendance')
          .doc(attendanceId)
          .get();
      
      if (!doc.exists) {
        throw Exception('출근 기록을 찾을 수 없습니다.');
      }
      
      final data = doc.data()!;
      if (data['checkOut'] != null) {
        throw Exception('이미 퇴근하셨습니다.');
      }
      
      // 2. 퇴근 시간
      final now = DateTime.now();
      final checkOutTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      
      // 3. 근무 시간 계산
      final checkInTime = data['checkIn'] as String;
      final workHours = _calculateWorkHours(checkInTime, checkOutTime);
      
      // 4. 퇴근 기록 저장
      await _firestore.collection('attendance').doc(attendanceId).update({
        'checkOut': checkOutTime,
        'checkOutLat': latitude,
        'checkOutLng': longitude,
        'checkOutMethod': method,
        'checkOutTime': FieldValue.serverTimestamp(),
        'workHours': workHours,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ 퇴근 체크 완료');
      return true;
    } catch (e) {
      print('❌ 퇴근 체크 실패: $e');
      rethrow;
    }
  }

  /// 근무 시간 계산 (시:분:초 → 시간)
  double _calculateWorkHours(String checkIn, String checkOut) {
    try {
      final inParts = checkIn.split(':');
      final outParts = checkOut.split(':');
      
      final inMinutes = int.parse(inParts[0]) * 60 + int.parse(inParts[1]);
      final outMinutes = int.parse(outParts[0]) * 60 + int.parse(outParts[1]);
      
      final diffMinutes = outMinutes - inMinutes;
      return diffMinutes / 60.0;
    } catch (e) {
      print('❌ 근무 시간 계산 실패: $e');
      return 0.0;
    }
  }

  /// 오늘 내 출근 기록 조회
  Future<AttendanceModel?> getTodayAttendance({
    required String userId,
    required String applicationId,
  }) async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      
      final snapshot = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .where('applicationId', isEqualTo: applicationId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('workDate', isLessThan: Timestamp.fromDate(todayEnd))
          .limit(1)
          .get();
      
      if (snapshot.docs.isEmpty) {
        return null;
      }
      
      return AttendanceModel.fromFirestore(snapshot.docs.first);
    } catch (e) {
      print('❌ 오늘 출근 기록 조회 실패: $e');
      return null;
    }
  }

  /// 사업장별 오늘 출근 현황 조회 (관리자용)
  Future<List<AttendanceModel>> getTodayAttendanceByBusiness({
    required String businessId,
  }) async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      
      print('🔍 [getTodayAttendanceByBusiness] 조회 시작...');
      print('   businessId: $businessId');
      print('   todayStart: $todayStart');
      
      final snapshot = await _firestore
          .collection('attendance')
          .where('businessId', isEqualTo: businessId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('workDate', isLessThan: Timestamp.fromDate(todayEnd))
          .orderBy('workDate', descending: false)
          .orderBy('checkInTime', descending: false)
          .get();
      
      final attendances = snapshot.docs
          .map((doc) => AttendanceModel.fromFirestore(doc))
          .toList();
      
      print('✅ 오늘 출근 현황: ${attendances.length}명');
      return attendances;
    } catch (e) {
      print('❌ 출근 현황 조회 실패: $e');
      return [];
    }
  }

  /// 오늘 확정된 근무자 목록 조회 (출근 대상자)
  Future<List<ApplicationModel>> getTodayConfirmedWorkers({
    required String businessId,
  }) async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      
      print('🔍 [getTodayConfirmedWorkers] 조회 시작...');
      
      // 1. 오늘 확정된 단기 근무
      final shortTermSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .where('workDate', isEqualTo: Timestamp.fromDate(todayStart))
          .get();
      
      final shortTerm = shortTermSnapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
      
      print('   단기 근무자: ${shortTerm.length}명');
      
      // 2. 오늘 근무하는 장기 근무자
      final longTermSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .where('type', isEqualTo: 'long_term')
          .get();
      
      final longTerm = longTermSnapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .where((app) {
            // 오늘이 근무일인지 확인
            if (app.workEndDate == null) return false;
            
            final isInRange = !todayStart.isBefore(app.workDate) && 
                             !todayStart.isAfter(app.workEndDate!);
            
            if (!isInRange) return false;
            
            // 근무 요일 확인
            if (app.workDays == null || app.workDays!.isEmpty) {
              return true; // 매일 근무
            }
            
            final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
            final todayWeekday = weekdays[today.weekday - 1];
            
            return app.workDays!.contains(todayWeekday);
          })
          .toList();
      
      print('   장기 근무자: ${longTerm.length}명');
      
      final allWorkers = [...shortTerm, ...longTerm];
      print('✅ 총 출근 대상: ${allWorkers.length}명');
      
      return allWorkers;
    } catch (e) {
      print('❌ 출근 대상자 조회 실패: $e');
      return [];
    }
  }

  /// 특정 날짜 출근 기록 조회
  Future<List<AttendanceModel>> getAttendanceByDate({
    required String businessId,
    required DateTime date,
  }) async {
    try {
      final dateStart = DateTime(date.year, date.month, date.day);
      final dateEnd = dateStart.add(const Duration(days: 1));
      
      final snapshot = await _firestore
          .collection('attendance')
          .where('businessId', isEqualTo: businessId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .where('workDate', isLessThan: Timestamp.fromDate(dateEnd))
          .get();
      
      return snapshot.docs
          .map((doc) => AttendanceModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 출근 기록 조회 실패: $e');
      return [];
    }
  }
  // ═══════════════════════════════════════════════════════════
  // 스케줄 변경 요청 관리 (Schedule Change Request Management)
  // ═══════════════════════════════════════════════════════════

  /// 스케줄 변경 요청 생성
  Future<String?> createScheduleChangeRequest(ScheduleChangeRequestModel request) async {
    try {
      final docRef = await _firestore.collection('schedule_change_requests').add(request.toMap());
      print('✅ 스케줄 변경 요청 생성 완료: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ 스케줄 변경 요청 생성 실패: $e');
      return null;
    }
  }

  /// 사업장의 대기중인 스케줄 변경 요청 조회
  Future<List<ScheduleChangeRequestModel>> getPendingScheduleChangeRequests(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('schedule_change_requests')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'PENDING')
          .orderBy('requestedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ScheduleChangeRequestModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 대기중인 스케줄 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 사업장의 모든 스케줄 변경 요청 조회
  Future<List<ScheduleChangeRequestModel>> getAllScheduleChangeRequests(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('schedule_change_requests')
          .where('businessId', isEqualTo: businessId)
          .orderBy('requestedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ScheduleChangeRequestModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 스케줄 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 지원자의 스케줄 변경 요청 조회
  Future<List<ScheduleChangeRequestModel>> getMyScheduleChangeRequests(String applicantUid) async {
    try {
      final snapshot = await _firestore
          .collection('schedule_change_requests')
          .where('applicantUid', isEqualTo: applicantUid)
          .orderBy('requestedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ScheduleChangeRequestModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 내 스케줄 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 스케줄 변경 요청 승인
  Future<bool> approveScheduleChangeRequest({
    required String requestId,
    required String approverUid,
  }) async {
    try {
      // 1. 요청 정보 조회
      final requestDoc = await _firestore
          .collection('schedule_change_requests')
          .doc(requestId)
          .get();

      if (!requestDoc.exists) {
        print('❌ 요청을 찾을 수 없음');
        return false;
      }

      final request = ScheduleChangeRequestModel.fromMap(requestDoc.data()!, requestId);

      // 2. 요청 상태 업데이트
      await _firestore.collection('schedule_change_requests').doc(requestId).update({
        'status': 'APPROVED',
        'respondedByUid': approverUid,
        'respondedAt': FieldValue.serverTimestamp(),
      });

      // 3. ApplicationModel의 leaveDates 또는 extraWorkDates 업데이트
      final appSnapshot = await _firestore
          .collection('applications')
          .doc(request.applicationId)
          .get();

      if (appSnapshot.exists) {
        final appData = appSnapshot.data()!;
        
        if (request.isLeaveRequest || request.isNoWorkRequest) {
          // 휴무/미출근 → leaveDates에 추가
          List<DateTime> leaveDates = [];
          if (appData['leaveDates'] != null) {
            leaveDates = (appData['leaveDates'] as List)
                .map((e) => (e as Timestamp).toDate())
                .toList();
          }
          
          if (!leaveDates.any((d) => 
              d.year == request.targetDate.year &&
              d.month == request.targetDate.month &&
              d.day == request.targetDate.day)) {
            leaveDates.add(request.targetDate);
          }

          await _firestore.collection('applications').doc(request.applicationId).update({
            'leaveDates': leaveDates.map((e) => Timestamp.fromDate(e)).toList(),
          });
        } else if (request.isExtraWorkRequest) {
          // 추가 근무 → extraWorkDates에 추가
          List<DateTime> extraWorkDates = [];
          if (appData['extraWorkDates'] != null) {
            extraWorkDates = (appData['extraWorkDates'] as List)
                .map((e) => (e as Timestamp).toDate())
                .toList();
          }
          
          if (!extraWorkDates.any((d) => 
              d.year == request.targetDate.year &&
              d.month == request.targetDate.month &&
              d.day == request.targetDate.day)) {
            extraWorkDates.add(request.targetDate);
          }

          await _firestore.collection('applications').doc(request.applicationId).update({
            'extraWorkDates': extraWorkDates.map((e) => Timestamp.fromDate(e)).toList(),
          });
        }
      }

      print('✅ 스케줄 변경 요청 승인 완료: $requestId');
      return true;
    } catch (e) {
      print('❌ 스케줄 변경 요청 승인 실패: $e');
      return false;
    }
  }

  /// 스케줄 변경 요청 거절
  Future<bool> rejectScheduleChangeRequest({
    required String requestId,
    required String rejectorUid,
    String? rejectReason,
  }) async {
    try {
      await _firestore.collection('schedule_change_requests').doc(requestId).update({
        'status': 'REJECTED',
        'respondedByUid': rejectorUid,
        'respondedAt': FieldValue.serverTimestamp(),
        'rejectReason': rejectReason,
      });

      print('✅ 스케줄 변경 요청 거절 완료: $requestId');
      return true;
    } catch (e) {
      print('❌ 스케줄 변경 요청 거절 실패: $e');
      return false;
    }
  }

  /// 스케줄 변경 요청 취소
  Future<bool> cancelScheduleChangeRequest({
    required String requestId,
    required String canceledByUid,
  }) async {
    try {
      // 1. 요청 정보 조회
      final requestDoc = await _firestore
          .collection('schedule_change_requests')
          .doc(requestId)
          .get();

      if (!requestDoc.exists) {
        print('❌ 요청을 찾을 수 없음');
        return false;
      }

      final request = ScheduleChangeRequestModel.fromMap(requestDoc.data()!, requestId);

      // 2. 승인된 요청이면 ApplicationModel에서도 제거
      if (request.isApproved) {
        final appSnapshot = await _firestore
            .collection('applications')
            .doc(request.applicationId)
            .get();

        if (appSnapshot.exists) {
          final appData = appSnapshot.data()!;
          
          if (request.isLeaveRequest || request.isNoWorkRequest) {
            // leaveDates에서 제거
            List<DateTime> leaveDates = [];
            if (appData['leaveDates'] != null) {
              leaveDates = (appData['leaveDates'] as List)
                  .map((e) => (e as Timestamp).toDate())
                  .toList();
            }
            
            leaveDates.removeWhere((d) => 
                d.year == request.targetDate.year &&
                d.month == request.targetDate.month &&
                d.day == request.targetDate.day);

            await _firestore.collection('applications').doc(request.applicationId).update({
              'leaveDates': leaveDates.map((e) => Timestamp.fromDate(e)).toList(),
            });
          } else if (request.isExtraWorkRequest) {
            // extraWorkDates에서 제거
            List<DateTime> extraWorkDates = [];
            if (appData['extraWorkDates'] != null) {
              extraWorkDates = (appData['extraWorkDates'] as List)
                  .map((e) => (e as Timestamp).toDate())
                  .toList();
            }
            
            extraWorkDates.removeWhere((d) => 
                d.year == request.targetDate.year &&
                d.month == request.targetDate.month &&
                d.day == request.targetDate.day);

            await _firestore.collection('applications').doc(request.applicationId).update({
              'extraWorkDates': extraWorkDates.map((e) => Timestamp.fromDate(e)).toList(),
            });
          }
        }
      }

      // 3. 요청 상태 업데이트
      await _firestore.collection('schedule_change_requests').doc(requestId).update({
        'status': 'CANCELED',
        'respondedByUid': canceledByUid,
        'respondedAt': FieldValue.serverTimestamp(),
      });

      print('✅ 스케줄 변경 요청 취소 완료: $requestId');
      return true;
    } catch (e) {
      print('❌ 스케줄 변경 요청 취소 실패: $e');
      return false;
    }
  }

  /// 대기중인 요청 개수 조회
  Future<int> getPendingScheduleChangeRequestCount(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('schedule_change_requests')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'PENDING')
          .get();

      return snapshot.docs.length;
    } catch (e) {
      print('❌ 대기중인 요청 개수 조회 실패: $e');
      return 0;
    }
  }
  /// 지원서 업데이트
  Future<bool> updateApplication(String applicationId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('applications').doc(applicationId).update(data);
      print('✅ 지원서 업데이트 완료: $applicationId');
      return true;
    } catch (e) {
      print('❌ 지원서 업데이트 실패: $e');
      return false;
    }
  }
  Future<void> updateUserDocument(String uid, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('users').doc(uid).update(data);
      
      // 캐시 무효화
      _userCache.remove(uid);
      _userCacheTimestamps.remove(uid);
      
      print('✅ 사용자 정보 업데이트 완료: $uid');
    } catch (e) {
      print('❌ 사용자 정보 업데이트 실패: $e');
      rethrow;
    }
  }
  // ═══════════════════════════════════════════════════════════
  // ✨ Lazy Loading 메서드 (성능 최적화)
  // ═══════════════════════════════════════════════════════════

  /// 1단계: 겉 카드용 TO 목록 로드 (최적화 - 추가 쿼리 없음!)
  Future<List<TOGroupItem>> getTOGroupItemsLight({
    bool activeOnly = true,
    bool closedOnly = false,
  }) async {
    try {
      print('🔍 [Lazy] 겉 카드용 TO 목록 로드 시작...');
      
      List<TOModel> masterTOs;
      if (closedOnly) {
        masterTOs = await getClosedTOs();
      } else if (activeOnly) {
        masterTOs = await getActiveTOs();
      } else {
        final active = await getActiveTOs();
        final closed = await getClosedTOs();
        masterTOs = [...active, ...closed];
      }
      
      List<TOGroupItem> groupItems = [];
      
      // ✨ 그룹 TO의 경우 전체 통계 계산을 위해 그룹별로 묶기
      Map<String, List<TOModel>> groupMap = {};
      List<TOModel> singleTOs = [];
      
      for (var to in masterTOs) {
        if (to.isGrouped && to.groupId != null) {
          // 그룹 마스터만 처리 (중복 방지)
          if (to.isGroupMaster) {
            groupMap[to.groupId!] = [to];  // ✨ 마스터 TO 임시 저장
          }
        } else {
          singleTOs.add(to);
        }
      }
      
      // ✨ 그룹 TO 처리 (마스터 통계 우선 사용, 없으면 Fallback)
      List<String> groupIdsNeedingFetch = [];  // 통계 없는 그룹만 조회
      
      for (var entry in groupMap.entries) {
        final groupId = entry.key;
        final masterTO = entry.value.first;  // 임시 저장된 마스터 TO
        
        // ✨ 마스터에 그룹 통계가 있으면 바로 사용 (추가 쿼리 없음!)
        if (masterTO.groupTotalRequired != null) {
          groupItems.add(TOGroupItem(
            masterTO: masterTO,
            groupTOs: [
              TOItem(
                to: masterTO,
                workDetails: null,
                confirmedCount: masterTO.groupTotalConfirmed ?? 0,
                pendingCount: masterTO.groupTotalPending ?? 0,
                totalRequired: masterTO.groupTotalRequired ?? 0,
                isWorkDetailLoaded: false,
              ),
            ],
            isGrouped: true,
            isGroupDetailLoaded: false,
          ));
          print('   ✅ [Lazy] 그룹 $groupId: 마스터 통계 사용');
        } else {
          // 통계 없으면 Fallback 목록에 추가
          groupIdsNeedingFetch.add(groupId);
        }
      }
      
      // ✨ Fallback: 통계 없는 그룹만 병렬 조회
      if (groupIdsNeedingFetch.isNotEmpty) {
        print('   ⚠️ [Lazy] ${groupIdsNeedingFetch.length}개 그룹 Fallback 조회...');
        
        final groupResults = await Future.wait(
          groupIdsNeedingFetch.map((groupId) => getTOsByGroup(groupId))
        );
        
        for (int i = 0; i < groupIdsNeedingFetch.length; i++) {
          final groupId = groupIdsNeedingFetch[i];
          final groupTOs = groupResults[i];
          
          if (groupTOs.isEmpty) continue;
          
          // 마스터 TO 찾기
          final masterTO = groupTOs.firstWhere(
            (to) => to.isGroupMaster,
            orElse: () => groupTOs.first,
          );
          
          // 그룹 전체 통계 합산
          int totalRequired = 0;
          int totalConfirmed = 0;
          int totalPending = 0;
          
          for (var to in groupTOs) {
            totalRequired += to.totalRequired;
            totalConfirmed += to.totalConfirmed;
            totalPending += to.totalPending;
          }
          
          groupItems.add(TOGroupItem(
            masterTO: masterTO,
            groupTOs: [
              TOItem(
                to: masterTO,
                workDetails: null,
                confirmedCount: totalConfirmed,
                pendingCount: totalPending,
                totalRequired: totalRequired,
                isWorkDetailLoaded: false,
              ),
            ],
            isGrouped: true,
            isGroupDetailLoaded: false,
          ));
          
          // ⚠️ Fallback 발생 시 마스터 통계 자동 업데이트 (백그라운드)
          _updateGroupMasterStats(groupId).catchError((e) {
            print('   ⚠️ 마스터 통계 자동 업데이트 실패: $e');
          });
        }
      }
      
      // 단일 TO 처리 (TO 문서의 값 직접 사용)
      for (var to in singleTOs) {
        groupItems.add(TOGroupItem(
          masterTO: to,
          groupTOs: [
            TOItem(
              to: to,
              workDetails: null,
              confirmedCount: to.totalConfirmed,
              pendingCount: to.totalPending,
              totalRequired: to.totalRequired,
              isWorkDetailLoaded: false,
            ),
          ],
          isGrouped: false,
          isGroupDetailLoaded: true,
        ));
      }
      
      print('✅ [Lazy] 겉 카드 로드 완료: ${groupItems.length}개');
      return groupItems;
    } catch (e) {
      print('❌ [Lazy] 겉 카드 로드 실패: $e');
      return [];
    }
  }

  /// 2단계: 그룹 펼칠 때 - 그룹 내 TO 목록 + 기본 통계 로드
  Future<List<TOItem>> loadGroupTOsLight(String groupId) async {
    try {
      print('🔍 [Lazy] 그룹 내 TO 목록 로드: $groupId');
      
      final groupTOs = await getTOsByGroup(groupId);
      final toIds = groupTOs.map((to) => to.id).toList();
      
      // ✨ 병렬로 WorkDetails 개수 + 지원자 통계 로드
      final results = await Future.wait([
        getWorkDetailsBatch(toIds),
        getApplicationsByTOs(groupTOs),  // ✅ TO 정보 전달 - 중복 조회 제거
      ]);
      
      final workDetailsMap = results[0] as Map<String, List<WorkDetailModel>>;
      final applicationsMap = results[1] as Map<String, List<ApplicationModel>>;
      
      List<TOItem> toItems = [];
      for (var to in groupTOs) {
        final workDetails = workDetailsMap[to.id] ?? [];
        final apps = applicationsMap[to.id] ?? [];
        
        // 통계 계산
        int totalRequired = 0;
        for (var work in workDetails) {
          totalRequired += work.requiredCount;
        }
        
        int confirmed = apps.where((a) => a.status == 'CONFIRMED').length;
        int pending = apps.where((a) => a.status == 'PENDING').length;
        
        toItems.add(TOItem(
          to: to,
          workDetails: null,  // 업무별 상세는 펼칠 때 로드
          confirmedCount: confirmed,
          pendingCount: pending,
          totalRequired: totalRequired,
          isWorkDetailLoaded: false,
        ));
      }
      
      print('✅ [Lazy] 그룹 TO 로드 완료: ${toItems.length}개 (통계 포함)');
      return toItems;
    } catch (e) {
      print('❌ [Lazy] 그룹 TO 로드 실패: $e');
      return [];
    }
  }

  /// 3단계: TO 펼칠 때 - WorkDetails + 지원자 통계 로드
  Future<Map<String, dynamic>> loadTOWorkDetails(TOModel to) async {
    try {
      print('🔍 [Lazy] TO 상세 로드: ${to.id}');
      print('   📋 TO 정보: businessId=${to.businessId}, title=${to.title}, date=${to.date}');
      print('   📋 장기여부: ${to.isLongTerm}');
      
      // 병렬로 WorkDetails와 지원자 조회
      final results = await Future.wait([
        getWorkDetails(to.id, forceRefresh: true),
        getApplicationsByTO(to.businessId, to.title, to.date),
      ]);
      
      final workDetails = results[0] as List<WorkDetailModel>;
      final apps = results[1] as List<ApplicationModel>;
      
      print('   📋 WorkDetails: ${workDetails.length}개');
      print('   📋 Applications: ${apps.length}개');
      for (var app in apps) {
        print('      - ${app.selectedWorkType}: ${app.status} (workDate: ${app.workDate})');
      }
      
      // 업무별 통계 계산
      Map<String, Map<String, int>> workStats = {};
      for (var work in workDetails) {
        final workApps = apps.where((a) => a.selectedWorkType == work.workType);
        workStats[work.workType] = {
          'confirmed': workApps.where((a) => a.status == 'CONFIRMED').length,
          'pending': workApps.where((a) => a.status == 'PENDING').length,
        };
        print('   📊 ${work.workType}: 확정=${workStats[work.workType]!['confirmed']}, 대기=${workStats[work.workType]!['pending']}');
      }
      
      // 시간 범위 설정
      if (workDetails.isNotEmpty) {
        String? minStart;
        String? maxEnd;
        
        for (var work in workDetails) {
          if (minStart == null || work.startTime.compareTo(minStart) < 0) {
            minStart = work.startTime;
          }
          if (maxEnd == null || work.endTime.compareTo(maxEnd) > 0) {
            maxEnd = work.endTime;
          }
        }
        
        if (minStart != null && maxEnd != null) {
          to.setTimeRange(minStart, maxEnd);
        }
      }
      
      print('✅ [Lazy] TO 상세 로드 완료: WorkDetails ${workDetails.length}개');
      
      return {
        'workDetails': workDetails,
        'workStats': workStats,
      };
    } catch (e) {
      print('❌ [Lazy] TO 상세 로드 실패: $e');
      return {
        'workDetails': <WorkDetailModel>[],
        'workStats': <String, Map<String, int>>{},
      };
    }
  }
  /// ✅ TO의 totalRequired + 급여 정보 재계산
  Future<void> _recalculateTOWorkInfo(String toId) async {
    try {
      final workDetails = await getWorkDetails(toId, forceRefresh: true);
      
      if (workDetails.isEmpty) {
        await _firestore.collection('tos').doc(toId).update({
          'totalRequired': 0,
          'minWage': null,
          'maxWage': null,
          'wageType': null,
          'workDetailCount': 0,
        });
        print('📊 TO 정보 초기화 (업무 없음)');
        return;
      }
      
      // 인원 계산
      int totalRequired = 0;
      for (var work in workDetails) {
        totalRequired += work.requiredCount;
      }
      
      // 급여 계산
      final wages = workDetails.map((w) => w.wage).toList();
      final minWage = wages.reduce((a, b) => a < b ? a : b);
      final maxWage = wages.reduce((a, b) => a > b ? a : b);
      final wageType = workDetails.first.wageType;
      final workDetailCount = workDetails.length;
      
      await _firestore.collection('tos').doc(toId).update({
        'totalRequired': totalRequired,
        'minWage': minWage,
        'maxWage': maxWage,
        'wageType': wageType,
        'workDetailCount': workDetailCount,
      });
      
      print('📊 TO 정보 업데이트: 인원=$totalRequired, 급여=$minWage~$maxWage ($wageType), 업무=$workDetailCount개');
    } catch (e) {
      print('❌ TO 정보 업데이트 실패: $e');
    }
  }
  
  /// 기존 함수명 호환용 (deprecated)
  Future<void> _recalculateTotalRequired(String toId) async {
    await _recalculateTOWorkInfo(toId);
  }
  // ═══════════════════════════════════════════════════════════
  // ✨ 그룹 마스터 통계 동기화 (Group Master Stats Sync)
  // ═══════════════════════════════════════════════════════════

  /// 그룹 마스터 TO의 통계 업데이트
  /// - 그룹 내 모든 TO의 통계를 합산하여 마스터에 저장
  /// - 지원 확정/거절/취소, TO 생성/삭제 시 호출
  Future<bool> _updateGroupMasterStats(String groupId) async {
    try {
      print('📊 [Sync] 그룹 마스터 통계 업데이트: $groupId');
      
      // 1. 그룹의 모든 TO 조회
      final groupTOs = await getTOsByGroup(groupId);
      if (groupTOs.isEmpty) {
        print('   ⚠️ 그룹 TO가 없습니다');
        return false;
      }
      
      // 2. 마스터 TO 찾기
      final masterTO = groupTOs.firstWhere(
        (to) => to.isGroupMaster,
        orElse: () => groupTOs.first,
      );
      
      // 3. 그룹 전체 통계 합산
      int groupTotalRequired = 0;
      int groupTotalConfirmed = 0;
      int groupTotalPending = 0;
      
      // ✅ 그룹 전체 급여 정보 (최대/최소)
      int? groupMinWage;
      int? groupMaxWage;
      
      for (var to in groupTOs) {
        groupTotalRequired += to.totalRequired;
        groupTotalConfirmed += to.totalConfirmed;
        groupTotalPending += to.totalPending;
        
        // 급여 정보 비교
        if (to.minWage != null) {
          if (groupMinWage == null || to.minWage! < groupMinWage) {
            groupMinWage = to.minWage;
          }
        }
        if (to.maxWage != null) {
          if (groupMaxWage == null || to.maxWage! > groupMaxWage) {
            groupMaxWage = to.maxWage;
          }
        }
      }
      
      // 4. 마스터 TO 업데이트
      await _firestore.collection('tos').doc(masterTO.id).update({
        'groupTotalRequired': groupTotalRequired,
        'groupTotalConfirmed': groupTotalConfirmed,
        'groupTotalPending': groupTotalPending,
        // ✅ 그룹 전체 급여 정보
        'minWage': groupMinWage,
        'maxWage': groupMaxWage,
        // ✅ 그룹 실제 날짜 개수
        'groupActualDaysCount': groupTOs.length,
        'groupStatsUpdatedAt': FieldValue.serverTimestamp(),
      });
      
      print('   ✅ 마스터 통계 업데이트 완료: 필요 $groupTotalRequired, 확정 $groupTotalConfirmed, 대기 $groupTotalPending');
      return true;
    } catch (e) {
      print('❌ [Sync] 그룹 마스터 통계 업데이트 실패: $e');
      return false;
    }
  }

  /// 공개 메서드: TO의 그룹 마스터 통계 동기화
  /// - toId로 해당 TO의 groupId를 찾아서 마스터 통계 업데이트
  Future<bool> syncGroupMasterStats(String toId) async {
    try {
      final to = await getTO(toId);
      if (to == null) return false;
      
      // 그룹 TO가 아니면 스킵
      if (to.groupId == null) {
        print('   ℹ️ 단일 TO - 그룹 동기화 스킵');
        return true;
      }
      
      return await _updateGroupMasterStats(to.groupId!);
    } catch (e) {
      print('❌ syncGroupMasterStats 실패: $e');
      return false;
    }
  }

  /// 그룹 마스터 통계 전체 재계산 (마이그레이션/수동 보정용)
  Future<int> migrateAllGroupMasterStats() async {
    try {
      print('🔄 [Migration] 전체 그룹 마스터 통계 마이그레이션 시작...');
      
      // 모든 그룹 마스터 TO 조회
      final snapshot = await _firestore
          .collection('tos')
          .where('isGroupMaster', isEqualTo: true)
          .get();
      
      int successCount = 0;
      final groupIds = <String>{};
      
      for (var doc in snapshot.docs) {
        final groupId = doc.data()['groupId'] as String?;
        if (groupId != null && !groupIds.contains(groupId)) {
          groupIds.add(groupId);
          final success = await _updateGroupMasterStats(groupId);
          if (success) successCount++;
        }
      }
      
      print('✅ [Migration] 완료: $successCount/${groupIds.length}개 그룹');
      return successCount;
    } catch (e) {
      print('❌ [Migration] 실패: $e');
      return 0;
    }
  }
  // ═══════════════════════════════════════════════════════════════════════════
  // 📝 FirestoreService 추가 메서드 (리뷰, 신분증 열람, 알림)
  // 이 내용을 lib/services/firestore_service.dart에 추가하세요
  // ═══════════════════════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════
  // 리뷰 관리 (Review Management)
  // ═══════════════════════════════════════════════════════════

  /// 리뷰 작성
  Future<String?> createReview({
    required String applicationId,
    required String reviewerId,
    required String reviewerName,
    required String targetUserId,
    required String businessId,
    required String businessName,
    required String workType,
    required DateTime workDate,
    required int rating,
    String? comment,
    bool wouldRehire = true,
  }) async {
    try {
      print('📝 [createReview] 리뷰 작성 시작');
      
      // 1. 리뷰 생성
      final docRef = await _firestore.collection('reviews').add({
        'applicationId': applicationId,
        'reviewerId': reviewerId,
        'reviewerName': reviewerName,
        'targetUserId': targetUserId,
        'businessId': businessId,
        'businessName': businessName,
        'workType': workType,
        'workDate': Timestamp.fromDate(workDate),
        'rating': rating,
        'comment': comment,
        'wouldRehire': wouldRehire,
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // 2. 사용자 통계 업데이트 (평균 평점, 리뷰 수)
      await _updateUserReviewStats(targetUserId);
      
      // 3. 지원서에 리뷰 작성 표시
      await _firestore.collection('applications').doc(applicationId).update({
        'hasReview': true,
        'reviewId': docRef.id,
      });
      
      // 4. 알림 생성
      await createNotification(
        NotificationModel.createReviewReceived(
          userId: targetUserId,
          businessName: businessName,
          rating: rating,
          reviewId: docRef.id,
        ),
      );
      
      print('✅ [createReview] 리뷰 작성 완료: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ [createReview] 실패: $e');
      return null;
    }
  }

  /// 사용자 리뷰 통계 업데이트
  Future<void> _updateUserReviewStats(String userId) async {
    try {
      final reviews = await _firestore
          .collection('reviews')
          .where('targetUserId', isEqualTo: userId)
          .get();
      
      if (reviews.docs.isEmpty) return;
      
      double totalRating = 0;
      for (var doc in reviews.docs) {
        totalRating += (doc.data()['rating'] ?? 0) as int;
      }
      
      final avgRating = totalRating / reviews.docs.length;
      
      await _firestore.collection('users').doc(userId).update({
        'averageRating': avgRating,
        'reviewCount': reviews.docs.length,
      });
      
      print('✅ 사용자 리뷰 통계 업데이트: avg=$avgRating, count=${reviews.docs.length}');
    } catch (e) {
      print('⚠️ 사용자 리뷰 통계 업데이트 실패: $e');
    }
  }

  /// 사용자가 받은 리뷰 목록 조회
  Future<List<ReviewModel>> getUserReviews(String userId, {int limit = 10}) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('targetUserId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit)
          .get();
      
      return snapshot.docs
          .map((doc) => ReviewModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 사용자 리뷰 조회 실패: $e');
      return [];
    }
  }

  /// 특정 지원서의 리뷰 조회
  Future<ReviewModel?> getReviewByApplicationId(String applicationId) async {
    try {
      final snapshot = await _firestore
          .collection('reviews')
          .where('applicationId', isEqualTo: applicationId)
          .limit(1)
          .get();
      
      if (snapshot.docs.isEmpty) return null;
      return ReviewModel.fromFirestore(snapshot.docs.first);
    } catch (e) {
      print('❌ 리뷰 조회 실패: $e');
      return null;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 우리 사업장 근무 이력 (Business Work History)
  // ═══════════════════════════════════════════════════════════

  /// 특정 사용자의 우리 사업장 근무 이력 조회
  Future<Map<String, dynamic>> getBusinessWorkHistory({
    required String userId,
    required String businessId,
  }) async {
    try {
      print('🔍 [getBusinessWorkHistory] 조회: userId=$userId, businessId=$businessId');
      
      // 1. 확정된 지원서 조회
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: userId)
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .orderBy('workDate', descending: true)
          .get();
      
      if (snapshot.docs.isEmpty) {
        return {
          'workCount': 0,
          'lastWorkDate': null,
          'lastWorkType': null,
          'averageRating': null,
          'reviews': <ReviewModel>[],
        };
      }
      
      final applications = snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
      
      // 2. 이 사업장에서 받은 리뷰 조회
      final reviewSnapshot = await _firestore
          .collection('reviews')
          .where('targetUserId', isEqualTo: userId)
          .where('businessId', isEqualTo: businessId)
          .orderBy('createdAt', descending: true)
          .limit(5)
          .get();
      
      final reviews = reviewSnapshot.docs
          .map((doc) => ReviewModel.fromFirestore(doc))
          .toList();
      
      // 3. 이 사업장에서의 평균 평점 계산
      double? avgRating;
      if (reviews.isNotEmpty) {
        double total = 0;
        for (var review in reviews) {
          total += review.rating;
        }
        avgRating = total / reviews.length;
      }
      
      // 4. 가장 최근 근무 정보
      final lastApp = applications.first;
      
      print('✅ [getBusinessWorkHistory] 조회 완료: ${applications.length}회 근무');
      
      return {
        'workCount': applications.length,
        'lastWorkDate': lastApp.workDate,
        'lastWorkType': lastApp.selectedWorkType,
        'averageRating': avgRating,
        'reviews': reviews,
        'applications': applications,
      };
    } catch (e) {
      print('❌ [getBusinessWorkHistory] 실패: $e');
      return {
        'workCount': 0,
        'lastWorkDate': null,
        'lastWorkType': null,
        'averageRating': null,
        'reviews': <ReviewModel>[],
      };
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 신분증 열람 요청 (ID Card Access Request)
  // ═══════════════════════════════════════════════════════════

  /// 신분증 열람 요청 생성
  Future<String?> createIdCardAccessRequest({
    required String requesterId,
    required String requesterName,
    required String requesterBusinessId,
    required String requesterBusinessName,
    required String targetUserId,
    required String targetUserName,
    required IdCardAccessReason reason,
    String? customReason,
    String? applicationId,
  }) async {
    try {
      print('📄 [createIdCardAccessRequest] 요청 생성');
      
      // 1. 이미 대기 중인 요청이 있는지 확인
      final existingPending = await _firestore
          .collection('idCardAccessRequests')
          .where('requesterId', isEqualTo: requesterId)
          .where('targetUserId', isEqualTo: targetUserId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      
      if (existingPending.docs.isNotEmpty) {
        print('⚠️ 이미 대기 중인 요청이 있습니다');
        ToastHelper.showWarning('이미 요청 중입니다. 응답을 기다려주세요.');
        return null;
      }
      
      // 2. 유효한 승인이 있는지 확인
      final existingApproved = await _firestore
          .collection('idCardAccessRequests')
          .where('requesterId', isEqualTo: requesterId)
          .where('targetUserId', isEqualTo: targetUserId)
          .where('status', isEqualTo: 'approved')
          .get();
      
      for (var doc in existingApproved.docs) {
        final expiresAt = (doc.data()['expiresAt'] as Timestamp?)?.toDate();
        if (expiresAt != null && DateTime.now().isBefore(expiresAt)) {
          print('⚠️ 이미 유효한 열람 권한이 있습니다');
          ToastHelper.showInfo('이미 열람 권한이 있습니다.');
          return doc.id;
        }
      }
      
      // 3. 요청 생성
      final docRef = await _firestore.collection('idCardAccessRequests').add({
        'requesterId': requesterId,
        'requesterName': requesterName,
        'requesterBusinessId': requesterBusinessId,
        'requesterBusinessName': requesterBusinessName,
        'targetUserId': targetUserId,
        'targetUserName': targetUserName,
        'reason': _reasonToString(reason),
        'customReason': customReason,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
        'applicationId': applicationId,
      });
      
      // 4. 알림 생성 (지원자에게)
      final reasonText = reason == IdCardAccessReason.other 
          ? (customReason ?? '기타') 
          : _getReasonText(reason);
      
      await createNotification(
        NotificationModel.createIdCardAccessRequest(
          userId: targetUserId,
          businessName: requesterBusinessName,
          reason: reasonText,
          requestId: docRef.id,
        ),
      );
      
      print('✅ [createIdCardAccessRequest] 요청 생성 완료: ${docRef.id}');
      ToastHelper.showSuccess('신분증 열람 요청을 보냈습니다');
      return docRef.id;
    } catch (e) {
      print('❌ [createIdCardAccessRequest] 실패: $e');
      ToastHelper.showError('요청 실패');
      return null;
    }
  }

  /// 신분증 열람 요청 승인
  Future<bool> approveIdCardAccessRequest(String requestId) async {
    try {
      print('✅ [approveIdCardAccessRequest] 승인: $requestId');
      
      final docRef = _firestore.collection('idCardAccessRequests').doc(requestId);
      final doc = await docRef.get();
      
      if (!doc.exists) {
        print('❌ 요청을 찾을 수 없습니다');
        return false;
      }
      
      final data = doc.data()!;
      final expiresAt = DateTime.now().add(const Duration(days: 7));
      
      // 1. 요청 상태 업데이트
      await docRef.update({
        'status': 'approved',
        'respondedAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAt),
      });
      
      // 2. 알림 생성 (관리자에게)
      await createNotification(
        NotificationModel.createIdCardAccessApproved(
          userId: data['requesterId'],
          targetUserName: data['targetUserName'],
          requestId: requestId,
        ),
      );
      
      print('✅ [approveIdCardAccessRequest] 승인 완료');
      return true;
    } catch (e) {
      print('❌ [approveIdCardAccessRequest] 실패: $e');
      return false;
    }
  }

  /// 신분증 열람 요청 거절
  Future<bool> rejectIdCardAccessRequest(String requestId, {String? reason}) async {
    try {
      print('❌ [rejectIdCardAccessRequest] 거절: $requestId');
      
      final docRef = _firestore.collection('idCardAccessRequests').doc(requestId);
      final doc = await docRef.get();
      
      if (!doc.exists) {
        print('❌ 요청을 찾을 수 없습니다');
        return false;
      }
      
      final data = doc.data()!;
      
      // 1. 요청 상태 업데이트
      await docRef.update({
        'status': 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
        'rejectionReason': reason,
      });
      
      // 2. 알림 생성 (관리자에게)
      await createNotification(
        NotificationModel.createIdCardAccessRejected(
          userId: data['requesterId'],
          targetUserName: data['targetUserName'],
          requestId: requestId,
          rejectionReason: reason,
        ),
      );
      
      print('✅ [rejectIdCardAccessRequest] 거절 완료');
      return true;
    } catch (e) {
      print('❌ [rejectIdCardAccessRequest] 실패: $e');
      return false;
    }
  }

  /// 신분증 열람 권한 확인 (pending, approved 모두 조회)
  Future<IdCardAccessRequestModel?> checkIdCardAccess({
    required String requesterId,
    required String targetUserId,
  }) async {
    try {
      // ✅ pending 또는 approved 상태 조회 (최신순)
      final snapshot = await _firestore
          .collection('idCardAccessRequests')
          .where('requesterId', isEqualTo: requesterId)
          .where('targetUserId', isEqualTo: targetUserId)
          .where('status', whereIn: ['pending', 'approved'])
          .orderBy('requestedAt', descending: true)
          .limit(1)
          .get(const GetOptions(source: Source.server));
      
      if (snapshot.docs.isEmpty) return null;
      
      final request = IdCardAccessRequestModel.fromFirestore(snapshot.docs.first);
      
      // 승인된 경우 만료 확인
      if (request.status == IdCardAccessStatus.approved && request.isExpired) {
        // 만료 상태로 업데이트
        await _firestore
            .collection('idCardAccessRequests')
            .doc(request.id)
            .update({'status': 'expired'});
        return null;
      }
      
      return request;
    } catch (e) {
      print('❌ 열람 권한 확인 실패: $e');
      return null;
    }
  }

  /// 대기 중인 신분증 열람 요청 조회 (지원자용)
  Future<List<IdCardAccessRequestModel>> getPendingIdCardRequests(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('idCardAccessRequests')
          .where('targetUserId', isEqualTo: userId)
          .where('status', isEqualTo: 'pending')
          .orderBy('requestedAt', descending: true)
          .get();
      
      return snapshot.docs
          .map((doc) => IdCardAccessRequestModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 대기 요청 조회 실패: $e');
      return [];
    }
  }

  /// 내가 보낸 신분증 열람 요청 조회 (관리자용)
  Future<List<IdCardAccessRequestModel>> getMyIdCardRequests(String requesterId) async {
    try {
      final snapshot = await _firestore
          .collection('idCardAccessRequests')
          .where('requesterId', isEqualTo: requesterId)
          .orderBy('requestedAt', descending: true)
          .limit(50)
          .get();
      
      return snapshot.docs
          .map((doc) => IdCardAccessRequestModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 내 요청 조회 실패: $e');
      return [];
    }
  }

  // Helper methods for IdCardAccessReason
  String _reasonToString(IdCardAccessReason reason) {
    switch (reason) {
      case IdCardAccessReason.incomeTax: return 'incomeTax';
      case IdCardAccessReason.laborContract: return 'laborContract';
      case IdCardAccessReason.insurance: return 'insurance';
      case IdCardAccessReason.identityVerify: return 'identityVerify';
      case IdCardAccessReason.other: return 'other';
    }
  }

  String _getReasonText(IdCardAccessReason reason) {
    switch (reason) {
      case IdCardAccessReason.incomeTax: return '소득세 신고';
      case IdCardAccessReason.laborContract: return '근로계약서 작성';
      case IdCardAccessReason.insurance: return '4대보험 신고';
      case IdCardAccessReason.identityVerify: return '본인 확인';
      case IdCardAccessReason.other: return '기타';
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 알림 관리 (Notification Management)
  // ═══════════════════════════════════════════════════════════

  /// 알림 생성
  Future<String?> createNotification(NotificationModel notification) async {
    try {
      final docRef = await _firestore.collection('notifications').add(
        notification.toMap(),
      );
      print('✅ 알림 생성: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ 알림 생성 실패: $e');
      return null;
    }
  }

  /// 사용자 알림 목록 조회
  Future<List<NotificationModel>> getUserNotifications(
    String userId, {
    int limit = 50,
    bool unreadOnly = false,
  }) async {
    try {
      Query query = _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .orderBy('createdAt', descending: true)
          .limit(limit);
      
      if (unreadOnly) {
        query = query.where('isRead', isEqualTo: false);
      }
      
      final snapshot = await query.get();
      
      return snapshot.docs
          .map((doc) => NotificationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      print('❌ 알림 조회 실패: $e');
      return [];
    }
  }

  /// 읽지 않은 알림 개수
  Future<int> getUnreadNotificationCount(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .count()
          .get();
      
      return snapshot.count ?? 0;
    } catch (e) {
      print('❌ 읽지 않은 알림 개수 조회 실패: $e');
      return 0;
    }
  }

  /// 알림 읽음 처리
  Future<bool> markNotificationAsRead(String notificationId) async {
    try {
      await _firestore.collection('notifications').doc(notificationId).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      print('❌ 알림 읽음 처리 실패: $e');
      return false;
    }
  }

  /// 모든 알림 읽음 처리
  Future<bool> markAllNotificationsAsRead(String userId) async {
    try {
      final batch = _firestore.batch();
      
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('isRead', isEqualTo: false)
          .get();
      
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      
      await batch.commit();
      print('✅ ${snapshot.docs.length}개 알림 읽음 처리');
      return true;
    } catch (e) {
      print('❌ 전체 읽음 처리 실패: $e');
      return false;
    }
  }

  /// 오래된 알림 삭제 (30일 이상)
  Future<int> deleteOldNotifications(String userId) async {
    try {
      final cutoffDate = DateTime.now().subtract(const Duration(days: 30));
      
      final snapshot = await _firestore
          .collection('notifications')
          .where('userId', isEqualTo: userId)
          .where('createdAt', isLessThan: Timestamp.fromDate(cutoffDate))
          .get();
      
      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      
      await batch.commit();
      print('✅ ${snapshot.docs.length}개 오래된 알림 삭제');
      return snapshot.docs.length;
    } catch (e) {
      print('❌ 오래된 알림 삭제 실패: $e');
      return 0;
    }
  }

  /// 알림 스트림 (실시간)
  Stream<List<NotificationModel>> watchUserNotifications(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => NotificationModel.fromFirestore(doc))
            .toList());
  }

  /// 읽지 않은 알림 개수 스트림 (실시간)
  Stream<int> watchUnreadNotificationCount(String userId) {
    return _firestore
        .collection('notifications')
        .where('userId', isEqualTo: userId)
        .where('isRead', isEqualTo: false)
        .snapshots()
        .map((snapshot) => snapshot.docs.length);
  }
  
}