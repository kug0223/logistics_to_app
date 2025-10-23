import 'package:cloud_firestore/cloud_firestore.dart';

/// TO(근무 오더) 모델 - 사업장 기반 + 마감 시간 추가 버전
class TOModel {
  final String id; // 문서 ID
  
  // ✅ 사업장 연결
  final String businessId; // 사업장 ID
  final String businessName; // 사업장명
  
  // ⚠️ 하위 호환성을 위해 유지 (deprecated)
  final String? centerId;
  final String? centerName;
  
  final DateTime date; // 근무 날짜
  final String startTime; // 시작 시간 (예: "09:00")
  final String endTime; // 종료 시간 (예: "18:00")
  
  // ✅ NEW! Phase 1 추가 필드
  final DateTime applicationDeadline; // 지원 마감 일시
  
  final int requiredCount; // 필요 인원
  final int currentCount; // 현재 지원 인원
  final String workType; // 업무 유형
  final String? description; // 설명
  final String creatorUID; // 생성한 관리자 UID
  final DateTime createdAt; // 생성 시각

  TOModel({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.applicationDeadline, // ✅ 필수 필드로 추가!
    required this.requiredCount,
    required this.currentCount,
    required this.workType,
    this.description,
    required this.creatorUID,
    required this.createdAt,
  });

  /// Firestore 문서를 TOModel로 변환
  factory TOModel.fromMap(Map<String, dynamic> data, String documentId) {
    return TOModel(
      id: documentId,
      businessId: data['businessId'] ?? '',
      businessName: data['businessName'] ?? '',
      date: (data['date'] as Timestamp).toDate(),
      startTime: data['startTime'] ?? '',
      endTime: data['endTime'] ?? '',
      // ✅ NEW! 마감 일시 파싱 (없으면 근무 날짜 전날 18:00으로 기본값)
      applicationDeadline: data['applicationDeadline'] != null
          ? (data['applicationDeadline'] as Timestamp).toDate()
          : DateTime(
              (data['date'] as Timestamp).toDate().year,
              (data['date'] as Timestamp).toDate().month,
              (data['date'] as Timestamp).toDate().day - 1,
              18,
              0,
            ),
      requiredCount: data['requiredCount'] ?? 0,
      currentCount: data['currentCount'] ?? 0,
      workType: data['workType'] ?? '',
      description: data['description'],
      creatorUID: data['creatorUID'] ?? '',
      createdAt: data['createdAt'] != null 
          ? (data['createdAt'] as Timestamp).toDate() 
          : DateTime.now(),
    );
  }

  /// TOModel을 Firestore 문서로 변환
  Map<String, dynamic> toMap() {
    return {
      'businessId': businessId,
      'businessName': businessName,
      'centerId': centerId,
      'centerName': centerName,
      'date': Timestamp.fromDate(date),
      'startTime': startTime,
      'endTime': endTime,
      'applicationDeadline': Timestamp.fromDate(applicationDeadline), // ✅ NEW!
      'requiredCount': requiredCount,
      'currentCount': currentCount,
      'workType': workType,
      'description': description,
      'creatorUID': creatorUID,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  // ✅ NEW! 마감 여부 Getter
  /// 지원 마감이 지났는지 확인
  bool get isDeadlinePassed {
    return DateTime.now().isAfter(applicationDeadline);
  }

  // ✅ NEW! 마감까지 남은 시간 표시
  /// 마감까지 남은 시간 표시 (예: "3시간 남음", "마감됨")
  String get deadlineStatus {
    if (isDeadlinePassed) {
      return '마감됨';
    }

    final now = DateTime.now();
    final difference = applicationDeadline.difference(now);

    if (difference.inDays > 0) {
      return '${difference.inDays}일 남음';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}시간 남음';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}분 남음';
    } else {
      return '곧 마감';
    }
  }

  // ✅ NEW! 마감 일시 포맷팅
  /// 마감 일시 표시 (예: "10월 24일 18:00까지")
  String get formattedDeadline {
    return '${applicationDeadline.month}월 ${applicationDeadline.day}일 '
        '${applicationDeadline.hour.toString().padLeft(2, '0')}:'
        '${applicationDeadline.minute.toString().padLeft(2, '0')}까지';
  }

  /// 남은 인원 계산
  int get remainingCount => requiredCount - currentCount;

  /// 지원 가능 여부 (인원 + 마감 시간 체크)
  bool get isAvailable => currentCount < requiredCount && !isDeadlinePassed;

  /// 날짜 포맷팅 (예: "2025년 10월 21일")
  String get formattedDate {
    return '${date.year}년 ${date.month}월 ${date.day}일';
  }

  /// 요일 반환 (예: "화요일")
  String get weekday {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${weekdays[date.weekday - 1]}요일';
  }

  /// 시간대 표시 (예: "09:00 - 18:00")
  String get timeRange => '$startTime - $endTime';

  /// 복사본 생성 (일부 필드만 변경)
  TOModel copyWith({
    String? id,
    String? businessId,
    String? businessName,
    String? centerId,
    String? centerName,
    DateTime? date,
    String? startTime,
    String? endTime,
    DateTime? applicationDeadline,
    int? requiredCount,
    int? currentCount,
    String? workType,
    String? description,
    String? creatorUID,
    DateTime? createdAt,
  }) {
    return TOModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      applicationDeadline: applicationDeadline ?? this.applicationDeadline,
      requiredCount: requiredCount ?? this.requiredCount,
      currentCount: currentCount ?? this.currentCount,
      workType: workType ?? this.workType,
      description: description ?? this.description,
      creatorUID: creatorUID ?? this.creatorUID,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}