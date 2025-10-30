// ✅ lib/models/application_model.dart 전체 수정

import 'package:cloud_firestore/cloud_firestore.dart';
import '../utils/format_helper.dart';

/// 지원서 모델 - 업무유형 선택 및 변경 이력 지원
class ApplicationModel {
  final String id; // 문서 ID
  
  // ✅ 변경: toId 제거, TO 식별 정보 추가
  final String businessId; // 사업장 ID
  final String businessName; // 사업장명
  final String toTitle; // TO 제목
  final DateTime workDate; // 근무 날짜
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

  ApplicationModel({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.toTitle,
    required this.workDate,
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
  }) {
    return ApplicationModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      toTitle: toTitle ?? this.toTitle,
      workDate: workDate ?? this.workDate,
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
    );
  }

  @override
  String toString() {
    return 'ApplicationModel(id: $id, businessId: $businessId, toTitle: $toTitle, '
        'workDate: $workDate, uid: $uid, selectedWorkType: $selectedWorkType, '
        'wage: $wage, status: $status, isChanged: $isWorkTypeChanged)';
  }
}