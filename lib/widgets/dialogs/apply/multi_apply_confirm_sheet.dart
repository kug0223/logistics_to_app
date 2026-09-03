// lib/widgets/dialogs/apply/multi_apply_confirm_sheet.dart
//
// JPS 전용 단기공고 Multi-Apply Confirm Sheet
//
// ─ 책임 ─────────────────────────────────────────────────────────────────────
//   Selection Owner    : JobPostingScreen (caller — 날짜·업무 선택)
//   Confirmation Owner : THIS WIDGET (conflict check + consent + submit + result)
//   Submit Owner       : ApplicationFirestore / callableApplyToTO (FirestoreService 위임)
//
// ─ 이 Sheet에 포함 ──────────────────────────────────────────────────────────
//   • 선택 item별 conflict / already-applied 분류
//   • documentAccessConsent 표시 (documentAccessConsentVersion: "2026-08-21-v1")
//   • N개 업무 일괄 지원 (applyToTOWithWorkType × N)
//   • 부분 실패 결과 표시
//
// ─ 이 Sheet에서 제외 ─────────────────────────────────────────────────────────
//   • 지원 취소 / 확정 취소 — 기존 지원 관리 UI 담당
//   • 날짜 선택 — JPS selection UI 담당 (items는 날짜가 이미 확정된 상태)
//   • 장기공고 — LongTermApplySheet 담당
//   • UserTOCard 경로 — ApplyWorkDialog → ApplyConfirmDialog 유지
//
// ─ Conflict 정책 ─────────────────────────────────────────────────────────────
//   BLOCKED  : 기존 CONFIRMED / CONTRACT_PENDING과 시간 겹침 → 지원 불가, submit 대상 제외
//   WARNING  : 이전 근무 종료 직후 (딱 붙는 경우) → 경고 표시, 지원 허용
//   AVAILABLE: 충돌 없음
//   ALREADY_APPLIED: 동일 (toId, slotId, workType)에 PENDING/CONTRACT_PENDING/CONFIRMED 존재
//                    → 표시만, submit 대상 제외. 중복지원 서버 gate도 유지됨.
//
// ─ PENDING↔PENDING 허용 ──────────────────────────────────────────────────────
//   선택한 PENDING 후보끼리 시간이 겹쳐도 BLOCK하지 않는다. (Product Policy)
//   ScheduleConflictService는 CONFIRMED/CONTRACT_PENDING만 조회한다.
//
// ─ Partial Failure ────────────────────────────────────────────────────────────
//   All success  → Toast + sheet close
//   Partial fail → sheet 내 결과 표시 (성공/실패 항목 구분)
//   All fail     → sheet 내 결과 표시

import 'dart:math' show max;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/core/to_model.dart';
import '../../../models/core/slot_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/schedule_conflict_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/common_widgets.dart';
import '../styled_dialog.dart';

// ─ 결과 타입 ──────────────────────────────────────────────────────────────────

class MultiApplyResult {
  final bool hasChanges;
  final int appliedCount;
  const MultiApplyResult({required this.hasChanges, required this.appliedCount});
}

// ─ 내부 item 분류 ─────────────────────────────────────────────────────────────

enum _ItemStatus {
  checking,       // 충돌 체크 중
  available,      // 지원 가능 (충돌 없음)
  warning,        // 경고 (시간 붙음 등) — 지원 허용
  blocked,        // CONFIRMED/CONTRACT_PENDING 시간 겹침 — 지원 불가
  alreadyApplied, // 이미 지원/확정 중 — 중복지원 서버 게이트도 유지됨
}

class _ItemMeta {
  final ({SlotModel? slot, WorkDetailModel work}) item;
  _ItemStatus status = _ItemStatus.checking;
  ConflictInfo conflictInfo = ConflictInfo.ok;
  String? applyError; // null = 아직 미제출 또는 성공, non-null = 실패 메시지
  bool submitted = false;

  _ItemMeta({required this.item});

  /// submit 대상 여부 (alreadyApplied / blocked 제외)
  bool get isSubmittable =>
      status == _ItemStatus.available || status == _ItemStatus.warning;
}

// ─ Widget ────────────────────────────────────────────────────────────────────

class MultiApplyConfirmSheet extends StatefulWidget {
  final List<({SlotModel? slot, WorkDetailModel work})> items;
  final TOModel to;
  final List<ApplicationModel> myApplications;

  const MultiApplyConfirmSheet({
    super.key,
    required this.items,
    required this.to,
    required this.myApplications,
  });

  @override
  State<MultiApplyConfirmSheet> createState() => _MultiApplyConfirmSheetState();
}

class _MultiApplyConfirmSheetState extends State<MultiApplyConfirmSheet> {
  final _conflictService = ScheduleConflictService();
  final _firestoreService = FirestoreService();

  late List<_ItemMeta> _metas;
  bool _isCheckingConflicts = true;
  bool _isSubmitting = false;
  bool _submitDone = false;

  @override
  void initState() {
    super.initState();
    _metas = widget.items.map((item) => _ItemMeta(item: item)).toList();
    _initAlreadyApplied(); // conflict check 전 선제 분류
    _loadConflicts();
  }

  // ─ 초기화 ────────────────────────────────────────────────────────────────

  /// myApplications 기반 already-applied 선분류
  void _initAlreadyApplied() {
    for (final meta in _metas) {
      if (_hasActiveApplication(meta.item)) {
        meta.status = _ItemStatus.alreadyApplied;
      }
    }
  }

  bool _hasActiveApplication(({SlotModel? slot, WorkDetailModel work}) item) {
    final slotId = item.slot?.id;
    return widget.myApplications.any((app) {
      final sameTO = app.toId == widget.to.id;
      final sameWork = app.selectedWorkType == item.work.workType;
      // slotId가 null이면 contract TO (slotId 없는 지원서와 매칭)
      final sameSlot = slotId == null
          ? (app.slotId == null || app.slotId!.isEmpty)
          : app.slotId == slotId;
      const active = [
        AppStatus.pending,
        AppStatus.contractPending,
        AppStatus.confirmed,
      ];
      return sameTO && sameWork && sameSlot && active.contains(app.status);
    });
  }

  // ─ Conflict 체크 ─────────────────────────────────────────────────────────

  Future<void> _loadConflicts() async {
    // alreadyApplied 항목은 conflict check 불필요
    final toCheck = _metas.where((m) => m.status != _ItemStatus.alreadyApplied).toList();

    if (toCheck.isEmpty) {
      if (mounted) setState(() => _isCheckingConflicts = false);
      return;
    }

    try {
      // 날짜별로 grouping → 같은 날짜는 CF 1회 호출로 처리 (비용 절감)
      // Flex TO: slot.date 사용 / Contract TO: to.date 사용
      final byDate = <DateTime, List<_ItemMeta>>{};
      for (final meta in toCheck) {
        final raw = meta.item.slot?.date ?? widget.to.date;
        final key = DateTime(raw.year, raw.month, raw.day);
        byDate.putIfAbsent(key, () => []).add(meta);
      }

      // 날짜별 conflict check 병렬 실행
      await Future.wait(byDate.entries.map((entry) async {
        final date = entry.key;
        final metas = entry.value;
        final works = metas.map((m) => m.item.work).toList();
        try {
          final conflictMap = await _conflictService.checkConflictsForWorkDetails(
            workDate: date,
            workDetails: works,
          );
          if (!mounted) return;
          setState(() {
            for (final meta in metas) {
              final info = conflictMap[meta.item.work.id] ?? ConflictInfo.ok;
              meta.conflictInfo = info;
              switch (info.level) {
                case ConflictLevel.blocked:
                  meta.status = _ItemStatus.blocked;
                case ConflictLevel.warning:
                  meta.status = _ItemStatus.warning;
                case ConflictLevel.ok:
                  meta.status = _ItemStatus.available;
              }
            }
          });
        } catch (_) {
          // 에러 시 available로 폴백 — 서버 게이트가 최종 차단
          if (mounted) {
            setState(() {
              for (final meta in metas) {
                if (meta.status == _ItemStatus.checking) {
                  meta.status = _ItemStatus.available;
                }
              }
            });
          }
        }
      }));
    } finally {
      if (mounted) setState(() => _isCheckingConflicts = false);
    }
  }

  // ─ 제출 ──────────────────────────────────────────────────────────────────

  List<_ItemMeta> get _submitTargets =>
      _metas.where((m) => m.isSubmittable).toList();

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final targets = _submitTargets;
    if (targets.isEmpty) return;

    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);

    int successCount = 0;

    for (final meta in targets) {
      final item = meta.item;
      final work = item.work;
      final slot = item.slot;
      // Flex: slot.date / Contract: to.date (AWD의 workDate: date ?? to.date 와 동일)
      final workDate = slot?.date ?? widget.to.date;

      try {
        final success = await _firestoreService.applyToTOWithWorkType(
          uid: user.uid,
          businessId: widget.to.businessId,
          businessName: widget.to.businessName,
          toTitle: widget.to.title,
          workDate: workDate,
          selectedWorkType: work.workType,
          workDetailId: work.id,
          wage: work.wage,
          wageType: work.wageType,
          workTypeIcon: work.workTypeIcon,
          workTypeColor: work.workTypeColor,
          workTypeBackgroundColor: work.workTypeBackgroundColor,
          startTime: work.startTime,
          endTime: work.endTime,
          workEndDate: widget.to.endDate,
          workDays: widget.to.workDays,
          type: widget.to.type,
          toId: widget.to.id,
          slotId: slot?.id,
        );
        if (!mounted) return;
        if (success) {
          successCount++;
          setState(() {
            meta.submitted = true;
            meta.applyError = null;
          });
        } else {
          setState(() {
            meta.submitted = true;
            meta.applyError = '지원에 실패했습니다';
          });
        }
      } catch (e) {
        if (!mounted) return;
        setState(() {
          meta.submitted = true;
          meta.applyError = _friendlyError(e);
        });
      }
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _submitDone = true;
    });

    if (successCount > 0 && successCount == targets.length) {
      // All success → toast + close
      final msg = targets.length == 1
          ? '지원이 완료되었습니다'
          : '${targets.length}개 업무에 지원했어요.';
      ToastHelper.showSuccess(msg);
      if (mounted) {
        Navigator.pop(
          context,
          MultiApplyResult(hasChanges: true, appliedCount: successCount),
        );
      }
    }
    // Partial / All fail → sheet 내 결과 표시 (_submitDone == true)
  }

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('already') || msg.contains('duplicate') || msg.contains('중복')) {
      return '이미 지원한 업무입니다';
    }
    if (msg.contains('capacity') || msg.contains('정원')) return '정원이 마감되었습니다';
    if (msg.contains('closed') || msg.contains('마감')) return '모집이 마감되었습니다';
    if (msg.contains('conflict') || msg.contains('시간 충돌') || msg.contains('schedule')) {
      return '확정된 근무와 시간이 겹칩니다';
    }
    if (msg.contains('offline') || msg.contains('network') || msg.contains('인터넷')) {
      return '인터넷 연결을 확인해주세요';
    }
    return '지원에 실패했습니다';
  }

  // ─ Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        max(20, MediaQuery.viewPaddingOf(context).bottom),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),

          // 업무 목록 — 많을 경우 이 영역만 스크롤, sheet 전체 무한 확장 방지
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.42,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _metas
                    .map((meta) => _buildItemCard(context, meta))
                    .toList(),
              ),
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // 서류 접근 사전동의 — submit 전에만 표시 (result 후 불필요)
          if (!_submitDone) ...[
            _buildConsent(context),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          ],

          _submitDone ? _buildResult(context) : _buildCTA(context),
        ],
      ),
    );
  }

  // ─ 헤더 ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    if (_submitDone) {
      final successCount = _submitTargets.where((m) => m.applyError == null).length;
      final String title;
      if (_submitTargets.isEmpty) {
        title = '지원할 업무가 없었어요';
      } else if (successCount == _submitTargets.length) {
        title = '지원 완료';
      } else if (successCount == 0) {
        title = '지원하지 못했어요';
      } else {
        title = '일부 지원이 완료됐어요';
      }
      return Text(
        title,
        style: ResponsiveHelper.subtitleStyle(context)
            .copyWith(fontWeight: FontWeight.bold),
      );
    }

    final totalCount = widget.items.length;
    final submitCount =
        _isCheckingConflicts ? totalCount : _submitTargets.length;
    final blockedCount = totalCount - submitCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          blockedCount > 0
              ? '$totalCount개 중 $submitCount개 업무에 지원할 수 있어요'
              : '$totalCount개 업무에 지원합니다',
          style: ResponsiveHelper.subtitleStyle(context)
              .copyWith(fontWeight: FontWeight.bold),
        ),
        if (blockedCount > 0 && !_isCheckingConflicts) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            '나머지 $blockedCount개는 이미 지원 중이거나 확정된 근무와 겹쳐요.',
            style: ResponsiveHelper.tinyStyle(context)
                .copyWith(color: AppColors.grey500),
          ),
        ],
      ],
    );
  }

  // ─ 업무 카드 ─────────────────────────────────────────────────────────────

  Widget _buildItemCard(BuildContext context, _ItemMeta meta) {
    final work = meta.item.work;
    final slot = meta.item.slot;
    final weekDays = ['월', '화', '수', '목', '금', '토', '일'];
    String dateStr = '';
    if (slot != null) {
      final d = slot.date;
      dateStr = '${d.month}월 ${d.day}일(${weekDays[d.weekday - 1]}) · ';
    }

    final isDisabled = meta.status == _ItemStatus.blocked ||
        meta.status == _ItemStatus.alreadyApplied;
    final isChecking =
        !_submitDone && (_isCheckingConflicts || meta.status == _ItemStatus.checking);

    // 색상 / 배지 결정
    late Color borderColor;
    late Color bgColor;
    String? badgeText;
    Color? badgeColor;
    String? subMsg;
    Color? subColor;

    if (_submitDone) {
      // ── 제출 후 상태 ──────────────────────────────────────────────────────
      if (isDisabled) {
        borderColor = AppColors.grey200;
        bgColor = AppColors.grey50;
      } else if (meta.applyError == null) {
        borderColor = AppColors.success.withValues(alpha: 0.5);
        bgColor = AppColors.success.withValues(alpha: 0.04);
        badgeText = '지원 완료';
        badgeColor = AppColors.success;
      } else {
        borderColor = AppColors.error.withValues(alpha: 0.4);
        bgColor = AppColors.error.withValues(alpha: 0.04);
        badgeText = '실패';
        badgeColor = AppColors.error;
        subMsg = meta.applyError;
        subColor = AppColors.error;
      }
    } else {
      // ── 제출 전 상태 ──────────────────────────────────────────────────────
      switch (meta.status) {
        case _ItemStatus.checking:
          borderColor = AppColors.grey200;
          bgColor = AppColors.grey50;
        case _ItemStatus.available:
          borderColor = AppColors.grey200;
          bgColor = AppColors.grey50;
        case _ItemStatus.warning:
          borderColor = AppColors.warning.withValues(alpha: 0.4);
          bgColor = AppColors.warning.withValues(alpha: 0.05);
          badgeText = '주의';
          badgeColor = AppColors.warning;
          subMsg = meta.conflictInfo.message ??
              '이전 근무 종료 직후입니다. 이동 시간을 고려하세요.';
          subColor = AppColors.warningDark;
        case _ItemStatus.blocked:
          borderColor = AppColors.error.withValues(alpha: 0.3);
          bgColor = AppColors.error.withValues(alpha: 0.04);
          badgeText = '지원 불가';
          badgeColor = AppColors.error;
          subMsg = '이미 확정된 근무와 시간이 겹쳐 지원할 수 없어요.';
          subColor = AppColors.error;
        case _ItemStatus.alreadyApplied:
          borderColor = AppColors.grey300;
          bgColor = AppColors.grey50;
          badgeText = '이미 지원중';
          badgeColor = AppColors.grey500;
      }
    }

    return Container(
      margin:
          EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$dateStr${work.workType}',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDisabled
                            ? AppColors.grey400
                            : AppColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 3)),
                    Text(
                      '${work.startTime} ~ ${work.endTime}  ·  ${work.formattedWage}',
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: isDisabled
                            ? AppColors.grey400
                            : AppColors.grey600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isChecking)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: AppColors.grey400,
                  ),
                )
              else if (_submitDone && meta.applyError == null && !isDisabled)
                const Icon(Icons.check_circle, color: AppColors.success, size: 20)
              else if (badgeText != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: badgeColor!.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    badgeText,
                    style: ResponsiveHelper.tinyStyle(context).copyWith(
                      color: badgeColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          if (subMsg != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(
              subMsg,
              style: ResponsiveHelper.tinyStyle(context)
                  .copyWith(color: subColor ?? AppColors.grey500),
            ),
          ],
        ],
      ),
    );
  }

  // ─ 서류 접근 사전동의 ─────────────────────────────────────────────────────
  //
  // [DOCUMENT-CONSENT] 서류 접근 사전동의 (V3: 신분증+급여계좌+통장사본)
  // documentAccessConsentVersion: "2026-08-21-v1"
  // [LEGAL-REVIEW-ID-CONSENT] 동의 문구 및 방식의 법적 적절성은 별도 법무 검토 필요

  Widget _buildConsent(BuildContext context) {
    return StyledDialogInfoCard.warning(
      '지원하기를 누르면 [${widget.to.businessName}]의 권한 있는 관리자가 '
      '근무 확정 후 소득신고·급여처리 목적으로 등록된 서류에 접근할 수 있음에 동의합니다.\n'
      '· 신분증: 확정일로부터 7일간\n'
      '· 급여계좌·통장사본: 급여처리 관계가 유효한 동안',
    );
  }

  // ─ CTA ───────────────────────────────────────────────────────────────────

  Widget _buildCTA(BuildContext context) {
    final targets = _submitTargets;
    final isAllDisabled = targets.isEmpty && !_isCheckingConflicts;

    return Column(
      children: [
        // 지원 안내 문구 (지원 가능 항목 있을 때만)
        if (!_isCheckingConflicts && !isAllDisabled) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 14, color: AppColors.grey600),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Flexible(
                  child: Text(
                    '지원 후 관리자의 근무 확정을 기다려주세요. '
                    '근무 확정 전까지 지원을 취소할 수 있습니다.',
                    style: ResponsiveHelper.tinyStyle(context)
                        .copyWith(color: AppColors.grey700),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        ],

        // 전체 지원 불가 안내
        if (isAllDisabled) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Text(
              '선택한 업무 모두 이미 지원 중이거나 확정된 근무와 시간이 겹쳐요.',
              style: ResponsiveHelper.smallStyle(context)
                  .copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        ],

        // 지원하기 버튼
        CommonWidgets.primaryButton(
          context: context,
          text: isAllDisabled
              ? '지원 불가'
              : _isSubmitting
                  ? '지원 중...'
                  : _isCheckingConflicts
                      ? '확인 중...'
                      : targets.length > 1
                          ? '${targets.length}개 업무 지원하기'
                          : '지원하기',
          onPressed: (isAllDisabled || _isSubmitting || _isCheckingConflicts)
              ? null
              : _submit,
          icon: Icons.send,
        ),

        // 취소
        Center(
          child: TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.pop(context),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.grey400,
              padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 8)),
            ),
            child: Text(
              '취소',
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(color: AppColors.grey400),
            ),
          ),
        ),
      ],
    );
  }

  // ─ 결과 표시 ─────────────────────────────────────────────────────────────

  Widget _buildResult(BuildContext context) {
    final targets = _submitTargets;
    final successCount = targets.where((m) => m.applyError == null).length;
    final failCount = targets.length - successCount;

    return Column(
      children: [
        if (failCount > 0) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.error.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  successCount == 0
                      ? '지원에 실패했어요'
                      : '${targets.length}개 중 $failCount개 업무 지원에 실패했어요',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...targets
                    .where((m) => m.applyError != null)
                    .map((m) => Padding(
                          padding: EdgeInsets.only(
                              top: ResponsiveHelper.spacing(context, 4)),
                          child: Text(
                            '· ${m.item.work.workType}: ${m.applyError}',
                            style: ResponsiveHelper.tinyStyle(context)
                                .copyWith(color: AppColors.error),
                          ),
                        )),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        ],
        CommonWidgets.primaryButton(
          context: context,
          text: '확인',
          onPressed: () => Navigator.pop(
            context,
            MultiApplyResult(
              hasChanges: successCount > 0,
              appliedCount: successCount,
            ),
          ),
        ),
      ],
    );
  }
}
