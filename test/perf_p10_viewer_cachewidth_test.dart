import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/image_helper.dart';

// [P10 · impl_7] 전체화면 이미지 뷰어 — 원본을 그대로 디코드하지 않고 화면 긴 변 × DPR × 2 로 줄여 디코드한다.
void main() {
  testWidgets('P10-1 파일 이미지 전체화면 뷰어는 디코드 폭 상한(ResizeImage)을 건다', (t) async {
    final dir = Directory.systemTemp.createTempSync('p10');
    addTearDown(() => dir.deleteSync(recursive: true));
    // 1×1 PNG
    final f = File('${dir.path}/a.png')..writeAsBytesSync(base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=='));
    t.view.physicalSize = const Size(1080, 2340);
    t.view.devicePixelRatio = 2.625;
    addTearDown(t.view.reset);
    late BuildContext ctx;
    await t.pumpWidget(MaterialApp(home: Builder(builder: (c) {
      ctx = c;
      return const SizedBox.shrink();
    })));
    ImageHelper.showFullScreenViewer(ctx, imageFile: f);
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    final img = t.widget<Image>(find.byType(Image).last);
    expect(img.image, isA<ResizeImage>(), reason: '원본 해상도 그대로 디코드하지 않는다');
    // 논리 화면 411×891 · DPR 2.625 → 긴 변 891.4×2.625×2 ≈ 4680 → 상한 4096
    expect((img.image as ResizeImage).width, 4096);
  });
}
