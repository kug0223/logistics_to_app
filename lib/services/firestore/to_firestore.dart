part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 공고(TO) 서비스 — slots 구조 기반
// ═══════════════════════════════════════════════════════════

extension TOFirestore on FirestoreService {

  // ───────────────────────────────────────────────────────
  // 단일 조회
  // ───────────────────────────────────────────────────────

  /// 공고 단건 조회 (workDetails 배열 포함)
  Future<TOModel?> getTO(String toId) async {
    try {
      final doc = await _firestore.collection('tos').doc(toId).get();
      if (!doc.exists) return null;
      return TOModel.fromMap(doc.data()!, doc.id);
    } catch (e) {
      debugPrint('❌ [TO] 공고 조회 실패: $e');
      return null;
    }
  }

  // ───────────────────────────────────────────────────────
  // 목록 조회
  // ───────────────────────────────────────────────────────

  /// 사업장 공고 목록 (관리자용)
  Future<List<TOModel>> getTOsByBusiness(
    String businessId, {
    bool activeOnly = false,
    bool closedOnly = false,
  }) async {
    try {
      Query query = _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .orderBy('createdAt', descending: true);

      if (activeOnly) {
        query = query.where('status', whereIn: ['ACTIVE', 'FULL', 'SCHEDULED']);
      } else if (closedOnly) {
        query = query.where('status', whereIn: ['CLOSED', 'EXPIRED']);
      }

      final snap = await query.get();
      return snap.docs.map((d) => TOModel.fromMap(d.data() as Map<String, dynamic>, d.id)).toList();
    } catch (e) {
      debugPrint('❌ [TO] 사업장 공고 목록 조회 실패: $e');
      return [];
    }
  }

  /// 공개 공고 목록 (지원자용 — isPublished: true 만)
  Future<List<TOModel>> getPublishedTOs() async {
    try {
      final snap = await _firestore
          .collection('tos')
          .where('isPublished', isEqualTo: true)
          .where('status', whereIn: ['ACTIVE', 'FULL'])
          .orderBy('createdAt', descending: true)
          .get();

      return snap.docs.map((d) => TOModel.fromMap(d.data(), d.id)).toList();
    } catch (e) {
      debugPrint('❌ [TO] 공개 공고 목록 조회 실패: $e');
      return [];
    }
  }

  /// 최근 등록 공고 (기존 공고 연결용)
  Future<List<TOModel>> getRecentTOsByBusiness(
    String businessId, {
    int days = 60,
  }) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      final snap = await _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff))
          .orderBy('createdAt', descending: true)
          .limit(20)
          .get();

      return snap.docs.map((d) => TOModel.fromMap(d.data(), d.id)).toList();
    } catch (e) {
      debugPrint('❌ [TO] 최근 공고 조회 실패: $e');
      return [];
    }
  }

  // ───────────────────────────────────────────────────────
  // 생성
  // ───────────────────────────────────────────────────────

  /// 공고 생성 (flex: slots 동시 생성 / contract: 슬롯 없음)
  Future<String?> createTO({
    required String businessId,
    required String businessName,
    required String title,
    String? groupTitle,
    String? description,
    required String type, // 'flex' | 'contract'
    required List<WorkDetailData> workDetails,
    required String creatorUID,

    // flex 전용
    List<DateTime>? dates,
    String deadlineType = 'HOURS_BEFORE',
    int hoursBeforeStart = 2,
    DateTime? fixedDeadline, // FIXED_TIME 용

    // contract 전용
    DateTime? rangeStart,
    DateTime? rangeEnd,
    List<String>? workDays,
    DateTime? contractDeadline,

    // 예약 공개
    String publishMode = 'immediate',
    int? publishDaysBefore,
    String? publishTime,
  }) async {
    try {
      // 사업장 주소 조회
      String? businessAddress, businessCity, businessDistrict;
      try {
        final biz = await getBusinessById(businessId);
        businessAddress = biz?.address;
        businessCity = biz?.city;
        businessDistrict = biz?.district;
      } catch (_) {}

      // 전체 필요 인원 (flex: 슬롯 수 × 1개 슬롯 기준, contract: 단일 값)
      final perSlotRequired = workDetails.fold<int>(0, (s, d) => s + d.requiredCount);
      final totalRequired = type == 'flex'
          ? perSlotRequired * (dates?.length ?? 1)
          : perSlotRequired;

      // 예약 공개 시각 계산
      DateTime? publishAt;
      bool isPublished = publishMode == 'immediate';

      if (publishMode == 'scheduled' && publishDaysBefore != null && publishTime != null) {
        final baseDate = type == 'flex'
            ? (dates?.reduce((a, b) => a.isBefore(b) ? a : b) ?? DateTime.now())
            : (rangeStart ?? DateTime.now());

        final parts = publishTime.split(':');
        final candidate = DateTime(
          baseDate.year, baseDate.month, baseDate.day,
          int.parse(parts[0]), int.parse(parts[1]),
        ).subtract(Duration(days: publishDaysBefore));

        if (candidate.isBefore(DateTime.now())) {
          isPublished = true; // 과거 시간이면 즉시 공개
        } else {
          publishAt = candidate;
        }
      }

      // TO 문서 생성
      final toData = TOModel(
        id: '',
        businessId: businessId,
        businessName: businessName,
        businessAddress: businessAddress,
        businessCity: businessCity,
        businessDistrict: businessDistrict,
        type: type,
        title: title,
        groupTitle: (groupTitle?.isNotEmpty == true) ? groupTitle : null,
        description: description,
        workDetails: workDetails,
        totalSlots: type == 'flex' ? (dates?.length ?? 0) : 0,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        workDays: workDays ?? const [],
        deadlineType: deadlineType,
        hoursBeforeStart: hoursBeforeStart,
        applicationDeadline: contractDeadline,
        totalRequired: totalRequired,
        publishMode: publishMode,
        publishAt: publishAt,
        isPublished: isPublished,
        publishDaysBefore: publishDaysBefore,
        publishTime: publishTime,
        creatorUID: creatorUID,
        createdAt: DateTime.now(),
        status: isPublished ? 'ACTIVE' : 'SCHEDULED',
      ).toMap()
        ..['createdAt'] = FieldValue.serverTimestamp()
        ..['statusUpdatedAt'] = FieldValue.serverTimestamp();

      final toDoc = await _firestore.collection('tos').add(toData);
      debugPrint('✅ [TO] 공고 생성: ${toDoc.id}');

      // flex: slots 생성 — 실패 시 TO 문서도 롤백 삭제
      if (type == 'flex' && dates != null && dates.isNotEmpty) {
        try {
          await _createSlots(
            toId: toDoc.id,
            dates: dates,
            workDetails: workDetails,
            deadlineType: deadlineType,
            hoursBeforeStart: hoursBeforeStart,
            fixedDeadline: fixedDeadline,
            publishMode: publishMode,
            publishDaysBefore: publishDaysBefore,
            publishTime: publishTime,
          );
        } catch (e) {
          debugPrint('⚠️ [TO] 슬롯 생성 실패 — TO 문서 롤백: ${toDoc.id}');
          await toDoc.delete();
          rethrow;
        }
      }

      return toDoc.id;
    } catch (e) {
      debugPrint('❌ [TO] 공고 생성 실패: $e');
      return null;
    }
  }

  // ───────────────────────────────────────────────────────
  // 수정
  // ───────────────────────────────────────────────────────

  Future<void> updateTO(String toId, Map<String, dynamic> updates) async {
    try {
      await _firestore.collection('tos').doc(toId).update(updates);
      clearCache(toId: toId);
    } catch (e) {
      debugPrint('❌ [TO] 공고 수정 실패: $e');
      rethrow;
    }
  }

  // ───────────────────────────────────────────────────────
  // 삭제
  // ───────────────────────────────────────────────────────

  Future<Map<String, dynamic>> checkTOBeforeDelete(
    String toId, {
    required String businessId,
  }) async {
    try {
      final apps = await getApplicationsByTOId(toId, businessId: businessId);
      final confirmed = apps.where((a) => a.status == 'CONFIRMED').length;
      return {
        'hasApplicants': apps.isNotEmpty,
        'confirmedCount': confirmed,
        'totalCount': apps.length,
      };
    } catch (e) {
      return {'hasApplicants': false, 'confirmedCount': 0, 'totalCount': 0};
    }
  }

  Future<bool> deleteTO(String toId) async {
    try {
      final to = await getTO(toId);
      if (to == null) {
        ToastHelper.showError('공고를 찾을 수 없습니다.');
        return false;
      }

      final batch = _firestore.batch();

      // 1. slots 서브컬렉션 삭제 (flex)
      if (to.isFlexType) {
        final slotsSnap = await _firestore
            .collection('tos').doc(toId)
            .collection('slots').get();
        for (final s in slotsSnap.docs) {
          batch.delete(s.reference);
        }
      }

      // 2. applications 알림 후 삭제 (businessId 필터로 보안 규칙 통과)
      final appsSnap = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .where('businessId', isEqualTo: to.businessId)
          .get();

      for (final doc in appsSnap.docs) {
        final data = doc.data();
        final status = data['status'] as String?;
        if (status == 'PENDING' || status == 'CONFIRMED') {
          _sendTOCanceledNotification(
            applicantUid: data['uid'] as String,
            businessName: to.businessName,
            toTitle: to.title,
            status: status!,
          );
        }
        batch.delete(doc.reference);
      }

      // 3. TO 문서 삭제
      batch.delete(_firestore.collection('tos').doc(toId));

      await batch.commit();
      clearCache(toId: toId);

      ToastHelper.showSuccess('공고가 삭제되었습니다.');
      return true;
    } catch (e) {
      debugPrint('❌ [TO] 공고 삭제 실패: $e');
      ToastHelper.showError('공고 삭제에 실패했습니다.');
      return false;
    }
  }

  // ───────────────────────────────────────────────────────
  // 슬롯 (flex 전용)
  // ───────────────────────────────────────────────────────

  /// 슬롯 목록 조회
  /// [visibleOnly] true 면 visibleFrom <= 현재시각인 슬롯만 반환 (유저용)
  Future<List<SlotModel>> getSlots(String toId, {bool visibleOnly = false}) async {
    try {
      final snap = await _firestore
          .collection('tos').doc(toId)
          .collection('slots')
          .orderBy('date')
          .get();

      final slots = snap.docs
          .map((d) => SlotModel.fromMap(d.data(), d.id, toId))
          .toList();

      if (!visibleOnly) return slots;

      final now = DateTime.now();
      return slots
          .where((s) => s.visibleFrom == null || !s.visibleFrom!.isAfter(now))
          .toList();
    } catch (e) {
      debugPrint('❌ [TO] 슬롯 조회 실패: $e');
      return [];
    }
  }

  /// 근무시간/마감시간 설정 변경 시 모든 슬롯의 workDetails.applicationDeadline 일괄 재계산
  Future<void> updateSlotsDeadlines({
    required String toId,
    required String deadlineType,
    required int hoursBeforeStart,
    required List<WorkDetailData> newWorkDetails,
    DateTime? fixedDeadline,
  }) async {
    try {
      final slots = await getSlots(toId);
      if (slots.isEmpty) return;

      final batch = _firestore.batch();

      for (final slot in slots) {
        final slotRef = _firestore
            .collection('tos').doc(toId)
            .collection('slots').doc(slot.id);

        // 슬롯의 각 workDetail에 대해 새 마감 계산
        final updatedWorkDetails = slot.workDetails.map((d) {
          // 동일 workType의 새 설정에서 startTime 가져오기
          final newDef = newWorkDetails.firstWhere(
            (nd) => nd.workType == d.workType,
            orElse: () => d,
          );
          DateTime? deadline;
          if (deadlineType == 'HOURS_BEFORE') {
            final parts = newDef.startTime.split(':');
            deadline = DateTime(
              slot.date.year, slot.date.month, slot.date.day,
              int.parse(parts[0]), int.parse(parts[1]),
            ).subtract(Duration(hours: hoursBeforeStart)).toUtc();
          } else if (deadlineType == 'FIXED_TIME' && fixedDeadline != null) {
            deadline = fixedDeadline.toUtc();
          }
          return d.copyWith(
            startTime: newDef.startTime,
            endTime: newDef.endTime,
            applicationDeadline: deadline,
          );
        }).toList();

        // 슬롯 레벨 마감 = 가장 이른 업무 마감
        final slotDeadline = updatedWorkDetails
            .where((d) => d.applicationDeadline != null)
            .map((d) => d.applicationDeadline!)
            .fold<DateTime?>(null, (earliest, dt) =>
                earliest == null || dt.isBefore(earliest) ? dt : earliest);

        batch.update(slotRef, {
          'workDetails': WorkDetailData.listToFirestore(updatedWorkDetails),
          'applicationDeadline': slotDeadline != null
              ? Timestamp.fromDate(slotDeadline)
              : FieldValue.delete(),
        });
      }

      await batch.commit();
      debugPrint('✅ [TO] 슬롯 ${slots.length}개 마감시간 갱신 완료');
    } catch (e) {
      debugPrint('❌ [TO] 슬롯 마감시간 갱신 실패: $e');
      rethrow;
    }
  }

  /// 특정 슬롯 전체 수정 (업무 구성·금액·인원·마감시간)
  Future<void> updateSlotFull({
    required String toId,
    required String slotId,
    required List<WorkDetailData> workDetails,
    DateTime? applicationDeadline,
    String? title,
    int? oldTotalRequired,
  }) async {
    final slotRef = _firestore
        .collection('tos').doc(toId)
        .collection('slots').doc(slotId);
    final newTotalRequired = workDetails.fold<int>(0, (s, d) => s + d.requiredCount);

    final batch = _firestore.batch();
    batch.update(slotRef, {
      'workDetails': WorkDetailData.listToFirestore(workDetails),
      'applicationDeadline': applicationDeadline != null
          ? Timestamp.fromDate(applicationDeadline.toUtc())
          : FieldValue.delete(),
      if (title != null && title.isNotEmpty) 'title': title
      else 'title': FieldValue.delete(),
    });

    // 요구인원 변경 시 마스터 TO의 totalRequired 동기화
    if (oldTotalRequired != null && oldTotalRequired != newTotalRequired) {
      batch.update(_firestore.collection('tos').doc(toId), {
        'totalRequired': FieldValue.increment(newTotalRequired - oldTotalRequired),
      });
    }

    await batch.commit();
    clearCache(toId: toId);
    debugPrint('✅ [Slot] 슬롯 $slotId 전체 수정 완료');
  }

  /// 선택한 슬롯들 일괄 마감
  Future<void> batchCloseSlots({
    required String toId,
    required List<String> slotIds,
    required String closedBy,
  }) async {
    if (slotIds.isEmpty) return;
    final batch = _firestore.batch();
    for (final slotId in slotIds) {
      final ref = _firestore
          .collection('tos').doc(toId)
          .collection('slots').doc(slotId);
      batch.update(ref, {
        'isManualClosed': true,
        'status': 'closed',
        'closedAt': FieldValue.serverTimestamp(),
        'closedBy': closedBy,
      });
    }
    await batch.commit();
    debugPrint('✅ [Slot] ${slotIds.length}개 슬롯 일괄 마감 완료');
  }

  /// 선택한 슬롯들 일괄 재오픈
  Future<void> batchReopenSlots({
    required String toId,
    required List<String> slotIds,
    required String reopenedBy,
  }) async {
    if (slotIds.isEmpty) return;
    final batch = _firestore.batch();
    for (final slotId in slotIds) {
      final ref = _firestore
          .collection('tos').doc(toId)
          .collection('slots').doc(slotId);
      batch.update(ref, {
        'isManualClosed': false,
        'status': 'open',
        'reopenedAt': FieldValue.serverTimestamp(),
        'reopenedBy': reopenedBy,
        'closedAt': FieldValue.delete(),
        'closedBy': FieldValue.delete(),
      });
    }
    await batch.commit();
    debugPrint('✅ [Slot] ${slotIds.length}개 슬롯 일괄 재오픈 완료');
  }

  /// 선택한 슬롯들 일괄 삭제
  Future<void> batchDeleteSlots({
    required String toId,
    required List<String> slotIds,
    int removedRequired = 0,
    int removedConfirmed = 0,
    int removedPending = 0,
  }) async {
    if (slotIds.isEmpty) return;
    final batch = _firestore.batch();
    for (final slotId in slotIds) {
      final ref = _firestore
          .collection('tos').doc(toId)
          .collection('slots').doc(slotId);
      batch.delete(ref);
    }
    batch.update(_firestore.collection('tos').doc(toId), {
      'totalSlots': FieldValue.increment(-slotIds.length),
      if (removedRequired > 0) 'totalRequired': FieldValue.increment(-removedRequired),
      if (removedConfirmed > 0) 'totalConfirmed': FieldValue.increment(-removedConfirmed),
      if (removedPending > 0) 'totalPending': FieldValue.increment(-removedPending),
    });
    await batch.commit();
    debugPrint('✅ [Slot] ${slotIds.length}개 슬롯 일괄 삭제 완료');
  }

  /// 새 날짜 슬롯 추가
  Future<void> addSlot({
    required TOModel to,
    required DateTime date,
    required List<WorkDetailData> workDetails,
    int? hoursBeforeStart,
    String? title,
  }) async {
    await _createSlots(
      toId: to.id,
      dates: [date],
      workDetails: workDetails,
      deadlineType: to.deadlineType,
      hoursBeforeStart: hoursBeforeStart ?? to.hoursBeforeStart ?? 2,
      fixedDeadline: to.applicationDeadline,
      publishMode: to.publishMode,
      publishDaysBefore: to.publishDaysBefore,
      publishTime: to.publishTime,
      slotTitle: title,
    );

    final slotRequired = workDetails.fold<int>(0, (s, d) => s + d.requiredCount);
    await _firestore.collection('tos').doc(to.id).update({
      'totalSlots': FieldValue.increment(1),
      'totalRequired': FieldValue.increment(slotRequired),
    });
    debugPrint('✅ [TO] 슬롯 추가 완료: ${date.toIso8601String().substring(0, 10)}');
  }

  /// publish 설정 변경 시 모든 슬롯의 visibleFrom 일괄 업데이트
  Future<void> updateSlotsPublishSettings({
    required String toId,
    required String publishMode,
    int? publishDaysBefore,
    String? publishTime,
  }) async {
    try {
      final slots = await getSlots(toId);
      if (slots.isEmpty) return;

      final batch = _firestore.batch();

      for (final slot in slots) {
        final slotRef = _firestore
            .collection('tos').doc(toId)
            .collection('slots').doc(slot.id);

        if (publishMode == 'scheduled' &&
            publishDaysBefore != null &&
            publishTime != null) {
          final parts = publishTime.split(':');
          final visibleFrom = DateTime(
            slot.date.year, slot.date.month, slot.date.day,
            int.parse(parts[0]), int.parse(parts[1]),
          ).subtract(Duration(days: publishDaysBefore));

          batch.update(slotRef, {
            'visibleFrom': Timestamp.fromDate(visibleFrom.toUtc()),
          });
        } else {
          // immediate 모드 → visibleFrom 제거
          batch.update(slotRef, {'visibleFrom': FieldValue.delete()});
        }
      }

      await batch.commit();
      debugPrint('✅ [TO] 슬롯 ${slots.length}개 visibleFrom 업데이트 완료');
    } catch (e) {
      debugPrint('❌ [TO] 슬롯 visibleFrom 업데이트 실패: $e');
      rethrow;
    }
  }

  /// 슬롯 통계 업데이트 (지원/확정/거절 시 호출)
  Future<void> updateSlotStats(
    String toId,
    String slotId, {
    int confirmedDelta = 0,
    int pendingDelta = 0,
  }) async {
    try {
      final slotRef = _firestore
          .collection('tos').doc(toId)
          .collection('slots').doc(slotId);

      final toRef = _firestore.collection('tos').doc(toId);

      await _firestore.runTransaction((tx) async {
        final slotSnap = await tx.get(slotRef);
        final toSnap = await tx.get(toRef);

        if (!slotSnap.exists || !toSnap.exists) return;

        final slotData = slotSnap.data()!;
        final newSlotConfirmed = (slotData['confirmedCount'] as int? ?? 0) + confirmedDelta;
        final newSlotPending = (slotData['pendingCount'] as int? ?? 0) + pendingDelta;

        // 슬롯 자체의 workDetails에서 requiredCount 합산 (TO 전체 합이 아님)
        final rawWorkDetails = slotData['workDetails'] as List? ?? [];
        final slotTotalRequired = rawWorkDetails.fold<int>(
          0, (acc, d) => acc + ((d as Map<String, dynamic>)['requiredCount'] as int? ?? 0));

        // 슬롯 상태 갱신
        final slotStatus = slotTotalRequired > 0 && newSlotConfirmed >= slotTotalRequired
            ? 'full'
            : 'open';

        tx.update(slotRef, {
          'confirmedCount': newSlotConfirmed,
          'pendingCount': newSlotPending,
          'status': slotStatus,
        });

        // TO 집계 갱신
        tx.update(toRef, {
          'totalConfirmed': FieldValue.increment(confirmedDelta),
          'totalPending': FieldValue.increment(pendingDelta),
        });
      });
    } catch (e) {
      debugPrint('❌ [TO] 슬롯 통계 업데이트 실패: $e');
    }
  }

  // ───────────────────────────────────────────────────────
  // 내부 유틸
  // ───────────────────────────────────────────────────────

  Future<void> _createSlots({
    required String toId,
    required List<DateTime> dates,
    required List<WorkDetailData> workDetails,
    required String deadlineType,
    required int hoursBeforeStart,
    DateTime? fixedDeadline,
    String publishMode = 'immediate',
    int? publishDaysBefore,
    String? publishTime,
    String? slotTitle,
  }) async {
    final batch = _firestore.batch();
    final now = DateTime.now();

    for (final date in dates) {
      final slotRef = _firestore
          .collection('tos').doc(toId)
          .collection('slots').doc();

      // 업무별 마감 계산 — 각 workDetail의 startTime 기준으로 개별 계산
      final workDetailsWithDeadlines = workDetails.map((d) {
        DateTime? deadline;
        if (deadlineType == 'HOURS_BEFORE') {
          final parts = d.startTime.split(':');
          deadline = DateTime(
            date.year, date.month, date.day,
            int.parse(parts[0]), int.parse(parts[1]),
          ).subtract(Duration(hours: hoursBeforeStart)).toUtc();
        } else if (deadlineType == 'FIXED_TIME' && fixedDeadline != null) {
          deadline = fixedDeadline.toUtc();
        }
        return d.copyWith(applicationDeadline: deadline);
      }).toList();

      // 슬롯 레벨 마감 = 가장 이른 업무 마감 (하위 호환용)
      final slotDeadline = workDetailsWithDeadlines
          .where((d) => d.applicationDeadline != null)
          .map((d) => d.applicationDeadline!)
          .fold<DateTime?>(null, (earliest, dt) =>
              earliest == null || dt.isBefore(earliest) ? dt : earliest);

      // 슬롯 공개 시각 (각 슬롯 날짜 기준 N일 전 publishTime)
      DateTime? visibleFrom;
      if (publishMode == 'scheduled' &&
          publishDaysBefore != null &&
          publishTime != null) {
        final parts = publishTime.split(':');
        visibleFrom = DateTime(
          date.year, date.month, date.day,
          int.parse(parts[0]), int.parse(parts[1]),
        ).subtract(Duration(days: publishDaysBefore)).toUtc();
      }

      final workTypeCounts = {
        for (final d in workDetailsWithDeadlines)
          d.workType: const SlotWorkTypeCount(),
      };

      batch.set(slotRef, SlotModel(
        id: slotRef.id,
        toId: toId,
        date: DateTime(date.year, date.month, date.day),
        workDetails: workDetailsWithDeadlines,
        workTypeCounts: workTypeCounts,
        applicationDeadline: slotDeadline,
        visibleFrom: visibleFrom,
        title: (slotTitle?.isNotEmpty == true) ? slotTitle : null,
        createdAt: now,
      ).toMap()..['createdAt'] = FieldValue.serverTimestamp());
    }

    await batch.commit();
    debugPrint('✅ [TO] 슬롯 ${dates.length}개 생성 완료');
  }

  Future<void> _sendTOCanceledNotification({
    required String applicantUid,
    required String businessName,
    required String toTitle,
    required String status,
  }) async {
    try {
      await createNotification(
        NotificationModel.createTOCanceled(
          userId: applicantUid,
          businessName: businessName,
          toTitle: toTitle,
          workDate: DateTime.now(),
          status: status,
        ),
      );
    } catch (e) {
      debugPrint('⚠️ TO 취소 알림 전송 실패: $e');
    }
  }
}
