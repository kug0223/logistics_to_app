import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/schedule_change_request_model.dart';
import '../../../models/core/user_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../widgets/common/loading_widget.dart';

/// 고정근무자 관리 다이얼로그 (탭 구조)
class FixedWorkerManagementDialog extends StatefulWidget {
  final String businessId;
  final VoidCallback onChanged;

  const FixedWorkerManagementDialog({
    super.key,
    required this.businessId,
    required this.onChanged,
  });

  @override
  State<FixedWorkerManagementDialog> createState() => _FixedWorkerManagementDialogState();
}

class _FixedWorkerManagementDialogState extends State<FixedWorkerManagementDialog>
    with SingleTickerProviderStateMixin {
  final FirestoreService _firestoreService = FirestoreService();

  // 고정근무자 목록
  List<ApplicationModel> _fixedWorkers = [];
  bool _isLoadingWorkers = true;

  @override
  void initState() {
    super.initState();
    // 알림 탭 제거 - 고정근무자 탭만 사용
    _loadData();
  }

  @override
  void dispose() {
    // TabController 제거됨
    super.dispose();
  }

  /// 데이터 로드
  Future<void> _loadData() async {
    await _loadFixedWorkers();
  }

  /// 고정근무자 로드
  Future<void> _loadFixedWorkers() async {
    setState(() => _isLoadingWorkers = true);

    try {
      // 장기 근무 확정 지원자만 조회
      final allApps = await _firestoreService.getApplicationsByBusinessId(widget.businessId);
      
      _fixedWorkers = allApps.where((app) {
        return app.status == 'CONFIRMED' && 
               app.workEndDate != null && 
               app.resignStatus != 'APPROVED' &&
               app.resignStatus != 'AUTO_APPROVED';
      }).toList();

      // 최신순 정렬
      _fixedWorkers.sort((a, b) => b.confirmedAt!.compareTo(a.confirmedAt!));

    } catch (e) {
      print('❌ 고정근무자 로드 실패: $e');
    } finally {
      setState(() => _isLoadingWorkers = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.92,
        height: MediaQuery.of(context).size.height * 0.8,
        constraints: const BoxConstraints(maxWidth: 500),
        padding: ResponsiveHelper.cardPadding(context),
        child: Column(
          children: [
            // 헤더
            Row(
              children: [
                Icon(
                  Icons.manage_accounts, 
                  size: ResponsiveHelper.iconSize(context, 28),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Text(
                  '고정근무자 관리',
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            
            Divider(height: ResponsiveHelper.spacing(context, 24)),

            // 고정근무자 수 표시
            Padding(
              padding: EdgeInsets.only(
                bottom: ResponsiveHelper.spacing(context, 12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.people,
                    size: ResponsiveHelper.iconSize(context, 20),
                    color: Theme.of(context).primaryColor,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    '총 ${_fixedWorkers.length}명',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
                ],
              ),
            ),

            // 고정근무자 목록
            Expanded(
              child: _buildWorkersTab(),
            ),
          ],
        ),
      ),
    );
  }

  /// 고정근무자 탭
  Widget _buildWorkersTab() {
    if (_isLoadingWorkers) {
      return const LoadingWidget(message: '고정근무자 로딩 중...');
    }

    if (_fixedWorkers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.people_outline, 
              size: ResponsiveHelper.iconSize(context, 64),  // ⭐ 변경
              color: Theme.of(context).disabledColor,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
            Text(
              '고정근무자가 없습니다',
              style: ResponsiveHelper.subtitleStyle(  // ⭐ 변경
                context,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(  // ⭐ const 제거
        vertical: ResponsiveHelper.spacing(context, 16),  // ⭐ 변경
      ),
      itemCount: _fixedWorkers.length,
      itemBuilder: (context, index) {
        final app = _fixedWorkers[index];
        return _buildWorkerCard(app);
      },
    );
  }

  /// 근무자 카드
  Widget _buildWorkerCard(ApplicationModel app) {
    return FutureBuilder<UserModel?>(
      future: _firestoreService.getUserByUID(app.uid),
      builder: (context, snapshot) {
        final user = snapshot.data;
        final name = user?.name ?? '이름 없음';
        final phone = user?.phone ?? '전화번호 없음';

        return Card(
          margin: EdgeInsets.only(  // ⭐ const 제거
            bottom: ResponsiveHelper.spacing(context, 12),  // ⭐ 변경
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).primaryColor.withOpacity(0.2),
              child: Text(
                name.isNotEmpty ? name[0] : '?',
                style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            title: Text(
              name,
              style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                fontWeight: FontWeight.bold,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${app.selectedWorkType} · ${_formatWorkDays(app.workDays)}'),
                Text(
                  '${DateFormat('M/d').format(app.workDate)} ~ ${DateFormat('M/d').format(app.workEndDate!)}',
                  style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                    context,
                    color: Theme.of(context).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),
            trailing: TextButton(
              onPressed: () => _showWorkerDetailDialog(app, user),
              child: const Text('자세히'),
            ),
          ),
        );
      },
    );
  }

  /// 근무 요일 포맷
  String _formatWorkDays(List<String>? workDays) {
    if (workDays == null || workDays.isEmpty) return '매일';
    if (workDays.length == 7) return '매일';
    return workDays.join(', ');
  }

  /// 근무자 상세 다이얼로그
  Future<void> _showWorkerDetailDialog(ApplicationModel app, UserModel? user) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.person),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
            const Text('근무자 상세 정보'),
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 기본 정보
                _buildInfoRow('이름', user?.name ?? '이름 없음'),
                _buildInfoRow('성별·나이', user?.gender != null && user?.age != null 
                    ? '${user!.gender} · ${user.age}세' 
                    : '-'),
                _buildInfoRow('연락처', user?.phone ?? '전화번호 없음'),
                _buildInfoRow('주소', user?.address ?? '-'),
                
                Divider(height: ResponsiveHelper.spacing(context, 24)),  // ⭐ 변경
                
                // 급여 정보
                Text(
                  '💳 급여 정보', 
                  style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                _buildInfoRow('은행', user?.bankName ?? '-'),
                _buildInfoRow('계좌번호', user?.accountNumber ?? '-'),
                _buildInfoRow('예금주', user?.accountHolder ?? '-'),
                
                Divider(height: ResponsiveHelper.spacing(context, 24)),  // ⭐ 변경
                
                // 신분증 인증
                Row(
                  children: [
                    Icon(
                      user?.isIdVerified == true ? Icons.verified : Icons.warning,
                      color: user?.isIdVerified == true ? Colors.green : Colors.orange,
                      size: ResponsiveHelper.iconSize(context, 20),  // ⭐ 변경
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                    Text(
                      user?.isIdVerified == true 
                          ? '신분증 인증 완료 (${user?.idCardVerifiedAt != null ? DateFormat('yyyy.MM.dd').format(user!.idCardVerifiedAt!) : '-'})'
                          : '신분증 미인증',
                      style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                        context,
                        color: user?.isIdVerified == true ? Colors.green : Colors.orange,
                      ),
                    ),
                  ],
                ),
                
                Divider(height: ResponsiveHelper.spacing(context, 24)),  // ⭐ 변경
                
                // 근무 이력
                Text(
                  '📊 근무 이력', 
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildInfoRow('총 근무', user != null ? '${user.totalWorkDays}일 (${user.totalWorkHours}시간)' : '-'),
                _buildInfoRow('평균 평점', user != null && user.averageRating > 0
                    ? '⭐ ${user.averageRating.toStringAsFixed(1)} (${user.reviewCount}개)'
                    : '-'),
                _buildInfoRow('무단결근', user != null ? '${user.noShowCount}회 · 지각: ${user.lateCount}회' : '-'),
                
                Divider(height: ResponsiveHelper.spacing(context, 24)),  // ⭐ 변경
                
                // 계약 정보
                Text(
                  '💼 계약 정보', 
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _buildInfoRow('업무', '${app.selectedWorkType} · 시급 ${NumberFormat('#,###').format(app.wage)}원'),
                _buildInfoRow('계약 기간', 
                    '${DateFormat('yyyy.MM.dd').format(app.workDate)} ~ ${DateFormat('yyyy.MM.dd').format(app.workEndDate!)}'),
                _buildInfoRow('근무 요일', _formatWorkDays(app.workDays)),
                
                if (user?.bio != null && user!.bio!.isNotEmpty) ...[
                  Divider(height: ResponsiveHelper.spacing(context, 24)),  // ⭐ 변경
                  Text(
                    '📝 자기소개', 
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Text(user.bio!, style: ResponsiveHelper.bodyStyle(context)),
                ],
              ],
            ),
          ),
        ),
        actions: [
          // 버튼들을 Column으로 세로 배치
          SizedBox(
            width: double.infinity,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 추가 근무 요청 (초록)
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showExtraWorkRequestDialog(app);
                  },
                  icon: Icon(Icons.add_circle, size: ResponsiveHelper.iconSize(context, 20)),
                  label: const Text('추가 근무 요청'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 14),
                    ),
                  ),
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showNoWorkRequestDialog(app);
                  },
                  icon: Icon(Icons.block, size: ResponsiveHelper.iconSize(context, 20)),
                  label: const Text('미출근 요청'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 14),
                    ),
                  ),
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                TextButton(
                  onPressed: () => Navigator.pop(context),
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 14),
                    ),
                  ),
                  child: const Text('닫기'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 정보 행
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 8),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final labelWidth = constraints.maxWidth < 300 ? 60.0 : 80.0;
          
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: labelWidth,
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
          );
        },
      ),
    );
  }

  /// 미출근 요청 다이얼로그
  Future<void> _showNoWorkRequestDialog(ApplicationModel app) async {
    // ⭐ 선택 가능한 첫 날짜 찾기
    DateTime? findFirstSelectableDate() {
      final now = DateTime.now();
      final workStart = DateTime(app.workDate.year, app.workDate.month, app.workDate.day);
      final workEnd = DateTime(app.workEndDate!.year, app.workEndDate!.month, app.workEndDate!.day);
      
      // 오늘부터 시작해서 선택 가능한 날짜 찾기
      DateTime checkDate = now.isAfter(workStart) ? now : workStart;
      
      for (int i = 0; i < 365; i++) {
        final targetDate = DateTime(checkDate.year, checkDate.month, checkDate.day);
        
        // 근무 기간 체크
        if (targetDate.isBefore(workStart) || targetDate.isAfter(workEnd)) {
          checkDate = checkDate.add(const Duration(days: 1));
          continue;
        }
        
        // 근무 요일 체크
        if (app.workDays != null && app.workDays!.isNotEmpty) {
          final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
          final dayOfWeek = weekdays[checkDate.weekday - 1];
          if (!app.workDays!.contains(dayOfWeek)) {
            checkDate = checkDate.add(const Duration(days: 1));
            continue;
          }
        }
        
        // 이미 휴무 처리된 날짜 체크
        if (app.leaveDates != null) {
          final alreadyLeave = app.leaveDates!.any((d) =>
              d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day);
          if (alreadyLeave) {
            checkDate = checkDate.add(const Duration(days: 1));
            continue;
          }
        }
        
        // 선택 가능한 날짜 발견!
        return checkDate;
      }
      
      return null;
    }

    final initialDate = findFirstSelectableDate();

    if (initialDate == null) {
      ToastHelper.showWarning('미출근 요청 가능한 날짜가 없습니다');
      return;
    }

    final DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,  // ⭐ 수정!
      firstDate: DateTime.now(),
      lastDate: app.workEndDate ?? DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
            ),
          ),
          child: child!,
        );
      },
      selectableDayPredicate: (DateTime date) {
        final workStart = DateTime(app.workDate.year, app.workDate.month, app.workDate.day);
        final workEnd = DateTime(app.workEndDate!.year, app.workEndDate!.month, app.workEndDate!.day);
        final targetDate = DateTime(date.year, date.month, date.day);
        
        if (targetDate.isBefore(workStart) || targetDate.isAfter(workEnd)) {
          return false;
        }
        
        if (app.workDays != null && app.workDays!.isNotEmpty) {
          final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
          final dayOfWeek = weekdays[date.weekday - 1];
          if (!app.workDays!.contains(dayOfWeek)) {
            return false;
          }
        }
        
        if (app.leaveDates != null) {
          final alreadyLeave = app.leaveDates!.any((d) =>
              d.year == date.year && d.month == date.month && d.day == date.day);
          if (alreadyLeave) return false;
        }
        
        return true;
      },
    );

    if (selectedDate == null) return;

    final reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.block, color: Colors.red),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
            const Text('미출근 요청'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(selectedDate),
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text('근무자: ${app.uid}'),
            Divider(height: ResponsiveHelper.spacing(context, 24)),  // ⭐ 변경
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline, 
                    color: Colors.orange,
                    size: ResponsiveHelper.iconSize(context, 20)
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      '해당 날짜에 근무하지 않아도 됨을 알립니다',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: Colors.orange,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '요청 사유', 
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: '미출근 요청 사유를 입력하세요',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('요청'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final userProvider = context.read<UserProvider>();
    final adminUid = userProvider.currentUser?.uid;
    final adminName = userProvider.currentUser?.name;

    if (adminUid == null || adminName == null) {
      ToastHelper.showError('관리자 정보를 찾을 수 없습니다');
      return;
    }

    final worker = await _firestoreService.getUserByUID(app.uid);
    final workerName = worker?.name ?? '이름 없음';

    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: widget.businessId,
      applicationId: app.id,
      applicantUid: app.uid,
      applicantName: workerName,
      targetDate: DateTime(selectedDate.year, selectedDate.month, selectedDate.day),
      requestType: RequestType.NO_WORK,
      requestedBy: RequesterType.ADMIN,
      requestedByUid: adminUid,
      requestedAt: DateTime.now(),
      reason: reasonController.text.trim().isEmpty 
          ? null 
          : reasonController.text.trim(),
      wageAmount: app.wage,
    );

    final requestId = await _firestoreService.createScheduleChangeRequest(request);

    if (requestId != null) {
      ToastHelper.showSuccess('미출근 요청이 전송되었습니다');
      widget.onChanged();
    } else {
      ToastHelper.showError('미출근 요청 실패');
    }
  }

  /// 추가 근무 요청 다이얼로그
  Future<void> _showExtraWorkRequestDialog(ApplicationModel app) async {
    // ⭐ 선택 가능한 첫 날짜 찾기
    DateTime? findFirstSelectableDate() {
      final now = DateTime.now();
      final workStart = DateTime(app.workDate.year, app.workDate.month, app.workDate.day);
      final workEnd = DateTime(app.workEndDate!.year, app.workEndDate!.month, app.workEndDate!.day);
      
      // 오늘부터 시작해서 선택 가능한 날짜 찾기
      DateTime checkDate = now.isAfter(workStart) ? now : workStart;
      
      for (int i = 0; i < 365; i++) {
        final targetDate = DateTime(checkDate.year, checkDate.month, checkDate.day);
        
        // 근무 기간 체크
        if (targetDate.isBefore(workStart) || targetDate.isAfter(workEnd)) {
          checkDate = checkDate.add(const Duration(days: 1));
          continue;
        }
        
        // 원래 근무일 여부 확인
        bool isOriginalWorkDay = false;
        if (app.workDays != null && app.workDays!.isNotEmpty) {
          final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
          final dayOfWeek = weekdays[checkDate.weekday - 1];
          isOriginalWorkDay = app.workDays!.contains(dayOfWeek);
        } else {
          isOriginalWorkDay = true;
        }
        
        // 원래 근무일인 경우
        if (isOriginalWorkDay) {
          // 휴무 처리된 날만 선택 가능
          if (app.leaveDates != null) {
            final isLeaveDay = app.leaveDates!.any((d) =>
                d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day);
            if (isLeaveDay) {
              return checkDate;
            }
          }
          checkDate = checkDate.add(const Duration(days: 1));
          continue;
        }
        
        // 원래 근무일이 아닌 경우
        // 이미 추가 근무 처리된 날짜 체크
        if (app.extraWorkDates != null) {
          final alreadyExtra = app.extraWorkDates!.any((d) =>
              d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day);
          if (alreadyExtra) {
            checkDate = checkDate.add(const Duration(days: 1));
            continue;
          }
        }
        
        // 선택 가능한 날짜 발견!
        return checkDate;
      }
      
      return null;
    }

    final initialDate = findFirstSelectableDate();

    if (initialDate == null) {
      ToastHelper.showWarning('추가 근무 요청 가능한 날짜가 없습니다');
      return;
    }

    final DateTime? selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,  // ⭐ 수정!
      firstDate: DateTime.now(),
      lastDate: app.workEndDate ?? DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
            ),
          ),
          child: child!,
        );
      },
      selectableDayPredicate: (DateTime date) {
        final workStart = DateTime(app.workDate.year, app.workDate.month, app.workDate.day);
        final workEnd = DateTime(app.workEndDate!.year, app.workEndDate!.month, app.workEndDate!.day);
        final targetDate = DateTime(date.year, date.month, date.day);
        
        if (targetDate.isBefore(workStart) || targetDate.isAfter(workEnd)) {
          return false;
        }
        
        bool isOriginalWorkDay = false;
        if (app.workDays != null && app.workDays!.isNotEmpty) {
          final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
          final dayOfWeek = weekdays[date.weekday - 1];
          isOriginalWorkDay = app.workDays!.contains(dayOfWeek);
        } else {
          isOriginalWorkDay = true;
        }
        
        if (isOriginalWorkDay) {
          if (app.leaveDates != null) {
            final isLeaveDay = app.leaveDates!.any((d) =>
                d.year == date.year && d.month == date.month && d.day == date.day);
            if (isLeaveDay) {
              return true;
            }
          }
          return false;
        }
        
        if (app.extraWorkDates != null) {
          final alreadyExtra = app.extraWorkDates!.any((d) =>
              d.year == date.year && d.month == date.month && d.day == date.day);
          if (alreadyExtra) return false;
        }
        
        return true;
      },
    );

    if (selectedDate == null) return;

    final reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.add_circle, color: Colors.green),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
            const Text('추가 근무 요청'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(selectedDate),
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text('근무자: ${app.uid}'),
            Text('추가 급여: ${NumberFormat('#,###').format(app.wage)}원'),
            Divider(height: ResponsiveHelper.spacing(context, 24)),  // ⭐ 변경
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline, 
                    color: Colors.green,
                    size: ResponsiveHelper.iconSize(context, 20)
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      '해당 날짜에 추가 근무를 요청합니다',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '요청 사유', 
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: '추가 근무 요청 사유를 입력하세요',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('요청'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final userProvider = context.read<UserProvider>();
    final adminUid = userProvider.currentUser?.uid;
    final adminName = userProvider.currentUser?.name;

    if (adminUid == null || adminName == null) {
      ToastHelper.showError('관리자 정보를 찾을 수 없습니다');
      return;
    }

    final worker = await _firestoreService.getUserByUID(app.uid);
    final workerName = worker?.name ?? '이름 없음';

    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: widget.businessId,
      applicationId: app.id,
      applicantUid: app.uid,
      applicantName: workerName,
      targetDate: DateTime(selectedDate.year, selectedDate.month, selectedDate.day),
      requestType: RequestType.EXTRA_WORK,
      requestedBy: RequesterType.ADMIN,
      requestedByUid: adminUid,
      requestedAt: DateTime.now(),
      reason: reasonController.text.trim().isEmpty 
          ? null 
          : reasonController.text.trim(),
      wageAmount: app.wage,
    );

    final requestId = await _firestoreService.createScheduleChangeRequest(request);

    if (requestId != null) {
      ToastHelper.showSuccess('추가 근무 요청이 전송되었습니다');
      widget.onChanged();
    } else {
      ToastHelper.showError('추가 근무 요청 실패');
    }
  }
}