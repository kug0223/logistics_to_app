import 'package:flutter/material.dart';
import '../models/core/to_model.dart';
import 'common/styled_container.dart';

/// TO 정보를 표시하는 카드 위젯 - 신버전
class TOCardWidget extends StatelessWidget {
  final TOModel to;
  final VoidCallback? onTap;
  final String? applicationStatus; // 지원 상태 (PENDING, CONFIRMED, REJECTED, CANCELED)

  const TOCardWidget({
    super.key,
    required this.to,
    this.onTap,
    this.applicationStatus,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1행: 사업장명 + 배지들
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      to.businessName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // 배지들
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 마감 배지
                      _buildDeadlineBadge(),
                      const SizedBox(width: 4),
                      
                      // 지원 상태 배지
                      if (applicationStatus != null) _buildStatusBadge(),
                    ],
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              // ✅ 그룹명 + 제목
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 그룹명 표시 (그룹 TO일 경우만)
                  if (to.isGrouped && to.groupName != null) ...[
                    Row(
                      children: [
                        Icon(Icons.link, size: 12, color: Colors.green[700]),
                        const SizedBox(width: 4),
                        Text(
                          to.groupName!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green[700],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ],
                  
                  // 제목
                  Text(
                    to.title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[800],
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              
              const SizedBox(height: 12),
              
             // 2행: 날짜 + 요일 (장기/단기 분기)
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Expanded(
                    child: to.isLongTerm 
                      ? Column(  // ⭐ 장기는 2줄
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              to.longTermPeriodWithDays,  // "1/7 ~ 2/7"
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[700],
                              ),
                            ),
                            if (to.workDays != null && to.workDays!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                to.workDaysLabel,  // "주 3일 (월, 수, 금)"
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ],
                        )
                      : Text(  // 단기는 1줄
                          '${to.formattedDate} (${to.weekday})',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey[700],
                          ),
                        ),
                  ),
                ],
              ),
              
              const SizedBox(height: 8),
              
              // 3행: 시간대
              Row(
                children: [
                  Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(
                    to.displayTimeRange,  // ✅ 계산된 시간 범위 사용!
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],  // 색상도 변경
                      fontWeight: FontWeight.w500,  // 굵기 추가
                    ),
                  ),
                ],
              ),
              
              const Divider(height: 20, thickness: 1),
              
              // 4행: 인원 정보 + 마감까지 남은 시간
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ✅ 전체 인원 정보
                  Row(
                    children: [
                      Icon(Icons.people, size: 16, color: Colors.blue[700]),
                      const SizedBox(width: 6),
                      Text(
                        '${to.totalConfirmed}/${to.totalRequired}명',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  
                  // 마감까지 남은 시간
                  if (!to.isDeadlinePassed)
                    Row(
                      children: [
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: Colors.orange[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          to.deadlineStatus, // "3시간 남음"
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange[600],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ✅ 마감 배지 빌드 메서드
  Widget _buildDeadlineBadge() {
    if (to.isDeadlinePassed) {
      // ⭐ 변경: StyledBadge 사용
      return StyledBadge(
        label: '마감',
        backgroundColor: Colors.red[50]!,
        textColor: Colors.red[700]!,
        icon: Icons.lock_clock,
        fontSize: 12,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      );
    } else {
      final hoursLeft = to.applicationDeadline.difference(DateTime.now()).inHours;
      
      if (hoursLeft <= 24) {
        // ⭐ 변경: StyledBadge 사용
        return StyledBadge(
          label: to.deadlineStatus,
          backgroundColor: Colors.orange[50]!,
          textColor: Colors.orange[700]!,
          icon: Icons.access_alarm,
          fontSize: 12,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        );
      }
    }
    
    return const SizedBox.shrink();
  }

  /// 지원 상태 배지
  Widget _buildStatusBadge() {
    // ⭐ 변경: StyledBadge 사용
    switch (applicationStatus) {
      case 'PENDING':
        return StyledBadge(
          label: '대기',
          backgroundColor: Colors.orange.shade50,
          textColor: Colors.orange.shade700,
          fontSize: 11,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        );
      case 'CONFIRMED':
        return StyledBadge(
          label: '확정',
          backgroundColor: Colors.blue.shade50,
          textColor: Colors.blue.shade700,
          fontSize: 11,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        );
      case 'REJECTED':
        return StyledBadge(
          label: '거절',
          backgroundColor: Colors.red.shade50,
          textColor: Colors.red.shade700,
          fontSize: 11,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        );
      case 'CANCELED':
        return StyledBadge(
          label: '취소',
          backgroundColor: Colors.grey.shade100,
          textColor: Colors.grey.shade600,
          fontSize: 11,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        );
      default:
        return StyledBadge(
          label: '지원 가능',
          backgroundColor: Colors.green.shade50,
          textColor: Colors.green.shade700,
          fontSize: 11,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        );
    }
  }
}