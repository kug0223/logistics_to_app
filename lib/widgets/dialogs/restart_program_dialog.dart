// lib/widgets/dialogs/restart_program_dialog.dart

import 'package:flutter/material.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import '../../services/trust_score_service.dart';
import '../../utils/toast_helper.dart';
import 'styled_dialog.dart';

/// 재시작 프로그램 다이얼로그
/// 
/// 정책:
/// - 신뢰도 50점으로 리셋
/// - 노쇼 1회, 지각 1회 감면
/// - 2개월 쿨타임
class RestartProgramDialog extends StatefulWidget {
  final String userId;
  final int currentScore;
  final int noShowCount;
  final int lateCount;
  final VoidCallback? onSuccess;

  const RestartProgramDialog({
    super.key,
    required this.userId,
    required this.currentScore,
    required this.noShowCount,
    required this.lateCount,
    this.onSuccess,
  });

  @override
  State<RestartProgramDialog> createState() => _RestartProgramDialogState();
}

class _RestartProgramDialogState extends State<RestartProgramDialog> {
  final _trustService = TrustScoreService();
  
  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _canRestart = false;
  String? _reason;
  int? _daysRemaining;
  bool _agreed = false;

  @override
  void initState() {
    super.initState();
    _checkCanRestart();
  }

  Future<void> _checkCanRestart() async {
    setState(() => _isLoading = true);
    
    final result = await _trustService.canApplyRestart(widget.userId);
    
    setState(() {
      _canRestart = result.canRestart;
      _reason = result.reason;
      _daysRemaining = result.daysRemaining;
      _isLoading = false;
    });
  }

  Future<void> _applyRestart() async {
    if (!_agreed) {
      ToastHelper.showWarning('준수사항에 동의해주세요.');
      return;
    }
    
    setState(() => _isSubmitting = true);
    
    final success = await _trustService.applyRestartProgram(widget.userId);
    
    if (success) {
      ToastHelper.showSuccess('재시작 프로그램이 적용되었습니다!');
      widget.onSuccess?.call();
      if (mounted) Navigator.pop(context, true);
    } else {
      ToastHelper.showError('재시작 프로그램 적용에 실패했습니다.');
      setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return StyledDialog(
      title: '재시작 프로그램',
      icon: Icons.refresh,
      headerColor: theme.primaryColor,
      content: _isLoading
          ? Center(
              child: Padding(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 32)),
                child: CircularProgressIndicator(),
              ),
            )
          : _buildContent(context),
      actions: _isLoading
          ? []
          : [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('취소'),
              ),
              if (_canRestart)
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _applyRestart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                  child: _isSubmitting
                      ? SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(Colors.white),
                          ),
                        )
                      : Text('신청하기'),
                ),
            ],
    );
  }

  Widget _buildContent(BuildContext context) {
    if (!_canRestart) {
      return _buildCooldownMessage(context);
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 안내 메시지
        Container(
          padding: ResponsiveHelper.cardPadding(context),
          decoration: BoxDecoration(
            color: AppColors.info.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                color: AppColors.info,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Text(
                  '새로운 시작을 응원합니다!\n재시작 프로그램으로 신뢰도를 리셋할 수 있습니다.',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.info),
                ),
              ),
            ],
          ),
        ),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 20)),
        
        // 현재 상태 → 변경 후
        _buildComparisonCard(context),
        
        SizedBox(height: ResponsiveHelper.spacing(context, 20)),
        
        // 준수사항
        _buildAgreementSection(context),
      ],
    );
  }

  Widget _buildCooldownMessage(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            Icons.timer_outlined,
            color: AppColors.warning,
            size: ResponsiveHelper.iconSize(context, 48),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            '쿨타임 중입니다',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.warning,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          if (_daysRemaining != null)
            Text(
              '$_daysRemaining일 후 다시 신청할 수 있습니다.',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
              textAlign: TextAlign.center,
            ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '재시작 프로그램은 2개월에 1회만\n이용할 수 있습니다.',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonCard(BuildContext context) {
    final theme = Theme.of(context);
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        children: [
          // 헤더
          Row(
            children: [
              Expanded(
                child: Text(
                  '현재',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                  textAlign: TextAlign.center,
                ),
              ),
              Icon(Icons.arrow_forward, color: theme.primaryColor),
              Expanded(
                child: Text(
                  '변경 후',
                  style: ResponsiveHelper.smallStyle(context, color: theme.primaryColor),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Divider(height: 1),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 신뢰도
          _buildCompareRow(
            context,
            label: '신뢰도',
            current: '${widget.currentScore}점',
            after: '50점',
            currentColor: _getScoreColor(widget.currentScore),
            afterColor: AppColors.grey600,
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          // 노쇼
          _buildCompareRow(
            context,
            label: '노쇼',
            current: '${widget.noShowCount}회',
            after: '${(widget.noShowCount - 1).clamp(0, 999)}회',
            currentColor: widget.noShowCount > 0 ? AppColors.error : AppColors.grey600,
            afterColor: AppColors.success,
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          // 지각
          _buildCompareRow(
            context,
            label: '지각',
            current: '${widget.lateCount}회',
            after: '${(widget.lateCount - 1).clamp(0, 999)}회',
            currentColor: widget.lateCount > 0 ? AppColors.warning : AppColors.grey600,
            afterColor: AppColors.success,
          ),
        ],
      ),
    );
  }

  Widget _buildCompareRow(
    BuildContext context, {
    required String label,
    required String current,
    required String after,
    required Color currentColor,
    required Color afterColor,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            label,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
          ),
        ),
        Expanded(
          child: Text(
            current,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: currentColor,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        SizedBox(width: 32), // 화살표 공간
        Expanded(
          child: Text(
            after,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: afterColor,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _buildAgreementSection(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.warning.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '📋 반드시 지켜주세요',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          _buildRuleItem(context, '1️⃣', '시간 약속', '출근 시간 10분 전까지 도착해주세요.'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          _buildRuleItem(context, '2️⃣', '사전 연락', '불참이 예상되면 반드시 미리 연락하세요.'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          _buildRuleItem(context, '3️⃣', '성실 근무', '맡은 업무를 책임감 있게 완수해주세요.'),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 동의 체크박스
          InkWell(
            onTap: () => setState(() => _agreed = !_agreed),
            borderRadius: BorderRadius.circular(8),
            child: Row(
              children: [
                Checkbox(
                  value: _agreed,
                  onChanged: (v) => setState(() => _agreed = v ?? false),
                  activeColor: Theme.of(context).primaryColor,
                ),
                Expanded(
                  child: Text(
                    '위 내용을 확인했으며, 성실히 이행하겠습니다.',
                    style: ResponsiveHelper.smallStyle(context),
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          
          Text(
            '⚠️ 재시작 후에도 노쇼/지각이 반복되면\n다음 재시작까지 2개월을 기다려야 합니다.',
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleItem(BuildContext context, String emoji, String title, String desc) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: ResponsiveHelper.bodyStyle(context)),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                desc,
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getScoreColor(int score) {
    if (score >= 90) return Color(0xFFFFD700);
    if (score >= 70) return AppColors.success;
    if (score >= 50) return AppColors.grey600;
    if (score >= 30) return AppColors.warning;
    return AppColors.error;
  }
}

/// 재시작 프로그램 다이얼로그 표시 헬퍼
Future<bool?> showRestartProgramDialog(
  BuildContext context, {
  required String userId,
  required int currentScore,
  required int noShowCount,
  required int lateCount,
  VoidCallback? onSuccess,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => RestartProgramDialog(
      userId: userId,
      currentScore: currentScore,
      noShowCount: noShowCount,
      lateCount: lateCount,
      onSuccess: onSuccess,
    ),
  );
}