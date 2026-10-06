// lib/widgets/auth/legal_consent_list.dart
//
// [R7-LEGAL.1B.1] 동의를 받는 자리는 **한 벌**이어야 한다.
//
//   가입·복구·재동의는 들어온 맥락만 다르고 묻는 것은 같다. 본문을 보여
//   주고, 필수와 선택을 구분하고, 사용자가 직접 고르고, 열람을 동의로
//   세지 않는다. 화면마다 다른 동의 다이얼로그를 만들면 그 규칙이 조금씩
//   어긋난다.
//
//   판정은 `TermsConsentPlan` 이 갖고 이 위젯은 그리기만 한다.

import 'package:flutter/material.dart';

import '../../models/core/legal_terms_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/terms_consent_plan.dart';
import 'terms_viewer_screen.dart';

class LegalConsentList extends StatelessWidget {
  const LegalConsentList({
    super.key,
    required this.items,
    required this.stored,
    required this.choices,
    required this.viewed,
    required this.onChanged,
    required this.onViewed,
    this.enabled = true,
    this.highlightIds = const <String>{},
  });

  final List<LegalTermsItem> items;
  final Map<String, StoredConsent> stored;
  final Map<String, bool> choices;
  final Set<String> viewed;

  /// 사용자가 체크를 바꿨다.
  final void Function(String itemId, bool agreed) onChanged;

  /// 본문을 열었다(동의 여부와 무관).
  final void Function(String itemId) onViewed;

  final bool enabled;

  /// 이번에 바뀐 항목 — 재동의에서 "무엇이 달라졌는지" 를 말하기 위해 쓴다.
  final Set<String> highlightIds;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final item in items) _row(context, item)],
      );

  Widget _row(BuildContext context, LegalTermsItem item) {
    // 이미 같은 판에 동의한 항목은 여기서 취소하지 않는다(서버도 막는다).
    final settled = TermsConsentPlan.isLocked(item, stored);
    final checked = choices[item.id] == true;
    final changed = highlightIds.contains(item.id);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: checked,
            onChanged: (settled || !enabled)
                ? null
                : (v) {
                    final on = v ?? false;
                    // 보지 않은 약관에 체크부터 하게 두지 않는다 — 누르면
                    // 본문을 먼저 연다.
                    if (on && !viewed.contains(item.id)) {
                      _open(context, item);
                      return;
                    }
                    onChanged(item.id, on);
                  },
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: item.isRequired ? AppColors.errorBg : AppColors.grey100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              item.isRequired ? '필수' : '선택',
              style: ResponsiveHelper.tinyStyle(
                context,
                color: item.isRequired ? AppColors.error : AppColors.grey500,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              settled
                  ? '${item.title} (동의함)'
                  : (changed ? '${item.title} (변경됨)' : item.title),
              style: ResponsiveHelper.smallStyle(
                context,
                color: settled ? AppColors.grey500 : AppColors.grey900,
              ),
            ),
          ),
          TextButton(
            onPressed: enabled ? () => _open(context, item) : null,
            child: Text('보기', style: ResponsiveHelper.smallStyle(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, LegalTermsItem item) async {
    final agreed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => TermsViewerScreen(item: item)),
    );
    onViewed(item.id);
    // 뷰어에서 '동의하고 닫기' 를 누른 경우에만 체크된다. 그냥 닫으면
    // 선택은 그대로다 — 열람이 동의가 되지 않는다.
    if (agreed == true) onChanged(item.id, true);
  }
}
