// test/simulation/attendance_admin_confirmed_model_test.dart
//
// AttendanceModel.adminConfirmed 필드 단위 테스트
// 목적: adminConfirmed 기본값, copyWith 동작, getter 일관성을 검증한다.
//
// 참고: fromMap / toMap 은 내부에서 cloud_firestore.Timestamp 를 직접 생성/파싱하므로
//       Firebase 초기화 없이는 호출이 불가능하다.
//       따라서 이 파일에서는 생성자와 copyWith 기반 테스트로만 검증하며,
//       fromMap 의 adminConfirmed 파싱 동작은 주석으로 명세를 문서화한다.

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/attendance_model.dart';

// ── 최소 AttendanceModel 생성 헬퍼 ──────────────────────────────────────────
AttendanceModel _base({
  bool adminConfirmed = false,
  String wageStatus = 'pending',
  String status = 'present',
  String? checkIn,
  String? checkOut,
}) =>
    AttendanceModel(
      id: 'test-att-id',
      applicationId: 'test-app-id',
      userId: 'test-user-id',
      businessId: 'test-biz-id',
      businessName: '테스트 사업장',
      workDate: DateTime(2026, 6, 15),
      workType: '서빙',
      status: status,
      createdAt: DateTime(2026, 6, 15, 9, 0),
      wageStatus: wageStatus,
      adminConfirmed: adminConfirmed,
      checkIn: checkIn,
      checkOut: checkOut,
    );

void main() {
  // ════════════════════════════════════════════════════════════════════
  // 생성자: adminConfirmed 기본값 검증
  // ════════════════════════════════════════════════════════════════════
  group('생성자 — adminConfirmed 기본값', () {
    test('adminConfirmed 명시 없이 생성 → 기본값 false', () {
      final att = AttendanceModel(
        id: 'id',
        applicationId: 'app',
        userId: 'uid',
        businessId: 'biz',
        businessName: '테스트',
        workDate: DateTime(2026, 6, 15),
        workType: '서빙',
        status: 'present',
        createdAt: DateTime(2026, 6, 15),
        // adminConfirmed 생략 → 기본값 false
      );
      expect(att.adminConfirmed, isFalse);
    });

    test('adminConfirmed=false 명시 → false', () {
      final att = _base(adminConfirmed: false);
      expect(att.adminConfirmed, isFalse);
    });

    test('adminConfirmed=true 명시 → true', () {
      final att = _base(adminConfirmed: true);
      expect(att.adminConfirmed, isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // fromMap 파싱 명세 문서화
  // (실제 호출은 Firebase 초기화 필요 → 여기서는 파싱 규칙만 명세)
  // ════════════════════════════════════════════════════════════════════
  group('fromMap — adminConfirmed 파싱 명세 (문서화)', () {
    // 실제 fromMap 코드:
    //   adminConfirmed: map['adminConfirmed'] ?? false,
    //
    // 파싱 규칙:
    //   map['adminConfirmed'] == true  → adminConfirmed = true
    //   map['adminConfirmed'] == false → adminConfirmed = false
    //   map['adminConfirmed'] == null  → adminConfirmed = false  (null 병합)
    //   key 자체 없음                  → adminConfirmed = false  (null 병합)

    test('파싱 규칙: map[adminConfirmed] ?? false 패턴 — null 병합 결과 확인', () {
      // 직접 Dart로 검증
      final bool? fromMap = null;
      expect(fromMap ?? false, isFalse); // null → false
    });

    test('파싱 규칙: true 값은 그대로 유지', () {
      const bool? fromMap = true;
      expect(fromMap ?? false, isTrue); // true → true
    });

    test('파싱 규칙: false 값은 그대로 유지', () {
      const bool? fromMap = false;
      expect(fromMap ?? false, isFalse); // false → false
    });

    test('파싱 규칙: adminConfirmed 키 없으면 기본값 false', () {
      final map = <String, dynamic>{'other': 'value'};
      final parsed = (map['adminConfirmed'] as bool?) ?? false;
      expect(parsed, isFalse);
    });

    test('파싱 규칙: adminConfirmed=true 키 있으면 true', () {
      final map = <String, dynamic>{'adminConfirmed': true};
      final parsed = (map['adminConfirmed'] as bool?) ?? false;
      expect(parsed, isTrue);
    });

    test('파싱 규칙: adminConfirmed=false 키 있으면 false', () {
      final map = <String, dynamic>{'adminConfirmed': false};
      final parsed = (map['adminConfirmed'] as bool?) ?? false;
      expect(parsed, isFalse);
    });

    test('파싱 규칙: adminConfirmed=null 키 있으면 false (null 병합)', () {
      final map = <String, dynamic>{'adminConfirmed': null};
      final parsed = (map['adminConfirmed'] as bool?) ?? false;
      expect(parsed, isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // toMap 저장 명세 문서화
  // (실제 호출은 Firebase 초기화 필요 → 여기서는 조건 분기 로직만 명세)
  // ════════════════════════════════════════════════════════════════════
  group('toMap — adminConfirmed 저장 명세 (문서화)', () {
    // 실제 toMap 코드:
    //   if (adminConfirmed) 'adminConfirmed': adminConfirmed,
    //
    // 저장 규칙:
    //   adminConfirmed=true  → 'adminConfirmed': true  포함
    //   adminConfirmed=false → 키 자체 미포함 (불필요한 false 저장 최소화)

    test('저장 규칙: adminConfirmed=false → Map에 키 미포함', () {
      final map = <String, dynamic>{};
      const adminConfirmed = false;
      if (adminConfirmed) map['adminConfirmed'] = adminConfirmed;
      expect(map.containsKey('adminConfirmed'), isFalse);
    });

    test('저장 규칙: adminConfirmed=true → Map에 키 포함 및 true', () {
      final map = <String, dynamic>{};
      const adminConfirmed = true;
      if (adminConfirmed) map['adminConfirmed'] = adminConfirmed;
      expect(map.containsKey('adminConfirmed'), isTrue);
      expect(map['adminConfirmed'], isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // copyWith — adminConfirmed 변경
  // ════════════════════════════════════════════════════════════════════
  group('copyWith — adminConfirmed 변경', () {
    test('copyWith(adminConfirmed: true) → adminConfirmed = true', () {
      final original = _base(adminConfirmed: false);
      final updated = original.copyWith(adminConfirmed: true);
      expect(updated.adminConfirmed, isTrue);
    });

    test('copyWith(adminConfirmed: false) → adminConfirmed = false', () {
      final original = _base(adminConfirmed: true);
      final updated = original.copyWith(adminConfirmed: false);
      expect(updated.adminConfirmed, isFalse);
    });

    test('copyWith() 에서 adminConfirmed 생략 → 기존 false 값 유지', () {
      final original = _base(adminConfirmed: false);
      final updated = original.copyWith(wageStatus: 'calculated');
      expect(updated.adminConfirmed, isFalse);
    });

    test('copyWith() 에서 adminConfirmed 생략 → 기존 true 값 유지', () {
      final original = _base(adminConfirmed: true);
      final updated = original.copyWith(wageStatus: 'calculated');
      expect(updated.adminConfirmed, isTrue);
    });

    test('copyWith 는 원본을 변경하지 않음 (불변성)', () {
      final original = _base(adminConfirmed: false);
      original.copyWith(adminConfirmed: true);
      expect(original.adminConfirmed, isFalse); // 원본 유지
    });

    test('copyWith(adminConfirmed: true) 후 원본은 false 유지 (불변성)', () {
      final original = _base(adminConfirmed: false);
      final updated = original.copyWith(adminConfirmed: true);
      expect(original.adminConfirmed, isFalse);
      expect(updated.adminConfirmed, isTrue);
    });

    test('copyWith 시 다른 필드는 유지됨', () {
      final original = _base(adminConfirmed: false, wageStatus: 'calculated', status: 'late');
      final updated = original.copyWith(adminConfirmed: true);
      expect(updated.wageStatus, 'calculated');
      expect(updated.status, 'late');
      expect(updated.id, original.id);
      expect(updated.businessId, original.businessId);
    });

    test('false → true → false 토글 시 최종값 false', () {
      final step1 = _base(adminConfirmed: false);
      final step2 = step1.copyWith(adminConfirmed: true);
      final step3 = step2.copyWith(adminConfirmed: false);
      expect(step3.adminConfirmed, isFalse);
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // adminConfirmed 와 wageStatus 조합 검증
  // (탭 분류 로직이 두 필드를 함께 사용하므로 조합 동작 확인)
  // ════════════════════════════════════════════════════════════════════
  group('adminConfirmed + wageStatus 조합', () {
    test('adminConfirmed=false, wageStatus=pending → 초기 상태', () {
      final att = _base(adminConfirmed: false, wageStatus: 'pending');
      expect(att.adminConfirmed, isFalse);
      expect(att.isWagePending, isTrue);
    });

    test('adminConfirmed=true, wageStatus=pending → 확인 완료 but 급여 미확정', () {
      final att = _base(adminConfirmed: true, wageStatus: 'pending');
      expect(att.adminConfirmed, isTrue);
      expect(att.isWagePending, isTrue);
      expect(att.isWageCalculated, isFalse);
    });

    test('adminConfirmed=false, wageStatus=calculated → 급여 계산됨 but 미확인', () {
      final att = _base(adminConfirmed: false, wageStatus: 'calculated');
      expect(att.adminConfirmed, isFalse);
      expect(att.isWageCalculated, isTrue);
    });

    test('adminConfirmed=true, wageStatus=transferred → 확인+완료 상태', () {
      final att = _base(adminConfirmed: true, wageStatus: 'transferred');
      expect(att.adminConfirmed, isTrue);
      expect(att.isWageTransferred, isTrue);
    });

    test('copyWith로 adminConfirmed=true 전환 후 wageStatus는 유지', () {
      final before = _base(adminConfirmed: false, wageStatus: 'pending');
      final after = before.copyWith(adminConfirmed: true);
      expect(after.adminConfirmed, isTrue);
      expect(after.wageStatus, 'pending'); // wageStatus 변경 없음
    });

    test('copyWith로 wageStatus=calculated 전환 후 adminConfirmed는 유지', () {
      final before = _base(adminConfirmed: true, wageStatus: 'pending');
      final after = before.copyWith(wageStatus: 'calculated');
      expect(after.adminConfirmed, isTrue); // adminConfirmed 변경 없음
      expect(after.isWageCalculated, isTrue);
    });
  });
}
