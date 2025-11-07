import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/format_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';

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
      builder: (context) => _ConfirmedListDialogWidget(
        toItem: toItem,
        firestoreService: firestoreService,
      ),
    );
  }
}

// ✅ StatefulWidget으로 변경!
class _ConfirmedListDialogWidget extends StatefulWidget {
  final TOItem toItem;
  final FirestoreService firestoreService;

  const _ConfirmedListDialogWidget({
    required this.toItem,
    required this.firestoreService,
  });

  @override
  State<_ConfirmedListDialogWidget> createState() => _ConfirmedListDialogWidgetState();
}

class _ConfirmedListDialogWidgetState extends State<_ConfirmedListDialogWidget> {
  // ✅ 상태 변수 추가
  bool _isLoading = true;
  Map<String, List<Map<String, dynamic>>> _confirmedByWork = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConfirmedApplicants(); // ✅ initState에서 로드!
  }

  // ✅ 확정된 지원자 로드 (병렬 최적화!)
  Future<void> _loadConfirmedApplicants() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final applications = await widget.firestoreService.getApplicationsByTO(
        widget.toItem.to.businessId,
        widget.toItem.to.title,
        widget.toItem.to.date,
      );
      
      // 확정된 지원자만 필터링
      final confirmed = applications.where((app) => app.status == 'CONFIRMED').toList();
      
      // ✅ 병렬로 사용자 정보 조회!
      final futures = confirmed.map((app) async {
        final user = await widget.firestoreService.getUser(app.uid);
        return {
          'application': app,
          'user': user,
          'workType': app.selectedWorkType,
        };
      }).toList();
      
      final results = await Future.wait(futures);
      
      // 업무별로 그룹화
      final Map<String, List<Map<String, dynamic>>> groupedByWork = {};
      
      for (var result in results) {
        if (result['user'] != null) {
          final workType = result['workType'] as String;
          groupedByWork.putIfAbsent(workType, () => []);
          groupedByWork[workType]!.add(result);
        }
      }
      
      setState(() {
        _confirmedByWork = groupedByWork;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 확정 명단 로드 실패: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
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
                          '${DateFormat('MM/dd (E)', 'ko_KR').format(widget.toItem.to.date)} - ${widget.toItem.to.title}',
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
            
            // ✅ 로딩/에러/데이터 표시
            Flexible(
              child: _buildContent(),
            ),
          ],
        ),
      ),
    );
  }

  // ✅ 컨텐츠 빌드
  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: CircularProgressIndicator(),
        ),
      );
    }
    
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('오류: $_error'),
        ),
      );
    }
    
    if (_confirmedByWork.isEmpty) {
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
      children: widget.toItem.workDetails.map((work) {
        final applicants = _confirmedByWork[work.workType] ?? [];
        
        if (applicants.isEmpty) return const SizedBox.shrink();
        
        return _buildWorkSection(work, applicants);
      }).toList(),
    );
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
              color: Colors.grey[50],
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                // 업무 아이콘
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: FormatHelper.parseColor(work.workTypeBackgroundColor ?? '#2196F3'),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: WorkTypeIcon.buildFromString(
                      work.workTypeIcon,
                      color: work.workTypeColor != null 
                          ? FormatHelper.parseColor(work.workTypeColor) 
                          : Colors.white,
                      size: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                
                // 업무명
                Expanded(
                  child: Text(
                    work.workType,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                // 인원 배지
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
                  
                  // 정보
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? '이름 없음',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '📱 ${user?.phone ?? '전화번호 없음'}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[700],
                          ),
                        ),
                        Text(
                          '💰 ${FormatHelper.formatWage(app.wage)}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}