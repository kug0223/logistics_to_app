part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 업무 상세 정보 관리 (Work Detail Management)
// ═══════════════════════════════════════════════════════════

extension WorkDetailFirestore on FirestoreService {

  // ═══════════════════════════════════════════════════════════
  // WorkDetail 조회
  // ═══════════════════════════════════════════════════════════

  /// 업무 상세 정보 조회 (캐싱 적용)
  Future<List<WorkDetailModel>> getWorkDetails(String toId, {bool forceRefresh = false}) async {
    try {
      // 🔥 강제 새로고침이 아닐 때만 캐시 확인
      if (!forceRefresh && workDetailCache.containsKey(toId)) {
        final cacheTime = cacheTimestamps['workDetail_$toId'];
        if (cacheTime != null && DateTime.now().difference(cacheTime) < cacheValidDuration) {
          return workDetailCache[toId]!;
        }
      }
      
      final snapshot = await db
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .orderBy('order')
          .get();

      final workDetails = snapshot.docs
          .map((doc) => WorkDetailModel.fromMap(doc.data(), doc.id))
          .toList();

      // ✅ 캐시 저장
      workDetailCache[toId] = workDetails;
      cacheTimestamps['workDetail_$toId'] = DateTime.now();

      return workDetails;
    } catch (e) {
      print('❌ WorkDetails 조회 실패: $e');
      return [];
    }
  }

  /// 여러 TO의 WorkDetails 배치 조회
  Future<Map<String, List<WorkDetailModel>>> getWorkDetailsBatch(List<String> toIds) async {
    try {
      if (toIds.isEmpty) return {};
      
      final Map<String, List<WorkDetailModel>> result = {};
      
      await Future.wait(toIds.map((toId) async {
        result[toId] = await getWorkDetails(toId);
      }));
      
      return result;
    } catch (e) {
      print('❌ WorkDetails 배치 조회 실패: $e');
      return {};
    }
  }

  // ═══════════════════════════════════════════════════════════
  // WorkDetail CRUD
  // ═══════════════════════════════════════════════════════════

  /// WorkDetail 생성 (TO 생성 시 함께 호출)
  Future<bool> createWorkDetails({
    required String toId,
    required List<Map<String, dynamic>> workDetailsData,
  }) async {
    try {
      final batch = db.batch();

      for (int i = 0; i < workDetailsData.length; i++) {
        final data = workDetailsData[i];
        final docRef = db
            .collection('tos')
            .doc(toId)
            .collection('workDetails')
            .doc();

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
  Future<String> addWorkDetail({
    required String toId,
    required WorkDetailModel workDetail,
  }) async {
    try {
      final docRef = await db
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
      await db
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
      await db
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

  // ═══════════════════════════════════════════════════════════
  // WorkDetail 마감/재오픈
  // ═══════════════════════════════════════════════════════════

  /// WorkDetail 마감
  Future<bool> closeWorkDetail({
    required String toId,
    required String workDetailId,
    required String adminUID,
  }) async {
    try {
      await db
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
  Future<bool> reopenWorkDetail({
    required String toId,
    required String workDetailId,
    required String adminUID,
  }) async {
    try {
      await db
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
      final workDetailsSnapshot = await db
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
        await db.collection('tos').doc(toId).update({
          'status': 'CLOSED',
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        });
        print('   ✅ TO status → CLOSED');
        
        // 4. 그룹 TO면 마스터 status도 재계산
        final toDoc = await db.collection('tos').doc(toId).get();
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
      await db.collection('tos').doc(toId).update({
        'status': 'ACTIVE',
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      print('   ✅ TO status → ACTIVE');
      
      // 그룹 TO면 마스터 status도 재계산
      final toDoc = await db.collection('tos').doc(toId).get();
      final groupId = toDoc.data()?['groupId'] as String?;
      if (groupId != null) {
        await _updateGroupMasterStatus(groupId);
      }
      
      invalidateListCache();
    } catch (e) {
      print('⚠️ TO status 업데이트 실패: $e');
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 긴급 모집
  // ═══════════════════════════════════════════════════════════

  /// WorkDetail 긴급 모집 시작
  Future<bool> startEmergencyRecruitment({
    required String toId,
    required String workDetailId,
    required String adminUID,
  }) async {
    try {
      await db
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
      await db
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

  // ═══════════════════════════════════════════════════════════
  // 유틸리티
  // ═══════════════════════════════════════════════════════════

  /// WorkDetail ID 찾기 (workType으로 검색)
  Future<String?> findWorkDetailIdByType(String toId, String workType) async {
    try {
      final snapshot = await db
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
      await db
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
      await db
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
  // 마감시간 관리
  // ═══════════════════════════════════════════════════════════

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
      final workDetailsSnapshot = await db
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();
      
      if (workDetailsSnapshot.docs.isEmpty) {
        print('⚠️ WorkDetails가 없습니다');
        return true;
      }
      
      // 2. Batch 업데이트
      final batch = db.batch();
      
      for (var workDoc in workDetailsSnapshot.docs) {
        final workData = workDoc.data();
        final startTime = workData['startTime'] as String;
        
        // 🔥 각 업무 시작 N시간 전으로 마감시간 계산
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
      
      final workDetailsSnapshot = await db
          .collection('tos')
          .doc(toId)
          .collection('workDetails')
          .get();
      
      if (workDetailsSnapshot.docs.isEmpty) {
        print('⚠️ WorkDetails가 없습니다');
        return true;
      }
      
      final batch = db.batch();
      
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

  /// 🔥 일회성: 기존 WorkDetails에 마감시간 추가 (마이그레이션용)
  Future<void> migrateWorkDetailDeadlines() async {
    try {
      print('🔄 WorkDetail 마감시간 마이그레이션 시작...');
      
      // 1. 모든 TO 조회
      final tosSnapshot = await db.collection('tos').get();
      int migratedCount = 0;
      
      for (var toDoc in tosSnapshot.docs) {
        final toData = toDoc.data();
        final workDate = (toData['date'] as Timestamp?)?.toDate();
        final hoursBeforeStart = toData['hoursBeforeStart'] ?? 2;
        
        if (workDate == null) continue;
        
        // 2. 각 TO의 WorkDetails 마이그레이션
        final success = await recalculateWorkDetailDeadlines(
          toId: toDoc.id,
          workDate: workDate,
          hoursBeforeStart: hoursBeforeStart,
        );
        
        if (success) migratedCount++;
      }
      
      print('✅ WorkDetail 마감시간 마이그레이션 완료: $migratedCount개 TO 처리');
    } catch (e) {
      print('❌ WorkDetail 마감시간 마이그레이션 실패: $e');
    }
  }
}