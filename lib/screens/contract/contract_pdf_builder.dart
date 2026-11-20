import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/core/contract_template_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../models/core/insurance_rate_model.dart';
import '../../utils/attendance_policy_disclosure.dart';

/// PDF 빌드 — 쌍방 서명 완료 시 호출
class ContractPdfBuilder {
  static Future<Uint8List> build({
    required ContractSnapshot snapshot,
    required DateTime contractDate,
    List<ContractSlot> slots = const [],
    List<ContractArticle> articles = const [],
    Uint8List? employerSignatureBytes,
    Uint8List? workerSignatureBytes,
    String? ownerNameOverride,
    bool? isLongTermOverride,
    String employerSealType = 'stamp',
  }) async {
    // [R8P6-SIG-CUTOVER] 인자 검증은 폰트 파싱보다 **앞**이다 — 서명이 비었으면
    //   한글 폰트 두 벌을 읽을 이유가 없다. 빈 바이트는 "서명 없음"이 아니라
    //   "못 가져왔다"는 뜻이므로, 서명란이 빈 PDF 를 만들어선 안 된다.
    if (employerSignatureBytes != null && employerSignatureBytes.isEmpty) {
      throw Exception('사업주 서명 이미지가 비어 있습니다');
    }
    if (workerSignatureBytes != null && workerSignatureBytes.isEmpty) {
      throw Exception('근로자 서명 이미지가 비어 있습니다');
    }

    // ownerNameOverride: 근무자 경로에서 스냅샷 ownerName이 없을 때 Firestore 조회값.
    // 둘 다 없는 구형 계약서는 '(사업주)' fallback으로 PDF에서 빈 이름 방지.
    final effectiveOwnerName = snapshot.ownerName.isNotEmpty
        ? snapshot.ownerName
        : (ownerNameOverride?.isNotEmpty == true ? ownerNameOverride! : '(사업주)');
    final doc = pw.Document();

    // 한글 폰트 로드 (번들 에셋 — 오프라인 가능)
    final fontRegular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf'));
    final fontBold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf'));

    // 서명 이미지 로드
    pw.MemoryImage? employerSig;
    pw.MemoryImage? workerSig;

    // [R8P6-SIG-CUTOVER] 여기서 네트워크를 쓰지 않는다 — 바이트를 받아 그린다.
    //
    //   예전에는 계약 문서의 영구 토큰 URL 을 이 안에서 `http.get` 했다.
    //   그래서 (1) 빌더가 권한·만료·재시도를 알아야 했고, (2) URL 이 없는
    //   계약(단계 C 의 신규 계약)에서는 **사업주 서명이 빠진 PDF 가 조용히**
    //   만들어졌다. 서명란이 빈 계약서가 완료 처리되는 셈이었다.
    //
    //   이제 호출자가 `ContractService.fetchContractSignatureBytes` 로
    //   그때의 권한에 따라 바이트를 받아 넘긴다. 못 받으면 거기서 예외가 난다 —
    //   빌더까지 오지 않는다. 근로자 서명(`workerSignatureBytes`)과 **같은 모양**이다.
    if (employerSignatureBytes != null) {
      employerSig = pw.MemoryImage(employerSignatureBytes);
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
            // [R7-PAYROLL-POLICY.4] 화면과 PDF 가 같은 것을 말해야 한다 —
            //   서명된 문서가 화면보다 적게 적혀 있으면 안 된다.
            // [R7-PAYROLL-POLICY.4B] 그래서 항목 목록을 손으로 적지 않고
            //   화면과 **같은 formatter** 에서 받는다. 한쪽만 7개가 되는 일이
            //   구조적으로 생기지 않는다.
            // [ATTENDANCE-RULE-GUIDE.29-A1] 화면과 같은 구조·같은 생성 함수 — 서명된 문서가 화면보다 적게
            //   말하지 않는다. 이 빌더는 근로자 서명 때 한 번 돌아 PDF 를 보관한다(이미 보관된 PDF 는 그대로).
            if (snapshot.attendancePolicy case final policy?)
              _buildAttendanceRuleGuide(
                  attendanceRuleGuide(policy,
                      startHHmm: snapshot.startTime, endHHmm: snapshot.endTime),
                  baseStyle,
                  boldStyle),
          ], fontBold),
          // 템플릿 조항 동적 렌더링
          ...articles.map((a) => pw.Column(children: [
            pw.SizedBox(height: 16),
            _buildSection(a.title, [
              pw.Text(a.content, style: baseStyle),
            ], fontBold),
          ])),
          pw.SizedBox(height: 32),
          // [PDF-PAGEBREAK.30] 계약일과 서명란은 한 덩어리 — 날짜만 앞 쪽에 남고 서명이 다음 쪽에
          //   홀로 넘어가지 않게 한다(실제 서명 PDF 3쪽에서 관찰).
          pw.Inseparable(
            child: pw.Column(children: [
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
            ]),
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
    // [PDF-PAGEBREAK.30] 조 제목과 내용 상자는 한 덩어리 — Column 은 MultiPage 에서 쪽을 나눌 수 있어
    //   제목만 앞 쪽 끝에 남고 상자가 다음 쪽으로 넘어갔다(제3조, 실제 서명 PDF). 상자는 원래 나뉘지 않는다.
    return pw.Inseparable(
        child: pw.Column(
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
    ));
  }

  /// [ATTENDANCE-RULE-GUIDE.29-A1] 근무시간 → 출근/퇴근 기준 → 항목 설명 → 그 기준의 사례.
  static pw.Widget _buildAttendanceRuleGuide(
      AttendanceRuleGuide g, pw.TextStyle base, pw.TextStyle bold) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 8),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(kAttendanceRuleGuideTitle, style: bold),
          if (g.workTime != null) pw.Text('근무시간 ${g.workTime}', style: base),
          for (final s in g.sections) ...[
            pw.SizedBox(height: 4),
            pw.Text(s.title, style: bold),
            for (final i in s.items) ...[
              pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 6, top: 2),
                  child: pw.Text(i.title, style: bold)),
              for (final p in i.points)
                pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 10),
                    child: pw.Text('· $p', style: base)),
              for (final e in i.examples)
                pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 16),
                    child: pw.Text('예: ${attendanceRuleExampleText(e)}',
                        style: base.copyWith(color: PdfColors.grey700))),
            ],
          ],
        ],
      ),
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
