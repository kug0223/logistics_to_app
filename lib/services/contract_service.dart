import 'dart:convert';
import 'dart:math' show Random;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/core/application_model.dart';
import '../models/core/business_model.dart';
import '../models/core/to_model.dart';
import '../models/core/contract_template_model.dart';
import '../models/core/employment_contract_model.dart';
import '../models/core/user_model.dart';
import '../utils/work_detail_helper.dart';
import '../models/core/work_detail_data.dart';
import '../utils/format_helper.dart';
import 'firestore_service.dart';

/// [R8P6-SIG-CUTOVER] 서명 이미지 1건의 **그때의** 열람 링크.
///
///   `url` 은 15분 뒤 만료되므로 **저장하지 않는다**. `version` 은 그 반대로
///   서명 파일이 바뀌지 않는 한 그대로여서, 이미지 캐시 키의 근거가 된다
///   (URL 을 키로 쓰면 15분마다 같은 서명을 다시 내려받는다).
class ContractSignatureLink {
  final String url;
  final String version;

  const ContractSignatureLink({required this.url, required this.version});
}

/// 서명 링크를 받아 오는 방법 — 렌더 테스트가 서버 없이 돌 수 있게 분리했다.
typedef ContractSignatureResolver = Future<ContractSignatureLink> Function(
  String contractId,
  String role,
);

/// [REISSUE-RECOVERY] 계약 상태 일괄 조회 결과 — **모름과 없음을 나눠** 돌려준다.
///
///   `statuses` 는 조회에 성공한 지원서만 담는다(계약이 없으면 값이 null).
///   `unresolved` 는 그 청크 조회가 실패해 **아직 모르는** 지원서다.
///   소비자는 `isMissingContract` 로만 "계약서 없음"을 판정해야 한다 —
///   `statuses[id] == null` 하나만 보면 조회 실패가 미작성으로 섞인다.
class ContractStatusBatch {
  final Map<String, String?> statuses;
  final Set<String> unresolved;

  const ContractStatusBatch({
    this.statuses = const {},
    this.unresolved = const {},
  });

  /// 계약서가 **없다고 확인된** 경우만 true. 조회 실패는 false.
  bool isMissingContract(String applicationId) {
    if (unresolved.contains(applicationId)) return false;
    final s = statuses[applicationId];
    return s == null || s.isEmpty || s == 'voided';
  }

  bool isUnresolved(String applicationId) => unresolved.contains(applicationId);

  /// 발송 직후 낙관적 반영 — 그 건은 더 이상 `unresolved` 가 아니다.
  ContractStatusBatch withStatus(String applicationId, String status) =>
      ContractStatusBatch(
        statuses: {...statuses, applicationId: status},
        unresolved: unresolved.where((id) => id != applicationId).toSet(),
      );
}

/// [BULK-DISPATCH-RECONCILE] 지원서 하나에 **발송된 계약이 있는가**의 세 가지 답.
///
///   `none` 과 `unknown` 을 같은 값으로 돌려주는 API 로는 롤백을 판단할 수 없다.
///   조회가 실패한 것을 "계약 0건"으로 읽으면, 계약이 살아 있는데 지원서를
///   PENDING 으로 되돌리게 된다 — 근로자가 PENDING 지원서의 계약서에 서명한다.
///   그래서 `getByApplication`(실패를 null 로 삼킨다)을 쓰지 않고 따로 둔다.
enum ContractLedgerProbe {
  /// 근로자에게 전달된 계약이 **있다** (pending_worker·completed·active…).
  issued,

  /// 조회는 됐고, 전달된 계약이 **없다** (문서 없음 또는 voided/draft/pending_employer).
  notIssued,

  /// **확인하지 못했다.** 0건이 아니다.
  unknown,
}

/// [E2-EMPLOYER-SIG-LOST-RESPONSE] 사업주 서명 callable 호출 경계 — 테스트에서 교체한다.
typedef EmployerSignatureCall = Future<Object?> Function(Map<String, dynamic> data);

/// [E2-EMPLOYER-SIG-LOST-RESPONSE] 계약 문서 단건 원본 읽기 경계(없으면 null).
///   production 은 [ContractService.getById] 와 같은 `employment_contracts/{id}` get 이다.
typedef ContractDocReader = Future<Map<String, dynamic>?> Function(String contractId);

/// 서버가 끝까지 처리했는지 **알 수 없는** callable 오류 코드.
///   work_applicants_dialog `_indeterminateCfCodes` 와 같은 집합 + 'unknown'.
const Set<String> kEmployerSignatureIndeterminateCodes = {
  'deadline-exceeded',
  'unavailable',
  'internal',
  'cancelled',
  'aborted',
  'unknown',
};

/// [E2-EMPLOYER-SIG-LOST-RESPONSE · E2-WORKER-SIG-LOST-RESPONSE] 서명 callable 응답을 못 받았고,
///   원장으로도 커밋을 **증명하지 못했다.** (사업주·근로자 서명 공통)
///
///   실패가 아니다 — 서버가 아직 처리 중이거나, 처리했는데 읽지 못했을 수 있다.
///   원래 오류의 `code` 를 그대로 들고 다닌다. 일괄 발송 경로는 code 로
///   "불명확"을 판정하므로(확정을 되돌리지 않는다) 그 동작이 바뀌지 않는다.
class SignatureOutcomeUnknown extends FirebaseFunctionsException {
  SignatureOutcomeUnknown({required super.code, required this.reason})
      : super(
          message: '서명 저장 결과를 확인하지 못했습니다. '
              '계약서 목록에서 상태를 확인한 뒤 다시 시도해 주세요.',
          details: {'reason': reason},
        );

  /// `absent`(문서 없음·아직 미서명) · `mismatch`(다른 지원서·사업장·근로자·서명) · `readFailed`.
  final String reason;
}

class ContractService {
  final _db = FirebaseFirestore.instance;
  final _firestoreService = FirestoreService();

  /// 서명 이미지 바이트를 받을 때만 쓴다 — 테스트에서 교체할 수 있게 주입받는다.
  final http.Client _http;

  final EmployerSignatureCall? _employerSignatureCall;
  final EmployerSignatureCall? _workerSignatureCall;
  final ContractDocReader? _contractDocReader;
  final Duration _employerSignatureRecheckDelay;

  ContractService({
    http.Client? httpClient,
    EmployerSignatureCall? employerSignatureCall,
    EmployerSignatureCall? workerSignatureCall,
    ContractDocReader? contractDocReader,
    Duration employerSignatureRecheckDelay = const Duration(seconds: 2),
  })  : _http = httpClient ?? http.Client(),
        _employerSignatureCall = employerSignatureCall,
        _workerSignatureCall = workerSignatureCall,
        _contractDocReader = contractDocReader,
        _employerSignatureRecheckDelay = employerSignatureRecheckDelay;

  // ── 핵심: 번들링 생성/추가 ─────────────────────────────────────

  /// 확정 시 호출. 동일 (toId + workDetailId + workerId) 계약서가 있으면
  /// 슬롯 추가, 없으면 새 계약서 생성.
  /// 장기 근무는 기존처럼 단일 계약서 생성.
  ///
  /// [C01 동시성 설계]
  /// 두 관리자가 동시에 같은 근무자에게 계약서를 생성하는 경우:
  /// - 단기: _findBundle이 둘 다 null을 반환 → _createNew가 둘 다 isNewUnsaved:true 객체 반환.
  ///   이후 saveEmployerSignature에서 각자 다른 doc ref로 트랜잭션 set을 실행하므로
  ///   중복 계약서 2개가 생성될 수 있다 (TOCTOU).
  ///   방어책: saveEmployerSignature 진입 전 applicationId 기준으로 재조회하여 이미 존재하면
  ///   기존 계약에 슬롯 추가로 전환. 이 재조회-생성 사이도 race 가능하나, 실제로
  ///   두 관리자가 밀리초 단위로 동일 지원서에 계약서를 생성하는 빈도는 매우 낮으므로
  ///   last-write-wins 허용(의도된 설계). 중복 발생 시 UI에서 경고 표시.
  ///
  /// - 장기: 계약서가 근무자당 1개여야 하는 동일 문제. 마찬가지로 빈도 낮아 허용.
  ///
  /// 완전한 방어를 위해서는 Cloud Functions에서 트랜잭션으로 처리해야 하나,
  /// 현재 클라이언트 단계에서는 위 설계 수준으로 충분하다고 판단.
  Future<EmploymentContractModel> findOrCreateContract({
    required ApplicationModel application,
    required BusinessModel business,
    required UserModel worker,
    required WorkDetailData workDetail,
    List<ContractArticle> articles = const [],
    String? templateId,
  }) async {
    workDetail = _withPromisedWage(application, workDetail);
    final isLong = application.isLongTermApplication;
    final toId = application.toId ?? '';
    final workDetailId = application.workDetailId ?? workDetail.id;

    if (!isLong) {
      // 단기: 기존 번들 계약서 탐색 (articles는 최초 생성 시에만 적용)
      final existing = await _findBundle(
        toId: toId,
        workDetailId: workDetailId,
        workerId: worker.uid,
        businessId: business.id,
      );
      // [K-001] pendingEmployer 상태에서만 슬롯 추가 허용
      // — pendingWorker 이상(사업주 서명 완료)은 슬롯 추가 불가: 서명 무결성 보호
      if (existing != null &&
          existing.status == ContractStatus.pendingEmployer) {
        return _addSlot(existing, application, workDetail);
      }
    }

    // 신규 생성 (장기 또는 첫 번째 단기 슬롯)
    return _createNew(
      application: application,
      business: business,
      worker: worker,
      workDetail: workDetail,
      toId: toId,
      workDetailId: workDetailId,
      articles: articles,
      templateId: templateId,
    );
  }

  /// 미리보기 전용 계약서 생성 — 번들 탐색 없이 항상 isNewUnsaved:true 반환.
  /// Firestore에 저장되지 않으므로 미리보기 후 버려도 안전하다.
  Future<EmploymentContractModel> buildPreviewContract({
    required ApplicationModel application,
    required BusinessModel business,
    required UserModel worker,
    required WorkDetailData workDetail,
    List<ContractArticle> articles = const [],
  }) async {
    workDetail = _withPromisedWage(application, workDetail);
    return _createNew(
      application: application,
      business: business,
      worker: worker,
      workDetail: workDetail,
      toId: application.toId ?? '',
      workDetailId: application.workDetailId ?? workDetail.id,
      articles: articles,
    );
  }

  /// [POSTING-V2-03I.1] 계약서 임금은 **그 사람에게 약속한 임금**이다.
  ///
  /// 공고의 현재 모집 임금이 아니다. 두 값은 정상적으로 다를 수 있다 —
  /// 관리자가 모집 임금을 올리면 그 뒤 지원하는 사람에게만 적용되고,
  /// 이미 지원·확정한 사람의 약속은 그대로다. 근태·급여는 이미 그렇게
  /// 동작한다(attendance.snapshotWage ← application.wage).
  ///
  /// 계약서만 예외였다. 진입점에 따라 현재 슬롯 임금을 쓰거나
  /// (`TOItem.workDetails`) 갱신되지 않는 마스터 TO 템플릿을 썼고
  /// (`to.workDetails`), 둘 다 실제 지급액과 어긋날 수 있었다.
  /// 같은 지원서면 어디서 만들어도 같은 임금이어야 한다.
  ///
  /// 업무명·시간 등 나머지 정보는 현재 workDetail을 그대로 쓴다 —
  /// 바꾸는 것은 임금 두 필드뿐이다.
  ///
  /// [application]에 약속 임금이 없으면(레거시 결측) **예외를 던진다.**
  /// 현재 모집 임금으로 과거 약속을 조용히 덮어쓰지 않는다.
  /// [POSTING-V2-03I.3] 금액만이 아니라 **급여 산정 조건 전체**를 약속 버전으로
  /// 맞춘다. 같은 100,000원이라도 휴게시간·야간수당·연장 단가가 다르면
  /// 실제로 받는 돈이 달라지므로, 금액만 덮으면 계약서가 반쪽만 약속 버전인
  /// mixed-version 문서가 된다.
  ///
  /// 스냅샷이 없는 레거시 지원서는 금액만 맞춘다 — 그 이상은 복원할 근거가 없다.
  /// [GAP-2] 그 **날짜의 약속 시간** — 계약 슬롯이 쓸 유일한 출처.
  ///
  ///   예전에는 `workDetail.startTime/endTime` 을 썼다. 그 `workDetail` 은
  ///   `_getWorkForApp()` 이 **마스터 TO 의 workDetails** 에서 찾은 값이다.
  ///   그런데 슬롯(날짜)은 자기 `workDetails` 를 갖고
  ///   `callableUpdateSlotWorkDetails` 가 **날짜 하나만** 바꿀 수 있다 —
  ///   날짜마다 시간이 갈라지면 계약서에 그 날의 실제 시간이 아닌 값이 적힌다.
  ///
  ///   지원서는 그 날짜의 약속을 보존한다(`[DESIGN-SLOT-S4]`: 슬롯 시간을
  ///   바꿔도 기존 지원서는 소급 변경하지 않는다). 서버도 composite
  ///   `workDetailId`(`workType_startTime_endTime`)를 **슬롯의 workDetails 와
  ///   exact match** 시킨 뒤에야 지원을 받는다.
  ///
  ///   값이 비어 있으면 **마스터 값으로 조용히 대체하지 않는다.** 그렇게 하면
  ///   "확인되지 않은 시간"이 정상 계약처럼 보인다 — 임금과 같은 규칙이다.
  ({String start, String end}) _promisedTimes(ApplicationModel application) {
    final start = application.startTime.trim();
    final end = application.endTime.trim();
    if (start.isEmpty || end.isEmpty) {
      throw StateError(
        '지원 시점 근무시간 정보가 없어 계약서를 만들 수 없습니다. '
        '(applicationId: ${application.id})',
      );
    }
    return (start: start, end: end);
  }

  WorkDetailData _withPromisedWage(
    ApplicationModel application,
    WorkDetailData workDetail,
  ) {
    final promisedWage = application.wage;
    if (promisedWage <= 0) {
      throw StateError(
        '지원 시점 임금 정보가 없어 계약서를 만들 수 없습니다. '
        '(applicationId: ${application.id})',
      );
    }
    final promisedType = application.wageType;
    if (!application.hasCompensationSnapshot) {
      // [POSTING-V2-03I.4] legacy compatibility — 지원서가 아는 것까지만
      //   맞춘다: 금액과 급여유형. 휴게·야간·연장 단가·공제는 지원 시점
      //   값을 알 수 없으므로 현재 정의를 그대로 둔다 —
      //   현재 값을 과거 약속이라고 표시하지 않는다.
      //   그 조건들은 활성 레거시가 있는 동안 서버가 변경을 막는다.
      return workDetail.copyWith(
        wage: promisedWage,
        wageType: promisedType ?? workDetail.wageType,
      );
    }
    // 지급일 설정(paySchedule*)은 임금 조건이 아니라 별도 변경 flow를 가지므로
    // 현재 값을 그대로 둔다. 업무명·아이콘 등 표시 정보도 마찬가지다.
    return workDetail.copyWith(
      wage: promisedWage,
      wageType: promisedType ?? workDetail.wageType,
      baseHourlyWage: application.baseHourlyWage,
      // [R5.3C.1] 약속이 AUTO면 공고의 수동값이 계약서로 흘러들지 않게 지운다.
      //   clearBaseHourlyWage는 copyWith에서 mode도 AUTO로 맞춘다.
      clearBaseHourlyWage: application.baseHourlyWage == null,
      baseHourlyWageMode: WorkDetailHelper.baseHourlyWageModeOf(application),
      breakMinutes: application.breakMinutes,
      nightAllowanceApplied: application.nightAllowanceApplied,
      nightIncluded: application.nightIncluded,
      taxDeductionType: application.taxDeductionType,
      // 근무시간은 임금 조건이 아니다 — 현재 정의를 따른다.
      // 활성 지원자가 있는 동안의 시간 변경은 03G identity guard가 막는다.
    );
  }

  // ── 서명 저장 ────────────────────────────────────────────────

  /// 사업주 서명 → 근무자 서명 대기로 전환
  /// [SEC-EMPLOYER-SIG] callableFinalizeEmployerSignature CF 경유:
  ///   Storage Admin SDK 업로드 + 소속 검증 서버 강제.
  ///   storage.rules signature_employer.png → if false (클라이언트 직접 업로드 차단).
  ///
  /// [CONTRACT-DISPATCH-B1] [signatureBytes] 가 null 이면 **사업장 owner 의 등록 날인**을
  ///   서버가 찾아 찍는다(P4.4C-SIGNER-01). 앱은 owner 문서를 읽을 수 없다 — 사업장 목록은
  ///   ownerId 를 지우고(SEC-20) users 문서는 본인만 읽는다. 그래서 발송 화면은 바이트를
  ///   보내지 않는다. 바이트를 보내도 owner 본인일 때만 그 바이트가 쓰인다(서버 판정).
  Future<EmploymentContractModel> saveEmployerSignature({
    required EmploymentContractModel contract,
    Uint8List? signatureBytes,
  }) async {
    // 클라이언트 사전 가드 (UX용) — CF에서 재검증
    if (contract.status == ContractStatus.voided) {
      throw Exception('무효 처리된 계약서에는 서명할 수 없습니다');
    }
    if (contract.status == ContractStatus.completed) {
      throw Exception('이미 완료된 계약서입니다');
    }
    if (contract.employerSignatureUrl != null && contract.employerSignatureUrl!.isNotEmpty) {
      throw Exception('이미 사업주 서명이 완료된 계약서입니다');
    }

    // 응답 유실 때 "이 시도가 커밋됐는가"를 확인할 표식 — 서버가 계약 문서에 그대로 남긴다.
    final signRequestId =
        '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(1 << 32)}';
    final Map<String, dynamic> cfData = {
      'contractId': contract.id,
      if (signatureBytes != null) 'signatureBase64': base64Encode(signatureBytes),
      'signRequestId': signRequestId,
    };

    if (contract.isNewUnsaved) {
      // 신규 계약서: 계약서 데이터를 CF에 전달 (타임스탬프·서명 필드는 CF가 서버 강제)
      final contractMap = contract.toMap();
      for (final key in ['employerSignatureUrl', 'employerSignatureHash',
          'employerSignedAt', 'createdAt', 'updatedAt']) {
        contractMap.remove(key);
      }
      cfData['isNewUnsaved'] = true;
      cfData['contractData'] = contractMap;
    }

    Object? responseData;
    final injectedCall = _employerSignatureCall;
    try {
      responseData = injectedCall != null
          ? await injectedCall(cfData)
          : (await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                  .httpsCallable('callableFinalizeEmployerSignature',
                      options: HttpsCallableOptions(timeout: const Duration(seconds: 30)))
                  .call(cfData))
              .data;
    } on FirebaseFunctionsException catch (e) {
      // [E2-EMPLOYER-SIG-LOST-RESPONSE] 명확한 거절(권한·검증·중복 등)은 그대로 실패다.
      if (!kEmployerSignatureIndeterminateCodes.contains(e.code)) rethrow;
      // 응답을 못 받았다 — 서버가 커밋했는지 원장으로 확인한다.
      //   성공으로 바꾸는 것은 **이 계약 문서에 이 지원서·사업장·근로자로, 이번에 보낸
      //   서명 바이트(sha256)가 저장된 것이 보일 때**뿐이다. 그 밖에는 원래 code 를
      //   유지한 "불명확" 으로 던진다 — 다시 보내지 않는다(서버도 중복 생성을 막는다).
      final verdict = await _confirmEmployerSignatureCommitted(
          contract, signatureBytes, signRequestId);
      if (verdict != 'committed') {
        debugPrint('⚠️ [contract] 사업주 서명 응답 유실 — 커밋 확인 안 됨 '
            '(${contract.id}, ${e.code}, $verdict)');
        throw SignatureOutcomeUnknown(code: e.code, reason: verdict);
      }
      debugPrint('ℹ️ [contract] 사업주 서명 응답 유실 — 원장에서 커밋 확인 (${contract.id}, ${e.code})');
      responseData = null;
    }

    // [BULK-DISPATCH-RECONCILE] 응답 모양을 캐스트로 단정하지 않는다.
    //   `as Map` 은 응답이 Map 이 아니면 **커밋 뒤에** TypeError 를 던진다.
    final cfMap = responseData is Map ? responseData : null;
    // [R8P6-STAGE-B] 서명이 **저장됐다**는 증거는 경로다 — URL 이 아니다.
    //
    //   예전에는 `employerSignatureUrl` 이 비면 예외를 던졌다. 단계 C 에서
    //   CF 가 URL 발급을 멈추는 순간 그 줄이 **사업주 서명을 막는다**.
    //   근로자 서명 경로는 이미 `pdfStoragePath` 를 보도록 고쳐져 있었다 —
    //   여기만 비대칭으로 남아 있었다.
    final sigPath = cfMap?['employerSignatureStoragePath'] as String? ?? '';
    final url = cfMap?['employerSignatureUrl'] as String? ?? '';
    if (sigPath.isEmpty && url.isEmpty) {
      // [BULK-DISPATCH-RECONCILE] 여기서 던지면 **커밋된 뒤의 실패**가 된다.
      //
      //   CF 가 정상 반환했다는 것은 트랜잭션이 커밋됐다는 뜻이다 — 커밋
      //   이후로 그 CF 는 던지지 않는다(알림 실패는 CF 안에서 삼킨다).
      //   응답을 읽지 못한 것은 **저장되지 않았다는 증거가 아니다.**
      //   예전에는 예외를 던졌고, 일괄 발송 루프가 그 예외를 보고 확정을
      //   PENDING 으로 되돌렸다 — 계약서는 살아 있는데 지원서만 돌아갔다.
      //   그래서 실패로 바꾸지 않고, 눈에 보이게 기록만 남긴다.
      debugPrint('⚠️ [contract] 사업주 서명 응답에 경로·URL 이 둘 다 없다 '
          '— 서버 커밋은 된 것으로 본다 (${contract.id})');
    }
    final now = DateTime.now();
    final updated = contract.copyWith(
      status: ContractStatus.pendingWorker,
      // 단계 A 에서는 둘 다 온다. 단계 C 에서는 경로만 온다.
      employerSignatureUrl: url.isNotEmpty ? url : null,
      employerSignatureAvailable: true,
      employerSignedAt: now,
      updatedAt: now,
    );

    // [FCM-FIX 2026-08-10] 클라이언트 알림 발송 제거 — callableFinalizeEmployerSignature CF 내부로 이전
    // CF가 계약서 저장 직후 notifications 문서를 직접 write하므로 원자성 보장됨
    // (이전 클라이언트 createNotification 호출은 CF 반환 후 크래시 시 영구 누락 위험이 있었음)

    return updated;
  }

  /// [E2-EMPLOYER-SIG-LOST-RESPONSE] 사업주 서명이 **이 시도로** 커밋됐는가.
  ///
  ///   읽는 것은 `employment_contracts/{contract.id}` 단건 get 하나다(이미 허용된 경로 —
  ///   rules 의 get 은 사업장 관리자·계약 권한 하위관리자, CF 호출 권한과 같은 범위).
  ///   CF(00066)는 커밋 때 `employerSignatureHash = sha256(서명 바이트)` 를 함께 쓴다.
  ///   그 값이 이번에 보낸 바이트의 해시와 같아야 "이번 서명"이다 — 다른 관리자의
  ///   서명이나 다른 계약을 성공으로 읽지 않는다.
  ///
  ///   반환: `committed` · `absent`(문서 없음·아직 미서명 — 진행 중일 수 있음) ·
  ///   `mismatch`(다른 지원서·사업장·근로자·서명) · `readFailed`.
  ///   `absent` 이면 한 번만 더 읽는다(제한된 재조회).
  Future<String> _confirmEmployerSignatureCommitted(
    EmploymentContractModel contract,
    Uint8List? signatureBytes,
    String signRequestId,
  ) async {
    // [CONTRACT-DISPATCH-B1] 서버가 owner 날인을 찍으면 앱은 그 해시를 모른다 —
    //   이번 요청 id 가 저장된 것으로 증명한다. 보낸 바이트 해시가 같아도 이번 시도다.
    final expectedHash =
        signatureBytes == null ? null : sha256.convert(signatureBytes).toString();
    final reader = _contractDocReader ??
        (String id) async =>
            (await _db.collection('employment_contracts').doc(id).get()).data();
    String verdictOf(Map<String, dynamic>? d) {
      if (d == null) return 'absent';
      final appIds = (d['applicationIds'] as List?)?.whereType<String>().toSet() ?? const <String>{};
      final sameApp = contract.applicationId.isNotEmpty &&
          (d['applicationId'] == contract.applicationId || appIds.contains(contract.applicationId));
      if (!sameApp ||
          d['businessId'] != contract.businessId ||
          d['workerId'] != contract.workerId) {
        return 'mismatch';
      }
      final status = d['status'];
      final signed = d['employerSignedAt'] != null &&
          (status == 'pending_worker' || status == 'completed');
      if (!signed) return 'absent';
      final sameRequest = d['employerSignRequestId'] == signRequestId;
      final sameBytes = expectedHash != null && d['employerSignatureHash'] == expectedHash;
      return (sameRequest || sameBytes) ? 'committed' : 'mismatch';
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future<void>.delayed(_employerSignatureRecheckDelay);
      Map<String, dynamic>? doc;
      try {
        doc = await reader(contract.id);
      } catch (e) {
        debugPrint('⚠️ [contract] 사업주 서명 커밋 확인 읽기 실패 (${contract.id}): $e');
        return 'readFailed';
      }
      final v = verdictOf(doc);
      if (v != 'absent') return v;
    }
    return 'absent';
  }

  /// 근무자 서명 → 완료 상태로 전환
  Future<EmploymentContractModel> saveWorkerSignature({
    required EmploymentContractModel contract,
    required Uint8List signatureBytes,
    required Uint8List pdfBytes,
  }) async {
    if (contract.status == ContractStatus.voided) {
      throw Exception('무효 처리된 계약서에는 서명할 수 없습니다');
    }
    if (contract.status == ContractStatus.completed) {
      throw Exception('이미 완료된 계약서입니다');
    }
    // H-5: 사업주가 아직 서명하지 않은 상태에서는 근무자가 서명할 수 없음
    if (contract.status == ContractStatus.pendingEmployer) {
      throw Exception('사업주 서명이 완료되기 전에는 근무자가 서명할 수 없습니다.');
    }
    if (contract.workerSignatureUrl != null && contract.workerSignatureUrl!.isNotEmpty) {
      throw Exception('이미 근무자 서명이 완료된 계약서입니다');
    }

    // [SEC-WORKER-SIG] CF Admin SDK로 Storage 업로드 전환 (storage.rules: if false)
    // 클라이언트가 직접 업로드하지 않고 base64로 CF에 전달 → CF가 Admin SDK로 업로드
    final sigBase64 = base64Encode(signatureBytes);
    final pdfBase64 = base64Encode(pdfBytes);
    final cfPayload = {
      'contractId': contract.id,
      'signatureBase64': sigBase64,
      'pdfBase64': pdfBase64,
    };
    Map<Object?, Object?>? cfData;
    final injectedCall = _workerSignatureCall;
    try {
      final data = injectedCall != null
          ? await injectedCall(cfPayload)
          : (await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                  .httpsCallable('callableFinalizeWorkerSignature',
                      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
                  .call(cfPayload))
              .data;
      cfData = data as Map<Object?, Object?>?;
    } on FirebaseFunctionsException catch (e) {
      // CF 실패 → CF 내부에서 Storage 정리 완료. 명확한 거절은 그대로 실패다.
      if (!kEmployerSignatureIndeterminateCodes.contains(e.code)) rethrow;
      // [E2-WORKER-SIG-LOST-RESPONSE] 응답을 못 받았다 — 서버가 커밋했는지 원장으로 본다.
      //   성공으로 바꾸는 것은 이 계약이 이 근로자·지원서·사업장으로 completed 가 됐고,
      //   저장된 근로자 서명 해시와 PDF 해시가 **이번에 보낸 바이트**와 둘 다 같을 때뿐이다.
      //   CF 는 다시 부르지 않고 파일도 다시 올리지 않는다(읽기만).
      final confirmed = await _confirmWorkerSignatureCommitted(contract, signatureBytes, pdfBytes);
      if (confirmed.verdict != 'committed') {
        debugPrint('⚠️ [contract] 근무자 서명 응답 유실 — 커밋 확인 안 됨 '
            '(${contract.id}, ${e.code}, ${confirmed.verdict})');
        throw SignatureOutcomeUnknown(code: e.code, reason: confirmed.verdict);
      }
      debugPrint('ℹ️ [contract] 근무자 서명 응답 유실 — 원장에서 커밋 확인 (${contract.id}, ${e.code})');
      cfData = {
        'pdfStoragePath': confirmed.pdfStoragePath,
        'workerSignatureStoragePath': confirmed.sigStoragePath,
      };
    }

    // CF 응답 추출.
    //
    // [R8P6-PDF-REMEDIATION] PDF 는 더 이상 영구 URL 로 오지 않는다.
    //   CF 가 `pdfStoragePath` 를 돌려주고, 열람은 그때마다
    //   `callableGetContractPdfSignedUrl` 이 권한을 확인한 뒤 15분 링크로 낸다.
    //   그래서 여기서 검사하는 것도 URL 이 아니라 **경로**다.
    final cfPdfPath = cfData?['pdfStoragePath'] as String? ?? '';
    final cfSigUrl = cfData?['sigUrl'] as String? ?? '';
    // [R8P6-STAGE-B] 서명이 저장됐다는 증거는 **경로**다 — 단계 C 에서
    //   `sigUrl` 이 사라져도 근로자가 서명을 끝낼 수 있어야 한다.
    final cfSigPath = cfData?['workerSignatureStoragePath'] as String? ?? '';
    if (cfSigPath.isEmpty && cfSigUrl.isEmpty) {
      throw Exception('CF 응답에 근로자 서명 경로가 없음');
    }
    if (cfPdfPath.isEmpty) throw Exception('CF 응답에 pdfStoragePath 없음');

    final workerNow = DateTime.now(); // 로컬 변수 분리 — nullable ! 방지
    final updated = contract.copyWith(
      status: ContractStatus.completed,
      workerSignatureUrl: cfSigUrl.isNotEmpty ? cfSigUrl : null,
      workerSignatureAvailable: true,
      workerSignedAt: workerNow,
      pdfStoragePath: cfPdfPath,
      updatedAt: workerNow,
    );

    // [알림 흐름]
    // 1차) 근무자 지원 → 관리자에게 newApplication 알림 (application_firestore.dart)
    // 2차) 관리자 확정 + 계약서 발송 → 근무자에게 contractSignRequested 알림 (saveEmployerSignature)
    // 3차) 근무자 서명 완료 → 관리자 + canManageContract 서브어드민에게 contractSigned
    //
    // [R8-P3B] 3차 알림 발송을 callableFinalizeWorkerSignature CF 안으로 옮겼다.
    //   여기서는 사업장 문서를 한 번 읽고, 관리자 수만큼 createNotification 을
    //   **다시** 호출했다. 서명을 누른 근로자가 그 왕복을 전부 기다렸고
    //   (callable 왕복 하나가 DEV 실측 500ms대), 응답을 받은 직후 앱이 죽으면
    //   알림은 영구히 사라졌다. 2차(사업주 서명)는 이미 같은 이유로 CF 안에
    //   있었다 — 이쪽만 남아 있었다.
    //
    //   수신자 범위는 그대로다. 오히려 관리자 수만큼 반복되던 서브어드민
    //   팬아웃이 한 번으로 정리돼 중복 알림이 사라진다.

    return updated;
  }

  /// [E2-WORKER-SIG-LOST-RESPONSE] 근무자 서명·PDF 가 **이 시도로** 커밋됐는가.
  ///
  ///   읽는 것은 `employment_contracts/{contract.id}` 단건 get 하나다 — rules 의 get 은
  ///   `isOwner(resource.data.workerId)` 로 근로자 본인에게 열려 있다(DEV ruleset 8210de0d).
  ///   CF(00081)는 같은 tx 에서 `workerSignatureHash`·`pdfHash`(각 바이트의 sha256 hex)와
  ///   status completed·workerSignedAt·pdfStoragePath 를 쓴다. 둘 다 이번 바이트와 같아야 한다.
  ///   `absent`(없음·아직 미완료)면 한 번만 더 읽는다.
  Future<({String verdict, String pdfStoragePath, String sigStoragePath})> _confirmWorkerSignatureCommitted(
    EmploymentContractModel contract,
    Uint8List signatureBytes,
    Uint8List pdfBytes,
  ) async {
    final sigHash = sha256.convert(signatureBytes).toString();
    final pdfHash = sha256.convert(pdfBytes).toString();
    final reader = _contractDocReader ??
        (String id) async =>
            (await _db.collection('employment_contracts').doc(id).get()).data();
    String verdictOf(Map<String, dynamic>? d) {
      if (d == null) return 'absent';
      final appIds = (d['applicationIds'] as List?)?.whereType<String>().toSet() ?? const <String>{};
      final sameApp = contract.applicationId.isNotEmpty &&
          (d['applicationId'] == contract.applicationId || appIds.contains(contract.applicationId));
      if (!sameApp ||
          d['businessId'] != contract.businessId ||
          d['workerId'] != contract.workerId) {
        return 'mismatch';
      }
      if (d['status'] != 'completed' || d['workerSignedAt'] == null) return 'absent';
      final pathOk = (d['pdfStoragePath'] as String? ?? '').isNotEmpty;
      return (d['workerSignatureHash'] == sigHash && d['pdfHash'] == pdfHash && pathOk)
          ? 'committed'
          : 'mismatch';
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future<void>.delayed(_employerSignatureRecheckDelay);
      Map<String, dynamic>? doc;
      try {
        doc = await reader(contract.id);
      } catch (e) {
        debugPrint('⚠️ [contract] 근무자 서명 커밋 확인 읽기 실패 (${contract.id}): $e');
        return (verdict: 'readFailed', pdfStoragePath: '', sigStoragePath: '');
      }
      final v = verdictOf(doc);
      if (v == 'committed') {
        return (
          verdict: v,
          pdfStoragePath: doc!['pdfStoragePath'] as String,
          sigStoragePath: doc['workerSignatureStoragePath'] as String? ?? '',
        );
      }
      if (v != 'absent') return (verdict: v, pdfStoragePath: '', sigStoragePath: '');
    }
    return (verdict: 'absent', pdfStoragePath: '', sigStoragePath: '');
  }

  // ── 사용자 서명 저장/삭제 ─────────────────────────────────────

  /// users/{uid}.signatureBase64 저장 (CF callableSaveUserSignature 경유)
  Future<void> saveUserSignature({
    required String uid,
    required String base64,
  }) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid != uid) {
      throw StateError('saveUserSignature: 본인 서명만 저장 가능합니다.');
    }
    await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableSaveUserSignature')
        .call({'signatureBase64': base64});
  }

  /// 저장된 서명 삭제 (CF callableSaveUserSignature 경유)
  Future<void> clearUserSignature(String uid) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null || currentUid != uid) {
      throw StateError('clearUserSignature: 본인 서명만 삭제 가능합니다.');
    }
    await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableSaveUserSignature')
        .call({'signatureBase64': null});
  }

  /// 기존 계약서에 템플릿 조항 적용 (articles가 비어있던 구 계약서용)
  ///
  /// [BUG-수정] completed/voided 상태의 계약서는 수정 불가 — StateError 발생.
  Future<void> updateArticles({
    required String contractId,
    required List<ContractArticle> articles,
    String? templateId,
  }) async {
    // SEC-28: TOCTOU 방지 — 상태 체크와 쓰기를 트랜잭션으로 원자 처리
    final contractRef = _db.collection('employment_contracts').doc(contractId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(contractRef);
      if (!snap.exists) throw StateError('계약서를 찾을 수 없습니다.');
      final contract = EmploymentContractModel.tryFromFirestore(snap);
      if (contract == null) throw StateError('계약서 데이터를 파싱할 수 없습니다.');
      if (contract.status == ContractStatus.pendingWorker) {
        throw StateError('근무자 서명 대기 중인 계약서는 조항을 수정할 수 없습니다. 수정이 필요하면 계약서를 재발송하세요.');
      }
      if (contract.status == ContractStatus.completed ||
          contract.status == ContractStatus.voided) {
        throw StateError('서명 완료 또는 무효화된 계약서는 수정할 수 없습니다.');
      }
      tx.update(contractRef, {
        'articles': articles.map((a) => a.toMap()).toList(),
        if (templateId != null) 'templateId': templateId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // ── 조회 ─────────────────────────────────────────────────────

  /// contractId로 계약서 단건 조회 (get — list 보안 규칙 우회 불필요)
  ///
  /// 알림 등 contractId를 직접 갖고 있는 경우 사용.
  /// allow get 규칙: workerId/businessId 확인은 문서 fetch 후 판단하므로 복합 쿼리 문제 없음.
  Future<EmploymentContractModel?> getById(String contractId) async {
    try {
      final snap = await _db.collection('employment_contracts').doc(contractId).get();
      if (!snap.exists) return null;
      return EmploymentContractModel.tryFromFirestore(snap);
    } on FirebaseException catch (e) {
      debugPrint('❌ [contract] getById 실패 (Firebase): ${e.code} $e');
      return null;
    } catch (e) {
      debugPrint('❌ [contract] getById 실패: $e');
      return null;
    }
  }

  /// applicationId로 계약서 조회 (하위 호환 + 슬롯 포함 검색)
  ///
  /// 보안 규칙상 아래 중 하나를 반드시 전달해야 함:
  ///   [workerId] USER 컨텍스트 — 본인 uid (근무자가 자신의 계약서 조회)
  ///   [businessId] 관리자 컨텍스트 — 소속 사업장 id (관리자가 계약서 조회)
  ///
  /// [보안 주의] workerId 경로는 Firestore LIST 복합 쿼리를 실행한다.
  /// Firestore 보안 규칙은 USER role의 employment_contracts 직접 list를 거부한다
  /// (규칙 주석: "USER: CF getMyContracts 프록시로 이전 — 직접 list 불허").
  /// contractId를 이미 알고 있다면 반드시 [getById]를 사용해 단건 GET으로 조회할 것.
  /// 이 메서드를 USER 컨텍스트에서 호출하는 곳은 contractId가 없을 때만 폴백으로 사용해야 한다.
  Future<EmploymentContractModel?> getByApplication(
    String applicationId, {
    String? workerId,
    String? businessId,
  }) async {
    // assert 대신 throw — assert는 릴리스 빌드에서 무시되어 Firestore 보안 규칙 오류로 이어질 수 있음 (E-043)
    if (workerId == null && businessId == null) {
      throw ArgumentError('getByApplication: workerId 또는 businessId 중 하나는 필수입니다');
    }
    try {
      if (businessId != null) {
        // CF 호출: 복합 equality 쿼리 보안 규칙 버그 우회
        // (businessId + applicationId 복합 필터에서 request.query.filters.businessId → null 문제)
        final res = await _fn
            .httpsCallable('callableGetContractsByBiz')
            .call({'businessId': businessId, 'applicationId': applicationId, 'limit': 10});
        final raw = (res.data['contracts'] as List? ?? []).whereType<Map>().toList();
        if (raw.isNotEmpty) {
          final m = Map<String, dynamic>.from(raw.first);
          final id = m['id'] as String? ?? '';
          return EmploymentContractModel.tryFromMap(m, id);
        }
        return null;
      }
      // [CF-MIGRATED 2026-07-15] employment_contracts USER list 차단
      //   workerId 단독 경로는 PERMISSION_DENIED 발생 — 호출자 없음 (데드코드)
      //   contractId를 알고 있으면 getById(), 없으면 businessId 경로 필수
      debugPrint('⚠️ [contract] getByApplication(workerId:) — USER list 차단됨, null 반환');
      return null;
    } on FirebaseException catch (e) {
      // FAILED_PRECONDITION: 복합 인덱스 미생성 → 개발자가 인지해야 하므로 rethrow
      if (e.code == 'failed-precondition') {
        debugPrint('🚨 [contract] 복합 인덱스 누락: ${e.message}');
        rethrow;
      }
      debugPrint('❌ 계약서 조회 실패 (Firebase): $e');
      return null;
    } catch (e) {
      debugPrint('❌ 계약서 조회 실패: $e');
      return null;
    }
  }

  /// [BULK-DISPATCH-RECONCILE] 이 지원서에 **발송된 계약이 있는지** 원장에 묻는다.
  ///
  ///   일괄 발송이 실패했을 때 지원 상태를 되돌리기 전에 쓴다. 판정식은 서버와
  ///   **같은 한 벌**이다 — `srvContractNotIssuedYet`:
  ///   `voided · pending_employer · draft · (상태 없음)` 은 아직 미발송이다.
  ///
  ///   읽기 실패는 [ContractLedgerProbe.unknown] 이다. 0건으로 바꾸지 않는다.
  ///
  ///   조회 범위: 그 지원서 하나(`callableGetContractsByBiz` 의 `applicationId`
  ///   경로). 목록 전체를 다시 읽지 않고, polling 도 하지 않는다.
  ///
  ///   한계: CF 의 `applicationId` 경로는 **1차 링크만** 본다
  ///   (`applicationIds array-contains` 2차 링크는 보지 않는다). 번들 2차
  ///   지원서는 지금 생성 경로가 없어 실사용에는 해당 사례가 없다.
  Future<ContractLedgerProbe> probeIssuedContract(
    String applicationId, {
    required String businessId,
  }) async {
    if (applicationId.isEmpty || businessId.isEmpty) {
      return ContractLedgerProbe.unknown;
    }
    try {
      final res = await _fn
          .httpsCallable('callableGetContractsByBiz',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
          .call({
        'businessId': businessId,
        'applicationId': applicationId,
        'limit': 10,
      });
      final data = res.data;
      if (data is! Map) return ContractLedgerProbe.unknown;
      final listRaw = data['contracts'];
      // 응답 모양이 다르면 "없다"가 아니라 "모른다"다.
      if (listRaw is! List) return ContractLedgerProbe.unknown;
      final issued = listRaw.whereType<Map>().any((m) {
        final s = (m['status'] as String?) ?? '';
        return !(s.isEmpty ||
            s == 'voided' ||
            s == 'pending_employer' ||
            s == 'draft');
      });
      return issued
          ? ContractLedgerProbe.issued
          : ContractLedgerProbe.notIssued;
    } catch (e) {
      debugPrint('⚠️ [contract] 원장 재조회 실패 ($applicationId): $e');
      return ContractLedgerProbe.unknown;
    }
  }

  /// applicationId 목록으로 계약서 상태 일괄 조회 (지원명단 배지용)
  /// 반환: applicationId → contractStatus 문자열 (계약서 없으면 null)
  ///
  /// [CF 전환] 복합 equality 쿼리 보안 규칙 버그 우회:
  ///   applicationIds를 30개씩 청크로 나눠 callableGetContractsByBiz 병렬 호출.
  ///   CF는 applicationId 필드 직접 매핑만 수행하므로 번들 슬롯 2차 applicationId는
  ///   탐색 불가(null 처리). 배지 표시 전용 기능이므로 허용된 설계.
  ///
  /// [REISSUE-RECOVERY] **조회 실패한 지원서는 `unresolved` 로 따로 돌려준다.**
  ///
  ///   예전에는 청크 호출이 실패해도 그 청크의 모든 id 를 `null` 로 채웠다.
  ///   소비자는 `null` 을 "계약서 없음"으로 읽는다 — 그래서 조회 실패가
  ///   `계약서 미작성 N명` 이라는 **가짜 업무**가 됐고, 이미 완료된 계약에도
  ///   `계약서 작성` 버튼이 떴다. ERROR 와 ZERO 는 다른 사실이다.
  ///   성공한 청크의 결과는 그대로 쓴다 — 부분 성공을 버리지 않는다.
  Future<ContractStatusBatch> getContractStatusBatch(
    List<String> applicationIds, {
    required String businessId,
  }) async {
    if (applicationIds.isEmpty) return const ContractStatusBatch();
    final result = <String, String?>{};
    final unresolved = <String>{};

    // CF 병렬 호출: applicationIds 30개 단위 청크
    const chunkSize = 30;
    final futures = <Future<void>>[];
    for (var i = 0; i < applicationIds.length; i += chunkSize) {
      final chunk = applicationIds.sublist(
          i, (i + chunkSize).clamp(0, applicationIds.length));
      futures.add(() async {
        try {
          final res = await _fn
              .httpsCallable('callableGetContractsByBiz')
              .call({'businessId': businessId, 'applicationIds': chunk, 'limit': 200});
          final data = res.data;
          final raw = data is Map ? data['contracts'] : null;
          if (raw is! List) {
            // 응답 모양이 다르면 "계약 0건"이 아니라 **모르는 것**이다.
            unresolved.addAll(chunk);
            return;
          }
          for (final c in raw.whereType<Map>()) {
            final appId = c['applicationId'] as String?;
            final status = c['status'] as String?;
            if (appId != null && !result.containsKey(appId)) {
              result[appId] = status;
            }
          }
        } catch (e) {
          debugPrint('⚠️ 계약 상태 조회 오류 (청크 ${chunk.length}건): $e');
          unresolved.addAll(chunk);
        }
      }());
    }
    await Future.wait(futures);

    // 미매칭 항목 null 처리 (번들 슬롯 2차 applicationId 포함).
    //   조회에 성공한 청크에서만 "없음"으로 단정한다.
    for (final id in applicationIds) {
      if (unresolved.contains(id)) continue;
      result.putIfAbsent(id, () => null);
    }

    return ContractStatusBatch(statuses: result, unresolved: unresolved);
  }

  static final _fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  /// 근무자 uid로 계약서 목록 조회 (페이지네이션 + 상태 필터) — CF 프록시
  /// employment_contracts list 규칙에서 isUser() 제거 → CF로 auth.uid 기반 서버 검증
  Future<({List<EmploymentContractModel> items, String? lastDocId, bool hasMore})>
      getByWorkerPaged(
    String workerId, {
    ContractStatus? statusFilter,
    String? startAfter,
    int pageSize = 20,
  }) async {
    try {
      final callable = _fn.httpsCallable('getMyContracts',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
      final result = await callable.call({
        if (statusFilter != null) 'statusFilter': statusFilter.value,
        if (startAfter != null) 'lastDocId': startAfter,
        'pageSize': pageSize,
      });
      final data = (result.data as Map<dynamic, dynamic>?);
      if (data == null) throw Exception('CF 응답이 null입니다 (getPagedContracts)');
      final rawItems = (data['items'] as List<dynamic>? ?? []);
      final items = rawItems
          .whereType<Map>()
          .map((e) {
            final m = Map<String, dynamic>.from(e);
            final id = m.remove('id') as String? ?? '';
            return EmploymentContractModel.tryFromMap(m, id);
          })
          .whereType<EmploymentContractModel>()
          .toList();
      return (
        items: items,
        lastDocId: data['lastDocId'] as String?,
        hasMore: data['hasMore'] as bool? ?? false,
      );
    } catch (e) {
      debugPrint('❌ 근무자 계약서 조회 실패: $e');
      rethrow;
    }
  }

  /// 근무자 uid로 계약서 목록 조회 (하위 호환 - 내부 캐시용) — CF 프록시
  Future<List<EmploymentContractModel>> getByWorker(String workerId) async {
    try {
      final callable = _fn.httpsCallable('getMyContracts',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
      final result = await callable.call({'pageSize': 200});
      final data = (result.data as Map<dynamic, dynamic>?);
      if (data == null) return [];
      final rawItems = (data['items'] as List<dynamic>? ?? []);
      return rawItems
          .whereType<Map>()
          .map((e) {
            final m = Map<String, dynamic>.from(e);
            final id = m.remove('id') as String? ?? '';
            return EmploymentContractModel.tryFromMap(m, id);
          })
          .whereType<EmploymentContractModel>()
          .toList();
    } catch (e) {
      // [R8-P7.3] 빈 목록을 돌려주지 않는다. 계약은 약속이다 —
      //   조회가 실패했는데 "계약 없음"으로 보이면 화면은 근로자에게
      //   "관리자가 계약서를 준비 중"이라고 단정하고 서명 버튼을 숨긴다.
      //   서명을 기다리는 계약이 실제로 있어도 근로자는 서명할 수 없다.
      debugPrint('❌ 근무자 계약서 조회 실패: $e');
      rethrow;
    }
  }

  /// 사업장 계약서 목록 조회 (페이지네이션 + 상태 필터)
  ///
  /// [CF 전환] 복합 equality 쿼리 보안 규칙 버그 우회.
  /// startAfterId: DocumentSnapshot 대신 문서 ID 문자열 사용 (CF 커서 방식).
  Future<({List<EmploymentContractModel> items, String? lastDocId, bool hasMore})>
      getByBusinessPaged(
    String businessId, {
    ContractStatus? statusFilter,
    String? startAfterId,
    int pageSize = 20,
  }) async {
    try {
      // pageSize+1로 호출해 hasMore 정확도 보장 — 마지막 페이지에서 빈 호출 없앰 (E-047)
      final res = await _fn
          .httpsCallable('callableGetContractsByBiz')
          .call({
            'businessId': businessId,
            if (statusFilter != null) 'status': statusFilter.value,
            'limit': pageSize + 1,
            if (startAfterId != null) 'startAfterId': startAfterId,
          });
      final raw = (res.data['contracts'] as List? ?? []).whereType<Map>().toList();
      final hasMore = raw.length > pageSize;
      final page = hasMore ? raw.sublist(0, pageSize) : raw;
      final items = page
          .map((e) {
            final m = Map<String, dynamic>.from(e);
            final id = m['id'] as String? ?? '';
            return EmploymentContractModel.tryFromMap(m, id);
          })
          .whereType<EmploymentContractModel>()
          .toList();
      final lastDocId = page.isNotEmpty ? page.last['id'] as String? : null;
      return (items: items, lastDocId: lastDocId, hasMore: hasMore);
    } catch (e) {
      debugPrint('❌ 사업장 계약서 조회 실패: $e');
      rethrow;
    }
  }


  /// 계약서 무효화 (관리자 전용)
  /// [R8P6-PDF-REMEDIATION] 계약서 PDF 열람 링크를 **그때의 권한으로** 받는다.
  ///
  ///   예전에는 계약 문서의 `pdfUrl`(영구 다운로드 토큰)을 그대로 열었다.
  ///   그 URL 은 만료가 없고 로그인도 필요 없어서, 한 번 본 사람이 권한을
  ///   잃은 뒤에도 계속 열 수 있었다. 이제는 열 때마다 서버가 계약 당사자·
  ///   사업장 관계·`canManageContract` 를 확인한 뒤 15분 링크를 낸다.
  ///
  ///   돌려받은 URL 은 **저장하지 않는다.** 만료되면 다시 부른다.
  ///   레거시 계약(`pdfStoragePath` 없음)도 서버가 경로를 역산해 처리한다.
  Future<String> fetchContractPdfUrl(String contractId) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableGetContractPdfSignedUrl',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
    final result = await callable.call({'contractId': contractId});
    final data = result.data as Map<dynamic, dynamic>?;
    final url = data?['signedUrl'] as String? ?? '';
    if (url.isEmpty) throw Exception('CF 응답에 signedUrl 없음');
    return url;
  }

  /// [R8P6-SIG-CUTOVER] 서명 이미지(PNG) 열람 링크를 **그때의 권한으로** 받는다.
  ///
  ///   PDF 와 같은 인가 한 벌(`srvAssertContractViewAccess`)을 쓴다 — 같은 계약에서
  ///   PDF 는 열리고 서명은 막히는 상태가 생기지 않는다.
  ///   계약이 `pending_worker`(사업주만 서명)인 동안에도 근로자는 당사자이므로
  ///   사업주 서명을 볼 수 있다. 서버는 계약 **상태를 보지 않는다.**
  ///
  ///   `role` 은 `employer` 또는 `worker`. 클라이언트는 Storage 경로를
  ///   **보내지 않는다** — 서버가 계약 문서에서 경로를 찾고, 레거시 계약은
  ///   기존 URL 에서 경로만 역산한다.
  Future<ContractSignatureLink> fetchContractSignature(
    String contractId,
    String role,
  ) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableGetContractSignatureUrl',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
    final result = await callable.call({
      'contractId': contractId,
      'role': role,
    });
    final data = result.data as Map<dynamic, dynamic>?;
    final url = data?['signedUrl'] as String? ?? '';
    if (url.isEmpty) throw Exception('CF 응답에 signedUrl 없음');
    return ContractSignatureLink(
      url: url,
      // 서버가 판을 못 주는 구버전 CF 와 섞여 돌 수 있다 — 그때는 계약·역할만으로
      //   키를 만든다(재서명 후 옛 이미지가 남을 수 있으나 깨지지는 않는다).
      version: data?['signatureVersion'] as String? ?? 'unknown',
    );
  }

  /// [R8P6-SIG-CUTOVER] 서명 이미지 **바이트**를 가져온다 — PDF 에 박을 때 쓴다.
  ///
  ///   예전에는 계약 문서의 영구 토큰 URL 을 `http.get` 했다. 그 URL 이 사라지는
  ///   단계 C 에서는 **사업주 서명이 빠진 PDF 가 조용히 만들어졌다** — 서명란이
  ///   빈 계약서가 완료 처리되는 셈이다. 그래서 여기서는 못 가져온 것을
  ///   **예외로** 알린다. 빈 바이트를 돌려주지 않는다.
  ///
  ///   만료는 정상적인 일이다(링크 수명 15분). 403/401 이면 **한 번** 다시 발급받아
  ///   재시도한다. 두 번째도 실패하면 예외다.
  Future<Uint8List> fetchContractSignatureBytes(
    String contractId,
    String role,
  ) async {
    Future<http.Response> get(String url) => _http.get(Uri.parse(url));

    var link = await fetchContractSignature(contractId, role);
    var resp = await get(link.url);

    if (resp.statusCode == 401 || resp.statusCode == 403) {
      // 만료되었거나 서명이 더는 유효하지 않다 — 그때의 권한으로 한 번 더 받는다.
      link = await fetchContractSignature(contractId, role);
      resp = await get(link.url);
    }

    if (resp.statusCode != 200) {
      throw Exception('서명 이미지를 불러오지 못했습니다 (HTTP ${resp.statusCode})');
    }
    if (resp.bodyBytes.isEmpty) {
      throw Exception('서명 이미지가 비어 있습니다');
    }
    return resp.bodyBytes;
  }

  ///
  /// [CONTRACT-VOID-ATOMIC 2026-09-07] callableVoidContractWithApplications CF로 교체.
  ///   Contract void + Application cancel + ID-CONSENT grant revoke를 단일 Firestore
  ///   Transaction으로 처리. 기존 2단계 패턴(P1: split state 위험)을 제거.
  Future<void> voidContract(String contractId) async {
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableVoidContractWithApplications',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
    final result = await callable.call({'contractId': contractId});
    // Firebase SDK 런타임 반환형은 Map<dynamic,dynamic> — 방어 캐스팅
    final data = result.data as Map<dynamic, dynamic>?;

    final alreadyVoided = data?['alreadyVoided'] as bool? ?? false;
    if (alreadyVoided) return; // 멱등 처리 — 이미 voided 상태

    // [R8-P3B.1] 무효화 알림은 callableVoidContractWithApplications 가 보낸다.
    //
    //   예전에는 여기서 CF 응답을 받은 뒤 알림 callable 을 한 번 더 불렀다.
    //   근로자가 반드시 알아야 할 사실의 통지가 **호출자 앱의 생존**에
    //   달려 있었다 — 응답 직후 앱이 죽으면 계약이 무효가 된 줄 모른다.
    //   수신자(근로자 본인)·문구·목적지(userContracts)는 그대로다.
    //   [H-34] 알림 실패가 TX 상태(voided+CANCELED)를 되돌리지 않는 것도 그대로다.
  }

  /// voidFailedAppIds에 기록된 application들을 재시도로 취소 처리.
  /// 성공한 항목은 voidFailedAppIds에서 제거하고, 전부 성공 시 필드를 삭제.
  Future<void> retryVoidFailedApps(EmploymentContractModel contract) async {
    if (contract.voidFailedAppIds.isEmpty) return;

    // [PERF] 재처리 N+1 → 병렬 처리 (voidContract와 동일 패턴)
    final retryResults = await Future.wait(
      contract.voidFailedAppIds.map((appId) async {
        try {
          final ok = await _firestoreService.cancelConfirmedApplication(
            appId,
            canceledBy: 'system', // [W-2] 재처리도 시스템 취소 — ADMIN_CANCELED 기록 유지
            cancelReason: '계약서가 무효화되었습니다',
          );
          if (!ok) {
            debugPrint('⚠️ retryVoidFailedApps: application 취소 실패 ($appId): false 반환');
            return appId;
          }
          return null;
        } catch (e) {
          debugPrint('⚠️ retryVoidFailedApps: application 취소 실패 ($appId): $e');
          return appId;
        }
      }),
    );
    final stillFailedIds = retryResults.whereType<String>().toList();

    // 성공한 항목 반영: 전부 성공 시 voidFailedAppIds 필드 삭제, 일부 실패 시 갱신
    await _db.collection('employment_contracts').doc(contract.id).update({
      'voidFailedAppIds': stillFailedIds.isEmpty
          ? FieldValue.delete()
          : stillFailedIds,
    });

    if (stillFailedIds.isNotEmpty) {
      throw Exception('${stillFailedIds.length}개 지원서 재처리 실패. 잠시 후 다시 시도해주세요.');
    }
  }

  // ── 내부: 번들 탐색 ──────────────────────────────────────────

  /// 단기 번들 계약서 탐색 (toId + workDetailId + workerId 조합으로 기존 번들 찾기)
  ///
  /// [CF 전환] 5중 equality 필터가 보안 규칙 버그를 확실히 유발하므로 CF 사용.
  /// Admin SDK는 보안 규칙을 우회하여 복합 필터를 안전하게 실행한다.
  Future<EmploymentContractModel?> _findBundle({
    required String toId,
    required String workDetailId,
    required String workerId,
    required String businessId,
  }) async {
    try {
      final res = await _fn
          .httpsCallable('callableGetContractsByBiz')
          .call({
            'businessId': businessId,
            'toId': toId,
            'workDetailId': workDetailId,
            'workerId': workerId,
            'isLongTerm': false,
            // [GAP-1] 슬롯을 **추가할 수 있는** 계약만 고른다.
            //
            //   예전에는 상태를 묻지 않고 `limit: 1` 로 받아 와서 호출자가
            //   걸렀다. 그런데 그 CF 는 `orderBy` 가 없어 문서 id 순으로 주고
            //   auto-id 는 무작위다 — 같은 키에 계약이 둘 이상이면(사업주 서명
            //   뒤 날짜가 추가돼 쪼개진 경우) **아무거나** 하나가 왔다.
            //   그게 서명된 쪽이면 이어붙일 수 있는 미서명 계약을 놓치고
            //   계약이 또 쪼개졌다.
            //
            //   서버는 `status` 를 `limit` **전에** where 로 적용하므로
            //   (`buildBase()` → `q.limit(cap)`), 여기서 넘기면 후보가 정확해진다.
            'status': 'pending_employer',
            'limit': 1,
          });
      final raw = (res.data['contracts'] as List? ?? []).whereType<Map>().toList();
      if (raw.isEmpty) return null;
      final m = Map<String, dynamic>.from(raw.first);
      final id = m['id'] as String? ?? '';
      return EmploymentContractModel.tryFromMap(m, id);
    } catch (e) {
      debugPrint('❌ 번들 계약서 조회 실패: $e');
      rethrow; // null 반환 시 _createNew가 중복 계약서를 생성하므로 에러 전파
    }
  }

  // ── 내부: 슬롯 추가 ──────────────────────────────────────────

  Future<EmploymentContractModel> _addSlot(
    EmploymentContractModel contract,
    ApplicationModel application,
    WorkDetailData workDetail,
  ) async {
    // [GAP-2] 시간은 그 날짜의 지원서에서, 임금은 이미 그렇게 하고 있었다.
    final times = _promisedTimes(application);
    final newSlot = ContractSlot(
      applicationId: application.id,
      workDate: _fmtDate(application.workDate),
      startTime: times.start,
      endTime: times.end,
      wage: workDetail.wage,
      wageType: workDetail.wageType,
    );

    final contractRef = _db.collection('employment_contracts').doc(contract.id);

    // 트랜잭션으로 동시 확정 시 슬롯 유실 방지 (last-write-wins 방지)
    final updatedContract = await _db.runTransaction((tx) async {
      final snap = await tx.get(contractRef);
      if (!snap.exists) throw Exception('계약서를 찾을 수 없습니다: ${contract.id}');
      final current = EmploymentContractModel.tryFromFirestore(snap);
      if (current == null) throw StateError('계약서 데이터를 파싱할 수 없습니다: ${contract.id}');

      // 멱등성 보호 — 동일 applicationId가 이미 등록된 경우 슬롯 중복 추가 방지
      // (이중 확정 또는 동시 호출 시 발생 가능)
      if (current.applicationIds.contains(application.id)) {
        return current;
      }

      // [SEC-FIX] 트랜잭션 내 status 재검증 — K-001 외부 검증(L57)과 트랜잭션 진입 사이
      // 사업주 서명이 완료된 경우 slotの추가를 차단해 서명 무결성 보호
      if (current.status != ContractStatus.pendingEmployer) {
        throw StateError('계약서가 이미 서명 단계에 있어 슬롯을 추가할 수 없습니다: ${current.status.value}');
      }

      final updatedSlots = [...current.slots, newSlot];
      final updatedIds = [...current.applicationIds, application.id];
      final now = DateTime.now(); // copyWith 용 로컬 변수 (Firestore는 serverTimestamp 사용)
      tx.update(contractRef, {
        'slots': updatedSlots.map((s) => s.toMap()).toList(),
        'applicationIds': updatedIds,
        'updatedAt': FieldValue.serverTimestamp(), // [M3-FIX] serverTimestamp 강제
      });
      return current.copyWith(
        slots: updatedSlots,
        applicationIds: updatedIds,
        updatedAt: now,
      );
    });

    return updatedContract;
  }

  // ── 내부: 신규 생성 ──────────────────────────────────────────

  Future<EmploymentContractModel> _createNew({
    required ApplicationModel application,
    required BusinessModel business,
    required UserModel worker,
    required WorkDetailData workDetail,
    required String toId,
    required String workDetailId,
    List<ContractArticle> articles = const [],
    String? templateId,
  }) async {
    // ownerName이 없으면 ownerId로 users 컬렉션에서 조회
    BusinessModel effectiveBusiness = business;
    if (business.ownerName == null || business.ownerName!.trim().isEmpty) {
      try {
        final ownerDoc = await _db.collection('users').doc(business.ownerId).get();
        final data = ownerDoc.data();
        // 사업자등록증 대표자명(ceoName) 우선, 없으면 계정 이름
        final ceoName = data?['ceoName'] as String?;
        final accountName = data?['name'] as String?;
        final name = (ceoName?.trim().isNotEmpty == true) ? ceoName : accountName;
        if (name != null && name.trim().isNotEmpty) {
          effectiveBusiness = business.copyWith(ownerName: name);
        }
      } catch (e) {
        debugPrint('대표자 이름 조회 실패: $e');
      }
    }

    bool isLong = application.isLongTermApplication;
    // 기존 데이터(type 필드 미기록)를 위해 TO 타입으로 fallback
    if (!isLong && toId.isNotEmpty) {
      try {
        final toDoc = await _db.collection('tos').doc(toId).get();
        if (toDoc.exists && toDoc.data()?['type'] == TOType.contract) {
          isLong = true;
        }
      } catch (e) {
        debugPrint('TO 타입 조회 실패 (fallback): $e');
      }
    }
    final snapshot = _buildSnapshot(
      application: application,
      business: effectiveBusiness,
      worker: worker,
      workDetail: workDetail,
      isLongTermOverride: isLong,
    );

    // 단기: 첫 슬롯 생성
    final slots = isLong
        ? <ContractSlot>[]
        : [
            // [GAP-2] 시간의 출처는 그 날짜의 지원서다 — 마스터 TO 가 아니다.
            ContractSlot(
              applicationId: application.id,
              workDate: _fmtDate(application.workDate),
              startTime: _promisedTimes(application).start,
              endTime: _promisedTimes(application).end,
              wage: workDetail.wage,
              wageType: workDetail.wageType,
            ),
          ];

    final ref = _db.collection('employment_contracts').doc();
    final contract = EmploymentContractModel(
      id: ref.id,
      applicationId: application.id,
      businessId: business.id,
      workerId: worker.uid,
      isLongTerm: isLong,
      toId: toId,
      workDetailId: workDetailId,
      slots: slots,
      applicationIds: [application.id],
      status: ContractStatus.pendingEmployer,
      snapshot: snapshot,
      articles: articles,
      templateId: templateId,
      createdAt: DateTime.now(),
      isNewUnsaved: true,  // 서명 완료 시 최초 저장
    );

    // Firestore에 저장하지 않음 — 사업주 서명 시 최초 저장
    return contract;
  }

  // ── 스냅샷 생성 ──────────────────────────────────────────────

  ContractSnapshot _buildSnapshot({
    required ApplicationModel application,
    required BusinessModel business,
    required UserModel worker,
    required WorkDetailData workDetail,
    bool? isLongTermOverride,
  }) {
    final isLong = isLongTermOverride ?? application.isLongTermApplication;
    return ContractSnapshot(
      businessName: business.name,
      businessNumber: business.formattedBusinessNumber,
      businessAddress: [business.address, business.detailAddress]
          .whereType<String>()
          .join(' '),
      businessPhone: business.phone,
      ownerName: business.ownerName ?? '',
      // [V3 FOREIGN-DOCUMENT-FIRST] officialName = 외국인은 legalName 우선, 내국인은 name
      workerName: worker.officialName,
      workerBirthDate:
          worker.birthDate != null ? _fmtDate(worker.birthDate) : null,
      workerPhone: worker.effectivePhone,
      workerAddress: [worker.address, worker.detailAddress]
              .whereType<String>()
              .join(' ')
              .trim()
              .isEmpty
          ? null
          : [worker.address, worker.detailAddress]
              .whereType<String>()
              .join(' ')
              .trim(),
      workType: workDetail.workType,
      workPlace: business.address,
      isLongTerm: isLong,
      // 희망 시작일 우선, 없으면 workDate(TO 시작일 or 지원일) 사용
      contractStart: isLong
          ? _fmtDate(application.desiredStartDate ?? application.workDate)
          : null,
      // workEndDate가 null(개방형 계약)이면 '' 대신 null을 전달 — '' 전달 시 workPeriodText != null 체크 통과
      contractEnd: isLong && application.workEndDate != null
          ? _fmtDate(application.workEndDate)
          : null,
      workDays: application.workDays,
      startTime: workDetail.startTime,
      endTime: workDetail.endTime,
      breakMinutes: workDetail.breakMinutes,
      wage: workDetail.wage,
      wageType: workDetail.wageType,
      wagePaymentDay: business.wagePaymentDay,
      baseHourlyWage: workDetail.baseHourlyWage,
      payScheduleType: workDetail.payScheduleType,
      payScheduleDay: workDetail.payScheduleDay,
      payScheduleTime: workDetail.payScheduleTime,
      taxDeductionType: workDetail.taxDeductionType,
      // [R7-PAYROLL-POLICY.4] 출처는 **Application 의 canonical snapshot**
      //   하나다. `business.attendanceRules` 를 여기서 읽지 않는다 — 그러면
      //   계약서가 말하는 기준과 서버가 적용하는 기준이 갈라진다.
      //   없으면 계약서에도 적지 않는다(기본값을 합의 내용으로 만들지 않는다).
      attendancePolicy: application.attendancePolicySnapshot,
    );
  }

  // ── 유틸 ─────────────────────────────────────────────────────

  String _fmtDate(DateTime? d) =>
      d == null ? '' : FormatHelper.formatDateISO(d);
}
