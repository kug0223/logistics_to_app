import 'dart:async';

import 'package:flutter/widgets.dart';

/// [.20 PERCEIVED-PERFORMANCE] 화면에 가까워지기 전에는 [child] 를 만들지 않는다.
///
///   공고 상세의 지도(WebView)는 화면 맨 아래에 있는데 진입하자마자 만들어졌다.
///   앱이 켜진 뒤 첫 WebView 생성은 UI 스레드를 1~2초 멈춘다(LOCAL 에뮬레이터 실측) —
///   지도를 보지도 않을 사람이 상세에 들어갈 때마다 그 멈춤을 겪었다.
///
///   [placeholder] 를 먼저 그리고 다음 둘 중 하나가 되면 [child] 로 바꾼다(한 번 만들면 유지).
///   · 스크롤하다가 자기 위치가 화면 아래 끝에서 [lead] 이내로 들어온다.
///   · 진입 뒤 [settle] 이 지나 화면이 자리 잡았을 때 **실제로 화면 안**에 있다(짧은 페이지).
///     진입 직후 첫 프레임에서 판정하지 않는 이유: 위쪽 영역이 아직 비어 있어
///     맨 아래 지도가 잠깐 화면 안으로 보였다(그 판정으로 다시 진입 즉시 생성됐다 — 실측).
class DeferUntilOnScreen extends StatefulWidget {
  const DeferUntilOnScreen({
    super.key,
    required this.child,
    required this.placeholder,
    this.lead = 200,
    this.settle = const Duration(milliseconds: 1200),
  });

  final Widget child;
  final Widget placeholder;

  /// 스크롤로 다가올 때 화면 아래 끝보다 이만큼(논리 픽셀) 먼저 만든다.
  final double lead;

  /// 진입 뒤 화면 안 여부를 처음 판정하기까지 기다리는 시간.
  final Duration settle;

  @override
  State<DeferUntilOnScreen> createState() => _DeferUntilOnScreenState();
}

class _DeferUntilOnScreenState extends State<DeferUntilOnScreen> {
  bool _shown = false;
  ScrollPosition? _position;
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    _settleTimer = Timer(widget.settle, () => _check(lead: 0));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shown) return;
    final next = Scrollable.maybeOf(context)?.position;
    if (!identical(next, _position)) {
      _position?.removeListener(_onScroll);
      _position = next;
      _position?.addListener(_onScroll);
    }
  }

  void _onScroll() => _check(lead: widget.lead);

  void _check({required double lead}) {
    if (_shown || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final top = box.localToGlobal(Offset.zero).dy;
    if (top <= MediaQuery.sizeOf(context).height + lead) {
      _settleTimer?.cancel();
      _position?.removeListener(_onScroll);
      _position = null;
      setState(() => _shown = true);
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _position?.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _shown ? widget.child : widget.placeholder;
}
