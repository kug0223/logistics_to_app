import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/core/to_model.dart';
import '../../../services/firestore_service.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../utils/toast_helper.dart';

/// 그룹 뷰 - 진행 중인 TO만 표시
class WorkforceGroupView extends StatefulWidget {
  final String businessId;

  const WorkforceGroupView({
    super.key,
    required this.businessId,
  });

  @override
  State<WorkforceGroupView> createState() => _WorkforceGroupViewState();
}

class _WorkforceGroupViewState extends State<WorkforceGroupView> {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<TOModel> _groupMasterTOs = [];
  List<TOModel> _independentTOs = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadActiveTOs();
  }

  /// 진행 중인 TO 로드
  Future<void> _loadActiveTOs() async {
    setState(() => _isLoading = true);

    try {
      // 모든 TO 조회
      final allTOs = await _firestoreService.getActiveTOsByBusinessId(
        widget.businessId,
      );

      // 오늘 이후 & 마감 안 된 것만 필터링
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      
      final activeTOs = allTOs.where((to) {
        // 날짜 체크
        final toDate = DateTime(to.date.year, to.date.month, to.date.day);
        if (toDate.isBefore(today)) return false;
        
        // 마감 체크 (TO는 긴급 재오픈이 없음, WorkDetail만 있음)
        if (to.isManualClosed) return false;
        
        return true;
      }).toList();

      // 그룹 마스터와 독립 TO 분리
      final groupMasters = <TOModel>[];
      final independents = <TOModel>[];

      for (var to in activeTOs) {
        if (to.isGroupMaster) {
          groupMasters.add(to);
        } else if (to.groupId == null) {
          independents.add(to);
        }
        // 그룹 멤버는 마스터에 포함되므로 제외
      }

      // 날짜순 정렬
      groupMasters.sort((a, b) => a.date.compareTo(b.date));
      independents.sort((a, b) => a.date.compareTo(b.date));

      setState(() {
        _groupMasterTOs = groupMasters;
        _independentTOs = independents;
        _isLoading = false;
      });

      print('✅ 그룹 마스터: ${groupMasters.length}개, 독립 TO: ${independents.length}개');
    } catch (e) {
      print('❌ TO 로드 실패: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const LoadingWidget(message: 'TO 목록을 불러오는 중...');
    }

    if (_groupMasterTOs.isEmpty && _independentTOs.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadActiveTOs,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 통계 카드
          _buildStatisticsCard(),
          const SizedBox(height: 16),

          // 그룹 TO 섹션
          if (_groupMasterTOs.isNotEmpty) ...[
            _buildSectionHeader('📦 그룹 TO', _groupMasterTOs.length),
            const SizedBox(height: 12),
            ..._groupMasterTOs.map((to) => _buildGroupCard(to)),
            const SizedBox(height: 24),
          ],

          // 독립 TO 섹션
          if (_independentTOs.isNotEmpty) ...[
            _buildSectionHeader('📋 개별 TO', _independentTOs.length),
            const SizedBox(height: 12),
            ..._independentTOs.map((to) => _buildIndependentCard(to)),
          ],
        ],
      ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '진행 중인 TO가 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'TO 생성 메뉴에서 새 TO를 등록해보세요',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }

  /// 통계 카드
  Widget _buildStatisticsCard() {
    final totalTOs = _groupMasterTOs.length + _independentTOs.length;
    
    int totalRequired = 0;
    int totalConfirmed = 0;
    
    for (var to in [..._groupMasterTOs, ..._independentTOs]) {
      totalRequired += to.totalRequired;
      totalConfirmed += to.totalConfirmed;
    }
    
    final fillRate = totalRequired > 0 
        ? (totalConfirmed / totalRequired * 100).toInt() 
        : 0;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.blue[700], size: 20),
                const SizedBox(width: 8),
                const Text(
                  '진행 중 현황',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem('TO 수', '$totalTOs건', Colors.blue),
                ),
                Expanded(
                  child: _buildStatItem(
                    '필요 인원',
                    '$totalRequired명',
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    '확정 인원',
                    '$totalConfirmed명',
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    '충족률',
                    '$fillRate%',
                    fillRate >= 80 ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 통계 아이템
  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  /// 섹션 헤더
  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: Colors.blue[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.blue[900],
            ),
          ),
        ),
      ],
    );
  }

  /// 그룹 카드
  Widget _buildGroupCard(TOModel to) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => _showGroupDetail(to),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 그룹 헤더
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.blue[50],
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.blue[300]!),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder, size: 14, color: Colors.blue[700]),
                        const SizedBox(width: 4),
                        Text(
                          '그룹',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue[900],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      to.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 날짜 범위 (그룹 전체)
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    to.groupDateRangeDisplay ?? '',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 시간
              Row(
                children: [
                  Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  FutureBuilder<String>(
                    future: _getTimeRange(to),
                    builder: (context, snapshot) {
                      return Text(
                        snapshot.data ?? '시간 확인 중...',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                        ),
                      );
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 인원 현황
              _buildPersonnelStatus(to),
            ],
          ),
        ),
      ),
    );
  }

  /// 독립 카드
  Widget _buildIndependentCard(TOModel to) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => _showIndependentDetail(to),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Text(
                to.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              // 날짜
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    DateFormat('M월 d일 (E)', 'ko_KR').format(to.date),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    to.displayTimeRange.isNotEmpty 
                        ? to.displayTimeRange 
                        : '${to.startTime} ~ ${to.endTime}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // 인원 현황
              _buildPersonnelStatus(to),

              // 그룹 연결 버튼
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    // TODO: 그룹 연결 기능
                  },
                  icon: const Icon(Icons.link, size: 16),
                  label: const Text('그룹 연결'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.blue,
                    side: const BorderSide(color: Colors.blue),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 인원 현황 표시
  Widget _buildPersonnelStatus(TOModel to) {
    final fillRate = to.totalRequired > 0
        ? (to.totalConfirmed / to.totalRequired * 100).toInt()
        : 0;

    Color statusColor;
    if (fillRate >= 100) {
      statusColor = Colors.green;
    } else if (fillRate >= 50) {
      statusColor = Colors.orange;
    } else {
      statusColor = Colors.red;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '인원: ${to.totalConfirmed}/${to.totalRequired}명',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '($fillRate%)',
              style: TextStyle(
                fontSize: 13,
                color: statusColor,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: to.totalRequired > 0 ? to.totalConfirmed / to.totalRequired : 0,
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  /// 그룹 상세 보기
  void _showGroupDetail(TOModel to) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.blue[300]!),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder, size: 14, color: Colors.blue[700]),
                  const SizedBox(width: 4),
                  Text(
                    '그룹',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[900],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                to.title,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(Icons.calendar_today, '날짜 범위', 
                  to.groupDateRangeDisplay ?? ''),
              const SizedBox(height: 12),
              FutureBuilder<String>(
                future: _getTimeRange(to),
                builder: (context, snapshot) {
                  return _buildDetailRow(Icons.access_time, '시간',
                      snapshot.data ?? '확인 중...');
                },
              ),
              const SizedBox(height: 12),
              _buildDetailRow(Icons.people, '인원',
                  '${to.totalConfirmed}/${to.totalRequired}명'),
              if (to.description != null && to.description!.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  '설명',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  to.description!,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              // TODO: 그룹 내 지원자 관리 화면으로 이동
              ToastHelper.showInfo('그룹 지원자 관리 화면 준비 중');
            },
            icon: const Icon(Icons.people),
            label: const Text('지원자 관리'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// 독립 TO 상세 보기
  void _showIndependentDetail(TOModel to) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(to.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(Icons.calendar_today, '날짜',
                  DateFormat('M월 d일 (E)', 'ko_KR').format(to.date)),
              const SizedBox(height: 12),
              FutureBuilder<String>(
                future: _getTimeRange(to),
                builder: (context, snapshot) {
                  return _buildDetailRow(Icons.access_time, '시간',
                      snapshot.data ?? '확인 중...');
                },
              ),
              const SizedBox(height: 12),
              _buildDetailRow(Icons.people, '인원',
                  '${to.totalConfirmed}/${to.totalRequired}명'),
              if (to.description != null && to.description!.isNotEmpty) ...[
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  '설명',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  to.description!,
                  style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              // TODO: 지원자 관리 화면으로 이동
              ToastHelper.showInfo('지원자 관리 화면 준비 중');
            },
            icon: const Icon(Icons.people),
            label: const Text('지원자 관리'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue[700],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// 상세 정보 행
  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: Colors.grey[700],
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(fontSize: 13, color: Colors.grey[600]),
          ),
        ),
      ],
    );
  }


  /// TO의 시간 범위 가져오기
  Future<String> _getTimeRange(TOModel to) async {
    // 이미 시간이 있으면 반환
    if (to.startTime.isNotEmpty && to.endTime.isNotEmpty) {
      return '${to.startTime} ~ ${to.endTime}';
    }
    
    // WorkDetails에서 시간 가져오기
    try {
      final workDetails = await _firestoreService.getWorkDetails(to.id);
      if (workDetails.isEmpty) return '시간 미정';
      
      final minStart = workDetails.map((w) => w.startTime).reduce((a, b) => 
        a.compareTo(b) < 0 ? a : b
      );
      final maxEnd = workDetails.map((w) => w.endTime).reduce((a, b) => 
        a.compareTo(b) > 0 ? a : b
      );
      
      return '$minStart ~ $maxEnd';
    } catch (e) {
      return '시간 미정';
    }
  }
}