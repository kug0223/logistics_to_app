// [POSTING-V2-03J.1] CONTRACT 공고 수정 — blanket에서 필드별 정책으로
//
// 03J READ에서 확인된 것:
//   · 서버는 `confirmed > 0 && "workDetails" in updates`만으로 전부 막았다.
//     값 비교가 아니라 키 존재였다.
//   · 그런데 기존 근무자의 약속은 03I 스냅샷이 이미 지키고 있다. CONTRACT도
//     예외가 아님을 코드로 확인했다(promisedWD = matchedWD, snapshotWage).
//     즉 그 잠금은 약속 보호가 아니라 운영 차단이었다.
//   · 다만 blanket이 실제로 덮고 있던 구멍이 셋 있었다:
//       1) identity guard가 CONFIRMED를 보지 않는다
//       2) wdId 교체가 아무 데서도 검증되지 않는다
//       3) 업무별 requiredCount 하한 guard가 없다
//     그래서 guard를 먼저 세우고 blanket을 마지막에 좁혔다.
//
// 최종 정책 (확정자 존재 시):
//   ALLOW  임금·산정 조건 / 하한 위 인원 변경 / 관계 없는 업무 추가·삭제
//   BLOCK  활성 관계 업무의 삭제·workType·시간·wdId 교체 /
//          하한 미만 인원 / 레거시 미스냅샷 조건 / 미검증 metadata

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';
const _editPath = 'lib/screens/business_admin/to_management/edit_to_screen.dart';

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

String _callableOf(String source, String name) {
  final start = source.indexOf('export const $name = onCall(');
  if (start == -1) throw StateError('$name 을 찾지 못함');
  var depth = 0;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') depth++;
    if (source[i] == ')') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$name 본문의 끝을 찾지 못함');
}

// ═══════════════════════════════════════════════════════════════
// callableUpdateTO 정책 replica
// ═══════════════════════════════════════════════════════════════

const _compensation = [
  'wage', 'wageType', 'baseHourlyWage', 'breakMinutes',
  'nightAllowanceApplied', 'nightIncluded', 'taxDeductionType',
];
const _legacyUnknown = [
  'baseHourlyWage', 'breakMinutes',
  'nightAllowanceApplied', 'nightIncluded', 'taxDeductionType',
];
const _nonPolicy = ['order', 'wdId'];
const _identityKeys = ['workType', 'startTime', 'endTime'];

const _identityStatuses = ['PENDING', 'INVITED', 'CONTRACT_PENDING', 'CONFIRMED'];
const _occupancy = ['CONFIRMED', 'CONTRACT_PENDING'];

class Rel {
  final String status;
  final String workType;
  final bool hasSnapshot;

  /// [POSTING-V2-03J.2] 지원서가 가리키는 업무. 신규는 compositeId,
  /// 레거시는 업무명만 저장한다. null이면 업무명만 아는 레거시로 본다.
  final String? workDetailId;

  const Rel(this.status, this.workType,
      {this.hasSnapshot = true, this.workDetailId});
}

Map<String, dynamic> wd({
  String workType = '포장',
  String startTime = '09:00',
  String endTime = '18:00',
  String? wdId = 'wd_pack',
  int wage = 100000,
  String wageType = 'daily',
  int? baseHourlyWage,
  int breakMinutes = 60,
  bool nightAllowanceApplied = true,
  String taxDeductionType = 'none',
  int requiredCount = 5,
  int order = 0,
  String? description,
}) =>
    {
      'workType': workType,
      'startTime': startTime,
      'endTime': endTime,
      if (wdId != null) 'wdId': wdId,
      'wage': wage,
      'wageType': wageType,
      if (baseHourlyWage != null) 'baseHourlyWage': baseHourlyWage,
      'breakMinutes': breakMinutes,
      'nightAllowanceApplied': nightAllowanceApplied,
      'taxDeductionType': taxDeductionType,
      'requiredCount': requiredCount,
      'order': order,
      if (description != null) 'description': description,
    };

String _id(Map<String, dynamic> w) =>
    '${w['workType']}_${w['startTime']}_${w['endTime']}';

/// 차단 사유. null이면 허용. [queries]로 관계 조회 횟수를 센다.
String? updateTOBlock({
  required List<Map<String, dynamic>> oldWDs,
  required List<Map<String, dynamic>> newWDs,
  required List<Rel> rels,
  bool sendsWorkDetails = true,
  List<int>? queries,
}) {
  if (!sendsWorkDetails) return null; // 제목만 수정 — 키 자체가 실리지 않는다

  final newIds = newWDs.map(_id).toSet();
  final identityWorkTypes = <String>[];
  final legacyLockWorkTypes = <String>[];
  final capacityReductions =
      <({String workType, String compositeId, int next})>[];
  var touchesUnverified = false;

  for (final o in oldWDs) {
    if (!newIds.contains(_id(o))) identityWorkTypes.add(o['workType'] as String);
  }
  for (final o in oldWDs) {
    final n = newWDs.where((d) => _id(d) == _id(o)).firstOrNull;
    if (n == null) continue;
    final workType = o['workType'] as String;

    if (o['wdId'] != null && n['wdId'] != o['wdId']) {
      identityWorkTypes.add(workType);
    }
    if (_legacyUnknown.any((f) => o[f] != n[f])) {
      legacyLockWorkTypes.add(workType);
    }
    final oc = (o['requiredCount'] as int?) ?? 0;
    final nc = (n['requiredCount'] as int?) ?? 0;
    if (nc < oc) {
      capacityReductions.add(
          (workType: workType, compositeId: _id(o), next: nc));
    }

    for (final k in {...o.keys, ...n.keys}) {
      if (_compensation.contains(k)) continue;
      if (_nonPolicy.contains(k)) continue;
      if (k == 'requiredCount') continue;
      if (_identityKeys.contains(k)) continue;
      if (o[k] != n[k]) touchesUnverified = true;
    }
  }

  final confirmed =
      rels.where((r) => _occupancy.contains(r.status)).length;

  // ── txEdit 판정 순서 ──
  if (touchesUnverified && confirmed > 0) return 'UNVERIFIED_FIELD';

  // [POSTING-V2-03J.2] workDetail 단위로 센다 — 같은 업무명의 다른 시간대는
  //   서로의 자리를 막지 않는다. 업무명만 아는 레거시는 보수적으로 포함한다.
  for (final c in capacityReductions) {
    queries?.add(1);
    final occupied = rels.where((r) {
      if (!_occupancy.contains(r.status)) return false;
      if (r.workType != c.workType) return false;
      final wdi = r.workDetailId;
      if (wdi == null) return true; // 레거시 — 시간대를 알 수 없다
      return wdi == c.compositeId || wdi == c.workType;
    }).length;
    if (c.next < occupied) return 'CAPACITY';
  }

  if (identityWorkTypes.isNotEmpty) {
    queries?.add(identityWorkTypes.length);
    final blocked = identityWorkTypes.any((wt) => rels
        .any((r) => _identityStatuses.contains(r.status) && r.workType == wt));
    if (blocked) return 'IDENTITY';
  }

  if (legacyLockWorkTypes.isNotEmpty) {
    queries?.add(legacyLockWorkTypes.length);
    final blocked = legacyLockWorkTypes.any((wt) => rels.any((r) =>
        _identityStatuses.contains(r.status) &&
        r.workType == wt &&
        !r.hasSnapshot));
    if (blocked) return 'LEGACY';
  }
  return null;
}

void main() {
  late final String updateTO = _callableOf(_src(_fnsPath), 'callableUpdateTO');

  // ── §25 behavior matrix ───────────────────────────────────────
  group('CONTRACT-01 확정자가 있어도 허용되는 것', () {
    const confirmedA = [Rel('CONFIRMED', '포장')];

    test('01-a wage만 변경 → ALLOW (§10, §11)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(wage: 100000)],
            newWDs: [wd(wage: 110000)],
            rels: confirmedA,
          ),
          isNull);
    });

    test('01-b 스냅샷 cohort의 baseHourlyWage 변경 → ALLOW (§10)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(baseHourlyWage: 12500)],
            newWDs: [wd(baseHourlyWage: 15000)],
            rels: confirmedA,
          ),
          isNull);
    });

    test('01-c 관계 없는 새 업무 추가 → ALLOW (§12)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd()],
            newWDs: [wd(), wd(workType: '검수', wdId: 'wd_insp', order: 1)],
            rels: confirmedA,
          ),
          isNull,
          reason: '새 업무 때문에 기존 확정자를 취소하게 만들지 않는다');
    });

    test('01-d 관계 없는 다른 업무 삭제 → ALLOW (§13)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(), wd(workType: '검수', wdId: 'wd_insp')],
            newWDs: [wd()],
            rels: confirmedA,
          ),
          isNull);
    });

    test('01-e 제목만 수정 → ALLOW (§3 무회귀)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd()],
            newWDs: [wd()],
            rels: confirmedA,
            sendsWorkDetails: false,
          ),
          isNull);
    });

    test('01-f 인원 5→4, occupied 3 → ALLOW (§8)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(requiredCount: 5)],
            newWDs: [wd(requiredCount: 4)],
            rels: const [
              Rel('CONFIRMED', '포장'),
              Rel('CONFIRMED', '포장'),
              Rel('CONTRACT_PENDING', '포장'),
            ],
          ),
          isNull);
    });

    test('01-g 인원 5→3, occupied 3 → ALLOW (경계)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(requiredCount: 5)],
            newWDs: [wd(requiredCount: 3)],
            rels: const [
              Rel('CONFIRMED', '포장'),
              Rel('CONFIRMED', '포장'),
              Rel('CONTRACT_PENDING', '포장'),
            ],
          ),
          isNull);
    });
  });

  group('CONTRACT-02 확정자가 있으면 막히는 것', () {
    const confirmedA = [Rel('CONFIRMED', '포장')];

    test('02-a 시간 변경 → BLOCK (§4, §14)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(startTime: '09:00')],
            newWDs: [wd(startTime: '10:00')],
            rels: confirmedA,
          ),
          'IDENTITY');
    });

    test('02-b workType 변경 → BLOCK (§14)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(workType: '포장')],
            newWDs: [wd(workType: '검수')],
            rels: confirmedA,
          ),
          'IDENTITY');
    });

    test('02-c 확정자가 붙은 업무 삭제 → BLOCK (§13)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd()],
            newWDs: const [],
            rels: confirmedA,
          ),
          'IDENTITY');
    });

    test('02-d wdId 교체 → BLOCK (§1)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(wdId: 'wd_pack')],
            newWDs: [wd(wdId: 'wd_other')],
            rels: confirmedA,
          ),
          'IDENTITY',
          reason: '같은 업무·같은 시간인데 식별자만 갈아끼우면 연결이 끊긴다');
    });

    test('02-e 인원 5→2, occupied 3 → BLOCK (§8)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(requiredCount: 5)],
            newWDs: [wd(requiredCount: 2)],
            rels: const [
              Rel('CONFIRMED', '포장'),
              Rel('CONFIRMED', '포장'),
              Rel('CONTRACT_PENDING', '포장'),
            ],
          ),
          'CAPACITY',
          reason: 'CONTRACT_PENDING도 자리를 차지한다');
    });

    test('02-f 레거시 + 미스냅샷 조건 변경 → BLOCK (§5)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(breakMinutes: 60)],
            newWDs: [wd(breakMinutes: 30)],
            rels: const [Rel('CONFIRMED', '포장', hasSnapshot: false)],
          ),
          'LEGACY');
    });

    test('02-g 레거시여도 wage/wageType은 ALLOW (§6)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(wage: 100000)],
            newWDs: [wd(wage: 110000)],
            rels: const [Rel('CONFIRMED', '포장', hasSnapshot: false)],
          ),
          isNull);
    });

    test('02-h 미검증 metadata 변경 → BLOCK (§15)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(description: null)],
            newWDs: [wd(description: '새 설명')],
            rels: confirmedA,
          ),
          'UNVERIFIED_FIELD',
          reason: 'blanket을 좁힌다는 이유만으로 metadata를 열지 않는다');
    });

    test('02-i 확정자가 없으면 metadata도 ALLOW', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(description: null)],
            newWDs: [wd(description: '새 설명')],
            rels: const [Rel('PENDING', '포장')],
          ),
          isNull);
    });

    test('02-j 허용+차단이 섞이면 전체 BLOCK (§18)', () {
      final r = updateTOBlock(
        oldWDs: [wd(wage: 100000, startTime: '09:00')],
        newWDs: [wd(wage: 110000, startTime: '10:00')],
        rels: confirmedA,
      );
      expect(r, 'IDENTITY', reason: 'wage만 몰래 저장하지 않는다');
    });
  });

  // ── 03J.2 §4·§5 workDetail 단위 capacity ──────────────────────
  group('CONTRACT-09 같은 업무명의 다른 시간대는 서로를 막지 않는다', () {
    // wdA 포장 09:00~18:00 occupied 2 / wdB 포장 18:00~22:00 occupied 0
    Map<String, dynamic> wdA({int requiredCount = 3}) =>
        wd(startTime: '09:00', endTime: '18:00', wdId: null,
            requiredCount: requiredCount);
    Map<String, dynamic> wdB({int requiredCount = 3}) =>
        wd(startTime: '18:00', endTime: '22:00', wdId: null,
            requiredCount: requiredCount, order: 1);

    const occupiedOnA = [
      Rel('CONFIRMED', '포장', workDetailId: '포장_09:00_18:00'),
      Rel('CONTRACT_PENDING', '포장', workDetailId: '포장_09:00_18:00'),
    ];

    test('09-a wdA 3→2 → ALLOW (occupied 2)', () {
      expect(
          updateTOBlock(
            oldWDs: [wdA(), wdB()],
            newWDs: [wdA(requiredCount: 2), wdB()],
            rels: occupiedOnA,
          ),
          isNull);
    });

    test('09-b wdA 3→1 → BLOCK (occupied 2)', () {
      expect(
          updateTOBlock(
            oldWDs: [wdA(), wdB()],
            newWDs: [wdA(requiredCount: 1), wdB()],
            rels: occupiedOnA,
          ),
          'CAPACITY');
    });

    test('09-c wdB 3→1 → ALLOW (§4 — A의 확정자가 B를 막지 않는다)', () {
      expect(
          updateTOBlock(
            oldWDs: [wdA(), wdB()],
            newWDs: [wdA(), wdB(requiredCount: 1)],
            rels: occupiedOnA,
          ),
          isNull);
    });

    test('09-d wdB 3→0 → ALLOW (§4)', () {
      expect(
          updateTOBlock(
            oldWDs: [wdA(), wdB()],
            newWDs: [wdA(), wdB(requiredCount: 0)],
            rels: occupiedOnA,
          ),
          isNull,
          reason: '03J.1의 workType 합산이었다면 여기서 막혔다');
    });

    test('09-e 다른 workType도 독립적이다 (§5)', () {
      final pack = wd(workType: '포장', wdId: null);
      final insp = wd(workType: '검수', wdId: null, order: 1);
      expect(
          updateTOBlock(
            oldWDs: [pack, insp],
            newWDs: [pack, wd(workType: '검수', wdId: null, order: 1,
                requiredCount: 1)],
            rels: const [
              Rel('CONFIRMED', '포장', workDetailId: '포장_09:00_18:00'),
              Rel('CONFIRMED', '포장', workDetailId: '포장_09:00_18:00'),
            ],
          ),
          isNull);
    });

    test('09-f PENDING/INVITED는 occupied가 아니다 (§3)', () {
      for (final st in ['PENDING', 'INVITED']) {
        expect(
            updateTOBlock(
              oldWDs: [wdA()],
              newWDs: [wdA(requiredCount: 0)],
              rels: [Rel(st, '포장', workDetailId: '포장_09:00_18:00')],
            ),
            isNull,
            reason: st);
      }
    });

    test('09-g CONFIRMED·CONTRACT_PENDING만 센다 (§3)', () {
      expect(
          updateTOBlock(
            oldWDs: [wdA()],
            newWDs: [wdA(requiredCount: 1)],
            rels: const [
              Rel('CONFIRMED', '포장', workDetailId: '포장_09:00_18:00'),
              Rel('CONTRACT_PENDING', '포장', workDetailId: '포장_09:00_18:00'),
            ],
          ),
          'CAPACITY');
    });

    test('09-h 업무명만 아는 레거시는 보수적으로 센다', () {
      expect(
          updateTOBlock(
            oldWDs: [wdA(), wdB()],
            newWDs: [wdA(), wdB(requiredCount: 0)],
            rels: const [Rel('CONFIRMED', '포장')], // workDetailId 없음
          ),
          'CAPACITY',
          reason: '어느 시간대인지 알 수 없으면 막는 쪽이 안전하다');
    });

    test('09-i 다른 workType의 관계 없는 업무 삭제는 허용 (§12)', () {
      final insp = wd(workType: '검수', wdId: null, order: 1);
      expect(
          updateTOBlock(
            oldWDs: [wdA(), insp],
            newWDs: [wdA()],
            rels: occupiedOnA,
          ),
          isNull);
    });

    // [발견] identity guard는 여전히 **업무명 단위**다. 같은 '포장'의 다른
    //   시간대를 지우면, 그 업무에 관계가 없어도 다른 시간대의 확정자 때문에
    //   막힌다. 03J.2는 capacity 축만 다뤘고 identity 축은 그대로 두었다 —
    //   완료 보고에 남긴다. 여기서는 현재 동작을 사실대로 고정한다.
    test('09-i2 같은 workType의 다른 시간대 삭제는 identity가 막는다', () {
      expect(
          updateTOBlock(
            oldWDs: [wdA(), wdB()],
            newWDs: [wdA()],
            rels: occupiedOnA,
          ),
          'IDENTITY',
          reason: 'identity guard granularity는 이번 범위 밖이다');
    });

    test('09-j race — occupied 증가 후 재시도에서 차단 (§13)', () {
      // 1차: wdB occupied 0
      expect(
          updateTOBlock(
            oldWDs: [wdA(), wdB()],
            newWDs: [wdA(), wdB(requiredCount: 0)],
            rels: occupiedOnA,
          ),
          isNull);
      // 재시도: 그 사이 wdB에 CONTRACT_PENDING이 생겼다
      expect(
          updateTOBlock(
            oldWDs: [wdA(), wdB()],
            newWDs: [wdA(), wdB(requiredCount: 0)],
            rels: const [
              ...occupiedOnA,
              Rel('CONTRACT_PENDING', '포장',
                  workDetailId: '포장_18:00_22:00'),
            ],
          ),
          'CAPACITY');
    });
  });

  // ── 03J.2 §1·§2·§6 counter 조사 결과 고정 ─────────────────────
  group('CONTRACT-10 CONTRACT에는 workDetail 카운터가 없다', () {
    test('10-a workDetailCounts는 슬롯 전용이다 (§2)', () {
      final fns = _src(_fnsPath);
      // 슬롯 생성에서만 초기화된다
      expect(
          fns.contains('workDetailCounts[wdId] = {confirmedCount: 0, pendingCount: 0};'),
          true);
      // CONTRACT(non-slot)는 workType 단위 카운터만 유지한다
      expect(fns.contains('workTypeConfirmedUpdate[`workTypeConfirmedCounts.\${wt}`]'),
          true);
      expect(fns.contains('toRef.update({ workDetailCounts'), false);
    });

    test('10-b CONTRACT workDetails에는 wdId가 생성되지 않는다 (§6)', () {
      final fns = _src(_fnsPath);
      final createTO = _callableOf(fns, 'callableCreateTO');
      expect(createTO.contains('generateWdId()'), false,
          reason: 'wdId 생성은 슬롯 경로에만 있다 — CONTRACT canonical key는 compositeId');
    });

    test('10-c 그래서 관계를 직접 본다 (§7)', () {
      final body = _flat(_codeOf(updateTO));
      expect(body.contains('const OCCUPANCY_STATUSES_TO = ["CONFIRMED", "CONTRACT_PENDING"];'),
          true);
      expect(body.contains('if (wdi === c.compositeId) return true;'), true);
      expect(body.contains('freshData.workTypeConfirmedCounts'), false,
          reason: '합산 카운터를 하한으로 쓰지 않는다');
    });

    test('10-d 기존 인덱스를 쓴다 — 새 인덱스 없음 (§8)', () {
      final body = _flat(_codeOf(updateTO));
      expect(
          body.contains('.where("toId", "==", toId) '
              '.where("selectedWorkType", "==", c.workType) '
              '.where("status", "in", OCCUPANCY_STATUSES_TO)'),
          true,
          reason: 'toId+selectedWorkType+status 인덱스가 이미 있다');
      final idx = _src('firestore.indexes.json');
      expect(idx.contains('"selectedWorkType"'), true);
    });
  });

  // ── §7 관계 종료 ──────────────────────────────────────────────
  group('CONTRACT-03 관계가 끝나면 풀린다', () {
    test('03-a 종료 상태만 남으면 identity 변경 ALLOW', () {
      for (final st in ['REJECTED', 'CANCELED', 'AUTO_CANCELED', 'EXPIRED']) {
        expect(
            updateTOBlock(
              oldWDs: [wd(startTime: '09:00')],
              newWDs: [wd(startTime: '10:00')],
              rels: [Rel(st, '포장')],
            ),
            isNull,
            reason: st);
      }
    });

    test('03-b 종료 상태만 남으면 legacy lock도 풀린다 (§7)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(breakMinutes: 60)],
            newWDs: [wd(breakMinutes: 30)],
            rels: const [Rel('CANCELED', '포장', hasSnapshot: false)],
          ),
          isNull);
    });
  });

  // ── §2, §8 서버 배선 ──────────────────────────────────────────
  group('CONTRACT-04 서버 guard 배선', () {
    test('04-a identity guard가 CONFIRMED를 본다 (§2)', () {
      final body = _flat(_codeOf(updateTO));
      expect(
          body.contains('const ACTIVE_STATUSES = '
              '["PENDING", "INVITED", "CONTRACT_PENDING", "CONFIRMED"];'),
          true,
          reason: 'blanket이 좁아진 뒤 확정 약속을 지키는 유일한 자리');
    });

    test('04-b wdId 교체를 identity로 접어 넣었다 (§1, 추가 쿼리 0)', () {
      final body = _flat(_codeOf(updateTO));
      expect(
          body.contains('if (typeof oldWdId === "string" && oldWdId.length > 0 && '
              'newWdId !== oldWdId) { identityWorkTypesToGuard.push(workType); }'),
          true);
    });

    // [POSTING-V2-03J.2 재작성] 03J.1은 freshData의 workType 합산 카운터를
    //   썼다. 같은 업무명의 다른 시간대가 섞이므로 workDetail 단위 관계
    //   조회로 바꿨다. 판정이 txEdit 안이라는 점은 그대로다.
    test('04-c 업무별 capacity가 workDetail 단위 관계를 본다 (§8, §9)', () {
      final body = _flat(_codeOf(updateTO));
      expect(body.contains('if (wdi === c.compositeId) return true;'), true);
      expect(body.contains('if (c.next < occupied) {'), true);
      expect(body.contains('freshData.workTypeConfirmedCounts'), false,
          reason: '합산 카운터를 하한으로 쓰지 않는다');
    });

    test('04-d occupied 정의가 CONFIRMED+CONTRACT_PENDING이다 (§3)', () {
      final body = _flat(_codeOf(updateTO));
      expect(
          body.contains('const OCCUPANCY_STATUSES_TO = '
              '["CONFIRMED", "CONTRACT_PENDING"];'),
          true,
          reason: 'PENDING/INVITED는 자리를 차지하지 않는다');
    });

    test('04-e CONTRACT legacy lock이 존재한다 (§5)', () {
      final body = _flat(_codeOf(updateTO));
      expect(body.contains('legacyLockWorkTypes.length > 0'), true);
      expect(
          body.contains('typeof d.data().nightAllowanceApplied !== "boolean"'),
          true,
          reason: '03I.4와 같은 판정 기준');
      expect(
          _src(_fnsPath).contains('"이 공고에는 이전 버전의 지원 기록이 있어 일부 급여 산정 조건을 " +'),
          true,
          reason: '기존 canonical message 재사용 (§19)');
    });

    test('04-f blanket이 미검증 필드로 좁혀졌다 (§16)', () {
      final body = _flat(_codeOf(updateTO));
      expect(
          body.contains('if (!isSuperAdmin && touchesUnverifiedFields && freshConfirmed > 0) {'),
          true);
      expect(body.contains('mutatesWorkDetails && freshConfirmed > 0'), false,
          reason: '옛 blanket이 남아 있으면 안 된다');
      // 메시지는 그대로 재사용한다
      expect(_src(_fnsPath).contains('"확정된 지원자가 있는 공고의 근무 조건은 수정할 수 없습니다."'),
          true);
    });
  });

  // ── §3, §9 atomicity ──────────────────────────────────────────
  group('CONTRACT-05 원자성', () {
    test('05-a 모든 새 guard가 txEdit 안이다 (§3, §9)', () {
      final tx = updateTO.substring(
          updateTO.indexOf('db.runTransaction(async (txEdit) => {'));
      for (final marker in [
        'touchesUnverifiedFields && freshConfirmed > 0',
        'capacityReductions.length > 0',
        'identityWorkTypesToGuard.length > 0',
        'legacyLockWorkTypes.length > 0',
      ]) {
        expect(tx.contains(marker), true, reason: '$marker 가 TX 밖에 있다');
      }
    });

    test('05-b read가 write보다 앞이다 (§9)', () {
      final tx = updateTO.substring(
          updateTO.indexOf('db.runTransaction(async (txEdit) => {'));
      final write = tx.indexOf('txEdit.update(toRef,');
      expect(write, greaterThan(-1));
      expect(tx.lastIndexOf('txEdit.get('), lessThan(write));
    });

    test('05-c 분류는 TX 밖, 판정은 TX 안이다 (§3)', () {
      final txStart = updateTO.indexOf('db.runTransaction(async (txEdit) => {');
      final outside = updateTO.substring(0, txStart);
      // 순수 비교만 밖에 있다 — 관계 조회는 없다
      expect(outside.contains('legacyLockWorkTypes.push(workType);'), true);
      expect(outside.contains('capacityReductions.push('), true);
      expect(outside.contains('db.collection("applications")'), false,
          reason: 'TX 밖 관계 조회는 재시도 때 다시 실행되지 않는다');
    });

    test('05-d race — 확정 생성 후 재시도에서 identity 차단 (§22)', () {
      // 1차: 관계 없음 → 통과할 뻔했으나
      expect(
          updateTOBlock(
            oldWDs: [wd(startTime: '09:00')],
            newWDs: [wd(startTime: '10:00')],
            rels: const [],
          ),
          isNull);
      // 재시도: 그 사이 확정이 생겼다 → 차단
      expect(
          updateTOBlock(
            oldWDs: [wd(startTime: '09:00')],
            newWDs: [wd(startTime: '10:00')],
            rels: const [Rel('CONFIRMED', '포장')],
          ),
          'IDENTITY');
    });

    test('05-e race — occupied 증가 후 재시도에서 capacity 차단 (§22)', () {
      expect(
          updateTOBlock(
            oldWDs: [wd(requiredCount: 5)],
            newWDs: [wd(requiredCount: 2)],
            rels: const [Rel('CONFIRMED', '포장'), Rel('CONFIRMED', '포장')],
          ),
          isNull);
      expect(
          updateTOBlock(
            oldWDs: [wd(requiredCount: 5)],
            newWDs: [wd(requiredCount: 2)],
            rels: const [
              Rel('CONFIRMED', '포장'),
              Rel('CONFIRMED', '포장'),
              Rel('CONTRACT_PENDING', '포장'),
            ],
          ),
          'CAPACITY');
    });
  });

  // ── §17 client 정렬 ───────────────────────────────────────────
  group('CONTRACT-06 client가 서버와 같은 결과를 낸다', () {
    test('06-a 옛 blanket preflight가 제거됐다 (§17)', () {
      final body = _codeOf(
          _bodyOf(_src(_editPath), 'String? _workChangeBlockReason('));
      expect(
          body.contains("if (confirmed > 0) {\n      return "
              "'확정된 지원자가 있는 공고의 근무 조건은 수정할 수 없습니다.';"),
          false,
          reason: '서버는 허용하는데 client가 먼저 막으면 안 된다');
    });

    test('06-b client identity가 CONFIRMED를 본다 (§17)', () {
      final code = _flat(_codeOf(_src(_editPath)));
      expect(
          code.contains('static const _toIdentityStatuses = [ AppStatus.pending, '
              'AppStatus.invited, AppStatus.contractPending, AppStatus.confirmed, ];'),
          true);
    });

    test('06-c client가 wdId 교체를 막는다 (§17)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_editPath), 'String? _workChangeBlockReason(')));
      expect(body.contains('if (orig.wdId != null && work.wdId != orig.wdId) {'),
          true);
    });

    test('06-d client가 업무별 capacity 하한을 본다 (§17)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_editPath), 'String? _workChangeBlockReason(')));
      expect(body.contains('if (work.requiredCount < orig.requiredCount) {'), true);
      // [POSTING-V2-03J.2 재작성] 업무명이 아니라 그 업무에 걸린 사람만 센다 —
      //   서버와 같은 매칭(_appMatchesWork)을 쓴다.
      expect(
          body.contains("_occupancyStatuses.contains(app['status']) && "
              '_appMatchesWork(app, work)'),
          true);
      expect(body.contains("app['selectedWorkType'] == work.workType) .length"),
          false,
          reason: 'workType 단위 합산이 남아 있으면 서버와 granularity가 어긋난다');
    });

    test('06-e 새 업무는 기존 약속과 무관하다 (§12)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_editPath), 'String? _workChangeBlockReason(')));
      expect(body.contains('if (orig == null) continue;'), true);
    });

    test('06-f legacy 안내는 WAGE-GUARD가 담당한다 (03I.4 무회귀)', () {
      final code = _codeOf(_src(_editPath));
      expect(code.contains('bool _hasLegacyProtectedConditionChanged()'), true);
      expect(code.contains('if (hasActiveLegacy && _hasLegacyProtectedConditionChanged()) {'),
          true);
    });
  });

  // ── §23 무회귀 ────────────────────────────────────────────────
  group('CONTRACT-07 기존 계약 무회귀', () {
    test('07-a totalRequired 하한 guard 유지 (§8)', () {
      final body = _flat(_codeOf(updateTO));
      expect(body.contains('if (!isSuperAdmin && "totalRequired" in finalUpdates) {'),
          true);
      expect(body.contains('newReq !== 0 && newReq < freshConfirmed'), true);
    });

    test('07-b date guard 유지 (§23)', () {
      final body = _flat(_codeOf(updateTO));
      expect(body.contains('if (isDateChange && !isSuperAdmin) {'), true);
      expect(
          body.contains('const DATE_ACTIVE_STATUSES = '
              '["PENDING", "INVITED", "CONTRACT_PENDING", "CONFIRMED"];'),
          true);
    });

    test('07-c FLEX 경로 무변경 (§23)', () {
      final slot = _callableOf(_src(_fnsPath), 'callableUpdateSlotWorkDetails');
      expect(slot.contains('await checkActiveApplications('), true);
      expect(slot.contains('await checkRequiredCountLowerBound('), true);
      expect(slot.contains('await assertNoLegacyCompensationLock('), true);
      expect(slot.contains('touchesUnverifiedFields'), false,
          reason: 'CONTRACT patch가 FLEX 정책을 건드리지 않는다');
    });

    test('07-d 03I 스냅샷 체계 무회귀 (§23)', () {
      final fns = _src(_fnsPath);
      expect(fns.contains('const effectiveWage = serverWage;'), true);
      expect('...compensationSnapshot,'.allMatches(fns).length, 2);
      expect(fns.contains('export function buildCompensationSnapshot('), true);
    });

    test('07-e harmless title-only 계약 유지 (§3, §23)', () {
      final body = _flat(_codeOf(_bodyOf(_src(_editPath), 'Future<void> _saveChanges(')));
      expect(body.contains('final workDetailsChanged = _hasWorkDetailsChanged();'),
          true);
      expect(
          body.contains("if (workDetailsChanged) ...{ "
              "'workDetails': WorkDetailData.listToFirestore(_workDetails), "
              "'totalRequired': totalRequired, },"),
          true);
    });
  });

  // ── §21 비용 ──────────────────────────────────────────────────
  group('CONTRACT-08 비용', () {
    test('08-a compensation-only edit은 관계 조회 0 (§21)', () {
      final q = <int>[];
      updateTOBlock(
        oldWDs: [wd(wage: 100000, baseHourlyWage: 12500)],
        newWDs: [wd(wage: 110000, baseHourlyWage: 12500)],
        rels: const [Rel('CONFIRMED', '포장')],
        queries: q,
      );
      expect(q, isEmpty, reason: 'identity 미변경 + legacy 조건 미변경');
    });

    // [POSTING-V2-03J.2 재작성] 정확한 granularity의 대가로, 인원을 **줄이는**
    //   업무에 대해서만 관계 조회가 1회 생긴다. 늘리거나 그대로면 0이다.
    test('08-b 인원을 줄일 때만 조회 1회 (§8)', () {
      final down = <int>[];
      updateTOBlock(
        oldWDs: [wd(requiredCount: 5)],
        newWDs: [wd(requiredCount: 4)],
        rels: const [Rel('CONFIRMED', '포장')],
        queries: down,
      );
      expect(down.length, 1);

      final up = <int>[];
      updateTOBlock(
        oldWDs: [wd(requiredCount: 5)],
        newWDs: [wd(requiredCount: 9)],
        rels: const [Rel('CONFIRMED', '포장')],
        queries: up,
      );
      expect(up, isEmpty, reason: '인원을 늘리는 것은 하한을 건드리지 않는다');
    });

    test('08-c identity 변경 시에만 조회 (§21)', () {
      final q = <int>[];
      updateTOBlock(
        oldWDs: [wd(startTime: '09:00')],
        newWDs: [wd(startTime: '10:00')],
        rels: const [],
        queries: q,
      );
      expect(q.length, 1);
    });

    test('08-d 전체 application full scan이 없다 (§21)', () {
      final body = _codeOf(updateTO);
      // 모든 관계 조회는 selectedWorkType으로 좁힌다
      final relQueries = '.where("toId", "==", toId)'.allMatches(body).length;
      expect(relQueries, 4, reason: 'identity · legacy · capacity · date guard');
      // capacity도 selectedWorkType으로 좁힌 뒤 workDetailId는 코드에서 거른다
      expect('.where("selectedWorkType", "=='.allMatches(body).length, 3);
      expect(body.contains('.limit(500)'), true, reason: '무제한 스캔 없음');
    });
  });
}
