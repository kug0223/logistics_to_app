import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'wage_detail_model.dart';
import '../../utils/firestore_helper.dart';

/// 출근 기록 모델
class AttendanceModel {
  // ── DB status 상수 ──────────────────────────────────────────
  static const String statusPresent    = 'present';
  static const String statusLate       = 'late';
  static const String statusEarlyLeave = 'early_leave';
  static const String statusAbsent     = 'absent';
  static const String statusNoShow     = 'NO_SHOW';

  // ── wageStatus 상수 ─────────────────────────────────────────
  static const String wagePending     = 'pending';
  static const String wageCalculated  = 'calculated';
  static const String wageConfirmed   = 'confirmed';
  static const String wageTransferred = 'transferred'; // 송금 완료
  final String id;
  final String applicationId;    // 소속 지원서 ID
  final String userId;
  final String businessId;
  final String businessName;
  
  // 근무 정보
  final DateTime workDate;       // 실제 근무일
  final String workType;         // 업무 유형
  
  // 출근 정보
  final String? checkIn;         // "09:05:23"
  final String? originalCheckIn; // 근무자가 최초 체크한 출근 시각 (관리자 수정 이전값 보존)
  final double? checkInLat;
  final double? checkInLng;
  final String? checkInMethod;   // "gps" | "beacon" | "manual"
  final DateTime? checkInTime;   // Timestamp

  // 퇴근 정보
  final String? checkOut;        // "18:10:45"
  final String? originalCheckOut; // 근무자가 최초 체크한 퇴근 시각
  final double? checkOutLat;
  final double? checkOutLng;
  final String? checkOutMethod;  // "gps" | "beacon" | "manual"
  final DateTime? checkOutTime;  // Timestamp
  
  // 상태
  final String status;           // "present" | "absent" | "late" | "early_leave"
  
  // 수정 관리
  final bool isModified;
  final bool modifyRequested;    // 지원자가 수정 요청
  final String? modifyReason;
  final String? modifiedBy;
  final DateTime? modifiedAt;
  
  // 급여 계산
  final double? workHours;
  final int? calculatedWage;       // ⚠️ 하위 호환용 (deprecated)
  
  // 관리자 확인 (⚠️ 하위 호환용 - deprecated)
  final String? confirmedBy;
  final DateTime? confirmedAt;
  
  // ========== 급여 관련 (신규) ==========
  /// 급여 상태 - 'pending' | 'calculated' | 'confirmed' | 'transferred'
  final String wageStatus;

  /// 최종 확정된 급여 (인덱싱/쿼리용, confirmed 시 totalAmount 복사)
  final int? finalWage;

  /// 급여 상세 정보 (임베디드)
  final WageDetailModel? wageDetail;

  /// 월별 근무일수 집계용 인덱스 필드 ('yyyy-MM')
  final String? yearMonth;

  // ========== 관리자 확인 (당일명단 워크플로) ==========
  /// 관리자가 출퇴근 확인 완료 처리 — true면 '확인' 탭으로 이동
  final bool adminConfirmed;

  // ========== 지급 예정일 (오늘 처리할 송금 기능) ==========
  /// 급여 확정 시 payScheduleType 기반으로 자동 계산된 지급 예정일
  /// null = 기존 데이터 (수동 처리)
  final DateTime? paymentDueDate;

  // ========== 송금 관련 (transferred 상태) ==========
  /// 송금 완료 일시
  final DateTime? transferDate;
  /// 송금 메모 (이체번호, 메모 등)
  final String? transferNote;
  /// 송금 처리한 관리자 UID
  final String? transferredBy;

  // ========== 서버 측 GPS 검증 결과 ==========
  /// CF onAttendanceCreated가 GPS 좌표를 서버에서 검증한 결과 — 반경 초과 시 true
  final bool checkInSuspicious;
  /// 출근 시 사업장까지 거리 (미터, GPS 방식일 때만 설정)
  final int? checkInDistance;

  final DateTime createdAt;
  final DateTime? updatedAt;

  AttendanceModel({
    required this.id,
    required this.applicationId,
    required this.userId,
    required this.businessId,
    required this.businessName,
    required this.workDate,
    required this.workType,
    this.checkIn,
    this.originalCheckIn,
    this.checkInLat,
    this.checkInLng,
    this.checkInMethod,
    this.checkInTime,
    this.checkOut,
    this.originalCheckOut,
    this.checkOutLat,
    this.checkOutLng,
    this.checkOutMethod,
    this.checkOutTime,
    required this.status,
    this.isModified = false,
    this.modifyRequested = false,
    this.modifyReason,
    this.modifiedBy,
    this.modifiedAt,
    this.workHours,
    this.calculatedWage,
    this.confirmedBy,
    this.confirmedAt,
    required this.createdAt,
    this.updatedAt,
    // 급여 관련 (신규)
    this.wageStatus = 'pending',
    this.finalWage,
    this.wageDetail,
    this.yearMonth,
    this.adminConfirmed = false,
    this.paymentDueDate,
    // 송금 관련
    this.transferDate,
    this.transferNote,
    this.transferredBy,
    // 서버 GPS 검증
    this.checkInSuspicious = false,
    this.checkInDistance,
  });

  /// Firestore → AttendanceModel
  factory AttendanceModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) {
      throw ArgumentError('AttendanceModel.fromFirestore: 문서 데이터 없음 (id: ${doc.id})');
    }
    return AttendanceModel.fromMap(raw as Map<String, dynamic>, doc.id);
  }

  // [SCHEMA-09] 역직렬화 실패 격리 — 손상 문서 1건이 목록 전체 크래시 방지
  // 목록 조회: snap.docs.map(tryFromFirestore).whereType<AttendanceModel>().toList()
  static AttendanceModel? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return AttendanceModel.fromFirestore(doc);
    } catch (e, st) {
      debugPrint('[AttendanceModel] 역직렬화 실패 id=${doc.id}: $e\n$st');
      return null;
    }
  }

  /// Map → AttendanceModel
  factory AttendanceModel.fromMap(Map<String, dynamic> map, String id) {
    return AttendanceModel(
      id: id,
      applicationId: map['applicationId'] ?? '',
      userId: map['userId'] ?? '',
      businessId: map['businessId'] ?? '',
      businessName: map['businessName'] ?? '',
      workDate: map['workDate'] != null
          ? parseTimestamp(map['workDate'])
          : (throw ArgumentError('AttendanceModel: workDate 필드 누락 (id: $id)')),
      workType: map['workType'] ?? '',
      checkIn: map['checkIn'],
      originalCheckIn: map['originalCheckIn'] as String?,
      checkInLat: (map['checkInLat'] as num?)?.toDouble(),
      checkInLng: (map['checkInLng'] as num?)?.toDouble(),
      checkInMethod: map['checkInMethod'],
      checkInTime: parseTimestampNullable(map['checkInTime']),
      checkOut: map['checkOut'],
      originalCheckOut: map['originalCheckOut'] as String?,
      checkOutLat: (map['checkOutLat'] as num?)?.toDouble(),
      checkOutLng: (map['checkOutLng'] as num?)?.toDouble(),
      checkOutMethod: map['checkOutMethod'],
      checkOutTime: parseTimestampNullable(map['checkOutTime']),
      status: map['status'] ?? 'absent',
      isModified: map['isModified'] ?? false,
      modifyRequested: map['modifyRequested'] ?? false,
      modifyReason: map['modifyReason'],
      modifiedBy: map['modifiedBy'],
      modifiedAt: parseTimestampNullable(map['modifiedAt']),
      workHours: (map['workHours'] as num?)?.toDouble(),
      calculatedWage: (map['calculatedWage'] as num?)?.toInt(),
      confirmedBy: map['confirmedBy'],
      confirmedAt: parseTimestampNullable(map['confirmedAt']),
      createdAt: map['createdAt'] != null
          ? parseTimestamp(map['createdAt'])
          : (throw ArgumentError('AttendanceModel: createdAt 필드 누락 (id: $id)')),
      updatedAt: parseTimestampNullable(map['updatedAt']),
      // 급여 관련 (신규)
      wageStatus: map['wageStatus'] ?? 'pending',
      finalWage: (map['finalWage'] as num?)?.toInt(),
      wageDetail: map['wageDetail'] != null
          ? WageDetailModel.tryFromMap(Map<String, dynamic>.from(map['wageDetail'] as Map))
          : null,
      yearMonth: map['yearMonth'] as String?,
      adminConfirmed: map['adminConfirmed'] ?? false,
      paymentDueDate: parseTimestampNullable(map['paymentDueDate']),
      // 송금 관련
      transferDate: parseTimestampNullable(map['transferDate']),
      transferNote: map['transferNote'] as String?,
      transferredBy: map['transferredBy'] as String?,
      // 서버 GPS 검증
      checkInSuspicious: map['checkInSuspicious'] as bool? ?? false,
      checkInDistance: (map['checkInDistance'] as num?)?.toInt(),
    );
  }

  /// AttendanceModel → Map
  Map<String, dynamic> toMap() {
    return {
      'applicationId': applicationId,
      'userId': userId,
      'businessId': businessId,
      'businessName': businessName,
      'workDate': Timestamp.fromDate(workDate),
      'workType': workType,
      'checkIn': checkIn,
      'originalCheckIn': originalCheckIn,
      'checkInLat': checkInLat,
      'checkInLng': checkInLng,
      'checkInMethod': checkInMethod,
      'checkInTime': checkInTime != null 
          ? Timestamp.fromDate(checkInTime!) 
          : null,
      'checkOut': checkOut,
      'originalCheckOut': originalCheckOut,
      'checkOutLat': checkOutLat,
      'checkOutLng': checkOutLng,
      'checkOutMethod': checkOutMethod,
      'checkOutTime': checkOutTime != null
          ? Timestamp.fromDate(checkOutTime!)
          : null,
      'status': status,
      'isModified': isModified,
      'modifyRequested': modifyRequested,
      'modifyReason': modifyReason,
      'modifiedBy': modifiedBy,
      'modifiedAt': modifiedAt != null
          ? Timestamp.fromDate(modifiedAt!)
          : null,
      'workHours': workHours,
      'calculatedWage': calculatedWage,
      'confirmedBy': confirmedBy,
      'confirmedAt': confirmedAt != null
          ? Timestamp.fromDate(confirmedAt!)
          : null,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': updatedAt != null
          ? Timestamp.fromDate(updatedAt!)
          : null,
      // 급여 관련 (신규)
      'wageStatus': wageStatus,
      'finalWage': finalWage,
      'wageDetail': wageDetail?.toMap(),
      if (yearMonth != null) 'yearMonth': yearMonth,
      if (adminConfirmed) 'adminConfirmed': adminConfirmed,
      if (paymentDueDate != null)
        'paymentDueDate': Timestamp.fromDate(paymentDueDate!),
      // 송금 관련
      if (transferDate != null)
        'transferDate': Timestamp.fromDate(transferDate!),
      if (transferNote != null) 'transferNote': transferNote,
      if (transferredBy != null) 'transferredBy': transferredBy,
      // 서버 GPS 검증 (CF 전용 필드, 클라이언트는 읽기만)
      if (checkInSuspicious) 'checkInSuspicious': checkInSuspicious,
      if (checkInDistance != null) 'checkInDistance': checkInDistance,
    };
  }

  /// 출근 여부
  bool get hasCheckedIn => checkIn != null;

  /// 퇴근 여부
  bool get hasCheckedOut => checkOut != null;

  /// 지각 여부
  bool get isLate => status == statusLate;

  /// 조퇴 여부
  bool get isEarlyLeave => status == statusEarlyLeave;

  /// 노쇼 여부
  bool get isNoShow => status == statusNoShow;

  /// 결근 여부
  bool get isAbsent => status == statusAbsent;

  /// 퇴근 미체크 여부 (출근했지만 퇴근 기록 없음, 노쇼 제외)
  bool get isMissedCheckout => hasCheckedIn && !hasCheckedOut && !isNoShow;

  /// 출근 상태 라벨
  String get statusLabel {
    switch (status) {
      case statusPresent:
        return '출근';
      case statusLate:
        return '지각';
      case statusAbsent:
        return '결근';
      case statusEarlyLeave:
        return '조퇴';
      case statusNoShow:
        return '노쇼';
      default:
        return '미출근';
    }
  }

  // ========== 급여 관련 Getter ==========
  
  /// 급여 미계산 상태
  bool get isWagePending => wageStatus == wagePending;

  /// 급여 1차 확정 상태 (관리자 검토중)
  bool get isWageCalculated => wageStatus == wageCalculated;

  /// 급여 최종 확정 상태 (지원자 노출)
  bool get isWageConfirmed => wageStatus == wageConfirmed;

  /// 송금 완료 상태
  bool get isWageTransferred => wageStatus == wageTransferred;

  /// 급여 상태 라벨
  String get wageStatusLabel {
    switch (wageStatus) {
      case wagePending:
        return '미계산';
      case wageCalculated:
        return '검토중';
      case wageConfirmed:
        return '확정';
      case wageTransferred:
        return '송금완료';
      default:
        return '미계산';
    }
  }
  
  /// 표시용 급여 (지원자용 - confirmed·transferred 모두 표시)
  /// [SAFE] 확정 전 null 반환(→ UI에서 '-')은 의도된 설계.
  /// 관리자가 확정 시 출퇴근 시간을 조정할 수 있어 예상 금액이 최종 금액과 달라짐.
  /// wageDetail.effectiveNetWage로 예상치를 노출하면 혼란 유발 — 현행 유지.
  int? get displayWage => (isWageConfirmed || isWageTransferred) ? finalWage : null;
  
  /// 포맷팅된 표시용 급여
  String get formattedDisplayWage {
    if (displayWage == null) return '-';
    return '${displayWage.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}원';
  }

  /// 복사
  AttendanceModel copyWith({
    String? id,
    String? applicationId,
    String? userId,
    String? businessId,
    String? businessName,
    DateTime? workDate,
    String? workType,
    String? checkIn,
    String? originalCheckIn,
    double? checkInLat,
    double? checkInLng,
    String? checkInMethod,
    DateTime? checkInTime,
    String? checkOut,
    String? originalCheckOut,
    double? checkOutLat,
    double? checkOutLng,
    String? checkOutMethod,
    DateTime? checkOutTime,
    String? status,
    bool? isModified,
    bool? modifyRequested,
    String? modifyReason,
    String? modifiedBy,
    DateTime? modifiedAt,
    double? workHours,
    int? calculatedWage,
    String? confirmedBy,
    DateTime? confirmedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    // 급여 관련 (신규)
    String? wageStatus,
    int? finalWage,
    WageDetailModel? wageDetail,
    String? yearMonth,
    bool? adminConfirmed,
    DateTime? paymentDueDate,
    // 송금 관련
    DateTime? transferDate,
    String? transferNote,
    String? transferredBy,
    // 서버 GPS 검증
    bool? checkInSuspicious,
    int? checkInDistance,
  }) {
    return AttendanceModel(
      id: id ?? this.id,
      applicationId: applicationId ?? this.applicationId,
      userId: userId ?? this.userId,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      workDate: workDate ?? this.workDate,
      workType: workType ?? this.workType,
      checkIn: checkIn ?? this.checkIn,
      originalCheckIn: originalCheckIn ?? this.originalCheckIn,
      checkInLat: checkInLat ?? this.checkInLat,
      checkInLng: checkInLng ?? this.checkInLng,
      checkInMethod: checkInMethod ?? this.checkInMethod,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOut: checkOut ?? this.checkOut,
      originalCheckOut: originalCheckOut ?? this.originalCheckOut,
      checkOutLat: checkOutLat ?? this.checkOutLat,
      checkOutLng: checkOutLng ?? this.checkOutLng,
      checkOutMethod: checkOutMethod ?? this.checkOutMethod,
      checkOutTime: checkOutTime ?? this.checkOutTime,
      status: status ?? this.status,
      isModified: isModified ?? this.isModified,
      modifyRequested: modifyRequested ?? this.modifyRequested,
      modifyReason: modifyReason ?? this.modifyReason,
      modifiedBy: modifiedBy ?? this.modifiedBy,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      workHours: workHours ?? this.workHours,
      calculatedWage: calculatedWage ?? this.calculatedWage,
      confirmedBy: confirmedBy ?? this.confirmedBy,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      // 급여 관련 (신규)
      wageStatus: wageStatus ?? this.wageStatus,
      finalWage: finalWage ?? this.finalWage,
      wageDetail: wageDetail ?? this.wageDetail,
      yearMonth: yearMonth ?? this.yearMonth,
      adminConfirmed: adminConfirmed ?? this.adminConfirmed,
      paymentDueDate: paymentDueDate ?? this.paymentDueDate,
      // 송금 관련
      transferDate: transferDate ?? this.transferDate,
      transferNote: transferNote ?? this.transferNote,
      transferredBy: transferredBy ?? this.transferredBy,
      // 서버 GPS 검증
      checkInSuspicious: checkInSuspicious ?? this.checkInSuspicious,
      checkInDistance: checkInDistance ?? this.checkInDistance,
    );
  }
}