import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';  // ⭐ 추가
import '../../../widgets/work_type_icon.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../models/core/user_model.dart';
import '../../../utils/dialog_helper.dart';



/// 업무별 지원자 관리 다이얼로그
class WorkApplicantsDialog extends StatefulWidget {
  final WorkDetailModel work;
  final TOItem toItem;
  final VoidCallback onChanged;

  const WorkApplicantsDialog({
    super.key,
    required this.work,
    required this.toItem,
    required this.onChanged,
  });

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

      // ✅ 병렬로 사용자 정보 조회 (최적화!)
      final futures = filtered.map((app) async {
        final user = await _firestoreService.getUserByUID(app.uid);
        return {
          'application': app,
          'user': user,  // ⭐ UserModel 전체 저장
          'userName': user?.name ?? '이름 없음',
          'userPhone': user?.phone ?? '전화번호 없음',
          'userEmail': user?.email ?? '',
        };
      }).toList();

      final applicantsWithUserInfo = await Future.wait(futures);

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
              Icon(Icons.warning, color: Theme.of(context).colorScheme.error),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
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
              Divider(height: ResponsiveHelper.spacing(context, 24)),
              Text(
                '$overflow명이 초과됩니다.',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
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
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: Text('초과 승인'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;
    } else {
      final confirmed = await DialogHelper.showConfirm(
        context,
        title: '일괄 승인',
        message: '${_selectedIds.length}명을 승인하시겠습니까?',
        confirmText: '승인',
        confirmColor: Colors.green,
      );

      if (!confirmed) return;
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

    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '일괄 거절',
      message: '${_selectedIds.length}명을 거절하시겠습니까?',
      confirmText: '거절',
      confirmColor: Colors.red,
    );

    if (!confirmed) return;

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
      child: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            // 헤더
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  WorkTypeIcon.buildFromString(
                    widget.work.workTypeIcon,
                    color: FormatHelper.parseColor(widget.work.workTypeColor),
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${widget.work.workType} - 지원자 관리',
                          style: ResponsiveHelper.titleStyle(context),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                        Text(
                          '${widget.work.startTime}~${widget.work.endTime} | ${widget.work.formattedWage}',
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: Theme.of(context).textTheme.bodySmall?.color,
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
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 16),
                  vertical: ResponsiveHelper.spacing(context, 12),
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: Theme.of(context).dividerColor,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Checkbox(
                      value: _selectAll,
                      onChanged: _toggleSelectAll,
                    ),
                    Text(
                      '전체 선택',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Spacer(),
                    Text(
                      '대기: ${pendingApplicants.length}명',
                      style: ResponsiveHelper.bodyStyle(
                        context,
                        color: Colors.orange,
                      ).copyWith(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                    Text(
                      '확정: ${confirmedApplicants.length}/${widget.work.requiredCount}명',
                      style: ResponsiveHelper.bodyStyle(
                        context,
                        color: Theme.of(context).primaryColor,
                      ).copyWith(fontWeight: FontWeight.bold),
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
                              Icon(
                                Icons.inbox, 
                                size: ResponsiveHelper.iconSize(context, 64),
                                color: Theme.of(context).disabledColor,
                              ),
                              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                              Text(
                                '지원자가 없습니다',
                                style: ResponsiveHelper.subtitleStyle(
                                  context,
                                  color: Theme.of(context).textTheme.bodySmall?.color,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView(
                          padding: ResponsiveHelper.cardPadding(context),
                          children: [
                            // 대기 중 지원자
                            if (pendingApplicants.isNotEmpty) ...[
                              Text(
                                '⏳ 대기 중 (${pendingApplicants.length}명)',
                                style: ResponsiveHelper.bodyStyle(
                                  context,
                                  color: Colors.orange,
                                ).copyWith(fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                              ...pendingApplicants.map((item) => 
                                _buildApplicantCard(item, true)
                              ),
                              SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                            ],

                            // 확정된 지원자
                            if (confirmedApplicants.isNotEmpty) ...[
                              Text(
                                '✅ 확정됨 (${confirmedApplicants.length}명)',
                                style: ResponsiveHelper.bodyStyle(
                                  context,
                                  color: Colors.green,
                                ).copyWith(fontWeight: FontWeight.bold),
                              ),
                              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
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
                padding: ResponsiveHelper.cardPadding(context),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Theme.of(context).dividerColor),
                  ),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 넓이가 좁으면 버튼을 작게
                    final isNarrow = constraints.maxWidth < 400;
                    
                    return Wrap(
                      spacing: ResponsiveHelper.spacing(context, 8),
                      runSpacing: ResponsiveHelper.spacing(context, 8),
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '선택: ${_selectedIds.length}명',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            ElevatedButton.icon(
                              onPressed: _selectedIds.isEmpty ? null : _rejectSelected,
                              icon: Icon(
                                Icons.close, 
                                size: ResponsiveHelper.iconSize(
                                  context, 
                                  isNarrow ? 16 : 18,
                                ),
                              ),
                              label: Text(isNarrow ? '거절' : '일괄 거절'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.red,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  horizontal: ResponsiveHelper.spacing(
                                    context, 
                                    isNarrow ? 12 : 16,
                                  ),
                                  vertical: ResponsiveHelper.spacing(
                                    context, 
                                    isNarrow ? 8 : 12,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                            ElevatedButton.icon(
                              onPressed: _selectedIds.isEmpty ? null : _approveSelected,
                              icon: Icon(
                                Icons.check, 
                                size: ResponsiveHelper.iconSize(
                                  context, 
                                  isNarrow ? 16 : 18,
                                ),
                              ),
                              label: Text(isNarrow ? '승인' : '일괄 승인'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).primaryColor,
                                foregroundColor: Colors.white,
                                padding: EdgeInsets.symmetric(
                                  horizontal: ResponsiveHelper.spacing(
                                    context, 
                                    isNarrow ? 12 : 16,
                                  ),
                                  vertical: ResponsiveHelper.spacing(
                                    context, 
                                    isNarrow ? 8 : 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
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
    final user = item['user'] as UserModel?;
    final userName = item['userName'] as String;
    final userPhone = item['userPhone'] as String;
    
    final isSelected = _selectedIds.contains(app.id);
    final timeAgo = _getTimeAgo(app.appliedAt);

    // ⭐ 이름 + 나이 + 성별
    String displayName = userName;
    if (user != null) {
      final List<String> extras = [];
      if (user.age != null) extras.add('${user.age}세');
      if (user.gender != null) extras.add(user.gender!);
      
      if (extras.isNotEmpty) {
        displayName += ' (${extras.join(', ')})';
      }
    }

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      decoration: BoxDecoration(
        color: isSelected 
            ? Theme.of(context).primaryColor.withOpacity(0.1) 
            : Theme.of(context).cardColor,
        border: Border.all(
          color: isSelected 
              ? Theme.of(context).primaryColor 
              : Theme.of(context).dividerColor,
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
            : Icon(Icons.check_circle, color: Colors.green),
        title: Text(
          displayName,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              userPhone,
              style: ResponsiveHelper.smallStyle(context),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              '$timeAgo 지원',
              style: ResponsiveHelper.tinyStyle(
                context,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
            // ⭐ Phase 1-C: 장기 계약 정보 표시
            if (app.isLongTermApplication) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(
                  color: Colors.purple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.purple.withOpacity(0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 첫 줄: 아이콘 + 근무 기간
                    Row(
                      children: [
                        Icon(
                          Icons.event_note, 
                          size: ResponsiveHelper.iconSize(context, 12),
                          color: Colors.purple,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                        Flexible(
                          child: Text(
                            '장기: ${app.workPeriodDisplay}',
                            style: ResponsiveHelper.tinyStyle(
                              context,
                              color: Colors.purple,
                            ).copyWith(fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    // 둘째 줄: 근무 요일
                    if (app.workDaysDisplay != null) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                      Text(
                        app.workDaysDisplay!,
                        style: ResponsiveHelper.tinyStyle(
                          context,
                          color: Colors.purple,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
        trailing: IconButton(
          icon: Icon(
            Icons.info_outline, 
            size: ResponsiveHelper.iconSize(context, 20),
            color: Theme.of(context).primaryColor,
          ),
          onPressed: () => _showApplicantDetail(item),
          tooltip: '상세 정보',
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
              Icon(Icons.warning, color: Theme.of(context).colorScheme.error),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text('인원 초과'),
            ],
          ),
          content: Text(
            '이미 필요 인원($requiredCount명)이 충족되었습니다.\n그래도 $userName님을 승인하시겠습니까?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('취소'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
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

      ToastHelper.showSuccess('$userName님을 승인했습니다');
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

      ToastHelper.showSuccess('$userName님을 거절했습니다');
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
  
  /// 지원자 상세 정보
  void _showApplicantDetail(Map<String, dynamic> item) {
    final app = item['application'] as ApplicationModel;
    final user = item['user'] as UserModel?;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${user?.name ?? '이름 없음'} - 상세 정보'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('이름', user?.name ?? '-'),
                _buildDetailRow('나이', user?.age != null ? '${user!.age}세' : '-'),
                _buildDetailRow('성별', user?.gender ?? '-'),
                _buildDetailRow('연락처', user?.phone ?? '-'),
                if (user?.address != null)
                  _buildDetailRow('주소', '${user!.address}${user.detailAddress != null ? ' ${user.detailAddress}' : ''}'),
                Divider(height: ResponsiveHelper.spacing(context, 24)),
                _buildDetailRow('지원 시각', DateFormat('yyyy-MM-dd HH:mm').format(app.appliedAt)),
                _buildDetailRow('상태', _getStatusText(app.status)),
                if (user?.bio != null) ...[
                  Divider(height: ResponsiveHelper.spacing(context, 24)),
                  Text(
                    '자기소개', 
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Text(user!.bio!),
                ],
                Divider(height: ResponsiveHelper.spacing(context, 24)),
                Text(
                  '근무 통계', 
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildDetailRow('총 근무', '${user?.totalWorkDays ?? 0}일'),
                _buildDetailRow('평균 평점', '${user?.averageRating.toStringAsFixed(1) ?? '0.0'}점'),
                _buildDetailRow('무단결근', '${user?.noShowCount ?? 0}회'),
                _buildDetailRow('지각', '${user?.lateCount ?? 0}회'),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('닫기'),
          ),
          if (app.status == 'PENDING') ...[
            TextButton(
              onPressed: () {
                Navigator.pop(context);
                _rejectSingle(item);
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: Text('거절'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _approveSingle(item);
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: Text('승인'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
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
              style: ResponsiveHelper.bodyStyle(context),
            ),
          ),
        ],
      ),
    );
  }

  String _getStatusText(String status) {
    switch (status) {
      case 'PENDING': return '대기중';
      case 'CONFIRMED': return '확정';
      case 'REJECTED': return '거절됨';
      case 'CANCELED': return '취소됨';
      default: return status;
    }
  }
}