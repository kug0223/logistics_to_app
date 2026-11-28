import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/image_helper.dart';

// [P10 · impl_7] 디코드 폭 = 화면 긴 변 × DPR × 2 · 1080..4096.
void main() {
  test('P10-2 폭 계산 — 세로·가로 화면 같은 값(회전 여유) · 하한·상한', () {
    expect(fullScreenDecodeWidthForTest(const Size(360, 640), 2.0), 2560);
    expect(fullScreenDecodeWidthForTest(const Size(640, 360), 2.0), 2560);
    expect(fullScreenDecodeWidthForTest(const Size(300, 400), 1.0), 1080);
    expect(fullScreenDecodeWidthForTest(const Size(411, 891), 2.625), 4096);
  });
}
