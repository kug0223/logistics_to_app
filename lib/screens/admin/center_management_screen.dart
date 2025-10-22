import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/center_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import './center_form_screen.dart';

/// 사업장 관리 화면 (목록 + 추가/수정/삭제)
/// ✅ 🆕 각 관리자는 본인이 생성한 사업장만 볼 수 있음
class CenterManagementScreen extends StatefulWidget {
  const CenterManagementScreen({Key? key}) : super(key: key);

  @override
  State<CenterManagementScreen> createState() => _CenterManagementScreenState();
}

class _CenterManagementScreenState extends State<CenterManagementScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = true;
  List<CenterModel> _centers = [];

  @override
  void initState() {
    super.initState();
    _loadCenters();
  }

  /// ✅ 🆕 본인이 생성한 사업장만 로드
  Future<void> _loadCenters() async {
    setState(() => _isLoading = true);
    try {
      final userProvider = context.read<UserProvider>();
      final currentUserId = userProvider.currentUser?.uid;
      
      if (currentUserId == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        setState(() => _isLoading = false);
        return;
      }

      // ✅ 본인이 생성한 사업장만 가져오기 (ownerId 필터)
      final centers = await _firestoreService.getCentersByOwnerId(currentUserId);
      
      if (mounted) {
        setState(() {
          _centers = centers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastHelper.showError('사업장 목록을 불러오는데 실패했습니다: $e');
      }
    }
  }

  /// 사업장 삭제
  Future<void> _deleteCenter(CenterModel center) async {
    // ✅ center.id null 체크
    if (center.id == null) {
      ToastHelper.showError('사업장 ID를 찾을 수 없습니다');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('사업장 삭제'),
        content: Text('${center.name}을(를) 정말 삭제하시겠습니까?\n\n비활성화됩니다.'),
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

    if (confirm != true) return;

    try {
      // ✅ deleteCenter는 bool 반환
      final success = await _firestoreService.deleteCenter(center.id!);
      if (success && mounted) {
        _loadCenters();
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showError('사업장 삭제에 실패했습니다: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 사업장 관리'),
        backgroundColor: Colors.blue.shade700,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _centers.isEmpty
              ? _buildEmptyState()
              : _buildCenterList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const CenterFormScreen(),
            ),
          );
          if (result == true) {
            _loadCenters();
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('사업장 추가'),
        backgroundColor: Colors.blue.shade700,
      ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.business_outlined,
            size: 80,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            '등록된 사업장이 없습니다',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '우측 하단 버튼으로 사업장을 추가하세요',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  /// 사업장 목록
  Widget _buildCenterList() {
    return RefreshIndicator(
      onRefresh: _loadCenters,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _centers.length,
        itemBuilder: (context, index) {
          final center = _centers[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              leading: CircleAvatar(
                backgroundColor: center.isActive 
                    ? Colors.blue.shade100 
                    : Colors.grey.shade300,
                child: Icon(
                  Icons.business,
                  color: center.isActive 
                      ? Colors.blue.shade700 
                      : Colors.grey.shade600,
                ),
              ),
              title: Text(
                center.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 4),
                  Text(
                    center.address,
                    style: TextStyle(
                      color: Colors.grey.shade700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: center.isActive 
                          ? Colors.green.shade50 
                          : Colors.red.shade50,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      center.isActive ? '활성' : '비활성',
                      style: TextStyle(
                        color: center.isActive 
                            ? Colors.green.shade700 
                            : Colors.red.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              trailing: PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') {
                    final result = await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CenterFormScreen(
                          center: center,
                        ),
                      ),
                    );
                    if (result == true) {
                      _loadCenters();
                    }
                  } else if (value == 'delete') {
                    _deleteCenter(center);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20),
                        SizedBox(width: 8),
                        Text('수정'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 20, color: Colors.red),
                        SizedBox(width: 8),
                        Text('삭제', style: TextStyle(color: Colors.red)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}