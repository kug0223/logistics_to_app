import 'package:flutter/material.dart';

/// [L48 · impl_28] 목록을 유지한 채 다시 읽는 동안의 본문 — 잠금 + 위쪽 얇은 진행 표시.
///
///   [AbsorbPointer] 는 **항상** 같은 자리에 둔다(잠글 때만 끼우면 하위 트리가 새로 만들어져 스크롤 위치를 잃는다).
///   잠금 중에는 탭·스크롤 입력이 아래 목록의 버튼(저장·삭제·상태 변경)에 닿지 않는다.
class KeepContentBody extends StatelessWidget {
  const KeepContentBody({super.key, required this.refreshing, required this.child});

  /// true = 다시 읽는 중(잠금 · 진행 표시).
  final bool refreshing;
  final Widget child;

  static const Key progressKey = ValueKey('keep-content-refresh-progress');

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: AbsorbPointer(absorbing: refreshing, child: child)),
        if (refreshing)
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(key: progressKey, minHeight: 2),
          ),
      ],
    );
  }
}
