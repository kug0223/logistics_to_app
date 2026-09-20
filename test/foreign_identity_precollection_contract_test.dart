// [PII-B4-R1.3A] 전체번호 수집을 시작하기 전에 닫아야 하는 것들
//
// 이 파일이 고정하는 것:
//
//   INV-1  식별번호는 로그 문자열이 되지 않는다 (릴리스 포함)
//   INV-2  외국인 경로는 외국인 코드만 받는다 (1~4 통과 금지)
//   INV-3  잘못된 코드로 birthDate·gender가 파생되지 않는다
//   INV-4  민감번호 경고 탐지가 내국인·외국인을 같이 본다
//   INV-5  처리방침이 실제 수집보다 많이도, 적게도 말하지 않는다
//
// R1.4(Tax Identity writer/OCR/gate)는 여기서 다루지 않는다.

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

/// debugPrint(...) 호출 전체를 뽑는다 — 중첩 괄호·보간 때문에 정규식 대신 괄호 세기.
List<String> _debugPrints(String code) {
  final out = <String>[];
  var i = 0;
  while (true) {
    final s = code.indexOf('debugPrint(', i);
    if (s < 0) break;
    var depth = 0;
    var j = s + 'debugPrint'.length;
    for (; j < code.length; j++) {
      final c = code[j];
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) break;
      }
    }
    out.add(code.substring(s, j + 1));
    i = j + 1;
  }
  return out;
}

const _foreignScreen = 'lib/screens/auth/foreign_register_screen.dart';
const _authService = 'lib/services/auth_service.dart';
const _foreignOcr = 'lib/services/foreign_id_ocr_service.dart';
const _parser = 'lib/utils/contract_article_parser.dart';
const _terms = 'lib/models/core/legal_terms_model.dart';
const _privacyHtml = 'public/privacy.html';
const _cfPath = 'functions/src/index.ts';

void main() {
  final screenRaw = _src(_foreignScreen);
  final screen = _codeOf(screenRaw);
  final authRaw = _src(_authService);
  final auth = _codeOf(authRaw);
  final ocr = _codeOf(_src(_foreignOcr));
  final cfRaw = _src(_cfPath);
  final cf = _codeOf(cfRaw);

  group('INV-1 — 식별번호는 로그가 되지 않는다 (§2·§3·§23)', () {
    test('01 알려진 3곳에서 앞 8자리 마스킹이 사라졌다', () {
      // 13자리 중 마지막은 체크섬이므로 8자리를 주면 남는 건 4자리뿐이다.
      expect(screen, isNot(contains("rawId.substring(0, 8)")),
          reason: '_processRegistration / _commitFreshRegistration');
      expect(auth, isNot(contains("rawForeignId.substring(0, 8)")),
          reason: 'finalizeForeignIdentity');
      // 변수 이름째로 사라져야 재사용되지 않는다.
      expect(screen, isNot(contains('dbgMaskedId')));
      expect(auth, isNot(contains('maskedId')));
    });

    test('02 실명이 로그에 실리지 않는다', () {
      // 값이 아니라 "있는가"만 남는다 — hasLegalName=true 는 이름이 아니다.
      for (final entry in {_foreignScreen: screen, _authService: auth}.entries) {
        for (final line in _debugPrints(entry.value)) {
          expect(line.contains(r'$legalName'), isFalse, reason: '${entry.key}: $line');
          expect(line.contains(r'${legalName}'), isFalse, reason: '${entry.key}: $line');
          if (line.contains('legalName')) {
            expect(line, contains('hasLegalName='), reason: '${entry.key}: $line');
          }
        }
      }
    });

    test('03 등록번호에서 파생된 어떤 값도 로그에 없다', () {
      for (final entry in {_foreignScreen: screen, _authService: auth}.entries) {
        for (final line in _debugPrints(entry.value)) {
          for (final banned in [
            'rawId.substring', 'rawForeignId.substring', 'sentinelId',
            r'$rawId', r'$rawForeignId', 'foreignIdRaw',
          ]) {
            expect(line.contains(banned), isFalse, reason: '${entry.key}: $line');
          }
        }
      }
    });

    test('04 남은 진단값은 비식별 metadata다', () {
      // 길이·불리언·uid는 §3 허용 목록이다. 값이 아니라 상태를 남긴다.
      expect(screen, contains(r'idLen=${rawId.length}'));
      expect(screen, contains(r'hasLegalName=${legalName.isNotEmpty}'));
      expect(auth, contains(r'idLen=$idLen'));
      expect(auth, contains('hasLegalName='));
      expect(auth, contains('hasVisaType='));
    });

    test('05 kDebugMode로 감싸는 방식으로 되돌리지 않았다 (§4)', () {
      // 민감값을 만들어 놓고 debug에서만 찍는 것도 금지다 — 값을 만들지 않는다.
      final guarded = RegExp(r'kDebugMode[^;]{0,200}(rawId|rawForeignId)\.substring');
      expect(guarded.hasMatch(screen), isFalse);
      expect(guarded.hasMatch(auth), isFalse);
    });

    test('06 OCR 서비스의 기존 마스킹은 그대로다 (회귀 금지)', () {
      // 여기는 원래 7자리 + kDebugMode였다. 이번에 건드리지 않았다.
      expect(ocr, contains("rawId.substring(0, 6)"));
      expect(ocr, isNot(contains("rawId.substring(0, 8)")));
    });

    test('07 서버 로그는 길이만 남긴다 (§5)', () {
      final finalizeLogs = RegExp(r'console\.(info|log|warn|error)\([^\n]*')
          .allMatches(cf)
          .map((m) => m.group(0)!)
          .where((l) => l.contains('finalize') || l.contains('Foreign'));
      expect(finalizeLogs, isNotEmpty, reason: 'finalize 로그를 찾지 못함');
      for (final l in finalizeLogs) {
        expect(l.contains(r'${normalized}'), isFalse, reason: l);
        expect(l.contains('rawForeignId'), isFalse, reason: l);
        expect(l.contains('legalName'), isFalse, reason: l);
      }
      expect(cf, contains(r'idLen=${normalized.length}'));
    });
  });

  group('INV-2 — 외국인 경로는 외국인 코드만 받는다 (§6·§24)', () {
    final normFn = _flat(_codeOf(
        _sliceOf(cfRaw, 'function normalizeForeignId(', '\n}')));

    test('08 허용 코드 집합이 5·6·7·8 뿐이다', () {
      expect(cf, contains(
          'const FOREIGN_GENDER_CODES = new Set(["5", "6", "7", "8"]);'));
    });

    test('09 옛 규칙("0이 아니면 통과")이 사라졌다', () {
      expect(normFn, isNot(contains('normalized[6] === "0"')),
          reason: '내국인 1~4가 통과하던 규칙');
    });

    test('10 정규화가 그 집합으로 판정한다', () {
      expect(normFn, contains('if (!FOREIGN_GENDER_CODES.has(normalized[6])) return null;'));
      // 길이·숫자 검사는 그대로 앞에 남아 있어야 한다.
      expect(normFn, contains(r'if (!/^\d{13}$/.test(normalized)) return null;'));
    });

    test('11 9는 추측으로 열지 않았다', () {
      expect(cf, isNot(contains('new Set(["5", "6", "7", "8", "9"]')));
    });

    test('12 precheck와 finalize가 같은 관문을 쓴다', () {
      expect('normalizeForeignId('.allMatches(cf).length, 3,
          reason: '정의 1 + precheck 1 + finalize 1');
    });

    test('13 거부 사유를 사용자에게 설명한다', () {
      // "13자리 숫자여야 합니다"는 13자리인 주민번호를 넣은 사람에게 거짓말이었다.
      expect(cf, contains('FOREIGN_ID_FORMAT_MESSAGE'));
      expect(cf, contains('뒷자리 첫 숫자가 5~8인지'));
      expect(cf, isNot(contains('"외국인등록번호는 13자리 숫자여야 합니다."')));
    });
  });

  group('INV-3 — 잘못된 코드로 파생값이 생기지 않는다 (§7·§9)', () {
    test('14 파생은 여전히 서버가 한다', () {
      expect(cf, contains('birthDate: admin.firestore.Timestamp.fromDate(serverBirthDate)'));
      expect(cf, contains('const serverGender ='));
    });

    test('15 파생 표는 그대로다 — 5·7 남성 / 6·8 여성', () {
      expect(_flat(cf), contains(
          '(genderDigit === 5 || genderDigit === 7) ? "남성" : '
          '((genderDigit === 6 || genderDigit === 8) ? "여성" : null)'));
      expect(_flat(cf), contains(
          'const birthYear = (genderDigit === 7 || genderDigit === 8) ? '
          '(2000 + yy) : (1900 + yy);'));
    });

    test('16 sentinel·fingerprint semantics 회귀 없음', () {
      expect(cf, contains('foreignIdentityFingerprint: fingerprint'));
      expect(cf, contains('computeForeignIdFingerprint'));
      expect(screen, contains(r"'${rawId.substring(0, 6)}-${rawId[6]}${'*' * 6}'"));
    });

    test('17 외국인 가입 경로가 살아 있다 (§29)', () {
      expect(screen, contains('finalizeForeignIdentity('));
      expect(auth, contains("httpsCallable('callableFinalizeForeignIdentity'"));
      expect(auth, contains("httpsCallable('callablePrecheckForeignIdentity'"));
      expect(_src('lib/screens/auth/register_screen.dart'),
          contains('ForeignRegisterScreen(role: _selectedRole!)'));
    });
  });

  group('INV-4 — 민감번호 경고가 양쪽을 본다 (§16)', () {
    final parser = _codeOf(_src(_parser));

    test('18 내국인 1~4 + 외국인 5~8', () {
      expect(parser, contains(r"RegExp(r'\d{6}-[1-8]\d{6}')"));
      expect(parser, isNot(contains(r"RegExp(r'\d{6}-[1-4]\d{6}')")));
    });

    test('19 실제로 외국인등록번호를 잡는다', () {
      final rrn = RegExp(r'\d{6}-[1-8]\d{6}');
      expect(rrn.hasMatch('900101-1234567'), isTrue, reason: '내국인');
      expect(rrn.hasMatch('001020-5123456'), isTrue, reason: '외국인 5');
      expect(rrn.hasMatch('001020-8123456'), isTrue, reason: '외국인 8');
      expect(rrn.hasMatch('001020-9123456'), isFalse, reason: '9는 범위 밖');
      expect(rrn.hasMatch('010-1234-5678'), isFalse, reason: '전화번호');
    });
  });

  group('INV-5 — 처리방침이 실제와 같다 (§10~§15·§27)', () {
    final terms = _src(_terms);
    final html = _src(_privacyHtml);
    final both = {_terms: terms, _privacyHtml: html};

    test('20 실제로 수집하는 것을 고지한다', () {
      for (final e in both.entries) {
        for (final must in [
          '외국인등록번호 13자리',
          '외국인등록증 사진',
          '외국인등록증에 기재된 공식 이름',
          '체류자격(비자 종류)',
        ]) {
          expect(e.value, contains(must), reason: e.key);
        }
      }
    });

    test('21 취업자격 심사를 주장하지 않는다 (§14)', () {
      for (final e in both.entries) {
        expect(e.value, contains('취업 가능 여부나 체류 자격의 적법성을 심사·판정하지 않습니다'),
            reason: e.key);
        for (final banned in [
          '취업자격 인증', '취업 자격 인증', '취업자격 확인 완료',
          '정부 인증 완료', '체류자격 검증',
        ]) {
          expect(e.value, isNot(contains(banned)), reason: '$banned in ${e.key}');
        }
      }
    });

    test('22 수집하지 않는 것을 수집한다고 하지 않는다 (§15)', () {
      // stayExpiryDate는 클라이언트가 보내지 않는다 — 고지 목록에 없어야 한다.
      for (final e in both.entries) {
        expect(e.value, isNot(contains('체류기간만료일')), reason: e.key);
        expect(e.value, isNot(contains('체류 기간 만료일')), reason: e.key);
      }
    });

    test('23 주민등록번호 drift가 정정됐다 (§13)', () {
      for (final e in both.entries) {
        expect(e.value, isNot(contains('주민등록번호 — 근로계약서 작성 시 입력')),
            reason: '존재하지 않는 입력 UI를 설명하던 문구: ${e.key}');
        // [PII-B4-R1.3B §5] R1.3A는 여기에 "향후 수집 예정"까지 적었다.
        //   로드맵은 수집항목이 아니다 — 현재 사실만 남기고 변경은 개정 조항으로
        //   옮겼다. 문구 truth 전수는 legal_terms_current_truth_contract_test.
        expect(e.value, contains('주민등록번호 — 현재 수집하지 않습니다'),
            reason: e.key);
      }
    });

    test('24 예정 기능을 제공 중인 것처럼 말하지 않는다 (§11)', () {
      for (final e in both.entries) {
        // [PII-B4-R1.3B §5] 변경 예고는 일반 개정 조항으로만 한다.
        expect(e.value, contains('■ 처리방침의 개정'), reason: e.key);
        expect(e.value, isNot(contains('수집할 예정이며')), reason: e.key);
        // 아직 없는 기능 — 제공 중이라고 쓰면 안 된다.
        expect(e.value, isNot(contains('지급명세서를 제출합니다')), reason: e.key);
        expect(e.value, isNot(contains('홈택스')), reason: e.key);
      }
    });

    test('25 OCR 전송 사실을 숨기지 않는다', () {
      for (final e in both.entries) {
        expect(e.value, isNot(contains('신분증 OCR 텍스트 인식 — 기기 내 처리 전용, 서버 저장 없음')),
            reason: '외국인등록번호는 실제로 서버로 전송된다: ${e.key}');
        expect(e.value, contains('외국인등록번호는 동일인 식별을 위해 서버로 전송되며'),
            reason: e.key);
      }
    });

    test('26 목적에 세무·정합성 확인이 들어갔다 (§12)', () {
      for (final e in both.entries) {
        expect(e.value, contains('급여 공제 계산 및 소득신고·원천징수 등 법정 세무 처리'),
            reason: e.key);
        expect(e.value, contains('본인 및 제출 서류 정보의 정합성 확인'), reason: e.key);
      }
    });

    test('27 안전성 조치 문구가 실제 보관 형태와 같다', () {
      for (final e in both.entries) {
        expect(e.value, isNot(contains('주민등록번호 등 민감 정보는 AES 암호화 저장')),
            reason: '신규 저장이 없는데 저장한다고 읽히던 문구: ${e.key}');
        expect(e.value, contains('복원이 불가능한 고유값으로 변환해 보관'), reason: e.key);
      }
    });

    test('28 개정된 항목의 version이 올라갔다', () {
      final privacyItem = _sliceOf(terms, "id: 'privacy_policy'", 'order: 2');
      expect(privacyItem, contains("version: '2026.09'"));
      // 내용이 바뀌지 않은 항목은 그대로다.
      final serviceItem = _sliceOf(terms, "id: 'service_terms'", 'order: 1');
      expect(serviceItem, contains("version: '2026.08'"));
    });
  });

  group('범위 — R1.4는 아직 아니다 (§18·§30)', () {
    test('29 taxIdentities / tax secret 을 만들지 않았다', () {
      for (final banned in [
        'taxIdentities', 'TAX_ID_HMAC_SECRET', 'TAX_ID_ENCRYPT_KEY',
        'callableRegisterTaxIdentity', 'callableUpdateTaxIdentity',
      ]) {
        expect(cf, isNot(contains(banned)), reason: banned);
      }
      expect(_src('firestore.rules'), isNot(contains('taxIdentities')));
    });

    test('30 지원 gate를 바꾸지 않았다', () {
      final gate = _codeOf(_sliceOf(
          _src('lib/screens/user/apply_prerequisites_screen.dart'),
          'bool meetsApplyPrerequisites(', '\n}'));
      expect(gate, isNot(contains('TaxIdentity')));
      expect(gate, isNot(contains('taxIdentity')));
      // 기존 조건은 그대로다.
      expect(gate, contains('if (!user.hasBankAccount) return false;'));
      expect(gate, contains('if (!user.hasIdDocument)'));
    });

    test('31 내국인 OCR parser를 확장하지 않았다', () {
      final idOcr = _src('lib/utils/ocr_verification_helper.dart');
      expect(idOcr, contains(r"RegExp(r'(\d{6})[-\s]?(\d)')"),
          reason: '13자리 확장은 R1.4');
    });

    test('32 CONFIRMED 자동 신분증 grant 재도입 없음 (§29)', () {
      expect(cf, isNot(contains('ensureIdCardGrantForConfirmedApplication')));
      expect(cf, isNot(contains('callableAdminVerifyIdCard')));
    });
  });
}
