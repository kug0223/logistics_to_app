import 'package:flutter/material.dart';
import '../models/to_model.dart';

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
              
              // ✅ 제목
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
              
              const SizedBox(height: 12),
              
              // 2행: 날짜 + 요일
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                  const SizedBox(width: 6),
                  Text(
                    '${to.formattedDate} (${to.weekday})',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
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
                    to.timeRange, // "09:00 - 18:00"
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[700],
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
      // 마감됨 (빨간색)
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_clock,
              size: 14,
              color: Colors.red[700],
            ),
            const SizedBox(width: 4),
            Text(
              '마감',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: Colors.red[700],
              ),
            ),
          ],
        ),
      );
    } else {
      // 마감 임박 (주황색) - 24시간 이내
      final hoursLeft = to.applicationDeadline.difference(DateTime.now()).inHours;
      
      if (hoursLeft <= 24) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.orange[50],
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.shade300),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.access_alarm,
                size: 14,
                color: Colors.orange[700],
              ),
              const SizedBox(width: 4),
              Text(
                to.deadlineStatus, // "3시간 남음"
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[700],
                ),
              ),
            ],
          ),
        );
      }
    }
    
    return const SizedBox.shrink(); // 마감 임박 아니면 표시 안 함
  }

  /// 지원 상태 배지
  Widget _buildStatusBadge() {
    Color bgColor;
    Color textColor;
    String text;

    switch (applicationStatus) {
      case 'PENDING':
        bgColor = Colors.orange.shade50;
        textColor = Colors.orange.shade700;
        text = '대기';
        break;
      case 'CONFIRMED':
        bgColor = Colors.blue.shade50;
        textColor = Colors.blue.shade700;
        text = '확정';
        break;
      case 'REJECTED':
        bgColor = Colors.red.shade50;
        textColor = Colors.red.shade700;
        text = '거절';
        break;
      case 'CANCELED':
        bgColor = Colors.grey.shade100;
        textColor = Colors.grey.shade600;
        text = '취소';
        break;
      default:
        bgColor = Colors.green.shade50;
        textColor = Colors.green.shade700;
        text = '지원 가능';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: textColor.withOpacity(0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: textColor,
        ),
      ),
    );
  }
}