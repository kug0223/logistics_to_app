import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// [PERF-P3] SharedPreferences 를 앱 시작 때 **미리 열어** 두는 자리.
///
///   AuthWrapper 는 로그인 사용자가 정해진 뒤 온보딩 완료 여부(`onboarding_completed_<uid>`)를
///   읽는다. 예전에는 그 자리에서 `SharedPreferences.getInstance()` 를 postFrame 으로 기다렸고,
///   그동안 **흰 화면 가운데 스피너**가 한 프레임 이상 그려졌다(스플래시 → 흰 화면 → 홈 뼈대).
///
///   main() 이 Firebase 초기화와 **겹쳐서** 저장소를 연다(기다리지 않는다). 열린 뒤에는
///   [instanceOrNull] 로 같은 프레임에 동기 판정할 수 있다. 판정 자체(어느 uid 의 키를 읽는가)는
///   여전히 AuthWrapper 가 uid 확정 뒤에 한다 — 여기서는 키를 읽지 않는다.
///
///   SharedPreferences 는 프로세스 단일 인스턴스다. 다른 화면이 `getInstance()` 로 쓴 값도
///   같은 인스턴스의 메모리 캐시에 들어오므로 여기서 잡아 둔 인스턴스가 낡지 않는다.
///   열기 실패는 삼킨다 — AuthWrapper 가 기존 비동기 경로로 돌아간다.
class PrefsPreload {
  PrefsPreload._();

  static SharedPreferences? _instance;
  static Future<SharedPreferences?>? _future;

  /// 저장소 열기를 시작한다(여러 번 불러도 한 번만 연다). 결과를 기다릴 필요는 없다.
  static Future<SharedPreferences?> start() {
    return _future ??= SharedPreferences.getInstance().then<SharedPreferences?>(
      (p) => _instance = p,
      onError: (Object e) {
        debugPrint('⚠️ [PrefsPreload] 저장소 미리 열기 실패(기존 경로 사용): $e');
        return null;
      },
    );
  }

  /// 이미 열린 인스턴스. 아직이거나 실패했으면 null.
  static SharedPreferences? get instanceOrNull => _instance;

  /// 시험 전용 — `SharedPreferences.setMockInitialValues` 뒤 이전 인스턴스를 버린다.
  @visibleForTesting
  static void debugReset() {
    _instance = null;
    _future = null;
  }
}
