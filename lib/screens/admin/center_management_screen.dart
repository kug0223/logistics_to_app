import 'package:flutter/material.dart';
import '../../models/center_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/toast_helper.dart';
import './center_form_screen.dart';

/// 센터 관리 화면 (목록 + 추가/수정/삭제)
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

  /// 센터 목록 로드
  Future<void> _loadCenters() async {
    setState(() => _isLoading = true);
    try {
      // ✅ activeOnly 파라미터 사용
      final centers = await _firestoreService.getCenters(activeOnly: false);
      if (mounted) {
        setState(() {
          _centers = centers;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ToastHelper.showError('센터 목록을 불러오는데 실패했습니다: $e');
      }
    }
  }

  /// 센터 삭제
  Future<void> _deleteCenter(CenterModel center) async {
    // ✅ center.id null 체크
    if (center.id == null) {
      ToastHelper.showError('센터 ID를 찾을 수 없습니다');
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('센터 삭제'),
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
        ToastHelper.showError('센터 삭제에 실패했습니다: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('사업장 관리'),
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

  /// 센터 목록
  Widget _buildCenterList() {
    return RefreshIndicator(
      onRefresh: _loadCenters,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _centers.length,
        itemBuilder: (context, index) {
          final center = _centers[index];
          return _buildCenterCard(center);
        },
      ),
    );
  }

  /// 센터 카드
  Widget _buildCenterCard(CenterModel center) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () async {
          final result = await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CenterFormScreen(center: center),
            ),
          );
          if (result == true) {
            _loadCenters();
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더 (이름 + 상태 + 삭제 버튼)
              Row(
                children: [
                  // 센터 아이콘
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.business,
                      color: Colors.blue.shade700,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // 센터명 + 코드
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              center.name,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // 활성화 상태 배지
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: center.isActive
                                    ? Colors.green.shade50
                                    : Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                center.isActive ? '활성' : '비활성',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: center.isActive
                                      ? Colors.green.shade700
                                      : Colors.grey.shade600,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'ID: ${center.code}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  // 삭제 버튼
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    color: Colors.red.shade400,
                    onPressed: () => _deleteCenter(center),
                    tooltip: '삭제',
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              
              // 주소
              Row(
                children: [
                  Icon(Icons.location_on, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      center.address,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                      ),
                    ),
                  ),
                ],
              ),
              
              // 좌표 (있는 경우)
              if (center.latitude != null && center.longitude != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.my_location, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(
                      '위도: ${center.latitude!.toStringAsFixed(6)}, 경도: ${center.longitude!.toStringAsFixed(6)}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
              
              // 설명 (있는 경우)
              if (center.description != null && center.description!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        center.description!,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
              
              // 담당자 정보 (있는 경우)
              if (center.managerName != null || center.managerPhone != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.person, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(
                      '${center.managerName ?? ''}${center.managerPhone != null ? ' (${center.managerPhone})' : ''}',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}