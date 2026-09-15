// [SYSTEM-INTEGRATION-R0] staffing readiness schema contract
//
// 실기기 모순:
//   Posting  9/16 · 필요 30 · 모집중
//   Home     앞으로 7일 안에도 예정된 근무가 없어요
//
// 원인은 freshness도 timezone도 아니었다. `callableGetStaffingReadiness`가
// canonical 식별자 `wdId`가 아니라 **스키마에 존재하지 않는 `id`**를 읽고
// `.filter(w => w.id.length > 0)`으로 모든 workDetail을 버리고 있었다.
//   FLEX     → wds = [] → required 한 번도 더해지지 않음
//   CONTRACT → totalRequired = 0 → `if (totalRequired === 0) return;`
// 즉 이 callable은 **어떤 TO에 대해서도** 0이 아닌 required를 만들 수 없었다.
//
// DEV 실제 문서(TO CW31vrJxVdUSUF6mIeDb)로 확인한 writer 스키마:
//   TO.workDetails[0]  키 = {workType, requiredCount}   ← id·wdId 둘 다 없음
//   slot.workDetails[0].wdId = "hCsKdykr0nsixUUwgSgS"
//   slot.workDetailCounts    = {"hCsKdykr0nsixUUwgSgS": {confirmedCount: 0, ...}}
//
// 이 파일의 fixture는 그 실제 스키마를 그대로 쓴다.
// `workDetails[].id`는 어떤 fixture에도 넣지 않는다 — 존재하지 않는 필드다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _cfPath = 'functions/src/index.ts';
const _wdPath = 'lib/models/core/work_detail_data.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// TS top-level 함수/블록 본문 — `Promise<{...}>` 반환 타입 중괄호 회피
String _tsSliceOf(String source, String from, String to) {
  final a = source.indexOf(from);
  if (a == -1) throw StateError('$from 를 찾지 못함');
  final b = source.indexOf(to, a);
  if (b == -1) throw StateError('$to 를 찾지 못함');
  return source.substring(a, b);
}

// ═══════════════════════════════════════════════════════════════
// writer schema fixture — DEV 실제 문서와 동일한 모양
// ═══════════════════════════════════════════════════════════════

/// TO 문서의 workDetails 항목. **id도 wdId도 없다** (실측).
Map<String, Object?> toWorkDetail({required int requiredCount}) => {
      'workType': '사무업무',
      'requiredCount': requiredCount,
      'startTime': '09:00',
      'endTime': '18:00',
      'wage': 12000,
      'wageType': 'hourly',
    };

/// slot 문서. wdId가 있고 workDetailCounts 키와 일치한다 (실측).
Map<String, Object?> slotDoc({
  required String wdId,
  required int requiredCount,
  required int confirmedCount,
  bool breakCounts = false,
  bool dropWdId = false,
}) =>
    {
      'workDetails': [
        {
          if (!dropWdId) 'wdId': wdId,
          'workType': '사무업무',
          'requiredCount': requiredCount,
        }
      ],
      'workDetailCounts': breakCounts
          ? <String, Object?>{}
          : {
              wdId: {'confirmedCount': confirmedCount, 'pendingCount': 0}
            },
    };

class DayAcc {
  int required = 0;
  int confirmed = 0;
  int shortage = 0;
}

class ContractError implements Exception {
  final String message;
  ContractError(this.message);
  @override
  String toString() => 'ContractError: $message';
}

/// 수정된 FLEX 집계 규칙 — **슬롯 자신의** workDetails ↔ workDetailCounts.
/// 계약 위반은 0이 아니라 예외다 (§4).
DayAcc flexAccumulate(Map<String, Object?> slot) {
  final acc = DayAcc();
  final wds = (slot['workDetails'] as List).cast<Map<String, Object?>>();
  final wdc = (slot['workDetailCounts'] as Map).cast<String, Object?>();
  for (final w in wds) {
    final wdId = ((w['wdId'] as String?) ?? '').trim();
    final required = (w['requiredCount'] as int?) ?? 0;
    if (wdId.isEmpty || !wdc.containsKey(wdId)) {
      throw ContractError('WORKDETAIL_CONTRACT_BROKEN wdId="$wdId"');
    }
    final counts = (wdc[wdId] as Map).cast<String, Object?>();
    final confirmed = (counts['confirmedCount'] as int?) ?? 0;
    acc.required += required;
    acc.confirmed += confirmed;
    acc.shortage += (required - confirmed) > 0 ? required - confirmed : 0;
  }
  return acc;
}

/// 수정된 CONTRACT 규칙 — wdId join 없이 requiredCount 합산.
int contractTotalRequired(List<Map<String, Object?>> toWorkDetails) =>
    toWorkDetails.fold(0, (s, w) => s + ((w['requiredCount'] as int?) ?? 0));

/// **구** 규칙 재현 — 회귀 방지용. `id` 필터가 전부를 버렸다.
int legacyFilteredCount(List<Map<String, Object?>> toWorkDetails) =>
    toWorkDetails
        .where((w) => ((w['id'] as String?) ?? '').trim().isNotEmpty)
        .length;

void main() {
  final cf = _src(_cfPath);
  final wdModel = _src(_wdPath);
  final flexBlock = _tsSliceOf(
      cf, '// ── 5b. Flex TOs', '// ── 5c. Contract TOs');
  final flexCode = _codeOf(flexBlock);
  final popBlock = _tsSliceOf(cf, '// ── 5a. TO 목록 조회', '// ── 5b. Flex TOs');
  final popCode = _codeOf(popBlock);

  // ═══════════════════════════════════════════════════════════════
  // 01. canonical schema proof — §1
  // ═══════════════════════════════════════════════════════════════
  group('[R0-01] canonical identifier는 wdId다', () {
    test('01-a WorkDetailData.toMap()에 id 필드가 없다', () {
      final toMap = _tsSliceOf(wdModel, 'Map<String, dynamic> toMap()', '};');
      expect(toMap.contains("'wdId'"), isTrue);
      expect(toMap.contains("'id':"), isFalse,
          reason: 'id는 스키마에 존재하지 않는다');
    });

    test('01-b CF capacity helper가 wdId를 canonical로 선언한다', () {
      expect(cf, contains('CASE A: wdId 있음 + workDetailCounts entry 있음'));
      expect(cf, contains('CASE B: [Phase 8.1E.5] wdId 없음'));
    });

    test('01-c slot writer가 wdId를 생성하고 counts 키로 쓴다', () {
      expect(cf, contains('wdId: generateWdId()'));
      expect(cf,
          contains('workDetailCounts[wdId] = {confirmedCount: 0, pendingCount: 0}'));
    });

    test('01-d staffing reader가 더 이상 id를 읽지 않는다', () {
      expect(popCode.contains('w["id"]'), isFalse);
      expect(popCode, contains('w["wdId"]'));
    });

    test('01-e id legacy alias를 새로 만들지 않았다', () {
      // §금지: `id` legacy alias 임의 추가 금지
      expect(popCode.contains('?? w["id"]'), isFalse);
      expect(flexCode.contains('w["id"]'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 02. FLEX — §2, §7
  // ═══════════════════════════════════════════════════════════════
  group('[R0-02] FLEX writer→reader', () {
    test('02-a required 30 / confirmed 0 → day 존재, shortage 30', () {
      final acc = flexAccumulate(slotDoc(
          wdId: 'hCsKdykr0nsixUUwgSgS', requiredCount: 30, confirmedCount: 0));
      expect(acc.required, 30);
      expect(acc.confirmed, 0);
      expect(acc.shortage, 30);
    });

    test('02-b required 30 / confirmed 30 → day 유지, shortage 0', () {
      final acc = flexAccumulate(slotDoc(
          wdId: 'w1', requiredCount: 30, confirmedCount: 30));
      expect(acc.required, 30, reason: 'FULL이어도 day가 사라지면 안 된다');
      expect(acc.shortage, 0);
    });

    test('02-c 초과 확정이 required를 깎지 않는다', () {
      final acc = flexAccumulate(
          slotDoc(wdId: 'w1', requiredCount: 5, confirmedCount: 8));
      expect(acc.required, 5);
      expect(acc.confirmed, 8);
      expect(acc.shortage, 0);
    });

    test('02-d 실제 DEV 문서 모양에서 required 5가 나온다', () {
      // TO CW31vrJxVdUSUF6mIeDb / slot KST 2026-09-16
      final acc = flexAccumulate(slotDoc(
          wdId: 'hCsKdykr0nsixUUwgSgS', requiredCount: 5, confirmedCount: 0));
      expect(acc.required, 5);
      expect(acc.shortage, 5);
    });

    test('02-e 구 규칙은 같은 문서에서 전부 버렸다 (회귀 고정)', () {
      final toWds = [toWorkDetail(requiredCount: 5)];
      expect(legacyFilteredCount(toWds), 0,
          reason: 'id 필터가 모든 workDetail을 제거했다');
      expect(toWds.first.containsKey('id'), isFalse);
      expect(toWds.first.containsKey('wdId'), isFalse);
    });

    test('02-f 구현이 슬롯 자신의 workDetails를 쓴다', () {
      expect(flexCode, contains('sd["workDetails"]'));
      expect(flexCode, contains('w["wdId"]'));
      expect(flexCode, contains('wd.wdId in wdc'));
      expect(flexCode.contains('for (const wd of to.wds)'), isFalse,
          reason: 'TO-level 배열로 슬롯 counter를 join하면 안 된다');
    });

    test('02-g 추가 Firestore read가 없다', () {
      // 슬롯은 이미 읽은 문서 — 새 get()을 만들지 않았다
      expect(RegExp(r'\.get\(\)').allMatches(flexCode).length, 1,
          reason: 'slots 쿼리 하나뿐');
      final flat = flexCode.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat,
          contains('db .collection("tos").doc(to.toId).collection("slots")'));
      // 슬롯 안에서 다시 문서를 읽지 않는다
      expect(flexCode.contains('getAll'), isFalse);
      expect(flexCode.contains('.doc(slotDoc.id)'), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 03. CONTRACT — §3, §8
  // ═══════════════════════════════════════════════════════════════
  group('[R0-03] CONTRACT writer→reader', () {
    test('03-a wdId가 없어도 required가 살아남는다', () {
      final wds = [
        toWorkDetail(requiredCount: 3),
        toWorkDetail(requiredCount: 2),
      ];
      expect(wds.every((w) => !w.containsKey('wdId')), isTrue);
      expect(contractTotalRequired(wds), 5);
    });

    test('03-b totalRequired > 0이면 target이 존재한다', () {
      expect(contractTotalRequired([toWorkDetail(requiredCount: 30)]), 30);
    });

    test('03-c 구현에서 id 필터가 사라졌다', () {
      expect(popCode.contains('.filter((w) => w.id.length > 0)'), isFalse);
      expect(popCode, contains('required: Math.max(0,'));
    });

    test('03-d contract에 slot join 요구를 만들지 않았다', () {
      final contractBlock =
          _tsSliceOf(cf, '// ── 5c. Contract TOs', '// ── 5d');
      expect(contractBlock.contains('workDetailCounts'), isFalse);
      expect(contractBlock, contains('to.totalRequired'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 04. invalid data — §4, §5, §9
  // ═══════════════════════════════════════════════════════════════
  group('[R0-04] DATA CONTRACT ERROR ≠ ZERO', () {
    test('04-a slot workDetail에 wdId 없음 → 0이 아니라 예외', () {
      expect(
        () => flexAccumulate(slotDoc(
            wdId: 'w1', requiredCount: 5, confirmedCount: 0, dropWdId: true)),
        throwsA(isA<ContractError>()),
      );
    });

    test('04-b workDetailCounts entry 없음 → 0이 아니라 예외', () {
      expect(
        () => flexAccumulate(slotDoc(
            wdId: 'w1', requiredCount: 5, confirmedCount: 0, breakCounts: true)),
        throwsA(isA<ContractError>()),
      );
    });

    test('04-c 구현이 silent skip을 하지 않는다', () {
      expect(flexCode.contains('— skip'), isFalse);
      expect(flexCode, contains('WORKDETAIL_CONTRACT_BROKEN'));
      expect(flexCode, contains('throw new Error('));
    });

    test('04-d 예외가 해당 사업장 success=false로 이어진다', () {
      final forEachBlock = _tsSliceOf(cf, 'flexResults.forEach', '// ── 5c.');
      expect(forEachBlock, contains('success = false'));
    });

    test('04-e success=false가 available/partial로 내려간다', () {
      expect(cf, contains('available: failedBusinessCount === 0,'));
      expect(cf,
          contains('partial: okBusinessCount > 0 && failedBusinessCount > 0'));
    });

    test('04-f 0 fallback을 만들지 않았다', () {
      // `?? 0`으로 결손을 메우지 않는다 — confirmedCount 정상 경로만 허용
      expect(flexCode.contains('wd.required ?? 0'), isFalse);
      expect(flexCode.contains('|| 0'), isFalse);
    });

    test('04-g legacy fail-closed 계약을 유지한다', () {
      // 8.1E.5가 세운 CASE B/C fail-closed는 그대로
      expect(cf, contains('CASE C: wdId 있음 + workDetailCounts entry 없음'));
      expect(cf, contains('silently 0으로 반환하면'));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 05. multi-date — §7
  // ═══════════════════════════════════════════════════════════════
  group('[R0-05] 날짜별 독립 계산', () {
    test('05-a 9/18 full · 9/19 shortage · 9/22 full', () {
      final d18 = flexAccumulate(
          slotDoc(wdId: 'a', requiredCount: 5, confirmedCount: 5));
      final d19 = flexAccumulate(
          slotDoc(wdId: 'b', requiredCount: 5, confirmedCount: 2));
      final d22 = flexAccumulate(
          slotDoc(wdId: 'c', requiredCount: 5, confirmedCount: 5));
      expect([d18.shortage, d19.shortage, d22.shortage], [0, 3, 0]);
      expect([d18.required, d19.required, d22.required], [5, 5, 5]);
    });

    test('05-b 슬롯마다 다른 wdId를 갖는다 (실측 스키마)', () {
      // DEV 실제: 6개 슬롯이 전부 다른 wdId
      const ids = [
        'Oqvg1zYLyLy6fdyXPdam', 'hCsKdykr0nsixUUwgSgS', '9ndmNdlh3l7yoGmkljDe',
        '3T8fuFgOnO5jdEZ9VrHd', '9rVcPwFZfy8dAkFWiiKa', 'HQ8e5SZ9KQXxpn3Kc47X',
      ];
      expect(ids.toSet().length, 6,
          reason: 'TO 한 벌로 join할 수 없는 이유 — 슬롯마다 독립 ID');
      for (final id in ids) {
        final acc = flexAccumulate(
            slotDoc(wdId: id, requiredCount: 5, confirmedCount: 0));
        expect(acc.required, 5);
      }
    });

    test('05-c 6일 합계가 공고 카드의 필요 30과 일치한다', () {
      var total = 0;
      for (var i = 0; i < 6; i++) {
        total += flexAccumulate(
                slotDoc(wdId: 'w$i', requiredCount: 5, confirmedCount: 0))
            .required;
      }
      expect(total, 30, reason: 'Posting `필요 30` ↔ staffing 합계 일치');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 06. 무회귀
  // ═══════════════════════════════════════════════════════════════
  group('[R0-06] 무회귀', () {
    test('06-a population status 집합이 그대로다', () {
      expect(popCode, contains('.where("status", "in", ["ACTIVE", "SCHEDULED", "FULL"])'));
      expect(popCode, contains('if (d["isDeleted"] === true) continue;'));
    });

    test('06-b publishedCount / hasDraft 신호가 그대로다', () {
      expect(popCode, contains('publishedCount++'));
    });

    test('06-c D0~D+7 날짜 창이 그대로다', () {
      expect(cf, contains('const N_DAYS = 8; // D0~D+7 포함'));
      expect(cf, contains('.where("date", ">=", d0Ts)'));
      expect(cf, contains('.where("date", "<", d7EndTs)'));
    });

    test('06-d FLEX status 정책을 건드리지 않았다', () {
      // §금지: FLEX status 정책 문제를 이번 patch에 섞지 않기
      expect(cf, contains('const IMMUTABLE_TO_STATUSES ='));
    });

    test('06-e review emitter를 건드리지 않았다', () {
      // §금지: review patch를 이번 Phase에 섞지 않기
      expect(cf, contains('async function createPendingReviewRequests('));
      expect(cf, contains('[M2-FIX] absent/NO_SHOW는 실제 근무 없음'));
    });
  });
}
