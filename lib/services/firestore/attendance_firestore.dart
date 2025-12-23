part of '../firestore_service.dart';

// ═══════════════════════════════════════════════════════════
// 출근/스케줄/퇴사 관리 (Attendance & Schedule Management)
// ═══════════════════════════════════════════════════════════

extension AttendanceFirestore on FirestoreService {
  // ═══════════════════════════════════════════════════════════
  // 🕐 출근 관리 (Attendance Management)
  // ═══════════════════════════════════════════════════════════

  /// 출근 체크
  Future<String?> checkIn({
    required String applicationId,
    required String userId,
    required String businessId,
    required String businessName,
    required DateTime workDate,
    required String workType,
    required double latitude,
    required double longitude,
    String method = 'gps',
  }) async {
    try {
      print('🕐 [checkIn] 출근 체크 시작...');
      print('   applicationId: $applicationId');
      print('   workDate: $workDate');
      
      // 🔥 0. 지원서 상태 확인 (CONFIRMED만 출근 가능)
      final appDoc = await _firestore
          .collection('applications')
          .doc(applicationId)
          .get();
      
      if (!appDoc.exists) {
        throw Exception('지원서를 찾을 수 없습니다.');
      }
      
      final appStatus = appDoc.data()?['status'] as String?;
      if (appStatus != 'CONFIRMED') {
        throw Exception('확정된 근무만 출퇴근 체크가 가능합니다. (현재 상태: $appStatus)');
      }
      
      // 1. 오늘 이미 출근했는지 확인
      final todayStart = DateTime(workDate.year, workDate.month, workDate.day);
      final todayEnd = todayStart.add(const Duration(days: 1));
      
      final existing = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('workDate', isLessThan: Timestamp.fromDate(todayEnd))
          .where('applicationId', isEqualTo: applicationId)
          .limit(1)
          .get();
      
      if (existing.docs.isNotEmpty) {
        final existingData = existing.docs.first.data();
        if (existingData['checkIn'] != null) {
          print('⚠️ 이미 출근 완료');
          throw Exception('오늘 이미 출근하셨습니다.');
        }
      }
      
      // 2. 출근 시간
      final now = DateTime.now();
      final checkInTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      
      // 3. 출근 기록 생성
      final attendanceData = {
        'applicationId': applicationId,
        'userId': userId,
        'businessId': businessId,
        'businessName': businessName,
        'workDate': Timestamp.fromDate(workDate),
        'workType': workType,
        'checkIn': checkInTime,
        'checkInLat': latitude,
        'checkInLng': longitude,
        'checkInMethod': method,
        'checkInTime': FieldValue.serverTimestamp(),
        'status': 'present',
        'isModified': false,
        'modifyRequested': false,
        'wageStatus': 'pending',              // ✅ 추가
        'createdAt': FieldValue.serverTimestamp(),
      };
      
      final docRef = await _firestore.collection('attendance').add(attendanceData);
      
      print('✅ 출근 체크 완료: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      print('❌ 출근 체크 실패: $e');
      rethrow;
    }
  }

  /// 퇴근 체크
  Future<bool> checkOut({
    required String attendanceId,
    required double latitude,
    required double longitude,
    String method = 'gps',
  }) async {
    try {
      print('🕐 [checkOut] 퇴근 체크 시작...');
      print('   attendanceId: $attendanceId');
      
      // 1. 출근 기록 조회
      final doc = await _firestore
          .collection('attendance')
          .doc(attendanceId)
          .get();
      
      if (!doc.exists) {
        throw Exception('출근 기록을 찾을 수 없습니다.');
      }
      
      final data = doc.data()!;
      if (data['checkOut'] != null) {
        throw Exception('이미 퇴근하셨습니다.');
      }
      
      // 2. 퇴근 시간
      final now = DateTime.now();
      final checkOutTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
      
      // 3. 근무 시간 계산
      final checkInTime = data['checkIn'] as String;
      final workHours = _calculateWorkHours(checkInTime, checkOutTime);
      
      // 4. 퇴근 기록 저장
      await _firestore.collection('attendance').doc(attendanceId).update({
        'checkOut': checkOutTime,
        'checkOutLat': latitude,
        'checkOutLng': longitude,
        'checkOutMethod': method,
        'checkOutTime': FieldValue.serverTimestamp(),
        'workHours': workHours,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      
      print('✅ 퇴근 체크 완료');
      return true;
    } catch (e) {
      print('❌ 퇴근 체크 실패: $e');
      rethrow;
    }
  }

  /// 근무 시간 계산 (시:분:초 → 시간)
  double _calculateWorkHours(String checkIn, String checkOut) {
    try {
      final inParts = checkIn.split(':');
      final outParts = checkOut.split(':');
      
      final inMinutes = int.parse(inParts[0]) * 60 + int.parse(inParts[1]);
      final outMinutes = int.parse(outParts[0]) * 60 + int.parse(outParts[1]);
      
      final diffMinutes = outMinutes - inMinutes;
      return diffMinutes / 60.0;
    } catch (e) {
      print('❌ 근무 시간 계산 실패: $e');
      return 0.0;
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
      
      final snapshot = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .where('applicationId', isEqualTo: applicationId)
          .where('workDate', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .where('workDate', isLessThan: Timestamp.fromDate(todayEnd))
          .limit(1)
          .get();
      
      if (snapshot.docs.isEmpty) {
        return null;
      }
      
      return AttendanceModel.fromFirestore(snapshot.docs.first);
    } catch (e) {
      print('❌ 오늘 출근 기록 조회 실패: $e');
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
      
      print('🔍 [getTodayAttendanceByBusiness] 조회 시작...');
      print('   businessId: $businessId');
      print('   todayStart: $todayStart');
      
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
      
      print('✅ 오늘 출근 현황: ${attendances.length}명');
      return attendances;
    } catch (e) {
      print('❌ 출근 현황 조회 실패: $e');
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
      
      print('🔍 [getTodayConfirmedWorkers] 조회 시작...');
      
      // 1. 오늘 확정된 단기 근무
      final shortTermSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .where('workDate', isEqualTo: Timestamp.fromDate(todayStart))
          .get();
      
      final shortTerm = shortTermSnapshot.docs
          .map((doc) => ApplicationModel.fromFirestore(doc))
          .toList();
      
      print('   단기 근무자: ${shortTerm.length}명');
      
      // 2. 오늘 근무하는 장기 근무자
      final longTermSnapshot = await _firestore
          .collection('applications')
          .where('businessId', isEqualTo: businessId)
          .where('status', isEqualTo: 'CONFIRMED')
          .where('type', isEqualTo: 'long_term')
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
            
            final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
            final todayWeekday = weekdays[today.weekday - 1];
            
            return app.workDays!.contains(todayWeekday);
          })
          .toList();
      
      print('   장기 근무자: ${longTerm.length}명');
      
      final allWorkers = [...shortTerm, ...longTerm];
      print('✅ 총 출근 대상: ${allWorkers.length}명');
      
      return allWorkers;
    } catch (e) {
      print('❌ 출근 대상자 조회 실패: $e');
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
      print('❌ 출근 기록 조회 실패: $e');
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
      
      print('🔍 [getMyMonthlyAttendances] $year년 $month월 출근 기록 조회');
      print('   userId: $userId');
      print('   monthStart: $monthStart');
      print('   monthEnd: $monthEnd');
      
      // 🔍 디버그: userId만으로 전체 조회
      final debugSnapshot = await _firestore
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .get();
      print('🔍 [DEBUG] userId로만 조회: ${debugSnapshot.docs.length}건');
      for (var doc in debugSnapshot.docs) {
        final data = doc.data();
        print('   📋 docId: ${doc.id}');
        print('      workDate: ${data['workDate']}');
        print('      wageStatus: ${data['wageStatus']}');
        print('      finalWage: ${data['finalWage']}');
      }
      
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
      
      print('✅ 월별 출근 기록: ${attendances.length}건');
      
      // 🔍 디버그: 각 attendance의 wageStatus, finalWage 출력
      for (var att in attendances) {
        print('   📋 ${att.workDate.toString().substring(0, 10)}: checkIn=${att.checkIn}, wageStatus=${att.wageStatus}, finalWage=${att.finalWage}');
      }
      
      return attendances;
    } catch (e, stackTrace) {
      print('❌ 월별 출근 기록 조회 실패: $e');
      print('📋 스택트레이스: $stackTrace');
      
      // 🔗 인덱스 생성 링크가 에러에 포함되어 있으면 출력
      if (e.toString().contains('index')) {
        print('⚠️ Firestore 복합 인덱스가 필요합니다!');
        print('   위 에러 메시지의 링크를 클릭하여 인덱스를 생성하세요.');
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
      print('✅ 스케줄 변경 요청 생성 완료: ${docRef.id}');
      
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
      print('❌ 스케줄 변경 요청 생성 실패: $e');
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
      print('❌ 대기중인 스케줄 변경 요청 조회 실패: $e');
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
      print('❌ 스케줄 변경 요청 조회 실패: $e');
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
      print('❌ 내 스케줄 변경 요청 조회 실패: $e');
      return [];
    }
  }

  /// 스케줄 변경 요청 승인
  Future<bool> approveScheduleChangeRequest({
    required String requestId,
    required String approverUid,
  }) async {
    try {
      // 1. 요청 정보 조회
      final requestDoc = await _firestore
          .collection('schedule_change_requests')
          .doc(requestId)
          .get();

      if (!requestDoc.exists) {
        print('❌ 요청을 찾을 수 없음');
        return false;
      }

      final request = ScheduleChangeRequestModel.fromMap(requestDoc.data()!, requestId);

      // 2. 요청 상태 업데이트
      await _firestore.collection('schedule_change_requests').doc(requestId).update({
        'status': 'APPROVED',
        'respondedByUid': approverUid,
        'respondedAt': FieldValue.serverTimestamp(),
      });

      // 3. ApplicationModel의 leaveDates 또는 extraWorkDates 업데이트
      final appSnapshot = await _firestore
          .collection('applications')
          .doc(request.applicationId)
          .get();

      if (appSnapshot.exists) {
        final appData = appSnapshot.data()!;
        
        if (request.isLeaveRequest || request.isNoWorkRequest) {
          // 휴무/미출근 → leaveDates에 추가
          List<DateTime> leaveDates = [];
          if (appData['leaveDates'] != null) {
            leaveDates = (appData['leaveDates'] as List)
                .map((e) => (e as Timestamp).toDate())
                .toList();
          }
          
          if (!leaveDates.any((d) => 
              d.year == request.targetDate.year &&
              d.month == request.targetDate.month &&
              d.day == request.targetDate.day)) {
            leaveDates.add(request.targetDate);
          }

          await _firestore.collection('applications').doc(request.applicationId).update({
            'leaveDates': leaveDates.map((e) => Timestamp.fromDate(e)).toList(),
          });
        } else if (request.isExtraWorkRequest) {
          // 추가 근무 → extraWorkDates에 추가
          List<DateTime> extraWorkDates = [];
          if (appData['extraWorkDates'] != null) {
            extraWorkDates = (appData['extraWorkDates'] as List)
                .map((e) => (e as Timestamp).toDate())
                .toList();
          }
          
          if (!extraWorkDates.any((d) => 
              d.year == request.targetDate.year &&
              d.month == request.targetDate.month &&
              d.day == request.targetDate.day)) {
            extraWorkDates.add(request.targetDate);
          }

          await _firestore.collection('applications').doc(request.applicationId).update({
            'extraWorkDates': extraWorkDates.map((e) => Timestamp.fromDate(e)).toList(),
          });
        }
      }

      print('✅ 스케줄 변경 요청 승인 완료: $requestId');
      
      // 🔔 알림 생성 (요청자에게)
      _sendScheduleChangeApprovedNotification(
        applicantUid: request.applicantUid,
        businessId: request.businessId,
        requestType: request.requestType.name,
        targetDate: request.targetDate,
        requestId: requestId,
      );
      
      return true;
    } catch (e) {
      print('❌ 스케줄 변경 요청 승인 실패: $e');
      return false;
    }
  }

  /// 스케줄 변경 요청 거절
  Future<bool> rejectScheduleChangeRequest({
    required String requestId,
    required String rejectorUid,
    String? rejectReason,
  }) async {
    try {
      // 1. 요청 정보 먼저 조회 (알림용)
      final requestDoc = await _firestore
          .collection('schedule_change_requests')
          .doc(requestId)
          .get();
      
      // 2. 상태 업데이트
      await _firestore.collection('schedule_change_requests').doc(requestId).update({
        'status': 'REJECTED',
        'respondedByUid': rejectorUid,
        'respondedAt': FieldValue.serverTimestamp(),
        'rejectReason': rejectReason,
      });

      print('✅ 스케줄 변경 요청 거절 완료: $requestId');
      
      // 🔔 알림 생성 (요청자에게)
      if (requestDoc.exists) {
        final request = ScheduleChangeRequestModel.fromMap(requestDoc.data()!, requestId);
        _sendScheduleChangeRejectedNotification(
          applicantUid: request.applicantUid,
          businessId: request.businessId,
          requestType: request.requestType.name,
          targetDate: request.targetDate,
          requestId: requestId,
          rejectReason: rejectReason,
        );
      }
      
      return true;
    } catch (e) {
      print('❌ 스케줄 변경 요청 거절 실패: $e');
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
      
      final adminUid = businessDoc.data()?['adminUid'] as String?;
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
      
      print('🔔 스케줄 변경 요청 알림 전송 완료 → 관리자: $adminUid');
    } catch (e) {
      print('⚠️ 스케줄 변경 요청 알림 전송 실패: $e');
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
        ),
      );
      
      print('🔔 스케줄 변경 승인 알림 전송 완료 → 지원자: $applicantUid');
    } catch (e) {
      print('⚠️ 스케줄 변경 승인 알림 전송 실패: $e');
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
          rejectReason: rejectReason,
        ),
      );
      
      print('🔔 스케줄 변경 거절 알림 전송 완료 → 지원자: $applicantUid');
    } catch (e) {
      print('⚠️ 스케줄 변경 거절 알림 전송 실패: $e');
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
        print('❌ 요청을 찾을 수 없음');
        return false;
      }

      final request = ScheduleChangeRequestModel.fromMap(requestDoc.data()!, requestId);

      // 2. 승인된 요청이면 ApplicationModel에서도 제거
      if (request.isApproved) {
        final appSnapshot = await _firestore
            .collection('applications')
            .doc(request.applicationId)
            .get();

        if (appSnapshot.exists) {
          final appData = appSnapshot.data()!;
          
          if (request.isLeaveRequest || request.isNoWorkRequest) {
            // leaveDates에서 제거
            List<DateTime> leaveDates = [];
            if (appData['leaveDates'] != null) {
              leaveDates = (appData['leaveDates'] as List)
                  .map((e) => (e as Timestamp).toDate())
                  .toList();
            }
            
            leaveDates.removeWhere((d) => 
                d.year == request.targetDate.year &&
                d.month == request.targetDate.month &&
                d.day == request.targetDate.day);

            await _firestore.collection('applications').doc(request.applicationId).update({
              'leaveDates': leaveDates.map((e) => Timestamp.fromDate(e)).toList(),
            });
          } else if (request.isExtraWorkRequest) {
            // extraWorkDates에서 제거
            List<DateTime> extraWorkDates = [];
            if (appData['extraWorkDates'] != null) {
              extraWorkDates = (appData['extraWorkDates'] as List)
                  .map((e) => (e as Timestamp).toDate())
                  .toList();
            }
            
            extraWorkDates.removeWhere((d) => 
                d.year == request.targetDate.year &&
                d.month == request.targetDate.month &&
                d.day == request.targetDate.day);

            await _firestore.collection('applications').doc(request.applicationId).update({
              'extraWorkDates': extraWorkDates.map((e) => Timestamp.fromDate(e)).toList(),
            });
          }
        }
      }

      // 3. 요청 상태 업데이트
      await _firestore.collection('schedule_change_requests').doc(requestId).update({
        'status': 'CANCELED',
        'respondedByUid': canceledByUid,
        'respondedAt': FieldValue.serverTimestamp(),
      });

      print('✅ 스케줄 변경 요청 취소 완료: $requestId');
      return true;
    } catch (e) {
      print('❌ 스케줄 변경 요청 취소 실패: $e');
      return false;
    }
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
      print('❌ 대기중인 요청 개수 조회 실패: $e');
      return 0;
    }
  }
}