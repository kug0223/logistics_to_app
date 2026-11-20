// [DU1 VQ] LOCAL 렌더 PNG 공통 — production 글꼴 로드 + RepaintBoundary 캡처(덮어쓰기 금지·실행 기록).
//   기기 캡처가 아니다. DU1_VQ_PHASE 가 없으면 캡처하지 않는다(일반 시험 실행에서 파일을 쓰지 않는다).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final String? vqPhase = Platform.environment['DU1_VQ_PHASE'];
bool get vqEnabled => vqPhase != null && vqPhase!.isNotEmpty;
final String vqRun = Platform.environment['DU1_VQ_RUN'] ??
    DateTime.now().toIso8601String().replaceAll(':', '').split('.').first;
// 캡처는 확인용으로 build/du1_vq 에 쓰고 회차 끝에 D:/AlFit-evidence/DU1/vq/png-runs 로 옮긴다(작은 PNG, C 용량 영향 미미)
// [DU1 후속37 §2.1] DU1_VQ_OUT 이 있으면 그 폴더(records 새 차수)에 직접 쓴다 — 복사 없음
Directory get vqOutDir {
  final o = Platform.environment['DU1_VQ_OUT'] ?? '';
  return Directory('${o.isNotEmpty ? o : 'build/du1_vq'}/$vqPhase/$vqRun');
}

/// [DU1 후속37 §2.1] 캡처 기준 '지금' — DU1_VQ_DATE=YYYY-MM-DD(KST) 가 있으면 그 날의 KST 자정 instant, 없으면 실제 지금.
///   fixture 날짜와 clock 이 같은 값에서 파생되게 한다(du1_vq_capture_test.dart 의 _baseDate 와 같은 규칙).
DateTime vqNow() {
  final v = Platform.environment['DU1_VQ_DATE'];
  if (v == null || v.isEmpty) return DateTime.now();
  final p = v.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]).subtract(const Duration(hours: 9));
}

Future<void> vqLoadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto']) {
    final l = FontLoader(fam)
      ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
      ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf'));
    await l.load();
  }
  final icons = FontLoader('MaterialIcons')
    ..addFont(b('C:/Users/kug02/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'));
  await icons.load();
}

/// [boundaryKey] 가 붙은 RepaintBoundary 를 PNG 로 쓴다. 같은 파일이 있으면 실패.
Future<void> vqCapture(WidgetTester t, GlobalKey boundaryKey, String id, {required Map<String, Object?> conditions}) async {
  if (!vqEnabled) return;
  final dir = vqOutDir..createSync(recursive: true);
  final rj = File('${dir.path}/$id.run.txt');
  final out = File('${dir.path}/$id.png');
  if (out.existsSync() || rj.existsSync()) throw StateError('이미 있는 캡처를 덮지 않는다: ${out.path}');
  final boundary = boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.0);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    out.writeAsBytesSync(bytes!.buffer.asUint8List());
  });
  rj.writeAsStringSync(conditions.entries.map((e) => '${e.key}=${e.value}').join('\n'));
}
