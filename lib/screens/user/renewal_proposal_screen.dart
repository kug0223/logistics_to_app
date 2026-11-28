// [RENEWAL-PROPOSAL-COMMITMENT] 근로자가 연장 제안에 답하는 화면.
//
//   근로자가 수락하는 것은 "연장"이라는 단어가 아니라 **조건**이다.
//   그래서 기간·업무·요일·시간·임금을 모두 보여준 뒤에 묻는다.
//
//   수락하면 그때 새 계약이 CONTRACT_PENDING 으로 만들어지고, 거기서부터
//   좌석과 근무 일정이 효력일부터 살아난다. 거절은 해지도 퇴사도 아니다 —
//   기존 계약은 원래 종료일까지 그대로다.

import 'package:flutter/material.dart';

import '../../models/core/renewal_proposal_model.dart';
import 'renewal_proposal_reads.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/action_guard.dart';

class RenewalProposalScreen extends StatefulWidget {
  /// 알림 deep link 로 들어온 경우의 제안 id. 없으면 목록 전체를 본다.
  final String? focusProposalId;

  /// [DU262] 시험용 읽기 주입 자리. production 은 null(FirestoreService 로 읽는다).
  final RenewalProposalReads? reads;

  const RenewalProposalScreen({super.key, this.focusProposalId, this.reads});

  @override
  State<RenewalProposalScreen> createState() => _RenewalProposalScreenState();
}

class _RenewalProposalScreenState extends State<RenewalProposalScreen> {
  final _svc = FirestoreService();
  List<RenewalProposalModel> _proposals = [];
  bool _loading = true;
  bool _hasError = false;
  bool _busy = false;

  /// [RENEWAL-PROPOSAL-STALE-RECOVERY] 알림을 눌러 들어왔는데 그 제안이
  /// 이미 시작일을 넘긴 경우.
  ///
  ///   "받은 제안이 없어요"라고 말하면 근로자는 제안이 온 적 없다고
  ///   이해한다. 제안은 왔고, 답할 수 있는 기간이 지났을 뿐이다.
  bool _focusExpired = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// [impl_27b · L48 같은 꼴] 읽기 차례 — 늦게 끝난 옛 읽기가 수락·거절 뒤 새 목록을 덮지 않게.
  int _loadGen = 0;

  Future<void> _load() async {
    final gen = ++_loadGen;
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      // [DU262] 시험은 reads 로 목록을 준다. production 은 그대로 _svc.getMyRenewalProposals().
      final all = await (widget.reads != null
          ? widget.reads!.myRenewalProposals()
          : _svc.getMyRenewalProposals());
      final now = DateTime.now();
      // 서버도 같은 판정을 하지만, 화면이 먼저 걸러 준다 — 누를 수 없는
      //   버튼을 보여주고 눌렀을 때 거절하는 것보다 낫다.
      final actionable = all.where((p) => p.isActionableAt(now)).toList()
        ..sort((a, b) => a.effectiveStart.compareTo(b.effectiveStart));

      // 알림으로 지목된 제안이 목록에서 빠졌다면, 그것은 "없는 제안"이
      //   아니라 **시작일이 지난 제안**이다. 그렇게 말한다.
      final focusId = widget.focusProposalId;
      final focusExpired = focusId != null &&
          !actionable.any((p) => p.id == focusId);

      if (!mounted || gen != _loadGen) return;
      setState(() {
        _proposals = actionable;
        _focusExpired = focusExpired;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ [연장제안] 조회 실패: $e');
      if (!mounted || gen != _loadGen) return;
      // 못 불러온 것을 "제안 없음"으로 말하지 않는다.
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_acceptLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _accept(RenewalProposalModel p) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('renewalProposal._busy', this), () => _acceptLocked(p));

  Future<void> _acceptLocked(RenewalProposalModel p) async {
    if (_busy) return;
    final ok = await DialogHelper.showConfirm(
      context,
      title: '연장 수락',
      message: '${p.businessName}과의 계약을 '
          '${_md(p.effectiveStart)}부터 ${_md(p.effectiveEnd)}까지 연장합니다.\n\n'
          '수락하면 새 계약 절차가 시작되고, 계약 시작일부터 근무 일정이 적용됩니다.',
      confirmText: '수락',
      // [DU262] 초록 위 흰 글자(2.78) → 대표색(5.58). 아이콘은 읽히는 진한 초록.
      confirmColor: AppColors.brand,
      icon: Icons.check_circle_outline,
      iconColor: AppColors.successDark,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _svc.acceptRenewalProposal(p.id);
      if (!mounted) return;
      ToastHelper.showSuccess('연장 제안을 수락했습니다');
      await _load();
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError(e.toString().replaceFirst('Exception: ', ''));
      // 이미 처리됐거나 시작일이 지난 경우 — 현재 상태를 다시 읽는다.
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_declineLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _decline(RenewalProposalModel p) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('renewalProposal._busy', this), () => _declineLocked(p));

  Future<void> _declineLocked(RenewalProposalModel p) async {
    if (_busy) return;
    final ok = await DialogHelper.showConfirm(
      context,
      title: '연장 거절',
      message: '이번 계약 연장 제안을 거절합니다.\n'
          '현재 계약은 기존 종료일까지 유지됩니다.',
      confirmText: '거절',
      // [DU262] 확인 순간의 위험색은 유지하되 읽히게(error 흰 글자 3.68 → errorDark).
      confirmColor: AppColors.errorDark,
      icon: Icons.cancel_outlined,
      iconColor: AppColors.errorDark,
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await _svc.declineRenewalProposal(p.id);
      if (!mounted) return;
      ToastHelper.showSuccess('연장 제안을 거절했습니다');
      await _load();
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError(e.toString().replaceFirst('Exception: ', ''));
      await _load();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _md(DateTime d) {
    final k = FormatHelper.toKstDate(d);
    return '${k.month}/${k.day}';
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: '계약 연장 제안',
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) return const LoadingWidget(message: '연장 제안 확인 중...');
    if (_hasError) {
      return AppEmptyState(
        icon: Icons.error_outline,
        title: '연장 제안을 불러오지 못했어요',
        action: TextButton(onPressed: _load, child: const Text('다시 시도')),
      );
    }
    if (_proposals.isEmpty) {
      // 알림을 눌러 들어왔는데 그 제안이 만료됐다면, 없었다고 하지 않는다.
      if (_focusExpired) {
        return const AppEmptyState(
          icon: Icons.hourglass_disabled,
          title: '이 연장 제안은 계약 시작일이 지나 종료되었어요',
          subtitle: '새 제안이 오면 다시 안내해 드릴게요.',
        );
      }
      return const AppEmptyState(
        icon: Icons.inbox_outlined,
        title: '받은 연장 제안이 없어요',
      );
    }

    // deep link 로 들어왔으면 그 제안을 맨 위에 둔다.
    final ordered = [..._proposals];
    final focusId = widget.focusProposalId;
    if (focusId != null) {
      final i = ordered.indexWhere((p) => p.id == focusId);
      if (i > 0) ordered.insert(0, ordered.removeAt(i));
    }

    return ListView.separated(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 16),
        MediaQuery.paddingOf(context).bottom +
            ResponsiveHelper.spacing(context, 16),
      ),
      itemCount: ordered.length,
      separatorBuilder: (_, __) =>
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
      itemBuilder: (ctx, i) => _buildCard(ctx, ordered[i]),
    );
  }

  Widget _buildCard(BuildContext context, RenewalProposalModel p) {
    final days = (p.workDays ?? const <String>[]).join(' · ');
    // [DU262] 글자 1.3배 이상이면 버튼은 수락 위·거절 아래 전체 폭(DU256 정보 줄과 같은 기준).
    final stacked = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final decline = OutlinedButton(
      onPressed: _busy ? null : () => _decline(p),
      // [DU262] 빨강 → 중립 테두리(본문색 글자, 테마 border 선). 거절은 해지가 아니다
      //   (현재 계약은 종료일까지 유지) — 위험색은 확인 대화에만 둔다(DU245).
      style: OutlinedButton.styleFrom(foregroundColor: AppColors.textPrimary),
      child: const Text('거절'),
    );
    // [DU262] 초록 위 흰 글자(2.78) → 테마 대표색 채움(5.58·48)
    final accept = ElevatedButton(
      onPressed: _busy ? null : () => _accept(p),
      child: const Text('연장 수락'),
    );
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      // [DU262] 반경 14·grey300 → 앱 카드 16·grey200
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [DU262] 사업장명 — 16 bold 본문색(이전 15 w700 grey700), 이름 단위 줄바꿈
          Text(
            TextLayout.identity(p.businessName),
            semanticsLabel: p.businessName,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            TextLayout.keepWords('계약 연장을 제안했습니다.'), // [DU262 r2] B320 '제안했습니/다.' 끊김
            semanticsLabel: '계약 연장을 제안했습니다.',
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.textSecondary), // [DU262] grey600
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          _row(context, '기간',
              '${_md(p.effectiveStart)} ~ ${_md(p.effectiveEnd)}'),
          if (p.selectedWorkType != null)
            _row(context, '업무', p.selectedWorkType!),
          if (days.isNotEmpty) _row(context, '근무요일', days),
          if (p.startTime != null && p.endTime != null)
            _row(context, '근무시간', '${p.startTime} ~ ${p.endTime}'),
          if (p.wage != null)
            _row(context, '임금',
                FormatHelper.formatWageWithType(p.wage!, p.wageType ?? 'hourly')),
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
          if (stacked) ...[
            SizedBox(width: double.infinity, child: accept),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            SizedBox(width: double.infinity, child: decline),
          ] else
            Row(
              children: [
                Expanded(child: decline),
                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                Expanded(child: accept),
              ],
            ),
        ],
      ),
    );
  }

  /// [DU262] 라벨 grey500(2.68) → textSecondary, 값 본문색.
  ///   글자 1.3배 이상이면 라벨 위·값 아래(64 폭 라벨 열에서 '근무/요일'·'근무/시간' 이 끊겼다).
  Widget _row(BuildContext context, String label, String value) {
    final labelText = Text(label,
        style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary));
    final valueText = Text(value,
        style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary)
            .copyWith(fontWeight: FontWeight.w600));
    final stacked = MediaQuery.textScalerOf(context).scale(10) >= 13;
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 6)),
      child: stacked
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [labelText, const SizedBox(height: 2), valueText],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: ResponsiveHelper.spacing(context, 64),
                  child: labelText,
                ),
                Expanded(child: valueText),
              ],
            ),
    );
  }
}
