import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Models
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/to_model.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

// Providers
import '../../../providers/user_provider.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';

// Theme
import '../../../theme/app_colors.dart';

// Widgets
import '../../work_type_icon.dart';

// Dialogs
import '../../../screens/business_admin/dialogs/work_applicants_dialog.dart';

/// ✨ 업무 상세 행 위젯 (간소화된 디자인)
/// 
/// 개선 사항:
/// - 좌측 컬러 인디케이터
/// - 정보 간소화 (업무명 + 시간 + 인원)
/// - 상태별 색상 적용
class WorkDetailRow extends StatelessWidget {
  final WorkDetailModel work;
  final int confirmedCount;
  final int pendingCount;
  final TOItem toItem;
  final FirestoreService firestoreService;
  final VoidCallback onChanged;

  const WorkDetailRow({
    super.key,
    required this.work,
    required this.confirmedCount,
    required this.pendingCount,
    required this.toItem,
    required this.firestoreService,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isFull = confirmedCount >= work.requiredCount;
    final isClosed = work.isClosed || work.isTimeExpired || work.isFull;
    final isEmergency = work.isEmergencyOpen;
    
    // 상태별 색상
    Color statusColor;
    if (isClosed) {
      statusColor = AppColors.grey400;
    } else if (isEmergency) {
      statusColor = AppColors.error;
    } else if (isFull) {
      statusColor = AppColors.success;
    } else {
      statusColor = AppColors.info;
    }

    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 8),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ✨ 좌측 상태 인디케이터
            Container(
              width: 3,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            
            // ✨ 메인 컨텐츠 (카드 전체 클릭 가능)
            Expanded(
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _showApplicantsDialog(context),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.grey200),
                    ),
                    child: Row(
                      children: [
                        // 업무 아이콘
                        _buildWorkIcon(context),
                        
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                        
                        // 업무 정보
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 1줄: 업무명
                              Text(
                                work.workType,
                                style: ResponsiveHelper.bodyStyle(context).copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                              // 2줄: 근무시간
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: ResponsiveHelper.iconSize(context, 12),
                                    color: AppColors.grey500,
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                  Text(
                                    '${work.startTime} ~ ${work.endTime}',
                                    style: ResponsiveHelper.smallStyle(
                                      context,
                                      color: AppColors.grey600,
                                    ),
                                  ),
                                ],
                              ),
                              // 3줄: 마감시간 (단기공고만 - 장기공고는 카드 레벨에서 표시)
                              if (!toItem.to.isLongTerm) ...[
                                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                                Row(
                                  children: [
                                    Icon(
                                      Icons.timer_off_outlined,
                                      size: ResponsiveHelper.iconSize(context, 12),
                                      color: isClosed ? AppColors.grey500 : AppColors.warningDark,
                                    ),
                                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                    Text(
                                      '마감 ${work.applicationDeadline != null ? FormatHelper.formatTime(work.applicationDeadline!) : work.startTime}',
                                      style: ResponsiveHelper.smallStyle(
                                        context,
                                        color: isClosed ? AppColors.grey500 : AppColors.warningDark,
                                      ),
                                    ),
                                    if (isClosed) ...[
                                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: ResponsiveHelper.spacing(context, 6),
                                          vertical: ResponsiveHelper.spacing(context, 2),
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.grey200,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '마감됨',
                                          style: ResponsiveHelper.tinyStyle(
                                            context,
                                            color: AppColors.grey600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                              // 4줄: 급여
                              Row(
                                children: [
                                  Icon(
                                    Icons.paid,
                                    size: ResponsiveHelper.iconSize(context, 12),
                                    color: AppColors.successDark,
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                  Text(
                                    FormatHelper.formatWage(work.wage),
                                    style: ResponsiveHelper.smallStyle(
                                      context,
                                      color: AppColors.successDark,
                                    ).copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        
                        // 오른쪽: 인원 + 버튼 (세로 배치)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 인원 현황
                            _buildPersonnelStatus(context, isFull, isClosed, statusColor),
                            
                            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                            
                            // 지원자 보기 버튼
                            _buildApplicantButton(context, theme),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 업무 아이콘
  Widget _buildWorkIcon(BuildContext context) {
    return Container(
      width: ResponsiveHelper.iconSize(context, 36),
      height: ResponsiveHelper.iconSize(context, 36),
      decoration: BoxDecoration(
        color: FormatHelper.parseColor(work.workTypeBackgroundColor ?? '#E3F2FD'),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: WorkTypeIcon.buildFromString(
          work.workTypeIcon,
          color: FormatHelper.parseColor(work.workTypeColor ?? '#2196F3'),
          size: ResponsiveHelper.iconSize(context, 18),
        ),
      ),
    );
  }

  /// 인원 현황 (항상 표시 + 상태별 색상)
  Widget _buildPersonnelStatus(
    BuildContext context,
    bool isFull,
    bool isClosed,
    Color statusColor,
  ) {
    // 상태별 색상: 마감=회색, 충족=초록, 진행중=파랑
    Color displayColor;
    if (isClosed) {
      displayColor = AppColors.grey500;
    } else if (isFull) {
      displayColor = AppColors.successDark;
    } else {
      displayColor = AppColors.infoDark;
    }
    
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isFull ? Icons.check_circle : Icons.people_outline,
          size: ResponsiveHelper.iconSize(context, 14),
          color: displayColor,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text(
          '$confirmedCount/${work.requiredCount}',
          style: ResponsiveHelper.bodyStyle(
            context,
            color: displayColor,
          ).copyWith(fontWeight: FontWeight.bold),
        ),
        if (pendingCount > 0) ...[
          Text(
            ' +$pendingCount',
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.warningDark,
            ),
          ),
        ],
      ],
    );
  }

  /// 지원자 보기 버튼
  Widget _buildApplicantButton(BuildContext context, ThemeData theme) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showApplicantsDialog(context),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: theme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.people,
            size: ResponsiveHelper.iconSize(context, 18),
            color: theme.primaryColor,
          ),
        ),
      ),
    );
  }

  /// 지원자 다이얼로그 표시
  Future<void> _showApplicantsDialog(BuildContext context) async {
    await showDialog(
      context: context,
      builder: (context) => WorkApplicantsDialog(
        toItem: toItem,
        work: work,
        onChanged: onChanged,
      ),
    );
    // 다이얼로그 닫힌 후 항상 부모에 갱신 요청
    onChanged();
  }
}