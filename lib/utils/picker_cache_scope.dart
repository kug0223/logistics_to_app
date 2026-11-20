// lib/utils/picker_cache_scope.dart
//
// [SIM-PICKER-CACHE] image_picker 가 **이 선택 한 번으로** 앱 cache 에 만든 것만
//   추적하고 정리한다.
//
//   image_picker_android 는 선택마다 두 가지를 cache 에 남긴다 —
//     · `cache/<UUID>/<이름>`   원본 사본 (FileUtils)
//     · `cache/scaled_<이름>`   크기 조정본 (ImageResizer — maxWidth·maxHeight·
//                               imageQuality<100 중 하나라도 주면 항상)
//   플러그인은 그것을 지우지 않고, 앱도 지우지 않았다. 통장사본·신분증·인감을
//   고를 때마다 민감 서류 사본 두 개가 cache 에 쌓였다(기기 READ 2026-10-18).
//
//   소유 판정 — 확실한 것만 지운다:
//     · 선택 **전** cache 루트의 UUID 폴더 목록을 찍어 두고, 선택 **후** 새로
//       생긴 UUID 폴더만 이 선택의 것으로 본다. 이미 있던 폴더(다른 선택·과거
//       잔여물)는 건드리지 않는다.
//     · picker 가 돌려준 경로는 그것이 cache 루트의 `scaled_*` 이거나 이 선택의
//       UUID 폴더 안에 있을 때만 지운다. cache 밖 경로는 절대 지우지 않는다.
//     · cache 루트 전체·`image_staging`(support 디렉터리)은 대상이 아니다.
//
//   언제 지우는가 — 마지막 소비자가 끝난 뒤:
//     · `ImageHelper.pickAndCompressImage` : 앱 소유 staging 사본이 만들어진 직후
//     · 인감 등록 : `readAsBytes()` 로 메모리에 올린 직후
//     · 외국인 신분증 : picker 경로를 업로드까지 들고 가므로 **재선택·화면 종료** 때
//
//   한계: 같은 이미지를 다른 화면이 동시에 골라 같은 `scaled_<이름>` 을 쓰고 있으면
//   그 파일은 공유된다(플러그인이 덮어쓴다). 선택 창이 모달이라 동시 선택은 없다.
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class PickerCacheScope {
  PickerCacheScope._(this._root, this._before);

  /// 선택 범위가 없는 상태(웹·cache 경로 없음) — 아무것도 지우지 않는다.
  PickerCacheScope._noop()
      : _root = null,
        _before = const {};

  final Directory? _root;
  final Set<String> _before;
  final Set<String> _ownedDirs = {};
  final List<String> _pickedPaths = [];
  final Set<String> _pickedKeys = {};
  bool _captured = false;
  bool _released = false;

  static final RegExp _uuid = RegExp(
      r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$');

  /// 선택 직전에 부른다.
  static Future<PickerCacheScope> begin({@visibleForTesting Directory? root}) async {
    if (kIsWeb) return PickerCacheScope._noop();
    try {
      final r = root ?? await getTemporaryDirectory();
      return PickerCacheScope._(r, await _uuidDirs(r));
    } catch (_) {
      return PickerCacheScope._noop();
    }
  }

  static Future<Set<String>> _uuidDirs(Directory root) async {
    final out = <String>{};
    try {
      await for (final e in root.list(followLinks: false)) {
        if (e is! Directory) continue;
        final name = e.uri.pathSegments.where((s) => s.isNotEmpty).last;
        if (_uuid.hasMatch(name)) out.add(name);
      }
    } catch (_) {}
    return out;
  }

  /// 선택이 끝난 직후(결과가 null 이어도) 부른다 — 이 선택이 만든 것을 확정한다.
  Future<void> capture(String? pickedPath) =>
      captureAll(pickedPath == null ? const [] : [pickedPath]);

  /// 다중 선택용 — picker 가 돌려준 경로 전부(잘라낸 것 포함)를 넘긴다.
  Future<void> captureAll(List<String> pickedPaths) async {
    final root = _root;
    if (_captured || root == null) return;
    _captured = true;
    for (final p in pickedPaths) {
      final k = _key(p);
      if (_pickedKeys.add(k)) {
        _pickedPaths.add(p);
        _liveClaims[k] = (_liveClaims[k] ?? 0) + 1;
      }
    }
    final after = await _uuidDirs(root);
    _ownedDirs.addAll(after.difference(_before));
  }

  /// [SIM-PICKER-CACHE] 같은 MediaStore 사진을 다시 고르면 플러그인이 **같은**
  ///   `scaled_<이름>` 을 덮어쓴다. 앞 선택을 놓으면서 그 경로를 지우면, 아직 그
  ///   경로를 쥔 새 선택(외국인 신분증의 재선택처럼 업로드까지 들고 가는 경우)의
  ///   파일이 사라진다. 그래서 놓지 않은 범위가 쥔 경로는 **마지막 소유자**가
  ///   놓을 때만 지운다.
  static final Map<String, int> _liveClaims = {};

  /// 이 선택이 소유한 것만 지운다. 여러 번 불러도 안전하다. 실패는 조용히 넘긴다.
  Future<void> release() async {
    final root = _root;
    if (_released || root == null) return;
    if (!_captured) await capture(null);
    _released = true;
    final rootPath = root.absolute.path;
    for (final picked in _pickedPaths) {
      final k = _key(picked);
      final left = (_liveClaims[k] ?? 1) - 1;
      if (left > 0) {
        _liveClaims[k] = left;
        continue; // 다른 선택이 아직 쓰고 있다
      }
      _liveClaims.remove(k);
      final f = File(picked);
      final parent = f.parent.absolute.path;
      final name = f.uri.pathSegments.last;
      final inRootScaled = _samePath(parent, rootPath) && name.startsWith('scaled_');
      final inOwnedDir = _ownedDirs.any((d) => _samePath(parent, '$rootPath${Platform.pathSeparator}$d'));
      if (inRootScaled || inOwnedDir) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
    for (final d in _ownedDirs) {
      try {
        final dir = Directory('$rootPath${Platform.pathSeparator}$d');
        if (await dir.exists()) await dir.delete(recursive: true);
      } catch (_) {}
    }
  }

  static String _key(String p) =>
      File(p).absolute.path.replaceAll('\\', '/').toLowerCase();

  static bool _samePath(String a, String b) {
    String n(String s) => s.replaceAll('\\', '/').replaceAll(RegExp(r'/+$'), '');
    return n(a) == n(b);
  }

  /// 테스트용 — 이 선택의 것으로 확정된 UUID 폴더.
  @visibleForTesting
  Set<String> get ownedDirsForTesting => Set.unmodifiable(_ownedDirs);
}
