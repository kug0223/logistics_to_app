// [R7-P1-2 DEVICE.1E.1] 회복 경로와 lifecycle 분류 — **실행** 검증.
//
//   DEVICE.1E 는 정상 경로만 증명하고 실패→재시도·권한 회수·순서 역전·
//   mutation 후 정합성을 미검증으로 남겼다. 미검증은 closure 면제 사유가
//   아니므로, 화면이 실제로 쓰는 객체를 그대로 실행한다.
//
//   테스트 전용 분기를 만들지 않았다. 주입되는 것은 loader 하나뿐이고,
//   상태기계(`CapacityLoadState`)와 판정(`applicantLoadOutcome`,
//   `staffingRelationOf`)은 production 이 부르는 그 코드다.
//   계산식을 테스트로 복사해 같은 답을 만드는 방식이 아니다.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/capacity_load_state.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/utils/applicant_load_outcome.dart';
import 'package:ALfit/utils/staffing_relation.dart';

// ═══════════════════════════════════════════════════════════════
// fixture — DEV 실측값 (alfit-89567 / zqaJEjUVPA6O1FWajlTX)
// ═══════════════════════════════════════════════════════════════

DateTime _kst(int y, int m, int d, [int h = 0]) =>
    DateTime.utc(y, m, d, h).subtract(const Duration(hours: 9));

final _today = _kst(2026, 9, 27, 12);

const _composite = '사무업무_06:00_08:00';

WorkDetailData _work() => WorkDetailData(
      workType: '사무업무',
      startTime: '06:00',
      endTime: '08:00',
      requiredCount: 2,
      wage: 12000,
    );

/// `loadTOWorkDetails` 가 돌려주는 모양 그대로.
Map<String, dynamic> _ok(int confirmed) => {
      'workDetails': [_work()],
      'workStats': {
        _composite: {'confirmed': confirmed, 'pending': 0}
      },
      'statsFailed': false,
    };

/// 실패했을 때의 실제 모양 — **전부 0 으로 seed 된 map 이 함께 온다.**
Map<String, dynamic> _failed() => {
      'workDetails': [_work()],
      'workStats': {
        _composite: {'confirmed': 0, 'pending': 0}
      },
      'statsFailed': true,
    };

ApplicationModel _app({
  required String status,
  DateTime? workEndDate,
  DateTime? actualResignDate,
  DateTime? confirmedAt,
  DateTime? staffingReleasedAt,
  String? renewalDecision,
  String type = AppType.longTerm,
}) =>
    ApplicationModel(
      id: 'a1',
      toId: 'to1',
      uid: 'u1',
      businessId: 'biz1',
      businessName: '위워커',
      toTitle: '[R7FIX] 장기 근무 공고',
      status: status,
      applicationType: type,
      selectedWorkType: '사무업무',
      startTime: '06:00',
      endTime: '08:00',
      wage: 12000,
      workDate: _kst(2026, 9, 9),
      confirmedAt: confirmedAt ?? _kst(2026, 9, 16, 5),
      workEndDate: workEndDate,
      actualResignDate: actualResignDate,
      staffingReleasedAt: staffingReleasedAt,
      renewalDecision: renewalDecision,
      workDays: const ['월', '화', '수', '목', '금', '토', '일'],
      appliedAt: _kst(2026, 9, 15, 9),
    );

void main() {
  // ══════════════════════════════════════════════════════════════
  // A. 정원 실패 → 재시도 → 회복
  // ══════════════════════════════════════════════════════════════

  group('REC-A capacity 실패 → 재시도', () {
    test('REC-A1 실패는 UNKNOWN 이다 — seed 된 0 을 쓰지 않는다', () async {
      final cap = CapacityLoadState(loader: () async => _failed());
      await cap.load();

      expect(cap.failed, isTrue);
      expect(cap.confirmedFor(_work()), isNull,
          reason: 'statsFailed 응답의 0 은 아무도 읽지 못한 값이다');
      expect(
          inviteCapacityStateOf(
              canonicalConfirmed: cap.confirmedFor(_work()), requiredCount: 2),
          InviteCapacityState.unknown);
    });

    test('REC-A2 재시도가 정원 source 를 **실제로 다시 호출**한다', () async {
      var calls = 0;
      final cap = CapacityLoadState(loader: () async {
        calls++;
        return calls == 1 ? _failed() : _ok(0);
      });

      await cap.load();
      expect(calls, 1);
      expect(cap.failed, isTrue);

      // 화면의 `다시 시도` 가 부르는 바로 그 함수.
      await cap.load();
      expect(calls, 2, reason: '지원서만 다시 읽던 과거 동작이면 여기서 1 이다');
      expect(cap.failed, isFalse, reason: '배너가 사라진다');
      expect(cap.confirmedFor(_work()), 0, reason: '성공한 0 은 진짜 0 이다');
      expect(
          staffingShortageOf(
              capacity: inviteCapacityStateOf(
                  canonicalConfirmed: cap.confirmedFor(_work()),
                  requiredCount: 2),
              requiredCount: 2,
              seatedConfirmed: 0),
          2);
    });

    test('REC-A3 예외로 끝나도 UNKNOWN 이고 재시도로 회복된다', () async {
      var calls = 0;
      final cap = CapacityLoadState(loader: () async {
        calls++;
        if (calls == 1) throw FirebaseException(plugin: 'cloud_firestore');
        return _ok(1);
      });
      await cap.load();
      expect(cap.confirmedFor(_work()), isNull);
      await cap.load();
      expect(cap.confirmedFor(_work()), 1);
    });

    test('REC-A4 재시도가 상태를 중복시키지 않는다', () async {
      final cap = CapacityLoadState(loader: () async => _ok(1));
      await cap.load();
      await cap.load();
      await cap.load();
      expect(cap.stats!.length, 1, reason: '같은 키에 덮어쓴다 — 행이 늘지 않는다');
      expect(cap.confirmedFor(_work()), 1);
    });

    test('REC-A5 부모 snapshot 이 실패였으면 그 0 을 쓰지 않는다', () {
      final cap = CapacityLoadState(loader: () async => _ok(0));
      cap.seed({
        _composite: {'confirmed': 0, 'pending': 0}
      }, parentFailed: true);
      expect(cap.confirmedFor(_work()), isNull);
    });

    test('REC-A6 정상 부모 snapshot 은 첫 프레임에 그대로 쓴다', () {
      final cap = CapacityLoadState(loader: () async => _ok(0));
      cap.seed({
        _composite: {'confirmed': 1, 'pending': 0}
      }, parentFailed: false);
      expect(cap.confirmedFor(_work()), 1);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // B/C. 사람 목록 — 실패 vs 빈 목록 vs 권한 거부
  // ══════════════════════════════════════════════════════════════

  group('REC-B 실패와 없음은 다르다', () {
    test('REC-B1 최초 실패 → ERROR (지원자 없음이 아니다)', () {
      final o = applicantLoadOutcome(ok: false, denied: false, hadRows: false);
      expect(o.loadFailed, isTrue);
      expect(o.clearRows, isFalse);
      expect(o.refreshFailed, isFalse);
    });

    test('REC-B2 성공한 빈 목록은 진짜 없음이다', () {
      final o = applicantLoadOutcome(ok: true, denied: false, hadRows: false);
      expect(o.loadFailed, isFalse);
      expect(o.refreshFailed, isFalse);
    });

    test('REC-B3 새로고침 실패는 기존 명단을 지우지 않는다 (PARTIAL)', () {
      final o = applicantLoadOutcome(ok: false, denied: false, hadRows: true);
      expect(o.refreshFailed, isTrue);
      expect(o.clearRows, isFalse);
      expect(o.loadFailed, isFalse);
    });
  });

  group('REC-C 권한 거부는 일반 오류와 다르다', () {
    test('REC-C1 code 로만 판정한다', () {
      expect(
          isPermissionDenialError(
              FirebaseFunctionsException(code: 'permission-denied', message: '')),
          isTrue);
      expect(
          isPermissionDenialError(
              FirebaseFunctionsException(code: 'unauthenticated', message: '')),
          isTrue);
      expect(
          isPermissionDenialError(
              FirebaseFunctionsException(code: 'unavailable', message: '')),
          isFalse,
          reason: '네트워크 오류를 권한 거부로 읽으면 남의 권한을 지운다');
      expect(isPermissionDenialError(Exception('permission denied')), isFalse,
          reason: '문구로 판별하지 않는다');
    });

    test('REC-C2 확인된 거부는 행을 지운다 — stale + 배너 조합이 아니다', () {
      final o = applicantLoadOutcome(ok: false, denied: true, hadRows: true);
      expect(o.clearRows, isTrue);
      expect(o.refreshFailed, isFalse);
      expect(o.loadFailed, isFalse);
    });

    test('REC-C3 회수 뒤 늦게 도착한 정원 응답이 다시 노출되지 않는다', () async {
      final gate = Completer<Map<String, dynamic>>();
      final cap = CapacityLoadState(loader: () => gate.future);

      final inFlight = cap.load(); // 조회 시작 — 아직 응답 전
      cap.clearOnRevocation(); // 권한 회수 확인
      expect(cap.confirmedFor(_work()), isNull);

      gate.complete(_ok(2)); // 회수 **후** 응답 도착
      await inFlight;

      expect(cap.stats, isNull, reason: '회수 뒤 정원이 되살아나면 안 된다');
      expect(cap.confirmedFor(_work()), isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // D. 순서 역전 / dispose
  // ══════════════════════════════════════════════════════════════

  group('REC-D 늦게 온 응답', () {
    test('REC-D1 이전 요청이 새 요청을 덮지 않는다', () async {
      final first = Completer<Map<String, dynamic>>();
      final second = Completer<Map<String, dynamic>>();
      var calls = 0;
      final cap = CapacityLoadState(loader: () {
        calls++;
        return calls == 1 ? first.future : second.future;
      });

      final f1 = cap.load();
      final f2 = cap.load();

      // 두 번째가 먼저 도착한다.
      second.complete(_ok(2));
      await f2;
      expect(cap.confirmedFor(_work()), 2);

      // 첫 번째가 뒤늦게 도착 — 과거다.
      first.complete(_ok(99));
      await f1;
      expect(cap.confirmedFor(_work()), 2,
          reason: '순서가 뒤집혀도 최신 요청의 답이 남는다');
    });

    test('REC-D2 dispose 이후 응답은 아무것도 바꾸지 않는다', () async {
      final gate = Completer<Map<String, dynamic>>();
      var notified = 0;
      final cap = CapacityLoadState(
          loader: () => gate.future, onChanged: () => notified++);

      final f = cap.load();
      final before = notified;
      cap.dispose();
      gate.complete(_ok(3));
      await f;

      expect(cap.stats, isNull);
      expect(notified, before, reason: 'dispose 뒤에는 setState 를 부르지 않는다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // E. mutation 후 정합성
  // ══════════════════════════════════════════════════════════════

  group('REC-E mutation 후', () {
    test('REC-E1 로컬 반영이 즉시 보이고, 진행 중이던 응답에 덮이지 않는다', () async {
      final stale = Completer<Map<String, dynamic>>();
      final cap = CapacityLoadState(loader: () => stale.future);

      final inFlight = cap.load(); // mutation **전에** 나간 요청
      cap.applyLocal({
        _composite: {'confirmed': 1, 'pending': 0}
      });
      expect(cap.confirmedFor(_work()), 1);

      stale.complete(_ok(0)); // 확정 전 상태가 뒤늦게 도착
      await inFlight;

      expect(cap.confirmedFor(_work()), 1,
          reason: '방금 확정한 사람이 사라지면 안 된다');
    });

    test('REC-E2 그 다음 canonical 조회가 최종 권위다', () async {
      final cap = CapacityLoadState(loader: () async => _ok(1));
      cap.applyLocal({
        _composite: {'confirmed': 2, 'pending': 0}
      });
      expect(cap.confirmedFor(_work()), 2);
      await cap.load();
      expect(cap.confirmedFor(_work()), 1,
          reason: '서버가 세는 좌석이 최종이다 — 로컬 값이 영구히 이기지 않는다');
    });

    test('REC-E3 빈 로컬 집계가 아는 값을 덮지 않는다', () async {
      final cap = CapacityLoadState(loader: () async => _ok(1));
      await cap.load();
      cap.applyLocal({});
      expect(cap.confirmedFor(_work()), 1,
          reason: '셀 업무가 없었다면 정원에 대해 아무 말도 하지 못한 것이다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // F. §4 — 좌석 아님 != 계약 종료
  // ══════════════════════════════════════════════════════════════

  group('REC-F lifecycle 분류', () {
    test('REC-F1 현재 유효 관계', () {
      final r = staffingRelationOf(
          _app(status: AppStatus.confirmed, workEndDate: _kst(2026, 10, 20)),
          _today);
      expect(r.isCurrentStaffing, isTrue);
      expect(r.resolvedEnded, isFalse);
      expect(r.decisionPending, isFalse);
    });

    test('REC-F2 미래 종료 D — D 까지 유효, 종료 예정', () {
      final app =
          _app(status: AppStatus.confirmed, workEndDate: _kst(2026, 10, 5));
      final r = staffingRelationOf(app, _today);
      expect(r.isCurrentStaffing, isTrue);
      expect(r.endingSoon, isTrue);
      expect(staffingRelationLabel(app, _today), '계약 종료 예정');
    });

    test('REC-F3 resolved TERMINATE + D+1 → 좌석 제외, 이력 보존', () {
      // DEV 실측 fixture 그대로.
      final app = _app(
          status: AppStatus.contractPending,
          workEndDate: _kst(2026, 9, 22),
          renewalDecision: 'TERMINATE');
      final r = staffingRelationOf(app, _today);
      expect(r.isCurrentStaffing, isFalse);
      expect(r.resolvedEnded, isTrue);
      expect(r.decisionPending, isFalse);
      expect(staffingRelationLabel(app, _today), '계약 종료');
    });

    test('REC-F4 **만료 + 미결정은 계약 종료가 아니다**', () {
      // DEVICE.1E 가 틀렸던 자리 — 좌석이 비었다는 이유로 종료로 적었다.
      final app = _app(
          status: AppStatus.contractPending,
          workEndDate: _kst(2026, 9, 22)); // renewalDecision 없음
      final r = staffingRelationOf(app, _today);
      expect(r.isCurrentStaffing, isFalse, reason: '좌석은 비었다');
      expect(r.decisionPending, isTrue, reason: '결정이 남아 있다');
      expect(r.resolvedEnded, isFalse, reason: '종료로 단정하면 관리자 할 일이 사라진다');
      expect(staffingRelationLabel(app, _today), '계약 확인 필요');
    });

    test('REC-F5 **좌석 반납 != 관계 종료**', () {
      // DEVICE.1E 가 틀렸던 또 한 자리 — 정원은 빼는데 사람 수는 세었다.
      final app = _app(
          status: AppStatus.confirmed,
          workEndDate: _kst(2026, 10, 20),
          staffingReleasedAt: _kst(2026, 9, 25));
      final r = staffingRelationOf(app, _today);
      expect(r.isCurrentStaffing, isFalse, reason: '정원 조회와 같은 규칙');
      expect(r.seatReleased, isTrue);
      expect(r.resolvedEnded, isFalse);
      expect(r.decisionPending, isFalse);
      expect(staffingRelationLabel(app, _today), '좌석 반납');
    });

    test('REC-F6 퇴사 승인은 결정이 끝난 것이다', () {
      final app = _app(
        status: AppStatus.confirmed,
        workEndDate: _kst(2026, 9, 22),
      ).copyWith(resignStatus: AppStatus.approved);
      final r = staffingRelationOf(app, _today);
      expect(r.resolvedEnded, isTrue);
      expect(r.decisionPending, isFalse);
    });

    test('REC-F7 단기는 날짜 축이 없다 — 기존 판정 유지', () {
      final app = _app(
          status: AppStatus.confirmed,
          type: AppType.shortTerm,
          workEndDate: _kst(2026, 9, 22));
      final r = staffingRelationOf(app, _today);
      expect(r.isCurrentStaffing, isTrue);
      expect(r.resolvedEnded, isFalse);
      expect(staffingRelationLabel(app, _today), isNull);
    });

    test('REC-F8 종료일을 모르면 좌석을 빼앗지 않는다', () {
      final r = staffingRelationOf(_app(status: AppStatus.confirmed), _today);
      expect(r.isCurrentStaffing, isTrue);
      expect(r.resolvedEnded, isFalse);
    });

    test('REC-F9 현재 인력 규칙이 정원 규칙과 같다', () {
      // 같은 모집단이어야 `확정 N` 과 `부족` 이 갈리지 않는다.
      final rows = [
        _app(status: AppStatus.confirmed, workEndDate: _kst(2026, 10, 20)),
        _app(
            status: AppStatus.confirmed,
            workEndDate: _kst(2026, 10, 20),
            staffingReleasedAt: _kst(2026, 9, 25)),
        _app(
            status: AppStatus.contractPending,
            workEndDate: _kst(2026, 9, 22),
            renewalDecision: 'TERMINATE'),
      ];
      final current =
          rows.where((a) => staffingRelationOf(a, _today).isCurrentStaffing);
      expect(current.length, 1);
    });
  });
}
