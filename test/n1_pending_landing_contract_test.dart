// [CROSS-DOMAIN-R5.1G.2A] N1 — newApplication이 지목하는 지원서
//
// 원본 계약(R5.1 §35 / R5.1A K):
//   newApplication → 관리자 → canManageTo → exact current PENDING Application
//
// R5.1G.2까지 DEV에는 현재 PENDING인 newApplication 알림이 하나도 없어
// "PENDING 지원서로 정확히 착지"만 런타임으로 밟지 못했다. 이번에 canonical
// apply writer(`callableApplyToTO`)로 1건을 만들어 끝까지 쟀다(PASS 20/0).
//
// 실측으로 확인한 것:
//   · apply → Application 1건, status=PENDING, 자연키 identity 정상
//     (`toId_slotId_wdId_uid`), 대기 +1, 좌석 불변
//   · 관리자 두 명(소유자·SUB_ADMIN)에게 newApplication 알림이 가고, 둘 다
//     방금 만든 **exact applicationId**와 일치하는 businessId를 담는다
//   · payload에는 status가 없다 — 목적지가 과거 상태를 믿을 수단 자체가 없다
//   · canManageTo를 회수하면 목적지 데이터 조회가 403
//   · 없는 id는 404, 다른 사업장 id는 403, 그 과정에서 상태 변화 0
//   · fixture(지원서·알림·카운터) 전부 원복
//
// 여기서는 그 계약이 소스에서 유지되는지를 고정한다. 화면 픽셀과 back-stack은
// R7 PRODUCT PENDING이다.

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

String _bodyOf(String raw, String signature) {
  final start = raw.indexOf(signature);
  if (start < 0) throw StateError('$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = raw.indexOf('(', start); i < raw.length; i++) {
    if (raw[i] == '(') paren++;
    if (raw[i] == ')') {
      paren--;
      if (paren == 0) { afterParams = i; break; }
    }
  }
  final open = raw.indexOf('{', afterParams);
  var depth = 0;
  for (var j = open; j < raw.length; j++) {
    if (raw[j] == '{') depth++;
    if (raw[j] == '}') {
      depth--;
      if (depth == 0) return raw.substring(start, j + 1);
    }
  }
  throw StateError('$signature 본문이 닫히지 않음');
}

const _cf = 'functions/src/index.ts';
const _notif = 'lib/screens/common/notification_screen.dart';

void main() {
  final rawCf = _codeOf(_src(_cf));
  final cf = _flat(rawCf);
  final notif = _load(_notif);

  group('N1 — 알림이 지원서 하나를 지목한다', () {
    test('지원서 id가 자연키다', () {
      // 실측 id: CW31…_cWqx…_HQ8e…_8xhv… (toId_slotId_wdId_uid)
      expect(cf.contains('const complexId'), true);
      expect(
          cf.contains('`\${toId}_\${slotId}_\${wdKey}_\${uid}`') ||
              cf.contains('`\${toId}_\${slotId}_\${discriminator}_\${uid}`'),
          true,
          reason: '한 근무 단위에 한 사람당 지원서 하나');
    });

    test('newApplication payload가 applicationId를 담는다', () {
      final i = rawCf.indexOf('type: "newApplication"');
      expect(i, greaterThan(-1));
      final seg = _flat(rawCf.substring(i, i + 700));
      expect(seg.contains('applicationId'), true);
      expect(seg.contains('businessId'), true);
    });

    test('payload에 status를 싣지 않는다', () {
      final i = rawCf.indexOf('type: "newApplication"');
      final seg = _flat(rawCf.substring(i, i + 700));
      expect(seg.contains('status:'), false,
          reason: '과거 상태를 실어 보내면 목적지가 그것을 믿을 수 있다');
    });
  });

  group('N1 — 목적지는 canManageTo를 요구한다', () {
    test('알림 라우트가 canManageTo로 막는다', () {
      final i = notif.indexOf('case NotificationType.newApplication:');
      expect(i, greaterThan(-1));
      final seg = notif.substring(i, i + 700);
      expect(seg.contains('requiredPermission: (p) => p.canManageTo,'), true);
    });

    test('목적지 데이터 조회도 서버에서 같은 권한을 요구한다', () {
      // 실측: 권한 회수 후 403 "지원서 조회 권한이 없습니다."
      expect(cf.contains('"지원서 조회 권한이 없습니다."'), true);
    });
  });

  group('N1 — 현재 상태를 다시 읽는다', () {
    test('확정 경로가 지원서를 서버에서 재조회한다', () {
      final body = _flat(_bodyOf(rawCf, 'export const callableConfirmApplication = onCall('));
      expect(body.contains('const appSnap = await appRef.get();'), true);
      expect(body.contains('if (!appSnap.exists) throw new HttpsError("not-found", '
          '"지원서를 찾을 수 없습니다.");'), true,
          reason: '실측: 없는 id → 404');
    });

    test('주장한 사업장과 다르면 없는 것과 같다', () {
      final body = _flat(_bodyOf(rawCf, 'export const callableConfirmApplication = onCall('));
      expect(body.contains('if (businessId !== claimedBusinessId) { '
          'throw new HttpsError("not-found", "지원서를 찾을 수 없습니다."); }'), true);
    });

    test('상태 전이는 현재 상태로 판정한다', () {
      final body = _flat(_bodyOf(rawCf, 'export const callableConfirmApplication = onCall('));
      expect(body.contains('if (!fresh.exists) throw new HttpsError("not-found", '
          '"지원서를 찾을 수 없습니다.");'), true,
          reason: '트랜잭션 안에서 다시 읽는다 — payload가 아니라 문서가 authority다');
      expect(body.contains('if (status === "REJECTED") throw new HttpsError('
          '"failed-precondition", "거절된 지원서는 확정할 수 없습니다.");'), true);
    });
  });

  group('N1 — 지원이 만드는 것', () {
    test('PENDING으로 만들고 대기 카운터만 올린다', () {
      final body = _flat(_bodyOf(rawCf, 'export const callableApplyToTO = onCall('));
      expect(body.contains('status: "PENDING"'), true);
      expect(body.contains('pendingCount: admin.firestore.FieldValue.increment(1)') ||
             body.contains('pendingCount`] = admin.firestore.FieldValue.increment(1)'), true);
    });

    test('좌석은 확정에서만 움직인다', () {
      final body = _flat(_bodyOf(rawCf, 'export const callableApplyToTO = onCall('));
      expect(body.contains('totalConfirmed: admin.firestore.FieldValue.increment(1)'), false,
          reason: '실측: 지원 후 좌석 0→0');
    });
  });
}
