// [R8-P3B.3B] 한국식 이름이 한 번도 저장된 적이 없었다.
//
//   외국인 가입 화면 두 곳이 users/{uid} 에 koreanName 을 직접 update 했다.
//   그런데 그 필드는 [PII-B4-R1.4.3] denylist('name','legalName','koreanName')에
//   들어 있다 — 정당한 writer 는 전부 CF 다. 그래서 그 write 는 **항상**
//   PERMISSION_DENIED 였고, try/catch 가 "치명적 아님"으로 삼켰다.
//
//   고치려던 버그(재개 가입에서 displayName 이 한국식 이름을 못 씀)는 그대로
//   남았고, 매번 실패하는 왕복만 한 번 더 붙었다.
//
//   이제 callableFinalizeForeignIdentity 가 저장한다. 그리고 그 CF 의
//   멱등(idempotent) 갈래 — 같은 uid 가 다시 부르는 재개 경로 — 에서도
//   프로필 필드는 반영한다. 예전에는 그 갈래가 아무것도 쓰지 않고 return 했다.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

/// 주석으로 시작하는 줄(`//`·`///`)을 지운다 — 표지는 코드에서만 찾는다.
String _codeOf(String raw) => raw
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _flat(String s) => s.replaceAll(RegExp(r'\s+'), ' ');

/// 그룹 수집 시점에도 불리므로 expect 대신 예외로 실패시킨다.
String _sliceOf(String raw, String from, String to) {
  final i = raw.indexOf(from);
  if (i < 0) throw StateError('시작 표지를 찾지 못함: $from');
  final j = raw.indexOf(to, i + from.length);
  if (j < 0) throw StateError('끝 표지를 찾지 못함: $to');
  return raw.substring(i, j);
}

String _cfBody(String fn, String name) {
  final i = fn.indexOf('export const $name =');
  if (i < 0) throw StateError('CF 를 찾지 못함: $name');
  final j = fn.indexOf('\nexport const ', i + 20);
  return fn.substring(i, j < 0 ? fn.length : j);
}

void main() {
  final fn = _read('functions/src/index.ts');
  final finalizeCf = _codeOf(_cfBody(fn, 'callableFinalizeForeignIdentity'));
  final screen = _read('lib/screens/auth/foreign_register_screen.dart');
  final screenCode = _codeOf(screen);
  final authService = _codeOf(_read('lib/services/auth_service.dart'));
  final rules = _read('firestore.rules');

  group('FKN-1 클라이언트 직접 write 가 사라졌다', () {
    test('FKN-10 foreign_register_screen 에 koreanName 직접 update 가 없다', () {
      expect(screenCode.contains("update({'koreanName'"), isFalse);
      expect(screenCode.contains('update({"koreanName"'), isFalse);
    });

    test('FKN-11 lib 전체에 koreanName 직접 write 가 없다', () {
      final hits = <String>[];
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final code = _codeOf(f.readAsStringSync());
        // users 컬렉션에 koreanName 을 담아 set/update 하는 형태만 본다.
        if (RegExp(r"(set|update)\(\s*\{[^}]*'koreanName'").hasMatch(code)) {
          hits.add(f.path);
        }
      }
      expect(hits, isEmpty, reason: '남은 직접 writer: $hits');
    });

    test('FKN-12 Rules denylist 에 koreanName 이 그대로 있다 (다시 열지 않았다)', () {
      // 이름 축 전체가 CF 전용이라는 사실을 고정한다.
      expect(rules.contains("'name', 'legalName', 'koreanName'"), isTrue);
    });
  });

  group('FKN-2 canonical writer 가 koreanName 을 받는다', () {
    test('FKN-20 CF 가 요청에서 koreanName 을 읽는다', () {
      expect(_flat(finalizeCf).contains('koreanName: koreanNameRaw'), isTrue);
    });

    test('FKN-21 기존 이름 검증 계약(trim + 100자)을 그대로 쓴다', () {
      final f = _flat(finalizeCf);
      expect(f.contains('const srvTrimmedName = (v: unknown): string | null =>'), isTrue);
      expect(f.contains('return t.length > 0 ? t.slice(0, 100) : null;'), isTrue);
      expect(f.contains('const koreanNameValue = srvTrimmedName(koreanNameRaw);'), isTrue);
    });

    test('FKN-22 legalName 과 koreanName 은 서로 덮어쓰지 않는다', () {
      final f = _flat(finalizeCf);
      // 각각 자기 값이 있을 때만 자기 키를 쓴다.
      expect(f.contains('...(legalNameValue ? {legalName: legalNameValue} : {})'), isTrue);
      expect(f.contains('...(koreanNameValue ? {koreanName: koreanNameValue} : {})'), isTrue);
    });

    test('FKN-23 자기 문서만 쓴다 — 클라이언트가 uid 를 넘길 수 없다', () {
      final f = _flat(finalizeCf);
      expect(f.contains('const uid = request.auth.uid;'), isTrue);
      expect(f.contains('const userRef = db.collection("users").doc(uid);'), isTrue);
      // 요청 파라미터 목록에 uid/userId 가 없다.
      final params = _flat(_sliceOf(finalizeCf, 'request.data as {', '};'));
      expect(params.contains('uid?'), isFalse);
      expect(params.contains('userId?'), isFalse);
    });
  });

  group('FKN-3 재개 경로 — 멱등 갈래도 프로필을 반영한다', () {
    test('FKN-30 멱등 갈래가 빈손으로 return 하지 않는다', () {
      final idem = _flat(_sliceOf(finalizeCf,
          'if (existingUid === uid) {', 'return;'));
      expect(idem.contains('tx.update(userRef, foreignProfilePatch)'), isTrue);
    });

    test('FKN-31 두 갈래가 같은 패치를 쓴다', () {
      final f = _flat(finalizeCf);
      // 패치는 트랜잭션 밖에서 한 번만 만들어진다.
      expect(f.contains('const foreignProfilePatch: Record<string, unknown> = {'), isTrue);
      // 신규 등록 갈래도 같은 변수를 편다.
      expect(f.contains('...foreignProfilePatch,'), isTrue);
    });

    test('FKN-32 멱등 갈래는 신원 파생 값을 다시 쓰지 않는다', () {
      final idem = _flat(_sliceOf(finalizeCf,
          'if (existingUid === uid) {', 'return;'));
      // fingerprint/birthDate/gender 는 이미 확정된 값이다 — 건드리지 않는다.
      expect(idem.contains('foreignIdentityFingerprint:'), isFalse);
      expect(idem.contains('birthDate:'), isFalse);
      expect(idem.contains('srvIdentityBasisPatch'), isFalse);
    });
  });

  group('FKN-4 클라이언트가 CF 로 koreanName 을 넘긴다', () {
    test('FKN-40 auth_service 가 koreanName 파라미터를 payload 에 싣는다', () {
      final f = _flat(authService);
      expect(f.contains('String? koreanName,'), isTrue);
      expect(
        f.contains("if (koreanName != null && koreanName.isNotEmpty) payload['koreanName'] = koreanName;"),
        isTrue,
      );
    });

    test('FKN-41 화면의 finalize 호출 3곳이 모두 koreanName 을 넘긴다', () {
      final calls = RegExp(r'finalizeForeignIdentity\(')
          .allMatches(screenCode)
          .length;
      expect(calls, 3, reason: '호출 지점 수가 바뀌면 이 테스트를 같이 갱신해야 한다');
      final withKorean = RegExp(r'koreanName: koreanName\.isNotEmpty \? koreanName : null,')
          .allMatches(screenCode)
          .length;
      expect(withKorean, 3);
    });

    test('FKN-42 재개 경로는 이름이 달라졌으면 finalize 를 건너뛰지 않는다', () {
      final f = _flat(screenCode);
      expect(f.contains('final koreanNameNeedsSave = koreanName.isNotEmpty && koreanName != storedKoreanName;'), isTrue);
      expect(f.contains('if (!hasFingerprint || koreanNameNeedsSave) {'), isTrue);
    });

    test('FKN-43 그 판단은 이미 하던 읽기에서 가져온다 — 왕복을 늘리지 않는다', () {
      final f = _flat(screenCode);
      // fingerprint 를 확인하던 바로 그 snapshot 에서 koreanName 도 읽는다.
      expect(
        f.contains("hasFingerprint = docSnap.data()?['foreignIdentityFingerprint'] != null; storedKoreanName = docSnap.data()?['koreanName'] as String?;"),
        isTrue,
      );
    });

    test('FKN-44 finalize 실패는 가입 실패로 처리된다 — 조용히 넘어가지 않는다', () {
      // 세 호출 모두 반환값을 보고 에러면 진행을 멈춘다.
      final stops = RegExp(r'if \(finalizeErr != null\) \{')
          .allMatches(screenCode)
          .length;
      expect(stops, 3);
    });
  });

  group('FKN-5 이름 축 semantics 가 유지된다', () {
    test('FKN-50 displayName 우선순위 (koreanName → legalName → name) 불변', () {
      final model = _codeOf(_read('lib/models/core/user_model.dart'));
      expect(
        _flat(model).contains('String get displayName => koreanName ?? legalName ?? name;'),
        isTrue,
      );
    });

    test('FKN-51 fresh 경로의 name 저장(effectiveName)은 그대로다', () {
      final f = _flat(screenCode);
      expect(f.contains('final effectiveName = koreanName.isNotEmpty ? koreanName : legalName;'), isTrue);
      expect(f.contains('name: effectiveName,'), isTrue);
    });
  });
}
