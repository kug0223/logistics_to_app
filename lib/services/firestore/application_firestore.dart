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
  /// [uid] USER 컨텍스트에서 중복 체크 시 필수 — 보안 규칙 `uid == auth.uid` 필터 충족
  ///       미전달 시 관리자 컨텍스트(businessId 필수)로 간주
  Future<List<ApplicationModel>> getApplicationsByTOId(
    String toId, {
    String? businessId,
    String? uid,
    List<String>? statuses,
  }) async {
    assert(
      uid != null || (businessId != null && businessId.isNotEmpty),
      'getApplicationsByTOId: admin 컨텍스트에서는 businessId 필수',
    );
    // USER 컨텍스트(uid 제공): [CF 이전 2026-07-15] callableGetMyApplications
    // uid를 서버에서 강제 검증 — Firestore 직접 list 차단 후 CF 경유 필수
    if (uid != null && uid.isNotEmpty) {
      try {
        final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableGetMyApplications',
                options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
        final result = await callable.call<Map<String, dynamic>>({
          'toId': toId,
          'limit': 2000,
        });
        final statusSet = statuses != null ? Set<String>.from(statuses) : null;
        return (result.data['applications'] as List? ?? [])
            .whereType<Map>()
            .map((m) {
              final raw = _cfHydrate(Map<String, dynamic>.from(m));
              final id = raw.remove('id') as String? ?? '';
              return ApplicationModel.tryFromMap(raw, id);
            })
            .whereType<ApplicationModel>()
            .where((a) => statusSet == null || statusSet.contains(a.status))
            .toList();
      } catch (e) {
        debugPrint('❌ 지원자 목록 조회 실패(user): $e');
        return [];
      }
    }
    // 관리자 컨텍스트 — [CF 이전 2026-07-13] callableGetApplicationsByBiz
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetApplicationsByBiz',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': businessId,
        'toId': toId,
        'limit': 2000,
      });
      final statusSet = statuses != null ? Set<String>.from(statuses) : null;
      return (result.data['applications'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return ApplicationModel.tryFromMap(raw, id);
          })
          .whereType<ApplicationModel>()
          .where((a) => statusSet == null || statusSet.contains(a.status))
          .toList();
    } catch (e) {
      debugPrint('❌ 지원자 목록 조회 실패(admin): $e');
      rethrow; // 빈 목록 반환 시 관리자가 지원자 없는 것으로 오인
    }
  }

  /// 슬롯별 지원서 조회 (flex 타입) — [CF 이전 2026-07-13] callableGetApplicationsByBiz
  /// [statuses] 지정 시 해당 상태만 조회 (미지정 시 전체)
  Future<List<ApplicationModel>> getApplicationsBySlotId(
    String toId,
    String slotId, {
    String? businessId,
    List<String>? statuses,
  }) async {
    assert(businessId != null && businessId.isNotEmpty, 'getApplicationsBySlotId: businessId 필수');
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetApplicationsByBiz',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': businessId ?? '',
        'toId': toId,
        'slotId': slotId,
        'limit': 2000,
      });
      final statusSet = statuses != null ? Set<String>.from(statuses) : null;
      return (result.data['applications'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return ApplicationModel.tryFromMap(raw, id);
          })
          .whereType<ApplicationModel>()
          .where((a) => statusSet == null || statusSet.contains(a.status))
          .toList();
    } catch (e) {
      debugPrint('❌ 슬롯 지원자 목록 조회 실패: $e');
      return [];
    }
  }

  /// 여러 TO의 지원서 병렬 조회 (관리자 전용)
  /// [businessId] 보안 규칙상 필수 — 소속 사업장 businessId를 반드시 전달해야 함
  Future<Map<String, List<ApplicationModel>>> getApplicationsByTOIds(
    List<String> toIds, {
    required String businessId,
  }) async {
    if (toIds.isEmpty) return {};
    try {
      final results = await Future.wait(
        toIds.map((id) async {
          final apps = await getApplicationsByTOId(id, businessId: businessId);
          return MapEntry(id, apps);
        }),
      );
      return Map.fromEntries(results);
    } catch (e) {
      debugPrint('❌ 배치 지원자 조회 실패: $e');
      return {};
    }
  }

  /// 사업장별 전체 지원서 조회 (관리자용) — [CF 이전 2026-07-13] callableGetApplicationsByBiz
  Future<List<ApplicationModel>> getApplicationsByBusinessId(
    String businessId,
  ) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetApplicationsByBiz',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': businessId,
        'orderByAppliedAtDesc': true,
        'limit': 1000,
      });
      return (result.data['applications'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return ApplicationModel.tryFromMap(raw, id);
          })
          .whereType<ApplicationModel>()
          .toList();
    } catch (e) {
      debugPrint('❌ 사업장별 지원서 조회 실패: $e');
      return [];
    }
  }

  /// 내 지원 내역 조회 (사용자용)
  ///
  /// [E02 캐시 Stampede 설계]
  /// 동시에 두 요청이 캐시 미스 → 둘 다 Firestore 조회 → 마지막 write가 캐시에 저장됨.
  /// Dart는 단일 스레드(isolate)이므로 await 사이에는 동시 실행이 없어
  /// 캐시 미스 감지와 Firestore 조회 사이의 race는 실질적으로 발생하지 않는다.
  /// (동일 이벤트 루프 틱 내의 동기 구간은 항상 원자적)
  /// 단, 동시 네트워크 요청이 겹치면 Firestore를 2회 조회할 수 있으나
  /// 결과는 동일하므로 last-write-wins는 안전하다 — 의도된 설계.
  Future<List<ApplicationModel>> getMyApplications(String uid) async {
    // TTL 캐시 — 1분 내 동일 uid 재조회 시 캐시 반환
    final cached = _myApplicationsCache[uid];
    final ts = _myApplicationsCacheTimestamps[uid];
    if (cached != null && ts != null &&
        DateTime.now().difference(ts) < FirestoreService._myApplicationsCacheTTL) {
      return cached;
    }
    try {
      // [CF 이전 2026-07-15] callableGetMyApplications — uid 서버 검증 강제
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetMyApplications',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({'limit': 200});
      final list = (result.data['applications'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return ApplicationModel.tryFromMap(raw, id);
          })
          .whereType<ApplicationModel>()
          .toList()
        ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));
      _myApplicationsCache[uid] = list;
      _myApplicationsCacheTimestamps[uid] = DateTime.now();
      return list;
    } catch (e) {
      debugPrint('내 지원 내역 조회 실패: $e');
      return cached ?? [];
    }
  }

  /// 내 지원 내역 페이지네이션 조회 (내 지원 화면 전용)
  ///
  /// [startAfterDocId] cursor 문서 ID — null이면 첫 페이지
  /// 반환: {items, lastDocId, hasMore}
  /// [CF 이전 2026-07-15] callableGetMyApplications — uid 서버 검증 강제
  Future<Map<String, dynamic>> getMyApplicationsPaged({
    required String uid,
    int pageSize = 20,
    String? startAfterDocId,
    String? statusFilter, // null = 전체, 'active', 'inactive'
  }) async {
    try {
      Set<String>? statusSet;
      if (statusFilter == 'active') {
        statusSet = Set<String>.from(AppStatus.activeStates);
      } else if (statusFilter == 'inactive') {
        statusSet = Set<String>.from(AppStatus.inactiveStates);
      }

      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetMyApplications',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'limit': pageSize,
        if (startAfterDocId != null) 'startAfterDocId': startAfterDocId,
      });

      final items = (result.data['applications'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return ApplicationModel.tryFromMap(raw, id);
          })
          .whereType<ApplicationModel>()
          .where((a) => statusSet == null || statusSet.contains(a.status))
          .toList()
        ..sort((a, b) => b.appliedAt.compareTo(a.appliedAt));

      return {
        'items': items,
        'lastDocId': result.data['lastDocId'],
        'hasMore': result.data['hasMore'] ?? false,
      };
    } catch (e) {
      debugPrint('지원 내역 페이지 조회 실패: $e');
      return {'items': <ApplicationModel>[], 'lastDocId': null, 'hasMore': false};
    }
  }

  // ───────────────────────────────────────────────────────
  // 지원하기
  // ───────────────────────────────────────────────────────

  /// 공고 지원 (flex: slotId 필수, contract: slotId null)
  /// [CF 이전 2026-07-14] callableApplyToTO — 검증+쓰기+카운터 증감 원자화
  ///   이전 이유: 클라이언트 runTransaction(검증)과 batch(쓰기) 분리로 TOCTOU 가능
  ///             서류/블랙리스트/제재/시간충돌 검증이 클라이언트에서만 이루어져 위조 가능
  /// [A02-FIX] 복합 docId: CF에서 동일하게 계산 — 동시 지원 시 트랜잭션 충돌로 하나만 성공
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
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableApplyToTO',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'toId': toId,
        if (slotId != null) 'slotId': slotId,
        'businessId': businessId,
        'businessName': businessName,
        'toTitle': toTitle,
        'workDateMs': workDate.millisecondsSinceEpoch,
        'selectedWorkType': selectedWorkType,
        if (workDetailId != null && workDetailId.isNotEmpty) 'workDetailId': workDetailId,
        'startTime': startTime,
        'endTime': endTime,
        'wage': wage,
        'wageType': wageType,
        if (workTypeIcon != null) 'workTypeIcon': workTypeIcon,
        if (workTypeColor != null) 'workTypeColor': workTypeColor,
        if (workTypeBackgroundColor != null) 'workTypeBackgroundColor': workTypeBackgroundColor,
        if (workEndDate != null) 'workEndDateMs': workEndDate.millisecondsSinceEpoch,
        if (workDays != null) 'workDays': workDays,
        if (desiredStartDate != null) 'desiredStartDateMs': desiredStartDate.millisecondsSinceEpoch,
      });
      final data = result.data;
      final applicationId = data['applicationId'] as String? ?? '';
      final isReactivation = data['isReactivation'] as bool? ?? false;

      clearCache(toId: toId);
      invalidateMyApplicationsCache(uid);
      try {
        _sendNewApplicationNotification(
          businessId: businessId,
          applicantUid: uid,
          workType: selectedWorkType,
          workDate: workDate,
          applicationId: applicationId,
          toId: toId,
          workDetailId: workDetailId ?? '',
        );
      } catch (notifErr) {
        debugPrint('⚠️ ${isReactivation ? "재지원" : "지원"} 알림 전송 실패 (지원은 완료됨): $notifErr');
      }
      debugPrint('✅ ${isReactivation ? "재지원" : "지원"} 완료: $toTitle / $selectedWorkType');
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ 지원 CF 오류: ${e.code} / ${e.message}');
      final msg = e.message ?? '지원 중 오류가 발생했습니다.';
      if (e.code == 'already-exists') {
        ToastHelper.showWarning(msg);
      } else {
        ToastHelper.showError(msg);
      }
      return false;
    } catch (e) {
      debugPrint('❌ 지원 실패: $e');
      ToastHelper.showError('지원 중 오류가 발생했습니다.');
      return false;
    }
  }

  // ───────────────────────────────────────────────────────
  // 상태 변경
  // ───────────────────────────────────────────────────────

  /// 지원서 거절 — callableRejectApplication CF 호출
  /// rejectedBy는 CF에서 callerUid로 서버 강제 (클라이언트 위조 불가)
  /// statusHistory.at도 CF 서버 타임스탬프로 기록
  Future<void> rejectApplication(String applicationId, {String? message}) async {
    NetworkChecker.instance.assertOnline('거절 처리를 하려면 인터넷 연결이 필요합니다.');
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableRejectApplication',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
      await callable.call<Map<String, dynamic>>({
        'applicationId': applicationId,
        if (message != null) 'message': message,
      });
    } on FirebaseFunctionsException {
      rethrow;
    } catch (e) {
      debugPrint('❌ [Application] 거절 실패: $e');
      rethrow;
    }
  }

  /// 지원자 확정 (충돌 지원서 자동 취소 포함)
  /// 반환: 충돌로 취소된 TO ID 목록
  Future<List<String>> updateApplicationStatus({
    required String applicationId,
    required String status,
    String? confirmedBy,
    String? rejectedBy,
    String? canceledBy,
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

      // [CF-ONLY] REJECTED → callableRejectApplication (rejectedBy 서버 강제)
      if (status == AppStatus.rejected) {
        await rejectApplication(applicationId, message: message);
        return [];
      }

      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get(const GetOptions(source: Source.server));
      if (!appDoc.exists) return [];

      final appData = appDoc.data()!;
      final prevStatus = appData['status'] as String?;
      final toId = appData['toId'] as String?;
      final slotId = appData['slotId'] as String?;
      final selectedWorkType = appData['selectedWorkType'] as String?;

      // 확정/계약 서명 상태는 거절로 전이 불가 (cancelConfirmedApplication() 사용)
      if (status == AppStatus.rejected &&
          AppStatus.confirmedStatuses.contains(prevStatus)) {
        ToastHelper.showError('확정된 지원서는 거절할 수 없습니다.\n취소 처리를 이용해주세요.');
        return [];
      }

      // [B-001] 비활성 상태(거절/취소)의 지원서는 관리자가 직접 PENDING으로 되돌릴 수 없음
      // 재지원은 callableApplyToTO CF 경로(지원자 직접 재지원)만 허용 — wage/startTime 등 재검증 필요
      if (status == AppStatus.pending && AppStatus.inactiveStates.contains(prevStatus)) {
        ToastHelper.showError('거절/취소된 지원서는 재활성화할 수 없습니다.\n지원자가 직접 재지원해야 합니다.');
        return [];
      }

      // [DEAD-CODE-REMOVED] REJECTED 분기는 line 391에서 CF 호출 후 이미 return됨
      // → rejectedBy 클라이언트 직접 쓰기 취약점이 활성화되지 않으나 코드 명확성을 위해 제거
      final updates = <String, dynamic>{'status': status};
      if (status == AppStatus.canceled) {
        updates['canceledAt'] = FieldValue.serverTimestamp();
        // canceledBy는 rules에서 admin 경로 직접 쓰기 차단 — statusHistory.by로 감사 로그 대체
        // statusHistory.at: Firestore 배열 요소 내부에서 serverTimestamp() 미지원
        // → 클라이언트 시계 사용이 불가피. 법적 근거는 루트 canceledAt(serverTimestamp)을 사용.
        updates['statusHistory'] = _appendHistory(appData, {
          'status': 'CANCELED',
          'at': Timestamp.now(),
          'by': canceledBy,
          'action': 'ADMIN_CANCEL',
        });
      } else if (status == AppStatus.pending &&
          AppStatus.confirmedStatuses.contains(prevStatus)) {
        // confirmed → pending 롤백 이력 기록
        updates['statusHistory'] = _appendHistory(appData, {
          'status': 'PENDING',
          'at': Timestamp.now(),
          'by': confirmedBy,
          'action': 'CONFIRM_ROLLBACK',
        });
      }

      final batch = _firestore.batch();
      batch.update(appDoc.reference, updates);
      // [PERM-FIX] TO 카운터(totalConfirmed/totalPending) 직접 쓰기는
      // rules에서 isSuperAdmin() / isUser() 전용 — isToAdmin 경로 차단.
      // 배치에 포함 시 PERMISSION_DENIED → application 상태 업데이트까지 실패.
      // 아래 별도 counterBatch에서 비임계 처리 (실패 시 CF syncTOStats 교정).

      await batch.commit();

      // [H-CF-2] 확정 취소/취소 시 계약서 무효화 — callableVoidApplicationContracts CF 경유
      // assertBizAdmin 서버 교차검증. application 상태 변경(batch) 완료 후 처리.
      // 원자성 분리: CF 실패 시 계약서가 유령 상태로 남을 수 있으나 application은 이미 복구됨.
      // [BUG-FIX] CANCELED 경로도 포함 — CONFIRMED→CANCELED 시 계약서 유령 상태 방지
      if ((status == AppStatus.pending || status == AppStatus.canceled) &&
          AppStatus.confirmedStatuses.contains(prevStatus)) {
        try {
          final contractBusinessId = appData['businessId'] as String? ?? '';
          await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('callableVoidApplicationContracts')
              .call({'applicationId': applicationId, 'businessId': contractBusinessId});
        } catch (e) {
          debugPrint('⚠️ [H-CF-2] 계약서 무효화 CF 실패 (복구 가능): $e');
          ToastHelper.showWarning('계약서 무효화 처리 중 오류가 발생했습니다. 계약서를 직접 확인해 주세요.');
        }
      }

      // TO/슬롯 카운터 낙관적 업데이트 — 비임계 별도 배치
      // tos totalConfirmed/totalPending은 rules상 admin 직접 쓰기 불가(PERMISSION_DENIED 가능).
      // 슬롯 confirmedCount/pendingCount(±1)는 isToAdmin 허용이지만 같은 배치라 같이 실패.
      // CF syncTOStats가 최종 교정하므로 실패는 UI 일시 불일치만 발생.
      if (toId != null) {
        try {
          final counterBatch = _firestore.batch();
          if (AppStatus.confirmedStatuses.contains(prevStatus)) {
            _decrementTOConfirmed(counterBatch, toId, slotId, workType: selectedWorkType);
            if (status == AppStatus.pending) {
              _incrementTOPending(counterBatch, toId, slotId, delta: 1, workType: selectedWorkType);
            }
          } else if (prevStatus == AppStatus.pending) {
            _incrementTOPending(counterBatch, toId, slotId, delta: -1, workType: selectedWorkType);
          }
          await counterBatch.commit();
        } catch (e) {
          debugPrint('⚠️ [updateApplicationStatus] TO 카운터 낙관적 업데이트 실패 — CF syncTOStats 교정 예정: $e');
        }
        clearCache(toId: toId);
      }

      // 알림
      final applicantUid = appData['uid'] as String? ?? '';
      if (applicantUid.isEmpty) return [];
      invalidateMyApplicationsCache(applicantUid);
      if (AppStatus.confirmedStatuses.contains(prevStatus)) {
        await createNotification(NotificationModel.createConfirmationCanceled(
          userId: applicantUid,
          businessName: appData['businessName'] as String? ?? '',
          businessId: appData['businessId'] as String? ?? '',
          workType: appData['selectedWorkType'] as String? ?? '',
          workDate: (appData['workDate'] as Timestamp?)?.toDate().toLocal() ?? DateTime.now(),
          applicationId: applicationId,
          cancelReason: message,
        ));
      } else if (prevStatus == AppStatus.pending && status == AppStatus.rejected) {
        await createNotification(NotificationModel.createApplicationRejected(
          userId: applicantUid,
          businessName: appData['businessName'] as String? ?? '',
          businessId: appData['businessId'] as String? ?? '',
          workType: appData['selectedWorkType'] as String? ?? '',
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
          .get(const GetOptions(source: Source.server));
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
      if (currentStatus == AppStatus.rejected) {
        ToastHelper.showInfo('이미 거절된 지원서입니다.');
        return true;
      }
      if (AppStatus.inactiveStates.contains(currentStatus)) {
        ToastHelper.showInfo('이미 취소된 지원서입니다.');
        return true;
      }

      final toId = appData['toId'] as String?;
      final slotId = appData['slotId'] as String?;

      // [A03-FIX] TOCTOU 방지: 조회(get) 이후 배치 커밋 사이에 관리자가 지원자를
      // 확정(CONTRACT_PENDING/CONFIRMED)할 수 있다. 트랜잭션으로 서버 상태를 재확인해
      // 확정된 지원서를 사용자가 취소하는 것을 원자적으로 막는다.
      await _firestore.runTransaction((tx) async {
        final fresh = await tx.get(appDoc.reference);
        final freshStatus = fresh.data()?['status'] as String?;
        if (AppStatus.confirmedStatuses.contains(freshStatus)) {
          throw Exception('확정된 TO는 취소할 수 없습니다.');
        }
        if (AppStatus.inactiveStates.contains(freshStatus)) {
          // 이미 취소됨 — 멱등 처리
          return;
        }
        // 트랜잭션 시작 후 문서가 삭제된 경우(경쟁조건) — 멱등 처리
        final freshData = fresh.data();
        if (freshData == null) return;
        tx.update(appDoc.reference, {
          'status': 'CANCELED',
          'canceledAt': FieldValue.serverTimestamp(),
          // [CANCEL-FIX] 취소 주체를 명시해 관리자(ADMIN_CANCELED)/사용자(USER_CANCELED)를 구분.
          // 이전 코드는 cancelReason을 저장하지 않아 분쟁 발생 시 취소 경위 추적이 불가능했다.
          'cancelReason': 'USER_CANCELED',
          // [RACE-FIX] 트랜잭션 외부 스냅샷(appData)의 statusHistory 사용 → 동시 업데이트 시 유실
          // freshData로 교체하여 트랜잭션 내 최신 데이터 기반으로 append
          'statusHistory': _appendHistory(freshData, {
            'status': 'CANCELED',
            'at': Timestamp.now(),
            'by': uid,
            'action': 'CANCEL',
            'reason': 'USER_CANCELED',
          }),
        });
        if (toId != null) {
          // [낙관적 카운터] 앱이 먼저 ±1 반영 → CF syncTOStats가 나중에 count()로 교정.
          // 이 increment가 실패해도 CF가 자동 복구하므로 rollback 불필요.
          // [특이사항] workTypeCounts.$workType.pendingCount는 CF가 재계산하므로 이중 쓰기 발생.
          //   최종값은 CF가 덮어쓰며, 이 increment는 CF 실행 전까지 UI 즉각 반영을 위한 것.
          tx.update(_firestore.collection('tos').doc(toId), {
            'totalPending': FieldValue.increment(-1),
          });
          if (slotId != null) {
            // [A1-FIX 누락 수정] workTypeCounts는 CF callableIncrementSlotPending이 처리.
            // USER rules는 hasOnly(['pendingCount'])만 허용 — workTypeCounts 포함 시 PERMISSION_DENIED.
            tx.update(
              _firestore.collection('tos').doc(toId).collection('slots').doc(slotId),
              {
                'pendingCount': FieldValue.increment(-1),
              },
            );
          }
        }
      });
      if (toId != null) clearCache(toId: toId);
      invalidateMyApplicationsCache(uid); // 내 지원 목록 캐시 무효화

      await _cleanupApplicationRelatedData(
        applicationId: applicationId,
        uid: uid,
        // USER 자기 취소 — targetUserId 필터 경로 (businessId 미전달)
      );
      if (toId != null) {
        _sendApplicationCanceledNotification(
          businessId: appData['businessId'] as String? ?? '',
          applicantUid: uid,
          workType: appData['selectedWorkType'] as String? ?? '',
          workDate: (appData['workDate'] as Timestamp?)?.toDate().toLocal() ?? DateTime.now(),
          applicationId: applicationId,
          toId: toId,
          workDetailId: appData['workDetailId'] as String? ?? '',
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
  // [CF-ONLY] application 상태 업데이트는 callableCancelConfirmedApplication CF로 이전
  //   canceledBy 위조 차단: 관리자 A가 관리자 B UID를 전달해 책임 전가하는 공격 차단
  //   statusHistory.at 위조 차단: 클라이언트 Timestamp.now() → CF 서버 시간
  // canceledBy 파라미터는 하위 호환 유지 — CF 내부에서 callerUid로 대체됨
  Future<bool> cancelConfirmedApplication(
    String applicationId, {
    bool applyNoShowPenalty = false,
    String? canceledBy,   // 하위 호환 — CF가 callerUid로 대체, 이 값은 무시됨
    String? cancelReason, // 관리자 취소 사유
  }) async {
    NetworkChecker.instance.assertOnline('확정 취소를 하려면 인터넷 연결이 필요합니다.');
    try {
      // 1. CF로 application 상태 업데이트 (canceledBy·at 서버 강제)
      final cancelCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCancelConfirmedApplication',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
      final cfResult = await cancelCallable.call<Map<String, dynamic>>({
        'applicationId': applicationId,
        if (cancelReason != null) 'cancelReason': cancelReason,
        if (applyNoShowPenalty) 'applyNoShowPenalty': true,
      });
      final cfData = Map<String, dynamic>.from(cfResult.data as Map);
      final uid = cfData['workerUid'] as String? ?? '';
      if (uid.isEmpty) return false;

      final toId = cfData['toId'] as String?;
      final slotId = cfData['slotId'] as String?;
      final selectedWorkType = cfData['selectedWorkType'] as String?;
      final businessId = cfData['businessId'] as String?;
      final businessName = cfData['businessName'] as String? ?? '';
      final isAdminCancel = cfData['isAdminCancel'] as bool? ?? false;
      final workDateMs = cfData['workDateMs'] as int?;
      final workDetailId = cfData['workDetailId'] as String? ?? '';
      final workDate = workDateMs != null
          ? DateTime.fromMillisecondsSinceEpoch(workDateMs).toLocal()
          : DateTime.now();

      // 2. 슬롯 확정 인원 감소 (CF)
      if (toId != null) {
        clearCache(toId: toId);
        try {
          final decrementCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('callableDecrementSlotConfirmed',
                  options: HttpsCallableOptions(timeout: const Duration(seconds: 10)));
          await decrementCallable.call({
            'applicationId': applicationId,
            'toId': toId,
            'slotId': slotId,
            'workType': selectedWorkType,
          });
        } catch (e) {
          debugPrint('⚠️ slot confirmedCount 감소 CF 실패 (syncTOStats 복구 예정): $e');
        }
      }

      // 3. 노쇼 패널티 (CF)
      if (applyNoShowPenalty) {
        try {
          final penaltyCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('callableApplyNoShowPenalty',
                  options: HttpsCallableOptions(timeout: const Duration(seconds: 10)));
          await penaltyCallable.call({'applicationId': applicationId});
        } catch (e) {
          debugPrint('⚠️ 노쇼 패널티 CF 실패 ($uid): $e');
        }
      }

      // 4. 취소 후 슬롯 상태('full'→'open') 재계산
      if (toId != null && slotId != null) {
        await _recalculateSlotStatus(toId, slotId);
      }

      // 5. 관련 데이터 정리
      final cleanupBusinessId = isAdminCancel
          ? (businessId?.isEmpty ?? true) ? null : businessId
          : null;
      await _cleanupApplicationRelatedData(
        applicationId: applicationId,
        uid: uid,
        businessId: cleanupBusinessId,
      );

      // 6. 알림 발송
      if (isAdminCancel) {
        await createNotification(NotificationModel.createConfirmationCanceled(
          userId: uid,
          businessName: businessName,
          businessId: businessId ?? '',
          workType: selectedWorkType ?? '',
          workDate: workDate,
          applicationId: applicationId,
          cancelReason: cancelReason,
        ));
      } else {
        // M-1: 근무자 자기 취소 시 관리자에게 확정취소 알림
        try {
          final bId = businessId ?? '';
          if (bId.isNotEmpty) {
            final bizDoc = await _firestore.collection('businesses').doc(bId)
                .get(const GetOptions(source: Source.server));
            final adminIds = List<String>.from(bizDoc.data()?['adminIds'] as List? ?? []);
            if (adminIds.isEmpty) {
              final fallback = bizDoc.data()?['ownerId'] as String?;
              if (fallback != null && fallback.isNotEmpty) adminIds.add(fallback);
            }
            if (adminIds.isNotEmpty) {
              final workerDoc = await _firestore.collection('users').doc(uid)
                  .get(const GetOptions(source: Source.server));
              final workerName = workerDoc.data()?['name'] as String? ?? '근무자';
              for (final adminUid in adminIds) {
                await createNotification(NotificationModel.createConfirmationCanceledByWorker(
                  userId: adminUid,
                  workerName: workerName,
                  workType: selectedWorkType ?? '',
                  workDate: workDate,
                  applicationId: applicationId,
                  businessId: bId,
                  toId: toId ?? '',
                  workDetailId: workDetailId,
                ));
              }
            }
          }
        } catch (e) {
          debugPrint('⚠️ [M-1] 근무자 확정 취소 관리자 알림 발송 실패: $e');
        }
      }

      debugPrint('✅ 확정 취소 완료 (관리자: $isAdminCancel, 패널티: $applyNoShowPenalty)');
      return true;
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') {
        ToastHelper.showError('지원서를 찾을 수 없습니다');
        return false;
      }
      if (e.code == 'failed-precondition') {
        ToastHelper.showError(e.message ?? '확정된 지원만 취소할 수 있습니다');
        return false;
      }
      debugPrint('❌ 확정 취소 CF 오류: ${e.code} ${e.message}');
      ToastHelper.showError('확정 취소에 실패했습니다');
      return false;
    } catch (e) {
      debugPrint('❌ 확정 취소 실패: $e');
      ToastHelper.showError('확정 취소에 실패했습니다');
      return false;
    }
  }

  /// 지원자 업무유형 변경 (관리자용)
  // [WORK-TYPE-CF] callableChangeApplicationWorkType CF 호출 — 카운터 증감·attendance wagePending 서버 강제.
  // assertBizAdmin + businessId 교차검증은 CF 내부에서 처리.
  Future<bool> changeApplicationWorkType({
    required String applicationId,
    required String newWorkType,
    required int newWage,
    required String adminUID,
    String? newWorkDetailId,
    // [B-1] 파트변경 시 wageType·아이콘·색상도 함께 업데이트 — 미전달 시 급여 계산 오류 유발
    String? newWageType,
    String? newWorkTypeIcon,
    String? newWorkTypeColor,
    String? newWorkTypeBackgroundColor,
  }) async {
    try {
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get(const GetOptions(source: Source.server));
      if (!appDoc.exists) {
        ToastHelper.showError('지원서를 찾을 수 없습니다.');
        return false;
      }
      final appData = appDoc.data()!;
      final currentWorkType = appData['selectedWorkType'] as String? ?? '';
      final businessId = appData['businessId'] as String? ?? '';
      final toId = appData['toId'] as String?;
      final slotId = appData['slotId'] as String?;

      if (currentWorkType == newWorkType) {
        ToastHelper.showError('동일한 업무유형입니다.');
        return false;
      }

      // 새 업무유형의 모집인원 초과 여부 경고 (차단하지 않음 — 관리자 의도 허용)
      if (toId != null && slotId != null) {
        final slotSnap = await _firestore
            .collection('tos').doc(toId)
            .collection('slots').doc(slotId).get(const GetOptions(source: Source.server));
        if (slotSnap.exists) {
          final slotData = slotSnap.data()!;
          final workDetails = (slotData['workDetails'] as List? ?? [])
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
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
        final toSnap = await _firestore.collection('tos').doc(toId).get(const GetOptions(source: Source.server));
        if (toSnap.exists) {
          final toData = toSnap.data()!;
          final workDetails = (toData['workDetails'] as List? ?? [])
              .whereType<Map>()
              .map((m) => Map<String, dynamic>.from(m))
              .toList();
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

      final cfCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableChangeApplicationWorkType',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 60)));
      await cfCallable.call({
        'applicationId': applicationId,
        'businessId': businessId,
        'newWorkType': newWorkType,
        'newWage': newWage,
        if (newWorkDetailId != null) 'newWorkDetailId': newWorkDetailId,
        if (newWageType != null) 'newWageType': newWageType,
        if (newWorkTypeIcon != null) 'newWorkTypeIcon': newWorkTypeIcon,
        if (newWorkTypeColor != null) 'newWorkTypeColor': newWorkTypeColor,
        if (newWorkTypeBackgroundColor != null) 'newWorkTypeBackgroundColor': newWorkTypeBackgroundColor,
      });

      if (toId != null) clearCache(toId: toId);

      // Toast는 호출부(work_applicants_dialog)에서 표시 — 중복 방지
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ 업무유형 변경 CF 실패: ${e.code} ${e.message}');
      ToastHelper.showError(e.message ?? '업무유형 변경에 실패했습니다.');
      return false;
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
  ///
  /// [설계 원칙] 반드시 순차 처리(for-loop)를 사용한다.
  /// 이전 코드는 Future.wait으로 병렬 확정을 시도했으나, 같은 지원자의 여러 지원서를
  /// 동시에 확정하면 _confirmWithConflictCheck 내부의 CONTRACT_PENDING 선점 트랜잭션이
  /// 서로 충돌(이슈 #186)을 필연적으로 일으킨다. 순차 처리 시 앞 확정이 완료된 후
  /// 충돌 탐지가 정상 작동해 자동 취소까지 올바르게 처리된다.
  Future<BatchResult> batchConfirmApplications({
    required List<String> applicationIds,
    required String adminUID,
  }) async {
    if (applicationIds.isEmpty) return BatchResult(success: 0, failed: 0);
    int success = 0;
    int failed = 0;
    // failedIds로 부분 실패 시 재처리 대상 applicationId 특정 가능
    final List<String> failedIds = [];
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
        failedIds.add(id); // 실패한 applicationId 기록
      }
    }
    return BatchResult(success: success, failed: failed, failedIds: failedIds);
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
      // [PERF-2026-07-16] 별도 CF 호출(limit:2000) 대신 getMyApplications 캐시 재사용
      // PENDING/CONTRACT_PENDING은 최근 항목이므로 limit:200으로 충분; 캐시 히트 시 latency 없음
      final statusFilter = Set<String>.from(statuses ?? [AppStatus.pending, AppStatus.contractPending]);
      final allApps = await getMyApplications(uid);
      return allApps
          .where((a) => a.id != excludeId)
          .where((a) => statusFilter.contains(a.status))
          .where((a) => a.isWorkingOnDate(workDate))
          .where((a) => ApplicationModel.hasTimeOverlap(startTime, endTime, a.startTime, a.endTime))
          .toList();
    } catch (e) {
      debugPrint('❌ 충돌 지원서 조회 실패: $e');
      return [];
    }
  }

  /// 특정 날짜 × 사업장의 단기 PENDING 지원자 조회 (지원명단용)
  /// [CF 이전 2026-07-13] callableGetApplicationsByBiz (workDateGteMs/LtMs)
  Future<List<ApplicationModel>> getPendingApplicationsByDateAndBusiness({
    required DateTime date,
    required String businessId,
  }) async {
    final dateStart = DateTime(date.year, date.month, date.day);
    final dateEnd = dateStart.add(const Duration(days: 1));
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetApplicationsByBiz',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': businessId,
        'workDateGteMs': dateStart.millisecondsSinceEpoch,
        'workDateLtMs': dateEnd.millisecondsSinceEpoch,
        'limit': 2000,
      });
      return (result.data['applications'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return ApplicationModel.tryFromMap(raw, id);
          })
          .whereType<ApplicationModel>()
          .where((app) => app.status == AppStatus.pending && !app.isLongTermApplication)
          .toList();
    } catch (e) {
      debugPrint('❌ 지원자 조회 실패: $e');
      return [];
    }
  }

  /// 지원자 거절 처리 + 근무자 알림 발송 (지원명단 다이얼로그용)
  ///
  /// [D-04 수정] 알림 중복 발송 제거:
  /// updateApplicationStatus() 내부에서 PENDING→REJECTED 전이 시
  /// createNotification(createApplicationRejected(...))를 이미 호출하므로,
  /// 이전에 존재하던 직접 Firestore 쓰기(중복 경로)를 제거했다.
  /// rejectReason은 message 파라미터로 updateApplicationStatus()에 전달한다.
  Future<void> rejectApplicationWithNotification({
    required String applicationId,
    required String workerUid,
    required String businessId,
    required String businessName,
    required String workType,
    required DateTime workDate,
    required String rejectedBy,
    String? rejectReason,
  }) async {
    await updateApplicationStatus(
      applicationId: applicationId,
      status: AppStatus.rejected,
      rejectedBy: rejectedBy,
      message: rejectReason,
    );
  }

  /// 특정 날짜 × 사업장의 확정 근무자 조회 (단기 + 장기 병합)
  /// [CF 이전 2026-07-13] callableGetApplicationsByBiz (workDateGteMs/LtMs, workEndDateGteMs)
  Future<List<ApplicationModel>> getConfirmedWorkersByDateAndBusiness({
    required DateTime date,
    required String businessId,
  }) async {
    final dateStart = DateTime(date.year, date.month, date.day);
    final dateEnd = dateStart.add(const Duration(days: 1));

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetApplicationsByBiz',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final futures = await Future.wait([
        callable.call<Map<String, dynamic>>({
          'businessId': businessId,
          'workDateGteMs': dateStart.millisecondsSinceEpoch,
          'workDateLtMs': dateEnd.millisecondsSinceEpoch,
          'limit': 2000,
        }),
        callable.call<Map<String, dynamic>>({
          'businessId': businessId,
          'workEndDateGteMs': dateStart.millisecondsSinceEpoch,
          'limit': 2000,
        }),
      ]);

      List<ApplicationModel> parseApps(HttpsCallableResult<Map<String, dynamic>> r) =>
          (r.data['applications'] as List? ?? [])
              .whereType<Map>()
              .map((m) {
                final raw = _cfHydrate(Map<String, dynamic>.from(m));
                final id = raw.remove('id') as String? ?? '';
                return ApplicationModel.tryFromMap(raw, id);
              })
              .whereType<ApplicationModel>()
              .toList();

      final results = futures.map(parseApps).toList();

      // [B01-FIX] 단기 쿼리 결과에 type 필터가 없어 장기 지원서(type=long_term)가
      // workDate == 오늘인 경우 shortTermApps에도 포함될 수 있는 중복 버그 수정.
      // isLongTermApplication getter로 클라이언트 필터링하여 단기만 남긴다.
      const confirmedStatuses = {AppStatus.confirmed, AppStatus.contractPending};
      final shortTermApps = results[0]
          .where((app) => confirmedStatuses.contains(app.status) && !app.isLongTermApplication)
          .toList();

      final longTermCandidates = results[1]
          .where((app) => confirmedStatuses.contains(app.status) && app.workDays != null && app.workDays!.isNotEmpty)
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

        // [F02-FIX] extraWorkDates 우선 처리 — 비정규 요일 추가 근무일이면
        // workDays에 해당 요일이 없어도 당일명단에 포함되어야 한다.
        // isWorkingOnDate getter와 동일한 우선순위(extra → leave → workDays)를 유지한다.
        final isExtraWork = app.extraWorkDates != null &&
            app.extraWorkDates!.any((d) =>
                d.year == dateStart.year && d.month == dateStart.month && d.day == dateStart.day);
        if (isExtraWork) {
          result.add(app);
          continue;
        }

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
    // TTL 캐시 — 날짜별 3분 캐시 (지원 상태 변경 시 invalidateMyApplicationsCache로 무효화)
    final dateStr = '${workDate.year}-${workDate.month.toString().padLeft(2, '0')}-${workDate.day.toString().padLeft(2, '0')}';
    final cacheKey = '${uid}_$dateStr';
    final cached = _confirmedSchedulesCache[cacheKey];
    final cachedTs = _confirmedSchedulesCacheTs[cacheKey];
    if (cached != null && cachedTs != null &&
        DateTime.now().difference(cachedTs) < FirestoreService._confirmedSchedulesCacheTTL) {
      return cached;
    }

    try {
      // [PERF-2026-07-16] 단기/장기 분리 병렬 조회로 전환 — 기존 limit:2000 단일 조회 대비 데이터 전송량 90%↓
      // 단기: isLongTerm=false 서버 필터 + 클라이언트 날짜 필터 (limit:200)
      // 장기: isLongTerm=true 서버 필터 + 클라이언트 스케줄 필터 (limit:50)
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetMyApplications',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));

      final results = await Future.wait([
        callable.call<Map<String, dynamic>>({
          'statuses': AppStatus.confirmedStatuses,
          'isLongTerm': false,
          'limit': 200,
        }),
        callable.call<Map<String, dynamic>>({
          'statuses': AppStatus.confirmedStatuses,
          'isLongTerm': true,
          'limit': 50,
        }),
      ]);

      ApplicationModel? parseApp(Map m) {
        final raw = _cfHydrate(Map<String, dynamic>.from(m));
        final id = raw.remove('id') as String? ?? '';
        return ApplicationModel.tryFromMap(raw, id);
      }

      final shortTermAll = (results[0].data['applications'] as List? ?? [])
          .whereType<Map>().map(parseApp).whereType<ApplicationModel>().toList();
      final longTermAll = (results[1].data['applications'] as List? ?? [])
          .whereType<Map>().map(parseApp).whereType<ApplicationModel>().toList();

      final dateStart = DateTime(workDate.year, workDate.month, workDate.day);
      final dateEnd = dateStart.add(const Duration(days: 1));

      final shortTerm = shortTermAll.where((a) {
        final wd = DateTime(a.workDate.year, a.workDate.month, a.workDate.day);
        return !wd.isBefore(dateStart) && wd.isBefore(dateEnd);
      }).toList();

      final longTermCandidates = longTermAll
          .where((a) => a.isWorkingOnDate(workDate))
          .toList();

      final combined = [...shortTerm, ...longTermCandidates];
      _confirmedSchedulesCache[cacheKey] = combined;
      _confirmedSchedulesCacheTs[cacheKey] = DateTime.now();
      return combined;
    } catch (e) {
      debugPrint('❌ 확정 일정 조회 실패: $e');
      return cached ?? [];
    }
  }

  // ───────────────────────────────────────────────────────
  // 내부 헬퍼
  // ───────────────────────────────────────────────────────

  /// 확정 처리 (충돌 자동 취소 포함) — [MED-3] callableConfirmApplication CF 이전
  /// 트랜잭션·CAPACITY-GUARD·배치·슬롯 재계산·확정 알림을 서버에서 원자적으로 처리
  Future<List<String>> _confirmWithConflictCheck({
    required String applicationId,
    String? confirmedBy,
    String? message,
  }) async {
    NetworkChecker.instance.assertOnline('지원자 확정을 하려면 인터넷 연결이 필요합니다.');

    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableConfirmApplication',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));

    final result = await callable.call<Map<String, dynamic>>({
      'applicationId': applicationId,
      if (message != null) 'message': message,
    });

    final data = result.data;
    if (data['alreadyConfirmed'] == true) return [];

    final capacityWarning = data['capacityWarning'] as Map<String, dynamic>?;
    if (capacityWarning != null) {
      ToastHelper.showWarning(
        '[${capacityWarning['workType']}] 모집인원(${capacityWarning['required']}명)이 이미 찼습니다. 초과 확정됩니다.');
    }

    final appInfo = (data['appInfo'] as Map?)?.cast<String, dynamic>() ?? {};
    final toId = appInfo['toId'] as String?;
    final uid = appInfo['uid'] as String? ?? '';
    final businessId = appInfo['businessId'] as String? ?? '';
    final businessName = appInfo['businessName'] as String? ?? '';
    final startTime = appInfo['startTime'] as String? ?? '';
    final endTime = appInfo['endTime'] as String? ?? '';
    final isLongTerm = appInfo['isLongTerm'] as bool? ?? false;
    final workDateMs = appInfo['workDateMs'] as int? ?? 0;
    final startDateMs = appInfo['startDateMs'] as int?;
    final workEndDateMs = appInfo['workEndDateMs'] as int?;
    final workDays = (appInfo['workDays'] as List?)?.cast<String>();

    if (toId != null) clearCache(toId: toId);
    if (uid.isNotEmpty) invalidateMyApplicationsCache(uid);

    // [SEC-FIX] 충돌 AUTO_CANCEL → CF 이전 (callableAutoConflictCancel)
    // 이유: BUSINESS_ADMIN이 uid 단독 LIST 쿼리 시 보안 규칙에서 PERMISSION_DENIED
    //   → 클라이언트에서 타사업장 포함 전체 충돌 탐색 불가 → Admin SDK CF로 처리
    List<Map<String, dynamic>> canceledDetails = [];
    try {
      final autoConflictCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableAutoConflictCancel',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final autoConflictResult = await autoConflictCallable.call({
        'confirmedAppId': applicationId,
        'targetUid': uid,
        'businessId': businessId,
        'businessName': businessName,
        'startTime': startTime,
        'endTime': endTime,
        if (!isLongTerm) 'workDate': workDateMs,
        if (isLongTerm) ...{
          'isLongTerm': true,
          'startDate': startDateMs ?? workDateMs,
          if (workEndDateMs != null) 'endDate': workEndDateMs,
          if (workDays != null) 'workDays': workDays,
        },
      });
      canceledDetails = ((autoConflictResult.data as Map?)?['canceledDetails'] as List? ?? [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      debugPrint('✅ AUTO_CANCEL CF 완료 — ${canceledDetails.length}건 취소');
    } catch (e) {
      debugPrint('⚠️ AUTO_CANCEL CF 실패 (확정은 완료됨): $e');
    }

    // 자동 취소된 충돌 지원서의 TO 캐시 무효화
    final Set<String> affectedTOIds = {};
    for (final detail in canceledDetails) {
      final cId = detail['id'] as String?;
      if (cId != null) affectedTOIds.add(cId);
    }
    for (final tId in affectedTOIds) {
      clearCache(toId: tId);
    }

    // 자동 취소된 충돌 지원서 알림
    final fallbackDate = workDateMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(workDateMs)
        : DateTime.now();
    for (final detail in canceledDetails) {
      final detailWorkDateMs = detail['workDateMs'] as int?;
      _sendApplicationAutoCanceledNotification(
        applicantUid: detail['uid'] as String? ?? '',
        businessName: detail['businessName'] as String? ?? '',
        businessId: detail['businessId'] as String? ?? '',
        workType: detail['selectedWorkType'] as String? ?? '',
        workDate: detailWorkDateMs != null
            ? DateTime.fromMillisecondsSinceEpoch(detailWorkDateMs)
            : fallbackDate,
        applicationId: detail['id'] as String? ?? '',
        conflictingBusinessName: businessName,
        conflictingTime: '$startTime~$endTime',
      );
    }

    debugPrint('✅ 확정 완료 + ${canceledDetails.length}건 AUTO_CANCEL');
    return affectedTOIds.toList();
  }

  /// TO.totalPending 및 Slot.pendingCount 변경
  /// [A1-FIX] workTypeCounts 업데이트 제거 — callableIncrementSlotPending CF로 이전.
  /// rules에서 isUser() slots update의 workTypeCounts 허용 삭제로 맵 전체 교체 취약점 차단.
  /// workTypeCounts.pendingCount는 CF가 dot-notation으로 정밀 업데이트 (confirmedCount 보호).
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
      // [A1-FIX] workTypeCounts 제거 — CF callableIncrementSlotPending이 별도로 처리
      batch.update(slotRef, {
        'pendingCount': FieldValue.increment(delta),
      });
    }
  }

  // [A1-FIX] workTypeCounts.pendingCount는 callableIncrementSlotPending CF(Admin SDK)가
  // dot-notation으로 정밀 업데이트. 현재는 pendingCount만 rules에서 허용하며,
  // workTypeCounts 통계 정밀도가 필요할 때 CF 호출을 추가한다.
  //
  // ⚠️ [이중 카운트 방지] CF 호출 추가 시 필수 확인:
  // callableIncrementSlotPending은 totalPending + pendingCount + workTypeCounts.pendingCount를
  // 모두 업데이트한다. CF 호출 코드가 추가되면 _incrementTOPending의 totalPending/pendingCount
  // 업데이트(위 batch.update 두 곳)를 반드시 제거해야 한다. 제거 없이 CF까지 호출하면
  // 같은 지원에서 totalPending/pendingCount가 2씩 증가하는 이중 카운트 버그 발생.

  /// TO.totalConfirmed 및 Slot.confirmedCount 변경
  ///
  /// [skipWorkTypeCounts] CONFIRM 경로에서 true — workTypeCounts/workTypeConfirmedCounts는
  /// 트랜잭션(_confirmWithConflictCheck) 내에서 이미 increment됨. 배치에서 재증가 시 이중 카운트.
  /// CANCEL/DECREMENT 경로(delta=-1)는 false(기본값) — 트랜잭션 없음, 배치에서 직접 감소.
  ///
  /// [F01/F02/F03 동시성] FieldValue.increment()는 서버 측 원자 연산 → count 정확도 보장.
  /// [CRIT-02-FIX] 정원 초과 방지: 정원 검증 필드를 트랜잭션 내 write로 이동해
  ///   Firestore 낙관적 잠금 활성화. 두 트랜잭션이 같은 slotRef write 시 충돌 감지 → retry.
  void _incrementTOConfirmed(
    WriteBatch batch,
    String toId,
    String? slotId, {
    required int delta,
    String? workType,
    bool skipWorkTypeCounts = false,
  }) {
    final toUpdate = <String, dynamic>{
      'totalConfirmed': FieldValue.increment(delta),
    };
    // contract TO: workTypeConfirmedCounts — CONFIRM 경로에서 트랜잭션이 처리, 배치에서 skip
    if (!skipWorkTypeCounts && slotId == null && workType != null && workType.isNotEmpty) {
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
      // flex TO: workTypeCounts.$workType.confirmedCount — CONFIRM 경로에서 트랜잭션이 처리
      if (!skipWorkTypeCounts && workType != null) {
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
  // 슬롯 상태 재계산
  // ───────────────────────────────────────────────────────

  /// 확정 인원 변경 후 슬롯 status('open'↔'full') 재계산
  /// CLOSED 슬롯은 건드리지 않음
  ///
  /// [특이사항] CF syncTOStats도 동일한 슬롯 status를 count() 기반으로 덮어씀(이중 갱신).
  ///   이 함수는 CF 실행 전까지 즉각 UI 반영을 위한 낙관적 업데이트.
  ///   최종 status는 CF가 교정하므로 이 함수의 실패(catch)는 데이터 무결성에 영향 없음.
  Future<void> _recalculateSlotStatus(String toId, String slotId) async {
    final slotRef = _firestore
        .collection('tos').doc(toId)
        .collection('slots').doc(slotId);
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(slotRef);
        if (!snap.exists) return;
        final data = snap.data()!;
        // [B-2 수정] isManualClosed 가드 추가 — updateSlotStats와 일관성 유지
        if (data['status'] == 'closed' || data['isManualClosed'] == true) return;
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

  /// 지원서 취소/퇴사 시 연관 데이터(신분증요청, 스케줄변경, 출근기록) 일괄 정리
  ///
  /// [businessId] 유무에 따라 Firestore 보안 규칙 경로가 달라짐:
  ///   null → USER 경로: `targetUserId == uid` 필터 사용
  ///          (근무자 자기 취소: cancelApplication, cancelConfirmedApplication isAdminCancel=false)
  ///   non-null → ADMIN 경로: `requesterBusinessId == businessId` 필터 사용
  ///          (관리자 취소: cancelConfirmedApplication isAdminCancel=true)
  ///
  // [CF-MIGRATED 2026-07-15] callableCleanupApplicationData CF 이전 완료
  // Admin SDK로 idCardAccessRequests·schedule_change_requests·attendance 일괄 정리.
  // USER list 직접 쿼리 불필요 → schedule_change_requests·idCardAccessRequests USER list 규칙 차단 가능.
  Future<void> _cleanupApplicationRelatedData({
    required String applicationId,
    required String uid,   // CF 내부에서 application.uid로 서버 검증 — 이 값은 미사용
    String? businessId,    // CF 내부에서 callerUid 권한 검증 — 이 값은 미사용
    WriteBatch? batch,     // CF는 자체 배치 사용 — 이 값은 미사용
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCleanupApplicationData',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
      await callable.call({'applicationId': applicationId});
    } catch (e) {
      debugPrint('❌ 연관 데이터 정리 실패: $e');
      if (batch != null) rethrow;
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
    required String workDetailId,
  }) async {
    try {
      final businessDoc =
          await _firestore.collection('businesses').doc(businessId).get();
      if (!businessDoc.exists) return;
      final adminIds = List<String>.from(businessDoc.data()?['adminIds'] as List? ?? []);
      if (adminIds.isEmpty) {
        final fallback = businessDoc.data()?['ownerId'] as String?;
        if (fallback != null && fallback.isNotEmpty) adminIds.add(fallback);
      }
      if (adminIds.isEmpty) return;
      final userDoc =
          await _firestore.collection('users').doc(applicantUid).get();
      final applicantName = userDoc.data()?['name'] as String? ?? '지원자';
      for (final adminUid in adminIds) {
        await createNotification(NotificationModel.createNewApplication(
          userId: adminUid,
          applicantName: applicantName,
          workType: workType,
          workDate: workDate,
          applicationId: applicationId,
          toId: toId,
          businessId: businessId,
          workDetailId: workDetailId,
        ));
      }
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
    required String workDetailId,
  }) async {
    try {
      final businessDoc =
          await _firestore.collection('businesses').doc(businessId).get();
      if (!businessDoc.exists) return;
      final adminIds = List<String>.from(businessDoc.data()?['adminIds'] as List? ?? []);
      if (adminIds.isEmpty) {
        final fallback = businessDoc.data()?['ownerId'] as String?;
        if (fallback != null && fallback.isNotEmpty) adminIds.add(fallback);
      }
      if (adminIds.isEmpty) return;
      final userDoc =
          await _firestore.collection('users').doc(applicantUid).get();
      final applicantName = userDoc.data()?['name'] as String? ?? '지원자';
      for (final adminUid in adminIds) {
        await createNotification(NotificationModel.createApplicationCanceled(
          userId: adminUid,
          applicantName: applicantName,
          workType: workType,
          workDate: workDate,
          applicationId: applicationId,
          businessId: businessId,
          toId: toId,
          workDetailId: workDetailId,
        ));
      }
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

  /// 특정 필드만 업데이트
  /// [APP-H2] 화이트리스트 필드만 허용 — 임의 필드 덮어쓰기 차단
  static const _updateApplicationAllowedFields = {
    'isStarred',
    'renewalDecision',
    'terminationCompletionNotifiedAt',
  };

  Future<void> updateApplicationFields(
    String applicationId,
    Map<String, dynamic> fields,
  ) async {
    final invalid = fields.keys.where((k) => !_updateApplicationAllowedFields.contains(k)).toList();
    if (invalid.isNotEmpty) {
      throw Exception('[updateApplicationFields] 허용되지 않은 필드: $invalid');
    }
    await _firestore.collection('applications').doc(applicationId).update(fields);
  }

  /// 계약 연장: 기존 Application 기반으로 새 Application 생성
  ///
  /// [M7-FIX] callableCreateContractRenewal CF 이전
  /// - confirmedAt/appliedAt/contractVoidedAt: serverTimestamp() 강제
  /// - TOCTOU 방지: 트랜잭션 내 원본 상태 재확인 (이중 연장 차단)
  /// - 알림은 각 호출부(_executeExtend, _processRenewal)에서 발송
  Future<ApplicationModel> createRenewedApplication({
    required ApplicationModel original,
    required DateTime newStartDate,
    required DateTime newEndDate,
  }) async {
    NetworkChecker.instance.assertOnline('계약 연장 중 네트워크 연결이 필요합니다.');
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCreateContractRenewal',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call({
        'originalApplicationId': original.id,
        'newStartDateMs': newStartDate.millisecondsSinceEpoch,
        'newEndDateMs': newEndDate.millisecondsSinceEpoch,
      });
      final data = result.data as Map<dynamic, dynamic>;
      final newApplicationId = data['newApplicationId'] as String;
      // CF 완료 후 신규 application 문서 fetch
      final newDoc = await _firestore
          .collection('applications')
          .doc(newApplicationId)
          .get();
      if (!newDoc.exists) throw Exception('계약 연장 후 지원서를 찾을 수 없습니다.');
      if (original.toId != null) clearCache(toId: original.toId!);
      // [BUG-H1 수정 2026-07-14] fromMap → tryFromFirestore (CLAUDE.md tryFromFirestore 패턴 적용)
      // 기존: fromMap 직접 호출 → 필드 누락/타입 불일치 시 Exception → 계약 연장 기능 중단
      final parsed = ApplicationModel.tryFromFirestore(newDoc);
      if (parsed == null) throw Exception('계약 연장 후 지원서 파싱에 실패했습니다.');
      return parsed;
    } on FirebaseFunctionsException catch (e) {
      throw Exception(e.message ?? '계약 연장 중 오류가 발생했습니다.');
    }
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
