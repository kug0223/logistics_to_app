// [BULK-OPERATIONS.2A] 이체는 실제로 돈이 간 건에만, 그리고 한 번만
//
// 두 가지를 고쳤다.
//
//   1. NO_SHOW와 결근은 finalWage 0으로 마감되면서 wageStatus가 confirmed가
//      된다. 이체 writer는 wageStatus만 봤으므로 그 둘이 그대로 통과해
//      "이체 처리 완료"가 됐다 — 보낸 돈은 0원인데. 급여 대시보드가 목록에서
//      빼 주고 있었을 뿐, 서버에는 조건이 없었다.
//   2. 이미 이체된 건을 processed로 세고 있었다. 같은 목록을 다시 보내면
//      아무것도 바뀌지 않는데 "N건 이체 처리"라고 답했고, 화면도 그대로
//      성공이라고 말했다.
//
// DEV runtime (수정 후):
//   present/late/early_leave · >0 · confirmed → transferred
//   NO_SHOW · 0 · confirmed                   → skip (confirmed 유지)
//   absent  · 0 · confirmed                   → skip
//   present · >0 · calculated                 → skip
//   present · >0 · transferred                → alreadyTransferred (시각 불변)
//   7/7 기대와 일치 · 재실행 processed=0 already=4 · 이체시각 변경 0건
//   NO_SHOW 근로자 조회: wageStatus=confirmed — 이체 완료로 보이지 않음
//
// 그리고 급여 확정 ↔ 근태 보정을 실제로 동시에 던졌을 때(그리고 보정 선행
// 순서에서도) 결과는 하나였다: 시각이 09:30으로 바뀌고 wageStatus가 pending으로
// 돌아가고 금액이 삭제되고 사유가 남았으며, 확정은 skip됐다. 시각이 바뀐 채
// 예전 금액이 confirmed로 남는 상태는 나오지 않았다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';
const _svcPath = 'lib/services/payroll_payment_service.dart';
const _dashPath =
    'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';

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
  final tr = _codeOf(_callableOf(raw, 'callableMarkTransferredBatch'));
  final trFlat = _flat(tr);

  group('지급 대상이 아닌 기록은 이체하지 않는다', () {
    test('서버가 status와 finalWage를 직접 본다', () {
      expect(
        trFlat.contains(
            'if ((attStatus === "NO_SHOW" || attStatus === "absent") && fw === 0)'),
        true,
        reason: '화면이 목록에서 빼 주는 것에 기대면 직접 호출로 뚫린다',
      );
      final i = trFlat.indexOf('attStatus === "NO_SHOW"');
      final w = trFlat.indexOf('wageStatus: "transferred"');
      expect(i > 0 && w > i, true, reason: '쓰기 전에 걸러야 한다');
    });

    test('미이체 집계와 같은 식을 쓴다', () {
      // srvHomeUnpaidWage의 nonPayable 판정과 같은 조건이어야 한다 —
      // 목록에서 빠진 건이 이체에서는 통과하면 두 화면이 다른 말을 한다.
      expect(
        _flat(_codeOf(raw)).contains(
            'const nonPayable = (st === "NO_SHOW" || st === "absent") && fw === 0;'),
        true,
      );
    });

    test('confirmed가 아닌 건은 여전히 건너뛴다', () {
      // [PII-DOC-R0.2] 제외 지점마다 **사유**가 함께 기록되면서 한 줄이 두 줄이 됐다.
      //   고정하려던 것은 "calculated·pending이 이체되지 않는다"이지
      //   그 두 문장이 붙어 있다는 사실이 아니다.
      final i = trFlat.indexOf('if (ws !== "confirmed") {');
      expect(i > 0, true, reason: 'calculated·pending을 이체 완료로 만들면 안 된다');
      final block = trFlat.substring(i, i + 140);
      expect(block.contains('skipped.push(id)'), true);
      expect(block.contains('continue;'), true);
      expect(block.contains('blocked[id] = XFER_NOT_CONFIRMED'), true,
          reason: '왜 제외됐는지도 함께 돌려준다');
    });
  });

  group('재실행은 처리했다고 말하지 않는다', () {
    test('이미 이체된 건을 processed로 세지 않는다', () {
      final i = trFlat.indexOf('if (ws === "transferred")');
      expect(i > 0, true);
      final block = trFlat.substring(i, i + 120);
      expect(block.contains('alreadyTransferred.push(id)'), true);
      expect(block.contains('processed++'), false,
          reason: '멱등 통과를 성공으로 세면 재시도가 새 이체처럼 보인다');
    });

    test('응답이 실제 delta와 멱등 통과를 구분한다', () {
      expect(trFlat.contains('alreadyTransferred,'), true,
          reason: '응답에 already가 없으면 화면이 구분할 수 없다');
    });

    test('클라이언트가 서버 숫자를 그대로 쓴다', () {
      final svc = _flat(_codeOf(_src(_svcPath)));
      expect(svc.contains("confirmedCount += (data['processed'] as int?) ?? 0;"), true);
      expect(svc.contains('confirmedCount += chunk.length - (skipped.length);'), false,
          reason: '선택 수에서 skip을 빼면 already가 성공에 섞인다');
      expect(svc.contains('final int transferredNow;'), true);
    });

    test('화면이 새로 처리한 건수만 성공으로 말한다', () {
      final dash = _flat(_codeOf(_src(_dashPath)));
      expect(dash.contains('final processedCount = batchResult.transferredNow;'), true);
      expect(dash.contains('이미 이체 완료된 항목이에요'), true,
          reason: '아무것도 안 바뀐 경우를 침묵으로 두지 않는다');
    });
  });

  group('돈이 확정된 뒤 근태가 조용히 바뀌지 않는다', () {
    test('확정·이체 건은 시간 보정에서 제외된다', () {
      final adj =
          _flat(_codeOf(_callableOf(raw, 'callableBatchAdjustAttendanceTime')));
      expect(
        adj.contains(
            'if (serverStatus === "confirmed" || serverStatus === "transferred")'),
        true,
      );
    });

    test('계산 상태에서 시간이 바뀌면 금액이 무효화된다', () {
      final adj =
          _flat(_codeOf(_callableOf(raw, 'callableBatchAdjustAttendanceTime')));
      expect(
        adj.contains(
            'const effectiveResetWageDetail = resetWageDetail || serverStatus === "calculated";'),
        true,
        reason: '금액을 남겨 두면 바뀐 시간과 옛 금액이 함께 확정될 수 있다',
      );
    });

    test('확정은 계산된 건만 받는다', () {
      final conf = _flat(_codeOf(_callableOf(raw, 'callableConfirmFinalWage')));
      expect(conf.contains('if (data.wageStatus !== "calculated")'), true,
          reason: '보정이 먼저 커밋되면 pending이 되므로 확정이 들어와도 걸러진다');
    });
  });

  group('돈을 움직이기 전에 범위가 보인다', () {
    final dash = _flat(_codeOf(_src(_dashPath)));

    test('전체 선택은 현재 필터 결과까지다', () {
      expect(dash.contains('final allIds = groups.expand((e) => e.value.map((r) => r.id)).toSet();'),
          true, reason: '숨은 목록까지 포함되면 범위를 알 수 없다');
      expect(dash.contains('onSelectAll: () => setState(() => _selectedIds.addAll(allIds)),'),
          true);
    });

    test('선택 인원과 금액을 함께 보여준다', () {
      expect(dash.contains('selectedCount: _selectedIds.length,'), true);
      expect(dash.contains('selectedAmount: _selectedNet,'), true,
          reason: '금액 없이 인원만 보면 얼마가 나가는지 모른다');
      expect(dash.contains('onAction: _selectedIds.isNotEmpty && _selectedNet > 0'), true);
    });

    test('범위가 바뀌면 선택을 비운다', () {
      expect('_selectedIds.clear()'.allMatches(dash).length >= 4, true,
          reason: '탭·재로드·필터 변경에서 이전 선택이 남으면 다른 맥락의 급여가 섞인다');
    });
  });

  // 계약서 중복 발송 — contractId 가드만으로는 막히지 않던 구멍.
  //
  // 발송이 타임아웃된 줄 알고 다시 누르면 클라이언트는 새 contractId를 만든다.
  // 서버 가드는 그 문서가 있는지만 봤으므로 통과했고, 같은 근무에 계약서가
  // 두 장 가고 근로자에게 서명 요청 알림이 두 번 갔다.
  // (측정: 다른 contractId 2회 → 계약서 3건 · 알림 3건)
  //
  // 수정 후 DEV:
  //   동시·다른 contractId  → [거부 | OK]  계약서 1건 · 알림 1건 · 고아 문서 없음 (2회 반복 동일)
  //   순차 재시도           → [OK | 거부]  계약서 1건 · 알림 1건
  //   무효화 후 재발송      → OK           정당한 재발송은 그대로 가능
  //   60명 벤치마크 10776ms · 성공 60/60 · 교차오염 0 · 알림중복 0 (회귀 없음)
  group('같은 근무에 계약서가 두 장 가지 않는다', () {
    final cf = _codeOf(_callableOf(raw, 'callableFinalizeEmployerSignature'));
    final cfFlat = _flat(cf);

    test('클라이언트에 진행 중 잠금이 있다', () {
      final d = _flat(_codeOf(_src(
          'lib/screens/business_admin/dialogs/day_applicants_dialog.dart')));
      expect(d.contains('if (_contractBatchGroupKey != null) return;'), true);
    });

    test('서버가 contractId가 아니라 지원서 기준으로 막는다', () {
      expect(cfFlat.contains('이미 계약서가 발송된 근무입니다'), true,
          reason: 'contractId 가드는 새 id로 다시 부르면 그냥 통과한다');
      expect(cfFlat.contains('await srvIssuedContractExists(targetAppId, bizId)'), true);
    });

    test('동시 요청은 트랜잭션 안에서 다시 걸러진다', () {
      final i = cfFlat.indexOf('await db.runTransaction');
      expect(i > 0, true);
      final tx = cfFlat.substring(i, cfFlat.indexOf('tx.set(contractRef, data)'));
      expect(tx.contains('srvIssuedContractExists(dupAppId, dupBizId, tx)'), true,
          reason: 'pre-read만 두면 같은 순간에 들어온 둘이 모두 통과한다');
    });

    test('미발송 집계와 같은 판정식을 쓴다', () {
      // srvContractIssuedFor(홈·계약탭 집계)가 같은 함수로 위임돼야
      // "발송됨"으로 세어진 지원서에 한 장이 더 생기지 않는다.
      expect(
        _flat(_codeOf(raw))
            .contains('async function srvContractIssuedFor( appId: string, bizId: string ): '
                'Promise<boolean> { return srvIssuedContractExists(appId, bizId); }'),
        true,
        reason: '사본을 만들면 집계와 차단이 다른 말을 하게 된다',
      );
    });

    test('무효화된 계약서는 재발송을 막지 않는다', () {
      expect(_flat(_codeOf(raw)).contains('status === "voided" || status === "pending_employer"'),
          true, reason: 'voided를 발송됨으로 보면 정당한 재발송이 영구히 막힌다');
    });

    test('이미 발송된 건을 실패로 세지 않는다', () {
      final d = _flat(_codeOf(_src(
          'lib/screens/business_admin/dialogs/day_applicants_dialog.dart')));
      expect(d.contains("if (e.code == 'already-exists') {"), true);
      expect(d.contains('이미 계약서가 발송된 근무예요'), true,
          reason: '"다시 시도해주세요"라고 하면 없는 실패를 쫓게 된다');
    });
  });
}
