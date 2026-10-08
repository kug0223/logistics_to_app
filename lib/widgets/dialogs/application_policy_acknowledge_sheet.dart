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

  @override
  Widget build(BuildContext context) {
    final current = widget.currentBusinessRules;
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
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
            Text(
              '${widget.workerName}님은 변경 전 근태·급여 기준으로 지원했습니다.\n'
              '지원 당시 기준으로 확정하며, 조건은 바뀌지 않습니다.',
              style:
                  ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            _block(context,
                title: '지원 당시 기준 (이 근무에 적용)',
                rules: widget.snapshot,
                highlight: true),
            if (current != null && !current.sameRulesAs(widget.snapshot)) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 10)),
              _block(context,
                  title: '현재 사업장 기준 (이 근무에는 적용되지 않음)',
                  rules: current,
                  highlight: false),
            ],
            SizedBox(height: ResponsiveHelper.spacing(context, 14)),
            Text(
              '현재 사업장 기준은 변경 이후 새로 지원하는 근로자에게 적용됩니다.',
              style:
                  ResponsiveHelper.tinyStyle(context, color: AppColors.grey600),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 14)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed:
                        _sending ? null : () => Navigator.pop(context, false),
                    child: const Text('나중에'),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 14)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: _sending ? null : _acknowledge,
                    child: Text(
                      _sending ? '확인 중...' : '지원 당시 기준으로 확정',
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
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
    required AttendanceRules rules,
    required bool highlight,
  }) {
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
          Text(
            title,
            style: ResponsiveHelper.smallStyle(context,
                color: highlight ? AppColors.brand : AppColors.grey500),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          // [R7-PAYROLL-POLICY.4B] 근로자 화면·계약서와 **같은 목록**을 쓴다.
          //   관리자가 확인하는 것이 근로자가 본 것과 달라서는 안 된다.
          for (final line in attendancePolicyLines(rules))
            Padding(
              padding:
                  EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 3)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: ResponsiveHelper.spacing(context, 80),
                    child: Text(line.label,
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey700)),
                  ),
                  Expanded(
                    child: Text(line.value,
                        style: ResponsiveHelper.smallStyle(context)
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
