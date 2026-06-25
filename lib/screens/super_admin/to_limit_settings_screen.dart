import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/responsive_helper.dart';
import '../../theme/app_colors.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/gradient_scaffold.dart';

/// 슈퍼관리자 — 사업장 공고 등록 개수 제한 설정
/// Firestore: settings/app_config.maxActiveTOPerBusiness
class TOLimitSettingsScreen extends StatefulWidget {
  const TOLimitSettingsScreen({super.key});

  @override
  State<TOLimitSettingsScreen> createState() => _TOLimitSettingsScreenState();
}

class _TOLimitSettingsScreenState extends State<TOLimitSettingsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _controller = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;
  int _currentLimit = 4;

  @override
  void initState() {
    super.initState();
    _loadLimit();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadLimit() async {
    try {
      final doc = await _firestore.collection('settings').doc('app_config').get();
      final v = (doc.data()?['maxActiveTOPerBusiness'] as num?)?.toInt() ?? 4;
      if (mounted) {
        setState(() {
          _currentLimit = v;
          _controller.text = v.toString();
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _controller.text = '4';
          _isLoading = false;
        });
        ToastHelper.showError('설정을 불러오는데 실패했습니다');
      }
    }
  }

  Future<void> _save() async {
    final value = int.tryParse(_controller.text.trim());
    if (value == null || value < 1 || value > 50) {
      ToastHelper.showError('1~50 사이의 숫자를 입력해주세요');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await _firestore.collection('settings').doc('app_config').set(
        {'maxActiveTOPerBusiness': value},
        SetOptions(merge: true),
      );
      if (mounted) {
        setState(() => _currentLimit = value);
        ToastHelper.showSuccess('공고 등록 개수 제한이 $value개로 설정되었습니다');
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('저장에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '공고 등록 개수 제한',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: ResponsiveHelper.cardPadding(context),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: ResponsiveHelper.cardPadding(context),
                    decoration: BoxDecoration(
                      color: AppColors.infoBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: ResponsiveHelper.iconSize(context, 24),
                            color: AppColors.infoDark),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                        Expanded(
                          child: Text(
                            '사업장 당 동시에 진행할 수 있는 공고(active) 최대 개수입니다.\n기존 공고를 초과하더라도 draft 상태로는 제한 없이 저장 가능합니다.',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.infoDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                  Text(
                    '현재 제한: $_currentLimit개',
                    style: ResponsiveHelper.subtitleStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  TextField(
                    controller: _controller,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: '새 제한 값',
                      hintText: '1 ~ 50',
                      suffixText: '개',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 16),
                        vertical: ResponsiveHelper.spacing(context, 14),
                      ),
                    ),
                    style: ResponsiveHelper.bodyStyle(context),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(context, 14)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white),
                            )
                          : Text(
                              '저장',
                              style: ResponsiveHelper.bodyStyle(context,
                                  color: Colors.white),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
