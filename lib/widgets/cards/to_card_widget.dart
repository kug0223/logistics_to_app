import 'package:flutter/material.dart';
import '../../models/core/to_model.dart';
import '../../models/core/work_detail_model.dart';
import '../../models/core/application_model.dart';
import '../../services/firestore_service.dart';
import 'work_item_card.dart';
import '../common/styled_container.dart';

/// TO 카드 위젯 (공통 위젯)
class UserTOCard extends StatefulWidget {
  final TOModel to;
  final bool isSelected;
  final VoidCallback onTap;
  final List<ApplicationModel> myApplications;
  final VoidCallback onApplySuccess;

  const UserTOCard({
    super.key,
    required this.to,
    required this.isSelected,
    required this.onTap,
    required this.myApplications,
    required this.onApplySuccess,
  });

  @override
  State<UserTOCard> createState() => _UserTOCardState();
}

class _UserTOCardState extends State<UserTOCard> {
  final FirestoreService _firestoreService = FirestoreService();
  List<WorkDetailModel> _workDetails = [];
  bool _isLoadingWorkDetails = false;

  @override
  void didUpdateWidget(UserTOCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 선택 상태가 변경되면 업무 로드
    if (widget.isSelected && !oldWidget.isSelected) {
      _loadWorkDetails();
    }
  }

  /// 업무 상세 로드
  Future<void> _loadWorkDetails() async {
    if (_workDetails.isNotEmpty) return;
    
    setState(() => _isLoadingWorkDetails = true);
    
    try {
      final workDetails = await _firestoreService.getWorkDetails(widget.to.id);
      
      if (mounted) {
        setState(() {
          _workDetails = workDetails;
          _isLoadingWorkDetails = false;
        });
      }
    } catch (e) {
      print('❌ 업무 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoadingWorkDetails = false);
      }
    }
  }

  /// 내가 해당 TO에 지원했는지 확인
  bool get _hasAppliedToTO {
    return widget.myApplications.any((app) {
      // ✅ 날짜만 비교 (시간 제외)
      final dateMatch = app.workDate.year == widget.to.date.year &&
                      app.workDate.month == widget.to.date.month &&
                      app.workDate.day == widget.to.date.day;
      
      return app.businessId == widget.to.businessId &&
            app.toTitle == widget.to.title &&
            dateMatch;
    });
  }

  bool _hasAppliedToWork(String workType) {
    for (var app in widget.myApplications) {
      // ⭐ Phase 2: 취소/거절된 지원은 제외
      if (app.status == 'CANCELED' || 
          app.status == 'AUTO_CANCELED' || 
          app.status == 'REJECTED') {
        continue;
      }
      
      final businessMatch = app.businessId == widget.to.businessId;
      final titleMatch = app.toTitle == widget.to.title;
      final dateMatch = app.workDate.year == widget.to.date.year &&
                      app.workDate.month == widget.to.date.month &&
                      app.workDate.day == widget.to.date.day;
      final workTypeMatch = app.selectedWorkType == workType;
      
      if (businessMatch && titleMatch && dateMatch && workTypeMatch) {
        return true;
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: widget.isSelected ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.isSelected 
              ? Theme.of(context).primaryColor 
              : Colors.transparent,
          width: widget.isSelected ? 2 : 0,
        ),
      ),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          decoration: BoxDecoration(
            color: widget.isSelected
                ? Theme.of(context).primaryColor.withOpacity(0.05)
                : null,
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🔥 첫 번째 줄: 사업장명(좌) + 배지들(우)
              Row(
                children: [
                  // 사업장명
                  Expanded(
                    child: Row(
                      children: [
                        Icon(Icons.business, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            widget.to.businessName,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[800],
                              fontWeight: FontWeight.w600,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(width: 8),
                  
                  // 배지들
                  Wrap(
                    spacing: 4,
                    children: [
                      // 단기/장기 배지
                      if (widget.to.isShortTerm)
                        StyledBadge(
                          label: '단기',
                          backgroundColor: Colors.blue[100]!,
                          textColor: Colors.blue[700]!,
                          fontSize: 11,
                        ),
                      if (widget.to.isLongTerm)
                        StyledBadge(
                          label: '장기',
                          backgroundColor: Colors.purple[100]!,
                          textColor: Colors.purple[700]!,
                          fontSize: 11,
                        ),

                      // 마감임박 배지
                      if (widget.to.isDeadlineSoon)
                        StyledBadge(
                          label: '마감임박',
                          backgroundColor: Colors.orange[100]!,
                          textColor: Colors.orange[700]!,
                          fontSize: 11,
                        ),
                      
                      // 지원완료 배지
                      if (_hasAppliedToTO)
                        StyledBadge(
                          label: '지원완료',
                          backgroundColor: Colors.green[100]!,
                          textColor: Colors.green[700]!,
                          fontSize: 11,
                        ),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // 🔥 두 번째 줄: 공고 제목
              Text(
                widget.to.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              
              const SizedBox(height: 8),
              
              // 🔥 세 번째 줄: 날짜 (장기/단기 구분)
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(
                    widget.to.isLongTerm && widget.to.endDate != null
                        ? '${widget.to.date.month}/${widget.to.date.day} ~ ${widget.to.endDate!.month}/${widget.to.endDate!.day}'
                        : '${widget.to.date.month}/${widget.to.date.day} (${_getWeekday(widget.to.date)})',
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                ],
              ),
              
              // 펼친 상태일 때만 업무 목록 표시
              if (widget.isSelected) ...[
                const SizedBox(height: 12),
                const Divider(),
                const SizedBox(height: 8),
                _buildWorkDetailsList(),
              ],
              
              // 펼치기/접기 버튼
              const SizedBox(height: 8),
              Center(
                child: Icon(
                  widget.isSelected ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 업무 목록
  Widget _buildWorkDetailsList() {
    if (_isLoadingWorkDetails) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_workDetails.isEmpty) {
      return const Text(
        '업무 정보가 없습니다',
        style: TextStyle(color: Colors.grey),
      );
    }

    return Column(
      children: _workDetails.map((work) {
        return WorkItemCard(
          work: work,
          to: widget.to,
          hasApplied: _hasAppliedToWork(work.workType),
          onApplySuccess: widget.onApplySuccess,
        );
      }).toList(),
    );
  }

  /// 요일 반환
  String _getWeekday(DateTime date) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return weekdays[date.weekday - 1];
  }
}