import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/utils/text_layout.dart';

/// [ADMIN-HOME.31] TextLayout.phrases — 구분점 문구를 낱말 단위로만 줄바꿈.
void main() {
  const wj = '⁠';

  test('TLP-1 원문 복원 — 표시 전용 문자만 넣는다', () {
    for (final s in [
      '연체 1건 · 지급일 확인 필요 1건',
      '[합성] E7 사업장 · 분류 · 10:35–11:35',
      '다음 근무는 내일이에요\n[합성] E7 사업장 · 5명 중 0명 확정',
      '가장 오래된 날 2026.10.05',
    ]) {
      expect(TextLayout.plain(TextLayout.phrases(s)), s);
    }
  });

  test('TLP-2 낱말 안은 WORD JOINER, 공백에서만 줄바꿈 가능', () {
    final d = TextLayout.phrases('지급일 확인 필요 1건');
    expect(d, '지${wj}급${wj}일 확${wj}인 필${wj}요 1${wj}건');
  });

  test('TLP-3 구분점은 앞 조각에 붙는다 — 다음 줄이 · 로 시작하지 않는다', () {
    final d = TextLayout.phrases('연체 1건 · 지급일');
    expect(d, '연${wj}체 1${wj}건$wj $wj· 지${wj}급${wj}일');
  });

  test('TLP-4 줄바꿈 문자는 유지', () {
    final d = TextLayout.phrases('가 나\n다');
    expect(d.split('\n').length, 2);
  });
}
