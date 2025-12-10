// lib/utils/attendance_list_pdf.dart
// 인원현황 명단 PDF 생성 유틸리티
//
// 필요 패키지:
// pdf: ^3.10.8
// printing: ^5.12.0
//
// pubspec.yaml에 추가:
// dependencies:
//   pdf: ^3.10.8
//   printing: ^5.12.0

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/core/application_model.dart';
import '../models/core/user_model.dart';

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
  final String name;
  final String gender;
  final String phone;
  final String workTime;

  AttendanceListItem({
    required this.name,
    required this.gender,
    required this.phone,
    required this.workTime,
  });
}

/// 명단 PDF 생성 및 미리보기 헬퍼
class AttendanceListPdf {
  static pw.Font? _koreanFont;
  static pw.Font? _koreanBoldFont;

  /// 한글 폰트 로드
  static Future<void> _loadFonts() async {
    if (_koreanFont != null) return;

    try {
      // Google Fonts에서 Noto Sans KR 로드
      _koreanFont = await PdfGoogleFonts.notoSansKRRegular();
      _koreanBoldFont = await PdfGoogleFonts.notoSansKRBold();
    } catch (e) {
      // 폴백: 기본 폰트 사용
    }
  }

  /// ✅ 폰트 미리 로딩 (외부에서 호출 가능)
  static Future<void> preloadFonts() async {
    await _loadFonts();
  }

  /// 바텀시트로 PDF 미리보기 표시
  static Future<void> showPreview({
    required BuildContext context,
    required AttendanceListData data,
  }) async {
    try {
      await _loadFonts();

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => _PreviewBottomSheet(data: data),
      );
    } catch (e) {
      print('❌ PDF 미리보기 오류: $e');
      rethrow;
    }
  }

  /// ✅ 미리 생성된 PDF로 바로 미리보기 표시 (로딩 없음)
  static Future<void> showPreviewWithBytes({
    required BuildContext context,
    required AttendanceListData data,
    required Uint8List pdfBytes,
  }) async {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PreviewBottomSheetWithBytes(
        data: data,
        pdfBytes: pdfBytes,
      ),
    );
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
    final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[data.date.weekday - 1];
    final dateStr = '${data.date.year}년 ${data.date.month}월 ${data.date.day}일 ($weekday)';

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
    // 업무명 (시간 포함)
    final workTypeLabel = workTime.isNotEmpty 
        ? '■ $workType ($workTime)' 
        : '■ $workType';
    
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
              1: const pw.FixedColumnWidth(55),   // 이름
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
                  _buildTableCell('이름', headerStyle, isHeader: true),
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
    final printTime = '${now.year}.${now.month.toString().padLeft(2, '0')}.${now.day.toString().padLeft(2, '0')} ${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

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
    Map<String, dynamic>? workTypeMap,  // 업무유형별 시간 정보
  }) {
    // 업무별 그룹화
    final Map<String, List<ApplicationModel>> workTypeGroups = {};
    for (var app in confirmedWorkers) {
      final workType = app.selectedWorkType;
      workTypeGroups.putIfAbsent(workType, () => []);
      workTypeGroups[workType]!.add(app);
    }

    // 각 그룹 내 정렬 (출근시간 → 성별 → 이름 가나다순)
    for (var entry in workTypeGroups.entries) {
      final workType = entry.key;
      final workers = entry.value;
      // workTypeMap에서 기본 시간 정보 가져오기
      final workTypeInfo = workTypeMap?[workType];
      final defaultStartTime = workTypeInfo?['startTime'] ?? '';
      
      workers.sort((a, b) {
        // 1. 출근시간 정렬 (빠른 순)
        final startTimeA = a.startTime.isNotEmpty ? a.startTime : defaultStartTime;
        final startTimeB = b.startTime.isNotEmpty ? b.startTime : defaultStartTime;
        
        if (startTimeA != startTimeB) {
          return startTimeA.compareTo(startTimeB);
        }
        
        final userA = userMap[a.uid];
        final userB = userMap[b.uid];

        if (userA == null || userB == null) return 0;

        // 2. 성별 정렬 (남성 먼저)
        final genderOrder = {'남성': 0, '여성': 1};
        final genderA = genderOrder[userA.gender] ?? 2;
        final genderB = genderOrder[userB.gender] ?? 2;

        if (genderA != genderB) {
          return genderA.compareTo(genderB);
        }

        // 3. 이름 가나다순
        return (userA.name ?? '').compareTo(userB.name ?? '');
      });
    }

    // AttendanceListItem으로 변환
    final Map<String, List<AttendanceListItem>> convertedGroups = {};
    for (var entry in workTypeGroups.entries) {
      final workType = entry.key;
      // workTypeMap에서 시간 정보 가져오기
      final workTypeInfo = workTypeMap?[workType];
      final defaultStartTime = workTypeInfo?['startTime'] ?? '';
      final defaultEndTime = workTypeInfo?['endTime'] ?? '';
      
      convertedGroups[entry.key] = entry.value.map((app) {
        final user = userMap[app.uid];
        // ApplicationModel의 시간이 비어있으면 workTypeMap에서 가져오기
        final startTime = app.startTime.isNotEmpty ? app.startTime : defaultStartTime;
        final endTime = app.endTime.isNotEmpty ? app.endTime : defaultEndTime;
        
        return AttendanceListItem(
          name: user?.name ?? 'Unknown',
          gender: user?.gender ?? '',
          phone: _formatPhone(user?.phone ?? ''),
          workTime: _formatWorkTime(startTime, endTime),
        );
      }).toList();
    }

    // 업무별 근무시간 Map 생성
    final Map<String, String> workTypeTimeMap = {};
    if (workTypeMap != null) {
      for (var entry in workTypeMap.entries) {
        final workType = entry.key;
        final info = entry.value;
        final startTime = info['startTime'] ?? '';
        final endTime = info['endTime'] ?? '';
        if (startTime.isNotEmpty && endTime.isNotEmpty) {
          workTypeTimeMap[workType] = '$startTime~$endTime';
        }
      }
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

  /// 근무시간 포맷 (09:00~18:00 형식 유지)
  static String _formatWorkTime(String start, String end) {
    if (start.isEmpty || end.isEmpty) return '-';
    return '$start~$end';
  }
}

/// PDF 미리보기 바텀시트 (성능 최적화 + 핀치 줌)
class _PreviewBottomSheet extends StatefulWidget {
  final AttendanceListData data;

  const _PreviewBottomSheet({required this.data});

  @override
  State<_PreviewBottomSheet> createState() => _PreviewBottomSheetState();
}

class _PreviewBottomSheetState extends State<_PreviewBottomSheet> {
  Uint8List? _pdfBytes;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generatePdf();
  }

  /// ✅ PDF 미리 생성 (한 번만)
  Future<void> _generatePdf() async {
    try {
      final bytes = await AttendanceListPdf.generatePdf(widget.data);
      if (mounted) {
        setState(() {
          _pdfBytes = bytes;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 핸들바
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 헤더
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '명단 미리보기',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      // ✅ 줌 힌트 추가
                      Text(
                        '두 손가락으로 확대/축소 가능',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // PDF 미리보기
          Expanded(
            child: _isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('PDF 생성 중...'),
                      ],
                    ),
                  )
                : _error != null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, size: 48, color: Colors.red),
                            const SizedBox(height: 16),
                            Text('PDF 생성 실패\n$_error', textAlign: TextAlign.center),
                          ],
                        ),
                      )
                    // ✅ 미리 생성된 PDF 사용 + InteractiveViewer로 줌 지원
                    : PdfPreview(
                        build: (format) async => _pdfBytes!,
                        canChangeOrientation: false,
                        canChangePageFormat: false,
                        canDebug: false,
                        allowPrinting: true,
                        allowSharing: true,
                        useActions: true,
                        pdfPreviewPageDecoration: BoxDecoration(
                          color: Colors.white,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 10,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        pdfFileName: '${widget.data.businessName}_근무명단_${widget.data.date.year}${widget.data.date.month.toString().padLeft(2, '0')}${widget.data.date.day.toString().padLeft(2, '0')}.pdf',
                      ),
          ),
        ],
      ),
    );
  }
}

/// ✅ 미리 생성된 PDF로 바로 표시하는 바텀시트 (로딩 없음)
class _PreviewBottomSheetWithBytes extends StatelessWidget {
  final AttendanceListData data;
  final Uint8List pdfBytes;

  const _PreviewBottomSheetWithBytes({
    required this.data,
    required this.pdfBytes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 핸들바
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 헤더
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.description_outlined, color: Colors.blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '명단 미리보기',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '두 손가락으로 확대/축소 가능',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ✅ PDF 바로 표시 (로딩 없음!)
          Expanded(
            child: PdfPreview(
              build: (format) async => pdfBytes,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              allowPrinting: true,
              allowSharing: true,
              useActions: true,
              pdfPreviewPageDecoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              pdfFileName: '${data.businessName}_근무명단_${data.date.year}${data.date.month.toString().padLeft(2, '0')}${data.date.day.toString().padLeft(2, '0')}.pdf',
            ),
          ),
        ],
      ),
    );
  }
}