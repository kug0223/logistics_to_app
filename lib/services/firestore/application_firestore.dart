part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 지원서 관리 (Application Management) — slots 구조 기반
// ═══════════════════════════════════════════════════════════

extension ApplicationFirestore on FirestoreService {

  // ───────────────────────────────────────────────────────
  // 조회
  // ───────────────────────────────────────────────────────

  /// TO별 지원서 조회
  /// [statuses] 지정 시 해당 상태만 조회 (미지정 시 전체)
  Future<List<ApplicationModel>> getApplicationsByTOId(
    String toId, {
    String? businessId,
    List<String>? statuses,
  }) async {
    try {
      Query query = _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId);
      if (businessId != null && businessId.isNotEmpty) {
        query = query.where('businessId', isEqualTo: businessId);
      }
      if (statuses != null && statuses.isNotEmpty) {
        query = query.where('status', whereIn: statuses);
      }
      final snap = await query.limit(500).get();
      return snap.docs
          .map((d) => ApplicationModel.fromFirestore(d))
          .toList();
    } catch (e) {
      debugPrint('❌ 지원자 목록 조회 실패: $e');
      return [];
    }
  }

  /// 슬롯별 지원서 조회 (flex 타입)
  /// [statuses] 지정 시 해당 상태만 조회 (미지정 시 전체)
  Future<List<ApplicationModel>> getApplicationsBySlotId(
    String toId,
    String slotId, {
    String? businessId,
    List<String>? statuses,
  }) async {
    try {
      Query query = _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .where('slotId', isEqualTo: slotId);
      if (businessId != null && businessId.isNotEmpty) {
        query = query.where('businessId', isEqualTo: businessId);
      }
      if (statuses != null && statuses.isNotEmpty) {
        query = query.where('status', whereIn: statuses);
      }
      final snap = await query.limit(500).get();
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
          .orderBy('appliedAt', descending: true)
          .limit(1000)
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
    // TTL 캐시 — 1분 내 동일 uid 재조회 시 캐시 반환
    final cached = _myApplicationsCache[uid];
    final ts = _myApplicationsCacheTimestamps[uid];
    if (cached != null && ts != null &&
        DateTime.now().difference(ts) < FirestoreService._myApplicationsCacheTTL) {
      return cached;
    }
    try {
      final snap = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .orderBy('appliedAt', descending: true)
          .limit(200)
          .get();
      final result = snap.docs
          .map((d) => ApplicationModel.fromFirestore(d))
          .toList();
      _myApplicationsCache[uid] = result;
      _myApplicationsCacheTimestamps[uid] = DateTime.now();
      return result;
    } catch (e) {
      debugPrint('내 지원 내역 조회 실패: $e');
      return cached ?? []; // 캐시 만료 후 실패 시 기존 캐시 반환
    }
  }

  /// 내 지원 내역 페이지네이션 조회 (내 지원 화면 전용)
  ///
  /// [startAfter] cursor — null이면 첫 페이지
  /// 반환: {items, lastDoc, hasMore}
  Future<Map<String, dynamic>> getMyApplicationsPaged({
    required String uid,
    int pageSize = 20,
    DocumentSnapshot? startAfter,
    String? statusFilter, // null = 전체, 'active', 'inactive'
  }) async {
    try {
      Query query = _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .orderBy('appliedAt', descending: true);

      if (statusFilter == 'active') {
        query = query.where('status', whereIn: AppStatus.activeStates);
      } else if (statusFilter == 'inactive') {
        query = query.where('status', whereIn: AppStatus.inactiveStates);
      }

      query = query.limit(pageSize);
      if (startAfter != null) query = query.startAfterDocument(startAfter);

      final snap = await query.get();
      return {
        'items': snap.docs.map((d) => ApplicationModel.fromFirestore(d)).toList(),
        'lastDoc': snap.docs.isNotEmpty ? snap.docs.last : null,
        'hasMore': snap.docs.length == pageSize,
      };
    } catch (e) {
      debugPrint('지원 내역 페이지 조회 실패: $e');
      return {'items': <ApplicationModel>[], 'lastDoc': null, 'hasMore': false};
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
    String? workDetailId,
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
    NetworkChecker.instance.assertOnline('지원하려면 인터넷 연결이 필요합니다.');
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

      // ── 1.1. 블랙리스트 체크 ──
      if (userData['isBlacklisted'] == true) {
        final reason = userData['blacklistReason'] as String? ?? '이용 정책 위반';
        ToastHelper.showError('이용 제한된 계정입니다.\n사유: $reason\n고객센터에 문의해주세요.');
        return false;
      }

      // ── 1.2. 이메일 인증 체크 ──
      if (userData['isEmailVerified'] != true) {
        ToastHelper.showError('이메일 인증이 필요합니다.\n설정 > 이메일 인증에서 완료해주세요.');
        return false;
      }

      // ── 1.3. 신분증 인증 체크 (단기 공고 지원 시 필수) ──
      // 장기공고(contract type)는 계약서 서명 시 신분증 확인하므로 여기서는 단기만 체크
      if (userData['isIdVerified'] != true) {
        ToastHelper.showError('신분증 인증 후 지원할 수 있습니다.\n설정 > 서류 관리에서 신분증을 등록해주세요.');
        return false;
      }

      // ── 1.4. 제재 상태 체크 ──
      final restrictedUntilTs = userData['restrictedUntil'] as Timestamp?;
      if (restrictedUntilTs != null && restrictedUntilTs.toDate().isAfter(DateTime.now())) {
        final restrictedDate = restrictedUntilTs.toDate().toLocal();
        final remainDays = restrictedDate.difference(DateTime.now()).inDays + 1;
        ToastHelper.showError('무단 결근 페널티로 $remainDays일 동안 지원이 제한됩니다.\n(해제일: ${restrictedDate.month}/${restrictedDate.day})');
        return false;
      }

      // ── 1.5. TO / 슬롯 상태 · 마감 · 정원 체크 ──
      final toDoc = await _firestore.collection('tos').doc(toId).get();
      if (!toDoc.exists) {
        ToastHelper.showError('공고를 찾을 수 없습니다.');
        return false;
      }
      final toData = toDoc.data()!;
      if (toData['status'] == TOStatus.draft) {
        ToastHelper.showError('비공개 공고에는 지원할 수 없습니다.');
        return false;
      }
      if (toData['isManualClosed'] == true || toData['status'] == TOStatus.closed) {
        ToastHelper.showError('마감된 공고입니다.');
        return false;
      }
      // 게시 기간 만료 또는 지원 마감일 경과 체크 (contract 타입)
      final toModel = TOModel.fromMap(toData, toId);
      if (toModel.isPostingExpired || toModel.isDeadlinePassed) {
        ToastHelper.showError('지원 마감된 공고입니다.');
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
        if (slotData['isManualClosed'] == true || slotData['status'] == SlotStatus.closed) {
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

        final requiredCount = (workDetailMap['requiredCount'] as num?)?.toInt() ?? 0;

        final rawCounts = slotData['workTypeCounts'] as Map<String, dynamic>?;
        final workTypeCount = rawCounts?[selectedWorkType] as Map<String, dynamic>?;
        final confirmedCount = (workTypeCount?['confirmedCount'] as num?)?.toInt() ?? 0;

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
        final confirmedCount = (toData['totalConfirmed'] as num?)?.toInt() ?? 0;
        final totalRequired = (toData['totalRequired'] as num?)?.toInt() ?? 0;
        if (totalRequired > 0 && confirmedCount >= totalRequired) {
          ToastHelper.showError('모집 인원이 마감되었습니다.');
          return false;
        }
        // 업무유형별 정원 초과 체크 (contract TO)
        final rawWorkDetails = toData['workDetails'] as List<dynamic>? ?? [];
        final workTypeConfirmed = ((toData['workTypeConfirmedCounts'] as Map<String, dynamic>? ?? {})[selectedWorkType] as num?)?.toInt() ?? 0;
        for (final wd in rawWorkDetails.cast<Map<String, dynamic>>()) {
          if (wd['workType'] == selectedWorkType) {
            final workTypeRequired = (wd['requiredCount'] as num?)?.toInt() ?? 0;
            if (workTypeRequired > 0 && workTypeConfirmed >= workTypeRequired) {
              ToastHelper.showError('해당 업무의 모집 인원이 마감되었습니다.');
              return false;
            }
            break;
          }
        }
      }

      // ── 2. 중복 지원 체크 ──
      Query<Map<String, dynamic>> dupQ = _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .where('uid', isEqualTo: uid)
          .where('selectedWorkType', isEqualTo: selectedWorkType);
      if (slotId != null) {
        dupQ = dupQ.where('slotId', isEqualTo: slotId);
      }
      final dupQuery = await dupQ.get();

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
        if (AppStatus.activeStates.contains(status)) {
          activeApp = doc;
          break;
        }
        if (AppStatus.inactiveStates.contains(status)) {
          reactivatableApp = doc;
        }
      }

      if (activeApp != null) {
        ToastHelper.showWarning('이미 지원한 업무입니다.');
        return false;
      }

      // ── 3. 시간 충돌 체크 ──
      final toType = toData['type'] as String? ?? TOType.flex;
      final isContract = toType == TOType.contract || (workDays != null && workDays.isNotEmpty);
      final confirmedSnap = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', whereIn: AppStatus.confirmedStatuses)
          .get();
      final allConfirmed = confirmedSnap.docs
          .map((d) => ApplicationModel.fromFirestore(d))
          .toList();

      if (isContract && workEndDate != null && workDays != null && workDays.isNotEmpty) {
        // 장기 충돌 체크: 날짜 루프 대신 기존 확정 지원서 레벨 검사 O(confirmedApps)
        final newStart = DateTime.fromMillisecondsSinceEpoch(
            (desiredStartDate ?? workDate).millisecondsSinceEpoch);
        final newStartOnly = DateTime(newStart.year, newStart.month, newStart.day);
        final newEndOnly   = DateTime(workEndDate.year, workEndDate.month, workEndDate.day);

        for (final s in allConfirmed) {
          if (!ApplicationModel.hasTimeOverlap(startTime, endTime, s.startTime, s.endTime)) {
            continue;
          }
          if (s.isLongTermApplication) {
            final sEnd = s.actualResignDate ?? s.workEndDate;
            if (sEnd == null) continue;
            final sStartOnly = DateTime(s.workDate.year, s.workDate.month, s.workDate.day);
            final sEndOnly   = DateTime(sEnd.year, sEnd.month, sEnd.day);
            if (newEndOnly.isBefore(sStartOnly) || newStartOnly.isAfter(sEndOnly)) continue;
            final sWorkDays = s.workDays ?? [];
            if (!workDays.any((d) => sWorkDays.contains(d))) continue;
            final conflictDay = workDays.firstWhere((d) => sWorkDays.contains(d));
            ToastHelper.showError(
              '매주 $conflictDay에\n'
              '${s.startTime}~${s.endTime} (${s.businessName})\n'
              '확정된 근무가 있어 지원할 수 없습니다.',
            );
            return false;
          } else {
            // 단기 확정 지원서
            final sDate = DateTime(s.workDate.year, s.workDate.month, s.workDate.day);
            if (sDate.isBefore(newStartOnly) || sDate.isAfter(newEndOnly)) continue;
            if (!workDays.contains(FormatHelper.weekday(s.workDate))) continue;
            ToastHelper.showError(
              '${s.workDate.month}/${s.workDate.day}에\n'
              '${s.startTime}~${s.endTime} (${s.businessName})\n'
              '확정된 근무가 있어 지원할 수 없습니다.',
            );
            return false;
          }
        }
      } else {
        for (final s in allConfirmed) {
          if (s.isWorkingOnDate(workDate) &&
              ApplicationModel.hasTimeOverlap(startTime, endTime, s.startTime, s.endTime)) {
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
          'type': isContract ? AppType.longTerm : AppType.shortTerm,
          'appliedAt': FieldValue.serverTimestamp(),
          // 재지원 날짜·슬롯 정보 갱신 (다른 날짜/슬롯으로 재지원 시 정합성 보장)
          'workDate': Timestamp.fromDate(workDate),
          if (slotId != null) 'slotId': slotId,
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
          // 이전 자동취소 충돌 정보 초기화
          'conflictingAppId': null,
          'conflictingBusiness': null,
          'conflictingTime': null,
          // 이전 퇴사/해지 이력 초기화
          'resignStatus': null,
          'resignRequestedAt': null,
          'resignRequestDate': null,
          'actualResignDate': null,
          'terminationStatus': null,
          'terminationRequestedAt': null,
          'terminationEffectiveDate': null,
          'terminationRejectReason': null,
          if (workDetailId != null && workDetailId.isNotEmpty) 'workDetailId': workDetailId,
          if (desiredStartDate != null)
            'desiredStartDate': Timestamp.fromDate(desiredStartDate),
          if (workEndDate != null)
            'workEndDate': Timestamp.fromDate(workEndDate),
          if (workDays != null) 'workDays': workDays,
        });
        _incrementTOPending(batch, toId, slotId, delta: 1, workType: selectedWorkType);
        await batch.commit();
        clearCache(toId: toId);
        invalidateMyApplicationsCache(uid);
        try {
          _sendNewApplicationNotification(
            businessId: businessId,
            applicantUid: uid,
            workType: selectedWorkType,
            workDate: workDate,
            applicationId: reactivatableApp.id,
            toId: toId,
          );
        } catch (notifErr) {
          debugPrint('⚠️ 재지원 알림 전송 실패 (지원은 완료됨): $notifErr');
        }
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
        if (workDetailId != null && workDetailId.isNotEmpty) 'workDetailId': workDetailId,
        'wage': wage,
        'wageType': wageType,
        'workTypeIcon': workTypeIcon,
        'workTypeColor': workTypeColor,
        'workTypeBackgroundColor': workTypeBackgroundColor,
        'workDate': Timestamp.fromDate(workDate),
        'startTime': startTime,
        'endTime': endTime,
        'status': 'PENDING',
        'type': isContract ? 'long_term' : 'short',
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
      // 최종 정원/마감 재검증 — TOCTOU 방지 (read-check 이후 상태가 변경됐을 수 있음)
      if (slotId != null) {
        final slotRef = _firestore.collection('tos').doc(toId).collection('slots').doc(slotId);
        await _firestore.runTransaction((tx) async {
          final snap = await tx.get(slotRef);
          if (!snap.exists) throw Exception('해당 날짜 정보를 찾을 수 없습니다.');
          final d = snap.data()!;
          if (d['isManualClosed'] == true || d['status'] == SlotStatus.closed) {
            throw Exception('방금 마감된 날짜입니다.');
          }
          final rawWD = d['workDetails'] as List<dynamic>? ?? [];
          final wd = rawWD.cast<Map<String, dynamic>>()
              .firstWhere((x) => x['workType'] == selectedWorkType, orElse: () => {});
          final deadlineTs = wd['applicationDeadline'] as Timestamp?;
          if (deadlineTs != null && deadlineTs.toDate().isBefore(DateTime.now())) {
            throw Exception('방금 마감된 업무입니다.');
          }
          final req = (wd['requiredCount'] as num?)?.toInt() ?? 0;
          final rawCounts = d['workTypeCounts'] as Map<String, dynamic>?;
          final cnt = ((rawCounts?[selectedWorkType] as Map<String, dynamic>?)?['confirmedCount'] as num?)?.toInt() ?? 0;
          if (req > 0 && cnt >= req) throw Exception('방금 마감된 업무입니다. (정원 초과)');
        });
      } else {
        // Contract TO (슬롯 없음): TO 문서 기준 최종 정원·마감 재검증
        final toRef = _firestore.collection('tos').doc(toId);
        await _firestore.runTransaction((tx) async {
          final snap = await tx.get(toRef);
          if (!snap.exists) throw Exception('공고를 찾을 수 없습니다.');
          final d = snap.data()!;
          if (d['isManualClosed'] == true || d['status'] == TOStatus.closed) {
            throw Exception('방금 마감된 공고입니다.');
          }
          final deadlineTs = d['applicationDeadline'] as Timestamp?;
          if (deadlineTs != null && deadlineTs.toDate().isBefore(DateTime.now())) {
            throw Exception('지원 마감 시간이 지났습니다.');
          }
          final confirmedCount = (d['totalConfirmed'] as num?)?.toInt() ?? 0;
          final totalRequired = (d['totalRequired'] as num?)?.toInt() ?? 0;
          if (totalRequired > 0 && confirmedCount >= totalRequired) {
            throw Exception('방금 마감된 공고입니다. (정원 초과)');
          }
          final rawWorkDetails = d['workDetails'] as List<dynamic>? ?? [];
          final confirmedCounts = d['workTypeConfirmedCounts'] as Map<String, dynamic>?;
          final workTypeConfirmed = (confirmedCounts?[selectedWorkType] as num?)?.toInt() ?? 0;
          for (final wd in rawWorkDetails.cast<Map<String, dynamic>>()) {
            if (wd['workType'] == selectedWorkType) {
              final workTypeRequired = (wd['requiredCount'] as num?)?.toInt() ?? 0;
              if (workTypeRequired > 0 && workTypeConfirmed >= workTypeRequired) {
                throw Exception('방금 마감된 업무입니다. (정원 초과)');
              }
              break;
            }
          }
        });
      }

      _incrementTOPending(batch, toId, slotId, delta: 1, workType: selectedWorkType);
      await batch.commit();
      clearCache(toId: toId);
      invalidateMyApplicationsCache(uid); // 내 지원 목록 캐시 무효화
      try {
        _sendNewApplicationNotification(
          businessId: businessId,
          applicantUid: uid,
          workType: selectedWorkType,
          workDate: workDate,
          applicationId: appRef.id,
          toId: toId,
        );
      } catch (notifErr) {
        debugPrint('⚠️ 지원 알림 전송 실패 (지원은 완료됨): $notifErr');
      }
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
      if (status == AppStatus.confirmed) {
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

      // 확정/계약 서명 상태는 거절로 전이 불가 (cancelConfirmedApplication() 사용)
      if (status == AppStatus.rejected &&
          (AppStatus.confirmedStatuses.contains(prevStatus) ||
           prevStatus == AppStatus.contractPending)) {
        ToastHelper.showError('확정된 지원서는 거절할 수 없습니다.\n취소 처리를 이용해주세요.');
        return [];
      }

      final updates = <String, dynamic>{'status': status};
      if (status == AppStatus.rejected) {
        updates['rejectedAt'] = FieldValue.serverTimestamp();
        if (rejectedBy != null) updates['rejectedBy'] = rejectedBy;
        if (message != null) updates['rejectMessage'] = message;
        final newEntry = {
          'status': 'REJECTED',
          'at': Timestamp.now(),
          'by': rejectedBy,
          'action': 'REJECT',
          if (message != null) 'reason': message,
        };
        final history = _appendHistory(appData, newEntry);
        updates['statusHistory'] = history;
      }

      final batch = _firestore.batch();
      batch.update(appDoc.reference, updates);

      if (toId != null) {
        if (AppStatus.confirmedStatuses.contains(prevStatus)) {
          _decrementTOConfirmed(batch, toId, slotId, workType: selectedWorkType);
          // confirmed → pending 롤백 시 pendingCount도 복원
          if (status == AppStatus.pending) {
            _incrementTOPending(batch, toId, slotId, delta: 1, workType: selectedWorkType);
          }
        } else if (prevStatus == AppStatus.pending) {
          _incrementTOPending(batch, toId, slotId, delta: -1, workType: selectedWorkType);
        }
      }

      await batch.commit();
      if (toId != null) clearCache(toId: toId);

      // 알림
      final applicantUid = appData['uid'] as String;
      if (AppStatus.confirmedStatuses.contains(prevStatus)) {
        await createNotification(NotificationModel.createConfirmationCanceled(
          userId: applicantUid,
          businessName: appData['businessName'] as String,
          businessId: appData['businessId'] as String? ?? '',
          workType: appData['selectedWorkType'] as String,
          workDate: (appData['workDate'] as Timestamp?)?.toDate().toLocal() ?? DateTime.now(),
          applicationId: applicationId,
          cancelReason: message,
        ));
      } else if (prevStatus == AppStatus.pending && status == AppStatus.rejected) {
        await createNotification(NotificationModel.createApplicationRejected(
          userId: applicantUid,
          businessName: appData['businessName'] as String,
          businessId: appData['businessId'] as String? ?? '',
          workType: appData['selectedWorkType'] as String,
          workDate: (appData['workDate'] as Timestamp?)?.toDate().toLocal() ?? DateTime.now(),
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
    NetworkChecker.instance.assertOnline('지원 취소를 하려면 인터넷 연결이 필요합니다.');
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
      final currentStatus = appData['status'] as String?;
      if (AppStatus.confirmedStatuses.contains(currentStatus)) {
        ToastHelper.showError('확정된 TO는 취소할 수 없습니다.\n관리자에게 문의해주세요.');
        return false;
      }
      // REJECTED/AUTO_CANCELED 는 이미 비활성 — pendingCount 이중 감소 방지
      if (AppStatus.inactiveStates.contains(currentStatus)) {
        ToastHelper.showInfo('이미 취소된 지원서입니다.');
        return true;
      }

      final toId = appData['toId'] as String?;
      final slotId = appData['slotId'] as String?;
      final selectedWorkType = appData['selectedWorkType'] as String?;
      final batch = _firestore.batch();
      batch.update(appDoc.reference, {
        'status': 'CANCELED',
        'canceledAt': FieldValue.serverTimestamp(),
        'statusHistory': _appendHistory(appData, {
          'status': 'CANCELED',
          'at': Timestamp.now(),
          'by': uid,
          'action': 'CANCEL',
        }),
      });
      if (toId != null) {
        _incrementTOPending(batch, toId, slotId, delta: -1, workType: selectedWorkType);
      }
      await batch.commit();
      if (toId != null) clearCache(toId: toId);
      invalidateMyApplicationsCache(uid); // 내 지원 목록 캐시 무효화

      await _cleanupApplicationRelatedData(
        applicationId: applicationId,
        uid: uid,
      );
      if (toId != null) {
        _sendApplicationCanceledNotification(
          businessId: appData['businessId'] as String,
          applicantUid: uid,
          workType: appData['selectedWorkType'] as String? ?? '',
          workDate: (appData['workDate'] as Timestamp?)?.toDate().toLocal() ?? DateTime.now(),
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
    NetworkChecker.instance.assertOnline('확정 취소를 하려면 인터넷 연결이 필요합니다.');
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
      if (!AppStatus.confirmedStatuses.contains(appData['status'])) {
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
        'statusHistory': _appendHistory(appData, {
          'status': 'CANCELED',
          'at': Timestamp.now(),
          'by': canceledBy ?? uid,
          'action': action,
          'reason': cancelReason ?? reason,
        }),
      });

      if (toId != null) {
        _decrementTOConfirmed(batch, toId, slotId, workType: selectedWorkType);
      }
      await batch.commit();
      if (toId != null) clearCache(toId: toId);

      // 노쇼 페널티: 배치 후 별도 트랜잭션으로 카운트 원자적 갱신
      if (applyNoShowPenalty) {
        await _applyNoShowPenaltyTransactional(uid);
      }

      // 취소 후 슬롯 상태('full'→'open') 재계산
      if (toId != null && slotId != null) {
        await _recalculateSlotStatus(toId, slotId);
      }

      await _cleanupApplicationRelatedData(applicationId: applicationId, uid: uid);

      // 알림: 관리자 취소 시 확정취소 알림, 아닐 때는 별도 처리하지 않음
      if (isAdminCancel) {
        await createNotification(NotificationModel.createConfirmationCanceled(
          userId: uid,
          businessName: appData['businessName'] as String,
          businessId: appData['businessId'] as String? ?? '',
          workType: appData['selectedWorkType'] as String,
          workDate: (appData['workDate'] as Timestamp?)?.toDate().toLocal() ?? DateTime.now(),
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
      final currentWage = (appData['wage'] as num?)?.toInt() ?? 0;
      final uid = appData['uid'] as String;
      final businessName = appData['businessName'] as String? ?? '';
      final businessId = appData['businessId'] as String? ?? '';
      final workDate = (appData['workDate'] as Timestamp).toDate().toLocal();
      final toId = appData['toId'] as String?;
      final slotId = appData['slotId'] as String?;
      final currentStatus = appData['status'] as String? ?? '';

      if (currentWorkType == newWorkType) {
        ToastHelper.showError('동일한 업무유형입니다.');
        return false;
      }

      // 새 업무유형의 모집인원 초과 여부 경고 (차단하지 않음 — 관리자 의도 허용)
      if (toId != null && slotId != null) {
        final slotSnap = await _firestore
            .collection('tos').doc(toId)
            .collection('slots').doc(slotId).get();
        if (slotSnap.exists) {
          final slotData = slotSnap.data()!;
          final workDetails = (slotData['workDetails'] as List? ?? [])
              .cast<Map<String, dynamic>>();
          final wd = workDetails.firstWhere(
            (d) => d['workType'] == newWorkType, orElse: () => {});
          final required = (wd['requiredCount'] as num?)?.toInt() ?? 0;
          final counts = slotData['workTypeCounts'] as Map<String, dynamic>?;
          final confirmed = (counts?[newWorkType]?['confirmedCount'] as num?)?.toInt() ?? 0;
          if (required > 0 && confirmed >= required) {
            ToastHelper.showWarning(
              '[$newWorkType] 모집인원($required명)이 이미 찼습니다. 그래도 변경됩니다.');
          }
        }
      } else if (toId != null && slotId == null) {
        final toSnap = await _firestore.collection('tos').doc(toId).get();
        if (toSnap.exists) {
          final toData = toSnap.data()!;
          final workDetails = (toData['workDetails'] as List? ?? [])
              .cast<Map<String, dynamic>>();
          final wd = workDetails.firstWhere(
            (d) => d['workType'] == newWorkType, orElse: () => {});
          final required = (wd['requiredCount'] as num?)?.toInt() ?? 0;
          final confirmedCounts = toData['workTypeConfirmedCounts']
              as Map<String, dynamic>?;
          final confirmed = (confirmedCounts?[newWorkType] as num?)?.toInt() ?? 0;
          if (required > 0 && confirmed >= required) {
            ToastHelper.showWarning(
              '[$newWorkType] 모집인원($required명)이 이미 찼습니다. 그래도 변경됩니다.');
          }
        }
      }

      final batch = _firestore.batch();

      // 지원서 업데이트
      batch.update(_firestore.collection('applications').doc(applicationId), {
        'selectedWorkType': newWorkType,
        'wage': newWage,
        'originalWorkType': appData['originalWorkType'] ?? currentWorkType,
        'originalWage': appData['originalWage'] ?? currentWage,
        'changedAt': FieldValue.serverTimestamp(),
        'changedBy': adminUID,
        if (newWorkDetailId != null) 'workDetailId': newWorkDetailId,
      });

      // workTypeCounts 카운터 동기화 (슬롯 기반 단기TO)
      if (toId != null && slotId != null) {
        final slotRef = _firestore.collection('tos').doc(toId).collection('slots').doc(slotId);
        if (AppStatus.confirmedStatuses.contains(currentStatus)) {
          batch.update(slotRef, {
            'workTypeCounts.$currentWorkType.confirmedCount': FieldValue.increment(-1),
            'workTypeCounts.$newWorkType.confirmedCount': FieldValue.increment(1),
          });
        } else if (currentStatus == AppStatus.pending) {
          batch.update(slotRef, {
            'workTypeCounts.$currentWorkType.pendingCount': FieldValue.increment(-1),
            'workTypeCounts.$newWorkType.pendingCount': FieldValue.increment(1),
          });
        }
      }

      // workTypeConfirmedCounts 카운터 동기화 (슬롯 없는 장기TO)
      if (toId != null && slotId == null && AppStatus.confirmedStatuses.contains(currentStatus)) {
        batch.update(_firestore.collection('tos').doc(toId), {
          'workTypeConfirmedCounts.$currentWorkType': FieldValue.increment(-1),
          'workTypeConfirmedCounts.$newWorkType': FieldValue.increment(1),
        });
      }

      await batch.commit();
      if (toId != null) clearCache(toId: toId);

      _sendWorkTypeChangedNotification(
        applicantUid: uid,
        businessName: businessName,
        businessId: businessId,
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
      } catch (e) {
        debugPrint('❌ 지원서 일괄 확정 실패 ($id): $e');
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
    List<String>? statuses,
    String? businessId,
  }) async {
    try {
      final statusFilter = statuses ?? [AppStatus.pending, AppStatus.contractPending];
      var query = _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', whereIn: statusFilter);
      if (businessId != null) {
        query = query.where('businessId', isEqualTo: businessId);
      }
      final snap = await query.get();

      return snap.docs
          .where((d) => d.id != excludeId)
          .map((d) => ApplicationModel.fromFirestore(d))
          .where((a) => a.isWorkingOnDate(workDate))
          .where((a) => ApplicationModel.hasTimeOverlap(startTime, endTime, a.startTime, a.endTime))
          .toList();
    } catch (e) {
      debugPrint('❌ 충돌 지원서 조회 실패: $e');
      return [];
    }
  }

  /// 특정 날짜 × 사업장의 확정 근무자 조회 (단기 + 장기 병합)
  Future<List<ApplicationModel>> getConfirmedWorkersByDateAndBusiness({
    required DateTime date,
    required String businessId,
  }) async {
    final dateStart = DateTime(date.year, date.month, date.day);
    final dateEnd = dateStart.add(const Duration(days: 1));

    try {
      final shortTermFuture = _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', whereIn: [AppStatus.confirmed, AppStatus.contractPending])
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .where('workDate', isLessThan: Timestamp.fromDate(dateEnd))
          .get();

      final longTermFuture = _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', whereIn: [AppStatus.confirmed, AppStatus.contractPending])
          .where('workEndDate', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .get();

      final results = await Future.wait([shortTermFuture, longTermFuture]);

      final shortTermApps = results[0].docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();

      final longTermCandidates = results[1].docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .where((app) => app.workDays != null && app.workDays!.isNotEmpty)
          .toList();

      final result = <ApplicationModel>[...shortTermApps];

      final dayWeekday = FormatHelper.weekday(date);

      for (final app in longTermCandidates) {
        final endDate = app.actualResignDate ?? app.workEndDate;
        if (endDate == null) continue;

        DateTime effectiveStart = app.desiredStartDate ?? app.workDate;
        if (app.confirmedAt != null && app.desiredStartDate == null) {
          final confirmedDay = DateTime(
              app.confirmedAt!.year, app.confirmedAt!.month, app.confirmedAt!.day);
          if (confirmedDay.isAfter(app.workDate)) effectiveStart = confirmedDay;
        }

        final startOnly = DateTime(effectiveStart.year, effectiveStart.month, effectiveStart.day);
        final endOnly = DateTime(endDate.year, endDate.month, endDate.day);

        if (dateStart.isBefore(startOnly) || dateStart.isAfter(endOnly)) continue;

        if (app.leaveDates != null && app.leaveDates!.isNotEmpty) {
          final isLeave = app.leaveDates!.any((d) =>
              d.year == dateStart.year && d.month == dateStart.month && d.day == dateStart.day);
          if (isLeave) continue;
        }

        if (app.workDays!.contains(dayWeekday)) result.add(app);
      }

      return result;
    } catch (e) {
      debugPrint('❌ 확정 근무자 조회 실패: $e');
      return [];
    }
  }

  Future<List<ApplicationModel>> getConfirmedSchedules({
    required String uid,
    required DateTime workDate,
  }) async {
    try {
      final dateStart = DateTime(workDate.year, workDate.month, workDate.day);
      final dateEnd = dateStart.add(const Duration(days: 1));

      // 단기: 정확한 날짜 필터로 Firestore 쿼리 최소화
      final shortTermFuture = _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', whereIn: AppStatus.confirmedStatuses)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .where('workDate', isLessThan: Timestamp.fromDate(dateEnd))
          .get();

      // 장기: workEndDate >= 오늘인 것만 조회 (과거 종료된 계약 제외)
      final longTermFuture = _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', whereIn: AppStatus.confirmedStatuses)
          .where('workEndDate', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .get();

      final results = await Future.wait([shortTermFuture, longTermFuture]);
      final shortTerm = results[0].docs.map((d) => ApplicationModel.fromFirestore(d)).toList();
      final longTermCandidates = results[1].docs
          .map((d) => ApplicationModel.fromFirestore(d))
          .where((a) => a.isLongTermApplication)
          .where((a) => a.isWorkingOnDate(workDate))
          .toList();

      // 단기는 date가 정확히 맞으므로 isWorkingOnDate 재확인 불필요
      return [...shortTerm, ...longTermCandidates];
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
    NetworkChecker.instance.assertOnline('지원자 확정을 하려면 인터넷 연결이 필요합니다.');
    final appRef = _firestore.collection('applications').doc(applicationId);

    // 트랜잭션으로 상태 체크 + CONTRACT_PENDING 선점 — 동시 확정 요청 방지
    bool alreadyConfirmed = false;
    await _firestore.runTransaction((tx) async {
      final fresh = await tx.get(appRef);
      if (!fresh.exists) throw Exception('지원서를 찾을 수 없습니다');
      final status = fresh.data()?['status'] as String?;
      if (AppStatus.confirmedStatuses.contains(status)) {
        alreadyConfirmed = true;
        return;
      }
      if (status == AppStatus.canceled) {
        throw Exception('취소된 지원서는 확정할 수 없습니다');
      }
      if (status == AppStatus.autoCanceled) {
        throw Exception('자동 취소된 지원서는 확정할 수 없습니다');
      }
      // 상태를 CONTRACT_PENDING으로 선점 → 두 번째 요청은 alreadyConfirmed=true 반환
      tx.update(appRef, {
        'status': 'CONTRACT_PENDING',
        'confirmedAt': FieldValue.serverTimestamp(),
        if (confirmedBy != null) 'confirmedBy': confirmedBy,
      });
    });
    if (alreadyConfirmed) return [];

    // 선점 후 최신 문서 재조회 (workDays, workEndDate 등 필요)
    final appDoc = await appRef.get();
    if (!appDoc.exists) throw Exception('지원서를 찾을 수 없습니다');
    final appData = appDoc.data()!;

    final app = ApplicationModel.fromMap(appData, appDoc.id);
    final toId = appData['toId'] as String?;
    final slotId = appData['slotId'] as String?;

    if (toId == null) throw Exception('toId가 없는 지원서입니다');

    // ── TO 로드 (계약기간 계산 + 충돌 탐색에 사용) ──
    final toDoc = await _firestore.collection('tos').doc(toId).get();
    final toModel = toDoc.exists ? TOModel.fromMap(toDoc.data()!, toDoc.id) : null;

    // ── 장기공고 확정 시 workEndDate 자동 계산 ──
    // (지원 시 workEndDate가 null인 경우: apply_dialog 경유 or preset period TO)
    DateTime? computedWorkEndDate = app.workEndDate;
    List<String>? computedWorkDays = app.workDays;
    final isLongTermApp = app.applicationType == AppType.longTerm ||
        (app.workDays != null && app.workDays!.isNotEmpty);
    if (isLongTermApp && computedWorkEndDate == null && toModel != null) {
      final startDate = app.desiredStartDate ?? app.workDate;
      if (toModel.contractPeriodType != null && toModel.contractPeriodType != 'custom') {
        computedWorkEndDate = toModel.computeContractEndDate(startDate);
      } else if (toModel.rangeEnd != null) {
        computedWorkEndDate = toModel.rangeEnd;
      }
    }
    // workDays 미설정 시 TO에서 보완
    if ((computedWorkDays == null || computedWorkDays.isEmpty) &&
        toModel != null && toModel.workDays.isNotEmpty) {
      computedWorkDays = toModel.workDays;
    }

    // ── 모집 인원 초과 여부 경고 (차단하지 않음 — 관리자 의도적 초과 확정 허용) ──
    if (slotId != null) {
      final slotSnap = await _firestore
          .collection('tos').doc(toId)
          .collection('slots').doc(slotId).get();
      if (slotSnap.exists) {
        final slotData = slotSnap.data()!;
        final workType = app.selectedWorkType;
        final workDetails = (slotData['workDetails'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        final wd = workDetails.firstWhere(
          (d) => d['workType'] == workType, orElse: () => {});
        final required = (wd['requiredCount'] as num?)?.toInt() ?? 0;
        final counts = slotData['workTypeCounts'] as Map<String, dynamic>?;
        final confirmed = (counts?[workType]?['confirmedCount'] as num?)?.toInt() ?? 0;
        if (required > 0 && confirmed >= required) {
          ToastHelper.showWarning(
            '[$workType] 모집인원($required명)이 이미 찼습니다. 초과 확정됩니다.');
        }
      }
    } else if (toModel != null) {
      // 장기 TO (슬롯 없음) — workTypeConfirmedCounts 확인
      final workType = app.selectedWorkType;
      final workDetails = (toModel.workDetails)
          .where((d) => d.workType == workType);
      if (workDetails.isNotEmpty) {
        final required = workDetails.first.requiredCount;
        final confirmedCounts = toDoc.data()?['workTypeConfirmedCounts']
            as Map<String, dynamic>?;
        final confirmed = (confirmedCounts?[workType] as num?)?.toInt() ?? 0;
        if (required > 0 && confirmed >= required) {
          ToastHelper.showWarning(
            '[$workType] 모집인원($required명)이 이미 찼습니다. 초과 확정됩니다.');
        }
      }
    }

    // 충돌 지원서 탐색 (타사 포함 전체 검색)
    List<ApplicationModel> conflictingApps;
    if (isLongTermApp && computedWorkEndDate != null && computedWorkDays != null && computedWorkDays.isNotEmpty) {
      conflictingApps = await _findConflictingForLongTerm(
        uid: app.uid,
        startDate: app.desiredStartDate ?? app.workDate,
        endDate: computedWorkEndDate,
        workDays: computedWorkDays,
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
      );
    }

    final batch = _firestore.batch();
    final now = FieldValue.serverTimestamp();

    // 확정 상태는 위 트랜잭션에서 이미 CONTRACT_PENDING으로 선점됨
    // 배치에서는 추가 필드(확인 메시지·기간·요일·statusHistory)만 보완
    batch.update(appDoc.reference, {
      if (message != null) 'confirmMessage': message,
      if (computedWorkEndDate != null)
        'workEndDate': Timestamp.fromDate(computedWorkEndDate),
      if (computedWorkDays != null && (app.workDays == null || app.workDays!.isEmpty))
        'workDays': computedWorkDays,
      'statusHistory': FieldValue.arrayUnion([{
        'status': 'CONTRACT_PENDING',
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

    // 확정 후 슬롯 상태('open'↔'full') 재계산
    if (slotId != null) {
      await _recalculateSlotStatus(toId, slotId);
    }

    // 충돌 지원서의 TO 통계 감소
    final Set<String> affectedTOIds = {};
    if (conflictingApps.isNotEmpty) {
      final statsBatch = _firestore.batch();
      for (final conflict in conflictingApps) {
        final cToId = conflict.toId;
        final cSlotId = conflict.slotId;
        if (cToId != null && cToId.isNotEmpty) {
          // CONTRACT_PENDING는 이미 확정인원으로 집계됨 → confirmedCount 감소
          final isConfirmed = AppStatus.confirmedStatuses.contains(conflict.status);
          if (isConfirmed) {
            _decrementTOConfirmed(statsBatch, cToId, cSlotId,
                workType: conflict.selectedWorkType);
          } else {
            _incrementTOPending(statsBatch, cToId, cSlotId, delta: -1,
                workType: conflict.selectedWorkType);
          }
          affectedTOIds.add(cToId);
          clearCache(toId: cToId);
        }
      }
      await statsBatch.commit();
    }

    // 알림 — 계약서 서명 요청 알림은 saveEmployerSignature()에서 발송됨
    for (final conflict in conflictingApps) {
      _sendApplicationAutoCanceledNotification(
        applicantUid: conflict.uid,
        businessName: conflict.businessName,
        businessId: conflict.businessId,
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
      // 타사 포함 전체 PENDING·CONTRACT_PENDING·CONFIRMED 조회 — businessId 필터 없음
      // CONFIRMED도 포함: 단기 확정 근무자와도 충돌 방지
      final snap = await _firestore
          .collection('applications')
          .where('uid', isEqualTo: uid)
          .where('status', whereIn: [AppStatus.pending, AppStatus.contractPending, AppStatus.confirmed])
          .get();

      final startOnly = DateTime(startDate.year, startDate.month, startDate.day);
      final endOnly   = DateTime(endDate.year,   endDate.month,   endDate.day);

      final result = <ApplicationModel>[];

      for (final doc in snap.docs) {
        if (doc.id == excludeId) continue;
        final a = ApplicationModel.fromFirestore(doc);

        // 시간 겹침 먼저 확인 (빠른 탈락)
        if (!ApplicationModel.hasTimeOverlap(startTime, endTime, a.startTime, a.endTime)) {
          continue;
        }

        if (a.isLongTermApplication) {
          // 장기 지원 — 근무 기간 + 요일 겹침 확인
          final aEndDate = a.actualResignDate ?? a.workEndDate;
          if (aEndDate == null) continue;
          final aStart = DateTime(a.workDate.year, a.workDate.month, a.workDate.day);
          final aEnd   = DateTime(aEndDate.year,   aEndDate.month,   aEndDate.day);

          // 기간 겹침
          if (endOnly.isBefore(aStart) || startOnly.isAfter(aEnd)) continue;

          // 근무 요일 겹침
          final aWorkDays = a.workDays ?? [];
          if (aWorkDays.isEmpty) continue;
          if (!workDays.any((d) => aWorkDays.contains(d))) continue;

          result.add(a);
        } else {
          // 단기 지원 — 날짜가 새 계약 범위 내 + 해당 요일 포함
          final aDate = DateTime(a.workDate.year, a.workDate.month, a.workDate.day);
          if (aDate.isBefore(startOnly) || aDate.isAfter(endOnly)) continue;
          if (!workDays.contains(FormatHelper.weekday(a.workDate))) continue;

          result.add(a);
        }
      }
      return result;
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
    final toUpdate = <String, dynamic>{
      'totalConfirmed': FieldValue.increment(delta),
    };
    // contract TO: 업무유형별 확정인원 추적 (슬롯 없는 경우)
    if (slotId == null && workType != null && workType.isNotEmpty) {
      toUpdate['workTypeConfirmedCounts.$workType'] = FieldValue.increment(delta);
    }
    batch.update(_firestore.collection('tos').doc(toId), toUpdate);
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
  // 노쇼 페널티 원자적 갱신
  // ───────────────────────────────────────────────────────

  /// 노쇼 카운트를 트랜잭션으로 원자적으로 증가시키고 3회 도달 시 제한 적용.
  /// 배치 외부에서 호출해 동시 요청 시 카운트 중복 증가를 방지한다.
  Future<void> _applyNoShowPenaltyTransactional(String uid) async {
    try {
      final userRef = _firestore.collection('users').doc(uid);
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(userRef);
        final current = (snap.data()?['noShowCount'] as num?)?.toInt() ?? 0;
        final next = current + 1;
        if (next >= 3) {
          final restrictedUntil =
              DateTime.now().add(const Duration(days: 3));
          tx.update(userRef, {
            'noShowCount': 0,
            'restrictedUntil': Timestamp.fromDate(restrictedUntil),
          });
          debugPrint('⚠️ 노쇼 3회 — 3일 이용 제한 적용: $uid');
        } else {
          tx.update(userRef, {'noShowCount': next});
        }
      });
    } catch (e) {
      debugPrint('❌ 노쇼 카운트 업데이트 실패: $e');
    }
  }

  // ───────────────────────────────────────────────────────
  // 슬롯 상태 재계산
  // ───────────────────────────────────────────────────────

  /// 확정 인원 변경 후 슬롯 status('open'↔'full') 재계산
  /// CLOSED 슬롯은 건드리지 않음
  Future<void> _recalculateSlotStatus(String toId, String slotId) async {
    final slotRef = _firestore
        .collection('tos').doc(toId)
        .collection('slots').doc(slotId);
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(slotRef);
        if (!snap.exists) return;
        final data = snap.data()!;
        if (data['status'] == 'closed') return; // 마감 슬롯은 유지
        final confirmed = (data['confirmedCount'] as num?)?.toInt() ?? 0;
        final workDetails = data['workDetails'] as List? ?? [];
        final totalRequired = workDetails.fold<int>(
          0, (acc, d) => acc + (((d as Map<String, dynamic>)['requiredCount'] as num?)?.toInt() ?? 0));
        if (totalRequired <= 0) return;
        final newStatus = confirmed >= totalRequired ? 'full' : 'open';
        if (data['status'] != newStatus) {
          tx.update(slotRef, {'status': newStatus});
        }
      });
    } catch (e) {
      debugPrint('⚠️ 슬롯 상태 재계산 실패 ($slotId): $e');
    }
  }

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
        localBatch.update(doc.reference, {'status': 'canceled'});
      }
      final scheduleRequests = await _firestore
          .collection('schedule_change_requests')
          .where('applicationId', isEqualTo: applicationId)
          .where('status', isEqualTo: 'PENDING')
          .get();
      for (final doc in scheduleRequests.docs) {
        localBatch.update(doc.reference, {'status': 'CANCELED'});
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
    required String businessId,
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
        businessId: businessId,
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
    required String businessId,
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
        businessId: businessId,
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

  /// 특정 필드만 업데이트
  Future<void> updateApplicationFields(
    String applicationId,
    Map<String, dynamic> fields,
  ) async {
    await _firestore.collection('applications').doc(applicationId).update(fields);
  }

  /// 계약 연장: 기존 Application 기반으로 새 Application 생성
  Future<ApplicationModel> createRenewedApplication({
    required ApplicationModel original,
    required DateTime newStartDate,
    required DateTime newEndDate,
  }) async {
    final ref = _firestore.collection('applications').doc();
    final now = DateTime.now();
    // copyWith으로 기본 필드 복사 후, null로 초기화해야 할 필드는
    // map을 직접 수정 (copyWith null-coalescing 패턴 우회)
    final base = original.copyWith(
      workDate: newStartDate,
      workEndDate: newEndDate,
      confirmedAt: now,
      appliedAt: now,
      renewedFromApplicationId: original.id,
    );
    final data = base.toMap()
      ..['status'] = AppStatus.contractPending   // 근무자 서명 완료 시 CONFIRMED로 전환
      ..['renewalDecision'] = null
      ..['renewalNotifiedAt'] = null
      ..['desiredStartDate'] = null
      ..['statusHistory'] = []
      ..['resignStatus'] = null
      ..['resignRequestedAt'] = null
      ..['resignRequestDate'] = null
      ..['actualResignDate'] = null
      ..['terminationStatus'] = null
      ..['terminationRequestedAt'] = null
      ..['terminationEffectiveDate'] = null
      ..['terminationRejectReason'] = null;
    await ref.set(data);
    return ApplicationModel.fromMap(data, ref.id);
  }

  /// statusHistory 배열에 새 항목 추가 후 최근 20개만 유지
  /// arrayUnion 대신 사용 — 문서 크기 폭증 방지
  List<Map<String, dynamic>> _appendHistory(
    Map<String, dynamic> appData,
    Map<String, dynamic> newEntry,
  ) {
    final raw = appData['statusHistory'] as List? ?? [];
    final history = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    history.add(newEntry);
    if (history.length > 20) {
      return history.sublist(history.length - 20);
    }
    return history;
  }
}
