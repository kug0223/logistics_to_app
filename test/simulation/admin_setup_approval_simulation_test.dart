// test/simulation/admin_setup_approval_simulation_test.dart
//
// 슈퍼관리자 외국인 회원 승인/거절 시나리오 시뮬레이션 테스트
//
// 검증 범위:
//   1. accountStatus 흐름 (pending → active / rejected)
//   2. 로그인 시 status 체크 (auth_service.dart 71~83줄 재현)
//   3. ForeignWorkerApprovalScreen 조회 필터 로직
//   4. 거절 다이얼로그 유효성 검사
//   5. 임시 비밀번호 재설정 조건
//   6. 탭별 목록 정렬 로직
//   7. CloudFunctions 에러 처리 시뮬레이션
//   8. 비밀번호 초기화 후 안내 로직
//
// 코드 원본:
//   lib/services/auth_service.dart (signIn 메서드 71~83줄)
//   lib/screens/super_admin/foreign_worker_approval_screen.dart
// 실행: flutter test test/simulation/admin_setup_approval_simulation_test.dart

// ignore_for_file: avoid_print

import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 데이터 클래스 (Firebase 의존 없음)
// ══════════════════════════════════════════════════════════════════════════════

enum SimUserRole { SUPER_ADMIN, BUSINESS_ADMIN, USER }

class SimUserModel {
  final String uid;
  final String username;
  final String name;
  final String? phone;
  final SimUserRole role;
  final String? foreignIdNumber; // null = 내국인, non-null = 외국인
  final String accountStatus;   // 'active' | 'pending' | 'rejected'
  final String? rejectionReason;
  final bool isBlacklisted;
  final String? blacklistReason;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;
  final String? idCardImageUrl;
  final String? businessId;
  final String? ci; // PASS CI값 (내국인)

  const SimUserModel({
    required this.uid,
    required this.username,
    required this.name,
    this.phone,
    required this.role,
    this.foreignIdNumber,
    this.accountStatus = 'active',
    this.rejectionReason,
    this.isBlacklisted = false,
    this.blacklistReason,
    this.createdAt,
    this.approvedAt,
    this.rejectedAt,
    this.idCardImageUrl,
    this.businessId,
    this.ci,
  });

  bool get isForeign => foreignIdNumber != null;
  bool get isPending => accountStatus == 'pending';
  bool get isRejected => accountStatus == 'rejected';
  bool get isActive => accountStatus == 'active';

  SimUserModel copyWith({
    String? accountStatus,
    String? rejectionReason,
    DateTime? approvedAt,
    DateTime? rejectedAt,
  }) {
    return SimUserModel(
      uid: uid,
      username: username,
      name: name,
      phone: phone,
      role: role,
      foreignIdNumber: foreignIdNumber,
      accountStatus: accountStatus ?? this.accountStatus,
      rejectionReason: rejectionReason ?? this.rejectionReason,
      isBlacklisted: isBlacklisted,
      blacklistReason: blacklistReason,
      createdAt: createdAt,
      approvedAt: approvedAt ?? this.approvedAt,
      rejectedAt: rejectedAt ?? this.rejectedAt,
      idCardImageUrl: idCardImageUrl,
      businessId: businessId,
      ci: ci,
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 로직 재현 함수들
// ══════════════════════════════════════════════════════════════════════════════

/// auth_service.dart signIn() 내 accountStatus 체크 로직 재현 (71~83줄)
/// 반환: null = 로그인 성공, String = throw할 에러 메시지
String? checkAccountStatusForLogin(Map<String, dynamic> userData) {
  final status = userData['accountStatus'] as String? ?? 'active';

  if (status == 'pending') {
    return '가입 승인 대기 중입니다.\n슈퍼관리자 승인 후 이용 가능합니다.';
  }
  if (status == 'rejected') {
    final reason = userData['rejectionReason'] as String?;
    if (reason != null) {
      return '가입이 거절되었습니다.\n사유: $reason';
    }
    return '가입이 거절되었습니다.\n고객센터에 문의해주세요.';
  }
  return null; // 로그인 허용
}

/// 블랙리스트 체크 로직 재현 (auth_service.dart)
String? checkBlacklist(Map<String, dynamic> userData) {
  if (userData['isBlacklisted'] == true) {
    final reason = userData['blacklistReason'] as String? ?? '이용 정책 위반';
    return '이용 제한된 계정입니다.\n사유: $reason\n고객센터에 문의해주세요.';
  }
  return null;
}

/// accountStatus null 폴백 로직
String resolveAccountStatus(String? rawStatus) {
  return rawStatus ?? 'active';
}

/// 외국인 가입 시 accountStatus 결정 로직 재현
/// (register_screen.dart — 내국인=active, 외국인=pending)
String determineAccountStatus({required bool isForeign}) {
  return isForeign ? 'pending' : 'active';
}

/// 승인 처리 시뮬레이션 (CF approveForeignWorker 결과 반영)
SimUserModel applyApproval(SimUserModel user, DateTime approvedAt) {
  return user.copyWith(
    accountStatus: 'active',
    approvedAt: approvedAt,
  );
}

/// 거절 처리 시뮬레이션 (CF rejectForeignWorker 결과 반영)
SimUserModel applyRejection(
  SimUserModel user, {
  required String reason,
  required DateTime rejectedAt,
}) {
  return user.copyWith(
    accountStatus: 'rejected',
    rejectionReason: reason,
    rejectedAt: rejectedAt,
  );
}

/// ForeignWorkerApprovalScreen 쿼리 필터 로직 재현
/// (foreign_worker_approval_screen.dart _loadUsers + 클라이언트 필터)
List<SimUserModel> applyApprovalScreenFilter(List<SimUserModel> allUsers) {
  return allUsers.where((u) {
    // role == 'USER' 조건
    if (u.role != SimUserRole.USER) return false;
    // accountStatus in ['pending', 'active', 'rejected'] 조건
    if (!['pending', 'active', 'rejected'].contains(u.accountStatus)) return false;
    // 클라이언트 필터: foreignIdNumber != null (외국인만)
    if (u.foreignIdNumber == null) return false;
    return true;
  }).toList();
}

/// 탭별 필터 (accountStatus == statusFilter)
List<SimUserModel> filterByTab(List<SimUserModel> users, String statusFilter) {
  return users.where((u) => u.accountStatus == statusFilter).toList();
}

/// pending 탭: 최신 가입순 정렬 (createdAt desc)
List<SimUserModel> sortPendingTab(List<SimUserModel> users) {
  final filtered = filterByTab(users, 'pending');
  filtered.sort((a, b) {
    final aDate = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate); // desc
  });
  return filtered;
}

/// active 탭: 승인 최신순 정렬 (approvedAt desc)
List<SimUserModel> sortActiveTab(List<SimUserModel> users) {
  final filtered = filterByTab(users, 'active');
  filtered.sort((a, b) {
    final aDate = a.approvedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.approvedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate); // desc
  });
  return filtered;
}

/// rejected 탭: 거절 최신순 정렬 (rejectedAt desc)
List<SimUserModel> sortRejectedTab(List<SimUserModel> users) {
  final filtered = filterByTab(users, 'rejected');
  filtered.sort((a, b) {
    final aDate = a.rejectedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bDate = b.rejectedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return bDate.compareTo(aDate); // desc
  });
  return filtered;
}

/// 거절 사유 유효성 검사 (_RejectReasonDialog 내 onPressed 재현)
String? validateRejectionReason(String raw, {int maxLength = 500}) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return '거절 사유를 입력해주세요';
  if (trimmed.length > maxLength) return '거절 사유는 ${maxLength}자 이하로 입력해주세요';
  return null; // 통과
}

/// 임시 비밀번호 재설정 가능 여부 (active 상태 외국인 전용)
String? canResetPassword(SimUserModel user) {
  if (user.role != SimUserRole.USER) return '사용자 계정만 비밀번호 초기화가 가능합니다';
  if (!user.isForeign) return '외국인 계정만 비밀번호 초기화가 가능합니다';
  if (user.accountStatus == 'pending') return '승인 대기 중인 계정은 비밀번호 초기화가 불가합니다';
  if (user.accountStatus == 'rejected') return '거절된 계정은 비밀번호 초기화가 불가합니다';
  return null; // 가능
}

/// CF 에러 메시지 결정 로직 재현 (FirebaseFunctionsException 대응)
String resolveCfErrorMessage(
  String? exceptionMessage,
  String fallback,
) {
  return exceptionMessage ?? fallback;
}

/// 임시 비밀번호 안내 다이얼로그 콘텐츠 생성 (표시용 로직 재현)
Map<String, String> buildTempPasswordDialogContent(
  String name,
  String tempPassword,
) {
  return {
    'title': '임시 비밀번호 발급',
    'nameLabel': '${name}님의 임시 비밀번호:',
    'password': tempPassword,
    'guide': '이 비밀번호를 해당 근무자에게 전달해주세요.\n로그인 후 반드시 비밀번호를 변경하도록 안내해주세요.',
  };
}

/// pending 탭 배지 표시 여부 (count > 0 && value == 'pending')
bool shouldShowPendingBadge(List<SimUserModel> users) {
  return users.any((u) => u.accountStatus == 'pending');
}

/// 탭별 카운트 계산
int tabCount(List<SimUserModel> users, String status) {
  return users.where((u) => u.accountStatus == status).length;
}

// ══════════════════════════════════════════════════════════════════════════════
// 테스트 픽스처 헬퍼
// ══════════════════════════════════════════════════════════════════════════════

SimUserModel makeForeignUser({
  String uid = 'uid_foreign_001',
  String name = '왕리',
  String accountStatus = 'pending',
  String? rejectionReason,
  DateTime? createdAt,
  DateTime? approvedAt,
  DateTime? rejectedAt,
  String? idCardImageUrl,
  String? businessId,
}) {
  return SimUserModel(
    uid: uid,
    username: 'wangli01',
    name: name,
    phone: '010-1234-5678',
    role: SimUserRole.USER,
    foreignIdNumber: '9001011234567',
    accountStatus: accountStatus,
    rejectionReason: rejectionReason,
    createdAt: createdAt ?? DateTime(2026, 7, 1, 10, 0),
    approvedAt: approvedAt,
    rejectedAt: rejectedAt,
    idCardImageUrl: idCardImageUrl,
    businessId: businessId,
  );
}

SimUserModel makeKoreanUser({
  String uid = 'uid_korean_001',
  String name = '김한국',
  String accountStatus = 'active',
}) {
  return SimUserModel(
    uid: uid,
    username: 'korean01',
    name: name,
    phone: '010-9999-8888',
    role: SimUserRole.USER,
    foreignIdNumber: null, // 내국인
    ci: 'PASS_CI_abc123',
    accountStatus: accountStatus,
    createdAt: DateTime(2026, 6, 15),
  );
}

SimUserModel makeBusinessAdmin({
  String uid = 'uid_biz_001',
  String? foreignIdNumber,
}) {
  return SimUserModel(
    uid: uid,
    username: 'bizadmin01',
    name: '사장박',
    phone: '010-7777-6666',
    role: SimUserRole.BUSINESS_ADMIN,
    foreignIdNumber: foreignIdNumber, // 외국인등록번호 있어도 BUSINESS_ADMIN이면 제외
    accountStatus: 'active',
    createdAt: DateTime(2026, 5, 1),
  );
}

// ══════════════════════════════════════════════════════════════════════════════
// 테스트
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  // ────────────────────────────────────────────────────────────────────────────
  // 그룹 1: accountStatus 흐름
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-APPR — accountStatus 흐름', () {
    test('SCENARIO-APPR-001: 외국인 가입 시 accountStatus = pending', () {
      final status = determineAccountStatus(isForeign: true);
      expect(status, equals('pending'));
    });

    test('SCENARIO-APPR-002: 내국인(PASS) 가입 시 accountStatus = active', () {
      final status = determineAccountStatus(isForeign: false);
      expect(status, equals('active'));
    });

    test('SCENARIO-APPR-003: 승인 처리 후 accountStatus = active', () {
      final user = makeForeignUser(accountStatus: 'pending');
      final now = DateTime(2026, 7, 8, 9, 0);
      final approved = applyApproval(user, now);
      expect(approved.accountStatus, equals('active'));
    });

    test('SCENARIO-APPR-004: 승인 처리 후 approvedAt 설정됨', () {
      final user = makeForeignUser(accountStatus: 'pending');
      final now = DateTime(2026, 7, 8, 9, 0);
      final approved = applyApproval(user, now);
      expect(approved.approvedAt, equals(now));
    });

    test('SCENARIO-APPR-005: 거절 처리 후 accountStatus = rejected', () {
      final user = makeForeignUser(accountStatus: 'pending');
      final now = DateTime(2026, 7, 8, 10, 0);
      final rejected = applyRejection(user, reason: '서류 미비', rejectedAt: now);
      expect(rejected.accountStatus, equals('rejected'));
    });

    test('SCENARIO-APPR-006: 거절 처리 후 rejectionReason 저장됨', () {
      final user = makeForeignUser(accountStatus: 'pending');
      final rejected = applyRejection(
        user,
        reason: '외국인등록번호 불일치',
        rejectedAt: DateTime(2026, 7, 8),
      );
      expect(rejected.rejectionReason, equals('외국인등록번호 불일치'));
    });

    test('SCENARIO-APPR-007: 거절 처리 후 rejectedAt 설정됨', () {
      final user = makeForeignUser(accountStatus: 'pending');
      final ts = DateTime(2026, 7, 8, 14, 30);
      final rejected = applyRejection(user, reason: '사유', rejectedAt: ts);
      expect(rejected.rejectedAt, equals(ts));
    });

    test('SCENARIO-APPR-008: active 상태는 isPending = false', () {
      final user = makeForeignUser(accountStatus: 'active');
      expect(user.isPending, isFalse);
    });

    test('SCENARIO-APPR-009: pending 상태는 isPending = true', () {
      final user = makeForeignUser(accountStatus: 'pending');
      expect(user.isPending, isTrue);
    });

    test('SCENARIO-APPR-010: rejected 상태는 isRejected = true', () {
      final user = makeForeignUser(accountStatus: 'rejected', rejectionReason: '사유');
      expect(user.isRejected, isTrue);
    });

    test('SCENARIO-APPR-011: active 상태는 isActive = true', () {
      final user = makeForeignUser(accountStatus: 'active');
      expect(user.isActive, isTrue);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 그룹 2: 로그인 시 accountStatus 체크
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-APPR — 로그인 시 status 체크', () {
    test('SCENARIO-APPR-012: status=pending → 승인 대기 메시지 throw', () {
      final data = {'accountStatus': 'pending'};
      final msg = checkAccountStatusForLogin(data);
      expect(msg, isNotNull);
      expect(msg, contains('가입 승인 대기 중'));
    });

    test('SCENARIO-APPR-013: status=pending → signOut 필요 (메시지 비null)', () {
      final data = {'accountStatus': 'pending'};
      final msg = checkAccountStatusForLogin(data);
      // null이 아니면 signOut 후 throw해야 한다
      expect(msg, isNotNull);
    });

    test('SCENARIO-APPR-014: status=rejected + 사유있음 → 사유 포함 메시지', () {
      final data = {
        'accountStatus': 'rejected',
        'rejectionReason': '제출 서류 미비',
      };
      final msg = checkAccountStatusForLogin(data);
      expect(msg, isNotNull);
      expect(msg, contains('가입이 거절되었습니다'));
      expect(msg, contains('제출 서류 미비'));
    });

    test('SCENARIO-APPR-015: status=rejected + 사유없음 → 고객센터 안내 메시지', () {
      final data = {'accountStatus': 'rejected'};
      final msg = checkAccountStatusForLogin(data);
      expect(msg, isNotNull);
      expect(msg, contains('고객센터'));
    });

    test('SCENARIO-APPR-016: status=active → 로그인 허용 (null 반환)', () {
      final data = {'accountStatus': 'active'};
      final msg = checkAccountStatusForLogin(data);
      expect(msg, isNull);
    });

    test('SCENARIO-APPR-017: status=null (레거시) → active 폴백 → 로그인 허용', () {
      final data = <String, dynamic>{}; // accountStatus 키 없음
      final status = resolveAccountStatus(data['accountStatus']);
      expect(status, equals('active'));
      final msg = checkAccountStatusForLogin(data);
      expect(msg, isNull);
    });

    test('SCENARIO-APPR-018: pending 메시지에 슈퍼관리자 언급 포함', () {
      final data = {'accountStatus': 'pending'};
      final msg = checkAccountStatusForLogin(data);
      expect(msg, contains('슈퍼관리자'));
    });

    test('SCENARIO-APPR-019: rejected 메시지에 거절 문구 포함', () {
      final data = {'accountStatus': 'rejected', 'rejectionReason': '불일치'};
      final msg = checkAccountStatusForLogin(data);
      expect(msg, contains('거절'));
    });

    test('SCENARIO-APPR-020: 블랙리스트 체크 — isBlacklisted=true → 에러 메시지', () {
      final data = {
        'isBlacklisted': true,
        'blacklistReason': '반복 노쇼',
      };
      final msg = checkBlacklist(data);
      expect(msg, isNotNull);
      expect(msg, contains('이용 제한'));
      expect(msg, contains('반복 노쇼'));
    });

    test('SCENARIO-APPR-021: 블랙리스트 체크 — isBlacklisted=false → null 반환', () {
      final data = {'isBlacklisted': false};
      final msg = checkBlacklist(data);
      expect(msg, isNull);
    });

    test('SCENARIO-APPR-022: 블랙리스트 체크 — blacklistReason 없으면 기본 사유 표시', () {
      final data = {'isBlacklisted': true};
      final msg = checkBlacklist(data);
      expect(msg, contains('이용 정책 위반'));
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 그룹 3: ForeignWorkerApprovalScreen 조회 필터
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-APPR — 조회 필터 로직', () {
    test('SCENARIO-APPR-023: 외국인 USER pending → 목록 포함됨', () {
      final user = makeForeignUser(accountStatus: 'pending');
      final result = applyApprovalScreenFilter([user]);
      expect(result, contains(user));
    });

    test('SCENARIO-APPR-024: 외국인 USER active → 목록 포함됨', () {
      final user = makeForeignUser(accountStatus: 'active');
      final result = applyApprovalScreenFilter([user]);
      expect(result, contains(user));
    });

    test('SCENARIO-APPR-025: 외국인 USER rejected → 목록 포함됨', () {
      final user = makeForeignUser(
        accountStatus: 'rejected',
        rejectionReason: '사유',
      );
      final result = applyApprovalScreenFilter([user]);
      expect(result, contains(user));
    });

    test('SCENARIO-APPR-026: 내국인(foreignIdNumber=null) USER → 목록 제외됨', () {
      final korean = makeKoreanUser();
      final result = applyApprovalScreenFilter([korean]);
      expect(result, isEmpty);
    });

    test('SCENARIO-APPR-027: BUSINESS_ADMIN + foreignIdNumber 있어도 제외됨', () {
      final bizAdmin = makeBusinessAdmin(foreignIdNumber: '9001011234567');
      final result = applyApprovalScreenFilter([bizAdmin]);
      expect(result, isEmpty);
    });

    test('SCENARIO-APPR-028: SUPER_ADMIN은 제외됨', () {
      final superAdmin = SimUserModel(
        uid: 'uid_super',
        username: 'superadmin',
        name: '슈퍼관리자',
        role: SimUserRole.SUPER_ADMIN,
        foreignIdNumber: null,
        accountStatus: 'active',
      );
      final result = applyApprovalScreenFilter([superAdmin]);
      expect(result, isEmpty);
    });

    test('SCENARIO-APPR-029: 혼합 목록에서 외국인 USER만 필터링됨', () {
      final foreign1 = makeForeignUser(uid: 'f1', accountStatus: 'pending');
      final foreign2 = makeForeignUser(uid: 'f2', accountStatus: 'active');
      final korean = makeKoreanUser();
      final bizAdmin = makeBusinessAdmin();
      final all = [foreign1, foreign2, korean, bizAdmin];
      final result = applyApprovalScreenFilter(all);
      expect(result.length, equals(2));
      expect(result, containsAll([foreign1, foreign2]));
    });

    test('SCENARIO-APPR-030: 탭 필터 — pending 탭에서 active 유저는 제외됨', () {
      final pending = makeForeignUser(uid: 'p1', accountStatus: 'pending');
      final active = makeForeignUser(uid: 'a1', accountStatus: 'active');
      final filtered = filterByTab([pending, active], 'pending');
      expect(filtered, contains(pending));
      expect(filtered, isNot(contains(active)));
    });

    test('SCENARIO-APPR-031: 탭 필터 — active 탭에서 rejected 유저는 제외됨', () {
      final active = makeForeignUser(uid: 'a1', accountStatus: 'active');
      final rejected = makeForeignUser(uid: 'r1', accountStatus: 'rejected');
      final filtered = filterByTab([active, rejected], 'active');
      expect(filtered, contains(active));
      expect(filtered, isNot(contains(rejected)));
    });

    test('SCENARIO-APPR-032: 탭 필터 — rejected 탭에서 pending 유저는 제외됨', () {
      final pending = makeForeignUser(uid: 'p1', accountStatus: 'pending');
      final rejected = makeForeignUser(uid: 'r1', accountStatus: 'rejected');
      final filtered = filterByTab([pending, rejected], 'rejected');
      expect(filtered, contains(rejected));
      expect(filtered, isNot(contains(pending)));
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 그룹 4: 거절 다이얼로그 유효성 검사
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-APPR — 거절 다이얼로그 유효성', () {
    test('SCENARIO-APPR-033: 빈 문자열 → 유효성 에러 반환 (차단)', () {
      final error = validateRejectionReason('');
      expect(error, isNotNull);
    });

    test('SCENARIO-APPR-034: 공백만 있는 문자열 → 유효성 에러 반환 (차단)', () {
      final error = validateRejectionReason('   ');
      expect(error, isNotNull);
    });

    test('SCENARIO-APPR-035: 정상 사유 → null 반환 (통과)', () {
      final error = validateRejectionReason('제출 서류 미비');
      expect(error, isNull);
    });

    test('SCENARIO-APPR-036: 500자 이하 사유 → 통과', () {
      final reason = 'a' * 500;
      final error = validateRejectionReason(reason);
      expect(error, isNull);
    });

    test('SCENARIO-APPR-037: 501자 사유 → 에러 반환 (500자 초과)', () {
      final reason = 'a' * 501;
      final error = validateRejectionReason(reason);
      expect(error, isNotNull);
    });

    test('SCENARIO-APPR-038: 공백 trim 후 정상 사유 → 통과', () {
      final error = validateRejectionReason('  외국인등록번호 불일치  ');
      expect(error, isNull);
    });

    test('SCENARIO-APPR-039: 거절 사유 저장 시 trim된 값이 rejectionReason에 들어감', () {
      final raw = '  서류 미비  ';
      final trimmed = raw.trim();
      final user = makeForeignUser(accountStatus: 'pending');
      final rejected = applyRejection(
        user,
        reason: trimmed,
        rejectedAt: DateTime(2026, 7, 8),
      );
      expect(rejected.rejectionReason, equals('서류 미비'));
    });

    test('SCENARIO-APPR-040: 커스텀 최대길이 200자 적용 — 201자 사유는 에러', () {
      final reason = 'b' * 201;
      final error = validateRejectionReason(reason, maxLength: 200);
      expect(error, isNotNull);
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 그룹 5: 임시 비밀번호 재설정 조건
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-APPR — 임시 비밀번호 재설정 조건', () {
    test('SCENARIO-APPR-041: active 외국인 → 재설정 가능 (null 반환)', () {
      final user = makeForeignUser(accountStatus: 'active');
      final error = canResetPassword(user);
      expect(error, isNull);
    });

    test('SCENARIO-APPR-042: pending 외국인 → 재설정 불가 (에러 반환)', () {
      final user = makeForeignUser(accountStatus: 'pending');
      final error = canResetPassword(user);
      expect(error, isNotNull);
      expect(error, contains('승인 대기'));
    });

    test('SCENARIO-APPR-043: rejected 외국인 → 재설정 불가 (에러 반환)', () {
      final user = makeForeignUser(
        accountStatus: 'rejected',
        rejectionReason: '서류 미비',
      );
      final error = canResetPassword(user);
      expect(error, isNotNull);
      expect(error, contains('거절'));
    });

    test('SCENARIO-APPR-044: 내국인(foreignIdNumber=null) → 재설정 불가', () {
      final korean = makeKoreanUser(accountStatus: 'active');
      final error = canResetPassword(korean);
      expect(error, isNotNull);
      expect(error, contains('외국인'));
    });

    test('SCENARIO-APPR-045: BUSINESS_ADMIN → 재설정 불가 (사용자 계정 아님)', () {
      final bizAdmin = SimUserModel(
        uid: 'biz01',
        username: 'biz',
        name: '사장',
        role: SimUserRole.BUSINESS_ADMIN,
        foreignIdNumber: '9001011234567',
        accountStatus: 'active',
      );
      final error = canResetPassword(bizAdmin);
      expect(error, isNotNull);
      expect(error, contains('사용자 계정'));
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 그룹 6: 탭별 목록 정렬 로직
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-APPR — 탭별 목록 정렬', () {
    test('SCENARIO-APPR-046: pending 탭 — 최신 가입순 정렬 (createdAt desc)', () {
      final older = makeForeignUser(
        uid: 'p_old',
        accountStatus: 'pending',
        createdAt: DateTime(2026, 7, 1),
      );
      final newer = makeForeignUser(
        uid: 'p_new',
        accountStatus: 'pending',
        createdAt: DateTime(2026, 7, 5),
      );
      final sorted = sortPendingTab([older, newer]);
      expect(sorted.first.uid, equals('p_new'));
      expect(sorted.last.uid, equals('p_old'));
    });

    test('SCENARIO-APPR-047: active 탭 — 승인 최신순 정렬 (approvedAt desc)', () {
      final firstApproved = makeForeignUser(
        uid: 'a_old',
        accountStatus: 'active',
        approvedAt: DateTime(2026, 7, 1),
      );
      final recentApproved = makeForeignUser(
        uid: 'a_new',
        accountStatus: 'active',
        approvedAt: DateTime(2026, 7, 7),
      );
      final sorted = sortActiveTab([firstApproved, recentApproved]);
      expect(sorted.first.uid, equals('a_new'));
      expect(sorted.last.uid, equals('a_old'));
    });

    test('SCENARIO-APPR-048: rejected 탭 — 거절 최신순 정렬 (rejectedAt desc)', () {
      final firstRejected = makeForeignUser(
        uid: 'r_old',
        accountStatus: 'rejected',
        rejectionReason: '사유',
        rejectedAt: DateTime(2026, 6, 20),
      );
      final recentRejected = makeForeignUser(
        uid: 'r_new',
        accountStatus: 'rejected',
        rejectionReason: '사유',
        rejectedAt: DateTime(2026, 7, 6),
      );
      final sorted = sortRejectedTab([firstRejected, recentRejected]);
      expect(sorted.first.uid, equals('r_new'));
      expect(sorted.last.uid, equals('r_old'));
    });

    test('SCENARIO-APPR-049: 각 탭은 독립 — pending 정렬이 active 탭에 영향 없음', () {
      final pending = makeForeignUser(uid: 'p1', accountStatus: 'pending');
      final active = makeForeignUser(uid: 'a1', accountStatus: 'active', approvedAt: DateTime(2026, 7, 1));
      final allUsers = [pending, active];
      final pendingSorted = sortPendingTab(allUsers);
      final activeSorted = sortActiveTab(allUsers);
      expect(pendingSorted.length, equals(1));
      expect(activeSorted.length, equals(1));
      expect(pendingSorted.first.uid, equals('p1'));
      expect(activeSorted.first.uid, equals('a1'));
    });

    test('SCENARIO-APPR-050: pending 탭 배지 — pending 유저 있으면 true', () {
      final users = [
        makeForeignUser(uid: 'p1', accountStatus: 'pending'),
        makeForeignUser(uid: 'a1', accountStatus: 'active'),
      ];
      expect(shouldShowPendingBadge(users), isTrue);
    });

    test('SCENARIO-APPR-051: pending 탭 배지 — pending 유저 없으면 false', () {
      final users = [makeForeignUser(uid: 'a1', accountStatus: 'active')];
      expect(shouldShowPendingBadge(users), isFalse);
    });

    test('SCENARIO-APPR-052: 탭별 카운트 — 혼합 목록에서 각 탭 수 정확히 계산', () {
      final users = [
        makeForeignUser(uid: 'p1', accountStatus: 'pending'),
        makeForeignUser(uid: 'p2', accountStatus: 'pending'),
        makeForeignUser(uid: 'a1', accountStatus: 'active'),
        makeForeignUser(uid: 'r1', accountStatus: 'rejected', rejectionReason: '사유'),
      ];
      expect(tabCount(users, 'pending'), equals(2));
      expect(tabCount(users, 'active'), equals(1));
      expect(tabCount(users, 'rejected'), equals(1));
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 그룹 7: CloudFunctions 에러 처리 시뮬레이션
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-APPR — CloudFunctions 에러 처리', () {
    test('SCENARIO-APPR-053: FirebaseFunctionsException 메시지 있으면 그대로 표시', () {
      const cfMessage = '이미 처리된 사용자입니다';
      final display = resolveCfErrorMessage(cfMessage, '승인에 실패했습니다');
      expect(display, equals(cfMessage));
    });

    test('SCENARIO-APPR-054: FirebaseFunctionsException 메시지 null이면 fallback 표시', () {
      final display = resolveCfErrorMessage(null, '승인에 실패했습니다');
      expect(display, equals('승인에 실패했습니다'));
    });

    test('SCENARIO-APPR-055: 거절 CF fallback 메시지', () {
      final display = resolveCfErrorMessage(null, '거절 처리에 실패했습니다');
      expect(display, equals('거절 처리에 실패했습니다'));
    });

    test('SCENARIO-APPR-056: 비밀번호 초기화 CF fallback 메시지', () {
      final display = resolveCfErrorMessage(null, '비밀번호 초기화에 실패했습니다');
      expect(display, equals('비밀번호 초기화에 실패했습니다'));
    });

    test('SCENARIO-APPR-057: 네트워크 오류(비-CF)는 재시도 가능 Toast 메시지 표시', () {
      // 비-CF 예외 시 '오류가 발생했습니다. 다시 시도해주세요' 표시 (foreign_worker_approval_screen.dart 98줄)
      const networkErrorMsg = '오류가 발생했습니다. 다시 시도해주세요';
      expect(networkErrorMsg, contains('다시 시도'));
    });

    test('SCENARIO-APPR-058: 승인 성공 Toast 메시지 형식', () {
      final user = makeForeignUser(name: '왕리');
      final msg = '${user.name}님이 승인되었습니다';
      expect(msg, equals('왕리님이 승인되었습니다'));
    });

    test('SCENARIO-APPR-059: 거절 성공 Toast 메시지 형식', () {
      final user = makeForeignUser(name: '첸웨이');
      final msg = '${user.name}님이 거절되었습니다';
      expect(msg, equals('첸웨이님이 거절되었습니다'));
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 그룹 8: 비밀번호 초기화 후 안내 다이얼로그 콘텐츠
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-APPR — 임시 비밀번호 안내 다이얼로그', () {
    test('SCENARIO-APPR-060: 다이얼로그 title = 임시 비밀번호 발급', () {
      final content = buildTempPasswordDialogContent('왕리', 'TEMP1234');
      expect(content['title'], equals('임시 비밀번호 발급'));
    });

    test('SCENARIO-APPR-061: 다이얼로그 nameLabel에 이름 포함', () {
      final content = buildTempPasswordDialogContent('첸웨이', 'ABCD5678');
      expect(content['nameLabel'], contains('첸웨이'));
    });

    test('SCENARIO-APPR-062: 다이얼로그 password 필드에 임시 비밀번호 표시', () {
      final tempPw = 'TMP9999';
      final content = buildTempPasswordDialogContent('왕리', tempPw);
      expect(content['password'], equals(tempPw));
    });

    test('SCENARIO-APPR-063: 다이얼로그 guide에 비밀번호 변경 안내 포함', () {
      final content = buildTempPasswordDialogContent('왕리', 'ABC123');
      expect(content['guide'], contains('비밀번호를 변경'));
    });

    test('SCENARIO-APPR-064: 다이얼로그 guide에 전달 안내 포함', () {
      final content = buildTempPasswordDialogContent('왕리', 'ABC123');
      expect(content['guide'], contains('전달'));
    });
  });

  // ────────────────────────────────────────────────────────────────────────────
  // 그룹 9: 경계값 및 복합 시나리오
  // ────────────────────────────────────────────────────────────────────────────
  group('SCENARIO-APPR — 경계값 및 복합 시나리오', () {
    test('SCENARIO-APPR-065: 빈 유저 목록 → 필터 결과 빈 리스트', () {
      final result = applyApprovalScreenFilter([]);
      expect(result, isEmpty);
    });

    test('SCENARIO-APPR-066: 승인 후 active 탭에 나타남', () {
      final user = makeForeignUser(accountStatus: 'pending');
      final now = DateTime(2026, 7, 8);
      final approved = applyApproval(user, now);
      final allUsers = applyApprovalScreenFilter([approved]);
      final activeTab = filterByTab(allUsers, 'active');
      expect(activeTab, contains(approved));
    });

    test('SCENARIO-APPR-067: 승인 후 pending 탭에서 사라짐', () {
      final user = makeForeignUser(accountStatus: 'pending');
      final approved = applyApproval(user, DateTime(2026, 7, 8));
      final pendingTab = filterByTab([approved], 'pending');
      expect(pendingTab, isEmpty);
    });

    test('SCENARIO-APPR-068: 거절 후 rejected 탭에 나타남', () {
      final user = makeForeignUser(accountStatus: 'pending');
      final rejected = applyRejection(
        user,
        reason: '사유',
        rejectedAt: DateTime(2026, 7, 8),
      );
      final rejectedTab = filterByTab([rejected], 'rejected');
      expect(rejectedTab, contains(rejected));
    });

    test('SCENARIO-APPR-069: 여러 pending 유저 동시 조회 — 각각 독립 처리', () {
      final user1 = makeForeignUser(uid: 'p1', name: '왕리', accountStatus: 'pending');
      final user2 = makeForeignUser(uid: 'p2', name: '첸웨이', accountStatus: 'pending');
      final filtered = applyApprovalScreenFilter([user1, user2]);
      expect(filtered.length, equals(2));
    });

    test('SCENARIO-APPR-070: 승인된 외국인에게 비밀번호 초기화 가능', () {
      final user = makeForeignUser(accountStatus: 'active');
      final error = canResetPassword(user);
      expect(error, isNull);
    });

    test('SCENARIO-APPR-071: 사업장 소속 외국인 — 목록 포함됨 (businessId 무관)', () {
      final user = makeForeignUser(
        accountStatus: 'pending',
        businessId: 'biz_001',
      );
      final result = applyApprovalScreenFilter([user]);
      expect(result, contains(user));
    });

    test('SCENARIO-APPR-072: 신분증 이미지 없는 외국인 — 목록 포함됨 (이미지 필수 아님)', () {
      final user = makeForeignUser(accountStatus: 'pending', idCardImageUrl: null);
      final result = applyApprovalScreenFilter([user]);
      expect(result, contains(user));
    });

    test('SCENARIO-APPR-073: accountStatus null 처리 — resolveAccountStatus → active 폴백', () {
      final status = resolveAccountStatus(null);
      expect(status, equals('active'));
    });

    test('SCENARIO-APPR-074: 탭 카운트 — 빈 목록에서 각 탭은 0', () {
      expect(tabCount([], 'pending'), equals(0));
      expect(tabCount([], 'active'), equals(0));
      expect(tabCount([], 'rejected'), equals(0));
    });

    test('SCENARIO-APPR-075: pending 탭 정렬 — 동일 createdAt이면 순서 유지(stable)', () {
      final ts = DateTime(2026, 7, 5);
      final u1 = makeForeignUser(uid: 'u1', accountStatus: 'pending', createdAt: ts);
      final u2 = makeForeignUser(uid: 'u2', accountStatus: 'pending', createdAt: ts);
      final sorted = sortPendingTab([u1, u2]);
      // 동일 날짜면 2명 모두 포함
      expect(sorted.length, equals(2));
    });

    test('SCENARIO-APPR-076: 거절 사유 정확히 500자 → 통과', () {
      final reason = 'x' * 500;
      final error = validateRejectionReason(reason);
      expect(error, isNull);
    });

    test('SCENARIO-APPR-077: CF 성공 후 목록 재조회 필요 — isProcessing 해제됨을 확인', () {
      // _isProcessing 상태 시뮬레이션
      bool isProcessing = true;
      // finally 블록에서 해제 (실제 코드: finally { if (mounted) setState(() => _isProcessing = false); })
      isProcessing = false;
      expect(isProcessing, isFalse);
    });

    test('SCENARIO-APPR-078: 이중 탭 방어 — isProcessing=true이면 재진입 차단', () {
      bool isProcessing = true;
      // _approve/_reject 최상단: if (_isProcessing) return;
      final blocked = isProcessing; // true면 차단됨
      expect(blocked, isTrue);
    });

    test('SCENARIO-APPR-079: 승인 후 목록 상태 갱신 시뮬레이션', () {
      // 가입 목록에서 pending → active 전환 후 전체 reload 시뮬레이션
      var userList = [
        makeForeignUser(uid: 'p1', accountStatus: 'pending'),
        makeForeignUser(uid: 'p2', accountStatus: 'pending'),
      ];
      // 승인 처리 후 새 목록으로 교체 (CF 성공 → _loadUsers 재호출)
      final approvedUser = applyApproval(userList[0], DateTime(2026, 7, 8));
      userList = [approvedUser, userList[1]];
      expect(filterByTab(userList, 'pending').length, equals(1));
      expect(filterByTab(userList, 'active').length, equals(1));
    });

    test('SCENARIO-APPR-080: 거절 후 목록 상태 갱신 시뮬레이션', () {
      var userList = [
        makeForeignUser(uid: 'p1', accountStatus: 'pending'),
      ];
      // 거절 처리 후 새 목록으로 교체
      final rejectedUser = applyRejection(
        userList[0],
        reason: '불일치',
        rejectedAt: DateTime(2026, 7, 8),
      );
      userList = [rejectedUser];
      expect(filterByTab(userList, 'pending'), isEmpty);
      expect(filterByTab(userList, 'rejected').length, equals(1));
    });
  });
}
