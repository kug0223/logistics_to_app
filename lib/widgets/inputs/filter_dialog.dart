import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../pickers/date_picker_bottom_sheet.dart';

class FilterDialog extends StatefulWidget {
  final String? selectedBusiness;
  final DateTimeRange? selectedDateRange;
  final String? selectedTOType;        // null / 'flex' / 'contract'
  final String? selectedPublishStatus; // null / 'published' / 'unpublished' / 'pending'
  final List<String> businessNames;
  final Function(String?) onBusinessChanged;
  final Function(DateTimeRange?) onDateRangeChanged;
  final Function(String?)? onTOTypeChanged;
  final Function(String?)? onPublishStatusChanged;
  final bool isUserMode;
  final bool showTOTypeFilter;
  final bool showPublishStatusFilter;

  const FilterDialog({
    super.key,
    this.selectedBusiness,
    this.selectedDateRange,
    this.selectedTOType,
    this.selectedPublishStatus,
    required this.businessNames,
    required this.onBusinessChanged,
    required this.onDateRangeChanged,
    this.onTOTypeChanged,
    this.onPublishStatusChanged,
    this.isUserMode = false,
    this.showTOTypeFilter = false,
    this.showPublishStatusFilter = false,
  });

  @override
  State<FilterDialog> createState() => _FilterDialogState();
}

class _FilterDialogState extends State<FilterDialog> {
  String? _tempBusiness;
  DateTimeRange? _tempDateRange;
  String? _tempTOType;
  String? _tempPublishStatus;

  @override
  void initState() {
    super.initState();
    _tempBusiness = widget.selectedBusiness;
    _tempDateRange = widget.selectedDateRange;
    _tempTOType = widget.selectedTOType;
    _tempPublishStatus = widget.selectedPublishStatus;
  }

  int get _activeCount {
    int c = 0;
    if (_tempBusiness != null) c++;
    if (_tempDateRange != null) c++;
    if (_tempTOType != null) c++;
    if (_tempPublishStatus != null) c++;
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).primaryColor;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, primary),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (widget.businessNames.length > 1) ...[
                      _buildSection(
                        context,
                        label: '사업장',
                        icon: Icons.business_outlined,
                        child: _buildBusinessChips(context, primary),
                      ),
                      _buildDivider(),
                    ],
                    if (widget.showTOTypeFilter) ...[
                      _buildSection(
                        context,
                        label: '공고 유형',
                        icon: Icons.category_outlined,
                        child: _buildTOTypeChips(context, primary),
                      ),
                      _buildDivider(),
                    ],
                    if (widget.showPublishStatusFilter) ...[
                      _buildSection(
                        context,
                        label: '공개 상태',
                        icon: Icons.visibility_outlined,
                        child: _buildPublishStatusChips(context, primary),
                      ),
                      _buildDivider(),
                    ],
                    _buildSection(
                      context,
                      label: '날짜',
                      icon: Icons.calendar_today_outlined,
                      child: _buildDateChips(context, primary),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            _buildBottomBar(context, primary),
          ],
        ),
      ),
    );
  }

  // ─── Header ───────────────────────────────────────────────

  Widget _buildHeader(BuildContext context, Color primary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 8, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withValues(alpha: 0.82)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.tune, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 12),
          Text(
            '필터',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_activeCount > 0) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$_activeCount개 적용',
                style: ResponsiveHelper.tinyStyle(context, color: Colors.white).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          const Spacer(),
          TextButton(
            onPressed: _resetFilters,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              minimumSize: const Size(0, 36),
            ),
            child: Text(
              '초기화',
              style: ResponsiveHelper.smallStyle(context, color: Colors.white70),
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close, color: Colors.white54, size: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
        ],
      ),
    );
  }

  // ─── Section ──────────────────────────────────────────────

  Widget _buildSection(
    BuildContext context, {
    required String label,
    required IconData icon,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: AppColors.grey500),
            const SizedBox(width: 5),
            Text(
              label,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600).copyWith(
                fontWeight: FontWeight.w600,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  Widget _buildDivider() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      height: 1,
      color: AppColors.grey100,
    );
  }

  // ─── 사업장 Chips ─────────────────────────────────────────

  Widget _buildBusinessChips(BuildContext context, Color primary) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(
          context,
          label: '전체',
          isSelected: _tempBusiness == null,
          primary: primary,
          onTap: () => setState(() => _tempBusiness = null),
        ),
        ...widget.businessNames.map((name) => _chip(
              context,
              label: name,
              isSelected: _tempBusiness == name,
              primary: primary,
              onTap: () => setState(() => _tempBusiness = _tempBusiness == name ? null : name),
            )),
      ],
    );
  }

  // ─── 공고 유형 Chips ──────────────────────────────────────

  Widget _buildTOTypeChips(BuildContext context, Color primary) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(context, label: '전체', isSelected: _tempTOType == null, primary: primary,
            onTap: () => setState(() => _tempTOType = null)),
        _chip(context, label: '단기', icon: Icons.bolt_outlined, isSelected: _tempTOType == 'flex',
            primary: primary, onTap: () => setState(() => _tempTOType = 'flex')),
        _chip(context, label: '장기', icon: Icons.calendar_month_outlined, isSelected: _tempTOType == 'contract',
            primary: primary, onTap: () => setState(() => _tempTOType = 'contract')),
      ],
    );
  }

  // ─── 공개 상태 Chips ──────────────────────────────────────

  Widget _buildPublishStatusChips(BuildContext context, Color primary) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(context, label: '전체', isSelected: _tempPublishStatus == null, primary: primary,
            onTap: () => setState(() => _tempPublishStatus = null)),
        _chip(context, label: '공개중', icon: Icons.public_outlined,
            isSelected: _tempPublishStatus == 'published', primary: AppColors.success,
            onTap: () => setState(() => _tempPublishStatus = 'published')),
        _chip(context, label: '미공개', icon: Icons.lock_outline,
            isSelected: _tempPublishStatus == 'unpublished', primary: AppColors.grey600,
            onTap: () => setState(() => _tempPublishStatus = 'unpublished')),
        _chip(context, label: '예약공개', icon: Icons.schedule_outlined,
            isSelected: _tempPublishStatus == 'pending', primary: AppColors.warning,
            onTap: () => setState(() => _tempPublishStatus = 'pending')),
      ],
    );
  }

  // ─── 날짜 Chips ───────────────────────────────────────────

  Widget _buildDateChips(BuildContext context, Color primary) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final presets = <_DatePreset>[
      _DatePreset('전체', null),
      _DatePreset('오늘', DateTimeRange(start: today, end: today)),
      _DatePreset('이번 주', _thisWeekRange(today)),
      _DatePreset('다음 주', _nextWeekRange(today)),
      _DatePreset('이번 달', _thisMonthRange(now)),
    ];

    final isCustom = _tempDateRange != null &&
        !presets.any((p) => p.range != null && _rangeEquals(p.range!, _tempDateRange!));

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        ...presets.map((p) => _chip(
              context,
              label: p.label,
              isSelected: p.range == null
                  ? _tempDateRange == null
                  : _tempDateRange != null && _rangeEquals(p.range!, _tempDateRange!),
              primary: primary,
              onTap: () => setState(() => _tempDateRange = p.range),
            )),
        _chip(
          context,
          label: isCustom
              ? '${DateFormat('MM/dd').format(_tempDateRange!.start)} ~ ${DateFormat('MM/dd').format(_tempDateRange!.end)}'
              : '직접 선택',
          icon: isCustom ? Icons.edit_calendar_outlined : Icons.add_outlined,
          isSelected: isCustom,
          primary: primary,
          onTap: _pickCustomRange,
        ),
      ],
    );
  }

  DateTimeRange _thisWeekRange(DateTime today) {
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return DateTimeRange(start: monday, end: monday.add(const Duration(days: 6)));
  }

  DateTimeRange _nextWeekRange(DateTime today) {
    final nextMonday = today.add(Duration(days: 8 - today.weekday));
    return DateTimeRange(start: nextMonday, end: nextMonday.add(const Duration(days: 6)));
  }

  DateTimeRange _thisMonthRange(DateTime now) {
    final first = DateTime(now.year, now.month, 1);
    final last = DateTime(now.year, now.month + 1, 0);
    return DateTimeRange(start: first, end: last);
  }

  bool _rangeEquals(DateTimeRange a, DateTimeRange b) =>
      a.start.year == b.start.year &&
      a.start.month == b.start.month &&
      a.start.day == b.start.day &&
      a.end.year == b.end.year &&
      a.end.month == b.end.month &&
      a.end.day == b.end.day;

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();

    final picked = await DateRangePickerBottomSheet.show(
      context: context,
      initialStart: _tempDateRange?.start,
      initialEnd: _tempDateRange?.end,
      title: '날짜 범위 선택',
      subtitle: '조회할 기간을 선택해주세요',
      allowPastDates: !widget.isUserMode,
      minDate: widget.isUserMode ? DateTime(now.year, now.month, now.day) : DateTime(2024),
      maxDate: DateTime(now.year + 2),
    );

    if (picked != null) {
      setState(() => _tempDateRange = picked);
    }
  }

  // ─── 공통 Chip ────────────────────────────────────────────

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required Color primary,
    required VoidCallback onTap,
    IconData? icon,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 7),
        ),
        decoration: BoxDecoration(
          color: isSelected ? primary.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? primary : AppColors.grey300,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: isSelected ? primary : AppColors.grey500),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: ResponsiveHelper.smallStyle(
                context,
                color: isSelected ? primary : AppColors.grey700,
              ).copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Bottom Bar ───────────────────────────────────────────

  Widget _buildBottomBar(BuildContext context, Color primary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFF0F0F0))),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.grey700,
                side: BorderSide(color: AppColors.grey300),
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('취소', style: ResponsiveHelper.bodyStyle(context)),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _applyFilters,
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: Text(
                _activeCount > 0 ? '적용 ($_activeCount)' : '적용',
                style: ResponsiveHelper.bodyStyle(context, color: Colors.white).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _resetFilters() {
    setState(() {
      _tempBusiness = null;
      _tempDateRange = null;
      _tempTOType = null;
      _tempPublishStatus = null;
    });
  }

  void _applyFilters() {
    widget.onBusinessChanged(_tempBusiness);
    widget.onDateRangeChanged(_tempDateRange);
    widget.onTOTypeChanged?.call(_tempTOType);
    widget.onPublishStatusChanged?.call(_tempPublishStatus);
    Navigator.pop(context);
  }
}

class _DatePreset {
  final String label;
  final DateTimeRange? range;
  const _DatePreset(this.label, this.range);
}
