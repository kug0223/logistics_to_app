// lib/screens/business_admin/payroll/today_payment_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/core/attendance_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/firestore_service.dart';
import '../../../services/payroll_payment_service.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/payment_due_date_calculator.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/payroll_excel_helper.dart';
import '../../../models/core/wage_detail_model.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/common/gradient_scaffold.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_batch_action_bar.dart';

// 로컬 퀵필터
enum _QuickFilter { all, overdue, today }

class TodayPaymentScreen extends StatefulWidget {
  final String businessId;
  final String? businessName;

  const TodayPaymentScreen({
    super.key,
    required this.businessId,
    this.businessName,
  });

  @override
  State<TodayPaymentScreen> createState() => _TodayPaymentScreenState();
}

class _TodayPaymentScreenState extends State<TodayPaymentScreen> {
  final _payService = PayrollPaymentService();
  final _fsService  = FirestoreService();

  bool _isLoading    = true;
  bool _isProcessing = false;
  List<AttendanceModel> _records = [];
  Map<String, List<AttendanceModel>> _groupedCache = {};
  final Set<String> _selectedIds = {};
  bool _batchMode = false;
  _QuickFilter _quickFilter = _QuickFilter.all;

  // uid → 근무자 이름 캐시
  final Map<String, String> _nameCache = {};

  // ── 날짜 ──────────────────────────────────────────────────
  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  bool _isOverdue(DateTime? due) =>
      due != null &&
      DateTime(due.year, due.month, due.day).isBefore(_today);

  bool _isDueToday(DateTime? due) =>
      due != null &&
      DateTime(due.year, due.month, due.day) == _today;

  // ── 로드 ──────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final records = await _payService.getTodayPayments(
        businessId: widget.businessId,
      );

      final uids = records.map((r) => r.userId).toSet()
          .difference(_nameCache.keys.toSet());
      if (uids.isNotEmpty) {
        final users =
            await Future.wait(uids.map((uid) => _fsService.getUser(uid)));
        for (int i = 0; i < uids.length; i++) {
          final user = users[i];
          if (user != null) _nameCache[uids.elementAt(i)] = user.name;
        }
      }

      if (!mounted) return;
      final map = <String, List<AttendanceModel>>{};
      for (final r in records) {
        final key = r.wageDetail?.payScheduleType ?? 'unknown';
        (map[key] ??= []).add(r);
      }
      final sortedKeys = map.keys.toList()
        ..sort((a, b) => PaymentDueDateCalculator.sortOrder(a)
            .compareTo(PaymentDueDateCalculator.sortOrder(b)));

      if (mounted) {
        setState(() {
          _records      = records;
          _groupedCache = {for (final k in sortedKeys) k: map[k]!};
          _selectedIds.clear();
          _batchMode = false;
        });
      }
    } catch (e) {
      debugPrint('❌ 급여 목록 로드 실패: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── 필터된 레코드 ─────────────────────────────────────────
  List<AttendanceModel> get _filteredRecords {
    switch (_quickFilter) {
      case _QuickFilter.overdue:
        return _records.where((r) => _isOverdue(r.paymentDueDate)).toList();
      case _QuickFilter.today:
        return _records.where((r) => _isDueToday(r.paymentDueDate)).toList();
      case _QuickFilter.all:
        return _records;
    }
  }

  Map<String, List<AttendanceModel>> get _filteredGrouped {
    final filtered = _filteredRecords;
    if (filtered.length == _records.length) return _groupedCache;
    final map = <String, List<AttendanceModel>>{};
    for (final r in filtered) {
      (map[r.wageDetail?.payScheduleType ?? 'unknown'] ??= []).add(r);
    }
    final sortedKeys = map.keys.toList()
      ..sort((a, b) => PaymentDueDateCalculator.sortOrder(a)
          .compareTo(PaymentDueDateCalculator.sortOrder(b)));
    return {for (final k in sortedKeys) k: map[k]!};
  }

  int get _totalAmount => _records.fold(0, (s, r) {
        final wd = r.wageDetail;
        if (wd == null) return s;
        return s + (wd.netWage > 0 ? wd.netWage : wd.totalAmount);
      });

  int get _selectedAmount => _records
      .where((r) => _selectedIds.contains(r.id))
      .fold(0, (s, r) {
        final wd = r.wageDetail;
        if (wd == null) return s;
        return s + (wd.netWage > 0 ? wd.netWage : wd.totalAmount);
      });

  int get _overdueCount =>
      _records.where((r) => _isOverdue(r.paymentDueDate)).length;

  int get _todayCount =>
      _records.where((r) => _isDueToday(r.paymentDueDate)).length;

  // ── 이체 처리 ─────────────────────────────────────────────
  String? _uid() =>
      Provider.of<UserProvider>(context, listen: false).currentUser?.uid;

  Future<String?> _showNoteDialog() async {
    final ctrl = TextEditingController();
    // context 의존 값을 builder 바깥에서 미리 캡처 → 다이얼로그 내부에서 stale context 방지
    final primaryColor = Theme.of(context).primaryColor;

    final note = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 헤더
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [primaryColor, primaryColor.withValues(alpha: 0.85)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(20)),
                  ),
                  child: Row(children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.edit_note_rounded,
                          color: Colors.white, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('이체 메모',
                              style: ResponsiveHelper.subtitleStyle(ctx)
                                  .copyWith(color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                          Text('선택 입력',
                              style: ResponsiveHelper.tinyStyle(ctx,
                                  color: Colors.white.withValues(alpha: 0.75))),
                        ],
                      ),
                    ),
                  ]),
                ),

                // 본문
                Container(
                  color: AppColors.grey50,
                  padding: const EdgeInsets.all(20),
                  child: Column(children: [
                    // 입력 필드 (흰 카드)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 6, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: TextField(
                        controller: ctrl,
                        autofocus: true,
                        maxLines: 3,
                        textInputAction: TextInputAction.done,
                        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                        style: ResponsiveHelper.bodyStyle(ctx),
                        decoration: InputDecoration(
                          hintText: '이체 번호, 참고사항 등 자유롭게 입력',
                          hintStyle: ResponsiveHelper.smallStyle(ctx,
                              color: AppColors.grey400),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.all(14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    // 버튼
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () =>
                            Navigator.pop(ctx, ctrl.text.trim()),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        child: Text('확인',
                            style: ResponsiveHelper.bodyStyle(ctx)
                                .copyWith(color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, ''),
                      child: Text('건너뛰기',
                          style: ResponsiveHelper.smallStyle(ctx,
                              color: AppColors.grey400)),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    );
    ctrl.dispose();
    return (note == null || note.isEmpty) ? null : note;
  }

  Future<void> _exportExcel() async {
    final today = DateTime.now();
    final biz = widget.businessName ?? widget.businessId;
    await PayrollExcelHelper.exportAndShare(
      context: context,
      records: _records,
      title: '$biz ${today.month}월 오늘 처리할 송금',
      filename: '${biz}_${today.month}월_오늘송금목록.xlsx',
    );
  }

  Future<void> _markTransferred(AttendanceModel record) async {
    final uid = _uid();
    if (uid == null || uid.isEmpty) {
      ToastHelper.showError('로그인 정보를 확인해주세요');
      return;
    }
    final name = _nameCache[record.userId] ?? record.userId;
    final wd   = record.wageDetail;
    final net  = wd != null
        ? (wd.netWage > 0 ? wd.netWage : wd.totalAmount)
        : 0;

    final ok = await DialogHelper.showConfirm(
      context,
      title: '송금 처리',
      message: '$name님께\n${FormatHelper.formatWage(net)}을\n송금 처리하시겠습니까?',
      confirmText: '송금 처리',
      cancelText: '취소',
      icon: Icons.payment_outlined,
    );
    if (!ok || !mounted) return;

    final note = await _showNoteDialog();
    if (!mounted) return;

    setState(() => _isProcessing = true);
    try {
      await _payService.markTransferred(
        attendanceId: record.id,
        processedBy:  uid,
        transferNote: note,
      );
      if (mounted) {
        ToastHelper.showSuccess('송금 처리되었습니다');
        _load();
      }
    } catch (e) {
      debugPrint('❌ 송금 처리 실패: $e');
      if (mounted) ToastHelper.showError('송금 처리 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _markBatchTransferred() async {
    if (_selectedIds.isEmpty) {
      ToastHelper.showWarning('처리할 항목을 선택해주세요');
      return;
    }
    final uid = _uid();
    if (uid == null || uid.isEmpty) {
      ToastHelper.showError('로그인 정보를 확인해주세요');
      return;
    }

    final ok = await DialogHelper.showConfirm(
      context,
      title: '일괄 송금 처리',
      message: '선택한 ${_selectedIds.length}건\n(${FormatHelper.formatWage(_selectedAmount)})을\n송금 처리하시겠습니까?',
      confirmText: '송금 처리',
      cancelText: '취소',
      icon: Icons.payment_outlined,
    );
    if (!ok || !mounted) return;

    final note = await _showNoteDialog();
    if (!mounted) return;

    setState(() => _isProcessing = true);
    try {
      await _payService.markTransferredBatch(
        attendanceIds: _selectedIds.toList(),
        processedBy:   uid,
        transferNote:  note,
      );
      if (mounted) {
        ToastHelper.showSuccess('${_selectedIds.length}건 송금 처리되었습니다');
        _load();
      }
    } catch (e) {
      debugPrint('❌ 일괄 송금 실패: $e');
      if (mounted) ToastHelper.showError('송금 처리 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _toggleSelect(String id) => setState(() {
        _selectedIds.contains(id)
            ? _selectedIds.remove(id)
            : _selectedIds.add(id);
      });

  // ── Build ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final title = widget.businessName != null
        ? '오늘 처리할 송금 · ${widget.businessName}'
        : '오늘 처리할 송금';

    return GradientScaffold(
      title: title,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          tooltip: '새로고침',
          onPressed: _load,
        ),
      ],
      body: _isLoading
          ? const LoadingWidget()
          : _records.isEmpty
              ? _buildEmpty()
              : Column(
                  children: [
                    _buildSummaryHeader(),
                    _buildFilterAndActionRow(),
                    if (_batchMode) _buildBatchBar(),
                    Expanded(
                      child: RefreshIndicator(
                        onRefresh: _load,
                        child: _buildList(),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildEmpty() {
    return const AppEmptyState(
      icon: Icons.check_circle_outline,
      iconColor: AppColors.success,
      title: '오늘 처리할 송금이 없습니다',
      subtitle: '지급 예정일이 오늘 이하인 확정 급여가 없습니다',
    );
  }

  // ── 요약 헤더 — 급여 지급 현황과 동일한 히어로+보조 구조 ─────
  Widget _buildSummaryHeader() {
    final theme   = Theme.of(context);
    final overdue = _overdueCount;

    return Container(
      color: theme.primaryColor.withValues(alpha: 0.06),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1행: 총 송금액(히어로) + 연체(경고)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 히어로 금액
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.send_outlined,
                    size: 16, color: AppColors.warningDark),
                const SizedBox(width: 6),
                Text(
                  FormatHelper.formatWage(_totalAmount),
                  style: ResponsiveHelper.titleStyle(context,
                      color: AppColors.warningDark),
                ),
              ]),
              const SizedBox(width: 6),
              Text('총 송금액',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey700)),
              const Spacer(),
              // 연체 경고 칩 / 없음
              if (overdue > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.errorBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 13, color: AppColors.errorDark),
                    const SizedBox(width: 4),
                    Text(
                      '연체 $overdue건',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.errorDark,
                          fontWeight: FontWeight.bold),
                    ),
                  ]),
                )
              else
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_circle_outline,
                      size: 12, color: AppColors.success),
                  const SizedBox(width: 4),
                  Text('연체 없음',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.success)),
                ]),
            ],
          ),

          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.grey200),
          const SizedBox(height: 8),

          // ── 2행: 총 건수 + 엑셀 버튼
          Row(children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.receipt_outlined,
                  size: 12, color: theme.primaryColor),
              const SizedBox(width: 4),
              Text(
                '${_records.length}건',
                style: ResponsiveHelper.smallStyle(context,
                    color: theme.primaryColor,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              Text('총 건수',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey700)),
            ]),
            const Spacer(),
            // 엑셀 내보내기
            SizedBox(
              height: 28,
              child: TextButton.icon(
                onPressed: _exportExcel,
                icon: Icon(Icons.download_outlined,
                    size: ResponsiveHelper.iconSize(context, 14)),
                label: Text('엑셀',
                    style: ResponsiveHelper.tinyStyle(context,
                        fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.infoDark,
                  padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 8)),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ── 퀵필터 + 일괄선택 행 ──────────────────────────────────
  Widget _buildFilterAndActionRow() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      child: Row(
        children: [
          _QuickFilterChip(
            label: '전체',
            count: _records.length,
            active: _quickFilter == _QuickFilter.all,
            onTap: () => setState(() {
              _quickFilter = _QuickFilter.all;
              _selectedIds.clear();
            }),
          ),
          const SizedBox(width: 6),
          if (_overdueCount > 0)
            _QuickFilterChip(
              label: '연체',
              count: _overdueCount,
              active: _quickFilter == _QuickFilter.overdue,
              activeColor: AppColors.error,
              onTap: () => setState(() {
                _quickFilter = _QuickFilter.overdue;
                _selectedIds.clear();
              }),
            ),
          if (_overdueCount > 0) const SizedBox(width: 6),
          if (_todayCount > 0)
            _QuickFilterChip(
              label: '오늘마감',
              count: _todayCount,
              active: _quickFilter == _QuickFilter.today,
              activeColor: AppColors.warning,
              onTap: () => setState(() {
                _quickFilter = _QuickFilter.today;
                _selectedIds.clear();
              }),
            ),
          const Spacer(),
          // 일괄선택 토글
          TextButton.icon(
            onPressed: () => setState(() {
              _batchMode = !_batchMode;
              if (!_batchMode) _selectedIds.clear();
            }),
            icon: Icon(
              _batchMode ? Icons.close : Icons.checklist,
              size: 15,
              color: _batchMode ? AppColors.error : AppColors.grey600,
            ),
            label: Text(
              _batchMode ? '취소' : '일괄선택',
              style: ResponsiveHelper.smallStyle(context,
                color: _batchMode ? AppColors.error : AppColors.grey600,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 30),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchBar() {
    return AppBatchActionBar(
      selectedCount: _selectedIds.length,
      selectedAmount: _selectedAmount,
      onSelectAll: () => setState(
          () => _selectedIds.addAll(_filteredRecords.map((r) => r.id))),
      onDeselectAll: () => setState(() => _selectedIds.clear()),
      onAction: _isProcessing || _selectedAmount <= 0 ? null : _markBatchTransferred,
      actionLabel: '송금',
      actionIcon: Icons.send,
    );
  }

  Widget _buildList() {
    final grouped = _filteredGrouped;
    final padding = ResponsiveHelper.cardPadding(context);

    if (grouped.isEmpty) {
      return AppEmptyState(
        icon: _quickFilter == _QuickFilter.overdue
            ? Icons.check_circle_outline
            : Icons.inbox_outlined,
        iconColor: _quickFilter == _QuickFilter.overdue
            ? AppColors.success
            : AppColors.grey300,
        title: _quickFilter == _QuickFilter.overdue
            ? '연체 건이 없습니다'
            : '오늘 마감 건이 없습니다',
      );
    }

    return ListView.builder(
      padding:
          EdgeInsets.fromLTRB(padding.left, 8, padding.right, 80),
      itemCount: grouped.length,
      itemBuilder: (ctx, idx) {
        final type  = grouped.keys.elementAt(idx);
        final items = grouped[type]!;
        return _GroupSection(
          type:         type,
          items:        items,
          batchMode:    _batchMode,
          selectedIds:  _selectedIds,
          nameCache:    _nameCache,
          onToggle:     _toggleSelect,
          onTransfer:   _isProcessing ? null : _markTransferred,
          isOverdueFn:  _isOverdue,
          isDueTodayFn: _isDueToday,
        );
      },
    );
  }
}

// ── 퀵필터 칩 ────────────────────────────────────────────────

class _QuickFilterChip extends StatelessWidget {
  final String label;
  final int count;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _QuickFilterChip({
    required this.label,
    required this.count,
    required this.active,
    required this.onTap,
    this.activeColor = AppColors.info,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: active
              ? activeColor.withValues(alpha: 0.12)
              : AppColors.grey100,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: active ? activeColor : AppColors.grey200,
              width: active ? 1.5 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label,
              style: ResponsiveHelper.smallStyle(context,
                  color: active ? activeColor : AppColors.grey500,
                  fontWeight: active ? FontWeight.w700 : FontWeight.normal)),
          if (count > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                  color: active ? activeColor : AppColors.grey300,
                  borderRadius: BorderRadius.circular(10)),
              child: Text('$count',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: Colors.white,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ]),
      ),
    );
  }
}

// ── 지급유형 그룹 섹션 ────────────────────────────────────────

class _GroupSection extends StatelessWidget {
  final String type;
  final List<AttendanceModel> items;
  final bool batchMode;
  final Set<String> selectedIds;
  final Map<String, String> nameCache;
  final ValueChanged<String> onToggle;
  final void Function(AttendanceModel)? onTransfer;
  final bool Function(DateTime?) isOverdueFn;
  final bool Function(DateTime?) isDueTodayFn;

  const _GroupSection({
    required this.type,
    required this.items,
    required this.batchMode,
    required this.selectedIds,
    required this.nameCache,
    required this.onToggle,
    required this.onTransfer,
    required this.isOverdueFn,
    required this.isDueTodayFn,
  });

  Color _typeColor() {
    switch (type) {
      case 'same_day': return AppColors.error;
      case 'next_day': return AppColors.warning;
      case 'weekly':   return AppColors.info;
      case 'monthly':  return AppColors.purple;
      default:         return AppColors.grey500;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = PaymentDueDateCalculator.label(
        type == 'unknown' ? null : type);
    final groupAmount = items.fold<int>(0, (s, r) {
      final wd = r.wageDetail;
      if (wd == null) return s;
      return s + (wd.netWage > 0 ? wd.netWage : wd.totalAmount);
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 섹션 헤더 — 더 명확하게
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _typeColor().withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: _typeColor().withValues(alpha: 0.4)),
              ),
              child: Text(label,
                  style: ResponsiveHelper.smallStyle(context,
                      color: _typeColor(),
                      fontWeight: FontWeight.w700)),
            ),
            const SizedBox(width: 8),
            Text(
              '${items.length}건 · ${FormatHelper.formatWage(groupAmount)}',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey600,
                  fontWeight: FontWeight.w500),
            ),
          ]),
        ),
        ...items.map((r) => _PaymentCard(
              record:       r,
              workerName:   nameCache[r.userId] ?? r.userId,
              batchMode:    batchMode,
              isSelected:   selectedIds.contains(r.id),
              isOverdue:    isOverdueFn(r.paymentDueDate),
              isDueToday:   isDueTodayFn(r.paymentDueDate),
              onToggle:     () => onToggle(r.id),
              onTransfer:   onTransfer != null ? () => onTransfer!(r) : null,
            )),
      ],
    );
  }
}

// ── 개별 지급 카드 (2행 compact) ────────────────────────────

class _PaymentCard extends StatelessWidget {
  final AttendanceModel record;
  final String workerName;
  final bool batchMode;
  final bool isSelected;
  final bool isOverdue;
  final bool isDueToday;
  final VoidCallback onToggle;
  final VoidCallback? onTransfer;

  const _PaymentCard({
    required this.record,
    required this.workerName,
    required this.batchMode,
    required this.isSelected,
    required this.isOverdue,
    required this.isDueToday,
    required this.onToggle,
    required this.onTransfer,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wd    = record.wageDetail;
    final net   = wd != null
        ? (wd.netWage > 0 ? wd.netWage : wd.totalAmount)
        : 0;
    final due   = record.paymentDueDate;

    // 상태 색상
    final accentColor = isOverdue
        ? AppColors.error
        : isDueToday
            ? AppColors.warning
            : Colors.transparent;

    // 지급일 상태 텍스트 & 색상
    String? statusText;
    Color statusColor = AppColors.grey500;
    if (due != null) {
      // MM.dd 형식으로 짧게 표시
      final shortDate = '${due.month}.${due.day.toString().padLeft(2, '0')}';
      if (isOverdue) {
        statusText = '$shortDate 초과';
        statusColor = AppColors.error;
      } else if (isDueToday) {
        statusText = '오늘 지급';
        statusColor = AppColors.warning;
      } else {
        statusText = shortDate;
        statusColor = AppColors.grey500;
      }
    }

    return GestureDetector(
      onTap: batchMode ? onToggle : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primaryColor.withValues(alpha: 0.04)
              : isOverdue
                  ? AppColors.errorBg.withValues(alpha: 0.35)
                  : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.primaryColor.withValues(alpha: 0.5)
                : isOverdue
                    ? AppColors.error.withValues(alpha: 0.25)
                    : AppColors.grey200,
            width: isSelected || isOverdue ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 4,
                offset: const Offset(0, 1)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 왼쪽 컬러 인디케이터
                Container(width: 4, color: accentColor),

                // 본문
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 배치 체크박스
                        if (batchMode) ...[
                          Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: isSelected
                                ? theme.primaryColor
                                : AppColors.grey400,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                        ],

                        // 이름 + 상태칩 + 사업장 (아바타 제거 → 공간 확보)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // 1행: 이름 + 연체배지 + 상태칩
                              Row(children: [
                                Flexible(
                                  child: Text(
                                    workerName,
                                    style: ResponsiveHelper.bodyStyle(context,
                                        fontWeight: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // 상태칩 — 날짜를 짧게 (MM.dd) + 지급유형
                                // 연체 배지 제거 — 상태칩(△ 주급·5.26 초과)으로 충분
                                if (statusText != null) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: statusColor
                                            .withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(4),
                                      ),
                                      child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (isOverdue || isDueToday)
                                              Padding(
                                                padding: const EdgeInsets.only(right: 2),
                                                child: Icon(
                                                    isOverdue
                                                        ? Icons.warning_amber_rounded
                                                        : Icons.schedule,
                                                    size: 10,
                                                    color: statusColor),
                                              ),
                                            Flexible(
                                              child: Text(
                                                _buildChipText(wd, statusText),
                                                style: ResponsiveHelper.tinyStyle(context,
                                                    color: statusColor,
                                                    fontWeight: isOverdue || isDueToday
                                                        ? FontWeight.w700
                                                        : FontWeight.normal),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ]),
                                    ),
                                  ),
                                ],
                              ]),

                              // 2행: 사업장명 · 근무일
                              const SizedBox(height: 3),
                              Text(
                                '${record.businessName} · ${FormatHelper.formatDateDot(record.workDate)}',
                                style: ResponsiveHelper.tinyStyle(context,
                                    color: AppColors.grey400),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // 금액 + 버튼
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              FormatHelper.formatWage(net),
                              style: ResponsiveHelper.subtitleStyle(context,
                                  color: AppColors.grey800),
                            ),
                            if (!batchMode) ...[
                              const SizedBox(height: 6),
                              SizedBox(
                                height: 28,
                                child: OutlinedButton(
                                  onPressed: onTransfer,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor:
                                        AppColors.successDark,
                                    side: const BorderSide(
                                        color: AppColors.success,
                                        width: 1.2),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    textStyle: ResponsiveHelper.tinyStyle(context, fontWeight: FontWeight.w600),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(6)),
                                  ),
                                  child: const Text('송금'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 상태 칩 텍스트 — 날짜를 MM.dd로 짧게 + 지급유형 앞에 붙임
  String _buildChipText(WageDetailModel? wd, String statusText) {
    final typeLabel = wd?.payScheduleType != null
        ? '${PaymentDueDateCalculator.label(wd!.payScheduleType)} · '
        : '';
    return '$typeLabel$statusText';
  }
}
