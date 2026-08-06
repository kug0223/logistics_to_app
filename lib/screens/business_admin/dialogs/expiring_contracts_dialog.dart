import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/core/application_model.dart';
import '../../../models/core/business_model.dart';
import '../../../models/core/user_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/loading_state_mixin.dart';
import '../../../utils/responsive_helper.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import 'fixed_worker_management_dialog.dart';

class _ExpiringItem {
  final ApplicationModel application;
  final UserModel? user;
  final BusinessModel? business;
  final int daysRemaining;

  const _ExpiringItem({
    required this.application,
    this.user,
    required this.business,
    required this.daysRemaining,
  });
}

class ExpiringContractsDialog extends StatefulWidget {
  final List<String> businessIds;
  final List<BusinessModel> businesses;

  const ExpiringContractsDialog({
    super.key,
    required this.businessIds,
    required this.businesses,
  });

  @override
  State<ExpiringContractsDialog> createState() => _ExpiringContractsDialogState();
}

class _ExpiringContractsDialogState extends State<ExpiringContractsDialog>
    with LoadingStateMixin {
  final _svc = FirestoreService();
  List<_ExpiringItem> _items = [];

  static const int _daysWindow = 15;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await runWithLoading(() async {
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);

      final perBusiness = await Future.wait(
        widget.businessIds.map((bizId) async {
          final apps = await _svc.getExpiringLongTermApplications(
            businessId: bizId,
            fromDate: todayOnly,
          );

          final inWindow = apps.where((app) {
            final end = app.actualResignDate ?? app.workEndDate;
            if (end == null) return false;
            final endOnly = DateTime(end.year, end.month, end.day);
            return endOnly.difference(todayOnly).inDays <= _daysWindow;
          }).toList();

          if (inWindow.isEmpty) return <_ExpiringItem>[];

          final uids = inWindow.map((a) => a.uid).toSet().toList();
          final userMap = await _svc.getUsersBatch(uids, businessId: bizId);

          BusinessModel? biz;
          try {
            biz = widget.businesses.firstWhere((b) => b.id == bizId);
          } catch (_) {}

          return inWindow.map((app) {
            final end = app.actualResignDate ?? app.workEndDate;
            final endOnly = DateTime(end!.year, end.month, end.day);
            final diff = endOnly.difference(todayOnly).inDays;
            return _ExpiringItem(
              application: app,
              user: userMap[app.uid],
              business: biz,
              daysRemaining: diff,
            );
          }).toList();
        }),
      );

      final items = perBusiness.expand((e) => e).toList()
        ..sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));

      if (mounted) setState(() => _items = items);
    });
  }

  Color _barColor(int days, ThemeData theme) {
    if (days <= 3) return AppColors.error;
    if (days <= 7) return AppColors.warning;
    return theme.primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppDialogSize.borderRadius),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, AppDialogSize.insetH),
        vertical: AppDialogSize.insetV,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, theme),
            if (!isLoading) _buildSummaryCard(context),
            Expanded(
              child: isLoading
                  ? const LoadingWidget(message: '계약 현황 조회 중...')
                  : _items.isEmpty
                      ? _buildEmptyState(context)
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(context, 8),
                          ),
                          itemCount: _items.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1, indent: 56),
                          itemBuilder: (_, i) =>
                              _buildWorkerRow(context, theme, _items[i]),
                        ),
            ),
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.warning,
            AppColors.warning.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppDialogSize.borderRadius),
          topRight: Radius.circular(AppDialogSize.borderRadius),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.calendar_month_outlined,
              color: Colors.white,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '계약 종료 예정',
                style: ResponsiveHelper.titleStyle(context).copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'D-15 이내 만료 임박 근무자',
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  color: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            onPressed: () => Navigator.pop(context),
            tooltip: '닫기',
            icon: Icon(
              Icons.close,
              color: Colors.white,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(BuildContext context) {
    final urgent = _items.where((i) => i.daysRemaining <= 3).length;
    final soon =
        _items.where((i) => i.daysRemaining > 3 && i.daysRemaining <= 7).length;

    return Container(
      margin: ResponsiveHelper.cardPadding(context),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildStatItem(context, '총 인원', '${_items.length}명', AppColors.grey600),
          _vDivider(context),
          _buildStatItem(context, 'D-3 이내', '$urgent명', AppColors.error),
          _vDivider(context),
          _buildStatItem(context, 'D-7 이내', '$soon명', AppColors.warning),
        ],
      ),
    );
  }

  Widget _vDivider(BuildContext context) => Container(
        width: 1,
        height: ResponsiveHelper.spacing(context, 30),
        color: AppColors.border,
      );

  Widget _buildStatItem(
      BuildContext context, String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
        Text(
          label,
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.cardPadding(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_available, size: 48, color: AppColors.grey300),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              'D-15 이내 종료 예정 근무자가 없습니다',
              style:
                  ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkerRow(
      BuildContext context, ThemeData theme, _ExpiringItem item) {
    final barColor = _barColor(item.daysRemaining, theme);
    final name = item.user?.name ?? '알 수 없음';
    final bizName = item.business?.name ?? '';
    final endDate = item.application.actualResignDate ?? item.application.workEndDate;
    final dateStr = endDate != null
        ? DateFormat('M/d(E)', 'ko_KR').format(endDate)
        : '-';
    final dayLabel =
        item.daysRemaining == 0 ? 'D-Day' : 'D-${item.daysRemaining}';

    return InkWell(
      onTap: () async {
        final biz = item.business;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => FixedWorkerManagementDialog(
            businessIds: [item.application.businessId],
            businesses: biz != null ? [biz] : widget.businesses,
            initialBusinessId: item.application.businessId,
            initialWorkerUid: item.application.uid,
            onChanged: () {},
          ),
        );
        if (mounted) _loadData();
      },
      child: Row(
        children: [
          Container(
            width: 4,
            height: ResponsiveHelper.spacing(context, 56),
            color: barColor,
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 16),
                vertical: ResponsiveHelper.spacing(context, 10),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: ResponsiveHelper.spacing(context, 18),
                    backgroundColor: barColor.withValues(alpha: 0.12),
                    child: Text(
                      name.isNotEmpty ? name[0] : '?',
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: barColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (bizName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            bizName,
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.grey500),
                          ),
                        ],
                      ],
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        dateStr,
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey600),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 8),
                          vertical: ResponsiveHelper.spacing(context, 3),
                        ),
                        decoration: BoxDecoration(
                          color: barColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          dayLabel,
                          style: ResponsiveHelper.smallStyle(context).copyWith(
                            color: barColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(AppDialogSize.borderRadius),
          bottomRight: Radius.circular(AppDialogSize.borderRadius),
        ),
        border: const Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: () => Navigator.pop(context),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.grey200,
            foregroundColor: AppColors.grey700,
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 14),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: 0,
          ),
          child: Text(
            '닫기',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
