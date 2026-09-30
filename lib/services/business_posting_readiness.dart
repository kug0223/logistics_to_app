import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/core/business_model.dart';
import 'firestore_service.dart';

/// [5D.2A] 공고 등록 준비 상태 — 서버 5D.1A assertBusinessPostingReady와 동일 정책.
///
/// 서버 기준:
///   business.isApproved == true
///   AND (business.businessLicenseImageUrl 존재
///        OR users/{business.ownerId}.businessLicenseImageUrl 존재)
///   AND business/workTypes isActive==true count >= 1
///
/// Flutter helper는 UX precheck/display 용도.
/// 서버가 최종 authority — 이 클래스의 결과와 서버 결과가 다를 수 있음.
///
/// [중요] legacy fallback은 반드시 business.ownerId 기준.
/// 호출자(SubAdmin / co-admin)의 businessLicenseImageUrl을 fallback으로 사용하면
/// 오너가 license 없는 사업장이 READY로 오판된다.
class BusinessPostingReadiness {
  final String bizId;
  final bool isApproved;
  final bool hasCanonicalLicense;
  final bool hasOwnerLegacyLicense;
  final bool hasActiveWorkTypes;

  /// [R8-P7.4] 업무 목록을 **읽지 못했다**.
  ///
  /// 이때 [hasActiveWorkTypes]는 false지만 그것은 "업무가 없다"는 뜻이 아니다.
  /// [isReady]는 그대로 false로 둔다 — 서버가 최종 gate이므로 모를 때 열어 주면
  /// 안 된다. 다만 "업무를 등록하세요"라고 **단정하는 안내**는 이 값이 true인
  /// 동안 만들지 않는다.
  final bool workTypesUnknown;

  /// [P4.4C] 이 사업장의 **고용주 날인**(`businesses/{id}.ownerId` 의
  /// `users/{ownerId}.sealBase64`)이 있는가.
  ///
  /// 호출자 자신의 날인이 아니다 — 계약 writer 가 실제로 쓰는 것과 같은 값이다.
  final bool hasEmployerSeal;

  /// 사업주 문서를 **읽지 못했다.** [hasEmployerSeal] 은 false 지만 그것이
  /// "날인이 없다" 는 뜻은 아니다. [isReady] 는 false 로 두되(서버가 최종
  /// gate), "인감을 등록하세요" 라고 **단정하는 안내**는 만들지 않는다.
  final bool employerSealUnknown;

  const BusinessPostingReadiness({
    required this.bizId,
    required this.isApproved,
    required this.hasCanonicalLicense,
    required this.hasOwnerLegacyLicense,
    required this.hasActiveWorkTypes,
    this.workTypesUnknown = false,
    this.hasEmployerSeal = false,
    this.employerSealUnknown = false,
  });

  /// canonical OR owner legacy
  bool get hasLicense => hasCanonicalLicense || hasOwnerLegacyLicense;

  /// **사업장 축** 준비 — 승인 · 등록증 · 활성 업무.
  ///
  /// [P4.4C] 이것은 서버 gate 전체가 아니다. 서버는 여기에 **계약서 템플릿**과
  /// **고용주 날인**을 더 요구한다(`assertBusinessPostingReady`).
  /// 일부러 나눠 둔다 — Home 체크리스트가 항목별로 무엇이 빠졌는지 말해야
  /// 하는데, 다섯 축을 하나로 접으면 날인이 없을 때 '업무 등록' 칸이
  /// 미완료로 보인다(잘못된 귀인). 전체 gate 는 서버가 최종 판정한다.
  bool get isReady => isApproved && hasLicense && hasActiveWorkTypes;

  /// 고용주 날인이 없다고 **말할 수 있는가**. 못 읽었으면 말하지 않는다.
  bool get isMissingEmployerSeal => !employerSealUnknown && !hasEmployerSeal;

  /// 업무가 없다고 **말할 수 있는가**. 못 읽었으면 말하지 않는다.
  bool get isMissingWorkTypes => !workTypesUnknown && !hasActiveWorkTypes;

  // ────────────────────────────────────────────────────
  // Static helpers
  // ────────────────────────────────────────────────────

  /// ownerId 기준 라이선스 유무만 비동기 체크.
  /// workType은 포함하지 않음 — 가볍게 라이선스만 확인할 때 사용.
  ///
  /// canonical이 이미 있으면 Firestore 조회 없이 즉시 반환.
  static Future<bool> hasLicenseForBusiness(BusinessModel biz) async {
    if (biz.businessLicenseImageUrl?.isNotEmpty == true) return true;
    final ownerId = biz.ownerId;
    if (ownerId.isEmpty) return false;
    try {
      final ownerSnap = await FirebaseFirestore.instance
          .collection('users')
          .doc(ownerId)
          .get();
      return _ownerHasLicense(ownerSnap.data());
    } catch (_) {
      return false;
    }
  }

  /// [R8-P5.1] owner 문서의 사업자등록증 보유 여부.
  ///
  ///   서버(checkBusinessLicense)와 같은 순서로 본다 —
  ///   businessLicenseImagePath(CF가 기록한 canonical) 우선, 레거시 URL 폴백.
  ///   path만 보면 레거시 사용자가 NOT READY로 보이고,
  ///   URL만 보면 신규 등록자가 NOT READY로 보인다.
  static bool _ownerHasLicense(Map<String, dynamic>? ownerData) {
    if (ownerData == null) return false;
    final path = ownerData['businessLicenseImagePath'] as String?;
    if (path?.isNotEmpty == true) return true;
    return (ownerData['businessLicenseImageUrl'] as String?)?.isNotEmpty == true;
  }

  /// 단일 사업장의 전체 readiness 비동기 조회.
  ///
  /// [firestoreService] — getBusinessWorkTypes(isActive==true) 의존.
  static Future<BusinessPostingReadiness> forBusiness(
    BusinessModel biz,
    FirestoreService firestoreService,
  ) async {
    final isApproved = biz.isApproved;

    final hasCanonicalLicense =
        biz.businessLicenseImageUrl?.isNotEmpty == true;

    // [P4.4C] owner 문서를 한 번 읽어 **등록증 legacy 폴백**과
    //   **고용주 날인**을 같이 본다.
    //
    //   날인을 여기서 보는 이유: `actor seal` 과 `employer seal readiness` 는
    //   다른 문제다. 예전에는 화면들이 **호출자 자신의** `sealBase64` 를 보고
    //   SubAdmin 이면 그냥 면제했다. 그러면 owner 날인이 없는 사업장도
    //   SubAdmin 경로로 준비 완료가 되고, 확정 이후 계약 단계에서 막힌다.
    //   계약 writer 가 실제로 쓰는 것은 `business.ownerId` 의 날인이므로
    //   readiness 도 같은 것을 봐야 한다.
    bool hasOwnerLegacyLicense = false;
    bool hasEmployerSeal = false;
    bool employerSealUnknown = false;
    final ownerId = biz.ownerId;
    if (ownerId.isEmpty) {
      // owner 를 모르면 "날인 없음" 이 아니라 **모른다** 다.
      employerSealUnknown = true;
    } else {
      try {
        final ownerSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(ownerId)
            .get();
        final ownerData = ownerSnap.data();
        if (!hasCanonicalLicense) {
          hasOwnerLegacyLicense = _ownerHasLicense(ownerData);
        }
        hasEmployerSeal =
            (ownerData?['sealBase64'] as String?)?.isNotEmpty == true;
      } catch (e) {
        debugPrint('⚠️ [readiness] 사업주 문서 조회 실패 [${biz.id}]: $e');
        // 읽기 실패를 "날인 없음" 으로 접지 않는다 — 서버가 최종 gate 다.
        employerSealUnknown = true;
      }
    }

    bool hasActiveWorkTypes = false;
    // [R8-P7.4] 읽기 실패를 "업무 0개"로 접지 않는다.
    bool workTypesUnknown = false;
    if (isApproved) {
      try {
        final wts = await firestoreService.getBusinessWorkTypes(biz.id);
        hasActiveWorkTypes = wts.isNotEmpty;
      } catch (e) {
        debugPrint('⚠️ [readiness] 업무 유형 조회 실패 [${biz.id}]: $e');
        workTypesUnknown = true;
      }
    }

    return BusinessPostingReadiness(
      bizId: biz.id,
      isApproved: isApproved,
      hasCanonicalLicense: hasCanonicalLicense,
      hasOwnerLegacyLicense: hasOwnerLegacyLicense,
      hasActiveWorkTypes: hasActiveWorkTypes,
      workTypesUnknown: workTypesUnknown,
      hasEmployerSeal: hasEmployerSeal,
      employerSealUnknown: employerSealUnknown,
    );
  }

  /// [POSTING-V2-02C.1] 실제로 공고를 만들 수 있는 사업장이 하나라도 있는가.
  ///
  /// `any(hasLicense) && any(hasActiveWorkTypes)` 형태로 풀어 쓰지 않는다 —
  /// 그렇게 접으면 A의 등록증과 B의 업무가 합쳐져, 존재하지 않는
  /// "준비된 사업장"이 만들어진다. 서버 gate는 business 단위이므로
  /// 조건도 같은 business 안에서 모두 성립해야 한다.
  static bool hasReadyBusiness(
    Map<String, BusinessPostingReadiness> readinessMap,
  ) =>
      readinessMap.values.any((r) => r.isReady);

  /// 여러 사업장 readiness 병렬 조회.
  /// 반환: bizId → BusinessPostingReadiness
  static Future<Map<String, BusinessPostingReadiness>> forBusinesses(
    List<BusinessModel> businesses,
    FirestoreService firestoreService,
  ) async {
    final entries = await Future.wait(
      businesses.map((biz) async {
        final r = await forBusiness(biz, firestoreService);
        return MapEntry(biz.id, r);
      }),
    );
    return Map.fromEntries(entries);
  }

  // ────────────────────────────────────────────────────
  // [APPROVAL-RECOVERY] 승인 상태 재확인
  // ────────────────────────────────────────────────────

  /// 사업장 승인 상태를 서버에 다시 확인한다.
  ///
  /// 자동 승인은 사업장 생성 시 1회만 실행되고 재평가 트리거가 없다.
  /// 그 순간 Storage 확인이 실패하면 사업자등록증이 정상인데도
  /// 미승인 상태가 고착된다. 이 호출은 서버가 자동 승인 정책과
  /// 사업자등록증을 **다시 판정**하게 하는 경로다.
  ///
  /// 승인 권한을 클라이언트가 갖는 것이 아니다 — 판정은 전적으로 서버가 한다.
  /// 클라이언트는 businessId만 보내고 결과 상태를 받는다.
  static Future<BusinessApprovalRecheck> recheckApproval(String businessId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableRecheckBusinessApproval');
      final res = await callable.call<Map<String, dynamic>>({
        'businessId': businessId,
      });
      final status = res.data['status'] as String?;
      return BusinessApprovalRecheck.values.firstWhere(
        (e) => e.wireName == status,
        // 서버가 새 상태를 추가해도 클라이언트가 임의 해석하지 않는다.
        orElse: () => BusinessApprovalRecheck.temporaryCheckFailed,
      );
    } on FirebaseFunctionsException catch (e) {
      debugPrint('❌ [recheckApproval] ${e.code}: ${e.message}');
      // 권한/입력 오류는 재시도로 풀리지 않으므로 구분해 올린다.
      if (e.code == 'permission-denied' || e.code == 'unauthenticated') {
        return BusinessApprovalRecheck.notPermitted;
      }
      if (e.code == 'not-found') return BusinessApprovalRecheck.notFound;
      return BusinessApprovalRecheck.temporaryCheckFailed;
    } catch (e) {
      debugPrint('❌ [recheckApproval] $e');
      return BusinessApprovalRecheck.temporaryCheckFailed;
    }
  }
}

/// 첫 공고까지 필요한 준비 — **사용자 mental model 기준** 4개.
///
/// CreateTO의 correctness predicate는 canonical fact 5개
/// (승인 / 업무 / 계약서 템플릿 / 사업자등록증 / 인감)를 그대로 쓴다.
/// 사업자등록증은 사업장 등록 폼에서 필수로 받으므로 사용자에게는
/// "사업장 준비" 안에 포함된 것으로 보이는 편이 실제 경험과 맞다.
enum FirstPostingTask {
  /// 사업장 등록 + 승인 + 사업자등록증
  business,

  /// 업무 등록
  workType,

  /// 계약서 템플릿 (신규 계약에 쓸 수 있는 분류)
  contractTemplate,

  /// 인감/서명
  seal,
}

/// 첫 공고 준비 상태 — 기존 canonical fact에서만 derive한다.
///
/// 저장되는 onboarding 플래그가 없다. 사업장 승인/등록증, 업무, 템플릿,
/// 인감이 각각 canonical이며 이 클래스는 그것을 읽어 조합할 뿐이다.
///
/// 홈과 CreateTO가 **같은 의미**를 쓰도록 하는 것이 이 클래스의 목적이다.
/// 이전에는 홈이 서버 강제 항목(등록증·업무) 2개만 세고 CreateTO가 5개를
/// 요구해, 홈에서 준비 카드가 사라진 뒤에도 공고 등록에서 다시 막혔다.
class FirstPostingReadiness {
  /// 사업장이 하나라도 있는가 (승인 여부 무관)
  final bool hasAnyBusiness;

  /// 승인 + 사업자등록증을 모두 갖춘 사업장이 있는가
  final bool businessReady;

  /// [POSTING-V2-02C.1] 공고를 실제로 만들 수 있는 사업장이 있는가.
  ///
  /// "승인된 사업장 중 활성 업무가 있는 곳이 있는가"가 아니다 —
  /// 승인·등록증·업무가 **같은 사업장**에서 모두 성립해야 한다.
  /// (`BusinessPostingReadiness.hasReadyBusiness`)
  final bool workTypesReady;

  /// [R8-P7.4] 업무 상태를 읽지 못한 사업장이 있어 [workTypesReady]를
  /// "아직 아니다"로 단정할 수 없다.
  ///
  /// 준비 완료로 올리지는 않는다(서버가 최종 gate). 대신 "업무를 등록하세요"라는
  /// 안내를 만들지 않는다 — 업무가 이미 있는 관리자에게 그 문장은 거짓이다.
  final bool workTypesUnknown;

  /// 신규 계약에 쓸 수 있는 템플릿이 있는가 (관리자 보유 전 사업장 합산)
  final bool contractTemplateReady;

  /// 인감/서명이 등록되어 있는가
  final bool sealReady;

  const FirstPostingReadiness({
    required this.hasAnyBusiness,
    required this.businessReady,
    required this.workTypesReady,
    required this.contractTemplateReady,
    required this.sealReady,
    this.workTypesUnknown = false,
  });

  static const int totalTasks = 4;

  bool isDone(FirstPostingTask task) {
    switch (task) {
      case FirstPostingTask.business:
        return businessReady;
      case FirstPostingTask.workType:
        return workTypesReady;
      case FirstPostingTask.contractTemplate:
        return contractTemplateReady;
      case FirstPostingTask.seal:
        return sealReady;
    }
  }

  /// 지금 바로 수행할 수 있는가.
  ///
  /// 강제 순서를 만들지 않는다 — 실제 의존성이 있는 항목만 잠근다.
  ///   · 사업장     : 언제나 가능
  ///   · 업무       : 사업장이 있어야 businessId로 이동할 수 있다
  ///   · 계약 템플릿 : 사업장이 있어야 저장 위치가 생긴다.
  ///                  **승인은 필요 없다** — Rules도 isAdminOf만 요구한다.
  ///   · 인감       : users/{uid} 값이라 사업장과 무관, 가입 직후부터 가능
  bool isActionable(FirstPostingTask task) {
    switch (task) {
      case FirstPostingTask.business:
      case FirstPostingTask.seal:
        return true;
      case FirstPostingTask.workType:
      case FirstPostingTask.contractTemplate:
        return hasAnyBusiness;
    }
  }

  int get completedCount =>
      FirstPostingTask.values.where(isDone).length;

  bool get allReady => completedCount == totalTasks;

  /// 아직 남은 준비 (표시 순서 유지)
  List<FirstPostingTask> get remaining =>
      FirstPostingTask.values.where((t) => !isDone(t)).toList();
}

/// 승인 재확인 결과.
///
/// [wireName]은 서버 result contract와 1:1로 대응한다.
/// 클라이언트가 승인 여부를 스스로 계산하지 않고 이 값만 해석한다.
enum BusinessApprovalRecheck {
  /// 이미 승인된 상태 — 반복 호출에 안전
  alreadyApproved('ALREADY_APPROVED'),

  /// 이번 호출로 승인됨
  approved('APPROVED'),

  /// 수동 승인 정책(businessAutoApprove=false)이거나 비활성화된 사업장.
  /// 재확인으로 통과시킬 수 없다.
  awaitingManualReview('AWAITING_MANUAL_REVIEW'),

  /// 사업자등록증을 확인할 수 없음 (미등록/잘못된 경로/파일 없음)
  licenseNotReady('LICENSE_NOT_READY'),

  /// 판정 자체를 하지 못함 — 일시적일 수 있으므로 "없음"으로 단정하지 않는다
  temporaryCheckFailed('TEMPORARY_CHECK_FAILED'),

  /// 소유자가 아니거나 로그인 상태가 아님 (클라이언트 전용 매핑)
  notPermitted('__NOT_PERMITTED'),

  /// 사업장을 찾을 수 없음 (클라이언트 전용 매핑)
  notFound('__NOT_FOUND');

  final String wireName;
  const BusinessApprovalRecheck(this.wireName);

  bool get isApproved =>
      this == approved || this == alreadyApproved;

  /// 재시도로 해결될 수 있는 상태인가.
  bool get isRetryable => this == temporaryCheckFailed;
}

// ═══════════════════════════════════════════════════════════════════
// [R7-P4.4E.2A] 첫 공고 준비 상태 — canonical resolver + scoped projection
// ═══════════════════════════════════════════════════════════════════

/// 한 번의 판정이 만들어 내는 것 전부.
///
///   Home 은 사업장별 결핍(`readinessMap`)으로 CTA 대상을 고르고,
///   공고 root·CreateTO 는 합산 결과(`readiness`)만 본다.
///   둘이 다른 코드로 계산되면 같은 사업장을 두고 다른 말을 하게 된다.
class FirstPostingReadinessResult {
  const FirstPostingReadinessResult({
    required this.readiness,
    required this.readinessMap,
  });

  final FirstPostingReadiness readiness;
  final Map<String, BusinessPostingReadiness> readinessMap;
}

/// 준비 상태를 **누가 물어보든 같은 방법으로** 계산한다.
///
///   예전에는 이 판정이 Home 위젯의 State 안에만 있었다. 그래서 Home 을 한
///   번도 그리지 않고 공고 탭으로 바로 들어가면 아무도 답을 갖고 있지 않았다.
///   계산을 화면 밖으로 꺼낸다 — UX 소유(무엇을 어떻게 보여줄지)는 여전히
///   Home 이지만, **사실**은 화면의 생명주기에 매이지 않는다.
class FirstPostingReadinessResolver {
  FirstPostingReadinessResolver._();

  static Future<FirstPostingReadinessResult> resolve({
    required List<BusinessModel> businesses,
    required Future<Map<String, BusinessPostingReadiness>> Function(
            List<BusinessModel>)
        postingReadiness,
    required Future<List<dynamic>> Function(String businessId) contractTemplates,
    required bool Function(List<dynamic>) selectableForNewContract,
    required bool callerHasSeal,
  }) async {
    final approved = businesses.where((b) => b.isApproved).toList();
    final readinessMap = approved.isEmpty
        ? <String, BusinessPostingReadiness>{}
        : await postingReadiness(approved);

    // [P4.4B-TPL-01] 템플릿은 **사업장별**이다 — 합산하지 않는다.
    //   공고를 낼 수 있는 사업장이 있으면 그 사업장의 템플릿을 본다(CreateTO
    //   가 실제로 쓰는 사실과 같게). 아직 없으면 진행도 표시로만 쓴다.
    var hasTemplate = false;
    if (businesses.isNotEmpty) {
      try {
        final lists = await Future.wait(
          businesses.map((b) => contractTemplates(b.id)),
        );
        bool selectable(int i) => selectableForNewContract(lists[i]);

        final postable = <int>[];
        for (var i = 0; i < businesses.length; i++) {
          if (readinessMap[businesses[i].id]?.isReady == true) postable.add(i);
        }
        hasTemplate = postable.isNotEmpty
            ? postable.any(selectable)
            : List.generate(lists.length, (i) => i).any(selectable);
      } catch (e) {
        // 조회 실패를 "준비됨"으로 올리지 않는다 — 서버가 최종 gate 다.
        debugPrint('⚠️ [readiness] 계약서 템플릿 조회 실패: $e');
      }
    }

    // [P4.4C-SEAL-02] `actor seal` 과 `employer seal readiness` 는 다르다.
    //   사업장이 아직 없거나 전부 미승인이면 읽을 owner 가 없으므로, 그때만
    //   호출자를 예비 owner 로 보고 자기 날인으로 진행도를 표시한다.
    final sealReady = readinessMap.isEmpty
        ? callerHasSeal
        : readinessMap.values.any((r) => r.hasEmployerSeal);

    return FirstPostingReadinessResult(
      readinessMap: readinessMap,
      readiness: FirstPostingReadiness(
        hasAnyBusiness: businesses.isNotEmpty,
        // 사업장 task 는 승인 + 등록증까지만 — 업무는 다음 task 가 맡는다.
        businessReady:
            readinessMap.values.any((r) => r.isApproved && r.hasLicense),
        // [POSTING-V2-02C.1] 업무 task 는 business identity 를 유지한다.
        workTypesReady: BusinessPostingReadiness.hasReadyBusiness(readinessMap),
        // [R8-P7.4] "업무가 없어서" 와 "못 읽어서" 를 구분한다.
        workTypesUnknown: readinessMap.values.any((r) => r.workTypesUnknown) &&
            !readinessMap.values.any((r) => r.isMissingWorkTypes),
        contractTemplateReady: hasTemplate,
        sealReady: sealReady,
      ),
    );
  }
}

/// 판정 결과가 지금 어떤 상태인가.
///
///   `null` 하나에 여러 뜻을 섞지 않는다 — "아직 안 셌다" 와 "세다가 실패했다"
///   와 "준비가 덜 됐다" 는 사용자에게 보여야 할 것이 전부 다르다.
enum FirstPostingReadinessStatus {
  /// 아무도 아직 묻지 않았다.
  idle,

  /// 지금 세고 있다.
  loading,

  /// 셌다. `value` 가 있다.
  resolved,

  /// 세려다 실패했다. 준비 미완료가 **아니다**.
  failed,
}

/// 어느 계정·어느 사업장 집합에 대한 판정인지까지 들고 있는 한 장면.
class FirstPostingReadinessSnapshot {
  const FirstPostingReadinessSnapshot({
    required this.status,
    this.value,
    this.uid,
    this.scopeKey,
  });

  const FirstPostingReadinessSnapshot.idle()
      : status = FirstPostingReadinessStatus.idle,
        value = null,
        uid = null,
        scopeKey = null;

  final FirstPostingReadinessStatus status;
  final FirstPostingReadiness? value;

  /// 이 판정을 만든 계정. 다른 계정이 보면 그 값은 **남의 것**이다.
  final String? uid;

  /// 이 판정이 덮는 사업장 집합. 전환되면 다시 세야 한다.
  final String? scopeKey;

  bool get isResolved => status == FirstPostingReadinessStatus.resolved;

  /// 지금 이 사용자에게 이 값을 보여도 되는가.
  bool matches(String? currentUid, String? currentScopeKey) =>
      uid != null && uid == currentUid && scopeKey == currentScopeKey;
}

/// 화면들이 **같은 진실**을 보도록 최신 판정을 들고 있는 자리.
///
///   Home 은 계속 setup UX 의 owner 다 — 전체 체크리스트와 각 단계로 가는
///   길은 Home 에만 있다. 다만 **값** 은 Home 위젯이 살아 있는지와 무관하게
///   존재해야 한다. 예전에는 Home 이 그리지 않으면 아무도 답을 몰랐고,
///   공고 탭은 그 모름을 "정상 · 공고 0건" 으로 그렸다.
class FirstPostingReadinessStore {
  FirstPostingReadinessStore._();

  static final ValueNotifier<FirstPostingReadinessSnapshot> current =
      ValueNotifier<FirstPostingReadinessSnapshot>(
          const FirstPostingReadinessSnapshot.idle());

  static Future<void>? _inFlight;

  /// 여러 사업장을 한 문자열로 — 집합이 바뀌면 판정도 바뀐다.
  static String scopeKeyOf(Iterable<String> businessIds) {
    final ids = businessIds.toList()..sort();
    return ids.join(',');
  }

  static void publish(
    FirstPostingReadiness value, {
    required String? uid,
    required String scopeKey,
  }) {
    current.value = FirstPostingReadinessSnapshot(
      status: FirstPostingReadinessStatus.resolved,
      value: value,
      uid: uid,
      scopeKey: scopeKey,
    );
  }

  static void markFailed({required String? uid, required String scopeKey}) {
    current.value = FirstPostingReadinessSnapshot(
      status: FirstPostingReadinessStatus.failed,
      uid: uid,
      scopeKey: scopeKey,
    );
  }

  /// 로그아웃·계정 전환·사업장 전환처럼 이전 판정을 이어 쓰면 안 되는 경계.
  static void reset() {
    _inFlight = null;
    current.value = const FirstPostingReadinessSnapshot.idle();
  }

  /// 이 사용자·이 사업장 집합에 대한 값이 없으면 채운다.
  ///
  ///   Home 을 한 번도 그리지 않았어도 공고 탭이 스스로 물어볼 수 있다.
  ///   이미 같은 scope 의 값이 있으면 다시 세지 않는다. 동시에 여러 화면이
  ///   물어도 한 번만 센다.
  static Future<void> ensureLoaded({
    required String? uid,
    required String scopeKey,
    required Future<FirstPostingReadiness> Function() resolve,
    /// 이미 아는 값이 있어도 다시 센다. 앱 복귀처럼 그 사이 다른 기기·다른
    /// 관리자가 템플릿이나 날인을 바꿨을 수 있는 순간에만 쓴다.
    bool force = false,
  }) {
    final snap = current.value;
    if (!force && snap.isResolved && snap.matches(uid, scopeKey)) {
      return Future<void>.value();
    }
    if (_inFlight != null && snap.matches(uid, scopeKey)) return _inFlight!;

    current.value = FirstPostingReadinessSnapshot(
      status: FirstPostingReadinessStatus.loading,
      uid: uid,
      scopeKey: scopeKey,
      // 세는 동안에도 이전 값을 들고 있으면 깜빡이지 않는다 — 단 scope 가
      // 같을 때만이다. 다른 계정의 값을 이어 보여주지 않는다.
      value: snap.matches(uid, scopeKey) ? snap.value : null,
    );

    final future = () async {
      try {
        final value = await resolve();
        publish(value, uid: uid, scopeKey: scopeKey);
      } catch (e) {
        debugPrint('❌ [readiness] 준비 상태 조회 실패: $e');
        markFailed(uid: uid, scopeKey: scopeKey);
      } finally {
        _inFlight = null;
      }
    }();
    _inFlight = future;
    return future;
  }
}
