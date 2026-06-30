import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class PayrollWorkerSummary {
  final String workerId;
  final String name;
  final int totalPayout;
  final int workDays;

  const PayrollWorkerSummary({
    required this.workerId,
    required this.name,
    required this.totalPayout,
    required this.workDays,
  });

  factory PayrollWorkerSummary.fromMap(String workerId, Map<String, dynamic> map) {
    return PayrollWorkerSummary(
      workerId: workerId,
      name: map['name'] as String? ?? '',
      totalPayout: (map['totalPayout'] as num?)?.toInt() ?? 0,
      workDays: (map['workDays'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() => {
    'name': name,
    'totalPayout': totalPayout,
    'workDays': workDays,
  };
}

class PayrollSummaryModel {
  final String id; // {businessId}_{YYYY-MM}
  final String businessId;
  final String yearMonth; // 'YYYY-MM'
  final int year;
  final int month;
  final int totalPayout;
  final int confirmedCount;
  final int workerCount;
  final int pendingCount;         // 미확정 (wagePending/wageCalculated)
  final int notTransferredCount;  // 미이체 (wageConfirmed)
  final Map<String, PayrollWorkerSummary> workers;
  final DateTime updatedAt;

  const PayrollSummaryModel({
    required this.id,
    required this.businessId,
    required this.yearMonth,
    required this.year,
    required this.month,
    required this.totalPayout,
    required this.confirmedCount,
    required this.workerCount,
    this.pendingCount = 0,
    this.notTransferredCount = 0,
    required this.workers,
    required this.updatedAt,
  });

  factory PayrollSummaryModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) {
      throw ArgumentError('PayrollSummaryModel: document ${doc.id} has no data');
    }
    final data = raw as Map<String, dynamic>;
    // [MED-SAFE] 오프라인 쓰기 직후 읽기 시 updatedAt에 FieldValue.serverTimestamp()가 null로 반환될 수 있음.
    // ArgumentError 대신 DateTime.now() 폴백으로 crash 방지
    final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate().toLocal() ?? DateTime.now();
    final workersRaw = data['workers'] as Map<String, dynamic>? ?? {};
    final workers = workersRaw.map(
      // [SAFETY] Firestore 내부 타입(_JsonMap)은 직접 as Map<String, dynamic> 캐스팅 실패 가능 — from()으로 안전 변환
      (k, v) => MapEntry(k, PayrollWorkerSummary.fromMap(k, Map<String, dynamic>.from(v as Map))),
    );
    return PayrollSummaryModel(
      id: doc.id,
      businessId: data['businessId'] as String? ?? '',
      yearMonth: data['yearMonth'] as String? ?? '',
      year: (data['year'] as num?)?.toInt() ?? 0,
      month: (data['month'] as num?)?.toInt() ?? 0,
      totalPayout: (data['totalPayout'] as num?)?.toInt() ?? 0,
      confirmedCount: (data['confirmedCount'] as num?)?.toInt() ?? 0,
      workerCount: (data['workerCount'] as num?)?.toInt() ?? 0,
      pendingCount: (data['pendingCount'] as num?)?.toInt() ?? 0,
      notTransferredCount: (data['notTransferredCount'] as num?)?.toInt() ?? 0,
      workers: workers,
      updatedAt: updatedAt,
    );
  }

  // [SCHEMA-09] 역직렬화 실패 격리 — workers 맵 손상 시 급여 조회 화면 전체 크래시 방지
  static PayrollSummaryModel? tryFromFirestore(DocumentSnapshot doc) {
    try {
      return PayrollSummaryModel.fromFirestore(doc);
    } catch (e, st) {
      debugPrint('[PayrollSummaryModel] 역직렬화 실패 id=${doc.id}: $e\n$st');
      return null;
    }
  }

  /// 빈 요약 (해당 월 데이터 없음)
  factory PayrollSummaryModel.empty({
    required String businessId,
    required int year,
    required int month,
  }) {
    final mm = month.toString().padLeft(2, '0');
    return PayrollSummaryModel(
      id: '${businessId}_$year-$mm',
      businessId: businessId,
      yearMonth: '$year-$mm',
      year: year,
      month: month,
      totalPayout: 0,
      confirmedCount: 0,
      workerCount: 0,
      workers: {},
      updatedAt: DateTime.now(),
    );
  }

  bool get isEmpty => confirmedCount == 0 && pendingCount == 0;

  String get formattedTotalPayout {
    if (totalPayout == 0) return '-';
    return '${totalPayout.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    )}원';
  }

  List<PayrollWorkerSummary> get sortedWorkers =>
      workers.values.toList()..sort((a, b) => b.totalPayout.compareTo(a.totalPayout));
}
