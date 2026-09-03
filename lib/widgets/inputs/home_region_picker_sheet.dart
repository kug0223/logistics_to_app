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
            child: Row(
              children: [
                if (_showCities) ...[
                  GestureDetector(
                    onTap: _goBackToProvince,
                    child: Icon(
                      Icons.arrow_back_ios,
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                ],
                Expanded(
                  child: Text(
                    _showCities && _province != null
                        ? '$_province — 시/군/구 선택'
                        : '시/도 선택',
                    style: ResponsiveHelper.titleStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text(
                    '닫기',
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: AppColors.grey500,
                    ),
                  ),
                ),
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
        color: isSelected
            ? theme.primaryColor.withValues(alpha: 0.08)
            : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? theme.primaryColor : null,
                ),
              ),
            ),
            if (isSelected)
              Icon(
                Icons.check,
                color: theme.primaryColor,
                size: ResponsiveHelper.iconSize(context, 18),
              )
            else if (trailing != null)
              Icon(
                trailing,
                color: AppColors.grey400,
                size: ResponsiveHelper.iconSize(context, 18),
              ),
          ],
        ),
      ),
    );
  }
}
