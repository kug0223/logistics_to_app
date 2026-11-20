// [SIM-PICKER-CACHE] image_picker 산출물의 정리 책임 — 실제 `ImageHelper.pickAndCompressImage` 경로.
//
// 기기 READ(2026-10-18, 파일 미개봉): 통장사본·신분증·인감을 고를 때마다
//   image_picker 가 앱 cache 에 두 개를 남긴다 —
//     · `cache/<UUID>/<id>.jpg`  원본 사본 (FileUtils)
//     · `cache/scaled_<id>.jpg`  크기 조정본 (ImageResizer — maxWidth 를 주면 항상)
//   앱은 그중 무엇도 지우지 않았다. 앱이 지우는 것은 자기 staging 사본뿐이다.
//
// 이 하네스: image_picker·path_provider 플랫폼을 가짜로 바꿔 **실제 플러그인과 같은 배치**로
//   파일을 만든다. 모든 파일은 합성 바이트다(실제 서류 이미지 없음).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/utils/image_helper.dart';
import 'package:ALfit/utils/picker_cache_scope.dart';

class _FakePaths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _FakePaths(this.temp, this.support);
  final String temp;
  final String support;
  @override
  Future<String?> getTemporaryPath() async => temp;
  @override
  Future<String?> getApplicationSupportPath() async => support;
}

/// 실제 image_picker_android 와 같은 배치로 파일을 만든다.
class FakePicker extends ImagePickerPlatform with MockPlatformInterfaceMixin {
  FakePicker(this.cacheRoot);
  final String cacheRoot;
  bool cancel = false;
  int mediaId = 64;
  int _seq = 0;
  final created = <String>[];

  String _uuid() {
    _seq++;
    final h = _seq.toRadixString(16).padLeft(12, '0');
    return '0000${_seq.toString().padLeft(4, '0')}-0000-4000-8000-$h';
  }

  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    if (cancel) return null;
    final dir = Directory('$cacheRoot/${_uuid()}')..createSync();
    final orig = File('${dir.path}/$mediaId.jpg')
      ..writeAsBytesSync(List<int>.filled(4096, 7));
    created.add(dir.path);
    final scales = options.maxWidth != null ||
        options.maxHeight != null ||
        (options.imageQuality ?? 100) < 100;
    if (!scales) return XFile(orig.path);
    final scaled = File('$cacheRoot/scaled_$mediaId.jpg')
      ..writeAsBytesSync(List<int>.filled(2048, 7));
    created.add(scaled.path);
    return XFile(scaled.path);
  }

  /// 다중 선택 — 실제 플러그인처럼 사진마다 UUID 사본 + scaled_<id>.
  int multiCount = 3;
  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    if (cancel) return [];
    final out = <XFile>[];
    for (var i = 0; i < multiCount; i++) {
      final id = 200 + i;
      final dir = Directory('$cacheRoot/${_uuid()}')..createSync();
      File('${dir.path}/$id.jpg').writeAsBytesSync(List<int>.filled(4096, 7));
      created.add(dir.path);
      final scaled = File('$cacheRoot/scaled_$id.jpg')
        ..writeAsBytesSync(List<int>.filled(2048, 7));
      created.add(scaled.path);
      out.add(XFile(scaled.path));
    }
    return out;
  }
}

class Harness {
  late Directory root;
  late Directory cache;
  late Directory support;
  late FakePicker picker;

  Future<void> setUp() async {
    root = await Directory.systemTemp.createTemp('picker_cache_');
    cache = Directory('${root.path}/cache')..createSync();
    support = Directory('${root.path}/support')..createSync();
    PathProviderPlatform.instance = _FakePaths(cache.path, support.path);
    picker = FakePicker(cache.path);
    ImagePickerPlatform.instance = picker;
  }

  Future<void> tearDown() async {
    try {
      await root.delete(recursive: true);
    } catch (_) {}
  }

  /// cache 루트의 항목(파일명/폴더명) — 정렬.
  List<String> cacheEntries() => cache
      .listSync()
      .map((e) => e.path.substring(cache.path.length + 1))
      .toList()
    ..sort();
}

/// 실제 `pickAndCompressImage(context, type: document)` 를 소스 다이얼로그 탭까지 포함해 돌린다.
Future<File?> runPick(WidgetTester t) async {
  File? result;
  var done = false;
  await t.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: ElevatedButton(
            onPressed: () async {
              result = await ImageHelper.pickAndCompressImage(ctx,
                  type: ImageType.document);
              done = true;
            },
            child: const Text('pick'),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('pick'));
  // 선택 전 cache 스냅샷(실제 파일 IO)이 끝나야 소스 다이얼로그가 뜬다.
  for (var i = 0; i < 200 && find.text('갤러리에서 선택').evaluate().isEmpty; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await t.pump();
  }
  await t.pumpAndSettle();
  await t.tap(find.text('갤러리에서 선택'));
  for (var i = 0; i < 200 && !done; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
    await t.pump();
  }
  expect(done, isTrue, reason: 'pickAndCompressImage 가 끝나야 한다');
  await t.pumpAndSettle(); // 소스 다이얼로그 닫힘 애니메이션까지 — 다음 선택이 옛 창을 보지 않게
  return result;
}

void main() {
  final h = Harness();
  setUp(h.setUp);
  tearDown(h.tearDown);

  testWidgets('REPRO-1 통장·신분증 선택 후 picker 산출물(UUID 사본·scaled_)이 cache 에 남지 않는다',
      (t) async {
    final f = await runPick(t);
    expect(f, isNotNull);
    final exists = await t.runAsync(() => f!.exists());
    expect(exists, isTrue, reason: '호출자가 OCR·업로드에 쓸 앱 소유 사본은 살아 있어야 한다');
    expect(f!.path.startsWith(h.support.path), isTrue,
        reason: '반환 파일은 support/image_staging — picker cache 가 아니다');
    // ignore: avoid_print
    print('REPRO-1 cache 남은 항목: ${h.cacheEntries()}');
    expect(h.cacheEntries(), isEmpty, reason: 'picker 가 이 선택으로 만든 것은 정리돼야 한다');
  });

  group('PICK — 실제 pickAndCompressImage 경로', () {
    testWidgets('P-2 다른 선택·다른 흐름·사업장 staging 은 건드리지 않는다', (t) async {
      final other = Directory('${h.cache.path}/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee')..createSync();
      File('${other.path}/99.jpg').writeAsBytesSync([1]);
      File('${h.cache.path}/scaled_99.jpg').writeAsBytesSync([1]);
      Directory('${h.cache.path}/WebView').createSync();
      final staging = Directory('${h.support.path}/image_staging')..createSync(recursive: true);
      final bizStaged = File('${staging.path}/staged_123.jpg')..writeAsBytesSync([2]);

      final f = await runPick(t);
      expect(f, isNotNull);
      expect(h.cacheEntries(), [
        'WebView', 'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee', 'scaled_99.jpg',
      ]);
      expect(File('${other.path}/99.jpg').existsSync(), isTrue);
      expect(bizStaged.existsSync(), isTrue, reason: '사업장 등록 staging 은 대상이 아니다');
    });

    testWidgets('P-3 선택 창 취소 — 아무것도 만들지 않고 남은 것도 없다', (t) async {
      h.picker.cancel = true;
      final f = await runPick(t);
      expect(f, isNull);
      expect(h.cacheEntries(), isEmpty);
    });

    testWidgets('P-4 재선택 — 앞 선택의 반환 파일(호출자 소유)은 남고 cache 는 비어 있다', (t) async {
      final first = await runPick(t);
      h.picker.mediaId = 66;
      final second = await runPick(t);
      expect(await t.runAsync(() => first!.exists()), isTrue,
          reason: '첫 사본은 호출자가 업로드·삭제 책임을 가진다');
      expect(await t.runAsync(() => second!.exists()), isTrue);
      expect(first!.path, isNot(second!.path));
      expect(h.cacheEntries(), isEmpty);
    });

    testWidgets('P-5 반환 파일은 picker 산출물이 지워진 뒤에도 OCR·업로드에 쓸 수 있다', (t) async {
      final f = await runPick(t);
      final bytes = await t.runAsync(() => f!.readAsBytes());
      expect(bytes!.length, 2048, reason: 'scaled 본의 내용이 staging 사본에 온전히 있다');
    });

    testWidgets('P-6 소스 선택 창에서 취소 — picker 를 부르지 않는다', (t) async {
      var done = false;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => Scaffold(
        body: ElevatedButton(
          onPressed: () async {
            await ImageHelper.pickAndCompressImage(ctx, type: ImageType.document);
            done = true;
          },
          child: const Text('pick'),
        ),
      ))));
      await t.tap(find.text('pick'));
      for (var i = 0; i < 40 && find.text('취소').evaluate().isEmpty; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await t.pump();
      }
      await t.pumpAndSettle();
      await t.tap(find.text('취소'));
      for (var i = 0; i < 20 && !done; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await t.pump();
      }
      expect(done, isTrue);
      expect(h.picker.created, isEmpty);
      expect(h.cacheEntries(), isEmpty);
    });
  });

  group('SCOPE — 소유 판정', () {
    test('S-1 cache 밖 경로는 절대 지우지 않는다', () async {
      final outside = File('${h.root.path}/outside.jpg')..writeAsBytesSync([1]);
      final s = await PickerCacheScope.begin(root: h.cache);
      await s.capture(outside.path);
      await s.release();
      expect(outside.existsSync(), isTrue);
    });

    test('S-2 결과가 null 이어도 이 선택이 만든 UUID 폴더는 지운다', () async {
      final s = await PickerCacheScope.begin(root: h.cache);
      Directory('${h.cache.path}/11111111-2222-4333-8444-555555555555').createSync();
      await s.capture(null);
      expect(s.ownedDirsForTesting, hasLength(1));
      await s.release();
      expect(h.cacheEntries(), isEmpty);
    });

    test('S-3 UUID 가 아닌 새 폴더·이전부터 있던 scaled_ 는 소유가 아니다', () async {
      final s = await PickerCacheScope.begin(root: h.cache);
      Directory('${h.cache.path}/share').createSync();
      File('${h.cache.path}/scaled_1.jpg').writeAsBytesSync([1]);
      await s.capture(null);
      await s.release();
      expect(h.cacheEntries(), ['scaled_1.jpg', 'share']);
    });

    test('S-4 release 는 여러 번 불러도 안전하고, capture 없이 불러도 된다', () async {
      final s = await PickerCacheScope.begin(root: h.cache);
      Directory('${h.cache.path}/11111111-2222-4333-8444-555555555555').createSync();
      await s.release();
      await s.release();
      expect(h.cacheEntries(), isEmpty);
    });

    test('S-5 들고 있는 선택(외국인 신분증 형) — 놓기 전까지 파일이 살아 있고, 다음 선택 채택 때 앞의 것만 지운다', () async {
      final a = await PickerCacheScope.begin(root: h.cache);
      final pa = await h.picker.getImageFromSource(source: ImageSource.gallery,
          options: const ImagePickerOptions(maxWidth: 2000));
      await a.capture(pa!.path);
      expect(File(pa.path).existsSync(), isTrue, reason: '업로드 전까지 써야 한다');

      h.picker.mediaId = 66;
      final b = await PickerCacheScope.begin(root: h.cache);
      final pb = await h.picker.getImageFromSource(source: ImageSource.gallery,
          options: const ImagePickerOptions(maxWidth: 2000));
      await b.capture(pb!.path);
      await a.release(); // 채택 교체 — 앞 선택만
      expect(File(pa.path).existsSync(), isFalse);
      expect(File(pb.path).existsSync(), isTrue);
      expect(b.ownedDirsForTesting.every((d) => Directory('${h.cache.path}/$d').existsSync()), isTrue);
      await b.release();
      expect(h.cacheEntries(), isEmpty);
    });
  });

  group('MULTI — pickAndCompressMultipleImages(사업장·업무 사진)', () {
    Future<List<File>> runMulti(WidgetTester t, {int maxImages = 0}) async {
      List<File>? result;
      await t.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => Scaffold(
        body: ElevatedButton(
          onPressed: () async {
            result = await ImageHelper.pickAndCompressMultipleImages(ctx,
                maxImages: maxImages);
          },
          child: const Text('multi'),
        ),
      ))));
      await t.tap(find.text('multi'));
      for (var i = 0; i < 200 && result == null; i++) {
        await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
        await t.pump();
      }
      await t.pump(const Duration(seconds: 3)); // 잘라내기 경고 토스트
      return result!;
    }

    testWidgets('M-1 사진마다 생긴 UUID 사본·scaled_ 를 모두 정리하고, 반환 사본은 남는다', (t) async {
      final st = Directory('${h.support.path}/image_staging')..createSync(recursive: true);
      final biz = File('${st.path}/staged_555.jpg')..writeAsBytesSync([2]);
      final files = await runMulti(t);
      expect(files, hasLength(3));
      for (final f in files) {
        expect(await t.runAsync(() => f.exists()), isTrue);
      }
      expect(h.cacheEntries(), isEmpty);
      expect(biz.existsSync(), isTrue, reason: '사업장 staging 은 대상이 아니다');
    });

    testWidgets('M-2 개수 제한으로 잘라낸 사진의 산출물도 남지 않는다', (t) async {
      final files = await runMulti(t, maxImages: 2);
      expect(files, hasLength(2));
      expect(h.cacheEntries(), isEmpty, reason: '잘라낸 세 번째 사진의 UUID·scaled_ 까지');
    });
  });

  group('SHARED — 같은 사진 재선택으로 scaled_<id> 가 재사용될 때', () {
    test('SH-1 앞 선택을 놓아도, 같은 경로를 쥔 새 선택의 파일은 지우지 않는다(외국인 신분증 재선택)', () async {
      final a = await PickerCacheScope.begin(root: h.cache);
      final pa = await h.picker.getImageFromSource(source: ImageSource.gallery,
          options: const ImagePickerOptions(maxWidth: 2000));
      await a.capture(pa!.path);

      // 같은 MediaStore 사진 — 플러그인이 같은 scaled_64 를 덮어쓴다
      final b = await PickerCacheScope.begin(root: h.cache);
      final pb = await h.picker.getImageFromSource(source: ImageSource.gallery,
          options: const ImagePickerOptions(maxWidth: 2000));
      await b.capture(pb!.path);
      expect(pb.path, pa.path, reason: '재현 전제: 같은 경로');

      await a.release(); // 채택 교체 — 앞 선택만 놓는다
      expect(File(pb.path).existsSync(), isTrue,
          reason: '새 선택이 업로드까지 써야 하는 파일이다');
      await b.release();
      expect(File(pb.path).existsSync(), isFalse, reason: '마지막 소유자가 놓으면 지운다');
      expect(h.cacheEntries(), isEmpty);
    });

    test('SH-2 다른 범위가 쥐고 있는 scaled_ 는, 먼저 끝난 선택이 지우지 않는다', () async {
      final holder = await PickerCacheScope.begin(root: h.cache);
      final ph = await h.picker.getImageFromSource(source: ImageSource.gallery,
          options: const ImagePickerOptions(maxWidth: 2000));
      await holder.capture(ph!.path);

      final quick = await PickerCacheScope.begin(root: h.cache);
      final pq = await h.picker.getImageFromSource(source: ImageSource.gallery,
          options: const ImagePickerOptions(maxWidth: 4096));
      await quick.capture(pq!.path);
      await quick.release();
      expect(File(ph.path).existsSync(), isTrue);
      await holder.release();
      expect(h.cacheEntries(), isEmpty);
    });
  });

  group('LEGACY — 소유가 확정되는 옛 compressed_ 만', () {
    test('L-1 cache 루트 compressed_<13자리>.jpg 만 지운다', () async {
      File('${h.cache.path}/compressed_1787280304743.jpg').writeAsBytesSync([1]);
      File('${h.cache.path}/compressed_1787282670136123.jpg').writeAsBytesSync([1]); // 16자리
      File('${h.cache.path}/scaled_64.jpg').writeAsBytesSync([1]);
      Directory('${h.cache.path}/aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee').createSync();
      final staging = Directory('${h.support.path}/image_staging')..createSync(recursive: true);
      final cur = File('${staging.path}/compressed_1787280304743.jpg')..writeAsBytesSync([1]);
      final n = await ImageHelper.sweepLegacyCacheCompressed(cacheRoot: h.cache);
      expect(n, 1);
      expect(h.cacheEntries(), [
        'aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee',
        'compressed_1787282670136123.jpg',
        'scaled_64.jpg',
      ]);
      expect(cur.existsSync(), isTrue, reason: 'staging 은 다른 디렉터리 — 대상 아님');
    });
  });

  group('SOURCE — 인감·외국인 신분증 정리 시점', () {
    String code(String p) => File(p)
        .readAsStringSync()
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');

    test('SEAL-1 인감: 선택 전 begin, readAsBytes 직후 release, finally 에서도 release', () {
      final s = code('lib/screens/common/settings_screen.dart');
      final start = s.indexOf('Future<void> _registerSeal(');
      final body = s.substring(start, s.indexOf('String _sealErrorMessage', start));
      final iBegin = body.indexOf('PickerCacheScope.begin()');
      final iPick = body.indexOf('pickImage(');
      final iRead = body.indexOf('readAsBytes()');
      final iRelease = body.indexOf('pickScope.release()', iRead);
      final iCall = body.indexOf('_callSaveSeal(');
      expect(iBegin, greaterThanOrEqualTo(0));
      expect(iBegin, lessThan(iPick));
      expect(iRelease, greaterThan(iRead), reason: 'bytes 를 읽은 뒤에야 놓는다');
      expect(iRelease, lessThan(iCall));
      final iFinally = body.lastIndexOf(RegExp(r'\}\s*finally\s*\{'));
      expect(iFinally, greaterThan(iCall), reason: '바깥 finally 가 있다');
      expect(body.indexOf('pickScope.release()', iFinally), greaterThan(iFinally),
          reason: '취소·이탈·예외에도 놓는다');
    });

    test('PRF-1 프로필 사진: 선택 전 begin, readAsBytes 완료 시 release, 업로드(putData)는 그 뒤', () {
      final s = code('lib/screens/common/profile_edit_screen.dart');
      final start = s.indexOf('Future<void> _uploadPhoto(');
      final body = s.substring(start, s.indexOf('Future<void> _searchAddress', start));
      expect(body.indexOf('PickerCacheScope.begin()'), lessThan(body.indexOf('pickImage(')));
      expect(body, contains('readAsBytes().whenComplete(pickScope.release)'));
      expect(body.indexOf('whenComplete(pickScope.release)'), lessThan(body.indexOf('putData(')));
      expect('pickScope.release()'.allMatches(body).length, greaterThanOrEqualTo(2),
          reason: '취소·선택 예외 경로');
    });

    test('FRN-1 외국인 신분증: 채택 2곳·재사용·dispose 에서만 놓고, 업로드 경로는 놓지 않는다', () {
      final s = code('lib/screens/auth/foreign_register_screen.dart');
      expect('_adoptPickedImage(picked.path, scope)'.allMatches(s).length, 2);
      final dispose = s.substring(s.indexOf('void dispose()'), s.indexOf('super.dispose()', s.indexOf('void dispose()')));
      expect(dispose, contains('_releaseHeldPick()'));
      // 업로드(putFile) 가 있는 함수 본문엔 놓는 호출이 없다
      for (final m in RegExp(r'putFile\(File\(imagePath\)\)').allMatches(s)) {
        final fnStart = s.lastIndexOf('Future<void> _', m.start);
        final body = s.substring(fnStart, m.start);
        expect(body, isNot(contains('_releaseHeldPick()')), reason: '업로드 전에 놓으면 업로드가 깨진다');
        expect(body, isNot(contains('scope.release()')));
      }
    });
  });
}
