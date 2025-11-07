import 'package:flutter/material.dart';
import '../models/work_detail_model.dart';
import '../models/to_model.dart';
import '../models/application_model.dart';
import '../utils/format_helper.dart';
import '../screens/user/dialogs/work_detail_dialog.dart';
import '../screens/user/dialogs/apply_dialog.dart';
import '../widgets/work_type_icon.dart';

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
  late bool _localHasApplied; // ✅ 로컬 상태 추가

  @override
  void initState() {
    super.initState();
    _localHasApplied = widget.hasApplied;
  }

  @override
  void didUpdateWidget(WorkItemCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // ✅ props가 바뀌면 로컬 상태도 업데이트
    if (oldWidget.hasApplied != widget.hasApplied) {
      _localHasApplied = widget.hasApplied;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
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
              // ✅ 공통 위젯으로 아이콘 + 배경색 처리
              WorkTypeIcon.buildWithBackground(
                iconString: widget.work.workTypeIcon ?? 'work',
                iconColor: widget.work.workTypeColor,
                backgroundColor: widget.work.workTypeBackgroundColor,
                size: 18,
                containerSize: 36,
              ),
              
              const SizedBox(width: 12),
              
              Expanded(
                child: Text(
                  widget.work.workType,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 8),
          
          // 시간 + 금액
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                '${widget.work.startTime}~${widget.work.endTime}',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(width: 16),
              Icon(Icons.attach_money, size: 14, color: Colors.green[600]),
              const SizedBox(width: 4),
              Text(
                FormatHelper.formatWage(widget.work.wage),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 4),
          
          // 모집 인원
          Row(
            children: [
              Icon(Icons.people, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                '${widget.work.requiredCount}명 모집',
                style: const TextStyle(fontSize: 13),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
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
                  icon: const Icon(Icons.info_outline, size: 16),
                  label: const Text('자세히'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: Colors.grey[400]!),
                  ),
                ),
              ),
              
              const SizedBox(width: 8),
              
              // 지원하기 버튼
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: _localHasApplied || widget.work.isClosed || widget.work.isTimeExpired // ✅ 추가!
                      ? null
                      : () async {
                          final success = await ApplyDialog.show(
                            context: context,
                            work: widget.work,
                            to: widget.to,
                            onSuccess: widget.onApplySuccess,
                          );
                          
                          // ✅ 지원 성공 시 로컬 상태 즉시 업데이트
                          if (success && mounted) {
                            setState(() {
                              _localHasApplied = true;
                            });
                          }
                        },
                  icon: Icon(
                    _localHasApplied ? Icons.check : Icons.send, // ✅ 로컬 상태 사용
                    size: 16,
                  ),
                  label: Text(
                    _localHasApplied 
                        ? '지원완료' 
                        : (widget.work.isClosed || widget.work.isTimeExpired)
                            ? '마감됨'
                            : '지원하기'
                  ),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    backgroundColor: _localHasApplied ? Colors.grey : null, // ✅ 로컬 상태 사용
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