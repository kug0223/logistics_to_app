import 'package:cloud_firestore/cloud_firestore.dart';

/// TO(근무 오더) 모델 - 사업장 기반 버전
class TOModel {
  final String id; // 문서 ID
  
  // ✅ 사업장 연결 (신규)
  final String businessId; // 사업장 ID (businesses 컬렉션 문서 ID)
  final String businessName; // 사업장명
  
  // ⚠️ 하위 호환성을 위해 유지 (deprecated, 삭제 예정)
  final String? centerId; // CENTER_A, CENTER_B, CENTER_C
  final String? centerName; // 송파 물류센터 등
  
  final DateTime date; // 근무 날짜
  final String startTime; // 시작 시간 (예: "09:00")
  final String endTime; // 종료 시간 (예: "18:00")
  final int requiredCount; // 필요 인원
  final int currentCount; // 현재 지원 인원 (동적 계산, 사용 안 함)
  final String workType; // 업무 유형 (피킹, 패킹, 배송 등)
  final String? description; // 설명 (선택사항)
  final String creatorUID; // 생성한 관리자 UID
  final DateTime createdAt; // 생성 시각

  TOModel({
    required this.id,
    required this.businessId,
    required this.businessName,
    this.centerId, // nullable (하위 호환용)
    this.centerName, // nullable (하위 호환용)
    required this.date,
    required this.startTime,
    required this.endTime,
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
      businessId: data['businessId'] ?? '', // ✅ 신규 필드
      businessName: data['businessName'] ?? '', // ✅ 신규 필드
      centerId: data['centerId'], // nullable
      centerName: data['centerName'], // nullable
      date: (data['date'] as Timestamp).toDate(),
      startTime: data['startTime'] ?? '',
      endTime: data['endTime'] ?? '',
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
      'businessId': businessId, // ✅ 필수
      'businessName': businessName, // ✅ 필수
      'centerId': centerId, // 하위 호환용 (nullable)
      'centerName': centerName, // 하위 호환용 (nullable)
      'date': Timestamp.fromDate(date),
      'startTime': startTime,
      'endTime': endTime,
      'requiredCount': requiredCount,
      'currentCount': currentCount,
      'workType': workType,
      'description': description,
      'creatorUID': creatorUID,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  /// 남은 인원 계산
  int get remainingCount => requiredCount - currentCount;

  /// 지원 가능 여부
  bool get isAvailable => currentCount < requiredCount;

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
      centerId: centerId ?? this.centerId,
      centerName: centerName ?? this.centerName,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      requiredCount: requiredCount ?? this.requiredCount,
      currentCount: currentCount ?? this.currentCount,
      workType: workType ?? this.workType,
      description: description ?? this.description,
      creatorUID: creatorUID ?? this.creatorUID,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}