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
  // ═══════════════════════════════════════════════════════════
  // TO 목록 조회 (Active/Closed)
  // ═══════════════════════════════════════════════════════════

  /// 진행중인 TO 목록 조회 (대표 TO + 단일 TO)
  Future<List<TOModel>> getActiveTOs({
    bool publishedOnly = false,
    bool forceRefresh = false,
  }) async {
    try {
      // ✅ Phase 3: 캐시 체크
      if (!forceRefresh && activeTOsCacheData != null && activeTOsCacheTime != null) {
        final cacheAge = DateTime.now().difference(activeTOsCacheTime!);
        if (cacheAge < listCacheValidDuration) {
          print('📦 [캐시] 진행중 TO 캐시 사용 (${cacheAge.inSeconds}초 경과)');
          
          if (publishedOnly) {
            return activeTOsCacheData!.where((to) => to.isPublished).toList();
          }
          return activeTOsCacheData!;
        }
      }
      
      // ✅ Phase 4-3: 서버 필터링 적용
      final snapshot = await db
          .collection('tos')
          .where('status', isEqualTo: 'ACTIVE')
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

      // ✅ Phase 3: 캐시 저장
      activeTOsCacheData = masterOrSingleTOs;
      activeTOsCacheTime = DateTime.now();

      if (publishedOnly) {
        return masterOrSingleTOs.where((to) => to.isPublished).toList();
      }

      print('✅ [최적화] 진행중 TO: ${masterOrSingleTOs.length}개');
      return masterOrSingleTOs;
    } catch (e) {
      print('❌ 진행중 TO 조회 실패: $e');
      return [];
    }
  }

  /// 마감된 TO 목록 조회 (대표 TO + 단일 TO)
  Future<List<TOModel>> getClosedTOs({bool forceRefresh = false}) async {
    try {
      // ✅ Phase 3: 캐시 체크
      if (!forceRefresh && closedTOsCacheData != null && closedTOsCacheTime != null) {
        final cacheAge = DateTime.now().difference(closedTOsCacheTime!);
        if (cacheAge < listCacheValidDuration) {
          print('📦 [캐시] 마감 TO 캐시 사용 (${cacheAge.inSeconds}초 경과)');
          return closedTOsCacheData!;
        }
      }
      
      // ✅ Phase 4-3: 서버 필터링
      final snapshot = await db
          .collection('tos')
          .where('status', whereIn: ['CLOSED', 'FULL', 'EXPIRED'])
          .orderBy('date', descending: true)
          .limit(50)
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

      final recentClosedTOs = masterOrSingleTOs.take(5).toList();

      // ✅ Phase 3: 캐시 저장
      closedTOsCacheData = recentClosedTOs;
      closedTOsCacheTime = DateTime.now();
      
      print('✅ [최적화] 마감된 TO: ${recentClosedTOs.length}개');
      return recentClosedTOs;
    } catch (e) {
      print('❌ 마감된 TO 조회 실패: $e');
      return [];
    }
  }

  /// 사업장별 진행중 TO 조회
  Future<List<TOModel>> getActiveTOsByBusinessId(String businessId) async {
    try {
      final snapshot = await db
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'ACTIVE')
          .orderBy('date', descending: false)
          .get();

      return snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 사업장 진행중 TO 조회 실패: $e');
      return [];
    }
  }

  /// 사업장별 마감 TO 조회
  Future<List<TOModel>> getClosedTOsByBusinessId(String businessId) async {
    try {
      final snapshot = await db
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('status', whereIn: ['CLOSED', 'FULL', 'EXPIRED'])
          .orderBy('date', descending: true)
          .limit(20)
          .get();

      return snapshot.docs
          .map((doc) => TOModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      print('❌ 사업장 마감 TO 조회 실패: $e');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════
  // TO 마감/재오픈
  // ═══════════════════════════════════════════════════════════

  /// TO 수동 마감
  Future<bool> closeTOManually(String toId, String adminUID) async {
    try {
      final toDoc = await db.collection('tos').doc(toId).get();
      final toData = toDoc.data();
      final groupId = toData?['groupId'] as String?;
      final isGroupMaster = toData?['isGroupMaster'] ?? false;
      
      await db.collection('tos').doc(toId).update({
        'isManualClosed': true,
        'closedAt': FieldValue.serverTimestamp(),
        'closedBy': adminUID,
        'status': 'CLOSED',
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      
      clearCache(toId: toId);
      invalidateListCache();

      if (groupId != null && !isGroupMaster) {
        await _updateGroupMasterStatus(groupId);
      }

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
      final toDoc = await db.collection('tos').doc(toId).get();
      final toData = toDoc.data();
      final groupId = toData?['groupId'] as String?;
      
      await db.collection('tos').doc(toId).update({
        'isManualClosed': false,
        'reopenedAt': FieldValue.serverTimestamp(),
        'reopenedBy': adminUID,
      });
      
      await updateTOStatus(toId);
      
      clearCache(toId: toId);
      invalidateListCache();

      if (groupId != null) {
        await _updateGroupMasterStatus(groupId);
      }

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
      print('🔒 [closeGroupTOs] 시작: $groupId');
      
      final snapshot = await db
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();

      if (snapshot.docs.isEmpty) {
        print('❌ 그룹 TO를 찾을 수 없음');
        return false;
      }

      final batch = db.batch();
      
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isManualClosed': true,
          'closedAt': FieldValue.serverTimestamp(),
          'closedBy': adminUID,
          'status': 'CLOSED',
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();

      // 각 TO의 WorkDetails 마감
      for (var doc in snapshot.docs) {
        final workDetailsSnapshot = await db
            .collection('tos')
            .doc(doc.id)
            .collection('workDetails')
            .get();

        if (workDetailsSnapshot.docs.isNotEmpty) {
          final workBatch = db.batch();
          
          for (var workDoc in workDetailsSnapshot.docs) {
            workBatch.update(workDoc.reference, {
              'isManualClosed': true,
              'closedAt': FieldValue.serverTimestamp(),
              'closedBy': adminUID,
            });
          }
          
          await workBatch.commit();
        }
        
        clearCache(toId: doc.id);
      }

      invalidateListCache();
      print('✅ 그룹 전체 마감 완료: $groupId');
      return true;
    } catch (e) {
      print('❌ 그룹 마감 실패: $e');
      return false;
    }
  }

  /// 그룹 TO 전체 재오픈
  Future<bool> reopenGroupTOs(String groupId, String adminUID) async {
    try {
      print('🔓 [reopenGroupTOs] 시작: $groupId');
      
      final snapshot = await db
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();

      if (snapshot.docs.isEmpty) {
        print('❌ 그룹 TO를 찾을 수 없음');
        return false;
      }

      final batch = db.batch();
      
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isManualClosed': false,
          'reopenedAt': FieldValue.serverTimestamp(),
          'reopenedBy': adminUID,
        });
      }

      await batch.commit();

      // 각 TO의 WorkDetails 재오픈
      for (var doc in snapshot.docs) {
        final workDetailsSnapshot = await db
            .collection('tos')
            .doc(doc.id)
            .collection('workDetails')
            .get();

        if (workDetailsSnapshot.docs.isNotEmpty) {
          final workBatch = db.batch();
          
          for (var workDoc in workDetailsSnapshot.docs) {
            workBatch.update(workDoc.reference, {
              'isManualClosed': false,
              'closedAt': FieldValue.delete(),
              'closedBy': FieldValue.delete(),
            });
          }
          
          await workBatch.commit();
        }
        
        clearCache(toId: doc.id);
      }

      // 각 TO 상태 재계산
      for (var doc in snapshot.docs) {
        await updateTOStatus(doc.id);
      }
      
      invalidateListCache();
      print('✅ 그룹 전체 재오픈 완료: $groupId');
      return true;
    } catch (e) {
      print('❌ 그룹 재오픈 실패: $e');
      return false;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // TO 상태 관리
  // ═══════════════════════════════════════════════════════════

  /// TO 상태 업데이트
  Future<bool> updateTOStatus(String toId) async {
    try {
      final toDoc = await db.collection('tos').doc(toId).get();
      if (!toDoc.exists) return false;
      
      final data = toDoc.data()!;
      final newStatus = _calculateTOStatus(data);
      
      await db.collection('tos').doc(toId).update({
        'status': newStatus,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ TO status 업데이트: $toId → $newStatus');
      return true;
    } catch (e) {
      print('❌ TO status 업데이트 실패: $e');
      return false;
    }
  }

  /// TO 상태 계산
  String _calculateTOStatus(Map<String, dynamic> data) {
    // 1. 수동 마감
    if (data['isManualClosed'] == true) {
      return 'CLOSED';
    }
    
    // 2. 인원 충족
    final totalConfirmed = data['totalConfirmed'] ?? 0;
    final totalRequired = data['totalRequired'] ?? 0;
    if (totalRequired > 0 && totalConfirmed >= totalRequired) {
      return 'FULL';
    }
    
    // 3. 시간 초과 체크
    if (_isTimeExpired(data)) {
      return 'EXPIRED';
    }
    
    return 'ACTIVE';
  }

  /// 시간 만료 체크
  bool _isTimeExpired(Map<String, dynamic> data) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    
    final jobType = data['jobType'] ?? 'short';
    
    if (jobType == 'long_term') {
      final deadline = (data['applicationDeadline'] as Timestamp?)?.toDate();
      if (deadline != null && now.isAfter(deadline)) {
        return true;
      }
    } else {
      final workDate = (data['date'] as Timestamp?)?.toDate();
      if (workDate != null) {
        final workDay = DateTime(workDate.year, workDate.month, workDate.day);
        if (workDay.isBefore(today)) {
          return true;
        }
      }
    }
    
    return false;
  }

  /// status 필드 마이그레이션
  Future<int> migrateToStatusField() async {
    try {
      print('🔄 [Migration] TO status 필드 마이그레이션 시작...');
      
      final snapshot = await db
          .collection('tos')
          .where('status', isNull: true)
          .get();
      
      int count = 0;
      for (var doc in snapshot.docs) {
        final status = _calculateTOStatus(doc.data());
        await doc.reference.update({
          'status': status,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        });
        count++;
      }
      
      print('✅ [Migration] 완료: $count개 TO 업데이트');
      return count;
    } catch (e) {
      print('❌ [Migration] 실패: $e');
      return 0;
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 통계 재계산
  // ═══════════════════════════════════════════════════════════

  /// TO 통계 재계산
  Future<bool> recalculateTOStats(String toId) async {
    try {
      print('🔄 TO 통계 재계산: $toId');
      
      final apps = await getApplicationsByTOId(toId);
      
      final totalPending = apps.where((a) => a.status == 'PENDING').length;
      final totalConfirmed = apps.where((a) => a.status == 'CONFIRMED').length;
      
      await db.collection('tos').doc(toId).update({
        'totalPending': totalPending,
        'totalConfirmed': totalConfirmed,
      });
      
      // WorkDetail 통계도 재계산
      await recalculateWorkDetailStats(toId);
      
      // status 업데이트
      await updateTOStatus(toId);
      
      clearCache(toId: toId);
      print('✅ TO 통계 재계산 완료: 대기=$totalPending, 확정=$totalConfirmed');
      return true;
    } catch (e) {
      print('❌ TO 통계 재계산 실패: $e');
      return false;
    }
  }

  /// WorkDetail 통계 재계산
  Future<bool> recalculateWorkDetailStats(String toId) async {
    try {
      final apps = await getApplicationsByTOId(toId);
      final workDetailsSnapshot = await db
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();
      
      final batch = db.batch();
      
      for (var workDoc in workDetailsSnapshot.docs) {
        final workData = workDoc.data();
        final workType = workData['workType'];
        final startTime = workData['startTime'];
        final endTime = workData['endTime'];
        
        final workApps = apps.where((a) {
          if (a.workDetailId == workDoc.id) return true;
          return a.selectedWorkType == workType &&
                 a.startTime == startTime &&
                 a.endTime == endTime;
        });
        
        final pendingCount = workApps.where((a) => a.status == 'PENDING').length;
        final currentCount = workApps.where((a) => a.status == 'CONFIRMED').length;
        
        batch.update(workDoc.reference, {
          'pendingCount': pendingCount,
          'currentCount': currentCount,
        });
      }
      
      await batch.commit();
      print('✅ WorkDetail 통계 재계산 완료');
      return true;
    } catch (e) {
      print('❌ WorkDetail 통계 재계산 실패: $e');
      return false;
    }
  }

  /// 그룹 통계 재계산
  Future<bool> recalculateGroupStats(String groupId) async {
    try {
      print('🔄 그룹 통계 재계산: $groupId');
      
      final groupTOs = await getTOsByGroup(groupId);
      
      if (groupTOs.isEmpty) {
        print('❌ 그룹 TO를 찾을 수 없습니다: $groupId');
        return false;
      }
      
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

  /// TO의 totalRequired + 급여 정보 재계산
  Future<void> _recalculateTOWorkInfo(String toId) async {
    try {
      final workDetails = await getWorkDetails(toId, forceRefresh: true);
      
      if (workDetails.isEmpty) {
        await db.collection('tos').doc(toId).update({
          'totalRequired': 0,
          'minWage': null,
          'maxWage': null,
          'wageType': null,
          'workDetailCount': 0,
        });
        return;
      }
      
      int totalRequired = 0;
      for (var work in workDetails) {
        totalRequired += work.requiredCount;
      }
      
      final wages = workDetails.map((w) => w.wage).toList();
      final minWage = wages.reduce((a, b) => a < b ? a : b);
      final maxWage = wages.reduce((a, b) => a > b ? a : b);
      
      await db.collection('tos').doc(toId).update({
        'totalRequired': totalRequired,
        'minWage': minWage,
        'maxWage': maxWage,
        'wageType': workDetails.first.wageType,
        'workDetailCount': workDetails.length,
      });
      
      print('📊 TO 정보 업데이트: 필요인원=$totalRequired, 급여=$minWage~$maxWage');
    } catch (e) {
      print('❌ TO 정보 재계산 실패: $e');
    }
  }

  /// TO의 totalRequired만 재계산
  Future<void> _recalculateTotalRequired(String toId) async {
    try {
      final workDetails = await getWorkDetails(toId, forceRefresh: true);
      
      int totalRequired = 0;
      for (var work in workDetails) {
        totalRequired += work.requiredCount;
      }
      
      await db.collection('tos').doc(toId).update({
        'totalRequired': totalRequired,
        'workDetailCount': workDetails.length,
      });
      
      print('📊 totalRequired 업데이트: $totalRequired');
    } catch (e) {
      print('❌ totalRequired 재계산 실패: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 캐시 관리
  // ═══════════════════════════════════════════════════════════

  /// 캐시 초기화
  void clearCache({String? toId}) {
    if (toId != null) {
      print('🗑️ 캐시 삭제: $toId');
      applicationCache.remove(toId);
      workDetailCache.remove(toId);
      timeRangeCache.remove(toId);
      
      cacheTimestamps.remove('application_$toId');
      cacheTimestamps.remove('workDetail_$toId');
      cacheTimestamps.remove('timeRange_$toId');
    } else {
      print('🗑️ 전체 캐시 삭제');
      applicationCache.clear();
      workDetailCache.clear();
      timeRangeCache.clear();
      cacheTimestamps.clear();

      activeTOsCacheData = null;
      closedTOsCacheData = null;
      activeTOsCacheTime = null;
      closedTOsCacheTime = null;
      
      userCache.clear();
      userCacheTimestamps.clear();
    }
  }

  /// TO 목록 캐시만 무효화
  void invalidateListCache() {
    activeTOsCacheData = null;
    closedTOsCacheData = null;
    activeTOsCacheTime = null;
    closedTOsCacheTime = null;
    print('🗑️ TO 목록 캐시 무효화');
  }

  // ═══════════════════════════════════════════════════════════
  // Lazy Loading
  // ═══════════════════════════════════════════════════════════

  /// 그룹 TO 아이템 경량 조회 (목록용)
  Future<List<Map<String, dynamic>>> getTOGroupItemsLight(String groupId) async {
    try {
      final groupTOs = await getTOsByGroup(groupId);
      
      return groupTOs.map((to) => {
        'to': to,
        'workDetails': <WorkDetailModel>[],
        'workStats': <String, Map<String, int>>{},
      }).toList();
    } catch (e) {
      print('❌ 그룹 TO 경량 조회 실패: $e');
      return [];
    }
  }

  /// 그룹 TO 목록 경량 로드
  Future<List<TOModel>> loadGroupTOsLight(String groupId) async {
    return await getTOsByGroup(groupId);
  }

  /// TO의 WorkDetails + 통계 로드
  Future<Map<String, dynamic>> loadTOWorkDetails(TOModel to) async {
    try {
      final workDetails = await getWorkDetails(to.id);
      final apps = await getApplicationsByTOId(to.id);
      
      Map<String, Map<String, int>> workStats = {};
      for (var work in workDetails) {
        final workApps = apps.where((a) {
          if (a.workDetailId != null && a.workDetailId!.isNotEmpty) {
            return a.workDetailId == work.id;
          }
          return a.selectedWorkType == work.workType &&
                 a.startTime == work.startTime &&
                 a.endTime == work.endTime;
        });
        
        workStats[work.id] = {
          'confirmed': workApps.where((a) => a.status == 'CONFIRMED').length,
          'pending': workApps.where((a) => a.status == 'PENDING').length,
        };
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
      
      return {
        'workDetails': workDetails,
        'workStats': workStats,
      };
    } catch (e) {
      print('❌ TO 상세 로드 실패: $e');
      return {
        'workDetails': <WorkDetailModel>[],
        'workStats': <String, Map<String, int>>{},
      };
    }
  }
  /// 그룹 마스터 TO의 status 업데이트
  /// - 그룹 내 TO들의 상태에 따라 마스터 status 결정
  Future<bool> _updateGroupMasterStatus(String groupId) async {
    try {
      print('📊 [Sync] 그룹 마스터 status 업데이트: $groupId');
      
      // 1. 그룹의 모든 TO 조회
      final snapshot = await db
          .collection('tos')
          .where('groupId', isEqualTo: groupId)
          .get();
      
      if (snapshot.docs.isEmpty) return false;
      
      // 2. 마스터 TO 찾기
      final masterDoc = snapshot.docs.firstWhere(
        (doc) => doc.data()['isGroupMaster'] == true,
        orElse: () => snapshot.docs.first,
      );
      
      // 3. 그룹 내 활성 TO 여부 확인
      bool hasActiveTO = false;
      for (var doc in snapshot.docs) {
        final data = doc.data();
        final status = data['status'] ?? 'ACTIVE';
        if (status == 'ACTIVE') {
          hasActiveTO = true;
          break;
        }
      }
      
      // 마스터 status 결정
      final masterData = masterDoc.data();
      final isManualClosed = masterData['isManualClosed'] ?? false;
      
      String newStatus;
      if (isManualClosed) {
        newStatus = 'CLOSED';
      } else if (hasActiveTO) {
        newStatus = 'ACTIVE';
      } else {
        newStatus = 'CLOSED';
      }
      
      // 4. 마스터 status 업데이트
      await masterDoc.reference.update({
        'status': newStatus,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      
      print('   ✅ 마스터 status 업데이트: $newStatus (활성 TO: $hasActiveTO)');
      return true;
    } catch (e) {
      print('❌ [Sync] 그룹 마스터 status 업데이트 실패: $e');
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
      
      return await updateGroupMasterStats(to.groupId!);
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
      final snapshot = await db
          .collection('tos')
          .where('isGroupMaster', isEqualTo: true)
          .get();
      
      int successCount = 0;
      final groupIds = <String>{};
      
      for (var doc in snapshot.docs) {
        final groupId = doc.data()['groupId'] as String?;
        if (groupId != null && !groupIds.contains(groupId)) {
          groupIds.add(groupId);
          final success = await updateGroupMasterStats(groupId);
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
}