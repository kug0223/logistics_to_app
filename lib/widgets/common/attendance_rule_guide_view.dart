import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/attendance_policy_disclosure.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';

/// [ATTENDANCE-RULE-GUIDE.29-A1] 공고·초대·계약 공통 '근태 인정 기준' 표시 — 표시만 한다.
///
///   근무시간 → 출근 기준(일찍 출근·지각) → 퇴근 기준(늦게 퇴근·조퇴). 항목마다 짧은 설명 바로 아래에
///   그 기준의 사례('17:41 출근 → 인정 시작 18:05')를 둔다. 라벨 칸 + 긴 본문 표를 쓰지 않고 전폭을 쓴다.
///   기준 설명은 항상 보인다. [collapsibleExamples] 이면 사례만 '시간 예시 보기' 로 접는다(공고·초대).
///   글자는 줄이지 않고 띄어쓰기에서만 줄을 바꾼다. 사례의 '입력 →' 과 '결과' 는 각각 한 덩어리.
class AttendanceRuleGuideView extends StatefulWidget {
  final AttendanceRuleGuide guide;
  final bool collapsibleExamples;

  /// 근무시간 줄 앞말 — 공고는 어느 근무 시각 기준인지 밝힌다('예시 기준 근무').
  final String workTimeLabel;

  const AttendanceRuleGuideView({
    super.key,
    required this.guide,
    this.collapsibleExamples = false,
    this.workTimeLabel = '근무시간',
  });

  @override
  State<AttendanceRuleGuideView> createState() => _AttendanceRuleGuideViewState();
}

class _AttendanceRuleGuideViewState extends State<AttendanceRuleGuideView> {
  bool _showExamples = false;

  @override
  Widget build(BuildContext context) {
    final g = widget.guide;
    final examplesVisible = !widget.collapsibleExamples || _showExamples;
    final body = ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary);
    final muted = ResponsiveHelper.smallStyle(context, color: AppColors.grey600);
    final gap = ResponsiveHelper.spacing(context, 6);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (g.workTime != null)
          Padding(
            padding: EdgeInsets.only(bottom: gap),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: '${widget.workTimeLabel} ', style: muted),
                TextSpan(
                  text: TextLayout.unit(g.workTime!),
                  semanticsLabel: g.workTime,
                  style: body.copyWith(fontWeight: FontWeight.w600),
                ),
              ]),
            ),
          ),
        for (final section in g.sections) ...[
          Padding(
            padding: EdgeInsets.only(top: gap),
            child: Text(section.title,
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary)
                    .copyWith(fontWeight: FontWeight.w700)),
          ),
          for (final item in section.items)
            Padding(
              padding: EdgeInsets.only(top: gap, left: ResponsiveHelper.spacing(context, 8)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title,
                      style: body.copyWith(fontWeight: FontWeight.w600, color: AppColors.grey700)),
                  for (final p in item.points)
                    Padding(
                      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 2)),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('· ', style: muted),
                          Expanded(
                            child: Text(TextLayout.keepWords(p), semanticsLabel: p, style: body),
                          ),
                        ],
                      ),
                    ),
                  if (examplesVisible)
                    for (final e in item.examples)
                      Padding(
                        padding: EdgeInsets.only(
                            top: ResponsiveHelper.spacing(context, 2),
                            left: ResponsiveHelper.spacing(context, 10)),
                        child: Semantics(
                          label: '예: ${attendanceRuleExampleText(e)}',
                          excludeSemantics: true,
                          child: Wrap(
                            spacing: ResponsiveHelper.spacing(context, 4),
                            children: [
                              Text(TextLayout.unit('예: ${e.input} →'), style: muted),
                              Text(TextLayout.unit(e.result),
                                  style: body.copyWith(fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ),
                      ),
                ],
              ),
            ),
        ],
        if (widget.collapsibleExamples && g.hasExamples)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _showExamples = !_showExamples),
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              child: Text(_showExamples ? '시간 예시 접기' : '시간 예시 보기',
                  // [DU1 구현127 C124-2] 현 위치 사례 펼침/접기 보조 행동 글자 — infoDark(#1976D2)는 초대 수락 grey50 상자에서 4.41:1
                  //   (작은 글 4.5 미만, 구현127 관측). 앱의 행동 파랑 brand(흰 5.58 · grey50 5.35)로 한 값만 바꾼다. 크기·굵기·문구·배치·상태는 그대로.
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.brand)),
            ),
          ),
      ],
    );
  }
}
