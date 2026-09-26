// [R5-F] 계약 종료 알림 문구 계약.
//
//   지키는 문장은 하나다.
//
//     알림은 그때 일어난 일의 기록이지 지금 상태가 아니다.
//
//   그래서 문구는 ① 읽는 시점의 도메인 상태를 단정하지 않고,
//   ② 이 알림이 갈 수 없는 곳의 행동을 암시하지 않아야 한다.
//
//   이번 수정은 문구만이다. 발송 조건·수신자·목적지·중복키는 그대로다 —
//   그 사실도 함께 고정한다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  expect(i, greaterThan(-1), reason: '$name 을 찾지 못했다');
  final e = (i + chars) > src.length ? src.length : i + chars;
  return src.substring(i, e);
}

void main() {
  late String cf;
  late String ended;

  setUpAll(() {
    cf = _codeOf(File('functions/src/index.ts').readAsStringSync());
    ended = _after(cf, 'async function srvNotifyWorkerContractEnded(', 3400);
  });

  // ───────────────────────────────────────────────────────────
  group('F-1x 종료 알림 문구 (§9 A·B·C)', () {
    test('A 지금 제안이 확인 중이라고 단정하지 않는다', () {
      expect(ended.contains('확인 중인 연장 제안'), isFalse,
          reason: '보낼 때의 상태를 얼려 단정하면 읽는 시점에 거짓이 된다');
      for (final asserting in <String>[
        '검토 중인 연장', '대기 중인 연장 제안이 있습니다', '연장 제안이 진행 중',
      ]) {
        expect(ended.contains(asserting), isFalse, reason: asserting);
      }
    });

    test('B 제안을 처리할 수 있다고 단정하지 않는다', () {
      expect(ended.contains('별도로 처리할 수 있습니다'), isFalse);
      for (final action in <String>[
        '수락하', '거절하', '지금 응답', '여기서 처리',
      ]) {
        expect(ended.contains(action), isFalse, reason: action);
      }
    });

    test('C proposalId 가 없는 payload 다 — 제안 전용 CTA 를 쓸 수 없다', () {
      // 이 알림의 data 에 proposalId 가 없다는 사실이 근거다.
      final dataBlock = ended.substring(ended.indexOf('type: "workerContractEnded"'));
      final head = dataBlock.substring(0, 420);
      expect(head.contains('applicationId: doc.id'), isTrue);
      expect(head.contains('proposalId'), isFalse,
          reason: '제안을 지목할 수 없으니 제안 행동을 말하면 안 된다');
    });

    test('C2 대신 현재 상태를 다시 보게 한다', () {
      expect(ended.contains('연장 제안이 있는 경우'), isTrue,
          reason: '있다/없다를 단정하지 않는 조건부 서술');
      expect(ended.contains('현재 상태는 앱에서 확인할 수 있습니다'), isTrue);
    });

    test('C3 일어난 일 자체는 그대로 말한다', () {
      expect(ended.contains('기존 계약기간이'), isTrue);
      expect(ended.contains('종료되었습니다'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('F-2x 문구 외에는 바꾸지 않았다 (§9 D·E·F·G)', () {
    test('D 목적지가 그대로다', () {
      expect(ended.contains('screen: "mySchedule"'), isTrue);
      expect(ended.contains('screen: "renewalProposal"'), isFalse,
          reason: '목적지를 바꾸는 것은 이번 범위가 아니다');
    });

    test('E 수신자가 그대로다', () {
      expect(ended.contains('collection("users").doc(uid)'), isTrue);
      expect(ended.contains('userId: uid'), isTrue);
      expect(ended.contains('category: "personal"'), isTrue);
    });

    test('F 중복키가 그대로다', () {
      expect(
        ended.contains(
            '.doc(`worker_contract_ended_${r'$'}{doc.id}_'
            '${r'$'}{srvKstDateKey(end.toDate())}`)'),
        isTrue,
      );
      expect(ended.contains('.create({'), isTrue,
          reason: 'create 실패(code 6)로 중복을 막는 방식 유지');
    });

    test('G 발송 조건이 그대로다', () {
      // 후보 필터 — 관리자 종료 결정·퇴사/해지 효력 경로 제외.
      expect(ended.contains('a.renewalDecision === "TERMINATE"'), isTrue);
      expect(ended.contains('done.includes(a.resignStatus as string)'), isTrue);
      expect(ended.contains('done.includes(a.terminationStatus as string)'),
          isTrue);
      // 분기 선택은 여전히 "지금 유효한" 제안으로 판정한다.
      expect(ended.contains('srvOldAppsWithActiveProposal('), isTrue);
      expect(ended.contains('waiting.has(doc.id)'), isTrue);
      // 연장이 이어지는 경우의 침묵 규칙도 그대로.
      expect(ended.contains('startNum <= endNum + 1'), isTrue);
    });

    test('G2 세 갈래 구조가 유지된다', () {
      expect(ended.contains('app.renewalDecision === "EXTEND"'), isTrue);
      expect(ended.contains('새로운 근무 일정이 확정되면 다시 안내드립니다'), isTrue);
    });
  });

  // ───────────────────────────────────────────────────────────
  group('F-3x 인접 알림 무회귀 (§9 H·I·J)', () {
    test('H 제안 알림은 실제 행동 경로를 유지한다', () {
      final prop = _after(cf, 'type: "renewalProposal"', 500);
      expect(prop.contains('proposalId: a.proposalId'), isTrue);
      expect(prop.contains('screen: "renewalProposal"'), isTrue);
    });

    test('H2 제안 화면은 payload 가 아니라 현재 상태를 읽는다', () {
      final screen = _codeOf(
          File('lib/screens/user/renewal_proposal_screen.dart')
              .readAsStringSync());
      expect(screen.contains('_svc.getMyRenewalProposals()'), isTrue);
      expect(screen.contains('isActionableAt(now)'), isTrue);
    });

    test('I 알림은 할 일이 아니다 — 홈 카드는 제안 문서가 근거다', () {
      final home = File('lib/screens/user/user_home_screen.dart')
          .readAsStringSync();
      expect(home.contains('[RENEWAL-PROPOSAL-COMMITMENT] 연장 제안 할 일 카드'),
          isTrue);
      expect(home.contains('source 는 알림이 아니라 제안 문서다'), isTrue);
    });

    test('J type 이 screen 보다 우선한다 (prior 계약)', () {
      final n = _codeOf(File('lib/screens/common/notification_screen.dart')
          .readAsStringSync());
      expect(
        n.contains("(payload['type'] ?? payload['screen'])?.toString()"),
        isTrue,
        reason: 'type = canonical identity, screen = legacy alias',
      );
    });

    test('J2 네 계약 알림이 같은 semantic 으로 묶여 있다', () {
      for (final t in <String>[
        'workerContractEnded: "contractAlert"',
        'workerContractExpiring: "contractAlert"',
        'renewalProposal: "contractAlert"',
        'contractTerminating:       "contractAlert"',
      ]) {
        expect(cf.contains(t), isTrue, reason: t);
      }
    });

    test('J3 인접 두 알림 문구는 건드리지 않았다', () {
      // 종료 예정 — 단정도 행동 암시도 없다(원래부터).
      expect(cf.contains('연장 여부가 결정되면 별도로 안내됩니다'), isTrue);
      // 종료 완료(관리자 결정 경로).
      expect(cf.contains('계약이 종료되었습니다. 이용해 주셔서 감사합니다'), isTrue);
    });
  });
}
