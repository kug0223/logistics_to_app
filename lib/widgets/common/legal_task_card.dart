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

class LegalTaskCard extends StatefulWidget {
  const LegalTaskCard({super.key, this.loadReadiness, this.scale = 1.0});

  /// 테스트에서 갈아끼우는 경계. 운영에서는 null → callable.
  final Future<LegalReadiness> Function()? loadReadiness;
  final double scale;

  @override
  State<LegalTaskCard> createState() => _LegalTaskCardState();
}

class _LegalTaskCardState extends State<LegalTaskCard> {
  late final Future<LegalReadiness> Function() _load =
      widget.loadReadiness ?? LegalConsentReads.of().readiness;

  LegalReadiness _readiness = LegalReadiness.loading;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final r = await _load();
      if (mounted) setState(() => _readiness = r);
    } catch (e) {
      debugPrint('⚠️ 약관 상태 조회 실패: $e');
      // 모르는 것을 "동의하지 않았다" 로 바꾸지 않는다 — 카드를 숨길 뿐이다.
      if (mounted) setState(() => _readiness = LegalReadiness.error);
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

    return Padding(
      padding: EdgeInsets.fromLTRB(16 * s, 0, 16 * s, 8 * s),
      child: InkWell(
        onTap: _open,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.all(14 * s),
          decoration: BoxDecoration(
            color: AppColors.yellowWarnBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.yellowWarnDark.withValues(
                alpha: 0.25)),
          ),
          child: Row(
            children: [
              Icon(Icons.gavel_rounded,
                  size: 20 * s, color: AppColors.yellowWarnDark),
              SizedBox(width: 10 * s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.yellowWarnText,
                            fontWeight: FontWeight.w700)),
                    SizedBox(height: 2 * s),
                    Text(body,
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.yellowWarnText)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  size: 18 * s, color: AppColors.yellowWarnDark),
            ],
          ),
        ),
      ),
    );
  }
}
