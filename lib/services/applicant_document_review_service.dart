import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../providers/user_provider.dart' show PermissionCheck;
import '../utils/global_loading_controller.dart';
import '../utils/toast_helper.dart';

/// [DOCUMENT-VERIFICATION-INTEGRITY-R1.2] 사업장의 지원자 서류 검토.
///
/// 상태 판정은 전부 서버가 한다. 이 클래스는 서버가 준 값을 나르기만 한다 —
/// 낡음(stale)을 화면이 다시 계산하면 두 곳이 서로 다른 답을 갖게 된다.
class ApplicantDocumentReviewService {
  static final ApplicantDocumentReviewService _default =
      ApplicantDocumentReviewService._();
  static ApplicantDocumentReviewService? _testOverride;

  /// 앱 전체가 쓰는 하나.
  static ApplicantDocumentReviewService get instance =>
      _testOverride ?? _default;

  /// [INVITE-PREACCEPT] 렌더 테스트가 서버 응답을 대신할 때만 쓴다.
  /// production 은 대입하지 않는다. null 이면 기본 인스턴스로 돌아간다.
  @visibleForTesting
  static set debugOverride(ApplicantDocumentReviewService? s) =>
      _testOverride = s;

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

  /// [CONSENT-PENDING-COPY] 화면에 보일 문장. 서버의 "동의하지 않았습니다"는 실제로는
  ///   **아직 동의 전**(documentAccessConsentGiven != true)이라 거절처럼 읽혔다.
  ///   서버 판정(srvApplicantReviewAccessBlock)에는 '거절' 상태가 없다 — 만료·검토 대상 아님·
  ///   옛 버전 동의는 서버가 다른 문장으로 보내고, 그 문장들은 그대로 보인다.
  static const String serverConsentMissingText = '근로자가 서류 접근에 동의하지 않았습니다.';
  String? get consentBlockLabel => consentBlock == serverConsentMissingText
      ? '근로자가 아직 서류 열람에 동의하지 않아 지금은 서류를 볼 수 없어요.'
      : consentBlock;

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

  /// [DOC-APP-CLOSEOUT.10] 응답에 신분증 등록 기록(`documents.hasIdCard`)이 실려 왔는가.
  ///   구 응답처럼 빠져 있으면 [hasIdCard] false 는 '미등록'이 아니라 '모름'이다.
  final bool idPresenceKnown;
  final bool hasBankbook;

  /// 자격이 있을 때만 채워진다. 없으면 null — 서버가 키 자체를 주지 않는다.
  final String? bankName;
  final String? accountNumber;
  final String? accountHolder;

  final List<String> openCorrectionTypes;

  // ── [PII-DOC-R1.5] 근무 확정 readiness ──────────────────────
  //
  //   위의 `ready`는 사람 검토 기반 판정이고 급여 경로가 아직 쓴다.
  //   확정 버튼이 실제로 따르는 것은 이 값이다 — 신분 확인만 본다.
  //   통장사본 상태는 확정을 막지 않는다. (PD-3)

  /// 근무 확정 가능 여부.
  final bool matchingReady;

  /// READY_AUTO | READY_MANUAL | ID_MISSING | ID_MISMATCH |
  /// ID_OCR_UNCERTAIN | ID_UNASSESSED
  final String matchingState;

  /// 확정이 막힌 사유. [matchingReady]면 null.
  final String? matchingReason;

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
    this.idPresenceKnown = true,
    required this.hasBankbook,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
    required this.openCorrectionTypes,
    required this.matchingReady,
    required this.matchingState,
    required this.matchingReason,
  });

  factory ApplicantDocumentReview.fromMap(Map<String, dynamic> m) {
    final v = Map<String, dynamic>.from((m['versions'] as Map?) ?? {});
    final r = Map<String, dynamic>.from((m['readiness'] as Map?) ?? {});
    final d = Map<String, dynamic>.from((m['documents'] as Map?) ?? {});
    final b = m['bank'] is Map ? Map<String, dynamic>.from(m['bank'] as Map) : null;
    final mr = Map<String, dynamic>.from((m['matchingReadiness'] as Map?) ?? {});
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
      idPresenceKnown: d['hasIdCard'] is bool,
      hasBankbook: d['hasBankbook'] == true,
      bankName: b?['bankName'] as String?,
      accountNumber: b?['accountNumber'] as String?,
      accountHolder: b?['accountHolder'] as String?,
      openCorrectionTypes: corr,
      matchingReady: mr['ready'] == true,
      matchingState: (mr['state'] as String?) ?? 'ID_UNASSESSED',
      matchingReason: mr['reason'] as String?,
    );
  }

  /// 자동 정합성으로 통과했는가 — 사람이 보지 않아도 되는 경우.
  bool get matchedAutomatically => matchingState == 'READY_AUTO';

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
        // [PII-DOC-R1.5] 사람이 아직 안 봤다고 해서 '확인 전'이 아니다 —
        //   시스템이 이미 대조했고 일치하면 그 사실을 말한다.
        //   '인증 완료'가 아니라 '정보 일치'다. 이건 진위 확인이 아니다.
        if (isId && matchedAutomatically) return '서류 정보 일치';
        return '확인 전';
    }
  }

  bool okFor({required bool isId}) =>
      (isId ? idDecision : bankDecision) == 'REVIEWED_OK' &&
      !(isId ? idStale : bankStale);

  /// [ADMIN-DOC-REVIEW-UX] 지원자 **상세 화면 안에서** 쓰는 확정 차단 안내.
  ///
  ///   서버의 [matchingReason] 은 목록·확정 거절용이라 "지원자 상세에서
  ///   확인해주세요"로 끝난다. 상세 안에서 그대로 보이면 자기 참조다.
  ///   판정은 그대로([matchingState]) 두고 **다음 행동**만 이 화면 기준으로
  ///   말한다 — 누가 확인할 수 있는지(권한·동의)까지 포함한다.
  /// [DOC-APP-CLOSEOUT.10] `ID_MISSING` 의 실제 사정 — 지원 상세와 초대 상세가 같이 쓴다.
  ///   [DOC-LATE-DELETE.7 · D] 신분증은 등록돼 있는데 서버가 사진 파일을 아직 확인하지 못했거나
  ///   없다고 확인한 경우도 같은 상태로 온다. 서버 사유(파일 확인 중 / 파일 없음)로 나눈다.
  ///   등록 기록이 응답에 없거나, 등록은 있는데 사유를 알아볼 수 없으면 UNKNOWN — 미등록·파일 없음으로
  ///   추정하지 않는다. 이 값은 등록 기록이지 파일이 있다는 보장이 아니다.
  IdMissingKind? get idMissingKind {
    if (matchingState != 'ID_MISSING') return null;
    if (!idPresenceKnown) return IdMissingKind.unknown;
    if (!hasIdCard) return IdMissingKind.unregistered;
    final why = matchingReason ?? '';
    if (why.contains('확인하고 있')) return IdMissingKind.checking;
    if (why.contains('찾을 수 없')) return IdMissingKind.fileMissing;
    return IdMissingKind.unknown;
  }

  String? get approvalBlockText {
    if (matchingReady) return null;
    final String lead;
    switch (matchingState) {
      case 'ID_MISSING':
        switch (idMissingKind!) {
          case IdMissingKind.checking:
            return '신분증 사진 파일을 확인하는 중이라 아직 확정할 수 없어요.\n잠시 후 다시 확인해 주세요.';
          case IdMissingKind.fileMissing:
            return '신분증 사진 파일을 찾을 수 없어 확정할 수 없어요.\n[다시 등록 요청]으로 근로자에게 새로 등록해 달라고 요청해 주세요.';
          case IdMissingKind.unknown:
            return '신분증 상태를 확인하지 못해 아직 확정할 수 없어요.\n잠시 후 다시 불러와 주세요.';
          case IdMissingKind.unregistered:
            // [DOC-DEV-ROLLOUT.9] 미등록 — 할 사람(지원자)과 다음 조건을 말한다. 기존 '다시 등록 요청'은
            //   사진 품질 사유(흐림·판독 불가…)라 등록된 사진을 전제한다 — 미등록에는 붙이지 않는다.
            return '지원자가 아직 신분증을 등록하지 않았어요.\n등록이 완료되면 다시 진행할 수 있어요.';
        }
      case 'ID_MISMATCH':
        lead = '등록된 신원정보와 신분증이 일치하지 않아요.';
      case 'ID_OCR_UNCERTAIN':
        lead = '신분증 정보를 자동으로 확인하지 못했어요.';
      default:
        lead = idStale
            ? '신분증이 바뀌어 다시 확인해야 확정할 수 있어요.'
            : '확정하려면 신분증 확인이 필요해요.';
    }
    final String how;
    if (!canReviewDocuments) {
      how = 'TO 관리와 급여 관리 권한이 모두 있는 관리자가 신분증을 확인하면 확정할 수 있어요.';
    } else if (consentBlock != null) {
      how = '근로자가 서류 열람에 동의하면 신분증을 확인할 수 있어요.';
    } else {
      how = '위 신분증을 보고 [확인 완료]를 누르면 확정할 수 있어요.';
    }
    return '$lead\n$how';
  }

  /// [E2-INVITE-NEXT-ACTION] **초대** 건의 다음 행동 안내.
  ///
  ///   [approvalBlockText] 는 직접 지원(관리자가 확정)의 문장이다. 초대에서는
  ///   관리자가 확정하지 않는다 — 신분증 확인 뒤 **근로자가 기한 안에 수락해야**
  ///   확정된다. 초대 상세가 "[확인 완료]를 누르면 확정할 수 있어요"라고 말하면
  ///   없는 버튼을 약속한다.
  ///
  ///   네 단계를 나눈다: 기한 종료 · 동의 전 · 확인 대기 · 확인 완료.
  ///   [expired] 는 호출자가 서버 마감(`effectiveInviteDeadline`)으로 정한다.
  ///   [deadlineLabel] 은 KST 로 포맷한 마감 — 모르면 null(지어내지 않는다).
  String inviteNextActionText({
    required bool expired,
    String? deadlineLabel,
  }) {
    if (expired) {
      return '초대 수락 기한이 지났어요.\n근로자가 더 이상 수락할 수 없어요.';
    }
    final until = deadlineLabel == null ? '기한 안에' : '$deadlineLabel까지';
    if (matchingReady) {
      return '신분증 확인이 끝났어요.\n근로자가 $until 수락하면 확정돼요.';
    }
    // [DOC-APP-CLOSEOUT.10] 지원 상세와 같은 분류. 이 화면을 보는 사람은 관리자이고, 수락은 근로자가 한다.
    //   [다시 등록 요청]은 그 버튼이 이 화면에 보일 때(검토 권한·동의·등록 기록)만 말한다.
    switch (idMissingKind) {
      case IdMissingKind.unregistered:
        return '근로자가 아직 신분증을 등록하지 않았어요.\n근로자가 신분증을 등록하면 수락할 수 있어요.';
      case IdMissingKind.checking:
        return '신분증 사진 파일을 확인하는 중이라 아직 수락할 수 없어요.\n잠시 후 다시 확인해 주세요.';
      case IdMissingKind.fileMissing:
        return canReviewDocuments && consentBlock == null
            ? '신분증 사진 파일을 찾을 수 없어 근로자가 수락할 수 없어요.\n[다시 등록 요청]으로 근로자에게 새로 등록해 달라고 요청해 주세요.'
            : '신분증 사진 파일을 찾을 수 없어 근로자가 수락할 수 없어요.\n근로자가 신분증을 다시 등록하면 수락할 수 있어요.';
      case IdMissingKind.unknown:
        return '신분증 상태를 확인하지 못했어요.\n잠시 후 다시 불러와 주세요.';
      case null:
        break;
    }
    if (consentBlock != null) {
      return '근로자가 서류 열람에 동의하면 신분증을 확인할 수 있어요.\n'
          '확인이 끝나면 근로자가 $until 수락할 수 있어요.';
    }
    final String lead;
    switch (matchingState) {
      case 'ID_MISMATCH':
        lead = '등록된 신원정보와 신분증이 일치하지 않아요.';
      case 'ID_OCR_UNCERTAIN':
        lead = '신분증 정보를 자동으로 확인하지 못했어요.';
      default:
        lead = idStale
            ? '신분증이 바뀌어 다시 확인해야 해요.'
            : '근로자가 수락하려면 신분증 확인이 필요해요.';
    }
    final how = canReviewDocuments
        ? '위 신분증을 보고 [확인 완료]를 누르면 근로자가 $until 수락할 수 있어요.'
        : 'TO 관리와 급여 관리 권한이 모두 있는 관리자가 신분증을 확인하면 '
            '근로자가 $until 수락할 수 있어요.';
    return '$lead\n$how';
  }
}

/// [ADMIN-DOC-REVIEW-UX] 상세 하단 `승인` 버튼이 따르는 상태.
///
///   서버 `callableConfirmApplication` 은 신분 확인([ApplicantDocumentReview.
///   matchingReady])을 본다. 화면은 그 값을 **알 때만** 승인을 연다.
///     checking — 아직 조회 중
///     unknown  — 조회 실패(모름). 승인 가능으로도, 불가로도 단정하지 않는다
///     blocked  — 서버가 확정을 막는다
///     ready    — 서버가 확정을 허용한다(정원·마감은 서버가 확정 시 다시 본다)
///     denied   — 확정 권한(canManageTo)이 **확인된 거부**다
///
///   [ADMIN-APPROVAL-PERMISSION] 근무 이력·리뷰 같은 부가 조회는 서버 확정
///   조건이 아니다 — 이 판정의 입력이 아니다. 입력은 셋뿐이다:
///   확정 권한, 서류 조회 상태, 서버가 준 신분 확인(matchingReady).
enum ApprovalGate { checking, unknown, blocked, denied, ready }

ApprovalGate approvalGateOf({
  required bool loading,
  required bool failed,
  required ApplicantDocumentReview? review,
  PermissionCheck permission = PermissionCheck.allowed,
}) {
  // 권한이 먼저다 — 거부면 서류 상태와 무관하게 확정할 수 없다.
  switch (permission) {
    case PermissionCheck.denied:
      return ApprovalGate.denied;
    case PermissionCheck.unknown:
      return ApprovalGate.checking;
    case PermissionCheck.error:
      return ApprovalGate.unknown;
    case PermissionCheck.allowed:
      break;
  }
  if (loading) return ApprovalGate.checking;
  if (review == null) {
    return failed ? ApprovalGate.unknown : ApprovalGate.checking;
  }
  return review.matchingReady ? ApprovalGate.ready : ApprovalGate.blocked;
}

/// [DOC-APP-CLOSEOUT.10] 확정을 막는 `ID_MISSING` 의 사정.
///   unregistered = 등록 기록 없음 · checking = 등록됨, 서버가 파일 확인 중 ·
///   fileMissing = 등록됨, 서버가 파일 없음 확인 · unknown = 응답에 근거가 없거나 알아볼 수 없음.
enum IdMissingKind { unregistered, checking, fileMissing, unknown }
