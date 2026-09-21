// [R8-P3B.2] 20명을 마감하면 알림 왕복이 20번 더 붙었다.
//
//   급여 마감·마감취소·소급공제·신분증요청·계약연장은 모두 CF 가 도메인을
//   커밋한 뒤, **클라이언트가** 알림 callable 을 다시 불렀다. 마감은 건수만큼
//   반복이라 20명이면 20번이었고, 화면이 그걸 await 했다. 왕복 하나가
//   DEV 실측 600ms대다.
//
//   그리고 마감취소는 같은 이벤트를 급여 화면과 근태 화면이 **각각** 만들어
//   문구 생성 로직이 두 벌이었다.
//
//   쓰는 주체만 서버로 옮겼다. 수신자·문구·목적지는 그대로다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _fn() => File('functions/src/index.ts').readAsStringSync();
String _read(String p) => File(p).readAsStringSync();

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
  final wageHelper = _codeOf(_sliceOf(fn,
      'async function srvNotifyWageEvent(',
      'export const callableConfirmFinalWage = onCall('));
  final wh = _flat(wageHelper);
  final confirmCf = _codeOf(_cfBody(fn, 'callableConfirmFinalWage'));
  final cancelCf = _codeOf(_cfBody(fn, 'callableCancelFinalConfirmation'));
  final idHelper = _codeOf(_sliceOf(fn,
      'async function srvNotifyIdCardAccessRequested(',
      'export const callableCreateIdCardAccessRequest = onCall('));
  final retroHelper = _codeOf(_sliceOf(fn,
      'async function srvNotifyRetroactiveDeduction(',
      'export const callableCalculateAndConfirmWage = onCall('));
  final renewHelper = _codeOf(_sliceOf(fn,
      'async function srvNotifyContractRenewed(',
      'export const callableCreateContractRenewal = onCall('));

  final wageDialog = _codeOf(
      _read('lib/screens/business_admin/dialogs/wage_confirm_dialog.dart'));
  final attDialog = _codeOf(
      _read('lib/screens/business_admin/dialogs/attendance_status_dialog.dart'));
  final idSvc = _codeOf(_read('lib/services/firestore/id_card_firestore.dart'));
  final fixedDialog = _codeOf(_read(
      'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart'));

  group('CN3-1 — 급여 알림을 서버가 쓴다', () {
    test('CN3-10 마감 CF 가 실제로 마감된 건만 알린다', () {
      expect(_flat(confirmCf), contains('const confirmedIds: string[] = [];'));
      expect(_flat(confirmCf), contains('confirmedIds.push(chunk[j]);'));
      expect(_flat(confirmCf), contains('await srvNotifyWageEvent("wageConfirmed", businessId,'));
    });

    test('CN3-11 마감취소 CF 도 실제 취소된 건만 알린다', () {
      expect(_flat(cancelCf), contains('const canceledRows:'));
      expect(_flat(cancelCf), contains('canceledRows.push(r.value);'));
      expect(_flat(cancelCf), contains('await srvNotifyWageEvent("wageCancelConfirmed", businessId, canceledRows);'));
    });

    test('CN3-12 알림 재료는 트랜잭션에서 읽은 값이다', () {
      expect(_flat(cancelCf), contains('const cancelNotifyRow = { attendanceId: id,'));
      expect(_flat(confirmCf), contains('const d = attSnapById.get(attId) ?? {};'));
    });

    test('CN3-13 금액은 실수령액 우선 — 화면이 쓰던 순서와 같다', () {
      expect(_flat(confirmCf), contains('amount: (wd.netWage as number | undefined) ?? (d.finalWage as number | undefined) ?? 0,'));
    });
  });

  group('CN3-2 — 소급공제·신분증·연장도 서버가 쓴다', () {
    test('CN3-20 소급공제는 계산한 CF 가 알린다', () {
      final calc = _codeOf(_cfBody(fn, 'callableCalculateAndConfirmWage'));
      expect(_flat(calc), contains('if (wageResult2.retroactiveDeduction > 0) {'));
      expect(_flat(calc), contains('await srvNotifyRetroactiveDeduction({'));
      expect(_flat(retroHelper), contains('type: "retroactiveDeductionAlert"'));
    });

    test('CN3-21 신분증 요청은 만든 CF 가 알린다', () {
      final idCf = _codeOf(_cfBody(fn, 'callableCreateIdCardAccessRequest'));
      expect(_flat(idCf), contains('await srvNotifyIdCardAccessRequested({'));
      // CREATED 로 반환하기 직전에만 보낸다
      final notifyAt = idCf.indexOf('await srvNotifyIdCardAccessRequested(');
      final createdAt = idCf.indexOf('return {requestId: docRef.id, reason: "CREATED"};');
      expect(notifyAt, lessThan(createdAt));
    });

    test('CN3-22 계약 연장은 연장 CF 가 알린다', () {
      final renew = _codeOf(_cfBody(fn, 'callableCreateContractRenewal'));
      expect(_flat(renew), contains('await srvNotifyContractRenewed({'));
      expect(_flat(renewHelper), contains('type: "contractRenewed"'));
      expect(_flat(renewHelper), contains('screen: "mySchedule"'));
    });

    test('CN3-23 사유 문구 표가 서버로 왔다', () {
      expect(_flat(fn), contains('const ID_ACCESS_REASON_TEXT: Record<string, string> = { incomeTax: "소득세 신고", laborContract: "근로계약서 작성", insurance: "4대보험 신고", identityVerify: "본인 확인", other: "기타", };'));
      expect(idSvc.contains('_getReasonText'), false);
    });
  });

  group('CN3-3 — 클라이언트 추가 왕복이 사라졌다', () {
    test('CN3-30 급여 화면에 알림 호출이 없다', () {
      expect(wageDialog.contains('createNotification'), false);
      expect(wageDialog.contains('NotificationModel.'), false);
    });

    test('CN3-31 근태 화면의 마감취소 알림도 사라졌다', () {
      expect(attDialog.contains('createWageCancelConfirmed'), false);
      expect(attDialog.contains('NotificationModel.'), false);
    });

    test('CN3-32 신분증 서비스에 알림 호출이 없다', () {
      expect(idSvc.contains('createNotification'), false);
    });

    test('CN3-33 계약 연장 알림 호출이 없다', () {
      expect(fixedDialog.contains('createContractRenewed'), false);
    });

    test('CN3-34 같은 이벤트를 두 화면이 각각 만들지 않는다', () {
      // wageCancelConfirmed 문구를 만드는 곳은 서버 한 곳뿐이다
      expect('wageCancelConfirmed'.allMatches(wageDialog).length, 0);
      expect('wageCancelConfirmed'.allMatches(attDialog).length, 0);
      expect(wh, contains('"wage_confirmed" : "wage_cancel_confirmed"'));
    });
  });

  group('CN3-4 — 재시도가 알림을 두 번 쌓지 않는다', () {
    test('CN3-40 문서 id 가 사건·수신자로 고정돼 있다', () {
      expect(wh, contains(r'.doc(`${idPrefix}_${r.attendanceId}_${r.userId}`)'));
      expect(_flat(idHelper), contains(r'.doc(`id_access_requested_${a.requestId}_${a.targetUserId}`)'));
      expect(_flat(retroHelper), contains(r'.doc(`retroactive_deduction_${a.attendanceId}_${a.userId}`)'));
      expect(_flat(renewHelper), contains(r'.doc(`contract_renewed_${a.applicationId}_${a.workerUid}`)'));
    });

    test('CN3-41 add 가 아니라 create 다', () {
      for (final h in [wageHelper, idHelper, retroHelper, renewHelper]) {
        expect(h.contains('.add('), false);
        expect(_flat(h), contains('.create({'));
      }
    });

    test('CN3-42 이미 있음(6)은 오류가 아니다', () {
      for (final h in [wageHelper, idHelper, retroHelper, renewHelper]) {
        expect(h.contains('code === 6'), true);
      }
    });
  });

  group('CN3-5 — 알림 실패가 도메인 실패가 아니다', () {
    test('CN3-50 마감/취소 CF 가 알림 예외를 삼킨다', () {
      expect(_flat(confirmCf), contains('console.error("[confirmFinalWage] 마감 알림 실패(마감은 유지):", e);'));
      expect(_flat(cancelCf), contains('console.error("[cancelFinalConfirmation] 취소 알림 실패(취소는 유지):", e);'));
    });

    test('CN3-51 커밋 이후에만 보낸다', () {
      expect(confirmCf.indexOf('runTransaction'),
          lessThan(confirmCf.indexOf('await srvNotifyWageEvent(')));
      expect(cancelCf.indexOf('runTransaction'),
          lessThan(cancelCf.indexOf('await srvNotifyWageEvent(')));
    });

    test('CN3-52 수신자별 실패가 서로를 막지 않는다', () {
      expect(wh, contains('await Promise.allSettled(targets.map((r) =>'));
    });

    test('CN3-53 실패를 숨기지 않는다 — 수신자·사건 id 를 남긴다', () {
      expect(wh, contains(r'`⚠️ [${kind}] 알림 저장 실패 uid=${targets[i].userId} ` + `attendance=${targets[i].attendanceId}:`, r.reason)'));
    });
  });

  group('CN3-6 — 문구·목적지 parity', () {
    test('CN3-60 급여 문구가 그대로다', () {
      expect(wh, contains('title: kind === "wageConfirmed" ? "급여 정산 완료" : "급여 확정 취소"'));
      expect(wh, contains(r'`${head} 급여가 정산되었습니다. 앱에서 확인하세요.`'));
      expect(wh, contains(r'`${head} 급여 확정이 취소되었습니다. 급여 조정 후 다시 안내드릴 예정입니다.`'));
      expect(wh, contains('action: "wageDetail"'));
      expect(wh, contains('category: "personal"'));
    });

    test('CN3-61 근무일 표기가 KST M/D 다', () {
      expect(wh, contains('const when = r.workDateMs ? srvKstMonthDay(r.workDateMs) : "";'));
    });

    test('CN3-62 §13 신분증 알림에 민감정보가 없다', () {
      expect(_flat(idHelper), contains('data: { requestId: a.requestId, businessId: a.businessId, action: "idCardAccessRequest", }'));
      for (final bad in ['idCardImage', 'residentNumber', 'signedUrl', 'ci']) {
        expect(idHelper.contains('"$bad"'), false, reason: bad);
      }
    });

    test('CN3-63 FCM 은 여전히 트리거가 보낸다', () {
      for (final h in [wageHelper, idHelper, retroHelper, renewHelper]) {
        expect(h.contains('sendEachForMulticast'), false);
        expect(h.contains('messaging()'), false);
      }
    });
  });

  group('CN3-7 — 인접 계약 불변', () {
    test('CN3-70 급여 truth 가 그대로다', () {
      expect(_flat(confirmCf), contains('return { success: true, processed: successCount, skipped, correctionsOpened, };'));
      expect(_flat(cancelCf), contains('return {success: true, processed: successCount, skipped};'));
    });

    test('CN3-71 P3B/P3B.1 알림 소유가 유지된다', () {
      for (final h in ['srvNotifyContractSigned', 'srvNotifyConfirmationCanceled',
        'srvNotifyContractVoided']) {
        expect(fn.contains('async function $h'), true, reason: h);
      }
    });
  });
}
