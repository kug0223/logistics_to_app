// [AUD-10 M2·M3 · impl_70] 기기에 남는 민감 사본 정리 — 동작 시험 + 소스 계약.
//
//   SC-1x  공유 사본 폴더(cache/share_plus · cache/share)만 지우고 다른 cache 는 건드리지 않는다
//   SC-2x  이미지 캐시(메모리·디스크) 정리 · 실패해도 던지지 않는다
//   SC-3x  소스 계약: 사업자등록증 뷰어는 디스크 캐시 0 · signOut 두 갈래 · 앱 시작 1곳
import 'dart:io';

import 'package:ALfit/utils/sensitive_cache_cleanup.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

String _src(String p) => File(p).readAsStringSync();

String _slice(String raw, String from, String to) {
  final a = raw.indexOf(from);
  if (a < 0) throw StateError('$from 를 찾지 못함');
  final b = raw.indexOf(to, a + from.length);
  if (b < 0) throw StateError('$to 를 찾지 못함');
  return raw.substring(a, b);
}

/// 소스 계약 판정식 — 되돌림 확인(records 의 impl_70 revert 시험)도 같은 식을 쓴다.
bool licenseViewerNoDiskCache(String allBusinessesSrc) {
  final v = _slice(allBusinessesSrc, 'void _showLicenseImage(String url) {', 'Positioned(');
  return !v.contains('CachedNetworkImage(') && v.contains('Image.network(');
}

int signOutCleanupCalls(String userProviderSrc) {
  final s = _slice(userProviderSrc, 'Future<void> signOut() async {', '// 에러 초기화');
  return 'SensitiveCacheCleanup.onSignOut();'.allMatches(s).length;
}

bool appStartCleanup(String mainSrc) => mainSrc.contains('SensitiveCacheCleanup.onAppStart();');

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('impl70_');
    SensitiveCacheCleanup.cacheRootOverride = () async => root;
  });

  tearDown(() {
    SensitiveCacheCleanup.cacheRootOverride = null;
    SensitiveCacheCleanup.emptyDiskImageCacheOverride = null;
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  File mk(String rel, [String body = 'x']) {
    final f = File('${root.path}${Platform.pathSeparator}$rel');
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(body);
    return f;
  }

  group('SC-1x 공유 사본 폴더', () {
    test('SC-11 share_plus · share 만 지우고 다른 cache 는 남긴다', () async {
      final xlsx = mk('share_plus/이체_2026-11.xlsx', '계좌번호');
      final pdf = mk('share/근로계약서.pdf', 'pdf');
      final keep1 = mk('scaled_photo.jpg');
      final keep2 = mk('0f8fad5b-d9cb-469f-a165-70867728950e/orig.jpg');
      final keep3 = mk('libCachedImageData/a.jpg');
      final keep4 = mk('shared_other/x.txt'); // 이름이 비슷해도 대상 아님
      final n = await SensitiveCacheCleanup.clearShareFolders();
      expect(n, 2);
      expect(xlsx.existsSync(), isFalse);
      expect(pdf.existsSync(), isFalse);
      expect(Directory('${root.path}/share_plus').existsSync(), isFalse);
      expect(Directory('${root.path}/share').existsSync(), isFalse);
      for (final k in [keep1, keep2, keep3, keep4]) {
        expect(k.existsSync(), isTrue, reason: '${k.path} 는 지우면 안 된다');
      }
    });

    test('SC-12 없으면 0 · 두 번째 호출도 안전', () async {
      expect(await SensitiveCacheCleanup.clearShareFolders(), 0);
      mk('share/a.pdf');
      expect(await SensitiveCacheCleanup.clearShareFolders(), 1);
      expect(await SensitiveCacheCleanup.clearShareFolders(), 0);
    });

    test('SC-13 cache 루트를 못 얻어도 던지지 않는다', () async {
      SensitiveCacheCleanup.cacheRootOverride = () async => throw const FileSystemException('no cache');
      expect(await SensitiveCacheCleanup.clearShareFolders(), 0);
    });

    test('SC-14 같은 이름의 파일(폴더 아님)은 지우지 않는다', () async {
      final f = mk('share'); // 파일
      expect(await SensitiveCacheCleanup.clearShareFolders(), 0);
      expect(f.existsSync(), isTrue);
    });
  });

  group('SC-2x 이미지 캐시', () {
    test('SC-21 디스크 캐시 비움 호출 · 실패는 false', () async {
      var called = 0;
      SensitiveCacheCleanup.emptyDiskImageCacheOverride = () async => called++;
      expect(await SensitiveCacheCleanup.clearDiskImageCache(), isTrue);
      expect(called, 1);
      SensitiveCacheCleanup.emptyDiskImageCacheOverride = () async => throw StateError('io');
      expect(await SensitiveCacheCleanup.clearDiskImageCache(), isFalse);
    });

    testWidgets('SC-22 메모리 이미지 캐시를 비운다', (tester) async {
      final img = await tester.runAsync(() => createTestImage(width: 1, height: 1));
      final cache = PaintingBinding.instance.imageCache;
      const key = 'impl70-sensitive-key';
      cache.putIfAbsent(key, () => OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: img!))));
      expect(cache.containsKey(key), isTrue, reason: '전제: 캐시에 들어 있다');
      SensitiveCacheCleanup.clearMemoryImageCache();
      expect(cache.containsKey(key), isFalse);
      expect(cache.currentSize, 0);
      expect(cache.liveImageCount, 0);
    });

    test('SC-24 실제 캐시 관리자가 저장소를 못 열어도(플러그인 없음) 새는 오류 없이 false', () async {
      // 캐시 관리자 생성자가 기다리지 않고 시작하는 디렉터리 생성 실패가 zone 으로 새지 않아야 한다
      //   (예전 구현에서 AB-1·LI-6 시험이 그 미처리 오류로 깨졌다).
      expect(await SensitiveCacheCleanup.clearDiskImageCache(), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    test('SC-23 onSignOut 이 디스크·공유 정리를 모두 출발시킨다', () async {
      var disk = 0;
      SensitiveCacheCleanup.emptyDiskImageCacheOverride = () async => disk++;
      mk('share_plus/a.xlsx');
      SensitiveCacheCleanup.onSignOut();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(disk, 1);
      expect(Directory('${root.path}/share_plus').existsSync(), isFalse);
    });
  });

  group('SC-3x 소스 계약', () {
    test('SC-31 사업자등록증 뷰어는 디스크 캐시를 쓰지 않는다', () {
      expect(licenseViewerNoDiskCache(_src('lib/screens/super_admin/all_businesses_screen.dart')), isTrue);
    });
    test('SC-32 signOut 성공·실패 두 갈래 모두 정리를 부른다', () {
      expect(signOutCleanupCalls(_src('lib/providers/user_provider.dart')), 2);
    });
    test('SC-33 앱 시작에서 공유 사본 정리를 한 번 부른다', () {
      final m = _src('lib/main.dart');
      expect(appStartCleanup(m), isTrue);
      expect('SensitiveCacheCleanup.onAppStart();'.allMatches(m).length, 1);
    });
  });
}
