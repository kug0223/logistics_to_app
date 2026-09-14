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

  /// 지원서가 가리키는 업무. 실제로 세 가지 형태가 존재한다.
  ///   · compositeId — 시간대까지 특정 (신규)
  ///   · 업무명 단독 — 시간대 미상 (레거시)
  ///   · **필드 자체가 없음** — 클라이언트가 안 보내면 저장되지 않는다
  ///     (callableApplyToTO). Firestore는 "필드 없음"을 질의할 수 없다.
  /// 뒤의 둘은 복원할 근거가 없어 보수적으로 본다 — 여기서는 null로 둔다.
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
  // [POSTING-V2-03J.3] 업무명이 아니라 **변경 전** compositeId를 들고 간다.
  final identityTargets = <({String workType, String compositeId})>[];
  // [POSTING-V2-03J.4] legacy lock도 workDetail 단위다.
  final legacyLockTargets = <({String workType, String compositeId})>[];
  final capacityReductions =
      <({String workType, String compositeId, int next})>[];
  var touchesUnverified = false;

  for (final o in oldWDs) {
    if (!newIds.contains(_id(o))) {
      identityTargets
          .add((workType: o['workType'] as String, compositeId: _id(o)));
    }
  }
  for (final o in oldWDs) {
    final n = newWDs.where((d) => _id(d) == _id(o)).firstOrNull;
    if (n == null) continue;
    final workType = o['workType'] as String;

    if (o['wdId'] != null && n['wdId'] != o['wdId']) {
      identityTargets.add((workType: workType, compositeId: _id(o)));
    }
    if (_legacyUnknown.any((f) => o[f] != n[f])) {
      legacyLockTargets.add((workType: workType, compositeId: _id(o)));
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

  // [POSTING-V2-03J.4] 세 guard가 볼 관계를 **한 번만, 자르지 않고** 읽는다.
  //   limit으로 잘라 읽고 메모리에서 거르면 그 밖의 관계를 놓친다.
  final relationWorkTypes = <String>{
    ...capacityReductions.map((c) => c.workType),
    ...identityTargets.map((t) => t.workType),
    ...legacyLockTargets.map((t) => t.workType),
  };
  if (relationWorkTypes.isNotEmpty) queries?.add(relationWorkTypes.length);
  // 완전 읽기 — truncation 없음. 활성 상태만 읽는다.
  List<Rel> relationsFor(String wt) => rels
      .where((r) =>
          relationWorkTypes.contains(wt) &&
          _identityStatuses.contains(r.status) &&
          r.workType == wt)
      .toList();
  // compositeId면 그 업무 하나. 업무명만 있거나 아예 없으면 시간대를 복원할
  //   근거가 없으므로 보수적으로 걸린 것으로 본다.
  bool boundTo(Rel r, String workType, String compositeId) {
    final wdi = r.workDetailId;
    if (wdi == null || wdi.isEmpty) return true;
    return wdi == compositeId || wdi == workType;
  }

  for (final c in capacityReductions) {
    final occupied = relationsFor(c.workType)
        .where((r) =>
            _occupancy.contains(r.status) &&
            boundTo(r, c.workType, c.compositeId))
        .length;
    if (c.next < occupied) return 'CAPACITY';
  }

  // [POSTING-V2-03J.3] identity도 workDetail 단위다. 같은 업무명이라는 이유로
  //   관계 없는 시간대가 잠기지 않는다. status 집합은 capacity와 다르다(§14).
  if (identityTargets.any((t) => relationsFor(t.workType)
      .any((r) => boundTo(r, t.workType, t.compositeId)))) {
    return 'IDENTITY';
  }

  // [POSTING-V2-03J.4] legacy 보상 잠금도 그 workDetail에 걸린 것만 본다.
  if (legacyLockTargets.any((t) => relationsFor(t.workType).any(
      (r) => !r.hasSnapshot && boundTo(r, t.workType, t.compositeId)))) {
    return 'LEGACY';
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

    // [POSTING-V2-03J.3] 03J.2에서는 identity가 업무명 단위라 여기가 막혔다.
    //   이제 관계가 걸린 workDetail만 잠근다.
    test('09-i2 같은 workType의 다른 시간대 삭제는 허용된다', () {
      expect(
          updateTOBlock(
            oldWDs: [wdA(), wdB()],
            newWDs: [wdA()],
            rels: occupiedOnA,
          ),
          isNull,
          reason: 'A의 확정자가 관계 없는 B를 잠그면 안 된다');
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
      // [POSTING-V2-03J.4] 매칭은 공용 boundTo로 옮겼다
      expect(body.contains('boundTo(d, c)'), true);
      expect(body.contains('freshData.workTypeConfirmedCounts'), false,
          reason: '합산 카운터를 하한으로 쓰지 않는다');
    });

    test('10-d 기존 인덱스를 쓴다 — 새 인덱스 없음 (§8)', () {
      final body = _flat(_codeOf(updateTO));
      expect(
          body.contains('.where("toId", "==", toId) '
              '.where("selectedWorkType", "==", wt) '
              '.where("status", "in", ACTIVE_STATUSES)'),
          true,
          reason: 'toId+selectedWorkType+status 인덱스가 이미 있다');
      final idx = _src('firestore.indexes.json');
      expect(idx.contains('"selectedWorkType"'), true);
    });
  });

  // ── 03J.3 §4~§7·§13 workDetail 단위 identity ──────────────────
  group('CONTRACT-11 identity도 workDetail 단위다', () {
    // A 포장 09-18 / B 포장 18-22 / C 포장 22-02
    Map<String, dynamic> a() =>
        wd(startTime: '09:00', endTime: '18:00', wdId: null);
    Map<String, dynamic> b({String startTime = '18:00',
            String endTime = '22:00', String workType = '포장'}) =>
        wd(workType: workType, startTime: startTime, endTime: endTime,
            wdId: null, order: 1);
    Map<String, dynamic> c() =>
        wd(startTime: '22:00', endTime: '02:00', wdId: null, order: 2);

    const relA = Rel('CONFIRMED', '포장', workDetailId: '포장_09:00_18:00');
    const relB = Rel('CONFIRMED', '포장', workDetailId: '포장_18:00_22:00');
    const relC = Rel('PENDING', '포장', workDetailId: '포장_22:00_02:00');
    const legacyPack = Rel('CONFIRMED', '포장'); // workDetailId 없음

    test('11-a 관계 없는 같은 workType 삭제 → ALLOW (§5)', () {
      expect(
          updateTOBlock(oldWDs: [a(), b()], newWDs: [a()], rels: const [relA]),
          isNull);
    });

    test('11-b 관계가 걸린 workDetail 삭제 → BLOCK (§5)', () {
      expect(
          updateTOBlock(oldWDs: [a(), b()], newWDs: [b()], rels: const [relA]),
          'IDENTITY');
    });

    test('11-c 네 가지 active 상태 모두 exact로 잠근다 (§3)', () {
      for (final st in ['PENDING', 'INVITED', 'CONTRACT_PENDING', 'CONFIRMED']) {
        expect(
            updateTOBlock(
              oldWDs: [a(), b()],
              newWDs: [a()],
              rels: [Rel(st, '포장', workDetailId: '포장_18:00_22:00')],
            ),
            'IDENTITY',
            reason: st);
      }
    });

    test('11-d 종료 상태는 exact여도 잠그지 않는다 (§3)', () {
      for (final st in ['REJECTED', 'CANCELED', 'AUTO_CANCELED', 'EXPIRED']) {
        expect(
            updateTOBlock(
              oldWDs: [a(), b()],
              newWDs: [a()],
              rels: [Rel(st, '포장', workDetailId: '포장_18:00_22:00')],
            ),
            isNull,
            reason: st);
      }
    });

    test('11-e 시간 변경 — 그 업무에 관계가 있으면 BLOCK (§6)', () {
      expect(
          updateTOBlock(
            oldWDs: [a(), b()],
            newWDs: [a(), b(startTime: '19:00', endTime: '23:00')],
            rels: const [relB],
          ),
          'IDENTITY');
    });

    test('11-f 시간 변경 — 형제 시간대의 관계만 있으면 ALLOW (§6)', () {
      expect(
          updateTOBlock(
            oldWDs: [a(), b()],
            newWDs: [a(), b(startTime: '19:00', endTime: '23:00')],
            rels: const [relA],
          ),
          isNull,
          reason: '같은 업무명이라는 이유만으로 다른 시간대가 막히면 안 된다');
    });

    test('11-g workType 변경 — 그 업무에 관계가 있으면 BLOCK (§7)', () {
      expect(
          updateTOBlock(
            oldWDs: [a(), b()],
            newWDs: [a(), b(workType: '검수')],
            rels: const [relB],
          ),
          'IDENTITY',
          reason: '판정 기준은 변경 전 identity다');
    });

    test('11-h workType 변경 — 형제 관계만 있으면 ALLOW (§7)', () {
      expect(
          updateTOBlock(
            oldWDs: [a(), b()],
            newWDs: [a(), b(workType: '검수')],
            rels: const [relA],
          ),
          isNull);
    });

    test('11-i 레거시(workDetailId=업무명)는 보수적으로 전부 BLOCK (§2, §5)', () {
      expect(
          updateTOBlock(
            oldWDs: [a(), b()], newWDs: [a()], rels: const [legacyPack]),
          'IDENTITY');
      expect(
          updateTOBlock(
            oldWDs: [a(), b()], newWDs: [b()], rels: const [legacyPack]),
          'IDENTITY',
          reason: '어느 시간대인지 복원할 근거가 없다 — backfill하지 않는다');
    });

    test('11-j 같은 workType 3개가 독립적으로 판정된다 (§13)', () {
      const rels = [relA, relC];
      expect(
          updateTOBlock(
              oldWDs: [a(), b(), c()], newWDs: [b(), c()], rels: rels),
          'IDENTITY',
          reason: 'A 삭제 — CONFIRMED');
      expect(
          updateTOBlock(
              oldWDs: [a(), b(), c()], newWDs: [a(), c()], rels: rels),
          isNull,
          reason: 'B 삭제 — 관계 없음');
      expect(
          updateTOBlock(
              oldWDs: [a(), b(), c()], newWDs: [a(), b()], rels: rels),
          'IDENTITY',
          reason: 'C 삭제 — PENDING');
    });

    test('11-k 레거시가 끼면 3개 모두 BLOCK (§13)', () {
      const rels = [relA, relC, legacyPack];
      for (final next in [
        [b(), c()],
        [a(), c()],
        [a(), b()],
      ]) {
        expect(
            updateTOBlock(oldWDs: [a(), b(), c()], newWDs: next, rels: rels),
            'IDENTITY');
      }
    });

    test('11-l race — B에 확정이 생기면 재시도에서 BLOCK (§11)', () {
      expect(
          updateTOBlock(oldWDs: [a(), b()], newWDs: [a()], rels: const [relA]),
          isNull);
      expect(
          updateTOBlock(
              oldWDs: [a(), b()], newWDs: [a()], rels: const [relA, relB]),
          'IDENTITY');
    });

    test('11-m race — 형제 A에 확정이 늘어도 B 삭제는 ALLOW (§11)', () {
      expect(
          updateTOBlock(
            oldWDs: [a(), b()],
            newWDs: [a()],
            rels: const [relA, relA, relC],
          ),
          isNull,
          reason: '다른 workDetail의 관계가 B를 잠그면 안 된다');
    });

    test('11-n compensation-only edit은 identity 조회 0 (§12)', () {
      final q = <int>[];
      updateTOBlock(
        oldWDs: [a(), b()],
        newWDs: [wd(startTime: '09:00', endTime: '18:00', wdId: null,
            wage: 120000), b()],
        rels: const [relA, relB],
        queries: q,
      );
      expect(q, isEmpty);
    });

    test('11-o 새 업무 추가는 identity 조회 0 (§8, §12)', () {
      final q = <int>[];
      expect(
          updateTOBlock(
            oldWDs: [a()],
            newWDs: [a(), b()],
            rels: const [relA],
            queries: q,
          ),
          isNull);
      expect(q, isEmpty, reason: 'old identity가 없으므로 guard 대상이 아니다');
    });

    test('11-p 같은 업무명 여러 건이어도 관계 조회는 1회 (§12)', () {
      final q = <int>[];
      updateTOBlock(
        oldWDs: [a(), b(), c()],
        newWDs: [c()],
        rels: const [relC],
        queries: q,
      );
      expect(q, [1], reason: '업무명 단위로 중복 제거한 뒤 조회한다');
    });

    // ── 서버 배선 ──
    // [POSTING-V2-03J.4] 매칭 규칙은 공용 boundTo로 옮겼다 — 판정은 동일하다.
    test('11-q 서버가 workDetailId exact match를 한다 (§4)', () {
      final body = _flat(_codeOf(updateTO));
      expect(body.contains('return wdi === t.compositeId || wdi === t.workType;'),
          true);
      expect(
          body.contains('const blocked = identityTargets.filter( '
              '(t) => relationsFor(t.workType).some((d) => boundTo(d, t)));'),
          true);
    });

    test('11-r 업무명 중복 제거 후 조회한다 (§12)', () {
      final body = _flat(_codeOf(updateTO));
      expect(
          body.contains('...identityTargets.map((t) => t.workType)'), true);
      expect(body.contains('const relationWorkTypes = [...new Set(['), true);
      expect(body.contains('.where("status", "in", ACTIVE_STATUSES)'), true);
    });

    test('11-s identity와 capacity의 status 집합이 다르다 (§14)', () {
      final body = _flat(_codeOf(updateTO));
      expect(
          body.contains('const ACTIVE_STATUSES = '
              '["PENDING", "INVITED", "CONTRACT_PENDING", "CONFIRMED"];'),
          true);
      expect(
          body.contains('const OCCUPANCY_STATUSES_TO = '
              '["CONFIRMED", "CONTRACT_PENDING"];'),
          true);
    });

    test('11-t 기존 error copy를 그대로 쓴다 (§16)', () {
      expect(
          _src(_fnsPath).contains(
              "업무에 활성 지원자가 있어 업무 구성을 변경할 수 없습니다. 해당 지원을 먼저 처리해주세요.`"),
          true,
          reason: '새 메시지 종류를 만들지 않는다');
    });

    test('11-u CONTRACT에는 wdId가 없어 wdId guard는 no-op이다 (§15)', () {
      // 주석에는 근거로 적어 뒀으므로 코드만 본다
      expect(_codeOf(updateTO).contains('generateWdId()'), false);
      final createTO = _callableOf(_src(_fnsPath), 'callableCreateTO');
      expect(createTO.contains('generateWdId()'), false);
      // no-op이어도 제거하지 않는다 — 슬롯 payload 방어로 남긴다
      expect(_flat(_codeOf(updateTO))
          .contains('identityTargets.push({workType, compositeId: oldId});'),
          true);
    });
  });

  // ── 03J.4 §2·§4·§6·§11 relation guard completeness ────────────
  group('CONTRACT-12 판정이 500건에서 잘리지 않는다', () {
    Map<String, dynamic> a({int requiredCount = 600}) =>
        wd(startTime: '09:00', endTime: '18:00', wdId: null,
            requiredCount: requiredCount);
    Map<String, dynamic> b() =>
        wd(startTime: '18:00', endTime: '22:00', wdId: null, order: 1);

    /// 같은 workType에 [n]건의 관계를 만든다.
    List<Rel> many(int n, String status, String? workDetailId) => List.generate(
        n, (_) => Rel(status, '포장', workDetailId: workDetailId));

    test('12-a identity — 보호 관계가 501번째에 있어도 BLOCK (§11)', () {
      final rels = [
        ...many(500, 'PENDING', '포장_09:00_18:00'), // 관계 없는 형제 500건
        const Rel('CONFIRMED', '포장', workDetailId: '포장_18:00_22:00'),
      ];
      expect(
          updateTOBlock(oldWDs: [a(), b()], newWDs: [a()], rels: rels),
          'IDENTITY',
          reason: '앞 500건에 가려 놓치면 안 된다');
    });

    test('12-b identity — 형제가 아무리 많아도 관계 없으면 ALLOW (§10)', () {
      expect(
          updateTOBlock(
            oldWDs: [a(), b()],
            newWDs: [a()],
            rels: many(700, 'CONFIRMED', '포장_09:00_18:00'),
          ),
          isNull,
          reason: '700건이어도 B를 잘못 잠그지 않는다');
    });

    test('12-c capacity — occupied 501을 500으로 과소 계산하지 않는다 (§4)', () {
      final rels = many(501, 'CONFIRMED', '포장_09:00_18:00');
      expect(
          updateTOBlock(
            oldWDs: [a()],
            newWDs: [a(requiredCount: 500)],
            rels: rels,
          ),
          'CAPACITY',
          reason: '500으로 잘렸다면 500 >= 500이라 통과했을 것이다');
    });

    test('12-d capacity — 정확한 occupied 경계 (§4)', () {
      final rels = many(501, 'CONFIRMED', '포장_09:00_18:00');
      expect(
          updateTOBlock(
              oldWDs: [a()], newWDs: [a(requiredCount: 501)], rels: rels),
          isNull);
      expect(
          updateTOBlock(
              oldWDs: [a()], newWDs: [a(requiredCount: 500)], rels: rels),
          'CAPACITY');
    });

    test('12-e legacy 보상 — 보호 관계가 뒤쪽 페이지에 있어도 BLOCK (§6)', () {
      final rels = [
        ...many(600, 'CONFIRMED', '포장_09:00_18:00'), // 전부 스냅샷 보유
        const Rel('CONFIRMED', '포장',
            hasSnapshot: false, workDetailId: '포장_09:00_18:00'),
      ];
      expect(
          updateTOBlock(
            oldWDs: [wd(startTime: '09:00', endTime: '18:00', wdId: null,
                breakMinutes: 60, requiredCount: 700)],
            newWDs: [wd(startTime: '09:00', endTime: '18:00', wdId: null,
                breakMinutes: 30, requiredCount: 700)],
            rels: rels,
          ),
          'LEGACY');
    });

    test('12-f legacy 보상 — 다른 시간대의 레거시는 이 업무를 잠그지 않는다 (§6)', () {
      expect(
          updateTOBlock(
            oldWDs: [a(), b()],
            newWDs: [
              a(),
              wd(startTime: '18:00', endTime: '22:00', wdId: null, order: 1,
                  breakMinutes: 30),
            ],
            rels: const [
              Rel('CONFIRMED', '포장',
                  hasSnapshot: false, workDetailId: '포장_09:00_18:00'),
            ],
          ),
          isNull,
          reason: 'A에 걸린 레거시가 B의 산정 조건 변경을 막으면 안 된다');
      // 같은 레거시가 A의 조건을 바꾸는 것은 여전히 막는다
      expect(
          updateTOBlock(
            oldWDs: [a(), b()],
            newWDs: [
              wd(startTime: '09:00', endTime: '18:00', wdId: null,
                  requiredCount: 600, breakMinutes: 30),
              b(),
            ],
            rels: const [
              Rel('CONFIRMED', '포장',
                  hasSnapshot: false, workDetailId: '포장_09:00_18:00'),
            ],
          ),
          'LEGACY');
    });

    test('12-g workDetailId가 아예 없는 지원서도 보수적으로 잡는다 (§2)', () {
      // callableApplyToTO는 클라이언트가 안 보내면 필드를 저장하지 않는다.
      // Firestore는 "필드 없음"을 질의할 수 없으므로 놓치면 fail-open이다.
      const noKey = [Rel('CONFIRMED', '포장')]; // workDetailId 없음
      expect(
          updateTOBlock(oldWDs: [a(), b()], newWDs: [a()], rels: noKey),
          'IDENTITY');
      expect(
          updateTOBlock(oldWDs: [a(), b()], newWDs: [b()], rels: noKey),
          'IDENTITY');
    });

    test('12-h 세 guard가 workType당 한 번만 읽는다 (§13)', () {
      final q = <int>[];
      updateTOBlock(
        // 같은 '포장'에서 삭제 + 인원 축소 + 레거시 조건 변경을 동시에
        oldWDs: [
          wd(startTime: '09:00', endTime: '18:00', wdId: null,
              requiredCount: 5, breakMinutes: 60),
          b(),
        ],
        newWDs: [
          wd(startTime: '09:00', endTime: '18:00', wdId: null,
              requiredCount: 1, breakMinutes: 30),
        ],
        rels: const [],
        queries: q,
      );
      expect(q, [1], reason: 'guard마다 따로 읽지 않는다');
    });

    // ── 서버 배선 ──
    test('12-i 서버 relation 조회에 limit이 없다 (§2, §4, §6)', () {
      final body = _flat(_codeOf(updateTO));
      expect(
          body.contains('.where("toId", "==", toId) '
              '.where("selectedWorkType", "==", wt) '
              '.where("status", "in", ACTIVE_STATUSES) ) )'),
          true,
          reason: 'limit을 걸면 그 뒤 관계를 놓친다');
      expect(body.contains('.limit(500)'), false,
          reason: 'edit guard에 500 truncation이 남아 있으면 안 된다');
    });

    test('12-j 세 guard가 같은 완전 읽기를 공유한다 (§13)', () {
      final body = _flat(_codeOf(updateTO));
      expect(body.contains('const relationWorkTypes = [...new Set(['), true);
      expect('relationsFor('.allMatches(body).length, 3,
          reason: 'capacity · identity · legacy 세 guard가 같은 읽기를 쓴다');
      expect(body.contains('relationDocs.set(wt, relationSnaps[i].docs)'), true);
    });

    test('12-k 식별 불가 지원서를 보수적으로 취급한다 (§12)', () {
      final body = _flat(_codeOf(updateTO));
      expect(
          body.contains(
              'if (typeof wdi !== "string" || wdi.length === 0) return true;'),
          true,
          reason: 'fail-open 금지 — 모르면 잠근다');
    });

    test('12-l aggregate count를 도입하지 않았다 (§5)', () {
      expect(_codeOf(updateTO).contains('.count()'), false,
          reason: 'txEdit.get(query) 기반 구조를 유지한다');
    });

    test('12-m 새 index 없이 기존 index로 돈다 (§14)', () {
      final idx = _flat(_src('firestore.indexes.json'));
      expect(
          idx.contains('{ "fieldPath": "toId", "order": "ASCENDING" }, '
              '{ "fieldPath": "selectedWorkType", "order": "ASCENDING" }, '
              '{ "fieldPath": "status", "order": "ASCENDING" }'),
          true,
          reason: 'toId+selectedWorkType+status 복합 인덱스가 이미 있다');
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
              'newWdId !== oldWdId) { '
              'identityTargets.push({workType, compositeId: oldId}); }'),
          true);
    });

    // [POSTING-V2-03J.2 재작성] 03J.1은 freshData의 workType 합산 카운터를
    //   썼다. 같은 업무명의 다른 시간대가 섞이므로 workDetail 단위 관계
    //   조회로 바꿨다. 판정이 txEdit 안이라는 점은 그대로다.
    test('04-c 업무별 capacity가 workDetail 단위 관계를 본다 (§8, §9)', () {
      final body = _flat(_codeOf(updateTO));
      expect(body.contains('boundTo(d, c)'), true);
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
      expect(body.contains('legacyLockTargets.length > 0'), true);
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
        'identityTargets.length > 0',
        'legacyLockTargets.length > 0',
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
      expect(
          outside.contains(
              'legacyLockTargets.push({workType, compositeId: oldId});'),
          true);
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

    // [POSTING-V2-03J.3] identity preflight도 서버와 같은 매칭을 쓴다.
    //   서버가 허용하는데 client가 같은 업무명이라는 이유로 먼저 막으면 안 된다.
    test('06-g client identity가 workDetail 단위다 (03J.3 §9)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_editPath), 'String? _workChangeBlockReason(')));
      expect(
          body.contains("_toIdentityStatuses.contains(app['status']) && "
              '_appMatchesWork(app, work)'),
          true,
          reason: 'removed는 변경 전 workDetail이다');
      expect(
          body.contains("_toIdentityStatuses.contains(app['status']) && "
              '_appMatchesWork(app, orig)'),
          true,
          reason: 'wdId 교체는 교체 전 identity로 판정한다');
      expect(
          body.contains("_toIdentityStatuses.contains(app['status']) && "
              "app['selectedWorkType'] == work.workType"),
          false,
          reason: 'workType 단위 판정이 남아 있으면 서버보다 과잉 차단한다');
    });

    test('06-h client가 서버와 같은 3가지 매칭을 쓴다 (03J.3 §4)', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_editPath), 'bool _appMatchesWork(')));
      expect(body.contains('if (workDetailId == work.id) return true;'), true);
      expect(body.contains('if (workDetailId == work.workType) return true;'),
          true);
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

    // [POSTING-V2-03J.4 재작성] guard별 3개 조회가 공용 완전 읽기 1개로
    //   합쳐졌다. 남은 applications 조회는 그 하나와 date guard뿐이다.
    test('08-d 전체 application full scan이 없다 (§21)', () {
      final body = _codeOf(updateTO);
      final relQueries = '.where("toId", "==", toId)'.allMatches(body).length;
      expect(relQueries, 2, reason: '공용 relation 읽기 · date guard');
      // 관계 조회는 selectedWorkType으로 좁힌다 — 전체 스캔이 아니다
      expect('.where("selectedWorkType", "=='.allMatches(body).length, 1);
      expect(body.contains('.limit(500)'), false,
          reason: '잘라 읽으면 판정이 fail-open이 된다 (03J.4)');
    });
  });
}
