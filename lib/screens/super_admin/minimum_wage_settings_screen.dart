import 'package:flutter/material.dart';
// [R7-P1-6 P16-A] GradientScaffold(지원자 공통 레이아웃) → AppPageScaffold
//   (D0 관리자 표준 flat shell). 이 화면은 headerContent 를 쓰지 않고 헤더에
//   TabBar 도 없으며 가로 스크롤 표도 없다 — 그래서 위젯 이름만 바뀐다.
//   본문의 흰 카드는 flat 배경(grey100) 위에서 그대로 카드로 읽힌다.
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';
import '../../utils/responsive_helper.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/wage_calculator.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../utils/keep_content_refresh.dart';
import '../../widgets/common/keep_content_body.dart';

/// [MW-52] 화면 값과 서버에서 불러온 값의 차이만 연도별 변경으로 만든다.
///   expected = 서버에서 불러온 그 연도의 값(없었으면 null) — 서버가 현재 값과 비교해 다르면 충돌로 거절한다.
List<Map<String, Object?>> minimumWageChanges(Map<int, int> server, Map<int, int> edited) {
  final out = <Map<String, Object?>>[];
  for (final e in edited.entries) {
    if (server[e.key] != e.value) {
      out.add({'year': e.key, 'op': 'set', 'wage': e.value, 'expected': server[e.key]});
    }
  }
  for (final e in server.entries) {
    if (!edited.containsKey(e.key)) out.add({'year': e.key, 'op': 'delete', 'expected': e.value});
  }
  out.sort((a, b) => (a['year'] as int).compareTo(b['year'] as int));
  return out;
}

class MinimumWageSettingsScreen extends StatefulWidget {
  const MinimumWageSettingsScreen({super.key});

  @override
  State<MinimumWageSettingsScreen> createState() => _MinimumWageSettingsScreenState();
}

class _MinimumWageSettingsScreenState extends State<MinimumWageSettingsScreen>
    with KeepContentRefreshMixin {
  /// [impl_28] 마지막으로 서버에서 읽어 보인 표 — 다시 읽는 동안 편집 중이던 값 대신 이것을 보인다(값 미리 표시 0).
  Map<int, int> _lastShownWages = const {};
  final _firestore = FirebaseFirestore.instance;
  final int _currentYear = DateTime.now().year;

  bool _isLoading = true;
  bool _isSaving = false;
  // [SA-MINWAGE.51] 불러오기 실패 상태에서 저장하면 빈 표가 서버 값을 지운다(mergeFields 는 맵 전체를 바꾼다) — 저장을 막는다.
  bool _loadFailed = false;
  Map<int, int> _wages = {};
  // [MW-52] 서버에서 실제로 불러온 값(문서가 없으면 빈 표). 화면의 기본표와 구별한다 — 저장은 이 값과의 차이만 보낸다.
  Map<int, int> _serverWages = {};

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
    // [L48 · impl_28] 처리 뒤 다시 읽기는 목록을 유지한다(잠금 + 얇은 진행 표시 · KeepContentRefreshMixin) — 첫 읽기·실패 화면만 전체 로딩 · 늦은 옛 응답 착지 0.
    //   값 미리 표시 0: 유지하는 동안 표는 **마지막으로 읽은 값**으로 되돌린다(서버가 거절한 편집값을 보이지 않게).
    final t = beginContentLoad(canKeep: !_loadFailed);
    setState(() {
      if (t.keep) {
        _wages = Map.of(_lastShownWages);
      } else {
        _isLoading = true;
      }
      _loadFailed = false;
    });
    var shown = false;
    try {
      final doc = await _firestore.collection('settings').doc('wage_config').get();
      if (!isCurrentContentLoad(t.gen)) return;
      final raw = doc.data()?['minimumWages'];
      // [MW-52] 양의 정수만 값으로 본다 — 손상된 값(문자열·소수)은 비어 있는 연도로 보이고, 서버도 '없음'과 같이 비교해 덮어쓸 수 있다.
      _serverWages = {
        if (raw is Map)
          for (final e in raw.entries)
            if (int.tryParse(e.key.toString()) != null && e.value is int && (e.value as int) > 0)
              int.parse(e.key.toString()): e.value as int,
      };
      _wages = Map.of(_serverWages);
      if (_wages.isEmpty) {
        _wages = {
          2020: 8590, 2021: 8720, 2022: 9160, 2023: 9620,
          2024: 9860, 2025: 10030, 2026: 10320,
          2027: 10700, // [.73] 고시 제2026-60호 — 서버 SETMW 공식표와 같은 값
        };
      }
      _lastShownWages = Map.of(_wages);
      shown = true;
    } catch (e) {
      debugPrint('⚠️ 최저시급 설정 불러오기 실패: $e');
      if (!isCurrentContentLoad(t.gen)) return;
      _wages = {};
      _loadFailed = true;
      ToastHelper.showError('최저시급 설정을 불러오지 못했습니다. 다시 열어 주세요. 이 상태에서는 저장할 수 없습니다.');
    } finally {
      if (isCurrentContentLoad(t.gen)) {
        setState(() => _isLoading = false);
        finishContentLoad(t.gen, shown: shown);
      }
    }
  }

  Future<void> _save() async {
    if (_isSaving) return;
    if (_loadFailed) return;
    final changes = minimumWageChanges(_serverWages, _wages);
    if (changes.isEmpty) {
      ToastHelper.showInfo('바뀐 내용이 없습니다.');
      return;
    }
    setState(() => _isSaving = true);
    try {
      // [MW-52] 연도별 변경만 서버가 검증·저장한다(양의 정수·법정 최저임금 이상·충돌 확인·감사 기록).
      //   직접 쓰기는 규칙 후보가 막는다. 다른 연도·보험료율은 건드리지 않는다.
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableSetMinimumWages')
          .call<Map<String, dynamic>>({'changes': changes});
      await WageCalculator.loadMinimumWages();
      if (!mounted) return;
      ToastHelper.showSuccess('저장되었습니다. 새 지원·초대부터 이 기준으로 판정합니다.');
      await _load(); // 저장된 서버 값으로 다시 그린다
    } on FirebaseFunctionsException catch (e) {
      debugPrint('⚠️ 최저시급 저장 거절: ${e.code}');
      if (!mounted) return;
      // 서버 문장(법정 최저임금 미만·충돌·권한)을 그대로 보인다. 충돌이면 최신 값으로 다시 그린다.
      ToastHelper.showError(TextLayout.keepWords(e.message ?? '저장하지 못했습니다.'));
      if (e.code == 'aborted') await _load();
    } catch (e) {
      debugPrint('⚠️ 최저시급 저장 실패: $e');
      if (mounted) ToastHelper.showError('저장 결과를 확인하지 못했습니다. 화면을 다시 열어 확인해 주세요.');
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
          // [MW-52] 삭제한 연도는 그 연도의 법정 내장값으로만 판정한다. 내장값이 없는 연도는 '확인 불가'가 되어 그 연도 근무의
          //   새 공개·지원·확정이 막힌다(다른 연도 값으로 대신하지 않는다).
          TextLayout.keepWords('$year년 최저시급을 삭제하시겠습니까?\n삭제하면 그 연도는 앱·서버에 내장된 법정 최저임금으로 판정합니다. '
              '내장값이 없는 연도는 기준을 확인할 수 없어 그 연도 근무의 새 공고 공개·지원·확정이 막힙니다.'),
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

    return AppPageScaffold(
      title: '최저시급 관리',
      actions: [
        if (!_isLoading)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: (_isSaving || _loadFailed || refreshingKeep) ? null : _save,
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
      body: KeepContentBody(
        refreshing: refreshingKeep,
        child: _isLoading
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
      ),
      floatingActionButton: _isLoading || refreshingKeep
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
