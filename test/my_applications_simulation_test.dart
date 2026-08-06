// ignore_for_file: lines_longer_than_80_chars
//
// 내 지원 내역 화면 — 로직 시뮬레이션 테스트
//
// 검증 대상:
//   A. 상태 필터 로직 (_filteredApplications 시뮬레이션)
//   B. 장기 공고 판별 (isLongTermApplication)
//   C. 자동 취소 사유 텍스트 분기 (_buildAutoCanceledInfo 로직)
//   D. D-day 배지 계산 (_buildDdayBadge 로직)
//   E. 리뷰 기간 윈도우 (_buildReviewSection 로직)
//   F. 퇴사/계약해지 배너 텍스트 (_buildLongTermStatusSection 로직)
//   G. isWorkingOnDate — 충돌 판단
//   H. hasTimeOverlap — 시간대 겹침 (야간 교대 포함)
//   I. workPeriodDisplay — 기간 표시
//   J. isScheduledOnDate — 캘린더 표시
//   K. isTerminationApproved — 퇴사·해지 완료 판별

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/application_model.dart';

// ════════════════════════════════════════════════════════════
// 팩토리 헬퍼
// ════════════════════════════════════════════════════════════

ApplicationModel _app({
  String id = 'app1',
  String status = AppStatus.pending,
  String? applicationType,
  DateTime? workDate,
  DateTime? workEndDate,
  List<String>? workDays,
  DateTime? desiredStartDate,
  DateTime? confirmedAt,
  DateTime? actualResignDate,
  DateTime? resignRequestDate,
  String? resignStatus,
  String? resignRejectReason,
  String? terminationStatus,
  String? terminationReason,
  DateTime? terminationEffectiveDate,
  String? terminationRejectReason,
  String? cancelReason,
  String? conflictingBusiness,
  String? conflictingTime,
  List<DateTime>? leaveDates,
  List<DateTime>? extraWorkDates,
  String startTime = '09:00',
  String endTime = '18:00',
  int wage = 100000,
}) {
  final now = DateTime.now();
  return ApplicationModel(
    id: id,
    businessId: 'biz1',
    businessName: '테스트 사업장',
    toTitle: 'test1',
    workDate: workDate ?? DateTime(now.year, now.month, now.day + 1),
    workEndDate: workEndDate,
    workDays: workDays,
    desiredStartDate: desiredStartDate,
    confirmedAt: confirmedAt,
    actualResignDate: actualResignDate,
    resignRequestDate: resignRequestDate,
    resignStatus: resignStatus,
    resignRejectReason: resignRejectReason,
    terminationStatus: terminationStatus,
    terminationReason: terminationReason,
    terminationEffectiveDate: terminationEffectiveDate,
    terminationRejectReason: terminationRejectReason,
    startTime: startTime,
    endTime: endTime,
    uid: 'uid1',
    selectedWorkType: '사무업무',
    wage: wage,
    status: status,
    appliedAt: DateTime.now().subtract(const Duration(hours: 1)),
    applicationType: applicationType,
    cancelReason: cancelReason,
    conflictingBusiness: conflictingBusiness,
    conflictingTime: conflictingTime,
    leaveDates: leaveDates,
    extraWorkDates: extraWorkDates,
  );
}

// ── 화면 내 필터 로직 시뮬레이션 ─────────────────────────────
List<ApplicationModel> _filterApplications(
  List<ApplicationModel> apps,
  String selectedFilter,
) {
  if (selectedFilter == 'ALL') return apps;
  return apps.where((app) {
    final status = app.status;
    if (selectedFilter == AppStatus.canceled) {
      return AppStatus.inactiveStates.contains(status) && status != AppStatus.rejected;
    }
    if (selectedFilter == AppStatus.confirmed) return status == AppStatus.confirmed;
    if (selectedFilter == AppStatus.contractPending) return status == AppStatus.contractPending;
    return status == selectedFilter;
  }).toList();
}

// ── 화면 내 자동취소 사유 텍스트 시뮬레이션 ─────────────────
String _autoCanceledReasonText(ApplicationModel app) {
  final bool hasConflict = app.conflictingBusiness != null;
  return switch (app.cancelReason) {
    'SLOT_WORK_DETAIL_EXPIRED' => '슬롯 업무 마감으로 자동 취소됨',
    'WORK_DETAIL_EXPIRED'      => '업무 마감으로 자동 취소됨',
    'TO_EXPIRED'               => '공고 마감으로 자동 취소됨',
    _                          => hasConflict ? '시간 충돌로 자동 취소됨' : '자동으로 취소되었습니다',
  };
}

// ── 화면 내 D-day 배지 레이블 시뮬레이션 ─────────────────────
String _ddayLabel(DateTime endDate) {
  final today = DateTime.now();
  final end = DateTime(endDate.year, endDate.month, endDate.day);
  final todayOnly = DateTime(today.year, today.month, today.day);
  final remaining = end.difference(todayOnly).inDays;
  if (remaining < 0)  return '만료';
  if (remaining == 0) return 'D-Day';
  return 'D-$remaining';
}

// ── 화면 내 리뷰 기간 윈도우 시뮬레이션 ──────────────────────
DateTime? _reviewDate(ApplicationModel app) {
  if (app.isLongTermApplication) {
    return app.actualResignDate ?? app.workEndDate;
  }
  return app.workDate;
}

bool _withinReviewWindow(DateTime rd) {
  final monthEnd = DateTime(rd.year, rd.month + 1, 0);
  return DateTime.now().isBefore(monthEnd.add(const Duration(days: 15)));
}

bool _canWriteReview(ApplicationModel app) {
  if (app.status != AppStatus.confirmed) return false;
  final rd = _reviewDate(app);
  if (rd == null) return false;
  if (rd.isAfter(DateTime.now())) return false;
  return _withinReviewWindow(rd);
}

// ── 화면 내 퇴사 배너 텍스트 시뮬레이션 ──────────────────────
String _resignBannerLabel(ApplicationModel app) {
  final rs = app.resignStatus!;
  return switch (rs) {
    'PENDING' => app.resignRequestDate != null
        ? '퇴사 신청 중 · 희망일 ${_mmdd(app.resignRequestDate!)}'
        : '퇴사 신청 중',
    'APPROVED' || 'AUTO_APPROVED' => app.actualResignDate != null
        ? '퇴사 확정 · ${_mmdd(app.actualResignDate!)}'
        : '퇴사 확정',
    'REJECTED' => app.resignRejectReason?.isNotEmpty == true
        ? '퇴사 신청 거절 · ${app.resignRejectReason}'
        : '퇴사 신청이 거절되었습니다',
    _ => '퇴사 신청 처리 중',
  };
}

String _terminationBannerLabel(ApplicationModel app) {
  final ts = app.terminationStatus!;
  return switch (ts) {
    'PENDING' => app.terminationReason?.isNotEmpty == true
        ? '계약해지 요청 수신 · ${app.terminationReason}'
        : '계약해지 요청이 접수되었습니다',
    'APPROVED' || 'AUTO_APPROVED' => app.terminationEffectiveDate != null
        ? '계약해지 완료 · ${_mmdd(app.terminationEffectiveDate!)}'
        : '계약해지 완료',
    'REJECTED' => app.terminationRejectReason?.isNotEmpty == true
        ? '계약해지 거절 · ${app.terminationRejectReason}'
        : '계약해지 거절 처리됨',
    _ => '계약해지 처리 중',
  };
}

// ── 확정 취소 힌트 (단기·확정·오늘 이상) 텍스트 ──────────────
String _confirmedCancelHintText(ApplicationModel app) {
  final workDate = app.workDate;
  final now = DateTime.now();
  final isToday = workDate.year == now.year &&
      workDate.month == now.month &&
      workDate.day == now.day;
  return isToday
      ? '오늘 근무 취소는 노쇼 1회 패널티가 부과됩니다. 취소가 필요하다면 공고 상세를 탭해주세요.'
      : '취소가 필요하다면 이 카드를 탭해 공고 상세에서 확정 취소를 선택하세요.';
}

// ── 확정 취소 힌트 표시 조건 ──────────────────────────────────
bool _showConfirmedCancelHint(ApplicationModel app) {
  if (app.status != AppStatus.confirmed) return false;
  if (app.isLongTermApplication) return false;
  final today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
  return !app.workDate.isBefore(today);
}

String _mmdd(DateTime d) =>
    '${d.month.toString().padLeft(2, '0')}.${d.day.toString().padLeft(2, '0')}';

// ════════════════════════════════════════════════════════════

void main() {
  final today = DateTime.now();
  final todayOnly = DateTime(today.year, today.month, today.day);
  final tomorrow = todayOnly.add(const Duration(days: 1));
  final yesterday = todayOnly.subtract(const Duration(days: 1));

  // ═══════════════════════════════════════════════════════
  // A. 상태 필터 로직
  // ═══════════════════════════════════════════════════════

  group('A. 상태 필터 로직', () {
    final apps = [
      _app(id: 'a1', status: AppStatus.pending),
      _app(id: 'a2', status: AppStatus.confirmed),
      _app(id: 'a3', status: AppStatus.contractPending),
      _app(id: 'a4', status: AppStatus.rejected),
      _app(id: 'a5', status: AppStatus.canceled),
      _app(id: 'a6', status: AppStatus.autoCanceled),
    ];

    test('A-1: ALL 필터 — 모든 상태 포함', () {
      final filtered = _filterApplications(apps, 'ALL');
      expect(filtered.length, 6);
    });

    test('A-2: PENDING 필터 — PENDING만', () {
      final filtered = _filterApplications(apps, AppStatus.pending);
      expect(filtered.length, 1);
      expect(filtered.first.status, AppStatus.pending);
    });

    test('A-3: CONFIRMED 필터 — CONFIRMED만 (CONTRACT_PENDING 제외)', () {
      final filtered = _filterApplications(apps, AppStatus.confirmed);
      expect(filtered.length, 1);
      expect(filtered.first.status, AppStatus.confirmed);
    });

    test('A-4: CONTRACT_PENDING 필터 — CONTRACT_PENDING만', () {
      final filtered = _filterApplications(apps, AppStatus.contractPending);
      expect(filtered.length, 1);
      expect(filtered.first.status, AppStatus.contractPending);
    });

    test('A-5: REJECTED 필터 — REJECTED만', () {
      final filtered = _filterApplications(apps, AppStatus.rejected);
      expect(filtered.length, 1);
      expect(filtered.first.status, AppStatus.rejected);
    });

    test('A-6: 취소 필터 — CANCELED + AUTO_CANCELED 포함 (REJECTED 제외)', () {
      final filtered = _filterApplications(apps, AppStatus.canceled);
      expect(filtered.length, 2);
      expect(filtered.map((a) => a.status).toSet(),
          {AppStatus.canceled, AppStatus.autoCanceled});
    });

    test('A-7: 취소 필터 — REJECTED는 절대 포함되지 않음', () {
      final filtered = _filterApplications(apps, AppStatus.canceled);
      expect(filtered.any((a) => a.status == AppStatus.rejected), false);
    });

    test('A-8: 빈 목록 — 모든 필터 결과 빈 리스트', () {
      for (final f in ['ALL', AppStatus.pending, AppStatus.confirmed,
          AppStatus.contractPending, AppStatus.rejected, AppStatus.canceled]) {
        expect(_filterApplications([], f).isEmpty, true, reason: 'filter=$f');
      }
    });

    test('A-9: 취소 필터 — AUTO_CANCELED가 있으면 inactiveStates에 포함', () {
      expect(AppStatus.inactiveStates.contains(AppStatus.autoCanceled), true);
    });
  });

  // ═══════════════════════════════════════════════════════
  // B. 장기 공고 판별 (isLongTermApplication)
  // ═══════════════════════════════════════════════════════

  group('B. 장기 공고 판별 (isLongTermApplication)', () {
    test('B-1: applicationType=long_term → true', () {
      expect(_app(applicationType: 'long_term').isLongTermApplication, true);
    });

    test('B-2: applicationType=short → false (workDays 있어도 false)', () {
      expect(
        _app(applicationType: 'short', workDays: ['월', '화', '수']).isLongTermApplication,
        false,
      );
    });

    test('B-3: applicationType null + workDays 있음 → true', () {
      expect(
        _app(workDays: ['월', '화', '수', '목', '금']).isLongTermApplication,
        true,
      );
    });

    test('B-4: workEndDate == workDate (동일일) → false (단기 구 데이터)', () {
      final d = DateTime(2026, 7, 20);
      expect(_app(workDate: d, workEndDate: d).isLongTermApplication, false);
    });

    test('B-5: workEndDate != workDate (다른 날짜) → true (장기 구 데이터)', () {
      expect(
        _app(
          workDate: DateTime(2026, 7, 1),
          workEndDate: DateTime(2026, 7, 31),
        ).isLongTermApplication,
        true,
      );
    });

    test('B-6: workEndDate=null, workDays=null, applicationType=null → false', () {
      expect(_app().isLongTermApplication, false);
    });

    test('B-7: workDays 빈 리스트 → false', () {
      expect(_app(workDays: []).isLongTermApplication, false);
    });
  });

  // ═══════════════════════════════════════════════════════
  // C. 자동 취소 사유 텍스트 분기
  // ═══════════════════════════════════════════════════════

  group('C. 자동 취소 사유 텍스트 분기', () {
    test('C-1: SLOT_WORK_DETAIL_EXPIRED → 슬롯 업무 마감 문구', () {
      final app = _app(cancelReason: 'SLOT_WORK_DETAIL_EXPIRED');
      expect(_autoCanceledReasonText(app), '슬롯 업무 마감으로 자동 취소됨');
    });

    test('C-2: WORK_DETAIL_EXPIRED → 업무 마감 문구', () {
      final app = _app(cancelReason: 'WORK_DETAIL_EXPIRED');
      expect(_autoCanceledReasonText(app), '업무 마감으로 자동 취소됨');
    });

    test('C-3: TO_EXPIRED → 공고 마감 문구', () {
      final app = _app(cancelReason: 'TO_EXPIRED');
      expect(_autoCanceledReasonText(app), '공고 마감으로 자동 취소됨');
    });

    test('C-4: cancelReason null + conflictingBusiness 있음 → 시간 충돌 문구', () {
      final app = _app(
        conflictingBusiness: '다른 사업장',
        conflictingTime: '09:00~18:00',
      );
      expect(_autoCanceledReasonText(app), '시간 충돌로 자동 취소됨');
    });

    test('C-5: cancelReason null + conflictingBusiness null → 일반 자동취소 문구', () {
      final app = _app();
      expect(_autoCanceledReasonText(app), '자동으로 취소되었습니다');
    });

    test('C-6: cancelReason=SCHEDULE_CONFLICT(구 데이터) + conflictingBusiness null → 일반 문구', () {
      final app = _app(cancelReason: 'SCHEDULE_CONFLICT');
      expect(_autoCanceledReasonText(app), '자동으로 취소되었습니다');
    });

    test('C-7: cancelReason=SCHEDULE_CONFLICT + conflictingBusiness 있음 → 충돌 문구', () {
      final app = _app(
        cancelReason: 'SCHEDULE_CONFLICT',
        conflictingBusiness: 'ABC 회사',
      );
      expect(_autoCanceledReasonText(app), '시간 충돌로 자동 취소됨');
    });
  });

  // ═══════════════════════════════════════════════════════
  // D. D-day 배지 계산
  // ═══════════════════════════════════════════════════════

  group('D. D-day 배지 계산', () {
    test('D-1: 종료일이 어제 → 만료', () {
      expect(_ddayLabel(yesterday), '만료');
    });

    test('D-2: 종료일이 오늘 → D-Day', () {
      expect(_ddayLabel(todayOnly), 'D-Day');
    });

    test('D-3: 종료일 = 내일 → D-1', () {
      expect(_ddayLabel(todayOnly.add(const Duration(days: 1))), 'D-1');
    });

    test('D-4: 종료일 = D+7 → D-7 (경계값)', () {
      expect(_ddayLabel(todayOnly.add(const Duration(days: 7))), 'D-7');
    });

    test('D-5: 종료일 = D+8 → D-8', () {
      expect(_ddayLabel(todayOnly.add(const Duration(days: 8))), 'D-8');
    });

    test('D-6: 종료일 = D+14 → D-14 (경계값)', () {
      expect(_ddayLabel(todayOnly.add(const Duration(days: 14))), 'D-14');
    });

    test('D-7: 종료일 = D+15 → D-15', () {
      expect(_ddayLabel(todayOnly.add(const Duration(days: 15))), 'D-15');
    });

    test('D-8: 종료일 = D+30 → D-30 (초록 구간)', () {
      expect(_ddayLabel(todayOnly.add(const Duration(days: 30))), 'D-30');
    });
  });

  // ═══════════════════════════════════════════════════════
  // E. 리뷰 기간 윈도우
  // ═══════════════════════════════════════════════════════

  group('E. 리뷰 기간 윈도우', () {
    test('E-1: 단기 근무 — _reviewDate = workDate', () {
      final app = _app(workDate: yesterday);
      expect(_reviewDate(app), yesterday);
    });

    test('E-2: 장기 근무 — actualResignDate 있음 → _reviewDate = actualResignDate', () {
      final end = DateTime(2026, 6, 30);
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 6, 1),
        workEndDate: DateTime(2026, 6, 30),
        actualResignDate: end,
        status: AppStatus.confirmed,
      );
      expect(_reviewDate(app), end);
    });

    test('E-3: 장기 근무 — actualResignDate 없음 → _reviewDate = workEndDate', () {
      final end = DateTime(2026, 6, 30);
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 6, 1),
        workEndDate: end,
        status: AppStatus.confirmed,
      );
      expect(_reviewDate(app), end);
    });

    test('E-4: 장기 근무 — 둘 다 null → _reviewDate = null (재직 중, 리뷰 불가)', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 6, 1),
        status: AppStatus.confirmed,
      );
      expect(_reviewDate(app), null);
    });

    test('E-5: 단기 — 오늘 근무 → 리뷰 작성 가능', () {
      final app = _app(workDate: todayOnly, status: AppStatus.confirmed);
      expect(_canWriteReview(app), true);
    });

    test('E-6: 단기 — 내일 근무 → 리뷰 불가 (근무 미완료)', () {
      final app = _app(workDate: tomorrow, status: AppStatus.confirmed);
      expect(_canWriteReview(app), false);
    });

    test('E-7: 리뷰 기간 만료 — 2개월 전 근무 → 리뷰 불가', () {
      final twoMonthsAgo = DateTime(today.year, today.month - 2, 1);
      final app = _app(workDate: twoMonthsAgo, status: AppStatus.confirmed);
      // 근무월 말일 + 15일 이후라면 불가
      final rd = _reviewDate(app)!;
      final monthEnd = DateTime(rd.year, rd.month + 1, 0);
      final windowEnd = monthEnd.add(const Duration(days: 15));
      if (DateTime.now().isAfter(windowEnd)) {
        expect(_canWriteReview(app), false);
      }
      // 2개월 전이면 항상 기간 만료 (today.month - 2의 말일 + 15일이 지났음)
    });

    test('E-8: PENDING 상태 — 리뷰 불가', () {
      final app = _app(workDate: yesterday, status: AppStatus.pending);
      expect(_canWriteReview(app), false);
    });

    test('E-9: REJECTED 상태 — 리뷰 불가', () {
      final app = _app(workDate: yesterday, status: AppStatus.rejected);
      expect(_canWriteReview(app), false);
    });

    test('E-10: 장기 재직 중 — _reviewDate null → 리뷰 불가', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 1, 1),
        status: AppStatus.confirmed,
      );
      expect(_canWriteReview(app), false);
    });
  });

  // ═══════════════════════════════════════════════════════
  // F. 퇴사/계약해지 배너 텍스트
  // ═══════════════════════════════════════════════════════

  group('F. 퇴사/계약해지 배너 텍스트', () {
    // 퇴사
    test('F-1: resignStatus=PENDING, resignRequestDate 있음 → 희망일 포함 문구', () {
      final d = DateTime(2026, 8, 15);
      final app = _app(resignStatus: 'PENDING', resignRequestDate: d);
      expect(_resignBannerLabel(app), '퇴사 신청 중 · 희망일 08.15');
    });

    test('F-2: resignStatus=PENDING, resignRequestDate null → 기본 문구', () {
      final app = _app(resignStatus: 'PENDING');
      expect(_resignBannerLabel(app), '퇴사 신청 중');
    });

    test('F-3: resignStatus=APPROVED, actualResignDate 있음 → 퇴사 확정 + 날짜', () {
      final d = DateTime(2026, 8, 31);
      final app = _app(resignStatus: 'APPROVED', actualResignDate: d);
      expect(_resignBannerLabel(app), '퇴사 확정 · 08.31');
    });

    test('F-4: resignStatus=AUTO_APPROVED, actualResignDate 있음 → 퇴사 확정 + 날짜', () {
      final d = DateTime(2026, 9, 1);
      final app = _app(resignStatus: 'AUTO_APPROVED', actualResignDate: d);
      expect(_resignBannerLabel(app), '퇴사 확정 · 09.01');
    });

    test('F-5: resignStatus=APPROVED, actualResignDate null → 날짜 없이 퇴사 확정', () {
      final app = _app(resignStatus: 'APPROVED');
      expect(_resignBannerLabel(app), '퇴사 확정');
    });

    test('F-6: resignStatus=REJECTED, resignRejectReason 있음 → 거절 + 사유', () {
      final app = _app(
        resignStatus: 'REJECTED',
        resignRejectReason: '업무 인수인계 미완료',
      );
      expect(_resignBannerLabel(app), '퇴사 신청 거절 · 업무 인수인계 미완료');
    });

    test('F-7: resignStatus=REJECTED, resignRejectReason null → 기본 거절 문구', () {
      final app = _app(resignStatus: 'REJECTED', resignRejectReason: null);
      expect(_resignBannerLabel(app), '퇴사 신청이 거절되었습니다');
    });

    test('F-8: resignStatus=REJECTED, resignRejectReason 빈 문자열 → 기본 거절 문구', () {
      final app = _app(resignStatus: 'REJECTED', resignRejectReason: '');
      expect(_resignBannerLabel(app), '퇴사 신청이 거절되었습니다');
    });

    // 계약해지
    test('F-9: terminationStatus=PENDING, terminationReason 있음 → 해지 요청 수신 + 사유', () {
      final app = _app(
        terminationStatus: 'PENDING',
        terminationReason: '근태 불량',
      );
      expect(_terminationBannerLabel(app), '계약해지 요청 수신 · 근태 불량');
    });

    test('F-10: terminationStatus=PENDING, terminationReason null → 기본 접수 문구', () {
      final app = _app(terminationStatus: 'PENDING');
      expect(_terminationBannerLabel(app), '계약해지 요청이 접수되었습니다');
    });

    test('F-11: terminationStatus=APPROVED, terminationEffectiveDate 있음 → 해지 완료 + 날짜', () {
      final d = DateTime(2026, 8, 10);
      final app = _app(terminationStatus: 'APPROVED', terminationEffectiveDate: d);
      expect(_terminationBannerLabel(app), '계약해지 완료 · 08.10');
    });

    test('F-12: terminationStatus=AUTO_APPROVED → 해지 완료 처리', () {
      final d = DateTime(2026, 8, 20);
      final app = _app(terminationStatus: 'AUTO_APPROVED', terminationEffectiveDate: d);
      expect(_terminationBannerLabel(app), '계약해지 완료 · 08.20');
    });

    test('F-13: terminationStatus=REJECTED, terminationRejectReason 있음 → 거절 + 사유', () {
      final app = _app(
        terminationStatus: 'REJECTED',
        terminationRejectReason: '정당한 사유 없음',
      );
      expect(_terminationBannerLabel(app), '계약해지 거절 · 정당한 사유 없음');
    });

    test('F-14: terminationStatus=REJECTED, terminationRejectReason null → 기본 거절 문구', () {
      final app = _app(terminationStatus: 'REJECTED');
      expect(_terminationBannerLabel(app), '계약해지 거절 처리됨');
    });
  });

  // ═══════════════════════════════════════════════════════
  // G. isWorkingOnDate — 충돌 판단
  // ═══════════════════════════════════════════════════════

  group('G. isWorkingOnDate — 충돌 판단', () {
    final mon = DateTime(2026, 8, 3); // 월요일
    final tue = DateTime(2026, 8, 4); // 화요일
    final wed = DateTime(2026, 8, 5); // 수요일
    final sat = DateTime(2026, 8, 8); // 토요일

    test('G-1: 단기 — workDate에만 근무 중', () {
      final app = _app(workDate: mon);
      expect(app.isWorkingOnDate(mon), true);
      expect(app.isWorkingOnDate(tue), false);
    });

    test('G-2: 장기 — 범위 이전 날짜 → false', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 8, 1),
        workEndDate: DateTime(2026, 8, 31),
        workDays: ['월', '화', '수', '목', '금'],
      );
      expect(app.isWorkingOnDate(DateTime(2026, 7, 31)), false);
    });

    test('G-3: 장기 — 범위 이후 날짜 → false', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 8, 1),
        workEndDate: DateTime(2026, 8, 31),
        workDays: ['월', '화', '수', '목', '금'],
      );
      expect(app.isWorkingOnDate(DateTime(2026, 9, 1)), false);
    });

    test('G-4: 장기 — 범위 내 근무 요일 → true', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 8, 1),
        workEndDate: DateTime(2026, 8, 31),
        workDays: ['월', '화', '수', '목', '금'],
      );
      expect(app.isWorkingOnDate(mon), true); // 월
      expect(app.isWorkingOnDate(wed), true); // 수
    });

    test('G-5: 장기 — 범위 내 비근무 요일(토) → false', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 8, 1),
        workEndDate: DateTime(2026, 8, 31),
        workDays: ['월', '화', '수', '목', '금'],
      );
      expect(app.isWorkingOnDate(sat), false);
    });

    test('G-6: 장기 — 휴무일(leaveDates) → false (근무 요일이어도)', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 8, 1),
        workEndDate: DateTime(2026, 8, 31),
        workDays: ['월', '화', '수', '목', '금'],
        leaveDates: [mon], // 월요일 휴무
      );
      expect(app.isWorkingOnDate(mon), false);
      expect(app.isWorkingOnDate(tue), true);
    });

    test('G-7: 장기 — 추가 근무일(extraWorkDates) → true (비근무 요일이어도)', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 8, 1),
        workEndDate: DateTime(2026, 8, 31),
        workDays: ['월', '화', '수', '목', '금'],
        extraWorkDates: [sat], // 토요일 추가 근무
      );
      expect(app.isWorkingOnDate(sat), true);
    });

    test('G-8: 장기 — workEndDate=null → false', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 8, 1),
        workDays: ['월'],
      );
      expect(app.isWorkingOnDate(mon), false);
    });

    test('G-9: 장기 — actualResignDate 이후 → false', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 8, 1),
        workEndDate: DateTime(2026, 8, 31),
        actualResignDate: DateTime(2026, 8, 15), // 8/15 퇴사
        workDays: ['월', '화', '수', '목', '금'],
      );
      expect(app.isWorkingOnDate(DateTime(2026, 8, 17)), false); // 8/17은 퇴사 이후
      expect(app.isWorkingOnDate(DateTime(2026, 8, 14)), true);  // 8/14는 퇴사 이전 (금)
    });

    test('G-10: 장기 — desiredStartDate > workDate → desiredStartDate 이전 날짜 false', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 8, 1),
        desiredStartDate: DateTime(2026, 8, 10),
        workEndDate: DateTime(2026, 8, 31),
        workDays: ['월', '화', '수', '목', '금'],
      );
      expect(app.isWorkingOnDate(DateTime(2026, 8, 3)), false); // workDate 이후지만 desiredStartDate 이전
      expect(app.isWorkingOnDate(DateTime(2026, 8, 10)), true); // desiredStartDate 당일(월)
    });
  });

  // ═══════════════════════════════════════════════════════
  // H. hasTimeOverlap — 시간대 겹침
  // ═══════════════════════════════════════════════════════

  group('H. hasTimeOverlap — 시간대 겹침', () {
    test('H-1: 동일한 시간대 → true', () {
      expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '09:00', '18:00'), true);
    });

    test('H-2: 앞부분 겹침 — 09~18 vs 06~12', () {
      expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '06:00', '12:00'), true);
    });

    test('H-3: 뒷부분 겹침 — 09~18 vs 15~22', () {
      expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '15:00', '22:00'), true);
    });

    test('H-4: 완전 포함 — 09~18 vs 10~14', () {
      expect(ApplicationModel.hasTimeOverlap('09:00', '18:00', '10:00', '14:00'), true);
    });

    test('H-5: 전혀 겹치지 않음 — 09~12 vs 14~18', () {
      expect(ApplicationModel.hasTimeOverlap('09:00', '12:00', '14:00', '18:00'), false);
    });

    test('H-6: 인접 경계 — 09~12 vs 12~18 (겹치지 않음)', () {
      // a < y2 && a2 < y1 → 09~12 vs 12~18: 9<18(true) && 12<12(false) → false
      expect(ApplicationModel.hasTimeOverlap('09:00', '12:00', '12:00', '18:00'), false);
    });

    test('H-7: 빈 문자열 → false', () {
      expect(ApplicationModel.hasTimeOverlap('', '18:00', '09:00', '12:00'), false);
      expect(ApplicationModel.hasTimeOverlap('09:00', '', '09:00', '12:00'), false);
    });

    test('H-8: 야간 시프트 — 22:00~02:00 vs 01:00~09:00 → 겹침', () {
      expect(ApplicationModel.hasTimeOverlap('22:00', '02:00', '01:00', '09:00'), true);
    });

    test('H-9: 야간 시프트 — 22:00~02:00 vs 09:00~18:00 → 겹치지 않음', () {
      expect(ApplicationModel.hasTimeOverlap('22:00', '02:00', '09:00', '18:00'), false);
    });

    test('H-10: 야간 시프트 — 20:00~04:00 vs 22:00~06:00 → 겹침', () {
      expect(ApplicationModel.hasTimeOverlap('20:00', '04:00', '22:00', '06:00'), true);
    });
  });

  // ═══════════════════════════════════════════════════════
  // I. workPeriodDisplay — 기간 표시
  // ═══════════════════════════════════════════════════════

  group('I. workPeriodDisplay — 기간 표시', () {
    test('I-1: desiredStartDate 있음 → desiredStartDate~workEndDate 표시', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 8, 1),
        desiredStartDate: DateTime(2026, 8, 10),
        workEndDate: DateTime(2026, 8, 31),
        workDays: ['월'],
      );
      expect(app.workPeriodDisplay, '8/10~8/31');
    });

    test('I-2: desiredStartDate null + confirmedAt > workDate → confirmedAt 기준 표시', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 8, 1),
        confirmedAt: DateTime(2026, 8, 5, 10, 0),
        workEndDate: DateTime(2026, 8, 31),
        workDays: ['월'],
      );
      // confirmedAt(8/5) > workDate(8/1) → effectiveStart = 8/5
      expect(app.workPeriodDisplay, '8/5~8/31');
    });

    test('I-3: desiredStartDate null + confirmedAt == workDate → workDate 기준', () {
      final start = DateTime(2026, 8, 1);
      final app = _app(
        applicationType: 'long_term',
        workDate: start,
        confirmedAt: DateTime(2026, 8, 1, 9, 0), // 같은 날
        workEndDate: DateTime(2026, 8, 31),
        workDays: ['월'],
      );
      expect(app.workPeriodDisplay, '8/1~8/31');
    });

    test('I-4: actualResignDate 있음 → actualResignDate가 종료일', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 8, 1),
        workEndDate: DateTime(2026, 8, 31),
        actualResignDate: DateTime(2026, 8, 15),
        workDays: ['월'],
      );
      expect(app.workPeriodDisplay, '8/1~8/15');
    });

    test('I-5: workEndDate=null → 빈 문자열', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 8, 1),
        workDays: ['월'],
      );
      expect(app.workPeriodDisplay, '');
    });

    test('I-6: desiredStartDate 있을 때 confirmedAt은 effectiveStart에 영향 없음', () {
      final app = _app(
        applicationType: 'long_term',
        workDate: DateTime(2026, 8, 1),
        desiredStartDate: DateTime(2026, 8, 10),
        confirmedAt: DateTime(2026, 8, 20), // confirmedAt이 더 늦어도 무시
        workEndDate: DateTime(2026, 8, 31),
        workDays: ['월'],
      );
      // desiredStartDate 있으면 confirmedAt 보정 비활성 → 8/10 기준
      expect(app.workPeriodDisplay, '8/10~8/31');
    });
  });

  // ═══════════════════════════════════════════════════════
  // J. isScheduledOnDate — 캘린더 표시
  // ═══════════════════════════════════════════════════════

  group('J. isScheduledOnDate — 캘린더 표시', () {
    final mon = DateTime(2026, 8, 3);
    final tue = DateTime(2026, 8, 4);
    final sat = DateTime(2026, 8, 8);

    test('J-1: 단기 — workDate에만 표시', () {
      final app = _app(workDate: mon);
      expect(app.isScheduledOnDate(mon), true);
      expect(app.isScheduledOnDate(tue), false);
    });

    test('J-2: 장기 PENDING — desiredStartDate에만 표시', () {
      final app = _app(
        applicationType: 'long_term',
        status: AppStatus.pending,
        workDate: DateTime(2026, 8, 1),
        desiredStartDate: mon,
        workEndDate: DateTime(2026, 8, 31),
        workDays: ['월'],
      );
      expect(app.isScheduledOnDate(mon), true);
      expect(app.isScheduledOnDate(tue), false);
    });

    test('J-3: 장기 CONFIRMED — 휴무일도 캘린더에 표시됨(회색 처리용)', () {
      final app = _app(
        applicationType: 'long_term',
        status: AppStatus.confirmed,
        workDate: DateTime(2026, 8, 1),
        workEndDate: DateTime(2026, 8, 31),
        workDays: ['월', '화', '수', '목', '금'],
        leaveDates: [mon], // 월요일 휴무
        confirmedAt: DateTime(2026, 8, 1),
      );
      expect(app.isScheduledOnDate(mon), true); // 휴무지만 캘린더 표시
      expect(app.isScheduledOnDate(sat), false); // 비근무 요일
    });

    test('J-4: isTerminationApproved이면 장기 일정 표시 안 함', () {
      final app = _app(
        applicationType: 'long_term',
        status: AppStatus.confirmed,
        workDate: DateTime(2026, 8, 1),
        workEndDate: DateTime(2026, 8, 31),
        workDays: ['월'],
        resignStatus: 'APPROVED',
        actualResignDate: DateTime(2026, 8, 10),
        confirmedAt: DateTime(2026, 8, 1),
      );
      expect(app.isTerminationApproved, true);
      expect(app.isScheduledOnDate(mon), false);
    });
  });

  // ═══════════════════════════════════════════════════════
  // K. isTerminationApproved — 퇴사·해지 완료 판별
  // ═══════════════════════════════════════════════════════

  group('K. isTerminationApproved — 퇴사·해지 완료 판별', () {
    test('K-1: resignStatus=APPROVED → true', () {
      expect(_app(resignStatus: 'APPROVED').isTerminationApproved, true);
    });

    test('K-2: resignStatus=AUTO_APPROVED → true', () {
      expect(_app(resignStatus: 'AUTO_APPROVED').isTerminationApproved, true);
    });

    test('K-3: terminationStatus=APPROVED → true', () {
      expect(_app(terminationStatus: 'APPROVED').isTerminationApproved, true);
    });

    test('K-4: terminationStatus=AUTO_APPROVED → true', () {
      expect(_app(terminationStatus: 'AUTO_APPROVED').isTerminationApproved, true);
    });

    test('K-5: resignStatus=PENDING → false', () {
      expect(_app(resignStatus: 'PENDING').isTerminationApproved, false);
    });

    test('K-6: terminationStatus=PENDING → false', () {
      expect(_app(terminationStatus: 'PENDING').isTerminationApproved, false);
    });

    test('K-7: resignStatus=REJECTED → false', () {
      expect(_app(resignStatus: 'REJECTED').isTerminationApproved, false);
    });

    test('K-8: 둘 다 null → false', () {
      expect(_app().isTerminationApproved, false);
    });
  });

  // ═══════════════════════════════════════════════════════
  // L. 확정 취소 힌트 표시 조건 및 텍스트
  // ═══════════════════════════════════════════════════════

  group('L. 확정 취소 힌트', () {
    test('L-1: 단기 확정 + 내일 근무 → 힌트 표시', () {
      final app = _app(status: AppStatus.confirmed, workDate: tomorrow);
      expect(_showConfirmedCancelHint(app), true);
    });

    test('L-2: 단기 확정 + 오늘 근무 → 힌트 표시', () {
      final app = _app(status: AppStatus.confirmed, workDate: todayOnly);
      expect(_showConfirmedCancelHint(app), true);
    });

    test('L-3: 단기 확정 + 어제 근무(과거) → 힌트 미표시', () {
      final app = _app(status: AppStatus.confirmed, workDate: yesterday);
      expect(_showConfirmedCancelHint(app), false);
    });

    test('L-4: 장기 확정 + 미래 날짜 → 힌트 미표시', () {
      final app = _app(
        status: AppStatus.confirmed,
        workDate: tomorrow,
        applicationType: 'long_term',
        workEndDate: tomorrow.add(const Duration(days: 30)),
        workDays: ['월'],
      );
      expect(_showConfirmedCancelHint(app), false);
    });

    test('L-5: PENDING 상태 → 힌트 미표시', () {
      final app = _app(status: AppStatus.pending, workDate: tomorrow);
      expect(_showConfirmedCancelHint(app), false);
    });

    test('L-6: 오늘 근무 → 노쇼 패널티 경고 문구', () {
      final app = _app(status: AppStatus.confirmed, workDate: todayOnly);
      expect(
        _confirmedCancelHintText(app),
        contains('노쇼'),
      );
    });

    test('L-7: 내일 근무 → 일반 취소 안내 문구', () {
      final app = _app(status: AppStatus.confirmed, workDate: tomorrow);
      expect(
        _confirmedCancelHintText(app),
        contains('공고 상세에서 확정 취소'),
      );
    });
  });

  // ═══════════════════════════════════════════════════════
  // M. AppStatus 상수 그룹 정합성
  // ═══════════════════════════════════════════════════════

  group('M. AppStatus 상수 그룹 정합성', () {
    test('M-1: activeStates 구성', () {
      expect(AppStatus.activeStates, containsAll([
        AppStatus.pending,
        AppStatus.contractPending,
        AppStatus.confirmed,
      ]));
    });

    test('M-2: confirmedStatuses = CONFIRMED + CONTRACT_PENDING', () {
      expect(AppStatus.confirmedStatuses, containsAll([
        AppStatus.confirmed,
        AppStatus.contractPending,
      ]));
      expect(AppStatus.confirmedStatuses.length, 2);
    });

    test('M-3: inactiveStates 구성', () {
      expect(AppStatus.inactiveStates, containsAll([
        AppStatus.rejected,
        AppStatus.canceled,
        AppStatus.autoCanceled,
      ]));
    });

    test('M-4: activeStates와 inactiveStates 교집합 없음', () {
      final intersection = AppStatus.activeStates
          .where((s) => AppStatus.inactiveStates.contains(s));
      expect(intersection.isEmpty, true);
    });

    test('M-5: 취소 필터 로직 — inactiveStates에서 REJECTED 제외 = CANCELED + AUTO_CANCELED', () {
      final canceledGroup = AppStatus.inactiveStates
          .where((s) => s != AppStatus.rejected)
          .toList();
      expect(canceledGroup, containsAll([AppStatus.canceled, AppStatus.autoCanceled]));
      expect(canceledGroup.contains(AppStatus.rejected), false);
    });
  });
}
