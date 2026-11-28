import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/pdf_font_cache.dart';

// [L30 · impl_7] 계약서 PDF 폰트 — 세션 안 최초 1회만 읽고 해석한다(명세서와 같은 static 캐시 방식).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final loads = <String>[];
  Future<ByteData> fileLoader(String key) async {
    loads.add(key);
    final b = await File(key).readAsBytes();
    return ByteData.view(b.buffer);
  }

  setUp(() {
    PdfFontCache.resetForTest();
    loads.clear();
  });
  tearDown(PdfFontCache.resetForTest);

  test('PF-1 두 번 만들어도 폰트 읽기는 종류마다 1회 · 같은 Font 객체', () async {
    PdfFontCache.loader = fileLoader;
    final r1 = await PdfFontCache.regular();
    final b1 = await PdfFontCache.bold();
    final r2 = await PdfFontCache.regular();
    final b2 = await PdfFontCache.bold();
    expect(identical(r1, r2) && identical(b1, b2), isTrue);
    expect(loads, [PdfFontCache.regularAsset, PdfFontCache.boldAsset]);
  });

  test('PF-2 동시 첫 요청 — 둘 다 폰트를 받고, 그 뒤 요청은 다시 읽지 않는다(r3: Future 공유 대신 값 캐시)', () async {
    final gate = Completer<ByteData>();
    var n = 0;
    PdfFontCache.loader = (k) { n++; return gate.future; };
    final a = PdfFontCache.regular();
    final b = PdfFontCache.regular();
    final bytes = await File(PdfFontCache.regularAsset).readAsBytes();
    gate.complete(ByteData.view(bytes.buffer));
    final ra = await a;
    final rb = await b;
    expect(ra, isNotNull);
    expect(rb, isNotNull);
    final before = n;
    final rc = await PdfFontCache.regular();
    expect(n, before, reason: '해석된 값을 재사용');
    expect(identical(rc, ra) || identical(rc, rb), isTrue);
  });

  test('PF-3 실패는 담지 않는다 — 다음 요청이 다시 읽는다', () async {
    var n = 0;
    PdfFontCache.loader = (k) async {
      n++;
      if (n == 1) throw StateError('asset');
      final b = await File(k).readAsBytes();
      return ByteData.view(b.buffer);
    };
    await expectLater(PdfFontCache.regular(), throwsStateError);
    await PdfFontCache.regular();
    expect(n, 2);
  });

  test('PF-5 번들 읽기가 SynchronousFuture 여도 Future.wait 로 두 폰트를 받는다(시험·캐시 자산 환경 회귀)', () async {
    PdfFontCache.loader = (k) => SynchronousFuture<ByteData>(
        ByteData.view(File(k).readAsBytesSync().buffer));
    final fonts = await Future.wait([PdfFontCache.regular(), PdfFontCache.bold()]);
    expect(fonts.length, 2);
  });

  test('PF-4 PDF 세 종류(계약서·임금명세서·근태 명단)가 폰트 캐시 **하나**를 쓴다(원문 · 판정291 공용 1개)', () {
    for (final f in [
      'lib/screens/contract/contract_pdf_builder.dart',
      'lib/screens/payroll/payslip_pdf_builder.dart',
      'lib/utils/attendance_list_pdf.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src.contains("rootBundle.load('assets/fonts/NotoSansKR"), isFalse, reason: f);
      expect(src.contains('PdfFontCache.regular()') && src.contains('PdfFontCache.bold()'), isTrue, reason: f);
    }
    // 앱 전체에서 폰트 자산을 직접 읽는 곳은 공용 캐시뿐
    final direct = Directory('lib').listSync(recursive: true).whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('assets/fonts/NotoSansKR-'))
        .map((f) => f.path.replaceAll(r'\', '/'))
        .toList();
    expect(direct, ['lib/utils/pdf_font_cache.dart']);
  });
}
