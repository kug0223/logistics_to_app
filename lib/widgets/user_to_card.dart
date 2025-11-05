import 'package:flutter/material.dart';
import '../models/to_model.dart';
import '../models/work_detail_model.dart';
import '../models/application_model.dart';
import '../services/firestore_service.dart';
import '../utils/format_helper.dart';
import 'work_type_icon.dart';

class UserTOCard extends StatefulWidget {  // ⭐ StatefulWidget으로 변경
  final TOModel to;
  final bool isSelected;
  final VoidCallback onTap;
  final List<ApplicationModel> myApplications;
  
  const UserTOCard({
    Key? key,
    required this.to,
    required this.isSelected,
    required this.onTap,
    required this.myApplications,
  }) : super(key: key);

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
    
    // ⭐ 선택 상태가 변경되면 업무 로드
    if (widget.isSelected && !oldWidget.isSelected) {
      _loadWorkDetails();
    }
  }
  
  /// 업무 상세 로드
  Future<void> _loadWorkDetails() async {
    if (_workDetails.isNotEmpty) return; // 이미 로드됨
    
    setState(() {
      _isLoadingWorkDetails = true;
    });
    
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
        setState(() {
          _isLoadingWorkDetails = false;
        });
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.only(bottom: 12),
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
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 배지
              _buildBadges(),
              
              SizedBox(height: 12),
              
              // 사업장 정보
              _buildBusinessInfo(),
              
              // 펼친 상태에만 표시
              if (widget.isSelected) ...[
                SizedBox(height: 16),
                Divider(),
                SizedBox(height: 12),
                
                // 업무 상세 목록
                _buildWorkDetailsList(context),
              ],
              
              // 펼치기/접기 버튼
              SizedBox(height: 12),
              _buildExpandButton(),
            ],
          ),
        ),
      ),
    );
  }
  
  /// 배지 영역
  Widget _buildBadges() {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        // 단기/장기
        if (widget.to.isShortTerm)
          _buildBadge(
            icon: Icons.event,
            label: '단기 알바',
            backgroundColor: Colors.blue[100]!,
            textColor: Colors.blue[700]!,
          ),
        
        if (widget.to.isLongTerm)
          _buildBadge(
            icon: Icons.event_repeat,
            label: '1개월+ 계약직',
            backgroundColor: Colors.purple[100]!,
            textColor: Colors.purple[700]!,
          ),
        
        // 마감 임박
        if (widget.to.isDeadlineSoon)
          _buildBadge(
            icon: Icons.local_fire_department,
            label: '마감임박',
            backgroundColor: Colors.orange[100]!,
            textColor: Colors.orange[700]!,
          ),
      ],
    );
  }
  
  Widget _buildBadge({
    required IconData icon,
    required String label,
    required Color backgroundColor,
    required Color textColor,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: textColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: textColor),
          SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
        ],
      ),
    );
  }
  
  /// 사업장 정보
  Widget _buildBusinessInfo() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 사업장명
        Row(
          children: [
            Icon(Icons.business, size: 18, color: Colors.grey[700]),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.to.businessName,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        
        SizedBox(height: 8),
        
        // 날짜 정보
        Row(
          children: [
            Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
            SizedBox(width: 8),
            Text(
              widget.to.isLongTerm 
                  ? widget.to.longTermPeriodWithDays 
                  : widget.to.formattedDate,
              style: TextStyle(fontSize: 14),
            ),
            
            // 접힌 상태: 급여 정보 표시
            if (!widget.isSelected && _workDetails.isNotEmpty) ...[
              SizedBox(width: 16),
              Icon(Icons.attach_money, size: 16, color: Colors.green[600]),
              SizedBox(width: 4),
              Text(
                _getWageRange(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
            ],
          ],
        ),
        
        // 장기: 근무 요일
        if (widget.to.isLongTerm && widget.to.workDaysLabel != null) ...[
          SizedBox(height: 4),
          Row(
            children: [
              Icon(Icons.event_repeat, size: 16, color: Colors.purple[600]),
              SizedBox(width: 8),
              Text(
                widget.to.workDaysLabel!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.purple[700],
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
  
  /// 급여 범위 (접힌 상태용)
  String _getWageRange() {
    if (_workDetails.isEmpty) return '';
    
    final wages = _workDetails.map((w) => w.wage).toList();
    final minWage = wages.reduce((a, b) => a < b ? a : b);
    final maxWage = wages.reduce((a, b) => a > b ? a : b);
    
    if (minWage == maxWage) {
      return FormatHelper.formatWage(minWage);
    }
    
    return '${FormatHelper.formatWage(minWage)}~${FormatHelper.formatWage(maxWage)}';
  }
  
  /// 업무 상세 목록
  Widget _buildWorkDetailsList(BuildContext context) {
    if (_isLoadingWorkDetails) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    if (_workDetails.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text(
            '업무 정보가 없습니다',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '📋 업무 상세',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 12),
        
        // 업무 카드들
        ..._workDetails.map((work) => _buildWorkDetailCard(context, work)),
      ],
    );
  }
  
  /// 업무 카드
  Widget _buildWorkDetailCard(BuildContext context, WorkDetailModel work) {
    return Container(
      margin: EdgeInsets.only(bottom: 8),
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 업무명
          Row(
            children: [
                Text(
                work.workTypeIcon ?? '📋',
                style: TextStyle(fontSize: 20),
              ),
              SizedBox(width: 8),
              Text(
                work.workType,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          
          SizedBox(height: 8),
          
          // 시간 + 금액
          Row(
            children: [
              Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
              SizedBox(width: 4),
              Text(
                '${work.startTime}~${work.endTime}',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(width: 16),
              Icon(Icons.attach_money, size: 16, color: Colors.green[600]),
              SizedBox(width: 4),
              Text(
                FormatHelper.formatWage(work.wage),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: Colors.green[700],
                ),
              ),
            ],
          ),
          
          SizedBox(height: 4),
          
          // 모집 인원 + 마감 시간
          Row(
            children: [
              Icon(Icons.people, size: 16, color: Colors.grey[600]),
              SizedBox(width: 4),
              Text(
                '${work.requiredCount}명 모집',
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(width: 16),
              Icon(Icons.schedule, size: 16, color: Colors.orange[600]),
              SizedBox(width: 4),
              Text(
                _getDeadlineText(work),
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.orange[700],
                ),
              ),
            ],
          ),
          
          SizedBox(height: 12),
          
          // 버튼들
          Row(
            children: [
              // [자세히] 버튼
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    // TODO: 업무 상세 다이얼로그
                  },
                  icon: Icon(Icons.info_outline, size: 16),
                  label: Text('자세히'),
                  style: OutlinedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    side: BorderSide(color: Colors.grey[400]!),
                  ),
                ),
              ),
              
              SizedBox(width: 8),
              
              // [지원하기] 버튼
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    // TODO: 지원 다이얼로그
                  },
                  icon: Icon(Icons.check_circle, size: 16),
                  label: Text('지원하기'),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    backgroundColor: Colors.green[600],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  String _getDeadlineText(WorkDetailModel work) {
    if (work.applicationDeadline == null) return '마감시간 미정';
    
    final deadline = work.applicationDeadline!;
    final now = DateTime.now();
    final diff = deadline.difference(now);
    
    if (diff.isNegative) return '마감';
    if (diff.inHours < 1) return '${diff.inMinutes}분 남음';
    if (diff.inHours < 24) return '${diff.inHours}시간 남음';
    
    return '${deadline.month}/${deadline.day} ${deadline.hour}:${deadline.minute.toString().padLeft(2, '0')}';
  }
  
  /// 펼치기/접기 버튼
  Widget _buildExpandButton() {
    return Center(
      child: Text(
        widget.isSelected ? '접기 ▲' : '자세히 보기 ▼',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Colors.grey[600],
        ),
      ),
    );
  }
}