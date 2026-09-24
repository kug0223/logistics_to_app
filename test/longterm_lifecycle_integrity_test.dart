// [PRELAUNCH-LONGTERM-LIFECYCLE-INTEGRITY] 장기 근무일 resolver · 출퇴근 시각 권위.
//
// 장기(CONTRACT)에는 날짜별 slot이 없다. 실제 근무일은
//
//     rangeStart · rangeEnd · workDays · leaveDates · extraWorkDates
//     + actualResignDate(효력일)
//
// 에서 **파생**된다. 그래서 "이 날짜에 근무하는가"를 묻는 곳이 많고,
// 그 답이 한 곳에서만 나와야 한다. 이 테스트는 canonical 규칙과
// 서버 시각 권위를 코드로 고정한다.
//
// 출퇴근 시각의 권위는 기기가 아니다:
//
//     GPS 좌표          → 장소 주장
//     기기 시계/타임존  → 권위 아님
//     서버 시각          → raw punch 권위 (originalCheckIn/Out)
//     workDateMs        → 대상 business-date 입력 (서버가 재검증)
//     KST 변환           → business-day 권위

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';

const _cfPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 주석 줄을 지운 본문. 마커는 주석이 아니라 **코드**여야 한다.
String _codeOf(String s) =>
    s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// [name] 선언 이후 [chars]자.
String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  if (i < 0) throw StateError('$name 를 찾지 못함');
  return src.substring(i, (i + chars).clamp(0, src.length));
}

DateTime _d(int y, int m, int d) => DateTime(y, m, d);

/// 장기 확정 지원서 하나. 날짜 규칙 외의 필드는 의미가 없다.
ApplicationModel _app({
  DateTime? workDate,
  DateTime? workEndDate,
  List<String>? workDays,
  DateTime? desiredStartDate,
  DateTime? actualResignDate,
  List<DateTime>? leaveDates,
  List<DateTime>? extraWorkDates,
  DateTime? confirmedAt,
  String status = AppStatus.confirmed,
}) =>
    ApplicationModel(
      id: 'app1',
      businessId: 'biz1',
      businessName: '테스트 사업장',
      toTitle: '[테스트] 장기 근무',
      workDate: workDate ?? _d(2026, 9, 1),
      workEndDate: workEndDate ?? _d(2026, 9, 30),
      workDays: workDays ?? const ['월', '화', '수', '목', '금'],
      startTime: '09:00',
      endTime: '18:00',
      uid: 'worker1',
      selectedWorkType: '사무업무',
      wage: 12000,
      wageType: 'hourly',
      status: status,
      appliedAt: _d(2026, 8, 25),
      confirmedAt: confirmedAt,
      desiredStartDate: desiredStartDate,
      actualResignDate: actualResignDate,
      leaveDates: leaveDates,
      extraWorkDates: extraWorkDates,
    );

void main() {
  final cf = _codeOf(_src(_cfPath));

  // ══════════════════════════════════════════════════════════════
  // 01. 근무일 resolver — 경계
  //
  //   2026-09-01(화) ~ 2026-09-30(수), 평일 근무.
  // ══════════════════════════════════════════════════════════════
  group('01. 장기 근무일 경계', () {
    test('01-a rangeStart 당일은 근무일이다', () {
      expect(_app().isWorkingOnDate(_d(2026, 9, 1)), true);
    });

    test('01-b rangeStart 이전은 근무일이 아니다', () {
      // 8/31은 월요일 — 요일만 보면 근무일이지만 기간 밖이다.
      expect(_d(2026, 8, 31).weekday, DateTime.monday);
      expect(_app().isWorkingOnDate(_d(2026, 8, 31)), false);
    });

    test('01-c rangeEnd 당일은 근무일이다', () {
      expect(_app().isWorkingOnDate(_d(2026, 9, 30)), true);
    });

    test('01-d rangeEnd 이후는 근무일이 아니다', () {
      // 10/1은 목요일 — 요일이 맞아도 계약이 끝났다.
      expect(_d(2026, 10, 1).weekday, DateTime.thursday);
      expect(_app().isWorkingOnDate(_d(2026, 10, 1)), false);
    });

    test('01-e 기간 안이어도 비근무요일이면 근무일이 아니다', () {
      // 9/5 토요일
      expect(_app().isWorkingOnDate(_d(2026, 9, 5)), false);
    });

    test('01-f workEndDate 없는 계약은 근무일을 만들지 않는다', () {
      // "기간 미정"은 전 시스템에서 일관되게 false다 — 무기한이 아니다.
      final open = ApplicationModel(
        id: 'a', businessId: 'b', businessName: 'n', toTitle: 't',
        workDate: _d(2026, 9, 1), workDays: const ['월', '화', '수', '목', '금'],
        startTime: '09:00', endTime: '18:00', uid: 'u',
        selectedWorkType: '사무업무', wage: 12000,
        status: AppStatus.confirmed, appliedAt: _d(2026, 8, 25),
      );
      expect(open.isWorkingOnDate(_d(2026, 9, 2)), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. 효력 시작·종료 — desiredStartDate / actualResignDate
  // ══════════════════════════════════════════════════════════════
  group('02. 효력 경계', () {
    test('02-a desiredStartDate가 있으면 그것이 시작이다', () {
      final a = _app(desiredStartDate: _d(2026, 9, 10));
      expect(a.isWorkingOnDate(_d(2026, 9, 9)), false);
      expect(a.isWorkingOnDate(_d(2026, 9, 10)), true);
    });

    test('02-b desiredStartDate가 없으면 workDate가 시작이다', () {
      // 서버 checkIn 게이트가 desiredStartDate만 보는 것과 대비되는 canonical 규칙.
      expect(_app().desiredStartDate, isNull);
      expect(_app().isWorkingOnDate(_d(2026, 8, 31)), false);
      expect(_app().isWorkingOnDate(_d(2026, 9, 1)), true);
    });

    test('02-c 퇴사 효력일 당일까지만 근무한다', () {
      // checkIn 서버 게이트는 `resignDate <= workDate` 를 막는다 —
      // 즉 효력일 당일은 이미 근무하지 않는다.
      final a = _app(actualResignDate: _d(2026, 9, 15));
      expect(a.isWorkingOnDate(_d(2026, 9, 14)), true);
      expect(a.isWorkingOnDate(_d(2026, 9, 16)), false);
    });

    test('02-d 퇴사 효력일이 rangeEnd보다 앞서면 그쪽이 이긴다', () {
      final a = _app(actualResignDate: _d(2026, 9, 15));
      expect(a.isWorkingOnDate(_d(2026, 9, 21)), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. leaveDates / extraWorkDates — 우선순위
  // ══════════════════════════════════════════════════════════════
  group('03. 휴무·추가근무', () {
    test('03-a 정상 근무일을 휴무로 지정하면 근무가 사라진다', () {
      final a = _app(leaveDates: [_d(2026, 9, 2)]);
      expect(_app().isWorkingOnDate(_d(2026, 9, 2)), true);
      expect(a.isWorkingOnDate(_d(2026, 9, 2)), false);
    });

    test('03-b 비근무요일이어도 추가근무일이면 근무한다', () {
      final a = _app(extraWorkDates: [_d(2026, 9, 5)]);
      expect(_app().isWorkingOnDate(_d(2026, 9, 5)), false);
      expect(a.isWorkingOnDate(_d(2026, 9, 5)), true);
    });

    test('03-c 추가근무가 휴무보다 먼저 판정된다', () {
      // 서버 approve가 두 배열의 교집합을 지우지만, reader도 같은
      // 우선순위를 갖는다 — dual-state가 남아도 판정이 갈리지 않는다.
      final a = _app(
        leaveDates: [_d(2026, 9, 5)],
        extraWorkDates: [_d(2026, 9, 5)],
      );
      expect(a.isWorkingOnDate(_d(2026, 9, 5)), true);
    });

    test('03-d 추가근무도 계약 기간 밖으로는 나가지 못한다', () {
      final a = _app(extraWorkDates: [_d(2026, 10, 3)]);
      expect(a.isWorkingOnDate(_d(2026, 10, 3)), false);
    });

    test('03-e 서버 approve가 leave/extra 교집합을 만들지 않는다', () {
      final seg = _after(cf, 'if (requestType === "LEAVE" || requestType === "NO_WORK")', 700);
      // LEAVE 승인은 extraWorkDates에서 같은 날짜를 지운다.
      expect(seg.contains('parseDates("extraWorkDates").filter((ts) => !sameDay(ts))'), true);
      // EXTRA_WORK 승인은 대칭으로 leaveDates에서 지운다.
      expect(seg.contains('parseDates("leaveDates").filter((ts) => !sameDay(ts))'), true);
    });

    test('03-f 이미 출근한 날짜는 휴무로 바꾸지 못한다', () {
      // 역사 삭제 금지 — 승인 트랜잭션 안에서 attendance를 읽고 막는다.
      final seg = _after(
          cf, 'if (requestTypeEarly === "LEAVE" || requestTypeEarly === "NO_WORK")', 900);
      expect(seg.contains('attSnap.exists && attSnap.data()?.checkIn != null'), true);
      expect(seg.contains('이미 출근한 날짜는'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. 출퇴근 시각 권위 — 기기가 아니라 서버다
  // ══════════════════════════════════════════════════════════════
  group('04. time authority', () {
    test('04-a raw punch는 서버 시각이다', () {
      final ci = _after(cf, 'export const callableCheckIn', 25000);
      // 트랜잭션 안에서 서버 시각을 얻고, 그것을 originalCheckIn으로 쓴다.
      expect(ci.contains('const now = new Date();'), true);
      expect(
        ci.contains(
            'originalCheckIn: admin.firestore.Timestamp.fromDate(now)'),
        true,
      );
    });

    test('04-b 클라이언트가 출근 시각을 보내지 않는다', () {
      // request.data에서 꺼내는 이름에 checkIn 시각이 없다.
      final params = _after(cf, 'export const callableCheckIn', 1200);
      for (final banned in ['checkInMs', 'checkInAt', 'nowMs', 'clientNow']) {
        expect(params.contains(banned), false, reason: banned);
      }
    });

    test('04-c checkOut의 raw punch도 서버 시각이고 불변이다', () {
      final co = _after(cf, 'export const callableCheckOut', 9000);
      expect(co.contains('const now = new Date();'), true);
      expect(co.contains('if (data.originalCheckOut == null)'), true,
          reason: 'originalCheckOut은 최초 1회만 기록된다');
      expect(
        co.contains(
            'update.originalCheckOut = admin.firestore.Timestamp.fromDate(now)'),
        true,
      );
    });

    test('04-d effective 시각은 서버 attendanceRules로만 만든다', () {
      final ci = _after(cf, 'export const callableCheckIn', 25000);
      // 클라이언트 rules fallback이 없다.
      expect(ci.contains('bizSnap.data()?.attendanceRules'), true);
      expect(ci.contains('_clampAttendanceRules(serverRules)'), true);
      expect(ci.contains('request.data.attendanceRules'), false);
    });

    test('04-e original과 effective를 같은 필드에 쓰지 않는다', () {
      final ci = _after(cf, 'export const callableCheckIn', 25000);
      expect(
        ci.contains('checkIn: admin.firestore.Timestamp.fromDate(effectiveCheckIn)'),
        true,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 05. business date — KST 권위
  // ══════════════════════════════════════════════════════════════
  group('05. KST business-date', () {
    test('05-a attendance 문서 식별자에 날짜가 들어간다', () {
      // 같은 Application이 여러 근무일을 가지므로 날짜가 빠지면
      // 하루치 근태가 계약 전체를 덮어쓴다.
      final ci = _after(cf, 'export const callableCheckIn', 25000);
      expect(ci.contains(r'const docId = `${applicationId}_${dateStr}`;'), true);
    });

    test('05-b 날짜 문자열은 KST에서 만든다', () {
      final ci = _after(cf, 'export const callableCheckIn', 25000);
      expect(ci.contains('const KST_OFFSET_MS = 9 * 60 * 60 * 1000;'), true);
      expect(
        ci.contains('const workDateKST = new Date(workDateMs + KST_OFFSET_MS);'),
        true,
      );
      // getUTC*()로 KST 구성요소를 읽는다 — 서버 로컬 타임존에 의존하지 않는다.
      expect(ci.contains('workDateKST.getUTCFullYear()'), true);
    });

    test('05-c 중복 출근은 거절된다', () {
      final ci = _after(cf, 'export const callableCheckIn', 25000);
      expect(ci.contains('if (snap.exists) throw new HttpsError("already-exists"'),
          true);
    });

    test('05-d 야간교대 퇴근은 다음 날 Application으로 갈라지지 않는다', () {
      // 같은 attendance 문서를 수정하고, 계약 종료시각만 +24h 한다.
      final co = _after(cf, 'export const callableCheckOut', 9000);
      expect(co.contains('if (cEndMs < cStartMs) cEndMs += 24 * 60 * 60 * 1000;'),
          true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 06. workDateMs는 신뢰 입력이 아니라 대상 지정이다
  // ══════════════════════════════════════════════════════════════
  group('06. workDateMs 재검증', () {
    test('06-a 단기는 지원서 날짜와 일치해야 한다', () {
      final ci = _after(cf, 'export const callableCheckIn', 25000);
      expect(ci.contains('지원서에 지정된 날짜에만 출근할 수 있습니다.'), true);
    });

    test('06-b 장기 날짜 판정은 공용 resolver가 한다', () {
      // [LONGTERM-DATE-ELIGIBILITY] 요일·추가근무·휴무·시작·종료를 각각
      //   보던 if문 더미를 걷어냈다. 경계 자체는
      //   longterm_date_eligibility_test 가 A~R로 고정한다.
      final ci = _after(cf, 'export const callableCheckIn', 25000);
      expect(ci.contains('srvLongTermEligibleOnDay('), true);
      expect(ci.contains('srvWorkerDayMessage('), true);
    });

    test('06-c 휴무일 출근은 거절된다', () {
      // 문구는 그대로 유지한다 — 장기는 resolver가, 단기는 각 경로가 본다.
      expect(cf.contains('휴무일에는 출근할 수 없습니다.'), true);
    });

    test('06-d 퇴사 효력일 **이후** 출근이 거절된다', () {
      // 효력일 D는 마지막 근무 가능일이다. `>=`로 막으면 하루가 지워진다.
      expect(cf.contains('퇴직 이후 출근할 수 없습니다.'), true);
      expect(cf.contains('if (resignDateKSTDay <= workDateKSTDay)'), false);
      final ci = _after(cf, 'export const callableCheckIn', 25000);
      expect(
        ci.contains('shortResign && ciDayNum > srvKstDateNum(shortResign.toDate())'),
        true,
        reason: '단기 경로도 같은 경계를 쓴다',
      );
    });

    test('06-e 관리자 배치 경로도 같은 재검증을 쓴다', () {
      // 배치 출근/노쇼가 개별 출근보다 느슨하면 그쪽이 우회로가 된다.
      final r = _after(cf, 'async function _resolveAttendanceWorkContext(', 6000);
      expect(r.contains('srvLongTermEligibleOnDay('), true);
      expect(r.contains('_fail("wrong_date_flex")'), true);
      expect(r.contains('LEAVE: "leave_date"'), true);
      expect(r.contains('NON_WORKDAY: "not_work_day"'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 07. 약속 snapshot — Posting 수정이 과거를 다시 쓰지 않는다
  // ══════════════════════════════════════════════════════════════
  group('07. promise snapshot', () {
    test('07-a 계약 기간 변경은 활성 지원자가 있으면 거절된다', () {
      final u = _after(cf, 'export const callableUpdateTO', 30000);
      expect(u.contains('활성 지원자가 있는 공고의 계약 기간을 변경할 수 없습니다.'), true);
    });

    test('07-b 그 판정이 트랜잭션 안에서 이뤄진다', () {
      // 트랜잭션 밖 read는 재시도해도 다시 실행되지 않는다 —
      // "조회 → (지원 발생) → commit" 순서가 그대로 성립한다.
      final u = _after(cf, 'export const callableUpdateTO', 30000);
      final guardIdx = u.indexOf('const dateActiveSnapshots');
      expect(guardIdx, greaterThan(-1));
      final seg = u.substring(guardIdx, guardIdx + 700);
      expect(seg.contains('txEdit.get('), true,
          reason: 'tx.get(Query) 결과가 read-set에 들어가야 재시도가 보장된다');
    });

    test('07-c 지원도 트랜잭션 안에서 공고의 신선한 기간을 읽는다', () {
      final a = _after(cf, 'export const callableApplyToTO', 45000);
      expect(a.contains('if (freshRs) effectiveContractWorkDate = freshRs;'), true);
      expect(a.contains('if (freshRe) effectiveContractWorkEndDate = freshRe;'),
          true);
    });

    test('07-d 계약서 임금은 공고가 아니라 약속에서 온다', () {
      final svc = _codeOf(_src('lib/services/contract_service.dart'));
      expect(svc.contains('WorkDetailData _withPromisedWage('), true);
      expect(svc.contains('final promisedWage = application.wage;'), true);
      // 약속 임금이 없으면 현재 모집 임금으로 덮지 않고 던진다.
      expect(svc.contains('지원 시점 임금 정보가 없어 계약서를 만들 수 없습니다.'), true);
    });

    test('07-e 장기 계약서 snapshot이 기간·요일을 담는다', () {
      final svc = _codeOf(_src('lib/services/contract_service.dart'));
      final seg = _after(svc, 'ContractSnapshot _buildSnapshot(', 2500);
      expect(seg.contains('contractStart: isLong'), true);
      expect(seg.contains('contractEnd: isLong && application.workEndDate != null'),
          true);
      expect(seg.contains('workDays: application.workDays'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 08. 계약 연장 — 과거를 덮어쓰지 않는다
  // ══════════════════════════════════════════════════════════════
  group('08. 계약 연장', () {
    test('08-a 연장은 기존 계약 수정이 아니라 새 Application 생성이다', () {
      final r = _after(cf, 'export const callableAcceptRenewalProposal', 9500);
      expect(r.contains('const newRef = db.collection("applications").doc();'),
          true);
      expect(r.contains('renewedFromApplicationId: originalApplicationId'), true);
      expect(r.contains('tx.set(newRef, newData);'), true);
    });

    test('08-b 원본은 기간이 바뀌지 않고 역참조만 남는다', () {
      final r = _after(cf, 'export const callableAcceptRenewalProposal', 9500);
      final i = r.indexOf('tx.update(originalRef, {');
      expect(i, greaterThan(-1));
      final seg = r.substring(i, i + 300);
      expect(seg.contains('renewalDecision: "EXTEND"'), true);
      expect(seg.contains('renewedToApplicationId: newApplicationId'), true);
      // 원본의 기간을 다시 쓰지 않는다.
      expect(seg.contains('workEndDate'), false);
      expect(seg.contains('workDate'), false);
    });

    test('08-c 연장 시작일은 원본 종료일 **다음 날**부터다', () {
      // workEndDate 는 inclusive 다. 예전 가드는 `newStart < oldEnd` 만
      // 막아서 같은 날짜가 통과했고, 그 하루가 원본과 갱신 양쪽의
      // 근무일이 됐다(DEV 실측: 그 날 좌석 2건).
      //   경계 자체는 longterm_renewal_boundary_test 가 고정한다.
      final r = _after(cf, 'export const callableAcceptRenewalProposal', 9500);
      expect(r.contains('갱신 계약 시작일은 원본 계약 종료일 다음 날부터여야 합니다.'), true);
      expect(r.contains('if (newStartNum <= originalEndNum) {'), true);
    });

    test('08-d 새 계약은 임금 집계와 휴무·추가근무를 물려받지 않는다', () {
      final r = _after(cf, 'export const callableAcceptRenewalProposal', 9500);
      for (final f in [
        'wageStatus: "pending"',
        'finalWage: null',
        'leaveDates: []',
        'extraWorkDates: []',
        'actualResignDate: null',
      ]) {
        expect(r.contains(f), true, reason: f);
      }
    });

    test('08-e 운영 목록이 구 계약과 새 계약을 같이 세지 않는다', () {
      final d = _codeOf(
          _src('lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart'));
      // 일반 목록에서는 EXTEND(구 계약)를 제외한다.
      expect(d.contains('if (app.renewalDecision == AppStatus.renewalExtend)'),
          true);
      // 날짜 모드에서는 구 계약이 그 날짜를 덮을 때만 포함하고,
      // 그 경우 같은 uid의 새 계약을 숨긴다.
      expect(d.contains('uidsWithActiveLegacy'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 09. 종료·해지 — 승인이 곧 소멸은 아니다
  // ══════════════════════════════════════════════════════════════
  group('09. 종료/해지', () {
    test('09-a 퇴사 자동승인은 결정만 기록한다', () {
      // 승인 순간 status를 바꾸면 효력일 전 근무자가 화면에서 사라진다.
      final seg = _after(cf, 'resignStatus: "AUTO_APPROVED"', 400);
      expect(seg.contains('actualResignDate: Timestamp.fromDate(actualResignDate)'),
          true);
      expect(seg.contains('status: "CANCELED"'), false,
          reason: '효력일 전에 status를 바꾸면 안 된다');
    });

    test('09-b 마감된 공고가 기존 지원서를 건드리지 않는다', () {
      // FULL/CLOSED는 모집 상태다 — 이미 선 약속을 끝내지 않는다.
      final c = _after(cf, 'export const callableCloseTOManually', 4000);
      expect(c.contains('isManualClosed: true'), true);
      expect(c.contains('status: "CLOSED"'), true);
      // applications를 건드리는 write가 이 callable 안에 없다.
      expect(c.contains('collection("applications")'), false);
      expect(c.contains('AUTO_CANCELED'), false);
    });

    test('09-c 퇴사 소급 입력은 제한된다', () {
      expect(cf.contains('퇴사일은 30일 이전으로 소급할 수 없습니다.'), true);
    });

    test('09-d 퇴사 승인된 근무자는 연장되지 않는다', () {
      final r = _after(cf, 'export const callableAcceptRenewalProposal', 9500);
      expect(r.contains('퇴사가 승인된 근무자의 계약은 연장할 수 없습니다.'), true);
      expect(r.contains('계약 해지가 승인된 근무자의 계약은 연장할 수 없습니다.'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 10. 자동 NO_SHOW — 같은 날짜 규칙을 쓴다
  // ══════════════════════════════════════════════════════════════
  group('10. NO_SHOW eligibility', () {
    // 장기 자동 노쇼 블록의 코드 앵커(주석이 아니다).
    const noShowAnchor =
        '.where("workEndDate", ">=", Timestamp.fromDate(yesterdayStartUTC))';

    test('10-a 결근은 근무일에만 성립한다 — 공용 resolver가 판정한다', () {
      final seg = _after(cf, noShowAnchor, 1400);
      expect(seg.contains('srvLongTermEligibleOnDay('), true);
      expect(seg.contains(').eligible) continue;'), true);
    });

    test('10-b 사본이 남아 있지 않다', () {
      // 이 블록은 시작일을 desiredStartDate로만 보고 퇴사 효력일을 몰랐다.
      final seg = _after(cf, noShowAnchor, 1400);
      expect(seg.contains('if (!isRegularDay && !isExtraDay) continue;'), false);
      expect(seg.contains('const isRegularDay'), false);
      expect(
        seg.contains(
            'if (!startTs || startTs.toMillis() > yesterdayStartUTC.getTime()) continue;'),
        false,
      );
    });

    test('10-c 노쇼 기록도 목록에서 사라지지 않게 createdAt을 쓴다', () {
      final seg = _after(cf, noShowAnchor, 2400);
      expect(seg.contains('createdAt: admin.firestore.FieldValue.serverTimestamp()'),
          true);
    });
  });
}
