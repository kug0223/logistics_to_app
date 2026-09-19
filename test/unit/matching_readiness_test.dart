// test/unit/matching_readiness_test.dart
//
// [PII-DOC-R1.5] 근무 확정 readiness truth table.
//
//   서버 `srvResolveMatchingReadiness`와 **같은 식**을 여기서 돌린다.
//   식이 서버와 같다는 것은 matching_readiness_contract_test가 고정한다.
//
//   핵심: 급여계좌 상태가 이 판정에 들어오지 않는다. 통장사본이 없어도,
//   불일치여도, 못 읽었어도 근무 확정은 된다 — 돈은 나중 문제다.

import 'package:flutter_test/flutter_test.dart';

/// 서버 helper와 같은 규칙.
({bool ready, String state, bool auto}) resolve({
  required bool hasIdDoc,
  String? matchStatus,
  int? matchVersion,
  int idVersion = 1,
  String manualDecision = 'NOT_REVIEWED',
  int? reviewedIdVersion,
}) {
  // 1) 자동 정합성 — 읽는 시점 버전 비교 (R1.4 resolver와 같다)
  String auto;
  if (!hasIdDoc) {
    auto = 'MISSING';
  } else if (matchStatus == null) {
    auto = 'UNASSESSED';
  } else {
    auto = (matchVersion ?? -1) != idVersion ? 'UNASSESSED' : matchStatus;
  }

  // 2) 사람 검토
  final manualStale =
      manualDecision != 'NOT_REVIEWED' && (reviewedIdVersion ?? -1) != idVersion;
  final manualOk = manualDecision == 'REVIEWED_OK' && !manualStale;

  if (auto == 'MISSING') return (ready: false, state: 'ID_MISSING', auto: false);
  if (auto == 'MATCHED') return (ready: true, state: 'READY_AUTO', auto: true);
  if (manualOk) return (ready: true, state: 'READY_MANUAL', auto: false);
  if (auto == 'MISMATCH') {
    return (ready: false, state: 'ID_MISMATCH', auto: false);
  }
  if (auto == 'OCR_UNCERTAIN') {
    return (ready: false, state: 'ID_OCR_UNCERTAIN', auto: false);
  }
  return (ready: false, state: 'ID_UNASSESSED', auto: false);
}

void main() {
  group('MR — 핵심 truth table', () {
    test('MR-1 자동 MATCHED + 사람 미검토 → READY_AUTO', () {
      final r = resolve(
          hasIdDoc: true, matchStatus: 'MATCHED', matchVersion: 1, idVersion: 1);
      expect(r.ready, isTrue);
      expect(r.state, 'READY_AUTO');
      expect(r.auto, isTrue, reason: '정상 사용자는 사람 검토 없이 확정된다');
    });

    test('MR-2 UNASSESSED + 사람 REVIEWED_OK(현재) → READY_MANUAL', () {
      final r = resolve(
          hasIdDoc: true, matchStatus: null, idVersion: 2,
          manualDecision: 'REVIEWED_OK', reviewedIdVersion: 2);
      expect(r.ready, isTrue);
      expect(r.state, 'READY_MANUAL');
    });

    test('MR-3 OCR_UNCERTAIN + 사람 REVIEWED_OK → READY_MANUAL', () {
      final r = resolve(
          hasIdDoc: true, matchStatus: 'OCR_UNCERTAIN', matchVersion: 3,
          idVersion: 3, manualDecision: 'REVIEWED_OK', reviewedIdVersion: 3);
      expect(r.ready, isTrue, reason: 'OCR이 못 읽는 정상 서류가 실재한다');
      expect(r.state, 'READY_MANUAL');
    });

    test('MR-4 MISMATCH + 사람 미검토 → NOT_READY', () {
      final r = resolve(
          hasIdDoc: true, matchStatus: 'MISMATCH', matchVersion: 1, idVersion: 1);
      expect(r.ready, isFalse);
      expect(r.state, 'ID_MISMATCH');
    });

    test('MISMATCH라도 사람이 원본을 봤으면 통과', () {
      final r = resolve(
          hasIdDoc: true, matchStatus: 'MISMATCH', matchVersion: 1, idVersion: 1,
          manualDecision: 'REVIEWED_OK', reviewedIdVersion: 1);
      expect(r.ready, isTrue);
      expect(r.state, 'READY_MANUAL');
    });

    test('MR-5 문서 없음 → NOT_READY', () {
      final r = resolve(hasIdDoc: false, matchStatus: 'MATCHED', matchVersion: 1);
      expect(r.ready, isFalse);
      expect(r.state, 'ID_MISSING');
    });

    test('문서가 없으면 사람 검토가 있어도 통과하지 않는다', () {
      // 삭제는 idDocumentVersion을 되돌리지 않으므로 검토가 '현재'로 보인다.
      final r = resolve(
          hasIdDoc: false, idVersion: 1,
          manualDecision: 'REVIEWED_OK', reviewedIdVersion: 1);
      expect(r.ready, isFalse);
      expect(r.state, 'ID_MISSING');
    });

    test('MR-6 저장된 MATCHED가 낡으면 자동 통과 아님', () {
      final r = resolve(
          hasIdDoc: true, matchStatus: 'MATCHED', matchVersion: 1, idVersion: 2);
      expect(r.ready, isFalse);
      expect(r.state, 'ID_UNASSESSED');
    });

    test('MR-7 낡은 사람 검토는 fallback이 아니다', () {
      final r = resolve(
          hasIdDoc: true, matchStatus: null, idVersion: 2,
          manualDecision: 'REVIEWED_OK', reviewedIdVersion: 1);
      expect(r.ready, isFalse);
      expect(r.state, 'ID_UNASSESSED');
    });

    test('재등록 요청 중은 통과가 아니다', () {
      final r = resolve(
          hasIdDoc: true, matchStatus: 'UNASSESSED', matchVersion: 1,
          idVersion: 1,
          manualDecision: 'REUPLOAD_REQUIRED', reviewedIdVersion: 1);
      expect(r.ready, isFalse);
    });

    test('낡은 MATCHED + 현재 사람 검토 → READY_MANUAL', () {
      final r = resolve(
          hasIdDoc: true, matchStatus: 'MATCHED', matchVersion: 1, idVersion: 2,
          manualDecision: 'REVIEWED_OK', reviewedIdVersion: 2);
      expect(r.ready, isTrue);
      expect(r.state, 'READY_MANUAL');
    });
  });

  group('BI — 급여계좌 독립성', () {
    // 이 판정에는 통장 관련 입력이 **존재하지 않는다**. 그게 핵심이다.
    // 아래는 "통장이 어떤 상태든 같은 답"임을 명시적으로 남긴다.
    final idOk = () => resolve(
        hasIdDoc: true, matchStatus: 'MATCHED', matchVersion: 1, idVersion: 1);

    test('BI-1 ID MATCHED + BANK MISMATCH → READY_AUTO', () {
      expect(idOk().state, 'READY_AUTO');
    });

    test('BI-2 ID MATCHED + BANK MISSING → READY_AUTO', () {
      expect(idOk().state, 'READY_AUTO');
    });

    test('BI-3 ID MATCHED + BANK OCR_UNCERTAIN → READY_AUTO', () {
      expect(idOk().state, 'READY_AUTO');
    });

    test('판정 입력에 통장 축이 없다', () {
      // resolve의 named parameter 어디에도 bank가 없다 — 구조적 보장이다.
      expect(idOk().ready, isTrue);
    });
  });

  group('상태가 원인을 잃지 않는다', () {
    test('NOT_READY 사유가 서로 구분된다', () {
      final states = <String>{
        resolve(hasIdDoc: false).state,
        resolve(hasIdDoc: true, matchStatus: 'MISMATCH', matchVersion: 1).state,
        resolve(hasIdDoc: true, matchStatus: 'OCR_UNCERTAIN', matchVersion: 1)
            .state,
        resolve(hasIdDoc: true, matchStatus: null).state,
      };
      expect(states.length, 4, reason: 'ready=false 하나로 뭉개지 않는다');
    });

    test('READY도 경로가 구분된다', () {
      expect(
          resolve(hasIdDoc: true, matchStatus: 'MATCHED', matchVersion: 1).state,
          'READY_AUTO');
      expect(
          resolve(
                  hasIdDoc: true,
                  manualDecision: 'REVIEWED_OK',
                  reviewedIdVersion: 1)
              .state,
          'READY_MANUAL');
    });
  });
}
