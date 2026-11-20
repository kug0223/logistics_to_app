// [DU1-F2~F4] 대표 화면 보완 계약(소스) — DU_followup_2 §2.
//   실제 렌더·320dp·2.0 분절 해소는 기기 캡처(D:\AlFit-evidence\DU1\afterC3)가 근거다. 여기서는 되돌림을 막는다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _code(String p) => File(p)
    .readAsLinesSync()
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

void main() {
  final detail = _code('lib/screens/common/job_posting_screen.dart');

  test('[F3] 하단 주 행동 라벨은 짧게 — 선택 수는 버튼 위 줄로 분리', () {
    expect(detail.contains("buttonText = '지원하기';"), isTrue);
    expect(detail.contains("개 업무 선택됨  ·  지원하기"), isFalse, reason: '320dp·2.0 에서 지원하/기로 끊기던 결합 라벨');
    expect(detail.contains("Text('\$count개 업무 선택됨'"), isTrue);
    expect(detail.contains('minimumSize: const Size.fromHeight(52)'), isTrue, reason: '주 행동 최소 52');
  });

  test('[F4] 날짜 헤더 수치는 범위 그대로 — 가능한 업무라 부르지 않는다', () {
    expect(detail.contains('가능한 업무 \$available개'), isFalse);
    // 숫자와 '개' 사이 단어 결합(⁠) — 큰 글씨에서 '1|개'로 떼지 않는다
    expect(detail.contains("· 업무 \${workDetails.length}\\u2060개"), isTrue);
  });

  test('[F2] 실근무·공제 방식은 읽을 수 있는 보조 글자색', () {
    final i = detail.indexOf("'실근무 \${_netTimeKorean(work)}'");
    expect(i, greaterThan(0));
    expect(detail.substring(i, i + 200).contains('AppColors.textSecondary'), isTrue);
    final j = detail.indexOf('InsuranceRateModel.typeLabel(work.taxDeductionType)');
    expect(detail.substring(j, j + 200).contains('AppColors.textSecondary'), isTrue);
  });

  test('[F2] 금액 단위 — 홈 새 확정·지원 확인 요약에 저장 급여 형태 라벨', () {
    final home = _code('lib/screens/user/user_home_screen.dart');
    expect(home.contains('FormatHelper.formatWageWithType(app.wage, wageType)'), isTrue);
    final sheet = _code('lib/widgets/dialogs/apply/multi_apply_confirm_sheet.dart');
    expect(sheet.contains(r"${work.wageTypeLabel} ${work.formattedWage}"), isTrue);
  });
  test('[82-R §2] 급여 목록 휴게 칩은 미확정(pending)만 편집한다 — 계산분은 명세 경로', () {
    final src = _code('lib/screens/business_admin/dialogs/wage_confirm_dialog.dart');
    expect(src.contains('onTap: isPending ? () => _showBreakReviewSheet(context, app) : null,'), isTrue);
  });

  test('[F2] 의미색 안내 본문은 진한 글자 토큰(경고 3.0 → 4.96)', () {
    final src = _code('lib/widgets/dialogs/styled_dialog.dart');
    expect(src.contains('if (color == AppColors.warning) return AppColors.warningDark;'), isTrue);
    // [DU288] 본문 스타일이 한 줄로 바뀌었다 — 뿌리(본문 글자색 = _textColor 토큰)는 같다.
    expect(src.contains('ResponsiveHelper.smallStyle(context, color: _textColor(color))'), isTrue);
  });
}
