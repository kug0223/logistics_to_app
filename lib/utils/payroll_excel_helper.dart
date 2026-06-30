// lib/utils/payroll_excel_helper.dart
//
// 이체용 엑셀(.xlsx) 생성 + 공유 공통 유틸리티
// payroll_payment_dashboard_screen, today_payment_screen 등에서 공용 사용

import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/payroll_payment_service.dart';
import '../services/firestore_service.dart';
import '../models/core/attendance_model.dart';
import 'toast_helper.dart';

class PayrollExcelHelper {
  /// 이체 목록 엑셀 생성 후 공유 시트 열기
  ///
  /// [records]   이체 대상 출근 기록
  /// [title]     엑셀 제목 행에 표시할 텍스트 (예: "신세계푸드 평택 5월 이체목록")
  /// [filename]  저장 파일명 (.xlsx 포함)
  static Future<void> exportAndShare({
    required BuildContext context,
    required List<AttendanceModel> records,
    required String title,
    required String filename,
    required String businessId,  // SEC-22: CF 프록시를 위해 필수
  }) async {
    if (records.isEmpty) {
      ToastHelper.showWarning('이체 내역이 없습니다');
      return;
    }

    // SEC-22: CF callableGetUsersBatch를 통해 조회 — 극도 민감 필드(ci/주민번호 등) 서버 필터링
    final fsService = FirestoreService();
    final bankInfo = <String, Map<String, String>>{};
    final uidList = records.map((r) => r.userId).toSet().toList();

    final userMap = await fsService.getUsersBatch(uidList, businessId: businessId);
    int missingCount = 0;
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
      ToastHelper.showWarning('$missingCount명의 계좌 정보를 불러오지 못했습니다. 해당 항목은 빈 칸으로 처리됩니다.');
    }

    final rows = buildTransferRows(records, bankInfo);
    if (rows.isEmpty) {
      if (context.mounted) ToastHelper.showWarning('이체 데이터가 없습니다');
      return;
    }

    // ── Excel 생성
    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final sheet = excel['이체목록'];

    sheet.setColumnWidth(0, 12);
    sheet.setColumnWidth(1, 14);
    sheet.setColumnWidth(2, 22);
    sheet.setColumnWidth(3, 12);
    sheet.setColumnWidth(4, 12);
    sheet.setColumnWidth(5, 32);

    // 제목 행
    _cell(sheet, 0, 0, title, bold: true, fontSize: 13);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: 0),
    );

    // 헤더 행
    const headers = ['이름', '은행명', '계좌번호', '예금주', '이체금액', '메모'];
    for (int c = 0; c < headers.length; c++) {
      _cell(sheet, 1, c, headers[c], bold: true, bgHex: 'FFD6E4F0');
    }

    // 데이터 행
    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      _cell(sheet, 2 + i, 0, r.workerName);
      _cell(sheet, 2 + i, 1, r.bankName);
      _cell(sheet, 2 + i, 2, r.accountNumber);
      _cell(sheet, 2 + i, 3, r.accountHolder);
      _cell(sheet, 2 + i, 4, r.netAmount.toString());
      _cell(sheet, 2 + i, 5, r.memo);
    }

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
}
