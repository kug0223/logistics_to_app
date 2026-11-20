// lib/screens/business_admin/expiring_contracts_screen.dart
// 계약 종료 예정 전체화면 — PHASE 2D
//
// ExpiringContractsDialog(Modal) → ExpiringContractsScreen(Full Screen) 교체
// - 중첩 Dialog 제거 (Dialog 안에서 FixedWorkerManagementDialog 열기 → 허용)
// - gradient header / 통계 카드 제거
// - D-day 순 목록 — [N352-1] 기한 묶음(만료 · 3일 이내 · 4–7일 · 8–15일) 제목 + 흰 카드 한 장씩
// - Error ≠ 0건 (별도 상태)

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/core/application_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/user_model.dart';
import '../../services/firestore_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/format_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/renewal_decision_state.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/notification_badge.dart';
import '../common/notification_screen.dart';
import 'dialogs/fixed_worker_management_dialog.dart';
import 'expiring_contracts_reads.dart';

class _ExpiringItem {
  final ApplicationModel application;
  final UserModel? user;
  final BusinessModel? business;
  final int daysRemaining;

  const _ExpiringItem({
    required this.application,
    this.user,
    required this.business,
    required this.daysRemaining,
  });
}

class ExpiringContractsScreen extends StatefulWidget {
  final List<String> businessIds;
  final List<BusinessModel> businesses;

  /// [DU347] 세 조회 주입 지점(같은 폴더 *_reads.dart 패턴). null 이면 [ExpiringContractsReads.of] — FirestoreService 실제 조회.
  final ExpiringContractsReads? reads;

  const ExpiringContractsScreen({
    super.key,
    required this.businessIds,
    required this.businesses,
    this.reads,
  });

  @override
  State<ExpiringContractsScreen> createState() =>
      _ExpiringContractsScreenState();
}

class _ExpiringContractsScreenState extends State<ExpiringContractsScreen> {
  final _svc = FirestoreService();
  late final ExpiringContractsReads _reads = widget.reads ?? ExpiringContractsReads.of(_svc);
  List<_ExpiringItem> _items = [];
  bool _loading = true;
  bool _hasError = false;

  // [CORRECTION-EXPIRED-UNDECIDED-RENEWAL-ACTION-SURFACE]
  //   창은 이제 renewal_decision_state 가 정한다 — Home·이 화면·고정근무자가
  //   각자 날짜 조건을 갖고 있으면 같은 사람을 두고 서로 다른 말을 한다.
  //   ([PHASE 2D] 의 지역 상수 _daysWindow 는 그래서 사라졌다.)

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    try {
      final today = DateTime.now();
      final todayOnly = FormatHelper.toKstDate(today);

      final perBusiness = await Future.wait(
        widget.businessIds.map((bizId) async {
          final apps = await _reads.expiringApplications(
            businessId: bizId,
            fromDate: todayOnly,
          );

          // [RENEWAL-PROPOSAL-COMMITMENT] 이미 제안을 보낸 건은 관리자가
          //   지금 할 일이 아니다. 거절·철회·대체되거나 시작일이 지나면
          //   다시 결정이 필요해지므로 자동으로 목록에 돌아온다.
          final waiting = (await _reads.pendingRenewalProposals(bizId))
              .where((p) => p.isActionableAt(today))
              .map((p) => p.oldApplicationId)
              .toSet();

          // [CORRECTION-EXPIRED-UNDECIDED-RENEWAL-ACTION-SURFACE]
          //   `diff >= 0` 이라 종료일이 지나는 순간 그 사람이 사라졌다.
          //   결정은 아직 남아 있는데 신호만 꺼진 것이다.
          //   이제 Home 과 같은 하나의 판정식을 쓴다.
          final inWindow = apps
              .where((app) =>
                  needsManagerRenewalAction(app, todayOnly, waiting))
              .toList()
            ..sort((a, b) => compareRenewalUrgency(a, b, todayOnly));

          if (inWindow.isEmpty) return <_ExpiringItem>[];

          final uids = inWindow.map((a) => a.uid).toSet().toList();
          // [PII-DOC-R0.1 / INV-1] 계약 만료 화면 — 이름만 쓴다.
          final userMap = await _reads.usersBatch(uids, businessId: bizId);

          BusinessModel? biz;
          try {
            biz = widget.businesses.firstWhere((b) => b.id == bizId);
          } catch (_) {}

          return inWindow.map((app) {
            final end = app.actualResignDate ?? app.workEndDate;
            // [DU347] 남은 날은 공용 판정과 같은 자(KST 달력 날짜 키)로 잰다. 예전에는 기기 로컬 자정
            //   DateTime(end.y, m, d) 에서 UTC 키 todayOnly 를 빼, KST 기기에서 앞으로 n일 남은 계약이 n−1(내일 = D-Day)로
            //   보이고 오늘 · 내일 행이 같은 0 으로 사업장 사이 순서가 섞였다. UTC 로 표현된 같은 instant 도 같은 날이 된다.
            final endOnly = FormatHelper.toKstDate(end!);
            final diff = endOnly.difference(todayOnly).inDays;
            return _ExpiringItem(
              application: app,
              user: userMap[app.uid],
              business: biz,
              daysRemaining: diff,
            );
          }).toList();
        }),
      );

      final items = perBusiness.expand((e) => e).toList()
        ..sort((a, b) => a.daysRemaining.compareTo(b.daysRemaining));

      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (e) {
      debugPrint('❌ [계약종료예정] 화면 조회 실패: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _hasError = true;
      });
    }
  }

  Color _dDayColor(BuildContext context, int days) {
    if (days <= 3) return AppColors.error;
    if (days <= 7) return AppColors.warning;
    return Theme.of(context).primaryColor;
  }

  /// [DU347] 같은 구간의 글자색 — 막대 · 칩 바탕의 중간 톤은 연한 칩 위 글자로 대비가 모자랐다(1.96~3.15).
  Color _dDayTextColor(int days) {
    if (days <= 3) return AppColors.errorDark;
    // [DU352] 4–7일: warningDark 는 반투명 주황 칩 실제 바탕(#F7ECDC) 위 4.49 → warningInk(약 6.0)
    if (days <= 7) return AppColors.warningInk;
    return AppColors.brandDark;
  }

  /// [N352-1] 기한 묶음 제목 — 표시 순서 그대로. 경계는 위 칩 색 구간(≤3 · ≤7 · 그 밖)과 같은 **표시 경계**이며,
  ///   갱신 결정 기한이나 만료 뒤 유예가 아니다. 15일 상한 · 과거 하한 없음 · 응답 대기 제외는 `_loadData` 의 판정이 정한다.
  static const List<String> _groupTitles = [
    '만료 · 결정 필요',
    '3일 이내 종료',
    '4–7일 후 종료',
    '8–15일 후 종료',
  ];

  /// [N352-1] 이미 계산된 남은 날(`daysRemaining`)로 묶음 번호만 고른다 — 날짜를 다시 재지 않는다.
  ///   만료(d < 0)만 칩 색 구간(≤3)에서 떼어 맨 앞 묶음으로 둔다.
  static int _groupOf(int days) {
    if (days < 0) return 0;
    if (days <= 3) return 1;
    if (days <= 7) return 2;
    return 3;
  }

  /// 만료와 예정을 한 숫자로 뭉치지 않는다 — 늦은 건이 있으면 먼저 말한다.
  String _countHeaderText() {
    final expired = _items.where((e) => e.daysRemaining < 0).length;
    final upcoming = _items.length - expired;
    if (expired == 0) return '곧 종료 $upcoming명';
    if (upcoming == 0) return '만료 · 결정 필요 $expired명';
    return '만료 · 결정 필요 $expired명 · 곧 종료 $upcoming명';
  }

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: '계약 확인 필요',
      actions: [
        IconButton(
          icon: const Icon(Icons.home_outlined),
          color: AppColors.textSecondary,
          onPressed: () => NavigationHelper.goHome(context),
          tooltip: '홈',
        ),
        NotificationBadge(
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined),
            color: AppColors.textSecondary,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
            tooltip: '알림',
          ),
        ),
      ],
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const LoadingWidget(message: '계약 현황 조회 중...');
    }
    if (_hasError) return _buildError(context);
    if (_items.isEmpty) return _buildEmpty(context);

    // [N352-1] 같은 기한 묶음의 행을 제목 + 흰 카드 한 장으로 묶는다. `_items`(판정 · 정렬 그대로)를 앞에서부터
    //   순서대로 나누기만 한다 — 묶음을 이어 붙이면 원래 목록과 같은 집합 · 같은 순서다(다시 정렬하지 않는다).
    //   빈 묶음은 제목 · 빈 카드 · 그 여백을 모두 만들지 않는다. 접기 · 필터 없이 전부 펼친다.
    final groups = List.generate(_groupTitles.length, (_) => <_ExpiringItem>[]);
    for (final item in _items) {
      groups[_groupOf(item.daysRemaining)].add(item);
    }
    final gutter = ResponsiveHelper.spacing(context, 16);
    final sections = <Widget>[];
    for (var g = 0; g < groups.length; g++) {
      if (groups[g].isEmpty) continue;
      sections.addAll([
        if (sections.isNotEmpty) SizedBox(height: ResponsiveHelper.spacing(context, 24)),
        _buildGroupTitle(_groupTitles[g], groups[g].length),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        _buildGroupCard(context, groups[g]),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCountHeader(context),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            // AppPageScaffold는 body에 하단 SafeArea를 적용하지 않는다.
            // gesture navigation 기기에서 마지막 row가 시스템 바에 가리지 않도록 보정.
            padding: EdgeInsets.fromLTRB(
              gutter,
              gutter,
              gutter,
              gutter + MediaQuery.paddingOf(context).bottom,
            ),
            children: sections,
          ),
        ),
      ],
    );
  }

  /// [N352-1] 묶음 제목과 건수 `(n)` — 공용 섹션 제목 위계(AppTextStyles.sectionTitle) · 중립 글자색.
  ///   급함색은 행의 D-day 칩 한 곳에만 둔다(제목에서 반복하지 않는다). 제목은 낱말 사이에서만 줄을 바꾼다
  ///   (표시만 — 화면 읽기는 원문).
  Widget _buildGroupTitle(String title, int count) {
    final style = AppTextStyles.sectionTitle();
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: TextLayout.phrases(title)),
          TextSpan(
            text: ' ($count)',
            style: style.copyWith(color: AppColors.textSecondary, fontWeight: FontWeight.w400),
          ),
        ],
      ),
      semanticsLabel: '$title ($count)',
      style: style,
    );
  }

  /// [N352-1] 묶음 카드 — 공용 카드 장식(흰 면 · 옅은 테두리) 한 장 안에 행을 중립 구분선으로 잇는다.
  ///   행마다 따로 뜬 카드를 만들지 않는다. 안쪽 투명 Material 은 행(InkWell)의 눌림 물결이 흰 면 위에 보이게 하고,
  ///   모서리 밖으로 번지는 물결은 카드가 자른다(면 색 · 그림자 추가 0).
  ///   행은 예전 itemBuilder 처럼 목록 안의 자기 context 로 만든다(Builder) — 목록 안 자기 context 를 유지한다(정확한 조상 깊이 동일은 주장하지 않는다 · N352 사전 판정 §1-3).
  Widget _buildGroupCard(BuildContext context, List<_ExpiringItem> items) {
    final inset = ResponsiveHelper.spacing(context, 16);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: CommonWidgets.compactCardDecoration(),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 1,
                  thickness: 1,
                  indent: inset,
                  endIndent: inset,
                  color: AppColors.borderLight,
                ),
              Builder(builder: (rowContext) => _buildRow(rowContext, items[i])),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCountHeader(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      // [DU347] grey600(바탕 4.30) → textSecondary, 구분점 뒤 줄바꿈
      child: Text(
        TextLayout.phrases(_countHeaderText()),
        semanticsLabel: _countHeaderText(),
        style: ResponsiveHelper.bodyStyle(context).copyWith(
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.event_available,
      title: '결정이 필요한 계약이 없어요',
    );
  }

  Widget _buildError(BuildContext context) {
    return AppEmptyState(
      icon: Icons.error_outline,
      title: '계약 종료 예정 정보를 불러오지 못했어요',
      // [DU347] 실패 본문 '다시 시도' — 보조 outlined · 새로고침 아이콘(소급 5 S009/S079 일관 방향)
      action: OutlinedButton.icon(
        onPressed: _loadData,
        icon: const Icon(Icons.refresh),
        label: const Text('다시 시도'),
      ),
    );
  }

  Widget _buildRow(BuildContext context, _ExpiringItem item) {
    final color = _dDayColor(context, item.daysRemaining);
    final name = item.user?.name ?? '알 수 없음';
    final bizName = item.business?.name ?? '';
    final endDate =
        item.application.actualResignDate ?? item.application.workEndDate;
    // [DU347] 날짜 글자도 KST 달력 날짜로(UTC 로 표현된 instant 가 하루 이르게 보였다).
    final dateStr = endDate != null
        ? DateFormat('M/d(E)', 'ko_KR').format(FormatHelper.toKstDate(endDate))
        : '-';
    final dayLabel =
        item.daysRemaining < 0
            ? '만료 ${-item.daysRemaining}일'
            : (item.daysRemaining == 0 ? 'D-Day' : 'D-${item.daysRemaining}');

    return InkWell(
      // [N352-1] 행 식별 — 지원서 객체로 가른다. 같은 이름(동명이인)이어도 지원서가 다르면 다른 행이다.
      key: ObjectKey(item.application),
      onTap: () async {
        final biz = item.business;
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (_) => FixedWorkerManagementDialog(
            businessIds: [item.application.businessId],
            businesses: biz != null ? [biz] : widget.businesses,
            initialBusinessId: item.application.businessId,
            initialWorkerUid: item.application.uid,
            onChanged: () {},
          ),
        );
        // FixedWorkerManagement에서 계약 처리 후 목록 갱신
        if (mounted) _loadData();
      },
      // [N352-1] 행 앞 이니셜 원 · 왼쪽 급함색 막대를 뺐다 — 바로 옆 이름을 되풀이하고 같은 기한색을 세 번 반복했다.
      //   개별 기한색은 D-day 칩 한 곳에만 남는다. 이름 · 사업장 · 종료일은 중립 읽기색 그대로 · 대체 장식 0.
      //   행 전체(InkWell)가 그대로 한 탭 수신자다. 높이는 내용으로 정해진다(새 고정 높이 0).
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 10),
        ),
        // [DU347] 이름 identity · 사업장 낱말 단위 · 글자색 진한 짝. 오른쪽(날짜 · 칩) 칸이 글자 칸을 본문 6자보다
        //   좁히면(320 · 2.0) 날짜 · 칩을 이름 아래 줄로 내린다 — 실제 글자 배율로 잰다.
        //   [N352-1] 원 자리가 빠진 새 남은 폭으로 잰다(판정식 · 기준 6자 그대로).
        child: LayoutBuilder(builder: (ctx, cons) {
          final textColor = _dDayTextColor(item.daysRemaining);
          final nameStyle = ResponsiveHelper.bodyStyle(ctx).copyWith(fontWeight: FontWeight.w600);
          final dateStyle = ResponsiveHelper.smallStyle(ctx, color: AppColors.textSecondary);
          final chipStyle = ResponsiveHelper.smallStyle(ctx).copyWith(color: textColor, fontWeight: FontWeight.bold);
          double oneLine(String text, TextStyle style) {
            final tp = TextPainter(
              text: TextSpan(text: text, style: DefaultTextStyle.of(ctx).style.merge(style)),
              textDirection: Directionality.of(ctx),
              textScaler: MediaQuery.textScalerOf(ctx),
              maxLines: 1,
            )..layout();
            final w = tp.width;
            tp.dispose();
            return w;
          }

          final chipPadH = ResponsiveHelper.spacing(ctx, 8);
          final dateText = Text(dateStr, style: dateStyle);
          final chip = Container(
            padding: EdgeInsets.symmetric(
              horizontal: chipPadH,
              vertical: ResponsiveHelper.spacing(ctx, 3),
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(dayLabel, style: chipStyle),
          );
          final texts = <Widget>[
            Text(TextLayout.identity(name), semanticsLabel: name, style: nameStyle),
            if (bizName.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                TextLayout.phrases(bizName),
                semanticsLabel: bizName,
                style: ResponsiveHelper.smallStyle(ctx, color: AppColors.textSecondary),
              ),
            ],
          ];
          final rightW = math.max(oneLine(dateStr, dateStyle), oneLine(dayLabel, chipStyle) + chipPadH * 2);
          final sideBySide = !cons.hasBoundedWidth ||
              cons.maxWidth - ResponsiveHelper.spacing(ctx, 8) - rightW >= oneLine('가나다라마바', nameStyle);
          if (sideBySide) {
            return Row(
              children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: texts),
                ),
                SizedBox(width: ResponsiveHelper.spacing(ctx, 8)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [dateText, const SizedBox(height: 4), chip],
                ),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...texts,
              SizedBox(height: ResponsiveHelper.spacing(ctx, 6)),
              Wrap(
                spacing: ResponsiveHelper.spacing(ctx, 8),
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [dateText, chip],
              ),
            ],
          );
        }),
      ),
    );
  }
}
