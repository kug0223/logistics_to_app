// lib/screens/legal/legal_consent_screen.dart
//
// [R7-LEGAL.1B.1] 재동의가 필요할 때 가는 **하나의** 자리.
//
//   홈의 할 일도, 지원이 막혔을 때의 안내도 여기로 온다. 화면마다 다른
//   동의 다이얼로그를 만들면 같은 사건을 다른 말로 설명하게 된다.
//
//   묻는 방식은 가입·복구와 같다 — 본문을 보여 주고, 필수와 선택을 나누고,
//   사용자가 직접 고르고, 열람을 동의로 세지 않는다(`LegalConsentList`).
//   달라지는 것은 **왜 왔는가** 뿐이다.
//
//     RECONSENT_REQUIRED      "이용약관이 변경되었습니다"
//     LEGACY_CONSENT_UNKNOWN  "약관 동의 정보를 다시 확인해 주세요"
//
//   같은 화면을 쓰되 두 사건을 같은 문장으로 말하지 않는다. 하나는 우리가
//   약관을 바꿨다는 뜻이고, 하나는 예전 기록이 불완전하다는 뜻이다.

import 'package:flutter/material.dart';

import '../../models/core/legal_readiness.dart';
import '../../models/core/legal_terms_model.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/terms_consent_plan.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/auth/legal_consent_list.dart';
import 'legal_consent_reads.dart';

class LegalConsentScreen extends StatefulWidget {
  const LegalConsentScreen({super.key, this.reads});

  /// 테스트에서 갈아끼우는 경계. 운영에서는 null.
  final LegalConsentReads? reads;

  @override
  State<LegalConsentScreen> createState() => _LegalConsentScreenState();
}

class _LegalConsentScreenState extends State<LegalConsentScreen> {
  late final LegalConsentReads _reads = widget.reads ?? LegalConsentReads.of();

  LegalReadiness _readiness = LegalReadiness.loading;
  LegalTerms? _terms;
  Map<String, StoredConsent> _stored = const {};
  Map<String, bool> _choices = const {};
  final Set<String> _viewed = <String>{};
  bool _submitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _readiness = LegalReadiness.loading;
      _errorMessage = null;
    });
    try {
      final results = await Future.wait([
        _reads.readiness(),
        _reads.terms(),
        _reads.storedConsent(),
      ]);
      if (!mounted) return;
      final readiness = results[0] as LegalReadiness;
      final terms = results[1] as LegalTerms;
      final stored = StoredConsent.parseMap(results[2]);
      setState(() {
        _readiness = readiness;
        _terms = terms;
        _stored = stored;
        _choices = TermsConsentPlan.initialChoices(
            activeItems: terms.activeItems, stored: stored);
      });
    } catch (e) {
      debugPrint('⚠️ 약관 상태 조회 실패: $e');
      if (!mounted) return;
      // 조회 실패를 "동의하지 않았다" 로 바꾸지 않는다.
      setState(() => _readiness = LegalReadiness.error);
    }
  }

  Future<void> _submit() async {
    final terms = _terms;
    if (terms == null) return;
    if (!TermsConsentPlan.allRequiredChosen(
        activeItems: terms.activeItems, stored: _stored, choices: _choices)) {
      setState(() => _errorMessage = '필수 약관에 동의해야 계속할 수 있습니다.');
      return;
    }

    setState(() {
      _submitting = true;
      _errorMessage = null;
    });
    try {
      final record = TermsConsentPlan.buildPayload(
        activeItems: terms.activeItems,
        stored: _stored,
        choices: _choices,
      );
      if (record.isNotEmpty) await _reads.recordConsent(record);
      if (!mounted) return;
      // 기록 뒤 canonical 상태를 **다시 묻는다** — 화면이 스스로
      // "이제 됐다" 고 판단하지 않는다.
      final fresh = await _reads.readiness();
      if (!mounted) return;
      setState(() {
        _readiness = fresh;
        _submitting = false;
      });
      if (!fresh.needsAttention) {
        ToastHelper.showSuccess('약관 동의가 완료되었습니다.');
        if (mounted) Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('⚠️ 약관 동의 기록 실패: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _errorMessage = '저장에 실패했습니다.\n연결을 확인하고 다시 시도해주세요.';
      });
    }
  }

  // ── 문구 — 사건이 다르면 다르게 말한다 ───────────────────────
  String get _headline => switch (_readiness.status) {
        LegalReadinessStatus.reconsentRequired => '이용약관이 변경되었습니다',
        LegalReadinessStatus.legacyConsentUnknown => '약관 동의 정보를 다시 확인해 주세요',
        _ => '약관 동의',
      };

  String get _body => switch (_readiness.status) {
        LegalReadinessStatus.reconsentRequired =>
          '변경된 내용을 확인하고 동의해 주세요.',
        LegalReadinessStatus.legacyConsentUnknown =>
          '이전 동의 기록으로는 어떤 내용에 동의하셨는지 확인할 수 없습니다.\n'
              '번거롭지만 현재 약관을 다시 확인해 주세요.',
        _ => '내용을 확인하고 선택해 주세요.',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('약관 동의'),
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    switch (_readiness.status) {
      case LegalReadinessStatus.loading:
        return const Center(child: CircularProgressIndicator());
      case LegalReadinessStatus.error:
        return _buildError();
      default:
        return _buildConsent();
    }
  }

  Widget _buildError() => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined,
                size: 40, color: AppColors.textTertiary),
            const SizedBox(height: 16),
            Text('약관 상태를 확인하지 못했어요',
                style: ResponsiveHelper.bodyStyle(context,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            // 모르는 것과 동의하지 않은 것은 다른 말이다.
            Text('동의하지 않았다는 뜻이 아닙니다.',
                textAlign: TextAlign.center,
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.textTertiary)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('다시 시도'),
            ),
          ],
        ),
      );

  /// [R7-PAYROLL-POLICY.5A] 시행 예정 약관 안내 한 줄.
  ///
  /// 발행과 시행은 다른 사건이다. 예정 약관은 **아직 효력이 없으므로**
  /// 여기서 동의를 받지 않는다 — 알려 주기만 한다. 동의를 받으면 그 글이
  /// 더 늦은 판으로 교체됐을 때 그 동의가 어느 글도 가리키지 않게 된다.
  String? get _upcomingNotice {
    final up = _readiness.upcoming;
    if (up.isEmpty) return null;
    final dates = up
        .map((u) => u.effectiveAt)
        .whereType<DateTime>()
        .toList()
      ..sort();
    if (dates.isEmpty) {
      return '변경된 약관이 공지되어 있습니다. 시행일부터 적용됩니다.';
    }
    final d = dates.first;
    final sameDay = dates.every(
        (x) => x.year == d.year && x.month == d.month && x.day == d.day);
    final when = '${d.year}년 ${d.month}월 ${d.day}일';
    return sameDay
        ? '변경된 약관이 공지되어 있습니다. $when부터 적용됩니다.'
        : '변경된 약관이 공지되어 있습니다. 가장 이른 시행일은 $when입니다.';
  }

  Widget _buildUpcomingNotice(String notice) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.infoBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.event_outlined,
                size: 16, color: AppColors.infoDark),
            const SizedBox(width: 8),
            // 좁은 화면에서 넘치지 않게 — 줄바꿈을 허용한다.
            Expanded(
              child: Text(notice,
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.infoDark)),
            ),
          ],
        ),
      );

  Widget _buildConsent() {
    final terms = _terms;
    if (terms == null) return const Center(child: CircularProgressIndicator());
    final items = terms.activeItems;
    final canProceed = TermsConsentPlan.allRequiredChosen(
        activeItems: items, stored: _stored, choices: _choices);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            children: [
              Text(_headline,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text(_body, style: ResponsiveHelper.smallStyle(context)),
              if (_upcomingNotice case final notice?) ...[
                const SizedBox(height: 12),
                _buildUpcomingNotice(notice),
              ],
              const SizedBox(height: 20),
              LegalConsentList(
                items: items,
                stored: _stored,
                choices: _choices,
                viewed: _viewed,
                enabled: !_submitting,
                // 무엇이 달라졌는지 짚어 준다.
                highlightIds: _readiness.attentionItems.toSet(),
                onChanged: (id, v) =>
                    setState(() => _choices = {..._choices, id: v}),
                onViewed: (id) => setState(() => _viewed.add(id)),
              ),
              const SizedBox(height: 16),
              if (_errorMessage != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.errorBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_errorMessage!,
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.error)),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_submitting || !canProceed) ? null : _submit,
              style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('동의하고 계속하기'),
            ),
          ),
        ),
      ],
    );
  }
}
