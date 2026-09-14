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

  /// 지원서가 가리키는 workDetail. **null이면 필드 자체가 없다** —
  /// callableApplyToTO는 클라이언트가 보냈을 때만 저장한다.
  final String? workDetailId;

  /// [POSTING-V2-03K] 슬롯 경로의 canonical immutable key. 역시 조건부 저장.
  final String? wdId;

  /// [POSTING-V2-03K.1] 항상 저장된다 — 키가 없을 때 보수적 범위를 정한다.
  final String? selectedWorkType;
  final bool hasSnapshot;
  const AppRow(this.status, this.workDetailId,
      {this.hasSnapshot = false, this.wdId, this.selectedWorkType});
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
  queries?.add(1); // 슬롯당 1회 — limit 없이 완전히 읽는다 (03K)
  final id = '${newWD['workType']}_${newWD['startTime']}_${newWD['endTime']}';
  // [POSTING-V2-03K] 매칭 키는 **슬롯에 저장된** old WD에서 가져온다.
  //   클라이언트 payload가 wdId를 되돌려주지 않아도 놓치지 않는다.
  final wdId = (oldWD['wdId'] ?? newWD['wdId']) as String?;
  return apps.any((a) {
    if (!_activeStatuses.contains(a.status)) return false;
    if (a.hasSnapshot) return false;
    // 어느 workDetail인지 특정할 근거가 아예 없으면 보수적으로 잠근다
    if (a.workDetailId == null && a.wdId == null) return true;
    return a.workDetailId == id ||
        a.workDetailId == newWD['workType'] ||
        (wdId != null && a.wdId == wdId);
  });
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
      // [POSTING-V2-03J.1 재작성] blanket 조건이 좁혀졌다(§16). 확인하려는
      //   것은 여전히 같다 — 확정자 판정이 freshData 기준으로 TX 안에 있다.
      expect(
          fns.contains('if (!isSuperAdmin && touchesUnverifiedFields && freshConfirmed > 0) {'),
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

  // ── 03K FLEX guard completeness ───────────────────────────────
  group('LEGACY-10 판정이 500건에서 잘리지 않는다', () {
    /// 같은 슬롯 안의 두 업무. A만 조건을 바꾼다.
    Map<String, dynamic> wdA({int breakMinutes = 60, String? wdId = 'wd_a'}) => {
          'workType': '피킹',
          'startTime': '09:00',
          'endTime': '18:00',
          if (wdId != null) 'wdId': wdId,
          'wage': 100000,
          'baseHourlyWage': null,
          'breakMinutes': breakMinutes,
          'nightAllowanceApplied': true,
          'taxDeductionType': 'none',
        };
    Map<String, dynamic> wdB({int breakMinutes = 60}) => {
          'workType': '검수',
          'startTime': '18:00',
          'endTime': '22:00',
          'wdId': 'wd_b',
          'wage': 100000,
          'baseHourlyWage': null,
          'breakMinutes': breakMinutes,
          'nightAllowanceApplied': true,
          'taxDeductionType': 'none',
        };

    List<AppRow> many(int n, {required bool hasSnapshot, String? workDetailId,
            String? wdId}) =>
        List.generate(
            n,
            (_) => AppRow('CONFIRMED', workDetailId,
                hasSnapshot: hasSnapshot, wdId: wdId));

    test('10-a 보호 관계가 501번째에 있어도 BLOCK (§12 case A)', () {
      final apps = [
        // 스냅샷을 가진 정상 cohort 600건이 앞에 있다
        ...many(600, hasSnapshot: true, workDetailId: '피킹_09:00_18:00'),
        const AppRow('CONFIRMED', '피킹_09:00_18:00'), // 레거시 — 마지막
      ];
      expect(
          legacyLocked(
              oldWD: wdA(), newWD: wdA(breakMinutes: 30), apps: apps),
          true,
          reason: '앞 500건에 가려 놓치면 안 된다');
    });

    test('10-b 다른 workDetail 관계 700건 — 대상 수정은 ALLOW (§12 case B)', () {
      final apps = many(700, hasSnapshot: false, workDetailId: '검수_18:00_22:00',
          wdId: 'wd_b');
      expect(
          legacyLocked(
              oldWD: wdA(), newWD: wdA(breakMinutes: 30), apps: apps),
          false,
          reason: 'B의 레거시가 A의 산정 조건을 잠그면 안 된다');
    });

    test('10-c 같은 슬롯 sibling granularity (§6)', () {
      // A에 레거시 관계, B에는 없음 → B의 조건 변경은 허용
      const onA = [AppRow('CONFIRMED', '피킹_09:00_18:00', wdId: 'wd_a')];
      expect(
          legacyLocked(oldWD: wdB(), newWD: wdB(breakMinutes: 30), apps: onA),
          false);
      // 같은 관계가 A의 조건 변경은 막는다
      expect(
          legacyLocked(oldWD: wdA(), newWD: wdA(breakMinutes: 30), apps: onA),
          true);
    });

    test('10-d identity 불명 legacy는 보수적 BLOCK (§12 case C)', () {
      // workDetailId도 wdId도 없다 — 어느 업무인지 복원할 근거가 없다
      const unknown = [AppRow('CONFIRMED', null)];
      expect(
          legacyLocked(oldWD: wdA(), newWD: wdA(breakMinutes: 30),
              apps: unknown),
          true);
      expect(
          legacyLocked(oldWD: wdB(), newWD: wdB(breakMinutes: 30),
              apps: unknown),
          true,
          reason: '같은 슬롯의 어느 업무도 특정할 수 없다');
    });

    test('10-e workType만 아는 legacy도 보수적 BLOCK (§3)', () {
      const byWorkType = [AppRow('CONFIRMED', '피킹')];
      expect(
          legacyLocked(oldWD: wdA(), newWD: wdA(breakMinutes: 30),
              apps: byWorkType),
          true);
      expect(
          legacyLocked(oldWD: wdB(), newWD: wdB(breakMinutes: 30),
              apps: byWorkType),
          false,
          reason: '업무명이 다르면 이 업무의 관계가 아니다');
    });

    test('10-f wdId로만 연결된 legacy도 잡는다 (§2)', () {
      // 클라이언트 payload에 wdId가 없어도 슬롯의 old WD에서 가져온다
      const byWdId = [AppRow('CONFIRMED', null, wdId: 'wd_a')];
      final newNoWdId = wdA(breakMinutes: 30, wdId: null);
      expect(legacyLocked(oldWD: wdA(), newWD: newNoWdId, apps: byWdId), true);
    });

    test('10-g 정상 snapshot cohort만 있으면 ALLOW (§9)', () {
      final apps = many(800, hasSnapshot: true, workDetailId: '피킹_09:00_18:00',
          wdId: 'wd_a');
      expect(
          legacyLocked(oldWD: wdA(), newWD: wdA(breakMinutes: 30), apps: apps),
          false,
          reason: '기존 worker는 자기 스냅샷으로 계산된다');
    });

    test('10-h 4개 active 상태 모두 잠근다 / 종료 상태는 아니다 (§4)', () {
      for (final st in ['PENDING', 'INVITED', 'CONTRACT_PENDING', 'CONFIRMED']) {
        expect(
            legacyLocked(
                oldWD: wdA(),
                newWD: wdA(breakMinutes: 30),
                apps: [AppRow(st, '피킹_09:00_18:00')]),
            true,
            reason: st);
      }
      for (final st in ['REJECTED', 'CANCELED', 'AUTO_CANCELED', 'EXPIRED']) {
        expect(
            legacyLocked(
                oldWD: wdA(),
                newWD: wdA(breakMinutes: 30),
                apps: [AppRow(st, '피킹_09:00_18:00')]),
            false,
            reason: st);
      }
    });

    test('10-i 보호 필드 무변경이면 관계 조회 0 (§10)', () {
      final q = <int>[];
      legacyLocked(
        oldWD: wdA(),
        newWD: wdA(), // 아무것도 안 바뀜
        apps: many(900, hasSnapshot: false, workDetailId: '피킹_09:00_18:00'),
        queries: q,
      );
      expect(q, isEmpty);
    });

    // ── 서버 배선 ──
    test('10-j 서버 조회에 limit이 없다 (§5)', () {
      final body = _codeOf(
          _bodyOf(_src(_fnsPath), 'const assertNoLegacyCompensationLock = async ('));
      expect(body.contains('.limit('), false,
          reason: '잘라 읽으면 그 뒤 레거시를 놓쳐 fail-open이 된다');
      expect(body.contains('.where("slotId", "==", checkSlotId)'), true,
          reason: '범위는 슬롯 하나로 이미 좁다');
    });

    test('10-k 식별 불가 지원서를 보수적으로 취급한다 (§3)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_fnsPath), 'const assertNoLegacyCompensationLock = async (')));
      expect(
          body.contains('if (typeof a.workDetailId !== "string" && '
              'typeof a.wdId !== "string") return true;'),
          true);
    });

    test('10-l 매칭 키를 슬롯의 old WD에서 가져온다 (§2)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_fnsPath), 'const assertNoLegacyCompensationLock = async (')));
      expect(body.contains('wdId: (ow["wdId"] ?? nw["wdId"]) as string | undefined,'),
          true,
          reason: '클라이언트 payload만 믿으면 wdId로만 연결된 관계를 놓친다');
    });

    test('10-m 기존 canonical message를 그대로 쓴다 (§13)', () {
      final body = _bodyOf(
          _src(_fnsPath), 'const assertNoLegacyCompensationLock = async (');
      expect(
          body.contains('"이 공고에는 이전 버전의 지원 기록이 있어 일부 급여 산정 조건을 " +'),
          true);
    });

    test('10-n SINGLE/BATCH가 같은 헬퍼를 쓴다 (§7)', () {
      final fns = _src(_fnsPath);
      expect('await assertNoLegacyCompensationLock('.allMatches(fns).length, 2);
      expect('const assertNoLegacyCompensationLock = async ('.allMatches(fns).length,
          1, reason: '구현이 하나이므로 진입점이 달라도 결과가 같다');
    });

    test('10-o 다른 FLEX guard는 건드리지 않았다 (§11)', () {
      final fns = _src(_fnsPath);
      // identity guard — exact key + limit(1)
      expect(fns.contains('.where("workDetailId", "==", compositeId)'), true);
      // requiredCount guard — aggregate count
      expect(fns.contains('.count()'), true);
    });

    test('10-p CONTRACT 경로 무회귀 (§16)', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('const relationWorkTypes = [...new Set(['), true,
          reason: '03J.4 CONTRACT 구조가 그대로다');
      expect(fns.contains('legacyLockTargets.length > 0'), true);
    });
  });

  // ── 03K.1 client granularity ──────────────────────────────────
  group('LEGACY-11 client가 서버와 같은 단위로 본다', () {
    const editPath =
        'lib/screens/business_admin/to_management/edit_to_screen.dart';
    const cohort = ['PENDING', 'INVITED', 'CONTRACT_PENDING', 'CONFIRMED'];

    /// 편집 대상 업무 한 건.
    ({String id, String workType, String? wdId}) work(
            String workType, String start, String end, {String? wdId}) =>
        (id: '${workType}_${start}_$end', workType: workType, wdId: wdId);

    /// `_showWageGuardWarning`의 레거시 차단 판정 replica.
    ///
    /// [changed]는 보호 조건이 바뀐 **변경 전** 업무들이다.
    bool clientLegacyBlock({
      required List<({String id, String workType, String? wdId})> changed,
      required List<AppRow> apps,
      bool isSlotMode = false,
    }) {
      if (changed.isEmpty) return false;
      final active =
          apps.where((a) => cohort.contains(a.status) && !a.hasSnapshot);
      bool boundTo(AppRow a, ({String id, String workType, String? wdId}) w) {
        final hasKey = a.workDetailId != null || a.wdId != null;
        if (!hasKey) return isSlotMode || a.selectedWorkType == w.workType;
        // _appMatchesWork와 같은 세 가지 매칭
        if (a.workDetailId == w.id) return true;
        if (a.workDetailId == w.workType) return true;
        if (w.wdId != null && a.wdId == w.wdId) return true;
        return false;
      }

      return changed.any((w) => active.any((a) => boundTo(a, w)));
    }

    final wdA = work('피킹', '09:00', '18:00', wdId: 'wd_a');
    final wdB = work('검수', '18:00', '22:00', wdId: 'wd_b');
    // 같은 업무명 다른 시간대 (§7)
    final packA = work('포장', '09:00', '18:00', wdId: 'wd_pa');
    final packB = work('포장', '18:00', '22:00', wdId: 'wd_pb');

    test('11-a A에 레거시, B 조건 변경 → ALLOW (§5)', () {
      expect(
          clientLegacyBlock(
            changed: [wdB],
            apps: const [
              AppRow('CONFIRMED', '피킹_09:00_18:00', wdId: 'wd_a'),
            ],
          ),
          false,
          reason: '서버가 허용하는 것을 client가 먼저 막으면 안 된다');
    });

    test('11-b A에 레거시, A 조건 변경 → BLOCK (§6)', () {
      expect(
          clientLegacyBlock(
            changed: [wdA],
            apps: const [
              AppRow('CONFIRMED', '피킹_09:00_18:00', wdId: 'wd_a'),
            ],
          ),
          true);
    });

    test('11-c 같은 workType 다른 wdId — modern은 정확히 가른다 (§7)', () {
      const onPackA = [
        AppRow('CONFIRMED', '포장_09:00_18:00', wdId: 'wd_pa'),
      ];
      expect(clientLegacyBlock(changed: [packB], apps: onPackA), false);
      expect(clientLegacyBlock(changed: [packA], apps: onPackA), true);
    });

    test('11-d workType만 아는 레거시 — 같은 이름은 전부 BLOCK (§7)', () {
      const byWorkType = [AppRow('CONFIRMED', '포장')];
      expect(clientLegacyBlock(changed: [packA], apps: byWorkType), true);
      expect(clientLegacyBlock(changed: [packB], apps: byWorkType), true);
      expect(clientLegacyBlock(changed: [wdB], apps: byWorkType), false,
          reason: '업무명이 다르면 이 업무의 관계가 아니다');
    });

    test('11-e identity 키가 아예 없으면 보수적 BLOCK (§8)', () {
      const noKey = [AppRow('CONFIRMED', null, selectedWorkType: '피킹')];
      // 마스터 경로 — 서버 쿼리가 업무명으로 좁혀지므로 업무명 범위까지
      expect(clientLegacyBlock(changed: [wdA], apps: noKey), true);
      expect(clientLegacyBlock(changed: [wdB], apps: noKey), false);
      // 슬롯 경로 — 서버가 slotId로만 좁히므로 슬롯 전체가 보수적 범위
      expect(
          clientLegacyBlock(changed: [wdB], apps: noKey, isSlotMode: true),
          true);
    });

    test('11-f 스냅샷 cohort만 있으면 차단하지 않는다 (§10)', () {
      final apps = List.generate(
          50,
          (_) => const AppRow('CONFIRMED', '피킹_09:00_18:00',
              hasSnapshot: true, wdId: 'wd_a'));
      expect(clientLegacyBlock(changed: [wdA], apps: apps), false,
          reason: '경고는 띄우되 저장은 허용하는 경로다');
    });

    test('11-g 종료 상태 레거시는 차단하지 않는다 (§9)', () {
      for (final st in ['REJECTED', 'CANCELED', 'AUTO_CANCELED', 'EXPIRED']) {
        expect(
            clientLegacyBlock(
                changed: [wdA],
                apps: [AppRow(st, '피킹_09:00_18:00', wdId: 'wd_a')]),
            false,
            reason: st);
      }
    });

    test('11-h 4개 active 상태 모두 차단한다 (§9)', () {
      for (final st in cohort) {
        expect(
            clientLegacyBlock(
                changed: [wdA],
                apps: [AppRow(st, '피킹_09:00_18:00', wdId: 'wd_a')]),
            true,
            reason: st);
      }
    });

    test('11-i 보호 조건이 안 바뀌면 판정 자체가 없다 (§4)', () {
      expect(
          clientLegacyBlock(
            changed: const [],
            apps: const [AppRow('CONFIRMED', '피킹_09:00_18:00')],
          ),
          false,
          reason: 'requiredCount만 고친 경우 등 — 레거시 차단 대상이 아니다');
    });

    test('11-j client가 server 03K와 같은 결과를 낸다 (§16)', () {
      // 같은 관계 집합에 대해 두 replica가 같은 판정을 내는지 교차 확인
      const rels = [
        AppRow('CONFIRMED', '피킹_09:00_18:00', wdId: 'wd_a'),
      ];
      Map<String, dynamic> serverWD(String wt, String s, String e,
              {required int breakMinutes, String? wdId}) =>
          {
            'workType': wt, 'startTime': s, 'endTime': e,
            if (wdId != null) 'wdId': wdId,
            'wage': 100000, 'baseHourlyWage': null,
            'breakMinutes': breakMinutes,
            'nightAllowanceApplied': true, 'taxDeductionType': 'none',
          };
      // A 변경 — 양쪽 BLOCK
      expect(
          legacyLocked(
            oldWD: serverWD('피킹', '09:00', '18:00',
                breakMinutes: 60, wdId: 'wd_a'),
            newWD: serverWD('피킹', '09:00', '18:00',
                breakMinutes: 30, wdId: 'wd_a'),
            apps: rels,
          ),
          true);
      expect(clientLegacyBlock(changed: [wdA], apps: rels), true);
      // B 변경 — 양쪽 ALLOW
      expect(
          legacyLocked(
            oldWD: serverWD('검수', '18:00', '22:00',
                breakMinutes: 60, wdId: 'wd_b'),
            newWD: serverWD('검수', '18:00', '22:00',
                breakMinutes: 30, wdId: 'wd_b'),
            apps: rels,
          ),
          false);
      expect(clientLegacyBlock(changed: [wdB], apps: rels), false);
    });

    // ── 클라이언트 배선 ──
    test('11-k 기존 매칭 helper를 재사용한다 (§3)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(editPath), 'bool _appBoundToWork(')));
      expect(body.contains('return _appMatchesWork(app, work);'), true,
          reason: '비슷한 매칭 로직을 복제하지 않는다');
      expect(
          body.contains("final hasKey = app['workDetailId'] is String "
              "|| app['wdId'] is String;"),
          true);
      expect(
          body.contains("return widget.isSlotMode "
              "|| app['selectedWorkType'] == work.workType;"),
          true,
          reason: '슬롯/마스터의 보수적 범위가 서버와 같다');
    });

    test('11-l 슬롯 경로는 그 날짜의 지원서만 본다 (§14)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(editPath), 'Future<bool> _showWageGuardWarning(')));
      expect(
          body.contains('(!widget.isSlotMode || '
              'slotIds.any((id) => _isForSlot(m, id)))'),
          true);
      expect(
          body.contains('widget.isBatchMode '
              '? widget.batchSlots!.map((s) => s.id).toList() '
              ': [widget.slot!.id]'),
          true,
          reason: 'SINGLE/BATCH가 같은 매칭을 쓴다');
    });

    test('11-m 추가 조회를 만들지 않았다 (§12)', () {
      final body = _codeOf(
          _bodyOf(_src(editPath), 'Future<bool> _showWageGuardWarning('));
      expect('_applicationRelations.fresh()'.allMatches(body).length, 1);
      expect(body.contains('httpsCallable('), false,
          reason: '같은 fresh 응답을 재사용한다 — 추가 callable 없음');
    });

    test('11-n canonical message를 그대로 쓴다 (§6)', () {
      final body = _codeOf(
          _bodyOf(_src(editPath), 'Future<bool> _showWageGuardWarning('));
      expect(
          body.contains('이 공고에는 이전 버전의 지원 기록이 있어 일부 급여 산정 조건을 변경할 수 없습니다. '),
          true);
    });

    test('11-o 서버를 다시 고치지 않았다 (§15)', () {
      final body = _codeOf(
          _bodyOf(_src(_fnsPath), 'const assertNoLegacyCompensationLock = async ('));
      expect(body.contains('.limit('), false, reason: '03K 상태 그대로');
      expect(
          body.contains('wdId: (ow["wdId"] ?? nw["wdId"]) as string | undefined,'),
          true);
    });
  });

  // ── §11, §12 클라이언트 UX ────────────────────────────────────
  group('LEGACY-09 안내가 상황에 맞는다', () {
    const editPath =
        'lib/screens/business_admin/to_management/edit_to_screen.dart';

    test('09-a 레거시 케이스는 cohort 안내를 보여주지 않는다 (§11)', () {
      final body = _codeOf(
          _bodyOf(_src(editPath), 'Future<bool> _showWageGuardWarning('));
      final legacyIdx = body.indexOf('if (legacyChangedWorks.isNotEmpty) {');
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
          _bodyOf(_src(editPath),
              'List<WorkDetailData> _legacyProtectedChangedWorks(')));
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
