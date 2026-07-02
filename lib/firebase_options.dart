// ENV 라우터: --dart-define=IS_PROD=true 이면 prod Firebase 사용
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'firebase_options_dev.dart' as dev;
// prod 설정 파일은 아래 절차로 생성 후 주석 해제:
//   flutterfire configure --project=alfit-prod --out=lib/firebase_options_prod.dart
// import 'firebase_options_prod.dart' as prod;

const bool _isProd = bool.fromEnvironment('IS_PROD', defaultValue: false);

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (_isProd) {
      // [TODO-PROD] firebase_options_prod.dart 생성 후 위 import + 아래 반환문 활성화
      throw UnimplementedError(
        'Prod Firebase 미설정.\n'
        '  1. Firebase 콘솔에서 alfit-prod 프로젝트 생성\n'
        '  2. flutterfire configure --project=alfit-prod --out=lib/firebase_options_prod.dart\n'
        '  3. firebase_options.dart에서 prod import 주석 해제',
      );
      // return prod.DefaultFirebaseOptions.currentPlatform;
    }
    return dev.DefaultFirebaseOptions.currentPlatform;
  }
}
