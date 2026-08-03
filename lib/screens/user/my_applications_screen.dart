import 'package:flutter/material.dart';
import 'dart:async' show unawaited;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../models/core/monthly_review_model.dart';
import '../../models/core/review_request_model.dart';
import '../../models/core/to_model.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../screens/user/interim_settlement_request_screen.dart';
import '../../screens/common/job_posting_screen.dart';
import '../../services/contract_service.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_review_service.dart';
import '../../widgets/dialogs/business_review_dialog.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/skeleton_widget.dart';
import '../../widgets/work_type_icon.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_tab_label.dart';

/// 내 지원 내역 화면 (리팩토링 버전)
class MyApplicationsScreen extends StatefulWidget {
  const MyApplicationsScreen({super.key});

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen>
    with TickerProviderStateMixin {
  static const _tabLabels = ['전체', '대기중', '확정', '계약대기', '거절', '취소'];
  static const _tabFilters = [
    'ALL',
    AppStatus.pending,
    AppStatus.confirmed,
    AppStatus.contractPending,
    AppStatus.rejected,
    AppStatus.canceled,
  ];
  final FirestoreService _firestoreService = FirestoreService();
  final ContractService _contractService = ContractService();
  final MonthlyReviewService _reviewService = MonthlyReviewService(); // M-4: 매번 new 대신 재사용
  final ScrollController _scrollController = ScrollController();

  List<_ApplicationWithTO> _applications = [];
  Map<String, EmploymentContractModel> _contractMap = {};
  Map<String, MonthlyReviewModel?> _reviewMap = {};

  // M-3: TO 화면 수준 캐시 — _loadMore마다 동일 TO 반복 서버 읽기 방지
  final Map<String, TOModel> _toCache = {};
  // H-4: 리뷰 key 캐시 — 같은 biz+month 리뷰를 여러 지원서가 공유할 때 중복 Firestore 읽기 방지
  final Map<String, MonthlyReviewModel?> _reviewKeyCache = {};
  // H-2: getByWorker(200건) 중복 호출 방지 — 초기 로드 후 _loadMore에서 재호출 차단
  bool _contractsLoaded = false;
  // M-2: _filteredApplications 매 build마다 O(N) 재계산 방지
  List<_ApplicationWithTO>? _cachedFiltered;
  int _cachedFilterIdx = -1;

  bool _isLoading = true;
  bool _fetchInProgress = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _lastDocId;

  late final TabController _tabCtrl;
  int _autoLoadCount = 0;
  static const int _maxAutoLoad = 5;

  final Set<String> _cancellingIds = {};
  final Set<String> _reviewDialogOpenIds = {};
  bool _isContractSignOpening = false;

  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabLabels.length, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        // M-1: 탭 전환은 클라이언트 필터 변경 — _hasMore는 서버 페이지 상태라 건드리지 않음
        // M-2: 탭 인덱스 변경 시 필터 캐시 무효화
        setState(() { _autoLoadCount = 0; _cachedFiltered = null; });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _filteredApplications.isEmpty && _hasMore && !_isLoadingMore) {
            _loadMore();
          }
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadApplications();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadApplications() async {
    if (!mounted) return; // _cancelApplication 등 재호출 경로에서 화면 pop 후 진입 방지
    if (_fetchInProgress) return; // 동시 다중 호출 방지 (pull-to-refresh + 자동 재로드 경합)
    _fetchInProgress = true;
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) {
      ToastHelper.showError('로그인이 필요합니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _applications = [];
      _lastDocId = null;
      _hasMore = true;
      // H-2: 전체 재로드 시 계약서·TO·리뷰 캐시 초기화
      _contractsLoaded = false;
      _toCache.clear();
      _reviewKeyCache.clear();
      _cachedFiltered = null;
    });

    try {
      // 만료된 PENDING 자동 처리 — unawaited로 병렬 실행해 화면 로드를 블로킹하지 않음
      // [BUG-FIX] await 사용 시 성공 경로에서도 만료 처리 완료까지 데이터 로드 지연 발생
      unawaited(_firestoreService.autoExpirePendingApplications(uid).catchError((e) {
        debugPrint('⚠️ autoExpirePendingApplications 실패 (무시): $e');
      }));

      final page = await _firestoreService.getMyApplicationsPaged(
        uid: uid, pageSize: _pageSize,
      );
      final items = page['items'] as List<ApplicationModel>;
      final appWithTOs = await _attachTOInfo(items);

      // [PERF] 계약서 · 리뷰 병렬 로드 (_loadMore와 동일 패턴)
      final initResults = await Future.wait([
        _loadContracts(uid, appWithTOs).catchError((_) => <String, EmploymentContractModel>{}),
        _loadWrittenReviews(uid, appWithTOs).catchError((_) => <String, MonthlyReviewModel?>{}),
      ]);
      final contractMap = initResults[0] as Map<String, EmploymentContractModel>;
      final reviewMap   = initResults[1] as Map<String, MonthlyReviewModel?>;

      if (mounted) {
        setState(() {
          _applications = appWithTOs;
          _contractMap = contractMap;
          _reviewMap = reviewMap;
          _lastDocId = page['lastDocId'] as String?;
          _hasMore = page['hasMore'] as bool;
          _isLoading = false;
          _cachedFiltered = null; // M-2: 새 데이터 반영
        });
      }
    } catch (e) {
      debugPrint('❌ 지원 내역 로드 실패: $e');
      if (mounted) {
        ToastHelper.showError(_firestoreErrMsg(e, '지원 내역을 불러오는데 실패했습니다.'));
        setState(() => _isLoading = false);
      }
    } finally {
      _fetchInProgress = false; // L-1: mounted 여부와 무관하게 반드시 해제
    }
  }

  /// Firestore 예외 코드에 따라 사용자 친화적 오류 메시지 반환
  String _firestoreErrMsg(dynamic e, String fallback) {
    if (e is FirebaseException) {
      return switch (e.code) {
        'unavailable' || 'network-request-failed' =>
          '네트워크 연결을 확인해 주세요.',
        'permission-denied' =>
          '권한이 없습니다. 관리자에게 문의하세요.',
        'not-found' =>
          '데이터를 찾을 수 없습니다. 이미 삭제되었을 수 있습니다.',
        'deadline-exceeded' || 'cancelled' =>
          '요청 시간이 초과되었습니다. 다시 시도해 주세요.',
        _ => fallback,
      };
    }
    return fallback;
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore || _lastDocId == null) return;
    if (_fetchInProgress) return; // H-1: _loadApplications와 동시 실행 방지
    if (!mounted) return;
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoadingMore = true);
    try {
      final page = await _firestoreService.getMyApplicationsPaged(
        uid: uid, pageSize: _pageSize, startAfterDocId: _lastDocId,
      );
      final items = page['items'] as List<ApplicationModel>;
      final appWithTOs = await _attachTOInfo(items);
      // H-2: _contractsLoaded=true이면 계약서 200건 재호출 건너뜀 (TO 캐시와 동일 원칙)
      final moreResults = await Future.wait([
        _contractsLoaded
            ? Future.value(<String, EmploymentContractModel>{})
            : _loadContracts(uid, appWithTOs),
        _loadWrittenReviews(uid, appWithTOs),
      ]);
      final newContracts = moreResults[0] as Map<String, EmploymentContractModel>;
      final newReviews = moreResults[1] as Map<String, MonthlyReviewModel?>;

      if (mounted) {
        setState(() {
          _applications = [..._applications, ...appWithTOs];
          _contractMap = {..._contractMap, ...newContracts};
          _reviewMap = {..._reviewMap, ...newReviews};
          _lastDocId = page['lastDocId'] as String?;
          _hasMore = page['hasMore'] as bool;
          _isLoadingMore = false;
          _cachedFiltered = null; // M-2: 새 항목 추가 시 캐시 무효화
        });
        final filtered = _filteredApplications;
        if (filtered.isEmpty && _hasMore && !_isLoadingMore &&
            _autoLoadCount < _maxAutoLoad) {
          // M-5: 실제 _loadMore() 호출 직전에 카운트 — 호출 전 체크와 카운트 사이 경합 제거
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _filteredApplications.isEmpty && _hasMore && !_isLoadingMore) {
              _autoLoadCount++;
              _loadMore();
            }
          });
        } else if (filtered.isEmpty && _hasMore &&
            _autoLoadCount >= _maxAutoLoad) {
          // [W-01 fix] 자동로드 5회 소진 후에도 필터 통과 항목 없음.
          // _hasMore=true 유지 시 _onScroll이 계속 _loadMore()를 호출하는 무한루프 발생.
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

  /// 지원서 목록에 TO 정보 결합
  /// TO가 삭제됐더라도 지원서는 표시 (to=null로 폴백)
  /// [SAFE] to==null 시 간소화 카드(AppColors.grey50)로 안전 렌더링됨 — null 크래시 없음
  Future<List<_ApplicationWithTO>> _attachTOInfo(List<ApplicationModel> apps) async {
    final toIds = apps.map((a) => a.toId).whereType<String>().toSet().toList();
    if (toIds.isEmpty) return apps.map((a) => _ApplicationWithTO(application: a, to: null)).toList();
    // M-3: 이미 로드한 TO는 캐시에서 반환 — _loadMore마다 동일 TO 반복 서버 읽기 방지
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

  /// 확정/계약 대기 지원서의 계약서 로드
  Future<Map<String, EmploymentContractModel>> _loadContracts(
    String uid,
    List<_ApplicationWithTO> items,
  ) async {
    final hasConfirmed = items.any((a) =>
        a.application.status == AppStatus.confirmed ||
        a.application.status == AppStatus.contractPending);
    if (!hasConfirmed) return {};
    final contracts = await _contractService.getByWorker(uid);
    // 번들 계약서는 applicationIds 배열이 여러 지원서를 포함 → 모든 ID를 키로 맵핑
    final Map<String, EmploymentContractModel> result = {};
    for (final c in contracts) {
      final ids = c.applicationIds.isNotEmpty ? c.applicationIds : [c.applicationId];
      for (final id in ids) {
        if (id.isNotEmpty) result[id] = c;
      }
    }
    _contractsLoaded = true; // H-2: 이후 _loadMore에서 재호출 차단
    return result;
  }

  /// 과거 확정 지원서의 내가 쓴 사업장 리뷰 병렬 조회
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

    // H-4: 같은 biz+month 리뷰를 여러 지원서가 공유할 수 있음 → key 기준으로 dedup 후 캐시
    // key = businessId + reviewerId + year + month (MonthlyReview 식별자)
    final keyToAppIds = <String, List<String>>{};
    for (final item in relevant) {
      final app = item.application;
      final rd = _reviewDate(app)!;
      final key = MonthlyReviewModel.generateKeyForBusiness(
        businessId: app.businessId,
        reviewerId: uid,
        year: rd.year,
        month: rd.month,
      );
      keyToAppIds.putIfAbsent(key, () => []).add(app.id);
    }

    // 이미 캐시된 key는 Firestore 읽기 생략
    final uncachedKeys = keyToAppIds.keys
        .where((k) => !_reviewKeyCache.containsKey(k))
        .toList();
    if (uncachedKeys.isNotEmpty) {
      final fetched = await Future.wait(
        uncachedKeys.map((key) => _reviewService.getReviewById(key)), // M-4: 필드 재사용
      );
      for (var i = 0; i < uncachedKeys.length; i++) {
        _reviewKeyCache[uncachedKeys[i]] = fetched[i];
      }
    }

    // appId → 리뷰 매핑 (캐시 활용)
    final result = <String, MonthlyReviewModel?>{};
    for (final entry in keyToAppIds.entries) {
      for (final appId in entry.value) {
        result[appId] = _reviewKeyCache[entry.key];
      }
    }
    return result;
  }

  /// 리뷰 기준일: 단기=근무일, 장기=종료일(null이면 아직 재직 중 → 리뷰 불가)
  DateTime? _reviewDate(ApplicationModel app) {
    if (app.isLongTermApplication) {
      // actualResignDate/workEndDate 모두 null이면 아직 재직 중 — 리뷰 대상 아님
      return app.actualResignDate ?? app.workEndDate;
    }
    return app.workDate;
  }

  String get _currentFilter => _tabFilters[_tabCtrl.index];

  // M-2: build 사이클마다 O(N) 재계산 방지 — 탭/데이터 변경 시에만 재계산
  List<_ApplicationWithTO> get _filteredApplications {
    final idx = _tabCtrl.index;
    if (_cachedFiltered != null && _cachedFilterIdx == idx) return _cachedFiltered!;
    _cachedFilterIdx = idx;
    _cachedFiltered = _computeFilteredApplications();
    return _cachedFiltered!;
  }

  List<_ApplicationWithTO> _computeFilteredApplications() {
    if (_currentFilter == 'ALL') return _applications;
    return _applications.where((item) {
      final status = item.application.status;
      if (_currentFilter == AppStatus.canceled) {
        return AppStatus.inactiveStates.contains(status) && status != AppStatus.rejected;
      }
      if (_currentFilter == AppStatus.confirmed) {
        return status == AppStatus.confirmed;
      }
      if (_currentFilter == AppStatus.contractPending) {
        return status == AppStatus.contractPending;
      }
      return status == _currentFilter;
    }).toList();
  }

  Future<void> _cancelApplication(String applicationId) async {
    if (_cancellingIds.contains(applicationId)) return;
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;

    if (uid == null) {
      ToastHelper.showError('로그인이 필요합니다.');
      return;
    }

    setState(() => _cancellingIds.add(applicationId));
    try {
      final confirmed = await DialogHelper.showCancelConfirm(
        context,
        title: '지원 취소',
        message: '지원을 취소하시겠습니까?',
      );

      if (!confirmed || !mounted) return;

      // cancelApplication 내부에서 이미 상태에 맞는 토스트(showSuccess/showInfo/showError)를
      // 표시하므로, 여기서는 추가 메시지 없이 화면 갱신만 수행한다.
      // (REJECTED·이미취소 상태에서 success=true가 반환될 때 중복 토스트 방지)
      final success = await _firestoreService.cancelApplication(applicationId, uid);
      if (!mounted) return;
      if (success) {
        // H-3: 단건 취소 → 전체 재로드 대신 로컬 상태만 업데이트
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
            _cachedFiltered = null; // 필터 캐시 무효화
            _cancellingIds.remove(applicationId);
          });
        } else {
          // 리스트에 없으면 fallback으로 전체 재로드
          _loadApplications();
        }
      } else {
        ToastHelper.showError('취소에 실패했습니다.');
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

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '내 지원 내역',
      onRefresh: _loadApplications,
      headerBottom: TabBar(
        controller: _tabCtrl,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white.withValues(alpha: 0.6),
        indicatorColor: Colors.white,
        indicatorWeight: 2.5,
        dividerColor: Colors.transparent,
        tabs: _tabLabels.map((l) => Tab(child: AppTabLabel(label: l))).toList(),
      ),
      body: _isLoading
          ? const ApplicationListSkeleton()
          : _filteredApplications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadApplications,
                  child: ListView.builder(
                    controller: _scrollController,
                    padding: ResponsiveHelper.listPadding(context),
                    itemCount: _filteredApplications.length + (_hasMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _filteredApplications.length) {
                        return _isLoadingMore
                            ? const LoadingWidget()
                            : const SizedBox.shrink();
                      }
                      return _buildApplicationCard(_filteredApplications[index]);
                    },
                  ),
                ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 빈 상태
  // ═══════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return AppEmptyState(
      icon: Icons.assignment_outlined,
      title: _currentFilter == 'ALL' ? '지원 내역이 없습니다' : '해당 상태의 지원이 없습니다',
      subtitle: 'TO에 지원해보세요!',
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 지원서 카드 (간소화된 디자인)
  // ═══════════════════════════════════════════════════════════

  Widget _buildApplicationCard(_ApplicationWithTO item) {
    final app = item.application;
    final to = item.to;
    final statusInfo = _getStatusInfo(app.status);
    final now = DateTime.now(); // 카드당 한 번 — _buildDdayBadge·_buildActionStrip 공유

    // TO가 삭제된 경우 간소화 카드 표시
    if (to == null) {
      return Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
        decoration: BoxDecoration(
          color: AppColors.grey50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.grey200),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 14),
          vertical: ResponsiveHelper.spacing(context, 10),
        ),
        child: Row(children: [
          Icon(Icons.info_outline, color: AppColors.grey400,
              size: ResponsiveHelper.iconSize(context, 18)),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('삭제된 공고',
                  style: ResponsiveHelper.bodyStyle(context,
                      color: AppColors.grey500)),
              Text('${app.businessName} · ${statusInfo.label}',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey400)),
            ]),
          ),
        ]),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 6)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: statusInfo.color.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.grey300.withValues(alpha: 0.4),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => JobPostingScreen(
                to: to,
                workDetails: to.workDetails,
              ),
            ),
          ).then((changed) { if (changed == true && mounted) _loadApplications(); }),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardHeader(app, to, statusInfo),
                SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                Text(
                  to.title,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                _buildDateTimeRow(app, to, now: now),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                _buildWorkWageRow(app),
                if (app.isLongTermApplication && AppStatus.confirmedStatuses.contains(app.status))
                  _buildLongTermStatusSection(app),
                if (app.isLongTermApplication && AppStatus.confirmedStatuses.contains(app.status))
                  _buildInterimSettlementButton(app),
                _buildActionStrip(app, now: now),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardHeader(ApplicationModel app, TOModel to, _StatusInfo statusInfo) {
    return Row(
      children: [
        Icon(
          Icons.business,
          size: ResponsiveHelper.iconSize(context, 13),
          color: AppColors.grey500,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Expanded(
          child: Text(
            '${to.businessName}  ·  ${DateFormat('yy.MM.dd HH:mm').format(app.appliedAt)}',
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        _buildStatusBadge(statusInfo),
      ],
    );
  }

  Widget _buildDateTimeRow(ApplicationModel app, TOModel to, {required DateTime now}) {
    final timeDisplay = (app.startTime.isNotEmpty && app.endTime.isNotEmpty)
        ? '${app.startTime} ~ ${app.endTime}'
        : '--:-- ~ --:--';

    // 장기 근무: 희망 시작일 또는 실제 계약 기간 표시 (갱신·퇴사 반영)
    final String dateDisplay;
    if (app.isLongTermApplication) {
      final start = app.desiredStartDate ?? to.startDate ?? app.workDate;
      // 갱신된 계약의 실제 종료일(app.workEndDate) 우선, 없으면 TO 공고 종료일 표시
      final end = app.actualResignDate ?? app.workEndDate ?? to.endDate;
      dateDisplay = end != null
          ? '${FormatHelper.formatDateCompact(start)} ~ ${FormatHelper.formatDateCompact(end)}'
          : FormatHelper.formatDateLong(start);
    } else {
      dateDisplay = FormatHelper.formatDateLong(app.workDate);
    }

    // D-day 배지: 실제 계약 종료일(갱신·퇴사 반영) 기준
    final effectiveEndDate = app.isLongTermApplication
        ? (app.actualResignDate ?? app.workEndDate ?? to.endDate)
        : null;

    return Row(
      children: [
        Icon(
          app.isLongTermApplication ? Icons.date_range : Icons.calendar_today,
          size: ResponsiveHelper.iconSize(context, 14),
          color: AppColors.grey500,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Flexible(
          child: Text(
            dateDisplay,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (app.isLongTermApplication &&
            (app.status == AppStatus.confirmed || app.status == AppStatus.contractPending) &&
            effectiveEndDate != null) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          _buildDdayBadge(context, effectiveEndDate, now: now),
        ],
        if (!app.isLongTermApplication) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Icon(
            Icons.access_time,
            size: ResponsiveHelper.iconSize(context, 14),
            color: AppColors.grey500,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Flexible(
            child: Text(
              timeDisplay,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDdayBadge(BuildContext context, DateTime endDate, {required DateTime now}) {
    final today = now;
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    final todayOnly = DateTime(today.year, today.month, today.day);
    final remaining = end.difference(todayOnly).inDays;

    final String label;
    final Color color;
    if (remaining < 0) {
      label = '만료';
      color = AppColors.grey500;
    } else if (remaining == 0) {
      label = 'D-Day';
      color = AppColors.error;
    } else if (remaining <= 7) {
      label = 'D-$remaining';
      color = AppColors.error;
    } else if (remaining <= 14) {
      label = 'D-$remaining';
      color = AppColors.warning;
    } else {
      label = 'D-$remaining';
      color = AppColors.success;
    }

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.tinyStyle(context)
            .copyWith(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildWorkWageRow(ApplicationModel app) {
    return Row(
      children: [
        // 업무유형 아이콘
        if (app.workTypeIcon != null)
          WorkTypeIcon.buildWithBackground(
            iconString: app.workTypeIcon!,
            iconColor: app.workTypeColor,
            backgroundColor: app.workTypeBackgroundColor,
            size: ResponsiveHelper.iconSize(context, 12),
            containerSize: ResponsiveHelper.spacing(context, 20),
          )
        else
          Icon(
            Icons.work_outline,
            size: ResponsiveHelper.iconSize(context, 13),
            color: AppColors.grey500,
          ),
        SizedBox(width: ResponsiveHelper.spacing(context, 5)),
        Flexible(
          child: Text(
            app.selectedWorkType,
            overflow: TextOverflow.ellipsis,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        // 급여
        Flexible(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 8),
              vertical: ResponsiveHelper.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              app.formattedWage,
              overflow: TextOverflow.ellipsis,
              style: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.successDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(_StatusInfo statusInfo) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 3),
      ),
      decoration: BoxDecoration(
        color: statusInfo.bgColor,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        statusInfo.label,
        style: ResponsiveHelper.tinyStyle(
          context,
          color: statusInfo.color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 액션 스트립 — 계약서·취소·리뷰를 칩으로 한 줄 표시
  Widget _buildActionStrip(ApplicationModel app, {required DateTime now}) {
    final chips = <Widget>[];

    // 자동취소 사유 칩
    if (app.status == AppStatus.autoCanceled) {
      final String reasonText;
      switch (app.cancelReason) {
        case 'SLOT_WORK_DETAIL_EXPIRED':
          reasonText = '슬롯 업무 마감으로 자동 취소됨';
        case 'WORK_DETAIL_EXPIRED':
          reasonText = '업무 마감으로 자동 취소됨';
        case 'TO_EXPIRED':
          reasonText = '공고 마감으로 자동 취소됨';
        default:
          reasonText = app.conflictingBusiness != null ? '시간 충돌로 자동 취소됨' : '자동으로 취소됨';
      }
      chips.add(_buildChip(icon: Icons.info_outline, label: reasonText, color: AppColors.warning));
    }

    // 취소 칩 (대기중)
    if (app.status == AppStatus.pending) {
      chips.add(_buildChip(
        icon: Icons.close,
        label: '취소',
        color: AppColors.error,
        onTap: _cancellingIds.contains(app.id) ? null : () => _cancelApplication(app.id),
      ));
    }

    // 계약서 칩 (확정 / 계약 대기)
    if (app.status == AppStatus.confirmed || app.status == AppStatus.contractPending) {
      final contract = _contractMap[app.id];
      if (contract != null) {
        switch (contract.status) {
          case ContractStatus.pendingWorker:
            chips.add(_buildChip(
              icon: Icons.draw_outlined,
              label: '서명 필요',
              color: AppColors.warning,
              onTap: () => _openContractSign(contract),
              showArrow: true,
            ));
          case ContractStatus.pendingEmployer:
            chips.add(_buildChip(
              icon: Icons.hourglass_top_outlined,
              label: '사업주 서명 대기',
              color: AppColors.grey500,
            ));
          case ContractStatus.completed:
            chips.add(_buildChip(
              icon: Icons.verified_outlined,
              label: '계약서 완료',
              color: AppColors.success,
            ));
          case ContractStatus.voided:
            chips.add(_buildChip(
              icon: Icons.block_outlined,
              label: '계약서 무효',
              color: AppColors.grey500,
            ));
        }
      }
    }

    // 리뷰 칩 (확정 + 근무 완료)
    if (app.status == AppStatus.confirmed) {
      final rd = _reviewDate(app);
      if (rd != null) {
        if (!rd.isAfter(now)) {
          final review = _reviewMap[app.id];
          if (review != null) {
            chips.add(_buildReviewDoneChip(review));
          } else {
            final monthEnd = DateTime(rd.year, rd.month + 1, 0);
            final withinWindow =
                now.isBefore(monthEnd.add(const Duration(days: 15)));
            if (withinWindow) {
              chips.add(_buildChip(
                icon: Icons.rate_review_outlined,
                label: '리뷰 작성',
                color: Theme.of(context).primaryColor,
                onTap: () => _openReviewDialog(app, rd),
                showArrow: true,
              ));
            }
          }
        }
      }
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      child: Wrap(
        spacing: ResponsiveHelper.spacing(context, 6),
        runSpacing: ResponsiveHelper.spacing(context, 4),
        children: chips,
      ),
    );
  }

  Widget _buildChip({
    required IconData icon,
    required String label,
    required Color color,
    VoidCallback? onTap,
    bool showArrow = false,
  }) {
    final inner = Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 12), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: color)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          if (showArrow) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 2)),
            Icon(Icons.chevron_right,
                size: ResponsiveHelper.iconSize(context, 12), color: color),
          ],
        ],
      ),
    );
    if (onTap == null) return inner;
    return GestureDetector(onTap: onTap, child: inner);
  }

  Widget _buildReviewDoneChip(MonthlyReviewModel review) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey100,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.grey300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...List.generate(
            5,
            (i) => Icon(
              i < review.rating ? Icons.star_rounded : Icons.star_border_rounded,
              size: ResponsiveHelper.iconSize(context, 11),
              color: AppColors.amber,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            review.isPublished ? '공개됨' : '검토 중',
            style: ResponsiveHelper.tinyStyle(
              context,
              color: review.isPublished ? AppColors.successDark : AppColors.grey500,
            ).copyWith(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 장기 공고 퇴사/계약해지 복합 상태 배너
  // ═══════════════════════════════════════════════════════════

  Widget _buildLongTermStatusSection(ApplicationModel app) {
    final resignStatus = app.resignStatus;
    final terminationStatus = app.terminationStatus;

    if (resignStatus == null && terminationStatus == null) {
      return const SizedBox.shrink();
    }

    final banners = <Widget>[];

    // 퇴사 신청 상태
    if (resignStatus != null) {
      final (icon, color, bgColor, label) = switch (resignStatus) {
        'PENDING' => (
            Icons.exit_to_app_outlined,
            AppColors.warningDark,
            AppColors.warningBg,
            app.resignRequestDate != null
                ? '퇴사 신청 중 · 희망일 ${DateFormat('MM.dd').format(app.resignRequestDate!)}'
                : '퇴사 신청 중',
          ),
        'APPROVED' || 'AUTO_APPROVED' => (
            Icons.check_circle_outline,
            AppColors.successDark,
            AppColors.successBg,
            app.actualResignDate != null
                ? '퇴사 확정 · ${DateFormat('MM.dd').format(app.actualResignDate!)}'
                : '퇴사 확정',
          ),
        'REJECTED' => (
            Icons.cancel_outlined,
            AppColors.errorDark,
            AppColors.errorBg,
            app.resignRejectReason?.isNotEmpty == true
                ? '퇴사 신청 거절 · ${app.resignRejectReason}'
                : '퇴사 신청이 거절되었습니다',
          ),
        _ => (
            Icons.info_outline,
            AppColors.grey600,
            AppColors.grey100,
            '퇴사 신청 처리 중',
          ),
      };

      banners.add(
        Container(
          margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(icon, size: ResponsiveHelper.iconSize(context, 14), color: color),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Expanded(
              child: Text(
                label,
                style: ResponsiveHelper.smallStyle(context, color: color)
                    .copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ]),
        ),
      );
    }

    // 계약해지 상태
    if (terminationStatus != null) {
      final (icon, color, bgColor, label) = switch (terminationStatus) {
        'PENDING' => (
            Icons.warning_amber_outlined,
            AppColors.warningDark,
            AppColors.warningBg,
            app.terminationReason?.isNotEmpty == true
                ? '계약해지 요청 수신 · ${app.terminationReason}'
                : '계약해지 요청이 접수되었습니다',
          ),
        'APPROVED' || 'AUTO_APPROVED' => (
            Icons.assignment_turned_in_outlined,
            AppColors.infoDark,
            AppColors.infoBg,
            app.terminationEffectiveDate != null
                ? '계약해지 완료 · ${DateFormat('MM.dd').format(app.terminationEffectiveDate!)}'
                : '계약해지 완료',
          ),
        'REJECTED' => (
            Icons.block_outlined,
            AppColors.grey600,
            AppColors.grey100,
            app.terminationRejectReason?.isNotEmpty == true
                ? '계약해지 거절 · ${app.terminationRejectReason}'
                : '계약해지 거절 처리됨',
          ),
        _ => (
            Icons.info_outline,
            AppColors.grey600,
            AppColors.grey100,
            '계약해지 처리 중',
          ),
      };

      banners.add(
        Container(
          margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            Icon(icon, size: ResponsiveHelper.iconSize(context, 14), color: color),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Expanded(
              child: Text(
                label,
                style: ResponsiveHelper.smallStyle(context, color: color)
                    .copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ]),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: banners,
    );
  }

  // ── 중간정산 요청 버튼 (장기근무 확정 카드) ────────────────────
  Widget _buildInterimSettlementButton(ApplicationModel app) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 6)),
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
        icon: Icon(Icons.account_balance_wallet_outlined,
            size: ResponsiveHelper.iconSize(context, 15)),
        label: Text('중간정산 요청',
            style: ResponsiveHelper.smallStyle(context)),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.tealDark,
          side: BorderSide(color: AppColors.teal),
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
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
    // H-3: 서명 후 계약서만 갱신 — 지원서·TO·리뷰 전체 재로드 불필요
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;
    _contractsLoaded = false; // 재로드 허용
    final updated = await _loadContracts(uid, _applications);
    if (!mounted) return;
    setState(() => _contractMap = {..._contractMap, ...updated});
  }

  Future<void> _openReviewDialog(ApplicationModel app, DateTime reviewDate) async {
    if (_reviewDialogOpenIds.contains(app.id)) return;
    final uid =
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;
    setState(() => _reviewDialogOpenIds.add(app.id));
    try {
      final requestKey = ReviewRequestModel.generateKey(
        businessId: app.businessId,
        workerId: uid,
        year: reviewDate.year,
        month: reviewDate.month,
      );
      // 두 쿼리는 서로 독립적 — 병렬 실행으로 RTT 1회 절약
      ReviewRequestModel? reviewRequest;
      List<AttendanceModel> attendances = [];
      await Future.wait([
        _reviewService.getReviewRequest(requestKey).then((r) => reviewRequest = r),
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

  // ═══════════════════════════════════════════════════════════
  // 상태 정보 헬퍼
  // ═══════════════════════════════════════════════════════════

  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case AppStatus.confirmed:
        return _StatusInfo(
          label: '확정',
          color: AppColors.successDark,
          bgColor: AppColors.successBg,
        );
      case AppStatus.contractPending:
        return _StatusInfo(
          label: '계약 대기',
          color: Theme.of(context).primaryColor,
          bgColor: Theme.of(context).primaryColor.withValues(alpha: 0.08),
        );
      case AppStatus.pending:
        return _StatusInfo(
          label: '대기중',
          color: AppColors.warningDark,
          bgColor: AppColors.warningBg,
        );
      case AppStatus.rejected:
        return _StatusInfo(
          label: '거절',
          color: AppColors.errorDark,
          bgColor: AppColors.errorBg,
        );
      case AppStatus.canceled:
        return _StatusInfo(
          label: '취소',
          color: AppColors.grey600,
          bgColor: AppColors.grey200,
        );
      case AppStatus.autoCanceled:
        return _StatusInfo(
          label: '자동 취소',
          color: AppColors.warningDark,
          bgColor: AppColors.warningBg,
        );
      default:
        return _StatusInfo(
          label: '알 수 없음',
          color: AppColors.grey600,
          bgColor: AppColors.grey200,
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 데이터 클래스
// ═══════════════════════════════════════════════════════════

class _ApplicationWithTO {
  final ApplicationModel application;
  final TOModel? to; // TO 삭제 시 null 가능

  _ApplicationWithTO({
    required this.application,
    this.to,
  });
}

class _StatusInfo {
  final String label;
  final Color color;
  final Color bgColor;

  _StatusInfo({
    required this.label,
    required this.color,
    required this.bgColor,
  });
}
