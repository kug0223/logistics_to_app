import 'package:cloud_firestore/cloud_firestore.dart';

/// TO(근무 오더) 모델 - 하위 컬렉션 방식
/// workDetails 하위 컬렉션에 업무 상세 정보 저장
class TOModel {
  final String id; // 문서 ID
  
  // ✅ 사업장 연결
  final String businessId; // 사업장 ID
  final String businessName; // 사업장명
  
  // ✅ NEW: 제목
  final String title; // TO 제목 (예: "물류센터 파트타임알바")
  
  final DateTime date; // 근무 날짜
  final String startTime; // 시작 시간 (예: "09:00")
  final String endTime; // 종료 시간 (예: "18:00")
  
  final DateTime applicationDeadline; // 지원 마감 일시
  
  // ✅ NEW: 전체 필요 인원 (모든 업무유형 합계)
  final int totalRequired; // 전체 필요 인원
  final int totalConfirmed; // 전체 확정 인원
  
  // ❌ REMOVED: workType, requiredCount, currentCount
  // → workDetails 하위 컬렉션으로 이동
  
  final String? description; // 전체 설명
  final String creatorUID; // 생성한 관리자 UID
  final DateTime createdAt; // 생성 시각

  TOModel({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.applicationDeadline,
    required this.totalRequired,
    this.totalConfirmed = 0,
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
      title: data['title'] ?? '제목 없음',
      date: (data['date'] as Timestamp).toDate(),
      startTime: data['startTime'] ?? '',
      endTime: data['endTime'] ?? '',
      applicationDeadline: data['applicationDeadline'] != null
          ? (data['applicationDeadline'] as Timestamp).toDate()
          : DateTime(
              (data['date'] as Timestamp).toDate().year,
              (data['date'] as Timestamp).toDate().month,
              (data['date'] as Timestamp).toDate().day - 1,
              18,
              0,
            ),
      totalRequired: data['totalRequired'] ?? 0,
      totalConfirmed: data['totalConfirmed'] ?? 0,
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
      'title': title,
      'date': Timestamp.fromDate(date),
      'startTime': startTime,
      'endTime': endTime,
      'applicationDeadline': Timestamp.fromDate(applicationDeadline),
      'totalRequired': totalRequired,
      'totalConfirmed': totalConfirmed,
      'description': description,
      'creatorUID': creatorUID,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// 복사본 생성
  TOModel copyWith({
    String? id,
    String? businessId,
    String? businessName,
    String? title,
    DateTime? date,
    String? startTime,
    String? endTime,
    DateTime? applicationDeadline,
    int? totalRequired,
    int? totalConfirmed,
    String? description,
    String? creatorUID,
    DateTime? createdAt,
  }) {
    return TOModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      title: title ?? this.title,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      applicationDeadline: applicationDeadline ?? this.applicationDeadline,
      totalRequired: totalRequired ?? this.totalRequired,
      totalConfirmed: totalConfirmed ?? this.totalConfirmed,
      description: description ?? this.description,
      creatorUID: creatorUID ?? this.creatorUID,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  // ==================== 편의 메서드 ====================

  /// 포맷팅된 날짜 (예: "2025년 10월 25일")
  String get formattedDate {
    return '${date.year}년 ${date.month}월 ${date.day}일';
  }

  /// 요일 반환
  String get weekday {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return weekdays[date.weekday - 1];
  }

  /// 시간 범위 (예: "09:00 ~ 18:00")
  String get timeRange => '$startTime ~ $endTime';

  /// 마감 여부 (전체 인원 기준)
  bool get isFull => totalConfirmed >= totalRequired;

  /// 남은 인원
  int get remainingCount => totalRequired - totalConfirmed;

  /// 지원 마감 시간이 지났는지
  bool get isDeadlinePassed {
    return DateTime.now().isAfter(applicationDeadline);
  }

  /// 포맷팅된 마감 시간
  String get formattedDeadline {
    return '${applicationDeadline.month}/${applicationDeadline.day} '
        '${applicationDeadline.hour.toString().padLeft(2, '0')}:'
        '${applicationDeadline.minute.toString().padLeft(2, '0')}';
  }

  @override
  String toString() {
    return 'TOModel(id: $id, title: $title, businessName: $businessName, '
        'date: $formattedDate, totalRequired: $totalRequired, '
        'totalConfirmed: $totalConfirmed)';
  }
}