import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';

import '../models/core/business_member_model.dart';
import '../models/core/member_invitation_model.dart';
import '../models/core/notification_model.dart';
import '../utils/format_helper.dart';
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

  /// 전화번호로 근무자 검색 (숫자형·하이픈형 모두 시도)
  Future<Map<String, dynamic>?> findUserByPhone(String phone) async {
    // 입력값 정규화: 숫자만 추출
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final formatted = FormatHelper.formatPhone(digits); // 010-1234-5678

    // 두 형식으로 순차 조회 (DB 저장 방식이 다를 수 있음)
    for (final query in [digits, formatted]) {
      try {
        final snap = await _db
            .collection('users')
            .where('phone', isEqualTo: query)
            .where('role', isEqualTo: 'USER')
            .limit(1)
            .get();
        if (snap.docs.isNotEmpty) {
          final doc = snap.docs.first;
          final data = doc.data();
          return {
            'uid': doc.id,
            'name': data['name'] ?? '',
            'phone': data['phone'] ?? '',
          };
        }
      } catch (e) {
        debugPrint('전화번호 검색 실패 ($query): $e');
      }
    }
    return null;
  }

  /// 이미 해당 사업장 멤버인지 확인
  Future<bool> isAlreadyMember(String businessId, String uid) async {
    final doc = await _members(businessId).doc(uid).get();
    return doc.exists;
  }

  /// 이미 유효한 pending 초대가 있는지 확인 (30일 이내 발송된 것만)
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
      debugPrint('⚠️ hasPendingInvitation CF 오류, 폴백: $e');
      return false;
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

  /// 초대 수락 → members 서브컬렉션에 추가
  /// user.subAdminOf 설정은 onMemberInvitationAccepted CF trigger가 담당 (BUG-33C-33 fix)
  ///
  /// ⚠️ F-032: 동시 이중 수락 시 알림 2건 중복 발생 가능(데이터 무결성 문제 없음).
  Future<void> acceptInvitation(MemberInvitationModel invitation) async {
    // [D05-FIX] 만료/거절/취소 상태 초대 수락 방어 (F-035).
    // UI에서 pending만 노출하지만 딥링크·직접 호출 경로 방어를 위해 서버 검증 추가.
    if (!invitation.isPending) {
      throw Exception('이미 처리된 초대입니다.');
    }
    // 30일 만료 체크 (hasPendingInvitation과 동일 기준)
    final expiryDate = invitation.createdAt.add(const Duration(days: 30));
    if (DateTime.now().isAfter(expiryDate)) {
      throw Exception('초대 유효기간(30일)이 만료되었습니다.');
    }
    // [HIGH-01] 이미 해당 사업장 멤버이면 batch.set으로 기존 권한이 덮어씌워짐 — 사전 차단
    final alreadyMember = await isAlreadyMember(
      invitation.businessId,
      invitation.targetUid,
    );
    if (alreadyMember) {
      throw Exception('이미 해당 사업장의 멤버입니다.');
    }

    final batch = _db.batch();
    final now = DateTime.now();

    // 1. 초대 상태 업데이트 → trigger에서 subAdminOf 설정
    // [M9-FIX] respondedAt serverTimestamp 사용 — 기기 시계 조작으로 수락 시각 위변조 차단
    batch.update(_invitations.doc(invitation.id), {
      'status': 'accepted',
      'respondedAt': FieldValue.serverTimestamp(),
    });

    // 2. members 서브컬렉션에 추가 (invitationId 포함 — 규칙에서 pending 초대 검증에 사용)
    // [M9-FIX] addedAt serverTimestamp 사용 — 기기 시계 조작으로 가입 시각 위변조 차단
    //   BusinessMemberModel(addedAt: now)의 DateTime은 toMap() 경유 → Timestamp 변환이라 조작 가능.
    //   batch.set 시 map에 FieldValue.serverTimestamp()를 직접 오버라이드.
    final member = BusinessMemberModel(
      uid: invitation.targetUid,
      name: invitation.targetName,
      phone: invitation.targetPhone,
      permissions: invitation.permissions,
      addedAt: now,          // UI 표시용 로컬 임시값, 실제 저장은 아래 serverTimestamp 사용
      addedBy: invitation.invitedBy,
      invitationId: invitation.id,
    );
    batch.set(
      _members(invitation.businessId).doc(invitation.targetUid),
      {...member.toMap(), 'addedAt': FieldValue.serverTimestamp()},
    );

    await batch.commit();

    // 4. 초대한 관리자에게 수락 알림
    try {
      await _firestoreService.createNotification(
        NotificationModel.createMemberInvitationAccepted(
          adminUid: invitation.invitedBy,
          acceptedName: invitation.targetName,
          businessName: invitation.businessName,
          businessId: invitation.businessId,
        ),
      );
    } catch (e) {
      debugPrint('초대 수락 알림 발송 실패: $e');
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

  /// 특정 사용자의 pending 초대 목록 (30일 이내만 — 만료된 초대 자동 제외)
  /// [CF 이전 2026-07-15] callableGetMyInvitations — targetUid 서버 검증 강제
  Future<List<MemberInvitationModel>> getPendingInvitations(String uid) async {
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetMyInvitations',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      final result = await callable.call<Map<String, dynamic>>({});
      final expiry = DateTime.now().subtract(const Duration(days: 30));
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
      debugPrint('초대 목록 조회 실패: $e');
      return [];
    }
  }

  /// invitationId로 초대 조회
  Future<MemberInvitationModel?> getInvitation(String invitationId) async {
    try {
      final doc = await _invitations.doc(invitationId).get();
      if (!doc.exists) return null;
      return MemberInvitationModel.tryFromFirestore(doc);
    } catch (e) {
      debugPrint('초대 조회 실패: $e');
      return null;
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
      debugPrint('멤버 목록 조회 실패: $e');
      return [];
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
      return null;
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

  /// 멤버 제거 → user.subAdminOf 초기화
  Future<void> removeMember({
    required String businessId,
    required String uid,
  }) async {
    final memberRef = _members(businessId).doc(uid);
    final userRef = _db.collection('users').doc(uid);

    // 트랜잭션으로 subAdminOf 현재 값 확인 후 일치 시에만 삭제 (BUG-F-01)
    // 사용자가 다른 사업장의 서브어드민인 경우 무조건 삭제하면 타 사업장 권한을 잃음
    await _db.runTransaction((tx) async {
      final userSnap = await tx.get(userRef);
      tx.delete(memberRef);
      final currentSubAdminOf = userSnap.data()?['subAdminOf'] as String?;
      if (currentSubAdminOf == businessId) {
        tx.update(userRef, {'subAdminOf': FieldValue.delete()});
      }
    });
  }
}
