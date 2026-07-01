import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/core/application_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../models/core/notification_model.dart';
import '../../models/core/monthly_review_model.dart';
import '../../models/core/review_request_model.dart';
import '../../models/core/to_model.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../screens/user/user_contracts_screen.dart';
import '../../screens/common/job_posting_screen.dart';
import '../../services/contract_service.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_review_service.dart';
import '../../widgets/dialogs/business_review_dialog.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/work_type_icon.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_filter_chip.dart';

/// 내 지원 내역 화면 (리팩토링 버전)
class MyApplicationsScreen extends StatefulWidget {
  const MyApplicationsScreen({super.key});

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ContractService _contractService = ContractService();
  final ScrollController _scrollController = ScrollController();

  List<_ApplicationWithTO> _applications = [];
  Map<String, EmploymentContractModel> _contractMap = {};
  Map<String, MonthlyReviewModel?> _reviewMap = {};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDoc;

  String _selectedFilter = 'ALL';
  int _autoLoadCount = 0;
  static const int _maxAutoLoad = 5;

  // 계약서 요청 쿨다운 (앱ID → 마지막 요청 시각)
  final Map<String, DateTime> _lastContractRequestMap = {};
  final Map<String, bool> _isRequestingContract = {};
  final Set<String> _cancellingIds = {};
  static const Duration _contractRequestCooldown = Duration(hours: 24);

  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadApplications();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
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
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) {
      ToastHelper.showError('로그인이 필요합니다.');
      return;
    }

    setState(() {
      _isLoading = true;
      _applications = [];
      _lastDoc = null;
      _hasMore = true;
    });

    try {
      // 만료된 PENDING 자동 처리
      await _firestoreService.autoExpirePendingApplications(uid);

      final page = await _firestoreService.getMyApplicationsPaged(
        uid: uid, pageSize: _pageSize,
      );
      final items = page['items'] as List<ApplicationModel>;
      final appWithTOs = await _attachTOInfo(items);

      // 계약서 · 리뷰 병렬 로드 — 개별 실패가 전체 로드를 막지 않도록 독립 처리
      final contractMap = await _loadContracts(uid, appWithTOs)
          .catchError((_) => <String, EmploymentContractModel>{});
      final reviewMap = await _loadWrittenReviews(uid, appWithTOs)
          .catchError((_) => <String, MonthlyReviewModel?>{});

      if (mounted) {
        setState(() {
          _applications = appWithTOs;
          _contractMap = contractMap;
          _reviewMap = reviewMap;
          _lastDoc = page['lastDoc'] as DocumentSnapshot?;
          _hasMore = page['hasMore'] as bool;
          _isLoading = false;
        });
        _loadContractRequestTimes(appWithTOs.map((a) => a.application.id).toList());
      }
    } catch (e) {
      debugPrint('❌ 지원 내역 로드 실패: $e');
      if (mounted) {
        ToastHelper.showError(_firestoreErrMsg(e, '지원 내역을 불러오는데 실패했습니다.'));
        setState(() => _isLoading = false);
      }
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
    if (_isLoadingMore || !_hasMore || _lastDoc == null) return;
    if (!mounted) return;
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoadingMore = true);
    try {
      final page = await _firestoreService.getMyApplicationsPaged(
        uid: uid, pageSize: _pageSize, startAfter: _lastDoc,
      );
      final items = page['items'] as List<ApplicationModel>;
      final appWithTOs = await _attachTOInfo(items);
      // 신규 확정 지원서에 대한 계약서만 추가 로드
      // Future.wait — 한 쪽 실패 시 다른 쪽 결과 유실; outer catch가 에러 처리하므로 허용
      final moreResults = await Future.wait([
        _loadContracts(uid, appWithTOs),
        _loadWrittenReviews(uid, appWithTOs),
      ]);
      final newContracts = moreResults[0] as Map<String, EmploymentContractModel>;
      final newReviews = moreResults[1] as Map<String, MonthlyReviewModel?>;

      if (mounted) {
        setState(() {
          _applications = [..._applications, ...appWithTOs];
          _contractMap = {..._contractMap, ...newContracts};
          _reviewMap = {..._reviewMap, ...newReviews};
          _lastDoc = page['lastDoc'] as DocumentSnapshot?;
          _hasMore = page['hasMore'] as bool;
          _isLoadingMore = false;
        });
        if (_filteredApplications.isEmpty && _hasMore && !_isLoadingMore &&
            _autoLoadCount < _maxAutoLoad) {
          _autoLoadCount++;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _filteredApplications.isEmpty && _hasMore && !_isLoadingMore) {
              _loadMore();
            }
          });
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
    final toList = await Future.wait(toIds.map((id) => _firestoreService.getTO(id)));
    final toMap = {for (final to in toList.whereType<TOModel>()) to.id: to};
    return apps
        .map((a) => _ApplicationWithTO(
              application: a,
              to: a.toId != null ? toMap[a.toId!] : null, // TO 삭제 시 null로 폴백
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
      return rd.isBefore(DateTime.now());
    }).toList();

    if (relevant.isEmpty) return {};

    final entries = await Future.wait(relevant.map((item) async {
      final app = item.application;
      final rd = _reviewDate(app);
      final key = MonthlyReviewModel.generateKeyForBusiness(
        businessId: app.businessId,
        reviewerId: uid,
        year: rd.year,
        month: rd.month,
      );
      final review = await MonthlyReviewService().getReviewById(key);
      return MapEntry(app.id, review);
    }));

    return Map.fromEntries(entries);
  }

  /// 리뷰 기준일: 단기=근무일, 장기=종료일
  DateTime _reviewDate(ApplicationModel app) {
    if (app.isLongTermApplication) {
      return app.actualResignDate ?? app.workEndDate ?? app.workDate;
    }
    return app.workDate;
  }

  List<_ApplicationWithTO> get _filteredApplications {
    if (_selectedFilter == 'ALL') return _applications;
    return _applications.where((item) {
      final status = item.application.status;
      if (_selectedFilter == AppStatus.canceled) {
        return AppStatus.inactiveStates.contains(status) && status != AppStatus.rejected;
      }
      if (_selectedFilter == AppStatus.confirmed) {
        return AppStatus.confirmedStatuses.contains(status);
      }
      return status == _selectedFilter;
    }).toList();
  }

  // ── 계약서 요청 쿨다운 ──

  Future<void> _loadContractRequestTimes(List<String> appIds) async {
    final prefs = await SharedPreferences.getInstance();
    final Map<String, DateTime> map = {};
    for (final id in appIds) {
      final ts = prefs.getInt('contract_req_$id');
      if (ts != null) {
        map[id] = DateTime.fromMillisecondsSinceEpoch(ts);
      }
    }
    if (mounted) setState(() => _lastContractRequestMap.addAll(map));
  }

  Future<void> _requestContract(ApplicationModel app) async {
    if (_isRequestingContract[app.id] == true) return;
    // W05-046: async gap 이전이라도 dispose 직후 호출될 수 있으므로 mounted 체크 필수
    if (!mounted) return;
    setState(() => _isRequestingContract[app.id] = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      // W05-047: currentUser가 null인 비로그인 상태에서는 알림 발송 불가 — 조기 반환
      final currentUser = userProvider.currentUser;
      if (currentUser == null) {
        ToastHelper.showError('로그인이 필요합니다.');
        return;
      }
      final workerName = currentUser.name;

      // FirebaseFirestore.instance 직접 사용 — firestoreService에 ownerId 단독 조회 메서드가 없어
      //           businesses 컬렉션을 직접 읽는다. 추후 firestoreService.getBusinessOwnerId() 추가 시 교체.
      final bizDoc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(app.businessId)
          .get();
      if (!mounted) return;
      final ownerId = bizDoc.data()?['ownerId'] as String?;
      if (ownerId == null || ownerId.isEmpty) {
        ToastHelper.showError('사업주 정보를 찾을 수 없습니다.');
        return;
      }

      final notification = NotificationModel.createContractRequested(
        userId: ownerId,
        workerName: workerName,
        businessId: app.businessId,
        applicationId: app.id,
      );
      await _firestoreService.createNotification(notification);
      if (!mounted) return;

      // 쿨다운 저장
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('contract_req_${app.id}', now.millisecondsSinceEpoch);
      if (!mounted) return;

      setState(() => _lastContractRequestMap[app.id] = now);
      ToastHelper.showSuccess('계약서 발송을 요청했습니다.');
    } catch (e) {
      debugPrint('❌ 계약서 요청 실패: $e');
      if (!mounted) return;
      ToastHelper.showError(_firestoreErrMsg(e, '계약서 요청에 실패했습니다. 다시 시도해 주세요.'));
    } finally {
      if (mounted) setState(() => _isRequestingContract[app.id] = false);
    }
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
        message: '정말 지원을 취소하시겠습니까?',
      );

      if (!confirmed || !mounted) return;

      // cancelApplication 내부에서 이미 상태에 맞는 토스트(showSuccess/showInfo/showError)를
      // 표시하므로, 여기서는 추가 메시지 없이 화면 갱신만 수행한다.
      // (REJECTED·이미취소 상태에서 success=true가 반환될 때 중복 토스트 방지)
      final success = await _firestoreService.cancelApplication(applicationId, uid);
      if (!mounted) return;
      if (success) {
        _loadApplications();
      } else {
        ToastHelper.showError('취소에 실패했습니다.');
      }
    } finally {
      if (mounted) setState(() => _cancellingIds.remove(applicationId));
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '내 지원 내역',
      onRefresh: _loadApplications,
      body: Column(
        children: [
          _buildFilterSection(),
          Expanded(
            child: _isLoading
                ? const LoadingWidget(message: '지원 내역을 불러오는 중...')
                : _filteredApplications.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadApplications,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: ResponsiveHelper.listPadding(context),
                          // +1 for bottom loading indicator
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
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 필터 섹션
  // ═══════════════════════════════════════════════════════════

  Widget _buildFilterSection() {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.grey200, width: 1),
        ),
      ),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
          ),
          child: Row(
            children: [
              _buildFilterChip('전체', 'ALL', Icons.list_alt, AppColors.info),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('대기중', AppStatus.pending, Icons.schedule, AppColors.warning),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('확정', AppStatus.confirmed, Icons.check_circle, AppColors.success),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('거절', AppStatus.rejected, Icons.cancel, AppColors.error),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('취소', AppStatus.canceled, Icons.remove_circle_outline, AppColors.grey500),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, IconData icon, Color color) {
    return AppFilterChip(
      label: label,
      isSelected: _selectedFilter == value,
      onTap: () {
        setState(() { _selectedFilter = value; _autoLoadCount = 0; });
        // 탭 필터는 클라이언트 필터 — 탭 변경 시 서버 재조회 없이 로드된 데이터 내에서만 필터링
        // _loadMore 내 _lastDoc 가드로 커서 소실 방지 처리됨
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _filteredApplications.isEmpty && _hasMore && !_isLoadingMore) {
            _loadMore();
          }
        });
      },
      color: color,
      leadingIcon: icon,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 빈 상태
  // ═══════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return AppEmptyState(
      icon: Icons.assignment_outlined,
      title: _selectedFilter == 'ALL' ? '지원 내역이 없습니다' : '해당 상태의 지원이 없습니다',
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
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
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
          ),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 14),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1줄: 사업장명 + 상태 배지
                _buildCardHeader(app, to, statusInfo),

                SizedBox(height: ResponsiveHelper.spacing(context, 4)),

                // 2줄: TO 제목
                Text(
                  to.title,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 6)),

                // 3줄: 근무일 · 근무시간
                _buildDateTimeRow(app, to),

                SizedBox(height: ResponsiveHelper.spacing(context, 4)),

                // 4줄: 업무유형 · 급여
                _buildWorkWageRow(app),

                // 지원일
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '지원일: ${DateFormat('yyyy.MM.dd HH:mm').format(app.appliedAt)}',
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
                ),
                
                // 자동 취소인 경우 취소 사유 표시
                // [H-001 수정] conflictingBusiness 유무와 관계없이 항상 표시
                // cancelReason(마감·슬롯 만료)도 UI에서 전달
                if (app.status == AppStatus.autoCanceled)
                  _buildAutoCanceledInfo(app),

                // 대기 중인 경우 취소 버튼
                // [A08/A09 설계] CONTRACT_PENDING·CONFIRMED 상태에서는 취소 버튼 미표시.
                // cancelApplication()에서 confirmedStatuses 포함 시 에러 반환하므로 서버도 차단됨.
                // 계약 서명 대기/완료 후 취소는 관리자에게 문의해야 한다(의도된 설계).
                if (app.status == AppStatus.pending)
                  _buildCancelButton(app),

                // 확정/계약대기인 경우 계약서 섹션
                if (app.status == AppStatus.confirmed ||
                    app.status == AppStatus.contractPending)
                  _buildContractSection(app),

                // 장기 공고: 퇴사/계약해지 복합 상태 배너
                if (app.isLongTermApplication)
                  _buildLongTermStatusSection(app),

                // 과거 확정 근무 → 리뷰 섹션
                _buildReviewSection(app),
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
          size: ResponsiveHelper.iconSize(context, 16),
          color: AppColors.grey600,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Expanded(
          child: Text(
            to.businessName,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _buildStatusBadge(statusInfo),
      ],
    );
  }

  Widget _buildDateTimeRow(ApplicationModel app, TOModel to) {
    final timeDisplay = (app.startTime.isNotEmpty && app.endTime.isNotEmpty)
        ? '${app.startTime} ~ ${app.endTime}'
        : '--:-- ~ --:--';

    // 장기 근무: 희망 시작일 또는 TO 근무 기간 표시
    final String dateDisplay;
    if (app.isLongTermApplication) {
      final start = app.desiredStartDate ?? to.startDate ?? app.workDate;
      final end = to.endDate;
      dateDisplay = end != null
          ? '${FormatHelper.formatDateCompact(start)} ~ ${FormatHelper.formatDateCompact(end)}'
          : FormatHelper.formatDateLong(start);
    } else {
      dateDisplay = FormatHelper.formatDateLong(app.workDate);
    }

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
        if (!app.isLongTermApplication) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Icon(
            Icons.access_time,
            size: ResponsiveHelper.iconSize(context, 14),
            color: AppColors.grey500,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            timeDisplay,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
          ),
        ],
      ],
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
            size: ResponsiveHelper.iconSize(context, 14),
            containerSize: ResponsiveHelper.spacing(context, 24),
          )
        else
          Icon(
            Icons.work_outline,
            size: ResponsiveHelper.iconSize(context, 14),
            color: AppColors.grey500,
          ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
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
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: statusInfo.bgColor,
        borderRadius: BorderRadius.circular(8),
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

  /// 자동 취소 충돌 정보 (간소화)
  Widget _buildAutoCanceledInfo(ApplicationModel app) {
    // [H-001 수정] cancelReason 기반 안내 문구 분기
    // conflictingBusiness가 없는 마감·슬롯 만료 케이스도 사유 전달
    final String reasonText;
    final bool hasConflict = app.conflictingBusiness != null;
    switch (app.cancelReason) {
      case 'SLOT_WORK_DETAIL_EXPIRED':
        reasonText = '슬롯 업무 마감으로 자동 취소됨';
      case 'WORK_DETAIL_EXPIRED':
        reasonText = '업무 마감으로 자동 취소됨';
      case 'TO_EXPIRED':
        reasonText = '공고 마감으로 자동 취소됨';
      default:
        reasonText = hasConflict ? '시간 충돌로 자동 취소됨' : '자동으로 취소되었습니다';
    }

    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
      padding: ResponsiveHelper.listPadding(context),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warningLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.warningDark,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                reasonText,
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: AppColors.warningDark,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          // 시간 충돌인 경우에만 충돌 공고 정보 표시
          if (hasConflict) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Row(
              children: [
                Icon(
                  Icons.business,
                  size: ResponsiveHelper.iconSize(context, 12),
                  color: AppColors.grey600,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Expanded(
                  child: Text(
                    [app.conflictingBusiness, app.conflictingTime]
                        .where((s) => s != null && s.isNotEmpty)
                        .join(' · '),
                    style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey700),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 6),
                    vertical: ResponsiveHelper.spacing(context, 2),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.successBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '확정됨',
                    style: ResponsiveHelper.tinyStyle(
                      context,
                      color: AppColors.successDark,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 취소 버튼
  Widget _buildCancelButton(ApplicationModel app) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _cancelApplication(app.id),
        icon: Icon(
          Icons.close,
          size: ResponsiveHelper.iconSize(context, 16),
        ),
        label: Text(
          '지원 취소',
          style: ResponsiveHelper.smallStyle(context),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
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

  /// 계약서 섹션 (확정된 지원서용)
  Widget _buildContractSection(ApplicationModel app) {
    final contract = _contractMap[app.id];

    // 계약서 미생성 + 계약 대기 → 계약서 요청하기 버튼
    if (contract == null && app.status == AppStatus.contractPending) {
      final lastReq = _lastContractRequestMap[app.id];
      final cooldownActive = lastReq != null &&
          DateTime.now().difference(lastReq) < _contractRequestCooldown;
      final isRequesting = _isRequestingContract[app.id] == true;

      return Container(
        margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: (cooldownActive || isRequesting)
              ? null
              : () => _requestContract(app),
          icon: isRequesting
              ? SizedBox(
                  width: ResponsiveHelper.iconSize(context, 14),
                  height: ResponsiveHelper.iconSize(context, 14),
                  child: const CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.mail_outline, size: ResponsiveHelper.iconSize(context, 16)),
          label: Text(
            cooldownActive
                ? '요청 완료 (24시간 내 재요청 불가)'
                : '계약서 요청하기',
            style: ResponsiveHelper.smallStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: Theme.of(context).primaryColor,
            side: BorderSide(
              color: cooldownActive
                  ? AppColors.grey300
                  : Theme.of(context).primaryColor,
            ),
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      );
    }

    if (contract == null) return const SizedBox.shrink();

    if (contract.status == ContractStatus.pendingWorker) {
      return Container(
        margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _openContractSign(contract),
          icon: Icon(Icons.draw, size: ResponsiveHelper.iconSize(context, 16)),
          label: Text(
            '근로계약서 서명하기',
            style: ResponsiveHelper.smallStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
        ),
      );
    }

    if (contract.status == ContractStatus.completed) {
      return Column(
        children: [
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.verified,
                    size: ResponsiveHelper.iconSize(context, 14),
                    color: AppColors.successDark),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Expanded(
                  child: Text(
                    '근로계약서 서명 완료',
                    style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.successDark)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const UserContractsScreen()),
                  ),
                  child: Text(
                    '전체 보기',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.infoDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (contract.status == ContractStatus.pendingEmployer) {
      return Container(
        margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 10),
        ),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_top, size: ResponsiveHelper.iconSize(context, 14), color: AppColors.warningDark),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              '사업주 서명 대기 중',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
            ),
          ],
        ),
      );
    }

    if (contract.status == ContractStatus.voided) {
      return Container(
        margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 10),
        ),
        decoration: BoxDecoration(
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.grey300),
        ),
        child: Row(
          children: [
            Icon(Icons.block_outlined,
                size: ResponsiveHelper.iconSize(context, 14),
                color: AppColors.grey500),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Expanded(
              child: Text(
                '계약서가 무효 처리되었습니다. 사업주에게 문의하세요.',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey500),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
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

  Future<void> _openContractSign(EmploymentContractModel contract) async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContractSignScreen(contract: contract, role: 'worker'),
      ),
    );
    // 서명 완료 후 화면 갱신
    if (mounted) _loadApplications();
  }

  // ═══════════════════════════════════════════════════════════
  // 리뷰 섹션
  // ═══════════════════════════════════════════════════════════

  Widget _buildReviewSection(ApplicationModel app) {
    if (app.status != AppStatus.confirmed) return const SizedBox.shrink();
    final rd = _reviewDate(app);
    if (rd.isAfter(DateTime.now())) return const SizedBox.shrink();

    final review = _reviewMap[app.id];
    if (review != null) return _buildWrittenReviewBadge(review);

    final withinWindow = DateTime.now().isBefore(rd.add(const Duration(days: 14)));
    if (withinWindow) return _buildWriteReviewButton(app, rd);

    return const SizedBox.shrink();
  }

  Widget _buildWrittenReviewBadge(MonthlyReviewModel review) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Row(
        children: [
          Icon(Icons.rate_review,
              size: ResponsiveHelper.iconSize(context, 14),
              color: AppColors.grey500),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text(
            '내 리뷰 작성 완료',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600)
                .copyWith(fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(
              5,
              (i) => Icon(
                i < review.rating ? Icons.star_rounded : Icons.star_border_rounded,
                size: ResponsiveHelper.iconSize(context, 12),
                color: AppColors.amber,
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 6),
              vertical: ResponsiveHelper.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: review.isPublished ? AppColors.successBg : AppColors.grey100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              review.isPublished ? '공개됨' : '검토 중',
              style: ResponsiveHelper.tinyStyle(
                context,
                color: review.isPublished ? AppColors.successDark : AppColors.grey500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWriteReviewButton(ApplicationModel app, DateTime reviewDate) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _openReviewDialog(app, reviewDate),
        icon: Icon(Icons.rate_review_outlined,
            size: ResponsiveHelper.iconSize(context, 16)),
        label: Text('사업장 리뷰 작성',
            style: ResponsiveHelper.smallStyle(context)),
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).primaryColor,
          side: BorderSide(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.5)),
          padding:
              EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 8)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
    );
  }

  Future<void> _openReviewDialog(ApplicationModel app, DateTime reviewDate) async {
    final uid =
        Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;

    final requestKey = ReviewRequestModel.generateKey(
      businessId: app.businessId,
      workerId: uid,
      year: reviewDate.year,
      month: reviewDate.month,
    );
    final reviewRequest =
        await MonthlyReviewService().getReviewRequest(requestKey);
    if (!mounted) return;

    final result = await showBusinessReviewDialog(
      context,
      reviewerId: uid,
      businessId: app.businessId,
      businessName: app.businessName,
      reviewYear: reviewDate.year,
      reviewMonth: reviewDate.month,
      workDaysInMonth: 1,
      requestId: reviewRequest?.id,
    );

    if (result == true && mounted) {
      final key = MonthlyReviewModel.generateKeyForBusiness(
        businessId: app.businessId,
        reviewerId: uid,
        year: reviewDate.year,
        month: reviewDate.month,
      );
      final review = await MonthlyReviewService().getReviewById(key);
      if (!mounted) return;
      setState(() => _reviewMap[app.id] = review);
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
