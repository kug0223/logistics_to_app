// admin_home_summary_model.dart
// PHASE 1 — Admin Home Summary Data Layer
// callableGetAdminHomeSummary 응답 모델
//
// 각 섹션: available (쿼리 성공 여부), count, byBusiness 배열
// available:false → "데이터 로드 실패" 표시 (0과 명시적으로 구분)

import 'package:cloud_functions/cloud_functions.dart';

// ─── 기본 섹션 모델 ──────────────────────────────────────────────────────────

/// 단순 카운트 섹션 (byBusiness: [{businessId, count}])
class AdminHomeSimpleSection {
  final bool available;
  final int count;
  final List<AdminHomeSimpleBizCount> byBusiness;

  const AdminHomeSimpleSection({
    required this.available,
    required this.count,
    required this.byBusiness,
  });

  factory AdminHomeSimpleSection.fromMap(Map<String, dynamic> map) {
    return AdminHomeSimpleSection(
      available: (map['available'] as bool?) ?? false,
      count: (map['count'] as num?)?.toInt() ?? 0,
      byBusiness: ((map['byBusiness'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => AdminHomeSimpleBizCount.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  /// 권한 없음 (available:false, count:0)
  static const AdminHomeSimpleSection noAccess =
      AdminHomeSimpleSection(available: false, count: 0, byBusiness: []);

  bool get hasData => available && count > 0;
}

class AdminHomeSimpleBizCount {
  final String businessId;
  final int count;

  const AdminHomeSimpleBizCount({required this.businessId, required this.count});

  factory AdminHomeSimpleBizCount.fromMap(Map<String, dynamic> map) {
    return AdminHomeSimpleBizCount(
      businessId: (map['businessId'] as String?) ?? '',
      count: (map['count'] as num?)?.toInt() ?? 0,
    );
  }
}

// ─── Approval 섹션 ───────────────────────────────────────────────────────────

class AdminHomeApprovalSection {
  final bool available;
  final int count;
  final int overdueCount;
  final List<AdminHomeApprovalBizCount> byBusiness;

  const AdminHomeApprovalSection({
    required this.available,
    required this.count,
    required this.overdueCount,
    required this.byBusiness,
  });

  factory AdminHomeApprovalSection.fromMap(Map<String, dynamic> map) {
    return AdminHomeApprovalSection(
      available: (map['available'] as bool?) ?? false,
      count: (map['count'] as num?)?.toInt() ?? 0,
      overdueCount: (map['overdueCount'] as num?)?.toInt() ?? 0,
      byBusiness: ((map['byBusiness'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => AdminHomeApprovalBizCount.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  static const AdminHomeApprovalSection noAccess =
      AdminHomeApprovalSection(available: false, count: 0, overdueCount: 0, byBusiness: []);

  bool get hasData => available && count > 0;
  bool get hasOverdue => overdueCount > 0;
}

class AdminHomeApprovalBizCount {
  final String businessId;
  final int count;
  final int overdueCount;

  const AdminHomeApprovalBizCount({
    required this.businessId,
    required this.count,
    required this.overdueCount,
  });

  factory AdminHomeApprovalBizCount.fromMap(Map<String, dynamic> map) {
    return AdminHomeApprovalBizCount(
      businessId: (map['businessId'] as String?) ?? '',
      count: (map['count'] as num?)?.toInt() ?? 0,
      overdueCount: (map['overdueCount'] as num?)?.toInt() ?? 0,
    );
  }
}

// ─── Unpaid Wage 섹션 ────────────────────────────────────────────────────────

class AdminHomeUnpaidWageSection {
  /// canonical unit: businessId × userId × paymentDueDate 그룹 수
  final bool available;
  final int count;
  final int overdueCount;

  /// paymentDueDate가 null인 confirmed attendance 건수
  final int missingDueDateCount;
  final List<AdminHomeUnpaidWageBizCount> byBusiness;

  const AdminHomeUnpaidWageSection({
    required this.available,
    required this.count,
    required this.overdueCount,
    required this.missingDueDateCount,
    required this.byBusiness,
  });

  factory AdminHomeUnpaidWageSection.fromMap(Map<String, dynamic> map) {
    return AdminHomeUnpaidWageSection(
      available: (map['available'] as bool?) ?? false,
      count: (map['count'] as num?)?.toInt() ?? 0,
      overdueCount: (map['overdueCount'] as num?)?.toInt() ?? 0,
      missingDueDateCount: (map['missingDueDateCount'] as num?)?.toInt() ?? 0,
      byBusiness: ((map['byBusiness'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => AdminHomeUnpaidWageBizCount.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  static const AdminHomeUnpaidWageSection noAccess = AdminHomeUnpaidWageSection(
    available: false, count: 0, overdueCount: 0, missingDueDateCount: 0, byBusiness: [],
  );

  bool get hasData => available && (count > 0 || missingDueDateCount > 0);
  bool get hasOverdue => overdueCount > 0;
  bool get hasMissingDueDate => missingDueDateCount > 0;
}

class AdminHomeUnpaidWageBizCount {
  final String businessId;
  final int count;
  final int overdueCount;
  final int missingDueDateCount;

  const AdminHomeUnpaidWageBizCount({
    required this.businessId,
    required this.count,
    required this.overdueCount,
    required this.missingDueDateCount,
  });

  factory AdminHomeUnpaidWageBizCount.fromMap(Map<String, dynamic> map) {
    return AdminHomeUnpaidWageBizCount(
      businessId: (map['businessId'] as String?) ?? '',
      count: (map['count'] as num?)?.toInt() ?? 0,
      overdueCount: (map['overdueCount'] as num?)?.toInt() ?? 0,
      missingDueDateCount: (map['missingDueDateCount'] as num?)?.toInt() ?? 0,
    );
  }
}

// ─── Unclosed 섹션 ───────────────────────────────────────────────────────────

class AdminHomeUnclosedSection {
  /// canonical unit: businessId × date 기준 미처리 날짜 수
  final bool available;
  final int count;

  /// 가장 오래된 미처리 날짜 ('YYYY-MM-DD', KST 기준) — null이면 없음
  final String? oldestDate;
  final List<AdminHomeUnclosedBizCount> byBusiness;

  const AdminHomeUnclosedSection({
    required this.available,
    required this.count,
    required this.oldestDate,
    required this.byBusiness,
  });

  factory AdminHomeUnclosedSection.fromMap(Map<String, dynamic> map) {
    return AdminHomeUnclosedSection(
      available: (map['available'] as bool?) ?? false,
      count: (map['count'] as num?)?.toInt() ?? 0,
      oldestDate: map['oldestDate'] as String?,
      byBusiness: ((map['byBusiness'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => AdminHomeUnclosedBizCount.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  static const AdminHomeUnclosedSection noAccess =
      AdminHomeUnclosedSection(available: false, count: 0, oldestDate: null, byBusiness: []);

  bool get hasData => available && count > 0;
}

class AdminHomeUnclosedBizCount {
  final String businessId;
  final int count;
  final String? oldestDate;

  const AdminHomeUnclosedBizCount({
    required this.businessId,
    required this.count,
    required this.oldestDate,
  });

  factory AdminHomeUnclosedBizCount.fromMap(Map<String, dynamic> map) {
    return AdminHomeUnclosedBizCount(
      businessId: (map['businessId'] as String?) ?? '',
      count: (map['count'] as num?)?.toInt() ?? 0,
      oldestDate: map['oldestDate'] as String?,
    );
  }
}

// ─── Actions / Upcoming 집합 ─────────────────────────────────────────────────

class AdminHomeActionsData {
  /// PENDING 지원 승인 대기
  final AdminHomeApprovalSection approval;

  /// 미발송 계약서 (CONTRACT_PENDING + 계약서 없음)
  final AdminHomeSimpleSection unsentContract;

  /// 급여 미이체 (wageStatus=confirmed 그룹, canonical: uid×paymentDueDate)
  final AdminHomeUnpaidWageSection unpaidWage;

  /// 마감 미처리 날짜 수 (all-time, canonical: businessId×date)
  final AdminHomeUnclosedSection unclosed;

  /// 급여 지급방식 변경 요청 (PENDING)
  final AdminHomeSimpleSection wageChangeRequest;

  /// 중간정산 요청 (PENDING)
  final AdminHomeSimpleSection settlementRequest;

  const AdminHomeActionsData({
    required this.approval,
    required this.unsentContract,
    required this.unpaidWage,
    required this.unclosed,
    required this.wageChangeRequest,
    required this.settlementRequest,
  });

  factory AdminHomeActionsData.fromMap(Map<String, dynamic> map) {
    return AdminHomeActionsData(
      approval: AdminHomeApprovalSection.fromMap(
        Map<String, dynamic>.from((map['approval'] as Map?) ?? {}),
      ),
      unsentContract: AdminHomeSimpleSection.fromMap(
        Map<String, dynamic>.from((map['unsentContract'] as Map?) ?? {}),
      ),
      unpaidWage: AdminHomeUnpaidWageSection.fromMap(
        Map<String, dynamic>.from((map['unpaidWage'] as Map?) ?? {}),
      ),
      unclosed: AdminHomeUnclosedSection.fromMap(
        Map<String, dynamic>.from((map['unclosed'] as Map?) ?? {}),
      ),
      wageChangeRequest: AdminHomeSimpleSection.fromMap(
        Map<String, dynamic>.from((map['wageChangeRequest'] as Map?) ?? {}),
      ),
      settlementRequest: AdminHomeSimpleSection.fromMap(
        Map<String, dynamic>.from((map['settlementRequest'] as Map?) ?? {}),
      ),
    );
  }

  /// 처리할 액션이 하나라도 있는지
  bool get hasAnyAction =>
      approval.hasData ||
      unsentContract.hasData ||
      unpaidWage.hasData ||
      unclosed.hasData ||
      wageChangeRequest.hasData ||
      settlementRequest.hasData;

  /// 전체 액션 건수 합산 (배지용)
  int get totalActionCount =>
      approval.count +
      unsentContract.count +
      unpaidWage.count +
      unclosed.count +
      wageChangeRequest.count +
      settlementRequest.count;
}

class AdminHomeUpcomingData {
  /// 계약 만료 예정 (D+15 이내)
  final AdminHomeSimpleSection expiringContract;

  const AdminHomeUpcomingData({required this.expiringContract});

  factory AdminHomeUpcomingData.fromMap(Map<String, dynamic> map) {
    return AdminHomeUpcomingData(
      expiringContract: AdminHomeSimpleSection.fromMap(
        Map<String, dynamic>.from((map['expiringContract'] as Map?) ?? {}),
      ),
    );
  }
}

// ─── 최상위 모델 ─────────────────────────────────────────────────────────────

class AdminHomeScopeData {
  final int businessCount;
  const AdminHomeScopeData({required this.businessCount});
  factory AdminHomeScopeData.fromMap(Map<String, dynamic> map) =>
      AdminHomeScopeData(businessCount: (map['businessCount'] as num?)?.toInt() ?? 0);
}

class AdminHomeSummaryModel {
  final AdminHomeScopeData scope;
  final AdminHomeActionsData actions;
  final AdminHomeUpcomingData upcoming;
  final DateTime generatedAt;

  const AdminHomeSummaryModel({
    required this.scope,
    required this.actions,
    required this.upcoming,
    required this.generatedAt,
  });

  factory AdminHomeSummaryModel.fromMap(Map<String, dynamic> map) {
    return AdminHomeSummaryModel(
      scope: AdminHomeScopeData.fromMap(
        Map<String, dynamic>.from((map['scope'] as Map?) ?? {}),
      ),
      actions: AdminHomeActionsData.fromMap(
        Map<String, dynamic>.from((map['actions'] as Map?) ?? {}),
      ),
      upcoming: AdminHomeUpcomingData.fromMap(
        Map<String, dynamic>.from((map['upcoming'] as Map?) ?? {}),
      ),
      generatedAt: DateTime.fromMillisecondsSinceEpoch(
        (map['generatedAt'] as num?)?.toInt() ?? 0,
      ),
    );
  }

  /// Cloud Functions 응답(HttpsCallableResult)에서 직접 파싱
  /// cloud_functions v5에서 result.data는 런타임에 Map(String → dynamic) 호환
  factory AdminHomeSummaryModel.fromCallable(HttpsCallableResult result) {
    final raw = result.data;
    if (raw is! Map) {
      throw Exception('[adminHomeSummary] CF 응답 형식 오류: Map이 아님 (${raw.runtimeType})');
    }
    return AdminHomeSummaryModel.fromMap(Map<String, dynamic>.from(raw));
  }
}
