// lib/screens/user/my_schedule_requests_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../models/core/schedule_change_request_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/loading_widget.dart';

/// 사용자용 - 내가 보낸 스케줄 변경 요청 조회 화면
class MyScheduleRequestsScreen extends StatefulWidget {
  const MyScheduleRequestsScreen({super.key});

  @override
  State<MyScheduleRequestsScreen> createState() => _MyScheduleRequestsScreenState();
}

class _MyScheduleRequestsScreenState extends State<MyScheduleRequestsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<ScheduleChangeRequestModel> _allRequests = [];
  List<ScheduleChangeRequestModel> _filteredRequests = [];
  
  bool _isLoading = true;
  String _selectedFilter = 'PENDING'; // PENDING, ALL, APPROVED, REJECTED
  
  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  /// 요청 목록 로드
  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);

    try {
      final userProvider = context.read<UserProvider>();
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('사용자 정보를 찾을 수 없습니다');
        return;
      }

      final requests = await _firestoreService.getMyScheduleChangeRequests(uid);

      setState(() {
        _allRequests = requests;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 요청 목록 로드 실패: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ToastHelper.showError('요청 목록을 불러올 수 없습니다');
      }
    }
  }

  /// 필터 적용
  void _applyFilter() {
    if (_selectedFilter == 'ALL') {
      _filteredRequests = _allRequests;
    } else {
      _filteredRequests = _allRequests.where((request) {
        return request.status.toString().split('.').last == _selectedFilter;
      }).toList();
    }

    // 최신순 정렬
    _filteredRequests.sort((a, b) => 
      b.requestedAt.compareTo(a.requestedAt)
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('내 요청 내역'),
      ),
      body: Column(
        children: [
          // 필터 탭
          _buildFilterTabs(),

          // 요청 목록
          Expanded(
            child: _isLoading
                ? const LoadingWidget(message: '요청 내역을 불러오는 중...')
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
    );
  }

  /// 필터 탭
  Widget _buildFilterTabs() {
    final pendingCount = _allRequests.where((r) => r.isPending).length;
    
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
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '내 스케줄 화면에서 휴무를 요청할 수 있습니다',
            style: ResponsiveHelper.smallStyle(
              context,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ),
          ),
        ],
      ),
    );
  }

  /// 요청 카드
  Widget _buildRequestCard(ScheduleChangeRequestModel request) {
    return Card(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 12),
      ),
      child: InkWell(
        onTap: () => _showRequestDetail(request),
        borderRadius: BorderRadius.circular(12),
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

              // 대상 날짜
              Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: ResponsiveHelper.iconSize(context, 18),
                    color: Theme.of(context).primaryColor,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(request.targetDate),
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
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

              // 사유
              if (request.reason != null && request.reason!.isNotEmpty) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).primaryColor.withOpacity(0.2),
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
                          style: ResponsiveHelper.smallStyle(context),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
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
                      color: request.isApproved ? Colors.green : Colors.red,
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
                      color: Colors.red.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.withOpacity(0.2)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: ResponsiveHelper.iconSize(context, 16),
                          color: Colors.red,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Expanded(
                          child: Text(
                            '거절 사유: ${request.rejectReason}',
                            style: ResponsiveHelper.smallStyle(
                              context,
                              color: Colors.red,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],

              // 취소 버튼 (대기중인 경우만)
              if (request.isPending) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _handleCancel(request),
                    icon: const Icon(Icons.close),
                    label: const Text('요청 취소'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 요청 타입 칩
  Widget _buildRequestTypeChip(RequestType type) {
    IconData icon;
    Color color;
    String label;

    switch (type) {
      case RequestType.LEAVE:
        icon = Icons.event_busy;
        color = Colors.orange;
        label = '휴무 요청';
        break;
      case RequestType.NO_WORK:
        icon = Icons.block;
        color = Colors.red;
        label = '미출근 요청';
        break;
      case RequestType.EXTRA_WORK:
        icon = Icons.add_circle;
        color = Colors.green;
        label = '추가 근무';
        break;
      case RequestType.CANCEL_LEAVE:
        icon = Icons.event_available;
        color = Colors.blue;
        label = '휴무 취소';
        break;
      case RequestType.CANCEL_EXTRA:
        icon = Icons.remove_circle;
        color = Colors.purple;
        label = '추가근무 취소';
        break;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
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
            label,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// 상태 배지
  Widget _buildStatusBadge(RequestStatus status) {
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
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
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

  /// 요청 상세 다이얼로그
  void _showRequestDetail(ScheduleChangeRequestModel request) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(request.requestTypeLabel),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildInfoRow('대상 날짜', DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(request.targetDate)),
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
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          if (request.isPending)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _handleCancel(request);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('요청 취소'),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: ResponsiveHelper.smallStyle(
                context,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 요청 취소
  Future<void> _handleCancel(ScheduleChangeRequestModel request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('요청 취소'),
        content: Text(
          '${request.requestTypeLabel}을 취소하시겠습니까?',
          style: ResponsiveHelper.bodyStyle(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('아니오'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('취소'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final userProvider = context.read<UserProvider>();
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('사용자 정보를 찾을 수 없습니다');
        return;
      }

      final success = await _firestoreService.cancelScheduleChangeRequest(
        requestId: request.id,
        canceledByUid: uid,
      );

      if (success && mounted) {
        ToastHelper.showSuccess('요청이 취소되었습니다');
        await _loadRequests();
      } else if (mounted) {
        ToastHelper.showError('요청 취소에 실패했습니다');
      }
    } catch (e) {
      print('❌ 요청 취소 실패: $e');
      if (mounted) {
        ToastHelper.showError('요청 취소 중 오류가 발생했습니다');
      }
    }
  }
}