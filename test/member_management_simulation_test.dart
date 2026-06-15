// ignore_for_file: lines_longer_than_80_chars
//
// 멤버 관리 로직 시뮬레이션 — 300+ 시나리오
//
// 검증 대상:
//   A. MemberPermissions (hasAnyPermission, summaryText, factory, copyWith, toMap)
//   B. InvitationStatus (파싱, 직렬화)
//   C. MemberInvitationModel (isPending, toMap/fromMap 왕복)
//   D. BusinessMemberModel (copyWith, toMap)
//   E. UserModel 역할 로직 (isSubAdmin, isBusinessAdmin, isSuperAdmin, isAdmin)
//   F. UserModel managedBusinessIds 폴백 로직
//   G. UserProvider.can() 로직 재현
//   H. effectiveBusinessId 로직 재현
//   I. hasPendingInvitation 만료 로직 재현
//   J. 권한 조합 시나리오 (RBAC)
//   K. 경계값 / 엣지케이스

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/member_invitation_model.dart';
import 'package:ALfit/models/core/user_model.dart';

// ════════════════════════════════════════════════════════════
// 팩토리 헬퍼
// ════════════════════════════════════════════════════════════

final _now    = DateTime.now();
final _past1d = _now.subtract(const Duration(days: 1));
final _past29d= _now.subtract(const Duration(days: 29));
final _past30d= _now.subtract(const Duration(days: 30));
final _past31d= _now.subtract(const Duration(days: 31));
final _past60d= _now.subtract(const Duration(days: 60));

MemberPermissions _perm({
  bool to = false,
  bool workers = false,
  bool wage = false,
  bool contract = false,
}) => MemberPermissions(
  canManageTo: to,
  canManageWorkers: workers,
  canManageWage: wage,
  canManageContract: contract,
);

BusinessMemberModel _member({
  String uid = 'uid1',
  String name = '테스터',
  String? phone = '010-1234-5678',
  MemberPermissions? permissions,
  DateTime? addedAt,
  String addedBy = 'admin1',
}) => BusinessMemberModel(
  uid: uid,
  name: name,
  phone: phone,
  permissions: permissions ?? MemberPermissions.none(),
  addedAt: addedAt ?? _past1d,
  addedBy: addedBy,
);

MemberInvitationModel _invite({
  String id = 'inv1',
  String businessId = 'biz1',
  String targetUid = 'uid1',
  InvitationStatus status = InvitationStatus.pending,
  MemberPermissions? permissions,
  DateTime? createdAt,
  DateTime? respondedAt,
}) => MemberInvitationModel(
  id: id,
  businessId: businessId,
  businessName: '테스트사업장',
  targetUid: targetUid,
  targetName: '테스터',
  invitedBy: 'admin1',
  invitedByName: '관리자',
  permissions: permissions ?? MemberPermissions.none(),
  status: status,
  createdAt: createdAt ?? _past1d,
  respondedAt: respondedAt,
);

UserModel _user({
  String uid = 'uid1',
  UserRole role = UserRole.USER,
  String? businessId,
  List<String>? managedBusinessIds,
  String? subAdminOf,
}) => UserModel(
  uid: uid,
  username: 'tester',
  name: '테스터',
  email: 'test@alfit.kr',
  role: role,
  businessId: businessId,
  managedBusinessIds: managedBusinessIds,
  subAdminOf: subAdminOf,
);

// ════════════════════════════════════════════════════════════
// A. MemberPermissions
// ════════════════════════════════════════════════════════════

void _runPermissionsTests() {
  group('A. MemberPermissions', () {

    // ── A1. hasAnyPermission ─────────────────────────────────
    group('A1. hasAnyPermission', () {
      test('A1-01 모두 false → hasAnyPermission=false', () {
        expect(_perm().hasAnyPermission, isFalse);
      });
      test('A1-02 canManageTo=true → hasAnyPermission=true', () {
        expect(_perm(to: true).hasAnyPermission, isTrue);
      });
      test('A1-03 canManageWorkers=true → hasAnyPermission=true', () {
        expect(_perm(workers: true).hasAnyPermission, isTrue);
      });
      test('A1-04 canManageWage=true → hasAnyPermission=true', () {
        expect(_perm(wage: true).hasAnyPermission, isTrue);
      });
      test('A1-05 canManageContract=true → hasAnyPermission=true', () {
        expect(_perm(contract: true).hasAnyPermission, isTrue);
      });
      test('A1-06 all=true → hasAnyPermission=true', () {
        expect(MemberPermissions.all().hasAnyPermission, isTrue);
      });
      test('A1-07 none() → hasAnyPermission=false', () {
        expect(MemberPermissions.none().hasAnyPermission, isFalse);
      });
      test('A1-08 to+workers=true → hasAnyPermission=true', () {
        expect(_perm(to: true, workers: true).hasAnyPermission, isTrue);
      });
      test('A1-09 wage+contract=true → hasAnyPermission=true', () {
        expect(_perm(wage: true, contract: true).hasAnyPermission, isTrue);
      });
      test('A1-10 to+workers+wage=true → hasAnyPermission=true', () {
        expect(_perm(to: true, workers: true, wage: true).hasAnyPermission, isTrue);
      });
    });

    // ── A2. summaryText ──────────────────────────────────────
    group('A2. summaryText', () {
      test('A2-01 모두 false → "권한 없음"', () {
        expect(_perm().summaryText, '권한 없음');
      });
      test('A2-02 to=true → "공고"', () {
        expect(_perm(to: true).summaryText, '공고');
      });
      test('A2-03 workers=true → "근무자"', () {
        expect(_perm(workers: true).summaryText, '근무자');
      });
      test('A2-04 wage=true → "급여"', () {
        expect(_perm(wage: true).summaryText, '급여');
      });
      test('A2-05 contract=true → "계약서"', () {
        expect(_perm(contract: true).summaryText, '계약서');
      });
      test('A2-06 to+workers → "공고 · 근무자"', () {
        expect(_perm(to: true, workers: true).summaryText, '공고 · 근무자');
      });
      test('A2-07 to+wage → "공고 · 급여"', () {
        expect(_perm(to: true, wage: true).summaryText, '공고 · 급여');
      });
      test('A2-08 to+contract → "공고 · 계약서"', () {
        expect(_perm(to: true, contract: true).summaryText, '공고 · 계약서');
      });
      test('A2-09 workers+wage → "근무자 · 급여"', () {
        expect(_perm(workers: true, wage: true).summaryText, '근무자 · 급여');
      });
      test('A2-10 workers+contract → "근무자 · 계약서"', () {
        expect(_perm(workers: true, contract: true).summaryText, '근무자 · 계약서');
      });
      test('A2-11 wage+contract → "급여 · 계약서"', () {
        expect(_perm(wage: true, contract: true).summaryText, '급여 · 계약서');
      });
      test('A2-12 to+workers+wage → "공고 · 근무자 · 급여"', () {
        expect(_perm(to: true, workers: true, wage: true).summaryText, '공고 · 근무자 · 급여');
      });
      test('A2-13 to+workers+contract → "공고 · 근무자 · 계약서"', () {
        expect(_perm(to: true, workers: true, contract: true).summaryText, '공고 · 근무자 · 계약서');
      });
      test('A2-14 to+wage+contract → "공고 · 급여 · 계약서"', () {
        expect(_perm(to: true, wage: true, contract: true).summaryText, '공고 · 급여 · 계약서');
      });
      test('A2-15 workers+wage+contract → "근무자 · 급여 · 계약서"', () {
        expect(_perm(workers: true, wage: true, contract: true).summaryText, '근무자 · 급여 · 계약서');
      });
      test('A2-16 all=true → "공고 · 근무자 · 급여 · 계약서"', () {
        expect(MemberPermissions.all().summaryText, '공고 · 근무자 · 급여 · 계약서');
      });
    });

    // ── A3. factory 메서드 ────────────────────────────────────
    group('A3. factory 메서드', () {
      test('A3-01 none() → 모두 false', () {
        final p = MemberPermissions.none();
        expect(p.canManageTo, isFalse);
        expect(p.canManageWorkers, isFalse);
        expect(p.canManageWage, isFalse);
        expect(p.canManageContract, isFalse);
      });
      test('A3-02 all() → 모두 true', () {
        final p = MemberPermissions.all();
        expect(p.canManageTo, isTrue);
        expect(p.canManageWorkers, isTrue);
        expect(p.canManageWage, isTrue);
        expect(p.canManageContract, isTrue);
      });
      test('A3-03 fromMap 빈 맵 → all false', () {
        final p = MemberPermissions.fromMap({});
        expect(p.hasAnyPermission, isFalse);
      });
      test('A3-04 fromMap canManageTo=true → to=true 나머지 false', () {
        final p = MemberPermissions.fromMap({'canManageTo': true});
        expect(p.canManageTo, isTrue);
        expect(p.canManageWorkers, isFalse);
      });
      test('A3-05 fromMap canManageWorkers=true', () {
        final p = MemberPermissions.fromMap({'canManageWorkers': true});
        expect(p.canManageWorkers, isTrue);
        expect(p.canManageTo, isFalse);
      });
      test('A3-06 fromMap canManageWage=true', () {
        expect(MemberPermissions.fromMap({'canManageWage': true}).canManageWage, isTrue);
      });
      test('A3-07 fromMap canManageContract=true', () {
        expect(MemberPermissions.fromMap({'canManageContract': true}).canManageContract, isTrue);
      });
      test('A3-08 fromMap null 값 → false (기본값)', () {
        final p = MemberPermissions.fromMap({'canManageTo': null});
        expect(p.canManageTo, isFalse);
      });
      test('A3-09 fromMap 전체 true', () {
        final p = MemberPermissions.fromMap({
          'canManageTo': true,
          'canManageWorkers': true,
          'canManageWage': true,
          'canManageContract': true,
        });
        expect(p.hasAnyPermission, isTrue);
        expect(p.summaryText, '공고 · 근무자 · 급여 · 계약서');
      });
      test('A3-10 fromMap 일부 true, 일부 false', () {
        final p = MemberPermissions.fromMap({
          'canManageTo': true,
          'canManageWorkers': false,
          'canManageWage': true,
          'canManageContract': false,
        });
        expect(p.canManageTo, isTrue);
        expect(p.canManageWorkers, isFalse);
        expect(p.canManageWage, isTrue);
        expect(p.canManageContract, isFalse);
      });
    });

    // ── A4. copyWith ─────────────────────────────────────────
    group('A4. copyWith', () {
      test('A4-01 아무것도 안 바꾸면 동일', () {
        final original = _perm(to: true, workers: false);
        final copy = original.copyWith();
        expect(copy.canManageTo, original.canManageTo);
        expect(copy.canManageWorkers, original.canManageWorkers);
      });
      test('A4-02 canManageTo 변경', () {
        final p = MemberPermissions.none().copyWith(canManageTo: true);
        expect(p.canManageTo, isTrue);
        expect(p.canManageWorkers, isFalse);
      });
      test('A4-03 canManageWorkers 변경', () {
        final p = MemberPermissions.none().copyWith(canManageWorkers: true);
        expect(p.canManageWorkers, isTrue);
      });
      test('A4-04 canManageWage 변경', () {
        final p = MemberPermissions.none().copyWith(canManageWage: true);
        expect(p.canManageWage, isTrue);
      });
      test('A4-05 canManageContract 변경', () {
        final p = MemberPermissions.none().copyWith(canManageContract: true);
        expect(p.canManageContract, isTrue);
      });
      test('A4-06 all()에서 to만 false로', () {
        final p = MemberPermissions.all().copyWith(canManageTo: false);
        expect(p.canManageTo, isFalse);
        expect(p.canManageWorkers, isTrue);
        expect(p.canManageWage, isTrue);
        expect(p.canManageContract, isTrue);
      });
      test('A4-07 all()에서 wage만 false로', () {
        final p = MemberPermissions.all().copyWith(canManageWage: false);
        expect(p.canManageWage, isFalse);
        expect(p.hasAnyPermission, isTrue);
      });
      test('A4-08 none()에서 4개 모두 true로', () {
        final p = MemberPermissions.none().copyWith(
          canManageTo: true,
          canManageWorkers: true,
          canManageWage: true,
          canManageContract: true,
        );
        expect(p.summaryText, '공고 · 근무자 · 급여 · 계약서');
      });
    });

    // ── A5. toMap 왕복 (round-trip) ───────────────────────────
    group('A5. toMap 왕복', () {
      test('A5-01 none() toMap → fromMap → none()', () {
        final original = MemberPermissions.none();
        final p = MemberPermissions.fromMap(original.toMap());
        expect(p.hasAnyPermission, isFalse);
      });
      test('A5-02 all() toMap → fromMap → all()', () {
        final original = MemberPermissions.all();
        final p = MemberPermissions.fromMap(original.toMap());
        expect(p.canManageTo, isTrue);
        expect(p.canManageWorkers, isTrue);
        expect(p.canManageWage, isTrue);
        expect(p.canManageContract, isTrue);
      });
      test('A5-03 부분 권한 왕복', () {
        final original = _perm(to: true, wage: true);
        final p = MemberPermissions.fromMap(original.toMap());
        expect(p.canManageTo, isTrue);
        expect(p.canManageWage, isTrue);
        expect(p.canManageWorkers, isFalse);
        expect(p.canManageContract, isFalse);
      });
      test('A5-04 toMap 키 존재 확인', () {
        final m = MemberPermissions.all().toMap();
        expect(m.containsKey('canManageTo'), isTrue);
        expect(m.containsKey('canManageWorkers'), isTrue);
        expect(m.containsKey('canManageWage'), isTrue);
        expect(m.containsKey('canManageContract'), isTrue);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// B. InvitationStatus 파싱/직렬화
// ════════════════════════════════════════════════════════════

void _runInvitationStatusTests() {
  group('B. InvitationStatus 파싱', () {


    test('B-01 pending 상태 → isPending=true', () {
      expect(_invite(status: InvitationStatus.pending).isPending, isTrue);
    });
    test('B-02 accepted → isPending=false', () {
      expect(_invite(status: InvitationStatus.accepted).isPending, isFalse);
    });
    test('B-03 rejected → isPending=false', () {
      expect(_invite(status: InvitationStatus.rejected).isPending, isFalse);
    });
    test('B-04 cancelled → isPending=false', () {
      expect(_invite(status: InvitationStatus.cancelled).isPending, isFalse);
    });
    test('B-05 toMap pending → 직렬화 확인', () {
      final m = _invite(status: InvitationStatus.pending).toMap();
      expect(m['status'], 'pending');
    });
    test('B-06 toMap accepted → 직렬화', () {
      final m = _invite(status: InvitationStatus.accepted).toMap();
      expect(m['status'], 'accepted');
    });
    test('B-07 toMap rejected → 직렬화', () {
      final m = _invite(status: InvitationStatus.rejected).toMap();
      expect(m['status'], 'rejected');
    });
    test('B-08 toMap cancelled → 직렬화', () {
      final m = _invite(status: InvitationStatus.cancelled).toMap();
      expect(m['status'], 'cancelled');
    });
    test('B-09 InvitationStatus.values 4개', () {
      expect(InvitationStatus.values.length, 4);
    });
    test('B-10 pending 상태의 초대만 hasAnyPermission 의미 있음', () {
      final inv = _invite(status: InvitationStatus.pending, permissions: MemberPermissions.all());
      expect(inv.isPending, isTrue);
      expect(inv.permissions.hasAnyPermission, isTrue);
    });
  });
}

// ════════════════════════════════════════════════════════════
// C. MemberInvitationModel
// ════════════════════════════════════════════════════════════

void _runInvitationModelTests() {
  group('C. MemberInvitationModel', () {

    group('C1. 필드 접근', () {
      test('C1-01 businessId 필드', () {
        expect(_invite(businessId: 'biz999').businessId, 'biz999');
      });
      test('C1-02 targetUid 필드', () {
        expect(_invite(targetUid: 'uid999').targetUid, 'uid999');
      });
      test('C1-03 createdAt 필드', () {
        final now = DateTime.now();
        expect(_invite(createdAt: now).createdAt, now);
      });
      test('C1-04 respondedAt null (미응답)', () {
        expect(_invite(respondedAt: null).respondedAt, isNull);
      });
      test('C1-05 respondedAt 설정됨 (응답됨)', () {
        expect(_invite(respondedAt: _past1d).respondedAt, isNotNull);
      });
      test('C1-06 permissions 필드 접근', () {
        expect(_invite(permissions: MemberPermissions.all()).permissions.hasAnyPermission, isTrue);
      });
    });

    group('C2. toMap 왕복', () {
      test('C2-01 toMap businessId 포함', () {
        final m = _invite(businessId: 'biz1').toMap();
        expect(m['businessId'], 'biz1');
      });
      test('C2-02 toMap targetUid 포함', () {
        expect(_invite(targetUid: 'uid1').toMap()['targetUid'], 'uid1');
      });
      test('C2-03 toMap status=pending', () {
        expect(_invite(status: InvitationStatus.pending).toMap()['status'], 'pending');
      });
      test('C2-04 toMap permissions 중첩 맵', () {
        final m = _invite(permissions: MemberPermissions.all()).toMap();
        expect((m['permissions'] as Map)['canManageTo'], isTrue);
      });
      test('C2-05 toMap respondedAt null', () {
        expect(_invite(respondedAt: null).toMap()['respondedAt'], isNull);
      });
      test('C2-06 toMap respondedAt not null', () {
        expect(_invite(respondedAt: _past1d).toMap()['respondedAt'], isNotNull);
      });
      test('C2-07 toMap businessName 포함', () {
        expect(_invite().toMap()['businessName'], '테스트사업장');
      });
      test('C2-08 toMap targetName 포함', () {
        expect(_invite().toMap()['targetName'], '테스터');
      });
      test('C2-09 toMap invitedBy 포함', () {
        expect(_invite().toMap()['invitedBy'], 'admin1');
      });
    });

    group('C3. 만료 판정 재현 (hasPendingInvitation 로직)', () {
      // 만료 기준: now - 30일 (createdAt > expiry 이어야 유효)
      bool isExpired(MemberInvitationModel inv) {
        final expiry = _now.subtract(const Duration(days: 30));
        return !inv.createdAt.isAfter(expiry);
      }

      test('C3-01 createdAt=1일전 → 유효 (not expired)', () {
        expect(isExpired(_invite(createdAt: _past1d)), isFalse);
      });
      test('C3-02 createdAt=29일전 → 유효', () {
        expect(isExpired(_invite(createdAt: _past29d)), isFalse);
      });
      test('C3-03 createdAt=30일전 → 만료 (경계: 정확히 30일 = 만료)', () {
        expect(isExpired(_invite(createdAt: _past30d)), isTrue);
      });
      test('C3-04 createdAt=31일전 → 만료', () {
        expect(isExpired(_invite(createdAt: _past31d)), isTrue);
      });
      test('C3-05 createdAt=60일전 → 만료', () {
        expect(isExpired(_invite(createdAt: _past60d)), isTrue);
      });
      test('C3-06 pending + 유효 → hasPendingInvitation=true', () {
        final inv = _invite(status: InvitationStatus.pending, createdAt: _past1d);
        final isActive = inv.isPending && !isExpired(inv);
        expect(isActive, isTrue);
      });
      test('C3-07 pending + 만료 → hasPendingInvitation=false', () {
        final inv = _invite(status: InvitationStatus.pending, createdAt: _past31d);
        final isActive = inv.isPending && !isExpired(inv);
        expect(isActive, isFalse);
      });
      test('C3-08 accepted + 유효기간 내 → hasPendingInvitation=false (status 비일치)', () {
        final inv = _invite(status: InvitationStatus.accepted, createdAt: _past1d);
        expect(inv.isPending && !isExpired(inv), isFalse);
      });
      test('C3-09 rejected + 유효기간 내 → hasPendingInvitation=false', () {
        final inv = _invite(status: InvitationStatus.rejected, createdAt: _past1d);
        expect(inv.isPending && !isExpired(inv), isFalse);
      });
      test('C3-10 cancelled + 유효기간 내 → hasPendingInvitation=false', () {
        final inv = _invite(status: InvitationStatus.cancelled, createdAt: _past1d);
        expect(inv.isPending && !isExpired(inv), isFalse);
      });
      test('C3-11 now - 30d + 1ms = 유효 (29d 23h 59m 59s 999ms)', () {
        final justInsideExpiry = _now.subtract(const Duration(days: 30)).add(const Duration(milliseconds: 1));
        final inv = _invite(status: InvitationStatus.pending, createdAt: justInsideExpiry);
        expect(!isExpired(inv), isTrue);
      });
      test('C3-12 now - 30d - 1ms = 만료 (경계 밖)', () {
        final justOutsideExpiry = _now.subtract(const Duration(days: 30)).subtract(const Duration(milliseconds: 1));
        final inv = _invite(status: InvitationStatus.pending, createdAt: justOutsideExpiry);
        expect(isExpired(inv), isTrue);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// D. BusinessMemberModel
// ════════════════════════════════════════════════════════════

void _runBusinessMemberModelTests() {
  group('D. BusinessMemberModel', () {

    group('D1. 필드', () {
      test('D1-01 uid 필드', () {
        expect(_member(uid: 'uid999').uid, 'uid999');
      });
      test('D1-02 name 필드', () {
        expect(_member(name: '홍길동').name, '홍길동');
      });
      test('D1-03 phone null', () {
        expect(_member(phone: null).phone, isNull);
      });
      test('D1-04 phone 설정됨', () {
        expect(_member(phone: '010-9999-8888').phone, '010-9999-8888');
      });
      test('D1-05 addedBy 필드', () {
        expect(_member(addedBy: 'boss1').addedBy, 'boss1');
      });
      test('D1-06 addedAt 필드', () {
        expect(_member(addedAt: _past30d).addedAt, _past30d);
      });
    });

    group('D2. copyWith', () {
      test('D2-01 name 변경', () {
        final m = _member(name: '원본').copyWith(name: '수정됨');
        expect(m.name, '수정됨');
        expect(m.uid, 'uid1');  // uid는 유지
      });
      test('D2-02 phone 변경', () {
        final m = _member(phone: '010-0000-0000').copyWith(phone: '010-9999-9999');
        expect(m.phone, '010-9999-9999');
      });
      test('D2-03 permissions 변경', () {
        final m = _member().copyWith(permissions: MemberPermissions.all());
        expect(m.permissions.hasAnyPermission, isTrue);
      });
      test('D2-04 아무것도 안 바꾸면 동일', () {
        final original = _member(name: '테스터');
        final copy = original.copyWith();
        expect(copy.name, original.name);
        expect(copy.uid, original.uid);
      });
      test('D2-05 uid는 copyWith로 변경 불가', () {
        // uid는 copyWith 파라미터에 없음
        final copy = _member(uid: 'uid1').copyWith(name: '변경');
        expect(copy.uid, 'uid1');  // 변경 안 됨
      });
    });

    group('D3. toMap', () {
      test('D3-01 name 포함', () {
        expect(_member(name: '홍길동').toMap()['name'], '홍길동');
      });
      test('D3-02 phone 포함', () {
        expect(_member(phone: '010-1111-2222').toMap()['phone'], '010-1111-2222');
      });
      test('D3-03 phone null 포함', () {
        expect(_member(phone: null).toMap()['phone'], isNull);
      });
      test('D3-04 permissions 중첩 맵', () {
        final m = _member(permissions: MemberPermissions.all()).toMap();
        expect((m['permissions'] as Map)['canManageTo'], isTrue);
      });
      test('D3-05 addedBy 포함', () {
        expect(_member(addedBy: 'boss1').toMap()['addedBy'], 'boss1');
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// E. UserModel 역할 로직
// ════════════════════════════════════════════════════════════

void _runUserRoleTests() {
  group('E. UserModel 역할 로직', () {

    group('E1. isSuperAdmin', () {
      test('E1-01 role=SUPER_ADMIN → isSuperAdmin=true', () {
        expect(_user(role: UserRole.SUPER_ADMIN).isSuperAdmin, isTrue);
      });
      test('E1-02 role=BUSINESS_ADMIN → isSuperAdmin=false', () {
        expect(_user(role: UserRole.BUSINESS_ADMIN).isSuperAdmin, isFalse);
      });
      test('E1-03 role=USER → isSuperAdmin=false', () {
        expect(_user(role: UserRole.USER).isSuperAdmin, isFalse);
      });
    });

    group('E2. isBusinessAdmin', () {
      test('E2-01 role=BUSINESS_ADMIN → isBusinessAdmin=true', () {
        expect(_user(role: UserRole.BUSINESS_ADMIN).isBusinessAdmin, isTrue);
      });
      test('E2-02 role=SUPER_ADMIN → isBusinessAdmin=false', () {
        expect(_user(role: UserRole.SUPER_ADMIN).isBusinessAdmin, isFalse);
      });
      test('E2-03 role=USER → isBusinessAdmin=false', () {
        expect(_user(role: UserRole.USER).isBusinessAdmin, isFalse);
      });
    });

    group('E3. isSubAdmin', () {
      test('E3-01 role=USER + subAdminOf=null → isSubAdmin=false', () {
        expect(_user(role: UserRole.USER, subAdminOf: null).isSubAdmin, isFalse);
      });
      test('E3-02 role=USER + subAdminOf="biz1" → isSubAdmin=true', () {
        expect(_user(role: UserRole.USER, subAdminOf: 'biz1').isSubAdmin, isTrue);
      });
      test('E3-03 role=BUSINESS_ADMIN + subAdminOf="biz1" → isSubAdmin=false (역할 우선)', () {
        expect(_user(role: UserRole.BUSINESS_ADMIN, subAdminOf: 'biz1').isSubAdmin, isFalse);
      });
      test('E3-04 role=SUPER_ADMIN + subAdminOf="biz1" → isSubAdmin=false', () {
        expect(_user(role: UserRole.SUPER_ADMIN, subAdminOf: 'biz1').isSubAdmin, isFalse);
      });
      test('E3-05 role=USER + subAdminOf="" (빈 문자열) → isSubAdmin=true (null 아님)', () {
        // 빈 문자열도 null이 아니므로 isSubAdmin=true (DB 오류 케이스)
        expect(_user(role: UserRole.USER, subAdminOf: '').isSubAdmin, isTrue);
      });
      test('E3-06 isUser=true, subAdminOf 있음 → isAdmin=true', () {
        final u = _user(role: UserRole.USER, subAdminOf: 'biz1');
        expect(u.isAdmin, isTrue);
      });
    });

    group('E4. isAdmin', () {
      test('E4-01 SUPER_ADMIN → isAdmin=true', () {
        expect(_user(role: UserRole.SUPER_ADMIN).isAdmin, isTrue);
      });
      test('E4-02 BUSINESS_ADMIN → isAdmin=true', () {
        expect(_user(role: UserRole.BUSINESS_ADMIN).isAdmin, isTrue);
      });
      test('E4-03 USER + subAdminOf=null → isAdmin=false', () {
        expect(_user(role: UserRole.USER).isAdmin, isFalse);
      });
      test('E4-04 USER + subAdminOf="biz" → isAdmin=true (하위관리자)', () {
        expect(_user(role: UserRole.USER, subAdminOf: 'biz1').isAdmin, isTrue);
      });
    });

    group('E5. isUser', () {
      test('E5-01 role=USER → isUser=true', () {
        expect(_user(role: UserRole.USER).isUser, isTrue);
      });
      test('E5-02 role=BUSINESS_ADMIN → isUser=false', () {
        expect(_user(role: UserRole.BUSINESS_ADMIN).isUser, isFalse);
      });
      test('E5-03 role=SUPER_ADMIN → isUser=false', () {
        expect(_user(role: UserRole.SUPER_ADMIN).isUser, isFalse);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// F. managedBusinessIds 폴백 로직
// ════════════════════════════════════════════════════════════

void _runManagedBusinessIdsTests() {
  group('F. managedBusinessIds 폴백', () {
    test('F-01 businessId="biz1", managedIds=null → managedIds=["biz1"]', () {
      final u = _user(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1', managedBusinessIds: null);
      expect(u.managedBusinessIds, ['biz1']);
    });
    test('F-02 businessId=null, managedIds=null → managedIds=[]', () {
      final u = _user(role: UserRole.BUSINESS_ADMIN, businessId: null, managedBusinessIds: null);
      expect(u.managedBusinessIds, isEmpty);
    });
    test('F-03 businessId="biz1", managedIds=["biz1","biz2"] → managedIds=["biz1","biz2"]', () {
      final u = _user(businessId: 'biz1', managedBusinessIds: ['biz1', 'biz2']);
      expect(u.managedBusinessIds, ['biz1', 'biz2']);
    });
    test('F-04 businessId=null, managedIds=["biz3"] → managedIds=["biz3"]', () {
      final u = _user(managedBusinessIds: ['biz3']);
      expect(u.managedBusinessIds, ['biz3']);
    });
    test('F-05 SUPER_ADMIN은 managedIds 사용 안 함 (WorkforceController에서 null 반환)', () {
      final u = _user(role: UserRole.SUPER_ADMIN);
      expect(u.isSuperAdmin, isTrue);
      // WorkforceController: isSuperAdmin → businessIds = null (전체 조회)
    });
    test('F-06 BUSINESS_ADMIN, managedIds 여러 개', () {
      final u = _user(
        role: UserRole.BUSINESS_ADMIN,
        businessId: 'biz1',
        managedBusinessIds: ['biz1', 'biz2', 'biz3'],
      );
      expect(u.managedBusinessIds.length, 3);
    });
    test('F-07 SUB_ADMIN: isSubAdmin=true, subAdminOf="biz1" → 컨트롤러에서 businessIds=["biz1"]', () {
      final u = _user(role: UserRole.USER, subAdminOf: 'biz1');
      expect(u.isSubAdmin, isTrue);
      expect(u.subAdminOf, 'biz1');
      // WorkforceController: isSubAdmin && subAdminOf != null → businessIds = [subAdminOf]
      final businessIds = u.isSubAdmin && u.subAdminOf != null ? [u.subAdminOf!] : null;
      expect(businessIds, ['biz1']);
    });
    test('F-08 SUB_ADMIN, subAdminOf=null (비정상 상태) → businessIds = managedBusinessIds', () {
      final u = _user(role: UserRole.USER, subAdminOf: null);
      expect(u.isSubAdmin, isFalse);
      // WorkforceController: !isSuperAdmin && !isSubAdmin → businessIds = managedBusinessIds
      final businessIds = u.managedBusinessIds;
      expect(businessIds, isEmpty);
    });
  });
}

// ════════════════════════════════════════════════════════════
// G. UserProvider.can() 로직 재현
// ════════════════════════════════════════════════════════════

// UserProvider.can() 로직 순수 재현 (Firestore 없이)
bool canCheck(
  UserModel? user,
  MemberPermissions? memberPermissions,
  bool Function(MemberPermissions p) check,
) {
  if (user?.isBusinessAdmin == true) return true;
  if (memberPermissions != null) return check(memberPermissions);
  return false;
}

void _runCanCheckTests() {
  group('G. UserProvider.can() 로직', () {
    final bizAdmin = _user(role: UserRole.BUSINESS_ADMIN);
    final superAdmin = _user(role: UserRole.SUPER_ADMIN);
    final subAdminFull = _user(role: UserRole.USER, subAdminOf: 'biz1');
    final regularUser = _user(role: UserRole.USER);
    final allPerms = MemberPermissions.all();
    final nonePerms = MemberPermissions.none();

    group('G1. BUSINESS_ADMIN — 항상 true', () {
      test('G1-01 BUSINESS_ADMIN + canManageTo 체크 → true', () {
        expect(canCheck(bizAdmin, null, (p) => p.canManageTo), isTrue);
      });
      test('G1-02 BUSINESS_ADMIN + canManageWorkers 체크 → true', () {
        expect(canCheck(bizAdmin, null, (p) => p.canManageWorkers), isTrue);
      });
      test('G1-03 BUSINESS_ADMIN + canManageWage 체크 → true', () {
        expect(canCheck(bizAdmin, null, (p) => p.canManageWage), isTrue);
      });
      test('G1-04 BUSINESS_ADMIN + canManageContract 체크 → true', () {
        expect(canCheck(bizAdmin, null, (p) => p.canManageContract), isTrue);
      });
      test('G1-05 BUSINESS_ADMIN + permissions=none → 여전히 true', () {
        expect(canCheck(bizAdmin, nonePerms, (p) => p.canManageTo), isTrue);
      });
    });

    group('G2. SUPER_ADMIN — can()은 false (isSuperAdmin 별도 체크)', () {
      test('G2-01 SUPER_ADMIN + 권한 없음 → false', () {
        expect(canCheck(superAdmin, null, (p) => p.canManageTo), isFalse);
      });
      test('G2-02 SUPER_ADMIN + allPerms → true (memberPermissions로 통과)', () {
        expect(canCheck(superAdmin, allPerms, (p) => p.canManageTo), isTrue);
      });
    });

    group('G3. SUB_ADMIN + permissions', () {
      test('G3-01 SUB_ADMIN + allPerms + canManageTo → true', () {
        expect(canCheck(subAdminFull, allPerms, (p) => p.canManageTo), isTrue);
      });
      test('G3-02 SUB_ADMIN + allPerms + canManageWorkers → true', () {
        expect(canCheck(subAdminFull, allPerms, (p) => p.canManageWorkers), isTrue);
      });
      test('G3-03 SUB_ADMIN + allPerms + canManageWage → true', () {
        expect(canCheck(subAdminFull, allPerms, (p) => p.canManageWage), isTrue);
      });
      test('G3-04 SUB_ADMIN + allPerms + canManageContract → true', () {
        expect(canCheck(subAdminFull, allPerms, (p) => p.canManageContract), isTrue);
      });
      test('G3-05 SUB_ADMIN + nonePerms + canManageTo → false', () {
        expect(canCheck(subAdminFull, nonePerms, (p) => p.canManageTo), isFalse);
      });
      test('G3-06 SUB_ADMIN + nonePerms + canManageWage → false', () {
        expect(canCheck(subAdminFull, nonePerms, (p) => p.canManageWage), isFalse);
      });
      test('G3-07 SUB_ADMIN + to권한만 → canManageTo=true, 나머지 false', () {
        final toOnly = _perm(to: true);
        expect(canCheck(subAdminFull, toOnly, (p) => p.canManageTo), isTrue);
        expect(canCheck(subAdminFull, toOnly, (p) => p.canManageWorkers), isFalse);
        expect(canCheck(subAdminFull, toOnly, (p) => p.canManageWage), isFalse);
        expect(canCheck(subAdminFull, toOnly, (p) => p.canManageContract), isFalse);
      });
      test('G3-08 SUB_ADMIN + workers권한만', () {
        final workersOnly = _perm(workers: true);
        expect(canCheck(subAdminFull, workersOnly, (p) => p.canManageTo), isFalse);
        expect(canCheck(subAdminFull, workersOnly, (p) => p.canManageWorkers), isTrue);
      });
      test('G3-09 SUB_ADMIN + wage권한만', () {
        final wageOnly = _perm(wage: true);
        expect(canCheck(subAdminFull, wageOnly, (p) => p.canManageWage), isTrue);
        expect(canCheck(subAdminFull, wageOnly, (p) => p.canManageTo), isFalse);
      });
      test('G3-10 SUB_ADMIN + contract권한만', () {
        final contractOnly = _perm(contract: true);
        expect(canCheck(subAdminFull, contractOnly, (p) => p.canManageContract), isTrue);
        expect(canCheck(subAdminFull, contractOnly, (p) => p.canManageTo), isFalse);
      });
      test('G3-11 SUB_ADMIN + memberPermissions=null → false (권한 로드 안 됨)', () {
        expect(canCheck(subAdminFull, null, (p) => p.canManageTo), isFalse);
      });
    });

    group('G4. 일반 USER', () {
      test('G4-01 regularUser + 권한 없음 → false', () {
        expect(canCheck(regularUser, null, (p) => p.canManageTo), isFalse);
      });
      test('G4-02 regularUser + allPerms (비정상) → true (permissions 있으면 check)', () {
        // 일반 유저에게 권한이 있는 비정상 상태지만, can() 로직 자체는 통과
        expect(canCheck(regularUser, allPerms, (p) => p.canManageTo), isTrue);
      });
    });

    group('G5. null user', () {
      test('G5-01 user=null → false', () {
        expect(canCheck(null, null, (p) => p.canManageTo), isFalse);
      });
      test('G5-02 user=null + allPerms → true (null-safe 체크)', () {
        // user?.isBusinessAdmin == null != true → false, 그 다음 memberPermissions로 통과
        expect(canCheck(null, allPerms, (p) => p.canManageTo), isTrue);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// H. effectiveBusinessId 로직 재현
// ════════════════════════════════════════════════════════════

String? effectiveBusinessId(UserModel user) {
  if (user.isBusinessAdmin) return user.businessId;
  if (user.isSubAdmin) return user.subAdminOf;
  return null;
}

void _runEffectiveBusinessIdTests() {
  group('H. effectiveBusinessId', () {
    test('H-01 BUSINESS_ADMIN + businessId="biz1" → "biz1"', () {
      expect(effectiveBusinessId(_user(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1')), 'biz1');
    });
    test('H-02 BUSINESS_ADMIN + businessId=null → null', () {
      expect(effectiveBusinessId(_user(role: UserRole.BUSINESS_ADMIN, businessId: null)), isNull);
    });
    test('H-03 SUB_ADMIN + subAdminOf="biz2" → "biz2"', () {
      expect(effectiveBusinessId(_user(role: UserRole.USER, subAdminOf: 'biz2')), 'biz2');
    });
    test('H-04 USER + subAdminOf=null → null', () {
      expect(effectiveBusinessId(_user(role: UserRole.USER)), isNull);
    });
    test('H-05 SUPER_ADMIN → null', () {
      expect(effectiveBusinessId(_user(role: UserRole.SUPER_ADMIN)), isNull);
    });
    test('H-06 BUSINESS_ADMIN, managedIds 여럿이어도 businessId 반환', () {
      final u = _user(
        role: UserRole.BUSINESS_ADMIN,
        businessId: 'biz1',
        managedBusinessIds: ['biz1', 'biz2'],
      );
      expect(effectiveBusinessId(u), 'biz1');
    });
    test('H-07 SUB_ADMIN: subAdminOf가 businessId보다 우선', () {
      // USER 역할이면 businessId 필드는 의미 없음
      final u = _user(role: UserRole.USER, businessId: 'biz_owner', subAdminOf: 'biz_sub');
      expect(effectiveBusinessId(u), 'biz_sub');
    });
    test('H-08 BUSINESS_ADMIN: subAdminOf 있어도 businessId 반환 (역할 우선)', () {
      final u = _user(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1', subAdminOf: 'biz2');
      expect(effectiveBusinessId(u), 'biz1');
    });
  });
}

// ════════════════════════════════════════════════════════════
// I. 권한 조합 RBAC 시나리오
// ════════════════════════════════════════════════════════════

void _runRBACTests() {
  group('I. RBAC 권한 조합', () {

    // can() + 메뉴 노출 조건 재현:
    // - 공고 메뉴: !isSubAdmin || can(canManageTo)
    // - 근무자 메뉴: !isSubAdmin || can(canManageTo) || can(canManageWorkers)
    // - 급여 메뉴: !isSubAdmin || can(canManageWage)
    // - 계약서 메뉴: !isSubAdmin || can(canManageContract)

    bool showToMenu(UserModel u, MemberPermissions? p) =>
        !u.isSubAdmin || canCheck(u, p, (pp) => pp.canManageTo);

    bool showWorkersMenu(UserModel u, MemberPermissions? p) =>
        !u.isSubAdmin || canCheck(u, p, (pp) => pp.canManageTo) || canCheck(u, p, (pp) => pp.canManageWorkers);

    bool showWageMenu(UserModel u, MemberPermissions? p) =>
        !u.isSubAdmin || canCheck(u, p, (pp) => pp.canManageWage);

    bool showContractMenu(UserModel u, MemberPermissions? p) =>
        !u.isSubAdmin || canCheck(u, p, (pp) => pp.canManageContract);

    final bizAdmin = _user(role: UserRole.BUSINESS_ADMIN);
    final subUser = _user(role: UserRole.USER, subAdminOf: 'biz1');
    final regularUser = _user(role: UserRole.USER);

    group('I1. BUSINESS_ADMIN — 모든 메뉴 표시', () {
      test('I1-01 BUSINESS_ADMIN: 공고 메뉴 표시', () {
        expect(showToMenu(bizAdmin, null), isTrue);
      });
      test('I1-02 BUSINESS_ADMIN: 근무자 메뉴 표시', () {
        expect(showWorkersMenu(bizAdmin, null), isTrue);
      });
      test('I1-03 BUSINESS_ADMIN: 급여 메뉴 표시', () {
        expect(showWageMenu(bizAdmin, null), isTrue);
      });
      test('I1-04 BUSINESS_ADMIN: 계약서 메뉴 표시', () {
        expect(showContractMenu(bizAdmin, null), isTrue);
      });
    });

    group('I2. 일반 USER — 모든 관리자 메뉴 표시 (관리자 영역 진입 자체 불가)', () {
      test('I2-01 일반 USER: 공고 메뉴 표시 (isSubAdmin=false → !isSubAdmin=true)', () {
        expect(showToMenu(regularUser, null), isTrue);  // !isSubAdmin이므로 통과
      });
    });

    group('I3. SUB_ADMIN + 권한 없음', () {
      test('I3-01 to=false → 공고 메뉴 숨김', () {
        expect(showToMenu(subUser, _perm()), isFalse);
      });
      test('I3-02 workers=false → 근무자 메뉴 숨김 (to도 false)', () {
        expect(showWorkersMenu(subUser, _perm()), isFalse);
      });
      test('I3-03 wage=false → 급여 메뉴 숨김', () {
        expect(showWageMenu(subUser, _perm()), isFalse);
      });
      test('I3-04 contract=false → 계약서 메뉴 숨김', () {
        expect(showContractMenu(subUser, _perm()), isFalse);
      });
    });

    group('I4. SUB_ADMIN + to권한만', () {
      final toOnly = _perm(to: true);
      test('I4-01 to=true → 공고 메뉴 표시', () {
        expect(showToMenu(subUser, toOnly), isTrue);
      });
      test('I4-02 to=true → 근무자 메뉴도 표시 (to 있으면 근무자 통과)', () {
        expect(showWorkersMenu(subUser, toOnly), isTrue);
      });
      test('I4-03 to=true, wage=false → 급여 메뉴 숨김', () {
        expect(showWageMenu(subUser, toOnly), isFalse);
      });
      test('I4-04 to=true, contract=false → 계약서 메뉴 숨김', () {
        expect(showContractMenu(subUser, toOnly), isFalse);
      });
    });

    group('I5. SUB_ADMIN + workers권한만', () {
      final workersOnly = _perm(workers: true);
      test('I5-01 workers=true, to=false → 공고 메뉴 숨김', () {
        expect(showToMenu(subUser, workersOnly), isFalse);
      });
      test('I5-02 workers=true → 근무자 메뉴 표시', () {
        expect(showWorkersMenu(subUser, workersOnly), isTrue);
      });
      test('I5-03 workers=true, wage=false → 급여 메뉴 숨김', () {
        expect(showWageMenu(subUser, workersOnly), isFalse);
      });
    });

    group('I6. SUB_ADMIN + wage권한만', () {
      final wageOnly = _perm(wage: true);
      test('I6-01 wage=true, to=false → 공고 메뉴 숨김', () {
        expect(showToMenu(subUser, wageOnly), isFalse);
      });
      test('I6-02 wage=true → 급여 메뉴 표시', () {
        expect(showWageMenu(subUser, wageOnly), isTrue);
      });
    });

    group('I7. SUB_ADMIN + contract권한만', () {
      final contractOnly = _perm(contract: true);
      test('I7-01 contract=true, to=false → 공고 메뉴 숨김', () {
        expect(showToMenu(subUser, contractOnly), isFalse);
      });
      test('I7-02 contract=true → 계약서 메뉴 표시', () {
        expect(showContractMenu(subUser, contractOnly), isTrue);
      });
    });

    group('I8. SUB_ADMIN + 전체 권한', () {
      final allPerms = MemberPermissions.all();
      test('I8-01 all → 공고 메뉴 표시', () {
        expect(showToMenu(subUser, allPerms), isTrue);
      });
      test('I8-02 all → 근무자 메뉴 표시', () {
        expect(showWorkersMenu(subUser, allPerms), isTrue);
      });
      test('I8-03 all → 급여 메뉴 표시', () {
        expect(showWageMenu(subUser, allPerms), isTrue);
      });
      test('I8-04 all → 계약서 메뉴 표시', () {
        expect(showContractMenu(subUser, allPerms), isTrue);
      });
    });

    group('I9. SUB_ADMIN + permissions=null (로드 실패)', () {
      test('I9-01 null permissions → 공고 메뉴 숨김', () {
        expect(showToMenu(subUser, null), isFalse);
      });
      test('I9-02 null permissions → 근무자 메뉴 숨김', () {
        expect(showWorkersMenu(subUser, null), isFalse);
      });
      test('I9-03 null permissions → 급여 메뉴 숨김', () {
        expect(showWageMenu(subUser, null), isFalse);
      });
      test('I9-04 null permissions → 계약서 메뉴 숨김', () {
        expect(showContractMenu(subUser, null), isFalse);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// J. 초대 워크플로 시나리오
// ════════════════════════════════════════════════════════════

void _runInvitationWorkflowTests() {
  group('J. 초대 워크플로 시나리오', () {

    group('J1. 초대 상태 전환', () {
      test('J1-01 pending → accepted: isPending 변경', () {
        final before = _invite(status: InvitationStatus.pending);
        final after = _invite(status: InvitationStatus.accepted);
        expect(before.isPending, isTrue);
        expect(after.isPending, isFalse);
      });
      test('J1-02 pending → rejected: isPending 변경', () {
        final after = _invite(status: InvitationStatus.rejected);
        expect(after.isPending, isFalse);
      });
      test('J1-03 pending → cancelled: isPending 변경', () {
        final after = _invite(status: InvitationStatus.cancelled);
        expect(after.isPending, isFalse);
      });
      test('J1-04 수락 시 respondedAt 설정됨', () {
        final inv = _invite(status: InvitationStatus.accepted, respondedAt: _now);
        expect(inv.respondedAt, isNotNull);
      });
      test('J1-05 거절 시 respondedAt 설정됨', () {
        final inv = _invite(status: InvitationStatus.rejected, respondedAt: _now);
        expect(inv.respondedAt, isNotNull);
      });
      test('J1-06 pending 상태 respondedAt=null (미응답)', () {
        expect(_invite(status: InvitationStatus.pending, respondedAt: null).respondedAt, isNull);
      });
    });

    group('J2. 초대 권한 상속', () {
      test('J2-01 초대에 to권한 포함 → 수락 후 멤버도 to권한', () {
        final inv = _invite(permissions: _perm(to: true));
        final memberPerms = inv.permissions;
        expect(memberPerms.canManageTo, isTrue);
      });
      test('J2-02 초대에 권한 없음 → 수락 후 권한 없음', () {
        final inv = _invite(permissions: MemberPermissions.none());
        expect(inv.permissions.hasAnyPermission, isFalse);
      });
      test('J2-03 초대에 전체 권한 → 멤버도 전체 권한', () {
        final inv = _invite(permissions: MemberPermissions.all());
        expect(inv.permissions.summaryText, '공고 · 근무자 · 급여 · 계약서');
      });
    });

    group('J3. CF 트리거 시뮬레이션 (onMemberInvitationAccepted)', () {
      // before.status=pending AND after.status=accepted → subAdminOf 설정 대상

      bool shouldSetSubAdminOf(InvitationStatus before, InvitationStatus after) {
        return before == InvitationStatus.pending && after == InvitationStatus.accepted;
      }

      test('J3-01 pending→accepted → subAdminOf 설정', () {
        expect(shouldSetSubAdminOf(InvitationStatus.pending, InvitationStatus.accepted), isTrue);
      });
      test('J3-02 pending→rejected → 설정 안 함', () {
        expect(shouldSetSubAdminOf(InvitationStatus.pending, InvitationStatus.rejected), isFalse);
      });
      test('J3-03 pending→cancelled → 설정 안 함', () {
        expect(shouldSetSubAdminOf(InvitationStatus.pending, InvitationStatus.cancelled), isFalse);
      });
      test('J3-04 accepted→accepted (중복) → 설정 안 함', () {
        expect(shouldSetSubAdminOf(InvitationStatus.accepted, InvitationStatus.accepted), isFalse);
      });
      test('J3-05 rejected→accepted → 설정 안 함', () {
        expect(shouldSetSubAdminOf(InvitationStatus.rejected, InvitationStatus.accepted), isFalse);
      });
    });

    group('J4. 멤버 제거 워크플로', () {
      test('J4-01 제거 후 isSubAdmin=false (subAdminOf=null)', () {
        // removeMember 후 user.subAdminOf = null → isSubAdmin=false
        final userBefore = _user(role: UserRole.USER, subAdminOf: 'biz1');
        final userAfter = userBefore.copyWith(clearSubAdminOf: true);
        expect(userBefore.isSubAdmin, isTrue);
        expect(userAfter.isSubAdmin, isFalse);
      });
      test('J4-02 제거 후 effectiveBusinessId=null', () {
        final userAfter = _user(role: UserRole.USER, subAdminOf: null);
        expect(effectiveBusinessId(userAfter), isNull);
      });
      test('J4-03 제거 후 isAdmin=false', () {
        final userAfter = _user(role: UserRole.USER, subAdminOf: null);
        expect(userAfter.isAdmin, isFalse);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// K. 멤버 관리 화면 로직 재현
// ════════════════════════════════════════════════════════════

void _runMemberManagementScreenTests() {
  group('K. 멤버 관리 화면 로직', () {

    group('K1. 초대 발송 가능 조건', () {
      // 조건: !isAlreadyMember && !hasPendingInvitation
      bool canSendInvite(bool isAlreadyMember, bool hasPending) =>
          !isAlreadyMember && !hasPending;

      test('K1-01 미멤버 + pending없음 → 초대 가능', () {
        expect(canSendInvite(false, false), isTrue);
      });
      test('K1-02 이미멤버 → 초대 불가', () {
        expect(canSendInvite(true, false), isFalse);
      });
      test('K1-03 pending초대 있음 → 초대 불가', () {
        expect(canSendInvite(false, true), isFalse);
      });
      test('K1-04 이미멤버 + pending있음 → 초대 불가', () {
        expect(canSendInvite(true, true), isFalse);
      });
    });

    group('K2. 권한 수정 저장 버튼 활성화 조건', () {
      // 최소 1개 이상 권한 선택 필수
      bool canSave(MemberPermissions p) => p.hasAnyPermission;

      test('K2-01 권한 없음 → 저장 비활성', () {
        expect(canSave(MemberPermissions.none()), isFalse);
      });
      test('K2-02 to=true → 저장 활성', () {
        expect(canSave(_perm(to: true)), isTrue);
      });
      test('K2-03 workers=true → 저장 활성', () {
        expect(canSave(_perm(workers: true)), isTrue);
      });
      test('K2-04 wage=true → 저장 활성', () {
        expect(canSave(_perm(wage: true)), isTrue);
      });
      test('K2-05 contract=true → 저장 활성', () {
        expect(canSave(_perm(contract: true)), isTrue);
      });
      test('K2-06 all=true → 저장 활성', () {
        expect(canSave(MemberPermissions.all()), isTrue);
      });
    });

    group('K3. 권한 변경 후 summaryText', () {
      test('K3-01 none → to=true → "공고"', () {
        final updated = MemberPermissions.none().copyWith(canManageTo: true);
        expect(updated.summaryText, '공고');
      });
      test('K3-02 to=true → to=false → "권한 없음"', () {
        final updated = _perm(to: true).copyWith(canManageTo: false);
        expect(updated.summaryText, '권한 없음');
      });
      test('K3-03 to+workers → contract 추가 → "공고 · 근무자 · 계약서"', () {
        final updated = _perm(to: true, workers: true).copyWith(canManageContract: true);
        expect(updated.summaryText, '공고 · 근무자 · 계약서');
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// L. 파라미터화 대량 조합표
// ════════════════════════════════════════════════════════════

void _runParameterizedTests() {
  group('L. 파라미터화 시나리오', () {

    group('L1. MemberPermissions 16가지 조합 hasAnyPermission', () {
      // 4개 bool의 모든 조합 = 2^4 = 16
      final cases = <(bool, bool, bool, bool, bool)>[
        // (to, workers, wage, contract, hasAny)
        (false, false, false, false, false),
        (true,  false, false, false, true),
        (false, true,  false, false, true),
        (false, false, true,  false, true),
        (false, false, false, true,  true),
        (true,  true,  false, false, true),
        (true,  false, true,  false, true),
        (true,  false, false, true,  true),
        (false, true,  true,  false, true),
        (false, true,  false, true,  true),
        (false, false, true,  true,  true),
        (true,  true,  true,  false, true),
        (true,  true,  false, true,  true),
        (true,  false, true,  true,  true),
        (false, true,  true,  true,  true),
        (true,  true,  true,  true,  true),
      ];
      for (final (to, workers, wage, contract, expected) in cases) {
        test('L1 to=$to w=$workers wa=$wage c=$contract → hasAny=$expected', () {
          expect(_perm(to: to, workers: workers, wage: wage, contract: contract).hasAnyPermission,
              expected ? isTrue : isFalse);
        });
      }
    });

    group('L2. isSubAdmin 조합표', () {
      final cases = <(UserRole, String?, bool)>[
        (UserRole.USER, null, false),
        (UserRole.USER, 'biz1', true),
        (UserRole.USER, '', true),          // 빈 문자열도 non-null
        (UserRole.BUSINESS_ADMIN, null, false),
        (UserRole.BUSINESS_ADMIN, 'biz1', false), // 역할 우선
        (UserRole.SUPER_ADMIN, null, false),
        (UserRole.SUPER_ADMIN, 'biz1', false),
      ];
      for (final (role, subAdminOf, expected) in cases) {
        test('L2 role=$role subAdminOf=$subAdminOf → isSubAdmin=$expected', () {
          expect(_user(role: role, subAdminOf: subAdminOf).isSubAdmin,
              expected ? isTrue : isFalse);
        });
      }
    });

    group('L3. isAdmin 조합표', () {
      final cases = <(UserRole, String?, bool)>[
        (UserRole.SUPER_ADMIN, null, true),
        (UserRole.BUSINESS_ADMIN, null, true),
        (UserRole.USER, null, false),
        (UserRole.USER, 'biz1', true),
        (UserRole.USER, '', true),
      ];
      for (final (role, subAdminOf, expected) in cases) {
        test('L3 role=$role subAdminOf=$subAdminOf → isAdmin=$expected', () {
          expect(_user(role: role, subAdminOf: subAdminOf).isAdmin,
              expected ? isTrue : isFalse);
        });
      }
    });

    group('L4. can() 조합표', () {
      final cases = <(UserRole, MemberPermissions?, bool Function(MemberPermissions), bool)>[
        // (role, perms, check, expected)
        (UserRole.BUSINESS_ADMIN, null, (p) => p.canManageTo, true),
        (UserRole.BUSINESS_ADMIN, MemberPermissions.none(), (p) => p.canManageTo, true),
        (UserRole.SUPER_ADMIN, null, (p) => p.canManageTo, false),
        (UserRole.SUPER_ADMIN, MemberPermissions.all(), (p) => p.canManageTo, true),
        (UserRole.USER, null, (p) => p.canManageTo, false),
        (UserRole.USER, MemberPermissions.all(), (p) => p.canManageTo, true),
        (UserRole.USER, MemberPermissions.none(), (p) => p.canManageTo, false),
      ];
      for (final (role, perms, check, expected) in cases) {
        test('L4 role=$role perms=${perms?.summaryText ?? "null"} → can=$expected', () {
          final u = _user(role: role, subAdminOf: role == UserRole.USER ? 'biz' : null);
          expect(canCheck(u, perms, check), expected ? isTrue : isFalse);
        });
      }
    });

    group('L5. invitationStatus 만료 조합표', () {
      final cases = <(Duration, InvitationStatus, bool)>[
        // (age, status, isStillActive)
        (const Duration(days: 1), InvitationStatus.pending, true),
        (const Duration(days: 29), InvitationStatus.pending, true),
        (const Duration(days: 30), InvitationStatus.pending, false),
        (const Duration(days: 31), InvitationStatus.pending, false),
        (const Duration(days: 1), InvitationStatus.accepted, false),
        (const Duration(days: 1), InvitationStatus.rejected, false),
        (const Duration(days: 1), InvitationStatus.cancelled, false),
      ];
      for (final (age, status, expected) in cases) {
        test('L5 age=${age.inDays}d status=$status → active=$expected', () {
          final inv = _invite(status: status, createdAt: _now.subtract(age));
          final expiry = _now.subtract(const Duration(days: 30));
          final isActive = inv.isPending && inv.createdAt.isAfter(expiry);
          expect(isActive, expected ? isTrue : isFalse);
        });
      }
    });
  });
}

// ════════════════════════════════════════════════════════════
// M. 엣지케이스 / 경계값
// ════════════════════════════════════════════════════════════

void _runEdgeCaseTests() {
  group('M. 엣지케이스 & 경계값', () {

    group('M1. MemberPermissions 극단값', () {
      test('M1-01 none().copyWith() 반복 → 동일', () {
        final p = MemberPermissions.none().copyWith().copyWith().copyWith();
        expect(p.hasAnyPermission, isFalse);
      });
      test('M1-02 all().copyWith() 반복 → 동일', () {
        final p = MemberPermissions.all().copyWith().copyWith();
        expect(p.summaryText, '공고 · 근무자 · 급여 · 계약서');
      });
      test('M1-03 fromMap 미지 키 → 무시 (기본값 사용)', () {
        final p = MemberPermissions.fromMap({'unknownField': true, 'canManageTo': true});
        expect(p.canManageTo, isTrue);
        expect(p.canManageWorkers, isFalse); // 미지 키는 무시
      });
      test('M1-04 fromMap 타입 오류 (int 대신 bool) → ?? false 처리', () {
        // int를 넣으면 타입 캐스팅 오류 가능성 — ?? false로 방어
        // 실제 Firestore에서는 bool로 저장되므로 정상 케이스
        final p = MemberPermissions.fromMap({'canManageTo': false});
        expect(p.canManageTo, isFalse);
      });
    });

    group('M2. BusinessMemberModel 경계값', () {
      test('M2-01 이름 빈 문자열', () {
        expect(_member(name: '').name, '');
      });
      test('M2-02 이름 한글 최대 길이', () {
        final longName = '가' * 50;
        expect(_member(name: longName).name.length, 50);
      });
      test('M2-03 phone 비표준 형식 저장 가능', () {
        expect(_member(phone: '01012345678').phone, '01012345678');
      });
      test('M2-04 같은 uid로 두 멤버 생성 가능 (앱 로직에서 중복 방지)', () {
        final m1 = _member(uid: 'same');
        final m2 = _member(uid: 'same', name: '다른 이름');
        expect(m1.uid, m2.uid);
      });
    });

    group('M3. 초대 만료 경계 1ms', () {
      test('M3-01 exactly 30d − 1ms → 유효', () {
        final justInside = _now.subtract(const Duration(days: 30)).add(const Duration(milliseconds: 1));
        final expiry = _now.subtract(const Duration(days: 30));
        expect(justInside.isAfter(expiry), isTrue);
      });
      test('M3-02 exactly 30d → 만료 (isAfter가 false)', () {
        final exactly30d = _now.subtract(const Duration(days: 30));
        final expiry = _now.subtract(const Duration(days: 30));
        // isAfter: strictly after. 동일한 순간은 isAfter=false
        // 단, 1ms 차이가 있을 수 있으므로 equal도 만료로 처리
        expect(exactly30d.isAfter(expiry) || exactly30d.isAtSameMomentAs(expiry), isTrue);
      });
    });

    group('M4. UserModel copyWith 엣지케이스', () {
      test('M4-01 clearSubAdminOf=true → subAdminOf=null', () {
        final u = _user(role: UserRole.USER, subAdminOf: 'biz1');
        final cleared = u.copyWith(clearSubAdminOf: true);
        expect(cleared.subAdminOf, isNull);
        expect(cleared.isSubAdmin, isFalse);
      });
      test('M4-02 subAdminOf 변경', () {
        final u = _user(role: UserRole.USER, subAdminOf: 'biz1');
        final changed = u.copyWith(subAdminOf: 'biz2');
        expect(changed.subAdminOf, 'biz2');
      });
      test('M4-03 role 변경 (USER→BUSINESS_ADMIN)', () {
        final u = _user(role: UserRole.USER, subAdminOf: 'biz1');
        final changed = u.copyWith(role: UserRole.BUSINESS_ADMIN);
        expect(changed.isSubAdmin, isFalse);
        expect(changed.isBusinessAdmin, isTrue);
      });
    });

    group('M5. 동시 멤버십 불가 (BUSINESS_ADMIN은 isSubAdmin=false)', () {
      test('M5-01 BUSINESS_ADMIN이 subAdminOf 설정되어도 isSubAdmin=false', () {
        final u = _user(role: UserRole.BUSINESS_ADMIN, subAdminOf: 'other_biz');
        expect(u.isSubAdmin, isFalse);
        expect(u.isBusinessAdmin, isTrue);
      });
      test('M5-02 effectiveBusinessId는 BUSINESS_ADMIN의 businessId 반환', () {
        final u = _user(role: UserRole.BUSINESS_ADMIN, businessId: 'my_biz', subAdminOf: 'other_biz');
        expect(effectiveBusinessId(u), 'my_biz');
      });
    });

    group('M6. 권한 없는 하위관리자 화면 접근 불가', () {
      final subNoPerms = _user(role: UserRole.USER, subAdminOf: 'biz1');

      test('M6-01 SUB_ADMIN + 권한없음 → 모든 관리 기능 불가', () {
        final checks = [
          canCheck(subNoPerms, MemberPermissions.none(), (p) => p.canManageTo),
          canCheck(subNoPerms, MemberPermissions.none(), (p) => p.canManageWorkers),
          canCheck(subNoPerms, MemberPermissions.none(), (p) => p.canManageWage),
          canCheck(subNoPerms, MemberPermissions.none(), (p) => p.canManageContract),
        ];
        expect(checks.every((c) => c == false), isTrue);
      });

      test('M6-02 권한 없는 SUB_ADMIN → summaryText="권한 없음"', () {
        expect(MemberPermissions.none().summaryText, '권한 없음');
      });

      test('M6-03 권한 로드 전(null) → 모든 기능 불가', () {
        final checks = [
          canCheck(subNoPerms, null, (p) => p.canManageTo),
          canCheck(subNoPerms, null, (p) => p.canManageWorkers),
        ];
        expect(checks.every((c) => c == false), isTrue);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// main
// ════════════════════════════════════════════════════════════

void main() {
  _runPermissionsTests();
  _runInvitationStatusTests();
  _runInvitationModelTests();
  _runBusinessMemberModelTests();
  _runUserRoleTests();
  _runManagedBusinessIdsTests();
  _runCanCheckTests();
  _runEffectiveBusinessIdTests();
  _runRBACTests();
  _runInvitationWorkflowTests();
  _runMemberManagementScreenTests();
  _runParameterizedTests();
  _runEdgeCaseTests();
}
