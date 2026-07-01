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
      final checkInTime = FormatHelper.formatTimeWithSeconds(now);
      final isNextDay = now.year != workDate.year ||
          now.month != workDate.month ||
          now.day != workDate.day;
      final isLate = scheduledStartTime != null &&
          AttendanceStatusHelper.isLate(checkInTime, scheduledStartTime, isNextDay: isNextDay);
      final dbStatus = isLate
          ? AttendanceModel.statusLate
          : AttendanceModel.statusPresent;

      debugPrint('   checkInTime: $checkInTime, scheduled: $scheduledStartTime, isLate: $isLate');

      // 4. 트랜잭션으로 원자적 체크 + 생성 (동시 요청 시 중복 출근 방지)
      await _firestore.runTransaction((tx) async {
        final existing = await tx.get(docRef);
        if (existing.exists && ((existing.data()?['checkIn'] as String?) ?? '').isNotEmpty) {
          debugPrint('⚠️ 이미 출근 완료');
          throw Exception('오늘 이미 출근하셨습니다.');
        }
        tx.set(docRef, {
          'applicationId': applicationId,
          'userId': userId,
          'businessId': businessId,
          'businessName': businessName,
          'workDate': Timestamp.fromDate(workDate),
          'workType': workType,
          'checkIn': checkInTime,           // HH:mm:ss 표시용 (클라이언트 로컬 시간)
          'checkInTime': FieldValue.serverTimestamp(), // 서버 시간 기준 실제 기록
          'originalCheckIn': checkInTime,  // 원본 보존
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
  Future<bool> checkOut({
    required String attendanceId,
    double? latitude,
    double? longitude,
    String method = 'gps',
    String? scheduledEndTime,
  }) async {
    NetworkChecker.instance.assertOnline('퇴근 체크를 하려면 인터넷 연결이 필요합니다.');
    try {
      debugPrint('🕐 [checkOut] 퇴근 체크 시작...');
      debugPrint('   attendanceId: $attendanceId');

      final attendanceRef =
          _firestore.collection('attendance').doc(attendanceId);
      final now = DateTime.now();
      final checkOutTime = FormatHelper.formatTimeWithSeconds(now);

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

        final checkInTime = data['checkIn'] as String?;
        if (checkInTime == null) throw Exception('출근 기록에 시간 정보가 없습니다.');
        final workMins = AttendanceStatusHelper.workMinutes(checkInTime, checkOutTime);
        final workHours = workMins / 60.0;

        final currentStatus =
            data['status'] as String? ?? AttendanceModel.statusPresent;
        final isEarlyLeave = scheduledEndTime != null &&
            AttendanceStatusHelper.isEarlyLeave(
                checkOutTime, scheduledEndTime, checkIn: checkInTime);
        final updatedStatus = isEarlyLeave
            ? AttendanceModel.statusEarlyLeave
            : currentStatus;

        tx.update(attendanceRef, {
          'checkOut': checkOutTime,
          if (data['originalCheckOut'] == null)
            'originalCheckOut': checkOutTime,  // 최초 퇴근 시에만 원본 보존
          if (latitude != null) 'checkOutLat': latitude,
          if (longitude != null) 'checkOutLng': longitude,
          'checkOutMethod': method,
          'workHours': workHours,
          'status': updatedStatus,
          // M-3: 0분 근무(출근 직후 퇴근) 플래그 — 관리자 검토 배지 표시용
          if (workMins == 0) 'isZeroWork': true,
          'updatedAt': FieldValue.serverTimestamp(),
        });
        debugPrint('   checkOutTime: $checkOutTime, scheduled: $scheduledEndTime, isEarlyLeave: $isEarlyLeave');
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
        final att = AttendanceModel.fromFirestore(doc);
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

  /// 사업장별 오늘 출근 현황 조회 (관리자용)
  Future<List<AttendanceModel>> getTodayAttendanceByBusiness({
    required String businessId,
  }) async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      
      debugPrint('🔍 [getTodayAttendanceByBusiness] 조회 시작...');
      debugPrint('   businessId: $businessId');
      debugPrint('   todayStart: $todayStart');
      
      final snapshot = await _firestore
          .collection('attendance')
          .where('businessId', isEqualTo: businessId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('workDate', isLessThan: Timestamp.fromDate(todayEnd))
          .orderBy('workDate', descending: false)
          .orderBy('checkInTime', descending: false)
          .get(const GetOptions(source: Source.server));

      final attendances = snapshot.docs
          .map(AttendanceModel.tryFromFirestore)
          .whereType<AttendanceModel>()
          .toList();

      debugPrint('✅ 오늘 출근 현황: ${attendances.length}명');
      return attendances;
    } catch (e) {
      debugPrint('❌ 출근 현황 조회 실패: $e');
      return [];
    }
  }

  /// 오늘 확정된 근무자 목록 조회 (출근 대상자)
  Future<List<ApplicationModel>> getTodayConfirmedWorkers({
    required String businessId,
  }) async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      
      debugPrint('🔍 [getTodayConfirmedWorkers] 조회 시작...');

      // 단기·장기 쿼리 병렬 실행 (독립적이므로 Future.wait 가능)
      // [BUGFIX] whereIn + equality 복합쿼리에서 Firestore 보안 규칙이
      //   request.query.filters.businessId를 null 반환 → PERMISSION_DENIED.
      //   status whereIn 제거 후 클라이언트 필터링으로 전환.
      final confirmedSet = Set<String>.from(AppStatus.confirmedStatuses);
      final snapshots = await Future.wait([
        // 1. 오늘 단기 근무 전체 조회 → status 클라이언트 필터
        _firestore
            .collection('applications')
            .where('businessId', isEqualTo: businessId)
            .where('workDate', isEqualTo: Timestamp.fromDate(todayStart))
            .get(const GetOptions(source: Source.server)),
        // 2. 장기 근무자 전체 조회 → status·isWorkingOnDate 클라이언트 필터
        _firestore
            .collection('applications')
            .where('businessId', isEqualTo: businessId)
            .where('type', isEqualTo: AppType.longTerm)
            .get(const GetOptions(source: Source.server)),
      ]);

      final shortTerm = snapshots[0].docs
          .map(ApplicationModel.tryFromFirestore)
          .whereType<ApplicationModel>()
          .where((app) => confirmedSet.contains(app.status))
          .toList();

      debugPrint('   단기 근무자: ${shortTerm.length}명');

      final longTerm = snapshots[1].docs
          .map(ApplicationModel.tryFromFirestore)
          .whereType<ApplicationModel>()
          .where((app) => confirmedSet.contains(app.status))
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

  /// 특정 날짜 출근 기록 조회
  Future<List<AttendanceModel>> getAttendanceByDate({
    required String businessId,
    required DateTime date,
  }) async {
    try {
      final dateStart = DateTime(date.year, date.month, date.day);
      final dateEnd = dateStart.add(const Duration(days: 1));
      
      final snapshot = await _firestore
          .collection('attendance')
          .where('businessId', isEqualTo: businessId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(dateStart))
          .where('workDate', isLessThan: Timestamp.fromDate(dateEnd))
          .get(const GetOptions(source: Source.server));

      return snapshot.docs
          .map(AttendanceModel.tryFromFirestore)
          .whereType<AttendanceModel>()
          .toList();
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
          .httpsCallable('getMyMonthlyAttendances');
      final result = await callable.call({'year': year, 'month': month});
      final items = (result.data['items'] as List<dynamic>? ?? []);
      return items
          .map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            final id = m.remove('id') as String? ?? '';
            return AttendanceModel.fromMap(m, id);
          })
          .toList();
    } catch (e) {
      debugPrint('❌ 월별 출근 기록 조회 실패: $e');
      return [];
    }
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
            (attendanceDoc.data()?['checkIn'] as String?) != null) {
          throw Exception('이미 출근한 날짜는 휴무 요청을 할 수 없습니다.');
        }
      }

      final docRef = await _firestore.collection('schedule_change_requests').add(request.toMap());
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
  Future<List<ScheduleChangeRequestModel>> getPendingScheduleChangeRequests(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('schedule_change_requests')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'PENDING')
          .orderBy('requestedAt', descending: true)
          .get(const GetOptions(source: Source.server));

      return snapshot.docs
          .map((doc) => ScheduleChangeRequestModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('❌ 대기중인 스케줄 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 사업장의 모든 스케줄 변경 요청 조회
  Future<List<ScheduleChangeRequestModel>> getAllScheduleChangeRequests(String businessId) async {
    try {
      final snapshot = await _firestore
          .collection('schedule_change_requests')
          .where('businessId', isEqualTo: businessId)
          .orderBy('requestedAt', descending: true)
          .limit(2000)
          .get(const GetOptions(source: Source.server));

      return snapshot.docs
          .map((doc) => ScheduleChangeRequestModel.fromMap(doc.data(), doc.id))
          .toList();
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
          .map((doc) => ScheduleChangeRequestModel.fromMap(doc.data(), doc.id))
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
  Future<List<ScheduleChangeRequestModel>> getScheduleChangeRequestsForDate({
    required DateTime date,
    required List<String> businessIds,
  }) async {
    if (businessIds.isEmpty) return [];
    try {
      // 사업장별 개별 쿼리를 병렬로 실행 (whereIn은 보안 규칙 위반으로 사용 불가)
      final snaps = await Future.wait(
        businessIds.map((businessId) => _firestore
            .collection('schedule_change_requests')
            .where('businessId', isEqualTo: businessId)
            .where('status', isEqualTo: 'PENDING')
            .get(const GetOptions(source: Source.server))),
      );
      return snaps
          .expand((snap) => snap.docs
              .map((d) => ScheduleChangeRequestModel.fromMap(d.data(), d.id))
              .where((r) =>
                  r.targetDate.year == date.year &&
                  r.targetDate.month == date.month &&
                  r.targetDate.day == date.day))
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
  Future<bool> approveScheduleChangeRequest({
    required String requestId,
    required String approverUid,
  }) async {
    ScheduleChangeRequestModel? request;
    try {
      final requestRef = _firestore.collection('schedule_change_requests').doc(requestId);

      await _firestore.runTransaction((tx) async {
        final requestDoc = await tx.get(requestRef);
        if (!requestDoc.exists) throw Exception('요청을 찾을 수 없음');

        request = ScheduleChangeRequestModel.fromMap(requestDoc.data()!, requestId);

        // 이미 처리된 요청 중복 승인 방지 (트랜잭션 내 원자적 체크)
        if (!request!.isPending) {
          throw Exception('이미 처리된 요청 (${request!.status})');
        }

        tx.update(requestRef, {
          'status': 'APPROVED',
          'respondedByUid': approverUid,
          'respondedAt': FieldValue.serverTimestamp(),
        });

        // ── Application leaveDates / extraWorkDates 원자적 업데이트 ──────────────
        // 요청 타입별로 Application 문서의 배열 필드를 트랜잭션 내에서 갱신.
        // 트랜잭션 외부에서 별도 업데이트하면 요청 상태(APPROVED)와 배열 변경 사이에
        // 타이밍 불일치가 생길 수 있으므로 반드시 같은 tx 안에서 처리.
        final appRef = _firestore.collection('applications').doc(request!.applicationId);
        final appSnapshot = await tx.get(appRef);
        if (appSnapshot.exists) {
          final appData = appSnapshot.data()!;

          bool sameDay(DateTime d) =>
              d.year == request!.targetDate.year &&
              d.month == request!.targetDate.month &&
              d.day == request!.targetDate.day;

          List<DateTime> parseDates(String field) =>
              appData[field] is List
                  ? (appData[field] as List)
                      .map((e) => (e as Timestamp).toDate().toLocal())
                      .toList()
                  : [];

          if (request!.isLeaveRequest || request!.isNoWorkRequest) {
            // 휴무·미출근 승인: leaveDates에 날짜 추가
            // → isLeaveDateOn(date)=true → isWorkingOnDate=false → 당일 명단·출근 체크 차단
            final leaveDates = parseDates('leaveDates');
            if (!leaveDates.any(sameDay)) leaveDates.add(request!.targetDate);
            tx.update(appRef, {
              'leaveDates': leaveDates.map((e) => Timestamp.fromDate(e)).toList(),
            });
          } else if (request!.isExtraWorkRequest) {
            // 추가근무 승인: extraWorkDates에 날짜 추가
            // → isExtraWorkDateOn(date)=true → isWorkingOnDate=true → 비근무 요일에도 출근 가능
            final extraWorkDates = parseDates('extraWorkDates');
            if (!extraWorkDates.any(sameDay)) extraWorkDates.add(request!.targetDate);
            tx.update(appRef, {
              'extraWorkDates': extraWorkDates.map((e) => Timestamp.fromDate(e)).toList(),
            });
          } else if (request!.requestType == RequestType.CANCEL_LEAVE) {
            // 휴무 취소 승인: leaveDates에서 해당 날짜 제거
            // 제거하지 않으면 isLeaveDateOn=true가 유지돼 checkIn 서비스에서
            // "오늘은 승인된 휴무일" 예외가 발생해 근무자가 출근 불가 상태에 빠짐
            final leaveDates = parseDates('leaveDates')..removeWhere(sameDay);
            tx.update(appRef, {
              'leaveDates': leaveDates.map((e) => Timestamp.fromDate(e)).toList(),
            });
          } else if (request!.requestType == RequestType.CANCEL_EXTRA) {
            // 추가근무 취소 승인: extraWorkDates에서 해당 날짜 제거
            // 제거하지 않으면 isExtraWorkDateOn=true가 유지돼 당일 명단에 계속 포함되고
            // 해당 날짜 isWorkingOnDate=true 상태가 유지됨
            final extraWorkDates = parseDates('extraWorkDates')..removeWhere(sameDay);
            tx.update(appRef, {
              'extraWorkDates': extraWorkDates.map((e) => Timestamp.fromDate(e)).toList(),
            });
          }
        }
      });

      debugPrint('✅ 스케줄 변경 요청 승인 완료: $requestId');

      // [BUG-수정 N-H-2] 배치 커밋 후 지원자 TTL 캐시 무효화.
      // 트랜잭션에서 leaveDates/extraWorkDates가 변경됐지만 캐시가 살아 있으면
      // 지원자 화면에서 최대 1분간 구 데이터가 표시되는 문제 수정.
      if (request != null) {
        invalidateMyApplicationsCache(request!.applicantUid);
      }

      // 🔔 알림 생성 (트랜잭션 외부 — 알림 실패가 승인을 롤백하지 않도록)
      if (request != null) {
        _sendScheduleChangeApprovedNotification(
          applicantUid: request!.applicantUid,
          businessId: request!.businessId,
          requestType: request!.requestType.name,
          targetDate: request!.targetDate,
          requestId: requestId,
        );
      }

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
  Future<bool> rejectScheduleChangeRequest({
    required String requestId,
    required String rejectorUid,
    String? rejectReason,
  }) async {
    ScheduleChangeRequestModel? request;
    try {
      final requestRef = _firestore.collection('schedule_change_requests').doc(requestId);

      await _firestore.runTransaction((tx) async {
        final requestDoc = await tx.get(requestRef);
        if (!requestDoc.exists) throw Exception('요청 문서 없음');

        request = ScheduleChangeRequestModel.fromMap(requestDoc.data()!, requestId);
        if (!request!.isPending) throw Exception('이미 처리된 요청 (${request!.status})');

        tx.update(requestRef, {
          'status': 'REJECTED',
          'respondedByUid': rejectorUid,
          'respondedAt': FieldValue.serverTimestamp(),
          'rejectReason': rejectReason,
        });
      });

      debugPrint('✅ 스케줄 변경 요청 거절 완료: $requestId');

      // [BUG-수정 N-H-3] 거절 완료 후 지원자 TTL 캐시 무효화.
      // 캐시가 만료되기 전까지 요청 상태가 여전히 PENDING으로 보이는 문제 수정.
      if (request != null) {
        invalidateMyApplicationsCache(request!.applicantUid);
      }

      if (request != null) {
        _sendScheduleChangeRejectedNotification(
          applicantUid: request!.applicantUid,
          businessId: request!.businessId,
          requestType: request!.requestType.name,
          targetDate: request!.targetDate,
          requestId: requestId,
          rejectReason: rejectReason,
        );
      }

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
      
      final adminUid = businessDoc.data()?['ownerId'] as String?;
      if (adminUid == null || adminUid.isEmpty) return;
      
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
      
      debugPrint('🔔 스케줄 변경 요청 알림 전송 완료 → 관리자: $adminUid');
    } catch (e) {
      debugPrint('⚠️ 스케줄 변경 요청 알림 전송 실패: $e');
    }
  }

  /// 🔔 스케줄 변경 승인 알림 전송 (요청자에게)
  Future<void> _sendScheduleChangeApprovedNotification({
    required String applicantUid,
    required String businessId,
    required String requestType,
    required DateTime targetDate,
    required String requestId,
  }) async {
    try {
      // 사업장 이름 조회
      final businessDoc = await _firestore.collection('businesses').doc(businessId).get(const GetOptions(source: Source.server));
      final businessName = businessDoc.data()?['name'] as String? ?? '';
      
      await createNotification(
        NotificationModel.createScheduleChangeApproved(
          userId: applicantUid,
          requestType: requestType,
          targetDate: targetDate,
          requestId: requestId,
          businessName: businessName,
          businessId: businessId,
        ),
      );
      
      debugPrint('🔔 스케줄 변경 승인 알림 전송 완료 → 지원자: $applicantUid');
    } catch (e) {
      debugPrint('⚠️ 스케줄 변경 승인 알림 전송 실패: $e');
    }
  }

  /// 🔔 스케줄 변경 거절 알림 전송 (요청자에게)
  Future<void> _sendScheduleChangeRejectedNotification({
    required String applicantUid,
    required String businessId,
    required String requestType,
    required DateTime targetDate,
    required String requestId,
    String? rejectReason,
  }) async {
    try {
      // 사업장 이름 조회
      final businessDoc = await _firestore.collection('businesses').doc(businessId).get(const GetOptions(source: Source.server));
      final businessName = businessDoc.data()?['name'] as String? ?? '';
      
      await createNotification(
        NotificationModel.createScheduleChangeRejected(
          userId: applicantUid,
          requestType: requestType,
          targetDate: targetDate,
          requestId: requestId,
          businessName: businessName,
          businessId: businessId,
          rejectReason: rejectReason,
        ),
      );
      
      debugPrint('🔔 스케줄 변경 거절 알림 전송 완료 → 지원자: $applicantUid');
    } catch (e) {
      debugPrint('⚠️ 스케줄 변경 거절 알림 전송 실패: $e');
    }
  }


  /// 스케줄 변경 요청 취소
  Future<bool> cancelScheduleChangeRequest({
    required String requestId,
    required String canceledByUid,
  }) async {
    try {
      // 1. 요청 정보 조회
      final requestDoc = await _firestore
          .collection('schedule_change_requests')
          .doc(requestId)
          .get(const GetOptions(source: Source.server));

      if (!requestDoc.exists) {
        debugPrint('❌ 요청을 찾을 수 없음');
        return false;
      }

      final request = ScheduleChangeRequestModel.fromMap(requestDoc.data()!, requestId);

      // 취소 가능 상태: PENDING(미처리) 또는 APPROVED(적용 취소)
      // REJECTED/CANCELED 요청은 재취소 불가 — 상태 이력 왜곡 방지
      if (!request.isPending && !request.isApproved) {
        debugPrint('⚠️ 취소 불가 상태: ${request.status}');
        return false;
      }

      // 2. 승인된 요청이면 ApplicationModel에서도 제거 (batch로 원자화)
      final batch = _firestore.batch();

      if (request.isApproved) {
        final appSnapshot = await _firestore
            .collection('applications')
            .doc(request.applicationId)
            .get(const GetOptions(source: Source.server));

        if (appSnapshot.exists) {
          final appData = appSnapshot.data()!;

          if (request.isLeaveRequest || request.isNoWorkRequest) {
            // leaveDates에서 제거 (.toLocal()로 approve 경로와 일관성 유지)
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

            batch.update(_firestore.collection('applications').doc(request.applicationId), {
              'leaveDates': leaveDates.map((e) => Timestamp.fromDate(e)).toList(),
            });
          } else if (request.isExtraWorkRequest) {
            // extraWorkDates에서 제거 (.toLocal()로 approve 경로와 일관성 유지)
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

            batch.update(_firestore.collection('applications').doc(request.applicationId), {
              'extraWorkDates': extraWorkDates.map((e) => Timestamp.fromDate(e)).toList(),
            });
          }
        }
      }

      // 3. 요청 상태 업데이트 (batch에 포함 — applications 업데이트와 원자적으로 처리)
      batch.update(_firestore.collection('schedule_change_requests').doc(requestId), {
        'status': 'CANCELED',
        'respondedByUid': canceledByUid,
        'respondedAt': FieldValue.serverTimestamp(),
      });
      await batch.commit();

      debugPrint('✅ 스케줄 변경 요청 취소 완료: $requestId');
      return true;
    } catch (e) {
      debugPrint('❌ 스케줄 변경 요청 취소 실패: $e');
      return false;
    }
  }

  /// 사업장 주간 출근 기록 일괄 조회 (userId → AttendanceModel 리스트)
  /// weekStart ~ weekEnd(inclusive) 범위 내 모든 근무자의 출근 기록 반환
  Future<Map<String, List<AttendanceModel>>> getWeeklyAttendanceByBusiness({
    required String businessId,
    required DateTime weekStart,
    required DateTime weekEnd,
  }) async {
    try {
      final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
      final end = DateTime(weekEnd.year, weekEnd.month, weekEnd.day)
          .add(const Duration(days: 1));
      final snapshot = await _firestore
          .collection('attendance')
          .where('businessId', isEqualTo: businessId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('workDate', isLessThan: Timestamp.fromDate(end))
          .get(const GetOptions(source: Source.server));
      final map = <String, List<AttendanceModel>>{};
      for (final doc in snapshot.docs) {
        final att = AttendanceModel.tryFromFirestore(doc);
        if (att == null) continue;
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