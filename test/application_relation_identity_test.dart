// [CROSS-DOMAIN-R5.3C.2] Application 관계 identity / 금전 약속 chain
//
// 이 파일이 고정하는 것:
//
//   1. 한 근무 단위에 대한 관계는 `{uid, toId, slotId, wdId}` 하나다.
//      문서 id는 저장 구현일 뿐이고 실제로 writer마다 다르다:
//        직접 지원  → `{toId}_{slotId}_{workDetailId}_{uid}`  (composite)
//        초대·제안  → `{toId}_{slotId}_{wdId}_{uid}`
//      id로만 중복을 보면 같은 사람이 같은 업무에 두 줄로 남는다.
//      DEV 실측: Application 2건, pendingCount 2 — 한 사람이 두 번 세어졌다.
//
//      id를 통일하는 migration은 하지 않는다 — 기존 알림·계약·근태가 전부
//      그 id를 참조한다. 새 writer가 **관계로 찾아 수렴**한다.
//
//   2. 법정 최저임금은 약속을 만드는 **모든** writer가 본다.
//      worker-specific 제안만 막고 직접 지원·초대를 두면 경계가 아니다.
//
//   3. 급여명세서는 확정된 Wage truth를 읽는다. 공고를 다시 읽어
//      약속을 재구성하지 않는다. 그리고 없는 값을 0원으로 표시하지 않는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _load(String p) => _flat(_codeOf(_src(p)));

String _callableBody(String raw, String name) {
  final start = raw.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final end = raw.indexOf('\n);', start);
  if (end < 0) throw StateError('$name 본문 끝을 찾지 못함');
  return raw.substring(start, end);
}

const _cf = 'functions/src/index.ts';
const _payslipView = 'lib/screens/payroll/payslip_view_screen.dart';
const _payslipPdf = 'lib/screens/payroll/payslip_pdf_builder.dart';
const _workerWage = 'lib/screens/user/wage_detail_screen.dart';

void main() {
  final rawCf = _codeOf(_src(_cf));
  final cf = _flat(rawCf);
  final apply = _flat(_callableBody(rawCf, 'callableApplyToTO'));
  final invite = _flat(_callableBody(rawCf, 'callableInviteWorker'));
  final offer = _flat(_callableBody(rawCf, 'callableOfferAlternativeWork'));

  // ══════════════════════════════════════════════════════════════════
  // BLOCKER-APPLICATION-NATURAL-KEY-DISCRIMINATOR-SPLIT
  // ══════════════════════════════════════════════════════════════════

  group('관계는 tuple 하나다 — 문서 id가 아니다', () {
    test('공용 관계 조회 helper가 있다', () {
      expect(cf.contains('async function srvFindRelationApplications('), true);
    });

    test('조회 축이 uid + toId + slotId + wdId다', () {
      expect(
          cf.contains('.where("uid", "==", uid) .where("toId", "==", toId);'),
          true);
      expect(cf.contains('if (slotId) q = q.where("slotId", "==", slotId);'), true);
      expect(cf.contains('(d) => d.get("wdId") === wdId && d.id !== excludeDocId'),
          true);
    });

    test('wdId가 없으면 관계로 묶지 않는다', () {
      // 같은 업무명만 보고 합치면 시간대가 다른 별개 근무가 하나로 뭉친다.
      expect(cf.contains('if (!wdId) return [];'), true);
    });

    test('세 writer가 모두 같은 helper를 쓴다', () {
      expect(apply.contains('const applyRelated = await srvFindRelationApplications('),
          true);
      expect(invite.contains('const inviteRelated = await srvFindRelationApplications('),
          true);
      expect(offer.contains('const offerRelated = await srvFindRelationApplications('),
          true);
    });

    test('기존 문서에 수렴한다 — 새 id를 만들지 않는다', () {
      expect(
          apply.contains('const applyDocId = applyRelation ? applyRelation.id : complexId;'),
          true);
      expect(
          apply.contains('const appRef = db.collection("applications").doc(applyDocId);'),
          true);
      expect(
          invite.contains('.doc(inviteRelation ? inviteRelation.id : inviteComplexId);'),
          true);
    });

    test('docId 일괄 migration을 하지 않았다', () {
      // 기존 알림·계약·근태가 참조하는 id를 바꾸지 않는다.
      expect(apply.contains('const complexId = slotId ?'), true,
          reason: '직접 지원의 기존 id 규칙은 그대로다');
      expect(invite.contains('const inviteComplexId = slotId ?'), true);
    });

    test('초대받은 근무에 다시 지원하지 않는다', () {
      // 수렴 이후 두 문서가 만나므로 INVITED를 명시적으로 막아야 한다.
      // 막지 않으면 tx.set이 초대를 덮어쓰고 카운터가 한 번 더 오른다.
      expect(
          apply.contains('if (exStatus === "INVITED") { throw new HttpsError( '
              '"already-exists", '
              '"이미 초대를 받은 근무입니다. 내 지원 내역에서 초대를 확인해주세요.");'),
          true);
    });

    test('제안도 관계를 트랜잭션 읽기 집합에 넣는다', () {
      expect(offer.contains('const freshAlt = await offerTx.get(offerAltKeyed.ref);'),
          true);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // VERIFY-SHARED-MINIMUM-WAGE-PRECOMMIT-BOUNDARY
  // ══════════════════════════════════════════════════════════════════

  group('최저임금은 약속을 만드는 모든 writer가 본다', () {
    test('공용 validator 하나를 쓴다', () {
      expect(cf.contains('function srvValidateMinimumWagePromise('), true);
      expect(cf.contains('async function srvLoadMinimumWage('), true);
    });

    test('직접 지원', () {
      expect(apply.contains('srvValidateMinimumWagePromise({'), true);
      expect(apply.contains('if (applyViolation) { throw new HttpsError('), true);
    });

    test('초대', () {
      expect(invite.contains('srvValidateMinimumWagePromise({'), true);
      expect(invite.contains('if (invViolation) { throw new HttpsError('), true);
    });

    test('다른 업무 제안', () {
      expect(offer.contains('srvValidateMinimumWagePromise({'), true);
    });

    test('근무일 기준으로 본다 — 공고 작성 시점이 아니다', () {
      // 최저임금은 해마다 바뀐다. 작년 공고가 올해 근무일에는 미달일 수 있다.
      expect(apply.contains('const applyKstYear = new Date( workDate.toMillis() + '
          '9 * 60 * 60 * 1000).getUTCFullYear();'), true);
      expect(invite.contains('new Date(new Date(workDate).getTime() + '
          '9 * 60 * 60 * 1000) .getUTCFullYear());'), true);
    });

    test('커밋 전에 본다', () {
      for (final body in [apply, invite, offer]) {
        final at = body.indexOf('srvValidateMinimumWagePromise({');
        final tx = body.indexOf('runTransaction');
        expect(at, greaterThan(-1));
        expect(at < tx, true, reason: '트랜잭션보다 먼저여야 상태가 남지 않는다');
      }
    });

    test('급여 확정과 같은 판정식이다', () {
      expect(cf.contains('const minDaily = Math.ceil(p.minimumWage * work / 60);'),
          true);
      expect(cf.contains('const applyMinWage = await srvLoadMinimumWage(applyKstYear);'),
          true, reason: '최저임금 출처도 같아야 한다');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // BLOCKER-PAYSLIP-COMPENSATION-PROJECTION-PARITY
  // ══════════════════════════════════════════════════════════════════

  group('급여명세서는 확정된 Wage truth를 읽는다', () {
    final view = _load(_payslipView);
    final pdf = _load(_payslipPdf);
    final worker = _load(_workerWage);

    test('명세서 뷰어는 attendance.wageDetail에서 만든다', () {
      expect(view.contains('return PayslipData.fromAttendance( attendance: widget.attendance,'),
          true);
    });

    test('명세서가 공고를 다시 읽지 않는다', () {
      for (final s in [view, pdf, worker]) {
        for (final forbidden in [
          "collection('tos')", 'getTO(', 'workDetailTimeMap',
          'getSlotWorkDetails', 'WorkDetailHelper',
        ]) {
          expect(s.contains(forbidden), false,
              reason: '명세서에서 공고를 재조회하면 약속이 재구성된다: $forbidden');
        }
      }
    });

    test('PDF도 attendance.wageDetail만 쓴다', () {
      expect(pdf.contains('final wd = attendance.wageDetail;'), true);
    });

    test('통상시급은 확정 계산이 남긴 값을 쓴다', () {
      // AUTO는 서버가 약정 금액과 근무시간으로 파생해 저장한 값이다.
      expect(
          worker.contains('final int standardHourly = (wd?.appliedSupplementWage ?? 0) > 0'),
          true);
    });
  });

  group('없는 값을 0원으로 표시하지 않는다', () {
    final view = _load(_payslipView);
    final pdf = _load(_payslipPdf);

    test('급여 정보가 없으면 예외다', () {
      expect(
          view.contains("if (widget.attendance.wageDetail == null) { "
              "throw Exception('급여 정보가 없습니다. 관리자에게 문의해주세요.'); }"),
          true,
          reason: '데이터 부재를 0원 명세서로 만들지 않는다');
    });

    test('이체됐는데 날짜가 없으면 그렇게 말한다', () {
      expect(pdf.contains("'임금지급일: 확인 필요',"), true,
          reason: '날짜를 지어내지 않는다');
    });

    test('예정일이 없으면 행을 생략한다 — 0이나 임의 날짜가 아니다', () {
      expect(
          pdf.contains('} else if (d.wageStatus == AttendanceModel.wageConfirmed && '
              'd.scheduledPaymentDate != null) {'),
          true);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 금전 chain — 한 관계만 존재하므로 선택 여지가 없다
  // ══════════════════════════════════════════════════════════════════

  group('Contract / Attendance / Wage가 같은 관계를 읽는다', () {
    test('Attendance는 applicationId로 join한다', () {
      expect(cf.contains('applicationId,'), true);
      expect(cf.contains('snapshotWage: typeof appData.wage === "number" ? appData.wage : undefined,'),
          true);
    });

    test('급여 계산은 그 Application의 약속을 읽는다', () {
      final wage = _flat(_callableBody(rawCf, 'callableCalculateAndConfirmWage'));
      expect(wage.contains('const wageAppId = attData2.applicationId as string | undefined;'),
          true);
      expect(wage.contains('srvResolvePromisedCompensation(wagePromiseApp,'), true);
    });

    test('계약서는 Application의 약속을 workDetail 위에 덮는다', () {
      expect(
          _load('lib/services/contract_service.dart')
              .contains('workDetail = _withPromisedWage(application, workDetail);'),
          true);
    });
  });
}
