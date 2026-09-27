import 'package:flutter/material.dart';

import '../../models/ui/invite_capacity_state.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// [R7-P1-2 DEVICE.1E.2A] 인력 현황 상단의 **정원 문구**.
///
///   화면에서 떼어 낸 이유는 하나다 — 이 자리에 어떤 숫자가 적히는지를
///   실행으로 확인할 수 있어야 한다. getter 를 읽는 것만으로는 "렌더에
///   노출되지 않는다"를 증명할 수 없다.
///
///   ── 이 위젯이 지키는 계약 ─────────────────────────────────────
///
///   1. **필요 인원은 항상 말한다.** 공고가 정한 값이고 정원 조회와 무관하게
///      유효하다. 조회가 실패했다고 감추면 알 수 있는 것까지 잃는다.
///
///   2. **충원 수는 canonical 일 때만 적는다.** mutation 직후 화면이 손으로
///      다시 센 값은 canonical 과 identity 규칙이 다르다(화면은 `wdId` 를
///      보지 않는다). workType·시간이 같고 wdId 만 다른 두 업무가 있으면
///      같은 지원서를 둘 다에 세어 **필요 12 에 15** 가 나올 수 있다.
///      그 수를 `갱신 중` 이라는 말과 함께라도 현재 충원으로 적지 않는다.
///
///   3. **모르는 것과 확인 중인 것을 구분한다.** 방금 확정을 누른 관리자에게
///      `확인 불가` 는 실패처럼 읽힌다 — 그 처리는 성공했다.
class CapacitySummaryText extends StatelessWidget {
  /// 이 업무가 필요로 하는 인원. 공고가 정한 값이다.
  final int requiredCount;

  /// canonical 정원 조회의 판정. UNKNOWN 이면 수치를 말할 수 없다.
  final InviteCapacityState capacity;

  /// 아직 확인 중인가(mutation 직후의 로컬 값 또는 재조회 진행 중).
  final bool isPending;

  const CapacitySummaryText({
    super.key,
    required this.requiredCount,
    required this.capacity,
    required this.isPending,
  });

  bool get _unknown => capacity == InviteCapacityState.unknown;

  /// UNKNOWN 일 때 그 이유를 말하는 짧은 꼬리말. 알고 있으면 null.
  ///
  ///   `정원 확인 불가` 문구는 기존 계약이므로 그대로 둔다.
  String? get stateLabel {
    if (!_unknown) return null;
    return isPending ? '갱신 중' : '정원 확인 불가';
  }

  @override
  Widget build(BuildContext context) {
    final tail = stateLabel;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: ResponsiveHelper.spacing(context, 6),
      children: [
        // 필요 인원은 조회 상태와 무관하게 유효하다.
        Text(
          '필요 $requiredCount명',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
        ),
        if (tail != null)
          Text(
            tail,
            style:
                ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
          ),
      ],
    );
  }
}
