part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// TO 관리 - 기본 CRUD 및 조회 (TO Basic Operations)
// ═══════════════════════════════════════════════════════════

extension TOFirestore on FirestoreService {

  // ═══════════════════════════════════════════════════════════
  // TO 기본 CRUD
  // ═══════════════════════════════════════════════════════════

  /// 단일 TO 조회
  Future<TOModel?> getTO(String toId) async {
    try {
      final doc = await db.collection('tos').doc(toId).get();
      
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
      await db.collection('tos').doc(toId).update(updates);
      clearCache(toId: toId);
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
      final workDetailsSnapshot = await db
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();
      
      for (var doc in workDetailsSnapshot.docs) {
        await doc.reference.delete();
      }
      
      // 2. Applications 삭제
      final applicationsSnapshot = await db
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
          await db.collection('tos').doc(nextTO.id).update({
            'isGroupMaster': true,
          });
          
          // 날짜 범위 재계산
          await updateGroupDateRange(toDoc.groupId!);
        }
      }
      
      // 4. TO 문서 삭제
      await db.collection('tos').doc(toId).delete();

      clearCache(toId: toId);

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
  // TO 조회 - 다양한 조건별
  // ═══════════════════════════════════════════════════════════

  /// 모든 TO 조회 (지원자용, 최고관리자용)
  Future<List<TOModel>> getAllTOs() async {
    try {
      // ✅ 서버에서 바로 필터링 (오늘 이후만)
      final today = DateTime.now();
      final startOfToday = DateTime(today.year, today.month, today.day);

      final snapshot = await db
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

      final snapshot = await db
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

      final snapshot = await db
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

      final snapshot = await db
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
  // TO 생성
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
        'totalPending': 0,
        'totalApplications': 0,
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
        'isPublished': shouldPublishImmediately,
        'publishDaysBefore': publishDaysBefore,
        'publishTime': publishTime,
        // ✅ Phase 4: 상태 필드
        'status': 'ACTIVE',
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      };

      // 3. TO 문서 생성
      final toDoc = await db.collection('tos').add(toData);
      print('✅ TO 문서 생성 완료: ${toDoc.id}');

      // 4. WorkDetails 하위 컬렉션에 업무 추가
      final batch = db.batch();
      
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
            // 🔥 UTC → 로컬 변환 후 날짜 추출
            final localDate = date.toLocal();
            final workStartDateTime = DateTime(
              localDate.year,
              localDate.month,
              localDate.day,
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

      // ✅ 그룹 TO면 마스터 통계 동기화
      if (groupId != null) {
        await updateGroupMasterStats(groupId);
      }

      return toDoc.id;
    } catch (e) {
      print('❌ [FirestoreService] TO 생성 실패: $e');
      return null;
    }
  }

  /// ApplicationModel에서 TO 찾기
  Future<TOModel?> getTOByApplication(ApplicationModel app) async {
    try {
      final snapshot = await db
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