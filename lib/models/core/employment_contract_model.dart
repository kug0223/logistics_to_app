import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'contract_template_model.dart';
import 'insurance_rate_model.dart';
import '../../utils/firestore_helper.dart';

// ─── 상태 ─────────────────────────────────────────────────────

enum ContractStatus {
  pendingEmployer,  // 사업주 서명 대기
  pendingWorker,    // 근무자 서명 대기
  completed,        // 쌍방 서명 완료
  voided,           // 무효 (재발급 등)
}

extension ContractStatusX on ContractStatus {
  String get value {
    switch (this) {
      case ContractStatus.pendingEmployer:  return 'pending_employer';
      case ContractStatus.pendingWorker:    return 'pending_worker';
      case ContractStatus.completed:        return 'completed';
      case ContractStatus.voided:           return 'voided';
    }
  }

  String get label {
    switch (this) {
      case ContractStatus.pendingEmployer:  return '사업주 서명 대기';
      case ContractStatus.pendingWorker:    return '근무자 서명 대기';
      case ContractStatus.completed:        return '계약 완료';
      case ContractStatus.voided:           return '무효';
    }
  }

  static ContractStatus fromString(String v) {
    switch (v) {
      case 'pending_employer': return ContractStatus.pendingEmployer;
      case 'pending_worker':   return ContractStatus.pendingWorker;
      case 'completed':        return ContractStatus.completed;
      case 'voided':           return ContractStatus.voided;
      default:                 return ContractStatus.pendingEmployer;
    }
  }
}

// ─── 근무 슬롯 (계약서 내 개별 근무 일정) ──────────────────────

class ContractSlot {
  final String applicationId; // 해당 슬롯의 지원서 ID
  final String workDate;      // 'yyyy-MM-dd'
  final String startTime;     // 'HH:mm'
  final String endTime;       // 'HH:mm'
  final int wage;
  final String wageType;      // 'hourly' | 'daily' | 'monthly'

  const ContractSlot({
    required this.applicationId,
    required this.workDate,
    required this.startTime,
    required this.endTime,
    required this.wage,
    required this.wageType,
  });

  Map<String, dynamic> toMap() => {
    'applicationId': applicationId,
    'workDate': workDate,
    'startTime': startTime,
    'endTime': endTime,
    'wage': wage,
    'wageType': wageType,
  };

  factory ContractSlot.fromMap(Map<String, dynamic> m) => ContractSlot(
    applicationId: m['applicationId'] ?? '',
    workDate:      m['workDate'] ?? '',
    startTime:     m['startTime'] ?? '09:00',
    endTime:       m['endTime'] ?? '18:00',
    wage:          (m['wage'] as num?)?.toInt() ?? 0,
    wageType:      m['wageType'] ?? 'hourly',
  );

  String get wageTypeLabel {
    switch (wageType) {
      case 'hourly':  return '시급';
      case 'daily':   return '일급';
      case 'monthly': return '월급';
      default:        return '시급';
    }
  }

  String get formattedWage {
    final s = wage.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '$s원';
  }
}

// ─── 계약서 스냅샷 (서명 시점 데이터 고정) ────────────────────

class ContractSnapshot {
  // 사업주 정보
  final String businessName;
  final String businessNumber;
  final String businessAddress;
  final String? businessPhone;
  final String ownerName;

  // 근로자 정보
  final String workerName;
  final String? workerBirthDate;   // 'yyyy-MM-dd'
  final String? workerPhone;
  final String? workerAddress;

  // 근무 조건
  final String workType;           // 업무명
  final String workPlace;          // 근무 장소
  final bool isLongTerm;

  // 장기: 계약 기간 + 요일
  final String? contractStart;     // 장기: 'yyyy-MM-dd'
  final String? contractEnd;       // 장기: 'yyyy-MM-dd'
  final List<String>? workDays;    // 장기: ['월', '화', ...]

  // 단기: 슬롯 목록 (날짜/시간/금액이 각기 다를 수 있음)
  // 장기의 경우에도 대표 시간/임금은 아래 필드 사용
  final String startTime;          // 'HH:mm'
  final String endTime;            // 'HH:mm'
  final int breakMinutes;

  // 급여 조건
  final int wage;
  final String wageType;           // 'hourly' | 'daily' | 'monthly'
  final int? wagePaymentDay;       // 매월 OO일 (레거시)
  final String paymentMethod;      // '계좌이체'
  /// 업무상세에 등록된 통상시급 (일급제 연장·야간 수당 계산 기준)
  final int? baseHourlyWage;
  /// 급여 지급 유형: 'same_day' | 'next_day' | 'weekly' | 'monthly'
  final String? payScheduleType;
  /// 지급 기준일: 주급=1~7(월~일), 월급=1~31(31=말일)
  final int? payScheduleDay;
  /// 입금 예정 시간 'HH:mm'
  final String? payScheduleTime;

  /// 공제 방식
  final String taxDeductionType;

  const ContractSnapshot({
    required this.businessName,
    required this.businessNumber,
    required this.businessAddress,
    this.businessPhone,
    required this.ownerName,
    required this.workerName,
    this.workerBirthDate,
    this.workerPhone,
    this.workerAddress,
    required this.workType,
    required this.workPlace,
    required this.isLongTerm,
    this.contractStart,
    this.contractEnd,
    this.workDays,
    required this.startTime,
    required this.endTime,
    required this.breakMinutes,
    required this.wage,
    required this.wageType,
    this.wagePaymentDay,
    this.paymentMethod = '계좌이체',
    this.baseHourlyWage,
    this.payScheduleType,
    this.payScheduleDay,
    this.payScheduleTime,
    this.taxDeductionType = InsuranceRateModel.typeNone,
  });

  Map<String, dynamic> toMap() => {
    'businessName': businessName,
    'businessNumber': businessNumber,
    'businessAddress': businessAddress,
    'businessPhone': businessPhone,
    'ownerName': ownerName,
    'workerName': workerName,
    'workerBirthDate': workerBirthDate,
    'workerPhone': workerPhone,
    'workerAddress': workerAddress,
    'workType': workType,
    'workPlace': workPlace,
    'isLongTerm': isLongTerm,
    'contractStart': contractStart,
    'contractEnd': contractEnd,
    'workDays': workDays,
    'startTime': startTime,
    'endTime': endTime,
    'breakMinutes': breakMinutes,
    'wage': wage,
    'wageType': wageType,
    'wagePaymentDay': wagePaymentDay,
    'paymentMethod': paymentMethod,
    'baseHourlyWage': baseHourlyWage,
    if (payScheduleType != null) 'payScheduleType': payScheduleType,
    if (payScheduleDay != null) 'payScheduleDay': payScheduleDay,
    if (payScheduleTime != null) 'payScheduleTime': payScheduleTime,
    if (taxDeductionType != InsuranceRateModel.typeNone) 'taxDeductionType': taxDeductionType,
  };

  factory ContractSnapshot.fromMap(Map<String, dynamic> m) => ContractSnapshot(
    businessName: m['businessName'] ?? '',
    businessNumber: m['businessNumber'] ?? '',
    businessAddress: m['businessAddress'] ?? '',
    businessPhone: m['businessPhone'],
    ownerName: m['ownerName'] ?? '',
    workerName: m['workerName'] ?? '',
    workerBirthDate: m['workerBirthDate'],
    workerPhone: m['workerPhone'],
    workerAddress: m['workerAddress'],
    workType: m['workType'] ?? '',
    workPlace: m['workPlace'] ?? '',
    isLongTerm: m['isLongTerm'] ?? false,
    contractStart: m['contractStart'],
    contractEnd: m['contractEnd'],
    workDays: m['workDays'] != null ? List<String>.from(m['workDays']) : null,
    startTime: m['startTime'] ?? '09:00',
    endTime: m['endTime'] ?? '18:00',
    breakMinutes: (m['breakMinutes'] as num?)?.toInt() ?? 0,
    wage: (m['wage'] as num?)?.toInt() ?? 0,
    wageType: m['wageType'] ?? 'hourly',
    wagePaymentDay: m['wagePaymentDay'],
    paymentMethod: m['paymentMethod'] ?? '계좌이체',
    baseHourlyWage: (m['baseHourlyWage'] as num?)?.toInt(),
    payScheduleType: m['payScheduleType'] as String?,
    payScheduleDay: (m['payScheduleDay'] as num?)?.toInt(),
    payScheduleTime: m['payScheduleTime'] as String?,
    taxDeductionType: m['taxDeductionType'] as String? ?? InsuranceRateModel.typeNone,
  );

  // ── 표시용 헬퍼 ─────────────────────────────────────────────

  static const _weekdayLabels = ['', '월', '화', '수', '목', '금', '토', '일'];

  /// payScheduleType → 지급 방식 라벨 (당일 / 익일 / 주급 / 월급)
  String get payScheduleTypeLabel {
    switch (payScheduleType) {
      case 'same_day': return '당일';
      case 'next_day': return '익일';
      case 'weekly':   return '주급';
      case 'monthly':  return '월급';
      default:         return '';
    }
  }

  /// payScheduleType 기반 지급 일정 표시. 없으면 wagePaymentDay 레거시 값으로 폴백.
  String get payScheduleLabel {
    final timeStr = payScheduleTime != null ? ' $payScheduleTime' : '';
    switch (payScheduleType) {
      case 'same_day':  return '당일$timeStr';
      case 'next_day':  return '익일$timeStr';
      case 'weekly':
        final day = _weekdayLabels[payScheduleDay?.clamp(1, 7) ?? 1];
        return '매주 $day요일$timeStr';
      case 'monthly':
        final d = payScheduleDay ?? 1;
        return '매월 ${d == 31 ? '말일' : '$d일'}$timeStr';
      default:
        if (wagePaymentDay != null) return '매월 $wagePaymentDay일';
        return '별도 협의';
    }
  }

  String get wageTypeLabel {
    switch (wageType) {
      case 'hourly':  return '시급';
      case 'daily':   return '일급';
      case 'monthly': return '월급';
      default:        return '시급';
    }
  }

  String get formattedWage {
    final s = wage.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
    return '$s원';
  }

  String get workPeriodText {
    if (contractStart != null && contractEnd != null) {
      return '$contractStart ~ $contractEnd';
    }
    return '-';
  }

  String get workDaysText => workDays?.join(', ') ?? '-';

  String get workTimeText {
    final rawMins = _timeDiff(startTime, endTime) - breakMinutes;
    final workMins = rawMins < 0 ? 0 : rawMins;
    final h = workMins / 60.0;
    final hStr = h == h.toInt()
        ? '${h.toInt()}h'
        : '${h.toStringAsFixed(1)}h';
    final breakText = breakMinutes > 0 ? ' (휴게 $breakMinutes분)' : '';
    return '$startTime ~ $endTime$breakText · $hStr';
  }

  /// 통상시급: 업무상세 등록값 우선, 없으면 시급=직접값, 일급=wage÷순근무시간
  int? get hourlyWage {
    if (baseHourlyWage != null && baseHourlyWage! > 0) return baseHourlyWage;
    if (wageType == 'hourly') return wage;
    if (wageType == 'daily') {
      final workMins = _timeDiff(startTime, endTime) - breakMinutes;
      if (workMins <= 0) return null;
      return (wage / (workMins / 60.0)).round();
    }
    return null;
  }

  String get formattedHourlyWage {
    final hw = hourlyWage;
    if (hw == null) return '-';
    return '${_fmt(hw)}원/시간';
  }

  String _fmt(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }

  int _timeDiff(String s, String e) {
    final sp = s.split(':');
    final ep = e.split(':');
    if (sp.length < 2 || ep.length < 2) return 0; // 잘못된 형식 방어
    // startTime/endTime은 TO 등록 시 "HH:mm" 형식으로만 저장 — parse 예외 없음
    final sm = int.parse(sp[0]) * 60 + int.parse(sp[1]);
    var em = int.parse(ep[0]) * 60 + int.parse(ep[1]);
    if (em < sm) em += 24 * 60;
    return em - sm;
  }
}

// ─── 메인 모델 ────────────────────────────────────────────────

class EmploymentContractModel {
  final String id;
  final String applicationId; // 최초 생성 기준 지원서 ID
  final String businessId;
  final String workerId;      // 근무자 uid
  final bool isLongTerm;

  // 번들링 키: (toId + workDetailId + workerId)로 기존 계약서 찾기
  final String toId;
  final String workDetailId;

  // 단기 근무 슬롯 목록 (장기는 비어 있음)
  final List<ContractSlot> slots;

  // 이 계약에 포함된 모든 applicationId 목록 (arrayContains 조회용)
  final List<String> applicationIds;

  final ContractStatus status;

  // 사업주 서명
  final String? employerSignatureUrl;
  final DateTime? employerSignedAt;

  // 근무자 서명
  final String? workerSignatureUrl;
  final DateTime? workerSignedAt;

  // 완성 PDF
  final String? pdfUrl;

  // 서명 시점 계약 내용 스냅샷
  final ContractSnapshot snapshot;

  // 관리자가 선택한 템플릿의 조항 복사본 (서명 시점 고정)
  final List<ContractArticle> articles;
  final String? templateId;

  final DateTime createdAt;
  final DateTime? updatedAt;

  /// voidContract 실행 후 취소 실패한 applicationId 목록.
  /// 비어있으면 정상 완료. 있으면 관리자가 재처리 필요.
  /// toMap()에 포함하지 않음 — Firestore .update()로만 관리.
  final List<String> voidFailedAppIds;

  /// Firestore에 아직 저장되지 않은 미리보기 상태 (서명 시 최초 저장됨)
  /// toMap/fromFirestore에 포함되지 않는 트랜지언트 필드
  final bool isNewUnsaved;

  const EmploymentContractModel({
    required this.id,
    required this.applicationId,
    required this.businessId,
    required this.workerId,
    required this.isLongTerm,
    required this.toId,
    required this.workDetailId,
    this.slots = const [],
    this.applicationIds = const [],
    required this.status,
    this.employerSignatureUrl,
    this.employerSignedAt,
    this.workerSignatureUrl,
    this.workerSignedAt,
    this.pdfUrl,
    required this.snapshot,
    this.articles = const [],
    this.templateId,
    required this.createdAt,
    this.updatedAt,
    this.voidFailedAppIds = const [],
    this.isNewUnsaved = false,
  });

  bool get isCompleted => status == ContractStatus.completed;
  bool get needsEmployerSignature => status == ContractStatus.pendingEmployer;
  bool get needsWorkerSignature => status == ContractStatus.pendingWorker;
  bool get hasVoidFailedApps => voidFailedAppIds.isNotEmpty;

  factory EmploymentContractModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) {
      throw ArgumentError('EmploymentContractModel.fromFirestore: 문서 데이터 없음 (id: ${doc.id})');
    }
    return EmploymentContractModel.fromMap(raw as Map<String, dynamic>, doc.id);
  }

  // [SCHEMA-09] 역직렬화 실패 격리
  static EmploymentContractModel? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return EmploymentContractModel.fromFirestore(doc);
    } catch (e, st) {
      debugPrint('[EmploymentContractModel] 역직렬화 실패 id=${doc.id}: $e\n$st');
      return null;
    }
  }

  factory EmploymentContractModel.fromMap(Map<String, dynamic> d, String id) {
    final rawSlots = d['slots'] as List<dynamic>?;
    final rawArticles = d['articles'] as List<dynamic>?;
    return EmploymentContractModel(
      id: id,
      applicationId: d['applicationId'] ?? '',
      businessId: d['businessId'] ?? '',
      workerId: d['workerId'] ?? '',
      isLongTerm: d['isLongTerm'] ?? false,
      toId: d['toId'] ?? '',
      workDetailId: d['workDetailId'] ?? '',
      // [CRASH-GUARD] whereType<Map>()은 Dart에서 LinkedHashMap 등 모든 Map 구현체 포함 — 안전
      slots: rawSlots != null
          ? rawSlots.whereType<Map>()
              .map((s) { try { return ContractSlot.fromMap(Map<String, dynamic>.from(s)); } catch (_) { return null; } })
              .whereType<ContractSlot>()
              .toList()
          : [],
      applicationIds: d['applicationIds'] != null
          ? List<String>.from(d['applicationIds'] as List)
          : [],
      status: ContractStatusX.fromString(d['status'] ?? 'pending_employer'),
      employerSignatureUrl: d['employerSignatureUrl'],
      employerSignedAt: parseTimestampNullable(d['employerSignedAt']),
      workerSignatureUrl: d['workerSignatureUrl'],
      workerSignedAt: parseTimestampNullable(d['workerSignedAt']),
      pdfUrl: d['pdfUrl'],
      snapshot: d['snapshot'] != null
          ? ContractSnapshot.fromMap(
              Map<String, dynamic>.from(d['snapshot'] as Map))
          : (throw ArgumentError('EmploymentContractModel: snapshot 필드 누락 (id: $id)')),
      articles: rawArticles != null
          ? rawArticles
              .map((a) { try { return ContractArticle.fromMap(Map<String, dynamic>.from(a as Map)); } catch (_) { return null; } })
              .whereType<ContractArticle>()
              .toList()
          : [],
      templateId: d['templateId'] as String?,
      createdAt: d['createdAt'] != null
          ? parseTimestamp(d['createdAt'])
          : (throw ArgumentError('EmploymentContractModel: createdAt 필드 누락 (id: $id)')),
      updatedAt: parseTimestampNullable(d['updatedAt']),
      voidFailedAppIds: d['voidFailedAppIds'] != null
          ? List<String>.from(d['voidFailedAppIds'] as List)
          : [],
    );
  }

  Map<String, dynamic> toMap() => {
    'applicationId': applicationId,
    'businessId': businessId,
    'workerId': workerId,
    'isLongTerm': isLongTerm,
    'toId': toId,
    'workDetailId': workDetailId,
    'slots': slots.map((s) => s.toMap()).toList(),
    'applicationIds': applicationIds,
    'status': status.value,
    'employerSignatureUrl': employerSignatureUrl,
    'employerSignedAt': employerSignedAt != null
        ? Timestamp.fromDate(employerSignedAt!)
        : null,
    'workerSignatureUrl': workerSignatureUrl,
    'workerSignedAt': workerSignedAt != null
        ? Timestamp.fromDate(workerSignedAt!)
        : null,
    'pdfUrl': pdfUrl,
    'snapshot': snapshot.toMap(),
    'articles': articles.map((a) => a.toMap()).toList(),
    'templateId': templateId,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
  };

  EmploymentContractModel copyWith({
    ContractStatus? status,
    List<ContractSlot>? slots,
    List<String>? applicationIds,
    String? employerSignatureUrl,
    DateTime? employerSignedAt,
    String? workerSignatureUrl,
    DateTime? workerSignedAt,
    String? pdfUrl,
    List<ContractArticle>? articles,
    String? templateId,
    DateTime? updatedAt,
    List<String>? voidFailedAppIds,
  }) {
    return EmploymentContractModel(
      id: id,
      applicationId: applicationId,
      businessId: businessId,
      workerId: workerId,
      isLongTerm: isLongTerm,
      toId: toId,
      workDetailId: workDetailId,
      slots: slots ?? this.slots,
      applicationIds: applicationIds ?? this.applicationIds,
      status: status ?? this.status,
      employerSignatureUrl: employerSignatureUrl ?? this.employerSignatureUrl,
      employerSignedAt: employerSignedAt ?? this.employerSignedAt,
      workerSignatureUrl: workerSignatureUrl ?? this.workerSignatureUrl,
      workerSignedAt: workerSignedAt ?? this.workerSignedAt,
      pdfUrl: pdfUrl ?? this.pdfUrl,
      snapshot: snapshot,
      articles: articles ?? this.articles,
      templateId: templateId ?? this.templateId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      voidFailedAppIds: voidFailedAppIds ?? this.voidFailedAppIds,
      isNewUnsaved: isNewUnsaved,
    );
  }
}
