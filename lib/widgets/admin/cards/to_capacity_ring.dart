import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../../../theme/app_colors.dart';

/// 확정(녹색) / 대기(앰버) / 미충원(회색) 3-세그먼트 링 차트.
///
/// [RepaintBoundary]로 감싸 부모 리빌드 시 불필요한 재드로잉 차단.
class TOCapacityRing extends StatelessWidget {
  final int confirmed;
  final int pending;
  final int total;
  final double size;
  final double strokeWidth;

  const TOCapacityRing({
    super.key,
    required this.confirmed,
    required this.pending,
    required this.total,
    this.size = 76,
    this.strokeWidth = 9,
  });

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(size, size),
              painter: _RingPainter(
                confirmed: confirmed,
                pending: pending,
                total: total,
                strokeWidth: strokeWidth,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$confirmed',
                  style: TextStyle(
                    fontSize: size * 0.26,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    color: AppColors.textPrimary,
                  ),
                ),
                Text(
                  '/$total',
                  style: TextStyle(
                    fontSize: size * 0.15,
                    color: AppColors.grey500,
                    height: 1.2,
                  ),
                ),
                if (pending > 0)
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '+$pending',
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppColors.warning,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final int confirmed;
  final int pending;
  final int total;
  final double strokeWidth;

  const _RingPainter({
    required this.confirmed,
    required this.pending,
    required this.total,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    const startAngle = -math.pi / 2; // 12시 방향 기준
    final effectiveTotal = total > 0 ? total : 1;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true;

    // 배경 트랙
    paint.color = AppColors.grey200;
    canvas.drawArc(rect, 0, math.pi * 2, false, paint);

    // 대기 아크 (확정 직후부터 이어짐)
    if (pending > 0) {
      final confirmedSweep = math.pi * 2 * confirmed / effectiveTotal;
      final pendingSweep = math.pi * 2 * pending / effectiveTotal;
      paint.color = AppColors.warning;
      canvas.drawArc(rect, startAngle + confirmedSweep, pendingSweep, false, paint);
    }

    // 확정 아크 (맨 위에 렌더링)
    if (confirmed > 0) {
      final confirmedSweep = math.pi * 2 * confirmed / effectiveTotal;
      paint.color = AppColors.success;
      canvas.drawArc(rect, startAngle, confirmedSweep, false, paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      confirmed != old.confirmed || pending != old.pending || total != old.total;
}
