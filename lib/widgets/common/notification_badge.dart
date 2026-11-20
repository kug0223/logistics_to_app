import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../utils/responsive_helper.dart';

/// 알림 아이콘에 읽지 않은 개수 뱃지 표시
class NotificationBadge extends StatelessWidget {
  final Widget child;
  final bool showZero;

  /// [DU306 L2] 배지 위 끝 위치(버튼 위 기준). 기본 −4(기존 그대로). 머리 위 여백이 0 인 두 홈만 0 을 넘겨
  ///   배지가 SafeArea·머리 시작 위로 돌출하지 않게 한다. 오른쪽(−4)·글자 배율·폭 증가·색·의미·receiver 는 그대로다.
  final double badgeTop;

  const NotificationBadge({
    super.key,
    required this.child,
    this.showZero = false,
    this.badgeTop = -4,
  });

  @override
  Widget build(BuildContext context) {
    // [PERF-2026-07-16] 값 몇 개만 필요 → Selector로 rebuild 범위 축소
    // [.66] 미읽음 수는 **불러온 범위**(최근 30건 + 더 보기) 안에서 센다. 더 오래된 알림이 남아 있으면
    //   (hasMore) 그 수는 전체가 아니라 최소값이다 — 'N+'·'N건 이상'으로 말한다(31건인데 '25'로 보였다).
    //   목록을 못 불러왔으면 0 으로 보이지 않게 '!' 로 알린다. 새 집계 조회는 만들지 않는다.
    return Selector<NotificationProvider, (int, bool, bool)>(
      selector: (_, p) => (p.unreadCount, p.hasMore, p.hasError),
      builder: (context, s, _) {
        final (count, partial, failed) = s;
        if (!failed && count == 0 && !showZero) {
          return child;
        }

        final countText = failed
            ? '!'
            : count > 99
                ? '99+'
                : partial
                    ? '$count+'
                    : '$count';
        final semanticValue = failed
            ? '알림을 불러오지 못했습니다'
            : count > 99 || partial
                ? '읽지 않은 알림 ${count > 99 ? 99 : count}건 이상'
                : '읽지 않은 알림 $count건';
        final style = TextStyle(
          color: Colors.white,
          fontSize: ResponsiveHelper.tinyStyle(context).fontSize,
          fontWeight: FontWeight.bold,
        );
        final scaler = MediaQuery.textScalerOf(context);
        final pad = ResponsiveHelper.spacing(context, 4);
        final minSide = ResponsiveHelper.spacing(context, 18);

        // [NOTIFICATION-BADGE.33] 배지는 사용자 글자 배율을 그대로 따른다(.32 의 1.4 상한 철회).
        //   대신 배지가 1.0 보다 커진 만큼 **버튼 오른쪽에 여유 폭**을 둔다. 배지는 예전 자리(오른쪽·위 −4)에
        //   붙어 있으므로 왼쪽 끝이 1.0 때와 같고, 커진 만큼은 새 여유 폭 쪽으로 자란다 — 종 아이콘 위로
        //   덮지 않는다. 위로는 예전 −4 그대로다(.32 기기: 더 올리면 AppBar 툴바 경계에서 잘림).
        //   배율 1.0 기준 폭은 TextPainter 기본(배율 없음)으로 잰다 — 측정에만 쓰고 그리지는 않는다.
        // [.66] 기준을 '그려지는 배지 폭'으로 바꾸고, 1.0 의 한 글자 배지 폭에 맞춘다 — 'N+'·'99+' 처럼
        //   글자가 늘어난 만큼도 오른쪽 여유 폭으로 자란다(392·2.0 에서 '25+' 가 종 아이콘을 다 덮었다).
        double widthOf(TextScaler? s, String text) {
          final tp = s == null
              ? TextPainter(
                  text: TextSpan(text: text, style: style),
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                )
              : TextPainter(
                  text: TextSpan(text: text, style: style),
                  textScaler: s,
                  textDirection: TextDirection.ltr,
                  maxLines: 1,
                );
          tp.layout();
          final w = tp.width + pad * 2;
          tp.dispose();
          return w < minSide ? minSide : w;
        }

        final growth = widthOf(scaler, countText) - widthOf(null, countText.characters.first);
        final extra = growth > 0 ? growth : 0.0;

        // 화면 읽기에는 버튼에 '읽지 않은 알림 N건'을 값으로 한 번만 전한다(배지 숫자는 따로 읽지 않는다).
        //   버튼 이름(tooltip '알림' 등)은 호출부 것을 그대로 둔다.
        return Semantics(
          value: semanticValue,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Padding(
                padding: EdgeInsets.only(right: extra),
                child: child,
              ),
              Positioned(
                right: -4,
                top: badgeTop,
                // 배지는 장식이다 — 탭은 아래 버튼으로 그대로 간다.
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: Container(
                      padding: EdgeInsets.all(pad),
                      decoration: BoxDecoration(
                        color: failed ? AppColors.warning : AppColors.error,
                        // 'N+' 는 원 안에 들어가지 않는다 — 넓어지면 둥근 사각형으로 늘린다.
                        borderRadius: BorderRadius.circular(minSide),
                      ),
                      constraints: BoxConstraints(
                        minWidth: minSide,
                        minHeight: minSide,
                      ),
                      child: Center(
                        child: Text(countText, style: style),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
