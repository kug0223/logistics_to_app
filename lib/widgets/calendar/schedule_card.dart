import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/core/application_model.dart';
import '../../utils/dialog_helper.dart';
import '../../services/firestore_service.dart';
import '../../utils/toast_helper.dart';
import '../../utils/responsive_helper.dart';  // ⭐ 추가
import '../dialogs/schedule_detail_dialog.dart';
import '../../models/core/schedule_change_request_model.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';

/// 개별 일정 카드
class ScheduleCard extends StatelessWidget {
  final ApplicationModel application;
  final VoidCallback? onChanged;
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
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 12),
      ),
      elevation: application.status == 'CONFIRMED' ? 3 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: application.status == 'CONFIRMED'
            ? BorderSide(color: Colors.green[300]!, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () => _showDetailDialog(context),
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
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ⭐ 첫 줄: 사업장명 + 상태
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        application.businessName,
                        style: ResponsiveHelper.subtitleStyle(context),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    _buildStatusBadge(context, statusInfo),
                  ],
                ),
                
                // ⭐ 두 번째 줄: 휴무/추가근무/요청 배지들
                if (selectedDay != null && application.isLongTermApplication) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      // 휴무 배지
                      if (application.isLeaveDateOn(selectedDay!))
                        _buildSmallBadge(
                          context,
                          icon: Icons.block,
                          label: '휴무',
                          color: Colors.grey,
                        ),
                      
                      // 추가근무 배지
                      if (application.isExtraWorkDateOn(selectedDay!))
                        _buildSmallBadge(
                          context,
                          icon: Icons.add_circle,
                          label: '추가근무',
                          color: Colors.green,
                        ),
                      
                      // 요청 대기중 배지
                      FutureBuilder<ScheduleChangeRequestModel?>(
                        future: _getPendingRequest(selectedDay!),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || snapshot.data == null) {
                            return const SizedBox.shrink();
                          }
                          
                          final request = snapshot.data!;
                          String label;
                          Color color;
                          IconData icon;
                          
                          if (request.requestType == RequestType.LEAVE) {
                            label = '휴무요청중';
                            color = Colors.orange;
                            icon = Icons.beach_access;
                          } else if (request.requestType == RequestType.CANCEL_LEAVE) {
                            label = '휴무취소중';
                            color = Colors.blue;
                            icon = Icons.refresh;
                          } else if (request.requestType == RequestType.CANCEL_EXTRA) {
                            label = '근무취소중';
                            color = Colors.red;
                            icon = Icons.remove_circle_outline;
                          } else {
                            return const SizedBox.shrink();
                          }
                          
                          return _buildSmallBadge(
                            context,
                            icon: icon,
                            label: label,
                            color: color,
                            outlined: true,
                          );
                        },
                      ),
                    ],
                  ),
                ],
                
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                
                // 시간 정보
                Row(
                  children: [
                    Icon(
                      Icons.access_time, 
                      size: ResponsiveHelper.iconSize(context, 16), 
                      color: Colors.grey[600]
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Text(
                      '${application.startTime} ~ ${application.endTime}',
                      style: ResponsiveHelper.bodyStyle(context),
                    ),
                  ],
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                
                // 업무 유형
                Row(
                  children: [
                    Icon(
                      Icons.work_outline, 
                      size: ResponsiveHelper.iconSize(context, 16), 
                      color: Colors.grey[600]
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Text(
                      application.selectedWorkType,
                      style: ResponsiveHelper.bodyStyle(context),
                    ),
                  ],
                ),
                
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                
                // 금액
                Row(
                  children: [
                    Icon(
                      Icons.attach_money, 
                      size: ResponsiveHelper.iconSize(context, 16), 
                      color: Colors.green[600]
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Text(
                      application.formattedWage,
                      style: ResponsiveHelper.bodyStyle(
                        context,
                        color: Colors.green[700],
                      ).copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                
                // 장기 근무 정보
                if (application.isLongTermApplication) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                    decoration: BoxDecoration(
                      color: Colors.purple[50],
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.purple[200]!),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.calendar_month, 
                          size: ResponsiveHelper.iconSize(context, 14), 
                          color: Colors.purple[700]
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                        Text(
                          '${application.workPeriodDisplay} ${application.workDaysDisplay ?? ""}',
                          style: ResponsiveHelper.smallStyle(
                            context,
                            color: Colors.purple[700],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                // ⭐ 액션 버튼들
                if (application.status == 'PENDING' || application.status == 'CONFIRMED') ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Row(
                    children: [
                      // 상세 보기 버튼
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _showDetailDialog(context),
                          icon: Icon(
                            Icons.info_outline, 
                            size: ResponsiveHelper.iconSize(context, 18)
                          ),
                          label: const Text('상세 정보'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.blue,
                            side: const BorderSide(color: Colors.blue),
                          ),
                        ),
                      ),
                      
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      
                      // ⭐ 취소/휴무 버튼 (요청 대기중 상태 확인)
                      Expanded(
                        child: FutureBuilder<bool>(
                          future: selectedDay != null && 
                                  application.isLongTermApplication && 
                                  application.status == 'CONFIRMED'
                              ? _hasPendingRequest(selectedDay!)
                              : Future.value(false),
                          builder: (context, snapshot) {
                            final hasPendingRequest = snapshot.data ?? false;
                            
                            // ⭐ 대기중인 요청이 있으면
                            if (hasPendingRequest) {
                              return OutlinedButton.icon(
                                onPressed: null,
                                icon: Icon(
                                  Icons.schedule, 
                                  size: ResponsiveHelper.iconSize(context, 18)
                                ),
                                label: const Text('요청 대기중'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.grey,
                                  side: const BorderSide(color: Colors.grey),
                                ),
                              );
                            }
                            
                            // ⭐ 일반 버튼
                            return OutlinedButton.icon(
                              onPressed: () => _handleCancel(context),
                              icon: Icon(
                                // 휴무일인 경우
                                selectedDay != null && 
                                application.isLongTermApplication && 
                                application.isLeaveDateOn(selectedDay!)
                                    ? Icons.refresh
                                // 추가근무일인 경우
                                : selectedDay != null && 
                                  application.isLongTermApplication && 
                                  application.isExtraWorkDateOn(selectedDay!)
                                    ? Icons.remove_circle_outline
                                // 일반 장기 확정
                                : application.isLongTermApplication && application.status == 'CONFIRMED'
                                    ? Icons.beach_access
                                // 그 외
                                : Icons.cancel_outlined,
                                size: ResponsiveHelper.iconSize(context, 18),
                              ),
                              label: Text(
                                // 휴무일인 경우
                                selectedDay != null && 
                                application.isLongTermApplication && 
                                application.isLeaveDateOn(selectedDay!)
                                    ? '휴무 취소'
                                // 추가근무일인 경우
                                : selectedDay != null && 
                                  application.isLongTermApplication && 
                                  application.isExtraWorkDateOn(selectedDay!)
                                    ? '근무 취소'
                                // 일반 장기 확정
                                : application.isLongTermApplication && application.status == 'CONFIRMED'
                                    ? '휴무 요청'
                                // 단기 확정
                                : application.status == 'CONFIRMED'
                                    ? '취소 요청'
                                // 대기중
                                : '지원 취소'
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: selectedDay != null && 
                                                application.isLongTermApplication && 
                                                application.isLeaveDateOn(selectedDay!)
                                    ? Colors.green
                                    : Colors.red,
                                side: BorderSide(
                                  color: selectedDay != null && 
                                        application.isLongTermApplication && 
                                        application.isLeaveDateOn(selectedDay!)
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                            );
                          },
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
    
    // ⭐ 휴무일 취소
    if (selectedDay != null && 
        application.isLongTermApplication && 
        application.isLeaveDateOn(selectedDay!)) {
      await _cancelLeaveDay(context);
      return;
    }
    
    // ⭐ 추가근무일 취소
    if (selectedDay != null && 
        application.isLongTermApplication && 
        application.isExtraWorkDateOn(selectedDay!)) {
      await _cancelExtraWorkDay(context);
      return;
    }
    
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
              Icon(
                Icons.warning_amber_rounded, 
                color: Colors.orange[700], 
                size: ResponsiveHelper.iconSize(context, 28)
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              const Text('확정 근무 취소'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '확정된 근무를 취소하시겠습니까?',
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
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
                        Icon(
                          Icons.error_outline, 
                          color: Colors.red[700], 
                          size: ResponsiveHelper.iconSize(context, 20)
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                        Text(
                          '⚠️ 주의사항',
                          style: ResponsiveHelper.bodyStyle(
                            context,
                            color: Colors.red[900],
                          ).copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      '• 확정 취소 시 패널티가 부과될 수 있습니다.\n'
                      '• 반복적인 취소는 향후 지원에 불이익이 있을 수 있습니다.\n'
                      '• 부득이한 사유가 있는 경우 관리자에게 먼저 연락해주세요.',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: Colors.red[800],
                      ).copyWith(height: 1.5),
                    ),
                  ],
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Text(
                '그래도 취소하시겠습니까?',
                style: ResponsiveHelper.bodyStyle(
                  context,
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
  Widget _buildStatusBadge(BuildContext context, _StatusInfo info) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
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
            size: ResponsiveHelper.iconSize(context, 14),
            color: info.color[700],
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            info.text,
            style: ResponsiveHelper.smallStyle(
              context,
              color: info.color[700],
            ).copyWith(fontWeight: FontWeight.bold),
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
        title: Row(
          children: [
            const Icon(Icons.beach_access, color: Colors.orange),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            const Text('휴무 요청'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(selectedDay!),
              style: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text('${application.toTitle} - ${application.selectedWorkType}'),
            Divider(height: ResponsiveHelper.spacing(context, 24)),
            Text(
              '휴무 사유',
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
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
      applicantName: '',
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

  /// ⭐ 추가근무일 취소 요청 (관리자 승인 필요)
  Future<void> _cancelExtraWorkDay(BuildContext context) async {
    final reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.remove_circle_outline, color: Colors.orange),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            const Text('추가근무 취소 요청'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(selectedDay!),
              style: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            const Text('추가 근무를 취소하시겠습니까?'),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[300]!),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline, 
                    color: Colors.blue[700], 
                    size: ResponsiveHelper.iconSize(context, 20)
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      '관리자 승인 후 추가 근무가 취소됩니다.',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: Colors.blue[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '취소 사유',
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: '취소 사유를 입력하세요',
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
              backgroundColor: Colors.red,
            ),
            child: const Text('요청'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 추가근무 취소 요청 생성
    final firestoreService = FirestoreService();
    
    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: application.businessId,
      applicationId: application.id,
      applicantUid: application.uid,
      applicantName: '',
      targetDate: DateTime(selectedDay!.year, selectedDay!.month, selectedDay!.day),
      requestType: RequestType.CANCEL_EXTRA,
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
      ToastHelper.showSuccess('추가근무 취소 요청이 전송되었습니다');
      onChanged?.call();
    } else {
      ToastHelper.showError('요청 실패');
    }
  }

  /// ⭐ 휴무일 취소 요청 (관리자 승인 필요)
  Future<void> _cancelLeaveDay(BuildContext context) async {
    final reasonController = TextEditingController();
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.refresh, color: Colors.green),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            const Text('휴무 취소 요청'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(selectedDay!),
              style: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            const Text('휴무를 취소하고 출근하시겠습니까?'),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[300]!),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline, 
                    color: Colors.blue[700], 
                    size: ResponsiveHelper.iconSize(context, 20)
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      '관리자 승인 후 정상 출근으로 변경됩니다.',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: Colors.blue[900],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '취소 사유',
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                hintText: '출근 가능한 사유를 입력하세요',
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
              backgroundColor: Colors.green,
            ),
            child: const Text('요청'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // 휴무 취소 요청 생성
    final firestoreService = FirestoreService();
    
    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: application.businessId,
      applicationId: application.id,
      applicantUid: application.uid,
      applicantName: '',
      targetDate: DateTime(selectedDay!.year, selectedDay!.month, selectedDay!.day),
      requestType: RequestType.CANCEL_LEAVE,
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
      ToastHelper.showSuccess('휴무 취소 요청이 전송되었습니다');
      onChanged?.call();
    } else {
      ToastHelper.showError('요청 실패');
    }
  }

  /// ⭐ 해당 날짜에 대기중인 요청이 있는지 확인
  Future<bool> _hasPendingRequest(DateTime date) async {
    final request = await _getPendingRequest(date);
    return request != null;
  }
  
  /// ⭐ 해당 날짜의 대기중인 요청 가져오기 (상세 정보 포함)
  Future<ScheduleChangeRequestModel?> _getPendingRequest(DateTime date) async {
    final firestoreService = FirestoreService();
    
    try {
      final requests = await firestoreService.getMyScheduleChangeRequests(application.uid);
      
      return requests.firstWhere(
        (r) => 
          r.isPending &&
          r.applicationId == application.id &&
          r.targetDate.year == date.year &&
          r.targetDate.month == date.month &&
          r.targetDate.day == date.day &&
          r.isApplicantRequest,
        orElse: () => null as ScheduleChangeRequestModel,
      );
    } catch (e) {
      return null;
    }
  }

  /// 작은 배지 위젯
  Widget _buildSmallBadge(
    BuildContext context, {
    required IconData icon,
    required String label,
    required Color color,
    bool outlined = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: outlined ? color.withOpacity(0.1) : color.withOpacity(0.3),
        borderRadius: BorderRadius.circular(6),
        border: outlined ? Border.all(color: color.withOpacity(0.5)) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon, 
            size: ResponsiveHelper.iconSize(context, 12), 
            color: color
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(
              context,
              color: color,
            ).copyWith(fontWeight: FontWeight.bold),
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