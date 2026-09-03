import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'wage_detail_model.dart';
import '../../utils/firestore_helper.dart';
import '../../utils/encryption_helper.dart';

/// 출근 기록 모델
///
/// ## 시간 필드 설계 (v2 — DateTime 기반)
///
/// 모든 시각은 [DateTime] (Firestore Timestamp)으로 저장한다.
/// - [checkInAt]        : 반올림 적용 후 최종 출근 시각 (관리자 수정 가능)
/// - [checkOutAt]       : 반올림 적용 후 최종 퇴근 시각 (관리자 수정 가능)
/// - [originalCheckInAt]: GPS/비콘 원본 출근 시각 (절대 불변)
/// - [originalCheckOutAt]: GPS/비콘 원본 퇴근 시각 (절대 불변)
///
/// 표시용 "HH:mm" 문자열은 getter [checkIn] / [checkOut] 등을 사용한다.
/// 날짜가 포함된 [DateTime]을 사용하므로 야간 교대·자정 출근 등
/// 모든 경계가 특수 처리 없이 올바르게 계산된다.
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
  static const String wageTransferred = 'transferred';

  final String id;
  final String applicationId;
  final String userId;
  final String businessId;
  final String businessName;

  // 근무 정보
  final DateTime workDate;
  final String workType;

  // ── 출근 시각 (DateTime 기반) ────────────────────────────────
  /// 반올림 적용 후 최종 출근 시각 (Firestore: Timestamp)
  final DateTime? checkInAt;
  /// GPS/비콘 원본 출근 시각 — 절대 불변
  final DateTime? originalCheckInAt;
  final double? checkInLat;
  final double? checkInLng;
  final String? checkInMethod;   // "gps" | "beacon" | "manual"

  // ── 퇴근 시각 (DateTime 기반) ────────────────────────────────
  /// 반올림 적용 후 최종 퇴근 시각 (Firestore: Timestamp)
  final DateTime? checkOutAt;
  /// GPS/비콘 원본 퇴근 시각 — 절대 불변
  final DateTime? originalCheckOutAt;
  final double? checkOutLat;
  final double? checkOutLng;
  final String? checkOutMethod;  // "gps" | "beacon" | "manual"

  // 상태
  final String status;
  final bool isZeroWork;

  // 수정 관리
  final bool isModified;
  final bool modifyRequested;
  final String? modifyReason;
  final String? modifiedBy;
  final DateTime? modifiedAt;

  // 급여 계산
  final double? workHours;
  final int? calculatedWage;     // ⚠️ 하위 호환용 (deprecated)

  // 관리자 확인 (⚠️ 하위 호환용 - deprecated)
  final String? confirmedBy;
  final DateTime? confirmedAt;

  // 급여 관련
  final String wageStatus;
  final int? finalWage;
  final WageDetailModel? wageDetail;
  final String? yearMonth;

  // 관리자 확인 플래그
  final bool adminConfirmed;

  // 지급 예정일
  final DateTime? paymentDueDate;

  // 송금 관련
  final DateTime? transferDate;
  final String? transferNote;
  final String? transferredBy;

  // 서버 측 GPS 검증
  final bool checkInSuspicious;
  final int? checkInDistance;

  // 파트전환 대비 — 체크인 시점 임금 스냅샷 (CF callableCheckIn에서 저장)
  // 파트전환 후 급여 계산 시 이 값을 우선 사용 → 전환 전 날짜는 구 임금으로 정확히 계산
  final int? snapshotWage;
  final String? snapshotWageType;

  // ── 급여 이체 계좌 스냅샷 ─────────────────────────────────────
  // callableConfirmFinalWage 시점에 User 문서에서 복사 (복호화 없음, AES 암호문 그대로)
  // 이후 User 계좌 변경과 무관하게 확정 시점 계좌로 이체 처리 가능
  final String? wageAccountBankName;
  /// AES-CBC 암호문 — 클라이언트 EncryptionHelper.decrypt()로만 복호화 가능
  final String? wageAccountNumberEncrypted;
  final String? wageAccountHolder;
  /// 스냅샷 시점 계좌 인증 상태: 'verified' | 'review_required'
  final String? wageAccountVerificationStatus;
  final DateTime? wageAccountSnapshotAt;
  /// [BATCH-1B] SUPER_ADMIN이 snapshot 계좌를 현재 사용자 계좌와 대조 승격한 시각
  final DateTime? wageAccountVerifiedAt;

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
    this.checkInAt,
    this.originalCheckInAt,
    this.checkInLat,
    this.checkInLng,
    this.checkInMethod,
    this.checkOutAt,
    this.originalCheckOutAt,
    this.checkOutLat,
    this.checkOutLng,
    this.checkOutMethod,
    required this.status,
    this.isZeroWork = false,
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
    this.wageStatus = 'pending',
    this.finalWage,
    this.wageDetail,
    this.yearMonth,
    this.adminConfirmed = false,
    this.paymentDueDate,
    this.transferDate,
    this.transferNote,
    this.transferredBy,
    this.checkInSuspicious = false,
    this.checkInDistance,
    this.snapshotWage,
    this.snapshotWageType,
    // 급여 이체 계좌 스냅샷
    this.wageAccountBankName,
    this.wageAccountNumberEncrypted,
    this.wageAccountHolder,
    this.wageAccountVerificationStatus,
    this.wageAccountSnapshotAt,
    this.wageAccountVerifiedAt,
  });

  // ── 표시용 "HH:mm" getter ───────────────────────────────────

  static const _kst = Duration(hours: 9);
  static String _fmt(DateTime dt) {
    final kst = dt.toUtc().add(_kst);
    return '${kst.hour.toString().padLeft(2, '0')}:${kst.minute.toString().padLeft(2, '0')}';
  }

  // ── 급여 이체 계좌 getter ────────────────────────────────────

  /// 복호화된 계좌번호 (클라이언트 전용 — ENCRYPT_KEY 필요)
  String? get wageAccountNumberDecrypted =>
      wageAccountNumberEncrypted != null
          ? EncryptionHelper.decrypt(wageAccountNumberEncrypted!)
          : null;

  /// 마스킹된 계좌번호 (UI 표시용) — 끝 4자리만 표시
  String? get wageAccountNumberMasked {
    final full = wageAccountNumberDecrypted;
    if (full == null) return null;
    final digits = full.replaceAll(RegExp(r'\D'), '');
    return digits.length >= 4
        ? '****${digits.substring(digits.length - 4)}'
        : '****';
  }

  /// 최종 출근 시각 "HH:mm" (UI 표시용)
  String? get checkIn         => checkInAt        != null ? _fmt(checkInAt!)        : null;
  /// 원본 출근 시각 "HH:mm" (UI 표시용)
  String? get originalCheckIn => originalCheckInAt != null ? _fmt(originalCheckInAt!) : null;
  /// 최종 퇴근 시각 "HH:mm" (UI 표시용)
  String? get checkOut         => checkOutAt        != null ? _fmt(checkOutAt!)        : null;
  /// 원본 퇴근 시각 "HH:mm" (UI 표시용)
  String? get originalCheckOut => originalCheckOutAt != null ? _fmt(originalCheckOutAt!) : null;

  // ── 역직렬화 ─────────────────────────────────────────────────

  factory AttendanceModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) {
      throw ArgumentError('AttendanceModel.fromFirestore: 문서 데이터 없음 (id: ${doc.id})');
    }
    return AttendanceModel.fromMap(raw as Map<String, dynamic>, doc.id);
  }

  static AttendanceModel? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return AttendanceModel.fromFirestore(doc);
    } catch (e, st) {
      debugPrint('[AttendanceModel] 역직렬화 실패 id=${doc.id}: $e\n$st');
      return null;
    }
  }

  static AttendanceModel? tryFromMap(Map<String, dynamic> map, String id) {
    try {
      return AttendanceModel.fromMap(map, id);
    } catch (e, st) {
      debugPrint('[AttendanceModel] tryFromMap 실패 id=$id: $e\n$st');
      return null;
    }
  }

  factory AttendanceModel.fromMap(Map<String, dynamic> map, String id) {
    // ── 시각 파싱 (v2 Timestamp / CF Map / v1 String 모두 처리) ──────
    final checkInAt         = _parseTimeField(map['checkIn'],          map['workDate']);
    final originalCheckInAt = _parseTimeField(map['originalCheckIn'],  map['workDate']);

    // v1 야간교대 보정: String "HH:mm" 파싱 시 항상 workDate 당일로 복원되므로
    // checkOut이 checkIn보다 이전이면 익일로 보정 (예: checkIn 22:00 / checkOut 06:00)
    var checkOutAt         = _parseTimeField(map['checkOut'],         map['workDate']);
    var originalCheckOutAt = _parseTimeField(map['originalCheckOut'], map['workDate']);
    if (checkInAt != null) {
      if (checkOutAt != null && checkOutAt.isBefore(checkInAt)) {
        checkOutAt = checkOutAt.add(const Duration(days: 1));
      }
      if (originalCheckOutAt != null && originalCheckOutAt.isBefore(checkInAt)) {
        originalCheckOutAt = originalCheckOutAt.add(const Duration(days: 1));
      }
    }

    return AttendanceModel(
      id: id,
      applicationId: map['applicationId'] ?? '',
      userId:        map['userId']        ?? '',
      businessId:    map['businessId']    ?? '',
      businessName:  map['businessName']  ?? '',
      workDate: map['workDate'] != null
          ? parseTimestamp(map['workDate'])
          : throw ArgumentError('AttendanceModel: workDate 필드 누락 (id: $id)'),
      workType: map['workType'] ?? '',

      // ── 출근 시각 ──────────────────────────────────────────────
      checkInAt:         checkInAt,
      originalCheckInAt: originalCheckInAt,
      checkInLat:    (map['checkInLat']  as num?)?.toDouble(),
      checkInLng:    (map['checkInLng']  as num?)?.toDouble(),
      checkInMethod: map['checkInMethod'],

      // ── 퇴근 시각 ──────────────────────────────────────────────
      checkOutAt:         checkOutAt,
      originalCheckOutAt: originalCheckOutAt,
      checkOutLat:    (map['checkOutLat']  as num?)?.toDouble(),
      checkOutLng:    (map['checkOutLng']  as num?)?.toDouble(),
      checkOutMethod: map['checkOutMethod'],

      status:           map['status']   ?? 'absent',
      isZeroWork:       map['isZeroWork'] as bool? ?? false,
      isModified:       map['isModified']       ?? false,
      modifyRequested:  map['modifyRequested']  ?? false,
      modifyReason:     map['modifyReason'],
      modifiedBy:       map['modifiedBy'],
      modifiedAt:       parseTimestampNullable(map['modifiedAt']),
      workHours:        (map['workHours']     as num?)?.toDouble(),
      calculatedWage:   (map['calculatedWage'] as num?)?.toInt(),
      confirmedBy:      map['confirmedBy'],
      confirmedAt:      parseTimestampNullable(map['confirmedAt']),
      createdAt: map['createdAt'] != null
          ? parseTimestamp(map['createdAt'])
          : throw ArgumentError('AttendanceModel: createdAt 필드 누락 (id: $id)'),
      updatedAt:        parseTimestampNullable(map['updatedAt']),
      wageStatus:       map['wageStatus']  ?? 'pending',
      finalWage:        (map['finalWage']  as num?)?.toInt(),
      wageDetail: map['wageDetail'] != null
          ? WageDetailModel.tryFromMap(Map<String, dynamic>.from(map['wageDetail'] as Map))
          : null,
      yearMonth:        map['yearMonth']    as String?,
      adminConfirmed:   map['adminConfirmed'] ?? false,
      paymentDueDate:   parseTimestampNullable(map['paymentDueDate']),
      transferDate:     parseTimestampNullable(map['transferDate']),
      transferNote:     map['transferNote']  as String?,
      transferredBy:    map['transferredBy'] as String?,
      checkInSuspicious: map['checkInSuspicious'] as bool? ?? false,
      checkInDistance:   (map['checkInDistance'] as num?)?.toInt(),
      snapshotWage:      (map['snapshotWage']     as num?)?.toInt(),
      snapshotWageType:  map['snapshotWageType']  as String?,
      // 급여 이체 계좌 스냅샷
      wageAccountBankName:             map['wageAccountBankName']             as String?,
      wageAccountNumberEncrypted:      map['wageAccountNumberEncrypted']      as String?,
      wageAccountHolder:               map['wageAccountHolder']               as String?,
      wageAccountVerificationStatus:   map['wageAccountVerificationStatus']   as String?,
      wageAccountSnapshotAt:           parseTimestampNullable(map['wageAccountSnapshotAt']),
      wageAccountVerifiedAt:           parseTimestampNullable(map['wageAccountVerifiedAt']),
    );
  }

  /// v1(String "HH:mm") / v2(Timestamp) 혼용 파싱
  ///
  /// - Timestamp → DateTime 변환
  /// - "HH:mm" String → workDate 기준 DateTime 복원 (v1 하위 호환)
  /// - null → null
  static DateTime? _parseTimeField(dynamic value, dynamic workDateRaw) {
    if (value == null) return null;
    // 기기 타임존과 무관하게 항상 KST(UTC+9)로 반환한다.
    if (value is Timestamp) return value.toDate().toLocal();
    // CF 응답: {_seconds: N, _nanoseconds: N} Map 형식
    if (value is Map) {
      try {
        final s = (value['_seconds'] as num).toInt();
        final ns = (value['_nanoseconds'] as num? ?? 0).toInt();
        return Timestamp(s, ns).toDate().toLocal();
      } catch (_) {
        return null;
      }
    }
    if (value is String && value.length >= 4) {
      // v1: "H:mm"/"HH:mm"/"HH:mm:ss" — workDate 기준으로 복원 (문자열 자체가 KST)
      final parts = value.split(':');
      if (parts.length < 2) return null;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return null;
      if (workDateRaw == null) return null;
      try {
        final wd = workDateRaw is Timestamp
            ? workDateRaw.toDate().toLocal()
            : workDateRaw is Map
                ? Timestamp((workDateRaw['_seconds'] as num).toInt(),
                            (workDateRaw['_nanoseconds'] as num? ?? 0).toInt())
                    .toDate().toLocal()
                : null;
        if (wd == null) return null;
        return DateTime(wd.year, wd.month, wd.day, h, m);
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  // ── 직렬화 ───────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      'applicationId': applicationId,
      'userId':        userId,
      'businessId':    businessId,
      'businessName':  businessName,
      'workDate':      Timestamp.fromDate(workDate),
      'workType':      workType,

      // 출근 시각 — Timestamp 저장
      if (checkInAt != null)
        'checkIn':         Timestamp.fromDate(checkInAt!),
      if (originalCheckInAt != null)
        'originalCheckIn': Timestamp.fromDate(originalCheckInAt!),
      'checkInLat':    checkInLat,
      'checkInLng':    checkInLng,
      'checkInMethod': checkInMethod,

      // 퇴근 시각 — Timestamp 저장
      if (checkOutAt != null)
        'checkOut':         Timestamp.fromDate(checkOutAt!),
      if (originalCheckOutAt != null)
        'originalCheckOut': Timestamp.fromDate(originalCheckOutAt!),
      'checkOutLat':    checkOutLat,
      'checkOutLng':    checkOutLng,
      'checkOutMethod': checkOutMethod,

      'status':          status,
      if (isZeroWork)    'isZeroWork': true,
      'isModified':      isModified,
      'modifyRequested': modifyRequested,
      'modifyReason':    modifyReason,
      'modifiedBy':      modifiedBy,
      if (modifiedAt != null)
        'modifiedAt': Timestamp.fromDate(modifiedAt!),
      'workHours':       workHours,
      'calculatedWage':  calculatedWage,
      'confirmedBy':     confirmedBy,
      if (confirmedAt != null)
        'confirmedAt': Timestamp.fromDate(confirmedAt!),
      'createdAt': Timestamp.fromDate(createdAt),
      if (updatedAt != null)
        'updatedAt': Timestamp.fromDate(updatedAt!),
      'wageStatus': wageStatus,
      'finalWage':  finalWage,
      'wageDetail': wageDetail?.toMap(),
      if (yearMonth != null)     'yearMonth':     yearMonth,
      if (adminConfirmed)        'adminConfirmed': adminConfirmed,
      if (paymentDueDate != null)
        'paymentDueDate': Timestamp.fromDate(paymentDueDate!),
      if (transferDate != null)
        'transferDate': Timestamp.fromDate(transferDate!),
      if (transferNote != null)  'transferNote':  transferNote,
      if (transferredBy != null) 'transferredBy': transferredBy,
      if (checkInSuspicious)       'checkInSuspicious': checkInSuspicious,
      if (checkInDistance != null) 'checkInDistance':   checkInDistance,
      if (snapshotWage != null)    'snapshotWage':      snapshotWage,
      if (snapshotWageType != null)'snapshotWageType':  snapshotWageType,
      // 급여 이체 계좌 스냅샷
      if (wageAccountBankName != null)           'wageAccountBankName':           wageAccountBankName,
      if (wageAccountNumberEncrypted != null)    'wageAccountNumberEncrypted':    wageAccountNumberEncrypted,
      if (wageAccountHolder != null)             'wageAccountHolder':             wageAccountHolder,
      if (wageAccountVerificationStatus != null) 'wageAccountVerificationStatus': wageAccountVerificationStatus,
      if (wageAccountSnapshotAt != null)         'wageAccountSnapshotAt':         Timestamp.fromDate(wageAccountSnapshotAt!),
      if (wageAccountVerifiedAt != null)         'wageAccountVerifiedAt':         Timestamp.fromDate(wageAccountVerifiedAt!),
    };
  }

  // ── 상태 getter ──────────────────────────────────────────────

  bool get hasCheckedIn  => checkInAt  != null;
  bool get hasCheckedOut => checkOutAt != null;
  bool get isLate        => status == statusLate;
  bool get isEarlyLeave  => status == statusEarlyLeave;
  bool get isNoShow      => status == statusNoShow;
  bool get isAbsent      => status == statusAbsent;
  bool get isMissedCheckout => hasCheckedIn && !hasCheckedOut && !isNoShow;

  String get statusLabel {
    switch (status) {
      case statusPresent:    return '출근';
      case statusLate:       return '지각';
      case statusAbsent:     return '결근';
      case statusEarlyLeave: return '조퇴';
      case statusNoShow:     return '노쇼';
      default:               return '미출근';
    }
  }

  // ── 급여 getter ──────────────────────────────────────────────

  bool get isWagePending    => wageStatus == wagePending;
  bool get isWageCalculated => wageStatus == wageCalculated;
  bool get isWageConfirmed  => wageStatus == wageConfirmed;
  bool get isWageTransferred => wageStatus == wageTransferred;

  String get wageStatusLabel {
    switch (wageStatus) {
      case wagePending:     return '미계산';
      case wageCalculated:  return '검토중';
      case wageConfirmed:   return '확정';
      case wageTransferred: return '송금완료';
      default:              return '미계산';
    }
  }

  /// 표시용 급여 (confirmed·transferred 상태일 때만)
  int? get displayWage =>
      (isWageConfirmed || isWageTransferred) ? finalWage : null;

  String get formattedDisplayWage {
    if (displayWage == null) return '-';
    return '${displayWage.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]},',
    )}원';
  }

  // ── copyWith ────────────────────────────────────────────────

  AttendanceModel copyWith({
    String? id,
    String? applicationId,
    String? userId,
    String? businessId,
    String? businessName,
    DateTime? workDate,
    String? workType,
    DateTime? checkInAt,
    DateTime? originalCheckInAt,
    double? checkInLat,
    double? checkInLng,
    String? checkInMethod,
    DateTime? checkOutAt,
    DateTime? originalCheckOutAt,
    double? checkOutLat,
    double? checkOutLng,
    String? checkOutMethod,
    String? status,
    bool? isZeroWork,
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
    String? wageStatus,
    int? finalWage,
    WageDetailModel? wageDetail,
    String? yearMonth,
    bool? adminConfirmed,
    DateTime? paymentDueDate,
    DateTime? transferDate,
    String? transferNote,
    String? transferredBy,
    bool? checkInSuspicious,
    int? checkInDistance,
    int? snapshotWage,
    String? snapshotWageType,
    // 급여 이체 계좌 스냅샷
    String? wageAccountBankName,
    String? wageAccountNumberEncrypted,
    String? wageAccountHolder,
    String? wageAccountVerificationStatus,
    DateTime? wageAccountSnapshotAt,
    DateTime? wageAccountVerifiedAt,
  }) {
    return AttendanceModel(
      id:            id            ?? this.id,
      applicationId: applicationId ?? this.applicationId,
      userId:        userId        ?? this.userId,
      businessId:    businessId    ?? this.businessId,
      businessName:  businessName  ?? this.businessName,
      workDate:      workDate      ?? this.workDate,
      workType:      workType      ?? this.workType,
      checkInAt:         checkInAt         ?? this.checkInAt,
      originalCheckInAt: originalCheckInAt ?? this.originalCheckInAt,
      checkInLat:    checkInLat    ?? this.checkInLat,
      checkInLng:    checkInLng    ?? this.checkInLng,
      checkInMethod: checkInMethod ?? this.checkInMethod,
      checkOutAt:         checkOutAt         ?? this.checkOutAt,
      originalCheckOutAt: originalCheckOutAt ?? this.originalCheckOutAt,
      checkOutLat:    checkOutLat    ?? this.checkOutLat,
      checkOutLng:    checkOutLng    ?? this.checkOutLng,
      checkOutMethod: checkOutMethod ?? this.checkOutMethod,
      status:          status          ?? this.status,
      isZeroWork:      isZeroWork      ?? this.isZeroWork,
      isModified:      isModified      ?? this.isModified,
      modifyRequested: modifyRequested ?? this.modifyRequested,
      modifyReason:    modifyReason    ?? this.modifyReason,
      modifiedBy:      modifiedBy      ?? this.modifiedBy,
      modifiedAt:      modifiedAt      ?? this.modifiedAt,
      workHours:       workHours       ?? this.workHours,
      calculatedWage:  calculatedWage  ?? this.calculatedWage,
      confirmedBy:     confirmedBy     ?? this.confirmedBy,
      confirmedAt:     confirmedAt     ?? this.confirmedAt,
      createdAt:       createdAt       ?? this.createdAt,
      updatedAt:       updatedAt       ?? this.updatedAt,
      wageStatus:      wageStatus      ?? this.wageStatus,
      finalWage:       finalWage       ?? this.finalWage,
      wageDetail:      wageDetail      ?? this.wageDetail,
      yearMonth:       yearMonth       ?? this.yearMonth,
      adminConfirmed:  adminConfirmed  ?? this.adminConfirmed,
      paymentDueDate:  paymentDueDate  ?? this.paymentDueDate,
      transferDate:    transferDate    ?? this.transferDate,
      transferNote:    transferNote    ?? this.transferNote,
      transferredBy:   transferredBy   ?? this.transferredBy,
      checkInSuspicious: checkInSuspicious ?? this.checkInSuspicious,
      checkInDistance:   checkInDistance   ?? this.checkInDistance,
      snapshotWage:      snapshotWage      ?? this.snapshotWage,
      snapshotWageType:  snapshotWageType  ?? this.snapshotWageType,
      wageAccountBankName:           wageAccountBankName           ?? this.wageAccountBankName,
      wageAccountNumberEncrypted:    wageAccountNumberEncrypted    ?? this.wageAccountNumberEncrypted,
      wageAccountHolder:             wageAccountHolder             ?? this.wageAccountHolder,
      wageAccountVerificationStatus: wageAccountVerificationStatus ?? this.wageAccountVerificationStatus,
      wageAccountSnapshotAt:         wageAccountSnapshotAt         ?? this.wageAccountSnapshotAt,
      wageAccountVerifiedAt:         wageAccountVerifiedAt         ?? this.wageAccountVerifiedAt,
    );
  }
}
