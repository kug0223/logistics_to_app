import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../utils/transfer_export_plan.dart';

/// [PII-DOC-R1.6.1] 근로자에게 열려 있는 서류 보완 요청 하나.
///
///   `sourceDomain`이 두 종류다:
///     APPLICATION  관리자가 지원자 검토에서 다시 등록을 요청한 것
///     PAYROLL      지급이 막혀 지급 판정이 연 것
///
///   둘 다 근로자가 서류를 고쳐야 풀리지만, 문맥이 다르므로 문구가 다르다.
class DocumentCorrectionTask {
  const DocumentCorrectionTask({
    required this.requestId,
    required this.businessId,
    required this.businessName,
    required this.documentType,
    required this.sourceDomain,
    this.payrollReadinessState,
    this.reasonCode,
    this.reasonNote,
  });

  final String requestId;
  final String businessId;
  final String businessName;

  /// 'ID_CARD' | 'BANKBOOK'
  final String documentType;

  /// 'APPLICATION' | 'PAYROLL'
  final String sourceDomain;

  /// PAYROLL일 때만 — [PayrollReadinessReason]의 상수.
  final String? payrollReadinessState;
  final String? reasonCode;
  final String? reasonNote;

  bool get isPayroll => sourceDomain == 'PAYROLL';

  /// 할 일 제목 — 무엇을 해야 하는지 한 줄로.
  String get title {
    if (isPayroll) {
      return PayrollReadinessReason.workerActionOf(payrollReadinessState);
    }
    return documentType == 'ID_CARD'
        ? '신분증을 다시 등록해주세요.'
        : '통장사본을 다시 등록해주세요.';
  }

  /// 왜 필요한지 — 사업장 문맥.
  String subtitleFor() {
    final biz = businessName.isEmpty ? '사업장' : businessName;
    return isPayroll
        ? '$biz 급여 지급을 위해 필요해요'
        : '$biz에서 서류 재등록을 요청했어요';
  }

  static DocumentCorrectionTask fromMap(Map<String, dynamic> m) =>
      DocumentCorrectionTask(
        requestId: (m['requestId'] ?? '') as String,
        businessId: (m['businessId'] ?? '') as String,
        businessName: (m['businessName'] ?? '') as String,
        documentType: (m['documentType'] ?? '') as String,
        sourceDomain: (m['sourceDomain'] ?? 'APPLICATION') as String,
        payrollReadinessState: m['payrollReadinessState'] as String?,
        reasonCode: m['reasonCode'] as String?,
        reasonNote: m['reasonNote'] as String?,
      );
}

/// 조회 결과 — 못 읽은 것과 없는 것을 구분한다.
///
///   조회 실패를 "할 일 없음"으로 바꾸면, 실제로 막혀 있는 급여를
///   근로자가 영원히 모르게 된다. UNKNOWN ≠ EMPTY.
class DocumentCorrectionSurface {
  const DocumentCorrectionSurface._(this.tasks, this.loadFailed);

  final List<DocumentCorrectionTask> tasks;
  final bool loadFailed;

  static const DocumentCorrectionSurface empty =
      DocumentCorrectionSurface._(<DocumentCorrectionTask>[], false);
  static const DocumentCorrectionSurface failed =
      DocumentCorrectionSurface._(<DocumentCorrectionTask>[], true);

  bool get hasTasks => tasks.isNotEmpty;

  /// 지급 때문에 막힌 할 일을 먼저 보여준다 — 돈이 걸려 있다.
  DocumentCorrectionTask? get primary {
    if (tasks.isEmpty) return null;
    for (final t in tasks) {
      if (t.isPayroll) return t;
    }
    return tasks.first;
  }
}

/// 근로자 본인의 열린 보완 요청만 읽는다. 남의 것은 서버가 주지 않는다.
class PayrollCorrectionService {
  PayrollCorrectionService._();

  static Future<DocumentCorrectionSurface> loadMine() async {
    try {
      final res = await FirebaseFunctions.instanceFor(
              region: 'asia-northeast3')
          .httpsCallable('callableGetMyDocumentCorrections')
          .call<Map<String, dynamic>>();
      final raw = (res.data['requests'] as List<dynamic>?) ?? <dynamic>[];
      final tasks = raw
          .whereType<Map>()
          .map((e) => DocumentCorrectionTask.fromMap(
              Map<String, dynamic>.from(e)))
          .toList();
      return DocumentCorrectionSurface._(tasks, false);
    } catch (e) {
      debugPrint('❌ 보완 요청 조회 실패: $e');
      return DocumentCorrectionSurface.failed;
    }
  }
}
