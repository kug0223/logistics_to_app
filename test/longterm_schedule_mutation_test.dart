// [PRELAUNCH-LONGTERM-LIFECYCLE-INTEGRITY.3]
// 장기 근로자의 일정 예외 — 휴무 · 추가근무 · 상호전환 · 취소.
//
// 장기에는 날짜별 slot 이 없으므로, 하루를 빼거나 더하는 일은 슬롯을
// 지우고 만드는 것이 아니라 Application 의 두 배열을 바꾸는 일이다.
//
//     NO_WORK   승인 → leaveDates += D,  extraWorkDates -= D
//     EXTRA_WORK 승인 → extraWorkDates += D, leaveDates -= D
//
// 두 배열에 같은 날짜가 동시에 들어가면 소비자마다 다른 답을 낸다.
// 그래서 승인 writer 가 상호 배제를 **한 트랜잭션 안에서** 해야 한다.
//
// 그리고 PENDING 은 사실이 아니다 — 승인만이 일정을 바꾼다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';

const _cfPath = 'functions/src/index.ts';
const _fixedWorkerPath =
    'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart';

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

/// 2026-09-21 ~ 2026-10-20, 평일 근무. DEV 런타임 fixture 와 같은 모양.
ApplicationModel _app({
  List<DateTime>? leaveDates,
  List<DateTime>? extraWorkDates,
  DateTime? confirmedAt,
}) =>
    ApplicationModel(
      id: 'app1',
      businessId: 'biz1',
      businessName: '위워커',
      toTitle: '[LTSCHED] 일정 예외',
      workDate: _d(2026, 9, 21),
      workEndDate: _d(2026, 10, 20),
      workDays: const ['월', '화', '수', '목', '금'],
      startTime: '01:00',
      endTime: '02:30',
      uid: 'worker1',
      selectedWorkType: '사무업무',
      wage: 14000,
      wageType: 'hourly',
      status: AppStatus.confirmed,
      appliedAt: _d(2026, 9, 20),
      confirmedAt: confirmedAt ?? _d(2026, 9, 21),
      leaveDates: leaveDates,
      extraWorkDates: extraWorkDates,
    );

void main() {
  final cf = _codeOf(_src(_cfPath));
  final approve =
      _after(cf, 'export const callableApproveScheduleChangeRequest', 9000);
  final create =
      _after(cf, 'export const callableCreateScheduleChangeRequest', 6000);
  final cancel =
      _after(cf, 'export const callableCancelScheduleChangeRequest', 7000);

  // R = 2026-09-24 (목) 정규 근무일 · E = 2026-09-26 (토) 비근무일
  final r = _d(2026, 9, 24);
  final e = _d(2026, 9, 26);

  // ══════════════════════════════════════════════════════════════
  // 01. 날짜 truth — 배열 상태별
  // ══════════════════════════════════════════════════════════════
  group('01. 배열 → 근무일 truth', () {
    test('01-a baseline — R 근무 · E 비근무', () {
      expect(r.weekday, DateTime.thursday);
      expect(e.weekday, DateTime.saturday);
      expect(_app().isWorkingOnDate(r), true);
      expect(_app().isWorkingOnDate(e), false);
    });

    test('01-b 정규일에 휴무가 들어가면 근무가 사라진다', () {
      expect(_app(leaveDates: [r]).isWorkingOnDate(r), false);
    });

    test('01-c 비근무일에 추가근무가 들어가면 근무가 생긴다', () {
      expect(_app(extraWorkDates: [e]).isWorkingOnDate(e), true);
    });

    test('01-d 휴무 → 추가근무 전환이면 다시 근무다', () {
      // 승인 writer 가 leaveDates 에서 R 을 빼 주는 것이 전제다.
      expect(_app(extraWorkDates: [r]).isWorkingOnDate(r), true);
    });

    test('01-e 취소로 배열이 비면 원래 truth 로 돌아온다', () {
      expect(_app().isWorkingOnDate(r), true);
      expect(_app().isWorkingOnDate(e), false);
    });

    test('01-f 일정 예외는 계약 기간을 넓히지 못한다', () {
      // 범위 밖 추가근무는 근무일이 되지 않는다(서버도 승인에서 막는다).
      final out = _d(2026, 10, 25);
      expect(_app(extraWorkDates: [out]).isWorkingOnDate(out), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. 승인 writer — 상호 배제
  // ══════════════════════════════════════════════════════════════
  group('02. cross-type 상호 배제', () {
    test('02-a NO_WORK 승인이 extraWorkDates 에서 같은 날짜를 뺀다', () {
      final seg = _after(
          approve, 'if (requestType === "LEAVE" || requestType === "NO_WORK")', 600);
      expect(seg.contains('parseDates("extraWorkDates").filter((ts) => !sameDay(ts))'),
          true);
      expect(seg.contains('tx.update(appRef, {leaveDates, extraWorkDates});'), true);
    });

    test('02-b EXTRA_WORK 승인이 leaveDates 에서 같은 날짜를 뺀다', () {
      final seg = _after(approve, 'else if (requestType === "EXTRA_WORK")', 600);
      expect(seg.contains('parseDates("leaveDates").filter((ts) => !sameDay(ts))'),
          true);
      expect(seg.contains('tx.update(appRef, {leaveDates, extraWorkDates});'), true);
    });

    test('02-c 두 배열을 한 번에 쓴다 — 중간 상태가 없다', () {
      // 따로 쓰면 그 사이를 읽은 소비자가 dual-state 를 본다.
      final writes = RegExp(r'tx\.update\(appRef, \{leaveDates, extraWorkDates\}\);')
          .allMatches(approve)
          .length;
      expect(writes, 2, reason: 'NO_WORK 와 EXTRA_WORK 각각 한 번씩');
    });

    test('02-d 요청 상태와 배열이 같은 트랜잭션이다', () {
      // 하나만 커밋되면 "승인됐는데 일정은 그대로" 가 된다.
      final txStart = approve.indexOf('await db.runTransaction(');
      final statusWrite = approve.indexOf('tx.update(requestRef, updateData);');
      final arrayWrite = approve.indexOf('tx.update(appRef, {leaveDates, extraWorkDates});');
      expect(txStart, greaterThan(-1));
      expect(txStart, lessThan(statusWrite));
      expect(txStart, lessThan(arrayWrite));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. PENDING 은 사실이 아니다
  // ══════════════════════════════════════════════════════════════
  group('03. PENDING ≠ schedule truth', () {
    test('03-a 생성은 요청 문서만 쓴다', () {
      // applications 를 건드리는 write 가 create 에 없다.
      expect(create.contains("tx.set(newRef, {"), true);
      expect(create.contains('status: "PENDING",'), true);
      expect(create.contains('leaveDates'), false);
      expect(create.contains('extraWorkDates'), false);
    });

    test('03-b 배열 변경은 APPROVED 분기 안에서만 일어난다', () {
      expect(approve.contains('if (action === "APPROVED" && appSnap && appRef) {'),
          true);
      final i = approve.indexOf('if (action === "APPROVED" && appSnap && appRef) {');
      final j = approve.indexOf('tx.update(appRef, {leaveDates, extraWorkDates});');
      expect(i, lessThan(j));
    });

    test('03-c 거절은 일정을 바꾸지 않는다', () {
      // REJECTED 분기가 쓰는 것은 사유뿐이다.
      final seg = _after(approve, 'if (action === "REJECTED" && rejectReason)', 200);
      expect(seg.contains('updateData.rejectReason = rejectReason;'), true);
      expect(seg.contains('leaveDates'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. 범위·역사 보호
  // ══════════════════════════════════════════════════════════════
  group('04. 범위와 역사', () {
    test('04-a 계약 시작 이전 날짜는 승인되지 않는다', () {
      expect(approve.contains('targetDate가 계약 시작일 이전입니다.'), true);
    });

    test('04-b 계약 종료 이후 날짜는 승인되지 않는다', () {
      expect(approve.contains('targetDate가 계약 종료일 이후입니다.'), true);
    });

    test('04-c 범위는 퇴사 효력일을 우선한다', () {
      final seg = _after(approve, 'const effectiveStart = (appDataPre.desiredStartDate', 400);
      expect(seg.contains('appDataPre.actualResignDate ?? appDataPre.workEndDate'),
          true);
    });

    test('04-d 시작일은 workDate fallback 을 갖는다', () {
      expect(
        approve.contains(
            'const effectiveStart = (appDataPre.desiredStartDate ?? appDataPre.workDate)'),
        true,
      );
    });

    test('04-e 이미 출근한 날짜는 휴무로 바꿀 수 없다', () {
      final seg = _after(
          approve, 'if (requestTypeEarly === "LEAVE" || requestTypeEarly === "NO_WORK")', 900);
      expect(seg.contains('attSnap.exists && attSnap.data()?.checkIn != null'), true);
      expect(seg.contains('이미 출근한 날짜는'), true);
    });

    test('04-f 그 검사가 쓰기보다 먼저다', () {
      final guard = approve.indexOf('attSnap.exists && attSnap.data()?.checkIn != null');
      final write = approve.indexOf('tx.update(requestRef, updateData);');
      expect(guard, greaterThan(-1));
      expect(guard, lessThan(write), reason: 'read-before-write');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 05. 취소 — 원래 truth 복귀
  // ══════════════════════════════════════════════════════════════
  group('05. 승인 취소', () {
    test('05-a NO_WORK 취소는 leaveDates 에서 뺀다', () {
      final seg = _after(cancel, 'if (requestType === "LEAVE" || requestType === "NO_WORK")', 400);
      expect(seg.contains('tx.update(appRef, {leaveDates: filtered});'), true);
    });

    test('05-b EXTRA_WORK 취소는 extraWorkDates 에서 뺀다', () {
      final seg = _after(cancel, 'else if (requestType === "EXTRA_WORK")', 400);
      expect(seg.contains('tx.update(appRef, {extraWorkDates: filtered});'), true);
    });

    test('05-c APPROVED 취소만 배열을 되돌린다', () {
      expect(cancel.contains('if (freshStatus === "APPROVED" && applicationId && targetDate)'),
          true);
    });

    test('05-d 근로자는 PENDING 만 취소할 수 있다', () {
      expect(cancel.contains('이미 처리된 요청은 취소할 수 없습니다.'), true);
      expect(cancel.contains('if (isRequester && !isAdmin)'), true);
    });

    test('05-e 관리자는 PENDING·APPROVED 만 취소할 수 있다', () {
      expect(
        cancel.contains('if (scrStatus !== "PENDING" && scrStatus !== "APPROVED")'),
        true,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 06. 중복·권한
  // ══════════════════════════════════════════════════════════════
  group('06. 중복과 권한', () {
    test('06-a 같은 날짜 PENDING 중복은 트랜잭션에서 막는다', () {
      expect(create.contains('.where("status", "==", "PENDING")'), true);
      final seg = _after(create, 'await db.runTransaction(async (tx) => {', 900);
      expect(seg.contains('const pendingSnap = await tx.get(pendingQuery);'), true,
          reason: 'TX read-set 에 들어가야 경합에서 하나만 남는다');
      expect(seg.contains('created = false;'), true);
    });

    test('06-b 활성 요청 타입은 EXTRA_WORK / NO_WORK 둘뿐이다', () {
      expect(
        create.contains(
            'if (requestType !== "EXTRA_WORK" && requestType !== "NO_WORK")'),
        true,
      );
    });

    test('06-c 클라이언트 UI 도 그 둘만 만든다', () {
      final d = _codeOf(_src(_fixedWorkerPath));
      expect(d.contains('requestType: RequestType.EXTRA_WORK'), true);
      expect(d.contains('requestType: RequestType.NO_WORK'), true);
      expect(d.contains('requestType: RequestType.LEAVE'), false);
      expect(d.contains('requestType: RequestType.CANCEL_LEAVE'), false);
    });

    test('06-d 생성·승인·취소 모두 canManageWorkers 다', () {
      for (final seg in [create, approve, cancel]) {
        expect(seg.contains('assertBizAdmin('), true);
        expect(seg.contains('canManageWorkers'), true);
        expect(seg.contains('근로자 관리 권한이 없습니다.'), true);
      }
    });

    test('06-e 요청자·사업장 식별자는 서버가 쓴다', () {
      expect(create.contains('requestedBy: "ADMIN",'), true);
      expect(create.contains('requestedByUid: callerUid,'), true);
      expect(approve.contains('respondedByUid: callerUid,'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 07. 좌석 — 휴무는 그날 자리를 놓는다
  // ══════════════════════════════════════════════════════════════
  group('07. staffing seat', () {
    // 좌석은 canonical worker-day resolver 하나가 정한다.
    int seat(ApplicationModel a, DateTime d) => a.isWorkingOnDate(d) ? 1 : 0;

    test('07-a 정규일 휴무 → 그날 좌석 0', () {
      expect(seat(_app(), r), 1);
      expect(seat(_app(leaveDates: [r]), r), 0);
    });

    test('07-b 추가근무 전환 → 좌석 복귀', () {
      expect(seat(_app(extraWorkDates: [r]), r), 1);
    });

    test('07-c 비근무일 추가근무는 그날에만 좌석을 만든다', () {
      final a = _app(extraWorkDates: [e]);
      expect(seat(a, e), 1);
      // 다음 주 같은 요일은 그대로 비근무일이다.
      expect(seat(a, _d(2026, 10, 3)), 0);
    });

    test('07-d 좌석 판정이 공용 resolver 를 쓴다', () {
      final seg = _after(cf, 'function srvContractConfirmedOnDay(', 700);
      expect(seg.contains('srvLongTermEligibleOnDay('), true);
    });

    test('07-e resolver 가 두 배열을 모두 본다', () {
      final res = _after(cf, 'function srvLongTermEligibleOnDay(', 2200);
      expect(res.contains('hasDay("extraWorkDates")'), true);
      expect(res.contains('hasDay("leaveDates")'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 08. 승인이 만들지 않는 것
  // ══════════════════════════════════════════════════════════════
  group('08. 부작용 없음', () {
    test('08-a 승인이 attendance 를 만들지 않는다', () {
      // 승인 TX 가 attendance 에 쓰는 곳이 없다 — 읽기만 한다.
      expect(approve.contains("tx.set(db.collection('attendance')"), false);
      expect(approve.contains('tx.set(db.collection("attendance")'), false);
      expect(approve.contains('const attSnap = await tx.get(attRef);'), true);
    });

    test('08-b 승인이 급여를 만들지 않는다', () {
      for (final banned in ['finalWage', 'wageDetail', 'wageStatus']) {
        expect(approve.contains(banned), false, reason: banned);
      }
    });

    test('08-c 요청의 wageAmount 는 급여 authority 가 아니다', () {
      // 생성 시 기록만 하고, 승인에서 읽지 않는다.
      expect(create.contains('wageAmount: wageAmount ?? null,'), true);
      expect(approve.contains('wageAmount'), false);
    });

    test('08-d 승인이 TO 정원을 건드리지 않는다', () {
      // 추가근무는 기존 근로자의 일정 예외지 새 모집 자리가 아니다.
      for (final banned in ['totalConfirmed', 'totalRequired', 'workDetailCounts']) {
        expect(approve.contains(banned), false, reason: banned);
      }
    });

    test('08-e 승인이 계약서를 건드리지 않는다', () {
      expect(approve.contains('employment_contracts'), false);
    });

    test('08-f 승인이 약속 필드를 건드리지 않는다', () {
      for (final banned in [
        'workEndDate:', 'workDays:', 'wage:', 'startTime:', 'selectedWorkType:',
      ]) {
        expect(approve.contains(banned), false, reason: banned);
      }
    });
  });
}
