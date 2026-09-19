// [BULK-OPERATIONS.2] 계약·근태·급여·이체 일괄 처리
//
// 한 사람의 실패가 다른 사람의 계약이나 금액을 건드리면 안 된다.
// 아래는 DEV 실측 결과와, 그 결과를 만들어 낸 구조를 고정한 것이다.
//
// 계약 일괄 발송 (bounded concurrency 5, 10/30/60명)
//   4.6s / 4.9s / 10.0s · 성공 100% · 교차오염 0 · 알림 누락 0 · 중복 0
//   같은 계약서 재발송 → 409 "이미 계약서가 생성되었습니다" · 문서·알림 중복 없음
//   미발송 큐 Δ −30 / −60 (발송 수와 일치)
//
// 근태 일괄 시간보정 (10명 혼합)
//   processed 7 / skipped 3
//   pending → 시각 변경 + 사유 저장 · calculated → pending 복귀 + 금액 삭제
//   NO_SHOW · absent · confirmed → skip (시각·금액 불변)
//
// 급여 일괄 확정 (각자 다른 단가)
//   11000/11500/12000 → 88000/92000/96000 · 전원 자기 금액 · 지급일·계좌 snapshot
//   지급일을 못 푸는 건이 섞이면 전체가 쓰이지 않는다(all-or-nothing)
//
// 이체 일괄 (혼합 10건)
//   confirmed만 transferred로 이동 · calculated/pending은 skip
//   재실행 → finalWage·transferDate 불변
//   근로자 수입 조회 = 서버 (88000 / transferred)

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';
const _contractSvcPath = 'lib/services/contract_service.dart';
const _dialogPath =
    'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _callableOf(String source, String name) {
  final start = source.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final next = source.indexOf('\nexport ', start + 10);
  return source.substring(start, next == -1 ? source.length : next);
}

void main() {
  final raw = _src(_fnsPath);
  final fns = _codeOf(raw);
  final fnsFlat = _flat(fns);

  group('계약 일괄 발송은 사람마다 자기 것을 쓴다', () {
    test('임금 snapshot을 덮어쓸 때 공유 객체를 변형하지 않는다', () {
      final svc = _codeOf(_src(_contractSvcPath));
      final i = svc.indexOf('WorkDetailData _withPromisedWage(');
      expect(i > 0, true);
      final body = svc.substring(i, i + 1400);
      // copyWith는 새 객체를 돌려준다 — 일괄 발송이 하나의 workDetail을
      // 돌려쓰므로, 여기서 원본을 고치면 뒷사람 계약에 앞사람 임금이 남는다.
      expect(body.contains('workDetail.copyWith('), true);
      expect(RegExp(r'workDetail\.\w+\s*=').hasMatch(body), false,
          reason: '공유 객체에 대입하면 근로자 간 값이 섞인다');
    });

    test('지원 시점 임금이 없으면 그 건만 실패시킨다', () {
      final svc = _codeOf(_src(_contractSvcPath));
      expect(svc.contains('지원 시점 임금 정보가 없어 계약서를 만들 수 없습니다'), true,
          reason: '조용히 공고의 현재 임금으로 대체하면 약속이 바뀐다');
    });

    test('동시 처리 폭이 제한돼 있다', () {
      final d = _flat(_codeOf(_src(_dialogPath)));
      expect(d.contains('const batchSize = 5;'), true,
          reason: '무제한 병렬은 Storage·CF 부하를 튀긴다');
    });

    test('같은 계약서 재발송은 서버가 막는다', () {
      final cf = _codeOf(_callableOf(raw, 'callableFinalizeEmployerSignature'));
      expect(cf.contains('이미 계약서가 생성되었습니다'), true,
          reason: '재시도가 계약서·알림을 두 벌 만들면 안 된다');
    });
  });

  group('근태 일괄 보정은 상태별로 다르게 끝난다', () {
    final adj =
        _flat(_codeOf(_callableOf(raw, 'callableBatchAdjustAttendanceTime')));

    test('확정·이체된 건은 건너뛴다', () {
      expect(
        adj.contains(
            'if (serverStatus === "confirmed" || serverStatus === "transferred")'),
        true,
      );
    });

    test('계산된 건은 금액을 무효화한다', () {
      expect(
        adj.contains(
            'const effectiveResetWageDetail = resetWageDetail || serverStatus === "calculated";'),
        true,
      );
    });

    test('사유는 실제로 바뀐 건에만 남는다', () {
      expect(adj.contains('if (didChangeTime && adjReason.length > 0)'), true);
      expect(adj.contains('updates["modifyReason"] = adjReason'), true);
    });

    test('일부가 걸러져도 나머지는 처리된다', () {
      expect(adj.contains('skipped.push(attendanceId)'), true);
      expect(adj.contains('successCount++'), true,
          reason: '한 건이 막혔다고 전체를 되돌리지 않는다');
    });
  });

  group('급여 확정은 자기 근태에서만 금액을 만든다', () {
    final conf = _codeOf(_callableOf(raw, 'callableConfirmFinalWage'));
    final flat = _flat(conf);

    test('계산된 건만 확정한다', () {
      expect(flat.contains('if (data.wageStatus !== "calculated")'), true);
      expect(flat.contains('return "already_closed"'), true,
          reason: '이미 확정·이체된 건은 다시 확정하지 않는다');
    });

    test('지급일을 못 푸는 건이 있으면 아무것도 쓰지 않는다', () {
      expect(conf.contains('급여 지급일을 확인할 수 없습니다'), true,
          reason: '일부만 확정되면 지급일 없는 금액이 남는다');
    });

    test('확정 시점에 계좌를 그 사람 것으로 snapshot한다', () {
      for (final f in [
        'wageAccountBankName',
        'wageAccountNumberEncrypted',
        'wageAccountHolder',
        'wageAccountSnapshotAt',
      ]) {
        expect(flat.contains(f), true, reason: '$f 가 빠지면 이체 대상이 불완전해진다');
      }
    });
  });

  group('이체는 확정된 것만, 한 번만', () {
    final tr = _flat(_codeOf(_callableOf(raw, 'callableMarkTransferredBatch')));

    test('confirmed가 아닌 건은 건너뛴다', () {
      // [PII-DOC-R0.2] 제외 지점에 사유 기록이 추가돼 문장이 나뉘었다.
      //   불변식("calculated·pending은 이체되지 않는다")은 그대로다.
      final i = tr.indexOf('if (ws !== "confirmed") {');
      expect(i > 0, true, reason: 'calculated·pending을 이체 완료로 만들면 안 된다');
      final block = tr.substring(i, i + 140);
      expect(block.contains('skipped.push(id)'), true);
      expect(block.contains('continue;'), true);
    });

    test('권한은 급여 권한이다', () {
      expect(tr.contains('canManageWage'), true);
    });
  });
}
