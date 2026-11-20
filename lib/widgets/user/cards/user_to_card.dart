import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/slot_model.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/text_layout.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../theme/app_colors.dart';
import '../../../providers/user_provider.dart';
import '../../work_type_icon.dart';
import '../../common/tax_deduction_badge.dart';
import '../../common/first_line_icon.dart';
import '../../common/loading_widget.dart';
import '../../../screens/common/job_posting_screen.dart';
import '../../dialogs/apply/apply_work_dialog.dart';
import '../../dialogs/apply/application_relation.dart';

/// 지원자용 TO 카드
///
/// [compact = false] 기본 모드:
///   접힌 상태: 급여·날짜+시간·위치·모집현황 한눈에
///   펼친 상태:
///     - flex TO → 날짜별 슬롯 목록 (슬롯별 지원 버튼)
///     - contract TO → 공고 설명 + 업무 목록
///   카드 상호 비활성화: isAnyOtherExpanded=true 시 반투명 처리
///
/// [compact = true] 탐색 전용 모드 (일자리 탭 목록):
///   왼쪽 컬러바·펼침 없음. 카드 전체 탭 → JobPostingScreen 이동.
///   selectedNotifier / onFetchWorkDetails / onFetchSlots 불필요.
class UserTOCard extends StatefulWidget {
  const UserTOCard({
    super.key,
    required this.to,
    required this.myApplications,
    required this.onApplySuccess,
    this.compact = false,
    this.selectedNotifier,
    this.onFetchWorkDetails,
    this.workDetails,
    this.slots,
    this.onFetchSlots,
    this.selectedDate,
  });

  final TOModel to;
  final List<ApplicationModel> myApplications;
  final VoidCallback onApplySuccess;

  /// true: 탐색 전용 컴팩트 카드 — 확장 없음, 카드 탭 시 상세 화면으로 이동
  final bool compact;

  /// [R7-P2-2 P22-N] 목록이 고르고 있는 **하루**. 상세로 그대로 넘긴다.
  ///   상세는 이 날짜로 슬롯을 **다시 읽는다**(`_slot` 이 전달값보다 우선) —
  ///   넘기는 것은 "어느 날을 보고 있었는가"뿐이고 수치는 목적지가 만든다.
  final DateTime? selectedDate;

  /// 화면 전체 공유 선택 상태 — value == to.id 이면 이 카드가 펼쳐짐
  /// compact=false 일 때만 사용. ValueNotifier 방식: 탭 시 해당 카드 2개만 rebuild
  final ValueNotifier<String?>? selectedNotifier;

  // contract TO용 (compact=false)
  final List<WorkDetailModel>? workDetails;
  final Future<List<WorkDetailModel>> Function(String toId)? onFetchWorkDetails;

  // flex TO용 슬롯 (compact=false)
  final List<SlotModel>? slots;
  final Future<List<SlotModel>> Function(String toId)? onFetchSlots;

  @override
  State<UserTOCard> createState() => _UserTOCardState();
}

class _UserTOCardState extends State<UserTOCard> {
  bool _isFetching = false;
  bool _isFetchingSlots = false;
  bool _isApplyLoading = false;
  DateTime _buildNow = DateTime.now();

  // 빌드마다 재계산 방지 — myApplications/to 변경 시에만 갱신
  late bool _cachedHasApplied;
  late String _cachedTimeAgo;
  // M3: _hasAppliedForSlot O(n) → O(1) 조회용 사전 계산 Set
  late Set<String> _appliedSlotIds;
  late Set<String> _appliedDateKeys;

  List<WorkDetailModel> get _workDetails => widget.workDetails ?? const [];
  bool get _showLoading => _isFetching && _workDetails.isEmpty;
  bool get _showSlotsLoading => _isFetchingSlots && (widget.slots == null || widget.slots!.isEmpty);

  // ValueNotifier 기반 선택 상태 — 탭 시 전체 화면 setState 없이 이 카드만 rebuild
  // compact=true 이면 selectedNotifier가 null → 항상 false
  bool get _isSelected =>
      widget.selectedNotifier?.value == widget.to.id;

  void _onSelectionChanged() {
    if (_isSelected) {
      // 이 카드가 선택됨 → 필요 시 데이터 fetch
      if (widget.to.isFlexType) {
        if (widget.slots == null) _fetchSlots();
      } else {
        if (widget.workDetails == null) _fetch();
      }
    }
    // ValueListenableBuilder가 rebuild를 처리하므로 setState 불필요
  }

  @override
  void initState() {
    super.initState();
    _cachedHasApplied = _computeHasApplied();
    _cachedTimeAgo    = _computeTimeAgo();
    _rebuildAppliedSets();
    // compact 모드에서는 selectedNotifier가 null — addListener 생략
    if (!widget.compact) {
      widget.selectedNotifier?.addListener(_onSelectionChanged);
    }
  }

  @override
  void dispose() {
    if (!widget.compact) {
      widget.selectedNotifier?.removeListener(_onSelectionChanged);
    }
    super.dispose();
  }

  // M3: 슬롯별 지원 여부를 O(1)로 조회하기 위한 Set 사전 계산
  void _rebuildAppliedSets() {
    final slotIds = <String>{};
    final dateKeys = <String>{};
    for (final app in widget.myApplications) {
      // [SIM-EXPIRED-JOB-CARD] 관계 판정은 공용 resolver 가 한다(EXPIRED·종료 결정 = 관계 아님).
      if (!ApplicationRelationResolver.holdsRelation(app)) continue;
      if (app.toId?.isNotEmpty == true && app.toId != widget.to.id) continue;
      if (app.slotId?.isNotEmpty == true) {
        slotIds.add(app.slotId!);
      } else {
        final d = app.workDate;
        dateKeys.add('${d.year}-${d.month}-${d.day}');
      }
    }
    _appliedSlotIds = slotIds;
    _appliedDateKeys = dateKeys;
  }

  bool _computeHasApplied() => widget.myApplications.any((app) {
        if (!ApplicationRelationResolver.holdsRelation(app)) return false;
        if (app.toId?.isNotEmpty == true) return app.toId == widget.to.id;
        return _legacyMatch(app);
      });

  String _computeTimeAgo() {
    final diff = DateTime.now().difference(widget.to.createdAt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
    if (diff.inHours < 24) return '${diff.inHours}시간 전';
    return '${diff.inDays}일 전';
  }

  // ── 위젯 업데이트 ────────────────────────────────────

  @override
  void didUpdateWidget(UserTOCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _buildNow = DateTime.now(); // 위젯 갱신 시 시간 캐시 동기화 — build() 내 상태 변이 방지
    // 지원 목록 또는 TO가 바뀌면 캐시 갱신
    // identical 비교 외 length도 확인 — 같은 List 객체에 항목이 추가/제거된 경우 포착
    if (!identical(widget.myApplications, oldWidget.myApplications) ||
        widget.myApplications.length != oldWidget.myApplications.length ||
        widget.to.id != oldWidget.to.id) {
      _cachedHasApplied = _computeHasApplied();
      _rebuildAppliedSets(); // M3
    }
    if (widget.to.createdAt != oldWidget.to.createdAt) {
      _cachedTimeAgo = _computeTimeAgo();
    }
    // 선택 상태 변경 시 fetch는 _onSelectionChanged 리스너에서 처리
    // 부모 캐시에서 데이터가 들어옴 → 로딩 종료
    if (widget.workDetails != null && oldWidget.workDetails == null && _isFetching) {
      setState(() => _isFetching = false);
    }
    if (widget.slots != null && oldWidget.slots == null && _isFetchingSlots) {
      setState(() => _isFetchingSlots = false);
    }
  }

  Future<List<WorkDetailModel>> _fetch() async {
    if (_isFetching) return widget.workDetails ?? const [];
    setState(() => _isFetching = true);
    try {
      return await widget.onFetchWorkDetails!(widget.to.id);
    } finally {
      if (mounted) setState(() => _isFetching = false);
    }
  }

  Future<List<SlotModel>> _fetchSlots() async {
    if (widget.onFetchSlots == null) return [];
    if (_isFetchingSlots) return widget.slots ?? [];
    setState(() => _isFetchingSlots = true);
    try {
      return await widget.onFetchSlots!(widget.to.id);
    } finally {
      if (mounted) setState(() => _isFetchingSlots = false);
    }
  }

  // ── 지원 상태 ─────────────────────────────────────────

  bool get _hasApplied => _cachedHasApplied;

  bool _legacyMatch(ApplicationModel app) {
    final to = widget.to;
    if (app.businessId != to.businessId || app.toTitle != to.title) return false;
    if (to.isLongTerm) return true;
    return app.workDate.year == to.date.year &&
        app.workDate.month == to.date.month &&
        app.workDate.day == to.date.day;
  }

  // M3: O(n) → O(1) — _rebuildAppliedSets()로 사전 계산된 Set 조회
  bool _hasAppliedForSlot(SlotModel slot) {
    if (_appliedSlotIds.contains(slot.id)) return true;
    final key = '${slot.date.year}-${slot.date.month}-${slot.date.day}';
    return _appliedDateKeys.contains(key);
  }

  ApplicationModel? _appForWork(WorkDetailModel work) {
    try {
      return widget.myApplications.firstWhere((app) {
        if (app.selectedWorkType != work.workType || app.startTime != work.startTime) {
          return false;
        }
        if (!ApplicationRelationResolver.holdsRelation(app)) return false;
        if (app.toId?.isNotEmpty == true) return app.toId == widget.to.id;
        return _legacyMatch(app);
      });
    } catch (_) {
      return null;
    }
  }

  // ── 마감 임박 ─────────────────────────────────────────

  bool get _isUrgent {
    // contract TO: TO 레벨 applicationDeadline 기준
    if (!widget.to.isFlexType) return widget.to.isDeadlineUrgent;
    // flex TO: 로드된 슬롯 중 24시간 내 마감 슬롯 존재 여부
    final slots = widget.slots;
    if (slots == null) return false;
    final now = _buildNow;
    return slots.any((s) {
      if (s.isEffectivelyClosed) return false;
      final dl = s.applicationDeadline;
      if (dl == null) return false;
      final diff = dl.difference(now);
      return diff.inSeconds > 0 && diff.inHours <= 24;
    });
  }

  // ── 표시 문자열 ───────────────────────────────────────

  String get _dateText {
    final to = widget.to;
    if (!to.isLongTerm) return FormatHelper.formatDateCompact(to.date);

    // custom: 관리자가 직접 지정한 고정 기간
    if (to.contractPeriodType == 'custom') {
      if (to.rangeStart != null && to.rangeEnd != null) {
        return '${FormatHelper.formatDateCompact(to.rangeStart!)} ~ '
            '${FormatHelper.formatDateCompact(to.rangeEnd!)}';
      }
      return FormatHelper.formatDateCompact(to.date);
    }

    // preset 신규 정책: 근무 시작 가능기간 표시
    if (to.hasWorkStartAvailableRange) {
      return '${FormatHelper.formatDateCompact(to.workStartAvailableFrom!)} ~ '
          '${FormatHelper.formatDateCompact(to.workStartAvailableUntil!)}';
    }

    // legacy: rangeStart ~ rangeEnd (구 데이터 호환)
    if (to.rangeStart != null && to.rangeEnd != null) {
      return '${FormatHelper.formatDateCompact(to.rangeStart!)} ~ '
          '${FormatHelper.formatDateCompact(to.rangeEnd!)}';
    }

    return FormatHelper.formatDateCompact(to.date);
  }

  String get _wageLabel =>
      widget.to.wageType != null
          ? FormatHelper.getWageTypeLabel(widget.to.wageType!)
          : '급여';

  String get _wageAmount {
    final to = widget.to;
    if (to.maxWage == null) return '-';
    if (to.minWage == to.maxWage) return FormatHelper.formatWage(to.maxWage!);
    return '~${FormatHelper.formatNumber(to.maxWage!)}원';
  }

  String get _location => FormatHelper.formatLocation(
        address: widget.to.businessAddress,
        city: widget.to.businessCity,
        district: widget.to.businessDistrict,
      );

  String get _timeAgo => _cachedTimeAgo;

  String? get _workHint {
    final list = widget.to.workDetails;
    if (list.isEmpty) return null;
    if (list.length == 1) return list.first.workType;
    return '${list.first.workType} 외 ${list.length - 1}개';
  }

  String? get _recruitText {
    // Flex TO: 인원 합산은 의미 없음 (날짜별 인원이 다를 수 있음)
    // → 공개된 날파 수로 표시
    if (widget.to.isFlexType) {
      final slots = widget.slots;
      if (slots != null && slots.isNotEmpty) {
        // 슬롯 로드됨: 현재 공개 + 비마감 날파 수
        final now = DateTime.now();
        final openCount = slots.where((s) =>
          !s.isEffectivelyClosed &&
          (s.visibleFrom == null || !s.visibleFrom!.isAfter(now))
        ).length;
        if (openCount > 0) return '$openCount개 날파';
      }
      // 슬롯 미로드: totalSlots(전체 날파 수) fallback
      final total = widget.to.totalSlots;
      return total > 0 ? '$total개 날파' : null;
    }
    // Contract TO: 기존 N/M명 표시
    final req = widget.to.totalRequired;
    if (req <= 0) return null;
    return '${widget.to.totalConfirmed}/$req명';
  }

  // ── compact 모드 전용 표시 ──────────────────────────────

  /// compact 모드 날짜 텍스트
  /// flex TO 복수 날파: "8/12(수) 외 9일"
  /// flex TO 단일: "8/12(수)"
  /// contract TO custom: "8/12(수) ~ 9/30(화)" (고정 기간)
  /// contract TO preset 신규: "8/12(수) ~ 9/30(화)" (시작 가능기간)
  /// contract TO legacy: "8/12(수) ~ 9/30(화)"
  String get _compactDateText {
    final to = widget.to;
    if (!to.isLongTerm) {
      // flex TO
      final total = to.totalSlots;
      final first = FormatHelper.formatDateCompact(to.date);
      if (total <= 1) return first;
      return '$first 외 ${total - 1}일';
    }

    // custom: 고정 기간
    if (to.contractPeriodType == 'custom') {
      if (to.rangeStart != null && to.rangeEnd != null) {
        return '${FormatHelper.formatDateCompact(to.rangeStart!)} ~ '
            '${FormatHelper.formatDateCompact(to.rangeEnd!)}';
      }
      return FormatHelper.formatDateCompact(to.date);
    }

    // preset 신규 정책: 근무 시작 가능기간
    if (to.hasWorkStartAvailableRange) {
      return '${FormatHelper.formatDateCompact(to.workStartAvailableFrom!)} ~ '
          '${FormatHelper.formatDateCompact(to.workStartAvailableUntil!)}';
    }

    // legacy
    if (to.rangeStart != null && to.rangeEnd != null) {
      return '${FormatHelper.formatDateCompact(to.rangeStart!)} ~ '
          '${FormatHelper.formatDateCompact(to.rangeEnd!)}';
    }

    return FormatHelper.formatDateCompact(to.date);
  }

  /// compact 모드 시간 텍스트
  /// 업무 없거나 모두 같은 시간 → "09:00 ~ 18:00" 반환
  /// 시간이 다르면 null → _compactWorkSuffix 사용
  String? get _compactTimeText {
    final wds = widget.to.workDetails;
    if (wds.isEmpty) {
      final tr = widget.to.timeRange;
      return tr.startsWith('--') ? null : tr;
    }
    if (wds.length == 1) return wds.first.timeRange;
    final first = wds.first;
    final allSame = wds.every(
        (wd) => wd.startTime == first.startTime && wd.endTime == first.endTime);
    if (allSame) return first.timeRange;
    return null;
  }

  /// 업무·시간이 여러 종류일 때 대체 문구 (ex. "업무 2종")
  String? get _compactWorkSuffix {
    final wds = widget.to.workDetails;
    if (wds.length <= 1) return null;
    final first = wds.first;
    final allSame = wds.every(
        (wd) => wd.startTime == first.startTime && wd.endTime == first.endTime);
    if (allSame) return null;
    return '업무 ${wds.length}종';
  }

  /// compact 모드 모집 현황 텍스트
  /// flex TO: null (날짜 텍스트가 날파 수 표현)
  /// contract TO: "잔여 N명" / "모집 마감"
  String? get _compactRecruitText {
    if (widget.to.isFlexType) return null;
    final req = widget.to.totalRequired;
    if (req <= 0) return null;
    final remaining = req - widget.to.totalConfirmed;
    if (remaining <= 0) return '모집 마감';
    return '잔여 $remaining명';
  }

  /// compact 모드 급여 표시
  /// 여러 업무 급여가 다르면 최솟값 기준 "70,000원~"
  String get _compactWageAmount {
    final to = widget.to;
    if (to.maxWage == null) return '-';
    if (to.minWage == null || to.minWage == to.maxWage) {
      return FormatHelper.formatWage(to.maxWage!);
    }
    return '${FormatHelper.formatNumber(to.minWage!)}원~';
  }

  // ── Build ──────────────────────────────────────────────

  // 탭 시 선택 토글 — selectedNotifier.value 변경만으로 ValueListenableBuilder가 rebuild 처리
  void _toggleSelection() {
    final id = widget.to.id;
    final notifier = widget.selectedNotifier!;
    notifier.value = notifier.value == id ? null : id;
  }

  @override
  Widget build(BuildContext context) {
    // compact 모드: 컴팩트 카드 바로 반환 (ValueListenableBuilder 불필요)
    if (widget.compact) return _buildCompactCard(context);

    // 일반 모드: ValueListenableBuilder — 선택 상태가 바뀔 때 이 카드(2개 최대)만 rebuild
    return ValueListenableBuilder<String?>(
      valueListenable: widget.selectedNotifier!,
      builder: (context, selectedId, _) {
        final isSelected = selectedId == widget.to.id;
        final isAnyOtherExpanded =
            selectedId != null && selectedId != widget.to.id;
        return _buildCard(context, isSelected, isAnyOtherExpanded);
      },
    );
  }

  // ── 컴팩트 카드 (탐색 전용, compact=true) ─────────────────────────────

  Widget _buildCompactCard(BuildContext context) {
    final to = widget.to;
    final theme = Theme.of(context);

    // 위치·사업장명
    final loc = _location.isNotEmpty ? _location : '위치 미정';
    final biz = to.businessName;
    final locationBiz = biz.isNotEmpty ? '$loc · $biz' : loc;

    // 근무유형 · 급여유형 인라인 텍스트
    final typeStr = to.isLongTerm ? '장기' : '단기';

    // compact 모드 전용 — 날짜·시간·업무종류·모집현황·급여
    final compactTime = _compactTimeText;
    final workSuffix = _compactWorkSuffix;
    final recruitText = _compactRecruitText;

    return Card(
      margin: EdgeInsets.only(
          bottom: ResponsiveHelper.spacing(context, 7)),
      color: Colors.white,
      elevation: 0,
      shadowColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.borderLight, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _goToDetailCompact,
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── 상단 행: 위치·사업장명 / 시간ago + 상태칩 + ♡ ──
              // [SCALE-BALANCE.34] 큰 글자에서 위치가 '위치 …'·'강남구 강남구 · [...' 로 사라졌다 —
              //   기본 배치가 안 들어가면 위치 줄을 넓게, 상태·시각·찜은 다음 줄로.
              if (!_rowFits(context, 330))
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // [SCALE-BALANCE.34] 핀은 위치 첫 줄 높이 가운데에.
                    Padding(padding: EdgeInsets.only(top: ((MediaQuery.textScalerOf(context).scale(13) * 1.4 - ResponsiveHelper.iconSize(context, 12)) / 2).clamp(0.0, 30.0)), child: Icon(Icons.location_on,
                        size: ResponsiveHelper.iconSize(context, 12), color: theme.primaryColor)),
                    SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                    Expanded(
                      child: Text(TextLayout.phrases(locationBiz),
                          semanticsLabel: locationBiz,
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                    ),
                  ]),
                  Row(children: [
                    ..._statusBadgeWidgets(context).skip(1),
                    if (_hasApplied || _isUrgent) SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    // [DU458] 게시 시각 grey500(2.68) → textTertiary — 전체 카드 머리와 같은 보조 글자.
                    Flexible(
                      child: Text(_timeAgo,
                          style: ResponsiveHelper.tinyStyle(context, color: AppColors.textTertiary)),
                    ),
                    const Spacer(),
                    _buildFavoriteButton(context),
                  ]),
                ])
              else
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(Icons.location_on,
                      size: ResponsiveHelper.iconSize(context, 12),
                      color: theme.primaryColor),
                  SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                  Expanded(
                    child: Text(
                      locationBiz,
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w500),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // 상태 배지: 시간ago 앞 배치 — 마감임박 등 긴급 상태를 먼저 인지
                  // (SizedBox는 _statusBadgeWidgets 내부에 포함)
                  ..._statusBadgeWidgets(context),
                  SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                  Text(
                    _timeAgo,
                    // [DU458] grey500(2.68) → textTertiary.
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.textTertiary),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  _buildFavoriteButton(context),
                ],
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 6)),

              // ── 공고 제목 ──
              Text(
                to.title,
                style: ResponsiveHelper.titleStyle(context).copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  letterSpacing: -0.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 3)),

              // ── 근무유형 · 급여유형 ──
              Text(
                '$typeStr · $_wageLabel',
                // [DU464] 작은 카드 메타 grey500(2.68) → textTertiary — 큰 카드 요약 · 인원(DU450)과 같은 보조 글자.
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.textTertiary),
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 8)),

              // ── 날짜 · 시간/업무종류 행 ──
              // flex TO 복수 날파: "8/12(수) 외 9일"
              // 시간이 다른 업무: 시간 대신 "업무 N종" 표시
              // [SCALE-BALANCE.34] 큰 글자에서 '09:00 ~ 13:…' 로 잘렸다 — 덩어리째 줄바꿈.
              if (!_rowFits(context, 300))
                _chunkWrap(context, [
                  _chunk(context, Icons.calendar_today, _compactDateText,
                      ResponsiveHelper.smallStyle(context, color: AppColors.grey700, fontWeight: FontWeight.w500)),
                  if (compactTime != null)
                    _chunk(context, Icons.schedule, compactTime,
                        ResponsiveHelper.smallStyle(context, color: AppColors.grey600))
                  else if (workSuffix != null)
                    // [DU464] grey500 → textTertiary(가로 배치와 같다).
                    _chunk(context, null, workSuffix, ResponsiveHelper.smallStyle(context, color: AppColors.textTertiary)),
                ])
              else
              Row(
                children: [
                  Icon(Icons.calendar_today,
                      size: ResponsiveHelper.iconSize(context, 12),
                      color: AppColors.grey400),
                  SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  Flexible(
                    child: Text(
                      _compactDateText,
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey700,
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (compactTime != null) ...[
                    _divider(context),
                    Icon(Icons.schedule,
                        size: ResponsiveHelper.iconSize(context, 12),
                        color: AppColors.grey400),
                    SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                    Flexible(
                      child: Text(
                        compactTime,
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey600),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ] else if (workSuffix != null) ...[
                    _divider(context),
                    Text(
                      workSuffix,
                      // [DU464] grey500 → textTertiary.
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.textTertiary),
                    ),
                  ],
                ],
              ),

              SizedBox(height: ResponsiveHelper.spacing(context, 10)),
              Container(height: 1, color: AppColors.grey100),
              SizedBox(height: ResponsiveHelper.spacing(context, 10)),

              // ── 급여 · 모집현황 행 ──
              // [일급/시급] Badge 제거 — 상단 "단기 · 일급" 텍스트와 중복
              // 모집현황: "잔여 N명" / "모집 마감" (contract TO만, flex TO는 날짜로 표현)
              Row(
                children: [
                  // [DU465] B(320 · 2.0)에서 급여가 '12,00…'로 잘렸다 — Flexible + Spacer 가 남는 폭을 반씩 나눴다.
                  //   Expanded 로 남는 폭을 모두 쓰고, 말줄임 대신 쉼표 뒤에서만 줄바꿈(읽기는 원문). 모집 현황은 오른쪽 끝 그대로.
                  Expanded(
                    child: Text(
                      TextLayout.amount(_compactWageAmount),
                      semanticsLabel: _compactWageAmount,
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  if (recruitText != null) ...[
                    Icon(Icons.people_outline,
                        size: ResponsiveHelper.iconSize(context, 12),
                        color: AppColors.grey400),
                    SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                    Text(
                      recruitText,
                      // [DU464] '잔여 N명' grey500 · '모집 마감' grey400 → textTertiary(큰 카드 인원 · DU450). 문구가 상태를 말한다.
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.textTertiary),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 컴팩트 카드 탭 → 공고 상세 화면
  Future<void> _goToDetailCompact() async {
    final result = await NavigationHelper.push<bool>(
      context,
      destination: JobPostingScreen(
        to: widget.to,
        workDetails: widget.to.workDetails,
        // [R7-P2-2 P22-N] 목록에서 보고 있던 하루를 상세까지 들고 간다.
        slotDate: widget.selectedDate,
      ),
    );
    if (result == true && mounted) widget.onApplySuccess();
  }

  // ── 일반 카드 (compact=false) ───────────────────────────────────────

  Widget _buildCard(
      BuildContext context, bool isSelected, bool isAnyOtherExpanded) {
    final theme = Theme.of(context);
    final to = widget.to;
    final barColor = to.isLongTerm ? AppColors.longTerm : AppColors.shortTerm;

    final card = Card(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
        elevation: isSelected ? 2 : 0.5,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected ? theme.primaryColor : AppColors.border,
            width: isSelected ? 1.5 : 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            // 왼쪽 컬러바
            Positioned(
              left: 0, top: 0, bottom: 0,
              child: Container(
                width: ResponsiveHelper.spacing(context, 5),
                color: barColor,
              ),
            ),
            Padding(
              padding: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 5)),
              child: InkWell(
                onTap: _toggleSelection,
                child: Container(
                  color: isSelected
                      ? theme.primaryColor.withValues(alpha: 0.02)
                      : AppColors.surface,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 접힌 영역
                      Padding(
                        padding: EdgeInsets.fromLTRB(
                          ResponsiveHelper.spacing(context, 12),
                          ResponsiveHelper.spacing(context, 10),
                          ResponsiveHelper.spacing(context, 12),
                          0,
                        ),
                        child: _buildCollapsed(context, theme),
                      ),
                      // 펼치기 바
                      _buildExpandBar(context, isSelected),
                      // 펼친 영역
                      AnimatedSize(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeInOutCubic,
                        alignment: Alignment.topCenter,
                        clipBehavior: Clip.antiAlias,
                        child: isSelected
                            ? TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeIn,
                                builder: (context, opacity, child) =>
                                    Opacity(opacity: opacity, child: child!),
                                child: Column(children: [
                                  const Divider(height: 1, color: AppColors.grey100),
                                  _buildExpanded(context),
                                ]),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
    );
    if (!isAnyOtherExpanded) return card;
    return AnimatedOpacity(
      opacity: 0.5,
      duration: const Duration(milliseconds: 200),
      child: card,
    );
  }

  // ── 접힌 상태 ──────────────────────────────────────────

  Widget _buildCollapsed(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTopRow(context, theme),
        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
        // [DU450] B 에서 '물류센터 장기 근 / 무'처럼 음절에서 끊겼다 — 이름 규칙(낱말 단위 · 긴 낱말은 가운데에서만 · 읽기는 원문).
        Text(
          TextLayout.identity(widget.to.title),
          semanticsLabel: widget.to.title,
          style: ResponsiveHelper.titleStyle(context).copyWith(
            fontWeight: FontWeight.bold,
            height: 1.3,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
        _buildDateTimeRow(context),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Container(height: 1, color: AppColors.grey100),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        _buildWageRow(context),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        _buildActionRow(context, theme),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
      ],
    );
  }

  Widget _buildTopRow(BuildContext context, ThemeData theme) {
    // 위치 · 사업장명 합치기 (단기/고정 공통 — 별도 사업장명 행 제거)
    final loc = _location.isNotEmpty ? _location : '위치 미정';
    final biz = widget.to.businessName;
    final locationBiz = biz.isNotEmpty ? '$loc · $biz' : loc;

    // [SCALE-BALANCE.34] 큰 글자에서 한 줄에 위치·등록시각·지원완료·찜을 다 넣어 위치가 '위치 …' 로 사라졌다(392·2.0 기기).
    //   기본 배치가 들어가지 않으면 위치 줄을 넓게 쓰고(낱말 단위 줄바꿈), 나머지는 다음 줄로.
    if (!_rowFits(context, 330)) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _typeBadge(context),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          // [SCALE-BALANCE.34] 핀은 위치 첫 줄 높이 가운데에.
          Padding(padding: EdgeInsets.only(top: ((MediaQuery.textScalerOf(context).scale(13) * 1.4 - ResponsiveHelper.iconSize(context, 13)) / 2).clamp(0.0, 30.0)), child: Icon(Icons.location_on,
              size: ResponsiveHelper.iconSize(context, 13), color: theme.primaryColor)),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Expanded(
            child: Text(
              TextLayout.phrases(locationBiz),
              semanticsLabel: locationBiz,
              style: ResponsiveHelper.smallStyle(context).copyWith(
                fontWeight: FontWeight.w500, color: theme.primaryColor),
            ),
          ),
        ]),
        // [DU458] 게시 시각 grey400(1.88) → textTertiary — 같은 카드 인원 · 요약(DU450)과 같은 보조 글자.
        Row(children: [
          Flexible(
            child: Text(_timeAgo,
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.textTertiary)),
          ),
          ..._statusBadgeWidgets(context),
          const Spacer(),
          _buildFavoriteButton(context),
        ]),
      ]);
    }

    return Row(
      children: [
        _typeBadge(context),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Icon(Icons.location_on,
            size: ResponsiveHelper.iconSize(context, 13),
            color: theme.primaryColor),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        Expanded(
          child: Text(
            locationBiz,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              fontWeight: FontWeight.w500,
              color: theme.primaryColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        // 등록 시간 — 헤더 우측 (사업장명 행 제거로 이동)
        // Flexible 필수: overflow:ellipsis는 bounded constraint에서만 동작
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Flexible(
          fit: FlexFit.loose,
          child: Text(
            _timeAgo,
            // [DU458] grey400(1.88) → textTertiary(좁은 배치와 같다).
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.textTertiary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ..._statusBadgeWidgets(context),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        _buildFavoriteButton(context),
      ],
    );
  }

  Widget _buildFavoriteButton(BuildContext context) {
    return Selector<UserProvider, bool>(
      selector: (_, p) => p.isFavoriteTo(widget.to.id),
      builder: (ctx, isFav, _) => GestureDetector(
        onTap: () => ctx.read<UserProvider>().toggleFavoriteTo(widget.to.id),
        behavior: HitTestBehavior.opaque,
        child: SizedBox(
          width: ResponsiveHelper.spacing(ctx, 36),
          height: ResponsiveHelper.spacing(ctx, 36),
          child: Center(
            child: Icon(
              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              size: ResponsiveHelper.iconSize(ctx, 18),
              // [DU458] 비활성 하트 grey300(누를 수 있는 아이콘인데 거의 안 보임) → textSecondary(DU310 user_job_tab 비활성 하트와 같다).
              color: isFav ? AppColors.error : AppColors.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _statusBadgeWidgets(BuildContext context) {
    return [
      if (_hasApplied) ...[
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        // [DU457] success 채움 + 흰 글자(2.78) → 지원 대화 업무 카드(WorkSelectionCard · DU274 WC3)의 '지원완료'와 같은 infoBg/infoDeep(7.56).
        _pill(context, '지원완료', AppColors.infoBg, AppColors.infoDeep),
      ],
      if (_isUrgent) ...[
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        _pill(context, '마감임박', AppColors.warningDark, Colors.white),
      ],
    ];
  }

  /// [SCALE-BALANCE.34] 기본 배치(한 줄)가 들어가는가 — 카드 일반·compact 가 같은 기준을 쓴다.
  bool _rowFits(BuildContext context, double base) =>
      TextLayout.fits(context, MediaQuery.sizeOf(context).width - 56, base);

  /// [SCALE-BALANCE.34] 아이콘 + 한 덩어리 글자(안에서는 줄을 바꾸지 않는다).
  Widget _chunk(BuildContext context, IconData? icon, String text, TextStyle style) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[
          Icon(icon, size: ResponsiveHelper.iconSize(context, 13), color: AppColors.grey500),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        ],
        Flexible(child: Text(TextLayout.unit(text), semanticsLabel: text, style: style)),
      ]);

  /// [SCALE-BALANCE.34] 덩어리들을 한 줄에, 모자라면 덩어리째 다음 줄로 — 말줄임 없음.
  Widget _chunkWrap(BuildContext context, List<Widget> chunks) => Wrap(
        spacing: ResponsiveHelper.spacing(context, 10),
        runSpacing: ResponsiveHelper.spacing(context, 2),
        crossAxisAlignment: WrapCrossAlignment.center,
        children: chunks,
      );

  Widget _buildDateTimeRow(BuildContext context) {
    final timeRange = widget.to.timeRange;
    final showTime = !timeRange.startsWith('--');

    // [SCALE-BALANCE.34] 큰 글자에서 '09:00 ~ 13:…' 으로 시간이 잘렸다 — 날짜·시간·요일을 각각 한 덩어리로 두고
    //   한 줄에 안 들어가면 덩어리째 다음 줄로(말줄임 없음). 기본 배치가 들어가면 예전 그대로.
    if (!_rowFits(context, 300)) {
      final st = ResponsiveHelper.smallStyle(context, color: AppColors.grey700);
      return _chunkWrap(context, [
        _chunk(context, Icons.calendar_today, _dateText, st.copyWith(fontWeight: FontWeight.w500)),
        if (showTime) _chunk(context, Icons.schedule, timeRange, st),
        if (widget.to.isLongTerm && widget.to.workDays.isNotEmpty)
          _chunk(context, null, widget.to.workDaysLabel, ResponsiveHelper.smallStyle(context, color: AppColors.grey600)),
      ]);
    }

    return Row(
      children: [
        Icon(Icons.calendar_today,
            size: ResponsiveHelper.iconSize(context, 13),
            color: AppColors.grey500),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Flexible(
          child: Text(
            _dateText,
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.grey700, fontWeight: FontWeight.w500),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (showTime) ...[
          _divider(context),
          Icon(Icons.schedule,
              size: ResponsiveHelper.iconSize(context, 13),
              color: AppColors.grey500),
          SizedBox(width: ResponsiveHelper.spacing(context, 3)),
          Flexible(
            child: Text(
              timeRange,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
        if (widget.to.isLongTerm && widget.to.workDays.isNotEmpty) ...[
          _divider(context),
          Flexible(
            child: Text(
              widget.to.workDaysLabel,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }


  // [DU450] B 에서 업무 요약이 '분…'으로 말줄임되고 인원 '0/9명'이 카드 끝에 걸렸다 — 옆 칸이 모자라면 두 줄(금액 / 요약 + 인원).
  //   요약 · 인원 grey500(2.68) → textTertiary, 인원 아이콘 grey400 → grey600. 넓으면 한 줄 그대로다.
  Widget _buildWageRow(BuildContext context) {
    final hint = _workHint;
    final recruit = _recruitText;
    final pill = _pill(context, _wageLabel, AppColors.successBg, AppColors.successDark,
        border: AppColors.successLight);
    final amount = Text(
      _wageAmount,
      style: ResponsiveHelper.subtitleStyle(context).copyWith(
        color: AppColors.successDark,
        fontWeight: FontWeight.bold,
      ),
      overflow: TextOverflow.ellipsis,
    );
    final people = recruit == null
        ? const <Widget>[]
        : <Widget>[
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            Icon(Icons.people_outline,
                size: ResponsiveHelper.iconSize(context, 13),
                color: AppColors.grey600),
            SizedBox(width: ResponsiveHelper.spacing(context, 2)),
            Text(
              recruit,
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.textTertiary),
              overflow: TextOverflow.ellipsis,
            ),
          ];
    return LayoutBuilder(builder: (_, box) {
      if (TextLayout.fits(context, box.maxWidth, 300)) {
        return Row(
          children: [
            pill,
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Flexible(child: amount),
            if (hint != null) ...[
              Padding(
                padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 6)),
                child: Text('·',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey300)),
              ),
              Expanded(
                child: Text(
                  hint,
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.textTertiary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ] else
              const Spacer(),
            ...people,
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [pill, SizedBox(width: ResponsiveHelper.spacing(context, 6)), Flexible(child: amount)]),
          if (hint != null || recruit != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hint != null)
                  Expanded(
                    child: Text(
                      TextLayout.keepWords(hint),
                      semanticsLabel: hint,
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.textTertiary),
                    ),
                  )
                else
                  const Spacer(),
                ...people,
              ],
            ),
          ],
        ],
      );
    });
  }

  // [DU450] B 에서 두 버튼이 카드 밖으로 넘쳤다('지원관' 뒤) — 옆 칸이 모자라면 두 버튼을 위아래 전체 폭으로(순서 · 동작 그대로).
  Widget _buildActionRow(BuildContext context, ThemeData theme) {
    return LayoutBuilder(builder: (_, box) {
      final wide = TextLayout.fits(context, box.maxWidth, 230);
      final detail = _actionBtn(context,
          label: '상세보기',
          icon: Icons.article_outlined,
          onTap: _goToDetail,
          primary: false,
          expand: !wide);
      final apply = _isApplyLoading
          ? _loadingBtn(context, theme)
          : _actionBtn(context,
              label: _hasApplied ? '지원관리' : '지원하기',
              icon: _hasApplied ? Icons.manage_accounts_outlined : Icons.send,
              onTap: _openApplyDialog,
              primary: !_hasApplied,
              expand: !wide);
      if (wide) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [detail, SizedBox(width: ResponsiveHelper.spacing(context, 8)), apply],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [detail, SizedBox(height: ResponsiveHelper.spacing(context, 8)), apply],
      );
    });
  }

  Widget _buildExpandBar(BuildContext context, bool isSelected) {
    final theme = Theme.of(context);
    final label = isSelected
        ? '접기'
        : widget.to.isFlexType
            ? '날짜 선택'
            : '업무 상세';

    return Container(
      color: isSelected
          ? theme.primaryColor.withValues(alpha: 0.05)
          : AppColors.grey50,
      padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 6)),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSelected
                ? Icons.keyboard_arrow_up
                : widget.to.isFlexType
                    ? Icons.calendar_today_outlined
                    : Icons.expand_more,
            size: ResponsiveHelper.iconSize(context, 13),
            // [DU460] 접힌 상태 화살표 grey400 → textSecondary — 누르는 줄의 아이콘(DU458 비활성 하트와 같은 짝).
            color: isSelected ? theme.primaryColor : AppColors.textSecondary,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context,
                // [DU460] 접힌 상태 이름표 grey500(grey50 위 2.56) → textSecondary.
                color: isSelected ? theme.primaryColor : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal),
          ),
        ],
      ),
    );
  }

  // ── 펼친 상태 ──────────────────────────────────────────

  Widget _buildExpanded(BuildContext context) {
    final isPending = widget.to.isPendingPublish;

    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isPending) ...[
            _pendingNotice(context),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          ],
          if (widget.to.description?.isNotEmpty == true) ...[
            _descriptionPreview(context),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          ],
          // flex TO: 날짜-슬롯 목록 / contract TO: 업무 목록
          if (widget.to.isFlexType)
            _buildFlexSlotList(context)
          else
            Opacity(
              opacity: isPending ? 0.4 : 1.0,
              child: _buildWorkList(context),
            ),
        ],
      ),
    );
  }

  // ── flex TO 날짜-슬롯 목록 ─────────────────────────────

  Widget _buildFlexSlotList(BuildContext context) {
    if (_showSlotsLoading) {
      return Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        child: const LoadingWidget(),
      );
    }

    // null = 아직 fetch 안 됨 / 빈 리스트 = fetch 완료 후 슬롯 없음
    if (widget.slots == null) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 8)),
        child: Text(
          '날짜 정보를 불러오는 중...',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
        ),
      );
    }
    if (widget.slots!.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 8)),
        child: Text(
          '등록된 날짜가 없습니다',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
        ),
      );
    }

    final slots = widget.slots!;
    final now = _buildNow;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.calendar_month_outlined,
                size: ResponsiveHelper.iconSize(context, 14),
                color: AppColors.grey600),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              '날짜별 근무',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey700, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Text(
              '${slots.length}개 날짜',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        ...slots.map((slot) => _buildSlotRow(context, slot, now)),
      ],
    );
  }

  Widget _buildSlotRow(BuildContext context, SlotModel slot, DateTime now) {
    final isPending = slot.visibleFrom != null && slot.visibleFrom!.isAfter(now);
    // 모델 단일 진실 소스 사용 — wd.isClosed(수동마감) + slot.applicationDeadline 모두 포함
    final isEffectivelyClosed = slot.isEffectivelyClosed;
    final isDisabled = isPending || isEffectivelyClosed;

    final hasApplied = _hasAppliedForSlot(slot);

    // 배지 우선순위: 지원완료 > 예약(visibleFrom 미래) > 충족 > 마감 > 모집중
    // isFull을 isEffectivelyClosed보다 먼저 체크: slot.isFull은 isEffectivelyClosed에
    // 포함되지만 '충족'과 '마감'을 구분 표시하기 위해 별도 처리.
    // TO 레벨 isManualClosed는 공고 목록 필터에서 이미 제외되므로 여기서 불필요.
    String statusLabel;
    Color statusBg;
    Color statusFg;
    if (hasApplied) {
      statusLabel = '지원완료';
      statusBg = AppColors.infoBg;
      statusFg = AppColors.info;
    } else if (isPending) {
      statusLabel = '예약';
      statusBg = AppColors.warningBg;
      statusFg = AppColors.warningDark;
    } else if (slot.isFull) {
      statusLabel = '충족';
      statusBg = AppColors.grey100;
      statusFg = AppColors.grey500;
    } else if (isEffectivelyClosed) {
      statusLabel = '마감';
      statusBg = AppColors.grey100;
      statusFg = AppColors.grey500;
    } else {
      // [R7-P1-2] 모집중은 진행 상태다 — green 은 충족·확정에 남긴다.
      statusLabel = '모집중';
      statusBg = AppColors.infoBg;
      statusFg = AppColors.infoDark;
    }

    // 업무 힌트 (슬롯 자체 workDetails 사용)
    final workHint = slot.workDetails.isEmpty
        ? null
        : slot.workDetails.length == 1
            ? slot.workDetails.first.workType
            : '${slot.workDetails.first.workType} 외 ${slot.workDetails.length - 1}개';

    final slotDate = slot.date;
    // [TZ-FIX] KST calendar date 기준 표시 — device timezone 무관
    final kstSlotDate = FormatHelper.toKstDate(slotDate);
    final dateLabel = '${kstSlotDate.month}월 ${kstSlotDate.day}일';
    final semanticDesc = isDisabled
        ? '$dateLabel 슬롯, 마감됨'
        : hasApplied
            ? '$dateLabel 슬롯, 지원 완료, 상세 보기'
            : '$dateLabel 슬롯, 지원 가능, 공고 상세 보기';

    return Semantics(
      label: semanticDesc,
      button: !(isDisabled && !hasApplied),
      enabled: !(isDisabled && !hasApplied),
      child: GestureDetector(
      // 마감된 슬롯은 상세 진입 불가 (지원완료 상태는 확인 가능하도록 허용)
      onTap: (isDisabled && !hasApplied) ? null : () => _goToDetailForSlot(slot),
      child: Opacity(
      opacity: (isDisabled && !hasApplied) ? 0.55 : 1.0,
      child: Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 10),
          vertical: ResponsiveHelper.spacing(context, 9),
        ),
        decoration: BoxDecoration(
          color: hasApplied
              ? AppColors.infoBg
              : isDisabled
                  ? AppColors.grey50
                  : AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: hasApplied
                ? AppColors.infoLight
                : isDisabled
                    ? AppColors.grey200
                    : AppColors.grey300,
          ),
        ),
        child: Row(
          children: [
            // 날짜 배지
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 7),
                vertical: ResponsiveHelper.spacing(context, 3),
              ),
              decoration: BoxDecoration(
                color: AppColors.shortTermBg,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.shortTermLight),
              ),
              child: Text(
                FormatHelper.formatDateCompact(slot.date),
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.shortTermDark,
                    fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            // 업무 힌트
            Expanded(
              child: workHint != null
                  ? Text(
                      workHint,
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    )
                  : const SizedBox.shrink(),
            ),
            // 인원 현황 — "확정/모집" 또는 "확정/모집 +대기" (예약 슬롯 미표시)
            if (!isPending) ...[
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              // Flexible 필수: Row 내 무한 제약 → overflow: ellipsis 미동작 방지
              Flexible(
                fit: FlexFit.loose,
                child: Builder(builder: (_) {
                  final req = slot.totalRequired;
                  if (req <= 0) return const SizedBox.shrink();
                  final conf = slot.confirmedCount;
                  final pend = slot.pendingCount;
                  final label = pend > 0 ? '$conf/$req +$pend' : '$conf/$req';
                  final color = slot.isFull
                      ? AppColors.grey400
                      : pend > 0
                          ? AppColors.warning
                          : AppColors.grey500;
                  return Text(
                    label,
                    style: ResponsiveHelper.tinyStyle(context, color: color),
                    overflow: TextOverflow.ellipsis,
                  );
                }),
              ),
            ],
            // 상태 칩
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            _statusChip(context, statusLabel, statusBg, statusFg),
            // 지원 버튼 (마감 아닐 때만)
            if (!isDisabled) ...[
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _slotApplyBtn(context, slot, hasApplied),
            ],
          ],
        ),
      ),
    ), // Opacity
    ), // GestureDetector
    ); // Semantics
  }

  Widget _slotApplyBtn(BuildContext context, SlotModel slot, bool hasApplied) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => _openApplyDialogForSlot(slot),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 10),
          vertical: ResponsiveHelper.spacing(context, 5),
        ),
        decoration: BoxDecoration(
          color: hasApplied
              ? Colors.transparent
              : theme.primaryColor,
          borderRadius: BorderRadius.circular(6),
          border: hasApplied
              ? Border.all(color: AppColors.info)
              : null,
        ),
        child: Text(
          hasApplied ? '지원관리' : '지원하기',
          style: ResponsiveHelper.tinyStyle(context,
              color: hasApplied ? AppColors.info : Colors.white,
              fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _statusChip(BuildContext context, String label, Color bg, Color fg) =>
      ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 72),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 6),
            vertical: ResponsiveHelper.spacing(context, 3),
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(label,
              style: ResponsiveHelper.tinyStyle(context,
                  color: fg, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
              maxLines: 1),
        ),
      );

  // ── contract TO 업무 목록 ──────────────────────────────

  Widget _pendingNotice(BuildContext context) => Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warningLight),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.warningDark),
            SizedBox(width: ResponsiveHelper.spacing(context, 10)),
            Expanded(
              child: Text(
                widget.to.publishAtDisplay != null
                    ? '${widget.to.publishAtDisplay}에 오픈됩니다'
                    : '곧 오픈 예정입니다',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.warningDark, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );

  Widget _descriptionPreview(BuildContext context) => Container(
        width: double.infinity,
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
        decoration: BoxDecoration(
          color: AppColors.grey50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.grey200),
        ),
        child: Text(
          widget.to.description!,
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );

  Widget _buildWorkList(BuildContext context) {
    if (_showLoading) {
      return Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        child: const LoadingWidget(),
      );
    }
    if (_workDetails.isEmpty) {
      return Padding(
        padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 8)),
        child: Text('업무 목록을 불러오는 중...',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500)),
      );
    }

    final dups = _workDetails
        .map((w) => w.workType)
        .fold<Map<String, int>>({}, (m, t) {
          m[t] = (m[t] ?? 0) + 1;
          return m;
        })
        .entries
        .where((e) => e.value > 1)
        .map((e) => e.key)
        .toSet();

    return Column(
      children: _workDetails
          .map((work) => _WorkItem(
                work: work,
                application: _appForWork(work),
                to: widget.to,
                showTimeLabel: dups.contains(work.workType),
              ))
          .toList(),
    );
  }

  // ── 공통 소위젯 ───────────────────────────────────────

  Widget _typeBadge(BuildContext context) {
    final long = widget.to.isLongTerm;
    return _pill(
      context,
      long ? '장기' : '단기',
      long ? AppColors.longTermBg : AppColors.shortTermBg,
      long ? AppColors.longTermDark : AppColors.shortTermDark,
      border: long ? AppColors.longTermLight : AppColors.shortTermLight,
    );
  }

  Widget _pill(
    BuildContext context,
    String label,
    Color bg,
    Color text, {
    Color? border,
  }) =>
      Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 7),
          vertical: ResponsiveHelper.spacing(context, 3),
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
          border: border != null ? Border.all(color: border) : null,
        ),
        child: Text(
          label,
          style: ResponsiveHelper.tinyStyle(context,
              color: text, fontWeight: FontWeight.bold),
        ),
      );

  Widget _divider(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 7)),
        child: Container(width: 1, height: 11, color: AppColors.grey200),
      );

  Widget _actionBtn(
    BuildContext context, {
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    bool primary = true,
    bool expand = false,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 14),
          vertical: ResponsiveHelper.spacing(context, 8),
        ),
        decoration: BoxDecoration(
          color: primary ? theme.primaryColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: primary ? null : Border.all(color: AppColors.grey300),
        ),
        child: Row(
          // [DU450] 전체 폭(expand)일 때만 가운데 정렬 — 기본(false)은 예전과 같다.
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: expand ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            Icon(icon,
                size: ResponsiveHelper.iconSize(context, 13),
                color: primary ? Colors.white : AppColors.grey700),
            SizedBox(width: ResponsiveHelper.spacing(context, 5)),
            Text(
              label,
              style: ResponsiveHelper.smallStyle(context,
                  color: primary ? Colors.white : AppColors.grey700,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loadingBtn(BuildContext context, ThemeData theme) => Container(
        height: ResponsiveHelper.spacing(context, 34),
        width: ResponsiveHelper.spacing(context, 84),
        decoration: BoxDecoration(
          color: theme.primaryColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Center(
          child: SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
        ),
      );

  // ── Navigation ────────────────────────────────────────

  Future<void> _goToDetail() async {
    // flex TO는 슬롯 데이터 기반이지만 상세 화면은 마스터 workDetails 사용
    var details = _workDetails;
    if (details.isEmpty && !widget.to.isFlexType) {
      setState(() => _isApplyLoading = true);
      await _fetch();
      if (!mounted) return;
      setState(() => _isApplyLoading = false);
      details = _workDetails;
      if (details.isEmpty) return;
    } else if (details.isEmpty && widget.to.isFlexType) {
      // flex TO: 마스터 TO workDetails (슬롯 없어도 이동 가능)
      details = widget.to.workDetails;
    }
    if (!mounted) return;
    final result = await NavigationHelper.push<bool>(
      context,
      destination: JobPostingScreen(
          to: widget.to, workDetails: details, slotDate: widget.selectedDate),
    );
    if (result == true && mounted) widget.onApplySuccess();
  }

  /// 하단 "지원하기" 버튼 — flex TO면 전체 슬롯 다이얼로그, contract TO면 단일 다이얼로그
  Future<void> _openApplyDialog() async {
    if (_isApplyLoading) return; // 연타 방지
    if (widget.to.isFlexType) {
      await _openApplyDialogAllSlots();
      return;
    }
    // contract / single-date TO
    final List<WorkDetailModel> workDetails;
    if (_workDetails.isEmpty) {
      setState(() => _isApplyLoading = true);
      try {
        workDetails = await _fetch();
      } catch (e) {
        if (mounted) {
          setState(() => _isApplyLoading = false);
          ToastHelper.showError('근무 정보를 불러오는데 실패했습니다.');
        }
        return;
      } finally {
        // mounted 체크 없이 조기 리턴하면 _isApplyLoading이 true로 고착됨 — finally로 항상 리셋
        if (mounted) setState(() => _isApplyLoading = false);
      }
      if (!mounted) return;
      if (workDetails.isEmpty) return;
    } else {
      workDetails = _workDetails;
    }
    if (!mounted) return;

    final result = await ApplyWorkDialog.show(
      context: context,
      to: widget.to,
      workDetails: workDetails,
      businessName: widget.to.businessName,
      myApplications: widget.myApplications,
    );
    // result == null: 스와이프 닫기 → 변경 여부 불명이므로 안전하게 갱신
    // result.hasChanges == false: 닫기 버튼으로 닫고 변경 없음 → 갱신 생략
    if (result?.hasChanges != false && mounted) {
      widget.onApplySuccess();
    }
  }

  /// flex TO: 모든 오픈 슬롯을 GroupTO 형식으로 다이얼로그 오픈
  Future<void> _openApplyDialogAllSlots() async {
    // 슬롯 미로드 시 먼저 fetch — 반환값을 직접 사용(widget rebuild 대기 불필요)
    final List<SlotModel> slots;
    if (widget.slots == null) {
      setState(() => _isApplyLoading = true);
      try {
        slots = await _fetchSlots();
      } catch (e) {
        if (mounted) {
          setState(() => _isApplyLoading = false);
          ToastHelper.showError('슬롯 정보를 불러오는데 실패했습니다.');
        }
        return;
      } finally {
        if (mounted) setState(() => _isApplyLoading = false);
      }
      if (!mounted) return;
    } else {
      slots = widget.slots!;
    }
    if (slots.isEmpty) return;

    final now = DateTime.now();
    final groupTOsByDate = <DateTime, TOModel>{};
    final groupWorkDetailsByDate = <DateTime, List<WorkDetailData>>{};
    final groupSlotIdsByDate = <DateTime, String>{};

    for (final slot in slots) {
      if (slot.isEffectivelyClosed) continue;
      if (slot.visibleFrom != null && slot.visibleFrom!.isAfter(now)) continue;
      // 모든 업무의 지원 마감이 경과한 슬롯 제외
      if (slot.workDetails.isNotEmpty &&
          slot.workDetails.every((wd) => wd.isTimeExpired)) { continue; }
      final dateKey = FormatHelper.toKstDate(slot.date);
      groupTOsByDate[dateKey] = widget.to.copyWith(rangeStart: slot.date);
      // [8.1E.4] runtimeFull: workDetail 단위 정원 충족 여부 주입
      // (wdId 우선 → legacy fallback, 동일 workType 다른 시간대는 독립 판정)
      groupWorkDetailsByDate[dateKey] = slot.workDetails.map((wd) =>
          slot.isWorkDetailFull(wd)
              ? wd.copyWith(runtimeFull: true)
              : wd).toList();
      groupSlotIdsByDate[dateKey] = slot.id;
    }

    if (!mounted) return;
    if (groupTOsByDate.isEmpty) {
      ToastHelper.showInfo('지원 가능한 날짜가 모두 마감되었습니다.');
      return;
    }

    final result = await ApplyWorkDialog.show(
      context: context,
      to: widget.to,
      workDetails: widget.to.workDetails,
      groupTOsByDate: groupTOsByDate,
      groupWorkDetailsByDate: groupWorkDetailsByDate,
      groupSlotIdsByDate: groupSlotIdsByDate,
      businessName: widget.to.businessName,
      myApplications: widget.myApplications,
    );
    if (result?.hasChanges != false && mounted) {
      widget.onApplySuccess();
    }
  }

  /// 슬롯 행 탭 → 해당 날짜 공고 상세 화면
  Future<void> _goToDetailForSlot(SlotModel slot) async {
    final slotTO = widget.to.copyWith(rangeStart: slot.date);
    final required = slot.workDetails.fold(0, (sum, wd) => sum + wd.requiredCount);
    final result = await NavigationHelper.push<bool>(
      context,
      destination: JobPostingScreen(
        to: slotTO,
        workDetails: slot.workDetails,
        slotDate: slot.date,
        slotTotalRequired: required,
        slotConfirmedCount: slot.confirmedCount,
        slotPendingCount: slot.pendingCount,
      ),
    );
    // 공고 상세에서 지원한 경우 부모 화면 지원 목록 갱신
    if (result == true && mounted) widget.onApplySuccess();
  }

  /// 슬롯 행의 "지원하기" → 해당 날짜 단일 슬롯 다이얼로그
  Future<void> _openApplyDialogForSlot(SlotModel slot) async {
    if (_isApplyLoading || !mounted) return;
    final slotTO = widget.to.copyWith(rangeStart: slot.date);
    // [8.1E.4] 동일 workType 다른 시간대도 독립 판정
    final annotatedDetails = slot.workDetails.map((wd) =>
        slot.isWorkDetailFull(wd)
            ? wd.copyWith(runtimeFull: true)
            : wd).toList();
    final result = await ApplyWorkDialog.show(
      context: context,
      to: slotTO,
      workDetails: annotatedDetails,
      slotId: slot.id,
      businessName: widget.to.businessName,
      myApplications: widget.myApplications,
    );
    // result == null: 스와이프 닫기 → 변경 여부 불명이므로 안전하게 갱신 (1127 조건과 통일)
    if (result?.hasChanges != false && mounted) {
      widget.onApplySuccess();
    }
  }
}

// ══════════════════════════════════════════════════════════
// 업무 아이템 위젯 (contract TO 펼친 상태 전용)
// ══════════════════════════════════════════════════════════

class _WorkItem extends StatelessWidget {
  const _WorkItem({
    required this.work,
    required this.application,
    required this.to,
    required this.showTimeLabel,
  });

  final WorkDetailModel work;
  final ApplicationModel? application;
  final TOModel to;
  final bool showTimeLabel;

  @override
  Widget build(BuildContext context) {
    final hasApplied = application != null && application!.id.isNotEmpty;
    final isConfirmed = AppStatus.confirmedStatuses.contains(application?.status);

    // [DU443] 마감 행을 Opacity(0.5)로 통째로 흐리게 하던 것을 뺐다 — 글자 · 칩 대비가 반으로 떨어졌다(DU429 와 같은 이유).
    //   마감은 '마감' 칩(지원 대화 업무 카드와 같은 중립 짝)으로 말한다.
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 11)),
      // [DU443e · 후속116b N116-1] 행 전체를 상태색(확정 초록 · 대기 파랑)으로 칠하던 것을 중립 면 · 약한 선으로 —
      //   상태는 오른쪽 칩(엷은 면 + 진한 글자)이 말한다. 행 면 = 칩 면이 되어 칩이 사라지던 것도 풀린다(시안: 흰 행 + 작은 상태 칩).
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          WorkTypeIcon.buildWithBackground(
            iconString: work.workTypeIcon,
            iconColor: work.workTypeColor,
            backgroundColor: work.workTypeBackgroundColor,
            containerSize: ResponsiveHelper.spacing(context, 36),
            size: ResponsiveHelper.iconSize(context, 18),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(work.workType,
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                _infoRow(context),
              ],
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          _statusBadge(context, hasApplied, isConfirmed),
        ],
      ),
    );
  }

  Widget _infoRow(BuildContext context) {
    return Wrap(
      spacing: ResponsiveHelper.spacing(context, 8),
      runSpacing: ResponsiveHelper.spacing(context, 4),
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showTimeLabel)
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 5),
              vertical: ResponsiveHelper.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: AppColors.infoBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text('${work.startTime}~${work.endTime}',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.info, fontWeight: FontWeight.bold)),
          )
        else
          // [DU444] B(320 · 2.0)에서 '10:00~14:00' 한 덩어리가 행 글 칸보다 넓어 행마다 넘쳤다.
          //   글을 Flexible 로 두고 줄을 바꿔야 하면 '~' 뒤에서만 바꾼다(공용 TextLayout.range — 카드 머리 '09:00 ~ 17:00' 과 같은 띄어쓰기).
          //   아이콘은 첫 줄에 맞춘다(공용 FirstLineIcon · 크기 그대로). 화면 읽기는 원문 시각 범위.
          //   글자 grey600(옅은 파랑 · 초록 행 위 4.03 · 4.18) → textSecondary(5.18 · 5.37).
          Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FirstLineIcon(Icons.access_time,
                  size: ResponsiveHelper.iconSize(context, 12),
                  color: AppColors.grey500,
                  textStyle: ResponsiveHelper.tinyStyle(context)),
              SizedBox(width: ResponsiveHelper.spacing(context, 3)),
              Flexible(
                child: Text(TextLayout.range(work.startTime, work.endTime),
                    semanticsLabel: '${work.startTime}~${work.endTime}',
                    style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary)),
              ),
            ],
          ),
        Text(
          FormatHelper.formatWage(work.wage),
          style: ResponsiveHelper.smallStyle(context).copyWith(
            color: AppColors.successDark,
            fontWeight: FontWeight.bold,
          ),
        ),
        TaxDeductionBadge.chip(taxDeductionType: work.taxDeductionType),
      ],
    );
  }

  // _WorkItem은 _buildWorkList 전용 — contract TO (!isFlexType) 에서만 호출됨.
  // contract TO는 isLongTerm=true이므로 아래 !isLongTerm 분기는 단기 단일날짜 레거시 TO 대응용.
  Widget _statusBadge(BuildContext context, bool hasApplied, bool isConfirmed) {
    // [DU443] 채움 + 흰 글자(확정 2.78 · 대기중 3.12 · 긴급 3.68 · 마감 1.88)를 지원 대화 업무 카드(WorkSelectionCard · DU274 WC3)와
    //   같은 짝으로 바꿨다: 확정 successBg/successDark · 대기중 · 모집중 infoBg/infoDeep · 마감 grey100/textSecondary · 긴급 errorBg/errorDark.
    //   상태 판정 · 문구는 그대로다.
    if (hasApplied) {
      return _chip(context,
          isConfirmed ? '확정' : '대기중',
          isConfirmed ? AppColors.successBg : AppColors.infoBg,
          isConfirmed ? AppColors.successDark : AppColors.infoDeep);
    }
    if (to.isLongTerm) {
      // contract TO: TO 레벨 마감(수동/게시만료) → 업무별 마감 순으로 판단
      if (to.isManualClosed || to.isDeadlinePassed) {
        return _chip(context, '마감', AppColors.grey100, AppColors.textSecondary);
      }
      if (work.isFull) return _chip(context, '마감', AppColors.grey100, AppColors.textSecondary);
      if (work.isEmergencyOpen) return _chip(context, '긴급', AppColors.errorBg, AppColors.errorDark);
      // [R7-P1-2] 모집중 = 진행. green 은 확정·충족에만.
      return _chip(context, '모집중', AppColors.infoBg, AppColors.infoDeep);
    }
    // 단기 단일날짜 레거시 TO: 업무 레벨 상태만 체크
    if (work.isClosed || work.isTimeExpired || work.isFull) {
      return _chip(context, '마감', AppColors.grey100, AppColors.textSecondary);
    }
    if (work.isEmergencyOpen) return _chip(context, '긴급', AppColors.errorBg, AppColors.errorDark);
    // [R7-P1-2] 모집중 = 진행. green 은 확정·충족에만.
    return _chip(context, '모집중', AppColors.infoBg, AppColors.infoDeep);
  }

  Widget _chip(BuildContext context, String label, Color bg, Color text) =>
      Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 8),
          vertical: ResponsiveHelper.spacing(context, 4),
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: ResponsiveHelper.tinyStyle(context,
                color: text, fontWeight: FontWeight.bold)),
      );
}
