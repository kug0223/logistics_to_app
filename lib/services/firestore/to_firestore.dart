part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 공고(TO) 서비스 — slots 구조 기반
// ═══════════════════════════════════════════════════════════

extension TOFirestore on FirestoreService {

  // ───────────────────────────────────────────────────────
  // 사업장 공고 등록 개수 제한 (슈퍼관리자 설정)
  // ───────────────────────────────────────────────────────

  /// 관리자 uid 기준 전체 사업장의 active TO 합산 개수 반환.
  /// [H-9] Firestore 오류 시 999 반환(fail-closed) — 조회 실패 시 한도 초과 상태로 처리
  /// CF callableGetTOsByBiz 경유 (Admin SDK로 보안 규칙 우회)
  Future<int> countAllActiveTO(String uid) async {
    if (uid.isEmpty) return 0;
    try {
      final myBusinesses = await getMyBusiness(uid);
      if (myBusinesses.isEmpty) return 0;
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetTOsByBiz');
      // Future.wait의 클로저에서 total += 직접 수정하면 race condition 발생 — fold로 안전하게 합산
      final counts = await Future.wait<int>(myBusinesses.map((biz) async {
        final result = await callable.call({
          'businessId': biz.id,
          'statuses': [TOStatus.active, TOStatus.full, TOStatus.scheduled, TOStatus.closed],
          'limit': 1000,
        });
        final tos = result.data['tos'] as List? ?? [];
        return tos.length;
      }));
      return counts.fold<int>(0, (acc, c) => acc + c);
    } catch (e) {
      // [H-9] fail-closed: 조회 실패 시 한도 초과 상태로 처리해 TO 생성 차단
      debugPrint('⚠️ [TOFirestore] active TO 개수 조회 실패, fail-closed: $e');
      return 999;
    }
  }

  /// settings/app_config.maxActiveTOPerBusiness 읽기, 미설정 시 기본값 4
  /// adminUID가 있으면 users/{adminUID}.maxActiveTOs 개별 설정을 우선 사용
  /// 개별 설정 없으면 전역값 폴백. 1시간 인메모리 캐시 적용
  static int? _cachedMaxActiveTO;
  static DateTime? _cachedMaxActiveTOAt;
  static final Map<String, int> _cachedPerAdmin = {};
  static final Map<String, DateTime> _cachedPerAdminAt = {};

  Future<int> getMaxActiveTOLimit({String? adminUID}) async {
    final now = DateTime.now();

    // 관리자별 개별 한도 우선 조회
    if (adminUID != null && adminUID.isNotEmpty) {
      final cached = _cachedPerAdmin[adminUID];
      final cachedAt = _cachedPerAdminAt[adminUID];
      if (cached != null && cachedAt != null &&
          now.difference(cachedAt).inHours < 1) {
        return cached;
      }
      try {
        final doc = await _firestore.collection('users').doc(adminUID).get();
        final v = (doc.data()?['maxActiveTOs'] as num?)?.toInt();
        if (v != null && v > 0) {
          _cachedPerAdmin[adminUID] = v;
          _cachedPerAdminAt[adminUID] = now;
          return v;
        }
      } catch (_) {}
    }

    // 전역값 폴백
    if (_cachedMaxActiveTO != null &&
        _cachedMaxActiveTOAt != null &&
        now.difference(_cachedMaxActiveTOAt!).inHours < 1) {
      return _cachedMaxActiveTO!;
    }
    try {
      final doc = await _firestore.collection('settings').doc('app_config').get();
      if (doc.exists) {
        final v = (doc.data()?['maxActiveTOPerBusiness'] as num?)?.toInt();
        if (v != null && v > 0) {
          _cachedMaxActiveTO = v;
          _cachedMaxActiveTOAt = now;
          return v;
        }
      }
    } catch (_) {}
    return 4;
  }

  /// 관리자별 개별 한도 캐시 무효화 (TOLimitSettingsScreen에서 저장 후 호출)
  void invalidateAdminTOLimitCache(String adminUID) {
    _cachedPerAdmin.remove(adminUID);
    _cachedPerAdminAt.remove(adminUID);
  }

  /// 전역 기본값 캐시 무효화
  void invalidateGlobalTOLimitCache() {
    _cachedMaxActiveTO = null;
    _cachedMaxActiveTOAt = null;
  }

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

  /// 사업장 공고 목록 (관리자용) — [CF 이전 2026-07-13] callableGetTOsByBiz
  Future<List<TOModel>> getTOsByBusiness(
    String businessId, {
    bool activeOnly = false,
    bool closedOnly = false,
    int? limit,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetTOsByBiz',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': businessId,
        if (limit != null) 'limit': limit,
      });
      var models = (result.data['tos'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return TOModel.tryFromMap(raw, id);
          })
          .whereType<TOModel>()
          .toList();
      if (activeOnly) {
        models = models.where((t) => TOStatus.openStates.contains(t.status)).toList();
      } else if (closedOnly) {
        models = models.where((t) => TOStatus.closedStates.contains(t.status)).toList();
      }
      return models;
    } catch (e) {
      debugPrint('❌ [TO] 사업장 공고 목록 조회 실패: $e');
      return [];
    }
  }

  /// 공개 공고 목록 (지원자용 — isPublished: true 만)
  Future<List<TOModel>> getPublishedTOs() async {
    try {
      // [BUGFIX-WHEREIN] isPublished isEqualTo + status whereIn → PERMISSION_DENIED
      // status 서버 필터 제거, 클라이언트에서 active/full 필터링
      // [SEC] tos list 규칙: USER에게 limit <= 50 강제 — limit(100)이면 PERMISSION_DENIED
      final snap = await _firestore
          .collection('tos')
          .where('isPublished', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get(const GetOptions(source: Source.server));

      return snap.docs
          .map((d) => TOModel.tryFromMap(d.data(), d.id))
          .whereType<TOModel>()
          .where((t) => t.status == TOStatus.active || t.status == TOStatus.full)
          .take(50)
          .toList();
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
    // [BUGFIX-WHEREIN] isPublished isEqualTo + status whereIn → PERMISSION_DENIED
    // status 서버 필터 제거, 페이지 수신 후 클라이언트에서 active/full 필터링
    Query query = _firestore
        .collection('tos')
        .where('isPublished', isEqualTo: true);

    if (filter?.type != null) {
      query = query.where('type', isEqualTo: filter!.type);
    }
    if (filter?.city != null) {
      query = query.where('businessCity', isEqualTo: filter!.city);
      if (filter.district != null) {
        query = query.where('businessDistrict', isEqualTo: filter.district);
      }
    }

    // sortBy='date'(마감임박순)는 서버 정렬 미지원 — 클라이언트 후처리로만 동작
    // Firestore는 복합 정렬(isPublished+closingAt)을 위한 복합 인덱스가 필요하나 미구성.
    // 현재: createdAt desc 서버 정렬 후 1페이지 내에서만 마감임박순 재정렬.
    // 2페이지 이후 마감임박 공고는 createdAt 기준 뒤에 밀려 노출 안 될 수 있음.
    // 해결 시: Firestore에 (isPublished ASC, closingAt ASC) 복합 인덱스 추가 + 쿼리 변경 필요.
    query = query.orderBy('createdAt', descending: true).limit(pageSize);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get(const GetOptions(source: Source.server));
    final items = snap.docs
        .map((d) => TOModel.tryFromMap(d.data() as Map<String, dynamic>, d.id))
        .whereType<TOModel>()
        // [BUGFIX-WHEREIN] status whereIn 제거로 클라이언트에서 active/full 필터링
        .where((t) => t.status == TOStatus.active || t.status == TOStatus.full)
        .toList();
    return {
      'items': items,
      'lastDoc': snap.docs.isNotEmpty ? snap.docs.last : null,
      'hasMore': snap.docs.length >= pageSize,
    };
  }

  /// ID 목록으로 공고 배치 조회 (Algolia 검색 결과 fetch용)
  /// 마감/비공개 TO는 클라이언트에서 필터링 (Algolia 인덱스와 Firestore 상태 불일치 방어)
  ///
  /// [TO-PERM-FIX] documentId whereIn LIST 쿼리 → 개별 doc GET 병렬 호출로 전환
  /// LIST 규칙: isUser() && request.query.filters.isPublished==true 강제
  /// → documentId whereIn 쿼리에 isPublished 서버 필터 없음 → PERMISSION_DENIED
  /// GET 규칙: isLoggedIn() && isPublished==true (resource.data 기반) → 개별 GET으로 해결
  /// 비공개 TO는 GET 규칙에서 자동 거부 → null로 처리하여 결과에서 제외
  Future<List<TOModel>> getTOsByIds(List<String> ids) async {
    if (ids.isEmpty) return [];
    final snaps = await Future.wait(
      ids.map((id) => _firestore
          .collection('tos')
          .doc(id)
          .get(const GetOptions(source: Source.server))
          .then<DocumentSnapshot<Map<String, dynamic>>?>(
              (snap) => snap,
              onError: (_) => null,
          )),
    );
    return snaps
        .whereType<DocumentSnapshot<Map<String, dynamic>>>()
        .where((snap) => snap.exists)
        .map((snap) => TOModel.tryFromMap(snap.data()!, snap.id))
        .whereType<TOModel>()
        .where((to) => to.isPublished && !to.isClosed)
        .toList();
  }

  /// 최근 등록 공고 (기존 공고 연결용) — [CF 이전 2026-07-13] callableGetTOsByBiz
  Future<List<TOModel>> getRecentTOsByBusiness(
    String businessId, {
    int days = 60,
  }) async {
    try {
      final cutoff = DateTime.now().subtract(Duration(days: days));
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetTOsByBiz',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': businessId,
        'createdAtGteMs': cutoff.millisecondsSinceEpoch,
        'orderByCreatedAtDesc': true,
        'limit': 20,
      });
      return (result.data['tos'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return TOModel.tryFromMap(raw, id);
          })
          .whereType<TOModel>()
          .toList();
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

    // [HIGH-02] 개수 제한은 callableCreateTO CF에서 서버 측 강제 — 클라이언트 체크 제거

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
        if (parts.length < 2) {
          isPublished = true; // 형식 오류 시 즉시 공개 폴백
          debugPrint('⚠️ [TO] publishTime 형식 오류: $publishTime');
        } else {
          // int.parse 대신 tryParse — 잘못된 시간값(예: "25:00", "AB:CD")으로 인한 크래시 방지
          final hour = int.tryParse(parts[0]);
          final minute = int.tryParse(parts[1]);
          if (hour == null || minute == null || hour > 23 || minute > 59) {
            isPublished = true;
            debugPrint('⚠️ [TO] publishTime 파싱 실패 (즉시 공개 폴백): $publishTime');
          } else {
            final candidate = DateTime(
              baseDate.year, baseDate.month, baseDate.day,
              hour, minute,
            ).subtract(Duration(days: publishDaysBefore));

            if (candidate.isBefore(DateTime.now())) {
              isPublished = true; // 과거 시간이면 즉시 공개
            } else {
              publishAt = candidate;
            }
          }
        }
      }

      // 미공개(draft) 처리
      final isDraft = publishMode == 'draft';
      final String toStatus = isDraft
          ? TOStatus.draft
          : isPublished
              ? TOStatus.active
              : TOStatus.scheduled;

      // TO 문서 데이터 — createdAt/statusUpdatedAt은 CF에서 serverTimestamp 강제
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
        createdAt: DateTime.now(), // CF에서 serverTimestamp로 덮어씀
        status: toStatus,
      ).toMap()
        ..remove('createdAt')       // CF에서 serverTimestamp 강제
        ..remove('statusUpdatedAt'); // CF에서 serverTimestamp 강제

      // flex + 즉시공개: 슬롯 생성 완료 전까지 비공개로 생성 → 슬롯 없는 TO 노출 방지
      final deferPublish = type == TOType.flex &&
          isPublished &&
          !isDraft &&
          dates != null &&
          dates.isNotEmpty;
      final initialData = deferPublish
          ? {...toData, 'isPublished': false, 'status': TOStatus.scheduled}
          : toData;

      // [HIGH-02] CF callableCreateTO — 개수 제한 서버 강제 + serverTimestamp 설정
      final cfResult = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCreateTO')
          .call({'toData': initialData});
      final toId = cfResult.data['toId'] as String;
      final toRef = _firestore.collection('tos').doc(toId);
      debugPrint('✅ [TO] 공고 생성: $toId');

      // flex: slots 생성 — 실패 시 부분 생성된 슬롯 + TO 문서 모두 롤백 삭제
      if (type == TOType.flex && dates != null && dates.isNotEmpty) {
        try {
          await _createSlots(
            toId: toId,
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
          debugPrint('⚠️ [TO] 슬롯 생성 실패 — 부분 슬롯 및 TO 롤백: $toId');
          // 부분 커밋된 슬롯 정리 (배치 분할 커밋 중 실패 시 고아 슬롯 방지)
          try {
            final partialSlots = await toRef.collection('slots').get();
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
          await toRef.delete();
          rethrow;
        }

        // 슬롯 생성 완료 후 즉시공개 상태로 전환 (노출 창 최소화)
        if (deferPublish) {
          await toRef.update({
            'isPublished': true,
            'status': toStatus,
            'statusUpdatedAt': FieldValue.serverTimestamp(),
          });
        }
      }

      return toId;
    } catch (e) {
      debugPrint('❌ [TO] 공고 생성 실패: $e');
      return null;
    }
  }

  /// 관리자의 전체 사업장 합산 active TO 수가 제한 이상이면 예외를 던진다.
  /// draft TO를 즉시공개로 전환하기 직전에 호출한다.
  Future<void> assertActiveTOLimit(String uid) async {
    final limit = await getMaxActiveTOLimit(adminUID: uid);
    final totalActive = await countAllActiveTO(uid);
    if (totalActive >= limit) {
      throw Exception('MAX_ACTIVE_TO_LIMIT:$limit');
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
      // [BUGFIX] statuses whereIn 제거 → 전체 조회 후 클라이언트 필터링
      final allApps = await getApplicationsByTOId(toId, businessId: businessId);
      final apps = allApps.where((a) => AppStatus.activeStates.contains(a.status)).toList();
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

  /// 공고 삭제 — CF callableDeleteTO 위임 (Admin SDK로 보안 규칙 우회)
  /// 슬롯·지원서·고아 데이터 정리 및 알림 발송은 CF에서 처리
  Future<bool> deleteTO(String toId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableDeleteTO');
      await callable.call({'toId': toId});
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

  /// 특정 슬롯의 총 필요 인원 (workDetails.requiredCount 합계, 지원명단 정원 표시용)
  Future<int> getSlotTotalRequired(String toId, String slotId) async {
    try {
      final doc = await _firestore
          .collection('tos').doc(toId)
          .collection('slots').doc(slotId)
          .get(const GetOptions(source: Source.server));
      if (!doc.exists) return 0;
      final workDetails = doc.data()?['workDetails'] as List? ?? [];
      return workDetails.fold<int>(
        0,
        (acc, wd) => acc + (((wd as Map<String, dynamic>)['requiredCount'] as num?)?.toInt() ?? 0),
      );
    } catch (_) {
      return 0;
    }
  }

  /// 슬롯 문서의 workDetails별 requiredCount 맵 반환
  /// key: workDetail.id (없으면 '${workType}_${startTime}_${endTime}')
  Future<Map<String, int>> getSlotWorkDetailCapacities(String toId, String slotId) async {
    try {
      final doc = await _firestore
          .collection('tos').doc(toId)
          .collection('slots').doc(slotId)
          .get(const GetOptions(source: Source.server));
      if (!doc.exists) return {};
      final workDetails = doc.data()?['workDetails'] as List? ?? [];
      final result = <String, int>{};
      for (final wd in workDetails) {
        final map = wd as Map<String, dynamic>;
        final id = (map['id'] as String?)?.isNotEmpty == true
            ? map['id'] as String
            : '${map['workType']}_${map['startTime']}_${map['endTime']}';
        result[id] = (map['requiredCount'] as num?)?.toInt() ?? 0;
      }
      return result;
    } catch (_) {
      return {};
    }
  }

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
          .map((d) => SlotModel.tryFromMap(d.data(), d.id, toId))
          .whereType<SlotModel>()
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
            if (parts.length >= 2) {
              deadline = DateTime(
                slot.date.year, slot.date.month, slot.date.day,
                int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0,
              ).subtract(Duration(hours: hoursBeforeStart)).toUtc();
            }
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

  /// 선택한 슬롯들 일괄 마감 — CF callableCloseSlots 위임 (Admin SDK로 보안 규칙 우회)
  /// PENDING 취소·카운터 감소·알림 발송은 CF에서 처리.
  /// [closedBy] 파라미터는 CF에서 callerUid로 대체되므로 무시됨 (하위 호환 유지)
  Future<void> batchCloseSlots({
    required String toId,
    required String businessId,
    required List<String> slotIds,
    required String closedBy,
  }) async {
    if (slotIds.isEmpty) return;
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableCloseSlots');
    await callable.call({
      'toId': toId,
      'slotIds': slotIds,
      'businessId': businessId,
    });
    debugPrint('✅ [Slot] ${slotIds.length}개 슬롯 일괄 마감 완료 (CF)');
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

  /// 선택한 슬롯들 일괄 삭제 — CF callableDeleteSlots 위임 (Admin SDK로 보안 규칙 우회)
  /// 활성 지원서 REJECTED·카운터 감소·알림 발송·TO 자동 CLOSED 처리는 CF에서 수행.
  Future<void> batchDeleteSlots({
    required String toId,
    required String businessId,
    required List<String> slotIds,
  }) async {
    if (slotIds.isEmpty) return;
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableDeleteSlots');
    await callable.call({
      'toId': toId,
      'slotIds': slotIds,
      'businessId': businessId,
    });
    clearCache(toId: toId);
    debugPrint('✅ [Slot] ${slotIds.length}개 슬롯 일괄 삭제 완료 (CF)');
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
    final slotRequired = workDetails.fold<int>(0, (s, d) => s + d.requiredCount);
    final dateOnly = DateTime(date.year, date.month, date.day);

    // [BUG-수정] T-M-1: toUpdates를 미리 계산해 _createSlots의 마지막 배치에 함께 커밋
    // — 슬롯 생성 후 별도 update() 호출 시 카운터 업데이트 실패로 totalSlots/totalRequired
    //   불일치하는 비원자성 문제를 제거한다.
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
      toRefForCounter: _firestore.collection('tos').doc(to.id),
      toCounterUpdates: toUpdates,
    );

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
          if (parts.length >= 2) {
            // [NEW-03 수정] int.parse → int.tryParse: 잘못된 publishTime 입력 시 FormatException 크래시 방지
            // createTO·_createSlots는 이미 tryParse 사용 중 — 여기서도 통일
            final hour = int.tryParse(parts[0]);
            final minute = int.tryParse(parts[1]);
            if (hour == null || minute == null || hour > 23 || minute > 59) continue;
            final visibleFrom = DateTime(
              slot.date.year, slot.date.month, slot.date.day,
              hour, minute,
            ).subtract(Duration(days: publishDaysBefore));
            batch.update(slotRef, {
              'visibleFrom': Timestamp.fromDate(visibleFrom.toUtc()),
            });
          }
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
    // [BUG-수정] T-M-1: 마지막 배치에 함께 커밋할 TO 카운터 업데이트를 받아
    // 슬롯 생성과 TO 카운터 변경을 원자적으로 처리한다.
    DocumentReference? toRefForCounter,
    Map<String, dynamic>? toCounterUpdates,
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
          if (parts.length >= 2) {
            deadline = DateTime(
              date.year, date.month, date.day,
              int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0,
            ).subtract(Duration(hours: hoursBeforeStart)).toUtc();
          }
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
        if (parts.length >= 2) {
          visibleFrom = DateTime(
            date.year, date.month, date.day,
            int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0,
          ).subtract(Duration(days: publishDaysBefore)).toUtc();
        }
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

    // [BUG-수정] T-M-1: TO 카운터 업데이트를 마지막 배치에 포함해 원자적으로 커밋
    // — 슬롯 생성 성공 후 TO 업데이트 실패로 totalSlots/totalRequired 불일치하는 문제 방지
    if (toRefForCounter != null && toCounterUpdates != null) {
      batch.update(toRefForCounter, toCounterUpdates);
    }
    if (count > 0 || (toRefForCounter != null && toCounterUpdates != null)) {
      await batch.commit();
    }
    debugPrint('✅ [TO] 슬롯 ${dates.length}개 생성 완료');
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
        // isManualClosed도 함께 초기화 — TOModel.effectiveStatus 게터가
        // isManualClosed=true이면 status 값과 무관하게 CLOSED를 반환하므로,
        // cascade 재오픈 시 남겨두면 TO가 ACTIVE로 세팅됐어도 사용자에게 여전히 CLOSED로 보임.
        await _firestore.collection('tos').doc(toId).update({
          'status': TOStatus.active,
          'closedAt': FieldValue.delete(),
          'isManualClosed': false,
        });
        debugPrint('✅ [TO] 슬롯 재오픈 → ACTIVE 복구 ($toId)');
      }
    } catch (e) {
      debugPrint('⚠️ TO 상태 동기화 실패: $e');
    }
  }
}
