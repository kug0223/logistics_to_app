import 'package:flutter/material.dart';
import '../../models/core/application_model.dart';
import '../../utils/dialog_helper.dart';
import '../../services/firestore_service.dart';
import '../../utils/toast_helper.dart';
import '../dialogs/schedule_detail_dialog.dart';

/// 개별 일정 카드
class ScheduleCard extends StatelessWidget {
  final ApplicationModel application;
  final VoidCallback? onChanged;  // ⭐ 추가
  
  const ScheduleCard({
    super.key,
    required this.application,
    this.onChanged,
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
                      
                      // 취소 버튼
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _handleCancel(context),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: Text(
                            application.status == 'CONFIRMED' ? '취소 요청' : '지원 취소'
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