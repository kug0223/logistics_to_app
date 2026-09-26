// [R5-F.1] 알림 type 문자열 · locator 정합성 계약.
//
//   지키는 문장은 하나다.
//
//     서버가 보내는 알림은 클라이언트가 알아들어야 한다.
//
//   서버 emitter 에서 type 문자열을 **전수 추출해** 파서와 대조한다.
//   목록을 손으로 적지 않는다 — 손으로 적으면 새 알림이 추가될 때 조용히
//   빠진다. 길을 만들지 않기로 한 알림은 이유와 함께 명시적으로 적는다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

/// 서버가 **알림 문서로** 쓰는 type 문자열 전수.
///   알림 문서는 title 을 갖는다 — 다른 용도의 `type:` 과 그것으로 가른다.
Set<String> serverEmittedTypes(String raw) {
  final lines = raw.split('\n');
  final re = RegExp(r'type: "([a-zA-Z_]+)"');
  final out = <String>{};
  for (var i = 0; i < lines.length; i++) {
    final m = re.firstMatch(lines[i]);
    if (m == null) continue;
    final lo = (i - 3).clamp(0, lines.length - 1);
    final hi = (i + 6).clamp(0, lines.length - 1);
    var hasTitle = false;
    for (var j = lo; j <= hi; j++) {
      if (lines[j].contains('title:')) hasTitle = true;
    }
    if (hasTitle) out.add(m.group(1)!);
  }
  return out;
}

/// 파서가 알아듣는 문자열 전수.
Set<String> parserRecognized(String modelSrc) =>
    RegExp(r"case '([A-Za-z_]+)':")
        .allMatches(modelSrc)
        .map((m) => m.group(1)!)
        .toSet();

/// 길을 만들지 않기로 한 알림 — 이유가 붙어야 목록에 남을 수 있다.
///   전부 "받는 사람이 할 일이 없는" 결과 통보다.
const informationalNoRoute = <String, String>{
  'confirmedReassignmentAccepted':
      '수락 결과 통보 — 받는 쪽이 더 할 일이 없다',
  'confirmedReassignmentDeclined':
      '거절 결과 통보 — 제안은 이미 끝났다',
  'confirmedReassignmentCanceled':
      '철회 통보 — 제안이 사라졌으므로 열 대상이 없다',
  'confirmedReassignmentSuperseded':
      '진행 불가 통보 — 제안이 무효가 됐다',
  'documentReviewed':
      '확인 결과 통보 — 보완이 필요하면 별도로 재등록 요청이 온다',
};

void main() {
  late String cfRaw;
  late String model;
  late String router;
  late Set<String> emitted;
  late Set<String> parsed;

  setUpAll(() {
    cfRaw = File('functions/src/index.ts').readAsStringSync();
    model = _codeOf(
        File('lib/models/core/notification_model.dart').readAsStringSync());
    router = _codeOf(
        File('lib/screens/common/notification_screen.dart').readAsStringSync());
    emitted = serverEmittedTypes(cfRaw);
    parsed = parserRecognized(model);
  });

  // ───────────────────────────────────────────────────────────
  group('F1-1x 전수 parity (§11)', () {
    test('F1-10 추출이 실제로 동작한다', () {
      // 추출이 비면 아래 대조가 통째로 무의미해진다.
      expect(emitted.length, greaterThan(30),
          reason: '서버 알림 type 을 ${emitted.length}개만 찾았다');
      expect(emitted.contains('applicationConfirmed'), isTrue);
      expect(emitted.contains('renewalProposal'), isTrue);
      expect(parsed.length, greaterThan(50));
    });

    test('F1-11 서버가 보내는 type 은 파서가 알아듣는다', () {
      final unknown = emitted
          .where((t) => !parsed.contains(t))
          .where((t) => !informationalNoRoute.containsKey(t))
          .toList()
        ..sort();
      expect(unknown, isEmpty,
          reason: '파서가 모르면 other 로 떨어져 눌러도 아무 데도 가지 않는다: '
              '$unknown');
    });

    test('F1-12 길 없는 알림은 암묵적이 아니라 명시적이다', () {
      // allowlist 에 적힌 것이 실제로 서버가 보내는 type 이어야 한다.
      //   없어진 type 이 목록에 남아 있으면 다음 사람이 오해한다.
      for (final t in informationalNoRoute.keys) {
        expect(emitted.contains(t), isTrue,
            reason: '$t 는 더 이상 발송되지 않는다 — 목록에서 빼야 한다');
      }
      // 그리고 전부 이유가 적혀 있어야 한다.
      for (final e in informationalNoRoute.entries) {
        expect(e.value.trim().isNotEmpty, isTrue, reason: e.key);
      }
    });
  });

  // ───────────────────────────────────────────────────────────
  group('F1-2x type 수정 (§12 A·B·F)', () {
    test('A 스케줄 변경 요청 — canonical 문자열을 알아듣는다', () {
      expect(cfRaw.contains('type: "scheduleChangeRequest"'), isTrue,
          reason: '서버가 보내는 canonical 문자열');
      expect(model.contains("case 'scheduleChangeRequest':"), isTrue);
      // 같은 의미로 모인다 — 새 enum 을 만들지 않았다.
      final i = model.indexOf("case 'scheduleChangeRequest':");
      expect(
        model.substring(i, i + 160)
            .contains('NotificationType.scheduleChangeRequested'),
        isTrue,
      );
    });

    test('F 이미 저장된 옛 문자열도 계속 열린다', () {
      expect(model.contains("case 'scheduleChangeRequested':"), isTrue,
          reason: '과거 알림 역직렬화 호환을 깨지 않는다');
    });

    test('A2 목적지는 기존에 검증된 관리자 경로 그대로다', () {
      final i = router.indexOf('case NotificationType.scheduleChangeRequested:');
      expect(i, greaterThan(-1));
      final body = router.substring(i, i + 900);
      expect(body.contains('_validateAdminNotificationAccess'), isTrue);
      expect(body.contains('p.canManageWorkers'), isTrue,
          reason: '현재 권한으로 다시 판정한다 — payload 를 믿지 않는다');
    });

    test('B 확정 근무 변경 제안 — 파서·라우터가 모두 안다', () {
      expect(model.contains("case 'confirmedReassignmentProposed':"), isTrue);
      expect(
        router.contains('case NotificationType.confirmedReassignmentProposed:'),
        isTrue,
      );
    });

    test('B2 서류 재등록 요청 — 파서·라우터가 모두 안다', () {
      expect(model.contains("case 'documentReuploadRequested':"), isTrue);
      expect(
        router.contains('case NotificationType.documentReuploadRequested:'),
        isTrue,
      );
    });

    test('G 정말 모르는 type 은 조용히 멈춘다', () {
      expect(model.contains('default: return NotificationType.other;'), isTrue);
      final i = router.indexOf('case NotificationType.other:');
      expect(i, greaterThan(-1));
      expect(router.substring(i, i + 160).contains('break;'), isTrue,
          reason: '모르는 알림으로 아무 화면이나 열지 않는다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('F1-3x locator (§13)', () {
    test('확정 변경 제안은 살아 있는 원 지원으로 간다', () {
      // 서버 payload 가 sourceApplicationId 를 담는다.
      final i = cfRaw.indexOf('type: "confirmedReassignmentProposed"');
      expect(i, greaterThan(-1));
      final payload = cfRaw.substring(i, i + 520);
      expect(payload.contains('sourceApplicationId'), isTrue);
      expect(payload.contains('proposalId'), isTrue);
      // 라우터가 그 키를 쓴다 — 없는 ID 를 지어내지 않는다.
      final r = router.indexOf(
          'case NotificationType.confirmedReassignmentProposed:');
      expect(router.substring(r, r + 420).contains("'sourceApplicationId'"),
          isTrue);
    });

    test('스케줄 변경은 businessId 로 사업장을 지목한다', () {
      final i = cfRaw.indexOf('type: "scheduleChangeRequest"');
      expect(cfRaw.substring(i, i + 320).contains('businessId'), isTrue);
    });

    test('서류 재등록은 목록 landing 이면 충분하다', () {
      // 근로자 본인의 서류 화면이라 entity focus 가 필요 없다.
      final r = router.indexOf(
          'case NotificationType.documentReuploadRequested:');
      final body = router.substring(r, r + 300);
      expect(body.contains('DocumentManagementScreen()'), isTrue);
      expect(body.contains('focus'), isFalse,
          reason: '없는 focus 파라미터를 발명하지 않는다');
    });

    test('타 사업장 locator 는 여전히 권한에서 막힌다', () {
      final i = router.indexOf('case NotificationType.scheduleChangeRequested:');
      final body = router.substring(i, i + 900);
      expect(body.contains('businessId: schedBizId'), isTrue);
      expect(body.contains('_handleAdminAccess(access)'), isTrue,
          reason: 'payload 의 사업장으로 현재 권한을 다시 본다');
    });
  });

  // ───────────────────────────────────────────────────────────
  group('F1-4x 무회귀 (§2)', () {
    test('type 이 screen 보다 우선한다', () {
      expect(
        router.contains("(payload['type'] ?? payload['screen'])?.toString()"),
        isTrue,
      );
    });

    test('세 알림이 행동 필요 집합에 들어갔다', () {
      final i = model.indexOf('_actionRequiredTypes');
      expect(i, greaterThan(-1));
      final body = model.substring(i, i + 1400);
      expect(body.contains('NotificationType.confirmedReassignmentProposed'),
          isTrue);
      expect(body.contains('NotificationType.documentReuploadRequested'),
          isTrue);
      expect(body.contains('NotificationType.scheduleChangeRequested'), isTrue);
    });

    test('서버 emitter 를 건드리지 않았다', () {
      // 이번 수정은 클라이언트 쪽이다 — 발송 문자열·payload 는 그대로다.
      expect(cfRaw.contains('type: "scheduleChangeRequest"'), isTrue);
      expect(cfRaw.contains('type: "confirmedReassignmentProposed"'), isTrue);
      expect(cfRaw.contains('type: "documentReuploadRequested"'), isTrue);
    });
  });
}
