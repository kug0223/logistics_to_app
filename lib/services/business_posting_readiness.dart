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

  const BusinessPostingReadiness({
    required this.bizId,
    required this.isApproved,
    required this.hasCanonicalLicense,
    required this.hasOwnerLegacyLicense,
    required this.hasActiveWorkTypes,
  });

  /// canonical OR owner legacy
  bool get hasLicense => hasCanonicalLicense || hasOwnerLegacyLicense;

  /// 공고 등록 가능 여부 (서버와 동일 로직)
  bool get isReady => isApproved && hasLicense && hasActiveWorkTypes;

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
      return (ownerSnap.data()?['businessLicenseImageUrl'] as String?)
              ?.isNotEmpty ==
          true;
    } catch (_) {
      return false;
    }
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

    // owner legacy — business.ownerId 기준, 호출자 uid 아님
    bool hasOwnerLegacyLicense = false;
    if (!hasCanonicalLicense) {
      final ownerId = biz.ownerId;
      if (ownerId.isNotEmpty) {
        try {
          final ownerSnap = await FirebaseFirestore.instance
              .collection('users')
              .doc(ownerId)
              .get();
          hasOwnerLegacyLicense =
              (ownerSnap.data()?['businessLicenseImageUrl'] as String?)
                      ?.isNotEmpty ==
                  true;
        } catch (_) {}
      }
    }

    bool hasActiveWorkTypes = false;
    if (isApproved) {
      try {
        final wts = await firestoreService.getBusinessWorkTypes(biz.id);
        hasActiveWorkTypes = wts.isNotEmpty;
      } catch (_) {}
    }

    return BusinessPostingReadiness(
      bizId: biz.id,
      isApproved: isApproved,
      hasCanonicalLicense: hasCanonicalLicense,
      hasOwnerLegacyLicense: hasOwnerLegacyLicense,
      hasActiveWorkTypes: hasActiveWorkTypes,
    );
  }

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
