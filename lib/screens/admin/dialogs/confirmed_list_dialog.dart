import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';  // ⭐ 추가
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
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                border: Border(
                  bottom: BorderSide(color: Colors.green.withOpacity(0.3)),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),  // ⭐ 변경
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '확정 명단',
                          style: ResponsiveHelper.titleStyle(context),  // ⭐ 변경
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                        Text(
                          '${DateFormat('MM/dd (E)', 'ko_KR').format(widget.toItem.to.date)} - ${widget.toItem.to.title}',
                          style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                            context,
                            color: Theme.of(context).textTheme.bodyMedium?.color,
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
      return Center(
        child: Padding(
          padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
          child: const CircularProgressIndicator(),
        ),
      );
    }
    
    if (_error != null) {
      return Center(
        child: Padding(
          padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
          child: Text('오류: $_error'),
        ),
      );
    }
    
    if (_confirmedByWork.isEmpty) {
      return Center(
        child: Padding(
          padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.person_off, 
                size: ResponsiveHelper.iconSize(context, 48),  // ⭐ 변경
                color: Theme.of(context).disabledColor,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),  // ⭐ 변경
              Text(
                '확정된 지원자가 없습니다',
                style: ResponsiveHelper.bodyStyle(  // ⭐ 변경
                  context,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
              ),
            ],
          ),
        ),
      );
    }
    
    return ListView(
      padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
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
      margin: EdgeInsets.only(  // ⭐ const 제거
        bottom: ResponsiveHelper.spacing(context, 16),  // ⭐ 변경
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 업무 헤더
          Container(
            padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                // 업무 아이콘
                Container(
                  width: ResponsiveHelper.iconSize(context, 32),  // ⭐ 변경
                  height: ResponsiveHelper.iconSize(context, 32),  // ⭐ 변경
                  decoration: BoxDecoration(
                    color: FormatHelper.parseColor(work.workTypeBackgroundColor ?? '#2196F3'),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(
                    child: WorkTypeIcon.buildFromString(
                      work.workTypeIcon,
                      color: FormatHelper.parseColor(work.workTypeColor),
                      size: ResponsiveHelper.iconSize(context, 16),  // ⭐ 변경
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
                
                // 업무명
                Expanded(
                  child: Text(
                    work.workType,
                    style: ResponsiveHelper.subtitleStyle(context).copyWith(  // ⭐ 변경
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                
                // 인원 배지
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 10),  // ⭐ 변경
                    vertical: ResponsiveHelper.spacing(context, 4),  // ⭐ 변경
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${applicants.length}/${work.requiredCount}명',
                    style: ResponsiveHelper.tinyStyle(context).copyWith(  // ⭐ 변경
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
              padding: ResponsiveHelper.cardPadding(context),  // ⭐ 변경
              decoration: BoxDecoration(
                border: Border(
                  bottom: index < applicants.length - 1
                      ? BorderSide(color: Theme.of(context).dividerColor)
                      : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  // 번호
                  Container(
                    width: ResponsiveHelper.iconSize(context, 28),  // ⭐ 변경
                    height: ResponsiveHelper.iconSize(context, 28),  // ⭐ 변경
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: ResponsiveHelper.tinyStyle(  // ⭐ 변경
                          context,
                          color: Colors.green,
                        ).copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),  // ⭐ 변경
                  
                  // 정보
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? '이름 없음',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(  // ⭐ 변경
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 4)),  // ⭐ 변경
                        Text(
                          '📱 ${user?.phone ?? '전화번호 없음'}',
                          style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                            context,
                            color: Theme.of(context).textTheme.bodyMedium?.color,
                          ),
                        ),
                        Text(
                          '💰 ${FormatHelper.formatWage(app.wage)}',
                          style: ResponsiveHelper.smallStyle(  // ⭐ 변경
                            context,
                            color: Theme.of(context).primaryColor,
                          ).copyWith(fontWeight: FontWeight.w600),
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