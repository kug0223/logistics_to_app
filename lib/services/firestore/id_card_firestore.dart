part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 신분증 열람 요청 (ID Card Access Request)
// ═══════════════════════════════════════════════════════════

extension IdCardFirestore on FirestoreService {
  
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
      debugPrint('📄 [createIdCardAccessRequest] 요청 생성');
      
      // 1 & 2. pending/approved 동시 조회 — 두 쿼리는 독립적이므로 Future.wait 병렬 처리
      // [특이사항] 첫 요청(pending·approved 모두 없는 케이스)이 대부분이므로 병렬이 유리
      final now = Timestamp.fromDate(DateTime.now());
      final results = await Future.wait([
        _firestore
            .collection('idCardAccessRequests')
            .where('requesterId', isEqualTo: requesterId)
            .where('targetUserId', isEqualTo: targetUserId)
            .where('status', isEqualTo: 'pending')
            .limit(1)
            .get(),
        _firestore
            .collection('idCardAccessRequests')
            .where('requesterId', isEqualTo: requesterId)
            .where('targetUserId', isEqualTo: targetUserId)
            .where('status', isEqualTo: 'approved')
            .where('expiresAt', isGreaterThan: now)
            .limit(1)
            .get(),
      ]);
      final existingPending = results[0];
      final existingApproved = results[1];

      if (existingPending.docs.isNotEmpty) {
        debugPrint('⚠️ 이미 대기 중인 요청이 있습니다');
        ToastHelper.showWarning('이미 요청 중입니다. 응답을 기다려주세요.');
        return null;
      }

      if (existingApproved.docs.isNotEmpty) {
        debugPrint('⚠️ 이미 유효한 열람 권한이 있습니다');
        ToastHelper.showInfo('이미 열람 권한이 있습니다.');
        return existingApproved.docs.first.id;
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
      
      debugPrint('✅ [createIdCardAccessRequest] 요청 생성 완료: ${docRef.id}');
      ToastHelper.showSuccess('신분증 열람 요청을 보냈습니다');
      return docRef.id;
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

      // [특이사항] 관리자 2명이 동시에 승인 버튼을 탭하면 get→update 사이에 두 번째 get이
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
            requestId: requestId,
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

      // [특이사항] approveIdCardAccessRequest와 동일하게 트랜잭션 적용 — 관리자 2명이
      // 동시에 거절 버튼을 탭하면 중복 알림이 발송될 수 있으므로 pending 상태일 때만 처리.
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
            requestId: requestId,
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
  Future<IdCardAccessRequestModel?> checkIdCardAccess({
    required String requesterId,
    required String targetUserId,
  }) async {
    try {
      final snapshot = await _firestore
          .collection('idCardAccessRequests')
          .where('requesterId', isEqualTo: requesterId)
          .where('targetUserId', isEqualTo: targetUserId)
          .orderBy('requestedAt', descending: true)
          .limit(1)
          .get(const GetOptions(source: Source.server));

      if (snapshot.docs.isEmpty) return null;

      var request = IdCardAccessRequestModel.fromFirestore(snapshot.docs.first);

      // approved 상태인데 만료됐으면 Firestore 업데이트 + expired로 반환
      if (request.status == IdCardAccessStatus.approved && request.isExpired) {
        await _firestore
            .collection('idCardAccessRequests')
            .doc(request.id)
            .update({'status': 'expired'});
        request = IdCardAccessRequestModel(
          id: request.id,
          requesterId: request.requesterId,
          requesterName: request.requesterName,
          requesterBusinessId: request.requesterBusinessId,
          requesterBusinessName: request.requesterBusinessName,
          targetUserId: request.targetUserId,
          targetUserName: request.targetUserName,
          reason: request.reason,
          customReason: request.customReason,
          status: IdCardAccessStatus.expired,
          requestedAt: request.requestedAt,
          respondedAt: request.respondedAt,
          expiresAt: request.expiresAt,
          applicationId: request.applicationId,
          rejectionReason: request.rejectionReason,
        );
      }

      return request;
    } catch (e) {
      debugPrint('❌ 열람 권한 확인 실패: $e');
      return null;
    }
  }
  /// 사용자에게 온 신분증 열람 요청 조회 (지원자/근무자용)
  Future<List<IdCardAccessRequestModel>> getPendingIdCardRequestsForUser(String userId) async {
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
      debugPrint('❌ 신분증 요청 조회 실패: $e');
      return [];
    }
  }

  /// 사용자에게 온 계약해지 요청 조회 (근무자용)
  Future<List<ApplicationModel>> getMyTerminationRequests(String uid) async {
    try {
      final snapshot = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', whereIn: ['CONFIRMED', 'CONTRACT_PENDING'])
          .where('terminationStatus', isEqualTo: 'PENDING')
          .get();

      return snapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ 계약해지 요청 조회 실패: $e');
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
      debugPrint('❌ 내 요청 조회 실패: $e');
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
  
}