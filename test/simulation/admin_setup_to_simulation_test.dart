// test/simulation/admin_setup_to_simulation_test.dart
//
// 관리자 TO(근무공고) 생성 시나리오 시뮬레이션 테스트
//
// 검증 범위:
//   1. 사전조건 체크 (businessApproved / workTypesReady / contractTemplatesReady)
//   2. TO 타입별 필드 유효성 (flex / contract)
//   3. 계약기간 타입별 종료일 계산
//   4. 업무상세 유효성 (_createTO 검사 로직)
//   5. 사업주 날인(sealBase64) 체크
//   6. publishMode 분기 (immediate / scheduled)
//   7. visibleFrom 계산 로직 (flex scheduled)
//   8. SlotModel 자동 생성 (flex)
//   9. 사전조건 미충족 시 안내 플로우
//  10. TO 상태 흐름 (생성 → 마감 → 재오픈)
//
// Firebase 의존성 없음 — 순수 Dart 로직만 검증
//
// 실행: flutter test test/simulation/admin_setup_to_simulation_test.dart

import 'package:flutter_test/flutter_test.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 테스트용 경량 모델 · 상수
// ══════════════════════════════════════════════════════════════════════════════

/// 사전조건 상태 컨테이너 (create_to_screen.dart _allPrerequisitesMet 재현)
class _Prerequisites {
  final bool businessApproved;
  final bool workTypesReady;
  final bool contractTemplatesReady;

  const _Prerequisites({
    required this.businessApproved,
    required this.workTypesReady,
    required this.contractTemplatesReady,
  });

  bool get allMet => businessApproved && workTypesReady && contractTemplatesReady;
}

/// 업무 상세 입력 (WorkDetailInput 핵심 필드 재현)
class _WorkDetailInput {
  final String? workType;
  final int? wage;
  final int? requiredCount;
  final String? startTime;
  final String? endTime;
  final String wageType;

  const _WorkDetailInput({
    this.workType,
    this.wage,
    this.requiredCount,
    this.startTime,
    this.endTime,
    this.wageType = 'hourly',
  });

  bool get isValid =>
      workType != null &&
      workType!.isNotEmpty &&
      wage != null &&
      requiredCount != null &&
      startTime != null &&
      endTime != null;
}

/// TO 슬롯 (SlotModel 핵심 필드 재현)
class _Slot {
  final String id;
  final DateTime date;
  final String status;
  final bool isManualClosed;
  final DateTime? visibleFrom;
  final DateTime createdAt;

  const _Slot({
    required this.id,
    required this.date,
    this.status = 'open',
    this.isManualClosed = false,
    this.visibleFrom,
    required this.createdAt,
  });
}

/// TO 상태 상수 (TOStatus 재현)
abstract class _TOStatus {
  static const String active  = 'ACTIVE';
  static const String closed  = 'CLOSED';
  static const String full    = 'FULL';
  static const String expired = 'EXPIRED';
}

/// TO 타입 상수 (TOType 재현)
abstract class _TOType {
  static const String flex     = 'flex';
  static const String contract = 'contract';
}

// ══════════════════════════════════════════════════════════════════════════════
// 순수 로직 함수 (create_to_screen.dart 핵심 로직 추출)
// ══════════════════════════════════════════════════════════════════════════════

/// 사전조건 체크 결과 메시지
String _preCheckMessage(_Prerequisites pre) {
  if (!pre.businessApproved) return '사업장 승인 대기 중';
  if (!pre.workTypesReady) return '업무목록 미등록 — WorkTypeManagementScreen으로 이동 유도';
  if (!pre.contractTemplatesReady) return '계약서 템플릿 미등록 — ContractTemplateListScreen으로 이동 유도';
  return 'OK';
}

/// flex: 날짜 목록 유효성 검사
String? _validateFlexDates(List<DateTime> dates) {
  if (dates.isEmpty) return '날짜를 선택해주세요';
  return null;
}

/// flex: 과거 날짜 포함 여부
bool _hasFlexPastDate(List<DateTime> dates, DateTime today) {
  final todayOnly = DateTime(today.year, today.month, today.day);
  return dates.any((d) =>
      DateTime(d.year, d.month, d.day).isBefore(todayOnly));
}

/// contract: 계약기간 타입 유효성 검사
String? _validateContractPeriod({
  required String? periodType,
  required DateTime? rangeStart,
  required DateTime? rangeEnd,
}) {
  if (periodType == null) return '계약 기간을 선택해주세요';
  if (periodType == 'custom') {
    if (rangeStart == null || rangeEnd == null) {
      return '계약 시작일과 종료일을 설정해주세요';
    }
    if (rangeStart.isAfter(rangeEnd)) {
      return '계약 시작일이 종료일보다 이후일 수 없습니다';
    }
  }
  return null;
}

/// 업무상세 유효성 검사 (create_to_screen.dart _createTO 내 순서 그대로)
String? _validateWorkDetails(List<_WorkDetailInput> details) {
  if (details.isEmpty) return '최소 1개의 업무를 추가해주세요';
  if (details.any((w) => !w.isValid)) return '모든 업무 정보를 입력해주세요';
  if (details.any((w) => (w.wage ?? 0) <= 0)) return '급여는 0원보다 커야 합니다';
  if (details.any((w) => (w.wage ?? 0) > 50000000)) return '급여는 5,000만원 이하여야 합니다';
  if (details.any((w) => (w.requiredCount ?? 0) <= 0)) return '필요 인원은 1명 이상이어야 합니다';
  if (details.any((w) => (w.requiredCount ?? 0) > 10000)) return '필요 인원은 10,000명 이하여야 합니다';
  return null;
}

/// 사업주 날인 체크
String? _validateSeal(String? sealBase64) {
  if (sealBase64 == null || sealBase64.isEmpty) return '사업주 날인 미등록';
  return null;
}

/// 계약기간 종료일 계산 (TOModel.computeContractEndDate 재현)
DateTime _computeContractEndDate(String periodType, DateTime startDate) {
  switch (periodType) {
    case '15days':
      return startDate.add(const Duration(days: 14));
    case '1month':
      return DateTime(startDate.year, startDate.month + 2, 1)
          .subtract(const Duration(days: 1));
    case '3months':
      return DateTime(startDate.year, startDate.month + 4, 1)
          .subtract(const Duration(days: 1));
    case '6months':
      return DateTime(startDate.year, startDate.month + 7, 1)
          .subtract(const Duration(days: 1));
    case '1year':
      return DateTime(startDate.year + 1, startDate.month + 1, 1)
          .subtract(const Duration(days: 1));
    default:
      throw ArgumentError('알 수 없는 계약기간 타입: $periodType');
  }
}

/// flex scheduled: 슬롯별 visibleFrom 계산
/// 결과가 과거이면 null(즉시공개) 반환
DateTime? _computeSlotVisibleFrom({
  required DateTime slotDate,
  required int publishDaysBefore,
  required String publishTime, // 'HH:mm'
  required DateTime now,
}) {
  final parts = publishTime.split(':');
  final hour   = int.parse(parts[0]);
  final minute = int.parse(parts[1]);

  final visibleFrom = DateTime(
    slotDate.year,
    slotDate.month,
    slotDate.day - publishDaysBefore,
    hour,
    minute,
  );

  if (visibleFrom.isBefore(now)) return null; // 과거 → 즉시공개
  return visibleFrom;
}

/// flex TO 생성 시 슬롯 목록 생성
List<_Slot> _buildFlexSlots({
  required String toId,
  required List<DateTime> dates,
  required String publishMode,
  int? publishDaysBefore,
  String? publishTime,
  DateTime? now,
}) {
  final createdAt = now ?? DateTime.now();
  return dates.map((date) {
    DateTime? visibleFrom;
    if (publishMode == 'scheduled' && publishDaysBefore != null && publishTime != null) {
      visibleFrom = _computeSlotVisibleFrom(
        slotDate: date,
        publishDaysBefore: publishDaysBefore,
        publishTime: publishTime,
        now: createdAt,
      );
    }
    return _Slot(
      id: 'slot_${date.toIso8601String().substring(0, 10)}',
      date: date,
      status: 'open',
      isManualClosed: false,
      visibleFrom: visibleFrom,
      createdAt: createdAt,
    );
  }).toList();
}

/// TO 마감 처리 상태 계산
Map<String, dynamic> _closeTO({
  required String currentStatus,
  required String closedBy,
  required DateTime closedAt,
}) {
  return {
    'status': _TOStatus.closed,
    'isManualClosed': true,
    'closedAt': closedAt,
    'closedBy': closedBy,
  };
}

/// TO 재오픈 처리 상태 계산
Map<String, dynamic> _reopenTO({
  required String reopenedBy,
  required DateTime reopenedAt,
}) {
  return {
    'status': _TOStatus.active,
    'isManualClosed': false,
    'reopenedAt': reopenedAt,
    'reopenedBy': reopenedBy,
  };
}

// ══════════════════════════════════════════════════════════════════════════════
// main
// ══════════════════════════════════════════════════════════════════════════════

void main() {
  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 1: 사전조건 체크 (AND 조건)
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TO-01: 사전조건 체크 — 3가지 AND 조건', () {
    test('SCENARIO-TO-01-001: 3가지 모두 충족 → allMet=true, 폼 활성화', () {
      final pre = _Prerequisites(
        businessApproved: true,
        workTypesReady: true,
        contractTemplatesReady: true,
      );
      expect(pre.allMet, isTrue);
      expect(_preCheckMessage(pre), 'OK');
    });

    test('SCENARIO-TO-01-002: businessApproved=false → allMet=false, 폼 잠금', () {
      final pre = _Prerequisites(
        businessApproved: false,
        workTypesReady: true,
        contractTemplatesReady: true,
      );
      expect(pre.allMet, isFalse);
    });

    test('SCENARIO-TO-01-003: workTypesReady=false → allMet=false, 폼 잠금', () {
      final pre = _Prerequisites(
        businessApproved: true,
        workTypesReady: false,
        contractTemplatesReady: true,
      );
      expect(pre.allMet, isFalse);
    });

    test('SCENARIO-TO-01-004: contractTemplatesReady=false → allMet=false, 폼 잠금', () {
      final pre = _Prerequisites(
        businessApproved: true,
        workTypesReady: true,
        contractTemplatesReady: false,
      );
      expect(pre.allMet, isFalse);
    });

    test('SCENARIO-TO-01-005: 3가지 모두 미충족 → allMet=false', () {
      final pre = _Prerequisites(
        businessApproved: false,
        workTypesReady: false,
        contractTemplatesReady: false,
      );
      expect(pre.allMet, isFalse);
    });

    test('SCENARIO-TO-01-006: businessApproved+workTypesReady 충족, contractTemplates만 미충족 → allMet=false', () {
      final pre = _Prerequisites(
        businessApproved: true,
        workTypesReady: true,
        contractTemplatesReady: false,
      );
      expect(pre.allMet, isFalse);
    });

    test('SCENARIO-TO-01-007: businessApproved=false 메시지 → 사업장 승인 대기 중', () {
      final pre = _Prerequisites(
        businessApproved: false,
        workTypesReady: true,
        contractTemplatesReady: true,
      );
      expect(_preCheckMessage(pre), contains('사업장 승인 대기 중'));
    });

    test('SCENARIO-TO-01-008: workTypesReady=false 메시지 → WorkTypeManagementScreen 이동 유도', () {
      final pre = _Prerequisites(
        businessApproved: true,
        workTypesReady: false,
        contractTemplatesReady: true,
      );
      expect(_preCheckMessage(pre), contains('WorkTypeManagementScreen'));
    });

    test('SCENARIO-TO-01-009: contractTemplatesReady=false 메시지 → ContractTemplateListScreen 이동 유도', () {
      final pre = _Prerequisites(
        businessApproved: true,
        workTypesReady: true,
        contractTemplatesReady: false,
      );
      expect(_preCheckMessage(pre), contains('ContractTemplateListScreen'));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 2: flex 타입 날짜 유효성
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TO-02: flex 타입 — 날짜 유효성', () {
    test('SCENARIO-TO-02-001: 날짜 없음 → 차단 메시지 반환', () {
      final error = _validateFlexDates([]);
      expect(error, '날짜를 선택해주세요');
    });

    test('SCENARIO-TO-02-002: 날짜 1개 이상 → 통과', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final error = _validateFlexDates([tomorrow]);
      expect(error, isNull);
    });

    test('SCENARIO-TO-02-003: 날짜 여러 개 → 통과', () {
      final base = DateTime.now().add(const Duration(days: 1));
      final dates = List.generate(5, (i) => base.add(Duration(days: i)));
      final error = _validateFlexDates(dates);
      expect(error, isNull);
    });

    test('SCENARIO-TO-02-004: 과거 날짜 포함 → hasPastDate=true (경고 트리거)', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final tomorrow  = DateTime.now().add(const Duration(days: 1));
      final hasPast = _hasFlexPastDate([yesterday, tomorrow], DateTime.now());
      expect(hasPast, isTrue);
    });

    test('SCENARIO-TO-02-005: 미래 날짜만 → hasPastDate=false (경고 없음)', () {
      final future1 = DateTime.now().add(const Duration(days: 1));
      final future2 = DateTime.now().add(const Duration(days: 2));
      final hasPast = _hasFlexPastDate([future1, future2], DateTime.now());
      expect(hasPast, isFalse);
    });

    test('SCENARIO-TO-02-006: 오늘 날짜만 → 과거 날짜 아님 (hasPastDate=false)', () {
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final hasPast = _hasFlexPastDate([todayOnly], today);
      expect(hasPast, isFalse);
    });

    test('SCENARIO-TO-02-007: 어제 날짜만 → hasPastDate=true', () {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final hasPast = _hasFlexPastDate([yesterday], DateTime.now());
      expect(hasPast, isTrue);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 3: contract 타입 유효성
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TO-03: contract 타입 — 기간 유효성', () {
    test('SCENARIO-TO-03-001: periodType=null → 차단', () {
      final err = _validateContractPeriod(
        periodType: null, rangeStart: null, rangeEnd: null,
      );
      expect(err, '계약 기간을 선택해주세요');
    });

    test('SCENARIO-TO-03-002: custom + rangeStart만 있음 → 차단', () {
      final err = _validateContractPeriod(
        periodType: 'custom',
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: null,
      );
      expect(err, '계약 시작일과 종료일을 설정해주세요');
    });

    test('SCENARIO-TO-03-003: custom + rangeEnd만 있음 → 차단', () {
      final err = _validateContractPeriod(
        periodType: 'custom',
        rangeStart: null,
        rangeEnd: DateTime(2026, 12, 31),
      );
      expect(err, '계약 시작일과 종료일을 설정해주세요');
    });

    test('SCENARIO-TO-03-004: custom + rangeEnd < rangeStart → 차단', () {
      final err = _validateContractPeriod(
        periodType: 'custom',
        rangeStart: DateTime(2026, 12, 1),
        rangeEnd: DateTime(2026, 8, 1),
      );
      expect(err, '계약 시작일이 종료일보다 이후일 수 없습니다');
    });

    test('SCENARIO-TO-03-005: custom + rangeStart == rangeEnd → 통과 (당일 계약 허용)', () {
      final date = DateTime(2026, 8, 1);
      final err = _validateContractPeriod(
        periodType: 'custom',
        rangeStart: date,
        rangeEnd: date,
      );
      expect(err, isNull);
    });

    test('SCENARIO-TO-03-006: custom + 정상 기간 → 통과', () {
      final err = _validateContractPeriod(
        periodType: 'custom',
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: DateTime(2026, 12, 31),
      );
      expect(err, isNull);
    });

    test('SCENARIO-TO-03-007: preset(1month) + rangeStart/rangeEnd 없어도 통과', () {
      // preset 타입은 rangeStart/rangeEnd 없이 종료일 자동 계산
      final err = _validateContractPeriod(
        periodType: '1month',
        rangeStart: null,
        rangeEnd: null,
      );
      expect(err, isNull);
    });

    test('SCENARIO-TO-03-008: preset(3months) → 통과', () {
      final err = _validateContractPeriod(
        periodType: '3months',
        rangeStart: null,
        rangeEnd: null,
      );
      expect(err, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 4: 계약기간 종료일 계산
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TO-04: 계약기간 종료일 계산', () {
    test('SCENARIO-TO-04-001: 15days — 시작일 +14일', () {
      final start = DateTime(2026, 8, 1);
      final end = _computeContractEndDate('15days', start);
      expect(end, DateTime(2026, 8, 15));
    });

    test('SCENARIO-TO-04-002: 1month — 시작일 기준 1개월 뒤 말일 (월말 오버플로우 없음)', () {
      final start = DateTime(2026, 1, 31);
      final end = _computeContractEndDate('1month', start);
      // 1월31일 +1개월 → 2월 말일 = 2026-02-28
      expect(end, DateTime(2026, 2, 28));
    });

    test('SCENARIO-TO-04-003: 1month — 공식: startMonth+N 달의 말일 (March → April 30)', () {
      final start = DateTime(2026, 3, 1);
      final end = _computeContractEndDate('1month', start);
      // 공식: DateTime(y, startMonth+2, 1) - 1day = last day of (startMonth+1)
      // 3월(month=3) → DateTime(2026, 5, 1) - 1 = 2026-04-30 (4월 말일)
      expect(end, DateTime(2026, 4, 30));
    });

    test('SCENARIO-TO-04-004: 3months — 3개월 뒤 말일', () {
      final start = DateTime(2026, 1, 1);
      final end = _computeContractEndDate('3months', start);
      // 1월1일 +3개월 → 4월 말일 = 2026-04-30
      expect(end, DateTime(2026, 4, 30));
    });

    test('SCENARIO-TO-04-005: 6months — 6개월 뒤 말일', () {
      final start = DateTime(2026, 1, 1);
      final end = _computeContractEndDate('6months', start);
      // 1월1일 +6개월 → 7월 말일 = 2026-07-31
      expect(end, DateTime(2026, 7, 31));
    });

    test('SCENARIO-TO-04-006: 1year — 1년 뒤 같은 달 말일', () {
      final start = DateTime(2026, 3, 1);
      final end = _computeContractEndDate('1year', start);
      // 2026-03-01 +1year → 2027년 3월 말일 = 2027-03-31
      expect(end, DateTime(2027, 3, 31));
    });

    test('SCENARIO-TO-04-007: 1year — 연말 경계 처리', () {
      final start = DateTime(2026, 12, 1);
      final end = _computeContractEndDate('1year', start);
      // 2026-12-01 +1year → 2027년 12월 말일 = 2027-12-31
      expect(end, DateTime(2027, 12, 31));
    });

    test('SCENARIO-TO-04-008: 15days — 월말 경계 처리 (8월 31일 → 9월 14일)', () {
      final start = DateTime(2026, 8, 31);
      final end = _computeContractEndDate('15days', start);
      expect(end, DateTime(2026, 9, 14));
    });

    test('SCENARIO-TO-04-009: 알 수 없는 타입 → ArgumentError 발생', () {
      expect(
        () => _computeContractEndDate('unknown', DateTime(2026, 1, 1)),
        throwsArgumentError,
      );
    });

    test('SCENARIO-TO-04-010: 6months — 윤년 경계 (2024-08-01 → 2025-02-28)', () {
      final start = DateTime(2024, 8, 1);
      final end = _computeContractEndDate('6months', start);
      // 8월1일 +6개월 → 2025년 2월 말일 = 2025-02-28
      expect(end, DateTime(2025, 2, 28));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 5: 업무상세 유효성 (_createTO 내 검사 로직)
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TO-05: 업무상세 유효성', () {
    final _validDetail = _WorkDetailInput(
      workType: '피킹',
      wage: 12000,
      requiredCount: 3,
      startTime: '09:00',
      endTime: '18:00',
    );

    test('SCENARIO-TO-05-001: 업무목록 없음 → 차단', () {
      final err = _validateWorkDetails([]);
      expect(err, '최소 1개의 업무를 추가해주세요');
    });

    test('SCENARIO-TO-05-002: 미완성 업무(workType=null) → 차단', () {
      final detail = _WorkDetailInput(
        workType: null,
        wage: 12000,
        requiredCount: 3,
        startTime: '09:00',
        endTime: '18:00',
      );
      final err = _validateWorkDetails([detail]);
      expect(err, '모든 업무 정보를 입력해주세요');
    });

    test('SCENARIO-TO-05-003: 미완성 업무(wage=null) → 차단', () {
      final detail = _WorkDetailInput(
        workType: '패킹',
        wage: null,
        requiredCount: 3,
        startTime: '09:00',
        endTime: '18:00',
      );
      final err = _validateWorkDetails([detail]);
      expect(err, '모든 업무 정보를 입력해주세요');
    });

    test('SCENARIO-TO-05-004: 미완성 업무(startTime=null) → 차단', () {
      final detail = _WorkDetailInput(
        workType: '패킹',
        wage: 12000,
        requiredCount: 3,
        startTime: null,
        endTime: '18:00',
      );
      final err = _validateWorkDetails([detail]);
      expect(err, '모든 업무 정보를 입력해주세요');
    });

    test('SCENARIO-TO-05-005: 급여 0 → 차단', () {
      final detail = _WorkDetailInput(
        workType: '청소',
        wage: 0,
        requiredCount: 2,
        startTime: '08:00',
        endTime: '17:00',
      );
      final err = _validateWorkDetails([detail]);
      expect(err, '급여는 0원보다 커야 합니다');
    });

    test('SCENARIO-TO-05-006: 급여 음수 → 차단', () {
      final detail = _WorkDetailInput(
        workType: '청소',
        wage: -1000,
        requiredCount: 2,
        startTime: '08:00',
        endTime: '17:00',
      );
      final err = _validateWorkDetails([detail]);
      expect(err, '급여는 0원보다 커야 합니다');
    });

    test('SCENARIO-TO-05-007: 급여 5,000만원 초과 → 차단', () {
      final detail = _WorkDetailInput(
        workType: '관리직',
        wage: 50000001,
        requiredCount: 1,
        startTime: '09:00',
        endTime: '18:00',
      );
      final err = _validateWorkDetails([detail]);
      expect(err, '급여는 5,000만원 이하여야 합니다');
    });

    test('SCENARIO-TO-05-008: 급여 정확히 5,000만원 → 통과', () {
      final detail = _WorkDetailInput(
        workType: '관리직',
        wage: 50000000,
        requiredCount: 1,
        startTime: '09:00',
        endTime: '18:00',
      );
      final err = _validateWorkDetails([detail]);
      expect(err, isNull);
    });

    test('SCENARIO-TO-05-009: 필요 인원 0 → 차단', () {
      final detail = _WorkDetailInput(
        workType: '피킹',
        wage: 12000,
        requiredCount: 0,
        startTime: '09:00',
        endTime: '18:00',
      );
      final err = _validateWorkDetails([detail]);
      expect(err, '필요 인원은 1명 이상이어야 합니다');
    });

    test('SCENARIO-TO-05-010: 필요 인원 음수 → 차단', () {
      final detail = _WorkDetailInput(
        workType: '피킹',
        wage: 12000,
        requiredCount: -1,
        startTime: '09:00',
        endTime: '18:00',
      );
      final err = _validateWorkDetails([detail]);
      expect(err, '필요 인원은 1명 이상이어야 합니다');
    });

    test('SCENARIO-TO-05-011: 필요 인원 10,000명 초과 → 차단', () {
      final detail = _WorkDetailInput(
        workType: '피킹',
        wage: 12000,
        requiredCount: 10001,
        startTime: '09:00',
        endTime: '18:00',
      );
      final err = _validateWorkDetails([detail]);
      expect(err, '필요 인원은 10,000명 이하여야 합니다');
    });

    test('SCENARIO-TO-05-012: 필요 인원 정확히 10,000명 → 통과', () {
      final detail = _WorkDetailInput(
        workType: '피킹',
        wage: 12000,
        requiredCount: 10000,
        startTime: '09:00',
        endTime: '18:00',
      );
      final err = _validateWorkDetails([detail]);
      expect(err, isNull);
    });

    test('SCENARIO-TO-05-013: 정상 업무 1개 → 통과', () {
      final err = _validateWorkDetails([_validDetail]);
      expect(err, isNull);
    });

    test('SCENARIO-TO-05-014: 정상 업무 여러 개 → 통과', () {
      final details = [
        _validDetail,
        _WorkDetailInput(
          workType: '패킹',
          wage: 13000,
          requiredCount: 5,
          startTime: '14:00',
          endTime: '22:00',
        ),
      ];
      final err = _validateWorkDetails(details);
      expect(err, isNull);
    });

    test('SCENARIO-TO-05-015: 유효한 것과 무효한 업무 혼재 → 차단 (무효 우선)', () {
      final invalid = _WorkDetailInput(
        workType: '',
        wage: 12000,
        requiredCount: 1,
        startTime: '09:00',
        endTime: '18:00',
      );
      final err = _validateWorkDetails([_validDetail, invalid]);
      // workType이 빈 문자열 → isValid=false
      expect(err, isNotNull);
    });

    test('SCENARIO-TO-05-016: 급여 검사 순서 — 유효성 체크보다 나중에 실행됨', () {
      // 미완성 업무가 있으면 급여 체크보다 먼저 에러 반환
      final incomplete = _WorkDetailInput(
        workType: null, // isValid=false
        wage: 0,        // 급여도 0이지만 isValid 먼저 걸림
        requiredCount: 1,
        startTime: '09:00',
        endTime: '18:00',
      );
      final err = _validateWorkDetails([incomplete]);
      expect(err, '모든 업무 정보를 입력해주세요');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 6: 사업주 날인 체크
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TO-06: 사업주 날인(sealBase64) 체크', () {
    test('SCENARIO-TO-06-001: sealBase64=null → 차단', () {
      expect(_validateSeal(null), '사업주 날인 미등록');
    });

    test('SCENARIO-TO-06-002: sealBase64=빈문자열 → 차단', () {
      expect(_validateSeal(''), '사업주 날인 미등록');
    });

    test('SCENARIO-TO-06-003: sealBase64=유효한 Base64 문자열 → 통과', () {
      expect(_validateSeal('data:image/png;base64,iVBORw0KGgoAAAANSUhEUg=='), isNull);
    });

    test('SCENARIO-TO-06-004: sealBase64=공백만 있는 문자열 → 통과 (서버 검증 위임)', () {
      // 클라이언트 체크는 null/empty만; 공백은 서버에서 처리
      expect(_validateSeal('   '), isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 7: publishMode 분기
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TO-07: publishMode 분기', () {
    test('SCENARIO-TO-07-001: immediate → 슬롯에 visibleFrom 없음(즉시 공개)', () {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final slots = _buildFlexSlots(
        toId: 'to-001',
        dates: [tomorrow],
        publishMode: 'immediate',
      );
      expect(slots.length, 1);
      expect(slots.first.visibleFrom, isNull);
    });

    test('SCENARIO-TO-07-002: scheduled → 슬롯에 visibleFrom 설정됨', () {
      final farFuture = DateTime.now().add(const Duration(days: 30));
      final slots = _buildFlexSlots(
        toId: 'to-002',
        dates: [farFuture],
        publishMode: 'scheduled',
        publishDaysBefore: 3,
        publishTime: '14:00',
        now: DateTime(2026, 7, 1),
      );
      expect(slots.length, 1);
      expect(slots.first.visibleFrom, isNotNull);
    });

    test('SCENARIO-TO-07-003: scheduled + visibleFrom이 과거 → null(즉시공개) 처리', () {
      // 슬롯 날짜 - publishDaysBefore가 이미 과거인 경우
      final tomorrow = DateTime(2026, 7, 9);       // 슬롯 날짜
      final now      = DateTime(2026, 7, 8, 15, 0); // 현재 시각
      final visibleFrom = _computeSlotVisibleFrom(
        slotDate: tomorrow,
        publishDaysBefore: 2, // tomorrow - 2일 = 2026-07-07 → 과거
        publishTime: '14:00',
        now: now,
      );
      expect(visibleFrom, isNull); // 과거 → 즉시공개
    });

    test('SCENARIO-TO-07-004: scheduled + visibleFrom이 미래 → 해당 시각 반환', () {
      final slotDate = DateTime(2026, 7, 20);
      final now      = DateTime(2026, 7, 8, 10, 0);
      final visibleFrom = _computeSlotVisibleFrom(
        slotDate: slotDate,
        publishDaysBefore: 3,
        publishTime: '14:00',
        now: now,
      );
      // 2026-07-17 14:00
      expect(visibleFrom, DateTime(2026, 7, 17, 14, 0));
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 8: visibleFrom 계산 (flex scheduled)
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TO-08: visibleFrom 계산 — flex scheduled', () {
    test('SCENARIO-TO-08-001: publishDaysBefore=1, publishTime=14:00 → 슬롯날짜 전날 14시', () {
      final slotDate = DateTime(2026, 8, 10);
      final now      = DateTime(2026, 8, 1);
      final result = _computeSlotVisibleFrom(
        slotDate: slotDate,
        publishDaysBefore: 1,
        publishTime: '14:00',
        now: now,
      );
      expect(result, DateTime(2026, 8, 9, 14, 0));
    });

    test('SCENARIO-TO-08-002: publishDaysBefore=3, publishTime=09:00 → 슬롯날짜 3일 전 9시', () {
      final slotDate = DateTime(2026, 8, 10);
      final now      = DateTime(2026, 8, 1);
      final result = _computeSlotVisibleFrom(
        slotDate: slotDate,
        publishDaysBefore: 3,
        publishTime: '09:00',
        now: now,
      );
      expect(result, DateTime(2026, 8, 7, 9, 0));
    });

    test('SCENARIO-TO-08-003: publishDaysBefore=7, publishTime=00:00 → 슬롯날짜 7일 전 자정', () {
      final slotDate = DateTime(2026, 8, 10);
      final now      = DateTime(2026, 8, 1);
      final result = _computeSlotVisibleFrom(
        slotDate: slotDate,
        publishDaysBefore: 7,
        publishTime: '00:00',
        now: now,
      );
      expect(result, DateTime(2026, 8, 3, 0, 0));
    });

    test('SCENARIO-TO-08-004: visibleFrom = 현재 시각과 동일 → 미래로 간주 (isNull 아님)', () {
      final now = DateTime(2026, 8, 7, 14, 0);
      final slotDate = DateTime(2026, 8, 8);
      // 2026-08-08 - 1day = 2026-08-07 14:00 == now → isBefore(now) = false
      final result = _computeSlotVisibleFrom(
        slotDate: slotDate,
        publishDaysBefore: 1,
        publishTime: '14:00',
        now: now,
      );
      // now.isBefore(now) == false → 즉시공개 아님, visibleFrom 반환
      expect(result, DateTime(2026, 8, 7, 14, 0));
    });

    test('SCENARIO-TO-08-005: 날짜 2개, 첫째는 미래/둘째는 과거 → 개별 처리', () {
      final now = DateTime(2026, 8, 5, 12, 0);
      final slots = _buildFlexSlots(
        toId: 'to-multi',
        dates: [
          DateTime(2026, 8, 20), // 미래 슬롯
          DateTime(2026, 8, 6),  // 바로 내일
        ],
        publishMode: 'scheduled',
        publishDaysBefore: 3,
        publishTime: '14:00',
        now: now,
      );
      // 첫째: 2026-08-17 14:00 → 미래 → visibleFrom 있음
      // 둘째: 2026-08-03 14:00 → 과거 → visibleFrom null
      expect(slots[0].visibleFrom, isNotNull);
      expect(slots[1].visibleFrom, isNull);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 9: SlotModel 자동 생성 (flex)
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TO-09: SlotModel 자동 생성 — flex', () {
    test('SCENARIO-TO-09-001: 날짜 1개 → 슬롯 1개 생성', () {
      final date = DateTime(2026, 8, 10);
      final slots = _buildFlexSlots(
        toId: 'to-001',
        dates: [date],
        publishMode: 'immediate',
        now: DateTime(2026, 8, 1),
      );
      expect(slots.length, 1);
    });

    test('SCENARIO-TO-09-002: 날짜 2개 → 슬롯 2개 생성', () {
      final date1 = DateTime(2026, 8, 10);
      final date2 = DateTime(2026, 8, 11);
      final slots = _buildFlexSlots(
        toId: 'to-001',
        dates: [date1, date2],
        publishMode: 'immediate',
        now: DateTime(2026, 8, 1),
      );
      expect(slots.length, 2);
    });

    test('SCENARIO-TO-09-003: 날짜 5개 → 슬롯 5개 생성', () {
      final base = DateTime(2026, 8, 10);
      final dates = List.generate(5, (i) => base.add(Duration(days: i)));
      final slots = _buildFlexSlots(
        toId: 'to-001',
        dates: dates,
        publishMode: 'immediate',
        now: DateTime(2026, 8, 1),
      );
      expect(slots.length, 5);
    });

    test('SCENARIO-TO-09-004: 각 슬롯 초기 status=open', () {
      final date = DateTime(2026, 8, 10);
      final slots = _buildFlexSlots(
        toId: 'to-001',
        dates: [date],
        publishMode: 'immediate',
        now: DateTime(2026, 8, 1),
      );
      expect(slots.first.status, 'open');
    });

    test('SCENARIO-TO-09-005: 각 슬롯 초기 isManualClosed=false', () {
      final date = DateTime(2026, 8, 10);
      final slots = _buildFlexSlots(
        toId: 'to-001',
        dates: [date],
        publishMode: 'immediate',
        now: DateTime(2026, 8, 1),
      );
      expect(slots.first.isManualClosed, isFalse);
    });

    test('SCENARIO-TO-09-006: immediate 모드 — visibleFrom=null (즉시 공개)', () {
      final date = DateTime(2026, 8, 10);
      final slots = _buildFlexSlots(
        toId: 'to-001',
        dates: [date],
        publishMode: 'immediate',
        now: DateTime(2026, 8, 1),
      );
      expect(slots.first.visibleFrom, isNull);
    });

    test('SCENARIO-TO-09-007: scheduled 모드 — visibleFrom이 올바른 날짜로 설정됨', () {
      final date = DateTime(2026, 8, 20);
      final now  = DateTime(2026, 8, 1);
      final slots = _buildFlexSlots(
        toId: 'to-001',
        dates: [date],
        publishMode: 'scheduled',
        publishDaysBefore: 3,
        publishTime: '14:00',
        now: now,
      );
      // 2026-08-17 14:00
      expect(slots.first.visibleFrom, DateTime(2026, 8, 17, 14, 0));
    });

    test('SCENARIO-TO-09-008: 슬롯 ID 형식 — 날짜 기반 고유 ID', () {
      final date = DateTime(2026, 8, 10);
      final slots = _buildFlexSlots(
        toId: 'to-001',
        dates: [date],
        publishMode: 'immediate',
        now: DateTime(2026, 8, 1),
      );
      expect(slots.first.id, contains('2026-08-10'));
    });

    test('SCENARIO-TO-09-009: 날짜 순서 보존 (생성 순서 = 입력 순서)', () {
      final date1 = DateTime(2026, 8, 10);
      final date2 = DateTime(2026, 8, 15);
      final slots = _buildFlexSlots(
        toId: 'to-001',
        dates: [date1, date2],
        publishMode: 'immediate',
        now: DateTime(2026, 8, 1),
      );
      expect(slots[0].date, date1);
      expect(slots[1].date, date2);
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 10: TO 상태 흐름 (생성 → 마감 → 재오픈)
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TO-10: TO 상태 흐름', () {
    test('SCENARIO-TO-10-001: 생성 시 status=ACTIVE', () {
      // TO 생성 초기 상태
      const status = _TOStatus.active;
      expect(status, 'ACTIVE');
    });

    test('SCENARIO-TO-10-002: 마감 처리 → status=CLOSED, isManualClosed=true, closedAt 설정', () {
      final closedAt = DateTime(2026, 8, 10, 12, 0);
      final result = _closeTO(
        currentStatus: _TOStatus.active,
        closedBy: 'admin-uid-001',
        closedAt: closedAt,
      );
      expect(result['status'], _TOStatus.closed);
      expect(result['isManualClosed'], isTrue);
      expect(result['closedAt'], closedAt);
      expect(result['closedBy'], 'admin-uid-001');
    });

    test('SCENARIO-TO-10-003: 재오픈 처리 → status=ACTIVE, isManualClosed=false, reopenedAt 설정', () {
      final reopenedAt = DateTime(2026, 8, 11, 9, 0);
      final result = _reopenTO(
        reopenedBy: 'admin-uid-001',
        reopenedAt: reopenedAt,
      );
      expect(result['status'], _TOStatus.active);
      expect(result['isManualClosed'], isFalse);
      expect(result['reopenedAt'], reopenedAt);
      expect(result['reopenedBy'], 'admin-uid-001');
    });

    test('SCENARIO-TO-10-004: 마감 후 재오픈 → 최종 status=ACTIVE', () {
      final closedAt   = DateTime(2026, 8, 10, 12, 0);
      final reopenedAt = DateTime(2026, 8, 11, 9, 0);

      final closed  = _closeTO(currentStatus: _TOStatus.active, closedBy: 'admin', closedAt: closedAt);
      expect(closed['status'], _TOStatus.closed);

      final reopened = _reopenTO(reopenedBy: 'admin', reopenedAt: reopenedAt);
      expect(reopened['status'], _TOStatus.active);
      expect(reopened['isManualClosed'], isFalse);
    });

    test('SCENARIO-TO-10-005: 마감 시 closedBy에 관리자 UID 기록됨', () {
      final result = _closeTO(
        currentStatus: _TOStatus.active,
        closedBy: 'uid-super-admin',
        closedAt: DateTime.now(),
      );
      expect(result['closedBy'], 'uid-super-admin');
    });

    test('SCENARIO-TO-10-006: 재오픈 시 reopenedBy에 관리자 UID 기록됨', () {
      final result = _reopenTO(
        reopenedBy: 'uid-manager-001',
        reopenedAt: DateTime.now(),
      );
      expect(result['reopenedBy'], 'uid-manager-001');
    });
  });

  // ──────────────────────────────────────────────────────────────────────────
  // GROUP 11: 복합 시나리오 (전체 생성 흐름 통합 검증)
  // ──────────────────────────────────────────────────────────────────────────
  group('SCENARIO-TO-11: 복합 시나리오 — 전체 생성 흐름', () {
    test('SCENARIO-TO-11-001: 사전조건 충족 → flex 날짜 선택 → 업무상세 유효 → 날인 있음 → 생성 가능', () {
      final pre = _Prerequisites(
        businessApproved: true,
        workTypesReady: true,
        contractTemplatesReady: true,
      );
      expect(pre.allMet, isTrue);

      final datesErr = _validateFlexDates([DateTime.now().add(const Duration(days: 1))]);
      expect(datesErr, isNull);

      final workErr = _validateWorkDetails([
        _WorkDetailInput(
          workType: '피킹',
          wage: 12000,
          requiredCount: 3,
          startTime: '09:00',
          endTime: '18:00',
        ),
      ]);
      expect(workErr, isNull);

      expect(_validateSeal('valid-base64-seal'), isNull);
    });

    test('SCENARIO-TO-11-002: 사전조건 미충족 → 폼 차단 (다른 검사 진행 불필요)', () {
      final pre = _Prerequisites(
        businessApproved: false,
        workTypesReady: true,
        contractTemplatesReady: true,
      );
      expect(pre.allMet, isFalse);
      // 이 단계에서 폼 자체가 잠기므로 날짜/업무/날인 체크는 도달 불가
    });

    test('SCENARIO-TO-11-003: contract 생성 — 1month 계약기간, 정상 업무, 날인 있음 → 생성 가능', () {
      final contractErr = _validateContractPeriod(
        periodType: '1month',
        rangeStart: DateTime(2026, 8, 1),
        rangeEnd: null,
      );
      expect(contractErr, isNull);

      final workErr = _validateWorkDetails([
        _WorkDetailInput(
          workType: '사무보조',
          wage: 2200000,
          requiredCount: 1,
          startTime: '09:00',
          endTime: '18:00',
          wageType: 'monthly',
        ),
      ]);
      expect(workErr, isNull);

      expect(_validateSeal('seal-base64-data'), isNull);
    });

    test('SCENARIO-TO-11-004: flex 5일 공고 생성 → 슬롯 5개 생성, 모두 status=open', () {
      final base = DateTime(2026, 8, 10);
      final dates = List.generate(5, (i) => base.add(Duration(days: i)));
      final slots = _buildFlexSlots(
        toId: 'to-flex-5days',
        dates: dates,
        publishMode: 'immediate',
        now: DateTime(2026, 8, 1),
      );
      expect(slots.length, 5);
      expect(slots.every((s) => s.status == 'open'), isTrue);
      expect(slots.every((s) => !s.isManualClosed), isTrue);
    });

    test('SCENARIO-TO-11-005: contract custom — rangeEnd < rangeStart → 전체 생성 차단', () {
      final contractErr = _validateContractPeriod(
        periodType: 'custom',
        rangeStart: DateTime(2026, 12, 1),
        rangeEnd: DateTime(2026, 8, 1),
      );
      // 업무상세·날인 체크 이전에 차단됨
      expect(contractErr, isNotNull);
      expect(contractErr, contains('이후일 수 없습니다'));
    });

    test('SCENARIO-TO-11-006: 날인 없음 → 업무상세 유효해도 최종 차단', () {
      // 업무상세는 통과
      final workErr = _validateWorkDetails([
        _WorkDetailInput(
          workType: '피킹',
          wage: 12000,
          requiredCount: 3,
          startTime: '09:00',
          endTime: '18:00',
        ),
      ]);
      expect(workErr, isNull);

      // 날인 없음 → 차단
      final sealErr = _validateSeal(null);
      expect(sealErr, isNotNull);
    });

    test('SCENARIO-TO-11-007: flex scheduled — 날짜 3개 선택, publishDaysBefore=2 → 슬롯 3개, 각 visibleFrom 계산됨', () {
      final now = DateTime(2026, 7, 1);
      final dates = [
        DateTime(2026, 8, 10),
        DateTime(2026, 8, 15),
        DateTime(2026, 8, 20),
      ];
      final slots = _buildFlexSlots(
        toId: 'to-scheduled',
        dates: dates,
        publishMode: 'scheduled',
        publishDaysBefore: 2,
        publishTime: '10:00',
        now: now,
      );
      expect(slots.length, 3);
      // 각 슬롯의 visibleFrom = 날짜 - 2일 14시가 미래 → 설정됨
      expect(slots[0].visibleFrom, DateTime(2026, 8, 8, 10, 0));
      expect(slots[1].visibleFrom, DateTime(2026, 8, 13, 10, 0));
      expect(slots[2].visibleFrom, DateTime(2026, 8, 18, 10, 0));
    });

    test('SCENARIO-TO-11-008: 사전조건 3가지 중 2가지만 충족해도 여전히 폼 잠금 (AND 조건)', () {
      final cases = [
        _Prerequisites(businessApproved: true,  workTypesReady: true,  contractTemplatesReady: false),
        _Prerequisites(businessApproved: true,  workTypesReady: false, contractTemplatesReady: true),
        _Prerequisites(businessApproved: false, workTypesReady: true,  contractTemplatesReady: true),
      ];
      for (final pre in cases) {
        expect(pre.allMet, isFalse, reason: 'businessApproved=${pre.businessApproved}, '
            'workTypesReady=${pre.workTypesReady}, '
            'contractTemplatesReady=${pre.contractTemplatesReady}');
      }
    });
  });
}
