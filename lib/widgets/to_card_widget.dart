import 'package:flutter/material.dart';
import '../models/to_model.dart';

/// TO 정보를 표시하는 카드 위젯
class TOCardWidget extends StatelessWidget {
  final TOModel to;
  final VoidCallback? onTap;
  final String? applicationStatus; // 지원 상태 추가!

  const TOCardWidget({
    Key? key,
    required this.to,
    this.onTap,
    this.applicationStatus, // 추가!
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    print('🎴 TOCardWidget - TO: ${to.id}, 지원상태: $applicationStatus');
    
    return Card(
      elevation: 3,
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
              // 상단: 날짜 + 요일 + 상태 배지
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // 날짜 정보
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today,
                        size: 18,
                        color: Colors.blue[700],
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            to.formattedDate,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87,
                            ),
                          ),
                          Text(
                            to.weekday,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  
                  // 상태 배지
                  _buildStatusBadge(),
                ],
              ),
              
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              
              // 시간 정보
              _buildInfoRow(
                Icons.access_time,
                '시간',
                to.timeRange,
                Colors.orange,
              ),
              
              const SizedBox(height: 8),
              
              // 업무 유형
              _buildInfoRow(
                Icons.work,
                '업무',
                to.workType,
                Colors.purple,
              ),
              
              const SizedBox(height: 8),
              
              // 인원 정보
              _buildInfoRow(
                Icons.people,
                '인원',
                '${to.currentCount}/${to.requiredCount}명 (남은 자리: ${to.remainingCount}명)',
                to.isAvailable ? Colors.green : Colors.red,
              ),
              
              // 설명 (있을 경우)
              if (to.description != null && to.description!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Colors.grey[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          to.description!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[800],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 정보 행 빌더
  Widget _buildInfoRow(IconData icon, String label, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey[700],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              color: Colors.black87,
            ),
          ),
        ),
      ],
    );
  }

  /// 상태 배지 (지원 가능 여부)
  Widget _buildStatusBadge() {
    print('🏷️ 배지 빌드 - applicationStatus: $applicationStatus');
    
    // 내가 지원한 상태가 있으면 우선 표시
    if (applicationStatus != null) {
      print('✅ 지원 상태 있음: $applicationStatus');
      switch (applicationStatus) {
        case 'PENDING':
          return _buildBadge(
            '지원 완료 (대기)',
            Colors.orange,
            Icons.schedule,
          );
        case 'CONFIRMED':
          return _buildBadge(
            '확정됨',
            Colors.blue,
            Icons.check_circle,
          );
        case 'REJECTED':
          return _buildBadge(
            '거절됨',
            Colors.red,
            Icons.cancel,
          );
      }
    }

    print('⚪ 지원 안 함 - 기본 배지');
    
    // 지원 안 했으면 기존 로직
    final isAvailable = to.isAvailable;
    final color = isAvailable ? Colors.green : Colors.red;
    final text = isAvailable ? '지원 가능' : '마감';
    final icon = isAvailable ? Icons.check_circle : Icons.cancel;

    return _buildBadge(text, color, icon);
  }

  /// 배지 빌더
  Widget _buildBadge(String text, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}