// [CUTOVER-SA-LOGIN] 토큰 파일 소비 규칙 — 로컬 단위 시험(기기 검증 아님).
import 'dart:io';

import 'package:ALfit/debug/cutover_sa_login.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('cutover_sa_'));
  tearDown(() => dir.deleteSync(recursive: true));
  File tokenFile() => File('${dir.path}${Platform.pathSeparator}${CutoverSaLogin.fileName}');
  const secret = 'eyJ.secret-token-value.sig';

  test('CSL-1 파일 없음 → 로그인 시도 없음', () async {
    var calls = 0;
    final r = await CutoverSaLogin.consume(dir: dir, signIn: (_) async => calls++);
    expect(r, CutoverSaLoginResult.noFile);
    expect(calls, 0);
  });

  test('CSL-2 파일 있음 → 로그인 전에 파일 삭제 · 토큰은 한 번만 전달 · 로그에 토큰 없음', () async {
    tokenFile().writeAsStringSync('$secret\n');
    final logs = <String>[];
    bool? existedDuringSignIn;
    String? got;
    final r = await CutoverSaLogin.consume(
      dir: dir,
      signIn: (t) async {
        existedDuringSignIn = tokenFile().existsSync();
        got = t;
      },
      log: logs.add,
    );
    expect(r, CutoverSaLoginResult.signedIn);
    expect(got, secret);
    expect(existedDuringSignIn, isFalse, reason: '로그인 시도 전에 지운다');
    expect(tokenFile().existsSync(), isFalse);
    expect(logs.any((l) => l.contains('secret') || l.contains('eyJ')), isFalse);
  });

  test('CSL-3 로그인 실패 → 파일은 이미 없음 · 예외 메시지(토큰 포함 가능)를 로그에 남기지 않음', () async {
    tokenFile().writeAsStringSync(secret);
    final logs = <String>[];
    final r = await CutoverSaLogin.consume(
      dir: dir,
      signIn: (t) async => throw Exception('invalid token $t'),
      log: logs.add,
    );
    expect(r, CutoverSaLoginResult.signInFailed);
    expect(tokenFile().existsSync(), isFalse);
    expect(logs.join(' ').contains(secret), isFalse);
  });

  test('CSL-4 빈 파일 → 무시하고 삭제', () async {
    tokenFile().writeAsStringSync('  \n');
    var calls = 0;
    final r = await CutoverSaLogin.consume(dir: dir, signIn: (_) async => calls++);
    expect(r, CutoverSaLoginResult.emptyFile);
    expect(calls, 0);
    expect(tokenFile().existsSync(), isFalse);
  });
}
