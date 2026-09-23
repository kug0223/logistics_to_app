// [PRELAUNCH-LONGTERM-LIFECYCLE-INTEGRITY.4]
// 장기 계약 연장 — 기간 경계 · 역사 보존 · manual vs auto.
//
// `workEndDate` 는 inclusive 다. 종료일 D 는 **일하는 날**이다. 그러므로
// 연장은 D+1 부터여야 한다.
//
// 서버 가드는 이렇게 돼 있었다:
//
//     if (newStartDateMs < originalEndDate.toMillis()) throw …
//
// 주석과 오류 문구는 "종료일 **이후**"라고 말했지만 연산자는 같은 날짜를
// 통과시켰다. 그래서 D 가 원본과 갱신 양쪽의 근무일이 됐고, 실측에서 한
// 사람이 그 날 좌석을 둘 차지했다.
//
// 어긋난 것은 비교 연산자 하나였다.

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

/// OLD: 2026-09-21 ~ 2026-09-28(월), 평일 근무. DEV 런타임 fixture 와 같다.
ApplicationModel _old() => ApplicationModel(
      id: 'old1',
      businessId: 'biz1',
      businessName: '위워커',
      toTitle: '[LTRENEW] 계약 연장',
      workDate: _d(2026, 9, 21),
      workEndDate: _d(2026, 9, 28),
      workDays: const ['월', '화', '수', '목', '금'],
      startTime: '04:00',
      endTime: '05:00',
      uid: 'worker1',
      selectedWorkType: '사무업무',
      wage: 15500,
      wageType: 'hourly',
      status: AppStatus.confirmed,
      appliedAt: _d(2026, 9, 20),
      confirmedAt: _d(2026, 9, 21),
    );

/// NEW: 2026-09-29(화) ~ 2026-10-28.
ApplicationModel _new({DateTime? start}) => ApplicationModel(
      id: 'new1',
      businessId: 'biz1',
      businessName: '위워커',
      toTitle: '[LTRENEW] 계약 연장',
      workDate: start ?? _d(2026, 9, 29),
      workEndDate: _d(2026, 10, 28),
      workDays: const ['월', '화', '수', '목', '금'],
      startTime: '04:00',
      endTime: '05:00',
      uid: 'worker1',
      selectedWorkType: '사무업무',
      wage: 15500,
      wageType: 'hourly',
      status: AppStatus.confirmed,
      appliedAt: _d(2026, 9, 28),
      confirmedAt: start ?? _d(2026, 9, 29),
      renewedFromApplicationId: 'old1',
    );

void main() {
  final cf = _codeOf(_src(_cfPath));
  final renew =
      // 창이 넓으면 다음 함수(callableCloseTOManually)가 섞여 들어와
      // '연장이 공고를 건드리지 않는다' 같은 단언이 거짓으로 깨진다.
      // 실측 길이(주석 제외) 7,668자.
      _after(cf, 'export const callableCreateContractRenewal', 7668);

  final dMinus1 = _d(2026, 9, 25); // 금
  final d = _d(2026, 9, 28); // 월 — OLD 종료일
  final dPlus1 = _d(2026, 9, 29); // 화 — NEW 시작일
  final dPlus2 = _d(2026, 9, 30); // 수

  // ══════════════════════════════════════════════════════════════
  // 01. 기간 경계 — 같은 날짜가 둘에 속하지 않는다
  // ══════════════════════════════════════════════════════════════
  group('01. 기간 경계', () {
    test('01-a D 는 OLD 의 근무일이다 — workEndDate 는 inclusive', () {
      expect(d.weekday, DateTime.monday);
      expect(_old().isWorkingOnDate(d), true);
    });

    test('01-b D 는 NEW 의 근무일이 아니다', () {
      expect(_new().isWorkingOnDate(d), false);
    });

    test('01-c D+1 은 NEW 만의 근무일이다', () {
      expect(_old().isWorkingOnDate(dPlus1), false);
      expect(_new().isWorkingOnDate(dPlus1), true);
    });

    test('01-d 경계 네 날짜 모두 좌석이 정확히 하나씩이다', () {
      int seats(DateTime x) =>
          (_old().isWorkingOnDate(x) ? 1 : 0) + (_new().isWorkingOnDate(x) ? 1 : 0);
      expect(seats(dMinus1), 1);
      expect(seats(d), 1);
      expect(seats(dPlus1), 1);
      expect(seats(dPlus2), 1);
    });

    test('01-e NEW 가 D 부터 시작하면 그 날 좌석이 둘이 된다 — 회귀 고정', () {
      // 서버가 막지 않으면 실제로 이 상태가 만들어졌다(DEV 실측).
      final overlapping = _new(start: d);
      expect(_old().isWorkingOnDate(d), true);
      expect(overlapping.isWorkingOnDate(d), true);
      final seats = (_old().isWorkingOnDate(d) ? 1 : 0) +
          (overlapping.isWorkingOnDate(d) ? 1 : 0);
      expect(seats, 2, reason: '이것이 막아야 하는 상태다');
    });

    test('01-f 주말은 어느 쪽에서도 근무일이 아니다', () {
      final sat = _d(2026, 9, 26);
      expect(_old().isWorkingOnDate(sat), false);
      expect(_new().isWorkingOnDate(sat), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. 서버 경계 가드
  // ══════════════════════════════════════════════════════════════
  group('02. 서버 경계 가드', () {
    test('02-a 시작일이 종료일 이하이면 거절한다', () {
      expect(renew.contains('if (newStartNum <= originalEndNum) {'), true);
      expect(renew.contains('갱신 계약 시작일은 원본 계약 종료일 다음 날부터여야 합니다.'),
          true);
    });

    test('02-b 옛 비교(같은 날짜 통과)가 남아 있지 않다', () {
      expect(renew.contains('newStartDateMs < originalEndDate.toMillis()'), false);
    });

    test('02-c ms 가 아니라 KST 달력 날짜로 비교한다', () {
      // workEndDate 는 KST 자정으로도 UTC 자정으로도 저장된다.
      expect(renew.contains('srvKstDateNum(originalEndDate.toDate())'), true);
      expect(renew.contains('srvKstDateNum(new Date(newStartDateMs))'), true);
    });

    test('02-d 종료 기준이 canonical effectiveEnd 다', () {
      expect(
        renew.contains('(originalData.actualResignDate ??\n      originalData.workEndDate)') ||
            renew.contains('originalData.actualResignDate ??'),
        true,
      );
    });

    test('02-e 시작일이 종료일보다 뒤여야 한다는 기본 검사도 남아 있다', () {
      expect(renew.contains('if (newStartDateMs >= newEndDateMs) {'), true);
    });

    test('02-f 소급 생성 하한이 유지된다', () {
      expect(renew.contains('계약 시작일은 30일 이전으로 소급할 수 없습니다.'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. OLD 불변 · NEW 생성
  // ══════════════════════════════════════════════════════════════
  group('03. 연장 writer', () {
    test('03-a 새 Application 을 만든다 — 기존 수정이 아니다', () {
      expect(renew.contains("const newRef = db.collection(\"applications\").doc();"),
          true);
      expect(renew.contains('tx.set(newRef, newData);'), true);
    });

    test('03-b 원본에는 결정과 역참조만 쓴다', () {
      final i = renew.indexOf('tx.update(originalRef, {');
      expect(i, greaterThan(-1));
      final seg = renew.substring(i, i + 300);
      expect(seg.contains('renewalDecision: "EXTEND"'), true);
      expect(seg.contains('renewedToApplicationId: newApplicationId'), true);
      // 기간을 다시 쓰지 않는다.
      expect(seg.contains('workEndDate'), false);
      expect(seg.contains('workDate'), false);
    });

    test('03-c 양방향 링크가 생긴다', () {
      expect(renew.contains('renewedFromApplicationId: originalApplicationId'), true);
      expect(renew.contains('renewedToApplicationId: newApplicationId'), true);
    });

    test('03-d 완료된 계약서는 건드리지 않는다', () {
      // void 대상은 서명 대기 계약서뿐이다.
      expect(
        renew.contains('const pendingStatuses = ["pending_employer", "pending_worker"];'),
        true,
      );
      final i = renew.indexOf('voidReason: "RENEWAL"');
      expect(i, greaterThan(-1));
      final seg = renew.substring((i - 400).clamp(0, i), i);
      expect(seg.contains('pendingStatuses.includes(cSnap.data()!.status as string)'),
          true);
    });

    test('03-e NEW 는 CONTRACT_PENDING 으로 시작한다', () {
      expect(renew.contains('status: "CONTRACT_PENDING",'), true);
    });

    test('03-f 운영 state 를 물려받지 않는다', () {
      for (final f in [
        'leaveDates: []', 'extraWorkDates: []', 'wageStatus: "pending"',
        'finalWage: null', 'wageDetail: null', 'actualResignDate: null',
        'resignStatus: null', 'terminationStatus: null',
        'renewalDecision: null', 'desiredStartDate: null',
      ]) {
        expect(renew.contains(f), true, reason: f);
      }
    });

    test('03-g 확정 카운터를 다시 올리지 않는다', () {
      // 연장은 기간 연장이지 확정 인원 변경이 아니다.
      expect(renew.contains('totalConfirmed'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. 중복 · 퇴사 gate · 권한
  // ══════════════════════════════════════════════════════════════
  group('04. 가드', () {
    test('04-a 이미 연장된 계약은 다시 연장되지 않는다', () {
      expect(renew.contains('if (freshData.renewalDecision === "EXTEND")'), true);
      expect(renew.contains('이미 연장 처리된 계약입니다.'), true);
    });

    test('04-b 그 판정이 트랜잭션 안에서 이뤄진다', () {
      // 밖에서 보면 두 관리자가 동시에 연장해 Application 이 둘 생긴다.
      final txStart = renew.indexOf('await db.runTransaction(');
      final guard = renew.indexOf('if (freshData.renewalDecision === "EXTEND")');
      final write = renew.indexOf('tx.set(newRef, newData);');
      expect(txStart, lessThan(guard));
      expect(guard, lessThan(write));
      expect(renew.contains('const freshSnap = await tx.get(originalRef);'), true);
    });

    test('04-c 확정 상태의 계약만 연장된다', () {
      expect(renew.contains('if (freshData.status !== "CONFIRMED")'), true);
    });

    test('04-d 퇴사·해지 승인자는 연장되지 않는다', () {
      expect(renew.contains('퇴사가 승인된 근무자의 계약은 연장할 수 없습니다.'), true);
      expect(renew.contains('계약 해지가 승인된 근무자의 계약은 연장할 수 없습니다.'), true);
      expect(
        renew.contains('const approvedExitStatuses = ["APPROVED", "AUTO_APPROVED"];'),
        true,
      );
    });

    test('04-e 연장 권한은 canManageContract 다', () {
      expect(renew.contains('assertBizAdmin(callerUid, businessId)'), true);
      expect(renew.contains('memberPermsForRenewal.canManageContract'), true);
      expect(renew.contains('계약 관리 권한이 없습니다.'), true);
    });

    test('04-f 클라이언트 가드도 같은 capability 다', () {
      final d = _codeOf(_src(_fixedWorkerPath));
      expect(d.contains('if (!_canManageContract()) {'), true);
      expect(d.contains('계약 연장 권한이 없습니다.'), true);
    });

    test('04-g 클라이언트가 D+1 을 만든다', () {
      final d = _codeOf(_src(_fixedWorkerPath));
      expect(
        d.contains("final newStart = app.workEndDate!.add(const Duration(days: 1));"),
        true,
      );
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 05. 자동 연장(D-0) — 같은 사건, 다른 writer
  // ══════════════════════════════════════════════════════════════
  group('05. 자동 연장', () {
    final auto = _after(
        cf, '.where("workEndDate", ">=", d0Start)', 6000);

    test('05-a 자동도 D+1 부터 시작한다', () {
      expect(auto.contains('newStartDateKST.setDate(newStartDateKST.getDate() + 1);'),
          true);
    });

    test('05-b 자동도 이미 결정된 계약은 건너뛴다', () {
      expect(auto.contains('if (freshData.renewalDecision) return;'), true);
    });

    test('05-c 수동이 먼저 커밋하면 자동이 재시도에서 비켜난다', () {
      // 같은 원본 문서를 TX 안에서 읽으므로 충돌하면 재시도된다.
      expect(auto.contains('const freshSnap = await tx.get(doc.ref);'), true);
    });

    test('05-d 자동도 퇴사·해지 승인자를 건너뛴다', () {
      expect(auto.contains('approvedExitStatuses.includes(freshData.resignStatus as string)'),
          true);
      expect(auto.contains('approvedExitStatuses.includes(freshData.terminationStatus as string)'),
          true);
    });

    test('05-e 자동도 운영 state 를 물려받지 않는다', () {
      for (final f in [
        'leaveDates: [],', 'extraWorkDates: [],', 'wageStatus: "pending",',
        'finalWage: null,', 'actualResignDate: null,',
      ]) {
        expect(auto.contains(f), true, reason: f);
      }
    });

    test('05-f 자동은 서명 없이 CONFIRMED 를 만든다 — 수동과 다르다', () {
      // 이것이 manual/auto 의 유일한 의미 차이다. 결함 여부는 제품 판단이므로
      // 여기서는 **현재 사실**을 고정한다. 바뀌면 이 테스트가 먼저 깨진다.
      expect(auto.contains('status: "CONFIRMED",'), true);
      expect(auto.contains('confirmedBy: "SYSTEM",'), true);
      expect(renew.contains('status: "CONTRACT_PENDING",'), true);
    });

    test('05-g 자동 연장은 계약서를 만들지 않는다', () {
      // 계약 의무는 좌석 기준(srvNeedsContractIssue)으로 따로 떠오른다.
      expect(auto.contains('callableFinalizeEmployerSignature'), false);
      expect(auto.contains('employment_contracts'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 06. 모집과 운영의 분리
  // ══════════════════════════════════════════════════════════════
  group('06. 모집 ≠ 운영', () {
    test('06-a 연장이 공고 기간을 늘리지 않는다', () {
      // tos 문서를 쓰는 곳이 연장 writer 안에 없다.
      expect(renew.contains('collection("tos")'), false);
      expect(renew.contains('rangeEnd'), false);
    });

    test('06-b 공고 마감은 기존 지원서를 건드리지 않는다', () {
      final close = _after(cf, 'export const callableCloseTOManually', 4000);
      expect(close.contains('collection("applications")'), false);
    });

    test('06-c 운영 목록은 공고가 아니라 지원서를 읽는다', () {
      final d = _codeOf(_src(_fixedWorkerPath));
      expect(d.contains('getApplicationsByBusinessId(businessId)'), true);
      // 구 계약은 일반 목록에서 빠지고 날짜 모드에서만 살아난다.
      expect(d.contains('if (app.renewalDecision == AppStatus.renewalExtend)'), true);
      expect(d.contains('uidsWithActiveLegacy'), true);
    });

    test('06-d 좌석 판정은 공용 resolver 하나를 쓴다', () {
      final seat = _after(cf, 'function srvContractConfirmedOnDay(', 700);
      expect(seat.contains('srvLongTermEligibleOnDay('), true);
    });
  });
}
