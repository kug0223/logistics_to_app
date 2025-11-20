import 'package:flutter/material.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';

/// 🎨 세련된 아이콘 아이템 클래스
class IconItem {
  final IconData icon;
  final String label;
  final List<String> keywords;
  final String category;
  
  IconItem({
    required this.icon,
    required this.label,
    required this.keywords,
    required this.category,
  });
}

/// ✨ 세련된 아이콘 선택 다이얼로그
class IconPickerDialog {
  /// 아이콘 선택 다이얼로그 표시
  static Future<Map<String, dynamic>?> show({
    required BuildContext context,
    String? initialIcon,
    String? initialIconColor,
    String? initialBackgroundColor,
  }) async {
    final theme = Theme.of(context);
    
    return await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => _IconPickerWidget(
        theme: theme,
        initialIcon: initialIcon,
        initialIconColor: initialIconColor,
        initialBackgroundColor: initialBackgroundColor,
      ),
    );
  }

  /// 🎯 세련된 Material Icons 컬렉션 (호환성 개선)
  static List<IconItem> getAllIcons() {
    return [
      // ========== 📦 물류/배송 카테고리 ==========
      IconItem(icon: Icons.inventory_2, label: '재고관리', keywords: ['inventory', '재고', '창고'], category: '물류/배송'),
      IconItem(icon: Icons.warehouse, label: '창고', keywords: ['warehouse', '창고', '보관'], category: '물류/배송'),
      IconItem(icon: Icons.local_shipping, label: '배송', keywords: ['shipping', '배송', '트럭'], category: '물류/배송'),
      IconItem(icon: Icons.arrow_downward, label: '입고', keywords: ['move', 'down', '입고'], category: '물류/배송'),
      IconItem(icon: Icons.arrow_upward, label: '출고', keywords: ['move', 'up', '출고'], category: '물류/배송'),
      IconItem(icon: Icons.category, label: '분류', keywords: ['category', '분류', '카테고리'], category: '물류/배송'),
      IconItem(icon: Icons.qr_code_scanner, label: 'QR스캔', keywords: ['qr', '스캔', 'barcode'], category: '물류/배송'),
      IconItem(icon: Icons.qr_code, label: 'QR코드', keywords: ['qr', 'code', '코드'], category: '물류/배송'),
      IconItem(icon: Icons.assignment_turned_in, label: '검수완료', keywords: ['check', '검수', '완료'], category: '물류/배송'),
      IconItem(icon: Icons.checklist, label: '체크리스트', keywords: ['checklist', '목록', '체크'], category: '물류/배송'),
      IconItem(icon: Icons.list_alt, label: '목록', keywords: ['list', '목록', '리스트'], category: '물류/배송'),
      IconItem(icon: Icons.fact_check, label: '검사', keywords: ['fact', 'check', '검사'], category: '물류/배송'),
      IconItem(icon: Icons.production_quantity_limits, label: '수량제한', keywords: ['quantity', '수량'], category: '물류/배송'),
      IconItem(icon: Icons.precision_manufacturing, label: '제조', keywords: ['manufacturing', '제조'], category: '물류/배송'),
      IconItem(icon: Icons.settings_input_component, label: '컴포넌트', keywords: ['component', '부품'], category: '물류/배송'),
      IconItem(icon: Icons.agriculture, label: '농업', keywords: ['agriculture', '농업'], category: '물류/배송'),
      IconItem(icon: Icons.fire_truck, label: '트럭', keywords: ['truck', '트럭'], category: '물류/배송'),
      IconItem(icon: Icons.airport_shuttle, label: '셔틀', keywords: ['shuttle', '셔틀'], category: '물류/배송'),
      IconItem(icon: Icons.delivery_dining, label: '배달', keywords: ['delivery', '배달'], category: '물류/배송'),
      IconItem(icon: Icons.home_work, label: '작업장', keywords: ['work', '작업장', '진열'], category: '물류/배송'),
      
      // ========== 🍕 음식/음료 카테고리 ==========
      IconItem(icon: Icons.restaurant, label: '식당', keywords: ['restaurant', '식당', '음식'], category: '음식/음료'),
      IconItem(icon: Icons.local_cafe, label: '카페', keywords: ['cafe', '카페', '커피'], category: '음식/음료'),
      IconItem(icon: Icons.coffee, label: '커피', keywords: ['coffee', '커피'], category: '음식/음료'),
      IconItem(icon: Icons.local_pizza, label: '피자', keywords: ['pizza', '피자'], category: '음식/음료'),
      IconItem(icon: Icons.fastfood, label: '패스트푸드', keywords: ['fastfood', '햄버거'], category: '음식/음료'),
      IconItem(icon: Icons.ramen_dining, label: '라면', keywords: ['ramen', '라면', '국수'], category: '음식/음료'),
      IconItem(icon: Icons.lunch_dining, label: '점심', keywords: ['lunch', '점심', '식사'], category: '음식/음료'),
      IconItem(icon: Icons.dinner_dining, label: '저녁', keywords: ['dinner', '저녁'], category: '음식/음료'),
      IconItem(icon: Icons.breakfast_dining, label: '아침', keywords: ['breakfast', '아침'], category: '음식/음료'),
      IconItem(icon: Icons.brunch_dining, label: '브런치', keywords: ['brunch', '브런치'], category: '음식/음료'),
      IconItem(icon: Icons.liquor, label: '주류', keywords: ['liquor', '술', '주류'], category: '음식/음료'),
      IconItem(icon: Icons.local_bar, label: '바', keywords: ['bar', '바', '술집'], category: '음식/음료'),
      IconItem(icon: Icons.icecream, label: '아이스크림', keywords: ['icecream', '아이스크림'], category: '음식/음료'),
      IconItem(icon: Icons.cake, label: '케이크', keywords: ['cake', '케이크', '디저트'], category: '음식/음료'),
      IconItem(icon: Icons.cookie, label: '쿠키', keywords: ['cookie', '쿠키'], category: '음식/음료'),
      IconItem(icon: Icons.bakery_dining, label: '베이커리', keywords: ['bakery', '빵', '베이커리'], category: '음식/음료'),
      IconItem(icon: Icons.takeout_dining, label: '테이크아웃', keywords: ['takeout', '포장'], category: '음식/음료'),
      IconItem(icon: Icons.dining, label: '식사', keywords: ['dining', '식사'], category: '음식/음료'),
      IconItem(icon: Icons.kitchen, label: '주방', keywords: ['kitchen', '주방'], category: '음식/음료'),
      IconItem(icon: Icons.egg_alt, label: '계란', keywords: ['egg', '계란'], category: '음식/음료'),
      
      // ========== 🧹 청소/관리 카테고리 ==========
      IconItem(icon: Icons.cleaning_services, label: '청소', keywords: ['cleaning', '청소'], category: '청소/관리'),
      IconItem(icon: Icons.sanitizer, label: '소독', keywords: ['sanitizer', '소독', '살균'], category: '청소/관리'),
      IconItem(icon: Icons.clean_hands, label: '손세척', keywords: ['clean', 'hands', '손세척'], category: '청소/관리'),
      IconItem(icon: Icons.shower, label: '샤워', keywords: ['shower', '샤워'], category: '청소/관리'),
      IconItem(icon: Icons.bathtub, label: '욕조', keywords: ['bathtub', '욕조'], category: '청소/관리'),
      IconItem(icon: Icons.wash, label: '세탁', keywords: ['wash', '세탁', '빨래'], category: '청소/관리'),
      IconItem(icon: Icons.dry_cleaning, label: '드라이클리닝', keywords: ['dry', 'cleaning', '드라이'], category: '청소/관리'),
      IconItem(icon: Icons.local_laundry_service, label: '세탁소', keywords: ['laundry', '세탁소'], category: '청소/관리'),
      IconItem(icon: Icons.soap, label: '비누', keywords: ['soap', '비누'], category: '청소/관리'),
      IconItem(icon: Icons.water_drop, label: '물방울', keywords: ['water', '물'], category: '청소/관리'),
      IconItem(icon: Icons.waves, label: '물결', keywords: ['waves', '물결'], category: '청소/관리'),
      IconItem(icon: Icons.delete_sweep, label: '청소', keywords: ['sweep', '청소'], category: '청소/관리'),
      IconItem(icon: Icons.recycling, label: '재활용', keywords: ['recycle', '재활용'], category: '청소/관리'),
      IconItem(icon: Icons.eco, label: '친환경', keywords: ['eco', '친환경'], category: '청소/관리'),
      IconItem(icon: Icons.delete, label: '삭제', keywords: ['delete', '삭제', '쓰레기'], category: '청소/관리'),
      IconItem(icon: Icons.restore_from_trash, label: '복원', keywords: ['restore', '복원'], category: '청소/관리'),
      IconItem(icon: Icons.cleaning_services, label: '청소도구', keywords: ['clean', '청소도구'], category: '청소/관리'),
      IconItem(icon: Icons.hvac, label: '환기', keywords: ['hvac', '환기'], category: '청소/관리'),
      IconItem(icon: Icons.air, label: '공기', keywords: ['air', '공기'], category: '청소/관리'),
      IconItem(icon: Icons.window, label: '창문', keywords: ['window', '창문'], category: '청소/관리'),
      
      // ========== 🔧 도구/작업 카테고리 ==========
      IconItem(icon: Icons.construction, label: '건설', keywords: ['construction', '건설', '공사'], category: '도구/작업'),
      IconItem(icon: Icons.handyman, label: '수리공', keywords: ['handyman', '수리공'], category: '도구/작업'),
      IconItem(icon: Icons.build, label: '제작', keywords: ['build', '제작', '만들기'], category: '도구/작업'),
      IconItem(icon: Icons.carpenter, label: '목수', keywords: ['carpenter', '목수'], category: '도구/작업'),
      IconItem(icon: Icons.home_repair_service, label: '수리', keywords: ['repair', '수리'], category: '도구/작업'),
      IconItem(icon: Icons.plumbing, label: '배관', keywords: ['plumbing', '배관'], category: '도구/작업'),
      IconItem(icon: Icons.electrical_services, label: '전기', keywords: ['electrical', '전기'], category: '도구/작업'),
      IconItem(icon: Icons.engineering, label: '엔지니어링', keywords: ['engineering', '엔지니어링'], category: '도구/작업'),
      IconItem(icon: Icons.architecture, label: '건축', keywords: ['architecture', '건축'], category: '도구/작업'),
      IconItem(icon: Icons.design_services, label: '디자인', keywords: ['design', '디자인'], category: '도구/작업'),
      IconItem(icon: Icons.hardware, label: '하드웨어', keywords: ['hardware', '하드웨어'], category: '도구/작업'),
      IconItem(icon: Icons.settings, label: '설정', keywords: ['settings', '설정'], category: '도구/작업'),
      IconItem(icon: Icons.tune, label: '조정', keywords: ['tune', '조정'], category: '도구/작업'),
      IconItem(icon: Icons.power, label: '전원', keywords: ['power', '전원'], category: '도구/작업'),
      IconItem(icon: Icons.lightbulb, label: '전구', keywords: ['lightbulb', '전구'], category: '도구/작업'),
      IconItem(icon: Icons.roofing, label: '지붕', keywords: ['roofing', '지붕'], category: '도구/작업'),
      IconItem(icon: Icons.foundation, label: '기초', keywords: ['foundation', '기초'], category: '도구/작업'),
      IconItem(icon: Icons.fence, label: '울타리', keywords: ['fence', '울타리'], category: '도구/작업'),
      IconItem(icon: Icons.stairs, label: '계단', keywords: ['stairs', '계단'], category: '도구/작업'),
      IconItem(icon: Icons.meeting_room, label: '문', keywords: ['door', '문'], category: '도구/작업'),
      
      // ========== 📝 사무/문서 카테고리 ==========
      IconItem(icon: Icons.assignment, label: '과제', keywords: ['assignment', '과제', '업무'], category: '사무/문서'),
      IconItem(icon: Icons.description, label: '문서', keywords: ['description', '문서', '설명'], category: '사무/문서'),
      IconItem(icon: Icons.article, label: '기사', keywords: ['article', '기사', '글'], category: '사무/문서'),
      IconItem(icon: Icons.note, label: '노트', keywords: ['note', '노트', '메모'], category: '사무/문서'),
      IconItem(icon: Icons.sticky_note_2, label: '포스트잇', keywords: ['sticky', '포스트잇'], category: '사무/문서'),
      IconItem(icon: Icons.edit_note, label: '편집', keywords: ['edit', '편집'], category: '사무/문서'),
      IconItem(icon: Icons.folder, label: '폴더', keywords: ['folder', '폴더'], category: '사무/문서'),
      IconItem(icon: Icons.folder_open, label: '열린폴더', keywords: ['folder', 'open', '열림'], category: '사무/문서'),
      IconItem(icon: Icons.insert_drive_file, label: '파일', keywords: ['file', '파일'], category: '사무/문서'),
      IconItem(icon: Icons.file_copy, label: '복사', keywords: ['copy', '복사'], category: '사무/문서'),
      IconItem(icon: Icons.summarize, label: '요약', keywords: ['summarize', '요약'], category: '사무/문서'),
      IconItem(icon: Icons.receipt_long, label: '영수증', keywords: ['receipt', '영수증'], category: '사무/문서'),
      IconItem(icon: Icons.request_quote, label: '견적', keywords: ['quote', '견적'], category: '사무/문서'),
      IconItem(icon: Icons.print, label: '인쇄', keywords: ['print', '인쇄'], category: '사무/문서'),
      IconItem(icon: Icons.scanner, label: '스캔', keywords: ['scanner', '스캔'], category: '사무/문서'),
      IconItem(icon: Icons.create, label: '작성', keywords: ['create', '작성', '쓰기'], category: '사무/문서'),
      IconItem(icon: Icons.edit, label: '수정', keywords: ['edit', '수정'], category: '사무/문서'),
      IconItem(icon: Icons.draw, label: '그리기', keywords: ['draw', '그리기'], category: '사무/문서'),
      IconItem(icon: Icons.text_fields, label: '텍스트', keywords: ['text', '텍스트'], category: '사무/문서'),
      IconItem(icon: Icons.format_list_bulleted, label: '목록', keywords: ['list', '목록'], category: '사무/문서'),
      
      // ========== ⏰ 시간/일정 카테고리 ==========
      IconItem(icon: Icons.schedule, label: '스케줄', keywords: ['schedule', '스케줄', '일정'], category: '시간/일정'),
      IconItem(icon: Icons.access_time, label: '시간', keywords: ['time', '시간'], category: '시간/일정'),
      IconItem(icon: Icons.alarm, label: '알람', keywords: ['alarm', '알람'], category: '시간/일정'),
      IconItem(icon: Icons.timer, label: '타이머', keywords: ['timer', '타이머'], category: '시간/일정'),
      IconItem(icon: Icons.today, label: '오늘', keywords: ['today', '오늘'], category: '시간/일정'),
      IconItem(icon: Icons.event, label: '이벤트', keywords: ['event', '이벤트'], category: '시간/일정'),
      IconItem(icon: Icons.calendar_month, label: '달력', keywords: ['calendar', '달력'], category: '시간/일정'),
      IconItem(icon: Icons.calendar_today, label: '오늘날짜', keywords: ['calendar', '오늘'], category: '시간/일정'),
      IconItem(icon: Icons.date_range, label: '기간', keywords: ['date', 'range', '기간'], category: '시간/일정'),
      IconItem(icon: Icons.watch_later, label: '나중에', keywords: ['watch', 'later', '나중'], category: '시간/일정'),
      IconItem(icon: Icons.update, label: '업데이트', keywords: ['update', '업데이트'], category: '시간/일정'),
      IconItem(icon: Icons.history, label: '기록', keywords: ['history', '기록', '히스토리'], category: '시간/일정'),
      IconItem(icon: Icons.pending, label: '대기중', keywords: ['pending', '대기'], category: '시간/일정'),
      IconItem(icon: Icons.hourglass_bottom, label: '모래시계', keywords: ['hourglass', '모래시계'], category: '시간/일정'),
      IconItem(icon: Icons.timelapse, label: '타임랩스', keywords: ['timelapse', '타임랩스'], category: '시간/일정'),
      
      // ========== 👥 사람/팀 카테고리 ==========
      IconItem(icon: Icons.person, label: '사람', keywords: ['person', '사람', '개인'], category: '사람/팀'),
      IconItem(icon: Icons.group, label: '그룹', keywords: ['group', '그룹', '팀'], category: '사람/팀'),
      IconItem(icon: Icons.people, label: '사람들', keywords: ['people', '사람들'], category: '사람/팀'),
      IconItem(icon: Icons.groups, label: '여러그룹', keywords: ['groups', '그룹들'], category: '사람/팀'),
      IconItem(icon: Icons.supervisor_account, label: '관리자', keywords: ['supervisor', '관리자'], category: '사람/팀'),
      IconItem(icon: Icons.badge, label: '배지', keywords: ['badge', '배지', '신분증'], category: '사람/팀'),
      IconItem(icon: Icons.contact_page, label: '연락처', keywords: ['contact', '연락처'], category: '사람/팀'),
      IconItem(icon: Icons.account_circle, label: '계정', keywords: ['account', '계정'], category: '사람/팀'),
      IconItem(icon: Icons.manage_accounts, label: '계정관리', keywords: ['manage', '관리'], category: '사람/팀'),
      IconItem(icon: Icons.admin_panel_settings, label: '관리자패널', keywords: ['admin', '관리자'], category: '사람/팀'),
      
      // ========== ✅ 상태/액션 카테고리 ==========
      IconItem(icon: Icons.check_circle, label: '완료', keywords: ['check', '완료', '체크'], category: '상태/액션'),
      IconItem(icon: Icons.verified, label: '검증완료', keywords: ['verified', '검증'], category: '상태/액션'),
      IconItem(icon: Icons.task_alt, label: '작업완료', keywords: ['task', '작업'], category: '상태/액션'),
      IconItem(icon: Icons.done_all, label: '모두완료', keywords: ['done', '완료'], category: '상태/액션'),
      IconItem(icon: Icons.pending_actions, label: '대기중', keywords: ['pending', '대기'], category: '상태/액션'),
      IconItem(icon: Icons.error, label: '에러', keywords: ['error', '에러', '오류'], category: '상태/액션'),
      IconItem(icon: Icons.warning, label: '경고', keywords: ['warning', '경고'], category: '상태/액션'),
      IconItem(icon: Icons.info, label: '정보', keywords: ['info', '정보'], category: '상태/액션'),
      IconItem(icon: Icons.help, label: '도움말', keywords: ['help', '도움말'], category: '상태/액션'),
      IconItem(icon: Icons.cancel, label: '취소', keywords: ['cancel', '취소'], category: '상태/액션'),
      IconItem(icon: Icons.close, label: '닫기', keywords: ['close', '닫기'], category: '상태/액션'),
      IconItem(icon: Icons.add, label: '추가', keywords: ['add', '추가', '더하기'], category: '상태/액션'),
      IconItem(icon: Icons.remove, label: '제거', keywords: ['remove', '제거', '빼기'], category: '상태/액션'),
      IconItem(icon: Icons.refresh, label: '새로고침', keywords: ['refresh', '새로고침'], category: '상태/액션'),
      IconItem(icon: Icons.sync, label: '동기화', keywords: ['sync', '동기화'], category: '상태/액션'),
    ];
  }
}

/// ✨ 세련된 아이콘 선택 위젯
class _IconPickerWidget extends StatefulWidget {
  final ThemeData theme;
  final String? initialIcon;
  final String? initialIconColor;
  final String? initialBackgroundColor;

  const _IconPickerWidget({
    required this.theme,
    this.initialIcon,
    this.initialIconColor,
    this.initialBackgroundColor,
  });

  @override
  State<_IconPickerWidget> createState() => _IconPickerWidgetState();
}

class _IconPickerWidgetState extends State<_IconPickerWidget> {
  late List<IconItem> _allIcons;
  List<IconItem> _filteredIcons = [];
  IconData? _selectedIcon;
  Color _selectedIconColor = Colors.white;
  String _selectedBackgroundColor = '#2196F3';
  String _selectedCategory = '전체';
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _categoryScrollController = ScrollController(); // ⭐ 추가

  final List<String> _categories = [
    '전체',
    '물류/배송',
    '음식/음료',
    '청소/관리',
    '도구/작업',
    '사무/문서',
    '시간/일정',
    '사람/팀',
    '상태/액션',
  ];

  final List<String> _predefinedColors = [
    '#FFFFFF', // 흰색
    '#000000', // 검정
    '#F44336', // 빨강
    '#2196F3', // 파랑
    '#4CAF50', // 초록
    '#FFC107', // 노랑
    '#9C27B0', // 보라
    '#FF9800', // 주황
  ];

  @override
  void initState() {
    super.initState();
    _allIcons = IconPickerDialog.getAllIcons();
    _selectedBackgroundColor = widget.initialBackgroundColor ?? '#2196F3';
    
    if (widget.initialIconColor != null) {
      _selectedIconColor = FormatHelper.parseColor(widget.initialIconColor!);
    }
    
    if (widget.initialIcon != null && widget.initialIcon!.startsWith('material:')) {
      final codePoint = int.tryParse(widget.initialIcon!.substring(9));
      if (codePoint != null) {
        _selectedIcon = IconData(codePoint, fontFamily: 'MaterialIcons');
      }
    }
    
    _filterIcons();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _categoryScrollController.dispose(); // ⭐ 추가
    super.dispose();
  }

  void _filterIcons() {
    setState(() {
      var filtered = _allIcons;
      
      // 카테고리 필터
      if (_selectedCategory != '전체') {
        filtered = filtered.where((icon) => icon.category == _selectedCategory).toList();
      }
      
      // 검색 필터
      if (_searchController.text.isNotEmpty) {
        final query = _searchController.text.toLowerCase();
        filtered = filtered.where((icon) {
          return icon.label.toLowerCase().contains(query) ||
                 icon.keywords.any((keyword) => keyword.toLowerCase().contains(query));
        }).toList();
      }
      
      _filteredIcons = filtered;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 600,
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ✨ 세련된 헤더
            _buildHeader(),
            
            // ✨ 메인 컨텐츠 (스크롤 가능)
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    // ✨ 검색바
                    _buildSearchBar(),
                    
                    // ✨ 색상 설정 (선택시에만 표시) - 상단으로 이동!
                    if (_selectedIcon != null) _buildColorSettings(),
                    
                    // ✨ 카테고리 탭
                    _buildCategoryTabs(),
                    
                    // ✨ 아이콘 그리드
                    _buildIconGrid(),
                  ],
                ),
              ),
            ),
            
            // ✨ 액션 버튼
            _buildActionButtons(),
          ],
        ),
      ),
    );
  }

  /// ✨ 세련된 헤더
  Widget _buildHeader() {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            widget.theme.primaryColor,
            widget.theme.primaryColor.withOpacity(0.8),
          ],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(24),
          topRight: Radius.circular(24),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.auto_awesome,
              color: Colors.white,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '아이콘 선택',
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '${_filteredIcons.length}개 아이콘',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: Colors.white.withOpacity(0.9),
                  ),
                ),
              ],
            ),
          ),
          Material(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
            child: InkWell(
              onTap: () => Navigator.pop(context),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                child: Icon(
                  Icons.close,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 20),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 검색바
  Widget _buildSearchBar() {
    return Padding(
      padding: ResponsiveHelper.cardPadding(context),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: '아이콘 검색...',
          prefixIcon: Icon(Icons.search, color: widget.theme.primaryColor),
          suffixIcon: _searchController.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    _filterIcons();
                  },
                )
              : null,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.grey[100],
        ),
        onChanged: (_) => _filterIcons(),
      ),
    );
  }

  /// ✨ 카테고리 탭 (화살표 버튼 추가)
  Widget _buildCategoryTabs() {
    return Container(
      height: 56,
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      child: Row(
        children: [
          // ⭐ 왼쪽 화살표
          IconButton(
            icon: Icon(Icons.chevron_left, color: widget.theme.primaryColor),
            onPressed: () {
              _categoryScrollController.animateTo(
                _categoryScrollController.offset - 150,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
          // 카테고리 목록
          Expanded(
            child: ListView.builder(
              controller: _categoryScrollController,
              scrollDirection: Axis.horizontal,
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final category = _categories[index];
                final isSelected = _selectedCategory == category;
                
                return Padding(
                  padding: EdgeInsets.only(
                    right: ResponsiveHelper.spacing(context, 8),
                  ),
                  child: Material(
                    color: isSelected
                        ? widget.theme.primaryColor
                        : Colors.grey[200],
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedCategory = category;
                          _filterIcons();
                        });
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 16),
                          vertical: ResponsiveHelper.spacing(context, 8),
                        ),
                        child: Text(
                          category,
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: isSelected ? Colors.white : Colors.grey[700],
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          // ⭐ 오른쪽 화살표
          IconButton(
            icon: Icon(Icons.chevron_right, color: widget.theme.primaryColor),
            onPressed: () {
              _categoryScrollController.animateTo(
                _categoryScrollController.offset + 150,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              );
            },
          ),
        ],
      ),
    );
  }

  /// ✨ 아이콘 그리드 (반응형 복구)
  Widget _buildIconGrid() {
    if (_filteredIcons.isEmpty) {
      return Container(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.search_off,
                size: ResponsiveHelper.iconSize(context, 64),
                color: Colors.grey[400],
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Text(
                '검색 결과가 없습니다',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    // ⭐ 그리드 높이 계산 (반응형)
    final iconSize = ResponsiveHelper.iconSize(context, 56);
    final gapSize = ResponsiveHelper.spacing(context, 8);
    final labelHeight = 30.0;
    final rows = (_filteredIcons.length / 5).ceil();
    final itemHeight = iconSize + gapSize + labelHeight;
    final mainSpacing = ResponsiveHelper.spacing(context, 8);
    final gridHeight = (rows * itemHeight) + (rows - 1) * mainSpacing + 16.0;
    
    return Container(
      height: gridHeight,
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: ResponsiveHelper.spacing(context, 8),
          crossAxisSpacing: ResponsiveHelper.spacing(context, 8),
          mainAxisExtent: itemHeight,
        ),
        itemCount: _filteredIcons.length,
        itemBuilder: (context, index) {
          final iconItem = _filteredIcons[index];
          final isSelected = _selectedIcon == iconItem.icon;
          
          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedIcon = iconItem.icon;
              });
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 아이콘
                Container(
                  width: ResponsiveHelper.iconSize(context, 56),
                  height: ResponsiveHelper.iconSize(context, 56),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? LinearGradient(
                            colors: [
                              FormatHelper.parseColor(_selectedBackgroundColor),
                              FormatHelper.parseColor(_selectedBackgroundColor).withOpacity(0.8),
                            ],
                          )
                        : null,
                    color: isSelected ? null : Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? widget.theme.primaryColor
                          : Colors.grey[300]!,
                      width: isSelected ? 2 : 1,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: widget.theme.primaryColor.withOpacity(0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ]
                        : null,
                  ),
                  child: Icon(
                    iconItem.icon,
                    color: isSelected ? _selectedIconColor : Colors.grey[700],
                    size: ResponsiveHelper.iconSize(context, 28),
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                // 라벨 (고정 높이)
                SizedBox(
                  height: 30,
                  child: Center(
                    child: Text(
                      iconItem.label,
                      style: ResponsiveHelper.tinyStyle(context).copyWith(
                        color: isSelected ? widget.theme.primaryColor : Colors.grey[600],
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: ResponsiveHelper.getFontSize(context, 10),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// ✨ 색상 설정 (ExpansionTile - 접을 수 있음)
  Widget _buildColorSettings() {
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ExpansionTile(
        initiallyExpanded: false, // ⭐ 기본 접힘
        title: Row(
          children: [
            Icon(
              Icons.palette,
              color: widget.theme.primaryColor,
              size: ResponsiveHelper.iconSize(context, 20),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '색상 설정',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        children: [
          Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 아이콘 색상
                Text(
                  '아이콘 색상',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Wrap(
                  spacing: ResponsiveHelper.spacing(context, 10),
                  runSpacing: ResponsiveHelper.spacing(context, 8),
                  children: _predefinedColors.map((colorHex) {
                    final color = FormatHelper.parseColor(colorHex);
                    final isSelected = _selectedIconColor.value == color.value;
                    
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedIconColor = color;
                        });
                      },
                      child: Container(
                        width: ResponsiveHelper.iconSize(context, 36),
                        height: ResponsiveHelper.iconSize(context, 36),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? widget.theme.primaryColor : Colors.grey[400]!,
                            width: isSelected ? 3 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: widget.theme.primaryColor.withOpacity(0.3),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check,
                                color: colorHex == '#FFFFFF' ? Colors.black : Colors.white,
                                size: ResponsiveHelper.iconSize(context, 18),
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                
                // 배경색
                Text(
                  '배경색',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Wrap(
                  spacing: ResponsiveHelper.spacing(context, 10),
                  runSpacing: ResponsiveHelper.spacing(context, 8),
                  children: _predefinedColors.map((colorHex) {
                    final color = FormatHelper.parseColor(colorHex);
                    final isSelected = _selectedBackgroundColor == colorHex;
                    
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedBackgroundColor = colorHex;
                        });
                      },
                      child: Container(
                        width: ResponsiveHelper.iconSize(context, 36),
                        height: ResponsiveHelper.iconSize(context, 36),
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected ? widget.theme.primaryColor : Colors.grey[400]!,
                            width: isSelected ? 3 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: widget.theme.primaryColor.withOpacity(0.3),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSelected
                            ? Icon(
                                Icons.check,
                                color: colorHex == '#FFFFFF' ? Colors.black : Colors.white,
                                size: ResponsiveHelper.iconSize(context, 18),
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 액션 버튼
  Widget _buildActionButtons() {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 16),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                '취소',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    widget.theme.primaryColor,
                    widget.theme.primaryColor.withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: widget.theme.primaryColor.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _selectedIcon == null
                      ? null
                      : () {
                          final iconString = 'material:${_selectedIcon!.codePoint}';
                          final colorHex = '#${_selectedIconColor.value.toRadixString(16).padLeft(8, '0').substring(2)}';
                          
                          Navigator.pop(context, {
                            'icon': iconString,
                            'iconColor': colorHex,
                            'backgroundColor': _selectedBackgroundColor,
                          });
                        },
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 16),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle,
                          color: Colors.white,
                          size: ResponsiveHelper.iconSize(context, 20),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Text(
                          '선택 완료',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}