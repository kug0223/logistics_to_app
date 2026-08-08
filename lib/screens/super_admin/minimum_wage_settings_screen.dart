import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../utils/responsive_helper.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/wage_calculator.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/dialogs/styled_dialog.dart';

class MinimumWageSettingsScreen extends StatefulWidget {
  const MinimumWageSettingsScreen({super.key});

  @override
  State<MinimumWageSettingsScreen> createState() => _MinimumWageSettingsScreenState();
}

class _MinimumWageSettingsScreenState extends State<MinimumWageSettingsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final int _currentYear = DateTime.now().year;

  bool _isLoading = true;
  bool _isSaving = false;
  Map<int, int> _wages = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<UserProvider>().isSuperAdmin) {
        Navigator.pop(context);
        return;
      }
      _load();
    });
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
      if (_wages.isEmpty) {
        _wages = {
          2020: 8590, 2021: 8720, 2022: 9160, 2023: 9620,
          2024: 9860, 2025: 10030, 2026: 10320,
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
      final data = {for (final e in _wages.entries) e.key.toString(): e.value};
      await _firestore.collection('settings').doc('wage_config').set(
        {'minimumWages': data},
        SetOptions(merge: true),
      );
      await WageCalculator.loadMinimumWages();
      if (mounted) ToastHelper.showSuccess('저장되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('저장 실패: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _showAddOrEditDialog({int? existingYear, int? existingWage}) async {
    // _WageEditDialog StatefulWidget이 컨트롤러 생명주기를 직접 관리
    // → showDialog Future 완료 시점(애니메이션 시작 전)에 dispose되는 문제 방지
    final result = await showDialog<({int year, int wage})?>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _WageEditDialog(
        isEdit: existingYear != null,
        existingYear: existingYear,
        existingWage: existingWage,
        existingWages: _wages,
      ),
    );
    if (result != null && mounted) {
      setState(() => _wages[result.year] = result.wage);
    }
  }

  Future<void> _confirmDelete(int year) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StyledDialog(
        title: '삭제 확인',
        subtitle: '$year년 최저시급',
        icon: Icons.delete_outline,
        headerColor: AppColors.error,
        content: Text(
          '$year년 최저시급을 삭제하시겠습니까?\n삭제하면 해당 연도는 직전 연도 값이 적용됩니다.',
          style: ResponsiveHelper.bodyStyle(ctx).copyWith(color: AppColors.grey700),
        ),
        actions: [
          StyledDialogButton.cancel(onPressed: () => Navigator.pop(ctx, false)),
          StyledDialogButton.danger(
            text: '삭제',
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    if (ok == true && mounted) setState(() => _wages.remove(year));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentYear = _currentYear;
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
                    padding: ResponsiveHelper.listPadding(context),
                    itemCount: sortedYears.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final year = sortedYears[i];
                      final wage = _wages[year]!;
                      final isCurrentYear = year == currentYear;
                      final isNextYear = year == currentYear + 1;

                      return Container(
                        decoration: BoxDecoration(
                          color: AppColors.surface,
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
                            style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
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

/// 수정/추가 다이얼로그 — StatefulWidget으로 컨트롤러 수명 직접 관리
///
/// showDialog의 Future는 exit 애니메이션이 끝나기 전에 완료되므로,
/// StatelessWidget 방식으로 컨트롤러를 외부에서 dispose하면
/// 아직 렌더링 중인 TextField가 disposed 컨트롤러를 참조해
/// `_dependents.isEmpty: is not true` assertion이 발생한다.
/// StatefulWidget.dispose()에서 처리하면 Flutter가 위젯 트리 해제 후 호출을 보장한다.
class _WageEditDialog extends StatefulWidget {
  final bool isEdit;
  final int? existingYear;
  final int? existingWage;
  final Map<int, int> existingWages;

  const _WageEditDialog({
    required this.isEdit,
    this.existingYear,
    this.existingWage,
    required this.existingWages,
  });

  @override
  State<_WageEditDialog> createState() => _WageEditDialogState();
}

class _WageEditDialogState extends State<_WageEditDialog> {
  late final TextEditingController _yearController;
  late final TextEditingController _wageController;

  @override
  void initState() {
    super.initState();
    _yearController = TextEditingController(
      text: widget.isEdit ? widget.existingYear.toString() : '',
    );
    _wageController = TextEditingController(
      text: widget.isEdit && widget.existingWage != null
          ? FormatHelper.formatNumber(widget.existingWage!)
          : '',
    );
  }

  @override
  void dispose() {
    _yearController.dispose();
    _wageController.dispose();
    super.dispose();
  }

  void _submit() {
    final year = widget.isEdit
        ? widget.existingYear!
        : int.tryParse(_yearController.text);
    final wage = int.tryParse(_wageController.text.replaceAll(',', ''));

    if (year == null || year < 2000 || year > 2100) {
      ToastHelper.showError('유효한 연도를 입력하세요');
      return;
    }
    if (wage == null || wage <= 0) {
      ToastHelper.showError('유효한 금액을 입력하세요');
      return;
    }
    if (!widget.isEdit && widget.existingWages.containsKey(year)) {
      ToastHelper.showError('이미 등록된 연도입니다');
      return;
    }

    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, (year: year, wage: wage));
  }

  @override
  Widget build(BuildContext context) {
    return StyledDialog(
      title: widget.isEdit ? '${widget.existingYear}년 수정' : '연도 추가',
      subtitle: widget.isEdit ? '최저시급을 수정합니다' : '새 연도 최저시급을 입력합니다',
      icon: Icons.payments_outlined,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.isEdit) ...[
            StyledDialogTextField(
              controller: _yearController,
              labelText: '연도',
              hintText: '예) 2027',
              prefixIcon: Icons.calendar_today_outlined,
              suffixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Text(
                  '년',
                  style: TextStyle(color: AppColors.grey600, fontWeight: FontWeight.w500),
                ),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ],
          StyledDialogTextField(
            controller: _wageController,
            labelText: '최저시급',
            hintText: '예) 10,320',
            prefixIcon: Icons.attach_money_outlined,
            suffixIcon: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                '원',
                style: TextStyle(color: AppColors.grey600, fontWeight: FontWeight.w500),
              ),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [NumberInputFormatter()],
            autofocus: true,
            onFieldSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        StyledDialogButton.cancel(onPressed: () {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.pop(context);
        }),
        StyledDialogButton.primary(
          text: widget.isEdit ? '수정' : '추가',
          onPressed: _submit,
        ),
      ],
    );
  }
}
