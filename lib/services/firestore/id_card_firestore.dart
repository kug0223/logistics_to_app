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
      
      // 1. 이미 대기 중인 요청이 있는지 확인
      final existingPending = await _firestore
          .collection('idCardAccessRequests')
          .where('requesterId', isEqualTo: requesterId)
          .where('targetUserId', isEqualTo: targetUserId)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();
      
      if (existingPending.docs.isNotEmpty) {
        debugPrint('⚠️ 이미 대기 중인 요청이 있습니다');
        ToastHelper.showWarning('이미 요청 중입니다. 응답을 기다려주세요.');
        return null;
      }
      
      // 2. 유효한 승인이 있는지 확인 — expiresAt > now 조건을 서버에서 필터링
      final now = Timestamp.fromDate(DateTime.now());
      final existingApproved = await _firestore
          .collection('idCardAccessRequests')
          .where('requesterId', isEqualTo: requesterId)
          .where('targetUserId', isEqualTo: targetUserId)
          .where('status', isEqualTo: 'approved')
          .where('expiresAt', isGreaterThan: now)
          .limit(1)
          .get();

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
      final doc = await docRef.get();
      
      if (!doc.exists) {
        debugPrint('❌ 요청을 찾을 수 없습니다');
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
      
      // 2. 알림 생성 — 실패해도 승인 결과에 영향 없음
      try {
        await createNotification(
          NotificationModel.createIdCardAccessApproved(
            userId: data['requesterId'],
            targetUserName: data['targetUserName'],
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
      final doc = await docRef.get();
      
      if (!doc.exists) {
        debugPrint('❌ 요청을 찾을 수 없습니다');
        return false;
      }
      
      final data = doc.data()!;
      
      // 1. 요청 상태 업데이트
      await docRef.update({
        'status': 'rejected',
        'respondedAt': FieldValue.serverTimestamp(),
        'rejectionReason': reason,
      });
      
      // 2. 알림 생성 — 실패해도 거절 결과에 영향 없음
      try {
        await createNotification(
          NotificationModel.createIdCardAccessRejected(
            userId: data['requesterId'],
            targetUserName: data['targetUserName'],
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
      debugPrint('❌ 대기 요청 조회 실패: $e');
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