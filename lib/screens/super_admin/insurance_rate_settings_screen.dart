import 'package:flutter/material.dart';
// [R7-P1-6 P16-A] GradientScaffold(지원자 공통 레이아웃) → AppPageScaffold
//   (D0 관리자 표준 flat shell). 이 화면은 headerContent 를 쓰지 않고 헤더에
//   TabBar 도 없으며 가로 스크롤 표도 없다 — 그래서 위젯 이름만 바뀐다.
//   본문의 흰 카드는 flat 배경(grey100) 위에서 그대로 카드로 읽힌다.
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/core/insurance_rate_model.dart';
import '../../providers/user_provider.dart';
import '../../services/insurance_rate_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../utils/keep_content_refresh.dart';
import '../../widgets/common/keep_content_body.dart';

/// 연도별 4대보험·소득세 요율 관리 화면 (슈퍼관리자)
///
/// Firestore settings/wage_config.insuranceRates 에 저장
class InsuranceRateSettingsScreen extends StatefulWidget {
  const InsuranceRateSettingsScreen({super.key, this.loadStored, this.save});

  /// [.59] 시험용 경계 — null 이면 [InsuranceRateService.fetchStored] / [InsuranceRateService.saveRates].
  final Future<Map<int, InsuranceRateModel>> Function()? loadStored;
  final Future<void> Function(InsuranceRateModel rates, InsuranceRateModel? expected)? save;

  @override
  State<InsuranceRateSettingsScreen> createState() =>
      _InsuranceRateSettingsScreenState();
}

class _InsuranceRateSettingsScreenState
    extends State<InsuranceRateSettingsScreen> with KeepContentRefreshMixin {
  bool _isLoading = true;
  bool _isSaving = false;
  /// [.59] 저장값을 읽지 못했다 — 내장값을 현재값처럼 보이거나 저장하지 않는다.
  Object? _loadError;
  /// [.59] 서버에 저장된 연도별 값(화면을 연 시점). 저장 직전 대조 기준이다.
  Map<int, InsuranceRateModel> _stored = {};

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
    // [L48 · impl_28] 처리 뒤 다시 읽기는 목록을 유지한다(잠금 + 얇은 진행 표시 · KeepContentRefreshMixin) — 첫 읽기·실패 화면만 전체 로딩 · 늦은 옛 응답 착지 0.
    //   값 미리 표시 0: 유지하는 동안 입력칸은 **마지막으로 읽은 값**(_rates)으로 되돌린다 — 서버가 받지 않은 입력값을
    //   다시 읽는 동안 그대로 보이지 않게(저장 충돌·결과 불명 뒤 다시 읽기).
    final t = beginContentLoad(canKeep: _loadError == null);
    if (t.keep) {
      setState(_updateControllers);
    } else {
      setState(() { _isLoading = true; _loadError = null; });
    }
    var shown = false;
    try {
      final stored = await (widget.loadStored ?? InsuranceRateService.fetchStored)();
      if (!isCurrentContentLoad(t.gen)) return;
      _stored = Map.of(stored);
      _rates = {...InsuranceRateService.builtinDefaults, ...stored};
      // 현재 연도가 없으면 기본값 추가(저장값 없음 안내와 함께 보인다)
      _rates.putIfAbsent(_selectedYear, InsuranceRateModel.defaults2026);
      _updateControllers();
      shown = true;
    } catch (e) {
      if (isCurrentContentLoad(t.gen)) setState(() => _loadError = e);
    } finally {
      if (isCurrentContentLoad(t.gen)) {
        setState(() => _isLoading = false);
        finishContentLoad(t.gen, shown: shown);
      }
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
    if (_loadError != null) return;
    final parsed = _ctrl.parse(_selectedYear);
    if (parsed == null) {
      // [.59] 범위는 앱 계산(InsuranceRateModel.fromMap)이 실제로 쓰는 상한과 같다 — 넘는 값은 앱이 잘라 쓰고
      //   서버는 그대로 써서 미리보기와 확정액이 갈렸다(시험 25% → 앱 20% / 서버 25%).
      ToastHelper.showWarning(TextLayout.keepWords('요율 값을 확인해주세요\n'
          '국민연금·건강·고용 0~20%, 그 밖의 요율 0~30%, 비과세 한도 0~500,000원'));
      return;
    }
    setState(() => _isSaving = true);
    try {
      await (widget.save ?? ((r, e) => InsuranceRateService.saveRates(r, expected: e)))(parsed, _stored[_selectedYear]);
      if (!mounted) return; // [BUG-수정] async gap 후 mounted 체크
      _rates[_selectedYear] = parsed;
      _stored[_selectedYear] = parsed;
      ToastHelper.showSuccess('$_selectedYear년 보험료율 저장 완료');
    } on InsuranceRatesChangedException catch (e) {
      if (!mounted) return;
      ToastHelper.showError(TextLayout.keepWords('${e.year}년 보험료율이 이 화면을 연 뒤 다른 곳에서 바뀌었습니다. 다시 불러온 값을 확인한 뒤 저장해 주세요'));
      await _load();
    } catch (e) {
      // 저장 결과를 모른다 — 실패라고 단정하지 않고 다시 읽어 보인다.
      if (mounted) ToastHelper.showError('저장 결과를 확인하지 못했습니다. 다시 불러온 값을 확인해 주세요');
      if (mounted) await _load();
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
    return AppPageScaffold(
      title: '보험료율 관리',
      actions: [
        IconButton(
          icon: const Icon(Icons.add, color: Colors.white),
          tooltip: '연도 추가',
          // 저장 중 탭 시 _selectedYear 변경 → 저장 데이터 덮어쓰기 방지
          onPressed: _isSaving || _isLoading || refreshingKeep || _loadError != null ? null : _addYear,
        ),
      ],
      body: KeepContentBody(
        refreshing: refreshingKeep,
        child: _isLoading
          ? const LoadingWidget()
          : _loadError != null
              // [.59] 읽지 못했으면 내장값을 현재값처럼 보이거나 저장 버튼을 열지 않는다.
              ? AppEmptyState(
                  icon: Icons.cloud_off_outlined,
                  title: '보험료율을 불러오지 못했습니다',
                  subtitle: '저장된 값을 모르는 상태라 편집과 저장을 막았습니다.',
                  action: TextButton(
                    onPressed: _load,
                    child: const Text('다시 시도'),
                  ),
                )
              : _railWidth() <= MediaQuery.sizeOf(context).width / 3
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 연도 목록
                        _buildYearList(theme),
                        const VerticalDivider(width: 1),
                        // 요율 편집
                        Expanded(child: _buildEditor(theme)),
                      ],
                    )
                  // [.59] 글자가 커서 왼쪽 목록이 화면 1/3 을 넘으면 연도를 위쪽 가로 목록으로 옮긴다(글자를 줄이지 않는다).
                  : Column(
                      children: [
                        _buildYearChips(theme),
                        const Divider(height: 1),
                        Expanded(child: _buildEditor(theme)),
                      ],
                    ),
      ),
    );
  }

  TextStyle _yearStyle(bool selected, ThemeData theme) => ResponsiveHelper.bodyStyle(
        context,
        color: selected ? theme.primaryColor : null,
      ).copyWith(fontWeight: selected ? FontWeight.bold : FontWeight.normal);

  static const double _railPad = 12;

  /// [.59] '2026/년' 처럼 숫자와 단위가 갈렸다(Pixel 5 392·1.0, 고정 폭 90). 가장 긴 연도 글자를 실제로 재서 폭을 정한다.
  double _railWidth() {
    final tp = TextPainter(
      text: TextSpan(text: TextLayout.keepWords('${_rates.keys.fold<int>(0, (m, y) => y > m ? y : m)}년'), style: _yearStyle(true, Theme.of(context))),
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    // ListTile 이 물려주는 글자 간격 등은 여기서 재지 못한다 — 8% 여유(시험 실측: 4.5px 모자람).
    return (tp.width * 1.08 + _railPad * 2 + 4).clamp(90.0, double.infinity);
  }

  Widget _buildYearChips(ThemeData theme) {
    final years = _rates.keys.toList()..sort((a, b) => b.compareTo(a));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 8)),
      child: Row(
        children: [
          for (final y in years)
            Padding(
              padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
              child: ChoiceChip(
                label: Text(TextLayout.keepWords('$y년'), semanticsLabel: '$y년',
                    style: _yearStyle(y == _selectedYear, theme)),
                selected: y == _selectedYear,
                onSelected: (_) => _selectYear(y),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildYearList(ThemeData theme) {
    final years = _rates.keys.toList()..sort((a, b) => b.compareTo(a));
    return SizedBox(
      width: _railWidth(),
      child: ListView.builder(
        itemCount: years.length,
        itemBuilder: (_, i) {
          final y = years[i];
          final selected = y == _selectedYear;
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: _railPad),
            selected: selected,
            selectedTileColor: theme.primaryColor.withValues(alpha: 0.1),
            title: Text(
              TextLayout.keepWords('$y년'),
              semanticsLabel: '$y년',
              style: _yearStyle(selected, theme),
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
            TextLayout.keepWords('$_selectedYear년 보험료율'),
            style: ResponsiveHelper.subtitleStyle(context)
                .copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            // [.59] 320·1.3 에서 '사업/주' 로 갈렸다(기기) — 낱말로 묶는다.
            TextLayout.keepWords('근로자 부담분 기준. 사업주 부담분은 별도.'),
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
          ),
          if (!_stored.containsKey(_selectedYear)) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            // [.59] 저장값이 없는데 내장값을 저장값처럼 보였다. 서버 급여 확정은 저장값이 없으면 서버 내장값을 쓴다
            //   — 앱 내장값과 다를 수 있다(LOCAL 확인: 2026 서버 내장 4.5% / 앱 4.75%).
            Text(
              TextLayout.keepWords('저장된 $_selectedYear년 요율이 없습니다. 아래는 앱 내장 기본값입니다. '
                  '저장값이 없으면 서버 급여 확정은 서버 내장값을 써서 금액이 다를 수 있습니다. 확인 후 저장해 주세요.'),
              style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
            ),
          ],
          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
          _buildSection('4대보험 요율 (%) — $_selectedYear년 기준', [
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
          TextLayout.keepWords(title),
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

  // [.59] 칸 이름은 칸 위의 글자로 둔다 — 떠 있는 라벨은 한 줄이라 큰 글자에서 '장기요양 (건보료 대…' 처럼 잘렸다
  //   (Pixel 5 392·2.0). 이름은 줄을 바꿔 다 보이고, 칸은 이름을 접근성 라벨로 갖는다.
  Widget _labeled(String label, Widget field) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(TextLayout.keepWords(label), semanticsLabel: label,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700)),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Semantics(label: label, child: field),
        ],
      ),
    );
  }

  Widget _field(String label, TextEditingController ctrl, String hint) {
    return _labeled(label, TextField(
      key: ValueKey('rate-$label'),
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d.]'))],
      decoration: InputDecoration(
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixText: '%',
      ),
    ));
  }

  Widget _fieldInt(String label, TextEditingController ctrl, String hint) {
    return _labeled(label, TextField(
      key: ValueKey('rate-$label'),
      controller: ctrl,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
        suffixText: '원',
      ),
    ));
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
    // [.59] 범위 = 앱 계산(InsuranceRateModel.fromMap clamp)이 실제로 쓰는 상한. 예전 '0~100% 미만' 은
    //   앱이 잘라 쓰는 값(예: 25% → 20%)까지 저장해 서버 확정액과 갈렸다.
    if ([p, h, e].any((v) => v < 0 || v > 20)) return null;
    if ([l, dt, lt, bi, bl].any((v) => v < 0 || v > 30)) return null;
    if (ex < 0 || ex > 500000) return null;
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
    if (v == null || v < 2000 || v > 2100) {
      ToastHelper.showError('2000~2100 사이의 연도를 입력해주세요');
      return;
    }
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
