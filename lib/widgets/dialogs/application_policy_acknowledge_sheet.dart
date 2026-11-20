// [R7-PAYROLL-POLICY.4A §12] 지원 당시 기준을 확인하고 확정한다
//
// 언제 보이는가: 기존 열린 공고에서 미확인 기준으로 지원이 들어온 뒤 사업장이
// **다른** 기준을 확인한 경우다. 그러면 사업장의 확인 기록은 새 기준의 것뿐이고,
// 확정하려는 약속의 기준은 지원 당시 것이다. 서버가 그 상태에서 확정을 막는다
// (`APPLICATION_POLICY_NOT_ACKNOWLEDGED`).
//
// 이 화면이 하는 일은 **확인**이다:
//   · 재협상이 아니다 — 근로자에게 새 조건을 제시하지 않는다.
//   · 소급변경이 아니다 — 지원서의 기준을 현재 기준으로 덮지 않는다.
//   · 근로자 재확인이 필요하지 않다 — 그 사람은 이미 이 조건으로 지원했다.
//
// 유리해 보이는 변경이라도 자동 적용하지 않는다. 어느 쪽이 유리한지는 제품이
// 판단할 일이 아니다.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../models/core/application_model.dart';
import '../../models/core/business_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/attendance_policy_disclosure.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/toast_helper.dart';

class ApplicationPolicyAcknowledgeSheet {
  const ApplicationPolicyAcknowledgeSheet._();

  /// 확인에 성공하면 `true` — 호출자가 확정을 다시 시도한다.
  static Future<bool> show(
    BuildContext context, {
    required ApplicationModel application,
    required String workerName,
    AttendanceRules? currentBusinessRules,
  }) async {
    final snapshot = application.attendancePolicySnapshot;
    if (snapshot == null) return false;
    final result = await DialogHelper.showSheet<bool>(
      context,
      isScrollControlled: true,
      builder: (ctx) => _Sheet(
        application: application,
        workerName: workerName,
        snapshot: snapshot,
        currentBusinessRules: currentBusinessRules,
      ),
    );
    return result ?? false;
  }
}

class _Sheet extends StatefulWidget {
  const _Sheet({
    required this.application,
    required this.workerName,
    required this.snapshot,
    required this.currentBusinessRules,
  });

  final ApplicationModel application;
  final String workerName;
  final AttendanceRules snapshot;
  final AttendanceRules? currentBusinessRules;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  bool _sending = false;

  Future<void> _acknowledge() async {
    setState(() => _sending = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableAcknowledgeApplicationPolicy')
          .call<Map<dynamic, dynamic>>({
        'applicationId': widget.application.id,
        'businessId': widget.application.businessId,
      });
      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _sending = false);
      // 권한이 없으면 할 수 없는 일을 시키지 않는다 — 누가 해야 하는지 말한다.
      ToastHelper.showError(e.code == 'permission-denied'
          ? '사업장 관리자만 기준을 확인할 수 있어요\n사업장 관리자에게 확인을 요청해 주세요'
          : (e.message ?? '기준 확인에 실패했어요'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _sending = false);
      ToastHelper.showError('기준 확인에 실패했어요');
    }
  }

  /// [DU295] 큰 글자(1.3배 이상) 배치 전환 기준 — DU264 지원 확인의 `_stacked` 와 같다.
  static bool _stacked(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(10) >= 13;

  /// [DU295] 화면 글자만 낱말 단위로 줄을 바꾼다(문구·접근성 이름은 원문 그대로).
  static Widget _words(String s, {TextStyle? style, TextAlign? textAlign}) =>
      Text(
        TextLayout.keepWords(s),
        semanticsLabel: s,
        style: style,
        textAlign: textAlign,
      );

  @override
  Widget build(BuildContext context) {
    final current = widget.currentBusinessRules;
    final pad = ResponsiveHelper.spacing(context, 20);
    // [DU295] 가운데 내용만 스크롤하고 버튼은 아래에 고정한다.
    //   이전: 버튼이 스크롤 맨 끝 — W360 1.0 첫 화면에서 주 버튼 11px 잘림,
    //   B320 2.0 은 1743px 내려야 닿았다.
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  pad, pad, pad, ResponsiveHelper.spacing(context, 8)),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '지원 당시 기준 확인',
                    style: ResponsiveHelper.subtitleStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  _words(
                    '${widget.workerName}님은 변경 전 근태·급여 기준으로 지원했습니다.\n'
                    '지원 당시 기준으로 확정하며, 조건은 바뀌지 않습니다.',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey600),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  _block(context,
                      title: '지원 당시 기준 (이 근무에 적용)',
                      rules: widget.snapshot,
                      highlight: true),
                  if (current != null &&
                      !current.sameRulesAs(widget.snapshot)) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                    _block(context,
                        title: '현재 사업장 기준 (이 근무에는 적용되지 않음)',
                        rules: current,
                        highlight: false),
                  ],
                  SizedBox(height: ResponsiveHelper.spacing(context, 14)),
                  _words(
                    '현재 사업장 기준은 변경 이후 새로 지원하는 근로자에게 적용됩니다.',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.grey600),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(
                pad, ResponsiveHelper.spacing(context, 8), pad, pad),
            child: _actions(context),
          ),
        ],
      ),
    );
  }

  /// [DU295] 버튼 높이 52. 배율 1.0 은 나중에 1 : 주 2(DU264 지원 확인과 같은 비율),
  ///   큰 글자는 주 버튼 위·나중에 아래(전체 폭). 이전: 반 폭씩이라 '확 | 정' 음절 끊김.
  Widget _actions(BuildContext context) {
    const shape = RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(12)));
    final vPad =
        EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 14));
    final later = OutlinedButton(
      style: OutlinedButton.styleFrom(
        // [DU295] 글자 대표색 → 본문색 w600(DU264 '취소' 와 같다). 처리 중 흐림은 테마 그대로.
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size(0, 52),
        padding: vPad,
        shape: shape,
      ),
      onPressed: _sending ? null : () => Navigator.pop(context, false),
      child: const Text('나중에', style: TextStyle(fontWeight: FontWeight.w600)),
    );
    final primary = ElevatedButton(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.brand,
        foregroundColor: AppColors.surface,
        // [DU295] 처리 중 비활성 — 흰 글 on 회색이라 안 보이던 것을 DU290 DP1 과 같은 짝으로
        disabledBackgroundColor: AppColors.grey200,
        disabledForegroundColor: AppColors.textSecondary,
        minimumSize: const Size(0, 52),
        padding: vPad,
        shape: shape,
      ),
      onPressed: _sending ? null : _acknowledge,
      child: _words(
        _sending ? '확인 중...' : '지원 당시 기준으로 확정',
        textAlign: TextAlign.center,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
    );
    if (_stacked(context)) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          primary,
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          later,
        ],
      );
    }
    return Row(
      children: [
        Expanded(child: later),
        SizedBox(width: ResponsiveHelper.spacing(context, 10)),
        Expanded(flex: 2, child: primary),
      ],
    );
  }

  Widget _block(
    BuildContext context, {
    required String title,
    required AttendanceRules rules,
    required bool highlight,
  }) {
    final stacked = _stacked(context);
    final labelStyle =
        ResponsiveHelper.smallStyle(context, color: AppColors.grey700);
    // [DU295] 값 글자 기본 grey600(회색 면 4.23) → textSecondary. 굵기 그대로.
    final valueStyle =
        ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary)
            .copyWith(fontWeight: FontWeight.w600);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: highlight ? AppColors.surface : AppColors.grey100,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? AppColors.brand : Colors.transparent,
          width: highlight ? 2 : 0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [DU295] '현재 사업장 기준' 제목 grey500(2.46) → textSecondary
          _words(
            title,
            style: ResponsiveHelper.smallStyle(context,
                color: highlight ? AppColors.brand : AppColors.textSecondary),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          // [R7-PAYROLL-POLICY.4B] 근로자 화면·계약서와 **같은 목록**을 쓴다.
          //   관리자가 확인하는 것이 근로자가 본 것과 달라서는 안 된다.
          //   [DU295] 문구는 그대로 두고 화면 글자만 낱말 단위로 묶는다.
          //   큰 글자는 라벨 위·값 아래(DU264 와 같은 기준).
          for (final line in attendancePolicyLines(rules))
            Padding(
              padding:
                  EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 3)),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _words(line.label, style: labelStyle),
                        _words(line.value, style: valueStyle),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: ResponsiveHelper.spacing(context, 80),
                          child: _words(line.label, style: labelStyle),
                        ),
                        Expanded(child: _words(line.value, style: valueStyle)),
                      ],
                    ),
            ),
        ],
      ),
    );
  }
}
