import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/core/application_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/dialog_helper.dart';

/// 퇴사 요청 관리 다이얼로그 (관리자용)
class ResignRequestManagementDialog extends StatefulWidget {
  final String businessId;
  final VoidCallback onChanged;

  const ResignRequestManagementDialog({
    super.key,
    required this.businessId,
    required this.onChanged,
  });

  @override
  State<ResignRequestManagementDialog> createState() =>
      _ResignRequestManagementDialogState();
}

class _ResignRequestManagementDialogState
    extends State<ResignRequestManagementDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  List<_ResignRequestWithUser> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadResignRequests();
  }

  /// 퇴사 요청 목록 로드
  Future<void> _loadResignRequests() async {
    setState(() => _isLoading = true);

    try {
      // 해당 사업장의 모든 장기 근무 확정 건 중 퇴사 요청이 있는 것만
      final applications = await _firestoreService.getResignRequests(
        widget.businessId,
      );

      // 사용자 정보와 함께 조회
      final futures = applications.map((app) async {
        final user = await _firestoreService.getUser(app.uid);
        return _ResignRequestWithUser(
          application: app,
          userName: user?.name ?? '이름 없음',
          userPhone: user?.phone ?? '전화번호 없음',
        );
      }).toList();

      final results = await Future.wait(futures);

      // 요청일 최신순 정렬
      results.sort((a, b) => b.application.resignRequestedAt!
          .compareTo(a.application.resignRequestedAt!));

      setState(() {
        _requests = results;
        _isLoading = false;
      });

      print('✅ 퇴사 요청 ${results.length}건 로드 완료');
    } catch (e) {
      print('❌ 퇴사 요청 로드 실패: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
        child: Column(
          children: [
            // 헤더
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[700],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(4),
                  topRight: Radius.circular(4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.exit_to_app, color: Colors.white),
                  const SizedBox(width: 12),
                  const Text(
                    '퇴사 요청 관리',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 본문
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _requests.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _requests.length,
                          itemBuilder: (context, index) {
                            return _buildRequestCard(_requests[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '퇴사 요청이 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 요청 카드
  Widget _buildRequestCard(_ResignRequestWithUser item) {
    final app = item.application;
    final daysLeft = 3 - DateTime.now().difference(app.resignRequestedAt!).inDays;
    final isUrgent = daysLeft <= 1;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isUrgent ? Colors.red[300]! : Colors.grey[300]!,
          width: isUrgent ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 근무자 정보
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue[100],
                  child: Text(
                    item.userName[0],
                    style: TextStyle(
                      color: Colors.blue[900],
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.userName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        item.userPhone,
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                // 긴급 배지
                if (isUrgent)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.red[300]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning, size: 14, color: Colors.red[700]),
                        const SizedBox(width: 4),
                        Text(
                          '긴급',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.red[700],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),

            // 근무 정보
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoRow(Icons.business, '사업장', app.businessName),
                  const SizedBox(height: 8),
                  _buildInfoRow(
                    Icons.calendar_today,
                    '근무 기간',
                    app.workPeriodDisplay,
                  ),
                  const SizedBox(height: 8),
                  if (app.workDaysDisplay != null)
                    _buildInfoRow(
                      Icons.event_repeat,
                      '근무 요일',
                      app.workDaysDisplay!,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // 퇴사 요청 정보
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.exit_to_app,
                          size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Text(
                        '퇴사 희망일: ${DateFormat('yyyy년 M월 d일').format(app.resignRequestDate!)}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[900],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.schedule, size: 16, color: Colors.orange[700]),
                      const SizedBox(width: 8),
                      Text(
                        '요청일: ${DateFormat('M월 d일 HH:mm').format(app.resignRequestedAt!)}',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange[800],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        isUrgent ? Icons.warning : Icons.info_outline,
                        size: 16,
                        color: isUrgent ? Colors.red[700] : Colors.orange[700],
                      ),
                      const SizedBox(width: 8),
                      Text(
                        daysLeft > 0
                            ? '$daysLeft일 후 자동 승인'
                            : '오늘 자정 자동 승인',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: isUrgent ? Colors.red[700] : Colors.orange[800],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 승인/거절 버튼
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _handleReject(item),
                    icon: const Icon(Icons.cancel),
                    label: const Text('거절'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => _handleApprove(item),
                    icon: const Icon(Icons.check_circle),
                    label: const Text('승인'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 정보 행
  Widget _buildInfoRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey[600],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// 승인 처리
  Future<void> _handleApprove(_ResignRequestWithUser item) async {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '퇴사 승인',
      message:
          '${item.userName}님의 퇴사를 승인하시겠습니까?\n\n'
          '퇴사일: ${DateFormat('yyyy년 M월 d일').format(item.application.resignRequestDate!)}\n\n'
          '승인 후에는 취소할 수 없습니다.',
      confirmText: '승인',
      confirmColor: Colors.green,
    );

    if (!confirmed || !mounted) return;

    try {
      final adminUID = 'ADMIN_UID'; // TODO: 실제 관리자 UID 가져오기

      final success = await _firestoreService.approveResignation(
        applicationId: item.application.id,
        adminUID: adminUID,
      );

      if (success && mounted) {
        ToastHelper.showSuccess('퇴사가 승인되었습니다.');
        widget.onChanged();
        await _loadResignRequests();
      } else if (mounted) {
        ToastHelper.showError('승인 처리 중 오류가 발생했습니다.');
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showError('승인 처리 중 오류가 발생했습니다.');
      }
    }
  }

  /// 거절 처리
  Future<void> _handleReject(_ResignRequestWithUser item) async {
    // 거절 사유 입력
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('퇴사 거절 사유'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${item.userName}님의 퇴사 요청을 거절하는 이유를 입력해주세요.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              maxLength: 200,
              decoration: const InputDecoration(
                hintText: '거절 사유를 입력하세요',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () {
              if (reasonController.text.trim().isEmpty) {
                ToastHelper.showWarning('거절 사유를 입력해주세요.');
                return;
              }
              Navigator.pop(context, reasonController.text.trim());
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('거절'),
          ),
        ],
      ),
    );

    if (reason == null || reason.isEmpty || !mounted) return;

    try {
      final adminUID = 'ADMIN_UID'; // TODO: 실제 관리자 UID 가져오기

      final success = await _firestoreService.rejectResignation(
        applicationId: item.application.id,
        adminUID: adminUID,
        rejectReason: reason,
      );

      if (success && mounted) {
        ToastHelper.showSuccess('퇴사 요청이 거절되었습니다.');
        widget.onChanged();
        await _loadResignRequests();
      } else if (mounted) {
        ToastHelper.showError('거절 처리 중 오류가 발생했습니다.');
      }
    } catch (e) {
      if (mounted) {
        ToastHelper.showError('거절 처리 중 오류가 발생했습니다.');
      }
    }
  }
}

/// 퇴사 요청 + 사용자 정보
class _ResignRequestWithUser {
  final ApplicationModel application;
  final String userName;
  final String userPhone;

  _ResignRequestWithUser({
    required this.application,
    required this.userName,
    required this.userPhone,
  });
}