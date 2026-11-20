// [CUTOVER-SA-LOGIN] 디버그 전용 — 전환 운영용 시험 SUPER_ADMIN 의 에뮬레이터 로그인.
//
// 이 파일은 `lib/main_cutover_debug.dart`(별도 진입점)에서만 import 한다. 기본 진입점 `lib/main.dart`
// 의 import 그래프에 없으므로 배포용 빌드(`flutter build apk --release`, 기본 -t)에는 들어가지 않는다.
//
// 토큰 전달: 운영자 도구가 `adb shell run-as com.alfit.app` 으로 앱 내부 files 폴더에
// `cutover_sa_token.txt` 를 stdin 으로 쓴다(run-as 는 debuggable APK 에서만 된다).
// 앱은 파일을 **읽은 즉시 지우고** 그 토큰으로 한 번 로그인한다. 토큰 값은 어디에도 출력하지 않는다.
import 'dart:io';

import 'package:flutter/foundation.dart';

/// 소비 결과 — 로그에는 이 값만 남긴다(토큰 원문·길이·앞자리 없음).
enum CutoverSaLoginResult { noFile, emptyFile, signedIn, signInFailed }

class CutoverSaLogin {
  static const fileName = 'cutover_sa_token.txt';

  /// [dir] 의 토큰 파일을 한 번 소비한다. 파일은 로그인 시도 **전에** 지운다(실패해도 재사용 불가).
  static Future<CutoverSaLoginResult> consume({
    required Directory dir,
    required Future<void> Function(String token) signIn,
    void Function(String message)? log,
  }) async {
    final file = File('${dir.path}${Platform.pathSeparator}$fileName');
    if (!file.existsSync()) return CutoverSaLoginResult.noFile;
    String token;
    try {
      token = file.readAsStringSync().trim();
    } finally {
      try {
        file.deleteSync();
      } catch (_) {/* 이미 없음 */}
    }
    if (token.isEmpty) {
      log?.call('[CUTOVER-SA-LOGIN] 빈 파일 — 무시');
      return CutoverSaLoginResult.emptyFile;
    }
    try {
      await signIn(token);
      log?.call('[CUTOVER-SA-LOGIN] 로그인 성공');
      return CutoverSaLoginResult.signedIn;
    } catch (e) {
      // 예외 메시지에 토큰이 섞일 수 있어 유형만 남긴다.
      log?.call('[CUTOVER-SA-LOGIN] 로그인 실패 (${e.runtimeType})');
      return CutoverSaLoginResult.signInFailed;
    }
  }

  /// 배포 빌드에서 부르면 바로 멈춘다(이중 방어).
  static void assertDebugOnly() {
    if (!kDebugMode) {
      throw StateError('CutoverSaLogin 은 디버그 빌드 전용입니다.');
    }
  }
}
