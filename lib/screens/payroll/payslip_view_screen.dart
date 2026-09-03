// lib/screens/payroll/payslip_view_screen.dart
//
// 임금명세서 PDF Preview 화면 (PAYSLIP-FINAL)
//
// 역할:
//   - 진입 즉시 공식 A4 임금명세서 PDF를 Full-screen으로 표시
//   - PayslipData 구성 → PDF lazy 생성 → 핀치줌 뷰어
//   - AppBar: ← 임금명세서 | 인쇄(blue) | 공유(blue)
//   - Document Viewer 스타일: 흰 AppBar + #F5F6F8 배경 (GradientScaffold 아님)
//
// Navigation:
//   WageDetailDialog / ScheduleCard / PayrollWorkerDetailScreen
//   → PayslipViewScreen (직접 PDF 진입, 중간 Mobile Payslip 화면 없음)
//
// PayslipPdfBuilder / WageDetailModel / CF 로직 변경 없음

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
  /// PayslipData 구성 Future
  Future<PayslipData>? _dataFuture;

  /// PDF bytes lazy cache — _pdfBytes getter로만 접근
  /// initState에서 미시작, _dataFuture 완료 후 최초 PDF 뷰어 빌드 시 시작
  Future<Uint8List>? _pdfBytesFuture;

  /// 공유/인쇄 작업 진행 중 여부 (중복 탭 방지)
  bool _isActing = false;

  /// [V3 FOREIGN-DOCUMENT-FIRST] officialName 우선 (외국인=legalName, 내국인=name)
  String get _workerName =>
      widget.worker?.officialName ?? widget.workerNameOverride ?? '근무자';

  /// PDF bytes lazy getter — _dataFuture 완료 후 최초 접근 시만 PayslipPdfBuilder.build() 실행
  Future<Uint8List> get _pdfBytes {
    _pdfBytesFuture ??=
        _dataFuture!.then((data) => PayslipPdfBuilder.build(data));
    return _pdfBytesFuture!;
  }

  @override
  void initState() {
    super.initState();
    _dataFuture = _buildData();
    // PDF는 on-demand — PayslipData 준비 완료 후 뷰어 빌드 시 자동 시작
  }

  Future<PayslipData> _buildData() async {
    if (widget.attendance.wageDetail == null) {
      throw Exception('급여 정보가 없습니다. 관리자에게 문의해주세요.');
    }
    // [PERF-5] 폰트 사전 로드 + 캐시 — build() 호출 시 캐시 히트로 재파싱 방지
    try {
      await PayslipPdfBuilder.loadFonts();
    } catch (e) {
      throw Exception('PDF 생성에 필요한 폰트를 로드할 수 없습니다: $e');
    }
    final biz = widget.business;
    final w = widget.worker;
    // 지급일(transferDate/paymentDueDate)은 fromAttendance() 내부에서
    // wageStatus 기반으로 자동 파생된다 — 별도 전달 불필요 (PAYSLIP-07)
    // 사업장 주소·사업자번호·대표자명은 현재 스펙상 불필요하므로 의도적으로 생략
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

  // ── Document Viewer 색상 상수 ─────────────────────────────────────
  // GradientScaffold를 쓰지 않는 이유:
  //   이 화면은 ALfit 메인 내비게이션 화면이 아니라 공식 문서를 열어보는 뷰어다.
  //   상단 전체 Blue Header + Home/Notification 버튼은 문서 집중을 방해한다.
  //   Brand Blue는 인쇄/공유 액션 accent으로만 사용한다.
  static const _kViewerBg  = Color(0xFFF5F6F8); // 문서 주변 배경
  static const _kBarBg     = Colors.white;       // AppBar 배경
  static const _kBarDivider = Color(0xFFEEEEEE); // AppBar 하단 divider
  static const _kBackIcon   = Color(0xFF212121); // 뒤로가기 아이콘 (dark neutral)
  static const _kTitleColor = Color(0xFF212121); // 제목 텍스트
  static const _kActionColor = AppColors.brand;  // 인쇄/공유 아이콘 (#1565C0)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kViewerBg,
      // ── Document Viewer AppBar: 흰 배경, 하단 구분선, brand blue 액션
      appBar: AppBar(
        backgroundColor: _kBarBg,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        // 뒤로가기
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: _kBackIcon),
          tooltip: '뒤로',
          onPressed: () => Navigator.of(context).pop(),
        ),
        // 제목
        title: const Text(
          '임금명세서',
          style: TextStyle(
            color: _kTitleColor,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.3,
          ),
        ),
        // 액션: 인쇄 + 공유 (brand blue)
        actions: [
          IconButton(
            icon: const Icon(Icons.print_outlined, color: _kActionColor),
            tooltip: '인쇄',
            onPressed: _isActing ? null : _print,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined, color: _kActionColor),
            tooltip: '공유',
            onPressed: _isActing ? null : _share,
          ),
          const SizedBox(width: 4),
        ],
        // 하단 구분선
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(
            height: 1,
            thickness: 1,
            color: _kBarDivider,
          ),
        ),
      ),
      body: FutureBuilder<PayslipData>(
        future: _dataFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingWidget(message: '임금명세서 준비 중...');
          }
          if (snapshot.hasError) {
            return _buildError(context, snapshot.error.toString());
          }
          // PayslipData 준비 완료 → PDF lazy 빌드 시작 (_pdfBytes getter)
          return _PdfZoomViewer(pdfFuture: _pdfBytes);
        },
      ),
    );
  }

  Widget _buildError(BuildContext context, String message) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 32)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: ResponsiveHelper.iconSize(context, 56),
                color: AppColors.error),
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

  Future<void> _share() async {
    if (_isActing) return;
    setState(() => _isActing = true);
    try {
      final bytes = await _pdfBytes;
      await Printing.sharePdf(bytes: bytes, filename: _fileName);
    } catch (e) {
      if (mounted) ToastHelper.showError('공유에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
  }

  Future<void> _print() async {
    if (_isActing) return;
    setState(() => _isActing = true);
    try {
      final bytes = await _pdfBytes;
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: _fileName,
      );
    } catch (e) {
      if (mounted) ToastHelper.showError('인쇄에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isActing = false);
    }
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
        // ─ fitWidth 뷰어 ──────────────────────────────────────────
        // 클리핑 방어:
        //   InteractiveViewer(constrained: false)는 자식에게 무한 제약을 주므로
        //   Padding+Container 합산이 뷰포트와 정확히 일치해도
        //   부동소수점 차이로 우측 1-2px 클리핑이 발생할 수 있다.
        //   → SizedBox(width: viewW)로 자식 폭을 뷰포트와 명시적으로 동일하게
        //     고정하면 이 문제가 완전히 해소된다.
        return LayoutBuilder(
          builder: (ctx, constraints) {
            final viewW = constraints.maxWidth; // 뷰포트 폭(= SizedBox 폭)
            final imgW = viewW - 24;            // 좌우 12px 여백 확보

            return InteractiveViewer(
              constrained: false,   // 세로 스크롤 + 핀치줌 허용
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 5.0,
              child: SizedBox(
                // ← 핵심 수정: 자식을 뷰포트 폭에 명시 고정 (우측 잘림 방지)
                width: viewW,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    children: pages
                        .map((pageBytes) => Padding(
                              // 좌우 12px 여백 → 그림자 출혈 없이 안전 확보
                              padding:
                                  const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.08),
                                      blurRadius: 8,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                                child: Image.memory(
                                  pageBytes,
                                  width: imgW,
                                  fit: BoxFit.fitWidth,
                                ),
                              ),
                            ))
                        .toList(),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
