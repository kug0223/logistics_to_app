import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

/// [PII-B4-R1] 세무 identity 육안 확인 상태.
///
///   관리자가 신분증 원본을 보는 이유는 하나다 — 소득신고에 쓸 등록
///   성명·생년월일이 지금 제출된 신분증과 맞는지 대조하는 것.
///
///   이것은 정부기관의 진위 인증이 아니다. 사람이 두 값을 비교했다는
///   기록이므로 "인증 완료"라고 부르지 않는다.
enum TaxReviewState {
  /// 아직 이 사업장이 확인한 적 없음.
  unreviewed,

  /// 현재 신분증·현재 등록정보 기준 확인 완료.
  reviewedOk,

  /// 불일치 — 근로자에게 재등록을 요청한 상태.
  reuploadRequired,

  /// 확인 이후 신분증이나 등록정보가 바뀜.
  stale,
}

TaxReviewState _stateOf(String? wire) => switch (wire) {
      'REVIEWED_OK' => TaxReviewState.reviewedOk,
      'REUPLOAD_REQUIRED' => TaxReviewState.reuploadRequired,
      'STALE' => TaxReviewState.stale,
      _ => TaxReviewState.unreviewed,
    };

extension TaxReviewStateLabel on TaxReviewState {
  /// 관리자에게 보여줄 상태 문구.
  ///
  ///   "인증 완료" 계열 표현은 쓰지 않는다 — 확인한 것은 사람이고,
  ///   확인한 것은 진위가 아니라 두 값의 일치다.
  String get label => switch (this) {
        TaxReviewState.reviewedOk => '확인 완료',
        TaxReviewState.unreviewed => '확인 필요',
        TaxReviewState.stale => '재확인 필요',
        TaxReviewState.reuploadRequired => '정보 수정 필요',
      };

  String get description => switch (this) {
        TaxReviewState.reviewedOk =>
          '등록 정보와 신분증 정보가 일치하는 것을 확인했습니다',
        TaxReviewState.unreviewed =>
          '소득신고에 쓸 등록 정보가 신분증과 맞는지 확인해주세요',
        TaxReviewState.stale =>
          '신분증 또는 등록 정보가 변경되어 다시 확인해야 합니다',
        TaxReviewState.reuploadRequired =>
          '근로자에게 정보 수정을 요청한 상태입니다',
      };

  /// 확인 화면을 열 수 있는가.
  bool get needsReview => this != TaxReviewState.reviewedOk;
}

/// 한 사업장이 한 근로자에 대해 가진 세무 identity 확인 사실.
class TaxIdentityReview {
  const TaxIdentityReview({
    required this.state,
    required this.valid,
    required this.idDocumentVersion,
    required this.taxIdentityFingerprint,
    required this.hasIdDocument,
    this.reviewedAt,
    this.officialName,
    this.koreanName,
    this.birthDate,
  });

  final TaxReviewState state;
  final bool valid;

  /// 지금 화면이 보고 있는 신분증 문서 버전. 제출 시 그대로 돌려보낸다.
  final int idDocumentVersion;

  /// 지금 화면이 보고 있는 등록 정보의 지문. 제출 시 그대로 돌려보낸다.
  final String taxIdentityFingerprint;

  final bool hasIdDocument;
  final DateTime? reviewedAt;

  /// 신분증과 대조할 등록 정보.
  final String? officialName;
  final String? koreanName;
  final DateTime? birthDate;

  static TaxIdentityReview fromMap(Map<String, dynamic> m) {
    final ms = m['reviewedAtMs'];
    final b = m['birthDateMs'];
    return TaxIdentityReview(
      state: _stateOf(m['state'] as String?),
      valid: m['valid'] == true,
      idDocumentVersion: (m['idDocumentVersion'] as num?)?.toInt() ?? 0,
      taxIdentityFingerprint: (m['taxIdentityFingerprint'] ?? '') as String,
      hasIdDocument: m['hasIdDocument'] == true,
      reviewedAt: ms is num
          ? DateTime.fromMillisecondsSinceEpoch(ms.toInt())
          : null,
      officialName: m['officialName'] as String?,
      koreanName: m['koreanName'] as String?,
      birthDate:
          b is num ? DateTime.fromMillisecondsSinceEpoch(b.toInt()) : null,
    );
  }
}

class TaxIdentityReviewService {
  TaxIdentityReviewService._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 이 사업장의 확인 사실을 읽는다. 원본 이미지는 오지 않는다.
  static Future<TaxIdentityReview?> load({
    required String businessId,
    required String targetUid,
  }) async {
    try {
      final res = await _fn
          .httpsCallable('callableGetTaxIdentityReview')
          .call<Map<String, dynamic>>({
        'businessId': businessId,
        'targetUid': targetUid,
      });
      return TaxIdentityReview.fromMap(Map<String, dynamic>.from(res.data));
    } catch (e) {
      debugPrint('❌ 세무 identity 확인 상태 조회 실패: $e');
      return null;
    }
  }

  /// [§22] 관리자가 확인을 **누른 순간에만** 원본을 연다.
  static Future<String> idCardUrl({
    required String businessId,
    required String targetUid,
    required int expectedIdDocumentVersion,
  }) async {
    final res = await _fn
        .httpsCallable('callableGetTaxIdentityIdCardUrl')
        .call<Map<String, dynamic>>({
      'businessId': businessId,
      'targetUid': targetUid,
      'expectedIdDocumentVersion': expectedIdDocumentVersion,
    });
    return (res.data['signedUrl'] ?? '') as String;
  }

  /// 확인 결과를 현재 값에 묶어 기록한다.
  ///
  /// [decision] 'REVIEWED_OK' | 'REUPLOAD_REQUIRED'
  static Future<({bool correctionOpened})> submit({
    required String businessId,
    required String targetUid,
    required String decision,
    required int expectedIdDocumentVersion,
    required String expectedTaxIdentityFingerprint,
    String? note,
  }) async {
    final res = await _fn
        .httpsCallable('callableReviewTaxIdentity')
        .call<Map<String, dynamic>>({
      'businessId': businessId,
      'targetUid': targetUid,
      'decision': decision,
      'expectedIdDocumentVersion': expectedIdDocumentVersion,
      'expectedTaxIdentityFingerprint': expectedTaxIdentityFingerprint,
      if (note != null) 'note': note,
    });
    return (correctionOpened: res.data['correctionOpened'] == true);
  }
}
