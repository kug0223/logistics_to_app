import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/utils/request_relation_error.dart';

/// [서버296 보안 묶음 · impl_42] 앱 연결
///   V  무효 계약 지원서 재처리 = callableRetryVoidFailedApplications 1회 · 클라 voidFailedAppIds 쓰기 0 · kept/오류 안내
///   R  변경 요청 승인·거절의 보류 거절(SCR_RELATION_MISMATCH · SCR_TYPE_INVALID · PCR_RELATION_MISMATCH) 안내
///   응답 모양은 서버 원문(functions/src/index.ts)의 return/HttpsError 그대로다.
void main() {
  FirebaseFunctionsException fx(String code, String msg, [Object? details]) =>
      FirebaseFunctionsException(code: code, message: msg, details: details);

  group('V 재처리', () {
    test('V1 성공 — kept 0 이면 완료 · kept 있으면 확인 필요 n건(사유별)', () {
      final ok = RetryVoidFailedResult.fromResponse(
          {'success': true, 'canceled': ['a1', 'a2'], 'cleared': ['a3'], 'kept': []});
      expect((ok.canceled.length, ok.cleared.length, ok.hasKept), (2, 1, false));
      expect(ok.message(), '지원서 취소 재처리를 마쳤어요');
      final kept = RetryVoidFailedResult.fromResponse({'success': true, 'canceled': ['a1'], 'cleared': [], 'kept': [
        {'applicationId': 'a4', 'reason': 'ACTUAL_WORK'},
        {'applicationId': 'a5', 'reason': 'FAILED'},
        {'applicationId': 'a6', 'reason': 'ACTUAL_WORK'},
        {'applicationId': 'a7', 'reason': 'NEW_REASON'},
        {'reason': 'NOT_FOUND'}, // id 없는 항목은 버린다
      ]});
      expect(kept.hasKept, isTrue);
      expect(kept.kept.length, 4);
      expect(kept.message(), '확인 필요 4건이 남았어요(실제 근무 기록 있음 2 · 처리 실패 1 · 기타 1)');
      expect(RegExp(r'[A-Z_]{4,}').hasMatch(kept.message()), isFalse);
    });

    test('V2 모양 오류 응답은 성공으로 말하지 않는다(결과 모름 → 경고)', () {
      for (final bad in <Object?>[null, 'x', {'success': true}, {'canceled': [], 'cleared': [], 'kept': 'a'}]) {
        final r = RetryVoidFailedResult.fromResponse(bad);
        expect(r.known, isFalse, reason: '$bad');
        expect(r.needsAttention, isTrue, reason: '모르는 결과를 성공으로 말하지 않는다');
        expect(r.message().contains('확인하지 못했어요'), isTrue);
      }
      final ok = RetryVoidFailedResult.fromResponse({'canceled': [], 'cleared': [], 'kept': []});
      expect((ok.known, ok.needsAttention), (true, false));
    });

    test('V3 오류 안내 — 미무효 · 권한 · 없음 · 50 초과(서버 문구) · 모름', () {
      expect(retryVoidFailedErrorMessage(fx('failed-precondition', '무효화된 계약서만 재처리할 수 있습니다.', {'code': 'CONTRACT_NOT_VOIDED'})),
          '무효 처리된 계약서만 재처리할 수 있어요.');
      expect(retryVoidFailedErrorMessage(fx('permission-denied', '계약서 관리 권한이 없습니다.')), '계약서 관리 권한이 없어 재처리할 수 없어요.');
      expect(retryVoidFailedErrorMessage(fx('not-found', '계약서를 찾을 수 없습니다.')), contains('찾을 수 없어요'));
      expect(retryVoidFailedErrorMessage(fx('failed-precondition', '재처리 대상이 너무 많습니다. 관리자에게 문의해 주세요.')),
          '재처리 대상이 너무 많습니다. 관리자에게 문의해 주세요.');
      expect(retryVoidFailedErrorMessage(Exception('[x] boom')), '재처리에 실패했어요. 잠시 뒤 다시 시도해 주세요.');
    });

    test('V4 소스 — callable 1회 · 클라 voidFailedAppIds 쓰기 0 · 건별 취소 0 · 화면은 kept/오류 안내', () {
      final svc = File('lib/services/contract_service.dart').readAsStringSync();
      final b = svc.substring(svc.indexOf('Future<RetryVoidFailedResult> retryVoidFailedApps('),
          svc.indexOf('// ── 내부: 번들 탐색 ──'));
      expect(b.contains("'callableRetryVoidFailedApplications'"), isTrue);
      expect(b.contains("{'contractId': contract.id}"), isTrue);
      expect(b.contains('voidFailedAppIds'), isFalse, reason: '클라 직접 쓰기 0(rules R2374)');
      expect(b.contains('cancelConfirmedApplication'), isFalse);
      expect(RegExp(r'\.update\(').hasMatch(b), isFalse);
      final scr = File('lib/screens/business_admin/admin_contract_management_screen.dart').readAsStringSync();
      final h = scr.substring(scr.indexOf('Future<void> _retryVoidFailedApps('), scr.indexOf('Future<void> _sendContractFromApp('));
      expect(h.contains('if (result.needsAttention) {'), isTrue);
      expect(h.contains('ToastHelper.showWarning(result.message());'), isTrue);
      expect(h.contains('ToastHelper.showError(retryVoidFailedErrorMessage(e));'), isTrue);
      expect(h.contains(r'$e'), isFalse);
      final idx = File('functions/src/index.ts').readAsStringSync();
      expect(idx.contains('export const callableRetryVoidFailedApplications = onCall('), isTrue);
      expect(idx.contains('{code: "CONTRACT_NOT_VOIDED"}'), isTrue);
      expect(idx.contains('return {success: true, canceled, cleared, kept};'), isTrue);
    });
  });

  group('R 변경 요청 보류 거절', () {
    test('R1 code 로만 판정 — SCR 불일치·종류 · PCR 불일치 · 그 밖은 null', () {
      expect(requestHeldMessageOf(fx('failed-precondition', 'x', {'code': 'SCR_RELATION_MISMATCH', 'reason': 'BUSINESS'})),
          requestRelationHeldMessage);
      expect(requestHeldMessageOf(fx('failed-precondition', 'x', {'code': 'PCR_RELATION_MISMATCH', 'reason': 'WORKER'})),
          requestRelationHeldMessage);
      expect(requestHeldMessageOf(fx('failed-precondition', 'x', {'code': 'SCR_TYPE_INVALID'})), requestTypeInvalidMessage);
      expect(requestHeldMessageOf(fx('failed-precondition', '요청 정보가 지원서와 맞지 않습니다')), isNull, reason: '문구로 판정하지 않는다');
      expect(requestHeldMessageOf(Exception('x')), isNull);
      for (final m in [requestRelationHeldMessage, requestTypeInvalidMessage]) {
        expect(m.contains('대기 상태로 남아 있어요'), isTrue);
        expect(RegExp(r'[A-Z_]{4,}').hasMatch(m), isFalse);
      }
      expect(requestFailureMessageOf(fx('internal', '서버 문구'), fallback: 'f'), '서버 문구');
      expect(requestFailureMessageOf(Exception('e'), fallback: 'f'), 'f');
    });

    test('R2 소스 — SCR 서비스가 보류 거절을 false 로 접지 않고 다시 던진다 · 화면 4곳 + PCR 2곳이 안내한다', () {
      final svc = File('lib/services/firestore/attendance_firestore.dart').readAsStringSync();
      expect('if (requestHeldMessageOf(e) != null) rethrow;'.allMatches(svc).length, 2);
      final srm = File('lib/screens/business_admin/dialogs/schedule_request_management_dialog.dart').readAsStringSync();
      expect('ToastHelper.showWarning(held);'.allMatches(srm).length, 2);
      final fwm = File('lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart').readAsStringSync();
      expect('held != null ? ToastHelper.showWarning(held)'.allMatches(fwm).length, 2);
      final dash = File('lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart').readAsStringSync();
      final seg = dash.substring(dash.indexOf('Future<void> _approveChangeRequest('), dash.indexOf('void _toggleBatchMode() {'));
      expect('final held = requestHeldMessageOf(e);'.allMatches(seg).length, 2);
      expect(seg.contains(r'$e'), isFalse);
      final idx = File('functions/src/index.ts').readAsStringSync();
      for (final c in ['SCR_RELATION_MISMATCH', 'SCR_TYPE_INVALID', 'PCR_RELATION_MISMATCH']) {
        expect(idx.contains('code: "$c"'), isTrue, reason: '서버 code $c');
      }
    });
  });
}
