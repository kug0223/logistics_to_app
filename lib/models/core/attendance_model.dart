import 'package:cloud_firestore/cloud_firestore.dart';
import 'wage_detail_model.dart';

/// 출근 기록 모델
class AttendanceModel {
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
  final double? checkInLat;
  final double? checkInLng;
  final String? checkInMethod;   // "gps" | "beacon" | "manual"
  final DateTime? checkInTime;   // Timestamp
  
  // 퇴근 정보
  final String? checkOut;        // "18:10:45"
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
  /// 급여 상태 - 'pending' | 'calculated' | 'confirmed'
  final String wageStatus;
  
  /// 최종 확정된 급여 (인덱싱/쿼리용, confirmed 시 totalAmount 복사)
  final int? finalWage;
  
  /// 급여 상세 정보 (임베디드)
  final WageDetailModel? wageDetail;
  
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
    this.checkInLat,
    this.checkInLng,
    this.checkInMethod,
    this.checkInTime,
    this.checkOut,
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
  });

  /// Firestore → AttendanceModel
  factory AttendanceModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AttendanceModel.fromMap(data, doc.id);
  }

  /// Map → AttendanceModel
  factory AttendanceModel.fromMap(Map<String, dynamic> map, String id) {
    return AttendanceModel(
      id: id,
      applicationId: map['applicationId'] ?? '',
      userId: map['userId'] ?? '',
      businessId: map['businessId'] ?? '',
      businessName: map['businessName'] ?? '',
      workDate: (map['workDate'] as Timestamp).toDate(),
      workType: map['workType'] ?? '',
      checkIn: map['checkIn'],
      checkInLat: map['checkInLat']?.toDouble(),
      checkInLng: map['checkInLng']?.toDouble(),
      checkInMethod: map['checkInMethod'],
      checkInTime: map['checkInTime'] != null 
          ? (map['checkInTime'] as Timestamp).toDate().toLocal()  // 🔥 .toLocal() 추가
          : null,
      checkOut: map['checkOut'],
      checkOutLat: map['checkOutLat']?.toDouble(),
      checkOutLng: map['checkOutLng']?.toDouble(),
      checkOutMethod: map['checkOutMethod'],
      checkOutTime: map['checkOutTime'] != null
          ? (map['checkOutTime'] as Timestamp).toDate().toLocal()  // 🔥 .toLocal() 추가
          : null,
      status: map['status'] ?? 'absent',
      isModified: map['isModified'] ?? false,
      modifyRequested: map['modifyRequested'] ?? false,
      modifyReason: map['modifyReason'],
      modifiedBy: map['modifiedBy'],
      modifiedAt: map['modifiedAt'] != null
          ? (map['modifiedAt'] as Timestamp).toDate().toLocal()  // 🔥 .toLocal() 추가
          : null,
      workHours: map['workHours']?.toDouble(),
      calculatedWage: map['calculatedWage'],
      confirmedBy: map['confirmedBy'],
      confirmedAt: map['confirmedAt'] != null
          ? (map['confirmedAt'] as Timestamp).toDate().toLocal()
          : null,
      createdAt: (map['createdAt'] as Timestamp).toDate(),
      updatedAt: map['updatedAt'] != null
          ? (map['updatedAt'] as Timestamp).toDate()
          : null,
      // 급여 관련 (신규)
      wageStatus: map['wageStatus'] ?? 'pending',
      finalWage: map['finalWage'],
      wageDetail: map['wageDetail'] != null
          ? WageDetailModel.fromMap(map['wageDetail'] as Map<String, dynamic>)
          : null,
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
      'checkInLat': checkInLat,
      'checkInLng': checkInLng,
      'checkInMethod': checkInMethod,
      'checkInTime': checkInTime != null 
          ? Timestamp.fromDate(checkInTime!) 
          : null,
      'checkOut': checkOut,
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
    };
  }

  /// 출근 여부
  bool get hasCheckedIn => checkIn != null;

  /// 퇴근 여부
  bool get hasCheckedOut => checkOut != null;

  /// 지각 여부
  bool get isLate => status == 'late';

  /// 출근 상태 라벨
  String get statusLabel {
    switch (status) {
      case 'present':
        return '출근';
      case 'late':
        return '지각';
      case 'absent':
        return '결근';
      case 'early_leave':
        return '조퇴';
      default:
        return '미출근';
    }
  }

  // ========== 급여 관련 Getter ==========
  
  /// 급여 미계산 상태
  bool get isWagePending => wageStatus == 'pending';
  
  /// 급여 1차 확정 상태 (관리자 검토중)
  bool get isWageCalculated => wageStatus == 'calculated';
  
  /// 급여 최종 확정 상태 (지원자 노출)
  bool get isWageConfirmed => wageStatus == 'confirmed';
  
  /// 급여 상태 라벨
  String get wageStatusLabel {
    switch (wageStatus) {
      case 'pending':
        return '미계산';
      case 'calculated':
        return '검토중';
      case 'confirmed':
        return '확정';
      default:
        return '미계산';
    }
  }
  
  /// 표시용 급여 (지원자용 - confirmed만 표시)
  int? get displayWage => isWageConfirmed ? finalWage : null;
  
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
    double? checkInLat,
    double? checkInLng,
    String? checkInMethod,
    DateTime? checkInTime,
    String? checkOut,
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
      checkInLat: checkInLat ?? this.checkInLat,
      checkInLng: checkInLng ?? this.checkInLng,
      checkInMethod: checkInMethod ?? this.checkInMethod,
      checkInTime: checkInTime ?? this.checkInTime,
      checkOut: checkOut ?? this.checkOut,
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
    );
  }
}