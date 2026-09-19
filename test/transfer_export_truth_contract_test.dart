// [PII-DOC-R0.1] 지원 단계 개인정보 최소화 + 이체 자료의 truth
//
// 이 파일이 고정하는 것:
//
//   INV-1  지원자·운영 목록의 서버 응답에 계좌가 실리지 않는다.
//          UI가 안 그리는 것은 데이터가 안 갔다는 뜻이 아니다.
//
//   INV-2  확정된 급여의 지급 계좌는 Attendance 스냅샷이다.
//          현재 User 프로필이 은행 업로드 파일에 침투하는 경로가 없다.
//
//   INV-3  제외는 조용히 일어나지 않는다. 화면이 말한 행 수와 파일의 행 수가 같다.
//
// 판정 로직 자체의 검증은 test/unit/transfer_export_plan_test.dart에 있다.
// 여기서는 **누가 무엇을 호출하는지**를 소스에서 고정한다 — 그 연결이 끊기면
// 판정이 아무리 옳아도 실제 파일은 예전 값으로 만들어진다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// `//` 주석 줄 제거 — 주석에 적힌 옛 코드가 통과 근거가 되지 않도록.
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

/// 선언 [from]부터 다음 선언 [to] 직전까지.
String _sliceOf(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';
const _fsPath = 'lib/services/firestore_service.dart';
const _excelPath = 'lib/utils/payroll_excel_helper.dart';
const _planPath = 'lib/utils/transfer_export_plan.dart';
const _dashPath =
    'lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';

/// 목록·운영 목적으로 조회해야 하는 화면들. 여기 빠지면 전체본이 내려간다.
const _directoryCallers = <String>[
  'lib/screens/business_admin/dialogs/work_applicants_dialog.dart',
  'lib/screens/business_admin/dialogs/day_applicants_dialog.dart',
  'lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart',
  'lib/screens/business_admin/dialogs/resign_request_management_dialog.dart',
  'lib/screens/business_admin/dialogs/schedule_request_management_dialog.dart',
  'lib/screens/business_admin/dialogs/attendance_status_dialog.dart',
  'lib/screens/business_admin/dialogs/expiring_contracts_dialog.dart',
  'lib/screens/business_admin/expiring_contracts_screen.dart',
  'lib/screens/business_admin/workforce_management/workforce_operational_view.dart',
  'lib/services/admin_stats_service.dart',
];

void main() {
  final rawCf = _src(_cfPath);
  final cf = _codeOf(rawCf);

  group('INV-1 — 지원 단계 개인정보 최소화', () {
    test('01 서버가 workerDirectory purpose를 받는다', () {
      final batch = _flat(_codeOf(
          _sliceOf(rawCf, 'export const callableGetUsersBatch = onCall(',
              'export const callableGetAllUsers')));

      expect(batch, contains('purpose === "workerDirectory"'),
          reason: 'purpose 인식이 없으면 호출부가 보내도 무시된다');
      // 허용 목록에 없는 purpose는 거절한다 — 오타가 조용히 전체본이 되면 안 된다.
      expect(batch,
          contains('!isApplicantReview && !isWorkerDirectory'),
          reason: '알 수 없는 purpose는 invalid-argument여야 한다');
    });

    test('02 workerDirectory는 allowlist로 좁힌다 (denylist 아님)', () {
      final batch = _flat(_codeOf(
          _sliceOf(rawCf, 'export const callableGetUsersBatch = onCall(',
              'export const callableGetAllUsers')));

      expect(
          batch,
          contains(
              'isWorkerDirectory && !WORKER_DIRECTORY_ALLOWED.has(key)'),
          reason: 'allowlist여야 새 필드가 조용히 통과하지 않는다');
    });

    test('03 WORKER_DIRECTORY_ALLOWED에 계좌·서류·식별번호가 없다', () {
      final set = _codeOf(_sliceOf(
          rawCf, 'const WORKER_DIRECTORY_ALLOWED = new Set([', ']);'));

      for (final forbidden in [
        'accountNumber', 'bankName', 'accountHolder',
        'bankVerificationStatus',
        'bankbookImagePath', 'bankbookImageUrl',
        'idCardImagePath', 'idCardImageUrl',
        'residentNumber', 'foreignIdNumber', 'foreignIdentityFingerprint',
        'ciHash', 'ci',
        'address', 'detailAddress',
      ]) {
        expect(set, isNot(contains('"$forbidden"')),
            reason: '$forbidden 는 목록·운영 화면의 판단 정보가 아니다');
      }
    });

    test('04 지원 검토 allowlist에서 파생한다 — 두 벌로 갈라지지 않게', () {
      final set = _flat(_codeOf(_sliceOf(
          rawCf, 'const WORKER_DIRECTORY_ALLOWED = new Set([', ']);')));

      expect(set, contains('...APPLICANT_REVIEW_ALLOWED'),
          reason: '목록이 둘이면 한쪽만 늘어나고, 늘어나는 쪽은 덜 검토된 쪽이다');
    });

    test('05 클라이언트 purpose 상수가 서버 문자열과 같다', () {
      final fs = _codeOf(_src(_fsPath));

      expect(fs, contains("purposeWorkerDirectory = 'workerDirectory'"));
      expect(fs, contains("purposeApplicantReview = 'applicantReview'"));
    });

    test('06 캐시는 목적별로 나뉜다', () {
      final fs = _flat(_codeOf(_src(_fsPath)));

      // 축약본과 전체본이 한 칸에 섞이면, 급여 화면이 계좌 없는 사용자를
      // 받거나 목록 화면이 계좌가 실린 사용자를 받는다.
      expect(fs, contains("purpose == null ? uid : '\$purpose|\$uid'"),
          reason: '캐시 키에 목적이 들어가야 한다');
    });

    test('07 목록·운영 화면 전부가 workerDirectory로 조회한다', () {
      for (final path in _directoryCallers) {
        final code = _codeOf(_src(path));
        expect(code, contains('getUsersBatch'),
            reason: '$path 가 더는 이 CF를 쓰지 않으면 목록에서 빼야 한다');
        expect(code, contains('FirestoreService.purposeWorkerDirectory'),
            reason: '$path 가 전체본(계좌 포함)을 받고 있다');
      }
    });

    test('08 엑셀 생성은 사용자 문서에서 이름만 가져온다', () {
      final excel = _codeOf(_src(_excelPath));

      expect(excel, contains('FirestoreService.purposeWorkerDirectory'));
      for (final banned in [
        'user.bankName', 'user.accountNumber', 'user.accountHolder',
      ]) {
        expect(excel, isNot(contains(banned)),
            reason: '엑셀은 현재 프로필 계좌를 읽지 않는다');
      }
    });
  });

  group('INV-2 — 지급 계좌 source of truth는 확정 시점 스냅샷', () {
    test('09 판정기가 스냅샷 4필드만 본다', () {
      final plan = _flat(_codeOf(_src(_planPath)));

      for (final field in [
        'r.wageAccountBankName',
        'r.wageAccountNumberEncrypted',
        'r.wageAccountHolder',
        'r.wageAccountSnapshotAt',
      ]) {
        expect(plan, contains(field), reason: '$field 검사가 빠졌다');
      }
      // 서버 이체 CF와 같은 판별 — version 1만 V3 경로다.
      expect(plan, contains('r.wageAccountSnapshotVersion != 1'));
    });

    test('10 판정기에 현재 프로필 계좌가 들어올 입구가 없다', () {
      final plan = _codeOf(_src(_planPath));

      // UserModel을 아예 import하지 않는다 — fallback을 쓰고 싶어도 쓸 수 없다.
      expect(plan, isNot(contains('user_model.dart')));
      for (final banned in [
        'user.bankName', 'user.accountNumber', 'user.accountHolder',
        'UserModel',
      ]) {
        expect(plan, isNot(contains(banned)),
            reason: '현재 계좌가 스냅샷 자리를 대체하면 INV-2가 무너진다');
      }
    });

    test('11 legacy를 현재 계좌로 메우지 않고 별도 사유로 분리한다', () {
      final plan = _codeOf(_src(_planPath));

      expect(plan, contains('legacyNoSnapshot'));
      expect(plan, contains('reviewRequired'));
      expect(plan, contains('noAccountSnapshot'));
    });

    test('12 엑셀이 계획의 행만 그린다', () {
      final excel = _codeOf(_src(_excelPath));

      expect(excel, contains('required TransferExportPlan plan'),
          reason: '엑셀은 레코드가 아니라 이미 판정된 계획을 받는다');
      expect(excel, contains('final rows = plan.rows;'));
      // 옛 경로가 남아 있으면 누군가 다시 부른다.
      expect(excel, isNot(contains('buildTransferRows(')));
    });

    test('13 현재 프로필 계좌를 쓰던 옛 함수는 deprecated로 막혀 있다', () {
      final svc = _src('lib/services/payroll_payment_service.dart');
      final idx = svc.indexOf('List<TransferRow> buildTransferRows(');
      expect(idx, greaterThan(0));
      expect(svc.substring(0, idx), contains('@Deprecated('),
          reason: '같은 버그로 되돌아가는 문을 열어두지 않는다');
    });

    test('14 급여 화면 카드도 같은 출처를 읽는다', () {
      final dash = _codeOf(_src(_dashPath));

      // 화면이 보여주는 계좌와 실제 이체 계좌가 다르면 새 불일치가 된다.
      expect(dash, contains('_bankLineFor('));
      expect(dash, contains('buildTransferExportPlan('));
      expect(dash, isNot(contains("bank['accountNumber']")),
          reason: '카드가 현재 프로필 계좌를 그리면 안 된다');
      expect(dash, isNot(contains("user.accountNumber")));
    });

    test('15 Attendance 스냅샷 필드는 읽기 전용 투영이다', () {
      final model = _codeOf(_src('lib/models/core/attendance_model.dart'));

      expect(model, contains('wageAccountSnapshotVersion'));
      expect(model, contains('wageAccountReviewRequired'));
      // toMap에 실리면 rules가 클라이언트 쓰기를 막아 정상 경로가 죽는다.
      final toMap = _sliceOf(model, 'Map<String, dynamic> toMap()', '\n  Attendance');
      expect(toMap, isNot(contains("'wageAccountSnapshotVersion'")));
      expect(toMap, isNot(contains("'wageAccountReviewRequired'")));
    });
  });

  group('INV-3 — PARTIAL은 SUCCESS가 아니다', () {
    test('16 계획이 모든 건을 한 갈래에 담는다', () {
      final plan = _flat(_codeOf(_src(_planPath)));

      expect(
          plan,
          contains(
              'totalRecords == exportedRecords + blockedRecords + notApplicableRecords'),
          reason: '이 불변식이 없으면 건이 조용히 사라질 수 있다');
    });

    test('17 파일을 만들기 전에 계획을 먼저 보여준다', () {
      final dash = _flat(_codeOf(_src(_dashPath)));

      expect(dash, contains('prepareTransferPlan('));
      expect(dash, contains('_showTransferPlanSheet(plan)'));
      // 확인 전에 파일이 만들어지면 안 된다.
      final idxPlan = dash.indexOf('_showTransferPlanSheet(plan)');
      final idxExport = dash.indexOf('PayrollExcelHelper.exportTransferList(');
      expect(idxPlan, lessThan(idxExport),
          reason: '확인 시트가 export보다 먼저여야 한다');
      expect(dash, contains("confirmed != true"),
          reason: '닫기를 눌렀는데 파일이 만들어지면 안 된다');
    });

    test('18 화면이 말하는 숫자가 엑셀 행 수다', () {
      final dash = _flat(_codeOf(_src(_dashPath)));

      expect(dash, contains("'\${plan.rowCount}행 엑셀 다운로드'"),
          reason: '버튼이 실제 행 수를 말해야 한다');
      final plan = _flat(_codeOf(_src(_planPath)));
      expect(plan, contains('int get rowCount => rows.length;'));
    });

    test('19 확인 필요 대상이 이름과 사유로 보인다', () {
      final dash = _flat(_codeOf(_src(_dashPath)));

      expect(dash, contains('b.workerName'));
      expect(dash, contains('b.reason.label'));
      expect(dash, contains('b.reason.action'),
          reason: '왜 빠졌는지에서 끝나면 운영자가 다음에 할 일을 모른다');
    });

    test('20 제외 사유마다 라벨과 할 일이 따로 있다', () {
      final plan = _codeOf(_src(_planPath));
      final labels = _sliceOf(plan, 'String get label =>', 'String get action');

      for (final r in [
        'reviewRequired', 'noAccountSnapshot', 'legacyNoSnapshot',
        'zeroAmountUnexplained', 'dataError',
      ]) {
        expect(labels, contains('TransferBlockReason.$r'),
            reason: '$r 가 다른 사유와 한 문장으로 합쳐졌다');
      }
    });

    test('21 지급 대상 아님은 오류와 섞이지 않는다', () {
      final plan = _flat(_codeOf(_src(_planPath)));

      // 서버 이체 CF와 같은 식 — NO_SHOW/결근 0원만 '대상 아님'이다.
      expect(plan, contains('AttendanceModel.statusNoShow'));
      expect(plan, contains('AttendanceModel.statusAbsent'));
      expect(plan, contains('(r.finalWage ?? 0) == 0'));
      // 그 밖의 0원은 UNKNOWN이지 EMPTY가 아니다.
      expect(plan, contains('zeroAmountUnexplained'));
    });

    test('22 엑셀 파일 자체가 누락을 고지한다', () {
      final excel = _flat(_codeOf(_src(_excelPath)));

      // 파일은 화면을 떠나 은행·회계로 간다. 거기엔 물어볼 화면이 없다.
      expect(excel, contains('plan.totalRecords'));
      expect(excel, contains('plan.exportedRecords'));
      expect(excel, contains('plan.blockedWorkers'));
    });

    test('23 조회 실패한 uid를 목록에서 지우지 않는다', () {
      final excel = _flat(_codeOf(_src(_excelPath)));

      // 예전에는 user 조회 실패 시 continue로 사람이 사라지고 토스트만 떴다.
      expect(excel, isNot(contains('missingCount')));
      final plan = _flat(_codeOf(_src(_planPath)));
      expect(plan, contains("'이름 확인 불가'"),
          reason: '이름을 모르는 것과 대상이 아닌 것은 다르다');
    });
  });

  group('권한 — 새 capability를 만들지 않는다', () {
    test('24 급여 화면은 여전히 canManageWage로 fail-closed', () {
      final dash = _flat(_codeOf(_src(_dashPath)));

      expect(dash, contains('!perms.canManageWage'));
      expect(dash, isNot(contains('canExportTax')),
          reason: '이번 Phase에서 새 권한을 만들지 않는다');
    });

    test('25 workerDirectory는 추가 권한을 요구하지 않는다', () {
      final batch = _flat(_codeOf(
          _sliceOf(rawCf, 'export const callableGetUsersBatch = onCall(',
              'export const callableGetAllUsers')));

      // applicantReview만 canManageTo를 요구한다. 목록 목적까지 요구하면
      // 근태·계약 담당자가 이름조차 못 읽는 regression이 된다.
      expect(batch, contains('isApplicantReview && !isSuperAdmin && !isAdmin'));
      expect(batch, isNot(contains('isWorkerDirectory && !isSuperAdmin')));
    });
  });

  // ═══════════════════════════════════════════════════════════
  // [PII-DOC-R0.2] TRANSFERABLE IFF canonical snapshot
  //
  //   R0.1은 Excel을 스냅샷에 맞췄지만 이체 CF의 legacy 분기는 그대로
  //   통과시키고 있었다. 같은 급여 건에 Export=NOT READY / Transfer=ALLOWED
  //   라는 두 개의 답이 남아 있었고, 느슨한 쪽이 돈이 나가는 쪽이었다.
  // ═══════════════════════════════════════════════════════════
  group('R0.2 — legacy transfer fail-close', () {
    final xferBody = _codeOf(_sliceOf(
        rawCf, 'export const callableMarkTransferredBatch = onCall(',
        '// ─── callableCancelTransfer'));

    test('28 판정이 한 곳에만 있다 (helper)', () {
      final helper = _flat(_codeOf(_sliceOf(
          rawCf, 'function srvWageAccountBlockReason(', '\n}')));

      // 순서가 클라이언트 classifyRecord와 같아야 같은 건을 같은 이름으로 부른다.
      final iReview = helper.indexOf('wageAccountReviewRequired');
      final iLegacy = helper.indexOf('wageAccountSnapshotVersion');
      final iFields = helper.indexOf('wageAccountBankName');
      expect(iReview, greaterThan(-1));
      expect(iReview, lessThan(iLegacy), reason: '낡은 검토가 먼저다');
      expect(iLegacy, lessThan(iFields), reason: 'legacy 판별이 4필드보다 먼저다');

      // T3 — version 1인데 4필드가 비면 거절
      for (final f in [
        'wageAccountBankName', 'wageAccountNumberEncrypted',
        'wageAccountHolder', 'wageAccountSnapshotAt',
      ]) {
        expect(helper, contains('!data["$f"]'), reason: '$f 검사 누락');
      }
      // T4 — 재확인 필요면 거절
      expect(helper, contains('data["wageAccountReviewRequired"] === true'));
      // T2 — 위를 모두 통과하면 이체 가능
      expect(helper, contains('return null;'));
    });

    test('29 T1 — 이체 CF가 그 helper를 쓰고 legacy 통과 분기가 없다', () {
      expect(xferBody, contains('srvWageAccountBlockReason(data)'));
      expect(xferBody, contains('blocked[id] = blockReason'));
      expect(xferBody, contains('skipped.push(id)'));

      // 사라져야 하는 것: "legacy는 그대로 통과" 분기
      expect(xferBody, isNot(contains('LEGACY path')));
      expect(_flat(xferBody),
          isNot(contains('snapVersion === 1')),
          reason: 'V3/legacy 이분기가 남아 있으면 legacy가 다시 통과한다');
    });

    test('30 T5 — 이미 transferred인 과거 기록은 판정에 닿지 않는다', () {
      // 멱등 통과가 차단 판정보다 **먼저** 와야 소급 차단이 생기지 않는다.
      final iAlready = xferBody.indexOf('alreadyTransferred.push(id)');
      final iBlock = xferBody.indexOf('srvWageAccountBlockReason(data)');
      expect(iAlready, greaterThan(-1));
      expect(iBlock, greaterThan(-1));
      expect(iAlready, lessThan(iBlock),
          reason: 'historical legacy transferred는 그대로 보존한다');
    });

    test('31 batch 계약은 PARTIAL_RESULT 그대로 — throw로 바꾸지 않았다', () {
      // 99건 정상 + 1건 legacy에서 전체를 되돌리지 않는다.
      expect(xferBody, contains('return {'));
      expect(xferBody, contains('skipped,'));
      expect(xferBody, contains('blocked,'));
      // 차단 지점에서 HttpsError를 던지면 atomic으로 바뀐다.
      final blockSlice = xferBody.substring(
          xferBody.indexOf('const blockReason'));
      expect(blockSlice.substring(0, 300), isNot(contains('HttpsError')));
    });

    test('32 제외 사유가 id 하나로 뭉뚱그려지지 않는다', () {
      for (final code in [
        'XFER_NOT_FOUND', 'XFER_OTHER_BUSINESS', 'XFER_NOT_PAYABLE',
        'XFER_NOT_CONFIRMED', 'XFER_SETTLEMENT_LOCKED',
      ]) {
        expect(xferBody, contains('blocked[id] = $code'),
            reason: '$code 사유가 응답에 실리지 않는다');
      }
    });

    test('33 서버·클라이언트가 같은 단어를 쓴다', () {
      // 같은 사실을 두 언어가 다르게 부르면 화면이 "알 수 없는 오류"로 번역한다.
      final consts = _codeOf(_sliceOf(
          rawCf, 'const XFER_REVIEW_REQUIRED', 'function srvWageAccountBlockReason'));
      final dart = _codeOf(_src(_planPath));

      for (final token in [
        'reviewRequired', 'legacyNoSnapshot', 'noAccountSnapshot',
      ]) {
        expect(consts, contains('"$token"'), reason: '서버 토큰 $token');
        // Dart enum 이름 + TransferBlockCode 상수 양쪽에 있어야 한다.
        expect(dart, contains('  $token,'), reason: 'Dart enum $token');
        expect(dart, contains("$token = '$token'"),
            reason: 'TransferBlockCode.$token');
      }
    });

    test('34 T6 — 마감 취소가 스냅샷 흔적을 남기지 않는다', () {
      final cancel = _codeOf(_sliceOf(
          rawCf, 'export const callableCancelFinalConfirmation = onCall(',
          '// ─── callableWageCancel'));

      for (final f in [
        'wageAccountSnapshotVersion', 'wageAccountBankName',
        'wageAccountNumberEncrypted', 'wageAccountHolder',
        'wageAccountSnapshotAt',
        // 재확인 표시도 스냅샷과 같은 생애를 가진다.
        'wageAccountReviewRequired',
      ]) {
        expect(_flat(cancel),
            contains('$f: admin.firestore.FieldValue.delete()'),
            reason: '$f 가 calculated 상태에 남으면 재확정 판정을 오염시킨다');
      }
      // 급여 계산값·근무일·식별자는 유지 — 재확정이 새 급여를 만들지 않는다.
      expect(cancel, contains('wageStatus: "calculated"'));
      expect(cancel, isNot(contains('finalWage: admin.firestore.FieldValue.delete()')),
          reason: '금액을 지우면 재확정이 같은 급여가 아니게 된다');
      expect(cancel, isNot(contains('workDate:')));
    });

    test('35 T6 — 재확정이 V3 스냅샷을 다시 만든다', () {
      final confirm = _flat(_codeOf(_sliceOf(
          rawCf, 'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation')));

      expect(confirm, contains('updateData["wageAccountSnapshotVersion"] = 1'));
      expect(confirm, contains('wageAccountSnapshotAt'));
      expect(confirm, contains('bankReviewOkByUid'));
    });

    test('36 단건 경로가 제외를 성공으로 읽지 않는다', () {
      final svc = _codeOf(_src('lib/services/payroll_payment_service.dart'));

      expect(svc, contains('class TransferBlockedException'));
      expect(svc, contains('throw TransferBlockedException('));
      // skipped에 있으면 반드시 예외 — 조용한 성공 금지
      expect(svc, contains('if (!skipped.contains(attendanceId)) return;'));
      expect(svc, contains("already.contains(attendanceId)"),
          reason: '멱등 재시도는 실패가 아니다');
    });

    test('37 화면이 사유별로 다른 안내를 한다', () {
      final dash = _flat(_codeOf(_src(_dashPath)));

      expect(dash, contains('_explainTransferBlocks('));
      expect(dash, contains('_explainSingleBlock('));
      expect(dash, contains('TransferBlockCode.labelOf('));
      expect(dash, contains('TransferBlockCode.actionOf('));
      // 모든 제외를 한 문장으로 번역하던 옛 문구는 사라져야 한다.
      expect(dash, isNot(contains('계좌 정보 미확인으로 이체에서 제외되었습니다')));
      // CF 오류 문자열을 그대로 노출하지 않는다.
      expect(dash, contains('on TransferBlockedException catch'));
    });

    test('38 사유를 모르면 성공으로 바꾸지 않는다', () {
      final plan = _codeOf(_src(_planPath));
      // 알 수 없는 토큰 → '확인 필요'. 조용한 통과 아님.
      expect(plan, contains("_ => '확인 필요',"));

      final dash = _flat(_codeOf(_src(_dashPath)));
      expect(dash, contains('이체에서 제외되었습니다. 목록에서 상태를 확인해주세요.'),
          reason: '구버전 응답이라 사유를 몰라도 제외 사실은 말해야 한다');
    });
  });

  group('R1.2 회귀 — 기존 계약이 그대로다', () {
    test('26 지원 검토 purpose와 계좌 DTO 게이트가 유지된다', () {
      expect(cf, contains('APPLICANT_REVIEW_ALLOWED'));
      expect(_flat(cf), contains('canSeeDocs ? { bank: {'));
    });

    test('27 급여 확정의 계좌 검토 가드가 유지된다', () {
      final confirm = _flat(_codeOf(_sliceOf(
          rawCf, 'export const callableConfirmFinalWage = onCall(',
          'export const callableCancelFinalConfirmation')));

      expect(confirm, contains('bankReviewOkByUid'));
      expect(confirm, contains('wageAccountReviewRequired'));
    });
  });
}
