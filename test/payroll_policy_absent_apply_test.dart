// [R7-PAYROLL-POLICY.4D] 기준 자체가 없는데 지원이 됐다
//
// ── 문제 ────────────────────────────────────────────────────────────
//   `.4C` 는 "근로자가 본 기준" 과 "지금 기준" 이 같은지만 봤다. 그래서 둘 다
//   없는 경우가 통과했다:
//
//     policy 없음 → client token "absent"
//     policy 없음 → server token "absent"
//     "absent" == "absent" → 지원 성공, snapshot 없음
//
//   근로자가 확인한 임금조건이 **없는 상태로** 지원서가 생긴다. 그 지원서를
//   나중에 확정하면, 지원 당시 볼 수 없었던 숫자가 약속에 들어간다.
//
// ── 세 상태를 나눈다 ────────────────────────────────────────────────
//   A. 기준 있음 + 사업장 확인됨   → 정상 지원
//   B. 기준 있음 + 사업장 미확인   → **지원 허용**(`.4A` 의 의도된 정책)
//                                   확정 전에 그 기준의 확인이 필요하다
//   C. 기준 없음                   → 신규 지원 금지
//
//   B 를 함께 막으면 `.4A` 가 일부러 열어 둔 경로를 깨뜨린다 — 그래서 B 는
//   positive control 로 고정한다.
//
// 반올림 산술은 **한 줄도 바꾸지 않았다.**
//
// 고정하는 것
//   ABS-1  canonical 판정은 **원값**만 본다 (부분 정책 ≠ 완전한 정책)
//   ABS-2  서버가 기본값을 생성하지 않는다
//   ABS-3  신규 지원이 기준 없음에서 fail closed
//   ABS-4  판정이 멱등 guard 뒤 · 쓰기 앞 (side effect 0)
//   ABS-5  "absent == absent" 가 성공 경로가 아니다
//   ABS-6  기준 있음 + 미확인은 **막지 않는다** (positive control)
//   TAX-1  세 reason 이 분리돼 있다
//   TAX-2  판정 순서: 기준 없음 → 미고지 → 변경
//   UX-5   근로자 문구가 근로자 잘못·영구 거부로 읽히지 않는다
//   UX-6   ERROR 와 ABSENT 를 구별한다
//   UX-7   자동 재지원·자동 재조회가 없다
//   UX-8   클라이언트 차단만으로 무결성을 삼지 않는다
//   LEG-1  기존 snapshot 없는 지원서를 건드리지 않는다
//   MUT-6  변형 방어
import 'dart:io';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/services/firestore_service.dart'
    show ApplyOutcome, ApplyResult;
import 'package:ALfit/utils/attendance_policy_disclosure.dart';
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
  final apply = _code(_callable(cfRaw, 'callableApplyToTO'));
  final predicate = _code(_slice(
      cfRaw, 'function srvHasCanonicalAttendancePolicy(', '\n/**'));

  group('canonical 판정 — 부분 정책은 완전한 정책이 아니다', () {
    test('ABS-1 원값만 본다', () {
      // 7개가 전부 숫자로 **저장돼** 있어야 한다.
      expect(predicate.contains('for (const k of ATTENDANCE_POLICY_MATERIAL_FIELDS)'),
          isTrue);
      expect(predicate.contains('if (typeof r[k] !== "number") return false;'),
          isTrue);
      // 기본값을 메우는 helper 를 쓰지 않는다 — 그걸 쓰면 부분 정책이
      //   완전한 정책으로 보인다.
      expect(predicate.contains('srvAttendancePolicyValue'), isFalse,
          reason: '메워서 만든 값으로 판정하면 근로자가 못 본 숫자가 약속에 들어간다');
      expect(predicate.contains('ATTENDANCE_POLICY_DEFAULTS'), isFalse);
      // 객체 자체가 없으면 당연히 없다.
      expect(
          predicate.contains(
              'if (rules == null || typeof rules !== "object") return false;'),
          isTrue);
    });

    test('ABS-2 서버가 기본값을 생성하지 않는다', () {
      // 지원 경로에 `AttendanceRules.defaults()` 상당의 생성이 없다.
      expect(apply.contains('ATTENDANCE_POLICY_DEFAULTS'), isFalse);
      // snapshot builder 는 규칙이 없으면 여전히 null 을 돌려준다(.3 계약).
      final builder = _code(_slice(
          cfRaw, 'function srvBuildAttendancePolicySnapshot(', '\n/**'));
      expect(
          builder.contains(
              'if (raw == null || typeof raw !== "object") return null;'),
          isTrue);
    });

    test('ABS-5 "absent == absent" 가 성공 경로가 아니다', () {
      // fingerprint 는 여전히 'absent' 를 돌려준다(진단·표시용).
      final fp = _code(
          _slice(cfRaw, 'function srvAttendancePolicyFingerprint(', '\n/**'));
      expect(fp.contains('return "absent"'), isTrue);
      // 그런데 그 비교 **앞**에 canonical 판정이 있어 통과하지 못한다.
      final iPred = apply.indexOf('srvHasCanonicalAttendancePolicy(applyTxRules)');
      final iFp = apply.indexOf('srvAttendancePolicyFingerprint(applyTxRules)');
      expect(iPred, greaterThan(-1));
      expect(iFp, greaterThan(-1));
      expect(iPred, lessThan(iFp),
          reason: 'fingerprint 비교가 먼저면 absent==absent 가 통과한다');
      // 클라이언트도 null 을 지원 가능 상태로 보지 않는다.
      expect(canApplyWithAttendancePolicy(null), isFalse);
      expect(canApplyWithAttendancePolicy(const AttendanceRules()), isTrue);
    });
  });

  group('direct apply gate', () {
    test('ABS-3 기준 없음에서 fail closed', () {
      expect(apply.contains('if (!srvHasCanonicalAttendancePolicy(applyTxRules)) {'),
          isTrue);
      expect(apply.contains('{reason: "ATTENDANCE_POLICY_UNAVAILABLE"}'), isTrue);
      // 판정 대상은 **트랜잭션 안에서 읽은** 값이다.
      expect(
          apply.contains(
              'const applyTxRules = applyTxBizSnap.data()?.["attendanceRules"];'),
          isTrue);
    });

    test('ABS-4 멱등 guard 뒤 · 쓰기 앞', () {
      final iExisting =
          apply.indexOf('const existingInTx = await tx.get(appRef);');
      final iAlready = apply.indexOf('"이미 지원한 업무입니다."');
      final iPred = apply.indexOf('if (!srvHasCanonicalAttendancePolicy(');
      expect(iExisting, greaterThan(-1));
      expect(iAlready, lessThan(iPred),
          reason: '기존 성공이 있는데 기준이 지워졌다고 거짓 실패시키면 안 된다');
      // 쓰기·알림은 모두 판정 뒤다 → side effect 0.
      for (final w in [
        'tx.set(appRef, setData)',
        'tx.update(appRef, reactivateData)',
        'tx.update(toRef, {totalPending',
        '[applyToTO] 알림 발송 시작',
      ]) {
        final iW = apply.indexOf(w);
        expect(iW, greaterThan(-1), reason: '$w 를 찾지 못했다');
        expect(iPred, lessThan(iW), reason: '$w 가 판정보다 앞이면 부분 성공이 생긴다');
      }
    });

    test('ABS-6 기준 있음 + 미확인은 막지 않는다 (positive control)', () {
      // `.4A` 가 일부러 열어 둔 경로다 — 지원은 관심이고, 그 기준의 확인은
      //   **확정 전에** 요구된다. 이 Phase 가 그것을 깨지 않는다.
      expect(apply.contains('attendancePolicyConfirmation'), isFalse,
          reason: '지원 경로가 사업장 확인 여부를 보면 .4A 정책이 깨진다');
      expect(apply.contains('srvAttendancePolicyBlock('), isFalse);
      expect(apply.contains('srvApplicationPolicyOwnership('), isFalse);
      expect(apply.contains('srvAssertAttendancePolicyConfirmed('), isFalse);
      // 확인 요구는 확정 writer 에 그대로 있다.
      final confirm = _code(_callable(cfRaw, 'callableConfirmApplication'));
      expect(confirm.contains('srvApplicationPolicyOwnership(fd, cfmBizSnap.data())'),
          isTrue);
    });
  });

  group('reason taxonomy', () {
    test('TAX-1 세 reason 이 분리돼 있다', () {
      for (final r in [
        'ATTENDANCE_POLICY_UNAVAILABLE',
        'ATTENDANCE_POLICY_NOT_DISCLOSED',
        'ATTENDANCE_POLICY_CHANGED',
      ]) {
        expect(apply.contains('{reason: "$r"}'), isTrue, reason: '$r 누락');
      }
      // 클라이언트도 세 상태를 합치지 않는다.
      final af =
          _code(_src('lib/services/firestore/application_firestore.dart'));
      expect(af.contains("reason == 'ATTENDANCE_POLICY_UNAVAILABLE'"), isTrue);
      expect(af.contains('ApplyResult.policyUnavailable('), isTrue);
      final r = ApplyResult.policyUnavailable('x',
          code: 'ATTENDANCE_POLICY_UNAVAILABLE');
      expect(r.outcome, ApplyOutcome.policyUnavailable);
      expect(r.isPolicyUnavailable, isTrue);
      expect(r.isPolicyChanged, isFalse, reason: '바뀐 것이 아니라 없는 것이다');
      expect(r.isApplied, isFalse);
      expect(r.isUnknown, isFalse);
    });

    test('TAX-2 판정 순서: 없음 → 미고지 → 변경', () {
      final iUnavail = apply.indexOf('ATTENDANCE_POLICY_UNAVAILABLE');
      final iNotDisc = apply.indexOf('ATTENDANCE_POLICY_NOT_DISCLOSED');
      final iChanged = apply.indexOf('ATTENDANCE_POLICY_CHANGED');
      expect(iUnavail, lessThan(iNotDisc),
          reason: '사업장에 기준이 없으면 클라이언트 토큰을 따질 일이 아니다');
      expect(iNotDisc, lessThan(iChanged));
    });
  });

  group('worker UX', () {
    final dlg = _code(_src('lib/widgets/dialogs/apply/apply_work_dialog.dart'));
    final confirmSheet =
        _code(_src('lib/widgets/dialogs/apply/apply_confirm_dialog.dart'));

    test('UX-5 근로자 잘못·영구 거부로 읽히지 않는다', () {
      // 근로자는 기준을 입력할 수 없다.
      for (final banned in ['입력해 주세요', '입력해주세요', '등록해 주세요']) {
        expect(kAttendancePolicyUnavailableNote.contains(banned), isFalse,
            reason: '근로자가 할 수 없는 일을 시킨다: $banned');
      }
      // 영구 거부가 아니라 준비 중이다.
      expect(kAttendancePolicyUnavailableNote.contains('준비'), isTrue);
      expect(kAttendancePolicyUnavailableNote.contains('지원할 수 없습니다'), isFalse);
      // 법률 경고가 아니다.
      for (final banned in ['위반', '법적', '책임']) {
        expect(kAttendancePolicyUnavailableNote.contains(banned), isFalse);
      }
    });

    test('UX-6 ERROR 와 ABSENT 를 구별한다', () {
      expect(kAttendancePolicyLoadFailedNote.contains('확인하지 못했'), isTrue);
      expect(kAttendancePolicyLoadFailedNote ==
          kAttendancePolicyUnavailableNote, isFalse);
      // 확인 화면이 둘을 나눠 말한다.
      expect(
          confirmSheet.contains('policyLoaded\n'
              '          ? kAttendancePolicyUnavailableNote\n'
              '          : kAttendancePolicyLoadFailedNote'),
          isTrue,
          reason: '읽기 실패를 기준 없음으로 위조하지 않는다');
      // 지원 직전 차단도 두 상태를 나눈다.
      expect(dlg.contains('if (!_policyLoaded) {'), isTrue);
      expect(dlg.contains('ToastHelper.showWarning(kAttendancePolicyLoadFailedNote)'),
          isTrue);
      expect(dlg.contains('if (!canApplyWithAttendancePolicy(_policyRules)) {'),
          isTrue);
    });

    test('UX-7 자동 재지원·자동 재조회가 없다', () {
      // 그 분기 **안**만 본다 — 다음 `else if` 까지 자른다. 창을 넓게 잡으면
      //   옆 분기(기준 변경)의 재조회를 잘못 잡는다.
      final i = dlg.indexOf('applied.isPolicyUnavailable');
      expect(i, greaterThan(-1));
      final j = dlg.indexOf('} else if', i);
      expect(j, greaterThan(i));
      final branch = dlg.substring(i, j);
      expect(branch.contains('_submit.apply('), isFalse);
      expect(branch.contains('_loadPolicyRules()'), isFalse,
          reason: '다시 읽어도 해결되지 않는다 — 사업장이 기준을 저장해야 한다');
      // 안내는 한다.
      expect(
          branch.contains(
              'ToastHelper.showWarning(kAttendancePolicyUnavailableNote)'),
          isTrue);
      // 장기 지원 경로도 같다.
      final lt =
          _code(_src('lib/widgets/dialogs/apply/longterm_apply_sheet.dart'));
      expect(lt.contains('if (result.isPolicyUnavailable) anyPolicyUnavailable = true;'),
          isTrue);
      expect(lt.contains('ToastHelper.showWarning(kAttendancePolicyUnavailableNote)'),
          isTrue);
      // 공고 화면이 기준 없음을 "변경" 으로 다루지 않는다 — 재조회 분기는
      //   policyChanged 전용이다.
      final posting = _code(_src('lib/screens/common/job_posting_screen.dart'));
      expect(posting.contains('policyUnavailable'), isFalse);
    });

    test('UX-8 클라이언트 차단만으로 무결성을 삼지 않는다', () {
      // 화면이 막아도 서버 gate 가 canonical 이다.
      expect(apply.contains('srvHasCanonicalAttendancePolicy('), isTrue);
      // 다건 지원은 건별 결과를 그대로 보여준다 — 서버 문구가 설명한다.
      final multi =
          _code(_src('lib/widgets/dialogs/apply/multi_apply_confirm_sheet.dart'));
      expect(multi.contains('meta.applyError = result.isApplied ? null : result.message;'),
          isTrue);
      // 기준 없음을 "변경" 으로 세지 않는다.
      expect(multi.contains('if (result.isPolicyChanged) policyChangedCount++;'),
          isTrue);
      expect(multi.contains('isPolicyUnavailable) policyChangedCount++'), isFalse);
    });
  });

  group('legacy 경계', () {
    test('LEG-1 기존 snapshot 없는 지원서를 건드리지 않는다', () {
      // 이 Phase 는 **새 지원서**만 막는다. backfill·migration 없음.
      expect(cf.contains('backfillAttendancePolicySnapshot'), isFalse);
      expect(cf.contains('migrateAttendancePolicy'), isFalse);
      // 확정 시 legacy 채움은 `.3` 계약 그대로 남아 있다(지우지 않았다).
      final confirm = _code(_callable(cfRaw, 'callableConfirmApplication'));
      expect(confirm.contains('if (fd["attendancePolicySnapshot"] == null) {'),
          isTrue);
      // 계산 경로의 legacy 폴백도 그대로다.
      final resolver = _code(_slice(
          cfRaw, 'function srvEffectiveAttendanceRules(', '\n/**'));
      expect(resolver.contains('attendanceRules'), isTrue);
    });
  });

  group('변형 방어', () {
    test('MUT-6 조건을 무력화하는 형태를 막는다', () {
      expect(cf.contains('if (false'), isFalse);
      // 판정이 상수로 꺾이지 않았다.
      //
      //   끝이 `return true;` 라는 것만으로는 부족하다 — 앞에 `return true;`
      //   를 하나 더 넣으면 뒤 문장이 죽은 코드로 남아 그 고정을 통과한다
      //   (실측: 변형 M7 이 그렇게 빠져나갔다). 그래서 **통과가 7개 확인
      //   뒤에 한 번만** 있다는 것을 위치로 고정한다.
      expect('return true;'.allMatches(predicate).length, 1,
          reason: '통과 경로가 둘이면 어느 쪽으로 열렸는지 알 수 없다');
      final iObj = predicate.indexOf('typeof rules !== "object"');
      final iFor = predicate.indexOf('for (const k of');
      final iTrue = predicate.indexOf('return true;');
      expect(iObj, greaterThan(-1));
      expect(iFor, greaterThan(iObj));
      expect(iTrue, greaterThan(iFor),
          reason: '7개를 확인하기 전에 통과하면 부분·없음 정책이 그대로 통과한다');
      expect(predicate.trimRight().endsWith('return true;\n}'), isTrue,
          reason: '통과는 마지막 한 줄이어야 한다');
      expect('return false;'.allMatches(predicate).length, 2,
          reason: '객체 없음·항목 없음 두 거부가 모두 살아 있어야 한다');
      // 반올림 산술 변경 0.
      final ci = _code(_slice(cfRaw, 'function _processCheckin(', '\n/**'));
      expect(ci.contains('Math.ceil(offsetMinutes / lateUnit) * lateUnit'),
          isTrue);
      expect(ci.contains('Math.trunc(offsetMinutes / earlyArrivalUnit)'), isTrue);
      final co = _code(_slice(cfRaw, 'function _processCheckout(', '\n/**'));
      expect(
          co.contains('Math.floor(offsetMinutes / overtimeUnit) * overtimeUnit'),
          isTrue);
      expect(co.contains('Math.ceil(earlyDiff / earlyLeaveUnit)'), isTrue);
    });
  });
}
