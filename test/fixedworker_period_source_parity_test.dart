// [VERIFY-R7-FIXEDWORKER-PERIOD-SOURCE-KST-PARITY] 같은 약속을 두 화면이 같게 말한다.
//
//   실기기에서 같은 사람(P-005)의 같은 약속이 이렇게 보였다.
//
//     인력 현황        장기 9/16~9/22
//     고정근무 관리    9/8~9/21
//
//   두 가지가 각각 틀려 있었다.
//
//   ① 종료일 9/21 vs 9/22 — **같은 field** 다.
//      고정근무 관리 행이 `DateFormat('M/d').format(...)` 으로 찍었고, 그것은
//      DateTime 자신의 zone 으로 찍는다. UTC 기기에서 `9/22 KST` 는 `9/21` 이다.
//      바로 아래 D-day 계산은 이미 `toKstDate` 를 쓰고 있었다 — 한 블록에서
//      두 달력을 함께 쓴 셈이다.
//
//   ② 시작일 9/8(→9/9) vs 9/16 — **확정일 보정**이 빠져 있었다.
//      `application_model.dart` 는 "세 곳의 effectiveStart 로직이 동일해야
//      한다"고 적어 두었지만 규칙이 각 자리에 복사돼 있었고, 고정근무 관리가
//      그 규칙을 모르는 네 번째 소비자였다.
//
//   같은 숫자로 만드는 것이 목적이 아니다. **같은 field 를 읽으면 같아야 하고,
//   다른 기간이면 출처가 달라야 한다** — 여기는 같은 약속의 같은 기간이었다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/posting_presentation_mode.dart';

// ═══════════════════════════════════════════════════════════════
// fixture — DEV 실측 저장값 그대로 (P-005 / zqaJEjUVPA6O1FWajlTX)
//
//   workDate 2026-09-09 KST · confirmedAt 2026-09-16 05:00 KST
//   workEndDate 2026-09-22 KST · desiredStartDate 없음 · actualResignDate 없음
// ═══════════════════════════════════════════════════════════════

DateTime _kst(int y, int m, int d, [int h = 0]) =>
    DateTime.utc(y, m, d, h).subtract(const Duration(hours: 9));

ApplicationModel _app({
  DateTime? workDate,
  DateTime? confirmedAt,
  DateTime? desiredStartDate,
  DateTime? workEndDate,
  DateTime? actualResignDate,
  String type = AppType.longTerm,
  /// `workEndDate: null` 은 기본값으로 대체되므로 "정말 없음"을 따로 표현한다.
  bool noEnd = false,
}) =>
    ApplicationModel(
      id: 'a1',
      toId: 'to1',
      uid: 'u1',
      businessId: 'biz1',
      businessName: '위워커',
      toTitle: '[R7FIX] 장기 근무 공고',
      status: AppStatus.contractPending,
      applicationType: type,
      selectedWorkType: '사무업무',
      startTime: '06:00',
      endTime: '08:00',
      wage: 12000,
      workDate: workDate ?? _kst(2026, 9, 9),
      confirmedAt: confirmedAt ?? _kst(2026, 9, 16, 5),
      desiredStartDate: desiredStartDate,
      workEndDate: noEnd ? null : (workEndDate ?? _kst(2026, 9, 22)),
      actualResignDate: actualResignDate,
      workDays: const ['월', '화', '수', '목', '금', '토', '일'],
      appliedAt: _kst(2026, 9, 15, 9),
    );

/// 인력 현황이 그리는 문자열 — production getter.
String workApplicantsPeriod(ApplicationModel a) => a.workPeriodDisplay;

/// 고정근무 관리 행이 그리는 문자열 — production 표현식 그대로.
///
///   `'${FormatHelper.formatDateShort(app.effectiveStartDate)} ~ '
///    '${end != null ? FormatHelper.formatDateShort(end) : '미정'}'`
String fixedWorkerPeriod(ApplicationModel a) {
  final end = a.effectiveEndDate;
  return '${FormatHelper.formatDateShort(a.effectiveStartDate)} ~ '
      '${end != null ? FormatHelper.formatDateShort(end) : '미정'}';
}

TOModel _to({String type = 'contract', DateTime? rangeEnd}) => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '위워커',
      type: type,
      title: 'test8',
      creatorUID: 'uid1',
      status: TOStatus.closed,
      deadlineType: 'HOURS_BEFORE',
      hoursBeforeStart: 2,
      workDetails: const [],
      totalRequired: 3,
      totalConfirmed: 0,
      totalPending: 0,
      rangeStart: _kst(2026, 8, 17),
      rangeEnd: rangeEnd,
      createdAt: _kst(2026, 8, 17, 17),
      statusUpdatedAt: _kst(2026, 8, 17, 17),
    );

String _read(String p) => File(p).readAsStringSync();

void main() {
  // ══════════════════════════════════════════════════════════════
  // A. 종료일 — 같은 field 는 같아야 한다
  // ══════════════════════════════════════════════════════════════

  group('FWP-A 종료일 parity', () {
    test('FWP-A1 두 화면이 같은 종료일을 말한다', () {
      final a = _app();
      expect(workApplicantsPeriod(a), endsWith('9/22'));
      expect(fixedWorkerPeriod(a), endsWith('9/22'),
          reason: '실기기에서 여기가 9/21 이었다 — DateFormat 은 기기 달력이다');
    });

    test('FWP-A2 DEV 실측 저장값의 canonical 기간 = 9/16~9/22', () {
      final a = _app();
      expect(workApplicantsPeriod(a), '9/16~9/22');
      expect(fixedWorkerPeriod(a), '9/16 ~ 9/22');
    });

    test('FWP-A3 actualResignDate 가 workEndDate 를 이긴다 — 양쪽 동일', () {
      final a = _app(actualResignDate: _kst(2026, 9, 19));
      expect(workApplicantsPeriod(a), '9/16~9/19');
      expect(fixedWorkerPeriod(a), '9/16 ~ 9/19');
    });

    test('FWP-A4 KST 자정 직전 종료도 같은 날을 말한다', () {
      // 9/22 23:59 KST = 9/22 14:59 UTC — 기기 성분을 읽으면 갈렸다.
      final a = _app(workEndDate: _kst(2026, 9, 22, 23));
      expect(fixedWorkerPeriod(a), endsWith('9/22'));
      expect(workApplicantsPeriod(a), endsWith('9/22'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // B. 시작일 — 규칙이 하나다
  // ══════════════════════════════════════════════════════════════

  group('FWP-B 시작일 규칙', () {
    test('FWP-B1 확정일이 공고일보다 늦으면 확정일이 시작이다', () {
      final a = _app(); // workDate 9/9, confirmedAt 9/16
      expect(a.effectiveStartDate, FormatHelper.toKstDate(_kst(2026, 9, 16)));
      expect(fixedWorkerPeriod(a), startsWith('9/16'),
          reason: '실기기에서 여기가 9/8(=9/9 의 UTC 표기) 이었다');
    });

    test('FWP-B2 희망시작일이 있으면 그것이 시작이고 보정하지 않는다', () {
      final a = _app(desiredStartDate: _kst(2026, 9, 20));
      expect(fixedWorkerPeriod(a), startsWith('9/20'));
      expect(workApplicantsPeriod(a), startsWith('9/20'));
    });

    test('FWP-B3 확정일이 공고일보다 이르면 공고일이 시작이다', () {
      final a = _app(
          workDate: _kst(2026, 9, 20), confirmedAt: _kst(2026, 9, 10, 5));
      expect(fixedWorkerPeriod(a), startsWith('9/20'));
    });

    test('FWP-B4 두 화면의 시작일이 항상 같다', () {
      for (final a in [
        _app(),
        _app(desiredStartDate: _kst(2026, 9, 20)),
        _app(workDate: _kst(2026, 9, 20), confirmedAt: _kst(2026, 9, 10)),
        _app(confirmedAt: _kst(2026, 9, 9, 3)),
      ]) {
        final wa = workApplicantsPeriod(a).split('~').first.trim();
        final fw = fixedWorkerPeriod(a).split('~').first.trim();
        expect(fw, wa, reason: '같은 약속의 시작일이 화면마다 달라진다');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // C. 없는 값을 만들지 않는다
  // ══════════════════════════════════════════════════════════════

  group('FWP-C 결측', () {
    test('FWP-C1 종료일이 없으면 미정이다 — 만들어 내지 않는다', () {
      final a = _app(noEnd: true);
      expect(fixedWorkerPeriod(a), '9/16 ~ 미정');
      expect(workApplicantsPeriod(a), '',
          reason: '인력 현황 행은 기간을 말할 수 없으면 줄을 세우지 않는다');
    });

    test('FWP-C2 createdAt 같은 무관한 값으로 기간을 만들지 않는다', () {
      final a = _app(noEnd: true);
      expect(fixedWorkerPeriod(a), isNot(contains('8/17')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // D. test8 — operationEnd 분류
  // ══════════════════════════════════════════════════════════════

  group('FWP-D operationEnd 분류', () {
    final today = _kst(2026, 9, 27, 12);

    test('FWP-D1 test8 저장 형태: contract + rangeEnd null → UNKNOWN', () {
      // DEV 실측: type=contract, rangeEnd=null, slots=0, status=CLOSED
      final g = TOGroupItem(singleTO: _to(rangeEnd: null));
      expect(g.operationEndDate, isNull,
          reason: '운영 종료일이 데이터에 없다 — createdAt 으로 대신하지 않는다');
      expect(
          resolvePostingPresentationMode(
              operationEnd: g.operationEndDate,
              recruitmentClosed: true,
              now: today),
          PostingPresentationMode.closedActive,
          reason: 'UNKNOWN 을 과거로 조작하지 않는다');
    });

    test('FWP-D2 운영 종료가 증명되면 PAST_ENDED 다', () {
      // DEV 실측 test1: 마지막 슬롯 2026-07-26
      final g = TOGroupItem(singleTO: _to(rangeEnd: _kst(2026, 7, 26)));
      expect(
          resolvePostingPresentationMode(
              operationEnd: g.operationEndDate,
              recruitmentClosed: true,
              now: today),
          PostingPresentationMode.pastEnded);
    });

    test('FWP-D3 미래 종료 + 모집 마감 → CLOSED_ACTIVE', () {
      // DEV 실측 [R8P2] p3b1 cancel-admin: 2027-01-19
      final g = TOGroupItem(singleTO: _to(rangeEnd: _kst(2027, 1, 19)));
      expect(
          resolvePostingPresentationMode(
              operationEnd: g.operationEndDate,
              recruitmentClosed: true,
              now: today),
          PostingPresentationMode.closedActive);
    });

    test('FWP-D4 모집 마감과 근로자 종료를 분리한다', () {
      // 근로자 한 명이 9/22 에 끝나도 공고 운영은 10/23 까지다.
      final g = TOGroupItem(singleTO: _to(rangeEnd: _kst(2026, 10, 23)));
      expect(
          resolvePostingPresentationMode(
              operationEnd: g.operationEndDate,
              recruitmentClosed: false,
              now: today),
          PostingPresentationMode.active);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // FWP-W wiring (보조 증거)
  // ══════════════════════════════════════════════════════════════

  group('FWP-W wiring', () {
    test('FWP-W1 고정근무 관리가 업무 날짜에 DateFormat 을 쓰지 않는다', () {
      final src = _read(
              'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart')
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(src.contains('DateFormat('), isFalse);
      expect(src.contains('FormatHelper.formatDateShort(effectiveStartDate)'),
          isTrue);
    });

    test('FWP-W2 시작일 규칙이 한 곳에 있다', () {
      final model = _read('lib/models/core/application_model.dart');
      expect(model.contains('DateTime get effectiveStartDate'), isTrue);
      // workPeriodDisplay 도 그 getter 를 쓴다 — 규칙 복사본을 남기지 않는다.
      //   주석이 길어 고정 길이 창은 쓰지 않는다. 코드 marker 로 자른다.
      final i = model.indexOf('String get workPeriodDisplay');
      final j = model.indexOf('DateTime get effectiveStartDate', i);
      expect(i, greaterThan(-1));
      expect(j, greaterThan(i));
      final seg = model.substring(i, j);
      expect(seg.contains('formatDateShort(effectiveStartDate)'), isTrue);
      // 규칙이 복사돼 남아 있지 않다.
      expect(seg.contains('desiredStartDate ?? workDate'), isFalse);
    });
  });
}
