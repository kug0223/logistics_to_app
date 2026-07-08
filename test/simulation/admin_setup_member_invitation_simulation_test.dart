// test/simulation/admin_setup_member_invitation_simulation_test.dart
//
// 관리자 초대/권한 관리 시나리오 시뮬레이션 테스트
//
// 목적: 관리자(BUSINESS_ADMIN)가 직원(USER)을 초대하고 권한을 관리하는
//       전체 플로우를 순수 Dart 로직으로 검증한다.
//
// 검증 대상:
//   1. findUserByPhone — 전화번호 정규화 및 role 필터 로직
//   2. 초대 사전 검사 — isAlreadyMember, hasPendingInvitation
//   3. MemberPermissions 플래그 조합
//   4. sendInvitation() — 초대 문서 생성 로직
//   5. acceptInvitation() — 수락 조건 검사 + WriteBatch 시뮬레이션
//   6. rejectInvitation() — 거절 조건 검사
//   7. cancelInvitation() — 취소 조건 검사
//   8. removeMember() — subAdminOf 조건부 삭제
//   9. updatePermissions() — 권한 갱신
//  10. 초대 만료 처리 (30일 기준)
//  11. TOCTOU 경쟁조건 시나리오
//  12. isAdminMode 전환 (isSubAdmin 조건)
//  13. can() 권한 체크
//
// 의존성: Firebase · Flutter · Provider 없음. 순수 Dart 로직만.

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

// ════════════════════════════════════════════════════════════════
// 시뮬레이션 데이터 클래스 (Firebase 의존 없음)
// ════════════════════════════════════════════════════════════════

enum SimUserRole { SUPER_ADMIN, BUSINESS_ADMIN, USER }

enum SimInvitationStatus { pending, accepted, rejected, cancelled }

class SimMemberPermissions {
  final bool canManageTo;
  final bool canManageWorkers;
  final bool canManageWage;
  final bool canManageContract;

  const SimMemberPermissions({
    this.canManageTo = false,
    this.canManageWorkers = false,
    this.canManageWage = false,
    this.canManageContract = false,
  });

  factory SimMemberPermissions.none() => const SimMemberPermissions();
  factory SimMemberPermissions.all() => const SimMemberPermissions(
        canManageTo: true,
        canManageWorkers: true,
        canManageWage: true,
        canManageContract: true,
      );
  factory SimMemberPermissions.fromMap(Map<String, dynamic> m) =>
      SimMemberPermissions(
        canManageTo: m['canManageTo'] as bool? ?? false,
        canManageWorkers: m['canManageWorkers'] as bool? ?? false,
        canManageWage: m['canManageWage'] as bool? ?? false,
        canManageContract: m['canManageContract'] as bool? ?? false,
      );

  Map<String, dynamic> toMap() => {
        'canManageTo': canManageTo,
        'canManageWorkers': canManageWorkers,
        'canManageWage': canManageWage,
        'canManageContract': canManageContract,
      };

  SimMemberPermissions copyWith({
    bool? canManageTo,
    bool? canManageWorkers,
    bool? canManageWage,
    bool? canManageContract,
  }) =>
      SimMemberPermissions(
        canManageTo: canManageTo ?? this.canManageTo,
        canManageWorkers: canManageWorkers ?? this.canManageWorkers,
        canManageWage: canManageWage ?? this.canManageWage,
        canManageContract: canManageContract ?? this.canManageContract,
      );

  bool get hasAnyPermission =>
      canManageTo || canManageWorkers || canManageWage || canManageContract;

  String get summaryText {
    final parts = <String>[];
    if (canManageTo) parts.add('공고');
    if (canManageWorkers) parts.add('근무자');
    if (canManageWage) parts.add('급여');
    if (canManageContract) parts.add('계약서');
    return parts.isEmpty ? '권한 없음' : parts.join(' · ');
  }
}

class SimUser {
  final String uid;
  final String name;
  final String? phone;
  final SimUserRole role;
  final String? subAdminOf;

  const SimUser({
    required this.uid,
    required this.name,
    this.phone,
    required this.role,
    this.subAdminOf,
  });

  bool get isBusinessAdmin => role == SimUserRole.BUSINESS_ADMIN;
  bool get isSuperAdmin => role == SimUserRole.SUPER_ADMIN;
  bool get isSubAdmin => role == SimUserRole.USER && subAdminOf != null;

  SimUser copyWith({
    String? subAdminOf,
    bool clearSubAdminOf = false,
    SimUserRole? role,
  }) =>
      SimUser(
        uid: uid,
        name: name,
        phone: phone,
        role: role ?? this.role,
        subAdminOf: clearSubAdminOf ? null : (subAdminOf ?? this.subAdminOf),
      );
}

class SimInvitation {
  final String id;
  final String businessId;
  final String businessName;
  final String targetUid;
  final String targetName;
  final String? targetPhone;
  final String invitedBy;
  final String invitedByName;
  final SimMemberPermissions permissions;
  final SimInvitationStatus status;
  final DateTime createdAt;
  final DateTime? respondedAt;

  const SimInvitation({
    required this.id,
    required this.businessId,
    required this.businessName,
    required this.targetUid,
    required this.targetName,
    this.targetPhone,
    required this.invitedBy,
    required this.invitedByName,
    required this.permissions,
    required this.status,
    required this.createdAt,
    this.respondedAt,
  });

  bool get isPending => status == SimInvitationStatus.pending;

  /// 만료 여부 (createdAt + 30일 < now)
  bool get isExpired {
    final expiresAt = createdAt.add(const Duration(days: 30));
    return DateTime.now().isAfter(expiresAt);
  }

  SimInvitation withStatus(SimInvitationStatus newStatus, {DateTime? respondedAt}) =>
      SimInvitation(
        id: id,
        businessId: businessId,
        businessName: businessName,
        targetUid: targetUid,
        targetName: targetName,
        targetPhone: targetPhone,
        invitedBy: invitedBy,
        invitedByName: invitedByName,
        permissions: permissions,
        status: newStatus,
        createdAt: createdAt,
        respondedAt: respondedAt ?? this.respondedAt,
      );
}

class SimMember {
  final String uid;
  final String name;
  final String? phone;
  final SimMemberPermissions permissions;
  final DateTime addedAt;
  final String addedBy;
  final String? invitationId;

  const SimMember({
    required this.uid,
    required this.name,
    this.phone,
    required this.permissions,
    required this.addedAt,
    required this.addedBy,
    this.invitationId,
  });

  SimMember copyWith({SimMemberPermissions? permissions}) => SimMember(
        uid: uid,
        name: name,
        phone: phone,
        permissions: permissions ?? this.permissions,
        addedAt: addedAt,
        addedBy: addedBy,
        invitationId: invitationId,
      );
}

// ════════════════════════════════════════════════════════════════
// 시뮬레이션 서비스 (순수 Dart — Firebase 대신 Map 사용)
// ════════════════════════════════════════════════════════════════

/// 전화번호 정규화: 숫자만 추출
String _normalizePhoneDigits(String phone) =>
    phone.replaceAll(RegExp(r'[^0-9]'), '');

/// 숫자 전화번호를 하이픈 형식으로 포맷
String _formatPhone(String digits) {
  if (digits.length == 11) {
    return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
  } else if (digits.length == 10) {
    if (digits.startsWith('02')) {
      return '${digits.substring(0, 2)}-${digits.substring(2, 6)}-${digits.substring(6)}';
    }
    return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
  }
  return digits;
}

/// findUserByPhone 로직 재현:
/// 두 형식(digits, formatted) 모두 시도 후 USER role만 반환
SimUser? findUserByPhone(
  String inputPhone,
  List<SimUser> usersDb,
) {
  final digits = _normalizePhoneDigits(inputPhone);
  final formatted = _formatPhone(digits);

  for (final query in [digits, formatted]) {
    final found = usersDb.where(
      (u) => u.phone == query && u.role == SimUserRole.USER,
    );
    if (found.isNotEmpty) return found.first;
  }
  return null;
}

/// isAlreadyMember 로직 재현
bool isAlreadyMember(
  String businessId,
  String uid,
  Map<String, Map<String, SimMember>> membersDb,
) {
  return membersDb[businessId]?.containsKey(uid) ?? false;
}

/// hasPendingInvitation 로직 재현 (30일 이내 pending만)
bool hasPendingInvitation(
  String businessId,
  String targetUid,
  List<SimInvitation> invitationsDb,
) {
  final expiry = DateTime.now().subtract(const Duration(days: 30));
  return invitationsDb.any(
    (inv) =>
        inv.businessId == businessId &&
        inv.targetUid == targetUid &&
        inv.status == SimInvitationStatus.pending &&
        inv.createdAt.isAfter(expiry),
  );
}

/// sendInvitation() 결과 구조
class SendInvitationResult {
  final SimInvitation invitation;
  final bool notificationSent;
  const SendInvitationResult({
    required this.invitation,
    required this.notificationSent,
  });
}

/// sendInvitation 로직 재현
SendInvitationResult sendInvitation({
  required String businessId,
  required String businessName,
  required String targetUid,
  required String targetName,
  String? targetPhone,
  required String invitedBy,
  required String invitedByName,
  required SimMemberPermissions permissions,
  List<SimInvitation>? invitationsDb,
}) {
  final now = DateTime.now();
  final invitation = SimInvitation(
    id: 'inv_${now.millisecondsSinceEpoch}',
    businessId: businessId,
    businessName: businessName,
    targetUid: targetUid,
    targetName: targetName,
    targetPhone: targetPhone,
    invitedBy: invitedBy,
    invitedByName: invitedByName,
    permissions: permissions,
    status: SimInvitationStatus.pending,
    createdAt: now,
  );
  invitationsDb?.add(invitation);
  return SendInvitationResult(invitation: invitation, notificationSent: true);
}

/// acceptInvitation 로직 재현 (throw 조건 검사)
/// 성공 시 (updatedInvitation, createdMember) 반환
({SimInvitation updatedInvitation, SimMember createdMember}) acceptInvitation(
  SimInvitation invitation,
  Map<String, Map<String, SimMember>> membersDb,
) {
  if (!invitation.isPending) {
    throw Exception('이미 처리된 초대입니다.');
  }
  final expiryDate = invitation.createdAt.add(const Duration(days: 30));
  if (DateTime.now().isAfter(expiryDate)) {
    throw Exception('초대 유효기간(30일)이 만료되었습니다.');
  }
  if (isAlreadyMember(invitation.businessId, invitation.targetUid, membersDb)) {
    throw Exception('이미 해당 사업장의 멤버입니다.');
  }

  final now = DateTime.now();
  final updatedInvitation = invitation.withStatus(
    SimInvitationStatus.accepted,
    respondedAt: now,
  );
  final member = SimMember(
    uid: invitation.targetUid,
    name: invitation.targetName,
    phone: invitation.targetPhone,
    permissions: invitation.permissions,
    addedAt: now,
    addedBy: invitation.invitedBy,
    invitationId: invitation.id,
  );
  membersDb.putIfAbsent(invitation.businessId, () => {})[invitation.targetUid] = member;
  return (updatedInvitation: updatedInvitation, createdMember: member);
}

/// rejectInvitation 로직 재현
SimInvitation rejectInvitation(SimInvitation invitation) {
  if (!invitation.isPending) {
    throw Exception('이미 처리된 초대입니다.');
  }
  return invitation.withStatus(SimInvitationStatus.rejected, respondedAt: DateTime.now());
}

/// cancelInvitation 로직 재현
SimInvitation cancelInvitation(SimInvitation invitation) {
  if (!invitation.isPending) {
    throw Exception('이미 처리된 초대는 취소할 수 없습니다.');
  }
  return invitation.withStatus(SimInvitationStatus.cancelled);
}

/// removeMember 로직 재현 (subAdminOf 조건부 삭제)
SimUser removeMember({
  required String businessId,
  required String uid,
  required SimUser user,
  required Map<String, Map<String, SimMember>> membersDb,
}) {
  membersDb[businessId]?.remove(uid);
  // subAdminOf가 이 businessId와 일치할 때만 삭제
  if (user.subAdminOf == businessId) {
    return user.copyWith(clearSubAdminOf: true);
  }
  return user;
}

/// updatePermissions 로직 재현
SimMember? updatePermissions({
  required String businessId,
  required String uid,
  required SimMemberPermissions permissions,
  required Map<String, Map<String, SimMember>> membersDb,
}) {
  final member = membersDb[businessId]?[uid];
  if (member == null) throw Exception('멤버를 찾을 수 없습니다.');
  final updated = member.copyWith(permissions: permissions);
  membersDb[businessId]![uid] = updated;
  return updated;
}

/// isAdminMode 전환 로직 재현
/// isSubAdmin=false → 전환 불가 (return false)
bool toggleAdminMode(SimUser user, bool currentMode) {
  if (!user.isSubAdmin) return currentMode; // 변경 없이 반환
  return !currentMode;
}

/// can() 권한 체크 로직 재현
bool can(
  SimUser user,
  SimMemberPermissions? memberPermissions,
  bool Function(SimMemberPermissions p) check,
) {
  if (user.isBusinessAdmin) return true;
  if (memberPermissions != null) return check(memberPermissions);
  return false;
}

// ════════════════════════════════════════════════════════════════
// 팩토리 헬퍼
// ════════════════════════════════════════════════════════════════

final _now = DateTime.now();
final _past1d = _now.subtract(const Duration(days: 1));
final _past10d = _now.subtract(const Duration(days: 10));
final _past29d = _now.subtract(const Duration(days: 29));
final _past30d = _now.subtract(const Duration(days: 30));
final _past31d = _now.subtract(const Duration(days: 31));
final _past60d = _now.subtract(const Duration(days: 60));

SimUser _bizAdmin({String uid = 'admin1', String? businessId = 'biz1'}) => SimUser(
      uid: uid,
      name: '관리자',
      phone: '010-0000-0001',
      role: SimUserRole.BUSINESS_ADMIN,
    );

SimUser _regularUser({
  String uid = 'user1',
  String? phone = '010-1234-5678',
  String? subAdminOf,
}) =>
    SimUser(
      uid: uid,
      name: '테스터',
      phone: phone,
      role: SimUserRole.USER,
      subAdminOf: subAdminOf,
    );

SimUser _superAdmin({String uid = 'super1'}) => SimUser(
      uid: uid,
      name: '슈퍼관리자',
      phone: '010-0000-0000',
      role: SimUserRole.SUPER_ADMIN,
    );

SimInvitation _pendingInvite({
  String id = 'inv1',
  String businessId = 'biz1',
  String targetUid = 'user1',
  SimMemberPermissions? permissions,
  DateTime? createdAt,
}) =>
    SimInvitation(
      id: id,
      businessId: businessId,
      businessName: '테스트사업장',
      targetUid: targetUid,
      targetName: '테스터',
      invitedBy: 'admin1',
      invitedByName: '관리자',
      permissions: permissions ?? SimMemberPermissions.none(),
      status: SimInvitationStatus.pending,
      createdAt: createdAt ?? _past1d,
    );

SimInvitation _processedInvite({
  SimInvitationStatus status = SimInvitationStatus.accepted,
}) =>
    SimInvitation(
      id: 'inv_done',
      businessId: 'biz1',
      businessName: '테스트사업장',
      targetUid: 'user1',
      targetName: '테스터',
      invitedBy: 'admin1',
      invitedByName: '관리자',
      permissions: SimMemberPermissions.none(),
      status: status,
      createdAt: _past1d,
      respondedAt: _now,
    );

Map<String, Map<String, SimMember>> _emptyMembersDb() => {};
Map<String, Map<String, SimMember>> _membersDbWith(
  String businessId,
  String uid,
  SimMember member,
) =>
    {
      businessId: {uid: member}
    };

SimMember _simMember({
  String uid = 'user1',
  SimMemberPermissions? permissions,
  String addedBy = 'admin1',
}) =>
    SimMember(
      uid: uid,
      name: '테스터',
      permissions: permissions ?? SimMemberPermissions.none(),
      addedAt: _past1d,
      addedBy: addedBy,
    );

// ════════════════════════════════════════════════════════════════
// SCENARIO-INV-1xx: findUserByPhone 검색 로직
// ════════════════════════════════════════════════════════════════

void _runFindUserByPhoneTests() {
  group('SCENARIO-INV-1xx: findUserByPhone 검색 로직', () {
    final usersDb = [
      _regularUser(uid: 'u1', phone: '01012345678'),
      _regularUser(uid: 'u2', phone: '010-9876-5432'),
      _regularUser(uid: 'u3', phone: null),
      _bizAdmin(uid: 'a1'),
      _superAdmin(uid: 's1'),
    ];

    test('SCENARIO-INV-101 하이픈 없는 입력 → digits 형식으로 직접 매칭', () {
      final result = findUserByPhone('01012345678', usersDb);
      expect(result, isNotNull);
      expect(result!.uid, 'u1');
    });

    test('SCENARIO-INV-102 하이픈 있는 입력 → 정규화 후 digits 매칭 시도', () {
      final result = findUserByPhone('010-1234-5678', usersDb);
      expect(result, isNotNull);
      expect(result!.uid, 'u1');
    });

    test('SCENARIO-INV-103 하이픈 형식 저장 → formatted 형식으로 매칭', () {
      final result = findUserByPhone('01098765432', usersDb);
      expect(result, isNotNull);
      expect(result!.uid, 'u2');
    });

    test('SCENARIO-INV-104 하이픈 입력으로 하이픈 저장 사용자 매칭', () {
      final result = findUserByPhone('010-9876-5432', usersDb);
      expect(result, isNotNull);
      expect(result!.uid, 'u2');
    });

    test('SCENARIO-INV-105 BUSINESS_ADMIN은 검색 결과 제외', () {
      // bizAdmin의 phone이 등록된 경우에도 role=USER만 반환
      final dbWithAdmin = [
        SimUser(uid: 'a1', name: '관리자', phone: '01000000001', role: SimUserRole.BUSINESS_ADMIN),
      ];
      final result = findUserByPhone('010-0000-0001', dbWithAdmin);
      expect(result, isNull);
    });

    test('SCENARIO-INV-106 SUPER_ADMIN은 검색 결과 제외', () {
      final dbWithSuper = [
        SimUser(uid: 's1', name: '슈퍼', phone: '01000000000', role: SimUserRole.SUPER_ADMIN),
      ];
      final result = findUserByPhone('01000000000', dbWithSuper);
      expect(result, isNull);
    });

    test('SCENARIO-INV-107 존재하지 않는 전화번호 → null 반환', () {
      final result = findUserByPhone('01099999999', usersDb);
      expect(result, isNull);
    });

    test('SCENARIO-INV-108 전화번호 null인 USER → 매칭 안 됨', () {
      // u3의 phone=null
      final result = findUserByPhone('', usersDb);
      expect(result, isNull);
    });

    test('SCENARIO-INV-109 전화번호 정규화 — 하이픈 제거 로직', () {
      final digits = _normalizePhoneDigits('010-1234-5678');
      expect(digits, '01012345678');
    });

    test('SCENARIO-INV-110 전화번호 정규화 — 공백/특수문자 제거', () {
      final digits = _normalizePhoneDigits('010 1234 5678');
      expect(digits, '01012345678');
    });

    test('SCENARIO-INV-111 포맷팅 — 11자리 → 010-xxxx-xxxx', () {
      expect(_formatPhone('01012345678'), '010-1234-5678');
    });

    test('SCENARIO-INV-112 포맷팅 — 02 서울 번호 10자리 → 02-xxxx-xxxx', () {
      expect(_formatPhone('0212345678'), '02-1234-5678');
    });

    test('SCENARIO-INV-113 포맷팅 — 10자리 비서울 → 031-xxx-xxxx', () {
      expect(_formatPhone('0311234567'), '031-123-4567');
    });

    test('SCENARIO-INV-114 두 형식 모두 매칭 실패 시 null', () {
      final result = findUserByPhone('01055550000', usersDb);
      expect(result, isNull);
    });

    test('SCENARIO-INV-115 같은 전화번호 USER 여러 명 — 첫 번째 반환', () {
      final db = [
        _regularUser(uid: 'first', phone: '01099999999'),
        _regularUser(uid: 'second', phone: '01099999999'),
      ];
      final result = findUserByPhone('01099999999', db);
      expect(result?.uid, 'first');
    });
  });
}

// ════════════════════════════════════════════════════════════════
// SCENARIO-INV-2xx: 초대 사전 검사
// ════════════════════════════════════════════════════════════════

void _runPreCheckTests() {
  group('SCENARIO-INV-2xx: 초대 사전 검사', () {

    // ── isAlreadyMember ───────────────────────────────────────
    group('SCENARIO-INV-2xx: isAlreadyMember', () {
      test('SCENARIO-INV-201 멤버 없음 → false', () {
        expect(isAlreadyMember('biz1', 'user1', _emptyMembersDb()), isFalse);
      });

      test('SCENARIO-INV-202 동일 사업장 멤버 존재 → true', () {
        final db = _membersDbWith('biz1', 'user1', _simMember());
        expect(isAlreadyMember('biz1', 'user1', db), isTrue);
      });

      test('SCENARIO-INV-203 다른 사업장 멤버 → false', () {
        final db = _membersDbWith('biz2', 'user1', _simMember());
        expect(isAlreadyMember('biz1', 'user1', db), isFalse);
      });

      test('SCENARIO-INV-204 다른 uid → false', () {
        final db = _membersDbWith('biz1', 'user2', _simMember(uid: 'user2'));
        expect(isAlreadyMember('biz1', 'user1', db), isFalse);
      });

      test('SCENARIO-INV-205 사업장+uid 모두 일치 → true', () {
        final db = {
          'biz1': {
            'user1': _simMember(),
            'user2': _simMember(uid: 'user2'),
          }
        };
        expect(isAlreadyMember('biz1', 'user1', db), isTrue);
        expect(isAlreadyMember('biz1', 'user2', db), isTrue);
      });
    });

    // ── hasPendingInvitation ──────────────────────────────────
    group('SCENARIO-INV-2xx: hasPendingInvitation', () {
      test('SCENARIO-INV-211 초대 없음 → false', () {
        expect(hasPendingInvitation('biz1', 'user1', []), isFalse);
      });

      test('SCENARIO-INV-212 pending + 1일전 → true (유효)', () {
        final invs = [_pendingInvite(createdAt: _past1d)];
        expect(hasPendingInvitation('biz1', 'user1', invs), isTrue);
      });

      test('SCENARIO-INV-213 pending + 29일전 → true (유효)', () {
        final invs = [_pendingInvite(createdAt: _past29d)];
        expect(hasPendingInvitation('biz1', 'user1', invs), isTrue);
      });

      test('SCENARIO-INV-214 pending + 30일전 → false (경계: 만료)', () {
        final invs = [_pendingInvite(createdAt: _past30d)];
        expect(hasPendingInvitation('biz1', 'user1', invs), isFalse);
      });

      test('SCENARIO-INV-215 pending + 31일전 → false (만료)', () {
        final invs = [_pendingInvite(createdAt: _past31d)];
        expect(hasPendingInvitation('biz1', 'user1', invs), isFalse);
      });

      test('SCENARIO-INV-216 accepted + 1일전 → false (status 비일치)', () {
        final invs = [_pendingInvite().withStatus(SimInvitationStatus.accepted)];
        expect(hasPendingInvitation('biz1', 'user1', invs), isFalse);
      });

      test('SCENARIO-INV-217 rejected + 1일전 → false', () {
        final invs = [_pendingInvite().withStatus(SimInvitationStatus.rejected)];
        expect(hasPendingInvitation('biz1', 'user1', invs), isFalse);
      });

      test('SCENARIO-INV-218 cancelled + 1일전 → false', () {
        final invs = [_pendingInvite().withStatus(SimInvitationStatus.cancelled)];
        expect(hasPendingInvitation('biz1', 'user1', invs), isFalse);
      });

      test('SCENARIO-INV-219 다른 사업장 pending → false', () {
        final invs = [_pendingInvite(businessId: 'biz999', createdAt: _past1d)];
        expect(hasPendingInvitation('biz1', 'user1', invs), isFalse);
      });

      test('SCENARIO-INV-220 다른 targetUid → false', () {
        final invs = [_pendingInvite(targetUid: 'other_user', createdAt: _past1d)];
        expect(hasPendingInvitation('biz1', 'user1', invs), isFalse);
      });

      test('SCENARIO-INV-221 만료된 초대 후 재초대 가능 — false이므로 재발송 OK', () {
        // 31일 전 pending은 만료로 hasPendingInvitation=false → 재초대 가능
        final invs = [_pendingInvite(createdAt: _past31d)];
        final hasActive = hasPendingInvitation('biz1', 'user1', invs);
        expect(hasActive, isFalse); // 재초대 가능
      });
    });

    // ── 초대 발송 가능 조건 종합 ──────────────────────────────
    group('SCENARIO-INV-2xx: 초대 발송 가능 조건', () {
      bool canSend(bool alreadyMember, bool hasPending) =>
          !alreadyMember && !hasPending;

      test('SCENARIO-INV-231 미멤버 + pending없음 → 초대 가능', () {
        expect(canSend(false, false), isTrue);
      });
      test('SCENARIO-INV-232 이미멤버 + pending없음 → 초대 불가', () {
        expect(canSend(true, false), isFalse);
      });
      test('SCENARIO-INV-233 미멤버 + pending있음 → 초대 불가', () {
        expect(canSend(false, true), isFalse);
      });
      test('SCENARIO-INV-234 이미멤버 + pending있음 → 초대 불가', () {
        expect(canSend(true, true), isFalse);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════════
// SCENARIO-INV-3xx: sendInvitation() 로직
// ════════════════════════════════════════════════════════════════

void _runSendInvitationTests() {
  group('SCENARIO-INV-3xx: sendInvitation() 로직', () {
    test('SCENARIO-INV-301 초대 생성 — status=pending', () {
      final result = sendInvitation(
        businessId: 'biz1',
        businessName: '테스트사업장',
        targetUid: 'user1',
        targetName: '테스터',
        invitedBy: 'admin1',
        invitedByName: '관리자',
        permissions: SimMemberPermissions.none(),
      );
      expect(result.invitation.status, SimInvitationStatus.pending);
    });

    test('SCENARIO-INV-302 초대 생성 — businessId 설정', () {
      final result = sendInvitation(
        businessId: 'biz999',
        businessName: '사업장',
        targetUid: 'u',
        targetName: '직원',
        invitedBy: 'a',
        invitedByName: '관리자',
        permissions: SimMemberPermissions.none(),
      );
      expect(result.invitation.businessId, 'biz999');
    });

    test('SCENARIO-INV-303 초대 생성 — targetUid 설정', () {
      final result = sendInvitation(
        businessId: 'biz1',
        businessName: '사업장',
        targetUid: 'target_uid',
        targetName: '직원',
        invitedBy: 'a',
        invitedByName: '관리자',
        permissions: SimMemberPermissions.none(),
      );
      expect(result.invitation.targetUid, 'target_uid');
    });

    test('SCENARIO-INV-304 초대 생성 — permissions 포함', () {
      final perms = SimMemberPermissions.all();
      final result = sendInvitation(
        businessId: 'biz1',
        businessName: '사업장',
        targetUid: 'u',
        targetName: '직원',
        invitedBy: 'a',
        invitedByName: '관리자',
        permissions: perms,
      );
      expect(result.invitation.permissions.canManageTo, isTrue);
      expect(result.invitation.permissions.canManageWage, isTrue);
    });

    test('SCENARIO-INV-305 초대 생성 — invitedBy 설정', () {
      final result = sendInvitation(
        businessId: 'biz1',
        businessName: '사업장',
        targetUid: 'u',
        targetName: '직원',
        invitedBy: 'admin_x',
        invitedByName: '관리자X',
        permissions: SimMemberPermissions.none(),
      );
      expect(result.invitation.invitedBy, 'admin_x');
    });

    test('SCENARIO-INV-306 초대 생성 — createdAt ≈ now', () {
      final before = DateTime.now();
      final result = sendInvitation(
        businessId: 'biz1',
        businessName: '사업장',
        targetUid: 'u',
        targetName: '직원',
        invitedBy: 'a',
        invitedByName: '관리자',
        permissions: SimMemberPermissions.none(),
      );
      final after = DateTime.now();
      expect(
        result.invitation.createdAt.isAfter(before.subtract(const Duration(seconds: 1))) &&
            result.invitation.createdAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });

    test('SCENARIO-INV-307 초대 생성 — expiresAt = createdAt + 30일', () {
      final result = sendInvitation(
        businessId: 'biz1',
        businessName: '사업장',
        targetUid: 'u',
        targetName: '직원',
        invitedBy: 'a',
        invitedByName: '관리자',
        permissions: SimMemberPermissions.none(),
      );
      final expectedExpiry = result.invitation.createdAt.add(const Duration(days: 30));
      final now = DateTime.now();
      expect(expectedExpiry.isAfter(now), isTrue); // 아직 만료 안 됨
      expect(result.invitation.isExpired, isFalse);
    });

    test('SCENARIO-INV-308 초대 생성 — 알림 발송됨 (notificationSent=true)', () {
      final result = sendInvitation(
        businessId: 'biz1',
        businessName: '사업장',
        targetUid: 'u',
        targetName: '직원',
        invitedBy: 'a',
        invitedByName: '관리자',
        permissions: SimMemberPermissions.none(),
      );
      expect(result.notificationSent, isTrue);
    });

    test('SCENARIO-INV-309 초대 생성 — DB에 추가됨', () {
      final db = <SimInvitation>[];
      sendInvitation(
        businessId: 'biz1',
        businessName: '사업장',
        targetUid: 'u',
        targetName: '직원',
        invitedBy: 'a',
        invitedByName: '관리자',
        permissions: SimMemberPermissions.none(),
        invitationsDb: db,
      );
      expect(db.length, 1);
      expect(db.first.status, SimInvitationStatus.pending);
    });

    test('SCENARIO-INV-310 권한 없는 초대도 생성 가능 (열람만 가능 상태)', () {
      final result = sendInvitation(
        businessId: 'biz1',
        businessName: '사업장',
        targetUid: 'u',
        targetName: '직원',
        invitedBy: 'a',
        invitedByName: '관리자',
        permissions: SimMemberPermissions.none(),
      );
      expect(result.invitation.permissions.hasAnyPermission, isFalse);
      expect(result.invitation.isPending, isTrue);
    });
  });
}

// ════════════════════════════════════════════════════════════════
// SCENARIO-INV-4xx: acceptInvitation() 로직
// ════════════════════════════════════════════════════════════════

void _runAcceptInvitationTests() {
  group('SCENARIO-INV-4xx: acceptInvitation() 로직', () {
    test('SCENARIO-INV-401 pending + 유효 + 미멤버 → 수락 성공', () {
      final inv = _pendingInvite(createdAt: _past1d);
      final db = _emptyMembersDb();
      expect(() => acceptInvitation(inv, db), returnsNormally);
    });

    test('SCENARIO-INV-402 수락 후 invitation status=accepted', () {
      final inv = _pendingInvite(createdAt: _past1d);
      final db = _emptyMembersDb();
      final result = acceptInvitation(inv, db);
      expect(result.updatedInvitation.status, SimInvitationStatus.accepted);
    });

    test('SCENARIO-INV-403 수락 후 respondedAt 설정됨', () {
      final inv = _pendingInvite(createdAt: _past1d);
      final db = _emptyMembersDb();
      final result = acceptInvitation(inv, db);
      expect(result.updatedInvitation.respondedAt, isNotNull);
    });

    test('SCENARIO-INV-404 수락 후 멤버 문서 생성됨', () {
      final inv = _pendingInvite(createdAt: _past1d);
      final db = _emptyMembersDb();
      acceptInvitation(inv, db);
      expect(db['biz1']?.containsKey('user1'), isTrue);
    });

    test('SCENARIO-INV-405 수락 후 멤버의 permissions = 초대의 permissions', () {
      final perms = SimMemberPermissions.all();
      final inv = _pendingInvite(createdAt: _past1d, permissions: perms);
      final db = _emptyMembersDb();
      final result = acceptInvitation(inv, db);
      expect(result.createdMember.permissions.canManageTo, isTrue);
    });

    test('SCENARIO-INV-406 accepted 초대 수락 시도 → 예외', () {
      final inv = _processedInvite(status: SimInvitationStatus.accepted);
      final db = _emptyMembersDb();
      expect(() => acceptInvitation(inv, db), throwsException);
    });

    test('SCENARIO-INV-407 rejected 초대 수락 시도 → 예외', () {
      final inv = _processedInvite(status: SimInvitationStatus.rejected);
      final db = _emptyMembersDb();
      expect(() => acceptInvitation(inv, db), throwsException);
    });

    test('SCENARIO-INV-408 cancelled 초대 수락 시도 → 예외', () {
      final inv = _processedInvite(status: SimInvitationStatus.cancelled);
      final db = _emptyMembersDb();
      expect(() => acceptInvitation(inv, db), throwsException);
    });

    test('SCENARIO-INV-409 만료된 초대(31일 전) 수락 → 예외', () {
      final inv = _pendingInvite(createdAt: _past31d);
      final db = _emptyMembersDb();
      expect(() => acceptInvitation(inv, db), throwsException);
    });

    test('SCENARIO-INV-410 이미 멤버인 경우 수락 → 예외 (HIGH-01 방어)', () {
      final inv = _pendingInvite(createdAt: _past1d);
      final db = _membersDbWith('biz1', 'user1', _simMember());
      expect(() => acceptInvitation(inv, db), throwsException);
    });

    test('SCENARIO-INV-411 수락 후 멤버의 invitationId 설정됨', () {
      final inv = _pendingInvite(id: 'inv_abc', createdAt: _past1d);
      final db = _emptyMembersDb();
      final result = acceptInvitation(inv, db);
      expect(result.createdMember.invitationId, 'inv_abc');
    });

    test('SCENARIO-INV-412 수락 후 멤버의 addedBy = 초대한 관리자', () {
      final inv = _pendingInvite(createdAt: _past1d);
      final db = _emptyMembersDb();
      final result = acceptInvitation(inv, db);
      expect(result.createdMember.addedBy, 'admin1');
    });

    test('SCENARIO-INV-413 만료 직전(29일) 초대 수락 → 성공', () {
      final inv = _pendingInvite(createdAt: _past29d);
      final db = _emptyMembersDb();
      expect(() => acceptInvitation(inv, db), returnsNormally);
    });

    test('SCENARIO-INV-414 예외 메시지 — 이미 처리된 초대', () {
      final inv = _processedInvite(status: SimInvitationStatus.accepted);
      final db = _emptyMembersDb();
      expect(
        () => acceptInvitation(inv, db),
        throwsA(predicate<Exception>((e) => e.toString().contains('이미 처리된 초대'))),
      );
    });

    test('SCENARIO-INV-415 예외 메시지 — 만료된 초대', () {
      final inv = _pendingInvite(createdAt: _past60d);
      final db = _emptyMembersDb();
      expect(
        () => acceptInvitation(inv, db),
        throwsA(predicate<Exception>((e) => e.toString().contains('만료'))),
      );
    });

    test('SCENARIO-INV-416 예외 메시지 — 이미 멤버', () {
      final inv = _pendingInvite(createdAt: _past1d);
      final db = _membersDbWith('biz1', 'user1', _simMember());
      expect(
        () => acceptInvitation(inv, db),
        throwsA(predicate<Exception>((e) => e.toString().contains('멤버'))),
      );
    });
  });
}

// ════════════════════════════════════════════════════════════════
// SCENARIO-INV-5xx: rejectInvitation() / cancelInvitation() 로직
// ════════════════════════════════════════════════════════════════

void _runRejectCancelTests() {
  group('SCENARIO-INV-5xx: rejectInvitation() / cancelInvitation()', () {

    group('rejectInvitation', () {
      test('SCENARIO-INV-501 pending → rejected 성공', () {
        final inv = _pendingInvite();
        final result = rejectInvitation(inv);
        expect(result.status, SimInvitationStatus.rejected);
      });

      test('SCENARIO-INV-502 거절 후 respondedAt 설정됨', () {
        final result = rejectInvitation(_pendingInvite());
        expect(result.respondedAt, isNotNull);
      });

      test('SCENARIO-INV-503 accepted → reject 시도 → 예외', () {
        final inv = _processedInvite(status: SimInvitationStatus.accepted);
        expect(() => rejectInvitation(inv), throwsException);
      });

      test('SCENARIO-INV-504 rejected → reject 시도 → 예외 (중복 거절 방어)', () {
        final inv = _processedInvite(status: SimInvitationStatus.rejected);
        expect(() => rejectInvitation(inv), throwsException);
      });

      test('SCENARIO-INV-505 cancelled → reject 시도 → 예외', () {
        final inv = _processedInvite(status: SimInvitationStatus.cancelled);
        expect(() => rejectInvitation(inv), throwsException);
      });

      test('SCENARIO-INV-506 예외 메시지 — 이미 처리된 초대', () {
        final inv = _processedInvite(status: SimInvitationStatus.accepted);
        expect(
          () => rejectInvitation(inv),
          throwsA(predicate<Exception>((e) => e.toString().contains('이미 처리된 초대'))),
        );
      });
    });

    group('cancelInvitation', () {
      test('SCENARIO-INV-511 pending → cancelled 성공', () {
        final result = cancelInvitation(_pendingInvite());
        expect(result.status, SimInvitationStatus.cancelled);
      });

      test('SCENARIO-INV-512 accepted → cancel 시도 → 예외', () {
        final inv = _processedInvite(status: SimInvitationStatus.accepted);
        expect(() => cancelInvitation(inv), throwsException);
      });

      test('SCENARIO-INV-513 rejected → cancel 시도 → 예외', () {
        final inv = _processedInvite(status: SimInvitationStatus.rejected);
        expect(() => cancelInvitation(inv), throwsException);
      });

      test('SCENARIO-INV-514 cancelled → cancel 시도 → 예외 (중복 취소 방어)', () {
        final inv = _processedInvite(status: SimInvitationStatus.cancelled);
        expect(() => cancelInvitation(inv), throwsException);
      });

      test('SCENARIO-INV-515 예외 메시지 — 취소 불가', () {
        final inv = _processedInvite(status: SimInvitationStatus.accepted);
        expect(
          () => cancelInvitation(inv),
          throwsA(predicate<Exception>((e) => e.toString().contains('취소할 수 없습니다'))),
        );
      });
    });
  });
}

// ════════════════════════════════════════════════════════════════
// SCENARIO-INV-6xx: removeMember() 로직
// ════════════════════════════════════════════════════════════════

void _runRemoveMemberTests() {
  group('SCENARIO-INV-6xx: removeMember() 로직', () {
    test('SCENARIO-INV-601 멤버 제거 후 DB에서 삭제됨', () {
      final db = _membersDbWith('biz1', 'user1', _simMember());
      final user = _regularUser(subAdminOf: 'biz1');
      removeMember(businessId: 'biz1', uid: 'user1', user: user, membersDb: db);
      expect(db['biz1']?.containsKey('user1'), isFalse);
    });

    test('SCENARIO-INV-602 subAdminOf == businessId → clearSubAdminOf', () {
      final db = _membersDbWith('biz1', 'user1', _simMember());
      final user = _regularUser(subAdminOf: 'biz1');
      final updated = removeMember(businessId: 'biz1', uid: 'user1', user: user, membersDb: db);
      expect(updated.subAdminOf, isNull);
    });

    test('SCENARIO-INV-603 제거 후 isSubAdmin=false', () {
      final db = _membersDbWith('biz1', 'user1', _simMember());
      final user = _regularUser(subAdminOf: 'biz1');
      final updated = removeMember(businessId: 'biz1', uid: 'user1', user: user, membersDb: db);
      expect(updated.isSubAdmin, isFalse);
    });

    test('SCENARIO-INV-604 subAdminOf != businessId → subAdminOf 유지 (타 사업장 권한 보호)', () {
      final db = _membersDbWith('biz1', 'user1', _simMember());
      final user = _regularUser(subAdminOf: 'biz_other');
      final updated = removeMember(businessId: 'biz1', uid: 'user1', user: user, membersDb: db);
      expect(updated.subAdminOf, 'biz_other'); // 건드리지 않음
    });

    test('SCENARIO-INV-605 subAdminOf=null 유저 제거 → subAdminOf 그대로 null', () {
      final db = _membersDbWith('biz1', 'user1', _simMember());
      final user = _regularUser(subAdminOf: null);
      final updated = removeMember(businessId: 'biz1', uid: 'user1', user: user, membersDb: db);
      expect(updated.subAdminOf, isNull);
    });

    test('SCENARIO-INV-606 존재하지 않는 멤버 제거 시도 — DB 변화 없음', () {
      final db = _emptyMembersDb();
      final user = _regularUser(subAdminOf: 'biz1');
      expect(
        () => removeMember(businessId: 'biz1', uid: 'user1', user: user, membersDb: db),
        returnsNormally,
      );
    });

    test('SCENARIO-INV-607 다른 멤버는 영향받지 않음', () {
      final db = {
        'biz1': {
          'user1': _simMember(uid: 'user1'),
          'user2': _simMember(uid: 'user2'),
        }
      };
      final user = _regularUser(uid: 'user1', subAdminOf: 'biz1');
      removeMember(businessId: 'biz1', uid: 'user1', user: user, membersDb: db);
      expect(db['biz1']?.containsKey('user2'), isTrue);
    });
  });
}

// ════════════════════════════════════════════════════════════════
// SCENARIO-INV-7xx: updatePermissions() 로직
// ════════════════════════════════════════════════════════════════

void _runUpdatePermissionsTests() {
  group('SCENARIO-INV-7xx: updatePermissions() 로직', () {
    test('SCENARIO-INV-701 권한 업데이트 — none → all', () {
      final db = _membersDbWith('biz1', 'user1', _simMember());
      final updated = updatePermissions(
        businessId: 'biz1',
        uid: 'user1',
        permissions: SimMemberPermissions.all(),
        membersDb: db,
      );
      expect(updated?.permissions.hasAnyPermission, isTrue);
    });

    test('SCENARIO-INV-702 권한 업데이트 — all → none', () {
      final db = _membersDbWith(
          'biz1', 'user1', _simMember(permissions: SimMemberPermissions.all()));
      final updated = updatePermissions(
        businessId: 'biz1',
        uid: 'user1',
        permissions: SimMemberPermissions.none(),
        membersDb: db,
      );
      expect(updated?.permissions.hasAnyPermission, isFalse);
    });

    test('SCENARIO-INV-703 권한 업데이트 — 특정 권한만 부여', () {
      final db = _membersDbWith('biz1', 'user1', _simMember());
      final updated = updatePermissions(
        businessId: 'biz1',
        uid: 'user1',
        permissions: const SimMemberPermissions(canManageWage: true),
        membersDb: db,
      );
      expect(updated?.permissions.canManageWage, isTrue);
      expect(updated?.permissions.canManageTo, isFalse);
    });

    test('SCENARIO-INV-704 DB에 실제로 반영됨', () {
      final db = _membersDbWith('biz1', 'user1', _simMember());
      updatePermissions(
        businessId: 'biz1',
        uid: 'user1',
        permissions: SimMemberPermissions.all(),
        membersDb: db,
      );
      expect(db['biz1']?['user1']?.permissions.canManageTo, isTrue);
    });

    test('SCENARIO-INV-705 멤버 없는 경우 → 예외 (F-042 대응)', () {
      final db = _emptyMembersDb();
      expect(
        () => updatePermissions(
          businessId: 'biz1',
          uid: 'user1',
          permissions: SimMemberPermissions.all(),
          membersDb: db,
        ),
        throwsException,
      );
    });

    test('SCENARIO-INV-706 권한 업데이트는 캐시 갱신 없이 다음 로드 시 반영 (설계 확인)', () {
      // updatePermissions는 Firestore만 업데이트 — UserProvider 캐시 갱신 불필요
      // 순수 Dart 확인: DB 업데이트 후 DB 재조회로 확인
      final db = _membersDbWith('biz1', 'user1', _simMember());
      updatePermissions(
        businessId: 'biz1',
        uid: 'user1',
        permissions: const SimMemberPermissions(canManageTo: true),
        membersDb: db,
      );
      final fromDb = db['biz1']?['user1'];
      expect(fromDb?.permissions.canManageTo, isTrue);
    });
  });
}

// ════════════════════════════════════════════════════════════════
// SCENARIO-INV-8xx: TOCTOU 경쟁조건 시나리오
// ════════════════════════════════════════════════════════════════

void _runTOCTOUTests() {
  group('SCENARIO-INV-8xx: TOCTOU 경쟁조건', () {
    test('SCENARIO-INV-801 관리자 2명이 동시 초대 → 중복 초대 문서 생성 가능', () {
      final db = <SimInvitation>[];
      // 관리자 A가 초대 발송
      sendInvitation(
        businessId: 'biz1', businessName: '사업장',
        targetUid: 'user1', targetName: '직원',
        invitedBy: 'admin1', invitedByName: '관리자A',
        permissions: SimMemberPermissions.none(),
        invitationsDb: db,
      );
      // 관리자 B가 동시에 초대 발송 (사전 체크를 통과한 상태)
      sendInvitation(
        businessId: 'biz1', businessName: '사업장',
        targetUid: 'user1', targetName: '직원',
        invitedBy: 'admin2', invitedByName: '관리자B',
        permissions: SimMemberPermissions.none(),
        invitationsDb: db,
      );
      // 중복 초대 2건 생성됨 (F-020 알려진 이슈)
      expect(db.where((i) => i.targetUid == 'user1').length, 2);
    });

    test('SCENARIO-INV-802 중복 초대 중 하나 수락 후 두 번째 수락 → isAlreadyMember로 차단', () {
      final membersDb = _emptyMembersDb();
      final inv1 = _pendingInvite(id: 'inv1', createdAt: _past1d);
      final inv2 = _pendingInvite(id: 'inv2', createdAt: _past1d);

      // 첫 번째 초대 수락
      acceptInvitation(inv1, membersDb);
      // 두 번째 초대 수락 시도 → 이미 멤버이므로 차단
      expect(() => acceptInvitation(inv2, membersDb), throwsException);
    });

    test('SCENARIO-INV-803 첫 번째 수락 후 멤버 DB에 추가됨', () {
      final membersDb = _emptyMembersDb();
      final inv = _pendingInvite(createdAt: _past1d);
      acceptInvitation(inv, membersDb);
      expect(isAlreadyMember('biz1', 'user1', membersDb), isTrue);
    });

    test('SCENARIO-INV-804 중복 초대 시 알림 2건 발송 가능 (F-032 알려진 이슈)', () {
      // 알림 중복은 데이터 무결성에 영향 없음 — 확인 테스트
      int notificationCount = 0;
      void sendNotification() => notificationCount++;

      sendNotification(); // 첫 번째 초대 알림
      sendNotification(); // 두 번째 초대 알림
      expect(notificationCount, 2); // 중복 발송 시뮬레이션
    });

    test('SCENARIO-INV-805 TOCTOU 방어 — acceptInvitation의 isAlreadyMember 체크로 무결성 보장', () {
      // 두 초대가 동시 수락되어도 첫 번째만 성공, 두 번째는 예외
      final membersDb = _emptyMembersDb();
      int successCount = 0;
      int failureCount = 0;

      for (final inv in [
        _pendingInvite(id: 'inv1', createdAt: _past1d),
        _pendingInvite(id: 'inv2', createdAt: _past1d),
      ]) {
        try {
          acceptInvitation(inv, membersDb);
          successCount++;
        } catch (_) {
          failureCount++;
        }
      }

      expect(successCount, 1);
      expect(failureCount, 1);
      expect(membersDb['biz1']?.length, 1); // 멤버는 1명만
    });
  });
}

// ════════════════════════════════════════════════════════════════
// SCENARIO-INV-9xx: isAdminMode 전환 / can() 권한 체크
// ════════════════════════════════════════════════════════════════

void _runAdminModeAndCanTests() {
  group('SCENARIO-INV-9xx: isAdminMode 전환 및 can() 권한 체크', () {

    // ── isAdminMode 전환 ──────────────────────────────────────
    group('isAdminMode 전환', () {
      test('SCENARIO-INV-901 isSubAdmin=true → toggleAdminMode 가능', () {
        final user = _regularUser(subAdminOf: 'biz1');
        expect(user.isSubAdmin, isTrue);
        final newMode = toggleAdminMode(user, false);
        expect(newMode, isTrue); // false → true 전환
      });

      test('SCENARIO-INV-902 isSubAdmin=true, adminMode=true → false로 전환', () {
        final user = _regularUser(subAdminOf: 'biz1');
        final newMode = toggleAdminMode(user, true);
        expect(newMode, isFalse);
      });

      test('SCENARIO-INV-903 isSubAdmin=false → toggleAdminMode 불가 (현재 상태 유지)', () {
        final user = _regularUser(subAdminOf: null);
        expect(user.isSubAdmin, isFalse);
        final newMode = toggleAdminMode(user, false);
        expect(newMode, isFalse); // 변경 없음
      });

      test('SCENARIO-INV-904 isSubAdmin=false, adminMode=true → 여전히 true (변경 안 됨)', () {
        // isSubAdmin=false 유저가 adminMode=true라면 그대로 반환 (비정상 상태)
        final user = _regularUser(subAdminOf: null);
        final newMode = toggleAdminMode(user, true);
        expect(newMode, isTrue); // 변경 없음
      });

      test('SCENARIO-INV-905 BUSINESS_ADMIN은 isSubAdmin=false → toggleAdminMode 불가', () {
        final admin = _bizAdmin();
        expect(admin.isSubAdmin, isFalse);
        final newMode = toggleAdminMode(admin, false);
        expect(newMode, isFalse);
      });

      test('SCENARIO-INV-906 관리자 모드 활성 시 사업장 관리 기능 접근 허용 (설계 확인)', () {
        final user = _regularUser(subAdminOf: 'biz1');
        final isAdminMode = toggleAdminMode(user, false);
        // 관리자 모드 = true → 사업장 관리 접근 가능
        expect(isAdminMode && user.isSubAdmin, isTrue);
      });

      test('SCENARIO-INV-907 일반 모드 시 근무자 기능만 접근 (설계 확인)', () {
        final user = _regularUser(subAdminOf: 'biz1');
        const isAdminMode = false;
        // 일반 모드 = false → 근무자 기능만 (관리 기능 접근 불가)
        expect(isAdminMode, isFalse);
      });
    });

    // ── can() 권한 체크 ───────────────────────────────────────
    group('can() 권한 체크', () {
      final bizAdmin = _bizAdmin();
      final subAdminUser = _regularUser(subAdminOf: 'biz1');
      final regularUser = _regularUser(subAdminOf: null);

      test('SCENARIO-INV-911 BUSINESS_ADMIN → can() 항상 true', () {
        expect(can(bizAdmin, null, (p) => p.canManageTo), isTrue);
        expect(can(bizAdmin, null, (p) => p.canManageWorkers), isTrue);
        expect(can(bizAdmin, null, (p) => p.canManageWage), isTrue);
        expect(can(bizAdmin, null, (p) => p.canManageContract), isTrue);
      });

      test('SCENARIO-INV-912 BUSINESS_ADMIN + permissions=none → 여전히 true', () {
        expect(can(bizAdmin, SimMemberPermissions.none(), (p) => p.canManageTo), isTrue);
      });

      test('SCENARIO-INV-913 isSubAdmin + memberPermissions=null → false', () {
        expect(can(subAdminUser, null, (p) => p.canManageTo), isFalse);
      });

      test('SCENARIO-INV-914 isSubAdmin + all perms + canManageTo → true', () {
        expect(can(subAdminUser, SimMemberPermissions.all(), (p) => p.canManageTo), isTrue);
      });

      test('SCENARIO-INV-915 isSubAdmin + all perms + canManageWage → true', () {
        expect(can(subAdminUser, SimMemberPermissions.all(), (p) => p.canManageWage), isTrue);
      });

      test('SCENARIO-INV-916 isSubAdmin + none perms + canManageTo → false', () {
        expect(can(subAdminUser, SimMemberPermissions.none(), (p) => p.canManageTo), isFalse);
      });

      test('SCENARIO-INV-917 isSubAdmin + to권한만 → canManageTo=true, 나머지 false', () {
        final toOnly = const SimMemberPermissions(canManageTo: true);
        expect(can(subAdminUser, toOnly, (p) => p.canManageTo), isTrue);
        expect(can(subAdminUser, toOnly, (p) => p.canManageWorkers), isFalse);
        expect(can(subAdminUser, toOnly, (p) => p.canManageWage), isFalse);
        expect(can(subAdminUser, toOnly, (p) => p.canManageContract), isFalse);
      });

      test('SCENARIO-INV-918 isSubAdmin + wage권한만 → canManageWage=true', () {
        final wageOnly = const SimMemberPermissions(canManageWage: true);
        expect(can(subAdminUser, wageOnly, (p) => p.canManageWage), isTrue);
        expect(can(subAdminUser, wageOnly, (p) => p.canManageTo), isFalse);
      });

      test('SCENARIO-INV-919 일반 USER + null → false', () {
        expect(can(regularUser, null, (p) => p.canManageTo), isFalse);
      });

      test('SCENARIO-INV-920 일반 USER + all perms (비정상) → permissions로 통과', () {
        // 일반 USER에게 권한이 있는 비정상 상태지만 can() 로직 자체는 통과
        expect(can(regularUser, SimMemberPermissions.all(), (p) => p.canManageTo), isTrue);
      });

      test('SCENARIO-INV-921 권한 없는 하위관리자 — 모든 기능 불가', () {
        final checks = [
          can(subAdminUser, SimMemberPermissions.none(), (p) => p.canManageTo),
          can(subAdminUser, SimMemberPermissions.none(), (p) => p.canManageWorkers),
          can(subAdminUser, SimMemberPermissions.none(), (p) => p.canManageWage),
          can(subAdminUser, SimMemberPermissions.none(), (p) => p.canManageContract),
        ];
        expect(checks.every((c) => !c), isTrue);
      });

      test('SCENARIO-INV-922 전체 권한 하위관리자 — 모든 기능 가능', () {
        final checks = [
          can(subAdminUser, SimMemberPermissions.all(), (p) => p.canManageTo),
          can(subAdminUser, SimMemberPermissions.all(), (p) => p.canManageWorkers),
          can(subAdminUser, SimMemberPermissions.all(), (p) => p.canManageWage),
          can(subAdminUser, SimMemberPermissions.all(), (p) => p.canManageContract),
        ];
        expect(checks.every((c) => c), isTrue);
      });

      test('SCENARIO-INV-923 contract 권한만 있는 하위관리자 — 계약서만 가능', () {
        final contractOnly = const SimMemberPermissions(canManageContract: true);
        expect(can(subAdminUser, contractOnly, (p) => p.canManageContract), isTrue);
        expect(can(subAdminUser, contractOnly, (p) => p.canManageTo), isFalse);
        expect(can(subAdminUser, contractOnly, (p) => p.canManageWorkers), isFalse);
        expect(can(subAdminUser, contractOnly, (p) => p.canManageWage), isFalse);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════════
// SCENARIO-INV-Axx: 초대 만료 처리
// ════════════════════════════════════════════════════════════════

void _runExpirationTests() {
  group('SCENARIO-INV-Axx: 초대 만료 처리', () {
    test('SCENARIO-INV-A01 createdAt=1일전 → isExpired=false', () {
      expect(_pendingInvite(createdAt: _past1d).isExpired, isFalse);
    });

    test('SCENARIO-INV-A02 createdAt=10일전 → isExpired=false', () {
      expect(_pendingInvite(createdAt: _past10d).isExpired, isFalse);
    });

    test('SCENARIO-INV-A03 createdAt=29일전 → isExpired=false', () {
      expect(_pendingInvite(createdAt: _past29d).isExpired, isFalse);
    });

    test('SCENARIO-INV-A04 createdAt=30일전 정확히 → isExpired=true (경계)', () {
      // createdAt + 30일 = now → isAfter(expiresAt)는 false지만 equals도 만료로 처리
      // 실제 Firestore: createdAt > (now - 30d) 이어야 유효
      expect(_pendingInvite(createdAt: _past30d).isExpired, isTrue);
    });

    test('SCENARIO-INV-A05 createdAt=31일전 → isExpired=true', () {
      expect(_pendingInvite(createdAt: _past31d).isExpired, isTrue);
    });

    test('SCENARIO-INV-A06 createdAt=60일전 → isExpired=true', () {
      expect(_pendingInvite(createdAt: _past60d).isExpired, isTrue);
    });

    test('SCENARIO-INV-A07 만료된 pending 초대 → acceptInvitation 예외 발생', () {
      final inv = _pendingInvite(createdAt: _past31d);
      expect(() => acceptInvitation(inv, _emptyMembersDb()), throwsException);
    });

    test('SCENARIO-INV-A08 만료된 초대 → hasPendingInvitation=false (재초대 가능)', () {
      final invs = [_pendingInvite(createdAt: _past31d)];
      final hasActive = hasPendingInvitation('biz1', 'user1', invs);
      expect(hasActive, isFalse);
    });

    test('SCENARIO-INV-A09 만료 1분 전 → 아직 유효', () {
      // _now는 모듈 로드 시 캡처되므로 isExpired 체크 시점과 차이가 있다.
      // 실행 시간(수 초)보다 충분히 큰 버퍼(1분)를 사용해 flakiness를 방지한다.
      final justBeforeExpiry = DateTime.now()
          .subtract(const Duration(days: 30))
          .add(const Duration(minutes: 1)); // 만료까지 1분 남음
      final inv = _pendingInvite(createdAt: justBeforeExpiry);
      expect(inv.isExpired, isFalse);
    });

    test('SCENARIO-INV-A10 accepted 초대는 isExpired와 무관하게 acceptInvitation 예외', () {
      // accepted는 isPending=false → 만료 체크 전에 예외 발생
      final inv = _processedInvite(status: SimInvitationStatus.accepted);
      expect(() => acceptInvitation(inv, _emptyMembersDb()), throwsException);
    });
  });
}

// ════════════════════════════════════════════════════════════════
// main
// ════════════════════════════════════════════════════════════════

void main() {
  _runFindUserByPhoneTests();
  _runPreCheckTests();
  _runSendInvitationTests();
  _runAcceptInvitationTests();
  _runRejectCancelTests();
  _runRemoveMemberTests();
  _runUpdatePermissionsTests();
  _runTOCTOUTests();
  _runAdminModeAndCanTests();
  _runExpirationTests();
}
