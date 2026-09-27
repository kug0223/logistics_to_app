// [R7-P1-2 DEVICE.1C-CONTINUE] 운영 집계와 사람 상태는 다른 말을 쓴다.
//
//   ALfit core: 지원 = 관심, 확정 = 약속.
//   계약이 끝나도 "그 사람이 확정됐었다"는 사실은 남는다.
//
//   그런데 공고 카드의 `확정 N` 은 **지금 자리를 채우는 사람 수**였다.
//   같은 단어가 역사와 현재를 함께 말하니, 9/22 에 끝난 근무자가 있는
//   공고에서 `확정 0` 이 과거를 부정하는 것처럼 읽혔다.
//
//   그래서 운영 집계는 `충원`, 사람의 상태·행동은 `확정` 으로 나눈다.
//
//   그리고 lifecycle 은 결정과 효력을 구분한다.
//
//     만료 + 미결정        → 계약 확인 필요  (할 일 있음)
//     TERMINATE + D 미래   → 계약 종료 예정  (D 까지 좌석 유지)
//     TERMINATE + D 지남   → 계약 종료      (좌석 0, 할 일 없음)

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/application_model.dart';

String _read(String p) => File(p).readAsStringSync();

String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  expect(i, greaterThan(-1), reason: '구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  expect(j, greaterThan(i), reason: '구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

DateTime _d(int y, int m, int day) =>
    DateTime.utc(y, m, day).subtract(const Duration(hours: 9));

ApplicationModel _lt({
  required DateTime workEndDate,
  DateTime? actualResignDate,
  String status = AppStatus.contractPending,
}) =>
    ApplicationModel(
      id: 'a1', toId: 't1', uid: 'u1',
      businessId: 'b1', businessName: 'biz', toTitle: 'to',
      status: status, applicationType: AppType.longTerm,
      selectedWorkType: '사무업무', startTime: '06:00', endTime: '08:00',
      wage: 12000,
      workDate: _d(2026, 9, 9), confirmedAt: _d(2026, 9, 16),
      workEndDate: workEndDate, actualResignDate: actualResignDate,
      workDays: const ['월', '화', '수', '목', '금', '토', '일'],
      appliedAt: _d(2026, 9, 9),
    );

void main() {
  late String card, detail, fixed, work, day;

  setUpAll(() {
    card = _codeOf(_read('lib/widgets/admin/cards/admin_to_group_card.dart'));
    detail = _codeOf(_read('lib/widgets/admin/cards/admin_work_detail.dart'));
    fixed = _codeOf(_read(
        'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart'));
    work = _codeOf(_read(
        'lib/screens/business_admin/dialogs/work_applicants_dialog.dart'));
    day = _codeOf(_read(
        'lib/screens/business_admin/dialogs/day_applicants_dialog.dart'));
  });

  // ══════════════════════════════════════════════════════════════
  // N~Q. 용어
  // ══════════════════════════════════════════════════════════════

  group('VOC-N 운영 집계는 충원', () {
    test('VOC-N1 공고 요약', () {
      final line = _slice(card, 'Widget _buildStaffingLine(', 'Widget _build',);
      expect(line, contains("text: '충원 \$safeConfirmed'"));
      expect(line, contains("' / 필요 \$required'"));
      expect(line, contains("text: '부족 \$shortage'"));
      expect(line, isNot(contains("text: '확정 ")),
          reason: '운영 집계를 사람 상태와 같은 말로 부르지 않는다');
    });

    test('VOC-N2 업무 상세도 같은 말', () {
      expect(detail, contains("Text('충원 \$_confirmedCount'"));
      expect(detail, contains("Text('대기 \$_pendingCount'"));
      expect(detail, contains("Text('미충원 \$missing'"));
      expect(detail, isNot(contains("Text('확정 \$_confirmedCount'")));
    });

    test('VOC-N3 FLEX·CONTRACT 가 같은 component 를 쓴다', () {
      // 장기에만 다른 말을 쓰지 않는다 — 한 곳을 고치면 둘 다 바뀐다.
      expect(card, contains('_buildStaffingLine('));
      expect('WorkDetailRow('.allMatches(card).length, greaterThanOrEqualTo(2),
          reason: '단건/그룹 두 경로가 같은 행 component 를 쓴다');
    });

    test('VOC-O 사람의 확정 상태·행동은 그대로다', () {
      expect(work, contains("_buildSectionHeader(context, '확정'"),
          reason: '확정된 사람 목록의 머리말');
      expect(work, contains("label: '확정'"), reason: '확정 action');
      expect(work, contains("confirmText: '확정'"));
      expect(day, contains("label: '확정'"));
      expect(day, contains("'확정', _confirmedApps.length"),
          reason: '당일 명단 상단은 사람 수다 — 좌석 집계가 아니다');
    });

    test('VOC-Q 같은 화면에서 혼용하지 않는다', () {
      // 공고 카드의 운영 집계에 `확정` 이 남아 있지 않다.
      final line = _slice(card, 'Widget _buildStaffingLine(', 'Widget _build');
      expect(line, isNot(contains('확정')));
      // 업무 행도 마찬가지.
      final row = _slice(detail, "Text('충원", "Text('미충원");
      expect(row, isNot(contains('확정')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // F~K. lifecycle
  // ══════════════════════════════════════════════════════════════

  group('VOC-F lifecycle', () {
    test('VOC-F D 당일은 현재 관계다', () {
      final a = _lt(workEndDate: _d(2026, 9, 22));
      expect(a.occupiesSeatOn(_d(2026, 9, 22)), isTrue);
    });

    test('VOC-G D+1 은 끝난 관계다', () {
      final a = _lt(workEndDate: _d(2026, 9, 22));
      expect(a.occupiesSeatOn(_d(2026, 9, 23)), isFalse);
    });

    test('VOC-H TERMINATE + D 미래 → 종료 예정', () {
      // 라벨 분기가 결정이 아니라 **효력**을 본다.
      final chip = _slice(fixed, "label = '다음 계약 연장됨';", 'return Container(');
      expect(chip, contains("app.occupiesSeatOn(DateTime.now()) ? '계약 종료 예정' : '계약 종료'"));
    });

    test('VOC-I TERMINATE + D 지남 → 계약 종료', () {
      final a = _lt(workEndDate: _d(2026, 9, 22));
      expect(a.occupiesSeatOn(_d(2026, 9, 27)), isFalse);
      expect(fixed, contains("'계약 종료'"));
    });

    test('VOC-J 만료 + 미결정은 여전히 확인 필요', () {
      // 시간이 지났다는 이유로 결정을 추측하지 않는다.
      final rds = _codeOf(_read('lib/utils/renewal_decision_state.dart'));
      expect(rds, contains('if (app.renewalDecision != null) return RenewalDecisionState.resolved;'));
      expect(fixed, contains('RenewalDecisionState.expired'));
      // 줄바꿈을 가로질러 매칭하지 않는다 — 이 저장소는 CRLF 다.
      expect(fixed, contains("'계약 확인', expiredDecisionCount"));
    });

    test('VOC-K 끝난 관계에는 계약 할 일이 없다', () {
      // 줄바꿈 무관하게 — 배너 게이트에 좌석 조건이 함께 걸려 있는가.
      // 주석은 `_codeOf` 가 걷어낸다 — 코드 marker 로 자른다.
      final gate = _slice(
          fixed,
          '_buildStatusBanner(app, hasResignRequest, hasTerminationRequest),',
          '_buildContractPendingBanner(context),');
      expect(gate, contains('app.status == AppStatus.contractPending'));
      expect(gate, contains('app.occupiesSeatOn(DateTime.now())'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // L·M·P. FixedWorker 현재/이력
  // ══════════════════════════════════════════════════════════════

  group('VOC-L FixedWorker', () {
    test('VOC-L 근무중 집계가 끝난 관계를 뺀다', () {
      final agg = _slice(fixed, 'bool isEnded(_FixedWorkerItem w)', 'final endedCount');
      expect(agg, contains('!w.application.occupiesSeatOn(now)'));
      expect(agg, contains('!isEnded(w)'));
      expect(fixed, contains("_buildStatChip(context, '근무중', activeCount"));
    });

    test('VOC-M 끝난 관계가 화면에서 사라지지 않는다', () {
      // 전체 수는 그대로고, 끝난 수를 따로 센다.
      expect(fixed, contains("_buildStatChip(context, '전체', _fixedWorkers.length"));
      expect(fixed, contains("_buildStatChip(context, '계약 종료', endedCount"));
      // 목록 자체를 걸러내지 않는다.
      expect(fixed, isNot(contains('_fixedWorkers.removeWhere')));
    });

    test('VOC-P 끝난 행의 primary 상태가 계약 종료다', () {
      expect(fixed, contains("? '계약 종료 예정' : '계약 종료'"));
    });

    test('VOC-L2 `정상` 이 `근무중` 으로 바뀌었다', () {
      expect(fixed, isNot(contains("_buildStatChip(context, '정상'")));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 보존 계약
  // ══════════════════════════════════════════════════════════════

  group('VOC-Z 보존', () {
    test('VOC-Z1 UNKNOWN != ZERO 유지', () {
      for (final p in [
        'lib/widgets/admin/cards/admin_to_group_card.dart',
        'lib/widgets/admin/cards/admin_to_item_card.dart',
      ]) {
        expect(_codeOf(_read(p)), contains('stats == null'));
      }
    });

    test('VOC-Z2 부족 CTA·초대 진입이 그대로다 (§24)', () {
      expect(card, contains('_buildStaffingLine('));
      expect(day, contains('인력 초대 (\$shortage명 부족)'));
      expect(work, contains("label: Text('인력 초대 (\$shortage명 부족)')"));
    });

    test('VOC-Z3 FixedWorker 날짜가 KST 달력이다', () {
      // 실기기에서 9/9~9/22 가 9/8~9/21 로 보였다 — 기기 성분 직접 읽기.
      final deviceComponent = RegExp(r'\$\{[A-Za-z_.!()\[\]]*\.(month|day)\}');
      expect(deviceComponent.allMatches(fixed).toList(), isEmpty,
          reason: '계약 기간을 기기 달력으로 말한다');
      expect(fixed, contains('FormatHelper.formatDateShort('));

      // [R7-P1-2 DEVICE.1F] 이 앵커가 놓친 형태가 하나 더 있었다.
      //
      //   위 정규식은 `${d.month}/${d.day}` 만 본다. 그래서 같은 파일의
      //   `DateFormat('M/d').format(effectiveStartDate)` 를 통과시켰고,
      //   실기기에서 `9/8~9/21` 로 남아 있었다. `DateFormat.format` 은
      //   DateTime 자신의 zone 으로 찍으므로 기기 달력과 같다.
      //   업무 날짜를 말하는 이 파일에서는 쓰지 않는다.
      expect(fixed, isNot(contains('DateFormat(')),
          reason: '업무 날짜는 FormatHelper(KST) 로만 말한다');
    });

    test('VOC-Z5 같은 약속의 기간을 두 화면이 같은 식으로 말한다', () {
      // 시작일에 확정일 보정이 빠져 인력 현황은 `9/16~`, 고정근무 관리는
      //   `9/9~` 라고 했다. 규칙은 `effectiveStartDate` 하나다.
      expect(fixed, contains('app.effectiveStartDate'));
      expect(fixed, contains('app.effectiveEndDate'));
      final model = _codeOf(_read('lib/models/core/application_model.dart'));
      expect(model, contains('DateTime get effectiveStartDate'));
      expect(model, contains('FormatHelper.formatDateShort(effectiveStartDate)'),
          reason: 'workPeriodDisplay 도 같은 getter 를 쓴다');
    });

    test('VOC-Z4 삭제가 없다', () {
      for (final s in [card, detail, fixed]) {
        expect(s, isNot(contains('.delete()\n')));
      }
    });
  });
}
