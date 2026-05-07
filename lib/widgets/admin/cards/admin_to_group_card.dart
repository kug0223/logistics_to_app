import 'package:flutter/material.dart';

// Models
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../models/core/work_detail_model.dart';

// Helper
import '../../../utils/toast_helper.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/responsive_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/format_helper.dart';

// Widgets
import '../../../theme/app_colors.dart';

// Screens
import '../../../screens/business_admin/to_management/edit_to_screen.dart';
import '../../../screens/common/job_posting_screen.dart';

// Dialogs
import '../../../screens/business_admin/dialogs/confirmed_list_dialog.dart';
import '../../../screens/business_admin/dialogs/work_detail_management_dialog.dart';
import '../../../screens/business_admin/dialogs/to_list_dialogs.dart';

// Local Widgets
import 'admin_to_item_card.dart';
import 'admin_work_detail.dart';

/// ✨ TO 그룹 카드 (개선된 디자인 - 한눈에 들어오는 UI)
/// 
/// 개선 사항:
/// - 좌측 상태 컬러바 추가
/// - 정보 계층 명확화 (제목 강조)
/// - 태그/배지 최소화
/// - 핵심 정보만 표시 (날짜 + 인원)
class TOGroupCard extends StatefulWidget {
  final TOGroupItem groupItem;
  final FirestoreService firestoreService;
  final TOListDialogs dialogs;
  final VoidCallback onChanged;
  final bool isExpanded;
  final Set<String> expandedTOs;
  final VoidCallback onToggleExpand;
  final Function(String toId) onToggleTOExpand;
  final DateTime? selectedDate;
  
  // ✨ Lazy Loading 상태
  final bool isGroupLoading;      // 그룹 로딩 중
  final Set<String> loadingTOs;   // 로딩 중인 TO 목록
  final void Function(Set<String> affectedTOIds)? onAffectedTOsChanged;  // 🔥 추가

  const TOGroupCard({
    super.key,
    required this.groupItem,
    required this.firestoreService,
    required this.dialogs,
    required this.onChanged,
    required this.isExpanded,
    required this.expandedTOs,
    required this.onToggleExpand,
    required this.onToggleTOExpand,
    this.selectedDate,
    this.isGroupLoading = false,
    this.loadingTOs = const {},
    this.onAffectedTOsChanged,  // 🔥 추가
  });

  @override
  State<TOGroupCard> createState() => _TOGroupCardState();
}

class _TOGroupCardState extends State<TOGroupCard> with SingleTickerProviderStateMixin {
 @override
  Widget build(BuildContext context) {
    final masterTO = widget.groupItem.masterTO;
    final theme = Theme.of(context);
    
    // flex TO이고 날짜 필터가 있으면 해당 날짜 슬롯만, 아니면 전체
    final targetTOs = (widget.selectedDate != null && !widget.groupItem.isLongTerm)
        ? widget.groupItem.groupTOs.where((toItem) =>
            DateUtils.isSameDay(toItem.to.date, widget.selectedDate!)).toList()
        : widget.groupItem.groupTOs;

    // 전체 통계 계산
    int totalConfirmed = 0;
    int totalPending = 0;
    int totalRequired = 0;

    // groupTOs가 아직 로드 안 됐으면 groupItem에서 통계 사용
    if (targetTOs.isEmpty) {
      totalConfirmed = widget.groupItem.totalConfirmed;
      totalPending = widget.groupItem.totalPending;
      totalRequired = widget.groupItem.totalRequired;
    } else {
      for (var toItem in targetTOs) {
      // ✅ workDetails 로드됐으면 각 업무별로 workDetailStats에서 합산
      if (toItem.isWorkDetailLoaded && toItem.workDetails.isNotEmpty) {
        for (var work in toItem.workDetails) {
          // ✅ workDetailId로 조회
          final stats = toItem.workDetailStats?[work.id];
          totalConfirmed += (stats?['confirmed'] ?? 0);
          totalPending += (stats?['pending'] ?? 0);
        }
        totalRequired += toItem.totalRequired;
      } else {
        // 아직 로드 안 됐으면 초기값 사용
        totalConfirmed += toItem.confirmedCount;
        totalPending += toItem.pendingCount;
        totalRequired += toItem.totalRequired;
      }
    }
    }  // ✅ else 블록 닫기
    
    debugPrint('🔍 [TOGroupCard] 최종 통계: $totalConfirmed/$totalRequired (+$totalPending)');
    
    // 인원 충족 여부 (groupTOs 로드 안됐으면 groupItem에서 직접 체크)
    final isFull = widget.groupItem.groupTOs.isEmpty 
        ? widget.groupItem.isFull 
        : widget.groupItem.groupTOs.every((toItem) {
            // workDetails 로드 안됐으면 TO 문서의 통계 사용
            if (!toItem.isWorkDetailLoaded || toItem.workDetails.isEmpty) {
              return toItem.confirmedCount >= toItem.totalRequired && toItem.totalRequired > 0;
            }
            return toItem.workDetails.every((work) {
              final stats = toItem.workDetailStats?[work.id];
              final confirmed = stats?['confirmed'] ?? 0;
              return confirmed >= work.requiredCount;
            });
          });

    // ✅ 전체 마감 여부 (WorkDetail 실제 상태 우선)
    final allClosed = widget.groupItem.groupTOs.isEmpty
        ? widget.groupItem.isClosed
        : widget.groupItem.groupTOs.every((toItem) {
            final to = toItem.to;
            
            // ✅ WorkDetails 로드된 경우: 실제 상태 우선!
            if (toItem.isWorkDetailLoaded && toItem.workDetails.isNotEmpty) {
              return toItem.workDetails.every((work) =>
                  work.isClosed || work.isTimeExpired || work.isFull);
            }
            
            // ✅ WorkDetails 미로드: DB status 기반 판단
            if (to.status == 'CLOSED' || to.status == 'EXPIRED' || to.status == 'FULL') {
              return true;
            }
            
            // ✅ 수동 마감 체크
            if (to.isManualClosed) {
              return true;
            }
            
            // ✅ DB status가 ACTIVE면 모집중
            return false;
          });

    // ✨ 컬러바 색상 결정 (장기: 보라, 단기: 초록)
    Color statusBarColor;
    if (allClosed) {
      statusBarColor = AppColors.grey400;
    } else {
      statusBarColor = widget.groupItem.isLongTerm ? AppColors.longTerm : AppColors.shortTerm;
    }

    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 12),
      ),
      child: Stack(
        children: [
          // ✅ 메인 카드
          Container(
            margin: const EdgeInsets.only(left: 4),  // 좌측 컬러바 공간
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
              border: Border.all(
                color: widget.isExpanded ? theme.primaryColor : AppColors.grey200,
                width: widget.isExpanded ? 1.5 : 1,
              ),
            ),
            child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              // ✨ 헤더 (클릭 가능)
              InkWell(
                onTap: widget.onToggleExpand,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(widget.isExpanded ? 0 : 16),
                  bottomRight: Radius.circular(widget.isExpanded ? 0 : 16),
                ),
                child: Padding(
                  padding: ResponsiveHelper.cardPadding(context),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ✨ 첫째 줄: 배지 + 사업장 + 등록시간 + 메뉴
                      Row(
                        children: [
                          // 장기/단기 텍스트 배지 (맨 앞)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 8),
                              vertical: ResponsiveHelper.spacing(context, 3),
                            ),
                            decoration: BoxDecoration(
                              color: widget.groupItem.isLongTerm 
                                  ? AppColors.longTermBg 
                                  : AppColors.shortTermBg,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: widget.groupItem.isLongTerm 
                                    ? AppColors.longTermLight 
                                    : AppColors.shortTermLight,
                              ),
                            ),
                            child: Text(
                              widget.groupItem.isLongTerm ? '고정' : '단기',
                              style: ResponsiveHelper.smallStyle(
                                context,
                                color: widget.groupItem.isLongTerm 
                                    ? AppColors.longTermDark 
                                    : AppColors.shortTermDark,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          
                          // 플렉스 TO: 날짜 슬롯 수 뱃지
                          if (!widget.groupItem.isLongTerm && masterTO.totalSlots > 1) ...[
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 6),
                                vertical: ResponsiveHelper.spacing(context, 3),
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.infoBg,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppColors.infoLight),
                              ),
                              child: Text(
                                '${masterTO.totalSlots}일',
                                style: ResponsiveHelper.smallStyle(
                                  context,
                                  color: AppColors.infoDark,
                                ).copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],

                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),

                          // 사업장명
                          Expanded(
                            child: Text(
                              widget.groupItem.businessName,
                              style: ResponsiveHelper.smallStyle(
                                context,
                                color: AppColors.grey600,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          
                          // 등록시간
                          Text(
                            _getCreatedAtText(widget.groupItem.createdAt),
                            style: ResponsiveHelper.tinyStyle(
                              context,
                              color: AppColors.grey500,
                            ),
                          ),
                          
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          
                          // 메뉴 버튼
                          _buildSingleTOMenu(context),
                        ],
                      ),
                      
                      SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                      
                      // ✨ 둘째 줄: 제목 (크게 강조!)
                      Text(
                        widget.groupItem.groupName,
                        style: ResponsiveHelper.titleStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      
                      SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                      
                      // ✨ 셋째 줄: 날짜 + 인원현황 (핵심 정보만!)
                      Row(
                        children: [
                          // 날짜 정보
                          Expanded(
                            child: Row(
                              children: [
                                Icon(
                                  Icons.event,
                                  size: ResponsiveHelper.iconSize(context, 14),
                                  color: AppColors.grey500,
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                Expanded(
                                  child: Text(
                                    _getDateText(masterTO),
                                    style: ResponsiveHelper.bodyStyle(
                                      context,
                                      color: AppColors.grey700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          
                          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                          
                          // ✨ 인원 현황 (핵심!)
                          _buildPersonnelBadge(
                            context,
                            confirmed: totalConfirmed,
                            required: totalRequired,
                            pending: totalPending,
                            isFull: isFull,
                          ),
                        ],
                      ),
                      
                      // ✨ 장기공고 마감일시 표시 (장기공고인 경우)
                      if (masterTO.isLongTerm && !allClosed) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        Row(
                          children: [
                            Icon(
                              Icons.timer_outlined,
                              size: ResponsiveHelper.iconSize(context, 14),
                              color: masterTO.isDeadlinePassed 
                                  ? AppColors.grey500 
                                  : AppColors.warningDark,
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                            Text(
                              '지원마감 ${masterTO.formattedDeadline}',
                              style: ResponsiveHelper.smallStyle(
                                context,
                                color: masterTO.isDeadlinePassed 
                                    ? AppColors.grey500 
                                    : AppColors.warningDark,
                              ),
                            ),
                            if (masterTO.isDeadlineSoon && !masterTO.isDeadlinePassed) ...[
                              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: ResponsiveHelper.spacing(context, 6),
                                  vertical: ResponsiveHelper.spacing(context, 2),
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.warningBg,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '마감임박',
                                  style: ResponsiveHelper.tinyStyle(
                                    context,
                                    color: AppColors.warningDark,
                                  ).copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                      
                      // ✨ 상태 표시 (마감/예약/모집중) - targetTOs 기준
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      _buildStatusBadge(context, allClosed: allClosed, targetTOs: targetTOs),
                      
                      // 펼침 힌트
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                      Center(
                        child: Icon(
                          widget.isExpanded 
                              ? Icons.keyboard_arrow_up 
                              : Icons.keyboard_arrow_down,
                          size: ResponsiveHelper.iconSize(context, 20),
                          color: AppColors.grey400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              
              // 펼쳐진 경우: flex 다중 슬롯 목록
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                clipBehavior: Clip.hardEdge,
                child: widget.isExpanded && !widget.groupItem.isLongTerm && widget.groupItem.groupTOs.length > 1
                    ? Column(
                        children: [
                          Divider(height: 1, color: AppColors.grey200),
                          Container(
                            decoration: BoxDecoration(
                              color: AppColors.grey50,
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              ),
                            ),
                            child: Padding(
                              padding: ResponsiveHelper.cardPadding(context),
                              child: widget.isGroupLoading
                                  // ✨ 로딩 중 스피너
                                  ? Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(
                                          ResponsiveHelper.spacing(context, 24),
                                        ),
                                        child: Column(
                                          children: [
                                            SizedBox(
                                              width: 24,
                                              height: 24,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: theme.primaryColor,
                                              ),
                                            ),
                                            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                                            Text(
                                              '불러오는 중...',
                                              style: ResponsiveHelper.smallStyle(context).copyWith(
                                                color: AppColors.grey500,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    )
                                  // ✨ 로드 완료 - TO 목록 표시
                                  : Column(
                                      children: _getFilteredGroupTOs().map((toItem) {
                                        return TOItemCard(
                                          toItem: toItem,
                                          groupItem: widget.groupItem,
                                          firestoreService: widget.firestoreService,
                                          dialogs: widget.dialogs,
                                          onChanged: widget.onChanged,
                                          isExpanded: widget.expandedTOs.contains(toItem.to.id),
                                          onToggleExpand: () => widget.onToggleTOExpand(toItem.to.id),
                                          isLoading: widget.loadingTOs.contains(toItem.to.id),
                                          onLocalStatsChanged: () => setState(() {}),
                                          onAffectedTOsChanged: widget.onAffectedTOsChanged,  // 🔥 추가
                                        );
                                      }).toList(),
                                    ),
                            ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              
              // 펼쳐진 경우: 단건 슬롯 or 장기 TO 업무 상세
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                clipBehavior: Clip.hardEdge,
                child: widget.isExpanded && (widget.groupItem.isLongTerm || widget.groupItem.groupTOs.length <= 1)
                    ? Column(
                        children: [
                          Divider(height: 1, color: AppColors.grey200),
                          Container(
                            padding: ResponsiveHelper.cardPadding(context),
                            decoration: BoxDecoration(
                              color: AppColors.grey50,
                              borderRadius: BorderRadius.only(
                                bottomLeft: Radius.circular(16),
                                bottomRight: Radius.circular(16),
                              ),
                            ),
                            child: (widget.groupItem.groupTOs.isEmpty || widget.loadingTOs.contains(widget.groupItem.groupTOs.first.to.id))
                                // ✨ 로딩 중 스피너
                                ? Center(
                                    child: Padding(
                                      padding: EdgeInsets.all(
                                        ResponsiveHelper.spacing(context, 24),
                                      ),
                                      child: Column(
                                        children: [
                                          SizedBox(
                                            width: 24,
                                            height: 24,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: theme.primaryColor,
                                            ),
                                          ),
                                          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                                          Text(
                                            '업무 정보 불러오는 중...',
                                            style: ResponsiveHelper.smallStyle(context).copyWith(
                                              color: AppColors.grey500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                // ✨ 로드 완료 - 업무 상세 표시
                                : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // 업무 상세 헤더
                                      Row(
                                        children: [
                                          Icon(
                                            Icons.assignment,
                                            size: ResponsiveHelper.iconSize(context, 16),
                                            color: theme.primaryColor,
                                          ),
                                          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                                          Text(
                                            '업무 상세',
                                            style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                                      
                                      // 업무 목록
                                      ...widget.groupItem.groupTOs.first.workDetails.map((work) {
                                        final stats = widget.groupItem.groupTOs.first
                                            .workDetailStats?[work.id];
                                        final confirmed = stats?['confirmed'] ?? 0;
                                        final pending = stats?['pending'] ?? 0;

                                        return WorkDetailRow(
                                          work: work,
                                          confirmedCount: confirmed,
                                          pendingCount: pending,
                                          toItem: widget.groupItem.groupTOs.first,
                                          firestoreService: widget.firestoreService,
                                          onChanged: widget.onChanged,
                                          onLocalStatsChanged: () => setState(() {}),
                                          onAffectedTOsChanged: widget.onAffectedTOsChanged,  // 🔥 추가
                                        );
                                      }),
                                    ],
                                  ),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ),
          ),
          // ✅ 좌측 컬러바 (Stack으로 위에 덮기)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              decoration: BoxDecoration(
                color: statusBarColor,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // ✨ 새로운 간소화된 위젯들
  // ═══════════════════════════════════════════════════════════════
  /// 등록일 텍스트
  String _getCreatedAtText(DateTime created) {
    final now = DateTime.now();
    final diff = now.difference(created);
    
    if (diff.inMinutes < 60) {
      return '${diff.inMinutes}분 전';
    } else if (diff.inHours < 24) {
      return '${diff.inHours}시간 전';
    } else if (diff.inDays < 7) {
      return '${diff.inDays}일 전';
    } else {
      return '${created.month}/${created.day}';
    }
  }

  /// 날짜 텍스트 생성
  String _getDateText(dynamic masterTO) {
    if (masterTO.isLongTerm) {
      return masterTO.longTermPeriodWithDays;
    }
    // flex TO: 로드된 슬롯 수 우선, 없으면 totalSlots 사용
    final int count = widget.groupItem.isGroupDetailLoaded && widget.groupItem.groupTOs.isNotEmpty
        ? widget.groupItem.groupTOs.length
        : masterTO.totalSlots;
    if (count <= 1) {
      return FormatHelper.formatDate(masterTO.rangeStart ?? masterTO.createdAt);
    }
    return '${FormatHelper.formatDate(masterTO.rangeStart ?? masterTO.createdAt)} 외 ${count - 1}일';
  }
/// ✨ 인원 현황 배지 (핵심 정보)
  Widget _buildPersonnelBadge(
    BuildContext context, {
    required int confirmed,
    required int required,
    required int pending,
    required bool isFull,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: isFull ? AppColors.successBg : AppColors.infoBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isFull ? AppColors.successLight : AppColors.infoLight,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isFull ? Icons.check_circle : Icons.people,
            size: ResponsiveHelper.iconSize(context, 14),
            color: isFull ? AppColors.successDark : AppColors.infoDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            '$confirmed/$required',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: isFull ? AppColors.successDark : AppColors.infoDark,
            ).copyWith(fontWeight: FontWeight.bold),
          ),
          if (pending > 0) ...[
            Text(
              ' +$pending',
              style: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.warningDark,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// ✨ 예약 공개 정보 (간소화)
  Widget _buildScheduledInfo(BuildContext context, dynamic masterTO) {
    return Row(
      children: [
        Icon(
          Icons.visibility_off,
          size: ResponsiveHelper.iconSize(context, 12),
          color: AppColors.warningDark,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text(
          '예약 공개: ${masterTO.publishAtDisplay ?? ''}',
          style: ResponsiveHelper.smallStyle(
            context,
            color: AppColors.warningDark,
          ),
        ),
      ],
    );
  }
  /// ✨ 상태 배지 (마감/예약/모집중) - targetTOs 기준
  Widget _buildStatusBadge(BuildContext context, {
    required bool allClosed,
    required List<TOItem> targetTOs,
  }) {
    // 1. 마감됨
    if (allClosed) {
      return _buildClosedBadge(context);
    }
    
    // ✅ targetTOs가 비어있으면 groupItem에서 상태 판단
    if (targetTOs.isEmpty) {
      if (widget.groupItem.isPendingPublish) {
        return _buildScheduledBadge(context, widget.groupItem.publishAt);
      }
      return _buildRecruitingBadge(context);
    }
    
    // 2. 모집중 (하나라도 공개된 TO가 있으면)
    final hasRecruiting = targetTOs.any((toItem) => !toItem.to.isPendingPublish);
    if (hasRecruiting) {
      return _buildRecruitingBadge(context);
    }
    
    // 3. 예약 (모두 예약 상태일 때만)
    final scheduledTO = targetTOs.first;  // ✅ 위에서 isEmpty 체크했으므로 안전
    return _buildScheduledBadge(context, scheduledTO.to.publishAt);
  }

  /// ✨ 예약 배지 (오픈 예정)
  Widget _buildScheduledBadge(BuildContext context, DateTime? publishAt) {
    String displayText = '예약';
    if (publishAt != null) {
      displayText = '${publishAt.month}/${publishAt.day} ${publishAt.hour.toString().padLeft(2, '0')}:${publishAt.minute.toString().padLeft(2, '0')} 오픈';
    }
    
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: AppColors.scheduledBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.schedule,
            size: ResponsiveHelper.iconSize(context, 12),
            color: AppColors.scheduledDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            displayText,
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.scheduledDark,
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 모집중 배지
  Widget _buildRecruitingBadge(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: AppColors.successBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.campaign,
            size: ResponsiveHelper.iconSize(context, 12),
            color: AppColors.successDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            '모집중',
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.successDark,
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 마감 배지 (간소화)
  Widget _buildClosedBadge(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock,
            size: ResponsiveHelper.iconSize(context, 12),
            color: AppColors.grey600,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            '마감됨',
            style: ResponsiveHelper.smallStyle(
              context,
              color: AppColors.grey600,
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // 메뉴 관련 (기존 유지)
  // ═══════════════════════════════════════════════════════════════

  /// 단일 TO 메뉴
  Widget _buildSingleTOMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: ResponsiveHelper.iconSize(context, 20),
        color: AppColors.grey600,
      ),
      padding: EdgeInsets.zero,
      tooltip: '메뉴',
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      onSelected: (value) => _handleSingleTOMenuAction(context, value),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'preview',
          child: Row(
            children: [
              Icon(
                Icons.visibility,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.info,  
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('공고 미리보기'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(
                Icons.edit,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.warning,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('수정'),
            ],
          ),
        ),
        PopupMenuItem(
          value: widget.groupItem.isClosed ? 'reopen' : 'close',
          child: Row(
            children: [
              Icon(
                widget.groupItem.isClosed ? Icons.lock_open : Icons.lock_outline,
                size: ResponsiveHelper.iconSize(context, 18),
                color: widget.groupItem.isClosed ? AppColors.success : AppColors.warning,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text(widget.groupItem.isClosed ? '재오픈' : '마감'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.error,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('삭제'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'confirmedList',
          child: Row(
            children: [
              Icon(
                Icons.check_circle_outline,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.success,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('확정명단'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'manageWorkDetails',
          child: Row(
            children: [
              Icon(
                Icons.assignment_turned_in,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.purple,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('업무별 마감'),
            ],
          ),
        ),
      ],
    );
  }

  /// 단일 TO 메뉴 액션
  Future<void> _handleSingleTOMenuAction(
      BuildContext context, String value) async {
    final masterTO = widget.groupItem.masterTO;

    switch (value) {
      case 'preview':
        // ✅ WorkDetails 로드 확인 후 미리보기 열기
        final toItemForPreview = widget.groupItem.groupTOs.isNotEmpty 
            ? widget.groupItem.groupTOs.first 
            : null;
        
        if (toItemForPreview == null) {
          ToastHelper.showError('TO 정보를 불러올 수 없습니다.');
          return;
        }
        
        if (!toItemForPreview.isWorkDetailLoaded || toItemForPreview.workDetails.isEmpty) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: CircularProgressIndicator()),
          );
          
          try {
            final result = await widget.firestoreService.loadTOWorkDetails(toItemForPreview.to);
            toItemForPreview.setWorkDetails(
              result['workDetails'] as List<WorkDetailModel>,
              result['workStats'] as Map<String, Map<String, int>>,
            );
          } catch (e) {
            Navigator.pop(context);
            ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
            return;
          }
          
          Navigator.pop(context);
        }
        
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => JobPostingScreen(
              to: widget.groupItem.masterTO,
              workDetails: toItemForPreview.workDetails,
              mode: TODetailMode.adminPreview,
            ),
          ),
        );
        break;
      case 'edit':
        await NavigationHelper.push<bool>(
          context,
          destination: AdminEditTOScreen(to: masterTO),
          onReturn: (result) {
            if (result == true) {
              widget.firestoreService.clearCache();
              widget.onChanged();
            }
          },
        );
        break;

      case 'close':
        widget.dialogs.showCloseTODialog(masterTO);
        break;

      case 'reopen':
        widget.dialogs.showReopenTODialog(masterTO);
        break;

      case 'delete':
        if (widget.groupItem.groupTOs.isEmpty) {
          ToastHelper.showError('TO 정보를 불러올 수 없습니다.');
          return;
        }
        widget.dialogs.showDeleteTODialog(widget.groupItem.groupTOs.first);
        break;

      case 'confirmedList':
        // ✅ WorkDetails 로드 확인 후 다이얼로그 열기
        if (widget.groupItem.groupTOs.isEmpty) {
          ToastHelper.showError('TO 정보를 불러올 수 없습니다.');
          return;
        }

        // 다중 슬롯이면 날짜 선택
        final toItemForConfirmed = await _selectTOItem(context);
        if (toItemForConfirmed == null || !mounted) return;

        if (!toItemForConfirmed.isWorkDetailLoaded || toItemForConfirmed.workDetails.isEmpty) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: CircularProgressIndicator()),
          );

          try {
            final result = await widget.firestoreService.loadTOWorkDetails(toItemForConfirmed.to);
            toItemForConfirmed.setWorkDetails(
              result['workDetails'] as List<WorkDetailModel>,
              result['workStats'] as Map<String, Map<String, int>>,
            );
          } catch (e) {
            if (mounted) Navigator.pop(context);
            ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
            return;
          }

          if (mounted) Navigator.pop(context);
        }

        if (!mounted) return;
        ConfirmedListDialog(
          context: context,
          toItem: toItemForConfirmed,
          firestoreService: widget.firestoreService,
          onLocalStatsChanged: () {
            if (mounted) setState(() {});
          },
        ).show();

      case 'manageWorkDetails':
        // ✅ WorkDetails 로드 확인 후 다이얼로그 열기
        if (widget.groupItem.groupTOs.isEmpty) {
          ToastHelper.showError('TO 정보를 불러올 수 없습니다.');
          return;
        }

        // 다중 슬롯이면 날짜 선택
        final toItemForManage = await _selectTOItem(context);
        if (toItemForManage == null || !mounted) return;

        if (!toItemForManage.isWorkDetailLoaded || toItemForManage.workDetails.isEmpty) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (_) => const Center(child: CircularProgressIndicator()),
          );

          try {
            final result = await widget.firestoreService.loadTOWorkDetails(toItemForManage.to);
            toItemForManage.setWorkDetails(
              result['workDetails'] as List<WorkDetailModel>,
              result['workStats'] as Map<String, Map<String, int>>,
            );
          } catch (e) {
            if (mounted) Navigator.pop(context);
            ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
            return;
          }

          if (mounted) Navigator.pop(context);
        }

        if (!mounted) return;
        WorkDetailManagementDialog(
          context: context,
          toItem: toItemForManage,
          firestoreService: widget.firestoreService,
          onComplete: widget.onChanged,
          onLocalStatsChanged: () {
            if (mounted) setState(() {});
          },
        ).show();
        break;
    }
  }

  /// 다중 슬롯 플렉스 TO에서 날짜 선택 다이얼로그
  /// 슬롯이 1개면 바로 반환, 여러 개면 날짜 선택 시트 표시
  Future<TOItem?> _selectTOItem(BuildContext context) async {
    final slots = widget.groupItem.groupTOs;
    if (slots.isEmpty) return null;
    if (slots.length == 1) return slots.first;

    return await showModalBottomSheet<TOItem>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                child: Text(
                  '날짜를 선택하세요',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: slots.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final toItem = slots[i];
                    final confirmed = toItem.confirmedCount;
                    final required = toItem.totalRequired;
                    final pending = toItem.pendingCount;
                    return ListTile(
                      leading: Icon(
                        Icons.event,
                        color: Theme.of(context).primaryColor,
                        size: ResponsiveHelper.iconSize(context, 20),
                      ),
                      title: Text(
                        FormatHelper.formatDate(toItem.to.date),
                        style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '$confirmed/$required',
                            style: ResponsiveHelper.bodyStyle(context, color: AppColors.infoDark)
                                .copyWith(fontWeight: FontWeight.bold),
                          ),
                          if (pending > 0)
                            Text(
                              ' +$pending',
                              style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
                            ),
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                          Icon(Icons.chevron_right, size: ResponsiveHelper.iconSize(context, 18), color: AppColors.grey400),
                        ],
                      ),
                      onTap: () => Navigator.pop(ctx, toItem),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 선택된 날짜에 해당하는 TO만 필터링
  List<TOItem> _getFilteredGroupTOs() {
    // selectedDate가 null이면 전체 표시 (리스트 뷰)
    if (widget.selectedDate == null) {
      return widget.groupItem.groupTOs;
    }
    
    // selectedDate가 있으면 해당 날짜 TO만 필터링 (캘린더 뷰)
    return widget.groupItem.groupTOs.where((toItem) {
      return DateUtils.isSameDay(toItem.to.date, widget.selectedDate!);
    }).toList();
  }
}