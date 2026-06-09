import 'package:cloud_firestore/cloud_firestore.dart';

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
    required this.workers,
    required this.updatedAt,
  });

  factory PayrollSummaryModel.fromFirestore(DocumentSnapshot doc) {
    final raw = doc.data();
    if (raw == null) {
      throw ArgumentError('PayrollSummaryModel: document ${doc.id} has no data');
    }
    final data = raw as Map<String, dynamic>;
    final updatedAt = (data['updatedAt'] as Timestamp?)?.toDate().toLocal();
    if (updatedAt == null) {
      throw ArgumentError('PayrollSummaryModel: updatedAt is missing (id=${doc.id})');
    }
    final workersRaw = data['workers'] as Map<String, dynamic>? ?? {};
    final workers = workersRaw.map(
      (k, v) => MapEntry(k, PayrollWorkerSummary.fromMap(k, v as Map<String, dynamic>)),
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
      workers: workers,
      updatedAt: updatedAt,
    );
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

  bool get isEmpty => confirmedCount == 0;

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
