import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// 지역(시/군/구 → 동) 2단계 선택 바텀시트
///
/// ```dart
/// final result = await RegionPickerSheet.show(
///   context: context,
///   cities: ['강남구', '수원시', ...],
///   districtOf: (city) => ['역삼동', '삼성동'],
///   selectedCity: _filter.city,
///   selectedDistrict: _filter.district,
/// );
/// if (result != null) {
///   setState(() => _filter = _filter.copyWith(
///     city: result.city, district: result.district,
///   ));
/// }
/// ```
class RegionPickerSheet extends StatefulWidget {
  const RegionPickerSheet({
    super.key,
    required this.cities,
    required this.districtOf,
    this.selectedCity,
    this.selectedDistrict,
  });

  final List<String> cities;
  final List<String> Function(String city) districtOf;
  final String? selectedCity;
  final String? selectedDistrict;

  static Future<RegionResult?> show({
    required BuildContext context,
    required List<String> cities,
    required List<String> Function(String city) districtOf,
    String? selectedCity,
    String? selectedDistrict,
  }) {
    return showModalBottomSheet<RegionResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => RegionPickerSheet(
        cities: cities,
        districtOf: districtOf,
        selectedCity: selectedCity,
        selectedDistrict: selectedDistrict,
      ),
    );
  }

  @override
  State<RegionPickerSheet> createState() => _RegionPickerSheetState();
}

class _RegionPickerSheetState extends State<RegionPickerSheet> {
  String? _city;
  String? _district;
  bool _showDistricts = false;

  @override
  void initState() {
    super.initState();
    _city = widget.selectedCity;
    _district = widget.selectedDistrict;
    _showDistricts = _city != null;
  }

  List<String> get _districts => _city != null ? widget.districtOf(_city!) : [];

  void _selectCity(String city) {
    setState(() {
      _city = city;
      _district = null; // 시/군/구 바뀌면 동 초기화
      _showDistricts = widget.districtOf(city).isNotEmpty;
    });
    if (!_showDistricts) {
      Navigator.pop(context, RegionResult(city: city, district: null));
    }
  }

  void _selectDistrict(String district) {
    Navigator.pop(context, RegionResult(city: _city!, district: district));
  }

  void _confirmCityOnly() {
    if (_city != null) {
      Navigator.pop(context, RegionResult(city: _city!, district: null));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheetHeight = MediaQuery.sizeOf(context).height * 0.6;

    return Container(
      height: sheetHeight,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // 핸들 바
          Container(
            margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 12)),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 헤더
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 20),
              vertical: ResponsiveHelper.spacing(context, 16),
            ),
            child: Row(
              children: [
                if (_showDistricts && _city != null) ...[
                  GestureDetector(
                    onTap: () => setState(() {
                      _showDistricts = false;
                      _city = null;
                    }),
                    child: Icon(Icons.arrow_back_ios, size: ResponsiveHelper.iconSize(context, 20)),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                ],
                Expanded(
                  child: Text(
                    _showDistricts && _city != null ? '$_city — 동 선택' : '지역 선택',
                    style: ResponsiveHelper.titleStyle(context).copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: Text('닫기', style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500)),
                ),
              ],
            ),
          ),

          // 전체 선택 버튼 (시/군/구 단계 — 해당 구 전체 보기)
          if (_showDistricts && _city != null)
            Padding(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 16), 0,
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 8),
              ),
              child: OutlinedButton.icon(
                onPressed: _confirmCityOnly,
                icon: const Icon(Icons.location_city_outlined),
                label: Text('$_city 전체'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 44),
                  side: BorderSide(color: theme.primaryColor),
                  foregroundColor: theme.primaryColor,
                ),
              ),
            ),

          const Divider(height: 1),

          // 목록
          Expanded(
            child: !_showDistricts && widget.cities.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.location_off_outlined,
                            size: ResponsiveHelper.iconSize(context, 48),
                            color: AppColors.grey300),
                        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                        Text(
                          '아직 등록된 지역 정보가 없습니다',
                          style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey400),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                        Text(
                          '공고가 등록되면 지역이 자동으로 나타납니다',
                          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey300),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 4),
                    ),
                    itemCount: _showDistricts ? _districts.length : widget.cities.length,
                    itemBuilder: (context, index) {
                      if (_showDistricts) {
                        final district = _districts[index];
                        final isSelected = district == _district;
                        return _buildItem(
                          context,
                          label: district,
                          isSelected: isSelected,
                          onTap: () => _selectDistrict(district),
                          theme: theme,
                        );
                      } else {
                        final city = widget.cities[index];
                        final isSelected = city == _city;
                        final hasDistricts = widget.districtOf(city).isNotEmpty;
                        return _buildItem(
                          context,
                          label: city,
                          isSelected: isSelected,
                          trailing: hasDistricts ? Icons.chevron_right : null,
                          onTap: () => _selectCity(city),
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
        color: isSelected ? theme.primaryColor.withValues(alpha: 0.08) : null,
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? theme.primaryColor : null,
                ),
              ),
            ),
            if (isSelected)
              Icon(Icons.check, color: theme.primaryColor, size: ResponsiveHelper.iconSize(context, 18))
            else if (trailing != null)
              Icon(trailing, color: AppColors.grey400, size: ResponsiveHelper.iconSize(context, 18)),
          ],
        ),
      ),
    );
  }
}

class RegionResult {
  final String city;
  final String? district;

  const RegionResult({required this.city, this.district});
}
