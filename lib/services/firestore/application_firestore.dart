part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 지원서 관리 (Application Management) — slots 구조 기반
// ═══════════════════════════════════════════════════════════

extension ApplicationFirestore on FirestoreService {

  // ───────────────────────────────────────────────────────
  // 조회
  // ───────────────────────────────────────────────────────

  /// TO별 전체 지원서 조회
  Future<List<ApplicationModel>> getApplicationsByTOId(String toId, {String? businessId}) async {
    try {
      Query query = _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId);
      // businessId를 함께 필터링하면 Firestore 보안규칙 query-time 검증 가능
      if (businessId != null && businessId.isNotEmpty) {
        query = query.where('businessId', isEqualTo: businessId);
      }
      final snap = await query.get();
      return snap.docs
          .map((d) => ApplicationModel.fromFirestore(d))
          .toList();
    } catch (e) {
      debugPrint('❌ 지원자 목록 조회 실패: $e');
      return [];
    }
  }

  /// 슬롯별 지원서 조회 (flex 타입)
  Future<List<ApplicationModel>> getApplicationsBySlotId(
    String toId,
    String slotId,
  ) async {
    try {
      final snap = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .where('slotId', isEqualTo: slotId)
          .get();
      return snap.docs
          .map((d) => ApplicationModel.fromFirestore(d))
          .toList();
    } catch (e) {
      debugPrint('❌ 슬롯 지원자 목록 조회 실패: $e');
      return [];
    }
  }

  /// 여러 TO의 지원서 병렬 조회
  Future<Map<String, List<ApplicationModel>>> getApplicationsByTOIds(
    List<String> toIds,
  ) async {
    if (toIds.isEmpty) return {};
    try {
      final results = await Future.wait(
        toIds.map((id) async {
          final apps = await getApplicationsByTOId(id);
          return MapEntry(id, apps);
        }),
      );
      return Map.fromEntries(results);
    } catch (e) {
      debugPrint('❌ 배치 지원자 조회 실패: $e');
      return {};
    }
  }

  /// 사업장별 전체 지원서 조회 (관리자용)
  Future<List<ApplicationModel>> getApplicationsByBusinessId(
    String businessId,
  ) async {
    try {
      final snap = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .get();
      return snap.docs
          .map((d) => ApplicationModel.fromMap(d.data(), d.id))
          .toList();
    } catch (e) {
      debugPrint('❌ 사업장별 지원서 조회 실패: $e');
      return [];
    }
  }

  /// 내 지원 내역 조회 (사용자용)
  Future<List<ApplicationModel>> getMyApplications(String uid) async {
    try {
      final snap = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .orderBy('appliedAt', descending: true)
          .get();
      return snap.docs
          .map((d) => ApplicationModel.fromFirestore(d))
          .toList();
    } catch (e) {
      debugPrint('내 지원 내역 조회 실패: $e');
      return [];
    }
  }

  // ───────────────────────────────────────────────────────
  // 지원하기
  // ───────────────────────────────────────────────────────

  /// 공고 지원 (flex: slotId 필수, contract: slotId null)
  Future<bool> applyToTO({
    required String toId,
    String? slotId,
    required String businessId,
    required String businessName,
    required String toTitle,
    required DateTime workDate,
    required String uid,
    required String selectedWorkType,
    required String startTime,
    required String endTime,
    required int wage,
    String wageType = 'hourly',
    String? workTypeIcon,
    String? workTypeColor,
    String? workTypeBackgroundColor,
    // contract 전용
    DateTime? workEndDate,
    List<String>? workDays,
    DateTime? desiredStartDate,
  }) async {
    try {
      // ── 1. 사용자 서류 체크 ──
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (!userDoc.exists) {
        ToastHelper.showError('사용자 정보를 찾을 수 없습니다.');
        return false;
      }
      final userData = userDoc.data()!;
      if (userData['idCardImageUrl'] == null) {
        ToastHelper.showError('신분증 등록이 필요합니다.');
        return false;
      }
      if (userData['bankName'] == null || userData['accountNumber'] == null) {
        ToastHelper.showError('통장 정보 등록이 필요합니다.');
        return false;
      }
      if (userData['bankbookImageUrl'] == null) {
        ToastHelper.showError('통장사본 등록이 필요합니다.');
        return false;
      }

      // ── 1.5. TO / 슬롯 상태 · 마감 · 정원 체크 ──
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        ToastHelper.showError('공고를 찾을 수 없습니다.');
        return false;
      }
      final toData = toDoc.data()!;
      if (toData['isManualClosed'] == true || toData['status'] == 'CLOSED') {
        ToastHelper.showError('마감된 공고입니다.');
        return false;
      }

      if (slotId != null) {
        final slotDoc = await _firestore
            .collection('tos')
            .doc(toId)
            .collection('slots')
            .doc(slotId)
            .get();
        if (!slotDoc.exists) {
          ToastHelper.showError('해당 날짜 정보를 찾을 수 없습니다.');
          return false;
        }
        final slotData = slotDoc.data()!;
        if (slotData['isManualClosed'] == true || slotData['status'] == 'closed') {
          ToastHelper.showError('해당 날짜는 마감되었습니다.');
          return false;
        }
        // 업무유형별 정원·마감 체크 — 슬롯의 workDetails 기준
        final rawWorkDetails = slotData['workDetails'] as List<dynamic>? ?? [];
        final workDetailMap = rawWorkDetails
            .cast<Map<String, dynamic>>()
            .firstWhere(
              (d) => d['workType'] == selectedWorkType,
              orElse: () => {},
            );

        // 해당 업무의 마감 시각 체크
        final workDeadlineTs = workDetailMap['applicationDeadline'] as Timestamp?;
        if (workDeadlineTs != null && workDeadlineTs.toDate().isBefore(DateTime.now())) {
          ToastHelper.showError('해당 업무의 지원 마감 시간이 지났습니다.');
          return false;
        }

        final requiredCount = workDetailMap['requiredCount'] as int? ?? 0;

        final rawCounts = slotData['workTypeCounts'] as Map<String, dynamic>?;
        final workTypeCount = rawCounts?[selectedWorkType] as Map<String, dynamic>?;
        final confirmedCount = workTypeCount?['confirmedCount'] as int? ?? 0;

        if (requiredCount > 0 && confirmedCount >= requiredCount) {
          ToastHelper.showError('해당 업무의 모집 인원이 마감되었습니다.');
          return false;
        }
      } else {
        final toDeadline = toData['applicationDeadline'] as Timestamp?;
        if (toDeadline != null && toDeadline.toDate().isBefore(DateTime.now())) {
          ToastHelper.showError('지원 마감 시간이 지났습니다.');
          return false;
        }
        final confirmedCount = toData['totalConfirmed'] as int? ?? 0;
        final totalRequired = toData['totalRequired'] as int? ?? 0;
        if (totalRequired > 0 && confirmedCount >= totalRequired) {
          ToastHelper.showError('모집 인원이 마감되었습니다.');
          return false;
        }
      }

      // ── 2. 중복 지원 체크 ──
      final dupQuery = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .where('uid', isEqualTo: uid)
          .where('selectedWorkType', isEqualTo: selectedWorkType)
          .get();

      DocumentSnapshot? activeApp;
      DocumentSnapshot? reactivatableApp;

      for (final doc in dupQuery.docs) {
        if (slotId != null && doc.data()['slotId'] != slotId) continue;
        final data = doc.data();
        final status = data['status'] as String?;
        final isResignDone = ['APPROVED', 'AUTO_APPROVED']
            .contains(data['resignStatus']);
        final isTermDone = ['APPROVED', 'AUTO_APPROVED']
            .contains(data['terminationStatus']);
        if (isResignDone || isTermDone) continue;
        if (status == 'PENDING' || status == 'CONFIRMED') {
          activeApp = doc;
          break;
        }
        if (status == 'CANCELED' || status == 'REJECTED' ||
            status == 'AUTO_CANCELED') {
          reactivatableApp = doc;
        }
      }

      if (activeApp != null) {
        ToastHelper.showWarning('이미 지원한 업무입니다.');
        return false;
      }

      // ── 3. 시간 충돌 체크 ──
      final isContract = workDays != null && workDays.isNotEmpty;
      final confirmedSnap = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'CONFIRMED')
          .get();
      final allConfirmed = confirmedSnap.docs
          .map((d) => ApplicationModel.fromFirestore(d))
          .toList();

      if (isContract && workEndDate != null) {
        var current = desiredStartDate ?? workDate;
        while (!current.isAfter(workEndDate)) {
          final day = _getKoreanDayOfWeek(current);
          if (workDays.contains(day)) {
            for (final s in allConfirmed) {
              if (_isWorkingOnDate(s, current) &&
                  _hasTimeOverlap(startTime, endTime, s.startTime, s.endTime)) {
                ToastHelper.showError(
                  '${current.month}/${current.day}에\n'
                  '${s.startTime}~${s.endTime} (${s.businessName})\n'
                  '확정된 근무가 있어 지원할 수 없습니다.',
                );
                return false;
              }
            }
          }
          current = current.add(const Duration(days: 1));
        }
      } else {
        for (final s in allConfirmed) {
          if (_isWorkingOnDate(s, workDate) &&
              _hasTimeOverlap(startTime, endTime, s.startTime, s.endTime)) {
            ToastHelper.showError(
              '이미 ${s.startTime}~${s.endTime}에\n'
              '${s.businessName}에서 확정된 근무가 있습니다.',
            );
            return false;
          }
        }
      }

      // ── 4. 지원서 생성 / 재활성화 ──
      final batch = _firestore.batch();

      if (reactivatableApp != null) {
        batch.update(reactivatableApp.reference, {
          'status': 'PENDING',
          'appliedAt': FieldValue.serverTimestamp(),
          'statusHistory': FieldValue.arrayUnion([{
            'status': 'PENDING',
            'at': Timestamp.now(),
            'by': null,
            'action': 'REAPPLY',
          }]),
          'canceledAt': null,
          'cancelReason': null,
          'rejectedAt': null,
          'rejectedBy': null,
          'rejectMessage': null,
          'confirmedAt': null,
          'confirmedBy': null,
          if (desiredStartDate != null)
            'desiredStartDate': Timestamp.fromDate(desiredStartDate),
          if (workEndDate != null)
            'workEndDate': Timestamp.fromDate(workEndDate),
          if (workDays != null) 'workDays': workDays,
        });
        _incrementTOPending(batch, toId, slotId, delta: 1, workType: selectedWorkType);
        await batch.commit();
        clearCache(toId: toId);
        _sendNewApplicationNotification(
          businessId: businessId,
          applicantUid: uid,
          workType: selectedWorkType,
          workDate: workDate,
          applicationId: reactivatableApp.id,
          toId: toId,
        );
        debugPrint('✅ 재지원 완료: $toId');
        return true;
      }

      final appRef = _firestore.collection('applications').doc();
      batch.set(appRef, {
        'uid': uid,
        'businessId': businessId,
        'businessName': businessName,
        'toId': toId,
        if (slotId != null) 'slotId': slotId,
        'toTitle': toTitle,
        'selectedWorkType': selectedWorkType,
        'wage': wage,
        'wageType': wageType,
        'workTypeIcon': workTypeIcon,
        'workTypeColor': workTypeColor,
        'workTypeBackgroundColor': workTypeBackgroundColor,
        'workDate': Timestamp.fromDate(workDate),
        'startTime': startTime,
        'endTime': endTime,
        'status': 'PENDING',
        'appliedAt': FieldValue.serverTimestamp(),
        'statusHistory': [{
          'status': 'PENDING',
          'at': Timestamp.now(),
          'by': null,
          'action': 'APPLY',
        }],
        if (isContract) ...{
          'workEndDate': workEndDate != null
              ? Timestamp.fromDate(workEndDate)
              : null,
          'workDays': workDays,
          'desiredStartDate': desiredStartDate != null
              ? Timestamp.fromDate(desiredStartDate)
              : null,
        },
      });
      _incrementTOPending(batch, toId, slotId, delta: 1, workType: selectedWorkType);
      await batch.commit();
      clearCache(toId: toId);
      _sendNewApplicationNotification(
        businessId: businessId,
        applicantUid: uid,
        workType: selectedWorkType,
        workDate: workDate,
        applicationId: appRef.id,
        toId: toId,
      );
      debugPrint('✅ 지원 완료: $toTitle / $selectedWorkType');
      return true;
    } catch (e) {
      debugPrint('❌ 지원 실패: $e');
      ToastHelper.showError('지원 중 오류가 발생했습니다.');
      return false;
    }
  }

  // ───────────────────────────────────────────────────────
  // 상태 변경
  // ───────────────────────────────────────────────────────

  /// 지원자 확정 (충돌 지원서 자동 취소 포함)
  /// 반환: 충돌로 취소된 TO ID 목록
  Future<List<String>> updateApplicationStatus({
    required String applicationId,
    required String status,
    String? confirmedBy,
    String? rejectedBy,
    String? message,
  }) async {
    try {
      if (status == 'CONFIRMED') {
        return await _confirmWithConflictCheck(
          applicationId: applicationId,
          confirmedBy: confirmedBy,
          message: message,
        );
      }

      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();
      if (!appDoc.exists) return [];

      final appData = appDoc.data()!;
      final prevStatus = appData['status'] as String?;
      final toId = appData['toId'] as String?;
      final slotId = appData['slotId'] as String?;
      final selectedWorkType = appData['selectedWorkType'] as String?;

      final updates = <String, dynamic>{'status': status};
      if (status == 'REJECTED') {
        updates['rejectedAt'] = FieldValue.serverTimestamp();
        if (rejectedBy != null) updates['rejectedBy'] = rejectedBy;
        if (message != null) updates['rejectMessage'] = message;
        updates['statusHistory'] = FieldValue.arrayUnion([{
          'status': 'REJECTED',
          'at': Timestamp.now(),
          'by': rejectedBy,
          'action': 'REJECT',
          if (message != null) 'reason': message,
        }]);
      }

      final batch = _firestore.batch();
      batch.update(appDoc.reference, updates);

      if (toId != null) {
        if (prevStatus == 'CONFIRMED') {
          _decrementTOConfirmed(batch, toId, slotId, workType: selectedWorkType);
        } else if (prevStatus == 'PENDING') {
          _incrementTOPending(batch, toId, slotId, delta: -1, workType: selectedWorkType);
        }
      }

      await batch.commit();
      if (toId != null) clearCache(toId: toId);

      // 알림
      final applicantUid = appData['uid'] as String;
      if (prevStatus == 'CONFIRMED') {
        await createNotification(NotificationModel.createConfirmationCanceled(
          userId: applicantUid,
          businessName: appData['businessName'] as String,
          workType: appData['selectedWorkType'] as String,
          workDate: (appData['workDate'] as Timestamp).toDate(),
          applicationId: applicationId,
          cancelReason: message,
        ));
      } else if (prevStatus == 'PENDING' && status == 'REJECTED') {
        await createNotification(NotificationModel.createApplicationRejected(
          userId: applicantUid,
          businessName: appData['businessName'] as String,
          workType: appData['selectedWorkType'] as String,
          workDate: (appData['workDate'] as Timestamp).toDate(),
          applicationId: applicationId,
          rejectReason: message,
        ));
      }
      return [];
    } catch (e) {
      debugPrint('❌ 지원서 상태 업데이트 실패: $e');
      rethrow;
    }
  }

  /// 지원 취소 (사용자용 — PENDING 상태만)
  Future<bool> cancelApplication(String applicationId, String uid) async {
    try {
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();
      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }
      final appData = appDoc.data()!;
      if (appData['uid'] != uid) {
        ToastHelper.showError('본인의 지원서만 취소할 수 있습니다.');
        return false;
      }
      if (appData['status'] == 'CONFIRMED') {
        ToastHelper.showError('확정된 TO는 취소할 수 없습니다.\n관리자에게 문의해주세요.');
        return false;
      }

      final toId = appData['toId'] as String?;
      final slotId = appData['slotId'] as String?;
      final selectedWorkType = appData['selectedWorkType'] as String?;
      final batch = _firestore.batch();
      batch.update(appDoc.reference, {
        'status': 'CANCELED',
        'canceledAt': FieldValue.serverTimestamp(),
        'statusHistory': FieldValue.arrayUnion([{
          'status': 'CANCELED',
          'at': Timestamp.now(),
          'by': uid,
          'action': 'CANCEL',
        }]),
      });
      if (toId != null) {
        _incrementTOPending(batch, toId, slotId, delta: -1, workType: selectedWorkType);
      }
      await batch.commit();
      if (toId != null) clearCache(toId: toId);

      await _cleanupApplicationRelatedData(
        applicationId: applicationId,
        uid: uid,
      );
      if (toId != null) {
        _sendApplicationCanceledNotification(
          businessId: appData['businessId'] as String,
          applicantUid: uid,
          workType: appData['selectedWorkType'] as String? ?? '',
          workDate: (appData['workDate'] as Timestamp).toDate(),
          applicationId: applicationId,
          toId: toId,
        );
      }
      ToastHelper.showSuccess('지원이 취소되었습니다.');
      return true;
    } catch (e) {
      debugPrint('❌ 지원 취소 실패: $e');
      ToastHelper.showError('지원 취소에 실패했습니다.');
      return false;
    }
  }

  /// 확정된 지원 취소 (노쇼 패널티 포함, 관리자/사용자 공용)
  Future<bool> cancelConfirmedApplication(
    String applicationId, {
    bool applyNoShowPenalty = false,
    String? canceledBy,   // 관리자 UID (관리자가 취소할 때)
    String? cancelReason, // 관리자 취소 사유
  }) async {
    try {
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();
      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다');
        return false;
      }
      final appData = appDoc.data()!;
      final uid = appData['uid'] as String;
      if (appData['status'] != 'CONFIRMED') {
        ToastHelper.showError('확정된 지원만 취소할 수 있습니다');
        return false;
      }

      final toId = appData['toId'] as String?;
      final slotId = appData['slotId'] as String?;
      final selectedWorkType = appData['selectedWorkType'] as String?;
      final isAdminCancel = canceledBy != null;
      final batch = _firestore.batch();

      // 관리자 취소: ADMIN_CANCEL / 사용자 취소: USER_CANCELED / 노쇼: SAME_DAY_CANCEL
      final String reason = isAdminCancel
          ? 'ADMIN_CANCELED'
          : (applyNoShowPenalty ? 'SAME_DAY_CANCEL' : 'USER_CANCELED');
      final String action = isAdminCancel
          ? 'ADMIN_CANCEL_CONFIRMED'
          : 'CONFIRM_CANCEL';

      batch.update(appDoc.reference, {
        'status': 'CANCELED',
        'canceledAt': FieldValue.serverTimestamp(),
        'cancelReason': reason,
        if (isAdminCancel && cancelReason != null) 'cancelMessage': cancelReason,
        if (canceledBy != null) 'canceledBy': canceledBy,
        'statusHistory': FieldValue.arrayUnion([{
          'status': 'CANCELED',
          'at': Timestamp.now(),
          'by': canceledBy ?? uid,
          'action': action,
          'reason': cancelReason ?? reason,
        }]),
      });

      if (applyNoShowPenalty) {
        batch.update(_firestore.collection('users').doc(uid), {
          'noShowCount': FieldValue.increment(1),
        });
        final userDoc = await _firestore.collection('users').doc(uid).get();
        final currentNoShow = (userDoc.data()?['noShowCount'] ?? 0) as int;
        if (currentNoShow >= 2) {
          final restrictedUntil = DateTime.now().add(const Duration(days: 3));
          batch.update(_firestore.collection('users').doc(uid), {
            'restrictedUntil': Timestamp.fromDate(restrictedUntil),
            'noShowCount': 0,
          });
        }
      }

      if (toId != null) {
        _decrementTOConfirmed(batch, toId, slotId, workType: selectedWorkType);
      }
      await batch.commit();
      if (toId != null) clearCache(toId: toId);

      await _cleanupApplicationRelatedData(applicationId: applicationId, uid: uid);

      // 알림: 관리자 취소 시 확정취소 알림, 아닐 때는 별도 처리하지 않음
      if (isAdminCancel) {
        await createNotification(NotificationModel.createConfirmationCanceled(
          userId: uid,
          businessName: appData['businessName'] as String,
          workType: appData['selectedWorkType'] as String,
          workDate: (appData['workDate'] as Timestamp).toDate(),
          applicationId: applicationId,
          cancelReason: cancelReason,
        ));
      }

      debugPrint('✅ 확정 취소 완료 (관리자: $isAdminCancel, 패널티: $applyNoShowPenalty)');
      return true;
    } catch (e) {
      debugPrint('❌ 확정 취소 실패: $e');
      ToastHelper.showError('확정 취소에 실패했습니다');
      return false;
    }
  }

  /// 지원자 업무유형 변경 (관리자용)
  Future<bool> changeApplicationWorkType({
    required String applicationId,
    required String newWorkType,
    required int newWage,
    required String adminUID,
    String? newWorkDetailId,
  }) async {
    try {
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();
      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }
      final appData = appDoc.data()!;
      final currentWorkType = appData['selectedWorkType'] as String;
      final currentWage = appData['wage'] as int;
      final uid = appData['uid'] as String;
      final businessName = appData['businessName'] as String? ?? '';
      final workDate = (appData['workDate'] as Timestamp).toDate();

      await _firestore.collection('applications').doc(applicationId).update({
        'selectedWorkType': newWorkType,
        'wage': newWage,
        'originalWorkType': appData['originalWorkType'] ?? currentWorkType,
        'originalWage': appData['originalWage'] ?? currentWage,
        'changedAt': FieldValue.serverTimestamp(),
        'changedBy': adminUID,
      });
      _sendWorkTypeChangedNotification(
        applicantUid: uid,
        businessName: businessName,
        workDate: workDate,
        originalWorkType: currentWorkType,
        newWorkType: newWorkType,
        newWage: newWage,
        applicationId: applicationId,
      );
      ToastHelper.showSuccess('업무유형이 변경되었습니다.');
      return true;
    } catch (e) {
      debugPrint('❌ 업무유형 변경 실패: $e');
      ToastHelper.showError('업무유형 변경에 실패했습니다.');
      return false;
    }
  }

  // ───────────────────────────────────────────────────────
  // 일괄 처리
  // ───────────────────────────────────────────────────────

  /// 지원서 일괄 확정
  Future<BatchResult> batchConfirmApplications({
    required List<String> applicationIds,
    required String adminUID,
  }) async {
    if (applicationIds.isEmpty) return BatchResult(success: 0, failed: 0);
    int success = 0;
    int failed = 0;
    for (final id in applicationIds) {
      try {
        await updateApplicationStatus(
          applicationId: id,
          status: 'CONFIRMED',
          confirmedBy: adminUID,
        );
        success++;
      } catch (_) {
        failed++;
      }
    }
    return BatchResult(success: success, failed: failed);
  }

  // ───────────────────────────────────────────────────────
  // 충돌 체크
  // ───────────────────────────────────────────────────────

  Future<List<ApplicationModel>> findConflictingApplications({
    required String uid,
    required DateTime workDate,
    required String startTime,
    required String endTime,
    required String excludeId,
    String status = 'PENDING',
  }) async {
    try {
      final snap = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: status)
          .get();

      return snap.docs
          .where((d) => d.id != excludeId)
          .map((d) => ApplicationModel.fromFirestore(d))
          .where((a) => _isWorkingOnDate(a, workDate))
          .where((a) => _hasTimeOverlap(startTime, endTime, a.startTime, a.endTime))
          .toList();
    } catch (e) {
      debugPrint('❌ 충돌 지원서 조회 실패: $e');
      return [];
    }
  }

  Future<List<ApplicationModel>> getConfirmedSchedules({
    required String uid,
    required DateTime workDate,
  }) async {
    try {
      final snap = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'CONFIRMED')
          .get();
      return snap.docs
          .map((d) => ApplicationModel.fromFirestore(d))
          .where((a) => _isWorkingOnDate(a, workDate))
          .toList();
    } catch (e) {
      debugPrint('❌ 확정 일정 조회 실패: $e');
      return [];
    }
  }

  // ───────────────────────────────────────────────────────
  // 내부 헬퍼
  // ───────────────────────────────────────────────────────

  /// 확정 처리 (충돌 자동 취소 포함)
  Future<List<String>> _confirmWithConflictCheck({
    required String applicationId,
    String? confirmedBy,
    String? message,
  }) async {
    final appDoc = await _firestore
        .collection('applications')
        .doc(applicationId)
        .get();
    if (!appDoc.exists) throw Exception('지원서를 찾을 수 없습니다');

    final appData = appDoc.data()!;
    if (appData['status'] == 'CONFIRMED') return [];
    if (appData['status'] == 'CANCELED') {
      throw Exception('취소된 지원서는 확정할 수 없습니다');
    }

    final app = ApplicationModel.fromMap(appData, appDoc.id);
    final toId = appData['toId'] as String?;
    final slotId = appData['slotId'] as String?;

    if (toId == null) throw Exception('toId가 없는 지원서입니다');

    // 충돌 지원서 탐색
    List<ApplicationModel> conflictingApps;
    final isContract = app.workDays != null && app.workDays!.isNotEmpty;
    if (isContract && app.workEndDate != null) {
      conflictingApps = await _findConflictingForLongTerm(
        uid: app.uid,
        startDate: app.workDate,
        endDate: app.workEndDate!,
        workDays: app.workDays!,
        startTime: app.startTime,
        endTime: app.endTime,
        excludeId: applicationId,
      );
    } else {
      conflictingApps = await findConflictingApplications(
        uid: app.uid,
        workDate: app.workDate,
        startTime: app.startTime,
        endTime: app.endTime,
        excludeId: applicationId,
        status: 'PENDING',
      );
    }

    final batch = _firestore.batch();
    final now = FieldValue.serverTimestamp();

    // 확정 처리
    batch.update(appDoc.reference, {
      'status': 'CONFIRMED',
      'confirmedAt': now,
      if (confirmedBy != null) 'confirmedBy': confirmedBy,
      if (message != null) 'confirmMessage': message,
      'statusHistory': FieldValue.arrayUnion([{
        'status': 'CONFIRMED',
        'at': Timestamp.now(),
        'by': confirmedBy,
        'action': 'CONFIRM',
      }]),
    });

    // TO + Slot 통계 (PENDING→CONFIRMED)
    _incrementTOPending(batch, toId, slotId, delta: -1, workType: app.selectedWorkType);
    _incrementTOConfirmed(batch, toId, slotId, delta: 1, workType: app.selectedWorkType);

    // 충돌 지원서 자동 취소
    for (final conflict in conflictingApps) {
      batch.update(
        _firestore.collection('applications').doc(conflict.id),
        {
          'status': 'AUTO_CANCELED',
          'canceledAt': now,
          'cancelReason': 'SCHEDULE_CONFLICT',
          'conflictingAppId': applicationId,
          'conflictingBusiness': app.businessName,
          'conflictingTime': '${app.startTime}~${app.endTime}',
          'statusHistory': FieldValue.arrayUnion([{
            'status': 'AUTO_CANCELED',
            'at': Timestamp.now(),
            'by': 'SYSTEM',
            'action': 'AUTO_CANCEL',
            'reason': 'SCHEDULE_CONFLICT',
          }]),
        },
      );
    }

    await batch.commit();
    clearCache(toId: toId);

    // 충돌 지원서의 TO 통계 감소
    final Set<String> affectedTOIds = {};
    if (conflictingApps.isNotEmpty) {
      final statsBatch = _firestore.batch();
      for (final conflict in conflictingApps) {
        final cToId = conflict.toId;
        final cSlotId = conflict.slotId;
        if (cToId != null && cToId.isNotEmpty) {
          _incrementTOPending(statsBatch, cToId, cSlotId, delta: -1,
              workType: conflict.selectedWorkType);
          affectedTOIds.add(cToId);
          clearCache(toId: cToId);
        }
      }
      await statsBatch.commit();
    }

    // 알림
    await createNotification(NotificationModel.createApplicationConfirmed(
      userId: app.uid,
      businessName: app.businessName,
      workType: app.selectedWorkType,
      workDate: app.workDate,
      applicationId: applicationId,
    ));
    for (final conflict in conflictingApps) {
      _sendApplicationAutoCanceledNotification(
        applicantUid: conflict.uid,
        businessName: conflict.businessName,
        workType: conflict.selectedWorkType,
        workDate: conflict.workDate,
        applicationId: conflict.id,
        conflictingBusinessName: app.businessName,
        conflictingTime: '${app.startTime}~${app.endTime}',
      );
    }

    debugPrint('✅ 확정 완료 + ${conflictingApps.length}개 자동 취소');
    return affectedTOIds.toList();
  }

  Future<List<ApplicationModel>> _findConflictingForLongTerm({
    required String uid,
    required DateTime startDate,
    required DateTime endDate,
    required List<String> workDays,
    required String startTime,
    required String endTime,
    required String excludeId,
  }) async {
    try {
      final snap = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', isEqualTo: 'PENDING')
          .get();

      final conflicts = <ApplicationModel>{};
      var current = startDate;
      while (!current.isAfter(endDate)) {
        final day = _getKoreanDayOfWeek(current);
        if (workDays.contains(day)) {
          for (final doc in snap.docs) {
            if (doc.id == excludeId) continue;
            final a = ApplicationModel.fromFirestore(doc);
            if (_isWorkingOnDate(a, current) &&
                _hasTimeOverlap(startTime, endTime, a.startTime, a.endTime)) {
              conflicts.add(a);
            }
          }
        }
        current = current.add(const Duration(days: 1));
      }
      return conflicts.toList();
    } catch (e) {
      debugPrint('❌ 장기공고 충돌 조회 실패: $e');
      return [];
    }
  }

  /// TO.totalPending 및 Slot.pendingCount 변경
  void _incrementTOPending(
    WriteBatch batch,
    String toId,
    String? slotId, {
    required int delta,
    String? workType,
  }) {
    batch.update(_firestore.collection('tos').doc(toId), {
      'totalPending': FieldValue.increment(delta),
    });
    if (slotId != null) {
      final slotRef = _firestore
          .collection('tos')
          .doc(toId)
          .collection('slots')
          .doc(slotId);
      final slotUpdate = <String, dynamic>{
        'pendingCount': FieldValue.increment(delta),
      };
      if (workType != null) {
        slotUpdate['workTypeCounts.$workType.pendingCount'] =
            FieldValue.increment(delta);
      }
      batch.update(slotRef, slotUpdate);
    }
  }

  /// TO.totalConfirmed 및 Slot.confirmedCount 변경
  void _incrementTOConfirmed(
    WriteBatch batch,
    String toId,
    String? slotId, {
    required int delta,
    String? workType,
  }) {
    batch.update(_firestore.collection('tos').doc(toId), {
      'totalConfirmed': FieldValue.increment(delta),
    });
    if (slotId != null) {
      final slotRef = _firestore
          .collection('tos')
          .doc(toId)
          .collection('slots')
          .doc(slotId);
      final slotUpdate = <String, dynamic>{
        'confirmedCount': FieldValue.increment(delta),
      };
      if (workType != null) {
        slotUpdate['workTypeCounts.$workType.confirmedCount'] =
            FieldValue.increment(delta);
      }
      batch.update(slotRef, slotUpdate);
    }
  }

  void _decrementTOConfirmed(
    WriteBatch batch,
    String toId,
    String? slotId, {
    String? workType,
  }) =>
      _incrementTOConfirmed(batch, toId, slotId, delta: -1, workType: workType);

  // ───────────────────────────────────────────────────────
  // 연관 데이터 정리
  // ───────────────────────────────────────────────────────

  Future<void> _cleanupApplicationRelatedData({
    required String applicationId,
    required String uid,
    WriteBatch? batch,
  }) async {
    final useBatch = batch != null;
    final localBatch = batch ?? _firestore.batch();
    try {
      final idCardRequests = await _firestore
          .collection('idCardAccessRequests')
          .where('applicationId', isEqualTo: applicationId)
          .where('status', isEqualTo: 'pending')
          .get();
      for (final doc in idCardRequests.docs) {
        localBatch.update(doc.reference, {
          'status': 'canceled',
          'canceledAt': FieldValue.serverTimestamp(),
          'cancelReason': 'APPLICATION_CANCELED',
        });
      }
      final scheduleRequests = await _firestore
          .collection('scheduleChangeRequests')
          .where('applicationId', isEqualTo: applicationId)
          .where('status', isEqualTo: 'PENDING')
          .get();
      for (final doc in scheduleRequests.docs) {
        localBatch.update(doc.reference, {
          'status': 'CANCELED',
          'canceledAt': FieldValue.serverTimestamp(),
          'cancelReason': 'APPLICATION_CANCELED',
        });
      }
      if (!useBatch) await localBatch.commit();
    } catch (e) {
      debugPrint('❌ 연관 데이터 정리 실패: $e');
    }
  }

  // ───────────────────────────────────────────────────────
  // 알림 헬퍼
  // ───────────────────────────────────────────────────────

  Future<void> _sendNewApplicationNotification({
    required String businessId,
    required String applicantUid,
    required String workType,
    required DateTime workDate,
    required String applicationId,
    required String toId,
  }) async {
    try {
      final businessDoc =
          await _firestore.collection('businesses').doc(businessId).get();
      if (!businessDoc.exists) return;
      final adminUid = businessDoc.data()?['ownerId'] as String?;
      if (adminUid == null || adminUid.isEmpty) return;
      final userDoc =
          await _firestore.collection('users').doc(applicantUid).get();
      final applicantName = userDoc.data()?['name'] as String? ?? '지원자';
      await createNotification(NotificationModel.createNewApplication(
        userId: adminUid,
        applicantName: applicantName,
        workType: workType,
        workDate: workDate,
        applicationId: applicationId,
        toId: toId,
        businessId: businessId,
        workDetailId: '',
      ));
    } catch (e) {
      debugPrint('⚠️ 신규 지원 알림 전송 실패: $e');
    }
  }

  Future<void> _sendApplicationCanceledNotification({
    required String businessId,
    required String applicantUid,
    required String workType,
    required DateTime workDate,
    required String applicationId,
    required String toId,
  }) async {
    try {
      final businessDoc =
          await _firestore.collection('businesses').doc(businessId).get();
      if (!businessDoc.exists) return;
      final adminUid = businessDoc.data()?['ownerId'] as String?;
      if (adminUid == null || adminUid.isEmpty) return;
      final userDoc =
          await _firestore.collection('users').doc(applicantUid).get();
      final applicantName = userDoc.data()?['name'] as String? ?? '지원자';
      await createNotification(NotificationModel.createApplicationCanceled(
        userId: adminUid,
        applicantName: applicantName,
        workType: workType,
        workDate: workDate,
        applicationId: applicationId,
        businessId: businessId,
        toId: toId,
        workDetailId: '',
      ));
    } catch (e) {
      debugPrint('⚠️ 지원 취소 알림 전송 실패: $e');
    }
  }

  Future<void> _sendApplicationAutoCanceledNotification({
    required String applicantUid,
    required String businessName,
    required String workType,
    required DateTime workDate,
    required String applicationId,
    required String conflictingBusinessName,
    required String conflictingTime,
  }) async {
    try {
      await createNotification(NotificationModel.createApplicationAutoCanceled(
        userId: applicantUid,
        businessName: businessName,
        workType: workType,
        workDate: workDate,
        applicationId: applicationId,
        conflictingBusinessName: conflictingBusinessName,
        conflictingTime: conflictingTime,
      ));
    } catch (e) {
      debugPrint('⚠️ 자동 취소 알림 전송 실패: $e');
    }
  }

  Future<void> _sendWorkTypeChangedNotification({
    required String applicantUid,
    required String businessName,
    required DateTime workDate,
    required String originalWorkType,
    required String newWorkType,
    required int newWage,
    required String applicationId,
  }) async {
    try {
      await createNotification(NotificationModel.createWorkTypeChanged(
        userId: applicantUid,
        businessName: businessName,
        workDate: workDate,
        originalWorkType: originalWorkType,
        newWorkType: newWorkType,
        newWage: newWage,
        applicationId: applicationId,
      ));
    } catch (e) {
      debugPrint('⚠️ 파트 변경 알림 전송 실패: $e');
    }
  }
}
