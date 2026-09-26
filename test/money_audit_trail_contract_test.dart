// [R5-H] 돈을 움직인 기록 계약.
//
//   지키는 문장은 하나다.
//
//     누가 언제 무엇을 어떻게 바꿨는지 복원할 수 있어야 한다.
//
//   현재 금액은 원래도 맞았다. 문제는 이체와 취소가 서로의 흔적을 지우고,
//   급여 수정이 이전 값을 덮고, 마감 취소가 누가 열었는지조차 남기지 않은
//   것이었다. 상태 필드는 현재 진실로 그대로 두고 사건을 따로 쌓는다.
//
//   사건이 상태와 **같은 트랜잭션**에서 쓰이는지, 재시도로 늘지 않는지,
//   민감정보가 섞이지 않는지를 소스로 고정한다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _fn(String src, String name) {
  final i = src.indexOf(name);
  expect(i, greaterThan(-1), reason: '$name 을 찾지 못했다');
  final n = src.indexOf('\nexport const ', i + 10);
  return src.substring(i, n > 0 ? n : src.length);
}

String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  expect(i, greaterThan(-1), reason: '$name 을 찾지 못했다');
  final e = (i + chars) > src.length ? src.length : i + chars;
  return src.substring(i, e);
}

void main() {
  late String code;
  late String rules;

  setUpAll(() {
    code = _codeOf(File('functions/src/index.ts').readAsStringSync());
    rules = _codeOf(File('firestore.rules').readAsStringSync());
  });

  // ───────────────────────────────────────────────────────────
  group('H-1x 저장 구조 (§5·§6)', () {
    test('H-10 근태 문서 하위 append-only 저장소다', () {
      expect(code.contains('const MONEY_AUDIT_SUB = "money_audit";'), isTrue);
      final h = _after(code, 'function srvWriteMoneyAudit(', 1800);
      expect(h.contains('attRef.collection(MONEY_AUDIT_SUB).doc()'), isTrue,
          reason: '새 문서로 append 한다 — 기존 사건을 덮어쓰지 않는다');
      expect(h.contains('.update('), isFalse);
      expect(h.contains('.delete('), isFalse);
    });

    test('H-11 알림·payroll summary 를 감사 저장소로 쓰지 않았다', () {
      final h = _after(code, 'function srvWriteMoneyAudit(', 1800);
      expect(h.contains('notifications'), isFalse);
      expect(h.contains('payroll_summaries'), isFalse);
    });

    test('H-12 시각은 서버 시각이다 (§21)', () {
      final h = _after(code, 'function srvWriteMoneyAudit(', 1800);
      expect(h.contains('createdAt: admin.firestore.FieldValue.serverTimestamp()'),
          isTrue);
      expect(h.contains('Date.now()'), isFalse,
          reason: '클라이언트 시계는 근거가 되지 못한다');
      expect(code.contains('sequenceNumber'), isFalse,
          reason: '전역 시퀀스 시스템을 만들지 않았다');
    });

    test('H-13 최소 공통 필드가 있다 (§6)', () {
      final h = _after(code, 'function srvWriteMoneyAudit(', 1800);
      for (final k in <String>[
        'attendanceId', 'eventType', 'businessId', 'workerId', 'actorUid',
      ]) {
        expect(h.contains('$k:'), isTrue, reason: k);
      }
    });

    test('J 민감정보를 복제하지 않는다 (§6)', () {
      final h = _after(code, 'function srvWriteMoneyAudit(', 1800);
      for (final pii in <String>[
        'accountNumber', 'wageAccountNumberEncrypted', 'wageAccountHolder',
        'wageAccountBankName', 'idCard', 'rrn', 'taxIdentifier', 'ciHash',
      ]) {
        expect(h.contains(pii), isFalse, reason: pii);
      }
      // 금액 diff 대상도 화이트리스트로 못박혀 있다.
      final keys = _after(code, 'const MONEY_AUDIT_WAGE_KEYS', 500);
      expect(keys.contains('totalAmount'), isTrue);
      expect(keys.contains('netWage'), isTrue);
      expect(keys.contains('accountNumber'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('H-2x 이체·취소·재이체 (§7·§16 A·B·C·D)', () {
    test('A 이체는 TRANSFERRED 를 남긴다', () {
      final f = _fn(code, 'export const callableMarkTransferredBatch');
      expect(f.contains('eventType: "TRANSFERRED"'), isTrue);
      expect(f.contains('afterWageStatus: "transferred"'), isTrue);
      expect(f.contains('actorUid: callerUid'), isTrue);
    });

    test('B 실제 전환한 건에만 남긴다 — 재시도는 0', () {
      final f = _fn(code, 'export const callableMarkTransferredBatch');
      // 이미 transferred 면 위에서 continue 하고 update 에 닿지 않는다.
      expect(f.contains('alreadyTransferred.push(id);'), isTrue);
      final already = f.indexOf('alreadyTransferred.push(id);');
      final audit = f.indexOf('eventType: "TRANSFERRED"');
      expect(already, lessThan(audit),
          reason: '멱등 통과가 감사 기록보다 앞에서 끝나야 한다');
      // 기록은 상태 변경과 같은 자리(같은 트랜잭션)에 붙어 있다.
      final upd = f.indexOf('tx.update(snap.ref, updateData);');
      expect(upd, greaterThan(-1));
      expect(audit - upd, lessThan(700),
          reason: '상태 변경 직후에 남긴다 — 트랜잭션 경계 밖이면 어긋난다');
    });

    test('C 취소는 TRANSFER_CANCELED + 사유를 남긴다', () {
      final f = _fn(code, 'export const callableCancelTransfer');
      expect(f.contains('eventType: "TRANSFER_CANCELED"'), isTrue);
      expect(f.contains('reason: cancelNote.trim()'), isTrue);
      expect(f.contains('beforeWageStatus: "transferred"'), isTrue);
      expect(f.contains('afterWageStatus: "confirmed"'), isTrue);
    });

    test('D 서로의 흔적을 지워도 사건은 남는다', () {
      // 취소는 transferDate/transferredBy 를 지우고,
      //   재이체는 cancelNote/cancelledTransfer* 를 지운다. 그대로 둔다(§8).
      final cancel = _fn(code, 'export const callableCancelTransfer');
      expect(cancel.contains('transferDate: admin.firestore.FieldValue.delete()'),
          isTrue, reason: '현재 상태 표현은 기존 방식을 유지한다');
      final xfer = _fn(code, 'export const callableMarkTransferredBatch');
      expect(xfer.contains('cancelNote: admin.firestore.FieldValue.delete()'),
          isTrue);
      // 재이체도 같은 TRANSFERRED 사건을 새로 쌓는다 — 시퀀스로 구분된다.
      expect(xfer.contains('eventType: "TRANSFERRED"'), isTrue);
    });

    test('§8 현재 상태 필드를 제거하지 않았다', () {
      final xfer = _fn(code, 'export const callableMarkTransferredBatch');
      expect(xfer.contains('transferredBy: callerUid'), isTrue);
      final cancel = _fn(code, 'export const callableCancelTransfer');
      expect(cancel.contains('cancelledTransferBy: callerUid'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('H-3x 급여 수정 (§11·§16 E·F)', () {
    test('E WAGE_ADJUSTED 가 before/after 를 남긴다', () {
      final f = _fn(code, 'export const callableUpdateWageDetail');
      expect(f.contains('eventType: "WAGE_ADJUSTED"'), isTrue);
      expect(f.contains('beforeFinalWage: prevFinalWage'), isTrue);
      expect(f.contains('afterFinalWage: finalWage'), isTrue);
      expect(f.contains('srvMoneyAuditWageDiff('), isTrue);
    });

    test('E2 전체 스냅샷을 복제하지 않는다', () {
      final f = _fn(code, 'export const callableUpdateWageDetail');
      expect(f.contains('changed: wageChanged'), isTrue);
      expect(f.contains('beforeWageDetail: prevWageDetail'), isFalse,
          reason: '금액에 영향을 준 항목만 남긴다');
    });

    test('F 달라진 것이 없으면 사건을 만들지 않는다', () {
      final f = _fn(code, 'export const callableUpdateWageDetail');
      expect(
        f.contains(
            'if (Object.keys(wageChanged).length > 0 || prevFinalWage !== finalWage)'),
        isTrue,
      );
    });

    test('§12 없는 사유를 발명하지 않았다', () {
      final f = _fn(code, 'export const callableUpdateWageDetail');
      // 이 API 에는 reason 입력이 없다 — 그래서 넣지 않는다.
      expect(f.contains('reason:'), isFalse);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('H-4x 마감 취소 (§13·§16 G)', () {
    test('G WAGE_REOPENED 가 actor·시각·전이를 남긴다', () {
      final f = _fn(code, 'export const callableCancelFinalConfirmation');
      expect(f.contains('eventType: "WAGE_REOPENED"'), isTrue);
      expect(f.contains('actorUid: callerUid'), isTrue);
      expect(f.contains('beforeWageStatus: "confirmed"'), isTrue);
      expect(f.contains('afterWageStatus: "calculated"'), isTrue);
      expect(f.contains('beforeFinalWage:'), isTrue);
    });

    test('G2 confirmedBy 를 지우는 기존 동작은 그대로다', () {
      final f = _fn(code, 'export const callableCancelFinalConfirmation');
      expect(f.contains('confirmedBy: admin.firestore.FieldValue.delete()'),
          isTrue, reason: '현재 상태 정리는 유지 — 사건만 따로 남긴다');
    });

    test('H·I 거절·미전이는 사건을 만들지 않는다', () {
      final f = _fn(code, 'export const callableCancelFinalConfirmation');
      // 상태가 아니면 return null — update 에도 audit 에도 닿지 않는다.
      final guard = f.indexOf(
          'if (data.wageStatus === "transferred" || data.wageStatus !== "confirmed") return null;');
      final audit = f.indexOf('eventType: "WAGE_REOPENED"');
      expect(guard, greaterThan(-1));
      expect(guard, lessThan(audit));
    });
  });

  // ───────────────────────────────────────────────────────────
  group('H-5x 권한·규칙 (§14·§20)', () {
    test('네 writer 의 기존 권한 판정이 그대로다', () {
      for (final f in <List<String>>[
        ['export const callableMarkTransferredBatch', 'canManageWage'],
        ['export const callableCancelTransfer', 'canCancelTransfer'],
        ['export const callableUpdateWageDetail', 'canManageWage'],
        ['export const callableCancelFinalConfirmation', 'canManageWage'],
      ]) {
        expect(_fn(code, f[0]).contains(f[1]), isTrue, reason: '${f[0]} ${f[1]}');
      }
    });

    test('권한 판정이 감사 기록보다 앞이다 — 거절되면 사건 0', () {
      for (final name in <String>[
        'export const callableMarkTransferredBatch',
        'export const callableCancelTransfer',
        'export const callableUpdateWageDetail',
        'export const callableCancelFinalConfirmation',
      ]) {
        final f = _fn(code, name);
        final perm = f.indexOf('assertBizAdmin(');
        final audit = f.indexOf('srvWriteMoneyAudit(');
        expect(perm, greaterThan(-1), reason: name);
        expect(audit, greaterThan(perm), reason: name);
      }
    });

    test('클라이언트 직접 접근을 명시적으로 막았다', () {
      final i = rules.indexOf('match /money_audit/{eventId}');
      expect(i, greaterThan(-1));
      final block = rules.substring(i, i + 200);
      expect(block.contains('allow read: if false;'), isTrue);
      expect(block.contains('allow write: if false;'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('H-6x 현재 금액 의미 불변 (§15)', () {
    test('payable population·날짜 권위가 그대로다', () {
      expect(code.contains('function srvIsNonPayableZero('), isTrue);
      expect(code.contains('function srvPayableForTransfer('), isTrue);
      final wage = _fn(code, 'export const callableCalculateAndConfirmWage');
      expect(wage.contains('yearMonth: canon.yearMonth'), isTrue);
    });

    test('legacy backfill 을 만들지 않았다 (§3)', () {
      for (final bad in <String>[
        'backfillMoneyAudit', 'migrateMoneyAudit', 'inferTransferEvent',
      ]) {
        expect(code.contains(bad), isFalse, reason: bad);
      }
    });

    test('전역 이벤트 스토어를 만들지 않았다 (§5)', () {
      expect(code.contains('"moneyEvents"'), isFalse);
      expect(code.contains('"eventStore"'), isFalse);
    });
  });
}
