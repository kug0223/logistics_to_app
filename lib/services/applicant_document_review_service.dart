import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../utils/global_loading_controller.dart';
import '../utils/toast_helper.dart';

/// [DOCUMENT-VERIFICATION-INTEGRITY-R1.2] 사업장의 지원자 서류 검토.
///
/// 상태 판정은 전부 서버가 한다. 이 클래스는 서버가 준 값을 나르기만 한다 —
/// 낡음(stale)을 화면이 다시 계산하면 두 곳이 서로 다른 답을 갖게 된다.
class ApplicantDocumentReviewService {
  static final ApplicantDocumentReviewService instance =
      ApplicantDocumentReviewService._();
  ApplicantDocumentReviewService._();

  HttpsCallable _fn(String name, {int seconds = 20}) =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3').httpsCallable(
        name,
        options: HttpsCallableOptions(timeout: Duration(seconds: seconds)),
      );

  /// 지원자 상세가 읽는 단일 projection. 실패는 던진다 — 빈 값으로 바꾸지 않는다.
  Future<ApplicantDocumentReview> load({
    required String applicationId,
    required String businessId,
  }) async {
    final r = await _fn('callableGetApplicantDocumentReview')
        .call<Map<String, dynamic>>({
      'applicationId': applicationId,
      'businessId': businessId,
    });
    return ApplicantDocumentReview.fromMap(Map<String, dynamic>.from(r.data as Map));
  }

  /// 서류 이미지 1시간 Signed URL. 경로는 서버가 정한다.
  Future<String?> documentUrl({
    required String applicationId,
    required String businessId,
    required String targetUid,
    required String documentType,
  }) async {
    GlobalLoadingController.show('서류를 불러오는 중...');
    try {
      final r = await _fn('callableGetApplicantDocumentUrl')
          .call<Map<String, dynamic>>({
        'applicationId': applicationId,
        'businessId': businessId,
        'targetUid': targetUid,
        'documentType': documentType,
      });
      return (Map<String, dynamic>.from(r.data as Map))['signedUrl'] as String?;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ documentUrl 실패: ${e.code} ${e.message}');
      ToastHelper.showError(e.message ?? '서류를 불러오지 못했습니다.');
      return null;
    } finally {
      GlobalLoadingController.hide();
    }
  }

  /// 확인 완료 / 재등록 요청 기록.
  ///
  /// [expectedVersion]은 관리자가 **실제로 본** 문서의 버전이다. 그 사이
  /// 근로자가 다시 올렸으면 서버가 거절한다 — 본 적 없는 문서를 승인하지 않는다.
  Future<bool> review({
    required String applicationId,
    required String businessId,
    required String targetUid,
    required String documentType,
    required String decision,
    required int expectedVersion,
    int? expectedAccountVersion,
    String? note,
  }) async {
    GlobalLoadingController.show('처리 중...');
    try {
      await _fn('callableReviewApplicantDocument').call<Map<String, dynamic>>({
        'applicationId': applicationId,
        'businessId': businessId,
        'targetUid': targetUid,
        'documentType': documentType,
        'decision': decision,
        'expectedVersion': expectedVersion,
        if (expectedAccountVersion != null)
          'expectedAccountVersion': expectedAccountVersion,
        if (note != null) 'note': note,
      });
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ review 실패: ${e.code} ${e.message}');
      ToastHelper.showError(e.message ?? '처리에 실패했습니다.');
      return false;
    } finally {
      GlobalLoadingController.hide();
    }
  }

  /// 재등록 요청. 지원서는 PENDING 그대로다 — 거절이 아니다.
  Future<bool> requestCorrection({
    required String applicationId,
    required String businessId,
    required String targetUid,
    required String documentType,
    required String reasonCode,
    String? note,
  }) async {
    GlobalLoadingController.show('요청을 보내는 중...');
    try {
      await _fn('callableRequestDocumentCorrection').call<Map<String, dynamic>>({
        'applicationId': applicationId,
        'businessId': businessId,
        'targetUid': targetUid,
        'documentType': documentType,
        'reasonCode': reasonCode,
        if (note != null) 'note': note,
      });
      return true;
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ requestCorrection 실패: ${e.code} ${e.message}');
      ToastHelper.showError(e.message ?? '요청에 실패했습니다.');
      return false;
    } finally {
      GlobalLoadingController.hide();
    }
  }
}

/// 서버가 계산한 검토 상태. 화면은 이 값을 그린다.
class ApplicantDocumentReview {
  final String workerUid;

  /// 이 관리자가 서류 이미지·계좌 원문을 볼 자격이 있는가.
  final bool canReviewDocuments;

  /// 열람이 막힌 이유 (동의 미비 등). null이면 막힌 것이 없다.
  final String? consentBlock;

  final int idVersion;
  final int bankbookVersion;
  final int accountVersion;

  final bool ready;
  final String idDecision;
  final String bankDecision;
  final bool idStale;
  final bool bankStale;
  final String? reason;

  final bool hasIdCard;
  final bool hasBankbook;

  /// 자격이 있을 때만 채워진다. 없으면 null — 서버가 키 자체를 주지 않는다.
  final String? bankName;
  final String? accountNumber;
  final String? accountHolder;

  final List<String> openCorrectionTypes;

  const ApplicantDocumentReview({
    required this.workerUid,
    required this.canReviewDocuments,
    required this.consentBlock,
    required this.idVersion,
    required this.bankbookVersion,
    required this.accountVersion,
    required this.ready,
    required this.idDecision,
    required this.bankDecision,
    required this.idStale,
    required this.bankStale,
    required this.reason,
    required this.hasIdCard,
    required this.hasBankbook,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
    required this.openCorrectionTypes,
  });

  factory ApplicantDocumentReview.fromMap(Map<String, dynamic> m) {
    final v = Map<String, dynamic>.from((m['versions'] as Map?) ?? {});
    final r = Map<String, dynamic>.from((m['readiness'] as Map?) ?? {});
    final d = Map<String, dynamic>.from((m['documents'] as Map?) ?? {});
    final b = m['bank'] is Map ? Map<String, dynamic>.from(m['bank'] as Map) : null;
    final corr = ((m['openCorrections'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => (e['documentType'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .toList();
    int n(dynamic x) => x is int ? x : 0;
    return ApplicantDocumentReview(
      workerUid: (m['workerUid'] as String?) ?? '',
      canReviewDocuments: m['canReviewDocuments'] == true,
      consentBlock: m['consentBlock'] as String?,
      idVersion: n(v['id']),
      bankbookVersion: n(v['bankbook']),
      accountVersion: n(v['account']),
      ready: r['ready'] == true,
      idDecision: (r['idDecision'] as String?) ?? 'NOT_REVIEWED',
      bankDecision: (r['bankDecision'] as String?) ?? 'NOT_REVIEWED',
      idStale: r['idStale'] == true,
      bankStale: r['bankStale'] == true,
      reason: r['reason'] as String?,
      hasIdCard: d['hasIdCard'] == true,
      hasBankbook: d['hasBankbook'] == true,
      bankName: b?['bankName'] as String?,
      accountNumber: b?['accountNumber'] as String?,
      accountHolder: b?['accountHolder'] as String?,
      openCorrectionTypes: corr,
    );
  }

  /// 항목별 표시 상태. '확인 완료'는 사업장이 확인했다는 뜻이지
  /// 진위 보증이 아니다 — 문구를 그렇게 쓴다.
  String labelFor({required bool isId}) {
    final decision = isId ? idDecision : bankDecision;
    final stale = isId ? idStale : bankStale;
    if (stale) return '변경됨 · 재확인 필요';
    switch (decision) {
      case 'REVIEWED_OK':
        return isId ? '서류 확인 완료' : '계좌·통장 확인 완료';
      case 'REUPLOAD_REQUIRED':
        return '다시 등록 요청함';
      default:
        return '확인 전';
    }
  }

  bool okFor({required bool isId}) =>
      (isId ? idDecision : bankDecision) == 'REVIEWED_OK' &&
      !(isId ? idStale : bankStale);
}
