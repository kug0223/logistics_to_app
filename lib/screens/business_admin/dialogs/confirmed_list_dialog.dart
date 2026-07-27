// lib/screens/business_admin/dialogs/confirmed_list_dialog.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/user_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/loading_state_mixin.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/app_checkbox.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../utils/id_card_helper.dart';
import '../../../utils/trust_score_helper.dart';

class ConfirmedListDialog {
  final BuildContext context;
  final TOItem toItem;
  final FirestoreService firestoreService;
  final String? slotId;
  final VoidCallback? onChanged;
  final VoidCallback? onLocalStatsChanged;

  ConfirmedListDialog({
    required this.context,
    required this.toItem,
    required this.firestoreService,
    this.slotId,
    this.onChanged,
    this.onLocalStatsChanged,
  });

  void show() {
    showDialog(
      context: context,
      builder: (context) => _ConfirmedListDialogWidget(
        toItem: toItem,
        firestoreService: firestoreService,
        slotId: slotId,
        onChanged: onChanged,
        onLocalStatsChanged: onLocalStatsChanged,
      ),
    );
  }
}

class _ConfirmedListDialogWidget extends StatefulWidget {
  final TOItem toItem;
  final FirestoreService firestoreService;
  final String? slotId;
  final VoidCallback? onChanged;
  final VoidCallback? onLocalStatsChanged;

  const _ConfirmedListDialogWidget({
    required this.toItem,
    required this.firestoreService,
    this.slotId,
    this.onChanged,
    this.onLocalStatsChanged,
  });

  @override
  State<_ConfirmedListDialogWidget> createState() =>
      _ConfirmedListDialogWidgetState();
}

class _ConfirmedListDialogWidgetState extends State<_ConfirmedListDialogWidget>
    with LoadingStateMixin {
  bool _hasChanges = false;
  Map<String, List<Map<String, dynamic>>> _confirmedByWork = {};
  Map<String, String> _idCardStatusMap = {};
  String? _error;
  int _totalConfirmed = 0;

  // 신분증 일괄 요청 모드
  bool _isIdCardSelectMode = false;
  final Set<String> _selectedIdCardUserIds = {};

  // 확정 취소 모드
  bool _isCancelSelectMode = false;
  final Set<String> _selectedCancelAppIds = {};

  // [BUG-CANCEL-01] 근무 이력 있는 확정자는 확정취소 불가
  Map<String, bool> _hasWorkedMap = {};

  @override
  void initState() {
    super.initState();
    _loadConfirmedApplicants();
  }

  Future<void> _loadConfirmedApplicants() async {
    setLoading(true);
    if (mounted) setState(() => _error = null);
    final userProvider = context.read<UserProvider>();
    try {
      // [BUGFIX] whereIn + equality 복합쿼리 시 Firestore 보안 규칙
      //   request.query.filters.businessId가 null 반환 → PERMISSION_DENIED.
      //   statuses 파라미터 제거 후 클라이언트 필터링으로 전환.
      final allApps = widget.slotId != null
          ? await widget.firestoreService.getApplicationsBySlotId(
              widget.toItem.to.id,
              widget.slotId!,
              businessId: widget.toItem.to.businessId,
            )
          : await widget.firestoreService.getApplicationsByTOId(
              widget.toItem.to.id,
              businessId: widget.toItem.to.businessId,
            );
      const confirmedStatuses = {'CONFIRMED', 'CONTRACT_PENDING'};
      final confirmed = allApps.where((a) => confirmedStatuses.contains(a.status)).toList();

      // ✅ 1. 중복 제거된 UID 목록
      final uniqueUids = confirmed.map((app) => app.uid).toSet().toList();
      final currentUserId = userProvider.currentUser?.uid ?? '';

      // ✅ 2. getUsersBatch + loadStatusBatch + hasWorkedMap 동시 시작
      final userMapFuture = widget.firestoreService.getUsersBatch(uniqueUids, businessId: widget.toItem.to.businessId);
      final idCardFuture = IdCardHelper.loadStatusBatch(
        firestoreService: widget.firestoreService,
        requesterId: currentUserId,
        targetUserIds: uniqueUids,
      );
      // [BUG-CANCEL-01] 슬롯 날짜가 있을 때만 출퇴근 기록 조회 — 날짜 없으면 빈 맵(가드 없음)
      final slotDate = widget.toItem.slotDate;
      final hasWorkedFuture = (uniqueUids.isNotEmpty && slotDate != null)
          ? widget.firestoreService.loadHasWorkedMap(
              businessId: widget.toItem.to.businessId,
              date: slotDate,
            )
          : Future.value(<String, bool>{});

      final userMap = await userMapFuture;

      // ✅ 3. 결과 매핑 (추가 조회 없음)
      final results = confirmed.map((app) {
        // workDetailId 우선, 없으면 workType으로 폴백 (구 데이터 호환)
        final groupKey = (app.workDetailId?.isNotEmpty == true)
            ? app.workDetailId!
            : app.selectedWorkType;
        return {
          'application': app,
          'user': userMap[app.uid],
          'groupKey': groupKey,
        };
      }).toList();
      final Map<String, List<Map<String, dynamic>>> groupedByWork = {};

      // [BUG-FIX] null user도 포함 — 드롭하면 확정 근무자가 관리자 화면에서 사라짐
      // user가 null일 수 있는 경우: getUsersBatch CF 청크 오류, 또는 캐시 미스
      for (var result in results) {
        final groupKey = result['groupKey'] as String;
        groupedByWork.putIfAbsent(groupKey, () => []);
        groupedByWork[groupKey]!.add(result);
      }

      // 각 업무별로 성별→나이순 정렬 (user null 안전 처리)
      for (var workers in groupedByWork.values) {
        workers.sort((a, b) {
          final userA = a['user'] as UserModel?;
          final userB = b['user'] as UserModel?;
          if (userA == null && userB == null) return 0;
          if (userA == null) return 1;
          if (userB == null) return -1;

          final genderOrder = {'남성': 0, '여성': 1};
          final genderA = genderOrder[userA.gender] ?? 2;
          final genderB = genderOrder[userB.gender] ?? 2;

          if (genderA != genderB) {
            return genderA.compareTo(genderB);
          }

          final ageA = userA.age ?? 999;
          final ageB = userB.age ?? 999;
          return ageA.compareTo(ageB);
        });
      }

      // 신분증 상태 + 출퇴근 기록 — 위에서 동시에 시작한 Future 결과 수집
      final idCardStatusMap = await idCardFuture;
      final hasWorkedMap = await hasWorkedFuture;

      if (!mounted) return;
      setState(() {
        _confirmedByWork = groupedByWork;
        _idCardStatusMap = idCardStatusMap;
        _hasWorkedMap = hasWorkedMap; // [BUG-CANCEL-01]
        _totalConfirmed = groupedByWork.values.fold(0, (sum, list) => sum + list.length);
      });
    } catch (e) {
      debugPrint('❌ 확정 명단 로드 실패: $e');
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      setLoading(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MM/dd (E)', 'ko_KR');

    // ⭐ PopScope 추가: 외부 탭으로 닫아도 변경 여부 반환
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          // ⭐ 변경사항 있으면 로컬 콜백 호출
          if (_hasChanges) {
            widget.onLocalStatsChanged?.call();
          }
          Navigator.pop(context, _hasChanges);
        }
      },
      child: StyledDialog(
        title: '확정 명단',
        subtitle:
            '${dateFormat.format(widget.toItem.slot?.date ?? widget.toItem.to.date)} · ${widget.toItem.to.title}',
        icon: Icons.check_circle,
        headerColor: AppColors.success,
        maxHeightRatio: 0.85,
        fillHeight: true,
        content: _buildContent(),
        actions: [
          StyledDialogButton.cancel(
            text: '닫기',
            onPressed: () {
              // ⭐ 변경사항 있으면 로컬 콜백 호출
              if (_hasChanges) {
                widget.onLocalStatsChanged?.call();
              }
              Navigator.pop(context, _hasChanges);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (isLoading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const LoadingWidget(),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '확정 명단 불러오는 중...',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return AppEmptyState(
        icon: Icons.error_outline,
        title: '데이터를 불러올 수 없습니다',
        iconColor: AppColors.error,
        action: TextButton.icon(
          onPressed: _loadConfirmedApplicants,
          icon: const Icon(Icons.refresh),
          label: const Text('다시 시도'),
        ),
      );
    }

    if (_confirmedByWork.isEmpty) {
      return const AppEmptyState(
        icon: Icons.people_outline,
        title: '확정된 근무자가 없습니다',
      );
    }

    // 전체 미요청자 수 계산
    final totalRequestableCount = _idCardStatusMap.entries
        .where((e) => IdCardHelper.isRequestable(e.value))
        .length;

    return SingleChildScrollView(
      padding: ResponsiveHelper.cardPadding(context),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildTotalStats(),
        // 신분증 일괄 요청 영역
        if (totalRequestableCount > 0)
          _buildIdCardRequestSection(totalRequestableCount),
        _buildCancelSection(),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        ..._confirmedByWork.entries.map((entry) {
          final groupKey = entry.key;
          final workers = entry.value;

          // TO의 workDetails가 비어있으면 .first 호출 시 StateError 크래시.
          // TO 생성 직후 workDetails 저장 전 or 전체 삭제된 경우 발생 가능.
          if (widget.toItem.workDetails.isEmpty) return const SizedBox.shrink();

          // compositeId(신규) → legacyId(구) → workType → 첫 번째 순으로 폴백
          final workDetail = widget.toItem.workDetails.firstWhere(
            (w) => w.id == groupKey,
            orElse: () => widget.toItem.workDetails.firstWhere(
              (w) => w.legacyId == groupKey,
              orElse: () => widget.toItem.workDetails.firstWhere(
                (w) => w.workType == groupKey,
                orElse: () => widget.toItem.workDetails.first,
              ),
            ),
          );
          return _buildWorkSection(workDetail.workType, workers, workDetail);
        }),
      ],
    ),
    );
  }

  Widget _buildTotalStats() {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.success.withValues(alpha: 0.1), AppColors.success.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.people, color: Colors.white, size: ResponsiveHelper.iconSize(context, 24)),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('총 확정 인원', style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600)),
                Text('$_totalConfirmed명', style: ResponsiveHelper.titleStyle(context).copyWith(fontWeight: FontWeight.bold, color: AppColors.success)),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 12), vertical: ResponsiveHelper.spacing(context, 6)),
            decoration: BoxDecoration(color: AppColors.success, borderRadius: BorderRadius.circular(20)),
            child: Text('${_confirmedByWork.length}개 업무', style: ResponsiveHelper.smallStyle(context, color: Colors.white).copyWith(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// 신분증 일괄 요청 섹션
  Widget _buildIdCardRequestSection(int requestableCount) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 12)),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: _isIdCardSelectMode ? AppColors.infoBg : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isIdCardSelectMode ? AppColors.info : AppColors.border),
      ),
      child: Row(
        children: [
          Icon(
            Icons.badge,
            size: ResponsiveHelper.iconSize(context, 18),
            color: AppColors.info,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              _isIdCardSelectMode 
                  ? '${_selectedIdCardUserIds.length}명 선택됨'
                  : '미요청 $requestableCount명',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.infoDark),
            ),
          ),
          // 요청하기 버튼 (선택 모드 + 선택된 항목 있을 때)
          if (_isIdCardSelectMode && _selectedIdCardUserIds.isNotEmpty) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isLoading ? null : () => _batchRequestIdCard(),
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
                    '요청하기',
                    style: ResponsiveHelper.smallStyle(context, color: Colors.white).copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          ],
          // 신분증 요청 / 취소 버튼
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isIdCardSelectMode = !_isIdCardSelectMode;
                  if (!_isIdCardSelectMode) {
                    _selectedIdCardUserIds.clear();
                  } else {
                    _selectAllRequestableUsers();
                    _isCancelSelectMode = false;
                    _selectedCancelAppIds.clear();
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
                  color: _isIdCardSelectMode ? AppColors.grey100 : AppColors.info,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _isIdCardSelectMode ? '취소' : '신분증 요청',
                  style: ResponsiveHelper.smallStyle(
                    context, 
                    color: _isIdCardSelectMode ? AppColors.grey700 : Colors.white,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkSection(String workType, List<Map<String, dynamic>> workers, WorkDetailModel workDetail) {
    final confirmedCount = workers.length;
    final requiredCount = workDetail.requiredCount;
    final progress = requiredCount > 0 ? (confirmedCount / requiredCount).clamp(0.0, 1.0) : 0.0;
    final isFull = requiredCount > 0 && confirmedCount >= requiredCount;

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        children: [
          // 헤더
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    WorkTypeIcon.buildWithBackground(iconString: workDetail.workTypeIcon, backgroundColor: workDetail.workTypeBackgroundColor, size: ResponsiveHelper.iconSize(context, 32)),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(workType, style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold)),
                          _buildTimeRow(context, workDetail),
                        ],
                      ),
                    ),
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 10),
                        vertical: ResponsiveHelper.spacing(context, 4),
                      ),
                      decoration: BoxDecoration(
                        color: (isFull ? AppColors.success : AppColors.info)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$confirmedCount/$requiredCount명',
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: isFull ? AppColors.success : AppColors.infoDark,
                        ).copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: AppColors.grey200,
                    valueColor: AlwaysStoppedAnimation(
                      isFull ? AppColors.success : AppColors.info,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // 워커 목록
          ...workers.asMap().entries.map((entry) {
            final index = entry.key;
            final worker = entry.value;
            final user = worker['user'] as UserModel?;
            final application = worker['application'] as ApplicationModel;
            final isLast = index == workers.length - 1;
            if (user == null) return const SizedBox.shrink();
            final idCardStatus = _idCardStatusMap[user.uid] ?? 'none';
            final isIdCardSelected = _selectedIdCardUserIds.contains(user.uid);

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _isCancelSelectMode
                    ? (_canCancelConfirmation(application) ? () => _toggleCancelSelection(application.id, application) : null)
                    : _isIdCardSelectMode && (idCardStatus == 'none' || idCardStatus == 'expired' || idCardStatus == 'rejected')
                        ? () => _toggleIdCardSelection(user.uid)
                        : () => _showWorkerDetailDialog(context, user, application, workDetail),
                borderRadius: isLast ? const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)) : null,
                child: Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    color: isIdCardSelected ? AppColors.infoBg : Colors.transparent,
                    border: isLast ? null : Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      // ✅ 체크박스 영역 (애니메이션)
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: (_isIdCardSelectMode || _isCancelSelectMode) ? 32 : 0,
                        child: _isCancelSelectMode
                            ? AppCheckbox(
                                value: _selectedCancelAppIds.contains(application.id),
                                activeColor: AppColors.error,
                                size: 22,
                                enabled: _canCancelConfirmation(application),
                              )
                            : _isIdCardSelectMode
                                ? ((idCardStatus == 'none' || idCardStatus == 'expired' || idCardStatus == 'rejected')
                                    ? AppCheckbox(
                                        value: isIdCardSelected,
                                        activeColor: AppColors.info,
                                        size: 22,
                                      )
                                    : const SizedBox(width: 22))
                                : const SizedBox.shrink(),
                      ),
                      // 순번
                      CircleAvatar(
                        radius: ResponsiveHelper.spacing(context, 16),
                        backgroundColor: AppColors.success.withValues(alpha: 0.15),
                        child: Text(
                          '${index + 1}',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                            
                            color: AppColors.successDark,
                          ),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 1줄: 이름 + 성별·나이 + 화살표
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    user.name,
                                    style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (user.gender != null || user.age != null) ...[
                                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                  Flexible(
                                    child: Text(
                                      '(${user.gender ?? ''}${user.age != null ? ' · ${user.age}세' : ''})',
                                      style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                Icon(Icons.chevron_right, size: ResponsiveHelper.iconSize(context, 16), color: AppColors.grey400),
                              ],
                            ),
                            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                            // 2줄: 신뢰도 + 신분증 + 평점
                            Row(
                              children: [
                                _buildTrustBadge(user),
                                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                if (user.averageRating > 0) ...[
                                  Icon(Icons.star, size: ResponsiveHelper.iconSize(context, 12), color: AppColors.amber),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                                  Text(user.averageRating.toStringAsFixed(1), style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600)),
                                ],
                                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                IdCardHelper.buildStatusBadge(context, idCardStatus),
                              ],
                            ),
                            // 3줄: 장기 근무 정보 (있는 경우) - 희망 시작일만 강조
                            if (widget.toItem.to.isLongTerm && application.isLongTermApplication && application.workPeriodDisplay.isNotEmpty) ...[
                              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                              Row(
                                children: [
                                  Icon(
                                    Icons.date_range,
                                    size: ResponsiveHelper.iconSize(context, 12),
                                    color: application.desiredStartDate != null
                                        ? Theme.of(context).primaryColor
                                        : AppColors.grey500,
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                  Flexible(
                                    child: Text(
                                      application.desiredStartDate != null
                                          ? '희망: ${application.desiredStartDate!.month}/${application.desiredStartDate!.day}~'
                                            '${application.workEndDate != null ? " (${application.workEndDate!.month}/${application.workEndDate!.day}까지)" : ""}'
                                          : '장기: ${application.workPeriodDisplay}',
                                      style: ResponsiveHelper.smallStyle(
                                        context,
                                        color: application.desiredStartDate != null
                                            ? Theme.of(context).primaryColor
                                            : AppColors.grey600,
                                      ).copyWith(
                                        fontWeight: application.desiredStartDate != null ? FontWeight.w600 : FontWeight.normal,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildTimeRow(BuildContext context, WorkDetailModel workDetail) {
    final netTime = FormatHelper.calcNetWorkTime(
      workDetail.startTime,
      workDetail.endTime,
      breakMinutes: workDetail.breakMinutes,
    );
    return Wrap(
      spacing: ResponsiveHelper.spacing(context, 6),
      runSpacing: ResponsiveHelper.spacing(context, 4),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.access_time, size: ResponsiveHelper.iconSize(context, 12), color: AppColors.grey400),
            SizedBox(width: ResponsiveHelper.spacing(context, 3)),
            Text(
              netTime.isNotEmpty
                  ? '${workDetail.startTime} ~ ${workDetail.endTime} (실근무 $netTime)'
                  : '${workDetail.startTime} ~ ${workDetail.endTime}',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            ),
          ],
        ),
        if (workDetail.breakMinutes > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.successDark.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.pause_circle_outline, size: 11, color: AppColors.successDark),
                SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                Text(
                  '휴게 ${FormatHelper.formatCompactHours(workDetail.breakMinutes)}',
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: AppColors.successDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTrustBadge(UserModel user) {
    final trustScore = TrustScoreHelper.calculate(user);
    
    // 70+: 파랑, 40~69: 회색, 40 미만: 빨강
    final Color color;
    final Color bgColor;
    final bool isLow = trustScore < 40;
    
    if (trustScore >= 70) {
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
          Text(
            '신뢰$trustScore', 
            style: ResponsiveHelper.tinyStyle(context, color: color).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

/// ⭐ 수정: 로컬 통계 업데이트 패턴 적용
  Future<void> _showWorkerDetailDialog(BuildContext context, UserModel user, ApplicationModel application, WorkDetailModel workDetail) async {
    final userProvider = context.read<UserProvider>();
    final changed = await WorkerDetailDialog.show(
      context: context,
      user: user,
      application: application,
      toItem: widget.toItem,
      businessId: widget.toItem.to.businessId,
      isConfirmed: true,
      showApprovalButtons: false,
      onStatusChanged: () {
        _hasChanges = true;
      },
    );
    
    if (changed == true && mounted) {
      _hasChanges = true;

      final groupKey = (application.workDetailId?.isNotEmpty == true)
          ? application.workDetailId!
          : application.selectedWorkType;

      setState(() {
        // 1. 목록에서 해당 워커 제거
        _confirmedByWork[groupKey]?.removeWhere(
          (item) => (item['user'] as UserModel?)?.uid == user.uid
        );

        // 2. 해당 업무에 워커가 없으면 업무 자체 제거
        if (_confirmedByWork[groupKey]?.isEmpty ?? false) {
          _confirmedByWork.remove(groupKey);
        }
        
        // 3. 총 인원 감소
        _totalConfirmed--;
        
        // 4. 신분증 맵에서 제거
        _idCardStatusMap.remove(user.uid);
        _selectedIdCardUserIds.remove(user.uid);
        
        // 5. 부모 toItem.workDetailStats 업데이트 (compositeId 기반)
        widget.toItem.workDetailStats ??= {};
        final wdId = application.workDetailId;
        final statsKey = (wdId != null && wdId.isNotEmpty && wdId != application.selectedWorkType)
            ? wdId  // 신규 compositeId
            : '${application.selectedWorkType}_${application.startTime}_${application.endTime}';
        // 위 ??= {} 로 workDetailStats가 non-null 보장됨 — ! 안전
        final stats = widget.toItem.workDetailStats![statsKey];
        if (stats != null) {
          stats['confirmed'] = ((stats['confirmed'] ?? 0) - 1).clamp(0, 9999);
        }
        // 6. 슬롯 헤더 통계 감소 (그룹 헤더 배지 즉시 반영)
        widget.toItem.updateOuterStats(
          confirmed: (widget.toItem.confirmedCount - 1).clamp(0, 9999),
          pending: widget.toItem.pendingCount,
        );
      });
    } else if (mounted) {
      // 신분증 상태만 변경된 경우 (확정 취소 아님)
      final currentUserId = userProvider.currentUser?.uid ?? '';
      
      final newStatus = await IdCardHelper.loadStatusBatch(
        firestoreService: widget.firestoreService,
        requesterId: currentUserId,
        targetUserIds: [user.uid],
      );
      
      if (mounted) {
        setState(() {
          _idCardStatusMap.addAll(newStatus);
        });
      }
    }
  }

  /// 미요청자 전체 선택
  void _selectAllRequestableUsers() {
    _selectedIdCardUserIds.clear();
    for (var entry in _confirmedByWork.entries) {
      for (var worker in entry.value) {
        final user = worker['user'] as UserModel?;
        if (user == null) continue;
        final status = _idCardStatusMap[user.uid] ?? 'none';
        if (IdCardHelper.isRequestable(status)) {
          _selectedIdCardUserIds.add(user.uid);
        }
      }
    }
  }

  /// 신분증 선택 토글
  void _toggleIdCardSelection(String uid) {
    setState(() {
      if (_selectedIdCardUserIds.contains(uid)) {
        _selectedIdCardUserIds.remove(uid);
      } else {
        _selectedIdCardUserIds.add(uid);
      }
    });
  }

  // ── 확정 취소 섹션 ───────────────────────────────────────────

  Widget _buildCancelSection() {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 12)),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: _isCancelSelectMode ? AppColors.errorBg : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isCancelSelectMode
              ? AppColors.errorDark.withValues(alpha: 0.4)
              : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cancel_outlined,
            size: ResponsiveHelper.iconSize(context, 18),
            color: AppColors.error,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              _isCancelSelectMode
                  ? '${_selectedCancelAppIds.length}명 선택됨'
                  : '확정 취소 관리',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.errorDark),
            ),
          ),
          if (_isCancelSelectMode && _selectedCancelAppIds.isNotEmpty) ...[
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: isLoading ? null : _batchCancelConfirmation,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 12),
                    vertical: ResponsiveHelper.spacing(context, 6),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '마감취소',
                    style: ResponsiveHelper.smallStyle(context, color: Colors.white)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          ],
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () {
                setState(() {
                  _isCancelSelectMode = !_isCancelSelectMode;
                  if (_isCancelSelectMode) {
                    _isIdCardSelectMode = false;
                    _selectedIdCardUserIds.clear();
                  } else {
                    _selectedCancelAppIds.clear();
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
                  color: _isCancelSelectMode ? AppColors.grey100 : AppColors.errorBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _isCancelSelectMode ? '취소' : '일괄 취소',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: _isCancelSelectMode ? AppColors.grey700 : AppColors.errorDark,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // [BUG-CANCEL-01] 출퇴근 기록이 있는 근무자는 확정취소 불가
  bool _canCancelConfirmation(ApplicationModel app) {
    return _hasWorkedMap[app.uid] != true;
  }

  void _toggleCancelSelection(String applicationId, ApplicationModel app) {
    if (!_canCancelConfirmation(app)) return;
    setState(() {
      if (_selectedCancelAppIds.contains(applicationId)) {
        _selectedCancelAppIds.remove(applicationId);
      } else {
        _selectedCancelAppIds.add(applicationId);
      }
    });
  }

  Future<void> _batchCancelConfirmation() async {
    if (_selectedCancelAppIds.isEmpty) return;

    final cancelReason = await _showCancelReasonPicker();
    if (cancelReason == null || !mounted) return;

    final adminUID = context.read<UserProvider>().currentUser?.uid;
    if (adminUID == null) {
      ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
      return;
    }
    final targetIds = List<String>.from(_selectedCancelAppIds);

    setLoading(true);
    int successCount = 0;
    final Set<String> successIds = {};
    try {
      final results = await Future.wait(
        targetIds.map(
          (appId) => widget.firestoreService.cancelConfirmedApplication(
            appId,
            canceledBy: adminUID,
            cancelReason: cancelReason,
          ).catchError((_) => false),
        ),
      );
      for (int i = 0; i < targetIds.length; i++) {
        if (results[i]) {
          successCount++;
          successIds.add(targetIds[i]);
        }
      }
    } catch (e) {
      debugPrint('❌ 일괄 확정 취소 실패: $e');
      if (mounted) ToastHelper.showError('확정 취소 중 오류가 발생했습니다');
    } finally {
      setLoading(false);
    }

    if (successCount > 0 && mounted) {
      setState(() {
        // workDetailStats 업데이트 (개별 취소와 동일한 방어 로직)
        widget.toItem.workDetailStats ??= {};
        for (final entry in _confirmedByWork.entries) {
          for (final w in entry.value) {
            final app = w['application'] as ApplicationModel;
            if (!successIds.contains(app.id)) continue;
            final wdId = app.workDetailId;
            final statsKey = (wdId != null && wdId.isNotEmpty && wdId != app.selectedWorkType)
                ? wdId
                : '${app.selectedWorkType}_${app.startTime}_${app.endTime}';
            final stats = widget.toItem.workDetailStats![statsKey];
            if (stats != null) {
              stats['confirmed'] = ((stats['confirmed'] ?? 0) - 1).clamp(0, 9999);
            }
          }
        }
        // 슬롯 헤더 통계 업데이트 (그룹 헤더 배지 즉시 반영)
        widget.toItem.updateOuterStats(
          confirmed: (widget.toItem.confirmedCount - successCount).clamp(0, 9999),
          pending: widget.toItem.pendingCount,
        );
        for (final entry in _confirmedByWork.entries.toList()) {
          // 실제 성공한 ID만 UI에서 제거
          entry.value.removeWhere((w) {
            final app = w['application'] as ApplicationModel;
            return successIds.contains(app.id);
          });
          if (entry.value.isEmpty) _confirmedByWork.remove(entry.key);
        }
        _totalConfirmed -= successCount;
        _isCancelSelectMode = false;
        _selectedCancelAppIds.clear();
        _hasChanges = true;
      });
      final failCount = targetIds.length - successCount;
      if (failCount > 0) {
        ToastHelper.showWarning('$successCount명 취소 완료, $failCount명 실패');
      } else {
        ToastHelper.showSuccess('$successCount명의 확정이 취소되었습니다');
      }
      widget.onLocalStatsChanged?.call();
    }
  }

  Future<String?> _showCancelReasonPicker() async {
    String? selectedReason;
    final customController = TextEditingController();
    final count = _selectedCancelAppIds.length;
    const reasons = ['일정 변경', '인원 조정', '업무 취소', '근무자 요청', '기타'];

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(ctx, 16)),
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.cancel_outlined, color: Colors.white,
                          size: ResponsiveHelper.iconSize(ctx, 24)),
                      SizedBox(width: ResponsiveHelper.spacing(ctx, 12)),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '확정 취소 ($count명)',
                            style: ResponsiveHelper.subtitleStyle(ctx)
                                .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                          Text(
                            '취소 사유를 선택하세요',
                            style: ResponsiveHelper.smallStyle(ctx)
                                .copyWith(color: Colors.white.withValues(alpha: 0.8)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(ctx, 16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: ResponsiveHelper.spacing(ctx, 8),
                          runSpacing: ResponsiveHelper.spacing(ctx, 8),
                          children: reasons.map((r) {
                            final isSelected = selectedReason == r;
                            return GestureDetector(
                              onTap: () => setDialogState(() => selectedReason = r),
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: ResponsiveHelper.spacing(ctx, 14),
                                  vertical: ResponsiveHelper.spacing(ctx, 8),
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected ? AppColors.error : AppColors.grey100,
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: isSelected ? AppColors.error : AppColors.grey200,
                                  ),
                                ),
                                child: Text(
                                  r,
                                  style: ResponsiveHelper.smallStyle(
                                    ctx,
                                    color: isSelected ? Colors.white : AppColors.grey700,
                                  ).copyWith(fontWeight: FontWeight.w600),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        if (selectedReason == '기타') ...[
                          SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
                          TextField(
                            controller: customController,
                            maxLength: 200,
                            decoration: InputDecoration(
                              hintText: '취소 사유를 입력하세요',
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8)),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(ctx, 12),
                                vertical: ResponsiveHelper.spacing(ctx, 10),
                              ),
                              counterText: '',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    ResponsiveHelper.spacing(ctx, 16),
                    0,
                    ResponsiveHelper.spacing(ctx, 16),
                    ResponsiveHelper.spacing(ctx, 16),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            FocusScope.of(dialogCtx).unfocus();
                            Navigator.pop(dialogCtx);
                          },
                          child: const Text('취소'),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(ctx, 12)),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: selectedReason == null
                              ? null
                              : () {
                                  final reason = selectedReason == '기타' &&
                                          customController.text.trim().isNotEmpty
                                      ? customController.text.trim()
                                      : selectedReason!;
                                  FocusScope.of(dialogCtx).unfocus();
                                  Navigator.pop(dialogCtx, reason);
                                },
                          style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error),
                          child: Text('확정 취소',
                              style: ResponsiveHelper.bodyStyle(ctx, color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Future<void>.delayed(const Duration(milliseconds: 400)).then((_) {
      customController.dispose();
    });
    return result;
  }

  /// 일괄 신분증 요청
  Future<void> _batchRequestIdCard() async {
    if (_selectedIdCardUserIds.isEmpty) return;

    final userProvider = context.read<UserProvider>();
    final currentUser = userProvider.currentUser;
    if (currentUser == null) {
      ToastHelper.showError('로그인이 필요합니다');
      return;
    }

    // 선택된 사용자 정보 수집
    final targets = <Map<String, String>>[];
    for (var entry in _confirmedByWork.entries) {
      for (var worker in entry.value) {
        final user = worker['user'] as UserModel?;
        final app = worker['application'] as ApplicationModel?;
        if (user == null || !_selectedIdCardUserIds.contains(user.uid)) continue;
        
        targets.add({
          'uid': user.uid,
          'name': user.name,
          'applicationId': app?.id ?? '',
        });
      }
    }

    final businessId = widget.toItem.to.businessId;
    final business = await widget.firestoreService.getBusinessById(businessId);

    if (!mounted) return;
    if (business == null) {
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
      return;
    }
    final successCount = await IdCardHelper.showBatchRequestDialog(
      context: context,
      firestoreService: widget.firestoreService,
      requester: {
        'uid': currentUser.uid,
        'name': currentUser.name,
      },
      business: {
        'id': businessId,
        'name': business.name,
      },
      targets: targets,
    );

    if (successCount > 0 && mounted) {
      setState(() {
        for (final uid in _selectedIdCardUserIds) {
          _idCardStatusMap[uid] = 'pending';
        }
        _isIdCardSelectMode = false;
        _selectedIdCardUserIds.clear();
      });
    }
  }
}