// [DOC-LATE-DELETE.7 · D] LOCAL 기기 검증용 디버그 진입점이 릴리스에 섞이지 않는다.
//
//   릴리스 빌드는 lib/main.dart 만 컴파일한다. 진입점(integration_test/e6_local_main.dart)은
//   `-t` 로 지정할 때만 들어가므로, lib/ 의 어떤 코드도 그것을 참조하지 않아야 한다.
//   진입점이 하는 일(에뮬레이터 연결 · Functions 전송 교체 · 10.0.2.2)이 lib/ 로 새면
//   운영 앱이 LOCAL 주소를 부르게 된다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('E7-1 lib/ 는 디버그 진입점·integration_test 를 참조하지 않는다', () {
    for (final f in libFiles) {
      final s = f.readAsStringSync();
      expect(s.contains('e6_local_main'), isFalse, reason: f.path);
      expect(s.contains("import 'package:integration_test"), isFalse, reason: f.path);
    }
  });

  test('E7-2 LOCAL 연결 코드는 lib/ 에 없다(에뮬레이터 주소 · Functions 전송 교체)', () {
    for (final f in libFiles) {
      final s = f.readAsStringSync();
      expect(s.contains('10.0.2.2'), isFalse, reason: f.path);
      expect(s.contains('useFunctionsEmulator('), isFalse, reason: f.path);
      expect(s.contains('useFirestoreEmulator('), isFalse, reason: f.path);
      expect(s.contains('useAuthEmulator('), isFalse, reason: f.path);
      expect(s.contains('FirebaseFunctionsPlatform.instance ='), isFalse, reason: f.path);
    }
  });

  test('E7-3 진입점은 릴리스 모드에서 바로 멈춘다', () {
    final entry = File('integration_test/e6_local_main.dart').readAsStringSync();
    expect(entry, contains("if (kReleaseMode) throw StateError('E6 LOCAL 진입점은 디버그 전용이다');"));
  });

  test('E7-4 기기 실행용 임시 평문 허용 설정이 남아 있지 않다', () {
    expect(File('android/app/src/debug/res/xml/e7_local_cleartext.xml').existsSync(), isFalse);
    expect(File('android/app/src/debug/AndroidManifest.xml').readAsStringSync().contains('networkSecurityConfig'), isFalse);
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync().contains('usesCleartextTraffic="true"'), isFalse);
  });
}
