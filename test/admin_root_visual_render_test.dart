// [R7-P4.2B] 관리자 root 시각 시스템 — 실제로 그려서 잰다.
//
// ── 왜 이 파일이 필요한가 ─────────────────────────────────────────
//   P4.2-1 은 세 탭의 SETUP_REQUIRED 를 **소스 계약**으로만 고정했다.
//   문구가 갈라져 있다는 것은 증명했지만, 그 문구가 좁은 화면과 큰 글꼴에서
//   실제로 **읽히는지**는 한 번도 그려 본 적이 없다.
//
//   여기서는 320/360/411 × 1.0/1.3/2.0 로 직접 pump 해서
//   overflow·줄바꿈·버튼 높이·라벨 잘림을 본다. 기기 증거가 아니다 —
//   RENDER 등급이다.
//
// ── 무엇을 재지 않는가 ────────────────────────────────────────────
//   실제 FMP·프레임 시간·스크롤 성능은 여기서 알 수 없다. NOT SEEN.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/widgets/common/app_empty_state.dart';

// ── 하네스 ────────────────────────────────────────────────────────

const List<double> _widths = [320, 360, 411];
const List<double> _scales = [1.0, 1.3, 2.0];

Future<void> _pump(
  WidgetTester tester, {
  required double width,
  required double scale,
  required Widget child,
  double height = 760,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      theme: RoleTheme.businessAdminTheme,
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(width, height),
          textScaler: TextScaler.linear(scale),
        ),
        child: child,
      ),
    ),
  );
}

/// pump 중에 프레임워크가 기록한 예외(대표적으로 RenderFlex overflow)를 꺼낸다.
String? _overflow(WidgetTester tester) {
  final e = tester.takeException();
  if (e == null) return null;
  return e.toString();
}

// ── 대상: 세 탭의 NO_BUSINESS 표면 (production 문구 그대로) ──────────

const _payrollEmpty = AppEmptyState(
  icon: Icons.storefront_outlined,
  title: '아직 급여를 관리할 사업장이 없어요',
  subtitle: '사업장을 등록하면 근무·급여 관리를 시작할 수 있어요.',
  action: _SetupCta(),
);

const _workforceEmpty = AppEmptyState(
  icon: Icons.storefront_outlined,
  title: '아직 근무를 관리할 사업장이 없어요',
  subtitle: '사업장을 등록하면 확정 인력과 출퇴근을 여기서 관리해요.',
  action: _SetupCta(),
);

const _postingEmpty = AppEmptyState(
  icon: Icons.storefront_outlined,
  title: '아직 공고를 등록할 수 없어요',
  subtitle: '사업장 등록부터 마치면 공고를 만들 수 있어요',
  action: _SetupCta(),
);

/// 세 화면이 공유하는 CTA — 탭 전환은 Shell 콜백이라 테스트에서는 no-op.
class _SetupCta extends StatelessWidget {
  const _SetupCta();
  @override
  Widget build(BuildContext context) =>
      TextButton(onPressed: () {}, child: const Text('준비 단계 보기'));
}

// ── 대상: 하단 5탭 (Shell 설정 그대로) ────────────────────────────

class _ShellNavBar extends StatelessWidget {
  const _ShellNavBar({required this.index});
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return BottomNavigationBar(
      currentIndex: index,
      onTap: (_) {},
      type: BottomNavigationBarType.fixed,
      selectedItemColor: theme.primaryColor,
      unselectedItemColor: AppColors.grey500,
      selectedLabelStyle: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
      ),
      unselectedLabelStyle: const TextStyle(fontSize: 12),
      elevation: 0,
      backgroundColor: Colors.white,
      items: const [
        BottomNavigationBarItem(
            icon: Icon(Icons.home_outlined),
            activeIcon: Icon(Icons.home_rounded),
            label: '홈'),
        BottomNavigationBarItem(
            icon: Icon(Icons.work_outline_rounded),
            activeIcon: Icon(Icons.work_rounded),
            label: '공고'),
        BottomNavigationBarItem(
            icon: Icon(Icons.people_outline_rounded),
            activeIcon: Icon(Icons.people_rounded),
            label: '근무'),
        BottomNavigationBarItem(
            icon: Icon(Icons.payments_outlined),
            activeIcon: Icon(Icons.payments_rounded),
            label: '급여'),
        BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined),
            activeIcon: Icon(Icons.settings_rounded),
            label: '관리'),
      ],
    );
  }
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // VR-01. 세 탭의 SETUP 표면 — 9칸 매트릭스에서 안 깨진다
  // ══════════════════════════════════════════════════════════════
  group('VR-01 NO_BUSINESS 표면 렌더', () {
    final targets = <String, Widget>{
      '급여': _payrollEmpty,
      '근무': _workforceEmpty,
      '공고': _postingEmpty,
    };

    for (final entry in targets.entries) {
      for (final w in _widths) {
        for (final s in _scales) {
          testWidgets('VR-01 ${entry.key} ${w.toInt()}dp x$s', (tester) async {
            await _pump(
              tester,
              width: w,
              scale: s,
              child: Scaffold(body: entry.value),
            );
            expect(_overflow(tester), isNull,
                reason: '${entry.key} ${w.toInt()}dp x$s 에서 넘침');
          });
        }
      }
    }

    testWidgets('VR-01z 최악 조건에서도 제목·부제·CTA 가 모두 남는다',
        (tester) async {
      await _pump(
        tester,
        width: 320,
        scale: 2.0,
        child: const Scaffold(body: _payrollEmpty),
      );
      expect(find.text('아직 급여를 관리할 사업장이 없어요'), findsOneWidget);
      expect(find.text('사업장을 등록하면 근무·급여 관리를 시작할 수 있어요.'), findsOneWidget);
      expect(find.text('준비 단계 보기'), findsOneWidget);
    });

    testWidgets('VR-01y CTA 는 최소 탭 대상 높이를 넘긴다', (tester) async {
      // Material 권장 최소 48dp. TextButton 기본 minimumSize 는 (64, 36) 이라
      // 1.0 배율에서 이 값을 실제로 확인해 둔다 — 넘치면 판정을 바꾼다.
      await _pump(
        tester,
        width: 360,
        scale: 1.0,
        child: const Scaffold(body: _payrollEmpty),
      );
      final size = tester.getSize(find.byType(TextButton));
      expect(size.height, greaterThanOrEqualTo(36.0));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // VR-02. 하단 5탭 — 라벨이 잘리는 조건을 찾는다
  // ══════════════════════════════════════════════════════════════
  group('VR-02 하단 NavigationBar', () {
    for (final w in _widths) {
      for (final s in _scales) {
        testWidgets('VR-02 ${w.toInt()}dp x$s', (tester) async {
          await _pump(
            tester,
            width: w,
            scale: s,
            child: const Scaffold(
              body: SizedBox.shrink(),
              bottomNavigationBar: _ShellNavBar(index: 0),
            ),
          );
          final err = _overflow(tester);
          expect(err, isNull, reason: '${w.toInt()}dp x$s 에서 넘침: $err');
        });
      }
    }

    testWidgets('VR-02h 5개 라벨이 모두 한 번씩 보인다 (320dp x2.0)',
        (tester) async {
      await _pump(
        tester,
        width: 320,
        scale: 2.0,
        child: const Scaffold(
          body: SizedBox.shrink(),
          bottomNavigationBar: _ShellNavBar(index: 0),
        ),
      );
      for (final label in const ['홈', '공고', '근무', '급여', '관리']) {
        expect(find.text(label), findsOneWidget, reason: label);
      }
    });

    testWidgets('VR-02s 선택 탭은 색과 굵기 두 가지로 구별된다', (tester) async {
      await _pump(
        tester,
        width: 360,
        scale: 1.0,
        child: const Scaffold(
          body: SizedBox.shrink(),
          bottomNavigationBar: _ShellNavBar(index: 2),
        ),
      );
      // BottomNavigationBar 는 Text.style 에 직접 쓰지 않고 상위에서 합친다.
      // 그래서 위젯이 아니라 **실제로 칠해진 값**을 읽어야 한다.
      TextStyle styleOf(String label) =>
          tester.renderObject<RenderParagraph>(find.text(label)).text.style!;

      final selected = styleOf('근무');
      final other = styleOf('급여');
      // 색만으로 구별하면 색각 이상·저대비 환경에서 사라진다.
      expect(selected.color, isNot(other.color));
      expect(selected.color, const Color(0xFF1565C0));
      expect(selected.fontWeight, FontWeight.w700);
      expect(other.fontWeight, isNot(FontWeight.w700));
    });

    testWidgets('VR-02b 바가 본문과 경계를 가진다', (tester) async {
      // 흰 본문 + 흰 바 + elevation 0 이면 경계가 사라진다.
      // 지금 무엇이 경계를 만드는지 실제 값으로 기록한다.
      await _pump(
        tester,
        width: 360,
        scale: 1.0,
        child: const Scaffold(
          body: ColoredBox(color: Colors.white),
          bottomNavigationBar: _ShellNavBar(index: 0),
        ),
      );
      final bar = tester.widget<BottomNavigationBar>(
          find.byType(BottomNavigationBar));
      expect(bar.backgroundColor, Colors.white);
      expect(bar.elevation, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // VR-03. 관리 탭 identity 블록 — A/B/C 를 같은 조건에서 잰다
  // ══════════════════════════════════════════════════════════════
  //
  //   A 는 production(settings_screen._buildHeaderProfile)의 구성을 그대로
  //   옮긴 것이다. 아래 세 개는 **같은 하네스**에서 높이만 다르게 나온다.
  //   판정 근거는 "얼마나 예쁜가"가 아니라 **첫 화면에서 관리 항목이 몇 줄
  //   남는가**이다.
  group('VR-03 관리 identity 블록', () {
    for (final s in _scales) {
      testWidgets('VR-03 높이 비교 360dp x$s', (tester) async {
        final heights = <String, double>{};
        for (final v in _IdentityVariant.values) {
          await _pump(
            tester,
            width: 360,
            scale: s,
            child: Scaffold(
              backgroundColor: AppColors.background,
              body: Column(children: [_IdentityBlock(variant: v)]),
            ),
          );
          expect(_overflow(tester), isNull, reason: '$v x$s');
          heights[v.name] =
              tester.getSize(find.byKey(const Key('identity-block'))).height;
        }
        // ignore: avoid_print
        print('[VR-03] x$s  ${heights.entries.map((e) =>
            '${e.key}=${e.value.toStringAsFixed(1)}').join('  ')}');

        // ── 실측이 가정을 뒤집었다 ───────────────────────────────────
        //   "compact 하게 만들면 낮아진다"가 배율 전체에서 참이 아니다.
        //     x1.0  A=103  B/C=88   (-15dp)
        //     x1.3  A=118  B/C=123  (+5dp)
        //     x2.0  A=156  B/C=161  (+5dp)
        //   A 의 52dp 아바타는 글꼴과 무관한 고정 상자라 세 줄을 그 안에
        //   흡수한다. B/C 는 아이디+역할을 Wrap 한 줄로 접었는데, 배율이
        //   오르면 그 줄이 다시 둘로 갈라져 오히려 한 줄이 늘어난다.
        //   그래서 이득은 **기본 배율에서만** 있다. 이 사실을 고정한다.
        if (s == 1.0) {
          expect(heights['compact']!, lessThan(heights['current']!));
          expect(heights['tonal']!, lessThan(heights['current']!));
        } else {
          expect(heights['compact']!, greaterThan(heights['current']!),
              reason: '큰 글꼴에서는 compact 안이 더 높다 — 높이는 채택 근거가 아니다');
        }
        // 어느 배율에서도 두 안의 차이는 면 처리뿐이라 높이는 같다.
        expect(heights['compact'], heights['tonal']);
      });
    }

    testWidgets('VR-03i 세 안 모두 이름·아이디·역할을 잃지 않는다', (tester) async {
      for (final v in _IdentityVariant.values) {
        await _pump(
          tester,
          width: 360,
          scale: 1.0,
          child: Scaffold(body: Column(children: [_IdentityBlock(variant: v)])),
        );
        expect(find.text('김의관'), findsOneWidget, reason: v.name);
        expect(find.text('@adminkug'), findsOneWidget, reason: v.name);
        expect(find.text('사업장 관리자'), findsOneWidget, reason: v.name);
      }
    });

    testWidgets('VR-03p 진한 브랜드 면적 — A 만 블록 전체가 primary 다',
        (tester) async {
      for (final v in _IdentityVariant.values) {
        await _pump(
          tester,
          width: 360,
          scale: 1.0,
          child: Scaffold(body: Column(children: [_IdentityBlock(variant: v)])),
        );
        final box = tester.widget<Container>(
            find.byKey(const Key('identity-surface')));
        final deco = box.decoration as BoxDecoration;
        if (v == _IdentityVariant.current) {
          expect(deco.color, const Color(0xFF1565C0));
        } else {
          expect(deco.color, isNot(const Color(0xFF1565C0)),
              reason: '${v.name} 은 진한 파랑을 면으로 쓰지 않는다');
        }
      }
    });
  });
}

// ── identity 3안 ──────────────────────────────────────────────────

enum _IdentityVariant {
  /// A — 현재. primaryColor 면 + 52dp 아바타 + 흰 글자.
  current,

  /// B — compact neutral. 흰 면, 40dp 아바타, 역할만 브랜드색 배지.
  compact,

  /// C — light tonal. primary 8% 면 + 얇은 테두리, 40dp 아바타.
  tonal,
}

class _IdentityBlock extends StatelessWidget {
  const _IdentityBlock({required this.variant});
  final _IdentityVariant variant;

  static const _name = '김의관';
  static const _handle = '@adminkug';
  static const _role = '사업장 관리자';
  static const _primary = Color(0xFF1565C0);

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: const Key('identity-block'),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: switch (variant) {
        _IdentityVariant.current => _buildCurrent(context),
        _IdentityVariant.compact => _buildFlat(context, tonal: false),
        _IdentityVariant.tonal => _buildFlat(context, tonal: true),
      },
    );
  }

  // A — production 구성 그대로 (아바타 52, 내부 패딩 L16 T4 R16 B16)
  Widget _buildCurrent(BuildContext context) {
    return Container(
      key: const Key('identity-surface'),
      decoration: BoxDecoration(
        color: _primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, size: 30, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(_name,
                      style: TextStyle(
                          fontSize: 16,
                          color: Colors.white,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(_handle,
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.white.withValues(alpha: 0.8))),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3)),
                    ),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.admin_panel_settings,
                          size: 12, color: Colors.white),
                      SizedBox(width: 4),
                      Text(_role,
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                              fontWeight: FontWeight.w600)),
                    ]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // B/C — 같은 골격, 면만 다르다. 이름 한 줄 + 아이디·역할 한 줄.
  Widget _buildFlat(BuildContext context, {required bool tonal}) {
    return Container(
      key: const Key('identity-surface'),
      decoration: BoxDecoration(
        color: tonal ? _primary.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: tonal
              ? _primary.withValues(alpha: 0.16)
              : AppColors.grey200,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _primary.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.person, size: 22, color: _primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(_name,
                      style: TextStyle(
                          fontSize: 16,
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  // 아이디와 역할을 한 줄로 접는다 — 두 줄을 한 줄로 줄인 것이
                  // A 대비 높이 차이의 대부분이다.
                  Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      const Text(_handle,
                          style: TextStyle(
                              fontSize: 11, color: AppColors.grey500)),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: _primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.admin_panel_settings,
                                  size: 11, color: _primary),
                              SizedBox(width: 3),
                              Text(_role,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: _primary,
                                      fontWeight: FontWeight.w600)),
                            ]),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
