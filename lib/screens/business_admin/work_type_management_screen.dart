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
import '../../utils/responsive_helper.dart';

/// ✨ 세련된 업무 유형 관리 화면
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

  /// ✨ 세련된 업무 유형 추가 다이얼로그
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
    final theme = Theme.of(context);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 400,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ✨ 헤더
                Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        theme.primaryColor,
                        theme.primaryColor.withOpacity(0.8),
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
                          Icons.add_circle_outline,
                          color: Colors.white,
                          size: ResponsiveHelper.iconSize(context, 24),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                      Expanded(
                        child: Text(
                          '업무 유형 추가',
                          style: ResponsiveHelper.titleStyle(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ✨ 컨텐츠
                Padding(
                  padding: ResponsiveHelper.cardPadding(context),
                  child: TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: '업무 유형 이름',
                      hintText: '예: 피킹, 패킹, 검수',
                      prefixIcon: Icon(Icons.label, color: theme.primaryColor),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    autofocus: true,
                  ),
                ),
                // ✨ 버튼
                Padding(
                  padding: ResponsiveHelper.cardPadding(context),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: ResponsiveHelper.spacing(context, 16),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text('취소'),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.primaryColor,
                                theme.primaryColor.withOpacity(0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: theme.primaryColor.withOpacity(0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.pop(context, true),
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
                                      '추가',
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
                ),
              ],
            ),
          ),
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

  /// ✨ 세련된 업무 유형 수정 다이얼로그
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
    final theme = Theme.of(context);
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 400,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ✨ 헤더
                Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.orange,
                        Colors.orange.withOpacity(0.8),
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
                          Icons.edit,
                          color: Colors.white,
                          size: ResponsiveHelper.iconSize(context, 24),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                      Expanded(
                        child: Text(
                          '업무 유형 수정',
                          style: ResponsiveHelper.titleStyle(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ✨ 컨텐츠
                Padding(
                  padding: ResponsiveHelper.cardPadding(context),
                  child: TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: '업무 유형 이름',
                      hintText: '예: 피킹, 패킹, 검수',
                      prefixIcon: Icon(Icons.label, color: Colors.orange),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[50],
                    ),
                    autofocus: true,
                  ),
                ),
                // ✨ 버튼
                Padding(
                  padding: ResponsiveHelper.cardPadding(context),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: ResponsiveHelper.spacing(context, 16),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text('취소'),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        flex: 2,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.orange,
                                Colors.orange.withOpacity(0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.orange.withOpacity(0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.pop(context, true),
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
                                      '수정',
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
                ),
              ],
            ),
          ),
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

  /// ✨ 세련된 삭제 확인 다이얼로그
  Future<void> _confirmDelete(BusinessWorkTypeModel workType) async {
    if (_selectedBusiness == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: 400,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ✨ 헤더
                Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.red,
                        Colors.red.withOpacity(0.8),
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
                          Icons.warning_rounded,
                          color: Colors.white,
                          size: ResponsiveHelper.iconSize(context, 24),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                      Expanded(
                        child: Text(
                          '업무 유형 삭제',
                          style: ResponsiveHelper.titleStyle(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // ✨ 컨텐츠
                Padding(
                  padding: ResponsiveHelper.cardPadding(context),
                  child: Column(
                    children: [
                      Icon(
                        Icons.delete_forever,
                        size: ResponsiveHelper.iconSize(context, 64),
                        color: Colors.red.withOpacity(0.5),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      Text(
                        '정말로 삭제하시겠습니까?',
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        '${workType.name}',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: Theme.of(context).primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        '삭제된 데이터는 복구할 수 없습니다',
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                // ✨ 버튼
                Padding(
                  padding: ResponsiveHelper.cardPadding(context),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(context, false),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                              vertical: ResponsiveHelper.spacing(context, 16),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text('취소'),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.red,
                                Colors.red.withOpacity(0.8),
                              ],
                            ),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.red.withOpacity(0.4),
                                blurRadius: 8,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => Navigator.pop(context, true),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.spacing(context, 16),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.delete,
                                      color: Colors.white,
                                      size: ResponsiveHelper.iconSize(context, 20),
                                    ),
                                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                    Text(
                                      '삭제',
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
                ),
              ],
            ),
          ),
        );
      },
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
    final theme = Theme.of(context);
    
    return Scaffold(
      // ✨ 깔끔한 단색 AppBar
      appBar: AppBar(
        title: Text('업무 유형 관리'),
        actions: [
          IconButton(
            icon: Icon(Icons.add_circle_outline),
            onPressed: _selectedBusiness != null ? _showAddDialog : null,
            tooltip: '업무 유형 추가',
          ),
        ],
      ),
      // ✨ 연한 회색 배경 (카드와 대비)
      body: Container(
        color: Colors.grey[50],
        child: _isLoadingBusinesses
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
      ),
    );
  }

  /// ✨ 세련된 사업장 선택기
  Widget _buildBusinessSelector() {
    final theme = Theme.of(context);
    
    if (_myBusinesses.length == 1) {
      return Container(
        margin: ResponsiveHelper.cardPadding(context),
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.primaryColor.withOpacity(0.1),
              theme.primaryColor.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: theme.primaryColor.withOpacity(0.3),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.business,
                color: theme.primaryColor,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 16)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '현재 사업장',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  Text(
                    _selectedBusiness?.name ?? '',
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(
                      color: theme.primaryColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: ResponsiveHelper.cardPadding(context),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonFormField<BusinessModel>(
        value: _selectedBusiness,
        decoration: InputDecoration(
          labelText: '사업장 선택',
          prefixIcon: Icon(Icons.business, color: theme.primaryColor),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.grey[50],
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

  /// ✨ 세련된 사업장 없음 상태
  Widget _buildNoBusinessState() {
    final theme = Theme.of(context);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.business_outlined,
              size: ResponsiveHelper.iconSize(context, 80),
              color: theme.primaryColor.withOpacity(0.5),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          Text(
            '등록된 사업장이 없습니다',
            style: ResponsiveHelper.titleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '사업장을 먼저 등록해주세요',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 세련된 업무 유형 없음 상태
  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.work_outline,
              size: ResponsiveHelper.iconSize(context, 80),
              color: theme.primaryColor.withOpacity(0.5),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          Text(
            '등록된 업무 유형이 없습니다',
            style: ResponsiveHelper.titleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '상단의 + 버튼을 눌러 업무 유형을 추가하세요',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: theme.textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 세련된 업무 유형 리스트
  Widget _buildWorkTypeList() {
    final theme = Theme.of(context);
    
    return ListView.builder(
      padding: ResponsiveHelper.cardPadding(context),
      itemCount: _workTypes.length,
      itemBuilder: (context, index) {
        final workType = _workTypes[index];
        final isFirst = index == 0;
        final isLast = index == _workTypes.length - 1;

        return Container(
          margin: EdgeInsets.only(
            bottom: ResponsiveHelper.spacing(context, 16),
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.15),
                blurRadius: 15,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 20),
              vertical: ResponsiveHelper.spacing(context, 12),
            ),
            // ✨ 아이콘
            leading: Container(
              width: ResponsiveHelper.iconSize(context, 56),
              height: ResponsiveHelper.iconSize(context, 56),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    FormatHelper.parseColor(workType.backgroundColor ?? '#2196F3'),
                    FormatHelper.parseColor(workType.backgroundColor ?? '#2196F3').withOpacity(0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: FormatHelper.parseColor(workType.backgroundColor ?? '#2196F3').withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: WorkTypeIcon.build(
                  workType,
                  size: ResponsiveHelper.iconSize(context, 28),
                ),
              ),
            ),
            // ✨ 이름 및 순서
            title: Text(
              workType.name,
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Container(
              margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 4)),
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8),
                vertical: ResponsiveHelper.spacing(context, 4),
              ),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '순서: ${index + 1}',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: theme.primaryColor,
                ).copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            // ✨ 관리 버튼들
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 위로 이동
                _buildActionButton(
                  icon: Icons.arrow_upward,
                  color: isFirst ? Colors.grey : theme.primaryColor,
                  onPressed: isFirst ? null : () => _moveUp(index),
                  tooltip: '위로',
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                // 아래로 이동
                _buildActionButton(
                  icon: Icons.arrow_downward,
                  color: isLast ? Colors.grey : theme.primaryColor,
                  onPressed: isLast ? null : () => _moveDown(index),
                  tooltip: '아래로',
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                // 수정
                _buildActionButton(
                  icon: Icons.edit,
                  color: Colors.orange,
                  onPressed: () => _showEditDialog(workType),
                  tooltip: '수정',
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                // 삭제
                _buildActionButton(
                  icon: Icons.delete,
                  color: Colors.red,
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

  /// ✨ 세련된 액션 버튼
  Widget _buildActionButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onPressed,
    required String tooltip,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: onPressed != null ? color.withOpacity(0.1) : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: IconButton(
        icon: Icon(icon, size: ResponsiveHelper.iconSize(context, 20)),
        color: onPressed != null ? color : Colors.grey,
        onPressed: onPressed,
        tooltip: tooltip,
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
        constraints: BoxConstraints(
          minWidth: ResponsiveHelper.iconSize(context, 36),
          minHeight: ResponsiveHelper.iconSize(context, 36),
        ),
      ),
    );
  }
}