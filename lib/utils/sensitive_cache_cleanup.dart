// lib/utils/sensitive_cache_cleanup.dart
//
// [AUD-10 M2·M3 · impl_70] 기기에 남는 민감 사본 정리 — 로그아웃·앱 시작 두 지점에서만 부른다.
//
//   M2 공유 사본: 앱이 만든 임시 원본은 각 화면이 finally 로 지우지만, 플러그인이 **따로**
//     만든 사본이 남는다.
//       · share_plus(Android): 공유 파일을 `cache/share_plus/` 로 복사하고 **다음 공유 때**에만 비운다
//         → 이체 XLSX(이름·은행·계좌번호)가 다음 공유까지 남는다.
//       · printing.sharePdf(Android): `cache/share/<파일명>` 에 쓰고 `deleteOnExit()` 만 건다
//         (Android 에서는 돌지 않는다) → 근로계약서·급여명세 PDF 가 남는다.
//     두 폴더는 그 플러그인 전용 이름이라 소유가 확정된다. cache 루트의 다른 것은 건드리지 않는다.
//     공유 시트가 파일을 읽는 동안 지우지 않도록 공유 직후가 아니라 **로그아웃·다음 앱 시작**에 지운다.
//
//   M3 이미지 캐시: `CachedNetworkImage` 기본 디스크 캐시(계약 서명 이미지 · 예전에 캐시된 사업자등록증 등)와
//     메모리 이미지 캐시를 로그아웃 때 비운다 — 다음 계정이 같은 기기를 쓸 때 앞 계정 이미지 파일이 남지 않게.
//     기본 캐시 관리자는 `CachedNetworkImageProvider.defaultCacheManager`(DefaultCacheManager 단일 인스턴스)다.
//
//   모두 best-effort — 실패해도 로그아웃·시작을 막지 않는다. 결과만 돌려준다(시험용).
import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

class SensitiveCacheCleanup {
  SensitiveCacheCleanup._();

  /// 플러그인 공유 사본 폴더(cache 루트 바로 아래 · 이름 고정).
  static const List<String> shareFolders = ['share_plus', 'share'];

  /// 시험 주입점 — null 이면 실제 경로·캐시를 쓴다.
  @visibleForTesting
  static Future<Directory> Function()? cacheRootOverride;
  @visibleForTesting
  static Future<void> Function()? emptyDiskImageCacheOverride;

  /// 공유 사본 폴더 두 개를 지운다. 지운 폴더 수를 돌려준다.
  static Future<int> clearShareFolders() async {
    if (kIsWeb) return 0;
    var n = 0;
    try {
      final root = await (cacheRootOverride ?? getTemporaryDirectory)();
      for (final name in shareFolders) {
        final dir = Directory('${root.path}${Platform.pathSeparator}$name');
        try {
          if (await dir.exists()) {
            await dir.delete(recursive: true);
            n++;
          }
        } catch (e) {
          debugPrint('⚠️ 공유 사본 정리 실패(무시): $name — $e');
        }
      }
    } catch (e) {
      debugPrint('⚠️ 공유 사본 정리 실패(무시): $e');
    }
    return n;
  }

  /// 메모리 이미지 캐시를 비운다(동기).
  static void clearMemoryImageCache() {
    try {
      final cache = PaintingBinding.instance.imageCache;
      cache.clear();
      cache.clearLiveImages();
    } catch (e) {
      debugPrint('⚠️ 메모리 이미지 캐시 정리 실패(무시): $e');
    }
  }

  /// `CachedNetworkImage` 기본 디스크 캐시를 비운다.
  ///   캐시 관리자는 처음 만들어질 때 디렉터리 생성을 **기다리지 않는 future** 로 시작한다 — 그 실패
  ///   (예: path_provider 가 없는 환경)는 try/catch 로 잡히지 않고 zone 으로 샌다. 그래서 전용 zone 에서
  ///   실행하고, 어떤 실패든 false 로 끝낸다(로그아웃을 깨뜨리지 않는다).
  static Future<bool> clearDiskImageCache() {
    if (kIsWeb) return Future<bool>.value(false);
    final done = Completer<bool>();
    void fail(Object e) {
      debugPrint('⚠️ 디스크 이미지 캐시 정리 실패(무시): $e');
      if (!done.isCompleted) done.complete(false);
    }
    runZonedGuarded(() async {
      try {
        final f = emptyDiskImageCacheOverride ??
            () => CachedNetworkImageProvider.defaultCacheManager.emptyCache();
        await f();
        if (!done.isCompleted) done.complete(true);
      } catch (e) {
        fail(e);
      }
    }, (e, _) => fail(e));
    return done.future;
  }

  /// 로그아웃 — 메모리 캐시는 바로, 디스크 정리는 기다리지 않는다(로그아웃을 늦추지 않는다).
  static void onSignOut() {
    clearMemoryImageCache();
    unawaited(clearDiskImageCache());
    unawaited(clearShareFolders());
  }

  /// 앱 시작 — 첫 화면과 겹치지 않게 늦게 한 번(이전 실행이 남긴 공유 사본).
  static void onAppStart({Duration delay = const Duration(seconds: 5)}) {
    if (kIsWeb) return;
    unawaited(Future<void>.delayed(delay, clearShareFolders));
  }
}
