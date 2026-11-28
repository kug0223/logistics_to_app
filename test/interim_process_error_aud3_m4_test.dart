import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/services/payroll_payment_service.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/toast_helper.dart';

import 'support/visible_text.dart';

/// [AUD-3 M4] 승인된 중간정산 처리가 '계좌 스냅샷' 으로 거절될 때 — 다음 할 일('승인 취소' → 계좌 갱신 → 다시 승인)을 말한다.
///   거절 모양은 서버 원문 callableProcessInterimSettlement 의
///   `HttpsError("failed-precondition", \`급여 계좌 스냅샷 확인이 필요합니다: ${snap.id} (${piAcctBlock})\`)` 그대로다.
void main() {
  FirebaseFunctionsException fx(String code, String msg) => FirebaseFunctionsException(code: code, message: msg);
  FirebaseFunctionsException snap(String reason) =>
      fx('failed-precondition', '급여 계좌 스냅샷 확인이 필요합니다: att_123 ($reason)');

  test('P1 승인 뒤 계좌 변경(stale · 출처 모름) → 승인 취소·갱신·다시 승인 안내', () {
    expect(interimProcessErrorMessage(snap('stalePaymentSnapshot')), interimProcessStaleSnapshotMessage);
    expect(interimProcessErrorMessage(snap('snapshotProvenanceUnknown')), interimProcessStaleSnapshotMessage);
  });

  test('P2 계좌 스냅샷 자체 문제(검토 필요 · 레거시 · 없음) → 승인 취소·계좌 확인 안내', () {
    for (final r in ['reviewRequired', 'legacyNoSnapshot', 'noAccountSnapshot']) {
      expect(interimProcessErrorMessage(snap(r)), interimProcessAccountBlockMessage, reason: r);
    }
  });

  test('P3 그 밖의 서버 거절은 서버 문구 그대로 · 모르는 괄호 코드도 그대로 · 다른 오류 코드면 스냅샷 판정 0', () {
    const changed = '중간정산 승인 후 급여 금액이 변경되었습니다. 현재 요청을 취소하고 다시 승인해 주세요.';
    expect(interimProcessErrorMessage(fx('failed-precondition', changed)), changed);
    expect(interimProcessErrorMessage(snap('somethingNew')), '급여 계좌 스냅샷 확인이 필요합니다: att_123 (somethingNew)');
    expect(interimProcessErrorMessage(fx('internal', '내부 (stalePaymentSnapshot)')), '내부 (stalePaymentSnapshot)');
  });

  test('P8 [판정296] 새 서버 details.code 우선 — 문구와 달라도 구조화 code 로 고른다 · code 없으면 구서버 문구 fallback', () {
    FirebaseFunctionsException withCode(String msg, Object? details) =>
        FirebaseFunctionsException(code: 'failed-precondition', message: msg, details: details);
    // 현재 서버 모양: 문구 + {code, attendanceId}
    expect(interimProcessErrorMessage(withCode('급여 계좌 스냅샷 확인이 필요합니다: att_1 (stalePaymentSnapshot)',
        {'code': 'stalePaymentSnapshot', 'attendanceId': 'att_1'})), interimProcessStaleSnapshotMessage);
    // 문구 꼬리가 없어도(바뀌어도) details.code 로 판정
    expect(interimProcessErrorMessage(withCode('급여 계좌 스냅샷 확인이 필요합니다.', {'code': 'noAccountSnapshot'})),
        interimProcessAccountBlockMessage);
    // details.code 가 우선(문구 괄호와 다르면 details 를 따른다)
    expect(interimProcessErrorMessage(withCode('급여 계좌 스냅샷 확인이 필요합니다: a (stalePaymentSnapshot)', {'code': 'reviewRequired'})),
        interimProcessAccountBlockMessage);
    // 모르는 details.code 는 서버 문구 그대로(괄호 fallback 으로 넘어가지 않는다 — 서버가 말한 사유를 바꾸지 않는다)
    expect(interimProcessErrorMessage(withCode('새 거절 (stalePaymentSnapshot)', {'code': 'somethingNew'})), '새 거절 (stalePaymentSnapshot)');
    // details 가 Map 이 아니거나 code 가 문자열이 아니면 구서버 문구 fallback
    expect(interimProcessErrorMessage(withCode('급여 계좌 스냅샷 확인이 필요합니다: a (stalePaymentSnapshot)', 'x')),
        interimProcessStaleSnapshotMessage);
    expect(interimProcessErrorMessage(withCode('급여 계좌 스냅샷 확인이 필요합니다: a (stalePaymentSnapshot)', {'code': 3})),
        interimProcessStaleSnapshotMessage);
    final idx = File('functions/src/index.ts').readAsStringSync();
    final p = idx.substring(idx.indexOf('export const callableProcessInterimSettlement'),
        idx.indexOf('export const callableRejectInterimSettlement'));
    expect(p.contains('{code: piAcctBlock, attendanceId: snap.id}'), isTrue, reason: '서버가 구조화 code 를 싣는다(판정296)');
  });

  test('P4 모르는 실패 → 일반 문구(예외 문자열 0)', () {
    final m = interimProcessErrorMessage(Exception('[firebase_functions/unavailable] boom'));
    expect(m, '처리에 실패했습니다. 잠시 뒤 다시 시도해주세요.');
    expect(interimProcessErrorMessage(fx('unavailable', '')), m);
  });

  test('P5 안내 문구 — 개발 용어 0 · 화면 버튼 이름(승인 취소) · 금액 유지 사실', () {
    for (final s in [interimProcessStaleSnapshotMessage, interimProcessAccountBlockMessage]) {
      expect(RegExp(r'[A-Za-z_]{4,}').hasMatch(s), isFalse, reason: s);
      expect(s.contains("'승인 취소'"), isTrue);
      expect(s.contains('다시 승인'), isTrue);
    }
    expect(interimProcessStaleSnapshotMessage.contains('급여 금액은 그대로 유지됩니다'), isTrue);
    final dash = File('lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart').readAsStringSync();
    expect(dash.contains("child: const Text('승인 취소')"), isTrue, reason: '안내가 가리키는 버튼이 실제로 있다');
  });

  test('P6 호출부 · 서버 거절 모양(계약) 핀', () {
    final dash = File('lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart').readAsStringSync();
    final body = dash.substring(dash.indexOf('Future<void> _processSettlement('), dash.indexOf('Future<void> _rejectSettlement('));
    expect(body.contains('ToastHelper.showError(interimProcessErrorMessage(e));'), isTrue);
    expect(body.contains(r'$e'), isFalse);
    final idx = File('functions/src/index.ts').readAsStringSync();
    final p = idx.substring(idx.indexOf('export const callableProcessInterimSettlement'),
        idx.indexOf('export const callableRejectInterimSettlement'));
    expect(p.contains(r'`급여 계좌 스냅샷 확인이 필요합니다: ${snap.id} (${piAcctBlock})`'), isTrue,
        reason: '서버 거절 모양이 바뀌면 이 안내 판정도 함께 바꿔야 한다');
    for (final c in [...interimProcessStaleSnapshotCodes, ...interimProcessAccountBlockCodes]) {
      expect(idx.contains('= "$c";'), isTrue, reason: '서버 사유 코드 $c');
    }
  });

  for (final (w, s) in [(320.0, 1.3), (320.0, 2.0), (392.0, 2.0)]) {
    testWidgets('P7 $w·$s 안내 토스트가 예외 없이 보인다', (t) async {
      t.view.physicalSize = Size(w, 800);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)),
          child: child!,
        ),
        home: const Scaffold(body: SizedBox()),
      ));
      ToastHelper.showError(interimProcessErrorMessage(snap('stalePaymentSnapshot')));
      await t.pump();
      expect(t.takeException(), isNull);
      expect(findVisibleTextContaining('급여계좌를 변경해'), findsOneWidget);
      expect(findVisibleTextContaining('급여 금액은 그대로 유지됩니다'), findsOneWidget);
      await t.pump(const Duration(seconds: 5));
    });
  }
}
