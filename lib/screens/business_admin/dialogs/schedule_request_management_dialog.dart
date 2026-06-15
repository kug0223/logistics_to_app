// lib/screens/business_admin/dialogs/schedule_request_management_dialog.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/core/schedule_change_request_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/loading_state_mixin.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/common/loading_button.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../theme/app_colors.dart';


/// 스케줄 변경 요청 관리 다이얼로그 (관리자용)
class ScheduleRequestManagementDialog extends StatefulWidget {
  final String businessId;
  final VoidCallback onChanged;

  const ScheduleRequestManagementDialog({
    super.key,
    required this.businessId,
    required this.onChanged,
  });

  @override
  State<ScheduleRequestManagementDialog> createState() =>
      _ScheduleRequestManagementDialogState();
}

class _ScheduleRequestManagementDialogState
    extends State<ScheduleRequestManagementDialog>
    with LoadingStateMixin {
  final FirestoreService _firestoreService = FirestoreService();

  List<_RequestWithUser> _allRequests = [];
  List<_RequestWithUser> _filteredRequests = [];
  String _selectedFilter = 'PENDING';

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  /// 요청 목록 로드
  Future<void> _loadRequests() => runWithLoading(() async {
    final allRequests = await _firestoreService.getAllScheduleChangeRequests(
      widget.businessId,
    );

    final workerRequests = allRequests
        .where((r) => r.requestedBy == RequesterType.APPLICANT)
        .toList();

    final uniqueUids = workerRequests.map((r) => r.applicantUid).toSet().toList();
    final userMap = await _firestoreService.getUsersBatch(uniqueUids);

    final results = workerRequests.map((request) {
      final user = userMap[request.applicantUid];
      return _RequestWithUser(
        request: request,
        userName: user?.name ?? '이름 없음',
        userPhone: user?.phone ?? '전화번호 없음',
      );
    }).toList();

    if (mounted) {
      setState(() {
        _allRequests = results;
        _applyFilter();
      });
    }
  }, errorTag: '요청 목록 로드', errorMessage: '요청 목록을 불러올 수 없습니다');

  /// 필터 적용
  void _applyFilter() {
    if (_selectedFilter == 'ALL') {
      _filteredRequests = _allRequests;
    } else {
      _filteredRequests = _allRequests.where((item) {
        return item.request.status.toString().split('.').last == _selectedFilter;
      }).toList();
    }

    // 최신순 정렬
    _filteredRequests.sort((a, b) => 
      b.request.requestedAt.compareTo(a.request.requestedAt)
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: AppDialogSize.insetV,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
        ),
        child: Column(
          children: [
            // 헤더
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.edit_calendar,
                    color: Colors.white,
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Text(
                      '스케줄 변경 요청 관리',
                      style: ResponsiveHelper.titleStyle(context).copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 필터 탭
            _buildFilterTabs(),

            // 요청 목록
            Expanded(
              child: isLoading
                  ? const LoadingWidget(message: '요청 목록을 불러오는 중...')
                  : _filteredRequests.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadRequests,
                          child: ListView.builder(
                            padding: ResponsiveHelper.cardPadding(context),
                            itemCount: _filteredRequests.length,
                            itemBuilder: (context, index) {
                              return _buildRequestCard(_filteredRequests[index]);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  /// 필터 탭
  Widget _buildFilterTabs() {
    final pendingCount = _allRequests.where((r) => r.request.isPending).length;
    
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          _buildFilterTab('대기중 ($pendingCount)', 'PENDING'),
          _buildFilterTab('전체', 'ALL'),
          _buildFilterTab('승인됨', 'APPROVED'),
          _buildFilterTab('거절됨', 'REJECTED'),
        ],
      ),
    );
  }

  Widget _buildFilterTab(String label, String value) {
    final isSelected = _selectedFilter == value;
    
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() {
            _selectedFilter = value;
            _applyFilter();
          });
        },
        child: Container(
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected 
                    ? Theme.of(context).primaryColor 
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: isSelected 
                  ? Theme.of(context).primaryColor 
                  : Theme.of(context).textTheme.bodySmall?.color,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
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
          Icon(
            Icons.inbox,
            size: ResponsiveHelper.iconSize(context, 64),
            color: Theme.of(context).disabledColor,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            _selectedFilter == 'PENDING'
                ? '대기중인 요청이 없습니다'
                : '요청 내역이 없습니다',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  /// 요청 카드
  Widget _buildRequestCard(_RequestWithUser item) {
    final request = item.request;
    
    return Card(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 12),
      ),
      child: Padding(
        padding: ResponsiveHelper.cardPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 헤더: 요청 타입 + 상태
            Row(
              children: [
                _buildRequestTypeChip(request.requestType),
                const Spacer(),
                _buildStatusBadge(request.status),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),

            // 근무자 정보
            Row(
              children: [
                Icon(
                  Icons.person,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: Theme.of(context).primaryColor,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  item.userName,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  item.userPhone,
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),

            // 대상 날짜
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  '대상: ${FormatHelper.formatDateLong(request.targetDate)}',
                  style: ResponsiveHelper.bodyStyle(context),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),

            // 요청 시각
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  '요청: ${DateFormat('M/d HH:mm').format(request.requestedAt)}',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),

            // 요청자
            if (request.isAdminRequest) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              Row(
                children: [
                  Icon(
                    Icons.admin_panel_settings,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: AppColors.purple,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    '관리자 요청',
                    style: ResponsiveHelper.smallStyle(
                      context,
                      color: AppColors.purple,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],

            // 사유
            if (request.reason != null && request.reason!.isNotEmpty) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Container(
                padding: ResponsiveHelper.cardPadding(context),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.notes,
                      size: ResponsiveHelper.iconSize(context, 16),
                      color: Theme.of(context).primaryColor,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        request.reason!,
                        style: ResponsiveHelper.bodyStyle(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 처리 정보 (승인/거절된 경우)
            if (request.respondedAt != null) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Row(
                children: [
                  Icon(
                    request.isApproved ? Icons.check_circle : Icons.cancel,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: request.isApproved ? AppColors.success : AppColors.error,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    '처리: ${DateFormat('M/d HH:mm').format(request.respondedAt!)}',
                    style: ResponsiveHelper.smallStyle(context),
                  ),
                ],
              ),
              if (request.rejectReason != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: ResponsiveHelper.iconSize(context, 16),
                        color: AppColors.error,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Expanded(
                        child: Text(
                          '거절 사유: ${request.rejectReason}',
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: AppColors.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],

            // 승인/거절 버튼 (대기중인 경우만)
            if (request.isPending) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Row(
                children: [
                  Expanded(
                    child: LoadingButton.outlined(
                      text: '거절',
                      icon: Icons.cancel,
                      borderColor: AppColors.error,
                      foregroundColor: AppColors.error,
                      onPressed: () async => _handleReject(item),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: LoadingButton.success(
                      text: '승인',
                      icon: Icons.check_circle,
                      onPressed: () async => _handleApprove(item),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 요청 타입 칩
  Widget _buildRequestTypeChip(RequestType type) {
    IconData icon;
    Color color;

    switch (type) {
      case RequestType.LEAVE:
        icon = Icons.event_busy;
        color = AppColors.warning;
        break;
      case RequestType.NO_WORK:
        icon = Icons.block;
        color = AppColors.error;
        break;
      case RequestType.EXTRA_WORK:
        icon = Icons.add_circle;
        color = AppColors.success;
        break;
      case RequestType.CANCEL_LEAVE:
        icon = Icons.event_available;
        color = AppColors.info;
        break;
      case RequestType.CANCEL_EXTRA:
        icon = Icons.remove_circle;
        color = AppColors.purple;
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 16),
            color: color,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text(
            _getRequestTypeLabel(type),
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _getRequestTypeLabel(RequestType type) {
    switch (type) {
      case RequestType.LEAVE:
        return '휴무 요청';
      case RequestType.NO_WORK:
        return '미출근 요청';
      case RequestType.EXTRA_WORK:
        return '추가 근무';
      case RequestType.CANCEL_LEAVE:
        return '휴무 취소';
      case RequestType.CANCEL_EXTRA:
        return '추가근무 취소';
    }
  }

  /// 상태 배지
  Widget _buildStatusBadge(RequestStatus status) {
    Color color;
    String label;

    switch (status) {
      case RequestStatus.PENDING:
        color = AppColors.warning;
        label = '대기중';
        break;
      case RequestStatus.APPROVED:
        color = AppColors.success;
        label = '승인됨';
        break;
      case RequestStatus.REJECTED:
        color = AppColors.error;
        label = '거절됨';
        break;
      case RequestStatus.CANCELED:
        color = AppColors.grey500;
        label = '취소됨';
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.tinyStyle(context).copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 승인 처리
  Future<void> _handleApprove(_RequestWithUser item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StyledDialog(
        title: '요청 승인',
        icon: Icons.check_circle_outline,
        headerColor: AppColors.success,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.userName}님의 ${item.request.requestTypeLabel}을 승인하시겠습니까?',
              style: ResponsiveHelper.bodyStyle(context),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            StyledDialogInfoCard.success(_getApprovalMessage(item.request.requestType)),
          ],
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context, false),
          ),
          StyledDialogButton.primary(
            text: '승인',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final uid = context.read<UserProvider>().currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('관리자 정보를 찾을 수 없습니다');
        return;
      }

      final success = await _firestoreService.approveScheduleChangeRequest(
        requestId: item.request.id,
        approverUid: uid,
      );

      if (success && mounted) {
        ToastHelper.showSuccess('요청이 승인되었습니다');
        await _loadRequests();
        widget.onChanged();
      } else if (mounted) {
        ToastHelper.showError('승인 처리 중 오류가 발생했습니다');
      }
    } catch (e) {
      debugPrint('❌ 승인 실패: $e');
      if (mounted) {
        ToastHelper.showError('승인 처리 중 오류가 발생했습니다');
      }
    }
  }

  String _getApprovalMessage(RequestType type) {
    switch (type) {
      case RequestType.LEAVE:
        return '• 해당 날짜가 휴무로 표시됩니다\n• 근무 일수 및 급여에서 제외됩니다';
      case RequestType.NO_WORK:
        return '• 해당 날짜가 미출근으로 표시됩니다\n• 근무 일수 및 급여에서 제외됩니다';
      case RequestType.EXTRA_WORK:
        return '• 해당 날짜가 근무일로 추가됩니다\n• 근무 일수 및 급여에 포함됩니다';
      case RequestType.CANCEL_LEAVE:
        return '• 휴무가 취소되고 정상 근무일로 복구됩니다\n• 근무 일수 및 급여에 포함됩니다';
      case RequestType.CANCEL_EXTRA:
        return '• 추가 근무가 취소됩니다\n• 근무 일수 및 급여에서 제외됩니다';
    }
  }

  /// 거절 처리
  Future<void> _handleReject(_RequestWithUser item) async {
    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StyledDialog(
        title: '요청 거절',
        icon: Icons.cancel_outlined,
        headerColor: AppColors.error,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.userName}님의 ${item.request.requestTypeLabel}을 거절하시겠습니까?',
              style: ResponsiveHelper.bodyStyle(context),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '거절 사유',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: '거절 사유를 입력하세요',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context, false),
          ),
          StyledDialogButton.danger(
            text: '거절',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    final rejectReason = reasonController.text.trim().isEmpty ? null : reasonController.text.trim();
    reasonController.dispose();
    if (confirmed != true) return;
    if (!mounted) return;

    try {
      final uid = context.read<UserProvider>().currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('관리자 정보를 찾을 수 없습니다');
        return;
      }

      final success = await _firestoreService.rejectScheduleChangeRequest(
        requestId: item.request.id,
        rejectorUid: uid,
        rejectReason: rejectReason,
      );

      if (success && mounted) {
        ToastHelper.showSuccess('요청이 거절되었습니다');
        await _loadRequests();
        widget.onChanged();
      } else if (mounted) {
        ToastHelper.showError('거절 처리 중 오류가 발생했습니다');
      }
    } catch (e) {
      debugPrint('❌ 거절 실패: $e');
      if (mounted) {
        ToastHelper.showError('거절 처리 중 오류가 발생했습니다');
      }
    }
  }
}

/// 요청 + 사용자 정보
class _RequestWithUser {
  final ScheduleChangeRequestModel request;
  final String userName;
  final String userPhone;

  _RequestWithUser({
    required this.request,
    required this.userName,
    required this.userPhone,
  });
}