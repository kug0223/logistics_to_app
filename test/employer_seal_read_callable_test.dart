// [R7-P4.4E.3B] 하위관리자가 고용주 날인 상태를 **안전하게** 알 수 있다.
//
//   날인은 `users/{ownerId}.sealBase64` 에 있고 그 문서는 본인과
//   SUPER_ADMIN 만 읽는다(firestore.rules). 그래서 SubAdmin 은 영영
//   모름(UNKNOWN)에 머물렀고, 화면은 그 모름을 '미등록' 으로 말하거나
//   본인 날인을 고용주 날인인 것처럼 보여 줬다(P4.4E.3A 에서 멈춤).
//
//   이제 서버가 **있는지 여부만** 답한다. 이 파일의 계약은 두 가지다 —
//   값이 새지 않을 것, 그리고 공고 gate 와 같은 술어를 쓸 것.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _cf() => File('functions/src/index.ts').readAsStringSync();
String _resolver() =>
    File('lib/services/business_posting_readiness.dart').readAsStringSync();
String _settings() =>
    File('lib/screens/common/settings_screen.dart').readAsStringSync();

/// onCall export 의 **핸들러 본문**만 — 옵션 객체에서 멈추지 않게 센다.
String _handler(String src, String name) {
  final start = src.indexOf('export const $name = onCall');
  expect(start, greaterThan(-1), reason: '$name 을 찾지 못했다');
  final h = src.indexOf('async (request', start);
  expect(h, greaterThan(start));
  final open = src.indexOf('{', h);
  var depth = 0;
  for (var i = open; i < src.length; i++) {
    if (src[i] == '{') depth++;
    if (src[i] == '}') {
      depth--;
      if (depth == 0) return src.substring(open, i + 1);
    }
  }
  return src.substring(open);
}

void main() {
  late final String cf = _cf();
  late final String body =
      _handler(cf, 'callableGetEmployerSealReadiness');

  group('[R7-P4.4E.3B] 서버 — 권한', () {
    test('EMP-SEAL-READ-01 로그인하지 않으면 거부한다', () {
      expect(body.contains('if (!request.auth)'), isTrue);
      expect(body.contains('"unauthenticated"'), isTrue);
    });

    test('EMP-SEAL-READ-02 관계없는 사업장이면 거부한다', () {
      expect(body.contains('await assertBizAdmin(callerUid, businessId)'), isTrue,
          reason: 'businessId 를 안다는 것만으로 읽히면 안 된다');
      // 소속 판정기 자체는 owner·adminIds·subAdminBusinessIds 를 본다.
      final i = cf.indexOf('async function assertBizAdmin');
      final gate = cf.substring(i, i + 3000);
      expect(gate.contains('adminIds'), isTrue);
      expect(gate.contains('subAdminBusinessIds'), isTrue);
    });

    test('EMP-SEAL-READ-02b 새 permission 을 만들지 않았다', () {
      // 기존 소속 판정만 쓴다 — canManageTo/canManageContract 중 하나로
      // 좁히면 공고 권한만 가진 SubAdmin 이 공고 준비 상태를 못 본다.
      expect(body.contains('canManageContract'), isFalse);
      expect(body.contains('canManageTo'), isFalse);
    });

    test('EMP-SEAL-READ-08 없는 사업장은 fail closed 다', () {
      final i = cf.indexOf('async function assertBizAdmin');
      expect(
          cf
              .substring(i, i + 3000)
              .contains('"not-found", "사업장을 찾을 수 없습니다."'),
          isTrue);
    });

    test('EMP-SEAL-READ-09 App Check 를 이 callable 만 열지 않았다', () {
      final decl = cf.substring(
          cf.indexOf('export const callableGetEmployerSealReadiness'),
          cf.indexOf('async (request',
              cf.indexOf('export const callableGetEmployerSealReadiness')));
      expect(decl.contains('enforceAppCheck: true'), isTrue);
    });
  });

  group('[R7-P4.4E.3B] 서버 — 값이 새지 않는다', () {
    test('EMP-SEAL-READ-06 응답은 boolean 하나다', () {
      expect(body.contains('return {employerSealReady: ready};'), isTrue);
      // 날인 값·소유자 식별자는 응답에도 로그에도 없다.
      //   주석은 제외한다 — 무엇을 내보내지 않는지 적어 둔 설명까지
      //   금지하면 근거를 남길 수 없다. 계약은 **실행되는 코드**에 대한 것이다.
      final code = body
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code.contains('sealBase64'), isFalse,
          reason: '원문이 핸들러 안에 등장하면 새어 나갈 길이 생긴다');
      expect(code.contains('ownerId'), isFalse,
          reason: '다른 관리자 UID 를 돌려주지 않는다 (SEC-20 과 같은 이유)');
      expect(code.contains('console.'), isFalse, reason: '로그로도 남기지 않는다');
    });

    test('EMP-SEAL-READ-07 클라이언트가 owner 를 지목할 수 없다', () {
      // 입력은 businessId 뿐 — ownerId/targetUid 를 받지 않는다.
      expect(body.contains('request.data as {businessId?: string}'), isTrue);
      expect(body.contains('targetUid'), isFalse);
      // 서버가 businessId → 사업장 문서 → owner 로 스스로 간다.
      expect(body.contains('employerSealPresent(bizData, dbReadinessReader)'),
          isTrue);
    });
  });

  group('[R7-P4.4E.3B] 서버 — 공고 gate 와 같은 술어', () {
    test('EMP-SEAL-READ-10 날인 판정이 한 벌이다', () {
      expect(cf.contains('async function employerSealPresent('), isTrue);
      // 공고/계약 gate 도 같은 helper 를 쓴다 — 손으로 복제하지 않았다.
      expect(cf.contains('if (!(await employerSealPresent(bizData, reader)))'),
          isTrue);
      // 추출 전 인라인 판정이 남아 있지 않다.
      expect('ownerSnap.data()?.sealBase64'.allMatches(cf).length, 1,
          reason: '두 곳에서 따로 판정하면 언젠가 갈라진다');
    });

    test('EMP-SEAL-READ-10b owner 의 날인을 본다 — 호출자가 아니다', () {
      final i = cf.indexOf('async function employerSealPresent(');
      final fn = cf.substring(i, i + 700);
      expect(fn.contains('bizData?.ownerId'), isTrue);
      expect(fn.contains('request.auth'), isFalse);
    });
  });

  group('[R7-P4.4E.3B] 클라이언트 — 상태 의미', () {
    test('SEAL-READ-CLIENT-01/02 서버가 답하면 모름이 아니다', () {
      final i = _resolver().indexOf('final viaServer =');
      final blk = _resolver().substring(i, i + 500);
      expect(blk.contains('if (viaServer == null)'), isTrue);
      expect(blk.contains('employerSealUnknown = true;'), isTrue);
      expect(blk.contains('hasEmployerSeal = viaServer;'), isTrue,
          reason: 'true 도 false 도 확정된 답이다');
    });

    test('SEAL-READ-CLIENT-03 서버 실패만 모름이다', () {
      final i = _resolver().indexOf('static Future<bool?> _employerSealFromServer');
      final fn = _resolver().substring(i, i + 1200);
      expect(fn.contains('return ready is bool ? ready : null;'), isTrue);
      expect(fn.contains('return null;'), isTrue, reason: '예외는 모름으로');
    });

    test('SEAL-READ-CLIENT-06 owner 는 CF 를 부르지 않는다', () {
      // 본인 문서 읽기가 성공하면 fallback 자체에 도달하지 않는다.
      final r = _resolver();
      final tryIdx = r.indexOf("collection('users')");
      final callIdx = r.indexOf('_employerSealFromServer(biz.id)');
      expect(callIdx, greaterThan(tryIdx),
          reason: 'catch 안에서만 부른다 — 모든 관리자가 CF 를 치지 않는다');
    });

    test('SEAL-READ-CLIENT-07 화면 build 에서 직접 부르지 않는다', () {
      // 호출은 readiness 적재 경로(forBusiness) 안에서만 일어난다.
      expect(_settings().contains('callableGetEmployerSealReadiness'), isFalse);
      expect(
          File('lib/screens/business_admin/jobs_root_screen.dart')
              .readAsStringSync()
              .contains('callableGetEmployerSealReadiness'),
          isFalse);
      expect('callableGetEmployerSealReadiness'.allMatches(_resolver()).length, 1,
          reason: '호출 지점은 한 곳이다');
    });

    test('SEAL-READ-CLIENT-08 새 listener·polling 을 만들지 않았다', () {
      expect(_resolver().contains('Timer.periodic'), isFalse);
      expect(_resolver().contains('snapshots()'), isFalse);
    });
  });

  group('[R7-P4.4E.3B] 역할 회귀', () {
    test('SEAL-READ-CLIENT-04 SubAdmin 관리 화면에 편집 입구가 없다', () {
      final s = _settings();
      final i = s.indexOf('Widget _buildEmployerSealStatusCard');
      final j = s.indexOf('Widget _buildSealCard', i);
      final card = s.substring(i, j);
      for (final cta in ['_registerSeal', '_deleteSeal', '_callSaveSeal']) {
        expect(card.contains(cta), isFalse);
      }
    });

    test('SEAL-READ-CLIENT-05 BUSINESS_ADMIN 편집 흐름은 그대로다', () {
      final s = _settings();
      final i = s.indexOf('Widget _buildSealCard');
      final next = s.indexOf('\n  Future<void> _registerSeal', i);
      final card = s.substring(i, next > i ? next + 2000 : s.length);
      expect(card.contains('final sealBase64 = user?.sealBase64;'), isTrue);
      expect(card.contains('_registerSeal(context, user)'), isTrue);
      expect(card.contains('_deleteSeal(context, user)'), isTrue);
    });

    test('EMP-SEAL-READ-05 SubAdmin 개인 날인은 어떤 축도 열지 않는다', () {
      // 서버는 owner 문서만 보고, 클라이언트 판정도 owner 날인에서만 온다.
      final i = _cf().indexOf('async function employerSealPresent(');
      expect(_cf().substring(i, i + 700).contains('callerUid'), isFalse);
      expect(
          _resolver().contains('readinessMap.values.any((r) => r.hasEmployerSeal)'),
          isTrue);
    });

    test('EMP-SEAL-READ-11 callableSaveSeal 은 건드리지 않았다', () {
      final save = _handler(_cf(), 'callableSaveSeal');
      expect(save.contains('const uid = request.auth.uid;'), isTrue);
      expect(save.contains('collection("users").doc(uid).update('), isTrue,
          reason: 'owner-target write API 로 넓히지 않았다');
    });
  });
}
