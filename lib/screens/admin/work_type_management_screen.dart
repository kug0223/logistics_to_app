import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/business_work_type_model.dart';
import '../../models/business_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';

/// 아이콘 아이템 클래스
class IconItem {
  final dynamic icon;
  final List<String> keywords;
  final String category;  // ✅ 카테고리 추가
  final bool isMaterial;
  final bool isPopular;
  
  IconItem({
    required this.icon,
    required this.keywords,
    required this.category,  // ✅ 필수
    this.isMaterial = false,
    this.isPopular = false,
  });
}

/// 업무 유형 관리 화면
class WorkTypeManagementScreen extends StatefulWidget {
  const WorkTypeManagementScreen({Key? key}) : super(key: key);

  @override
  State<WorkTypeManagementScreen> createState() => _WorkTypeManagementScreenState();
}

class _WorkTypeManagementScreenState extends State<WorkTypeManagementScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<BusinessModel> _myBusinesses = [];
  BusinessModel? _selectedBusiness;
  
  List<BusinessWorkTypeModel> _workTypes = [];
  bool _isLoading = true;
  bool _isLoadingBusinesses = true;

  late final List<IconItem> _allIcons;

  @override
  void initState() {
    super.initState();
    _initializeIcons();
    _loadMyBusinesses();
  }

  void _initializeIcons() {
    _allIcons = [
      // ========== 물류/배송 ==========
      IconItem(icon: '📦', keywords: ['박스', '상자', '포장', '패킹', '택배', '입고'], category: '물류/배송', isPopular: true),
      IconItem(icon: '🚚', keywords: ['배송', '트럭', '운송', '출고', '배차'], category: '물류/배송', isPopular: true),
      IconItem(icon: '📋', keywords: ['목록', '리스트', '서류', '문서'], category: '물류/배송', isPopular: true),
      IconItem(icon: '✅', keywords: ['확인', '완료', '체크', '검수', '승인'], category: '물류/배송', isPopular: true),
      IconItem(icon: Icons.inventory, keywords: ['재고', '피킹', '인벤토리', '선별', '입고'], category: '물류/배송', isMaterial: true, isPopular: true),
      IconItem(icon: Icons.local_shipping, keywords: ['배송', '상차', '하차', '운송', '출고'], category: '물류/배송', isMaterial: true, isPopular: true),
      IconItem(icon: Icons.fact_check, keywords: ['검수', '확인', '검사', '점검', '체크'], category: '물류/배송', isMaterial: true, isPopular: true),
      IconItem(icon: Icons.category, keywords: ['분류', '카테고리', '정리', '분배'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.warehouse, keywords: ['창고', '입고', '보관', '저장'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.qr_code_scanner, keywords: ['스캔', '바코드', 'QR', '스캐너'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.scale, keywords: ['계량', '무게', '저울', '측정'], category: '물류/배송', isMaterial: true),
      IconItem(icon: '🏭', keywords: ['공장', '제조', '생산', '입고'], category: '물류/배송'),
      IconItem(icon: '🏗️', keywords: ['건설', '공사', '작업'], category: '물류/배송'),
      IconItem(icon: '📮', keywords: ['우편', '메일', '배송'], category: '물류/배송'),
      IconItem(icon: '📥', keywords: ['받기', '입고', '수령'], category: '물류/배송'),
      IconItem(icon: '📤', keywords: ['보내기', '출고', '발송'], category: '물류/배송'),
      IconItem(icon: '🚛', keywords: ['트럭', '화물', '대형'], category: '물류/배송'),
      IconItem(icon: '🚐', keywords: ['밴', '소형', '배송'], category: '물류/배송'),
      IconItem(icon: '✈️', keywords: ['비행기', '항공', '특송'], category: '물류/배송'),
      IconItem(icon: '🚢', keywords: ['배', '선박', '해운'], category: '물류/배송'),
      IconItem(icon: Icons.inventory_2, keywords: ['재고', '박스', '물품'], category: '물류/배송', isMaterial: true),
      IconItem(icon: Icons.forklift, keywords: ['지게차', '운반', '하역'], category: '물류/배송', isMaterial: true),
      
      // ========== 음식/카페 ==========
      IconItem(icon: '☕', keywords: ['커피', '카페', '음료', '카페인'], category: '음식/카페', isPopular: true),
      IconItem(icon: '🍔', keywords: ['햄버거', '버거', '패스트푸드', '음식'], category: '음식/카페', isPopular: true),
      IconItem(icon: '🍕', keywords: ['피자', '음식', '배달'], category: '음식/카페'),
      IconItem(icon: '🍰', keywords: ['케이크', '디저트', '베이커리', '제과'], category: '음식/카페'),
      IconItem(icon: '🥤', keywords: ['음료', '드링크', '주스', '음료수'], category: '음식/카페'),
      IconItem(icon: '🍜', keywords: ['면', '라면', '국수', '요리'], category: '음식/카페'),
      IconItem(icon: '🍱', keywords: ['도시락', '식사', '음식', '포장'], category: '음식/카페'),
      IconItem(icon: '🍲', keywords: ['요리', '조리', '주방', '식사'], category: '음식/카페'),
      IconItem(icon: '🧁', keywords: ['머핀', '컵케이크', '베이커리'], category: '음식/카페'),
      IconItem(icon: '🍩', keywords: ['도넛', '디저트', '빵'], category: '음식/카페'),
      IconItem(icon: '🍪', keywords: ['쿠키', '과자', '간식'], category: '음식/카페'),
      IconItem(icon: '🥐', keywords: ['크루아상', '빵', '베이커리'], category: '음식/카페'),
      IconItem(icon: '🍞', keywords: ['빵', '식빵', '토스트'], category: '음식/카페'),
      IconItem(icon: '🧃', keywords: ['주스', '음료', '박스'], category: '음식/카페'),
      IconItem(icon: '🍵', keywords: ['차', '티', '음료'], category: '음식/카페'),
      IconItem(icon: Icons.restaurant, keywords: ['식당', '레스토랑', '음식점', '요리'], category: '음식/카페', isMaterial: true),
      IconItem(icon: Icons.local_cafe, keywords: ['카페', '커피', '음료'], category: '음식/카페', isMaterial: true),
      IconItem(icon: Icons.bakery_dining, keywords: ['베이커리', '빵', '제과'], category: '음식/카페', isMaterial: true),
      IconItem(icon: Icons.lunch_dining, keywords: ['점심', '식사', '도시락'], category: '음식/카페', isMaterial: true),
      IconItem(icon: Icons.local_pizza, keywords: ['피자', '배달'], category: '음식/카페', isMaterial: true),
      
      // ========== 판매/서비스 ==========
      IconItem(icon: '🛒', keywords: ['장바구니', '쇼핑', '구매', '카트'], category: '판매/서비스'),
      IconItem(icon: '💰', keywords: ['돈', '금액', '매출', '수익', '계산'], category: '판매/서비스'),
      IconItem(icon: '💳', keywords: ['카드', '결제', '페이', '계산'], category: '판매/서비스'),
      IconItem(icon: '🏷️', keywords: ['태그', '라벨', '가격표', '할인'], category: '판매/서비스'),
      IconItem(icon: '📊', keywords: ['그래프', '통계', '분석', '데이터', '재고관리'], category: '판매/서비스', isPopular: true),
      IconItem(icon: '💼', keywords: ['비즈니스', '사무', '업무'], category: '판매/서비스'),
      IconItem(icon: Icons.shopping_cart, keywords: ['쇼핑', '구매', '장바구니'], category: '판매/서비스', isMaterial: true),
      IconItem(icon: Icons.point_of_sale, keywords: ['계산', 'POS', '포스', '결제'], category: '판매/서비스', isMaterial: true),
      IconItem(icon: Icons.receipt_long, keywords: ['영수증', '계산서', '영수'], category: '판매/서비스', isMaterial: true),
      IconItem(icon: Icons.store, keywords: ['가게', '매장', '상점'], category: '판매/서비스', isMaterial: true),
      IconItem(icon: Icons.sell, keywords: ['판매', '세일', '할인'], category: '판매/서비스', isMaterial: true),
      IconItem(icon: Icons.shopping_bag, keywords: ['쇼핑백', '구매', '포장'], category: '판매/서비스', isMaterial: true),
      IconItem(icon: Icons.payment, keywords: ['결제', '페이', '카드'], category: '판매/서비스', isMaterial: true),
      
      // ========== 청소/관리 ==========
      IconItem(icon: '🧹', keywords: ['청소', '빗자루', '정리', '클린'], category: '청소/관리', isPopular: true),
      IconItem(icon: '🧽', keywords: ['청소', '수세미', '닦기'], category: '청소/관리'),
      IconItem(icon: '🧴', keywords: ['세제', '청소', '용품'], category: '청소/관리'),
      IconItem(icon: '🗑️', keywords: ['쓰레기', '폐기', '버리기'], category: '청소/관리'),
      IconItem(icon: '♻️', keywords: ['재활용', '분리수거', '환경'], category: '청소/관리'),
      IconItem(icon: Icons.cleaning_services, keywords: ['청소', '관리', '정리'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.delete, keywords: ['삭제', '쓰레기', '폐기'], category: '청소/관리', isMaterial: true),
      IconItem(icon: Icons.wash, keywords: ['세탁', '빨래', '청소'], category: '청소/관리', isMaterial: true),
      
      // ========== 사무/행정 ==========
      IconItem(icon: '📝', keywords: ['메모', '기록', '문서', '작성'], category: '사무/행정'),
      IconItem(icon: '📄', keywords: ['서류', '문서', '파일'], category: '사무/행정'),
      IconItem(icon: '📁', keywords: ['폴더', '파일', '문서'], category: '사무/행정'),
      IconItem(icon: '✏️', keywords: ['쓰기', '작성', '펜', '연필'], category: '사무/행정'),
      IconItem(icon: Icons.assignment, keywords: ['업무', '과제', '작업', '문서'], category: '사무/행정', isMaterial: true),
      IconItem(icon: Icons.computer, keywords: ['컴퓨터', 'PC', '작업'], category: '사무/행정', isMaterial: true),
      IconItem(icon: Icons.print, keywords: ['프린트', '인쇄', '출력'], category: '사무/행정', isMaterial: true),
      IconItem(icon: Icons.email, keywords: ['이메일', '메일', '편지'], category: '사무/행정', isMaterial: true),
      IconItem(icon: Icons.event, keywords: ['일정', '캘린더', '스케줄'], category: '사무/행정', isMaterial: true),
      
      // ========== 작업/제조 ==========
      IconItem(icon: '🔧', keywords: ['수리', '정비', '도구', '렌치'], category: '작업/제조'),
      IconItem(icon: '⚙️', keywords: ['설정', '기계', '톱니', '작업'], category: '작업/제조'),
      IconItem(icon: '🔨', keywords: ['망치', '제작', '공구'], category: '작업/제조'),
      IconItem(icon: Icons.build, keywords: ['제작', '수리', '도구'], category: '작업/제조', isMaterial: true),
      IconItem(icon: Icons.construction, keywords: ['건설', '공사', '작업'], category: '작업/제조', isMaterial: true),
      IconItem(icon: Icons.handyman, keywords: ['수리', '정비', '작업'], category: '작업/제조', isMaterial: true),
      IconItem(icon: Icons.precision_manufacturing, keywords: ['제조', '생산', '공장'], category: '작업/제조', isMaterial: true),
      
      // ========== 기타 ==========
      IconItem(icon: '⭐', keywords: ['별', '중요', '추천', '즐겨찾기'], category: '기타'),
      IconItem(icon: '🎯', keywords: ['목표', '타겟', '달성'], category: '기타'),
      IconItem(icon: '💡', keywords: ['아이디어', '전구', '생각'], category: '기타'),
      IconItem(icon: '🔔', keywords: ['알림', '벨', '공지'], category: '기타'),
      IconItem(icon: '📞', keywords: ['전화', '콜', '통화'], category: '기타'),
      IconItem(icon: Icons.star, keywords: ['별', '즐겨찾기', '중요'], category: '기타', isMaterial: true),
      IconItem(icon: Icons.notifications, keywords: ['알림', '공지', '벨'], category: '기타', isMaterial: true),
      IconItem(icon: Icons.call, keywords: ['전화', '통화', '콜'], category: '기타', isMaterial: true),
      IconItem(icon: Icons.help, keywords: ['도움말', '질문', '헬프'], category: '기타', isMaterial: true),
      IconItem(icon: Icons.info, keywords: ['정보', '안내', '인포'], category: '기타', isMaterial: true),
    ];
  }

  Future<void> _loadMyBusinesses() async {
    setState(() => _isLoadingBusinesses = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }

      final businesses = await _firestoreService.getMyBusiness(uid);

      setState(() {
        _myBusinesses = businesses;
        if (_myBusinesses.isNotEmpty) {
          _selectedBusiness = _myBusinesses.first;
          _loadWorkTypes();
        } else {
          _isLoading = false;
        }
        _isLoadingBusinesses = false;
      });

      if (businesses.isEmpty) {
        ToastHelper.showInfo('등록된 사업장이 없습니다');
      }
    } catch (e) {
      print('❌ 사업장 목록 로드 실패: $e');
      setState(() {
        _isLoadingBusinesses = false;
        _isLoading = false;
      });
      ToastHelper.showError('사업장 목록을 불러올 수 없습니다');
    }
  }

  Future<void> _loadWorkTypes() async {
    if (_selectedBusiness == null) {
      setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final workTypes = await _firestoreService.getBusinessWorkTypes(_selectedBusiness!.id);
      
      setState(() {
        _workTypes = workTypes;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 업무 유형 로드 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('업무 유형을 불러올 수 없습니다');
    }
  }

  Future<void> _showAddDialog() async {
    if (_selectedBusiness == null) {
      ToastHelper.showWarning('사업장을 먼저 선택해주세요');
      return;
    }

    await showDialog(
      context: context,
      builder: (context) => _IconPickerDialog(
        allIcons: _allIcons,
        onSelected: (selectedIcon, iconColor, backgroundColor) async {
          final nameController = TextEditingController();
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('업무 유형 이름'),
              content: TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '이름',
                  hintText: '예: 피킹, 패킹',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('추가'),
                ),
              ],
            ),
          );

          if (confirmed == true && nameController.text.trim().isNotEmpty) {
            String iconString;
            if (selectedIcon is IconData) {
              iconString = 'material:${selectedIcon.codePoint}';
            } else {
              iconString = selectedIcon.toString();
            }
            String? colorHex;
            if (iconColor != null) {
              colorHex = '#${iconColor.value.toRadixString(16).padLeft(8, '0').substring(2)}';
            }

            final success = await _firestoreService.addBusinessWorkType(
              businessId: _selectedBusiness!.id,
              name: nameController.text.trim(),
              icon: iconString,
              color: colorHex ?? '#2196F3',  // ✅ 간단하게
              backgroundColor: backgroundColor,
            );
            if (success != null) {
              _loadWorkTypes();
            }
          }
        },
      ),
    );
  }

  Future<void> _showEditDialog(BusinessWorkTypeModel workType) async {
    if (_selectedBusiness == null) return;

    await showDialog(
      context: context,
      builder: (context) => _IconPickerDialog(
        allIcons: _allIcons,
        initialIcon: workType.icon,
        initialIconColor: workType.color,
        initialBackgroundColor: workType.backgroundColor,
        onSelected: (selectedIcon, iconColor, backgroundColor) async {
          final nameController = TextEditingController(text: workType.name);
          final confirmed = await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('업무 유형 수정'),
              content: TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: '이름',
                  border: OutlineInputBorder(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('취소'),
                ),
                ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('수정'),
                ),
              ],
            ),
          );

          if (confirmed == true && nameController.text.trim().isNotEmpty) {
            String iconString;
            if (selectedIcon is IconData) {
              iconString = 'material:${selectedIcon.codePoint}';
            } else {
              iconString = selectedIcon.toString();
            }

            String? colorHex;
            if (iconColor != null) {
              colorHex = '#${iconColor.value.toRadixString(16).padLeft(8, '0').substring(2)}';
            }

            final success = await _firestoreService.updateBusinessWorkType(
              businessId: _selectedBusiness!.id,
              workTypeId: workType.id,
              name: nameController.text.trim(),
              icon: iconString,
              color: colorHex,  // ✅ 간단하게
              backgroundColor: backgroundColor,
              showToast: true,
            );

            if (success) {
              _loadWorkTypes();
            }
          }
        },
      ),
    );
  }

  Future<void> _confirmDelete(BusinessWorkTypeModel workType) async {
    if (_selectedBusiness == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('업무 유형 삭제'),
        content: Text('${workType.name}을(를) 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await _firestoreService.deleteBusinessWorkType(
        businessId: _selectedBusiness!.id,
        workTypeId: workType.id,
      );

      if (success) {
        _loadWorkTypes();
      }
    }
  }

  Future<void> _moveUp(int index) async {
    if (index == 0 || _selectedBusiness == null) return;
    
    final current = _workTypes[index];
    final above = _workTypes[index - 1];
    final temp = current.displayOrder;
    
    await _firestoreService.updateBusinessWorkType(
      businessId: _selectedBusiness!.id,
      workTypeId: current.id,
      displayOrder: above.displayOrder,
      showToast: false,
    );
    
    await _firestoreService.updateBusinessWorkType(
      businessId: _selectedBusiness!.id,
      workTypeId: above.id,
      displayOrder: temp,
      showToast: false,
    );
    
    ToastHelper.showSuccess('순서가 변경되었습니다');
    _loadWorkTypes();
  }

  Future<void> _moveDown(int index) async {
    if (index >= _workTypes.length - 1 || _selectedBusiness == null) return;
    
    final current = _workTypes[index];
    final below = _workTypes[index + 1];
    final temp = current.displayOrder;
    
    await _firestoreService.updateBusinessWorkType(
      businessId: _selectedBusiness!.id,
      workTypeId: current.id,
      displayOrder: below.displayOrder,
      showToast: false,
    );
    
    await _firestoreService.updateBusinessWorkType(
      businessId: _selectedBusiness!.id,
      workTypeId: below.id,
      displayOrder: temp,
      showToast: false,
    );
    
    ToastHelper.showSuccess('순서가 변경되었습니다');
    _loadWorkTypes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('업무 유형 관리'),
        backgroundColor: Colors.blue[700],
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _selectedBusiness != null ? _showAddDialog : null,
            tooltip: '업무 유형 추가',
          ),
        ],
      ),
      body: _isLoadingBusinesses
          ? const LoadingWidget(message: '사업장 정보를 불러오는 중...')
          : _myBusinesses.isEmpty
              ? _buildNoBusinessState()
              : Column(
                  children: [
                    _buildBusinessSelector(),
                    Expanded(
                      child: _isLoading
                          ? const LoadingWidget(message: '업무 유형을 불러오는 중...')
                          : _workTypes.isEmpty
                              ? _buildEmptyState()
                              : _buildWorkTypeList(),
                    ),
                  ],
                ),
    );
  }

  Widget _buildBusinessSelector() {
    if (_myBusinesses.length == 1) {
      return Container(
        padding: const EdgeInsets.all(16),
        color: Colors.blue[50],
        child: Row(
          children: [
            Icon(Icons.business, color: Colors.blue[700]),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _selectedBusiness?.name ?? '',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[900],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.blue[50],
      child: DropdownButtonFormField<BusinessModel>(
        value: _selectedBusiness,
        decoration: InputDecoration(
          labelText: '사업장 선택',
          prefixIcon: const Icon(Icons.business),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: Colors.white,
        ),
        items: _myBusinesses.map((business) {
          return DropdownMenuItem(
            value: business,
            child: Text(business.name),
          );
        }).toList(),
        onChanged: (value) {
          if (value != null) {
            setState(() {
              _selectedBusiness = value;
            });
            _loadWorkTypes();
          }
        },
      ),
    );
  }

  Widget _buildNoBusinessState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.business_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '등록된 사업장이 없습니다',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.work_outline, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '등록된 업무 유형이 없습니다',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            '상단의 + 버튼을 눌러 업무 유형을 추가하세요',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkTypeList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _workTypes.length,
      itemBuilder: (context, index) {
        final workType = _workTypes[index];
        final isFirst = index == 0;
        final isLast = index == _workTypes.length - 1;
        
        // ✅ backgroundColor 사용 (color가 아님!)
        final bgColor = workType.backgroundColor != null && workType.backgroundColor!.isNotEmpty
            ? Color(int.parse(workType.backgroundColor!.replaceFirst('#', '0xFF')))
            : Colors.blue[700]!;

        Widget iconWidget;
        if (workType.icon.startsWith('material:')) {
          final codePoint = int.parse(workType.icon.split(':')[1]);
          
          // ✅ Material 아이콘의 색상 결정
          Color iconColor = Colors.white; // 기본은 흰색
          if (workType.color != null && workType.color!.isNotEmpty) {
            try {
              iconColor = Color(int.parse(workType.color!.replaceFirst('#', '0xFF')));
            } catch (e) {
              iconColor = Colors.white;
            }
          }
          
          iconWidget = Icon(
            IconData(codePoint, fontFamily: 'MaterialIcons'),
            size: 24,
            color: iconColor,
          );
        } else {
          iconWidget = Text(workType.icon, style: const TextStyle(fontSize: 24));
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: bgColor,  // ✅ 배경색 사용!
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: iconWidget,
            ),
            title: Text(
              workType.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            subtitle: Text('순서: ${workType.displayOrder + 1}'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_upward),
                  color: isFirst ? Colors.grey : Colors.blue,
                  onPressed: isFirst ? null : () => _moveUp(index),
                  tooltip: '위로',
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward),
                  color: isLast ? Colors.grey : Colors.blue,
                  onPressed: isLast ? null : () => _moveDown(index),
                  tooltip: '아래로',
                ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  onPressed: () => _showEditDialog(workType),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _confirmDelete(workType),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// ✅ 아이콘 선택 다이얼로그 (검색 + 카테고리 드롭다운)
class _IconPickerDialog extends StatefulWidget {
  final List<IconItem> allIcons;
  final String? initialIcon;
  final String? initialIconColor;
  final String? initialBackgroundColor;
  final Function(dynamic icon, Color? iconColor, String backgroundColor) onSelected;

  const _IconPickerDialog({
    required this.allIcons,
    this.initialIcon,
    this.initialIconColor, 
    this.initialBackgroundColor,
    required this.onSelected,
  });

  @override
  State<_IconPickerDialog> createState() => _IconPickerDialogState();
}

class _IconPickerDialogState extends State<_IconPickerDialog> {
  final TextEditingController _searchController = TextEditingController();
  List<IconItem> _filteredIcons = [];
  dynamic _selectedIcon;
  Color? _selectedIconColor;
  String _selectedBackgroundColor = '#2196F3';
  
  // ✅ 카테고리 관련
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

  final List<Color> _iconColors = [
    Colors.white,
    Colors.black,
    Colors.grey,
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.yellow.shade700,
    Colors.pink,
  ];

  final List<String> _backgroundColors = [
    '#2196F3', '#4CAF50', '#FF9800', '#F44336', '#9C27B0',
    '#00BCD4', '#795548', '#607D8B', '#E91E63', '#3F51B5',
  ];

  @override
  void initState() {
    super.initState();
    
    if (widget.initialIcon != null) {
      if (widget.initialIcon!.startsWith('material:')) {
        final codePoint = int.parse(widget.initialIcon!.split(':')[1]);
        _selectedIcon = IconData(codePoint, fontFamily: 'MaterialIcons');
        _selectedIconColor = Colors.white;
      } else {
        _selectedIcon = widget.initialIcon;
      }
    }
    
    if (widget.initialIconColor != null) {
      _selectedBackgroundColor = widget.initialIconColor!;
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
        // 검색어 없음 + 전체 선택 = 인기 아이콘만
        _filteredIcons = widget.allIcons.where((icon) => icon.isPopular).toList();
      } else if (query.isEmpty) {
        // 검색어 없음 + 특정 카테고리 = 해당 카테고리 전체
        _filteredIcons = widget.allIcons
            .where((icon) => icon.category == _selectedCategory)
            .toList();
      } else if (_selectedCategory == '전체 (인기)') {
        // 검색어 있음 + 전체 선택 = 전체에서 검색
        _filteredIcons = widget.allIcons.where((icon) {
          return icon.keywords.any((keyword) => keyword.contains(query));
        }).toList();
      } else {
        // 검색어 있음 + 특정 카테고리 = 해당 카테고리 내에서만 검색
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 12),
            
            // ✅ 카테고리 드롭다운
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: InputDecoration(
                labelText: '카테고리',
                prefixIcon: const Icon(Icons.category),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: _categories.map((category) {
                return DropdownMenuItem(
                  value: category,
                  child: Text(category),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedCategory = value;
                    _filterIcons();
                  });
                }
              },
              menuMaxHeight: 600,  // ✅ 최대 10개 정도 보이도록 높이 제한
            ),
            
            const SizedBox(height: 16),
            
            // 아이콘 그리드
            Expanded(
              child: _filteredIcons.isEmpty
                  ? Center(
                      child: Text(
                        '검색 결과가 없습니다',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  : GridView.builder(
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 5,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                      ),
                      itemCount: _filteredIcons.length,
                      itemBuilder: (context, index) {
                        final iconItem = _filteredIcons[index];
                        final isSelected = _selectedIcon == iconItem.icon;
                        
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _selectedIcon = iconItem.icon;
                              if (iconItem.isMaterial) {
                                _selectedIconColor = Colors.white;
                              } else {
                                _selectedIconColor = null;
                              }
                            });
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isSelected ? Colors.blue[100] : Colors.grey[200],
                              border: Border.all(
                                color: isSelected ? Colors.blue : Colors.grey[300]!,
                                width: isSelected ? 3 : 1,
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Center(
                              child: iconItem.isMaterial
                                  ? Icon(iconItem.icon as IconData, size: 28)
                                  : Text(iconItem.icon as String, style: const TextStyle(fontSize: 28)),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            
            const SizedBox(height: 16),
            
            // 선택된 아이콘 미리보기 + 색상 선택
            if (_selectedIcon != null) ...[
              const Divider(),
              const Text('선택된 아이콘', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 8),
              
              Container(
                width: 70,
                height: 70,
                decoration: BoxDecoration(
                  color: Color(int.parse(_selectedBackgroundColor.replaceFirst('#', '0xFF'))),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: _selectedIcon is IconData
                      ? Icon(_selectedIcon as IconData, size: 35, color: _selectedIconColor)
                      : Text(_selectedIcon as String, style: const TextStyle(fontSize: 35)),
                ),
              ),
              
              const SizedBox(height: 12),
              
              if (_selectedIcon is IconData) ...[
                const Text('아이콘 색상', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _iconColors.map((color) {
                    final isSelected = _selectedIconColor == color;
                    return InkWell(
                      onTap: () => setState(() => _selectedIconColor = color),
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: color,
                          border: Border.all(
                            color: isSelected ? Colors.black : Colors.grey[300]!,
                            width: isSelected ? 2 : 1,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: isSelected
                            ? Icon(Icons.check, 
                                color: color == Colors.white || color == Colors.yellow.shade700 
                                    ? Colors.black : Colors.white, 
                                size: 16)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 10),
              ],
              
              const Text('배경 색상', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _backgroundColors.map((colorHex) {
                  final isSelected = _selectedBackgroundColor == colorHex;
                  final color = Color(int.parse(colorHex.replaceFirst('#', '0xFF')));
                  return InkWell(
                    onTap: () => setState(() => _selectedBackgroundColor = colorHex),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: color,
                        border: Border.all(
                          color: isSelected ? Colors.black : Colors.grey[300]!,
                          width: isSelected ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(6),
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
                  Navigator.pop(context);
                  widget.onSelected(_selectedIcon, _selectedIconColor, _selectedBackgroundColor);
                },
          child: const Text('선택'),
        ),
      ],
    );
  }
}