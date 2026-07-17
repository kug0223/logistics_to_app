// lib/screens/super_admin/business_approval_settings_screen.dart

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../utils/loading_state_mixin.dart';
import 'package:provider/provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../providers/user_provider.dart';

/// 사업장 승인 정책 설정 화면 (슈퍼관리자 전용)
///
/// settings/system.businessAutoApprove 값을 ON/OFF로 전환.
/// ON(기본): 사업장 등록 즉시 CF가 자동 승인 → 관리자가 바로 공고 등록 가능.
/// OFF: 슈퍼관리자가 직접 사업장 목록에서 승인해야 활성화됨.
class BusinessApprovalSettingsScreen extends StatefulWidget {
  const BusinessApprovalSettingsScreen({super.key});

  @override
  State<BusinessApprovalSettingsScreen> createState() =>
      _BusinessApprovalSettingsScreenState();
}

class _BusinessApprovalSettingsScreenState
    extends State<BusinessApprovalSettingsScreen> with LoadingStateMixin {
  final _firestore = FirebaseFirestore.instance;

  bool _autoApprove = true;
  bool _isSaving = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<UserProvider>().isSuperAdmin) {
        Navigator.pop(context);
        return;
      }
      _loadSettings();
    });
  }

  Future<void> _loadSettings() async {
    setLoading(true);
    try {
      final doc = await _firestore.collection('settings').doc('system').get();
      if (doc.exists) {
        final data = doc.data()!;
        if (mounted) setState(() => _autoApprove = (data['businessAutoApprove'] as bool?) ?? true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadFailed = true);
        ToastHelper.showError('설정을 불러오는데 실패했습니다: $e');
      }
    } finally {
      if (mounted) setLoading(false);
    }
  }

  Future<void> _saveSettings() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await _firestore.collection('settings').doc('system').set(
        {'businessAutoApprove': _autoApprove},
        SetOptions(merge: true),
      );
      if (!mounted) return;
      ToastHelper.showSuccess(_autoApprove ? '자동 승인으로 변경되었습니다' : '수동 승인으로 변경되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '사업장 승인 정책',
      body: isLoading
          ? const LoadingWidget(message: '설정을 불러오는 중...')
          : ListView(
              padding: ResponsiveHelper.cardPadding(context),
              children: [
                _buildInfoCard(),
                SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                _buildToggleCard(),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                _buildModeDescription(),
                SizedBox(height: ResponsiveHelper.spacing(context, 32)),
                _buildSaveButton(),
              ],
            ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.domain_verification_outlined,
            size: ResponsiveHelper.iconSize(context, 32),
            color: AppColors.infoDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Text(
              '관리자가 사업장을 등록할 때\n자동으로 승인할지 여부를 설정합니다.',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: AppColors.infoDark,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleCard() {
    return Container(
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
      child: SwitchListTile(
        contentPadding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 20),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        title: Text(
          '자동 승인',
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          _autoApprove ? '등록 즉시 자동 승인됨' : '슈퍼관리자 수동 승인 필요',
          style: ResponsiveHelper.smallStyle(
            context,
            color: _autoApprove ? AppColors.success : AppColors.warning,
          ),
        ),
        value: _autoApprove,
        activeThumbColor: AppColors.success,
        activeTrackColor: AppColors.success.withValues(alpha: 0.4),
        onChanged: (value) => setState(() => _autoApprove = value),
      ),
    );
  }

  Widget _buildModeDescription() {
    final isAuto = _autoApprove;
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: isAuto
            ? AppColors.success.withValues(alpha: 0.08)
            : AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isAuto
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.warning.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isAuto ? Icons.check_circle_outline : Icons.pending_outlined,
                size: ResponsiveHelper.iconSize(context, 20),
                color: isAuto ? AppColors.success : AppColors.warning,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                isAuto ? '자동 승인 모드' : '수동 승인 모드',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: isAuto ? AppColors.success : AppColors.warning,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Text(
            isAuto
                ? '• 사업장 등록 즉시 Cloud Functions가 자동으로 승인합니다.\n'
                  '• 관리자가 등록 후 바로 공고를 올릴 수 있습니다.\n'
                  '• 소규모·신뢰 환경에서 운영 효율이 높습니다.'
                : '• 사업장 등록 후 "승인대기" 상태로 유지됩니다.\n'
                  '• 슈퍼관리자가 전체 사업장 목록에서 직접 승인해야\n'
                  '  공고 등록이 가능합니다.\n'
                  '• 불법·사기 사업장 사전 차단이 필요한 경우 사용합니다.',
            style: ResponsiveHelper.smallStyle(context).copyWith(height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildSaveButton() {
    return SafeArea(
      top: false,
      child: SizedBox(
        width: double.infinity,
        height: 52,
        child: ElevatedButton(
          // [approval-settings-01] 로드 실패 시 저장 차단 — 기본값(자동승인)으로 잘못 저장 방지
          onPressed: (_isSaving || _loadFailed) ? null : _saveSettings,
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: _isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(
                  '저장',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    );
  }
}
