import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:intl/intl.dart';
import '../../models/core/application_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/resign_auto_approval.dart';
import '../../utils/responsive_helper.dart';  // ⭐ 추가
import '../pickers/date_picker_bottom_sheet.dart';
import 'styled_dialog.dart';
import '../common/app_empty_state.dart';
import '../../utils/text_layout.dart';

/// 고정근무 관리 다이얼로그
class LongTermWorkManagementDialog extends StatefulWidget {
  final List<ApplicationModel> applications;
  final VoidCallback onChanged;

  const LongTermWorkManagementDialog({
    super.key,
    required this.applications,
    required this.onChanged,
  });

  @override
  State<LongTermWorkManagementDialog> createState() =>
      _LongTermWorkManagementDialogState();
}

class _LongTermWorkManagementDialogState
    extends State<LongTermWorkManagementDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    // 확정된 장기 근무만 필터링 (퇴사/해지 완료 제외)
    final longTermWorks = widget.applications
        .where((app) =>
            app.isLongTermApplication &&
            AppStatus.confirmedStatuses.contains(app.status) &&
            !app.isTerminationApproved)
        .toList();

    return AppModalShell(
      children: [
        AppModalHeader(
          title: '고정근무 관리',
          onClose: () => Navigator.pop(context),
        ),
        // 본문
        Expanded(
          child: longTermWorks.isEmpty
              ? _buildEmptyState()
              : Builder(builder: (context) {
                  final now = DateTime.now();
                  return ListView.builder(
                    padding: ResponsiveHelper.cardPadding(context),
                    itemCount: longTermWorks.length,
                    itemBuilder: (context, index) =>
                        _buildWorkCard(longTermWorks[index], now),
                  );
                }),
        ),
      ],
    );
  }

  /// 빈 상태
  /// [DU271] 직접 그린 빈 상태(disabledColor 아이콘·bodySmall 글자) → 공용 AppEmptyState(DU248 값, 문구 같음)
  Widget _buildEmptyState() {
    return const AppEmptyState(
      icon: Icons.work_off,
      title: '확정된 고정근무가 없습니다',
    );
  }

  /// 근무 카드
  Widget _buildWorkCard(ApplicationModel app, DateTime now) {
    final hasResignRequest = app.resignStatus != null;
    final isPending = app.resignStatus == AppStatus.pending;
    final isRejected = app.resignStatus == AppStatus.rejected;

    // [DU271] 그림자 Card → 흰 면·radius 16·grey200 선(시안 카드)
    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 12),
      ),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey200),
      ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 사업장명
            Row(
              children: [
                Icon(
                  Icons.business, 
                  size: ResponsiveHelper.iconSize(context, 18),  // ⭐ 변경
                  color: AppColors.textSecondary, // [DU271] 대표색 → 중립 아이콘
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                Expanded(
                  child: Text(
                    TextLayout.identity(app.businessName),
                    semanticsLabel: app.businessName,
                    style: ResponsiveHelper.subtitleStyle(context),  // ⭐ 변경
                  ),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경

            // 근무 기간
            _buildInfoRow(
              Icons.calendar_today,
              '근무 기간',
              app.workPeriodDisplay,
              shown: TextLayout.keepWords(app.workPeriodDisplay),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경

            // 근무 요일
            if (app.workDaysDisplay != null)
              _buildInfoRow(
                Icons.event_repeat,
                '근무 요일',
                app.workDaysDisplay!,
                shown: TextLayout.keepWords(app.workDaysDisplay!),
              ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경

            // 근무 시간
            _buildInfoRow(
              Icons.access_time,
              '근무 시간',
              '${app.startTime} ~ ${app.endTime}',
              shown: TextLayout.range(app.startTime, app.endTime),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경

            // 업무 유형 & 급여
            // [DU271] 큰 글자(DU256 규칙)에서는 반 폭 두 칸 대신 위·아래 두 줄(B320 '상/하/차'·'12/,0/00/원')
            if (MediaQuery.textScalerOf(context).scale(10) >= 13) ...[
              _buildInfoRow(Icons.work, '업무', app.selectedWorkType,
                  shown: TextLayout.identity(app.selectedWorkType)),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              _buildInfoRow(Icons.attach_money, '급여', FormatHelper.formatWage(app.wage),
                  shown: TextLayout.keepWords(FormatHelper.formatWage(app.wage))),
            ] else
              Row(
                children: [
                  Expanded(
                    child: _buildInfoRow(
                      Icons.work,
                      '업무',
                      app.selectedWorkType,
                      shown: TextLayout.identity(app.selectedWorkType),
                    ),
                  ),
                  Expanded(
                    child: _buildInfoRow(
                      Icons.attach_money,
                      '급여',
                      FormatHelper.formatWage(app.wage),
                      shown: TextLayout.keepWords(FormatHelper.formatWage(app.wage)),
                    ),
                  ),
                ],
              ),

            // 퇴사 요청 상태 표시
            if (hasResignRequest) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
              _buildResignStatusBanner(app, now),
            ],

            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경

            // 버튼
            // [DU271] 퇴사 진입은 중립 테두리 버튼(DU245 — 위험색은 확인 순간에만). 이전 빨강 테두리 3.68·빨강 채움 3.68·주황 2.16.
            if (isPending)
              // 퇴사 요청 대기 중 - 취소 버튼만
              _entryButton(Icons.cancel_outlined, '퇴사 요청 취소', () => _handleCancelResignRequest(app))
            else if (isRejected)
              // 퇴사 거절됨 - 재요청 버튼
              _entryButton(Icons.refresh, '퇴사 재요청', () => _handleResignRequest(app))
            else
              // 정상 상태 - 퇴사 요청 버튼
              _entryButton(Icons.exit_to_app, '퇴사 요청', () => _handleResignRequest(app)),
          ],
        ),
    );
  }

  /// [DU271] 퇴사 진입 버튼 — 공용 Outlined 테마(grey300 선·48) + 보조색 글자, 낱말 단위 줄바꿈. 아이콘·문구·동작은 같다.
  Widget _entryButton(IconData icon, String label, VoidCallback onPressed) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(TextLayout.keepWords(label), semanticsLabel: label),
          style: OutlinedButton.styleFrom(foregroundColor: AppColors.textSecondary),
        ),
      );

  /// 퇴사 상태 배너
  Widget _buildResignStatusBanner(ApplicationModel app, DateTime now) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String statusText;
    String? detailText;

    switch (app.resignStatus) {
      case AppStatus.pending:
        // [DU271] 의미색 10% 면·원색 글자(1.99~3.23) → 토큰 쌍(대기 4.81·거절 5.80·승인 6.47)
        bgColor = AppColors.warningBg;
        textColor = AppColors.warningDark;
        icon = Icons.schedule;
        statusText = '퇴사 승인 대기중';
        final requestDate = DateFormat('M월 d일').format(app.resignRequestDate ?? DateTime.now());
        // [D3-RETRO-EXCLUDE] 소급 요청은 자동 승인되지 않는다 — 일정은 서버와 같은 식(KST 날짜)으로 정한다.
        //   이전 식(경과 시간 floor)은 D+3 이 지나면 음수 일수를 보였다.
        final plan = ResignAutoApproval.of(
          requestedAt: app.resignRequestedAt,
          requestDate: app.resignRequestDate,
          now: now,
        );
        detailText = '$requestDate 퇴사 요청 (${plan.workerDetailText})';
        break;
      case AppStatus.rejected:
        bgColor = AppColors.errorBg;
        textColor = AppColors.errorDark;
        icon = Icons.cancel;
        statusText = '퇴사 요청 거절됨';
        detailText = app.resignRejectReason ?? '사유 없음';
        break;
      case AppStatus.approved:
      case AppStatus.autoApproved:
        bgColor = AppColors.successBg;
        textColor = AppColors.successDark;
        icon = Icons.check_circle;
        statusText = app.resignStatus == AppStatus.autoApproved ? '퇴사 자동 승인됨' : '퇴사 승인됨';
        final resignDate = DateFormat('M월 d일').format(app.actualResignDate ?? DateTime.now());
        detailText = '$resignDate자로 퇴사 처리';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12), // [DU271] 선 제거(다른 안내 면과 같음)
      ),
      child: Row(
        children: [
          Icon(
            icon, 
            color: textColor, 
            size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  TextLayout.keepWords(statusText),
                  semanticsLabel: statusText,
                  style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                    context,
                    color: textColor,
                  ).copyWith(fontWeight: FontWeight.bold),
                ),
                ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                // [DU271] tiny·알파 0.8 → smallStyle 같은 진한 색, 낱말 단위(화면 읽기는 원문)
                Text(
                  TextLayout.keepWords(detailText),
                  semanticsLabel: detailText,
                  style: ResponsiveHelper.smallStyle(context, color: textColor),
                ),
              ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 정보 행
  /// [DU271] 아이콘·이름 textSecondary, 값 본문색 w600(이전 grey600 4.61). 값 표시만 줄바꿈 단위([shown], 화면 읽기는 원문).
  ///   큰 글자(DU256 규칙)에서는 이름 줄 위·값 아래(아이콘 폭만큼 들여쓰기) — 좁은 값 칸에서 음절이 끊겼다.
  Widget _buildInfoRow(IconData icon, String label, String value, {String? shown}) {
    final iconW = Icon(
      icon,
      size: ResponsiveHelper.iconSize(context, 16),
      color: AppColors.textSecondary,
    );
    final gap = ResponsiveHelper.spacing(context, 8);
    final labelW = Text(
      '$label: ',
      style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
    );
    final valueW = Text(
      shown ?? value,
      semanticsLabel: value,
      style: ResponsiveHelper.smallStyle(context,
          color: AppColors.textPrimary, fontWeight: FontWeight.w600),
    );
    if (MediaQuery.textScalerOf(context).scale(10) >= 13) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [iconW, SizedBox(width: gap), Flexible(child: labelW)]),
          Padding(
            padding: EdgeInsets.only(left: ResponsiveHelper.iconSize(context, 16) + gap),
            child: valueW,
          ),
        ],
      );
    }
    return Row(
      children: [
        iconW,
        SizedBox(width: gap),
        labelW,
        Expanded(child: valueW),
      ],
    );
  }

  /// 퇴사 요청
  Future<void> _handleResignRequest(ApplicationModel app) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final resignDate = await DatePickerBottomSheet.show(
        context: context,
        title: '퇴사 희망일 선택',
        minDate: DateTime.now(),
        maxDate: app.workEndDate ?? DateTime.now().add(const Duration(days: 365)),
      );

      if (resignDate == null || !mounted) return;

      // [D3-RETRO-EXCLUDE] 희망일이 오늘(KST)보다 이르면 소급 요청 — 서버가 자동 승인하지 않는다.
      final isRetro = ResignAutoApproval.isRetro(
          requestedAt: DateTime.now(), requestDate: resignDate);
      final confirmed = await DialogHelper.showConfirm(
        context,
        title: '퇴사 요청',
        message:
            '${DateFormat('yyyy년 M월 d일').format(resignDate)}자로 퇴사 요청합니다.\n\n'
            '${isRetro
                ? '✓ 지난 날짜로 요청하면 자동 승인되지 않고 관리자가 직접 검토합니다\n'
                : '✓ 관리자가 3일 이내에 승인/거절합니다\n'
                  '✓ 3일 후에도 처리가 없으면 자동 승인됩니다\n'}'
            '✓ 승인 전까지 요청을 취소할 수 있습니다\n\n'
            '요청하시겠습니까?',
        confirmText: '퇴사 요청',
        confirmColor: AppColors.errorDark, // [DU271] 확정 순간의 위험색은 유지하고 읽히게(3.68 → errorDark)
      );

      if (!confirmed || !mounted) return;

      final success = await _firestoreService.requestResignation(
        applicationId: app.id,
        resignDate: resignDate,
      );

      if (!mounted) return;
      if (success) {
        ToastHelper.showSuccess('퇴사 요청이 완료되었습니다.');
        widget.onChanged();
      } else {
        ToastHelper.showError('퇴사 요청 중 오류가 발생했습니다.');
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('퇴사 요청 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// 퇴사 요청 취소
  Future<void> _handleCancelResignRequest(ApplicationModel app) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final confirmed = await DialogHelper.showConfirm(
        context,
        title: '퇴사 요청 취소',
        message: '퇴사 요청을 취소하시겠습니까?',
        confirmText: '취소하기',
        confirmColor: AppColors.brand, // [DU271] 요청 취소는 위험 행동이 아니다(warning 위 흰 2.16 → 대표색)
      );

      if (!confirmed || !mounted) return;

      final success = await _firestoreService.cancelResignRequest(app.id);

      if (!mounted) return;
      if (success) {
        ToastHelper.showSuccess('퇴사 요청이 취소되었습니다.');
        widget.onChanged();
      } else {
        ToastHelper.showError('취소 중 오류가 발생했습니다.');
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('취소 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}