// test/simulation/admin_confirmed_tab_simulation_test.dart
//
// 출근 현황 다이얼로그 4탭 분류 로직 시뮬레이션
// 목적: _workersByTab 의 탭 분류 우선순위(isDone > adminConfirmed > 검토상태 > 정상)를
//       순수 함수로 재구현하여 경계 케이스까지 검증한다.

import 'package:flutter_test/flutter_test.dart';

// ── 탭 분류 헬퍼 (attendance_status_dialog._workersByTab 로직 재구현) ──
//
// 실제 코드 (대략):
//   const reviewStatuses = {'late', 'missed_checkout', 'early_leave'};
//   const doneUiStatuses = {'transferred', 'final_confirmed', 'wage_confirmed', 'noshow'};
//   isDone = doneUiStatuses.contains(s) || wageStatus == calculated/confirmed/transferred || status == NO_SHOW
//   isAdminConfirmed = attendance.adminConfirmed == true
//   tab0: (reviewStatuses || s=='pending') && !isDone && !isAdminConfirmed
//   tab1: !reviewStatuses && s!='pending' && !isDone && !isAdminConfirmed
//   tab2: isAdminConfirmed && !isDone
//   tab3: isDone

const _reviewStatuses = {'late', 'missed_checkout', 'early_leave'};
const _doneUiStatuses = {'transferred', 'final_confirmed', 'wage_confirmed', 'noshow'};

/// isDone 판별: UI status가 완료 집합에 속하거나 wageStatus가 확정 이후이거나
/// attendance status 가 NO_SHOW 인 경우
bool _isDone({
  required String uiStatus,
  String wageStatus = 'pending',
  String attendanceStatus = 'present',
}) {
  return _doneUiStatuses.contains(uiStatus) ||
      wageStatus == 'calculated' ||
      wageStatus == 'confirmed' ||
      wageStatus == 'transferred' ||
      attendanceStatus == 'NO_SHOW';
}

/// 4탭 분류: 0=검토, 1=정상, 2=확인, 3=완료
/// status: _getAttendanceStatus 반환값 (UI 상태)
/// adminConfirmed: AttendanceModel.adminConfirmed
/// isDone: _isDone() 결과
int classifyWorkerTab({
  required String status,
  bool adminConfirmed = false,
  required bool isDone,
}) {
  if (isDone) return 3;
  if (adminConfirmed) return 2;
  if (_reviewStatuses.contains(status) || status == 'pending') return 0;
  return 1;
}

void main() {
  // ════════════════════════════════════════════════════════════════════
  // 탭 0: 검토 탭 — 이슈/미출근 상태이며 미완료·미확인
  // ════════════════════════════════════════════════════════════════════
  group('탭 0 — 검토 탭', () {
    test('status=late, adminConfirmed=false, isDone=false → 탭 0', () {
      expect(
        classifyWorkerTab(status: 'late', adminConfirmed: false, isDone: false),
        0,
      );
    });

    test('status=missed_checkout, adminConfirmed=false, isDone=false → 탭 0', () {
      expect(
        classifyWorkerTab(status: 'missed_checkout', adminConfirmed: false, isDone: false),
        0,
      );
    });

    test('status=early_leave, adminConfirmed=false, isDone=false → 탭 0', () {
      expect(
        classifyWorkerTab(status: 'early_leave', adminConfirmed: false, isDone: false),
        0,
      );
    });

    test('status=pending, adminConfirmed=false, isDone=false → 탭 0', () {
      expect(
        classifyWorkerTab(status: 'pending', adminConfirmed: false, isDone: false),
        0,
      );
    });

    test('status=pending, adminConfirmed=null(false), isDone=false → 탭 0', () {
      // adminConfirmed 기본값 false
      expect(
        classifyWorkerTab(status: 'pending', isDone: false),
        0,
      );
    });

    test('status=late (이슈+미검토), adminConfirmed=false, isDone=false → 탭 0', () {
      // 이슈 상태 + 관리자 미확인: 검토 탭
      final done = _isDone(uiStatus: 'late', wageStatus: 'pending');
      expect(
        classifyWorkerTab(status: 'late', adminConfirmed: false, isDone: done),
        0,
      );
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 탭 1: 정상 탭 — 이슈 없음, 미완료, 미확인
  // ════════════════════════════════════════════════════════════════════
  group('탭 1 — 정상 탭', () {
    test('status=present, adminConfirmed=false, isDone=false → 탭 1', () {
      expect(
        classifyWorkerTab(status: 'present', adminConfirmed: false, isDone: false),
        1,
      );
    });

    test('status=present, adminConfirmed=null(false), isDone=false → 탭 1', () {
      expect(
        classifyWorkerTab(status: 'present', isDone: false),
        1,
      );
    });

    test('status=on_time, adminConfirmed=false, isDone=false → 탭 1', () {
      expect(
        classifyWorkerTab(status: 'on_time', adminConfirmed: false, isDone: false),
        1,
      );
    });

    test('status=overtime, adminConfirmed=false, isDone=false → 탭 1', () {
      expect(
        classifyWorkerTab(status: 'overtime', adminConfirmed: false, isDone: false),
        1,
      );
    });

    test('status=early_arrival, adminConfirmed=false, isDone=false → 탭 1', () {
      expect(
        classifyWorkerTab(status: 'early_arrival', adminConfirmed: false, isDone: false),
        1,
      );
    });

    test('status=checkin (출근중), adminConfirmed=false, isDone=false → 탭 1', () {
      // checkin 은 reviewStatuses/pending 에 미포함 → 정상 탭
      expect(
        classifyWorkerTab(status: 'checkin', adminConfirmed: false, isDone: false),
        1,
      );
    });

    test('status=checkout, adminConfirmed=false, isDone=false → 탭 1', () {
      // checkout UI 상태 자체는 doneUiStatuses 미포함이면 정상 탭
      final done = _isDone(uiStatus: 'checkout', wageStatus: 'pending');
      expect(
        classifyWorkerTab(status: 'checkout', adminConfirmed: false, isDone: done),
        1,
      );
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 탭 2: 확인 탭 — adminConfirmed=true, 미완료
  // ════════════════════════════════════════════════════════════════════
  group('탭 2 — 확인 탭 (adminConfirmed=true)', () {
    test('status=present, adminConfirmed=true, isDone=false → 탭 2', () {
      expect(
        classifyWorkerTab(status: 'present', adminConfirmed: true, isDone: false),
        2,
      );
    });

    test('status=late (이슈지만 확인됨), adminConfirmed=true, isDone=false → 탭 2', () {
      expect(
        classifyWorkerTab(status: 'late', adminConfirmed: true, isDone: false),
        2,
      );
    });

    test('status=pending, adminConfirmed=true, isDone=false → 탭 2', () {
      expect(
        classifyWorkerTab(status: 'pending', adminConfirmed: true, isDone: false),
        2,
      );
    });

    test('status=early_leave, adminConfirmed=true, isDone=false → 탭 2', () {
      expect(
        classifyWorkerTab(status: 'early_leave', adminConfirmed: true, isDone: false),
        2,
      );
    });

    test('status=missed_checkout, adminConfirmed=true, isDone=false → 탭 2', () {
      expect(
        classifyWorkerTab(status: 'missed_checkout', adminConfirmed: true, isDone: false),
        2,
      );
    });

    test('status=overtime, adminConfirmed=true, isDone=false → 탭 2', () {
      expect(
        classifyWorkerTab(status: 'overtime', adminConfirmed: true, isDone: false),
        2,
      );
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 탭 3: 완료 탭 — isDone=true (우선순위 최고)
  // ════════════════════════════════════════════════════════════════════
  group('탭 3 — 완료 탭 (isDone=true)', () {
    test('UI status=transferred, isDone=true → 탭 3', () {
      final done = _isDone(uiStatus: 'transferred');
      expect(
        classifyWorkerTab(status: 'transferred', adminConfirmed: false, isDone: done),
        3,
      );
    });

    test('UI status=noshow, isDone=true → 탭 3', () {
      final done = _isDone(uiStatus: 'noshow');
      expect(
        classifyWorkerTab(status: 'noshow', adminConfirmed: false, isDone: done),
        3,
      );
    });

    test('wageStatus=transferred, adminConfirmed=false → isDone=true → 탭 3', () {
      final done = _isDone(uiStatus: 'checkout', wageStatus: 'transferred');
      expect(
        classifyWorkerTab(status: 'checkout', adminConfirmed: false, isDone: done),
        3,
      );
    });

    test('adminConfirmed=true이지만 isDone=true이면 탭 3 (isDone 우선)', () {
      final done = _isDone(uiStatus: 'wage_confirmed');
      expect(
        classifyWorkerTab(status: 'wage_confirmed', adminConfirmed: true, isDone: done),
        3,
      );
    });

    test('status=present, adminConfirmed=true, isDone=true → 탭 3 (isDone이 adminConfirmed보다 우선)', () {
      expect(
        classifyWorkerTab(status: 'present', adminConfirmed: true, isDone: true),
        3,
      );
    });

    test('status=pending, adminConfirmed=false, isDone=true → 탭 3', () {
      expect(
        classifyWorkerTab(status: 'pending', adminConfirmed: false, isDone: true),
        3,
      );
    });

    test('wageStatus=calculated → isDone=true → 탭 3', () {
      final done = _isDone(uiStatus: 'checkout', wageStatus: 'calculated');
      expect(
        classifyWorkerTab(status: 'checkout', adminConfirmed: false, isDone: done),
        3,
      );
    });

    test('wageStatus=confirmed → isDone=true → 탭 3', () {
      final done = _isDone(uiStatus: 'checkout', wageStatus: 'confirmed');
      expect(
        classifyWorkerTab(status: 'checkout', adminConfirmed: false, isDone: done),
        3,
      );
    });

    test('attendanceStatus=NO_SHOW → isDone=true → 탭 3', () {
      final done = _isDone(uiStatus: 'pending', wageStatus: 'pending', attendanceStatus: 'NO_SHOW');
      expect(
        classifyWorkerTab(status: 'pending', adminConfirmed: false, isDone: done),
        3,
      );
    });

    test('UI status=final_confirmed → isDone=true → 탭 3', () {
      final done = _isDone(uiStatus: 'final_confirmed');
      expect(
        classifyWorkerTab(status: 'final_confirmed', adminConfirmed: false, isDone: done),
        3,
      );
    });
  });

  // ════════════════════════════════════════════════════════════════════
  // 탭 우선순위 경계 케이스
  // ════════════════════════════════════════════════════════════════════
  group('탭 우선순위 경계 케이스', () {
    test('isDone=true이면 adminConfirmed=true라도 탭 3', () {
      expect(
        classifyWorkerTab(status: 'late', adminConfirmed: true, isDone: true),
        3,
      );
    });

    test('isDone=true이면 status=late(검토)라도 탭 3', () {
      expect(
        classifyWorkerTab(status: 'late', adminConfirmed: false, isDone: true),
        3,
      );
    });

    test('adminConfirmed=true, isDone=false이면 status=early_leave(검토상태)라도 탭 2', () {
      expect(
        classifyWorkerTab(status: 'early_leave', adminConfirmed: true, isDone: false),
        2,
      );
    });

    test('adminConfirmed=true, isDone=false이면 status=pending이라도 탭 2', () {
      expect(
        classifyWorkerTab(status: 'pending', adminConfirmed: true, isDone: false),
        2,
      );
    });

    test('탭 우선순위: isDone(3) > adminConfirmed(2) > 검토status(0) > 나머지(1)', () {
      // 가장 높은 우선순위: isDone
      expect(classifyWorkerTab(status: 'late', adminConfirmed: true, isDone: true), 3);
      // 두 번째: adminConfirmed
      expect(classifyWorkerTab(status: 'late', adminConfirmed: true, isDone: false), 2);
      // 세 번째: 검토 상태
      expect(classifyWorkerTab(status: 'late', adminConfirmed: false, isDone: false), 0);
      // 나머지: 정상
      expect(classifyWorkerTab(status: 'present', adminConfirmed: false, isDone: false), 1);
    });

    test('_doneUiStatuses 전체 집합 → 모두 isDone=true', () {
      for (final s in _doneUiStatuses) {
        final done = _isDone(uiStatus: s);
        expect(done, isTrue, reason: 'doneUiStatus=$s 는 isDone이어야 함');
      }
    });

    test('_reviewStatuses 전체 집합 → adminConfirmed=false, isDone=false이면 탭 0', () {
      for (final s in _reviewStatuses) {
        expect(
          classifyWorkerTab(status: s, adminConfirmed: false, isDone: false),
          0,
          reason: 'reviewStatus=$s 는 탭 0이어야 함',
        );
      }
    });
  });
}
