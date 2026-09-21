// [R8-P3B] 서명한 사람이 남의 알림 왕복을 기다렸다.
//
//   근로자가 계약서에 서명하면 클라이언트는 CF 응답을 받은 뒤 사업장 문서를
//   한 번 더 읽고, 관리자 수만큼 createNotification 을 **다시** 호출했다.
//   DEV 실측으로 그 왕복 하나가 609ms — 서명 화면이 그만큼 더 기다렸다.
//   게다가 응답을 받은 직후 앱이 죽으면 알림은 영구히 사라졌다.
//
//   사업주 서명 경로는 이미 같은 이유로 CF 안에 있었다. 이쪽만 남아 있었다.
//
//   옮긴 뒤: 서명 2444ms (이전 2408 + 32 + 609 ≈ 3049ms).
//   FCM 은 예나 지금이나 onNotificationCreated 트리거가 보낸다 —
//   여기서 바뀐 것은 "누가 알림 문서를 쓰는가"뿐이다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _svc() => File('lib/services/contract_service.dart').readAsStringSync();
String _fn() => File('functions/src/index.ts').readAsStringSync();
String _apply() =>
    File('lib/services/firestore/application_firestore.dart').readAsStringSync();

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
  final helper = _codeOf(_sliceOf(fn,
      'async function srvNotifyContractSigned(args: {',
      'export const callableFinalizeWorkerSignature = onCall('));
  final hf = _flat(helper);
  final signCf = _codeOf(_cfBody(fn, 'callableFinalizeWorkerSignature'));
  final sf = _flat(signCf);
  final client = _codeOf(_svc());
  final cf2 = _flat(client);

  group('CN-1 — 알림 문서를 서버가 쓴다', () {
    test('CN-10 클라이언트 서명 경로에 알림 호출이 없다', () {
      final worker = _sliceOf(client,
          'Future<EmploymentContractModel> saveWorkerSignature({',
          'Future<void> saveUserSignature({');
      expect(worker.contains('createNotification'), false);
      expect(worker.contains('NotificationModel.createContractSigned'), false);
      // 사업장 문서를 읽던 것도 사라졌다
      expect(worker.contains("collection('businesses')"), false);
    });

    test('CN-11 서명 CF 가 커밋 뒤 알림을 쓴다', () {
      expect(sf, contains('await srvNotifyContractSigned({ contractId, businessId: signedBizId,'));
    });

    test('CN-12 사업주 서명 경로는 예전 그대로다', () {
      final emp = _codeOf(_cfBody(fn, 'callableFinalizeEmployerSignature'));
      expect(emp.contains('collection("notifications")'), true);
    });
  });

  group('CN-2 — 수신자 범위가 그대로다', () {
    test('CN-20 관리자 + ownerId 폴백', () {
      expect(hf, contains('let adminIds: string[] = (bizData?.adminIds as string[] | undefined) ?? [];'));
      expect(hf, contains('const owner = bizData?.ownerId as string | undefined;'));
    });

    test('CN-21 canManageContract 서브어드민을 포함한다', () {
      expect(hf, contains('getSubAdminsWithPermission(businessId, "canManageContract")'));
    });

    test('CN-22 관리자와 겹치는 서브어드민은 한 번만 받는다', () {
      expect(hf, contains('...subAdminIds.filter((id) => !adminIds.includes(id)),'));
    });

    test('CN-23 수신자 해석을 직렬로 하지 않는다', () {
      expect(hf, contains('const [bizSnap, subAdminIds] = await Promise.all(['));
    });
  });

  group('CN-3 — payload / deeplink 불변', () {
    test('CN-30 타입·문구가 그대로다', () {
      expect(hf, contains('type: "contractSigned"'));
      expect(hf, contains('title: "계약서 서명 완료"'));
      expect(hf, contains(r'body: `${workerName}님이 근로계약서 서명을 완료했습니다.`'));
      expect(hf, contains('category: "admin"'));
      expect(hf, contains('isRead: false'));
    });

    test('CN-31 목적지 데이터가 그대로다', () {
      expect(hf, contains('data: {contractId, applicationId, businessId, screen: "contractSigned"}'));
    });

    test('CN-32 알림 재료는 트랜잭션에서 읽은 값이다', () {
      expect(sf, contains('signedBizId = contractBizId ?? "";'));
      expect(sf, contains('signedWorkerName ='));
      expect(sf, contains('signedApplicationId ='));
    });
  });

  group('CN-4 — 재시도가 알림을 두 번 쌓지 않는다', () {
    test('CN-40 문서 id 를 계약·수신자로 고정한다', () {
      expect(hf, contains(r'.doc(`contract_signed_${contractId}_${uid}`)'));
    });

    test('CN-41 add 가 아니라 create 다 — 이미 있으면 실패한다', () {
      expect(hf, contains('.create({...payload, userId: uid})'));
      expect(helper.contains('.add('), false);
    });

    test('CN-42 이미 있음은 오류로 취급하지 않는다', () {
      expect(hf, contains("if ((r.reason as {code?: number})?.code === 6) return;"));
    });
  });

  group('CN-5 — 알림 실패가 서명을 실패시키지 않는다', () {
    test('CN-50 커밋 이후에만 보낸다', () {
      final commitAt = signCf.indexOf('await db.runTransaction');
      final notifyAt = signCf.indexOf('await srvNotifyContractSigned(');
      expect(commitAt, greaterThan(-1));
      expect(commitAt, lessThan(notifyAt));
    });

    test('CN-51 알림 예외를 삼키고 성공을 반환한다', () {
      expect(sf, contains('} catch (e) { console.error( "⚠️ [finalizeWorkerSignature] contractSigned 알림 실패 (서명은 완료됨):", e); }'));
      final notifyAt = signCf.indexOf('await srvNotifyContractSigned(');
      final returnAt = signCf.indexOf('return {success: true, pdfUrl: computedPdfUrl, sigUrl};');
      expect(notifyAt, lessThan(returnAt));
    });

    test('CN-52 개별 수신자 실패도 서로를 막지 않는다', () {
      expect(hf, contains('await Promise.allSettled(recipients.map((uid) =>'));
    });

    test('CN-53 실패를 조용히 숨기지 않는다 — 수신자·계약을 남긴다', () {
      expect(hf, contains(r'`⚠️ [contractSigned] 알림 저장 실패 uid=${recipients[i]} ` + `contract=${contractId}:`, r.reason)'));
      expect(hf, contains(r'`⚠️ [contractSigned] 수신자 없음 — businessId=${businessId}`'));
    });
  });

  group('CN-6 — 인접 계약 불변', () {
    test('CN-60 FCM 은 여전히 트리거가 보낸다 — CF 는 문서만 쓴다', () {
      expect(helper.contains('sendEachForMulticast'), false);
      expect(helper.contains('messaging()'), false);
      expect(_codeOf(_cfBody(fn, 'onNotificationCreated')).contains('sendEachForMulticast'), true);
    });

    test('CN-61 P3A.1 지원 결과 계약이 그대로다', () {
      expect(_flat(_codeOf(_apply())), contains('Future<ApplyResult> applyToTO({'));
      expect(_flat(_codeOf(_apply())), contains('return ApplyResult.unknown('));
    });

    test('CN-62 서명 응답 모양이 그대로다', () {
      expect(sf, contains('return {success: true, pdfUrl: computedPdfUrl, sigUrl};'));
    });

    test('CN-63 클라이언트는 여전히 계약 모델을 돌려준다', () {
      expect(cf2, contains('return updated;'));
    });
  });
}
