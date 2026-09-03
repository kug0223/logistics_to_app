import 'package:cloud_firestore/cloud_firestore.dart';

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
}
