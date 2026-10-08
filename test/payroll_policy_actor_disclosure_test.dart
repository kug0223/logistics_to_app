// [R7-PAYROLL-POLICY.4B] 누가 확인했는가 · 근로자가 전부 볼 수 있는가
//
// ── 문제 A — 플랫폼 운영자를 사업장으로 읽었다 ──────────────────────
//   `.4A` 의 두 writer 는 `callerRole === "SUPER_ADMIN"` 이면 소속 검사를
//   건너뛰고 `confirmedBy`/`acknowledgedBy = callerUid` 를 적었다. 그러면
//   플랫폼 운영자의 행위가 "사업장이 이 정책을 채택했다" 는 증거로 남는다.
//
//   "이 기능을 실행할 수 있다" 와 "사업장이 채택했다" 는 다른 사실이다.
//   계약서 날인이 **누가 발송했는지가 아니라 사업장 사업주의 것**이어야
//   하는 것과 같은 규칙이다(P4.4C-SIGNER-01).
//
// ── 문제 B — 근로자가 일부만 봤다 ───────────────────────────────────
//   급여에 영향하는 숫자는 7개다. 그런데 근로자 수락 화면은 4개, 계약서·PDF 는
//   5개만 보여줬다. 빠진 셋(`earlyWindow`·`earlyArrivalUnit`·`lateWindow`)도
//   실제 지급액을 바꾼다 — 이 파일의 SEM-* 가 계산으로 증명한다.
//
// 반올림 산술은 **한 줄도 바꾸지 않았다.**
//
// 고정하는 것
//   ACT-1  두 writer 가 같은 actor 경계를 쓴다
//   ACT-2  owner / adminIds 만 사업장 확인을 만든다
//   ACT-3  SUPER_ADMIN 은 사업장 확인이 되지 않는다
//   ACT-4  SubAdmin 경계를 넓히지 않았다
//   ACT-5  기록이 행위자 종류를 담는다
//   ACT-6  판정이 행위자 종류를 본다 (종류 없는 기록 불인정)
//   ACT-7  actor uid 는 서버가 정한다 (client spoof 불가)
//   ACT-8  증거는 CF 전용 immutable
//   SEM-1  earlyWindow 가 금액을 바꾼다
//   SEM-2  earlyArrivalUnit 이 금액을 바꾼다
//   SEM-3  lateWindow 가 금액을 바꾼다
//   SEM-4  7개 전부가 고지 목록에 들어 있다
//   DISC-11 근로자 수락 화면이 7개 전부를 쓴다
//   DISC-12 계약서·PDF 가 같은 목록을 쓴다
//   DISC-13 관리자 확인 시트도 같은 목록이다
//   DISC-14 live 사업장 값으로 바꿔치지 않는다
//   DISC-15 기록 없음을 현재값으로 위조하지 않는다
//   DISC-16 snapshot 과 live 를 **항목별로 섞지 않는다**
//   DISC-17 재배치는 상속 사실을 말하고 확인 경로를 준다
//   DISC-18 이름이 화면 사이에 일관된다
//   DISC-19 금지 표현이 없다
//   MUT-4  변형 방어
import 'dart:io';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/utils/attendance_policy_disclosure.dart';
import 'package:ALfit/utils/attendance_rounding_helper.dart';
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

/// 7개 숫자를 담은 확인 기록. [actorRole] 을 비우면 종류 없는 기록이다.
AttendancePolicyConfirmation _evidence(
  AttendanceRules r, {
  String? actorRole = AttendancePolicyConfirmation.actorBusinessAdmin,
}) =>
    AttendancePolicyConfirmation(
      earlyWindow: r.earlyWindow,
      earlyArrivalUnit: r.earlyArrivalUnit,
      lateGrace: r.lateGrace,
      lateUnit: r.lateUnit,
      lateWindow: r.lateWindow,
      overtimeUnit: r.overtimeUnit,
      earlyLeaveUnit: r.earlyLeaveUnit,
      confirmedAt: DateTime(2026, 10, 8),
      confirmedBy: 'admin-1',
      actorRole: actorRole,
    );

BusinessModel _biz(AttendanceRules rules,
        {AttendancePolicyConfirmation? confirmation}) =>
    BusinessModel(
      id: 'b1',
      businessNumber: '1234567890',
      name: '사업장',
      category: 'c',
      subCategory: 's',
      address: '주소',
      ownerId: 'owner',
      createdAt: DateTime(2026, 1, 1),
      attendanceRules: rules,
      attendancePolicyConfirmation: confirmation,
    );

ApplicationModel _app({AttendanceRules? snapshot}) => ApplicationModel(
      id: 'a1',
      businessId: 'b1',
      businessName: '사업장',
      toTitle: '공고',
      workDate: DateTime(2026, 10, 8),
      startTime: '09:00',
      endTime: '18:00',
      uid: 'u1',
      status: 'PENDING',
      selectedWorkType: '분류',
      wage: 12000,
      appliedAt: DateTime(2026, 10, 1),
      attendancePolicySnapshot: snapshot,
    );

/// 인정 출근 시각(분 오프셋) — 서버 `_processCheckin` 과 같은 식이다.
int _inOffset(AttendanceRules r, int punchOffset) {
  final day = DateTime(2026, 1, 1);
  final start = contractStartAt(day, '09:00');
  return processCheckin(
          offsetMinutes: punchOffset, referenceAt: start, rules: r)
      .roundedOffset;
}

/// 인정 퇴근 시각(분 오프셋).
int _outOffset(AttendanceRules r, int punchOffset) {
  final day = DateTime(2026, 1, 1);
  final end = contractEndAt(day, '09:00', '18:00');
  return processCheckout(
          offsetMinutes: punchOffset, referenceAt: end, rules: r)
      .roundedOffset;
}

void main() {
  final cfRaw = _src('functions/src/index.ts');
  final cf = _code(cfRaw);
  final rules = _src('firestore.rules');
  final disclosure = _src('lib/utils/attendance_policy_disclosure.dart');

  group('actor — 누가 사업장 확인을 만들 수 있는가', () {
    final actorGate = _code(
        _slice(cfRaw, 'function srvAssertBusinessPolicyActor(', '\n/**'));
    final confirmCf = _code(_callable(cfRaw, 'callableConfirmAttendancePolicy'));
    final ackCf =
        _code(_callable(cfRaw, 'callableAcknowledgeApplicationPolicy'));

    test('ACT-1 두 writer 가 같은 actor 경계를 쓴다', () {
      expect('function srvAssertBusinessPolicyActor('.allMatches(cf).length, 1);
      expect(confirmCf.contains('srvAssertBusinessPolicyActor('), isTrue);
      expect(ackCf.contains('srvAssertBusinessPolicyActor('), isTrue);
      // 경계를 각자 다시 구현하지 않는다.
      for (final body in [confirmCf, ackCf]) {
        expect(body.contains('adminIds.includes(callerUid)'), isFalse,
            reason: '두 writer 가 다른 경계를 가지면 "사업장이 확인했다" 가 두 뜻이 된다');
      }
    });

    test('ACT-2 owner / adminIds 만 사업장 확인을 만든다', () {
      expect(actorGate.contains('adminIds.includes(callerUid)'), isTrue);
      expect(actorGate.contains('ownerId === callerUid'), isTrue);
      expect(actorGate.contains('return;'), isTrue, reason: '통과 경로가 있어야 한다');
    });

    test('ACT-3 SUPER_ADMIN 은 사업장 확인이 되지 않는다', () {
      // 통과시키지 않는다 — 통과 판정은 소속 검사 하나뿐이다.
      final pass = actorGate.indexOf('return;');
      final superBranch = actorGate.indexOf('callerRole === "SUPER_ADMIN"');
      expect(superBranch, greaterThan(pass),
          reason: 'SUPER_ADMIN 분기가 통과보다 앞이면 운영자 행위가 사업장 확인이 된다');
      expect(
          actorGate.contains('PLATFORM_ACTOR_NOT_BUSINESS_ACKNOWLEDGEMENT'),
          isTrue, reason: '운영자에게 왜 막혔는지 말한다');
      expect(actorGate.contains('throw new HttpsError(\n      "permission-denied"'),
          isTrue);
      // `.4A` 의 우회 조건이 남아 있지 않다.
      expect(cf.contains('callerRole !== "SUPER_ADMIN" &&\n        !bizAdminIds'),
          isFalse);
      expect(cf.contains('callerRole !== "SUPER_ADMIN" &&\n        !ackAdminIds'),
          isFalse);
    });

    test('ACT-4 SubAdmin 경계를 넓히지 않았다', () {
      for (final body in [actorGate, confirmCf, ackCf]) {
        expect(body.contains('subAdmin'), isFalse);
        expect(body.contains('canManageWage'), isFalse);
        expect(body.contains('canManageWorkers'), isFalse);
        expect(body.contains('assertBizAdmin('), isFalse,
            reason: 'assertBizAdmin 은 SubAdmin 까지 통과시킨다');
      }
    });

    test('ACT-5 기록이 행위자 종류를 담는다', () {
      expect(confirmCf.contains('actorRole: POLICY_ACTOR_BUSINESS_ADMIN'),
          isTrue);
      final builder = _code(_slice(
          cfRaw, 'function srvBuildPolicyAcknowledgement(', '\n/**'));
      expect(builder.contains('out["actorRole"] = POLICY_ACTOR_BUSINESS_ADMIN;'),
          isTrue);
      expect('const POLICY_ACTOR_BUSINESS_ADMIN'.allMatches(cf).length, 1);
    });

    test('ACT-6 판정이 행위자 종류를 본다', () {
      final covers =
          _code(_slice(cfRaw, 'function srvPolicyEvidenceCovers(', '\n/**'));
      expect(
          covers.contains(
              'if (e["actorRole"] !== POLICY_ACTOR_BUSINESS_ADMIN) return false;'),
          isTrue);

      // Dart 쪽도 같은 술어다.
      const r = AttendanceRules();
      expect(_evidence(r).hasEvidence, isTrue);
      // 종류가 없는 기록(이 Phase 이전)은 인정되지 않는다.
      expect(_evidence(r, actorRole: null).hasEvidence, isFalse,
          reason: '사업장 측이었음을 증명할 수 없는 기록을 사업장 확인으로 쓰지 않는다');
      expect(_evidence(r, actorRole: 'platform_admin').hasEvidence, isFalse);
      // 사업장 판정에도 그대로 반영된다.
      expect(_biz(r, confirmation: _evidence(r)).isAttendancePolicyConfirmed,
          isTrue);
      expect(
          _biz(r, confirmation: _evidence(r, actorRole: null))
              .isAttendancePolicyConfirmed,
          isFalse);
    });

    test('ACT-7 actor uid 는 서버가 정한다', () {
      // payload 에 uid·정책값이 들어올 자리가 없다.
      expect(confirmCf.contains('request.data as {businessId?: string}'), isTrue);
      expect(
          ackCf.contains('applicationId?: string;') &&
              ackCf.contains('businessId?: string;'),
          isTrue);
      for (final body in [confirmCf, ackCf]) {
        expect(body.contains('request.data as {actorRole'), isFalse);
        expect(body.contains('= request.auth.uid;'), isTrue);
      }
    });

    test('ACT-8 증거는 CF 전용 immutable', () {
      expect(
          rules.contains("'attendancePolicyConfirmation'"), isTrue,
          reason: '사업장 확인 기록은 클라이언트가 쓸 수 없다');
      expect(rules.contains("'attendancePolicyAcknowledgement'"), isTrue);
      // SUPER_ADMIN 도 rules 로 우회할 수 없다.
      //   사업장 update 규칙의 모양:
      //     (isAdminOf || isSuperAdmin()) && <차단목록> && (isSuperAdmin() || ...)
      //   첫 `isSuperAdmin()` 는 **권한**이고, 세 번째 절의 `(isSuperAdmin() ||`
      //   가 필드 제한을 면제하는 **우회 분기**다. 차단 목록이 그 우회보다
      //   앞이어야 슈퍼어드민도 이 필드를 직접 쓸 수 없다.
      final bizUpdate = _slice(
          rules,
          'allow update: if (isAdminOf(businessId)',
          'allow update: if isAdminOf');
      final iDeny = bizUpdate.indexOf("'attendancePolicyConfirmation'");
      final iBypass = bizUpdate.indexOf('(isSuperAdmin() ||');
      expect(iDeny, greaterThan(-1));
      expect(iBypass, greaterThan(-1));
      expect(iDeny, lessThan(iBypass),
          reason: '차단이 우회 분기 뒤에 있으면 SUPER_ADMIN 이 직접 쓸 수 있다');
    });
  });

  group('semantics — 7개가 모두 금액을 바꾼다', () {
    test('SEM-1 earlyWindow 가 금액을 바꾼다', () {
      // 시작 31분 전 도착: window 30 이면 조출 인정, window 40 이면 정시 처리.
      const w30 = AttendanceRules(earlyWindow: 30, earlyArrivalUnit: 30);
      const w40 = AttendanceRules(earlyWindow: 40, earlyArrivalUnit: 30);
      expect(_inOffset(w30, -31), -30,
          reason: 'window 를 넘긴 조기 도착은 30분 단위로 인정된다');
      expect(_inOffset(w40, -31), 0,
          reason: 'window 이내면 같은 시각에 와도 인정되지 않는다');
      // 30분 차이 = 지급 시간 30분 차이.
      expect(_inOffset(w30, -31) == _inOffset(w40, -31), isFalse);
    });

    test('SEM-2 earlyArrivalUnit 이 금액을 바꾼다', () {
      const u30 = AttendanceRules(earlyWindow: 30, earlyArrivalUnit: 30);
      const u10 = AttendanceRules(earlyWindow: 30, earlyArrivalUnit: 10);
      expect(_inOffset(u30, -55), -30);
      expect(_inOffset(u10, -55), -50,
          reason: '단위가 작으면 더 많은 시간이 인정된다 — 20분 차이');
    });

    test('SEM-3 lateWindow 가 금액을 바꾼다', () {
      const w30 = AttendanceRules(lateWindow: 30, overtimeUnit: 10);
      const w60 = AttendanceRules(lateWindow: 60, overtimeUnit: 10);
      expect(_outOffset(w30, 40), 40, reason: 'window 를 넘기면 연장으로 인정된다');
      expect(_outOffset(w60, 40), 0,
          reason: 'window 이내면 같은 시간 더 있어도 인정되지 않는다');
    });

    test('SEM-4 7개 전부가 고지 목록에 들어 있다', () {
      // 한 항목만 바꿨을 때 고지 문장이 **반드시** 달라져야 한다.
      //   그러지 않으면 그 숫자는 근로자에게 전달되지 않는 것이다.
      const base = AttendanceRules();
      String render(AttendanceRules r) => attendancePolicyLines(r)
          .map((l) => '${l.label}=${l.value}')
          .join('|');
      final baseText = render(base);
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
        expect(render(v) == baseText, isFalse,
            reason: '$k 가 바뀌어도 근로자가 보는 문장이 같다 — 고지되지 않는 임금조건이다');
      });
      // 출근 4줄 + 퇴근 3줄.
      final groups = attendancePolicyGroups(base);
      expect(groups.map((g) => g.title).toList(), ['출근', '퇴근']);
      expect(groups[0].lines.length, 4);
      expect(groups[1].lines.length, 3);
      // 내부 필드 이름을 그대로 쓰지 않는다.
      for (final bad in ['earlyWindow', 'lateUnit', 'overtimeUnit']) {
        expect(baseText.contains(bad), isFalse, reason: '내부 이름 노출: $bad');
      }
    });
  });

  group('disclosure — 모든 화면이 같은 것을 말한다', () {
    final mine = _code(_src('lib/screens/user/my_applications_screen.dart'));
    final sign = _code(_src('lib/screens/contract/contract_sign_screen.dart'));
    final pdf = _code(_src('lib/screens/contract/contract_pdf_builder.dart'));
    final ackSheet = _code(
        _src('lib/widgets/dialogs/application_policy_acknowledge_sheet.dart'));
    final posting = _code(_src('lib/screens/common/job_posting_screen.dart'));

    test('DISC-11 근로자 수락 화면이 7개 전부를 쓴다', () {
      expect(mine.contains('attendancePolicyGroups('), isTrue);
      // 자체 라벨 목록을 복제하지 않는다.
      for (final bad in ["('지각 유예'", "('지각 처리'", "('조퇴 처리'"]) {
        expect(mine.contains(bad), isFalse, reason: '라벨 복제: $bad');
      }
      expect(mine.contains('kAttendancePolicyTitle'), isTrue);
      expect(mine.contains('kAttendancePolicyFrozenNote'), isTrue);
    });

    test('DISC-12 계약서·PDF 가 같은 목록을 쓴다', () {
      for (final body in [sign, pdf]) {
        expect(body.contains('attendancePolicyLines('), isTrue);
        // 손으로 적은 항목이 남아 있지 않다 — 한쪽만 7개가 되는 일을 막는다.
        expect(body.contains("'조출 인정'"), isFalse);
        expect(body.contains("'지각 유예'"), isFalse);
      }
      // 둘 다 Application snapshot 에서만 온다.
      for (final body in [sign, pdf]) {
        expect(body.contains('snapshot.attendancePolicy'), isTrue);
        expect(body.contains('attendanceRules'), isFalse);
      }
    });

    test('DISC-13 관리자 확인 시트도 같은 목록이다', () {
      expect(ackSheet.contains('attendancePolicyLines('), isTrue);
      expect(ackSheet.contains("('지각 유예'"), isFalse);
    });

    test('DISC-14 live 사업장 값으로 바꿔치지 않는다', () {
      // 근로자 약속 화면·계약서는 사업장 문서를 읽지 않는다.
      for (final body in [mine, sign, pdf]) {
        expect(body.contains('getBusinessById'), isFalse);
        expect(body.contains('business.attendanceRules'), isFalse);
      }
      // 공고 상세는 지원 **전**이므로 현재 기준을 쓴다 — 그 사실이 명시돼 있다.
      expect(posting.contains('_business!.attendanceRules'), isTrue);
      expect(posting.contains('지원하면 이 기준이 지원 시점 조건으로 고정됩니다'), isTrue);
    });

    test('DISC-15 기록 없음을 현재값으로 위조하지 않는다', () {
      expect(disclosure.contains('kAttendancePolicyUnknownNote'), isTrue);
      expect(mine.contains('kAttendancePolicyUnknownNote'), isTrue);
      // 전달값이 null 이면 안내를 보여준다 — 아무것도 안 보여주지 않는다.
      expect(mine.contains('_attendancePolicyBlock(offerApp.attendancePolicySnapshot)'),
          isTrue);
      expect(mine.contains('if (rules == null)'), isTrue);
      // 안내 문구가 현재 기준을 권하지 않는다.
      expect(
          _src('lib/utils/attendance_policy_disclosure.dart')
              .contains('사업장에 확인해 주세요'),
          isTrue);
    });

    test('DISC-16 snapshot 과 live 를 항목별로 섞지 않는다', () {
      // 서버·클라이언트 모두 **객체 단위** 폴백이다. 항목별로 메우면
      //   약속에 없는 숫자가 약속의 일부처럼 된다.
      final resolver = _code(_slice(
          cfRaw, 'function srvEffectiveAttendanceRules(', '\n/**'));
      expect(resolver.contains('return snap as AttendanceRulesData'), isTrue);
      expect(resolver.contains('??'), isTrue);
      // 항목별 병합의 흔적이 없다.
      expect(resolver.contains('for (const k of'), isFalse);
      final model = _code(_src('lib/models/core/application_model.dart'));
      expect(
          model.contains('attendancePolicySnapshot ?? businessRules'), isTrue);

      const a = AttendanceRules(lateUnit: 30, earlyWindow: 30);
      const b = AttendanceRules(lateUnit: 10, earlyWindow: 60);
      // snapshot 이 있으면 전부 snapshot 이다.
      final eff = _app(snapshot: a).effectiveAttendanceRules(b);
      expect(eff!.lateUnit, 30);
      expect(eff.earlyWindow, 30);
      // 없으면 전부 사업장 기준이다.
      final eff2 = _app().effectiveAttendanceRules(b);
      expect(eff2!.lateUnit, 10);
      expect(eff2.earlyWindow, 60);
    });

    test('DISC-17 재배치는 상속 사실을 말하고 확인 경로를 준다', () {
      final sheet =
          _code(_src('lib/widgets/dialogs/confirmed_reassignment_sheet.dart'));
      expect(sheet.contains('동일하게 유지됩니다'), isTrue);
      expect(sheet.contains('근로계약서에서 확인할 수 있습니다'), isTrue,
          reason: '숫자를 반복하지 않는 대신 어디서 볼 수 있는지 말한다');
      expect(sheet.contains('attendanceRules'), isFalse);
    });

    test('DISC-18 이름이 화면 사이에 일관된다', () {
      // 근로자·계약·관리자가 같은 도메인 이름을 쓴다.
      expect(kAttendancePolicyTitle, '근태·급여 처리 기준');
      final form =
          _code(_src('lib/screens/business_admin/business_form_screen.dart'));
      expect(form.contains("title: '근태 및 급여 처리 기준'"), isTrue);
      final detail =
          _code(_src('lib/screens/business_admin/business_detail_screen.dart'));
      expect(detail.contains("title: '근태 및 급여 처리 기준'"), isTrue);
      // 옛 이름이 남아 있지 않다.
      for (final body in [mine, posting, ackSheet]) {
        expect(body.contains('반올림 규칙'), isFalse);
        expect(body.contains('출근 규칙'), isFalse);
      }
    });

    test('DISC-19 금지 표현이 없다', () {
      for (final body in [disclosure, mine, sign, pdf, ackSheet, posting]) {
        for (final banned in [
          '법적으로 승인',
          'ALfit이 보증',
          'ALfit 이 보증',
          '모든 책임은 사업장',
          '책임을 지지 않습니다',
        ]) {
          expect(body.contains(banned), isFalse, reason: '금지 표현: $banned');
        }
      }
    });
  });

  group('변형 방어', () {
    test('MUT-4 조건을 무력화하는 형태를 막는다', () {
      expect(cf.contains('if (false'), isFalse);
      expect(disclosure.contains('if (false'), isFalse);
      // actor 판정이 무조건 통과로 바뀌지 않았다.
      final actorGate = _code(
          _slice(cfRaw, 'function srvAssertBusinessPolicyActor(', '\n/**'));
      expect('return;'.allMatches(actorGate).length, 1,
          reason: '통과 경로는 소속 검사 하나뿐이다');
      expect('throw new HttpsError('.allMatches(actorGate).length, 2,
          reason: '운영자·그 밖 두 거부가 모두 살아 있어야 한다');
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
