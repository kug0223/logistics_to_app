// lib/widgets/inputs/home_region_picker_sheet.dart
//
// 주로 일할 지역 선택 바텀시트 (시/도 → 시/군/구 2단계)
//
// RegionPickerSheet(시/군/구 → 동)과 별도 구현:
//   - Level 1: 시/도 (province) 선택
//   - Level 2: 시/군/구 (city) 선택
//   - 반환: UserRegion(province, city, district: null)
//
// 세종특별자치시 특수 처리:
//   - 시/군/구 없음 → Level 1 선택 즉시 완료
//   - UserRegion(province: '세종특별자치시', city: '세종특별자치시')

import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../models/core/user_region.dart';
import '../../data/korean_regions.dart';

class HomeRegionPickerSheet extends StatefulWidget {
  const HomeRegionPickerSheet({
    super.key,
    this.selectedRegion,
  });

  final UserRegion? selectedRegion;

  /// 바텀시트를 띄우고 선택된 UserRegion을 반환 (취소 시 null)
  static Future<UserRegion?> show({
    required BuildContext context,
    UserRegion? selectedRegion,
  }) {
    return DialogHelper.showSheet<UserRegion>(
      context,
      isScrollControlled: true,
      builder: (_) => HomeRegionPickerSheet(selectedRegion: selectedRegion),
    );
  }

  @override
  State<HomeRegionPickerSheet> createState() => _HomeRegionPickerSheetState();
}

class _HomeRegionPickerSheetState extends State<HomeRegionPickerSheet> {
  String? _province; // 선택된 시/도
  bool _showCities = false; // true → 시/군/구 목록 표시

  @override
  void initState() {
    super.initState();
    _province = widget.selectedRegion?.province;
    _showCities = _province != null;
  }

  List<String> get _cities =>
      _province != null ? KoreanRegions.citiesOf(_province!) : const [];

  void _selectProvince(String province) {
    // 세종특별자치시 — 시/군/구 없음, 즉시 완료
    if (KoreanRegions.isSejong(province)) {
      Navigator.pop(
        context,
        UserRegion(province: province, city: province),
      );
      return;
    }
    setState(() {
      _province = province;
      _showCities = true;
    });
  }

  void _selectCity(String city) {
    Navigator.pop(
      context,
      UserRegion(province: _province!, city: city),
    );
  }

  void _goBackToProvince() {
    setState(() {
      _showCities = false;
      _province = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.65;
    final title = _showCities && _province != null
        ? '$_province — 시/군/구 선택'
        : '시/도 선택';
    // [DU266 r1] 줄표는 앞 지역명에 붙인다(B320 에서 '—' 가 한 줄에 홀로 남았다).
    final titleText = _showCities && _province != null
        ? '${TextLayout.unit('$_province —')} ${TextLayout.keepWords('시/군/구 선택')}'
        : TextLayout.keepWords(title);
    // [DU266 r2] 머리 요소 — 큰 글자(1.3배 이상)면 뒤로·닫기 줄 아래 전체 폭에 제목(좁은 칸에서 '경상북도 —' 가 쪼개졌다).
    final stackedHeader = MediaQuery.textScalerOf(context).scale(10) >= 13;
    // [DU266] 아이콘에 탭만 붙어 터치·낭독 이름이 없었다 → IconButton(48·'뒤로')
    Widget backButton() => IconButton(
          onPressed: _goBackToProvince,
          tooltip: '뒤로',
          color: AppColors.textPrimary,
          icon: Icon(
            Icons.arrow_back_ios,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
        );
    Widget closeButton() => TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: Text(
            '닫기',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: AppColors.textSecondary, // [DU266] grey500(2.68)
            ),
          ),
        );
    // [DU266] 본문색 명시·낱말 단위 줄바꿈
    Widget titleWidget() => Text(
          titleText,
          semanticsLabel: title,
          style: ResponsiveHelper.titleStyle(context, color: AppColors.textPrimary)
              .copyWith(fontWeight: FontWeight.bold),
        );

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // ── 핸들 바 ──────────────────────────────────────────────
          Container(
            margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 12)),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // ── 헤더 ─────────────────────────────────────────────────
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 20),
              vertical: ResponsiveHelper.spacing(context, 16),
            ),
            child: stackedHeader
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        if (_showCities) backButton(),
                        const Spacer(),
                        closeButton(),
                      ]),
                      titleWidget(),
                    ],
                  )
                : Row(
                    children: [
                      if (_showCities) ...[
                        backButton(),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                      ],
                      Expanded(child: titleWidget()),
                      closeButton(),
                    ],
                  ),
          ),

          const Divider(height: 1),

          // ── 목록 ─────────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 4),
              ),
              itemCount: _showCities
                  ? _cities.length
                  : KoreanRegions.provinces.length,
              itemBuilder: (context, index) {
                if (_showCities) {
                  final city = _cities[index];
                  final isSelected =
                      city == widget.selectedRegion?.city &&
                      _province == widget.selectedRegion?.province;
                  return _buildItem(
                    context,
                    label: city,
                    isSelected: isSelected,
                    onTap: () => _selectCity(city),
                    theme: theme,
                  );
                } else {
                  final province = KoreanRegions.provinces[index];
                  final isSelected = province == widget.selectedRegion?.province;
                  return _buildItem(
                    context,
                    label: province,
                    isSelected: isSelected,
                    // 세종은 직접 완료 → chevron 없음
                    trailing: KoreanRegions.isSejong(province)
                        ? null
                        : Icons.chevron_right,
                    onTap: () => _selectProvince(province),
                    theme: theme,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(
    BuildContext context, {
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required ThemeData theme,
    IconData? trailing,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 20),
          vertical: ResponsiveHelper.spacing(context, 14),
        ),
        // [DU266] 선택 = 대표색(알파 8% → brandSurface 토큰), 미선택 본문색, 꺾쇠 grey400(1.9) → textTertiary
        color: isSelected ? AppColors.brandSurface : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                TextLayout.keepWords(label),
                semanticsLabel: label,
                style: ResponsiveHelper.bodyStyle(context,
                        color: isSelected ? AppColors.brand : AppColors.textPrimary)
                    .copyWith(
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check,
                color: AppColors.brand,
                size: ResponsiveHelper.iconSize(context, 18),
              )
            else if (trailing != null)
              Icon(
                trailing,
                color: AppColors.textTertiary,
                size: ResponsiveHelper.iconSize(context, 18),
              ),
          ],
        ),
      ),
    );
  }
}
