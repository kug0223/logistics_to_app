// [CUTOVER-SA-LOGIN] 디버그 전용 진입점 — 기본 앱(main.dart)을 그대로 띄우고, 운영자가 넣어 둔
// 일회용 커스텀 토큰 파일이 있으면 한 번 소비해 시험 SUPER_ADMIN 으로 로그인한다.
//
//   빌드: flutter build apk --debug -t lib/main_cutover_debug.dart --dart-define-from-file=config/dev/dart_defines.json
//   배포용 빌드는 기본 진입점(lib/main.dart)을 쓰므로 이 파일과 lib/debug/ 는 포함되지 않는다.
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'debug/cutover_sa_login.dart';
import 'main.dart' as app;

void main() {
  CutoverSaLogin.assertDebugOnly();
  app.main();
  // app.main 이 Firebase 를 초기화한 뒤에만 시도한다(최대 60초 대기). 그 뒤에도 5초마다 파일을 한 번씩 본다 —
  // 운영자가 앱 실행 후 토큰을 넣는 순서를 허용한다. 소비는 파일 단위 1회.
  var waited = 0;
  Timer.periodic(const Duration(seconds: 5), (t) async {
    waited += 5;
    if (Firebase.apps.isEmpty) {
      if (waited > 60) t.cancel();
      return;
    }
    final dir = await getApplicationSupportDirectory(); // Android: 앱 내부 files 폴더(run-as 로만 접근)
    final r = await CutoverSaLogin.consume(
      dir: dir,
      // 미리 signOut 하지 않는다 — 성공하면 SDK 가 현재 사용자를 바꾸고, 실패하면 기존 세션이
      //   그대로 남는다(10-23 Pixel 5: 미리 signOut 해서 잘못된 토큰에도 admin01 세션이 끊겼다).
      signIn: (token) => FirebaseAuth.instance.signInWithCustomToken(token),
      log: debugPrint,
    );
    if (r == CutoverSaLoginResult.signedIn) t.cancel();
  });
}
