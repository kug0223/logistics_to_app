// [R7-PAYROLL-POLICY.4A] 확정되는 약속의 기준이 사업장이 확인한 기준인가
//
// `.4` 는 두 가지를 각각 닫았다 — 지원서가 지원 시점 기준을 들고 있고,
// 사업장이 **현재** 기준을 확인한다. 그런데 그 둘이 갈라질 수 있었다.
//
//   T1 기준 A · 확인 없음 · 기존 열린 공고
//   T2 근로자 지원        → snapshot A
//   T3 사업장이 B 로 변경 · T4 B 를 확인
//   T5 관리자가 확정      → 약속은 A 인데 확인 증거는 B 뿐이다
//
// A 를 B 로 덮는 것(지원조건 소급변경)도, B 의 확인을 A 의 확인으로 간주하는
// 것(증거 위조)도 금지다. 필요한 것은 **A 자체가 확인됐다는 증명**이다.
//
// 두 번째 구멍: 대체근무 제안이 근태 기준을 **수락 시점**에 찍었다. 그러면
// 제안 뒤 사업장이 기준을 바꾸면 근로자가 제안받은 조건과 확정 조건이 달라진다.
// 임금·휴게·야간을 제안 시점에 고정하는 원칙과 어긋난다.
//
// 반올림 계산식은 **한 줄도 바꾸지 않았다.**
//
// 고정하는 것
//   OWN-13 확인 비교가 한 벌이다
//   OWN-14 확인 기록은 7개 숫자 + actor + 시각이다
//   OWN-15 두 경로로만 증명된다 (지원서 확인 · 현재 확인과 일치)
//   OWN-16 다른 기준의 확인을 빌려 쓰지 않는다
//   OWN-17 지원서 확인은 CF 전용이다
//   OWN-18 확인 권한은 기준 수정 권한과 같다
//   OWN-19 확정된 약속의 기록을 다시 쓰지 않는다
//   GATE-7 확정이 지원서 기준으로 판정한다
//   GATE-8 초대 수락도 지원서 기준으로 판정한다
//   GATE-9 대체근무 제안은 미확인 기준에서 막힌다
//   GATE-10 기존 확정 근무·급여는 이 gate 에 걸리지 않는다
//   OFFER-1 제안이 제안 시점 기준을 고정한다
//   OFFER-2 제안이 확인 기록도 남긴다
//   OFFER-3 수락이 live 기준으로 덮지 않는다
//   INV-1   초대도 확인 기록을 남긴다
//   RAS-1   확정 재배치는 원 약속의 기준과 확인을 물려받는다
//   RAS-2   재배치가 사업장 현재 기준을 읽지 않는다
//   RAS-3   근로자 시트가 기준 불변을 말한다
//   DISC-8  근로자 수락 화면이 고정된 기준을 보여준다
//   DISC-9  관리자 확정 차단이 그 지원자에서 해결된다
//   DISC-10 계약·근태는 같은 snapshot 을 쓴다
//   MUT-3   변형 방어
import 'dart:io';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
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

/// 7개 숫자가 같은 확인 기록을 만든다.
AttendancePolicyConfirmation _evidenceFor(AttendanceRules r,
        {String by = 'admin-1'}) =>
    AttendancePolicyConfirmation(
      earlyWindow: r.earlyWindow,
      earlyArrivalUnit: r.earlyArrivalUnit,
      lateGrace: r.lateGrace,
      lateUnit: r.lateUnit,
      lateWindow: r.lateWindow,
      overtimeUnit: r.overtimeUnit,
      earlyLeaveUnit: r.earlyLeaveUnit,
      confirmedAt: DateTime(2026, 10, 8),
      confirmedBy: by,
    );

BusinessModel _biz({
  AttendanceRules? rules,
  AttendancePolicyConfirmation? confirmation,
}) =>
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

ApplicationModel _app({
  AttendanceRules? snapshot,
  AttendancePolicyConfirmation? acknowledgement,
}) =>
    ApplicationModel(
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
      attendancePolicyAcknowledgement: acknowledgement,
    );

void main() {
  final cfRaw = _src('functions/src/index.ts');
  final cf = _code(cfRaw);
  final rules = _src('firestore.rules');

  group('ownership — 그 약속의 기준이 확인됐는가', () {
    final ownership = _code(_slice(
        cfRaw, 'function srvApplicationPolicyOwnership(', '\n/**'));
    final covers =
        _code(_slice(cfRaw, 'function srvPolicyEvidenceCovers(', '\n/**'));
    final ackCf =
        _code(_callable(cfRaw, 'callableAcknowledgeApplicationPolicy'));

    test('OWN-13 확인 비교가 한 벌이다', () {
      // 사업장 확인과 지원서 확인이 같은 비교를 쓴다 — 두 벌이 되면 gate 마다
      //   다른 말을 하게 된다.
      expect('function srvPolicyEvidenceCovers('.allMatches(cf).length, 1);
      final bizBlock =
          _code(_slice(cfRaw, 'function srvAttendancePolicyBlock(', '\n/**'));
      expect(bizBlock.contains('srvPolicyEvidenceCovers('), isTrue);
      expect(ownership.contains('srvPolicyEvidenceCovers('), isTrue);
      // 비교 자체가 복제되지 않았다.
      expect(bizBlock.contains('ATTENDANCE_POLICY_MATERIAL_FIELDS'), isFalse);
      expect(ownership.contains('ATTENDANCE_POLICY_MATERIAL_FIELDS'), isFalse);
    });

    test('OWN-14 확인 기록은 7개 숫자 + actor + 시각이다', () {
      expect(covers.contains('for (const k of ATTENDANCE_POLICY_MATERIAL_FIELDS)'),
          isTrue);
      expect(covers.contains('srvAttendancePolicyValue(target, k)'), isTrue);
      expect(covers.contains('e[atKey] == null'), isTrue);
      expect(covers.contains('typeof by !== "string" || by.length === 0'),
          isTrue);
      final builder = _code(_slice(
          cfRaw, 'function srvBuildPolicyAcknowledgement(', '\n/**'));
      expect(builder.contains('acknowledgedAt'), isTrue);
      expect(builder.contains('serverTimestamp()'), isTrue,
          reason: '클라이언트 시각을 쓰지 않는다');
      expect(builder.contains('out["acknowledgedBy"] = actorUid;'), isTrue);
    });

    test('OWN-15 두 경로로만 증명된다', () {
      // ① 지원서별 확인 기록
      expect(
          ownership.contains('appData?.["attendancePolicyAcknowledgement"]'),
          isTrue);
      expect(ownership.contains('"acknowledgedAt", "acknowledgedBy"'), isTrue);
      // ② 사업장이 지금 확인한 기준과 일치
      expect(ownership.contains('bizData?.["attendancePolicyConfirmation"]'),
          isTrue);
      expect(ownership.contains('"confirmedAt", "confirmedBy"'), isTrue);
      // 그 밖에는 막는다.
      expect(
          ownership.contains('return "APPLICATION_POLICY_NOT_ACKNOWLEDGED";'),
          isTrue);

      // Dart 쪽 표현도 같은 순서다.
      const a = AttendanceRules(lateUnit: 30);
      const b = AttendanceRules(lateUnit: 10);
      // ① 지원서 확인 기록만 있으면 증명된다.
      expect(
          _app(snapshot: a, acknowledgement: _evidenceFor(a))
              .isAttendancePolicyOwned(
                  _biz(rules: b, confirmation: _evidenceFor(b))),
          isTrue);
      // ② 사업장 현재 확인과 같으면 별도 기록 없이 증명된다.
      expect(
          _app(snapshot: a)
              .isAttendancePolicyOwned(
                  _biz(rules: a, confirmation: _evidenceFor(a))),
          isTrue);
    });

    test('OWN-16 다른 기준의 확인을 빌려 쓰지 않는다', () {
      const a = AttendanceRules(lateUnit: 30);
      const b = AttendanceRules(lateUnit: 10);
      // 사업장은 B 를 확인했고 지원서는 A 다 — 증명되지 않는다.
      expect(
          _app(snapshot: a)
              .isAttendancePolicyOwned(
                  _biz(rules: b, confirmation: _evidenceFor(b))),
          isFalse,
          reason: 'B 의 확인을 A 의 확인으로 쓰면 책임 chain 이 끊긴 채 확정된다');
      // 지원서 확인 기록이 **다른 값**을 담고 있으면 그 기록도 소용없다.
      expect(
          _app(snapshot: a, acknowledgement: _evidenceFor(b))
              .isAttendancePolicyOwned(_biz(rules: a)),
          isFalse);
      // actor·시각이 비면 확인이 아니다.
      expect(
          _app(
            snapshot: a,
            acknowledgement: AttendancePolicyConfirmation(
              earlyWindow: a.earlyWindow,
              earlyArrivalUnit: a.earlyArrivalUnit,
              lateGrace: a.lateGrace,
              lateUnit: a.lateUnit,
              lateWindow: a.lateWindow,
              overtimeUnit: a.overtimeUnit,
              earlyLeaveUnit: a.earlyLeaveUnit,
            ),
          ).isAttendancePolicyOwned(_biz(rules: a)),
          isFalse);
    });

    test('OWN-17 지원서 확인은 CF 전용이다', () {
      expect(
          rules.contains("hasAny(['uid', 'attendancePolicySnapshot',"),
          isTrue);
      expect(rules.contains("'attendancePolicyAcknowledgement'])"), isTrue,
          reason: '클라이언트가 쓰면 조건 소급변경과 증거 위조가 모두 가능하다');
      // 클라이언트 모델은 이 필드를 쓰지 않는다.
      final model = _code(_src('lib/models/core/application_model.dart'));
      expect(model.contains("'attendancePolicyAcknowledgement': "), isFalse);
    });

    test('OWN-18 확인 권한은 기준 수정 권한과 같다', () {
      expect(ackCf.contains('ackAdminIds.includes(callerUid)'), isTrue);
      expect(ackCf.contains('ackOwnerId !== callerUid'), isTrue);
      expect(ackCf.contains('assertBizAdmin('), isFalse,
          reason: 'SubAdmin 은 기준을 수정할 수 없으므로 채택 결정도 할 수 없다');
      // 클라이언트가 확인할 값을 보내지 않는다 — 서버가 지원서에서 읽는다.
      expect(
          ackCf.contains('srvBuildPolicyAcknowledgement(\n'
              '      snap as Record<string, unknown>, callerUid)'),
          isTrue);
    });

    test('OWN-19 확정된 약속의 기록을 다시 쓰지 않는다', () {
      expect(
          ackCf.contains(
              'if (ackStatus === "CONFIRMED" || ackStatus === "CONTRACT_PENDING")'),
          isTrue, reason: '확인은 확정 전 행위다');
      // 고정된 기준이 없으면 확인할 대상이 없다.
      expect(ackCf.contains('NO_APPLICATION_POLICY_SNAPSHOT'), isTrue);
      // 소속이 다른 지원서의 존재를 알려주지 않는다.
      expect(ackCf.contains('"지원서를 찾을 수 없습니다."'), isTrue);
    });
  });

  group('gate — 새 약속의 기준이 확인된 것인가', () {
    test('GATE-7 확정이 지원서 기준으로 판정한다', () {
      final confirm = _code(_callable(cfRaw, 'callableConfirmApplication'));
      expect(
          confirm.contains('srvApplicationPolicyOwnership(fd, cfmBizSnap.data())'),
          isTrue);
      // 사업장 현재 기준만 보던 `.4` 판정은 더 쓰지 않는다.
      expect(confirm.contains('srvAssertAttendancePolicyConfirmed('), isFalse,
          reason: '사업장 현재 기준이 확인됐다는 사실은 이 약속의 확인이 아니다');
      expect(confirm.contains('APPLICATION_POLICY_NOT_ACKNOWLEDGED') ||
          confirm.contains('cfmPolicyReason'), isTrue);
    });

    test('GATE-8 초대 수락도 지원서 기준으로 판정한다', () {
      final accept = _code(_callable(cfRaw, 'callableAcceptTOInvitation'));
      expect(
          accept.contains(
              'srvApplicationPolicyOwnership(freshData, invBizSnap.data())'),
          isTrue);
      expect(accept.contains('srvAttendancePolicyBlock(invBizSnap.data())'),
          isFalse,
          reason: '사업장이 기준을 바꿨다는 이유로 이미 보낸 초대의 수락이 막히면 안 된다');
      // 근로자 문구는 그대로 — 고용주 설정 내부를 알려주지 않는다.
      expect(accept.contains('지금은 수락할 수 없는 초대예요'), isTrue);
      // 수락 경로는 확인 기록을 쓰지 않는다(호출자가 근로자다).
      expect(accept.contains('srvBuildPolicyAcknowledgement('), isFalse);
    });

    test('GATE-9 대체근무 제안은 미확인 기준에서 막힌다', () {
      final offer = _code(_callable(cfRaw, 'callableOfferAlternativeWork'));
      expect(offer.contains('srvAssertAttendancePolicyConfirmed(offerBizData)'),
          isTrue, reason: '관리자가 능동적으로 새 조건을 제시하는 writer 다');
      // 사업장 문서는 권한 검증에서 이미 읽는다 — 추가 읽기를 만들지 않는다.
      expect(offer.contains('bizData: offerBizData} =\n      await assertBizAdmin('),
          isTrue);
    });

    test('GATE-10 기존 확정 근무·급여는 이 gate 에 걸리지 않는다', () {
      for (final name in [
        'callableCheckIn',
        'callableCheckOut',
        'callableConfirmFinalWage',
        'callableAcceptConfirmedReassignment',
      ]) {
        final body = _code(_callable(cfRaw, name));
        expect(body.contains('srvApplicationPolicyOwnership('), isFalse,
            reason: '$name 이 막히면 이미 성립한 약속의 이행이 멈춘다');
        expect(body.contains('srvAssertAttendancePolicyConfirmed('), isFalse);
      }
    });
  });

  group('offer — 제안 시점 기준이 고정된다', () {
    final offer = _code(_callable(cfRaw, 'callableOfferAlternativeWork'));

    test('OFFER-1 제안이 제안 시점 기준을 고정한다', () {
      expect(offer.contains('srvBuildAttendancePolicySnapshot(offerBizData)'),
          isTrue);
      expect(offer.contains('attendancePolicySnapshot: s,'), isTrue);
    });

    test('OFFER-2 제안이 확인 기록도 남긴다', () {
      expect(
          offer.contains('srvBuildPolicyAcknowledgement(s, callerUid)'), isTrue,
          reason: '조건을 제시한 것이 관리자의 채택이다 — 수락 때 사업장 기준이 '
              '바뀌어 있어도 약속의 책임 chain 이 끊기지 않는다');
    });

    test('OFFER-3 수락이 live 기준으로 덮지 않는다', () {
      final accept = _code(_callable(cfRaw, 'callableAcceptTOInvitation'));
      expect(
          accept.contains('if (freshData["attendancePolicySnapshot"] == null)'),
          isTrue, reason: '있으면 그대로 둬야 한다 — 근로자가 보고 수락한 조건이다');
    });

    test('INV-1 초대도 확인 기록을 남긴다', () {
      final invite = _code(_callable(cfRaw, 'callableInviteWorker'));
      expect(invite.contains('srvBuildAttendancePolicySnapshot(invBizData)'),
          isTrue);
      expect(invite.contains('srvBuildPolicyAcknowledgement(s, callerUid)'),
          isTrue);
    });
  });

  group('reassignment — 원 약속의 기준을 물려받는다', () {
    final reassign =
        _code(_callable(cfRaw, 'callableAcceptConfirmedReassignment'));

    test('RAS-1 원 약속의 기준과 확인을 물려받는다', () {
      expect(reassign.contains('srcData["attendancePolicySnapshot"]'), isTrue);
      expect(reassign.contains('srcData["attendancePolicyAcknowledgement"]'),
          isTrue,
          reason: 'A 를 확인한 기록이 B 의 확인이다 — 바뀌지 않은 조건에 새 채택 '
              '행위를 만들지 않는다');
    });

    test('RAS-2 재배치가 사업장 현재 기준을 읽지 않는다', () {
      expect(reassign.contains('srvBuildAttendancePolicySnapshot('), isFalse,
          reason: '재배치를 계기로 이미 성립한 약속의 계산 기준이 바뀌면 안 된다');
      expect(reassign.contains('attendanceRules'), isFalse);
      // 제안 writer 도 근태 기준을 새로 만들지 않는다 — 바뀌는 것이 아니다.
      final propose =
          _code(_callable(cfRaw, 'callableProposeConfirmedReassignment'));
      expect(propose.contains('attendancePolicySnapshot'), isFalse);
      expect(propose.contains('srvBuildAttendancePolicySnapshot('), isFalse);
    });

    test('RAS-3 근로자 시트가 기준 불변을 말한다', () {
      final sheet =
          _code(_src('lib/widgets/dialogs/confirmed_reassignment_sheet.dart'));
      expect(sheet.contains('근태·급여 처리 기준은 지금 확정된 근무와 동일하게 유지됩니다'),
          isTrue);
      // 사업장 현재 설정을 읽어 보여주지 않는다.
      expect(sheet.contains('attendanceRules'), isFalse);
    });
  });

  group('disclosure', () {
    test('DISC-8 근로자 수락 화면이 고정된 기준을 보여준다', () {
      final mine = _code(_src('lib/screens/user/my_applications_screen.dart'));
      expect(mine.contains('offerApp.attendancePolicySnapshot case final snap?'),
          isTrue);
      expect(mine.contains('_attendancePolicyBlock(snap)'), isTrue);
      // 사업장 문서를 다시 읽지 않는다.
      expect(mine.contains('getBusinessById'), isFalse,
          reason: '이미 지원서에 있는 값을 위해 왕복을 더하지 않는다');
      expect(mine.contains('이 기준은 이 근무에 고정됩니다'), isTrue);
    });

    test('DISC-9 관리자 확정 차단이 그 지원자에서 해결된다', () {
      for (final p in [
        'lib/screens/business_admin/dialogs/day_applicants_dialog.dart',
        'lib/screens/business_admin/dialogs/work_applicants_dialog.dart',
      ]) {
        final body = _code(_src(p));
        expect(
            body.contains(
                'PostingNotReadyReason.applicationPolicyNotAcknowledged'),
            isTrue, reason: '$p 에서 분기가 없다');
        expect(body.contains('ApplicationPolicyAcknowledgeSheet.show('), isTrue);
      }
      // 이유 코드가 사업장 설정 안내로 뭉개지지 않는다.
      expect(
          PostingNotReady.fromCode('APPLICATION_POLICY_NOT_ACKNOWLEDGED')
              ?.reason,
          PostingNotReadyReason.applicationPolicyNotAcknowledged);
      expect(
          const PostingNotReady(
                  PostingNotReadyReason.applicationPolicyNotAcknowledged)
              .message
              .contains('지원 당시 기준'),
          isTrue);
      // 재협상·소급변경이 아니라는 것을 화면이 말한다.
      final sheet = _code(
          _src('lib/widgets/dialogs/application_policy_acknowledge_sheet.dart'));
      expect(sheet.contains('조건은 바뀌지 않습니다'), isTrue);
      expect(sheet.contains('현재 사업장 기준 (이 근무에는 적용되지 않음)'), isTrue);
      // 권한이 없으면 할 수 없는 일을 시키지 않는다.
      expect(sheet.contains('사업장 관리자에게 확인을 요청해 주세요'), isTrue);
    });

    test('DISC-10 계약·근태는 같은 snapshot 을 쓴다', () {
      final svc = _code(_src('lib/services/contract_service.dart'));
      expect(
          svc.contains(
              'attendancePolicy: application.attendancePolicySnapshot'),
          isTrue);
      expect(svc.contains('attendanceRules'), isFalse);
      // 출퇴근·관리자 batch 는 지원서 snapshot 우선 helper 를 쓴다.
      final resolver = _code(_slice(
          cfRaw, 'function srvEffectiveAttendanceRules(', '\n/**'));
      expect(resolver.contains('attendancePolicySnapshot'), isTrue);
    });
  });

  group('변형 방어', () {
    test('MUT-3 조건을 무력화하는 형태를 막는다', () {
      expect(cf.contains('if (false'), isFalse);
      // 판정이 항상 통과하도록 꺾이지 않았다.
      final ownership = _code(_slice(
          cfRaw, 'function srvApplicationPolicyOwnership(', '\n/**'));
      expect('return null;'.allMatches(ownership).length, 2,
          reason: '통과 경로는 두 개(지원서 확인 · 현재 확인 일치)뿐이다');
      expect(ownership.trimRight().endsWith(
          'return "APPLICATION_POLICY_NOT_ACKNOWLEDGED";\n}'), isTrue,
          reason: '마지막은 거부여야 한다 (fail-closed)');
      // 반올림 산술 변경 0.
      final ci = _code(_slice(cfRaw, 'function _processCheckin(', '\n/**'));
      expect(ci.contains('Math.ceil(offsetMinutes / lateUnit) * lateUnit'),
          isTrue);
      final co = _code(_slice(cfRaw, 'function _processCheckout(', '\n/**'));
      expect(co.contains('Math.floor(offsetMinutes / overtimeUnit) * overtimeUnit'),
          isTrue);
      expect(co.contains('Math.ceil(earlyDiff / earlyLeaveUnit)'), isTrue);
    });
  });
}
