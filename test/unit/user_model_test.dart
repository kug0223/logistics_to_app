// test/unit/user_model_test.dart
// UserModel 순수 Dart getter 단위 테스트
//
// fromMap/fromFirestore는 Timestamp·암호화 의존 → 생략.
// 생성자를 직접 사용하여 Firebase 없이 검증.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/user_model.dart';

/// 최소 필드만 가진 UserModel 팩토리
UserModel _make({
  UserRole role = UserRole.USER,
  List<String>? subAdminBusinessIds,
  String? ci,
  DateTime? passVerifiedAt,
  String? foreignIdNumber,
  String accountStatus = 'active',
  DateTime? birthDate,
  DateTime? restrictedUntil,
}) {
  return UserModel(
    uid: 'uid-001',
    username: 'testuser',
    name: '홍길동',
    email: 'testuser@ALfit-system.com',
    role: role,
    subAdminBusinessIds: subAdminBusinessIds,
    ci: ci,
    passVerifiedAt: passVerifiedAt,
    foreignIdNumber: foreignIdNumber,
    accountStatus: accountStatus,
    birthDate: birthDate,
    restrictedUntil: restrictedUntil,
  );
}

void main() {
  // ══════════════════════════════════════════════════════
  // 역할 getter
  // ══════════════════════════════════════════════════════
  group('UserModel: 역할 getter', () {
    test('SUPER_ADMIN → isSuperAdmin=true, 나머지=false', () {
      final m = _make(role: UserRole.SUPER_ADMIN);
      expect(m.isSuperAdmin,    isTrue);
      expect(m.isBusinessAdmin, isFalse);
      expect(m.isUser,          isFalse);
      expect(m.isSubAdmin,      isFalse);
    });

    test('BUSINESS_ADMIN → isBusinessAdmin=true, 나머지=false', () {
      final m = _make(role: UserRole.BUSINESS_ADMIN);
      expect(m.isSuperAdmin,    isFalse);
      expect(m.isBusinessAdmin, isTrue);
      expect(m.isUser,          isFalse);
      expect(m.isSubAdmin,      isFalse);
    });

    test('USER(subAdminBusinessIds 없음) → isUser=true, isSubAdmin=false', () {
      final m = _make(role: UserRole.USER);
      expect(m.isUser,     isTrue);
      expect(m.isSubAdmin, isFalse);
    });

    test('USER + subAdminBusinessIds → isSubAdmin=true', () {
      final m = _make(role: UserRole.USER, subAdminBusinessIds: ['biz-001']);
      expect(m.isUser,     isTrue);
      expect(m.isSubAdmin, isTrue);
    });

    test('BUSINESS_ADMIN은 subAdminBusinessIds가 있어도 isSubAdmin=false (role 조건 불충족)', () {
      final m = _make(role: UserRole.BUSINESS_ADMIN, subAdminBusinessIds: ['biz-001']);
      expect(m.isSubAdmin, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════
  // isAdmin
  // ══════════════════════════════════════════════════════
  group('UserModel: isAdmin', () {
    test('SUPER_ADMIN → isAdmin=true', () {
      expect(_make(role: UserRole.SUPER_ADMIN).isAdmin, isTrue);
    });

    test('BUSINESS_ADMIN → isAdmin=true', () {
      expect(_make(role: UserRole.BUSINESS_ADMIN).isAdmin, isTrue);
    });

    test('USER(SubAdmin) → isAdmin=true', () {
      expect(_make(role: UserRole.USER, subAdminBusinessIds: ['biz-001']).isAdmin, isTrue);
    });

    test('일반 USER → isAdmin=false', () {
      expect(_make(role: UserRole.USER).isAdmin, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════
  // isForeign
  // ══════════════════════════════════════════════════════
  group('UserModel: isForeign', () {
    test('foreignIdNumber 없음 → false', () {
      expect(_make().isForeign, isFalse);
    });

    test('foreignIdNumber 있음 → true', () {
      expect(_make(foreignIdNumber: 'F-ENCRYPTED').isForeign, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // isPassVerified
  // ══════════════════════════════════════════════════════
  group('UserModel: isPassVerified', () {
    test('SUPER_ADMIN → 항상 true (시스템 계정)', () {
      expect(_make(role: UserRole.SUPER_ADMIN).isPassVerified, isTrue);
    });

    test('ci + passVerifiedAt 모두 있음 → true', () {
      final m = _make(
        ci: 'CI-ENCRYPTED',
        passVerifiedAt: DateTime(2026, 1, 1),
      );
      expect(m.isPassVerified, isTrue);
    });

    test('ci만 있고 passVerifiedAt 없음 → false', () {
      final m = _make(ci: 'CI-ENCRYPTED');
      expect(m.isPassVerified, isFalse);
    });

    test('둘 다 없음 → false', () {
      expect(_make().isPassVerified, isFalse);
    });
  });

  // ══════════════════════════════════════════════════════
  // isPending / isRejected
  // ══════════════════════════════════════════════════════
  group('UserModel: accountStatus getter', () {
    test('active → isPending=false, isRejected=false', () {
      final m = _make(accountStatus: 'active');
      expect(m.isPending,  isFalse);
      expect(m.isRejected, isFalse);
    });

    test('pending → isPending=true', () {
      final m = _make(accountStatus: 'pending');
      expect(m.isPending,  isTrue);
      expect(m.isRejected, isFalse);
    });

    test('rejected → isRejected=true', () {
      final m = _make(accountStatus: 'rejected');
      expect(m.isPending,  isFalse);
      expect(m.isRejected, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // isRestricted (시간 비교)
  // ══════════════════════════════════════════════════════
  group('UserModel: isRestricted', () {
    test('restrictedUntil=null → false', () {
      expect(_make(restrictedUntil: null).isRestricted, isFalse);
    });

    test('restrictedUntil 과거 → false (제재 만료)', () {
      final m = _make(restrictedUntil: DateTime(2020, 1, 1));
      expect(m.isRestricted, isFalse);
    });

    test('restrictedUntil 미래 → true (제재 중)', () {
      final m = _make(restrictedUntil: DateTime(2099, 12, 31));
      expect(m.isRestricted, isTrue);
    });
  });

  // ══════════════════════════════════════════════════════
  // age 계산 (현재 날짜 기준)
  // ══════════════════════════════════════════════════════
  group('UserModel: age', () {
    test('birthDate=null → null 반환', () {
      expect(_make().age, isNull);
    });

    test('2000-01-01 출생 → 26세 (생일 이미 지남, 현재 2026-07-02)', () {
      final m = _make(birthDate: DateTime(2000, 1, 1));
      expect(m.age, equals(26));
    });

    test('2000-12-31 출생 → 25세 (생일 아직 안 지남, 현재 2026-07-02)', () {
      final m = _make(birthDate: DateTime(2000, 12, 31));
      expect(m.age, equals(25));
    });

    test('오늘 출생 → 0세', () {
      final today = DateTime.now();
      final m = _make(birthDate: DateTime(today.year, today.month, today.day));
      expect(m.age, equals(0));
    });

    test('내일 출생 → 아직 생일 전이므로 -1', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final m = _make(birthDate: DateTime(tomorrow.year, tomorrow.month, tomorrow.day));
      expect(m.age, equals(-1));
    });
  });

  // ══════════════════════════════════════════════════════
  // 제재(restrictedUntil / isRestricted)
  // ══════════════════════════════════════════════════════
  //
  // [R7-FS-1 A] 여기에 `trustGrade` 10셀 + `trustGradeEmoji` 5셀이 있었다.
  //   신뢰도 **점수/등급** 체계가 제품에서 폐기됐다([5A.2A] — 모델의
  //   `storedTrustScore` 필드와 세 getter, `lib/utils/trust_score_helper.dart`
  //   가 함께 사라졌다). 그래서 이 파일은 **컴파일조차 되지 않고 있었다.**
  //
  //   등급을 되살리지 않는다. 대신 그 자리를 이어받은 canonical 축을
  //   여기서 잰다: 누적 노쇼가 만드는 **제재**(`restrictedUntil` /
  //   `isRestricted`). 폐기가 유지되는지는
  //   `test/utils/trust_score_helper_test.dart` 가 지킨다.
  group('UserModel: isRestricted', () {
    test('restrictedUntil 없음 → 제재 아님', () {
      expect(_make().isRestricted, isFalse);
    });

    test('미래 시각 → 제재 중', () {
      final m = _make(
          restrictedUntil: DateTime.now().add(const Duration(days: 1)));
      expect(m.isRestricted, isTrue);
    });

    test('지난 시각 → 제재 만료 (자동으로 풀린다)', () {
      final m = _make(
          restrictedUntil: DateTime.now().subtract(const Duration(days: 1)));
      expect(m.isRestricted, isFalse,
          reason: '만료를 지우는 writer 없이도 화면에서 풀려야 한다');
    });

    test('영구 제재 표식(year 9999) → 제재 중', () {
      // 관리자 화면이 9999 를 "영구" 로 읽는다. 경계가 흔들리면
      // 영구 제재가 조용히 풀린다.
      expect(_make(restrictedUntil: DateTime(9999)).isRestricted, isTrue);
    });
  });
}
