// [R7-P4.4E.10A.4] 제어 필드는 서버만 쓴다 · 정리는 신분증만 지운다
//
// 무엇이 잘못됐었나
//
//   10A.1/10A.2 가 신설한 두 필드가 `firestore.rules` 의 **denylist** 에
//   들어가지 않았다. 그 규칙은 열거되지 않은 필드를 허용하므로, DEV 실측에서
//   소유자의 직접 write 가 HTTP 200 으로 통과했다(대조군 `isIdVerified` 는 403).
//
//     idDocumentAttemptSeq   0 으로 되돌리면 제출순서 fail-closed 가 legacy
//                            분기로 떨어진다 — 10A.2 가 막은 경로가 다시 열린다.
//     idDocumentOrphanPaths  서버 삭제 대기 목록이다. 경로를 심으면 다음
//                            신분증 제출에서 서버가 그것을 지운다.
//
//   그리고 정리 술어가 `users/{uid}/` 접두뿐이었다. 그 폴더에는 통장사본
//   (`bankbook_*`)과 사업자등록증(`businessLicense_*`)이 함께 산다 — DEV
//   Storage 실측 18건 = idCard 7 / bankbook 10 / businessLicense 1.
//
// 이 파일이 고정하는 것
//
//   AUTH-1  두 필드는 클라이언트가 쓸 수 없다 (본인·슈퍼관리자·가입)
//   AUTH-2  정리 네임스페이스는 신분증 artifact 하나다
//   AUTH-3  술어는 한 벌이다 — callsite 가 규칙을 복제하지 않는다
//   AUTH-4  writer 입력 경계도 같은 술어를 쓴다
//   AUTH-5  제출순서 계약은 그대로다 (회귀 금지)
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

/// 주석을 뺀 실행 코드만 — 계약은 주석에 대한 것이 아니다.
String _codeOf(String src) => src
    .split(RegExp(r'\r?\n'))
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

String _slice(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

const _cfPath = 'functions/src/index.ts';
const _rulesPath = 'firestore.rules';

/// 두 제어 필드. 이 목록이 늘어나면 테스트도 같이 늘어난다.
const _controlFields = ['idDocumentAttemptSeq', 'idDocumentOrphanPaths'];

void main() {
  final cfRaw = _src(_cfPath);
  final cf = _flat(_codeOf(cfRaw));
  final rulesRaw = _src(_rulesPath);
  final rules = _codeOf(rulesRaw);

  group('AUTH-1 — 제어 필드는 클라이언트가 쓸 수 없다 (§1)', () {
    // 본인 update 규칙은 `isOwner(userId)` 로 시작하는 denylist 하나다.
    String selfUpdateBlock() => _flat(_slice(
        rules, 'allow update: if isLoggedIn() &&\n                       isOwner(userId)', ']);'));

    // 슈퍼관리자 direct update denylist — 본인 블록보다 **앞**에 있다.
    //   anchor 는 규칙 선언 자체다. `isSuperAdmin()` 첫 등장(함수 정의)으로
    //   자르면 파일 앞쪽을 통째로 집어 테스트가 우연히 통과한다.
    String superAdminBlock() => _flat(_slice(
        rules, 'allow update: if isSuperAdmin() &&', ']);'));

    for (final f in _controlFields) {
      test('본인 update denylist 에 $f 가 있다', () {
        expect(selfUpdateBlock(), contains("'$f'"),
            reason: 'denylist 는 열거되지 않은 필드를 허용한다 — 빠지면 그대로 열린다');
      });

      test('슈퍼관리자 update denylist 에 $f 가 있다', () {
        expect(superAdminBlock(), contains("'$f'"),
            reason: '운영 권한이 제출순서·삭제대기를 직접 고칠 이유는 없다');
      });

      test('가입(create) 시 $f 주입이 차단된다', () {
        expect(rules,
            contains("request.resource.data.get('$f', null) == null"),
            reason: '가입 시 심으면 첫 제출부터 가드가 어긋난다');
      });
    }

    test('대조군 — 일반 프로필 필드는 denylist 에 없다', () {
      // 이 테스트가 의미를 가지려면 규칙이 allowlist 가 아니어야 한다.
      final b = selfUpdateBlock();
      for (final ok in ['profileImageUrl', 'address', 'regionKeys']) {
        expect(b, isNot(contains("'$ok'")),
            reason: '정상 프로필 수정은 계속 허용되어야 한다 ($ok)');
      }
    });
  });

  group('AUTH-2 — 정리 네임스페이스는 신분증 하나다 (§3·§4)', () {
    String helper() => _flat(_codeOf(_slice(
        cfRaw, 'function srvIsOwnedIdDocumentStoragePath(', '\n}')));

    test('술어가 소유자 접두를 본다', () {
      expect(helper(), contains(r'const prefix = `users/${uid}/`;'));
      expect(helper(), contains('if (!p.startsWith(prefix)) return false;'));
    });

    test('세그먼트 하나로 제한한다 — 하위 경로·경로 순회 금지', () {
      expect(helper(),
          contains('if (name.includes("/") || name.includes("..")) return false;'),
          reason: '하위 경로를 허용하면 네임스페이스를 벗어나는 길이 생긴다');
    });

    test('실제로 살아 있는 형식만 허용한다 (§3 READ 결과)', () {
      // DEV idCardImagePath 7/7 = users/{uid}/idCard_{millis}.jpg
      // 클라이언트 writer 4곳 전부 같은 모양을 만든다.
      expect(helper(), contains(r'/^idCard_\d{10,}\.(jpg|jpeg|png|webp|heic|heif)$/i'));
    });

    test('negative control — 다른 문서 접두를 허용하지 않는다 (§4)', () {
      // 술어가 `idCard_` 로 시작하는 파일명만 통과시키므로 아래는 전부 탈락한다.
      // 그 사실을 술어 모양으로 고정한다 — 다른 접두를 열면 이 테스트가 깨진다.
      final h = helper();
      for (final other in ['bankbook', 'businessLicense', 'profile']) {
        expect(h, isNot(contains(other)),
            reason: '$other 경로가 신분증 정리 대상이 되면 안 된다');
      }
    });

    test('현재 accepted 경로 보호가 술어보다 먼저 온다', () {
      final del = _flat(_codeOf(_slice(
          cfRaw, 'async function srvDeleteOrQueueOrphan(', 'try {')));
      final protectAt = del.indexOf('path === protect');
      final nsAt = del.indexOf('srvIsOwnedIdDocumentStoragePath');
      expect(protectAt, greaterThan(0));
      expect(nsAt, greaterThan(protectAt),
          reason: '현재 것 보호는 어떤 경우에도 통과해야 한다');
    });

    test('건너뛴 경로를 목록에서 몰래 지우지 않는다', () {
      // 삭제도 안 하면서 기록만 지우면 추적이 사라진다.
      final del = _flat(_codeOf(_slice(
          cfRaw, 'async function srvDeleteOrQueueOrphan(', 'try {')));
      expect(del, isNot(contains('arrayRemove')));
    });
  });

  group('AUTH-3 — 술어는 한 벌이다 (§5)', () {
    test('정의는 하나다', () {
      expect('function srvIsOwnedIdDocumentStoragePath('.allMatches(cf).length, 1);
    });

    test('네 callsite 가 모두 그 하나를 부른다', () {
      // stale cleanup · orphan drain · old-current cleanup 은 모두
      // srvDeleteOrQueueOrphan 을 거치므로 거기 한 번,
      // writer 입력 경계는 두 분기(storagePath / legacy imageUrl)에서 각각.
      final calls = 'srvIsOwnedIdDocumentStoragePath('.allMatches(cf).length;
      expect(calls, greaterThanOrEqualTo(4),
          reason: '정의 1 + 정리 1 + writer 2 = 최소 4');
    });

    test('callsite 가 경로 규칙을 복제하지 않는다', () {
      // `users/${uid}/` 접두 문자열 비교가 신분증 경로 판정에 남아 있지 않다.
      expect(cf, isNot(contains(r'directPath.startsWith(`users/${callerUid}/`)')));
      expect(cf, isNot(contains(r'storagePath.startsWith(`users/${callerUid}/`)')));
    });

    test('drain 은 자기 규칙을 따로 두지 않는다', () {
      final drain = _flat(_codeOf(_slice(
          cfRaw, 'async function srvDrainOrphanPaths(', '\n}')));
      expect(drain, contains('srvDeleteOrQueueOrphan(uid, p, protect)'),
          reason: '삭제 판단은 한 곳에서만 한다');
      expect(drain, isNot(contains('startsWith')));
      expect(drain, isNot(contains('idCard_')));
    });
  });

  group('AUTH-4 — writer 입력 경계 (§6)', () {
    String writer() => _flat(_codeOf(_slice(
        cfRaw, 'export const callableMarkIdCardVerified',
        '[SEC-IDCARD-EXIST]')));

    test('storagePath 분기가 술어를 쓴다', () {
      expect(writer(),
          contains('if (!srvIsOwnedIdDocumentStoragePath(callerUid, directPath)) {'));
    });

    test('legacy imageUrl 분기도 같은 술어를 쓴다', () {
      expect(writer(),
          contains('if (!srvIsOwnedIdDocumentStoragePath(callerUid, storagePath)) {'),
          reason: 'legacy 분기를 느슨하게 두면 좁힌 의미가 없다');
    });

    test('거절은 permission-denied 로 말한다', () {
      expect(writer(), contains('"permission-denied", "본인 신분증 이미지만 등록 가능합니다."'));
    });

    test('클라이언트 writer 4곳이 이 술어를 만족하는 경로를 만든다', () {
      // 좁힌 술어가 실제 호출부를 깨지 않는지 — 소스로 확인한다.
      final screens = [
        'lib/screens/common/document_management_screen.dart',
        'lib/screens/auth/foreign_register_screen.dart',
      ];
      var sites = 0;
      for (final s in screens) {
        for (final m in RegExp(r"'users/\$\{?\w+(\.uid)?\}?/idCard_\$\{?[\w.()]+\}?\.jpg'")
            .allMatches(_codeOf(_src(s)))) {
          expect(m.group(0), contains('/idCard_'));
          sites++;
        }
      }
      expect(sites, 4, reason: 'document_management 1 + foreign_register 3');
    });
  });

  group('AUTH-5 — 제출순서 계약 회귀 금지 (§7)', () {
    test('fail-closed 분기가 그대로다', () {
      expect(cf, contains('if (myAttemptSeq === null) { if (latestSeq > 0) {'));
      expect(cf, contains('reason: "missing-seq"'));
      expect(cf, contains('} else if (myAttemptSeq < latestSeq) {'));
      expect(cf, contains('reason: "stale-seq"'));
    });

    test('순번은 여전히 서버 트랜잭션이 센다', () {
      expect(cf, contains('tx.update(ref, {idDocumentAttemptSeq: next});'));
      expect(cf, contains('return {attemptSeq: seq};'));
    });

    test('클라이언트가 순번을 되돌려 legacy 로 떨어지는 길이 닫혔다', () {
      // 서버는 그대로 `latestSeq > 0` 를 보고, 그 값을 고칠 수 있는 유일한
      // 클라이언트 경로(Firestore 직접 write)는 rules 에서 닫혔다.
      final selfBlock = _flat(_slice(rules,
          'allow update: if isLoggedIn() &&\n                       isOwner(userId)', ']);'));
      expect(selfBlock, contains("'idDocumentAttemptSeq'"));
      expect(cf, contains(r'(cur["idDocumentAttemptSeq"] as number | undefined) ?? 0'));
    });
  });
}
