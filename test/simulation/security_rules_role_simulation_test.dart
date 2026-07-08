// test/simulation/security_rules_role_simulation_test.dart
//
// Firestore 보안 규칙 역할별 접근 제어 시뮬레이션 테스트
//
// 목적:
//   실제 firestore.rules의 핵심 함수와 컬렉션 규칙을 순수 Dart 함수로 재현하여
//   역할/상태/조건별 허용·거부 경계를 코드로 검증한다.
//
// 테스트 대상:
//   - 헬퍼 함수: isLoggedIn, myRole, isSuperAdmin, isBusinessAdmin, isUser,
//                isAdmin, isSubAdmin, isAdminOf, isSubAdminOf,
//                isNotBlacklisted, isNotRestricted
//   - tos 컬렉션 get / list / update (관리자·지원자)
//   - applications 컬렉션 list / create
//   - users 컬렉션 create / update (본인)
//   - businesses 컬렉션 list
//
// Firebase 의존성 없음 — 순수 Dart 로직만 검증
//
// 실행: flutter test test/simulation/security_rules_role_simulation_test.dart

import 'package:flutter_test/flutter_test.dart';

// ════════════════════════════════════════════════════════════════════════════
// 데이터 모델 (Firestore 문서 구조 최소 재현)
// ════════════════════════════════════════════════════════════════════════════

class _Auth {
  final String? uid;
  final DateTime time;

  _Auth({this.uid, DateTime? time})
      : time = time ?? DateTime(2026, 7, 8, 12, 0, 0);

  bool get loggedIn => uid != null;
}

class _UserDoc {
  final String uid;
  final String role; // 'SUPER_ADMIN' | 'BUSINESS_ADMIN' | 'USER'
  final bool isBlacklisted;
  final String subAdminOf; // '' if none
  final String businessId; // '' if none
  final DateTime? restrictedUntil;
  final int noShowCount;
  final int lateCount;
  final int totalWorkDays;

  const _UserDoc({
    required this.uid,
    required this.role,
    this.isBlacklisted = false,
    this.subAdminOf = '',
    this.businessId = '',
    this.restrictedUntil,
    this.noShowCount = 0,
    this.lateCount = 0,
    this.totalWorkDays = 0,
  });
}

class _BusinessDoc {
  final String id;
  final String ownerId;
  final List<String> adminIds;

  const _BusinessDoc({
    required this.id,
    required this.ownerId,
    this.adminIds = const [],
  });
}

class _TODoc {
  final String id;
  final String businessId;
  final bool isPublished;
  final String status; // 'OPEN' | 'CLOSED' | 'EXPIRED' | 'PENDING_OPEN'
  final int totalRequired;
  final int totalConfirmed;

  const _TODoc({
    required this.id,
    required this.businessId,
    this.isPublished = true,
    this.status = 'OPEN',
    this.totalRequired = 10,
    this.totalConfirmed = 0,
  });
}

class _ApplicationDoc {
  final String id;
  final String uid; // 지원자 uid
  final String businessId;
  final String toId;
  final String status;

  const _ApplicationDoc({
    required this.id,
    required this.uid,
    required this.businessId,
    required this.toId,
    this.status = 'PENDING',
  });
}

// ════════════════════════════════════════════════════════════════════════════
// 가상 Firestore DB
// ════════════════════════════════════════════════════════════════════════════

class _DB {
  final Map<String, _UserDoc> users;
  final Map<String, _BusinessDoc> businesses;
  final Map<String, _TODoc> tos;
  final Map<String, _ApplicationDoc> applications;

  const _DB({
    this.users = const {},
    this.businesses = const {},
    this.tos = const {},
    this.applications = const {},
  });
}

// ════════════════════════════════════════════════════════════════════════════
// 보안 규칙 함수 재현 (firestore.rules 1:1 대응)
// ════════════════════════════════════════════════════════════════════════════

class _Rules {
  final _Auth auth;
  final _DB db;

  _Rules({required this.auth, required this.db});

  // ── 헬퍼 함수 ──────────────────────────────────────────────────────────

  /// rules: request.auth != null
  bool isLoggedIn() => auth.loggedIn;

  /// rules: get(users/uid).data.get('role', null)
  String? myRole() {
    if (!isLoggedIn()) return null;
    return db.users[auth.uid]?.role;
  }

  bool isSuperAdmin() => isLoggedIn() && myRole() == 'SUPER_ADMIN';
  bool isBusinessAdmin() => isLoggedIn() && myRole() == 'BUSINESS_ADMIN';
  bool isUser() => isLoggedIn() && myRole() == 'USER';

  bool isAdmin() {
    final role = myRole();
    return isLoggedIn() && (role == 'SUPER_ADMIN' || role == 'BUSINESS_ADMIN');
  }

  bool isSubAdmin() {
    if (!isLoggedIn()) return false;
    final u = db.users[auth.uid];
    return u != null && u.subAdminOf.isNotEmpty;
  }

  /// [BUGFIX] null/빈 businessId → early-return false (whereIn 버그 방어)
  /// rules: businessId is string && businessId.size() > 0 먼저 체크
  bool isAdminOf(String? businessId) {
    if (businessId == null || businessId.isEmpty) return false;
    final biz = db.businesses[businessId];
    if (biz == null) return false;
    if (!isLoggedIn()) return false;
    final uid = auth.uid!;
    return biz.ownerId == uid || biz.adminIds.contains(uid);
  }

  bool isSubAdminOf(String? businessId) {
    if (businessId == null || businessId.isEmpty) return false;
    if (!isLoggedIn()) return false;
    final u = db.users[auth.uid];
    if (u == null) return false;
    return u.subAdminOf == businessId;
  }

  /// [SEC-04] u == null → false 반환 (블랙리스트 우회 차단)
  bool isNotBlacklisted() {
    if (!isLoggedIn()) return false;
    final u = db.users[auth.uid];
    if (u == null) return false;
    return !u.isBlacklisted;
  }

  /// [SEC-05] restrictedUntil 서버 검증
  bool isNotRestricted() {
    if (!isLoggedIn()) return false;
    final u = db.users[auth.uid];
    if (u == null) return false;
    final until = u.restrictedUntil;
    return until == null || auth.time.isAfter(until);
  }

  // ── tos 컬렉션 규칙 ──────────────────────────────────────────────────

  /// [S-M3-FIX] 비공개 TO get: 관리자·슈퍼어드민·isPublished==true
  bool tosGet(_TODoc to) {
    if (!isLoggedIn()) return false;
    return isSuperAdmin() ||
        isAdminOf(to.businessId) ||
        isSubAdminOf(to.businessId) ||
        to.isPublished;
  }

  /// tos list: 역할별 검증
  /// USER: limit<=50 AND filterIsPublished==true
  bool tosList({
    String? filterBusinessId,
    bool filterIsPublished = false,
    int limit = 20,
  }) {
    if (!isLoggedIn()) return false;
    if (isSuperAdmin()) return true;
    if (isBusinessAdmin()) return isAdminOf(filterBusinessId);
    if (isSubAdmin()) return isSubAdminOf(filterBusinessId);
    if (isUser()) {
      return limit <= 50 && filterIsPublished == true;
    }
    return false;
  }

  /// tos update — 관리자 경로
  /// [CLOSED/EXPIRED 핵심 필드 보호] [businessId 불변] [totalRequired 검증]
  bool tosUpdateAdmin(
    _TODoc current, {
    bool changeBusinessId = false,
    bool changeWorkDetailId = false,
    bool changeTotalRequired = false,
    int? newTotalRequired,
  }) {
    if (!isLoggedIn()) return false;
    final isToAdmin = isAdminOf(current.businessId) ||
        isSubAdminOf(current.businessId) ||
        isSuperAdmin();
    if (!isToAdmin) return false;

    // [SEC-45] businessId 항상 불변 (슈퍼어드민 예외)
    if (changeBusinessId && !isSuperAdmin()) return false;

    // CLOSED/EXPIRED 상태에서 핵심 운영 필드 변경 차단 (슈퍼어드민 예외)
    if (!isSuperAdmin() &&
        (current.status == 'CLOSED' || current.status == 'EXPIRED') &&
        changeWorkDetailId) {
      return false;
    }

    // [TO-H1] totalRequired 변경: 0(무제한)이거나 >= totalConfirmed
    if (!isSuperAdmin() && changeTotalRequired && newTotalRequired != null) {
      if (newTotalRequired != 0 &&
          newTotalRequired < current.totalConfirmed) {
        return false;
      }
    }

    return true;
  }

  /// tos update — 지원자 경로 (totalPending 카운터 ±1 제한)
  bool tosUpdateUserPending(int currentPending, int newPending) {
    if (!isLoggedIn() || !isUser()) return false;
    if (newPending < 0) return false; // 음수 방지
    if (newPending != currentPending + 1 &&
        newPending != currentPending - 1) return false; // ±1 제한
    return true;
  }

  // ── applications 컬렉션 규칙 ─────────────────────────────────────────

  /// [HIGH-FIX] USER는 uid 필터 강제, 관리자는 businessId 필터 강제
  bool applicationsList({
    String? filterBusinessId,
    String? filterUid,
  }) {
    if (!isLoggedIn()) return false;
    if (isSuperAdmin()) return true;
    if (isBusinessAdmin()) return isAdminOf(filterBusinessId);
    if (isSubAdmin()) return isSubAdminOf(filterBusinessId);
    if (isUser()) return filterUid == auth.uid;
    return false;
  }

  /// [SEC-43] TO의 businessId와 지원서 businessId 교차 검증
  /// [SEC-04/05] 블랙리스트·이용제한 서버 레벨 차단
  bool applicationsCreateUser({
    required String applicantUid,
    required String toBusinessId, // TO 문서에서 조회한 businessId
    required String appBusinessId, // 지원서에 기재된 businessId
  }) {
    if (!isLoggedIn()) return false;
    if (applicantUid != auth.uid) return false;
    if (!isNotBlacklisted()) return false;
    if (!isNotRestricted()) return false;
    if (toBusinessId != appBusinessId) return false;
    return true;
  }

  // ── users 컬렉션 규칙 ────────────────────────────────────────────────

  /// [AUTH-H1/M6 FIX] 키 자체 차단 vs 값 제한 분리
  bool usersCreateSelf({
    required String targetUid,
    required String role,
    required String accountStatus,
    required bool isBlacklisted,
    required String? subAdminOf,
    required String? businessId,
    required int noShowCount,
    required int lateCount,
    required int totalWorkDays,
    required dynamic ci,
    required dynamic ciHash,
    bool hasIsAdminKey = false, // 'isAdmin' 키 자체 존재 여부
    dynamic sealBase64,
    dynamic restrictedUntil,
    dynamic trustScore,
    dynamic rejectionReason,
  }) {
    if (!isLoggedIn()) return false;
    if (targetUid != auth.uid) return false;

    // 키 자체 차단: 서버 전용 필드 (isAdmin 등)
    if (hasIsAdminKey) return false;

    // sealBase64: null만 허용
    if (sealBase64 != null) return false;

    // role: SUPER_ADMIN 승격 차단
    if (!['USER', 'BUSINESS_ADMIN'].contains(role)) return false;

    // accountStatus: active/pending만 허용
    if (!['active', 'pending'].contains(accountStatus)) return false;

    // isBlacklisted: false만 허용
    if (isBlacklisted) return false;

    // CI 값: null만 허용 (CF Admin SDK 전용)
    if (ci != null) return false;
    if (ciHash != null) return false;

    // 사업장/하위관리자 소속: null만 허용
    if (subAdminOf != null) return false;
    if (businessId != null) return false;

    // 제재·신뢰도: null만 허용
    if (restrictedUntil != null) return false;
    if (trustScore != null) return false;
    if (rejectionReason != null) return false;

    // 통계 카운터: 0만 허용
    if (noShowCount != 0) return false;
    if (lateCount != 0) return false;
    if (totalWorkDays != 0) return false;

    return true;
  }

  /// 본인 문서 update — 불변 필드 변경 시도 차단
  bool usersUpdateSelf({
    required String targetUid,
    required Set<String> changedKeys,
  }) {
    if (!isLoggedIn()) return false;
    if (targetUid != auth.uid) return false;

    const immutableKeys = <String>{
      'role',
      'isBlacklisted',
      'subAdminOf',
      'businessId',
      'trustScore',
      'noShowCount',
      'lateCount',
      'totalWorkDays',
      'lastRestartAt',
      'restrictedUntil',
      'isAdmin',
      'sealBase64',
      'accountStatus',
      'rejectionReason',
      'approvedBy',
      'approvedAt',
      'rejectedBy',
      'rejectedAt',
    };

    return !changedKeys.any((k) => immutableKeys.contains(k));
  }

  // ── businesses 컬렉션 규칙 ───────────────────────────────────────────

  /// [CF 이전 완료] list: SUPER_ADMIN만 허용 (adminIds 덤프 방지)
  bool businessesList() {
    if (!isLoggedIn()) return false;
    return isSuperAdmin();
  }
}

// ════════════════════════════════════════════════════════════════════════════
// 테스트 픽스처
// ════════════════════════════════════════════════════════════════════════════

/// 표준 DB 픽스처 — 대부분의 테스트에서 재사용
_DB _buildStandardDB() {
  return _DB(
    users: {
      'super-uid': const _UserDoc(uid: 'super-uid', role: 'SUPER_ADMIN'),
      'biz-admin-uid': const _UserDoc(
        uid: 'biz-admin-uid',
        role: 'BUSINESS_ADMIN',
        businessId: 'biz-001',
      ),
      'biz-admin-b-uid': const _UserDoc(
        uid: 'biz-admin-b-uid',
        role: 'BUSINESS_ADMIN',
        businessId: 'biz-002',
      ),
      'sub-admin-uid': const _UserDoc(
        uid: 'sub-admin-uid',
        role: 'USER',
        subAdminOf: 'biz-001',
      ),
      'user-uid': const _UserDoc(
        uid: 'user-uid',
        role: 'USER',
        businessId: 'biz-001',
      ),
      'blacklisted-uid': const _UserDoc(
        uid: 'blacklisted-uid',
        role: 'USER',
        isBlacklisted: true,
        businessId: 'biz-001',
      ),
      'restricted-uid': _UserDoc(
        uid: 'restricted-uid',
        role: 'USER',
        businessId: 'biz-001',
        restrictedUntil: DateTime(2026, 12, 31, 23, 59),
      ),
    },
    businesses: {
      'biz-001': const _BusinessDoc(
        id: 'biz-001',
        ownerId: 'biz-admin-uid',
        adminIds: ['biz-admin-uid'],
      ),
      'biz-002': const _BusinessDoc(
        id: 'biz-002',
        ownerId: 'biz-admin-b-uid',
        adminIds: ['biz-admin-b-uid'],
      ),
    },
    tos: {
      'to-open-pub': const _TODoc(
        id: 'to-open-pub',
        businessId: 'biz-001',
        isPublished: true,
        status: 'OPEN',
        totalRequired: 5,
        totalConfirmed: 2,
      ),
      'to-open-priv': const _TODoc(
        id: 'to-open-priv',
        businessId: 'biz-001',
        isPublished: false,
        status: 'OPEN',
      ),
      'to-closed': const _TODoc(
        id: 'to-closed',
        businessId: 'biz-001',
        isPublished: true,
        status: 'CLOSED',
        totalRequired: 3,
        totalConfirmed: 3,
      ),
      'to-expired': const _TODoc(
        id: 'to-expired',
        businessId: 'biz-001',
        isPublished: true,
        status: 'EXPIRED',
        totalRequired: 2,
        totalConfirmed: 1,
      ),
    },
  );
}

_Rules _rulesFor(String? uid, {_DB? db, DateTime? time}) {
  return _Rules(
    auth: _Auth(uid: uid, time: time),
    db: db ?? _buildStandardDB(),
  );
}

void main() {
  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 1 — 역할 헬퍼 함수 기초 검증
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-01: 기본 역할 함수', () {
    test('SEC-001 미로그인 → isLoggedIn=false, 모든 역할=false', () {
      final r = _rulesFor(null);
      expect(r.isLoggedIn(), isFalse);
      expect(r.isSuperAdmin(), isFalse);
      expect(r.isBusinessAdmin(), isFalse);
      expect(r.isUser(), isFalse);
      expect(r.isAdmin(), isFalse);
      expect(r.isSubAdmin(), isFalse);
    });

    test('SEC-002 SUPER_ADMIN → isSuperAdmin=true, isAdmin=true, isBusinessAdmin=false', () {
      final r = _rulesFor('super-uid');
      expect(r.isLoggedIn(), isTrue);
      expect(r.isSuperAdmin(), isTrue);
      expect(r.isAdmin(), isTrue);
      expect(r.isBusinessAdmin(), isFalse);
      expect(r.isUser(), isFalse);
      expect(r.isSubAdmin(), isFalse);
    });

    test('SEC-003 BUSINESS_ADMIN → isBusinessAdmin=true, isAdmin=true, isSuperAdmin=false', () {
      final r = _rulesFor('biz-admin-uid');
      expect(r.isBusinessAdmin(), isTrue);
      expect(r.isAdmin(), isTrue);
      expect(r.isSuperAdmin(), isFalse);
      expect(r.isUser(), isFalse);
    });

    test('SEC-004 USER → isUser=true, isAdmin=false', () {
      final r = _rulesFor('user-uid');
      expect(r.isUser(), isTrue);
      expect(r.isAdmin(), isFalse);
      expect(r.isSuperAdmin(), isFalse);
      expect(r.isBusinessAdmin(), isFalse);
    });

    test('SEC-005 subAdminOf 설정된 USER → isSubAdmin=true', () {
      final r = _rulesFor('sub-admin-uid');
      expect(r.isSubAdmin(), isTrue);
      expect(r.isUser(), isTrue); // role은 USER
      expect(r.isAdmin(), isFalse);
    });

    test('SEC-006 subAdminOf 미설정 USER → isSubAdmin=false', () {
      final r = _rulesFor('user-uid');
      expect(r.isSubAdmin(), isFalse);
    });

    test('SEC-007 존재하지 않는 UID → myRole=null, 모든 역할=false', () {
      final r = _rulesFor('nonexistent-uid');
      expect(r.myRole(), isNull);
      expect(r.isSuperAdmin(), isFalse);
      expect(r.isBusinessAdmin(), isFalse);
      expect(r.isUser(), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 2 — isAdminOf(businessId) 검증
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-02: isAdminOf 함수', () {
    test('SEC-008 null businessId → early-return false (whereIn 버그 방어)', () {
      final r = _rulesFor('biz-admin-uid');
      expect(r.isAdminOf(null), isFalse);
    });

    test('SEC-009 빈 문자열 businessId → early-return false', () {
      final r = _rulesFor('biz-admin-uid');
      expect(r.isAdminOf(''), isFalse);
    });

    test('SEC-010 존재하지 않는 businessId → false (biz 문서 없음)', () {
      final r = _rulesFor('biz-admin-uid');
      expect(r.isAdminOf('nonexistent-biz'), isFalse);
    });

    test('SEC-011 ownerId 일치 → true', () {
      final r = _rulesFor('biz-admin-uid');
      expect(r.isAdminOf('biz-001'), isTrue);
    });

    test('SEC-012 adminIds 포함 → true', () {
      final db = _DB(
        users: {
          'other-admin': const _UserDoc(uid: 'other-admin', role: 'BUSINESS_ADMIN'),
        },
        businesses: {
          'biz-003': const _BusinessDoc(
            id: 'biz-003',
            ownerId: 'owner-uid',
            adminIds: ['other-admin', 'extra-admin'],
          ),
        },
      );
      final r = _rulesFor('other-admin', db: db);
      expect(r.isAdminOf('biz-003'), isTrue);
    });

    test('SEC-013 타 사업장 관리자 → false', () {
      final r = _rulesFor('biz-admin-uid');
      expect(r.isAdminOf('biz-002'), isFalse);
    });

    test('SEC-014 미로그인 → false (isLoggedIn 체크)', () {
      final r = _rulesFor(null);
      expect(r.isAdminOf('biz-001'), isFalse);
    });

    test('SEC-015 일반 USER가 isAdminOf 호출 → false', () {
      final r = _rulesFor('user-uid');
      expect(r.isAdminOf('biz-001'), isFalse);
    });

    test('SEC-016 SUPER_ADMIN은 isAdminOf로 관리자 여부 판단 불가 (별도 isSuperAdmin 사용)', () {
      // 슈퍼어드민은 adminIds에 없어도 모든 작업을 isSuperAdmin()으로 허용
      final r = _rulesFor('super-uid');
      expect(r.isAdminOf('biz-001'), isFalse); // adminIds에 없음
      expect(r.isSuperAdmin(), isTrue); // 슈퍼어드민 경로로 허용
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 3 — isSubAdminOf(businessId) 검증
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-03: isSubAdminOf 함수', () {
    test('SEC-017 null businessId → false', () {
      final r = _rulesFor('sub-admin-uid');
      expect(r.isSubAdminOf(null), isFalse);
    });

    test('SEC-018 빈 문자열 businessId → false', () {
      final r = _rulesFor('sub-admin-uid');
      expect(r.isSubAdminOf(''), isFalse);
    });

    test('SEC-019 subAdminOf 일치 → true', () {
      final r = _rulesFor('sub-admin-uid');
      expect(r.isSubAdminOf('biz-001'), isTrue);
    });

    test('SEC-020 다른 사업장 ID → false', () {
      final r = _rulesFor('sub-admin-uid');
      expect(r.isSubAdminOf('biz-002'), isFalse);
    });

    test('SEC-021 subAdminOf 없는 일반 USER → false', () {
      final r = _rulesFor('user-uid');
      expect(r.isSubAdminOf('biz-001'), isFalse);
    });

    test('SEC-022 미로그인 → false', () {
      final r = _rulesFor(null);
      expect(r.isSubAdminOf('biz-001'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 4 — isNotBlacklisted / isNotRestricted
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-04: 블랙리스트·이용제한 함수', () {
    test('SEC-023 정상 USER → isNotBlacklisted=true', () {
      final r = _rulesFor('user-uid');
      expect(r.isNotBlacklisted(), isTrue);
    });

    test('SEC-024 isBlacklisted=true → isNotBlacklisted=false', () {
      final r = _rulesFor('blacklisted-uid');
      expect(r.isNotBlacklisted(), isFalse);
    });

    test('SEC-025 users 문서가 없는 UID → isNotBlacklisted=false (우회 차단)', () {
      final r = _rulesFor('ghost-uid');
      expect(r.isNotBlacklisted(), isFalse);
    });

    test('SEC-026 미로그인 → isNotBlacklisted=false', () {
      final r = _rulesFor(null);
      expect(r.isNotBlacklisted(), isFalse);
    });

    test('SEC-027 restrictedUntil=null → isNotRestricted=true', () {
      final r = _rulesFor('user-uid');
      expect(r.isNotRestricted(), isTrue);
    });

    test('SEC-028 restrictedUntil > 현재 시각 → isNotRestricted=false (제재 중)', () {
      final r = _rulesFor(
        'restricted-uid',
        time: DateTime(2026, 7, 8, 12, 0, 0),
      );
      expect(r.isNotRestricted(), isFalse);
    });

    test('SEC-029 restrictedUntil < 현재 시각 → isNotRestricted=true (제재 만료)', () {
      final db = _DB(
        users: {
          'past-restricted': _UserDoc(
            uid: 'past-restricted',
            role: 'USER',
            restrictedUntil: DateTime(2026, 1, 1, 0, 0, 0),
          ),
        },
      );
      final r = _rulesFor(
        'past-restricted',
        db: db,
        time: DateTime(2026, 7, 8, 12, 0, 0),
      );
      expect(r.isNotRestricted(), isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 5 — tos 컬렉션 get 규칙
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-05: tos get 규칙', () {
    final db = _buildStandardDB();
    final pubTO = db.tos['to-open-pub']!;
    final privTO = db.tos['to-open-priv']!;

    test('SEC-030 SUPER_ADMIN → 공개·비공개 모두 허용', () {
      final r = _rulesFor('super-uid', db: db);
      expect(r.tosGet(pubTO), isTrue);
      expect(r.tosGet(privTO), isTrue);
    });

    test('SEC-031 소속 BUSINESS_ADMIN → 비공개 TO 허용', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(r.tosGet(privTO), isTrue);
    });

    test('SEC-032 소속 SubAdmin → 비공개 TO 허용', () {
      final r = _rulesFor('sub-admin-uid', db: db);
      expect(r.tosGet(privTO), isTrue);
    });

    test('SEC-033 isPublished=true → 일반 USER도 허용', () {
      final r = _rulesFor('user-uid', db: db);
      expect(r.tosGet(pubTO), isTrue);
    });

    test('SEC-034 isPublished=false → 일반 USER 거부', () {
      final r = _rulesFor('user-uid', db: db);
      expect(r.tosGet(privTO), isFalse);
    });

    test('SEC-035 미로그인 → 공개 TO도 거부', () {
      final r = _rulesFor(null, db: db);
      expect(r.tosGet(pubTO), isFalse);
    });

    test('SEC-036 타 사업장 BUSINESS_ADMIN → 비공개 TO 거부', () {
      final r = _rulesFor('biz-admin-b-uid', db: db);
      expect(r.tosGet(privTO), isFalse); // biz-002 관리자, privTO는 biz-001
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 6 — tos 컬렉션 list 규칙
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-06: tos list 규칙', () {
    final db = _buildStandardDB();

    test('SEC-037 SUPER_ADMIN → 무조건 허용', () {
      final r = _rulesFor('super-uid', db: db);
      expect(r.tosList(filterBusinessId: null), isTrue);
    });

    test('SEC-038 BUSINESS_ADMIN + 소속 사업장 businessId 필터 → 허용', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(r.tosList(filterBusinessId: 'biz-001'), isTrue);
    });

    test('SEC-039 BUSINESS_ADMIN + 타 사업장 businessId 필터 → 거부', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(r.tosList(filterBusinessId: 'biz-002'), isFalse);
    });

    test('SEC-040 BUSINESS_ADMIN + null businessId 필터 → 거부 (whereIn 버그 시뮬레이션)', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(r.tosList(filterBusinessId: null), isFalse);
    });

    test('SEC-041 SubAdmin + 소속 사업장 businessId 필터 → 허용', () {
      final r = _rulesFor('sub-admin-uid', db: db);
      expect(r.tosList(filterBusinessId: 'biz-001'), isTrue);
    });

    test('SEC-042 SubAdmin + 타 사업장 businessId 필터 → 거부', () {
      final r = _rulesFor('sub-admin-uid', db: db);
      expect(r.tosList(filterBusinessId: 'biz-002'), isFalse);
    });

    test('SEC-043 USER + isPublished=true + limit<=50 → 허용', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.tosList(filterIsPublished: true, limit: 20),
        isTrue,
      );
    });

    test('SEC-044 USER + isPublished=false → 거부 (비공개 TO 덤프 차단)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.tosList(filterIsPublished: false, limit: 20),
        isFalse,
      );
    });

    test('SEC-045 USER + isPublished=true + limit=51 → 거부 (limit>50 덤프 방지)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.tosList(filterIsPublished: true, limit: 51),
        isFalse,
      );
    });

    test('SEC-046 USER + isPublished=true + limit=50 → 허용 (경계값)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.tosList(filterIsPublished: true, limit: 50),
        isTrue,
      );
    });

    test('SEC-047 미로그인 → 거부', () {
      final r = _rulesFor(null, db: db);
      expect(r.tosList(filterIsPublished: true, limit: 10), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 7 — tos 컬렉션 update 규칙 (관리자 경로)
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-07: tos update 관리자 경로', () {
    final db = _buildStandardDB();
    final openTO = db.tos['to-open-pub']!;
    final closedTO = db.tos['to-closed']!;
    final expiredTO = db.tos['to-expired']!;

    test('SEC-048 소속 관리자 → OPEN TO 일반 수정 허용', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(r.tosUpdateAdmin(openTO), isTrue);
    });

    test('SEC-049 SubAdmin → OPEN TO 수정 허용', () {
      final r = _rulesFor('sub-admin-uid', db: db);
      expect(r.tosUpdateAdmin(openTO), isTrue);
    });

    test('SEC-050 관리자가 businessId 변경 시도 → 거부 (항상 불변)', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(r.tosUpdateAdmin(openTO, changeBusinessId: true), isFalse);
    });

    test('SEC-051 SUPER_ADMIN의 businessId 변경 → 허용 (예외)', () {
      final r = _rulesFor('super-uid', db: db);
      expect(r.tosUpdateAdmin(openTO, changeBusinessId: true), isTrue);
    });

    test('SEC-052 CLOSED TO에서 workDetailId 변경 시도 → 거부', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(
        r.tosUpdateAdmin(closedTO, changeWorkDetailId: true),
        isFalse,
      );
    });

    test('SEC-053 EXPIRED TO에서 workDetailId 변경 시도 → 거부', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(
        r.tosUpdateAdmin(expiredTO, changeWorkDetailId: true),
        isFalse,
      );
    });

    test('SEC-054 SUPER_ADMIN의 CLOSED TO workDetailId 변경 → 허용 (예외)', () {
      final r = _rulesFor('super-uid', db: db);
      expect(
        r.tosUpdateAdmin(closedTO, changeWorkDetailId: true),
        isTrue,
      );
    });

    test('SEC-055 totalRequired를 totalConfirmed 미만으로 낮춤 → 거부', () {
      // openTO: totalRequired=5, totalConfirmed=2
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(
        r.tosUpdateAdmin(
          openTO,
          changeTotalRequired: true,
          newTotalRequired: 1, // totalConfirmed(2) 미만
        ),
        isFalse,
      );
    });

    test('SEC-056 totalRequired=0 (무제한)으로 변경 → 항상 허용', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(
        r.tosUpdateAdmin(
          openTO,
          changeTotalRequired: true,
          newTotalRequired: 0,
        ),
        isTrue,
      );
    });

    test('SEC-057 totalRequired >= totalConfirmed → 허용', () {
      // openTO: totalConfirmed=2
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(
        r.tosUpdateAdmin(
          openTO,
          changeTotalRequired: true,
          newTotalRequired: 3, // >= 2
        ),
        isTrue,
      );
    });

    test('SEC-058 타 사업장 관리자 → 거부', () {
      final r = _rulesFor('biz-admin-b-uid', db: db);
      expect(r.tosUpdateAdmin(openTO), isFalse);
    });

    test('SEC-059 미로그인 → 거부', () {
      final r = _rulesFor(null, db: db);
      expect(r.tosUpdateAdmin(openTO), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 8 — tos 컬렉션 update 규칙 (지원자 totalPending 카운터)
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-08: tos update 지원자 totalPending 카운터', () {
    final db = _buildStandardDB();

    test('SEC-060 USER + currentPending+1 → 허용 (지원)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(r.tosUpdateUserPending(5, 6), isTrue);
    });

    test('SEC-061 USER + currentPending-1 → 허용 (취소)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(r.tosUpdateUserPending(5, 4), isTrue);
    });

    test('SEC-062 USER + currentPending+2 → 거부 (±1 초과)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(r.tosUpdateUserPending(5, 7), isFalse);
    });

    test('SEC-063 USER + newPending<0 → 거부 (음수 방지)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(r.tosUpdateUserPending(0, -1), isFalse);
    });

    test('SEC-064 BUSINESS_ADMIN → 거부 (지원자 경로는 USER만)', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(r.tosUpdateUserPending(5, 6), isFalse);
    });

    test('SEC-065 미로그인 → 거부', () {
      final r = _rulesFor(null, db: db);
      expect(r.tosUpdateUserPending(5, 6), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 9 — applications 컬렉션 list 규칙
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-09: applications list 규칙', () {
    final db = _buildStandardDB();

    test('SEC-066 SUPER_ADMIN → 필터 없이 허용', () {
      final r = _rulesFor('super-uid', db: db);
      expect(r.applicationsList(), isTrue);
    });

    test('SEC-067 BUSINESS_ADMIN + 소속 businessId 필터 → 허용', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(r.applicationsList(filterBusinessId: 'biz-001'), isTrue);
    });

    test('SEC-068 BUSINESS_ADMIN + 타 사업장 businessId 필터 → 거부', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(r.applicationsList(filterBusinessId: 'biz-002'), isFalse);
    });

    test('SEC-069 SubAdmin + 소속 businessId 필터 → 허용', () {
      final r = _rulesFor('sub-admin-uid', db: db);
      expect(r.applicationsList(filterBusinessId: 'biz-001'), isTrue);
    });

    test('SEC-070 USER + uid 필터 == 본인 → 허용', () {
      final r = _rulesFor('user-uid', db: db);
      expect(r.applicationsList(filterUid: 'user-uid'), isTrue);
    });

    test('SEC-071 USER + uid 필터 == 타인 → 거부 (타인 지원서 열람 차단)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(r.applicationsList(filterUid: 'other-uid'), isFalse);
    });

    test('SEC-072 USER + uid 필터 없음 → 거부', () {
      final r = _rulesFor('user-uid', db: db);
      expect(r.applicationsList(), isFalse);
    });

    test('SEC-073 미로그인 → 거부', () {
      final r = _rulesFor(null, db: db);
      expect(r.applicationsList(filterUid: 'user-uid'), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 10 — applications 컬렉션 create 규칙 (지원자 경로)
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-10: applications create 지원자 경로', () {
    final db = _buildStandardDB();

    test('SEC-074 정상 USER 지원 → 허용', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.applicationsCreateUser(
          applicantUid: 'user-uid',
          toBusinessId: 'biz-001',
          appBusinessId: 'biz-001',
        ),
        isTrue,
      );
    });

    test('SEC-075 타인 명의 지원 (uid 위조) → 거부', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.applicationsCreateUser(
          applicantUid: 'other-uid', // auth.uid와 불일치
          toBusinessId: 'biz-001',
          appBusinessId: 'biz-001',
        ),
        isFalse,
      );
    });

    test('SEC-076 블랙리스트 사용자 지원 → 거부', () {
      final r = _rulesFor('blacklisted-uid', db: db);
      expect(
        r.applicationsCreateUser(
          applicantUid: 'blacklisted-uid',
          toBusinessId: 'biz-001',
          appBusinessId: 'biz-001',
        ),
        isFalse,
      );
    });

    test('SEC-077 이용제한(restrictedUntil) 사용자 지원 → 거부', () {
      final r = _rulesFor(
        'restricted-uid',
        db: db,
        time: DateTime(2026, 7, 8, 12, 0, 0),
      );
      expect(
        r.applicationsCreateUser(
          applicantUid: 'restricted-uid',
          toBusinessId: 'biz-001',
          appBusinessId: 'biz-001',
        ),
        isFalse,
      );
    });

    test('SEC-078 TO의 businessId와 지원서 businessId 불일치 → 거부 (교차 검증)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.applicationsCreateUser(
          applicantUid: 'user-uid',
          toBusinessId: 'biz-001',
          appBusinessId: 'biz-002', // 불일치!
        ),
        isFalse,
      );
    });

    test('SEC-079 미로그인 → 거부', () {
      final r = _rulesFor(null, db: db);
      expect(
        r.applicationsCreateUser(
          applicantUid: 'user-uid',
          toBusinessId: 'biz-001',
          appBusinessId: 'biz-001',
        ),
        isFalse,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 11 — users 컬렉션 create 규칙 (본인 경로)
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-11: users create 본인 경로', () {
    final db = _buildStandardDB();

    test('SEC-080 정상 USER 회원가입 → 허용', () {
      final r = _rulesFor('new-uid', db: db);
      expect(
        r.usersCreateSelf(
          targetUid: 'new-uid',
          role: 'USER',
          accountStatus: 'active',
          isBlacklisted: false,
          subAdminOf: null,
          businessId: null,
          noShowCount: 0,
          lateCount: 0,
          totalWorkDays: 0,
          ci: null,
          ciHash: null,
        ),
        isTrue,
      );
    });

    test('SEC-081 BUSINESS_ADMIN 회원가입 → 허용', () {
      final r = _rulesFor('new-biz-uid', db: db);
      expect(
        r.usersCreateSelf(
          targetUid: 'new-biz-uid',
          role: 'BUSINESS_ADMIN',
          accountStatus: 'active',
          isBlacklisted: false,
          subAdminOf: null,
          businessId: null,
          noShowCount: 0,
          lateCount: 0,
          totalWorkDays: 0,
          ci: null,
          ciHash: null,
        ),
        isTrue,
      );
    });

    test('SEC-082 role=SUPER_ADMIN으로 회원가입 시도 → 거부', () {
      final r = _rulesFor('evil-uid', db: db);
      expect(
        r.usersCreateSelf(
          targetUid: 'evil-uid',
          role: 'SUPER_ADMIN', // 차단!
          accountStatus: 'active',
          isBlacklisted: false,
          subAdminOf: null,
          businessId: null,
          noShowCount: 0,
          lateCount: 0,
          totalWorkDays: 0,
          ci: null,
          ciHash: null,
        ),
        isFalse,
      );
    });

    test('SEC-083 isBlacklisted=true로 가입 시도 → 거부', () {
      final r = _rulesFor('evil-uid', db: db);
      expect(
        r.usersCreateSelf(
          targetUid: 'evil-uid',
          role: 'USER',
          accountStatus: 'active',
          isBlacklisted: true, // 차단!
          subAdminOf: null,
          businessId: null,
          noShowCount: 0,
          lateCount: 0,
          totalWorkDays: 0,
          ci: null,
          ciHash: null,
        ),
        isFalse,
      );
    });

    test('SEC-084 subAdminOf 설정해 가입 시도 → 거부 (CF trigger 전용)', () {
      final r = _rulesFor('evil-uid', db: db);
      expect(
        r.usersCreateSelf(
          targetUid: 'evil-uid',
          role: 'USER',
          accountStatus: 'active',
          isBlacklisted: false,
          subAdminOf: 'biz-001', // 차단!
          businessId: null,
          noShowCount: 0,
          lateCount: 0,
          totalWorkDays: 0,
          ci: null,
          ciHash: null,
        ),
        isFalse,
      );
    });

    test('SEC-085 ci 값 설정해 가입 시도 → 거부 (CF Admin SDK 전용)', () {
      final r = _rulesFor('evil-uid', db: db);
      expect(
        r.usersCreateSelf(
          targetUid: 'evil-uid',
          role: 'USER',
          accountStatus: 'active',
          isBlacklisted: false,
          subAdminOf: null,
          businessId: null,
          noShowCount: 0,
          lateCount: 0,
          totalWorkDays: 0,
          ci: 'some-ci-value', // 차단!
          ciHash: null,
        ),
        isFalse,
      );
    });

    test('SEC-086 isAdmin 키 포함 시도 → 거부', () {
      final r = _rulesFor('evil-uid', db: db);
      expect(
        r.usersCreateSelf(
          targetUid: 'evil-uid',
          role: 'USER',
          accountStatus: 'active',
          isBlacklisted: false,
          subAdminOf: null,
          businessId: null,
          noShowCount: 0,
          lateCount: 0,
          totalWorkDays: 0,
          ci: null,
          ciHash: null,
          hasIsAdminKey: true, // 차단!
        ),
        isFalse,
      );
    });

    test('SEC-087 noShowCount=1로 가입 시도 → 거부 (CF Admin SDK 전용)', () {
      final r = _rulesFor('evil-uid', db: db);
      expect(
        r.usersCreateSelf(
          targetUid: 'evil-uid',
          role: 'USER',
          accountStatus: 'active',
          isBlacklisted: false,
          subAdminOf: null,
          businessId: null,
          noShowCount: 1, // 차단!
          lateCount: 0,
          totalWorkDays: 0,
          ci: null,
          ciHash: null,
        ),
        isFalse,
      );
    });

    test('SEC-088 타인 UID로 문서 생성 시도 → 거부', () {
      final r = _rulesFor('my-uid', db: db);
      expect(
        r.usersCreateSelf(
          targetUid: 'someone-else-uid', // 불일치!
          role: 'USER',
          accountStatus: 'active',
          isBlacklisted: false,
          subAdminOf: null,
          businessId: null,
          noShowCount: 0,
          lateCount: 0,
          totalWorkDays: 0,
          ci: null,
          ciHash: null,
        ),
        isFalse,
      );
    });

    test('SEC-089 accountStatus=inactive로 가입 시도 → 거부', () {
      final r = _rulesFor('new-uid', db: db);
      expect(
        r.usersCreateSelf(
          targetUid: 'new-uid',
          role: 'USER',
          accountStatus: 'inactive', // 차단!
          isBlacklisted: false,
          subAdminOf: null,
          businessId: null,
          noShowCount: 0,
          lateCount: 0,
          totalWorkDays: 0,
          ci: null,
          ciHash: null,
        ),
        isFalse,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 12 — users 컬렉션 update 규칙 (본인)
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-12: users update 본인 경로 불변 필드 검증', () {
    final db = _buildStandardDB();

    test('SEC-090 허용 필드(displayName 등) 변경 → 허용', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.usersUpdateSelf(
          targetUid: 'user-uid',
          changedKeys: {'displayName', 'profileImageUrl', 'updatedAt'},
        ),
        isTrue,
      );
    });

    test('SEC-091 role 변경 시도 → 거부', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.usersUpdateSelf(
          targetUid: 'user-uid',
          changedKeys: {'role'}, // 차단!
        ),
        isFalse,
      );
    });

    test('SEC-092 isBlacklisted 변경 시도 → 거부', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.usersUpdateSelf(
          targetUid: 'user-uid',
          changedKeys: {'isBlacklisted'}, // 차단!
        ),
        isFalse,
      );
    });

    test('SEC-093 subAdminOf 변경 시도 → 거부 (CF trigger 전용)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.usersUpdateSelf(
          targetUid: 'user-uid',
          changedKeys: {'subAdminOf'}, // 차단!
        ),
        isFalse,
      );
    });

    test('SEC-094 businessId 변경 시도 → 거부 (교차 검증 우회 차단)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.usersUpdateSelf(
          targetUid: 'user-uid',
          changedKeys: {'businessId'}, // 차단!
        ),
        isFalse,
      );
    });

    test('SEC-095 accountStatus 변경 시도 → 거부 (승인 우회 차단)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.usersUpdateSelf(
          targetUid: 'user-uid',
          changedKeys: {'accountStatus'}, // 차단!
        ),
        isFalse,
      );
    });

    test('SEC-096 restrictedUntil 변경 시도 → 거부 (제재 해제 우회 차단)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.usersUpdateSelf(
          targetUid: 'user-uid',
          changedKeys: {'restrictedUntil'}, // 차단!
        ),
        isFalse,
      );
    });

    test('SEC-097 noShowCount·lateCount 변경 시도 → 거부 (CF Admin SDK 전용)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.usersUpdateSelf(
          targetUid: 'user-uid',
          changedKeys: {'noShowCount', 'lateCount'}, // 차단!
        ),
        isFalse,
      );
    });

    test('SEC-098 타인 문서 수정 시도 → 거부', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.usersUpdateSelf(
          targetUid: 'other-uid', // 불일치!
          changedKeys: {'displayName'},
        ),
        isFalse,
      );
    });

    test('SEC-099 sealBase64 변경 시도 → 거부 (계약서 위변조 차단)', () {
      final r = _rulesFor('user-uid', db: db);
      expect(
        r.usersUpdateSelf(
          targetUid: 'user-uid',
          changedKeys: {'sealBase64'}, // 차단!
        ),
        isFalse,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 13 — businesses 컬렉션 list 규칙
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-13: businesses list 규칙', () {
    final db = _buildStandardDB();

    test('SEC-100 SUPER_ADMIN → list 허용', () {
      final r = _rulesFor('super-uid', db: db);
      expect(r.businessesList(), isTrue);
    });

    test('SEC-101 BUSINESS_ADMIN → list 거부 (adminIds 덤프 방지)', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      expect(r.businessesList(), isFalse);
    });

    test('SEC-102 SubAdmin → list 거부', () {
      final r = _rulesFor('sub-admin-uid', db: db);
      expect(r.businessesList(), isFalse);
    });

    test('SEC-103 일반 USER → list 거부', () {
      final r = _rulesFor('user-uid', db: db);
      expect(r.businessesList(), isFalse);
    });

    test('SEC-104 미로그인 → list 거부', () {
      final r = _rulesFor(null, db: db);
      expect(r.businessesList(), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 14 — whereIn 복합쿼리 버그 방어 시나리오 (end-to-end)
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-14: whereIn 복합쿼리 버그 방어', () {
    final db = _buildStandardDB();

    test('SEC-105 whereIn → filters.businessId==null → isAdminOf(null)==false → 거부', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      // whereIn 복합쿼리 발생 시 Firebase가 null을 반환하는 상황 시뮬레이션
      final nullFromFilters = null as String?;
      expect(r.isAdminOf(nullFromFilters), isFalse);
      expect(r.tosList(filterBusinessId: nullFromFilters), isFalse);
      expect(r.applicationsList(filterBusinessId: nullFromFilters), isFalse);
    });

    test('SEC-106 isEqualTo 단건 쿼리 → filters.businessId 정상 반환 → 허용', () {
      final r = _rulesFor('biz-admin-uid', db: db);
      // isEqualTo 쿼리에서는 businessId가 정상 반환됨
      const bizId = 'biz-001';
      expect(r.isAdminOf(bizId), isTrue);
      expect(r.tosList(filterBusinessId: bizId), isTrue);
      expect(r.applicationsList(filterBusinessId: bizId), isTrue);
    });

    test('SEC-107 2사업장 관리자: 병렬 isEqualTo는 각각 허용, whereIn은 null로 거부', () {
      final db2 = _DB(
        users: {
          'multi-admin': const _UserDoc(
            uid: 'multi-admin',
            role: 'BUSINESS_ADMIN',
          ),
        },
        businesses: {
          'biz-A': const _BusinessDoc(
            id: 'biz-A',
            ownerId: 'multi-admin',
            adminIds: ['multi-admin'],
          ),
          'biz-B': const _BusinessDoc(
            id: 'biz-B',
            ownerId: 'multi-admin',
            adminIds: ['multi-admin'],
          ),
        },
      );
      final r = _rulesFor('multi-admin', db: db2);
      // 병렬 isEqualTo: 각 사업장별로 허용
      expect(r.isAdminOf('biz-A'), isTrue);
      expect(r.isAdminOf('biz-B'), isTrue);
      // whereIn 시뮬레이션: null → 거부
      expect(r.isAdminOf(null), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════════════════
  // GROUP 15 — 통합 시나리오 (복합 규칙 조합)
  // ══════════════════════════════════════════════════════════════════════════
  group('SCENARIO-SEC-15: 통합 접근 시나리오', () {
    final db = _buildStandardDB();

    test('SEC-108 블랙리스트 사용자: 모든 쓰기 경로 차단 검증', () {
      final r = _rulesFor('blacklisted-uid', db: db);
      // list는 허용 (블랙리스트는 create 차단)
      expect(r.isUser(), isTrue);
      // create 시 차단됨
      expect(r.isNotBlacklisted(), isFalse);
      expect(
        r.applicationsCreateUser(
          applicantUid: 'blacklisted-uid',
          toBusinessId: 'biz-001',
          appBusinessId: 'biz-001',
        ),
        isFalse,
      );
    });

    test('SEC-109 SubAdmin은 소속 사업장 TO 접근 허용, 타 사업장 접근 차단', () {
      final db2 = _DB(
        users: {
          'sub-a': const _UserDoc(
            uid: 'sub-a',
            role: 'USER',
            subAdminOf: 'biz-001',
          ),
        },
        businesses: {
          'biz-001': const _BusinessDoc(
            id: 'biz-001',
            ownerId: 'owner',
            adminIds: ['owner'],
          ),
          'biz-002': const _BusinessDoc(
            id: 'biz-002',
            ownerId: 'owner2',
            adminIds: ['owner2'],
          ),
        },
        tos: {
          'to-biz1': const _TODoc(
            id: 'to-biz1',
            businessId: 'biz-001',
            isPublished: false,
          ),
          'to-biz2': const _TODoc(
            id: 'to-biz2',
            businessId: 'biz-002',
            isPublished: false,
          ),
        },
      );
      final r = _rulesFor('sub-a', db: db2);
      expect(r.tosGet(db2.tos['to-biz1']!), isTrue); // 소속 사업장 비공개 TO: 허용
      expect(r.tosGet(db2.tos['to-biz2']!), isFalse); // 타 사업장 비공개 TO: 거부
    });

    test('SEC-110 USER가 타인 지원서 list 시도 → uid 필터 불일치로 거부', () {
      final r = _rulesFor('user-uid', db: db);
      expect(r.applicationsList(filterUid: 'user-uid'), isTrue); // 본인 OK
      expect(r.applicationsList(filterUid: 'biz-admin-uid'), isFalse); // 타인 거부
    });

    test('SEC-111 제재 만료 후 지원 가능', () {
      final db2 = _DB(
        users: {
          'was-restricted': _UserDoc(
            uid: 'was-restricted',
            role: 'USER',
            restrictedUntil: DateTime(2025, 12, 31), // 과거
          ),
        },
      );
      final r = _rulesFor(
        'was-restricted',
        db: db2,
        time: DateTime(2026, 7, 8, 12, 0),
      );
      expect(r.isNotRestricted(), isTrue);
      expect(
        r.applicationsCreateUser(
          applicantUid: 'was-restricted',
          toBusinessId: 'biz-001',
          appBusinessId: 'biz-001',
        ),
        isTrue,
      );
    });

    test('SEC-112 SUPER_ADMIN의 모든 특권 조합 검증', () {
      final r = _rulesFor('super-uid', db: db);
      // TO 비공개도 get 허용
      expect(r.tosGet(db.tos['to-open-priv']!), isTrue);
      // list 무제한 허용
      expect(r.tosList(), isTrue);
      // CLOSED TO 핵심 필드 수정 허용
      expect(
        r.tosUpdateAdmin(
          db.tos['to-closed']!,
          changeWorkDetailId: true,
          changeBusinessId: true,
        ),
        isTrue,
      );
      // businesses list 허용
      expect(r.businessesList(), isTrue);
      // applications list 필터 없이 허용
      expect(r.applicationsList(), isTrue);
    });
  });
}
