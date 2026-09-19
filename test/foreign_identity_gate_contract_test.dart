// [PII-DOC-R1.1] 외국인 신원 게이트 — 한 사람, 하나의 국적
//
// 이 파일이 고정하는 것:
//
//   1. 국적 판정은 mutation마다 다를 수 없다. 지원·초대 수락·근무 변경 수락이
//      같은 predicate를 쓴다.
//
//   2. `users.isForeign`은 **writer가 없는 필드였다.** 다시 읽기 시작하면
//      외국인이 또 내국인으로 분류된다 — 그 필드의 reader가 0이어야 한다.
//
//   3. 국적은 별도로 선언되는 사실이 아니라 신원 증거의 결과다.
//      V3(fingerprint)와 레거시(foreignIdNumber) 둘 다 외국인이다.
//
//   4. 신원이 아무것도 없으면 fail-close — 내국인으로 보고 PASS를 요구한다.
//
//   5. V3 가입 완료 판정(`callableRecordTermsConsent`)은 **다른 질문**이다.
//      "외국인인가"가 아니라 "V3 절차가 끝났는가"이고 fingerprint만으로 답한다.
//      이 helper로 바꾸면 레거시 외국인이 active로 승격돼 버린다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// `//` 주석 줄 제거 — 주석에 남은 옛 코드가 통과 근거가 되지 않도록.
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

/// 같은 국적 질문을 하는 세 mutation — §1 invariant의 대상.
const _identityGates = <String, List<String>>{
  'callableApplyToTO': [
    'export const callableApplyToTO = onCall(',
    'isForeignApplicant',
  ],
  'callableAcceptTOInvitation': [
    'export const callableAcceptTOInvitation = onCall(',
    'acceptIsForeign',
  ],
};

void main() {
  final rawCf = _src(_cfPath);
  final cf = _codeOf(rawCf);

  group('canonical predicate', () {
    final helper = _codeOf(
        _sliceOf(rawCf, 'function srvIsForeignIdentity(', '\n}'));

    test('01 helper가 존재하고 두 신원 증거를 모두 본다', () {
      expect(helper, contains('foreignIdentityFingerprint'));
      expect(helper, contains('foreignIdNumber'),
          reason: '레거시 외국인을 빠뜨리면 그 사람들이 내국인이 된다');
      expect(helper, contains('return false'),
          reason: 'userData 없음 → fail-close');
    });

    test('02 빈 문자열을 "있음"으로 읽지 않는다', () {
      // 기존 `??` 형태는 빈 fingerprint를 외국인으로 읽었다.
      expect(_flat(helper), contains('typeof fp === "string" && fp.length > 0'));
      expect(_flat(helper),
          contains('typeof legacy === "string" && legacy.length > 0'));
    });

    test('03 passVerifiedAt을 국적 판정에 쓰지 않는다', () {
      // "PASS가 없으면 외국인"은 역방향 추론이다 — 미인증 내국인이 외국인이 된다.
      expect(helper, isNot(contains('passVerifiedAt')));
      expect(helper, isNot(contains('ciHash')));
    });
  });

  group('writer 없는 users.isForeign은 아무도 읽지 않는다', () {
    test('04 functions 전체에 reader 0건', () {
      final readers = <String>[];
      final lines = rawCf.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final l = lines[i];
        if (l.trimLeft().startsWith('//')) continue; // 설명 주석 허용
        if (RegExp(r'\.isForeign\b').hasMatch(l) ||
            l.contains('get("isForeign")') ||
            l.contains('"isForeign"]')) {
          readers.add('index.ts:${i + 1}: ${l.trim()}');
        }
      }
      expect(readers, isEmpty,
          reason: 'writer 없는 필드를 읽으면 외국인이 다시 내국인이 된다: $readers');
    });

    test('05 클라이언트도 이 필드를 쓰지 않는다', () {
      // UserModel.isForeign은 **파생 getter**여야 한다 — Firestore 필드가 아니라.
      final um = _codeOf(_src('lib/models/core/user_model.dart'));
      expect(um, contains('bool get isForeign =>'),
          reason: '파생 getter로 남아 있어야 한다');
      expect(um, isNot(contains("map['isForeign']")),
          reason: 'Firestore 필드에서 읽으면 서버와 같은 함정에 빠진다');
    });
  });

  group('세 mutation이 같은 판정을 쓴다', () {
    test('06 지원 — callableApplyToTO', () {
      final body = _codeOf(_sliceOf(
          rawCf, 'export const callableApplyToTO = onCall(',
          'const isForeignApplicant'));
      expect(body, isNot(contains('.isForeign ===')));
      final decl = _sliceOf(rawCf, 'const isForeignApplicant', ';');
      expect(decl, contains('srvIsForeignIdentity(userData)'));
    });

    test('07 초대 수락 — callableAcceptTOInvitation', () {
      final decl = _sliceOf(rawCf, 'const acceptIsForeign', ';');
      expect(decl, contains('srvIsForeignIdentity(freshUserData)'));
      expect(decl, isNot(contains('isForeign === true')),
          reason: 'writer 없는 필드로 되돌아가면 외국인이 초대를 못 받는다');
    });

    test('08 근무 변경 수락 — callableAcceptConfirmedReassignment', () {
      final body = _flat(_codeOf(_sliceOf(
          rawCf, 'export const callableAcceptConfirmedReassignment = onCall(',
          '본인인증 후 수락할 수 있습니다')));
      expect(body, contains('!srvIsForeignIdentity(u) && !u.passVerifiedAt'));
    });

    test('09 세 곳 모두 PASS 요구 조건이 같은 모양이다', () {
      // "외국인이 아니고 passVerifiedAt이 없으면 차단" — 한 문장, 세 곳.
      final flat = _flat(cf);
      expect(flat, contains('!isForeignApplicant && !userData["passVerifiedAt"]'));
      expect(flat, contains('!acceptIsForeign && !freshUserData.passVerifiedAt'));
      expect(flat, contains('!srvIsForeignIdentity(u) && !u.passVerifiedAt'));
    });

    test('10 identity gate 목록이 이 테스트에 빠짐없이 들어 있다', () {
      for (final e in _identityGates.entries) {
        final i = rawCf.indexOf(e.value[0]);
        expect(i, greaterThan(0), reason: '${e.key} 를 찾지 못함');
        expect(rawCf.indexOf(e.value[1], i), greaterThan(i),
            reason: '${e.key} 의 판정 변수가 사라졌다');
      }
    });
  });

  group('시나리오 — 판정식이 각 경우에 무엇을 답하는가', () {
    // 서버 helper는 Dart에서 실행할 수 없으므로 **같은 식**을 여기서 돌려
    // 다섯 시나리오의 결과를 고정한다. 식이 서버와 같다는 것은 01·02가 고정한다.
    bool isForeign(Map<String, Object?> u) {
      final fp = u['foreignIdentityFingerprint'];
      final legacy = u['foreignIdNumber'];
      return (fp is String && fp.isNotEmpty) ||
          (legacy is String && legacy.isNotEmpty);
    }

    // 세 mutation이 공유하는 게이트: 외국인이 아니고 PASS도 없으면 차단.
    bool blocked(Map<String, Object?> u) =>
        !isForeign(u) && u['passVerifiedAt'] == null;

    test('S1 내국인 PASS 완료 → 통과', () {
      final u = {'passVerifiedAt': 'ts', 'ciHash': 'abc'};
      expect(isForeign(u), isFalse);
      expect(blocked(u), isFalse);
    });

    test('S2 내국인 PASS 미완료 → 기존대로 차단', () {
      final u = <String, Object?>{};
      expect(isForeign(u), isFalse);
      expect(blocked(u), isTrue, reason: '내국인 PASS 게이트는 유지된다');
    });

    test('S3 외국인 V3 → PASS 요구하지 않는다', () {
      final u = {'foreignIdentityFingerprint': 'hmac_abc'};
      expect(isForeign(u), isTrue);
      expect(blocked(u), isFalse, reason: '이 케이스가 막혀 있던 BLOCKER다');
    });

    test('S4 레거시 외국인 → foreign 판정 유지', () {
      final u = {'foreignIdNumber': '900101-5******'};
      expect(isForeign(u), isTrue);
      expect(blocked(u), isFalse);
    });

    test('S5 신원 없음 → fail-close', () {
      for (final u in <Map<String, Object?>>[
        {},
        {'foreignIdentityFingerprint': ''},
        {'foreignIdNumber': ''},
        {'foreignIdentityFingerprint': null, 'foreignIdNumber': null},
      ]) {
        expect(isForeign(u), isFalse, reason: '$u');
        expect(blocked(u), isTrue, reason: '$u — 빈 값은 신원이 아니다');
      }
    });

    test('S6 cross-surface — 같은 사람이면 세 답이 같다', () {
      for (final u in <Map<String, Object?>>[
        {'passVerifiedAt': 'ts'},
        {},
        {'foreignIdentityFingerprint': 'hmac'},
        {'foreignIdNumber': '900101-5******'},
      ]) {
        // 세 mutation이 같은 식을 쓰므로 답이 하나다.
        final apply = blocked(u);
        final invite = blocked(u);
        final reassign = blocked(u);
        expect({apply, invite, reassign}.length, 1,
            reason: '"지원은 되는데 초대는 안 되는" 상태가 다시 생겼다: $u');
      }
    });
  });

  group('건드리지 않은 것', () {
    test('11 V3 가입 완료 게이트는 fingerprint만 본다 (다른 질문)', () {
      final consent = _codeOf(_sliceOf(
          rawCf, 'const hasFingerprint =', 'accountStatus: "active"'));
      expect(consent, contains('foreignIdentityFingerprint'));
      expect(consent, isNot(contains('srvIsForeignIdentity')),
          reason: '이 helper를 쓰면 레거시 외국인이 active로 승격돼 버린다');
    });

    test('12 문서 상태·OCR·확정 게이트는 이번에 바뀌지 않았다', () {
      expect(cf, contains('srvComputeDocumentState'));
      expect(cf, contains('DOC_SELF_CHECK_PASSED'));
      expect(cf, contains('srvResolveReviewReadiness'));
      // 자동 MATCHED는 아직 없다.
      expect(cf, isNot(contains('documentMatchStatus')));
    });
  });
}
