// [PII-B4-R1.4] 외국인은 같은 번호를 두 번 입력하지 않는다
//
// 이 파일이 고정하는 것:
//
//   INV-1  가입 시 신원·uniqueness·세무가 같은 커밋에서 써진다
//   INV-2  재시도해도 중복 레코드가 생기지 않는다
//   INV-3  서류관리에 외국인 번호 입력란이 없다
//   INV-4  세 가지 truth를 섞지 않는다 (신원 / 세무 / 취업자격)
//   INV-5  취업 가능 여부를 판정한다고 말하지 않는다

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

/// finalize 트랜잭션 본문 — 줄바꿈 표기(CRLF/LF)에 기대지 않는 단일 줄 마커.
String _finalizeTx(String raw) => _sliceOf(raw,
    'const foreignTaxSnap = (foreignTaxEnc && foreignTaxFp) ?',
    '_diagStage = "FINALIZE_STAGE_TRANSACTION_DONE"');

String _sliceOf(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';
const _docPath = 'lib/screens/common/document_management_screen.dart';

void main() {
  final cfRaw = _src(_cfPath);
  final cf = _codeOf(cfRaw);
  final doc = _codeOf(_src(_docPath));

  group('INV-1 — 한 커밋에서 같은 사람을 말한다 (§23·§24)', () {
    test('01 세무 쓰기가 finalize 트랜잭션 안에 있다', () {
      final tx = _codeOf(_finalizeTx(cfRaw));
      expect(tx, contains('tx.set(fpRef, {'), reason: 'uniqueness sentinel');
      expect(tx, contains('tx.update(userRef, {'), reason: 'users 신원');
      expect(tx, contains('tx.set(foreignTaxRef, {'), reason: '세무 레코드');
    });

    test('02 암호화·지문은 트랜잭션 밖에서 끝낸다', () {
      // 재시도마다 새 IV로 다시 암호화하면 같은 커밋 안에서 값이 흔들린다.
      final pre = _flat(_codeOf(_sliceOf(cfRaw,
          'const foreignTaxEnabled = await srvIsTaxIdentityCollectionEnabled();',
          '_diagStage = "FINALIZE_STAGE_TRANSACTION_START"')));
      expect(pre, contains('srvEncryptTaxIdentifier(normalized)'));
      expect(pre, contains('srvTaxIdentifierFingerprint(normalized)'));
      final tx = _codeOf(_finalizeTx(cfRaw));
      expect(tx, isNot(contains('srvEncryptTaxIdentifier(')));
    });

    test('03 읽기를 쓰기보다 먼저 한다', () {
      final tx = _codeOf(_finalizeTx(cfRaw));
      final read = tx.indexOf('await tx.get(foreignTaxRef)');
      final write = tx.indexOf('tx.set(fpRef');
      expect(read, greaterThan(0));
      expect(write, greaterThan(read),
          reason: 'Firestore는 쓰기 뒤 읽기를 허용하지 않는다');
    });

    test('04 타입이 외국인 등록번호로 기록된다', () {
      final set = _flat(_sliceOf(cfRaw, 'tx.set(foreignTaxRef, {', '});'));
      expect(set, contains('identifierType: TAX_ID_TYPE_FOREIGN'));
      expect(set, contains('registrationSource: TAX_ID_SOURCE_FOREIGN_SIGNUP'));
      // 가입 시 대조는 하지 않았다 — 판정으로 올리지 않는다.
      expect(set, contains('documentMatchOutcome: DOC_FIELD_UNASSESSED'));
    });
  });

  group('INV-2 — 재시도가 망가뜨리지 않는다 (§25)', () {
    test('05 문서 id가 uid다 — 중복 생성 불가', () {
      expect(cf, contains('const foreignTaxRef = db.collection(TAX_ID_COL).doc(uid);'));
    });

    test('06 값이 같으면 다시 쓰지 않는다', () {
      final tx = _flat(_codeOf(_sliceOf(cfRaw,
          'if (foreignTaxEnc && foreignTaxFp && foreignTaxSnap) {',
          '\n      });')));
      expect(tx, contains('if (!foreignTaxSnap.exists) {'));
      expect(tx, contains(
          'foreignTaxSnap.get("identifierFingerprint") !== foreignTaxFp'));
    });

    test('07 기존 uniqueness 멱등 동작이 그대로다', () {
      final tx = _flat(_codeOf(_sliceOf(cfRaw,
          'const fpSnap = await tx.get(fpRef);', 'tx.set(fpRef')));
      expect(tx, contains('if (existingUid === uid) {'));
      expect(tx, contains('return;'));
      expect(tx, contains('throw new HttpsError("already-exists"'));
    });
  });

  group('INV-3 — 서류관리에서 다시 묻지 않는다 (§3·§65)', () {
    test('08 외국인에게는 입력·수정 CTA가 없다', () {
      final sec = _flat(_sliceOf(doc,
          'Widget _buildTaxIdentitySection(UserModel user) {',
          'Future<void> _openTaxIdentitySheet('));
      expect(sec, contains('if (isForeign)'));
      expect(sec, contains('가입 시 등록되어 추가 입력이 필요하지 않습니다.'));
      // 시트를 여는 버튼은 내국인 분기에만 있다 — 외국인 분기 구간에는 없다.
      final foreignBranch = _flat(_sliceOf(sec,
          '가입 시 등록되어 추가 입력이 필요하지 않습니다.', 'else if (registered)'));
      expect(foreignBranch, isNot(contains('_openTaxIdentitySheet')));
    });

    test('09 외국인 표시는 "가입 시 등록됨"이다', () {
      expect(doc, contains("'가입 시 등록됨 — 외국인등록번호'"));
    });

    test('10 서버도 외국인의 generic 수정을 막는다 (§66)', () {
      final v = _flat(_codeOf(_sliceOf(cfRaw,
          'async function srvValidateKoreanTaxIdentifierOrThrow(', '\n}')));
      expect(v, contains('if (srvIsForeignIdentity(userData))'));
    });
  });

  group('INV-4 — 세 truth를 섞지 않는다 (§4·§21·§44)', () {
    test('11 uniqueness 지문과 세무 지문은 다른 필드다', () {
      expect(cf, contains('foreignIdentityFingerprint: fingerprint'));
      final set = _flat(_sliceOf(cfRaw, 'tx.set(foreignTaxRef, {', '});'));
      expect(set, contains('identifierFingerprint: foreignTaxFp'));
      expect(set, isNot(contains('foreignIdentityFingerprint')));
    });

    test('12 uniqueness secret과 세무 secret이 다르다', () {
      expect(cf, contains('const TAX_ID_HMAC_SECRET = process.env.TAX_ID_HMAC_SECRET ?? "";'));
      expect(cf, contains('const FOREIGN_HMAC_SECRET: string = process.env.FOREIGN_HMAC_SECRET ?? "";'));
      expect(cf, contains('TAX_ID_HMAC_SECRET === FOREIGN_HMAC_SECRET'));
    });

    test('13 세무 지문이 uniqueness sentinel을 대신하지 않는다', () {
      // sentinel 경로는 여전히 computeForeignIdFingerprint를 쓴다.
      expect(cf, contains('const fingerprint = computeForeignIdFingerprint(normalized);'));
      expect(cf, contains(r'const fpDocId = `${fingerprint}_${role}`;'));
    });
  });

  group('INV-5 — 취업자격을 판정하지 않는다 (§53)', () {
    test('14 visaType으로 게이트를 만들지 않았다', () {
      // 지원·수락 게이트 어디에도 visaType 조건이 없다.
      final applyGate = _flat(_codeOf(_sliceOf(cfRaw,
          'const applyOnbMissing = srvMissingApplicantPayoutRegistration(userData);',
          'if (userData["isBlacklisted"] === true)')));
      expect(applyGate, isNot(contains('visaType')));
      expect(applyGate, isNot(contains('stayExpiryDate')));
    });

    test('15 Work Eligibility 개념을 새로 만들지 않았다', () {
      expect(cf, isNot(contains('WorkEligibility')));
      expect(cf, isNot(contains('workEligibility')));
      expect(doc, isNot(contains('취업 가능')));
    });

    test('16 처리방침 문구가 그대로다', () {
      final terms = _src('lib/models/core/legal_terms_model.dart');
      expect(terms, contains('취업 가능 여부나 체류 자격의 적법성을 심사·판정하지 않습니다'));
    });
  });

  group('회귀 — 외국인 가입을 깨지 않았다 (§29·§63)', () {
    test('17 precheck·finalize 경로가 그대로다', () {
      expect(cf, contains('export const callablePrecheckForeignIdentity'));
      expect(cf, contains('export const callableFinalizeForeignIdentity'));
      expect(cf, contains('const FOREIGN_GENDER_CODES = new Set(["5", "6", "7", "8"]);'));
    });

    test('18 서버 파생 birthDate·gender가 그대로다', () {
      expect(cf, contains('birthDate: admin.firestore.Timestamp.fromDate(serverBirthDate)'));
      expect(_flat(cf), contains(
          '(genderDigit === 5 || genderDigit === 7) ? "남성" : '
          '((genderDigit === 6 || genderDigit === 8) ? "여성" : null)'));
    });

    test('19 세무 준비 실패가 가입을 중단시키지 않는다', () {
      final pre = _flat(_codeOf(_sliceOf(cfRaw,
          'const foreignTaxEnabled = await srvIsTaxIdentityCollectionEnabled();',
          'const foreignTaxRef')));
      expect(pre, contains('} catch (taxErr) {'));
      expect(pre, isNot(contains('throw')));
    });

    test('20 릴리스 로그에 번호가 없다 (R1.3A 회귀)', () {
      final screen = _codeOf(_src('lib/screens/auth/foreign_register_screen.dart'));
      expect(screen, isNot(contains('rawId.substring(0, 8)')));
      final auth = _codeOf(_src('lib/services/auth_service.dart'));
      expect(auth, isNot(contains('rawForeignId.substring(0, 8)')));
    });
  });
}
