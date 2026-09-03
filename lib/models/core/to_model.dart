import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../utils/firestore_helper.dart';
import '../../utils/format_helper.dart';
import 'work_detail_data.dart';

/// 공고(TO) 모델 — slots 구조 기반
///
/// type: 'flex'     단기 일용직. 날짜별 SlotModel 서브컬렉션으로 관리.
/// type: 'contract' 장기 계약직. 날짜 슬롯 없이 공고 단위로 지원자 관리.
///
/// workDetails: 배열 필드로 TO 문서에 직접 저장 (별도 서브컬렉션 없음).
///
/// ─── 미구현 필터 (향후 추가 예정) ───────────────────────────────────
/// 아래 조건은 현재 TOModel/지원 로직에 없음 — 구현 시 이 파일 + applyToTO 수정 필요:
///
/// [A08] targetGender: 공고 지원 가능 성별 제한 (예: '남성만', '여성만', '무관')
///   → UserModel.gender와 비교하는 지원 검증 로직 필요
///
/// [A09] minAge / maxAge: 공고 지원 가능 나이 범위 제한
///   → UserModel에서 생년월일 → 나이 계산 후 비교 필요
///
/// [A10] requiredDocuments: 지원에 필요한 서류 목록 (예: ['주민등록증', '통장사본'])
///   → application_firestore.applyToTO 단계에서 UserModel.uploadedDocs 비교 필요
///   → 현재는 hasValidIdDocument(신분증 인증) + documentStatus(서류 완비) 일괄 체크만 수행
/// ──────────────────────────────────────────────────────────────────
class TOModel {
  final String id;

  // ── 사업장 ────────────────────────────────────────
  final String businessId;
  final String businessName;
  final String? businessAddress;
  final String? businessCity;
  final String? businessDistrict;

  // ── 공고 유형 ─────────────────────────────────────
  /// 'flex' (단기) | 'contract' (장기)
  final String type;

  // ── 기본 정보 ─────────────────────────────────────
  final String title;
  final String? groupTitle; // 관리자용 카드 제목 (null이면 title 사용)
  final String? description;

  // ── 업무 상세 (배열, 문서 내 저장) ────────────────
  final List<WorkDetailData> workDetails;

  // ── flex 전용 집계 ────────────────────────────────
  /// 등록된 슬롯(날짜) 수
  final int totalSlots;

  // ── contract 전용 ─────────────────────────────────
  final DateTime? rangeStart;
  final DateTime? rangeEnd;
  final List<String> workDays; // ['월', '화', ...]
  final String deadlineType;   // 'HOURS_BEFORE' | 'FIXED_TIME'
  final int? hoursBeforeStart;
  final DateTime? applicationDeadline; // contract: 공고 마감일
  /// 계약 기간 유형: '15days' | '1month' | '3months' | '6months' | '1year' | 'custom'
  final String? contractPeriodType;
  /// 게시 기간 (일수): 3, 5, 7, 10
  final int? postingDurationDays;
  /// 서버 저장 게시 만료일 (CF 계산값 — 연장 시 업데이트됨)
  final DateTime? postingExpiryDateServer;
  /// 근무 시작 가능기간 시작일 (preset 장기공고 전용)
  /// 지원자가 희망 시작일로 선택 가능한 범위의 첫날
  final DateTime? workStartAvailableFrom;
  /// 근무 시작 가능기간 종료일 (preset 장기공고 전용)
  /// 지원자가 희망 시작일로 선택 가능한 범위의 마지막날
  final DateTime? workStartAvailableUntil;

  // ── 인원 집계 ─────────────────────────────────────
  final int totalRequired;
  final int totalConfirmed;
  final int totalPending;

  // ── 상태 ─────────────────────────────────────────
  final String status; // 'ACTIVE' | 'CLOSED' | 'FULL' | 'EXPIRED' | 'SCHEDULED'
  final DateTime? statusUpdatedAt;
  final bool isManualClosed;
  final DateTime? closedAt;
  final String? closedBy;
  /// Firestore 저장 마감 원인 코드 (POSTING_EXPIRED | TIME_EXPIRED | MANUAL | ...)
  final String? closedReasonCode;
  final DateTime? reopenedAt;
  final String? reopenedBy;

  // ── 예약 공개 ─────────────────────────────────────
  final String publishMode; // 'immediate' | 'scheduled'
  final DateTime? publishAt;
  final bool isPublished;
  final int? publishDaysBefore;
  final String? publishTime;

  // ── 소프트 삭제 ──────────────────────────────────
  /// true이면 관리자가 삭제 처리한 공고. 문서·기록은 Firestore에 보존됨.
  final bool isDeleted;
  final DateTime? deletedAt;

  // ── 메타 ─────────────────────────────────────────
  final String creatorUID;
  final DateTime createdAt;

  TOModel({
    required this.id,
    required this.businessId,
    required this.businessName,
    this.businessAddress,
    this.businessCity,
    this.businessDistrict,
    this.type = 'flex',
    required this.title,
    this.groupTitle,
    this.description,
    this.workDetails = const [],
    this.totalSlots = 0,
    this.rangeStart,
    this.rangeEnd,
    this.workDays = const [],
    this.deadlineType = 'HOURS_BEFORE',
    this.hoursBeforeStart = 2,
    this.applicationDeadline,
    this.contractPeriodType,
    this.postingDurationDays,
    this.postingExpiryDateServer,
    this.workStartAvailableFrom,
    this.workStartAvailableUntil,
    this.totalRequired = 0,
    this.totalConfirmed = 0,
    this.totalPending = 0,
    this.status = TOStatus.active,
    this.statusUpdatedAt,
    this.isManualClosed = false,
    this.closedAt,
    this.closedBy,
    this.closedReasonCode,
    this.reopenedAt,
    this.reopenedBy,
    this.publishMode = 'immediate',
    this.publishAt,
    this.isPublished = true,
    this.publishDaysBefore,
    this.publishTime,
    this.isDeleted = false,
    this.deletedAt,
    required this.creatorUID,
    required this.createdAt,
  });

  // ── 직렬화 ────────────────────────────────────────

  static TOModel? tryFromMap(Map<String, dynamic> data, String documentId) {
    try {
      return TOModel.fromMap(data, documentId);
    } catch (e, st) {
      debugPrint('[TOModel] tryFromMap 실패 id=$documentId: $e\n$st');
      return null;
    }
  }

  factory TOModel.fromMap(Map<String, dynamic> data, String documentId) {
    return TOModel(
      id: documentId,
      businessId: data['businessId'] as String? ?? '',
      businessName: data['businessName'] as String? ?? '',
      businessAddress: data['businessAddress'] as String?,
      businessCity: data['businessCity'] as String?,
      businessDistrict: data['businessDistrict'] as String?,
      type: data['type'] as String? ?? 'flex',
      title: data['title'] as String? ?? '제목 없음',
      groupTitle: data['groupTitle'] as String?,
      description: data['description'] as String?,
      workDetails: WorkDetailData.listFromFirestore(data['workDetails']),
      // totalSlots=0 폴백 — 서버 FieldValue.increment 완료 전 순간 0으로 읽힐 수 있음
      // 크래시 없음, isFull 계산은 totalRequired 기준으로 별도 처리되므로 영향 없음
      totalSlots: (data['totalSlots'] as num?)?.toInt() ?? 0,
      rangeStart: parseTimestampNullable(data['rangeStart']),
      rangeEnd: parseTimestampNullable(data['rangeEnd']),
      workDays: data['workDays'] != null
          ? List<String>.from(data['workDays'] as List)
          : const [],
      deadlineType: data['deadlineType'] as String? ?? 'HOURS_BEFORE',
      hoursBeforeStart: (data['hoursBeforeStart'] as num?)?.toInt() ?? 2,
      applicationDeadline: parseTimestampNullable(data['applicationDeadline']),
      contractPeriodType: data['contractPeriodType'] as String?,
      postingDurationDays: (data['postingDurationDays'] as num?)?.toInt(),
      postingExpiryDateServer:
          parseTimestampNullable(data['postingExpiryDate']),
      workStartAvailableFrom:
          parseTimestampNullable(data['workStartAvailableFrom']),
      workStartAvailableUntil:
          parseTimestampNullable(data['workStartAvailableUntil']),
      totalRequired: (data['totalRequired'] as num?)?.toInt() ?? 0,
      totalConfirmed: (data['totalConfirmed'] as num?)?.toInt() ?? 0,
      totalPending: (data['totalPending'] as num?)?.toInt() ?? 0,
      status: data['status'] as String? ?? TOStatus.active,
      statusUpdatedAt: parseTimestampNullable(data['statusUpdatedAt']),
      isManualClosed: data['isManualClosed'] as bool? ?? false,
      closedAt: parseTimestampNullable(data['closedAt']),
      closedBy: data['closedBy'] as String?,
      closedReasonCode: data['closedReason'] as String?,
      reopenedAt: parseTimestampNullable(data['reopenedAt']),
      reopenedBy: data['reopenedBy'] as String?,
      publishMode: data['publishMode'] as String? ?? 'immediate',
      publishAt: parseTimestampNullable(data['publishAt']),
      isPublished: data['isPublished'] as bool? ?? true,
      publishDaysBefore: (data['publishDaysBefore'] as num?)?.toInt(),
      publishTime: data['publishTime'] as String?,
      isDeleted: data['isDeleted'] as bool? ?? false,
      deletedAt: parseTimestampNullable(data['deletedAt']),
      creatorUID: data['creatorUID'] as String? ?? '',
      // createdAt 누락 시 DateTime.now() 폴백 — 서버 미저장 임시 객체나 마이그레이션 전 문서에서 발생 가능
      createdAt: parseTimestampNullable(data['createdAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'businessId': businessId,
      'businessName': businessName,
      'businessAddress': businessAddress,
      'businessCity': businessCity,
      'businessDistrict': businessDistrict,
      'type': type,
      'title': title,
      if (groupTitle != null && groupTitle!.isNotEmpty) 'groupTitle': groupTitle,
      'description': description,
      'workDetails': WorkDetailData.listToFirestore(workDetails),
      'totalSlots': totalSlots,
      if (rangeStart != null) 'rangeStart': Timestamp.fromDate(rangeStart!),
      if (rangeEnd != null) 'rangeEnd': Timestamp.fromDate(rangeEnd!),
      'workDays': workDays,
      'deadlineType': deadlineType,
      'hoursBeforeStart': hoursBeforeStart,
      if (applicationDeadline != null)
        'applicationDeadline': Timestamp.fromDate(applicationDeadline!),
      if (contractPeriodType != null) 'contractPeriodType': contractPeriodType,
      if (postingDurationDays != null) 'postingDurationDays': postingDurationDays,
      if (postingExpiryDateServer != null)
        'postingExpiryDate': Timestamp.fromDate(postingExpiryDateServer!),
      if (workStartAvailableFrom != null)
        'workStartAvailableFrom': Timestamp.fromDate(workStartAvailableFrom!),
      if (workStartAvailableUntil != null)
        'workStartAvailableUntil': Timestamp.fromDate(workStartAvailableUntil!),
      'totalRequired': totalRequired,
      'totalConfirmed': totalConfirmed,
      'totalPending': totalPending,
      'status': status,
      if (statusUpdatedAt != null)
        'statusUpdatedAt': Timestamp.fromDate(statusUpdatedAt!),
      'isManualClosed': isManualClosed,
      if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!),
      if (closedReasonCode != null) 'closedReason': closedReasonCode,
      'closedBy': closedBy,
      if (reopenedAt != null) 'reopenedAt': Timestamp.fromDate(reopenedAt!),
      'reopenedBy': reopenedBy,
      'publishMode': publishMode,
      if (publishAt != null) 'publishAt': Timestamp.fromDate(publishAt!),
      'isPublished': isPublished,
      'publishDaysBefore': publishDaysBefore,
      'publishTime': publishTime,
      'isDeleted': isDeleted,
      if (deletedAt != null) 'deletedAt': Timestamp.fromDate(deletedAt!),
      'creatorUID': creatorUID,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  TOModel copyWith({
    String? id,
    String? businessId,
    String? businessName,
    String? businessAddress,
    String? businessCity,
    String? businessDistrict,
    String? type,
    String? title,
    String? groupTitle,
    bool clearGroupTitle = false,
    String? description,
    List<WorkDetailData>? workDetails,
    int? totalSlots,
    DateTime? rangeStart,
    DateTime? rangeEnd,
    List<String>? workDays,
    String? deadlineType,
    int? hoursBeforeStart,
    DateTime? applicationDeadline,
    int? totalRequired,
    int? totalConfirmed,
    int? totalPending,
    String? status,
    DateTime? statusUpdatedAt,
    bool? isManualClosed,
    DateTime? closedAt,
    String? closedBy,
    String? closedReasonCode,
    DateTime? reopenedAt,
    String? reopenedBy,
    String? publishMode,
    DateTime? publishAt,
    bool? isPublished,
    int? publishDaysBefore,
    String? publishTime,
    String? contractPeriodType,
    bool clearContractPeriodType = false,
    int? postingDurationDays,
    bool clearPostingDuration = false,
    DateTime? postingExpiryDateServer,
    bool clearPostingExpiryDateServer = false,
    DateTime? workStartAvailableFrom,
    bool clearWorkStartAvailableFrom = false,
    DateTime? workStartAvailableUntil,
    bool clearWorkStartAvailableUntil = false,
    String? creatorUID,
    DateTime? createdAt,
    bool? isDeleted,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
  }) {
    return TOModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      businessAddress: businessAddress ?? this.businessAddress,
      businessCity: businessCity ?? this.businessCity,
      businessDistrict: businessDistrict ?? this.businessDistrict,
      type: type ?? this.type,
      title: title ?? this.title,
      groupTitle: clearGroupTitle ? null : (groupTitle ?? this.groupTitle),
      description: description ?? this.description,
      workDetails: workDetails ?? this.workDetails,
      totalSlots: totalSlots ?? this.totalSlots,
      rangeStart: rangeStart ?? this.rangeStart,
      rangeEnd: rangeEnd ?? this.rangeEnd,
      workDays: workDays ?? this.workDays,
      deadlineType: deadlineType ?? this.deadlineType,
      hoursBeforeStart: hoursBeforeStart ?? this.hoursBeforeStart,
      applicationDeadline: applicationDeadline ?? this.applicationDeadline,
      totalRequired: totalRequired ?? this.totalRequired,
      totalConfirmed: totalConfirmed ?? this.totalConfirmed,
      totalPending: totalPending ?? this.totalPending,
      status: status ?? this.status,
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
      isManualClosed: isManualClosed ?? this.isManualClosed,
      closedAt: closedAt ?? this.closedAt,
      closedBy: closedBy ?? this.closedBy,
      closedReasonCode: closedReasonCode ?? this.closedReasonCode,
      reopenedAt: reopenedAt ?? this.reopenedAt,
      reopenedBy: reopenedBy ?? this.reopenedBy,
      publishMode: publishMode ?? this.publishMode,
      publishAt: publishAt ?? this.publishAt,
      isPublished: isPublished ?? this.isPublished,
      publishDaysBefore: publishDaysBefore ?? this.publishDaysBefore,
      publishTime: publishTime ?? this.publishTime,
      contractPeriodType: clearContractPeriodType ? null : (contractPeriodType ?? this.contractPeriodType),
      postingDurationDays: clearPostingDuration ? null : (postingDurationDays ?? this.postingDurationDays),
      postingExpiryDateServer: clearPostingExpiryDateServer ? null : (postingExpiryDateServer ?? this.postingExpiryDateServer),
      workStartAvailableFrom: clearWorkStartAvailableFrom ? null : (workStartAvailableFrom ?? this.workStartAvailableFrom),
      workStartAvailableUntil: clearWorkStartAvailableUntil ? null : (workStartAvailableUntil ?? this.workStartAvailableUntil),
      creatorUID: creatorUID ?? this.creatorUID,
      createdAt: createdAt ?? this.createdAt,
      isDeleted: isDeleted ?? this.isDeleted,
      deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
    );
  }

  // ── 타입 헬퍼 ─────────────────────────────────────

  bool get isFlexType => type == TOType.flex;
  bool get isContractType => type == TOType.contract;

  /// 소프트 삭제 여부 — isDeleted == true이면 관리자가 삭제 처리한 공고
  bool get isSoftDeleted => isDeleted;

  /// 관리자 카드에 표시할 제목 (groupTitle 없으면 title 사용)
  String get displayGroupTitle =>
      (groupTitle?.isNotEmpty == true) ? groupTitle! : title;

  String get typeLabel => isFlexType ? '단기 근무' : '고정 근무';

  // ── workDetails 집계 (computed) ───────────────────

  int get workDetailCount => workDetails.length;

  int? get minWage => workDetails.isEmpty
      ? null
      : workDetails.map((d) => d.wage).reduce((a, b) => a < b ? a : b);

  int? get maxWage => workDetails.isEmpty
      ? null
      : workDetails.map((d) => d.wage).reduce((a, b) => a > b ? a : b);

  String? get wageType => workDetails.isEmpty ? null : workDetails.first.wageType;

  String get timeRange {
    if (workDetails.isEmpty) return '--:-- ~ --:--';
    final starts = workDetails.map((d) => d.startTime).toList()..sort();
    final ends = workDetails.map((d) => d.endTime).toList()..sort();
    // isEmpty 가드 직후 — starts/ends 모두 ≥1개 보장, .first/.last 안전
    return '${starts.first} ~ ${ends.last}';
  }

  // ── 상태 헬퍼 ─────────────────────────────────────

  // totalRequired=0 이면 isFull=false (항상 모집 중) — "인원 제한 없음" 의도한 설계
  // TO 생성 시 totalRequired=0으로 저장하면 슬롯 수 무제한으로 운영 가능
  bool get isFull => totalRequired > 0 && totalConfirmed >= totalRequired;
  bool get isActive => status == TOStatus.active;
  bool get isScheduledPublish => publishMode == 'scheduled';

  bool get isPendingPublish {
    if (!isScheduledPublish || isPublished || publishAt == null) return false;
    return DateTime.now().isBefore(publishAt!);
  }

  // 닫힘 여부 단일 판단 — Firestore status + 런타임 만료 조건 통합
  // isManualClosed는 CF 갱신 전(최대 30분)에도 즉시 반영
  // contract TO: 게시만료(isPostingExpired) 또는 지원마감(isDeadlinePassed)도 마감으로 처리
  bool get isClosed =>
      isManualClosed ||
      isFull ||
      status == TOStatus.closed ||
      status == TOStatus.expired ||
      (isContractType && (isPostingExpired || isDeadlinePassed));

  /// [4J.0B] PENDING 지원자 승인 가능 여부 — isClosed보다 세분화된 판단
  ///
  /// - isManualClosed ONLY: 허용 (4I 설계 — 기존 PENDING은 관리자가 계속 처리 가능)
  /// - isFull: 거부 (정원 충족, CF capacity guard에서도 차단)
  /// - TIME_EXPIRED / POSTING_EXPIRED: 거부 (근무 시점·게시 기간 만료)
  /// - isContractType + postingExpired/deadlinePassed: 거부
  bool get canApprovePending =>
      !isFull &&
      status != TOStatus.expired &&
      !(status == TOStatus.closed && !isManualClosed) &&
      !(isContractType && (isPostingExpired || isDeadlinePassed));

  String get calculatedStatus {
    if (isManualClosed) return TOStatus.closed;
    if (isFull) return TOStatus.full;
    return TOStatus.active;
  }

  // ── contract 전용 ─────────────────────────────────

  /// preset 기간 여부
  bool get hasPresetPeriod => contractPeriodType != null && contractPeriodType != 'custom';

  /// 신규 근무 시작 가능기간 필드 존재 여부 (preset 전용)
  /// false이면 legacy 공고 — 기존 동작 유지
  bool get hasWorkStartAvailableRange =>
      workStartAvailableFrom != null && workStartAvailableUntil != null;

  /// 계약 기간 레이블
  String get contractPeriodLabel {
    switch (contractPeriodType) {
      case '15days': return '15일';
      case '1month': return '1개월';
      case '3months': return '3개월';
      case '6months': return '6개월';
      case '1year': return '1년';
      case 'custom': return '직접 입력';
      default: return '';
    }
  }

  /// 월말 clamp 후 N달 더하기 헬퍼 — Dart month overflow 방지
  /// 예: 1/31 + 1달 → 2/28 (clamp), 8/31 + 1달 → 9/30 (clamp)
  static DateTime _addMonths(DateTime start, int months) {
    final rawMonth = start.month + months;
    final targetYear = start.year + (rawMonth - 1) ~/ 12;
    final targetMonth = ((rawMonth - 1) % 12) + 1;
    final lastDayOfTarget = DateTime(targetYear, targetMonth + 1, 0).day;
    final targetDay = start.day.clamp(1, lastDayOfTarget);
    return DateTime(targetYear, targetMonth, targetDay);
  }

  /// 주어진 시작일에서 계약 종료일 계산 (preset 타입 전용)
  ///
  /// 규칙 (inclusive 계약기간):
  ///   15일:    start + 14일 (시작일 포함 15일)
  ///   월 단위: (start + N달) - 1일
  ///   연 단위: (start + 12달) - 1일
  ///
  /// 예: 8/17 + 1개월 → 9/17 - 1일 = 9/16
  ///     8/17 + 1년   → 2027/8/17 - 1일 = 2027/8/16
  ///     1/31 + 1개월 → 2/28(clamp) - 1일 = 2/27
  DateTime computeContractEndDate(DateTime startDate) {
    switch (contractPeriodType) {
      case '15days':
        // 시작일 포함 15일 = start + 14일
        return startDate.add(const Duration(days: 14));
      case '1month':
        return _addMonths(startDate, 1).subtract(const Duration(days: 1));
      case '3months':
        return _addMonths(startDate, 3).subtract(const Duration(days: 1));
      case '6months':
        return _addMonths(startDate, 6).subtract(const Duration(days: 1));
      case '1year':
        return _addMonths(startDate, 12).subtract(const Duration(days: 1));
      default:
        return rangeEnd ?? startDate;
    }
  }

  String get contractPeriodDisplay {
    if (!isContractType) return '';
    if (hasPresetPeriod) {
      // preset: 근무 시작 가능기간 + 계약기간 표시
      if (hasWorkStartAvailableRange) {
        return '근무 시작 가능 ${FormatHelper.formatDate(workStartAvailableFrom!)} ~ '
            '${FormatHelper.formatDate(workStartAvailableUntil!)} ($contractPeriodLabel)';
      }
      // legacy preset: 기간 레이블만 표시
      return contractPeriodLabel;
    }
    // custom: 고정 근무기간
    if (rangeStart == null || rangeEnd == null) return '';
    return '근무기간 ${FormatHelper.formatDate(rangeStart!)} ~ ${FormatHelper.formatDate(rangeEnd!)}';
  }

  String get workDaysLabel {
    if (!isContractType || workDays.isEmpty) return '';
    final count = workDays.length;
    if (count == 7) return '매일 근무';
    if (count == 6) {
      final all = ['월', '화', '수', '목', '금', '토', '일'];
      final off = all.firstWhere((d) => !workDays.contains(d));
      return '주 6일 ($off 휴무)';
    }
    if (count == 5) {
      final all = ['월', '화', '수', '목', '금', '토', '일'];
      final off = all.where((d) => !workDays.contains(d)).join(', ');
      return '주 5일 ($off 휴무)';
    }
    return '주 $count일 (${workDays.join(', ')})';
  }

  // ── 예약 공개 ─────────────────────────────────────

  String? get publishAtDisplay =>
      publishAt != null ? FormatHelper.formatDateTime(publishAt!) : null;

  // ── 인원 ─────────────────────────────────────────

  /// 남은 모집 인원 — 확정 초과 시(데이터 불일치 등) 0으로 클램핑
  /// (totalConfirmed가 totalRequired를 초과하더라도 음수 노출 방지 — A09)
  int get availableSlots => (totalRequired - totalConfirmed).clamp(0, totalRequired);

  // ── 마감 상태 (contract용) ────────────────────────

  bool get isDeadlinePassed {
    if (applicationDeadline == null) return false;
    return DateTime.now().isAfter(applicationDeadline!);
  }

  // ── 게시 만료 (contract용, postingDurationDays 기반) ─────────

  /// 게시 만료일: 서버 저장값 우선, 없으면 publishAt(또는 createdAt) + postingDurationDays 계산
  DateTime? get postingExpiryDate {
    if (postingExpiryDateServer != null) return postingExpiryDateServer;
    if (postingDurationDays == null) return null;
    final base = publishAt ?? createdAt;
    return base.add(Duration(days: postingDurationDays!));
  }

  /// "MM/DD" 형식 게시 만료일 (null = 무기한)
  String? get formattedPostingExpiry {
    final d = postingExpiryDate;
    if (d == null) return null;
    return '${d.month}/${d.day}';
  }

  bool get isPostingExpired {
    final d = postingExpiryDate;
    if (d == null) return false;
    // 만료일 당일은 표시, 다음날 00:00(KST) 이후 숨김
    final now = DateTime.now();
    return FormatHelper.toKstDate(now).isAfter(FormatHelper.toKstDate(d));
  }

  /// 게시기간 만료 마감이고 연장 가능
  /// 종료일 여유 검사는 CF(callableExtendPosting)에서 처리
  bool get isPostingExpiredAndExtendable {
    if (!isContractType) return false;
    if (status != TOStatus.closed) return false;
    if (closedReasonCode != 'POSTING_EXPIRED') return false;
    return true;
  }

  String get closedReason {
    if (isManualClosed) return '수동 마감';
    if (isFull) return '인원 충족';
    if (status == TOStatus.expired) return '슬롯 만료';
    if (isDeadlinePassed) return '지원 마감';
    if (isPostingExpired) return '게시 기간 만료';
    return '';
  }

  @override
  String toString() =>
      'TOModel(id: $id, type: $type, title: $title, status: $status, '
      'slots: $totalSlots, workDetails: ${workDetails.length})';

  // ── 하위 호환성 getters ───────────────────────────────────────
  // 구 아키텍처(groups/date 기반)에서 마이그레이션 중인 화면에서 사용.
  // Phase 5-6 리팩터링 완료 후 제거 예정.

  /// 공고 대표 날짜
  /// - flex(단기): createdAt
  /// - contract custom: rangeStart (고정 계약 시작일)
  /// - contract preset 신규: workStartAvailableFrom (근무 시작 가능 첫날)
  /// - contract preset legacy(신규 필드 없음): rangeStart (기존 동작 유지)
  DateTime get date => rangeStart ?? workStartAvailableFrom ?? createdAt;

  /// isContractType 별칭
  bool get isLongTerm => isContractType;

  /// isFlexType 별칭
  bool get isShortTerm => isFlexType;

  /// 공고 자체의 계약 종료일
  /// - preset 장기공고: null
  ///   (지원자마다 희망 시작일이 달라 TO 단일 종료일 없음 — computeContractEndDate 사용)
  /// - custom 장기공고: rangeEnd (고정 종료일)
  /// - 단기(flex): null
  DateTime? get endDate {
    if (hasPresetPeriod) return null;
    return rangeEnd;
  }

  /// rangeStart 별칭
  DateTime? get startDate => rangeStart;

  /// type 별칭 (구 jobType)
  String get jobType => type;

  /// typeLabel 별칭 (구 jobTypeLabel)
  String get jobTypeLabel => typeLabel;

  /// MM/dd 형식 날짜
  String get formattedDate {
    final d = date;
    return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}';
  }

  /// 마감일 표시
  String get formattedDeadline {
    final dl = applicationDeadline;
    return dl != null ? FormatHelper.formatDateTime(dl) : '-';
  }

  /// 실질 마감시각 — applicationDeadline 우선, 없으면 HOURS_BEFORE 계산
  /// user_to_card / 마감임박 판단의 단일 소스
  /// 공고 레벨 마감 시각 — 저장된 값만 반환 (contract TO: 지원 마감일)
  DateTime? get effectiveDeadline => applicationDeadline;

  /// 마감 30분 이내 여부
  bool get isDeadlineSoon {
    final dl = effectiveDeadline;
    if (dl == null) return false;
    final diff = dl.difference(DateTime.now()).inMinutes;
    return diff >= 0 && diff <= 30;
  }

  /// 마감 24시간 이내 여부 (유저 카드 "마감임박" 뱃지 기준)
  bool get isDeadlineUrgent {
    final dl = effectiveDeadline;
    if (dl == null) return false;
    final hours = dl.difference(DateTime.now()).inHours;
    return hours >= 0 && hours <= 24;
  }

  /// 날짜 범위 표시 (구 groupDateRangeDisplay)
  String get groupDateRangeDisplay => contractPeriodDisplay;

  /// 마감시간 초과 여부 (구 isTimeExpired)
  bool get isTimeExpired => isDeadlinePassed;

  /// 첫 번째 업무의 시작 시간 (구 startTime)
  String get startTime {
    if (workDetails.isEmpty) return '--:--';
    final starts = workDetails.map((d) => d.startTime).toList()..sort();
    return starts.first;
  }

  /// 마지막 업무의 종료 시간 (구 endTime)
  String get endTime {
    if (workDetails.isEmpty) return '--:--';
    final ends = workDetails.map((d) => d.endTime).toList()..sort();
    return ends.last;
  }

  /// 구 그룹 시간 범위 설정 — no-op (TO는 불변 객체, 이 필드 제거됨)
  // ignore: use_setters_to_change_properties
  void setTimeRange(String? minStart, String? maxEnd) {}
}

/// TO 타입 상수 (to 컬렉션 type 필드)
abstract class TOType {
  static const String contract = 'contract'; // 장기 고정 근무
  static const String flex     = 'flex';     // 단기 날짜별 근무
}

/// TO Firestore 상태 상수 (대문자 — TO 컬렉션 convention)
abstract class TOStatus {
  static const String active    = 'ACTIVE';
  static const String closed    = 'CLOSED';
  static const String full      = 'FULL';
  static const String expired   = 'EXPIRED';
  static const String scheduled = 'SCHEDULED';
  /// 미공개(초안) — 관리자에게만 보이고 지원자에게 비공개
  static const String draft     = 'DRAFT';

  /// 모집 중 상태 그룹 (Firestore whereIn 쿼리용 — 관리자 TO 목록용)
  /// 주의: 지원자 공개 기준은 isPublished=true + [ACTIVE, FULL] — CF에서 처리
  static const List<String> openStates   = [active, full, scheduled];
  /// 마감 상태 그룹
  static const List<String> closedStates = [closed, expired];
}
