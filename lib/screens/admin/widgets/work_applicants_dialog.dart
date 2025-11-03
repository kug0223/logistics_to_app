import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/application_model.dart';
import '../../../models/work_detail_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../models/to_list_models.dart';

/// 업무별 지원자 관리 다이얼로그
class WorkApplicantsDialog extends StatefulWidget {
  final WorkDetailModel work;
  final TOItem toItem;
  final VoidCallback onChanged;

  const WorkApplicantsDialog({
    Key? key,
    required this.work,
    required this.toItem,
    required this.onChanged,
  }) : super(key: key);

  @override
  State<WorkApplicantsDialog> createState() => _WorkApplicantsDialogState();
}

class _WorkApplicantsDialogState extends State<WorkApplicantsDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  
  // 🔥 ApplicationModel + 사용자 정보
  List<Map<String, dynamic>> _applicants = [];
  bool _isLoading = true;
  
  final Set<String> _selectedIds = {};
  bool _selectAll = false;

  @override
  void initState() {
    super.initState();
    _loadApplicants();
  }

  /// 🔥 지원자 + 사용자 정보 로드
  Future<void> _loadApplicants() async {
    setState(() => _isLoading = true);

    try {
      final apps = await _firestoreService.getApplicationsByTO(
        widget.toItem.to.businessId,
        widget.toItem.to.title,
        widget.toItem.to.date,
      );

      final filtered = apps.where((app) => 
        app.selectedWorkType == widget.work.workType
      ).toList();

      filtered.sort((a, b) => b.appliedAt.compareTo(a.appliedAt));

      // 🔥 각 지원자의 사용자 정보 조회
      List<Map<String, dynamic>> applicantsWithUserInfo = [];
      
      for (var app in filtered) {
        final user = await _firestoreService.getUser(app.uid);
        applicantsWithUserInfo.add({
          'application': app,
          'userName': user?.name ?? '이름 없음',
          'userPhone': user?.phone ?? '전화번호 없음',
          'userEmail': user?.email ?? '',
        });
      }

      setState(() {
        _applicants = applicantsWithUserInfo;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 지원자 로드 실패: $e');
      setState(() => _isLoading = false);
    }
  }

  /// 전체 선택/해제
  void _toggleSelectAll(bool? value) {
    setState(() {
      _selectAll = value ?? false;
      if (_selectAll) {
        _selectedIds.addAll(
          _applicants
              .where((item) => (item['application'] as ApplicationModel).status == 'PENDING')
              .map((item) => (item['application'] as ApplicationModel).id)
        );
      } else {
        _selectedIds.clear();
      }
    });
  }

  /// 개별 선택/해제
  void _toggleSelect(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
        _selectAll = false;
      } else {
        _selectedIds.add(id);
        
        final pendingCount = _applicants
            .where((item) => (item['application'] as ApplicationModel).status == 'PENDING')
            .length;
        _selectAll = _selectedIds.length == pendingCount;
      }
    });
  }

  /// 일괄 승인 (인원 체크 추가!)
  Future<void> _approveSelected() async {
    if (_selectedIds.isEmpty) {
      ToastHelper.showWarning('승인할 지원자를 선택해주세요');
      return;
    }

    // 🔥 현재 확정 인원 확인
    final confirmedApplicants = _applicants
        .where((item) => (item['application'] as ApplicationModel).status == 'CONFIRMED')
        .toList();
    
    final currentConfirmed = confirmedApplicants.length;
    final requiredCount = widget.work.requiredCount;
    final selectedCount = _selectedIds.length;
    final afterConfirm = currentConfirmed + selectedCount;

    // 🔥 인원 초과 체크
    if (afterConfirm > requiredCount) {
      final overflow = afterConfirm - requiredCount;
      
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange[700]),
              SizedBox(width: 8),
              Text('인원 초과'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('현재 확정: $currentConfirmed명'),
              Text('선택 인원: $selectedCount명'),
              Text('필요 인원: $requiredCount명'),
              Divider(height: 24),
              Text(
                '${overflow}명이 초과됩니다.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[700],
                ),
              ),
              SizedBox(height: 8),
              Text('그래도 승인하시겠습니까?'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: Text('초과 승인'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    } else {
      // 🔥 정상 범위 내 승인
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('일괄 승인'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${selectedCount}명을 승인하시겠습니까?'),
              SizedBox(height: 12),
              Text(
                '승인 후: ${afterConfirm}/${requiredCount}명',
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('승인'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid;

      for (var id in _selectedIds) {
        await _firestoreService.updateApplicationStatus(
          applicationId: id,
          status: 'CONFIRMED',
          confirmedBy: adminUID,
        );
      }

      ToastHelper.showSuccess('${_selectedIds.length}명 승인 완료!');
      widget.onChanged();
      
      await _loadApplicants();
      setState(() => _selectedIds.clear());
    } catch (e) {
      print('❌ 일괄 승인 실패: $e');
      ToastHelper.showError('승인 처리에 실패했습니다');
    }
  }

  /// 일괄 거절
  Future<void> _rejectSelected() async {
    if (_selectedIds.isEmpty) {
      ToastHelper.showWarning('거절할 지원자를 선택해주세요');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('일괄 거절'),
        content: Text('${_selectedIds.length}명을 거절하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text('거절'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid;

      for (var id in _selectedIds) {
        await _firestoreService.updateApplicationStatus(
          applicationId: id,
          status: 'REJECTED',
          rejectedBy: adminUID,
        );
      }

      ToastHelper.showSuccess('${_selectedIds.length}명 거절 완료!');
      widget.onChanged();
      
      await _loadApplicants();
      setState(() => _selectedIds.clear());
    } catch (e) {
      print('❌ 일괄 거절 실패: $e');
      ToastHelper.showError('거절 처리에 실패했습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingApplicants = _applicants
        .where((item) => (item['application'] as ApplicationModel).status == 'PENDING')
        .toList();
    final confirmedApplicants = _applicants
        .where((item) => (item['application'] as ApplicationModel).status == 'CONFIRMED')
        .toList();

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // 헤더
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  WorkTypeIcon.buildFromString(
                    widget.work.workTypeIcon,
                    color: FormatHelper.parseColor(widget.work.workTypeColor),
                    size: 24,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.work.workType} - 지원자 관리',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          '${widget.work.startTime}~${widget.work.endTime} | ${widget.work.formattedWage}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),

            // 전체 선택 + 통계
            if (pendingApplicants.isNotEmpty)
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: _selectAll,
                      onChanged: _toggleSelectAll,
                    ),
                    Text(
                      '전체 선택',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    Spacer(),
                    Text(
                      '대기: ${pendingApplicants.length}명',
                      style: TextStyle(
                        color: Colors.orange[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      '확정: ${confirmedApplicants.length}/${widget.work.requiredCount}명',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),

            // 지원자 목록
            Expanded(
              child: _isLoading
                  ? Center(child: CircularProgressIndicator())
                  : _applicants.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                              SizedBox(height: 16),
                              Text(
                                '지원자가 없습니다',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          padding: EdgeInsets.all(16),
                          children: [
                            // 대기 중 지원자
                            if (pendingApplicants.isNotEmpty) ...[
                              Text(
                                '⏳ 대기 중 (${pendingApplicants.length}명)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.orange[700],
                                ),
                              ),
                              SizedBox(height: 8),
                              ...pendingApplicants.map((item) => 
                                _buildApplicantCard(item, true)
                              ),
                              SizedBox(height: 24),
                            ],

                            // 확정된 지원자
                            if (confirmedApplicants.isNotEmpty) ...[
                              Text(
                                '✅ 확정됨 (${confirmedApplicants.length}명)',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green[700],
                                ),
                              ),
                              SizedBox(height: 8),
                              ...confirmedApplicants.map((item) => 
                                _buildApplicantCard(item, false)
                              ),
                            ],
                          ],
                        ),
            ),

            // 하단 버튼
            if (pendingApplicants.isNotEmpty)
              Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Colors.grey[300]!)),
                ),
                child: Row(
                  children: [
                    Text(
                      '선택: ${_selectedIds.length}명',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Spacer(),
                    ElevatedButton.icon(
                      onPressed: _selectedIds.isEmpty ? null : _rejectSelected,
                      icon: Icon(Icons.close, size: 18),
                      label: Text('일괄 거절'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                      ),
                    ),
                    SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: _selectedIds.isEmpty ? null : _approveSelected,
                      icon: Icon(Icons.check, size: 18),
                      label: Text('일괄 승인'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 지원자 카드
  Widget _buildApplicantCard(Map<String, dynamic> item, bool isPending) {
    final app = item['application'] as ApplicationModel;
    final userName = item['userName'] as String;
    final userPhone = item['userPhone'] as String;
    
    final isSelected = _selectedIds.contains(app.id);
    final timeAgo = _getTimeAgo(app.appliedAt);

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isSelected ? Colors.blue[50] : Colors.white,
        border: Border.all(
          color: isSelected ? Colors.blue[300]! : Colors.grey[300]!,
          width: isSelected ? 2 : 1,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: isPending
            ? Checkbox(
                value: isSelected,
                onChanged: (_) => _toggleSelect(app.id),
              )
            : Icon(Icons.check_circle, color: Colors.green[600]),
        title: Text(
          userName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: 4),
            Text(
              userPhone,
              style: TextStyle(fontSize: 13),
            ),
            SizedBox(height: 4),
            Text(
              '$timeAgo 지원',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
        trailing: !isPending
            ? null
            : PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 20),
                onSelected: (value) async {
                  if (value == 'approve') {
                    await _approveSingle(item);
                  } else if (value == 'reject') {
                    await _rejectSingle(item);
                  }
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'approve',
                    child: Row(
                      children: [
                        Icon(Icons.check, size: 18, color: Colors.green),
                        SizedBox(width: 8),
                        Text('승인'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'reject',
                    child: Row(
                      children: [
                        Icon(Icons.close, size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('거절'),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// 개별 승인 (인원 체크 추가!)
  Future<void> _approveSingle(Map<String, dynamic> item) async {
    final app = item['application'] as ApplicationModel;
    final userName = item['userName'] as String;
    
    // 🔥 인원 체크
    final confirmedApplicants = _applicants
        .where((item) => (item['application'] as ApplicationModel).status == 'CONFIRMED')
        .toList();
    
    final currentConfirmed = confirmedApplicants.length;
    final requiredCount = widget.work.requiredCount;

    if (currentConfirmed >= requiredCount) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning, color: Colors.orange[700]),
              SizedBox(width: 8),
              Text('인원 초과'),
            ],
          ),
          content: Text(
            '이미 필요 인원($requiredCount명)이 충족되었습니다.\n그래도 ${userName}님을 승인하시겠습니까?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              child: Text('초과 승인'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    }

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid;

      await _firestoreService.updateApplicationStatus(
        applicationId: app.id,
        status: 'CONFIRMED',
        confirmedBy: adminUID,
      );

      ToastHelper.showSuccess('${userName}님을 승인했습니다');
      widget.onChanged();
      await _loadApplicants();
    } catch (e) {
      print('❌ 승인 실패: $e');
      ToastHelper.showError('승인에 실패했습니다');
    }
  }

  /// 개별 거절
  Future<void> _rejectSingle(Map<String, dynamic> item) async {
    final app = item['application'] as ApplicationModel;
    final userName = item['userName'] as String;
    
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final adminUID = userProvider.currentUser?.uid;

      await _firestoreService.updateApplicationStatus(
        applicationId: app.id,
        status: 'REJECTED',
        rejectedBy: adminUID,
      );

      ToastHelper.showSuccess('${userName}님을 거절했습니다');
      widget.onChanged();
      await _loadApplicants();
    } catch (e) {
      print('❌ 거절 실패: $e');
      ToastHelper.showError('거절에 실패했습니다');
    }
  }

  /// 시간 경과 계산
  String _getTimeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    
    if (diff.inMinutes < 1) return '방금';
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    if (diff.inDays < 7) return '${diff.inDays}일 전';
    return '${(diff.inDays / 7).floor()}주 전';
  }
}