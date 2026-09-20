// [PII-B4-R1.4.1] 수집이 꺼져 있던 때 가입한 외국인에게 길을 연다
//
// 이 파일이 고정하는 것:
//
//   INV-1  서버가 혼자 채우지 않는다 (지문은 되돌릴 수 없다)
//   INV-2  입력값은 기존 신원 지문과 같아야만 받는다
//   INV-3  틀리면 아무것도 쓰지 않는다 (신원도, 세무도)
//   INV-4  신원 지문과 세무 지문은 계속 다른 secret이다
//   INV-5  복구와 정정은 다른 문이다
//   INV-6  꺼져 있으면 이 문도 열리지 않는다

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
const _docPath = 'lib/screens/common/document_management_screen.dart';

void main() {
  final cfRaw = _src(_cfPath);
  final cf = _codeOf(cfRaw);
  final rec = _flat(_codeOf(_sliceOf(cfRaw,
      'export const callableRecoverForeignTaxIdentity',
      'export const callableGetTaxIdentityStatus')));
  final svc = _codeOf(_src(_svcPath));
  final doc = _codeOf(_src(_docPath));

  group('INV-1 — backfill을 지어내지 않는다 (§11)', () {
    test('01 원문을 되살리려는 시도가 없다', () {
      for (final banned in [
        'reverseFingerprint', 'decryptForeignId', 'foreignIdNumberEncrypted',
        'bruteForce',
      ]) {
        expect(cf, isNot(contains(banned)), reason: banned);
      }
    });

    test('02 본인이 다시 입력한 값을 받는다', () {
      expect(rec, contains('rawForeignIdentifier'));
      expect(rec, contains('normalizeForeignId('));
    });

    test('03 본인만 호출한다 (§13)', () {
      expect(rec, contains('const uid = request.auth.uid;'));
      // 입력에 타인을 지정하는 인자가 없다 — payload는 번호 하나뿐이다.
      expect(rec, contains(
          'request.data as {rawForeignIdentifier?: unknown}'));
      expect(rec, isNot(contains('targetUid?:')));
      // 감사에 쓰는 targetUid도 본인이다.
      expect(rec, contains('actorUid: uid, targetUid: uid'));
    });
  });

  group('INV-2 — 신원 지문과 일치해야 받는다 (§14·§17)', () {
    test('04 기존 지문을 읽어 대조한다', () {
      expect(rec, contains('ud["foreignIdentityFingerprint"]'));
      expect(rec, contains(
          'if (computeForeignIdFingerprint(normalized) !== ownFp)'));
    });

    test('05 신원 지문이 없으면 이 경로가 아니다', () {
      expect(rec, contains('if (!ownFp)'));
      expect(rec, contains('외국인 신원 정보가 없어'));
    });

    test('06 uniqueness secret으로 대조하고, 저장은 tax secret으로 한다', () {
      // 대조: FOREIGN_HMAC_SECRET 기반 computeForeignIdFingerprint
      expect(rec, contains('computeForeignIdFingerprint(normalized)'));
      // 저장: TAX_ID_HMAC_SECRET 기반
      expect(rec, contains('srvTaxIdentifierFingerprint(normalized)'));
      expect(rec, contains('srvEncryptTaxIdentifier(normalized)'));
    });

    test('07 저장되는 지문은 신원 지문이 아니다 (§17)', () {
      final set = _sliceOf(rec, 'tx.set(ref, {', '});');
      expect(set, contains('identifierFingerprint: taxFp'));
      expect(set, isNot(contains('ownFp')),
          reason: '신원 지문을 세무 지문 자리에 넣지 않는다');
      expect(set, contains('identifierType: TAX_ID_TYPE_FOREIGN'));
      expect(set, contains(
          'registrationSource: TAX_ID_SOURCE_FOREIGN_RECOVERY'));
    });
  });

  group('INV-3 — 틀리면 아무것도 쓰지 않는다 (§16)', () {
    test('08 불일치 분기에 쓰기가 없다', () {
      final branch = _flat(_codeOf(_sliceOf(cfRaw,
          'if (computeForeignIdFingerprint(normalized) !== ownFp)',
          'const taxFp =')));
      expect(branch, contains('throw new HttpsError'));
      for (final w in ['tx.set', 'tx.update', '.set(', '.update(']) {
        expect(branch, isNot(contains(w)), reason: w);
      }
    });

    test('09 신원을 덮어쓰지 않는다', () {
      expect(rec, isNot(contains('foreignIdentityFingerprint:')));
      expect(rec, isNot(contains('foreignIdFingerprints')));
    });

    test('10 불일치를 generic 정정으로 흘려보내지 않는다', () {
      expect(rec, isNot(contains('CORRECTION_DOMAIN_TAX')));
      expect(rec, isNot(contains('documentCorrectionRequests')));
      // 사용자에게는 신원 재확인이 필요하다고 말한다.
      expect(rec, contains('가입 시 등록한 번호와 다릅니다'));
      expect(rec, contains('고객센터로 문의해주세요'));
    });

    test('11 로그에 번호가 없다 (§21)', () {
      final logs = RegExp(r'console\.(warn|info|error)\([^\n]*')
          .allMatches(_sliceOf(cfRaw,
              'export const callableRecoverForeignTaxIdentity',
              'export const callableGetTaxIdentityStatus'))
          .map((m) => m.group(0)!);
      expect(logs, isNotEmpty);
      for (final l in logs) {
        expect(l.contains(r'${normalized}'), isFalse, reason: l);
        expect(l.contains('rawForeignIdentifier'), isFalse, reason: l);
      }
      expect(rec, contains(r'idLen=${normalized.length}'));
    });

    test('12 응답에 번호가 없다 (§21)', () {
      expect(rec, contains('return {success: true, outcome};'));
      expect(rec, isNot(contains('identifier:')));
    });
  });

  group('INV-4 — 멱등 (§19)', () {
    test('13 이미 있으면 다시 쓰지 않는다', () {
      expect(rec, contains('if (cur.exists) { return "already_registered"; }'));
    });

    test('14 문서 id가 uid라 중복이 생길 수 없다', () {
      expect(rec, contains('db.collection(TAX_ID_COL).doc(uid)'));
    });

    test('15 새로 만든 경우에만 감사에 남는다', () {
      expect(rec, contains('if (outcome === "created")'));
      expect(rec, contains('action: "FOREIGN_RECOVERY"'));
    });
  });

  group('INV-5 — 복구와 정정은 다른 문이다 (§18)', () {
    test('16 generic update는 외국인을 계속 거부한다', () {
      final v = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvValidateKoreanTaxIdentifierOrThrow(', '\n}')));
      expect(v, contains('if (srvIsForeignIdentity(userData))'));
      expect(v, contains('외국인등록번호는 가입 시 등록됩니다'));
    });

    test('17 복구는 그 검증을 타지 않는다', () {
      expect(rec, isNot(contains('srvValidateKoreanTaxIdentifierOrThrow')));
    });

    test('18 source가 가입 경로와 구분된다 (§15)', () {
      expect(cf, contains(
          'const TAX_ID_SOURCE_FOREIGN_RECOVERY = "FOREIGN_RECOVERY";'));
      expect(cf, contains(
          'const TAX_ID_SOURCE_FOREIGN_SIGNUP = "FOREIGN_SIGNUP";'));
    });
  });

  group('INV-6 — 스위치를 우회하지 않는다 (§20)', () {
    test('19 관문이 인증 직후에 있다', () {
      expect(rec, contains('await srvAssertTaxIdentityCollectionEnabled();'));
      final gate = rec.indexOf('srvAssertTaxIdentityCollectionEnabled');
      final read = rec.indexOf('rawForeignIdentifier');
      expect(gate, greaterThan(0));
      expect(gate, lessThan(read), reason: '꺼져 있으면 입력값을 보지도 않는다');
    });
  });

  group('UI — 복구 CTA는 그 상태에서만 (§12·§22)', () {
    test('20 서버가 대상 여부를 알려준다', () {
      final st = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableGetTaxIdentityStatus',
          'export const callableGetTaxIdentityNumber')));
      expect(st, contains('foreignRecoveryAvailable:'));
      expect(st, contains(r'enabled && !!(u.data() ?? {})["foreignIdentityFingerprint"]'));
      // 이미 등록된 사람에게는 false다.
      expect(st, contains('foreignRecoveryAvailable: false'));
    });

    test('21 화면이 그 값으로만 CTA를 띄운다', () {
      expect(_flat(doc), contains(
          'bool get _needsForeignTaxRecovery => '
          '_taxStatus?.foreignRecoveryAvailable == true;'));
      expect(doc, contains('if (isForeign && _needsForeignTaxRecovery)'));
      // 정상 외국인에게는 기존 문구가 그대로 남는다.
      expect(doc, contains('가입 시 등록되어 추가 입력이 필요하지 않습니다.'));
    });

    test('22 복구 제출은 복구 callable로 간다', () {
      expect(svc, contains("httpsCallable('callableRecoverForeignTaxIdentity')"));
      expect(doc, contains('TaxIdentityService.recoverForeign(value)'));
    });

    test('23 복구에는 OCR 대조를 붙이지 않는다', () {
      // 서버가 신원 지문과 직접 대조하므로 그쪽이 더 강한 확인이다.
      expect(doc, contains('if (!widget.isForeignRecovery) TextButton.icon('));
    });

    test('24 조회 실패를 복구 대상으로 읽지 않는다', () {
      final unknown = _flat(_sliceOf(svc,
          'const TaxIdentityStatus.unknown()', 'loadFailed = true'));
      expect(unknown, contains('foreignRecoveryAvailable = false'));
    });
  });
}
