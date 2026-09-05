import 'package:cloud_functions/cloud_functions.dart';

import '../models/core/historical_contract_detail.dart';
import '../models/core/historical_contract_summary.dart';

/// 보관된 계약서 조회 서비스.
/// - CF 오류는 그대로 rethrow (Toast/context 없음 — 호출자가 처리).
/// - getHistoricalContractById: not-found 시 null 반환.
class HistoricalContractService {
  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 보관된 계약서 목록 조회 (커서 기반 페이지네이션).
  ///
  /// [pageSize]: 1~100, 기본값 20.
  /// [lastDocId]: 이전 페이지의 마지막 contractId. null이면 첫 페이지.
  ///
  /// 반환: `({contracts, lastDocId, hasMore})`
  /// - contracts: 현재 페이지 계약서 목록
  /// - lastDocId: 다음 페이지 커서 (null이면 다음 페이지 없음)
  /// - hasMore: 추가 페이지 존재 여부
  Future<
      ({
        List<HistoricalContractSummary> contracts,
        String? lastDocId,
        bool hasMore,
      })> getHistoricalContracts({
    int pageSize = 20,
    String? lastDocId,
  }) async {
    final callable = _fn.httpsCallable('callableGetHistoricalContracts');
    final result = await callable.call<Map<Object?, Object?>>({
      'pageSize': pageSize,
      if (lastDocId != null) 'lastDocId': lastDocId,
    });

    final data = Map<String, dynamic>.from(result.data);
    final rawList = data['contracts'];
    final List<HistoricalContractSummary> contracts = rawList is List
        ? rawList
            .whereType<Map>()
            .map((e) => HistoricalContractSummary.fromMap(
                  Map<String, dynamic>.from(e),
                ))
            .toList()
        : [];

    return (
      contracts: contracts,
      lastDocId: data['lastDocId'] as String?,
      hasMore: data['hasMore'] as bool? ?? false,
    );
  }

  /// 보관된 계약서 상세 조회.
  ///
  /// [contractId]: 조회할 계약서 ID.
  /// 계약서가 없거나 권한이 없으면 null 반환.
  /// 그 외 오류는 rethrow.
  Future<HistoricalContractDetail?> getHistoricalContractById(
    String contractId,
  ) async {
    if (contractId.trim().isEmpty) {
      throw ArgumentError.value(
        contractId,
        'contractId',
        'contractId must not be empty',
      );
    }
    try {
      final callable = _fn.httpsCallable('callableGetHistoricalContractById');
      final result = await callable.call<Map<Object?, Object?>>({
        'contractId': contractId,
      });
      final data = Map<String, dynamic>.from(result.data);
      return HistoricalContractDetail.fromMap(data);
    } on FirebaseFunctionsException catch (e) {
      if (e.code == 'not-found') return null;
      rethrow;
    }
  }
}
