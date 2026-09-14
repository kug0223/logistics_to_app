import 'package:flutter/material.dart';

import '../../../models/core/slot_model.dart';
import '../../../models/core/to_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/slot_status_util.dart';
import '../../../utils/format_helper.dart';
import '../../../widgets/common/app_checkbox.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/common/slot_status_badge.dart';

/// 다이얼로그가 돌려주는 선택 결과.
///
/// [POSTING-V2-03M.1] 해석하지 못한 슬롯은 [SlotModel]을 만들 수 없으므로
/// 문서 id로만 돌아온다. 서버는 slotId만 있으면 지울 수 있다.
class SlotBatchSelection {
  final List<SlotModel> slots;

  /// 선택된 '날짜 확인 불가' 항목의 문서 id.
  final List<String> malformedSlotIds;

  const SlotBatchSelection({
    required this.slots,
    this.malformedSlotIds = const [],
  });

  /// 서버에 보낼 canonical id 목록.
  List<String> get slotIds =>
      [...slots.map((s) => s.id), ...malformedSlotIds];

  int get length => slots.length + malformedSlotIds.length;
  bool get isEmpty => length == 0;
}

/// 배치 작업용 날짜(슬롯) 다중선택 다이얼로그
class SlotBatchSelectDialog extends StatefulWidget {
  final TOModel to;
  final FirestoreService firestoreService;
  final String title;
  final String confirmLabel;
  final bool openOnly;            // true면 마감되지 않은 슬롯만 표시
  final bool closedAndReopenable; // true면 수동마감 + 날짜 미경과 슬롯만 표시

  /// [POSTING-V2-03M.1] 해석하지 못한 슬롯을 복구 항목으로 노출할지.
  ///
  /// 삭제 경로에서만 켠다 — 날짜를 읽을 수 없는 슬롯은 종료·재오픈·수정의
  /// 대상이 될 수 없고(무엇을 바꾸는지 보여줄 수 없다), 그 경로들이 막혀도
  /// 공고가 정리 불가 상태가 되지는 않는다.
  final bool includeMalformed;

  const SlotBatchSelectDialog({
    super.key,
    required this.to,
    required this.firestoreService,
    required this.title,
    required this.confirmLabel,
    this.openOnly = false,
    this.closedAndReopenable = false,
    this.includeMalformed = false,
  });

  static Future<SlotBatchSelection?> show({
    required BuildContext context,
    required TOModel to,
    required FirestoreService firestoreService,
    required String title,
    required String confirmLabel,
    bool openOnly = false,
    bool closedAndReopenable = false,
    bool includeMalformed = false,
  }) {
    return showDialog<SlotBatchSelection>(
      context: context,
      barrierDismissible: false,
      builder: (_) => SlotBatchSelectDialog(
        to: to,
        firestoreService: firestoreService,
        title: title,
        confirmLabel: confirmLabel,
        openOnly: openOnly,
        closedAndReopenable: closedAndReopenable,
        includeMalformed: includeMalformed,
      ),
    );
  }

  @override
  State<SlotBatchSelectDialog> createState() => _SlotBatchSelectDialogState();
}

class _SlotBatchSelectDialogState extends State<SlotBatchSelectDialog> {
  bool _isLoading = true;
  List<SlotModel> _slots = [];

  /// [POSTING-V2-03M.1] 해석하지 못한 슬롯 문서의 id.
  List<String> _malformedIds = const [];
  final Set<String> _selectedIds = {};

  /// [POSTING-V2-03D.1] 조회 실패와 "선택할 날짜가 없음"은 다른 상태다.
  ///   toast는 사라지지만 목록은 남는다 — 실패한 채 '등록된 날짜가 없습니다'를
  ///   보여주면 관리자는 날짜가 정말 없다고 믿는다. ERROR != EMPTY.
  bool _loadError = false;

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    try {
      // [POSTING-V2-03M.1] 같은 조회 한 번에서 해석된 슬롯과 해석하지 못한
      //   문서를 함께 받는다 — 추가 조회 없음.
      final result =
          await widget.firestoreService.getSlotCandidates(widget.to.id);
      final slots = [...result.slots]
        ..sort((a, b) => a.date.compareTo(b.date));

      final now = DateTime.now();
      final today = FormatHelper.toKstDate(now);

      if (!mounted) return;
      final filtered = widget.closedAndReopenable
          ? slots.where((s) {
              if (!s.isManualClosed || FormatHelper.toKstDate(s.date).isBefore(today)) return false;
              if (s.workDetails.isNotEmpty &&
                  s.workDetails.every((d) => d.isTimeExpired)) { return false; }
              return true;
            }).toList()
          : widget.openOnly
              ? slots.where((s) => !s.isEffectivelyClosed).toList()
              : slots;

      setState(() {
        _slots = filtered;
        // 복구 항목을 노출하지 않는 경로에서도 **개수는 알린다** —
        //   목록이 전부인 것처럼 보이게 두지 않는다.
        _malformedIds = result.malformedIds;
        _isLoading = false;
        _loadError = false;
      });
    } catch (e) {
      debugPrint('❌ 슬롯 로드 실패: $e');
      if (mounted) {
        setState(() {
          _slots = [];
          _malformedIds = const [];
          _isLoading = false;
          _loadError = true;
        });
        ToastHelper.showError('날짜 목록을 불러오는데 실패했습니다.');
      }
    }
  }

  /// 선택 가능한 항목의 id — 복구 항목은 삭제 경로에서만 포함된다.
  List<String> get _selectableIds => [
        ..._slots.map((s) => s.id),
        if (widget.includeMalformed) ..._malformedIds,
      ];

  bool get _allSelected =>
      _selectableIds.isNotEmpty && _selectedIds.length == _selectableIds.length;

  void _toggleAll() {
    setState(() {
      if (_allSelected) {
        _selectedIds.clear();
      } else {
        _selectedIds.addAll(_selectableIds);
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
                  Navigator.pop(
                    context,
                    SlotBatchSelection(
                      slots: selected,
                      malformedSlotIds: _malformedIds
                          .where(_selectedIds.contains)
                          .toList(),
                    ),
                  );
                },
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const LoadingWidget();
    }

    // [POSTING-V2-03D.1] 실패 분기가 빈 목록 분기보다 앞이다.
    if (_loadError) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off,
                size: ResponsiveHelper.iconSize(context, 48),
                color: AppColors.grey400),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              '날짜 목록을 불러오는데 실패했습니다.',
              style: ResponsiveHelper.bodyStyle(context,
                  color: AppColors.grey600),
            ),
          ],
        ),
      );
    }

    if (_slots.isEmpty && _malformedIds.isEmpty) {
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
                      '전체 선택 (${_selectableIds.length}개)',
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

          // [POSTING-V2-03M.1] 해석하지 못한 슬롯 — 목록에서 지우지 않는다.
          //   삭제 경로에서는 선택 가능한 복구 항목으로, 그 밖에서는
          //   "여기 더 있다"는 사실만 알리는 안내로 보여준다.
          if (widget.includeMalformed)
            ...List.generate(
              _malformedIds.length,
              (i) => _buildMalformedTile(_malformedIds[i], i + 1),
            )
          else if (_malformedIds.isNotEmpty)
            _buildMalformedNotice(),
        ],
      ),
    );
  }

  /// 날짜를 읽을 수 없는 슬롯을 정상 날짜로 위장하지 않는다.
  /// 문서 id나 내부 스키마 오류는 노출하지 않는다.
  Widget _buildMalformedTile(String slotId, int ordinal) {
    final isSelected = _selectedIds.contains(slotId);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          setState(() {
            if (isSelected) {
              _selectedIds.remove(slotId);
            } else {
              _selectedIds.add(slotId);
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
                ? AppColors.warning.withValues(alpha: 0.08)
                : AppColors.grey50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected ? AppColors.warning : AppColors.border,
            ),
          ),
          child: Row(
            children: [
              AppCheckbox(
                value: isSelected,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 10)),
              Icon(Icons.warning_amber_rounded,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.warning),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '날짜 확인 불가 $ordinal',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    Text(
                      '데이터 오류로 날짜를 표시할 수 없습니다.',
                      style: ResponsiveHelper.captionStyle(context,
                          color: AppColors.grey600),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 삭제 외 경로 — 선택은 못 하지만 존재는 알린다.
  Widget _buildMalformedNotice() {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              size: ResponsiveHelper.iconSize(context, 18),
              color: AppColors.warning),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              '날짜를 표시할 수 없는 항목이 ${_malformedIds.length}개 있습니다. '
              '날짜 일괄삭제에서 정리할 수 있습니다.',
              style: ResponsiveHelper.captionStyle(context,
                  color: AppColors.grey700),
            ),
          ),
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
