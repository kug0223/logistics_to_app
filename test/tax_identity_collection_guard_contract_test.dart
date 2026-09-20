// [PII-B4-R1.4] 켜지 않은 수집은 일어나지 않는다
//
// 이 파일이 고정하는 것:
//
//   INV-1  서버에 별도 스위치가 있다 (UI 플래그는 경계가 아니다)
//   INV-2  모든 실패는 "꺼짐"으로 떨어진다 (fail closed)
//   INV-3  모든 민감 writer가 그 관문을 지난다
//   INV-4  클라이언트 기본값도 false다
//   INV-5  게이트가 꺼져 있으면 지원 전제도 살아나지 않는다

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

String _sliceOf(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';
const _svcPath = 'lib/services/tax_identity_service.dart';

void main() {
  final cfRaw = _src(_cfPath);
  final cf = _codeOf(cfRaw);
  final svc = _codeOf(_src(_svcPath));

  group('INV-1 — 서버 스위치 (§11·§13)', () {
    test('01 서버 설정 문서가 있다', () {
      expect(cf, contains(
          'const TAX_COLLECTION_DOC = "tax_identity_collection";'));
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvIsTaxIdentityCollectionEnabled(', '\n}')));
      expect(f, contains('db.collection("app_settings")'));
      expect(f, contains('snap.get("enabled") === true'));
    });

    test('02 클라이언트 플래그를 서버가 신뢰하지 않는다', () {
      // 요청 payload로 활성화를 판단하는 경로가 없어야 한다.
      expect(cf, isNot(contains('request.data.collectionEnabled')));
      expect(cf, isNot(contains('data["tax_identity_collection_enabled"]')));
    });
  });

  group('INV-2 — fail closed (§12)', () {
    test('03 읽기 실패는 꺼짐이다', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvIsTaxIdentityCollectionEnabled(', '\n}')));
      expect(f, contains('} catch (e) {'));
      expect(f, contains('return false;'));
      // 실패를 true로 바꾸는 분기가 없다.
      expect(f, isNot(contains('return true; }')));
    });

    test('04 문서가 없어도 꺼짐이다', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvIsTaxIdentityCollectionEnabled(', '\n}')));
      expect(f, contains('snap.exists && snap.get("enabled") === true'));
    });

    test('05 관문은 꺼짐이면 던진다', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvAssertTaxIdentityCollectionEnabled(', '\n}')));
      expect(f, contains('if (!await srvIsTaxIdentityCollectionEnabled())'));
      expect(f, contains('throw new HttpsError("failed-precondition"'));
    });
  });

  group('INV-3 — 모든 민감 writer가 관문을 지난다 (§12·§13)', () {
    test('06 등록·수정이 관문 뒤에 있다', () {
      for (final name in [
        'callableRegisterTaxIdentity',
        'callableUpdateTaxIdentity',
      ]) {
        final body = _flat(_codeOf(_sliceOf(cfRaw,
            'export const $name', 'const userSnap')));
        expect(body, contains('await srvAssertTaxIdentityCollectionEnabled();'),
            reason: name);
      }
    });

    test('07 관문이 인증 직후에 온다 — 유효성 검사보다 먼저', () {
      final reg = _codeOf(_sliceOf(cfRaw,
          'export const callableRegisterTaxIdentity',
          'export const callableUpdateTaxIdentity'));
      final gate = reg.indexOf('srvAssertTaxIdentityCollectionEnabled');
      final normalize = reg.indexOf('srvValidateKoreanTaxIdentifierOrThrow');
      expect(gate, greaterThan(0));
      expect(gate, lessThan(normalize),
          reason: '꺼져 있으면 값을 들여다보지도 않는다');
    });

    test('08 외국인 가입의 세무 쓰기도 플래그를 본다 (§63)', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'const foreignTaxEnabled = await srvIsTaxIdentityCollectionEnabled();',
          'const foreignTaxRef')));
      expect(f, contains('if (foreignTaxEnabled) {'));
      expect(f, contains('srvTaxIdentifierFingerprint(normalized)'));
      // secret 실패도 "쓰지 않음"으로 떨어진다.
      expect(f, contains('foreignTaxEnc = null;'));
    });

    test('09 그래도 외국인 가입 자체는 깨지지 않는다 (§63)', () {
      final tx = _flat(_codeOf(_sliceOf(cfRaw,
          'if (foreignTaxEnc && foreignTaxFp && foreignTaxSnap) {', '\n      });')));
      expect(tx, contains('if (!foreignTaxSnap.exists)'));
      // 세무 쓰기 실패가 신원 등록을 되돌리는 분기가 없다.
      expect(tx, isNot(contains('throw new HttpsError')));
    });

    test('10 status 조회는 관문 대상이 아니다 (§26)', () {
      final st = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableGetTaxIdentityStatus',
          'export const callableGetTaxIdentityNumber')));
      expect(st, isNot(contains('srvAssertTaxIdentityCollectionEnabled')),
          reason: '상태를 못 읽으면 화면이 무엇을 말할지 알 수 없다');
      expect(st, contains('collectionEnabled: enabled'));
    });
  });

  group('INV-4 — 클라이언트 기본값 (§14)', () {
    test('11 Remote Config 키와 기본 false', () {
      expect(svc, contains(
          "static const String remoteConfigKey = 'tax_identity_collection_enabled';"));
      final g = _flat(_sliceOf(svc, 'static bool get collectionEnabledLocally', '}\n'));
      expect(g, contains('catch (_) { return false;'));
    });

    test('12 조회 실패를 미등록으로 바꾸지 않는다', () {
      expect(svc, contains('const TaxIdentityStatus.unknown()'));
      expect(svc, contains('loadFailed = true'));
      final gate = _flat(_sliceOf(
          _src('lib/screens/user/apply_prerequisites_screen.dart'),
          'if (taxStatus != null && !taxStatus.loadFailed) {', '}'));
      expect(gate, contains('taxStatus.collectionEnabled && !taxStatus.registered'));
    });
  });

  group('INV-5 — 꺼져 있으면 지원 전제도 없다 (§34·§59)', () {
    test('13 온보딩 차단 helper가 플래그를 먼저 본다', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvTaxIdentityOnboardingBlock(', '\n}')));
      expect(f, contains('if (!await srvIsTaxIdentityCollectionEnabled()) return null;'));
    });

    test('14 조회 실패는 차단 사유가 아니다', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvTaxIdentityOnboardingBlock(', '\n}')));
      expect(f, contains('} catch (e) {'));
      expect(f, contains('return null; }'));
    });

    test('15 지원·초대수락 두 경로 모두 연결됐다 (§39)', () {
      expect(cf, contains('srvTaxIdentityOnboardingBlock(uid, userData)'));
      expect(cf, contains('if (acceptTaxEnabled) {'));
      expect(cf, contains('srvTaxIdentityGateMessage(ONB_MISSING_TAX_IDENTITY)'));
    });

    test('16 초대수락은 트랜잭션 밖에서 읽는다', () {
      // 트랜잭션 콜백 안에서 tx를 거치지 않은 읽기를 하지 않는다.
      final txBody = _sliceOf(cfRaw,
          'const acceptTaxEnabled = await srvIsTaxIdentityCollectionEnabled();',
          'srvResolveMatchingReadiness(freshUserData');
      final after = txBody.substring(txBody.indexOf('await db.runTransaction'));
      expect(after, isNot(contains('await db.collection(TAX_ID_COL)')));
    });

    test('17 기존 지급자료 helper와 합치지 않았다 (§38)', () {
      final payout = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvMissingApplicantPayoutRegistration(', '\n}')));
      expect(payout, isNot(contains('TAX_ID')));
      expect(payout, isNot(contains('taxIdentit')));
      expect(cf, contains('const ONB_MISSING_TAX_IDENTITY = "MISSING_TAX_IDENTITY";'));
    });
  });

  group('범위 — PROD는 이번에 켜지지 않는다 (§59)', () {
    test('18 저장소에 활성화된 설정을 심어 두지 않았다', () {
      // 코드가 기본값으로 enabled:true를 쓰는 경로가 없어야 한다.
      expect(cf, isNot(contains('enabled: true')));
    });
  });
}
