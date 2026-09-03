// lib/screens/business_admin/expiring_contracts_screen.dart
// 계약 종료 예정 전체화면 — PHASE 2D
//
// ExpiringContractsDialog(Modal) → ExpiringContractsScreen(Full Screen) 교체
// - 중첩 Dialog 제거 (Dialog 안에서 FixedWorkerManagementDialog 열기 → 허용)
// - gradient header / 통계 카드 제거
// - D-day 순 flat list
// - Error ≠ 0건 (별도 상태)

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/core/application_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/loading_widget.dart';
import 'dialogs/fixed_worker_management_dialog.dart';

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

class ExpiringContractsScreen extends StatefulWidget {
  final List<String> businessIds;
  final List<BusinessModel> businesses;

  const ExpiringContractsScreen({
    super.key,
    required this.businessIds,
    required this.businesses,
  });

  @override
  State<ExpiringContractsScreen> createState() =>
      _ExpiringContractsScreenState();
}

class _ExpiringContractsScreenState extends State<ExpiringContractsScreen> {
  final _svc = FirestoreService();
  List<_ExpiringItem> _items = [];
  bool _loading = true;
  bool _hasError = false;

  // [PHASE 2D] canonical range: D-0 to D-15 inclusive (CF와 동일)
  static const int _daysWindow = 15;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final today = DateTime.now();
      final todayOnly = FormatHelper.toKstDate(today);

      final perBusiness = await Future.wait(
        widget.businessIds.map((bizId) async {
          final apps = await _svc.getExpiringLongTermApplications(
            businessId: bizId,
            fromDate: todayOnly,
          );

          final inWindow = apps.where((app) {
            final end = app.actualResignDate ?? app.workEndDate;
            if (end == null) return false;
            final endOnly = FormatHelper.toKstDate(end);
            final diff = endOnly.difference(todayOnly).inDays;
            return diff >= 0 && diff <= _daysWindow;
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

      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ [계약종료예정] 화면 조회 실패: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  Color _dDayColor(BuildContext context, int days) {
    if (days <= 3) return AppColors.error;
    if (days <= 7) return AppColors.warning;
    return Theme.of(context).primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('계약 종료 예정'),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.grey800,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.border),
        ),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const LoadingWidget(message: '계약 현황 조회 중...');
    }
    if (_hasError) return _buildError(context);
    if (_items.isEmpty) return _buildEmpty(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCountHeader(context),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: _items.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, indent: 56),
            itemBuilder: (ctx, i) => _buildRow(ctx, _items[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildCountHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      child: Text(
        '계약 종료 예정 ${_items.length}명',
        style: ResponsiveHelper.bodyStyle(context).copyWith(
          color: AppColors.grey600,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.event_available, size: 48, color: AppColors.grey300),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Text(
            '곧 종료되는 계약이 없어요',
            style: ResponsiveHelper.bodyStyle(context,
                color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  Widget _buildError(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.grey300),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              '계약 종료 예정 정보를 불러오지 못했어요',
              style: ResponsiveHelper.bodyStyle(context,
                  color: AppColors.grey500),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            TextButton(
              onPressed: _loadData,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(BuildContext context, _ExpiringItem item) {
    final color = _dDayColor(context, item.daysRemaining);
    final name = item.user?.name ?? '알 수 없음';
    final bizName = item.business?.name ?? '';
    final endDate =
        item.application.actualResignDate ?? item.application.workEndDate;
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
        // FixedWorkerManagement에서 계약 처리 후 목록 갱신
        if (mounted) _loadData();
      },
      child: Row(
        children: [
          // D-day urgency 색상 바
          Container(
            width: 4,
            height: ResponsiveHelper.spacing(context, 56),
            color: color,
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
                    backgroundColor: color.withValues(alpha: 0.12),
                    child: Text(
                      name.isNotEmpty ? name[0] : '?',
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: color,
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
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          dayLabel,
                          style: ResponsiveHelper.smallStyle(context).copyWith(
                            color: color,
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
}
