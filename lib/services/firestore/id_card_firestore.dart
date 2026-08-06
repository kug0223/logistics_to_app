part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 신분증 열람 요청 (ID Card Access Request)
// ═══════════════════════════════════════════════════════════

extension IdCardFirestore on FirestoreService {
  
  // ═══════════════════════════════════════════════════════════
  // 신분증 열람 요청 (ID Card Access Request)
  // ═══════════════════════════════════════════════════════════

  /// 신분증 열람 요청 생성
  /// [CF-MIGRATED 2026-07-15] callableCreateIdCardAccessRequest CF 이전
  ///   · 중복 체크(compound 쿼리)가 FILTERS-BROKEN으로 PERMISSION_DENIED 발생
  ///   · Admin SDK로 중복 체크 + 생성. 알림만 클라이언트에서 처리.
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
      debugPrint('📄 [createIdCardAccessRequest] 요청 생성');
      final reasonStr = _reasonToString(reason);

      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCreateIdCardAccessRequest',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
      final result = await callable.call<Map<String, dynamic>>({
        'requesterId': requesterId,
        'requesterName': requesterName,
        'requesterBusinessId': requesterBusinessId,
        'requesterBusinessName': requesterBusinessName,
        'targetUserId': targetUserId,
        'targetUserName': targetUserName,
        'reason': reasonStr,
        'customReason': customReason,
        'applicationId': applicationId,
      });
      final data = Map<String, dynamic>.from(result.data as Map? ?? {});
      final cfReason = data['reason'] as String?;
      final requestId = data['requestId'] as String?;

      if (cfReason == 'ALREADY_PENDING') {
        debugPrint('⚠️ 이미 대기 중인 요청이 있습니다');
        ToastHelper.showWarning('이미 요청 중입니다. 응답을 기다려주세요.');
        return null;
      }
      if (cfReason == 'ALREADY_APPROVED') {
        debugPrint('⚠️ 이미 유효한 열람 권한이 있습니다');
        ToastHelper.showInfo('이미 열람 권한이 있습니다.');
        return requestId;
      }

      // CREATED: 알림 생성 (지원자에게) — 클라이언트에서 처리
      if (requestId != null) {
        final reasonText = reason == IdCardAccessReason.other
            ? (customReason ?? '기타')
            : _getReasonText(reason);
        try {
          await createNotification(
            NotificationModel.createIdCardAccessRequest(
              userId: targetUserId,
              businessName: requesterBusinessName,
              businessId: requesterBusinessId,
              reason: reasonText,
              requestId: requestId,
            ),
          );
        } catch (e) {
          debugPrint('⚠️ [createIdCardAccessRequest] 알림 생성 실패: $e');
        }
      }

      debugPrint('✅ [createIdCardAccessRequest] 요청 생성 완료: $requestId');
      ToastHelper.showSuccess('신분증 열람 요청을 보냈습니다');
      return requestId;
    } catch (e) {
      debugPrint('❌ [createIdCardAccessRequest] 실패: $e');
      ToastHelper.showError('요청 실패');
      return null;
    }
  }

  /// 신분증 열람 요청 승인
  Future<bool> approveIdCardAccessRequest(String requestId) async {
    try {
      debugPrint('✅ [approveIdCardAccessRequest] 승인: $requestId');

      final docRef = _firestore.collection('idCardAccessRequests').doc(requestId);
      Map<String, dynamic>? requestData;

      // 관리자 2명이 동시에 승인 버튼을 탭하면 get→update 사이에 두 번째 get이
      // 끼어들어 알림 2건 발송 + expiresAt 충돌이 발생할 수 있음.
      // 트랜잭션으로 처리: pending 상태일 때만 approved로 전환 (이미 처리된 경우 false 반환).
      final wasApproved = await _firestore.runTransaction<bool>((tx) async {
        final doc = await tx.get(docRef);
        if (!doc.exists) return false;
        if (doc.data()?['status'] != 'pending') return false;

        final expiresAt = DateTime.now().add(const Duration(days: 7));
        tx.update(docRef, {
          'status': 'approved',
          'respondedAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(expiresAt),
        });
        requestData = Map.from(doc.data()!);
        return true;
      });

      if (!wasApproved || requestData == null) {
        debugPrint('⚠️ [approveIdCardAccessRequest] 이미 처리된 요청이거나 찾을 수 없습니다');
        return false;
      }

      // 트랜잭션 성공 후 알림 — 실패해도 승인 결과에 영향 없음
      try {
        await createNotification(
          NotificationModel.createIdCardAccessApproved(
            userId: requestData!['requesterId'],
            targetUserName: requestData!['targetUserName'],
            // requesterBusinessId는 createIdCardAccessRequest(line 67)에서 항상 저장 — '' 폴백 실제 발생 가능성 없음
            businessId: requestData!['requesterBusinessId'] as String? ?? '',
            requestId: requestId,
            workerId: requestData!['targetUserId'] as String? ?? '',
          ),
        );
      } catch (e) {
        debugPrint('⚠️ [approveIdCardAccessRequest] 알림 생성 실패: $e');
      }

      debugPrint('✅ [approveIdCardAccessRequest] 승인 완료');
      return true;
    } catch (e) {
      debugPrint('❌ [approveIdCardAccessRequest] 실패: $e');
      return false;
    }
  }

  /// 신분증 열람 요청 거절
  Future<bool> rejectIdCardAccessRequest(String requestId, {String? reason}) async {
    try {
      debugPrint('❌ [rejectIdCardAccessRequest] 거절: $requestId');

      final docRef = _firestore.collection('idCardAccessRequests').doc(requestId);
      Map<String, dynamic>? requestData;

      // approveIdCardAccessRequest와 동일하게 트랜잭션 적용 — 근무자가
      // 실수로 두 번 탭하면 중복 알림이 발송될 수 있으므로 pending 상태일 때만 처리.
      final wasRejected = await _firestore.runTransaction<bool>((tx) async {
        final doc = await tx.get(docRef);
        if (!doc.exists) return false;
        if (doc.data()?['status'] != 'pending') return false;

        tx.update(docRef, {
          'status': 'rejected',
          'respondedAt': FieldValue.serverTimestamp(),
          'rejectionReason': reason,
        });
        requestData = Map.from(doc.data()!);
        return true;
      });

      if (!wasRejected || requestData == null) {
        debugPrint('⚠️ [rejectIdCardAccessRequest] 이미 처리된 요청이거나 찾을 수 없습니다');
        return false;
      }

      // 트랜잭션 성공 후 알림 — 실패해도 거절 결과에 영향 없음
      try {
        await createNotification(
          NotificationModel.createIdCardAccessRejected(
            userId: requestData!['requesterId'],
            targetUserName: requestData!['targetUserName'],
            // requesterBusinessId는 createIdCardAccessRequest(line 67)에서 항상 저장 — '' 폴백 실제 발생 가능성 없음
            businessId: requestData!['requesterBusinessId'] as String? ?? '',
            requestId: requestId,
            workerId: requestData!['targetUserId'] as String? ?? '',
            rejectionReason: reason,
          ),
        );
      } catch (e) {
        debugPrint('⚠️ [rejectIdCardAccessRequest] 알림 생성 실패: $e');
      }

      debugPrint('✅ [rejectIdCardAccessRequest] 거절 완료');
      return true;
    } catch (e) {
      debugPrint('❌ [rejectIdCardAccessRequest] 실패: $e');
      return false;
    }
  }



  /// 신분증 열람 권한 확인 (최신 요청 1건 반환 — 상태 무관)
  /// [CF-MIGRATED 2026-07-15] callableCheckIdCardAccess CF 이전
  ///   · requesterId+targetUserId compound 쿼리 FILTERS-BROKEN → Admin SDK 경유
  Future<IdCardAccessRequestModel?> checkIdCardAccess({
    required String requesterId,
    required String targetUserId,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCheckIdCardAccess',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      final result = await callable.call<Map<String, dynamic>>({
        'requesterId': requesterId,
        'targetUserId': targetUserId,
      });
      final data = Map<String, dynamic>.from(result.data as Map? ?? {});
      final raw = data['request'];
      if (raw == null) return null;
      final hydrated = _cfHydrate(Map<String, dynamic>.from(raw as Map));
      final id = hydrated.remove('id') as String? ?? '';
      return IdCardAccessRequestModel.fromMap(hydrated, id);
    } catch (e) {
      debugPrint('❌ 열람 권한 확인 실패: $e');
      return null;
    }
  }
  /// 신분증 열람 권한 일괄 확인 (N명 → 단일 CF 호출)
  /// [CF-BATCH 2026-07-21] callableCheckIdCardAccessBatch — N × checkIdCardAccess 대체
  Future<Map<String, IdCardAccessRequestModel?>> checkIdCardAccessBatch({
    required String requesterId,
    required List<String> targetUserIds,
  }) async {
    if (targetUserIds.isEmpty) return {};
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCheckIdCardAccessBatch',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
      final result = await callable.call<Map<String, dynamic>>({
        'requesterId': requesterId,
        'targetUserIds': targetUserIds,
      });
      final raw = Map<String, dynamic>.from(result.data['requests'] as Map? ?? {});
      return {
        for (final entry in raw.entries)
          entry.key: () {
            if (entry.value == null) return null;
            final hydrated = _cfHydrate(Map<String, dynamic>.from(entry.value as Map));
            final id = hydrated.remove('id') as String? ?? '';
            return IdCardAccessRequestModel.tryFromMap(hydrated, id);
          }(),
      };
    } catch (e) {
      debugPrint('❌ 신분증 일괄 권한 확인 실패: $e');
      return {};
    }
  }

  /// 사용자에게 온 신분증 열람 요청 조회 (지원자/근무자용)
  /// [CF 이전 2026-07-15] callableGetMyIdCardRequests — targetUserId 서버 검증 강제
  Future<List<IdCardAccessRequestModel>> getPendingIdCardRequestsForUser(String userId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetMyIdCardRequests',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({'status': 'pending'});
      return ((result.data['requests'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return IdCardAccessRequestModel.tryFromMap(raw, id);
          })
          .whereType<IdCardAccessRequestModel>()
          .toList()
        ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt)));
    } catch (e) {
      debugPrint('❌ 신분증 요청 조회 실패: $e');
      return [];
    }
  }

  /// 사용자에게 온 계약해지 요청 조회 (근무자용)
  /// [CF 이전 2026-07-15] callableGetMyApplications — uid 서버 검증 강제
  Future<List<ApplicationModel>> getMyTerminationRequests(String uid) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetMyApplications',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'statuses': ['CONFIRMED', 'CONTRACT_PENDING'],
        'limit': 200,
      });
      return (result.data['applications'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return ApplicationModel.tryFromMap(raw, id);
          })
          .whereType<ApplicationModel>()
          .where((a) => a.terminationStatus == 'PENDING')
          .toList();
    } catch (e) {
      debugPrint('❌ 계약해지 요청 조회 실패: $e');
      return [];
    }
  }

  /// 내가 보낸 신분증 열람 요청 조회 (관리자용)
  /// [CF-MIGRATED 2026-07-15] callableGetMyIdCardRequestsAsAdmin CF 이전
  ///   · requesterId 단일 필터도 FILTERS-BROKEN으로 isSuperAdmin only 규칙에 막힘 → Admin SDK 경유
  Future<List<IdCardAccessRequestModel>> getMyIdCardRequests(String requesterId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetMyIdCardRequestsAsAdmin',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      final result = await callable.call<Map<String, dynamic>>({'limit': 50});
      return ((result.data['requests'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return IdCardAccessRequestModel.tryFromMap(raw, id);
          })
          .whereType<IdCardAccessRequestModel>()
          .toList()
        ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt)));
    } catch (e) {
      debugPrint('❌ 내 요청 조회 실패: $e');
      return [];
    }
  }

  /// 신분증 이미지 서명 URL 발급 (ID-1 보안: 1시간 만료 Signed URL)
  /// CF callableGetIdCardSignedUrl 경유 — 승인 확인 + Storage Signed URL 반환
  ///
  /// [silent] true 이면 에러 Toast 표시 없이 null 반환 (병렬 선제 호출 시 사용)
  Future<String?> getIdCardSignedUrl(String targetUserId, {bool silent = false}) async {
    try {
      debugPrint('🪪 [getIdCardSignedUrl] 요청: $targetUserId');
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetIdCardSignedUrl');
      final result = await callable.call<Map<String, dynamic>>(
        {'targetUserId': targetUserId},
      );
      final signedUrl = result.data['signedUrl'] as String?;
      if (signedUrl == null || signedUrl.isEmpty) {
        debugPrint('❌ [getIdCardSignedUrl] signedUrl 없음');
        return null;
      }
      debugPrint('✅ [getIdCardSignedUrl] 성공');
      return signedUrl;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ [getIdCardSignedUrl] CF 오류: ${e.code} ${e.message}');
      if (!silent) {
        if (e.code == 'permission-denied') {
          ToastHelper.showError('신분증 열람 권한이 없거나 만료되었습니다');
        } else {
          ToastHelper.showError('신분증 이미지 로드 실패');
        }
      }
      return null;
    } catch (e) {
      debugPrint('❌ [getIdCardSignedUrl] 실패: $e');
      if (!silent) ToastHelper.showError('신분증 이미지 로드 실패');
      return null;
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
  
}