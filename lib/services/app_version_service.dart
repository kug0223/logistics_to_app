import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 앱 버전 관리 서비스
///
/// Firebase Remote Config 키:
///   min_version   — 이 버전 미만은 강제 업데이트
///   latest_version — 이 버전 미만은 권장 업데이트
///
/// Firebase 콘솔에서 설정:
///   Remote Config → 파라미터 추가 → min_version: "1.0.0", latest_version: "1.0.0"
class AppVersionService {
  static final _rc = FirebaseRemoteConfig.instance;

  static Future<void> init() async {
    try {
      await _rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval: kDebugMode
            ? Duration.zero
            : const Duration(hours: 1),
      ));
      await _rc.setDefaults({
        'min_version': '1.0.0',
        'latest_version': '1.0.0',
        'update_url_android': '',
        'update_url_ios': '',
      });
      // fetchAndActivate는 check()에서 호출하므로 여기서는 생략
      // → main()에서 await init()이 빠르게 완료되어 runApp() 진입 속도 개선
    } catch (e) {
      debugPrint('⚠️ Remote Config 초기화 실패: $e');
    }
  }

  /// 현재 앱 버전과 Remote Config 버전 비교 결과
  static Future<VersionCheckResult> check() async {
    try {
      await _rc.fetchAndActivate();
      final info = await PackageInfo.fromPlatform();
      final current = _parse(info.version);
      final minVer = _parse(_rc.getString('min_version'));
      final latestVer = _parse(_rc.getString('latest_version'));

      if (_isLess(current, minVer)) {
        return VersionCheckResult.forceUpdate;
      }
      if (_isLess(current, latestVer)) {
        return VersionCheckResult.recommendUpdate;
      }
      return VersionCheckResult.upToDate;
    } catch (e) {
      debugPrint('⚠️ 버전 체크 실패 (업데이트 생략): $e');
      return VersionCheckResult.upToDate;
    }
  }

  static List<int> _parse(String v) {
    final parts = v.split('.');
    return List.generate(3, (i) => i < parts.length ? int.tryParse(parts[i]) ?? 0 : 0);
  }

  static bool _isLess(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] < b[i]) return true;
      if (a[i] > b[i]) return false;
    }
    return false;
  }
}

enum VersionCheckResult { upToDate, recommendUpdate, forceUpdate }
