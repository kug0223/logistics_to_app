// lib/widgets/dialogs/wage/wage_detail_dialog.dart
// 공통 급여 상세/수정 다이얼로그
//
// 사용처:
// - attendance_status_dialog.dart (당일명단 → 더보기 → 급여 수정/상세)
// - wage_confirm_dialog.dart (급여확정 → 카드 클릭 → 급여 상세)
//
// 모드:
// - WageDialogMode.pending: 미확정 (급여 확정 버튼)
// - WageDialogMode.calculated: 급여확정 (수정 가능, 최종확정 버튼)
// - WageDialogMode.confirmed: 최종확정 (읽기 전용)
// - WageDialogMode.editOnly: 수정만 (저장 버튼)

import 'package:flutter/material.dart';

// Models
import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/wage_detail_model.dart';

// Utils
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../theme/app_colors.dart';

/// 다이얼로그 모드
enum WageDialogMode {
  pending,     // 미확정 → 급여 확정 버튼
  calculated,  // 급여확정 → 저장/최종확정/취소 버튼
  confirmed,   // 최종확정 → 읽기 전용
  editOnly,    // 수정만 → 저장 버튼
}

/// 다이얼로그 액션 결과
class WageDialogResult {
  final String action;  // 'confirm', 'update', 'final_confirm', 'cancel'
  final WageDetailModel wage;

  const WageDialogResult({
    required this.action,
    required this.wage,
  });
}

/// 공통 급여 상세/수정 다이얼로그
class WageDetailDialog extends StatefulWidget {
  final ApplicationModel app;
  final UserModel? user;
  final AttendanceModel attendance;
  final WageDetailModel wage;
  final WageDialogMode mode;

  const WageDetailDialog({
    super.key,
    required this.app,
    required this.user,
    required this.attendance,
    required this.wage,
    required this.mode,
  });

  /// 다이얼로그 표시 (편의 메서드)
  static Future<WageDialogResult?> show({
    required BuildContext context,
    required ApplicationModel app,
    required UserModel? user,
    required AttendanceModel attendance,
    required WageDetailModel wage,
    required WageDialogMode mode,
  }) {
    return showDialog<WageDialogResult>(
      context: context,
      builder: (context) => WageDetailDialog(
        app: app,
        user: user,
        attendance: attendance,
        wage: wage,
        mode: mode,
      ),
    );
  }

  @override
  State<WageDetailDialog> createState() => _WageDetailDialogState();
}

class _WageDetailDialogState extends State<WageDetailDialog> {
  late WageDetailModel _wage;
  final _additionalController = TextEditingController();
  final _memoController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _wage = widget.wage;
    _additionalController.text = widget.wage.additionalAmount > 0
        ? widget.wage.additionalAmount.toString()
        : '';
    _memoController.text = widget.wage.memo ?? '';
  }

  @override
  void dispose() {
    _additionalController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════
  // 급여 업데이트
  // ═══════════════════════════════════════════════════════════

  void _updateWage() {
    final additional = int.tryParse(_additionalController.text) ?? 0;
    final newTotal = _wage.baseAmount + _wage.overtimeAmount + _wage.nightAmount + additional;

    setState(() {
      _wage = _wage.copyWith(
        additionalAmount: additional,
        totalAmount: newTotal,
        memo: _memoController.text.trim().isNotEmpty
            ? _memoController.text.trim()
            : null,
      );
    });
  }

  // ═══════════════════════════════════════════════════════════
  // 액션 처리
  // ═══════════════════════════════════════════════════════════

  Future<void> _onAction(String action) async {
    _updateWage();

    final userName = widget.user?.name ?? '근무자';
    final totalText = FormatHelper.formatWage(_wage.totalAmount);

    String confirmTitle;
    String confirmMessage;
    String confirmText;
    bool isDanger = false;

    switch (action) {
      case 'confirm':
        confirmTitle = '급여 확정';
        confirmMessage = '$userName의 급여를 확정하시겠습니까?\n\n총 급여: $totalText';
        confirmText = '확정';
        break;
      case 'update':
        // 수정은 확인 없이 바로 저장
        Navigator.pop(context, WageDialogResult(action: action, wage: _wage));
        return;
      case 'final_confirm':
        confirmTitle = '최종 확정';
        confirmMessage = '$userName의 급여를 최종 확정하시겠습니까?\n\n총 급여: $totalText\n\n⚠️ 최종 확정 후에는 수정이 불가합니다.';
        confirmText = '최종 확정';
        break;
      case 'cancel':
        confirmTitle = '급여 확정 취소';
        confirmMessage = '$userName의 급여 확정을 취소하시겠습니까?\n\n미확정 상태로 되돌아갑니다.';
        confirmText = '취소하기';
        isDanger = true;
        break;
      default:
        return;
    }

    final confirmed = isDanger
        ? await DialogHelper.showDangerConfirm(
            context,
            title: confirmTitle,
            message: confirmMessage,
            confirmText: confirmText,
          )
        : await DialogHelper.showConfirm(
            context,
            title: confirmTitle,
            message: confirmMessage,
            confirmText: confirmText,
          );

    if (confirmed) {
      Navigator.pop(context, WageDialogResult(action: action, wage: _wage));
    }
  }

  // ═══════════════════════════════════════════════════════════
  // UI 속성
  // ═══════════════════════════════════════════════════════════

  Color get _headerColor {
    switch (widget.mode) {
      case WageDialogMode.pending:
        return AppColors.warning;
      case WageDialogMode.calculated:
      case WageDialogMode.editOnly:
        return AppColors.info;
      case WageDialogMode.confirmed:
        return AppColors.success;
    }
  }

  IconData get _headerIcon {
    switch (widget.mode) {
      case WageDialogMode.pending:
        return Icons.receipt_long;
      case WageDialogMode.calculated:
      case WageDialogMode.editOnly:
        return Icons.edit_outlined;
      case WageDialogMode.confirmed:
        return Icons.verified;
    }
  }

  String get _headerSubtitle {
    switch (widget.mode) {
      case WageDialogMode.pending:
        return '미확정 (급여 확정 필요)';
      case WageDialogMode.calculated:
        return '급여 확정됨 (수정 가능)';
      case WageDialogMode.editOnly:
        return '급여 수정';
      case WageDialogMode.confirmed:
        return '최종 확정됨';
    }
  }

  bool get _isEditable => widget.mode != WageDialogMode.confirmed;

  // ═══════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = widget.user?.name ?? '이름 없음';
    final screenWidth = MediaQuery.of(context).size.width;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 20)),
      ),
      child: Container(
        width: screenWidth * 0.9,
        constraints: BoxConstraints(maxWidth: screenWidth * 0.95),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, name),
            Flexible(
              child: SingleChildScrollView(
                padding: ResponsiveHelper.cardPadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildInfoSection(context, theme),
                    Divider(height: ResponsiveHelper.spacing(context, 24)),
                    _buildWageSection(context, theme),
                    if (_isEditable) ...[
                      Divider(height: ResponsiveHelper.spacing(context, 24)),
                      _buildAdditionalSection(context, theme),
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      _buildMemoSection(context, theme),
                    ],
                    if (!_isEditable) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      _buildConfirmedNotice(context),
                    ],
                  ],
                ),
              ),
            ),
            _buildBottomButtons(context, theme),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 헤더
  // ═══════════════════════════════════════════════════════════

  Widget _buildHeader(BuildContext context, String name) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: _headerColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(ResponsiveHelper.spacing(context, 20)),
          topRight: Radius.circular(ResponsiveHelper.spacing(context, 20)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
            ),
            child: Icon(
              _headerIcon,
              color: Colors.white,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name 급여 상세',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  _headerSubtitle,
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.close,
              color: Colors.white,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 근무 정보 섹션
  // ═══════════════════════════════════════════════════════════

  Widget _buildInfoSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '근무 정보',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        _buildInfoRow(context, '업무', widget.app.selectedWorkType),
        _buildInfoRow(context, '출근', widget.attendance.checkIn ?? '-'),
        _buildInfoRow(context, '퇴근', widget.attendance.checkOut ?? '-'),
        _buildInfoRow(context, '근무시간', '${_wage.workHours.toStringAsFixed(1)}시간'),
        if (_wage.overtimeMinutes > 0)
          _buildInfoRow(context, '연장근무', '${_wage.overtimeHours.toStringAsFixed(1)}시간', highlight: true),
        if (_wage.nightMinutes > 0)
          _buildInfoRow(context, '야간근무', '${_wage.nightHours.toStringAsFixed(1)}시간', highlight: true),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 급여 상세 섹션
  // ═══════════════════════════════════════════════════════════

  Widget _buildWageSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '급여 상세',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        _buildWageRow(context, '기본급', _wage.baseAmount),
        if (_wage.overtimeAmount > 0)
          _buildWageRow(context, '연장수당', _wage.overtimeAmount, highlight: true),
        if (_wage.nightAmount > 0)
          _buildWageRow(context, '야간수당', _wage.nightAmount, highlight: true),
        if (_wage.additionalAmount > 0)
          _buildWageRow(context, '추가수당', _wage.additionalAmount),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        _buildTotalRow(context),
      ],
    );
  }

  Widget _buildTotalRow(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.symmetricPadding(context, horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _headerColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '총 급여',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            FormatHelper.formatWage(_wage.totalAmount),
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: _headerColor,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 추가수당 섹션
  // ═══════════════════════════════════════════════════════════

  Widget _buildAdditionalSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '추가수당',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        TextField(
          controller: _additionalController,
          keyboardType: TextInputType.number,
          style: ResponsiveHelper.bodyStyle(context).copyWith(color: Colors.black87),
          decoration: InputDecoration(
            hintText: '0',
            hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
            suffixText: '원',
            suffixStyle: ResponsiveHelper.bodyStyle(context),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
            ),
            contentPadding: ResponsiveHelper.symmetricPadding(context, horizontal: 12, vertical: 12),
          ),
          onChanged: (_) => _updateWage(),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 메모 섹션
  // ═══════════════════════════════════════════════════════════

  Widget _buildMemoSection(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '메모',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.black87,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        TextField(
          controller: _memoController,
          maxLines: 2,
          style: ResponsiveHelper.bodyStyle(context).copyWith(color: Colors.black87),
          decoration: InputDecoration(
            hintText: '메모 입력 (선택)',
            hintStyle: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
            ),
            contentPadding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 최종확정 안내
  // ═══════════════════════════════════════════════════════════

  Widget _buildConfirmedNotice(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
        border: Border.all(color: AppColors.success.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lock,
            color: AppColors.success,
            size: ResponsiveHelper.iconSize(context, 18),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              '최종 확정된 급여입니다. 수정이 불가합니다.',
              style: ResponsiveHelper.smallStyle(context).copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 하단 버튼
  // ═══════════════════════════════════════════════════════════

  Widget _buildBottomButtons(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(ResponsiveHelper.spacing(context, 20)),
          bottomRight: Radius.circular(ResponsiveHelper.spacing(context, 20)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMainButtons(context, theme),
          if (widget.mode == WageDialogMode.calculated) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildCancelLink(context),
          ],
        ],
      ),
    );
  }

  Widget _buildMainButtons(BuildContext context, ThemeData theme) {
    switch (widget.mode) {
      case WageDialogMode.pending:
        return _buildPendingButtons(context, theme);
      case WageDialogMode.calculated:
        return _buildCalculatedButtons(context, theme);
      case WageDialogMode.editOnly:
        return _buildEditOnlyButtons(context, theme);
      case WageDialogMode.confirmed:
        return _buildConfirmedButtons(context, theme);
    }
  }

  /// 미확정 모드 버튼
  Widget _buildPendingButtons(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.grey600,
              side: BorderSide(color: theme.dividerColor),
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 14),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
              ),
            ),
            child: Text('취소', style: ResponsiveHelper.bodyStyle(context)),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () => _onAction('confirm'),
            icon: Icon(Icons.check, size: ResponsiveHelper.iconSize(context, 20)),
            label: Text(
              '급여 확정',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.warning,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 14),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 급여확정 모드 버튼
  Widget _buildCalculatedButtons(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _onAction('update'),
            icon: Icon(Icons.save, size: ResponsiveHelper.iconSize(context, 18)),
            label: Text('저장', style: ResponsiveHelper.bodyStyle(context)),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.primaryColor,
              side: BorderSide(color: theme.primaryColor),
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
              ),
            ),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () => _onAction('final_confirm'),
            icon: Icon(Icons.verified, size: ResponsiveHelper.iconSize(context, 20)),
            label: Text(
              '최종 확정',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.success,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 14),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 수정만 모드 버튼
  Widget _buildEditOnlyButtons(BuildContext context, ThemeData theme) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.grey600,
              side: BorderSide(color: theme.dividerColor),
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 14),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
              ),
            ),
            child: Text('취소', style: ResponsiveHelper.bodyStyle(context)),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          flex: 2,
          child: ElevatedButton.icon(
            onPressed: () => _onAction('update'),
            icon: Icon(Icons.save, size: ResponsiveHelper.iconSize(context, 20)),
            label: Text(
              '저장',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 14),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 최종확정 모드 버튼
  Widget _buildConfirmedButtons(BuildContext context, ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () => Navigator.pop(context),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 14),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
          ),
        ),
        child: Text(
          '확인',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  /// 급여 확정 취소 링크
  Widget _buildCancelLink(BuildContext context) {
    return TextButton(
      onPressed: () => _onAction('cancel'),
      child: Text(
        '급여 확정 취소',
        style: ResponsiveHelper.smallStyle(context, color: AppColors.error),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 공통 행 위젯
  // ═══════════════════════════════════════════════════════════

  Widget _buildInfoRow(BuildContext context, String label, String value, {bool highlight = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 4)),
      child: Row(
        children: [
          SizedBox(
            width: ResponsiveHelper.spacing(context, 70),
            child: Text(
              label,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: highlight ? _headerColor : Colors.black87,
                fontWeight: highlight ? FontWeight.w600 : null,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWageRow(BuildContext context, String label, int amount, {bool highlight = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 4)),
      child: Row(
        children: [
          SizedBox(
            width: ResponsiveHelper.spacing(context, 70),
            child: Text(
              label,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            ),
          ),
          Expanded(
            child: Text(
              FormatHelper.formatWage(amount),
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: highlight ? _headerColor : Colors.black87,
                fontWeight: highlight ? FontWeight.w600 : null,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}