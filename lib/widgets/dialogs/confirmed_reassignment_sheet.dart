// lib/widgets/dialogs/confirmed_reassignment_sheet.dart
//
// [CROSS-DOMAIN-R5.3E.2] 확정 근무 변경 — 근로자 결정 화면과 관리자 확인.
//
//   근로자가 여기서 고르는 것은 "수락 / 거절"이 아니다.
//   **기존 조건을 유지할 것인가, 변경을 받아들일 것인가**이다.
//   거절이라는 말은 관계가 끝난다는 인상을 주는데, 실제로는 원래 확정이
//   그대로 남는다. 그래서 CTA는 `기존 조건 유지`다.
//
//   두 조건을 나란히 놓고 **바뀌는 항목만** 강조한다. 전부 같은 무게로
//   보여주면 무엇이 달라지는지 근로자가 직접 대조해야 한다.

import 'package:flutter/material.dart';

import '../../models/core/confirmed_reassignment_proposal.dart';
import '../../services/confirmed_reassignment_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import 'apply/document_access_consent.dart';

/// 근로자 결정 결과.
enum ReassignmentDecision { kept, changed, dismissed }

class ConfirmedReassignmentSheet {
  const ConfirmedReassignmentSheet._();

  /// 서버 동의 문구 버전 — 지원·초대 수락과 같은 값을 쓴다.
  ///
  /// [R1.2] 문자열을 복제하지 않는다. 버전과 문구는 한 곳에서만 올라간다 —
  /// 복제해 두면 문구를 고칠 때 한쪽만 바뀌어 기록이 거짓이 된다.
  static String get consentVersion => DocumentAccessConsent.version;

  /// 근로자에게 변경 제안을 보여주고 결정을 받는다.
  static Future<ReassignmentDecision> decide(
    BuildContext context,
    ConfirmedReassignmentProposal p,
  ) async {
    final result = await DialogHelper.showSheet<ReassignmentDecision>(
      context,
      isScrollControlled: true,
      builder: (ctx) => _DecisionSheet(proposal: p),
    );
    return result ?? ReassignmentDecision.dismissed;
  }

  /// 관리자 — 보낸 제안을 철회한다.
  static Future<bool> confirmCancel(
    BuildContext context,
    ConfirmedReassignmentProposal p,
  ) async {
    final ok = await DialogHelper.showConfirm(
      context,
      title: '변경 제안 철회',
      message: '보낸 근무 변경 제안을 철회합니다.\n'
          '근로자의 기존 근무는 그대로 유지됩니다.',
      confirmText: '철회',
      cancelText: '닫기',
    );
    if (ok != true) return false;
    return ConfirmedReassignmentService.instance.cancel(p.proposalId);
  }
}

class _DecisionSheet extends StatelessWidget {
  final ConfirmedReassignmentProposal proposal;
  const _DecisionSheet({required this.proposal});

  @override
  Widget build(BuildContext context) {
    final cur = proposal.current;
    final next = proposal.proposed;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '근무 변경 제안',
              style: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '${proposal.businessName}에서 근무 조건 변경을 제안했습니다.\n'
              '선택하기 전까지 지금 확정된 근무는 그대로입니다.',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey600),
            ),
            const SizedBox(height: 16),
            _block(
              context,
              title: '현재 확정된 근무',
              promise: cur,
              muted: true,
              changed: const {},
            ),
            const SizedBox(height: 8),
            Center(
              child: Icon(Icons.arrow_downward,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: AppColors.grey400),
            ),
            const SizedBox(height: 8),
            _block(
              context,
              title: '변경 제안',
              promise: next,
              muted: false,
              // 바뀌는 항목만 강조한다 — 나머지는 그대로라는 뜻이다.
              changed: {
                if (proposal.changesWorkType) 'workType',
                if (proposal.changesTime) 'time',
                if (proposal.changesWage) 'wage',
              },
            ),
            if (proposal.hasIndividualCompensation) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.infoBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '이 급여는 회원님에게만 적용되는 조건입니다.',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.infoDeep),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              '변경을 수락하면 지금 확정된 근무는 ‘다른 업무로 변경 확정’으로 '
              '정리되며, 취소·노쇼 불이익은 적용되지 않습니다.\n'
              '기존 조건을 유지하면 아무것도 바뀌지 않습니다.',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey600),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final ok = await ConfirmedReassignmentService.instance
                          .decline(proposal.proposalId);
                      if (!context.mounted) return;
                      Navigator.pop(
                          context,
                          ok
                              ? ReassignmentDecision.kept
                              : ReassignmentDecision.dismissed);
                    },
                    child: const Text('기존 조건 유지'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () async {
                      final ok = await ConfirmedReassignmentService.instance
                          .accept(
                        proposalId: proposal.proposalId,
                        documentAccessConsentVersion:
                            ConfirmedReassignmentSheet.consentVersion,
                      );
                      if (!context.mounted) return;
                      Navigator.pop(
                          context,
                          ok
                              ? ReassignmentDecision.changed
                              : ReassignmentDecision.dismissed);
                    },
                    child: const Text('변경 수락',
                        style: TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _block(
    BuildContext context, {
    required String title,
    required ReassignmentPromise? promise,
    required bool muted,
    required Set<String> changed,
  }) {
    final fg = muted ? AppColors.grey600 : AppColors.grey800;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: muted ? AppColors.grey100 : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: muted ? Colors.transparent : AppColors.brand,
          width: muted ? 0 : 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: ResponsiveHelper.smallStyle(context,
                  color: muted ? AppColors.grey500 : AppColors.brand)),
          const SizedBox(height: 6),
          if (promise == null)
            Text('조건 정보를 불러오지 못했습니다.',
                style: ResponsiveHelper.bodyStyle(context,
                    color: AppColors.grey500))
          else ...[
            _row(context, '업무', promise.workType ?? '-',
                highlight: changed.contains('workType'), fg: fg),
            _row(context, '시간', promise.timeRange,
                highlight: changed.contains('time'), fg: fg),
            _row(
              context,
              '급여',
              promise.wage == null
                  ? '-'
                  : '${FormatHelper.formatWage(promise.wage!)}'
                      '${promise.wageType == 'hourly' ? ' (시급)' : ''}'
                      '${promise.wageType == 'daily' ? ' (일급)' : ''}',
              highlight: changed.contains('wage'),
              fg: fg,
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {required bool highlight, required Color fg}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 44,
            child: Text(label,
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey500)),
          ),
          Expanded(
            child: Text(
              value,
              style: ResponsiveHelper.bodyStyle(context,
                      color: highlight ? AppColors.brand : fg)
                  .copyWith(
                      fontWeight:
                          highlight ? FontWeight.bold : FontWeight.normal),
            ),
          ),
          if (highlight)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('변경',
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.brand)),
            ),
        ],
      ),
    );
  }
}
