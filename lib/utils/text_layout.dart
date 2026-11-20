import 'package:flutter/widgets.dart';

/// [COMMON-TEXT-LAYOUT.28] 좁은 폭·큰 글자에서 글자를 **줄이지 않고** 읽히게 하는 표시 규칙.
///
///   데이터 조회·권한·writer 는 두지 않는다 — 표시만.
///
///   원인 기록: `ResponsiveHelper.spacing()` 은 폭 360dp 미만에서 간격·고정 칸 폭을 85% 로 줄이지만
///   글자 크기(`smallStyle` 13 등)는 그대로다. 그래서 화면만 좁아져도 고정 칸의 한글이 음절 단위로
///   끊겼다('근무 / 일', '합성 다 / 건'). 사용자가 OS 글자를 키운 경우는 그 크기를 되돌려 줄이지 않고
///   배치를 바꾼다([fits]).
class TextLayout {
  TextLayout._();

  static const String _wordJoiner = '\u2060';
  static const String _breakHere = '\u200B';

  /// 짧은 레이블('급여 확정 근무', '근무일')·한 단위 문구 — 줄바꿈은 **공백에서만**.
  ///   한 낱말이 칸보다 길면 Flutter 가 낱말 안에서 강제로 끊으므로 잘리지는 않는다.
  static String keepWords(String s) =>
      s.split(' ').map((w) => w.characters.join(_wordJoiner)).join(' ');

  /// 이름·사업장명·업무명 — 식별 정보. 낱말 단위로 바꾸고, 띄어쓰기 없는 긴 이름(6자 이상)은
  ///   **가운데에서만** 끊을 수 있게 둔다. 마지막 한 음절만 다음 줄에 남는 배치를 피한다.
  static String identity(String s) => s.split(' ').map((w) {
        final cs = w.characters.toList();
        if (cs.length < 6) return cs.join(_wordJoiner);
        final mid = (cs.length / 2).ceil();
        return cs.sublist(0, mid).join(_wordJoiner) +
            _breakHere +
            cs.sublist(mid).join(_wordJoiner);
      }).join(' ');

  /// 한 덩어리 — 안에서는 줄을 바꾸지 않는다('(실근무 1.2h)', '17:35 ~'). 공백은 줄바꿈 없는 공백,
  ///   글자 사이는 WORD JOINER. 덩어리가 칸보다 길면 Flutter 가 강제로 끊으므로 잘리지는 않는다.
  ///   [.29] 기기에서 NBSP 만으로는 '17:35 / ~' 가 갈렸다 — 글자 사이를 함께 묶는다.
  static String unit(String s) => s.replaceAll(' ', '\u00A0').characters.join(_wordJoiner);

  /// 시간 범위 — 줄을 바꿔야 하면 '~' **뒤**에서만('00:00 ~' / '23:30'). 시각 안에서는 바뀌지 않는다.
  static String range(String from, String to) => '${unit('$from ~')} ${unit(to)}';

  /// 구분점으로 이은 머리말('2026년 10월 29일 (목) · 공고 1개 · 업무 3개') — 줄은 **구분점 뒤**에서만 바뀐다.
  ///   조각('공고 1개') 안은 글자 사이를 모두 WORD JOINER 로 묶고 구분점은 앞 조각에 붙인다
  ///   (다음 줄이 '·' 로 시작하거나 '공고 1 / 개' 로 갈리지 않게). 기기 실측: 줄바꿈 없는 공백(NBSP)만으로는
  ///   한글 음절 앞 줄바꿈이 막히지 않았다.
  static String joinParts(String joined, {String sep = ' · '}) => joined
      .split(sep)
      .map((p) => p.replaceAll(' ', '\u00A0').characters.join(_wordJoiner))
      .join('$_wordJoiner\u00A0$_wordJoiner· ');

  /// [ADMIN-HOME.31] 구분점으로 이은 상태 문구('연체 1건 · 지급일 확인 필요 1건', '사업장 · 업무 · 10:35–11:35')
  ///   — 낱말 안에서는 끊지 않고([keepWords]), 구분점은 앞 조각에 붙인다(다음 줄이 '·' 로 시작하지 않게).
  ///   [joinParts] 와 달리 조각 안의 **공백에서는** 줄을 바꿀 수 있다 — 긴 조각이 한 덩어리로 강제로 끊기지 않게.
  ///   줄바꿈 문자는 그대로 둔다.
  static String phrases(String s, {String sep = ' · '}) => s
      .split('\n')
      .map((line) => line.split(sep).map(keepWords).join('$_wordJoiner\u00A0$_wordJoiner· '))
      .join('\n');

  /// [UI-INTEGRATION.33] 금액·큰 숫자('1,322,099,341원') — 말줄임·축소 없이, 줄을 바꿔야 하면 **쉼표 뒤**에서만
  ///   ('1,322,099,' / '341원'). 숫자 묶음 안과 '원'·'건' 같은 단위 앞에서는 끊지 않는다.
  static String amount(String s) => s
      .split(',')
      .map((p) => p.characters.join(_wordJoiner))
      .join(',$_breakHere');

  /// 위 규칙들이 넣은 표시 전용 문자를 뺀 원문 — 접근성 이름(`semanticsLabel`)에 쓴다.
///   화면 글자에만 줄바꿈 제어 문자를 두고, 화면 읽기·시험·복사 기준은 원문으로 둔다.
///   (WORD JOINER U+2060 · ZERO WIDTH SPACE U+200B 제거, NBSP U+00A0 → 공백)
  static String plain(String s) =>
      s.replaceAll(_wordJoiner, '').replaceAll(_breakHere, '').replaceAll('\u00A0', ' ');

  /// 고정 탭 [count] 개가 [available] 폭에 탭 이름 한 줄로 들어가는가 — 아니면 TabBar 를 가로 스크롤로.
  ///   [perTab] 은 '확인필요 12' 같은 탭 하나의 글자 배율 1.0 기준 폭.
  static bool tabsFit(BuildContext context, double available, int count, {double perTab = 88}) =>
      fits(context, available, perTab * count);

  /// 이 배치(표의 열들·한 줄 칸들)가 [available] 폭에 들어가는가.
  ///   [baseWidth] 는 글자 배율 1.0 기준 폭 — 사용자 글자 배율을 곱해 비교하므로 큰 글자는 더 일찍
  ///   다른 배치(쌓은 행·2×2)로 간다. 영역에서 **한 번** 부른다(셀마다 재지 않는다).
  static bool fits(BuildContext context, double available, double baseWidth) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return available >= baseWidth * scale;
  }
}
