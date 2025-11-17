import 'package:flutter/material.dart';
import '../../models/core/application_model.dart';
import '../../utils/dialog_helper.dart';
import '../../services/firestore_service.dart';
import '../../utils/toast_helper.dart';
import '../dialogs/schedule_detail_dialog.dart';
import '../../models/core/schedule_change_request_model.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';

/// 개별 일정 카드
class ScheduleCard extends StatelessWidget {
  final ApplicationModel application;
  final VoidCallback? onChanged;  // ⭐ 추가
  final DateTime? selectedDay;
  
  const ScheduleCard({
    super.key,
    required this.application,
    this.onChanged,
    this.selectedDay, 
  });
  
  @override
  Widget build(BuildContext context) {
    final statusInfo = _getStatusInfo(application.status);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: application.status == 'CONFIRMED' ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: application.status == 'CONFIRMED'
            ? BorderSide(color: Colors.green[300]!, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _showDetailDialog(context),  // ⭐ 카드 클릭
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: application.status == 'CONFIRMED'
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [Colors.green[50]!, Colors.white],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                )
              : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더: 사업장명 + 상태
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        application.businessName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    _buildStatusBadge(statusInfo),
                  ],
                ),
                
                const SizedBox(height: 12),
                // ⭐ 휴무/추가근무 표시
                if (selectedDay != null && application.isLongTermApplication) ...[
                  if (application.isLeaveDateOn(selectedDay!))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.block, size: 14, color: Colors.grey[700]),
                          const SizedBox(width: 4),
                          Text(
                            '휴무일',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (application.isExtraWorkDateOn(selectedDay!))
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green[100],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_circle, size: 14, color: Colors.green[700]),
                          const SizedBox(width: 4),
                          Text(
                            '추가 근무일',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 8),
                ],
                
                // 시간 정보
                Row(
                  children: [
                    Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      '${application.startTime} ~ ${application.endTime}',
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // 업무 유형
                Row(
                  children: [
                    Icon(Icons.work_outline, size: 16, color: Colors.grey[600]),
                    const SizedBox(width: 6),
                    Text(
                      application.selectedWorkType,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
                
                const SizedBox(height: 8),
                
                // 금액
                Row(
                  children: [
                    Icon(Icons.attach_money, size: 16, color: Colors.green[600]),
                    const SizedBox(width: 6),
                    Text(
                      application.formattedWage,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[700],
                      ),
                    ),
                  ],
                ),
                
                // 장기 근무 정보
                if (application.isLongTermApplication) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.purple[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.purple[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_month, size: 14, color: Colors.purple[700]),
                        const SizedBox(width: 6),
                        Text(
                          '${application.workPeriodDisplay} ${application.workDaysDisplay ?? ""}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.purple[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // ⭐ 액션 버튼들
                if (application.status == 'PENDING' || application.status == 'CONFIRMED') ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      // 상세 보기 버튼
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showDetailDialog(context),
                          icon: const Icon(Icons.info_outline, size: 18),
                          label: const Text('상세 정보'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue,
                            side: const BorderSide(color: Colors.blue),
                          ),
                        ),
                      ),
                      
                      const SizedBox(width: 8),
                      
                      // 취소/휴무 버튼
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _handleCancel(context),
                          icon: Icon(
                            application.isLongTermApplication && application.status == 'CONFIRMED'
                                ? Icons.beach_access  // 장기 확정: 휴무 아이콘
                                : Icons.cancel_outlined,  // 그 외: 취소 아이콘
                            size: 18,
                          ),
                          label: Text(
                            application.isLongTermApplication && application.status == 'CONFIRMED'
                                ? '휴무 요청'  // ⭐ 장기 확정: 휴무 요청
                                : application.status == 'CONFIRMED'
                                    ? '취소 요청'  // 단기 확정: 취소 요청
                                    : '지원 취소'  // 대기중: 지원 취소
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// 상세 정보 다이얼로그
  void _showDetailDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => ScheduleDetailDialog(application: application),
    );
  }
  
  /// 지원 취소 처리
  Future<void> _handleCancel(BuildContext context) async {
    final firestoreService = FirestoreService();
    
    // ⭐ 장기 근무 확정 → 휴무 요청
    if (application.isLongTermApplication && application.status == 'CONFIRMED') {
      await _showLeaveRequestDialog(context);
      return;
    }
    
    // 단기 근무 확정 → 취소 요청
    if (application.status == 'CONFIRMED') {
      // ⭐ 확정된 경우 - 패널티 경고 후 취소 가능
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange[700], size: 28),
              const SizedBox(width: 8),
              const Text('확정 근무 취소'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '확정된 근무를 취소하시겠습니까?',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red[200]!),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.error_outline, color: Colors.red[700], size: 20),
                        const SizedBox(width: 6),
                        Text(
                          '⚠️ 주의사항',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.red[900],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '• 확정 취소 시 패널티가 부과될 수 있습니다.\n'
                      '• 반복적인 취소는 향후 지원에 불이익이 있을 수 있습니다.\n'
                      '• 부득이한 사유가 있는 경우 관리자에게 먼저 연락해주세요.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.red[800],
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                '그래도 취소하시겠습니까?',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('돌아가기'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('취소하기'),
            ),
          ],
        ),
      );
      
      if (confirmed != true) return;
      
      // 확정 취소 처리
      final success = await firestoreService.cancelApplication(
        application.id,
        application.uid,
      );
      
      if (success && context.mounted) {
        ToastHelper.showSuccess('근무가 취소되었습니다.');
        onChanged?.call();
      }
      
    } else if (application.status == 'PENDING') {
      // ⭐ 대기중인 경우 - 간단한 확인 후 취소
      final confirmed = await DialogHelper.showCancelConfirm(
        context,
        title: '지원 취소',
        message: '정말 지원을 취소하시겠습니까?',
      );
      
      if (!confirmed) return;
      
      final success = await firestoreService.cancelApplication(
        application.id,
        application.uid,
      );
      
      if (success && context.mounted) {
        ToastHelper.showSuccess('지원이 취소되었습니다.');
        onChanged?.call();
      }
    }
  }
  /// 상태 정보 가져오기
  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case 'CONFIRMED':
        return _StatusInfo(
          color: Colors.green,
          text: '확정',
          icon: Icons.check_circle,
        );
      case 'PENDING':
        return _StatusInfo(
          color: Colors.orange,
          text: '대기중',
          icon: Icons.schedule,
        );
      case 'REJECTED':
        return _StatusInfo(
          color: Colors.red,
          text: '거절',
          icon: Icons.cancel,
        );
      case 'CANCELED':
        return _StatusInfo(
          color: Colors.grey,
          text: '취소',
          icon: Icons.remove_circle_outline,
        );
      case 'AUTO_CANCELED':
        return _StatusInfo(
          color: Colors.orange,
          text: '자동 취소',
          icon: Icons.block,
        );
      default:
        return _StatusInfo(
          color: Colors.grey,
          text: '알 수 없음',
          icon: Icons.help_outline,
        );
    }
  }
  
  /// 상태 배지
  Widget _buildStatusBadge(_StatusInfo info) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: info.color[50],
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: info.color[300]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            info.icon,
            size: 14,
            color: info.color[700],
          ),
          const SizedBox(width: 4),
          Text(
            info.text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: info.color[700],
            ),
          ),
        ],
      ),
    );
  }
  /// ⭐ 휴무 요청 다이얼로그 (장기 근무용)
  Future<void> _showLeaveRequestDialog(BuildContext context) async {
    if (selectedDay == null) {
      ToastHelper.showWarning('날짜 정보를 찾을 수 없습니다');
      return;
    }

    final reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.beach_access, color: Colors.orange),
            SizedBox(width: 8),
            Text('휴무 요청'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(selectedDay!)}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text('${application.toTitle} - ${application.selectedWorkType}'),
            const Divider(height: 24),
            const Text('휴무 사유', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: '휴무 사유를 입력하세요',
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange,
            ),
            child: const Text('요청'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 휴무 요청 생성
    final firestoreService = FirestoreService();
    
    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: application.businessId,
      applicationId: application.id,
      applicantUid: application.uid,
      applicantName: '', // ⚠️ 실제 구현 시 UserProvider에서 가져와야 함
      targetDate: DateTime(selectedDay!.year, selectedDay!.month, selectedDay!.day),
      requestType: RequestType.LEAVE,
      requestedBy: RequesterType.APPLICANT,
      requestedByUid: application.uid,
      requestedAt: DateTime.now(),
      reason: reasonController.text.trim().isEmpty 
          ? null 
          : reasonController.text.trim(),
      wageAmount: application.wage,
    );

    final requestId = await firestoreService.createScheduleChangeRequest(request);

    if (requestId != null && context.mounted) {
      ToastHelper.showSuccess('휴무 요청이 전송되었습니다');
      onChanged?.call();
    } else {
      ToastHelper.showError('휴무 요청 실패');
    }
  }
}

/// 상태 정보 클래스
class _StatusInfo {
  final MaterialColor color;
  final String text;
  final IconData icon;
  
  _StatusInfo({
    required this.color,
    required this.text,
    required this.icon,
  });
}