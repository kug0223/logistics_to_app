part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 출근/스케줄/퇴사 관리 (Attendance & Schedule Management)
// ═══════════════════════════════════════════════════════════

extension AttendanceFirestore on FirestoreService {
  // ═══════════════════════════════════════════════════════════
  // 🕐 출근 관리 (Attendance Management)
  // ═══════════════════════════════════════════════════════════

  /// 출근 체크
  /// [scheduledStartTime] "HH:mm" 형식 예정 출근 시간 — 전달 시 지각 여부 자동 판단
  Future<String?> checkIn({
    required String applicationId,
    required String userId,
    required String businessId,
    required String businessName,
    required DateTime workDate,
    required String workType,
    double? latitude,   // 비콘 방식은 null 가능
    double? longitude,  // 비콘 방식은 null 가능
    String method = 'gps',
    String? scheduledStartTime,
    String? scheduledEndTime,
    AttendanceRules? attendanceRules,
  }) async {
    NetworkChecker.instance.assertOnline('출근 체크를 하려면 인터넷 연결이 필요합니다.');
    try {
      debugPrint('🕐 [checkIn] 출근 체크 시작...');
      debugPrint('   applicationId: $applicationId');
      debugPrint('   workDate: $workDate');

      // 0. 사용자 상태 확인
      final userDoc = await _firestore.collection('users').doc(userId).get(const GetOptions(source: Source.server));
      if (userDoc.exists) {
        final restrictedUntil = userDoc.data()?['restrictedUntil'];
        DateTime? restrictedDate;
        if (restrictedUntil is Timestamp) {
          restrictedDate = restrictedUntil.toDate().toLocal();
        }
        if (restrictedDate != null && restrictedDate.isAfter(DateTime.now())) {
          final until = FormatHelper.formatDateTime(restrictedDate);
          throw Exception('현재 근무 제재 중입니다. 제재 해제일: $until');
        }

        // H-9: 외국인 근로자 미승인(pending/rejected) 시 출근 차단
        // foreignIdNumber 필드가 존재하면 외국인으로 판단 (암호화 저장이지만 null 여부로 식별 가능)
        final isForeignUser = (userDoc.data()?['foreignIdNumber'] as String?) != null;
        final accStatus = userDoc.data()?['accountStatus'] as String? ?? 'active';
        if (isForeignUser && accStatus != 'active') {
          throw Exception('외국인 등록 확인이 완료되지 않았습니다. 관리자의 승인을 받은 후 이용 가능합니다.');
        }
      }

      // 1. 지원서 상태 확인 (CONFIRMED만 출근 가능)
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get(const GetOptions(source: Source.server));

      if (!appDoc.exists) {
        throw Exception('지원서를 찾을 수 없습니다.');
      }

      // 소유자 검증: applicationId가 userId 본인 것인지 확인 (타인 지원서로 출근 위변조 방지)
      final appUserId = appDoc.data()?['uid'] as String?;
      if (appUserId != userId) {
        throw Exception('본인의 지원서만 출근 체크가 가능합니다.');
      }

      // 사업장 교차 검증: 지원서의 businessId와 파라미터 businessId가 일치하는지 확인
      final appBusinessId = appDoc.data()?['businessId'] as String?;
      if (appBusinessId != businessId) {
        throw Exception('지원서와 사업장 정보가 일치하지 않습니다.');
      }

      // 장기 근무자 휴무일(leaveDates) 체크 — 승인된 휴무일에는 출근 불가
      final appModel = ApplicationModel.fromFirestore(appDoc);
      if (appModel.isLeaveDateOn(workDate)) {
        throw Exception('오늘은 승인된 휴무일입니다. 출근 체크가 불가합니다.');
      }

      // 실제 퇴사일(actualResignDate) 체크 — 퇴사 처리 완료 후에는 출근 불가
      if (appModel.actualResignDate != null &&
          !workDate.isBefore(appModel.actualResignDate!)) {
        throw Exception('퇴사 처리가 완료된 근무입니다.');
      }

      final appStatus = appDoc.data()?['status'] as String?;
      // CONTRACT_PENDING 포함 허용 — 의도된 정책:
      // 계약서 서명 전이더라도 근무 시작은 가능하게 하여 현장 마찰 최소화.
      // 서명 완료(CONFIRMED) 요구가 필요하다면 AppStatus.confirmed 단독으로 변경할 것.
      if (!AppStatus.confirmedStatuses.contains(appStatus)) {
        throw Exception('확정된 근무만 출퇴근 체크가 가능합니다. (현재 상태: $appStatus)');
      }

      // 2. 결정적 문서 ID — applicationId + 날짜 조합으로 중복 방지
      // workDate는 호출자(attendance_check_screen._checkIn)가 근무 유형에 맞게 전달:
      //   - 단기: work.workDate(예정 근무일) — 야간 자정 이후 체크인 시 docId가 다음 날로 밀리지 않도록
      //   - 장기: DateTime.now()(오늘 날짜) — work.workDate=계약 시작일(고정)이라 날짜별 docId 분리 불가
      final todayStart = DateTime(workDate.year, workDate.month, workDate.day);
      final dateStr = '${todayStart.year}${todayStart.month.toString().padLeft(2,'0')}${todayStart.day.toString().padLeft(2,'0')}';
      final attendanceDocId = '${applicationId}_$dateStr';
      final docRef = _firestore.collection('attendance').doc(attendanceDocId);

      // 3. 출근 시간 계산 (트랜잭션 밖에서 수행해도 무방)
      final now = DateTime.now();

      // 3-1. 근태 규칙 자동 반올림 — DateTime 기반 offset 계산
      // scheduledStartTime 이 있을 때만 적용; 없으면 now 그대로 사용
      DateTime effectiveCheckInAt = now;
      bool isLate = false;
      if (scheduledStartTime != null && scheduledStartTime.isNotEmpty) {
        final contractStart = contractStartAt(workDate, scheduledStartTime);
        final rules  = resolveRules(attendanceRules);
        final offset = now.difference(contractStart).inMinutes;
        final result = processCheckin(
          offsetMinutes: offset,
          referenceAt: contractStart,
          rules: rules,
        );
        effectiveCheckInAt = result.roundedAt;
        isLate = result.type == RoundingType.late;
        debugLogRounding(label: 'checkIn', punchAt: now, result: result);
      }

      final dbStatus = isLate
          ? AttendanceModel.statusLate
          : AttendanceModel.statusPresent;

      debugPrint('   effectiveCheckInAt: $effectiveCheckInAt, scheduled: $scheduledStartTime, isLate: $isLate');

      // 4. 트랜잭션으로 원자적 체크 + 생성 (동시 요청 시 중복 출근 방지)
      await _firestore.runTransaction((tx) async {
        final existing = await tx.get(docRef);
        // 기존 문서가 있으면 무조건 차단 — checkIn 여부 불문.
        // checkIn 없는 노쇼 사전 생성 레코드가 덮어쓰이는 것을 방지.
        if (existing.exists) {
          debugPrint('⚠️ 이미 출근 완료 또는 기록 존재');
          throw Exception('오늘 이미 출근하셨습니다.');
        }
        tx.set(docRef, {
          'applicationId': applicationId,
          'userId': userId,
          'businessId': businessId,
          'businessName': businessName,
          'workDate': Timestamp.fromDate(DateTime(workDate.year, workDate.month, workDate.day)),
          'yearMonth': '${workDate.year}-${workDate.month.toString().padLeft(2, '0')}',
          'workType': workType,
          'checkIn': Timestamp.fromDate(effectiveCheckInAt),  // 반올림 적용 최종값 (Timestamp)
          'originalCheckIn': Timestamp.fromDate(now),         // GPS/비콘 원본 (절대 불변)
          // [P-01] 설계 스펙(attendance_rounding_design): autoRounded 플래그(bool) 미구현.
          // checkIn != originalCheckIn 비교로 자동 반올림 여부를 역추론할 수는 있으나,
          // 관리자 수동 수정 후에는 구분 불가. 이력 감사·근무자 UI 표시를 위해 나중에 추가 필요.
          if (latitude != null) 'checkInLat': latitude,
          if (longitude != null) 'checkInLng': longitude,
          'checkInMethod': method,
          'status': dbStatus,
          'isModified': false,
          'modifyRequested': false,
          'wageStatus': AttendanceModel.wagePending,
          'createdAt': FieldValue.serverTimestamp(),
        });
      });

      debugPrint('✅ 출근 체크 완료: $attendanceDocId (status: $dbStatus)');
      return attendanceDocId;
    } catch (e) {
      debugPrint('❌ 출근 체크 실패: $e');
      rethrow;
    }
  }

  /// 퇴근 체크
  /// [scheduledEndTime] "HH:mm" 형식 예정 퇴근 시간 — 전달 시 조퇴 여부 자동 판단
  /// [workDate] 근무 기준일 — contractEndAt 계산에 필요 (야간 교대 자정 처리)
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
    try {
      debugPrint('🕐 [checkOut] 퇴근 체크 시작...');
      debugPrint('   attendanceId: $attendanceId');

      final attendanceRef =
          _firestore.collection('attendance').doc(attendanceId);
      final now = DateTime.now();

      // 근태 규칙 자동 반올림 — DateTime 기반 offset 계산
      // start·end 시간이 모두 있을 때만 적용
      DateTime effectiveCheckOutAt = now;
      bool isEarlyLeaveFromRounding = false;
      if (scheduledStartTime != null && scheduledStartTime.isNotEmpty &&
          scheduledEndTime   != null && scheduledEndTime.isNotEmpty) {
        final contractEnd = contractEndAt(workDate, scheduledStartTime, scheduledEndTime);
        final rules  = resolveRules(attendanceRules);
        final offset = now.difference(contractEnd).inMinutes;
        final result = processCheckout(
          offsetMinutes: offset,
          referenceAt: contractEnd,
          rules: rules,
        );
        effectiveCheckOutAt = result.roundedAt;
        isEarlyLeaveFromRounding = result.type == RoundingType.earlyLeave;
        debugLogRounding(label: 'checkOut', punchAt: now, result: result);
      }

      // 트랜잭션으로 원자적 체크 + 업데이트 (동시 요청 시 중복 퇴근 방지)
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(attendanceRef);
        if (!snap.exists) throw Exception('출근 기록을 찾을 수 없습니다.');
        final data = snap.data()!;

        // 앱 레벨 소유권 재검증 — Firestore 규칙 변경 시에도 타인 attendanceId로 퇴근 처리 불가
        final currentUid = FirebaseAuth.instance.currentUser?.uid;
        if (data['userId'] != currentUid) {
          throw Exception('본인의 출근 기록만 퇴근 처리할 수 있습니다.');
        }

        if (data['checkOut'] != null) throw Exception('이미 퇴근하셨습니다.');

        // 급여 확정·이체 완료 후 퇴근 수정 시도 → Firestore 규칙이 차단하기 전에 명확한 메시지 제공
        final wageStatus = data['wageStatus'] as String?;
        if (wageStatus == 'transferred' || wageStatus == 'confirmed' || wageStatus == 'calculated') {
          throw Exception('급여 처리가 완료된 근무 기록은 수정할 수 없습니다.');
        }

        // checkIn — Timestamp(신규) 또는 "HH:mm" String(v1 레거시) 모두 처리
        final checkInRaw = data['checkIn'];
        if (checkInRaw == null) throw Exception('출근 기록에 시간 정보가 없습니다.');
        DateTime? checkInAt;
        if (checkInRaw is Timestamp) {
          checkInAt = checkInRaw.toDate();
        } else if (checkInRaw is String && checkInRaw.contains(':')) {
          final parts = checkInRaw.split(':');
          final h = int.tryParse(parts[0]);
          final m = parts.length > 1 ? int.tryParse(parts[1]) : null;
          final wdRaw = data['workDate'];
          if (h != null && m != null && wdRaw is Timestamp) {
            final wd = wdRaw.toDate();
            checkInAt = DateTime(wd.year, wd.month, wd.day, h, m);
          }
        }
        if (checkInAt == null) throw Exception('출근 기록 시간 파싱 실패');
        final workMins  = effectiveCheckOutAt.difference(checkInAt).inMinutes;
        // 반올림 후 checkIn > checkOut 가능성(음수 근무) → 0으로 clamp
        final workHours = (workMins < 0 ? 0 : workMins) / 60.0;

        final currentStatus =
            data['status'] as String? ?? AttendanceModel.statusPresent;
        final updatedStatus = isEarlyLeaveFromRounding
            ? AttendanceModel.statusEarlyLeave
            : currentStatus;

        tx.update(attendanceRef, {
          'checkOut': Timestamp.fromDate(effectiveCheckOutAt),  // 반올림 적용 최종값 (Timestamp)
          if (data['originalCheckOut'] == null)
            'originalCheckOut': Timestamp.fromDate(now),        // GPS/비콘 원본 (절대 불변)
          if (latitude != null) 'checkOutLat': latitude,
          if (longitude != null) 'checkOutLng': longitude,
          'checkOutMethod': method,
          'workHours': workHours,
          'status': updatedStatus,
          // 0분 이하 근무(반올림 충돌 포함) 플래그 — 관리자 검토 배지 표시용
          if (workMins <= 0) 'isZeroWork': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint('   effectiveCheckOutAt: $effectiveCheckOutAt, scheduled: $scheduledEndTime, isEarlyLeave: $isEarlyLeaveFromRounding');
      });

      debugPrint('✅ 퇴근 체크 완료');
      return true;
    } catch (e) {
      debugPrint('❌ 퇴근 체크 실패: $e');
      rethrow;
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
      return {};
    }
  }

  /// 특정 날짜 출근 기록 조회 (관리자용 — CF 프록시)
  Future<List<AttendanceModel>> getAttendanceByDate({
    required String businessId,
    required DateTime date,
  }) async {
    try {
      final dateStart = DateTime(date.year, date.month, date.day);
      final dateEnd = dateStart.add(const Duration(days: 1));
      return await _callableGetAdminAttendances(
        businessId: businessId,
        startDate: dateStart,
        endDate: dateEnd,
      );
    } catch (e) {
      debugPrint('❌ 출근 기록 조회 실패: $e');
      return [];
    }
  }
  /// 사용자별 월별 출근 기록 조회 (CF 프록시)
  /// attendance list 규칙에서 isUser() 제거 → CF로 auth.uid 기반 서버 검증
  Future<List<AttendanceModel>> getMyMonthlyAttendances({
    required String userId,
    required int year,
    required int month,
  }) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('getMyMonthlyAttendances',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      final result = await callable.call({'year': year, 'month': month});
      final items = (result.data['items'] as List<dynamic>? ?? []);
      return items
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            final id = m.remove('id') as String? ?? '';
            return AttendanceModel.tryFromMap(m, id);
          })
          .whereType<AttendanceModel>()
          .toList();
    } catch (e) {
      debugPrint('❌ 월별 출근 기록 조회 실패: $e');
      return [];
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
        .map((e) {
          final m = Map<String, dynamic>.from(e as Map);
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
    try {
      // [특이사항] LEAVE 요청 시 해당 날짜에 이미 출근한 경우 차단.
      // 출근 후 LEAVE 승인 시 application.leaveDates에는 날짜가 추가되지만
      // attendance.status는 'present'로 남아 데이터 불일치가 발생한다.
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
      return items.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = m.remove('id') as String? ?? '';
        return ScheduleChangeRequestModel.tryFromMap(_cfHydrate(m), id);
      }).whereType<ScheduleChangeRequestModel>().toList();
    } catch (e) {
      debugPrint('❌ 대기중인 스케줄 변경 요청 조회 실패: $e');
      return [];
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
      return items.map((e) {
        final m = Map<String, dynamic>.from(e as Map);
        final id = m.remove('id') as String? ?? '';
        return ScheduleChangeRequestModel.tryFromMap(_cfHydrate(m), id);
      }).whereType<ScheduleChangeRequestModel>().toList();
    } catch (e) {
      debugPrint('❌ 스케줄 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 지원자의 스케줄 변경 요청 조회
  // [BUG-수정] 캐시 데이터로 중복 요청 방어 로직이 오동작하지 않도록 항상 서버에서 최신 상태 조회
  // [보안 규칙] where('applicantUid') 단독 → filters.applicantUid == auth.uid (CRIT-02) 충족.
  //   whereIn 없이 isEqualTo 단독이므로 filters 정상 반환. 혼합(where+whereIn) 시 null 반환됨.
  Future<List<ScheduleChangeRequestModel>> getMyScheduleChangeRequests(String applicantUid) async {
    try {
      final snapshot = await _firestore
          .collection('schedule_change_requests')
          .where('applicantUid', isEqualTo: applicantUid)
          .orderBy('requestedAt', descending: true)
          .get(const GetOptions(source: Source.server));

      return snapshot.docs
          .map((doc) => ScheduleChangeRequestModel.tryFromMap(doc.data(), doc.id))
          .whereType<ScheduleChangeRequestModel>()
          .toList();
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
    required String approverUid,
  }) async {
    try {
      final callable = FirebaseFunctions.instance
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
    }
  }

  /// 스케줄 변경 요청 거절
  /// [H3-FIX] callableApproveScheduleChangeRequest CF로 이전 (action=REJECTED)
  Future<bool> rejectScheduleChangeRequest({
    required String requestId,
    required String rejectorUid,
    String? rejectReason,
  }) async {
    try {
      final callable = FirebaseFunctions.instance
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

      for (final adminUid in adminIds) {
        await createNotification(
          NotificationModel.createScheduleChangeRequested(
            userId: adminUid,
            requesterName: requesterName,
            requestType: requestType,
            targetDate: targetDate,
            requestId: requestId,
            businessId: businessId,
            reason: reason,
          ),
        );
      }

      debugPrint('🔔 스케줄 변경 요청 알림 전송 완료 → 관리자: ${adminIds.length}명');
    } catch (e) {
      debugPrint('⚠️ 스케줄 변경 요청 알림 전송 실패: $e');
    }
  }

  // [H3-FIX] _sendScheduleChangeApprovedNotification, _sendScheduleChangeRejectedNotification 삭제
  // callableApproveScheduleChangeRequest CF가 알림을 직접 전송하므로 클라이언트 알림 함수 불필요

  /// 스케줄 변경 요청 취소
  Future<bool> cancelScheduleChangeRequest({
    required String requestId,
    required String canceledByUid,
  }) async {
    try {
      // [MEDIUM-03] batch → runTransaction 전환으로 TOCTOU 경쟁 상태 방지.
      // 조회와 쓰기 사이에 다른 관리자/근로자가 상태를 바꾸는 경우를 원자적으로 처리.
      bool canceled = false;
      await _firestore.runTransaction((tx) async {
        // 1. 트랜잭션 내 요청 문서 읽기
        final requestRef = _firestore.collection('schedule_change_requests').doc(requestId);
        final requestSnap = await tx.get(requestRef);

        if (!requestSnap.exists) return;

        final request = ScheduleChangeRequestModel.fromMap(requestSnap.data()!, requestId);

        // 취소 가능 상태: PENDING(미처리) 또는 APPROVED(적용 취소)
        // REJECTED/CANCELED 요청은 재취소 불가 — 상태 이력 왜곡 방지
        if (!request.isPending && !request.isApproved) {
          debugPrint('⚠️ 취소 불가 상태: ${request.status}');
          return;
        }

        // 2. 승인된 요청이면 applications 문서도 트랜잭션 내에서 읽고 업데이트
        if (request.isApproved) {
          final appRef = _firestore.collection('applications').doc(request.applicationId);
          final appSnap = await tx.get(appRef);

          if (appSnap.exists) {
            final appData = appSnap.data()!;

            if (request.isLeaveRequest || request.isNoWorkRequest) {
              List<DateTime> leaveDates = [];
              if (appData['leaveDates'] is List) {
                leaveDates = (appData['leaveDates'] as List)
                    .map((e) => (e as Timestamp).toDate().toLocal())
                    .toList();
              }
              leaveDates.removeWhere((d) =>
                  d.year == request.targetDate.year &&
                  d.month == request.targetDate.month &&
                  d.day == request.targetDate.day);
              tx.update(appRef, {
                'leaveDates': leaveDates.map((e) => Timestamp.fromDate(e)).toList(),
              });
            } else if (request.isExtraWorkRequest) {
              List<DateTime> extraWorkDates = [];
              if (appData['extraWorkDates'] is List) {
                extraWorkDates = (appData['extraWorkDates'] as List)
                    .map((e) => (e as Timestamp).toDate().toLocal())
                    .toList();
              }
              extraWorkDates.removeWhere((d) =>
                  d.year == request.targetDate.year &&
                  d.month == request.targetDate.month &&
                  d.day == request.targetDate.day);
              tx.update(appRef, {
                'extraWorkDates': extraWorkDates.map((e) => Timestamp.fromDate(e)).toList(),
              });
            }
          }
        }

        // 3. 요청 상태 업데이트 (트랜잭션 내 — 원자적 처리)
        tx.update(requestRef, {
          'status': 'CANCELED',
          'respondedByUid': canceledByUid,
          'respondedAt': FieldValue.serverTimestamp(),
        });
        canceled = true;
      });

      if (canceled) debugPrint('✅ 스케줄 변경 요청 취소 완료: $requestId');
      return canceled;
    } catch (e) {
      debugPrint('❌ 스케줄 변경 요청 취소 실패: $e');
      return false;
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

  /// 대기중인 요청 개수 조회
  Future<int> getPendingScheduleChangeRequestCount(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('schedule_change_requests')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'PENDING')
          .get(const GetOptions(source: Source.server));

      return snapshot.docs.length;
    } catch (e) {
      debugPrint('❌ 대기중인 요청 개수 조회 실패: $e');
      return 0;
    }
  }
}