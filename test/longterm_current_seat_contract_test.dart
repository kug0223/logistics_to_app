// [R7-P1-2 DEVICE.1B] 끝난 약속이 현재 정원을 계속 차지했다.
//
//   DEV 실측(toId zqaJEjUVPA6O1FWajlTX, 2026-09-27 KST 기준):
//
//     workDate 2026-09-09 · confirmedAt 2026-09-16 · workEndDate 2026-09-22
//     status CONTRACT_PENDING · renewalDecision TERMINATE
//
//     canonical eligibility  9/21 ✓  9/22 ✓  9/23 ✗(AFTER_END)  9/27 ✗
//     그런데 Posting 은 `확정 1 / 필요 2 / 부족 1`
//
//   관리자는 아무도 일하지 않는 자리에 한 명만 더 구하게 된다.
//
//   원인은 좌석 판정이 **status 만** 봤다는 것이다. 날짜로 끝난 관계에는
//   상태 전이가 일어나지 않는다 — 취소된 것이 아니기 때문이다. 그래서
//   scheduler 가 무엇을 하든, legacy 로 무엇이 남아 있든, 좌석은 스스로
//   비워져야 한다.
//
//   여기서 지키는 것:
//
//     확정 이력  !=  현재 좌석
//     D 까지는 좌석,  D+1 부터는 아니다
//     이력은 지우지 않는다

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/application_model.dart';

String _read(String p) => File(p).readAsStringSync();

// [R7-APPLICATION-LIFECYCLE.1C.1] 장기 약속 날짜 규칙의 canonical 위치.
const _cdPath = 'functions/src/commitment_dates.ts';

String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// KST 자정 instant — 저장 모양 그대로.
DateTime _d(int y, int m, int day) =>
    DateTime.utc(y, m, day).subtract(const Duration(hours: 9));

ApplicationModel _longTerm({
  String status = AppStatus.contractPending,
  required DateTime workDate,
  DateTime? desiredStartDate,
  DateTime? confirmedAt,
  DateTime? workEndDate,
  DateTime? actualResignDate,
  DateTime? staffingReleasedAt,
}) =>
    ApplicationModel(
      id: 'a1',
      toId: 'to1',
      uid: 'u1',
      businessId: 'b1',
      businessName: 'biz',
      toTitle: 'to',
      wage: 12000,
      status: status,
      applicationType: AppType.longTerm,
      selectedWorkType: '사무업무',
      startTime: '06:00',
      endTime: '08:00',
      workDate: workDate,
      desiredStartDate: desiredStartDate,
      confirmedAt: confirmedAt,
      workEndDate: workEndDate,
      actualResignDate: actualResignDate,
      staffingReleasedAt: staffingReleasedAt,
      workDays: const ['월', '화', '수', '목', '금', '토', '일'],
      appliedAt: workDate,
    );

/// 좌석 집계 — `loadTOWorkDetails.countsAsSeat` 와 같은 규칙.
const _activeStatuses = {'PENDING', 'CONFIRMED', 'CONTRACT_PENDING'};
int seats(List<ApplicationModel> apps, DateTime day) => apps
    .where((a) =>
        _activeStatuses.contains(a.status) &&
        !a.isStaffingReleased &&
        a.occupiesSeatOn(day))
    .where((a) => a.status != AppStatus.pending)
    .length;

void main() {
  // DEV 의 실제 약속.
  final dev = _longTerm(
    workDate: _d(2026, 9, 9),
    confirmedAt: _d(2026, 9, 16),
    workEndDate: _d(2026, 9, 22),
  );

  // ══════════════════════════════════════════════════════════════
  // A~C. 경계 (§14) — D 까지 좌석, D+1 부터 아님
  // ══════════════════════════════════════════════════════════════

  group('LCS-A 경계', () {
    test('LCS-A D-1 / D 는 좌석을 차지한다', () {
      expect(dev.occupiesSeatOn(_d(2026, 9, 21)), isTrue, reason: 'D-1');
      expect(dev.occupiesSeatOn(_d(2026, 9, 22)), isTrue, reason: 'D — 마지막 근무일');
    });

    test('LCS-B D+1 / D+5 는 좌석이 아니다', () {
      expect(dev.occupiesSeatOn(_d(2026, 9, 23)), isFalse, reason: 'D+1');
      expect(dev.occupiesSeatOn(_d(2026, 9, 27)), isFalse, reason: 'D+5 = 실기기 날짜');
    });

    test('LCS-C actualResignDate 가 있으면 그쪽이 경계다', () {
      final resigned = _longTerm(
        workDate: _d(2026, 9, 9),
        confirmedAt: _d(2026, 9, 16),
        workEndDate: _d(2026, 10, 23),
        actualResignDate: _d(2026, 9, 18),
      );
      expect(resigned.effectiveEndDate, _d(2026, 9, 18),
          reason: 'actualResignDate ?? workEndDate');
      expect(resigned.occupiesSeatOn(_d(2026, 9, 18)), isTrue, reason: '퇴사일 당일 포함');
      expect(resigned.occupiesSeatOn(_d(2026, 9, 19)), isFalse);
      // workEndDate 가 멀어도 퇴사일이 이긴다.
      expect(resigned.occupiesSeatOn(_d(2026, 10, 1)), isFalse);
    });

    test('LCS-C2 기기 timezone 과 무관하다', () {
      // 경계값을 KST 달력으로 판정한다 — 9/22 23:00 KST 도 여전히 D.
      final lateOnD = _d(2026, 9, 22).add(const Duration(hours: 23));
      expect(dev.occupiesSeatOn(lateOnD), isTrue);
      final earlyDPlus1 = _d(2026, 9, 23).add(const Duration(minutes: 1));
      expect(dev.occupiesSeatOn(earlyDPlus1), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // D~F. status 만으로 좌석을 살려내지 않는다 (§9)
  // ══════════════════════════════════════════════════════════════

  group('LCS-D status 독립', () {
    final today = _d(2026, 9, 27);

    test('LCS-D CONFIRMED 인데 기간이 지났으면 좌석 0', () {
      final a = _longTerm(
        status: AppStatus.confirmed,
        workDate: _d(2026, 9, 9),
        confirmedAt: _d(2026, 9, 16),
        workEndDate: _d(2026, 9, 22),
      );
      expect(a.status, AppStatus.confirmed);
      expect(seats([a], today), 0);
    });

    test('LCS-E CONTRACT_PENDING 인데 기간이 지났으면 좌석 0 — 실기기 그대로', () {
      expect(seats([dev], today), 0);
      // 그리고 아직 안 끝난 시점에는 좌석이다.
      expect(seats([dev], _d(2026, 9, 22)), 1);
    });

    test('LCS-F renewalDecision TERMINATE + 기간 경과 → 좌석 0', () {
      // renewalDecision 을 읽지 않는다 — 날짜만으로 이미 결론이 난다.
      //   scheduler 가 status 를 정리하지 않아도 판정이 어긋나지 않는 이유다.
      expect(seats([dev], today), 0);
    });

    test('LCS-F2 scheduler 에 의존하지 않는다 (§11)', () {
      // status 는 그대로 CONTRACT_PENDING 이고 취소된 적이 없다.
      expect(dev.status, AppStatus.contractPending);
      expect(dev.isStaffingReleased, isFalse);
      // 그런데도 좌석은 비어 있다.
      expect(dev.occupiesSeatOn(today), isFalse);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // G. 갱신 (§15)
  // ══════════════════════════════════════════════════════════════

  group('LCS-G 갱신', () {
    final today = _d(2026, 9, 27);

    test('LCS-G OLD 종료 + NEW 활성 → 정확히 1', () {
      final oldApp = dev; // ~9/22
      final newApp = _longTerm(
        workDate: _d(2026, 9, 23),
        confirmedAt: _d(2026, 9, 23),
        workEndDate: _d(2026, 10, 23),
      );
      expect(seats([oldApp, newApp], today), 1, reason: '이중 계상 0');
      expect(oldApp.occupiesSeatOn(today), isFalse);
      expect(newApp.occupiesSeatOn(today), isTrue);
    });

    test('LCS-G2 미래 시작 관계는 좌석을 유지한다 (§8)', () {
      // 시작 전이라고 자리를 비우지 않는다 — 남은 모집 기간의 자리다.
      final future = _longTerm(
        workDate: _d(2026, 10, 1),
        workEndDate: _d(2026, 10, 23),
      );
      expect(future.occupiesSeatOn(today), isTrue);
      expect(seats([future], today), 1);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // H~J. 보존 계약
  // ══════════════════════════════════════════════════════════════

  group('LCS-H 보존', () {
    final today = _d(2026, 9, 27);

    test('LCS-H 이력은 그대로다 (§10)', () {
      // 좌석에서 빠져도 약속 자체는 남는다 — 지우는 코드가 아니다.
      expect(dev.status, AppStatus.contractPending);
      expect(dev.workEndDate, _d(2026, 9, 22));
      expect(dev.confirmedAt, _d(2026, 9, 16));
      // 과거 날짜에 대한 근무 판정도 그대로다.
      expect(dev.isWorkingOnDate(_d(2026, 9, 20)), isTrue);
      expect(dev.isWorkingOnDate(_d(2026, 9, 22)), isTrue);
    });

    test('LCS-I 단기(FLEX)는 날짜 축이 없다 — 회귀 없음', () {
      final flex = ApplicationModel(
        id: 'f1',
        toId: 'to1',
        uid: 'u1',
        businessId: 'b1',
        businessName: 'biz',
      toTitle: 'to',
      wage: 12000,
        status: AppStatus.confirmed,
        applicationType: AppType.shortTerm,
        selectedWorkType: '홀서빙',
        startTime: '09:00',
        endTime: '18:00',
        workDate: _d(2026, 1, 1),
        appliedAt: _d(2026, 1, 1),
      );
      // 한참 지난 단기 근무여도 좌석 판정은 기존대로 status 가 정한다.
      expect(flex.occupiesSeatOn(today), isTrue);
      expect(seats([flex], today), 1);
    });

    test('LCS-I2 기간을 모르면 좌석을 빼앗지 않는다', () {
      final noEnd = _longTerm(workDate: _d(2026, 9, 9), workEndDate: null);
      expect(noEnd.effectiveEndDate, isNull);
      expect(noEnd.occupiesSeatOn(today), isTrue,
          reason: '확인하지 못한 것으로 부족을 부풀리지 않는다');
    });

    test('LCS-I3 좌석 반납은 여전히 별개 축이다', () {
      final released = _longTerm(
        workDate: _d(2026, 9, 9),
        workEndDate: _d(2026, 10, 23),
        staffingReleasedAt: _d(2026, 9, 20),
      );
      expect(released.occupiesSeatOn(today), isTrue, reason: '기간은 살아 있다');
      expect(seats([released], today), 0, reason: '반납이 좌석을 비운다');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 계약 배선
  // ══════════════════════════════════════════════════════════════

  group('LCS-W 배선', () {
    test('LCS-W1 집계가 좌석 판정을 쓴다', () {
      final svc = _codeOf(_read('lib/services/firestore_service.dart'));
      expect(svc, contains('a.occupiesSeatOn(seatDay)'));
      expect(svc, contains("const activeStatuses = {'PENDING', 'CONFIRMED', 'CONTRACT_PENDING'}"));
      expect(svc, contains('!a.isStaffingReleased'),
          reason: '기존 축을 지우지 않는다');
    });

    test('LCS-W2 effectiveEnd 식이 서버와 같다', () {
      final model = _codeOf(_read('lib/models/core/application_model.dart'));
      expect(model,
          contains('DateTime? get effectiveEndDate => actualResignDate ?? workEndDate;'));
      // [R7-APPLICATION-LIFECYCLE.1C.1] 서버 식의 canonical 위치는 모듈이다.
      final cd = _read(_cdPath);
      expect(cd, contains('const resign = asDate(appData["actualResignDate"]);'));
      expect(cd, contains('const end = resign ?? asDate(appData["workEndDate"]);'));
    });

    test('LCS-W3 정원 projection 이 effectiveEnd 를 실어 보낸다', () {
      final cf = _read('functions/src/index.ts');
      final allow = cf.substring(
          cf.indexOf('const CAPACITY_ALLOWED_FIELDS = new Set(['),
          cf.indexOf('const CAPACITY_ALLOWED_FIELDS = new Set([') + 900);
      expect(allow, contains('"workEndDate"'));
      expect(allow, contains('"actualResignDate"'));
      expect(allow, contains('"type"'), reason: '장기 여부 판정에 필요');
      // 사람을 식별하는 값은 여전히 들어가지 않는다.
      expect(allow, isNot(contains('"uid"')));
    });

    test('LCS-W4 UNKNOWN != ZERO 계약 유지 (§12)', () {
      for (final path in [
        'lib/widgets/admin/cards/admin_to_group_card.dart',
        'lib/widgets/admin/cards/admin_to_item_card.dart',
      ]) {
        expect(_codeOf(_read(path)), contains('stats == null'),
            reason: '$path — DEVICE.1A 계약이 풀렸다');
      }
      final svc = _codeOf(_read('lib/services/firestore_service.dart'));
      expect(svc,
          contains("for (final w in workDetails) w.canonicalId: {'confirmed': 0, 'pending': 0}"));
    });

    test('LCS-W5 새 정책을 만들지 않았다 (§2)', () {
      final model = _codeOf(_read('lib/models/core/application_model.dart'));
      // 기존 canonical 판정이 그대로 살아 있다.
      expect(model, contains('bool isWorkingOnDate(DateTime targetDate)'));
      expect(model, contains('final endDate = actualResignDate ?? workEndDate;'));
      // 삭제 계열 동작이 섞여 들어오지 않았다.
      for (final banned in ['.delete()', 'FieldValue.delete()']) {
        final svcSlice = _codeOf(_read('lib/services/firestore_service.dart'));
        final i = svcSlice.indexOf('bool countsAsSeat');
        expect(svcSlice.substring(i, i + 400), isNot(contains(banned)),
            reason: '좌석 판정이 데이터를 지우면 안 된다: $banned');
      }
    });
  });
}
