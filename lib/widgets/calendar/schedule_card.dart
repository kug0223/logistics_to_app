import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../providers/user_provider.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../utils/dialog_helper.dart';
import '../../services/firestore_service.dart';
import '../../utils/toast_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../dialogs/schedule_detail_dialog.dart';
import '../dialogs/wage/wage_detail_dialog.dart';
import '../../theme/app_colors.dart';
import '../../models/core/insurance_rate_model.dart';
import '../common/tax_deduction_badge.dart';
import '../work_type_icon.dart';

/// ✨ 개별 일정 카드 (세련된 디자인)
///
/// 탭 동작:
///   카드 전체 탭 → ScheduleDetailDialog (공고/일정 상세정보)
///   급여명세서 아이콘 탭 → WageDetailDialog (급여 확정 시만 표시)
class ScheduleCard extends StatelessWidget {
  final ApplicationModel application;
  final AttendanceModel? attendance;
  final VoidCallback? onChanged;
  final DateTime? selectedDay;

  const ScheduleCard({
    super.key,
    required this.application,
    this.attendance,
    this.onChanged,
    this.selectedDay,
  });

  /// 이 근무의 계약서가 근로자 서명을 기다리고 있으면 안내 + CTA를 낸다.
  ///
  /// 기다리는 계약이 없으면 아무것도 그리지 않는다 — 카드마다 계약 배지를
  /// 달지 않는다는 뜻이다. 완료된 계약에는 별도 표시를 하지 않는다.
  Widget _buildContractActionRow(BuildContext context) {
    final toId = application.toId ?? '';
    if (toId.isEmpty) return const SizedBox.shrink();
    final pending =
        context.select<UserProvider, EmploymentContractModel?>(
      (p) => p.pendingContractForTo(toId),
    );
    if (pending == null) return const SizedBox.shrink();

    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 8)),
      child: Material(
        // [DU581b] 근로자 서명 필요 줄 = warningBg 면 · warningDark 아이콘/글(판정139 §4 545-R6 · 이 줄은 서명 대기 계약이 있을 때만 그린다).
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            final provider = context.read<UserProvider>();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    ContractSignScreen(contract: pending, role: 'worker'),
              ),
            ).then((_) => provider.refreshPendingContracts());
          },
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 10),
              vertical: ResponsiveHelper.spacing(context, 7),
            ),
            child: Row(children: [
              Icon(Icons.draw_outlined,
                  size: ResponsiveHelper.iconSize(context, 14),
                  color: AppColors.warningDark),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Expanded(
                child: Text(
                  '계약서 서명이 필요해요',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: AppColors.warningDark,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '계약서 확인',
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  // [DU581b] 조작(계약서 확인 글 · 화살표) = brand(판정139 §4 545-R6).
                  color: AppColors.brand,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Icon(Icons.chevron_right,
                  size: ResponsiveHelper.iconSize(context, 14),
                  color: AppColors.brand),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusInfo = _getDisplayStatus();
    final theme = Theme.of(context);

    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showDetailDialog(context),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ═══════════════════════════════════════════════════
                // 첫 번째 줄: 사업장명 + 상태배지 + 급여명세서 아이콘
                // ═══════════════════════════════════════════════════
                Row(
                  children: [
                    // 사업장 아이콘
                    Icon(
                      Icons.business,
                      size: ResponsiveHelper.iconSize(context, 16),
                      color: AppColors.grey600,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    // 사업장명
                    // [DU1 후속68 · 감사68 F67-2] 1줄 말줄임을 풀었다 — 긴 사업장명(320@2.0·360@1.0)이
                    //   `QA 송파 …` 로 잘려 근무지를 식별할 수 없었다. 글자를 줄이지 않고 줄바꿈한다.
                    Expanded(
                      child: Text(
                        application.businessName,
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    // 상태 배지
                    _buildStatusBadgeCompact(context, statusInfo),
                    // 급여명세서 아이콘 버튼 (급여 확정 시만 표시)
                    _buildPayslipIconButton(context),
                  ],
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                // ═══════════════════════════════════════════════════
                // 두 번째 줄: 업무명
                // ═══════════════════════════════════════════════════
                Row(
                  children: [
                    // 업무유형 아이콘 (WorkTypeIcon 사용)
                    if (application.workTypeIcon != null)
                      WorkTypeIcon.buildWithBackground(
                        iconString: application.workTypeIcon!,
                        iconColor: application.workTypeColor,
                        backgroundColor: application.workTypeBackgroundColor,
                        size: 10,
                        containerSize: 18,
                      )
                    else
                      Container(
                        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 3)),
                        decoration: BoxDecoration(
                          color: AppColors.grey100,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Icon(
                          Icons.work,
                          size: ResponsiveHelper.iconSize(context, 12),
                          color: AppColors.grey600,
                        ),
                      ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Expanded(
                      child: Text(
                        application.selectedWorkType,
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 6)),

                // ═══════════════════════════════════════════════════
                // 세 번째 줄: 근무시간 · 급여
                // ═══════════════════════════════════════════════════
                // [DU1 후속68 · 감사68 F67-2] 시간과 급여를 한 Row 에 두면 320@2.0 에서 급여가 폭을 먼저
                //   가져가 예정시간 `09:00~13:00` 이 `0…` 로 잘렸다. Wrap 으로 바꿔 둘 다 전문을 보이고,
                //   자리가 모자라면 급여가 다음 줄로 내려간다(글자 축소 없음·원문 그대로).
                Wrap(
                  spacing: ResponsiveHelper.spacing(context, 8),
                  runSpacing: ResponsiveHelper.spacing(context, 4),
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.access_time,
                          size: ResponsiveHelper.iconSize(context, 14),
                          color: AppColors.grey500,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                        // [DU1 구현72 S073] 예정시간이 작은 회색(small·grey700)이라 굵은 급여보다 약하게 읽혔다 —
                        //   대표 패턴(구현69 홈·S041 업무 카드)처럼 시간과 급여는 같은 주 정보. 본문 크기·w600·본문색.
                        Text(
                          '${application.startTime}~${application.endTime}',
                          style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                    // 급여 (금액 + 타입)
                    // [DU1 구현72 S073] 녹색은 확정 상태 배지가 맡는다(달성 의미, R7-P1-2) — 급여는 S041 업무 카드와 같은 브랜드색.
                    Text(
                      _getWageDisplay(),
                      style: ResponsiveHelper.bodyStyle(context, color: AppColors.brand).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                // ═══════════════════════════════════════════════════
                // 계약서 서명 필요 (근로자가 할 일이 있을 때만)
                // ═══════════════════════════════════════════════════
                // [PREDEVICE-SCHEDULE-CONTRACT] 근무는 절대 숨기지 않는다.
                //   약속(확정된 근무)과 남은 행동(서명)을 같은 카드에서 함께
                //   보여준다. 근무 전에 발견할 수 있는 자리가 알림 말고도
                //   필요하기 때문이다.
                //
                //   서명 대기(pending_worker)일 때만 띄운다. 계약이 아직
                //   없거나 사업주 처리 중인 상태는 근로자가 할 수 있는 일이
                //   없으므로 "서명 필요"라고 말하면 거짓이 된다 — 근로자가
                //   가진 데이터로는 그 두 경우를 구분할 수도 없으므로
                //   아무 말도 하지 않는 쪽이 정확하다.
                _buildContractActionRow(context),

                // ═══════════════════════════════════════════════════
                // 세금 공제 배지 (급여 계산 후에만 표시)
                // ═══════════════════════════════════════════════════
                if (attendance?.wageDetail?.taxDeductionType case final taxType?
                    when taxType != InsuranceRateModel.typeNone) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                  TaxDeductionBadge.row(taxDeductionType: taxType),
                ],

                // ═══════════════════════════════════════════════════
                // 장기 근무 정보 (있을 때만)
                // ═══════════════════════════════════════════════════
                if (application.isLongTermApplication) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 10),
                      vertical: ResponsiveHelper.spacing(context, 6),
                    ),
                    // [DU545] 고정근무 띠 = 근무 유형 안내 — 중립 면 · 회색 별 · 본문/보조 글(문구 · 기하 그대로)
                    decoration: BoxDecoration(
                      color: AppColors.grey100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.star,
                          size: ResponsiveHelper.iconSize(context, 12),
                          color: AppColors.grey600,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                        Text(
                          '고정근무',
                          style: ResponsiveHelper.tinyStyle(context, color: AppColors.textPrimary).copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Flexible(
                          child: Text(
                            '${application.workDaysDisplay ?? ""} · ${application.workPeriodDisplay}',
                            style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ✅ 상태 배지 (컴팩트)
  Widget _buildStatusBadgeCompact(BuildContext context, _StatusInfo info) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      // [DU545] 상태 칩 = StatusBadge 짝(옅은 면 + 진한 글) — 원색 15% 면 · 원색 글(1.92–3.07)을 대신한다.
      decoration: BoxDecoration(
        color: info.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            info.icon,
            size: ResponsiveHelper.iconSize(context, 14),
            color: info.color,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            info.text,
            style: ResponsiveHelper.tinyStyle(context, color: info.color).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ 급여명세서 아이콘 버튼
  ///
  /// 노출 조건:
  ///   attendance.isWageConfirmed == true OR attendance.isWageTransferred == true
  ///   AND attendance.wageDetail != null
  ///
  /// 조건 미충족 시 SizedBox.shrink() 반환 — disabled 아이콘 표시하지 않음.
  ///
  /// 이벤트 격리:
  ///   IconButton은 내부적으로 InkWell을 사용하므로 제스처 아레나에서
  ///   부모 InkWell(카드 탭)보다 우선하여 onPressed만 실행된다.
  Widget _buildPayslipIconButton(BuildContext context) {
    final isWageConfirmed =
        attendance?.isWageConfirmed == true || attendance?.isWageTransferred == true;
    if (!isWageConfirmed || attendance?.wageDetail == null) {
      return const SizedBox.shrink();
    }
    return IconButton(
      icon: const Icon(Icons.receipt_long_outlined),
      iconSize: 20,
      color: AppColors.brand,
      tooltip: '급여 명세서',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      onPressed: () => _showWageDetailDialog(context),
    );
  }

  /// ✅ 급여 명세서 다이얼로그 (중간 BottomSheet 없이 직접 진입)
  Future<void> _showWageDetailDialog(BuildContext context) async {
    if (attendance == null || attendance!.wageDetail == null) {
      ToastHelper.showWarning('급여 정보가 없습니다');
      return;
    }

    final firestoreService = FirestoreService();
    final user = await firestoreService.getUser(application.uid);
    final business = await firestoreService.getBusinessById(application.businessId);

    if (!context.mounted) return;

    await WageDetailDialog.show(
      context: context,
      app: application,
      user: user,
      attendance: attendance!,
      wage: attendance!.wageDetail!,
      mode: WageDialogMode.confirmed,
      businessName: business?.name,
      scheduledBreakMinutes: attendance!.wageDetail!.scheduledBreakMinutes,
    );
  }

  /// 상세 정보 다이얼로그 (카드 탭 진입점)
  void _showDetailDialog(BuildContext context) {
    DialogHelper.showSheet(
      context,
      isScrollControlled: true,
      useRootNavigator: true,  // BottomNav까지 dim — modal 계층 명확화
      builder: (context) => ScheduleDetailDialog(application: application),
    );
  }

  /// 상태 정보 가져오기
  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case AppStatus.confirmed:
        return _StatusInfo(
          color: AppColors.successDark, bg: AppColors.successBg,
          text: '확정',
          icon: Icons.check_circle,
        );
      case AppStatus.pending:
        return _StatusInfo(
          color: AppColors.warningDark, bg: AppColors.warningBg,
          text: '대기',
          icon: Icons.schedule,
        );
      case AppStatus.contractPending:
        return _StatusInfo(
          // [DU576] 일반정보 상태 계약 진행 중 = brandSurface/brand(판정139 §3 PP-STATUS-PAIR · info 짝 4.03 미달 → 약 4.99).
          color: AppColors.brand, bg: AppColors.brandSurface,
          text: '계약 진행 중',
          icon: Icons.assignment_outlined,
        );
      case AppStatus.rejected:
        return _StatusInfo(
          // [DU576] 지원 거절 결과 = 중립 grey100/textSecondary(판정139 §3 · 노쇼 error 짝은 그대로).
          color: AppColors.textSecondary, bg: AppColors.grey100,
          text: '거절',
          icon: Icons.cancel,
        );
      case AppStatus.canceled:
        return _StatusInfo(
          color: AppColors.textSecondary, bg: AppColors.grey100,
          text: '취소',
          icon: Icons.remove_circle_outline,
        );
      case AppStatus.autoCanceled:
        return _StatusInfo(
          color: AppColors.textSecondary, bg: AppColors.grey100,
          text: '자동 취소',
          icon: Icons.block,
        );
      default:
        return _StatusInfo(
          color: AppColors.textSecondary, bg: AppColors.grey100,
          text: '알 수 없음',
          icon: Icons.help_outline,
        );
    }
  }

  /// ✅ 출근 기록 기반 표시 상태 결정
  _StatusInfo _getDisplayStatus() {
    // [DEVICE-MISMATCH-FIX] 근태 결말(노쇼·결근)은 지원서 상태보다 먼저다.
    //   CONTRACT_PENDING 으로 남은 노쇼 근무가 `계약 진행 중`으로 보였다(DEV 실측).
    if (AppStatus.confirmedStatuses.contains(application.status) &&
        attendance != null) {
      if (attendance!.status == AttendanceModel.statusNoShow) {
        return _StatusInfo(
          text: '노쇼',
          color: AppColors.errorDark, bg: AppColors.errorBg,
          icon: Icons.cancel,
        );
      }
      if (attendance!.status == AttendanceModel.statusAbsent) {
        return _StatusInfo(
          text: '결근',
          // [DU576] 명시 결근 결과 = errorBg/errorDark(판정139 §3 · 출근 기록 없음 · 정산 대기 warning 짝은 그대로).
          color: AppColors.errorDark, bg: AppColors.errorBg,
          icon: Icons.event_busy,
        );
      }
    }

    // 1. CONFIRMED가 아니면 기존 로직
    if (application.status != AppStatus.confirmed) {
      return _getStatusInfo(application.status);
    }

    // 2. attendance 없으면 "확정" — 단, 출근 기록 없이 예정 시간이 끝났으면
    //    더 이상 앞으로의 약속이 아니다(DEV 실측 Zdn7).
    if (attendance == null || attendance!.checkIn == null) {
      if (application.hasShiftEndedAt(DateTime.now())) {
        return _StatusInfo(
          text: '출근 기록 없음',
          color: AppColors.warningDark, bg: AppColors.warningBg,
          icon: Icons.event_busy,
        );
      }
    }
    if (attendance == null) {
      return _StatusInfo(
        text: '확정',
        color: AppColors.successDark, bg: AppColors.successBg,
        icon: Icons.check_circle,
      );
    }

    // 4. 급여 최종 확정 (confirmed = 정산완료, transferred = 송금완료)
    if (attendance!.isWageConfirmed || attendance!.isWageTransferred) {
      return _StatusInfo(
        text: attendance!.isWageTransferred ? '송금 완료' : '정산 완료',
        // [DU576] 정산 완료 · 송금 완료 = successBg/successDark(판정139 §3 · 상태명 · 지급 판단 그대로).
        color: AppColors.successDark, bg: AppColors.successBg,
        icon: Icons.verified,
      );
    }

    // 5. 급여 계산 완료 — 관리자 마감 대기
    if (attendance!.wageStatus == 'calculated') {
      return _StatusInfo(
        text: '정산 대기',
        color: AppColors.warningDark, bg: AppColors.warningBg,
        icon: Icons.hourglass_bottom,
      );
    }

    // 6. 퇴근 완료 — 급여는 아직 확정 전이다.
    //    [DEVICE-MISMATCH-FIX] 홈·수입의 `정산 중`과 같은 이름으로 부른다.
    if (attendance!.checkOut != null) {
      return _StatusInfo(
        text: '정산 중',
        // [DU576] 정산 중 작은 칩 = 중립 grey100/textSecondary(판정139 §3 · checkedOut/purple 전역 토큰 그대로).
        color: AppColors.textSecondary, bg: AppColors.grey100,
        icon: Icons.task_alt,
      );
    }

    // 7. 출근만 완료
    if (attendance!.checkIn != null) {
      return _StatusInfo(
        text: '근무 중',
        // [DU576] 근무 중 = successBg/successDark(판정139 §3 · 확정과는 이름 · 아이콘으로 구별).
        color: AppColors.successDark, bg: AppColors.successBg,
        icon: Icons.work,
      );
    }

    // 8. 기본 - 확정
    return _StatusInfo(
      text: '확정',
      color: AppColors.successDark, bg: AppColors.successBg,
      icon: Icons.check_circle,
    );
  }

  /// ✅ 급여 표시 (wageType 포함) - 모든 상태 통일
  String _getWageDisplay() {
    // 1. 정산완료/송금완료면 확정 급여 + wageType 표시
    if ((attendance?.isWageConfirmed == true || attendance?.isWageTransferred == true) &&
        attendance?.finalWage != null) {
      final wageTypeLabel = attendance!.wageDetail?.wageTypeLabel ?? '';
      return '${FormatHelper.formatWage(attendance!.finalWage!)}${wageTypeLabel.isNotEmpty ? ' ($wageTypeLabel)' : ''}';
    }

    // 2. 기본 - application의 wageType 우선 사용
    final wageTypeLabel = application.wageTypeLabel.isNotEmpty
        ? application.wageTypeLabel
        : (attendance?.wageDetail?.wageTypeLabel ?? '');
    final formattedWage = FormatHelper.formatWage(application.wage);

    return wageTypeLabel.isNotEmpty ? '$formattedWage ($wageTypeLabel)' : formattedWage;
  }
}

/// 상태 정보 클래스
class _StatusInfo {
  final Color color;
  final Color bg; // [DU545] 칩 옅은 면(StatusBadge 짝) — color 는 진한 글 · 아이콘
  final String text;
  final IconData icon;

  _StatusInfo({
    required this.color,
    required this.bg,
    required this.text,
    required this.icon,
  });
}
