import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/work_detail_model.dart';
import '../../../models/application_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/format_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../models/to_list_models.dart';

class ConfirmedListDialog {
  final BuildContext context;
  final TOItem toItem;
  final FirestoreService firestoreService;

  ConfirmedListDialog({
    required this.context,
    required this.toItem,
    required this.firestoreService,
  });

  void show() {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: const BoxConstraints(maxWidth: 500),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 헤더
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  border: Border(
                    bottom: BorderSide(color: Colors.green[200]!),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '확정 명단',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${DateFormat('MM/dd (E)', 'ko_KR').format(toItem.to.date)} - ${toItem.to.title}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[700],
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              
              // 업무별 확정 명단
              Flexible(
                child: FutureBuilder<Map<String, List<Map<String, dynamic>>>>(
                  future: _loadConfirmedApplicants(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: CircularProgressIndicator(),
                        ),
                      );
                    }
                    
                    if (snapshot.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text('오류: ${snapshot.error}'),
                        ),
                      );
                    }
                    
                    final confirmedByWork = snapshot.data ?? {};
                    
                    if (confirmedByWork.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.person_off, size: 48, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                '확정된 지원자가 없습니다',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    
                    return ListView(
                      padding: const EdgeInsets.all(16),
                      shrinkWrap: true,
                      children: toItem.workDetails.map((work) {
                        final applicants = confirmedByWork[work.workType] ?? [];
                        
                        if (applicants.isEmpty) return const SizedBox.shrink();
                        
                        return _buildWorkSection(work, applicants);
                      }).toList(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 확정된 지원자 로드
  Future<Map<String, List<Map<String, dynamic>>>> _loadConfirmedApplicants() async {
    final applications = await firestoreService.getApplicationsByTO(
      toItem.to.businessId,
      toItem.to.title,
      toItem.to.date,
    );
    
    // 확정된 지원자만 필터링
    final confirmed = applications.where((app) => app.status == 'CONFIRMED').toList();
    
    // 업무별로 그룹화
    final Map<String, List<Map<String, dynamic>>> result = {};
    
    for (var app in confirmed) {
      // 사용자 정보 조회
      final user = await firestoreService.getUser(app.uid);
      
      if (user != null) {
        result.putIfAbsent(app.selectedWorkType, () => []);
        result[app.selectedWorkType]!.add({
          'application': app,
          'user': user,
        });
      }
    }
    
    return result;
  }

  // 업무별 섹션
  Widget _buildWorkSection(WorkDetailModel work, List<Map<String, dynamic>> applicants) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 업무 헤더
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: FormatHelper.parseColor(work.workTypeColor).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: FormatHelper.parseColor(work.workTypeColor),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: WorkTypeIcon.buildFromString(
                      work.workTypeIcon,
                      color: Colors.white,
                      size: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        work.workType,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${work.startTime}~${work.endTime} | ${NumberFormat('#,###').format(work.wage)}원',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green[600],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${applicants.length}/${work.requiredCount}명',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // 지원자 목록
          ...applicants.asMap().entries.map((entry) {
            final index = entry.key;
            final data = entry.value;
            final user = data['user'];
            final app = data['application'] as ApplicationModel;
            
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: index < applicants.length - 1
                      ? BorderSide(color: Colors.grey[200]!)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  // 번호
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.green[100],
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  
                  // 이름
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (user.phone.isNotEmpty)
                          Text(
                            user.phone,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                  
                  // 확정 시간
                  if (app.confirmedAt != null)
                    Text(
                      DateFormat('MM/dd HH:mm').format(app.confirmedAt!),
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey[500],
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }
}