import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/business_work_type_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';

/// 업무 유형 관리 화면
class WorkTypeManagementScreen extends StatefulWidget {
  const WorkTypeManagementScreen({Key? key}) : super(key: key);

  @override
  State<WorkTypeManagementScreen> createState() => _WorkTypeManagementScreenState();
}

class _WorkTypeManagementScreenState extends State<WorkTypeManagementScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<BusinessWorkTypeModel> _workTypes = [];
  bool _isLoading = true;
  String? _businessId;

  @override
  void initState() {
    super.initState();
    _loadWorkTypes();
  }

  /// 업무 유형 목록 로드
  Future<void> _loadWorkTypes() async {
    setState(() => _isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      _businessId = userProvider.currentUser?.businessId;

      if (_businessId == null) {
        ToastHelper.showError('사업장 정보를 찾을 수 없습니다');
        return;
      }

      final workTypes = await _firestoreService.getBusinessWorkTypes(_businessId!);
      
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
    final nameController = TextEditingController();
    String selectedIcon = '📦';
    String selectedColor = '#2196F3';

    final icons = ['📦', '📋', '🚚', '🏷️', '🏋️', '✅', '📝', '🔧', '⚙️', '📊'];
    final colors = [
      '#2196F3', // Blue
      '#4CAF50', // Green
      '#FF9800', // Orange
      '#F44336', // Red
      '#9C27B0', // Purple
      '#00BCD4', // Cyan
      '#FFEB3B', // Yellow
      '#795548', // Brown
    ];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('업무 유형 추가'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 이름 입력
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '업무 유형 이름',
                    hintText: '예: 피킹, 패킹',
                    border: OutlineInputBorder(),
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),

                // 아이콘 선택
                const Text('아이콘', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: icons.map((icon) {
                    final isSelected = icon == selectedIcon;
                    return InkWell(
                      onTap: () {
                        setDialogState(() {
                          selectedIcon = icon;
                        });
                      },
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected ? Colors.blue : Colors.grey[300]!,
                            width: isSelected ? 3 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(icon, style: const TextStyle(fontSize: 24)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),

                // 색상 선택
                const Text('색상', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: colors.map((colorCode) {
                    final color = Color(int.parse(colorCode.replaceFirst('#', '0xFF')));
                    final isSelected = colorCode == selectedColor;
                    return InkWell(
                      onTap: () {
                        setDialogState(() {
                          selectedColor = colorCode;
                        });
                      },
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: color,
                          border: Border.all(
                            color: isSelected ? Colors.black : Colors.grey[300]!,
                            width: isSelected ? 3 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ToastHelper.showWarning('업무 유형 이름을 입력하세요');
                  return;
                }

                Navigator.pop(context);

                final success = await _firestoreService.addBusinessWorkType(
                  businessId: _businessId!,
                  name: nameController.text.trim(),
                  icon: selectedIcon,
                  color: selectedColor,
                );

                if (success != null) {
                  _loadWorkTypes();
                }
              },
              child: const Text('추가'),
            ),
          ],
        ),
      ),
    );
  }

  /// 업무 유형 수정 다이얼로그
  Future<void> _showEditDialog(BusinessWorkTypeModel workType) async {
    final nameController = TextEditingController(text: workType.name);
    String selectedIcon = workType.icon;
    String selectedColor = workType.color;

    final icons = ['📦', '📋', '🚚', '🏷️', '🏋️', '✅', '📝', '🔧', '⚙️', '📊'];
    final colors = [
      '#2196F3', '#4CAF50', '#FF9800', '#F44336',
      '#9C27B0', '#00BCD4', '#FFEB3B', '#795548',
    ];

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('업무 유형 수정'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: '업무 유형 이름',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('아이콘', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: icons.map((icon) {
                    final isSelected = icon == selectedIcon;
                    return InkWell(
                      onTap: () => setDialogState(() => selectedIcon = icon),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: isSelected ? Colors.blue : Colors.grey[300]!,
                            width: isSelected ? 3 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(icon, style: const TextStyle(fontSize: 24)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text('색상', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: colors.map((colorCode) {
                    final color = Color(int.parse(colorCode.replaceFirst('#', '0xFF')));
                    final isSelected = colorCode == selectedColor;
                    return InkWell(
                      onTap: () => setDialogState(() => selectedColor = colorCode),
                      child: Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: color,
                          border: Border.all(
                            color: isSelected ? Colors.black : Colors.grey[300]!,
                            width: isSelected ? 3 : 1,
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: isSelected
                            ? const Icon(Icons.check, color: Colors.white)
                            : null,
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) {
                  ToastHelper.showWarning('업무 유형 이름을 입력하세요');
                  return;
                }

                Navigator.pop(context);

                final success = await _firestoreService.updateBusinessWorkType(
                  businessId: _businessId!,
                  workTypeId: workType.id,
                  name: nameController.text.trim(),
                  icon: selectedIcon,
                  color: selectedColor,
                );

                if (success) {
                  _loadWorkTypes();
                }
              },
              child: const Text('수정'),
            ),
          ],
        ),
      ),
    );
  }

  /// 업무 유형 삭제 확인
  Future<void> _confirmDelete(BusinessWorkTypeModel workType) async {
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
        businessId: _businessId!,
        workTypeId: workType.id,
      );

      if (success) {
        _loadWorkTypes();
      }
    }
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
            onPressed: _businessId != null ? _showAddDialog : null,
            tooltip: '업무 유형 추가',
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget(message: '업무 유형을 불러오는 중...')
          : _workTypes.isEmpty
              ? _buildEmptyState()
              : _buildWorkTypeList(),
      floatingActionButton: _businessId != null
          ? FloatingActionButton(
              onPressed: _showAddDialog,
              child: const Icon(Icons.add),
            )
          : null,
    );
  }

  /// 빈 상태
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
            '+ 버튼을 눌러 업무 유형을 추가하세요',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  /// 업무 유형 목록
  Widget _buildWorkTypeList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _workTypes.length,
      itemBuilder: (context, index) {
        final workType = _workTypes[index];
        final color = Color(
          int.parse(workType.color.replaceFirst('#', '0xFF')),
        );

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  workType.icon,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            title: Text(
              workType.name,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              '순서: ${workType.displayOrder + 1}',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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