import 'package:flutter/material.dart';

// Models
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';

// Services
import '../../../services/firestore_service.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';

// Widgets
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/inputs/filter_dialog.dart';

// Dialogs
import '../dialogs/to_list_dialogs.dart';

// Local Widgets
import '../../../widgets/admin/cards/admin_to_group_card.dart';

/// 인력 관리 - 리스트 뷰 (business_admin_home_screen 스타일 통일)
class WorkforceListView extends StatefulWidget {
  const WorkforceListView({super.key});

  @override
  State<WorkforceListView> createState() => _WorkforceListViewState();
}

class _WorkforceListViewState extends State<WorkforceListView> {
  final FirestoreService _firestoreService = FirestoreService();
  late TOListDialogs _dialogs;
  
  @override
  void initState() {
    super.initState();
    _dialogs = TOListDialogs(
      context: context,
      firestoreService: _firestoreService,
      onChanged: _loadTOsWithStats,
    );
    _loadTOsWithStats();
  }

  
  // 필터 상태
  DateTimeRange? _selectedDateRange;
  String? _selectedBusiness;
  
  // TO 목록 + 통계
  List<TOGroupItem> _allGroupItems = [];
  List<TOGroupItem> _filteredGroupItems = [];
  bool _isLoading = true;
  
  // 탭 상태
  String _selectedTab = 'ACTIVE'; // 'ACTIVE' or 'CLOSED'

  // 사업장 목록
  List<String> _businessNames = [];
  
  // 이중 토글 상태 관리
  final Set<String> _expandedGroups = {};
  final Set<String> _expandedTOs = {};
  
  // ✨ Lazy Loading 상태
  final Set<String> _loadingGroups = {};  // 로딩 중인 그룹
  final Set<String> _loadingTOs = {};     // 로딩 중인 TO
  
  /// ✨ TO 목록 로드 (Lazy Loading - 겉 카드만)
  Future<void> _loadTOsWithStats() async {
    
    // ✅ Phase 3: 새로고침 시 목록 캐시 무효화
    _firestoreService.invalidateListCache();
    
    setState(() {
      _isLoading = true;
      // ✅ 새로고침 시 펼침 상태 초기화
      _expandedGroups.clear();
      _expandedTOs.clear();
    });

    try {
      // ✨ 겉 카드만 로드 (상세 정보 없이)
      final List<TOGroupItem> groupItems = await _firestoreService.getTOGroupItemsLight(
        activeOnly: _selectedTab == 'ACTIVE',
        closedOnly: _selectedTab == 'CLOSED',
      );

      // 사업장 목록 추출
      final businessSet = groupItems
          .map((TOGroupItem g) => g.masterTO.businessName)
          .where((String name) => name.isNotEmpty)
          .toSet();
      final businessList = businessSet.toList()..sort();

      setState(() {
        _allGroupItems = groupItems;
        _businessNames = businessList;
        _isLoading = false;
      });
      
      _applyFilters();
      
      print('✅ [Lazy] 초기 로드 완료: ${groupItems.length}개 카드');
    } catch (e) {
      print('❌ TO 목록 로드 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('TO 목록을 불러오는데 실패했습니다.');
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredGroupItems = _allGroupItems.where((groupItem) {
        // 1. 사업장 필터
        if (_selectedBusiness != null && 
            groupItem.masterTO.businessName != _selectedBusiness) {
          return false;
        }
        
        // 2. 날짜 필터
        if (_selectedDateRange != null) {
          final filterStart = DateTime(
            _selectedDateRange!.start.year,
            _selectedDateRange!.start.month,
            _selectedDateRange!.start.day,
          );
          final filterEnd = DateTime(
            _selectedDateRange!.end.year,
            _selectedDateRange!.end.month,
            _selectedDateRange!.end.day,
            23, 59, 59,
          );
          
          // 그룹 TO인 경우
          if (groupItem.isGrouped) {
            final hasMatchingDate = groupItem.groupTOs.any((toItem) {
              return _isDateInRange(toItem.to, filterStart, filterEnd);
            });
            
            if (!hasMatchingDate) return false;
          } 
          // 단일 TO인 경우
          else {
            if (!_isDateInRange(groupItem.masterTO, filterStart, filterEnd)) {
              return false;
            }
          }
        }
        
        return true;
      }).toList();
    });
  }

  /// ⭐ 날짜 범위 체크 (장기/단기 공고 모두 고려)
  bool _isDateInRange(TOModel to, DateTime filterStart, DateTime filterEnd) {
    // 단기 공고
    if (!to.isLongTerm) {
      final toDate = DateTime(
        to.date.year,
        to.date.month,
        to.date.day,
      );
      
      return toDate.isAfter(filterStart.subtract(const Duration(days: 1))) &&
            toDate.isBefore(filterEnd.add(const Duration(days: 1)));
    }
    
    // 장기 공고
    if (to.endDate == null) {
      // endDate가 없으면 date만 체크
      final toDate = DateTime(
        to.date.year,
        to.date.month,
        to.date.day,
      );
      
      return toDate.isAfter(filterStart.subtract(const Duration(days: 1))) &&
            toDate.isBefore(filterEnd.add(const Duration(days: 1)));
    }
    
    // 장기 공고 기간 체크
    final toStart = DateTime(
      to.date.year,
      to.date.month,
      to.date.day,
    );
    
    final toEnd = DateTime(
      to.endDate!.year,
      to.endDate!.month,
      to.endDate!.day,
    );
    
    // 필터 범위와 TO 기간이 겹치는지 확인
    // 겹치지 않는 경우: filterEnd < toStart OR filterStart > toEnd
    // 겹치는 경우: 위의 반대
    return !(filterEnd.isBefore(toStart) || filterStart.isAfter(toEnd));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildTabBar(),
        // ⭐ 마감됨 탭 안내 메시지
        if (_selectedTab == 'CLOSED')
          _buildClosedTabNotice(),
        Expanded(child: _buildTOList()),
      ],
    );
  }

  /// ✨ 마감됨 탭 안내 메시지 - 테마 기반
  Widget _buildClosedTabNotice() {
    final theme = Theme.of(context);
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
      ),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.primaryColor.withOpacity(0.1),
            theme.primaryColor.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.primaryColor.withOpacity(0.3),
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              Icons.info_outline,
              color: theme.primaryColor,
              size: ResponsiveHelper.iconSize(context, 20),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Text(
              '최근 마감된 5개만 표시됩니다. 이전 마감은 캘린더를 이용하세요.',
              style: ResponsiveHelper.smallStyle(
                context,
                color: theme.primaryColor.withOpacity(0.9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ✨ 탭바 + 필터 (business_admin_home_screen 스타일)
  Widget _buildTabBar() {
    final theme = Theme.of(context);
    
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.primaryColor.withOpacity(0.08),
                    theme.primaryColor.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: theme.primaryColor.withOpacity(0.2),
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(child: _buildTab('ACTIVE', '진행중', Icons.play_circle_outline)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  Expanded(child: _buildTab('CLOSED', '마감됨', Icons.check_circle_outline)),
                ],
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          _buildFilterButton(),
        ],
      ),
    );
  }

  /// ✨ 탭 버튼 - 그라데이션 스타일
  Widget _buildTab(String tab, String label, IconData icon) {
    final theme = Theme.of(context);
    final isSelected = _selectedTab == tab;
    
    return GestureDetector(
      onTap: () {
        if (_selectedTab != tab) {
          setState(() {
            _selectedTab = tab;
            _expandedGroups.clear();
            _expandedTOs.clear();
          });
          _loadTOsWithStats();
        }
      },
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 12),
        ),
        decoration: BoxDecoration(
          gradient: isSelected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    theme.primaryColor,
                    theme.primaryColor.withOpacity(0.85),
                  ],
                )
              : null,
          color: isSelected ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.primaryColor.withOpacity(0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 18),
              color: isSelected ? Colors.white : theme.primaryColor.withOpacity(0.7),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              label,
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : theme.primaryColor.withOpacity(0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ✨ 필터 버튼 - 세련된 배지
  Widget _buildFilterButton() {
    final theme = Theme.of(context);
    final hasFilters = _hasActiveFilters();
    
    return Material(
      color: hasFilters
          ? theme.primaryColor.withOpacity(0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: _showFilterDialog,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.filter_list,
                color: hasFilters ? theme.primaryColor : Colors.grey[600],
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              if (hasFilters)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 4)),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.primaryColor,
                          theme.primaryColor.withOpacity(0.8),
                        ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: theme.primaryColor.withOpacity(0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    constraints: BoxConstraints(
                      minWidth: ResponsiveHelper.spacing(context, 18),
                      minHeight: ResponsiveHelper.spacing(context, 18),
                    ),
                    child: Center(
                      child: Text(
                        '${_getActiveFilterCount()}',
                        style: ResponsiveHelper.tinyStyle(
                          context,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  bool _hasActiveFilters() {
    return _selectedBusiness != null || _selectedDateRange != null;
  }

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedBusiness != null) count++;
    if (_selectedDateRange != null) count++;
    return count;
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => FilterDialog(
        selectedBusiness: _selectedBusiness,
        selectedDateRange: _selectedDateRange,
        businessNames: _businessNames,
        isUserMode: true,
        onBusinessChanged: (value) {
          setState(() => _selectedBusiness = value);
          _applyFilters();
        },
        onDateRangeChanged: (value) {
          setState(() => _selectedDateRange = value);
          _applyFilters();
        },
      ),
    );
  }

  /// ✨ TO 목록
  Widget _buildTOList() {
    if (_isLoading) {
      return const LoadingWidget(message: 'TO 목록을 불러오는 중...');
    }

    if (_filteredGroupItems.isEmpty) {
      return _buildEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadTOsWithStats,
      child: ListView.builder(
        padding: ResponsiveHelper.cardPadding(context),
        itemCount: _filteredGroupItems.length,
        itemBuilder: (context, index) {
          final groupItem = _filteredGroupItems[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: ResponsiveHelper.spacing(context, 16),
            ),
            child: TOGroupCard(
              groupItem: groupItem,
              firestoreService: _firestoreService,
              dialogs: _dialogs,
              allGroupItems: _allGroupItems,
              onChanged: _loadTOsWithStats,
              isExpanded: _expandedGroups.contains(
                groupItem.masterTO.groupId ?? groupItem.masterTO.id
              ),
              expandedTOs: _expandedTOs,
              onToggleExpand: () => _handleGroupExpand(groupItem),
              onToggleTOExpand: (toId) async {
                // toId로 해당 TOItem 찾기
                if (groupItem.groupTOs.isEmpty) return;
                final toItem = groupItem.groupTOs.firstWhere(
                  (item) => item.to.id == toId,
                  orElse: () => groupItem.groupTOs.first,
                );
                await _handleTOExpand(toItem);
              },
              // ✨ 로딩 상태 전달 (카드에서 스피너 표시용)
              isGroupLoading: _loadingGroups.contains(
                groupItem.masterTO.groupId ?? groupItem.masterTO.id
              ),
              loadingTOs: _loadingTOs,
              onAffectedTOsChanged: _refreshAffectedTOs,  // 🔥 추가
            ),
          );
        },
      ),
    );
  }

  /// ✨ 빈 상태 - 세련된 디자인
  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    
    return Center(
      child: Container(
        margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 40)),
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 40)),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              theme.primaryColor.withOpacity(0.08),
              theme.primaryColor.withOpacity(0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.primaryColor.withOpacity(0.2),
            width: 1.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inbox_outlined,
                size: ResponsiveHelper.iconSize(context, 64),
                color: theme.primaryColor.withOpacity(0.4),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
            Text(
              '조건에 맞는 TO가 없습니다',
              style: ResponsiveHelper.titleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: theme.primaryColor.withOpacity(0.8),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              '필터를 변경하거나 새로운 TO를 생성하세요',
              style: ResponsiveHelper.bodyStyle(
                context,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  /// ✨ 그룹 카드 펼침 핸들러 (Lazy Loading)
  Future<void> _handleGroupExpand(TOGroupItem groupItem) async {
    final key = groupItem.masterTO.groupId ?? groupItem.masterTO.id;
    
    // 이미 펼쳐져 있으면 접기만
    if (_expandedGroups.contains(key)) {
      setState(() {
        _expandedGroups.remove(key);
        _expandedTOs.clear();
      });
      return;
    }
    
    // ✅ 다른 그룹 접기
    setState(() {
      _expandedGroups.clear();
      _expandedTOs.clear();
    });
    
    // 그룹 TO이고 아직 상세 로드 안됐으면 로드
    if (groupItem.needsGroupDetailLoad) {
      setState(() => _loadingGroups.add(key));
      
      try {
        final toItems = await _firestoreService.loadGroupTOsLight(
          groupItem.masterTO.groupId!
        );
        groupItem.setGroupTOs(toItems);
      } catch (e) {
        print('❌ 그룹 상세 로드 실패: $e');
        ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
      }
      
      setState(() => _loadingGroups.remove(key));
    }
    
    // ✨ 단일 TO인 경우: WorkDetails 로드 필요
    if (!groupItem.isGrouped && groupItem.groupTOs.isNotEmpty) {
      final toItem = groupItem.groupTOs.first;
      if (toItem.needsWorkDetailLoad) {
        setState(() => _loadingTOs.add(toItem.to.id));
        
        try {
          final result = await _firestoreService.loadTOWorkDetails(toItem.to);
          toItem.setWorkDetails(
            result['workDetails'] as List<WorkDetailModel>,
            result['workStats'] as Map<String, Map<String, int>>,
          );
        } catch (e) {
          print('❌ TO 상세 로드 실패: $e');
          ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
        }
        
        setState(() => _loadingTOs.remove(toItem.to.id));
      }
    }
    
    // 펼치기
    setState(() => _expandedGroups.add(key));
  }
  /// 🔥 영향받은 TO들만 개별 새로고침 (카드 접힘 상태 유지)
  Future<void> _refreshAffectedTOs(Set<String> affectedTOIds) async {
    if (affectedTOIds.isEmpty) return;
    
    print('🔄 영향받은 TO ${affectedTOIds.length}개 새로고침: $affectedTOIds');
    
    // ✅ 갱신된 그룹 마스터 ID 추적 (중복 갱신 방지)
    final Set<String> updatedGroupIds = {};
    
    for (var toId in affectedTOIds) {
      bool found = false;
      
      // 1. 모든 그룹에서 해당 TO 찾기
      for (var groupItem in _allGroupItems) {
        final toItem = groupItem.groupTOs.cast<TOItem?>().firstWhere(
          (item) => item?.to.id == toId,
          orElse: () => null,
        );
        
        if (toItem != null) {
          found = true;
          try {
            // ✅ 캐시 무효화
            _firestoreService.clearCache(toId: toId);
            
            // ✅ TO 문서 직접 조회 (Increment된 정확한 값)
            final toDoc = await _firestoreService.getTO(toId);
            if (toDoc != null) {
              // 겉 카드 통계 즉시 업데이트
              toItem.updateOuterStats(
                confirmed: toDoc.totalConfirmed,
                pending: toDoc.totalPending,
                required: toDoc.totalRequired,
              );
              print('✅ TO $toId 겉 통계 갱신: 확정=${toDoc.totalConfirmed}, 대기=${toDoc.totalPending}');
            }
            
            // 펼쳐진 상태면 WorkDetails도 새로고침
            if (_expandedTOs.contains(toId)) {
              final result = await _firestoreService.loadTOWorkDetails(toItem.to);
              toItem.setWorkDetails(
                result['workDetails'] as List<WorkDetailModel>,
                result['workStats'] as Map<String, Map<String, int>>,
              );
              print('✅ TO $toId WorkDetails도 갱신');
            }
          } catch (e) {
            print('❌ TO $toId 새로고침 실패: $e');
          }
          break;  // 찾았으면 다음 toId로
        }
      }
      
      // 2. ✅ 찾지 못했으면 그룹 마스터 갱신 (그룹이 접혀있는 경우)
      if (!found) {
        try {
          final toDoc = await _firestoreService.getTO(toId);
          if (toDoc != null && toDoc.groupId != null) {
            final groupId = toDoc.groupId!;
            
            // 이미 갱신한 그룹이면 스킵
            if (updatedGroupIds.contains(groupId)) continue;
            
            // 그룹 마스터 찾기
            for (var groupItem in _allGroupItems) {
              if (groupItem.id == groupId) {
                // 마스터 TO 다시 조회
                final masterDoc = await _firestoreService.getTO(groupItem.masterTO.id);
                if (masterDoc != null && groupItem.groupTOs.isNotEmpty) {
                  groupItem.groupTOs.first.updateOuterStats(
                    confirmed: masterDoc.groupTotalConfirmed ?? masterDoc.totalConfirmed,
                    pending: masterDoc.groupTotalPending ?? masterDoc.totalPending,
                    required: masterDoc.groupTotalRequired ?? masterDoc.totalRequired,
                  );
                  updatedGroupIds.add(groupId);
                  print('✅ 그룹 마스터 ${groupItem.masterTO.id} 통계 갱신: 대기=${masterDoc.groupTotalPending}');
                }
                break;
              }
            }
          }
        } catch (e) {
          print('❌ 그룹 마스터 갱신 실패: $e');
        }
      }
    }
    
    // UI 갱신
    if (mounted) setState(() {});
  }

  /// ✨ TO 카드 펼침 핸들러 (Lazy Loading)
  Future<void> _handleTOExpand(TOItem toItem) async {
    final key = toItem.to.id;
    
    // 이미 펼쳐져 있으면 접기만
    if (_expandedTOs.contains(key)) {
      setState(() => _expandedTOs.remove(key));
      return;
    }
    
    // ✅ 다른 TO 접기
    setState(() => _expandedTOs.clear());
    
    // 아직 WorkDetails 로드 안됐으면 로드
    if (toItem.needsWorkDetailLoad) {
      setState(() => _loadingTOs.add(key));
      
      try {
        final result = await _firestoreService.loadTOWorkDetails(toItem.to);
        toItem.setWorkDetails(
          result['workDetails'] as List<WorkDetailModel>,
          result['workStats'] as Map<String, Map<String, int>>,
        );
      } catch (e) {
        print('❌ TO 상세 로드 실패: $e');
        ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
      }
      
      setState(() => _loadingTOs.remove(key));
    }
    
    // 펼치기
    setState(() => _expandedTOs.add(key));
  }
}