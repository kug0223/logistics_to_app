// [PII-B4-R1.4.3] 기준을 고칠 수 있으면 기준이 아니다
//
// 이 파일이 고정하는 것:
//
//   INV-1  신원 기준 필드는 본인이 수정할 수 없다
//   INV-2  그 값은 서버가 확정하고, 확정했다는 표시를 남긴다
//   INV-3  표시가 없으면 세무 대조를 하지 않는다 (추정 금지)
//   INV-4  가입(CREATE)은 막지 않는다 — 직후 CF가 다시 확정한다
//   INV-5  표시용 필드까지 잠그지 않는다
//   INV-6  rules와 클라이언트 2차 방어가 같은 말을 한다

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

Set<String> _quoted(String s) =>
    RegExp(r"'([a-zA-Z]+)'").allMatches(s).map((m) => m.group(1)!).toSet();

const _cfPath = 'functions/src/index.ts';
const _rulesPath = 'firestore.rules';
const _userFsPath = 'lib/services/firestore/user_firestore.dart';

/// 신원 기준 — 서버만 쓸 수 있어야 한다.
const _basisFields = [
  'birthDate', 'gender', 'identityBasisSource', 'identityBasisAt',
  'name', 'legalName', 'koreanName',
];

/// 표시·편의 — 본인이 계속 고칠 수 있어야 한다.
const _editableFields = [
  'address', 'detailAddress', 'homeRegion', 'profileImageUrl', 'bio',
];

void main() {
  final cfRaw = _src(_cfPath);
  final cf = _codeOf(cfRaw);
  final rulesRaw = _src(_rulesPath);
  final userFs = _src(_userFsPath);

  final ownerUpdate = _sliceOf(rulesRaw,
      'allow update: if isLoggedIn() &&', ']);');
  final rulesDeny = _quoted(ownerUpdate);
  final protDeny = _quoted(_sliceOf(userFs,
      '_protectedUserFields = {', '};'));

  group('INV-1 — 본인이 기준을 고칠 수 없다 (§4)', () {
    for (final f in _basisFields) {
      test('01 rules 차단: $f', () {
        expect(rulesDeny.contains(f), isTrue, reason: '$f 가 본인 update 차단 목록에 없다');
      });
    }

    test('02 R1.4.2 실측 exploit 대상이 전부 잠겼다', () {
      // 그때 바꾼 것: birthDate, gender. passVerifiedAt은 원래 잠겨 있었다.
      expect(rulesDeny.containsAll({'birthDate', 'gender', 'passVerifiedAt'}),
          isTrue);
    });
  });

  group('INV-2 — 서버가 확정하고 표시를 남긴다 (§2·§5)', () {
    test('03 표시 필드와 helper가 있다', () {
      expect(cf, contains('const IDENTITY_BASIS_PASS = "PASS";'));
      expect(cf, contains(
          'const IDENTITY_BASIS_FOREIGN = "FOREIGN_IDENTITY";'));
      final p = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvIdentityBasisPatch(', '\n}')));
      expect(p, contains('identityBasisSource: source'));
      expect(p, contains('identityBasisAt: admin.firestore.FieldValue.serverTimestamp()'));
    });

    test('04 내국인 가입 — 서버 토큰 값으로 다시 확정한다', () {
      final fin = _flat(_codeOf(_sliceOf(cfRaw,
          'tx.update(db.collection("users").doc(uid), {', '});')));
      expect(fin, contains('ciHash'));
      expect(fin, contains('passVerifiedAt'));
      // 클라이언트가 쓴 값을 그대로 두지 않는다.
      expect(fin, contains('regGender ? {gender: regGender} : {}'));
      expect(fin, contains('regBirth ? {birthDate: regBirth} : {}'));
      expect(fin, contains('srvIdentityBasisPatch(IDENTITY_BASIS_PASS)'));
    });

    test('05 근거가 없으면 표시도 남기지 않는다', () {
      final fin = _flat(_codeOf(_sliceOf(cfRaw,
          'tx.update(db.collection("users").doc(uid), {', '});')));
      // 둘 다 있을 때만 표시한다 — 반쪽 근거를 근거로 쓰지 않는다.
      expect(fin, contains('(regGender && regBirth) ? srvIdentityBasisPatch'));
    });

    test('06 재인증도 같은 경로다', () {
      final re = _flat(_codeOf(_sliceOf(cfRaw,
          'const reauthName   = tokenData["name"]', 'await db.collection("users")')));
      expect(re, contains('srvPassBirthDateToTimestamp(reauthBdStr)'));
      expect(re, contains(
          'if (reauthGender && reauthBirth) { Object.assign(updateFields, '
          'srvIdentityBasisPatch(IDENTITY_BASIS_PASS)); }'));
    });

    test('07 외국인은 등록번호에서 파생한 값에 표시를 붙인다', () {
      final fg = _flat(_codeOf(_sliceOf(cfRaw,
          'foreignIdentityFingerprint: fingerprint,', '});')));
      expect(fg, contains('srvIdentityBasisPatch(IDENTITY_BASIS_FOREIGN)'));
      expect(fg, contains('birthDate: admin.firestore.Timestamp.fromDate(serverBirthDate)'));
    });

    test('08 날짜 파싱이 UTC로 한 곳에 모였다', () {
      final f = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvPassBirthDateToTimestamp(', '\n}')));
      expect(f, contains('new Date(Date.UTC(y, m - 1, d))'));
      // 읽는 쪽도 UTC getter다 — 하루 밀리지 않는다.
      final m = _flat(_codeOf(_sliceOf(cfRaw,
          'function srvKoreanRrnMatchesPassIdentity(', '\n}')));
      expect(m, contains('d.getUTCFullYear()'));
    });
  });

  group('INV-3 — 표시가 없으면 대조하지 않는다 (§6·§7)', () {
    final match = _flat(_codeOf(_sliceOf(cfRaw,
        'function srvKoreanRrnMatchesPassIdentity(', '\n}')));

    test('09 출처를 먼저 본다', () {
      expect(match, contains(
          'if (basis !== IDENTITY_BASIS_PASS && basis !== IDENTITY_BASIS_FOREIGN)'));
      expect(match, contains('본인인증으로 확인된 생년월일·성별이 없습니다.'));
    });

    test('10 passVerifiedAt 존재를 근거로 추정하지 않는다', () {
      expect(match, isNot(contains('passVerifiedAt')),
          reason: '인증 시각이 있다고 생년월일이 PASS에서 왔다는 뜻은 아니다');
    });

    test('11 출처 검사가 값 검사보다 앞이다', () {
      final basisAt = match.indexOf('basis !== IDENTITY_BASIS_PASS');
      final valueAt = match.indexOf('n.slice(0, 6)');
      expect(basisAt, greaterThan(0));
      expect(valueAt, greaterThan(basisAt));
    });
  });

  group('INV-4 — 가입을 막지 않는다 (§5)', () {
    test('12 CREATE 경로는 그대로다', () {
      // 차단은 allow update 블록 하나뿐이다.
      final createBlock = _sliceOf(rulesRaw,
          'match /users/{userId}', 'allow update: if isLoggedIn()');
      for (final f in ['birthDate', 'gender']) {
        expect(createBlock.contains("'$f'"), isFalse,
            reason: '$f 를 create에서까지 막으면 가입이 깨진다');
      }
    });

    test('13 서버 writer는 Admin SDK라 rules와 무관하다', () {
      for (final w in [
        'export const finalizeRegistration',
        'export const finalizePassReauth',
        'export const callableFinalizeForeignIdentity',
      ]) {
        expect(cf, contains(w), reason: w);
      }
    });
  });

  group('INV-5 — 표시용까지 잠그지 않는다 (§14)', () {
    for (final f in _editableFields) {
      test('14 여전히 수정 가능: $f', () {
        expect(rulesDeny.contains(f), isFalse);
        expect(protDeny.contains(f), isFalse);
      });
    }

    test('15 프로필 수정이 쓰는 것은 그 목록뿐이다', () {
      final save = _flat(_sliceOf(_src('lib/screens/common/profile_edit_screen.dart'),
          'Future<void> _saveProfile() async {', 'updateUserDocument'));
      for (final f in ['birthDate', 'gender', 'legalName', 'koreanName']) {
        expect(save, isNot(contains("updates['$f']")), reason: f);
      }
      expect(save, contains("updates['address']"));
      expect(save, contains("updates['homeRegion']"));
    });
  });

  group('INV-6 — 두 방어가 같은 말을 한다 (§13)', () {
    test('16 신원 기준 필드는 양쪽 모두에 있다', () {
      for (final f in _basisFields) {
        expect(rulesDeny.contains(f), isTrue, reason: 'rules: $f');
        expect(protDeny.contains(f), isTrue, reason: '_protectedUserFields: $f');
      }
    });

    test('17 기계적 union이 아니다 — 각자 이유가 있는 항목은 남는다', () {
      // 코드에만 있는 것(클라이언트 실수 방지)은 그대로 둔다.
      expect(protDeny.contains('isDummy'), isTrue);
      // rules에만 있는 것(서버 전용 상태)도 그대로 둔다.
      expect(rulesDeny.contains('idCardMatchStatus'), isTrue);
    });
  });

  group('범위 — 이번에 만들지 않은 것 (§22)', () {
    test('18 새 컬렉션·새 identity 스키마를 만들지 않았다', () {
      expect(cf, isNot(contains('verifiedIdentity')));
      expect(cf, isNot(contains('identityVersion')));
      expect(_src(_rulesPath), isNot(contains('match /verifiedIdentities')));
    });

    test('19 세무 contract는 그대로다', () {
      expect(cf, contains('const TAX_ID_COL = "taxIdentities";'));
      expect(cf, contains('srvKoreanRrnLegacyChecksumOk'));
      expect(cf, contains('TAX_ID_SOURCE_FOREIGN_RECOVERY'));
    });
  });
}
