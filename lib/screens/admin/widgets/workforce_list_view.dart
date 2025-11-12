import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/core/to_model.dart';
import '../../../services/firestore_service.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../utils/toast_helper.dart';
import '../dialogs/work_applicants_dialog.dart';

/// 인력 관리 - 리스트 뷰 (기존 TO 관리 스타일)
class WorkforceListView extends StatefulWidget {
  final String businessId;

  const WorkforceListView({
    super.key,
    required this.businessId,
  });

  @override
  State<WorkforceListView> createState() => _WorkforceListViewState();
}

class _WorkforceListViewState extends State<WorkforceListView> {
  final FirestoreService _firestoreService = FirestoreService();
  
  List<TOModel> _allTOs = [];
  List<TOModel> _groupMasterTOs = [];
  List<TOModel> _independentTOs = [];
  bool _isLoading = true;
  String _filter = 'ACTIVE'; // 'ACTIVE', 'CLOSED'

  @override
  void initState() {
    super.initState();
    _loadTOs();
  }

  /// TO 목록 로드
  Future<void> _loadTOs() async {
    setState(() => _isLoading = true);

    try {
      List<TOModel> toList;
      
      if (_filter == 'ACTIVE') {
        toList = await _firestoreService.getActiveTOsByBusinessId(widget.businessId);
      } else {
        toList = await _firestoreService.getClosedTOsByBusinessId(widget.businessId);
      }

      // 날짜순 정렬
      toList.sort((a, b) => a.date.compareTo(b.date));

      // 그룹 마스터와 독립 TO 분리
      final groupMasters = <TOModel>[];
      final independents = <TOModel>[];

      for (var to in toList) {
        if (to.isGroupMaster) {
          groupMasters.add(to);
        } else if (to.groupId == null) {
          independents.add(to);
        }
      }

      setState(() {
        _allTOs = toList;
        _groupMasterTOs = groupMasters;
        _independentTOs = independents;
        _isLoading = false;
      });

      print('✅ TO 로드: 그룹 ${groupMasters.length}개, 독립 ${independents.length}개');
    } catch (e) {
      print('❌ TO 로드 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('TO 목록을 불러오는데 실패했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const LoadingWidget(message: 'TO 목록을 불러오는 중...');
    }

    return Column(
      children: [
        // 필터 & 통계
        _buildFilterAndStats(),
        
        const Divider(height: 1),
        
        // TO 목록
        Expanded(
          child: _allTOs.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadTOs,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      // 그룹 TO 섹션
                      if (_groupMasterTOs.isNotEmpty) ...[
                        _buildSectionHeader('📦 그룹 TO', _groupMasterTOs.length),
                        const SizedBox(height: 12),
                        ..._groupMasterTOs.map((to) => _buildTOCard(to)),
                        const SizedBox(height: 24),
                      ],

                      // 독립 TO 섹션
                      if (_independentTOs.isNotEmpty) ...[
                        _buildSectionHeader('📋 개별 TO', _independentTOs.length),
                        const SizedBox(height: 12),
                        ..._independentTOs.map((to) => _buildTOCard(to)),
                      ],
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  /// 필터 & 통계
  Widget _buildFilterAndStats() {
    int totalRequired = 0;
    int totalConfirmed = 0;
    
    for (var to in _allTOs) {
      totalRequired += to.totalRequired;
      totalConfirmed += to.totalConfirmed;
    }
    
    final fillRate = totalRequired > 0 
        ? (totalConfirmed / totalRequired * 100).toInt() 
        : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey[50],
      child: Column(
        children: [
          // 필터 버튼
          Row(
            children: [
              Expanded(
                child: _buildFilterButton(
                  '진행 중',
                  'ACTIVE',
                  _filter == 'ACTIVE',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildFilterButton(
                  '마감됨',
                  'CLOSED',
                  _filter == 'CLOSED',
                ),
              ),
            ],
          ),
          
          if (_filter == 'ACTIVE') ...[
            const SizedBox(height: 16),
            // 통계
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatItem('TO 수', '${_allTOs.length}건', Colors.blue),
                  ),
                  Expanded(
                    child: _buildStatItem('필요', '$totalRequired명', Colors.orange),
                  ),
                  Expanded(
                    child: _buildStatItem('확정', '$totalConfirmed명', Colors.green),
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
            ),
          ],
        ],
      ),
    );
  }

  /// 필터 버튼
  Widget _buildFilterButton(String label, String value, bool isSelected) {
    return OutlinedButton(
      onPressed: () {
        setState(() {
          _filter = value;
        });
        _loadTOs();
      },
      style: OutlinedButton.styleFrom(
        backgroundColor: isSelected ? Colors.blue[700] : Colors.white,
        foregroundColor: isSelected ? Colors.white : Colors.blue[700],
        side: BorderSide(color: Colors.blue[700]!),
      ),
      child: Text(label),
    );
  }

  /// 통계 아이템
  Widget _buildStatItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
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

  /// TO 카드 (기존 디자인 재사용)
  Widget _buildTOCard(TOModel to) {
    final isGroup = to.isGroupMaster;
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      child: InkWell(
        onTap: () => _showApplicantsDialog(to),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 헤더
              Row(
                children: [
                  if (isGroup)
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
                  if (isGroup) const SizedBox(width: 12),
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

              // 날짜 정보
              Row(
                children: [
                  Icon(Icons.calendar_today, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 8),
                  Text(
                    isGroup && to.groupDateRangeDisplay != null
                        ? to.groupDateRangeDisplay!
                        : DateFormat('M월 d일 (E)', 'ko_KR').format(to.date),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[700],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // 시간 정보
              Row(
                children: [
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
              Column(
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
                      value: to.totalRequired > 0 
                          ? to.totalConfirmed / to.totalRequired 
                          : 0,
                      backgroundColor: Colors.grey[200],
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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
            _filter == 'ACTIVE' ? '진행 중인 TO가 없습니다' : '마감된 TO가 없습니다',
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  /// 지원자 관리 다이얼로그 표시
  void _showApplicantsDialog(TOModel to) {
    showDialog(
      context: context,
      builder: (context) => WorkApplicantsDialog(
        to: to,
        onChanged: _loadTOs,
      ),
    );
  }
}