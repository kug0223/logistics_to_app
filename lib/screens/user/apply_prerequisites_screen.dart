import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../common/document_management_screen.dart';

/// 지원 전 준비사항 체크 전체 화면.
///
/// 미충족 항목이 있으면 이 화면으로 push되고, 모든 항목 충족 후 "지원하기" 버튼을 누르면
/// `Navigator.pop(context, true)`로 복귀 — 호출자가 실제 지원 흐름을 계속 진행.
///
/// 사용법:
/// ```dart
/// final ok = await ApplyPrerequisitesScreen.show(context, isFlexType: to.isFlexType);
/// if (ok && mounted) { /* 지원 다이얼로그 열기 */ }
/// ```
class ApplyPrerequisitesScreen extends StatefulWidget {
  final bool isFlexType;

  const ApplyPrerequisitesScreen({super.key, required this.isFlexType});

  static Future<bool> show(BuildContext context, {required bool isFlexType}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ApplyPrerequisitesScreen(isFlexType: isFlexType),
      ),
    );
    return result == true;
  }

  @override
  State<ApplyPrerequisitesScreen> createState() => _ApplyPrerequisitesScreenState();
}

class _ApplyPrerequisitesScreenState extends State<ApplyPrerequisitesScreen> {
  bool _isLoading = false;

  UserModel? get _user =>
      context.read<UserProvider>().currentUser;

  bool get _idCardReady {
    final u = _user;
    return u != null && u.idCardImageUrl != null && u.idCardImageUrl!.isNotEmpty;
  }

  bool get _idVerified => _user?.isIdVerified ?? false;

  bool get _accountReady {
    final u = _user;
    return u != null &&
        u.bankName != null && u.bankName!.isNotEmpty &&
        u.accountNumber != null && u.accountNumber!.isNotEmpty;
  }

  bool get _bankbookReady {
    final u = _user;
    return u != null && u.bankbookImageUrl != null && u.bankbookImageUrl!.isNotEmpty;
  }

  bool get _isBlacklisted => _user?.isBlacklisted ?? false;

  bool get _isRestricted {
    final u = _user;
    return u != null && u.isRestricted;
  }

  int? get _restrictedRemainDays {
    final until = _user?.restrictedUntil;
    if (until == null) return null; // 영구 제한 — 일수 없음
    return until.difference(DateTime.now()).inDays + 1;
  }

  bool get _allPrerequisitesMet {
    if (_isBlacklisted || _isRestricted) return false;
    if (!_idCardReady) return false;
    if (widget.isFlexType && !_idVerified) return false;
    if (!_accountReady) return false;
    if (!_bankbookReady) return false;
    return true;
  }

  int get _totalItemCount => widget.isFlexType ? 4 : 3;

  Future<void> _reCheck() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await context.read<UserProvider>().refreshCurrentUser();
    } catch (e) {
      if (mounted) ToastHelper.showError('새로고침에 실패했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientScaffold(
      title: '지원하기',
      body: _isLoading
          ? const LoadingWidget()
          : SingleChildScrollView(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 이용제한 / 블랙리스트 배너
                  if (_isBlacklisted) ...[
                    _buildRestrictionBanner(
                      icon: Icons.block,
                      color: AppColors.error,
                      message: '이용이 영구 제한된 계정입니다. 지원이 불가합니다.',
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  ] else if (_isRestricted) ...[
                    _buildRestrictionBanner(
                      icon: Icons.timer_off_outlined,
                      color: AppColors.warning,
                      message: _restrictedRemainDays != null
                          ? '무단 결근 패널티로 $_restrictedRemainDays일간 지원이 제한됩니다.'
                          : '무단 결근 패널티로 이용이 제한되어 있습니다.',
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  ],

                  // 안내 헤더
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                    decoration: BoxDecoration(
                      color: theme.primaryColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.assignment_outlined,
                            color: theme.primaryColor,
                            size: ResponsiveHelper.iconSize(context, 28)),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('지원 전 준비사항',
                                  style: ResponsiveHelper.subtitleStyle(context)
                                      .copyWith(fontWeight: FontWeight.bold)),
                              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                              Text(
                                '아래 $_totalItemCount가지를 모두 완료해야 지원할 수 있습니다.',
                                style: ResponsiveHelper.smallStyle(context,
                                    color: AppColors.grey600),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                  // 1. 신분증 등록
                  _buildPrerequisiteCard(
                    index: 1,
                    title: '신분증 등록',
                    isReady: _idCardReady,
                    readyDescription: '신분증이 등록되어 있습니다',
                    notReadyDescription: '신분증 등록이 필요합니다.',
                    actionLabel: '서류 관리',
                    onAction: () async {
                      await NavigationHelper.push<void>(
                          context, destination: const DocumentManagementScreen());
                      if (!mounted) return;
                      await _reCheck();
                    },
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),

                  // 2. 신분증 인증 (단기 공고만)
                  if (widget.isFlexType) ...[
                    _buildPrerequisiteCard(
                      index: 2,
                      title: '신분증 인증',
                      isReady: _idVerified,
                      readyDescription: '신분증 인증이 완료되었습니다',
                      notReadyDescription: '단기 공고 지원 시 신분증 인증이 필요합니다.',
                      actionLabel: '서류 관리',
                      onAction: () async {
                        await NavigationHelper.push<void>(
                            context, destination: const DocumentManagementScreen());
                        if (!mounted) return;
                        await _reCheck();
                      },
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  ],

                  // 계좌 정보 (flex: 3번 / contract: 2번)
                  _buildPrerequisiteCard(
                    index: widget.isFlexType ? 3 : 2,
                    title: '계좌 정보 등록',
                    isReady: _accountReady,
                    readyDescription: '계좌 정보가 등록되어 있습니다',
                    notReadyDescription: '계좌 정보 등록이 필요합니다.',
                    actionLabel: '서류 관리',
                    onAction: () async {
                      await NavigationHelper.push<void>(
                          context, destination: const DocumentManagementScreen());
                      if (!mounted) return;
                      await _reCheck();
                    },
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),

                  // 통장사본 (flex: 4번 / contract: 3번)
                  _buildPrerequisiteCard(
                    index: widget.isFlexType ? 4 : 3,
                    title: '통장사본 등록',
                    isReady: _bankbookReady,
                    readyDescription: '통장사본이 등록되어 있습니다',
                    notReadyDescription: '통장사본 등록이 필요합니다.',
                    actionLabel: '서류 관리',
                    onAction: () async {
                      await NavigationHelper.push<void>(
                          context, destination: const DocumentManagementScreen());
                      if (!mounted) return;
                      await _reCheck();
                    },
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 32)),

                  // 하단 버튼
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _reCheck,
                          icon: const Icon(Icons.refresh),
                          label: const Text('다시 확인'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                                vertical: ResponsiveHelper.spacing(context, 14)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _allPrerequisitesMet
                              ? () => Navigator.pop(context, true)
                              : null,
                          icon: const Icon(Icons.send_outlined),
                          label: const Text('지원하기'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: AppColors.grey300,
                            padding: EdgeInsets.symmetric(
                                vertical: ResponsiveHelper.spacing(context, 14)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRestrictionBanner({
    required IconData icon,
    required Color color,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: ResponsiveHelper.iconSize(context, 20)),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Text(
              message,
              style: ResponsiveHelper.smallStyle(context).copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrerequisiteCard({
    required int index,
    required String title,
    required bool isReady,
    required String readyDescription,
    required String notReadyDescription,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final theme = Theme.of(context);
    final color = isReady ? AppColors.success : AppColors.error;

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isReady
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.grey300,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.grey500.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                isReady ? Icons.check_circle : Icons.radio_button_unchecked,
                color: color,
                size: ResponsiveHelper.iconSize(context, 22),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('$index.',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey500)),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Flexible(
                      child: Text(title,
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  isReady ? readyDescription : notReadyDescription,
                  style: ResponsiveHelper.smallStyle(context,
                      color: isReady ? AppColors.successDark : AppColors.grey600),
                ),
              ],
            ),
          ),
          if (!isReady && actionLabel != null && onAction != null) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            TextButton(
              onPressed: _isLoading ? null : onAction,
              style: TextButton.styleFrom(
                foregroundColor: theme.primaryColor,
                padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 10),
                    vertical: ResponsiveHelper.spacing(context, 6)),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel,
                      style: ResponsiveHelper.smallStyle(context,
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                  Icon(Icons.arrow_forward_ios,
                      size: ResponsiveHelper.iconSize(context, 12),
                      color: theme.primaryColor),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 지원 전 요구사항 충족 여부 순수 체크 함수.
/// 다이얼로그 없이 bool만 반환 — UI 결정은 호출자가 담당.
bool meetsApplyPrerequisites(UserModel user, {required bool isFlexType}) {
  // 블랙리스트·제재 계정: 문서 갖춰도 지원 불가 — CF 차단과 동일
  // restrictedUntil 만료 체크 포함 (위젯 _isRestricted getter와 동일 로직)
  if (user.isBlacklisted || user.isRestricted) {
    return false;
  }
  if (!user.isPassVerified) {
    return false;
  }
  if (user.idCardImageUrl == null || user.idCardImageUrl!.isEmpty) {
    return false;
  }
  if (isFlexType && !user.isIdVerified) {
    return false;
  }
  if (user.bankName == null || user.bankName!.isEmpty ||
      user.accountNumber == null || user.accountNumber!.isEmpty) {
    return false;
  }
  if (user.bankbookImageUrl == null || user.bankbookImageUrl!.isEmpty) {
    return false;
  }
  return true;
}
