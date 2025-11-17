// lib/screens/user/dialogs/my_requests_dialog.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../models/core/schedule_change_request_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../widgets/common/loading_widget.dart';

/// 내 스케줄 변경 요청 다이얼로그
class MyRequestsDialog extends StatefulWidget {
  final String applicantUid;
  final VoidCallback onChanged;

  const MyRequestsDialog({
    super.key,
    required this.applicantUid,
    required this.onChanged,
  });

  @override
  State<MyRequestsDialog> createState() => _MyRequestsDialogState();
}

class _MyRequestsDialogState extends State<MyRequestsDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<ScheduleChangeRequestModel> _requests = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  /// 요청 목록 로드
  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);

    try {
      _requests = await _firestoreService.getMyScheduleChangeRequests(widget.applicantUid);
      
      // 최신순 정렬
      _requests.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    } catch (e) {
      print('❌ 요청 목록 로드 실패: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.92,
        height: MediaQuery.of(context).size.height * 0.7,
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 헤더
            Row(
              children: [
                const Icon(Icons.notifications, size: 28),
                const SizedBox(width: 12),
                const Text(
                  '내 알림',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            
            const Divider(height: 24),

            // 요청 목록
            Expanded(
              child: _isLoading
                  ? const LoadingWidget(message: '알림 로딩 중...')
                  : _requests.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
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
          Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '알림이 없습니다',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  /// 요청 카드
  Widget _buildRequestCard(ScheduleChangeRequestModel request) {
    IconData icon;
    Color iconColor;
    
    if (request.isLeaveRequest) {
      icon = Icons.beach_access;
      iconColor = Colors.orange;
    } else if (request.isNoWorkRequest) {
      icon = Icons.block;
      iconColor = Colors.red;
    } else {
      icon = Icons.add_circle;
      iconColor = Colors.green;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconColor.withOpacity(0.2),
          child: Icon(icon, color: iconColor),
        ),
        title: Text(
          request.requestTypeLabel,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(DateFormat('M월 d일 (E)', 'ko_KR').format(request.targetDate)),
            if (request.reason != null)
              Text(
                request.reason!,
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 4),
            _buildStatusChip(request.status),
          ],
        ),
        trailing: request.isPending && request.isAdminRequest
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.red),
                    onPressed: () => _handleReject(request),
                    tooltip: '거절',
                  ),
                  IconButton(
                    icon: const Icon(Icons.check, color: Colors.green),
                    onPressed: () => _handleApprove(request),
                    tooltip: '수락',
                  ),
                ],
              )
            : request.isPending && request.isApplicantRequest
                ? IconButton(
                    icon: const Icon(Icons.cancel, color: Colors.grey),
                    onPressed: () => _handleCancel(request),
                    tooltip: '취소',
                  )
                : null,
        onTap: () => _showRequestDetail(request),
      ),
    );
  }

  /// 상태 칩
  Widget _buildStatusChip(RequestStatus status) {
    Color color;
    String label;

    switch (status) {
      case RequestStatus.PENDING:
        color = Colors.orange;
        label = '대기중';
        break;
      case RequestStatus.APPROVED:
        color = Colors.green;
        label = '승인됨';
        break;
      case RequestStatus.REJECTED:
        color = Colors.red;
        label = '거절됨';
        break;
      case RequestStatus.CANCELED:
        color = Colors.grey;
        label = '취소됨';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 요청 상세
  void _showRequestDetail(ScheduleChangeRequestModel request) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(request.requestTypeLabel),
        content: SingleChildScrollView(
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('대상 날짜', DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(request.targetDate)),
                _buildInfoRow('요청자', request.isAdminRequest ? '관리자' : '본인'),
                _buildInfoRow('요청 시각', DateFormat('M/d HH:mm').format(request.requestedAt)),
                if (request.reason != null)
                  _buildInfoRow('요청 사유', request.reason!),
                _buildInfoRow('상태', request.statusLabel),
                if (request.respondedAt != null)
                  _buildInfoRow('처리 시각', DateFormat('M/d HH:mm').format(request.respondedAt!)),
                if (request.rejectReason != null)
                  _buildInfoRow('거절 사유', request.rejectReason!),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  /// 정보 행
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 14),
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }

  /// 수락 처리
  Future<void> _handleApprove(ScheduleChangeRequestModel request) async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;

    if (uid == null) return;

    final success = await _firestoreService.approveScheduleChangeRequest(
      requestId: request.id,
      approverUid: uid,
    );

    if (success) {
      ToastHelper.showSuccess('수락되었습니다');
      await _loadRequests();
      widget.onChanged();
    } else {
      ToastHelper.showError('수락 실패');
    }
  }

  /// 거절 처리
  Future<void> _handleReject(ScheduleChangeRequestModel request) async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;

    if (uid == null) return;

    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('거절 사유'),
        content: TextField(
          controller: reasonController,
          decoration: const InputDecoration(
            hintText: '거절 사유를 입력하세요 (선택)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('거절'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final success = await _firestoreService.rejectScheduleChangeRequest(
      requestId: request.id,
      rejectorUid: uid,
      rejectReason: reasonController.text.trim().isEmpty 
          ? null 
          : reasonController.text.trim(),
    );

    if (success) {
      ToastHelper.showSuccess('거절되었습니다');
      await _loadRequests();
      widget.onChanged();
    } else {
      ToastHelper.showError('거절 실패');
    }
  }

  /// 취소 처리 (자신이 요청한 것만)
  Future<void> _handleCancel(ScheduleChangeRequestModel request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('요청 취소'),
        content: const Text('이 요청을 취소하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('아니오'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('예'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;

    if (uid == null) return;

    final success = await _firestoreService.cancelScheduleChangeRequest(
      requestId: request.id,
      canceledByUid: uid,
    );

    if (success) {
      ToastHelper.showSuccess('요청이 취소되었습니다');
      await _loadRequests();
      widget.onChanged();
    } else {
      ToastHelper.showError('취소 실패');
    }
  }
}