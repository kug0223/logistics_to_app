import 'package:cloud_functions/cloud_functions.dart';

import '../utils/encryption_helper.dart';

/// [CONSENT-R4b · C-R4-4] 관리자 근로자 상세 '급여 정보'의 목적별 현재 계좌 reader.
///
/// 목적 미지정 batch(callableGetUsersBatch)에서 계좌 3필드가 빠진 뒤(H11) 같은 화면을
/// 서버 `callableGetWorkerPayrollAccount` 로 다시 잇는다. 서버가 권한·관계·확정·동의·판본·
/// 열람 기간을 판정하고, 이 파일은 그 결과를 **상태별로** 돌려준다 — 불허·기간 종료·
/// 확인 필요·미등록·오류를 같은 '-' 로 숨기지 않는다.
///
/// 과거 지급 기록의 계좌(근태 스냅샷)·지급용 통장사본·이체 엑셀은 이 reader 의 몫이 아니다.
/// 후보(DRAFT) — A 에 반영되지 않았다.
enum WorkerPayrollAccountKind { ok, notRegistered, denied, error }

class WorkerPayrollAccountResult {
  const WorkerPayrollAccountResult._({
    required this.kind,
    this.bankName,
    this.accountNumber,
    this.accountHolder,
    this.reason,
    this.closedKind,
    this.errorCode,
  });

  final WorkerPayrollAccountKind kind;
  final String? bankName;

  /// 복호화한 계좌번호(UserModel 과 같은 EncryptionHelper 경로).
  final String? accountNumber;
  final String? accountHolder;

  /// DENIED 사유(NOT_CONFIRMED · CONSENT_MISSING · CONSENT_VERSION_NOT_READABLE · BANK_WINDOW_CLOSED).
  final String? reason;

  /// BANK_WINDOW_CLOSED 의 구분(PERIOD_ENDED · NEEDS_CONFIRMATION · NOT_STARTED).
  final String? closedKind;

  /// 호출 실패 코드(permission-denied · not-found · …).
  final String? errorCode;

  static const WorkerPayrollAccountResult noRelation = WorkerPayrollAccountResult._(
      kind: WorkerPayrollAccountKind.denied, reason: 'NO_RELATION');

  /// 서버 응답(Map) → 결과. 모양이 다르면 오류로 본다(조용히 '-'로 접지 않는다).
  static WorkerPayrollAccountResult fromResponse(Object? data) {
    if (data is! Map) {
      return const WorkerPayrollAccountResult._(
          kind: WorkerPayrollAccountKind.error, errorCode: 'BAD_RESPONSE');
    }
    final status = data['status'];
    if (status == 'OK') {
      final acc = data['account'];
      if (acc is! Map) {
        return const WorkerPayrollAccountResult._(
            kind: WorkerPayrollAccountKind.error, errorCode: 'BAD_RESPONSE');
      }
      final bank = acc['bankName'];
      final number = acc['accountNumber'];
      final holder = acc['accountHolder'];
      if (bank is! String || number is! String || holder is! String) {
        return const WorkerPayrollAccountResult._(
            kind: WorkerPayrollAccountKind.error, errorCode: 'BAD_RESPONSE');
      }
      return WorkerPayrollAccountResult._(
        kind: WorkerPayrollAccountKind.ok,
        bankName: bank,
        accountNumber: EncryptionHelper.decrypt(number),
        accountHolder: holder,
      );
    }
    if (status == 'NOT_REGISTERED') {
      return const WorkerPayrollAccountResult._(kind: WorkerPayrollAccountKind.notRegistered);
    }
    if (status == 'DENIED') {
      final r = data['reason'];
      final ck = data['closedKind'];
      return WorkerPayrollAccountResult._(
        kind: WorkerPayrollAccountKind.denied,
        reason: r is String ? r : 'UNKNOWN',
        closedKind: ck is String ? ck : null,
      );
    }
    return const WorkerPayrollAccountResult._(
        kind: WorkerPayrollAccountKind.error, errorCode: 'BAD_RESPONSE');
  }

  static WorkerPayrollAccountResult fromError(String code) =>
      WorkerPayrollAccountResult._(kind: WorkerPayrollAccountKind.error, errorCode: code);

  /// 계좌 대신 보일 한 줄. ok 이면 null.
  String? get statusText => payrollAccountStatusText(
      kind: kind, reason: reason, closedKind: closedKind, errorCode: errorCode);
}

/// 상태 → 화면 문장. 확정자 통장사본 오류 안내(BANK_WINDOW_CLOSED)도 같은 문장을 쓴다.
String? payrollAccountStatusText({
  required WorkerPayrollAccountKind kind,
  String? reason,
  String? closedKind,
  String? errorCode,
}) {
  switch (kind) {
    case WorkerPayrollAccountKind.ok:
      return null;
    case WorkerPayrollAccountKind.notRegistered:
      return '등록된 급여계좌가 없어요.';
    case WorkerPayrollAccountKind.error:
      if (errorCode == 'permission-denied') return '급여 정보를 볼 권한이 없어요.';
      if (errorCode == 'not-found') return '근무 정보를 찾을 수 없어요.';
      return '급여 정보를 불러오지 못했어요.';
    case WorkerPayrollAccountKind.denied:
      switch (reason) {
        case 'NO_RELATION':
          return '확정된 근무 정보가 없어 계좌를 볼 수 없어요.';
        case 'NOT_CONFIRMED':
          return '확정된 근무가 아니어서 계좌를 볼 수 없어요.';
        case 'CONSENT_MISSING':
        case 'CONSENT_VERSION_NOT_READABLE':
          return '근로자의 서류 열람 동의가 없어 계좌를 볼 수 없어요.';
        case 'BANK_WINDOW_CLOSED':
          return bankWindowClosedText(closedKind);
        default:
          return '지금은 계좌를 볼 수 없어요.';
      }
  }
}

/// 열람 기간 판정으로 닫힌 경우의 문장(계좌·통장사본 공통).
String bankWindowClosedText(String? closedKind) {
  switch (closedKind) {
    case 'NOT_STARTED':
      return '근무 시작 전이라 아직 볼 수 없어요.';
    case 'NEEDS_CONFIRMATION':
      return '근무·지급 기록 확인이 필요해 지금은 볼 수 없어요.';
    default:
      return '열람 기간이 끝나 볼 수 없어요. 지급할 급여는 급여 화면에서 처리돼요.';
  }
}

class WorkerPayrollAccountService {
  WorkerPayrollAccountService({FirebaseFunctions? functions})
      : _functions = functions ?? FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  final FirebaseFunctions _functions;

  /// 서버 판정 결과. 예외를 던지지 않는다 — 실패도 상태로 돌려준다.
  Future<WorkerPayrollAccountResult> fetch({
    required String businessId,
    required String applicationId,
  }) async {
    try {
      final res = await _functions
          .httpsCallable('callableGetWorkerPayrollAccount')
          .call({'businessId': businessId, 'applicationId': applicationId});
      return WorkerPayrollAccountResult.fromResponse(res.data);
    } on FirebaseFunctionsException catch (e) {
      return WorkerPayrollAccountResult.fromError(e.code);
    } catch (_) {
      return WorkerPayrollAccountResult.fromError('unknown');
    }
  }
}
