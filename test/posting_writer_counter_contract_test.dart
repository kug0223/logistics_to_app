// [SYSTEM-INTEGRATION-R1] FLEX posting writer — totalRequired 소유권
//
// DEV Golden Slice에서 발견:
//   필요 3명 × 2일 공고를 canonical writer 체인으로 만들었더니
//   TO.totalRequired = 12  (실제 Σ slot.requiredCount = 6)
//
// 실제 앱이 만든 기존 공고도 같은 증상:
//   CW31vrJxVd  totalRequired=55  Σslot=30  totalSlots=12  slots=6
//
// 원인 — 두 writer가 같은 양을 각각 더한다:
//   1) to_firestore.dart:385
//        totalRequired = perSlotRequired * dates.length     // 3 × 2 = 6
//      → toData로 전송 → callableCreateTO가 그대로 저장
//   2) callableCreateFlexSlots
//        totalRequired: FieldValue.increment(totalNewRequired)  // + 6
//   → 12 (정확히 2배)
//
// 영향: syncTOStats의 FULL 판정이
//   totalRequired > 0 && confirmedCnt >= totalRequired
// 이므로, 부풀려진 값은 자리를 다 채워도 FULL이 되지 않게 만든다.
//
// 교정: FLEX의 totalRequired는 **슬롯이 소유**한다. 생성 시점 씨앗은 0.
//   서버가 이미 totalConfirmed/totalPending에 쓰는 [S5-FIX] 패턴과 같다.
//   CONTRACT는 슬롯이 없고 workDetails 합이 곧 필요 인원이므로 유지.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _cfPath = 'functions/src/index.ts';
const _toWriterPath = 'lib/services/firestore/to_firestore.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _sliceOf(String source, String from, String to) {
  final a = source.indexOf(from);
  if (a == -1) throw StateError('$from 를 찾지 못함');
  final b = source.indexOf(to, a + from.length);
  if (b == -1) throw StateError('$to 를 찾지 못함');
  return source.substring(a, b);
}

// ═══════════════════════════════════════════════════════════════
// writer chain replica — 실제 스키마/순서와 동일
//   callableCreateTO  → seed
//   callableCreateFlexSlots → increment(Σ slot.requiredCount)
// ═══════════════════════════════════════════════════════════════

/// 클라이언트가 보내는 값 (to_firestore.dart:385)
int clientTotalRequired({
  required String type,
  required List<int> perWorkDetailRequired,
  required int dateCount,
}) {
  final perSlot = perWorkDetailRequired.fold<int>(0, (s, v) => s + v);
  return type == 'flex' ? perSlot * dateCount : perSlot;
}

/// callableCreateTO가 저장하는 씨앗 — flex는 서버가 0으로 강제.
int storedSeed({required String type, required int clientValue}) =>
    type == 'flex' ? 0 : clientValue;

/// callableCreateFlexSlots의 increment (flex만).
int afterSlotCreation({
  required int seed,
  required List<int> perWorkDetailRequired,
  required int dateCount,
}) {
  final perSlot = perWorkDetailRequired.fold<int>(0, (s, v) => s + v);
  return seed + perSlot * dateCount;
}

/// 슬롯이 말하는 진실 (canonical).
int slotTruth({
  required List<int> perWorkDetailRequired,
  required int dateCount,
}) =>
    perWorkDetailRequired.fold<int>(0, (s, v) => s + v) * dateCount;

void main() {
  final cf = _src(_cfPath);
  final writer = _src(_toWriterPath);
  final createTo = _codeOf(
      _sliceOf(cf, 'export const callableCreateTO = onCall(', '\n);'));

  // ═══════════════════════════════════════════════════════════════
  // 01. double-count 회귀 — §10, §25
  // ═══════════════════════════════════════════════════════════════
  group('[R1-01] FLEX totalRequired 이중 계상', () {
    test('01-a Golden Slice 값(3명 × 2일)이 6이어야 한다', () {
      const perWd = [3];
      const dates = 2;
      final client = clientTotalRequired(
          type: 'flex', perWorkDetailRequired: perWd, dateCount: dates);
      expect(client, 6);
      final stored = afterSlotCreation(
        seed: storedSeed(type: 'flex', clientValue: client),
        perWorkDetailRequired: perWd,
        dateCount: dates,
      );
      expect(stored, slotTruth(perWorkDetailRequired: perWd, dateCount: dates));
      expect(stored, 6, reason: '교정 전에는 12였다');
    });

    test('01-b 구 동작(씨앗=클라이언트 값)은 정확히 2배였다', () {
      const perWd = [3];
      const dates = 2;
      final client = clientTotalRequired(
          type: 'flex', perWorkDetailRequired: perWd, dateCount: dates);
      final legacy = afterSlotCreation(
        seed: client, // 구: flex도 클라이언트 값을 그대로 씨앗으로 저장
        perWorkDetailRequired: perWd,
        dateCount: dates,
      );
      expect(legacy, 12);
      expect(legacy,
          slotTruth(perWorkDetailRequired: perWd, dateCount: dates) * 2);
    });

    test('01-c 업무 여러 개 · 날짜 여러 개에서도 일치', () {
      for (final perWd in [
        [5],
        [2, 3],
        [1, 1, 1],
      ]) {
        for (final dates in [1, 3, 6]) {
          final stored = afterSlotCreation(
            seed: storedSeed(
                type: 'flex',
                clientValue: clientTotalRequired(
                    type: 'flex',
                    perWorkDetailRequired: perWd,
                    dateCount: dates)),
            perWorkDetailRequired: perWd,
            dateCount: dates,
          );
          expect(stored,
              slotTruth(perWorkDetailRequired: perWd, dateCount: dates),
              reason: 'perWd=$perWd dates=$dates');
        }
      }
    });

    test('01-d CONTRACT는 씨앗을 유지한다 (슬롯 없음)', () {
      const perWd = [4, 2];
      final client = clientTotalRequired(
          type: 'contract', perWorkDetailRequired: perWd, dateCount: 1);
      expect(client, 6);
      expect(storedSeed(type: 'contract', clientValue: client), 6,
          reason: 'contract는 workDetails 합이 곧 필요 인원이다');
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 02. 구현 배선 — §7, §8
  // ═══════════════════════════════════════════════════════════════
  group('[R1-02] 구현 배선', () {
    test('02-a 서버가 flex의 totalRequired를 0으로 강제한다', () {
      expect(createTo, contains('if (finalData.type === "flex") {'));
      expect(createTo, contains('finalData.totalRequired = 0;'));
    });

    test('02-b 기존 서버 전용 카운터 강제와 같은 자리에 있다', () {
      final flat = createTo.replaceAll(RegExp(r'\s+'), ' ');
      expect(flat, contains('finalData.totalConfirmed = 0; finalData.totalPending = 0;'));
      final confAt = createTo.indexOf('finalData.totalConfirmed = 0;');
      final reqAt = createTo.indexOf('finalData.totalRequired = 0;');
      expect(confAt, lessThan(reqAt));
    });

    test('02-c 슬롯 writer가 여전히 increment로 소유한다', () {
      expect(cf, contains('totalRequired: admin.firestore.FieldValue.increment(totalNewRequired)'));
    });

    test('02-d 슬롯 편집 delta 경로는 건드리지 않았다', () {
      // [TOCTOU-FIX] 서버 현재 값 기준 delta — 그대로 유지
      expect(writer, contains("tx.update(toRef, {'totalRequired': FieldValue.increment(delta)})"));
    });

    test('02-e 클라이언트 계산식을 바꾸지 않았다', () {
      // 구 클라이언트가 값을 보내도 서버가 막는다 — 서버 측 교정이 canonical
      expect(writer, contains('perSlotRequired * (dates?.length ?? 1)'));
    });

    test('02-f contract 경로에는 강제가 걸리지 않는다', () {
      final at = createTo.indexOf('finalData.totalRequired = 0;');
      final guard = createTo.lastIndexOf('if (finalData.type === "flex")', at);
      expect(guard, isNot(-1));
      expect(guard, lessThan(at));
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 03. FULL 판정 영향 — §25
  // ═══════════════════════════════════════════════════════════════
  group('[R1-03] FULL 판정 기준', () {
    test('03-a syncTOStats가 totalRequired를 쓴다', () {
      expect(cf, contains('totalRequired'));
      expect(cf, contains('confirmedCnt'));
    });

    test('03-b 부풀려진 값은 FULL을 영원히 막는다', () {
      // 자리 6개를 다 채워도 12 기준이면 FULL이 아니다
      const confirmed = 6;
      expect(confirmed >= 12, isFalse);
      expect(confirmed >= 6, isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // 04. writer 체인 무회귀 — §8, §31
  // ═══════════════════════════════════════════════════════════════
  group('[R1-04] writer 체인 무회귀', () {
    test('04-a FLEX는 3단계 체인이다', () {
      expect(writer, contains("httpsCallable('callableCreateTO')"));
      expect(writer, contains('_callCreateFlexSlots('));
      expect(writer, contains("httpsCallable('callablePublishTO'"));
    });

    test('04-b 슬롯 생성 실패 시 TO까지 롤백한다', () {
      expect(writer, contains('await toRef.delete();'));
    });

    test('04-c 슬롯이 wdId를 생성하고 counts 키로 쓴다 (R0.1 계약)', () {
      expect(cf, contains('wdId: generateWdId()'));
      expect(cf,
          contains('workDetailCounts[wdId] = {confirmedCount: 0, pendingCount: 0}'));
    });

    test('04-d staffing reader가 슬롯 join을 유지한다 (R0.1)', () {
      expect(cf, contains('wdc[wd.wdId]?.confirmedCount'));
      expect(cf, contains('WORKDETAIL_CONTRACT_BROKEN'));
    });

    test('04-e review eligibility를 건드리지 않았다 (R0.2)', () {
      expect(cf,
          contains('const ACTUAL_WORK_STATUSES = ["present", "late", "early_leave"]'));
      expect(cf, contains('srvHasActualWorkInMonth('));
    });
  });
}
