import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [PDF-PAGEBREAK.30] 실제 서명 PDF(단기·템플릿 2조항)에서 관찰한 쪽 나눔 두 건.
///   1) 제3조 제목만 1쪽 끝에 남고 상자가 2쪽으로 — pw.Column 은 MultiPage 에서 나뉜다.
///   2) 계약일은 2쪽 끝, 서명란은 3쪽에 홀로.
///   조 제목+상자, 계약일+서명란을 각각 나뉘지 않는 한 덩어리(pw.Inseparable)로 묶는다.
///   배치 자체는 기기에서 새 서명 PDF 를 렌더해 확인한다(텍스트 추출 PASS 는 배치 PASS 가 아니다).
void main() {
  final src = File('lib/screens/contract/contract_pdf_builder.dart').readAsStringSync();

  String body(String startMarker) {
    final i = src.indexOf(startMarker);
    expect(i, isNot(-1), reason: startMarker);
    return src.substring(i, (i + 900).clamp(0, src.length));
  }

  test('PB-1 조 제목과 내용 상자는 한 덩어리', () {
    final s = body('static pw.Widget _buildSection(');
    expect(s.contains('return pw.Inseparable('), isTrue);
    expect(s.indexOf('pw.Text(title'), greaterThan(s.indexOf('pw.Inseparable(')));
  });

  test('PB-2 계약일과 서명란은 한 덩어리', () {
    final i = src.indexOf('pw.Inseparable(\n            child: pw.Column(children: [\n              _buildDateLine(');
    final j = src.indexOf('pw.Inseparable(\r\n            child: pw.Column(children: [\r\n              _buildDateLine(');
    expect(i != -1 || j != -1, isTrue, reason: '계약일·서명란 묶음');
    expect(RegExp(r'_buildDateLine\(').allMatches(src).length, 2, reason: '정의 1 + 사용 1(묶음 안)');
    expect(RegExp(r'_buildSignatureRow\(').allMatches(src).length, 2);
  });
}
