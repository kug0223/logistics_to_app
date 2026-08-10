import 'package:flutter/material.dart';

import '../../../models/core/slot_model.dart';
import '../../../models/core/to_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/slot_status_util.dart';
import '../../../widgets/common/app_checkbox.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/common/slot_status_badge.dart';

/// 배치 작업용 날짜(슬롯) 다중선택 다이얼로그
class SlotBatchSelectDialog extends StatefulWidget {
  final TOModel to;
  final FirestoreService firestoreService;
  final String title;
  final String confirmLabel;
  final bool openOnly;            // true면 마감되지 않은 슬롯만 표시
  final bool closedAndReopenable; // true면 수동마감 + 날짜 미경과 슬롯만 표시

  const SlotBatchSelectDialog({
    super.key,
    required this.to,
    required this.firestoreService,
    required this.title,
    required this.confirmLabel,
    this.openOnly = false,
    this.closedAndReopenable = false,
  });

  static Future<List<SlotModel>?> show({
    required BuildContext context,
    required TOModel to,
    required FirestoreService firestoreService,
    required String title,
    required String confirmLabel,
    bool openOnly = false,
    bool closedAndReopenable = false,
  }) {
    return showDialog<List<SlotModel>>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SlotBatchSelectDialog(
        to: to,
        firestoreService: firestoreService,
        title: title,
        confirmLabel: confirmLabel,
        openOnly: openOnly,
        closedAndReopenable: closedAndReopenable,
      ),
    );
  }

  @override
  State<SlotBatchSelectDialog> createState() => _SlotBatchSelectDialogState();
}

class _SlotBatchSelectDialogState extends State<SlotBatchSelectDialog> {
  bool _isLoading = true;
  List<SlotModel> _slots = [];
  final Set<String> _selectedIds = {};

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    try {
      final slots = await widget.firestoreService.getSlots(widget.to.id);
      slots.sort((a, b) => a.date.compareTo(b.date));

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      if (!mounted) return;
      final filtered = widget.closedAndReopenable
          ? slots.where((s) {
              if (!s.isManualClosed || s.date.isBefore(today)) return false;
              if (s.workDetails.isNotEmpty &&
                  s.workDetails.every((d) => d.isTimeExpired)) { return false; }
              return true;
            }).toList()
          : widget.openOnly
              ? slots.where((s) => !s.isEffectivelyClosed).toList()
              : slots;

      setState(() {
        _slots = filtered;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 슬롯 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ToastHelper.showError('날짜 목록을 불러오는데 실패했습니다.');
      }
    }
  }

  bool get _allSelected => _slots.isNotEmpty && _selectedIds.length == _slots.length;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_slots.map((s) => s.id));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return StyledDialog(
      title: widget.title,
      subtitle: widget.to.title,
      icon: Icons.calendar_month,
      maxHeightRatio: 0.8,
      fillHeight: true,
      content: _buildContent(),
      actions: [
        StyledDialogButton.cancel(
          onPressed: () => Navigator.pop(context, null),
        ),
        StyledDialogButton.primary(
          text: '${widget.confirmLabel} (${_selectedIds.length}개)',
          onPressed: _selectedIds.isEmpty
              ? null
              : () {
                  final selected = _slots
                      .where((s) => _selectedIds.contains(s.id))
                      .toList();
                  Navigator.pop(context, selected);
                },
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const LoadingWidget();
    }

    if (_slots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_busy,
                size: ResponsiveHelper.iconSize(context, 48),
                color: AppColors.grey400),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              widget.closedAndReopenable
                  ? '재오픈 가능한 날짜가 없습니다'
                  : widget.openOnly
                      ? '마감 가능한 날짜가 없습니다'
                      : '등록된 날짜가 없습니다',
              style: ResponsiveHelper.bodyStyle(context,
                  color: AppColors.grey600),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: ResponsiveHelper.cardPadding(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 전체 선택 토글
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _toggleAll,
              borderRadius: BorderRadius.circular(10),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 10),
                ),
                decoration: BoxDecoration(
                  color: _allSelected
                      ? Theme.of(context).primaryColor.withValues(alpha: 0.08)
                      : AppColors.grey50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _allSelected
                        ? Theme.of(context).primaryColor
                        : AppColors.border,
                  ),
                ),
                child: Row(
                  children: [
                    AppCheckbox(
                      value: _allSelected,
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                    Text(
                      '전체 선택 (${_slots.length}개)',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: _allSelected
                            ? Theme.of(context).primaryColor
                            : AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // 슬롯 목록
          ..._slots.map((slot) => _buildSlotTile(slot)),
        ],
      ),
    );
  }

  Widget _buildSlotTile(SlotModel slot) {
    final isSelected = _selectedIds.contains(slot.id);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedIds.remove(slot.id);
            } else {
              _selectedIds.add(slot.id);
            }
          });
        },
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin:
              EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          decoration: BoxDecoration(
            color: isSelected
                ? Theme.of(context).primaryColor.withValues(alpha: 0.06)
                : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).primaryColor
                  : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              AppCheckbox(
                value: isSelected,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      slot.formattedDate,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                    Text(
                      '확정 ${slot.confirmedCount}/${slot.totalRequired}명  대기 ${slot.pendingCount}명',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600),
                    ),
                  ],
                ),
              ),
              // 상태 배지
              SlotStatusBadge(
                status: SlotStatusUtil.slotStatus(slot, widget.to),
                scheduledAt: SlotStatusUtil.slotScheduledAt(slot, widget.to),
                compact: true,
              ),
            ],
          ),
        ),
      ),
    );
  }

}
