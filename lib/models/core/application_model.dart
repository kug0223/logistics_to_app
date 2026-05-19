// ✅ lib/models/application_model.dart 전체 수정

import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/format_helper.dart';

/// 지원서 모델 - 업무유형 선택 및 변경 이력 지원
class ApplicationModel {
  final String id; // 문서 ID
  
  // ✅ 변경: toId 제거, TO 식별 정보 추가
  final String businessId; // 사업장 ID
  final String businessName; // 사업장명
  final String toTitle; // TO 제목
  final DateTime workDate; // 근무 날짜
  final DateTime? workEndDate;       // ⭐ 종료일 (장기용)
  final List<String>? workDays;      // ⭐ 근무 요일 (장기용)
  final String startTime; // 근무 시작 시간
  final String endTime; // 근무 종료 시간
 
  final String uid; // 지원자 UID
  
  // 업무 유형 및 금액
  final String selectedWorkType; // 현재 지원한 업무 유형 (예: "피킹")
  final String? workDetailId;  // ✅ 추가: WorkDetail 고유 ID
  final String? toId;          // ✅ TO 고유 ID
  final String? slotId;        // ✅ 슬롯 ID (flex 타입 공고의 특정 날짜 슬롯)
  final String? groupId;       // Deprecated — 하위 호환용, 신규 공고는 미사용
  final int wage; // 지원 시점의 금액 (업무유형 변경 시 함께 업데이트)
  // 🔥 업무 상세 정보 (UI 표시용)
  final String? wageType;              // 급여 타입 (hourly, daily)
  final String? workTypeIcon;          // 업무 아이콘
  final String? workTypeColor;         // 업무 색상
  final String? workTypeBackgroundColor; // 업무 배경색
  
  // 업무 변경 이력
  final String? originalWorkType; // 최초 지원한 업무 유형 (변경 시에만 값 존재)
  final int? originalWage; // 최초 지원 시 금액
  final DateTime? changedAt; // 업무유형 변경 시각
  final String? changedBy; // 업무유형 변경한 관리자 UID
  
  final String status; // PENDING, CONFIRMED, REJECTED, CANCELED
  final DateTime appliedAt; // 지원 시각
  final DateTime? confirmedAt; // 확정 시각 (null 가능)
  final String? confirmedBy; // 확정한 사람 (SYSTEM 또는 관리자 UID)
  // ⭐ Phase 2: 자동 취소 관련 필드
  final DateTime? canceledAt;           // 취소 시각
  final String? cancelReason;           // 'SCHEDULE_CONFLICT', 'USER_CANCELED'
  final String? conflictingAppId;       // 충돌된 지원서 ID
  final String? conflictingBusiness;    // 충돌된 사업장명
  final String? conflictingTime;        // 충돌 시간대 "09:00~18:00"
  
  // ⭐ Phase 2: 메시지 시스템
  final String? applicationMessage;     // 지원 시 지원자 메시지
  final String? confirmMessage;         // 확정 시 관리자 메시지
  final String? rejectMessage;          // 거절 시 관리자 메시지
  final String? cancelMessage;          // 취소 시 관리자 메시지

  // 🔥 Phase A: 퇴사 관리 시스템
  final DateTime? resignRequestedAt;    // 퇴사 요청 시각
  final DateTime? resignRequestDate;    // 퇴사 희망일
  // ⭐ 장기공고 희망 시작일
  final DateTime? desiredStartDate;
  // 🔥 Phase B: 스케줄 변경 관리
  final List<DateTime>? leaveDates;      // 승인된 휴무 날짜들
  final List<DateTime>? extraWorkDates;  // 승인된 추가 근무 날짜들
  // 🔥 상태 변경 이력
  final List<Map<String, dynamic>>? statusHistory;
  final String? resignStatus;           // 'PENDING', 'APPROVED', 'REJECTED', 'AUTO_APPROVED'
  final DateTime? resignApprovedAt;     // 승인/거절 시각
  final String? resignApprovedBy;       // 승인/거절자 UID
  final String? resignRejectReason;     // 거절 사유
  final DateTime? actualResignDate;     // 실제 퇴사일 (승인된 날짜)
  // 🔥 Phase C: 계약해지 관리 (관리자 → 근무자)
  final String? terminationStatus;          // 'PENDING', 'APPROVED', 'REJECTED', 'AUTO_APPROVED'
  final DateTime? terminationRequestedAt;   // 해지 요청 시각
  final String? terminationReason;          // 해지 사유
  final String? terminationRequestedByUid;  // 요청한 관리자 UID
  final DateTime? terminationRespondedAt;   // 근무자 응답 시각
  final String? terminationRejectReason;    // 근무자 거절 사유

  ApplicationModel({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.toTitle,
    required this.workDate,
    this.workEndDate,      // ⭐ 추가
    this.workDays,         // ⭐ 추가
    required this.startTime,
    required this.endTime,
    required this.uid,
    required this.selectedWorkType,
    this.workDetailId,
    this.toId,
    this.slotId,
    this.groupId,
    required this.wage,
    // 🔥 업무 상세 정보
    this.wageType,
    this.workTypeIcon,
    this.workTypeColor,
    this.workTypeBackgroundColor,
    this.originalWorkType,
    this.originalWage,
    this.changedAt,
    this.changedBy,
    required this.status,
    required this.appliedAt,
    this.confirmedAt,
    this.confirmedBy,
    // ⭐ Phase 2: 추가
    this.canceledAt,
    this.cancelReason,
    this.conflictingAppId,
    this.conflictingBusiness,
    this.conflictingTime,
    this.applicationMessage,
    this.confirmMessage,
    this.rejectMessage,
    this.cancelMessage,
    // 🔥 Phase A: 퇴사 관리
    this.resignRequestedAt,
    this.resignRequestDate,
    this.resignStatus,
    this.resignApprovedAt,
    this.resignApprovedBy,
    this.resignRejectReason,
    this.actualResignDate,
    // 🔥 Phase C: 계약해지 관리
    this.terminationStatus,
    this.terminationRequestedAt,
    this.terminationReason,
    this.terminationRequestedByUid,
    this.terminationRespondedAt,
    this.terminationRejectReason,
    // ⭐ 장기공고 희망 시작일
    this.desiredStartDate,
    // ⭐ 여기에 추가
    this.leaveDates,
    this.extraWorkDates,
    // 🔥 상태 변경 이력
    this.statusHistory,
    
  });

  /// Firestore 문서를 ApplicationModel로 변환
  factory ApplicationModel.fromMap(Map<String, dynamic> data, String documentId) {
    return ApplicationModel(
      id: documentId,
      businessId: data['businessId'] ?? '',
      businessName: data['businessName'] ?? '',
      toTitle: data['toTitle'] ?? '',
      workDate: data['workDate'] != null
          ? (data['workDate'] as Timestamp).toDate()
          : DateTime.now(),
      workEndDate: data['workEndDate'] != null
          ? (data['workEndDate'] as Timestamp).toDate()
          : null,  // ⭐
      workDays: data['workDays'] != null
          ? List<String>.from(data['workDays'])
          : null,  // ⭐
      startTime: data['startTime'] ?? '',
      endTime: data['endTime'] ?? '',
      uid: data['uid'] ?? '',
      selectedWorkType: data['selectedWorkType'] ?? '',
      workDetailId: data['workDetailId'],
      toId: data['toId'],
      slotId: data['slotId'],
      groupId: data['groupId'],
      wage: data['wage'] ?? 0,
      // 🔥 업무 상세 정보
      wageType: data['wageType'],
      workTypeIcon: data['workTypeIcon'],
      workTypeColor: data['workTypeColor'],
      workTypeBackgroundColor: data['workTypeBackgroundColor'],
      originalWorkType: data['originalWorkType'],
      originalWage: data['originalWage'],
      changedAt: data['changedAt'] != null
          ? (data['changedAt'] as Timestamp).toDate().toLocal()  // 🔥 .toLocal() 추가
          : null,
      changedBy: data['changedBy'],
      status: data['status'] ?? 'PENDING',
      appliedAt: data['appliedAt'] != null
          ? (data['appliedAt'] as Timestamp).toDate().toLocal()  // 🔥 .toLocal() 추가
          : DateTime.now(),
      confirmedAt: data['confirmedAt'] != null
          ? (data['confirmedAt'] as Timestamp).toDate().toLocal()  // 🔥 .toLocal() 추가
          : null,
      confirmedBy: data['confirmedBy'],
      // ⭐ Phase 2: 추가
      canceledAt: data['canceledAt'] != null
          ? (data['canceledAt'] as Timestamp).toDate().toLocal()  // 🔥 .toLocal() 추가
          : null,
      cancelReason: data['cancelReason'],
      conflictingAppId: data['conflictingAppId'],
      conflictingBusiness: data['conflictingBusiness'],
      conflictingTime: data['conflictingTime'],
      applicationMessage: data['applicationMessage'],
      confirmMessage: data['confirmMessage'],
      rejectMessage: data['rejectMessage'],
      cancelMessage: data['cancelMessage'],
      // 🔥 Phase A: 퇴사 관리
      resignRequestedAt: data['resignRequestedAt'] != null
          ? (data['resignRequestedAt'] as Timestamp).toDate().toLocal()  // 🔥 .toLocal() 추가
          : null,
      resignRequestDate: data['resignRequestDate'] != null
          ? (data['resignRequestDate'] as Timestamp).toDate()
          : null,
      resignStatus: data['resignStatus'],
      resignApprovedAt: data['resignApprovedAt'] != null
          ? (data['resignApprovedAt'] as Timestamp).toDate().toLocal()  // 🔥 .toLocal() 추가
          : null,
      resignApprovedBy: data['resignApprovedBy'],
      resignRejectReason: data['resignRejectReason'],
      actualResignDate: data['actualResignDate'] != null
          ? (data['actualResignDate'] as Timestamp).toDate()
          : null,
      // 🔥 Phase C: 계약해지 관리
      terminationStatus: data['terminationStatus'],
      terminationRequestedAt: data['terminationRequestedAt'] != null
          ? (data['terminationRequestedAt'] as Timestamp).toDate().toLocal()  // 🔥 .toLocal() 추가
          : null,
      terminationReason: data['terminationReason'],
      terminationRequestedByUid: data['terminationRequestedByUid'],
      terminationRespondedAt: data['terminationRespondedAt'] != null
          ? (data['terminationRespondedAt'] as Timestamp).toDate().toLocal()  // 🔥 .toLocal() 추가
          : null,
      terminationRejectReason: data['terminationRejectReason'],
      // ⭐ 장기공고 희망 시작일
      desiredStartDate: data['desiredStartDate'] != null
          ? (data['desiredStartDate'] as Timestamp).toDate()
          : null,
      // ⭐ 여기에 추가
      leaveDates: data['leaveDates'] != null
          ? (data['leaveDates'] as List)
              .map((e) => (e as Timestamp).toDate())
              .toList()
          : null,
      extraWorkDates: data['extraWorkDates'] != null
          ? (data['extraWorkDates'] as List)
              .map((e) => (e as Timestamp).toDate())
              .toList()
          : null,
          // 🔥 상태 변경 이력
      statusHistory: data['statusHistory'] != null
          ? (data['statusHistory'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : null,
    );
  }
  
  /// Firestore DocumentSnapshot에서 변환
  factory ApplicationModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ApplicationModel.fromMap(data, doc.id);
  }
  
  /// ApplicationModel을 Firestore 문서로 변환
  Map<String, dynamic> toMap() {
    return {
      'businessId': businessId,
      'businessName': businessName,
      'toTitle': toTitle,
      'workDate': Timestamp.fromDate(workDate),
      'workEndDate': workEndDate != null ? Timestamp.fromDate(workEndDate!) : null,  // ⭐
      'workDays': workDays,  // ⭐
      'desiredStartDate': desiredStartDate != null ? Timestamp.fromDate(desiredStartDate!) : null,  // ⭐ 희망 시작일
      'startTime': startTime,
      'endTime': endTime,
      'uid': uid,
      'selectedWorkType': selectedWorkType,
      'workDetailId': workDetailId,
      'toId': toId,
      'slotId': slotId,
      'groupId': groupId,
      'wage': wage,
      // 🔥 업무 상세 정보
      'wageType': wageType,
      'workTypeIcon': workTypeIcon,
      'workTypeColor': workTypeColor,
      'workTypeBackgroundColor': workTypeBackgroundColor,
      'originalWorkType': originalWorkType,
      'originalWage': originalWage,
      'changedAt': changedAt != null ? Timestamp.fromDate(changedAt!) : null,
      'changedBy': changedBy,
      'status': status,
      'appliedAt': Timestamp.fromDate(appliedAt),
      'confirmedAt': confirmedAt != null ? Timestamp.fromDate(confirmedAt!) : null,
      'confirmedBy': confirmedBy,
      // ⭐ Phase 2: 추가
      'canceledAt': canceledAt != null ? Timestamp.fromDate(canceledAt!) : null,
      'cancelReason': cancelReason,
      'conflictingAppId': conflictingAppId,
      'conflictingBusiness': conflictingBusiness,
      'conflictingTime': conflictingTime,
      'applicationMessage': applicationMessage,
      'confirmMessage': confirmMessage,
      'rejectMessage': rejectMessage,
      'cancelMessage': cancelMessage,
      // 🔥 Phase A: 퇴사 관리
      'resignRequestedAt': resignRequestedAt != null ? Timestamp.fromDate(resignRequestedAt!) : null,
      'resignRequestDate': resignRequestDate != null ? Timestamp.fromDate(resignRequestDate!) : null,
      'resignStatus': resignStatus,
      'resignApprovedAt': resignApprovedAt != null ? Timestamp.fromDate(resignApprovedAt!) : null,
      'resignApprovedBy': resignApprovedBy,
      'resignRejectReason': resignRejectReason,
      'actualResignDate': actualResignDate != null ? Timestamp.fromDate(actualResignDate!) : null,
      // 🔥 Phase C: 계약해지 관리
      'terminationStatus': terminationStatus,
      'terminationRequestedAt': terminationRequestedAt != null ? Timestamp.fromDate(terminationRequestedAt!) : null,
      'terminationReason': terminationReason,
      'terminationRequestedByUid': terminationRequestedByUid,
      'terminationRespondedAt': terminationRespondedAt != null ? Timestamp.fromDate(terminationRespondedAt!) : null,
      'terminationRejectReason': terminationRejectReason,
      
      // ⭐ 여기에 추가
      'leaveDates': leaveDates?.map((e) => Timestamp.fromDate(e)).toList(),
      'extraWorkDates': extraWorkDates?.map((e) => Timestamp.fromDate(e)).toList(),
      // 🔥 상태 변경 이력 (Timestamp 변환)
      'statusHistory': statusHistory,
    };
  }

  /// 상태 한글 표시
  String get statusText {
    switch (status) {
      case 'PENDING':
        return '대기 중';
      case 'CONFIRMED':
        return '확정';
      case 'REJECTED':
        return '거절';
      case 'CANCELED':
        return '취소됨';
      case 'AUTO_CANCELED':  // ⭐ 추가
        return '자동 취소됨';
      default:
        return '알 수 없음';
    }
  }

  /// 상태별 색상
  int get statusColor {
    switch (status) {
      case 'PENDING':
        return 0xFFF59E0B; // 주황색
      case 'CONFIRMED':
        return 0xFF10B981; // 초록색
      case 'REJECTED':
        return 0xFFEF4444; // 빨간색
      case 'CANCELED':
        return 0xFF6B7280; // 회색
      case 'AUTO_CANCELED':  // ⭐ 추가
        return 0xFFEF4444; // 빨간색
      default:
        return 0xFF9CA3AF; // 기본 회색
    }
  }

  /// 업무유형이 변경되었는지 여부
  bool get isWorkTypeChanged => originalWorkType != null;
  
   /// 포맷팅된 금액 (예: "50,000원")
  String get formattedWage {
    return FormatHelper.formatWage(wage);
  }
  
  /// 🔥 급여 타입 라벨 (예: "시급")
  String get wageTypeLabel {
    if (wageType == null) return '';
    return FormatHelper.getWageTypeLabel(wageType!);
  }

  /// 복사본 생성
  ApplicationModel copyWith({
    String? id,
    String? businessId,
    String? businessName,
    String? toTitle,
    DateTime? workDate,
    DateTime? workEndDate,     // ⭐
    List<String>? workDays,    // ⭐
    String? startTime,
    String? endTime,
    String? uid,
    String? selectedWorkType,
    String? toId,
    String? slotId,
    String? groupId,
    int? wage,
    // 🔥 업무 상세 정보
    String? wageType,
    String? workTypeIcon,
    String? workTypeColor,
    String? workTypeBackgroundColor,
    String? originalWorkType,
    int? originalWage,
    DateTime? changedAt,
    String? changedBy,
    String? status,
    DateTime? appliedAt,
    DateTime? confirmedAt,
    String? confirmedBy,
    // ⭐ Phase 2: 추가
    DateTime? canceledAt,
    String? cancelReason,
    String? conflictingAppId,
    String? conflictingBusiness,
    String? conflictingTime,
    String? applicationMessage,
    String? confirmMessage,
    String? rejectMessage,
    String? cancelMessage,
    // 🔥 Phase A: 퇴사 관리
    DateTime? resignRequestedAt,
    DateTime? resignRequestDate,
    String? resignStatus,
    DateTime? resignApprovedAt,
    String? resignApprovedBy,
    String? resignRejectReason,
    DateTime? actualResignDate,
    // 🔥 Phase C: 계약해지 관리
    String? terminationStatus,
    DateTime? terminationRequestedAt,
    String? terminationReason,
    String? terminationRequestedByUid,
    DateTime? terminationRespondedAt,
    String? terminationRejectReason,
    DateTime? desiredStartDate,
    List<DateTime>? leaveDates,
    List<DateTime>? extraWorkDates,
    // 🔥 상태 변경 이력
    List<Map<String, dynamic>>? statusHistory,
    
  }) {
    return ApplicationModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      toTitle: toTitle ?? this.toTitle,
      workDate: workDate ?? this.workDate,
      workEndDate: workEndDate ?? this.workEndDate,     // ⭐
      workDays: workDays ?? this.workDays,               // ⭐
      desiredStartDate: desiredStartDate ?? this.desiredStartDate,  // ⭐ 희망 시작일        // ⭐
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      uid: uid ?? this.uid,
      selectedWorkType: selectedWorkType ?? this.selectedWorkType,
      toId: toId ?? this.toId,          // ✅ 추가
      slotId: slotId ?? this.slotId,
      groupId: groupId ?? this.groupId,
      wage: wage ?? this.wage,
      // 🔥 업무 상세 정보
      wageType: wageType ?? this.wageType,
      workTypeIcon: workTypeIcon ?? this.workTypeIcon,
      workTypeColor: workTypeColor ?? this.workTypeColor,
      workTypeBackgroundColor: workTypeBackgroundColor ?? this.workTypeBackgroundColor,
      originalWorkType: originalWorkType ?? this.originalWorkType,
      originalWage: originalWage ?? this.originalWage,
      changedAt: changedAt ?? this.changedAt,
      changedBy: changedBy ?? this.changedBy,
      status: status ?? this.status,
      appliedAt: appliedAt ?? this.appliedAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      confirmedBy: confirmedBy ?? this.confirmedBy,
      // ⭐ Phase 2: 추가
      canceledAt: canceledAt ?? this.canceledAt,
      cancelReason: cancelReason ?? this.cancelReason,
      conflictingAppId: conflictingAppId ?? this.conflictingAppId,
      conflictingBusiness: conflictingBusiness ?? this.conflictingBusiness,
      conflictingTime: conflictingTime ?? this.conflictingTime,
      applicationMessage: applicationMessage ?? this.applicationMessage,
      confirmMessage: confirmMessage ?? this.confirmMessage,
      rejectMessage: rejectMessage ?? this.rejectMessage,
      cancelMessage: cancelMessage ?? this.cancelMessage,
      // 🔥 Phase A: 퇴사 관리
      resignRequestedAt: resignRequestedAt ?? this.resignRequestedAt,
      resignRequestDate: resignRequestDate ?? this.resignRequestDate,
      resignStatus: resignStatus ?? this.resignStatus,
      resignApprovedAt: resignApprovedAt ?? this.resignApprovedAt,
      resignApprovedBy: resignApprovedBy ?? this.resignApprovedBy,
      resignRejectReason: resignRejectReason ?? this.resignRejectReason,
      actualResignDate: actualResignDate ?? this.actualResignDate,
      // 🔥 Phase C: 계약해지 관리
      terminationStatus: terminationStatus ?? this.terminationStatus,
      terminationRequestedAt: terminationRequestedAt ?? this.terminationRequestedAt,
      terminationReason: terminationReason ?? this.terminationReason,
      terminationRequestedByUid: terminationRequestedByUid ?? this.terminationRequestedByUid,
      terminationRespondedAt: terminationRespondedAt ?? this.terminationRespondedAt,
      terminationRejectReason: terminationRejectReason ?? this.terminationRejectReason,
      leaveDates: leaveDates ?? this.leaveDates,
      extraWorkDates: extraWorkDates ?? this.extraWorkDates,
      // 🔥 상태 변경 이력
      statusHistory: statusHistory ?? this.statusHistory,
    );
  }

  @override
  String toString() {
    return 'ApplicationModel(id: $id, businessId: $businessId, toTitle: $toTitle, '
        'workDate: $workDate, uid: $uid, selectedWorkType: $selectedWorkType, '
        'wage: $wage, status: $status, isChanged: $isWorkTypeChanged)';
  }
  // ⭐ Phase 1-B: 장기 공고 표시용 헬퍼
  
  /// 장기 지원인지 확인
  /// ✅ workDays가 있어야만 장기 (workEndDate는 단기에도 있을 수 있음)
  bool get isLongTermApplication {
    // workDays가 있으면 확실히 장기
    return workDays != null && workDays!.isNotEmpty;
  }
  
  /// 근무 기간 표시 (예: "11/1~11/30")
  /// 🔥 희망 시작일/퇴사일 우선 적용
  String get workPeriodDisplay {
    final effectiveEnd = actualResignDate ?? workEndDate;
    if (effectiveEnd == null) return '';
    
    final effectiveStart = desiredStartDate ?? workDate;
    final startStr = '${effectiveStart.month}/${effectiveStart.day}';
    final endStr = '${effectiveEnd.month}/${effectiveEnd.day}';
    return '$startStr~$endStr';
  }
  
  /// 근무 요일 표시 (예: "주 5일 (월~금)" 또는 "주 3일 (월,수,금)")
  String? get workDaysDisplay {
    if (workDays == null || workDays!.isEmpty) return null;
    
    final count = workDays!.length;
    final daysStr = workDays!.join(',');
    
    // 연속된 요일인지 확인 (월~금)
    final weekDays = ['월', '화', '수', '목', '금', '토', '일'];
    final indices = workDays!.map((day) => weekDays.indexOf(day)).toList()..sort();
    
    bool isContinuous = true;
    for (int i = 1; i < indices.length; i++) {
      if (indices[i] != indices[i - 1] + 1) {
        isContinuous = false;
        break;
      }
    }
    
    if (isContinuous && count > 1) {
      return '주 $count일 (${workDays!.first}~${workDays!.last})';
    } else {
      return '주 $count일 ($daysStr)';
    }
  }
  // ⭐ 특정 날짜가 휴무일인지 확인
  bool isLeaveDateOn(DateTime date) {
    if (leaveDates == null || leaveDates!.isEmpty) return false;
    return leaveDates!.any((d) => _isSameDay(d, date));
  }

  // ⭐ 특정 날짜가 추가 근무일인지 확인
  bool isExtraWorkDateOn(DateTime date) {
    if (extraWorkDates == null || extraWorkDates!.isEmpty) return false;
    return extraWorkDates!.any((d) => _isSameDay(d, date));
  }

  // ─────────────────────────────────────────────────────────
  // 스케줄 판단 (단일 진실의 원천)
  // ─────────────────────────────────────────────────────────

  /// 충돌 판단용: 해당 날짜에 이 지원이 근무 중인지 확인
  /// - 휴무일(leaveDates) → false (근무 없음)
  /// - 추가 근무일(extraWorkDates) → true (요일 무관)
  bool isWorkingOnDate(DateTime targetDate) {
    if (!isLongTermApplication) {
      return _isSameDay(workDate, targetDate);
    }

    final endDate = actualResignDate ?? workEndDate;
    if (endDate == null) return false;

    DateTime effectiveStart = desiredStartDate ?? workDate;
    if (confirmedAt != null && desiredStartDate == null) {
      final confirmedDay = DateTime(confirmedAt!.year, confirmedAt!.month, confirmedAt!.day);
      if (confirmedDay.isAfter(workDate)) effectiveStart = confirmedDay;
    }

    final targetOnly = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final startOnly = DateTime(effectiveStart.year, effectiveStart.month, effectiveStart.day);
    final endOnly = DateTime(endDate.year, endDate.month, endDate.day);

    if (targetOnly.isBefore(startOnly) || targetOnly.isAfter(endOnly)) return false;

    if (isExtraWorkDateOn(targetOnly)) return true;
    if (isLeaveDateOn(targetOnly)) return false;

    return workDays!.contains(FormatHelper.weekday(targetDate));
  }

  /// 캘린더 표시용: 해당 날짜에 이 지원이 일정으로 표시되어야 하는지 확인
  /// - 미확정 장기공고 → 지원일에만 표시
  /// - 퇴사/계약해지 완료 → false
  /// - 휴무일도 true (캘린더에 휴무 상태로 표시)
  bool isScheduledOnDate(DateTime targetDate) {
    if (!isLongTermApplication) {
      return _isSameDay(workDate, targetDate);
    }

    if (status != AppStatus.confirmed) {
      return _isSameDay(workDate, targetDate);
    }

    if (resignStatus == AppStatus.approved || resignStatus == AppStatus.autoApproved ||
        terminationStatus == AppStatus.approved || terminationStatus == AppStatus.autoApproved) {
      return false;
    }

    final endDate = actualResignDate ?? workEndDate;
    if (endDate == null) return false;

    DateTime effectiveStart = desiredStartDate ?? workDate;
    if (confirmedAt != null && desiredStartDate == null) {
      final confirmedDay = DateTime(confirmedAt!.year, confirmedAt!.month, confirmedAt!.day);
      if (confirmedDay.isAfter(workDate)) effectiveStart = confirmedDay;
    }

    final targetOnly = DateTime(targetDate.year, targetDate.month, targetDate.day);
    final startOnly = DateTime(effectiveStart.year, effectiveStart.month, effectiveStart.day);
    final endOnly = DateTime(endDate.year, endDate.month, endDate.day);

    if (targetOnly.isBefore(startOnly) || targetOnly.isAfter(endOnly)) return false;

    if (isExtraWorkDateOn(targetOnly)) return true;
    if (isLeaveDateOn(targetOnly)) return true; // 휴무일도 캘린더에 표시

    return workDays!.contains(FormatHelper.weekday(targetDate));
  }

  /// 시간대 겹침 여부 (충돌 판단용 정적 유틸)
  static bool hasTimeOverlap(String s1, String e1, String s2, String e2) {
    if (s1.isEmpty || e1.isEmpty || s2.isEmpty || e2.isEmpty) return false;
    int toMin(String t) {
      final p = t.split(':');
      if (p.length < 2) return 0;
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }
    return !(toMin(e1) <= toMin(s2) || toMin(e2) <= toMin(s1));
  }

  static bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

/// 지원서 Firestore 상태 상수 (대문자 — applications 컬렉션 convention)
abstract class AppStatus {
  static const String pending     = 'PENDING';
  static const String confirmed   = 'CONFIRMED';
  static const String rejected    = 'REJECTED';
  static const String canceled    = 'CANCELED';
  static const String autoCanceled = 'AUTO_CANCELED';

  /// 퇴사·계약해지 하위 상태 (resignStatus / terminationStatus 필드용)
  static const String approved    = 'APPROVED';
  static const String autoApproved = 'AUTO_APPROVED';

  /// 활성 상태 그룹
  static const List<String> activeStates   = [pending, confirmed];
  /// 비활성 상태 그룹
  static const List<String> inactiveStates = [rejected, canceled, autoCanceled];
}