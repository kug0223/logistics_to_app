// [R8-P3B.1] 취소를 누른 사람이 알림 왕복을 한 번 더 기다렸다.
//
//   확정 취소와 계약 무효화는 CF 가 도메인을 커밋한 뒤, **클라이언트가**
//   알림 callable 을 다시 불렀다. 관리자 취소면 1회, 근무자 자기 취소면
//   사업장·근무자 문서를 읽고 관리자 수만큼 불렀다. 왕복 하나가 600ms대다.
//
//   그리고 응답 직후 앱이 죽으면 알림은 영구히 사라졌다 — 근무자가 반드시
//   알아야 할 사실의 통지가 호출자 앱의 생존에 달려 있었다.
//
//   수신자·문구·목적지는 그대로 두고 쓰는 주체만 서버로 옮겼다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _fn() => File('functions/src/index.ts').readAsStringSync();
String _appSvc() =>
    File('lib/services/firestore/application_firestore.dart').readAsStringSync();
String _contractSvc() =>
    File('lib/services/contract_service.dart').readAsStringSync();

/// 주석으로 시작하는 줄(`//`·`///`)을 지운다 — 표지는 코드에서만 찾는다.
String _codeOf(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 그룹 수집 시점에도 불리므로 expect 대신 예외로 실패시킨다.
String _sliceOf(String raw, String from, String to) {
  final i = raw.indexOf(from);
  if (i < 0) throw StateError('시작 표지를 찾지 못함: $from');
  final j = raw.indexOf(to, i + from.length);
  if (j < 0) throw StateError('끝 표지를 찾지 못함: $to');
  return raw.substring(i, j);
}

String _cfBody(String fn, String name) {
  final i = fn.indexOf('export const $name =');
  if (i < 0) throw StateError('CF 를 찾지 못함: $name');
  final j = fn.indexOf('\nexport const ', i + 20);
  return fn.substring(i, j < 0 ? fn.length : j);
}

void main() {
  final fn = _fn();
  final cancelHelper = _codeOf(_sliceOf(fn,
      'async function srvNotifyConfirmationCanceled(a: {',
      'async function srvNotifyContractVoided(a: {'));
  final ch = _flat(cancelHelper);
  final voidHelper = _codeOf(_sliceOf(fn,
      'async function srvNotifyContractVoided(a: {',
      'export const callableCancelConfirmedApplication = onCall('));
  final vh = _flat(voidHelper);
  final cancelCf = _codeOf(_cfBody(fn, 'callableCancelConfirmedApplication'));
  final voidCf = _codeOf(_cfBody(fn, 'callableVoidContractWithApplications'));
  final appSvc = _codeOf(_appSvc());
  final conSvc = _codeOf(_contractSvc());

  group('CN2-1 — 확정취소 알림을 서버가 쓴다', () {
    test('CN2-10 취소 CF 가 커밋 뒤에 보낸다', () {
      expect(_flat(cancelCf), contains('await srvNotifyConfirmationCanceled({ applicationId,'));
      final txAt = cancelCf.indexOf('runTransaction');
      final notifyAt = cancelCf.indexOf('await srvNotifyConfirmationCanceled(');
      expect(txAt, greaterThan(-1));
      expect(txAt, lessThan(notifyAt), reason: '도메인 커밋 이후에만');
    });

    test('CN2-11 관리자 취소 → 근무자 본인', () {
      expect(ch, contains('if (a.isAdminCancel) {'));
      expect(ch, contains('db.collection("users").doc(a.workerUid)'));
      expect(ch, contains('category: "personal"'));
      expect(ch, contains('action: "applicationDetail"'));
    });

    test('CN2-12 근무자 취소 → 사업장 관리자(ownerId 폴백)', () {
      expect(ch, contains('let adminIds: string[] = (bizData?.adminIds as string[] | undefined) ?? [];'));
      expect(ch, contains('const owner = bizData?.ownerId as string | undefined;'));
      expect(ch, contains('category: "admin"'));
      expect(ch, contains('action: "applicantDetail"'));
    });

    test('CN2-13 서브어드민 팬아웃을 새로 만들지 않았다', () {
      // confirmationCanceled 는 원래 팬아웃 제외 대상이다
      expect(cancelHelper.contains('getSubAdminsWithPermission'), false);
    });
  });

  group('CN2-2 — 계약무효 알림을 서버가 쓴다', () {
    test('CN2-20 무효화 CF 가 커밋 뒤에 보낸다', () {
      expect(_flat(voidCf), contains('await srvNotifyContractVoided({ contractId,'));
      final already = voidCf.indexOf('if (result.alreadyVoided) return {alreadyVoided: true};');
      final notifyAt = voidCf.indexOf('await srvNotifyContractVoided(');
      expect(already, greaterThan(-1));
      expect(already, lessThan(notifyAt), reason: '멱등 반환 뒤에는 보내지 않는다');
    });

    test('CN2-21 수신자는 근무자 본인이다', () {
      expect(vh, contains('db.collection("users").doc(a.workerId)'));
      expect(vh, contains('category: "personal"'));
      expect(vh, contains('screen: "userContracts"'));
    });
  });

  group('CN2-3 — 클라이언트 추가 왕복이 사라졌다', () {
    test('CN2-30 확정취소 서비스에 알림 호출이 없다', () {
      final m = _sliceOf(appSvc, 'Future<bool> cancelConfirmedApplication(',
          'Future<void> _cleanupApplicationRelatedData(');
      expect(m.contains('createNotification'), false);
      expect(m.contains('createConfirmationCanceled'), false);
      expect(m.contains('createConfirmationCanceledByWorker'), false);
    });

    test('CN2-31 계약무효 서비스에 알림 호출이 없다', () {
      final m = _sliceOf(conSvc, 'Future<void> voidContract(String contractId) async {',
          'Future<void> retryVoidFailedApps(');
      expect(m.contains('createNotification'), false);
      expect(m.contains('createContractVoided'), false);
    });

    test('CN2-32 contract_service 는 알림 모델을 더 쓰지 않는다', () {
      expect(conSvc.contains("import '../models/core/notification_model.dart';"), false);
      expect(conSvc.contains('NotificationModel.'), false);
    });
  });

  group('CN2-4 — 재시도가 알림을 두 번 쌓지 않는다', () {
    test('CN2-40 문서 id 가 사건·수신자로 고정돼 있다', () {
      expect(ch, contains(r'.doc(`confirmation_canceled_${a.applicationId}_${a.workerUid}`)'));
      expect(ch, contains(r'.doc(`confirmation_canceled_by_worker_${a.applicationId}_${adminUid}`)'));
      expect(vh, contains(r'.doc(`contract_voided_${a.contractId}_${a.workerId}`)'));
    });

    test('CN2-41 add 가 아니라 create 다', () {
      expect(cancelHelper.contains('.add('), false);
      expect(voidHelper.contains('.add('), false);
      expect(ch, contains('.create({'));
      expect(vh, contains('.create({'));
    });

    test('CN2-42 이미 있음(6)은 오류가 아니다', () {
      expect('code === 6'.allMatches(cancelHelper).length, 2);
      expect(vh, contains('if ((e as {code?: number})?.code === 6) return;'));
    });
  });

  group('CN2-5 — 알림 실패가 도메인 실패가 아니다', () {
    test('CN2-50 취소 CF 가 알림 예외를 삼킨다', () {
      expect(_flat(cancelCf), contains('"⚠️ [cancelConfirmedApplication] 확정취소 알림 실패 (취소는 완료됨):", e);'));
      final notifyAt = cancelCf.indexOf('await srvNotifyConfirmationCanceled(');
      final returnAt = cancelCf.indexOf('return {\n      success: true,\n      workerUid,');
      expect(notifyAt, lessThan(returnAt));
    });

    test('CN2-51 무효화 CF 도 같다', () {
      expect(_flat(voidCf), contains('"⚠️ [voidContractWithApplications] 무효화 알림 실패 (무효화는 완료됨):", e);'));
    });

    test('CN2-52 수신자별 실패가 서로를 막지 않는다', () {
      expect(ch, contains('await Promise.allSettled(adminIds.map((adminUid) =>'));
    });

    test('CN2-53 실패를 숨기지 않는다 — 수신자·사건 id 를 남긴다', () {
      expect(ch, contains(r'`⚠️ [confirmationCanceled] 알림 저장 실패 uid=${a.workerUid} ` + `application=${a.applicationId}:`, e)'));
      expect(vh, contains(r'`⚠️ [contractVoided] 알림 저장 실패 uid=${a.workerId} ` + `contract=${a.contractId}:`, e)'));
    });
  });

  group('CN2-6 — 문구·목적지 parity', () {
    test('CN2-60 확정취소 문구가 그대로다', () {
      expect(ch, contains('title: "확정 취소"'));
      expect(ch, contains(r'`${a.businessName}의 ${a.workType} 확정이 취소되었습니다.`'));
      expect(ch, contains(r'`${workerName}님이 ${a.workType} 확정 근무를 취소했습니다.${dateLine}`'));
      expect(ch, contains(r'const reasonLine = a.cancelReason ? `\n사유: ${a.cancelReason}` : "";'));
    });

    test('CN2-61 근무일 표기가 KST M/D 다', () {
      expect(_flat(_codeOf(_sliceOf(fn, 'function srvKstMonthDay(ms: number): string {',
          'async function srvNotifyConfirmationCanceled('))),
          contains('const d = new Date(ms + 9 * 60 * 60 * 1000);'));
      expect(ch, contains(r'const dateLine = when ? `\n근무일: ${when}` : "";'));
    });

    test('CN2-62 무효화 문구가 그대로다', () {
      expect(vh, contains('title: "계약서 무효 처리"'));
      expect(vh, contains(r'`${a.businessName}의 근로계약서가 무효 처리되었습니다. `'));
    });

    test('CN2-63 FCM 은 여전히 트리거가 보낸다', () {
      for (final h in [cancelHelper, voidHelper]) {
        expect(h.contains('sendEachForMulticast'), false);
        expect(h.contains('messaging()'), false);
      }
    });
  });

  group('CN2-7 — 인접 계약 불변', () {
    test('CN2-70 P3B 계약 서명 알림이 그대로다', () {
      expect(fn.contains('async function srvNotifyContractSigned(args: {'), true);
    });

    test('CN2-71 취소 CF 응답 필드가 그대로다 — 하위 호환', () {
      for (final f in ['workerUid', 'toId', 'slotId', 'selectedWorkType',
        'businessId', 'businessName', 'workDateMs', 'workDetailId',
        'isAdminCancel', 'shouldApplyNoShowPenalty']) {
        expect(_flat(cancelCf), contains(f), reason: f);
      }
    });
  });
}
