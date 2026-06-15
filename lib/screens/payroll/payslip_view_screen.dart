// lib/screens/payroll/payslip_view_screen.dart
//
// 임금명세서 미리보기 화면
// - Printing.raster() + InteractiveViewer로 직접 핀치줌 구현
// - 공유(share_plus) / 인쇄(printing) 지원
// - 성능: PDF bytes 최초 1회 생성, 래스터 이미지 캐싱

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';

import '../../models/core/attendance_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/user_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/loading_widget.dart';
import 'payslip_pdf_builder.dart';
import '../../widgets/common/gradient_scaffold.dart';

class PayslipViewScreen extends StatefulWidget {
  final AttendanceModel attendance;
  final UserModel? worker;          // UserModel 또는 workerName 중 하나 필수
  final String? workerNameOverride; // worker가 null일 때 사용
  final BusinessModel? business;    // 선택 — 사업장 주소 등 표시용

  const PayslipViewScreen({
    super.key,
    required this.attendance,
    this.worker,
    this.workerNameOverride,
    this.business,
  }) : assert(worker != null || workerNameOverride != null,
           'worker 또는 workerNameOverride 중 하나는 필수입니다');

  @override
  State<PayslipViewScreen> createState() => _PayslipViewScreenState();
}

class _PayslipViewScreenState extends State<PayslipViewScreen> {
  // PDF 바이트 캐시 — 한 번 생성 후 재사용 (성능 최적화)
  Future<PayslipData>? _dataFuture;
  // PDF bytes Future — build()마다 재생성 방지
  Future<Uint8List>? _pdfBytesFuture;

  /// worker?.name 우선, 없으면 workerNameOverride 사용
  String get _workerName =>
      widget.worker?.name ?? widget.workerNameOverride ?? '근무자';

  @override
  void initState() {
    super.initState();
    _dataFuture = _buildData();
  }

  Future<PayslipData> _buildData() async {
    if (widget.attendance.wageDetail == null) {
      throw Exception('급여 정보가 없습니다. 관리자에게 문의해주세요.');
    }
    // 폰트 로딩 포함 — rootBundle 접근 실패 방어
    try {
      await rootBundle.load('assets/fonts/NotoSansKR-Regular.ttf');
    } catch (e) {
      throw Exception('PDF 생성에 필요한 폰트를 로드할 수 없습니다: $e');
    }
    final biz = widget.business;
    final w = widget.worker;
    return PayslipData.fromAttendance(
      attendance: widget.attendance,
      workerName: _workerName,
      workerBirthDate: w?.birthDate != null
          ? FormatHelper.formatDateDot(w!.birthDate!)
          : '',
      businessNumber:  biz?.businessNumber ?? '',
      businessAddress: biz?.address       ?? '',
      ownerName:       biz?.ownerName     ?? '',
    );
  }

  String get _fileName {
    final date = FormatHelper.formatDateStamp(widget.attendance.workDate);
    return '${widget.attendance.businessName}_임금명세서_${_workerName}_$date.pdf';
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '임금명세서',
      actions: [
        IconButton(
          icon: const Icon(Icons.print_outlined, color: Colors.white),
          tooltip: '인쇄',
          onPressed: () => _print(),
        ),
        IconButton(
          icon: const Icon(Icons.share_outlined, color: Colors.white),
          tooltip: '공유',
          onPressed: () => _share(context),
        ),
      ],
      body: FutureBuilder<PayslipData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingWidget(message: '임금명세서 생성 중...');
          }
          if (snapshot.hasError) {
            return _buildError(context, snapshot.error.toString());
          }
          final data = snapshot.data!;
          return _buildPreview(context, data);
        },
      ),
    );
  }

  Widget _buildPreview(BuildContext context, PayslipData data) {
    return Column(
      children: [
        // 상단 정보 배너
        _InfoBanner(
          workerName: _workerName,
          businessName: widget.attendance.businessName,
          workDate: widget.attendance.workDate,
          netWage: data.wageDetail.effectiveNetWage,
        ),

        // PDF 핀치줌 뷰어 (직접 핀치로 확대/축소)
        Expanded(
          child: _PdfZoomViewer(
            pdfFuture: _pdfBytesFuture ??= PayslipPdfBuilder.build(data),
          ),
        ),
      ],
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 32)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: ResponsiveHelper.iconSize(context, 56), color: AppColors.error),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '임금명세서를 생성할 수 없습니다',
              style: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(color: AppColors.grey700),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              message.replaceAll('Exception: ', ''),
              textAlign: TextAlign.center,
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey500),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    try {
      final data = await _dataFuture;
      if (!mounted || data == null) return;
      _pdfBytesFuture ??= PayslipPdfBuilder.build(data);
      final bytes = await _pdfBytesFuture!;
      await Printing.sharePdf(bytes: bytes, filename: _fileName);
    } catch (e) {
      if (mounted) ToastHelper.showError('공유에 실패했습니다');
    }
  }

  Future<void> _print() async {
    try {
      final data = await _dataFuture;
      if (data == null || !mounted) return;
      _pdfBytesFuture ??= PayslipPdfBuilder.build(data);
      final bytes = await _pdfBytesFuture!;
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: _fileName,
      );
    } catch (e) {
      if (mounted) ToastHelper.showError('인쇄에 실패했습니다');
    }
  }
}

// ─── 상단 요약 배너 ───────────────────────────────────────────────

class _InfoBanner extends StatelessWidget {
  final String workerName;
  final String businessName;
  final DateTime workDate;
  final int netWage;

  const _InfoBanner({
    required this.workerName,
    required this.businessName,
    required this.workDate,
    required this.netWage,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      color: theme.primaryColor.withValues(alpha: 0.06),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$workerName · $businessName',
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  '근무일: ${FormatHelper.formatDateDot(workDate)}',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey500),
                ),
              ],
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '실수령액',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey500),
              ),
              Text(
                FormatHelper.formatWage(netWage),
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  color: theme.primaryColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── 핀치줌 PDF 뷰어 ─────────────────────────────────────────────
// Printing.raster() 로 PDF → 이미지 변환 후 InteractiveViewer 로 표시
// → 더블탭 없이 즉시 핀치줌 가능

class _PdfZoomViewer extends StatefulWidget {
  final Future<Uint8List> pdfFuture;
  const _PdfZoomViewer({required this.pdfFuture});

  @override
  State<_PdfZoomViewer> createState() => _PdfZoomViewerState();
}

class _PdfZoomViewerState extends State<_PdfZoomViewer> {
  late final Future<List<Uint8List>> _pagesFuture;

  @override
  void initState() {
    super.initState();
    _pagesFuture = _rasterPages();
  }

  Future<List<Uint8List>> _rasterPages() async {
    final bytes = await widget.pdfFuture;
    final pages = <Uint8List>[];
    await for (final page in Printing.raster(bytes, dpi: 150)) {
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
          return const LoadingWidget(message: 'PDF 렌더링 중...');
        }
        if (snap.hasError || snap.data == null || snap.data!.isEmpty) {
          return Center(
            child: Text('PDF를 불러올 수 없습니다',
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.error)),
          );
        }

        final pages = snap.data!;
        // LayoutBuilder로 화면 너비를 구해서 이미지를 맞춤
        return LayoutBuilder(
          builder: (ctx, constraints) {
            final pageWidth = constraints.maxWidth - 16; // 좌우 8px 여백
            return InteractiveViewer(
              // constrained: false → 줌인 시 화면 밖으로 스크롤 가능
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
                            // width를 화면에 맞게 고정 → 초기 렌더링 시 잘림 없음
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
