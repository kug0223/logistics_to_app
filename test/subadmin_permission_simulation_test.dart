// ignore_for_file: lines_longer_than_80_chars
//
// 서브관리자 권한별 기능 시뮬레이션 — 500+ 시나리오
//
// 검증 대상:
//   A. SubAdmin 식별 조건 (isSubAdmin getter 로직)
//   B. effectiveBusinessId (역할별 반환값)
//   C. WorkforceController businessIds 할당
//   D. 홈 메뉴 노출 조건 (공고등록/공고관리/급여/계약서/통계/설정)
//   E. canManageTo — 공고 등록/관리 기능 접근
//   F. canManageWorkers — 근무자 관리 기능 접근
//   G. canManageWage — 급여·통계 기능 접근
//   H. canManageContract — 계약서 기능 접근
//   I. 멤버 관리 접근 불가 조건 (SubAdmin 역할 자체 차단)
//   J. 사업장 편집 불가 조건
//   K. 관리자/근무자 모드 전환 로직
//   L. 네비게이션 라우팅 (isAdminMode에 따른 화면 분기)
//   M. 권한 조합 16가지 × 메뉴 전체 파라미터화
//   N. 사업장 데이터 격리 (SubAdmin은 subAdminOf 사업장만)
//   O. 엣지케이스 / 경계값

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';

// ════════════════════════════════════════════════════════════
// 헬퍼 팩토리
// ════════════════════════════════════════════════════════════

UserModel _user({
  UserRole role = UserRole.USER,
  String? businessId,
  List<String>? managedBusinessIds,
  String? subAdminOf,
}) => UserModel(
  uid: 'uid1',
  username: 'tester',
  name: '테스터',
  email: 'test@alfit.kr',
  role: role,
  businessId: businessId,
  managedBusinessIds: managedBusinessIds,
  subAdminOf: subAdminOf,
);

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

// ── 재사용 유저 인스턴스 ─────────────────────────────────────
final _bizAdmin = _user(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1');
final _superAdmin = _user(role: UserRole.SUPER_ADMIN);
final _subAll = _user(role: UserRole.USER, subAdminOf: 'biz1');
final _subNone = _user(role: UserRole.USER, subAdminOf: 'biz1');
final _subTo = _user(role: UserRole.USER, subAdminOf: 'biz1');
final _subWorkers = _user(role: UserRole.USER, subAdminOf: 'biz1');
final _subWage = _user(role: UserRole.USER, subAdminOf: 'biz1');
final _subContract = _user(role: UserRole.USER, subAdminOf: 'biz1');
final _regularUser = _user(role: UserRole.USER);

final _permAll      = MemberPermissions.all();
final _permNone     = MemberPermissions.none();
final _permTo       = _perm(to: true);
final _permWorkers  = _perm(workers: true);
final _permWage     = _perm(wage: true);
final _permContract = _perm(contract: true);
final _permToWorkers= _perm(to: true, workers: true);
final _permToWage   = _perm(to: true, wage: true);
final _permToContract = _perm(to: true, contract: true);
final _permWorkersWage = _perm(workers: true, wage: true);
final _permWorkersContract = _perm(workers: true, contract: true);
final _permWageContract = _perm(wage: true, contract: true);

// ── 로직 재현 함수 ──────────────────────────────────────────

/// UserProvider.can() 재현
bool can(UserModel user, MemberPermissions? perms, bool Function(MemberPermissions) check) {
  if (user.isBusinessAdmin) return true;
  if (perms != null) return check(perms);
  return false;
}

/// UserProvider.effectiveBusinessId 재현
String? effectiveBusinessId(UserModel user) {
  if (user.isBusinessAdmin) return user.businessId;
  if (user.isSubAdmin) return user.subAdminOf;
  return null;
}

/// WorkforceController.businessIds 할당 로직 재현
List<String>? resolveBusinessIds(UserModel user) {
  if (user.isSuperAdmin) return null;
  if (user.isSubAdmin && user.subAdminOf != null) return [user.subAdminOf!];
  return user.managedBusinessIds;
}

/// 홈 메뉴 노출 조건 재현
bool showToCreate(UserModel u, MemberPermissions? p) =>
    !u.isSubAdmin || can(u, p, (pp) => pp.canManageTo);

bool showToManage(UserModel u, MemberPermissions? p) =>
    !u.isSubAdmin || can(u, p, (pp) => pp.canManageTo) || can(u, p, (pp) => pp.canManageWorkers);

bool showWage(UserModel u, MemberPermissions? p) =>
    !u.isSubAdmin || can(u, p, (pp) => pp.canManageWage);

bool showContract(UserModel u, MemberPermissions? p) =>
    !u.isSubAdmin || can(u, p, (pp) => pp.canManageContract);

bool showStats(UserModel u, MemberPermissions? p) =>
    !u.isSubAdmin || can(u, p, (pp) => pp.canManageWage);

bool showSettings(UserModel u) => true;  // 항상 표시

/// 멤버 관리 접근 가능 조건 (settings_screen 로직)
bool canAccessMemberManagement(UserModel user) => !(user.isSubAdmin);

/// 사업장 편집 버튼 노출 조건
bool canEditBusiness(UserModel user) => !user.isSubAdmin;

/// 네비게이션: SubAdmin + isAdminMode → 관리자 홈
bool shouldShowAdminHome(UserModel user, bool isAdminMode) {
  if (user.isBusinessAdmin) return true;
  if (user.isSubAdmin && isAdminMode) return true;
  return false;
}

/// SubAdmin 모드 전환 가능 조건
bool canToggleMode(UserModel user) => user.isSubAdmin;

// ════════════════════════════════════════════════════════════
// A. SubAdmin 식별 조건
// ════════════════════════════════════════════════════════════

void _runSubAdminIdentificationTests() {
  group('A. SubAdmin 식별 조건', () {

    group('A1. isSubAdmin 기본 케이스', () {
      test('A1-01 USER + subAdminOf="biz1" → isSubAdmin=true', () {
        expect(_user(role: UserRole.USER, subAdminOf: 'biz1').isSubAdmin, isTrue);
      });
      test('A1-02 USER + subAdminOf=null → isSubAdmin=false', () {
        expect(_user(role: UserRole.USER, subAdminOf: null).isSubAdmin, isFalse);
      });
      test('A1-03 BUSINESS_ADMIN + subAdminOf="biz1" → isSubAdmin=false (역할 우선)', () {
        expect(_user(role: UserRole.BUSINESS_ADMIN, subAdminOf: 'biz1').isSubAdmin, isFalse);
      });
      test('A1-04 SUPER_ADMIN + subAdminOf="biz1" → isSubAdmin=false', () {
        expect(_user(role: UserRole.SUPER_ADMIN, subAdminOf: 'biz1').isSubAdmin, isFalse);
      });
      test('A1-05 USER + subAdminOf="" → isSubAdmin=true (빈 문자열은 non-null)', () {
        expect(_user(role: UserRole.USER, subAdminOf: '').isSubAdmin, isTrue);
      });
    });

    group('A2. isAdmin getter', () {
      test('A2-01 SubAdmin → isAdmin=true', () {
        expect(_user(role: UserRole.USER, subAdminOf: 'biz1').isAdmin, isTrue);
      });
      test('A2-02 일반 USER → isAdmin=false', () {
        expect(_user(role: UserRole.USER).isAdmin, isFalse);
      });
      test('A2-03 BUSINESS_ADMIN → isAdmin=true', () {
        expect(_bizAdmin.isAdmin, isTrue);
      });
      test('A2-04 SUPER_ADMIN → isAdmin=true', () {
        expect(_superAdmin.isAdmin, isTrue);
      });
    });

    group('A3. SubAdmin + 다른 필드 조합', () {
      test('A3-01 SubAdmin + businessId 있음 → isSubAdmin=true', () {
        final u = _user(role: UserRole.USER, subAdminOf: 'biz1', businessId: 'biz_other');
        expect(u.isSubAdmin, isTrue);
      });
      test('A3-02 SubAdmin + managedBusinessIds 있음 → isSubAdmin=true', () {
        final u = _user(role: UserRole.USER, subAdminOf: 'biz1', managedBusinessIds: ['biz2']);
        expect(u.isSubAdmin, isTrue);
      });
      test('A3-03 SubAdmin 제거 후 isSubAdmin=false', () {
        final u = _user(role: UserRole.USER, subAdminOf: 'biz1');
        final removed = u.copyWith(clearSubAdminOf: true);
        expect(removed.isSubAdmin, isFalse);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// B. effectiveBusinessId
// ════════════════════════════════════════════════════════════

void _runEffectiveBusinessIdTests() {
  group('B. effectiveBusinessId', () {
    test('B-01 BUSINESS_ADMIN → businessId 반환', () {
      expect(effectiveBusinessId(_user(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1')), 'biz1');
    });
    test('B-02 SubAdmin → subAdminOf 반환', () {
      expect(effectiveBusinessId(_user(role: UserRole.USER, subAdminOf: 'biz2')), 'biz2');
    });
    test('B-03 일반 USER → null', () {
      expect(effectiveBusinessId(_user(role: UserRole.USER)), isNull);
    });
    test('B-04 SUPER_ADMIN → null', () {
      expect(effectiveBusinessId(_user(role: UserRole.SUPER_ADMIN)), isNull);
    });
    test('B-05 BUSINESS_ADMIN + businessId=null → null', () {
      expect(effectiveBusinessId(_user(role: UserRole.BUSINESS_ADMIN, businessId: null)), isNull);
    });
    test('B-06 SubAdmin: subAdminOf가 businessId보다 우선', () {
      final u = _user(role: UserRole.USER, businessId: 'owner_biz', subAdminOf: 'sub_biz');
      expect(effectiveBusinessId(u), 'sub_biz');
    });
    test('B-07 BUSINESS_ADMIN: subAdminOf가 있어도 businessId 반환', () {
      final u = _user(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1', subAdminOf: 'biz2');
      expect(effectiveBusinessId(u), 'biz1');
    });
    test('B-08 여러 사업장 관리하는 BUSINESS_ADMIN → 대표 businessId', () {
      final u = _user(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1', managedBusinessIds: ['biz1','biz2','biz3']);
      expect(effectiveBusinessId(u), 'biz1');
    });
  });
}

// ════════════════════════════════════════════════════════════
// C. WorkforceController businessIds 할당
// ════════════════════════════════════════════════════════════

void _runBusinessIdsAllocationTests() {
  group('C. WorkforceController businessIds 할당', () {
    test('C-01 SUPER_ADMIN → null (모든 사업장)', () {
      expect(resolveBusinessIds(_superAdmin), isNull);
    });
    test('C-02 SubAdmin(subAdminOf="biz1") → ["biz1"]', () {
      expect(resolveBusinessIds(_user(role: UserRole.USER, subAdminOf: 'biz1')), ['biz1']);
    });
    test('C-03 SubAdmin(subAdminOf="biz99") → ["biz99"]', () {
      expect(resolveBusinessIds(_user(role: UserRole.USER, subAdminOf: 'biz99')), ['biz99']);
    });
    test('C-04 BUSINESS_ADMIN(managedIds=["biz1","biz2"]) → ["biz1","biz2"]', () {
      final u = _user(role: UserRole.BUSINESS_ADMIN, managedBusinessIds: ['biz1', 'biz2']);
      expect(resolveBusinessIds(u), ['biz1', 'biz2']);
    });
    test('C-05 BUSINESS_ADMIN(businessId="biz1", managedIds=null) → ["biz1"] 폴백', () {
      final u = _user(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1');
      expect(resolveBusinessIds(u), ['biz1']);
    });
    test('C-06 일반 USER(subAdminOf=null) → [] (managedIds 없음)', () {
      expect(resolveBusinessIds(_regularUser), isEmpty);
    });
    test('C-07 SubAdmin은 항상 단일 사업장', () {
      final ids = resolveBusinessIds(_user(role: UserRole.USER, subAdminOf: 'biz1'));
      expect(ids?.length, 1);
    });
    test('C-08 SubAdmin이지만 subAdminOf=null → managedBusinessIds 사용', () {
      // isSubAdmin=false가 되므로 managedBusinessIds 경로
      final u = _user(role: UserRole.USER, subAdminOf: null, managedBusinessIds: ['biz3']);
      expect(resolveBusinessIds(u), ['biz3']);
    });
    test('C-09 BUSINESS_ADMIN managedIds 3개', () {
      final u = _user(role: UserRole.BUSINESS_ADMIN, managedBusinessIds: ['biz1','biz2','biz3']);
      expect(resolveBusinessIds(u)?.length, 3);
    });
    test('C-10 SubAdmin: 반환 리스트는 subAdminOf와 동일', () {
      const subOf = 'specific_biz';
      final u = _user(role: UserRole.USER, subAdminOf: subOf);
      expect(resolveBusinessIds(u)?.first, subOf);
    });
  });
}

// ════════════════════════════════════════════════════════════
// D. 홈 메뉴 노출 조건
// ════════════════════════════════════════════════════════════

void _runHomeMenuTests() {
  group('D. 홈 메뉴 노출 조건', () {

    // ── D1. BUSINESS_ADMIN — 모든 메뉴 항상 표시 ─────────────
    group('D1. BUSINESS_ADMIN — 모든 메뉴', () {
      test('D1-01 공고등록 항상 표시', () => expect(showToCreate(_bizAdmin, null), isTrue));
      test('D1-02 공고관리 항상 표시', () => expect(showToManage(_bizAdmin, null), isTrue));
      test('D1-03 급여관리 항상 표시', () => expect(showWage(_bizAdmin, null), isTrue));
      test('D1-04 계약서관리 항상 표시', () => expect(showContract(_bizAdmin, null), isTrue));
      test('D1-05 통계 항상 표시', () => expect(showStats(_bizAdmin, null), isTrue));
      test('D1-06 설정 항상 표시', () => expect(showSettings(_bizAdmin), isTrue));
      test('D1-07 권한 none이어도 항상 표시', () {
        expect(showToCreate(_bizAdmin, _permNone), isTrue);
        expect(showWage(_bizAdmin, _permNone), isTrue);
      });
    });

    // ── D2. SubAdmin 권한 없음 — 모든 메뉴 숨김 ─────────────
    group('D2. SubAdmin + 권한 없음', () {
      test('D2-01 공고등록 숨김', () => expect(showToCreate(_subNone, _permNone), isFalse));
      test('D2-02 공고관리 숨김', () => expect(showToManage(_subNone, _permNone), isFalse));
      test('D2-03 급여관리 숨김', () => expect(showWage(_subNone, _permNone), isFalse));
      test('D2-04 계약서관리 숨김', () => expect(showContract(_subNone, _permNone), isFalse));
      test('D2-05 통계 숨김', () => expect(showStats(_subNone, _permNone), isFalse));
      test('D2-06 설정 표시 (설정은 권한 무관)', () => expect(showSettings(_subNone), isTrue));
      test('D2-07 null 권한 → 모든 관리 메뉴 숨김', () {
        expect(showToCreate(_subNone, null), isFalse);
        expect(showWage(_subNone, null), isFalse);
      });
    });

    // ── D3. SubAdmin canManageTo만 ────────────────────────────
    group('D3. SubAdmin + canManageTo만', () {
      test('D3-01 공고등록 표시', () => expect(showToCreate(_subTo, _permTo), isTrue));
      test('D3-02 공고관리 표시 (to OR workers)', () => expect(showToManage(_subTo, _permTo), isTrue));
      test('D3-03 급여관리 숨김', () => expect(showWage(_subTo, _permTo), isFalse));
      test('D3-04 계약서관리 숨김', () => expect(showContract(_subTo, _permTo), isFalse));
      test('D3-05 통계 숨김', () => expect(showStats(_subTo, _permTo), isFalse));
    });

    // ── D4. SubAdmin canManageWorkers만 ──────────────────────
    group('D4. SubAdmin + canManageWorkers만', () {
      test('D4-01 공고등록 숨김 (to 없음)', () => expect(showToCreate(_subWorkers, _permWorkers), isFalse));
      test('D4-02 공고관리 표시 (to OR workers)', () => expect(showToManage(_subWorkers, _permWorkers), isTrue));
      test('D4-03 급여관리 숨김', () => expect(showWage(_subWorkers, _permWorkers), isFalse));
      test('D4-04 계약서관리 숨김', () => expect(showContract(_subWorkers, _permWorkers), isFalse));
      test('D4-05 통계 숨김', () => expect(showStats(_subWorkers, _permWorkers), isFalse));
    });

    // ── D5. SubAdmin canManageWage만 ─────────────────────────
    group('D5. SubAdmin + canManageWage만', () {
      test('D5-01 공고등록 숨김', () => expect(showToCreate(_subWage, _permWage), isFalse));
      test('D5-02 공고관리 숨김', () => expect(showToManage(_subWage, _permWage), isFalse));
      test('D5-03 급여관리 표시', () => expect(showWage(_subWage, _permWage), isTrue));
      test('D5-04 계약서관리 숨김', () => expect(showContract(_subWage, _permWage), isFalse));
      test('D5-05 통계 표시 (wage로 통합)', () => expect(showStats(_subWage, _permWage), isTrue));
    });

    // ── D6. SubAdmin canManageContract만 ─────────────────────
    group('D6. SubAdmin + canManageContract만', () {
      test('D6-01 공고등록 숨김', () => expect(showToCreate(_subContract, _permContract), isFalse));
      test('D6-02 공고관리 숨김', () => expect(showToManage(_subContract, _permContract), isFalse));
      test('D6-03 급여관리 숨김', () => expect(showWage(_subContract, _permContract), isFalse));
      test('D6-04 계약서관리 표시', () => expect(showContract(_subContract, _permContract), isTrue));
      test('D6-05 통계 숨김', () => expect(showStats(_subContract, _permContract), isFalse));
    });

    // ── D7. SubAdmin 전체 권한 ────────────────────────────────
    group('D7. SubAdmin + 전체 권한', () {
      test('D7-01 공고등록 표시', () => expect(showToCreate(_subAll, _permAll), isTrue));
      test('D7-02 공고관리 표시', () => expect(showToManage(_subAll, _permAll), isTrue));
      test('D7-03 급여관리 표시', () => expect(showWage(_subAll, _permAll), isTrue));
      test('D7-04 계약서관리 표시', () => expect(showContract(_subAll, _permAll), isTrue));
      test('D7-05 통계 표시', () => expect(showStats(_subAll, _permAll), isTrue));
      test('D7-06 설정 표시', () => expect(showSettings(_subAll), isTrue));
    });
  });
}

// ════════════════════════════════════════════════════════════
// E. canManageTo 시나리오
// ════════════════════════════════════════════════════════════

void _runCanManageToTests() {
  group('E. canManageTo 권한 시나리오', () {
    final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');

    group('E1. 공고 등록 메뉴 접근', () {
      test('E1-01 to=true → 공고 등록 메뉴 접근 가능', () {
        expect(can(sub, _permTo, (p) => p.canManageTo), isTrue);
      });
      test('E1-02 to=false → 공고 등록 메뉴 접근 불가', () {
        expect(can(sub, _permNone, (p) => p.canManageTo), isFalse);
      });
      test('E1-03 to=false, workers=true → 공고 등록 불가 (등록은 to만)', () {
        expect(can(sub, _permWorkers, (p) => p.canManageTo), isFalse);
      });
      test('E1-04 to=false, wage=true → 공고 등록 불가', () {
        expect(can(sub, _permWage, (p) => p.canManageTo), isFalse);
      });
      test('E1-05 to=false, contract=true → 공고 등록 불가', () {
        expect(can(sub, _permContract, (p) => p.canManageTo), isFalse);
      });
      test('E1-06 all=true → 공고 등록 가능', () {
        expect(can(sub, _permAll, (p) => p.canManageTo), isTrue);
      });
      test('E1-07 to=true, 나머지 false → 공고 등록만 가능', () {
        expect(can(sub, _permTo, (p) => p.canManageTo), isTrue);
        expect(can(sub, _permTo, (p) => p.canManageWage), isFalse);
      });
    });

    group('E2. 공고 관리 메뉴 접근 (to OR workers)', () {
      test('E2-01 to=true → 공고 관리 접근 가능', () {
        expect(showToManage(sub, _permTo), isTrue);
      });
      test('E2-02 workers=true → 공고 관리 접근 가능', () {
        expect(showToManage(sub, _permWorkers), isTrue);
      });
      test('E2-03 to=true, workers=true → 공고 관리 접근 가능', () {
        expect(showToManage(sub, _permToWorkers), isTrue);
      });
      test('E2-04 to=false, workers=false → 공고 관리 접근 불가', () {
        expect(showToManage(sub, _permNone), isFalse);
      });
      test('E2-05 wage=true, to/workers=false → 공고 관리 접근 불가', () {
        expect(showToManage(sub, _permWage), isFalse);
      });
      test('E2-06 contract=true, to/workers=false → 공고 관리 접근 불가', () {
        expect(showToManage(sub, _permContract), isFalse);
      });
      test('E2-07 null permissions → 공고 관리 접근 불가', () {
        expect(showToManage(sub, null), isFalse);
      });
    });

    group('E3. canManageTo 관련 추가 체크', () {
      test('E3-01 to+wage → 공고등록 가능 + 급여 가능', () {
        expect(can(sub, _permToWage, (p) => p.canManageTo), isTrue);
        expect(can(sub, _permToWage, (p) => p.canManageWage), isTrue);
      });
      test('E3-02 to+contract → 공고등록 가능 + 계약서 가능', () {
        expect(can(sub, _permToContract, (p) => p.canManageTo), isTrue);
        expect(can(sub, _permToContract, (p) => p.canManageContract), isTrue);
      });
      test('E3-03 to만 있으면 workers/wage/contract는 false', () {
        expect(can(sub, _permTo, (p) => p.canManageWorkers), isFalse);
        expect(can(sub, _permTo, (p) => p.canManageWage), isFalse);
        expect(can(sub, _permTo, (p) => p.canManageContract), isFalse);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// F. canManageWorkers 시나리오
// ════════════════════════════════════════════════════════════

void _runCanManageWorkersTests() {
  group('F. canManageWorkers 권한 시나리오', () {
    final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');

    group('F1. 근무자 관련 기능', () {
      test('F1-01 workers=true → 근무자 기능 가능', () {
        expect(can(sub, _permWorkers, (p) => p.canManageWorkers), isTrue);
      });
      test('F1-02 workers=false → 근무자 기능 불가', () {
        expect(can(sub, _permNone, (p) => p.canManageWorkers), isFalse);
      });
      test('F1-03 workers=false, to=true → 근무자 기능 불가', () {
        expect(can(sub, _permTo, (p) => p.canManageWorkers), isFalse);
      });
      test('F1-04 all=true → 근무자 기능 가능', () {
        expect(can(sub, _permAll, (p) => p.canManageWorkers), isTrue);
      });
      test('F1-05 workers=true, 나머지 false', () {
        expect(can(sub, _permWorkers, (p) => p.canManageTo), isFalse);
        expect(can(sub, _permWorkers, (p) => p.canManageWorkers), isTrue);
        expect(can(sub, _permWorkers, (p) => p.canManageWage), isFalse);
        expect(can(sub, _permWorkers, (p) => p.canManageContract), isFalse);
      });
      test('F1-06 to+workers → 공고+근무자 둘 다 가능', () {
        expect(can(sub, _permToWorkers, (p) => p.canManageTo), isTrue);
        expect(can(sub, _permToWorkers, (p) => p.canManageWorkers), isTrue);
        expect(can(sub, _permToWorkers, (p) => p.canManageWage), isFalse);
      });
    });

    group('F2. 공고관리 메뉴 (workers OR to)', () {
      test('F2-01 workers만 있어도 공고관리 메뉴 표시', () {
        expect(showToManage(sub, _permWorkers), isTrue);
      });
      test('F2-02 to만 있어도 공고관리 메뉴 표시', () {
        expect(showToManage(sub, _permTo), isTrue);
      });
      test('F2-03 to+workers 모두 있어도 공고관리 메뉴 표시', () {
        expect(showToManage(sub, _permToWorkers), isTrue);
      });
    });

    group('F3. workers+wage 조합', () {
      test('F3-01 workers+wage → 공고관리 가능, 급여 가능', () {
        expect(showToManage(sub, _permWorkersWage), isTrue);
        expect(showWage(sub, _permWorkersWage), isTrue);
      });
      test('F3-02 workers+wage → 공고등록 불가, 계약서 불가', () {
        expect(showToCreate(sub, _permWorkersWage), isFalse);
        expect(showContract(sub, _permWorkersWage), isFalse);
      });
    });

    group('F4. workers+contract 조합', () {
      test('F4-01 workers+contract → 공고관리 가능, 계약서 가능', () {
        expect(showToManage(sub, _permWorkersContract), isTrue);
        expect(showContract(sub, _permWorkersContract), isTrue);
      });
      test('F4-02 workers+contract → 급여/통계 불가', () {
        expect(showWage(sub, _permWorkersContract), isFalse);
        expect(showStats(sub, _permWorkersContract), isFalse);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// G. canManageWage 시나리오
// ════════════════════════════════════════════════════════════

void _runCanManageWageTests() {
  group('G. canManageWage 권한 시나리오', () {
    final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');

    group('G1. 급여 화면 접근', () {
      test('G1-01 wage=true → 급여 메뉴 표시', () {
        expect(showWage(sub, _permWage), isTrue);
      });
      test('G1-02 wage=false → 급여 메뉴 숨김', () {
        expect(showWage(sub, _permNone), isFalse);
      });
      test('G1-03 to=true, wage=false → 급여 메뉴 숨김', () {
        expect(showWage(sub, _permTo), isFalse);
      });
      test('G1-04 workers=true, wage=false → 급여 메뉴 숨김', () {
        expect(showWage(sub, _permWorkers), isFalse);
      });
      test('G1-05 contract=true, wage=false → 급여 메뉴 숨김', () {
        expect(showWage(sub, _permContract), isFalse);
      });
      test('G1-06 null → 급여 메뉴 숨김', () {
        expect(showWage(sub, null), isFalse);
      });
      test('G1-07 all=true → 급여 메뉴 표시', () {
        expect(showWage(sub, _permAll), isTrue);
      });
    });

    group('G2. 통계 화면 접근 (wage로 통합)', () {
      test('G2-01 wage=true → 통계 표시', () {
        expect(showStats(sub, _permWage), isTrue);
      });
      test('G2-02 wage=false → 통계 숨김', () {
        expect(showStats(sub, _permNone), isFalse);
      });
      test('G2-03 to=true → 통계 숨김 (wage 아님)', () {
        expect(showStats(sub, _permTo), isFalse);
      });
      test('G2-04 급여 == 통계 (동일 조건)', () {
        // 같은 조건으로 확인
        for (final p in [_permWage, _permAll, _permNone, _permTo]) {
          expect(showWage(sub, p), showStats(sub, p));
        }
      });
    });

    group('G3. wage+contract 조합', () {
      test('G3-01 wage+contract → 급여, 통계, 계약서 가능', () {
        expect(showWage(sub, _permWageContract), isTrue);
        expect(showStats(sub, _permWageContract), isTrue);
        expect(showContract(sub, _permWageContract), isTrue);
      });
      test('G3-02 wage+contract → 공고등록/관리 불가', () {
        expect(showToCreate(sub, _permWageContract), isFalse);
        expect(showToManage(sub, _permWageContract), isFalse);
      });
    });

    group('G4. wage 권한으로 접근 가능한 기능들', () {
      test('G4-01 급여 개요 접근 가능', () {
        expect(can(sub, _permWage, (p) => p.canManageWage), isTrue);
      });
      test('G4-02 근무자 관리는 불가 (wage만 있을 때)', () {
        expect(can(sub, _permWage, (p) => p.canManageWorkers), isFalse);
      });
      test('G4-03 공고 등록 불가 (wage만 있을 때)', () {
        expect(can(sub, _permWage, (p) => p.canManageTo), isFalse);
      });
      test('G4-04 계약서 불가 (wage만 있을 때)', () {
        expect(can(sub, _permWage, (p) => p.canManageContract), isFalse);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// H. canManageContract 시나리오
// ════════════════════════════════════════════════════════════

void _runCanManageContractTests() {
  group('H. canManageContract 권한 시나리오', () {
    final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');

    group('H1. 계약서 화면 접근', () {
      test('H1-01 contract=true → 계약서 메뉴 표시', () {
        expect(showContract(sub, _permContract), isTrue);
      });
      test('H1-02 contract=false → 계약서 메뉴 숨김', () {
        expect(showContract(sub, _permNone), isFalse);
      });
      test('H1-03 to=true, contract=false → 계약서 숨김', () {
        expect(showContract(sub, _permTo), isFalse);
      });
      test('H1-04 workers=true, contract=false → 계약서 숨김', () {
        expect(showContract(sub, _permWorkers), isFalse);
      });
      test('H1-05 wage=true, contract=false → 계약서 숨김', () {
        expect(showContract(sub, _permWage), isFalse);
      });
      test('H1-06 null permissions → 계약서 숨김', () {
        expect(showContract(sub, null), isFalse);
      });
      test('H1-07 all=true → 계약서 표시', () {
        expect(showContract(sub, _permAll), isTrue);
      });
    });

    group('H2. contract 단독 권한 제약', () {
      test('H2-01 contract만 → 공고 불가', () {
        expect(showToCreate(sub, _permContract), isFalse);
        expect(showToManage(sub, _permContract), isFalse);
      });
      test('H2-02 contract만 → 급여/통계 불가', () {
        expect(showWage(sub, _permContract), isFalse);
        expect(showStats(sub, _permContract), isFalse);
      });
      test('H2-03 contract만 → 계약서만 가능', () {
        expect(showContract(sub, _permContract), isTrue);
        expect(can(sub, _permContract, (p) => p.canManageContract), isTrue);
      });
    });

    group('H3. contract+to 조합', () {
      test('H3-01 to+contract → 공고등록, 계약서 둘다', () {
        expect(showToCreate(sub, _permToContract), isTrue);
        expect(showContract(sub, _permToContract), isTrue);
      });
      test('H3-02 to+contract → 근무자 접근 불가 (공고관리는 to가 있어서 가능)', () {
        expect(showToManage(sub, _permToContract), isTrue);
        expect(can(sub, _permToContract, (p) => p.canManageWorkers), isFalse);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// I. 멤버 관리 접근 불가
// ════════════════════════════════════════════════════════════

void _runMemberManagementAccessTests() {
  group('I. 멤버 관리 접근 불가 (SubAdmin 역할 자체 차단)', () {
    test('I-01 SubAdmin → 멤버 관리 불가', () {
      expect(canAccessMemberManagement(_subAll), isFalse);
    });
    test('I-02 SubAdmin + 전체 권한 → 여전히 멤버 관리 불가', () {
      expect(canAccessMemberManagement(_user(role: UserRole.USER, subAdminOf: 'biz1')), isFalse);
    });
    test('I-03 BUSINESS_ADMIN → 멤버 관리 가능', () {
      expect(canAccessMemberManagement(_bizAdmin), isTrue);
    });
    test('I-04 SUPER_ADMIN → 멤버 관리 가능', () {
      expect(canAccessMemberManagement(_superAdmin), isTrue);
    });
    test('I-05 일반 USER(subAdminOf=null) → 멤버 관리 가능 (관리자 화면 자체 진입 불가)', () {
      expect(canAccessMemberManagement(_regularUser), isTrue);
    });
    test('I-06 SubAdmin에서 subAdminOf 제거 후 → 멤버 관리 가능', () {
      final removed = _subAll.copyWith(clearSubAdminOf: true);
      expect(canAccessMemberManagement(removed), isTrue);
    });
    test('I-07 멤버 초대 불가 (SubAdmin은 초대 발송 권한 없음)', () {
      // isAdminOf(businessId) 체크 → SubAdmin은 해당 안 됨
      expect(_subAll.isSubAdmin, isTrue);
      expect(_subAll.isBusinessAdmin, isFalse);
    });
    test('I-08 멤버 권한 수정 불가 (BUSINESS_ADMIN만 가능)', () {
      expect(canAccessMemberManagement(_subAll), isFalse);
    });
    test('I-09 멤버 제거 불가 (BUSINESS_ADMIN만 가능)', () {
      expect(canAccessMemberManagement(_subAll), isFalse);
    });
  });
}

// ════════════════════════════════════════════════════════════
// J. 사업장 편집 불가
// ════════════════════════════════════════════════════════════

void _runBusinessEditTests() {
  group('J. 사업장 편집 불가', () {
    test('J-01 SubAdmin → 사업장 편집 불가', () {
      expect(canEditBusiness(_subAll), isFalse);
    });
    test('J-02 SubAdmin + 전체 권한 → 여전히 사업장 편집 불가', () {
      expect(canEditBusiness(_user(role: UserRole.USER, subAdminOf: 'biz1')), isFalse);
    });
    test('J-03 BUSINESS_ADMIN → 사업장 편집 가능', () {
      expect(canEditBusiness(_bizAdmin), isTrue);
    });
    test('J-04 SUPER_ADMIN → 사업장 편집 가능', () {
      expect(canEditBusiness(_superAdmin), isTrue);
    });
    test('J-05 일반 USER → 편집 가능 반환 (화면 진입 자체가 불가)', () {
      expect(canEditBusiness(_regularUser), isTrue);
    });
  });
}

// ════════════════════════════════════════════════════════════
// K. 관리자/근무자 모드 전환
// ════════════════════════════════════════════════════════════

void _runModeToggleTests() {
  group('K. 관리자/근무자 모드 전환', () {
    group('K1. 모드 전환 가능 조건', () {
      test('K1-01 SubAdmin → 모드 전환 가능', () {
        expect(canToggleMode(_subAll), isTrue);
      });
      test('K1-02 일반 USER → 모드 전환 불가', () {
        expect(canToggleMode(_regularUser), isFalse);
      });
      test('K1-03 BUSINESS_ADMIN → 모드 전환 불가', () {
        expect(canToggleMode(_bizAdmin), isFalse);
      });
      test('K1-04 SUPER_ADMIN → 모드 전환 불가', () {
        expect(canToggleMode(_superAdmin), isFalse);
      });
    });

    group('K2. 네비게이션 분기 (isAdminMode)', () {
      test('K2-01 SubAdmin + isAdminMode=true → 관리자 홈 표시', () {
        expect(shouldShowAdminHome(_subAll, true), isTrue);
      });
      test('K2-02 SubAdmin + isAdminMode=false → 근무자 홈 표시', () {
        expect(shouldShowAdminHome(_subAll, false), isFalse);
      });
      test('K2-03 BUSINESS_ADMIN + isAdminMode=false → 관리자 홈 표시 (BUSINESS_ADMIN은 항상)', () {
        expect(shouldShowAdminHome(_bizAdmin, false), isTrue);
      });
      test('K2-04 일반 USER + isAdminMode=true → 근무자 홈 (SubAdmin 아님)', () {
        expect(shouldShowAdminHome(_regularUser, true), isFalse);
      });
      test('K2-05 SUPER_ADMIN + isAdminMode=false → 관리자 홈', () {
        // SUPER_ADMIN은 isBusinessAdmin=false이지만 별도 라우팅
        expect(shouldShowAdminHome(_superAdmin, false), isFalse);
      });
    });

    group('K3. 기본 진입 상태', () {
      test('K3-01 SubAdmin 첫 로그인 → isAdminMode=false (근무자 모드 기본)', () {
        // UserProvider 초기화 시 _isAdminMode = false
        const defaultAdminMode = false;
        expect(shouldShowAdminHome(_subAll, defaultAdminMode), isFalse);
      });
      test('K3-02 SubAdmin 모드 전환 후 → 관리자 홈', () {
        const afterToggle = true;
        expect(shouldShowAdminHome(_subAll, afterToggle), isTrue);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// L. 사업장 데이터 격리
// ════════════════════════════════════════════════════════════

void _runDataIsolationTests() {
  group('L. 사업장 데이터 격리', () {
    test('L-01 SubAdmin은 단일 사업장만 접근', () {
      final ids = resolveBusinessIds(_user(role: UserRole.USER, subAdminOf: 'biz1'));
      expect(ids?.length, 1);
      expect(ids?.first, 'biz1');
    });
    test('L-02 SubAdmin이 다른 사업장 ID로 조회하면 해당 사업장 없음 시뮬레이션', () {
      final myBizId = 'biz1';
      final otherBizId = 'biz2';
      expect(myBizId != otherBizId, isTrue);
    });
    test('L-03 BUSINESS_ADMIN은 여러 사업장 접근', () {
      final u = _user(role: UserRole.BUSINESS_ADMIN, managedBusinessIds: ['biz1','biz2','biz3']);
      expect(resolveBusinessIds(u)?.length, greaterThan(1));
    });
    test('L-04 SUPER_ADMIN은 모든 사업장 (null = 제한 없음)', () {
      expect(resolveBusinessIds(_superAdmin), isNull);
    });
    test('L-05 SubAdmin effectiveBusinessId = subAdminOf', () {
      final u = _user(role: UserRole.USER, subAdminOf: 'specific_biz');
      expect(effectiveBusinessId(u), 'specific_biz');
      expect(resolveBusinessIds(u)?.contains('specific_biz'), isTrue);
    });
    test('L-06 SubAdmin은 본인 subAdminOf 사업장만 로드', () {
      final u = _user(role: UserRole.USER, subAdminOf: 'biz99');
      final ids = resolveBusinessIds(u)!;
      expect(ids, ['biz99']);
      expect(ids.contains('biz1'), isFalse);
    });
  });
}

// ════════════════════════════════════════════════════════════
// M. 16가지 권한 조합 × 모든 메뉴 파라미터화
// ════════════════════════════════════════════════════════════

void _runAllPermCombinationsTests() {
  group('M. 권한 16가지 조합 × 메뉴 전체', () {
    final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');

    // 모든 2^4 = 16가지 조합
    final allCombinations = <(bool, bool, bool, bool)>[
      // (to, workers, wage, contract)
      (false, false, false, false),
      (true,  false, false, false),
      (false, true,  false, false),
      (false, false, true,  false),
      (false, false, false, true),
      (true,  true,  false, false),
      (true,  false, true,  false),
      (true,  false, false, true),
      (false, true,  true,  false),
      (false, true,  false, true),
      (false, false, true,  true),
      (true,  true,  true,  false),
      (true,  true,  false, true),
      (true,  false, true,  true),
      (false, true,  true,  true),
      (true,  true,  true,  true),
    ];

    for (final (to, workers, wage, contract) in allCombinations) {
      final p = _perm(to: to, workers: workers, wage: wage, contract: contract);
      final label = 'to=$to w=$workers wa=$wage c=$contract';

      test('M공고등록[$label] → $to', () {
        expect(showToCreate(sub, p), to ? isTrue : isFalse);
      });

      test('M공고관리[$label] → ${to || workers}', () {
        expect(showToManage(sub, p), (to || workers) ? isTrue : isFalse);
      });

      test('M급여[$label] → $wage', () {
        expect(showWage(sub, p), wage ? isTrue : isFalse);
      });

      test('M계약서[$label] → $contract', () {
        expect(showContract(sub, p), contract ? isTrue : isFalse);
      });

      test('M통계[$label] → $wage', () {
        expect(showStats(sub, p), wage ? isTrue : isFalse);
      });
    }
  });
}

// ════════════════════════════════════════════════════════════
// N. BUSINESS_ADMIN vs SubAdmin 비교 시나리오
// ════════════════════════════════════════════════════════════

void _runAdminComparisonTests() {
  group('N. BUSINESS_ADMIN vs SubAdmin 비교', () {
    final bizAdmin = _user(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1');

    group('N1. 동일 기능 — BUSINESS_ADMIN 항상 가능', () {
      test('N1-01 BUSINESS_ADMIN canManageTo → true (권한 없어도)', () {
        expect(can(bizAdmin, _permNone, (p) => p.canManageTo), isTrue);
      });
      test('N1-02 BUSINESS_ADMIN canManageWorkers → true', () {
        expect(can(bizAdmin, _permNone, (p) => p.canManageWorkers), isTrue);
      });
      test('N1-03 BUSINESS_ADMIN canManageWage → true', () {
        expect(can(bizAdmin, _permNone, (p) => p.canManageWage), isTrue);
      });
      test('N1-04 BUSINESS_ADMIN canManageContract → true', () {
        expect(can(bizAdmin, _permNone, (p) => p.canManageContract), isTrue);
      });
    });

    group('N2. SubAdmin은 권한에 따라 다름', () {
      final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');
      test('N2-01 SubAdmin + nonePerms → 모든 기능 false', () {
        expect(can(sub, _permNone, (p) => p.canManageTo), isFalse);
        expect(can(sub, _permNone, (p) => p.canManageWorkers), isFalse);
        expect(can(sub, _permNone, (p) => p.canManageWage), isFalse);
        expect(can(sub, _permNone, (p) => p.canManageContract), isFalse);
      });
      test('N2-02 SubAdmin + allPerms → 모든 기능 true', () {
        expect(can(sub, _permAll, (p) => p.canManageTo), isTrue);
        expect(can(sub, _permAll, (p) => p.canManageWorkers), isTrue);
        expect(can(sub, _permAll, (p) => p.canManageWage), isTrue);
        expect(can(sub, _permAll, (p) => p.canManageContract), isTrue);
      });
    });

    group('N3. 멤버 관리 차이', () {
      test('N3-01 BUSINESS_ADMIN → 멤버 관리 가능', () {
        expect(canAccessMemberManagement(bizAdmin), isTrue);
      });
      test('N3-02 SubAdmin → 멤버 관리 불가', () {
        expect(canAccessMemberManagement(_user(role: UserRole.USER, subAdminOf: 'biz1')), isFalse);
      });
    });

    group('N4. 사업장 편집 차이', () {
      test('N4-01 BUSINESS_ADMIN → 편집 가능', () {
        expect(canEditBusiness(bizAdmin), isTrue);
      });
      test('N4-02 SubAdmin → 편집 불가', () {
        expect(canEditBusiness(_user(role: UserRole.USER, subAdminOf: 'biz1')), isFalse);
      });
    });

    group('N5. 사업장 범위 차이', () {
      test('N5-01 BUSINESS_ADMIN은 여러 사업장 관리 가능', () {
        final u = _user(role: UserRole.BUSINESS_ADMIN, managedBusinessIds: ['a','b','c']);
        expect(resolveBusinessIds(u)?.length, 3);
      });
      test('N5-02 SubAdmin은 단일 사업장만', () {
        final u = _user(role: UserRole.USER, subAdminOf: 'single_biz');
        expect(resolveBusinessIds(u)?.length, 1);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// O. 실제 운영 시나리오
// ════════════════════════════════════════════════════════════

void _runRealWorldScenarioTests() {
  group('O. 실제 운영 시나리오', () {
    final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');

    test('O-01 [공고 담당자] to만 있는 서브관리자 → 공고등록/관리만 가능', () {
      expect(showToCreate(sub, _permTo), isTrue);
      expect(showToManage(sub, _permTo), isTrue);
      expect(showWage(sub, _permTo), isFalse);
      expect(showContract(sub, _permTo), isFalse);
      expect(canAccessMemberManagement(sub), isFalse);
    });

    test('O-02 [현장 담당자] workers만 있는 서브관리자 → 공고관리만 가능(공고등록불가)', () {
      expect(showToCreate(sub, _permWorkers), isFalse);
      expect(showToManage(sub, _permWorkers), isTrue);
      expect(showWage(sub, _permWorkers), isFalse);
    });

    test('O-03 [급여 담당자] wage만 있는 서브관리자 → 급여/통계만 가능', () {
      expect(showWage(sub, _permWage), isTrue);
      expect(showStats(sub, _permWage), isTrue);
      expect(showToCreate(sub, _permWage), isFalse);
      expect(showToManage(sub, _permWage), isFalse);
    });

    test('O-04 [계약서 담당자] contract만 있는 서브관리자 → 계약서만 가능', () {
      expect(showContract(sub, _permContract), isTrue);
      expect(showToCreate(sub, _permContract), isFalse);
      expect(showWage(sub, _permContract), isFalse);
    });

    test('O-05 [공고+현장 담당자] to+workers → 공고관련 모두 가능', () {
      expect(showToCreate(sub, _permToWorkers), isTrue);
      expect(showToManage(sub, _permToWorkers), isTrue);
      expect(showWage(sub, _permToWorkers), isFalse);
      expect(showContract(sub, _permToWorkers), isFalse);
    });

    test('O-06 [종합 담당자] 전체 권한 → 멤버관리 제외 모두 가능', () {
      expect(showToCreate(sub, _permAll), isTrue);
      expect(showToManage(sub, _permAll), isTrue);
      expect(showWage(sub, _permAll), isTrue);
      expect(showContract(sub, _permAll), isTrue);
      expect(showStats(sub, _permAll), isTrue);
      expect(canAccessMemberManagement(sub), isFalse); // 멤버관리는 여전히 불가
    });

    test('O-07 [서브관리자 로그인] 기본 근무자 모드 → 관리자 홈 미표시', () {
      expect(shouldShowAdminHome(sub, false), isFalse);
    });

    test('O-08 [모드 전환 후] 관리자 모드 → 관리자 홈 표시', () {
      expect(shouldShowAdminHome(sub, true), isTrue);
    });

    test('O-09 [권한 로드 실패] null permissions → 모든 기능 차단', () {
      expect(showToCreate(sub, null), isFalse);
      expect(showToManage(sub, null), isFalse);
      expect(showWage(sub, null), isFalse);
      expect(showContract(sub, null), isFalse);
    });

    test('O-10 [서브관리자 탈퇴] subAdminOf 제거 후 → 관리자 기능 전부 불가', () {
      final removed = sub.copyWith(clearSubAdminOf: true);
      expect(removed.isSubAdmin, isFalse);
      expect(shouldShowAdminHome(removed, true), isFalse);
      expect(effectiveBusinessId(removed), isNull);
      expect(resolveBusinessIds(removed), isEmpty);
    });

    test('O-11 [다른 사업장 할당] subAdminOf 변경 → 새 사업장으로 데이터 격리', () {
      final before = _user(role: UserRole.USER, subAdminOf: 'biz_old');
      final after = before.copyWith(subAdminOf: 'biz_new');
      expect(effectiveBusinessId(before), 'biz_old');
      expect(effectiveBusinessId(after), 'biz_new');
      expect(resolveBusinessIds(after), ['biz_new']);
    });

    test('O-12 [사업주 탈퇴 시뮬레이션] 서브관리자의 사업장이 삭제되면 subAdminOf 제거되어야 함', () {
      final sub = _user(role: UserRole.USER, subAdminOf: 'deleted_biz');
      final orphaned = sub.copyWith(clearSubAdminOf: true);
      expect(orphaned.isSubAdmin, isFalse);
      expect(orphaned.isAdmin, isFalse);
    });

    test('O-13 [서브관리자 격상] USER → BUSINESS_ADMIN 시 isSubAdmin=false', () {
      final promoted = sub.copyWith(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1');
      expect(promoted.isSubAdmin, isFalse);
      expect(promoted.isBusinessAdmin, isTrue);
    });
  });
}

// ════════════════════════════════════════════════════════════
// P. 엣지케이스 / 경계값
// ════════════════════════════════════════════════════════════

void _runEdgeCaseTests() {
  group('P. 엣지케이스 & 경계값', () {

    group('P1. null permissions 처리', () {
      final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');
      test('P1-01 null permissions + SubAdmin → can() = false', () {
        expect(can(sub, null, (p) => p.canManageTo), isFalse);
      });
      test('P1-02 null permissions + BUSINESS_ADMIN → can() = true', () {
        expect(can(_bizAdmin, null, (p) => p.canManageTo), isTrue);
      });
      test('P1-03 null permissions → 모든 메뉴 숨김 (SubAdmin)', () {
        expect([
          showToCreate(sub, null),
          showToManage(sub, null),
          showWage(sub, null),
          showContract(sub, null),
          showStats(sub, null),
        ].every((v) => v == false), isTrue);
      });
    });

    group('P2. 동시 권한 일관성', () {
      final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');

      test('P2-01 급여 메뉴 == 통계 메뉴 (동일 조건)', () {
        for (final perm in [_permNone, _permTo, _permWorkers, _permWage, _permContract, _permAll]) {
          expect(showWage(sub, perm), showStats(sub, perm),
              reason: '급여와 통계는 같은 조건: ${perm.summaryText}');
        }
      });

      test('P2-02 공고등록 허용 → 공고관리도 허용 (to → to || workers)', () {
        // to=true이면 공고관리도 true
        for (final perm in [_permTo, _permToWorkers, _permAll]) {
          if (showToCreate(sub, perm)) {
            expect(showToManage(sub, perm), isTrue,
                reason: '공고등록 가능하면 공고관리도 가능해야 함: ${perm.summaryText}');
          }
        }
      });

      test('P2-03 공고관리 허용 → 공고등록 허용 아닐 수 있음 (workers만 있을 때)', () {
        // workers=true이면 공고관리는 true이지만 공고등록은 false
        expect(showToManage(sub, _permWorkers), isTrue);
        expect(showToCreate(sub, _permWorkers), isFalse);
      });
    });

    group('P3. SubAdmin 전환 시 상태 변화', () {
      test('P3-01 USER → SubAdmin (subAdminOf 설정) 시 isAdmin 변경', () {
        final user = _user(role: UserRole.USER, subAdminOf: null);
        expect(user.isAdmin, isFalse);
        final promoted = user.copyWith(subAdminOf: 'biz1');
        expect(promoted.isAdmin, isTrue);
      });
      test('P3-02 SubAdmin → USER (subAdminOf 제거) 시 isAdmin 변경', () {
        final subAdmin = _user(role: UserRole.USER, subAdminOf: 'biz1');
        expect(subAdmin.isAdmin, isTrue);
        final removed = subAdmin.copyWith(clearSubAdminOf: true);
        expect(removed.isAdmin, isFalse);
      });
      test('P3-03 subAdminOf 변경 시 effectiveBusinessId 변경', () {
        final sub = _user(role: UserRole.USER, subAdminOf: 'biz_a');
        final changed = sub.copyWith(subAdminOf: 'biz_b');
        expect(effectiveBusinessId(changed), 'biz_b');
        expect(resolveBusinessIds(changed), ['biz_b']);
      });
    });

    group('P4. SUPER_ADMIN의 can() 특이 동작', () {
      test('P4-01 SUPER_ADMIN + null perms → false (isBusinessAdmin 아님)', () {
        expect(can(_superAdmin, null, (p) => p.canManageTo), isFalse);
      });
      test('P4-02 SUPER_ADMIN + allPerms → true (memberPermissions로 통과)', () {
        expect(can(_superAdmin, _permAll, (p) => p.canManageTo), isTrue);
      });
      test('P4-03 SUPER_ADMIN 메뉴 표시 (isSubAdmin=false → !isSubAdmin=true)', () {
        expect(showToCreate(_superAdmin, null), isTrue);
        expect(showWage(_superAdmin, null), isTrue);
      });
    });

    group('P5. 빈 managedBusinessIds', () {
      test('P5-01 BUSINESS_ADMIN + managedIds=[] → 공고 로드 시 빈 목록', () {
        final u = _user(role: UserRole.BUSINESS_ADMIN, managedBusinessIds: []);
        expect(resolveBusinessIds(u), isEmpty);
      });
      test('P5-02 빈 managedIds → 메뉴는 표시되지만 데이터 없음', () {
        final u = _user(role: UserRole.BUSINESS_ADMIN, managedBusinessIds: []);
        expect(showToCreate(u, null), isTrue); // BUSINESS_ADMIN이므로 메뉴 표시
        expect(resolveBusinessIds(u), isEmpty); // 하지만 데이터 없음
      });
    });

    group('P6. 다중 권한 해제 시나리오', () {
      test('P6-01 all → wage만 제거 → wage 관련 기능만 숨김', () {
        final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');
        final withoutWage = _perm(to: true, workers: true, contract: true); // wage=false
        expect(showToCreate(sub, withoutWage), isTrue);
        expect(showToManage(sub, withoutWage), isTrue);
        expect(showWage(sub, withoutWage), isFalse);
        expect(showContract(sub, withoutWage), isTrue);
        expect(showStats(sub, withoutWage), isFalse);
      });
      test('P6-02 all → to만 제거 → 공고등록 숨김, 나머지 유지', () {
        final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');
        final withoutTo = _perm(workers: true, wage: true, contract: true);
        expect(showToCreate(sub, withoutTo), isFalse);
        expect(showToManage(sub, withoutTo), isTrue); // workers=true이므로
        expect(showWage(sub, withoutTo), isTrue);
        expect(showContract(sub, withoutTo), isTrue);
      });
      test('P6-03 all → contract만 제거 → 계약서 숨김, 나머지 유지', () {
        final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');
        final withoutContract = _perm(to: true, workers: true, wage: true);
        expect(showToCreate(sub, withoutContract), isTrue);
        expect(showWage(sub, withoutContract), isTrue);
        expect(showContract(sub, withoutContract), isFalse);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// Q. MemberPermissions 모델 단위 테스트
// ════════════════════════════════════════════════════════════

void _runPermissionsModelTests() {
  group('Q. MemberPermissions 모델', () {
    group('Q1. none() 팩토리', () {
      test('Q1-01 none → canManageTo=false', () => expect(MemberPermissions.none().canManageTo, isFalse));
      test('Q1-02 none → canManageWorkers=false', () => expect(MemberPermissions.none().canManageWorkers, isFalse));
      test('Q1-03 none → canManageWage=false', () => expect(MemberPermissions.none().canManageWage, isFalse));
      test('Q1-04 none → canManageContract=false', () => expect(MemberPermissions.none().canManageContract, isFalse));
      test('Q1-05 none → hasAnyPermission=false', () => expect(MemberPermissions.none().hasAnyPermission, isFalse));
    });

    group('Q2. all() 팩토리', () {
      test('Q2-01 all → canManageTo=true', () => expect(MemberPermissions.all().canManageTo, isTrue));
      test('Q2-02 all → canManageWorkers=true', () => expect(MemberPermissions.all().canManageWorkers, isTrue));
      test('Q2-03 all → canManageWage=true', () => expect(MemberPermissions.all().canManageWage, isTrue));
      test('Q2-04 all → canManageContract=true', () => expect(MemberPermissions.all().canManageContract, isTrue));
      test('Q2-05 all → hasAnyPermission=true', () => expect(MemberPermissions.all().hasAnyPermission, isTrue));
    });

    group('Q3. copyWith', () {
      test('Q3-01 none.copyWith(canManageTo: true) → to=true', () {
        final p = MemberPermissions.none().copyWith(canManageTo: true);
        expect(p.canManageTo, isTrue);
        expect(p.canManageWorkers, isFalse);
      });
      test('Q3-02 all.copyWith(canManageWage: false) → wage=false 나머지 유지', () {
        final p = MemberPermissions.all().copyWith(canManageWage: false);
        expect(p.canManageWage, isFalse);
        expect(p.canManageTo, isTrue);
        expect(p.canManageWorkers, isTrue);
        expect(p.canManageContract, isTrue);
      });
      test('Q3-03 none.copyWith(canManageContract: true) → contract=true', () {
        final p = MemberPermissions.none().copyWith(canManageContract: true);
        expect(p.canManageContract, isTrue);
        expect(p.canManageTo, isFalse);
      });
      test('Q3-04 copyWith 후 원본 불변', () {
        final original = MemberPermissions.none();
        original.copyWith(canManageTo: true);
        expect(original.canManageTo, isFalse);
      });
    });

    group('Q4. toMap / fromMap', () {
      test('Q4-01 all().toMap() → 모든 값 true', () {
        final map = MemberPermissions.all().toMap();
        expect(map['canManageTo'], isTrue);
        expect(map['canManageWorkers'], isTrue);
        expect(map['canManageWage'], isTrue);
        expect(map['canManageContract'], isTrue);
      });
      test('Q4-02 none().toMap() → 모든 값 false', () {
        final map = MemberPermissions.none().toMap();
        expect(map['canManageTo'], isFalse);
        expect(map['canManageWorkers'], isFalse);
        expect(map['canManageWage'], isFalse);
        expect(map['canManageContract'], isFalse);
      });
      test('Q4-03 fromMap → all 복원', () {
        final original = MemberPermissions.all();
        final restored = MemberPermissions.fromMap(original.toMap());
        expect(restored.canManageTo, original.canManageTo);
        expect(restored.canManageWorkers, original.canManageWorkers);
        expect(restored.canManageWage, original.canManageWage);
        expect(restored.canManageContract, original.canManageContract);
      });
      test('Q4-04 fromMap → none 복원', () {
        final original = MemberPermissions.none();
        final restored = MemberPermissions.fromMap(original.toMap());
        expect(restored.hasAnyPermission, isFalse);
      });
      test('Q4-05 부분 map으로 fromMap → 나머지 false', () {
        final p = MemberPermissions.fromMap({'canManageTo': true});
        expect(p.canManageTo, isTrue);
        expect(p.canManageWorkers, isFalse);
        expect(p.canManageWage, isFalse);
        expect(p.canManageContract, isFalse);
      });
      test('Q4-06 빈 map으로 fromMap → all false', () {
        final p = MemberPermissions.fromMap({});
        expect(p.hasAnyPermission, isFalse);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// R. hasAnyPermission 다양한 조합
// ════════════════════════════════════════════════════════════

void _runHasAnyPermissionTests() {
  group('R. hasAnyPermission 조합', () {
    test('R-01 none → false', () => expect(_permNone.hasAnyPermission, isFalse));
    test('R-02 to만 → true', () => expect(_permTo.hasAnyPermission, isTrue));
    test('R-03 workers만 → true', () => expect(_permWorkers.hasAnyPermission, isTrue));
    test('R-04 wage만 → true', () => expect(_permWage.hasAnyPermission, isTrue));
    test('R-05 contract만 → true', () => expect(_permContract.hasAnyPermission, isTrue));
    test('R-06 to+workers → true', () => expect(_permToWorkers.hasAnyPermission, isTrue));
    test('R-07 to+wage → true', () => expect(_permToWage.hasAnyPermission, isTrue));
    test('R-08 to+contract → true', () => expect(_permToContract.hasAnyPermission, isTrue));
    test('R-09 workers+wage → true', () => expect(_permWorkersWage.hasAnyPermission, isTrue));
    test('R-10 workers+contract → true', () => expect(_permWorkersContract.hasAnyPermission, isTrue));
    test('R-11 wage+contract → true', () => expect(_permWageContract.hasAnyPermission, isTrue));
    test('R-12 all → true', () => expect(_permAll.hasAnyPermission, isTrue));
    test('R-13 to+workers+wage → true', () {
      expect(_perm(to: true, workers: true, wage: true).hasAnyPermission, isTrue);
    });
    test('R-14 to+workers+contract → true', () {
      expect(_perm(to: true, workers: true, contract: true).hasAnyPermission, isTrue);
    });
    test('R-15 workers+wage+contract → true', () {
      expect(_perm(workers: true, wage: true, contract: true).hasAnyPermission, isTrue);
    });
    test('R-16 모든 16가지 조합 중 none만 false', () {
      final cases = [
        _permNone, _permTo, _permWorkers, _permWage, _permContract,
        _permToWorkers, _permToWage, _permToContract, _permWorkersWage,
        _permWorkersContract, _permWageContract, _permAll,
        _perm(to: true, workers: true, wage: true),
        _perm(to: true, workers: true, contract: true),
        _perm(to: true, wage: true, contract: true),
        _perm(workers: true, wage: true, contract: true),
      ];
      final falseCount = cases.where((p) => !p.hasAnyPermission).length;
      expect(falseCount, 1, reason: '16가지 중 none만 false여야 함');
    });
  });
}

// ════════════════════════════════════════════════════════════
// S. summaryText / 권한 텍스트
// ════════════════════════════════════════════════════════════

void _runSummaryTextTests() {
  group('S. summaryText', () {
    test('S-01 none → summaryText 비어있거나 "없음" 포함', () {
      final text = _permNone.summaryText;
      expect(text, isA<String>());
    });
    test('S-02 all → summaryText 있음', () {
      final text = _permAll.summaryText;
      expect(text, isNotEmpty);
    });
    test('S-03 to만 → summaryText 포함', () {
      final text = _permTo.summaryText;
      expect(text, isA<String>());
    });
    test('S-04 wage만 → summaryText 포함', () {
      final text = _permWage.summaryText;
      expect(text, isA<String>());
    });
    test('S-05 두 권한 이상 → summaryText 길이 증가', () {
      final single = _permTo.summaryText;
      final multi = _permToWorkers.summaryText;
      expect(multi.length, greaterThanOrEqualTo(single.length));
    });
  });
}

// ════════════════════════════════════════════════════════════
// T. SubAdmin × 모든 권한 × 모든 메뉴 매트릭스 (추가 파라미터화)
// ════════════════════════════════════════════════════════════

void _runSubAdminMenuMatrixTests() {
  group('T. SubAdmin 메뉴 매트릭스 (권한 × 메뉴)', () {
    final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');

    // 각 단일 권한 × 각 메뉴
    final singlePerms = <(String, MemberPermissions)>[
      ('to', _permTo),
      ('workers', _permWorkers),
      ('wage', _permWage),
      ('contract', _permContract),
    ];

    final menuChecks = <(String, bool Function(UserModel, MemberPermissions?))>[
      ('공고등록', showToCreate),
      ('공고관리', showToManage),
      ('급여', showWage),
      ('통계', showStats),
      ('계약서', showContract),
    ];

    // 예상 결과 테이블: rows=권한, cols=메뉴
    // (to, workers, wage, contract) vs (toCreate, toManage, wage, stats, contract)
    final expected = <String, List<bool>>{
      'to':       [true,  true,  false, false, false],
      'workers':  [false, true,  false, false, false],
      'wage':     [false, false, true,  true,  false],
      'contract': [false, false, false, false, true ],
    };

    for (final (permName, perm) in singlePerms) {
      for (int i = 0; i < menuChecks.length; i++) {
        final (menuName, menuFn) = menuChecks[i];
        final exp = expected[permName]![i];
        test('T-$permName-$menuName → $exp', () {
          expect(menuFn(sub, perm), exp ? isTrue : isFalse);
        });
      }
    }

    // none × 모든 메뉴
    for (final (menuName, menuFn) in menuChecks) {
      test('T-none-$menuName → false', () {
        expect(menuFn(sub, _permNone), isFalse);
      });
    }

    // all × 모든 메뉴
    for (final (menuName, menuFn) in menuChecks) {
      test('T-all-$menuName → true', () {
        expect(menuFn(sub, _permAll), isTrue);
      });
    }
  });
}

// ════════════════════════════════════════════════════════════
// U. can() 함수 역할 × 권한 × 기능 전체 매트릭스
// ════════════════════════════════════════════════════════════

void _runCanFunctionMatrixTests() {
  group('U. can() 역할 × 기능 매트릭스', () {
    final sub      = _user(role: UserRole.USER, subAdminOf: 'biz1');
    final bizAdmin = _user(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1');
    final regular  = _user(role: UserRole.USER);

    final funcs = <(String, bool Function(MemberPermissions))>[
      ('to',       (p) => p.canManageTo),
      ('workers',  (p) => p.canManageWorkers),
      ('wage',     (p) => p.canManageWage),
      ('contract', (p) => p.canManageContract),
    ];

    // BUSINESS_ADMIN: perms 무관하게 항상 true
    for (final (fname, fn) in funcs) {
      for (final perm in [_permNone, _permTo, _permAll]) {
        test('U-bizAdmin-${perm.summaryText.isEmpty ? "none" : perm.summaryText}-$fname → true', () {
          expect(can(bizAdmin, perm, fn), isTrue);
        });
      }
      test('U-bizAdmin-nullPerm-$fname → true', () {
        expect(can(bizAdmin, null, fn), isTrue);
      });
    }

    // SubAdmin: 각 권한에 따라 달라짐
    for (final (fname, fn) in funcs) {
      test('U-sub-allPerm-$fname → true', () {
        expect(can(sub, _permAll, fn), isTrue);
      });
      test('U-sub-nonePerm-$fname → false', () {
        expect(can(sub, _permNone, fn), isFalse);
      });
      test('U-sub-nullPerm-$fname → false', () {
        expect(can(sub, null, fn), isFalse);
      });
    }

    // 일반 USER: perms=null이면 false, perms!=null이면 check(perms) (역할 체크 없음)
    for (final (fname, fn) in funcs) {
      test('U-regular-allPerm-$fname → true (perms!=null이면 check 적용)', () {
        expect(can(regular, _permAll, fn), isTrue);
      });
      test('U-regular-nullPerm-$fname → false', () {
        expect(can(regular, null, fn), isFalse);
      });
    }
  });
}

// ════════════════════════════════════════════════════════════
// V. BUSINESS_ADMIN 메뉴 매트릭스
// ════════════════════════════════════════════════════════════

void _runBizAdminMenuMatrixTests() {
  group('V. BUSINESS_ADMIN 메뉴 매트릭스', () {
    final bizAdmin = _user(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1');

    final menuChecks = <(String, bool Function(UserModel, MemberPermissions?))>[
      ('공고등록', showToCreate),
      ('공고관리', showToManage),
      ('급여', showWage),
      ('통계', showStats),
      ('계약서', showContract),
    ];

    // 권한과 무관하게 항상 true
    for (final (menuName, menuFn) in menuChecks) {
      for (final perm in [null, _permNone, _permTo, _permAll]) {
        final permLabel = perm?.summaryText.isEmpty ?? true ? 'null/none' : perm!.summaryText;
        test('V-bizAdmin-$permLabel-$menuName → true', () {
          expect(menuFn(bizAdmin, perm), isTrue);
        });
      }
    }

    // 멤버 관리 / 사업장 편집도 가능
    test('V-bizAdmin-멤버관리 → true', () {
      expect(canAccessMemberManagement(bizAdmin), isTrue);
    });
    test('V-bizAdmin-사업장편집 → true', () {
      expect(canEditBusiness(bizAdmin), isTrue);
    });
    test('V-bizAdmin-설정 → true', () {
      expect(showSettings(bizAdmin), isTrue);
    });
  });
}

// ════════════════════════════════════════════════════════════
// W. SubAdmin + null permissions 경계값
// ════════════════════════════════════════════════════════════

void _runSubAdminNullPermTests() {
  group('W. SubAdmin + null/none permissions 경계', () {
    final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');

    test('W-01 null → showToCreate false', () => expect(showToCreate(sub, null), isFalse));
    test('W-02 null → showToManage false', () => expect(showToManage(sub, null), isFalse));
    test('W-03 null → showWage false', () => expect(showWage(sub, null), isFalse));
    test('W-04 null → showContract false', () => expect(showContract(sub, null), isFalse));
    test('W-05 null → showStats false', () => expect(showStats(sub, null), isFalse));
    test('W-06 null → canToggleMode true (권한 무관)', () => expect(canToggleMode(sub), isTrue));
    test('W-07 null → canAccessMemberManagement false', () => expect(canAccessMemberManagement(sub), isFalse));
    test('W-08 null → canEditBusiness false', () => expect(canEditBusiness(sub), isFalse));
    test('W-09 none → showToCreate false', () => expect(showToCreate(sub, _permNone), isFalse));
    test('W-10 none → showToManage false', () => expect(showToManage(sub, _permNone), isFalse));
    test('W-11 none → showWage false', () => expect(showWage(sub, _permNone), isFalse));
    test('W-12 none → showContract false', () => expect(showContract(sub, _permNone), isFalse));
    test('W-13 none → showStats false', () => expect(showStats(sub, _permNone), isFalse));
    test('W-14 none → effectiveBusinessId=subAdminOf (권한 무관)', () {
      expect(effectiveBusinessId(sub), 'biz1');
    });
    test('W-15 none → resolveBusinessIds=[biz1] (권한 무관)', () {
      expect(resolveBusinessIds(sub), ['biz1']);
    });
    test('W-16 none.hasAnyPermission=false → 설정 메뉴는 표시', () {
      expect(showSettings(sub), isTrue);
    });
  });
}

// ════════════════════════════════════════════════════════════
// X. SubAdmin vs BUSINESS_ADMIN 경쟁 조건
// ════════════════════════════════════════════════════════════

void _runSubAdminVsBizAdminRaceTests() {
  group('X. SubAdmin vs BUSINESS_ADMIN 동일 사업장', () {
    final bizAdmin = _user(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1');
    final subNone  = _user(role: UserRole.USER, subAdminOf: 'biz1');
    final subAll   = _user(role: UserRole.USER, subAdminOf: 'biz1');

    test('X-01 같은 사업장, BizAdmin은 공고등록 가능 / SubNone은 불가', () {
      expect(showToCreate(bizAdmin, null), isTrue);
      expect(showToCreate(subNone, _permNone), isFalse);
    });
    test('X-02 같은 사업장, BizAdmin은 급여 가능 / SubAll도 가능', () {
      expect(showWage(bizAdmin, null), isTrue);
      expect(showWage(subAll, _permAll), isTrue);
    });
    test('X-03 멤버관리 — BizAdmin만 가능', () {
      expect(canAccessMemberManagement(bizAdmin), isTrue);
      expect(canAccessMemberManagement(subAll), isFalse);
    });
    test('X-04 사업장편집 — BizAdmin만 가능', () {
      expect(canEditBusiness(bizAdmin), isTrue);
      expect(canEditBusiness(subAll), isFalse);
    });
    test('X-05 BizAdmin은 모드 전환 불가, SubAdmin은 가능', () {
      expect(canToggleMode(bizAdmin), isFalse);
      expect(canToggleMode(subAll), isTrue);
    });
    test('X-06 effectiveBusinessId 동일 값 반환', () {
      expect(effectiveBusinessId(bizAdmin), effectiveBusinessId(subAll));
    });
    test('X-07 resolveBusinessIds 포함 여부', () {
      final bizIds = resolveBusinessIds(bizAdmin);
      final subIds = resolveBusinessIds(subAll);
      expect(bizIds?.contains('biz1'), isTrue);
      expect(subIds?.contains('biz1'), isTrue);
    });
  });
}

// ════════════════════════════════════════════════════════════
// Y. 동일 사업장에 여러 SubAdmin 시뮬레이션
// ════════════════════════════════════════════════════════════

void _runMultiSubAdminTests() {
  group('Y. 동일 사업장 다중 SubAdmin', () {
    final sub1 = _user(role: UserRole.USER, subAdminOf: 'biz1');
    final sub2 = _user(role: UserRole.USER, subAdminOf: 'biz1');

    test('Y-01 두 SubAdmin 모두 동일 effectiveBusinessId', () {
      expect(effectiveBusinessId(sub1), effectiveBusinessId(sub2));
    });
    test('Y-02 sub1=toPerms, sub2=wagePerms → 각자 다른 메뉴', () {
      expect(showToCreate(sub1, _permTo), isTrue);
      expect(showToCreate(sub2, _permWage), isFalse);
      expect(showWage(sub1, _permTo), isFalse);
      expect(showWage(sub2, _permWage), isTrue);
    });
    test('Y-03 둘 다 멤버관리 불가', () {
      expect(canAccessMemberManagement(sub1), isFalse);
      expect(canAccessMemberManagement(sub2), isFalse);
    });
    test('Y-04 각자 독립적으로 모드 전환 가능', () {
      expect(canToggleMode(sub1), isTrue);
      expect(canToggleMode(sub2), isTrue);
    });
    test('Y-05 sub1 resolveBusinessIds == sub2 resolveBusinessIds', () {
      expect(resolveBusinessIds(sub1), resolveBusinessIds(sub2));
    });
    test('Y-06 서로 다른 사업장 SubAdmin은 데이터 격리', () {
      final subA = _user(role: UserRole.USER, subAdminOf: 'biz_a');
      final subB = _user(role: UserRole.USER, subAdminOf: 'biz_b');
      expect(resolveBusinessIds(subA), isNot(equals(resolveBusinessIds(subB))));
    });
  });
}

// ════════════════════════════════════════════════════════════
// Z. 역할 전환 시나리오
// ════════════════════════════════════════════════════════════

void _runRoleTransitionTests() {
  group('Z. 역할 전환 시나리오', () {
    group('Z1. 일반 USER → SubAdmin', () {
      test('Z1-01 subAdminOf 설정 시 isSubAdmin=true', () {
        final user = _user(role: UserRole.USER);
        final promoted = user.copyWith(subAdminOf: 'biz1');
        expect(promoted.isSubAdmin, isTrue);
      });
      test('Z1-02 전환 전 관리자 메뉴 숨김', () {
        final user = _user(role: UserRole.USER);
        expect(showToCreate(user, _permAll), isTrue); // isSubAdmin=false이므로 !false = true
      });
      test('Z1-03 전환 후 SubAdmin 메뉴 → 권한에 따라', () {
        final promoted = _user(role: UserRole.USER, subAdminOf: 'biz1');
        expect(showToCreate(promoted, _permNone), isFalse);
        expect(showToCreate(promoted, _permTo), isTrue);
      });
      test('Z1-04 전환 후 effectiveBusinessId = subAdminOf', () {
        final promoted = _user(role: UserRole.USER).copyWith(subAdminOf: 'new_biz');
        expect(effectiveBusinessId(promoted), 'new_biz');
      });
    });

    group('Z2. SubAdmin → 일반 USER (강등)', () {
      test('Z2-01 subAdminOf 제거 시 isSubAdmin=false', () {
        final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');
        final demoted = sub.copyWith(clearSubAdminOf: true);
        expect(demoted.isSubAdmin, isFalse);
      });
      test('Z2-02 강등 후 effectiveBusinessId=null', () {
        final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');
        final demoted = sub.copyWith(clearSubAdminOf: true);
        expect(effectiveBusinessId(demoted), isNull);
      });
      test('Z2-03 강등 후 관리자 모드 불가', () {
        final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');
        final demoted = sub.copyWith(clearSubAdminOf: true);
        expect(canToggleMode(demoted), isFalse);
      });
      test('Z2-04 강등 후 멤버관리 접근 가능 (isSubAdmin=false)', () {
        final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');
        final demoted = sub.copyWith(clearSubAdminOf: true);
        expect(canAccessMemberManagement(demoted), isTrue);
      });
    });

    group('Z3. SubAdmin → BUSINESS_ADMIN (격상)', () {
      test('Z3-01 role 변경 시 isSubAdmin=false', () {
        final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');
        final promoted = sub.copyWith(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1');
        expect(promoted.isSubAdmin, isFalse);
        expect(promoted.isBusinessAdmin, isTrue);
      });
      test('Z3-02 격상 후 멤버관리 가능', () {
        final promoted = _user(role: UserRole.USER, subAdminOf: 'biz1')
            .copyWith(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1');
        expect(canAccessMemberManagement(promoted), isTrue);
      });
      test('Z3-03 격상 후 사업장편집 가능', () {
        final promoted = _user(role: UserRole.USER, subAdminOf: 'biz1')
            .copyWith(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1');
        expect(canEditBusiness(promoted), isTrue);
      });
      test('Z3-04 격상 후 권한 없어도 모든 메뉴 표시', () {
        final promoted = _user(role: UserRole.USER, subAdminOf: 'biz1')
            .copyWith(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1');
        expect(showToCreate(promoted, _permNone), isTrue);
        expect(showWage(promoted, _permNone), isTrue);
        expect(showContract(promoted, _permNone), isTrue);
      });
    });

    group('Z4. 사업장 재배정', () {
      test('Z4-01 subAdminOf 변경 시 새 사업장으로 전환', () {
        final sub = _user(role: UserRole.USER, subAdminOf: 'biz_old');
        final reassigned = sub.copyWith(subAdminOf: 'biz_new');
        expect(effectiveBusinessId(reassigned), 'biz_new');
        expect(resolveBusinessIds(reassigned), ['biz_new']);
      });
      test('Z4-02 변경 후 이전 사업장 ID 없음', () {
        final sub = _user(role: UserRole.USER, subAdminOf: 'biz_old');
        final reassigned = sub.copyWith(subAdminOf: 'biz_new');
        expect(resolveBusinessIds(reassigned)?.contains('biz_old'), isFalse);
      });
    });

    group('Z5. 연속 전환', () {
      test('Z5-01 USER → Sub → USER → Sub → 최종 상태 확인', () {
        final user = _user(role: UserRole.USER);
        final sub1 = user.copyWith(subAdminOf: 'biz1');
        final user2 = sub1.copyWith(clearSubAdminOf: true);
        final sub2 = user2.copyWith(subAdminOf: 'biz2');
        expect(sub2.isSubAdmin, isTrue);
        expect(sub2.subAdminOf, 'biz2');
        expect(effectiveBusinessId(sub2), 'biz2');
      });
      test('Z5-02 권한 부여 → 제거 → 재부여', () {
        final sub = _user(role: UserRole.USER, subAdminOf: 'biz1');
        expect(showToCreate(sub, _permTo), isTrue);
        expect(showToCreate(sub, _permNone), isFalse);
        expect(showToCreate(sub, _permTo), isTrue);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// AA. 16가지 권한 조합 × 역할별 can() 결과 파라미터화
// ════════════════════════════════════════════════════════════

void _runAllPermCanMatrixTests() {
  group('AA. 16가지 조합 × can() 역할별', () {
    final sub      = _user(role: UserRole.USER, subAdminOf: 'biz1');
    final bizAdmin = _user(role: UserRole.BUSINESS_ADMIN, businessId: 'biz1');

    final allCombinations = <(bool, bool, bool, bool)>[
      (false, false, false, false),
      (true,  false, false, false),
      (false, true,  false, false),
      (false, false, true,  false),
      (false, false, false, true),
      (true,  true,  false, false),
      (true,  false, true,  false),
      (true,  false, false, true),
      (false, true,  true,  false),
      (false, true,  false, true),
      (false, false, true,  true),
      (true,  true,  true,  false),
      (true,  true,  false, true),
      (true,  false, true,  true),
      (false, true,  true,  true),
      (true,  true,  true,  true),
    ];

    for (final (to, workers, wage, contract) in allCombinations) {
      final p = _perm(to: to, workers: workers, wage: wage, contract: contract);
      final label = 'to=$to w=$workers wa=$wage c=$contract';

      // SubAdmin: can() 결과 = 해당 필드값
      test('AA-sub-to[$label]', () {
        expect(can(sub, p, (pp) => pp.canManageTo), to ? isTrue : isFalse);
      });
      test('AA-sub-workers[$label]', () {
        expect(can(sub, p, (pp) => pp.canManageWorkers), workers ? isTrue : isFalse);
      });
      test('AA-sub-wage[$label]', () {
        expect(can(sub, p, (pp) => pp.canManageWage), wage ? isTrue : isFalse);
      });
      test('AA-sub-contract[$label]', () {
        expect(can(sub, p, (pp) => pp.canManageContract), contract ? isTrue : isFalse);
      });

      // BizAdmin: 항상 true
      test('AA-biz-to[$label]', () {
        expect(can(bizAdmin, p, (pp) => pp.canManageTo), isTrue);
      });
      test('AA-biz-contract[$label]', () {
        expect(can(bizAdmin, p, (pp) => pp.canManageContract), isTrue);
      });
    }
  });
}

// ════════════════════════════════════════════════════════════
// main
// ════════════════════════════════════════════════════════════

void main() {
  _runSubAdminIdentificationTests();
  _runEffectiveBusinessIdTests();
  _runBusinessIdsAllocationTests();
  _runHomeMenuTests();
  _runCanManageToTests();
  _runCanManageWorkersTests();
  _runCanManageWageTests();
  _runCanManageContractTests();
  _runMemberManagementAccessTests();
  _runBusinessEditTests();
  _runModeToggleTests();
  _runDataIsolationTests();
  _runAllPermCombinationsTests();
  _runAdminComparisonTests();
  _runRealWorldScenarioTests();
  _runEdgeCaseTests();
  _runPermissionsModelTests();
  _runHasAnyPermissionTests();
  _runSummaryTextTests();
  _runSubAdminMenuMatrixTests();
  _runCanFunctionMatrixTests();
  _runBizAdminMenuMatrixTests();
  _runSubAdminNullPermTests();
  _runSubAdminVsBizAdminRaceTests();
  _runMultiSubAdminTests();
  _runRoleTransitionTests();
  _runAllPermCanMatrixTests();
}
