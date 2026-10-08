// [R7-PAYROLL-POLICY.4C] 근로자가 본 급여조건과 저장되는 급여조건
//
// ── 문제 ────────────────────────────────────────────────────────────
//   T0 근로자가 공고 상세에서 기준 A 를 본다
//   T1 사업장이 B 로 바꾼다
//   T2 근로자가 지원 버튼을 누른다
//   T3 서버가 fresh 로 읽어 **B 를 지원서에 고정한다**
//
//   확인한 조건과 저장된 조건이 달라진다. 지원 = 관심이지만, 그 관심의
//   **임금 산정 조건**은 이미 그 순간 지원서에 박힌다.
//
// ── 닫는 방법 ───────────────────────────────────────────────────────
//   클라이언트가 "내가 본 기준" 토큰을 함께 보내고, 서버가 **commit 시점**
//   canonical 값과 비교한다. 다르면 지원을 만들지 않는다.
//
//   토큰은 **stale 탐지 입력일 뿐**이다. 저장되는 snapshot 은 언제나 서버가
//   읽은 사업장 문서에서 만든다 — 클라이언트가 보낸 숫자가 약속이 되지 않는다.
//
// 반올림 산술은 **한 줄도 바꾸지 않았다.**
//
// 고정하는 것
//   TX-1  비교와 snapshot 이 **같은 트랜잭션 읽기**에서 나온다
//   TX-2  비교가 중복/멱등 guard **뒤**다 (기존 성공을 덮지 않는다)
//   TX-3  mismatch 는 쓰기 전에 throw 한다 (side effect 0)
//   TX-4  클라이언트 값이 snapshot 출처가 되지 않는다
//   FP-1  7개 각각이 토큰을 바꾼다
//   FP-2  metadata 변경은 토큰을 바꾸지 않는다
//   FP-3  서버·클라이언트 7-field parity (같은 필드·순서·형식)
//   FP-4  기준 없음은 기본값 토큰이 아니다
//   ENTRY 네 지원 entry 전부 토큰을 보낸다
//   UX-1  policyChanged 는 failed·unknown 과 다른 상태다
//   UX-2  자동 재지원이 없다
//   UX-3  안내는 상태 변경이지 법률 경고가 아니다
//   UX-4  최신 기준은 기존 reader 로 다시 읽는다
//   MULTI 이미 성공한 건을 실패로 바꾸지 않는다
//   MUT-5 변형 방어
import 'dart:io';

import 'package:ALfit/models/core/business_model.dart';
// `application_firestore.dart` 는 `part of firestore_service.dart` 다 —
//   직접 import 할 수 없으므로 소유 라이브러리를 쓴다.
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

  group('트랜잭션 경계 — 비교한 값이 저장된 값이다', () {
    test('TX-1 비교와 snapshot 이 같은 트랜잭션 읽기에서 나온다', () {
      // 트랜잭션 **안**에서 사업장을 읽는다 → read-set 에 들어가므로
      //   비교와 commit 사이에 기준이 바뀌면 Firestore 가 재시도한다.
      expect(
          apply.contains('const applyTxBizSnap =\n'
              '        await tx.get(db.collection("businesses").doc(businessId));'),
          isTrue);
      // 비교도, 저장할 snapshot 도 **그 읽기**에서 만든다.
      expect(
          apply.contains(
              'srvAttendancePolicyFingerprint(applyTxBizSnap.data()?.["attendanceRules"])'),
          isTrue);
      expect(
          apply.contains(
              'srvBuildAttendancePolicySnapshot(applyTxBizSnap.data())'),
          isTrue);
      // 트랜잭션 **밖** 읽기로 만든 snapshot 은 더 쓰지 않는다.
      expect(apply.contains('applyPolicySnapshot'), isFalse,
          reason: '밖에서 만들면 비교 통과 뒤 commit 사이에 바뀐 값이 저장된다');
      expect(
          apply.contains(
              'srvBuildAttendancePolicySnapshot(applyBizSnap.data())'),
          isFalse);
    });

    test('TX-2 비교가 중복·멱등 guard 뒤다', () {
      // 첫 요청이 성공하고 응답만 유실된 뒤 사업장이 기준을 바꿨다면,
      //   재시도는 "이미 지원함" 으로 끝나야 한다. 비교를 먼저 하면
      //   실제로는 지원된 상태인데 기준 변경이라고 말한다.
      final iExisting = apply.indexOf('const existingInTx = await tx.get(appRef);');
      final iAlready = apply.indexOf('"이미 지원한 업무입니다."');
      final iInvited = apply.indexOf('"이미 초대를 받은 근무입니다');
      final iCompare = apply.indexOf('const applyTxBizSnap =');
      for (final i in [iExisting, iAlready, iInvited, iCompare]) {
        expect(i, greaterThan(-1));
      }
      expect(iExisting, lessThan(iCompare),
          reason: '멱등 확인이 비교보다 앞이어야 기존 성공이 보존된다');
      expect(iAlready, lessThan(iCompare));
      expect(iInvited, lessThan(iCompare));
    });

    test('TX-3 mismatch 는 쓰기 전에 throw 한다', () {
      final iCompare = apply.indexOf('expectedAttendancePolicy !== applyFreshFp');
      expect(iCompare, greaterThan(-1));
      // 비교 뒤에야 쓰기가 나온다 — 지원서·카운터·알림 어느 것도 앞서지 않는다.
      for (final w in [
        'tx.set(appRef, setData)',
        'tx.update(appRef, reactivateData)',
        'tx.update(toRef, {totalPending',
      ]) {
        final iW = apply.indexOf(w);
        expect(iW, greaterThan(-1), reason: '$w 를 찾지 못했다');
        expect(iCompare, lessThan(iW), reason: '$w 가 비교보다 앞이면 부분 성공이 생긴다');
      }
      // 알림은 트랜잭션 **뒤**에 있으므로 throw 하면 도달하지 않는다.
      final iNotif = apply.indexOf('[applyToTO] 알림 발송 시작');
      expect(iNotif, greaterThan(-1));
      expect(iCompare, lessThan(iNotif));
      // 두 거부 모두 명시적 reason 을 싣는다.
      expect(apply.contains('{reason: "ATTENDANCE_POLICY_CHANGED"}'), isTrue);
      expect(apply.contains('{reason: "ATTENDANCE_POLICY_NOT_DISCLOSED"}'),
          isTrue, reason: '기준을 보여주지 않은 경로도 fail closed 여야 한다');
    });

    test('TX-4 클라이언트 값이 snapshot 출처가 되지 않는다', () {
      // payload 에 정책 **값**이 들어올 자리가 없다 — 토큰 문자열 하나뿐이다.
      final destructure = _slice(apply, 'const data = request.data as {', '};');
      expect(destructure.contains('expectedAttendancePolicy?: string;'), isTrue);
      expect(destructure.contains('attendanceRules'), isFalse);
      expect(destructure.contains('attendancePolicySnapshot'), isFalse);
      // 토큰은 비교에만 쓰인다 — 저장 payload 에 들어가지 않는다.
      expect(apply.contains('attendancePolicySnapshot: expectedAttendancePolicy'),
          isFalse);
      expect(apply.contains('attendancePolicySnapshot: applyTxPolicy'), isTrue);
    });
  });

  group('fingerprint — 무엇을 비교하는가', () {
    const base = AttendanceRules();

    test('FP-1 7개 각각이 토큰을 바꾼다', () {
      final baseFp = attendancePolicyFingerprint(base);
      final variants = <String, AttendanceRules>{
        'earlyWindow': base.copyWith(earlyWindow: 45),
        'earlyArrivalUnit': base.copyWith(earlyArrivalUnit: 15),
        'lateGrace': base.copyWith(lateGrace: 9),
        'lateUnit': base.copyWith(lateUnit: 15),
        'lateWindow': base.copyWith(lateWindow: 45),
        'overtimeUnit': base.copyWith(overtimeUnit: 25),
        'earlyLeaveUnit': base.copyWith(earlyLeaveUnit: 15),
      };
      variants.forEach((k, v) {
        expect(attendancePolicyFingerprint(v) == baseFp, isFalse,
            reason: '$k 변경이 토큰에 반영되지 않는다 — 그 변경은 아무도 못 잡는다');
      });
    });

    test('FP-2 metadata 변경은 토큰을 바꾸지 않는다', () {
      // 급여에 영향하는 7개 숫자가 같으면 근로자에게 같은 조건이다.
      //   출처·감사 필드가 바뀌었다고 지원이 깨지면, 아무 변화도 없는 일로
      //   재지원을 요구하게 된다.
      final baseFp = attendancePolicyFingerprint(base);
      expect(
          attendancePolicyFingerprint(base.copyWith(
              policySource: AttendanceRules.sourceAdminSelected)),
          baseFp);
      expect(
          attendancePolicyFingerprint(
              base.copyWith(rulesUpdatedBy: 'someone')),
          baseFp);
      expect(
          attendancePolicyFingerprint(
              base.copyWith(rulesUpdatedAt: DateTime(2026, 10, 9))),
          baseFp);
      // 서버도 7개만 본다.
      final fp = _code(
          _slice(cfRaw, 'function srvAttendancePolicyFingerprint(', '\n/**'));
      expect(fp.contains('ATTENDANCE_POLICY_MATERIAL_FIELDS'), isTrue);
      expect(fp.contains('policySource'), isFalse);
      expect(fp.contains('attendancePolicyConfirmation'), isFalse);
      expect(fp.contains('rulesUpdated'), isFalse);
    });

    test('FP-3 서버·클라이언트 7-field parity', () {
      // 서버 소스의 **필드 목록 선언**에서 기대 문자열을 만든다.
      //   한쪽이 항목을 빼거나 순서를 바꾸면 여기서 깨진다.
      final decl = _slice(
          cfRaw, 'const ATTENDANCE_POLICY_MATERIAL_FIELDS = [', '] as const;');
      final fields = RegExp('"([a-zA-Z]+)"')
          .allMatches(decl)
          .map((m) => m.group(1)!)
          .toList();
      expect(fields.length, 7, reason: '서버 목록이 7개가 아니다');
      final values = <String, int>{
        'earlyWindow': base.earlyWindow,
        'earlyArrivalUnit': base.earlyArrivalUnit,
        'lateGrace': base.lateGrace,
        'lateUnit': base.lateUnit,
        'lateWindow': base.lateWindow,
        'overtimeUnit': base.overtimeUnit,
        'earlyLeaveUnit': base.earlyLeaveUnit,
      };
      final expected =
          fields.map((f) => '$f=${values[f]}').join('|');
      expect(attendancePolicyFingerprint(base), expected,
          reason: '서버 목록·순서와 클라이언트 토큰 형식이 어긋났다');
      // 서버 형식도 같은 모양이다.
      final fp = _code(
          _slice(cfRaw, 'function srvAttendancePolicyFingerprint(', '\n/**'));
      expect(fp.contains(r'`${k}=${srvAttendancePolicyValue(r, k)}`'), isTrue);
      expect(fp.contains('.join("|")'), isTrue);
    });

    test('FP-4 기준 없음은 기본값 토큰이 아니다', () {
      expect(attendancePolicyFingerprint(null), 'absent');
      // 기본값 규칙의 토큰과 **달라야** 한다 — 모름을 기본값으로 읽지 않는다.
      expect(attendancePolicyFingerprint(null) ==
          attendancePolicyFingerprint(base), isFalse);
      final fp = _code(
          _slice(cfRaw, 'function srvAttendancePolicyFingerprint(', '\n/**'));
      expect(fp.contains('return "absent"'), isTrue);
    });
  });

  group('entry — 모든 직접 지원 경로가 토큰을 보낸다', () {
    test('ENTRY 네 경로 전부', () {
      // ① 카드 → 지원 시트
      final dlg = _code(_src('lib/widgets/dialogs/apply/apply_work_dialog.dart'));
      expect(dlg.contains('expectedAttendancePolicy:'), isTrue);
      expect(dlg.contains('attendancePolicyFingerprint(_policyRules)'), isTrue);
      // 이 경로는 공고 상세를 거치지 않으므로 **스스로** 기준을 읽어 보여준다.
      expect(dlg.contains('_reads.businessForPolicy('), isTrue);
      expect(dlg.contains('policyRules: _policyRules'), isTrue);

      // ② 공고 상세 → 다건 지원
      final multi =
          _code(_src('lib/widgets/dialogs/apply/multi_apply_confirm_sheet.dart'));
      expect(
          multi.contains('attendancePolicyFingerprint(widget.policyRules)'),
          isTrue);

      // ③ 공고 상세 → 장기 지원
      final lt =
          _code(_src('lib/widgets/dialogs/apply/longterm_apply_sheet.dart'));
      expect(lt.contains('attendancePolicyFingerprint(widget.policyRules)'),
          isTrue);

      // ②③ 둘 다 공고 화면이 **보여준 그 값**을 받는다 — 새로 읽지 않는다.
      final posting = _code(_src('lib/screens/common/job_posting_screen.dart'));
      expect('policyRules: _business?.attendanceRules'
              .allMatches(posting)
              .length,
          2);

      // ④ 서비스 경계가 토큰을 **필수**로 요구한다 — 빠뜨린 경로는 컴파일되지
      //    않는다. 이것이 entry coverage 의 실질적 보장이다.
      final svc = _code(_src('lib/services/firestore_service.dart'));
      expect(svc.contains('required String expectedAttendancePolicy'), isTrue);
      final af =
          _code(_src('lib/services/firestore/application_firestore.dart'));
      expect(af.contains('required String expectedAttendancePolicy'), isTrue);
      expect(af.contains("'expectedAttendancePolicy': expectedAttendancePolicy"),
          isTrue);
      final submit =
          _code(_src('lib/widgets/dialogs/apply/apply_work_submit.dart'));
      expect(submit.contains('required String expectedAttendancePolicy'), isTrue);
    });

    test('ENTRY 읽지 못했으면 빈 토큰으로 fail closed', () {
      final dlg = _code(_src('lib/widgets/dialogs/apply/apply_work_dialog.dart'));
      // 읽기 실패와 "기준 없는 사업장"을 구별한다.
      expect(dlg.contains('bool _policyLoaded = false;'), isTrue);
      expect(
          dlg.contains("_policyLoaded ? attendancePolicyFingerprint(_policyRules) : ''"),
          isTrue,
          reason: '읽지 못한 상태에서 absent 토큰을 보내면 기준 없는 사업장으로 통과한다');
    });
  });

  group('UX — 기준 변경은 실패와 다른 상태다', () {
    test('UX-1 policyChanged 는 failed·unknown 과 다르다', () {
      final r = ApplyResult.policyChanged('x', code: 'ATTENDANCE_POLICY_CHANGED');
      expect(r.outcome, ApplyOutcome.policyChanged);
      expect(r.isPolicyChanged, isTrue);
      expect(r.isApplied, isFalse, reason: '지원은 만들어지지 않았다');
      expect(r.isUnknown, isFalse, reason: '모름이 아니다 — 확실히 안 만들어졌다');
      expect(r.isNewlyApplied, isFalse);
      // 분류는 서버 `details.reason` 으로 한다 — 문구 비교가 아니다.
      final af =
          _code(_src('lib/services/firestore/application_firestore.dart'));
      expect(af.contains("reason == 'ATTENDANCE_POLICY_CHANGED'"), isTrue);
      expect(af.contains("reason == 'ATTENDANCE_POLICY_NOT_DISCLOSED'"), isTrue);
      expect(af.contains("d['reason'] is String"), isTrue);
    });

    test('UX-2 자동 재지원이 없다', () {
      final dlg = _code(_src('lib/widgets/dialogs/apply/apply_work_dialog.dart'));
      // 기준을 다시 읽기만 한다 — 다시 보내지 않는다.
      final i = dlg.indexOf('applied.isPolicyChanged');
      expect(i, greaterThan(-1));
      final after = dlg.substring(i, i + 500);
      expect(after.contains('_loadPolicyRules()'), isTrue);
      expect(after.contains('_submit.apply('), isFalse,
          reason: '근로자가 바뀐 기준을 다시 확인해야 한다');
      // 서버도 재시도하지 않는다 — 거부하고 끝낸다.
      expect(apply.contains('ATTENDANCE_POLICY_CHANGED'), isTrue);
      expect(apply.contains('retryWithFreshPolicy'), isFalse);
    });

    test('UX-3 안내는 상태 변경이지 법률 경고가 아니다', () {
      expect(kAttendancePolicyChangedNote.contains('변경됐어요'), isTrue);
      expect(kAttendancePolicyChangedNote.contains('다시 지원'), isTrue);
      for (final banned in ['위반', '법적', '책임', '불이익']) {
        expect(kAttendancePolicyChangedNote.contains(banned), isFalse,
            reason: '금지 표현: $banned');
      }
      // "지원에 실패했습니다" 로 뭉개지 않는다.
      final dlg = _code(_src('lib/widgets/dialogs/apply/apply_work_dialog.dart'));
      expect(dlg.contains('ToastHelper.showWarning(kAttendancePolicyChangedNote)'),
          isTrue);
    });

    test('UX-4 최신 기준은 기존 reader 로 다시 읽는다', () {
      final posting = _code(_src('lib/screens/common/job_posting_screen.dart'));
      expect(posting.contains('Future<void> _refreshAfterPolicyChange()'), isTrue);
      expect(posting.contains('await _loadData();'), isTrue,
          reason: '별도 policy reader 를 만들지 않는다');
      // 서버 응답에 정책을 실어 두 번째 truth source 를 만들지 않는다.
      expect(apply.contains('currentAttendanceRules'), isFalse);
      expect(apply.contains('latestPolicy'), isFalse);
    });

    test('MULTI 이미 성공한 건을 실패로 바꾸지 않는다', () {
      final multi =
          _code(_src('lib/widgets/dialogs/apply/multi_apply_confirm_sheet.dart'));
      // 건별 결과를 따로 담는 기존 계약 유지 — 하나가 막혀도 나머지를
      //   취소하지 않고, 성공 건수는 성공 건수로 센다.
      expect(multi.contains('if (result.isNewlyApplied) successCount++;'), isTrue);
      expect(multi.contains('if (result.isPolicyChanged) policyChangedCount++;'),
          isTrue);
      expect(multi.contains('policyChanged: policyChangedCount > 0'), isTrue);
      // 전체 실패로 되돌리는 경로가 없다 — `successCount` 는 선언에서 0 으로
      //   시작하고 그 뒤로는 **증가만** 한다.
      expect('successCount = 0'.allMatches(multi).length, 1,
          reason: '성공 건수를 되돌리는 대입이 생기면 partial 의미가 깨진다');
      expect(multi.contains('successCount--'), isFalse);
    });
  });

  group('변형 방어', () {
    test('MUT-5 조건을 무력화하는 형태를 막는다', () {
      expect(cf.contains('if (false'), isFalse);
      // 비교를 상수로 꺾지 않았다.
      expect(apply.contains('expectedAttendancePolicy !== applyFreshFp'), isTrue);
      expect(apply.contains('expectedAttendancePolicy === applyFreshFp'), isFalse);
      // 두 거부가 모두 살아 있다.
      expect('throw new HttpsError('
              .allMatches(_slice(apply, 'const applyTxBizSnap =',
                  'const applyTxPolicy ='))
              .length,
          2);
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
