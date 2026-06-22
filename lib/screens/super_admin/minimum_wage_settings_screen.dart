import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/wage_calculator.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';

/// 연도별 최저시급 관리 화면
///
/// Firestore settings/wage_config.minimumWages 맵에 연도별 누적 저장
/// WageCalculator는 근무일의 연도를 기준으로 해당 값을 적용
class MinimumWageSettingsScreen extends StatefulWidget {
  const MinimumWageSettingsScreen({super.key});

  @override
  State<MinimumWageSettingsScreen> createState() => _MinimumWageSettingsScreenState();
}

class _MinimumWageSettingsScreenState extends State<MinimumWageSettingsScreen> {
  final _firestore = FirebaseFirestore.instance;

  bool _isLoading = true;
  bool _isSaving = false;

  // 연도 → 최저시급 (화면 편집용)
  Map<int, int> _wages = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final doc = await _firestore.collection('settings').doc('wage_config').get();
      final raw = doc.data()?['minimumWages'];
      if (raw is Map) {
        _wages = {
          for (final e in raw.entries)
            int.tryParse(e.key.toString()) ?? 0: (e.value as num?)?.toInt() ?? 0
        };
        _wages.remove(0);
      }
      // Firestore에 아무것도 없으면 코드 백업값으로 초기화
      if (_wages.isEmpty) {
        _wages = {
          2020: 8590, 2021: 8720, 2022: 9160, 2023: 9620,
          2024: 9860, 2025: 10030, 2026: 10360,
        };
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('데이터 로드 실패: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final data = {
        for (final e in _wages.entries) e.key.toString(): e.value,
      };
      await _firestore.collection('settings').doc('wage_config').set(
        {'minimumWages': data},
        SetOptions(merge: true),
      );
      // 앱 내 캐시도 즉시 갱신
      await WageCalculator.loadMinimumWages();
      if (mounted) ToastHelper.showSuccess('저장되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showAddOrEditDialog({int? existingYear, int? existingWage}) {
    final isEdit = existingYear != null;
    final yearController = TextEditingController(
      text: isEdit ? existingYear.toString() : '',
    );
    final wageController = TextEditingController(
      text: isEdit ? FormatHelper.formatNumber(existingWage!) : '',
    );

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: Text(isEdit ? '$existingYear년 수정' : '연도 추가'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isEdit) ...[
                TextField(
                  controller: yearController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: const InputDecoration(
                    labelText: '연도',
                    hintText: '예) 2027',
                    suffixText: '년',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              TextField(
                controller: wageController,
                keyboardType: TextInputType.number,
                inputFormatters: [NumberInputFormatter()],
                decoration: const InputDecoration(
                  labelText: '최저시급',
                  hintText: '예) 10,030',
                  suffixText: '원',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () {
              final year = isEdit
                  ? existingYear
                  : int.tryParse(yearController.text);
              final wage = int.tryParse(wageController.text.replaceAll(',', ''));

              if (year == null || year < 2000 || year > 2100) {
                ToastHelper.showError('유효한 연도를 입력하세요');
                return;
              }
              if (wage == null || wage <= 0) {
                ToastHelper.showError('유효한 금액을 입력하세요');
                return;
              }
              if (!isEdit && _wages.containsKey(year)) {
                ToastHelper.showError('이미 등록된 연도입니다');
                return;
              }

              Navigator.pop(ctx);
              setState(() => _wages[year] = wage);
            },
            child: Text(isEdit ? '수정' : '추가'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(int year) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        title: const Text('삭제 확인'),
        content: SingleChildScrollView(
          child: Text('$year년 최저시급을 삭제하시겠습니까?\n삭제하면 해당 연도는 직전 연도 값이 적용됩니다.'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.error),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _wages.remove(year));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentYear = DateTime.now().year;
    final sortedYears = _wages.keys.toList()..sort((a, b) => b.compareTo(a));

    return GradientScaffold(
      title: '최저시급 관리',
      actions: [
        if (!_isLoading)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save, size: 18),
              label: const Text('저장'),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: theme.primaryColor,
              ),
            ),
          ),
      ],
      body: _isLoading
          ? const LoadingWidget()
          : Column(
              children: [
                // 안내 배너
                Container(
                  width: double.infinity,
                  padding: ResponsiveHelper.cardPadding(context),
                  color: AppColors.infoBg,
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: AppColors.infoDark, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '연도별로 누적 저장됩니다. 내년 시급을 미리 등록해두면 해당 연도 근무일에 자동 적용됩니다.\n수정 후 반드시 [저장]을 눌러주세요.',
                          style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDeep),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: ListView.separated(
                    padding: ResponsiveHelper.cardPadding(context),
                    itemCount: sortedYears.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final year = sortedYears[i];
                      final wage = _wages[year]!;
                      final isCurrentYear = year == currentYear;
                      final isNextYear = year == currentYear + 1;

                      return Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: isCurrentYear
                              ? Border.all(color: theme.primaryColor, width: 2)
                              : isNextYear
                                  ? Border.all(color: AppColors.success, width: 1.5)
                                  : null,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.04),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ListTile(
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 16),
                            vertical: ResponsiveHelper.spacing(context, 4),
                          ),
                          leading: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: isCurrentYear
                                  ? theme.primaryColor.withValues(alpha: 0.12)
                                  : isNextYear
                                      ? AppColors.success.withValues(alpha: 0.1)
                                      : AppColors.grey100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Center(
                              child: Text(
                                '$year',
                                style: ResponsiveHelper.smallStyle(
                                  context,
                                  color: isCurrentYear
                                      ? theme.primaryColor
                                      : isNextYear
                                          ? AppColors.successDark
                                          : AppColors.grey600,
                                ).copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          title: Text(
                            '${FormatHelper.formatNumber(wage)}원',
                            style: ResponsiveHelper.subtitleStyle(context).copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: isCurrentYear
                              ? Text('현재 적용 중', style: ResponsiveHelper.smallStyle(context, color: theme.primaryColor).copyWith(fontWeight: FontWeight.w600))
                              : isNextYear
                                  ? Text('내년 적용 예정', style: ResponsiveHelper.smallStyle(context, color: AppColors.successDark).copyWith(fontWeight: FontWeight.w600))
                                  : null,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.edit_outlined, color: theme.primaryColor, size: 20),
                                onPressed: () => _showAddOrEditDialog(existingYear: year, existingWage: wage),
                                tooltip: '수정',
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline, color: AppColors.error, size: 20),
                                onPressed: () => _confirmDelete(year),
                                tooltip: '삭제',
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: _isLoading
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _showAddOrEditDialog(),
              icon: const Icon(Icons.add),
              label: const Text('연도 추가'),
              backgroundColor: theme.primaryColor,
              foregroundColor: Colors.white,
            ),
    );
  }
}
