// [impl_21 J4 · 2026-11-27] TextLayout 문구 정확 finder 재발 방지 census(시험 전용).
//
//   TextLayout.keepWords / identity / unit / range … 는 줄바꿈 제어용 보이지 않는 문자(U+2060 WORD JOINER ·
//   U+200B · U+00A0)를 글자 사이에 넣는다. 그 문구를 정확 `find.text('…')` / `find.textContaining('…')` 로
//   찾으면 늘 0개다 — 긍정 단언은 실패하고(ARP-36), **부정 단언(findsNothing)은 늘 통과하는 빈 단언**이 된다
//   (H35-DATE · TP-1/3/4/5 · ARP 지원완료). 공용 `support/visible_text.dart` 의 `findVisibleText` /
//   `findVisibleTextContaining` 을 쓴다.
//
//   탐지(근사 · 정밀 우선):
//   1) lib 의 `TextLayout.<fn>(` 인자 안 문자열 리터럴 + 인자가 식별자 하나면 같은 파일의 `이름: '…'` / `이름 = '…'`
//      리터럴을 'TextLayout 문맥' 위치로 모은다.
//   2) 그 리터럴이 lib 에서 **TextLayout 문맥에서만** 나오면(다른 자리에서 그대로 그려지는 일이 없으면) 대상.
//   3) test 의 정확 finder 가 대상 문구(또는 그 일부 · 두 글자 이상 낱말)를 찾으면 위반.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 서버 담당 l57 실행 목록에 든 파일 — 그 실행이 끝난 뒤 같은 변환을 한다(impl_21 §3.1). 이유 없는 예외는 두지 않는다.
///   [impl_21] du1_s038 의 5줄('수정' 4 · '삭제' 1)은 1차 근사(위치 무관)에서 잡혔지만, 이 census 의 정밀 규칙(2)으로는
///   위반이 아니다 — 두 문구는 lib 에 TextLayout 없이 그려지는 자리도 있다. 그래서 예외로 두지 않는다
///   (두면 '쓰이지 않는 예외' 로 실패한다). 보이는 글자 finder 로 바꾸는 정리는 l57 실행 뒤 따로 한다.
const _pendingConversion = <String, String>{};

/// 같은 문구가 그 화면에서는 TextLayout 없이 그려진다고 확인한 것(정확 finder 가 실제로 맞는다 · 탐지 근사의 오탐).
///   키 = '시험 파일|kind|문구' · 값 = 근거(그리는 위젯).
const _reviewedPlain = <String, String>{};

final _call = RegExp(r'TextLayout\.\w+\(');
final _lit = RegExp(r"'((?:[^'\\$\n]|\\.)*)'");
final _word2 = RegExp(r'[가-힣A-Za-z0-9]{2}');
final _find = RegExp(r"find\.(text|textContaining)\(\s*'((?:[^'\\$\n]|\\.)*)'");

/// 주석을 같은 길이의 공백으로 지운다(위치 보존).
String _blankComments(String s) =>
    s.replaceAllMapped(RegExp(r'//[^\n]*'), (m) => ' ' * m.group(0)!.length);

String _argOf(String src, int start) {
  var d = 1, i = start;
  while (i < src.length && d > 0) {
    final c = src[i];
    if (c == '(') d++;
    if (c == ')') d--;
    i++;
  }
  return src.substring(start, i - 1);
}

/// lib 소스(경로 → 내용)에서 'TextLayout 문맥에서만' 나오는 문구 집합.
Set<String> wrappedOnlyLiterals(Map<String, String> libSources) {
  final all = <String, Set<String>>{}; // 문구 → 위치
  final wrapped = <String, Set<String>>{};
  libSources.forEach((path, raw) {
    final src = _blankComments(raw);
    for (final m in _lit.allMatches(src)) {
      (all[m.group(1)!] ??= {}).add('$path:${m.start}');
    }
    for (final c in _call.allMatches(src)) {
      final arg = _argOf(src, c.end);
      for (final m in _lit.allMatches(arg)) {
        (wrapped[m.group(1)!] ??= {}).add('$path:${c.end + m.start}');
      }
      final ident = RegExp(r'^\s*([A-Za-z_]\w*)\s*$').firstMatch(arg);
      if (ident != null) {
        final flow = RegExp('\\b${RegExp.escape(ident.group(1)!)}\\s*[:=]\\s*([^;,)]*)');
        for (final f in flow.allMatches(src)) {
          final base = f.start + f.group(0)!.indexOf(f.group(1)!);
          for (final m in _lit.allMatches(f.group(1)!)) {
            (wrapped[m.group(1)!] ??= {}).add('$path:${base + m.start}');
          }
        }
      }
    }
  });
  return {
    for (final e in wrapped.entries)
      if (_word2.hasMatch(e.key) && (all[e.key] ?? {}).difference(e.value).isEmpty) e.key,
  };
}

/// test 소스(경로 → 내용)에서 위반 키 목록('경로|kind|문구' · 줄 번호는 메시지용).
List<({String key, int line})> exactFinderHits(Set<String> wrappedOnly, Map<String, String> testSources) {
  final out = <({String key, int line})>[];
  testSources.forEach((path, src) {
    final lines = src.replaceAll('\r\n', '\n').split('\n');
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith('//')) continue;
      for (final m in _find.allMatches(lines[i])) {
        final kind = m.group(1)!, x = m.group(2)!;
        if (!_word2.hasMatch(x)) continue;
        final hit = kind == 'text' ? wrappedOnly.contains(x) : wrappedOnly.any((w) => w.contains(x));
        if (hit) out.add((key: '$path|$kind|$x', line: i + 1));
      }
    }
  });
  return out;
}

Map<String, String> _read(String root, {String? skip}) {
  final out = <String, String>{};
  for (final f in Directory(root).listSync(recursive: true)) {
    if (f is! File || !f.path.endsWith('.dart')) continue;
    final rel = f.path.replaceAll('\\', '/').replaceFirst(RegExp(r'^.*?(?=(lib|test)/)'), '');
    if (rel == skip) continue;
    out[rel] = f.readAsStringSync();
  }
  return out;
}

void main() {
  group('TLF 탐지기 자체(양성·음성)', () {
    const lib = {
      'lib/a.dart': '''
Widget a(bool b) => Text(TextLayout.keepWords('일정 겹침'));
Widget c(String label) => Text(TextLayout.keepWords(label));
Widget d() => c(label: '선택 안 됨');
Widget e() => const Text('그냥 문구'); // TextLayout 없음
Widget f() => Text(TextLayout.keepWords('두 곳 문구'));
Widget g() => const Text('두 곳 문구'); // 같은 문구가 그대로 그려지는 자리도 있다
// Text(TextLayout.keepWords('주석 속 문구'))
''',
    };
    final only = wrappedOnlyLiterals(lib);

    test('TLF-1 양성 — 인자 리터럴 · 식별자로 넘긴 리터럴 · 정확/부분 finder 를 잡는다', () {
      expect(only, containsAll(['일정 겹침', '선택 안 됨']));
      final hits = exactFinderHits(only, const {
        'test/x_test.dart': "expect(find.text('일정 겹침'), findsOneWidget);\n"
            "expect(find.textContaining('선택 안'), findsNothing);\n"
            // 한 글자 낱말끼리('안 됨')는 사이에 WORD JOINER 가 없어 정확 finder 가 맞는다 — 잡지 않는다.
            "expect(find.textContaining('안 됨'), findsNothing);\n",
      });
      expect(hits.map((h) => h.key), [
        'test/x_test.dart|text|일정 겹침',
        'test/x_test.dart|textContaining|선택 안',
      ]);
    });

    test('TLF-2 음성 — TextLayout 없는 문구 · 다른 자리에서 그대로 그려지는 문구 · 주석 · 보이는 글자 finder 는 잡지 않는다', () {
      expect(only.contains('그냥 문구'), isFalse);
      expect(only.contains('두 곳 문구'), isFalse, reason: '그대로 그리는 자리가 있으면 정확 finder 가 맞을 수 있다');
      expect(only.contains('주석 속 문구'), isFalse);
      final hits = exactFinderHits(only, const {
        'test/y_test.dart': "expect(find.text('그냥 문구'), findsOneWidget);\n"
            "// expect(find.text('일정 겹침'), findsOneWidget);\n"
            "expect(findVisibleText('일정 겹침'), findsOneWidget);\n"
            "expect(find.text('두 곳 문구'), findsOneWidget);\n"
            "expect(find.text('\$name 일정 겹침'), findsNothing);\n",
      });
      expect(hits, isEmpty);
    });
  });

  test('TLF-3 test/ 전수 — TextLayout 문구를 정확 finder 로 찾는 새 코드 0 (이유 붙은 예외만)', () {
    final only = wrappedOnlyLiterals(_read('lib'));
    expect(only.length, greaterThan(100), reason: '탐지 대상이 비면 census 가 빈 단언이 된다');
    final hits = exactFinderHits(only, _read('test', skip: 'test/text_layout_exact_finder_census_test.dart'));
    final allowed = {..._pendingConversion.keys, ..._reviewedPlain.keys};
    final bad = hits.where((h) => !allowed.contains(h.key)).map((h) {
      final p = h.key.split('|');
      return '${p[0]}:${h.line} ${p[1]}(\'${p[2]}\') → findVisibleText${p[1] == 'text' ? '' : 'Containing'}';
    }).toList();
    expect(bad, isEmpty,
        reason: 'TextLayout(U+2060) 문구는 정확 finder 로 늘 0개다 — test/support/visible_text.dart 를 쓴다:\n${bad.join('\n')}');
    // 예외가 실제로 아직 쓰이는지 — 고쳐진 예외는 목록에서 지운다(낡은 예외 0).
    final used = hits.map((h) => h.key).toSet();
    final stale = allowed.where((k) => !used.contains(k)).toList();
    expect(stale, isEmpty, reason: '쓰이지 않는 예외: $stale');
  });
}
