import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/core/business_member_model.dart';
import '../models/core/member_invitation_model.dart';
import '../models/core/notification_model.dart';
import 'firestore_service.dart';

class MemberService {
  final _db = FirebaseFirestore.instance;
  final _firestoreService = FirestoreService();

  CollectionReference _members(String businessId) => _db
      .collection('businesses')
      .doc(businessId)
      .collection('members');

  CollectionReference get _invitations =>
      _db.collection('member_invitations');

  // ── 초대 발송 ─────────────────────────────────────────────────

  /// 전화번호로 근무자 검색 — callableGetUserByPhone CF 경유
  /// [CF-MIGRATED 2026-07-17] users list: if isSuperAdmin() 강화(M-3) 후
  /// BUSINESS_ADMIN PERMISSION_DENIED 발생 → Admin SDK CF 이전
  Future<Map<String, dynamic>?> findUserByPhone(String phone) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetUserByPhone',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      final result = await callable.call<Map<String, dynamic>>({'phone': phone});
      final uid = result.data['uid'] as String?;
      if (uid == null) return null;
      return {
        'uid': uid,
        'name': result.data['name'] as String? ?? '',
        'phone': result.data['phone'] as String? ?? '',
      };
    } catch (e) {
      // null 반환 시 "사용자 없음"과 "CF 오류"를 호출자가 구분 불가
      debugPrint('전화번호 검색 실패: $e');
      rethrow;
    }
  }

  /// 이미 해당 사업장 멤버인지 확인
  Future<bool> isAlreadyMember(String businessId, String uid) async {
    final doc = await _members(businessId).doc(uid).get();
    return doc.exists;
  }

  /// 이미 유효한 pending 초대가 있는지 확인 (3일 이내 발송된 것만)
  /// [CF 이전 2026-07-13] callableCheckPendingInvitation
  Future<bool> hasPendingInvitation(String businessId, String targetUid) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableCheckPendingInvitation',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': businessId,
        'targetUid': targetUid,
      });
      return result.data['hasPending'] as bool? ?? false;
    } catch (e) {
      // false 반환 시 pending 초대가 있어도 없다고 판단해 중복 초대 허용 위험
      debugPrint('⚠️ hasPendingInvitation CF 오류: $e');
      rethrow;
    }
  }

  /// 초대 발송
  ///
  /// ⚠️ TOCTOU 경쟁조건 (F-020): isAlreadyMember + hasPendingInvitation 확인 후 실제 발송 사이에
  /// 다른 클라이언트가 동시 초대를 발송할 수 있음. 관리자 단독 운영 환경에서는 발생 확률 극히 낮음.
  Future<void> sendInvitation({
    required String businessId,
    required String businessName,
    required String targetUid,
    required String targetName,
    String? targetPhone,
    required String invitedBy,
    required String invitedByName,
    required MemberPermissions permissions,
  }) async {
    final ref = _invitations.doc();
    final invitation = MemberInvitationModel(
      id: ref.id,
      businessId: businessId,
      businessName: businessName,
      targetUid: targetUid,
      targetName: targetName,
      targetPhone: targetPhone,
      invitedBy: invitedBy,
      invitedByName: invitedByName,
      permissions: permissions,
      status: InvitationStatus.pending,
      createdAt: DateTime.now(),
    );
    final invMap = Map<String, dynamic>.from(invitation.toMap());
    invMap['createdAt'] = FieldValue.serverTimestamp();
    await ref.set(invMap);

    // 초대받은 사람에게 알림
    try {
      await _firestoreService.createNotification(
        NotificationModel.createMemberInvitation(
          targetUid: targetUid,
          businessName: businessName,
          businessId: businessId,
          invitedByName: invitedByName,
          invitationId: ref.id,
        ),
      );
    } catch (e) {
      debugPrint('멤버 초대 알림 발송 실패: $e');
    }
  }

  // ── 초대 수락/거절 ─────────────────────────────────────────────

  /// 초대 수락 → [CF-MIGRATED D4-CP1] callableAcceptInvitation CF 경유
  /// 3일 만료 서버 강제 — 클라이언트 직접 Firestore 배치에서 Admin SDK로 이전
  /// onMemberInvitationAccepted 트리거: subAdminOf 설정 (변경 없음)
  Future<void> acceptInvitation(MemberInvitationModel invitation) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableAcceptInvitation',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 20)));
      await callable.call<Map<String, dynamic>>({'invitationId': invitation.id});
    } catch (e) {
      // FirebaseFunctionsException.message를 Exception으로 래핑 — 호출부 catch 호환
      debugPrint('초대 수락 CF 실패: $e');
      rethrow;
    }
  }

  /// 초대 거절 (근로자 측)
  Future<void> rejectInvitation(MemberInvitationModel invitation) async {
    // [MEDIUM-03] pending 상태가 아닌 초대에 대한 중복 거절 방어
    if (!invitation.isPending) {
      throw Exception('이미 처리된 초대입니다.');
    }
    await _invitations.doc(invitation.id).update({
      'status': 'rejected',
      'respondedAt': FieldValue.serverTimestamp(),
    });

    // 초대한 관리자에게 거절 알림
    try {
      await _firestoreService.createNotification(
        NotificationModel.createMemberInvitationRejected(
          adminUid: invitation.invitedBy,
          rejectedName: invitation.targetName,
          businessName: invitation.businessName,
          businessId: invitation.businessId,
        ),
      );
    } catch (e) {
      debugPrint('초대 거절 알림 발송 실패: $e');
    }
  }

  /// 초대 취소 (관리자 측) — [HIGH-02] Firestore rules status 화이트리스트와 동기화
  Future<void> cancelInvitation(MemberInvitationModel invitation) async {
    if (!invitation.isPending) {
      throw Exception('이미 처리된 초대는 취소할 수 없습니다.');
    }
    await _invitations.doc(invitation.id).update({
      'status': 'cancelled',
      'canceledAt': FieldValue.serverTimestamp(),
    });
  }

  // ── 초대 조회 ─────────────────────────────────────────────────

  /// 특정 사용자의 pending 초대 목록 (3일 이내만 — 만료된 초대 자동 제외)
  /// [CF 이전 2026-07-15] callableGetMyInvitations — targetUid 서버 검증 강제
  Future<List<MemberInvitationModel>> getPendingInvitations(String uid) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetMyInvitations',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      final result = await callable.call<Map<String, dynamic>>({});
      final expiry = DateTime.now().subtract(const Duration(days: 3));
      return (result.data['invitations'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final d = Map<String, dynamic>.from(m);
            final id = d.remove('id') as String? ?? '';
            return MemberInvitationModel.tryFromMap(d, id);
          })
          .whereType<MemberInvitationModel>()
          .where((inv) => inv.createdAt.isAfter(expiry))
          .toList();
    } catch (e) {
      // return [] 시 CF 오류를 "초대 없음"으로 오판 — 호출자에게 전파
      debugPrint('초대 목록 조회 실패: $e');
      rethrow;
    }
  }

  /// 관리자가 해당 사업장에 발송한 pending 초대 목록 (3일 이내만)
  /// [CF 이전 2026-07-27] member_invitations list 쿼리 PERMISSION_DENIED → callableGetSentPendingInvitations
  Future<List<MemberInvitationModel>> getSentPendingInvitations(String businessId) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetSentPendingInvitations',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      final result = await callable.call<Map<String, dynamic>>({'businessId': businessId});
      final expiry = DateTime.now().subtract(const Duration(days: 3));
      return (result.data['invitations'] as List? ?? [])
          .whereType<Map>()
          .map((m) {
            final d = Map<String, dynamic>.from(m);
            final id = d.remove('id') as String? ?? '';
            return MemberInvitationModel.tryFromMap(d, id);
          })
          .whereType<MemberInvitationModel>()
          .where((inv) => inv.createdAt.isAfter(expiry))
          .toList();
    } catch (e) {
      debugPrint('⚠️ getSentPendingInvitations CF 오류: $e');
      rethrow;
    }
  }

  /// invitationId로 초대 조회
  Future<MemberInvitationModel?> getInvitation(String invitationId) async {
    try {
      final doc = await _invitations.doc(invitationId).get();
      if (!doc.exists) return null;
      return MemberInvitationModel.tryFromFirestore(doc);
    } catch (e) {
      // null 반환 시 "초대 없음"과 "Firestore 오류"를 호출자가 구분 불가
      debugPrint('초대 조회 실패: $e');
      rethrow;
    }
  }

  // ── 멤버 관리 ─────────────────────────────────────────────────

  /// 사업장 멤버 목록 조회
  Future<List<BusinessMemberModel>> getMembers(String businessId) async {
    try {
      final snap = await _members(businessId)
          .orderBy('addedAt', descending: false)
          .limit(200)
          .get();
      return snap.docs.map(BusinessMemberModel.tryFromFirestore).whereType<BusinessMemberModel>().toList();
    } catch (e) {
      // return [] 시 Firestore 오류를 "멤버 없음"으로 오판 — 호출자에게 전파
      debugPrint('멤버 목록 조회 실패: $e');
      rethrow;
    }
  }

  /// 특정 멤버 권한 조회
  Future<MemberPermissions?> getMemberPermissions(
      String businessId, String uid) async {
    try {
      final doc = await _members(businessId).doc(uid).get();
      if (!doc.exists) return null;
      final data = doc.data() as Map<String, dynamic>;
      return MemberPermissions.fromMap(
          (data['permissions'] as Map<String, dynamic>?) ?? {});
    } catch (e) {
      debugPrint('멤버 권한 조회 실패: $e');
      rethrow;
    }
  }

  /// 멤버 권한 업데이트
  ///
  /// ⚠️ F-042: 멤버 문서가 없으면 Firestore update() throw — 호출부(UI)에서 try/catch로 보호됨.
  Future<void> updatePermissions({
    required String businessId,
    required String uid,
    required MemberPermissions permissions,
  }) async {
    await _members(businessId).doc(uid).update({
      'permissions': permissions.toMap(),
    });
  }

  /// 멤버 제거 → user.subAdminBusinessIds에서 해당 사업장만 제거 (다른 사업장 권한 유지)
  ///
  /// [TODO-CF] Trust Boundary Charter — subAdminBusinessIds는 _protectedUserFields.
  /// acceptInvitation처럼 callableRemoveMember CF로 이전 예정.
  /// 현재는 Firestore rules에서 BUSINESS_ADMIN의 자신 사업장 멤버에 대한 arrayRemove를 허용.
  Future<void> removeMember({
    required String businessId,
    required String uid,
  }) async {
    final memberRef = _members(businessId).doc(uid);
    final userRef = _db.collection('users').doc(uid);

    await _db.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      tx.delete(memberRef);
      // subAdminBusinessIds 배열에서 해당 사업장만 제거 (다른 사업장 권한 유지)
      final data = userSnap.data();
      if (data == null) return;
      final ids = (data['subAdminBusinessIds'] as List?)?.cast<String>() ?? [];
      final legacy = data['subAdminOf'] as String?;
      final isSubAdminOfThisBiz =
          ids.contains(businessId) || legacy == businessId;
      if (isSubAdminOfThisBiz) {
        tx.update(userRef, {
          'subAdminBusinessIds': FieldValue.arrayRemove([businessId]),
          'subAdminOf': FieldValue.delete(),
        });
      }
    });
  }
}
