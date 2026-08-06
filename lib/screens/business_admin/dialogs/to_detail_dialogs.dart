import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../../../theme/app_colors.dart';
import 'package:intl/intl.dart';
import '../../../models/core/application_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';  // ⭐ 추가
import '../../../models/ui/admin_to_detail_ui_models.dart';
import '../../../widgets/dialogs/styled_dialog.dart';

/// TO 상세 화면의 다이얼로그 모음
class TODetailDialogs {
  final BuildContext context;
  final FirestoreService firestoreService;
  final VoidCallback onChanged;

  TODetailDialogs({
    required this.context,
    required this.firestoreService,
    required this.onChanged,
  });

  /// 확정 명단 다이얼로그
  Future<void> showConfirmedListDialog(
    DateTime date, 
    List<DateTOItem> toItems,
  ) async {
    final dateFormat = DateFormat('MM/dd (E)', 'ko_KR');
    
    // 확정된 지원자만 수집
    List<Map<String, dynamic>> confirmedList = [];
    
    for (var toItem in toItems) {
      for (var work in toItem.workDetails) {
        for (var applicant in work.confirmedApplicants) {
          confirmedList.add({
            ...applicant,
            'toTitle': toItem.to.title,
            'workType': work.workDetail.workType,
            'workTime': '${work.workDetail.startTime}~${work.workDetail.endTime}',
          });
        }
      }
    }

    await showDialog(
      context: context,
      builder: (context) => StyledDialog(
        title: '${dateFormat.format(date)} 확정 명단 (${confirmedList.length}명)',
        icon: Icons.list_alt,
        content: SizedBox(
          width: double.maxFinite,
          child: confirmedList.isEmpty
              ? Center(
                  child: Padding(
                    padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
                    child: Text(
                      '확정된 지원자가 없습니다',
                      style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                        context,
                        color: Theme.of(context).disabledColor,
                      ),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: confirmedList.length,
                  itemBuilder: (context, index) {
                    final applicant = confirmedList[index];
                    return Card(
                      margin: EdgeInsets.only(  // ⭐ const 제거
                        bottom: ResponsiveHelper.spacing(context, 8),  // ⭐ 변경
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.success.withValues(alpha: 0.2),
                          child: Icon(Icons.person, color: AppColors.success),
                        ),
                        title: Text(
                          applicant['userName'] as String? ?? '이름 없음',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              const Icon(Icons.phone_outlined, size: 14, color: AppColors.grey600),
                              const SizedBox(width: 4),
                              Text(applicant['userPhone'] as String? ?? '-'),
                            ]),
                            Row(children: [
                              const Icon(Icons.work_outline, size: 14, color: AppColors.grey600),
                              const SizedBox(width: 4),
                              Flexible(child: Text('${applicant['workType']} (${applicant['workTime']})',
                                  overflow: TextOverflow.ellipsis, maxLines: 1)),
                            ]),
                            if (toItems.length > 1)
                              Row(children: [
                                const Icon(Icons.assignment_outlined, size: 14, color: AppColors.grey600),
                                const SizedBox(width: 4),
                                Flexible(child: Text(applicant['toTitle'],
                                    overflow: TextOverflow.ellipsis, maxLines: 1)),
                              ]),
                          ],
                        ),
                        dense: true,
                      ),
                    );
                  },
                ),
        ),
        actions: [
          if (confirmedList.isNotEmpty)
            TextButton.icon(
              onPressed: () async {
                final lines = confirmedList.map((a) =>
                  '${a['userName']}  ${a['userPhone']}  ${a['workType']}(${a['workTime']})'
                ).join('\n');
                await Clipboard.setData(ClipboardData(text: lines));
                ToastHelper.showSuccess('연락처가 클립보드에 복사되었습니다');
              },
              icon: const Icon(Icons.content_copy),
              label: const Text('연락처 복사'),
            ),
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// 지원자 목록 모달
  Future<void> showApplicantsModal(
    WorkDetailWithApplicants work,
    Function(String) onConfirm,
    Function(String) onReject,
  ) async {
    await showDialog(
      context: context,
      builder: (context) => StyledDialog(
        title: '${work.workDetail.workType} 지원자 (${work.totalApplicants}명)',
        icon: Icons.people,
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 업무 정보
                Container(
                  padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.access_time, 
                        size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                        color: Theme.of(context).primaryColor,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                      Text(
                        '${work.workDetail.startTime}~${work.workDetail.endTime}',
                        style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                          context,
                          color: Theme.of(context).primaryColor,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
                      Icon(
                        Icons.attach_money, 
                        size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                        color: Theme.of(context).primaryColor,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                      Text(
                        work.workDetail.formattedWage,
                        style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                          context,
                          color: Theme.of(context).primaryColor,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
                
                // 대기 중
                if (work.pendingApplicants.isNotEmpty) ...[
                  _buildSectionHeader(context, '⏳ 대기 중', AppColors.warning, work.pendingApplicants.length),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  ...work.pendingApplicants.map((applicant) {
                    return _buildApplicantCard(context, applicant, onConfirm, onReject);
                  }),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                ],

                // 확정
                if (work.confirmedApplicants.isNotEmpty) ...[
                  _buildSectionHeader(context, '✅ 확정', AppColors.success, work.confirmedApplicants.length),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  ...work.confirmedApplicants.map((applicant) {
                    return _buildApplicantCard(context, applicant, onConfirm, onReject);
                  }),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                ],

                // 거절
                if (work.rejectedApplicants.isNotEmpty) ...[
                  _buildSectionHeader(context, '❌ 거절', AppColors.error, work.rejectedApplicants.length),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  ...work.rejectedApplicants.map((applicant) {
                    return _buildApplicantCard(context, applicant, onConfirm, onReject);
                  }),
                ],
              ],
            ),
          ),
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  // ========================================
  // Helper 위젯들
  // ========================================

  static Color _appStatusColor(String status) {
    switch (status) {
      case AppStatus.pending:          return AppColors.warning;
      case AppStatus.contractPending:  return AppColors.info;
      case AppStatus.confirmed:        return AppColors.confirmed;
      case AppStatus.rejected:         return AppColors.rejected;
      case AppStatus.canceled:
      case AppStatus.autoCanceled:     return AppColors.grey500;
      default:                         return AppColors.grey500;
    }
  }

  /// 섹션 헤더
  Widget _buildSectionHeader(BuildContext ctx, String title, Color color, int count) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(ctx, 12),
            vertical: ResponsiveHelper.spacing(ctx, 6),
          ),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: ResponsiveHelper.bodyStyle(
                  ctx,
                  color: color,
                ).copyWith(fontWeight: FontWeight.bold),
              ),
              SizedBox(width: ResponsiveHelper.spacing(ctx, 8)),
              Text(
                '$count명',
                style: ResponsiveHelper.bodyStyle(
                  ctx,
                  color: color,
                ).copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 지원자 카드
  Widget _buildApplicantCard(
    BuildContext ctx,
    Map<String, dynamic> applicant,
    Function(String) onConfirm,
    Function(String) onReject,
  ) {
    final app = applicant['application'] as ApplicationModel?;
    if (app == null) return const SizedBox.shrink();

    final statusColor = _appStatusColor(app.status);
    final statusText = app.statusText;

    return Card(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(ctx, 8),
      ),
      child: Padding(
        padding: ResponsiveHelper.cardPadding(ctx),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 이름
                Expanded(
                  child: Text(
                    applicant['userName'] as String? ?? '이름 없음',
                    style: ResponsiveHelper.bodyStyle(ctx).copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                // 상태 배지
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(ctx, 8),
                    vertical: ResponsiveHelper.spacing(ctx, 4),
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    statusText,
                    style: ResponsiveHelper.tinyStyle(
                      ctx,
                      color: statusColor,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),

            SizedBox(height: ResponsiveHelper.spacing(ctx, 8)),

            // 연락처
            Row(
              children: [
                Icon(
                  Icons.phone,
                  size: ResponsiveHelper.iconSize(ctx, 14),
                  color: Theme.of(ctx).textTheme.bodySmall?.color,
                ),
                SizedBox(width: ResponsiveHelper.spacing(ctx, 6)),
                Text(
                  applicant['userPhone'] as String? ?? '-',
                  style: ResponsiveHelper.smallStyle(
                    ctx,
                    color: Theme.of(ctx).textTheme.bodyMedium?.color,
                  ),
                ),
              ],
            ),

            SizedBox(height: ResponsiveHelper.spacing(ctx, 4)),

            // 지원 시간
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: ResponsiveHelper.iconSize(ctx, 14),
                  color: Theme.of(ctx).textTheme.bodySmall?.color,
                ),
                SizedBox(width: ResponsiveHelper.spacing(ctx, 6)),
                Text(
                  '지원: ${DateFormat('MM/dd HH:mm', 'ko_KR').format(app.appliedAt)}',
                  style: ResponsiveHelper.tinyStyle(
                    ctx,
                    color: Theme.of(ctx).textTheme.bodySmall?.color,
                  ),
                ),
              ],
            ),

            // 버튼 (대기 중인 경우만)
            if (app.status == AppStatus.pending) ...[
              SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onReject(applicant['applicationId']);
                      },
                      icon: Icon(
                        Icons.close,
                        size: ResponsiveHelper.iconSize(ctx, 18),
                      ),
                      label: const Text('거절'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                      ),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(ctx, 8)),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        onConfirm(applicant['applicationId']);
                      },
                      icon: Icon(
                        Icons.check,
                        size: ResponsiveHelper.iconSize(ctx, 18),
                      ),
                      label: const Text('승인'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                      ),
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
}