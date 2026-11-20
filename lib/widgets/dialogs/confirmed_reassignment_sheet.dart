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
import '../../utils/text_layout.dart';
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
    // [DU270] 큰 글자(DU256 규칙) — 버튼을 세로로 쌓는다(반 폭에 '기존 조건 유지'가 들어가지 않는다)
    final stacked = MediaQuery.textScalerOf(context).scale(10) >= 13;

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
            _note(
              context,
              '${proposal.businessName}에서 근무 조건 변경을 제안했습니다.\n'
              '선택하기 전까지 지금 확정된 근무는 그대로입니다.',
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
                  color: AppColors.textTertiary), // [DU270] grey400 1.88
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
            const SizedBox(height: 10),
            // [R7-PAYROLL-POLICY.4A §25·§27A] 이 제안이 바꾸는 것은 업무·시간·
            //   임금이다(위 두 칸이 그것만 비교한다). 근태·급여 처리 기준은
            //   지금 확정된 근무의 것이 그대로 따라간다 — 사업장이 그 사이
            //   기준을 바꿨더라도 이 변경을 계기로 적용되지 않는다.
            //   그래서 숫자를 다시 보여주지 않고 **바뀌지 않는다는 사실**을
            //   말한다(값을 위해 문서를 더 읽지도 않는다).
            // [R7-PAYROLL-POLICY.4B §31] 숫자를 다시 보여주지 않는 대신
            //   **어디서 볼 수 있는지** 말한다. 지금 확정된 근무의 기준은 그
            //   근무의 근로계약서에 7개 항목으로 적혀 있다(같은 snapshot 이다).
            //   값을 위해 사업장 문서를 읽지 않는다.
            _note(
              context,
              '근태·급여 처리 기준은 지금 확정된 근무와 동일하게 유지됩니다.\n'
              '기준 내용은 해당 근무의 근로계약서에서 확인할 수 있습니다.',
            ),
            const SizedBox(height: 16),
            _note(
              context,
              '변경을 수락하면 지금 확정된 근무는 ‘다른 업무로 변경 확정’으로 '
              '정리되며, 취소·노쇼 불이익은 적용되지 않습니다.\n'
              '기존 조건을 유지하면 아무것도 바뀌지 않습니다.',
            ),
            const SizedBox(height: 16),
            // [DU270] 보통 글자는 왼쪽 '기존 조건 유지'·오른쪽 '변경 수락', 큰 글자는 같은 순서로 위·아래.
            if (stacked) ...[
              SizedBox(width: double.infinity, child: _keepButton(context)),
              const SizedBox(height: 10),
              SizedBox(width: double.infinity, child: _changeButton(context)),
            ] else
              Row(
                children: [
                  Expanded(child: _keepButton(context)),
                  const SizedBox(width: 10),
                  Expanded(child: _changeButton(context)),
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
    // [DU270] 현재 칸은 덜 강조하되 읽히게(grey100 위 grey500 2.46·grey600 4.23 → 바탕색 면 위 textSecondary 5.5),
    //   제안 칸은 흰 면·대표색 2 선 유지, 값 본문색. 시안 카드 radius 16.
    final fg = muted ? AppColors.textSecondary : AppColors.textPrimary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: muted ? AppColors.background : AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: muted ? null : Border.all(color: AppColors.brand, width: 2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(TextLayout.keepWords(title),
              semanticsLabel: title,
              style: ResponsiveHelper.smallStyle(context,
                  color: muted ? AppColors.textSecondary : AppColors.brand,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          if (promise == null)
            Text(TextLayout.keepWords('조건 정보를 불러오지 못했습니다.'),
                semanticsLabel: '조건 정보를 불러오지 못했습니다.',
                style: ResponsiveHelper.bodyStyle(context,
                    color: AppColors.textSecondary))
          else ...[
            // [DU270] 값 표시만 줄바꿈 단위를 준다 — 업무명 identity, 시간 한 덩어리, 급여 낱말(화면 읽기는 원문)
            _row(context, '업무', promise.workType ?? '-',
                shown: TextLayout.identity(promise.workType ?? '-'),
                highlight: changed.contains('workType'), fg: fg),
            _row(context, '시간', promise.timeRange,
                shown: TextLayout.unit(promise.timeRange),
                highlight: changed.contains('time'), fg: fg),
            _row(
              context,
              '급여',
              _wageText(promise),
              shown: TextLayout.keepWords(_wageText(promise)),
              highlight: changed.contains('wage'),
              fg: fg,
            ),
          ],
        ],
      ),
    );
  }

  static String _wageText(ReassignmentPromise p) => p.wage == null
      ? '-'
      : '${FormatHelper.formatWage(p.wage!)}'
          '${p.wageType == 'hourly' ? ' (시급)' : ''}'
          '${p.wageType == 'daily' ? ' (일급)' : ''}';

  /// [DU270] 안내 문장 — grey600(4.61)·grey700 → textSecondary, 표시만 낱말 단위(semanticsLabel 원문).
  Widget _note(BuildContext context, String s) => Text(
        TextLayout.keepWords(s),
        semanticsLabel: s,
        style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
      );

  /// [DU270] 공용 OutlinedButton 테마(brand 글자·grey300 선·radius 12). 결정·서비스 호출은 그대로다.
  ///   [r1] 나란한 '변경 수락'(Elevated 테마 16 bold·상하 14 → 51)과 높이·글자를 맞춘다(UI-1, 이전 48 vs 51).
  Widget _keepButton(BuildContext context) => OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: ResponsiveHelper.bodyStyle(context, fontWeight: FontWeight.bold)
              .copyWith(fontSize: 16),
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
      );

  /// [DU270] 공용 ElevatedButton 테마(brand·흰 글자·48·radius 12) — 직접 지정한 색·모양(값 같음)을 걷었다.
  Widget _changeButton(BuildContext context) => ElevatedButton(
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
        child: const Text('변경 수락'),
      );

  Widget _row(BuildContext context, String label, String value,
      {required bool highlight, required Color fg, String? shown}) {
    // [DU270] 이름 grey500(2.46~2.68) → textTertiary, '변경' 표시 brand 12% 면(4.71) → brandSurface 토큰·w600·radius 8
    final labelText = Text(label,
        style: ResponsiveHelper.smallStyle(context, color: AppColors.textTertiary));
    final valueText = Text(
      shown ?? value,
      semanticsLabel: value,
      style: ResponsiveHelper.bodyStyle(context,
              color: highlight ? AppColors.brand : fg)
          .copyWith(
              fontWeight:
                  highlight ? FontWeight.bold : FontWeight.normal),
    );
    final mark = highlight
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.brandSurface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('변경',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.brand, fontWeight: FontWeight.w600)),
          )
        : null;
    // [DU270] 큰 글자(DU256 규칙)에서는 이름·'변경'을 윗줄, 값을 아래 전체 폭에 둔다 — 폭 44 칸에서 '업/무'·'급/여',
    //   값 칸에서 '포장 및 검/수'로 끊겼다.
    if (MediaQuery.textScalerOf(context).scale(10) >= 13) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Flexible(child: labelText),
                if (mark != null) ...[const SizedBox(width: 8), mark],
              ],
            ),
            valueText,
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 44, child: labelText),
          Expanded(child: valueText),
          if (mark != null) mark,
        ],
      ),
    );
  }
}
