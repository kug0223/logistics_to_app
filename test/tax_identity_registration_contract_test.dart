// [PII-B4-R1.4] 신고할 번호는 어디에 있고, 무엇이 그 값을 정하는가
//
// 이 파일이 고정하는 것:
//
//   INV-1  canonical 저장소는 taxIdentities 하나다 (users 아님)
//   INV-2  등록 가부는 서버가 확인할 수 있는 것만으로 정한다
//   INV-3  암호화는 서버 키·인증 태그로 한다
//   INV-4  지문은 값 동일성이지 인증이 아니다
//   INV-5  등록된 번호는 되돌려주지 않는다
//   INV-6  외국인은 이 경로로 번호를 바꾸지 않는다

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

void main() {
  final cfRaw = _src(_cfPath);
  final cf = _codeOf(cfRaw);

  group('INV-1 — canonical 저장소 (§5·§6)', () {
    test('01 별도 컬렉션이다', () {
      expect(cf, contains('const TAX_ID_COL = "taxIdentities";'));
      final rules = _src('firestore.rules');
      final block =
          _sliceOf(rules, 'match /taxIdentities/{uid} {', '}');
      expect(block, contains('allow read, write: if false;'),
          reason: '본인도 직접 읽지 못한다 — 상태는 callable이 알려준다');
    });

    test('02 감사 로그도 클라이언트 접근 불가', () {
      final rules = _src('firestore.rules');
      final block =
          _sliceOf(rules, 'match /taxIdentityAuditLogs/{logId} {', '}');
      expect(block, contains('allow read, write: if false;'));
    });

    test('03 users에 전체번호를 새로 저장하지 않는다', () {
      // 외국인 finalize가 users에 쓰는 필드 목록에 번호가 없어야 한다.
      final txUpdate = _flat(_sliceOf(cfRaw,
          'tx.update(userRef, {\n          foreignIdentityFingerprint',
          '});'));
      expect(txUpdate, isNot(contains('foreignIdNumberEncrypted')));
      expect(txUpdate, isNot(contains('rawForeignId')));
      expect(txUpdate, isNot(contains('residentNumber')));
    });

    test('04 스키마가 §6 목록 그대로다', () {
      final set = _flat(_sliceOf(cfRaw, 'tx.set(ref, {\n        uid,', '});'));
      for (final f in [
        'identifierType', 'encryptedIdentifier', 'identifierFingerprint',
        'registrationSource', 'registeredAt', 'updatedAt',
      ]) {
        expect(set, contains(f), reason: f);
      }
      expect(cf, contains('const TAX_ID_TYPE_KOREAN = "KOREAN_RRN";'));
      expect(cf, contains(
          'const TAX_ID_TYPE_FOREIGN = "FOREIGN_REGISTRATION_NUMBER";'));
    });
  });

  group('INV-2 — 서버가 확인할 수 있는 것만 (§17~§20)', () {
    final validate = _flat(_codeOf(_sliceOf(cfRaw,
        'async function srvValidateKoreanTaxIdentifierOrThrow(', '\n}')));

    test('05 형식 — 숫자만 13자리', () {
      final norm = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvNormalizeTaxIdentifier(', '\n}')));
      expect(norm, contains(r'raw.replace(/\D/g, "")'));
      expect(norm, contains(r'/^\d{13}$/.test(digits)'));
    });

    test('06 PASS 신원과 앞 7자리 대조', () {
      expect(validate, contains('srvKoreanRrnMatchesPassIdentity(normalized, userData)'));
      final m = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvKoreanRrnMatchesPassIdentity(', '\n}')));
      // 생년월일 6자리 + 성별·세기 코드 1자리.
      expect(m, contains(r'n.slice(0, 6) !== `${yy}${mm}${dd}`'));
      expect(m, contains('n[6] !== expected'));
      // UTC로 읽는다 — 서버가 UTC 자정으로 저장하므로.
      expect(m, contains('d.getUTCFullYear()'));
      expect(m, contains('d.getUTCDate()'));
      // 기준이 없으면 통과시키지 않는다.
      expect(m, contains('if (!birth?.toDate || !gender)'));
    });

    test('07 구조 검증이 hard gate다 (R1.4.1에서 검증부호를 내렸다)', () {
      // [PII-B4-R1.4.1 §2] 구 검증부호는 2020.10 개편 이후 번호에 성립하지
      //   않아 hard gate에서 내려왔다. 그 자리를 구조 검증이 대신한다.
      //   검증부호 정책 전수는 rrn_current_assignment_contract_test.
      expect(cf, isNot(contains('function srvKoreanRrnChecksumOk(')));
      final s = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvKoreanRrnStructureError(', '\n}')));
      expect(s, contains('if (code < 1 || code > 4)'));
      expect(s, contains('mm < 1 || mm > 12 || dd < 1 || dd > 31'));
    });

    test('08 검증부호 알고리즘이 실제 번호에서 성립한다', () {
      bool ok(String n) {
        const w = [2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4, 5];
        var sum = 0;
        for (var i = 0; i < 12; i++) {
          sum += int.parse(n[i]) * w[i];
        }
        return ((11 - (sum % 11)) % 10) == int.parse(n[12]);
      }

      // 앞 12자리를 고정하고 검증부호를 직접 계산해 한 자리만 바꿔 본다.
      const front = '900101112345';
      const w = [2, 3, 4, 5, 6, 7, 8, 9, 2, 3, 4, 5];
      var sum = 0;
      for (var i = 0; i < 12; i++) {
        sum += int.parse(front[i]) * w[i];
      }
      final check = (11 - (sum % 11)) % 10;
      expect(ok('$front$check'), isTrue);
      expect(ok('$front${(check + 1) % 10}'), isFalse);
    });

    test('09 OCR 결과가 등록 가부를 정하지 않는다 (§20)', () {
      // documentMatch는 검증 목록에 없다 — 근거로만 저장된다.
      expect(validate, isNot(contains('documentMatch')));
      final reg = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableRegisterTaxIdentity', 'export const callableUpdateTaxIdentity')));
      expect(reg, contains('srvDocFieldOutcome(reqData?.documentMatch)'));
      // 클라이언트 주장으로 등록을 막거나 통과시키지 않는다.
      expect(reg, isNot(contains('if (regMatch ===')));
    });
  });

  group('INV-3 — 암호화 (§7·§8·§10)', () {
    test('10 AES-256-GCM + 인증 태그', () {
      final enc = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvEncryptTaxIdentifier(', '\n}')));
      expect(enc, contains('crypto.createCipheriv("aes-256-gcm", key, iv)'));
      expect(enc, contains('cipher.getAuthTag().toString("base64")'));
      expect(enc, contains('crypto.randomBytes(12)'));
      final dec = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvDecryptTaxIdentifier(', '\n}')));
      expect(dec, contains('d.setAuthTag('));
    });

    test('11 secret이 없으면 저장이 일어나지 않는다 (§8)', () {
      final s = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvTaxSecretsOrThrow(', '\n}')));
      expect(s, contains('if (!TAX_ID_ENCRYPT_KEY || !TAX_ID_HMAC_SECRET)'));
      expect(s, contains('throw new HttpsError("failed-precondition"'));
      // 길이 검사까지 한다 — 짧은 키로 조용히 돌지 않는다.
      expect(s, contains('key.length !== 32'));
      expect(s, contains('TAX_ID_HMAC_SECRET.length < 32'));
    });

    test('12 도메인 분리 — 외국인 uniqueness secret과 다르다 (§10)', () {
      final s = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvTaxSecretsOrThrow(', '\n}')));
      expect(s, contains('TAX_ID_HMAC_SECRET === FOREIGN_HMAC_SECRET'));
    });

    test('13 클라이언트 ENCRYPT_KEY를 서버로 들이지 않았다', () {
      expect(cf, isNot(contains('process.env.ENCRYPT_KEY')));
      expect(cf, isNot(contains('defineSecret("ENCRYPT_KEY")')));
      // legacy residentNumber를 복호화하려는 시도도 없다.
      expect(cf, isNot(contains('decryptResidentNumber')));
    });
  });

  group('INV-4 — 지문 (§9·§41·§42)', () {
    test('14 평문 HMAC — 결정적이다', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvTaxIdentifierFingerprint(', '\n}')));
      expect(f, contains('crypto.createHmac("sha256", hmac)'));
      expect(f, contains('.update(normalized, "utf8")'));
    });

    test('15 canonical이 legacy를 이긴다', () {
      final fp = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvTaxIdentityFingerprint(', '\n}')));
      expect(fp, contains('canonicalFp.length > 0 ? "T:" + canonicalFp'));
      // 레코드가 없을 때만 legacy 암호문으로 물러난다.
      expect(fp, contains('"R:" + (d["residentNumber"] as string) : "R:ABSENT"'));
    });

    test('16 review key 계약은 그대로다 (§43)', () {
      expect(cf, contains('reviewedTaxIdDocumentVersion'));
      expect(cf, contains('reviewedTaxIdentityFingerprint'));
      final resolve = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvResolveTaxIdentityReview(', '\n}')));
      expect(resolve, contains('rIdV !== curIdV || rFp !== curFp'));
    });

    test('17 자동 REVIEWED_OK 이전이 없다 (§44)', () {
      expect(cf, isNot(contains('migrateReviewedOk')));
      expect(cf, isNot(contains('taxIdentityDecision: TAX_REVIEW_OK,\n        reviewedTax')));
    });
  });

  group('INV-5 — 번호를 되돌려주지 않는다 (§26·§27·§38)', () {
    test('18 status 응답에 번호가 없다', () {
      final st = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableGetTaxIdentityStatus',
          'export const callableGetTaxIdentityNumber')));
      expect(st, isNot(contains('encryptedIdentifier')));
      expect(st, isNot(contains('srvDecryptTaxIdentifier')));
      expect(st, contains('registered: true'));
    });

    test('19 검토 조회 응답에도 없다', () {
      final rv = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableGetTaxIdentityReview',
          'async function srvValidateKoreanTaxIdentifierOrThrow(')));
      expect(rv, isNot(contains('srvDecryptTaxIdentifier')));
      expect(rv, contains('hasTaxIdentity: t.exists'));
    });

    test('20 복호화는 전용 문 하나에서만 일어난다', () {
      expect('srvDecryptTaxIdentifier('.allMatches(cf).length, 2,
          reason: '정의 1 + callableGetTaxIdentityNumber 1');
    });

    test('21 그 문은 권한·관계·현재 버전을 모두 본다 (§39·§49)', () {
      final n = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableGetTaxIdentityNumber',
          'export const callableGetTaxIdentityIdCardUrl')));
      expect(n, contains('srvAssertTaxIdentityAuthority(callerUid, businessId)'));
      expect(n, contains('srvHasBusinessWorkerRelationship(businessId, targetUid)'));
      expect(n, contains('expectedIdDocumentVersion !== srvDocumentVersionsOf(ud).id'));
      expect(n, contains('expectedTaxIdentityFingerprint !== srvTaxIdentityFingerprint(ud, t.data())'));
      // 열람도 감사에 남는다.
      expect(n, contains('action: "VIEW"'));
    });

    test('22 감사 로그에 번호·암호문이 없다 (§56)', () {
      final a = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvLogTaxIdentityAudit(', '\n}')));
      expect(a, isNot(contains('encryptedIdentifier')));
      expect(a, isNot(contains('normalized')));
      expect(a, contains('oldFingerprint'));
      expect(a, contains('newFingerprint'));
    });
  });

  group('INV-6 — 외국인은 이 경로로 바꾸지 않는다 (§22·§66)', () {
    test('23 등록·수정 진입에서 외국인을 막는다', () {
      final v = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvValidateKoreanTaxIdentifierOrThrow(', '\n}')));
      expect(v, contains('if (srvIsForeignIdentity(userData))'));
      expect(v, contains('외국인등록번호는 가입 시 등록됩니다'));
    });

    test('24 등록·수정 모두 같은 검증을 거친다', () {
      expect('srvValidateKoreanTaxIdentifierOrThrow('.allMatches(cf).length, 3,
          reason: '정의 1 + register 1 + update 1');
    });
  });

  group('멱등·수정 (§21·§61)', () {
    test('25 같은 값 재등록은 성공으로 본다', () {
      final reg = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableRegisterTaxIdentity',
          'export const callableUpdateTaxIdentity')));
      expect(reg, contains(
          'if (cur.get("identifierFingerprint") === fingerprint) return "unchanged";'));
      expect(reg, contains('throw new HttpsError("already-exists"'));
    });

    test('26 수정은 기존 레코드가 있어야 한다', () {
      final upd = _flat(_codeOf(_sliceOf(cfRaw,
          'export const callableUpdateTaxIdentity',
          'export const callableGetTaxIdentityStatus')));
      expect(upd, contains('if (!cur.exists)'));
      expect(upd, contains('등록된 세무정보가 없습니다'));
      expect(upd, contains('identifierFingerprint: fingerprint'));
    });

    test('27 탈퇴가 세무 레코드를 남기지 않는다 (§57)', () {
      expect(cf, contains('db.collection(TAX_ID_COL).doc(uid).delete()'));
    });
  });
}
