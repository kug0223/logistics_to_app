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

      // 0. 사용자 제재 상태 확인
      final userDoc = await _firestore.collection('users').doc(userId).get();
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
      }

      // 1. 지원서 상태 확인 (CONFIRMED만 출근 가능)
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();

      if (!appDoc.exists) {
        throw Exception('지원서를 찾을 수 없습니다.');
      }

      final appStatus = appDoc.data()?['status'] as String?;
      // CONTRACT_PENDING 포함 허용 — 의도된 정책:
      // 계약서 서명 전이더라도 근무 시작은 가능하게 하여 현장 마찰 최소화.
      // 서명 완료(CONFIRMED) 요구가 필요하다면 AppStatus.confirmed 단독으로 변경할 것.
      if (!AppStatus.confirmedStatuses.contains(appStatus)) {
        throw Exception('확정된 근무만 출퇴근 체크가 가능합니다. (현재 상태: $appStatus)');
      }

      // 2. 결정적 문서 ID — applicationId + 날짜 조합으로 중복 방지
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
        if (existing.exists && (existing.data()?['checkIn'] as String?)?.isNotEmpty == true) {
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
        if (data['checkOut'] != null) throw Exception('이미 퇴근하셨습니다.');

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
  Future<AttendanceModel?> getTodayAttendance({
    required String userId,
    required String applicationId,
  }) async {
    try {
      final today = DateTime.now();
      final todayStart = DateTime(today.year, today.month, today.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      // 야간 단기 근무(전날 출근 후 자정 이후 퇴근)를 위해 어제부터 조회
      final yesterdayStart = todayStart.subtract(const Duration(days: 1));

      final snapshot = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .where('applicationId', isEqualTo: applicationId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(yesterdayStart))
          .where('workDate', isLessThan: Timestamp.fromDate(todayEnd))
          .limit(1)
          .get();
      
      if (snapshot.docs.isEmpty) {
        return null;
      }
      
      return AttendanceModel.fromFirestore(snapshot.docs.first);
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
          .get();
      
      final attendances = snapshot.docs
          .map((doc) => AttendanceModel.fromFirestore(doc))
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
      
      // 1. 오늘 확정된 단기 근무 (CONTRACT_PENDING 포함)
      final shortTermSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', whereIn: AppStatus.confirmedStatuses)
          .where('workDate', isEqualTo: Timestamp.fromDate(todayStart))
          .get();
      
      final shortTerm = shortTermSnapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
      
      debugPrint('   단기 근무자: ${shortTerm.length}명');
      
      // 2. 오늘 근무하는 장기 근무자 (CONTRACT_PENDING 포함)
      final longTermSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', whereIn: AppStatus.confirmedStatuses)
          .where('type', isEqualTo: AppType.longTerm)
          .get();
      
      final longTerm = longTermSnapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .where((app) {
            // 오늘이 근무일인지 확인
            if (app.workEndDate == null) return false;
            
            final isInRange = !todayStart.isBefore(app.workDate) && 
                             !todayStart.isAfter(app.workEndDate!);
            
            if (!isInRange) return false;
            
            // 근무 요일 확인
            if (app.workDays == null || app.workDays!.isEmpty) {
              return true; // 매일 근무
            }
            
            final todayWeekday = FormatHelper.weekday(today);
            
            return app.workDays!.contains(todayWeekday);
          })
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
          .get();
      
      return snapshot.docs
          .map((doc) => AttendanceModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('❌ 출근 기록 조회 실패: $e');
      return [];
    }
  }
  /// 사용자별 월별 출근 기록 조회
  Future<List<AttendanceModel>> getMyMonthlyAttendances({
    required String userId,
    required int year,
    required int month,
  }) async {
    try {
      final monthStart = DateTime(year, month, 1);
      final monthEnd = DateTime(year, month + 1, 1);
      
      debugPrint('🔍 [getMyMonthlyAttendances] $year년 $month월 출근 기록 조회');
      debugPrint('   userId: $userId');
      debugPrint('   monthStart: $monthStart');
      debugPrint('   monthEnd: $monthEnd');
      
      final snapshot = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('workDate', isLessThan: Timestamp.fromDate(monthEnd))
          .orderBy('workDate', descending: false)
          .get();
      
      final attendances = snapshot.docs
          .map((doc) => AttendanceModel.fromFirestore(doc))
          .toList();
      
      debugPrint('✅ 월별 출근 기록: ${attendances.length}건');
      
      // 🔍 디버그: 각 attendance의 wageStatus, finalWage 출력
      for (var att in attendances) {
        debugPrint('   📋 ${att.workDate.toString().substring(0, 10)}: checkIn=${att.checkIn}, wageStatus=${att.wageStatus}, finalWage=${att.finalWage}');
      }
      
      return attendances;
    } catch (e, stackTrace) {
      debugPrint('❌ 월별 출근 기록 조회 실패: $e');
      debugPrint('📋 스택트레이스: $stackTrace');
      
      // 🔗 인덱스 생성 링크가 에러에 포함되어 있으면 출력
      if (e.toString().contains('index')) {
        debugPrint('⚠️ Firestore 복합 인덱스가 필요합니다!');
        debugPrint('   위 에러 메시지의 링크를 클릭하여 인덱스를 생성하세요.');
      }
      return [];
    }
  }
  // ═══════════════════════════════════════════════════════════
  // 스케줄 변경 요청 관리 (Schedule Change Request Management)
  // ═══════════════════════════════════════════════════════════

  /// 스케줄 변경 요청 생성
  Future<String?> createScheduleChangeRequest(ScheduleChangeRequestModel request) async {
    try {
      final docRef = await _firestore.collection('schedule_change_requests').add(request.toMap());
      debugPrint('✅ 스케줄 변경 요청 생성 완료: ${docRef.id}');
      
      // 🔔 알림 생성 (관리자에게) - 지원자가 요청한 경우
      if (request.requestedBy == RequesterType.APPLICANT) {
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
          .get();

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
          .get();

      return snapshot.docs
          .map((doc) => ScheduleChangeRequestModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('❌ 스케줄 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 지원자의 스케줄 변경 요청 조회
  Future<List<ScheduleChangeRequestModel>> getMyScheduleChangeRequests(String applicantUid) async {
    try {
      final snapshot = await _firestore
          .collection('schedule_change_requests')
          .where('applicantUid', isEqualTo: applicantUid)
          .orderBy('requestedAt', descending: true)
          .get();

      return snapshot.docs
          .map((doc) => ScheduleChangeRequestModel.fromMap(doc.data(), doc.id))
          .toList();
    } catch (e) {
      debugPrint('❌ 내 스케줄 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 특정 날짜의 대기중인 스케줄 변경 요청 조회 (다중 사업장)
  Future<List<ScheduleChangeRequestModel>> getScheduleChangeRequestsForDate({
    required DateTime date,
    required List<String> businessIds,
  }) async {
    if (businessIds.isEmpty) return [];
    try {
      final results = <ScheduleChangeRequestModel>[];
      for (int i = 0; i < businessIds.length; i += 10) {
        final batch = businessIds.sublist(
          i,
          i + 10 < businessIds.length ? i + 10 : businessIds.length,
        );
        final snap = await _firestore
            .collection('schedule_change_requests')
            .where('businessId', whereIn: batch)
            .where('status', isEqualTo: 'PENDING')
            .get();
        results.addAll(
          snap.docs
              .map((d) => ScheduleChangeRequestModel.fromMap(d.data(), d.id))
              .where((r) =>
                  r.targetDate.year == date.year &&
                  r.targetDate.month == date.month &&
                  r.targetDate.day == date.day),
        );
      }
      return results;
    } catch (e) {
      debugPrint('❌ 날짜별 스케줄 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 스케줄 변경 요청 승인
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

        // Application leaveDates / extraWorkDates 원자적 업데이트
        final appRef = _firestore.collection('applications').doc(request!.applicationId);
        final appSnapshot = await tx.get(appRef);
        if (appSnapshot.exists) {
          final appData = appSnapshot.data()!;

          if (request!.isLeaveRequest || request!.isNoWorkRequest) {
            List<DateTime> leaveDates = [];
            if (appData['leaveDates'] != null) {
              leaveDates = (appData['leaveDates'] as List)
                  .map((e) => (e as Timestamp).toDate().toLocal())
                  .toList();
            }
            if (!leaveDates.any((d) =>
                d.year == request!.targetDate.year &&
                d.month == request!.targetDate.month &&
                d.day == request!.targetDate.day)) {
              leaveDates.add(request!.targetDate);
            }
            tx.update(appRef, {
              'leaveDates': leaveDates.map((e) => Timestamp.fromDate(e)).toList(),
            });
          } else if (request!.isExtraWorkRequest) {
            List<DateTime> extraWorkDates = [];
            if (appData['extraWorkDates'] != null) {
              extraWorkDates = (appData['extraWorkDates'] as List)
                  .map((e) => (e as Timestamp).toDate().toLocal())
                  .toList();
            }
            if (!extraWorkDates.any((d) =>
                d.year == request!.targetDate.year &&
                d.month == request!.targetDate.month &&
                d.day == request!.targetDate.day)) {
              extraWorkDates.add(request!.targetDate);
            }
            tx.update(appRef, {
              'extraWorkDates': extraWorkDates.map((e) => Timestamp.fromDate(e)).toList(),
            });
          }
        }
      });

      debugPrint('✅ 스케줄 변경 요청 승인 완료: $requestId');

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
      final businessDoc = await _firestore.collection('businesses').doc(businessId).get();
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
      final businessDoc = await _firestore.collection('businesses').doc(businessId).get();
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
      final businessDoc = await _firestore.collection('businesses').doc(businessId).get();
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
          .get();

      if (!requestDoc.exists) {
        debugPrint('❌ 요청을 찾을 수 없음');
        return false;
      }

      final request = ScheduleChangeRequestModel.fromMap(requestDoc.data()!, requestId);

      // 2. 승인된 요청이면 ApplicationModel에서도 제거 (batch로 원자화)
      final batch = _firestore.batch();

      if (request.isApproved) {
        final appSnapshot = await _firestore
            .collection('applications')
            .doc(request.applicationId)
            .get();

        if (appSnapshot.exists) {
          final appData = appSnapshot.data()!;

          if (request.isLeaveRequest || request.isNoWorkRequest) {
            // leaveDates에서 제거 (.toLocal()로 approve 경로와 일관성 유지)
            List<DateTime> leaveDates = [];
            if (appData['leaveDates'] != null) {
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
            if (appData['extraWorkDates'] != null) {
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
          .get();
      final map = <String, List<AttendanceModel>>{};
      for (final doc in snapshot.docs) {
        final att = AttendanceModel.fromFirestore(doc);
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
          .get();

      return snapshot.docs.length;
    } catch (e) {
      debugPrint('❌ 대기중인 요청 개수 조회 실패: $e');
      return 0;
    }
  }
}