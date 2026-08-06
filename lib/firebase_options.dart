// ENV 라우터: --dart-define=IS_PROD=true 이면 prod Firebase 사용
// ignore_for_file: type=lint
import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'firebase_options_dev.dart' as dev;
import 'firebase_options_prod.dart' as prod;

const bool _isProd = bool.fromEnvironment('IS_PROD', defaultValue: false);

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (_isProd) return prod.DefaultFirebaseOptions.currentPlatform;
    return dev.DefaultFirebaseOptions.currentPlatform;
  }
}
