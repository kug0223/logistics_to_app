part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 근로자 실시간 위치 관리 (Worker Location Tracking)
// ═══════════════════════════════════════════════════════════

const _workerLocationCol = 'worker_locations';

extension WorkerLocationFirestore on FirestoreService {

  // ───────────────────────────────────────────────────────
  // 근로자 측 (출근 전 위치 업로드)
  // ───────────────────────────────────────────────────────

  /// 위치 공유 동의 저장 (출근 전 배너에서 허용 시 1회 호출)
  Future<void> grantLocationConsent({
    required String applicationId,
    required String userId,
    required String businessId,
    required DateTime workDate,
    required String scheduledStart,
  }) async {
    final now = DateTime.now();
    final ref = _firestore.collection(_workerLocationCol).doc(applicationId);
    final snap = await ref.get();
    if (snap.exists) {
      await ref.update({'consentGiven': true, 'updatedAt': Timestamp.fromDate(now)});
    } else {
      await ref.set({
        'userId': userId,
        'businessId': businessId,
        'lat': 0.0,
        'lng': 0.0,
        'accuracy': 0.0,
        'distanceMeters': null,
        'isActive': true,
        'workDate': Timestamp.fromDate(workDate),
        'scheduledStart': scheduledStart,
        'consentGiven': true,
        'updatedAt': Timestamp.fromDate(now),
        'createdAt': Timestamp.fromDate(now),
      });
    }
    debugPrint('✅ [WorkerLocation] 위치 공유 동의 저장: $applicationId');
  }

  /// 위치 갱신 (2분마다 호출)
  Future<void> updateWorkerLocation({
    required String applicationId,
    required double lat,
    required double lng,
    required double accuracy,
    double? distanceMeters,
  }) async {
    final now = DateTime.now();
    await _firestore.collection(_workerLocationCol).doc(applicationId).update({
      'lat': lat,
      'lng': lng,
      'accuracy': accuracy,
      'distanceMeters': distanceMeters,
      'isActive': true,
      'updatedAt': Timestamp.fromDate(now),
    });
    debugPrint('📍 [WorkerLocation] 위치 갱신: $applicationId '
        '(${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}) '
        '${distanceMeters != null ? "${distanceMeters.toStringAsFixed(0)}m" : ""}');
  }

  /// 추적 중지 (출근 체크 완료 또는 추적 윈도우 종료 시 호출)
  Future<void> stopWorkerTracking(String applicationId) async {
    try {
      await _firestore.collection(_workerLocationCol).doc(applicationId).update({
        'isActive': false,
        'updatedAt': Timestamp.fromDate(DateTime.now()),
      });
      debugPrint('🛑 [WorkerLocation] 추적 중지: $applicationId');
    } catch (e) {
      debugPrint('⚠️ [WorkerLocation] 추적 중지 실패 (문서 없을 수 있음): $e');
    }
  }

  // ───────────────────────────────────────────────────────
  // 관리자 측 (당일 명단 위치 조회)
  // ───────────────────────────────────────────────────────

  /// 특정 applicationId의 위치 정보 단건 조회
  Future<WorkerLocationModel?> getWorkerLocation(String applicationId) async {
    try {
      final snap = await _firestore.collection(_workerLocationCol).doc(applicationId).get();
      if (!snap.exists) return null;
      return WorkerLocationModel.fromFirestore(snap);
    } catch (e) {
      debugPrint('❌ [WorkerLocation] 단건 조회 실패: $e');
      return null;
    }
  }

  /// 사업장 + 근무일 기준 활성 위치 목록 조회 (관리자용)
  Future<List<WorkerLocationModel>> getActiveLocationsForBusiness({
    required String businessId,
    required DateTime workDate,
  }) async {
    try {
      final startOfDay = DateTime(workDate.year, workDate.month, workDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final snap = await _firestore
          .collection(_workerLocationCol)
          .where('businessId', isEqualTo: businessId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
          .where('workDate', isLessThan: Timestamp.fromDate(endOfDay))
          .where('isActive', isEqualTo: true)
          .get();

      return snap.docs.map(WorkerLocationModel.fromFirestore).toList();
    } catch (e) {
      debugPrint('❌ [WorkerLocation] 목록 조회 실패: $e');
      return [];
    }
  }

  /// applicationId 목록으로 위치 일괄 조회 (당일 명단 로드 시)
  Future<Map<String, WorkerLocationModel>> getLocationsForApplications(
    List<String> applicationIds,
  ) async {
    if (applicationIds.isEmpty) return {};
    try {
      // Firestore whereIn 최대 30개 제한 처리
      final result = <String, WorkerLocationModel>{};
      for (int i = 0; i < applicationIds.length; i += 30) {
        final chunk = applicationIds.sublist(
          i,
          (i + 30) < applicationIds.length ? i + 30 : applicationIds.length,
        );
        final snap = await _firestore
            .collection(_workerLocationCol)
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        for (final doc in snap.docs) {
          result[doc.id] = WorkerLocationModel.fromFirestore(doc);
        }
      }
      return result;
    } catch (e) {
      debugPrint('❌ [WorkerLocation] 일괄 조회 실패: $e');
      return {};
    }
  }

  /// 실시간 위치 스트림 (관리자 당일 명단 화면)
  Stream<WorkerLocationModel?> watchWorkerLocation(String applicationId) {
    return _firestore
        .collection(_workerLocationCol)
        .doc(applicationId)
        .snapshots()
        .map((snap) => snap.exists ? WorkerLocationModel.fromFirestore(snap) : null);
  }
}
