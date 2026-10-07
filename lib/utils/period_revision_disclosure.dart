// lib/utils/period_revision_disclosure.dart
//
// [R7-CONTRACT-PERIOD-DISCLOSURE] 근무 종료일이 바뀐 사실을 **당사자에게**
// 말하기 위한 판정 한 벌.
//
//   서버는 확정할 때 이미 이 사실을 알고 저장한다.
//
//     workEndDatePresentedAtApply  지원자가 지원할 때 화면에서 본 종료일
//     workEndDate                  규칙으로 다시 계산해 적용된 종료일
//     workEndDateRevisedAt         정정된 시각
//
//   그리고 관리자에게는 확정 응답으로 알려 준다(`period_revision_notice`).
//   그 문구는 스스로 "지원자에게 안내가 필요할 수 있습니다" 라고 적고
//   있었는데, 정작 지원자 쪽 reader 가 하나도 없었다. 날짜가 바뀐 당사자가
//   그 사실을 끝내 모른 채 계약서에 바뀐 날짜를 보게 된다.
//
//   ── 이 모듈이 지키는 것 ────────────────────────────────────────
//
//   · 판정은 한 곳에서만 한다. 화면이 날짜를 직접 비교하기 시작하면
//     "같은 날인데 다르다고 말하는" 경우가 생긴다.
//   · 비교는 **KST 달력일**로 한다. 서버가 그렇게 판정했기 때문이다
//     (`srvKstDayStartMs(presented) !== endMs`). 기기 자정과 KST 자정의
//     차이를 변경이라고 부르지 않는다.
//   · 제시값이 없으면 **변경이라고 말하지 않는다.** 적용값만 들고
//     "바뀌었다" 고 할 수는 없다 — 무엇에서 바뀌었는지 모른다.
//   · 공고의 **현재** 종료일을 쓰지 않는다. 지원서에 남은 snapshot 만 본다.
//     공고가 나중에 수정돼도 그 사람의 약속은 그때 그대로다.

import '../models/core/application_model.dart';
import 'format_helper.dart';

class PeriodRevisionDisclosure {
  const PeriodRevisionDisclosure._({
    required this.shouldShow,
    this.presentedEndDate,
    this.appliedEndDate,
  });

  /// 고지할 것이 있는가.
  final bool shouldShow;

  /// 지원 당시 본 종료일.
  final DateTime? presentedEndDate;

  /// 지금 적용된 종료일.
  final DateTime? appliedEndDate;

  static const none = PeriodRevisionDisclosure._(shouldShow: false);

  /// 지원서 snapshot 하나로 판정한다. 다른 입력을 받지 않는다 —
  /// 공고 현재값이 끼어들 자리를 만들지 않기 위해서다.
  factory PeriodRevisionDisclosure.of(ApplicationModel app) =>
      PeriodRevisionDisclosure.from(
        presented: app.workEndDatePresentedAtApply,
        applied: app.workEndDate,
      );

  /// 두 값으로 판정. 관리자 쪽 고지와 **같은 사실**을 쓰기 위해 분리해 둔다.
  factory PeriodRevisionDisclosure.from({
    required DateTime? presented,
    required DateTime? applied,
  }) {
    // 제시값이 없으면 변경을 말할 수 없다(legacy / 정정이 없던 건).
    if (presented == null || applied == null) return none;
    // KST 달력일이 같으면 변경이 아니다.
    if (FormatHelper.toKstDate(presented) == FormatHelper.toKstDate(applied)) {
      return none;
    }
    return PeriodRevisionDisclosure._(
      shouldShow: true,
      presentedEndDate: presented,
      appliedEndDate: applied,
    );
  }
}
