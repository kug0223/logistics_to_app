part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 업무 상세 정보 관리 (Work Details Management)
// ═══════════════════════════════════════════════════════════

extension WorkDetailFirestore on FirestoreService {
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
      
      // ✅ 모든 WorkDetail이 마감됐는지 체크 → TO status 업데이트
      await _checkAndUpdateTOStatusAfterWorkDetailClose(toId, adminUID);
      
      return true;
    } catch (e) {
      print('❌ WorkDetail 마감 실패: $e');
      return false;
    }
  }
  /// WorkDetail 재오픈
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
      
      // ✅ WorkDetail 재오픈 시 TO status도 ACTIVE로 업데이트
      await _checkAndUpdateTOStatusAfterWorkDetailReopen(toId, adminUID);
      
      return true;
    } catch (e) {
      print('❌ WorkDetail 재오픈 실패: $e');
      return false;
    }
  }
  /// WorkDetail 마감 후 TO status 체크 및 업데이트
  /// - 모든 WorkDetail이 마감됐으면 TO status = CLOSED
  Future<void> _checkAndUpdateTOStatusAfterWorkDetailClose(String toId, String adminUID) async {
    try {
      // 1. 해당 TO의 모든 WorkDetail 조회
      final workDetailsSnapshot = await _firestore
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();
      
      if (workDetailsSnapshot.docs.isEmpty) return;
      
      // 2. 모든 WorkDetail이 마감됐는지 체크
      final allClosed = workDetailsSnapshot.docs.every((doc) {
        final data = doc.data();
        return data['closedAt'] != null;
      });
      
      print('🔍 WorkDetail 마감 체크: 전체 ${workDetailsSnapshot.docs.length}개, 모두 마감: $allClosed');
      
      // 3. 모두 마감이면 TO status 업데이트
      if (allClosed) {
        await _firestore.collection('tos').doc(toId).update({
          'status': 'CLOSED',
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        });
        print('   ✅ TO status → CLOSED');
        
        // 4. 그룹 TO면 마스터 status도 재계산
        final toDoc = await _firestore.collection('tos').doc(toId).get();
        final groupId = toDoc.data()?['groupId'] as String?;
        if (groupId != null) {
          await _updateGroupMasterStatus(groupId);
        }
        
        invalidateListCache();
      }
    } catch (e) {
      print('⚠️ TO status 업데이트 실패: $e');
    }
  }
  
  /// WorkDetail 재오픈 후 TO status 업데이트
  /// - 하나라도 열리면 TO status = ACTIVE
  Future<void> _checkAndUpdateTOStatusAfterWorkDetailReopen(String toId, String adminUID) async {
    try {
      // TO status를 ACTIVE로 업데이트 (하나라도 열려있으면 활성)
      await _firestore.collection('tos').doc(toId).update({
        'status': 'ACTIVE',
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      print('   ✅ TO status → ACTIVE');
      
      // 그룹 TO면 마스터 status도 재계산
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      final groupId = toDoc.data()?['groupId'] as String?;
      if (groupId != null) {
        await _updateGroupMasterStatus(groupId);
      }
      
      invalidateListCache();
    } catch (e) {
      print('⚠️ TO status 업데이트 실패: $e');
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
        // 🔥 UTC → 로컬 변환 후 날짜 추출
        final localWorkDate = workDate.toLocal();
        final timeParts = startTime.split(':');
        final workStartDateTime = DateTime(
          localWorkDate.year,
          localWorkDate.month,
          localWorkDate.day,
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
        // 🔥 UTC → 로컬 변환
        final date = (toData['date'] as Timestamp).toDate().toLocal();
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
  
}