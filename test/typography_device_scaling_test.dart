// 기기 폭에 따른 폰트 크기 편차 제거 (TYPO-01)
//
// 문제였던 구조:
//   ResponsiveHelper.getScale()  <360 → 0.85 | <400 → 0.90 | ≥400 → 1.00
//   이 스케일이 fontSize에도 곱해져, 400dp 임계값이 실사용 기기 폭 분포
//   (360~412dp) 한가운데를 갈랐다. 같은 앱이 폰에 따라 body 12.6px / 14px로
//   보였고, Samsung '화면 크게/작게'처럼 logical width를 바꾸는 설정만으로도
//   글자 크기가 계단식으로 점프했다.
//
// canonical:
//   fontSize = base logical size × OS TextScaler
//   화면 폭 · devicePixelRatio · screen zoom 파생 스케일은 폰트에 쓰지 않는다.
//   레이아웃 치수(spacing/padding/icon)의 폭 스케일은 그대로 둔다.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_text_styles.dart';
import 'package:ALfit/utils/responsive_helper.dart';

/// 실사용 기기에서 흔한 logical width — 400dp 경계 양쪽을 모두 포함한다.
const _widths = <double>[320, 359, 360, 375, 393, 400, 412, 480, 600];

String _source(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

/// 지정한 logical width에서 [read]를 실행해 결과를 돌려준다.
Future<T> _atWidth<T>(WidgetTester tester, double width,
    T Function(BuildContext) read) async {
  late T out;
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(size: Size(width, 800)),
    child: Builder(builder: (ctx) {
      out = read(ctx);
      return const SizedBox.shrink();
    }),
  ));
  return out;
}

void main() {
  // ── §25 ResponsiveHelper typography ─────────────────────────────
  group('TYPO-0x 폰트는 화면 폭에 영향받지 않는다', () {
    testWidgets('TYPO-01 bodyStyle은 모든 폭에서 14', (tester) async {
      for (final w in _widths) {
        final size =
            (await _atWidth(tester, w, (c) => ResponsiveHelper.bodyStyle(c)))
                .fontSize;
        expect(size, 14, reason: 'width ${w}dp 에서 body가 $size');
      }
    });

    testWidgets('TYPO-02 나머지 텍스트 헬퍼도 폭 불변', (tester) async {
      final expected = <String, double>{
        'title': 18,
        'subtitle': 16,
        'small': 12,
        'tiny': 11,
        'caption': 11,
      };
      for (final w in _widths) {
        final got = await _atWidth(tester, w, (c) => <String, double?>{
              'title': ResponsiveHelper.titleStyle(c).fontSize,
              'subtitle': ResponsiveHelper.subtitleStyle(c).fontSize,
              'small': ResponsiveHelper.smallStyle(c).fontSize,
              'tiny': ResponsiveHelper.tinyStyle(c).fontSize,
              'caption': ResponsiveHelper.captionStyle(c).fontSize,
            });
        for (final e in expected.entries) {
          expect(got[e.key], e.value,
              reason: 'width ${w}dp 에서 ${e.key}=${got[e.key]}');
        }
      }
    });

    testWidgets('TYPO-03 getFontSize는 base를 그대로 돌려준다', (tester) async {
      for (final w in _widths) {
        final v =
            await _atWidth(tester, w, (c) => ResponsiveHelper.getFontSize(c, 17));
        expect(v, 17, reason: 'width ${w}dp 에서 $v');
      }
    });

    testWidgets('TYPO-04 400dp 경계에서 폰트가 점프하지 않는다', (tester) async {
      // 이것이 증상의 핵심이었다 — 393dp와 412dp가 달라 보였다.
      final a = (await _atWidth(tester, 393, (c) => ResponsiveHelper.bodyStyle(c)))
          .fontSize;
      final b = (await _atWidth(tester, 412, (c) => ResponsiveHelper.bodyStyle(c)))
          .fontSize;
      expect(a, b);
    });

    testWidgets('TYPO-05 360dp 경계에서도 점프하지 않는다', (tester) async {
      final a = (await _atWidth(tester, 359, (c) => ResponsiveHelper.smallStyle(c)))
          .fontSize;
      final b = (await _atWidth(tester, 360, (c) => ResponsiveHelper.smallStyle(c)))
          .fontSize;
      expect(a, b);
    });
  });

  // ── 레이아웃 스케일은 보존 ──────────────────────────────────────
  group('TYPO-1x 레이아웃 스케일은 그대로다', () {
    testWidgets('TYPO-10 getScale 계단값 유지', (tester) async {
      expect(await _atWidth(tester, 320, ResponsiveHelper.getScale), 0.85);
      expect(await _atWidth(tester, 359, ResponsiveHelper.getScale), 0.85);
      expect(await _atWidth(tester, 360, ResponsiveHelper.getScale), 0.9);
      expect(await _atWidth(tester, 393, ResponsiveHelper.getScale), 0.9);
      expect(await _atWidth(tester, 400, ResponsiveHelper.getScale), 1.0);
      expect(await _atWidth(tester, 412, ResponsiveHelper.getScale), 1.0);
    });

    testWidgets('TYPO-11 spacing·icon은 계속 폭에 반응한다', (tester) async {
      final narrow = await _atWidth(tester, 360, (c) => <String, double>{
            'spacing': ResponsiveHelper.spacing(c, 16),
            'icon': ResponsiveHelper.iconSize(c, 20),
          });
      final wide = await _atWidth(tester, 412, (c) => <String, double>{
            'spacing': ResponsiveHelper.spacing(c, 16),
            'icon': ResponsiveHelper.iconSize(c, 20),
          });
      expect(narrow['spacing'], lessThan(wide['spacing']!));
      expect(narrow['icon'], lessThan(wide['icon']!));
    });

    test('TYPO-12 spacing/padding/icon 구현 무변경', () {
      final s = _source('lib/utils/responsive_helper.dart');
      expect(s.contains('return baseSpacing * scale;'), true);
      expect(s.contains('return EdgeInsets.all(16 * scale);'), true);
      expect(s.contains('return baseSize * scale;'), true, reason: 'iconSize');
    });
  });

  // ── §27 OS TextScaler ───────────────────────────────────────────
  group('TYPO-2x OS 글꼴 확대는 계속 존중된다', () {
    testWidgets('TYPO-20 TextScaler가 base에 그대로 적용된다', (tester) async {
      for (final scaler in const [1.0, 1.3, 1.5]) {
        late double scaled;
        await tester.pumpWidget(MediaQuery(
          data: MediaQueryData(
            size: const Size(360, 800),
            textScaler: TextScaler.linear(scaler),
          ),
          child: Builder(builder: (ctx) {
            scaled = MediaQuery.textScalerOf(ctx).scale(14);
            return const SizedBox.shrink();
          }),
        ));
        expect(scaled, closeTo(14 * scaler, 0.001),
            reason: 'scaler $scaler 에서 $scaled');
      }
    });

    test('TYPO-21 앱이 TextScaler를 무력화하지 않는다', () {
      // noScaling / linear(1.0) / textScaleFactor 지정이 없어야 한다.
      final hits = <String>[];
      void walk(Directory d) {
        for (final e in d.listSync(recursive: true)) {
          if (e is! File || !e.path.endsWith('.dart')) continue;
          final t = e.readAsStringSync();
          if (t.contains('TextScaler.noScaling') ||
              t.contains('TextScaler.linear(1.0)') ||
              t.contains('textScaleFactor:')) {
            hits.add(e.path);
          }
        }
      }
      walk(Directory('lib'));
      expect(hits, isEmpty, reason: 'OS 글꼴 설정을 무시하는 코드: $hits');
    });
  });

  // ── §31 폭 기반 폰트 스케일 전멸 확인 ──────────────────────────
  group('TYPO-3x 폭 기반 폰트 스케일이 남아 있지 않다', () {
    test('TYPO-30 fontSize에 폭 스케일을 곱하는 코드가 없다', () {
      final re = RegExp(r'fontSize:[^,]*\*\s*(s|scale|_s\(|getScale)\b');
      final hits = <String>[];
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final lines = e.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (re.hasMatch(lines[i])) hits.add('${e.path}:${i + 1}');
        }
      }
      expect(hits, isEmpty, reason: '폭 스케일이 곱해진 fontSize: $hits');
    });

    test('TYPO-31 AppTextStyles가 외부 스케일을 받지 않는다', () {
      final s = _source('lib/theme/app_text_styles.dart');
      expect(s.contains('double s'), false, reason: 's 파라미터 잔존');
      expect(RegExp(r'fontSize: [0-9.]+ \* ').hasMatch(s), false);
    });

    testWidgets('TYPO-32 AppTextStyles도 폭과 무관하다', (tester) async {
      // 정적 메서드라 폭 자체를 받지 않지만, 값이 base 그대로인지 고정한다.
      expect(AppTextStyles.body().fontSize, 15);
      expect(AppTextStyles.caption().fontSize, 12);
      expect(AppTextStyles.jobTitle().fontSize, 17);
    });

    test('TYPO-33 홈 계열 로컬 스케일은 레이아웃 전용으로 남았다', () {
      // _s() / _scale() 자체는 padding·size에 계속 쓰이므로 제거하지 않았다.
      for (final p in const [
        'lib/screens/business_admin/business_admin_home_screen.dart',
        'lib/screens/user/user_home_screen.dart',
      ]) {
        final s = _source(p);
        expect(s.contains('double _s(BuildContext context)'), true,
            reason: '$p 의 레이아웃 스케일이 제거됐다');
        expect(RegExp(r'fontSize: [0-9.]+ \* s\b').hasMatch(s), false,
            reason: '$p 에 폰트 스케일 잔존');
      }
    });
  });

  // ── 범위 불변식 ─────────────────────────────────────────────────
  group('TYPO-4x 이번 범위 밖', () {
    test('TYPO-40 base 폰트 크기를 올리지 않았다', () {
      final s = _source('lib/utils/responsive_helper.dart');
      for (final pair in const [
        ['titleStyle', 18],
        ['subtitleStyle', 16],
        ['bodyStyle', 14],
        ['smallStyle', 12],
        ['tinyStyle', 11],
        ['captionStyle', 11],
      ]) {
        final i = s.indexOf('static TextStyle ${pair[0]}(');
        expect(i, greaterThan(-1));
        expect(s.substring(i, i + 260).contains('fontSize: ${pair[1]},'), true,
            reason: '${pair[0]} base가 바뀌었다');
      }
    });

    test('TYPO-41 fontFamily를 적용하지 않았다', () {
      // NotoSansKR 적용은 secondary issue — 이번 범위가 아니다.
      final theme = _source('lib/theme/role_theme.dart');
      expect(theme.contains('fontFamily'), false);
    });

    test('TYPO-42 FittedBox/AutoSizeText 우회를 추가하지 않았다', () {
      var fitted = 0;
      for (final e in Directory('lib').listSync(recursive: true)) {
        if (e is! File || !e.path.endsWith('.dart')) continue;
        final t = e.readAsStringSync();
        fitted += 'FittedBox'.allMatches(t).length;
        expect(t.contains('AutoSizeText'), false, reason: '${e.path}');
      }
      expect(fitted, 6, reason: 'FittedBox 사용처가 늘었다 (감사 시점 6건)');
    });

    test('TYPO-43 기기 모델 분기를 추가하지 않았다', () {
      final helper = _source('lib/utils/responsive_helper.dart');
      expect(helper.contains('devicePixelRatio'), false);
    });
  });
}
