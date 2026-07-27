// lib/utils/payroll_excel_helper.dart
//
// 급여 엑셀(.xlsx) 생성 + 공유 유틸리티
//
// [미이체 탭]    exportTransferList  — 은행 이체 전용 단순 시트
// [이체현황 탭]  exportPayrollDetail — 회계/세무용 건별 상세 시트

import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/payroll_payment_service.dart';
import '../services/firestore_service.dart';
import '../models/core/attendance_model.dart';
import 'format_helper.dart';
import 'toast_helper.dart';

class PayrollExcelHelper {

  // ══════════════════════════════════════════════════════════
  // 미이체 탭 — 은행 이체 전용 시트
  // 컬럼: 이름 | 은행명 | 계좌번호 | 예금주 | 이체금액 | 메모
  // 행 단위: 근무자별 합산 1행
  // ══════════════════════════════════════════════════════════
  static Future<void> exportTransferList({
    required BuildContext context,
    required List<AttendanceModel> records,
    required String title,
    required String filename,
    required String businessId,
  }) async {
    if (records.isEmpty) {
      ToastHelper.showWarning('이체 대상이 없습니다');
      return;
    }

    final bankInfo = await _loadBankInfo(context, records, businessId);

    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    final rows = buildTransferRows(records, bankInfo);
    if (rows.isEmpty) {
      if (context.mounted) ToastHelper.showWarning('이체 가능한 계좌 정보가 없습니다');
      return;
    }

    final sheet = excel['이체목록'];
    _setColWidths(sheet, [12, 14, 22, 12, 12, 32]);

    // 제목 행
    _cell(sheet, 0, 0, title, bold: true, fontSize: 13);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 0),
    );

    // 헤더
    const headers = ['이름', '은행명', '계좌번호', '예금주', '이체금액', '메모'];
    for (int c = 0; c < headers.length; c++) {
      _cell(sheet, 1, c, headers[c], bold: true, bgHex: 'FFD6E4F0');
    }

    // 데이터
    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      _cell(sheet, 2 + i, 0, r.workerName);
      _cell(sheet, 2 + i, 1, r.bankName);
      _cell(sheet, 2 + i, 2, r.accountNumber);
      _cell(sheet, 2 + i, 3, r.accountHolder);
      _numCell(sheet, 2 + i, 4, r.netAmount);
      _cell(sheet, 2 + i, 5, r.memo);
    }

    // 합계 행
    final totalRow = 2 + rows.length;
    final total = rows.fold<int>(0, (a, r) => a + r.netAmount);
    _cell(sheet, totalRow, 3, '합계', bold: true, bgHex: 'FFEAF4FF');
    _numCell(sheet, totalRow, 4, total, bold: true, bgHex: 'FFEAF4FF');

    if (!context.mounted) return;
    await _shareExcel(context, excel, filename);
  }

  // ══════════════════════════════════════════════════════════
  // 이체현황 탭 — 회계/세무용 건별 상세 시트
  // 컬럼: 이름 | 사업장 | 급여형태 | 근무일 | 세전금액 |
  //        국민연금 | 건강보험 | 장기요양 | 고용보험 |
  //        세후금액 | 이체상태 | 이체일
  // 행 단위: 근무 건별 1행 + 합계 행
  // ══════════════════════════════════════════════════════════
  static Future<void> exportPayrollDetail({
    required BuildContext context,
    required List<AttendanceModel> records,
    required String title,
    required String filename,
    required String businessId,
  }) async {
    if (records.isEmpty) {
      ToastHelper.showWarning('내보낼 급여 내역이 없습니다');
      return;
    }

    final bankInfo = await _loadBankInfo(context, records, businessId);

    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    final sheet = excel['급여현황'];
    _setColWidths(sheet, [12, 16, 10, 12, 12, 10, 10, 10, 10, 12, 10, 14]);

    // 제목 행
    _cell(sheet, 0, 0, title, bold: true, fontSize: 13);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 11, rowIndex: 0),
    );

    // 헤더
    const headers = [
      '이름', '사업장', '급여형태', '근무일',
      '세전금액', '국민연금', '건강보험', '장기요양', '고용보험',
      '세후금액', '이체상태', '이체일',
    ];
    for (int c = 0; c < headers.length; c++) {
      _cell(sheet, 1, c, headers[c], bold: true, bgHex: 'FFD6F0E4');
    }

    // 데이터 (근무 건별 1행)
    // 이름 기준 오름차순, 같은 이름이면 근무일 오름차순
    final sorted = [...records]
      ..sort((a, b) {
        final na = bankInfo[a.userId]?['name'] ?? a.userId;
        final nb = bankInfo[b.userId]?['name'] ?? b.userId;
        final nc = na.compareTo(nb);
        return nc != 0 ? nc : a.workDate.compareTo(b.workDate);
      });

    // 합계 누산
    int sumGross = 0, sumPension = 0, sumHealth = 0;
    int sumLtc   = 0, sumEmploy  = 0, sumNet    = 0;

    for (int i = 0; i < sorted.length; i++) {
      final r   = sorted[i];
      final wd  = r.wageDetail;
      final b   = bankInfo[r.userId];
      final row = 2 + i;

      final gross    = wd?.totalAmount            ?? 0;
      final pension  = wd?.nationalPensionDeduction  ?? 0;
      final health   = wd?.healthInsuranceDeduction  ?? 0;
      final ltc      = wd?.ltcInsuranceDeduction     ?? 0;
      final employ   = wd?.employmentInsuranceDeduction ?? 0;
      final net      = wd?.effectiveNetWage          ?? 0;
      final isXfer   = r.wageStatus == AttendanceModel.wageTransferred;

      sumGross   += gross;
      sumPension += pension;
      sumHealth  += health;
      sumLtc     += ltc;
      sumEmploy  += employ;
      sumNet     += net;

      _cell(sheet, row, 0,  b?['name'] ?? r.userId);
      _cell(sheet, row, 1,  r.businessName);
      _cell(sheet, row, 2,  _payTypeLabel(wd?.payScheduleType));
      _cell(sheet, row, 3,  FormatHelper.formatDateDot(r.workDate));
      _numCell(sheet, row, 4, gross);
      if (pension > 0) _numCell(sheet, row, 5, pension);
      if (health  > 0) _numCell(sheet, row, 6, health);
      if (ltc     > 0) _numCell(sheet, row, 7, ltc);
      if (employ  > 0) _numCell(sheet, row, 8, employ);
      _numCell(sheet, row, 9, net);
      _cell(sheet, row, 10, isXfer ? '이체완료' : '미이체');
      _cell(sheet, row, 11,
          r.transferDate != null ? FormatHelper.formatDateDot(r.transferDate!) : '');
    }

    // 합계 행
    final totalRow = 2 + sorted.length;
    _cell(sheet, totalRow, 3,    '합계',    bold: true, bgHex: 'FFEAF4FF');
    _numCell(sheet, totalRow, 4, sumGross,  bold: true, bgHex: 'FFEAF4FF');
    if (sumPension > 0) _numCell(sheet, totalRow, 5, sumPension, bold: true, bgHex: 'FFEAF4FF');
    if (sumHealth  > 0) _numCell(sheet, totalRow, 6, sumHealth,  bold: true, bgHex: 'FFEAF4FF');
    if (sumLtc     > 0) _numCell(sheet, totalRow, 7, sumLtc,     bold: true, bgHex: 'FFEAF4FF');
    if (sumEmploy  > 0) _numCell(sheet, totalRow, 8, sumEmploy,  bold: true, bgHex: 'FFEAF4FF');
    _numCell(sheet, totalRow, 9, sumNet,    bold: true, bgHex: 'FFEAF4FF');

    if (!context.mounted) return;
    await _shareExcel(context, excel, filename);
  }

  // ── 공통 유틸 ───────────────────────────────────────────

  static Future<Map<String, Map<String, String>>> _loadBankInfo(
    BuildContext context,
    List<AttendanceModel> records,
    String businessId,
  ) async {
    final fsService = FirestoreService();
    final uidList   = records.map((r) => r.userId).toSet().toList();
    final userMap   = await fsService.getUsersBatch(uidList, businessId: businessId);

    int missingCount = 0;
    final bankInfo = <String, Map<String, String>>{};
    for (final uid in uidList) {
      final user = userMap[uid];
      if (user == null) { missingCount++; continue; }
      bankInfo[uid] = {
        'name':          user.name,
        'bankName':      user.bankName      ?? '',
        'accountNumber': user.accountNumber ?? '',
        'accountHolder': user.accountHolder ?? user.name,
      };
    }
    if (missingCount > 0 && context.mounted) {
      ToastHelper.showWarning('$missingCount명의 계좌 정보를 불러오지 못했습니다');
    }
    return bankInfo;
  }

  static Future<void> _shareExcel(
    BuildContext context,
    Excel excel,
    String filename,
  ) async {
    final bytes = excel.encode();
    if (bytes == null) {
      if (context.mounted) ToastHelper.showError('엑셀 생성에 실패했습니다');
      return;
    }
    if (!context.mounted) return;
    final dir  = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    try {
      await file.writeAsBytes(bytes);
      try {
        await Share.shareXFiles(
          [XFile(file.path,
              mimeType:
                  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
          subject: filename,
        );
      } finally {
        await file.delete();
      }
    } catch (e) {
      if (context.mounted) ToastHelper.showError('엑셀 내보내기에 실패했습니다');
    }
  }

  static void _setColWidths(Sheet sheet, List<double> widths) {
    for (int i = 0; i < widths.length; i++) {
      sheet.setColumnWidth(i, widths[i]);
    }
  }

  static void _cell(Sheet sheet, int row, int col, String text,
      {bool bold = false, int fontSize = 10, String? bgHex}) {
    final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = TextCellValue(text);
    cell.cellStyle = bgHex != null
        ? CellStyle(
            bold: bold,
            fontSize: fontSize,
            backgroundColorHex: ExcelColor.fromHexString('#$bgHex'),
          )
        : CellStyle(bold: bold, fontSize: fontSize);
  }

  static void _numCell(Sheet sheet, int row, int col, int value,
      {bool bold = false, int fontSize = 10, String? bgHex}) {
    final cell = sheet.cell(
        CellIndex.indexByColumnRow(columnIndex: col, rowIndex: row));
    cell.value = IntCellValue(value);
    cell.cellStyle = bgHex != null
        ? CellStyle(
            bold: bold,
            fontSize: fontSize,
            backgroundColorHex: ExcelColor.fromHexString('#$bgHex'),
          )
        : CellStyle(bold: bold, fontSize: fontSize);
  }

  static String _payTypeLabel(String? type) => switch (type) {
    'monthly'                  => '월급',
    'weekly'                   => '주급',
    'same_day' || 'next_day'   => '일급',
    _                          => '',
  };
}
