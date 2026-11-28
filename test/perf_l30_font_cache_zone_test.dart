import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/pdf_font_cache.dart';

// [L30 r3 · impl_7] 회귀 재현 — 첫 testWidgets(FakeAsync zone)에서 채운 폰트 캐시를 다음 testWidgets 가 기다리다 멈추지 않는다.
//   (계약서 서명 시험 SIGX-51/52 10분 초과의 최소 재현 · 시험 사이 reset 없음이 핵심)
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    PdfFontCache.resetForTest();
    PdfFontCache.loader = (k) => SynchronousFuture<ByteData>(ByteData.view(File(k).readAsBytesSync().buffer));
  });
  tearDownAll(PdfFontCache.resetForTest);

  testWidgets('PZ-1 첫 시험이 폰트를 채운다', (t) async {
    final f = await Future.wait([PdfFontCache.regular(), PdfFontCache.bold()]);
    expect(f.length, 2);
  });

  testWidgets('PZ-2 다음 시험(다른 FakeAsync zone)도 같은 캐시를 기다리다 멈추지 않는다', (t) async {
    final f = await Future.wait([PdfFontCache.regular(), PdfFontCache.bold()]);
    expect(f.length, 2);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
