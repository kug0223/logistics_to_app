// lib/widgets/dialogs/apply/longterm_apply_sheet.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../models/core/to_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/firestore_service.dart';
import '../../../models/core/business_model.dart' show AttendanceRules;
import '../../../utils/attendance_policy_disclosure.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../theme/app_colors.dart';
import '../../work_type_icon.dart';
import 'apply_work_dialog.dart' show ApplyDialogResult;
import 'commitment_conflict.dart';
import 'document_access_consent.dart';

/// 장기공고 전용 지원 바텀시트
///
/// 희망 시작일 선택 → 계약 예정 기간 확인 → 단일 지원 액션.
/// 계약 종료일 계산은 [TOModel.computeContractEndDate] 재사용.
class LongTermApplySheet extends StatefulWidget {
  final TOModel to;
  final List<WorkDetailModel> selectedWorks;
  final String businessName;
  final List<ApplicationModel> myApplications;

  /// [R7-PAYROLL-POLICY.4C] 공고 상세가 보여준 근태·급여 기준(새 읽기 없음).
  final AttendanceRules? policyRules;

  const LongTermApplySheet({
    super.key,
    required this.to,
    required this.selectedWorks,
    required this.businessName,
    required this.myApplications,
    this.policyRules,
    this.commitmentsSource,
  });

  /// [R7-APPLICATION-LIFECYCLE.1C.2] 약속 목록의 출처 — 테스트가 끼울 수 있는
  ///   자리 하나. production 은 null → 기존 서비스 메서드를 그대로 쓴다.
  final Future<List<ApplicationModel>> Function()? commitmentsSource;

  static Future<ApplyDialogResult?> show({
    required BuildContext context,
    required TOModel to,
    required List<WorkDetailModel> selectedWorks,
    required String businessName,
    List<ApplicationModel>? myApplications,
    /// [R7-PAYROLL-POLICY.4C] 공고 상세가 보여준 근태·급여 기준. 새 읽기 없음.
    AttendanceRules? policyRules,
  }) {
    return DialogHelper.showSheet<ApplyDialogResult>(
      context,
      isScrollControlled: true,
      builder: (context) => LongTermApplySheet(
        to: to,
        selectedWorks: selectedWorks,
        businessName: businessName,
        myApplications: myApplications ?? [],
        policyRules: policyRules,
      ),
    );
  }

  @override
  State<LongTermApplySheet> createState() => _LongTermApplySheetState();
}

class _LongTermApplySheetState extends State<LongTermApplySheet> {

  late final FirestoreService _firestoreService;
  String? _currentUserId;

  DateTime? _desiredStartDate;
  DateTime? _focusedDay;
  bool _isSubmitting = false;
  bool _isLoadingConflicts = true;

  /// [R7-APPLICATION-LIFECYCLE.1C.2] 내 **약속**(CONFIRMED·CONTRACT_PENDING).
  ///
  ///   예전에는 preset 만 "충돌하는 날짜 집합"을 미리 만들어 두고 custom 은
  ///   아예 보지 않았다. 이제 두 경로가 같은 입력(약속 목록)과 같은 판정
  ///   (`CommitmentConflictResolver`)을 쓴다 — 읽기는 한 번이고, 선택값이
  ///   바뀔 때마다 **메모리에서** 다시 판정한다(추가 쿼리 0).
  List<ApplicationModel> _commitments = const [];

  /// 약속 목록을 읽었는가. 못 읽었으면 판정은 `unknown` 이다 —
  ///   읽기 실패를 "겹치는 약속이 없다" 로도 "전부 지원 불가" 로도 바꾸지 않는다.
  bool _commitmentsKnown = false;

  // ─── 계산 프로퍼티 ─────────────────────────────────────

  /// custom 장기공고 여부 (고정 기간, 달력 없음)
  bool get _isCustom => widget.to.contractPeriodType == 'custom';

  /// 신규 정책 적용 여부 (workStartAvailableFrom/Until 존재)
  bool get _isNewPolicy => widget.to.hasWorkStartAvailableRange;

  DateTime get _calendarFirstDay {
    if (_isNewPolicy) {
      // 신규: 근무 시작 가능기간 첫날이 속한 달의 1일
      final from = widget.to.workStartAvailableFrom!;
      return DateTime(from.year, from.month, 1);
    }
    // legacy: 기존 TO.date(=rangeStart) 기준
    final d = widget.to.date;
    return DateTime(d.year, d.month, 1);
  }

  DateTime? get _calendarLastDayNullable {
    if (_isNewPolicy) return widget.to.workStartAvailableUntil;
    // legacy: null (제한 없음 — TO가 CLOSED되면 자연 차단)
    return null;
  }

  // TableCalendar에 lastDay로 전달할 non-null 값 (null이면 먼 미래로 fallback)
  DateTime get _calendarLastDay =>
      _calendarLastDayNullable ?? DateTime(DateTime.now().year + 5, 12, 31);

  DateTime get _selectableStartDate {
    final today = DateTime.now();
    // 당일 지원 불가 — 최소 KST 내일부터
    final tomorrow = FormatHelper.toKstDate(today).add(const Duration(days: 1));
    if (_isNewPolicy) {
      final from = FormatHelper.toKstDate(widget.to.workStartAvailableFrom!);
      return tomorrow.isAfter(from) ? tomorrow : from;
    }
    // legacy: rangeStart(=TO.date) 기준
    final toStart = FormatHelper.toKstDate(widget.to.date);
    return tomorrow.isAfter(toStart) ? tomorrow : toStart;
  }

  /// 선택한 시작일 기준 계약 종료일 — TOModel.computeContractEndDate 재사용
  DateTime get _effectiveEndDate {
    if (widget.to.hasPresetPeriod && _desiredStartDate != null) {
      return widget.to.computeContractEndDate(_desiredStartDate!);
    }
    // custom: 고정 종료일
    return widget.to.rangeEnd ?? widget.to.date;
  }

  /// 이미 지원한 공고인지 확인 (PENDING / CONFIRMED)
  bool get _hasActiveApplication {
    return widget.myApplications.any((app) =>
        app.toId == widget.to.id &&
        (app.status == AppStatus.pending ||
            AppStatus.confirmedStatuses.contains(app.status)));
  }

  bool _isSelectable(DateTime day) {
    final dayOnly = DateTime.utc(day.year, day.month, day.day);
    if (dayOnly.isBefore(_selectableStartDate)) return false;
    if (dayOnly.isAfter(_calendarLastDay)) return false;

    final workDays = widget.to.workDays;
    if (workDays.isNotEmpty &&
        !workDays.contains(FormatHelper.weekday(day))) {
      return false;
    }
    // [R7-APPLICATION-LIFECYCLE.1C.2] 그 날을 **시작일로 하는 계약**이
    //   내 약속과 겹치는지 본다.
    //
    //   예전에는 "기간 안에 충돌하는 날이 하나라도 있으면 그 날 이전의 모든
    //   시작일을 막는다"(`!conflictDate.isBefore(dayOnly)`)였다. 11/20 에
    //   충돌이 하나 있으면 10/05 시작(10/19 종료) 계약까지 선택할 수 없었다 —
    //   서버는 허용하는 기간을 화면이 막은 것이다.
    return !_conflictFor(dayOnly).blocksNewApplication;
  }

  /// [startDate] 를 시작일로 하는 이 공고의 계약이 내 약속과 겹치는가.
  ///
  /// custom 은 기간이 고정이므로 선택값과 무관하게 같은 답을 준다.
  /// 판정은 공용 owner 하나다 — 화면 전용 충돌 함수를 만들지 않는다.
  CommitmentConflictDecision _conflictFor(DateTime? startDate) {
    final start = _isCustom ? widget.to.rangeStart : startDate;
    if (start == null) return CommitmentConflictDecision.unknown;
    return _conflictForPayload(
      workDate: start,
      desiredStartDate: _isCustom ? null : start,
      workEndDate: _isCustom
          ? widget.to.rangeEnd
          : widget.to.computeContractEndDate(start),
    );
  }

  /// **서버에 보낼 값 그대로** 판정한다 — 화면과 payload 가 같은 기간을 본다.
  ///
  /// 시작일은 `desiredStartDate ?? workDate` 다(서버 canonical 과 같은 식).
  /// 업무를 여러 개 고를 수 있으므로 **하나라도** 겹치면 지원할 수 없다 —
  /// 제출은 선택한 업무 전부를 한 번에 보낸다.
  CommitmentConflictDecision _conflictForPayload({
    required DateTime workDate,
    required DateTime? desiredStartDate,
    required DateTime? workEndDate,
  }) {
    final works = widget.selectedWorks;
    if (works.isEmpty) return CommitmentConflictDecision.unknown;
    CommitmentConflictDecision worst = CommitmentConflictDecision.none;
    for (final w in works) {
      final d = CommitmentConflictResolver.forLongTerm(
        commitments: _commitments,
        commitmentsKnown: _commitmentsKnown,
        startDate: desiredStartDate ?? workDate,
        endDate: workEndDate,
        workDays: widget.to.workDays,
        startTime: w.startTime,
        endTime: w.endTime,
      );
      if (d.blocksNewApplication) return d;
      if (d.isUnknown) worst = d;
    }
    return worst;
  }

  // ─── 생명주기 ─────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _firestoreService = FirestoreService();
    _focusedDay = _selectableStartDate;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _currentUserId = context.read<UserProvider>().currentUser?.uid;
      _loadConflicts();
    });
  }

  /// 내 약속을 **한 번** 읽는다.
  ///
  /// [R7-APPLICATION-LIFECYCLE.1C.2] 예전에는 여기서
  ///   · custom 이면 그냥 돌아갔다 — 그래서 custom 장기 지원은 화면이 아무
  ///     판정도 하지 않고 서버 거부로만 알게 됐다
  ///   · preset 이면 공고 기간(최대 +5년) 을 **하루씩 돌며** 충돌 날짜를
  ///     모았다 — 날짜 수 × 약속 수 만큼 계산하고, 그 결과를 "그 날 이전
  ///     전부 차단" 으로 썼다
  ///
  /// 이제 목록만 읽고, 판정은 선택값이 정해질 때 공용 resolver 가 한다.
  Future<void> _loadConflicts() async {
    if (!mounted) return;
    try {
      final all = await (widget.commitmentsSource ??
          _firestoreService.getMyConfirmedApplicationsForConflictCheck)();
      if (!mounted) return;
      setState(() {
        _commitments = CommitmentConflictResolver.commitmentsOf(all);
        _commitmentsKnown = true;
        _isLoadingConflicts = false;
      });
    } catch (e) {
      debugPrint('⚠️ 장기 지원 — 약속 목록 로드 실패: $e');
      if (!mounted) return;
      // 못 읽은 것을 "겹치는 약속이 없다" 로 바꾸지 않는다 — 판정은 unknown 이고
      //   화면이 그 사실을 말한다. 최종 판정은 서버가 한다.
      setState(() {
        _commitmentsKnown = false;
        _isLoadingConflicts = false;
      });
    }
  }

  // ─── 지원 액션 ────────────────────────────────────────

  Future<void> _apply() async {
    // custom: desiredStartDate 선택 없이 즉시 지원 가능
    // preset: 반드시 desiredStartDate 선택 후 지원
    if (!_isCustom && _desiredStartDate == null) return;
    if (_isSubmitting) return;
    if (_currentUserId == null) {
      ToastHelper.showError('로그인이 필요합니다');
      return;
    }

    // custom: workDate = rangeStart, desiredStartDate = null, workEndDate = rangeEnd
    // preset: workDate = TO.date (legacy anchor), desiredStartDate = 선택일, workEndDate = computeContractEndDate
    final DateTime effectiveWorkDate;
    final DateTime? effectiveDesiredStart;
    final DateTime effectiveWorkEndDate;

    if (_isCustom) {
      if (widget.to.rangeStart == null || widget.to.rangeEnd == null) {
        ToastHelper.showError('공고 기간 정보가 없습니다. 관리자에게 문의하세요.');
        return;
      }
      effectiveWorkDate = widget.to.rangeStart!;
      effectiveDesiredStart = null;
      effectiveWorkEndDate = widget.to.rangeEnd!;
    } else {
      effectiveWorkDate = widget.to.date;
      effectiveDesiredStart = _desiredStartDate;
      effectiveWorkEndDate = _effectiveEndDate;
    }

    // [R7-APPLICATION-LIFECYCLE.1C.2] 제출 직전, **보낼 값 그대로** 다시 본다.
    //
    //   렌더에서 CTA 를 막는 것만으로는 부족하다 — 낡은 화면에서 눌리는
    //   경로가 남으면 같은 거짓이 되돌아온다. 그리고 판정에 쓰는 값이
    //   payload 와 달라지면(UI 는 10/15 로 보고 서버엔 10/01 을 보내면)
    //   화면과 서버가 다른 기간을 말한다 — 그래서 여기서는 위에서 만든
    //   `effective*` 를 그대로 넣어 판정한다.
    final submitConflict = _conflictForPayload(
      workDate: effectiveWorkDate,
      desiredStartDate: effectiveDesiredStart,
      workEndDate: effectiveWorkEndDate,
    );
    if (submitConflict.blocksNewApplication) {
      ToastHelper.showWarning(_conflictSentence(submitConflict));
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      int appliedCount = 0;
      // [R8-P3A.1] 단건·다건이 같은 결과 계약을 쓴다 — 첫 실패 사유를 남긴다.
      String? firstProblem;
      var anyUnknown = false;
      // [R7-PAYROLL-POLICY.4C] 기준 변경은 실패와 다른 상태다.
      var anyPolicyChanged = false;
      // [R7-PAYROLL-POLICY.4D] 기준 **없음**은 변경과도 다른 상태다.
      var anyPolicyUnavailable = false;
      for (final work in widget.selectedWorks) {
        final result = await _firestoreService.applyToTOWithWorkType(
          uid: _currentUserId!,
          businessId: widget.to.businessId,
          businessName: widget.to.businessName,
          toTitle: widget.to.title,
          workDate: effectiveWorkDate,
          selectedWorkType: work.workType,
          workDetailId: work.id,
          wage: work.wage,
          wageType: work.wageType,
          workTypeIcon: work.workTypeIcon,
          workTypeColor: work.workTypeColor,
          workTypeBackgroundColor: work.workTypeBackgroundColor,
          startTime: work.startTime,
          endTime: work.endTime,
          workEndDate: effectiveWorkEndDate,
          workDays: widget.to.workDays,
          type: widget.to.type,
          toId: widget.to.id,
          slotId: null,
          desiredStartDate: effectiveDesiredStart,
          // [R7-PAYROLL-POLICY.4C] 공고 상세에서 보여준 기준의 토큰.
          expectedAttendancePolicy:
              attendancePolicyFingerprint(widget.policyRules),
        );
        if (result.isNewlyApplied) appliedCount++;
        if (!result.isApplied) {
          if (result.isUnknown) anyUnknown = true;
          if (result.isPolicyChanged) anyPolicyChanged = true;
          // [R7-PAYROLL-POLICY.4D] 기준 없음은 변경과 다른 상태다.
          if (result.isPolicyUnavailable) anyPolicyUnavailable = true;
          firstProblem ??= result.message;
        }
      }

      if (!mounted) return;
      // 결과를 모르는 건은 실패라고 말하지 않는다 — 확인이 필요하다고 말한다.
      if (anyUnknown) {
        ToastHelper.showWarning('일부 지원 결과를 확인하지 못했어요. 내 지원 목록에서 확인해주세요.');
      } else if (anyPolicyUnavailable) {
        // [R7-PAYROLL-POLICY.4D] 기준이 없다 — 다시 읽어도 해결되지 않는다.
        ToastHelper.showWarning(kAttendancePolicyUnavailableNote);
      } else if (anyPolicyChanged) {
        // 자동으로 새 기준으로 다시 보내지 않는다 — 공고 화면이 최신 기준을
        //   다시 읽어 보여주고, 근로자가 확인한 뒤 다시 누른다.
        ToastHelper.showWarning(kAttendancePolicyChangedNote);
      } else if (firstProblem != null && appliedCount == 0) {
        ToastHelper.showError(firstProblem);
      }
      Navigator.pop(
        context,
        ApplyDialogResult(
            hasChanges: appliedCount > 0,
            appliedCount: appliedCount,
            policyChanged: anyPolicyChanged),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ToastHelper.showError('지원 처리 중 오류가 발생했습니다');
      }
    }
  }

  // ─── 빌드 ────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_hasActiveApplication) return _buildAlreadyApplied(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSheetHeader(context),
        Flexible(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 4),
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_isCustom) ...[
                  // ── custom: 관리자가 날짜 직접 지정 ──────────────
                  Padding(
                    padding: EdgeInsets.only(
                      top: ResponsiveHelper.spacing(context, 12),
                      bottom: ResponsiveHelper.spacing(context, 10),
                    ),
                    child: Text(
                      '근무 예정 기간',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600, fontWeight: FontWeight.w600),
                    ),
                  ),
                  _buildCustomPeriodCard(context),
                ] else ...[
                  // ── preset: 희망 시작일 선택 ─────────────────────
                  Padding(
                    padding: EdgeInsets.only(
                      top: ResponsiveHelper.spacing(context, 12),
                      bottom: ResponsiveHelper.spacing(context, 10),
                    ),
                    child: Text(
                      '희망 시작일',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey600, fontWeight: FontWeight.w600),
                    ),
                  ),
                  // 날짜 미선택: 캘린더 / 날짜 선택 후: 컴팩트 칩 + 계약 기간
                  if (_desiredStartDate == null)
                    _buildCalendar(context)
                  else ...[
                    _buildSelectedDateChip(context),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    _buildPeriodCard(context),
                  ],
                ],
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                // ── 선택 업무 ──
                _buildWorkSummary(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                // ── 안내문 ──
                _buildInfoMessage(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                // [DS-08B.5] 서류 접근 사전동의 고지.
                // 이 시트도 지원 요청을 보내므로 다른 지원 경로와 동일하게 표시한다.
                // 표시 없이 동의 버전만 기록되면 기록이 거짓이 된다.
                DocumentAccessConsent.card(widget.to.businessName),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              ],
            ),
          ),
        ),
        _buildCTA(context),
      ],
    );
  }

  // ─── custom 전용: 고정 기간 카드 ─────────────────────────

  Widget _buildCustomPeriodCard(BuildContext context) {
    final rangeStart = widget.to.rangeStart;
    final rangeEnd = widget.to.rangeEnd;
    if (rangeStart == null || rangeEnd == null) {
      return Container(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '기간 정보를 불러올 수 없습니다.',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
        ),
      );
    }

    final startStr = FormatHelper.formatDateKorean(rangeStart);
    final endStr = FormatHelper.formatDateKorean(rangeEnd);
    final periodLabel = widget.to.contractPeriodLabel;
    final workDaysLabel = widget.to.workDaysLabel;

    return Container(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 14),
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 14),
        ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lock_outline,
                size: ResponsiveHelper.iconSize(context, 14),
                color: AppColors.infoDark,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Expanded(
                child: Text(
                  '관리자가 지정한 고정 기간이에요',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.infoDark, fontWeight: FontWeight.w600),
                ),
              ),
              if (periodLabel.isNotEmpty)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 3),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.infoDark,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    periodLabel,
                    style: ResponsiveHelper.tinyStyle(context,
                        color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '$startStr → $endStr',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: AppColors.grey800,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (workDaysLabel.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              workDaysLabel,
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.grey600),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 공통 바텀시트 Shell ──────────────────────────────
  // White + drag handle + title + close

  Widget _buildSheetHeader(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Drag handle
        Container(
          margin: EdgeInsets.only(
            top: ResponsiveHelper.spacing(context, 10),
            bottom: ResponsiveHelper.spacing(context, 2),
          ),
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.grey300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        // Title row
        Padding(
          padding: EdgeInsets.fromLTRB(
            ResponsiveHelper.spacing(context, 20),
            ResponsiveHelper.spacing(context, 10),
            ResponsiveHelper.spacing(context, 12),
            ResponsiveHelper.spacing(context, 10),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '장기 계약 지원',
                      style: ResponsiveHelper.subtitleStyle(context)
                          .copyWith(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                    Text(
                      widget.businessName,
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey500),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(Icons.close,
                    color: AppColors.grey500,
                    size: ResponsiveHelper.iconSize(context, 22)),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
      ],
    );
  }

  // ─── 캘린더 (날짜 미선택 상태) ──────────────────────

  Widget _buildCalendar(BuildContext context) {
    if (_isLoadingConflicts) {
      return SizedBox(
        height: ResponsiveHelper.spacing(context, 200),
        child: const Center(
          child: CircularProgressIndicator(
            color: AppColors.infoDark,
            strokeWidth: 2,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        children: [
          TableCalendar(
            locale: 'ko_KR',
            firstDay: _calendarFirstDay,
            lastDay: _calendarLastDay,
            focusedDay: _focusedDay ?? _selectableStartDate,
            calendarFormat: CalendarFormat.month,
            daysOfWeekHeight: ResponsiveHelper.spacing(context, 28),
            rowHeight: ResponsiveHelper.spacing(context, 42),
            selectedDayPredicate: (day) =>
                _desiredStartDate != null &&
                DateUtils.isSameDay(_desiredStartDate, day),
            enabledDayPredicate: (day) => _isSelectable(day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _desiredStartDate = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              setState(() => _focusedDay = focusedDay);
            },
            headerStyle: HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
              titleTextStyle: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
              leftChevronIcon: Icon(Icons.chevron_left,
                  color: AppColors.grey600,
                  size: ResponsiveHelper.iconSize(context, 20)),
              rightChevronIcon: Icon(Icons.chevron_right,
                  color: AppColors.grey600,
                  size: ResponsiveHelper.iconSize(context, 20)),
            ),
            daysOfWeekStyle: DaysOfWeekStyle(
              weekdayStyle: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey600),
              weekendStyle: ResponsiveHelper.smallStyle(context,
                  color: AppColors.error),
            ),
            calendarBuilders: CalendarBuilders(
              defaultBuilder: (ctx, day, _) =>
                  _buildDayCell(ctx, day, selectable: true),
              outsideBuilder: (ctx, day, _) =>
                  _buildDayCell(ctx, day, isOutside: true),
              todayBuilder: (ctx, day, _) =>
                  _buildDayCell(ctx, day,
                      isToday: true, selectable: _isSelectable(day)),
              selectedBuilder: (ctx, day, _) =>
                  _buildDayCell(ctx, day, isSelected: true),
              disabledBuilder: (ctx, day, _) => _buildDayCell(ctx, day),
            ),
          ),
          // 범례
          Padding(
            padding: EdgeInsets.fromLTRB(
              0,
              0,
              0,
              ResponsiveHelper.spacing(context, 10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendDot(context, AppColors.infoDark, '선택됨'),
                SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                _buildLegendDot(context, AppColors.infoBg, '선택가능',
                    bordered: true),
                SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                _buildLegendDot(context, AppColors.grey200, '선택불가'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCell(
    BuildContext context,
    DateTime day, {
    bool selectable = false,
    bool isOutside = false,
    bool isToday = false,
    bool isSelected = false,
  }) {
    Color bgColor;
    Color textColor;
    Border? border;

    if (isSelected) {
      bgColor = AppColors.infoDark;
      textColor = Colors.white;
      border = Border.all(color: AppColors.infoDark, width: 2);
    } else if (isOutside) {
      bgColor = Colors.transparent;
      textColor = AppColors.grey300;
    } else if (selectable) {
      bgColor = AppColors.infoBg;
      textColor = AppColors.infoDark;
      // today 여부와 무관하게 동일 스타일 — border 없음
    } else {
      bgColor = Colors.transparent;
      textColor = AppColors.grey400;
      // today 여부와 무관하게 동일 스타일 — border 없음
    }

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: bgColor,
        shape: BoxShape.circle,
        border: border,
      ),
      child: Center(
        child: Text(
          '${day.day}',
          style: ResponsiveHelper.smallStyle(context, color: textColor).copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildLegendDot(BuildContext context, Color color, String label,
      {bool bordered = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: ResponsiveHelper.spacing(context, 10),
          height: ResponsiveHelper.spacing(context, 10),
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: bordered
                ? Border.all(color: AppColors.infoDark, width: 1)
                : null,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Text(
          label,
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
        ),
      ],
    );
  }

  // ─── 선택한 날짜 컴팩트 칩 (날짜 선택 후) ─────────────

  Widget _buildSelectedDateChip(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 14),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_outlined,
            size: ResponsiveHelper.iconSize(context, 18),
            color: AppColors.infoDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '희망 시작일',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.infoDark),
                ),
                Text(
                  FormatHelper.formatDateKorean(_desiredStartDate!),
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: AppColors.infoDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _desiredStartDate = null),
            style: TextButton.styleFrom(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 10),
                vertical: ResponsiveHelper.spacing(context, 6),
              ),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: Text(
              '변경',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.infoDark, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 근무 예정 기간 카드 ──────────────────────────────
  // 세로선 제거 · infoBg 배경 · 날짜 한 줄 표시

  Widget _buildPeriodCard(BuildContext context) {
    if (_desiredStartDate == null) return const SizedBox.shrink();
    final endDate = _effectiveEndDate;
    final startStr = FormatHelper.formatDateKorean(_desiredStartDate!);
    final endStr = FormatHelper.formatDateKorean(endDate);
    final periodLabel = widget.to.contractPeriodLabel;
    final workDaysLabel = widget.to.workDaysLabel;

    return Container(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 14),
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 14),
        ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 첫 줄: 라벨 + 배지
          //
          // [R7-APPLICATION-LIFECYCLE.1C.2 CORRECTION] 라벨과 배지 둘 다 flex 가
          //   없어서 320dp × 배율 2.0 에서 **68px 넘쳤다**. 이번 phase 가 추가한
          //   이유 문구와 무관하게 이미 그랬다(LCA-R6 가 그것을 분리해 봤다).
          //   프로젝트 규칙대로 둘에 flex 를 준다 — 글자를 줄이거나 가리지 않는다.
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  '근무 예정 기간',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.infoDark, fontWeight: FontWeight.w600),
                ),
              ),
              if (periodLabel.isNotEmpty) ...[
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Flexible(
                  child: Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 8),
                      vertical: ResponsiveHelper.spacing(context, 3),
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.infoDark,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      periodLabel,
                      style: ResponsiveHelper.tinyStyle(context,
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          // 둘째 줄: 날짜 한 줄
          Text(
            '$startStr → $endStr',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: AppColors.grey800,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (workDaysLabel.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text(
              workDaysLabel,
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.grey600),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 업무 summary (읽기 전용) ─────────────────────────

  Widget _buildWorkSummary(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '선택한 업무',
          style: ResponsiveHelper.smallStyle(context,
              color: AppColors.grey600, fontWeight: FontWeight.w600),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        ...widget.selectedWorks.map((work) => _buildWorkCard(context, work)),
      ],
    );
  }

  Widget _buildWorkCard(BuildContext context, WorkDetailModel work) {
    final wageColor = work.wageType == 'daily'
        ? AppColors.warningDark
        : work.wageType == 'hourly'
            ? AppColors.successDark
            : AppColors.grey600;

    return Container(
      margin:
          EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.grey200),
      ),
      // [R7-APPLICATION-LIFECYCLE.1C.2 CORRECTION] 임금 Text 에 flex 가 없어서
      //   320dp × 배율 2.0 에서 **68px 넘쳤다**(프로브로 생성자 체인 확인:
      //   Row ← Padding ← DecoratedBox ← … ← Column). 이번 phase 가 추가한
      //   이유 문구와 무관하게 이미 그랬다 — LCA-R6 이 그 사실을 분리해 본다.
      //   E6(6E) 에서 같은 계열을 고친 방식 그대로: 글자를 줄이거나 가리지 않고
      //   남은 폭을 나눈다.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          WorkTypeIcon.buildWithBackground(
            iconString: work.workTypeIcon,
            iconColor: work.workTypeColor,
            backgroundColor: work.workTypeBackgroundColor,
            size: ResponsiveHelper.spacing(context, 16),
            containerSize: ResponsiveHelper.spacing(context, 32),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  work.workType,
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  work.timeRange,
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey600),
                ),
              ],
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Flexible(
            child: Text(
              '${work.wageType == 'hourly' ? '시급' : work.wageType == 'daily' ? '일급' : '월급'} ${FormatHelper.formatNumber(work.wage)}원',
              style: ResponsiveHelper.bodyStyle(context, color: wageColor)
                  .copyWith(fontWeight: FontWeight.bold),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 안내 메시지 ──────────────────────────────────────

  Widget _buildInfoMessage(BuildContext context) {
    final message = _isCustom
        ? '관리자가 지정한 기간으로 계약이 진행돼요.\n'
            '근무 시작 후 계약 종료는 퇴사 요청을 이용해주세요.'
        : '선택한 시작일을 기준으로 계약 기간이 자동 계산돼요.\n'
            '근무 시작 후 계약 종료는 퇴사 요청을 이용해주세요.';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline,
            size: ResponsiveHelper.iconSize(context, 14),
            color: AppColors.grey400),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Expanded(
          child: Text(
            message,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
          ),
        ),
      ],
    );
  }

  // ─── CTA 영역 ─────────────────────────────────────────

  Widget _buildCTA(BuildContext context) {
    // custom: 날짜 선택 없이 즉시 지원 가능
    // preset: 희망 시작일 선택 후 지원 가능
    final bool canApply;
    final String ctaLabel;
    // [R7-APPLICATION-LIFECYCLE.1C.2] 선택이 끝난 조건으로 겹침을 판정한다.
    //   custom 은 기간이 고정이므로 열자마자 판정이 나온다.
    final conflict = _conflictFor(_desiredStartDate);
    if (_isCustom) {
      canApply = !_isSubmitting && !_isLoadingConflicts &&
          !conflict.blocksNewApplication;
      ctaLabel = conflict.blocksNewApplication
          ? '확정 일정과 겹쳐 지원할 수 없어요'
          : '이 조건으로 지원하기';
    } else {
      canApply = _desiredStartDate != null &&
          !_isSubmitting &&
          !_isLoadingConflicts &&
          !conflict.blocksNewApplication;
      ctaLabel = _desiredStartDate == null
          ? '희망 시작일을 선택해주세요'
          : (conflict.blocksNewApplication
              ? '확정 일정과 겹쳐 지원할 수 없어요'
              : '이 조건으로 지원하기');
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          ResponsiveHelper.spacing(context, 16),
          ResponsiveHelper.spacing(context, 8),
          ResponsiveHelper.spacing(context, 16),
          ResponsiveHelper.spacing(context, 16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 왜 지원할 수 없는지(또는 확인하지 못했는지) 글자로 말한다.
            if (conflict.blocksNewApplication || conflict.isUnknown) ...[
              _buildConflictReason(context, conflict),
              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            ],
            SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: canApply ? _apply : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.infoDark,
              disabledBackgroundColor: AppColors.grey200,
              padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 16)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    ctaLabel,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: canApply ? Colors.white : AppColors.grey400,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// [R7-APPLICATION-LIFECYCLE.1C.2] 지원할 수 없는(또는 확인하지 못한) 이유.
  ///
  ///   색만으로 말하지 않는다. `마감`(정원)과 다른 상태이고, "이미 지원한
  ///   일정" 도 아니다 — 관심이 아니라 **약속**이 이유다. 문구는 1C 계열을
  ///   그대로 쓴다.
  Widget _buildConflictReason(
      BuildContext context, CommitmentConflictDecision conflict) {
    final unknown = conflict.isUnknown;
    final color = unknown ? AppColors.grey600 : AppColors.errorDark;
    final text = unknown
        ? '내 일정을 확인할 수 없어요. 지원 결과는 다시 확인해주세요.'
        : _conflictSentence(conflict);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.35)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 2)),
            child: Icon(
                unknown ? Icons.help_outline : Icons.event_busy_outlined,
                size: ResponsiveHelper.iconSize(context, 16),
                color: color),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Expanded(
            child: Text(
              text,
              style: ResponsiveHelper.captionStyle(context).copyWith(
                  color: color, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// 겹침 이유 한 줄 — 날짜·시간·사업장은 **근로자 자신의** 일정이다.
  String _conflictSentence(CommitmentConflictDecision conflict) {
    final when = conflict.conflictDate;
    final time = conflict.conflictTime;
    final biz = conflict.conflictBusinessName;
    final where = [
      if (when != null) FormatHelper.formatDateCompact(when),
      if (biz != null) biz,
      if (time != null) time,
    ].join(' ');
    if (where.isEmpty) return '확정된 일정과 시간이 겹쳐 지원할 수 없어요.';
    return '확정된 일정($where)과 시간이 겹쳐 지원할 수 없어요.';
  }

  // ─── 이미 지원됨 상태 ─────────────────────────────────

  Widget _buildAlreadyApplied(BuildContext context) {
    final existing = widget.myApplications
        .where((app) =>
            app.toId == widget.to.id &&
            (app.status == AppStatus.pending ||
                AppStatus.confirmedStatuses.contains(app.status)))
        .toList();
    final isConfirmed = existing.isNotEmpty &&
        AppStatus.confirmedStatuses.contains(existing.first.status);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSheetHeader(context),
        Padding(
          padding: EdgeInsets.fromLTRB(
            ResponsiveHelper.spacing(context, 24),
            ResponsiveHelper.spacing(context, 28),
            ResponsiveHelper.spacing(context, 24),
            ResponsiveHelper.spacing(context, 12),
          ),
          child: Column(
            children: [
              Icon(
                isConfirmed
                    ? Icons.check_circle
                    : Icons.assignment_turned_in_outlined,
                size: ResponsiveHelper.iconSize(context, 52),
                color: isConfirmed ? AppColors.success : AppColors.warning,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              Text(
                isConfirmed ? '이미 확정된 공고입니다' : '이미 지원한 공고입니다',
                style: ResponsiveHelper.subtitleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 6)),
              Text(
                isConfirmed
                    ? '내 스케줄에서 확정 근무를 확인하세요'
                    : '지원을 취소하거나 상태를 확인하려면 내 스케줄을 이용하세요',
                style: ResponsiveHelper.bodyStyle(context,
                    color: AppColors.grey500),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 28)),
              SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 14)),
                      side: BorderSide(color: AppColors.grey300),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      '확인',
                      style: ResponsiveHelper.bodyStyle(context,
                          color: AppColors.grey600,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
