// lib/screens/user/dialogs/my_requests_dialog.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../models/core/schedule_change_request_model.dart';
import '../../../models/core/id_card_access_request_model.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/interim_settlement_request_model.dart';
import '../../../services/firestore_service.dart';
import 'my_requests_reads.dart';
import '../../../services/payroll_payment_service.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/format_helper.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../utils/text_layout.dart';
import '../../../theme/app_colors.dart';

/// 통합 알림 아이템 타입
enum NotificationItemType {
  scheduleChange,      // 스케줄 변경 요청
  idCardRequest,       // 신분증 열람 요청
  termination,         // 계약해지 요청
  interimSettlement,   // 중간정산 요청
}

/// 통합 알림 아이템
class _NotificationItem {
  final NotificationItemType type;
  final dynamic data;
  final DateTime requestedAt;

  _NotificationItem({
    required this.type,
    required this.data,
    required this.requestedAt,
  });
}

/// 내 알림 다이얼로그 (스케줄 변경 + 신분증 요청 + 계약해지 통합)
class MyRequestsDialog extends StatefulWidget {
  final String applicantUid;
  final VoidCallback onChanged;

  /// [R7-P2 잔여 I45] 인박스가 열릴 때 나가는 네 읽기의 경계. production 은 null.
  final MyRequestsReads? reads;

  const MyRequestsDialog({
    super.key,
    required this.applicantUid,
    required this.onChanged,
    this.reads,
  });

  /// 공용 진입 helper.
  ///
  /// [DS-03] 알림 화면과 홈 화면이 같은 방식으로 연다.
  /// launch 파라미터(barrierDismissible: false)는 기존 알림 화면 동작 그대로다.
  /// 호출자는 반환된 Future를 await 해서 닫힌 뒤 자기 화면을 갱신할 수 있다.
  static Future<void> show(
    BuildContext context, {
    required String applicantUid,
    VoidCallback? onChanged,
    MyRequestsReads? reads,
  }) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => MyRequestsDialog(
        applicantUid: applicantUid,
        onChanged: onChanged ?? () {},
        reads: reads,
      ),
    );
  }

  @override
  State<MyRequestsDialog> createState() => _MyRequestsDialogState();
}

class _MyRequestsDialogState extends State<MyRequestsDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  final PayrollPaymentService _payService = PayrollPaymentService();
  late final MyRequestsReads _reads =
      widget.reads ?? MyRequestsReads.of(_firestoreService, _payService);

  List<_NotificationItem> _allNotifications = [];
  bool _isLoading = true;
  bool _isProcessing = false;

  /// [DU267] 읽기 실패 — 빈 목록과 구별한다(이전에는 실패해도 '알림이 없습니다'를 보였다).
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _loadAllNotifications();
  }

  /// 모든 알림 로드 (3가지 타입 통합)
  Future<void> _loadAllNotifications() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    try {
      // 병렬 조회
      final results = await Future.wait([
        _reads.scheduleChangeRequests(widget.applicantUid),
        _reads.pendingIdCardRequests(widget.applicantUid),
        _reads.terminationRequests(widget.applicantUid),
        _reads.interimSettlements(),
      ]);

      final scheduleRequests = results[0] as List<ScheduleChangeRequestModel>;
      final idCardRequests = results[1] as List<IdCardAccessRequestModel>;
      final terminations = results[2] as List<ApplicationModel>;
      final interimSettlements = results[3] as List<InterimSettlementRequestModel>;

      // 통합 리스트 생성
      final notifications = <_NotificationItem>[];

      // 1. 스케줄 변경 요청 (PENDING 기준 필터)
      // EXTRA_WORK는 requesterType과 무관하게 지원자에게 항상 표시 (관리자→지원자 방향이지만 혼용 기록 방어)
      // 그 외 타입은 관리자가 보낸(isAdminRequest) 또는 근무자 본인이 보낸(isApplicantRequest) 경우 표시
      // [FAIL-SCR-01] isApplicantRequest 추가 — 근무자 발신 LEAVE/CANCEL_LEAVE/CANCEL_EXTRA 요청도 목록에 포함
      for (final req in scheduleRequests) {
        if (req.isPending &&
            (req.isExtraWorkRequest || req.isAdminRequest || req.isApplicantRequest)) {
          notifications.add(_NotificationItem(
            type: NotificationItemType.scheduleChange,
            data: req,
            requestedAt: req.requestedAt,
          ));
        }
      }

      // 2. 신분증 열람 요청
      for (final req in idCardRequests) {
        notifications.add(_NotificationItem(
          type: NotificationItemType.idCardRequest,
          data: req,
          requestedAt: req.requestedAt,
        ));
      }

      // 3. 계약해지 요청
      for (final app in terminations) {
        if (app.terminationRequestedAt != null) {
          notifications.add(_NotificationItem(
            type: NotificationItemType.termination,
            data: app,
            requestedAt: app.terminationRequestedAt!,
          ));
        }
      }

      // 4. 중간정산 요청 — PENDING(대기) · APPROVED(이체 대기)만 표시
      for (final req in interimSettlements) {
        if (req.isPending || req.isApproved) {
          notifications.add(_NotificationItem(
            type: NotificationItemType.interimSettlement,
            data: req,
            requestedAt: req.createdAt,
          ));
        }
      }

      // 최신순 정렬
      notifications.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));

      if (!mounted) return;
      setState(() {
        _allNotifications = notifications;
        _isLoading = false;
      });

      debugPrint('✅ 알림 로드 완료: ${notifications.length}건');
    } catch (e) {
      debugPrint('❌ 알림 로드 실패: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = true;
        });
        ToastHelper.showError('알림을 불러오는데 실패했습니다.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: AppDialogSize.insetV,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
        ),
        child: Padding(
          padding: ResponsiveHelper.listPadding(context),
          child: Column(
          children: [
            // 헤더
            // [DU267] 아이콘 중립·제목 본문색·닫기 보조색. 건수는 단순 사실이라 경보색(error 위 흰 3.68) 대신
            //   시안 '처리할 일' 건수처럼 대표색 옅은 면. 제목은 좁은 칸에서 줄어들 수 있게 Flexible.
            Row(
              children: [
                Icon(
                  Icons.notifications,
                  size: ResponsiveHelper.iconSize(context, 28),
                  color: AppColors.textSecondary,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '내 알림',
                          style: ResponsiveHelper.titleStyle(context, color: AppColors.textPrimary),
                        ),
                      ),
                      if (_allNotifications.isNotEmpty)
                        Container(
                          margin: EdgeInsets.only(left: ResponsiveHelper.spacing(context, 8)),
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 8),
                            vertical: ResponsiveHelper.spacing(context, 2),
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.brandSurface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${_allNotifications.length}',
                            semanticsLabel: '${_allNotifications.length}건',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.brand, fontWeight: FontWeight.bold),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  color: AppColors.textSecondary,
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),

            Divider(height: ResponsiveHelper.spacing(context, 24)),

            // 알림 목록
            Expanded(
              child: _isLoading
                  ? const LoadingWidget(message: '알림 로딩 중...')
                  : _loadFailed
                      ? _buildErrorState()
                      : _allNotifications.isEmpty
                      ? _buildEmptyState()
                      : ListView.builder(
                          itemCount: _allNotifications.length,
                          itemBuilder: (context, index) {
                            return _buildNotificationCard(_allNotifications[index]);
                          },
                        ),
            ),
          ],
        ),
      ),
    ),
    );
  }

  /// 빈 상태
  /// [DU267] 직접 그린 빈 상태(disabledColor 아이콘·bodySmall 글자) → 공용 AppEmptyState(DU248 값, 문구 같음)
  Widget _buildEmptyState() {
    return const AppEmptyState(
      icon: Icons.notifications_none,
      title: '알림이 없습니다',
    );
  }

  /// [DU267] 읽기 실패 — 네 읽기 중 하나가 실패하면 전체가 실패한다(Future.wait). 이전에는 빈 상태로 보여
  ///   처리할 요청이 없다고 말했다. 같은 읽기를 다시 부르는 '다시 시도'를 둔다(토스트는 그대로).
  Widget _buildErrorState() {
    return AppEmptyState(
      icon: Icons.error_outline,
      title: '알림을 불러오지 못했습니다',
      subtitle: '잠시 후 다시 시도해 주세요',
      subtitleColor: AppColors.textSecondary,
      action: OutlinedButton(
        onPressed: _loadAllNotifications,
        child: const Text('다시 시도'),
      ),
    );
  }

  /// 통합 알림 카드
  Widget _buildNotificationCard(_NotificationItem item) {
    switch (item.type) {
      case NotificationItemType.scheduleChange:
        return _buildScheduleChangeCard(item.data as ScheduleChangeRequestModel);
      case NotificationItemType.idCardRequest:
        return _buildIdCardRequestCard(item.data as IdCardAccessRequestModel);
      case NotificationItemType.termination:
        return _buildTerminationCard(item.data as ApplicationModel);
      case NotificationItemType.interimSettlement:
        return _buildInterimSettlementCard(item.data as InterimSettlementRequestModel);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 스케줄 변경 요청 카드
  // ═══════════════════════════════════════════════════════════

  Widget _buildScheduleChangeCard(ScheduleChangeRequestModel request) {
    // [DU267] 의미색은 아이콘용 진한 토큰(연한 원색은 옅은 면 위 3:1 미달 가능)
    IconData icon;
    Color iconColor;

    if (request.isLeaveRequest) {
      icon = Icons.beach_access;
      iconColor = AppColors.warningDark;
    } else if (request.isNoWorkRequest) {
      icon = Icons.block;
      iconColor = AppColors.errorDark;
    } else {
      icon = Icons.add_circle;
      iconColor = AppColors.successDark;
    }

    return _requestCard(
      icon: icon,
      tone: iconColor,
      body: [
        _cardTitle(request.requestTypeLabel),
        _cardSubject(FormatHelper.formatDateKorean(request.targetDate)),
        // [DU267] 사유는 이 대화에서만 보인다 — 1줄 말줄임을 없앤다(사용자가 쓴 글이라 원문 줄바꿈).
        if (request.reason != null) _cardDetail(request.reason!, raw: true),
        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
        _buildStatusChip('대기중', AppColors.warningDark, AppColors.warningBg),
      ],
      // [DU267] 빨간 X 아이콘 → 글자 보조 행동(UI-1). 근무자 발신일 때만(기존 조건 그대로).
      secondary: request.isApplicantRequest
          ? _secondaryAction('요청 취소', () => _cancelScheduleRequest(request))
          : null,
    );
  }

  /// [FAIL-SCR-01] 근무자 발신 스케줄 변경 요청 취소
  Future<void> _cancelScheduleRequest(ScheduleChangeRequestModel request) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final success = await _firestoreService.cancelScheduleChangeRequest(
        requestId: request.id,
      );
      if (!mounted) return;
      if (success) {
        ToastHelper.showSuccess('요청이 취소되었습니다');
        widget.onChanged();
        await _loadAllNotifications();
      } else {
        ToastHelper.showError('요청 취소에 실패했습니다');
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('요청 취소에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 신분증 열람 요청 카드
  // ═══════════════════════════════════════════════════════════

  Widget _buildIdCardRequestCard(IdCardAccessRequestModel request) {
    return _requestCard(
      icon: Icons.badge,
      tone: AppColors.infoDark,
      body: [
        _cardTitle('신분증 열람 요청'),
        _cardSubject(request.requesterBusinessName, name: true),
        _cardDetail('요청자: ${request.requesterName}'),
        _cardDetail('사유: ${request.reasonText}', raw: true),
        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
        _buildStatusChip('승인 대기', AppColors.infoDeep, AppColors.infoBg),
      ],
      // [DU267] 빨간 X·초록 체크 아이콘(글자 없음, 초록 2.78) → 거절(글자, 왼쪽)·승인(대표색 채움, 오른쪽)(UI-1)
      secondary: _secondaryAction('거절', () => _handleIdCardReject(request)),
      primary: _primaryAction('승인', () => _handleIdCardApprove(request)),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 계약해지 요청 카드
  // ═══════════════════════════════════════════════════════════

  Widget _buildTerminationCard(ApplicationModel app) {
    final requestedAt = app.terminationRequestedAt;
    // [설계] inDays는 floor 처리라 실제 남은 시간보다 최대 23h 59m 일찍 0이 될 수 있음.
    // UI 표시 목적이므로 허용 범위 — 실제 자동승인은 서버(Cloud Function)에서 처리함.
    final daysLeft = requestedAt != null
        ? 3 - DateTime.now().difference(requestedAt).inDays
        : 0;

    return _requestCard(
      icon: Icons.warning_amber,
      tone: AppColors.warningDark,
      body: [
        // [DU267] 제목 warningDark → 본문색(주의 의미는 아이콘·상태 배지가 맡는다). 사업장명 말줄임 제거.
        _cardTitle('계약해지 요청'),
        _cardSubject(app.businessName, name: true),
        if (app.terminationReason != null)
          _cardDetail('사유: ${app.terminationReason}', raw: true),
        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
        _buildStatusChip(
          daysLeft > 0 ? '$daysLeft일 후 자동승인' : '오늘 자동승인',
          AppColors.warningDark,
          AppColors.warningBg,
        ),
      ],
      secondary: _secondaryAction('거절', () => _handleTerminationReject(app)),
      primary: _primaryAction('승인', () => _handleTerminationApprove(app)),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 중간정산 요청 카드
  // ═══════════════════════════════════════════════════════════

  Widget _buildInterimSettlementCard(InterimSettlementRequestModel req) {
    final isPending = req.isPending;
    // [DU267] 옅은 유형 바탕 제거 — 흰 카드 + 의미색 진한 토큰(아이콘)·토큰 쌍(배지). 사업장명 말줄임 제거.
    final color = isPending ? AppColors.warningDark : AppColors.tealDark;
    final bgColor = isPending ? AppColors.warningBg : AppColors.tealBg;
    final icon = isPending ? Icons.hourglass_top : Icons.event_available;
    final statusLabel = isPending ? '승인 대기' : '승인됨 · 이체 대기';
    final transferText = req.isApproved && req.scheduledTransferDate != null
        ? '이체 예정일: ${DateFormat('MM월 dd일').format(req.scheduledTransferDate!)}'
        : null;

    return _requestCard(
      icon: icon,
      tone: color,
      body: [
        _cardTitle('중간정산 요청'),
        _cardSubject(req.businessName, name: true),
        _cardDetail('${req.periodLabel}  ·  ${req.recordCount}일  ·  ${FormatHelper.formatWage(req.netAmount)}'),
        if (transferText != null)
          Text(
            TextLayout.keepWords(transferText),
            semanticsLabel: transferText,
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.tealDark, fontWeight: FontWeight.w600),
          ),
        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
        _buildStatusChip(statusLabel, color, bgColor),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 공통 위젯
  // ═══════════════════════════════════════════════════════════

  /// [DU267] 상태 배지 — 원색 20% 면 위 원색 tiny 글자(주황 약 2.x) → 의미 토큰 바탕·진한 글자,
  ///   13 w600(Standards 배지 13~14)·작은 배지 radius 8. 낱말 단위 줄바꿈.
  Widget _buildStatusChip(String label, Color fg, Color bg) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        TextLayout.keepWords(label),
        semanticsLabel: label,
        style: ResponsiveHelper.smallStyle(
          context,
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// [DU267] 요청 카드 공통 틀 — 이 대화를 여는 알림 카드(DU242)와 같은 값: 흰 면·radius 16·grey200 테두리,
  ///   의미색 진한 토큰 10% 면의 둥근 사각(radius 10) 아이콘 상자. 행동은 내용 아래 한 줄(UI-1):
  ///   보조(거절·요청 취소)는 왼쪽 글자, 주 행동(승인)은 오른쪽 대표색 채움. 이전 ListTile trailing 은 좁은 칸에서 내용 폭을 줄였다.
  Widget _requestCard({
    required IconData icon,
    required Color tone,
    required List<Widget> body,
    Widget? secondary,
    Widget? primary,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: ResponsiveHelper.spacing(context, 36),
                height: ResponsiveHelper.spacing(context, 36),
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: tone, size: ResponsiveHelper.iconSize(context, 18)),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 10)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: body,
                ),
              ),
            ],
          ),
          if (secondary != null || primary != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            // 폭 전체 안에서 양끝 정렬 — Wrap 만 두면 내용 폭으로 줄어 두 버튼이 왼쪽에 붙는다(DU261 r1).
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: ResponsiveHelper.spacing(context, 4),
                children: [
                  if (secondary != null) secondary,
                  if (primary != null) primary,
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// [DU267] 카드 제목 — 본문색 굵게, 낱말 단위 줄바꿈(화면 읽기는 원문).
  Widget _cardTitle(String s) => Text(
        TextLayout.keepWords(s),
        semanticsLabel: s,
        style: ResponsiveHelper.bodyStyle(context,
            color: AppColors.textPrimary, fontWeight: FontWeight.bold),
      );

  /// [DU267] 사업장·날짜 줄 — 본문색, 말줄임 없음. 사업장명은 식별 정보 단위로만 줄을 바꾼다.
  Widget _cardSubject(String s, {bool name = false}) => Text(
        name ? TextLayout.identity(s) : TextLayout.keepWords(s),
        semanticsLabel: s,
        style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary),
      );

  /// [DU267] 보조 줄(요청자·기간·사유) — textSecondary, 말줄임 없음.
  ///   raw: 사유는 원문 그대로 줄바꿈한다(사용자가 쓴 긴 글을 낱말로 묶지 않는다).
  Widget _cardDetail(String s, {bool raw = false}) => Text(
        raw ? s : TextLayout.keepWords(s),
        semanticsLabel: raw ? null : s,
        style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
      );

  /// [DU267] 보조 행동(거절·요청 취소) — 테두리 없는 보조색 글자, 터치 48(UI-1). 처리 중 비활성(기존 그대로).
  Widget _secondaryAction(String label, VoidCallback onPressed) => TextButton(
        onPressed: _isProcessing ? null : onPressed,
        // [DU267 r1] 글자 스타일은 버튼 textStyle 로 — Text 의 style 색(bodyStyle 기본 grey700)이 전경색·비활성색을 덮었다.
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          minimumSize: const Size(48, 48),
          textStyle: ResponsiveHelper.bodyStyle(context, fontWeight: FontWeight.w600),
        ),
        child: Text(label),
      );

  /// [DU267] 주 행동(승인) — 공용 ElevatedButton 테마(대표색·48). 처리 중 비활성(기존 그대로).
  Widget _primaryAction(String label, VoidCallback onPressed) => ElevatedButton(
        onPressed: _isProcessing ? null : onPressed,
        child: Text(label),
      );

  // ═══════════════════════════════════════════════════════════
  // 신분증 요청 액션 (이전 스케줄 승인/거절 함수는 USER 화면에서 제거됨)
  // ═══════════════════════════════════════════════════════════

  // ═══════════════════════════════════════════════════════════
  // 신분증 요청 액션
  // ═══════════════════════════════════════════════════════════

  Future<void> _handleIdCardApprove(IdCardAccessRequestModel request) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '신분증 열람 승인',
      message: '${request.requesterBusinessName}에서 신분증 열람을 요청했습니다.\n\n'
          '요청 사유: ${request.reasonText}\n\n'
          '승인 시 7일간 열람 가능합니다.',
      confirmText: '승인',
      // [DU309 §9.1·§12.2] 열람 승인 = 일반 진행(7일 한정 동의, 손실 실행 아님) → 버튼 brand(이전 successDark 녹색 채움),
      //   머리 아이콘의 예전 파랑(infoDark #1976D2)도 brand 로. 두 값 모두 기본값이라 지정하지 않는다.
      icon: Icons.badge,
    );

    if (!confirmed || !mounted) return;

      final success = await _firestoreService.approveIdCardAccessRequest(request.id);
      if (!mounted) return;
      if (success) {
        ToastHelper.showSuccess('승인되었습니다');
        await _loadAllNotifications();
        if (!mounted) return;
        widget.onChanged();
      } else {
        ToastHelper.showError('승인 실패');
      }
    } catch (e) {
      debugPrint('❌ 신분증 승인 오류: $e');
      if (mounted) ToastHelper.showError('처리 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleIdCardReject(IdCardAccessRequestModel request) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
    final reason = await DialogHelper.showTextInput(
      context,
      title: '신분증 열람 거절',
      message: '${request.requesterBusinessName}의 요청을 거절합니다.',
      hintText: '거절 사유 (선택)',
      maxLines: 2,
      confirmText: '거절',
      // [DU267] error 위 흰 글자 3.68 → errorDark
      confirmColor: AppColors.errorDark,
      icon: Icons.cancel,
      iconColor: AppColors.errorDark,
    );

    if (reason == null || !mounted) return;

      final success = await _firestoreService.rejectIdCardAccessRequest(
        request.id,
        reason: reason.isEmpty ? null : reason,
      );
      if (!mounted) return;
      if (success) {
        ToastHelper.showSuccess('거절되었습니다');
        await _loadAllNotifications();
        if (!mounted) return;
        widget.onChanged();
      } else {
        ToastHelper.showError('거절 실패');
      }
    } catch (e) {
      debugPrint('❌ 신분증 거절 오류: $e');
      if (mounted) ToastHelper.showError('처리 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ═══════════════════════════════════════════════════════════
  // 계약해지 액션
  // ═══════════════════════════════════════════════════════════

  Future<void> _handleTerminationApprove(ApplicationModel app) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '계약해지 승인',
      message: '${app.businessName}과의 계약을 해지합니다.'
          '${app.terminationReason != null ? '\n\n해지 사유: ${app.terminationReason}' : ''}'
          '\n\n승인 시 즉시 계약이 해지됩니다.',
      confirmText: '승인 (해지)',
      // [DU267] 되돌릴 수 없는 확정 순간의 위험색은 유지하고 읽히게(error 3.68 → errorDark)
      confirmColor: AppColors.errorDark,
      icon: Icons.warning_amber,
      iconColor: AppColors.warningDark,
    );

    if (!confirmed || !mounted) return;

      final success = await _firestoreService.approveTermination(app.id);
      if (!mounted) return;
      if (success) {
        ToastHelper.showSuccess('계약이 해지되었습니다');
        await _loadAllNotifications();
        if (!mounted) return;
        widget.onChanged();
      } else {
        ToastHelper.showError('처리 실패');
      }
    } catch (e) {
      debugPrint('❌ 계약해지 승인 오류: $e');
      if (mounted) ToastHelper.showError('처리 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _handleTerminationReject(ApplicationModel app) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
    final reason = await DialogHelper.showTextInput(
      context,
      title: '계약해지 거절',
      message: '${app.businessName}의 계약해지 요청을 거절합니다.',
      hintText: '거절 사유 (선택)',
      maxLines: 2,
      confirmText: '거절',
      // [DU309] 해지 거절은 고용 유지: 버튼과 머리 아이콘은 기본 brand.
      icon: Icons.cancel,
    );

    if (reason == null || !mounted) return;

      final success = await _firestoreService.rejectTermination(
        applicationId: app.id,
        rejectReason: reason.isEmpty ? null : reason,
      );
      if (!mounted) return;
      if (success) {
        ToastHelper.showSuccess('거절되었습니다');
        // 계약해지 거절 후 내 지원 목록 캐시 무효화 — terminationStatus=REJECTED 반영
        _firestoreService.invalidateMyApplicationsCache(widget.applicantUid);
        await _loadAllNotifications();
        if (!mounted) return;
        widget.onChanged();
      } else {
        ToastHelper.showError('거절 실패');
      }
    } catch (e) {
      debugPrint('❌ 계약해지 거절 오류: $e');
      if (mounted) ToastHelper.showError('처리 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}