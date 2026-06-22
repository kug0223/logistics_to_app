import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/core/application_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/business_work_type_model.dart';
import '../../models/core/to_model.dart';
import '../../models/core/work_detail_data.dart';
import '../../services/firestore_service.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/image_helper.dart';
import '../../theme/app_colors.dart';
import 'styled_dialog.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/tax_deduction_badge.dart';
import '../../widgets/work_type_icon.dart';

/// 내 스케줄 → 근무 상세 정보 BottomSheet
class ScheduleDetailDialog extends StatefulWidget {
  final ApplicationModel application;

  const ScheduleDetailDialog({super.key, required this.application});

  @override
  State<ScheduleDetailDialog> createState() => _ScheduleDetailDialogState();
}

class _ScheduleDetailDialogState extends State<ScheduleDetailDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = true;
  BusinessModel? _business;
  TOModel? _to;
  BusinessWorkTypeModel? _workType;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _firestoreService.getBusinessById(widget.application.businessId),
        _firestoreService.getTOByApplication(widget.application),
      ]);
      final biz = results[0] as BusinessModel?;
      final to = results[1] as TOModel?;

      // 업무유형 상세 정보 로드
      BusinessWorkTypeModel? wt;
      if (biz != null) {
        try {
          final wts = await _firestoreService.getBusinessWorkTypes(biz.id);
          wt = wts.firstWhere(
            (w) => w.name == widget.application.selectedWorkType,
            orElse: () => wts.isEmpty ? throw StateError('empty') : wts.first,
          );
        // [특이사항] 업무유형 조회 실패 시 wt=null 유지 — UI가 null을 폴백으로 처리함
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() {
        _business = biz;
        _to = to;
        _workType = wt;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 상세 정보 로드 실패: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  // ─── 매칭 WorkDetail ───────────────────────────────────────
  WorkDetailData? get _workDetail {
    if (_to == null) return null;
    final app = widget.application;
    return _to!.workDetails.firstWhere(
      (d) => d.workType == app.selectedWorkType && d.startTime == app.startTime,
      orElse: () => _to!.workDetails.firstWhere(
        (d) => d.workType == app.selectedWorkType,
        orElse: () => _to!.workDetails.isEmpty
            ? WorkDetailData(
                workType: app.selectedWorkType,
                wage: app.wage,
                wageType: app.wageType ?? 'daily',
                requiredCount: 0,
                startTime: app.startTime,
                endTime: app.endTime,
              )
            : _to!.workDetails.first,
      ),
    );
  }

  // ─── 상태 배지 정보 ───────────────────────────────────────
  ({String label, Color bg, Color fg}) get _statusInfo {
    final status = widget.application.status;
    if (AppStatus.confirmedStatuses.contains(status)) {
      return (label: '확정', bg: AppColors.successBg, fg: AppColors.successDark);
    }
    if (status == AppStatus.pending || status == AppStatus.contractPending) {
      return (label: '대기중', bg: AppColors.warningBg, fg: AppColors.warningDark);
    }
    return (label: '취소', bg: AppColors.grey100, fg: AppColors.grey500);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
      ),
      decoration: const BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 12)),
            width: ResponsiveHelper.spacing(context, 40),
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          _buildHeader(context, theme),
          // Content
          Flexible(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: LoadingWidget(),
                  )
                : SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      ResponsiveHelper.spacing(context, 16),
                      0,
                      ResponsiveHelper.spacing(context, 16),
                      // useSafeArea가 edge-to-edge에서 동작 안 할 수 있음.
                      // viewPaddingOf는 SafeArea 소비 여부와 무관하게 물리적 인셋을 반환.
                      // max 사용: SafeArea가 동작했을 때 이중 합산 방지.
                      max(
                        ResponsiveHelper.spacing(context, 24),
                        MediaQuery.viewPaddingOf(context).bottom,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                        _buildWorkDetailCard(context, theme),
                        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                        _buildBusinessCard(context, theme),
                        if (_to?.description?.isNotEmpty == true) ...[
                          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                          _buildDescriptionCard(context),
                        ],
                        if (_business?.precautions?.isNotEmpty == true) ...[
                          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                          _buildPrecautionsCard(context),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ─── 헤더 ────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    final app = widget.application;
    final si = _statusInfo;
    final isLong = app.isLongTermApplication;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 14),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.grey100)),
      ),
      child: Row(
        children: [
          // 날짜 + 업무유형 정보
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // 날짜 배지
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 8),
                        vertical: ResponsiveHelper.spacing(context, 3),
                      ),
                      decoration: BoxDecoration(
                        color: isLong ? AppColors.longTermBg : AppColors.shortTermBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isLong
                            ? (app.workDaysDisplay ?? '장기')
                            : FormatHelper.formatDateCompact(app.workDate),
                        style: ResponsiveHelper.tinyStyle(context,
                            color: isLong
                                ? AppColors.longTermDark
                                : AppColors.shortTermDark,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    // 상태 배지
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 8),
                        vertical: ResponsiveHelper.spacing(context, 3),
                      ),
                      decoration: BoxDecoration(
                        color: si.bg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        si.label,
                        style: ResponsiveHelper.tinyStyle(context,
                            color: si.fg, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                Text(
                  app.businessName,
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (_to != null)
                  Text(
                    _to!.title,
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            color: AppColors.grey500,
          ),
        ],
      ),
    );
  }

  // ─── 업무 상세 카드 ───────────────────────────────────────
  Widget _buildWorkDetailCard(BuildContext context, ThemeData theme) {
    final app = widget.application;
    final wd = _workDetail;

    final netTime = FormatHelper.calcNetWorkTime(
      app.startTime, app.endTime,
      breakMinutes: wd?.breakMinutes ?? 0,
    );

    final wageColor = app.wageType == 'daily'
        ? AppColors.warningDark
        : AppColors.successDark;

    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 타이틀
          CommonWidgets.sectionHeader(
            context: context,
            title: '업무 상세',
            icon: Icons.work_outline,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),

          // 업무 유형 행 — 탭 시 업무 상세 보기
          InkWell(
            onTap: () => _showWorkDetail(context),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 4)),
              child: Row(
                children: [
                  WorkTypeIcon.buildWithBackground(
                    iconString: app.workTypeIcon ?? '📋',
                    iconColor: app.workTypeColor ?? '#2196F3',
                    backgroundColor: app.workTypeBackgroundColor ?? '#E3F2FD',
                    size: ResponsiveHelper.iconSize(context, 20),
                    containerSize: ResponsiveHelper.iconSize(context, 40),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.selectedWorkType,
                          style: ResponsiveHelper.subtitleStyle(context)
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          '업무 상세 보기',
                          style: ResponsiveHelper.tinyStyle(context,
                              color: theme.primaryColor),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: ResponsiveHelper.iconSize(context, 18),
                      color: AppColors.grey400),
                ],
              ),
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
          Divider(height: 1, color: AppColors.grey100),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),

          // 근무 시간
          _infoRow(
            context,
            icon: Icons.access_time,
            iconColor: AppColors.info,
            label: '근무 시간',
            child: Row(
              children: [
                Text(
                  '${app.startTime} ~ ${app.endTime}',
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                if (netTime.isNotEmpty) ...[
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Text(
                    '($netTime)',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey500),
                  ),
                ],
              ],
            ),
          ),

          // 지원 마감은 이미 지원 완료 상태이므로 표시하지 않음

          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // 급여
          _infoRow(
            context,
            icon: Icons.payments_outlined,
            iconColor: wageColor,
            label: '급여',
            child: Row(
              children: [
                Text(
                  '${FormatHelper.formatNumber(app.wage)}원/${app.wageTypeLabel}',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: wageColor,
                  ),
                ),
                if (wd?.payScheduleTypeLabel.isNotEmpty == true) ...[
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 6),
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: wageColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      wd!.payScheduleTypeLabel,
                      style: ResponsiveHelper.tinyStyle(context,
                          color: wageColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // 입금일 상세
          if (wd?.payScheduleDetail.isNotEmpty == true) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _infoRow(
              context,
              icon: Icons.account_balance_wallet_outlined,
              iconColor: AppColors.grey500,
              label: '입금 예정',
              child: Text(
                '${wd!.payScheduleDetail} 입금',
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],

          // 공제 방식
          if (wd != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _infoRow(
              context,
              icon: Icons.receipt_long_outlined,
              iconColor: AppColors.grey500,
              label: '공제 방식',
              child: TaxDeductionBadge.chip(
                  taxDeductionType: wd.taxDeductionType),
            ),
          ],

          // 장기 근무 정보
          if (app.isLongTermApplication) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _infoRow(
              context,
              icon: Icons.date_range,
              iconColor: AppColors.longTerm,
              label: '근무 기간',
              child: Text(
                app.workPeriodDisplay,
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            if (app.workDaysDisplay != null) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              _infoRow(
                context,
                icon: Icons.event_repeat,
                iconColor: AppColors.longTerm,
                label: '근무 요일',
                child: Text(
                  app.workDaysDisplay!,
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ─── 사업장 카드 ──────────────────────────────────────────
  Widget _buildBusinessCard(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommonWidgets.sectionHeader(
            context: context,
            title: '사업장 정보',
            icon: Icons.business_outlined,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),

          // 사업장명
          _infoRow(
            context,
            icon: Icons.store_outlined,
            iconColor: theme.primaryColor,
            label: '사업장명',
            child: Text(
              widget.application.businessName,
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),

          // 주소
          if (_business?.address.isNotEmpty == true) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _infoRow(
              context,
              icon: Icons.location_on_outlined,
              iconColor: AppColors.error,
              label: '주소',
              child: Text(
                _business!.address,
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ],

          // 전화 버튼
          if (_business?.phone?.isNotEmpty == true) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 14)),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _call(_business!.phone!),
                icon: const Icon(Icons.phone_outlined),
                label: Text('전화하기  ${_business!.phone}'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.success,
                  side: const BorderSide(color: AppColors.success),
                  padding: EdgeInsets.symmetric(
                    vertical: ResponsiveHelper.spacing(context, 12),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 업무 설명 카드 ───────────────────────────────────────
  Widget _buildDescriptionCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.article_outlined,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: AppColors.infoDark),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                '업무 설명',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.infoDark, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            _to!.description!,
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.grey700),
          ),
        ],
      ),
    );
  }

  // ─── 준비사항 카드 ────────────────────────────────────────
  Widget _buildPrecautionsCard(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warningLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning_amber_outlined,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: AppColors.warningDark),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                '준비사항',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.warningDark, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            _business!.precautions!,
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.grey700),
          ),
        ],
      ),
    );
  }

  // ─── 공통 정보 행 ──────────────────────────────────────────
  Widget _infoRow(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required Widget child,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: ResponsiveHelper.iconSize(context, 30),
          height: ResponsiveHelper.iconSize(context, 30),
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon,
              size: ResponsiveHelper.iconSize(context, 16), color: iconColor),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 10)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey500),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
              child,
            ],
          ),
        ),
      ],
    );
  }

  // ─── 업무 상세 BottomSheet ──────────────────────────────
  void _showWorkDetail(BuildContext context) {
    final app = widget.application;
    final wd = _workDetail;
    final wt = _workType;
    final hasDetail = wt != null &&
        (wt.description != null ||
            wt.thumbnailUrl != null ||
            wt.images?.isNotEmpty == true);

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.65,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: EdgeInsets.symmetric(
                    vertical: ResponsiveHelper.spacing(ctx, 12)),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: AppColors.grey300,
                    borderRadius: BorderRadius.circular(2)),
              ),
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: () {
                    final cp = ResponsiveHelper.cardPadding(ctx);
                    return EdgeInsets.fromLTRB(
                      cp.left,
                      cp.top,
                      cp.right,
                      // edge-to-edge 대응: viewPaddingOf는 SafeArea 소비 무관 물리적 인셋.
                      // max로 SafeArea 정상 동작 시 이중 합산 방지.
                      max(cp.bottom, MediaQuery.viewPaddingOf(ctx).bottom),
                    );
                  }(),
                  children: [
                    // 헤더
                    Row(
                      children: [
                        WorkTypeIcon.buildWithBackground(
                          iconString: app.workTypeIcon ?? '📋',
                          iconColor: app.workTypeColor ?? '#2196F3',
                          backgroundColor:
                              app.workTypeBackgroundColor ?? '#E3F2FD',
                          size: ResponsiveHelper.iconSize(ctx, 26),
                          containerSize: ResponsiveHelper.iconSize(ctx, 52),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(ctx, 14)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(app.selectedWorkType,
                                  style:
                                      ResponsiveHelper.titleStyle(ctx).copyWith(
                                    fontWeight: FontWeight.bold,
                                  )),
                              if (wt?.oneLineIntro != null)
                                Text(wt!.oneLineIntro!,
                                    style: ResponsiveHelper.smallStyle(ctx,
                                        color: AppColors.grey600)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(ctx, 20)),
                    Divider(height: 1, color: AppColors.grey200),
                    SizedBox(height: ResponsiveHelper.spacing(ctx, 20)),

                    // 근무 시간
                    _detailItem(ctx, Icons.schedule_outlined, '근무 시간',
                        '${app.startTime} ~ ${app.endTime}'),
                    SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),

                    // 급여
                    _detailItem(
                      ctx,
                      Icons.payments_outlined,
                      '급여',
                      () {
                        final base =
                            '${app.wageTypeLabel} ${app.formattedWage}';
                        final sched = wd?.payScheduleTypeLabel ?? '';
                        return sched.isNotEmpty ? '$base · $sched' : base;
                      }(),
                    ),

                    // 입금일
                    if (wd?.payScheduleDetail.isNotEmpty == true) ...[
                      SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
                      _detailItem(ctx,
                          Icons.account_balance_wallet_outlined,
                          '입금일', wd!.payScheduleDetail),
                    ],

                    // 업무유형 상세 (등록된 경우)
                    if (hasDetail) ...[
                      SizedBox(height: ResponsiveHelper.spacing(ctx, 24)),
                      Divider(height: 1, color: AppColors.grey200),
                      SizedBox(height: ResponsiveHelper.spacing(ctx, 20)),
                      _buildWorkTypeImages(ctx, wt),
                      if (wt.description != null) ...[
                        SizedBox(height: ResponsiveHelper.spacing(ctx, 16)),
                        _detailItem(ctx, Icons.description_outlined,
                            '업무 설명', wt.description!),
                      ],
                      if (wt.workEnvironment != null) ...[
                        SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
                        _detailItem(ctx, Icons.thermostat_outlined,
                            '근무 환경', wt.workEnvironment!),
                      ],
                      if (wt.requirements != null) ...[
                        SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
                        _detailItem(ctx, Icons.checklist_outlined,
                            '자격 요건', wt.requirements!),
                      ],
                      if (wt.duties != null) ...[
                        SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
                        _detailItem(ctx, Icons.task_alt_outlined,
                            '주요 업무', wt.duties!),
                      ],
                      if (wt.precautions != null) ...[
                        SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
                        CommonWidgets.infoCard(
                          context: ctx,
                          message: wt.precautions!,
                          icon: Icons.warning_amber_outlined,
                          color: AppColors.warningDark,
                        ),
                      ],
                    ] else ...[
                      SizedBox(height: ResponsiveHelper.spacing(ctx, 24)),
                      Center(
                        child: Text('업무 유형 상세 정보가 등록되지 않았습니다.',
                            style: ResponsiveHelper.smallStyle(ctx,
                                color: AppColors.grey400)),
                      ),
                    ],
                    SizedBox(height: ResponsiveHelper.spacing(ctx, 32)),
                    CommonWidgets.outlineButton(
                      context: ctx,
                      text: '닫기',
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icons.close,
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(ctx, 16)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailItem(
      BuildContext context, IconData icon, String title, String content) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon,
                size: ResponsiveHelper.iconSize(context, 18),
                color: theme.primaryColor),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(title,
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
          decoration: BoxDecoration(
            color: AppColors.grey100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(content,
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(height: 1.5, color: AppColors.grey700)),
        ),
      ],
    );
  }

  Widget _buildWorkTypeImages(
      BuildContext context, BusinessWorkTypeModel wt) {
    final images = <String>[
      if (wt.thumbnailUrl != null) wt.thumbnailUrl!,
      if (wt.images != null) ...wt.images!,
    ];
    if (images.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        itemBuilder: (_, i) => Container(
          width: 240,
          margin: EdgeInsets.only(
              right: ResponsiveHelper.spacing(context, 12)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ImageHelper.buildCachedImage(images[i],
                fit: BoxFit.cover,
                memCacheWidth: 720,
                memCacheHeight: 540),
          ),
        ),
      ),
    );
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}
