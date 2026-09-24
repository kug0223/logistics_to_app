// [WORKER-CONTRACT-EXPIRY-NOTICE]
//
//   계약 만료를 미리 듣는 사람은 **관리자뿐**이었다. D-15
//   contractExpiringReminder 는 businesses.adminIds 로만 간다.
//
//   실제로 끝났다는 통지도 `renewalDecision = TERMINATE` 인 경우에만
//   갔다(contractTerminating). 아무도 결정하지 않은 채 만료된 관계 —
//   .4B 가 다룬 바로 그 상태 — 에서는 근로자에게 아무 말도 하지 않았다.
//   근로자 입장에서는 계약이 조용히 사라진다.
//
//   그래서 근로자에게도 말한다. 다만 **정보**이지 할 일이 아니다.
//
//       계약 종료 예정 / 계약 종료   = Notification
//       연장 제안 수락·거절          = Task (renewalProposal flow)
//
//   그리고 같은 D+1 이라도 관계의 상태가 다르다. 한 문장으로 뭉치면
//   거짓이 된다 — 내일부터 계약이 이어지는 사람에게 "종료되었습니다"
//   만 보내면 새 약속을 부정하는 말이 된다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/notification_model.dart';

const _cfPath = 'functions/src/index.ts';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 주석 줄을 지운 본문. 앵커는 주석이 아니라 **코드**여야 한다.
String _codeOf(String s) =>
    s.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _after(String src, String name, int chars) {
  final i = src.indexOf(name);
  if (i < 0) throw StateError('$name 를 찾지 못함');
  return src.substring(i, (i + chars).clamp(0, src.length));
}

void main() {
  final cf = _codeOf(_src(_cfPath));
  final expiring =
      _after(cf, 'async function srvNotifyWorkerContractExpiring(', 1881);
  final ended =
      _after(cf, 'async function srvNotifyWorkerContractEnded(', 2895);
  final scheduler =
      _after(cf, 'async function processContractRenewalChecks(', 22642);

  // ══════════════════════════════════════════════════════════════
  // 01. 기존 알림과 겹치지 않는다 (§4·§22·§46)
  // ══════════════════════════════════════════════════════════════
  group('01. 기존 emitter 보존', () {
    test('01-a D-15 관리자 알림은 그대로다', () {
      expect(scheduler, contains('type: "contractExpiringReminder"'));
      expect(scheduler, contains('tx.update(doc.ref, {renewalNotifiedAt: now});'));
    });

    test('01-b 관리자 dedupe 필드를 근로자 알림이 쓰지 않는다', () {
      // 한 필드가 두 수신자를 동시에 의미하면 한쪽이 조용히 누락된다.
      expect(expiring.contains('renewalNotifiedAt'), false);
      expect(ended.contains('renewalNotifiedAt'), false);
      expect(ended.contains('terminationCompletionNotifiedAt'), false);
    });

    test('01-c 종료 결정 건은 contractTerminating 이 이미 알린다', () {
      expect(scheduler, contains('type: "contractTerminating"'));
      // 그래서 근로자 종료 알림에서는 제외한다 — 중복 통지 금지.
      expect(ended, contains('if (a.renewalDecision === "TERMINATE") return false;'));
    });

    test('01-d 연장 제안 알림과 역할을 합치지 않는다', () {
      for (final s in [expiring, ended]) {
        expect(s.contains('renewalProposal'), false);
        expect(s.contains('proposalId'), false);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 02. 창을 새로 만들지 않았다 (§8)
  // ══════════════════════════════════════════════════════════════
  group('02. timing', () {
    test('02-a 기존 D-15 / D+1 창을 그대로 쓴다', () {
      expect(scheduler,
          contains('srvNotifyWorkerContractExpiring(d15Snap.docs, now)'));
      expect(scheduler,
          contains('srvNotifyWorkerContractEnded(d0Snap.docs, now)'));
    });

    test('02-b 새 cadence(D-7 · D-14 등)를 만들지 않았다', () {
      for (final banned in ['+ 7 * 24', '+ 14 * 24', '+ 3 * 24']) {
        expect(expiring.contains(banned), false, reason: banned);
        expect(ended.contains(banned), false, reason: banned);
      }
    });

    test('02-c 종료 알림은 D 가 아니라 D+1 창에서 나온다', () {
      // d0Snap 은 **어제** 만료된 건이다 — D 당일에는 보내지 않는다.
      expect(scheduler, contains('d0StartKST.setDate(d0StartKST.getDate() - 1)'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 03. 종료 예정 (§7·§9·§36·§38)
  // ══════════════════════════════════════════════════════════════
  group('03. 종료 예정', () {
    test('03-a 장기 근무관계만 대상이다', () {
      expect(expiring,
          contains('!Array.isArray(app.workDays) || app.workDays.length === 0'));
    });

    test('03-b 이미 결정된 관계에는 보내지 않는다', () {
      expect(expiring, contains('if (app.renewalDecision) continue;'));
    });

    test('03-c 퇴사·해지 승인 건은 제외한다', () {
      expect(expiring, contains('done.includes(app.resignStatus as string)'));
      expect(expiring, contains('done.includes(app.terminationStatus as string)'));
    });

    test('03-d 보내기 직전 종료일을 다시 본다 — 바뀌었으면 보내지 않는다', () {
      expect(expiring, contains('if (endNum !== targetNum) continue;'));
      expect(expiring, contains('srvKstDateNum(end.toDate())'));
    });

    test('03-e 종료 기준은 canonical effectiveEnd 다', () {
      expect(expiring, contains('(app.actualResignDate ?? app.workEndDate)'));
    });

    test('03-f 문구는 기간만 말한다', () {
      expect(expiring, contains('title: "계약 종료 예정"'));
      expect(expiring, contains('연장 여부가 결정되면 별도로 안내됩니다.'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 04. 상태별 종료 문구 (§12~§20·§52)
  // ══════════════════════════════════════════════════════════════
  group('04. 종료 matrix', () {
    test('04-a F 연속 연장(E = D+1)은 보내지 않는다', () {
      // 내일부터 이어지는 사람에게 "종료되었습니다"만 보내면 새 약속을
      //   부정하는 말이 된다. 새 약속은 renewal/계약 알림이 전한다.
      expect(ended, contains('if (startNum <= endNum + 1) continue;'));
    });

    test('04-b G 나중 시작 연장은 공백과 시작일을 말한다', () {
      expect(ended, contains('새 계약은 \${srvKstMd(newStart.toDate())}부터 시작됩니다.'));
    });

    test('04-c B 응답 대기 제안이 있으면 그 사실을 함께 말한다', () {
      expect(ended, contains('확인 중인 연장 제안은 별도로 처리할 수 있습니다.'));
      expect(ended, contains('waiting.has(doc.id)'));
    });

    test('04-d A/C/D/E 미결정·만료·거절·취소는 평범한 종료 안내', () {
      expect(ended, contains('새로운 근무 일정이 확정되면 다시 안내드립니다.'));
    });

    test('04-e H TERMINATE 는 제외된다', () {
      expect(ended, contains('a.renewalDecision === "TERMINATE"'));
    });

    test('04-f 세 문구가 모두 "기존 계약기간"으로 말한다', () {
      expect('기존 계약기간이'.allMatches(ended).length, 3);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 05. 만료된 제안을 "확인 중"이라 하지 않는다 (§15·§56)
  // ══════════════════════════════════════════════════════════════
  group('05. stale proposal', () {
    test('05-a derived 판정 helper 를 쓴다 — 저장 상태만 보지 않는다', () {
      expect(ended, contains('srvOldAppsWithActiveProposal('));
      final h = _after(cf, 'async function srvOldAppsWithActiveProposal(', 1600);
      expect(h, contains('srvRenewalProposalEffectiveStatus(data, now)'));
    });

    test('05-b 판정 시각은 실행 시각이다', () {
      expect(ended, contains('const nowDate = now.toDate();'));
      expect(ended, contains('candidates.map((d) => d.id), nowDate)'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 06. 추측하지 않는다 (§21·§39·§40)
  // ══════════════════════════════════════════════════════════════
  group('06. 재조회', () {
    test('06-a 연장 여부를 추측하지 않고 신규 지원서를 읽는다', () {
      expect(ended, contains('app.renewedToApplicationId as string | undefined'));
      expect(ended, contains('await db.collection("applications").doc(newId).get()'));
    });

    test('06-b 신규 시작일도 canonical 로 읽는다', () {
      expect(ended, contains('(n.desiredStartDate ?? n.workDate)'));
    });

    test('06-c 신규 지원서를 못 읽으면 보내지 않는다 — 지어내지 않는다', () {
      expect(ended, contains('if (!newSnap.exists) continue;'));
      expect(ended, contains('if (!newStart) continue;'));
    });

    test('06-d 공고 현재 값을 읽지 않는다', () {
      for (final banned in ['collection("tos")', 'workDetails']) {
        expect(ended.contains(banned), false, reason: banned);
        expect(expiring.contains(banned), false, reason: banned);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 07. dedupe (§30~§32·§42·§50)
  // ══════════════════════════════════════════════════════════════
  group('07. dedupe', () {
    test('07-a 결정적 문서 id + create() 로 한 번만 보낸다', () {
      expect(expiring, contains(r'worker_contract_expiring_${doc.id}_${dayKey}'));
      expect(ended, contains(r'worker_contract_ended_${doc.id}_'));
      expect(expiring, contains('.create({'));
      expect(ended, contains('.create({'));
    });

    test('07-b 재시도에서 ALREADY_EXISTS 는 정상이다', () {
      expect(expiring, contains('if ((e as {code?: number})?.code === 6) continue;'));
      expect(ended, contains('if ((e as {code?: number})?.code === 6) continue;'));
    });

    test('07-c dedupe key 에 applicationId 가 들어간다 — 같은 날 여러 계약', () {
      // worker + date 만으로 만들면 같은 날 두 사업장 만료가 하나로 뭉친다.
      expect(expiring, contains(r'${doc.id}_'));
      expect(ended, contains(r'${doc.id}_'));
    });

    test('07-d 새 source-of-truth 필드를 만들지 않았다', () {
      for (final banned in [
        'workerExpiringNotifiedAt', 'workerEndedNotifiedAt',
      ]) {
        expect(cf.contains(banned), false, reason: banned);
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 08. 상태를 바꾸지 않는다 (§34·§35·§58)
  // ══════════════════════════════════════════════════════════════
  group('08. no mutation', () {
    test('08-a 두 emitter 가 도메인 상태를 쓰지 않는다', () {
      for (final s in [expiring, ended]) {
        expect(s.contains('renewalDecision:'), false);
        expect(s.contains('tx.update'), false);
        expect(s.contains('.update({'), false);
        expect(s.contains('collection("attendance")'), false);
      }
    });

    test('08-b 새 지원서를 만들지 않는다', () {
      for (final s in [expiring, ended]) {
        expect(s.contains('collection("applications").doc()'), false);
        expect(s.contains('CONTRACT_PENDING'), false);
      }
    });

    test('08-c 자동 연장이 되살아나지 않았다 — 회귀 고정', () {
      expect(scheduler.contains('status: "CONFIRMED"'), false);
      expect(scheduler.contains('renewalDecision: "EXTEND"'), false);
      expect(scheduler, contains('자동 연장하지 않음 (AUTO-RENEW-POLICY)'));
    });

    test('08-d 알림 실패가 다른 건을 막지 않는다', () {
      expect(expiring, contains('나머지 계속'));
      expect(ended, contains('나머지 계속'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 09. 문구 (§11·§23·§45)
  // ══════════════════════════════════════════════════════════════
  group('09. copy', () {
    test('09-a 법적 단정 문구를 쓰지 않는다', () {
      for (final banned in [
        '근로관계 종료', '고용 종료', '퇴사 처리', '해고', '재입사',
        '계속근로가 단절',
      ]) {
        expect(expiring.contains(banned), false, reason: banned);
        expect(ended.contains(banned), false, reason: banned);
      }
    });

    test('09-b 사업장과 날짜를 말한다', () {
      expect(ended, contains('const bizName ='));
      expect(ended, contains('const endMd = srvKstMd(end.toDate());'));
    });

    test('09-c 날짜는 KST 달력일로 말한다', () {
      final md = _after(cf, 'function srvKstMd(', 300);
      expect(md, contains('SRV_KST_MS'));
      expect(md, contains('getUTCMonth'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 10. 수신자 · 사업장 (§25·§26·§41)
  // ══════════════════════════════════════════════════════════════
  group('10. recipient', () {
    test('10-a 수신자는 원본 지원서의 근로자다', () {
      expect(expiring, contains('const uid = app.uid as string | undefined;'));
      expect(ended, contains('const uid = app.uid as string;'));
      expect(expiring, contains('db.collection("users").doc(uid)'));
      expect(ended, contains('db.collection("users").doc(uid)'));
    });

    test('10-b payload 가 그 관계를 정확히 가리킨다', () {
      for (final s in [expiring, ended]) {
        expect(s, contains('applicationId: doc.id'));
        expect(s, contains('businessId: app.businessId'));
      }
    });

    test('10-c payload key 가 허용 목록 안이다', () {
      final allowed = _after(cf, 'const allowedDataKeys = new Set([', 400);
      for (final k in ['applicationId', 'businessId', 'expiryDate', 'screen']) {
        expect(allowed, contains('"$k"'), reason: k);
      }
    });

    test('10-d 개인 카테고리로 간다', () {
      expect(expiring, contains('category: "personal"'));
      expect(ended, contains('category: "personal"'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 11. Notification ≠ Task (§1·§29·§49·§55)
  // ══════════════════════════════════════════════════════════════
  group('11. task 아님', () {
    test('11-a 새 Home Task 타입을 만들지 않았다', () {
      for (final banned in [
        'contractEndingTask', 'contractEndedTask', 'workerContractTask',
      ]) {
        expect(cf.contains(banned), false, reason: banned);
      }
    });

    test('11-b 근로자 홈 Task 의 출처는 여전히 제안 문서다', () {
      final home = _codeOf(_src('lib/screens/user/user_home_screen.dart'));
      expect(home, contains('getMyRenewalProposals()'));
      expect(home.contains('workerContractEnded'), false);
      expect(home.contains('workerContractExpiring'), false);
    });

    test('11-c 알림 화면 routing 에 수락/거절 CTA 가 없다', () {
      final scr = _codeOf(_src('lib/screens/common/notification_screen.dart'));
      final at = scr.indexOf('case NotificationType.workerContractExpiring:');
      expect(at, isNot(-1));
      final seg = scr.substring(at, at + 500);
      expect(seg.contains('acceptRenewalProposal'), false);
      expect(seg.contains('RenewalProposalScreen'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 12. 타입 등록 (§47·§48)
  // ══════════════════════════════════════════════════════════════
  group('12. type', () {
    test('12-a 서버 whitelist 에 등록됐다', () {
      expect(cf, contains('"workerContractExpiring", "workerContractEnded"'));
    });

    test('12-b 서버 routing 카테고리가 있다', () {
      expect(cf, contains('workerContractExpiring: "contractAlert"'));
      expect(cf, contains('workerContractEnded: "contractAlert"'));
    });

    test('12-c Dart enum · 직렬화 양쪽에 등록됐다', () {
      // 직렬화 helper 는 private 이라 소스로 고정한다 — 한쪽만 등록하면
      //   저장은 되는데 읽을 때 사라진다.
      final nm = _codeOf(_src('lib/models/core/notification_model.dart'));
      for (final t in ['workerContractExpiring', 'workerContractEnded']) {
        expect(nm, contains("case '$t':"), reason: 'from $t');
        expect(nm, contains("return '$t';"), reason: 'to $t');
      }
      expect(NotificationType.values,
          contains(NotificationType.workerContractExpiring));
      expect(NotificationType.values,
          contains(NotificationType.workerContractEnded));
    });

    test('12-d 관리자 타입과 다른 타입이다 — 의미를 합치지 않았다', () {
      expect(NotificationType.workerContractExpiring,
          isNot(NotificationType.contractExpiringReminder));
      expect(NotificationType.workerContractEnded,
          isNot(NotificationType.contractTerminating));
    });
  });
}
