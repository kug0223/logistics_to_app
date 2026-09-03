// lib/screens/payroll/payslip_pdf_builder.dart
//
// 임금명세서 PDF 생성기 (근로기준법 제48조 준수)
// - 온디바이스 생성 (Firebase Storage 비용 없음)
// - 한글 NotoSansKR 폰트 (번들 에셋, 오프라인 가능)

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../models/core/attendance_model.dart';
import '../../models/core/insurance_rate_model.dart';
import '../../models/core/wage_detail_model.dart';
import '../../utils/format_helper.dart';
import '../../utils/wage_calculation_lines.dart';
import 'payslip_period_helper.dart';

/// 임금명세서 생성에 필요한 데이터 묶음
class PayslipData {
  // 사업장
  final String businessName;
  final String businessNumber;    // 사업자등록번호 (선택)
  final String businessAddress;   // 사업장 주소 (선택)
  final String ownerName;         // 대표자명 (선택)

  // 근무자
  final String workerName;
  final String workerBirthDate;   // 'yyyy-MM-dd' (선택)

  // 근무 정보
  final DateTime workDate;
  final String workType;
  final String? checkIn;
  final String? checkOut;
  final int workMinutes;

  // 급여 상세
  final WageDetailModel wageDetail;

  // 지급일 — wageStatus 기반 분리 (PAYSLIP-07)
  //   transferred: actualPaymentDate = transferDate (이체 완료 → "임금지급일")
  //   confirmed:   scheduledPaymentDate = paymentDueDate (이체 전 → "지급 예정일", null이면 행 숨김)
  //   그 외:       지급일 행 표시 안 함
  final String wageStatus;
  final DateTime? actualPaymentDate;     // 실제 이체일 (transferred 상태)
  final DateTime? scheduledPaymentDate;  // 지급 예정일 (confirmed 상태)

  const PayslipData({
    required this.businessName,
    this.businessNumber = '',
    this.businessAddress = '',
    this.ownerName = '',
    required this.workerName,
    this.workerBirthDate = '',
    required this.workDate,
    required this.workType,
    this.checkIn,
    this.checkOut,
    required this.workMinutes,
    required this.wageDetail,
    this.wageStatus = AttendanceModel.wageConfirmed,
    this.actualPaymentDate,
    this.scheduledPaymentDate,
  });

  /// AttendanceModel에서 편리하게 생성
  factory PayslipData.fromAttendance({
    required AttendanceModel attendance,
    required String workerName,
    String workerBirthDate = '',
    String businessNumber = '',
    String businessAddress = '',
    String ownerName = '',
    // [PAYSLIP-07] 지급일은 attendance에서 직접 파생 — 호출자 별도 전달 불필요
  }) {
    // assert는 release 빌드에서 제거됨 → ArgumentError로 교체해 런타임 크래시 방지
    final wd = attendance.wageDetail;
    if (wd == null) {
      throw ArgumentError('wageDetail이 없는 출근 기록으로는 임금명세서를 생성할 수 없습니다');
    }
    final status = attendance.wageStatus;
    return PayslipData(
      businessName: attendance.businessName,
      businessNumber: businessNumber,
      businessAddress: businessAddress,
      ownerName: ownerName,
      workerName: workerName,
      workerBirthDate: workerBirthDate,
      workDate: attendance.workDate,
      workType: attendance.workType,
      checkIn: attendance.checkIn?.split(':').take(2).join(':'),
      checkOut: attendance.checkOut?.split(':').take(2).join(':'),
      workMinutes: wd.workMinutes,
      wageDetail: wd,
      wageStatus: status,
      // transferred: 실제 이체일 사용 (null이면 정합성 오류로 UI에서 별도 표시)
      actualPaymentDate: status == AttendanceModel.wageTransferred
          ? attendance.transferDate
          : null,
      // confirmed: 지급 예정일 사용 (null이면 PDF에서 행 숨김)
      scheduledPaymentDate: status == AttendanceModel.wageConfirmed
          ? attendance.paymentDueDate
          : null,
    );
  }
}

// ─── PDF 빌더 ────────────────────────────────────────────────────

class PayslipPdfBuilder {
  // [PERF-4] 폰트 static 캐시 — 앱 세션 내 최초 1회만 ByteData 파싱
  static pw.Font? _cachedFontR;
  static pw.Font? _cachedFontB;

  // [PERF-9] 천단위 콤마 정규식 — 매 _fmtWon() 호출마다 생성 방지
  static final _commaRe = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');

  /// 폰트 사전 로드 및 캐시 — 호출 측에서 존재 확인 + build() 캐시 히트 보장
  static Future<(pw.Font, pw.Font)> loadFonts() async {
    _cachedFontR ??= pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf'));
    _cachedFontB ??= pw.Font.ttf(
        await rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf'));
    return (_cachedFontR!, _cachedFontB!);
  }

  /// 임금명세서 PDF 바이트 생성
  /// [data] - 표시할 급여 정보
  /// Returns: PDF 바이트 (share / print / download에 사용)
  static Future<Uint8List> build(PayslipData data) async {
    // ── 폰트 로드 (캐시 사용) ──────────────────────────────────
    final (fontR, fontB) = await loadFonts();

    // ── 스타일 헬퍼 ─────────────────────────────────────────────
    pw.TextStyle ts(double size, {bool bold = false, PdfColor? color}) =>
        pw.TextStyle(
          font: bold ? fontB : fontR,
          fontSize: size,
          color: color,
        );

    final primary = PdfColor.fromHex('#1565C0'); // AppColors.primary 대응
    final grey    = PdfColor.fromHex('#9E9E9E');
    final black   = PdfColors.black;

    final wd = data.wageDetail;

    // ── 문서 생성 ───────────────────────────────────────────────
    final doc = pw.Document();

    // 계산 기준 줄 목록 — 섹션 유무 분기용으로 미리 계산
    final calcLines = buildWageCalculationLines(wd);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
        footer: (ctx) => _buildFooter(ctx, ts, grey),
        build: (ctx) {
          return [
            // ─ 헤더 ─────────────────────────────────────────────
            _buildHeader(data, ts, primary, grey),
            pw.SizedBox(height: 10), // 14 → 10: 헤더 하단 간격 축소

            // ─ 기본 정보 ────────────────────────────────────────
            _buildInfoBlock(data, ts),
            pw.SizedBox(height: 16), // 12 → 16: 섹션 간 rhythm 균형

            // ─ 근무 시간 ────────────────────────────────────────
            _buildWorkTimeSection(data, wd, ts, primary, grey, black),
            pw.SizedBox(height: 16),

            // ─ 지급 내역 ────────────────────────────────────────
            _buildPaySection(wd, ts, primary, grey, black),
            pw.SizedBox(height: 16),

            // ─ 계산 기준 (수당 항목이 있을 때만) ─────────────────
            if (calcLines.isNotEmpty) ...[
              _buildCalculationSection(calcLines, ts, primary, grey, black),
              pw.SizedBox(height: 16),
            ],

            // ─ 공제 내역 ────────────────────────────────────────
            if (wd.taxDeductionType != InsuranceRateModel.typeNone) ...[
              _buildDeductionSection(wd, ts, primary, grey, black),
              pw.SizedBox(height: 16),
            ],

            // ─ 최종 실수령액 ─────────────────────────────────────
            _buildNetWageBox(wd, ts, primary),
            pw.SizedBox(height: 12), // 16 → 12

            // ─ 법적 고지 (compact — 박스 없이 인라인 텍스트) ────────
            _buildLegalNote(ts, grey),
          ];
        },
      ),
    );

    return doc.save();
  }

  // ─── 헤더 ──────────────────────────────────────────────────────
  static pw.Widget _buildHeader(
    PayslipData d,
    Function ts,
    PdfColor primary,
    PdfColor grey,
  ) {
    // ── 지급일 행 구성 (wageStatus 기반, PAYSLIP-07) ──────────────
    //   transferred + actualPaymentDate  → "임금지급일: X"
    //   transferred + null               → 정합성 오류 표시
    //   confirmed   + scheduledPaymentDate → "지급 예정일: X"
    //   confirmed   + null / 그 외       → 행 생략
    final List<pw.Widget> dateRows = [];

    if (d.wageStatus == AttendanceModel.wageTransferred) {
      if (d.actualPaymentDate != null) {
        dateRows.add(pw.Text(
          '임금지급일: ${FormatHelper.formatDateDot(d.actualPaymentDate!)}',
          style: ts(9.0, color: grey),
        ));
      } else {
        // [DEFENSIVE] transferred + transferDate == null
        //   CF 3개 경로 모두 동일 tx.update() 객체에 transferDate를 항상 포함시키므로
        //   정상 레코드에서는 발생하지 않음. legacy 데이터 또는 비정상 쓰기 방어용.
        dateRows.add(pw.Text(
          '임금지급일: 확인 필요',
          style: ts(9.0, bold: true, color: PdfColor.fromHex('#D32F2F')),
        ));
      }
    } else if (d.wageStatus == AttendanceModel.wageConfirmed &&
        d.scheduledPaymentDate != null) {
      dateRows.add(pw.Text(
        '지급 예정일: ${FormatHelper.formatDateDot(d.scheduledPaymentDate!)}',
        style: ts(9.0, color: grey),
      ));
    }

    dateRows.add(pw.Text(
      '근무일: ${FormatHelper.formatDateDot(d.workDate)}',
      style: ts(9.0, color: grey),
    ));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // 제목 줄
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text('임금명세서',
                style: ts(16.0, bold: true, color: primary)),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: dateRows,
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Divider(color: primary, thickness: 2.0),
        // 법적 근거
        pw.Text(
          '근로기준법 제48조 제2항에 따라 임금의 구성항목·계산방법·공제내역을 명시합니다.',
          style: ts(7.0, color: grey),
        ),
      ],
    );
  }

  // ─── 기본 정보 (식별 정보 최소화) ──────────────────────────────
  // 기존 4-column PartyInfo Table 대체.
  // 임금명세서 식별에 필요한 최소 항목만 표시.
  static pw.Widget _buildInfoBlock(PayslipData d, Function ts) {
    final labelColor = PdfColor.fromHex('#616161');
    final rows = <pw.TableRow>[];

    void addRow(String label, String value) {
      rows.add(pw.TableRow(children: [
        _cell(label, ts, bold: true, color: labelColor, fontSize: 9.0),
        _cell(value, ts, fontSize: 9.0),
      ]));
    }

    addRow('사업장명', d.businessName);
    addRow('근로자', d.workerName);
    if (d.workerBirthDate.isNotEmpty) {
      addRow('생년월일', d.workerBirthDate);
    }
    addRow('업무 유형', d.workType);
    addRow('임금 형태', d.wageDetail.wageType == 'hourly' ? '시급제' : '일급제');
    if (d.businessNumber.isNotEmpty) {
      addRow('사업자번호', d.businessNumber);
    }

    return pw.Table(
      border: pw.TableBorder.all(
          color: PdfColor.fromHex('#E0E0E0'), width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(65),
        1: const pw.FlexColumnWidth(1),
      },
      children: rows,
    );
  }

  // ─── 근무 시간 ─────────────────────────────────────────────────
  // 기존 4-column "구분|시간|구분|시간" 구조 → 2-column label/value.
  // 연장/야간은 0분이면 행 숨김.
  static pw.Widget _buildWorkTimeSection(
    PayslipData d,
    WageDetailModel wd,
    Function ts,
    PdfColor primary,
    PdfColor grey,
    PdfColor black,
  ) {
    final labelColor = PdfColor.fromHex('#616161');
    final rows = <pw.TableRow>[];

    void addRow(String label, String value) {
      rows.add(pw.TableRow(children: [
        _cell(label, ts, bold: true, color: labelColor, fontSize: 9.0),
        _cell(value, ts, fontSize: 9.0),
      ]));
    }

    addRow('출근', d.checkIn ?? '-');
    addRow('퇴근', d.checkOut ?? '-');
    addRow('실근무', _fmtMin(wd.workMinutes));
    addRow('휴게', _fmtMin(wd.breakMinutes));
    // 연장 근무 — canonical 분기
    if (wd.hasCanonicalExtraWorkBreakdown && (wd.contractExcessMinutes ?? 0) > 0) {
      // CANONICAL PATH: 전체 초과 + 세부 breakdown
      addRow('연장 근무', _fmtMin(wd.contractExcessMinutes!));
      if (wd.extraWork1xMinutes > 0) {
        addRow('계약시간 초과 (1배)', _fmtMin(wd.extraWork1xMinutes));
      }
      if (wd.extraWork15xMinutes > 0) {
        addRow('8시간 초과 (1.5배)', _fmtMin(wd.extraWork15xMinutes));
      }
    } else if (wd.overtimeMinutes > 0) {
      // LEGACY PATH
      addRow('연장 근무', _fmtMin(wd.overtimeMinutes));
    }
    if (wd.nightMinutes > 0) {
      addRow('야간수당', _fmtMin(wd.nightMinutes));
    }

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('근무 시간', ts, primary),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(
              color: PdfColor.fromHex('#E0E0E0'), width: 0.5),
          columnWidths: {
            0: const pw.FixedColumnWidth(65),
            1: const pw.FlexColumnWidth(1),
          },
          children: rows,
        ),
      ],
    );
  }

  // ─── 지급 내역 ────────────────────────────────────────────────
  static pw.Widget _buildPaySection(
    WageDetailModel wd,
    Function ts,
    PdfColor primary,
    PdfColor grey,
    PdfColor black,
  ) {
    final wageLabel = wd.wageType == 'hourly' ? '시급' : '일급';
    final rows = <pw.TableRow>[];

    // 헤더 — 연한 파란 배경 (그레이스케일에서도 헤더 구분 가능한 F0F4FF)
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F0F4FF')),
      children: [
        _cell('지급 항목', ts, bold: true, color: primary, fontSize: 9.0),
        _cell('금액', ts, bold: true, color: primary, align: pw.Alignment.centerRight, fontSize: 9.0),
        _cell('비고', ts, bold: true, color: primary, fontSize: 9.0),
      ],
    ));

    // 기본급
    rows.add(_payRow(
      '기본급 ($wageLabel ${_fmtWon(wd.baseWage)})',
      _fmtWon(wd.baseAmount),
      // [Q-02 fix] overtimeMinutes >= workMinutes 시 음수가 되어 '- 근무' 표시되는 것 방지
      '${_fmtMin((wd.workMinutes - wd.overtimeMinutes).clamp(0, wd.workMinutes))} 근무',
      ts,
      fontSize: 9.0,
    ));

    // 연장 근무수당 — canonical 분기
    if (wd.hasCanonicalExtraWorkBreakdown && (wd.contractExcessMinutes ?? 0) > 0) {
      // CANONICAL PATH: 세부 시간 breakdown만 표시
      // overtimeAmount는 HOURLY/DAILY mixed semantic이므로 "연장 근무수당 전체"로 오해되는
      // 단일 합계 행 표시 금지. 시간 breakdown이 상세 내역을 대체함.
      if (wd.extraWork1xMinutes > 0) {
        rows.add(_payRow(
          '계약시간 초과 (1배)',
          '',
          _fmtMin(wd.extraWork1xMinutes),
          ts,
          fontSize: 9.0,
        ));
      }
      if (wd.extraWork15xMinutes > 0) {
        rows.add(_payRow(
          '8시간 초과 (1.5배)',
          '',
          _fmtMin(wd.extraWork15xMinutes),
          ts,
          fontSize: 9.0,
        ));
      }
    } else if (wd.overtimeMinutes > 0) {
      // LEGACY PATH
      rows.add(_payRow(
        '연장 근무수당',
        _fmtWon(wd.overtimeAmount),
        _fmtMin(wd.overtimeMinutes),
        ts,
        fontSize: 9.0,
      ));
    }

    // 야간수당
    if (wd.nightAmount > 0) {
      rows.add(_payRow(
        '야간수당',
        _fmtWon(wd.nightAmount),
        _fmtMin(wd.nightMinutes),
        ts,
        fontSize: 9.0,
      ));
    }

    // 주휴수당
    if (wd.weeklyHolidayAmount > 0) {
      rows.add(_payRow(
        '주휴수당',
        _fmtWon(wd.weeklyHolidayAmount),
        '주 소정근로 개근',
        ts,
        fontSize: 9.0,
      ));
    }

    // 추가수당
    if (wd.additionalAmount > 0) {
      rows.add(_payRow(
        '추가수당',
        _fmtWon(wd.additionalAmount),
        wd.memo ?? '',
        ts,
        fontSize: 9.0,
      ));
    }

    // 추가공제 (앱 UI 표현 제거 → 공식 문서 표현으로)
    if (wd.deductionAmount > 0) {
      rows.add(_payRow(
        '추가공제',
        '-${_fmtWon(wd.deductionAmount)}',
        wd.memo ?? '',
        ts,
        isDeduction: true,
        fontSize: 9.0,
      ));
    }

    // 지급 합계 (기존: 세전 총액)
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F5F5F5')),
      children: [
        _cell('지급 합계', ts, bold: true, fontSize: 9.0),
        _cell(_fmtWon(wd.totalAmount), ts,
            bold: true, align: pw.Alignment.centerRight, fontSize: 9.0),
        _cell('', ts, fontSize: 9.0),
      ],
    ));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('지급 내역', ts, primary),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(
              color: PdfColor.fromHex('#E0E0E0'), width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(2),
          },
          children: rows,
        ),
      ],
    );
  }

  // ─── 계산 기준 섹션 ────────────────────────────────────────────
  // buildWageCalculationLines()가 반환한 문자열 목록을 PDF 블록으로 렌더링.
  // 기존 7.5pt grey → 8.5pt dark grey, accent container 스타일로 강화.
  // 호출자는 lines.isNotEmpty를 확인한 뒤 호출해야 한다.
  static pw.Widget _buildCalculationSection(
    List<String> lines,
    Function ts,
    PdfColor primary,
    PdfColor grey,
    PdfColor black,
  ) {
    final textColor = PdfColor.fromHex('#424242');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle('계산 기준', ts, primary),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.fromLTRB(10, 6, 10, 8),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromHex('#FAFAFA'),
            border: pw.Border.all(
              color: PdfColor.fromHex('#E0E0E0'),
              width: 0.5,
            ),
          ),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: lines
                .map(
                  (line) => pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 3),
                    child: pw.Text(
                      '·  $line',
                      style: ts(9.0, color: textColor),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }

  // ─── 공제 내역 ────────────────────────────────────────────────
  // 기존 주황색(#FFF3E0/#E65100) 경고 스타일 → 중립 grey 헤더 + primary 텍스트.
  // 공제는 오류가 아니므로 경보 UI 제거.
  static pw.Widget _buildDeductionSection(
    WageDetailModel wd,
    Function ts,
    PdfColor primary,
    PdfColor grey,
    PdfColor black,
  ) {
    final rows = <pw.TableRow>[];

    // 헤더 — 중립 grey 배경, primary 텍스트
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F5F5F5')),
      children: [
        _cell('공제 항목', ts, bold: true, color: primary, fontSize: 9.0),
        _cell('금액', ts, bold: true, color: primary,
            align: pw.Alignment.centerRight, fontSize: 9.0),
        _cell('비고', ts, bold: true, color: primary, fontSize: 9.0),
      ],
    ));

    if (wd.nationalPensionDeduction > 0) {
      rows.add(_payRow('국민연금', _fmtWon(wd.nationalPensionDeduction),
          '근로자 부담분', ts,
          isDeduction: true, fontSize: 9.0));
    }
    if (wd.healthInsuranceDeduction > 0) {
      rows.add(_payRow('건강보험', _fmtWon(wd.healthInsuranceDeduction),
          '근로자 부담분', ts,
          isDeduction: true, fontSize: 9.0));
    }
    if (wd.ltcInsuranceDeduction > 0) {
      rows.add(_payRow('장기요양보험', _fmtWon(wd.ltcInsuranceDeduction),
          '건강보험료 기준', ts,
          isDeduction: true, fontSize: 9.0));
    }
    if (wd.employmentInsuranceDeduction > 0) {
      rows.add(_payRow('고용보험', _fmtWon(wd.employmentInsuranceDeduction),
          '근로자 부담분', ts,
          isDeduction: true, fontSize: 9.0));
    }
    if (wd.incomeTaxDeduction > 0) {
      final taxLabel = wd.taxDeductionType == InsuranceRateModel.typeFreelancer33
          ? '사업소득세 3.3%'
          : '근로소득세·지방소득세';
      rows.add(_payRow(taxLabel, _fmtWon(wd.incomeTaxDeduction), '', ts,
          isDeduction: true, fontSize: 9.0));
    }
    if (wd.retroactiveDeduction > 0) {
      rows.add(_payRow('8일 소급 공제', _fmtWon(wd.retroactiveDeduction),
          '1~7일분 합산 공제', ts,
          isDeduction: true, fontSize: 9.0));
    }

    // 공제 합계 (기존: 총 공제액)
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F5F5F5')),
      children: [
        _cell('공제 합계', ts, bold: true, fontSize: 9.0),
        _cell(_fmtWon(wd.totalInsuranceDeduction), ts,
            bold: true, align: pw.Alignment.centerRight, fontSize: 9.0),
        _cell('', ts, fontSize: 9.0),
      ],
    ));

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _sectionTitle(
            '공제 내역 (${InsuranceRateModel.typeLabel(wd.taxDeductionType)})',
            ts, primary),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(
              color: PdfColor.fromHex('#E0E0E0'), width: 0.5),
          columnWidths: {
            0: const pw.FlexColumnWidth(3),
            1: const pw.FlexColumnWidth(2),
            2: const pw.FlexColumnWidth(2),
          },
          children: rows,
        ),
      ],
    );
  }

  // ─── 실수령액 박스 ───────────────────────────────────────────────
  // 금액 17pt Bold — 문서의 핵심 결과값으로 충분한 emphasis.
  // 배경 #E3F2FD (연한 파란) 유지 — 앱 카드 같은 full primary 배경 미사용.
  static pw.Widget _buildNetWageBox(
    WageDetailModel wd,
    Function ts,
    PdfColor primary,
  ) {
    final net = wd.effectiveNetWage;
    final metaGrey = PdfColor.fromHex('#9E9E9E');

    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#E3F2FD'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: primary, width: 1.5),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('실수령액', style: ts(11.0, bold: true, color: primary)),
              pw.SizedBox(height: 2),
              pw.Text('세후 지급액', style: ts(7.5, color: metaGrey)),
            ],
          ),
          pw.Text(_fmtWon(net), style: ts(18.0, bold: true, color: primary)),
        ],
      ),
    );
  }

  // ─── 법적 고지 (compact) ─────────────────────────────────────
  // 헤더에 이미 "근로기준법 제48조 제2항" 1줄이 있으므로 반복 최소화.
  // 박스/테두리 제거 — 인라인 supporting text 수준으로 축소.
  static pw.Widget _buildLegalNote(Function ts, PdfColor grey) {
    return pw.Text(
      '※ 공제내역은 국민연금법·건강보험법·고용보험법·소득세법에 근거합니다.'
      '   이의사항은 사업장 관리자 또는 관할 고용노동지청에 문의하시기 바랍니다.',
      style: ts(6.5, color: grey),
    );
  }

  // ─── 푸터 ────────────────────────────────────────────────────
  // 1페이지 문서: 푸터 완전 생략 (브랜드 텍스트·페이지 번호 불필요).
  // 멀티페이지: 우측 페이지 번호만 표시. 브랜드 텍스트 제거.
  static pw.Widget _buildFooter(
    pw.Context ctx,
    Function ts,
    PdfColor grey,
  ) {
    if (ctx.pagesCount <= 1) return pw.SizedBox();
    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Text(
        '${ctx.pageNumber} / ${ctx.pagesCount}',
        style: ts(7.0, color: grey),
      ),
    );
  }

  // ─── 헬퍼 ────────────────────────────────────────────────────

  // 섹션 타이틀 — "■" 기호 제거, 좌측 accent bar로 통일.
  // 단일 임금명세서 전용. 집계 PDF는 별도 inline 텍스트 사용.
  // 10pt 텍스트 기준으로 accent bar 16px로 비례 조정.
  static pw.Widget _sectionTitle(
      String title, Function ts, PdfColor primary) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(width: 3, height: 16, color: primary),
        pw.SizedBox(width: 6),
        pw.Text(title, style: ts(10.0, bold: true, color: primary)),
      ],
    );
  }

  // 집계 PDF에서 공유 사용 — 변경 금지
  static pw.TableRow _tableRow2Col(
    String k1, String v1,
    String k2, String v2,
    Function ts,
  ) {
    return pw.TableRow(children: [
      _cell(k1, ts, bold: true, color: PdfColor.fromHex('#757575')),
      _cell(v1, ts),
      _cell(k2, ts, bold: true, color: PdfColor.fromHex('#757575')),
      _cell(v2, ts),
    ]);
  }

  // isDeduction: 금액(amount)만 semantic red (#C62828).
  // 레이블은 항상 black — 공제 행 전체를 빨간색으로 만들지 않는다.
  // 집계 PDF에서도 공유 사용 — fontSize 기본값 8.0으로 집계 PDF 외관 보존.
  // 단일 명세서에서는 fontSize: 9.0 전달.
  static pw.TableRow _payRow(
    String label,
    String amount,
    String note,
    Function ts, {
    bool isDeduction = false,
    double fontSize = 8.0,
  }) {
    final amountColor =
        isDeduction ? PdfColor.fromHex('#C62828') : PdfColors.black;
    return pw.TableRow(children: [
      _cell(label, ts, color: PdfColors.black, fontSize: fontSize),
      _cell(amount, ts, align: pw.Alignment.centerRight, color: amountColor, fontSize: fontSize),
      _cell(note, ts, color: PdfColor.fromHex('#424242'), fontSize: fontSize),
    ]);
  }

  // fontSize 기본값 8.0 → 집계 PDF 호출부는 변경 불필요
  // 단일 임금명세서 섹션에서는 fontSize: 9.0 명시 전달
  static pw.Widget _cell(
    String text,
    Function ts, {
    bool bold = false,
    PdfColor? color,
    pw.Alignment align = pw.Alignment.centerLeft,
    double fontSize = 8.0,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      alignment: align,
      child: pw.Text(
        text,
        style: ts(fontSize, bold: bold, color: color ?? PdfColors.black),
      ),
    );
  }

  static String _fmtWon(int amount) {
    // [Q-01 fix] 0원은 '-'가 아닌 '0원'으로 표시 — 실수령액 0인 경우 법적 명세 명확성 확보
    if (amount == 0) return '0원';
    final abs = amount.abs();
    final formatted = abs.toString().replaceAllMapped(
      _commaRe, // [PERF-9] static 캐시 사용
      (m) => '${m[1]},',
    );
    return amount < 0 ? '-$formatted원' : '$formatted원';
  }

  static String _fmtMin(int minutes) {
    if (minutes <= 0) return '-';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    if (h == 0) return '$m분';
    if (m == 0) return '$h시간';
    return '$h시간 $m분';
  }

  // ══════════════════════════════════════════════════════════════
  // 집계 임금명세서 (월간 / 주간)
  // ══════════════════════════════════════════════════════════════

  /// 월간·주간 임금명세서 PDF 생성
  /// 1페이지: 집계 요약, 2페이지: 일별 상세 테이블
  static Future<Uint8List> buildAggregated(AggregatedPayslipData data) async {
    // ── 폰트 로드 (캐시 사용) ──────────────────────────────────
    final (fontR, fontB) = await loadFonts();

    pw.TextStyle ts(double size, {bool bold = false, PdfColor? color}) =>
        pw.TextStyle(font: bold ? fontB : fontR, fontSize: size, color: color);

    final primary = PdfColor.fromHex('#1565C0');
    final grey    = PdfColor.fromHex('#9E9E9E');

    final doc = pw.Document();

    // ── 1페이지: 합산 요약 ────────────────────────────────────────
    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
        footer: (ctx) => _aggFooter(ctx, ts, grey),
        build: (ctx) => [
          _aggHeader(data, ts, primary, grey),
          pw.SizedBox(height: 14),
          _aggPartyInfo(data, ts, grey),
          pw.SizedBox(height: 12),
          _aggWorkSummary(data, ts, primary, grey),
          pw.SizedBox(height: 12),
          _aggPaySection(data, ts, primary, grey),
          pw.SizedBox(height: 12),
          if (data.hasDeductions) ...[
            _aggDeductionSection(data, ts, primary, grey),
            pw.SizedBox(height: 12),
          ],
          _aggNetWageBox(data, ts, primary),

          if (data.hasMemos) ...[
            pw.SizedBox(height: 12),
            _aggMemoSection(data, ts, primary, grey),
          ],

          pw.SizedBox(height: 14),
          _aggLegalNote(ts, grey),
        ],
      ),
    );

    // ── 2페이지: 일별 상세 테이블 ─────────────────────────────────
    if (data.dailyRecords.isNotEmpty) {
      doc.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.fromLTRB(36, 36, 36, 40),
          footer: (ctx) => _aggFooter(ctx, ts, grey),
          build: (ctx) => [
            pw.Text('일별 근무 상세', style: ts(11.0, bold: true, color: primary)),
            pw.SizedBox(height: 4),
            pw.Text(
              '${data.periodTitle} — 총 ${data.totalWorkDays}일 근무',
              style: ts(8.0, color: grey),
            ),
            pw.SizedBox(height: 8),
            _aggDailyTable(data, ts, primary, grey),
          ],
        ),
      );
    }

    return doc.save();
  }

  // ─── 1페이지 섹션들 ───────────────────────────────────────────

  static pw.Widget _aggHeader(
    AggregatedPayslipData d, Function ts, PdfColor primary, PdfColor grey) {
    final payDate = d.paymentDate != null
        ? FormatHelper.formatDateDot(d.paymentDate!)
        : '${d.year}.${d.month.toString().padLeft(2, '0')}';

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(d.issueType == PayslipIssueType.weekly
              ? '주간 임금명세서'
              : '월간 임금명세서',
              style: ts(18.0, bold: true, color: primary)),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
            pw.Text('지급일: $payDate', style: ts(8.0, color: grey)),
            pw.Text(
                '기간: ${FormatHelper.formatDateDot(d.periodStart)} ~ ${FormatHelper.formatDateDot(d.periodEnd)}',
                style: ts(8.0, color: grey)),
          ]),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Divider(color: primary, thickness: 1.5),
      pw.Text(
        '근로기준법 제48조 제2항에 따라 임금의 구성항목·계산방법·공제내역을 명시합니다.',
        style: ts(7.0, color: grey),
      ),
    ]);
  }

  static pw.Widget _aggPartyInfo(
      AggregatedPayslipData d, Function ts, PdfColor grey) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColor.fromHex('#E0E0E0'), width: 0.5),
      columnWidths: {
        0: const pw.FixedColumnWidth(80),
        1: const pw.FlexColumnWidth(2),
        2: const pw.FixedColumnWidth(80),
        3: const pw.FlexColumnWidth(2),
      },
      children: [
        _tableRow2Col('사업장명', d.businessName, '근무자', d.workerName, ts),
        if (d.businessNumber.isNotEmpty || d.workerBirthDate.isNotEmpty)
          _tableRow2Col(
              '사업자번호', d.businessNumber.isNotEmpty ? d.businessNumber : '-',
              '생년월일', d.workerBirthDate.isNotEmpty ? d.workerBirthDate : '-',
              ts),
        _tableRow2Col(
            '발행 유형', d.issueType.label,
            '대상 기간', d.periodTitle.replaceAll(' 임금명세서', ''),
            ts),
      ],
    );
  }

  static pw.Widget _aggWorkSummary(
      AggregatedPayslipData d, Function ts, PdfColor primary, PdfColor grey) {
    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('■  근무 현황', style: ts(9.0, bold: true, color: primary)),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColor.fromHex('#E0E0E0'), width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(1), 1: pw.FlexColumnWidth(1),
          2: pw.FlexColumnWidth(1), 3: pw.FlexColumnWidth(1),
        },
        children: [
          pw.TableRow(
            decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F5F5F5')),
            children: [
              _cell('구분', ts, bold: true, color: grey),
              _cell('수치', ts, bold: true, color: grey),
              _cell('구분', ts, bold: true, color: grey),
              _cell('수치', ts, bold: true, color: grey),
            ],
          ),
          pw.TableRow(children: [
            _cell('근무일수', ts), _cell('${d.totalWorkDays}일', ts),
            _cell('총 근무시간', ts), _cell(_fmtMin(d.totalWorkMinutes), ts),
          ]),
          pw.TableRow(children: [
            _cell('연장 근무', ts), _cell(_fmtMin(d.totalOvertimeMinutes), ts),
            _cell('야간수당', ts), _cell(_fmtMin(d.totalNightMinutes), ts),
          ]),
        ],
      ),
    ]);
  }

  static pw.Widget _aggPaySection(
      AggregatedPayslipData d, Function ts, PdfColor primary, PdfColor grey) {
    final rows = <pw.TableRow>[];
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E3F2FD')),
      children: [
        _cell('지급 항목', ts, bold: true, color: primary),
        _cell('금액', ts, bold: true, color: primary, align: pw.Alignment.centerRight),
        _cell('비고', ts, bold: true, color: primary),
      ],
    ));

    rows.add(_payRow('기본급', _fmtWon(d.totalBaseAmount), '${d.totalWorkDays}일', ts));
    if (d.totalOvertimeAmount > 0) {
      rows.add(_payRow('연장 근무수당', _fmtWon(d.totalOvertimeAmount), _fmtMin(d.totalOvertimeMinutes), ts));
    }
    if (d.totalNightAmount > 0) {
      rows.add(_payRow('야간수당', _fmtWon(d.totalNightAmount), _fmtMin(d.totalNightMinutes), ts));
    }
    if (d.totalWeeklyHolidayAmount > 0) {
      rows.add(_payRow('주휴수당', _fmtWon(d.totalWeeklyHolidayAmount), '', ts));
    }
    if (d.totalAdditionalAmount > 0) {
      rows.add(_payRow('추가수당', _fmtWon(d.totalAdditionalAmount), '', ts));
    }
    if (d.totalDeductionAmount > 0) {
      rows.add(_payRow('▼ 추가공제', '-${_fmtWon(d.totalDeductionAmount)}', '', ts, isDeduction: true));
    }
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F5F5F5')),
      children: [
        _cell('세전 총액', ts, bold: true),
        _cell(_fmtWon(d.totalGrossAmount), ts, bold: true, align: pw.Alignment.centerRight),
        _cell('', ts),
      ],
    ));

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('■  지급 내역', style: ts(9.0, bold: true, color: primary)),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColor.fromHex('#E0E0E0'), width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(2),
        },
        children: rows,
      ),
    ]);
  }

  static pw.Widget _aggDeductionSection(
      AggregatedPayslipData d, Function ts, PdfColor primary, PdfColor grey) {
    final rows = <pw.TableRow>[];
    final deductColor = PdfColor.fromHex('#E65100');
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#FFF3E0')),
      children: [
        _cell('공제 항목', ts, bold: true, color: deductColor),
        _cell('금액', ts, bold: true, color: deductColor, align: pw.Alignment.centerRight),
        _cell('비고', ts, bold: true, color: deductColor),
      ],
    ));

    if (d.totalNationalPension > 0) {
      rows.add(_payRow('국민연금', _fmtWon(d.totalNationalPension), '근로자 부담분', ts, isDeduction: true));
    }
    if (d.totalHealthInsurance > 0) {
      rows.add(_payRow('건강보험', _fmtWon(d.totalHealthInsurance), '근로자 부담분', ts, isDeduction: true));
    }
    if (d.totalLtcInsurance > 0) {
      rows.add(_payRow('장기요양보험', _fmtWon(d.totalLtcInsurance), '', ts, isDeduction: true));
    }
    if (d.totalEmploymentInsurance > 0) {
      rows.add(_payRow('고용보험', _fmtWon(d.totalEmploymentInsurance), '근로자 부담분', ts, isDeduction: true));
    }
    if (d.totalIncomeTax > 0) {
      // taxDeductionTypeLabel 직접 비교 (contains 대신 정확한 라벨 사용)
      final incomeTaxLabel = d.taxDeductionTypeLabel == '3.3% 원천징수'
          ? '사업소득세 3.3%'
          : d.taxDeductionTypeLabel.isNotEmpty && d.taxDeductionTypeLabel != '세금 없음'
              ? d.taxDeductionTypeLabel
              : '근로소득세·지방소득세';
      rows.add(_payRow(incomeTaxLabel, _fmtWon(d.totalIncomeTax), '', ts, isDeduction: true));
    }
    if (d.totalRetroactiveDeduction > 0) {
      rows.add(_payRow('8일 소급 공제', _fmtWon(d.totalRetroactiveDeduction), '1~7일분 합산', ts, isDeduction: true));
    }
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F5F5F5')),
      children: [
        _cell('총 공제액', ts, bold: true),
        _cell(_fmtWon(d.totalInsuranceDeduction), ts, bold: true, align: pw.Alignment.centerRight),
        _cell('', ts),
      ],
    ));

    return pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
      pw.Text('■  공제 내역', style: ts(9.0, bold: true, color: primary)),
      pw.SizedBox(height: 4),
      pw.Table(
        border: pw.TableBorder.all(color: PdfColor.fromHex('#E0E0E0'), width: 0.5),
        columnWidths: const {
          0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(2), 2: pw.FlexColumnWidth(2),
        },
        children: rows,
      ),
    ]);
  }

  static pw.Widget _aggNetWageBox(
      AggregatedPayslipData d, Function ts, PdfColor primary) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#E3F2FD'),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
        border: pw.Border.all(color: primary, width: 1),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text('실수령액 (세후)', style: ts(11.0, bold: true, color: primary)),
          pw.Text(_fmtWon(d.totalNetWage), style: ts(14.0, bold: true, color: primary)),
        ],
      ),
    );
  }

  static pw.Widget _aggLegalNote(Function ts, PdfColor grey) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#FAFAFA'),
        border: pw.Border.all(color: PdfColor.fromHex('#E0E0E0'), width: 0.5),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
      ),
      child: pw.Text(
        '※ 본 임금명세서는 근로기준법 제48조 제2항에 따라 교부됩니다.\n'
        '※ 공제내역은 국민연금법, 국민건강보험법, 고용보험법, 소득세법에 근거합니다.\n'
        '※ 이의사항은 사업장 관리자 또는 관할 고용노동지청에 문의하시기 바랍니다.',
        style: ts(6.5, color: grey),
      ),
    );
  }

  // ─── 1페이지: 특이사항 섹션 ──────────────────────────────────

  static pw.Widget _aggMemoSection(
      AggregatedPayslipData d, Function ts, PdfColor primary, PdfColor grey) {
    final amber = PdfColor.fromHex('#F59E0B');
    final amberBg = PdfColor.fromHex('#FFFBEB');
    final amberBorder = PdfColor.fromHex('#FCD34D');

    final lines = d.memoRecords.map((r) {
      final dateStr = '${r.workDate.month}/${r.workDate.day}';
      return '$dateStr  —  ${r.memo}';
    }).join('\n');

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text('■  특이사항', style: ts(9.0, bold: true, color: amber)),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: amberBg,
            border: pw.Border.all(color: amberBorder, width: 0.5),
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(4)),
          ),
          child: pw.Text(lines, style: ts(8.0)),
        ),
      ],
    );
  }

  // ─── 2페이지: 일별 상세 테이블 ────────────────────────────────

  static pw.Widget _aggDailyTable(
      AggregatedPayslipData d, Function ts, PdfColor primary, PdfColor grey) {
    final rows = <pw.TableRow>[];
    final hasMemos = d.hasMemos;

    // 헤더
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E3F2FD')),
      children: [
        _cell('날짜', ts, bold: true, color: primary),
        _cell('출근', ts, bold: true, color: primary),
        _cell('퇴근', ts, bold: true, color: primary),
        _cell('실근무', ts, bold: true, color: primary),
        _cell('연장', ts, bold: true, color: primary),
        _cell('야간', ts, bold: true, color: primary),
        _cell('실수령', ts, bold: true, color: primary, align: pw.Alignment.centerRight),
        if (hasMemos) _cell('특이사항', ts, bold: true, color: primary),
      ],
    ));

    for (final r in d.dailyRecords) {
      final dateStr = '${r.workDate.month}/${r.workDate.day}';
      rows.add(pw.TableRow(children: [
        _cell(dateStr, ts),
        _cell(r.checkIn ?? '-', ts),
        _cell(r.checkOut ?? '-', ts),
        _cell(_fmtMin(r.workMinutes), ts),
        _cell(_fmtMin(r.overtimeMinutes), ts),
        _cell(_fmtMin(r.nightMinutes), ts),
        _cell(_fmtWon(r.netWage), ts, align: pw.Alignment.centerRight),
        if (hasMemos) _cell(r.memo ?? '', ts, color: PdfColor.fromHex('#424242')),
      ]));
    }

    // 합계 행
    rows.add(pw.TableRow(
      decoration: pw.BoxDecoration(color: PdfColor.fromHex('#F5F5F5')),
      children: [
        _cell('합계', ts, bold: true),
        _cell('', ts),
        _cell('', ts),
        _cell(_fmtMin(d.totalWorkMinutes), ts, bold: true),
        _cell(_fmtMin(d.totalOvertimeMinutes), ts, bold: true),
        _cell(_fmtMin(d.totalNightMinutes), ts, bold: true),
        _cell(_fmtWon(d.totalNetWage), ts, bold: true, align: pw.Alignment.centerRight),
        if (hasMemos) _cell('', ts),
      ],
    ));

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColor.fromHex('#E0E0E0'), width: 0.5),
      columnWidths: hasMemos
          ? const {
              0: pw.FixedColumnWidth(35),
              1: pw.FixedColumnWidth(40),
              2: pw.FixedColumnWidth(40),
              3: pw.FixedColumnWidth(45),
              4: pw.FixedColumnWidth(35),
              5: pw.FixedColumnWidth(35),
              6: pw.FlexColumnWidth(1),
              7: pw.FlexColumnWidth(2),
            }
          : const {
              0: pw.FixedColumnWidth(40),
              1: pw.FixedColumnWidth(45),
              2: pw.FixedColumnWidth(45),
              3: pw.FixedColumnWidth(50),
              4: pw.FixedColumnWidth(40),
              5: pw.FixedColumnWidth(40),
              6: pw.FlexColumnWidth(1),
            },
      children: rows,
    );
  }

  static pw.Widget _aggFooter(pw.Context ctx, Function ts, PdfColor grey) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text('AlFit 임금명세서', style: ts(7.0, color: grey)),
        pw.Text('${ctx.pageNumber} / ${ctx.pagesCount}', style: ts(7.0, color: grey)),
      ],
    );
  }
}
