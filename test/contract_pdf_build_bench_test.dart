// [R8-P6] 계약서 PDF 빌드 비용 분해 — 서명 버튼을 누른 뒤 무엇이 오래 걸리는가.
//
//   ContractPdfBuilder.build() 는 호출마다 NotoSansKR Regular/Bold 를 새로 파싱한다.
//   두 파일 합계 11.8MB 다. 폰트 파싱과 실제 렌더를 갈라서 잰다.
//
//   호스트 PC 측정이라 기기 절대값은 아니다. 알고 싶은 것은 비율이다 —
//   폰트가 지배적이면 캐시가 답이고, 렌더가 지배적이면 다른 이야기가 된다.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/widgets.dart' as pw;

import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/screens/contract/contract_pdf_builder.dart';

ContractSnapshot _snapshot() => ContractSnapshot.fromMap({
      'businessName': '합성사업장',
      'businessNumber': '000-00-00000',
      'businessAddress': '서울특별시 어딘가 123',
      'ownerName': '합성대표',
      'workerName': '합성근로자',
      'workerBirthDate': '1990-01-01',
      'workerPhone': '010-0000-0000',
      'workerAddress': '서울특별시 어딘가 456',
      'workType': '홀서빙',
      'workPlace': '합성사업장 1층',
      'isLongTerm': false,
      'startTime': '09:00',
      'endTime': '18:00',
      'breakMinutes': 60,
      'wage': 10030,
      'wageType': 'hourly',
      'paymentMethod': '계좌이체',
    });

/// 서명 패드 출력과 비슷한 합성 PNG (600x200 RGBA, 획 몇 개).
/// 실제 서명도 투명 배경에 얇은 획뿐이라 잘 압축된다 — 몇 KB 수준.
Uint8List _signaturePng() {
  const w = 600;
  const h = 200;
  final raw = Uint8List((w * 4 + 1) * h);
  for (var y = 0; y < h; y++) {
    final off = y * (w * 4 + 1);
    for (var x = 0; x < w; x++) {
      final p = off + 1 + x * 4;
      final onStroke = ((math.sin(x / 38) * 60 + 100) - y).abs() < 4 ||
          ((math.cos(x / 25) * 40 + 110) - y).abs() < 3;
      raw[p + 3] = onStroke ? 255 : 0;
    }
  }
  final idat = Uint8List.fromList(zlib.encode(raw));

  final crcTable = List<int>.generate(256, (n) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    return c;
  });
  int crc(List<int> bytes) {
    var c = 0xFFFFFFFF;
    for (final b in bytes) {
      c = crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
    }
    return (c ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }

  Uint8List chunk(String type, List<int> data) {
    final out = BytesBuilder();
    final len = ByteData(4)..setUint32(0, data.length);
    out.add(len.buffer.asUint8List());
    final td = <int>[...type.codeUnits, ...data];
    out.add(td);
    final c = ByteData(4)..setUint32(0, crc(td));
    out.add(c.buffer.asUint8List());
    return out.toBytes();
  }

  final ihdr = ByteData(13)
    ..setUint32(0, w)
    ..setUint32(4, h)
    ..setUint8(8, 8)
    ..setUint8(9, 6);
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ...chunk('IHDR', ihdr.buffer.asUint8List()),
    ...chunk('IDAT', idat),
    ...chunk('IEND', const []),
  ]);
}

int _ms(Stopwatch s) => s.elapsedMilliseconds;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('[R8P6-BENCH] PDF 빌드 단계별 비용', () async {
    // ── 1. 폰트 에셋 로드 + 파싱 ────────────────────────────
    final sw = Stopwatch()..start();
    final regularData = await rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf');
    final loadMs = _ms(sw);

    sw.reset();
    final fontRegular = pw.Font.ttf(regularData);
    final fontBold = pw.Font.ttf(boldData);
    final parseMs = _ms(sw);

    // ── 2. 같은 일을 다시 (캐시했다면 0 에 가까울 자리) ──────
    sw.reset();
    final r2 = await rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf');
    final b2 = await rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf');
    pw.Font.ttf(r2);
    pw.Font.ttf(b2);
    final secondMs = _ms(sw);

    // ── 3. 전체 build() 3회 ─────────────────────────────────
    final png = _signaturePng();
    final runs = <int>[];
    late Uint8List pdf;
    for (var i = 0; i < 3; i++) {
      sw.reset();
      pdf = await ContractPdfBuilder.build(
        snapshot: _snapshot(),
        contractDate: DateTime(2026, 10, 1),
        workerSignatureBytes: png,
        // employerSignatureUrl 은 일부러 비운다 — 네트워크는 따로 센다
      );
      runs.add(_ms(sw));
    }
    runs.sort();

    // ignore: avoid_print
    print('''

════════ [R8P6] PDF 빌드 비용 (호스트 측정) ════════
  폰트 에셋 크기        Regular ${(regularData.lengthInBytes / 1048576).toStringAsFixed(1)}MB / Bold ${(boldData.lengthInBytes / 1048576).toStringAsFixed(1)}MB
  ① 에셋 로드           ${loadMs}ms
  ② Font.ttf 파싱       ${parseMs}ms
  ③ ①+② 재실행          ${secondMs}ms   ← 매 호출 반복되는 비용
  ④ build() 전체        ${runs.join('ms, ')}ms  (median ${runs[1]}ms)
  ⑤ 서명 PNG 크기        ${(png.lengthInBytes / 1024).toStringAsFixed(1)}KB
  ⑥ 생성된 PDF 크기      ${(pdf.lengthInBytes / 1024).toStringAsFixed(0)}KB
  ⑦ PDF base64 후       ${(pdf.lengthInBytes * 4 / 3 / 1024).toStringAsFixed(0)}KB
  폰트 비중             ${(secondMs * 100 / (runs[1] == 0 ? 1 : runs[1])).toStringAsFixed(0)}% of build()
  참고: fontRegular=${fontRegular.hashCode != 0} fontBold=${fontBold.hashCode != 0}
════════════════════════════════════════════════════
''');

    expect(pdf.lengthInBytes, greaterThan(0));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
