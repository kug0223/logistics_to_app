import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/core/business_work_type_model.dart';
import '../../models/core/business_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/pickers/icon_picker_dialog.dart';
import '../../widgets/work_type_icon.dart';
import '../../utils/toast_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';  // ⭐ 추가

/// 업무 유형 관리 화면
class WorkTypeManagementScreen extends StatefulWidget {
  const WorkTypeManagementScreen({super.key});

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

  @override
  void initState() {
    super.initState();
    _loadMyBusinesses();
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

  /// 업무 유형 추가 다이얼로그
  Future<void> _showAddDialog() async {
    if (_selectedBusiness == null) {
      ToastHelper.showWarning('사업장을 먼저 선택해주세요');
      return;
    }

    // 1. 아이콘 선택
    final iconResult = await IconPickerDialog.show(context: context);
    
    if (iconResult == null) return;

    // 2. 이름 입력
    final nameController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('업무 유형 정보'),
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
        );
      },
    );

    // 3. Firestore에 저장
    if (confirmed == true && nameController.text.trim().isNotEmpty) {
      final success = await _firestoreService.addBusinessWorkType(
        businessId: _selectedBusiness!.id,
        name: nameController.text.trim(),
        icon: iconResult['icon'],
        color: iconResult['iconColor'] ?? '#FFFFFF',
        backgroundColor: iconResult['backgroundColor'],
      );
      
      if (success != null) {
        _loadWorkTypes();
      }
    }
  }

  /// 업무 유형 수정 다이얼로그
  Future<void> _showEditDialog(BusinessWorkTypeModel workType) async {
    if (_selectedBusiness == null) return;

    // 1. 아이콘 선택
    final iconResult = await IconPickerDialog.show(
      context: context,
      initialIcon: workType.icon,
      initialBackgroundColor: workType.backgroundColor,
    );
    
    if (iconResult == null) return;

    // 2. 이름 입력
    final nameController = TextEditingController(text: workType.name);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('업무 유형 수정'),
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
              child: const Text('수정'),
            ),
          ],
        );
      },
    );

    // 3. Firestore 업데이트
    if (confirmed == true && nameController.text.trim().isNotEmpty) {
      final success = await _firestoreService.updateBusinessWorkType(
        businessId: _selectedBusiness!.id,
        workTypeId: workType.id,
        name: nameController.text.trim(),
        icon: iconResult['icon'],
        color: iconResult['iconColor'],
        backgroundColor: iconResult['backgroundColor'],
      );
      
      if (success) {
        _loadWorkTypes();
      }
    }
  }

  /// 삭제 확인 다이얼로그
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

  /// 순서 위로 이동
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

  /// 순서 아래로 이동
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
        backgroundColor: Theme.of(context).primaryColor,
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

  /// 사업장 선택 드롭다운
  Widget _buildBusinessSelector() {
    if (_myBusinesses.length == 1) {
      return Container(
        padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
        color: Theme.of(context).primaryColor.withOpacity(0.1),
        child: Row(
          children: [
            Icon(Icons.business, color: Theme.of(context).primaryColor),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
            Expanded(
              child: Text(
                _selectedBusiness?.name ?? '',
                style: ResponsiveHelper.subtitleStyle(  // ⭐ 변경
                  context,
                  color: Theme.of(context).primaryColor,
                ).copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
      color: Theme.of(context).primaryColor.withOpacity(0.1),
      child: DropdownButtonFormField<BusinessModel>(
        initialValue: _selectedBusiness,
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

  /// 사업장 없음 상태
  Widget _buildNoBusinessState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.business_outlined, 
            size: ResponsiveHelper.iconSize(context, 80),  // ⭐ 변경
            color: Theme.of(context).disabledColor,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
          Text(
            '등록된 사업장이 없습니다',
            style: ResponsiveHelper.titleStyle(  // ⭐ 변경
              context,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  /// 업무 유형 없음 상태
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.work_outline, 
            size: ResponsiveHelper.iconSize(context, 80),  // ⭐ 변경
            color: Theme.of(context).disabledColor,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
          Text(
            '등록된 업무 유형이 없습니다',
            style: ResponsiveHelper.titleStyle(  // ⭐ 변경
              context,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
          Text(
            '상단의 + 버튼을 눌러 업무 유형을 추가하세요',
            style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
              context,
              color: Theme.of(context).disabledColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 업무 유형 리스트
  Widget _buildWorkTypeList() {
    return ListView.builder(
      padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
      itemCount: _workTypes.length,
      itemBuilder: (context, index) {
        final workType = _workTypes[index];
        final isFirst = index == 0;
        final isLast = index == _workTypes.length - 1;

        return Card(
          margin: EdgeInsets.only(  // ⭐ const 제거
            bottom: ResponsiveHelper.spacing(context, 12),  // ⭐ 변경
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(  // ⭐ const 제거
              horizontal: ResponsiveHelper.spacing(context, 16),  // ⭐ 변경
              vertical: ResponsiveHelper.spacing(context, 8),  // ⭐ 변경
            ),
            // ✅ 아이콘 (공통 위젯 사용)
            leading: Container(
              width: ResponsiveHelper.iconSize(context, 48),  // ⭐ 변경
              height: ResponsiveHelper.iconSize(context, 48),  // ⭐ 변경
              decoration: BoxDecoration(
                color: FormatHelper.parseColor(workType.backgroundColor),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: WorkTypeIcon.build(
                  workType, 
                  size: ResponsiveHelper.iconSize(context, 24),  // ⭐ 변경
                ),
              ),
            ),
            // 이름 및 순서
            title: Text(
              workType.name,
              style: ResponsiveHelper.subtitleStyle(context),  // ⭐ 변경
            ),
            subtitle: Text(
              '순서: ${index + 1}',
              style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                context,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            // 관리 버튼들
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 위로 이동
                IconButton(
                  icon: Icon(
                    Icons.arrow_upward,
                    color: isFirst 
                        ? Theme.of(context).disabledColor 
                        : Theme.of(context).primaryColor,
                  ),
                  onPressed: isFirst ? null : () => _moveUp(index),
                  tooltip: '위로',
                ),
                // 아래로 이동
                IconButton(
                  icon: Icon(
                    Icons.arrow_downward,
                    color: isLast 
                        ? Theme.of(context).disabledColor 
                        : Theme.of(context).primaryColor,
                  ),
                  onPressed: isLast ? null : () => _moveDown(index),
                  tooltip: '아래로',
                ),
                // 수정
                IconButton(
                  icon: Icon(Icons.edit, color: Colors.orange),
                  onPressed: () => _showEditDialog(workType),
                  tooltip: '수정',
                ),
                // 삭제
                IconButton(
                  icon: Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _confirmDelete(workType),
                  tooltip: '삭제',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}