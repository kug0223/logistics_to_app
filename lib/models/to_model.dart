import 'package:cloud_firestore/cloud_firestore.dart';

/// TO(근무 오더) 모델 - 하위 컬렉션 방식 + 그룹 기능
/// workDetails 하위 컬렉션에 업무 상세 정보 저장
class TOModel {
  final String id; // 문서 ID
  
  // ✅ 사업장 연결
  final String businessId; // 사업장 ID
  final String businessName; // 사업장명
  final String jobType; // "short" (단기, ~30일) 또는 "long_term" (1개월+)
  
  // ✅ NEW: TO 그룹 관리 (날짜 범위 지원)
  final String? groupId; // 같은 그룹의 TO들을 묶는 ID (nullable)
  final String? groupName; // 그룹 표시명 (nullable, 예: "피킹 모집")
  final DateTime? startDate; // 그룹 시작일 (nullable)
  final DateTime? endDate; // 그룹 종료일 (nullable)
  final bool isGroupMaster; // 대표 TO 여부 (목록 표시용, 기본값 false)
  
  // ✅ 제목
  final String title; // TO 제목 (예: "물류센터 파트타임알바")
  
  final DateTime date; // 근무 날짜
  final String startTime; // 시작 시간 (예: "09:00")
  final String endTime; // 종료 시간 (예: "18:00")
  
  final DateTime applicationDeadline; // 지원 마감 일시
  // ✅ NEW: 지원 마감 규칙
  final String deadlineType;  // 'HOURS_BEFORE' or 'FIXED_TIME'
  final int? hoursBeforeStart;  // N시간 전 (예: 2)
  
  // ✅ 전체 필요 인원 (모든 업무유형 합계)
  final int totalRequired; // 전체 필요 인원
  final int totalConfirmed; // 전체 확정 인원
  final int totalPending;        // ✅ 추가
  final int totalApplications;   // ✅ 추가
  
  final String? description; // 전체 설명
  final String creatorUID; // 생성한 관리자 UID
  final DateTime createdAt; // 생성 시각
  // ✅ Phase 4: TO 마감 관리
  final bool isManualClosed;        // 수동 마감 여부
  final DateTime? closedAt;         // 마감 시각
  final String? closedBy;           // 마감 처리자 UID
  final DateTime? reopenedAt;       // 재오픈 시각
  final String? reopenedBy;         // 재오픈 처리자 UID

  TOModel({
    required this.id,
    required this.businessId,
    required this.businessName,
    this.jobType = 'short', // ✅ NEW: 기본값 'short' (하위 호환성)
    this.groupId,
    this.groupName,
    this.startDate,
    this.endDate,
    this.isGroupMaster = false, // 기본값 false
    required this.title,
    required this.date,
    required this.startTime,
    required this.endTime,
    required this.applicationDeadline,
    this.deadlineType = 'HOURS_BEFORE',  // 기본값
    this.hoursBeforeStart = 2,  // 기본값: 2시간 전
    required this.totalRequired,
    this.totalConfirmed = 0,
    this.totalPending = 0,        // ✅ 추가
    this.totalApplications = 0,   // ✅ 추가
    this.description,
    required this.creatorUID,
    required this.createdAt,
    // ✅ Phase 4: TO 마감 관리
    this.isManualClosed = false,      // 기본값: 열림
    this.closedAt,
    this.closedBy,
    this.reopenedAt,
    this.reopenedBy,
  });

  /// Firestore 문서를 TOModel로 변환
  factory TOModel.fromMap(Map<String, dynamic> data, String documentId) {
    return TOModel(
      id: documentId,
      businessId: data['businessId'] ?? '',
      businessName: data['businessName'] ?? '',
      jobType: data['jobType'] ?? 'short', // ✅ NEW: 기본값 'short'
      groupId: data['groupId'],
      groupName: data['groupName'],
      startDate: data['startDate'] != null 
          ? (data['startDate'] as Timestamp).toDate()
          : null,
      endDate: data['endDate'] != null 
          ? (data['endDate'] as Timestamp).toDate()
          : null,
      isGroupMaster: data['isGroupMaster'] ?? false,
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
      // ✅ NEW: 지원 마감 규칙
      deadlineType: data['deadlineType'] ?? 'HOURS_BEFORE',
      hoursBeforeStart: data['hoursBeforeStart'] ?? 2,
      

      totalRequired: data['totalRequired'] ?? 0,
      totalConfirmed: data['totalConfirmed'] ?? 0,
      totalPending: data['totalPending'] ?? 0,           // ✅ 추가
      totalApplications: data['totalApplications'] ?? 0, // ✅ 추가
      description: data['description'],
      creatorUID: data['creatorUID'] ?? '',
      createdAt: data['createdAt'] != null 
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.now(),
      // ✅ Phase 4: TO 마감 관리
      isManualClosed: data['isManualClosed'] ?? false,
      closedAt: data['closedAt'] != null
          ? (data['closedAt'] as Timestamp).toDate()
          : null,
      closedBy: data['closedBy'],
      reopenedAt: data['reopenedAt'] != null
          ? (data['reopenedAt'] as Timestamp).toDate()
          : null,
      reopenedBy: data['reopenedBy'],
    );
  }

  /// TOModel을 Firestore 문서로 변환
  Map<String, dynamic> toMap() {
    return {
      'businessId': businessId,
      'businessName': businessName,
      'jobType': jobType, // ✅ NEW
      'groupId': groupId,
      'groupName': groupName,
      'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
      'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
      'isGroupMaster': isGroupMaster,
      'title': title,
      'date': Timestamp.fromDate(date),
      'startTime': startTime,
      'endTime': endTime,
      'applicationDeadline': Timestamp.fromDate(applicationDeadline),
       // ✅ NEW: 지원 마감 규칙
      'deadlineType': deadlineType,
      'hoursBeforeStart': hoursBeforeStart,
      'totalRequired': totalRequired,
      'totalConfirmed': totalConfirmed,
      'description': description,
      'creatorUID': creatorUID,
      'createdAt': Timestamp.fromDate(createdAt),
      // ✅ Phase 4: TO 마감 관리
      'isManualClosed': isManualClosed,
      'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
      'closedBy': closedBy,
      'reopenedAt': reopenedAt != null ? Timestamp.fromDate(reopenedAt!) : null,
      'reopenedBy': reopenedBy,
    };
  }

  /// 복사본 생성
  TOModel copyWith({
    String? id,
    String? businessId,
    String? businessName,
    String? jobType, // ✅ NEW
    String? groupId,
    String? groupName,
    DateTime? startDate,
    DateTime? endDate,
    bool? isGroupMaster,
    String? title,
    DateTime? date,
    String? startTime,
    String? endTime,
    DateTime? applicationDeadline,
    // ✅ NEW
    String? deadlineType,
    int? hoursBeforeStart,
    int? totalRequired,
    int? totalConfirmed,
    String? description,
    String? creatorUID,
    DateTime? createdAt,
    // ✅ Phase 4
    bool? isManualClosed,
    DateTime? closedAt,
    String? closedBy,
    DateTime? reopenedAt,
    String? reopenedBy,
  }) {
    return TOModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      isGroupMaster: isGroupMaster ?? this.isGroupMaster,
      title: title ?? this.title,
      date: date ?? this.date,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      applicationDeadline: applicationDeadline ?? this.applicationDeadline,
      // ✅ NEW
      deadlineType: deadlineType ?? this.deadlineType,
      hoursBeforeStart: hoursBeforeStart ?? this.hoursBeforeStart,
      totalRequired: totalRequired ?? this.totalRequired,
      totalConfirmed: totalConfirmed ?? this.totalConfirmed,
      description: description ?? this.description,
      creatorUID: creatorUID ?? this.creatorUID,
      createdAt: createdAt ?? this.createdAt,
      // ✅ Phase 4
      isManualClosed: isManualClosed ?? this.isManualClosed,
      closedAt: closedAt ?? this.closedAt,
      closedBy: closedBy ?? this.closedBy,
      reopenedAt: reopenedAt ?? this.reopenedAt,
      reopenedBy: reopenedBy ?? this.reopenedBy,
    );
  }
  // ============================================
  // ✅ NEW: 그룹 TO 시간 범위 계산
  // ============================================

  /// WorkDetails에서 계산된 최소 시작 시간 (캐시용)
  String? _cachedMinStartTime;

  /// WorkDetails에서 계산된 최대 종료 시간 (캐시용)
  String? _cachedMaxEndTime;

  /// 계산된 시간 범위 설정
  void setTimeRange(String minStart, String maxEnd) {
    _cachedMinStartTime = minStart;
    _cachedMaxEndTime = maxEnd;
  }

  /// 표시용 시작 시간
  String get displayStartTime {
    // 1순위: 캐시된 값
    if (_cachedMinStartTime != null && _cachedMinStartTime!.isNotEmpty) {
      return _cachedMinStartTime!;
    }
    
    // 2순위: startTime 필드
    if (startTime.isNotEmpty) {
      return startTime;
    }
    
    // 3순위: 기본값
    return '--:--';
  }

  /// 표시용 종료 시간  
  String get displayEndTime {
    // 1순위: 캐시된 값
    if (_cachedMaxEndTime != null && _cachedMaxEndTime!.isNotEmpty) {
      return _cachedMaxEndTime!;
    }
    
    // 2순위: endTime 필드
    if (endTime.isNotEmpty) {
      return endTime;
    }
    
    // 3순위: 기본값
    return '--:--';
  }

  /// 표시용 시간 범위 (예: "08:00 ~ 18:00")
  String get displayTimeRange {
    return '$displayStartTime ~ $displayEndTime';
  }

  /// 마감 여부 체크
  bool get isDeadlinePassed {
    return DateTime.now().isAfter(applicationDeadline);
  }

  /// 그룹 TO 여부
  bool get isGroupTO {
    return groupId != null;
  }

  /// 그룹 기간 문자열 (예: "10/24~10/30")
  String? get groupPeriodString {
    if (startDate == null || endDate == null) return null;
    
    final start = '${startDate!.month}/${startDate!.day}';
    final end = '${endDate!.month}/${endDate!.day}';
    return '$start~$end';
  }

  /// 그룹 일수
  int? get groupDaysCount {
    if (startDate == null || endDate == null) return null;
    return endDate!.difference(startDate!).inDays + 1;
  }

  /// 날짜 포맷 (예: "10/24 (금)")
  String get formattedDate {
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[date.weekday - 1];
    return '${date.month}/${date.day} ($weekday)';
  }

  /// 요일 (예: "금")
  String get weekday {
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return weekdays[date.weekday - 1];
  }

  /// 마감 상태 텍스트
  String get deadlineStatus {
    final now = DateTime.now();
    final diff = applicationDeadline.difference(now);
    
    if (diff.isNegative) {
      return '마감';
    } else if (diff.inHours < 1) {
      return 'D-${diff.inMinutes}분';
    } else if (diff.inHours < 24) {
      return 'D-${diff.inHours}시간';
    } else {
      return 'D-${diff.inDays}일';
    }
  }

  /// 마감 임박 여부 (24시간 이내)
  bool get isDeadlineSoon {
    final now = DateTime.now();
    final diff = applicationDeadline.difference(now);
    return diff.inHours < 24 && diff.inHours >= 0;
  }

  /// 그룹화된 TO인지 확인
  bool get isGrouped {
    return groupId != null;
  }
  /// 남은 자리 수
  int get availableSlots {
    return totalRequired - totalConfirmed;
  }
  /// 시간 범위 (예: "08:00 ~ 18:00")
  /// 그룹 TO의 경우 계산된 시간 범위 사용
  String get timeRange => displayTimeRange;
  /// 마감 시간 포맷 (예: "10/23 18:00")
  String get formattedDeadline {
    return '${applicationDeadline.month}/${applicationDeadline.day} '
           '${applicationDeadline.hour.toString().padLeft(2, '0')}:'
           '${applicationDeadline.minute.toString().padLeft(2, '0')}';
  }
  /// Phase A: 채용 유형 확인
  bool get isShortTerm => jobType == 'short';
  bool get isLongTerm => jobType == 'long_term';

  /// 채용 유형 표시명
  String get jobTypeLabel {
    return isShortTerm ? '단기 알바' : '1개월+ 계약직';
  }
  // ✅ NEW: 실제 지원 마감 시간 계산 (getter)
  DateTime get effectiveDeadline {
    if (deadlineType == 'HOURS_BEFORE' && hoursBeforeStart != null && startTime != null) {
      try {
        final timeParts = startTime!.split(':');
        final startDateTime = DateTime(
          date.year,
          date.month,
          date.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
        return startDateTime.subtract(Duration(hours: hoursBeforeStart!));
      } catch (e) {
        return applicationDeadline;
      }
    }
    return applicationDeadline;
  }
  // ============================================
  // ✅ Phase 4: TO 마감 상태 계산
  // ============================================

  /// 근무 시작 시간이 지났는지 확인
  bool get isTimeExpired {
    try {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      // 🔥 그룹 TO면 엄격하게 체크 안 함 (각 날짜별 시간이 다름)
      if (isGrouped) {
        // 그룹의 경우 endDate까지는 진행중
        if (endDate != null) {
          final groupEndDate = DateTime(endDate!.year, endDate!.month, endDate!.day);
          return groupEndDate.isBefore(today);
        }
      }
      
      // 단일 TO만 시간 체크
      final workDate = DateTime(date.year, date.month, date.day);
      
      if (workDate.isBefore(today)) {
        return true;
      }
      
      if (workDate.isAtSameMomentAs(today)) {
        if (startTime.isNotEmpty && startTime.contains(':')) {
          final timeParts = startTime.split(':');
          if (timeParts.length >= 2) {
            final workStart = DateTime(
              date.year,
              date.month,
              date.day,
              int.parse(timeParts[0]),
              int.parse(timeParts[1]),
            );
            return now.isAfter(workStart);
          }
        }
      }
      
      return false;
    } catch (e) {
      print('⚠️ isTimeExpired 계산 오류: $e');
      return false;
    }
  }

  /// 인원이 모두 충족되었는지 확인
  bool get isFull => totalConfirmed >= totalRequired;

  /// TO가 마감되었는지 확인 (수동 마감 or 시간 초과 or 인원 충족)
  bool get isClosed {
    return isManualClosed || isTimeExpired || isFull;
  }

  /// 마감 사유 문자열
  String get closedReason {
    if (isManualClosed) return '수동 마감';
    if (isTimeExpired) return '시간 초과';
    if (isFull) return '인원 충족';
    return '';
  }

  /// 마감 사유 색상 (UI용)
  int get closedReasonColor {
    if (isManualClosed) return 0xFFFF9800; // 주황색
    if (isTimeExpired) return 0xFFF44336; // 빨간색
    if (isFull) return 0xFF4CAF50; // 초록색
    return 0xFF9E9E9E; // 회색
  }
}