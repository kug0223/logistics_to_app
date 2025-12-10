part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// TO 관리 - 기본 CRUD 및 조회 (TO Basic Operations)
// ═══════════════════════════════════════════════════════════

extension TOFirestore on FirestoreService {
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
        // ✅ Phase 4: 상태 필드
        'status': 'ACTIVE',
        'statusUpdatedAt': FieldValue.serverTimestamp(),
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
        await _updateGroupMasterStats(groupId);
      }

      //ToastHelper.showSuccess('TO가 생성되었습니다!');
      return toDoc.id;
    } catch (e) {
      print('❌ [FirestoreService] TO 생성 실패: $e');
      return null;
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

  /// 2단계: 그룹 펼칠 때 - 그룹 내 TO 목록만 로드 (WorkDetails는 개별 펼침 시)
  Future<List<TOItem>> loadGroupTOsLight(String groupId) async {
    try {
      print('🔍 [Lazy] 그룹 내 TO 목록 로드: $groupId');
      
      // ✅ TO 목록만 조회 (WorkDetails, Applications 조회 제거!)
      final groupTOs = await getTOsByGroup(groupId);
      
      List<TOItem> toItems = [];
      for (var to in groupTOs) {
        toItems.add(TOItem(
          to: to,
          workDetails: null,                    // ✅ 펼칠 때 로드
          confirmedCount: to.totalConfirmed,    // ✅ TO 문서 값 사용
          pendingCount: to.totalPending,
          totalRequired: to.totalRequired,
          workDetailStats: null,                // ✅ 펼칠 때 로드
          isWorkDetailLoaded: false,            // ✅ 아직 안 로드됨
        ));
      }
      
      print('✅ [Lazy] 그룹 TO 로드 완료: ${toItems.length}개 (경량)');
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
        getApplicationsByTO(to.businessId, to.title, to.date, isLongTerm: to.isLongTerm),
      ]);
      
      final workDetails = results[0] as List<WorkDetailModel>;
      final apps = results[1] as List<ApplicationModel>;
      
      print('   📋 WorkDetails: ${workDetails.length}개');
      print('   📋 Applications: ${apps.length}개');
      for (var app in apps) {
        print('      - ${app.selectedWorkType}: ${app.status} (workDate: ${app.workDate})');
      }
      
      // 업무별 통계 계산 (workDetailId로 구분!)
      Map<String, Map<String, int>> workStats = {};
      for (var work in workDetails) {
        // ✅ workDetailId로 매칭 (없으면 workType + 시간으로 폴백)
        final workApps = apps.where((a) {
          if (a.workDetailId != null && a.workDetailId!.isNotEmpty) {
            return a.workDetailId == work.id;
          }
          // 기존 데이터 호환: workType + 시간으로 매칭
          return a.selectedWorkType == work.workType &&
                 a.startTime == work.startTime &&
                 a.endTime == work.endTime;
        });
        
        // ✅ key를 workDetailId로 변경
        workStats[work.id] = {
          'confirmed': workApps.where((a) => a.status == 'CONFIRMED').length,
          'pending': workApps.where((a) => a.status == 'PENDING').length,
        };
        print('   📊 ${work.workType} (${work.id}): 확정=${workStats[work.id]!['confirmed']}, 대기=${workStats[work.id]!['pending']}');
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
}