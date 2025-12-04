import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../utils/format_helper.dart';

/// TO(근무 오더) 모델 - 하위 컬렉션 방식 + 그룹 기능
/// workDetails 하위 컬렉션에 업무 상세 정보 저장
class TOModel {
  final String id; // 문서 ID
  
  // ✅ 사업장 연결
  final String businessId; // 사업장 ID
  final String businessName; // 사업장명
  final String? businessAddress;   // 사업장 주소
  final String? businessCity;      // 시/구 (예: 오산시, 강남구)
  final String? businessDistrict;  // 동 (예: 세교동, 역삼동)
  final String jobType; // "short" (단기, ~30일) 또는 "long_term" (1개월+)
  final List<String>? workDays; // 장기 근무 요일 (예: ['월', '수', '금'])  // ⭐ 이 줄 추가
  
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

  // ✅ 급여 정보 (겉 카드 표시용)
  final int? minWage;            // 최소 급여
  final int? maxWage;            // 최대 급여
  final String? wageType;        // 급여 타입 (hourly, daily, monthly)
  final int workDetailCount;     // 업무 개수

  // ✅ 그룹 마스터 전용 통계 (마스터 TO에만 저장)
  final int? groupTotalRequired;   // 그룹 전체 필요 인원
  final int? groupTotalConfirmed;  // 그룹 전체 확정 인원
  final int? groupTotalPending;    // 그룹 전체 대기 인원
  
  final String? description; // 전체 설명
  final String creatorUID; // 생성한 관리자 UID
  final DateTime createdAt; // 생성 시각
  // ✅ Phase 4: TO 마감 관리
  final bool isManualClosed;        // 수동 마감 여부
  final DateTime? closedAt;         // 마감 시각
  final String? closedBy;           // 마감 처리자 UID
  final DateTime? reopenedAt;       // 재오픈 시각
  final String? reopenedBy;         // 재오픈 처리자 UID

  // ✅ 예약 공개 관리
  final String publishMode;         // 'immediate' (즉시) | 'scheduled' (예약)
  final DateTime? publishAt;        // 예약 공개 시간
  final bool isPublished;           // 실제 공개 여부
  final int? publishDaysBefore;     // D-N (1, 2, 3 등)
  final String? publishTime;        // 공개 시간 ('14:00' 등)

  TOModel({
    required this.id,
    required this.businessId,
    required this.businessName,
    this.businessAddress,
    this.businessCity,
    this.businessDistrict,
    this.jobType = 'short',
    this.workDays,
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
    // ✅ 급여 정보
    this.minWage,
    this.maxWage,
    this.wageType,
    this.workDetailCount = 1,
    // ✅ 그룹 마스터 통계
    this.groupTotalRequired,
    this.groupTotalConfirmed,
    this.groupTotalPending,

    this.description,
    required this.creatorUID,
    required this.createdAt,
    // ✅ Phase 4: TO 마감 관리
    this.isManualClosed = false,      // 기본값: 열림
    this.closedAt,
    this.closedBy,
    this.reopenedAt,
    this.reopenedBy,
    // ✅ 예약 공개 관리
    this.publishMode = 'immediate',   // 기본값: 즉시 공개
    this.publishAt,
    this.isPublished = true,          // 기본값: 공개됨 (하위 호환성)
    this.publishDaysBefore,
    this.publishTime,
  });

  /// Firestore 문서를 TOModel로 변환
  factory TOModel.fromMap(Map<String, dynamic> data, String documentId) {
    return TOModel(
      id: documentId,
      businessId: data['businessId'] ?? '',
      businessName: data['businessName'] ?? '',
      businessAddress: data['businessAddress'],
      businessCity: data['businessCity'],
      businessDistrict: data['businessDistrict'],
      jobType: data['jobType'] ?? 'short',
      workDays: data['workDays'] != null  // ⭐ 이 3줄 추가
        ? List<String>.from(data['workDays'])
        : null,
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
      // ✅ 급여 정보
      minWage: data['minWage'],
      maxWage: data['maxWage'],
      wageType: data['wageType'],
      workDetailCount: data['workDetailCount'] ?? 1,
      // ✅ 그룹 마스터 통계
      groupTotalRequired: data['groupTotalRequired'],
      groupTotalConfirmed: data['groupTotalConfirmed'],
      groupTotalPending: data['groupTotalPending'],

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
      // ✅ 예약 공개 관리
      publishMode: data['publishMode'] ?? 'immediate',
      publishAt: data['publishAt'] != null
          ? (data['publishAt'] as Timestamp).toDate()
          : null,
      isPublished: data['isPublished'] ?? true,  // 기존 데이터는 공개 상태
      publishDaysBefore: data['publishDaysBefore'],
      publishTime: data['publishTime'],
    );
  }

  /// TOModel을 Firestore 문서로 변환
  Map<String, dynamic> toMap() {
    return {
      'businessId': businessId,
      'businessName': businessName,
      'businessAddress': businessAddress,
      'businessCity': businessCity,
      'businessDistrict': businessDistrict,
      'jobType': jobType,
      'workDays': workDays,
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
      // ✅ 급여 정보
      'minWage': minWage,
      'maxWage': maxWage,
      'wageType': wageType,
      'workDetailCount': workDetailCount,
      // ✅ 그룹 마스터 통계 (null이면 저장 안함)
      if (groupTotalRequired != null) 'groupTotalRequired': groupTotalRequired,
      if (groupTotalConfirmed != null) 'groupTotalConfirmed': groupTotalConfirmed,
      if (groupTotalPending != null) 'groupTotalPending': groupTotalPending,
      'description': description,
      'creatorUID': creatorUID,
      'createdAt': Timestamp.fromDate(createdAt),
      // ✅ Phase 4: TO 마감 관리
      'isManualClosed': isManualClosed,
      'closedAt': closedAt != null ? Timestamp.fromDate(closedAt!) : null,
      'closedBy': closedBy,
      'reopenedAt': reopenedAt != null ? Timestamp.fromDate(reopenedAt!) : null,
      'reopenedBy': reopenedBy,
      // ✅ 예약 공개 관리
      'publishMode': publishMode,
      'publishAt': publishAt != null ? Timestamp.fromDate(publishAt!) : null,
      'isPublished': isPublished,
      'publishDaysBefore': publishDaysBefore,
      'publishTime': publishTime,
    };
  }

  /// 복사본 생성
  TOModel copyWith({
    String? id,
    String? businessId,
    String? businessName,
    String? businessAddress,
    String? businessCity,
    String? businessDistrict,
    String? jobType,
    List<String>? workDays,
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
    // ✅ 급여 정보
    int? minWage,
    int? maxWage,
    String? wageType,
    int? workDetailCount,
    // ✅ 그룹 마스터 통계
    int? groupTotalRequired,
    int? groupTotalConfirmed,
    int? groupTotalPending,
    String? description,
    String? creatorUID,
    DateTime? createdAt,
    // ✅ Phase 4
    bool? isManualClosed,
    DateTime? closedAt,
    String? closedBy,
    DateTime? reopenedAt,
    String? reopenedBy,
    // ✅ 예약 공개 관리
    String? publishMode,
    DateTime? publishAt,
    bool? isPublished,
    int? publishDaysBefore,
    String? publishTime,
  }) {
    return TOModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      businessAddress: businessAddress ?? this.businessAddress,
      businessCity: businessCity ?? this.businessCity,
      businessDistrict: businessDistrict ?? this.businessDistrict,
      jobType: jobType ?? this.jobType,
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
      // ✅ 급여 정보
      minWage: minWage ?? this.minWage,
      maxWage: maxWage ?? this.maxWage,
      wageType: wageType ?? this.wageType,
      workDetailCount: workDetailCount ?? this.workDetailCount,
      // ✅ 그룹 마스터 통계
      groupTotalRequired: groupTotalRequired ?? this.groupTotalRequired,
      groupTotalConfirmed: groupTotalConfirmed ?? this.groupTotalConfirmed,
      groupTotalPending: groupTotalPending ?? this.groupTotalPending,
      description: description ?? this.description,
      creatorUID: creatorUID ?? this.creatorUID,
      createdAt: createdAt ?? this.createdAt,
      // ✅ Phase 4
      isManualClosed: isManualClosed ?? this.isManualClosed,
      closedAt: closedAt ?? this.closedAt,
      closedBy: closedBy ?? this.closedBy,
      reopenedAt: reopenedAt ?? this.reopenedAt,
      reopenedBy: reopenedBy ?? this.reopenedBy,
      // ✅ 예약 공개 관리
      publishMode: publishMode ?? this.publishMode,
      publishAt: publishAt ?? this.publishAt,
      isPublished: isPublished ?? this.isPublished,
      publishDaysBefore: publishDaysBefore ?? this.publishDaysBefore,
      publishTime: publishTime ?? this.publishTime,
      
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
  /// 장기 근무 기간 표시 (예: "11/28 (목) ~ 12/7 (토)")
  String get longTermPeriodWithDays {
    if (!isLongTerm || startDate == null || endDate == null) return '';
    
    return '${FormatHelper.formatDate(startDate!)} ~ ${FormatHelper.formatDate(endDate!)}';
  }
  /// 근무 요일 레이블 (새로 추가)
  String get workDaysLabel {
    if (!isLongTerm || workDays == null || workDays!.isEmpty) return '';
    
    final workCount = workDays!.length;
    
    // 주 7일
    if (workCount == 7) {
      return '매일 근무';
    }
    
    // 주 6일 (1일 휴무)
    if (workCount == 6) {
      final allDays = ['월', '화', '수', '목', '금', '토', '일'];
      final offDay = allDays.firstWhere((day) => !workDays!.contains(day));
      return '주 6일 ($offDay 휴무)';
    }
    
    // 주 5일 (2일 휴무)
    if (workCount == 5) {
      final allDays = ['월', '화', '수', '목', '금', '토', '일'];
      final offDays = allDays.where((day) => !workDays!.contains(day)).join(', ');
      return '주 5일 ($offDays 휴무)';
    }
    
    // 주 4일 이하
    if (workCount <= 4) {
      return '주 $workCount일 (${workDays!.join(', ')})';
    }
    
    return '주 $workCount일';
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
    return isShortTerm ? '단기 근무' : '고정 근무';
  }
  // ✅ NEW: 실제 지원 마감 시간 계산 (getter)
  DateTime get effectiveDeadline {
    if (deadlineType == 'HOURS_BEFORE' && hoursBeforeStart != null) {
      try {
        final timeParts = startTime.split(':');
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
      
      // ✅ 장기 공고: applicationDeadline 기준
      if (isLongTerm) {
        return now.isAfter(applicationDeadline);
      }
      
      // 🔥 그룹 TO면 엄격하게 체크 안 함 (각 날짜별 시간이 다름)
      if (isGrouped) {
        // 그룹의 경우 endDate까지는 진행중
        if (endDate != null) {
          final groupEndDate = DateTime(endDate!.year, endDate!.month, endDate!.day);
          return groupEndDate.isBefore(today);
        }
      }
      
      // 단기 TO만 시간 체크
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
  /// 그룹 날짜 범위 표시 (예: "11/15 ~ 11/17 (3일)")
  String? get groupDateRangeDisplay {
    if (!isGroupMaster || startDate == null || endDate == null) return null;
    
    final start = '${startDate!.month}/${startDate!.day}';
    final end = '${endDate!.month}/${endDate!.day}';
    final days = endDate!.difference(startDate!).inDays + 1;
    
    return '$start ~ $end ($days일)';
  }
  // ============================================
  // ✅ 예약 공개 관련 헬퍼
  // ============================================

  /// 예약 공개 모드인지 확인
  bool get isScheduledPublish => publishMode == 'scheduled';

  /// 공개 대기 중인지 확인 (예약 모드 + 미공개)
  bool get isPendingPublish => isScheduledPublish && !isPublished;

  /// 공개 예정 시간 표시 (예: "11/27 14:00")
  String? get publishAtDisplay {
    if (publishAt == null) return null;
    return '${publishAt!.month}/${publishAt!.day} '
           '${publishAt!.hour.toString().padLeft(2, '0')}:'
           '${publishAt!.minute.toString().padLeft(2, '0')}';
  }
}