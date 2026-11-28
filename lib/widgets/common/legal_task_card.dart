// lib/widgets/common/legal_task_card.dart
//
// [R7-LEGAL.1B.1] 재동의는 **알림이 아니라 할 일**이다.
//
//   알림은 읽으면 사라지고 지우면 없어진다. 약관 동의는 그래선 안 된다 —
//   `RECONSENT_REQUIRED` 가 살아 있는 동안 홈에 남아 있어야 하고, 앱을
//   다시 켜도 남아 있어야 한다. 그래서 이 카드는 서버 판정을 매번 다시
//   묻고, 상태가 풀릴 때까지 사라지지 않는다.
//
//   역할을 가리지 않는다. 약관 동의는 **개인 계정의 법적 상태**라
//   지원자·사업장관리자·하위관리자 모두에게 같은 뜻이다. 사업장 소유자만
//   할 수 있는 설정(사업자등록증·인감)과 섞지 않는다.
//
//   보여 주지 않는 경우
//     · 조회 중      — 아직 아무 말도 하지 않는다
//     · 조회 실패    — 사용자가 할 수 있는 일이 없다. "미동의" 로 그리지 않는다
//     · 선택만 미응답 — 선택은 선택이다. 할 일로 만들면 사실상 강요가 된다

import 'package:flutter/material.dart';

import '../../models/core/legal_readiness.dart';
import '../../screens/legal/legal_consent_reads.dart';
import '../../screens/legal/legal_consent_screen.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';

class LegalTaskCard extends StatefulWidget {
  const LegalTaskCard({super.key, this.loadReadiness, this.scale = 1.0, this.onReadiness});

  /// 테스트에서 갈아끼우는 경계. 운영에서는 null → callable.
  final Future<LegalReadiness> Function()? loadReadiness;
  final double scale;

  /// [PERF-P1 · 판정289 §4] 조회가 끝날 때마다(성공·error) 부모에게 알린다 — 근로자 홈의 첫 표시 조정이
  ///   이 출처의 terminal 여부를 안다. 표시·판정·숨김 규칙은 바꾸지 않는다(error 는 여전히 숨김 · R7-LEGAL).
  ///   null(관리자 홈 등)이면 아무 일도 없다.
  final ValueChanged<LegalReadiness>? onReadiness;

  @override
  State<LegalTaskCard> createState() => _LegalTaskCardState();
}

class _LegalTaskCardState extends State<LegalTaskCard> with WidgetsBindingObserver {
  late final Future<LegalReadiness> Function() _load =
      widget.loadReadiness ?? LegalConsentReads.of().readiness;

  LegalReadiness _readiness = LegalReadiness.loading;

  /// [.34-A1] 큰 글자에서 접어 둔 설명을 펼쳤는가(화면 안 '설명 보기').
  bool _bodyOpen = false;

  /// [.55] 겹친 읽기 중 늦게 온 결과를 버린다.
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    LegalReadinessSignal.changed.addListener(_refresh);
    _refresh();
  }

  @override
  void dispose() {
    LegalReadinessSignal.changed.removeListener(_refresh);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    final seq = ++_seq;
    try {
      final r = await _load();
      if (mounted && seq == _seq) {
        setState(() => _readiness = r);
        widget.onReadiness?.call(r);
      }
    } catch (e) {
      debugPrint('⚠️ 약관 상태 조회 실패: $e');
      // 모르는 것을 "동의하지 않았다" 로 바꾸지 않는다 — 카드를 숨길 뿐이다.
      if (mounted) {
        setState(() => _readiness = LegalReadiness.error);
        widget.onReadiness?.call(LegalReadiness.error);
      }
    }
  }

  Future<void> _open() async {
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const LegalConsentScreen()),
    );
    if (!mounted) return;
    // 돌아오면 canonical 상태를 다시 묻는다 — 화면이 스스로 지우지 않는다.
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (!_readiness.needsAttention) return const SizedBox.shrink();
    final s = widget.scale;

    // 두 사건을 같은 문장으로 말하지 않는다.
    final isChanged =
        _readiness.status == LegalReadinessStatus.reconsentRequired;
    final title = isChanged ? '이용약관이 변경되었습니다' : '약관 동의 정보 확인이 필요해요';
    final body = isChanged
        ? '변경된 내용을 확인하고 동의해 주세요.'
        : '이전 동의 기록으로는 내용을 확인할 수 없어요.';

    // [SCALE-BALANCE.34] 큰 글자에서 이 카드가 화면 ¼ 을 차지했다(제목 2줄 + 설명 2줄, 관리자·근로자 홈 기기).
    //   제목만으로 이미 두 줄이 되는 폭·배율이면 설명을 접어 두고 카드 안 '설명 보기' 로 그 자리에서 펼친다
    //   (.34-A1: 화면 읽기를 쓰지 않는 사용자도 설명을 볼 수 있어야 한다). 카드를 누르면 예전처럼 동의 화면으로 간다.
    //   동의 필요 판정·권한·처리 동작은 바꾸지 않는다. 글자는 줄이지 않는다.
    //   작은 아이콘은 여러 줄 글자의 세로 가운데가 아니라 **제목 첫 줄**에 맞춘다.
    // [S080 T3 · 판정63 B · 공용 두 호스트] 의미색은 작은 강조 하나(살구 원 + 적갈색 망치)만 — 제목 textPrimary · 설명/링크 textSecondary ·
    //   선 borderLight · 꺾쇠 grey600(시안 관리자 홈 '처리할 일' 위계 · §12.2). 문구 · 크기 · 접기 판정 · 탭/복귀 조회 · 숨김 무변경.
    final titleStyle = ResponsiveHelper.smallStyle(context,
        color: AppColors.textPrimary, fontWeight: FontWeight.w700);
    final bodyStyle = ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary);
    return Padding(
      padding: EdgeInsets.fromLTRB(16 * s, 0, 16 * s, 8 * s),
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(14 * s),
          // [DU1 구현69 VQ-01] 노란 채움+테두리가 확정 카드보다 먼저 시선을 잡았다(시안 대조) — 흰 면·옅은 선으로 낮추고
          //   주의 의미는 노란 아이콘·제목 글자색이 맡는다. 문구·동작·판정 무변경. → [S080 T3] 지금은 살구 원 아이콘 하나가 맡는다(아래).
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.borderLight),
          ),
          child: LayoutBuilder(builder: (context, c) {
            final iconSize = 20 * s;
            // [S080 T3] 선행 = 살구 원 지름 32·s — 글 폭 계산(접힘 판정)과 실제 Row 선행폭이 같은 값이다.
            final leadSize = 32 * s;
            final textWidth = c.maxWidth - leadSize - 10 * s - 18 * s;
            final tp = TextPainter(
              text: TextSpan(text: title, style: DefaultTextStyle.of(context).style.merge(titleStyle)),
              textScaler: MediaQuery.textScalerOf(context),
              textDirection: TextDirection.ltr,
              maxLines: 1,
            )..layout(maxWidth: textWidth > 0 ? textWidth : 1);
            final folded = tp.didExceedMaxLines;
            final lineH = tp.height;
            tp.dispose();
            // 원을 제목 첫 줄 높이의 가운데에 둔다. 원이 첫 줄보다 크면(기본 배율) 그리기만 위로 옮긴다 — 배치 높이 · 글 위치 불변.
            final leadDy = (lineH - leadSize) / 2;
            final lead = Container(
              width: leadSize,
              height: leadSize,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: AppColors.conceptAmberSurface, shape: BoxShape.circle),
              child: Icon(Icons.gavel_rounded, size: iconSize, color: AppColors.conceptAmberInk),
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                leadDy >= 0
                    ? Padding(padding: EdgeInsets.only(top: leadDy.clamp(0, 40)), child: lead)
                    : Transform.translate(offset: Offset(0, leadDy), child: lead),
                SizedBox(width: 10 * s),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // [ADMIN-HOME.31] 큰 글자에서 '필요|해요'·'내용|을' 로 끊겼다 — 낱말 단위(표시만).
                      Text(TextLayout.keepWords(title), semanticsLabel: title, style: titleStyle),
                      if (!folded || _bodyOpen) ...[
                        SizedBox(height: 2 * s),
                        Text(TextLayout.keepWords(body), semanticsLabel: body, style: bodyStyle),
                      ],
                      if (folded)
                        // 카드 탭(동의 화면 이동)과 따로 — 설명만 그 자리에서 펼치고 접는다.
                        Semantics(
                          button: true,
                          expanded: _bodyOpen,
                          child: InkWell(
                            onTap: () => setState(() => _bodyOpen = !_bodyOpen),
                            child: Padding(
                              padding: EdgeInsets.symmetric(vertical: 6 * s),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Text(_bodyOpen ? '설명 접기' : '설명 보기',
                                    style: bodyStyle.copyWith(
                                        fontWeight: FontWeight.w600,
                                        decoration: TextDecoration.underline)),
                                Icon(_bodyOpen ? Icons.expand_less : Icons.expand_more,
                                    size: 18 * s, color: AppColors.conceptAmberInk),
                              ]),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(top: ((lineH - 18 * s) / 2).clamp(0, 40)),
                  child: Icon(Icons.chevron_right,
                      size: 18 * s, color: AppColors.grey600),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }
}
