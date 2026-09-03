import 'package:flutter/material.dart';
import 'dart:async' show unawaited;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../models/core/monthly_review_model.dart';
import '../../models/core/review_request_model.dart';
import '../../models/core/to_model.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../screens/user/interim_settlement_request_screen.dart';
import '../../widgets/dialogs/long_term_work_management_dialog.dart';
import '../../screens/common/job_posting_screen.dart';
import '../../services/contract_service.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_review_service.dart';
import '../../widgets/dialogs/business_review_dialog.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/skeleton_widget.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// Presentation-layer enums — DB status / ApplicationModel 변경 없음
// ═══════════════════════════════════════════════════════════════════════════════

/// UI 필터 그룹 (DB status와 독립적인 화면 전용 분류)
enum _UiGroup { all, inProgress, confirmed, ended, invited }

extension _UiGroupLabel on _UiGroup {
  String get label {
    switch (this) {
      case _UiGroup.all:        return '전체';
      case _UiGroup.inProgress: return '진행중';
      case _UiGroup.confirmed:  return '확정';
      case _UiGroup.ended:      return '종료';
      case _UiGroup.invited:    return '초대';
    }
  }
}

/// DB status → UI 그룹 매핑 (순수 함수 — 비즈니스 로직 변경 없음)
_UiGroup _statusToGroup(String status) {
  switch (status) {
    case AppStatus.pending:
    case AppStatus.contractPending:
      return _UiGroup.inProgress;
    case AppStatus.confirmed:
      return _UiGroup.confirmed;
    case AppStatus.invited:
    case AppStatus.expired:
      return _UiGroup.invited;
    default: // rejected, canceled, autoCanceled
      return _UiGroup.ended;
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 내 지원 화면
// ═══════════════════════════════════════════════════════════════════════════════

/// 내 지원 내역 화면 (재디자인 버전)
class MyApplicationsScreen extends StatefulWidget {
  /// 초기 탭 인덱스 — 홈화면 초대 배너 탭 이동 시 구 인덱스 6('초대') 전달 가능.
  /// .clamp(0, 4)로 새 그룹 인덱스에 자동 대응.
  final int initialTabIndex;

  /// 뒤로가기 버튼 콜백.
  /// - null(기본): Navigator.pop() — 독립 화면으로 push됐을 때
  /// - 함수 전달: TabBarView 임베드 시 상위 탭으로 전환하는 용도
  final VoidCallback? onBack;

  const MyApplicationsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.onBack,
  });

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen> {
  // ─── 포맷터 캐싱 ──────────────────────────────────────────────────────────
  static final _mdFmt   = DateFormat('M월 d일');
  static final _mdhmFmt = DateFormat('MM.dd HH:mm');
  static const _korWeekday = ['월', '화', '수', '목', '금', '토', '일'];

  // ─── 서비스 ───────────────────────────────────────────────────────────────
  final FirestoreService    _firestoreService = FirestoreService();
  final ContractService     _contractService  = ContractService();
  final MonthlyReviewService _reviewService   = MonthlyReviewService();
  final ScrollController    _scrollController = ScrollController();

  // ─── 데이터 상태 (변경 없음) ───────────────────────────────────────────────
  List<_ApplicationWithTO>              _applications  = [];
  Map<String, EmploymentContractModel>  _contractMap   = {};
  Map<String, MonthlyReviewModel?>      _reviewMap     = {};
  final Map<String, TOModel>            _toCache       = {};
  final Map<String, MonthlyReviewModel?> _reviewKeyCache = {};
  bool _contractsLoaded = false;

  bool   _isLoading      = true;
  bool   _fetchInProgress = false;
  bool   _isLoadingMore  = false;
  bool   _hasMore        = true;
  String? _lastDocId;

  // ─── UI 상태 ──────────────────────────────────────────────────────────────
  /// 현재 선택된 그룹 인덱스 (0: 전체 … 4: 초대)
  int _selectedGroupIdx = 0;

  // M-2: 필터 결과 캐시
  List<_ApplicationWithTO>? _cachedFiltered;
  int _cachedGroupIdx = -1;

  int _autoLoadCount = 0;
  static const int _maxAutoLoad = 5;
  static const int _pageSize    = 20;

  // ─── 진행 중 action 상태 ──────────────────────────────────────────────────
  final Set<String> _cancellingIds        = {};
  final Set<String> _acceptingIds         = {};
  final Set<String> _decliningIds         = {};
  final Set<String> _reviewDialogOpenIds  = {};
  bool _isContractSignOpening             = false;

  // ─── 생명주기 ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // 구 initialTabIndex(최대 6) → 새 그룹 인덱스(최대 4)로 clamp
    _selectedGroupIdx = widget.initialTabIndex.clamp(0, _UiGroup.values.length - 1);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadApplications();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ─── 스크롤 무한 로딩 ─────────────────────────────────────────────────────

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 데이터 로딩 — 기존 로직 그대로 유지
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _loadApplications() async {
    if (!mounted) return;
    if (_fetchInProgress) return;
    _fetchInProgress = true;
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) {
      ToastHelper.showError('로그인이 필요합니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _applications  = [];
      _lastDocId     = null;
      _hasMore       = true;
      _contractsLoaded = false;
      _toCache.clear();
      _reviewKeyCache.clear();
      _cachedFiltered = null;
    });

    try {
      unawaited(_firestoreService.autoExpirePendingApplications(uid).catchError((e) {
        debugPrint('⚠️ autoExpirePendingApplications 실패 (무시): $e');
      }));

      final page = await _firestoreService.getMyApplicationsPaged(
        uid: uid, pageSize: _pageSize,
      );
      final items      = page['items'] as List<ApplicationModel>;
      final appWithTOs = await _attachTOInfo(items);

      final initResults = await Future.wait([
        _loadContracts(uid, appWithTOs).catchError((_) => <String, EmploymentContractModel>{}),
        _loadWrittenReviews(uid, appWithTOs).catchError((_) => <String, MonthlyReviewModel?>{}),
      ]);
      final contractMap = initResults[0] as Map<String, EmploymentContractModel>;
      final reviewMap   = initResults[1] as Map<String, MonthlyReviewModel?>;

      if (mounted) {
        setState(() {
          _applications  = appWithTOs;
          _contractMap   = contractMap;
          _reviewMap     = reviewMap;
          _lastDocId     = page['lastDocId'] as String?;
          _hasMore       = page['hasMore'] as bool;
          _isLoading     = false;
          _cachedFiltered = null;
        });
      }
    } catch (e) {
      debugPrint('❌ 지원 내역 로드 실패: $e');
      if (mounted) {
        ToastHelper.showError(_firestoreErrMsg(e, '지원 내역을 불러오는데 실패했습니다.'));
        setState(() => _isLoading = false);
      }
    } finally {
      _fetchInProgress = false;
    }
  }

  String _firestoreErrMsg(dynamic e, String fallback) {
    if (e is FirebaseException) {
      return switch (e.code) {
        'unavailable' || 'network-request-failed' => '네트워크 연결을 확인해 주세요.',
        'permission-denied'                        => '권한이 없습니다. 관리자에게 문의하세요.',
        'not-found'                                => '데이터를 찾을 수 없습니다.',
        'deadline-exceeded' || 'cancelled'         => '요청 시간이 초과되었습니다.',
        _                                          => fallback,
      };
    }
    return fallback;
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _lastDocId == null) return;
    if (_fetchInProgress) return;
    if (!mounted) return;
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoadingMore = true);
    try {
      final page = await _firestoreService.getMyApplicationsPaged(
        uid: uid, pageSize: _pageSize, startAfterDocId: _lastDocId,
      );
      final items      = page['items'] as List<ApplicationModel>;
      final appWithTOs = await _attachTOInfo(items);
      final moreResults = await Future.wait([
        _contractsLoaded
            ? Future.value(<String, EmploymentContractModel>{})
            : _loadContracts(uid, appWithTOs),
        _loadWrittenReviews(uid, appWithTOs),
      ]);
      final newContracts = moreResults[0] as Map<String, EmploymentContractModel>;
      final newReviews   = moreResults[1] as Map<String, MonthlyReviewModel?>;

      if (mounted) {
        setState(() {
          _applications  = [..._applications, ...appWithTOs];
          _contractMap   = {..._contractMap,   ...newContracts};
          _reviewMap     = {..._reviewMap,     ...newReviews};
          _lastDocId     = page['lastDocId'] as String?;
          _hasMore       = page['hasMore'] as bool;
          _isLoadingMore = false;
          _cachedFiltered = null;
        });
        final filtered = _filteredApplications;
        if (filtered.isEmpty && _hasMore && !_isLoadingMore &&
            _autoLoadCount < _maxAutoLoad) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _filteredApplications.isEmpty && _hasMore && !_isLoadingMore) {
              _autoLoadCount++;
              _loadMore();
            }
          });
        } else if (filtered.isEmpty && _hasMore && _autoLoadCount >= _maxAutoLoad) {
          setState(() => _hasMore = false);
        }
      }
    } catch (e) {
      debugPrint('❌ 추가 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
        ToastHelper.showError(_firestoreErrMsg(e, '추가 데이터를 불러오지 못했습니다.'));
      }
    }
  }

  Future<List<_ApplicationWithTO>> _attachTOInfo(List<ApplicationModel> apps) async {
    final toIds = apps.map((a) => a.toId).whereType<String>().toSet().toList();
    if (toIds.isEmpty) {
      return apps.map((a) => _ApplicationWithTO(application: a, to: null)).toList();
    }
    final uncachedIds = toIds.where((id) => !_toCache.containsKey(id)).toList();
    if (uncachedIds.isNotEmpty) {
      final fetched = await Future.wait(uncachedIds.map((id) => _firestoreService.getTO(id)));
      for (final to in fetched.whereType<TOModel>()) {
        _toCache[to.id] = to;
      }
    }
    return apps
        .map((a) => _ApplicationWithTO(
              application: a,
              to: a.toId != null ? _toCache[a.toId!] : null,
            ))
        .toList();
  }

  Future<Map<String, EmploymentContractModel>> _loadContracts(
    String uid,
    List<_ApplicationWithTO> items,
  ) async {
    final hasConfirmed = items.any((a) =>
        a.application.status == AppStatus.confirmed ||
        a.application.status == AppStatus.contractPending);
    if (!hasConfirmed) return {};
    final contracts = await _contractService.getByWorker(uid);
    final result = <String, EmploymentContractModel>{};
    for (final c in contracts) {
      final ids = c.applicationIds.isNotEmpty ? c.applicationIds : [c.applicationId];
      for (final id in ids) {
        if (id.isNotEmpty) result[id] = c;
      }
    }
    _contractsLoaded = true;
    return result;
  }

  Future<Map<String, MonthlyReviewModel?>> _loadWrittenReviews(
    String uid,
    List<_ApplicationWithTO> items,
  ) async {
    final relevant = items.where((item) {
      final app = item.application;
      if (app.status != AppStatus.confirmed) return false;
      final rd = _reviewDate(app);
      return rd != null && rd.isBefore(DateTime.now());
    }).toList();
    if (relevant.isEmpty) return {};

    final keyToAppIds = <String, List<String>>{};
    for (final item in relevant) {
      final app = item.application;
      final rd  = _reviewDate(app)!;
      final key = MonthlyReviewModel.generateKeyForBusiness(
        businessId: app.businessId,
        reviewerId: uid,
        year: rd.year,
        month: rd.month,
      );
      keyToAppIds.putIfAbsent(key, () => []).add(app.id);
    }

    final uncachedKeys = keyToAppIds.keys
        .where((k) => !_reviewKeyCache.containsKey(k))
        .toList();
    if (uncachedKeys.isNotEmpty) {
      final fetched = await Future.wait(
        uncachedKeys.map((key) => _reviewService.getReviewById(key)),
      );
      for (var i = 0; i < uncachedKeys.length; i++) {
        _reviewKeyCache[uncachedKeys[i]] = fetched[i];
      }
    }

    final result = <String, MonthlyReviewModel?>{};
    for (final entry in keyToAppIds.entries) {
      for (final appId in entry.value) {
        result[appId] = _reviewKeyCache[entry.key];
      }
    }
    return result;
  }

  DateTime? _reviewDate(ApplicationModel app) {
    if (app.isLongTermApplication) {
      return app.actualResignDate ?? app.workEndDate;
    }
    return app.workDate;
  }

  // ─── 필터 로직 ─────────────────────────────────────────────────────────────

  List<_ApplicationWithTO> get _filteredApplications {
    if (_cachedFiltered != null && _cachedGroupIdx == _selectedGroupIdx) {
      return _cachedFiltered!;
    }
    _cachedGroupIdx = _selectedGroupIdx;
    _cachedFiltered = _computeFiltered();
    return _cachedFiltered!;
  }

  List<_ApplicationWithTO> _computeFiltered() {
    if (_selectedGroupIdx == 0) return _applications;
    final target = _UiGroup.values[_selectedGroupIdx];
    return _applications
        .where((item) => _statusToGroup(item.application.status) == target)
        .toList();
  }

  /// 그룹별 카운트 (칩에 숫자 표시용)
  Map<_UiGroup, int> get _groupCounts {
    final counts = <_UiGroup, int>{for (final g in _UiGroup.values) g: 0};
    counts[_UiGroup.all] = _applications.length;
    for (final item in _applications) {
      final g = _statusToGroup(item.application.status);
      counts[g] = (counts[g] ?? 0) + 1;
    }
    return counts;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // build
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final isEmbedded = widget.onBack != null;

    // 로딩 완료 + 전체 지원 0건 → 필터 숨김 (CASE A)
    final totalIsZero = !_isLoading && _applications.isEmpty && !_hasMore;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: isEmbedded
          ? null
          : AppBar(
              title: const Text('내 지원 내역'),
              backgroundColor: Colors.white,
              foregroundColor: AppColors.textPrimary,
              elevation: 0,
              leading: BackButton(
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
      body: SafeArea(
        top: !isEmbedded, // 임베드 시 상위 SafeArea 이미 처리됨
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 필터 칩 (전체 지원 0건이면 숨김) ─────────────────
            if (!totalIsZero) ...[
              const SizedBox(height: 16),
              _buildFilterChips(),
            ],
            // ── 구분선 ─────────────────────────────────────────────
            Container(height: 1, color: AppColors.grey200),
            // ── 목록 ───────────────────────────────────────────────
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ─── 필터 칩 행 ─────────────────────────────────────────────────────────────

  Widget _buildFilterChips() {
    final counts = _isLoading ? null : _groupCounts;
    return SizedBox(
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
        itemCount: _UiGroup.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final group    = _UiGroup.values[i];
          final selected = _selectedGroupIdx == i;
          final count    = counts?[group] ?? 0;
          final label    = counts != null
              ? '${group.label} $count'
              : group.label;

          return GestureDetector(
            onTap: () {
              if (_selectedGroupIdx == i) return;
              setState(() {
                _selectedGroupIdx = i;
                _autoLoadCount    = 0;
                _cachedFiltered   = null;
              });
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted &&
                    _filteredApplications.isEmpty &&
                    _hasMore &&
                    !_isLoadingMore) {
                  _loadMore();
                }
              });
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeInOut,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
              decoration: BoxDecoration(
                color: selected ? AppColors.brand : AppColors.grey100,
                borderRadius: BorderRadius.circular(20),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? Colors.white : AppColors.grey700,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── body ───────────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_isLoading) return const ApplicationListSkeleton();

    // CASE A: 전체 지원 0건 → No-Application Empty State
    if (_applications.isEmpty && !_hasMore) {
      return _buildNoApplicationEmptyState();
    }

    // CASE B / C: 전체 > 0
    final filtered = _filteredApplications;
    if (filtered.isEmpty && !_hasMore) {
      // CASE C: 필터 결과 0건 (전체는 있음) → 경량 Filter Empty State
      return _buildFilterEmptyState();
    }

    return RefreshIndicator(
      onRefresh: _loadApplications,
      color: AppColors.brand,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        itemCount: filtered.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (index == filtered.length) {
            return _isLoadingMore
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: LoadingWidget(),
                  )
                : const SizedBox.shrink();
          }
          return _buildApplicationCard(filtered[index]);
        },
      ),
    );
  }

  // ─── 빈 상태 (CASE A) — 전체 지원 0건 ──────────────────────────────────────
  //
  // SizedBox(width: double.infinity) 필수:
  // SingleChildScrollView → SizedBox 에 LOOSE 폭 전달 → width 미지정 시
  // Column 이 intrinsic width(~220dp)로 축소되어 좌측으로 쏠리는 현상 방지.

  Widget _buildNoApplicationEmptyState() {
    return RefreshIndicator(
      onRefresh: _loadApplications,
      color: AppColors.brand,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          width: double.infinity,  // ← 폭을 available max로 고정
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 130, 24, 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Icon(
                  Icons.work_outline,
                  size: 52,
                  color: AppColors.grey300,
                ),
                const SizedBox(height: 22),
                const Text(
                  '아직 지원한 일자리가 없어요',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey700,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  '일하고 싶은 날짜를 선택하고\n나에게 맞는 일자리를 찾아보세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: AppColors.grey500,
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 52,
                  width: 220,
                  child: FilledButton(
                    onPressed: () => widget.onBack?.call(),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13),
                      ),
                    ),
                    child: const Text(
                      '날짜 선택하기',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 빈 상태 (CASE C) — 필터 결과 0건 (전체 > 0) ───────────────────────────

  Widget _buildFilterEmptyState() {
    final group = _UiGroup.values[_selectedGroupIdx];
    final String title = switch (group) {
      _UiGroup.inProgress => '진행 중인 지원이 없어요',
      _UiGroup.confirmed  => '확정된 일자리가 없어요',
      _UiGroup.ended      => '종료된 지원 내역이 없어요',
      _UiGroup.invited    => '받은 초대가 없어요',
      _UiGroup.all        => '일치하는 지원 내역이 없어요',
    };
    final IconData icon = group == _UiGroup.invited
        ? Icons.mail_outline
        : Icons.search_off_outlined;

    return RefreshIndicator(
      onRefresh: _loadApplications,
      color: AppColors.brand,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          width: double.infinity,  // ← 동일 이유로 width 고정
          child: Padding(
            padding: const EdgeInsets.only(top: 100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(icon, size: 44, color: AppColors.grey300),
                const SizedBox(height: 14),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.grey600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 지원서 카드
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildApplicationCard(_ApplicationWithTO item) {
    final app = item.application;
    final to  = item.to;

    // TO 소프트 삭제 / 하드 삭제 카드
    if (to == null || to.isSoftDeleted) {
      return _buildDeletedCard(app, to);
    }

    final contract   = _contractMap[app.id];
    final statusInfo = _statusInfo(app.status);
    final now        = DateTime.now();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => JobPostingScreen(
                to: to,
                workDetails: to.workDetails,
                myApplication: app,
                myContract: contract,
              ),
            ),
          ).then((changed) {
            if (changed == true && mounted) _loadApplications();
          }),
          borderRadius: BorderRadius.circular(16),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.grey200),
              boxShadow: [
                BoxShadow(
                  color: AppColors.grey300.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
              color: Colors.white,
            ),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 1행: 사업장명 + 상태 배지 ──────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        app.businessName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildStatusBadge(statusInfo),
                  ],
                ),
                const SizedBox(height: 4),

                // ── 2행: 업무명 (TO 제목) ────────────────────────────
                Text(
                  to.title,
                  style: AppTextStyles.jobTitle(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),

                // ── 3행: 날짜·시간 ────────────────────────────────────
                _buildDateTimeRow(app, to, now: now),
                const SizedBox(height: 3),

                // ── 4행: 급여 ─────────────────────────────────────────
                _buildWageRow(app),

                // ── 장기 공고 전용 섹션 ───────────────────────────────
                if (app.isLongTermApplication &&
                    AppStatus.confirmedStatuses.contains(app.status)) ...[
                  _buildLongTermStatusSection(app),
                  _buildInterimSettlementButton(app),
                  if (!app.isTerminationApproved &&
                      app.resignStatus != 'PENDING')
                    _buildResignButton(app),
                ],

                // ── 구분선 + 컨텍스트 행 ─────────────────────────────
                const SizedBox(height: 8),
                Container(height: 1, color: AppColors.grey100),
                const SizedBox(height: 7),
                _buildContextRow(app, contract, now: now),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ─── 삭제된 공고 카드 (간소화) ─────────────────────────────────────────────

  Widget _buildDeletedCard(ApplicationModel app, TOModel? to) {
    final isDeleted = to == null;
    final statusInfo = _statusInfo(app.status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.grey50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.grey200),
        ),
        child: Row(children: [
          Icon(Icons.info_outline, color: AppColors.grey400, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                isDeleted ? '삭제된 공고' : to.title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: AppColors.grey600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${app.businessName} · ${statusInfo.label}${isDeleted ? ' · 공고 삭제됨' : ''}',
                style: const TextStyle(fontSize: 12, color: AppColors.grey400),
              ),
            ]),
          ),
        ]),
      ),
    );
  }

  // ─── 날짜·시간 행 ────────────────────────────────────────────────────────────

  Widget _buildDateTimeRow(ApplicationModel app, TOModel to, {required DateTime now}) {
    final String dateText;
    if (app.isLongTermApplication) {
      final start = app.desiredStartDate ?? to.startDate ?? app.workDate;
      final end   = app.actualResignDate ?? app.workEndDate ?? to.endDate;
      dateText = end != null
          ? '${FormatHelper.formatDateCompact(start)} ~ ${FormatHelper.formatDateCompact(end)}'
          : FormatHelper.formatDateLong(start);
    } else {
      final dt  = app.workDate;
      final day = _korWeekday[dt.weekday - 1];
      final time = (app.startTime.isNotEmpty && app.endTime.isNotEmpty)
          ? ' · ${app.startTime}~${app.endTime}'
          : '';
      dateText = '${_mdFmt.format(dt)}($day)$time';
    }

    // D-day 배지 (장기 공고 + 확정)
    final effectiveEnd = app.isLongTermApplication
        ? (app.actualResignDate ?? app.workEndDate ?? to.endDate)
        : null;

    return Row(
      children: [
        const Icon(Icons.calendar_today_outlined,
            size: 13, color: AppColors.grey500),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            dateText,
            style: AppTextStyles.jobMeta(),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (app.isLongTermApplication &&
            AppStatus.confirmedStatuses.contains(app.status) &&
            effectiveEnd != null) ...[
          const SizedBox(width: 6),
          _buildDdayBadge(effectiveEnd, now: now),
        ],
      ],
    );
  }

  Widget _buildDdayBadge(DateTime endDate, {required DateTime now}) {
    final end       = FormatHelper.toKstDate(endDate);
    final todayOnly = FormatHelper.toKstDate(now);
    final remaining = end.difference(todayOnly).inDays;

    final String label;
    final Color  color;
    if (remaining < 0)       { label = '만료';        color = AppColors.grey500; }
    else if (remaining == 0) { label = 'D-Day';       color = AppColors.error;   }
    else if (remaining <= 7) { label = 'D-$remaining'; color = AppColors.error;   }
    else if (remaining <= 14){ label = 'D-$remaining'; color = AppColors.warning; }
    else                     { label = 'D-$remaining'; color = AppColors.success; }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ─── 급여 행 ──────────────────────────────────────────────────────────────────

  Widget _buildWageRow(ApplicationModel app) {
    final wageLabel = app.wageTypeLabel.isNotEmpty
        ? '${app.wageTypeLabel} ${app.formattedWage}'
        : app.formattedWage;
    return Text(
      wageLabel,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w700,
        color: AppColors.brand,
        letterSpacing: -0.3,
      ),
    );
  }

  // ─── 상태 배지 ───────────────────────────────────────────────────────────────

  Widget _buildStatusBadge(_StatusInfo info) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: info.bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        info.label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: info.color,
        ),
      ),
    );
  }

  // ─── 컨텍스트 행 ─────────────────────────────────────────────────────────────
  // 현재 상태에서 사용자가 다음에 알아야 할 정보 1가지 + 필요 시 액션

  Widget _buildContextRow(
    ApplicationModel app,
    EmploymentContractModel? contract, {
    required DateTime now,
  }) {
    switch (app.status) {
      // ── 대기 중 ─────────────────────────────────────────────────────────────
      case AppStatus.pending:
        return Row(
          children: [
            Expanded(
              child: Text(
                '지원 결과를 기다리고 있어요',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.brand,
                ),
              ),
            ),
            // 취소 버튼
            GestureDetector(
              onTap: _cancellingIds.contains(app.id)
                  ? null
                  : () => _cancelApplication(app.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.errorBg,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '취소',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _cancellingIds.contains(app.id)
                        ? AppColors.grey400
                        : AppColors.errorDark,
                  ),
                ),
              ),
            ),
          ],
        );

      // ── 계약 진행 중 ─────────────────────────────────────────────────────────
      case AppStatus.contractPending:
        final String ctxText;
        final VoidCallback? action;

        if (contract == null) {
          ctxText = '관리자가 계약서를 준비 중이에요';
          action  = null;
        } else {
          switch (contract.status) {
            case ContractStatus.pendingWorker:
              ctxText = '계약서를 확인하고 서명해주세요';
              action  = _isContractSignOpening
                  ? null
                  : () => _openContractSign(contract);
            case ContractStatus.pendingEmployer:
              ctxText = '관리자 서명을 기다리고 있어요';
              action  = null;
            case ContractStatus.completed:
              ctxText = '계약이 완료되었어요';
              action  = null;
            default:
              ctxText = '계약 진행 중이에요';
              action  = null;
          }
        }
        return _contextTextRow(
          text: ctxText,
          color: AppColors.brand,
          action: action,
        );

      // ── 확정 ─────────────────────────────────────────────────────────────────
      case AppStatus.confirmed:
        final rd     = _reviewDate(app);
        final review = _reviewMap[app.id];
        final today  = FormatHelper.toKstDate(now);

        if (rd != null) {
          final rdDate = FormatHelper.toKstDate(rd);
          if (rdDate == today) {
            // 근무 당일
            return const Text(
              '오늘 근무 예정이에요',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.successDark,
              ),
            );
          } else if (rdDate.isBefore(today)) {
            // 근무 완료 이후
            if (review != null) {
              return const Text(
                '근무 완료 · 리뷰 작성 완료',
                style: TextStyle(fontSize: 13, color: AppColors.grey600),
              );
            }
            // 리뷰 작성 가능 윈도우
            final monthEnd = DateTime(rd.year, rd.month + 1, 0);
            final withinWindow = now.isBefore(monthEnd.add(const Duration(days: 15)));
            if (withinWindow) {
              return _contextTextRow(
                text: '리뷰를 작성해 주세요',
                color: AppColors.brand,
                action: _reviewDialogOpenIds.contains(app.id)
                    ? null
                    : () => _openReviewDialog(app, rd),
              );
            }
            return const Text(
              '근무 완료',
              style: TextStyle(fontSize: 13, color: AppColors.grey600),
            );
          }
        }

        // 출근 예정 (미래 또는 장기 공고 진행 중)
        {
          final workDate = app.isLongTermApplication
              ? (app.desiredStartDate ?? app.workDate)
              : app.workDate;
          final workDay  = _korWeekday[workDate.weekday - 1];
          final dateStr  = '${_mdFmt.format(workDate)}($workDay)';
          return Text(
            '$dateStr 출근 예정이에요',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.successDark,
            ),
          );
        }

      // ── 거절 ─────────────────────────────────────────────────────────────────
      case AppStatus.rejected:
        return Text(
          app.rejectMessage?.isNotEmpty == true
              ? app.rejectMessage!
              : '이번 지원은 확정되지 않았어요',
          style: const TextStyle(fontSize: 13, color: AppColors.grey500),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );

      // ── 취소 / 자동취소 ──────────────────────────────────────────────────────
      case AppStatus.canceled:
      case AppStatus.autoCanceled:
        return Text(
          _cancelReasonText(app.cancelReason),
          style: const TextStyle(fontSize: 13, color: AppColors.grey500),
        );

      // ── 초대받음 ─────────────────────────────────────────────────────────────
      case AppStatus.invited:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '근무 초대가 도착했어요',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.brand,
              ),
            ),
            if (app.inviteExpiresAt != null) ...[
              const SizedBox(height: 2),
              Text(
                '~${_mdhmFmt.format(app.inviteExpiresAt!)} 만료',
                style: const TextStyle(fontSize: 11, color: AppColors.grey500),
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _inviteActionButton(
                  label: '수락하기',
                  color: AppColors.brand,
                  bgColor: AppColors.infoBg,
                  loading: _acceptingIds.contains(app.id),
                  onTap: () => _acceptInvite(app.id),
                ),
                const SizedBox(width: 8),
                _inviteActionButton(
                  label: '거절',
                  color: AppColors.grey600,
                  bgColor: AppColors.grey100,
                  loading: _decliningIds.contains(app.id),
                  onTap: () => _declineInvite(app.id),
                ),
              ],
            ),
          ],
        );

      // ── 초대 만료 ────────────────────────────────────────────────────────────
      case AppStatus.expired:
        return const Text(
          '초대 유효기간이 종료되었어요',
          style: TextStyle(fontSize: 13, color: AppColors.grey400),
        );

      default:
        return const SizedBox.shrink();
    }
  }

  /// 텍스트 + 선택적 chevron 행
  Widget _contextTextRow({
    required String text,
    required Color color,
    VoidCallback? action,
  }) {
    final child = Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
        if (action != null)
          Icon(Icons.chevron_right, size: 16, color: color),
      ],
    );
    if (action == null) return child;
    return GestureDetector(
      onTap: action,
      behavior: HitTestBehavior.opaque,
      child: child,
    );
  }

  /// 초대 수락/거절 버튼
  Widget _inviteActionButton({
    required String label,
    required Color color,
    required Color bgColor,
    required bool loading,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: loading ? AppColors.grey400 : color,
          ),
        ),
      ),
    );
  }

  // ─── cancelReason → 사용자 문장 ──────────────────────────────────────────────

  String _cancelReasonText(String? reason) {
    switch (reason) {
      case 'USER_CANCELED':             return '지원이 취소되었어요';
      case 'SAME_DAY_CANCEL':           return '당일 취소 처리된 지원이에요';
      case 'ADMIN_CANCELED':            return '사업장 사정으로 근무가 취소되었어요';
      case 'SCHEDULE_CONFLICT':         return '다른 업무가 확정되어 자동 취소되었어요';
      case 'WORK_DETAIL_EXPIRED':       return '해당 업무 모집이 마감되었어요';
      case 'SLOT_WORK_DETAIL_EXPIRED':  return '해당 업무 모집이 마감되었어요';
      case 'TO_EXPIRED':                return '모집 기간이 종료되어 자동 취소되었어요';
      case 'TO_DELETED':                return '공고가 삭제되어 자동 취소되었어요';
      default:                          return '취소된 지원이에요';
    }
  }

  // ─── 상태 정보 헬퍼 ──────────────────────────────────────────────────────────

  _StatusInfo _statusInfo(String status) {
    switch (status) {
      case AppStatus.pending:
        return const _StatusInfo(
          label: '지원 검토 중',
          color: AppColors.warningDark,
          bgColor: AppColors.warningBg,
        );
      case AppStatus.contractPending:
        return const _StatusInfo(
          label: '계약 진행 중',
          color: AppColors.infoDark,
          bgColor: AppColors.infoBg,
        );
      case AppStatus.confirmed:
        return const _StatusInfo(
          label: '확정',
          color: AppColors.successDark,
          bgColor: AppColors.successBg,
        );
      case AppStatus.rejected:
        return const _StatusInfo(
          label: '거절',
          color: AppColors.errorDark,
          bgColor: AppColors.errorBg,
        );
      case AppStatus.canceled:
        return const _StatusInfo(
          label: '취소',
          color: AppColors.grey600,
          bgColor: AppColors.grey100,
        );
      case AppStatus.autoCanceled:
        return const _StatusInfo(
          label: '자동 취소',
          color: AppColors.grey600,
          bgColor: AppColors.grey100,
        );
      case AppStatus.invited:
        return const _StatusInfo(
          label: '근무 초대',
          color: AppColors.infoDark,
          bgColor: AppColors.infoBg,
        );
      case AppStatus.expired:
        return const _StatusInfo(
          label: '초대 종료',
          color: AppColors.grey600,
          bgColor: AppColors.grey200,
        );
      default:
        return const _StatusInfo(
          label: '알 수 없음',
          color: AppColors.grey600,
          bgColor: AppColors.grey200,
        );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 장기 공고 전용 섹션 — 기존 로직 그대로 유지
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildLongTermStatusSection(ApplicationModel app) {
    final resignStatus      = app.resignStatus;
    final terminationStatus = app.terminationStatus;
    if (resignStatus == null && terminationStatus == null) {
      return const SizedBox.shrink();
    }

    final banners = <Widget>[];
    final mdFmt   = DateFormat('MM.dd');

    if (resignStatus != null) {
      final (icon, color, bgColor, label) = switch (resignStatus) {
        'PENDING' => (
            Icons.exit_to_app_outlined, AppColors.warningDark, AppColors.warningBg,
            app.resignRequestDate != null
                ? '퇴사 신청 중 · 희망일 ${mdFmt.format(app.resignRequestDate!)}'
                : '퇴사 신청 중',
          ),
        'APPROVED' || 'AUTO_APPROVED' => (
            Icons.check_circle_outline, AppColors.successDark, AppColors.successBg,
            app.actualResignDate != null
                ? '퇴사 확정 · ${mdFmt.format(app.actualResignDate!)}'
                : '퇴사 확정',
          ),
        'REJECTED' => (
            Icons.cancel_outlined, AppColors.errorDark, AppColors.errorBg,
            app.resignRejectReason?.isNotEmpty == true
                ? '퇴사 신청 거절 · ${app.resignRejectReason}'
                : '퇴사 신청이 거절되었습니다',
          ),
        _ => (Icons.info_outline, AppColors.grey600, AppColors.grey100, '퇴사 신청 처리 중'),
      };
      banners.add(_longTermBanner(icon, color, bgColor, label));
    }

    if (terminationStatus != null) {
      final (icon, color, bgColor, label) = switch (terminationStatus) {
        'PENDING' => (
            Icons.warning_amber_outlined, AppColors.warningDark, AppColors.warningBg,
            app.terminationReason?.isNotEmpty == true
                ? '계약해지 요청 수신 · ${app.terminationReason}'
                : '계약해지 요청이 접수되었습니다',
          ),
        'APPROVED' || 'AUTO_APPROVED' => (
            Icons.assignment_turned_in_outlined, AppColors.infoDark, AppColors.infoBg,
            app.terminationEffectiveDate != null
                ? '계약해지 완료 · ${mdFmt.format(app.terminationEffectiveDate!)}'
                : '계약해지 완료',
          ),
        'REJECTED' => (
            Icons.block_outlined, AppColors.grey600, AppColors.grey100,
            app.terminationRejectReason?.isNotEmpty == true
                ? '계약해지 거절 · ${app.terminationRejectReason}'
                : '계약해지 거절 처리됨',
          ),
        _ => (Icons.info_outline, AppColors.grey600, AppColors.grey100, '계약해지 처리 중'),
      };
      banners.add(_longTermBanner(icon, color, bgColor, label));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: banners);
  }

  Widget _longTermBanner(
    IconData icon, Color color, Color bgColor, String label,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ]),
    );
  }

  Widget _buildInterimSettlementButton(ApplicationModel app) {
    return Container(
      margin: const EdgeInsets.only(top: 6),
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          final requested = await Navigator.push<bool>(
            context,
            MaterialPageRoute(
              builder: (_) => InterimSettlementRequestScreen(app: app),
            ),
          );
          if (requested == true && mounted) _loadApplications();
        },
        icon: const Icon(Icons.account_balance_wallet_outlined, size: 15),
        label: const Text('중간정산 요청', style: TextStyle(fontSize: 13)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.tealDark,
          side: const BorderSide(color: AppColors.teal),
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Widget _buildResignButton(ApplicationModel app) {
    final isRejected = app.resignStatus == 'REJECTED';
    return Container(
      margin: const EdgeInsets.only(top: 6),
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () async {
          final allApps = _applications.map((a) => a.application).toList();
          await showDialog<void>(
            context: context,
            barrierDismissible: false,
            builder: (_) => LongTermWorkManagementDialog(
              applications: allApps,
              onChanged: _loadApplications,
            ),
          );
        },
        icon: const Icon(Icons.logout_outlined, size: 15),
        label: Text(
          isRejected ? '퇴사 재신청' : '퇴사 신청',
          style: const TextStyle(fontSize: 13),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: BorderSide(color: AppColors.error.withValues(alpha: 0.6)),
          padding: const EdgeInsets.symmetric(vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // 액션 핸들러 — 비즈니스 로직 변경 없음
  // ═══════════════════════════════════════════════════════════════════════════

  Future<void> _acceptInvite(String applicationId) async {
    if (_acceptingIds.contains(applicationId)) return;
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) { ToastHelper.showError('로그인이 필요합니다.'); return; }

    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '초대 수락',
      message: '이 업무에 참여하시겠습니까?\n수락 후 일정 충돌이 없으면 확정됩니다.',
      confirmText: '수락',
      cancelText: '취소',
      icon: Icons.check_circle_outline,
      confirmColor: AppColors.success,
    );
    if (!confirmed || !mounted) return;

    setState(() => _acceptingIds.add(applicationId));
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableAcceptTOInvitation');
      await callable.call({'applicationId': applicationId});
      if (!mounted) return;
      ToastHelper.showSuccess('초대를 수락했습니다!');
      _loadApplications();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ToastHelper.showError(e.message ?? '수락 중 오류가 발생했습니다.');
    } catch (e) {
      if (mounted) ToastHelper.showError('수락 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _acceptingIds.remove(applicationId));
    }
  }

  Future<void> _declineInvite(String applicationId) async {
    if (_decliningIds.contains(applicationId)) return;
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) { ToastHelper.showError('로그인이 필요합니다.'); return; }

    final confirmed = await DialogHelper.showCancelConfirm(
      context,
      title: '초대 거절',
      message: '초대를 거절하시겠습니까?',
    );
    if (!confirmed || !mounted) return;

    setState(() => _decliningIds.add(applicationId));
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableDeclineTOInvitation');
      await callable.call({'applicationId': applicationId});
      if (!mounted) return;
      ToastHelper.showInfo('초대를 거절했습니다.');
      _loadApplications();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ToastHelper.showError(e.message ?? '거절 중 오류가 발생했습니다.');
    } catch (e) {
      if (mounted) ToastHelper.showError('거절 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _decliningIds.remove(applicationId));
    }
  }

  Future<void> _cancelApplication(String applicationId) async {
    if (_cancellingIds.contains(applicationId)) return;
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) { ToastHelper.showError('로그인이 필요합니다.'); return; }

    setState(() => _cancellingIds.add(applicationId));
    try {
      final confirmed = await DialogHelper.showCancelConfirm(
        context,
        title: '지원 취소',
        message: '지원을 취소하시겠습니까?',
      );
      if (!confirmed || !mounted) return;

      final success = await _firestoreService.cancelApplication(applicationId, uid);
      if (!mounted) return;
      if (success) {
        final idx = _applications.indexWhere((item) => item.application.id == applicationId);
        if (idx >= 0) {
          final old = _applications[idx];
          setState(() {
            _applications = List.from(_applications)
              ..[idx] = _ApplicationWithTO(
                application: old.application.copyWith(status: AppStatus.canceled),
                to: old.to,
              );
            _contractMap.remove(applicationId);
            _cachedFiltered = null;
            _cancellingIds.remove(applicationId);
          });
        } else {
          _loadApplications();
        }
      }
    } catch (e) {
      debugPrint('❌ 지원 취소 오류: $e');
      if (mounted) ToastHelper.showError('취소 중 오류가 발생했습니다.');
    } finally {
      if (mounted && _cancellingIds.contains(applicationId)) {
        setState(() => _cancellingIds.remove(applicationId));
      }
    }
  }

  Future<void> _openContractSign(EmploymentContractModel contract) async {
    if (_isContractSignOpening || !mounted) return;
    setState(() => _isContractSignOpening = true);
    try {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ContractSignScreen(contract: contract, role: 'worker'),
        ),
      );
    } finally {
      if (mounted) setState(() => _isContractSignOpening = false);
    }
    if (!mounted) return;
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;
    _contractsLoaded = false;
    final updated = await _loadContracts(uid, _applications);
    if (!mounted) return;
    setState(() => _contractMap = {..._contractMap, ...updated});
  }

  Future<void> _openReviewDialog(ApplicationModel app, DateTime reviewDate) async {
    if (_reviewDialogOpenIds.contains(app.id)) return;
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;
    setState(() => _reviewDialogOpenIds.add(app.id));
    try {
      ReviewRequestModel? reviewRequest;
      List<AttendanceModel> attendances = [];
      await Future.wait([
        _reviewService.getReviewRequest(
          ReviewRequestModel.generateKey(
            businessId: app.businessId,
            workerId: uid,
            year: reviewDate.year,
            month: reviewDate.month,
          ),
        ).then((r) => reviewRequest = r),
        _firestoreService.getMyMonthlyAttendances(
          userId: uid,
          year: reviewDate.year,
          month: reviewDate.month,
        ).then((a) => attendances = a),
      ]);
      if (!mounted) return;
      final workDaysInMonth = attendances
          .where((a) =>
              a.businessId == app.businessId &&
              (a.isWageConfirmed || a.isWageTransferred))
          .length;

      final result = await showBusinessReviewDialog(
        context,
        reviewerId: uid,
        businessId: app.businessId,
        businessName: app.businessName,
        reviewYear: reviewDate.year,
        reviewMonth: reviewDate.month,
        workDaysInMonth: workDaysInMonth,
        requestId: reviewRequest?.id,
      );
      if (result == true && mounted) {
        final key = MonthlyReviewModel.generateKeyForBusiness(
          businessId: app.businessId,
          reviewerId: uid,
          year: reviewDate.year,
          month: reviewDate.month,
        );
        final review = await _reviewService.getReviewById(key);
        if (!mounted) return;
        setState(() => _reviewMap[app.id] = review);
      }
    } catch (e) {
      debugPrint('❌ 리뷰 다이얼로그 오류: $e');
      if (mounted) ToastHelper.showError('리뷰 데이터를 불러오는데 실패했습니다.');
    } finally {
      if (mounted) setState(() => _reviewDialogOpenIds.remove(app.id));
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// 데이터 클래스 (변경 없음)
// ═══════════════════════════════════════════════════════════════════════════════

class _ApplicationWithTO {
  final ApplicationModel application;
  final TOModel? to;
  const _ApplicationWithTO({required this.application, this.to});
}

class _StatusInfo {
  final String label;
  final Color  color;
  final Color  bgColor;
  const _StatusInfo({
    required this.label,
    required this.color,
    required this.bgColor,
  });
}
