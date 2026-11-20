import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:flutter/foundation.dart';
// resume 재확인은 lifecycle 신호 하나에만 붙는다 — 새 polling 을 만들지 않는다.
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// 앱 최소 버전 게이트.
///
/// Firebase Remote Config 키:
///   `min_version`        — 이 버전 **미만**은 차단
///   `latest_version`     — 이 버전 미만은 권장(차단 아님)
///   `update_url_android` / `update_url_ios` — 업데이트 목적지
///
/// [VERSION-GATE] 예전에는 확인 결과가 `upToDate / recommendUpdate / forceUpdate`
///   세 값이었고, **확인하지 못한 경우가 `upToDate` 와 같은 값**이었다. 그래서
///   네트워크 실패·타임아웃이 "최신"으로 둔갑했다. 모르는 것을 안다고 말하면
///   최소 버전 정책은 강제되지 않는다.
///
///   이제 세 **상태**를 구분한다 — [VersionGateStatus].
enum VersionGateStatus {
  /// 신뢰할 수 있는 정책을 확인했고 기준 이상이다.
  supported,

  /// 신뢰할 수 있는 정책을 확인했고 기준 미만이다.
  updateRequired,

  /// **정책을 확인하지 못했다.** 최신도 구버전도 아니다.
  unknown,
}

/// 정책 값이 어디서 왔는가 — "받은 정책"과 "앱에 박힌 기본값"은 다르다.
enum VersionPolicySource {
  /// Remote Config 서버에서 받아 활성화된 값(이번 fetch 또는 이전 활성 캐시).
  remote,

  /// `setDefaults` 의 로컬 기본값 — 정책을 **한 번도 받은 적이 없다**.
  localDefault,
}

@immutable
class VersionGateResult {
  final VersionGateStatus status;

  /// 차단은 아니지만 권장 업데이트 대상인가. `supported` 일 때만 의미가 있다.
  final bool recommendUpdate;

  final VersionPolicySource source;

  /// 이번 실행에서 새로 받지 못하고 **이전 활성값**으로 판정했는가.
  final bool fromCache;

  /// 업데이트 목적지. 없으면 null — 버튼을 비활성으로 두지 말고 다른 행동을 준다.
  final String? updateUrl;

  final String currentVersion;
  final String minVersion;

  const VersionGateResult({
    required this.status,
    required this.source,
    required this.fromCache,
    required this.currentVersion,
    required this.minVersion,
    this.recommendUpdate = false,
    this.updateUrl,
  });

  bool get blocksEntry => status != VersionGateStatus.supported;
}

class AppVersionService {
  static FirebaseRemoteConfig get _rc => FirebaseRemoteConfig.instance;

  /// 마지막 판정 — resume 재확인과 민감 기능 제한이 참조한다.
  static VersionGateResult? lastResult;

  /// 마지막으로 **정책을 실제로 받은** 시각. resume 재확인 주기의 기준이다.
  static DateTime? lastFetchAt;

  /// [VERSION-GATE] 릴리스에서 1시간. 0 으로 바꾸지 않는다 —
  ///   매 실행마다 서버 요청이 늘고 시작이 느려진다. 최소 버전 상향이
  ///   **즉시** 듣지 않는 구간이 생기는 것은 이 주기의 대가다(보고서에 명시).
  static const Duration releaseFetchInterval = Duration(hours: 1);

  /// resume 에서 이 시간이 지났을 때만 다시 받는다 — lifecycle 마다 fetch 하지 않는다.
  static const Duration resumeRecheckAfter = Duration(minutes: 30);

  static Future<void> init() async {
    try {
      await _rc.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(seconds: 10),
        minimumFetchInterval:
            kDebugMode ? Duration.zero : releaseFetchInterval,
      ));
      await _rc.setDefaults({
        'min_version': '1.0.0',
        'latest_version': '1.0.0',
        'update_url_android': '',
        'update_url_ios': '',
      });
    } catch (e) {
      debugPrint('⚠️ Remote Config 초기화 실패: $e');
    }
  }

  /// 지금의 버전 정책을 판정한다. **예외를 삼켜 `supported` 로 만들지 않는다.**
  static Future<VersionGateResult> evaluate({bool forceFetch = false}) async {
    String current = '';
    String? packageName;
    try {
      final info = await PackageInfo.fromPlatform();
      current = info.version;
      packageName = info.packageName;
    } catch (e) {
      debugPrint('⚠️ 앱 버전 조회 실패: $e');
    }

    var fetchedNow = false;
    try {
      if (forceFetch) await _rc.fetch();
      fetchedNow = await _rc.fetchAndActivate();
      lastFetchAt = DateTime.now();
    } catch (e) {
      // 네트워크 실패 — 이전에 활성화된 정책이 있으면 그것으로 판정한다.
      debugPrint('⚠️ Remote Config 조회 실패: $e');
    }

    // [VERSION-GATE] **활성값의 출처**가 판정의 핵심이다.
    //   `setDefaults` 로 박아 둔 `1.0.0` 은 정책이 아니다 — 그것으로 통과시키면
    //   정책을 한 번도 받지 못한 앱이 늘 통과한다.
    final minValue = _rc.getValue('min_version');
    final source = minValue.source == ValueSource.valueRemote
        ? VersionPolicySource.remote
        : VersionPolicySource.localDefault;

    final result = decide(
      currentVersion: current,
      minVersion: minValue.asString(),
      latestVersion: _rc.getString('latest_version'),
      source: source,
      fetchedNow: fetchedNow,
      configuredUpdateUrl: _platformUpdateUrl(),
      packageName: packageName,
    );
    lastResult = result;
    return result;
  }

  static String _platformUpdateUrl() {
    try {
      return defaultTargetPlatform == TargetPlatform.iOS
          ? _rc.getString('update_url_ios')
          : _rc.getString('update_url_android');
    } catch (_) {
      return '';
    }
  }

  /// 판정 **그 자체**. I/O 가 없어 테스트가 이 함수를 그대로 부른다.
  ///
  ///   비교는 `major.minor.patch` 세 자리로 한다. `PackageInfo.version` 은
  ///   빌드 번호를 포함하지 않으므로(`1.4.0+10` → `1.4.0`) 정책도 **버전명
  ///   기준**이다. 기존 계약을 바꾸지 않는다 — 정책 값에 `+10` 이 붙어 있어도
  ///   앞부분만 본다.
  @visibleForTesting
  static VersionGateResult decide({
    required String currentVersion,
    required String minVersion,
    required String latestVersion,
    required VersionPolicySource source,
    required bool fetchedNow,
    required String configuredUpdateUrl,
    required String? packageName,
  }) {
    final url = resolveUpdateUrl(configuredUpdateUrl, packageName);
    VersionGateResult unknown() => VersionGateResult(
          status: VersionGateStatus.unknown,
          source: source,
          fromCache: !fetchedNow,
          currentVersion: currentVersion,
          minVersion: minVersion,
          updateUrl: url,
        );

    // 정책을 한 번도 받지 못했다 — 통과도 차단도 아니다.
    if (source != VersionPolicySource.remote) return unknown();

    final cur = parseVersion(currentVersion);
    final min = parseVersion(minVersion);
    // 어느 한쪽이라도 읽을 수 없으면 비교가 성립하지 않는다.
    if (cur == null || min == null) return unknown();

    if (_isLess(cur, min)) {
      return VersionGateResult(
        status: VersionGateStatus.updateRequired,
        source: source,
        fromCache: !fetchedNow,
        currentVersion: currentVersion,
        minVersion: minVersion,
        updateUrl: url,
      );
    }

    final latest = parseVersion(latestVersion);
    return VersionGateResult(
      status: VersionGateStatus.supported,
      source: source,
      fromCache: !fetchedNow,
      currentVersion: currentVersion,
      minVersion: minVersion,
      recommendUpdate: latest != null && _isLess(cur, latest),
      updateUrl: url,
    );
  }

  /// 업데이트 목적지. 설정값이 비면 **이 앱 자신의 패키지명**으로 스토어를 연다.
  ///
  ///   패키지명을 지어내지 않는다 — 실행 중인 앱의 `PackageInfo.packageName`
  ///   이다. 그것도 없으면 null 이고, 그때 화면은 버튼을 비활성으로 두지 않고
  ///   다른 행동(다시 확인)을 준다.
  @visibleForTesting
  static String? resolveUpdateUrl(String configured, String? packageName) {
    final c = configured.trim();
    if (c.isNotEmpty) return c;
    if (defaultTargetPlatform == TargetPlatform.iOS) return null;
    if (packageName == null || packageName.trim().isEmpty) return null;
    return 'https://play.google.com/store/apps/details?id=${packageName.trim()}';
  }

  /// `1.4.0` · `1.4.0+10` → `[1,4,0]`. 그 밖은 null(= 판정 불가).
  @visibleForTesting
  static List<int>? parseVersion(String raw) {
    final v = raw.trim().split('+').first.trim();
    if (v.isEmpty) return null;
    final parts = v.split('.');
    if (parts.isEmpty || parts.length > 3) return null;
    final out = <int>[];
    for (final p in parts) {
      if (p.isEmpty || !RegExp(r'^\d+$').hasMatch(p)) return null;
      out.add(int.parse(p));
    }
    while (out.length < 3) {
      out.add(0);
    }
    return out;
  }

  static bool _isLess(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] < b[i]) return true;
      if (a[i] > b[i]) return false;
    }
    return false;
  }

  /// [VERSION-GATE] **지금 앱 진입이 막혀 있는가.**
  ///
  ///   게이트는 라우트를 대체해 막는다. 그런데 알림 딥링크는 root navigator 에
  ///   **직접 push** 하므로 그 차단 화면 **위로** 올라올 수 있다 — 막아 둔 앱을
  ///   알림 한 번으로 열게 된다. 그래서 push 하는 쪽이 이 값을 물어본다.
  ///
  ///   `unknown` 은 막지 않는다. 그건 최초 진입에서 다루고, 이미 들어와 쓰던
  ///   사용자의 알림까지 끊을 이유가 없다.
  static bool get entryBlocked =>
      lastResult?.status == VersionGateStatus.updateRequired;

  /// resume 재확인이 필요한가 — lifecycle 마다 네트워크를 두드리지 않는다.
  @visibleForTesting
  static bool shouldRecheckOnResume(DateTime now) {
    // 이미 차단 상태면 다시 확인할 이유가 없다(정상 화면으로 돌아갈 수 없다).
    if (lastResult?.status == VersionGateStatus.updateRequired) return false;
    final at = lastFetchAt;
    if (at == null) return true;
    return now.difference(at) >= resumeRecheckAfter;
  }

  /// [VERSION-GATE §6] 백그라운드에서 돌아올 때 정책이 바뀌었을 수 있다.
  ///
  ///   새 polling 을 만들지 않는다 — lifecycle 신호 하나에만 붙고,
  ///   [resumeRecheckAfter] 가 지나야 실제로 다시 받는다.
  ///   **차단은 `updateRequired` 일 때만** 한다. resume 중 네트워크가 잠깐
  ///   끊겼다고(UNKNOWN) 쓰던 화면을 뺏지 않는다 — 그건 최초 진입의 몫이다.
  static void startResumeWatch(void Function(VersionGateResult) onBlocked) {
    _resumeWatcher ??= _VersionResumeWatcher(onBlocked);
  }

  static _VersionResumeWatcher? _resumeWatcher;

  @visibleForTesting
  static void debugResetResumeWatch() {
    _resumeWatcher?.dispose();
    _resumeWatcher = null;
  }
}

class _VersionResumeWatcher with WidgetsBindingObserver {
  final void Function(VersionGateResult) onBlocked;
  bool _running = false;

  _VersionResumeWatcher(this.onBlocked) {
    WidgetsBinding.instance.addObserver(this);
  }

  void dispose() => WidgetsBinding.instance.removeObserver(this);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // 재확인이 돌고 있는 동안 또 들어와도 두 번 돌지 않는다(중복 Dialog 방지).
    if (_running) return;
    if (!AppVersionService.shouldRecheckOnResume(DateTime.now())) return;
    _running = true;
    AppVersionService.evaluate().then((r) {
      if (r.status == VersionGateStatus.updateRequired) onBlocked(r);
    }).catchError((Object e) {
      debugPrint('⚠️ resume 버전 재확인 실패: $e');
    }).whenComplete(() => _running = false);
  }
}
