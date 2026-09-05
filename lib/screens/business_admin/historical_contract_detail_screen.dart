import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';

import '../../models/core/historical_contract_detail.dart';
import '../../models/core/insurance_rate_model.dart';
import '../../services/historical_contract_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';

/// 보관된 계약서 상세 화면 — READ ONLY.
///
/// 서명/무효화/수정 등 운영 액션 없음.
/// PDF 저장/공유만 허용 (pdfUrl 있는 경우).
class HistoricalContractDetailScreen extends StatefulWidget {
  final String contractId;

  const HistoricalContractDetailScreen({
    super.key,
    required this.contractId,
  });

  @override
  State<HistoricalContractDetailScreen> createState() =>
      _HistoricalContractDetailScreenState();
}

class _HistoricalContractDetailScreenState
    extends State<HistoricalContractDetailScreen> {
  final _service = HistoricalContractService();

  HistoricalContractDetail? _detail;
  bool _isLoading = true;
  Object? _error;
  bool _isSharingPdf = false;

  // ─── 생명주기 ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadDetail();
  }

  // ─── 데이터 로드 ───────────────────────────────────────────

  Future<void> _loadDetail() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final detail =
          await _service.getHistoricalContractById(widget.contractId);
      if (!mounted) return;
      if (detail == null) {
        // 접근 불가 또는 존재하지 않음 — 목록으로 복귀
        ToastHelper.showError('계약서를 찾을 수 없습니다.');
        Navigator.of(context).pop();
        return;
      }
      setState(() {
        _detail = detail;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  // ─── PDF 공유 ──────────────────────────────────────────────

  Future<void> _sharePdf() async {
    final url = _detail?.pdfUrl;
    if (url == null || url.trim().isEmpty) return;
    if (_isSharingPdf) return;
    if (!mounted) return;
    setState(() => _isSharingPdf = true);
    try {
      final resp = await http.get(Uri.parse(url));
      if (!mounted) return;
      if (resp.statusCode != 200) {
        ToastHelper.showError('PDF를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.');
        return;
      }
      if (resp.bodyBytes.isEmpty) {
        ToastHelper.showError('PDF를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.');
        return;
      }
      await Printing.sharePdf(
        bytes: resp.bodyBytes,
        filename: 'ALfit_근로계약서.pdf',
      );
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('PDF를 불러오지 못했습니다. 잠시 후 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _isSharingPdf = false);
    }
  }

  // ─── 빌드 ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: '계약서 상세',
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const LoadingWidget(message: '계약서를 불러오는 중...');
    }
    if (_error != null) {
      return _buildError(context);
    }
    final detail = _detail;
    if (detail == null) return const SizedBox.shrink();
    return _buildDetail(context, detail);
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: ResponsiveHelper.iconSize(context, 48),
              color: AppColors.grey400,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '계약서를 불러오지 못했습니다.',
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(color: AppColors.textPrimary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(
              '잠시 후 다시 시도해 주세요.',
              style: ResponsiveHelper.captionStyle(context)
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
            OutlinedButton(
              onPressed: _loadDetail,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetail(BuildContext context, HistoricalContractDetail detail) {
    final snapshot = detail.snapshot;
    final workerName = _resolveWorkerName(detail);
    final businessName = _resolveBusinessName(detail);
    final dateInfo = _resolveDate(detail);
    final statusColors = _statusColors(detail.status);

    return SingleChildScrollView(
      padding: ResponsiveHelper.listPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ① 헤더 — 상태 + 당사자 요약
          _buildHeader(
            context,
            workerName: workerName,
            businessName: businessName,
            displayStatus: detail.displayStatus,
            statusColors: statusColors,
            dateInfo: dateInfo,
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          // ② 계약 당사자 / 근무 조건 / 임금 — snapshot 기반
          if (snapshot != null) ...[
            _DetailSection(
              title: '계약 당사자',
              children: [
                _InfoRow(label: '사업장명', value: snapshot.businessName),
                _InfoRow(label: '대표자', value: snapshot.ownerName),
                _InfoRow(label: '사업자번호', value: snapshot.businessNumber),
                _InfoRow(label: '소재지', value: snapshot.businessAddress),
                if (snapshot.businessPhone?.isNotEmpty == true)
                  _InfoRow(label: '연락처', value: snapshot.businessPhone!),
                const _SectionDivider(),
                _InfoRow(label: '근로자', value: snapshot.workerName),
                if (snapshot.workerBirthDate?.isNotEmpty == true)
                  _InfoRow(label: '생년월일', value: snapshot.workerBirthDate!),
                if (snapshot.workerPhone?.isNotEmpty == true)
                  _InfoRow(label: '연락처', value: snapshot.workerPhone!),
                if (snapshot.workerAddress?.isNotEmpty == true)
                  _InfoRow(label: '주소', value: snapshot.workerAddress!),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _DetailSection(
              title: '근무 조건',
              children: [
                _InfoRow(label: '근무 장소', value: snapshot.workPlace),
                _InfoRow(label: '담당 업무', value: snapshot.workType),
                if (snapshot.isLongTerm) ...[
                  _InfoRow(label: '근무 기간', value: snapshot.workPeriodText),
                  if (snapshot.workDays?.isNotEmpty == true)
                    _InfoRow(label: '근무 요일', value: snapshot.workDaysText),
                ] else
                  _InfoRow(
                    label: '근무 형태',
                    value: '단기 (${detail.slots.length}일)',
                  ),
                _InfoRow(label: '근무 시간', value: snapshot.workTimeText),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _DetailSection(
              title: '임금',
              children: [
                _InfoRow(
                  label: snapshot.wageTypeLabel,
                  value: snapshot.formattedWage,
                ),
                if (snapshot.hourlyWage != null)
                  _InfoRow(label: '통상시급', value: snapshot.formattedHourlyWage),
                _InfoRow(label: '지급 방법', value: snapshot.paymentMethod),
                if (snapshot.payScheduleTypeLabel.isNotEmpty)
                  _InfoRow(
                    label: '지급 방식',
                    value: snapshot.payScheduleTypeLabel,
                  ),
                _InfoRow(label: '지급 일정', value: snapshot.payScheduleLabel),
                if (snapshot.taxDeductionType != InsuranceRateModel.typeNone)
                  _InfoRow(
                    label: '공제 방식',
                    value:
                        InsuranceRateModel.typeLabel(snapshot.taxDeductionType),
                  ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          ] else ...[
            // snapshot 없음 — 세부 정보 미표시
            _buildSnapshotMissing(context),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          ],

          // ③ 근무 내역 (slots)
          if (detail.slots.isNotEmpty) ...[
            _DetailSection(
              title: '근무 내역',
              children: detail.slots.map((s) => _SlotRow(slot: s)).toList(),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          ],

          // ④ 계약 조항 (articles)
          ...detail.articles.map((a) {
            final hasTitle = a.title.trim().isNotEmpty;
            final hasContent = a.content.trim().isNotEmpty;
            if (!hasTitle && !hasContent) return const SizedBox.shrink();
            return Padding(
              padding: EdgeInsets.only(
                  bottom: ResponsiveHelper.spacing(context, 12)),
              child: _DetailSection(
                title: hasTitle ? a.title : '',
                children: [
                  if (hasContent) _Paragraph(content: a.content),
                ],
              ),
            );
          }),

          // ⑤ PDF 섹션
          _buildPdfSection(context, detail),

          SizedBox(height: ResponsiveHelper.spacing(context, 32)),
        ],
      ),
    );
  }

  // ─── 헤더 ──────────────────────────────────────────────────

  Widget _buildHeader(
    BuildContext context, {
    required String workerName,
    required String businessName,
    required String displayStatus,
    required ({Color bg, Color fg}) statusColors,
    required ({String label, DateTime? date}) dateInfo,
  }) {
    final formattedDate = dateInfo.date != null
        ? FormatHelper.formatDateDot(dateInfo.date!)
        : null;

    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 근로자명 + 상태 배지
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  workerName,
                  style: ResponsiveHelper.titleStyle(context)
                      .copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: ResponsiveHelper.spacing(context, 4),
                ),
                decoration: BoxDecoration(
                  color: statusColors.bg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  displayStatus,
                  style: ResponsiveHelper.captionStyle(context).copyWith(
                    color: statusColors.fg,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 4)),

          // 사업장명
          Text(
            businessName,
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(color: AppColors.textSecondary),
          ),

          // 날짜
          if (formattedDate != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: ResponsiveHelper.iconSize(context, 13),
                  color: AppColors.textSecondary,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '${dateInfo.label}  $formattedDate',
                  style: ResponsiveHelper.captionStyle(context)
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ─── snapshot 없음 알림 ────────────────────────────────────

  Widget _buildSnapshotMissing(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Text(
        '보관된 계약 세부 정보 일부를 표시할 수 없습니다.',
        style: ResponsiveHelper.captionStyle(context)
            .copyWith(color: AppColors.textSecondary),
      ),
    );
  }

  // ─── PDF 섹션 ──────────────────────────────────────────────

  Widget _buildPdfSection(
      BuildContext context, HistoricalContractDetail detail) {
    return _DetailSection(
      title: 'PDF',
      children: [
        if (detail.hasPdf)
          ElevatedButton.icon(
            onPressed: _isSharingPdf ? null : _sharePdf,
            icon: _isSharingPdf
                ? SizedBox(
                    width: ResponsiveHelper.iconSize(context, 16),
                    height: ResponsiveHelper.iconSize(context, 16),
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.picture_as_pdf_outlined),
            label: const Text('계약서 PDF 저장/공유'),
          )
        else
          Text(
            _noPdfCopy(detail),
            style: ResponsiveHelper.captionStyle(context)
                .copyWith(color: AppColors.textSecondary),
          ),
      ],
    );
  }

  // ─── 헬퍼 ─────────────────────────────────────────────────

  String _resolveWorkerName(HistoricalContractDetail detail) {
    final top = detail.workerName?.trim();
    if (top != null && top.isNotEmpty) return top;
    final snap = detail.snapshot?.workerName.trim();
    if (snap != null && snap.isNotEmpty) return snap;
    return '근로자 정보 없음';
  }

  String _resolveBusinessName(HistoricalContractDetail detail) {
    final top = detail.businessName?.trim();
    if (top != null && top.isNotEmpty) return top;
    final snap = detail.snapshot?.businessName.trim();
    if (snap != null && snap.isNotEmpty) return snap;
    return '사업장 정보 없음';
  }

  ({String label, DateTime? date}) _resolveDate(
      HistoricalContractDetail detail) {
    switch (detail.status) {
      case 'completed':
        return (
          label: '완료일',
          date: detail.workerSignedAt ??
              detail.employerSignedAt ??
              detail.createdAt,
        );
      case 'voided':
        return (
          label: '무효화일',
          date: detail.contractVoidedAt ?? detail.createdAt,
        );
      default:
        return (label: '등록일', date: detail.createdAt);
    }
  }

  ({Color bg, Color fg}) _statusColors(String? status) {
    switch (status) {
      case 'completed':
        return (bg: AppColors.successBg, fg: AppColors.successDark);
      case 'pending_employer':
      case 'pending_worker':
        return (bg: AppColors.warningBg, fg: AppColors.warningDark);
      case 'voided':
        return (bg: AppColors.grey100, fg: AppColors.grey600);
      default:
        return (bg: AppColors.grey100, fg: AppColors.grey600);
    }
  }

  String _noPdfCopy(HistoricalContractDetail detail) {
    if (detail.status == 'voided') {
      if (detail.voidReason == 'BUSINESS_DELETED') {
        return '사업장 삭제로 근로자 서명 전 계약이 종료되어 PDF가 생성되지 않았습니다.';
      }
      return '이 계약에는 저장/공유할 수 있는 PDF가 없습니다.';
    }
    if (detail.status == 'completed') {
      return '계약서 PDF를 찾을 수 없습니다.';
    }
    return '이 계약에는 저장/공유할 수 있는 PDF가 없습니다.';
  }
}

// ─── 섹션 컨테이너 ─────────────────────────────────────────────────

class _DetailSection extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _DetailSection({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 14),
                vertical: ResponsiveHelper.spacing(context, 10),
              ),
              child: Text(
                title,
                style: ResponsiveHelper.captionStyle(context).copyWith(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Divider(height: 1, color: AppColors.grey100),
          ],
          Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 키/값 행 ──────────────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 6)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: ResponsiveHelper.captionStyle(context)
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              value,
              style: ResponsiveHelper.captionStyle(context)
                  .copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── 섹션 구분선 ───────────────────────────────────────────────────

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 6)),
      child: const Divider(height: 1, color: AppColors.grey100),
    );
  }
}

// ─── 조항 본문 ─────────────────────────────────────────────────────

class _Paragraph extends StatelessWidget {
  final String content;

  const _Paragraph({required this.content});

  @override
  Widget build(BuildContext context) {
    return Text(
      content,
      style: ResponsiveHelper.captionStyle(context)
          .copyWith(color: AppColors.textPrimary, height: 1.6),
    );
  }
}

// ─── 슬롯 행 ──────────────────────────────────────────────────────

class _SlotRow extends StatelessWidget {
  final HistoricalContractSlot slot;

  const _SlotRow({required this.slot});

  String _wageTypeLabel(String? wageType) {
    switch (wageType) {
      case 'hourly':
        return '시급';
      case 'daily':
        return '일급';
      case 'monthly':
        return '월급';
      default:
        return '임금';
    }
  }

  @override
  Widget build(BuildContext context) {
    final workDate = slot.workDate;
    final hasTime = slot.startTime != null && slot.endTime != null;
    final hasWage = slot.wage != null;

    // 의미 있는 데이터가 전혀 없으면 미표시
    if (workDate == null && !hasTime && !hasWage) {
      return const SizedBox.shrink();
    }

    final parts = <String>[];
    if (workDate != null) parts.add(workDate);
    if (hasTime) parts.add('${slot.startTime} ~ ${slot.endTime}');
    if (hasWage) {
      final formatted = slot.wage.toString().replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]},',
          );
      parts.add('${_wageTypeLabel(slot.wageType)} $formatted원');
    }

    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 6)),
      child: Row(
        children: [
          Icon(
            Icons.circle,
            size: 5,
            color: AppColors.grey400,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              parts.join('  ·  '),
              style: ResponsiveHelper.captionStyle(context)
                  .copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
