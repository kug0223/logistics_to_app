part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 출근/스케줄/퇴사 관리 (Attendance & Schedule Management)
// ═══════════════════════════════════════════════════════════

extension AttendanceFirestore on FirestoreService {
  // ═══════════════════════════════════════════════════════════
  // 🕐 출근 관리 (Attendance Management)
  // ═══════════════════════════════════════════════════════════

  /// 출근 체크
  /// [B1-FIX] callableCheckIn CF로 이전 — 반올림·소유권·서버 시각 강제.
  /// 이전 이유: 클라이언트 DateTime.now() 조작으로 출근 시각·반올림 위조 가능.
  /// CF에서 소유권, 사업장, 휴무일, 퇴직 여부, 반올림을 모두 서버 측 재검증.
  Future<String?> checkIn({
    required String applicationId,
    required String userId,
    required String businessId,
    required String businessName,
    required DateTime workDate,
    required String workType,
    double? latitude,
    double? longitude,
    String method = 'gps',
    String? scheduledStartTime,
    String? scheduledEndTime,
    AttendanceRules? attendanceRules,
  }) async {
    NetworkChecker.instance.assertOnline('출근 체크를 하려면 인터넷 연결이 필요합니다.');
    GlobalLoadingController.show('출근 처리 중...');
    try {
      debugPrint('🕐 [checkIn] CF 호출...');
      debugPrint('   applicationId: $applicationId, workDate: $workDate');

      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCheckIn',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));

      // AttendanceRules.toMap()에 rulesUpdatedAt(Timestamp)이 포함되어 있어 직렬화 오류 발생.
      // CF에 필요한 int 필드만 선택적으로 전달.
      Map<String, int>? rulesMap;
      if (attendanceRules != null) {
        rulesMap = {
          'earlyWindow': attendanceRules.earlyWindow,
          'earlyArrivalUnit': attendanceRules.earlyArrivalUnit,
          'lateGrace': attendanceRules.lateGrace,
          'lateUnit': attendanceRules.lateUnit,
          'lateWindow': attendanceRules.lateWindow,
          'overtimeUnit': attendanceRules.overtimeUnit,
          'earlyLeaveUnit': attendanceRules.earlyLeaveUnit,
        };
      }

      final result = await callable.call({
        'applicationId': applicationId,
        'businessId': businessId,
        'businessName': businessName,
        'workDateMs': workDate.millisecondsSinceEpoch,
        'workType': workType,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'method': method,
        if (scheduledStartTime != null) 'scheduledStartTime': scheduledStartTime,
        if (scheduledEndTime != null) 'scheduledEndTime': scheduledEndTime,
        if (rulesMap != null) 'attendanceRules': rulesMap,
      });

      final data = result.data as Map<dynamic, dynamic>?;
      final attendanceId = data?['attendanceId'] as String?;
      debugPrint('✅ 출근 체크 완료 (CF): $attendanceId');
      invalidateMyAttendanceCache(userId);
      return attendanceId;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ 출근 체크 실패 (CF): ${e.code} ${e.message}');
      throw Exception(e.message ?? '출근 처리 중 오류가 발생했습니다.');
    } catch (e) {
      debugPrint('❌ 출근 체크 실패: $e');
      rethrow;
    } finally {
      GlobalLoadingController.hide();
    }
  }

  /// 퇴근 체크
  /// [B1-FIX] callableCheckOut CF로 이전 — 반올림·근무시간 계산·서버 시각 강제.
  /// 이전 이유: 클라이언트 DateTime.now() 및 workHours 계산 조작 가능 → 서버 강제.
  Future<bool> checkOut({
    required String attendanceId,
    required DateTime workDate,
    double? latitude,
    double? longitude,
    String method = 'gps',
    String? scheduledEndTime,
    String? scheduledStartTime,
    AttendanceRules? attendanceRules,
  }) async {
    NetworkChecker.instance.assertOnline('퇴근 체크를 하려면 인터넷 연결이 필요합니다.');
    GlobalLoadingController.show('퇴근 처리 중...');
    try {
      debugPrint('🕐 [checkOut] CF 호출...');
      debugPrint('   attendanceId: $attendanceId');

      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCheckOut',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));

      // rulesUpdatedAt(Timestamp) 제외하고 int 필드만 전달
      Map<String, int>? rulesMap;
      if (attendanceRules != null) {
        rulesMap = {
          'earlyWindow': attendanceRules.earlyWindow,
          'earlyArrivalUnit': attendanceRules.earlyArrivalUnit,
          'lateGrace': attendanceRules.lateGrace,
          'lateUnit': attendanceRules.lateUnit,
          'lateWindow': attendanceRules.lateWindow,
          'overtimeUnit': attendanceRules.overtimeUnit,
          'earlyLeaveUnit': attendanceRules.earlyLeaveUnit,
        };
      }

      await callable.call({
        'attendanceId': attendanceId,
        'workDateMs': workDate.millisecondsSinceEpoch,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        'method': method,
        if (scheduledStartTime != null) 'scheduledStartTime': scheduledStartTime,
        if (scheduledEndTime != null) 'scheduledEndTime': scheduledEndTime,
        if (rulesMap != null) 'attendanceRules': rulesMap,
      });

      debugPrint('✅ 퇴근 체크 완료 (CF)');
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ 퇴근 체크 실패 (CF): ${e.code} ${e.message}');
      throw Exception(e.message ?? '퇴근 처리 중 오류가 발생했습니다.');
    } catch (e) {
      debugPrint('❌ 퇴근 체크 실패: $e');
      rethrow;
    } finally {
      GlobalLoadingController.hide();
    }
  }


  /// 오늘 내 출근 기록 조회
  ///
  /// docId는 `${applicationId}_yyyyMMdd`로 결정적이므로 오늘·어제 순으로 직접 조회.
  /// workDate 범위 쿼리 대신 docId 직접 조회를 사용해야 하는 이유:
  ///   - 단기 야간 근무: workDate = 어제(근무 시작일) → 어제 docId로 퇴근 전까지 유지
  ///   - 장기 근무: checkIn 시 workDate = 오늘 날짜 (시작일 아님) → 오늘 docId
  ///   - 범위 쿼리는 workDate 값에 의존하므로 두 케이스를 limit(1)로 함께 처리할 때 비결정적
  Future<AttendanceModel?> getTodayAttendance({
    required String userId,
    required String applicationId,
  }) async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);

      String dateStr(DateTime d) =>
          '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';

      for (final date in [todayStart, todayStart.subtract(const Duration(days: 1))]) {
        final docId = '${applicationId}_${dateStr(date)}';
        final doc = await _firestore.collection('attendance').doc(docId).get();
        if (!doc.exists) continue;
        final att = AttendanceModel.tryFromFirestore(doc);
        if (att == null) continue;
        // 소유자 검증 (타인 applicationId 조회 방지)
        if (att.userId != userId) continue;
        return att;
      }
      return null;
    } catch (e) {
      debugPrint('❌ 오늘 출근 기록 조회 실패: $e');
      return null;
    }
  }

  /// 사업장별 오늘 출근 현황 조회 (관리자용 — CF 프록시)
  Future<List<AttendanceModel>> getTodayAttendanceByBusiness({
    required String businessId,
  }) async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      debugPrint('🔍 [getTodayAttendanceByBusiness] CF 조회 시작... businessId=$businessId');
      final attendances = await _callableGetAdminAttendances(
        businessId: businessId,
        startDate: todayStart,
        endDate: todayEnd,
      );
      debugPrint('✅ 오늘 출근 현황: ${attendances.length}명');
      return attendances;
    } catch (e) {
      debugPrint('❌ 출근 현황 조회 실패: $e');
      return [];
    }
  }

  /// 오늘 확정된 근무자 목록 조회 (출근 대상자)
  /// [CF 이전 2026-07-13] callableGetApplicationsByBiz (workDateEqMs + longTerm 병렬)
  Future<List<ApplicationModel>> getTodayConfirmedWorkers({
    required String businessId,
  }) async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      debugPrint('🔍 [getTodayConfirmedWorkers] 조회 시작...');

      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetApplicationsByBiz',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));

      final results = await Future.wait([
        // 1. 오늘 단기 근무 (workDate == today)
        callable.call<Map<String, dynamic>>({
          'businessId': businessId,
          'workDateGteMs': todayStart.millisecondsSinceEpoch,
          'workDateLtMs': todayEnd.millisecondsSinceEpoch,
          'limit': 2000,
        }),
        // 2. 장기 근무자 (workEndDate >= todayStart, 클라이언트에서 isWorkingOnDate 필터)
        callable.call<Map<String, dynamic>>({
          'businessId': businessId,
          'workEndDateGteMs': todayStart.millisecondsSinceEpoch,
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

      final confirmedSet = Set<String>.from(AppStatus.confirmedStatuses);

      final shortTerm = parseApps(results[0])
          .where((app) => confirmedSet.contains(app.status) && !app.isLongTermApplication)
          .toList();
      debugPrint('   단기 근무자: ${shortTerm.length}명');

      final longTerm = parseApps(results[1])
          .where((app) => confirmedSet.contains(app.status) && app.isLongTermApplication)
          // isWorkingOnDate: actualResignDate·leaveDates·extraWorkDates·workDays 모두 반영
          .where((app) => app.isWorkingOnDate(todayStart))
          .toList();
      debugPrint('   장기 근무자: ${longTerm.length}명');

      final allWorkers = [...shortTerm, ...longTerm];
      debugPrint('✅ 총 출근 대상: ${allWorkers.length}명');
      return allWorkers;
    } catch (e) {
      debugPrint('❌ 출근 대상자 조회 실패: $e');
      return [];
    }
  }

  /// 특정 날짜에 실제로 근무한 근로자 맵 반환 (확정취소 버튼 가드 공통 로직)
  ///
  /// key = userId, value = true
  /// 조건: checkIn이 있고 결근·노쇼가 아닌 경우 OR wageStatus가 confirmed/transferred
  /// [BUG-CANCEL-01] day_applicants_dialog · work_applicants_dialog 공통 사용
  Future<Map<String, bool>> loadHasWorkedMap({
    required String businessId,
    required DateTime date,
  }) async {
    try {
      final atts = await getAttendanceByDate(businessId: businessId, date: date);
      return {
        for (final att in atts)
          if ((att.checkIn != null &&
                  att.status != AttendanceModel.statusAbsent &&
                  att.status != AttendanceModel.statusNoShow) ||
              att.isWageConfirmed ||
              att.isWageTransferred)
            att.userId: true
      };
    } catch (e) {
      debugPrint('⚠️ loadHasWorkedMap 실패 ($date): $e');
      rethrow; // 빈 맵 반환 시 "근무자 없음"으로 오인 → 확정취소 가드 오동작
    }
  }

  /// 특정 날짜 출근 기록 조회 (관리자용 — CF 프록시)
  Future<List<AttendanceModel>> getAttendanceByDate({
    required String businessId,
    required DateTime date,
  }) async {
    // try-catch 제거 — 호출자(loadHasWorkedMap)가 rethrow를 담당
    // return [] 시 "근무자 없음"으로 오인되어 확정취소 가드가 오동작할 수 있음
    final dateStart = DateTime(date.year, date.month, date.day);
    final dateEnd = dateStart.add(const Duration(days: 1));
    return _callableGetAdminAttendances(
      businessId: businessId,
      startDate: dateStart,
      endDate: dateEnd,
    );
  }
  /// 사용자별 월별 출근 기록 조회 (CF 프록시, 2분 TTL 캐시)
  /// attendance list 규칙에서 isUser() 제거 → CF로 auth.uid 기반 서버 검증
  Future<List<AttendanceModel>> getMyMonthlyAttendances({
    required String userId,
    required int year,
    required int month,
  }) async {
    final cacheKey = '${userId}_${year}_$month';
    final cached = _myAttendanceCache[cacheKey];
    final ts = _myAttendanceCacheTimestamps[cacheKey];
    if (cached != null && ts != null &&
        DateTime.now().difference(ts) < FirestoreService._myAttendanceCacheTTL) {
      return cached;
    }
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('getMyMonthlyAttendances',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      final result = await callable.call({'year': year, 'month': month});
      final items = (result.data['items'] as List<dynamic>? ?? []);
      final list = items
          .whereType<Map>()
          .map((e) {
            final m = Map<String, dynamic>.from(e);
            final id = m.remove('id') as String? ?? '';
            return AttendanceModel.tryFromMap(m, id);
          })
          .whereType<AttendanceModel>()
          .toList();
      _myAttendanceCache[cacheKey] = list;
      _myAttendanceCacheTimestamps[cacheKey] = DateTime.now();
      return list;
    } catch (e) {
      debugPrint('❌ 월별 출근 기록 조회 실패: $e');
      return cached ?? [];
    }
  }
  /// 관리자용 출근 기록 목록 조회 (CF 프록시)
  /// attendance allow list: if false 이후 이 CF 사용 — 서버사이드 권한 검증
  Future<List<AttendanceModel>> _callableGetAdminAttendances({
    required String businessId,
    required DateTime startDate,
    required DateTime endDate,
    String? userId,
  }) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableGetAdminAttendances',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
    final params = <String, dynamic>{
      'businessId': businessId,
      'startMs': startDate.millisecondsSinceEpoch,
      'endMs': endDate.millisecondsSinceEpoch,
    };
    if (userId != null) params['userId'] = userId;
    final result = await callable.call<Map<String, dynamic>>(params);
    final items = (result.data['items'] as List<dynamic>? ?? []);
    final limitReached = result.data['limitReached'] as bool? ?? false;
    if (limitReached) {
      debugPrint('⚠️ callableGetAdminAttendances: limit(10000) 도달 — 데이터 누락 가능 (bizId=$businessId)');
    }
    return items
        .whereType<Map>()
        .map((e) {
          final m = Map<String, dynamic>.from(e);
          final id = m.remove('id') as String? ?? '';
          return AttendanceModel.tryFromMap(m, id);
        })
        .whereType<AttendanceModel>()
        .toList();
  }

  // ═══════════════════════════════════════════════════════════
  // 스케줄 변경 요청 관리 (Schedule Change Request Management)
  // ═══════════════════════════════════════════════════════════

  /// 스케줄 변경 요청 생성
  Future<String?> createScheduleChangeRequest(ScheduleChangeRequestModel request) async {
    // [특이사항] LEAVE 요청 시 해당 날짜에 이미 출근한 경우 차단.
    // 출근 후 LEAVE 승인 시 application.leaveDates에는 날짜가 추가되지만
    // attendance.status는 'present'로 남아 데이터 불일치가 발생한다.
    // → 의도적 검증 예외 — try-catch 밖에서 throw하여 호출부로 전파
    if (request.requestType == RequestType.LEAVE &&
        request.requestedBy == RequesterType.APPLICANT) {
      final t = request.targetDate;
      final dateStr =
          '${t.year}${t.month.toString().padLeft(2, '0')}${t.day.toString().padLeft(2, '0')}';
      final attendanceDoc = await _firestore
          .collection('attendance')
          .doc('${request.applicationId}_$dateStr')
          .get();
      if (attendanceDoc.exists &&
          attendanceDoc.data()?['checkIn'] != null) {
        throw Exception('이미 출근한 날짜는 휴무 요청을 할 수 없습니다.');
      }
    }

    try {
      // [B6-FIX] requestedAt 서버 타임스탬프 오버라이드 — toMap()의 DateTime 값 조작 차단
      final scrMap = request.toMap()..['requestedAt'] = FieldValue.serverTimestamp();
      final docRef = await _firestore.collection('schedule_change_requests').add(scrMap);
      debugPrint('✅ 스케줄 변경 요청 생성 완료: ${docRef.id}');

      // 🔔 알림 생성 (관리자에게) - 지원자가 요청한 경우 (fire-and-forget)
      if (request.requestedBy == RequesterType.APPLICANT) {
        // ignore: unawaited_futures
        _sendScheduleChangeRequestNotification(
          businessId: request.businessId,
          requesterName: request.applicantName,
          requestType: request.requestType.name,
          targetDate: request.targetDate,
          requestId: docRef.id,
          reason: request.reason,
        );
      }

      return docRef.id;
    } catch (e) {
      debugPrint('❌ 스케줄 변경 요청 생성 실패: $e');
      return null;
    }
  }

  /// 사업장의 대기중인 스케줄 변경 요청 조회
  /// [RULE-FIX-CF 2026-07-13] 직접 Firestore → callableGetScheduleChangeRequests CF 이전
  Future<List<ScheduleChangeRequestModel>> getPendingScheduleChangeRequests(String businessId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetScheduleChangeRequests',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': businessId,
        'pendingOnly': true,
      });
      final items = (result.data['items'] as List<dynamic>?) ?? [];
      return items.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        final id = m.remove('id') as String? ?? '';
        return ScheduleChangeRequestModel.tryFromMap(_cfHydrate(m), id);
      }).whereType<ScheduleChangeRequestModel>().toList();
    } catch (e) {
      debugPrint('❌ 대기중인 스케줄 변경 요청 조회 실패: $e');
      rethrow;
    }
  }

  /// 사업장의 모든 스케줄 변경 요청 조회
  /// [RULE-FIX-CF 2026-07-13] 직접 Firestore → callableGetScheduleChangeRequests CF 이전
  Future<List<ScheduleChangeRequestModel>> getAllScheduleChangeRequests(String businessId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetScheduleChangeRequests',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': businessId,
        'pendingOnly': false,
        'limit': 2000,
      });
      final items = (result.data['items'] as List<dynamic>?) ?? [];
      return items.whereType<Map>().map((e) {
        final m = Map<String, dynamic>.from(e);
        final id = m.remove('id') as String? ?? '';
        return ScheduleChangeRequestModel.tryFromMap(_cfHydrate(m), id);
      }).whereType<ScheduleChangeRequestModel>().toList();
    } catch (e) {
      debugPrint('❌ 스케줄 변경 요청 조회 실패: $e');
      rethrow;
    }
  }

  /// 지원자의 스케줄 변경 요청 조회
  // [BUG-수정] 캐시 데이터로 중복 요청 방어 로직이 오동작하지 않도록 항상 서버에서 최신 상태 조회
  // [BUGFIX-COMPOUND] orderBy('requestedAt') 제거 — applicantUid isEqualTo + orderBy requestedAt 복합 인덱스 쿼리에서
  //   request.query.filters.applicantUid가 null을 반환해 PERMISSION_DENIED 유발
  //   orderBy 제거 후 클라이언트 정렬. 보안 규칙: isUser() && filters.applicantUid == auth.uid.
  /// [CF 이전 2026-07-15] callableGetMyScheduleChanges — applicantUid 서버 검증 강제
  Future<List<ScheduleChangeRequestModel>> getMyScheduleChangeRequests(String applicantUid) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetMyScheduleChanges',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({});
      return ((result.data['items'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return ScheduleChangeRequestModel.tryFromMap(raw, id);
          })
          .whereType<ScheduleChangeRequestModel>()
          .toList()
        ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt)));
    } catch (e) {
      debugPrint('❌ 내 스케줄 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 특정 날짜의 대기중인 스케줄 변경 요청 조회 (다중 사업장)
  ///
  /// whereIn은 보안 규칙 request.query.filters.businessId를 채우지 못해
  /// isAdminOf 검증 실패 → PERMISSION_DENIED 발생.
  /// 사업장별 개별 isEqualTo 쿼리로 분리하여 보안 규칙 충족.
  /// [CF 이전 2026-07-13] callableGetScheduleChangeRequestsForDate
  Future<List<ScheduleChangeRequestModel>> getScheduleChangeRequestsForDate({
    required DateTime date,
    required List<String> businessIds,
  }) async {
    if (businessIds.isEmpty) return [];
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetScheduleChangeRequestsForDate',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessIds': businessIds,
        'dateMs': date.millisecondsSinceEpoch,
      });
      return (result.data['items'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final raw = _cfHydrate(Map<String, dynamic>.from(m));
            final id = raw.remove('id') as String? ?? '';
            return ScheduleChangeRequestModel.tryFromMap(raw, id);
          })
          .whereType<ScheduleChangeRequestModel>()
          .toList();
    } catch (e) {
      debugPrint('❌ 날짜별 스케줄 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 스케줄 변경 요청 승인
  ///
  /// 타입별 Application 배열 필드 업데이트 (트랜잭션 내 원자 처리):
  ///   · LEAVE / NO_WORK → leaveDates 추가: isLeaveDateOn=true → 당일 명단·출근 차단
  ///   · EXTRA_WORK      → extraWorkDates 추가: isExtraWorkDateOn=true → 비근무 요일 출근 허용
  ///   · CANCEL_LEAVE    → leaveDates 제거 [B1 수정]: 미제거 시 isLeaveDateOn=true 유지 → 출근 불가 상태 고착
  ///   · CANCEL_EXTRA    → extraWorkDates 제거 [B2 수정]: 미제거 시 isExtraWorkDateOn=true 유지 → 당일 명단 잔류
  ///
  /// ⚠️ CANCEL_LEAVE/CANCEL_EXTRA 분기를 수정할 때 removeWhere 누락 금지.
  ///    누락 시 근무자가 출근 불가 상태에 빠지거나 비근무일에 명단에 표시되는 문제 재발.
  /// 스케줄 변경 요청 승인
  /// [H3-FIX] callableApproveScheduleChangeRequest CF로 이전 — respondedByUid CF 직접 기록 + assertBizAdmin 권한 검증
  /// 이전 이유:
  ///  1. respondedByUid를 클라이언트가 설정 → 다른 관리자 UID 위조 가능 (M5 취약점)
  ///  2. 트랜잭션 내 businessId 권한 검증 없이 rules에만 의존 → CF assertBizAdmin으로 강화
  Future<bool> approveScheduleChangeRequest({
    required String requestId,
  }) async {
    GlobalLoadingController.show('처리 중...');
    try {
      // [BUG-REGION-FIX 2026-07-15] instance(us-central1 기본값) → instanceFor(asia-northeast3)
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableApproveScheduleChangeRequest');
      await callable.call({
        'requestId': requestId,
        'action': 'APPROVED',
      });

      debugPrint('✅ 스케줄 변경 요청 승인 완료 (CF): $requestId');
      // 캐시 무효화: 관리자 기기에는 근무자의 "내 지원 목록" 캐시가 없으므로 no-op
      return true;
    } catch (e) {
      if (e.toString().contains('이미 처리된 요청')) {
        debugPrint('⚠️ 이미 처리된 요청: $requestId');
      } else {
        debugPrint('❌ 스케줄 변경 요청 승인 실패: $e');
      }
      return false;
    } finally {
      GlobalLoadingController.hide();
    }
  }

  /// 스케줄 변경 요청 거절
  /// [H3-FIX] callableApproveScheduleChangeRequest CF로 이전 (action=REJECTED)
  Future<bool> rejectScheduleChangeRequest({
    required String requestId,
    String? rejectReason,
  }) async {
    GlobalLoadingController.show('처리 중...');
    try {
      // [BUG-REGION-FIX 2026-07-15] instance(us-central1 기본값) → instanceFor(asia-northeast3)
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableApproveScheduleChangeRequest');
      await callable.call({
        'requestId': requestId,
        'action': 'REJECTED',
        if (rejectReason != null) 'rejectReason': rejectReason,
      });

      debugPrint('✅ 스케줄 변경 요청 거절 완료 (CF): $requestId');
      return true;
    } catch (e) {
      if (e.toString().contains('이미 처리된 요청')) {
        debugPrint('⚠️ 이미 처리된 요청: $requestId');
      } else {
        debugPrint('❌ 스케줄 변경 요청 거절 실패: $e');
      }
      return false;
    } finally {
      GlobalLoadingController.hide();
    }
  }
  /// 🔔 스케줄 변경 요청 알림 전송 (관리자에게)
  Future<void> _sendScheduleChangeRequestNotification({
    required String businessId,
    required String requesterName,
    required String requestType,
    required DateTime targetDate,
    required String requestId,
    String? reason,
  }) async {
    try {
      // 사업장 관리자 UID 조회
      final businessDoc = await _firestore.collection('businesses').doc(businessId).get(const GetOptions(source: Source.server));
      if (!businessDoc.exists) return;
      
      final adminIds = List<String>.from(businessDoc.data()?['adminIds'] as List? ?? []);
      if (adminIds.isEmpty) {
        final fallback = businessDoc.data()?['ownerId'] as String?;
        if (fallback != null && fallback.isNotEmpty) adminIds.add(fallback);
      }
      if (adminIds.isEmpty) return;

      await Future.wait(adminIds.map((adminUid) => createNotification(
        NotificationModel.createScheduleChangeRequested(
          userId: adminUid,
          requesterName: requesterName,
          requestType: requestType,
          targetDate: targetDate,
          requestId: requestId,
          businessId: businessId,
          reason: reason,
        ),
      )));

      debugPrint('🔔 스케줄 변경 요청 알림 전송 완료 → 관리자: ${adminIds.length}명');
    } catch (e) {
      debugPrint('⚠️ 스케줄 변경 요청 알림 전송 실패: $e');
    }
  }

  // [H3-FIX] _sendScheduleChangeApprovedNotification, _sendScheduleChangeRejectedNotification 삭제
  // callableApproveScheduleChangeRequest CF가 알림을 직접 전송하므로 클라이언트 알림 함수 불필요

  /// 스케줄 변경 요청 취소
  /// [CF 이전 2026-07-14] callableCancelScheduleChangeRequest
  ///   이전 이유: applications leaveDates/extraWorkDates가 rules에서 명시적으로 보호되지 않아
  ///             관리자가 임의 배열로 덮어쓸 수 있었음. CF Admin SDK로 이전 후 차단 가능.
  Future<bool> cancelScheduleChangeRequest({
    required String requestId,
  }) async {
    GlobalLoadingController.show('처리 중...');
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCancelScheduleChangeRequest',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      await callable.call<Map<String, dynamic>>({'requestId': requestId});
      debugPrint('✅ 스케줄 변경 요청 취소 완료: $requestId');
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ 스케줄 변경 요청 취소 CF 오류: ${e.code} / ${e.message}');
      return false;
    } catch (e) {
      debugPrint('❌ 스케줄 변경 요청 취소 실패: $e');
      return false;
    } finally {
      GlobalLoadingController.hide();
    }
  }

  /// 사업장 주간 출근 기록 일괄 조회 (userId → AttendanceModel 리스트, CF 프록시)
  Future<Map<String, List<AttendanceModel>>> getWeeklyAttendanceByBusiness({
    required String businessId,
    required DateTime weekStart,
    required DateTime weekEnd,
  }) async {
    try {
      final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final end = DateTime(weekEnd.year, weekEnd.month, weekEnd.day)
          .add(const Duration(days: 1));
      final records = await _callableGetAdminAttendances(
        businessId: businessId,
        startDate: start,
        endDate: end,
      );
      final map = <String, List<AttendanceModel>>{};
      for (final att in records) {
        map.putIfAbsent(att.userId, () => []).add(att);
      }
      return map;
    } catch (e) {
      debugPrint('❌ 주간 출근 기록 조회 실패: $e');
      return {};
    }
  }

  /// 주휴수당 자격 판정 (현재 미사용 — 주휴 자동계산 기능 제거됨, 수동 확인용으로만 보존)
  /// [weeklyAttendances] 해당 userId의 주간 출근 리스트 (getWeeklyAttendanceByBusiness 결과)
  WeeklyHolidayEligibility computeWeeklyHolidayEligibility({
    required List<AttendanceModel> weeklyAttendances,
    required int scheduledDaysPerWeek,
    required int ordinaryHourlyWage,
    required DateTime weekStart,
    required DateTime weekEnd,
  }) {
    // 결근/노쇼가 아니고 실제 출근한 날 카운트
    final workedDays = weeklyAttendances
        .where((a) =>
            a.checkIn != null &&
            a.status != AttendanceModel.statusAbsent &&
            a.status != AttendanceModel.statusNoShow)
        .length;
    final totalWorkMinutes = weeklyAttendances
        .fold<int>(0, (acc, a) => acc + ((a.workHours ?? 0) * 60).round());
    final meetsHours = totalWorkMinutes >= 15 * 60;
    final meetsDays = workedDays >= scheduledDaysPerWeek;
    final isEligible = meetsHours && meetsDays;
    final weeklyHolidayAmount = isEligible
        ? WageCalculator.calculateWeeklyHolidayPay(
            ordinaryHourlyWage: ordinaryHourlyWage,
            weeklyWorkMinutes: totalWorkMinutes,
          )
        : 0;
    return WeeklyHolidayEligibility(
      isEligible: isEligible,
      workedDays: workedDays,
      scheduledDaysPerWeek: scheduledDaysPerWeek,
      totalWorkMinutes: totalWorkMinutes,
      weeklyHolidayAmount: weeklyHolidayAmount,
      weekStart: weekStart,
      weekEnd: weekEnd,
    );
  }

}