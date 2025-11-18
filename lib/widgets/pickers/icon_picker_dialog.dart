import 'package:flutter/material.dart';
import '../../utils/format_helper.dart';

/// 아이콘 아이템 클래스
class IconItem {
  final dynamic icon;
  final List<String> keywords;
  final String category;
  final bool isMaterial;
  final bool isPopular;
  
  IconItem({
    required this.icon,
    required this.keywords,
    required this.category,
    this.isMaterial = false,
    this.isPopular = false,
  });
}

/// 아이콘 선택 다이얼로그
class IconPickerDialog {
  /// 아이콘 선택 다이얼로그 표시
  static Future<Map<String, dynamic>?> show({
    required BuildContext context,
    String? initialIcon,
    String? initialIconColor,
    String? initialBackgroundColor,
  }) async {
    final allIcons = _getAllIcons();
    
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _IconPickerWidget(
        allIcons: allIcons,
        initialIcon: initialIcon,
        initialIconColor: initialIconColor,
        initialBackgroundColor: initialBackgroundColor,
      ),
    );
  }

  /// 모든 아이콘 목록 반환
  static List<IconItem> _getAllIcons() {
    return [
      // 물류 관련 (인기)
      IconItem(icon: '📦', keywords: ['box', '상자', '박스', '포장', '물류'], category: '물류/배송', isPopular: true),
      IconItem(icon: '🚚', keywords: ['truck', '트럭', '배송', '운송', '물류'], category: '물류/배송', isPopular: true),
      IconItem(icon: '📋', keywords: ['clipboard', '클립보드', '목록', '리스트', '체크'], category: '물류/배송', isPopular: true),
      IconItem(icon: '✅', keywords: ['check', '체크', '완료', '확인'], category: '물류/배송', isPopular: true),
      IconItem(icon: '🏭', keywords: ['factory', '공장', '제조', '생산'], category: '물류/배송', isPopular: true),
      
      // Material 아이콘 (인기)
      IconItem(icon: Icons.inventory, keywords: ['inventory', '재고', '물류', '창고'], category: '물류/배송', isMaterial: true, isPopular: true),
      IconItem(icon: Icons.local_shipping, keywords: ['shipping', '배송', '트럭', '운송'], category: '물류/배송', isMaterial: true, isPopular: true),
      IconItem(icon: Icons.warehouse, keywords: ['warehouse', '창고', '물류', '보관'], category: '물류/배송', isMaterial: true, isPopular: true),
      IconItem(icon: Icons.category, keywords: ['category', '분류', '카테고리'], category: '물류/배송', isMaterial: true, isPopular: true),
      IconItem(icon: Icons.check_box, keywords: ['checkbox', '체크', '완료', '확인'], category: '물류/배송', isMaterial: true, isPopular: true),
      
      // 물류 관련 (전체)
      IconItem(icon: '📪', keywords: ['mailbox', '우편함', '메일', '배송'], category: '물류/배송'),
      IconItem(icon: '📬', keywords: ['mailbox', '우편함', '메일', '배송'], category: '물류/배송'),
      IconItem(icon: '📮', keywords: ['postbox', '우체통', '우편', '배송'], category: '물류/배송'),
      IconItem(icon: '🚛', keywords: ['truck', '트럭', '배송', '운송'], category: '물류/배송'),
      IconItem(icon: '🚐', keywords: ['van', '밴', '배송', '운송'], category: '물류/배송'),
      IconItem(icon: '🏗️', keywords: ['construction', '건설', '공사', '작업'], category: '물류/배송'),
      IconItem(icon: Icons.archive, keywords: ['archive', '보관', '아카이브'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.inbox, keywords: ['inbox', '받은편지함', '입고'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.unarchive, keywords: ['unarchive', '출고', '언아카이브'], category: '물류/배송', isMaterial: true),
      
      // 음식/음료
      IconItem(icon: '☕', keywords: ['coffee', '커피', '음료', '카페'], category: '음식/음료', isPopular: true),
      IconItem(icon: '🍕', keywords: ['pizza', '피자', '음식'], category: '음식/음료', isPopular: true),
      IconItem(icon: '🍔', keywords: ['burger', '햄버거', '음식'], category: '음식/음료'),
      IconItem(icon: '🍟', keywords: ['fries', '감자튀김', '음식'], category: '음식/음료'),
      IconItem(icon: '🍜', keywords: ['ramen', '라면', '국수', '음식'], category: '음식/음료'),
      IconItem(icon: '🍱', keywords: ['bento', '도시락', '음식'], category: '음식/음료'),
      IconItem(icon: '🍺', keywords: ['beer', '맥주', '술', '음료'], category: '음식/음료'),
      IconItem(icon: '🍰', keywords: ['cake', '케이크', '디저트'], category: '음식/음료'),
      
      // 청소/관리
      IconItem(icon: '🧹', keywords: ['broom', '빗자루', '청소'], category: '청소/관리', isPopular: true),
      IconItem(icon: '🧽', keywords: ['sponge', '스펀지', '청소'], category: '청소/관리'),
      IconItem(icon: '🧴', keywords: ['bottle', '병', '세제'], category: '청소/관리'),
      IconItem(icon: Icons.cleaning_services, keywords: ['cleaning', '청소', '서비스'], category: '청소/관리', isMaterial: true, isPopular: true),
      
      // 도구/작업
      IconItem(icon: '🔧', keywords: ['wrench', '렌치', '수리', '도구'], category: '도구/작업', isPopular: true),
      IconItem(icon: '🔨', keywords: ['hammer', '망치', '공구', '도구'], category: '도구/작업'),
      IconItem(icon: '⚙️', keywords: ['gear', '톱니바퀴', '설정', '작업'], category: '도구/작업'),
      IconItem(icon: Icons.build, keywords: ['build', '빌드', '제작', '도구'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.handyman, keywords: ['handyman', '수리공', '작업자'], category: '도구/작업', isMaterial: true),
      IconItem(icon: Icons.construction, keywords: ['construction', '건설', '공사'], category: '도구/작업', isMaterial: true),
      
      // 사무/문서
      IconItem(icon: '📝', keywords: ['memo', '메모', '문서', '작성'], category: '사무/문서', isPopular: true),
      IconItem(icon: '📄', keywords: ['document', '문서', '서류'], category: '사무/문서'),
      IconItem(icon: '📊', keywords: ['chart', '차트', '그래프', '통계'], category: '사무/문서'),
      IconItem(icon: Icons.assignment, keywords: ['assignment', '과제', '업무'], category: '사무/문서', isMaterial: true),
      IconItem(icon: Icons.description, keywords: ['description', '설명', '문서'], category: '사무/문서', isMaterial: true),
      
      // 기타
      IconItem(icon: '⭐', keywords: ['star', '별', '즐겨찾기', '중요'], category: '기타'),
      IconItem(icon: '❤️', keywords: ['heart', '하트', '좋아요'], category: '기타'),
      IconItem(icon: '👍', keywords: ['thumbsup', '좋아요', '추천'], category: '기타'),
      IconItem(icon: '🎯', keywords: ['target', '타겟', '목표'], category: '기타'),
      IconItem(icon: Icons.work, keywords: ['work', '일', '업무', '작업'], category: '기타', isMaterial: true),
    ];
  }
}

/// 아이콘 선택 위젯
class _IconPickerWidget extends StatefulWidget {
  final List<IconItem> allIcons;
  final String? initialIcon;
  final String? initialIconColor;
  final String? initialBackgroundColor;

  const _IconPickerWidget({
    required this.allIcons,
    this.initialIcon,
    this.initialIconColor,
    this.initialBackgroundColor,
  });

  @override
  State<_IconPickerWidget> createState() => _IconPickerWidgetState();
}

class _IconPickerWidgetState extends State<_IconPickerWidget> {
  final TextEditingController _searchController = TextEditingController();
  List<IconItem> _filteredIcons = [];
  dynamic _selectedIcon;
  Color? _selectedIconColor;
  String _selectedBackgroundColor = '#2196F3';
  String _selectedCategory = '전체 (인기)';

  final List<String> _categories = [
    '전체 (인기)',
    '물류/배송',
    '음식/카페',
    '판매/서비스',
    '청소/관리',
    '사무/행정',
    '작업/제조',
    '기타',
  ];

  final List<String> _predefinedColors = [
    '#F44336', // Red
    '#E91E63', // Pink
    '#9C27B0', // Purple
    '#673AB7', // Deep Purple
    '#3F51B5', // Indigo
    '#2196F3', // Blue (default)
    '#03A9F4', // Light Blue
    '#00BCD4', // Cyan
    '#009688', // Teal
    '#4CAF50', // Green
    '#8BC34A', // Light Green
    '#CDDC39', // Lime
    '#FFEB3B', // Yellow
    '#FFC107', // Amber
    '#FF9800', // Orange
    '#FF5722', // Deep Orange
    '#795548', // Brown
    '#9E9E9E', // Grey
    '#607D8B', // Blue Grey
    '#000000', // Black
  ];

  @override
  void initState() {
    super.initState();
    
    _selectedBackgroundColor = widget.initialBackgroundColor ?? '#2196F3';
    // ✅ 초기 아이콘 색상 설정
    if (widget.initialIconColor != null) {
      _selectedIconColor = FormatHelper.parseColor(widget.initialIconColor!);
    }
    
    if (widget.initialIcon != null) {
      final matchingIcon = widget.allIcons.firstWhere(
        (icon) => icon.icon.toString() == widget.initialIcon,
        orElse: () => widget.allIcons.first,
      );
      _selectedIcon = matchingIcon.icon;
    }
    
    _filteredIcons = widget.allIcons.where((icon) => icon.isPopular).toList();
    _searchController.addListener(_filterIcons);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterIcons() {
    final query = _searchController.text.toLowerCase().trim();
    
    setState(() {
      if (query.isEmpty && _selectedCategory == '전체 (인기)') {
        _filteredIcons = widget.allIcons.where((icon) => icon.isPopular).toList();
      } else if (query.isEmpty) {
        _filteredIcons = widget.allIcons
            .where((icon) => icon.category == _selectedCategory)
            .toList();
      } else if (_selectedCategory == '전체 (인기)') {
        _filteredIcons = widget.allIcons.where((icon) {
          return icon.keywords.any((keyword) => keyword.contains(query));
        }).toList();
      } else {
        _filteredIcons = widget.allIcons.where((icon) {
          return icon.category == _selectedCategory &&
                 icon.keywords.any((keyword) => keyword.contains(query));
        }).toList();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('아이콘 선택'),
      content: SizedBox(
        width: double.maxFinite,
        height: 550,
        child: Column(
          children: [
            // 검색창
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '검색 (예: 입고, 배송, 커피)',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            
            // 카테고리 드롭다운
            DropdownButtonFormField<String>(
              initialValue: _selectedCategory,
              decoration: const InputDecoration(
                labelText: '카테고리',
                border: OutlineInputBorder(),
              ),
              items: _categories.map((category) {
                return DropdownMenuItem(
                  value: category,
                  child: Text(category),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedCategory = value!;
                  _filterIcons();
                });
              },
            ),
            const SizedBox(height: 12),
            
            // 아이콘 그리드 - 반응형
            Expanded(
              child: _filteredIcons.isEmpty
                  ? const Center(child: Text('검색 결과가 없습니다'))
                  : LayoutBuilder(  // ⭐ 추가
                      builder: (context, constraints) {  // ⭐ 추가
                        // ⭐ 화면 크기에 따라 열 개수 조정
                        final width = constraints.maxWidth;
                        final crossAxisCount = width < 300 ? 4 : width < 400 ? 5 : 6;
                        
                        return GridView.builder(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(  // ⭐ const 제거
                            crossAxisCount: crossAxisCount,  // ⭐ 반응형
                            mainAxisSpacing: 8,
                            crossAxisSpacing: 8,
                          ),
                      itemCount: _filteredIcons.length,
                      itemBuilder: (context, index) {
                        final iconItem = _filteredIcons[index];
                        final isSelected = _selectedIcon == iconItem.icon;
                        
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedIcon = iconItem.icon;
                              _selectedIconColor = iconItem.isMaterial ? Colors.white : null;
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected ? FormatHelper.parseColor(_selectedBackgroundColor) : Colors.grey[200],
                              border: Border.all(
                                color: isSelected ? Colors.blue : Colors.grey[300]!,
                                width: isSelected ? 2 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: iconItem.isMaterial
                                  ? Icon(
                                      iconItem.icon as IconData,
                                      color: isSelected 
                                          ? (_selectedIconColor ?? Colors.white)  // ✅ 선택된 색상 적용
                                          : Colors.grey[700],
                                      size: 28,
                                    )
                                  : Text(
                                      iconItem.icon.toString(),
                                      style: const TextStyle(fontSize: 28),
                                    ),
                            ),
                          ),
                        );  // ⭐ InkWell 닫기
                      },  // ⭐ itemBuilder 닫기
                    );  // ⭐ GridView.builder 닫기
                  },  // ⭐ LayoutBuilder의 builder 닫기
                ),  // ⭐ LayoutBuilder 닫기
              ),  // ⭐ Expanded 닫기
            
            // ✅ Material 아이콘 색상 선택 (Material 아이콘일 때만)
            if (_selectedIcon != null && _selectedIcon is IconData) ...[
              const SizedBox(height: 12),
              const Text('아이콘 색상', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _predefinedColors.map((colorHex) {
                  final isSelected = _selectedIconColor != null && 
                                    '#${_selectedIconColor!.value.toRadixString(16).padLeft(8, '0').substring(2)}' == colorHex;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedIconColor = FormatHelper.parseColor(colorHex);
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: FormatHelper.parseColor(colorHex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.black : Colors.grey[300]!,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                    ),
                  );
                }).toList(),
              ),
            ],
            
            // 배경색 선택
            if (_selectedIcon != null) ...[
              const SizedBox(height: 12),
              const Text('배경색', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _predefinedColors.map((colorHex) {
                  final isSelected = _selectedBackgroundColor == colorHex;
                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedBackgroundColor = colorHex;
                      });
                    },
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: FormatHelper.parseColor(colorHex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.black : Colors.grey[300]!,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 16) : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _selectedIcon == null
              ? null
              : () {
                  String iconString;
                  if (_selectedIcon is IconData) {
                    iconString = 'material:${_selectedIcon.codePoint}';
                  } else {
                    iconString = _selectedIcon.toString();
                  }
                  
                  String? colorHex;
                  if (_selectedIconColor != null) {
                    colorHex = '#${_selectedIconColor!.value.toRadixString(16).padLeft(8, '0').substring(2)}';
                  }
                  
                  Navigator.pop(context, {
                    'icon': iconString,
                    'iconColor': colorHex,
                    'backgroundColor': _selectedBackgroundColor,
                  });
                },
          child: const Text('선택'),
        ),
      ],
    );
  }
}