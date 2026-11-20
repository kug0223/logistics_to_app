import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/attendance_model.dart';
import '../../providers/user_provider.dart';
import '../../services/admin_stats_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import 'dialogs/attendance_status_dialog.dart';

/// [STATS-TO-ATTENDANCE.27] 통계에서 본 숫자의 **바로 그 근무들**.
///
///   통계는 집계와 탐색의 출발점이다. 여기서는 값을 바꾸지 않는다 — 각 행의
///   `근태 확인` 이 기존 근태 화면(`AttendanceStatusDialog`)을 그 근무의 날짜·사업장·
///   지원서로 연다. 권한·정정 writer·확인 창·급여 확정 차단은 그 화면의 것을 그대로 쓴다.
///
///   행은 집계가 쓴 **같은 분류식**(`AdminStatsService.bucketOf`)으로 고른 원본 근태 문서다.
///   이름·날짜로 근무를 다시 찾지 않는다 — 같은 사람이 같은 날 두 번 일할 수 있어서
///   근태 문서가 가진 applicationId 로 연다.
class StatsAttendanceListScreen extends StatefulWidget {
  /// 화면 제목 — 예: `퇴근 미확인 내역`.
  final String title;

  /// 어떤 범위의 목록인가 — 예: `2026년 10월 · 평택센터 · 홍길동`.
  final String scopeLabel;

  /// 조건에 맞는 원본을 읽는다. 통계와 같은 조회·분류를 쓴다. null = 읽지 못함.
  final Future<StatsAttendanceSnapshot?> Function() load;

  /// 이 목록의 조건. load 가 돌려준 원본에서 이것으로 고른다.
  final bool Function(AttendanceModel r) matches;

  /// 이미 손에 있는 원본(월 상세처럼). 주면 첫 조회를 하지 않는다.
  final StatsAttendanceSnapshot? initial;

  /// 결과 내역(결근 등)처럼 정정 대상으로 단정하지 않는 목록 — 안내 문구와 행동 이름이 다르다.
  final bool resultOnly;

  /// 정정이 성공한 **그 순간** 부른다 — 위 화면(월 상세·연간)이 돌아왔을 때 다시 읽을지 정한다.
  ///   뒤로 갈 때 돌려주는 값에 기대지 않는다(기기 뒤로 키에서 결과가 사라진 회차가 있었고,
  ///   그 값을 지키려면 PopScope 로 밀어서 뒤로 가기까지 막아야 한다).
  final VoidCallback? onCorrected;

  /// 시험 주입점 — 근태 화면 대신 불린다(권한 판정은 그대로 먼저 지난다). production 은 null.
  final Future<bool?> Function(AttendanceModel r)? debugOpenAttendance;

  const StatsAttendanceListScreen({
    super.key,
    required this.title,
    required this.scopeLabel,
    required this.load,
    required this.matches,
    this.initial,
    this.resultOnly = false,
    this.debugOpenAttendance,
    this.onCorrected,
  });

  @override
  State<StatsAttendanceListScreen> createState() =>
      _StatsAttendanceListScreenState();
}

class _StatsAttendanceListScreenState extends State<StatsAttendanceListScreen> {
  List<AttendanceModel>? _rows;
  Map<String, UserInfo> _info = const {};
  bool _loading = false;
  bool _loadFailed = false;
  /// 정정 뒤 다시 읽기에 실패했다 — 아래 목록은 정정 전 기준이다.
  bool _staleAfterChange = false;
  /// 정정 뒤 이 목록 조건에서 빠진 근무 수(다시 읽기 성공 시).
  int _leftAfterChange = 0;
  final Set<String> _multiBusiness = {};

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    if (init != null) {
      _apply(init);
    } else {
      _reload();
    }
  }

  void _apply(StatsAttendanceSnapshot s) {
    final rows = s.records.where(widget.matches).toList()
      ..sort((a, b) {
        final d = a.workDate.compareTo(b.workDate);
        if (d != 0) return d;
        final n = (s.userInfo[a.userId]?.name ?? '').compareTo(s.userInfo[b.userId]?.name ?? '');
        if (n != 0) return n;
        final p = (s.userInfo[a.userId]?.personNo ?? '').compareTo(s.userInfo[b.userId]?.personNo ?? '');
        if (p != 0) return p;
        final t = (a.checkInAt?.millisecondsSinceEpoch ?? 0).compareTo(b.checkInAt?.millisecondsSinceEpoch ?? 0);
        if (t != 0) return t;
        return a.id.compareTo(b.id);
      });
    _rows = rows;
    _info = s.userInfo;
    _multiBusiness
      ..clear()
      ..addAll(rows.map((r) => r.businessId));
  }

  /// [afterChange] 정정 뒤 다시 읽기 — 실패해도 이전 목록을 지우지 않고 낡았다고 말한다.
  Future<void> _reload({bool afterChange = false}) async {
    final before = _rows?.map((r) => r.id).toSet() ?? const <String>{};
    setState(() { _loading = true; if (!afterChange) _loadFailed = false; });
    StatsAttendanceSnapshot? snap;
    try {
      snap = await widget.load();
    } catch (e) {
      debugPrint('⚠️ [STATS-TO-ATTENDANCE] 내역 조회 실패: $e');
      snap = null;
    }
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (snap == null) {
        if (afterChange && _rows != null) {
          _staleAfterChange = true;
        } else {
          _loadFailed = true;
        }
        return;
      }
      _apply(snap);
      _loadFailed = false;
      _staleAfterChange = false;
      if (afterChange) {
        final now = _rows!.map((r) => r.id).toSet();
        _leftAfterChange = before.difference(now).length;
      }
    });
  }

  Future<void> _open(AttendanceModel r) async {
    if (r.applicationId.isEmpty || r.businessId.isEmpty) {
      ToastHelper.showWarning('이 근태는 원본 근무와 연결되어 있지 않아 열 수 없어요');
      return;
    }
    // 통계는 급여 권한으로 열렸다. 근태 화면은 근무자 관리 권한이 따로 필요하다 — 새로 주지 않는다.
    final access = context
        .read<UserProvider>()
        .checkForBusiness(r.businessId, (p) => p.canManageWorkers);
    if (access != PermissionCheck.allowed) {
      ToastHelper.showWarning(access == PermissionCheck.denied
          ? '이 사업장의 근태 관리 권한이 없어요'
          : '권한을 확인하지 못했어요. 잠시 후 다시 시도해 주세요');
      return;
    }
    final open = widget.debugOpenAttendance;
    final Future<bool?> pending = open != null
        ? open(r)
        : showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => AttendanceStatusDialog(
              date: FormatHelper.toKstDate(r.workDate),
              businessIds: [r.businessId],
              initialBusinessId: r.businessId,
              initialApplicationId: r.applicationId,
            ),
          );
    final changed = await pending;
    if (!mounted || changed != true) return; // 취소·변경 없음 — 다시 읽지 않는다.
    widget.onCorrected?.call();
    await _reload(afterChange: true);
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: widget.title,
      body: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    final rows = _rows;
    if (rows == null) {
      if (_loadFailed) {
        return AppEmptyState(
          icon: Icons.cloud_off_outlined,
          title: '내역을 불러오지 못했어요',
          subtitle: widget.scopeLabel,
          iconColor: AppColors.error,
          action: TextButton.icon(
            onPressed: _reload,
            icon: const Icon(Icons.refresh),
            label: const Text('다시 조회'),
          ),
        );
      }
      return const LoadingWidget(message: '내역 불러오는 중...');
    }
    final s = ResponsiveHelper.spacing;
    return RefreshIndicator(
      onRefresh: () => _reload(afterChange: _rows != null),
      child: ListView(
        padding: ResponsiveHelper.listPadding(context),
        children: [
          // [DU427] 범위 줄은 구분점 뒤에서만 줄을 바꾼다(다음 줄이 '·' 로 시작하지 않게). 화면 읽기는 원문.
          Text(TextLayout.phrases(widget.scopeLabel),
              semanticsLabel: widget.scopeLabel,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary)),
          if (_staleAfterChange) ...[
            SizedBox(height: s(context, 10)),
            _banner(
              context,
              '최신 내역을 불러오지 못했어요. 아래 목록은 정정 전 기준이에요.',
              AppColors.warningDark,
              action: TextButton(
                onPressed: _loading ? null : () => _reload(afterChange: true),
                child: const Text('다시 조회'),
              ),
            ),
          ] else if (_leftAfterChange > 0) ...[
            SizedBox(height: s(context, 10)),
            _banner(context, '정정으로 이 목록 조건에서 제외된 근무 $_leftAfterChange건 · 근무 기록은 그대로예요',
                AppColors.textSecondary),
          ],
          SizedBox(height: s(context, 12)),
          if (rows.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: s(context, 32)),
              child: Center(
                child: Text(TextLayout.keepWords('조건에 맞는 근무가 없어요'),
                    semanticsLabel: '조건에 맞는 근무가 없어요',
                    textAlign: TextAlign.center,
                    style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary)),
              ),
            )
          else
            ...rows.map((r) => _row(context, r)),
          if (_loading)
            Padding(
              padding: EdgeInsets.all(s(context, 12)),
              child: const Center(
                  child: SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            ),
        ],
      ),
    );
  }

  Widget _banner(BuildContext context, String text, Color color, {Widget? action}) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 8)),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Expanded(
          child: Text(text, style: ResponsiveHelper.smallStyle(context, color: color)),
        ),
        if (action != null) action,
      ]),
    );
  }

  /// [DU428] 날짜와 요일 사이 줄바꿈 없는 공백(U+00A0) — 번들 글꼴에 있어 폭이 늘지 않는다(진단 W probe nbsp delta 0.00).
  static final String _nbsp = String.fromCharCode(0x00A0);

  Widget _row(BuildContext context, AttendanceModel r) {
    final s = ResponsiveHelper.spacing;
    final info = _info[r.userId];
    final linked = r.applicationId.isNotEmpty && r.businessId.isNotEmpty;
    final inT = r.checkInAt != null ? FormatHelper.formatTime(r.checkInAt!) : null;
    final outT = r.checkOutAt != null ? FormatHelper.formatTime(r.checkOutAt!) : null;
    final times = inT == null && outT == null
        ? '출퇴근 기록 없음'
        : '출근 ${inT ?? '기록 없음'} · 퇴근 ${outT ?? '기록 없음'}';
    final settled = r.wageStatus == AttendanceModel.wageConfirmed ||
        r.wageStatus == AttendanceModel.wageTransferred;
    final person = [
      info?.name ?? '이름 확인 불가',
      if (info?.personNo != null) info!.personNo!,
    ].join(' · ');
    // [DU427 · DU428] 머리줄은 날짜(요일 포함)와 업무명을 Wrap 의 따로 항목으로 둔다 — 장식 '·' 없이(다음 줄이 '·' 로 시작하지 않고
    //   '10/5 / (월)' 처럼 날짜가 갈리지 않게). 시각 줄은 구분점 뒤 · 낱말 사이에서만 줄을 바꾼다. 화면 읽기는 원문.
    final date = FormatHelper.formatDate(r.workDate);
    final timesLine = _multiBusiness.length > 1 ? '$times · ${r.businessName}' : times;
    return Container(
      key: ValueKey('att-row-${r.id}'),
      margin: EdgeInsets.only(bottom: s(context, 8)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: linked ? () => _open(r) : null,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: Padding(
            padding: EdgeInsets.symmetric(
                horizontal: s(context, 12), vertical: s(context, 10)),
            // [DU428] 좁거나 글자가 크면(예: 320@2.0) '근태 확인 ›' 을 본문 아래 오른쪽으로 내려 본문이 카드 폭을 다 쓴다.
            //   나란히 두면 B 에서 본문 기둥이 약 146px 이라 칩 '근태 확인 필 / 요' · 시각 2→3줄이 생겼다(진단 du428 diag).
            //   누르는 곳(행 전체 InkWell) · 읽기 순서(본문 → 행동) · 문구는 그대로다. 기준 폭 260 은 글자 배율을 곱한다(TextLayout.fits).
            child: LayoutBuilder(builder: (context, c) {
              final body = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: s(context, 6),
                    runSpacing: s(context, 4),
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        date.replaceAll(' ', _nbsp),
                        semanticsLabel: date,
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                      if (r.workType.isNotEmpty)
                        Text(
                          TextLayout.identity(r.workType),
                          semanticsLabel: r.workType,
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      _chip(context, r.statusLabel, _statusColor(r), _statusBg(r)),
                      if (settled)
                        _chip(context, '급여 ${r.wageStatusLabel}', AppColors.textSecondary, AppColors.grey200),
                    ],
                  ),
                  SizedBox(height: s(context, 3)),
                  Text(person,
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary)),
                  SizedBox(height: s(context, 2)),
                  // [DU428] 사업장 하나면 시각 조각('출근 09:12' · '퇴근 기록 없음')을 통째로 묶고 구분점 뒤에서만 줄을 바꾼다
                  //   ('퇴근 기록 / 없음' 처럼 조각이 갈리지 않게). 사업장 이름이 붙는 여러 사업장 목록은 긴 이름을 위해 phrases 그대로.
                  Text(
                    _multiBusiness.length > 1 ? TextLayout.phrases(timesLine) : TextLayout.joinParts(times),
                    semanticsLabel: timesLine,
                    style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
                  ),
                  if (!linked)
                    Padding(
                      padding: EdgeInsets.only(top: s(context, 3)),
                      child: Text(TextLayout.keepWords('원본 근무와 연결되지 않아 열 수 없어요'),
                          semanticsLabel: '원본 근무와 연결되지 않아 열 수 없어요',
                          style: ResponsiveHelper.tinyStyle(context, color: AppColors.textTertiary)),
                    ),
                ],
              );
              if (!linked) return Row(children: [Expanded(child: body)]);
              final action = Text(widget.resultOnly ? '근태 보기 ›' : '근태 확인 ›',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.brand)
                      .copyWith(fontWeight: FontWeight.w700));
              if (!TextLayout.fits(context, c.maxWidth, 260)) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    body,
                    SizedBox(height: s(context, 6)),
                    Align(alignment: Alignment.centerRight, child: action),
                  ],
                );
              }
              return Row(children: [
                Expanded(child: body),
                SizedBox(width: s(context, 8)),
                action,
              ]);
            }),
          ),
        ),
      ),
    );
  }

  // [DU425 · DU426 · DU427] 상태 칩 글자는 같은 상태의 Bg 토큰 바탕(_statusBg) 위 12px 굵은 글자다 — 글자는 진한 짝(warningDark · textSecondary · errorDark),
  //   확인 필요는 purple(약 5.1:1 · 통계 · 월 상세 배지와 같은 색). 막대 · 범례 점 같은 채움은 기본색 그대로다. 분류 · 의미 · 문구는 그대로다.
  Color _statusColor(AttendanceModel r) {
    switch (AdminStatsService.bucketOf(r)) {
      case StatsAttendanceBucket.present:
        return AppColors.successDark;
      case StatsAttendanceBucket.late:
        return AppColors.warningDark;
      case StatsAttendanceBucket.missedCheckout:
        return AppColors.textSecondary;
      case StatsAttendanceBucket.unconfirmed:
        return AppColors.purple;
      case StatsAttendanceBucket.absent:
        return AppColors.errorDark;
    }
  }

  // [DU427] 칩 바탕은 앱 기준 상태 짝의 Bg 토큰이다(StatusBadge 와 같은 짝). 같은 색 12% 바탕은 지각에서 4.46:1 로 모자랐다.
  //   지각 warningDark/warningBg 4.81 · 결근 errorDark/errorBg 5.80 · 확인필요 purple/purpleBg 5.21 ·
  //   퇴근미확인 · 급여 textSecondary/grey200 5.10 · 출근 successDark/successBg 6.47(산술).
  Color _statusBg(AttendanceModel r) {
    switch (AdminStatsService.bucketOf(r)) {
      case StatsAttendanceBucket.present:
        return AppColors.successBg;
      case StatsAttendanceBucket.late:
        return AppColors.warningBg;
      case StatsAttendanceBucket.missedCheckout:
        return AppColors.grey200;
      case StatsAttendanceBucket.unconfirmed:
        return AppColors.purpleBg;
      case StatsAttendanceBucket.absent:
        return AppColors.errorBg;
    }
  }

  Widget _chip(BuildContext context, String label, Color color, Color bg) => Container(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 6),
          vertical: ResponsiveHelper.spacing(context, 2),
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label,
            style: ResponsiveHelper.tinyStyle(context,
                color: color, fontWeight: FontWeight.w600)),
      );
}
