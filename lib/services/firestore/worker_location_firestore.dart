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
  ///
  /// merge: true로 upsert — 문서 존재 여부 사전 확인(TOCTOU) 없이 원자적으로 처리한다.
  /// 문서가 없으면 전체 필드로 생성, 있으면 지정 필드만 덮어쓴다.
  Future<void> grantLocationConsent({
    required String applicationId,
    required String userId,
    required String businessId,
    required DateTime workDate,
    required String scheduledStart,
  }) async {
    final ref = _firestore.collection(_workerLocationCol).doc(applicationId);
    await ref.set(
      {
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
        'updatedAt': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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
    try {
      await _firestore.collection(_workerLocationCol).doc(applicationId).update({
        'lat': lat,
        'lng': lng,
        'accuracy': accuracy,
        'distanceMeters': distanceMeters,
        'isActive': true,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      debugPrint('📍 [WorkerLocation] 위치 갱신: $applicationId '
          '(${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}) '
          '${distanceMeters != null ? "${distanceMeters.toStringAsFixed(0)}m" : ""}');
    } catch (e) {
      debugPrint('⚠️ [WorkerLocation] 위치 갱신 실패 ($applicationId): $e');
    }
  }

  /// 추적 중지 (출근 체크 완료 또는 추적 윈도우 종료 시 호출)
  Future<void> stopWorkerTracking(String applicationId) async {
    try {
      await _firestore.collection(_workerLocationCol).doc(applicationId).update({
        'isActive': false,
        'updatedAt': FieldValue.serverTimestamp(),
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

  /// applicationId 목록으로 위치 일괄 조회 (당일 명단 로드 시)
  /// [크로스-사업장 방지] CF Admin SDK 경유 — whereIn 쿼리 시 보안 규칙 filters null 반환 버그 우회
  /// CF callableGetLocationsForApplications에서 역할 검증 후 조회
  Future<Map<String, WorkerLocationModel>> getLocationsForApplications(
    List<String> applicationIds, {
    required String businessId,
  }) async {
    if (applicationIds.isEmpty) return {};
    try {
      final resp = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetLocationsForApplications',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
          .call({'applicationIds': applicationIds, 'businessId': businessId});
      final raw = ((resp.data as Map<dynamic, dynamic>)['locations']
              as Map<dynamic, dynamic>?) ??
          {};
      final result = <String, WorkerLocationModel>{};
      for (final entry in raw.entries) {
        final id = entry.key as String;
        final data = (entry.value as Map<dynamic, dynamic>).cast<String, dynamic>();
        final model = WorkerLocationModel.tryFromMap(data, id);
        if (model != null) result[id] = model;
      }
      return result;
    } catch (e) {
      debugPrint('❌ [WorkerLocation] CF 일괄 조회 실패: $e');
      return {};
    }
  }

}
