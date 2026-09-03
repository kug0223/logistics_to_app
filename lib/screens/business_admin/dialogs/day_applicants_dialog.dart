// 지원명단 다이얼로그 — 선택 날짜의 지원자(PENDING) + 확정자(CONFIRMED)
// 공고(TO) → 업무상세별로 묶어서 표시, work_applicants_dialog 카드 스타일 준용
import 'dart:convert';
import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

import '../../../models/core/application_model.dart';
import '../../../models/core/attendance_model.dart';
import '../../../models/core/business_model.dart';
import '../../../models/core/employment_contract_model.dart';
import '../../../models/core/monthly_review_model.dart';
import '../../../models/core/user_model.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_data.dart';
import '../../../providers/user_provider.dart';
import '../../../screens/common/settings_screen.dart';
import '../../../screens/contract/contract_sign_screen.dart' show ContractTemplateWidget;
import '../../../services/contract_service.dart';
import '../../../services/firestore_service.dart';
import '../../../services/monthly_review_service.dart';
import '../../../utils/id_card_helper.dart';
// trust_score_helper: 신뢰도 점수 시스템 제거 (5A.2A)
import '../../../theme/app_colors.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../widgets/app_select_field.dart';
import '../../../widgets/common/app_checkbox.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../models/core/contract_template_model.dart' show ContractArticle;
import '../../../widgets/dialogs/contract_template_selector_dialog.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';
import '../../../widgets/work_type_icon.dart';
import 'available_workers_bottom_sheet.dart';
import 'invite_method_sheet.dart';
import 'invite_worker_dialog.dart';

// ─── 그룹 데이터 (업무 단위) ────────────────────────────────────────────────
class _GroupData {
  final String? toId;
  final String toTitle;
  final String workType;
  final String startTime;
  final String endTime;
  final bool isLongTerm;
  /// [8.1E.4] canonical workDetail ID (wdId, new-schema 슬롯)
  final String? wdId;
  final String? workDetailId;   // composite WorkDetail ID (레거시/capacityKey 용)
  int requiredCount;             // 나중에 채움
  final List<ApplicationModel> pendingApps = [];
  final List<ApplicationModel> confirmedApps = [];

  _GroupData({
    required this.toId,
    required this.toTitle,
    required this.workType,
    required this.startTime,
    required this.endTime,
    required this.isLongTerm,
    this.wdId,
    this.workDetailId,
    this.requiredCount = 0,
  });

  // 공고 고유 키 (공고 헤더 그룹핑용)
  String get toKey => toId ?? 'noid_$toTitle';

  // [8.1E.4] 업무 고유 키 — wdId 우선, composite fallback, legacy fallback
  String get groupKey {
    final wKey = wdId?.isNotEmpty == true
        ? wdId!
        : (workDetailId?.isNotEmpty == true
            ? workDetailId!
            : '${workType}_${startTime}_$endTime');
    return '${toId ?? toTitle}_$wKey';
  }

  // capacity 맵에서 찾을 때 사용할 키 (composite 기반 _workDetailCapacityMap 과 일치)
  String get capacityKey => workDetailId?.isNotEmpty == true
      ? workDetailId!
      : '${workType}_${startTime}_$endTime';
}

// ─── 다이얼로그 ────────────────────────────────────────────────────────────────
class DayApplicantsDialog extends StatefulWidget {
  final DateTime date;
  final List<String> businessIds;
  final List<BusinessModel> businesses;
  /// 특정 공고로 필터링 (TOGroupCard 명단 보기에서 사용). null이면 전체 표시.
  final String? filterToId;

  const DayApplicantsDialog({
    super.key,
    required this.date,
    required this.businessIds,
    required this.businesses,
    this.filterToId,
  });

  @override
  State<DayApplicantsDialog> createState() => _DayApplicantsDialogState();
}

class _DayApplicantsDialogState extends State<DayApplicantsDialog> {
  final FirestoreService _svc = FirestoreService();
  final ContractService _contractSvc = ContractService();
  final MonthlyReviewService _reviewSvc = MonthlyReviewService();

  bool _isLoading = true;
  bool _isProcessing = false;
  bool _hasChanges = false;
  String? _selectedBusinessId;

  List<ApplicationModel> _pendingApps = [];
  List<ApplicationModel> _confirmedApps = [];
  List<_GroupData> _cachedGroups = [];
  Map<String, UserModel> _userMap = {};
  Map<String, String?> _contractStatusMap = {};
  Map<String, int> _weeklyWorkCountMap = {};
  Map<String, int> _workDetailCapacityMap = {};

  final Set<String> _selectedIds = {};
  final Set<String> _starredIds = {};
  Map<String, String> _idCardStatusMap = {};
  final Map<String, bool> _reviewWrittenMap = {};
  // [BUG-CANCEL-01] 근무 이력 있는 확정자에게 확정취소 버튼 노출 방지용 맵
  // key = userId, value = 오늘 날짜에 checkIn 기록 존재 여부
  Map<String, bool> _hasWorkedMap = {};
  // 파트변경 다이얼로그용 TO 캐시 — 같은 TO 재탭 시 서버 읽기 생략
  final Map<String, TOModel> _toCache = {};
  bool _isBatchMode = false;
  // BUG-1 수정: 전역 bool → 그룹 key로 스코프화.
  // 전역이면 다중 그룹 시 그룹A 선택 모드가 그룹B UI에도 반영됨.
  String? _idCardSelectGroupKey;       // null = 선택 모드 없음
  final Set<String> _selectedIdCardUserIds = {};
  // BUG-3 수정: 동일 이유로 전역 bool → 그룹 key 스코프화.
  String? _contractBatchGroupKey;      // null = 처리 중 없음

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    // [특이사항] businessIds는 반드시 _getAdminBusinesses()가 반환한 서버 검증 목록만 전달해야 한다.
    // 다이얼로그 내부에서 businessId 소속 재검증을 하지 않으므로,
    // 호출부가 신뢰할 수 없는 출처의 ID를 전달하면 크로스-사업장 쿼리가 실행된다.
    _selectedBusinessId =
        widget.businessIds.isNotEmpty ? widget.businessIds.first : null;
    _applySavedBusinessThenLoad();
  }

  Future<void> _applySavedBusinessThenLoad() async {
    if (widget.businessIds.length > 1) {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('alfit_last_business_id');
      if (saved != null && widget.businessIds.contains(saved) && mounted) {
        setState(() => _selectedBusinessId = saved);
      }
    }
    if (!mounted) return;
    _load();
  }

  String _bizName(String? bizId) {
    if (bizId == null) return '';
    for (final b in widget.businesses) {
      if (b.id == bizId) return b.name;
    }
    return bizId;
  }

  Future<void> _load() async {
    final bizId = _selectedBusinessId;
    if (bizId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    setState(() {
      _isLoading = true;
      _selectedIds.clear();
      _starredIds.clear();
      _idCardStatusMap = {};
      _reviewWrittenMap.clear();
      _hasWorkedMap = {}; // [BUG-CANCEL-01] 로드 시작 시 초기화 — 이전 날짜 잔류 방지
      _toCache.clear();   // 파트변경 후 재로드 시 TO 캐시 무효화
      _isBatchMode = false;
      _idCardSelectGroupKey = null;
      _selectedIdCardUserIds.clear();
      _contractBatchGroupKey = null;
    });

    try {
      // Phase 1: 지원자 + 확정자 병렬 조회
      final phase1 = await Future.wait([
        _svc.getPendingApplicationsByDateAndBusiness(
            date: widget.date, businessId: bizId),
        _svc.getConfirmedWorkersByDateAndBusiness(
            date: widget.date, businessId: bizId),
      ]);
      var pending = phase1[0] as List<ApplicationModel>;
      var confirmed = phase1[1] as List<ApplicationModel>;

      // 특정 공고 필터 (TOGroupCard 명단 보기)
      if (widget.filterToId != null) {
        pending = pending.where((a) => a.toId == widget.filterToId).toList();
        confirmed = confirmed.where((a) => a.toId == widget.filterToId).toList();
      }

      if (!mounted || _selectedBusinessId != bizId) return;

      // Phase 2: 유저 프로필 + 계약서 상태 + 주간 근무횟수 병렬 조회
      final allApps = [...pending, ...confirmed];
      Map<String, UserModel> userMap = {};
      Map<String, String?> contractMap = {};
      Map<String, int> weeklyMap = {};

      if (allApps.isNotEmpty) {
        final allUids = allApps.map((a) => a.uid).toSet().toList();
        final allAppIds = allApps.map((a) => a.id).toList();

        // Phase 3 입력값은 Phase 1 결과만 필요 → Phase 2와 병렬로 선제 시작
        final confirmedUserIds = confirmed.map((a) => a.uid).toSet().toList();
        final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

        final idCardFuture = (confirmedUserIds.isNotEmpty && currentUserId.isNotEmpty)
            ? IdCardHelper.loadStatusBatch(
                firestoreService: _svc,
                requesterId: currentUserId,
                targetUserIds: confirmedUserIds,
              )
            : Future.value(<String, String>{});

        final reviewFuture = confirmedUserIds.isNotEmpty
            ? Future.wait(confirmedUserIds.map((uid) async {
                final key = MonthlyReviewModel.generateKeyForUser(
                  businessId: bizId,
                  targetUserId: uid,
                  year: widget.date.year,
                  month: widget.date.month,
                );
                final exists = await _reviewSvc.getReviewById(key);
                return MapEntry(uid, exists != null);
              }))
            : Future.value(<MapEntry<String, bool>>[]);

        final hasWorkedFuture = confirmedUserIds.isNotEmpty
            ? _svc.loadHasWorkedMap(businessId: bizId, date: widget.date)
            : Future.value(<String, bool>{});

        // Phase 2: Phase 3 futures가 이미 실행 중인 상태에서 병렬로 처리됨
        Map<String, int> workDetailCapacityMap = {};
        final results = await Future.wait([
          _svc.getUsersBatch(allUids, businessId: bizId),
          _contractSvc.getContractStatusBatch(allAppIds, businessId: bizId),
          _loadWeeklyCount(bizId),
          _loadWorkDetailCapacities(allApps),
          // [4J.0C] 대기 중 TO 모델 선제 로드 — canApprovePending UI gate용
          _fetchToCacheForPending(pending),
        ]);
        userMap = results[0] as Map<String, UserModel>;
        contractMap = results[1] as Map<String, String?>;
        weeklyMap = results[2] as Map<String, int>;
        workDetailCapacityMap = results[3] as Map<String, int>;

        // Phase 3 결과 수집 (Phase 2와 병렬로 이미 실행 완료됐을 가능성 높음)
        final idCardMap = await idCardFuture;

        final Map<String, bool> reviewMap = {};
        reviewMap.addAll(Map.fromEntries(await reviewFuture));

        // [BUG-CANCEL-01] 당일 근무 여부 맵 — 확정취소 버튼 가드용
        final hasWorkedMap = await hasWorkedFuture;

        final starredFromFirestore =
            allApps.where((app) => app.isStarred).map((app) => app.id).toSet();

        if (!mounted || _selectedBusinessId != bizId) return;
        setState(() {
          _pendingApps = pending;
          _confirmedApps = confirmed;
          _userMap = userMap;
          _contractStatusMap = contractMap;
          _weeklyWorkCountMap = weeklyMap;
          _workDetailCapacityMap = workDetailCapacityMap;
          _idCardStatusMap = idCardMap;
          _reviewWrittenMap.addAll(reviewMap);
          _starredIds.addAll(starredFromFirestore);
          _hasWorkedMap = hasWorkedMap; // [BUG-CANCEL-01]
          _isLoading = false;
          _rebuildGroups();
        });
        return;
      }

      if (!mounted || _selectedBusinessId != bizId) return;
      setState(() {
        _pendingApps = pending;
        _confirmedApps = confirmed;
        _userMap = userMap;
        _contractStatusMap = contractMap;
        _weeklyWorkCountMap = weeklyMap;
        _hasWorkedMap = {}; // [BUG-CANCEL-01] 확정자 없으면 초기화
        _isLoading = false;
        _rebuildGroups();
      });
    } catch (e) {
      debugPrint('❌ 지원명단 로드 실패: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _pendingApps = [];
        _confirmedApps = [];
        _cachedGroups = [];
        _userMap = {};
        _contractStatusMap = {};
        _idCardStatusMap = {};
        _workDetailCapacityMap = {};
        _weeklyWorkCountMap = {};
        _hasWorkedMap = {}; // [BUG-CANCEL-01] 로드 실패 시도 초기화
      });
      ToastHelper.showError('데이터를 불러오지 못했습니다. 다시 시도해주세요.');
    }
  }

  Future<Map<String, int>> _loadWeeklyCount(String bizId) async {
    try {
      final date = widget.date;
      final weekStart = date.subtract(Duration(days: date.weekday - 1));
      final weekEnd = weekStart.add(const Duration(days: 6));
      final result = await _svc.getWeeklyAttendanceByBusiness(
        businessId: bizId,
        weekStart: weekStart,
        weekEnd: weekEnd,
      );
      // Map<String, List<AttendanceModel>> — key = userId
      // 실제 출근 기록만 카운트 (결근·노쇼 제외)
      return result.map((uid, list) => MapEntry(
            uid,
            list
                .where((a) =>
                    a.checkIn != null &&
                    a.status != AttendanceModel.statusAbsent &&
                    a.status != AttendanceModel.statusNoShow)
                .length,
          ));
    } catch (e) {
      debugPrint('⚠️ _loadWeeklyCount 조회 실패 (빈 맵 반환): $e');
      return {};
    }
  }

  /// 슬롯 문서의 workDetails별 requiredCount 맵 반환 (업무 단위 정원 표시용)
  Future<Map<String, int>> _loadWorkDetailCapacities(List<ApplicationModel> allApps) async {
    final toSlotMap = <String, String>{};
    for (final app in allApps) {
      if (app.toId != null && app.slotId != null && !toSlotMap.containsKey(app.toId!)) {
        toSlotMap[app.toId!] = app.slotId!;
      }
    }

    if (toSlotMap.isEmpty) {
      // 장기TO 폴백: TO 문서의 workDetails에서 개별 requiredCount
      final toIds = allApps.where((a) => a.toId != null).map((a) => a.toId!).toSet().toList();
      if (toIds.isEmpty) return {};
      final tos = await Future.wait(toIds.map((id) => _svc.getTO(id)));
      final res = <String, int>{};
      for (var i = 0; i < toIds.length; i++) {
        final to = tos[i];
        if (to == null) continue;
        for (final wd in to.workDetails) {
          final key = wd.id.isNotEmpty ? wd.id : '${wd.workType}_${wd.startTime}_${wd.endTime}';
          res[key] = wd.requiredCount;
        }
      }
      return res;
    }

    final result = <String, int>{};
    await Future.wait(toSlotMap.entries.map((e) async {
      final caps = await _svc.getSlotWorkDetailCapacities(e.key, e.value);
      result.addAll(caps);
    }));
    return result;
  }

  /// [4J.0C] 대기 중 지원서의 TO 모델을 _toCache에 선제 로드
  /// 목적: canApprovePending UI gate (승인 버튼 show/hide, _batchApprove guard)
  /// - 캐시 미적중 시 낙관적 허용 처리 (CF가 최종 차단)
  Future<void> _fetchToCacheForPending(List<ApplicationModel> pending) async {
    final toIds = pending
        .map((a) => a.toId)
        .whereType<String>()
        .toSet()
        .toList();
    if (toIds.isEmpty) return;
    await Future.wait(toIds.map((id) async {
      final to = await _svc.getTO(id);
      if (to != null) _toCache[id] = to;
    }));
  }

  // ── Grouping ───────────────────────────────────────────────────────────────

  void _rebuildGroups() => _cachedGroups = _buildGroups();

  List<_GroupData> _buildGroups() {
    final Map<String, _GroupData> groups = {};

    void addApp(ApplicationModel app, bool isPending) {
      // [8.1E.4] wdId 우선 그룹키 — 동일 wdId 앱은 같은 그룹으로 집계
      final wKey = app.wdId?.isNotEmpty == true
          ? app.wdId!
          : (app.workDetailId?.isNotEmpty == true
              ? app.workDetailId!
              : '${app.selectedWorkType}_${app.startTime}_${app.endTime}');
      final key = '${app.toId ?? app.toTitle}_$wKey';
      // capacity 맵 조회는 composite key 기반 (_workDetailCapacityMap 키 포맷 유지)
      final compositeKey = app.workDetailId?.isNotEmpty == true
          ? app.workDetailId!
          : '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
      groups.putIfAbsent(
        key,
        () => _GroupData(
          toId: app.toId,
          toTitle: app.toTitle,
          workType: app.selectedWorkType,
          startTime: app.startTime,
          endTime: app.endTime,
          isLongTerm: app.isLongTermApplication,
          wdId: app.wdId,
          workDetailId: app.workDetailId,
          requiredCount: _workDetailCapacityMap[compositeKey] ?? 0,
        ),
      );
      if (isPending) {
        groups[key]!.pendingApps.add(app);
      } else {
        groups[key]!.confirmedApps.add(app);
      }
    }

    for (final app in _pendingApps) {
      addApp(app, true);
    }
    for (final app in _confirmedApps) {
      addApp(app, false);
    }

    int timeToMinutes(String t) {
      final parts = t.split(':');
      if (parts.length != 2) return 0;
      return (int.tryParse(parts[0]) ?? 0) * 60 + (int.tryParse(parts[1]) ?? 0);
    }

    return groups.values.toList()
      ..sort((a, b) {
        final t = a.toTitle.compareTo(b.toTitle);
        if (t != 0) return t;
        final s = timeToMinutes(a.startTime).compareTo(timeToMinutes(b.startTime));
        if (s != 0) return s;
        return timeToMinutes(a.endTime).compareTo(timeToMinutes(b.endTime));
      });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _hasChanges);
      },
      child: AppModalShell(
        children: [
          _buildHeader(context),
          if (!_isLoading) _buildStatsStrip(context),
          Expanded(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: LoadingWidget(message: '지원명단 불러오는 중...'),
                  )
                : _buildBody(context),
          ),
          if (!_isLoading && _selectedIds.isNotEmpty)
            _buildBatchActionBar(context),
          _buildBottomBar(context),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return AppModalHeader(
      title: '지원명단',
      subtitle: FormatHelper.formatDateLong(widget.date),
      onClose: () => Navigator.pop(context, _hasChanges),
      trailing: widget.businesses.length > 1
          ? AppSelectField<String>(
              value: _selectedBusinessId,
              hintText: '사업장을 선택하세요',
              sheetTitle: '사업장 선택',
              items: widget.businessIds,
              labelOf: (id) => _bizName(id),
              prefixIcon: Icons.business,
              onChanged: (value) {
                if (value != null && value != _selectedBusinessId) {
                  setState(() => _selectedBusinessId = value);
                  SharedPreferences.getInstance().then(
                    (prefs) => prefs.setString('alfit_last_business_id', value),
                  );
                  _load();
                }
              },
            )
          : null,
    );
  }

  // ── Stats Strip ────────────────────────────────────────────────────────────

  Widget _buildStatsStrip(BuildContext context) {
    final totalCount = _pendingApps.length + _confirmedApps.length;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.grey200)),
      ),
      child: Row(
        children: [
          _statCell(context, '합계', totalCount, AppColors.grey700),
          _statDivider(context),
          _statCell(context, '지원', _pendingApps.length, AppColors.warningDark),
          _statDivider(context),
          _statCell(
              context, '확정', _confirmedApps.length, AppColors.successDark),
          _statDivider(context),
          Material(
            color: _isBatchMode
                ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
                : AppColors.grey100,
            borderRadius: BorderRadius.circular(
                ResponsiveHelper.spacing(context, 8)),
            child: InkWell(
              onTap: () {
                // BATCH-STRIP-01: 일괄 확정 진입 시 canManageTo 확인
                if (!_isBatchMode) {
                  final up = Provider.of<UserProvider>(context, listen: false);
                  if (!up.can((p) => p.canManageTo)) {
                    ToastHelper.showWarning('일괄 확정 권한이 없습니다.');
                    return;
                  }
                }
                setState(() {
                  _isBatchMode = !_isBatchMode;
                  if (!_isBatchMode) {
                    _selectedIds.clear();
                  } else {
                    // 다른 모드와 상호 배제
                    _idCardSelectGroupKey = null;
                    _selectedIdCardUserIds.clear();
                    _contractBatchGroupKey = null;
                  }
                });
              },
              borderRadius: BorderRadius.circular(
                  ResponsiveHelper.spacing(context, 8)),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 8),
                  vertical: ResponsiveHelper.spacing(context, 4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _isBatchMode ? Icons.close : Icons.checklist,
                      size: ResponsiveHelper.iconSize(context, 14),
                      color: _isBatchMode
                          ? Theme.of(context).primaryColor
                          : AppColors.grey600,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Text(
                      _isBatchMode ? '취소' : '일괄선택',
                      style: ResponsiveHelper.smallStyle(
                        context,
                        color: _isBatchMode
                            ? Theme.of(context).primaryColor
                            : AppColors.grey600,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statCell(
      BuildContext context, String label, int count, Color color) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$count명',
              style: ResponsiveHelper.smallStyle(context)
                  .copyWith(fontWeight: FontWeight.bold, color: color)),
          Text(label,
              style:
                  ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
        ],
      ),
    );
  }

  Widget _statDivider(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      color: AppColors.grey200,
      margin: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 8)),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────────

  Widget _buildBody(BuildContext context) {
    if (_pendingApps.isEmpty && _confirmedApps.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: AppEmptyState(
          icon: Icons.people_outline,
          title: '지원자 없음',
          subtitle: '이 날짜에 지원하거나 확정된 근무자가 없습니다.',
        ),
      );
    }
    return _buildListBody(context);
  }

  Widget _buildListBody(BuildContext context) {
    final groups = _cachedGroups;
    if (groups.isEmpty) {
      return const AppEmptyState(
        icon: Icons.people_outline,
        title: '지원자가 없습니다',
      );
    }

    // 공고별로 묶기 (순서 유지)
    final byTO = <String, List<_GroupData>>{};
    for (final g in groups) {
      byTO.putIfAbsent(g.toKey, () => []).add(g);
    }

    final toKeys = byTO.keys.toList();
    return ListView.separated(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      itemCount: toKeys.length,
      separatorBuilder: (_, __) =>
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
      itemBuilder: (_, i) => _buildTOSection(context, byTO[toKeys[i]]!),
    );
  }

  // ── TO Section (공고 헤더 + 업무 서브섹션들) ──────────────────────────────

  Widget _buildTOSection(BuildContext context, List<_GroupData> groups) {
    final first = groups.first;
    final totalPending = groups.fold(0, (s, g) => s + g.pendingApps.length);
    final totalConfirmed = groups.fold(0, (s, g) => s + g.confirmedApps.length);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 공고 헤더 ──
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            decoration: const BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 5),
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: first.isLongTerm
                        ? AppColors.longTermBg
                        : AppColors.shortTermBg,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: first.isLongTerm
                          ? AppColors.longTermDark.withValues(alpha: 0.3)
                          : AppColors.shortTermDark.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    first.isLongTerm ? '장기' : '단기',
                    style: ResponsiveHelper.tinyStyle(
                      context,
                      color: first.isLongTerm
                          ? AppColors.longTermDark
                          : AppColors.shortTermDark,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    first.toTitle.isNotEmpty ? first.toTitle : first.workType,
                    style: ResponsiveHelper.subtitleStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 전체 통계 요약
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (totalPending > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '대기 $totalPending',
                          style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.warning)
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    if (totalConfirmed > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        margin: const EdgeInsets.only(left: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '확정 $totalConfirmed',
                          style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.success)
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          // ── 업무별 서브섹션 ──
          ...groups.asMap().entries.map((e) {
            final isLast = e.key == groups.length - 1;
            return _buildWorkSubSection(context, e.value,
                isLast: isLast, hasMultipleParts: groups.length > 1);
          }),
        ],
      ),
    );
  }

  // ── Work SubSection (업무별 서브섹션) ──────────────────────────────────────

  Widget _buildWorkSubSection(BuildContext context, _GroupData g,
      {required bool isLast, bool hasMultipleParts = false}) {
    final pendingIds = g.pendingApps.map((a) => a.id).toList();
    final allSelected = pendingIds.isNotEmpty &&
        pendingIds.every((id) => _selectedIds.contains(id));
    final someSelected = pendingIds.any((id) => _selectedIds.contains(id));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── 업무 서브헤더 ──
        GestureDetector(
          onTap: (!_isBatchMode || pendingIds.isEmpty)
              ? null
              : () => setState(() {
                    if (allSelected) {
                      _selectedIds.removeAll(pendingIds);
                    } else {
                      _selectedIds.addAll(pendingIds);
                    }
                  }),
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              border: Border(
                left: BorderSide(color: AppColors.info, width: 3),
              ),
            ),
            child: Row(
              children: [
                if (_isBatchMode && pendingIds.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: AppCheckbox(
                      value: allSelected || someSelected,
                      activeColor: someSelected && !allSelected
                          ? AppColors.grey400
                          : null,
                    ),
                  ),
                // 업무명 + 시간
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        g.workType,
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${g.startTime} ~ ${g.endTime}',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey500),
                      ),
                    ],
                  ),
                ),
                // 업무별 통계 배지
                _buildGroupStats(context, g),
              ],
            ),
          ),
        ),

        // ── [Phase 8.1B.3] 인력 초대 버튼 (단기 + 부족 시에만 표시) ──
        if (!g.isLongTerm && g.toId != null && g.requiredCount > 0 &&
            g.requiredCount > g.confirmedApps.length)
          Builder(builder: (ctx) {
            final slotId = g.confirmedApps.isNotEmpty
                ? g.confirmedApps.first.slotId
                : (g.pendingApps.isNotEmpty
                    ? g.pendingApps.first.slotId
                    : null);
            if (slotId == null) return const SizedBox.shrink();
            final up = Provider.of<UserProvider>(ctx, listen: false);
            if (!up.can((p) => p.canManageTo)) return const SizedBox.shrink();
            return _buildInviteButton(g, slotId);
          }),

        // ── 대기 중 섹션 ──
        if (g.pendingApps.isNotEmpty) ...[
          _sectionDivider(
              context, '대기 중 (${g.pendingApps.length}명)', AppColors.warning),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8)),
            child: Column(
              children: g.pendingApps
                  .asMap()
                  .entries
                  .map((e) => _buildApplicantCard(context, e.value,
                      isPending: true, index: e.key + 1))
                  .toList(),
            ),
          ),
        ],

        // ── 확정 섹션 ──
        if (g.confirmedApps.isNotEmpty) ...[
          _sectionDivider(
              context, '확정 (${g.confirmedApps.length}명)', AppColors.success),
          Builder(builder: (ctx) {
            final requestableCount = g.confirmedApps.where((app) {
              final user = _userMap[app.uid];
              if (user == null) return false;
              return IdCardHelper.isRequestable(
                  _idCardStatusMap[user.uid] ?? 'none');
            }).length;
            if (requestableCount == 0) return const SizedBox.shrink();
            return _buildIdCardRequestSection(ctx, g, requestableCount);
          }),
          Builder(builder: (ctx) {
            final noContractCount = g.confirmedApps.where((app) {
              final status = _contractStatusMap[app.id];
              return status == null || status.isEmpty || status == 'voided';
            }).length;
            if (noContractCount == 0) return const SizedBox.shrink();
            return _buildContractBatchSection(ctx, g, noContractCount);
          }),
          Padding(
            padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8)),
            child: Column(
              children: g.confirmedApps
                  .asMap()
                  .entries
                  .map((e) => _buildApplicantCard(context, e.value,
                      isPending: false,
                      isGroupIdCardMode: _idCardSelectGroupKey == g.groupKey,
                      index: e.key + 1,
                      hasMultipleParts: hasMultipleParts))
                  .toList(),
            ),
          ),
        ],

        // ── 구분선 (마지막 업무 섹션 제외) ──
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.border,
            indent: ResponsiveHelper.spacing(context, 12),
            endIndent: ResponsiveHelper.spacing(context, 12),
          )
        else
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
      ],
    );
  }

  Widget _sectionDivider(BuildContext context, String label, Color color) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      child: Row(
        children: [
          Container(
              width: 3,
              height: 12,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 6),
          Text(label,
              style: ResponsiveHelper.smallStyle(context, color: color)
                  .copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ── [Phase 8.1B.3] 인력 초대 버튼 + InviteMethodSheet 라우팅 ─────────────

  Widget _buildInviteButton(_GroupData g, String slotId) {
    final shortage = g.requiredCount - g.confirmedApps.length;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: OutlinedButton.icon(
        onPressed: () => _openInviteMethod(g, slotId),
        icon: const Icon(Icons.person_add_outlined, size: 16),
        label: Text('인력 초대 ($shortage명 부족)'),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.info,
          side: const BorderSide(color: AppColors.info),
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        ),
      ),
    );
  }

  Future<void> _openInviteMethod(_GroupData g, String slotId) async {
    if (!mounted) return;
    final shortage = (g.requiredCount - g.confirmedApps.length).clamp(0, 99);

    // 1. 인력 초대 방식 선택 시트 — State.context 사용 (mounted 보장)
    final choice = await DialogHelper.showSheet<String>(
      context,
      builder: (ctx) => InviteMethodSheet(
        workType: g.workType,
        date: widget.date,
        startTime: g.startTime,
        endTime: g.endTime,
        shortage: shortage,
      ),
    );

    if (!mounted || choice == null) return;

    // 사업장명 취득
    final biz = widget.businesses.where((b) => b.id == _selectedBusinessId)
        .isNotEmpty
        ? widget.businesses.firstWhere((b) => b.id == _selectedBusinessId)
        : (widget.businesses.isNotEmpty ? widget.businesses.first : null);
    final businessName = biz?.name ?? '';

    if (choice == 'availability') {
      // 2a. 근무 가능 인력 시트
      if (!mounted) return;
      await DialogHelper.showSheet<void>(
        context,
        isScrollControlled: true,
        builder: (ctx) => AvailableWorkersBottomSheet(
          toId: g.toId!,
          slotId: slotId,
          workDetailId: g.workDetailId,
          businessId: _selectedBusinessId ?? '',
          date: widget.date,
          workType: g.workType,
          startTime: g.startTime,
          endTime: g.endTime,
          requiredCount: g.requiredCount,
          confirmedCount: g.confirmedApps.length,
        ),
      );
    } else if (choice == 'direct') {
      // 2b. 직접 초대 다이얼로그 (contextual mode — 날짜·슬롯 재선택 없음)
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => InviteWorkerDialog.contextual(
          toId: g.toId!,
          businessId: _selectedBusinessId ?? '',
          businessName: businessName,
          date: widget.date,
          slotId: slotId,
          workType: g.workType,
          startTime: g.startTime,
          endTime: g.endTime,
        ),
      );
    }
  }

  // ── Applicant Card ─────────────────────────────────────────────────────────

  Widget _buildApplicantCard(BuildContext context, ApplicationModel app,
      {required bool isPending, bool isGroupIdCardMode = false, int index = 0, bool hasMultipleParts = false}) {
    final user = _userMap[app.uid];
    final isSelected = _selectedIds.contains(app.id);
    final isStarred = isPending && _starredIds.contains(app.id);
    final idCardStatus = _idCardStatusMap[user?.uid ?? ''] ?? 'none';
    final up = Provider.of<UserProvider>(context, listen: false);
    final canManageTo = up.can((p) => p.canManageTo);
    final canManageContract = up.can((p) => p.canManageContract);

    final Color cardBg;
    final Color cardBorder;
    final double borderWidth;
    if (isSelected) {
      cardBg = AppColors.warningBg;
      cardBorder = AppColors.warning;
      borderWidth = 1.5;
    } else if (isStarred) {
      cardBg = AppColors.amber.withValues(alpha: 0.1);
      cardBorder = AppColors.amberLight;
      borderWidth = 1.0;
    } else if (!isPending) {
      cardBg = AppColors.successBg.withValues(alpha: 0.35);
      cardBorder = AppColors.successLight.withValues(alpha: 0.7);
      borderWidth = 1.0;
    } else {
      cardBg = Colors.white;
      cardBorder = AppColors.grey200;
      borderWidth = 1.0;
    }

    return GestureDetector(
      onTap: () {
        if (isPending && _isBatchMode) {
          setState(() {
            if (isSelected) {
              _selectedIds.remove(app.id);
            } else {
              _selectedIds.add(app.id);
            }
          });
        } else if (!isPending && isGroupIdCardMode &&
            IdCardHelper.isRequestable(idCardStatus)) {
          _toggleIdCardSelection(user?.uid ?? '');
        } else {
          _showWorkerDetail(app, user, isPending: isPending);
        }
      },
      child: Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 4)),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 10),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: cardBorder, width: borderWidth),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Row 1: 체크박스/점 + 이름 + 나이성별 + 시간 + 별/리뷰 ──
            Row(
              children: [
                if (isPending)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _isBatchMode
                        ? ResponsiveHelper.spacing(context, 26)
                        : 0,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    child: _isBatchMode
                        ? Padding(
                            padding: EdgeInsets.only(
                                right: ResponsiveHelper.spacing(context, 6)),
                            child: AppCheckbox(
                              value: isSelected,
                              onTap: () => setState(() {
                                if (isSelected) {
                                  _selectedIds.remove(app.id);
                                } else {
                                  _selectedIds.add(app.id);
                                }
                              }),
                            ),
                          )
                        : const SizedBox.shrink(),
                  )
                else if (isGroupIdCardMode)
                  Padding(
                    padding: EdgeInsets.only(
                        right: ResponsiveHelper.spacing(context, 6)),
                    child: IdCardHelper.isRequestable(idCardStatus)
                        ? AppCheckbox(
                            value: _selectedIdCardUserIds
                                .contains(user?.uid ?? ''),
                            onTap: () =>
                                _toggleIdCardSelection(user?.uid ?? ''),
                            activeColor: AppColors.info,
                          )
                        : SizedBox(
                            width: ResponsiveHelper.spacing(context, 22)),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      '$index.',
                      style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.grey400)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          user?.name ?? '근무자',
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (_genderAge(user).isNotEmpty) ...[
                        const SizedBox(width: 3),
                        Text(_genderAge(user),
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.grey500)),
                      ],
                    ],
                  ),
                ),
                Text(
                  _timeAgo(app.appliedAt),
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey400),
                ),
                if (isPending)
                  GestureDetector(
                    onTap: () async {
                      final nowStarred = !_starredIds.contains(app.id);
                      setState(() {
                        if (nowStarred) { _starredIds.add(app.id); }
                        else { _starredIds.remove(app.id); }
                      });
                      try {
                        await _svc.updateApplicationFields(
                            app.id, {'isStarred': nowStarred});
                      } catch (e) {
                        if (mounted) {
                          setState(() {
                            if (nowStarred) { _starredIds.remove(app.id); }
                            else { _starredIds.add(app.id); }
                          });
                          ToastHelper.showError('별 표시 저장에 실패했습니다');
                        }
                      }
                    },
                    behavior: HitTestBehavior.opaque,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        ResponsiveHelper.spacing(context, 5),
                        2,
                        0,
                        2,
                      ),
                      child: Icon(
                        isStarred
                            ? Icons.star_rounded
                            : Icons.star_border_rounded,
                        size: ResponsiveHelper.iconSize(context, 16),
                        color: isStarred ? AppColors.amber : AppColors.grey300,
                      ),
                    ),
                  ),
              ],
            ),

            // ── Row 2: 정보 (신뢰점수·전화·주간횟수·별점) ──
            const SizedBox(height: 4),
            Wrap(
              spacing: 5,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (user?.effectivePhone != null && user!.effectivePhone!.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.phone_outlined,
                        size: 10, color: AppColors.grey400),
                    const SizedBox(width: 2),
                    Text(FormatHelper.formatPhone(user.effectivePhone!),
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.grey600)),
                  ]),
                if (user != null && user.recentNoShowCount > 0)
                  _buildNoShowBadge(context, user.recentNoShowCount),
                _weeklyCountBadge(context, app.uid),
                if (user != null && user.averageRating > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.star_rounded,
                        size: 11, color: AppColors.amber),
                    const SizedBox(width: 2),
                    Text(
                      user.averageRating.toStringAsFixed(1),
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey700),
                    ),
                  ]),
              ],
            ),

            // ── Row 3: 배지 (리뷰·계약·신분증) — 정보 라인과 분리, Wrap 자동 줄바꿈 ──
            const SizedBox(height: 3),
            Wrap(
              spacing: 4,
              runSpacing: 3,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (!isPending) _buildReviewBadge(context, user?.uid),
                _contractBadge(context, app.id, isPending: isPending),
                if (!isPending)
                  IdCardHelper.buildStatusBadge(context, idCardStatus),
              ],
            ),

            // ── Row 4: 액션 버튼 ──
            // [4J.0C] 거절: 항상 허용(PENDING 정리), 승인: canApprovePending만 허용 — WorkApplicants parity
            // _toCache에 TO가 없으면 true(낙관적 허용) — CF가 최종 gate
            if (isPending && !_isBatchMode && canManageTo) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _actionButton(
                    context,
                    label: '거절',
                    color: AppColors.error,
                    onTap: () => _rejectApp(app),
                  ),
                  if (_toCache[app.toId]?.canApprovePending ?? true) ...[
                    const SizedBox(width: 8),
                    _actionButton(
                      context,
                      label: '승인',
                      color: AppColors.success,
                      filled: true,
                      onTap: () => _approveApp(app),
                    ),
                  ],
                ],
              ),
            ] else if (!isPending) ...[
              // [BUG-CANCEL-01] 계약서 작성·확정취소·파트변경 중 하나라도 표시할 때 Row 렌더링
              if ((((_contractStatusMap[app.id] == null ||
                          _contractStatusMap[app.id]!.isEmpty ||
                          _contractStatusMap[app.id] == 'voided') &&
                      canManageContract) ||
                  (_canCancelConfirmation(app) && canManageTo) ||
                  (app.toId != null && hasMultipleParts && canManageTo))) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    // 계약 미작성 시 개별 계약서 작성 버튼
                    if ((_contractStatusMap[app.id] == null ||
                        _contractStatusMap[app.id]!.isEmpty ||
                        _contractStatusMap[app.id] == 'voided') &&
                        canManageContract) ...[
                      _actionButton(
                        context,
                        label: '계약서 작성',
                        color: AppColors.success,
                        filled: true,
                        onTap: () => _createContractForOne(app),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // [BUG-CANCEL-01] 근무 완료·장기계약 시작 후에는 확정취소 버튼 숨김
                    if (_canCancelConfirmation(app) && canManageTo) ...[
                      _actionButton(
                        context,
                        label: '확정취소',
                        color: AppColors.error,
                        onTap: () => _cancelConfirmation(app),
                      ),
                      if (app.toId != null && hasMultipleParts) const SizedBox(width: 8),
                    ],
                    // 파트변경 버튼 — TO 소속이고 다른 파트가 있는 경우에만 표시
                    if (app.toId != null && hasMultipleParts && canManageTo)
                      _actionButton(
                        context,
                        label: '파트변경',
                        color: AppColors.info,
                        onTap: () => _showChangeWorkPartDialog(app, _userMap[app.uid]),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required String label,
    required Color color,
    bool filled = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: _isProcessing ? null : onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: filled ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.7)),
        ),
        child: Text(
          label,
          style: ResponsiveHelper.smallStyle(
                  context, color: filled ? Colors.white : color)
              .copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  // ── Badges ─────────────────────────────────────────────────────────────────

  Widget _weeklyCountBadge(BuildContext context, String uid) {
    final count = _weeklyWorkCountMap[uid] ?? 0;
    final Color color;
    final Color bgColor;
    final IconData icon;
    if (count == 0) {
      color = AppColors.grey500;
      bgColor = AppColors.grey100;
      icon = Icons.calendar_today_outlined;
    } else if (count <= 2) {
      color = AppColors.successDark;
      bgColor = AppColors.successBg;
      icon = Icons.calendar_today;
    } else if (count <= 4) {
      color = AppColors.infoDark;
      bgColor = AppColors.infoBg;
      icon = Icons.calendar_today;
    } else {
      color = AppColors.warningDark;
      bgColor = AppColors.warningBg;
      icon = Icons.calendar_today;
    }
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 10), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text('주$count회',
              style: ResponsiveHelper.tinyStyle(context, color: color)
                  .copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // 노쇼 팩트 배지 (신뢰도 점수 대체 — 5A.2A)
  Widget _buildNoShowBadge(BuildContext context, int count) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: AppColors.errorBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.warning_amber_rounded,
              size: ResponsiveHelper.iconSize(context, 10),
              color: AppColors.error),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text('최근 90일 노쇼 $count회',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.error)
                  .copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _contractBadge(BuildContext context, String appId,
      {bool isPending = false}) {
    final status = _contractStatusMap[appId];
    if (status == null || status.isEmpty) {
      if (!isPending) {
        return _iconChip(context,
            icon: Icons.assignment_late_outlined,
            label: '계약미작성',
            color: AppColors.error);
      }
      return const SizedBox.shrink();
    }
    switch (status) {
      case 'pending_worker':
        return _iconChip(context,
            icon: Icons.draw_outlined,
            label: '서명대기',
            color: AppColors.warningDark);
      case 'pending_employer':
        return _chip(context,
            label: '관리자서명',
            color: AppColors.warningDark,
            bgColor: AppColors.warningDark.withValues(alpha: 0.1));
      case 'completed':
        return _chip(context,
            label: '계약완료',
            color: AppColors.successDark,
            bgColor: AppColors.successDark.withValues(alpha: 0.1));
      case 'voided':
        return _chip(context,
            label: '무효',
            color: AppColors.error,
            bgColor: AppColors.errorBg);
      default:
        return _chip(context,
            label: '계약중',
            color: AppColors.grey600,
            bgColor: AppColors.grey600.withValues(alpha: 0.1));
    }
  }

  // 아이콘 + 텍스트 조합 칩 — 액션이 필요한 계약 상태(미작성·서명대기)에 사용
  Widget _iconChip(BuildContext context,
      {required IconData icon, required String label, required Color color}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 9, color: color),
          const SizedBox(width: 2),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: color)
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewBadge(BuildContext context, String? uid) {
    if (uid == null || !_reviewWrittenMap.containsKey(uid)) {
      return const SizedBox.shrink();
    }
    final written = _reviewWrittenMap[uid]!;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: written
            ? AppColors.successDark.withValues(alpha: 0.12)
            : AppColors.warningDark.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            written ? Icons.rate_review : Icons.rate_review_outlined,
            size: ResponsiveHelper.iconSize(context, 10),
            color: written ? AppColors.successDark : AppColors.warningDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 2)),
          Text(
            written ? '리뷰완료' : '리뷰미작성',
            style: ResponsiveHelper.tinyStyle(
              context,
              color: written ? AppColors.successDark : AppColors.warningDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context,
      {required String label,
      required Color color,
      required Color bgColor}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 5),
        vertical: 1,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(label,
          style: ResponsiveHelper.tinyStyle(context, color: color)
              .copyWith(fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildGroupStats(BuildContext context, _GroupData g) {
    final confirmed = g.confirmedApps.length;
    final pending = g.pendingApps.length;
    final required = g.requiredCount;
    final isFull = required > 0 && confirmed >= required;
    final statusColor = isFull ? AppColors.successDark : AppColors.infoDark;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          isFull ? Icons.check_circle : Icons.people_outline,
          size: ResponsiveHelper.iconSize(context, 14),
          color: statusColor,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        Text(
          required > 0 ? '$confirmed/$required명' : '$confirmed명',
          style: ResponsiveHelper.smallStyle(context, color: statusColor)
              .copyWith(fontWeight: FontWeight.bold),
        ),
        if (pending > 0) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Icon(
            Icons.schedule,
            size: ResponsiveHelper.iconSize(context, 12),
            color: AppColors.warningDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 2)),
          Text(
            '+$pending',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark)
                .copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ],
    );
  }

  // ── ID Card Request ────────────────────────────────────────────────────────

  Widget _buildIdCardRequestSection(
      BuildContext context, _GroupData g, int requestableCount) {
    final isActive = _idCardSelectGroupKey == g.groupKey;
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: isActive ? AppColors.infoBg : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isActive ? AppColors.info : AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.badge,
              size: ResponsiveHelper.iconSize(context, 18),
              color: AppColors.info),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              isActive
                  ? '${_selectedIdCardUserIds.length}명 선택됨'
                  : '미요청 $requestableCount명',
              style:
                  ResponsiveHelper.bodyStyle(context, color: AppColors.infoDark),
            ),
          ),
          if (isActive && _selectedIdCardUserIds.isNotEmpty) ...[
            InkWell(
              onTap: _batchRequestIdCard,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 6),
                ),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('요청하기',
                    style: ResponsiveHelper.smallStyle(context,
                            color: Colors.white)
                        .copyWith(fontWeight: FontWeight.w600)),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          ],
          InkWell(
            onTap: () {
              setState(() {
                if (isActive) {
                  _idCardSelectGroupKey = null;
                  _selectedIdCardUserIds.clear();
                } else {
                  _idCardSelectGroupKey = g.groupKey;
                  _selectAllRequestableUsers(g);
                  // 다른 모드와 상호 배제
                  _isBatchMode = false;
                  _selectedIds.clear();
                  _contractBatchGroupKey = null;
                }
              });
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: ResponsiveHelper.spacing(context, 6),
              ),
              decoration: BoxDecoration(
                color: isActive ? AppColors.grey100 : AppColors.info,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                isActive ? '취소' : '신분증 요청',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: isActive ? AppColors.grey700 : Colors.white,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _selectAllRequestableUsers(_GroupData g) {
    _selectedIdCardUserIds.clear();
    for (final app in g.confirmedApps) {
      final user = _userMap[app.uid];
      if (user == null) continue;
      if (IdCardHelper.isRequestable(_idCardStatusMap[user.uid] ?? 'none')) {
        _selectedIdCardUserIds.add(user.uid);
      }
    }
  }

  void _toggleIdCardSelection(String uid) {
    setState(() {
      if (_selectedIdCardUserIds.contains(uid)) {
        _selectedIdCardUserIds.remove(uid);
      } else {
        _selectedIdCardUserIds.add(uid);
      }
    });
  }

  Future<void> _batchRequestIdCard() async {
    if (_isProcessing) return;
    if (_selectedIdCardUserIds.isEmpty) return;
    final currentUser = context.read<UserProvider>().currentUser;
    if (currentUser == null) {
      ToastHelper.showError('로그인이 필요합니다');
      return;
    }
    final bizId = _selectedBusinessId ?? '';
    if (bizId.isEmpty || widget.businesses.isEmpty) {
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
      return;
    }
    // [특이사항] orElse 폴백 제거 — bizId가 widget.businesses에 없으면 중단.
    // 폴백으로 첫 번째 사업장을 사용하면 잘못된 사업장 명의로 신분증 요청이 생성된다.
    final bizIdx = widget.businesses.indexWhere((b) => b.id == bizId);
    if (bizIdx < 0) return;
    final business = widget.businesses[bizIdx];

    // 선택된 사용자 정보 수집 — 확정 앱 우선, uid 중복 스킵
    final targets = <Map<String, String>>[];
    final seenUids = <String>{};
    for (final app in [..._confirmedApps, ..._pendingApps]) {
      final user = _userMap[app.uid];
      if (user == null || !_selectedIdCardUserIds.contains(user.uid)) continue;
      if (!seenUids.add(user.uid)) continue;
      targets.add({
        'uid': user.uid,
        'name': user.name,
        'applicationId': app.id,
      });
    }

    if (targets.isEmpty) {
      ToastHelper.showWarning('요청 가능한 대상이 없습니다');
      return;
    }

    if (!mounted) return;
    setState(() => _isProcessing = true);
    try {
      final successCount = await IdCardHelper.showBatchRequestDialog(
        context: context,
        firestoreService: _svc,
        requester: {'uid': currentUser.uid, 'name': currentUser.name},
        business: {'id': bizId, 'name': business.name},
        targets: targets,
      );

      if (!mounted) return;
      if (successCount > 0) {
        _hasChanges = true;
        setState(() {
          for (final uid in _selectedIdCardUserIds) {
            _idCardStatusMap[uid] = 'pending';
          }
          _idCardSelectGroupKey = null;
          _selectedIdCardUserIds.clear();
          _isProcessing = false;
        });
      }
    } catch (e) {
      debugPrint('❌ [day_batchRequestIdCard] 신분증 요청 실패: $e');
      if (mounted) ToastHelper.showError('신분증 요청 중 오류가 발생했습니다');
    } finally {
      if (mounted && _isProcessing) setState(() => _isProcessing = false);
    }
  }

  // ── Contract Batch Section ─────────────────────────────────────────────────

  Widget _buildContractBatchSection(
      BuildContext context, _GroupData g, int noContractCount) {
    final isProcessing = _contractBatchGroupKey == g.groupKey;
    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined,
              size: ResponsiveHelper.iconSize(context, 18),
              color: AppColors.success),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              '계약서 미작성 $noContractCount명',
              style: ResponsiveHelper.bodyStyle(context,
                  color: AppColors.successDark),
            ),
          ),
          if (isProcessing)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            InkWell(
              onTap: () => _batchCreateContracts(g),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 6),
                ),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '계약서 일괄작성',
                  style: ResponsiveHelper.smallStyle(context, color: Colors.white)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _batchCreateContracts(_GroupData g) async {
    // BATCH-CONTRACT-01: 계약서 일괄작성 권한 확인
    final up = Provider.of<UserProvider>(context, listen: false);
    if (!up.can((p) => p.canManageContract)) {
      ToastHelper.showWarning('계약서 관리 권한이 없습니다.');
      return;
    }
    if (_contractBatchGroupKey != null) return;
    final bizId = _selectedBusinessId ?? '';
    if (bizId.isEmpty || widget.businesses.isEmpty) {
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
      return;
    }
    // [특이사항] orElse 폴백 제거 — 잘못된 bizId 시 첫 번째 사업장 명의로 계약서가 생성되는 것을 방지.
    final bizIdx = widget.businesses.indexWhere((b) => b.id == bizId);
    if (bizIdx < 0) return;
    final business = widget.businesses[bizIdx];

    // 계약서 미작성 또는 무효 확정자 수집
    final toProcess = g.confirmedApps.where((app) {
      final status = _contractStatusMap[app.id];
      return status == null || status.isEmpty || status == 'voided';
    }).toList();
    if (toProcess.isEmpty) return;

    setState(() => _contractBatchGroupKey = g.groupKey);
    try {
      List<ContractArticle>? articles;
      String sealBase64 = '';
      String sealType = 'stamp';
      WorkDetailData? workDetail;

      // 1. 템플릿 선택
      articles =
          await ContractTemplateSelectorDialog.show(context, businessId: bizId);
      if (articles == null || !mounted) return;

      // 2. 인감 확인 — SubAdmin은 사업주(ownerId) 문서에서 날인 조회
      final sealUid = up.isSubAdmin ? business.ownerId : (up.currentUser?.uid ?? '');
      if (sealUid.isNotEmpty) {
        final sealDoc = await FirebaseFirestore.instance.collection('users').doc(sealUid).get();
        if (!mounted) return;
        sealBase64 = sealDoc.data()?['sealBase64'] ?? '';
        sealType = sealDoc.data()?['sealType'] ?? 'stamp';
      }
      if (sealBase64.isEmpty) {
        if (!mounted) return;
        final goSettings = await DialogHelper.showConfirm(
          context,
          title: '사업주 날인 미등록',
          message: up.isSubAdmin
              ? '일괄 계약 발송에는 사업주 날인이 필요합니다.\n사업주에게 날인 등록을 요청해주세요.'
              : '일괄 계약 발송에는 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 또는 서명을 먼저 등록해주세요.',
          confirmText: up.isSubAdmin ? '확인' : '설정으로 이동',
          cancelText: '취소',
        );
        if (!mounted) return;
        if (goSettings && !up.isSubAdmin) {
          Navigator.of(context, rootNavigator: true)
              .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
        }
        return;
      }

      // 3. TO에서 WorkDetailData 조회
      if (g.toId != null) {
        final to = await _svc.getTO(g.toId!);
        if (to != null && to.workDetails.isNotEmpty) {
          workDetail = to.workDetails
              .where((w) =>
                  w.workType == g.workType &&
                  w.startTime == g.startTime &&
                  w.endTime == g.endTime)
              .firstOrNull;
        }
      }
      if (!mounted) return;

      if (workDetail == null) {
        ToastHelper.showError('근무 유형 정보를 찾을 수 없습니다. TO를 확인해 주세요.');
        return;
      }

      // 4. 첫 번째 대상으로 미리보기 생성
      final firstApp = toProcess.first;
      final firstUser = _userMap[firstApp.uid];
      if (firstUser == null) {
        ToastHelper.showError('지원자 정보를 불러올 수 없습니다');
        return;
      }

      late EmploymentContractModel previewContract;
      try {
        previewContract = await ContractService().buildPreviewContract(
          application: firstApp,
          business: business,
          worker: firstUser,
          workDetail: workDetail,
          articles: articles,
        );
      } catch (e) {
        if (mounted) ToastHelper.showError('계약서 미리보기 생성에 실패했습니다');
        return;
      }
      if (!mounted) return;

      // 5. 미리보기 다이얼로그
      final confirmed = await _showBatchContractPreview(
        contract: previewContract,
        sealBase64: sealBase64,
        sealType: sealType,
        count: toProcess.length,
      );
      if (confirmed != true || !mounted) return;

      // 6. 일괄 계약서 생성 + 날인
      final sealBytes = base64Decode(sealBase64);
      final finalWorkDetail = workDetail;

      Future<bool> processOne(ApplicationModel app) async {
        final user = _userMap[app.uid];
        if (user == null) return false;
        try {
          final contract = await ContractService().findOrCreateContract(
            application: app,
            business: business,
            worker: user,
            workDetail: finalWorkDetail,
            articles: articles!,
          );
          await ContractService().saveEmployerSignature(
            contract: contract,
            signatureBytes: sealBytes,
          );
          return true;
        } catch (e) {
          debugPrint('❌ [${app.id}] 계약서 발송 실패: $e');
          return false;
        }
      }

      const batchSize = 5;
      int successCount = 0;
      final List<ApplicationModel> successApps = [];
      for (var i = 0; i < toProcess.length; i += batchSize) {
        final batch =
            toProcess.sublist(i, min(i + batchSize, toProcess.length));
        final results = await Future.wait(batch.map(processOne));
        if (!mounted) return;
        for (var j = 0; j < batch.length; j++) {
          if (results[j]) {
            successCount++;
            successApps.add(batch[j]);
          }
        }
      }

      if (!mounted) return;
      if (successCount < toProcess.length) {
        ToastHelper.showWarning(
            '$successCount/${toProcess.length}명 계약서 발송 완료. 실패한 항목은 다시 시도해주세요.');
      } else {
        ToastHelper.showSuccess('${toProcess.length}명에게 계약서가 발송되었습니다');
      }
      if (successCount > 0) {
        _hasChanges = true;
        setState(() {
          for (final app in successApps) {
            _contractStatusMap[app.id] = 'pending_worker';
          }
        });
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리 중 오류가 발생했습니다');
      debugPrint('❌ 계약서 일괄 발송 실패: $e');
    } finally {
      if (mounted) setState(() => _contractBatchGroupKey = null);
    }
  }

  Future<bool?> _showBatchContractPreview({
    required EmploymentContractModel contract,
    required String sealBase64,
    String sealType = 'stamp',
    required int count,
  }) {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false, // CSN-06: 미리보기 중 실수 닫힘 방지 (취소 버튼으로만 닫기)
      builder: (ctx) => Dialog(
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 32),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
              decoration: BoxDecoration(
                color: Theme.of(ctx).primaryColor,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined,
                      color: Colors.white, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '근로계약서 미리보기',
                      style: ResponsiveHelper.subtitleStyle(ctx).copyWith(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    icon: const Icon(Icons.close,
                        color: Colors.white, size: 20),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              color: AppColors.info.withValues(alpha: 0.08),
              child: Text(
                '아래 조건으로 선택된 $count명에게 계약서가 발송됩니다.\n이름·생년월일 등 개인정보는 각 근무자별로 적용됩니다.',
                style: ResponsiveHelper.smallStyle(ctx, color: AppColors.info),
                textAlign: TextAlign.center,
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: ContractTemplateWidget(
                  snapshot: contract.snapshot,
                  contractDate: contract.createdAt,
                  slots: contract.slots,
                  articles: contract.articles,
                  employerSignatureUrl: contract.employerSignatureUrl,
                  employerSealBase64: sealBase64,
                  employerSealType: sealType,
                  workerSignatureUrl: contract.workerSignatureUrl,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('취소'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text('$count명에게 발송'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── 확정 취소 ──────────────────────────────────────────────────────────────

  /// [BUG-CANCEL-01] 확정취소 가능 여부 판단
  ///
  /// 단기 근무: 당일 checkIn 기록이 있으면 이미 근무한 것 → 취소 불가
  /// 장기 근무: 계약 시작일(workDate)이 widget.date 이전이면 이미 근무 시작 → 취소 불가
  ///            (workDate == widget.date는 첫 근무일 당일 — 아직 출근 전이면 취소 허용)
  bool _canCancelConfirmation(ApplicationModel app) {
    // 당일 출근 기록 체크 (단기·장기 공통)
    if (_hasWorkedMap[app.uid] == true) return false;
    // 장기 근무자: 계약 시작일 이후 날짜를 보고 있는 경우 취소 불가
    // [특이사항] workEndDate == null 인 무기한 계약도 동일하게 처리됨
    if (app.isLongTermApplication) {
      // [BUG-FIX] workDate 직접 사용 → desiredStartDate ?? workDate
      // desiredStartDate는 희망 시작일(슬롯 날짜), workDate는 계약 기본 날짜
      // 장기 근무자가 특정 슬롯 날짜부터 시작하는 경우 desiredStartDate가 실제 시작일
      final effectiveStart = app.desiredStartDate ?? app.workDate;
      final contractStart = DateTime(
          effectiveStart.year, effectiveStart.month, effectiveStart.day);
      final viewDate = DateTime(
          widget.date.year, widget.date.month, widget.date.day);
      if (contractStart.isBefore(viewDate)) return false;
    }
    return true;
  }

  /// 파트변경 다이얼로그 (TO 소속 확정자 전용)
  Future<void> _showChangeWorkPartDialog(ApplicationModel app, UserModel? user) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);

    // TO 및 workDetails 로드 (캐시 우선 — 재탭 시 서버 읽기 생략)
    final toId = app.toId!;
    final to = _toCache[toId] ?? await _svc.getTO(toId);
    if (!mounted) return;
    if (to == null || to.workDetails.isEmpty) {
      setState(() => _isProcessing = false);
      ToastHelper.showError('공고 정보를 불러올 수 없습니다.');
      return;
    }
    _toCache[toId] = to;
    final workDetails = to.workDetails;

    // 현재 파트 식별 (workDetailId 우선, 없으면 selectedWorkType 폴백)
    final idx = workDetails.indexWhere(
      (w) => w.id == app.workDetailId || w.workType == app.selectedWorkType,
    );
    final currentWork = idx >= 0 ? workDetails[idx] : null;

    // 현재 파트 제외한 다른 파트 목록
    final otherWorkDetails = currentWork != null
        ? workDetails.where((w) => w.id != currentWork.id).toList()
        : List<WorkDetailData>.from(workDetails);

    if (otherWorkDetails.isEmpty) {
      setState(() => _isProcessing = false);
      ToastHelper.showWarning('변경 가능한 다른 파트가 없습니다.');
      return;
    }

    // [C-1] 파트변경 전 급여 상태 확인 — confirmed: 완전 차단 / calculated: 경고 후 선택
    final int confirmedCount;
    final int calculatedCount;
    try {
      final wageCountResult = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetWageStatusCount')
          .call({'applicationId': app.id, 'businessId': app.businessId});
      final resultMap = wageCountResult.data as Map;
      confirmedCount  = resultMap['confirmedCount']  as int? ?? 0;
      calculatedCount = resultMap['calculatedCount'] as int? ?? 0;
    } catch (e) {
      debugPrint('❌ 급여 상태 확인 실패: $e');
      if (mounted) {
        setState(() => _isProcessing = false);
        ToastHelper.showError('급여 상태 확인 중 오류가 발생했습니다. 다시 시도해주세요.');
      }
      return;
    }
    if (!mounted) return;

    if (confirmedCount > 0) {
      setState(() => _isProcessing = false);
      await DialogHelper.showError(
        context,
        title: '파트변경 불가',
        message: '마감 처리된 급여가 $confirmedCount건 있습니다.\n먼저 마감을 취소한 후 다시 시도해주세요.',
      );
      return;
    }

    if (calculatedCount > 0) {
      final proceed = await DialogHelper.showConfirm(
        context,
        title: '임금 계산 초기화 안내',
        message: '계산된 급여 $calculatedCount건이 있습니다.\n파트변경 시 해당 급여가 초기화되어 재계산이 필요합니다.\n계속하시겠습니까?',
        confirmText: '계속',
        cancelText: '취소',
      );
      if (proceed != true || !mounted) {
        if (mounted) setState(() => _isProcessing = false);
        return;
      }
    }

    final selectedWorkId = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StyledDialog(
        title: '파트변경',
        icon: Icons.swap_horiz,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${user?.name ?? '지원자'}님의 파트를 변경합니다.',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            if (currentWork != null)
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 8),
                ),
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 8)),
                ),
                child: Row(
                  children: [
                    Text('현재: ', style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600)),
                    Text(
                      currentWork.workType,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '변경할 파트 선택',
              style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            ...otherWorkDetails.map((work) => Padding(
              padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () async {
                    final confirmed = await DialogHelper.showConfirm(
                      context,
                      title: '파트 변경',
                      message: '${user?.name ?? '지원자'}님을\n'
                          '${currentWork?.workType ?? app.selectedWorkType} → ${work.workType}(으)로\n'
                          '변경하시겠습니까?',
                      confirmText: '변경',
                    );
                    if (confirmed == true && context.mounted) {
                      Navigator.pop(context, work.id);
                    }
                  },
                  borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 12),
                      vertical: ResponsiveHelper.spacing(context, 10),
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.border),
                      borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 12)),
                    ),
                    child: Row(
                      children: [
                        WorkTypeIcon.buildWithBackground(
                          iconString: work.workTypeIcon,
                          backgroundColor: work.workTypeBackgroundColor,
                          size: ResponsiveHelper.iconSize(context, 18),
                          containerSize: ResponsiveHelper.spacing(context, 32),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                work.workType,
                                style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
                              ),
                              Text(
                                '${work.startTime}~${work.endTime} | ${work.formattedWage}',
                                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.arrow_forward_ios, size: ResponsiveHelper.iconSize(context, 12), color: AppColors.grey300),
                      ],
                    ),
                  ),
                ),
              ),
            )),
          ],
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );

    if (selectedWorkId == null || !mounted) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    try {
      final userProvider = context.read<UserProvider>();
      final adminUID = userProvider.currentUser?.uid ?? 'UNKNOWN';
      final selectedWork = otherWorkDetails.firstWhere(
        (w) => w.id == selectedWorkId,
        orElse: () => throw StateError('선택한 파트를 찾을 수 없습니다'),
      );
      await _svc.changeApplicationWorkType(
        applicationId: app.id,
        newWorkType: selectedWork.workType,
        newWage: selectedWork.wage,
        adminUID: adminUID,
        newWorkDetailId: selectedWork.id,
        newWageType: selectedWork.wageType,
        newWorkTypeIcon: selectedWork.workTypeIcon,
        newWorkTypeColor: selectedWork.workTypeColor,
        newWorkTypeBackgroundColor: selectedWork.workTypeBackgroundColor,
      );
      final resetMsg = calculatedCount > 0
          ? '\n계산된 급여 $calculatedCount건이 초기화되었습니다.'
          : '';
      if (!mounted) return;
      ToastHelper.showSuccess(
        '${user?.name ?? '지원자'}님의 파트가 ${selectedWork.workType}(으)로 변경되었습니다$resetMsg',
      );
      await _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('파트 변경에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _cancelConfirmation(ApplicationModel app) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final user = _userMap[app.uid];
      // [BUG-FIX-2] 확정 취소 사유 수집 + cancelConfirmedApplication으로 교체
      //   work_applicants_dialog과 동일 패턴 적용 (cancelReason 감사 이력 기록)
      final reason = await DialogHelper.showRejectReasonPicker(
        context,
        title: '확정 취소',
        targetName: user?.name,
        message: '취소 사유를 선택해 주세요.',
      );
      if (reason == null || !mounted) return;
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      await _svc.cancelConfirmedApplication(
        app.id,
        canceledBy: adminUID,
        cancelReason: reason,
      );
      _hasChanges = true;
      if (!mounted) return;
      ToastHelper.showSuccess('확정이 취소되었습니다');
      await _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('처리 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── 개별 계약서 작성 ────────────────────────────────────────────────────────

  Future<void> _createContractForOne(ApplicationModel app) async {
    if (_isProcessing) return;
    final bizId = _selectedBusinessId ?? '';
    if (bizId.isEmpty || widget.businesses.isEmpty) return;
    // [특이사항] orElse 폴백 제거 — 잘못된 bizId 시 첫 번째 사업장 명의로 계약서가 생성되는 것을 방지.
    final bizIdx = widget.businesses.indexWhere((b) => b.id == bizId);
    if (bizIdx < 0) return;
    final business = widget.businesses[bizIdx];
    final user = _userMap[app.uid];
    if (user == null) {
      ToastHelper.showError('지원자 정보를 불러올 수 없습니다');
      return;
    }
    setState(() => _isProcessing = true);

    // 1. 템플릿 선택
    final articles =
        await ContractTemplateSelectorDialog.show(context, businessId: bizId);
    if (articles == null || !mounted) {
      if (mounted) setState(() => _isProcessing = false);
      return;
    }

    // 2. 인감 확인 — SubAdmin은 사업주(ownerId) 문서에서 날인 조회
    final up = context.read<UserProvider>();
    final sealUid = up.isSubAdmin ? business.ownerId : (up.currentUser?.uid ?? '');
    String sealBase64 = '';
    String sealType = 'stamp';
    if (sealUid.isNotEmpty) {
      final sealDoc = await FirebaseFirestore.instance.collection('users').doc(sealUid).get();
      if (!mounted) {
        setState(() => _isProcessing = false);
        return;
      }
      sealBase64 = sealDoc.data()?['sealBase64'] ?? '';
      sealType = sealDoc.data()?['sealType'] ?? 'stamp';
    }
    if (sealBase64.isEmpty) {
      if (!mounted) {
        return;
      }
      final goSettings = await DialogHelper.showConfirm(
        context,
        title: '사업주 날인 미등록',
        message: up.isSubAdmin
            ? '계약 발송에는 사업주 날인이 필요합니다.\n사업주에게 날인 등록을 요청해주세요.'
            : '계약 발송에는 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 또는 서명을 먼저 등록해주세요.',
        confirmText: up.isSubAdmin ? '확인' : '설정으로 이동',
        cancelText: '취소',
      );
      if (!mounted) {
        return;
      }
      if (goSettings && !up.isSubAdmin) {
        Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      }
      setState(() => _isProcessing = false);
      return;
    }

    // 3. TO에서 WorkDetailData 조회 — 해당 앱이 속한 그룹 탐색
    _GroupData? group;
    for (final g in _buildGroups()) {
      if (g.confirmedApps.any((a) => a.id == app.id)) {
        group = g;
        break;
      }
    }
    WorkDetailData? workDetail;
    final toId = group?.toId;
    final groupWorkType = group?.workType;
    final groupStartTime = group?.startTime;
    final groupEndTime = group?.endTime;
    if (toId != null) {
      setState(() => _isProcessing = true);
      try {
        final to = await _svc.getTO(toId);
        if (to != null && to.workDetails.isNotEmpty) {
          workDetail = to.workDetails
              .where((w) =>
                  w.workType == groupWorkType &&
                  w.startTime == groupStartTime &&
                  w.endTime == groupEndTime)
              .firstOrNull;
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
    if (!mounted) return;
    if (workDetail == null) {
      // [DART-HIGH-1-FIX] toId==null 경로에서 _isProcessing=true 상태로 return하면 버튼 영구 비활성화
      // toId!=null 경로는 finally에서 해제되지만 toId==null 경로는 해제 코드 없음
      if (mounted) setState(() => _isProcessing = false);
      ToastHelper.showError('근무 정보를 찾을 수 없습니다');
      return;
    }

    // 4. 미리보기 생성
    setState(() => _isProcessing = true);
    late EmploymentContractModel previewContract;
    try {
      previewContract = await ContractService().buildPreviewContract(
        application: app,
        business: business,
        worker: user,
        workDetail: workDetail,
        articles: articles,
      );
    } catch (e) {
      if (mounted) ToastHelper.showError('계약서 미리보기 생성에 실패했습니다');
      return;
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
    if (!mounted) return;

    // 5. 미리보기 다이얼로그 (1명)
    final confirmed = await _showBatchContractPreview(
      contract: previewContract,
      sealBase64: sealBase64,
      sealType: sealType,
      count: 1,
    );
    if (confirmed != true || !mounted) return;

    // 6. 계약서 생성 + 날인
    setState(() => _isProcessing = true);
    try {
      final sealBytes = base64Decode(sealBase64);
      final contract = await ContractService().findOrCreateContract(
        application: app,
        business: business,
        worker: user,
        workDetail: workDetail,
        articles: articles,
      );
      await ContractService().saveEmployerSignature(
        contract: contract,
        signatureBytes: sealBytes,
      );
      if (!mounted) return;
      ToastHelper.showSuccess('계약서가 발송되었습니다');
      _hasChanges = true;
      setState(() => _contractStatusMap[app.id] = 'pending_worker');
    } catch (e) {
      if (mounted) ToastHelper.showError('계약서 발송 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Batch Action Bar ───────────────────────────────────────────────────────

  Widget _buildBatchActionBar(BuildContext context) {
    final brand = Theme.of(context).primaryColor;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: brand.withValues(alpha: 0.05),
        border: Border(top: BorderSide(color: brand.withValues(alpha: 0.15))),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 14, color: brand),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text('${_selectedIds.length}명 선택',
              style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: FontWeight.bold, color: brand)),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() => _selectedIds.clear()),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.grey500,
              padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 8), vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('해제', style: TextStyle(fontSize: 12)),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _batchApprove,
            icon: Icon(Icons.check_circle_outline,
                size: ResponsiveHelper.iconSize(context, 14)),
            label: const Text('일괄 승인',  // [4J.0B] DayApplicants는 CONTRACT_PENDING만 생성 → '승인'이 정확한 표현
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            style: ElevatedButton.styleFrom(
              backgroundColor: brand,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 10),
                vertical: 6,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Bar ─────────────────────────────────────────────────────────────

  Widget _buildBottomBar(BuildContext context) {
    // top-right X 버튼이 기본 닫기 역할 — footer는 접근성 보조용 slim 버튼만 유지
    return AppModalFooter(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context, _hasChanges),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.textSecondary,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('닫기',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _approveApp(ApplicationModel app) async {
    if (_isProcessing) return;
    // [DART-HIGH-2-FIX] 개별 확정 시 정원 초과 체크 — _batchApprove에는 있으나 단일 확정에 누락
    final groups = _buildGroups();
    for (final g in groups) {
      if (g.confirmedApps.any((a) => a.id == app.id)) continue; // 이미 confirmed면 체크 불필요
      // [8.1E.4] groupKey와 동일한 우선순위: wdId 우선, composite fallback, legacy fallback
      final wKey = app.wdId?.isNotEmpty == true
          ? app.wdId!
          : (app.workDetailId?.isNotEmpty == true
              ? app.workDetailId!
              : '${app.selectedWorkType}_${app.startTime}_${app.endTime}');
      if (g.groupKey.endsWith('_$wKey') || g.groupKey == '${app.toId ?? app.toTitle}_$wKey') {
        if (g.requiredCount > 0 && g.confirmedApps.length >= g.requiredCount) {
          ToastHelper.showWarning('정원이 초과되어 확정할 수 없습니다 (${g.toTitle} · ${g.workType})');
          return;
        }
        break;
      }
    }
    setState(() => _isProcessing = true);
    try {
      final name = _userMap[app.uid]?.name ?? '근무자';
      final ok = await DialogHelper.showConfirm(
        context,
        title: '확정',
        message:
            '$name을(를) 계약 대기 상태로 변경하시겠습니까?\n이후 계약서를 직접 작성·서명해야 합니다.',
        confirmText: '확정',
      );
      if (!ok || !mounted) return;
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      await _svc.updateApplicationStatus(
        applicationId: app.id,
        // [P1-A-FIX] contractPending 직접 write 제거 → confirmed CF 경유 필수
        // updateApplicationStatus(confirmed) → _confirmWithConflictCheck() → callableConfirmApplication
        // CF가 TOCTOU 잠금·충돌감지·계약서 생성 후 CONTRACT_PENDING 상태로 설정
        status: AppStatus.confirmed,
        confirmedBy: adminUID,
      );
      _hasChanges = true;
      if (!mounted) return;
      ToastHelper.showSuccess('승인되었습니다. 계약서를 작성해 주세요.');  // [4J.0C] CONTRACT_PENDING 결과 — WorkApplicants parity
      await _load();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ToastHelper.showError(e.message ?? '확정 처리 중 오류가 발생했습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('확정 처리 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectApp(ApplicationModel app) async {
    if (_isProcessing || !mounted) return;
    setState(() => _isProcessing = true);
    try {
      final userName = _userMap[app.uid]?.name ?? '지원자';
      final reason = await DialogHelper.showRejectReasonPicker(
        context,
        title: '지원 거절',
        message: '$userName님을 거절합니다.\n거절 사유를 선택해주세요.',
      );
      if (reason == null || !mounted) return;
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      await _svc.updateApplicationStatus(
        applicationId: app.id,
        status: AppStatus.rejected,
        rejectedBy: adminUID,
        message: reason.trim().isEmpty ? null : reason.trim(),
      );
      _hasChanges = true;
      if (!mounted) return;
      ToastHelper.showSuccess('거절 처리되었습니다');
      await _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('거절 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }


  Future<void> _showWorkerDetail(
    ApplicationModel app,
    UserModel? user, {
    required bool isPending,
  }) async {
    if (user == null) {
      ToastHelper.showWarning('근무자 정보를 불러올 수 없습니다');
      return;
    }
    final changed = await WorkerDetailDialog.show(
      context: context,
      user: user,
      application: app,
      businessId: _selectedBusinessId,
      isConfirmed: !isPending,
      showApprovalButtons: isPending,
      onStatusChanged: () {
        _hasChanges = true;
        _load();
      },
    );
    if (changed == true) _hasChanges = true;
  }

  Future<void> _batchApprove() async {
    // PERM-01: 실행 시점 재확인 — UI 토글이 우회되더라도 서버 전 최후 방어
    final up = Provider.of<UserProvider>(context, listen: false);
    if (!up.can((p) => p.canManageTo)) {
      ToastHelper.showWarning('일괄 확정 권한이 없습니다.');
      return;
    }
    if (_isProcessing || _selectedIds.isEmpty) return;

    // 정원 초과 검증 (TO별로 현재 확정 수 + 선택 수 > 정원이면 경고)
    final selectedApps = _pendingApps.where((a) => _selectedIds.contains(a.id)).toList();

    // M3: toId 없는 지원서 사전 차단
    if (selectedApps.any((a) => a.toId == null)) {
      ToastHelper.showWarning('TO 정보가 없는 지원서가 포함되어 있습니다. 개별 처리해주세요.');
      return;
    }

    // [4J.0C] TO-level canApprovePending 가드 — _toCache에 있는 TO만 검사
    // FULL/TIME_EXPIRED/POSTING_EXPIRED TO는 선제 차단 (CF도 동일 gate)
    final blockedApps = selectedApps.where((a) {
      final to = _toCache[a.toId];
      return to != null && !to.canApprovePending;
    }).toList();
    if (blockedApps.isNotEmpty) {
      ToastHelper.showWarning('현재 상태의 공고(정원 초과·만료)에서는 승인할 수 없습니다. 공고 상태를 확인해 주세요.');
      return;
    }

    // [BUG-FIX-1] workDetail(업무) 단위 정원 초과 체크
    //   이전 코드는 TO 전체 합산 정원으로 체크해 특정 업무 파트가 초과돼도 허용되는 버그 존재
    final selectedByGroupKey = <String, int>{};
    for (final app in selectedApps) {
      // [8.1E.4] groupKey와 동일한 우선순위: wdId 우선, composite fallback, legacy fallback
      final wKey = app.wdId?.isNotEmpty == true
          ? app.wdId!
          : (app.workDetailId?.isNotEmpty == true
              ? app.workDetailId!
              : '${app.selectedWorkType}_${app.startTime}_${app.endTime}');
      final key = '${app.toId ?? app.toTitle}_$wKey';
      selectedByGroupKey[key] = (selectedByGroupKey[key] ?? 0) + 1;
    }
    final groups = _buildGroups();
    final overflowLabels = <String>[];
    for (final g in groups) {
      final selectedCount = selectedByGroupKey[g.groupKey] ?? 0;
      if (selectedCount == 0) continue;
      if (g.requiredCount > 0 &&
          g.confirmedApps.length + selectedCount > g.requiredCount) {
        overflowLabels.add('${g.toTitle}(${g.workType})');
      }
    }
    if (overflowLabels.isNotEmpty) {
      final names = overflowLabels.toSet().join(', ');
      ToastHelper.showWarning('업무별 정원 초과: $names\n해당 업무의 선택 인원을 줄여주세요.');
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final count = _selectedIds.length;
      final confirmed = await DialogHelper.showConfirm(
        context,
        title: '일괄 승인',
        message:
            '선택한 $count명을 계약 대기 상태로 변경하시겠습니까?\n이후 각 지원자의 계약서를 직접 작성·서명해야 합니다.',
        confirmText: '일괄 승인',
      );
      if (!confirmed || !mounted) return;
      final ids = _selectedIds.toList();
      final total = ids.length; // [4J.1] 부분 실패 카운트 계산용
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      // [P1-A-FIX] parallel Future.wait → sequential for-loop
      //   confirmed CF 경유: callableConfirmApplication은 Firestore 트랜잭션 내 충돌감지 수행.
      //   병렬 처리 시 CF 간 레이스컨디션으로 동일 슬롯 중복 확정 가능 → 순차 처리 필수.
      //   [보안] PERMISSION_DENIED 포함 실패 로그 유지 — 크로스-사업장 접근 감지용.
      int successCount = 0;
      for (final appId in ids) {
        try {
          await _svc.updateApplicationStatus(
            applicationId: appId,
            // confirmed → _confirmWithConflictCheck() → CF callableConfirmApplication
            // CF가 TOCTOU 잠금·충돌감지·계약서 생성 후 CONTRACT_PENDING 설정
            status: AppStatus.confirmed,
            confirmedBy: adminUID,
          );
          successCount++;
        } catch (e) {
          debugPrint('❌ [_batchApprove] 확정 실패 [$appId]: $e');
        }
      }
      if (successCount > 0) _hasChanges = true;
      if (!mounted) return;
      // [4J.1] 부분 실패 피드백 — 성공/전체 카운트 표시
      // 실패 원인: network 오류 외에 TO 정원 초과(동시 확정)·Application 취소 등
      // 재시도로 해결되지 않는 케이스 포함 → "상태를 확인" 권장
      if (successCount == 0) {
        ToastHelper.showError('승인에 실패했습니다. 지원자 상태를 확인해 주세요.');
      } else if (successCount < total) {
        ToastHelper.showWarning('$successCount/$total명 승인 완료. 실패한 지원자의 상태를 확인해 주세요.');
      } else {
        ToastHelper.showSuccess('$successCount명이 승인되었습니다');
      }
      await _load();
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String _genderAge(UserModel? user) {
    if (user == null) return '';
    final parts = <String>[];
    if (user.birthDate != null) {
      final now = DateTime.now();
      int age = now.year - user.birthDate!.year;
      if (now.month < user.birthDate!.month ||
          (now.month == user.birthDate!.month &&
              now.day < user.birthDate!.day)) {
        age--;
      }
      parts.add('$age세');
    }
    if (user.gender == '남성') {
      parts.add('남');
    } else if (user.gender == '여성') {
      parts.add('여');
    }
    return parts.isNotEmpty ? '(${parts.join(' ')})' : '';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.isNegative) return '방금 전';
    if (diff.inDays >= 1) return '${diff.inDays}일 전';
    if (diff.inHours >= 1) return '${diff.inHours}시간 전';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}분 전';
    return '방금 전';
  }

}
