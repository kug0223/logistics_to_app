import 'package:flutter/material.dart';
import 'my_applications_reads.dart';
import 'dart:async' show unawaited;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/core/application_model.dart';
import '../../models/core/business_model.dart' show AttendanceRules;
import '../../utils/attendance_policy_disclosure.dart';
import '../../utils/text_layout.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../models/core/monthly_review_model.dart';
import '../../models/core/review_request_model.dart';
import '../../models/core/to_model.dart';
import '../../models/ui/invite_capacity_state.dart';
import '../../models/ui/invite_accept_readiness.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../screens/user/interim_settlement_request_screen.dart';
import '../../widgets/dialogs/long_term_work_management_dialog.dart';
import '../../screens/common/job_posting_screen.dart';
import '../../services/contract_service.dart';
import '../../services/firestore_service.dart';
import '../../services/monthly_review_service.dart';
import '../../widgets/dialogs/business_review_dialog.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/attendance_rule_guide_view.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/skeleton_widget.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../widgets/dialogs/apply/document_access_consent.dart';
import 'apply_prerequisites_screen.dart';
import '../../utils/period_revision_disclosure.dart';
import '../../widgets/user/period_revision_notice_card.dart';
import '../../utils/format_helper.dart';
import '../../theme/app_colors.dart';
import '../../theme/light_app_bar_style.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/responsive_helper.dart';
import '../../models/core/confirmed_reassignment_proposal.dart';
import '../../services/confirmed_reassignment_service.dart';
import '../../widgets/dialogs/confirmed_reassignment_sheet.dart';

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

  /// [CROSS-DOMAIN-R5.1G.1] 알림이 지목한 지원서.
  ///
  /// `applicationConfirmed` / `applicationRejected` 알림은 특정 지원서 하나에
  /// 대한 소식인데, 여태 목록만 열어 어느 건인지 말하지 않았다(N3 미충족).
  /// 여기에 id를 주면 **현재 데이터로** 그 건을 찾아 카드 탭과 같은 화면을
  /// 연다. payload에 담긴 과거 상태는 쓰지 않는다 — 열리는 것은 지금 읽은
  /// Application이다. null이면 예전처럼 목록만 연다(legacy payload).
  final String? focusApplicationId;

  /// [R7-P2-2 후속 P22-M] 목록을 만들 때의 읽기 경계. production 은 null.
  final MyApplicationsReads? reads;

  /// [E1-MYA] 상태 판정이 보는 시계. production 은 null().
  ///   확정 근무가 '지났는가' 는 이 한 값으로 갈리므로 테스트가 쥘 수 있어야 한다.
  final DateTime Function()? clock;

  const MyApplicationsScreen({
    super.key,
    this.initialTabIndex = 0,
    this.onBack,
    this.focusApplicationId,
    this.reads,
    this.clock,
  });

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen> {
  DateTime _now() => (widget.clock ?? DateTime.now)();
  /// [R5.3E.2] 나에게 온 진행 중인 근무 변경 제안.
  List<ConfirmedReassignmentProposal> _reassignProposals = const [];
  // ─── 포맷터 캐싱 ──────────────────────────────────────────────────────────
  // [R1.2] 근무 날짜(workDate)는 FormatHelper의 KST 변환을 쓴다 — 여기에
  //   DateFormat을 다시 만들지 않는다.
  // [ISG2] 초대 만료 '시각' 포맷터(`MM.dd HH:mm`)도 지웠다. 이 화면이
  //   직접 가지고 있으면 기기 시간대 성분이 찍힌다 —
  //   `FormatHelper.formatKstMonthDayTime` 한 곳이 KST 로 고정한다.

  // ─── 서비스 ───────────────────────────────────────────────────────────────
  final FirestoreService    _firestoreService = FirestoreService();
  final ContractService     _contractService  = ContractService();
  late final MyApplicationsReads _reads =
      widget.reads ?? MyApplicationsReads.of(_firestoreService, _contractService);
  final MonthlyReviewService _reviewService   = MonthlyReviewService();
  final ScrollController    _scrollController = ScrollController();

  // ─── 데이터 상태 (변경 없음) ───────────────────────────────────────────────
  List<_ApplicationWithTO>              _applications  = [];
  Map<String, EmploymentContractModel>  _contractMap   = {};
  Map<String, MonthlyReviewModel?>      _reviewMap     = {};
  final Map<String, TOModel>            _toCache       = {};

  /// [SYSTEM-INTEGRATION-POSTING-1] 조회에 실패한 공고 id — 삭제된 공고와 다르다.
  final Set<String>                     _toLoadFailedIds = {};
  final Map<String, MonthlyReviewModel?> _reviewKeyCache = {};
  bool _contractsLoaded = false;

  /// [E1-MYA] 확정 근무가 실제로 어떻게 끝났는지 — applicationId 로 건다.
  ///
  ///   키는 출퇴근 화면·홈과 **같은 것**(`attendance.applicationId`)이다.
  ///   새 식별자를 만들지 않는다.
  final Map<String, AttendanceModel> _attendanceByApp = {};

  /// 이미 읽은 (year, month) — 같은 달을 두 번 읽지 않는다.
  final Set<String> _attendanceMonths = {};

  /// [ERROR ≠ ZERO] 근태를 **못 읽었다**. "근무 기록이 없다"와 다르다.
  ///   못 읽었으면 완료도 노쇼도 말하지 않는다.
  bool _attendanceFailed = false;

  /// [R8-P7.3] 계약 조회가 실패했다 — "계약이 아직 없다"와 다른 상태다.
  ///   실패를 빈 맵으로 두면 화면이 "관리자가 계약서를 준비 중"이라고
  ///   단정하고 서명 버튼을 숨긴다. 그 둘을 갈라 놓는다.
  bool _contractsFailed = false;

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
  // [INVITE-PREACCEPT] 서류 열람 동의 진행 중인 초대.
  final Set<String> _consentingIds        = {};
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
      // [R5.3E.2] 지원서 목록과 독립이다 — 제안은 별도 entity이고,
      //   Application 목록에는 나타나지 않는다(아직 좌석을 잡지 않았다).
      _loadReassignProposals();
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
      _contractsFailed = false;
      _toCache.clear();
      _reviewKeyCache.clear();
      _cachedFiltered = null;
      // [ATTENDANCE-SCREEN-REFRESH] 전체 다시 읽기(새로고침·재시도·복귀)는 근태도 다시
      //   읽는다. 월 키를 한 번 넣으면 비우지 않아, 출근한 뒤 새로고침해도 '오늘 근무
      //   예정이에요'가 남았다(DEVICE 10/20 12:38, 근태 조회 0). 실패 표시도 함께
      //   되돌린다 — 예전에는 한 번 실패하면 '다시 시도' 뒤에도 영구히 실패였다.
      //   다음 페이지 로드(_loadMore)는 이 집합을 그대로 써서 같은 달을 다시 읽지 않는다.
      _attendanceMonths.clear();
      _attendanceByApp.clear();
      _attendanceFailed = false;
    });

    try {
      unawaited(_reads.autoExpirePending(uid).catchError((e) {
        debugPrint('⚠️ autoExpirePendingApplications 실패 (무시): $e');
      }));

      final page = await _reads.myApplicationsPaged(
        uid: uid, pageSize: _pageSize,
      );
      final items      = page['items'] as List<ApplicationModel>;
      final appWithTOs = await _attachTOInfo(items);

      final initResults = await Future.wait([
        // 계약 조회가 실패해도 지원 목록 자체는 유효하다 — 전체를 ERROR 로
        // 만들지 않는다. 대신 실패했다는 사실을 남겨 "계약 없음"과 구분한다.
        _loadContracts(uid, appWithTOs).catchError((e) {
          debugPrint('⚠️ 계약 조회 실패 (목록은 유지): $e');
          _contractsFailed = true;
          return <String, EmploymentContractModel>{};
        }),
        _loadWrittenReviews(uid, appWithTOs).catchError((_) => <String, MonthlyReviewModel?>{}),
        // [E1-MYA] 근태는 목록과 **같은 왕복**에 합류한다. 실패해도 목록은
        //   그대로 그리고, 실패했다는 사실만 남겨 완료 단정을 막는다.
        _loadAttendances(uid, appWithTOs),
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
        // [CROSS-DOMAIN-R5.1G.1] 지목된 지원서가 있으면 지금 읽은 데이터로 연다.
        unawaited(_focusRequestedApplication());
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

  /// [CROSS-DOMAIN-R5.1G.1] 알림이 지목한 지원서를 **현재 상태로** 연다.
  ///
  ///   · 첫 로드 한 번만 동작한다(뒤로 돌아온 뒤 다시 열리지 않는다).
  ///   · 방금 읽은 목록에서 id로 찾는다 — payload의 과거 상태를 쓰지 않는다.
  ///   · 목록은 페이지 단위라 첫 페이지에 없을 수 있다. 그때는 그 문서 하나만
  ///     읽고, **본인 소유인지 확인한 뒤** 연다. 남의 지원서 id를 들고 와도
  ///     열리지 않는다(서버 규칙과 이중 방어).
  ///   · 찾지 못하면 조용히 목록만 두지 않고 이유를 말한다.
  bool _focusHandled = false;

  Future<void> _focusRequestedApplication() async {
    final wanted = widget.focusApplicationId;
    if (wanted == null || wanted.isEmpty || _focusHandled) return;
    _focusHandled = true;

    _ApplicationWithTO? hit;
    for (final e in _applications) {
      if (e.application.id == wanted) { hit = e; break; }
    }

    if (hit == null) {
      // 첫 페이지 밖일 수 있다 — 그 한 건만 확인한다.
      final uid = context.read<UserProvider>().currentUser?.uid;
      try {
        final one = await _firestoreService.getApplicationOnce(wanted);
        if (!mounted) return;
        if (one == null || uid == null || one.uid != uid) {
          ToastHelper.showWarning('지원 정보를 찾을 수 없습니다.');
          return;
        }
        final withTO = await _attachTOInfo([one]);
        if (!mounted || withTO.isEmpty) {
          if (mounted) ToastHelper.showWarning('지원 정보를 찾을 수 없습니다.');
          return;
        }
        hit = withTO.first;
      } catch (e) {
        debugPrint('⚠️ [R5.1G.1] 지목된 지원서 조회 실패: $e');
        if (mounted) ToastHelper.showError('지원 정보를 불러오지 못했습니다.');
        return;
      }
    }

    if (!mounted) return;
    final to = hit.to;
    final app = hit.application;
    // [CROSS-DOMAIN-R5.3D] 공고가 사라졌다고 **초대까지** 없어지지 않는다.
    //   약속은 Application에 남아 있고 근로자는 그 조건을 보고 답할 수 있어야
    //   한다. 상세 화면이 공고 없이도 초대 조건을 보여주는 fallback을 갖는다.
    //   초대가 아닌 건은 지금처럼 목록의 삭제 카드가 canonical 표현이다.
    if (to == null || to.isSoftDeleted) {
      if (app.status != 'INVITED') {
        ToastHelper.showWarning('해당 공고가 삭제되어 상세를 열 수 없습니다.');
        return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => JobPostingScreen(
            toId: app.toId,
            myApplication: app,
            myContract: _contractMap[app.id],
          ),
        ),
      ).then((changed) {
        if (changed == true && mounted) _loadApplications();
      });
      return;
    }
    // 카드 탭과 **같은** 목적지 — 새 상세 화면을 만들지 않는다.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JobPostingScreen(
          to: to,
          workDetails: to.workDetails,
          myApplication: app,
          myContract: _contractMap[app.id],
        ),
      ),
    ).then((changed) {
      if (changed == true && mounted) _loadApplications();
    });
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
      final page = await _reads.myApplicationsPaged(
        uid: uid, pageSize: _pageSize, startAfterDocId: _lastDocId,
      );
      final items      = page['items'] as List<ApplicationModel>;
      final appWithTOs = await _attachTOInfo(items);
      final moreResults = await Future.wait([
        // [R8-P7.3] 계약 조회 실패가 다음 페이지 전체를 날리지 않게 한다.
        //   실패 사실만 남기고 목록은 이어 붙인다.
        _contractsLoaded
            ? Future.value(<String, EmploymentContractModel>{})
            : _loadContracts(uid, appWithTOs).catchError((e) {
                debugPrint('⚠️ 계약 조회 실패 (목록은 유지): $e');
                _contractsFailed = true;
                return <String, EmploymentContractModel>{};
              }),
        _loadWrittenReviews(uid, appWithTOs),
        // [E1-MYA] 다음 페이지의 지난 근무도 근태를 보고 말해야 한다.
        //   이미 읽은 달은 건너뛰므로 보통 추가 왕복이 없다.
        _loadAttendances(uid, appWithTOs),
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
      // [SYSTEM-INTEGRATION-POSTING-1] 못 읽은 공고를 '삭제된 공고'로 말하지 않는다.
      //   근로자에게는 자기 약속이 사라진 것처럼 읽힌다.
      final fetched = await Future.wait(
          uncachedIds.map((id) => _reads.toOrFailure(id)));
      for (var i = 0; i < uncachedIds.length; i++) {
        final r = fetched[i];
        if (r.to != null) {
          _toCache[r.to!.id] = r.to!;
          _toLoadFailedIds.remove(uncachedIds[i]);
        } else if (r.failed) {
          _toLoadFailedIds.add(uncachedIds[i]);
        } else {
          _toLoadFailedIds.remove(uncachedIds[i]);
        }
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
    final contracts = await _reads.contractsByWorker(uid);
    final result = <String, EmploymentContractModel>{};
    for (final c in contracts) {
      final ids = c.applicationIds.isNotEmpty ? c.applicationIds : [c.applicationId];
      for (final id in ids) {
        if (id.isNotEmpty) result[id] = c;
      }
    }
    _contractsLoaded = true;
    _contractsFailed = false;
    return result;
  }

  /// [E1-MYA] 확정 근무의 **실제 결말**을 읽는다.
  ///
  ///   읽는 달은 "판정이 필요한 지원서"의 달뿐이다 — 미래 근무는 완료를
  ///   주장할 일이 없으므로 제외한다. QA 목록 8건 기준 달은 하나였다.
  ///   목록 전체에 대한 지원서별 개별 조회(N+1)는 하지 않는다.
  ///
  ///   한 달이라도 실패하면 `_attendanceFailed` 를 세운다 — 부분 결과로
  ///   "이 근무는 기록이 없다"고 말하면 안 되기 때문이다.
  Future<void> _loadAttendances(
      String uid, List<_ApplicationWithTO> items) async {
    final today = FormatHelper.toKstDate(_now());
    final months = <String, DateTime>{};
    for (final e in items) {
      final app = e.application;
      if (!AppStatus.confirmedStatuses.contains(app.status)) continue;
      final rd = _reviewDate(app);
      if (rd == null) continue;
      final d = FormatHelper.toKstDate(rd);
      if (d.isAfter(today)) continue; // 아직 오지 않은 근무는 판정 대상이 아니다
      months['${d.year}-${d.month}'] = d;
    }
    if (months.isEmpty) return;

    for (final entry in months.entries) {
      if (_attendanceMonths.contains(entry.key)) continue;
      try {
        final list = await _reads.monthlyAttendances(
          userId: uid, year: entry.value.year, month: entry.value.month,
        );
        for (final att in list) {
          if (att.userId != uid) continue;      // self-uid 계약을 화면에서도 지킨다
          if (att.applicationId.isEmpty) continue;
          _attendanceByApp[att.applicationId] = att;
        }
        _attendanceMonths.add(entry.key);
      } catch (e) {
        debugPrint('⚠️ 근태 조회 실패(${entry.key}): $e');
        _attendanceFailed = true;
      }
    }
  }

  /// [E1-MYA] 그 지원서의 근태. 못 읽었으면 **null 이 아니라 UNKNOWN** 이므로
  ///   호출부가 `_attendanceFailed` 를 먼저 본다.
  AttendanceModel? _attendanceOf(ApplicationModel app) =>
      _attendanceByApp[app.id];

  // ── [DEVICE-MISMATCH-FIX] 근태 결말이 지원서 상태보다 먼저다 ────────────
  static const _missedShiftText = Text(
    '근무 시간이 지났어요 · 출근 기록이 없어요',
    style: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.warningDark),
  );
  static const _settlingText = Text(
    '근무가 끝났어요 · 정산 중',
    style: TextStyle(fontSize: 13, color: AppColors.infoDark),
  );

  /// 노쇼·결근으로 마감된 근무의 상태 배지. 그 외에는 null(지원서 상태를 쓴다).
  _StatusInfo? _attendanceStatusInfo(ApplicationModel app) {
    if (!AppStatus.confirmedStatuses.contains(app.status)) return null;
    final att = _attendanceOf(app);
    if (att == null) return null;
    if (att.isNoShow) {
      return const _StatusInfo(
          label: '노쇼', color: AppColors.errorDark, bgColor: AppColors.errorBg);
    }
    if (att.isAbsent) {
      return const _StatusInfo(
          label: '결근',
          color: AppColors.warningDark,
          bgColor: AppColors.warningBg);
    }
    return null;
  }

  /// 오늘이거나 지난 근무의 **근태 결말**. 결말을 말할 근거가 없으면 null —
  ///   호출부(계약 진행 중)가 원래 문구로 이어간다.
  ///
  ///   근태를 못 읽었으면(ERROR) 결말을 지어내지 않고 null 을 돌려준다.
  Widget? _pastShiftOutcome(ApplicationModel app, {required DateTime now}) {
    final rd = _reviewDate(app);
    if (rd == null) return null;
    if (FormatHelper.toKstDate(rd).isAfter(FormatHelper.toKstDate(now))) {
      return null;
    }
    final att = _attendanceOf(app);
    if (att == null) {
      if (_attendanceFailed) return null;
      return app.hasShiftEndedAt(now) ? _missedShiftText : null;
    }
    if (att.isNoShow) {
      return const Text('노쇼 처리됐어요',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.errorDark));
    }
    if (att.isAbsent) {
      return const Text('결근 처리됐어요',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.warningDark));
    }
    if (!att.hasCheckedIn) {
      return app.hasShiftEndedAt(now) ? _missedShiftText : null;
    }
    if (!att.hasCheckedOut) {
      return const Text('근무 중이에요',
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: AppColors.infoDark));
    }
    if (att.isWageConfirmed || att.isWageTransferred) {
      return const Text('근무 완료',
          style: TextStyle(fontSize: 13, color: AppColors.grey600));
    }
    return _settlingText;
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
        uncachedKeys.map((key) => _reads.reviewById(key)),
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
              // [E2-APPBAR-ON-LIGHT] foregroundColor 만으로는 테마의 흰
              //   titleTextStyle·iconTheme 를 못 이긴다 — 제목·뒤로가기가 사라졌다.
              titleTextStyle: LightAppBarStyle.title(context),
              iconTheme: LightAppBarStyle.iconTheme,
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
                // [DU462] B(320 · 2.0)에서 '일자 / 리가'로 음절이 끊겼다 — 낱말 사이에서만 줄바꿈(읽기는 원문).
                Text(
                  TextLayout.keepWords('아직 지원한 일자리가 없어요'),
                  semanticsLabel: '아직 지원한 일자리가 없어요',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.grey700,
                  ),
                ),
                const SizedBox(height: 10),
                // [DU462] B 에서 '선 / 택하고'로 끊겼다 — 줄바꿈 문자는 두고 낱말 사이에서만(TextLayout.phrases).
                Text(
                  TextLayout.phrases('일하고 싶은 날짜를 선택하고\n나에게 맞는 일자리를 찾아보세요.'),
                  semanticsLabel: '일하고 싶은 날짜를 선택하고\n나에게 맞는 일자리를 찾아보세요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    // [DU461] 빈 상태 부제 grey500(2.68) → textTertiary(AppEmptyState 기본 부제 · DU248).
                    color: AppColors.textTertiary,
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
    // [DEVICE-MISMATCH-FIX] 근태가 노쇼·결근으로 마감된 근무는 지원서 상태
    //   (계약 진행 중·확정)보다 그 결말을 먼저 말한다.
    final statusInfo = _attendanceStatusInfo(app) ??
        _statusInfo(app.status, app: app);
    final now        = _now();

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

                // [CROSS-DOMAIN-R5.3E.2] 이 확정에 근무 변경 제안이 와 있는가.
                //   확정 표시는 그대로 둔다 — 아직 바뀐 것이 없기 때문이다.
                //   제안은 카드 아래에 별도 줄로 붙는다.
                _buildReassignmentBanner(app),

                // [R7-CONTRACT-PERIOD-DISCLOSURE] 지원 당시 본 종료일과
                //   적용된 종료일이 다르면 그 사실을 당사자에게 말한다.
                //
                //   서버는 확정할 때 이미 이것을 알고 저장했고, 관리자에게는
                //   알려 주면서 "지원자에게 안내가 필요할 수 있습니다" 라고
                //   적어 뒀다. 그런데 지원자 쪽 reader 가 하나도 없었다 —
                //   날짜가 바뀐 당사자만 그 사실을 몰랐다.
                //
                //   공고의 **현재** 종료일을 쓰지 않는다. 지원서에 남은
                //   snapshot 만 본다 — 공고가 나중에 수정돼도 그 사람의
                //   약속은 그때 그대로다.
                PeriodRevisionNoticeCard(
                  disclosure: PeriodRevisionDisclosure.of(app),
                ),

                // ── 장기 공고 전용 섹션 ───────────────────────────────
                if (app.isLongTermApplication &&
                    AppStatus.confirmedStatuses.contains(app.status)) ...[
                  _buildLongTermStatusSection(app),
                  _buildInterimSettlementButton(app),
                  // [DEFERRED-RESIGN] 퇴사 신청이 없거나 거절된 상태 + CANCELED 아직 아닌 경우만 버튼 표시
                  // APPROVED 상태여도 status!=CANCELED이면 D+1까지 고용 유지 → 버튼 숨김
                  if ((app.resignStatus == null ||
                       app.resignStatus == AppStatus.rejected) &&
                      app.status != AppStatus.canceled)
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
    // [SYSTEM-INTEGRATION-POSTING-1] 못 읽은 것과 없어진 것을 가른다.
    final loadFailed =
        to == null && app.toId != null && _toLoadFailedIds.contains(app.toId);
    final isDeleted = to == null && !loadFailed;
    final statusInfo = _statusInfo(app.status, app: app);
    // [DU462] B(320 · 2.0)에서 제목이 '공고 정보를 불…'로 잘리고 부제가 '지원 검 / 토 중'으로 끊겼다 —
    //   말줄임 대신 낱말 사이에서만 줄바꿈(제목 keepWords · 부제 phrases · 읽기는 원문).
    final titleText = loadFailed
        ? '공고 정보를 불러오지 못했어요'
        : (to == null ? '삭제된 공고' : to.title);
    final subText = '${app.businessName} · ${statusInfo.label}'
        '${isDeleted ? ' · 공고 삭제됨' : ''}'
        '${loadFailed ? ' · 새로고침하면 다시 보여요' : ''}';

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
                TextLayout.keepWords(titleText),
                semanticsLabel: titleText,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  // [DU462] grey600(grey50 위 4.41) → textSecondary — 제목 textSecondary · 부제 textTertiary 위계.
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                TextLayout.phrases(subText),
                semanticsLabel: subText,
                // [DU461] 부제 grey400(grey50 위 1.79) → textTertiary(같은 화면 카드 보조 줄 · DU459).
                style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
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
      // [R1.2] workDate = 사업장 운영 날짜(KST calendar date).
      //   _mdFmt/weekday는 기기 timezone을 따라 UTC 기기에서 하루 전으로 표시됐다.
      final dt  = app.workDate;
      final time = (app.startTime.isNotEmpty && app.endTime.isNotEmpty)
          ? ' · ${app.startTime}~${app.endTime}'
          : '';
      dateText = '${FormatHelper.formatDateKorean(dt)}$time';
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
        // [E2-NARROW] 근무 시각은 사실이라 자르지 않는다 — 320dp × 1.3 에서
        //   `14:00~1…` 로 종료 시각이 사라졌다. 좁으면 다음 줄로 흐른다
        //   (`14:00~15:00` 은 공백이 없어 한 덩어리로 넘어간다).
        Flexible(
          child: Text(
            dateText,
            style: AppTextStyles.jobMeta(),
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
    // [DU477] 글자는 진한 짝(면 · 테두리는 color 그대로). 이전에는 글자도 color 라 10% 면 위 1.99–3.23 이었다.
    final Color  ink;
    if (remaining < 0)       { label = '만료';        color = AppColors.grey500; ink = AppColors.textSecondary; }
    else if (remaining == 0) { label = 'D-Day';       color = AppColors.error;   ink = AppColors.errorDark; }
    else if (remaining <= 7) { label = 'D-$remaining'; color = AppColors.error;   ink = AppColors.errorDark; }
    else if (remaining <= 14){ label = 'D-$remaining'; color = AppColors.warning; ink = AppColors.warningDark; }
    else                     { label = 'D-$remaining'; color = AppColors.success; ink = AppColors.successDark; }

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
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: ink,
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
          fontSize: 12,
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
        // [DEVICE-MISMATCH-FIX] 지난 근무는 계약 진행보다 근태 결말이 먼저다.
        //   DEV 실측: NO_SHOW 로 마감된 CONTRACT_PENDING 3건이 모두
        //   `관리자가 계약서를 준비 중이에요`로 보였다(그중 1건은 좌석 반납으로
        //   관리자 미발송 목록에서도 빠져 계약서가 오지 않는다).
        final pastOutcome = _pastShiftOutcome(app, now: now);
        if (pastOutcome != null) return pastOutcome;

        final String ctxText;
        final VoidCallback? action;

        if (contract == null && _contractsFailed) {
          // [R8-P7.3] 계약이 없는 것과 계약을 못 읽은 것은 다르다.
          //   못 읽었는데 "준비 중"이라고 말하면, 서명을 기다리는 계약이
          //   있어도 근로자는 그 사실도 서명 버튼도 보지 못한다.
          ctxText = '계약 정보를 불러오지 못했어요. 다시 시도해주세요';
          action  = () => _refreshContracts();
        } else if (contract == null) {
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
          if (!rdDate.isAfter(today)) {
            // ── [E1-MYA] 오늘이거나 지난 확정 근무 ───────────────────────
            //
            //   예전에는 `rdDate.isBefore(today)` 하나로 `근무 완료`를 말하고
            //   리뷰까지 권했다. **날짜가 지났다는 것은 근무를 마쳤다는 뜻이
            //   아니다** — DEV 실측에서 노쇼로 기록된 근무 3건이 모두
            //   `리뷰를 작성해 주세요`로 보였다.
            //
            //   여기서부터는 실제 근태가 말한다. 판정식은 새로 만들지 않고
            //   출퇴근 화면·홈과 같은 술어를 쓴다(노쇼/결근 → 출근 → 퇴근),
            //   완료 여부는 리뷰 자격이 이미 쓰던 기준(`isWageConfirmed ||
            //   isWageTransferred`)을 그대로 따른다.
            final att = _attendanceOf(app);

            // 못 읽었으면 완료도 노쇼도 말하지 않는다(ERROR ≠ ZERO).
            if (att == null && _attendanceFailed) {
              return _contextTextRow(
                text: '근무 상태를 확인하지 못했어요',
                color: AppColors.grey600,
                action: () => _loadApplications(),
              );
            }

            if (att != null && att.isNoShow) {
              return const Text(
                '노쇼 처리됐어요',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.errorDark),
              );
            }
            if (att != null && att.isAbsent) {
              return const Text(
                '결근 처리됐어요',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.warningDark),
              );
            }

            if (att == null) {
              // 근태 문서가 없다. 오늘이면 아직 근무 전일 수 있고, 지난 날이면
              //   완료라고 말할 근거가 없다.
              // [DEVICE-MISMATCH-FIX] 오늘이어도 예정 시간이 끝났으면 "예정"이
              //   아니다 — DEV 실측 Zdn7(10:00~11:00, 근태 없음)이 14시 넘어서도
              //   `오늘 근무 예정이에요`였다.
              if (rdDate == today && app.hasShiftEndedAt(now)) {
                return _missedShiftText;
              }
              return rdDate == today
                  ? const Text(
                      '오늘 근무 예정이에요',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: AppColors.successDark),
                    )
                  : const Text(
                      '근무 기록이 없어요',
                      style: TextStyle(fontSize: 13, color: AppColors.grey600),
                    );
            }
            if (!att.hasCheckedIn) {
              return const Text(
                '출근 기록이 없어요',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.warningDark),
              );
            }
            if (!att.hasCheckedOut) {
              return const Text(
                '근무 중이에요',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppColors.infoDark),
              );
            }
            if (!(att.isWageConfirmed || att.isWageTransferred)) {
              // 퇴근까지 했지만 근태·급여 확정 전이다. 둘을 같은 말로 합치지
              //   않는다 — 리뷰도 이 단계에서는 권하지 않는다.
              // [DEVICE-MISMATCH-FIX] 홈·수입의 `정산 중`과 같은 이름으로 부른다.
              return _settlingText;
            }

            // ── 여기부터가 기존 완료 분기 — 근태가 확정된 근무뿐이다 ──
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
          // [R1.2] KST calendar date — device timezone 무관
          final dateStr  = FormatHelper.formatDateKorean(workDate);
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
        // [SYSTEM-INTEGRATION-R2.2] REJECTED에는 서로 다른 두 사건이 들어 있다.
        //
        //   관리자가 지원을 거절한 경우와, 근로자가 받은 초대를 스스로 거절한
        //   경우다. 같은 값이라서 둘 다 `거절 / 이번 지원은 확정되지 않았어요`로
        //   보였고, 자기가 거절한 초대가 거절당한 것처럼 읽혔다.
        //
        //   새 status를 만들지 않는다. `invitedAt`은 초대로 생긴 지원서에만
        //   있고(callableInviteWorker가 기록, callableApplyToTO는 쓰지 않는다)
        //   후보 자격 검사도 이미 같은 신호로 둘을 구분하고 있다.
        if (app.invitedAt != null) {
          return const Text(
            '초대를 거절했어요',
            // [DU459] 13px 상태 문장 grey500(2.68) → grey600 — 같은 함수 중립 상태 문장과 같다.
            style: TextStyle(fontSize: 13, color: AppColors.grey600),
          );
        }
        return Text(
          app.rejectMessage?.isNotEmpty == true
              ? app.rejectMessage!
              : '이번 지원은 확정되지 않았어요',
          // [DU459] grey500 → grey600(같은 함수 중립 상태 문장).
          style: const TextStyle(fontSize: 13, color: AppColors.grey600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        );

      // ── 취소 / 자동취소 ──────────────────────────────────────────────────────
      case AppStatus.canceled:
      case AppStatus.autoCanceled:
        // [R7-APPLICATION-LIFECYCLE.1E] 문구는 canonical 사전 하나에서 온다.
        //   일정 겹침이면 **내 다른 약속**의 맥락을 한 줄 더 보여준다 —
        //   내 일정이므로 사업장명·시간을 말할 수 있다.
        final conflictContext = app.scheduleConflictContext;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              app.workerEndReasonSentence,
              // [DU459] grey500 → grey600(같은 함수 중립 상태 문장).
              style: const TextStyle(fontSize: 13, color: AppColors.grey600),
            ),
            if (conflictContext != null) ...[
              const SizedBox(height: 2),
              Text(
                conflictContext,
                // [DU459] 12px 보조 줄 grey400(1.88) → textTertiary.
                style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ],
          ],
        );

      // ── 초대받음 ─────────────────────────────────────────────────────────────
      case AppStatus.invited:
        // [SYSTEM-INTEGRATION-R2.2] 이미 인원이 찬 초대에는 수락 버튼을 두지 않는다.
        //
        //   남은 자리 1에 두 명을 초대하면 한 명이 수락한 순간 나머지는 수락할 수
        //   없다. 서버는 정확히 막지만(`정원이 초과되어…`), 화면은 `수락하기`를
        //   그대로 띄워 눌러야 실패를 아는 action이었다.
        //   상태는 INVITED 그대로 두고 — 자리가 다시 열리면 되살아나야 한다 —
        //   지금 할 수 있는 것만 보여준다. 거절은 계속 가능하다.
        //
        // [SYSTEM-INTEGRATION-R2.2.1 CORRECTION] 세 갈래다.
        //
        //   `찼다`와 `모른다`는 다르다. 서버가 slot을 읽지 못했거나 wdId 계약이
        //   깨졌을 때 이전에는 필드가 없었고, 그것이 false로 읽혀 `수락하기`가
        //   떴다. 읽지 못한 것은 자리가 있다는 뜻이 아니다.
        //   관리자 화면과 같은 어휘(InviteCapacityState)를 쓴다.
        if (app.workInstanceCapacityState == InviteCapacityState.full) {
          // [INVITE-CLOSURE-PROJECTION] 정원이 찬 초대는 **끝난 초대가 아니다** —
          //   INVITED 그대로이고 자리가 다시 생기면 수락할 수 있다(R2.2).
          //   그래서 `초대 정리`(=끝난 것을 치우는 말)가 아니라 근로자 자신의
          //   결정인 `거절`을 그 이름 그대로 둔다.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '모집 인원이 찼어요',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.grey600,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                '자리가 다시 생기면 수락할 수 있어요',
                // [DU459] 12px 보조 줄 grey500(2.68) → textTertiary.
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 8),
              _inviteActionButton(
                label: '거절',
                // [DU469] grey600/grey100(4.23) → textSecondary(5.43 · 중립 배지 DU468 과 같은 짝).
                color: AppColors.textSecondary,
                bgColor: AppColors.grey100,
                loading: _decliningIds.contains(app.id),
                onTap: () => _declineInvite(app.id),
              ),
            ],
          );
        }
        if (app.workInstanceCapacityState == InviteCapacityState.closed) {
          // [INVITE-CLOSURE-PROJECTION] `closed` 는 이제 **초대 효력이 끝난 것**만
          //   말한다(수동 마감·공고 삭제·사업장 비활성 등 — 서버 수락 tx 와 같은
          //   판정). 공개 지원 접수의 자동 마감은 여기 오지 않는다.
          //
          //   정리 버튼을 두지 않는다. 그 버튼은 거절(REJECTED, `근로자가
          //   거절함`)을 썼는데 실제 사건은 사업장 쪽 종료다 — 원장의 사유와
          //   다른 기록이 남는다. 초대는 유효 기한에 만료(EXPIRED)로 정리되고
          //   그때 대기 인원도 돌려준다.
          final deleted = app.inviteEndedReason == 'POSTING_DELETED';
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                deleted ? '삭제된 공고의 초대예요' : '모집이 마감된 초대예요',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.grey600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                deleted
                    ? '이 근무는 더 이상 진행되지 않아요'
                    : '사업장이 모집을 마감해 수락할 수 없어요',
                // [DU459] 12px 보조 줄 grey500 → textTertiary.
                style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 2),
              const Text(
                '초대 기한이 지나면 목록에서 자동으로 정리돼요',
                // [DU459] 12px 보조 줄 grey400(1.88) → textTertiary.
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ],
          );
        }
        if (app.workInstanceCapacityState == InviteCapacityState.unknown) {
          // 찼다고도 비었다고도 말하지 않는다. 수락 CTA는 내리되 초대 자체는
          // 그대로 둔다 — 다시 조회되면 available/full 어느 쪽으로든 돌아온다.
          // 거절은 남긴다: 자리 상태와 무관하게 근로자가 언제나 할 수 있는
          // 자기 결정이고, 서버도 capacity를 보지 않는다.
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '근무 가능 여부를 확인하지 못했어요',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppColors.grey600,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                '새로고침 후 다시 확인해 주세요',
                // [DU459] 12px 보조 줄 grey500 → textTertiary.
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
              const SizedBox(height: 8),
              _inviteActionButton(
                label: '거절',
                // [DU469] grey600/grey100(4.23) → textSecondary(5.43 · 중립 배지 DU468 과 같은 짝).
                color: AppColors.textSecondary,
                bgColor: AppColors.grey100,
                loading: _decliningIds.contains(app.id),
                onTap: () => _declineInvite(app.id),
              ),
            ],
          );
        }
        // [CROSS-DOMAIN-R5.3B] 제안은 초대와 다르다 — 원래 지원(A)이 살아 있다.
        //   `근무 초대가 도착했어요`라고만 하면 근로자는 이것이 **기존 지원을
        //   대신하는 선택**이라는 것을 모른다. 무엇을 포기하는지 먼저 말한다.
        final isOffer = app.isAlternativeWorkOffer;
        // [ISG2] 수락 가능 여부는 이 화면의 시계로 본다 — 목록의 다른
        //   날짜 판정과 같은 시각을 써야 한 화면 안에서 말이 엇갈리지 않는다.
        final inviteDeadline = app.effectiveInviteDeadline;
        final acceptable =
            inviteDeadline == null || _now().isBefore(inviteDeadline);
        // [ISG2] 마감 표기는 **KST 고정**이다. `DateFormat.format` 은 받은
        //   DateTime 의 자기 성분을 쓰므로 기기 시간대에 따라 다른 시각이
        //   찍힌다(실측: KST 20:00 마감이 11:00 으로 렌더).
        final inviteDeadlineLabel = inviteDeadline == null
            ? ''
            : FormatHelper.formatKstMonthDayTime(inviteDeadline);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isOffer ? '다른 업무 제안이 도착했어요' : '근무 초대가 도착했어요',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: AppColors.brand,
              ),
            ),
            if (isOffer) ...[
              // [CROSS-DOMAIN-R5.3C.1] 실제 수락할 조건이 primary다.
              //   공고 기본급은 경쟁하는 또 하나의 진실로 띄우지 않는다 —
              //   근로자가 답할 수 없는 "왜 나는 다른가"를 만들지 않는다.
              if (app.hasIndividualCompensation) ...[
                const SizedBox(height: 2),
                Text(
                  '${app.formattedWage} · 회원님께 제안된 급여입니다',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.brand,
                  ),
                ),
              ],
              const SizedBox(height: 2),
              Text(
                '수락하면 기존 지원'
                '${app.sourceWorkType != null ? "(${app.sourceWorkType})" : ""}'
                '은 자동으로 정리돼요',
                // [DU459] 12px 보조 줄 grey500 → textTertiary.
                style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
              ),
            ],
            // [ISG2] 표시하는 마감은 **실제로 수락 가능한 마지막 시각**이다.
            //   저장된 inviteExpiresAt 만 읽으면, 그 계약 이전에 만들어진
            //   초대에서 근무가 끝난 다음 날까지 수락 가능한 것처럼 보인다.
            //   데이터를 고치지 않고 읽는 쪽에서 같은 계약을 적용한다.
            if (app.effectiveInviteDeadline != null) ...[
              const SizedBox(height: 2),
              Text(
                acceptable
                    ? '~$inviteDeadlineLabel 만료'
                    : '수락 기한이 지났어요 (~$inviteDeadlineLabel)',
                style: TextStyle(
                  fontSize: 12,
                  // [DU459] 기한 grey500 → textTertiary(보조 줄) · 지남 error(3.68) → errorDark('노쇼 처리됐어요'와 같다).
                  color: acceptable ? AppColors.textTertiary : AppColors.errorDark,
                ),
              ),
            ],
            // [INVITE-PREACCEPT] 기한 안에서는 **수락 준비 상태**를 말한다.
            //   판정은 서버 값 그대로다. [INVITE-PARITY] 모르면(unknown·
            //   unavailable) 이유를 말하고 수락을 막는다 — 다시 확인이 먼저다.
            // [INVITE-CLOSURE-PROJECTION] 공개 지원은 끝났어도 이 초대는 유효하다 —
            //   공고 목록에서 사라진 근무라 근로자가 헷갈리지 않게 한 줄로 말한다.
            if (acceptable && app.publicIntakeClosed) ...[
              const SizedBox(height: 2),
              const Text(
                '공개 모집은 마감됐지만, 받은 초대는 기한까지 수락할 수 있어요',
                style: TextStyle(fontSize: 12, color: AppColors.grey600),
              ),
            ],
            if (acceptable) ..._inviteReadinessLine(app),
            const SizedBox(height: 8),
            // [INVITE-PREACCEPT] 좁은 화면·큰 글자에서 버튼이 줄 밖으로 나가지
            //   않게 Row 대신 Wrap — 넘치면 다음 줄로 내려간다.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                // [ISG2] 마감이 지난 초대는 눌러도 서버가 거절한다.
                //   누를 수 있게 두고 실패 토스트를 보여 주는 대신,
                //   버튼을 비활성으로 두고 이유를 위에서 말한다.
                ..._invitePrimaryActions(app, isOffer: isOffer, acceptable: acceptable),
                _inviteActionButton(
                  label: '거절',
                  // [DU469] grey600/grey100(4.23) → textSecondary(5.43).
                  color: AppColors.textSecondary,
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
          // [DU459] 13px 상태 문장 grey400(1.88) → grey600(같은 함수 중립 상태 문장).
          style: TextStyle(fontSize: 13, color: AppColors.grey600),
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
  /// [INVITE-PREACCEPT] 기한 안의 초대가 지금 어느 단계인지 한 줄로 말한다.
  ///
  /// 서버가 준 [InviteAcceptReadiness] 그대로다. ready·unknown 은 덧붙이지
  /// 않는다 — 수락 버튼이 곧 다음 행동이다.
  List<Widget> _inviteReadinessLine(ApplicationModel app) {
    final String? text;
    switch (app.inviteAcceptReadiness) {
      case InviteAcceptReadiness.consentRequired:
        text = '사업장이 서류를 확인해야 수락할 수 있어요. 먼저 서류 열람에 동의해 주세요.';
        break;
      case InviteAcceptReadiness.reviewPending:
        text = '사업장이 서류를 확인하고 있어요. 확인이 끝나면 수락할 수 있어요.';
        break;
      case InviteAcceptReadiness.documentRequired:
        text = '신분증을 등록해야 수락할 수 있어요.';
        break;
      case InviteAcceptReadiness.unavailable:
        // 서버가 확인하려다 못 했다 — READY 가 아니다. 다시 확인하게 한다.
        text = '수락할 수 있는지 확인하지 못했어요. 다시 확인해 주세요.';
        break;
      case InviteAcceptReadiness.unknown:
        // [INVITE-PARITY] 서버가 이 값을 아예 주지 않았다(구버전 서버). 조회
        //   실패와 다른 이유다 — 근로자가 할 수 있는 일은 같다(다시 확인).
        text = '지금은 수락 가능 여부를 확인할 수 없어요. 잠시 후 다시 확인해 주세요.';
        break;
      case InviteAcceptReadiness.ready:
        text = null;
        break;
    }
    if (text == null) return const [];
    return [
      const SizedBox(height: 4),
      Text(text, style: const TextStyle(fontSize: 12, color: AppColors.grey600)),
    ];
  }

  /// [INVITE-PREACCEPT] 단계별 주 버튼.
  ///
  ///   동의 필요   → `서류 열람 동의` (수락이 아니다)
  ///   확인 대기   → `수락하기` 비활성(서버가 거절할 버튼을 열어 두지 않는다)
  ///   신분증 없음 → `서류 등록하기`
  ///   수락 가능   → `수락하기`
  ///   조회 실패·모름 → `다시 확인` + `수락하기` 비활성
  ///   기한 종료   → `수락하기` 비활성
  List<Widget> _invitePrimaryActions(
    ApplicationModel app, {
    required bool isOffer,
    required bool acceptable,
  }) {
    final acceptLabel = isOffer ? '제안 조건으로 수락' : '수락하기';
    Widget accept({required bool enabled}) => _inviteActionButton(
          label: acceptLabel,
          color: AppColors.brand,
          bgColor: AppColors.infoBg,
          loading: _acceptingIds.contains(app.id),
          onTap: enabled ? () => _acceptInvite(app.id) : null,
        );
    if (!acceptable) return [accept(enabled: false)];
    switch (app.inviteAcceptReadiness) {
      case InviteAcceptReadiness.consentRequired:
        return [
          _inviteActionButton(
            label: '서류 열람 동의',
            color: AppColors.brand,
            bgColor: AppColors.infoBg,
            loading: _consentingIds.contains(app.id),
            onTap: () => _giveInviteConsent(app),
          ),
        ];
      case InviteAcceptReadiness.reviewPending:
        return [accept(enabled: false)];
      case InviteAcceptReadiness.documentRequired:
        return [
          _inviteActionButton(
            label: '서류 등록하기',
            color: AppColors.brand,
            bgColor: AppColors.infoBg,
            loading: false,
            onTap: () async {
              await ApplyPrerequisitesScreen.show(context, isFlexType: true);
              if (mounted) _loadApplications();
            },
          ),
        ];
      case InviteAcceptReadiness.unavailable:
      case InviteAcceptReadiness.unknown:
        // [INVITE-PARITY] 모르면 수락하지 않게 한다. 확인되지 않은 상태로
        //   누르게 두면 서버 거절을 사용자가 처음 듣는 자리가 된다.
        //   다시 확인이 다음 행동이다.
        return [
          _inviteActionButton(
            label: '다시 확인',
            color: AppColors.brand,
            bgColor: AppColors.infoBg,
            loading: false,
            onTap: _loadApplications,
          ),
          accept(enabled: false),
        ];
      case InviteAcceptReadiness.ready:
        return [accept(enabled: true)];
    }
  }

  Widget _inviteActionButton({
    required String label,
    required Color color,
    required Color bgColor,
    required bool loading,
    // [ISG2] null 이면 비활성 — 마감이 지난 초대의 `수락하기`가 그렇다.
    //   누를 수 있게 두고 서버 실패 토스트로 알리는 대신 미리 막는다.
    required VoidCallback? onTap,
  }) {
    final disabled = loading || onTap == null;
    return GestureDetector(
      onTap: disabled ? null : onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: disabled ? AppColors.grey100 : bgColor,
          borderRadius: BorderRadius.circular(8),
        ),
        // [INVITE-PREACCEPT] 진행 중이면 **보이는** 표시를 준다 — 글자색만
        //   흐려지면 눌렸는지 알 수 없어 다시 누르게 된다.
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (loading) ...[
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.grey400),
              ),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: disabled ? AppColors.grey400 : color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── cancelReason → 사용자 문장 ──────────────────────────────────────────────
  //
  // [R7-APPLICATION-LIFECYCLE.1E] 이 화면에 있던 사전을 지웠다. 같은 이유
  //   코드의 문장이 화면마다 복제되면 한쪽만 고쳐지는 날이 온다 — canonical
  //   은 `ApplicationModel.workerEndReasonSentence` 하나다.

  // ─── 상태 정보 헬퍼 ──────────────────────────────────────────────────────────

  /// [SYSTEM-INTEGRATION-R2.2] [app]을 함께 받는다 — REJECTED 하나에 관리자 거절과
  /// 근로자의 초대 거절이 같이 들어 있어 상태 값만으로는 라벨을 정할 수 없다.
  _StatusInfo _statusInfo(String status, {ApplicationModel? app}) {
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
        // 내가 거절한 초대를 '거절당함'으로 읽히게 두지 않는다.
        if (app?.invitedAt != null) {
          return const _StatusInfo(
            label: '초대 거절',
            // [DU468] 중립 배지 grey600/grey100(4.23) → textSecondary/grey100(중립 상태 칩 짝 · DU274 · 소급8 · DU466 과 같다).
            color: AppColors.textSecondary,
            bgColor: AppColors.grey100,
          );
        }
        return const _StatusInfo(
          label: '거절',
          color: AppColors.errorDark,
          bgColor: AppColors.errorBg,
        );
      case AppStatus.canceled:
        return const _StatusInfo(
          label: '취소',
          // [DU468] 중립 배지 grey600/grey100(4.23) → textSecondary/grey100(중립 상태 칩 짝 · DU274 · 소급8 · DU466 과 같다).
          color: AppColors.textSecondary,
          bgColor: AppColors.grey100,
        );
      case AppStatus.autoCanceled:
        // [CROSS-DOMAIN-R5.3D.1] 제안을 받아들여 접힌 지원은 취소가 아니다.
        //   generic '자동 취소' 배지로 보이면 근로자 이력에 없는 사건이
        //   있는 것처럼 읽힌다 — 판정은 cancelReason 하나로 한다.
        if (app?.isReassignedAway ?? false) {
          return const _StatusInfo(
            label: '다른 업무로 확정됨',
            color: AppColors.successDark,
            bgColor: AppColors.successBg,
          );
        }
        return const _StatusInfo(
          label: '자동 취소',
          // [DU468] 중립 배지 grey600/grey100(4.23) → textSecondary/grey100(중립 상태 칩 짝 · DU274 · 소급8 · DU466 과 같다).
          color: AppColors.textSecondary,
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
          // [DU468] 중립 배지 grey600/grey200(3.97) → textSecondary/grey100(중립 상태 칩 짝 · DU274 · 소급8 · DU466 과 같다).
          color: AppColors.textSecondary,
          bgColor: AppColors.grey100,
        );
      default:
        return const _StatusInfo(
          label: '알 수 없음',
          // [DU468] 중립 배지 grey600/grey200(3.97) → textSecondary/grey100(중립 상태 칩 짝 · DU274 · 소급8 · DU466 과 같다).
          color: AppColors.textSecondary,
          bgColor: AppColors.grey100,
        );
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // [CROSS-DOMAIN-R5.3E.2] 확정 근무 변경 제안
  //
  //   제안이 왔다고 이 카드의 확정 표시가 바뀌지는 않는다. 근로자가 고르기
  //   전까지 근무는 지금 조건 그대로이고, 카드가 먼저 바뀌면 "이미 변경됐다"로
  //   읽힌다. 그래서 확정 정보는 손대지 않고 아래에 한 줄을 더한다.
  // ═══════════════════════════════════════════════════════════════════════════

  Widget _buildReassignmentBanner(ApplicationModel app) {
    final p = _reassignProposals
        .where((e) => e.sourceApplicationId == app.id && e.isActionable)
        .firstOrNull;
    if (p == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: InkWell(
        onTap: () => _openReassignmentSheet(p),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: BoxDecoration(
            color: AppColors.infoBg,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.swap_horiz,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.infoDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '근무 변경 제안이 왔어요 · 확인 전까지 지금 근무 그대로예요',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.infoDark),
                ),
              ),
              Icon(Icons.chevron_right,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.infoDark),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openReassignmentSheet(ConfirmedReassignmentProposal p) async {
    final decision = await ConfirmedReassignmentSheet.decide(context, p);
    if (!mounted || decision == ReassignmentDecision.dismissed) return;
    ToastHelper.showSuccess(decision == ReassignmentDecision.changed
        ? '변경된 근무로 확정됐습니다.'
        : '기존 근무 조건을 유지합니다.');
    await _loadReassignProposals();
    if (!mounted) return;
    await _loadApplications();
  }

  Future<void> _loadReassignProposals() async {
    try {
      final list = await ConfirmedReassignmentService.instance.myProposals();
      if (!mounted) return;
      setState(() => _reassignProposals = list);
    } catch (e) {
      // 못 읽은 것을 "제안 없음"으로 바꾸지 않는다 — 직전 목록을 유지한다.
      debugPrint('[R5.3E.2] 변경 제안 조회 실패: $e');
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

  /// [CROSS-DOMAIN-R5.3B] 제안 비교 한 줄 — A와 B를 같은 축으로 보여준다.
  ///
  /// 값을 모르면 **비워 둔다**. 모르는 조건을 `-`나 `0원`으로 채우면
  /// 근로자가 없는 사실을 근거로 고르게 된다.
  /// [R7-PAYROLL-POLICY.4B] 이 약속에 고정된 근태·급여 기준 — **7개 전부**.
  ///
  ///   `.4A` 는 네 항목만 보여줬다. 그런데 급여에 영향하는 숫자는 7개이고,
  ///   빠진 셋(일찍 도착·조출 단위·늦게 퇴근 인정 범위)도 실제 지급액을
  ///   바꾼다. 항목·문구는 `attendance_policy_disclosure` 한 곳에서 온다 —
  ///   계약서·PDF·관리자 확인 시트가 같은 목록을 쓴다.
  ///
  ///   값은 전달받은 snapshot 만 쓴다. 사업장 문서를 다시 읽지 않는다.
  /// 수락 확인창 맨 위 — 이 초대가 어느 근무인지(날짜·업무·시간·급여).
  Widget _inviteAcceptSummary(ApplicationModel app) {
    final day = app.isLongTermApplication ? (app.desiredStartDate ?? app.workDate) : app.workDate;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${FormatHelper.formatDateKorean(day)} · ${app.selectedWorkType}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text('${app.startTime} ~ ${app.endTime} · ${app.formattedWage}',
              style: const TextStyle(fontSize: 13, color: AppColors.grey700)),
        ],
      ),
    );
  }

  Widget _acceptDialogSectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      );

  /// [ATTENDANCE-RULE-GUIDE.29-A1] 초대 수락 — 이 약속(지원서 snapshot)의 '근태 인정 기준'.
  ///   공고·계약과 같은 형식: 근무시간 → 출근/퇴근 기준, 기준 설명은 늘 보이고 이 근무 시각의
  ///   사례는 '시간 예시 보기' 로 편다. 예전의 따로 떨어진 회색 사례 묶음(같은 내용)을 합쳤다.
  ///   기록이 없으면 **사업장 현재 기준으로 채우지 않는다.**
  Widget _attendancePolicyBlock(AttendanceRules? rules, ApplicationModel app) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(kAttendanceRuleGuideTitle,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          if (rules == null)
            const Text(kAttendancePolicyUnknownNote,
                style: TextStyle(fontSize: 12, color: AppColors.grey700))
          else ...[
            AttendanceRuleGuideView(
              guide: attendanceRuleGuide(rules,
                  startHHmm: app.startTime, endHHmm: app.endTime),
              collapsibleExamples: true,
            ),
            const SizedBox(height: 4),
            // 근로자에게 가는 문구다 — 폰트 하한(12px)을 지킨다.
            const Text(kAttendancePolicyEffectNote,
                style: TextStyle(fontSize: 12, color: AppColors.grey600)),
            const Text(kAttendancePolicyFrozenNote,
                style: TextStyle(fontSize: 12, color: AppColors.grey600)),
          ],
        ],
      ),
    );
  }

  Widget _offerComparisonRow({
    required String label,
    required String workType,
    required String? timeText,
    required String? wageText,
    required String? wageTypeText,
    required bool muted,
  }) {
    final fg = muted ? AppColors.grey500 : AppColors.textPrimary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: muted ? AppColors.grey100 : AppColors.infoBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: muted ? AppColors.grey500 : AppColors.brand,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            workType,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: fg,
              decoration: muted ? TextDecoration.lineThrough : null,
            ),
          ),
          if (timeText != null) ...[
            const SizedBox(height: 2),
            Text(timeText, style: TextStyle(fontSize: 12, color: fg)),
          ],
          if (wageText != null && wageText.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              wageTypeText != null && wageTypeText.isNotEmpty ?
                  '$wageTypeText $wageText' : wageText,
              style: TextStyle(fontSize: 12, color: fg),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _acceptInvite(String applicationId) async {
    // [INVITE-PREACCEPT] 누른 **즉시** 진행 중으로 표시하고 중복 탭을 막는다.
    //   예전에는 세무 상태 읽기·확인창 준비가 끝난 뒤(DEV 실측 2.4~6.4초)에야
    //   표시가 바뀌어, 반응 없는 버튼을 다시 누르면 확인창이 겹칠 수 있었다.
    if (_acceptingIds.contains(applicationId)) return;
    setState(() => _acceptingIds.add(applicationId));
    try {
      await _acceptInviteFlow(applicationId);
    } finally {
      if (mounted) setState(() => _acceptingIds.remove(applicationId));
    }
  }

  /// [INVITE-PREACCEPT] 이 초대에 서류 열람 동의**만** 기록한다.
  ///
  /// 수락이 아니다 — 상태·자리·계약은 그대로다. 동의가 있어야 사업장이
  /// 서류를 확인할 수 있고, 확인이 끝나야 수락할 수 있다. 수락은 근로자가
  /// 따로 한다. 문구와 버전은 [DocumentAccessConsent] 한 곳에서 온다.
  Future<void> _giveInviteConsent(ApplicationModel app) async {
    if (_consentingIds.contains(app.id)) return;
    setState(() => _consentingIds.add(app.id));
    try {
      final ok = await DialogHelper.showCustom<bool>(
        context,
        title: '서류 열람 동의',
        icon: Icons.assignment_ind_outlined,
        iconColor: AppColors.brand,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '사업장이 서류를 확인해야 이 초대를 수락할 수 있어요.\n'
              '동의만으로 근무가 확정되지는 않아요. 확인이 끝나면 '
              '수락은 따로 해 주세요.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            DocumentAccessConsent.inviteCard(app.businessName),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.brand),
            onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
            child: const Text('동의하기', style: TextStyle(color: Colors.white)),
          ),
        ],
      );
      if (ok != true || !mounted) return;
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGiveApplicationDocumentConsent')
          .call({
        'applicationId': app.id,
        'documentAccessConsentVersion': DocumentAccessConsent.inviteVersion,
      });
      if (!mounted) return;
      ToastHelper.showSuccess('동의했어요. 사업장이 서류를 확인하면 수락할 수 있어요.');
      _loadApplications();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) {
        ToastHelper.showError(e.message ?? '동의를 기록하지 못했어요. 다시 시도해 주세요.');
        _loadApplications();
      }
    } catch (_) {
      if (mounted) ToastHelper.showError('동의를 기록하지 못했어요. 다시 시도해 주세요.');
    } finally {
      if (mounted) setState(() => _consentingIds.remove(app.id));
    }
  }

  Future<void> _acceptInviteFlow(String applicationId) async {
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) { ToastHelper.showError('로그인이 필요합니다.'); return; }

    // [CROSS-DOMAIN-R5.2] 수락은 근무 확정이다 — 직접 지원과 같은 문턱을 둔다.
    //
    //   1) 서류가 없으면 좌석을 잡기 전에 등록으로 보낸다(서버도 같은 조건으로
    //      막지만, 여기서 막아야 근로자가 이유를 알고 고칠 수 있다).
    //   2) 동의는 **이 초대 건에 대해** 지금 받는다. 다른 지원서의 동의를
    //      가져다 쓰지 않는다. 문구는 지원 경로의 canonical 카드를 그대로 쓴다.
    final item = _applications.firstWhere(
      (e) => e.application.id == applicationId,
      orElse: () => _applications.first,
    );
    final isFlex = item.to?.isFlexType ?? true;
    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;
    // [PII-B4-R1.4 §39] 지원·수락 모든 진입점이 같은 축을 본다.
    // [R7-PREDEVICE-DISCLOSURE-RENDER.1] 읽기 경계 경유 — 판정은 그대로다.
    final acceptTax = await _reads.taxStatus();
    if (!mounted) return;
    if (!meetsApplyPrerequisites(user,
        isFlexType: isFlex, taxStatus: acceptTax)) {
      ToastHelper.showWarning('근무 확정을 위해 서류 등록이 필요합니다.');
      final ok = await ApplyPrerequisitesScreen.show(context, isFlexType: isFlex);
      if (!ok || !mounted) return;
    }

    // [R7-PAYROLL-POLICY.4A §30] 이 약속에 **고정된** 근태·급여 기준.
    //
    //   숫자를 전부 늘어놓지 않는다 — 급여에 가장 자주 영향하는 네 항목만
    //   보여주고, 그 기준이 이 약속에 묶여 있다는 사실을 말한다.
    //   값의 출처는 `Application.attendancePolicySnapshot` 하나다.
    //   사업장의 현재 설정을 읽어 보여주면 수락 뒤 실제 계산과 달라진다.

    // [CROSS-DOMAIN-R5.3B] 제안이면 A와 B를 **나란히** 보여주고 고르게 한다.
    //   "업무를 바로 변경합니다"가 아니다 — 근로자가 B를 확정하고 A를 접는 것이다.
    //   A는 같은 목록에 PENDING으로 함께 있다. 못 찾으면 비교를 생략하되
    //   "기존 지원이 정리된다"는 사실은 그대로 말한다(모름을 없음으로 읽지 않는다).
    final offerApp = item.application;
    final isOfferAccept = offerApp.isAlternativeWorkOffer;
    ApplicationModel? sourceApp;
    if (isOfferAccept && offerApp.sourceApplicationId != null) {
      for (final e in _applications) {
        if (e.application.id == offerApp.sourceApplicationId) {
          sourceApp = e.application;
          break;
        }
      }
      if (sourceApp == null) {
        // [CROSS-DOMAIN-R5.3B.1] 목록은 페이지 단위라 A가 첫 페이지 밖일 수 있다.
        //   비교를 보여줄 수 없으면 근로자는 무엇을 포기하는지 모르고 고른다.
        //   그 한 건만 읽고, **본인 소유일 때만** 쓴다.
        try {
          final one = await _firestoreService
              .getApplicationOnce(offerApp.sourceApplicationId!);
          if (one != null && one.uid == uid) sourceApp = one;
        } catch (e) {
          // 읽지 못한 것은 '기존 지원이 없다'가 아니다 — 비교만 생략한다.
          debugPrint('⚠️ [R5.3B.1] 원 지원서 조회 실패: $e');
        }
        if (!mounted) return;
      }
    }

    final confirmed = await DialogHelper.showCustom<bool>(
      context,
      title: isOfferAccept ? '다른 업무 제안 수락' : '초대 수락',
      icon: isOfferAccept ? Icons.swap_horiz : Icons.check_circle_outline,
      iconColor: AppColors.success,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isOfferAccept) ...[
            _offerComparisonRow(
              label: '기존 지원',
              workType: sourceApp?.selectedWorkType ??
                  offerApp.sourceWorkType ?? '기존 업무',
              timeText: sourceApp == null ? null :
                  '${sourceApp.startTime} ~ ${sourceApp.endTime}',
              wageText: sourceApp?.formattedWage,
              wageTypeText: sourceApp?.wageTypeLabel,
              muted: true,
            ),
            const SizedBox(height: 6),
            const Icon(Icons.arrow_downward,
                size: 18, color: AppColors.grey400),
            const SizedBox(height: 6),
            _offerComparisonRow(
              label: offerApp.hasIndividualCompensation
                  ? '제안받은 업무 · 회원님께 제안된 급여'
                  : '제안받은 업무',
              workType: offerApp.selectedWorkType,
              timeText: '${offerApp.startTime} ~ ${offerApp.endTime}',
              wageText: offerApp.formattedWage,
              wageTypeText: offerApp.wageTypeLabel,
              muted: false,
            ),
            const SizedBox(height: 12),
            // [R5.3D.1] 이력은 남는다 — 사라지는 것은 불이익이다.
            const Text(
              "제안받은 업무로 확정되고, 기존 지원은 '다른 업무로 확정됨'으로\n"
              '정리됩니다. 취소·노쇼 불이익은 적용되지 않습니다.',
              style: TextStyle(fontSize: 13),
            ),
          ] else ...[
            // [INVITE-ACCEPT-READABILITY] 무엇을 수락하는지가 맨 위 — 질문만 있고
            //   어느 근무인지가 없어 아래 긴 고지 속에서 찾아야 했다(Pixel 5 10-23).
            _inviteAcceptSummary(offerApp),
            const SizedBox(height: 8),
            const Text('이 업무에 참여하시겠습니까?\n수락 후 일정 충돌이 없으면 확정됩니다.',
                style: TextStyle(fontSize: 13, height: 1.45)),
          ],
          // [R7-PAYROLL-POLICY.4A §22·§23·§30] 수락 전에 **이 약속에 고정된**
          //   근태·급여 기준을 볼 수 있어야 한다. 사업장의 현재 설정이 아니다 —
          //   초대·제안을 보낸 시점의 기준이고, 사업장이 그 뒤에 기준을 바꿔도
          //   이 약속에는 적용되지 않는다. 지원서 문서에 이미 있으므로
          //   사업장 문서를 다시 읽지 않는다.
          // [R7-PAYROLL-POLICY.4B] 기록이 없어도 **그 사실을 말한다** —
          //   아무것도 보여주지 않으면 근로자는 기준이 없는지 화면이 빠뜨린
          //   것인지 알 수 없고, 사업장 현재 설정으로 대신 채우는 것은 금지다.
          // [INVITE-ACCEPT-READABILITY] 버튼이 말하는 '동의'의 내용을 기준표보다 먼저,
          //   제목으로 나눠 보인다. 동의 문구는 그대로다(버전 토큰이 문장을 가리킨다).
          const SizedBox(height: 16),
          _acceptDialogSectionTitle('서류 열람 동의'),
          DocumentAccessConsent.inviteCard(item.application.businessName),
          const SizedBox(height: 16),
          _attendancePolicyBlock(offerApp.attendancePolicySnapshot, offerApp),
        ],
      ),
      // [INVITE-ACCEPT-POP] 확인창은 루트 Navigator 에 뜨는데 이 화면은 탭 안의 중첩 Navigator 에 있다 —
      //   `Navigator.pop(context)` 는 탭 Navigator 를 닫으려 해서 버튼이 아무것도 하지 않았다(Pixel 5 10-23).
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(false),
          child: const Text('취소'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: AppColors.success),
          onPressed: () => Navigator.of(context, rootNavigator: true).pop(true),
          // [.29-A1] 좁은 폭·큰 글자에서 '동의하 / 고 초대 / 수락' 으로 낱말이 갈렸다 — 띄어쓰기에서만 줄바꿈.
          child: Text(
              TextLayout.keepWords(isOfferAccept ? '동의하고 제안 수락' : '동의하고 초대 수락'),
              semanticsLabel: isOfferAccept ? '동의하고 제안 수락' : '동의하고 초대 수락',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)),
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    // 진행 표시·중복 탭 방지는 [_acceptInvite] 가 이미 켰다.
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableAcceptTOInvitation');
      // [CROSS-DOMAIN-R5.2] 이 건에 대한 동의를 함께 보낸다 — 서버가 CONFIRMED와
      //   같은 트랜잭션에 기록한다. 버전은 방금 보여준 문구의 버전이다.
      await callable.call({
        'applicationId': applicationId,
        'documentAccessConsentGiven': true,
        'documentAccessConsentVersion': DocumentAccessConsent.inviteVersion,
      });
      if (!mounted) return;
      ToastHelper.showSuccess('초대를 수락했습니다!');
      _loadApplications();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      // [INVITE-PREACCEPT] 서버가 근로자용 문구와 상태 코드를 준다.
      //   목록을 다시 읽어 카드가 그 상태(동의 필요·확인 대기 등)로
      //   바뀌게 한다 — 근로자가 다음에 무엇을 해야 하는지가 카드에 보인다.
      // [MW-52] 서버 문장이 길다(최저임금 미달 초대 안내) — 기기에서 '요/청해'로 낱말 가운데가 끊겼다.
      ToastHelper.showError(TextLayout.keepWords(e.message ?? '수락 중 오류가 발생했습니다.'));
      final details = e.details;
      if (details is Map && details['inviteAcceptReadiness'] != null) {
        _loadApplications();
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('수락 중 오류가 발생했습니다.');
    }
  }

  Future<void> _declineInvite(String applicationId) async {
    if (_decliningIds.contains(applicationId)) return;
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) { ToastHelper.showError('로그인이 필요합니다.'); return; }

    final confirmed = await DialogHelper.showDeclineInviteConfirm(context);
    if (!confirmed || !mounted) return;

    setState(() => _decliningIds.add(applicationId));
    try {
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableDeclineTOInvitation');
      // [INVITE-DECLINE-INTENT] 상태를 보여 준 뒤의 명시 거절임을 서버에 알린다.
      await callable.call({'applicationId': applicationId, 'declineIntent': 'EXPLICIT'});
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
    await _refreshContracts();
  }

  /// 계약 맵만 다시 읽는다.
  ///
  ///   [R8-P7.3] 실패를 삼키지 않는다 — 실패하면 _contractsFailed 를 세워
  ///   화면이 "계약 없음"이 아니라 "불러오지 못했다"라고 말하게 한다.
  ///   지원 목록 자체는 유효하므로 화면 전체를 오류로 만들지는 않는다.
  Future<void> _refreshContracts() async {
    if (!mounted) return;
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;
    _contractsLoaded = false;
    try {
      final updated = await _loadContracts(uid, _applications);
      if (!mounted) return;
      setState(() {
        _contractMap = {..._contractMap, ...updated};
        _contractsFailed = false;
      });
    } catch (e) {
      debugPrint('⚠️ 계약 재조회 실패: $e');
      if (!mounted) return;
      setState(() => _contractsFailed = true);
      ToastHelper.showError('계약 정보를 불러오지 못했습니다');
    }
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

      // [R7-RER.2 §5] 자격 보류 중이면 빈 폼을 열지 않는다.
      //   요청을 못 읽은 경우(null)는 보류가 아니다 — 기존 동작을 유지한다.
      if (reviewRequest?.isEligibilitySuspended == true) {
        ToastHelper.showInfo(MonthlyReviewService.eligibilitySuspendedMessage);
        return;
      }

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
