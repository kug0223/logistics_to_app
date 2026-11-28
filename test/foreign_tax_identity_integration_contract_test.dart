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

  // [ALFIT-AUTH-KAKAO-ONBOARDING.1 갱신] 외국인 등록번호가 세무 레코드가 되는 writer 는 옛 가입 finalize(판정278 §2 로 닫힘 · 가입 sentinel
  //   포함) 대신 가입 후 등록 writer(callableRegisterForeignIdDocument)다. 이 파일의 불변식(한 커밋 · 밖에서 암호화 ·
  //   읽기 먼저 · uid 문서 · 재시도 안전 · 세 truth 분리)을 그 writer 에 고정한다. 가입 uniqueness sentinel 은
  //   clean cutover 로 이 writer 의 일이 아니다(가입 identity = KG CI) — 쓰지 않는다는 것을 함께 확인한다.
  final reg = _sliceOf(cfRaw, 'export const callableRegisterForeignIdDocument = onCall(',
      'console.info(`[foreignIdDocument]');
  final regTx = _sliceOf(reg, 'await db.runTransaction(async (tx) => {', '\n    });');

  group('INV-1 — 한 커밋에서 같은 사람을 말한다 (§23·§24)', () {
    test('01 세무 쓰기가 finalize 트랜잭션 안에 있다', () {
      final tx = _codeOf(regTx);
      expect(tx, contains('tx.update(userRef, patch);'), reason: 'users 서류 분류·지문');
      expect(tx, contains('tx.set(taxRef, {'), reason: '세무 레코드');
      expect(tx, isNot(contains('tx.set(fpRef')), reason: '옛 가입 sentinel 을 만들지 않는다(clean cutover)');
    });

    test('02 암호화·지문은 트랜잭션 밖에서 끝낸다', () {
      // 재시도마다 새 IV로 다시 암호화하면 같은 커밋 안에서 값이 흔들린다.
      final pre = _flat(_codeOf(_sliceOf(reg,
          'const taxEnabled = await srvIsTaxIdentityCollectionEnabled();',
          'await db.runTransaction(')));
      expect(pre, contains('srvEncryptTaxIdentifier(normalized)'));
      expect(pre, contains('srvTaxIdentifierFingerprint(normalized)'));
      expect(_codeOf(regTx), isNot(contains('srvEncryptTaxIdentifier(')));
    });

    test('03 읽기를 쓰기보다 먼저 한다', () {
      final tx = _codeOf(regTx);
      final read = tx.indexOf('await tx.get(taxRef)');
      final write = tx.indexOf('tx.update(userRef, patch)');
      expect(read, greaterThan(0));
      expect(write, greaterThan(read),
          reason: 'Firestore는 쓰기 뒤 읽기를 허용하지 않는다');
    });

    test('04 타입이 외국인 등록번호로 기록된다', () {
      final set = _flat(_sliceOf(regTx, 'tx.set(taxRef, {', '});'));
      expect(set, contains('identifierType: TAX_ID_TYPE_FOREIGN'));
      expect(set, contains('registrationSource: TAX_ID_SOURCE_FOREIGN_DOCUMENT'));
      // 등록 시 대조는 하지 않았다 — 판정으로 올리지 않는다.
      expect(set, contains('documentMatchOutcome: DOC_FIELD_UNASSESSED'));
    });
  });

  group('INV-2 — 재시도가 망가뜨리지 않는다 (§25)', () {
    test('05 문서 id가 uid다 — 중복 생성 불가', () {
      expect(_codeOf(reg), contains('const taxRef = db.collection(TAX_ID_COL).doc(uid);'));
    });

    test('06 값이 같으면 다시 쓰지 않는다', () {
      // 새 writer 는 기존 세무 레코드를 아예 덮지 않는다(없을 때만 set — 옛 '값이 다를 때만' 보다 강함).
      expect(_flat(_codeOf(regTx)), contains('if (taxEnc && taxFp && taxSnap && !taxSnap.exists) {'));
    });

    test('07 기존 uniqueness 멱등 동작이 그대로다', () {
      // 같은 서류 재제출은 멱등(프로필만) · 다른 서류로 이미 정해진 계정은 거절 — 옛 sentinel 멱등의 대응.
      final tx = _flat(_codeOf(regTx));
      expect(tx, contains('if (ns === "foreign" && cur["foreignIdDocumentFingerprint"] === docFp) {'));
      expect(tx, contains('return;'));
      expect(tx, contains('throw reject("NATIONALITY_ALREADY_SET"'));
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
      // [ALFIT-AUTH-KAKAO-ONBOARDING.1 갱신] 서류 지문(users.foreignIdDocumentFingerprint)과 세무 지문(taxIdentities.identifierFingerprint)이 다른 필드다.
      expect(_flat(_codeOf(regTx)), contains('foreignIdDocumentFingerprint: docFp'));
      final set = _flat(_sliceOf(regTx, 'tx.set(taxRef, {', '});'));
      expect(set, contains('identifierFingerprint: taxFp'));
      expect(set, isNot(contains('foreignIdDocumentFingerprint')));
      expect(set, isNot(contains('foreignIdentityFingerprint')));
    });

    test('12 uniqueness secret과 세무 secret이 다르다', () {
      expect(cf, contains('const TAX_ID_HMAC_SECRET = process.env.TAX_ID_HMAC_SECRET ?? "";'));
      expect(cf, contains('const FOREIGN_HMAC_SECRET: string = process.env.FOREIGN_HMAC_SECRET ?? "";'));
      expect(cf, contains('TAX_ID_HMAC_SECRET === FOREIGN_HMAC_SECRET'));
    });

    test('13 세무 지문이 uniqueness sentinel을 대신하지 않는다', () {
      // [ALFIT-AUTH-KAKAO-ONBOARDING.1 갱신] 서류 지문은 등록번호 HMAC(computeForeignIdFingerprint)이고 세무 HMAC 이 아니다.
      expect(_codeOf(reg), contains('const docFp = computeForeignIdFingerprint(normalized);'));
      expect(_codeOf(reg), isNot(contains('foreignIdFingerprints')), reason: '옛 가입 sentinel 은 만들지 않는다');
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
      // [ALFIT-AUTH-KAKAO-ONBOARDING.1 갱신] 파생은 서버 helper(signup_core deriveFromForeignId) — 같은 표(5·7 남성 / 6·8 여성 · 범위 밖 null).
      expect(_codeOf(reg), contains('const derived = normalized ? skDeriveFromForeignId(normalized) : null;'));
      expect(_codeOf(reg), contains('const bts = srvPassBirthDateToTimestamp(derived.birthDate);'));
      final core = _flat(_src('functions/src/signup_core.ts'));
      expect(core, contains('if (code < 5 || code > 8) return null;'));
      expect(core, contains('gender: (code === 5 || code === 7) ? "남성" : "여성"'));
    });

    test('19 세무 준비 실패가 가입을 중단시키지 않는다', () {
      // [ALFIT-AUTH-KAKAO-ONBOARDING.1 갱신] 새 등록 writer 에서도 세무 준비 실패는 등록을 멈추지 않는다.
      final pre = _flat(_codeOf(_sliceOf(reg,
          'const taxEnabled = await srvIsTaxIdentityCollectionEnabled();',
          'const trimmed =')));
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
