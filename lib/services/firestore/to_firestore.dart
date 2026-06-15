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
      final doc = await _firestore.collection('tos').doc(toId).get(const GetOptions(source: Source.server));
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
    int? limit,
  }) async {
    try {
      Query query = _firestore
          .collection('tos')
          .where('businessId', isEqualTo: businessId)
          .orderBy('createdAt', descending: true);

      if (activeOnly) {
        query = query.where('status', whereIn: TOStatus.openStates);
      } else if (closedOnly) {
        query = query.where('status', whereIn: TOStatus.closedStates);
      }
      if (limit != null) query = query.limit(limit);

      final snap = await query.get(const GetOptions(source: Source.server));
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
          .where('status', whereIn: [TOStatus.active, TOStatus.full])
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get(const GetOptions(source: Source.server));

      return snap.docs.map((d) => TOModel.fromMap(d.data(), d.id)).toList();
    } catch (e) {
      debugPrint('❌ [TO] 공개 공고 목록 조회 실패: $e');
      return [];
    }
  }

  /// 공개 공고 페이지네이션 조회 (지원자용)
  Future<Map<String, dynamic>> getPublishedTOsPaged({
    DocumentSnapshot? startAfter,
    int pageSize = 30,
    TOFilterState? filter,
  }) async {
    Query query = _firestore
        .collection('tos')
        .where('isPublished', isEqualTo: true)
        .where('status', whereIn: [TOStatus.active, TOStatus.full]);

    if (filter?.type != null) {
      query = query.where('type', isEqualTo: filter!.type);
    }
    if (filter?.city != null) {
      query = query.where('businessCity', isEqualTo: filter!.city);
      if (filter.district != null) {
        query = query.where('businessDistrict', isEqualTo: filter.district);
      }
    }

    query = query.orderBy('createdAt', descending: true).limit(pageSize);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get(const GetOptions(source: Source.server));
    return {
      'items': snap.docs.map((d) => TOModel.fromMap(d.data() as Map<String, dynamic>, d.id)).toList(),
      'lastDoc': snap.docs.isNotEmpty ? snap.docs.last : null,
      'hasMore': snap.docs.length >= pageSize,
    };
  }

  /// ID 목록으로 공고 배치 조회 (Algolia 검색 결과 fetch용)
  /// 마감/비공개 TO는 클라이언트에서 필터링 (Algolia 인덱스와 Firestore 상태 불일치 방어)
  Future<List<TOModel>> getTOsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final results = <TOModel>[];
    // Firestore whereIn 30개 제한 — 청크 처리
    for (var i = 0; i < ids.length; i += 30) {
      final chunk = ids.sublist(i, i + 30 > ids.length ? ids.length : i + 30);
      final snap = await _firestore
          .collection('tos')
          .where(FieldPath.documentId, whereIn: chunk)
          .get(const GetOptions(source: Source.server));
      // Firestore whereIn을 두 개 쓸 수 없으므로 클라이언트 필터링
      results.addAll(
        snap.docs
            .map((d) => TOModel.fromMap(d.data(), d.id))
            .where((to) => to.isPublished && !to.isClosed),
      );
    }
    return results;
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
          .get(const GetOptions(source: Source.server));

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
    String? contractPeriodType,
    int? postingDurationDays,

    // 예약 공개
    String publishMode = 'immediate',
    int? publishDaysBefore,
    String? publishTime,
  }) async {
    NetworkChecker.instance.assertOnline('공고 등록을 하려면 인터넷 연결이 필요합니다.');
    try {
      // 사업장 주소 조회
      String? businessAddress, businessCity, businessDistrict;
      try {
        final biz = await getBusinessById(businessId);
        businessAddress = biz?.address;
        businessCity = biz?.city;
        businessDistrict = biz?.district;
      } catch (e) {
        debugPrint('⚠️ TO 생성 시 사업장 주소 조회 실패 ($businessId): $e');
      }

      // 전체 필요 인원 (flex: 슬롯 수 × 1개 슬롯 기준, contract: 단일 값)
      final perSlotRequired = workDetails.fold<int>(0, (s, d) => s + d.requiredCount);
      final totalRequired = type == TOType.flex
          ? perSlotRequired * (dates?.length ?? 1)
          : perSlotRequired;

      // 예약 공개 시각 계산
      DateTime? publishAt;
      bool isPublished = publishMode == 'immediate';

      if (publishMode == 'scheduled' && publishDaysBefore != null && publishTime != null) {
        final baseDate = type == TOType.flex
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

      // 미공개(draft) 처리
      final isDraft = publishMode == 'draft';
      final String toStatus = isDraft
          ? TOStatus.draft
          : isPublished
              ? TOStatus.active
              : TOStatus.scheduled;

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
        totalSlots: type == TOType.flex ? (dates?.length ?? 0) : 0,
        rangeStart: type == TOType.flex
            ? dates?.reduce((a, b) => a.isBefore(b) ? a : b)
            : rangeStart,
        rangeEnd: type == TOType.flex
            ? dates?.reduce((a, b) => a.isAfter(b) ? a : b) // flex: 마지막 날짜
            : rangeEnd,
        workDays: workDays ?? const [],
        deadlineType: deadlineType,
        hoursBeforeStart: hoursBeforeStart,
        applicationDeadline: contractDeadline,
        contractPeriodType: contractPeriodType,
        postingDurationDays: postingDurationDays,
        totalRequired: totalRequired,
        publishMode: publishMode,
        publishAt: publishAt,
        isPublished: isPublished && !isDraft,
        publishDaysBefore: publishDaysBefore,
        publishTime: publishTime,
        creatorUID: creatorUID,
        createdAt: DateTime.now(),
        status: toStatus,
      ).toMap()
        ..['createdAt'] = FieldValue.serverTimestamp()
        ..['statusUpdatedAt'] = FieldValue.serverTimestamp();

      // flex + 즉시공개: 슬롯 생성 완료 전까지 비공개로 생성 → 슬롯 없는 TO 노출 방지
      final deferPublish = type == TOType.flex &&
          isPublished &&
          !isDraft &&
          dates != null &&
          dates.isNotEmpty;
      final initialData = deferPublish
          ? {...toData, 'isPublished': false, 'status': TOStatus.scheduled}
          : toData;

      final toDoc = await _firestore.collection('tos').add(initialData);
      debugPrint('✅ [TO] 공고 생성: ${toDoc.id}');

      // flex: slots 생성 — 실패 시 부분 생성된 슬롯 + TO 문서 모두 롤백 삭제
      if (type == TOType.flex && dates != null && dates.isNotEmpty) {
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
          debugPrint('⚠️ [TO] 슬롯 생성 실패 — 부분 슬롯 및 TO 롤백: ${toDoc.id}');
          // 부분 커밋된 슬롯 정리 (배치 분할 커밋 중 실패 시 고아 슬롯 방지)
          try {
            final partialSlots = await _firestore
                .collection('tos').doc(toDoc.id).collection('slots').get();
            if (partialSlots.docs.isNotEmpty) {
              var cleanupBatch = _firestore.batch();
              int cleanupCount = 0;
              for (final s in partialSlots.docs) {
                cleanupBatch.delete(s.reference);
                cleanupCount++;
                if (cleanupCount >= 499) {
                  await cleanupBatch.commit();
                  cleanupBatch = _firestore.batch();
                  cleanupCount = 0;
                }
              }
              if (cleanupCount > 0) await cleanupBatch.commit();
            }
          } catch (cleanupError) {
            debugPrint('❌ 부분 슬롯 정리 실패 (수동 삭제 필요): $cleanupError');
          }
          await toDoc.delete();
          rethrow;
        }

        // 슬롯 생성 완료 후 즉시공개 상태로 전환 (노출 창 최소화)
        if (deferPublish) {
          await toDoc.update({
            'isPublished': true,
            'status': toStatus,
            'statusUpdatedAt': FieldValue.serverTimestamp(),
          });
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
      final apps = await getApplicationsByTOId(
        toId,
        businessId: businessId,
        statuses: AppStatus.activeStates,
      );
      final confirmed = apps.where((a) =>
          AppStatus.confirmedStatuses.contains(a.status)).length;
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

      // Firestore WriteBatch 한도(500 ops) 초과 방지: 청크 단위 처리
      final ops = <Future<void> Function(WriteBatch)>[];

      // 1. slots 서브컬렉션 삭제 (flex)
      if (to.isFlexType) {
        final slotsSnap = await _firestore
            .collection('tos').doc(toId)
            .collection('slots').get(const GetOptions(source: Source.server));
        for (final s in slotsSnap.docs) {
          final ref = s.reference;
          ops.add((b) async => b.delete(ref));
        }
      }

      // 2. applications 알림 후 취소/삭제
      final appsSnap = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .where('businessId', isEqualTo: to.businessId)
          .get(const GetOptions(source: Source.server));

      for (final doc in appsSnap.docs) {
        final data = doc.data();
        final status = data['status'] as String?;
        if (AppStatus.activeStates.contains(status)) {
          final ref = doc.reference;
          ops.add((b) async => b.update(ref, {
            'status': AppStatus.autoCanceled,
            'canceledAt': FieldValue.serverTimestamp(),
            'cancelReason': 'TO_DELETED',
          }));
          _sendTOCanceledNotification(
            applicantUid: data['uid'] as String,
            businessName: to.businessName,
            businessId: to.businessId,
            toTitle: to.title,
            status: status!,
          );
        } else {
          final ref = doc.reference;
          ops.add((b) async => b.delete(ref));
        }
      }

      // 청크 단위(499 ops)로 나눠서 커밋 (슬롯·지원서 먼저)
      // [004] TO 문서 삭제는 모든 서브 데이터 커밋 완료 후 별도 실행
      // — 마지막 청크가 TO 삭제까지 포함하면 실패 시 TO가 빈 껍데기로 잔존
      const chunkSize = 499;
      for (var i = 0; i < ops.length; i += chunkSize) {
        final chunk = ops.sublist(i, i + chunkSize > ops.length ? ops.length : i + chunkSize);
        final batch = _firestore.batch();
        for (final op in chunk) {
          await op(batch);
        }
        await batch.commit();
      }

      // 모든 서브 데이터 삭제 완료 후 TO 문서 삭제
      await _firestore.collection('tos').doc(toId).delete();
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
          .get(const GetOptions(source: Source.server));

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

      var batch = _firestore.batch();
      int count = 0;

      for (final slot in slots) {
        final slotRef = _firestore
            .collection('tos').doc(toId)
            .collection('slots').doc(slot.id);

        // newWorkDetails 기준으로 슬롯 업무상세 재구성 (신규 업무유형 추가 포함)
        final updatedWorkDetails = newWorkDetails.map((newDef) {
          final existing = slot.workDetails.firstWhere(
            (d) => d.workType == newDef.workType,
            orElse: () => newDef,
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
          // 기존 슬롯에 같은 workType이 있으면 기존 상태(closedBy 등) 유지하면서 갱신
          final isNew = slot.workDetails.every((d) => d.workType != newDef.workType);
          if (isNew) {
            return newDef.copyWith(applicationDeadline: deadline);
          }
          return existing.copyWith(
            startTime: newDef.startTime,
            endTime: newDef.endTime,
            applicationDeadline: deadline,
            wage: newDef.wage,
            wageType: newDef.wageType,
            requiredCount: newDef.requiredCount,
          );
        }).toList();

        // 슬롯 레벨 마감 = 가장 이른 업무 마감
        final slotDeadline = updatedWorkDetails
            .where((d) => d.applicationDeadline != null)
            .map((d) => d.applicationDeadline!)
            .fold<DateTime?>(null, (earliest, dt) =>
                earliest == null || dt.isBefore(earliest) ? dt : earliest);

        // 미래 마감시간이 있는 활성 업무상세가 존재하면 자동마감 슬롯 재오픈
        final now = DateTime.now();
        final hasOpenDetail = updatedWorkDetails.any((d) =>
            !d.isClosed &&
            (d.applicationDeadline == null || d.applicationDeadline!.isAfter(now)));
        final isAutoClosed =
            slot.status == SlotStatus.closed && slot.closedBy == null;

        final updateData = <String, dynamic>{
          'workDetails': WorkDetailData.listToFirestore(updatedWorkDetails),
          'applicationDeadline': slotDeadline != null
              ? Timestamp.fromDate(slotDeadline)
              : FieldValue.delete(),
          if (hasOpenDetail && isAutoClosed) ...{
            'status': SlotStatus.open,
            'isManualClosed': false,
            'closedAt': FieldValue.delete(),
          },
        };

        batch.update(slotRef, updateData);
        count++;
        if (count >= 499) { await batch.commit(); batch = _firestore.batch(); count = 0; }
      }

      if (count > 0) await batch.commit();
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
    DateTime? visibleFrom,
    bool clearVisibleFrom = false,
  }) async {
    if (workDetails.any((d) => d.requiredCount <= 0)) {
      throw ArgumentError('requiredCount는 1 이상이어야 합니다');
    }
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
      if (clearVisibleFrom) 'visibleFrom': FieldValue.delete()
      else if (visibleFrom != null) 'visibleFrom': Timestamp.fromDate(visibleFrom.toUtc()),
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

  /// 선택한 슬롯들 일괄 마감 (직접 마감 — closedBy 설정)
  Future<void> batchCloseSlots({
    required String toId,
    required List<String> slotIds,
    required String closedBy,
  }) async {
    if (slotIds.isEmpty) return;

    // [003] 슬롯을 먼저 closed로 설정 → 신규 지원 차단 후 PENDING 취소
    // (역순: PENDING 취소 후 슬롯 마감 시, 취소~마감 사이 신규 PENDING 지원이 잔류 가능)
    var batch = _firestore.batch();
    int count = 0;
    for (final slotId in slotIds) {
      final ref = _firestore
          .collection('tos').doc(toId)
          .collection('slots').doc(slotId);
      batch.update(ref, {
        'isManualClosed': true,
        'status': SlotStatus.closed,
        'closedAt': FieldValue.serverTimestamp(),
        'closedBy': closedBy,
      });
      count++;
      if (count >= 499) { await batch.commit(); batch = _firestore.batch(); count = 0; }
    }
    if (count > 0) await batch.commit();

    // 슬롯 마감 완료 후 PENDING 지원서 취소 + TO totalPending 카운터 감소
    // [A-001] try-catch per slot: 특정 슬롯 cancelBatch 실패 시 해당 슬롯 카운트 제외 후 계속 진행
    int totalCanceledPending = 0;
    for (final slotId in slotIds) {
      final pendingSnap = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .where('slotId', isEqualTo: slotId)
          .where('status', isEqualTo: AppStatus.pending)
          .get(const GetOptions(source: Source.server));
      if (pendingSnap.docs.isEmpty) continue;
      int slotCanceled = 0;
      try {
        var cancelBatch = _firestore.batch();
        int cancelCount = 0;
        for (final doc in pendingSnap.docs) {
          cancelBatch.update(doc.reference, {
            'status': AppStatus.rejected,
            'rejectedAt': FieldValue.serverTimestamp(),
            'rejectReason': '공고 슬롯이 마감되었습니다',
          });
          cancelCount++;
          slotCanceled++;
          if (cancelCount >= 499) {
            await cancelBatch.commit();
            cancelBatch = _firestore.batch();
            cancelCount = 0;
          }
        }
        if (cancelCount > 0) await cancelBatch.commit();
        totalCanceledPending += slotCanceled;
      } catch (e) {
        debugPrint('❌ [SlotClose] 슬롯 $slotId PENDING 취소 실패 — TO 카운터 미감소: $e');
      }
    }

    // 실제로 취소 처리된 건만큼만 TO totalPending 감소
    if (totalCanceledPending > 0) {
      await _firestore.collection('tos').doc(toId).update({
        'totalPending': FieldValue.increment(-totalCanceledPending),
      });
    }
    debugPrint('✅ [Slot] ${slotIds.length}개 슬롯 일괄 마감 완료');

    await _syncTOCascadeStatus(toId);
  }

  /// 선택한 슬롯들 일괄 재오픈 (직접 마감 해제 — closedBy 삭제)
  Future<void> batchReopenSlots({
    required String toId,
    required List<String> slotIds,
    required String reopenedBy,
  }) async {
    if (slotIds.isEmpty) return;

    // 재오픈 전 각 슬롯의 확정/요구 인원을 읽어 full 여부 판단
    // — 이미 정원이 찬 슬롯을 open으로 강제하면 초과 지원이 허용되므로 full 상태를 유지
    final slotSnaps = await Future.wait(slotIds.map((id) => _firestore
        .collection('tos').doc(toId)
        .collection('slots').doc(id)
        .get(const GetOptions(source: Source.server))));

    var batch = _firestore.batch();
    int count = 0;
    for (int i = 0; i < slotIds.length; i++) {
      final slotId = slotIds[i];
      final ref = _firestore
          .collection('tos').doc(toId)
          .collection('slots').doc(slotId);

      String reopenedStatus = SlotStatus.open;
      if (slotSnaps[i].exists) {
        final d = slotSnaps[i].data()!;
        final confirmed = (d['confirmedCount'] as num?)?.toInt() ?? 0;
        final wds = d['workDetails'] as List? ?? [];
        final required = wds.fold<int>(0, (acc, wd) =>
            acc + (((wd as Map<String, dynamic>)['requiredCount'] as num?)?.toInt() ?? 0));
        if (required > 0 && confirmed >= required) reopenedStatus = SlotStatus.full;
      }

      batch.update(ref, {
        'isManualClosed': false,
        'status': reopenedStatus,
        'reopenedAt': FieldValue.serverTimestamp(),
        'reopenedBy': reopenedBy,
        'closedAt': FieldValue.delete(),
        'closedBy': FieldValue.delete(),
      });
      count++;
      if (count >= 499) { await batch.commit(); batch = _firestore.batch(); count = 0; }
    }
    if (count > 0) await batch.commit();
    debugPrint('✅ [Slot] ${slotIds.length}개 슬롯 일괄 재오픈 완료');

    await _syncTOCascadeStatus(toId);
  }

  /// 선택한 슬롯들 일괄 삭제
  Future<void> batchDeleteSlots({
    required String toId,
    required List<String> slotIds,
  }) async {
    if (slotIds.isEmpty) return;

    // [007] 슬롯 카운터를 직접 읽어서 계산 — 호출자 제공 값 대신 서버 데이터 사용
    final slotSnaps = await Future.wait(slotIds.map((id) => _firestore
        .collection('tos').doc(toId)
        .collection('slots').doc(id)
        .get(const GetOptions(source: Source.server))));
    int removedRequired = 0, removedConfirmed = 0, removedPending = 0;
    for (final snap in slotSnaps) {
      if (!snap.exists) continue;
      final d = snap.data()!;
      final wds = d['workDetails'] as List? ?? [];
      removedRequired += wds.fold<int>(0, (acc, wd) =>
          acc + ((wd as Map<String, dynamic>)['requiredCount'] as num? ?? 0).toInt());
      removedConfirmed += (d['confirmedCount'] as num?)?.toInt() ?? 0;
      removedPending += (d['pendingCount'] as num?)?.toInt() ?? 0;
    }

    // 삭제 대상 슬롯에 연결된 활성 지원서 전체 취소 처리 (PENDING/CONFIRMED/CONTRACT_PENDING)
    for (final slotId in slotIds) {
      final activeSnap = await _firestore
          .collection('applications')
          .where('toId', isEqualTo: toId)
          .where('slotId', isEqualTo: slotId)
          .where('status', whereIn: [AppStatus.pending, AppStatus.confirmed, AppStatus.contractPending])
          .get(const GetOptions(source: Source.server));
      if (activeSnap.docs.isEmpty) continue;
      var cancelBatch = _firestore.batch();
      int cancelCount = 0;
      for (final doc in activeSnap.docs) {
        cancelBatch.update(doc.reference, {
          'status': AppStatus.rejected,
          'rejectedAt': FieldValue.serverTimestamp(),
          'rejectReason': '공고 슬롯이 삭제되었습니다',
        });
        cancelCount++;
        if (cancelCount >= 499) {
          await cancelBatch.commit();
          cancelBatch = _firestore.batch();
          cancelCount = 0;
        }
      }
      if (cancelCount > 0) await cancelBatch.commit();
    }

    var batch = _firestore.batch();
    int count = 0;
    for (final slotId in slotIds) {
      final ref = _firestore
          .collection('tos').doc(toId)
          .collection('slots').doc(slotId);
      batch.delete(ref);
      count++;
      if (count >= 499) { await batch.commit(); batch = _firestore.batch(); count = 0; }
    }
    // TO 카운터 업데이트는 별도 commit
    batch.update(_firestore.collection('tos').doc(toId), {
      'totalSlots': FieldValue.increment(-slotIds.length),
      if (removedRequired > 0) 'totalRequired': FieldValue.increment(-removedRequired),
      if (removedConfirmed > 0) 'totalConfirmed': FieldValue.increment(-removedConfirmed),
      if (removedPending > 0) 'totalPending': FieldValue.increment(-removedPending),
    });
    await batch.commit();
    debugPrint('✅ [Slot] ${slotIds.length}개 슬롯 일괄 삭제 완료');

    // 남은 슬롯의 날짜 범위로 rangeStart/rangeEnd 재계산
    final remaining = await getSlots(toId);
    if (remaining.isNotEmpty) {
      final minDate = remaining.map((s) => s.date).reduce((a, b) => a.isBefore(b) ? a : b);
      final maxDate = remaining.map((s) => s.date).reduce((a, b) => a.isAfter(b) ? a : b);
      await _firestore.collection('tos').doc(toId).update({
        'rangeStart': Timestamp.fromDate(DateTime(minDate.year, minDate.month, minDate.day)),
        'rangeEnd': Timestamp.fromDate(DateTime(maxDate.year, maxDate.month, maxDate.day)),
      });
      await _syncTOCascadeStatus(toId);
    } else {
      // 슬롯이 전부 삭제됨 → TO 자동 CLOSED + 총 카운터 초기화
      await _firestore.collection('tos').doc(toId).update({
        'status': TOStatus.closed,
        'isPublished': false,
        'closedAt': FieldValue.serverTimestamp(),
        'totalSlots': 0,
        'totalRequired': 0,
        'totalConfirmed': 0,
        'totalPending': 0,
      });
      clearCache(toId: toId);
      debugPrint('✅ [TO] 모든 슬롯 삭제 → 자동 CLOSED + 카운터 초기화 ($toId)');
    }
  }

  /// 새 날짜 슬롯 추가
  Future<void> addSlot({
    required TOModel to,
    required DateTime date,
    required List<WorkDetailData> workDetails,
    int? hoursBeforeStart,
    String? title,
    DateTime? visibleFrom,
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
      overrideVisibleFrom: visibleFrom,
    );

    final slotRequired = workDetails.fold<int>(0, (s, d) => s + d.requiredCount);
    final dateOnly = DateTime(date.year, date.month, date.day);

    final Map<String, dynamic> toUpdates = {
      'totalSlots': FieldValue.increment(1),
      'totalRequired': FieldValue.increment(slotRequired),
    };

    // 마감/만료 상태였으면 새 슬롯 추가 시 ACTIVE 복구
    // isPublished는 기존 상태 유지 — 관리자가 의도적으로 비공개 설정한 경우 자동 공개 방지
    if (TOStatus.closedStates.contains(to.status)) {
      toUpdates['status'] = TOStatus.active;
      if (to.isPublished) toUpdates['isPublished'] = true;
      toUpdates['statusUpdatedAt'] = FieldValue.serverTimestamp();
      debugPrint('🔄 [TO] 상태 복구: ${to.status} → ACTIVE (새 슬롯 추가, isPublished=${to.isPublished})');
    }

    // 새 슬롯이 날짜 범위를 벗어나면 rangeStart/rangeEnd 갱신
    final rangeEnd = to.rangeEnd;
    final rangeStart = to.rangeStart;
    if (rangeEnd == null || dateOnly.isAfter(rangeEnd)) {
      toUpdates['rangeEnd'] = Timestamp.fromDate(dateOnly);
    }
    if (rangeStart == null || dateOnly.isBefore(rangeStart)) {
      toUpdates['rangeStart'] = Timestamp.fromDate(dateOnly);
    }

    await _firestore.collection('tos').doc(to.id).update(toUpdates);
    debugPrint('✅ [TO] 슬롯 추가 완료: ${date.toIso8601String().substring(0, 10)}');
  }

  /// TO 문서의 공개 설정(publishMode/publishDaysBefore/publishTime) 업데이트
  Future<void> updateTOPublishSettings({
    required String toId,
    required String publishMode,
    int? publishDaysBefore,
    String? publishTime,
  }) async {
    await _firestore.collection('tos').doc(toId).update({
      'publishMode': publishMode,
      'publishDaysBefore': publishDaysBefore,
      'publishTime': publishTime,
    });
    debugPrint('✅ [TO] 공개 설정 업데이트: $publishMode D-${publishDaysBefore ?? '-'} $publishTime');
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

      var batch = _firestore.batch();
      int count = 0;

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
        count++;
        if (count >= 499) { await batch.commit(); batch = _firestore.batch(); count = 0; }
      }

      if (count > 0) await batch.commit();
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
        final newSlotConfirmed = ((slotData['confirmedCount'] as num?)?.toInt() ?? 0) + confirmedDelta;
        final newSlotPending = ((slotData['pendingCount'] as num?)?.toInt() ?? 0) + pendingDelta;

        // 슬롯 자체의 workDetails에서 requiredCount 합산 (TO 전체 합이 아님)
        final rawWorkDetails = slotData['workDetails'] as List? ?? [];
        final slotTotalRequired = rawWorkDetails.fold<int>(
          0, (acc, d) => acc + (((d as Map<String, dynamic>)['requiredCount'] as num?)?.toInt() ?? 0));

        // 수동 마감 슬롯은 상태 변경 금지 (closedBy가 설정된 경우)
        final isManualClosed = slotData['isManualClosed'] == true;

        final Map<String, dynamic> slotUpdates = {
          'confirmedCount': newSlotConfirmed,
          'pendingCount': newSlotPending,
        };

        if (!isManualClosed) {
          slotUpdates['status'] = slotTotalRequired > 0 && newSlotConfirmed >= slotTotalRequired
              ? SlotStatus.full
              : SlotStatus.open;
        }

        tx.update(slotRef, slotUpdates);

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
    DateTime? overrideVisibleFrom,
  }) async {
    var batch = _firestore.batch();
    int count = 0;
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

      // 슬롯 공개 시각: override가 있으면 우선 사용, 없으면 TO 설정 기준 계산
      DateTime? visibleFrom = overrideVisibleFrom?.toUtc();
      if (visibleFrom == null &&
          publishMode == 'scheduled' &&
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
      count++;
      if (count >= 499) {
        await batch.commit();
        batch = _firestore.batch();
        count = 0;
      }
    }

    if (count > 0) await batch.commit();
    debugPrint('✅ [TO] 슬롯 ${dates.length}개 생성 완료');
  }

  Future<void> _sendTOCanceledNotification({
    required String applicantUid,
    required String businessName,
    required String businessId,
    required String toTitle,
    required String status,
  }) async {
    try {
      await createNotification(
        NotificationModel.createTOCanceled(
          userId: applicantUid,
          businessName: businessName,
          businessId: businessId,
          toTitle: toTitle,
          workDate: DateTime.now(),
          status: status,
        ),
      );
    } catch (e) {
      debugPrint('⚠️ TO 취소 알림 전송 실패: $e');
    }
  }

  /// 슬롯 일괄 변경(마감/재오픈) 후 TO 상태를 동기화한다.
  /// - 모집 가능 슬롯(open/full)이 없으면 TO를 자동 CLOSED
  /// - 모집 가능 슬롯이 생기고 TO가 CLOSED이면 ACTIVE로 복구
  /// full 슬롯은 확정 완료 상태이므로 closed 처리하지 않음 — batchReopenSlots 후에도 TO ACTIVE 유지
  Future<void> _syncTOCascadeStatus(String toId) async {
    try {
      final slots = await getSlots(toId);
      if (slots.isEmpty) return;

      final toDoc = await _firestore.collection('tos').doc(toId).get(const GetOptions(source: Source.server));
      if (!toDoc.exists) return;

      final currentStatus = toDoc.data()?['status'] as String? ?? '';
      // open 또는 full 슬롯이 있으면 "모집 가능" — full만 남은 경우도 명시적 closed 아님
      final hasOpenSlot = slots.any((s) =>
          s.status == SlotStatus.open || s.status == SlotStatus.full);

      if (!hasOpenSlot && TOStatus.openStates.contains(currentStatus)) {
        await _firestore.collection('tos').doc(toId).update({
          'status': TOStatus.closed,
          'closedAt': FieldValue.serverTimestamp(),
        });
        debugPrint('✅ [TO] 모든 슬롯 마감(open/full 없음) → 자동 CLOSED ($toId)');
      } else if (hasOpenSlot && currentStatus == TOStatus.closed) {
        await _firestore.collection('tos').doc(toId).update({
          'status': TOStatus.active,
          'closedAt': FieldValue.delete(),
        });
        debugPrint('✅ [TO] 슬롯 재오픈 → ACTIVE 복구 ($toId)');
      }
    } catch (e) {
      debugPrint('⚠️ TO 상태 동기화 실패: $e');
    }
  }
}
