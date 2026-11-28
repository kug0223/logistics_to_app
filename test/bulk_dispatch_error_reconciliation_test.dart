// [BULK-DISPATCH-ERROR-RECONCILIATION] 실패로 **보이는** 것과 실패인 것.
//
//   불변식 하나를 고정한다.
//
//     계약이 있거나, 있는지 확인할 수 없다면 — 지원서를 PENDING 으로
//     되돌리지 않는다.
//
//   오류 코드는 "어디까지 처리됐는지" 말해 주지 않는다. 서버는 트랜잭션
//   커밋 **뒤로는 던지지 않지만**(알림 실패는 CF 안에서 삼킨다), 전송 계층과
//   클라이언트 파싱은 커밋 뒤에도 던진다. 그래서 코드만 보고 되돌리면
//   계약서는 살아 있는데 지원서만 PENDING 이 되는 상태가 만들어진다 —
//   근로자가 PENDING 지원서의 계약서에 서명한다.
//
//   되돌리는 조건은 **전부** 맞아야 한다.
//     ① 원장 조회 성공 + 발송된 계약 없음
//     ② 지원서를 다시 읽을 수 있음
//     ③-0 이미 PENDING → 되돌릴 것이 없다(= 확정 전 실패, 확인된 실패)
//     ③ 좌석 보유 상태(CONFIRMED·CONTRACT_PENDING) 그대로
//     ④ 좌석 반납·해지·퇴사로 끝난 관계가 아님
//   응답을 못 받은 경우(`mayRollback: false`)는 원장이 "없다"고 해도
//   되돌리지 않는다 — 읽은 직후 커밋될 수 있어 신뢰 가능한 증거가 아니다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// 주석을 지운다 — 왜 바꿨는지 적은 문장에 옛 표현이 남아 있다.
String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 그룹 수집 시점에도 불리므로 expect 대신 예외로 실패시킨다.
String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  if (i < 0) throw StateError('구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  if (j < 0) throw StateError('구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

// ── 판단 복제 ────────────────────────────────────────────────────────
//
//   `settleFailure` 가 하는 판단 그대로다. 값이 바뀌면 여기가 먼저 깨진다.

/// 원장이 주는 세 가지 답 (`ContractLedgerProbe`).
enum Probe { issued, notIssued, unknown }

/// 지원서 재조회 결과.
class AppRead {
  final bool ok; // 읽기 성공?
  final bool exists;
  final String? status;
  final bool released; // staffingReleasedAt != null
  final String? termination;
  final String? resign;

  const AppRead({
    this.ok = true,
    this.exists = true,
    this.status = 'CONTRACT_PENDING',
    this.released = false,
    this.termination,
    this.resign,
  });
}

const _confirmedStatuses = ['CONFIRMED', 'CONTRACT_PENDING'];
const _endedStatuses = {'APPROVED', 'AUTO_APPROVED'};

class Settled {
  final String result;

  /// 이 경로가 지원서를 **쓰는가**. [ROLLBACK-ATOMICITY] 이후 언제나 false 다.
  final bool wrote;
  const Settled(this.result, {this.wrote = false});
}

Settled settle({
  required Probe probe,
  AppRead app = const AppRead(),
  bool mayRollback = true,
}) {
  if (probe == Probe.issued) return const Settled('already');
  if (probe == Probe.unknown) return const Settled('unknown');
  if (!mayRollback) return const Settled('unknown');
  if (!app.ok) return const Settled('unknown');
  if (!app.exists) return const Settled('unknown');
  if (app.status == 'PENDING') return const Settled('failed');
  if (app.status == null || !_confirmedStatuses.contains(app.status)) {
    return const Settled('rejected');
  }
  if (app.released ||
      _endedStatuses.contains(app.termination) ||
      _endedStatuses.contains(app.resign)) {
    return const Settled('rejected');
  }
  // 좌석은 유효하고 계약만 없다 — **쓰지 않는다.**
  return const Settled('needsReissue');
}

void main() {
  final workRaw =
      _read('lib/screens/business_admin/dialogs/work_applicants_dialog.dart');
  final work = _codeOf(workRaw);
  final svc = _codeOf(_read('lib/services/contract_service.dart'));
  final fn = _read('functions/src/index.ts');

  final settleSrc = _slice(work, 'Future<String> settleFailure(',
      'Future<String> processOne(Map<String, dynamic> item)');
  final path1 = _slice(work,
      'Future<String> processOne(Map<String, dynamic> item) async {',
      'const batchSize = 5;');

  group('BER-1 — 단계별 실패: 어디서 터졌는지가 답을 바꾼다', () {
    test('BER-01 ①확정 전 실패 — 되돌릴 것이 없고, 확인된 실패다', () {
      // 확정 callable 자체가 실패 → 지원서는 아직 PENDING.
      final s = settle(probe: Probe.notIssued, app: const AppRead(status: 'PENDING'));
      expect(s.result, 'failed');
      expect(s.wrote, isFalse, reason: '쓸 필요가 없다');
    });

    test('BER-02 ②확정 완료·계약 생성 전 실패 — 좌석 유지 + 재발송 요구', () {
      // [ROLLBACK-ATOMICITY] 예전에는 여기서 PENDING 으로 되돌렸다.
      //   그 쓰기가 다른 관리자의 정상 계약을 void 할 수 있었다.
      final s = settle(probe: Probe.notIssued);
      expect(s.result, 'needsReissue');
      expect(s.wrote, isFalse, reason: '쓰기가 없으면 남의 계약을 해칠 수 없다');
    });

    test('BER-03 ③계약 저장 전 검증 오류 — ②와 같다', () {
      // invalid-argument·failed-precondition·not-found 는 모두 커밋 전이다.
      //   그래도 코드로 단정하지 않고 원장을 본 뒤 같은 결론에 이른다.
      final s = settle(probe: Probe.notIssued, app: const AppRead(status: 'CONFIRMED'));
      expect(s.result, 'needsReissue');
      expect(s.wrote, isFalse);
    });

    test('BER-04 ⑤계약 저장 성공·응답 유실 — 원장에 보이면 already', () {
      final s = settle(probe: Probe.issued, mayRollback: false);
      expect(s.result, 'already');
      expect(s.wrote, isFalse);
    });

    test('BER-05 ⑤응답 유실 + 원장엔 아직 없음 — 좌석 판단으로 넘어가지 않는다', () {
      // 읽은 직후 커밋될 수 있다. "없다"가 "안 될 것이다"는 아니다.
      final s = settle(probe: Probe.notIssued, mayRollback: false);
      expect(s.result, 'unknown');
      expect(s.wrote, isFalse);
    });

    test('BER-06 ⑥알림 실패는 계약 실패가 아니다 (서버 코드)', () {
      // CF 는 알림 블록을 try/catch 로 감싸고 **던지지 않는다.**
      //   커밋 뒤에 서버가 던지는 경로가 없다는 것이 분류의 근거다.
      // `fn` 은 원문이다(주석 포함) — 표지로 주석을 쓸 수 있다.
      final cf = _slice(fn, 'export const callableFinalizeEmployerSignature',
          '// ── voidContractAtomicLifecycle');
      final afterTx = _slice(cf, '_mark("tx");', 'return {');
      // [L56 r4] 두 모양 중 하나: ① 예전 — 커밋 뒤 알림을 try/catch 로 감싸 던지지 않는다 ·
      //   ② 지금 — 알림은 서명 거래 안 direct 작업이고 커밋 뒤에는 알림 쓰기 자체가 없다(실패가 서명으로 번질 길이 없다).
      // [판정292] 정확히 하나: 작업 경로면 커밋 뒤 알림 쓰기·try/catch 가 **없어야** 하고(이중 발송 0), 예전 경로면 작업이 없어야 한다.
      final berJobs = 'tx.create(signJobRef, srvNotificationJobDoc("direct", {'.allMatches(cf).length;
      final berAfterDirect = RegExp(r'srvPersistNotification(WithId)?\(').hasMatch(afterTx);
      final viaJob = berJobs == 2 && !berAfterDirect;
      final viaOld = berJobs == 0 && afterTx.contains('} catch (notifErr) {');
      expect(viaJob || viaOld, isTrue,
          reason: '알림 실패가 서명 실패로 전파되면 분류 전제가 깨진다(또는 작업·직접 호출이 섞였다)');
      expect(afterTx.contains('throw '), isFalse,
          reason: '커밋 뒤에 서버가 던지면 "정상 반환 = 커밋"이 성립하지 않는다');
      if (!viaJob) expect(_flat(afterTx), contains('알림 실패는 계약서 저장 성공에 영향 없음'));
    });
  });

  group('BER-2 — already / unknown 은 되돌리지 않는다', () {
    test('BER-10 ⑦already-exists + pending_worker 계약', () {
      expect(settle(probe: Probe.issued).result, 'already');
    });

    test('BER-11 ⑧already-exists + completed 계약 — 같은 답', () {
      // 원장 술어는 "발송됐는가" 하나다. completed 도 발송된 것이다.
      expect(settle(probe: Probe.issued).result, 'already');
    });

    test('BER-12 ⑩원장 재조회 실패 — 0건으로 바꾸지 않는다', () {
      final s = settle(probe: Probe.unknown);
      expect(s.result, 'unknown');
      expect(s.wrote, isFalse, reason: 'ERROR != ZERO');
    });

    test('BER-13 지원서 재조회 실패 — 분류를 멈춘다', () {
      final s = settle(probe: Probe.notIssued, app: const AppRead(ok: false));
      expect(s.result, 'unknown');
      expect(s.wrote, isFalse);
    });

    test('BER-14 지원서가 없다 — 확인 불가다', () {
      final s = settle(probe: Probe.notIssued, app: const AppRead(exists: false));
      expect(s.result, 'unknown');
    });

    test('BER-15 어떤 분기도 지원서를 쓰지 않는다', () {
      // [ROLLBACK-ATOMICITY] 쓰기 경로 자체가 사라졌다 —
      //   "되돌리기가 실패하면?"이라는 질문이 성립하지 않는다.
      for (final p in [Probe.issued, Probe.notIssued, Probe.unknown]) {
        for (final may in [true, false]) {
          expect(settle(probe: p, mayRollback: may).wrote, isFalse);
        }
      }
    });
  });

  group('BER-3 — ⑪⑮ 후속 변경·끝난 관계는 손대지 않는다', () {
    test('BER-20 ⑪다른 관리자가 취소했다', () {
      for (final st in ['CANCELED', 'AUTO_CANCELED', 'REJECTED', 'EXPIRED']) {
        final s = settle(probe: Probe.notIssued, app: AppRead(status: st));
        expect(s.result, 'rejected', reason: '$st 인데 손을 댔다');
        expect(s.wrote, isFalse);
      }
    });

    test('BER-21 ⑮NO_SHOW 는 자동 롤백하지 않는다', () {
      final s = settle(probe: Probe.notIssued, app: const AppRead(status: 'NO_SHOW'));
      expect(s.result, 'rejected');
      expect(s.wrote, isFalse);
    });

    test('BER-22 ⑮이미 완료된 계약 — 원장이 먼저 걸러낸다', () {
      expect(settle(probe: Probe.issued, app: const AppRead(status: 'CONTRACT_PENDING'))
          .result, 'already');
    });

    test('BER-23 좌석 반납된 자리는 건드리지 않는다', () {
      final s = settle(probe: Probe.notIssued, app: const AppRead(released: true));
      expect(s.result, 'rejected');
      expect(s.wrote, isFalse);
    });

    test('BER-24 해지·퇴사가 승인된 관계는 건드리지 않는다', () {
      for (final st in ['APPROVED', 'AUTO_APPROVED']) {
        expect(settle(probe: Probe.notIssued, app: AppRead(termination: st)).result,
            'rejected');
        expect(settle(probe: Probe.notIssued, app: AppRead(resign: st)).result,
            'rejected');
      }
      // PENDING 해지 요청은 아직 끝난 관계가 아니다 — 좌석은 유효하다.
      expect(settle(probe: Probe.notIssued, app: const AppRead(termination: 'PENDING'))
          .result, 'needsReissue');
    });
  });

  group('BER-4 — ⑫⑬⑭ 중복·부분 실패·재시도', () {
    test('BER-30 ⑫같은 지원서를 두 번 보내도 계약은 하나다', () {
      // 두 번째 호출은 서버가 already-exists 로 막고, 우리는 쓰지 않는다.
      expect(settle(probe: Probe.issued).wrote, isFalse);
    });

    test('BER-31 ⑬3건 중 일부 실패 — 결과가 섞이지 않는다', () {
      final results = [
        settle(probe: Probe.notIssued).result, // 재발송 필요
        settle(probe: Probe.issued).result, // 이미 발송
        settle(probe: Probe.unknown).result, // 확인 필요
      ];
      expect(results, ['needsReissue', 'already', 'unknown']);
    });

    test('BER-32 ⑭재시도 대상은 좌석을 쥔 채 남는다', () {
      // 어떤 결과에서도 지원서가 대기 목록으로 내려가지 않는다.
      //   관리자는 `계약서 미작성` 목록에서 그 건만 다시 보낸다.
      for (final p in [Probe.notIssued, Probe.issued, Probe.unknown]) {
        expect(settle(probe: p).wrote, isFalse);
      }
      expect(settle(probe: Probe.notIssued).result, 'needsReissue');
    });

    test('BER-33 재시도한 건이 이미 발송됐으면 중복 발송이 아니다', () {
      expect(settle(probe: Probe.issued).result, 'already');
    });
  });

  group('BER-5 — 실제 배선이 같은 판단을 쓴다', () {
    test('BER-40 settleFailure 가 원장을 먼저 본다', () {
      final probeAt = settleSrc.indexOf('probeIssuedContract(');
      final readAt = settleSrc.indexOf("collection('applications')");
      expect(probeAt, greaterThan(-1), reason: '원장 조회가 없다');
      expect(readAt, greaterThan(probeAt), reason: '원장보다 지원서를 먼저 읽었다');
    });

    test('BER-41 분류 조건이 모두 코드에 있다', () {
      expect(_flat(settleSrc), contains('ContractLedgerProbe.issued'));
      expect(_flat(settleSrc), contains('ContractLedgerProbe.unknown'));
      expect(_flat(settleSrc), contains('AppStatus.confirmedStatuses.contains(nowStatus)'));
      expect(_flat(settleSrc), contains("appData['staffingReleasedAt'] != null"));
      expect(_flat(settleSrc), contains("appData['terminationStatus']"));
      expect(_flat(settleSrc), contains("appData['resignStatus']"));
      expect(_flat(settleSrc), contains('Source.server'),
          reason: '캐시를 읽고 분류하면 낡은 상태로 판단한다');
    });

    test('BER-42 확정 상태 집합은 서버와 같은 한 벌이다', () {
      // 확정 CF 가 쓰는 값은 CONTRACT_PENDING 이다 — CONFIRMED 만 보면
      //   정상 경로가 전부 `rejected` 로 떨어진다.
      expect(fn, contains('const CONFIRMED_STATUSES = ["CONFIRMED", "CONTRACT_PENDING"];'));
      final model = _read('lib/models/core/application_model.dart');
      expect(model,
          contains('confirmedStatuses = [confirmed, contractPending]'));
      final confirmCf = _slice(fn, 'export const callableConfirmApplication',
          'export const ');
      expect(_flat(confirmCf), contains('status: "CONTRACT_PENDING",'),
          reason: '확정이 쓰는 값이 바뀌면 좌석 판정도 바뀐다');
    });

    test('BER-43 응답 미수신은 원장을 올려 주는 데만 쓴다', () {
      final indet = _slice(path1, '_indeterminateCfCodes.contains(e.code)',
          '} catch (itemErr)');
      expect(_flat(indet), contains('mayRollback: false'));
      expect(_flat(settleSrc), contains('if (!mayRollback)'));
      // `settleSrc` 는 주석이 지워진 코드다 — 표지도 코드여야 한다.
      final noSeatJudgement = _slice(settleSrc, 'if (!mayRollback)',
          "if ((appData['status'] as String?) == AppStatus.pending)");
      expect(noSeatJudgement.contains("return 'needsReissue'"), isFalse,
          reason: '응답을 못 받은 건을 "계약만 없다"로 단정하면 안 된다');
    });

    test('BER-44 두 catch 가 모두 원장을 본다 (커밋 뒤 예외 포함)', () {
      final fnEx = _slice(path1, 'on FirebaseFunctionsException catch (e)',
          '} catch (itemErr)');
      final generic = _slice(path1, '} catch (itemErr)', '}\n      }');
      expect(_flat(fnEx), contains('settleFailure(appId, e, mayRollback: true)'));
      expect(_flat(generic),
          contains('settleFailure(appId, itemErr, mayRollback: true)'));
    });

    test('BER-45 **클라이언트에 확정 롤백 writer 가 하나도 없다**', () {
      // [ROLLBACK-ATOMICITY §11] 이것이 불변식의 증명이다.
      //   오래된 실패 복구가 남의 계약을 무효화할 수 없는 이유는 가드가
      //   똑똑해서가 아니라, **되돌리는 쓰기 자체가 없어서**다.
      //   트랜잭션 의미론에 의존하지 않는 증명이다.
      final dir = Directory('lib');
      final offenders = <String>[];
      for (final f in dir.listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final src = _codeOf(f.readAsStringSync());
        if (src.contains('status: AppStatus.pending')) offenders.add(f.path);
      }
      expect(offenders, isEmpty,
          reason: '확정→PENDING 쓰기가 되살아났다: $offenders');
      // void 호출도 그 경로에서만 일어났다 — 실패 복구가 계약을 지우지 않는다.
      expect(settleSrc.contains('callableVoidApplicationContracts'), isFalse);
      expect(settleSrc.contains('updateApplicationStatus'), isFalse);
    });

    test('BER-46 2차 피해 경고는 원인과 함께 사라졌다', () {
      // 확정을 되돌리지 않으므로 겹침 자동취소(B)는 **옳은 결과**다.
      //   복구 불가 경고가 가리켰던 상태가 생기지 않는다.
      expect(work.contains('batchRollbackWithCollateral'), isFalse,
          reason: '롤백이 없는데 롤백 경고가 남아 있다');
      expect(_flat(path1), contains('_affectedOtherTOIds.addAll(affectedTOIds)'),
          reason: '겹침 TO 캐시 무효화는 그대로 유지한다');
    });
  });

  group('BER-6 — 원장 조회 자체의 계약', () {
    test('BER-50 세 상태를 구별해 돌려준다', () {
      expect(svc, contains('enum ContractLedgerProbe'));
      for (final v in ['issued', 'notIssued', 'unknown']) {
        expect(svc, contains('  $v,'), reason: '$v 가 없다');
      }
    });

    test('BER-51 읽기 실패·모양 이상은 unknown 이다', () {
      final probe = _slice(svc, 'Future<ContractLedgerProbe> probeIssuedContract',
          'Future<ContractStatusBatch> getContractStatusBatch');
      expect(_flat(probe), contains('if (data is! Map) return ContractLedgerProbe.unknown'));
      expect(_flat(probe), contains('if (listRaw is! List) return ContractLedgerProbe.unknown'));
      expect(_flat(probe), contains('} catch (e) { debugPrint'));
      expect(_flat(probe), contains('return ContractLedgerProbe.unknown; }'));
      // 실패를 삼켜 null 로 돌려주는 기존 조회를 쓰지 않는다.
      expect(probe.contains('getByApplication'), isFalse);
    });

    test('BER-52 발송 판정식이 서버와 같다', () {
      final probe = _slice(svc, 'Future<ContractLedgerProbe> probeIssuedContract',
          'Future<ContractStatusBatch> getContractStatusBatch');
      for (final s in ['voided', 'pending_employer', 'draft']) {
        expect(_flat(probe), contains("s == '$s'"), reason: '$s 가 빠졌다');
      }
      // 서버 술어 원문 — 같은 네 가지다.
      final srv = _slice(fn, 'function srvContractNotIssuedYet', '\n}\n');
      for (final s in ['voided', 'pending_employer', 'draft']) {
        expect(srv, contains('"$s"'));
      }
      expect(_flat(srv), contains('if (!status) return true;'));
    });

    test('BER-53 그 지원서 하나만 읽는다 — 목록 재로드·polling 없음', () {
      final probe = _slice(svc, 'Future<ContractLedgerProbe> probeIssuedContract',
          'Future<ContractStatusBatch> getContractStatusBatch');
      expect(_flat(probe), contains("'applicationId': applicationId,"));
      expect(_flat(probe), contains("'limit': 10,"));
      expect(probe.contains('Timer'), isFalse);
      expect(probe.contains('snapshots('), isFalse);
      expect(probe.contains('while ('), isFalse);
    });

    test('BER-54 새 서버 함수를 만들지 않았다', () {
      final probe = _slice(svc, 'Future<ContractLedgerProbe> probeIssuedContract',
          'Future<ContractStatusBatch> getContractStatusBatch');
      expect(_flat(probe), contains("httpsCallable('callableGetContractsByBiz'"));
      expect(fn.contains('callableRollbackApplication'), isFalse,
          reason: '새 rollback callable 금지');
    });
  });

  group('BER-7 — 커밋 뒤 클라이언트 예외를 줄였다', () {
    test('BER-60 응답이 Map 이 아니어도 캐스트로 터지지 않는다', () {
      final sign = _slice(svc, 'Future<EmploymentContractModel> saveEmployerSignature',
          'Future<EmploymentContractModel> saveWorkerSignature');
      // [E2-EMPLOYER-SIG-LOST-RESPONSE] 응답 값을 한 변수로 받게 바뀌었다 — 보장은 같다.
      expect(_flat(sign), contains('final cfMap = responseData is Map ? responseData : null;'));
      expect(sign.contains('as Map<dynamic, dynamic>'), isFalse);
    });

    test('BER-61 경로·URL 이 둘 다 없어도 실패로 바꾸지 않는다', () {
      final sign = _slice(svc, 'Future<EmploymentContractModel> saveEmployerSignature',
          'Future<EmploymentContractModel> saveWorkerSignature');
      // 조건은 유지한다(SIGX-61) — 던지지 않는 것만 바뀌었다.
      expect(_flat(sign), contains('if (sigPath.isEmpty && url.isEmpty)'));
      expect(sign.contains("throw Exception('CF 응답에 사업주 서명 경로가 없음')"), isFalse,
          reason: '커밋 뒤 예외가 롤백 판단으로 흘러간다');
      expect(_flat(sign), contains('employerSignatureAvailable: true'));
    });

    test('BER-62 CF 실패는 여전히 예외로 올라온다', () {
      // 커밋 전 실패를 삼키면 안 된다 — 호출부가 알아야 한다.
      final sign = _slice(svc, 'Future<EmploymentContractModel> saveEmployerSignature',
          'Future<EmploymentContractModel> saveWorkerSignature');
      // [E2-EMPLOYER-SIG-LOST-RESPONSE] 호출을 감싸게 됐다. 대신 성공으로 바꾸는 길은
      //   원장에서 **이번 서명의 커밋이 증명될 때** 하나뿐이고, 명확한 거절은 그대로
      //   다시 던지며, 증명 못 한 불명확은 원래 code 를 가진 예외로 올라온다
      //   (일괄 발송은 그 code 로 '불명확' 분기를 탄다 — 확정을 되돌리지 않는다).
      final f = _flat(sign);
      expect(f, contains('.call(cfData))'));
      expect(f, contains('on FirebaseFunctionsException catch (e) {'));
      expect(f, contains('if (!kEmployerSignatureIndeterminateCodes.contains(e.code)) rethrow;'));
      expect(f, contains("if (verdict != 'committed') {"));
      expect(f, contains('throw SignatureOutcomeUnknown(code: e.code, reason: verdict);'));
      expect(RegExp(r'catch \(').allMatches(f.split('Future<String> _confirmEmployerSignatureCommitted')[0]).length, 1,
          reason: 'callable 실패를 받는 곳은 하나 — 다른 예외는 삼키지 않는다');
    });
  });
}
