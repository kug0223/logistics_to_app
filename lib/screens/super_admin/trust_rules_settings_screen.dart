// lib/screens/super_admin/trust_rules_settings_screen.dart

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../theme/app_colors.dart';
import '../../models/settings/trust_settings_model.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';

/// 신뢰도 규칙 설정 화면
class TrustRulesSettingsScreen extends StatefulWidget {
  const TrustRulesSettingsScreen({super.key});

  @override
  State<TrustRulesSettingsScreen> createState() => _TrustRulesSettingsScreenState();
}

class _TrustRulesSettingsScreenState extends State<TrustRulesSettingsScreen> {
  final _firestore = FirebaseFirestore.instance;
  
  bool _isLoading = true;
  bool _isSaving = false;
  TrustSettingsModel? _settings;
  
  // 편집 컨트롤러들
  final _startScoreController = TextEditingController();
  final _maxScoreController = TextEditingController();
  
  // 재시작 프로그램
  final _restartScoreController = TextEditingController();
  final _cooldownDaysController = TextEditingController();
  final _noshowReductionController = TextEditingController();
  final _lateReductionController = TextEditingController();
  
  // 규칙별 컨트롤러 (동적)
  final Map<String, TextEditingController> _ruleControllers = {};

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

  @override
  void dispose() {
    _startScoreController.dispose();
    _maxScoreController.dispose();
    _restartScoreController.dispose();
    _cooldownDaysController.dispose();
    _noshowReductionController.dispose();
    _lateReductionController.dispose();
    for (final controller in _ruleControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await _firestore.collection('settings').doc('trust_rules').get();
      
      if (doc.exists) {
        _settings = TrustSettingsModel.fromFirestore(doc);
      } else {
        _settings = TrustSettingsModel.defaults();
        await _firestore.collection('settings').doc('trust_rules').set(_settings!.toMap());
      }
      
      _populateControllers();
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 설정 로드 실패: $e');
      if (mounted) ToastHelper.showError('설정을 불러오는데 실패했습니다'); // [BUG-수정] catch Toast mounted 가드
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _populateControllers() {
    if (_settings == null) return;
    
    _startScoreController.text = _settings!.startScore.toString();
    _maxScoreController.text = _settings!.maxScore.toString();
    
    // 재시작 프로그램
    _restartScoreController.text = _settings!.restartProgram.resetScore.toString();
    _cooldownDaysController.text = _settings!.restartProgram.cooldownDays.toString();
    _noshowReductionController.text = _settings!.restartProgram.noshowReduction.toString();
    _lateReductionController.text = _settings!.restartProgram.lateReduction.toString();
    
    // 증가 규칙 컨트롤러
    for (final rule in _settings!.increaseRules) {
      _ruleControllers[rule.type] = TextEditingController(text: rule.points.toString());
    }
    
    // 감소 규칙 컨트롤러
    for (final rule in _settings!.decreaseRules) {
      _ruleControllers[rule.type] = TextEditingController(text: rule.points.abs().toString());
    }
  }

  Future<void> _saveSettings() async {
    if (!_validateInputs()) return;
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '설정 저장',
      message: '신뢰도 규칙을 저장하시겠습니까?\n변경사항은 즉시 적용됩니다.',
      confirmText: '저장',
    );
    if (!confirmed || !mounted) return;
    if (_settings == null) return;
      // 증가 규칙 업데이트
      final updatedIncreaseRules = _settings!.increaseRules.map((rule) {
        final controller = _ruleControllers[rule.type];
        final newPoints = int.tryParse(controller?.text ?? '') ?? rule.points;
        return TrustRule(
          type: rule.type,
          points: newPoints,
          description: rule.description,
          condition: rule.condition,
        );
      }).toList();
      
      // 감소 규칙 업데이트 (음수로 저장 — .abs()로 음수 입력 방어)
      final updatedDecreaseRules = _settings!.decreaseRules.map((rule) {
        final controller = _ruleControllers[rule.type];
        final newPoints = (int.tryParse(controller?.text ?? '') ?? rule.points.abs()).abs();
        return TrustRule(
          type: rule.type,
          points: -newPoints, // 음수로 저장
          description: rule.description,
          condition: rule.condition,
        );
      }).toList();
      
      final updatedSettings = TrustSettingsModel(
        startScore: int.parse(_startScoreController.text),
        maxScore: int.parse(_maxScoreController.text),
        increaseRules: updatedIncreaseRules,
        decreaseRules: updatedDecreaseRules,
        restartProgram: RestartProgramSettings(
          resetScore: int.parse(_restartScoreController.text),
          cooldownDays: int.parse(_cooldownDaysController.text),
          noshowReduction: int.parse(_noshowReductionController.text),
          lateReduction: int.parse(_lateReductionController.text),
        ),
      );
      
      await _firestore.collection('settings').doc('trust_rules').set(updatedSettings.toMap());

      _settings = updatedSettings;
      if (mounted) ToastHelper.showSuccess('설정이 저장되었습니다');
    } catch (e) {
      if (kDebugMode) debugPrint('❌ 설정 저장 실패: $e');
      if (mounted) ToastHelper.showError('설정 저장에 실패했습니다');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  bool _validateInputs() {
    try {
      final startScore = int.parse(_startScoreController.text);
      final maxScore = int.parse(_maxScoreController.text);
      final resetScore = int.parse(_restartScoreController.text);
      final cooldownDays = int.parse(_cooldownDaysController.text);
      final noshowReduction = int.parse(_noshowReductionController.text);
      final lateReduction = int.parse(_lateReductionController.text);

      if (startScore < 0 || startScore > 100) {
        ToastHelper.showError('시작 점수는 0~100 사이여야 합니다');
        return false;
      }

      if (maxScore < startScore || maxScore > 100) {
        ToastHelper.showError('최대 점수는 시작 점수 이상 100 이하여야 합니다');
        return false;
      }

      if (resetScore < 0 || resetScore > 100) {
        ToastHelper.showError('재시작 리셋 점수는 0~100 사이여야 합니다');
        return false;
      }

      if (cooldownDays < 1) {
        ToastHelper.showError('쿨다운 기간은 1일 이상이어야 합니다');
        return false;
      }

      if (noshowReduction < 0 || lateReduction < 0) {
        ToastHelper.showError('감면 횟수는 0 이상이어야 합니다');
        return false;
      }

      return true;
    } catch (e) {
      ToastHelper.showError('숫자만 입력해주세요');
      return false;
    }
  }

  Future<void> _resetToDefaults() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '기본값 복원',
      message: '모든 설정을 기본값으로 복원하시겠습니까?',
      confirmText: '복원',
    );
    if (!confirmed || !mounted) return;
      _settings = TrustSettingsModel.defaults();
      await _firestore.collection('settings').doc('trust_rules').set(_settings!.toMap());

      // 컨트롤러 초기화 (기존 컨트롤러 먼저 dispose)
      for (final c in _ruleControllers.values) { c.dispose(); }
      _ruleControllers.clear();
      _populateControllers();

      if (mounted) ToastHelper.showSuccess('기본값으로 복원되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('복원에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return GradientScaffold(
      title: '신뢰도 규칙',
      actions: [
        TextButton(
          onPressed: _isSaving ? null : _resetToDefaults,
          child: Text(
            '초기화',
            style: ResponsiveHelper.bodyStyle(context).copyWith(color: Colors.white),
          ),
        ),
      ],
      body: _isLoading
          ? const LoadingWidget()
          : _settings == null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.error),
                      const SizedBox(height: 12),
                      Text('설정을 불러오지 못했습니다', style: ResponsiveHelper.bodyStyle(context)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          setState(() => _isLoading = true);
                          _loadSettings();
                        },
                        child: const Text('다시 시도'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
              padding: ResponsiveHelper.cardPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 기본 설정
                  _buildSection(
                    context,
                    title: '기본 설정',
                    icon: Icons.settings_outlined,
                    children: [
                      _buildNumberField(
                        context,
                        label: '시작 점수',
                        controller: _startScoreController,
                        suffix: '점',
                        helperText: '신규 가입 시 부여되는 점수',
                      ),
                      _buildNumberField(
                        context,
                        label: '최대 점수',
                        controller: _maxScoreController,
                        suffix: '점',
                        helperText: '신뢰도 상한선',
                      ),
                    ],
                  ),
                  
                  SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                  
                  // 증가 규칙
                  _buildSection(
                    context,
                    title: '점수 증가 규칙',
                    icon: Icons.arrow_upward,
                    iconColor: AppColors.success,
                    children: _settings!.increaseRules.map((rule) {
                      return _buildNumberField(
                        context,
                        label: rule.description,
                        controller: _ruleControllers[rule.type]!,
                        prefix: '+',
                        suffix: '점',
                        prefixColor: AppColors.success,
                      );
                    }).toList(),
                  ),
                  
                  SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                  
                  // 감소 규칙
                  _buildSection(
                    context,
                    title: '점수 감소 규칙',
                    icon: Icons.arrow_downward,
                    iconColor: AppColors.error,
                    children: _settings!.decreaseRules.map((rule) {
                      return _buildNumberField(
                        context,
                        label: rule.description,
                        controller: _ruleControllers[rule.type]!,
                        prefix: '-',
                        suffix: '점',
                        prefixColor: AppColors.error,
                      );
                    }).toList(),
                  ),
                  
                  SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                  
                  // 재시작 프로그램
                  _buildSection(
                    context,
                    title: '재시작 프로그램',
                    icon: Icons.refresh,
                    iconColor: AppColors.info,
                    children: [
                      _buildNumberField(
                        context,
                        label: '리셋 점수',
                        controller: _restartScoreController,
                        suffix: '점',
                        helperText: '재시작 시 부여되는 점수',
                      ),
                      _buildNumberField(
                        context,
                        label: '쿨다운 기간',
                        controller: _cooldownDaysController,
                        suffix: '일',
                        helperText: '재시작 후 다시 신청 가능한 기간',
                      ),
                      _buildNumberField(
                        context,
                        label: '노쇼 감면',
                        controller: _noshowReductionController,
                        suffix: '회',
                        helperText: '재시작 시 차감되는 노쇼 횟수',
                      ),
                      _buildNumberField(
                        context,
                        label: '지각 감면',
                        controller: _lateReductionController,
                        suffix: '회',
                        helperText: '재시작 시 차감되는 지각 횟수',
                      ),
                    ],
                  ),
                  
                  SizedBox(height: ResponsiveHelper.spacing(context, 32)),
                  
                  // 저장 버튼
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: theme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 16),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSaving
                          ? SizedBox(
                              width: ResponsiveHelper.spacing(context, 20),
                              height: ResponsiveHelper.spacing(context, 20),
                              child: const CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : Text(
                              '저장하기',
                              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                  
                  SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    Color? iconColor,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: (iconColor ?? theme.primaryColor).withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: iconColor ?? theme.primaryColor,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  title,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: iconColor ?? theme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          // 내용
          Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    String? prefix,
    String? suffix,
    Color? prefixColor,
    String? helperText,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: ResponsiveHelper.bodyStyle(context),
                ),
                if (helperText != null)
                  Text(
                    helperText,
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                  ),
              ],
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          SizedBox(
            width: ResponsiveHelper.spacing(context, 100),
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                prefixText: prefix,
                prefixStyle: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: prefixColor,
                  fontWeight: FontWeight.bold,
                ),
                suffixText: suffix,
                suffixStyle: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 10),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.grey300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: AppColors.grey300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Theme.of(context).primaryColor),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}