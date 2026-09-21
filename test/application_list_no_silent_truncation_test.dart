// [R8-P7.1] 관리자 지원목록이 cap 에서 조용히 잘리지 않는다.
//
//   callableGetApplicationsByBiz 는 limit 에서 딱 그만큼 돌려주고 끝이었다.
//   호출부는 그게 전부인지 잘린 것인지 알 방법이 없었고, 전부라고 여겼다.
//   지원서가 cap 을 넘는 사업장에서는 나머지가 말없이 사라진다 —
//   관리자 화면에서는 "지원자가 없다"와 같은 모양이다.
//
//   이제 서버가 hasMore / lastDocId 를 준다. 클라이언트는 페이징 헬퍼
//   하나만 쓰므로 그 신호를 무시할 수 없다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _helperFile = 'lib/services/firestore/application_firestore.dart';

String _read(String path) {
  final f = File(path);
  if (!f.existsSync()) throw StateError('파일을 찾지 못했다: $path');
  return f.readAsStringSync();
}

/// 주석을 지운 코드만 남긴다 — 표지를 주석에 두지 않기 위해.
String _codeOf(String src) => src
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _slice(String raw, String from, String to) {
  final s = raw.indexOf(from);
  if (s < 0) throw StateError('시작 표지를 찾지 못했다: $from');
  final e = raw.indexOf(to, s + from.length);
  if (e < 0) throw StateError('끝 표지를 찾지 못했다: $to');
  return raw.substring(s, e);
}

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// lib/ 아래 모든 .dart 파일
List<File> _libFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'))
    .toList();

void main() {
  group('[R8P7.1] 페이징 헬퍼', () {
    test('TRUNC-1 헬퍼가 hasMore 를 보고 다음 페이지를 읽는다', () {
      final code = _codeOf(_read(_helperFile));
      final body = _flat(_slice(code,
          'Future<List<Map<String, dynamic>>> fetchApplicationsByBizPaged(',
          'extension ApplicationFirestore'));
      expect(body.contains("data['hasMore']"), isTrue,
          reason: 'hasMore 를 읽지 않으면 잘린 것을 전부로 보게 된다');
      expect(body.contains("data['lastDocId']"), isTrue);
      expect(body.contains("'startAfterDocId': cursor"), isTrue,
          reason: 'cursor 를 넘기지 않으면 같은 페이지만 반복한다');
    });

    test('TRUNC-2 페이지 상한을 다 써도 남아 있으면 던진다', () {
      final code = _codeOf(_read(_helperFile));
      final body = _flat(_slice(code,
          'Future<List<Map<String, dynamic>>> fetchApplicationsByBizPaged(',
          'extension ApplicationFirestore'));
      expect(body.contains('throw StateError'), isTrue,
          reason: '조용히 자르는 것을 없애려는 함수가 스스로 조용히 자르면 안 된다');
    });
  });

  group('[R8P7.1] 직접 호출 금지', () {
    test('TRUNC-3 헬퍼 밖에서 callableGetApplicationsByBiz 를 직접 부르지 않는다', () {
      final offenders = <String>[];
      for (final f in _libFiles()) {
        final src = _codeOf(f.readAsStringSync());
        if (!src.contains("httpsCallable('callableGetApplicationsByBiz'")) continue;
        // 헬퍼 자신만 예외다.
        if (f.path.replaceAll(r'\', '/').endsWith(_helperFile)) continue;
        offenders.add(f.path);
      }
      expect(offenders, isEmpty,
          reason: '직접 호출이 살아나면 그 경로만 다시 조용히 잘린다: $offenders');
    });

    test('TRUNC-4 헬퍼 안에서는 한 번만 선언한다', () {
      final src = _codeOf(_read(_helperFile));
      final n = "httpsCallable('callableGetApplicationsByBiz'".allMatches(src).length;
      expect(n, 1, reason: '헬퍼 외의 선언이 파일 안에 생겼다');
    });
  });

  group('[R8P7.1] UNKNOWN ≠ EMPTY', () {
    test('TRUNC-5 사업장 전체 조회 실패를 빈 목록으로 바꾸지 않는다', () {
      final code = _codeOf(_read(_helperFile));
      final body = _flat(_slice(code,
          'Future<List<ApplicationModel>> getApplicationsByBusinessId(',
          'Future<'.padRight(7)));
      expect(body.contains('rethrow'), isTrue,
          reason: '고정 근무자 명단의 원천이다 — 실패를 "근무자 없음"으로 말하면 안 된다');
      expect(body.contains('return [];'), isFalse);
    });
  });

  group('[R8P7.1] 인덱스', () {
    test('TRUNC-6 businessId+appliedAt 복합 인덱스가 정의돼 있다', () {
      final idx = _read('firestore.indexes.json');
      final flat = _flat(idx);
      // applications 컬렉션에 businessId ASC + appliedAt DESC 가 있어야
      // orderByAppliedAtDesc 경로가 INTERNAL 로 죽지 않는다.
      expect(
        flat.contains('"fieldPath": "businessId", "order": "ASCENDING" }, '
            '{ "fieldPath": "appliedAt", "order": "DESCENDING"'),
        isTrue,
        reason: '이 인덱스가 없으면 사업장 전체 조회가 항상 실패한다',
      );
    });
  });
}
