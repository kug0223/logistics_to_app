import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/core/to_model.dart';
import '../../models/core/application_model.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/user/cards/user_to_card.dart';
import '../../utils/toast_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/inputs/filter_dialog.dart';


/// 전체 TO 목록 화면 (지원자용)
class AllTOListScreen extends StatefulWidget {
  const AllTOListScreen({super.key});

  @override
  State<AllTOListScreen> createState() => _AllTOListScreenState();
}

class _AllTOListScreenState extends State<AllTOListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ScrollController _scrollController = ScrollController();

  // 필터 상태
  DateTimeRange? _selectedDateRange;
  String? _selectedBusiness;
  final String _jobTypeFilter = 'ALL';

  // 데이터
  List<TOModel> _allTOList = [];
  List<TOModel> _filteredTOList = [];
  List<ApplicationModel> _myApplications = [];
  List<String> _businessNames = [];

  // 페이지네이션
  DocumentSnapshot? _lastDoc;
  bool _hasMoreData = true;
  bool _isLoadingMore = false;

  // UI 상태
  bool _isLoading = true;
  String? _selectedTOId;

  @override
  void initState() {
    super.initState();
    _loadAllTOs();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 300) {
      _loadMoreTOs();
    }
  }

  /// 첫 페이지 로드 (새로고침 포함)
  Future<void> _loadAllTOs() async {
    setState(() {
      _isLoading = true;
      _lastDoc = null;
      _hasMoreData = true;
      _allTOList = [];
    });

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      // 두 요청을 병렬로 시작
      final tosFuture = _firestoreService.getPublishedTOsPaged();
      final appsFuture = uid != null
          ? _firestoreService.getMyApplications(uid)
          : Future.value(<ApplicationModel>[]);

      final tosResult = await tosFuture;
      final myApps = await appsFuture;

      final toList = tosResult['items'] as List<TOModel>;

      if (!mounted) return;
      setState(() {
        _allTOList = toList;
        _lastDoc = tosResult['lastDoc'] as DocumentSnapshot?;
        _hasMoreData = tosResult['hasMore'] as bool;
        _businessNames = toList.map((to) => to.businessName).toSet().toList()..sort();
        _myApplications = myApps;
        _isLoading = false;
      });

      _applyFilters();
    } catch (e) {
      debugPrint('❌ TO 목록 로드 실패: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ToastHelper.showError('TO 목록을 불러오는데 실패했습니다.');
    }
  }

  /// 다음 페이지 로드
  Future<void> _loadMoreTOs() async {
    if (_isLoadingMore || !_hasMoreData) return;

    setState(() => _isLoadingMore = true);

    try {
      final tosResult = await _firestoreService.getPublishedTOsPaged(
        startAfter: _lastDoc,
      );
      final toList = tosResult['items'] as List<TOModel>;

      if (!mounted) return;

      if (toList.isEmpty) {
        setState(() {
          _hasMoreData = false;
          _isLoadingMore = false;
        });
        return;
      }

      setState(() {
        _allTOList = [..._allTOList, ...toList];
        _lastDoc = tosResult['lastDoc'] as DocumentSnapshot?;
        _hasMoreData = tosResult['hasMore'] as bool;
        _businessNames = _allTOList.map((to) => to.businessName).toSet().toList()..sort();
        _isLoadingMore = false;
      });

      _applyFilters();
    } catch (e) {
      debugPrint('❌ TO 추가 로드 실패: $e');
      if (!mounted) return;
      setState(() => _isLoadingMore = false);
    }
  }

  /// 필터 적용
  void _applyFilters() {
    List<TOModel> filtered = _allTOList;

    // 1. 날짜 필터 - 당일 포함, 이전 날짜 제외
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    filtered = filtered.where((to) {
      if (!to.isLongTerm) {
        final toDate = DateTime(to.date.year, to.date.month, to.date.day);
        return toDate.isAtSameMomentAs(today) || toDate.isAfter(today);
      }
      if (to.endDate != null) {
        final endDate = DateTime(to.endDate!.year, to.endDate!.month, to.endDate!.day);
        return endDate.isAtSameMomentAs(today) || endDate.isAfter(today);
      }
      return true;
    }).toList();

    // 2. 날짜 범위 필터
    if (_selectedDateRange != null) {
      final rangeStart = DateTime(
        _selectedDateRange!.start.year,
        _selectedDateRange!.start.month,
        _selectedDateRange!.start.day,
      );
      final rangeEnd = DateTime(
        _selectedDateRange!.end.year,
        _selectedDateRange!.end.month,
        _selectedDateRange!.end.day,
      );

      filtered = filtered.where((to) {
        if (to.isLongTerm && to.endDate != null) {
          final toStart = DateTime(to.date.year, to.date.month, to.date.day);
          final toEnd = DateTime(to.endDate!.year, to.endDate!.month, to.endDate!.day);
          return (toStart.isBefore(rangeEnd) || toStart.isAtSameMomentAs(rangeEnd)) &&
              (toEnd.isAfter(rangeStart) || toEnd.isAtSameMomentAs(rangeStart));
        } else {
          final toDate = DateTime(to.date.year, to.date.month, to.date.day);
          return (toDate.isAtSameMomentAs(rangeStart) || toDate.isAfter(rangeStart)) &&
              (toDate.isAtSameMomentAs(rangeEnd) || toDate.isBefore(rangeEnd));
        }
      }).toList();
    }

    // 3. 사업장 필터
    if (_selectedBusiness != null) {
      filtered = filtered.where((to) => to.businessName == _selectedBusiness).toList();
    }

    // 4. 장기/단기 필터
    if (_jobTypeFilter != 'ALL') {
      filtered = filtered.where((to) => to.jobType == _jobTypeFilter).toList();
    }

    // 5. 날짜순 정렬
    filtered.sort((a, b) => a.date.compareTo(b.date));

    setState(() {
      _filteredTOList = filtered;
    });
  }

  /// TO 선택/해제
  void _toggleTOSelection(String toId) {
    setState(() {
      _selectedTOId = _selectedTOId == toId ? null : toId;
    });
  }

  /// 내 지원 내역만 새로고침
  Future<void> _refreshMyApplications() async {
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid != null) {
        final myApps = await _firestoreService.getMyApplications(uid);
        if (mounted) {
          setState(() {
            _myApplications = myApps;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ 지원 내역 새로고침 실패: $e');
    }
  }

  /// 필터 다이얼로그 표시
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

  int _getActiveFilterCount() {
    int count = 0;
    if (_selectedDateRange != null) count++;
    if (_selectedBusiness != null) count++;
    if (_jobTypeFilter != 'ALL') count++;
    return count;
  }

  bool get _hasActiveFilters {
    return _selectedDateRange != null ||
        _selectedBusiness != null ||
        _jobTypeFilter != 'ALL';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('지원하기'),
        actions: [
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.filter_alt),
                if (_hasActiveFilters)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 2)),
                      decoration: const BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                      ),
                      constraints: BoxConstraints(
                        minWidth: ResponsiveHelper.iconSize(context, 16),
                        minHeight: ResponsiveHelper.iconSize(context, 16),
                      ),
                      child: Text(
                        '${_getActiveFilterCount()}',
                        style: ResponsiveHelper.tinyStyle(context).copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: _showFilterDialog,
            tooltip: '필터',
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingWidget(message: 'TO 목록을 불러오는 중...')
          : _filteredTOList.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadAllTOs,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: ResponsiveHelper.cardPadding(context),
                    itemCount: _filteredTOList.length + (_hasMoreData ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _filteredTOList.length) {
                        return Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(context, 16),
                          ),
                          child: _isLoadingMore
                              ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                              : const SizedBox.shrink(),
                        );
                      }

                      final to = _filteredTOList[index];
                      final isSelected = _selectedTOId == to.id;

                      return UserTOCard(
                        to: to,
                        isSelected: isSelected,
                        onTap: () => _toggleTOSelection(to.id),
                        myApplications: _myApplications,
                        onApplySuccess: _refreshMyApplications,
                      );
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: ResponsiveHelper.iconSize(context, 80),
            color: Theme.of(context).disabledColor,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            '조건에 맞는 TO가 없습니다',
            style: ResponsiveHelper.titleStyle(
              context,
              color: Theme.of(context).textTheme.bodySmall?.color,
            ).copyWith(fontWeight: FontWeight.w500),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '필터를 변경하거나 새로고침해보세요',
            style: ResponsiveHelper.bodyStyle(
              context,
              color: Theme.of(context).disabledColor,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          if (!_hasMoreData && _allTOList.isEmpty)
            TextButton(
              onPressed: _loadAllTOs,
              child: const Text('새로고침'),
            ),
        ],
      ),
    );
  }
}
