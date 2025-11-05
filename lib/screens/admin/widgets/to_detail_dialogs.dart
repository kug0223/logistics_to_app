import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/application_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/toast_helper.dart';
import '../models/to_detail_models.dart';

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
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.list_alt, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${dateFormat.format(date)} 확정 명단 (${confirmedList.length}명)',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: confirmedList.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      '확정된 지원자가 없습니다',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: confirmedList.length,
                  itemBuilder: (context, index) {
                    final applicant = confirmedList[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green[100],
                          child: Icon(Icons.person, color: Colors.green[700]),
                        ),
                        title: Text(
                          applicant['userName'],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('📱 ${applicant['userPhone']}'),
                            Text('💼 ${applicant['workType']} (${applicant['workTime']})'),
                            if (toItems.length > 1)
                              Text('📋 ${applicant['toTitle']}'),
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
              onPressed: () {
                // TODO: 연락처 복사 기능
                ToastHelper.showInfo('연락처 복사 기능은 준비 중입니다');
              },
              icon: const Icon(Icons.content_copy),
              label: const Text('연락처 복사'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
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
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.people, color: Colors.blue),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                '${work.workDetail.workType} 지원자 (${work.totalApplicants}명)',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 업무 정보
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.access_time, size: 16, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        '${work.workDetail.startTime}~${work.workDetail.endTime}',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue[900],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.attach_money, size: 16, color: Colors.blue[700]),
                      const SizedBox(width: 8),
                      Text(
                        work.workDetail.formattedWage,
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.blue[900],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                
                // 대기 중
                if (work.pendingApplicants.isNotEmpty) ...[
                  _buildSectionHeader('⏳ 대기 중', Colors.orange, work.pendingApplicants.length),
                  const SizedBox(height: 8),
                  ...work.pendingApplicants.map((applicant) {
                    return _buildApplicantCard(applicant, onConfirm, onReject);
                  }),
                  const SizedBox(height: 16),
                ],
                
                // 확정
                if (work.confirmedApplicants.isNotEmpty) ...[
                  _buildSectionHeader('✅ 확정', Colors.green, work.confirmedApplicants.length),
                  const SizedBox(height: 8),
                  ...work.confirmedApplicants.map((applicant) {
                    return _buildApplicantCard(applicant, onConfirm, onReject);
                  }),
                  const SizedBox(height: 16),
                ],
                
                // 거절
                if (work.rejectedApplicants.isNotEmpty) ...[
                  _buildSectionHeader('❌ 거절', Colors.red, work.rejectedApplicants.length),
                  const SizedBox(height: 8),
                  ...work.rejectedApplicants.map((applicant) {
                    return _buildApplicantCard(applicant, onConfirm, onReject);
                  }),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  // ========================================
  // Helper 위젯들
  // ========================================

  /// 섹션 헤더
  Widget _buildSectionHeader(String title, Color color, int count) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count명',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 지원자 카드
  Widget _buildApplicantCard(
    Map<String, dynamic> applicant,
    Function(String) onConfirm,
    Function(String) onReject,
  ) {
    final app = applicant['application'] as ApplicationModel;
    
    Color statusColor;
    String statusText;
    
    switch (app.status) {
      case 'PENDING':
        statusColor = Colors.orange;
        statusText = '대기중';
        break;
      case 'CONFIRMED':
        statusColor = Colors.green;
        statusText = '확정';
        break;
      case 'REJECTED':
        statusColor = Colors.red;
        statusText = '거절';
        break;
      default:
        statusColor = Colors.grey;
        statusText = app.status;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 이름
                Expanded(
                  child: Text(
                    applicant['userName'],
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                // 상태 배지
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: statusColor,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            
            // 연락처
            Row(
              children: [
                Icon(Icons.phone, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  applicant['userPhone'],
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[700],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 4),
            
            // 지원 시간
            Row(
              children: [
                Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  '지원: ${DateFormat('MM/dd HH:mm', 'ko_KR').format(app.appliedAt)}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),

            // 버튼 (대기 중인 경우만)
            if (app.status == 'PENDING') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onReject(applicant['applicationId']);
                      },
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('거절'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        onConfirm(applicant['applicationId']);
                      },
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('승인'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
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