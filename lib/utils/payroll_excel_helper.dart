// lib/utils/payroll_excel_helper.dart
//
// 급여 엑셀(.xlsx) 생성 + 공유 유틸리티
//
// [미이체 탭]    exportTransferList  — 은행 이체 전용 단순 시트
// [이체현황 탭]  exportPayrollDetail — 회계/세무용 건별 상세 시트
//
// [PII-DOC-R0.1 / INV-2] 이체 시트의 계좌 출처는 **Attendance 스냅샷**이다.
//   `users/{uid}`의 현재 프로필이 아니다. 판정은 `transfer_export_plan.dart`에
//   모여 있고, 여기서는 이미 정해진 계획을 그린다.

import 'dart:io';
import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/firestore_service.dart';
import '../models/core/attendance_model.dart';
import 'encryption_helper.dart';
import 'format_helper.dart';
import 'toast_helper.dart';
import 'transfer_export_plan.dart';

class PayrollExcelHelper {

  // ══════════════════════════════════════════════════════════
  // 이체 계획 수립 — 파일을 만들기 **전에** 무엇이 나가고 무엇이 왜 빠지는지 정한다.
  // 화면이 이 계획을 먼저 보여주고, 사용자가 확인한 뒤에 파일이 만들어진다.
  // ══════════════════════════════════════════════════════════
  static Future<TransferExportPlan> prepareTransferPlan({
    required List<AttendanceModel> records,
    required String businessId,
  }) async {
    final p = await _loadWorkerProfiles(records, businessId);
    return buildTransferExportPlan(
      records: records,
      names: p.names,
      personNos: p.personNos,
      decrypt: EncryptionHelper.decrypt,
      formatDate: FormatHelper.formatDateDot,
    );
  }

  // ══════════════════════════════════════════════════════════
  // 미이체 탭 — 은행 이체 전용 시트
  // 컬럼: 이름 | 은행명 | 계좌번호 | 예금주 | 이체금액 | 메모
  // 행 단위: 근무자 × 확정 시점 계좌 합산 1행
  //
  // [INV-3] 파일에는 plan.rows만 들어간다. 화면이 말한 행 수와 같다.
  // ══════════════════════════════════════════════════════════
  static Future<void> exportTransferList({
    required BuildContext context,
    required TransferExportPlan plan,
    required String title,
    required String filename,
  }) async {
    final rows = plan.rows;
    if (rows.isEmpty) {
      ToastHelper.showWarning('엑셀에 포함할 이체 대상이 없습니다');
      return;
    }

    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    final sheet = excel['이체목록'];
    _setColWidths(sheet, [10, 12, 14, 22, 12, 12, 32]);

    // 제목 행
    _cell(sheet, 0, 0, title, bold: true, fontSize: 13);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: 0),
    );

    // 헤더
    // [R7-PRE1A.1] 근로자번호가 맨 앞이다. 이 파일은 은행·회계로 넘어가고,
    //   거기서는 "같은 이름이 둘인데 어느 쪽인가"를 물어볼 화면이 없다.
    //
    // 「이름」과 「예금주」는 **다른 사실**이다. 한쪽으로 통일하지 않는다.
    //   이름   = 지금 이 사람의 이름        (누구에게 주는가)
    //   예금주 = 급여 확정 시점 계좌의 명의  (어디로 보내는가)
    //   개명(본인인증 재인증)하면 둘이 달라질 수 있고, 그건 오류가 아니다.
    //   서버 어디에도 이 둘을 비교해 이체를 막는 로직은 없다 — 있어서도 안 된다.
    //   달라 보이는 이유를 운영자가 알 수 있게 **머리글에 적는다.**
    const headers = [
      '근로자번호', '이름(현재)', '은행명', '계좌번호', '예금주(확정 시점)',
      '이체금액', '메모',
    ];
    for (int c = 0; c < headers.length; c++) {
      _cell(sheet, 1, c, headers[c], bold: true, bgHex: 'FFD6E4F0');
    }

    // 데이터
    for (int i = 0; i < rows.length; i++) {
      final r = rows[i];
      _cell(sheet, 2 + i, 0, r.personNo ?? '');
      _cell(sheet, 2 + i, 1, r.workerName);
      _cell(sheet, 2 + i, 2, r.bankName);
      _cell(sheet, 2 + i, 3, r.accountNumber); // PAY-M3: TextCellValue가 수식 차단 보장 — _sanitizeField 불필요
      _cell(sheet, 2 + i, 4, r.accountHolder);
      _numCell(sheet, 2 + i, 5, r.netAmount);
      _cell(sheet, 2 + i, 6, r.memo);
    }

    // 합계 행
    final totalRow = 2 + rows.length;
    final total = rows.fold<int>(0, (a, r) => a + r.netAmount);
    _cell(sheet, totalRow, 4, '합계', bold: true, bgHex: 'FFEAF4FF');
    _numCell(sheet, totalRow, 5, total, bold: true, bgHex: 'FFEAF4FF');

    // [INV-3] 파일이 스스로 말하게 한다.
    //   이 파일은 화면을 떠나 은행·회계 담당에게 따로 간다. 거기서는 "몇 명이
    //   왜 빠졌는지"를 물어볼 화면이 없다. 그래서 그 사실을 파일에 적는다.
    //   사람을 추가하는 것이 아니라 **누락을 고지**하는 것이다.
    final excluded = plan.blockedRecords + plan.notApplicableRecords;
    if (excluded > 0) {
      final noteRow = totalRow + 2;
      final parts = <String>[
        '전체 급여 ${plan.totalRecords}건 중 ${plan.exportedRecords}건 포함',
        if (plan.blockedRecords > 0)
          '확인 필요 ${plan.blockedWorkers}명 · ${plan.blockedRecords}건 제외',
        if (plan.notApplicableRecords > 0)
          '$kNotApplicableLabel ${plan.notApplicableWorkers}명 · '
              '${plan.notApplicableRecords}건 제외',
      ];
      _cell(sheet, noteRow, 0, parts.join(' / '));
    }

    if (!context.mounted) return;
    await _shareExcel(context, excel, filename);
  }

  // ══════════════════════════════════════════════════════════
  // 이체현황 탭 — 회계/세무용 건별 상세 시트
  // 컬럼: 이름 | 사업장 | 업무 | 근무시간 | 급여형태 | 근무일 | 세전금액 |
  //        국민연금 | 건강보험 | 장기요양 | 고용보험 |
  //        세후금액 | 이체상태 | 이체일
  // 행 단위: 근무 건별 1행 + 합계 행
  //
  // [R7-PRE1] 업무·근무시간 두 컬럼은 **행을 구분하기 위한** 것이다.
  //   한 사람이 같은 날 두 건을 근무하는 것은 정상이고(오전 사무, 오후 행사),
  //   그때 예전 컬럼 구성으로는 두 행이 이름·사업장·급여형태·근무일까지
  //   모두 같아 보였다. 금액만 다른 똑같은 행 두 개 — 받는 쪽에서는
  //   중복 입력으로 읽힌다. DEV 실측으로 2026-09-20 에 3행이 그랬다.
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

    // [PII-DOC-R0.1] 이 시트는 이름만 필요하다 — 계좌 컬럼이 없다.
    // [R7-PRE1A.1] 사람 번호는 함께 읽는다 — 이름만으로는 동명이인이 구분되지 않는다.
    final profiles = await _loadWorkerProfiles(records, businessId);
    final names = profiles.names;
    final personNos = profiles.personNos;

    final excel = Excel.createExcel();
    excel.delete('Sheet1');

    final sheet = excel['급여현황'];
    _setColWidths(sheet, [10, 12, 16, 12, 14, 10, 12, 12, 10, 10, 10, 10, 12, 10, 14]);

    // 제목 행
    _cell(sheet, 0, 0, title, bold: true, fontSize: 13);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: 0),
      CellIndex.indexByColumnRow(columnIndex: 14, rowIndex: 0),
    );

    // 헤더
    const headers = [
      '근로자번호', '이름', '사업장', '업무', '근무시간', '급여형태', '근무일',
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
        final na = names[a.userId] ?? '이름 확인 불가';
        final nb = names[b.userId] ?? '이름 확인 불가';
        final nc = na.compareTo(nb);
        if (nc != 0) return nc;
        final dc = a.workDate.compareTo(b.workDate);
        if (dc != 0) return dc;
        // 같은 날 두 건이면 출근 시각 순 — 파일이 매번 같은 순서로 나와야
        // 두 번 내보낸 파일을 비교할 수 있다.
        final t = (a.checkIn ?? '').compareTo(b.checkIn ?? '');
        if (t != 0) return t;
        // [R7-PRE1A.1] 동명이인이면 여기까지 와도 갈리지 않는다 — 번호로,
        //   그래도 같으면 근태 문서 id 로 못을 박는다.
        final p = (personNos[a.userId] ?? '').compareTo(
            personNos[b.userId] ?? '');
        if (p != 0) return p;
        return a.id.compareTo(b.id);
      });

    // 합계 누산
    int sumGross = 0, sumPension = 0, sumHealth = 0;
    int sumLtc   = 0, sumEmploy  = 0, sumNet    = 0;

    for (int i = 0; i < sorted.length; i++) {
      final r   = sorted[i];
      final wd  = r.wageDetail;
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

      // 출퇴근이 아직 없으면 '-' 로 둔다. 빈 칸은 "같은 근무"로 읽힌다.
      final span = (r.checkIn == null && r.checkOut == null)
          ? '-'
          : '${r.checkIn ?? '-'}~${r.checkOut ?? '-'}';

      _cell(sheet, row, 0,  personNos[r.userId] ?? '');
      _cell(sheet, row, 1,  names[r.userId] ?? '이름 확인 불가');
      _cell(sheet, row, 2,  r.businessName);
      _cell(sheet, row, 3,  r.workType);
      _cell(sheet, row, 4,  span);
      _cell(sheet, row, 5,  _payTypeLabel(wd?.payScheduleType));
      _cell(sheet, row, 6,  FormatHelper.formatDateDot(r.workDate));
      _numCell(sheet, row, 7, gross);
      if (pension > 0) _numCell(sheet, row, 8, pension);
      if (health  > 0) _numCell(sheet, row, 9, health);
      if (ltc     > 0) _numCell(sheet, row, 10, ltc);
      if (employ  > 0) _numCell(sheet, row, 11, employ);
      _numCell(sheet, row, 12, net);
      _cell(sheet, row, 13, isXfer ? '이체완료' : '미이체');
      _cell(sheet, row, 14,
          r.transferDate != null ? FormatHelper.formatDateDot(r.transferDate!) : '');
    }

    // 합계 행
    final totalRow = 2 + sorted.length;
    _cell(sheet, totalRow, 6,    '합계',    bold: true, bgHex: 'FFEAF4FF');
    _numCell(sheet, totalRow, 7, sumGross,  bold: true, bgHex: 'FFEAF4FF');
    if (sumPension > 0) _numCell(sheet, totalRow, 8, sumPension, bold: true, bgHex: 'FFEAF4FF');
    if (sumHealth  > 0) _numCell(sheet, totalRow, 9, sumHealth,  bold: true, bgHex: 'FFEAF4FF');
    if (sumLtc     > 0) _numCell(sheet, totalRow, 10, sumLtc,    bold: true, bgHex: 'FFEAF4FF');
    if (sumEmploy  > 0) _numCell(sheet, totalRow, 11, sumEmploy, bold: true, bgHex: 'FFEAF4FF');
    _numCell(sheet, totalRow, 12, sumNet,   bold: true, bgHex: 'FFEAF4FF');

    if (!context.mounted) return;
    await _shareExcel(context, excel, filename);
  }

  // ── 공통 유틸 ───────────────────────────────────────────

  /// uid → 표시 이름.
  ///
  /// [PII-DOC-R0.1 / INV-1] Excel이 사용자 문서에서 필요로 하는 것은 **이름뿐**이다.
  ///   계좌는 Attendance 스냅샷에서 온다. 그래서 목적을 좁혀 호출한다 —
  ///   계좌 3필드가 응답에 실리지 않는다.
  ///
  ///   조회되지 않은 uid는 여기서 지우지 않는다. 이름을 모르는 것과 대상이
  ///   아닌 것은 다르고, 후자로 바꿔 버리면 그 사람이 파일에서 사라진다.
  ///   판정은 `buildTransferExportPlan`이 하고, 이름이 없으면 '이름 확인 불가'로 남는다.
  ///
  /// [R7-PRE1A.1] 번호도 함께 읽는다. 파일에는 **이름 말고 사람을 가리키는 것**이
  ///   하나는 있어야 한다 — 동명이인 두 사람의 급여가 한 파일에 있으면
  ///   이름만으로는 어느 줄이 누구의 것인지 알 수 없고, 받는 쪽에는 물어볼
  ///   화면이 없다. 번호는 사업장 범위 조회가 실어 준다.
  ///
  ///   번호가 row identity 를 대신하지는 않는다 — 한 사람이 여러 근무 행을
  ///   가질 수 있다. 행은 업무·근무시간·근무일이 가르고, 번호는 사람을 가른다.
  static Future<({Map<String, String> names, Map<String, String> personNos})>
      _loadWorkerProfiles(
    List<AttendanceModel> records,
    String businessId,
  ) async {
    final fsService = FirestoreService();
    final uidList   = records.map((r) => r.userId).toSet().toList();
    final userMap   = await fsService.getUsersBatch(
      uidList,
      businessId: businessId,
      purpose: FirestoreService.purposeWorkerDirectory,
    );
    return (
      names: {for (final e in userMap.entries) e.key: e.value.name},
      personNos: {
        for (final e in userMap.entries)
          if (e.value.personLabel != null) e.key: e.value.personLabel!,
      },
    );
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
      try { await file.delete(); } catch (_) {}
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
