// [.5-PATCH] TERMINATION EFFECTIVE-DATE / WORKER TASK / EXIT MUTEX
//
//   해지 승인은 **결정**이지 효력이 아니다.
//
//   예전에는 미래 효력일 D 를 기록하면서 같은 트랜잭션에서 status 를
//   CANCELED 로 바꾸고 정원을 줄이고 계약서를 void 하고 계정 세션까지
//   끊었다. 그래서 canonical worker-day resolver 는 "D 까지 근무"라고
//   말하는데 좌석·달력·고정근무자 명단은 "승인 즉시 끝"이라고 말했다.
//   같은 관계에 두 개의 진실이 있었고, 그 사이 기간의 근태·급여·연락을
//   아무도 처리할 수 없었다.
//
//       APPROVED ≠ EFFECTIVE
//       actualResignDate = D = 마지막으로 일할 수 있는 날 (inclusive)
//       D+1 부터 종료 효력
//
//   그리고 응답해야 할 사람은 근로자인데 홈에 그 일이 없었다. 알림이
//   유일한 경로였고, 알림을 지우면 D+3 에 조용히 자동 승인됐다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/ui/pending_termination_surface.dart';

const _cfPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 주석 줄을 지운 본문. 앵커는 주석이 아니라 **코드**여야 한다.
String _codeOf(String s) =>
    s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  if (i < 0) throw StateError('$name 를 찾지 못함');
  return src.substring(i, (i + chars).clamp(0, src.length));
}

DateTime _d(int y, int m, int day) => DateTime(y, m, day);

ApplicationModel _app({
  String status = AppStatus.confirmed,
  String? resignStatus,
  String? terminationStatus,
  DateTime? actualResignDate,
  DateTime? workEndDate,
  String id = 'app1',
  String businessName = '위워커',
}) =>
    ApplicationModel(
      id: id,
      businessId: 'biz1',
      businessName: businessName,
      toTitle: '[테스트] 장기',
      workDate: _d(2026, 9, 1),
      workEndDate: workEndDate ?? _d(2026, 12, 31),
      workDays: const ['월', '화', '수', '목', '금'],
      startTime: '09:00',
      endTime: '18:00',
      uid: 'worker1',
      selectedWorkType: '사무업무',
      wage: 12000,
      wageType: 'hourly',
      status: status,
      appliedAt: _d(2026, 8, 25),
      confirmedAt: _d(2026, 9, 1),
      resignStatus: resignStatus,
      terminationStatus: terminationStatus,
      actualResignDate: actualResignDate,
    );

void main() {
  final cf = _codeOf(_src(_cfPath));

  // ════════════════════════════════════════════════════════════════
  group('§48 수동 승인 — 결정만 쓴다', () {
    // 측정된 실제 span: callableApproveTermination → callableApproveResignation
    final approve = _after(cf, 'callableApproveTermination = onCall', 6800);

    test('T-01 terminationStatus=APPROVED 와 승인자를 기록한다', () {
      expect(approve.contains('terminationStatus: "APPROVED"'), isTrue);
      expect(approve.contains('terminationApprovedBy: callerUid'), isTrue);
      expect(approve.contains('terminationRespondedAt:'), isTrue);
    });

    test('T-02 actualResignDate = terminationEffectiveDate (D 를 확정한다)', () {
      expect(
        approve.contains('actualResignDate:\n          terminationEffectiveDate ??'),
        isTrue,
      );
    });

    test('T-03 status 를 CANCELED 로 바꾸지 않는다', () {
      expect(approve.contains('status: "CANCELED"'), isFalse);
    });

    test('T-04 confirmedDecrementedAt 를 쓰지 않는다 — 효력 전환의 마커다', () {
      expect(approve.contains('confirmedDecrementedAt'), isFalse);
    });

    test('T-05 정원을 줄이지 않는다', () {
      expect(approve.contains('totalConfirmed'), isFalse);
      expect(approve.contains('confirmedCount'), isFalse);
    });

    test('T-06 계약서를 void 하지 않는다', () {
      expect(approve.contains('status: "voided"'), isFalse);
      expect(approve.contains('voidReason'), isFalse);
    });

    test('T-07 승인 시점에 계정 세션을 끊지 않는다', () {
      expect(approve.contains('revokeRefreshTokens'), isFalse);
    });

    test('T-08 근로자 본인 또는 canManageWorkers 관리자만 — 권한 불변', () {
      expect(approve.contains('const isWorker = callerUid === workerUid'), isTrue);
      expect(approve.contains('canManageWorkers'), isTrue);
    });

    test('T-09 요청자 자기승인 차단이 남아 있다', () {
      expect(approve.contains('requestedBy === callerUid'), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§49 D+3 자동 승인 — manual 과 같은 operational truth', () {
    // 측정된 span: 이 블록의 마지막 단정 대상(actualResignDate: d3Effective)이
    //   +1305 에 있고, 금지 토큰(status:"CANCELED" 등)은 +19,246 이후다.
    final auto = _after(cf, 'const pendingTerminationSnap', 1450);

    test('T-10 terminationStatus=AUTO_APPROVED', () {
      expect(auto.contains('terminationStatus: "AUTO_APPROVED"'), isTrue);
    });

    test('T-11 종료일을 발명하지 않는다 — requestedAt + 24h 금지', () {
      expect(auto.contains('24 * 60 * 60 * 1000'), isFalse);
      expect(auto.contains('terminationEffectiveDate: Timestamp.fromDate'), isFalse);
    });

    test('T-12 요청이 이미 가진 terminationEffectiveDate 를 D 로 쓴다', () {
      expect(auto.contains('freshD3.terminationEffectiveDate'), isTrue);
      expect(auto.contains('actualResignDate: d3Effective'), isTrue);
    });

    test('T-13 D 가 없으면 자동승인을 보류한다 — 날짜를 만들지 않는다', () {
      expect(auto.contains('if (!d3Effective)'), isTrue);
    });

    test('T-14 status/정원/마커를 건드리지 않는다', () {
      expect(auto.contains('status: "CANCELED"'), isFalse);
      expect(auto.contains('confirmedDecrementedAt'), isFalse);
      expect(auto.contains('totalConfirmed'), isFalse);
    });

    test('T-15 승인 시점에 세션을 끊지 않는다', () {
      expect(auto.contains('revokeRefreshTokens'), isFalse);
    });

    test('T-16 PENDING 일 때만 전이 — 멱등', () {
      expect(auto.contains('terminationStatus !== "PENDING"'), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§9/§12 효력 전환 — 퇴사와 해지가 같은 전환을 쓴다', () {
    final tr = _after(cf, 'async function processExitEffectiveTransition', 11800);

    test('T-17 퇴사 population 이 그대로 있다 (회귀)', () {
      expect(tr.contains('exitQuery("resignStatus", "APPROVED", "CONFIRMED")'), isTrue);
      expect(
        tr.contains('exitQuery("resignStatus", "AUTO_APPROVED", "CONTRACT_PENDING")'),
        isTrue,
      );
    });

    test('T-18 해지 population 이 추가됐다', () {
      expect(
        tr.contains('exitQuery("terminationStatus", "APPROVED", "CONFIRMED")'),
        isTrue,
      );
      expect(
        tr.contains('exitQuery("terminationStatus", "AUTO_APPROVED", "CONTRACT_PENDING")'),
        isTrue,
      );
    });

    test('T-19 새 scheduler 를 복제하지 않았다 — 하나의 전환', () {
      expect(cf.contains('processTerminationEffectiveTransition'), isFalse);
      expect(cf.contains('processResignEffectiveTransition'), isFalse);
    });

    test('T-20 §15 KST 달력 경계 — raw Timestamp < now 를 쓰지 않는다', () {
      expect(tr.contains('const todayKstMidnight'), isTrue);
      expect(tr.contains('.where("actualResignDate", "<", todayKstMidnight)'), isTrue);
      expect(tr.contains('actualResignDate", "<", now'), isFalse);
    });

    test('T-21 §16 D 당일은 전환하지 않는다 — 오늘 > D 일 때만', () {
      expect(
        tr.contains('nowDateNum <= srvKstDateNum(actualResignDate)'),
        isTrue,
      );
      expect(
        tr.contains('nowDateNum <= srvKstDateNum(freshActualResignDate)'),
        isTrue,
      );
    });

    test('T-22 §17 confirmedDecrementedAt 는 여기서만 쓴다', () {
      expect(tr.contains('confirmedDecrementedAt: admin.firestore.FieldValue.serverTimestamp()'), isTrue);
    });

    test('T-23 §52 멱등 — 이미 전환된 건은 두 번 줄이지 않는다', () {
      expect(tr.contains('if (freshApp.confirmedDecrementedAt) return;'), isTrue);
    });

    test('T-24 승인된 종료만 전환한다 — fresh 재확인', () {
      expect(tr.contains('freshApproved.includes(freshApp.terminationStatus'), isTrue);
    });

    test('T-25 §19/§53 completed 계약서는 절대 void 하지 않는다', () {
      expect(tr.contains('voidablePendingStatuses'), isTrue);
      expect(
        tr.contains('const voidablePendingStatuses = ["pending_employer", "pending_worker"]'),
        isTrue,
      );
    });

    test('T-26 종료 사유가 퇴사/해지를 구분한다', () {
      expect(tr.contains('cancelReason: `\${exitKind}_EFFECTIVE`'), isTrue);
    });

    test('T-27 §11 세션 무효화는 D+1 로 옮겨졌다', () {
      expect(tr.contains('revokeRefreshTokens'), isTrue);
    });

    test('T-28 §54 D 이전 실제 근태는 건드리지 않는다 — strict > 만 absent', () {
      expect(tr.contains('workDate > actualResignDate'), isTrue);
      expect(tr.contains('workDate >= actualResignDate'), isFalse);
    });

    test('T-29 재시도 population 이 해지도 포함한다', () {
      expect(
        tr.contains('["RESIGNATION_EFFECTIVE", "TERMINATION_EFFECTIVE"]'),
        isTrue,
      );
    });

    test('T-30 자정 스케줄러가 이 전환을 부른다', () {
      expect(cf.contains('processExitEffectiveTransition(timestamp)'), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§36–39 퇴사 ↔ 해지 상호배제', () {
    test('T-31 conflict 상태는 PENDING/APPROVED/AUTO_APPROVED 뿐', () {
      expect(
        cf.contains(
            'const EXIT_CONFLICT_STATUSES = ["PENDING", "APPROVED", "AUTO_APPROVED"]'),
        isTrue,
      );
    });

    test('T-32 REJECTED/CANCELED 는 영구히 막지 않는다', () {
      expect(cf.contains('EXIT_CONFLICT_STATUSES = ["PENDING", "APPROVED", "AUTO_APPROVED", "REJECTED"'), isFalse);
    });

    test('T-33 퇴사 요청이 진행 중인 해지를 확인한다', () {
      final req = _after(cf, 'callableRequestResignation = onCall', 5000);
      expect(
        req.contains('EXIT_CONFLICT_STATUSES.includes(\n        (data.terminationStatus'),
        isTrue,
      );
    });

    test('T-34 해지 요청이 진행 중인 퇴사를 확인한다', () {
      final req = _after(cf, 'callableRequestTermination = onCall', 9200);
      expect(
        req.contains('EXIT_CONFLICT_STATUSES.includes(\n        (snap.data()?.resignStatus'),
        isTrue,
      );
    });

    test('T-35 §38 두 검증 모두 트랜잭션 fresh read 안에 있다', () {
      final rr = _after(cf, 'callableRequestResignation = onCall', 5000);
      final rt = _after(cf, 'callableRequestTermination = onCall', 9200);
      final rrTx = rr.indexOf('runTransaction');
      final rtTx = rt.indexOf('runTransaction');
      expect(rrTx >= 0 && rr.indexOf('EXIT_CONFLICT_STATUSES') > rrTx, isTrue);
      expect(rtTx >= 0 && rt.indexOf('EXIT_CONFLICT_STATUSES') > rtTx, isTrue);
    });

    test('T-36 §40 renewal 쪽 approvedExitStatuses guard 는 그대로다 (회귀)', () {
      expect(
        cf.contains('const approvedExitStatuses = ["APPROVED", "AUTO_APPROVED"]'),
        isTrue,
      );
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§21/§22 승인과 효력을 가르는 predicate', () {
    test('T-37 isTerminationApproved 는 이름 그대로 승인 여부다', () {
      final app = _app(
        terminationStatus: AppStatus.approved,
        actualResignDate: DateTime.now().add(const Duration(days: 5)),
      );
      // 승인됐다 — status 가 아직 살아 있어도 참이어야 한다.
      expect(app.isTerminationApproved, isTrue);
    });

    test('T-38 승인 + 미래 D → 아직 효력 아님', () {
      final app = _app(
        terminationStatus: AppStatus.approved,
        actualResignDate: DateTime.now().add(const Duration(days: 5)),
      );
      expect(app.isExitEffectiveNow, isFalse);
    });

    test('T-39 §50 D 당일은 여전히 근무 관계', () {
      final d = DateTime.now();
      final app = _app(terminationStatus: AppStatus.approved, actualResignDate: d);
      expect(app.isExitEffectiveOn(d), isFalse);
    });

    test('T-40 §51 D+1 부터 효력', () {
      final d = DateTime.now();
      final app = _app(terminationStatus: AppStatus.approved, actualResignDate: d);
      expect(app.isExitEffectiveOn(d.add(const Duration(days: 1))), isTrue);
    });

    test('T-41 D-1 은 당연히 근무 관계', () {
      final d = DateTime.now().add(const Duration(days: 3));
      final app = _app(terminationStatus: AppStatus.approved, actualResignDate: d);
      expect(app.isExitEffectiveOn(DateTime.now()), isFalse);
    });

    test('T-42 퇴사 경로도 같은 규칙 (회귀)', () {
      final d = DateTime.now();
      final app = _app(resignStatus: AppStatus.autoApproved, actualResignDate: d);
      expect(app.isExitEffectiveOn(d), isFalse);
      expect(app.isExitEffectiveOn(d.add(const Duration(days: 1))), isTrue);
    });

    test('T-43 결정이 없으면 효력도 없다', () {
      final app = _app(actualResignDate: _d(2020, 1, 1));
      expect(app.isExitEffectiveOn(DateTime.now()), isFalse);
    });

    test('T-44 종료일을 모르면 끝났다고 단정하지 않는다 — UNKNOWN ≠ ENDED', () {
      final app = ApplicationModel(
        id: 'a', businessId: 'b', businessName: 'n', toTitle: 't',
        workDate: _d(2026, 9, 1), workEndDate: null,
        workDays: const ['월'], startTime: '09:00', endTime: '18:00',
        uid: 'u', selectedWorkType: '사무업무', wage: 1, wageType: 'hourly',
        status: AppStatus.confirmed, appliedAt: _d(2026, 8, 1),
        terminationStatus: AppStatus.approved,
      );
      expect(app.isExitEffectiveNow, isFalse);
    });

    test('T-45 §16 KST 자정 경계 — D 23:59 와 D+1 00:00', () {
      final d = _d(2026, 10, 10);
      final app = _app(terminationStatus: AppStatus.approved, actualResignDate: d);
      expect(app.isExitEffectiveOn(DateTime(2026, 10, 10, 0, 0)), isFalse);
      expect(app.isExitEffectiveOn(DateTime(2026, 10, 10, 23, 59)), isFalse);
      expect(app.isExitEffectiveOn(DateTime(2026, 10, 11, 0, 0)), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§23/§24 운영 화면은 승인이 아니라 효력을 본다', () {
    test('T-46 Calendar 가 효력 기준으로 바뀌었다', () {
      final cal = _codeOf(_src('lib/utils/calendar_helper.dart'));
      expect(cal.contains('app.isLongTermApplication && app.isExitEffectiveNow'), isTrue);
      expect(cal.contains('app.isLongTermApplication && app.isTerminationApproved'), isFalse);
    });

    test('T-47 FixedWorker 가 효력 기준으로 바뀌었다', () {
      final fw = _codeOf(_src(
          'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart'));
      expect(fw.contains('app.isExitEffectiveOn(exitAsOf)'), isTrue);
    });

    test('T-48 FixedWorker 가 날짜 모드에서는 그 날짜로 판정한다', () {
      final fw = _codeOf(_src(
          'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart'));
      expect(fw.contains('_isDateMode ? widget.focusDate! : DateTime.now()'), isTrue);
    });

    test('T-49 §40 연장 판정은 승인 기준 그대로 (회귀)', () {
      final rds = _codeOf(_src('lib/utils/renewal_decision_state.dart'));
      expect(rds.contains('app.isTerminationApproved'), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§29–35 근로자 홈 계약해지 Task', () {
    test('T-50 §34 PENDING 만 센다', () {
      final s = PendingTerminationSurface.from(
        [_app(terminationStatus: AppStatus.pending)],
        available: true,
      );
      expect(s.isVisible, isTrue);
      expect(s.count, 1);
    });

    test('T-51 §34 APPROVED/AUTO_APPROVED/REJECTED/CANCELED 는 빠진다', () {
      for (final st in [
        AppStatus.approved,
        AppStatus.autoApproved,
        AppStatus.rejected,
        AppStatus.canceled,
      ]) {
        final s = PendingTerminationSurface.from(
          [_app(terminationStatus: st)],
          available: true,
        );
        expect(s.isVisible, isFalse, reason: st);
      }
    });

    test('T-52 §35 조회 실패는 0건이 아니다 — ERROR ≠ EMPTY', () {
      final s = PendingTerminationSurface.from([], available: false);
      expect(s.isVisible, isFalse);
      expect(s.isUnavailable, isTrue);
      expect(PendingTerminationSurface.none.isUnavailable, isFalse);
    });

    test('T-53 여러 건이면 건수로 말한다', () {
      final s = PendingTerminationSurface.from([
        _app(id: 'a', terminationStatus: AppStatus.pending),
        _app(id: 'b', terminationStatus: AppStatus.pending),
      ], available: true);
      expect(s.count, 2);
      expect(s.title.contains('2건'), isTrue);
      expect(s.applicationId, isNull);
    });

    test('T-54 §32 1건이면 그 지원서를 가리킨다', () {
      final s = PendingTerminationSurface.from(
        [_app(id: 'appX', terminationStatus: AppStatus.pending)],
        available: true,
      );
      expect(s.applicationId, 'appX');
      expect(s.title.contains('위워커'), isTrue);
    });

    test('T-55 §30 신분증 요청 표면과 합치지 않았다', () {
      final home = _codeOf(_src('lib/screens/user/user_home_screen.dart'));
      // 두 표면이 각각 자기 카드를 갖는다.
      expect(home.contains('_buildIdRequestCard(context, s, up)'), isTrue);
      expect(home.contains('_buildTerminationRequestCard(context, s, up)'), isTrue);
      // ID 표면에 해지 건수를 더하지 않았다.
      expect(home.contains('_idRequestSurface.count +'), isFalse);
    });

    test('T-56 §33 알림이 아니라 도메인 상태에서 파생된다', () {
      final surf = _codeOf(_src('lib/models/ui/pending_termination_surface.dart'));
      expect(surf.contains('a.terminationStatus == AppStatus.pending'), isTrue);
      expect(surf.contains('notification'), isFalse);
      final home = _codeOf(_src('lib/screens/user/user_home_screen.dart'));
      expect(
        home.contains('PendingTerminationSurface.from(\n      _applications,'),
        isTrue,
      );
    });

    test('T-57 §35 홈이 실패를 별도 상태로 렌더한다', () {
      final home = _codeOf(_src('lib/screens/user/user_home_screen.dart'));
      expect(home.contains('surface.isUnavailable'), isTrue);
      expect(home.contains('available: !_homeLoadFailed'), isTrue);
    });

    test('T-58 §32 기존 응답 화면으로 간다 — 새 화면을 만들지 않았다', () {
      final home = _codeOf(_src('lib/screens/user/user_home_screen.dart'));
      final card = _after(home, 'Widget _buildTerminationRequestCard', 4200);
      expect(card.contains('_openMyRequests(uid)'), isTrue);
    });
  });

  // ════════════════════════════════════════════════════════════════
  group('§44–45 NO-PATCH 회귀 — 이번 변경이 건드리지 않은 것', () {
    test('T-59 급여 미지급 집계는 attendance 기반 그대로', () {
      final unpaid = _after(cf, 'async function srvHomeUnpaidWage', 900);
      expect(unpaid.contains('.where("wageStatus", "==", "confirmed")'), isTrue);
      expect(unpaid.contains('Application'), isFalse);
    });

    test('T-60 이체 writer 는 Application status 를 게이트로 쓰지 않는다', () {
      final xfer = _after(cf, 'callableMarkTransferredBatch = onCall', 4000);
      expect(xfer.contains('"CANCELED"'), isFalse);
    });

    test('T-61 §26 근무일 resolver 는 그대로 — terminationEffectiveDate 를 읽지 않는다', () {
      final res = _after(cf, 'function srvLongTermEligibleOnDay', 1800);
      expect(res.contains('terminationEffectiveDate'), isFalse);
      expect(res.contains('terminationStatus'), isFalse);
    });

    test('T-62 §44 리뷰 요청 population 은 손대지 않았다', () {
      expect(
        cf.contains('.where("status", "in", CONFIRMED_STATUSES)'),
        isTrue,
      );
    });

    test('T-63 §43 C04 주석이 실제 계약을 설명한다', () {
      final raw = _src(_cfPath);
      expect(raw.contains('operational effective end = actualResignDate ?? workEndDate'),
          isTrue);
      expect(raw.contains('[C04 설계 의도]'), isFalse);
    });
  });
}
