import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/to_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/responsive_helper.dart';

/// 지원하기 확인 다이얼로그
class ApplyDialog {
  static Future<bool> show({
    required BuildContext context,
    required WorkDetailModel work,
    required TOModel to,
    required VoidCallback onSuccess,
  }) async {
    final result = await showDialog<_ApplyResult>(
      context: context,
      builder: (dialogContext) => _ApplyDialogContent(work: work, to: to),
    );

    if (result?.confirmed == true && context.mounted) {
      return _applyToWork(
        context: context,
        work: work,
        to: to,
        onSuccess: onSuccess,
        desiredStartDate: result?.desiredStartDate,
      );
    }

    return false;
  }

  /// 실제 지원 처리
  static Future<bool> _applyToWork({
    required BuildContext context,
    required WorkDetailModel work,
    required TOModel to,
    required VoidCallback onSuccess,
    DateTime? desiredStartDate,
  }) async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인이 필요합니다.');
        return false;
      }

      final firestoreService = FirestoreService();

      // 중복 체크는 callableApplyToTO CF에서 서버 검증 수행
      // [CF-MIGRATED 2026-07-15] applications list: if isSuperAdmin() only
      //   클라이언트 직접 list 쿼리는 항상 PERMISSION_DENIED — CF 단일 경로로 정리
      if (!context.mounted) return false;

      final success = await firestoreService.applyToTOWithWorkType(
        uid: uid,
        businessId: to.businessId,
        businessName: to.businessName,
        toTitle: to.title,
        workDate: to.date,
        selectedWorkType: work.workType,
        workDetailId: work.id,
        wage: work.wage,
        wageType: work.wageType,
        workTypeIcon: work.workTypeIcon,
        workTypeColor: work.workTypeColor,
        workTypeBackgroundColor: work.workTypeBackgroundColor,
        startTime: work.startTime,
        endTime: work.endTime,
        workEndDate: to.endDate,
        workDays: to.workDays,
        type: to.isLongTerm ? 'long_term' : 'short',
        desiredStartDate: desiredStartDate,
      );

      if (!context.mounted) return false;
      if (success) {
        ToastHelper.showSuccess('지원이 완료되었습니다!');
        debugPrint('🎉 지원 성공! onSuccess() 호출');
        onSuccess();
        debugPrint('✅ onSuccess() 호출 완료');
        return true;
      } else {
        ToastHelper.showError('지원에 실패했습니다.');
        return false;
      }
    } catch (e) {
      debugPrint('❌ 지원 실패: $e');
      if (!context.mounted) return false;
      ToastHelper.showError('지원 중 오류가 발생했습니다.');
      return false;
    }
  }
}

class _ApplyResult {
  final bool confirmed;
  final DateTime? desiredStartDate;
  _ApplyResult({required this.confirmed, this.desiredStartDate});
}

/// 지원 다이얼로그 콘텐츠 — 장기 공고 시 희망 시작일 필수 입력 포함
class _ApplyDialogContent extends StatefulWidget {
  final WorkDetailModel work;
  final TOModel to;

  const _ApplyDialogContent({required this.work, required this.to});

  @override
  State<_ApplyDialogContent> createState() => _ApplyDialogContentState();
}

class _ApplyDialogContentState extends State<_ApplyDialogContent> {
  DateTime? _desiredStartDate;
  bool _isSubmitting = false;

  bool get _canSubmit =>
      !_isSubmitting && (!widget.to.isLongTerm || _desiredStartDate != null);

  Future<void> _pickStartDate() async {
    final today = DateTime.now();
    final rangeStart = widget.to.rangeStart;
    final rangeEnd = widget.to.endDate;

    // 선택 가능 최소: 오늘 or 공고 시작일 중 더 늦은 날
    final firstDate = (rangeStart != null && rangeStart.isAfter(today))
        ? rangeStart
        : today;
    // 선택 가능 최대: 공고 종료일 or 1년 후
    final lastDate = rangeEnd ?? DateTime(today.year + 1, today.month, today.day);

    final picked = await showDatePicker(
      context: context,
      initialDate: _desiredStartDate ?? firstDate,
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: '희망 근무 시작일 선택',
      confirmText: '선택',
      cancelText: '취소',
    );

    if (picked != null && mounted) {
      setState(() => _desiredStartDate = picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final work = widget.work;
    final to = widget.to;

    return AlertDialog(
      title: const Text('지원하기'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '다음 업무에 지원하시겠습니까?',
            style: ResponsiveHelper.bodyStyle(context,
                color: AppColors.grey700),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    WorkTypeIcon.buildWithBackground(
                      iconString: work.workTypeIcon,
                      iconColor: work.workTypeColor,
                      backgroundColor: work.workTypeBackgroundColor,
                      size: 18,
                      containerSize: 36,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        work.workType,
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  icon: Icons.access_time,
                  text: '${work.startTime} ~ ${work.endTime}',
                ),
                const SizedBox(height: 4),
                _buildInfoRow(
                  icon: Icons.attach_money,
                  text: FormatHelper.formatWage(work.wage),
                  color: AppColors.successDark,
                ),
              ],
            ),
          ),

          // [B-4] 장기 공고: 희망 시작일 필수 입력
          if (to.isLongTerm) ...[
            const SizedBox(height: 16),
            Text(
              '희망 근무 시작일 *',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey700),
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: _pickStartDate,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _desiredStartDate == null
                        ? AppColors.error
                        : AppColors.grey300,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: ResponsiveHelper.iconSize(context, 16),
                      color: _desiredStartDate == null
                          ? AppColors.error
                          : AppColors.grey600,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _desiredStartDate != null
                            ? FormatHelper.formatDate(_desiredStartDate!)
                            : '날짜를 선택해주세요',
                        style: ResponsiveHelper.bodyStyle(context,
                            color: _desiredStartDate == null
                                ? AppColors.error
                                : AppColors.grey800),
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: ResponsiveHelper.iconSize(context, 16),
                      color: AppColors.grey400,
                    ),
                  ],
                ),
              ),
            ),
            if (_desiredStartDate == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '장기 근무 지원 시 희망 시작일을 반드시 선택해야 합니다',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.error),
                ),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _ApplyResult(confirmed: false)),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _canSubmit
              ? () async {
                  setState(() => _isSubmitting = true);
                  try {
                    Navigator.pop(
                      context,
                      _ApplyResult(
                        confirmed: true,
                        desiredStartDate: _desiredStartDate,
                      ),
                    );
                  } finally {
                    if (mounted) setState(() => _isSubmitting = false);
                  }
                }
              : null,
          child: const Text('지원하기'),
        ),
      ],
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String text,
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon,
            size: ResponsiveHelper.iconSize(context, 14),
            color: color ?? AppColors.grey600),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: ResponsiveHelper.smallStyle(context,
                color: color ?? AppColors.grey700),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ],
    );
  }
}
