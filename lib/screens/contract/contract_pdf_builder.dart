import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/core/contract_template_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../models/core/insurance_rate_model.dart';

/// PDF 빌드 — 쌍방 서명 완료 시 호출
class ContractPdfBuilder {
  static Future<Uint8List> build({
    required ContractSnapshot snapshot,
    required DateTime contractDate,
    List<ContractSlot> slots = const [],
    List<ContractArticle> articles = const [],
    String? employerSignatureUrl,
    Uint8List? workerSignatureBytes,
    String? ownerNameOverride,
    bool? isLongTermOverride,
    String employerSealType = 'stamp',
  }) async {
    final effectiveOwnerName = snapshot.ownerName.isNotEmpty
        ? snapshot.ownerName
        : (ownerNameOverride ?? '');
    final doc = pw.Document();

    // 한글 폰트 로드 (번들 에셋 — 오프라인 가능)
    final fontRegular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf'));
    final fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf'));

    // 서명 이미지 로드
    pw.MemoryImage? employerSig;
    pw.MemoryImage? workerSig;

    if (employerSignatureUrl != null) {
      try {
        final resp = await http.get(Uri.parse(employerSignatureUrl));
        if (resp.statusCode == 200) {
          employerSig = pw.MemoryImage(resp.bodyBytes);
        } else {
          throw Exception('사업주 서명 이미지 로드 실패 (HTTP ${resp.statusCode})');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('사업주 서명 이미지 로드 실패: $e');
        rethrow;
      }
    }
    if (workerSignatureBytes != null) {
      workerSig = pw.MemoryImage(workerSignatureBytes);
    }

    final baseStyle = pw.TextStyle(font: fontRegular, fontSize: 9);
    final boldStyle = pw.TextStyle(font: fontBold, fontSize: 9);
    final isLongTerm = isLongTermOverride ?? snapshot.isLongTerm;

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (ctx) => [
          _buildTitle(fontBold),
          pw.SizedBox(height: 24),
          _buildSection('제1조 (근로계약 당사자)', [
            _row('사업장명', snapshot.businessName, baseStyle, boldStyle),
            _row('대표자', effectiveOwnerName, baseStyle, boldStyle),
            _row('사업자번호', snapshot.businessNumber, baseStyle, boldStyle),
            _row('소재지', snapshot.businessAddress, baseStyle, boldStyle),
            if (snapshot.businessPhone != null)
              _row('연락처', snapshot.businessPhone!, baseStyle, boldStyle),
            pw.Divider(height: 12),
            _row('근로자 성명', snapshot.workerName, baseStyle, boldStyle),
            if (snapshot.workerBirthDate != null)
              _row('생년월일', snapshot.workerBirthDate!, baseStyle, boldStyle),
            if (snapshot.workerPhone != null)
              _row('연락처', snapshot.workerPhone!, baseStyle, boldStyle),
            if (snapshot.workerAddress != null)
              _row('주소', snapshot.workerAddress!, baseStyle, boldStyle),
          ], fontBold),
          pw.SizedBox(height: 16),
          _buildSection('제2조 (근무 조건)', [
            _row('근무 장소', snapshot.workPlace, baseStyle, boldStyle),
            _row('담당 업무', snapshot.workType, baseStyle, boldStyle),
            if (isLongTerm) ...[
              _row('근무 기간', snapshot.workPeriodText, baseStyle, boldStyle),
              if (snapshot.workDays != null)
                _row('근무 요일', snapshot.workDaysText, baseStyle, boldStyle),
              _row('근무 시간', snapshot.workTimeText, baseStyle, boldStyle),
            ] else ...[
              _row('근무 시간', snapshot.workTimeText, baseStyle, boldStyle),
              if (slots.isNotEmpty) ...[
                pw.SizedBox(height: 6),
                _buildSlotsTable(slots, baseStyle, boldStyle),
              ],
            ],
          ], fontBold),
          pw.SizedBox(height: 16),
          _buildSection('제3조 (임금)', [
            _row(snapshot.wageTypeLabel, snapshot.formattedWage, baseStyle, boldStyle),
            _row('지급 방법', snapshot.paymentMethod, baseStyle, boldStyle),
            if (snapshot.payScheduleTypeLabel.isNotEmpty)
              _row('지급 방식', snapshot.payScheduleTypeLabel, baseStyle, boldStyle),
            _row('지급 일정', snapshot.payScheduleLabel, baseStyle, boldStyle),
            if (snapshot.taxDeductionType != InsuranceRateModel.typeNone)
              _row('공제 방식', InsuranceRateModel.typeLabel(snapshot.taxDeductionType), baseStyle, boldStyle),
          ], fontBold),
          // 템플릿 조항 동적 렌더링
          ...articles.map((a) => pw.Column(children: [
            pw.SizedBox(height: 16),
            _buildSection(a.title, [
              pw.Text(a.content, style: baseStyle),
            ], fontBold),
          ])),
          pw.SizedBox(height: 32),
          _buildDateLine(contractDate, fontRegular),
          pw.SizedBox(height: 24),
          _buildSignatureRow(
            snapshot: snapshot,
            ownerName: effectiveOwnerName,
            employerSig: employerSig,
            workerSig: workerSig,
            fontRegular: fontRegular,
            fontBold: fontBold,
            employerSealType: employerSealType,
          ),
        ],
      ),
    );

    return doc.save();
  }

  // ─── 빌더 헬퍼 ────────────────────────────────────────────────

  static pw.Widget _buildTitle(pw.Font fontBold) {
    return pw.Center(
      child: pw.Column(children: [
        pw.Text(
          '근 로 계 약 서',
          style: pw.TextStyle(
            font: fontBold,
            fontSize: 22,
            fontWeight: pw.FontWeight.bold,
            letterSpacing: 4,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Container(height: 2, width: 120, color: PdfColors.blue700),
      ]),
    );
  }

  static pw.Widget _buildSection(
    String title,
    List<pw.Widget> children,
    pw.Font fontBold,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(title,
            style: pw.TextStyle(
                font: fontBold,
                fontSize: 11,
                fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 6),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(12),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
            color: PdfColors.grey100,
          ),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: children),
        ),
      ],
    );
  }

  static pw.Widget _row(
    String label,
    String value,
    pw.TextStyle base,
    pw.TextStyle bold,
  ) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 80,
            child: pw.Text(label,
                style: base.copyWith(color: PdfColors.grey700)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: bold),
          ),
        ],
      ),
    );
  }

  static pw.Widget _buildSlotsTable(
    List<ContractSlot> slots,
    pw.TextStyle base,
    pw.TextStyle bold,
  ) {
    final headerStyle = bold.copyWith(fontSize: 8, color: PdfColors.white);
    final cellStyle = base.copyWith(fontSize: 8);

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: {
        0: const pw.FlexColumnWidth(2),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FlexColumnWidth(2),
        3: const pw.FlexColumnWidth(2),
      },
      children: [
        // 헤더
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blueGrey700),
          children: ['근무일', '시작', '종료', '임금']
              .map((h) => pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(
                        vertical: 4, horizontal: 4),
                    child: pw.Text(h, style: headerStyle),
                  ))
              .toList(),
        ),
        // 슬롯 행
        ...slots.map((s) => pw.TableRow(
              children: [
                s.workDate,
                s.startTime,
                s.endTime,
                s.formattedWage,
              ]
                  .map((v) => pw.Padding(
                        padding: const pw.EdgeInsets.symmetric(
                            vertical: 3, horizontal: 4),
                        child: pw.Text(v, style: cellStyle),
                      ))
                  .toList(),
            )),
      ],
    );
  }

  static pw.Widget _buildDateLine(DateTime date, pw.Font font) {
    return pw.Center(
      child: pw.Text(
        '${date.year}년 ${date.month}월 ${date.day}일',
        style: pw.TextStyle(
            font: font, fontSize: 10, color: PdfColors.grey700),
      ),
    );
  }

  static pw.Widget _buildSignatureRow({
    required ContractSnapshot snapshot,
    required String ownerName,
    pw.MemoryImage? employerSig,
    pw.MemoryImage? workerSig,
    required pw.Font fontRegular,
    required pw.Font fontBold,
    String employerSealType = 'stamp',
  }) {
    return pw.Row(
      children: [
        pw.Expanded(
          child: _signBlock(
            label: '사업주 (갑)',
            name: ownerName,
            sigImage: employerSig,
            fontRegular: fontRegular,
            fontBold: fontBold,
            signLabel: employerSealType == 'stamp' ? '(인감)' : '(서명)',
          ),
        ),
        pw.SizedBox(width: 16),
        pw.Expanded(
          child: _signBlock(
            label: '근로자 (을)',
            name: snapshot.workerName,
            sigImage: workerSig,
            fontRegular: fontRegular,
            fontBold: fontBold,
          ),
        ),
      ],
    );
  }

  static pw.Widget _signBlock({
    required String label,
    required String name,
    pw.MemoryImage? sigImage,
    required pw.Font fontRegular,
    required pw.Font fontBold,
    String signLabel = '(서명)',
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  font: fontRegular,
                  fontSize: 10,
                  color: PdfColors.grey600)),
          pw.SizedBox(height: 8),
          pw.Container(
            height: 60,
            child: sigImage != null
                ? pw.Image(sigImage, fit: pw.BoxFit.contain)
                : pw.SizedBox(),
          ),
          pw.Divider(color: PdfColors.grey500),
          pw.Text(name,
              style: pw.TextStyle(
                  font: fontBold,
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold)),
          pw.Text(signLabel,
              style: pw.TextStyle(
                  font: fontRegular,
                  fontSize: 8,
                  color: PdfColors.grey500)),
        ],
      ),
    );
  }
}
