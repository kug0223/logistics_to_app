// [CP01] ALfit 머리 글자 로고 — 고정 그림(artwork).
//
// 원형: Montserrat Italic(variable, wght=700)의 단어 'ALfit' 전체를 HarfBuzz 로 shaping(커닝 포함)해
//   윤곽을 Path 로 옮긴 것이다. 추가 기울임·자간·덧칠은 없다.
// 생성: records/work/cp01-concept-logo-surface/gen/(gen_wordmark.py·recipe.json, 원 TTF SHA 51607f31…).
//   아래 생성 데이터는 손으로 고치지 않는다 — 바꾸려면 다시 생성한다.
// 라이선스: SIL OFL 1.1 글꼴(Copyright 2011 The Montserrat Project Authors)에서 만든 고정 단어 그림이다.
//   글꼴 소프트웨어(TTF·재사용 glyph 데이터)를 앱에 번들하지 않는다(OFL FAQ 1.1–1.1.2, 1.13).
// 크기: 잉크 높이 24dp 고정 — 브랜드 그림이라 글자 배율을 따르지 않는다. 이름·날짜 등 글자는 실제 배율을 받는다.
// 정본: records/reports/DU_concept_precise_spec_audit_2026-11-11.md §3.
import 'package:flutter/widgets.dart';

import '../../theme/app_colors.dart';

class AlfitWordmark extends StatelessWidget {
  const AlfitWordmark({super.key});

  /// 잉크(그려진 글자) 높이.
  static const double inkHeight = 24;

  /// 자리(slot) 최소 크기 — 위아래 2dp, 왼쪽 정렬.
  static const double slotMinWidth = 84;
  static const double slotHeight = 28;

  /// 원비례를 지킨 잉크 폭.
  static double get inkWidth => inkHeight * _kW / _kH;

  /// 실제 자리 폭.
  static double get slotWidth => inkWidth > slotMinWidth ? inkWidth : slotMinWidth;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'ALfit',
      image: true,
      child: ExcludeSemantics(
        child: SizedBox(
          width: slotWidth,
          height: slotHeight,
          child: Align(
            alignment: Alignment.centerLeft,
            child: CustomPaint(
              size: Size(inkWidth, inkHeight),
              painter: const _AlfitWordmarkPainter(),
            ),
          ),
        ),
      ),
    );
  }
}

class _AlfitWordmarkPainter extends CustomPainter {
  const _AlfitWordmarkPainter();

  static final Path _unitPath = _buildPath();

  static Path _buildPath() {
    final p = Path();
    var i = 0;
    while (i < _kOps.length) {
      switch (_kOps[i].toInt()) {
        case 0:
          p.moveTo(_kOps[i + 1], _kOps[i + 2]);
          i += 3;
        case 1:
          p.lineTo(_kOps[i + 1], _kOps[i + 2]);
          i += 3;
        case 2:
          p.quadraticBezierTo(_kOps[i + 1], _kOps[i + 2], _kOps[i + 3], _kOps[i + 4]);
          i += 5;
        case 3:
          p.cubicTo(_kOps[i + 1], _kOps[i + 2], _kOps[i + 3], _kOps[i + 4], _kOps[i + 5], _kOps[i + 6]);
          i += 7;
        default:
          p.close();
          i += 1;
      }
    }
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.height / _kH;
    canvas.save();
    canvas.scale(k, k);
    // [DU306 L1] 로고 전용 잉크색(brandInk #1A42E8). 크기(잉크 24·원비례)·slot·Semantics 는 그대로다.
    canvas.drawPath(_unitPath, Paint()..color = AppColors.brandInk);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AlfitWordmarkPainter oldDelegate) => false;
}

// ── 생성 데이터 (gen_wordmark.py 출력 — 손편집 금지) ──
const double _kW = 2558.55;
const double _kH = 794.8;

// op: 0 moveTo(x,y) · 1 lineTo(x,y) · 2 quadTo(x1,y1,x2,y2) · 3 cubicTo(…6) · 4 close. 단위=font units, y 아래로.
const List<double> _kOps = [
  0, 0, 787.21, 1, 452.64, 87.21, 1, 612.83, 87.21, 1, 784.87, 787.21, 1, 622.88, 787.21, 1,
  486.95, 167.25, 1, 551.19, 167.25, 1, 172.97, 787.21, 4, 0, 186.69, 637.45, 1, 253.54, 514.52,
  1, 614.16, 514.52, 1, 633.52, 637.45, 4, 0, 858.29, 787.21, 1, 998.29, 87.21, 1, 1160.68,
  87.21, 1, 1047.42, 654.9, 1, 1397.81, 654.9, 1, 1371.07, 787.21, 4, 0, 1470.64, 787.21, 1,
  1582.07, 230.66, 2, 1600.26, 142.31, 1658.9, 89.97, 2, 1717.54, 37.62, 1816.02, 37.62, 2,
  1852.8, 37.62, 1884.98, 45.03, 2, 1917.16, 52.43, 1939.93, 67.64, 1, 1878.67, 178.78, 2,
  1852.26, 159.75, 1816.81, 159.75, 2, 1781.37, 159.75, 1761.43, 179.57, 2, 1741.5, 199.4,
  1732.09, 240.85, 1, 1721.26, 291.37, 1, 1713.28, 354.42, 1, 1626.64, 787.21, 4, 0, 1468.05,
  380.9, 1, 1492, 261.16, 1, 1865.18, 261.16, 1, 1841.23, 380.9, 4, 0, 1842.67, 787.21, 1,
  1949.86, 249.26, 1, 2105.47, 249.26, 1, 1998.28, 787.21, 4, 0, 2054.28, 174.49, 2, 2012.78,
  174.49, 1987.93, 150.73, 2, 1963.09, 126.97, 1963.09, 93.43, 2, 1963.09, 53.71, 1991.42, 26.85,
  2, 2019.76, 0, 2066.05, 0, 2, 2107.55, 0, 2132.7, 22.36, 2, 2157.85, 44.73, 2157.85, 78.26, 2,
  2157.85, 120.99, 2129.51, 147.74, 2, 2101.18, 174.49, 2054.28, 174.49, 4, 0, 2361.83, 794.8, 2,
  2304.5, 794.8, 2263.35, 771.51, 2, 2222.19, 748.23, 2204.6, 703.76, 2, 2187.02, 659.29,
  2199.21, 597.95, 1, 2292.62, 129.88, 1, 2448.63, 129.88, 1, 2355.21, 596.95, 2, 2349.01,
  631.59, 2362.12, 651.53, 2, 2375.23, 671.46, 2409.69, 671.46, 2, 2426.11, 671.46, 2442.43,
  666.46, 2, 2458.76, 661.45, 2473.57, 652.43, 1, 2496.55, 762.8, 2, 2467.37, 781, 2432.18,
  787.9, 2, 2397, 794.8, 2361.83, 794.8, 4, 0, 2161.43, 369.01, 1, 2185.38, 249.26, 1, 2558.55,
  249.26, 1, 2534.61, 369.01, 4,
];
