// lib/screens/super_admin/system_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import '../../utils/toast_helper.dart';
import 'trust_rules_settings_screen.dart';
import 'review_tags_settings_screen.dart';
import 'badge_settings_screen.dart';
import 'minimum_wage_settings_screen.dart';
import 'insurance_rate_settings_screen.dart';
import 'to_limit_settings_screen.dart';
import 'business_approval_settings_screen.dart';
import '../../widgets/common/gradient_scaffold.dart';

/// 슈퍼관리자 시스템 설정 화면
///
/// 신뢰도 규칙, 리뷰 태그, 배지 등 시스템 전반 설정 관리
class SystemSettingsScreen extends StatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final up = Provider.of<UserProvider>(context, listen: false);
      if (!up.isSuperAdmin) {
        ToastHelper.showError('슈퍼관리자만 접근할 수 있습니다.');
        Navigator.pop(context);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '시스템 설정',
      body: ListView(
        padding: ResponsiveHelper.cardPadding(context),
        children: [
          // 안내 카드
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: AppColors.infoBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.admin_panel_settings,
                  size: ResponsiveHelper.iconSize(context, 32),
                  color: AppColors.infoDark,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Text(
                    '앱 전체에 적용되는 시스템 설정입니다.\n변경 시 주의해주세요.',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: AppColors.infoDark,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          
          // 설정 메뉴들
          _buildSettingSection(
            context,
            title: '리뷰 & 신뢰도',
            items: [
              _SettingItem(
                icon: Icons.analytics_outlined,
                title: '신뢰도 규칙',
                subtitle: '점수 증감 규칙, 재시작 프로그램 설정',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TrustRulesSettingsScreen(),
                  ),
                ),
              ),
              _SettingItem(
                icon: Icons.label_outline,
                title: '리뷰 태그',
                subtitle: '긍정/개선 태그 관리',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ReviewTagsSettingsScreen(),
                  ),
                ),
              ),
              _SettingItem(
                icon: Icons.emoji_events_outlined,
                title: '배지 관리',
                subtitle: '배지 추가/수정/활성화',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BadgeSettingsScreen(),
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          
          // 추가 설정 (향후 확장)
          _buildSettingSection(
            context,
            title: '기타 설정',
            items: [
              _SettingItem(
                icon: Icons.monetization_on_outlined,
                title: '최저시급 설정',
                subtitle: '연도별 최저시급 관리',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MinimumWageSettingsScreen(),
                  ),
                ),
              ),
              _SettingItem(
                icon: Icons.account_balance_outlined,
                title: '보험료율 설정',
                subtitle: '연도별 4대보험·소득세 요율 관리',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const InsuranceRateSettingsScreen(),
                  ),
                ),
              ),
              _SettingItem(
                icon: Icons.business_center_outlined,
                title: '공고 등록 개수 제한',
                subtitle: '사업장 당 동시 진행 공고 최대 개수',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const TOLimitSettingsScreen(),
                  ),
                ),
              ),
              _SettingItem(
                icon: Icons.domain_verification_outlined,
                title: '사업장 승인 정책',
                subtitle: '자동 승인 또는 슈퍼관리자 수동 승인 전환',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BusinessApprovalSettingsScreen(),
                  ),
                ),
              ),
              _SettingItem(
                icon: Icons.notifications_outlined,
                title: '알림 설정',
                subtitle: '푸시 알림 규칙',
                onTap: () => _showComingSoon(context),
                isDisabled: true,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingSection(
    BuildContext context, {
    required String title,
    required List<_SettingItem> items,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: ResponsiveHelper.subtitleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            children: items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              final isLast = index == items.length - 1;
              
              return Column(
                children: [
                  _buildSettingTile(context, item),
                  if (!isLast)
                    Divider(
                      height: 1,
                      indent: ResponsiveHelper.spacing(context, 56),
                    ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSettingTile(BuildContext context, _SettingItem item) {
    final theme = Theme.of(context);
    
    return ListTile(
      contentPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      leading: Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
        decoration: BoxDecoration(
          color: item.isDisabled 
              ? AppColors.grey200 
              : theme.primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(
          item.icon,
          size: ResponsiveHelper.iconSize(context, 24),
          color: item.isDisabled 
              ? AppColors.grey400 
              : theme.primaryColor,
        ),
      ),
      title: Text(
        item.title,
        style: ResponsiveHelper.bodyStyle(context).copyWith(
          fontWeight: FontWeight.w600,
          color: item.isDisabled ? AppColors.grey400 : null,
        ),
      ),
      subtitle: Text(
        item.subtitle,
        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: item.isDisabled ? AppColors.grey300 : AppColors.grey400,
      ),
      onTap: item.isDisabled ? null : item.onTap,
    );
  }

  void _showComingSoon(BuildContext context) {
    ToastHelper.showInfo('준비 중인 기능입니다');
  }
}

class _SettingItem {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDisabled;

  const _SettingItem({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDisabled = false,
  });
}