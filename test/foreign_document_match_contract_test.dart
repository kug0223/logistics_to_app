// [PII-DOC-R1.2] 외국인 서류 대조 — 검사하지 않은 값은 일치가 아니다
//
// 이 파일이 고정하는 것:
//
//   INV-1  expected가 없으면 matched = true 로 만들지 않는다.
//   INV-2  UNASSESSED ≠ MISMATCH, UNASSESSED ≠ MATCHED.
//   INV-3  최초 외국인 가입은 등록번호 OCR이 신원의 source 자체이므로
//          그 값으로 자기 자신을 검증해 PASSED를 만들지 않는다.
//   INV-4  전체 13자리를 새 평문 필드로 저장하지 않는다.
//
// 판정 규칙 자체(성별코드)는 test/unit/identity_identifier_test.dart가 고정한다.

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
const _ocrPath = 'lib/utils/ocr_verification_helper.dart';
const _pickPath = 'lib/utils/document_upload_helper.dart';
const _idPath = 'lib/utils/identity_identifier.dart';
const _docScreen = 'lib/screens/common/document_management_screen.dart';
const _foreignReg = 'lib/screens/auth/foreign_register_screen.dart';

void main() {
  final rawCf = _src(_cfPath);
  final cf = _codeOf(rawCf);

  group('INV-1 — 검사하지 않은 값을 true로 만들지 않는다', () {
    test('01 OCR helper에 "기본값 true" 가 없다', () {
      final ocr = _codeOf(_src(_ocrPath));
      // 이 한 줄이 R1-B3의 전부였다.
      expect(ocr, isNot(contains('bool isResidentNumberValid = true;')),
          reason: '기대값이 없으면 이 기본값이 그대로 일치로 올라갔다');
      expect(ocr, contains('bool isResidentNumberValid = false;'));
    });

    test('02 기대값이 없으면 UNASSESSED', () {
      final ocr = _flat(_codeOf(_src(_ocrPath)));
      expect(ocr,
          contains('DocFieldOutcome identifierOutcome = DocFieldOutcome.unassessed;'));
      // 이름도 같다 — 기대값이 비면 비교하지 않는다.
      expect(ocr, contains('nameAssessable'));
    });

    test('03 isValid는 두 항목이 모두 MATCHED일 때만', () {
      final ocr = _flat(_codeOf(_src(_ocrPath)));
      expect(
          ocr,
          contains('final isValid = nameOutcome == DocFieldOutcome.matched && '
              'identifierOutcome == DocFieldOutcome.matched;'),
          reason: 'UNASSESSED가 통과로 새면 안 된다');
    });

    test('04 서버도 MATCHED 둘일 때만 PASSED', () {
      final fn = _flat(_codeOf(
          _sliceOf(rawCf, 'function srvComputeDocumentState(', '\n}')));
      expect(
          fn,
          contains('nameOutcome === DOC_FIELD_MATCHED && '
              'identifierOutcome === DOC_FIELD_MATCHED'));
      // 옛 규칙이 남아 있으면 안 된다.
      expect(fn,
          isNot(contains('evidence.nameMatched && evidence.identifierMatched')));
    });
  });

  group('INV-2 — UNASSESSED ≠ MISMATCH ≠ MATCHED', () {
    test('05 네 값이 별개로 존재한다 (클라이언트)', () {
      final id = _codeOf(_src(_idPath));
      for (final v in ['matched', 'mismatch', 'unreadable', 'unassessed']) {
        expect(id, contains('  $v,'), reason: 'DocFieldOutcome.$v');
      }
    });

    test('06 네 값이 별개로 존재한다 (서버, 같은 문자열)', () {
      for (final v in ['MATCHED', 'MISMATCH', 'UNREADABLE', 'UNASSESSED']) {
        expect(cf, contains('= "$v"'), reason: '서버 토큰 $v');
      }
      final id = _codeOf(_src(_idPath));
      for (final v in ['MATCHED', 'MISMATCH', 'UNREADABLE', 'UNASSESSED']) {
        expect(id, contains("=> '$v'"), reason: '클라이언트 wire $v');
      }
    });

    test('07 F4 — 읽지 못한 것은 불일치가 아니다', () {
      final ocr = _flat(_codeOf(_src(_ocrPath)));
      expect(ocr, contains('anyCandidate'));
      expect(
          ocr,
          contains('? DocFieldOutcome.mismatch : DocFieldOutcome.unreadable'),
          reason: '후보가 하나도 없으면 UNREADABLE — 다르다고 말할 근거가 없다');
    });

    test('08 서버: 비교 못 한 항목이 남으면 SUBMITTED (불일치 아님)', () {
      final fn = _flat(_codeOf(
          _sliceOf(rawCf, 'function srvComputeDocumentState(', '\n}')));
      // MISMATCH만 OVERRIDDEN으로 간다.
      expect(
          fn,
          contains('nameOutcome === DOC_FIELD_MISMATCH || '
              'identifierOutcome === DOC_FIELD_MISMATCH'));
      expect(fn, contains('return {state: DOC_SUBMITTED, evidence};'));
    });

    test('09 화면도 셋을 구분해 말한다', () {
      final pick = _codeOf(_src(_pickPath));
      expect(pick, contains('등록된 신원정보와 신분증 번호가 다릅니다'));
      expect(pick, contains('신분증에서 번호를 읽지 못했습니다'));
      expect(pick, contains('등록된 정보가 부족해 서류와 대조하지 못했습니다'));
      // 비교 못 한 것을 "일치하지 않습니다"로 말하던 문구는 사라져야 한다.
      expect(pick, isNot(contains('• 주민번호가 일치하지 않습니다')));
    });

    test('10 비교 실패만 있었던 제출은 "강행"이 아니다', () {
      final pick = _flat(_codeOf(_src(_pickPath)));
      expect(pick, contains('overridden: idHasMismatch'),
          reason: '사용자가 무시한 불일치가 없으면 없는 잘못을 붙이지 않는다');
    });
  });

  group('INV-3 — 자기 자신으로 검증하지 않는다', () {
    test('11 외국인 가입 3경로가 UNASSESSED를 명시적으로 보낸다', () {
      final reg = _codeOf(_src(_foreignReg));
      final n = 'DocumentPickResult.unassessedSelfCheck()'.allMatches(reg).length;
      expect(n, 3, reason: '세 경로 모두 — 보내지 않는 것과 없다고 말하는 것은 다르다');
      // 가짜 통과를 채워 넣지 않는다.
      expect(reg, isNot(contains("'nameMatched': true")));
      expect(reg, isNot(contains("'identifier': 'MATCHED'")));
    });

    test('12 unassessedSelfCheck는 두 항목 모두 UNASSESSED', () {
      final fn = _flat(_codeOf(
          _sliceOf(_src(_pickPath), 'static Map<String, dynamic> unassessedSelfCheck(', '};')));
      expect(fn, contains("'name': DocFieldOutcome.unassessed.wire"));
      expect(fn, contains("'identifier': DocFieldOutcome.unassessed.wire"));
      expect(fn, contains("'overridden': false"));
    });

    test('13 구버전 payload를 통과 근거로 쓰지 않는다', () {
      final fn = _flat(_codeOf(
          _sliceOf(rawCf, 'function srvComputeDocumentState(', '\n}')));
      expect(fn, contains('selfCheckVersion'));
      expect(fn, contains('raw.selfCheckVersion >= 2'));
      // 구버전 주장은 보존하되 판정에는 안 쓴다.
      expect(fn, contains('legacyNameMatched'));
      expect(fn, contains('legacyIdentifierMatched'));
      expect(fn, contains('isV2 ? srvDocFieldOutcome(raw.name) : DOC_FIELD_UNASSESSED'));
    });

    test('14 기존 V3 identifierMatched=true는 MATCHED backfill 금지', () {
      // [§17] 실제 비교 근거가 아니다. 향후 R1.4 backfill이 이 값을 쓰면
      //   검사하지 않은 사실이 MATCHED로 굳는다.
      final fn = _codeOf(
          _sliceOf(rawCf, 'function srvComputeDocumentState(', '\n}'));
      expect(fn, contains('legacyIdentifierMatched'),
          reason: 'v1 주장은 legacy* 이름으로만 남아야 구분된다');
      expect(fn, isNot(contains('identifierMatched: b(raw.identifierMatched)')),
          reason: 'canonical 이름으로 저장하면 R1.4가 그대로 믿게 된다');
    });
  });

  group('INV-4 — 새 평문 식별번호 저장 없음', () {
    test('15 foreignIdRaw / 13자리 신규 저장 없음', () {
      final finalize = _codeOf(_sliceOf(rawCf,
          'export const callableFinalizeForeignIdentity = onCall(',
          'FINALIZE_STAGE_COMPLETE'));
      for (final banned in [
        'foreignIdRaw:', 'rawForeignId:', 'foreignIdNumberPlain',
        'normalized,',
      ]) {
        expect(finalize, isNot(contains(banned)),
            reason: '$banned — 전체 번호를 저장하면 안 된다');
      }
      // 저장되는 것은 HMAC 하나다.
      expect(finalize, contains('foreignIdentityFingerprint: fingerprint'));
    });

    test('16 전체 번호를 로그에 남기지 않는다', () {
      final finalize = _src(_cfPath);
      expect(finalize, isNot(contains('normalized}')),
          reason: '로그 문자열에 전체 번호 보간 금지');
      expect(finalize, contains('idLen='), reason: '길이만 남긴다');
    });

    test('17 파생값은 기존 필드에만 쓴다 (birthDate / gender)', () {
      final finalize = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableFinalizeForeignIdentity = onCall(',
          'FINALIZE_STAGE_COMPLETE')));
      expect(finalize, contains('const serverGender ='));
      expect(finalize, contains('serverGender ? {gender: serverGender} : {}'));
      expect(finalize, contains('birthDate: admin.firestore.Timestamp.fromDate(serverBirthDate)'));
    });

    test('18 표에 없는 성별코드는 추측하지 않는다', () {
      final finalize = _flat(_codeOf(_sliceOf(rawCf,
          'const serverGender =', 'const fpDocId')));
      expect(finalize, contains('genderDigit === 5 || genderDigit === 7'));
      expect(finalize, contains('genderDigit === 6 || genderDigit === 8'));
      expect(finalize, contains(': null'),
          reason: '구 규칙 코드(9 등)는 기대값을 만들지 않는다 — 거짓 불일치 방지');
    });
  });

  group('규칙은 한 곳에만 있다', () {
    test('19 화면이 성별코드를 직접 계산하지 않는다', () {
      final scr = _codeOf(_src(_docScreen));
      expect(scr, contains('expectedIdentifierForUser(user).prefix'));
      // 화면 안에 있던 계산은 사라져야 한다.
      expect(scr, isNot(contains('isMale ? 3 : 4')));
      expect(scr, isNot(contains("final isMale = user.gender == '남성'")));
    });

    test('20 국적 판정은 파생 getter를 쓴다 (dead field 금지)', () {
      final id = _codeOf(_src(_idPath));
      expect(id, contains('isForeign: user.isForeign'));
      expect(id, isNot(contains("map['isForeign']")));
      expect(id, isNot(contains("['isForeign']")));
    });

    test('21 규칙 구현이 한 파일에만 있다', () {
      // +4 변환이 여러 화면에 복사되면 또 갈라진다.
      var hits = 0;
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final t = _codeOf(e.readAsStringSync());
        if (t.contains('nativeCode + 4') || t.contains('genderCode - 4')) {
          hits++;
          // register_screen의 -4는 가입 입력 파싱 — 기대값 생성과 다른 축이다.
          expect(
              e.path.replaceAll(r'\', '/'),
              anyOf(contains('identity_identifier.dart'),
                  contains('register_screen.dart')),
              reason: '기대값 생성 규칙이 ${e.path} 에 복사됐다');
        }
      }
      expect(hits, greaterThan(0));
    });
  });

  group('R — 회귀', () {
    test('22 native PASS flow 무변경', () {
      // 실제 export 이름은 `verifyPassAuth`다 — CLAUDE.md의
      // `callableVerifyPassAuth` 표기는 문서 쪽 드리프트다.
      expect(cf, contains('export const verifyPassAuth = onCall('));
      expect(cf, contains('passVerifiedAt: admin.firestore.FieldValue.serverTimestamp()'));
      // R1.1 predicate 유지
      expect(cf, contains('srvIsForeignIdentity('));
    });

    test('23 isIdVerified 의미 무변경 — 업로드 완료', () {
      final mark = _flat(_codeOf(_sliceOf(rawCf,
          'export const callableMarkIdCardVerified = onCall(',
          'callableGetDocumentsPendingReview')));
      expect(mark, contains('isIdVerified: true'));
      expect(mark, contains('idDocumentVersion: admin.firestore.FieldValue.increment(1)'));
    });

    test('24 확정 게이트·문서 검토는 이번에 건드리지 않았다', () {
      expect(cf, contains('srvResolveReviewReadiness'));
      expect(cf, isNot(contains('documentMatchStatus')),
          reason: '최종 schema는 R1.4다');
      expect(cf, isNot(contains('matchAssurance')));
    });

    test('25 통장 판정 로직은 R1.3에서 바뀌었다', () {
      // R1.2 시점에는 'final isValid = isNameValid;'가 남아 있는 것이
      //   "아직 손대지 않았다"의 표시였다. R1.3이 그 자리를 처리했다.
      final ocr = _codeOf(_src(_ocrPath));
      expect(ocr, isNot(contains('final isValid = isNameValid;')));
      expect(ocr, contains('final isDocumentConsistent ='),
          reason: '계좌번호 MATCHED가 필수 조건이 됐다');
    });
  });
}
