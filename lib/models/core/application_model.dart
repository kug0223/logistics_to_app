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
  final int wage; // 지원 시점의 금액 (업무유형 변경 시 함께 업데이트)
  
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
  final String? resignStatus;           // 'PENDING', 'APPROVED', 'REJECTED', 'AUTO_APPROVED'
  final DateTime? resignApprovedAt;     // 승인/거절 시각
  final String? resignApprovedBy;       // 승인/거절자 UID
  final String? resignRejectReason;     // 거절 사유
  final DateTime? actualResignDate;     // 실제 퇴사일 (승인된 날짜)

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
    required this.wage,
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
      wage: data['wage'] ?? 0,
      originalWorkType: data['originalWorkType'],
      originalWage: data['originalWage'],
      changedAt: data['changedAt'] != null
          ? (data['changedAt'] as Timestamp).toDate()
          : null,
      changedBy: data['changedBy'],
      status: data['status'] ?? 'PENDING',
      appliedAt: data['appliedAt'] != null
          ? (data['appliedAt'] as Timestamp).toDate()
          : DateTime.now(),
      confirmedAt: data['confirmedAt'] != null
          ? (data['confirmedAt'] as Timestamp).toDate()
          : null,
      confirmedBy: data['confirmedBy'],
      // ⭐ Phase 2: 추가
      canceledAt: data['canceledAt'] != null
          ? (data['canceledAt'] as Timestamp).toDate()
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
          ? (data['resignRequestedAt'] as Timestamp).toDate()
          : null,
      resignRequestDate: data['resignRequestDate'] != null
          ? (data['resignRequestDate'] as Timestamp).toDate()
          : null,
      resignStatus: data['resignStatus'],
      resignApprovedAt: data['resignApprovedAt'] != null
          ? (data['resignApprovedAt'] as Timestamp).toDate()
          : null,
      resignApprovedBy: data['resignApprovedBy'],
      resignRejectReason: data['resignRejectReason'],
      actualResignDate: data['actualResignDate'] != null
          ? (data['actualResignDate'] as Timestamp).toDate()
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
      'startTime': startTime,
      'endTime': endTime,
      'uid': uid,
      'selectedWorkType': selectedWorkType,
      'wage': wage,
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
    int? wage,
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
    
    
  }) {
    return ApplicationModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      toTitle: toTitle ?? this.toTitle,
      workDate: workDate ?? this.workDate,
      workEndDate: workEndDate ?? this.workEndDate,     // ⭐
      workDays: workDays ?? this.workDays,               // ⭐
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      uid: uid ?? this.uid,
      selectedWorkType: selectedWorkType ?? this.selectedWorkType,
      wage: wage ?? this.wage,
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
  bool get isLongTermApplication {
    return workEndDate != null || (workDays != null && workDays!.isNotEmpty);
  }
  
  /// 근무 기간 표시 (예: "11/1~11/30")
  String get workPeriodDisplay {
    if (workEndDate == null) return '';
    
    final startStr = '${workDate.month}/${workDate.day}';
    final endStr = '${workEndDate!.month}/${workEndDate!.day}';
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
}