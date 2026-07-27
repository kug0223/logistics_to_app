import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/core/insurance_rate_model.dart';
import '../../providers/user_provider.dart';
import '../../services/insurance_rate_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/dialogs/styled_dialog.dart';

/// 연도별 4대보험·소득세 요율 관리 화면 (슈퍼관리자)
///
/// Firestore settings/wage_config.insuranceRates 에 저장
class InsuranceRateSettingsScreen extends StatefulWidget {
  const InsuranceRateSettingsScreen({super.key});

  @override
  State<InsuranceRateSettingsScreen> createState() =>
      _InsuranceRateSettingsScreenState();
}

class _InsuranceRateSettingsScreenState
    extends State<InsuranceRateSettingsScreen> {
  bool _isLoading = true;
  bool _isSaving = false;

  /// 연도별 데이터 (화면 편집용)
  Map<int, InsuranceRateModel> _rates = {};
  int _selectedYear = DateTime.now().year;

  // 현재 선택 연도 편집 컨트롤러
  late _RateControllers _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = _RateControllers();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<UserProvider>().isSuperAdmin) {
        Navigator.pop(context);
        return;
      }
      _load();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      _rates = await InsuranceRateService.fetchAll();
      if (!mounted) return;
      // 현재 연도가 없으면 기본값 추가
      _rates.putIfAbsent(_selectedYear, InsuranceRateModel.defaults2026);
      _updateControllers();
    } catch (e) {
      if (mounted) ToastHelper.showError('데이터 로드 실패: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _selectYear(int year) {
    setState(() {
      _selectedYear = year;
      _updateControllers();
    });
  }

  void _updateControllers() {
    final r = _rates[_selectedYear];
    if (r == null) return;
    _ctrl.update(r);
  }

  Future<void> _save() async {
    final parsed = _ctrl.parse(_selectedYear);
    if (parsed == null) {
      ToastHelper.showWarning('요율 값을 확인해주세요\n(0% 이상 100% 미만의 숫자만 입력 가능)');
      return;
    }
    setState(() => _isSaving = true);
    try {
      await InsuranceRateService.saveRates(parsed);
      if (!mounted) return; // [BUG-수정] async gap 후 mounted 체크
      _rates[_selectedYear] = parsed;
      ToastHelper.showSuccess('$_selectedYear년 보험료율 저장 완료');
    } catch (e) {
      if (mounted) ToastHelper.showError('저장 실패: $e'); // [BUG-수정] catch Toast mounted 가드
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _addYear() async {
    final newYear = await _showYearPickerDialog();
    if (newYear == null) return;
    if (!mounted) return;
    if (_rates.containsKey(newYear)) {
      _selectYear(newYear);
      return;
    }
    // 가장 최근 연도 데이터 복사해서 새 연도로 추가
    if (_rates.isEmpty) return;
    final latestYear = _rates.keys.reduce((a, b) => a > b ? a : b);
    final latestRate = _rates[latestYear];
    if (latestRate == null) return; // 이론적으로 발생 불가하나 방어 처리
    setState(() {
      _rates[newYear] = latestRate.copyWith(year: newYear);
      _selectedYear = newYear;
      _updateControllers();
    });
  }

  Future<int?> _showYearPickerDialog() {
    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _YearPickerDialog(
        initialYear: DateTime.now().year + 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientScaffold(
      title: '보험료율 관리',
      actions: [
        IconButton(
          icon: const Icon(Icons.add, color: Colors.white),
          tooltip: '연도 추가',
          onPressed: _addYear,
        ),
      ],
      body: _isLoading
          ? const LoadingWidget()
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 연도 목록
                _buildYearList(theme),
                const VerticalDivider(width: 1),
                // 요율 편집
                Expanded(child: _buildEditor(theme)),
              ],
            ),
    );
  }

  Widget _buildYearList(ThemeData theme) {
    final years = _rates.keys.toList()..sort((a, b) => b.compareTo(a));
    return SizedBox(
      width: 90,
      child: ListView.builder(
        itemCount: years.length,
        itemBuilder: (_, i) {
          final y = years[i];
          final selected = y == _selectedYear;
          return ListTile(
            dense: true,
            selected: selected,
            selectedTileColor: theme.primaryColor.withValues(alpha: 0.1),
            title: Text(
              '$y년',
              style: ResponsiveHelper.bodyStyle(
                context,
                color: selected ? theme.primaryColor : null,
              ).copyWith(
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            onTap: () => _selectYear(y),
          );
        },
      ),
    );
  }

  Widget _buildEditor(ThemeData theme) {
    return SingleChildScrollView(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$_selectedYear년 보험료율',
            style: ResponsiveHelper.subtitleStyle(context)
                .copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            '근로자 부담분 기준. 사업주 부담분은 별도.',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
          _buildSection('4대보험 요율 (%) — 2026년 기준', [
            _field('국민연금', _ctrl.pension, '4.75'),   // 2026: 9.5% × 1/2
            _field('건강보험', _ctrl.health, '3.595'),   // 2026: 7.19% × 1/2
            _field('장기요양 (건보료 대비 %)', _ctrl.ltc, '13.14'), // 2026: 0.9448/7.19×100
            _field('고용보험', _ctrl.employment, '0.9'),
          ], theme),
          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
          _buildSection('소득세', [
            _fieldInt('일용직 비과세 한도 (원)', _ctrl.exemption, '150000'),
            _field('일용직 소득세율 (%)', _ctrl.dailyTax, '2.7'),
            _field('지방소득세 (소득세 대비 %)', _ctrl.localTax, '10.0'),
            _field('사업소득 원천징수 (%)', _ctrl.bizIncome, '3.0'),
            _field('사업소득 지방세 (%)', _ctrl.bizLocal, '0.3'),
          ], theme),
          SizedBox(height: ResponsiveHelper.spacing(context, 28)),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isSaving ? null : _save,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? '저장 중...' : '$_selectedYear년 저장'),
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                    vertical: ResponsiveHelper.spacing(context, 14)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(String title, List<Widget> fields, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            color: theme.primaryColor,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        ...fields,
      ],
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      child: TextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixText: '%',
        ),
      ),
    );
  }

  Widget _fieldInt(String label, TextEditingController ctrl, String hint) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixText: '원',
        ),
      ),
    );
  }
}

/// 편집용 컨트롤러 묶음
class _RateControllers {
  final pension    = TextEditingController();
  final health     = TextEditingController();
  final ltc        = TextEditingController();
  final employment = TextEditingController();
  final exemption  = TextEditingController();
  final dailyTax   = TextEditingController();
  final localTax   = TextEditingController();
  final bizIncome  = TextEditingController();
  final bizLocal   = TextEditingController();

  void update(InsuranceRateModel r) {
    pension.text    = r.nationalPensionRate.toString();
    health.text     = r.healthInsuranceRate.toString();
    ltc.text        = r.ltcInsuranceRate.toString();
    employment.text = r.employmentInsuranceRate.toString();
    exemption.text  = r.dailyWageExemption.toString();
    dailyTax.text   = r.dailyWorkerTaxRate.toString();
    localTax.text   = r.localIncomeTaxRate.toString();
    bizIncome.text  = r.businessIncomeRate.toString();
    bizLocal.text   = r.businessIncomeLocalRate.toString();
  }

  InsuranceRateModel? parse(int year) {
    final p   = double.tryParse(pension.text);
    final h   = double.tryParse(health.text);
    final l   = double.tryParse(ltc.text);
    final e   = double.tryParse(employment.text);
    final ex  = int.tryParse(exemption.text);
    final dt  = double.tryParse(dailyTax.text);
    final lt  = double.tryParse(localTax.text);
    final bi  = double.tryParse(bizIncome.text);
    final bl  = double.tryParse(bizLocal.text);
    if (p == null || h == null || l == null || e == null ||
        ex == null || dt == null || lt == null || bi == null || bl == null) {
      return null;
    }
    // 범위 검증: 요율은 0% 이상 100% 미만, 면제금액은 0 이상
    if ([p, h, l, e, dt, lt, bi, bl].any((v) => v < 0 || v >= 100)) return null;
    if (ex < 0) return null;
    return InsuranceRateModel(
      year: year,
      nationalPensionRate: p,
      healthInsuranceRate: h,
      ltcInsuranceRate: l,
      employmentInsuranceRate: e,
      dailyWageExemption: ex,
      dailyWorkerTaxRate: dt,
      localIncomeTaxRate: lt,
      businessIncomeRate: bi,
      businessIncomeLocalRate: bl,
    );
  }

  void dispose() {
    pension.dispose();
    health.dispose();
    ltc.dispose();
    employment.dispose();
    exemption.dispose();
    dailyTax.dispose();
    localTax.dispose();
    bizIncome.dispose();
    bizLocal.dispose();
  }
}

// ── 연도 추가 다이얼로그 ──────────────────────────────────────────────
class _YearPickerDialog extends StatefulWidget {
  final int initialYear;

  const _YearPickerDialog({required this.initialYear});

  @override
  State<_YearPickerDialog> createState() => _YearPickerDialogState();
}

class _YearPickerDialogState extends State<_YearPickerDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialYear.toString());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final v = int.tryParse(_controller.text);
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, v);
  }

  @override
  Widget build(BuildContext context) {
    return StyledDialog(
      title: '연도 추가',
      subtitle: '보험료율을 새 연도로 추가합니다',
      icon: Icons.calendar_month_outlined,
      content: StyledDialogTextField(
        controller: _controller,
        labelText: '연도',
        hintText: '예: 2027',
        prefixIcon: Icons.calendar_today_outlined,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        autofocus: true,
        onFieldSubmitted: (_) => _submit(),
      ),
      actions: [
        StyledDialogButton.cancel(onPressed: () {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.pop(context);
        }),
        StyledDialogButton.primary(text: '추가', onPressed: _submit),
      ],
    );
  }
}
