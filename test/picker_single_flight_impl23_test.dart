// [impl_23 · 2026-11-27] 기기 사진 고르기 단일 실행 — `ImageHelper` 공용 진입점이 첫 await 전에 잠근다.
//
//   PK-1  (위젯) 출처 시트가 뜨기 전 연타 2번 → 시트 1장 · 피커 1번 · 끝나면 다시 고를 수 있다
//         (안쪽 단계는 잠그지 않는다 — 첫 탭이 실제 피커까지 간다 = 중첩 잠금으로 스스로 막히지 않는다)
//   PK-2  진행 중 다른 진입점(단일·다중·직접 출처)도 피커를 부르지 않고 즉시 "취소" 값(null / 빈 목록)
//   PK-3  실패해도 잠금이 풀린다
//   PK-4  소스 — 공개 진입점 5개 모두 exclusive · 직접 ImagePicker 를 부르는 화면 전수(넘김 목록과 일치)
// 플러그인 플랫폼 인터페이스(전이 의존)는 가짜 피커·경로를 끼우는 데만 쓴다 — picker_cache_ownership_test 와 같다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/utils/action_guard.dart';
import 'package:ALfit/utils/image_helper.dart';

class _Paths extends PathProviderPlatform with MockPlatformInterfaceMixin {
  _Paths(this.temp);
  final String temp;
  @override
  Future<String?> getTemporaryPath() async => temp;
  @override
  Future<String?> getApplicationSupportPath() async => temp;
}

/// 부를 때마다 센다. [hold] 가 있으면 그 Completer 가 끝날 때까지 피커가 "열려 있다".
class _CountingPicker extends ImagePickerPlatform with MockPlatformInterfaceMixin {
  int single = 0, multi = 0;
  Completer<XFile?>? hold;
  Object? throwOnce;
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async {
    single++;
    final t = throwOnce;
    if (t != null) {
      throwOnce = null;
      throw t;
    }
    return hold?.future;
  }

  @override
  Future<List<XFile>> getMultiImageWithOptions({
    MultiImagePickerOptions options = const MultiImagePickerOptions(),
  }) async {
    multi++;
    return const [];
  }
}

String _code(String p) => File(p)
    .readAsStringSync()
    .replaceAll('\r\n', '\n')
    .split('\n')
    .map((l) {
      final i = l.indexOf('//');
      return i >= 0 ? l.substring(0, i) : l;
    })
    .join('\n');

/// 실제 파일 I/O(PickerCacheScope 의 cache 폴더 목록)가 끝나고 시트 애니메이션이 멈출 때까지.
Future<void> _settleIo(WidgetTester t) async {
  for (var i = 0; i < 30; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump(const Duration(milliseconds: 50));
  }
  await t.pumpAndSettle();
}

void main() {
  late _CountingPicker picker;
  late Directory tmp;

  setUp(() async {
    ActionGuard.resetForTest();
    tmp = await Directory.systemTemp.createTemp('pk23_');
    PathProviderPlatform.instance = _Paths(tmp.path);
    picker = _CountingPicker();
    ImagePickerPlatform.instance = picker;
  });
  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  testWidgets('PK-1 시트가 뜨기 전 연타 2번 → 시트 1장 · 피커 1번 · 끝나면 다시 고를 수 있다', (t) async {
    final results = <File?>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () async =>
                  results.add(await ImageHelper.pickAndCompressImage(ctx, useBottomSheet: true)),
              child: const Text('사진 추가'),
            ),
          ),
        ),
      ),
    ));
    // 같은 프레임 두 번 — 사이에 pump 없음(시트의 막이 아직 덮지 않았다)
    await t.tap(find.text('사진 추가'));
    await t.tap(find.text('사진 추가'));
    // 첫 탭은 시트 전에 cache 폴더 목록을 실제 파일 I/O 로 읽는다(PickerCacheScope) — 실제 시간을 잠깐 준다.
    await _settleIo(t);
    expect(find.text('이미지 선택'), findsOneWidget, reason: '두 번째 탭이 출처 시트를 한 장 더 띄웠다');
    expect(results, [null], reason: '두 번째 탭은 즉시 "취소"(null)로 끝난다');
    expect(ImageHelper.debugPickerBusy, isTrue);

    picker.hold = Completer<XFile?>();
    await t.tap(find.text('갤러리에서 선택'));
    await t.pump();
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump();
    expect(picker.single, 1, reason: '첫 탭은 실제 피커까지 간다(안쪽 단계는 잠그지 않는다)');

    // 피커가 열린 동안 다시 눌러도 시트도 피커도 다시 열리지 않는다
    await t.tap(find.text('사진 추가'), warnIfMissed: false);
    await t.pumpAndSettle();
    expect(find.text('이미지 선택'), findsNothing);
    expect(picker.single, 1);

    picker.hold!.complete(null); // 사용자가 피커에서 취소
    await _settleIo(t); // 선택 뒤 cache 정리(실제 파일 I/O)까지
    expect(ImageHelper.debugPickerBusy, isFalse, reason: '끝나면 잠금이 풀려야 한다');

    await t.tap(find.text('사진 추가'));
    await _settleIo(t);
    expect(find.text('이미지 선택'), findsOneWidget, reason: '끝난 뒤에는 다시 고를 수 있다');
  });

  testWidgets('PK-2 진행 중이면 다른 진입점도 피커를 부르지 않고 즉시 취소 값', (t) async {
    picker.hold = Completer<XFile?>();
    final first = ImageHelper.pickImageFromSource(ImageSource.gallery);
    BuildContext? ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    expect(await ImageHelper.pickImageFromSource(ImageSource.camera), isNull);
    expect(await ImageHelper.pickMultipleImages(ctx!), isEmpty);
    expect(await ImageHelper.pickAndCompressMultipleImages(ctx!), isEmpty);
    expect(await ImageHelper.pickSingleImage(ctx!), isNull);
    expect(await ImageHelper.pickAndCompressImage(ctx!), isNull);
    expect(await ImageHelper.exclusive(() async => 'x'), isNull);
    expect(picker.single, 1);
    expect(picker.multi, 0);
    picker.hold!.complete(null);
    expect(await first, isNull);
    expect(ImageHelper.debugPickerBusy, isFalse);
  });

  testWidgets('PK-3 피커가 실패해도 잠금이 풀린다', (t) async {
    picker.throwOnce = StateError('already_active');
    expect(await ImageHelper.pickImageFromSource(ImageSource.gallery), isNull);
    expect(ImageHelper.debugPickerBusy, isFalse);
    expect(await ImageHelper.pickImageFromSource(ImageSource.gallery), isNull);
    expect(picker.single, 2, reason: '실패 뒤 다음 고르기는 피커까지 간다');
  });

  test('PK-4 소스 — 공개 진입점 5개 exclusive · 직접 ImagePicker 호출 전수', () {
    final h = _code('lib/utils/image_helper.dart').replaceAll(RegExp(r'\s+'), ' ');
    for (final sig in [
      'static Future<File?> pickSingleImage(',
      'static Future<File?> pickImageFromSource(',
      'static Future<List<File>> pickMultipleImages(',
      'static Future<File?> pickAndCompressImage(',
      'static Future<List<File>> pickAndCompressMultipleImages(',
    ]) {
      final at = h.indexOf(sig);
      expect(at, greaterThan(-1), reason: sig);
      final head = h.substring(at, (at + 600).clamp(0, h.length));
      expect(head.contains('exclusive('), isTrue, reason: '$sig — 단일 실행을 거치지 않는다');
    }
    expect(h.contains('final file = await _pickSingleImage('), isTrue, reason: '안쪽은 잠그지 않는 함수로(중첩 잠금 0)');
    expect(h.contains('final files = await _pickMultipleImages('), isTrue);
    expect(_code('lib/screens/common/profile_edit_screen.dart').replaceAll(RegExp(r'\s+'), ' '),
        contains('Future<void> _showPhotoPicker() => ImageHelper.exclusive<void>(() async {'));
    expect(_code('lib/screens/common/settings_screen.dart').replaceAll(RegExp(r'\s+'), ' '),
        contains('Future<void> _registerSeal(BuildContext context, UserModel? user) => ImageHelper.exclusive<void>(() => _registerSealLocked(context, user));'),
        reason: '인감 등록(출처 시트 + 직접 피커)도 같은 단일 실행');

    // helper 밖에서 피커 플러그인을 직접 부르는 곳 — 넘김 목록과 같아야 한다(새로 생기면 실패).
    const handedOff = {
      'lib/screens/auth/foreign_register_screen.dart', // auth 제외 · 옛 외국인 가입 마법사(신규 가입 닫힘)
    };
    final direct = <String>{};
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      final p = f.path.replaceAll('\\', '/');
      if (p == 'lib/utils/image_helper.dart') continue;
      final c = _code(p);
      final usesPicker = RegExp(r'ImagePicker\(\)\s*\.\s*pick|\bpicker\.pick(Image|MultiImage|Media|Video)\(|FilePicker\.platform').hasMatch(c);
      if (!usesPicker) continue;
      if ((p == 'lib/screens/common/profile_edit_screen.dart' || p == 'lib/screens/common/settings_screen.dart') &&
          c.contains('ImageHelper.exclusive')) {
        continue;
      }
      direct.add(p);
    }
    expect(direct, handedOff);
  });
}
