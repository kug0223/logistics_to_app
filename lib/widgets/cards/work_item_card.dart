import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/core/work_detail_model.dart';
import '../../models/core/to_model.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';  // ⭐ 추가
import '../../screens/user/dialogs/work_detail_dialog.dart';
import '../../screens/user/dialogs/apply_dialog.dart';
import '../work_type_icon.dart';

/// 업무 항목 카드 (공통 위젯) - StatefulWidget으로 변경
class WorkItemCard extends StatefulWidget {
  final WorkDetailModel work;
  final TOModel to;
  final bool hasApplied;
  final VoidCallback onApplySuccess;

  const WorkItemCard({
    super.key,
    required this.work,
    required this.to,
    required this.hasApplied,
    required this.onApplySuccess,
  });

  @override
  State<WorkItemCard> createState() => _WorkItemCardState();
}

class _WorkItemCardState extends State<WorkItemCard> {
  late bool _localHasApplied;

  @override
  void initState() {
    super.initState();
    _localHasApplied = widget.hasApplied;
  }

  @override
  void didUpdateWidget(WorkItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hasApplied != widget.hasApplied) {
      _localHasApplied = widget.hasApplied;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
      padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 🔥 업무명 (공통 위젯 사용)
          Row(
            children: [
              WorkTypeIcon.buildWithBackground(
                iconString: widget.work.workTypeIcon ?? 'work',
                iconColor: widget.work.workTypeColor,
                backgroundColor: widget.work.workTypeBackgroundColor,
                size: ResponsiveHelper.iconSize(context, 18),  // ⭐ 변경
                containerSize: ResponsiveHelper.iconSize(context, 36),  // ⭐ 변경
              ),
              
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
              
              Expanded(
                child: Text(
                  widget.work.workType,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경

          // ⭐ 시간
          Row(
            children: [
              Icon(
                Icons.access_time,
                size: ResponsiveHelper.iconSize(context, 14),  // ⭐ 변경
                color: Colors.grey[600],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
              Text(
                '${widget.work.startTime}~${widget.work.endTime}',
                style: ResponsiveHelper.smallStyle(context),  // ⭐ 변경
              ),
            ],
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경

          // ⭐ 금액 + 마감시간 (반응형)
          LayoutBuilder(
            builder: (context, constraints) {
              final deadlineText = widget.work.applicationDeadline != null
                  ? '마감: ${DateFormat('M/d HH:mm').format(widget.work.applicationDeadline!)}'
                  : widget.to.deadlineType == 'HOURS_BEFORE' && widget.to.hoursBeforeStart != null
                      ? '마감: ${widget.to.hoursBeforeStart}시간 전'
                      : null;
              
              if (constraints.maxWidth < 300 && deadlineText != null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 금액
                    Row(
                      children: [
                        Icon(
                          Icons.attach_money,
                          size: ResponsiveHelper.iconSize(context, 14),  // ⭐ 변경
                          color: Colors.green[600],
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                        Text(
                          FormatHelper.formatWage(widget.work.wage),
                          style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                            context,
                            color: Colors.green[700],
                          ).copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                    // 마감시간
                    Row(
                      children: [
                        Icon(
                          Icons.alarm,
                          size: ResponsiveHelper.iconSize(context, 13),  // ⭐ 변경
                          color: Colors.orange[600],
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                        Text(
                          deadlineText,
                          style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                            context,
                            color: Colors.orange[700],
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              }
              
              // 넓은 화면이면 한 줄로 배치
              return Row(
                children: [
                  Icon(
                    Icons.attach_money,
                    size: ResponsiveHelper.iconSize(context, 14),  // ⭐ 변경
                    color: Colors.green[600],
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                  Text(
                    FormatHelper.formatWage(widget.work.wage),
                    style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                      context,
                      color: Colors.green[700],
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (deadlineText != null) ...[
                    const Spacer(),
                    Icon(
                      Icons.alarm,
                      size: ResponsiveHelper.iconSize(context, 13),  // ⭐ 변경
                      color: Colors.orange[600],
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                    Text(
                      deadlineText,
                      style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                        context,
                        color: Colors.orange[700],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경

          // 모집 인원
          Row(
            children: [
              Icon(
                Icons.people,
                size: ResponsiveHelper.iconSize(context, 14),  // ⭐ 변경
                color: Colors.grey[600],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
              Text(
                '${widget.work.requiredCount}명 모집',
                style: ResponsiveHelper.smallStyle(context),  // ⭐ 변경
              ),
            ],
          ),
          
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
          
          // 버튼들
          Row(
            children: [
              // 자세히 버튼
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    WorkDetailDialog.show(
                      context: context,
                      work: widget.work,
                    );
                  },
                  icon: Icon(
                    Icons.info_outline,
                    size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                  ),
                  label: const Text('자세히'),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(  // ⭐ const 제거
                      vertical: ResponsiveHelper.spacing(context, 8),  // ⭐ 변경
                    ),
                    side: BorderSide(color: Colors.grey[400]!),
                  ),
                ),
              ),
              
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
              
              // 지원하기 버튼
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _localHasApplied || widget.work.isClosed || widget.work.isTimeExpired
                      ? null
                      : () async {
                          final success = await ApplyDialog.show(
                            context: context,
                            work: widget.work,
                            to: widget.to,
                            onSuccess: widget.onApplySuccess,
                          );
                          
                          if (success && mounted) {
                            setState(() {
                              _localHasApplied = true;
                            });
                          }
                        },
                  icon: Icon(
                    _localHasApplied ? Icons.check : Icons.send,
                    size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                  ),
                  label: Text(
                    _localHasApplied 
                        ? '지원완료' 
                        : (widget.work.isClosed || widget.work.isTimeExpired)
                            ? '마감됨'
                            : '지원하기'
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(  // ⭐ const 제거
                      vertical: ResponsiveHelper.spacing(context, 8),  // ⭐ 변경
                    ),
                    backgroundColor: _localHasApplied ? Colors.grey : null,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}