// lib/utils/attendance_list_pdf.dart
// 인원현황 명단 PDF/Excel 생성 유틸리티

import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../models/core/application_model.dart';
import '../models/core/user_model.dart';
import '../theme/app_colors.dart';
import '../widgets/common/loading_widget.dart';
import '../widgets/dialogs/styled_dialog.dart';
import 'format_helper.dart';
import 'responsive_helper.dart';

/// 그룹(파트) 정렬 기준
enum AttendanceGroupSort {
  partName, // 파트별 근무시간 (파트명 → 같은 파트 내 빠른 시간순)
  workTime, // 근무시간/파트이름 (빠른 시간 → 같은 시간 내 파트명순)
}

extension AttendanceGroupSortExt on AttendanceGroupSort {
  String get label {
    switch (this) {
      case AttendanceGroupSort.partName: return '파트·근무시간';
      case AttendanceGroupSort.workTime: return '근무시간·파트';
    }
  }

  IconData get icon {
    switch (this) {
      case AttendanceGroupSort.workTime: return Icons.schedule_outlined;
      case AttendanceGroupSort.partName: return Icons.work_outline;
    }
  }
}

/// 파트 내 개인 정렬 기준
enum AttendanceItemSort {
  nameOnly,       // 이름순 (기본 — 가나다)
  genderThenName, // 성별·이름순 (남→여→가나다)
}

extension AttendanceItemSortExt on AttendanceItemSort {
  String get label {
    switch (this) {
      case AttendanceItemSort.nameOnly: return '성명';
      case AttendanceItemSort.genderThenName: return '성별·성명';
    }
  }

  IconData get icon {
    switch (this) {
      case AttendanceItemSort.genderThenName: return Icons.people_outline;
      case AttendanceItemSort.nameOnly: return Icons.sort_by_alpha;
    }
  }
}

/// 명단 출력용 데이터 모델
class AttendanceListData {
  final String businessName;
  final DateTime date;
  final Map<String, List<AttendanceListItem>> workTypeGroups;
  final Map<String, String> workTypeTimeMap;  // 업무별 근무시간 (예: '냉장분류' -> '18:00~22:00')
  final int totalCount;

  AttendanceListData({
    required this.businessName,
    required this.date,
    required this.workTypeGroups,
    required this.workTypeTimeMap,
    required this.totalCount,
  });
}

/// 개별 근무자 데이터
class AttendanceListItem {
  final String workType;
  final String name;
  final String gender;
  final String phone;
  final String workTime; // 'HH:mm~HH:mm' 형식 (PDF용)
  final String startTime;
  final String endTime;

  AttendanceListItem({
    required this.workType,
    required this.name,
    required this.gender,
    required this.phone,
    required this.workTime,
    required this.startTime,
    required this.endTime,
  });
}

/// 명단 PDF 생성 및 미리보기 헬퍼
class AttendanceListPdf {
  static pw.Font? _koreanFont;
  static pw.Font? _koreanBoldFont;
  static bool _isLoading = false;  // ✅ 중복 로딩 방지

  /// 한글 폰트 로드 (Assets에서 - 빠름!)
  static Future<void> _loadFonts() async {
    // 이미 로드됨
    if (_koreanFont != null) return;
    
    // 중복 로딩 방지
    if (_isLoading) {
      // 로딩 중이면 완료될 때까지 대기
      while (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return;
    }

    _isLoading = true;
    
    try {
      debugPrint('📝 [PDF] 한글 폰트 로딩 시작 (Assets)...');
      final stopwatch = Stopwatch()..start();
      
      // ✅ Assets에서 로드 (네트워크 다운로드 없음 - 즉시!)
      final regularData = await rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf');
      final boldData = await rootBundle.load('assets/fonts/NotoSansKR-Bold.ttf');
      
      _koreanFont = pw.Font.ttf(regularData);
      _koreanBoldFont = pw.Font.ttf(boldData);
      
      stopwatch.stop();
      debugPrint('✅ [PDF] 한글 폰트 로드 완료: ${stopwatch.elapsedMilliseconds}ms');
    } catch (e) {
      debugPrint('⚠️ [PDF] 폰트 로드 실패: $e');
      // 폴백: 기본 폰트 사용 (한글 깨질 수 있음)
    } finally {
      _isLoading = false;
    }
  }

  /// ✅ 폰트 미리 로딩 (외부에서 호출 가능)
  static Future<void> preloadFonts() async {
    await _loadFonts();
  }

  /// ✅ 미리 생성된 PDF로 바로 미리보기 표시 (로딩 없음)
  static Future<void> showPreviewWithBytes({
    required BuildContext context,
    required AttendanceListData data,
    required Uint8List pdfBytes,
    // 정렬 변경 시 재생성용
    List<ApplicationModel>? confirmedWorkers,
    Map<String, UserModel>? userMap,
    String? businessName,
    DateTime? date,
  }) async {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: false,    // InteractiveViewer 제스처와 충돌 방지
      isDismissible: false, // PDF 재생성 중 실수로 닫히는 것 방지
      builder: (context) => _PreviewBottomSheetWithBytes(
        initialData: data,
        initialPdfBytes: pdfBytes,
        confirmedWorkers: confirmedWorkers,
        userMap: userMap,
        businessName: businessName,
        date: date,
      ),
    );
  }

  /// Excel 명단 생성 (.xlsx)
  static Future<Uint8List> generateExcel(AttendanceListData data) async {
    final excel = Excel.createExcel();
    excel.delete('Sheet1');
    final sheet = excel['근무명단'];

    final dateStr =
        '${data.date.year}년 ${data.date.month}월 ${data.date.day}일 (${FormatHelper.weekday(data.date)})';

    // 열 너비 설정
    sheet.setColumnWidth(0, 16);  // 사업장명
    sheet.setColumnWidth(1, 14);  // 근무일자
    sheet.setColumnWidth(2, 14);  // 파트
    sheet.setColumnWidth(3, 14);  // 성명
    sheet.setColumnWidth(4, 6);   // 성별
    sheet.setColumnWidth(5, 18);  // 연락처
    sheet.setColumnWidth(6, 12);  // 근무시작시간
    sheet.setColumnWidth(7, 12);  // 퇴근시간
    sheet.setColumnWidth(8, 20);  // 비고

    int row = 0;

    final workDateStr = FormatHelper.formatDateISO(data.date);

    // 제목
    _excelCell(sheet, row, 0,
        '${data.businessName} 근무명단',
        bold: true, fontSize: 14);
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row),
    );
    row++;

    // 날짜 + 총 인원
    _excelCell(sheet, row, 0, '$dateStr   |   전체 ${data.totalCount}명');
    sheet.merge(
      CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
      CellIndex.indexByColumnRow(columnIndex: 8, rowIndex: row),
    );
    row++;
    row++; // 빈 행

    // 컬럼 헤더
    const headers = ['사업장명', '근무일자', '파트', '성명', '성별', '연락처', '근무시작시간', '퇴근시간', '비고'];
    for (int c = 0; c < headers.length; c++) {
      _excelCell(sheet, row, c, headers[c], bold: true, bgHex: 'FFD6E4F0');
    }
    row++;

    // 데이터 행
    for (final entry in data.workTypeGroups.entries) {
      for (final worker in entry.value) {
        final gender = worker.gender == '남성'
            ? '남'
            : (worker.gender == '여성' ? '여' : '-');
        final rowData = [
          data.businessName,
          workDateStr,
          worker.workType,
          worker.name,
          gender,
          worker.phone,
          worker.startTime,
          worker.endTime,
          '',
        ];
        for (int c = 0; c < rowData.length; c++) {
          _excelCell(sheet, row, c, rowData[c]);
        }
        row++;
      }
    }

    // 출력일시
    final now = DateTime.now();
    final printTime = '출력일시: ${FormatHelper.formatDateDot(now)} ${FormatHelper.formatTime(now)}';
    _excelCell(sheet, row, 0, printTime, fontSize: 9);

    final bytes = excel.encode();
    if (bytes == null) throw Exception('Excel 생성 실패');
    return Uint8List.fromList(bytes);
  }

  static void _excelCell(
    Sheet sheet,
    int row,
    int col,
    String text, {
    bool bold = false,
    int fontSize = 10,
    String? bgHex,
  }) {
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

  /// Excel 파일 공유 (기기 공유 시트)
  static Future<void> shareAsExcel(AttendanceListData data) async {
    final bytes = await generateExcel(data);
    final dir = await getTemporaryDirectory();
    final fileName =
        '${data.businessName}_근무명단_${FormatHelper.formatDateStamp(data.date)}.xlsx';
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet')],
      subject: '${data.businessName} 근무명단',
    );
    await file.delete();
  }

  /// PDF 문서 생성
  static Future<Uint8List> generatePdf(AttendanceListData data) async {
    try {
      await _loadFonts();
    } catch (e) {
      // 폰트 로딩 실패 시 기본 폰트 사용
    }

    final pdf = pw.Document();
    
    // 날짜 포맷 (한글 로케일 문제 방지)
    final dateStr = '${data.date.year}년 ${data.date.month}월 ${data.date.day}일 (${FormatHelper.weekday(data.date)})';

    // 스타일 정의 (폰트가 null이면 기본 폰트 사용)
    final titleStyle = pw.TextStyle(
      font: _koreanBoldFont,
      fontFallback: _koreanFont != null ? [_koreanFont!] : [],
      fontSize: 18,
      fontWeight: pw.FontWeight.bold,
    );

    final subtitleStyle = pw.TextStyle(
      font: _koreanFont,
      fontSize: 12,
      color: PdfColors.grey700,
    );

    final headerStyle = pw.TextStyle(
      font: _koreanBoldFont,
      fontFallback: _koreanFont != null ? [_koreanFont!] : [],
      fontSize: 11,
      fontWeight: pw.FontWeight.bold,
    );

    final bodyStyle = pw.TextStyle(
      font: _koreanFont,
      fontSize: 10,
    );

    final sectionStyle = pw.TextStyle(
      font: _koreanBoldFont,
      fontFallback: _koreanFont != null ? [_koreanFont!] : [],
      fontSize: 12,
      fontWeight: pw.FontWeight.bold,
    );

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        build: (context) => [
          // 헤더
          _buildHeader(data, dateStr, titleStyle, subtitleStyle),
          pw.SizedBox(height: 20),

          // 업무별 테이블
          ...data.workTypeGroups.entries.map((entry) {
            return _buildWorkTypeSection(
              workType: entry.key,
              workTime: data.workTypeTimeMap[entry.key] ?? '',
              workers: entry.value,
              sectionStyle: sectionStyle,
              headerStyle: headerStyle,
              bodyStyle: bodyStyle,
            );
          }),

          pw.SizedBox(height: 30),

          // 하단 정보
          _buildFooter(bodyStyle),
        ],
      ),
    );

    return pdf.save();
  }

  /// 헤더 섹션
  static pw.Widget _buildHeader(
    AttendanceListData data,
    String dateStr,
    pw.TextStyle titleStyle,
    pw.TextStyle subtitleStyle,
  ) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: pw.BoxDecoration(
        color: PdfColors.blue50,
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        children: [
          // 1줄: 센터명
          pw.Text(
            '${data.businessName} 근무명단',
            style: titleStyle,
          ),
          pw.SizedBox(height: 6),
          // 2줄: 날짜 | 전체 명수
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(dateStr, style: subtitleStyle),
              pw.SizedBox(width: 16),
              pw.Container(
                width: 1,
                height: 12,
                color: PdfColors.grey400,
              ),
              pw.SizedBox(width: 16),
              pw.Text(
                '전체 ${data.totalCount}명',
                style: subtitleStyle.copyWith(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 업무유형별 섹션
  static pw.Widget _buildWorkTypeSection({
    required String workType,
    required String workTime,
    required List<AttendanceListItem> workers,
    required pw.TextStyle sectionStyle,
    required pw.TextStyle headerStyle,
    required pw.TextStyle bodyStyle,
  }) {
    // ✅ 업무명 (이미 시간이 포함되어 있으면 그대로, 아니면 추가)
    final workTypeLabel = workType.contains('~') 
        ? '■ $workType'  // 이미 시간 포함
        : (workTime.isNotEmpty ? '■ $workType ($workTime)' : '■ $workType');
    
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 20),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // 업무유형 헤더
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey200,
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(workTypeLabel, style: sectionStyle),
                pw.Text('${workers.length}명', style: bodyStyle),
              ],
            ),
          ),
          pw.SizedBox(height: 8),

          // 테이블
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
            columnWidths: {
              0: const pw.FixedColumnWidth(25),   // 체크박스
              1: const pw.FixedColumnWidth(55),   // 성명
              2: const pw.FixedColumnWidth(35),   // 성별
              3: const pw.FixedColumnWidth(95),   // 연락처
              4: const pw.FixedColumnWidth(80),   // 시간 (18:00~22:00)
              5: const pw.FlexColumnWidth(1),     // 비고
            },
            children: [
              // 헤더 행
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.grey100),
                children: [
                  _buildTableCell('□', headerStyle, isHeader: true),
                  _buildTableCell('성명', headerStyle, isHeader: true),
                  _buildTableCell('성별', headerStyle, isHeader: true),
                  _buildTableCell('연락처', headerStyle, isHeader: true),
                  _buildTableCell('시간', headerStyle, isHeader: true),
                  _buildTableCell('비고', headerStyle, isHeader: true),
                ],
              ),
              // 데이터 행
              ...workers.map((worker) => pw.TableRow(
                children: [
                  _buildTableCell('□', bodyStyle),
                  _buildTableCell(worker.name, bodyStyle),
                  _buildTableCell(_formatGender(worker.gender), bodyStyle),
                  _buildTableCell(worker.phone, bodyStyle),
                  _buildTableCell(worker.workTime, bodyStyle),
                  _buildTableCell('', bodyStyle), // 비고 빈칸
                ],
              )),
            ],
          ),
        ],
      ),
    );
  }

  /// 성별 포맷 (남성 → 남, 여성 → 여)
  static String _formatGender(String gender) {
    if (gender == '남성') return '남';
    if (gender == '여성') return '여';
    return '-';
  }

  /// 테이블 셀
  static pw.Widget _buildTableCell(
    String text,
    pw.TextStyle style, {
    bool isHeader = false,
  }) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      alignment: pw.Alignment.center,
      child: pw.Text(
        text,
        style: style,
        textAlign: pw.TextAlign.center,
      ),
    );
  }

  /// 하단 정보 (출력일시 + 서명란)
  static pw.Widget _buildFooter(pw.TextStyle bodyStyle) {
    final now = DateTime.now();
    final printTime = '${FormatHelper.formatDateDot(now)} ${FormatHelper.formatTime(now)}';

    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            '출력일시: $printTime',
            style: bodyStyle.copyWith(color: PdfColors.grey600),
          ),
          pw.Row(
            children: [
              pw.Text('담당자: ', style: bodyStyle),
              pw.Container(
                width: 120,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: PdfColors.grey400),
                  ),
                ),
                child: pw.Text(' ', style: bodyStyle),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 데이터 변환 헬퍼 (다이얼로그에서 호출용)
  static AttendanceListData convertFromDialogData({
    required String businessName,
    required DateTime date,
    required List<ApplicationModel> confirmedWorkers,
    required Map<String, UserModel> userMap,
    Map<String, dynamic>? workTypeMap,
    AttendanceGroupSort groupSort = AttendanceGroupSort.partName,
    AttendanceItemSort itemSort = AttendanceItemSort.nameOnly,
  }) {
    // workType + 시간 조합으로 그룹화
    final Map<String, List<ApplicationModel>> workTypeGroups = {};
    for (var app in confirmedWorkers) {
      final groupKey = '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
      workTypeGroups.putIfAbsent(groupKey, () => []);
      workTypeGroups[groupKey]!.add(app);
    }

    // 그룹 정렬
    final sortedEntries = workTypeGroups.entries.toList()
      ..sort((a, b) {
        final appA = a.value.first;
        final appB = b.value.first;
        switch (groupSort) {
          case AttendanceGroupSort.partName:
            final typeCompare = appA.selectedWorkType.compareTo(appB.selectedWorkType);
            if (typeCompare != 0) return typeCompare;
            return appA.startTime.compareTo(appB.startTime);
          case AttendanceGroupSort.workTime:
            final timeCompare = appA.startTime.compareTo(appB.startTime);
            if (timeCompare != 0) return timeCompare;
            final endCompare = appA.endTime.compareTo(appB.endTime);
            if (endCompare != 0) return endCompare;
            return appA.selectedWorkType.compareTo(appB.selectedWorkType);
        }
      });

    // 파트 내 개인 정렬
    for (var entry in sortedEntries) {
      entry.value.sort((a, b) {
        final userA = userMap[a.uid];
        final userB = userMap[b.uid];
        if (userA == null || userB == null) return 0;
        switch (itemSort) {
          case AttendanceItemSort.nameOnly:
            return userA.name.compareTo(userB.name);
          case AttendanceItemSort.genderThenName:
            final genderOrder = {'남성': 0, '여성': 1};
            final gA = genderOrder[userA.gender] ?? 2;
            final gB = genderOrder[userB.gender] ?? 2;
            if (gA != gB) return gA.compareTo(gB);
            return userA.name.compareTo(userB.name);
        }
      });
    }

    // AttendanceListItem으로 변환 + workTypeTimeMap 생성
    final Map<String, List<AttendanceListItem>> convertedGroups = {};
    final Map<String, String> workTypeTimeMap = {};
    
    for (var entry in sortedEntries) {
      final firstApp = entry.value.first;
      final workType = firstApp.selectedWorkType;
      final startTime = firstApp.startTime;
      final endTime = firstApp.endTime;
      
      // ✅ 표시 키: workType만 (시간은 workTypeTimeMap에서)
      // 같은 workType이 다른 시간대로 있을 수 있으므로 고유 키 생성
      final displayKey = '$workType ($startTime~$endTime)';
      
      // 시간 정보 저장 (빈 문자열로 - 이미 displayKey에 포함)
      workTypeTimeMap[displayKey] = '';
      
      convertedGroups[displayKey] = entry.value.map((app) {
        final user = userMap[app.uid];
        
        return AttendanceListItem(
          workType: workType,
          name: user?.name ?? 'Unknown',
          gender: user?.gender ?? '',
          phone: _formatPhone(user?.phone ?? ''),
          workTime: '${app.startTime}~${app.endTime}',
          startTime: app.startTime,
          endTime: app.endTime,
        );
      }).toList();
    }

    return AttendanceListData(
      businessName: businessName,
      date: date,
      workTypeGroups: convertedGroups,
      workTypeTimeMap: workTypeTimeMap,
      totalCount: confirmedWorkers.length,
    );
  }

  /// 전화번호 포맷 (010-1234-5678)
  static String _formatPhone(String phone) {
    if (phone.isEmpty) return '-';
    
    // 숫자만 추출
    final digits = phone.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (digits.length == 11) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 7)}-${digits.substring(7)}';
    } else if (digits.length == 10) {
      return '${digits.substring(0, 3)}-${digits.substring(3, 6)}-${digits.substring(6)}';
    }
    
    return phone;
  }

}

/// PDF 미리보기 바텀시트 (정렬 선택 + 재생성 지원)
class _PreviewBottomSheetWithBytes extends StatefulWidget {
  final AttendanceListData initialData;
  final Uint8List initialPdfBytes;
  final List<ApplicationModel>? confirmedWorkers;
  final Map<String, UserModel>? userMap;
  final String? businessName;
  final DateTime? date;

  const _PreviewBottomSheetWithBytes({
    required this.initialData,
    required this.initialPdfBytes,
    this.confirmedWorkers,
    this.userMap,
    this.businessName,
    this.date,
  });

  @override
  State<_PreviewBottomSheetWithBytes> createState() =>
      _PreviewBottomSheetWithBytesState();
}

class _PreviewBottomSheetWithBytesState
    extends State<_PreviewBottomSheetWithBytes> {
  late AttendanceListData _data;
  late Uint8List _pdfBytes;
  AttendanceGroupSort _groupSort = AttendanceGroupSort.partName;
  AttendanceItemSort _itemSort = AttendanceItemSort.nameOnly;
  bool _isRegenerating = false;
  bool _isExporting = false;
  bool _isPdfSharing = false;
  bool _isPdfPrinting = false;

  @override
  void initState() {
    super.initState();
    _data = widget.initialData;
    _pdfBytes = widget.initialPdfBytes;
  }

  Future<void> _exportExcel() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      await AttendanceListPdf.shareAsExcel(_data);
    } catch (_) {
      // 실패 시 조용히 무시 (share_plus 취소 포함)
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _sharePdf() async {
    if (_isPdfSharing) return;
    setState(() => _isPdfSharing = true);
    try {
      final name =
          '${_data.businessName}_근무명단_${FormatHelper.formatDateStamp(_data.date)}.pdf';
      await Printing.sharePdf(bytes: _pdfBytes, filename: name);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isPdfSharing = false);
    }
  }

  Future<void> _printPdf() async {
    if (_isPdfPrinting) return;
    setState(() => _isPdfPrinting = true);
    try {
      final name =
          '${_data.businessName}_근무명단_${FormatHelper.formatDateStamp(_data.date)}.pdf';
      await Printing.layoutPdf(onLayout: (_) async => _pdfBytes, name: name);
    } finally {
      if (mounted) setState(() => _isPdfPrinting = false);
    }
  }

  bool get _canSort =>
      widget.confirmedWorkers != null &&
      widget.userMap != null &&
      widget.businessName != null &&
      widget.date != null;

  Future<void> _applySort({
    AttendanceGroupSort? groupSort,
    AttendanceItemSort? itemSort,
  }) async {
    if (_isRegenerating || !_canSort) return;
    final newGroup = groupSort ?? _groupSort;
    final newItem = itemSort ?? _itemSort;
    if (newGroup == _groupSort && newItem == _itemSort) return;

    setState(() => _isRegenerating = true);
    try {
      final newData = AttendanceListPdf.convertFromDialogData(
        businessName: widget.businessName!,
        date: widget.date!,
        confirmedWorkers: widget.confirmedWorkers!,
        userMap: widget.userMap!,
        groupSort: newGroup,
        itemSort: newItem,
      );
      final newBytes = await AttendanceListPdf.generatePdf(newData);
      if (mounted) {
        setState(() {
          _data = newData;
          _pdfBytes = newBytes;
          _groupSort = newGroup;
          _itemSort = newItem;
          _isRegenerating = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isRegenerating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 핸들바
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, color: AppColors.info),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '미리보기',
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  onPressed: _isExporting ? null : _exportExcel,
                  icon: _isExporting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.table_chart_outlined, size: 18),
                  label: const Text('엑셀'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.print_outlined, size: 20),
                  tooltip: '인쇄',
                  onPressed: _printPdf,
                ),
                IconButton(
                  icon: _isPdfSharing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.share_outlined, size: 20),
                  tooltip: 'PDF 공유',
                  onPressed: _isPdfSharing ? null : _sharePdf,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          // 정렬 선택 바
          if (_canSort)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 그룹 정렬
                  _SortRow(
                    label: '파트순서',
                    options: AttendanceGroupSort.values
                        .map((o) => _SortChipData(
                              label: o.label,
                              icon: o.icon,
                              selected: o == _groupSort,
                              onTap: () => _applySort(groupSort: o),
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 6),
                  // 파트 내 개인 정렬
                  _SortRow(
                    label: '파트 내 순서',
                    options: AttendanceItemSort.values
                        .map((o) => _SortChipData(
                              label: o.label,
                              icon: o.icon,
                              selected: o == _itemSort,
                              onTap: () => _applySort(itemSort: o),
                            ))
                        .toList(),
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // PDF 미리보기 — 직접 핀치줌 (PdfPreview 더블탭 문제 해결)
          Expanded(
            child: Stack(
              children: [
                _AttendancePdfViewer(
                  key: ValueKey('${_groupSort.name}_${_itemSort.name}'),
                  pdfBytes: _pdfBytes,
                ),
                if (_isRegenerating)
                  Container(
                    color: Colors.white.withValues(alpha: 0.75),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('정렬 적용 중...'),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      ), // Container
    ); // ConstrainedBox
  }
}

class _SortChipData {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SortChipData({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
}

class _SortRow extends StatelessWidget {
  final String label;
  final List<_SortChipData> options;

  const _SortRow({required this.label, required this.options});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            children: options
                .map((o) => _SortChip(
                      label: o.label,
                      icon: o.icon,
                      selected: o.selected,
                      onTap: o.onTap,
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected ? theme.primaryColor : AppColors.grey500;
    return Material(
      color: selected
          ? theme.primaryColor.withValues(alpha: 0.1)
          : AppColors.grey100,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: ResponsiveHelper.smallStyle(context, color: color).copyWith(
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 핀치줌 PDF 뷰어 ─────────────────────────────────────────────
// PdfPreview는 더블탭 후 줌 → Printing.raster() + InteractiveViewer로 교체
class _AttendancePdfViewer extends StatefulWidget {
  final Uint8List pdfBytes;
  const _AttendancePdfViewer({super.key, required this.pdfBytes});

  @override
  State<_AttendancePdfViewer> createState() => _AttendancePdfViewerState();
}

class _AttendancePdfViewerState extends State<_AttendancePdfViewer> {
  late final Future<List<Uint8List>> _pagesFuture;

  @override
  void initState() {
    super.initState();
    _pagesFuture = _rasterPages();
  }

  Future<List<Uint8List>> _rasterPages() async {
    final pages = <Uint8List>[];
    await for (final page in Printing.raster(widget.pdfBytes, dpi: 150)) {
      pages.add(await page.toPng());
    }
    return pages;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Uint8List>>(
      future: _pagesFuture,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const LoadingWidget();
        }
        if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
          return const Center(child: Text('PDF를 불러올 수 없습니다'));
        }
        final pages = snap.data!;
        return LayoutBuilder(
          builder: (ctx, constraints) {
            final pageWidth = constraints.maxWidth - 16;
            return InteractiveViewer(
              constrained: false,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 5.0,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                child: Column(
                  children: pages
                      .map((pageBytes) => Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            width: pageWidth,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: Image.memory(
                              pageBytes,
                              width: pageWidth,
                              fit: BoxFit.fitWidth,
                            ),
                          ))
                      .toList(),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
