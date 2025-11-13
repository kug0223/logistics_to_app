import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../services/firestore_service.dart';
import 'widgets/workforce_list_view.dart';
import 'widgets/workforce_calendar_view.dart';
import 'dialogs/resign_request_management_dialog.dart';

/// 통합 인력 관리 화면 (TO 관리 + 캘린더)
class IntegratedWorkforceScreen extends StatefulWidget {
  const IntegratedWorkforceScreen({super.key});

  @override
  State<IntegratedWorkforceScreen> createState() =>
      _IntegratedWorkforceScreenState();
}

class _IntegratedWorkforceScreenState extends State<IntegratedWorkforceScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  String? _selectedBusinessId;
  bool _isCalendarView = false; // false: 리스트, true: 캘린더

  @override
  void initState() {
    super.initState();
    _loadBusinessId();
  }

  /// 사업장 ID 로드
  void _loadBusinessId() {
    final userProvider = context.read<UserProvider>();
    final businessId = userProvider.currentUser?.businessId;

    if (businessId == null || businessId.isEmpty) {
      ToastHelper.showWarning('등록된 사업장이 없습니다.');
      return;
    }

    setState(() {
      _selectedBusinessId = businessId;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedBusinessId == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('인력 관리'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.business_center, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '등록된 사업장이 없습니다',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isCalendarView ? '인력 관리 - 캘린더' : '인력 관리 - 목록'),
        actions: [
          // 퇴사 요청 알림 아이콘
          FutureBuilder<int>(
            future: _getResignRequestCount(),
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.exit_to_app),
                    onPressed: _showResignRequestManagement,
                    tooltip: '퇴사 요청',
                  ),
                  if (count > 0)
                    Positioned(
                      right: 8,
                      top: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          '$count',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          
          // 리스트/캘린더 토글
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                _buildToggleButton(
                  icon: Icons.view_list,
                  label: '목록',
                  isSelected: !_isCalendarView,
                  onTap: () {
                    setState(() {
                      _isCalendarView = false;
                    });
                  },
                ),
                _buildToggleButton(
                  icon: Icons.calendar_month,
                  label: '캘린더',
                  isSelected: _isCalendarView,
                  onTap: () {
                    setState(() {
                      _isCalendarView = true;
                    });
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      body: _isCalendarView
          ? WorkforceCalendarView(businessId: _selectedBusinessId!)
          : const WorkforceListView(), // ✅ businessId 파라미터 제거!
    );
  }

  /// 토글 버튼
  Widget _buildToggleButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? Theme.of(context).primaryColor : Colors.white,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isSelected ? Theme.of(context).primaryColor : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 퇴사 요청 개수 조회
  Future<int> _getResignRequestCount() async {
    if (_selectedBusinessId == null) return 0;
    
    try {
      final requests = await _firestoreService.getResignRequests(_selectedBusinessId!);
      return requests.length;
    } catch (e) {
      return 0;
    }
  }

  /// 퇴사 요청 관리 다이얼로그 표시
  void _showResignRequestManagement() {
    if (_selectedBusinessId == null) {
      ToastHelper.showWarning('사업장 정보를 찾을 수 없습니다.');
      return;
    }
    
    showDialog(
      context: context,
      builder: (context) => ResignRequestManagementDialog(
        businessId: _selectedBusinessId!,
        onChanged: () {
          setState(() {}); // 배지 업데이트
        },
      ),
    );
  }
}