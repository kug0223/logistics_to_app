// 지원명단 다이얼로그 — 선택 날짜의 지원자(PENDING) + 확정자(CONFIRMED)
// 공고(TO) → 업무상세별로 묶어서 표시, work_applicants_dialog 카드 스타일 준용
import 'dart:convert';
import 'dart:math' show min;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/core/application_model.dart';
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

// ─── 그룹 데이터 (공고(TO) 단위) ────────────────────────────────────────────
class _GroupData {
  final String? toId;
  final String toTitle;
  final String workType;
  final String startTime;
  final String endTime;
  final bool isLongTerm;
  final List<ApplicationModel> pendingApps = [];
  final List<ApplicationModel> confirmedApps = [];

  _GroupData({
    required this.toId,
    required this.toTitle,
    required this.workType,
    required this.startTime,
    required this.endTime,
    required this.isLongTerm,
  });

  // 그룹 고유 키 — 다중 그룹 선택 모드 스코프에 사용
  String get groupKey => toId ?? '${toTitle}_$workType';
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
  Map<String, int> _toCapacityMap = {};

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

      // Phase 2: 유저 프로필 + 계약서 상태 + 주간 근무횟수 병렬 조회
      final allApps = [...pending, ...confirmed];
      Map<String, UserModel> userMap = {};
      Map<String, String?> contractMap = {};
      Map<String, int> weeklyMap = {};

      if (allApps.isNotEmpty) {
        final allUids = allApps.map((a) => a.uid).toSet().toList();
        final allAppIds = allApps.map((a) => a.id).toList();

        Map<String, int> toCapacityMap = {};
        final results = await Future.wait([
          _svc.getUsersBatch(allUids),
          _contractSvc.getContractStatusBatch(allAppIds, businessId: bizId),
          _loadWeeklyCount(bizId),
          _loadSlotCapacity(allApps),
        ]);
        userMap = results[0] as Map<String, UserModel>;
        contractMap = results[1] as Map<String, String?>;
        weeklyMap = results[2] as Map<String, int>;
        toCapacityMap = results[3] as Map<String, int>;

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

        if (!mounted) return;
        setState(() {
          _pendingApps = pending;
          _confirmedApps = confirmed;
          _userMap = userMap;
          _contractStatusMap = contractMap;
          _weeklyWorkCountMap = weeklyMap;
          _toCapacityMap = toCapacityMap;
          _idCardStatusMap = idCardMap;
          _reviewWrittenMap.addAll(reviewMap);
          _starredIds.addAll(starredFromFirestore);
          _isLoading = false;
        });
        return;
      }

      if (!mounted) return;
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
      setState(() => _isLoading = false);
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
      return result.map((uid, list) => MapEntry(uid, list.length));
    } catch (_) {
      return {};
    }
  }

  /// 해당 날짜의 슬롯 기준 정원 조회 (TO 전체 정원이 아닌 슬롯별 정원)
  Future<Map<String, int>> _loadSlotCapacity(List<ApplicationModel> allApps) async {
    // toId → slotId (같은 날짜/TO의 앱은 같은 슬롯)
    final toSlotMap = <String, String>{};
    for (final app in allApps) {
      if (app.toId != null && app.slotId != null && !toSlotMap.containsKey(app.toId!)) {
        toSlotMap[app.toId!] = app.slotId!;
      }
    }
    if (toSlotMap.isEmpty) {
      // 슬롯 없는 장기TO 폴백: TO의 totalRequired 사용
      final toIds = allApps.where((a) => a.toId != null).map((a) => a.toId!).toSet().toList();
      if (toIds.isEmpty) return {};
      final tos = await Future.wait(toIds.map((id) => _svc.getTO(id)));
      final res = <String, int>{};
      for (var i = 0; i < toIds.length; i++) {
        if (tos[i] != null) res[toIds[i]] = tos[i]!.totalRequired;
      }
      return res;
    }
    // 슬롯 문서에서 workDetails.requiredCount 합산
    final result = <String, int>{};
    await Future.wait(toSlotMap.entries.map((e) async {
      final capacity = await _svc.getSlotTotalRequired(e.key, e.value);
      if (capacity > 0) result[e.key] = capacity;
    }));
    return result;
  }

  // ── Grouping ───────────────────────────────────────────────────────────────

  List<_GroupData> _buildGroups() {
    final Map<String, _GroupData> groups = {};

    void addApp(ApplicationModel app, bool isPending) {
      final key = app.toId ?? 'noid_${app.toTitle}_${app.selectedWorkType}';
      groups.putIfAbsent(
        key,
        () => _GroupData(
          toId: app.toId,
          toTitle: app.toTitle,
          workType: app.selectedWorkType,
          startTime: app.startTime,
          endTime: app.endTime,
          isLongTerm: app.isLongTermApplication,
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

    return groups.values.toList()
      ..sort((a, b) {
        final t = a.toTitle.compareTo(b.toTitle);
        return t != 0 ? t : a.startTime.compareTo(b.startTime);
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
                if (!_isBatchMode) _selectedIds.clear();
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

    final groups = _buildGroups();
    return ListView.separated(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      itemCount: groups.length,
      separatorBuilder: (_, __) =>
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
      itemBuilder: (_, i) => _buildGroupSection(context, groups[i]),
    );
  }

  // ── Group Section ──────────────────────────────────────────────────────────

  Widget _buildGroupSection(BuildContext context, _GroupData g) {
    final pendingIds = g.pendingApps.map((a) => a.id).toList();
    final allSelected = pendingIds.isNotEmpty &&
        pendingIds.every((id) => _selectedIds.contains(id));
    final someSelected = pendingIds.any((id) => _selectedIds.contains(id));

    return Container(
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 그룹 헤더 (업무유형 + 시간대) ──
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
                vertical: ResponsiveHelper.spacing(context, 10),
              ),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.06),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  // 전체 체크박스 (일괄선택 모드 + 대기자 있을 때)
                  if (_isBatchMode && pendingIds.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: AppCheckbox(
                        value: allSelected || someSelected,
                        activeColor: someSelected && !allSelected
                            ? AppColors.grey400
                            : null,
                      ),
                    ),
                  ],
                  // 공고명 + 업무상세
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // 단기/장기 배지
                            Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 5),
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: g.isLongTerm
                                    ? AppColors.longTermBg
                                    : AppColors.shortTermBg,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: g.isLongTerm
                                      ? AppColors.longTermDark
                                          .withValues(alpha: 0.3)
                                      : AppColors.shortTermDark
                                          .withValues(alpha: 0.3),
                                ),
                              ),
                              child: Text(
                                g.isLongTerm ? '장기' : '단기',
                                style: ResponsiveHelper.tinyStyle(
                                  context,
                                  color: g.isLongTerm
                                      ? AppColors.longTermDark
                                      : AppColors.shortTermDark,
                                ).copyWith(fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                g.toTitle.isNotEmpty ? g.toTitle : g.workType,
                                style: ResponsiveHelper.subtitleStyle(context)
                                    .copyWith(fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '${g.workType}  ${g.startTime} ~ ${g.endTime}',
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.grey600),
                        ),
                      ],
                    ),
                  ),
                  // 인원 아이콘 표시
                  _buildGroupStats(context, g),
                ],
              ),
            ),
          ),

          // ── 대기 중 섹션 ──
          if (g.pendingApps.isNotEmpty) ...[
            _sectionDivider(context, '대기 중 (${g.pendingApps.length}명)',
                AppColors.warning),
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 8)),
              child: Column(
                children: g.pendingApps
                    .map((app) => _buildApplicantCard(context, app,
                        isPending: true))
                    .toList(),
              ),
            ),
          ],

          // ── 확정 섹션 ──
          if (g.confirmedApps.isNotEmpty) ...[
            _sectionDivider(context, '확정 (${g.confirmedApps.length}명)',
                AppColors.success),
            Builder(builder: (context) {
              final requestableCount = g.confirmedApps.where((app) {
                final user = _userMap[app.uid];
                if (user == null) return false;
                return IdCardHelper.isRequestable(
                    _idCardStatusMap[user.uid] ?? 'none');
              }).length;
              if (requestableCount == 0) return const SizedBox.shrink();
              return _buildIdCardRequestSection(context, g, requestableCount);
            }),
            Builder(builder: (context) {
              final noContractCount = g.confirmedApps.where((app) {
                final status = _contractStatusMap[app.id];
                return status == null || status.isEmpty;
              }).length;
              if (noContractCount == 0) return const SizedBox.shrink();
              return _buildContractBatchSection(context, g, noContractCount);
            }),
            Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 8)),
              child: Column(
                children: g.confirmedApps
                    .map((app) => _buildApplicantCard(context, app,
                        isPending: false,
                        isGroupIdCardMode:
                            _idCardSelectGroupKey == g.groupKey))
                    .toList(),
              ),
            ),
          ],

          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        ],
      ),
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
      {required bool isPending, bool isGroupIdCardMode = false}) {
    final user = _userMap[app.uid];
    final isSelected = _selectedIds.contains(app.id);
    final isStarred = isPending && _starredIds.contains(app.id);
    final idCardStatus = _idCardStatusMap[user?.uid ?? ''] ?? 'none';

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
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 7),
                    decoration: BoxDecoration(
                      color: isPending ? AppColors.warning : AppColors.success,
                      shape: BoxShape.circle,
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
                  )
                else
                  _buildReviewBadge(context, user?.uid),
              ],
            ),

            // ── Row 2: 정보 + 배지 통합 ──
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
                _contractBadge(context, app.id, isPending: isPending),
                if (!isPending)
                  IdCardHelper.buildStatusBadge(context, idCardStatus),
              ],
            ),

            // ── Row 3: 액션 버튼 (대기자 + 일괄선택 아닐 때만) ──
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.calendar_today_outlined,
            size: 11, color: AppColors.grey500),
        const SizedBox(width: 2),
        Text('주$count회',
            style: ResponsiveHelper.tinyStyle(context,
                color: AppColors.grey600)),
      ],
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
    final required = g.toId != null ? (_toCapacityMap[g.toId] ?? 0) : 0;
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

    // 계약서 미작성 확정자 수집
    final toProcess = g.confirmedApps.where((app) {
      final status = _contractStatusMap[app.id];
      return status == null || status.isEmpty;
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
      for (var i = 0; i < toProcess.length; i += batchSize) {
        final batch =
            toProcess.sublist(i, min(i + batchSize, toProcess.length));
        final results = await Future.wait(batch.map(processOne));
        successCount += results.where((r) => r).length;
      }

      if (!mounted) return;
      if (successCount < toProcess.length) {
        ToastHelper.showWarning(
            '$successCount/${toProcess.length}명 계약서 발송 완료. 실패한 항목은 다시 시도해주세요.');
      } else {
        ToastHelper.showSuccess('${toProcess.length}명에게 계약서가 발송되었습니다');
      }
      _hasChanges = true;
      // BUG-2 수정: saveEmployerSignature 완료 후 실제 Firestore status는
      // 'pending_worker' — 'pending'으로 쓰면 _contractBadge default('계약중')로 표시됨.
      setState(() {
        for (final app in toProcess) {
          _contractStatusMap[app.id] = 'pending_worker';
        }
      });
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
    final reason = await _showRejectReasonDialog();
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

  Future<String?> _showRejectReasonDialog() async {
    String reason = '';
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('거절 사유'),
        content: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '사유 입력 (선택사항)',
            border: OutlineInputBorder(),
          ),
          maxLines: 2,
          onChanged: (v) => reason = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, reason),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('거절', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
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
        try {
          await _svc.updateApplicationStatus(
            applicationId: appId,
            status: AppStatus.confirmed,
            confirmedBy: adminUID,
          );
          successCount++;
        } catch (_) {}
      }
      _hasChanges = true;
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
    if (user.gender != null) parts.add(user.gender == '남성' ? '남' : '여');
    return parts.isNotEmpty ? '(${parts.join(' ')})' : '';
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays >= 1) return '${diff.inDays}일 전';
    if (diff.inHours >= 1) return '${diff.inHours}시간 전';
    if (diff.inMinutes >= 1) return '${diff.inMinutes}분 전';
    return '방금 전';
  }

}
