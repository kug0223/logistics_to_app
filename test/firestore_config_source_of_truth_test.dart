// [R7-P4.4E.11C.1.1] 탈퇴에 필요한 인덱스가 repo 에 없었다
//
// DEV runtime 에서 이 쿼리가 실패했다.
//
//   db.collectionGroup("members").where("uid", "==", uid)
//   → FAILED_PRECONDITION
//     The query requires a COLLECTION_GROUP_ASC index
//     for collection members and field uid
//
// 그 결과 개인정보 정리가 `queryFailed` 로 끝나고,
// `srvDeletionPersonalCleared` 가 영구히 false 가 되어
// `callableDeleteAccountFinal` 이 `FIRESTORE_RETRYABLE` 을 무한 반복했다.
// fail-closed 자체는 옳았다 — 아무것도 파괴하지 않았다. 문제는
// `firestore.indexes.json` 에 그 인덱스 선언이 없다는 것이었다.
// 즉 깨끗한 환경에 repo 만 배포하면 **회원탈퇴가 완료되지 않는다.**
//
// 두 번째 문제는 같은 뿌리에서 나왔다. `passTokens.expiresAt` 의 TTL 은
// 콘솔에만 있었고, 코드는 그 TTL 을 전제로 스케줄러를 지웠다
// (`cleanExpiredPassTokens 제거 — Firestore TTL 정책으로 대체`).
// 그래서 index 배포 한 번이 만료 PASS 토큰(이름·생년·전화·ciHash)을
// 지우는 **유일한 주인**을 조용히 없앴다.
//
// 고정하는 것
//   FCS-IDX-*    members.uid 선언의 정확한 모양
//   FCS-TTL-*    TTL canonical 표현과 금지 TTL
//   FCS-KEEP-*   기존 선언 보존
//   FCS-QUERY-*  쿼리 ↔ 인덱스 계약
//   FCS-GUARD-*  파괴적 배포 전 drift guard
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('소스를 찾지 못했다: $p');
  return f.readAsStringSync();
}

Map<String, dynamic> _indexes() =>
    jsonDecode(_src('firestore.indexes.json')) as Map<String, dynamic>;

List<Map<String, dynamic>> _overrides() =>
    ((_indexes()['fieldOverrides'] as List).cast<Map<String, dynamic>>());

Map<String, dynamic>? _override(String cg, String fieldPath) {
  for (final o in _overrides()) {
    if (o['collectionGroup'] == cg && o['fieldPath'] == fieldPath) return o;
  }
  return null;
}

/// 주석을 지운 코드만 — 주석 문구가 바뀌어도 깨지지 않게.
String _codeOf(String path) {
  final out = StringBuffer();
  for (final line in _src(path).split('\n')) {
    final t = line.trimLeft();
    if (t.startsWith('//') || t.startsWith('*') || t.startsWith('/*')) continue;
    out.writeln(line);
  }
  return out.toString();
}

void main() {
  group('FCS-IDX members.uid collection-group 인덱스', () {
    test('FCS-IDX-01 선언이 존재한다', () {
      final o = _override('members', 'uid');
      expect(o, isNotNull,
          reason: 'members.uid fieldOverride 가 없으면 탈퇴가 완료되지 않는다');
    });

    test('FCS-IDX-02 COLLECTION_GROUP + ASCENDING 을 포함한다', () {
      final idx = (_override('members', 'uid')!['indexes'] as List)
          .cast<Map<String, dynamic>>();
      final hasCgAsc = idx.any((i) =>
          i['queryScope'] == 'COLLECTION_GROUP' && i['order'] == 'ASCENDING');
      expect(hasCgAsc, isTrue,
          reason: 'Firestore 가 요구한 것은 COLLECTION_GROUP_ASC 다');
    });

    test('FCS-IDX-03 필요 범위만 선언한다 — 쓰지 않는 scope/모드를 넣지 않는다', () {
      final idx = (_override('members', 'uid')!['indexes'] as List)
          .cast<Map<String, dynamic>>();
      expect(idx.length, 1,
          reason: 'uid 를 collection scope 로 필터·정렬하는 쿼리가 코드에 없다');
      expect(idx.single['order'], 'ASCENDING');
      expect(idx.single['queryScope'], 'COLLECTION_GROUP');
      expect(idx.single.containsKey('arrayConfig'), isFalse,
          reason: 'uid 는 배열이 아니다');
    });

    test('FCS-IDX-04 composite indexes 쪽에 넣지 않았다 — single-field override 다', () {
      final composites = (_indexes()['indexes'] as List)
          .cast<Map<String, dynamic>>()
          .where((i) => i['collectionGroup'] == 'members');
      expect(composites, isEmpty,
          reason: 'single-field collection-group 인덱스는 fieldOverrides 로 선언한다');
    });
  });

  group('FCS-TTL TTL canonical 표현', () {
    test('FCS-TTL-01 passTokens.expiresAt TTL 이 repo 에 선언돼 있다', () {
      final o = _override('passTokens', 'expiresAt');
      expect(o, isNotNull);
      expect(o!['ttl'], isTrue,
          reason: 'TTL 이 콘솔에만 있으면 index 배포가 그것을 지운다');
    });

    test('FCS-TTL-02 코드가 그 TTL 을 전제로 스케줄러를 지웠다는 사실을 함께 고정한다', () {
      final code = _src('functions/src/index.ts');
      expect(code.contains('cleanExpiredPassTokens'), isTrue,
          reason: 'TTL 이 유일한 삭제 주인이라는 근거 주석이 사라지면 안 된다');
      expect(code.contains('expiresAt'), isTrue);
    });

    test('FCS-TTL-03 passTokens.expiresAt 의 collection scope 인덱스를 지우지 않는다', () {
      final idx = (_override('passTokens', 'expiresAt')!['indexes'] as List)
          .cast<Map<String, dynamic>>();
      final scopes = idx.map((i) => '${i['queryScope']}:${i['order']}').toSet();
      expect(scopes.contains('COLLECTION:ASCENDING'), isTrue);
      expect(scopes.contains('COLLECTION:DESCENDING'), isTrue);
    });

    test('FCS-TTL-04 account_deletion_tombstones 에는 TTL 을 선언하지 않는다', () {
      for (final o in _overrides()) {
        if (o['collectionGroup'] == 'account_deletion_tombstones') {
          expect(o['ttl'], isNot(true),
              reason: 'tombstone 이 사라지면 Auth-tail 재개 증거가 사라진다');
        }
      }
      final tomb = _override('account_deletion_tombstones', 'barrierAt');
      expect(tomb, isNull,
          reason: 'barrierAt TTL 은 어떤 이유로도 추가하지 않는다');
    });
  });

  group('FCS-KEEP 기존 선언 보존', () {
    test('FCS-KEEP-01 slots.status override 가 그대로 있다', () {
      final o = _override('slots', 'status');
      expect(o, isNotNull);
      expect((o!['indexes'] as List).length, 4);
    });

    test('FCS-KEEP-02 composite index 수를 줄이지 않았다', () {
      expect((_indexes()['indexes'] as List).length, greaterThanOrEqualTo(118));
    });
  });

  group('FCS-QUERY 쿼리 ↔ 인덱스 계약', () {
    test('FCS-QUERY-01 정리 경로가 members 를 uid equality 로 collectionGroup 조회한다', () {
      final code = _codeOf('functions/src/index.ts');
      final hits =
          RegExp(r'collectionGroup\("members"\)').allMatches(code).length;
      expect(hits, greaterThanOrEqualTo(2),
          reason: '정리와 잔존 재집계 두 곳이 같은 쿼리를 쓴다');
      expect(code.contains('.where("uid", "==", uid)'), isTrue,
          reason: '필드가 바뀌면 선언한 인덱스가 더 이상 맞지 않는다');
    });

    test('FCS-QUERY-02 개인정보 정리 실패를 0 으로 읽지 않는다', () {
      final code = _codeOf('functions/src/index.ts');
      expect(code.contains('queryFailed'), isTrue);
      expect(code.contains('!r.queryFailed && r.locations === 0'), isTrue,
          reason: '인덱스가 없어 쿼리가 실패하면 파괴를 멈춰야 한다');
    });
  });

  group('FCS-GUARD 파괴적 배포 전 drift guard', () {
    const guard = 'scripts/check-firestore-config-drift.js';

    test('FCS-GUARD-01 체커가 존재한다', () {
      expect(File(guard).existsSync(), isTrue);
    });

    test('FCS-GUARD-02 PROD 프로젝트를 거부한다', () {
      final code = _codeOf(guard);
      expect(code.contains("FORBIDDEN_PROJECTS"), isTrue);
      expect(code.contains("'alfit-prod'"), isTrue);
      expect(code.contains('FORBIDDEN_PROJECTS.includes(project)'), isTrue);
    });

    test('FCS-GUARD-03 remote-only 구성이 있으면 STOP 한다', () {
      final code = _codeOf(guard);
      expect(
          code.contains('d.composite.remoteOnly.length > 0 ||\n      d.override.remoteOnly.length > 0') ||
              code.contains('d.composite.remoteOnly.length > 0 || d.override.remoteOnly.length > 0'),
          isTrue,
          reason: 'remote-only 구성을 무시하면 배포가 그것을 지운다');
      expect(code.contains('return {code: 1, reasons}'), isTrue);
    });

    test('FCS-GUARD-04 repo 에 표현되지 않은 remote TTL 을 STOP 한다', () {
      final code = _codeOf(guard);
      expect(code.contains('t.unrepresented.length > 0'), isTrue);
      expect(code.contains('return {code: 3, reasons}'), isTrue);
    });

    test('FCS-GUARD-04a 판정 조건을 상수로 무력화하지 않았다', () {
      // 조건식을 남겨둔 채 `false &&` 를 끼워 넣으면 텍스트 pin 은 통과한다.
      // 판정 함수 본문에서 그 수법을 직접 금지한다.
      final code = _codeOf(guard);
      final start = code.indexOf('function verdict(');
      expect(start, greaterThan(-1));
      final body = code.substring(start, code.indexOf('\n}', start));
      for (final cheat in ['false &&', '&& false', 'true ||', '|| true']) {
        expect(body.contains(cheat), isFalse, reason: '판정에 $cheat 가 있다');
      }
    });

    test('FCS-GUARD-05 금지된 tombstone TTL 을 STOP 한다', () {
      final code = _codeOf(guard);
      expect(code.contains('account_deletion_tombstones'), isTrue);
      expect(code.contains('t.forbidden.length > 0'), isTrue);
      expect(code.contains('return {code: 4, reasons}'), isTrue);
    });

    test('FCS-GUARD-06 TTL 만 걸린 field 도 보이는 filter 를 쓴다', () {
      final code = _codeOf(guard);
      expect(code.contains("ttlConfig:*"), isTrue,
          reason: 'usesAncestorConfig=false 만으로는 TTL-only field 가 안 보인다');
      expect(code.contains('indexConfig.usesAncestorConfig=false OR'), isTrue);
    });

    test('FCS-GUARD-07 조회 실패를 drift 없음으로 읽지 않는다', () {
      final code = _codeOf(guard);
      expect(code.contains('return 2'), isTrue);
      expect(code.contains('remote 조회 실패'), isTrue);
    });

    test('FCS-GUARD-08 D1~D5 self-test 를 들고 있다', () {
      final code = _codeOf(guard);
      for (final c in ['D1', 'D2', 'D3', 'D4', 'D5']) {
        expect(code.contains(c), isTrue, reason: '$c 케이스가 없다');
      }
      expect(code.contains("argv.includes('--self-test')"), isTrue);
    });

    test('FCS-GUARD-09 시크릿을 출력하지 않는다', () {
      final code = _src(guard);
      expect(code.contains('readFileSync(keyFile'), isFalse,
          reason: '키 파일 내용을 읽어 출력할 길을 만들지 않는다');
      expect(code.contains('console.log(keyFile'), isFalse);
      expect(code.contains('--json'), isFalse,
          reason: 'functions:list --json 은 환경변수 시크릿을 평문으로 담는다');
    });
  });
}
