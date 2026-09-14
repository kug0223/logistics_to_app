// [POSTING-V2-03I.4] 레거시 지원자의 급여 조건 보호
//
// 03I.3 이후 지원서는 지원 시점 산정 조건을 스냅샷으로 갖는다. 그 이전
// 지원서에는 없어서, 급여를 계산할 때 공고의 **현재** 값을 읽는다.
// 과거 값을 복원할 근거가 없으므로 backfill하지 않는다(추정 금지).
//
// 대신 두 가지로 봉쇄한다:
//   1. 레거시도 **자기가 아는 것은 쓴다** — wage/wageType/startTime/endTime은
//      스냅샷 제도 이전에도 지원 시점 값으로 저장돼 있었다.
//   2. 모르는 5개 조건은, 그 사람이 아직 활성 관계를 갖고 있는 동안
//      **서버가 변경 자체를 막는다**. 관계가 끝나면 저절로 풀린다.
//
// 이것은 정상 정책이 아니라 legacy fallback이다. 스냅샷 cohort는 제한받지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/utils/work_detail_helper.dart';

const _fnsPath = 'functions/src/index.ts';
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
  String? wageType = 'daily',
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

Map<String, dynamic> _liveMap({
  required int wage,
  String wageType = 'daily',
  int? baseHourlyWage,
  int breakMinutes = 0,
  bool nightAllowanceApplied = true,
  String taxDeductionType = 'none',
  String startTime = '09:00',
  String endTime = '18:00',
}) =>
    {
      '피킹_09:00_18:00': {
        'wage': wage,
        'wageType': wageType,
        if (baseHourlyWage != null) 'baseHourlyWage': baseHourlyWage,
        'breakMinutes': breakMinutes,
        'nightAllowanceApplied': nightAllowanceApplied,
        'taxDeductionType': taxDeductionType,
        'startTime': startTime,
        'endTime': endTime,
      },
    };

// ── 서버 guard replica ──────────────────────────────────────────
const _protected = [
  'baseHourlyWage',
  'breakMinutes',
  'nightAllowanceApplied',
  'nightIncluded',
  'taxDeductionType',
];
const _activeStatuses = [
  'PENDING',
  'INVITED',
  'CONTRACT_PENDING',
  'CONFIRMED',
];

class AppRow {
  final String status;
  final String workDetailId;
  final bool hasSnapshot;
  const AppRow(this.status, this.workDetailId, {this.hasSnapshot = false});
}

bool _compChanged(Map<String, dynamic> oldWD, Map<String, dynamic> newWD) =>
    _protected.any((f) => oldWD[f] != newWD[f]);

/// assertNoLegacyCompensationLock replica.
/// 차단이면 true, 허용이면 false. [queries]로 실제 조회 횟수를 센다.
bool legacyLocked({
  required Map<String, dynamic> oldWD,
  required Map<String, dynamic> newWD,
  required List<AppRow> apps,
  List<int>? queries,
}) {
  if (!_compChanged(oldWD, newWD)) return false; // 조회하지 않는다
  queries?.add(1);
  final id = '${newWD['workType']}_${newWD['startTime']}_${newWD['endTime']}';
  return apps.any((a) =>
      _activeStatuses.contains(a.status) &&
      !a.hasSnapshot &&
      (a.workDetailId == id || a.workDetailId == newWD['workType']));
}

Map<String, dynamic> _wd({
  int? baseHourlyWage,
  int breakMinutes = 60,
  bool nightAllowanceApplied = true,
  String taxDeductionType = 'none',
  int wage = 100000,
}) =>
    {
      'workType': '피킹',
      'startTime': '09:00',
      'endTime': '18:00',
      'wage': wage,
      'baseHourlyWage': baseHourlyWage,
      'breakMinutes': breakMinutes,
      'nightAllowanceApplied': nightAllowanceApplied,
      'taxDeductionType': taxDeductionType,
    };

void main() {
  // ── §2 legacy 정의 ────────────────────────────────────────────
  group('LEGACY-01 legacy 판정', () {
    test('01-a nightAllowanceApplied 존재로 갈린다 (§2)', () {
      expect(_app(wage: 100000).hasCompensationSnapshot, false);
      expect(
          _app(wage: 100000, nightAllowanceApplied: true)
              .hasCompensationSnapshot,
          true);
    });

    test('01-b 서버도 같은 필드로 판정한다 (§2)', () {
      final fns = _src(_fnsPath);
      expect(
          fns.contains('if (typeof a.nightAllowanceApplied === "boolean") return false;'),
          true,
          reason: '클라이언트 hasCompensationSnapshot과 같은 기준');
    });

    test('01-c 별도 migration/version 필드를 만들지 않았다 (§2)', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('compensationSnapshotVersion'), false);
      expect(fns.contains('legacyMigrated'), false);
      final model = _codeOf(_src('lib/models/core/application_model.dart'));
      expect(model.contains('snapshotVersion'), false);
    });
  });

  // ── §4, §16 레거시가 아는 값 ──────────────────────────────────
  group('LEGACY-02 레거시도 자기가 아는 것은 쓴다', () {
    // [§4 부분 적용] wage/wageType은 적용했다. startTime/endTime은 적용하지
    // 않았다 — 근무시간은 임금 조건이 아니라 운영 일정이고, 이 앱에는
    // "관리자가 시간을 바꾸면 지각·조퇴 경계도 움직인다"는 기존 계약이 있다
    // (admin_home_attendance_effective_time_test). 완료 보고에 명시했다.
    test('02-a wage/wageType은 application 우선 (§4)', () {
      final legacy = _app(
        wage: 100000,
        wageType: 'daily',
        startTime: '09:00',
        endTime: '18:00',
      );
      final live = _liveMap(wage: 110000, wageType: 'hourly');
      final d = WorkDetailHelper.resolve(legacy, live);
      expect(WorkDetailHelper.wage(d), 100000, reason: '모집 임금이 올라도 약속은 그대로');
      expect(WorkDetailHelper.wageType(d), 'daily');
    });

    test('02-a2 근무시간은 현재 정의를 따른다 (기존 계약 유지)', () {
      final legacy = _app(wage: 100000, startTime: '09:00', endTime: '18:00');
      final live = _liveMap(wage: 100000, startTime: '10:00', endTime: '19:00');
      // 키가 약속 시간과 다르면 workType 단독 폴백으로 잡힌다
      live['피킹'] = live.remove('피킹_09:00_18:00')!;
      expect(WorkDetailHelper.effectiveStart(legacy, live), '10:00');
      expect(WorkDetailHelper.effectiveEnd(legacy, live), '19:00');
    });

    test('02-b 모르는 5개는 현재 값이 남는다 — backfill 금지 (§5)', () {
      final legacy = _app(wage: 100000);
      expect(legacy.promisedCompensation.containsKey('breakMinutes'), false);
      expect(legacy.promisedCompensation.containsKey('baseHourlyWage'), false);
      expect(
          legacy.promisedCompensation.containsKey('nightAllowanceApplied'), false);
      final d = WorkDetailHelper.resolve(
          legacy, _liveMap(wage: 110000, breakMinutes: 30, baseHourlyWage: 15000));
      expect(WorkDetailHelper.breakMinutes(d), 30, reason: 'legacy fallback');
      expect(WorkDetailHelper.baseHourlyWage(d), 15000);
    });

    test('02-c resolve가 더 이상 레거시를 통째로 live로 돌리지 않는다 (§4)', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_helperPath), 'static Map<String, dynamic>? resolve(')));
      expect(body.contains('final promised = app.promisedCompensation;'), true);
      expect(body.contains('if (promised == null) return live;'), false,
          reason: '03I.3의 전량 폴백이 남아 있으면 안 된다');
      expect(body.contains('return {...live, ...promised};'), true);
    });

    test('02-d 계약서도 레거시가 아는 값을 쓴다 (§16)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_contractSvc), 'WorkDetailData _withPromisedWage(')));
      final legacyIdx = body.indexOf('if (!application.hasCompensationSnapshot) {');
      expect(legacyIdx, greaterThan(-1));
      // legacy 분기만 잘라낸다 (스냅샷 분기로 넘어가지 않도록)
      final branchEnd = body.indexOf('} return workDetail.copyWith(', legacyIdx);
      expect(branchEnd, greaterThan(legacyIdx));
      final legacyBranch = body.substring(legacyIdx, branchEnd);
      expect(legacyBranch.contains('wage: promisedWage,'), true);
      expect(legacyBranch.contains('wageType: promisedType ?? workDetail.wageType,'),
          true);
      // 모르는 조건은 건드리지 않는다 — 현재 값을 과거 약속이라 하지 않는다
      expect(legacyBranch.contains('breakMinutes:'), false);
      expect(legacyBranch.contains('nightAllowanceApplied:'), false);
      expect(legacyBranch.contains('baseHourlyWage:'), false);
      // 근무시간도 임금 조건이 아니므로 건드리지 않는다
      expect(legacyBranch.contains('startTime:'), false);
    });
  });

  // ── §3, §6, §13 guard 동작 ────────────────────────────────────
  group('LEGACY-03 활성 레거시가 있으면 5개 조건을 막는다', () {
    final oldWD = _wd(breakMinutes: 60, nightAllowanceApplied: true);

    for (final st in ['PENDING', 'INVITED', 'CONTRACT_PENDING', 'CONFIRMED']) {
      test('03-a $st legacy → breakMinutes 변경 거부 (§3, §6)', () {
        expect(
            legacyLocked(
              oldWD: oldWD,
              newWD: _wd(breakMinutes: 30),
              apps: [AppRow(st, '피킹_09:00_18:00')],
            ),
            true);
      });
    }

    test('03-b 5개 필드 각각이 보호된다 (§6)', () {
      final cases = <String, Map<String, dynamic>>{
        'baseHourlyWage': _wd(baseHourlyWage: 15000),
        'breakMinutes': _wd(breakMinutes: 30),
        'nightAllowanceApplied': _wd(nightAllowanceApplied: false),
        'taxDeductionType': _wd(taxDeductionType: 'income_3_3'),
      };
      cases.forEach((name, newWD) {
        expect(
            legacyLocked(
              oldWD: oldWD,
              newWD: newWD,
              apps: const [AppRow('CONFIRMED', '피킹_09:00_18:00')],
            ),
            true,
            reason: name);
      });
    });

    test('03-c 종료된 기록만 있으면 허용 — 영구 잠금 금지 (§3, §13)', () {
      for (final st in ['REJECTED', 'CANCELED', 'AUTO_CANCELED', 'EXPIRED']) {
        expect(
            legacyLocked(
              oldWD: oldWD,
              newWD: _wd(breakMinutes: 30),
              apps: [AppRow(st, '피킹_09:00_18:00')],
            ),
            false,
            reason: st);
      }
    });

    test('03-d 스냅샷 cohort는 제한받지 않는다 (§1, §12)', () {
      expect(
          legacyLocked(
            oldWD: oldWD,
            newWD: _wd(breakMinutes: 30, baseHourlyWage: 15000),
            apps: const [
              AppRow('CONFIRMED', '피킹_09:00_18:00', hasSnapshot: true),
              AppRow('PENDING', '피킹_09:00_18:00', hasSnapshot: true),
            ],
          ),
          false,
          reason: '자기 조건으로 계산하므로 공고를 바꿔도 영향이 없다');
    });

    test('03-e 다른 업무의 레거시는 막지 않는다', () {
      expect(
          legacyLocked(
            oldWD: oldWD,
            newWD: _wd(breakMinutes: 30),
            apps: const [AppRow('CONFIRMED', '포장_14:00_18:00')],
          ),
          false);
    });

    test('03-f 레거시 workDetailId(업무명 단독)도 매칭된다', () {
      expect(
          legacyLocked(
            oldWD: oldWD,
            newWD: _wd(breakMinutes: 30),
            apps: const [AppRow('CONFIRMED', '피킹')],
          ),
          true,
          reason: '구 앱이 저장한 형태');
    });
  });

  // ── §7 허용되는 변경 ──────────────────────────────────────────
  group('LEGACY-04 아는 값은 계속 바꿀 수 있다', () {
    test('04-a wage만 바꾸면 레거시가 있어도 허용 (§7)', () {
      expect(
          legacyLocked(
            oldWD: _wd(wage: 100000),
            newWD: _wd(wage: 110000),
            apps: const [AppRow('CONFIRMED', '피킹_09:00_18:00')],
          ),
          false,
          reason: '모집 임금 변경은 향후 cohort를 위한 것이다');
    });

    test('04-b 그때 기존 레거시의 약속은 그대로다 (§7 전제)', () {
      final legacy = _app(wage: 100000, wageType: 'daily');
      final d = WorkDetailHelper.resolve(legacy, _liveMap(wage: 110000));
      expect(WorkDetailHelper.wage(d), 100000);
      expect(WorkDetailHelper.wageType(d), 'daily');
    });

    test('04-c wageType 변경도 기존 worker를 바꾸지 않는다 (§7)', () {
      final legacy = _app(wage: 100000, wageType: 'daily');
      final d = WorkDetailHelper.resolve(
          legacy, _liveMap(wage: 100000, wageType: 'hourly'));
      expect(WorkDetailHelper.wageType(d), 'daily');
    });
  });

  // ── §8, §10 서버 canonical guard ──────────────────────────────
  group('LEGACY-05 서버가 최종 방어한다', () {
    test('05-a SINGLE / BATCH 두 경로 모두 (§8)', () {
      final fns = _src(_fnsPath);
      expect('await assertNoLegacyCompensationLock('.allMatches(fns).length, 2,
          reason: '진입점이 달라도 같은 결과여야 한다');
    });

    test('05-b 재시도마다 재실행된다 (§10)', () {
      final fns = _src(_fnsPath);
      // checkActiveApplications 바로 다음 — 둘 다 transaction callback 안이다
      final single = fns.indexOf(
          'await checkActiveApplications(toId, slotId!, newIdSet, oldWDs);');
      final singleGuard =
          fns.indexOf('await assertNoLegacyCompensationLock(', single);
      expect(singleGuard, greaterThan(single));
      expect(singleGuard - single, lessThan(400),
          reason: '같은 블록 안에 있어야 재시도 때 함께 다시 돈다');
    });

    test('05-c 클라이언트 경고만으로 끝내지 않는다 (§8)', () {
      final fns = _src(_fnsPath);
      expect(
          fns.contains('"이 공고에는 이전 버전의 지원 기록이 있어 일부 급여 산정 조건을 " +'),
          true);
      expect(fns.contains('throw new HttpsError(\n            "failed-precondition",'),
          true);
    });

    test('05-d 03H atomicity 구조를 깨지 않았다 (§10)', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('const ACTIVE_STATUSES_WITH_CONFIRMED = '
          '["PENDING", "INVITED", "CONTRACT_PENDING", "CONFIRMED"];'), true);
      expect(fns.contains('if (!isSuperAdmin && mutatesWorkDetails && freshConfirmed > 0) {'),
          true);
    });
  });

  // ── §9, §19 비용 ──────────────────────────────────────────────
  group('LEGACY-06 정상 경로 비용 0', () {
    test('06-a 보호 필드가 안 바뀌면 조회하지 않는다 (§9)', () {
      final q = <int>[];
      legacyLocked(
        oldWD: _wd(wage: 100000),
        newWD: _wd(wage: 110000), // 금액만 변경
        apps: const [AppRow('CONFIRMED', '피킹_09:00_18:00')],
        queries: q,
      );
      expect(q.length, 0, reason: '정상 cohort는 추가 read가 없다');
    });

    test('06-b 바뀐 경우에만 1회 조회 (§9)', () {
      final q = <int>[];
      legacyLocked(
        oldWD: _wd(breakMinutes: 60),
        newWD: _wd(breakMinutes: 30),
        apps: const [AppRow('CONFIRMED', '피킹_09:00_18:00')],
        queries: q,
      );
      expect(q.length, 1);
    });

    test('06-c 서버도 같은 순서다 — early return이 조회보다 앞 (§9)', () {
      final fns = _src(_fnsPath);
      final body = _bodyOf(fns, 'const assertNoLegacyCompensationLock = async (');
      final earlyReturn = body.indexOf('if (touched.length === 0) return;');
      final query = body.indexOf('db.collection("applications")');
      expect(earlyReturn, greaterThan(-1));
      expect(query, greaterThan(earlyReturn));
    });

    test('06-d 슬롯당 1 query — workDetail마다 반복하지 않는다 (§9)', () {
      final body = _codeOf(
          _bodyOf(_src(_fnsPath), 'const assertNoLegacyCompensationLock = async ('));
      expect('db.collection("applications")'.allMatches(body).length, 1);
      expect(body.contains('.where("status", "in", ACTIVE_STATUSES_WITH_CONFIRMED)'),
          true,
          reason: '4상태를 한 번에 — 상태별 query를 만들지 않는다');
    });
  });

  // ── §11, §12 클라이언트 UX ────────────────────────────────────
  group('LEGACY-09 안내가 상황에 맞는다', () {
    const editPath =
        'lib/screens/business_admin/to_management/edit_to_screen.dart';

    test('09-a 레거시 케이스는 cohort 안내를 보여주지 않는다 (§11)', () {
      final body = _codeOf(
          _bodyOf(_src(editPath), 'Future<bool> _showWageGuardWarning('));
      final legacyIdx = body.indexOf('if (hasActiveLegacy &&');
      final dialogIdx = body.indexOf('showDialog<bool>(');
      expect(legacyIdx, greaterThan(-1));
      expect(dialogIdx, greaterThan(legacyIdx),
          reason: '레거시면 cohort 다이얼로그에 도달하지 않는다');
      expect(body.substring(legacyIdx, dialogIdx).contains('return false;'), true);
    });

    test('09-b 문구가 서버 메시지와 같다 (§11)', () {
      final body = _codeOf(
          _bodyOf(_src(editPath), 'Future<bool> _showWageGuardWarning('));
      expect(
          body.contains('이 공고에는 이전 버전의 지원 기록이 있어 일부 급여 산정 조건을 변경할 수 없습니다. '),
          true);
      expect(body.contains('해당 지원 관계가 종료된 후 변경해 주세요.'), true);
    });

    test('09-c 보호 필드가 바뀔 때만 차단한다 (§7)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(editPath), 'bool _hasLegacyProtectedConditionChanged(')));
      for (final f in [
        'cur.breakMinutes != orig.breakMinutes',
        'cur.nightAllowanceApplied != orig.nightAllowanceApplied',
        'cur.nightIncluded != orig.nightIncluded',
        'cur.baseHourlyWage != orig.baseHourlyWage',
        'cur.taxDeductionType != orig.taxDeductionType',
      ]) {
        expect(body.contains(f), true, reason: f);
      }
      // 금액·급여유형은 레거시도 알고 있으므로 제한 대상이 아니다
      expect(body.contains('cur.wage != orig.wage'), false);
      expect(body.contains('cur.wageType != orig.wageType'), false);
    });

    test('09-d 정상 cohort 안내는 그대로 유지된다 (§12)', () {
      final body = _codeOf(
          _bodyOf(_src(editPath), 'Future<bool> _showWageGuardWarning('));
      expect(
          body.contains('임금이나 급여 산정 조건을 변경해도 기존 지원자의 지원 당시 조건은 유지됩니다. '),
          true);
      expect(body.contains("title: '임금 및 급여 산정 조건 변경',"), true);
    });

    test('09-e 추가 조회를 만들지 않았다 (§9)', () {
      final body = _codeOf(
          _bodyOf(_src(editPath), 'Future<bool> _showWageGuardWarning('));
      expect(body.contains('await _applicationRelations.fresh();'), true);
      expect('await '.allMatches(body).length, 2,
          reason: 'fresh() 1회 + showDialog 1회 — 새 조회 없음');
      expect(body.contains("m['nightAllowanceApplied'] == null"), true,
          reason: '같은 응답에서 레거시를 판별한다');
    });

    test('09-f 서버 거부 문구가 화면까지 도달한다 (§11)', () {
      final code = _codeOf(_src(editPath));
      expect(
          code.contains("const safeCodes = "
              "['failed-precondition', 'invalid-argument', 'not-found'];"),
          true,
          reason: 'legacy guard는 failed-precondition으로 온다');
      expect("_cfErrorMessage(e) ?? '수정에 실패했습니다'".allMatches(code).length, 3,
          reason: '저장 경로 3곳 모두');
    });
  });

  // ── §14, §15 전환 ─────────────────────────────────────────────
  group('LEGACY-07 재지원·업무변경 후 정상 cohort', () {
    test('07-a 재지원은 스냅샷을 새로 만든다 (§14)', () {
      final fns = _src(_fnsPath);
      // reactivateData에도 compensationSnapshot이 붙는다 (03I.3)
      expect('...compensationSnapshot,'.allMatches(fns).length, 2);
    });

    test('07-b 스냅샷이 생기면 제한 대상에서 빠진다 (§14, §15)', () {
      final before = AppRow('PENDING', '피킹_09:00_18:00');
      const after = AppRow('PENDING', '피킹_09:00_18:00', hasSnapshot: true);
      final oldWD = _wd(breakMinutes: 60);
      final newWD = _wd(breakMinutes: 30);
      expect(legacyLocked(oldWD: oldWD, newWD: newWD, apps: [before]), true);
      expect(legacyLocked(oldWD: oldWD, newWD: newWD, apps: const [after]), false);
    });

    test('07-c 업무 변경도 서버가 재스냅샷한다 (§15)', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('changedCompensation = buildCompensationSnapshot(newWD);'),
          true);
    });

    test('07-d 관계가 끝나면 저절로 풀린다 (§13)', () {
      final oldWD = _wd(breakMinutes: 60);
      final newWD = _wd(breakMinutes: 30);
      expect(
          legacyLocked(
              oldWD: oldWD,
              newWD: newWD,
              apps: const [AppRow('CONFIRMED', '피킹_09:00_18:00')]),
          true);
      // 같은 사람이 완료/취소되면
      expect(
          legacyLocked(
              oldWD: oldWD,
              newWD: newWD,
              apps: const [AppRow('CANCELED', '피킹_09:00_18:00')]),
          false,
          reason: '수동 해제 없이 풀려야 한다');
    });
  });

  // ── §21 범위 ──────────────────────────────────────────────────
  group('LEGACY-08 범위를 넘지 않았다', () {
    test('08-a 일괄 migration / backfill 없음 (§21)', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('migrateCompensation'), false);
      expect(fns.contains('backfillCompensation'), false);
    });

    test('08-b 기존 지원서를 수정하지 않는다 (§21)', () {
      final fns = _src(_fnsPath);
      final body = _codeOf(
          _bodyOf(fns, 'const assertNoLegacyCompensationLock = async ('));
      expect(body.contains('.update('), false);
      expect(body.contains('.set('), false);
      expect(body.contains('batch'), false);
    });

    test('08-c 03I.3 신규 cohort 동작 무회귀 (§1)', () {
      final fresh = _app(
        wage: 100000,
        baseHourlyWage: 12500,
        breakMinutes: 60,
        nightAllowanceApplied: true,
        taxDeductionType: 'none',
      );
      final d = WorkDetailHelper.resolve(
          fresh,
          _liveMap(
              wage: 110000,
              baseHourlyWage: 15000,
              breakMinutes: 30,
              nightAllowanceApplied: false,
              taxDeductionType: 'income_3_3'));
      expect(WorkDetailHelper.baseHourlyWage(d), 12500);
      expect(WorkDetailHelper.breakMinutes(d), 60);
      expect(WorkDetailHelper.nightAllowanceApplied(d), true);
      expect(WorkDetailHelper.taxDeductionType(d), 'none');
    });
  });
}
