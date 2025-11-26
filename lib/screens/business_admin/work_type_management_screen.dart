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
import '../../utils/navigation_helper.dart';
import 'work_type_detail_screen.dart';
import '../../utils/dialog_helper.dart';
import '../../widgets/dialogs/styled_dialog.dart';

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
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StyledDialog(
        title: '업무 유형 추가',
        subtitle: '새로운 업무 유형을 등록합니다',
        icon: Icons.add_circle_outline,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StyledDialogTextField(
              controller: nameController,
              labelText: '업무 유형 이름',
              hintText: '예: 피킹, 패킹, 검수',
              prefixIcon: Icons.label,
            ),
          ],
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context, false),
          ),
          StyledDialogButton.primary(
            text: '추가',
            onPressed: () {
              if (nameController.text.trim().isEmpty) {
                ToastHelper.showWarning('업무 유형 이름을 입력해주세요');
                return;
              }
              Navigator.pop(context, true);
            },
          ),
        ],
      ),
    );

    // 3. Firestore에 저장
    if (confirmed == true && nameController.text.trim().isNotEmpty) {
      final newId = await _firestoreService.addBusinessWorkType(
        businessId: _selectedBusiness!.id,
        name: nameController.text.trim(),
        icon: iconResult['icon'],
        color: iconResult['iconColor'] ?? '#FFFFFF',
        backgroundColor: iconResult['backgroundColor'],
      );
      
      if (newId != null) {
        // 목록 새로고침
        await _loadWorkTypes();
        
        // 새로 생성된 업무유형 찾기
        final newWorkType = _workTypes.firstWhere(
          (wt) => wt.id == newId,
          orElse: () => BusinessWorkTypeModel(
            id: newId,
            businessId: _selectedBusiness!.id,
            name: nameController.text.trim(),
            icon: iconResult['icon'],
            color: iconResult['iconColor'] ?? '#FFFFFF',
            backgroundColor: iconResult['backgroundColor'],
            displayOrder: _workTypes.length,
            createdAt: DateTime.now(),
          ),
        );
        
        // 상세 정보 입력 여부 확인
        if (mounted) {
          final goToDetail = await showDialog<bool>(
            context: context,
            builder: (context) => StyledDialog(
              title: '등록 완료!',
              subtitle: '업무유형이 성공적으로 등록되었습니다',
              icon: Icons.check_circle,
              headerColor: Colors.green,
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  StyledDialogInfoCard.info(
                    '상세 정보(설명, 이미지 등)를 추가하면 지원자에게 더 많은 정보를 제공할 수 있어요!',
                  ),
                ],
              ),
              actions: [
                StyledDialogButton.cancel(
                  text: '나중에',
                  onPressed: () => Navigator.pop(context, false),
                ),
                StyledDialogButton.primary(
                  text: '상세 정보 입력',
                  onPressed: () => Navigator.pop(context, true),
                ),
              ],
            ),
          );
          
          if (goToDetail == true) {
            _openDetailScreen(newWorkType);
          }
        }
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
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StyledDialog(
        title: '업무 유형 수정',
        subtitle: '업무 유형 정보를 수정합니다',
        icon: Icons.edit,
        headerColor: Colors.orange,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            StyledDialogTextField(
              controller: nameController,
              labelText: '업무 유형 이름',
              hintText: '예: 피킹, 패킹, 검수',
              prefixIcon: Icons.label,
            ),
          ],
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context, false),
          ),
          StyledDialogButton.primary(
            text: '수정',
            backgroundColor: Colors.orange,
            onPressed: () {
              if (nameController.text.trim().isEmpty) {
                ToastHelper.showWarning('업무 유형 이름을 입력해주세요');
                return;
              }
              Navigator.pop(context, true);
            },
          ),
        ],
      ),
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
                        width: ResponsiveHelper.spacing(context, 48),
                        height: ResponsiveHelper.spacing(context, 48),
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(12),
                          image: _selectedBusiness?.mainImageUrl != null
                              ? DecorationImage(
                                  image: NetworkImage(_selectedBusiness!.mainImageUrl!),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        ),
                        child: _selectedBusiness?.mainImageUrl == null
                            ? Icon(
                                Icons.business,
                                color: Theme.of(context).primaryColor,
                                size: ResponsiveHelper.iconSize(context, 24),
                              )
                            : null,
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
                        workType.name,
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
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _selectedBusiness?.mainImageUrl != null
                  ? Image.network(
                      _selectedBusiness!.mainImageUrl!,
                      width: ResponsiveHelper.spacing(context, 48),
                      height: ResponsiveHelper.spacing(context, 48),
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: ResponsiveHelper.spacing(context, 48),
                          height: ResponsiveHelper.spacing(context, 48),
                          decoration: BoxDecoration(
                            color: theme.primaryColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.business,
                            color: theme.primaryColor,
                            size: ResponsiveHelper.iconSize(context, 24),
                          ),
                        );
                      },
                    )
                  : Container(
                      width: ResponsiveHelper.spacing(context, 48),
                      height: ResponsiveHelper.spacing(context, 48),
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
        initialValue: _selectedBusiness,
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

  /// ✨ 세련된 업무 유형 리스트 (더보기 메뉴 버전)
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
            onTap: () => _openDetailScreen(workType),
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
            subtitle: Padding(
              padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 4)),
              child: Row(
                children: [
                  Container(
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
                      style: ResponsiveHelper.tinyStyle(
                        context,
                        color: theme.primaryColor,
                      ).copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),
            // ✨ 더보기 메뉴
            trailing: PopupMenuButton<String>(
              icon: Icon(
                Icons.more_vert,
                color: theme.primaryColor,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              onSelected: (value) => _handleMenuAction(value, workType, index, isFirst, isLast),
              itemBuilder: (context) => [
                // 위로 이동
                PopupMenuItem(
                  value: 'moveUp',
                  enabled: !isFirst,
                  child: Row(
                    children: [
                      Icon(
                        Icons.arrow_upward,
                        size: ResponsiveHelper.iconSize(context, 20),
                        color: isFirst ? Colors.grey : theme.primaryColor,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Text(
                        '위로 이동',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: isFirst ? Colors.grey : null,
                        ),
                      ),
                    ],
                  ),
                ),
                // 아래로 이동
                PopupMenuItem(
                  value: 'moveDown',
                  enabled: !isLast,
                  child: Row(
                    children: [
                      Icon(
                        Icons.arrow_downward,
                        size: ResponsiveHelper.iconSize(context, 20),
                        color: isLast ? Colors.grey : theme.primaryColor,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Text(
                        '아래로 이동',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: isLast ? Colors.grey : null,
                        ),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                // 상세 정보
                PopupMenuItem(
                  value: 'detail',
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: ResponsiveHelper.iconSize(context, 20),
                        color: Colors.blue,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Text('상세 정보', style: ResponsiveHelper.bodyStyle(context)),
                    ],
                  ),
                ),
                // 수정
                PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(
                        Icons.edit,
                        size: ResponsiveHelper.iconSize(context, 20),
                        color: Colors.orange,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Text('수정', style: ResponsiveHelper.bodyStyle(context)),
                    ],
                  ),
                ),
                // 삭제
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(
                        Icons.delete,
                        size: ResponsiveHelper.iconSize(context, 20),
                        color: Colors.red,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Text(
                        '삭제',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: Colors.red,
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
  }
  /// 메뉴 액션 처리
  void _handleMenuAction(
      String action,
      BusinessWorkTypeModel workType,
      int index,
      bool isFirst,
      bool isLast,
    ) {
      switch (action) {
        case 'moveUp':
          if (!isFirst) _moveUp(index);
          break;
        case 'moveDown':
          if (!isLast) _moveDown(index);
          break;
        case 'detail':
          _openDetailScreen(workType);
          break;
        case 'edit':
          _showEditDialog(workType);
          break;
        case 'delete':
          _confirmDelete(workType);
          break;
      }
    }

  /// 상세 화면으로 이동
  Future<void> _openDetailScreen(BusinessWorkTypeModel workType) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WorkTypeDetailScreen(workType: workType),
      ),
    );
    
    // 변경사항이 있으면 목록 새로고침
    if (result == true) {
      _loadWorkTypes();
    }
  }
  
}