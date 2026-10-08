// [R7-PAYROLL-POLICY.4] 누가 기준을 정했고, 어떤 기준으로 약속했는가
//
// `.3` 은 확정 시점에 근태 기준을 고정했다. 그런데 두 군데가 남아 있었다.
//
//   ① **지원할 때 본 기준과 확정될 기준이 다를 수 있었다.**
//      휴게·야간·통상시급은 지원 시점에 고정하면서(`buildCompensationSnapshot`)
//      반올림 단위만 확정 시점에 읽었다. 그러면 10/1 에 지각 30분 기준을 보고
//      지원한 사람이 10/3 에 10분 기준으로 확정된다. 어느 쪽이 유리한지는
//      기준이 아니다 — **조건이 바뀌었다는 것**이 문제다.
//      이 7개 숫자는 인정 근로시간을 바꾸고 그대로 금액이 되므로, 휴게·야간과
//      같은 분류의 임금 산정 조건이다. 같은 원칙(지원 시점 고정)을 적용한다.
//
//   ② **기본값을 쓰는 사업장에 확인 증거가 없었다.**
//      `policySource = alfit_default` 는 값의 **출처**일 뿐 확인 행위가 아니다.
//      급여를 깎는 `lateUnit 30` 은 ALfit 기본값인데, 사업장이 그것을 자기
//      기준으로 확인한 기록이 없으면 그 정책의 책임이 어디에도 귀속되지 않는다.
//
// 반올림 계산식은 **한 줄도 바꾸지 않았다.**
//
// 고정하는 것
//   TIME-1  지원이 기준을 고정한다
//   TIME-2  재지원도 그 시점 기준으로 다시 고정한다
//   TIME-3  초대도 같은 자리에서 고정한다 (apply/invite 대칭)
//   TIME-4  확정은 기존 snapshot 을 덮지 않는다
//   TIME-5  초대 수락도 기존 snapshot 을 덮지 않는다
//   TIME-6  확정 재배치는 원 약속의 기준을 물려받는다
//   TIME-7  목록·기본값은 한 벌이다
//   OWN-6   출처와 확인은 다른 필드다
//   OWN-7   확인 기록에 확인한 값이 들어 있다
//   OWN-8   값이 바뀌면 과거 확인이 무효가 된다
//   OWN-9   서버가 출처를 바꾸지 않는다
//   OWN-10  기준이 없으면 서버가 기본값을 만들어 주지 않는다
//   OWN-11  확인 권한은 수정 권한과 같다 (SubAdmin 제외)
//   OWN-12  확인 증거는 CF 전용이다 (rules 차단)
//   GATE-1  공고 readiness 에 기준 확인이 들어 있다
//   GATE-2  확정이 미확인 기준을 거부한다
//   GATE-3  초대 발송도 거부한다
//   GATE-4  초대 수락도 거부한다 (근로자에게는 설정 내부를 알리지 않는다)
//   GATE-5  이유 코드가 분리돼 있다
//   GATE-6  기존 확정 근무는 gate 에 걸리지 않는다
//   DISC-1  관리자 설정 이름에 급여가 드러난다
//   DISC-2  영향 예시는 실제 계산 helper 로 만든다
//   DISC-3  면책 문구를 쓰지 않는다
//   DISC-4  계약서는 Application snapshot 만 쓴다
//   DISC-5  화면과 PDF 가 같은 것을 말한다
//   DISC-6  근로자 공고 상세에 기준 접근이 있다
//   DISC-7  관리자 근태 화면이 live 정책으로 미리보기하지 않는다
//   MUT-0   변형이 조건을 무력화하는 형태를 막는다
import 'dart:io';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/utils/attendance_rounding_helper.dart';
import 'package:ALfit/utils/posting_readiness_reason.dart';
import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

String _code(String s) => s
    .split('\n')
    .where((l) {
      final t = l.trimLeft();
      return !t.startsWith('//') && !t.startsWith('*') && !t.startsWith('/*');
    })
    .join('\n');

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  if (i < 0) throw StateError('구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  if (j <= i) throw StateError('구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

String _callable(String ts, String name) =>
    _slice(ts, 'export const $name = onCall(', '\nexport const ');

void main() {
  final cfRaw = _src('functions/src/index.ts');
  final cf = _code(cfRaw);
  final rules = _src('firestore.rules');
  final form =
      _code(_src('lib/screens/business_admin/business_form_screen.dart'));

  group('snapshot 시점 — 지원이 기준을 고정한다', () {
    final apply = _code(_callable(cfRaw, 'callableApplyToTO'));

    test('TIME-1 지원이 기준을 고정한다', () {
      // 금액 조건과 **같은 자리**에서 만든다 — 두 원칙이 갈라지지 않게.
      // [R7-PAYROLL-POLICY.4C] 읽기가 트랜잭션 **안**으로 들어갔다. 비교한
      //   값과 저장한 값이 같은 읽기에서 나와야 하기 때문이다(race 차단).
      //   지키려던 계약은 그대로다 — 지원 시점에 서버가 고정한다.
      expect(
          apply.contains(
              'srvBuildAttendancePolicySnapshot(applyTxBizSnap.data())'),
          isTrue,
          reason: '지원 시점 조건에 근태 기준이 빠지면 확정 때 바뀐 기준이 적용된다');
      expect(apply.contains('attendancePolicySnapshot: applyTxPolicy'), isTrue);
      // 지원 경로가 사업장 규칙을 직접 집어 쓰지 않는다 — `attendanceRules` 는
      //   **트랜잭션 안 읽기 한 줄**에만 나타난다.
      // [R7-PAYROLL-POLICY.4D] 그 값을 `applyTxRules` 로 한 번 꺼내 canonical
      //   판정·토큰 비교·snapshot 이 전부 같은 값을 쓴다.
      expect(
          'attendanceRules'.allMatches(apply).length, 1,
          reason: '정책 값을 다른 자리에서 또 집으면 출처가 둘이 된다');
      expect(
          apply.contains(
              'const applyTxRules = applyTxBizSnap.data()?.["attendanceRules"];'),
          isTrue);
      expect(apply.contains('srvAttendancePolicyFingerprint(applyTxRules)'),
          isTrue);
    });

    test('TIME-2 재지원도 그 시점 기준으로 다시 고정한다', () {
      // 되살리는 분기와 새로 만드는 분기 **둘 다** 적는다.
      final occurrences =
          'attendancePolicySnapshot: applyTxPolicy'.allMatches(apply);
      expect(occurrences.length, 2,
          reason: '재지원(update)과 신규(set) 중 하나만 적으면 경로마다 기준이 달라진다');
    });

    test('TIME-3 초대도 같은 자리에서 고정한다', () {
      final invite = _code(_callable(cfRaw, 'callableInviteWorker'));
      expect(invite.contains('srvBuildAttendancePolicySnapshot(invBizData)'),
          isTrue, reason: '직접 지원과 초대가 같은 약속을 만들어야 한다');
      expect(invite.contains('attendancePolicySnapshot: s'), isTrue);
    });

    test('TIME-4 확정은 기존 snapshot 을 덮지 않는다', () {
      final confirm = _code(_callable(cfRaw, 'callableConfirmApplication'));
      expect(confirm.contains('if (fd["attendancePolicySnapshot"] == null) {'),
          isTrue,
          reason: '지원 당시 조건을 확정 시점 값으로 덮으면 조건이 몰래 바뀐다');
    });

    test('TIME-5 초대 수락도 기존 snapshot 을 덮지 않는다', () {
      final accept = _code(_callable(cfRaw, 'callableAcceptTOInvitation'));
      expect(
          accept.contains('if (freshData["attendancePolicySnapshot"] == null)'),
          isTrue);
      // 수락은 **새 약속을 만드는 두 번째 writer** 다 — snapshot 이 없으면 만든다.
      expect(accept.contains('srvBuildAttendancePolicySnapshot('), isTrue);
    });

    test('TIME-6 확정 재배치는 원 약속의 기준을 물려받는다', () {
      final reassign =
          _code(_callable(cfRaw, 'callableAcceptConfirmedReassignment'));
      expect(
          reassign.contains('srcData["attendancePolicySnapshot"]'), isTrue,
          reason: '재배치를 계기로 이미 성립한 약속의 계산 기준이 바뀌면 안 된다');
      // 사업장 현재 설정을 읽어 새로 만들지 않는다.
      expect(reassign.contains('srvBuildAttendancePolicySnapshot('), isFalse);
    });

    test('TIME-7 목록·기본값은 한 벌이다', () {
      // snapshot builder 와 확인 판정이 같은 집합을 봐야 한다.
      final builder = _code(_slice(
          cfRaw, 'function srvBuildAttendancePolicySnapshot(', '\n/**'));
      expect(builder.contains('ATTENDANCE_POLICY_MATERIAL_FIELDS'), isTrue);
      // [R7-PAYROLL-POLICY.4A] 확인 판정이 비교 helper 로 한 번 더 빠졌다.
      //   사업장 확인과 지원서 확인이 같은 비교를 쓴다 — 목록을 보는 곳이
      //   `srvPolicyEvidenceCovers` 하나로 좁아졌다.
      final block =
          _code(_slice(cfRaw, 'function srvAttendancePolicyBlock(', '\n/**'));
      expect(block.contains('srvPolicyEvidenceCovers('), isTrue);
      final covers =
          _code(_slice(cfRaw, 'function srvPolicyEvidenceCovers(', '\n/**'));
      expect(covers.contains('ATTENDANCE_POLICY_MATERIAL_FIELDS'), isTrue);
      // 숫자 목록은 소스에 **한 번만** 선언된다.
      expect('const ATTENDANCE_POLICY_MATERIAL_FIELDS'.allMatches(cf).length, 1);
      expect('const ATTENDANCE_POLICY_DEFAULTS'.allMatches(cf).length, 1);
    });
  });

  group('ownership — 출처와 확인은 다른 사실이다', () {
    final block =
        _code(_slice(cfRaw, 'function srvAttendancePolicyBlock(', '\n/**'));
    final cfm =
        _code(_callable(cfRaw, 'callableConfirmAttendancePolicy'));

    test('OWN-6 출처와 확인은 다른 필드다', () {
      // policySource 만 보고 확인됐다고 판정하지 않는다.
      expect(block.contains('attendancePolicyConfirmation'), isTrue);
      expect(block.contains('policySource'), isFalse,
          reason: 'alfit_default 를 확인 증거로 쓰면 책임 귀속이 거짓이 된다');
    });

    test('OWN-7 확인 기록에 확인한 값과 actor·시각이 들어 있다', () {
      expect(cfm.contains('confirmedAt: admin.firestore.FieldValue.serverTimestamp()'),
          isTrue, reason: '클라이언트 시각을 쓰지 않는다');
      expect(cfm.contains('confirmedBy: callerUid'), isTrue,
          reason: '소유자 uid 가 아니라 실제 확인한 사람이다');
      expect(cfm.contains('for (const k of ATTENDANCE_POLICY_MATERIAL_FIELDS)'),
          isTrue);
      // 클라이언트가 보낸 값을 적지 않는다 — 저장된 값을 읽어 적는다.
      expect(cfm.contains('srvAttendancePolicyValue(r, k)'), isTrue);
      expect(cfm.contains('request.data as {businessId?: string}'), isTrue,
          reason: 'payload 에 정책 값이 들어올 자리가 없어야 한다');
    });

    test('OWN-8 값이 바뀌면 과거 확인이 무효가 된다', () {
      // 7개 중 하나라도 다르면 미확인이다 — 별도 revision 시스템 없이 보장.
      // [R7-PAYROLL-POLICY.4A] 비교가 `srvPolicyEvidenceCovers` 로 빠졌다.
      //   지키려던 계약은 그대로다 — 값이 다르면 그 확인은 무효다.
      expect(block.contains('ATTENDANCE_POLICY_NOT_CONFIRMED'), isTrue);
      final covers =
          _code(_slice(cfRaw, 'function srvPolicyEvidenceCovers(', '\n/**'));
      expect(covers.contains('if (e[k] !== srvAttendancePolicyValue(target, k)) return false;'),
          isTrue, reason: '값 비교가 없으면 낡은 확인이 새 정책의 동의로 재사용된다');

      // Dart 쪽 표현도 같은 술어여야 한다.
      const base = AttendanceRules();
      final confirmation = AttendancePolicyConfirmation(
        earlyWindow: base.earlyWindow,
        earlyArrivalUnit: base.earlyArrivalUnit,
        lateGrace: base.lateGrace,
        lateUnit: base.lateUnit,
        lateWindow: base.lateWindow,
        overtimeUnit: base.overtimeUnit,
        earlyLeaveUnit: base.earlyLeaveUnit,
        confirmedAt: DateTime(2026, 10, 8),
        confirmedBy: 'admin-1',
      );
      expect(confirmation.matches(base), isTrue);
      expect(confirmation.matches(base.copyWith(lateUnit: 10)), isFalse);
      expect(confirmation.matches(base.copyWith(lateGrace: 0)), isFalse);
      // 감사 필드만 다르면 같은 기준이다 — 저장마다 무효가 되면 안 된다.
      expect(
          confirmation.matches(base.copyWith(
              policySource: AttendanceRules.sourceAdminSelected)),
          isTrue);
    });

    test('OWN-8b 증거가 없으면 확인이 아니다', () {
      final noActor = AttendancePolicyConfirmation.fromMap(const {
        'lateUnit': 30,
        'confirmedBy': '',
      });
      expect(noActor!.hasEvidence, isFalse);
      // 시각·행위자 둘 다 있어야 한다.
      // [R7-PAYROLL-POLICY.4A] 판정이 공용 helper 로 옮겨졌다 — 키 이름은
      //   호출자가 넘긴다(사업장은 confirmedAt/By, 지원서는 acknowledgedAt/By).
      final covers =
          _code(_slice(cfRaw, 'function srvPolicyEvidenceCovers(', '\n/**'));
      expect(covers.contains('e[atKey] == null'), isTrue);
      expect(covers.contains('typeof by !== "string" || by.length === 0'),
          isTrue);
      expect(block.contains('"confirmedAt", "confirmedBy"'), isTrue,
          reason: '사업장 확인의 키 이름이 그대로여야 한다');
    });

    test('OWN-9 서버가 출처를 바꾸지 않는다', () {
      // 기본값을 확인했다고 admin_selected 로 위조하지 않는다.
      expect(cfm.contains('admin_selected'), isFalse,
          reason: '확인 행위가 값의 출처를 바꾸지 않는다');
      expect(cfm.contains('attendanceRules.policySource'), isFalse);
      // 확인 CF 는 7개 숫자를 **쓰지 않는다** — 확인 기록만 쓴다.
      expect(cfm.contains('update({attendancePolicyConfirmation: confirmation})'),
          isTrue);
    });

    test('OWN-10 기준이 없으면 서버가 기본값을 만들어 주지 않는다', () {
      expect(cfm.contains('NO_ATTENDANCE_POLICY'), isTrue);
      expect(block.contains('return "NO_ATTENDANCE_POLICY"'), isTrue,
          reason: '없는 것을 기본값으로 채우면 ownership 증거가 다시 무너진다');
      // snapshot builder 도 규칙이 없으면 만들지 않는다(.3 계약 유지).
      final builder = _code(_slice(
          cfRaw, 'function srvBuildAttendancePolicySnapshot(', '\n/**'));
      expect(builder.contains('if (raw == null || typeof raw !== "object") return null;'),
          isTrue);
    });

    test('OWN-11 확인 권한은 수정 권한과 같다 — SubAdmin 제외', () {
      // firestore.rules 의 `isAdminOf` 와 같은 경계다.
      // [R7-PAYROLL-POLICY.4B] 경계가 공용 helper 로 빠졌고, 플랫폼 운영자도
      //   제외됐다 — 지원서 확인 writer 와 **같은 함수**를 쓴다.
      expect(cfm.contains('srvAssertBusinessPolicyActor('), isTrue);
      final actorGate = _code(
          _slice(cfRaw, 'function srvAssertBusinessPolicyActor(', '\n/**'));
      expect(actorGate.contains('adminIds.includes(callerUid)'), isTrue);
      expect(actorGate.contains('ownerId === callerUid'), isTrue);
      // assertBizAdmin 은 SubAdmin 까지 통과시키므로 쓰지 않는다.
      expect(cfm.contains('assertBizAdmin('), isFalse,
          reason: '기준을 수정할 수 없는 사람의 확인은 책임 근거가 되지 못한다');
      expect(cfm.contains('subAdmin'), isFalse);
    });

    test('OWN-12 확인 증거는 CF 전용이다', () {
      // update 차단 목록에 있다 — 슈퍼어드민 직접 쓰기도 막는 쪽이다.
      final deny = _slice(rules, "hasAny(['isApproved', 'approvedBy'", '&&');
      expect(deny.contains('attendancePolicyConfirmation'), isTrue);
      // create 로 심을 수도 없다.
      expect(
          rules.contains(
              "!request.resource.data.keys().hasAny(['attendancePolicyConfirmation'])"),
          isTrue,
          reason: '신규 사업장은 항상 미확인에서 시작한다');
      // 클라이언트 모델은 이 필드를 쓰지 않는다.
      final model = _code(_src('lib/models/core/business_model.dart'));
      expect(model.contains("'attendancePolicyConfirmation': "), isFalse,
          reason: 'toMap 에 넣으면 사업장 저장 batch 가 이 필드를 보내려 한다');
    });
  });

  group('gate — 새 약속은 확인된 기준에서만 만들어진다', () {
    test('GATE-1 공고 readiness 에 기준 확인이 들어 있다', () {
      final posting = _code(_slice(
          cfRaw, 'async function evaluatePostingReadinessFirestore(', '\n/**'));
      expect(posting.contains('return srvAttendancePolicyBlock(bizData);'),
          isTrue);
      // 계약 능력 판정을 건너뛰지 않는다 — 둘 다 본다.
      expect(posting.contains('await evaluateContractCapability('), isTrue);
    });

    test('GATE-2 확정이 미확인 기준을 거부한다', () {
      final confirm = _code(_callable(cfRaw, 'callableConfirmApplication'));
      // [R7-PAYROLL-POLICY.4A] 판정 대상이 **사업장 현재 기준**에서
      //   **이 지원서에 고정된 기준**으로 좁아졌다. 지키려던 계약은 그대로다 —
      //   확정은 확인된 기준에서만 일어난다. 더 강해졌을 뿐이다.
      expect(
          confirm.contains(
              'srvApplicationPolicyOwnership(fd, cfmBizSnap.data())'),
          isTrue,
          reason: '첫 공고 gate 만으로는 이미 열린 공고의 대기 지원서를 막지 못한다');
      // 트랜잭션 안에서 읽은 사업장 문서를 쓴다 — 확인과 commit 사이가 결정적이다.
      expect(confirm.contains('const cfmBizSnap = await tx.get(cfmBizRef);'),
          isTrue);
    });

    test('GATE-3 초대 발송도 거부한다', () {
      final invite = _code(_callable(cfRaw, 'callableInviteWorker'));
      expect(invite.contains('srvAssertAttendancePolicyConfirmed(invBizData)'),
          isTrue,
          reason: '보내고 나서 수락 단계에서 막으면 근로자가 이유를 알 수 없다');
    });

    test('GATE-4 초대 수락도 거부하되 설정 내부를 알리지 않는다', () {
      final accept = _code(_callable(cfRaw, 'callableAcceptTOInvitation'));
      // [R7-PAYROLL-POLICY.4A] 판정 대상이 사업장 현재 기준 → 이 초대에
      //   고정된 기준으로 바뀌었다. 초대를 보낸 행위가 그 기준의 확인이므로
      //   사업장이 그 뒤 기준을 바꿨다는 이유로 수락이 막히지 않는다.
      expect(
          accept.contains(
              'srvApplicationPolicyOwnership(freshData, invBizSnap.data())'),
          isTrue);
      // 근로자 문구는 기존 그대로 — 고용주 설정 내부를 노출하지 않는다.
      expect(accept.contains('지금은 수락할 수 없는 초대예요'), isTrue);
      expect(accept.contains('srvAssertAttendancePolicyConfirmed('), isFalse,
          reason: '그 helper 는 관리자 문구를 담고 있다');
    });

    test('GATE-5 이유 코드가 분리돼 있다', () {
      // 기준 없음과 미확인은 관리자가 할 일이 다르다.
      expect(cf.contains('NO_ATTENDANCE_POLICY:'), isTrue);
      expect(cf.contains('ATTENDANCE_POLICY_NOT_CONFIRMED:'), isTrue);
      expect(
          PostingNotReady.fromCode('NO_ATTENDANCE_POLICY')?.reason,
          PostingNotReadyReason.noAttendancePolicy);
      expect(
          PostingNotReady.fromCode('ATTENDANCE_POLICY_NOT_CONFIRMED')?.reason,
          PostingNotReadyReason.attendancePolicyNotConfirmed);
      // 모르는 코드를 특정 단계로 단정하지 않는다(기존 계약 유지).
      expect(PostingNotReady.fromCode('SOMETHING_NEW'), isNull);
      // 두 이유 모두 사업장 설정으로 보낸다 — 새 체크리스트 칸을 만들지 않는다.
      expect(
          const PostingNotReady(PostingNotReadyReason.noAttendancePolicy).task,
          FirstPostingTask.business);
      // 문구에 급여 영향이 드러난다.
      expect(
          const PostingNotReady(
                  PostingNotReadyReason.attendancePolicyNotConfirmed)
              .message
              .contains('급여'),
          isTrue);
    });

    test('GATE-6 기존 확정 근무는 gate 에 걸리지 않는다', () {
      final confirm = _code(_callable(cfRaw, 'callableConfirmApplication'));
      // 이미 CONFIRMED / CONTRACT_PENDING 은 gate 앞에서 돌아간다.
      final iAlready = confirm.indexOf('alreadyConfirmed = true;');
      final iRetry = confirm.indexOf('isContractPendingRetry = true;');
      final iGate = confirm.indexOf('srvApplicationPolicyOwnership(');
      expect(iGate, greaterThan(-1));
      expect(iAlready, greaterThan(-1));
      expect(iAlready, lessThan(iGate),
          reason: '기존 약속의 후속 처리가 막히면 출퇴근·계약·급여가 멈춘다');
      expect(iRetry, lessThan(iGate));
      // 출퇴근·급여 writer 에는 gate 가 없다.
      for (final name in [
        'callableCheckIn',
        'callableCheckOut',
        'callableConfirmFinalWage',
      ]) {
        final body = _code(_callable(cfRaw, name));
        expect(body.contains('srvAssertAttendancePolicyConfirmed('), isFalse,
            reason: '$name 이 막히면 이미 약속된 근무의 이행이 멈춘다');
        expect(body.contains('srvApplicationPolicyOwnership('), isFalse,
            reason: '$name 이 막히면 이미 약속된 근무의 이행이 멈춘다');
      }
    });
  });

  group('disclosure — 같은 근무는 같은 기준을 말한다', () {
    test('DISC-1 관리자 설정 이름에 급여가 드러난다', () {
      expect(form.contains("title: '근태 및 급여 처리 기준'"), isTrue);
      expect(form.contains("title: '근태 반올림 규칙'"), isFalse,
          reason: '운영 설정처럼 들리는 이름은 급여 영향을 숨긴다');
      final detail =
          _code(_src('lib/screens/business_admin/business_detail_screen.dart'));
      expect(detail.contains("title: '근태 및 급여 처리 기준'"), isTrue);
    });

    test('DISC-2 영향 예시는 실제 계산 helper 로 만든다', () {
      expect(form.contains('processCheckin('), isTrue);
      expect(form.contains('processCheckout('), isTrue);
      expect(form.contains('rules: _attendanceRules'), isTrue,
          reason: '하드코딩한 예시는 알고리즘과 갈라진다');

      // 예시가 실제 알고리즘과 1:1 인지 직접 확인한다.
      //   grace 이내는 정시, grace+1 은 지각 단위로 올림.
      const r = AttendanceRules(); // grace 5 / lateUnit 30
      final day = DateTime(2026, 1, 1);
      final start = contractStartAt(day, '09:00');
      final onTime = processCheckin(
          offsetMinutes: r.lateGrace, referenceAt: start, rules: r);
      expect(onTime.roundedAt, start, reason: '유예 이내는 예정 시각으로 인정된다');
      final late = processCheckin(
          offsetMinutes: r.lateGrace + 1, referenceAt: start, rules: r);
      expect(late.roundedAt, start.add(Duration(minutes: r.lateUnit)),
          reason: '유예 1분 초과가 30분 공제가 되는 것이 이 기준의 실제 효과다');
    });

    test('DISC-3 면책 문구를 쓰지 않는다', () {
      // 목적은 정책 확인이고 책임 전가가 아니다.
      for (final banned in [
        '모든 책임은 사업장',
        '법적으로 문제가 없',
        '책임을 지지 않습니다',
      ]) {
        expect(form.contains(banned), isFalse, reason: '면책 문구 금지: $banned');
      }
      // 사업장이 해야 할 일은 말한다.
      expect(form.contains('근로계약·취업규칙 및 관련 법령에 맞는 기준'), isTrue);
    });

    test('DISC-4 계약서는 Application snapshot 만 쓴다', () {
      final svc = _code(_src('lib/services/contract_service.dart'));
      expect(
          svc.contains(
              'attendancePolicy: application.attendancePolicySnapshot'),
          isTrue);
      // 계약 생성 경로가 사업장 현재 설정을 읽지 않는다.
      expect(svc.contains('attendanceRules'), isFalse,
          reason: 'live 설정을 읽으면 계약서와 실제 계산이 다른 기준을 말한다');
    });

    test('DISC-5 화면과 PDF 가 같은 것을 말한다', () {
      final sign = _code(_src('lib/screens/contract/contract_sign_screen.dart'));
      final pdf = _code(_src('lib/screens/contract/contract_pdf_builder.dart'));
      // [R7-PAYROLL-POLICY.4B] 라벨이 **공용 formatter** 로 빠졌다. 지키려던
      //   것은 둘이 같은 것을 말한다는 것이고, 이제 같은 목록을 쓰므로
      //   한쪽만 달라질 수 없다. 항목 자체는 그 formatter 쪽에서 고정한다.
      for (final body in [sign, pdf]) {
        expect(body.contains('snapshot.attendancePolicy case final policy?'),
            isTrue, reason: '없는 값을 기본값으로 채워 계약 내용으로 만들지 않는다');
        expect(body.contains('attendancePolicyLines(policy)'), isTrue);
      }
      for (final label in ['지각 유예', '지각 처리', '조퇴 처리', '연장 인정']) {
        expect(
            _src('lib/utils/attendance_policy_disclosure.dart').contains(label),
            isTrue, reason: '$label 누락');
      }
    });

    test('DISC-6 근로자 공고 상세에 기준 접근이 있다', () {
      final posting = _code(_src('lib/screens/common/job_posting_screen.dart'));
      expect(posting.contains('_buildAttendancePolicyDisclosure('), isTrue);
      expect(posting.contains('_business!.attendanceRules'), isTrue,
          reason: '이미 불러온 사업장 문서를 쓴다 — 새 읽기를 만들지 않는다');
      // 지원 확인에도 같은 사실을 말한다.
      final confirmSheet =
          _code(_src('lib/widgets/dialogs/apply/apply_confirm_dialog.dart'));
      // [R7-PAYROLL-POLICY.4C] 안내 문구에서 **실제 7항목 표시**로 바뀌었다.
      //   이 시트는 공고 상세를 거치지 않는 경로에서도 열리므로, 상세로
      //   보내는 대신 여기서 보여준다. 계약은 더 강해졌다.
      expect(confirmSheet.contains('kAttendancePolicyTitle'), isTrue);
      expect(confirmSheet.contains('attendancePolicyGroups(r)'), isTrue);
      expect(confirmSheet.contains('지원하면 이 기준이 이 지원서에 고정됩니다'),
          isTrue);
    });

    test('DISC-7 관리자 근태 화면이 live 정책으로 미리보기하지 않는다', () {
      final dlg = _code(_src(
          'lib/screens/business_admin/dialogs/attendance_status_dialog.dart'));
      // 반올림 미리보기가 **이 근무의 약속**을 쓴다. 이 화면이 계산한 값이
      //   그대로 보정 요청으로 전송되므로 기준이 틀리면 금액이 틀린다.
      // 출근·퇴근 **둘 다** 같은 출처를 쓴다. 대입 형태까지 고정한다 —
      //   호출만 남기고 값을 live 로 바꾸는 변형이 `.3` 에서 실제로 빠져나갔다.
      expect(
          'final rules = app.effectiveAttendanceRules(_attendanceRules);'
              .allMatches(dlg)
              .length,
          2,
          reason: '출근·퇴근 둘 다 같은 출처를 써야 한다');
      // 대상자별 기준이 다를 수 있다는 사실도 같은 술어로 판정한다.
      expect(dlg.contains('bool _batchTargetsHaveMixedPolicy('), isTrue);
      expect(dlg.contains('final rules = _attendanceRules;'), isFalse,
          reason: '사업장 현재 설정으로 미리보기하면 서버 결과와 달라진다');
      expect(dlg.contains("'사업장 반올림 정책 적용'"), isFalse,
          reason: '확정 뒤 설정을 바꾼 사업장에서 틀린 말이 된다');
    });
  });

  group('변형 방어', () {
    test('MUT-0 조건을 무력화하는 형태를 막는다', () {
      // `if (false && <원래 조건>)` 은 부분 문자열 고정을 통과한다.
      expect(cf.contains('if (false'), isFalse);
      expect(form.contains('if (false'), isFalse);
      // gate 를 상수로 꺾는 형태도 막는다.
      expect(cf.contains('srvAttendancePolicyBlock(bizData) && false'), isFalse);
      expect(cf.contains('return null; // ATTENDANCE'), isFalse);
    });

    test('MUT-1 확인 판정이 항상 통과하도록 바뀌지 않았다', () {
      final block =
          _code(_slice(cfRaw, 'function srvAttendancePolicyBlock(', '\n/**'));
      // [R7-PAYROLL-POLICY.4A] 세 갈래 반복이 공용 비교 helper 로 접혀
      //   거부 경로가 하나로 모였다. 지키려던 것은 **fail-closed** 다 —
      //   통과는 확인 기록이 값을 덮을 때 **한 번만** 일어난다.
      expect('return "ATTENDANCE_POLICY_NOT_CONFIRMED"'.allMatches(block).length,
          1);
      expect('return "NO_ATTENDANCE_POLICY"'.allMatches(block).length, 1);
      expect('return null;'.allMatches(block).length, 1,
          reason: '통과 경로가 둘이 되면 어느 쪽으로 열렸는지 알 수 없다');
      expect(
          block.trimRight().endsWith(
              'return "ATTENDANCE_POLICY_NOT_CONFIRMED";\n}'),
          isTrue, reason: '마지막은 거부여야 한다 (fail-closed)');
      expect(block.contains('if (srvPolicyEvidenceCovers('), isTrue,
          reason: '통과는 확인 기록이 값을 덮을 때만이다');
    });

    test('MUT-2 저장만으로 확인되지 않는다', () {
      // 값이 바뀌거나 명시적 확인이 있을 때만 CF 를 부른다.
      expect(form.contains('if (!policyChanged && !_confirmPolicyNow) return;'),
          isTrue);
      expect(form.contains("httpsCallable('callableConfirmAttendancePolicy')"),
          isTrue);
      // 클라이언트가 확인 필드를 직접 **쓰지** 않는다(읽기는 표시용으로 한다).
      expect(form.contains("'attendancePolicyConfirmation'"), isFalse,
          reason: '사업장 저장 맵에 들어가면 rules 가 전체 저장을 거부한다');
    });
  });
}
