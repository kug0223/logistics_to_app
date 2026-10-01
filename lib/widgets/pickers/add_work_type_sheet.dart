import 'dart:math' show max;

import 'package:flutter/material.dart';
import '../../models/core/business_work_type_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import 'icon_picker_dialog.dart';

/// 저장을 실제로 수행하는 쪽이 돌려주는 결과. `true` 면 저장됐다.
typedef WorkTypeSubmit = Future<bool> Function(Map<String, dynamic> draft);

/// 업무유형 추가/수정 바텀시트
///
///   [R7-P4.4E.5.2] 예전에는 저장을 누르면 **먼저 닫고** 부모가 쓰기를 했다.
///   그래서 중복 이름이나 네트워크로 실패하면 시트는 이미 사라진 뒤였고,
///   관리자는 이름·아이콘·색을 처음부터 다시 골라야 했다. 잘못 저장된 것도
///   권한이 샌 것도 아니지만, **정상적인 실패에서 한 일을 잃게** 만든다.
///
///   쓰기 주체는 **그대로 부모**다 — businessId·중복 검사·권한·timestamps·
///   목록 갱신 전부. 바뀐 것은 **닫는 시점**뿐이다: 저장이 성공해야 닫는다.
class AddWorkTypeSheet extends StatefulWidget {
  final BusinessWorkTypeModel? editTarget;

  /// 시트가 모은 draft 로 **부모가** 저장을 수행한다.
  final WorkTypeSubmit onSubmit;

  const AddWorkTypeSheet._({this.editTarget, required this.onSubmit});

  /// 저장에 성공하면 `true` 로 닫힌다. 사용자가 그냥 닫으면 `null`.
  static Future<bool?> show(
    BuildContext context, {
    BusinessWorkTypeModel? editTarget,
    required WorkTypeSubmit onSubmit,
  }) {
    return DialogHelper.showSheet<bool>(
      context,
      isScrollControlled: true,
      builder: (_) =>
          AddWorkTypeSheet._(editTarget: editTarget, onSubmit: onSubmit),
    );
  }

  @override
  State<AddWorkTypeSheet> createState() => _AddWorkTypeSheetState();
}

class _AddWorkTypeSheetState extends State<AddWorkTypeSheet> {
  static const List<Color> _palette = AppColors.workTypePalette;

  static String _toHex(Color c) {
    final rgb = c.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  late Color _bgColor;
  IconItem? _selectedIcon;
  List<IconItem> _suggested = [];

  /// [R7-P4.4E.5.2] 저장이 진행 중인가 — 중복 전송을 막는다.
  bool _saving = false;

  /// 직전 저장이 실패했는가 — 입력이 그대로 남아 있다는 것을 말해 준다.
  ///   실패 **이유**는 writer 가 구분해서 말하므로 여기서 다시 쓰지 않는다.
  bool _failed = false;

  bool get _isEdit => widget.editTarget != null;

  @override
  void initState() {
    super.initState();
    _bgColor = _palette[0];

    final edit = widget.editTarget;
    if (edit != null) {
      _nameCtrl.text = edit.name;
      _searchCtrl.text = edit.name;

      if (edit.backgroundColor != null) {
        try {
          _bgColor = FormatHelper.parseColor(edit.backgroundColor!);
        // 색상 파싱 실패 시 기본 색상 유지 — 잘못된 색상 문자열 무시
        } catch (_) {}
      }

      if (edit.icon.startsWith('material:')) {
        final cp = int.tryParse(edit.icon.substring(9));
        if (cp != null) {
          final all = IconPickerDialog.getAllIcons();
          try {
            _selectedIcon = all.firstWhere((i) => i.icon.codePoint == cp);
          } catch (_) {
            // codePoint가 목록에 없으면 기본 아이콘으로 폴백 (runtime IconData 금지)
            _selectedIcon = IconItem(
              icon: Icons.work,
              label: '',
              keywords: [],
              category: '',
            );
          }
        }
      }
    }

    _suggested = IconPickerDialog.getSuggestedIcons(_searchCtrl.text);
    _searchCtrl.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final newSuggested = IconPickerDialog.getSuggestedIcons(_searchCtrl.text);
    setState(() {
      _suggested = newSuggested;
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openFullPicker() async {
    final result = await IconPickerDialog.show(
      context: context,
      initialSearchText: _searchCtrl.text,
      initialIcon: _selectedIcon != null
          ? 'material:${_selectedIcon!.icon.codePoint}'
          : null,
    );
    if (result != null && mounted) {
      setState(() => _selectedIcon = result);
    }
  }

  Future<void> _submit() async {
    // [R7-P4.4E.5.2] 저장 중에는 한 번만 보낸다 — 빠르게 두 번 눌러도
    //   쓰기는 1회다. 버튼 비활성만으로는 탭이 겹치는 순간을 못 막는다.
    if (_saving) return;

    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    if (name.length > 50) {
      // maxLength 초과는 UI에서 이미 차단되지만 방어적으로 추가
      return;
    }

    final iconStr = _selectedIcon != null
        ? 'material:${_selectedIcon!.icon.codePoint}'
        : null;

    final draft = <String, dynamic>{
      'name': name,
      'icon': iconStr,
      'iconColor': '#FFFFFF',
      'backgroundColor': _toHex(_bgColor),
    };

    FocusScope.of(context).unfocus();
    setState(() {
      _saving = true;
      _failed = false;
    });

    bool ok = false;
    try {
      ok = await widget.onSubmit(draft);
    } catch (e) {
      // 부모가 못 삼킨 예외도 draft 를 잃는 이유가 되지 않는다.
      debugPrint('❌ 업무유형 저장 실패: $e');
      ok = false;
    }
    if (!mounted) return;

    if (ok) {
      // **성공했을 때만** 닫는다.
      Navigator.pop(context, true);
      return;
    }

    // 실패 — 시트도 입력도 그대로 두고 다시 누를 수 있게 한다.
    //   실패 이유는 writer 가 이미 구분해서 말한다(중복 / 그 외).
    //   여기서 그 판정을 다시 쓰지 않는다.
    setState(() {
      _saving = false;
      _failed = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [R7-P4.4E.5] 바깥(DialogHelper)이 **실제로 넣은 값**을 빼야 한다.
    //
    //   예전에는 `viewPadding.bottom` 을 뺐는데, 바깥은
    //   `max(8.0, viewPadding.bottom)` 을 넣고 있었다. 홈 인디케이터가 8dp
    //   보다 얇은 기기에서는 그 차이만큼 바닥이 넘쳤다 — 실기기에서 정확히
    //   `BOTTOM OVERFLOWED BY 2.0 PIXELS`(=8-6) 였다.
    //   두 곳이 같은 함수를 본다. 숫자를 2 깎아 숨기지 않는다.
    final bottom = max(
      0.0,
      MediaQuery.viewInsetsOf(context).bottom -
          DialogHelper.sheetBottomInset(context),
    );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _handle(),
          _header(),
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 20),
                0,
                ResponsiveHelper.spacing(context, 20),
                ResponsiveHelper.spacing(context, 20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  _preview(),
                  SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                  _iconSearchField(theme),
                  SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                  _iconRow(theme),
                  SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                  _colorRow(theme),
                  SizedBox(height: ResponsiveHelper.spacing(context, 32)),
                  _actions(theme),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _handle() => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 4),
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.grey300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );

  Widget _header() => Padding(
        padding: EdgeInsets.fromLTRB(
          ResponsiveHelper.spacing(context, 20),
          ResponsiveHelper.spacing(context, 4),
          ResponsiveHelper.spacing(context, 8),
          0,
        ),
        child: Row(
          children: [
            // [R7-P4.4E.5.1] 제목이 공간을 양보한다.
            //   `Text + Spacer` 는 제목이 길어져도 줄지 못한다. 글자 배율
            //   2.0 에서 '새 업무유형 추가' 만으로 320dp 를 넘겼다(실측 96px).
            //   줄바꿈을 허용해 큰 배율에서도 제목을 끝까지 읽게 한다.
            Expanded(
              child: Text(
                _isEdit ? '업무유형 수정' : '새 업무유형 추가',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ResponsiveHelper.titleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                FocusScope.of(context).unfocus();
                Navigator.pop(context);
              },
            ),
          ],
        ),
      );

  // ─── 미리보기 + 이름 직접 입력 ────────────────────────────────────
  Widget _preview() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.circular(16),
        // [R7-P4.4E.5] 컬러 글로우(alpha 0.4 · blur 16)를 낮췄다.
        //
        //   이 블록은 **미리보기**다 — 저장하면 공고·일정·근태 카드에
        //   그대로 나타나는 그 칩이다. 그런데 그림자가 세서 입력란이
        //   아니라 큰 CTA 버튼처럼 읽혔고, 아래 아이콘·색 선택보다 훨씬
        //   무거워 "업무를 등록하는 화면" 이 "꾸미는 화면" 처럼 보였다.
        //   현재 관리자 화면 기준은 낮은 elevation 이다.
        boxShadow: [
          BoxShadow(
            color: _bgColor.withValues(alpha: 0.18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 왼쪽 아이콘 (고정 너비)
          SizedBox(
            width: 30,
            child: _buildPreviewIcon(),
          ),
          // 가운데 이름 입력 (Expanded + 텍스트 가운데 정렬)
          Expanded(
            child: TextField(
              controller: _nameCtrl,
              autofocus: !_isEdit,
              textAlign: TextAlign.center,
              maxLength: 50,
              style: ResponsiveHelper.bodyStyle(context, color: Colors.white)
                  .copyWith(fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: '업무유형 이름 입력',
                hintStyle: ResponsiveHelper.bodyStyle(context,
                    color: Colors.white54),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                counterText: '', // 글자수 카운터 숨김 (디자인 유지)
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              cursorColor: Colors.white,
              textInputAction: TextInputAction.done,
            ),
          ),
          // 오른쪽 균형용 공간 (왼쪽 아이콘과 동일 너비)
          const SizedBox(width: 30),
        ],
      ),
    );
  }

  Widget _buildPreviewIcon() {
    if (_selectedIcon != null) {
      return Icon(_selectedIcon!.icon,
          color: Colors.white,
          size: ResponsiveHelper.iconSize(context, 22));
    }
    return ListenableBuilder(
      listenable: _nameCtrl,
      builder: (ctx, __) {
        if (_nameCtrl.text.isNotEmpty) {
          return Text(
            _nameCtrl.text.characters.first,
            style: ResponsiveHelper.subtitleStyle(ctx)
                .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
          );
        }
        return Icon(Icons.edit,
            color: Colors.white54,
            size: ResponsiveHelper.iconSize(ctx, 20));
      },
    );
  }

  // ─── 아이콘 검색 필드 ─────────────────────────────────────────────
  Widget _iconSearchField(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('아이콘 검색'),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              // [R7-P4.4E.5] 예시를 실제 쓰임에 가깝게 바꿨다.
              //   '배달·청소·요리·운동' 은 이 제품에서 관리자가 만드는 업무와
              //   거리가 있다. 다만 한 업종으로 고정하지도 않는다 — 물류·
              //   매장·서비스가 섞이게 둔다.
              // [R7-P4.4E.5.1] 예시는 **사전이 실제로 찾아 주는 말**이어야 한다.
              //   직전에 넣은 '상하차' 는 매칭이 0건이었다 — 찾으라고 적어 둔
              //   말이 안 찾아지면 검색이 고장난 것처럼 보인다.
              //   아래 넷은 모두 매칭이 있다(포장 3 · 검수 2 · 청소 2 · 서빙 1).
              hintText: '예: 포장, 검수, 청소, 서빙',
              prefixIcon:
                  Icon(Icons.search, color: theme.primaryColor),
              suffixIcon: ListenableBuilder(
                listenable: _searchCtrl,
                builder: (_, __) => _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _searchCtrl.clear(),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            textInputAction: TextInputAction.search,
          ),
        ],
      );

  // ─── 아이콘 추천 행 ───────────────────────────────────────────────
  Widget _iconRow(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 같은 이유로 여기도 양보한다 — 라벨과 '전체 보기' 가
              //   큰 배율에서 한 줄을 넘길 수 있다.
              Expanded(child: _label('아이콘')),
              TextButton.icon(
                onPressed: _openFullPicker,
                icon: Icon(Icons.grid_view_rounded,
                    size: 15, color: theme.primaryColor),
                label: Text(
                  '전체 보기',
                  style: ResponsiveHelper.smallStyle(context,
                      color: theme.primaryColor),
                ),
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          // [R7-P4.4E.5.1] 고정 높이 상자를 없앴다 — **내용이 높이를 정한다.**
          //
          //   예전에는 상자가 `spacing(context, 80)` 이라 화면이 좁으면 같이
          //   줄었는데(320dp → ×0.82 → 65.6), 안에 든 칩은 `52 + 5 + 라벨` 로
          //   **고정**이었다. 좁은 화면과 큰 글자 배율에서 내용이 상자보다
          //   커져 바닥이 넘쳤다 — 키보드와 무관하게 늘 넘치던 자리다.
          //
          //   수평 스크롤에는 높이 제약이 필요하지만, 그 높이를 숫자로 정할
          //   이유가 없다. `Row` 를 감싸면 내용의 실제 높이가 그대로 상자가
          //   된다. 8을 6으로 깎는 식의 보정이 아니라 **원인을 없앤다.**
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _iconChip(null, isNone: true, theme: theme),
                const SizedBox(width: 8),
                if (_selectedIcon != null &&
                    !_suggested.any(
                        (s) => s.icon.codePoint == _selectedIcon!.icon.codePoint)) ...[
                  _iconChip(_selectedIcon, theme: theme),
                  const SizedBox(width: 8),
                ],
                ..._suggested.map((item) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _iconChip(item, theme: theme),
                    )),
              ],
            ),
          ),
        ],
      );

  Widget _iconChip(IconItem? item,
      {bool isNone = false, required ThemeData theme}) {
    final isSelected = isNone
        ? _selectedIcon == null
        : item != null &&
            _selectedIcon?.icon.codePoint == item.icon.codePoint;

    return GestureDetector(
      onTap: () => setState(() => _selectedIcon = isNone ? null : item),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isSelected ? _bgColor : AppColors.grey100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected ? _bgColor : AppColors.grey200,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: _bgColor.withValues(alpha: 0.35),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Icon(
              isNone ? Icons.do_not_disturb_alt_outlined : item!.icon,
              color: isSelected ? Colors.white : AppColors.grey500,
              size: 26,
            ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 52,
            child: Text(
              isNone ? '없음' : (item!.label),
              style: ResponsiveHelper.tinyStyle(context,
                      color: isSelected ? theme.primaryColor : AppColors.grey500)
                  .copyWith(
                fontWeight:
                    isSelected ? FontWeight.bold : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 배경색 선택 ──────────────────────────────────────────────────
  Widget _colorRow(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label('배경색'),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          // [R7-P4.4E.5] 고정폭 8칸을 `Row` 에 넣어 좁은 화면에서 넘쳤다.
          //
          //   320dp 에서 쓸 수 있는 가로는 ~280dp 인데 swatch 8개가 288dp 다
          //   (선택된 칸은 42dp 로 더 커져 6dp 가 더 붙는다). `spaceBetween`
          //   은 남는 공간을 나눌 뿐 모자란 공간을 만들지 못한다.
          //   줄바꿈을 허용한다 — preset 을 줄이면 색 선택지가 사라지고,
          //   칸을 더 줄이면 터치 영역이 작아진다.
          Wrap(
            spacing: ResponsiveHelper.spacing(context, 8),
            runSpacing: ResponsiveHelper.spacing(context, 8),
            children: _palette.map((color) {
              final isSelected =
                  _bgColor.toARGB32() == color.toARGB32();
              return GestureDetector(
                onTap: () => setState(() => _bgColor = color),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: isSelected ? 42 : 36,
                  height: isSelected ? 42 : 36,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                    border: isSelected
                        ? Border.all(color: Colors.white, width: 3)
                        : null,
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: color.withValues(alpha: 0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: isSelected
                      ? const Icon(Icons.check,
                          color: Colors.white, size: 18)
                      : null,
                ),
              );
            }).toList(),
          ),
        ],
      );

  // ─── 액션 버튼 ────────────────────────────────────────────────────
  Widget _actions(ThemeData theme) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // [R7-P4.4E.5.2] 왜 안 닫혔는지, 무엇이 남아 있는지 말한다.
          //   실패 **이유**는 writer 가 이미 구분해서 알린다(중복 / 그 외).
          //   여기서는 그 판정을 다시 쓰지 않고, 이 시트의 맥락에서만
          //   필요한 것을 말한다 — 입력이 살아 있고 다시 누르면 된다.
          if (_failed) ...[
            Text(
              '저장하지 못했어요. 입력한 내용은 그대로예요.',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.error),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          ],
          Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _saving
                  ? null
                  : () {
                FocusScope.of(context).unfocus();
                Navigator.pop(context);
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('취소'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ListenableBuilder(
              listenable: _nameCtrl,
              builder: (_, __) => ElevatedButton(
                onPressed: (_saving || _nameCtrl.text.trim().isEmpty)
                    ? null
                    : _submit,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(_isEdit ? '수정 완료' : '추가'),
              ),
            ),
          ),
            ],
          ),
        ],
      );

  Widget _label(String text) => Text(
        text,
        style: ResponsiveHelper.smallStyle(context).copyWith(
          fontWeight: FontWeight.bold,
          color: AppColors.textSecondary,
        ),
      );
}
