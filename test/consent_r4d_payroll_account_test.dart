// [CONSENT-R4c · r4b 판 04c88dca 대체 · C-R4-4 · PP-R4B-ACCOUNT-READ] 관리자 근로자 상세 '급여 정보' — 목적별 계좌 reader 소비 계약.
//   작성만 했다 — 이번 배정 실행 0. 통과 결과가 아니다.
//
//   LOCAL 위치(제안): A_copy/test/consent_r4b_payroll_account_test.dart
//   입력: 후보 lib/services/worker_payroll_account_service.dart · 후보 lib/widgets/dialogs/worker_detail_dialog.dart
//   네트워크·Firebase 0 — 응답 해석은 순수 함수로, 화면 배선은 원문 결속으로 본다.
//   (WorkerDetailDialog 전체를 그리는 위젯 시험은 이 파일에 없다 — 부가 조회 seam 이 없어 실제 화면 실측은
//    LOCAL 실행 판정 뒤 별도 셀 후보다. 결속 검사를 화면 실측 성공으로 올려 쓰지 않는다.)
//   성공 = 'All tests passed!' · rc 0.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/services/worker_payroll_account_service.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('PA-R 응답 해석 — 상태를 같은 \'-\' 로 접지 않는다', () {
    test('PA-R1 OK → 세 필드(계좌번호는 기존 복호화 경로 · 키 없는 시험 환경은 원문 그대로)', () {
      final r = WorkerPayrollAccountResult.fromResponse({
        'status': 'OK',
        'account': {'bankName': '국민은행', 'accountNumber': '000000000000', 'accountHolder': '홍길동'},
        'window': {'state': 'S3_SETTLED_T30', 'basis': 'LAST_PAYMENT', 'closesAtMs': 1},
      });
      expect(r.kind, WorkerPayrollAccountKind.ok);
      expect(r.bankName, '국민은행');
      expect(r.accountNumber, '000000000000');
      expect(r.accountHolder, '홍길동');
      expect(r.statusText, isNull);
    });
    test('PA-R2 OK 인데 필드 결손·형식 오류 → 오류(BAD_RESPONSE) — 빈 칸으로 그리지 않는다', () {
      for (final acc in [null, {'bankName': '국민은행'}, {'bankName': 1, 'accountNumber': 'x', 'accountHolder': 'y'}]) {
        final r = WorkerPayrollAccountResult.fromResponse({'status': 'OK', 'account': acc});
        expect(r.kind, WorkerPayrollAccountKind.error, reason: '$acc');
        expect(r.errorCode, 'BAD_RESPONSE');
      }
      expect(WorkerPayrollAccountResult.fromResponse('x').kind, WorkerPayrollAccountKind.error);
      expect(WorkerPayrollAccountResult.fromResponse({'status': 'WHAT'}).kind, WorkerPayrollAccountKind.error);
    });
    test('PA-R3 미등록 · 불허 사유 · 닫힘 구분이 서로 다른 문장', () {
      final texts = <String?>{
        WorkerPayrollAccountResult.fromResponse({'status': 'NOT_REGISTERED'}).statusText,
        WorkerPayrollAccountResult.fromResponse({'status': 'DENIED', 'reason': 'NOT_CONFIRMED'}).statusText,
        WorkerPayrollAccountResult.fromResponse({'status': 'DENIED', 'reason': 'CONSENT_MISSING'}).statusText,
        WorkerPayrollAccountResult.fromResponse(
            {'status': 'DENIED', 'reason': 'BANK_WINDOW_CLOSED', 'closedKind': 'PERIOD_ENDED'}).statusText,
        WorkerPayrollAccountResult.fromResponse(
            {'status': 'DENIED', 'reason': 'BANK_WINDOW_CLOSED', 'closedKind': 'NEEDS_CONFIRMATION'}).statusText,
        WorkerPayrollAccountResult.fromResponse(
            {'status': 'DENIED', 'reason': 'BANK_WINDOW_CLOSED', 'closedKind': 'NOT_STARTED'}).statusText,
        WorkerPayrollAccountResult.fromError('permission-denied').statusText,
        WorkerPayrollAccountResult.fromError('not-found').statusText,
        WorkerPayrollAccountResult.fromError('unavailable').statusText,
        WorkerPayrollAccountResult.noRelation.statusText,
      };
      expect(texts.length, 10, reason: '같은 문장으로 접힌 상태가 있다: $texts');
      expect(texts.contains(null), isFalse);
      expect(texts.any((s) => s == '-' || s!.trim().isEmpty), isFalse);
      // 판본 미지원은 동의 없음과 같은 사용자 문장(관리자가 할 일은 같다) — 서버 사유는 구분된다.
      expect(WorkerPayrollAccountResult.fromResponse(
              {'status': 'DENIED', 'reason': 'CONSENT_VERSION_NOT_READABLE'}).reason,
          'CONSENT_VERSION_NOT_READABLE');
    });
    test('PA-R4 기간 종료 문장은 지급 경로가 따로 있음을 말한다(화면 열람 ≠ 지급 권한)', () {
      expect(bankWindowClosedText('PERIOD_ENDED').contains('급여 화면에서 처리'), isTrue);
      expect(bankWindowClosedText(null), bankWindowClosedText('PERIOD_ENDED'));
    });
    test('PA-R5 서비스는 예외를 던지지 않고 실패를 상태로 돌려준다(원문 결속)', () {
      final s = _src('lib/services/worker_payroll_account_service.dart');
      expect(s.contains(".httpsCallable('callableGetWorkerPayrollAccount')"), isTrue);
      expect(s.contains("on FirebaseFunctionsException catch (e) {\n      return WorkerPayrollAccountResult.fromError(e.code);"),
          isTrue);
      expect(s.contains("'businessId': businessId, 'applicationId': applicationId"), isTrue);
    });
  });

  group('PA-W 근로자 상세 배선(원문 결속)', () {
    final s = _src('lib/widgets/dialogs/worker_detail_dialog.dart');
    final i = s.indexOf('Widget _buildPaymentInfo(BuildContext context) {');
    final pay = s.substring(i, s.indexOf('/// 근로계약서 섹션 (확정자만)', i));
    test('PA-W1 급여 정보는 목적 미지정 batch 의 user 계좌 필드를 그리지 않는다', () {
      for (final w in ['widget.user.bankName', 'widget.user.accountNumber', 'widget.user.accountHolder',
        '?? widget.user.name']) {
        expect(pay.contains(w), isFalse, reason: w);
      }
      expect(pay.contains('..._buildPayrollAccountRows(context),'), isTrue);
    });
    test('PA-W2 계좌 줄 = 목적별 reader 결과 · 상태마다 다른 한 줄 · 오류는 다시 불러오기(48)', () {
      final j = s.indexOf('List<Widget> _buildPayrollAccountRows(BuildContext context) {');
      final rows = s.substring(j, s.indexOf('/// 근로계약서 섹션 (확정자만)', j));
      expect(rows.contains("_buildInfoRow(context, '예금주', r.accountHolder ?? '-')"), isTrue);
      expect(rows.contains('r.statusText'), isTrue);
      expect(rows.contains("ValueKey('payrollAccountRetry')"), isTrue);
      expect(rows.contains('minimumSize: const Size(48, 48)'), isTrue);
    });
    test('PA-W3 확정 화면에서만 읽고, 급여 권한이 없으면 부르지 않는다 · 관계 없으면 서버 호출 0', () {
      final load = s.substring(s.indexOf('Future<void> _loadPayrollAccount() async {'),
          s.indexOf('/// [V3 BANKBOOK-SECURE-ACCESS] 통장사본 열람'));
      final perm = load.indexOf('p.canManageWage');
      final noRel = load.indexOf('WorkerPayrollAccountResult.noRelation');
      final fetch = load.indexOf('WorkerPayrollAccountService()');
      expect(perm > 0 && noRel > perm && fetch > noRel, isTrue);
      expect(load.contains('if (!mounted) return;'), isTrue, reason: 'await 뒤 mounted 확인');
      // [r4c · PP-R4B-ACCOUNT-READ] 상세를 열 때 자동 조회 0 — '급여계좌 보기'(48)에서만 요청.
      final add = s.substring(s.indexOf('Future<void> _loadAdditionalData() async {'),
          s.indexOf('Future<void> _loadAdditionalData() async {') + 2000);
      expect(add.contains('_loadPayrollAccount()'), isFalse, reason: '상세 열기 = 계좌 요청이 아니다');
      expect(load.contains('if (_payrollAccountLoading) return;'), isTrue, reason: '이중 요청 0');
      final j = s.indexOf('List<Widget> _buildPayrollAccountRows(BuildContext context) {');
      final rows = s.substring(j, s.indexOf('/// 근로계약서 섹션 (확정자만)', j));
      final btn = rows.indexOf("ValueKey('payrollAccountRequest')");
      expect(btn, greaterThan(0));
      expect(rows.indexOf('onPressed: _loadPayrollAccount,', btn), greaterThan(btn));
      expect(rows.contains("'급여계좌 보기'"), isTrue);
      expect(rows.substring(btn, btn + 400).contains('minimumSize: const Size(48, 48)'), isTrue);
    });
    test('PA-W4 통장사본 오류 안내 — 열람 기간 닫힘은 권한 없음과 다른 문장', () {
      final v = s.substring(s.indexOf('Future<void> _viewBankbook() async {'),
          s.indexOf('void _startAccessRefreshTimer() {'));
      expect(v.contains("details['code'] == 'BANK_WINDOW_CLOSED'"), isTrue);
      expect(v.contains('bankWindowClosedText(closedKind)'), isTrue);
    });
  });
}
