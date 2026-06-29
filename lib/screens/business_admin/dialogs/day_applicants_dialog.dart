// 지원명단 다이얼로그 — 선택 날짜의 지원자(PENDING) + 확정자(CONFIRMED)
// 공고(TO) → 업무상세별로 묶어서 표시, work_applicants_dialog 카드 스타일 준용
import 'dart:convert';
import 'dart:math' show min;

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
import '../../../models/core/work_detail_data.dart';
import '../../../providers/user_provider.dart';
import '../../../screens/common/settings_screen.dart';
import '../../../screens/contract/contract_sign_screen.dart' show ContractTemplateWidget;
import '../../../services/contract_service.dart';
import '../../../services/firestore_service.dart';
import '../../../services/monthly_review_service.dart';
import '../../../utils/id_card_helper.dart';
import '../../../utils/trust_score_helper.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../widgets/app_select_field.dart';
import '../../../widgets/common/app_checkbox.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/dialogs/contract_template_selector_dialog.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';

// ─── 그룹 데이터 (업무 단위) ────────────────────────────────────────────────
class _GroupData {
  final String? toId;
  final String toTitle;
  final String workType;
  final String startTime;
  final String endTime;
  final bool isLongTerm;
  final String? workDetailId;   // WorkDetail 고유 ID
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
    this.workDetailId,
    this.requiredCount = 0,
  });

  // 공고 고유 키 (공고 헤더 그룹핑용)
  String get toKey => toId ?? 'noid_$toTitle';

  // 업무 고유 키 (그룹 스코프 — 신분증/계약서 일괄처리)
  String get groupKey {
    final wKey = workDetailId?.isNotEmpty == true
        ? workDetailId!
        : '${workType}_${startTime}_$endTime';
    return '${toId ?? toTitle}_$wKey';
  }

  // capacity 맵에서 찾을 때 사용할 키
  String get capacityKey => workDetailId?.isNotEmpty == true
      ? workDetailId!
      : '${workType}_${startTime}_$endTime';
}

// ─── 다이얼로그 ────────────────────────────────────────────────────────────────
class DayApplicantsDialog extends StatefulWidget {
  final DateTime date;
  final List<String> businessIds;
  final List<BusinessModel> businesses;

  const DayApplicantsDialog({
    super.key,
    required this.date,
    required this.businessIds,
    required this.businesses,
  });

  @override
  State<DayApplicantsDialog> createState() => _DayApplicantsDialogState();
}

class _DayApplicantsDialogState extends State<DayApplicantsDialog> {
  final FirestoreService _svc = FirestoreService();
  final ContractService _contractSvc = ContractService();

  bool _isLoading = true;
  bool _isProcessing = false;
  bool _hasChanges = false;
  String? _selectedBusinessId;

  List<ApplicationModel> _pendingApps = [];
  List<ApplicationModel> _confirmedApps = [];
  Map<String, UserModel> _userMap = {};
  Map<String, String?> _contractStatusMap = {};
  Map<String, int> _weeklyWorkCountMap = {};
  Map<String, int> _workDetailCapacityMap = {};

  final Set<String> _selectedIds = {};
  final Set<String> _starredIds = {};
  Map<String, String> _idCardStatusMap = {};
  final Map<String, bool> _reviewWrittenMap = {};
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
    // [DATE-DEBUG] 다이얼로그 수신 날짜 확인
    debugPrint('🗓️ [DATE-DEBUG] DayApplicantsDialog._load:'
        ' widget.date=${widget.date.toIso8601String()}'
        ' isUtc=${widget.date.isUtc}'
        ' local=${widget.date.toLocal().toIso8601String()}');
    setState(() {
      _isLoading = true;
      _selectedIds.clear();
      _starredIds.clear();
      _idCardStatusMap = {};
      _reviewWrittenMap.clear();
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
      final pending = phase1[0] as List<ApplicationModel>;
      final confirmed = phase1[1] as List<ApplicationModel>;

      if (!mounted || _selectedBusinessId != bizId) return;

      // Phase 2: 유저 프로필 + 계약서 상태 + 주간 근무횟수 병렬 조회
      final allApps = [...pending, ...confirmed];
      Map<String, UserModel> userMap = {};
      Map<String, String?> contractMap = {};
      Map<String, int> weeklyMap = {};

      if (allApps.isNotEmpty) {
        final allUids = allApps.map((a) => a.uid).toSet().toList();
        final allAppIds = allApps.map((a) => a.id).toList();

        Map<String, int> workDetailCapacityMap = {};
        final results = await Future.wait([
          _svc.getUsersBatch(allUids),
          _contractSvc.getContractStatusBatch(allAppIds, businessId: bizId),
          _loadWeeklyCount(bizId),
          _loadWorkDetailCapacities(allApps),
        ]);
        userMap = results[0] as Map<String, UserModel>;
        contractMap = results[1] as Map<String, String?>;
        weeklyMap = results[2] as Map<String, int>;
        workDetailCapacityMap = results[3] as Map<String, int>;

        // Phase 3: 신분증 상태 + 리뷰 작성 여부 (확정자만) + 관심표시 복원
        final confirmedUserIds = confirmed.map((a) => a.uid).toSet().toList();
        final currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

        Map<String, String> idCardMap = {};
        if (confirmedUserIds.isNotEmpty && currentUserId.isNotEmpty) {
          idCardMap = await IdCardHelper.loadStatusBatch(
            firestoreService: _svc,
            requesterId: currentUserId,
            targetUserIds: confirmedUserIds,
          );
        }

        final Map<String, bool> reviewMap = {};
        if (confirmedUserIds.isNotEmpty) {
          final reviewEntries = await Future.wait(
            confirmedUserIds.map((uid) async {
              final key = MonthlyReviewModel.generateKeyForUser(
                businessId: bizId,
                targetUserId: uid,
                year: widget.date.year,
                month: widget.date.month,
              );
              final exists = await MonthlyReviewService().getReviewById(key);
              return MapEntry(uid, exists != null);
            }),
          );
          reviewMap.addAll(Map.fromEntries(reviewEntries));
        }

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
          _isLoading = false;
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
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 지원명단 로드 실패: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _pendingApps = [];
        _confirmedApps = [];
        _userMap = {};
        _contractStatusMap = {};
        _idCardStatusMap = {};
        _workDetailCapacityMap = {};
        _weeklyWorkCountMap = {};
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
    } catch (_) {
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

  // ── Grouping ───────────────────────────────────────────────────────────────

  List<_GroupData> _buildGroups() {
    final Map<String, _GroupData> groups = {};

    void addApp(ApplicationModel app, bool isPending) {
      final wKey = app.workDetailId?.isNotEmpty == true
          ? app.workDetailId!
          : '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
      final key = '${app.toId ?? app.toTitle}_$wKey';
      groups.putIfAbsent(
        key,
        () => _GroupData(
          toId: app.toId,
          toTitle: app.toTitle,
          workType: app.selectedWorkType,
          startTime: app.startTime,
          endTime: app.endTime,
          isLongTerm: app.isLongTermApplication,
          workDetailId: app.workDetailId,
          requiredCount: _workDetailCapacityMap[
              app.workDetailId?.isNotEmpty == true
                  ? app.workDetailId!
                  : '${app.selectedWorkType}_${app.startTime}_${app.endTime}'] ?? 0,
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
      child: Dialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDialogSize.borderRadius),
        ),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: AppDialogSize.insetH,
          vertical: AppDialogSize.insetV,
        ),
        child: SizedBox(
          height:
              MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
          child: Column(
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
        ),
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.info, AppColors.info.withValues(alpha: 0.85)],
        ),
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(AppDialogSize.borderRadius),
          topRight: Radius.circular(AppDialogSize.borderRadius),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.people_outlined,
                    color: Colors.white,
                    size: ResponsiveHelper.iconSize(context, 24)),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('지원명단',
                        style: ResponsiveHelper.titleStyle(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                    Text(FormatHelper.formatDateLong(widget.date),
                        style: ResponsiveHelper.smallStyle(context,
                            color: Colors.white.withValues(alpha: 0.8))),
                  ],
                ),
              ),
              Material(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: () => Navigator.pop(context, _hasChanges),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: EdgeInsets.all(
                        ResponsiveHelper.spacing(context, 8)),
                    child: Icon(Icons.close,
                        color: Colors.white,
                        size: ResponsiveHelper.iconSize(context, 24)),
                  ),
                ),
              ),
            ],
          ),
          if (widget.businesses.length > 1) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            AppSelectField<String>(
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
            ),
          ],
        ],
      ),
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
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        border:
            Border(bottom: BorderSide(color: AppColors.infoLight, width: 0.5)),
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
              onTap: () => setState(() {
                _isBatchMode = !_isBatchMode;
                if (!_isBatchMode) {
                  _selectedIds.clear();
                } else {
                  // 다른 모드와 상호 배제
                  _idCardSelectGroupKey = null;
                  _selectedIdCardUserIds.clear();
                  _contractBatchGroupKey = null;
                }
              }),
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
    final groups = _buildGroups();
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
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
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
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
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
            return _buildWorkSubSection(context, e.value, isLast: isLast);
          }),
        ],
      ),
    );
  }

  // ── Work SubSection (업무별 서브섹션) ──────────────────────────────────────

  Widget _buildWorkSubSection(BuildContext context, _GroupData g,
      {required bool isLast}) {
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
                      index: e.key + 1))
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

  // ── Applicant Card ─────────────────────────────────────────────────────────

  Widget _buildApplicantCard(BuildContext context, ApplicationModel app,
      {required bool isPending, bool isGroupIdCardMode = false, int index = 0}) {
    final user = _userMap[app.uid];
    final isSelected = _selectedIds.contains(app.id);
    final isStarred = isPending && _starredIds.contains(app.id);
    final idCardStatus = _idCardStatusMap[user?.uid ?? ''] ?? 'none';
    final trustScore = TrustScoreHelper.calculate(user);

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
                    onTap: () {
                      final nowStarred = !_starredIds.contains(app.id);
                      setState(() {
                        if (nowStarred) {
                          _starredIds.add(app.id);
                        } else {
                          _starredIds.remove(app.id);
                        }
                      });
                      _svc.updateApplicationFields(
                          app.id, {'isStarred': nowStarred});
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
                if (user?.phone != null && user!.phone!.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.phone_outlined,
                        size: 10, color: AppColors.grey400),
                    const SizedBox(width: 2),
                    Text(user.phone!,
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.grey600)),
                  ]),
                _buildTrustBadge(context, trustScore),
                _weeklyCountBadge(context, app.uid),
                if (user != null && user.averageRating > 0)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.star_rounded,
                        size: 11, color: Color(0xFFF59E0B)),
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
            if (isPending && !_isBatchMode) ...[
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
                  const SizedBox(width: 8),
                  _actionButton(
                    context,
                    label: '승인',
                    color: AppColors.success,
                    filled: true,
                    onTap: () => _approveApp(app),
                  ),
                ],
              ),
            ] else if (!isPending) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  // 계약 미작성 시 개별 계약서 작성 버튼
                  if ((_contractStatusMap[app.id] == null ||
                      _contractStatusMap[app.id]!.isEmpty ||
                      _contractStatusMap[app.id] == 'voided')) ...[
                    _actionButton(
                      context,
                      label: '계약서 작성',
                      color: AppColors.success,
                      filled: true,
                      onTap: () => _createContractForOne(app),
                    ),
                    const SizedBox(width: 8),
                  ],
                  _actionButton(
                    context,
                    label: '확정취소',
                    color: AppColors.error,
                    onTap: () => _cancelConfirmation(app),
                  ),
                ],
              ),
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

  Widget _buildTrustBadge(BuildContext context, int score) {
    final bool isLow = score < 40;
    final Color color;
    final Color bgColor;
    if (score >= 70) {
      color = AppColors.info;
      bgColor = AppColors.infoBg;
    } else if (isLow) {
      color = AppColors.error;
      bgColor = AppColors.errorBg;
    } else {
      color = AppColors.grey600;
      bgColor = AppColors.grey100;
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
          Icon(
            isLow ? Icons.shield : Icons.shield_outlined,
            size: ResponsiveHelper.iconSize(context, 10),
            color: color,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Text('신뢰$score',
              style: ResponsiveHelper.tinyStyle(context, color: color)
                  .copyWith(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _contractBadge(BuildContext context, String appId,
      {bool isPending = false}) {
    final status = _contractStatusMap[appId];
    if (status == null) {
      if (!isPending) {
        return _chip(context,
            label: '계약미작성',
            color: AppColors.error,
            bgColor: AppColors.errorBg);
      }
      return const SizedBox.shrink();
    }
    final String label;
    final Color color;
    switch (status) {
      case 'pending_employer':
        label = '관리자서명';
        color = AppColors.warningDark;
      case 'pending_worker':
        label = '서명대기';
        color = AppColors.warningDark;
      case 'completed':
        label = '계약완료';
        color = AppColors.successDark;
      case 'voided':
        label = '무효';
        color = AppColors.error;
      default:
        label = '계약중';
        color = AppColors.grey600;
    }
    return _chip(context,
        label: label, color: color, bgColor: color.withValues(alpha: 0.1));
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
    if (_selectedIdCardUserIds.isEmpty) return;
    final currentUser = context.read<UserProvider>().currentUser;
    if (currentUser == null) {
      ToastHelper.showError('로그인이 필요합니다');
      return;
    }
    final bizId = _selectedBusinessId ?? '';
    final business =
        widget.businesses.firstWhere((b) => b.id == bizId, orElse: () => widget.businesses.first);

    // 선택된 사용자 정보 수집 (전체 앱에서)
    final targets = <Map<String, String>>[];
    for (final app in [..._pendingApps, ..._confirmedApps]) {
      final user = _userMap[app.uid];
      if (user == null || !_selectedIdCardUserIds.contains(user.uid)) continue;
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
      });
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
    if (_contractBatchGroupKey != null) return;
    final bizId = _selectedBusinessId ?? '';
    if (bizId.isEmpty || widget.businesses.isEmpty) return;
    final business = widget.businesses.firstWhere(
      (b) => b.id == bizId,
      orElse: () => widget.businesses.first,
    );

    // 계약서 미작성 또는 무효 확정자 수집
    final toProcess = g.confirmedApps.where((app) {
      final status = _contractStatusMap[app.id];
      return status == null || status.isEmpty || status == 'voided';
    }).toList();
    if (toProcess.isEmpty) return;

    // 1. 템플릿 선택
    final articles =
        await ContractTemplateSelectorDialog.show(context, businessId: bizId);
    if (articles == null || !mounted) return;

    // 2. 인감 확인
    final currentUser = context.read<UserProvider>().currentUser;
    final sealBase64 = currentUser?.sealBase64 ?? '';
    final sealType = currentUser?.sealType ?? 'stamp';
    if (sealBase64.isEmpty) {
      if (!mounted) return;
      final goSettings = await DialogHelper.showConfirm(
        context,
        title: '사업주 날인 미등록',
        message:
            '일괄 계약 발송에는 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 또는 서명을 먼저 등록해주세요.',
        confirmText: '설정으로 이동',
        cancelText: '취소',
      );
      if (!mounted) return;
      if (goSettings) {
        Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      }
      return;
    }

    // 3. TO에서 WorkDetailData 조회
    setState(() => _contractBatchGroupKey = g.groupKey);
    WorkDetailData? workDetail;
    try {
      if (g.toId != null) {
        final to = await _svc.getTO(g.toId!);
        if (to != null && to.workDetails.isNotEmpty) {
          try {
            workDetail = to.workDetails.firstWhere(
              (w) =>
                  w.workType == g.workType &&
                  w.startTime == g.startTime &&
                  w.endTime == g.endTime,
            );
          } catch (_) {
            workDetail = to.workDetails.first;
          }
        }
      }
    } finally {
      if (mounted) setState(() => _contractBatchGroupKey = null);
    }
    if (!mounted) return;

    if (workDetail == null) {
      ToastHelper.showError('근무 정보를 찾을 수 없습니다');
      return;
    }

    // 4. 첫 번째 대상으로 미리보기 생성
    final firstApp = toProcess.first;
    final firstUser = _userMap[firstApp.uid];
    if (firstUser == null) {
      ToastHelper.showError('지원자 정보를 불러올 수 없습니다');
      return;
    }

    setState(() => _contractBatchGroupKey = g.groupKey);
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
      ToastHelper.showError('계약서 미리보기 생성에 실패했습니다');
      return;
    } finally {
      if (mounted) setState(() => _contractBatchGroupKey = null);
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
    setState(() => _contractBatchGroupKey = g.groupKey);
    final sealBytes = base64Decode(sealBase64);
    final finalWorkDetail = workDetail;
    try {
      Future<bool> processOne(ApplicationModel app) async {
        final user = _userMap[app.uid];
        if (user == null) return false;
        try {
          final contract = await ContractService().findOrCreateContract(
            application: app,
            business: business,
            worker: user,
            workDetail: finalWorkDetail,
            articles: articles,
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
      ToastHelper.showError('처리 중 오류가 발생했습니다');
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
      barrierDismissible: true,
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

  Future<void> _cancelConfirmation(ApplicationModel app) async {
    final user = _userMap[app.uid];
    final ok = await DialogHelper.showConfirm(
      context,
      title: '확정 취소',
      message: '${user?.name ?? '근무자'}의 확정을 취소하시겠습니까?\n취소 후 해당 지원자는 목록에서 제거됩니다.',
      confirmText: '확정 취소',
    );
    if (!ok || !mounted) return;

    setState(() => _isProcessing = true);
    try {
      await _svc.updateApplicationStatus(
        applicationId: app.id,
        status: AppStatus.canceled,
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
    final bizId = _selectedBusinessId ?? '';
    if (bizId.isEmpty || widget.businesses.isEmpty) return;
    final business = widget.businesses.firstWhere(
      (b) => b.id == bizId,
      orElse: () => widget.businesses.first,
    );
    final user = _userMap[app.uid];
    if (user == null) {
      ToastHelper.showError('지원자 정보를 불러올 수 없습니다');
      return;
    }

    // 1. 템플릿 선택
    final articles =
        await ContractTemplateSelectorDialog.show(context, businessId: bizId);
    if (articles == null || !mounted) return;

    // 2. 인감 확인
    final currentUser = context.read<UserProvider>().currentUser;
    final sealBase64 = currentUser?.sealBase64 ?? '';
    final sealType = currentUser?.sealType ?? 'stamp';
    if (sealBase64.isEmpty) {
      if (!mounted) return;
      final goSettings = await DialogHelper.showConfirm(
        context,
        title: '사업주 날인 미등록',
        message: '계약 발송에는 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 또는 서명을 먼저 등록해주세요.',
        confirmText: '설정으로 이동',
        cancelText: '취소',
      );
      if (!mounted) return;
      if (goSettings) {
        Navigator.of(context, rootNavigator: true)
            .push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
      }
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
          try {
            workDetail = to.workDetails.firstWhere(
              (w) =>
                  w.workType == groupWorkType &&
                  w.startTime == groupStartTime &&
                  w.endTime == groupEndTime,
            );
          } catch (_) {
            workDetail = to.workDetails.first;
          }
        }
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
    if (!mounted) return;
    if (workDetail == null) {
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
      ToastHelper.showError('계약서 미리보기 생성에 실패했습니다');
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
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        border:
            Border(top: BorderSide(color: AppColors.infoLight, width: 0.5)),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle_rounded, size: 16, color: AppColors.infoDark),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text('${_selectedIds.length}명 선택',
              style: ResponsiveHelper.smallStyle(context).copyWith(
                  fontWeight: FontWeight.bold, color: AppColors.infoDark)),
          const Spacer(),
          TextButton(
            onPressed: () => setState(() => _selectedIds.clear()),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 8), vertical: 4),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text('해제',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey500)),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          ElevatedButton.icon(
            onPressed: _isProcessing ? null : _batchApprove,
            icon: Icon(Icons.check_circle_outline,
                size: ResponsiveHelper.iconSize(context, 15)),
            label: Text('일괄 확정',
                style: ResponsiveHelper.smallStyle(context)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 12),
                vertical: 8,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom Bar ─────────────────────────────────────────────────────────────

  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.grey100)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () => Navigator.pop(context, _hasChanges),
          icon: Icon(Icons.close, size: ResponsiveHelper.iconSize(context, 16)),
          label: Text('닫기', style: ResponsiveHelper.bodyStyle(context)),
          style: OutlinedButton.styleFrom(
            padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 12)),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
      ),
    );
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _approveApp(ApplicationModel app) async {
    final name = _userMap[app.uid]?.name ?? '근무자';
    final ok = await DialogHelper.showConfirm(
      context,
      title: '확정',
      message:
          '$name을(를) 계약 대기 상태로 변경하시겠습니까?\n이후 계약서를 직접 작성·서명해야 합니다.',
      confirmText: '확정',
    );
    if (!ok || !mounted) return;
    setState(() => _isProcessing = true);
    try {
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      await _svc.updateApplicationStatus(
        applicationId: app.id,
        status: AppStatus.confirmed,
        confirmedBy: adminUID,
      );
      _hasChanges = true;
      if (!mounted) return;
      ToastHelper.showSuccess('확정 처리되었습니다');
      await _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('확정 실패: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _rejectApp(ApplicationModel app) async {
    if (!mounted) return;
    final userName = _userMap[app.uid]?.name ?? '지원자';
    final reason = await DialogHelper.showRejectReasonPicker(
      context,
      title: '지원 거절',
      message: '$userName님을 거절합니다.\n거절 사유를 선택해주세요.',
    );
    if (reason == null || !mounted) return;
    setState(() => _isProcessing = true);
    try {
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
    if (_isProcessing || _selectedIds.isEmpty) return;

    // 정원 초과 검증 (TO별로 현재 확정 수 + 선택 수 > 정원이면 경고)
    final selectedApps = _pendingApps.where((a) => _selectedIds.contains(a.id)).toList();

    // M3: toId 없는 지원서 사전 차단
    if (selectedApps.any((a) => a.toId == null)) {
      ToastHelper.showWarning('TO 정보가 없는 지원서가 포함되어 있습니다. 개별 처리해주세요.');
      return;
    }

    // M2: 모든 초과 TO를 수집 후 한 번에 경고 (업무 단위 정원 기준)
    final selectedByTo = <String, int>{};
    for (final app in selectedApps) {
      final toId = app.toId!;
      selectedByTo[toId] = (selectedByTo[toId] ?? 0) + 1;
    }
    final overflowToIds = <String>[];
    for (final entry in selectedByTo.entries) {
      final toId = entry.key;
      // TO 전체 정원 = 해당 TO의 workDetail별 capacity 합산
      final toGroups = _buildGroups().where((g) => g.toId == toId);
      final totalCapacity = toGroups.fold(0, (s, g) => s + g.requiredCount);
      if (totalCapacity > 0) {
        final alreadyConfirmed = _confirmedApps.where((a) => a.toId == toId).length;
        if (alreadyConfirmed + entry.value > totalCapacity) {
          overflowToIds.add(toId);
        }
      }
    }
    if (overflowToIds.isNotEmpty) {
      final names = overflowToIds
          .map((id) => selectedApps.firstWhere((a) => a.toId == id).toTitle)
          .toSet()
          .join(', ');
      ToastHelper.showWarning('정원 초과 공고: $names\n해당 공고의 선택 인원을 줄여주세요.');
      return;
    }

    final count = _selectedIds.length;
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '일괄 확정',
      message:
          '선택한 $count명을 계약 대기 상태로 변경하시겠습니까?\n이후 각 지원자의 계약서를 직접 작성·서명해야 합니다.',
      confirmText: '일괄 확정',
    );
    if (!confirmed || !mounted) return;

    setState(() => _isProcessing = true);
    int successCount = 0;
    final ids = _selectedIds.toList();
    try {
      final adminUID = FirebaseAuth.instance.currentUser?.uid;
      for (final appId in ids) {
        if (!mounted) break;
        try {
          await _svc.updateApplicationStatus(
            applicationId: appId,
            status: AppStatus.confirmed,
            confirmedBy: adminUID,
          );
          successCount++;
        } catch (_) {}
      }
      if (successCount > 0) _hasChanges = true;
      if (!mounted) return;
      ToastHelper.showSuccess('$successCount명이 확정되었습니다');
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
