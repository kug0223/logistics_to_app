// [POSTING-V2-03I.3] 급여 산정 조건도 약속이다
//
// 03I.2 READ에서 드러난 것:
//   · 금액(wage)만 스냅샷이었다. 휴게시간·야간수당·연장 단가·공제 방식은
//     급여를 확정하는 시점에 공고에서 **다시 읽혔다**
//     (wage_confirm_dialog → WorkDetailHelper.resolve(app, liveMap)
//      → WorkDetailTimeService → tos/{toId}/slots/{slotId}.workDetails).
//   · 그래서 이미 확정된 사람도 관리자가 공고 조건을 바꾸면
//     연장·야간 수당이 조용히 달라졌다. 정상근무만 하면 티가 나지 않았다.
//   · 계약서도 금액만 약속 버전이고 나머지는 현재 값이라 mixed-version이었다.
//
// 확정 정책: 지원/초대 시점의 산정 조건 전체가 그 사람의 compensation promise다.
//   CURRENT POSTING CONDITIONS != EXISTING APPLICATION PROMISED CONDITIONS

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/utils/work_detail_helper.dart';

const _fnsPath = 'functions/src/index.ts';
const _editPath = 'lib/screens/business_admin/to_management/edit_to_screen.dart';
const _contractSvc = 'lib/services/contract_service.dart';
const _helperPath = 'lib/utils/work_detail_helper.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) throw StateError('$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') paren++;
    if (source[i] == ')') {
      paren--;
      if (paren == 0) {
        afterParams = i;
        break;
      }
    }
  }
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$signature 본문의 끝을 찾지 못함');
}

// ── fixtures ────────────────────────────────────────────────────
ApplicationModel _app({
  required int wage,
  String wageType = 'daily',
  int? baseHourlyWage,
  int? breakMinutes,
  bool? nightAllowanceApplied,
  bool? nightIncluded,
  String? taxDeductionType,
  String startTime = '09:00',
  String endTime = '18:00',
  String status = 'CONFIRMED',
}) =>
    ApplicationModel(
      id: 'app1',
      uid: 'u1',
      businessId: 'b1',
      businessName: '테스트사업장',
      toTitle: '피킹 공고',
      selectedWorkType: '피킹',
      wage: wage,
      wageType: wageType,
      baseHourlyWage: baseHourlyWage,
      breakMinutes: breakMinutes,
      nightAllowanceApplied: nightAllowanceApplied,
      nightIncluded: nightIncluded,
      taxDeductionType: taxDeductionType,
      startTime: startTime,
      endTime: endTime,
      status: status,
      appliedAt: DateTime(2026, 9, 1),
      workDate: DateTime(2026, 9, 20),
    );

/// 공고의 **현재** 조건 (WorkDetailTimeService가 슬롯에서 읽어오는 형태)
Map<String, dynamic> _liveMap({
  required int wage,
  String wageType = 'daily',
  int? baseHourlyWage,
  int breakMinutes = 0,
  bool nightAllowanceApplied = true,
  bool nightIncluded = false,
  String taxDeductionType = 'none',
  String startTime = '09:00',
  String endTime = '18:00',
}) =>
    {
      '피킹_${startTime}_$endTime': {
        'wage': wage,
        'wageType': wageType,
        if (baseHourlyWage != null) 'baseHourlyWage': baseHourlyWage,
        'breakMinutes': breakMinutes,
        'nightAllowanceApplied': nightAllowanceApplied,
        'nightIncluded': nightIncluded,
        'taxDeductionType': taxDeductionType,
        'startTime': startTime,
        'endTime': endTime,
        'shiftType': 'day', // 스냅샷에 없는 표시 정보
      },
    };

void main() {
  // ── §3, §16 snapshot schema ───────────────────────────────────
  group('COMP-01 지원서가 산정 조건을 갖는다', () {
    test('01-a 스냅샷 유무가 필드 존재로 구분된다 (§16)', () {
      final legacy = _app(wage: 100000);
      expect(legacy.hasCompensationSnapshot, false);
      expect(legacy.compensationSnapshot, isNull);

      final fresh = _app(
        wage: 100000,
        baseHourlyWage: 12500,
        breakMinutes: 60,
        nightAllowanceApplied: true,
        nightIncluded: false,
        taxDeductionType: 'none',
      );
      expect(fresh.hasCompensationSnapshot, true);
      expect(fresh.compensationSnapshot, isNotNull);
    });

    test('01-b 별도 version 필드를 만들지 않았다 (§16)', () {
      final code = _codeOf(_src('lib/models/core/application_model.dart'));
      expect(code.contains('compensationSnapshotVersion'), false);
      expect(code.contains('snapshotVersion'), false);
      expect(
          code.contains('bool get hasCompensationSnapshot => '
              'nightAllowanceApplied != null;'),
          true);
    });

    test('01-c 스냅샷 키가 workDetail과 같은 이름이다', () {
      final snap = _app(
        wage: 100000,
        baseHourlyWage: 12500,
        breakMinutes: 60,
        nightAllowanceApplied: false,
        nightIncluded: true,
        taxDeductionType: 'income_3_3',
      ).compensationSnapshot!;
      expect(snap['wage'], 100000);
      expect(snap['wageType'], 'daily');
      expect(snap['baseHourlyWage'], 12500);
      expect(snap['breakMinutes'], 60);
      expect(snap['nightAllowanceApplied'], false);
      expect(snap['nightIncluded'], true);
      expect(snap['taxDeductionType'], 'income_3_3');
      // [POSTING-V2-03I.4] 근무시간은 임금 조건이 아니라 운영 일정이므로
      //   스냅샷에 넣지 않는다 — effectiveStart/End가 현재 정의를 따른다.
      expect(snap.containsKey('startTime'), false);
      expect(snap.containsKey('endTime'), false);
    });
  });

  // ── §3, §4, §5, §17 서버 생성 경로 ────────────────────────────
  group('COMP-02 서버가 세 경로에서 같은 스냅샷을 만든다', () {
    test('02-a 공통 빌더가 존재하고 기본값이 모델과 맞는다', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('export function buildCompensationSnapshot('), true);
      final body = _flat(_codeOf(
          _bodyOf(fns, 'export function buildCompensationSnapshot(')));
      expect(body.contains('out.breakMinutes = typeof brk === "number" ? brk : 0;'),
          true);
      expect(
          body.contains('out.nightAllowanceApplied = '
              'typeof nAp === "boolean" ? nAp : true;'),
          true,
          reason: '생략 = true (WorkDetailData.toMap 규칙)');
      expect(
          body.contains('out.nightIncluded = typeof nIn === "boolean" ? nIn : false;'),
          true);
    });

    test('02-b 지원(PENDING) 경로 — 신규/재지원 둘 다 (§3)', () {
      final fns = _src(_fnsPath);
      expect(
          'wage: effectiveWage, wageType: effectiveWageType,'.allMatches(fns).length,
          2,
          reason: '신규 setData + 재지원 reactivateData');
      expect('...compensationSnapshot,'.allMatches(fns).length, 2,
          reason: '두 payload 모두에 붙어야 한다');
      expect(
          fns.contains('const compensationSnapshot = '
              'buildCompensationSnapshot(promisedWD);'),
          true);
    });

    test('02-c 초대(INVITED) 경로도 동일 빌더 (§4)', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('...buildCompensationSnapshot(inviteMatchedWD),'), true);
      expect(fns.contains('inviteMatchedWD = matchedWD;'), true);
    });

    test('02-d 명시적 업무 변경은 새 조건으로 재약속 (§5)', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('changedCompensation = buildCompensationSnapshot(newWD);'),
          true);
      expect(fns.contains('...changedCompensation,'), true);
    });

    test('02-e 클라이언트 전달값을 신뢰하지 않는다 (§17)', () {
      final fns = _src(_fnsPath);
      // 조건은 모두 서버가 matched workDetail에서 뽑는다
      expect(fns.contains('buildCompensationSnapshot(d.breakMinutes'), false);
      expect(fns.contains('data.nightAllowanceApplied'), false);
      // 기존 서버 임금 권위도 유지
      expect(fns.contains('const effectiveWage = serverWage;'), true);
      expect(fns.contains('"해당 업무 유형의 임금 정보를 서버에서 찾을 수 없습니다."'), true);
    });
  });

  // ── §6, §9, §11 payroll / display source ──────────────────────
  group('COMP-03 급여 계산이 약속 조건을 쓴다', () {
    test('03-a 약속이 현재 공고 조건을 덮는다 (§6)', () {
      final app = _app(
        wage: 100000,
        baseHourlyWage: 12500,
        breakMinutes: 60,
        nightAllowanceApplied: true,
        nightIncluded: false,
        taxDeductionType: 'none',
      );
      // 관리자가 공고를 전부 바꿨다
      final live = _liveMap(
        wage: 110000,
        baseHourlyWage: 15000,
        breakMinutes: 30,
        nightAllowanceApplied: false,
        nightIncluded: true,
        taxDeductionType: 'income_3_3',
      );
      final d = WorkDetailHelper.resolve(app, live);
      expect(WorkDetailHelper.wage(d), 100000);
      expect(WorkDetailHelper.baseHourlyWage(d), 12500);
      expect(WorkDetailHelper.breakMinutes(d), 60);
      expect(WorkDetailHelper.nightAllowanceApplied(d), true);
      expect(WorkDetailHelper.nightIncluded(d), false);
      expect(WorkDetailHelper.taxDeductionType(d), 'none');
    });

    test('03-b 스냅샷에 없는 표시 정보는 현재 값이 남는다', () {
      final app = _app(wage: 100000, nightAllowanceApplied: true);
      final d = WorkDetailHelper.resolve(app, _liveMap(wage: 110000));
      expect(d!['shiftType'], 'day', reason: 'overlay는 조건만 덮는다');
    });

    // [POSTING-V2-03I.4 재작성] 03I.3에서 근무시간까지 약속으로 덮었는데,
    // 그것은 이 앱의 기존 계약과 충돌했다: 관리자가 업무 시간을 바꾸면
    // 지각·조퇴 판정 경계도 함께 움직여야 한다
    // (admin_home_attendance_effective_time_test가 그것을 검증한다).
    // 근무시간은 임금 조건이 아니라 운영 일정이므로 현재 정의를 따른다.
    // 활성 지원자가 있는 동안의 시간 변경은 03G identity guard가 막는다.
    test('03-c 근무시간은 현재 정의를 따른다 (기존 계약 유지)', () {
      final app = _app(
        wage: 100000,
        nightAllowanceApplied: true,
        startTime: '09:00',
        endTime: '18:00',
      );
      final live = _liveMap(wage: 110000, startTime: '09:00', endTime: '18:00');
      live['피킹_09:00_18:00']!['startTime'] = '10:00';
      live['피킹_09:00_18:00']!['endTime'] = '19:00';
      expect(WorkDetailHelper.effectiveStart(app, live), '10:00');
      expect(WorkDetailHelper.effectiveEnd(app, live), '19:00');
      // 임금 조건은 그대로 약속이 이긴다
      expect(WorkDetailHelper.wage(WorkDetailHelper.resolve(app, live)), 100000);
    });

    test('03-d 레거시는 현재 조건으로 계산한다 (§15 legacy compatibility)', () {
      final legacy = _app(wage: 100000); // 스냅샷 없음
      final live = _liveMap(wage: 110000, breakMinutes: 30, baseHourlyWage: 15000);
      final d = WorkDetailHelper.resolve(legacy, live);
      expect(WorkDetailHelper.breakMinutes(d), 30);
      expect(WorkDetailHelper.baseHourlyWage(d), 15000);
      // 그 경로가 legacy임을 코드가 명시한다
      final code = _src(_helperPath);
      expect(code.contains('legacy compatibility'), true);
    });

    // [POSTING-V2-03I.4 재작성] 03I.3에서는 스냅샷이 없으면 현재 값으로
    // 통째로 되돌렸다. 그러면 레거시가 자기도 갖고 있는 금액·급여유형까지
    // 잃는다. 이제 지원서가 아는 것은 언제나 덮고, 모르는 것만 현재 값이 남는다.
    test('03-e 약속이 현재 값을 덮는 방향이다 (§15)', () {
      final fresh = _app(wage: 100000, nightAllowanceApplied: true);
      final body = _flat(_codeOf(_bodyOf(_src(_helperPath),
          'static Map<String, dynamic>? resolve(')));
      expect(body.contains('final promised = app.promisedCompensation;'), true);
      expect(body.contains('return {...live, ...promised};'), true,
          reason: '약속이 현재 값을 덮는 방향이어야 한다');
      expect(body.contains('if (promised == null) return live;'), false,
          reason: '레거시를 통째로 현재 값으로 돌리지 않는다');
      expect(fresh.hasCompensationSnapshot, true);
    });
  });

  // ── §8 contract ───────────────────────────────────────────────
  group('COMP-04 계약서가 mixed-version이 아니다', () {
    test('04-a overlay가 조건 전체를 덮는다 (§8)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_contractSvc), 'WorkDetailData _withPromisedWage(')));
      for (final f in [
        'baseHourlyWage: application.baseHourlyWage,',
        'breakMinutes: application.breakMinutes,',
        'nightAllowanceApplied: application.nightAllowanceApplied,',
        'nightIncluded: application.nightIncluded,',
        'taxDeductionType: application.taxDeductionType,',
      ]) {
        expect(body.contains(f), true, reason: f);
      }
      expect(body.contains('clearBaseHourlyWage: application.baseHourlyWage == null,'),
          true,
          reason: '약속에 없으면 현재 값이 남으면 안 된다');
    });

    test('04-b 모델에 없는 필드를 추가하지 않았다 (§8)', () {
      final body = _codeOf(
          _bodyOf(_src(_contractSvc), 'WorkDetailData _withPromisedWage('));
      // 지급일 설정은 임금 조건이 아니다 — 별도 변경 flow가 있다
      expect(body.contains('payScheduleType:'), false);
      expect(body.contains('payScheduleDay:'), false);
    });

    test('04-c 레거시는 금액만 맞춘다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_contractSvc), 'WorkDetailData _withPromisedWage(')));
      expect(body.contains('if (!application.hasCompensationSnapshot) {'), true);
      // legacy 분기임은 주석으로 명시돼 있다 (§15)
      expect(_src(_contractSvc).contains('legacy compatibility'), true);
      // 03I.1의 결측 실패는 그대로
      expect(body.contains('if (promisedWage <= 0) {'), true);
      expect(body.contains('throw StateError('), true);
    });
  });

  // ── §1, §2, §12, §13 WAGE-GUARD ───────────────────────────────
  group('COMP-05 경고가 실제 조건 변경에만 뜬다', () {
    test('05-a requiredCount가 트리거에서 빠졌다 (§1)', () {
      final body = _codeOf(
          _bodyOf(_src(_editPath), 'bool _hasWageFieldsChanged('));
      expect(body.contains('requiredCount'), false,
          reason: '필요 인원은 급여 계산식 어디에도 없다');
    });

    test('05-b 배열 길이 변화가 트리거에서 빠졌다 (§2)', () {
      final body = _codeOf(
          _bodyOf(_src(_editPath), 'bool _hasWageFieldsChanged('));
      expect(body.contains('_workDetails.length != _originalWorkDetails.length'),
          false,
          reason: '업무 추가·삭제는 03G.1 preflight의 책임이다');
      expect(body.contains('if (orig == null) continue;'), true,
          reason: '새 업무는 기존 약속과 무관하다');
    });

    test('05-c start/end가 빠졌다 — 03G.1이 먼저 막는다 (§12)', () {
      final body = _codeOf(
          _bodyOf(_src(_editPath), 'bool _hasWageFieldsChanged('));
      expect(body.contains('cur.startTime != orig.startTime'), false);
      expect(body.contains('cur.endTime != orig.endTime'), false);
      // identity preflight는 그대로 살아 있다
      final code = _codeOf(_src(_editPath));
      expect(code.contains('Future<bool> _canApplyWorkChange('), true);
    });

    test('05-d 실제 산정 조건 7개는 남아 있다 (§12)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_editPath), 'bool _hasWageFieldsChanged(')));
      for (final f in [
        'cur.wage != orig.wage',
        'cur.wageType != orig.wageType',
        'cur.breakMinutes != orig.breakMinutes',
        'cur.nightAllowanceApplied != orig.nightAllowanceApplied',
        'cur.nightIncluded != orig.nightIncluded',
        'cur.baseHourlyWage != orig.baseHourlyWage',
        'cur.taxDeductionType != orig.taxDeductionType',
      ]) {
        expect(body.contains(f), true, reason: f);
      }
    });

    test('05-e 문구가 조건까지 포함한다 (§13)', () {
      final body = _codeOf(
          _bodyOf(_src(_editPath), 'Future<bool> _showWageGuardWarning('));
      expect(body.contains("title: '임금 및 급여 산정 조건 변경',"), true);
      expect(
          body.contains('임금이나 급여 산정 조건을 변경해도 기존 지원자의 지원 당시 조건은 유지됩니다. '),
          true);
      expect(body.contains('변경된 조건은 이후 새로 지원하는 사람부터 적용됩니다.'), true);
      expect(body.contains('이미 확정된 근무자의 약속된 임금과 지급 기준도 변경되지 않습니다.'), true);
      // 03I.1의 금액-only 문구는 사라졌다
      expect(body.contains('임금을 변경하면 기존 지원자의 지원 당시 임금은 유지되고'), false);
    });

    test('05-f cohort 4상태와 fresh fetch 유지 (§14)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_editPath), 'Future<bool> _showWageGuardWarning(')));
      expect(
          body.contains('const cohortStatuses = [ AppStatus.pending, '
              'AppStatus.invited, AppStatus.contractPending, AppStatus.confirmed, ];'),
          true);
      expect(body.contains('await _applicationRelations.fresh();'), true,
          reason: '03G.1 freshness 계약 유지');
    });
  });

  // ── §10 A/B cohort ────────────────────────────────────────────
  group('COMP-06 A/B cohort 전 조건 분리', () {
    final aPromise = _app(
      wage: 100000,
      baseHourlyWage: 12500,
      breakMinutes: 60,
      nightAllowanceApplied: true,
      nightIncluded: false,
      taxDeductionType: 'none',
    );
    // 공고 수정 후 상태
    final liveAfter = _liveMap(
      wage: 110000,
      baseHourlyWage: 15000,
      breakMinutes: 30,
      nightAllowanceApplied: false,
      nightIncluded: true,
      taxDeductionType: 'income_3_3',
    );

    test('06-a A는 전 조건이 지원 당시 그대로다 (§10)', () {
      final d = WorkDetailHelper.resolve(aPromise, liveAfter);
      expect(WorkDetailHelper.wage(d), 100000);
      expect(WorkDetailHelper.baseHourlyWage(d), 12500, reason: '연장 단가');
      expect(WorkDetailHelper.breakMinutes(d), 60);
      expect(WorkDetailHelper.nightAllowanceApplied(d), true, reason: '야간수당');
      expect(WorkDetailHelper.taxDeductionType(d), 'none');
    });

    test('06-b B는 새 조건으로 약속받는다 (§10)', () {
      // B의 지원서는 수정 후 슬롯에서 서버가 복사한 값이다
      final bPromise = _app(
        wage: 110000,
        baseHourlyWage: 15000,
        breakMinutes: 30,
        nightAllowanceApplied: false,
        nightIncluded: true,
        taxDeductionType: 'income_3_3',
      );
      final d = WorkDetailHelper.resolve(bPromise, liveAfter);
      expect(WorkDetailHelper.wage(d), 110000);
      expect(WorkDetailHelper.baseHourlyWage(d), 15000);
      expect(WorkDetailHelper.breakMinutes(d), 30);
      expect(WorkDetailHelper.nightAllowanceApplied(d), false);
      expect(WorkDetailHelper.taxDeductionType(d), 'income_3_3');
    });

    test('06-c 같은 슬롯에서 두 사람의 조건이 다르다', () {
      final a = WorkDetailHelper.resolve(aPromise, liveAfter);
      final b = WorkDetailHelper.resolve(
          _app(wage: 110000, baseHourlyWage: 15000, breakMinutes: 30,
              nightAllowanceApplied: false),
          liveAfter);
      expect(WorkDetailHelper.baseHourlyWage(a) ==
          WorkDetailHelper.baseHourlyWage(b), false);
      expect(WorkDetailHelper.nightAllowanceApplied(a) ==
          WorkDetailHelper.nightAllowanceApplied(b), false);
    });
  });

  // ── §21 무회귀 ────────────────────────────────────────────────
  group('COMP-07 기존 계약 무회귀', () {
    test('07-a payroll 금액 스냅샷 chain 유지 (§21)', () {
      final fns = _src(_fnsPath);
      expect(
          fns.contains('snapshotWage: typeof appData.wage === "number" ? '
              'appData.wage : undefined,'),
          true);
      expect(
          fns.contains('const effectiveBaseWage = '
              '(snapshotWage != null && snapshotWage > 0) ? snapshotWage : d.baseWage;'),
          true);
    });

    test('07-b 기존 지원서를 덮어쓰지 않는다 (§21)', () {
      final fns = _src(_fnsPath);
      final start = fns.indexOf('export const callableUpdateSlotWorkDetails = onCall(');
      final end = fns.indexOf('export const ', start + 40);
      final body = fns.substring(start, end > start ? end : fns.length);
      expect(body.contains('buildCompensationSnapshot'), false,
          reason: '공고 수정은 기존 약속을 건드리지 않는다');
      expect(body.contains('collection("applications").doc('), false);
    });

    test('07-c 03H atomicity guard 유지 (§21)', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('if (!isSuperAdmin && mutatesWorkDetails && freshConfirmed > 0) {'),
          true);
      expect(fns.contains('identityWorkTypesToGuard.length > 0'), true);
    });

    test('07-d 03I.1 진입점 overlay 유지 (§21)', () {
      final code = _codeOf(_src(_contractSvc));
      expect('_withPromisedWage('.allMatches(code).length, 3);
    });
  });
}
