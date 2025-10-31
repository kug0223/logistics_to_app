import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/to_model.dart';
import '../../models/application_model.dart';
import '../../models/work_detail_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/loading_widget.dart';
import '../../utils/toast_helper.dart';
import '../../utils/format_helper.dart';
import '../../widgets/work_type_icon.dart';

// ============================================================
// 📦 데이터 모델
// ============================================================

/// 날짜별 TO 아이템
class _DateTOItem {
  final TOModel to;
  final List<_WorkDetailWithApplicants> workDetails;
  
  _DateTOItem({
    required this.to,
    required this.workDetails,
  });
}

/// 업무별 지원자 정보
class _WorkDetailWithApplicants {
  final WorkDetailModel workDetail;
  final List<Map<String, dynamic>> pendingApplicants;
  final List<Map<String, dynamic>> confirmedApplicants;
  final List<Map<String, dynamic>> rejectedApplicants;
  
  _WorkDetailWithApplicants({
    required this.workDetail,
    required this.pendingApplicants,
    required this.confirmedApplicants,
    required this.rejectedApplicants,
  });
  
  int get totalApplicants => pendingApplicants.length + confirmedApplicants.length + rejectedApplicants.length;
}

// ============================================================
// 🖥️ 화면
// ============================================================

/// 관리자 TO 상세 화면 (지원자 관리) - Phase 3 리팩토링
class AdminTODetailScreen extends StatefulWidget {
  final TOModel to;
  final String? initialWorkType;

  const AdminTODetailScreen({
    Key? key,
    required this.to,
    this.initialWorkType,
  }) : super(key: key);

  @override
  State<AdminTODetailScreen> createState() => _AdminTODetailScreenState();
}

class _AdminTODetailScreenState extends State<AdminTODetailScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  
  // ✅ NEW: 날짜별로 그룹화된 데이터
  Map<DateTime, List<_DateTOItem>> _dateGroupedData = {};
  bool _isLoading = true;
  
  // ✅ NEW: 토글 상태 관리
  final Set<String> _expandedDates = {}; // 펼쳐진 날짜들
  final Set<String> _expandedTOs = {}; // 펼쳐진 TO들
  bool _hasChanges = false; // 🔥 추가!

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  /// ✅ NEW: 날짜별 트리 구조 데이터 로드
  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      List<TOModel> targetTOs = [];
      
      // 그룹 TO인 경우: 같은 그룹의 모든 TO
      if (widget.to.groupId != null) {
        targetTOs = await _firestoreService.getTOsByGroup(widget.to.groupId!);
      } else {
        // 단일 TO인 경우: 이 TO만
        targetTOs = [widget.to];
      }
      
      // 날짜별로 그룹화
      Map<DateTime, List<_DateTOItem>> dateGrouped = {};
      
      for (var to in targetTOs) {
        final date = DateTime(to.date.year, to.date.month, to.date.day);
        
        // WorkDetails 조회
        final workDetails = await _firestoreService.getWorkDetails(to.id);
        
        // 각 WorkDetail별로 지원자 조회 및 분류
        List<_WorkDetailWithApplicants> workDetailItems = [];
        
        for (var work in workDetails) {
          // 이 업무에 지원한 사람들 조회
          final applications = await _firestoreService.getApplicationsByWorkDetail(
            to.id,
            work.workType,
          );
          
          // 지원자 정보와 함께 매핑
          List<Map<String, dynamic>> pending = [];
          List<Map<String, dynamic>> confirmed = [];
          List<Map<String, dynamic>> rejected = [];
          
          for (var app in applications) {
            final userDoc = await _firestoreService.getUser(app.uid);
            if (userDoc != null) {
              final applicantData = {
                'applicationId': app.id,
                'application': app,
                'userName': userDoc.name,
                'userEmail': userDoc.email,
                'userPhone': userDoc.phone ?? '',
              };
              
              if (app.status == 'PENDING') {
                pending.add(applicantData);
              } else if (app.status == 'CONFIRMED') {
                confirmed.add(applicantData);
              } else if (app.status == 'REJECTED') {
                rejected.add(applicantData);
              }
            }
          }
          
          workDetailItems.add(_WorkDetailWithApplicants(
            workDetail: work,
            pendingApplicants: pending,
            confirmedApplicants: confirmed,
            rejectedApplicants: rejected,
          ));
        }
        
        // 날짜별로 추가
        if (!dateGrouped.containsKey(date)) {
          dateGrouped[date] = [];
        }
        
        dateGrouped[date]!.add(_DateTOItem(
          to: to,
          workDetails: workDetailItems,
        ));
      }
      
      setState(() {
        _dateGroupedData = dateGrouped;
        _isLoading = false;
      });
      
      print('✅ 날짜별 데이터 로드 완료: ${dateGrouped.keys.length}일');
    } catch (e) {
      print('❌ 데이터 로드 실패: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 지원자 승인
  Future<void> _confirmApplicant(String applicationId) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final adminUID = userProvider.currentUser?.uid;

    if (adminUID == null) {
      ToastHelper.showError('관리자 정보를 찾을 수 없습니다.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지원자 승인'),
        content: const Text('이 지원자를 승인하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('승인', style: TextStyle(color: Colors.green)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('승인 중...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      // ✅ WorkDetail과 TO 통계 업데이트 포함된 함수 사용
      final success = await _firestoreService.confirmApplicantWithWorkDetail(
        applicationId: applicationId,
        adminUID: adminUID,
      );
      
      if (mounted) {
        Navigator.pop(context);
      }

      if (success) {
        setState(() {
          _hasChanges = true; // 🔥 변경사항 기록
        });
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context, true);
      }
      print('❌ 승인 실패: $e');
    }
  }

  /// 지원자 거절
  Future<void> _rejectApplicant(String applicationId) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final adminUID = userProvider.currentUser?.uid;

    if (adminUID == null) {
      ToastHelper.showError('관리자 정보를 찾을 수 없습니다.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('지원자 거절'),
        content: const Text('이 지원자를 거절하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('거절', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('거절 중...'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final success = await _firestoreService.rejectApplicant(applicationId, adminUID);
      
      if (mounted) {
        Navigator.pop(context);
      }

      if (success) {
        setState(() {
          _hasChanges = true; // 🔥 변경사항 기록
        });
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context, true);
      }
      print('❌ 거절 실패: $e');
    }
  }
  /// 날짜의 모든 TO가 인원 모집 완료되었는지 확인
  bool _isDateFull(List<_DateTOItem> toItems) {
    for (var toItem in toItems) {
      for (var work in toItem.workDetails) {
        if (work.confirmedApplicants.length < work.workDetail.requiredCount) {
          return false; // 하나라도 미달이면 false
        }
      }
    }
    return true; // 모두 완료
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: LoadingWidget(message: 'TO 정보를 불러오는 중...'),
      );
    }
    
    return WillPopScope(  // 🔥 이 부분 추가!
      onWillPop: () async {
        // 뒤로가기 시 _hasChanges 값을 반환
        Navigator.pop(context, _hasChanges);
        return false; // false를 반환해서 기본 뒤로가기 동작을 막음
      },
      child: Scaffold(  // 🔥 기존 Scaffold를 WillPopScope의 child로 이동
        appBar: AppBar(
          title: Text(widget.to.isGrouped ? widget.to.groupName ?? '그룹 TO' : 'TO 상세'),
          backgroundColor: Colors.blue[700],
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              Navigator.pop(context, _hasChanges);
            },
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _loadData,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // 헤더
              _buildHeader(),
              const SizedBox(height: 24),

              // ✅ NEW: 날짜별 트리 구조
              _buildDateTreeView(),
              
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  /// 헤더 (그룹명, 사업장명, 기간)
  Widget _buildHeader() {
    final dateFormat = DateFormat('yyyy-MM-dd (E)', 'ko_KR');
    
    // 🔥 실제 날짜 범위 계산
    DateTime? minDate;
    DateTime? maxDate;
    String? minTime;
    String? maxTime;
    
    for (var dateEntry in _dateGroupedData.entries) {
      final date = dateEntry.key;
      if (minDate == null || date.isBefore(minDate)) minDate = date;
      if (maxDate == null || date.isAfter(maxDate)) maxDate = date;
      
      for (var toItem in dateEntry.value) {
        for (var work in toItem.workDetails) {
          if (minTime == null || work.workDetail.startTime.compareTo(minTime) < 0) {
            minTime = work.workDetail.startTime;
          }
          if (maxTime == null || work.workDetail.endTime.compareTo(maxTime) > 0) {
            maxTime = work.workDetail.endTime;
          }
        }
      }
    }
    
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ 사업장명 (변경 없음)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF1976D2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.business,
                    size: 14,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    widget.to.businessName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            
            // ✅ 그룹명 (변경 없음)
            if (widget.to.groupName != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.green[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green[300]!, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.folder_open, size: 16, color: Colors.green[700]),
                    const SizedBox(width: 6),
                    Text(
                      widget.to.groupName!,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[300]!, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.work_outline, size: 16, color: Colors.blue[700]),
                    const SizedBox(width: 6),
                    Text(
                      '단일 공고',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue[800],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            
            // 🔥 날짜 정보 (실제 범위로 표시)
            Row(
              children: [
                Icon(Icons.calendar_today, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  widget.to.groupName != null && minDate != null && maxDate != null
                      ? '${dateFormat.format(minDate)} ~ ${dateFormat.format(maxDate)}'
                      : dateFormat.format(widget.to.date),
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
            ),
            const SizedBox(height: 8),
            
            // 🔥 시간 정보 (실제 범위로 표시)
            Row(
              children: [
                Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                const SizedBox(width: 6),
                Text(
                  minTime != null && maxTime != null
                      ? '$minTime ~ $maxTime'
                      : '${widget.to.startTime} ~ ${widget.to.endTime}',
                  style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// ✅ NEW: 날짜별 트리 뷰
  Widget _buildDateTreeView() {
    if (_dateGroupedData.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(50),
          child: Column(
            children: [
              Icon(Icons.inbox_outlined, size: 60, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                '지원자 정보가 없습니다',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      );
    }

    // 날짜순 정렬
    final sortedDates = _dateGroupedData.keys.toList()..sort();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '📋 날짜별 업무별 지원 현황',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.grey[800],
          ),
        ),
        const SizedBox(height: 16),
        
        ...sortedDates.map((date) {
          return _buildDateCard(date, _dateGroupedData[date]!);
        }).toList(),
      ],
    );
  }

  /// 날짜 카드
  Widget _buildDateCard(DateTime date, List<_DateTOItem> toItems) {
    final dateKey = date.toIso8601String();
    final isExpanded = _expandedDates.contains(dateKey);
    final dateFormat = DateFormat('MM/dd (E)', 'ko_KR');
    
    // 이 날짜의 전체 통계
    int totalPending = 0;
    int totalConfirmed = 0;
    
    for (var toItem in toItems) {
      for (var work in toItem.workDetails) {
        totalPending += work.pendingApplicants.length;
        totalConfirmed += work.confirmedApplicants.length;
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      child: Column(
        children: [
          // 날짜 헤더
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedDates.remove(dateKey);
                } else {
                  _expandedDates.add(dateKey);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 20,
                    color: Colors.blue[700],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          dateFormat.format(date),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (toItems.length > 1) ...[
                          const SizedBox(height: 4),
                          Text(
                            '⚠️ 이 날짜에 ${toItems.length}개 TO',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[700],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // ✅ 통계 (조건부 색상)
                  Row(
                    children: [
                      _buildMiniStatChip('대기', totalPending, Colors.orange),
                      const SizedBox(width: 8),
                      _buildMiniStatChip(
                        '확정', 
                        totalConfirmed, 
                        _isDateFull(toItems) ? Colors.green : Colors.blue  // 날짜별 완료 여부 체크
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  
                  // 확정 명단 버튼
                  OutlinedButton.icon(
                    onPressed: () => _showConfirmedListDialog(date, toItems),
                    icon: const Icon(Icons.list_alt, size: 16),
                    label: const Text('확정명단', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue[700],
                      side: BorderSide(color: Colors.blue[300]!),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                  ),
                  const SizedBox(width: 8),
                  
                  // 토글 아이콘
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
          
          // TO 목록
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: toItems.map((toItem) {
                  return _buildTOItemCard(toItem);
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// TO 아이템 카드
  Widget _buildTOItemCard(_DateTOItem toItem) {
    final toKey = toItem.to.id;
    final isExpanded = _expandedTOs.contains(toKey);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        children: [
          // TO 헤더
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedTOs.remove(toKey);
                } else {
                  _expandedTOs.add(toKey);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.work_outline, size: 18, color: Colors.grey[700]),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      toItem.to.title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                    size: 20,
                    color: Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
          
          // 업무 목록
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: toItem.workDetails.map((work) {
                  return _buildWorkDetailCard(work);
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 업무 상세 카드
  Widget _buildWorkDetailCard(_WorkDetailWithApplicants work) {
    final totalApplicants = work.totalApplicants;
    final pending = work.pendingApplicants.length;
    final confirmed = work.confirmedApplicants.length;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 업무 정보
          Row(
            children: [
              // 업무 유형
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: FormatHelper.parseColor(work.workDetail.workTypeColor).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 🔥 WorkTypeIcon.buildFromString 사용
                    WorkTypeIcon.buildFromString(
                      work.workDetail.workTypeIcon,
                      color: FormatHelper.parseColor(work.workDetail.workTypeColor),
                      size: 14,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      work.workDetail.workType,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: FormatHelper.parseColor(work.workDetail.workTypeColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              
              // 시간
              Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 4),
              Text(
                '${work.workDetail.startTime}~${work.workDetail.endTime}',
                style: TextStyle(fontSize: 11, color: Colors.grey[700]),
              ),
              const SizedBox(width: 12),
              
              // 급여
              Text(
                work.workDetail.formattedWage,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // 지원자 통계 및 버튼
          Row(
            children: [
              // 통계
              _buildStatChip('대기', pending, Colors.orange),
              const SizedBox(width: 8),
              // ✅ 확정 인원 (조건부 색상)
              _buildStatChip(
                '확정', 
                confirmed, 
                confirmed >= work.workDetail.requiredCount ? Colors.green : Colors.blue
              ),
              const SizedBox(width: 8),
              Text(
                '${work.confirmedApplicants.length}/${work.workDetail.requiredCount}명',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
              
              const Spacer(),
              
              // 자세히 버튼
              if (totalApplicants > 0)
                TextButton.icon(
                  onPressed: () => _showApplicantsModal(work),
                  icon: const Icon(Icons.people, size: 16),
                  label: const Text('자세히', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.blue[700],
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// 통계 칩
  Widget _buildStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

  /// 미니 통계 칩
  Widget _buildMiniStatChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: color,
        ),
      ),
    );
  }

   /// ✅ NEW: 확정 명단 다이얼로그
  Future<void> _showConfirmedListDialog(DateTime date, List<_DateTOItem> toItems) async {
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

  /// ✅ NEW: 지원자 목록 모달
  Future<void> _showApplicantsModal(_WorkDetailWithApplicants work) async {
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
                    return _buildApplicantCard(applicant);
                  }).toList(),
                  const SizedBox(height: 16),
                ],
                
                // 확정
                if (work.confirmedApplicants.isNotEmpty) ...[
                  _buildSectionHeader('✅ 확정', Colors.green, work.confirmedApplicants.length),
                  const SizedBox(height: 8),
                  ...work.confirmedApplicants.map((applicant) {
                    return _buildApplicantCard(applicant);
                  }).toList(),
                  const SizedBox(height: 16),
                ],
                
                // 거절
                if (work.rejectedApplicants.isNotEmpty) ...[
                  _buildSectionHeader('❌ 거절', Colors.red, work.rejectedApplicants.length),
                  const SizedBox(height: 8),
                  ...work.rejectedApplicants.map((applicant) {
                    return _buildApplicantCard(applicant);
                  }).toList(),
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
  Widget _buildApplicantCard(Map<String, dynamic> applicant) {
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
                        _rejectApplicant(applicant['applicationId']);
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
                        _confirmApplicant(applicant['applicationId']);
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