import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../utils/format_helper.dart';
import '../../utils/firestore_helper.dart';

/// 지원서 모델 - 업무유형 선택 및 변경 이력 지원
class ApplicationModel {
  final String id; // 문서 ID
  
  
  final String businessId; // 사업장 ID
  final String businessName; // 사업장명
  final String toTitle; // TO 제목
  final DateTime workDate; // 근무 날짜
  final DateTime? workEndDate;       // ⭐ 종료일 (장기용)
  final List<String>? workDays;      // ⭐ 근무 요일 (장기용)
  final String startTime; // 근무 시작 시간
  final String endTime; // 근무 종료 시간
 
  final String uid; // 지원자 UID
  
  // 업무 유형 및 금액
  final String selectedWorkType; // 현재 지원한 업무 유형 (예: "피킹")
  final String? workDetailId;  // ✅ 추가: WorkDetail 고유 ID (composite or legacy)
  final String? wdId;          // [Phase 8.1E.2] immutable WorkDetail canonical ID (wdId from workDetails[].wdId)
  final String? toId;          // ✅ TO 고유 ID
  final String? slotId;        // ✅ 슬롯 ID (flex 타입 공고의 특정 날짜 슬롯)
  final String? groupId;       // Deprecated — 하위 호환용, 신규 공고는 미사용
  final int wage; // 지원 시점의 금액 (업무유형 변경 시 함께 업데이트)
  // 🔥 업무 상세 정보 (UI 표시용)
  final String? wageType;              // 급여 타입 (hourly, daily)
  final String? workTypeIcon;          // 업무 아이콘
  final String? workTypeColor;         // 업무 색상
  final String? workTypeBackgroundColor; // 업무 배경색
  
  // 업무 변경 이력
  final String? originalWorkType; // 최초 지원한 업무 유형 (변경 시에만 값 존재)
  final int? originalWage; // 최초 지원 시 금액
  final DateTime? changedAt; // 업무유형 변경 시각
  final String? changedBy; // 업무유형 변경한 관리자 UID
  
  final String status; // PENDING, CONTRACT_PENDING, CONFIRMED, REJECTED, CANCELED, AUTO_CANCELED
  final DateTime appliedAt; // 지원 시각
  final DateTime? confirmedAt; // 확정 시각 (null 가능)
  final String? confirmedBy; // 확정한 사람 (SYSTEM 또는 관리자 UID)
  // ⭐ Phase 2: 자동 취소 관련 필드
  final DateTime? canceledAt;           // 취소 시각
  final String? cancelReason;           // 'SCHEDULE_CONFLICT', 'USER_CANCELED'
  final String? conflictingAppId;       // 충돌된 지원서 ID
  final String? conflictingBusiness;    // 충돌된 사업장명
  final String? conflictingTime;        // 충돌 시간대 "09:00~18:00"
  
  // ⭐ Phase 2: 메시지 시스템
  final String? applicationMessage;     // 지원 시 지원자 메시지
  final String? confirmMessage;         // 확정 시 관리자 메시지
  final String? rejectMessage;          // 거절 시 관리자 메시지
  final String? cancelMessage;          // 취소 시 관리자 메시지

  // 🔥 Phase A: 퇴사 관리 시스템
  final DateTime? resignRequestedAt;    // 퇴사 요청 시각
  final DateTime? resignRequestDate;    // 퇴사 희망일
  // ⭐ 장기공고 희망 시작일
  final DateTime? desiredStartDate;
  // 🔥 Phase B: 스케줄 변경 관리
  final List<DateTime>? leaveDates;      // 승인된 휴무 날짜들
  final List<DateTime>? extraWorkDates;  // 승인된 추가 근무 날짜들
  // 🔥 상태 변경 이력
  final List<Map<String, dynamic>>? statusHistory;
  final String? resignStatus;           // 'PENDING', 'APPROVED', 'REJECTED', 'AUTO_APPROVED'
  final DateTime? resignApprovedAt;     // 승인 시각
  final String? resignApprovedBy;       // 승인자 UID
  // [BUG-수정] M-4: rejectResignation에서 승인 필드를 잘못 사용하던 문제 해결을 위해 거절 전용 필드 추가
  final DateTime? resignRejectedAt;     // 거절 시각
  final String? resignRejectedBy;       // 거절자 UID
  final String? resignRejectReason;     // 거절 사유
  final DateTime? actualResignDate;     // 실제 퇴사일 (승인된 날짜)
  // 🔥 Phase C: 계약해지 관리 (관리자 → 근무자)
  final String? terminationStatus;          // 'PENDING', 'APPROVED', 'REJECTED', 'AUTO_APPROVED'
  final DateTime? terminationRequestedAt;   // 해지 요청 시각
  final String? terminationReason;          // 해지 사유
  final DateTime? terminationEffectiveDate; // 해지 효력 발생일
  final String? terminationRequestedByUid;  // 요청한 관리자 UID
  final DateTime? terminationRespondedAt;   // 근무자 응답 시각
  final String? terminationRejectReason;    // 근무자 거절 사유

  // 🔄 계약 연장/종료 관리
  final String? renewalDecision;            // 'EXTEND' | 'TERMINATE' (관리자 선택)
  final DateTime? renewalNotifiedAt;        // D-15 알림 발송 시각
  final String? renewedFromApplicationId;   // 연장 시 이전 계약 Application ID

  /// 지원 유형: 'long_term' (장기/고정) | 'short' (단기)
  final String? applicationType;

  /// 관리자 관심표시 여부
  final bool isStarred;

  /// [A4] 계약서 요청 마지막 시각 — CF 서버 타임스탬프 (24h 쿨다운 서버 강제)
  final DateTime? lastContractRequestedAt;

  /// 지원 시점 성명 스냅샷 — CF/더미생성이 users/{uid}.name 을 비정규화해 저장
  /// getUsersBatch CF 미반환 시 폴백 표시용
  final String? applicantName;

  // 리컨펌(재확인) 알림 — 단기 근무 전용
  // null: 아직 알림 미발송 / 'pending': 발송 후 미응답 / 'confirmed': 출근 확인 / 'declined': 취소
  final String? reconfirmStatus;
  final DateTime? reconfirmSentAt;       // H-2 알림 발송 시각
  final DateTime? reconfirmRespondedAt;  // 응답 시각

  // 🎫 초대 시스템 — status=INVITED일 때 사용
  // 단기 초대: slotId + workDate 기존 필드 재활용
  // 장기 초대: desiredStartDate(시작일) + workEndDate(종료일) 기존 필드 재활용
  final String? invitedBy;         // 초대한 관리자 UID
  final DateTime? invitedAt;       // 초대 발송 시각 (만료 계산 기준)
  final DateTime? inviteExpiresAt; // 초대 만료 시각 (CF에서 invitedAt + 24h 계산 저장)

  // [ID-CONSENT] 신분증 열람 사전동의 — CF 서버 타임스탬프로 기록 (legacy, 하위 호환 유지)
  final bool idCardConsentGiven;       // 지원 시 동의 여부 (항상 true, 미동의 시 지원 불가)
  final DateTime? idCardConsentAt;     // 동의 시각 (serverTimestamp)
  final String? idCardConsentVersion;  // 동의 버전 (예: "2026-08-v1")

  // [DOCUMENT-CONSENT] 소득신고·급여처리 목적 서류 접근 통합 동의 — V3 신규
  // 신분증 + 급여계좌 + 통장사본을 권한 있는 관리자가 확인할 수 있음에 동의.
  // idCardConsentGiven은 legacy 신분증 접근 호환용으로 별도 유지.
  final bool documentAccessConsentGiven;    // 동의 여부 (지원 시 항상 true)
  final DateTime? documentAccessConsentAt;  // 동의 시각 (serverTimestamp)
  final String? documentAccessConsentVersion; // 동의 버전 (예: "2026-08-v1")

  ApplicationModel({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.toTitle,
    required this.workDate,
    this.workEndDate,      // ⭐ 추가
    this.workDays,         // ⭐ 추가
    required this.startTime,
    required this.endTime,
    required this.uid,
    required this.selectedWorkType,
    this.workDetailId,
    this.wdId,
    this.toId,
    this.slotId,
    this.groupId,
    required this.wage,
    // 🔥 업무 상세 정보
    this.wageType,
    this.workTypeIcon,
    this.workTypeColor,
    this.workTypeBackgroundColor,
    this.originalWorkType,
    this.originalWage,
    this.changedAt,
    this.changedBy,
    required this.status,
    required this.appliedAt,
    this.confirmedAt,
    this.confirmedBy,
    // ⭐ Phase 2: 추가
    this.canceledAt,
    this.cancelReason,
    this.conflictingAppId,
    this.conflictingBusiness,
    this.conflictingTime,
    this.applicationMessage,
    this.confirmMessage,
    this.rejectMessage,
    this.cancelMessage,
    // 🔥 Phase A: 퇴사 관리
    this.resignRequestedAt,
    this.resignRequestDate,
    this.resignStatus,
    this.resignApprovedAt,
    this.resignApprovedBy,
    this.resignRejectedAt,
    this.resignRejectedBy,
    this.resignRejectReason,
    this.actualResignDate,
    // 🔥 Phase C: 계약해지 관리
    this.terminationStatus,
    this.terminationRequestedAt,
    this.terminationReason,
    this.terminationEffectiveDate,
    this.terminationRequestedByUid,
    this.terminationRespondedAt,
    this.terminationRejectReason,
    // 🔄 계약 연장/종료 관리
    this.renewalDecision,
    this.renewalNotifiedAt,
    this.renewedFromApplicationId,
    // ⭐ 장기공고 희망 시작일
    this.desiredStartDate,
    // ⭐ 여기에 추가
    this.leaveDates,
    this.extraWorkDates,
    // 🔥 상태 변경 이력
    this.statusHistory,
    this.applicationType,
    this.isStarred = false,
    this.lastContractRequestedAt,
    this.applicantName,
    this.reconfirmStatus,
    this.reconfirmSentAt,
    this.reconfirmRespondedAt,
    // 🎫 초대 시스템
    this.invitedBy,
    this.invitedAt,
    this.inviteExpiresAt,
    // [ID-CONSENT] 신분증 열람 사전동의 (legacy)
    this.idCardConsentGiven = false,
    this.idCardConsentAt,
    this.idCardConsentVersion,
    // [DOCUMENT-CONSENT] 소득신고·급여처리 목적 서류 통합 동의 (V3 신규)
    this.documentAccessConsentGiven = false,
    this.documentAccessConsentAt,
    this.documentAccessConsentVersion,
  });

  static ApplicationModel? tryFromMap(Map<String, dynamic> data, String documentId) {
    try {
      return ApplicationModel.fromMap(data, documentId);
    } catch (e, st) {
      debugPrint('[ApplicationModel] tryFromMap 실패 id=$documentId: $e\n$st');
      return null;
    }
  }

  /// Firestore 문서를 ApplicationModel로 변환
  factory ApplicationModel.fromMap(Map<String, dynamic> data, String documentId) {
    return ApplicationModel(
      id: documentId,
      businessId: data['businessId'] ?? '',
      businessName: data['businessName'] ?? '',
      toTitle: data['toTitle'] ?? '',
      // workDate는 DB 스키마 필수 필드 — 누락 시 의도적으로 ArgumentError throw (fast-fail)
      workDate: data['workDate'] != null
          ? parseTimestamp(data['workDate'])
          : (throw ArgumentError('ApplicationModel: workDate 필드 누락 (id: $documentId)')),
      workEndDate: parseTimestampNullable(data['workEndDate']),
      workDays: data['workDays'] != null
          ? List<String>.from(data['workDays'])
          : null,  // ⭐
      startTime: data['startTime'] ?? '',
      endTime: data['endTime'] ?? '',
      uid: data['uid'] ?? '',
      selectedWorkType: data['selectedWorkType'] ?? '',
      workDetailId: data['workDetailId'],
      wdId: data['wdId'] as String?,
      toId: data['toId'],
      slotId: data['slotId'],
      groupId: data['groupId'],
      wage: (data['wage'] as num?)?.toInt() ?? 0,
      // 🔥 업무 상세 정보
      wageType: data['wageType'],
      workTypeIcon: data['workTypeIcon'],
      workTypeColor: data['workTypeColor'],
      workTypeBackgroundColor: data['workTypeBackgroundColor'],
      originalWorkType: data['originalWorkType'],
      originalWage: (data['originalWage'] as num?)?.toInt(),
      changedAt: parseTimestampNullable(data['changedAt']),
      changedBy: data['changedBy'],
      status: data['status'] ?? 'PENDING',
      appliedAt: data['appliedAt'] != null
          ? parseTimestamp(data['appliedAt'])
          : (throw ArgumentError('ApplicationModel: appliedAt 필드 누락 (id: $documentId)')),
      confirmedAt: parseTimestampNullable(data['confirmedAt']),
      confirmedBy: data['confirmedBy'],
      // ⭐ Phase 2: 추가
      canceledAt: parseTimestampNullable(data['canceledAt']),
      cancelReason: data['cancelReason'],
      conflictingAppId: data['conflictingAppId'],
      conflictingBusiness: data['conflictingBusiness'],
      conflictingTime: data['conflictingTime'],
      applicationMessage: data['applicationMessage'],
      confirmMessage: data['confirmMessage'],
      rejectMessage: data['rejectMessage'],
      cancelMessage: data['cancelMessage'],
      // 🔥 Phase A: 퇴사 관리
      resignRequestedAt: parseTimestampNullable(data['resignRequestedAt']),
      resignRequestDate: parseTimestampNullable(data['resignRequestDate']),
      resignStatus: data['resignStatus'],
      resignApprovedAt: parseTimestampNullable(data['resignApprovedAt']),
      resignApprovedBy: data['resignApprovedBy'],
      // [BUG-수정] M-4: 퇴사 거절 전용 필드 파싱 추가
      resignRejectedAt: parseTimestampNullable(data['resignRejectedAt']),
      resignRejectedBy: data['resignRejectedBy'],
      resignRejectReason: data['resignRejectReason'],
      actualResignDate: parseTimestampNullable(data['actualResignDate']),
      // 🔥 Phase C: 계약해지 관리
      terminationStatus: data['terminationStatus'],
      terminationRequestedAt: parseTimestampNullable(data['terminationRequestedAt']),
      terminationReason: data['terminationReason'],
      terminationEffectiveDate: parseTimestampNullable(data['terminationEffectiveDate']),
      terminationRequestedByUid: data['terminationRequestedByUid'],
      terminationRespondedAt: parseTimestampNullable(data['terminationRespondedAt']),
      terminationRejectReason: data['terminationRejectReason'],
      // 🔄 계약 연장/종료 관리
      renewalDecision: data['renewalDecision'],
      renewalNotifiedAt: parseTimestampNullable(data['renewalNotifiedAt']),
      renewedFromApplicationId: data['renewedFromApplicationId'],
      // ⭐ 장기공고 희망 시작일
      desiredStartDate: parseTimestampNullable(data['desiredStartDate']),
      leaveDates: data['leaveDates'] != null
          ? (data['leaveDates'] as List)
              .map((e) => parseTimestampNullable(e))
              .whereType<DateTime>()
              .toList()
          : null,
      extraWorkDates: data['extraWorkDates'] != null
          ? (data['extraWorkDates'] as List)
              .map((e) => parseTimestampNullable(e))
              .whereType<DateTime>()
              .toList()
          : null,
          // 🔥 상태 변경 이력
      statusHistory: data['statusHistory'] != null
          ? (data['statusHistory'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList()
          : null,
      applicationType: data['type'] as String?,
      isStarred: data['isStarred'] as bool? ?? false,
      lastContractRequestedAt: parseTimestampNullable(data['lastContractRequestedAt']),
      applicantName: data['applicantName'] as String?,
      reconfirmStatus: data['reconfirmStatus'] as String?,
      reconfirmSentAt: parseTimestampNullable(data['reconfirmSentAt']),
      reconfirmRespondedAt: parseTimestampNullable(data['reconfirmRespondedAt']),
      // 🎫 초대 시스템
      invitedBy: data['invitedBy'] as String?,
      invitedAt: parseTimestampNullable(data['invitedAt']),
      inviteExpiresAt: parseTimestampNullable(data['inviteExpiresAt']),
      // [ID-CONSENT] 신분증 열람 사전동의 (legacy)
      idCardConsentGiven: data['idCardConsentGiven'] as bool? ?? false,
      idCardConsentAt: parseTimestampNullable(data['idCardConsentAt']),
      idCardConsentVersion: data['idCardConsentVersion'] as String?,
      // [DOCUMENT-CONSENT] 소득신고·급여처리 목적 서류 통합 동의 (V3 신규)
      documentAccessConsentGiven: data['documentAccessConsentGiven'] as bool? ?? false,
      documentAccessConsentAt: parseTimestampNullable(data['documentAccessConsentAt']),
      documentAccessConsentVersion: data['documentAccessConsentVersion'] as String?,
    );
  }

  /// Firestore DocumentSnapshot에서 변환
  factory ApplicationModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) {
      throw ArgumentError('ApplicationModel.fromFirestore: 문서 데이터 없음 (id: ${doc.id})');
    }
    return ApplicationModel.fromMap(raw as Map<String, dynamic>, doc.id);
  }

  // [SCHEMA-09] 역직렬화 실패 격리 — 손상 문서 1건이 목록 전체 크래시 방지
  static ApplicationModel? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return ApplicationModel.fromFirestore(doc);
    } catch (e, st) {
      debugPrint('[ApplicationModel] 역직렬화 실패 id=${doc.id}: $e\n$st');
      return null;
    }
  }

  /// ApplicationModel을 Firestore 문서로 변환
  Map<String, dynamic> toMap() {
    return {
      'businessId': businessId,
      'businessName': businessName,
      'toTitle': toTitle,
      'workDate': Timestamp.fromDate(workDate),
      'workEndDate': workEndDate != null ? Timestamp.fromDate(workEndDate!) : null,  // ⭐
      'workDays': workDays,  // ⭐
      'desiredStartDate': desiredStartDate != null ? Timestamp.fromDate(desiredStartDate!) : null,  // ⭐ 희망 시작일
      'startTime': startTime,
      'endTime': endTime,
      'uid': uid,
      'selectedWorkType': selectedWorkType,
      'workDetailId': workDetailId,
      'wdId': wdId,
      'toId': toId,
      'slotId': slotId,
      'groupId': groupId,
      'wage': wage,
      // 🔥 업무 상세 정보
      'wageType': wageType,
      'workTypeIcon': workTypeIcon,
      'workTypeColor': workTypeColor,
      'workTypeBackgroundColor': workTypeBackgroundColor,
      'originalWorkType': originalWorkType,
      'originalWage': originalWage,
      'changedAt': changedAt != null ? Timestamp.fromDate(changedAt!) : null,
      'changedBy': changedBy,
      'status': status,
      'appliedAt': Timestamp.fromDate(appliedAt),
      'confirmedAt': confirmedAt != null ? Timestamp.fromDate(confirmedAt!) : null,
      'confirmedBy': confirmedBy,
      // ⭐ Phase 2: 추가
      'canceledAt': canceledAt != null ? Timestamp.fromDate(canceledAt!) : null,
      'cancelReason': cancelReason,
      'conflictingAppId': conflictingAppId,
      'conflictingBusiness': conflictingBusiness,
      'conflictingTime': conflictingTime,
      'applicationMessage': applicationMessage,
      'confirmMessage': confirmMessage,
      'rejectMessage': rejectMessage,
      'cancelMessage': cancelMessage,
      // 🔥 Phase A: 퇴사 관리
      'resignRequestedAt': resignRequestedAt != null ? Timestamp.fromDate(resignRequestedAt!) : null,
      'resignRequestDate': resignRequestDate != null ? Timestamp.fromDate(resignRequestDate!) : null,
      'resignStatus': resignStatus,
      'resignApprovedAt': resignApprovedAt != null ? Timestamp.fromDate(resignApprovedAt!) : null,
      'resignApprovedBy': resignApprovedBy,
      // [BUG-수정] M-4: 거절 전용 필드 직렬화 추가
      'resignRejectedAt': resignRejectedAt != null ? Timestamp.fromDate(resignRejectedAt!) : null,
      'resignRejectedBy': resignRejectedBy,
      'resignRejectReason': resignRejectReason,
      'actualResignDate': actualResignDate != null ? Timestamp.fromDate(actualResignDate!) : null,
      // 🔥 Phase C: 계약해지 관리
      'terminationStatus': terminationStatus,
      'terminationRequestedAt': terminationRequestedAt != null ? Timestamp.fromDate(terminationRequestedAt!) : null,
      'terminationReason': terminationReason,
      'terminationEffectiveDate': terminationEffectiveDate != null ? Timestamp.fromDate(terminationEffectiveDate!) : null,
      'terminationRequestedByUid': terminationRequestedByUid,
      'terminationRespondedAt': terminationRespondedAt != null ? Timestamp.fromDate(terminationRespondedAt!) : null,
      'terminationRejectReason': terminationRejectReason,
      // 🔄 계약 연장/종료 관리
      'renewalDecision': renewalDecision,
      'renewalNotifiedAt': renewalNotifiedAt != null ? Timestamp.fromDate(renewalNotifiedAt!) : null,
      'renewedFromApplicationId': renewedFromApplicationId,

      // ⭐ 여기에 추가
      'leaveDates': leaveDates?.map((e) => Timestamp.fromDate(e)).toList(),
      'extraWorkDates': extraWorkDates?.map((e) => Timestamp.fromDate(e)).toList(),
      // 🔥 상태 변경 이력 (Timestamp 변환)
      'statusHistory': statusHistory,
      'type': applicationType,
      'isStarred': isStarred,
      'reconfirmStatus': reconfirmStatus,
      'reconfirmSentAt': reconfirmSentAt != null ? Timestamp.fromDate(reconfirmSentAt!) : null,
      'reconfirmRespondedAt': reconfirmRespondedAt != null ? Timestamp.fromDate(reconfirmRespondedAt!) : null,
      // 🎫 초대 시스템
      'invitedBy': invitedBy,
      'invitedAt': invitedAt != null ? Timestamp.fromDate(invitedAt!) : null,
      'inviteExpiresAt': inviteExpiresAt != null ? Timestamp.fromDate(inviteExpiresAt!) : null,
      // [ID-CONSENT] 신분증 열람 사전동의 — legacy (읽기 전용 — CF가 serverTimestamp로 기록)
      'idCardConsentGiven': idCardConsentGiven,
      'idCardConsentAt': idCardConsentAt != null ? Timestamp.fromDate(idCardConsentAt!) : null,
      'idCardConsentVersion': idCardConsentVersion,
      // [DOCUMENT-CONSENT] 소득신고·급여처리 목적 서류 통합 동의 (읽기 전용 — CF 기록)
      'documentAccessConsentGiven': documentAccessConsentGiven,
      'documentAccessConsentAt': documentAccessConsentAt != null ? Timestamp.fromDate(documentAccessConsentAt!) : null,
      'documentAccessConsentVersion': documentAccessConsentVersion,
    };
  }

  /// 상태 한글 표시
  String get statusText {
    switch (status) {
      case 'PENDING':           return '대기 중';
      case 'CONTRACT_PENDING':  return '계약 대기';
      case 'CONFIRMED':         return '확정';
      case 'REJECTED':          return '거절';
      case 'CANCELED':          return '취소됨';
      case 'AUTO_CANCELED':     return '자동 취소됨';
      case 'INVITED':           return '초대받음';
      case 'EXPIRED':           return '초대 만료';
      default:                  return '알 수 없음';
    }
  }

/// 업무유형이 변경되었는지 여부
  bool get isWorkTypeChanged => originalWorkType != null;
  
   /// 포맷팅된 금액 (예: "50,000원")
  String get formattedWage {
    return FormatHelper.formatWage(wage);
  }
  
  /// 🔥 급여 타입 라벨 (예: "시급")
  String get wageTypeLabel {
    if (wageType == null) return '';
    return FormatHelper.getWageTypeLabel(wageType!);
  }

  /// 복사본 생성
  ApplicationModel copyWith({
    String? id,
    String? businessId,
    String? businessName,
    String? toTitle,
    DateTime? workDate,
    DateTime? workEndDate,     // ⭐
    List<String>? workDays,    // ⭐
    String? startTime,
    String? endTime,
    String? uid,
    String? selectedWorkType,
    String? toId,
    String? workDetailId,
    String? wdId,
    String? slotId,
    String? groupId,
    int? wage,
    // 🔥 업무 상세 정보
    String? wageType,
    String? workTypeIcon,
    String? workTypeColor,
    String? workTypeBackgroundColor,
    String? originalWorkType,
    int? originalWage,
    DateTime? changedAt,
    String? changedBy,
    String? status,
    DateTime? appliedAt,
    DateTime? confirmedAt,
    String? confirmedBy,
    // ⭐ Phase 2: 추가
    DateTime? canceledAt,
    String? cancelReason,
    String? conflictingAppId,
    String? conflictingBusiness,
    String? conflictingTime,
    String? applicationMessage,
    String? confirmMessage,
    String? rejectMessage,
    String? cancelMessage,
    // 🔥 Phase A: 퇴사 관리
    DateTime? resignRequestedAt,
    DateTime? resignRequestDate,
    String? resignStatus,
    DateTime? resignApprovedAt,
    String? resignApprovedBy,
    DateTime? resignRejectedAt,
    String? resignRejectedBy,
    String? resignRejectReason,
    DateTime? actualResignDate,
    // 🔥 Phase C: 계약해지 관리
    String? terminationStatus,
    DateTime? terminationRequestedAt,
    String? terminationReason,
    DateTime? terminationEffectiveDate,
    String? terminationRequestedByUid,
    DateTime? terminationRespondedAt,
    String? terminationRejectReason,
    String? renewalDecision,
    DateTime? renewalNotifiedAt,
    String? renewedFromApplicationId,
    DateTime? desiredStartDate,
    List<DateTime>? leaveDates,
    List<DateTime>? extraWorkDates,
    // 🔥 상태 변경 이력
    List<Map<String, dynamic>>? statusHistory,
    String? applicationType,
    bool? isStarred,
    DateTime? lastContractRequestedAt,
    String? applicantName,
    String? reconfirmStatus,
    DateTime? reconfirmSentAt,
    DateTime? reconfirmRespondedAt,
    // 🎫 초대 시스템
    String? invitedBy,
    DateTime? invitedAt,
    DateTime? inviteExpiresAt,
    // [ID-CONSENT] 신분증 열람 사전동의 (legacy)
    bool? idCardConsentGiven,
    DateTime? idCardConsentAt,
    String? idCardConsentVersion,
    // [DOCUMENT-CONSENT] 소득신고·급여처리 목적 서류 통합 동의 (V3 신규)
    bool? documentAccessConsentGiven,
    DateTime? documentAccessConsentAt,
    String? documentAccessConsentVersion,
  }) {
    return ApplicationModel(
      id: id ?? this.id,
      businessId: businessId ?? this.businessId,
      businessName: businessName ?? this.businessName,
      toTitle: toTitle ?? this.toTitle,
      workDate: workDate ?? this.workDate,
      workEndDate: workEndDate ?? this.workEndDate,     // ⭐
      workDays: workDays ?? this.workDays,               // ⭐
      desiredStartDate: desiredStartDate ?? this.desiredStartDate,  // ⭐ 희망 시작일        // ⭐
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      uid: uid ?? this.uid,
      selectedWorkType: selectedWorkType ?? this.selectedWorkType,
      toId: toId ?? this.toId,
      workDetailId: workDetailId ?? this.workDetailId,
      wdId: wdId ?? this.wdId,
      slotId: slotId ?? this.slotId,
      groupId: groupId ?? this.groupId,
      wage: wage ?? this.wage,
      // 🔥 업무 상세 정보
      wageType: wageType ?? this.wageType,
      workTypeIcon: workTypeIcon ?? this.workTypeIcon,
      workTypeColor: workTypeColor ?? this.workTypeColor,
      workTypeBackgroundColor: workTypeBackgroundColor ?? this.workTypeBackgroundColor,
      originalWorkType: originalWorkType ?? this.originalWorkType,
      originalWage: originalWage ?? this.originalWage,
      changedAt: changedAt ?? this.changedAt,
      changedBy: changedBy ?? this.changedBy,
      status: status ?? this.status,
      appliedAt: appliedAt ?? this.appliedAt,
      confirmedAt: confirmedAt ?? this.confirmedAt,
      confirmedBy: confirmedBy ?? this.confirmedBy,
      // ⭐ Phase 2: 추가
      canceledAt: canceledAt ?? this.canceledAt,
      cancelReason: cancelReason ?? this.cancelReason,
      conflictingAppId: conflictingAppId ?? this.conflictingAppId,
      conflictingBusiness: conflictingBusiness ?? this.conflictingBusiness,
      conflictingTime: conflictingTime ?? this.conflictingTime,
      applicationMessage: applicationMessage ?? this.applicationMessage,
      confirmMessage: confirmMessage ?? this.confirmMessage,
      rejectMessage: rejectMessage ?? this.rejectMessage,
      cancelMessage: cancelMessage ?? this.cancelMessage,
      // 🔥 Phase A: 퇴사 관리
      resignRequestedAt: resignRequestedAt ?? this.resignRequestedAt,
      resignRequestDate: resignRequestDate ?? this.resignRequestDate,
      resignStatus: resignStatus ?? this.resignStatus,
      resignApprovedAt: resignApprovedAt ?? this.resignApprovedAt,
      resignApprovedBy: resignApprovedBy ?? this.resignApprovedBy,
      resignRejectedAt: resignRejectedAt ?? this.resignRejectedAt,
      resignRejectedBy: resignRejectedBy ?? this.resignRejectedBy,
      resignRejectReason: resignRejectReason ?? this.resignRejectReason,
      actualResignDate: actualResignDate ?? this.actualResignDate,
      // 🔥 Phase C: 계약해지 관리
      terminationStatus: terminationStatus ?? this.terminationStatus,
      terminationRequestedAt: terminationRequestedAt ?? this.terminationRequestedAt,
      terminationReason: terminationReason ?? this.terminationReason,
      terminationEffectiveDate: terminationEffectiveDate ?? this.terminationEffectiveDate,
      terminationRequestedByUid: terminationRequestedByUid ?? this.terminationRequestedByUid,
      terminationRespondedAt: terminationRespondedAt ?? this.terminationRespondedAt,
      terminationRejectReason: terminationRejectReason ?? this.terminationRejectReason,
      renewalDecision: renewalDecision ?? this.renewalDecision,
      renewalNotifiedAt: renewalNotifiedAt ?? this.renewalNotifiedAt,
      renewedFromApplicationId: renewedFromApplicationId ?? this.renewedFromApplicationId,
      leaveDates: leaveDates ?? this.leaveDates,
      extraWorkDates: extraWorkDates ?? this.extraWorkDates,
      // 🔥 상태 변경 이력
      statusHistory: statusHistory ?? this.statusHistory,
      applicationType: applicationType ?? this.applicationType,
      isStarred: isStarred ?? this.isStarred,
      lastContractRequestedAt: lastContractRequestedAt ?? this.lastContractRequestedAt,
      applicantName: applicantName ?? this.applicantName,
      reconfirmStatus: reconfirmStatus ?? this.reconfirmStatus,
      reconfirmSentAt: reconfirmSentAt ?? this.reconfirmSentAt,
      reconfirmRespondedAt: reconfirmRespondedAt ?? this.reconfirmRespondedAt,
      // 🎫 초대 시스템
      invitedBy: invitedBy ?? this.invitedBy,
      invitedAt: invitedAt ?? this.invitedAt,
      inviteExpiresAt: inviteExpiresAt ?? this.inviteExpiresAt,
      // [ID-CONSENT] 신분증 열람 사전동의 (legacy)
      idCardConsentGiven: idCardConsentGiven ?? this.idCardConsentGiven,
      idCardConsentAt: idCardConsentAt ?? this.idCardConsentAt,
      idCardConsentVersion: idCardConsentVersion ?? this.idCardConsentVersion,
      // [DOCUMENT-CONSENT] 소득신고·급여처리 목적 서류 통합 동의 (V3 신규)
      documentAccessConsentGiven: documentAccessConsentGiven ?? this.documentAccessConsentGiven,
      documentAccessConsentAt: documentAccessConsentAt ?? this.documentAccessConsentAt,
      documentAccessConsentVersion: documentAccessConsentVersion ?? this.documentAccessConsentVersion,
    );
  }

  @override
  String toString() {
    return 'ApplicationModel(id: $id, businessId: $businessId, toTitle: $toTitle, '
        'workDate: $workDate, uid: $uid, selectedWorkType: $selectedWorkType, '
        'wage: $wage, status: $status, isChanged: $isWorkTypeChanged)';
  }
  // ⭐ Phase 1-B: 장기 공고 표시용 헬퍼
  
  /// 장기 지원인지 확인
  bool get isLongTermApplication {
    // 명시적으로 단기 → false
    if (applicationType == AppType.shortTerm) return false;
    // 명시적으로 장기 → true
    if (applicationType == AppType.longTerm) return true;
    // workDays가 있으면 장기 (신규 데이터)
    if (workDays != null && workDays!.isNotEmpty) return true;
    // [C-001 수정] workEndDate만으로 장기 판정 불충분
    // 단기 TO(1일 근무)도 workEndDate가 당일로 설정될 수 있어 오분류 위험
    // 구 데이터(contract-type 장기) 지원서는 workDate < workEndDate를 만족하므로 날짜 비교로 판별
    if (workEndDate != null) {
      final e = workEndDate!;
      return !(workDate.year == e.year && workDate.month == e.month && workDate.day == e.day);
    }
    return false;
  }
  
  /// 근무 기간 표시 (예: "11/1~11/30")
  ///
  /// effectiveStart 결정 방식은 isWorkingOnDate·isScheduledOnDate와 동일하게 맞춤.
  /// 불일치하면 캘린더에 표시되는 기간과 카드에 표시되는 기간이 달라져 혼란을 줄 수 있음.
  String get workPeriodDisplay {
    final effectiveEnd = actualResignDate ?? workEndDate;
    if (effectiveEnd == null) return '';

    // desiredStartDate가 없고 확정일(confirmedAt)이 workDate보다 늦으면
    // 실제 근무 시작은 confirmedAt 당일 — workDate부터 표시하면 미근무 기간이 포함됨
    DateTime effectiveStart = desiredStartDate ?? workDate;
    if (confirmedAt != null && desiredStartDate == null) {
      final confirmedDay = DateTime(confirmedAt!.year, confirmedAt!.month, confirmedAt!.day);
      if (confirmedDay.isAfter(effectiveStart)) effectiveStart = confirmedDay;
    }
    final startStr = '${effectiveStart.month}/${effectiveStart.day}';
    final endStr = '${effectiveEnd.month}/${effectiveEnd.day}';
    return '$startStr~$endStr';
  }
  
  /// 근무 요일 표시 (예: "주 5일 (월~금)" 또는 "주 3일 (월,수,금)")
  String? get workDaysDisplay {
    if (workDays == null || workDays!.isEmpty) return null;
    
    final count = workDays!.length;

    // 연속된 요일인지 확인 (월~금)
    final weekDays = ['월', '화', '수', '목', '금', '토', '일'];
    final indices = workDays!.map((day) => weekDays.indexOf(day)).toList()..sort();
    
    bool isContinuous = true;
    for (int i = 1; i < indices.length; i++) {
      if (indices[i] != indices[i - 1] + 1) {
        isContinuous = false;
        break;
      }
    }
    
    if (isContinuous && count > 1) {
      return '주 $count일 (${weekDays[indices.first]}~${weekDays[indices.last]})';
    } else {
      final sortedDays = indices.map((i) => weekDays[i]).join(',');
      return '주 $count일 ($sortedDays)';
    }
  }
  // ⭐ 특정 날짜가 휴무일인지 확인
  bool isLeaveDateOn(DateTime date) {
    if (leaveDates == null || leaveDates!.isEmpty) return false;
    return leaveDates!.any((d) => _isSameDay(d, date));
  }

  // ⭐ 특정 날짜가 추가 근무일인지 확인
  bool isExtraWorkDateOn(DateTime date) {
    if (extraWorkDates == null || extraWorkDates!.isEmpty) return false;
    return extraWorkDates!.any((d) => _isSameDay(d, date));
  }

  // ─────────────────────────────────────────────────────────
  // ─────────────────────────────────────────────────────────
  // 스케줄 판단 (단일 진실의 원천)
  //
  // [검증 이력]
  // · effectiveStart 결정 규칙: desiredStartDate ?? workDate
  //   confirmedAt > workDate이고 desiredStartDate=null이면 confirmedAt 당일로 보정.
  //   desiredStartDate가 있으면 확정일 보정 비활성 — 사용자 지정 시작일 우선.
  // · endDate = actualResignDate ?? workEndDate
  //   workEndDate=null이면 false/0 — "기간 미정" 계약은 전 시스템 일관성 있게 미지원 처리.
  // · isWorkingOnDate vs isScheduledOnDate 차이:
  //   isWorkingOnDate: 충돌 판단용 — 휴무일=false (근무 없음)
  //   isScheduledOnDate: 캘린더 표시용 — 휴무일=true (표시는 하되 회색 처리)
  // · 이 두 함수와 _workDaysInMonth·workPeriodDisplay의 effectiveStart 로직이 동일해야 함.
  //   세 곳 중 한 곳 변경 시 나머지도 반드시 함께 수정할 것.
  // ─────────────────────────────────────────────────────────

  /// 충돌 판단용: 해당 날짜에 이 지원이 근무 중인지 확인
  /// - 휴무일(leaveDates) → false (근무 없음)
  /// - 추가 근무일(extraWorkDates) → true (요일 무관)
  /// - workEndDate=null → false (isScheduledOnDate와 동일)
  bool isWorkingOnDate(DateTime targetDate) {
    if (!isLongTermApplication) {
      return _isSameDay(workDate, targetDate);
    }

    final endDate = actualResignDate ?? workEndDate;
    if (endDate == null) return false;

    DateTime effectiveStart = desiredStartDate ?? workDate;
    if (confirmedAt != null && desiredStartDate == null) {
      final confirmedDay = FormatHelper.toKstDate(confirmedAt!);
      if (confirmedDay.isAfter(FormatHelper.toKstDate(workDate))) effectiveStart = confirmedDay;
    }

    final targetOnly = FormatHelper.toKstDate(targetDate);
    final startOnly = FormatHelper.toKstDate(effectiveStart);
    final endOnly = FormatHelper.toKstDate(endDate);

    if (targetOnly.isBefore(startOnly) || targetOnly.isAfter(endOnly)) return false;

    if (isExtraWorkDateOn(targetOnly)) return true;
    if (isLeaveDateOn(targetOnly)) return false;

    return workDays?.contains(FormatHelper.weekday(targetDate)) ?? false;
  }

  /// 캘린더 표시용: 해당 날짜에 이 지원이 일정으로 표시되어야 하는지 확인
  /// - 미확정 장기공고 → 지원일(workDate)에만 표시
  /// - 퇴사/계약해지 완료(isTerminationApproved) → false
  /// - 휴무일도 true (캘린더에 표시, UI에서 회색 처리)
  /// - workEndDate=null → false (isWorkingOnDate와 동일)
  bool isScheduledOnDate(DateTime targetDate) {
    if (!isLongTermApplication) {
      return _isSameDay(workDate, targetDate);
    }

    if (status != AppStatus.confirmed && status != AppStatus.contractPending) {
      // PENDING 장기: buildDateIndex의 start(desiredStartDate ?? workDate)와 기준을 일치시켜
      // 희망 시작일에 지원 카드가 표시되도록 함
      return _isSameDay(desiredStartDate ?? workDate, targetDate);
    }

    if (isTerminationApproved) {
      return false;
    }

    final endDate = actualResignDate ?? workEndDate;
    if (endDate == null) return false;

    DateTime effectiveStart = desiredStartDate ?? workDate;
    if (confirmedAt != null && desiredStartDate == null) {
      final confirmedDay = FormatHelper.toKstDate(confirmedAt!);
      if (confirmedDay.isAfter(FormatHelper.toKstDate(workDate))) effectiveStart = confirmedDay;
    }

    final targetOnly = FormatHelper.toKstDate(targetDate);
    final startOnly = FormatHelper.toKstDate(effectiveStart);
    final endOnly = FormatHelper.toKstDate(endDate);

    if (targetOnly.isBefore(startOnly) || targetOnly.isAfter(endOnly)) return false;

    if (isExtraWorkDateOn(targetOnly)) return true;
    if (isLeaveDateOn(targetOnly)) return true; // 휴무일도 캘린더에 표시

    return workDays?.contains(FormatHelper.weekday(targetDate)) ?? false;
  }

  /// 시간대 겹침 여부 (충돌 판단용 정적 유틸)
  ///
  /// 야간 근무(22:00~02:00 등 자정 경계)를 정확히 처리합니다.
  /// end <= start 이면 야간 시프트로 간주하여 +24h 정규화 후 비교.
  static bool hasTimeOverlap(String s1, String e1, String s2, String e2) {
    if (s1.isEmpty || e1.isEmpty || s2.isEmpty || e2.isEmpty) return false;
    int toMin(String t) {
      final p = t.split(':');
      if (p.length < 2) return 0;
      return int.parse(p[0]) * 60 + int.parse(p[1]);
    }

    final a1 = toMin(s1);
    final rawB1 = toMin(e1);
    final a2 = toMin(s2);
    final rawB2 = toMin(e2);

    // 야간 시프트: end <= start → end + 24h 로 정규화
    final b1 = rawB1 <= a1 ? rawB1 + 1440 : rawB1;
    final b2 = rawB2 <= a2 ? rawB2 + 1440 : rawB2;

    bool overlaps(int x1, int y1, int x2, int y2) => x1 < y2 && x2 < y1;

    // 동일 날짜, 다음 날 shift2, 이전 날 shift2 세 가지 경우 검사
    return overlaps(a1, b1, a2, b2) ||
        overlaps(a1, b1, a2 + 1440, b2 + 1440) ||
        overlaps(a1, b1, a2 - 1440, b2 - 1440);
  }

  /// 퇴사 또는 계약해지가 승인 완료된 상태 (APPROVED / AUTO_APPROVED)
  bool get isTerminationApproved =>
      resignStatus == AppStatus.approved ||
      resignStatus == AppStatus.autoApproved ||
      terminationStatus == AppStatus.approved ||
      terminationStatus == AppStatus.autoApproved;

  static bool _isSameDay(DateTime a, DateTime b) {
    final ka = FormatHelper.toKstDate(a);
    final kb = FormatHelper.toKstDate(b);
    return ka.year == kb.year && ka.month == kb.month && ka.day == kb.day;
  }
}

/// 지원서 Firestore 상태 상수 (대문자 — applications 컬렉션 convention)
abstract class AppStatus {
  static const String pending          = 'PENDING';
  static const String contractPending  = 'CONTRACT_PENDING'; // 관리자 확정 후 쌍방 서명 대기
  static const String confirmed        = 'CONFIRMED';        // 계약 체결 완료
  static const String rejected         = 'REJECTED';
  static const String canceled         = 'CANCELED';
  static const String autoCanceled     = 'AUTO_CANCELED';
  // 🎫 초대 시스템
  static const String invited          = 'INVITED';          // 관리자 초대 발송 후 근로자 미응답
  static const String expired          = 'EXPIRED';          // 초대 24h 미응답으로 자동 만료

  /// 퇴사·계약해지 하위 상태 (resignStatus / terminationStatus 필드용)
  static const String approved    = 'APPROVED';
  static const String autoApproved = 'AUTO_APPROVED';

  /// 계약 연장/종료 결정 (renewalDecision 필드용)
  static const String renewalExtend    = 'EXTEND';
  static const String renewalTerminate = 'TERMINATE';

  /// 활성 상태 그룹 (CONTRACT_PENDING도 활성으로 취급)
  /// INVITED는 수락 전이므로 미포함 — 충돌 체크 대상에서 제외
  static const List<String> activeStates   = [pending, contractPending, confirmed];
  /// 확정 완료 상태 그룹 (Firestore whereIn 쿼리 및 in-memory 체크에 사용)
  static const List<String> confirmedStatuses = [confirmed, contractPending];
  /// 비활성 상태 그룹
  static const List<String> inactiveStates = [rejected, canceled, autoCanceled];
  /// 초대 관련 상태 그룹 (근로자 초대 탭 필터용)
  static const List<String> inviteStates   = [invited, expired];
}

/// 지원서 타입 상수 (applications 컬렉션 type 필드)
abstract class AppType {
  static const String longTerm = 'long_term'; // 장기 고정 근무 지원서
  static const String shortTerm = 'short';    // 단기 근무 지원서
}