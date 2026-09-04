import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/core/notification_model.dart';
import '../../widgets/common/notification_card.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/toast_helper.dart';
import '../../providers/user_provider.dart';
// 네비게이션 대상 화면들
import '../user/my_applications_screen.dart';
import '../user/my_schedule_screen.dart';
import '../user/user_contracts_screen.dart';
import '../user/dialogs/my_requests_dialog.dart';
import '../business_admin/workforce_management/integrated_workforce_screen.dart';
import '../business_admin/jobs_root_screen.dart';
import '../contract/contract_sign_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/core/to_model.dart';
import '../../models/core/work_detail_model.dart';
import '../../models/ui/admin_to_list_ui_models.dart';
import '../business_admin/dialogs/work_applicants_dialog.dart';
import '../business_admin/dialogs/day_applicants_dialog.dart';
import '../business_admin/dialogs/fixed_worker_management_dialog.dart';
import '../business_admin/dialogs/schedule_request_management_dialog.dart'; // [PATCH-NOTIF-B1]
import '../business_admin/dialogs/resign_request_management_dialog.dart';    // [PATCH-NOTIF-B1]
import '../../models/core/employment_contract_model.dart';
import '../../services/contract_service.dart';
import '../../services/member_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/loading_widget.dart';
import '../business_admin/admin_review_list_screen.dart';
import '../user/my_reviews_screen.dart';
import '../business_admin/admin_contract_management_screen.dart';
import '../../services/monthly_review_service.dart';
import '../../models/core/review_request_model.dart';
import '../../models/core/user_model.dart';
import '../../widgets/dialogs/monthly_review_dialog.dart';
import '../../widgets/dialogs/business_review_dialog.dart';
import '../../models/core/business_model.dart';
import '../../services/firestore_service.dart';
import '../../services/auth_service.dart';
import '../../widgets/dialogs/worker_detail_dialog.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../user/attendance_check_screen.dart';
import '../../models/core/business_member_model.dart';
import '../user/all_to_list_screen.dart';               // [Phase 8.1C] toMatch fallback
import 'job_posting_screen.dart';                       // [Phase 8.1C] toMatch 공고 상세
import '../business_admin/payroll/payroll_payment_dashboard_screen.dart'; // [FCM-ROUTE-01]
import '../../utils/admin_tab_switcher.dart';           // [FCM-ROUTE-01] Settlement tab canonical routing

// ════════════════════════════════════════════════════════════════════════
// 관리자 알림 접근 검증 결과 — 클릭 시점에 멤버십·권한을 재확인한다.
//
// [설계] 알림은 최대 30일 보존되므로 "알림 발송 시 권한" ≠ "클릭 시 권한".
// 4-layer defense:
//   1. 알림 category 분류 (Phase 2 explicit field)
//   2. 알림함 탭별 필터 (개인/관리 탭)
//   3. 클릭 시점 멤버십 + Permission 재검증 (이 enum·헬퍼가 담당)
//   4. 각 화면 내부 Firestore rules (최종 방어)
// ════════════════════════════════════════════════════════════════════════
enum _AdminAccessResult {
  allowed,           // 접근 허용
  noBusinessAccess,  // businessId가 현재 subAdminBusinessIds에 없음
  noPermission,      // 멤버십 있으나 현재 MemberPermissions 없음
  noBusinessId,      // businessId 필수이나 알림 data에 누락
  invalidContext,    // 순수 USER가 관리자 전용 알림을 탭
}

/// 알림 목록 화면 (전체 / 미읽음 탭)
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _isHandlingTap = false;
  bool _isMarkingAllRead = false;
  /// 미읽음만 보기 토글 — 탭이 아닌 필터 칩으로 전역 적용
  bool _showUnreadOnly = false;

  /// 현재 열려 있는 카드의 ID를 공유하는 노티파이어.
  /// 값이 바뀌면 해당 ID가 아닌 모든 카드가 listener를 통해 자동으로 닫힌다.
  final ValueNotifier<String?> _openCardId = ValueNotifier<String?>(null);

  /// 다른 화면에서 돌아올 때 열린 카드를 닫기 위한 secondary animation 참조.
  Animation<double>? _secondaryAnimation;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _secondaryAnimation = ModalRoute.of(context)?.secondaryAnimation;
      _secondaryAnimation?.addStatusListener(_onSecondaryAnimationStatus);
    });
  }

  /// 위에 올린 화면(detail, dialog 등)이 pop될 때 열린 카드를 닫는다.
  void _onSecondaryAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && mounted) {
      _openCardId.value = null;
    }
  }

  @override
  void dispose() {
    _secondaryAnimation?.removeStatusListener(_onSecondaryAnimationStatus);
    _openCardId.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, provider, _) {
        final isSubAdmin = context.select<UserProvider, bool>((p) => p.isSubAdmin);
        if (provider.loadMoreFailed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && provider.loadMoreFailed) {
              ToastHelper.showError('알림을 더 불러오지 못했습니다');
              provider.clearLoadMoreError();
            }
          });
        }

        // 모두 읽음 액션 버튼 — 흰색 배경이므로 Primary 색상으로
        final markAllReadAction = provider.hasUnread
            ? TextButton(
                onPressed: _isMarkingAllRead
                    ? null
                    : () async {
                        setState(() => _isMarkingAllRead = true);
                        try {
                          final ok = await provider.markAllAsRead();
                          if (!mounted) return;
                          if (ok) {
                            ToastHelper.showSuccess('모든 알림을 읽음 처리했습니다');
                          } else {
                            ToastHelper.showError('읽음 처리에 실패했습니다');
                          }
                        } catch (e) {
                          debugPrint('❌ 전체 읽음 처리 오류: $e');
                          if (mounted) ToastHelper.showError('읽음 처리에 실패했습니다');
                        } finally {
                          if (mounted) setState(() => _isMarkingAllRead = false);
                        }
                      },
                child: Text(
                  '모두 읽음',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: Theme.of(context).primaryColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              )
            : null;

        // 공통 AppBar 빌더
        AppBar buildAppBar({Widget? bottom}) => AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 1,
          shadowColor: AppColors.grey200,
          iconTheme: const IconThemeData(color: AppColors.textPrimary),
          title: Text(
            '알림',
            style: ResponsiveHelper.titleStyle(context, color: AppColors.textPrimary),
          ),
          titleSpacing: 4,
          actions: [
            if (markAllReadAction != null) markAllReadAction,
            const SizedBox(width: 4),
          ],
          bottom: bottom as PreferredSizeWidget?,
        );

        // ── SubAdmin: 3탭 (전체 / 내 알림 / 관리 알림) ───────────────────
        if (isSubAdmin) {
          final unreadPersonal = provider.unreadNotifications
              .where((n) => n.resolvedCategory != NotificationCategory.admin)
              .length;
          final unreadAdmin = provider.unreadNotifications
              .where((n) => n.resolvedCategory == NotificationCategory.admin)
              .length;

          return DefaultTabController(
            length: 3,
            child: Scaffold(
              backgroundColor: AppColors.grey50,
              appBar: buildAppBar(
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(48),
                  child: ColoredBox(
                    color: Colors.white,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TabBar(
                          labelColor: Theme.of(context).primaryColor,
                          unselectedLabelColor: AppColors.grey500,
                          indicatorColor: Theme.of(context).primaryColor,
                          indicatorWeight: 2.0,
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          labelStyle: ResponsiveHelper.smallStyle(
                            context,
                            fontWeight: FontWeight.w600,
                          ),
                          unselectedLabelStyle: ResponsiveHelper.smallStyle(context),
                          tabs: [
                            _buildTab('전체', provider.unreadCount),
                            _buildTab('내 알림', unreadPersonal),
                            _buildTab('관리 알림', unreadAdmin),
                          ],
                        ),
                        Divider(height: 1, color: AppColors.grey200),
                      ],
                    ),
                  ),
                ),
              ),
              body: _buildBody(context, provider, isSubAdmin: true),
            ),
          );
        }

        // ── Pure USER / BUSINESS_ADMIN: 단일 목록, 탭 없음 ───────────────
        return Scaffold(
          backgroundColor: AppColors.grey50,
          appBar: buildAppBar(),
          body: _buildBody(context, provider, isSubAdmin: false),
        );
      },
    );
  }

  /// 미읽음 수 배지가 붙은 탭 위젯 — count 0이면 배지 표시 안 함
  Widget _buildTab(String label, int unreadCount) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (unreadCount > 0) ...[
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: AppColors.error,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$unreadCount',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    NotificationProvider provider, {
    required bool isSubAdmin,
  }) {
    if (provider.isLoading) {
      return const LoadingWidget(message: '알림 불러오는 중...');
    }
    if (provider.hasError) {
      return _buildErrorState(context, provider);
    }

    // rebuild당 DateTime.now() 한 번만 계산
    final now = DateTime.now();

    // 미읽음 필터 토글 칩
    final toggleChip = _buildUnreadToggle(context, provider.unreadCount);

    if (isSubAdmin) {
      // ── SubAdmin: 3탭 (전체 / 내 알림 / 관리 알림) + 미읽음 토글 ───────
      // 전체 풀에 미읽음 필터 먼저 적용 후 탭별 분기
      final base = _showUnreadOnly ? provider.unreadNotifications : provider.notifications;
      final personalNotifs = base
          .where((n) => n.resolvedCategory != NotificationCategory.admin)
          .toList();
      final adminNotifs = base
          .where((n) => n.resolvedCategory == NotificationCategory.admin)
          .toList();

      return Column(
        children: [
          toggleChip,
          Expanded(
            child: TabBarView(
              children: [
                _buildList(
                  context, provider, base,
                  grouped: _buildGroupedItems(base, now),
                  emptyMessage: _showUnreadOnly ? '새로운 알림이 없습니다' : '알림이 없습니다',
                  emptySubtitle: _showUnreadOnly
                      ? '모든 알림을 확인했어요.'
                      : '새로운 알림이 오면 여기에서 확인할 수 있어요.',
                  hasMore: _showUnreadOnly ? false : provider.hasMore,
                  isLoadingMore: _showUnreadOnly ? false : provider.isLoadingMore,
                  onLoadMore: _showUnreadOnly ? null : provider.loadMore,
                  showLoadMoreHint: _showUnreadOnly && provider.hasMore,
                ),
                _buildList(
                  context, provider, personalNotifs,
                  grouped: _buildGroupedItems(personalNotifs, now),
                  emptyMessage: _showUnreadOnly ? '새로운 알림이 없습니다' : '개인 알림이 없습니다',
                  emptySubtitle: _showUnreadOnly ? '모든 알림을 확인했어요.' : null,
                  hasMore: false,
                  showLoadMoreHint: provider.hasMore,
                ),
                _buildList(
                  context, provider, adminNotifs,
                  grouped: _buildGroupedItems(adminNotifs, now),
                  emptyMessage: _showUnreadOnly ? '새로운 알림이 없습니다' : '관리 알림이 없습니다',
                  emptySubtitle: _showUnreadOnly ? '모든 알림을 확인했어요.' : null,
                  hasMore: false,
                  showLoadMoreHint: provider.hasMore,
                ),
              ],
            ),
          ),
        ],
      );
    }

    // ── Pure USER / BUSINESS_ADMIN: 단일 목록 + 미읽음 토글 ─────────────
    final notifs = _showUnreadOnly ? provider.unreadNotifications : provider.notifications;

    return Column(
      children: [
        toggleChip,
        Expanded(
          child: _buildList(
            context, provider, notifs,
            grouped: _buildGroupedItems(notifs, now),
            emptyMessage: _showUnreadOnly ? '새로운 알림이 없습니다' : '알림이 없습니다',
            emptySubtitle: _showUnreadOnly
                ? '모든 알림을 확인했어요.'
                : '새로운 알림이 오면 여기에서 확인할 수 있어요.',
            hasMore: _showUnreadOnly ? false : provider.hasMore,
            isLoadingMore: _showUnreadOnly ? false : provider.isLoadingMore,
            onLoadMore: _showUnreadOnly ? null : provider.loadMore,
            showLoadMoreHint: _showUnreadOnly && provider.hasMore,
          ),
        ),
      ],
    );
  }

  /// 미읽음만 보기 필터 칩 — 모든 역할에서 탭 대신 사용
  Widget _buildUnreadToggle(BuildContext context, int unreadCount) {
    return Padding(
      padding: EdgeInsets.only(
        left: ResponsiveHelper.spacing(context, 12),
        right: ResponsiveHelper.spacing(context, 12),
        top: ResponsiveHelper.spacing(context, 6),
        bottom: ResponsiveHelper.spacing(context, 2),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: FilterChip(
          label: const Text('미읽음만'),
          selected: _showUnreadOnly,
          onSelected: (val) => setState(() => _showUnreadOnly = val),
          // 활성 시 Blue 체크 + 연한 Blue 배경 — 빨간색(삭제/오류 의미)은 사용하지 않음
          showCheckmark: true,
          checkmarkColor: AppColors.workTypeBlue,
          backgroundColor: Colors.white,
          selectedColor: const Color(0xFFE3F2FD),
          side: BorderSide(
            color: _showUnreadOnly
                ? AppColors.workTypeBlue
                : const Color(0xFFE0E0E0),
          ),
          labelStyle: ResponsiveHelper.smallStyle(
            context,
            color: _showUnreadOnly
                ? AppColors.workTypeBlue
                : const Color(0xFF757575),
            fontWeight: _showUnreadOnly ? FontWeight.w600 : FontWeight.w400,
          ),
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 4),
          ),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
    );
  }

  /// 날짜 기준으로 섹션 헤더(String) + 알림(NotificationModel) 혼합 리스트 생성
  List<Object> _buildGroupedItems(List<NotificationModel> notifications, DateTime now) {
    final today = FormatHelper.toKstDate(now);
    final yesterday = today.subtract(const Duration(days: 1));
    final weekAgo = today.subtract(const Duration(days: 7));

    final todayItems = <NotificationModel>[];
    final yesterdayItems = <NotificationModel>[];
    final thisWeekItems = <NotificationModel>[];
    final olderItems = <NotificationModel>[];

    for (final n in notifications) {
      final date = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      if (!date.isBefore(today)) {
        todayItems.add(n);
      } else if (date == yesterday) {
        yesterdayItems.add(n);
      } else if (date.isAfter(weekAgo)) {
        thisWeekItems.add(n);
      } else {
        olderItems.add(n);
      }
    }

    final result = <Object>[];
    if (todayItems.isNotEmpty) {
      result.add('오늘');
      result.addAll(todayItems);
    }
    if (yesterdayItems.isNotEmpty) {
      result.add('어제');
      result.addAll(yesterdayItems);
    }
    if (thisWeekItems.isNotEmpty) {
      result.add('이번 주');
      result.addAll(thisWeekItems);
    }
    if (olderItems.isNotEmpty) {
      result.add('이전');
      result.addAll(olderItems);
    }
    return result;
  }

  Widget _buildSectionHeader(BuildContext context, String label) {
    return Padding(
      padding: EdgeInsets.only(
        left: ResponsiveHelper.spacing(context, 16),
        right: ResponsiveHelper.spacing(context, 16),
        top: ResponsiveHelper.spacing(context, 8),
        bottom: ResponsiveHelper.spacing(context, 6),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.smallStyle(context,
            color: AppColors.grey500, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildList(
    BuildContext context,
    NotificationProvider provider,
    List<NotificationModel> notifications, {
    required List<Object> grouped,
    String emptyMessage = '알림이 없습니다',
    String? emptySubtitle,
    bool hasMore = false,
    bool isLoadingMore = false,
    VoidCallback? onLoadMore,
    bool showLoadMoreHint = false,
  }) {
    if (notifications.isEmpty) {
      return AppEmptyState(
        icon: Icons.notifications_none,
        title: emptyMessage,
        subtitle: emptySubtitle,
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        provider.reload();
        await Future.delayed(const Duration(milliseconds: 400));
      },
      child: NotificationListener<ScrollStartNotification>(
        // 스크롤 시작 시 열린 카드를 닫아 UX 정돈
        onNotification: (notification) {
          _openCardId.value = null;
          return false;
        },
        child: ListView.builder(
          itemCount: grouped.length + (hasMore || showLoadMoreHint ? 1 : 0),
          // top은 FilterChip이 바로 위에 있어 4px만으로 충분
          padding: EdgeInsets.fromLTRB(
            ResponsiveHelper.spacing(context, 16),
            ResponsiveHelper.spacing(context, 4),
            ResponsiveHelper.spacing(context, 16),
            ResponsiveHelper.spacing(context, 16) + MediaQuery.paddingOf(context).bottom,
          ),
          itemBuilder: (context, index) {
            if (index == grouped.length) {
              if (hasMore) {
                return Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: ResponsiveHelper.spacing(context, 12),
                  ),
                  child: Center(
                    child: isLoadingMore
                        ? const CircularProgressIndicator()
                        : TextButton.icon(
                            onPressed: onLoadMore,
                            icon: const Icon(Icons.expand_more),
                            label: const Text('이전 알림 더 보기'),
                          ),
                  ),
                );
              }
              if (showLoadMoreHint) {
                return Padding(
                  padding: EdgeInsets.symmetric(
                    vertical: ResponsiveHelper.spacing(context, 12),
                    horizontal: ResponsiveHelper.spacing(context, 16),
                  ),
                  child: Text(
                    '이전 알림은 전체 탭에서 더 불러올 수 있습니다',
                    textAlign: TextAlign.center,
                    style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400),
                  ),
                );
              }
            }
            final item = grouped[index];
            if (item is String) {
              return _buildSectionHeader(context, item);
            }
            final notification = item as NotificationModel;
            // RepaintBoundary: 카드 스와이프 애니메이션이 인접 카드의 repaint를 유발하지 않도록 격리
            return RepaintBoundary(
              child: NotificationCard(
                key: Key(notification.id),
                notification: notification,
                openCardIdNotifier: _openCardId,
                onTap: () => _handleNotificationTap(context, notification, provider),
                onDismiss: () async {
                  try {
                    final success = await provider.deleteNotification(notification.id);
                    if (!mounted) return;
                    if (success) {
                      ToastHelper.showSuccess('알림이 삭제되었습니다');
                    } else {
                      ToastHelper.showError('알림 삭제에 실패했습니다');
                    }
                  } catch (e) {
                    debugPrint('❌ 알림 삭제 오류: $e');
                    if (mounted) ToastHelper.showError('알림 삭제에 실패했습니다');
                  }
                },
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, NotificationProvider provider) {
    return AppEmptyState(
      icon: Icons.cloud_off_outlined,
      iconColor: AppColors.warning,
      title: '알림을 불러오지 못했습니다',
      subtitle: '네트워크 상태를 확인하고 다시 시도해주세요',
      action: TextButton.icon(
        onPressed: provider.retry,
        icon: const Icon(Icons.refresh),
        label: const Text('다시 시도'),
      ),
    );
  }

  Future<void> _handleNotificationTap(
    BuildContext context,
    NotificationModel notification,
    NotificationProvider provider,
  ) async {
    if (_isHandlingTap) return;
    _isHandlingTap = true;
    // try/finally로 예외 발생 시에도 플래그를 반드시 해제한다.
    // 예외 없이 정상 완료해도 마지막에 해제되므로 중복 탭 방어가 유지된다.
    try {
      // 1. 읽음 처리 — 완료를 기다리지 않고 fire-and-forget (UI 반응성 우선)
      provider.markAsRead(notification.id).catchError((_) {});

      if (!context.mounted) return;

      // 2. 알림 타입에 따른 화면 이동
      final userProvider = context.read<UserProvider>();
      // SubAdmin은 role==USER이지만 관리자 알림을 수신하므로 관리자 분기로 처리한다.
      // isUser만 체크하면 SubAdmin이 isUser==true → 근무자 화면으로 잘못 이동한다.
      final isUser = userProvider.isUser && !userProvider.isSubAdmin;

      switch (notification.type) {
      // ═══════════════════════════════════════════════════════════
      // 지원 관련 알림
      // ═══════════════════════════════════════════════════════════
      // applicationConfirmed·applicationRejected는 근무자(지원자) 전용 발송 — isUser 가드 불필요
      case NotificationType.applicationConfirmed:
      case NotificationType.applicationRejected:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
        );
        break;

      // confirmationCanceled는 양방향:
      //   createConfirmationCanceled        → 지원자에게 (data에 toId/workDetailId 없음)
      //   createConfirmationCanceledByWorker → 관리자에게 (data에 toId/workDetailId 포함)
      // 관리자가 탭하면 WorkApplicantsDialog를 열고, 없으면 IntegratedWorkforceScreen 폴백.
      //
      // [FCM vs 알림함 라우팅 불일치 — 의도적 유지]
      // FCMService의 confirmationCanceled는 screen: "mySchedule" 데이터를 받아 MyScheduleScreen으로 이동.
      // 알림함 탭은 MyApplicationsScreen으로 이동한다.
      //
      // 이 불일치는 의도적으로 유지한다:
      //   - 취소된 확정 지원(CONFIRMED→CANCELED)은 MyScheduleScreen에서 보이지 않는다.
      //     MyScheduleScreen은 PENDING/CONFIRMED/SCHEDULE_CHANGE 상태만 표시한다.
      //   - MyApplicationsScreen은 취소된 지원 내역을 포함하므로 근로자가 실제 내역을 확인할 수 있다.
      //   - FCM의 "mySchedule" 데이터 필드는 CF가 설정하지만 해당 화면에 해당 정보가 없으므로
      //     알림함은 더 적절한 MyApplicationsScreen을 사용한다.
      case NotificationType.confirmationCanceled:
        if (isUser) {
          // 취소된 지원 내역 확인 → MyApplicationsScreen (MyScheduleScreen은 취소 건 미표시)
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
          );
        } else {
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: notification.data?['businessId']?.toString(),
            requiredPermission: (p) => p.canManageTo,
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            await _openWorkApplicantsFromNotification(context, notification);
          }
        }
        break;

      // 파트변경 알림 — 근무자에게만 발송, 내 지원내역에서 변경된 파트 확인 가능
      case NotificationType.workTypeChanged:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
        );
        break;

      // newApplication/applicationCanceled는 관리자에게만 발송되는 알림.
      // USER가 이 타입의 알림을 수신한 경우 → 에러 토스트 (MyApplicationsScreen 폴백 금지).
      case NotificationType.newApplication:
      case NotificationType.applicationCanceled:
        if (isUser) {
          ToastHelper.showWarning('현재 처리할 수 없는 알림입니다.');
        } else {
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: notification.data?['businessId']?.toString(),
            requiredPermission: (p) => p.canManageTo,
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            await _openWorkApplicantsFromNotification(context, notification);
          }
        }
        break;

      // ═══════════════════════════════════════════════════════════
      // TO 초대 관련 알림
      // ═══════════════════════════════════════════════════════════
      // toInvite/toInviteCanceled — 초대받은 근로자에게 발송, 내 지원 현황에서 확인
      case NotificationType.toInvite:
      case NotificationType.toInviteCanceled:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
        );
        break;

      // toInviteAccepted/Declined — 초대한 관리자에게 발송
      // USER(근로자)가 수신한 경우 → 에러 토스트 (관리자 화면 진입 차단).
      case NotificationType.toInviteAccepted:
      case NotificationType.toInviteDeclined:
        if (isUser) {
          ToastHelper.showWarning('현재 처리할 수 없는 알림입니다.');
        } else {
          // [AUDIT.2R2] TO 초대 응답은 TO 관리 도메인 — canManageTo 필요.
          // BUSINESS_ADMIN(OWNER)은 _validateAdminNotificationAccess 내부에서 자동 통과.
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: notification.data?['businessId']?.toString(),
            requiredPermission: (p) => p.canManageTo,
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
                initialBusinessId: notification.data?['businessId']?.toString(),
                notificationType: notification.type.name,
              )),
            );
          }
        }
        break;

      // ═══════════════════════════════════════════════════════════
      // 스케줄 변경 관련 알림
      // ═══════════════════════════════════════════════════════════
      // scheduleChangeRequested: 근로자→관리자 발송 — ADMIN_ONLY
      // USER 수신은 데이터 불일치. 개인 화면으로 이동 금지.
      case NotificationType.scheduleChangeRequested:
        if (isUser) {
          ToastHelper.showWarning('현재 처리할 수 없는 알림입니다.');
        } else {
          // [PATCH-NOTIF-B1] IWS → ScheduleRequestManagementDialog(B)
          final schedBizId = notification.data?['businessId']?.toString();
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: schedBizId,
            requiredPermission: (p) => p.canManageWorkers,
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            if (schedBizId != null && schedBizId.isNotEmpty) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => ScheduleRequestManagementDialog(
                  businessId: schedBizId,
                  onChanged: () {},
                ),
              );
            } else {
              // validator step2 가 noBusinessId 반환하므로 실질적으로 도달 불가.
              // 안전 처리: 경고 표시 후 종료.
              ToastHelper.showWarning('알림 정보를 확인할 수 없습니다.');
            }
          }
        }
        break;

      case NotificationType.scheduleChangeApproved:
      case NotificationType.scheduleChangeRejected:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;

      // ═══════════════════════════════════════════════════════════
      // 근로계약서 서명 요청
      // ═══════════════════════════════════════════════════════════
      case NotificationType.contractSignRequested:
        await _openContractSignFromNotification(context, notification);
        break;

      // contractSigned: 근무자 서명 완료 → 관리자에게만 발송 — ADMIN_ONLY
      // USER 수신 시 에러 토스트 (UserContractsScreen 폴백 금지 — 관리자 전용 알림).
      case NotificationType.contractSigned:
        {
          if (isUser) {
            ToastHelper.showWarning('현재 처리할 수 없는 알림입니다.');
          } else {
            final businessId = notification.data?['businessId']?.toString();
            final access = await _validateAdminNotificationAccess(
              context,
              businessId: businessId,
              requiredPermission: (p) => p.canManageContract,
            );
            if (!context.mounted) return;
            if (_handleAdminAccess(access)) {
              if (businessId != null && businessId.isNotEmpty) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AdminContractManagementScreen(businessId: businessId),
                  ),
                );
              } else {
                // businessId 없음 — validator가 noBusinessId 반환하므로 실질적으로 도달 불가.
                // 안전 처리: 경고 표시 후 종료 (IWS 폴백 제거).
                ToastHelper.showWarning('알림 정보를 확인할 수 없습니다.');
              }
            }
          }
        }
        break;

      // 계약서 무효화 알림 — 근무자의 계약서 목록 화면으로 이동 (H-34)
      case NotificationType.contractVoided:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserContractsScreen()),
        );
        break;

      case NotificationType.contractExpiringReminder:
        {
          // 관리자 전용 알림 — SubAdmin 권한 재검증 후 이동
          final notifBusinessId = notification.data?['businessId']?.toString();
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: notifBusinessId,
            requiredPermission: (p) => p.canManageContract,
          );
          if (!context.mounted) return;
          if (!_handleAdminAccess(access)) break;
          // 알림 data의 businessId 우선 — 다중 사업장 관리자가 다른 사업장 선택 중일 때 정확한 대화상자 표시
          final businessId = (notifBusinessId != null && notifBusinessId.isNotEmpty)
              ? notifBusinessId
              : userProvider.effectiveBusinessId;
          if (businessId != null) {
            // [5B.3B] applicationId 전달 — notification 경유 시 해당 근로자 자동 포커스
            final notifApplicationId = notification.data?['applicationId']?.toString();
            showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => FixedWorkerManagementDialog(
                initialBusinessId: businessId,
                onChanged: () {},
                initialApplicationId: notifApplicationId?.isNotEmpty == true ? notifApplicationId : null,
              ),
            );
          } else {
            // 목적지 해소 불가 — validator 통과 후 notifBusinessId는 항상 non-null/non-empty이므로
            // 실질적으로 도달 불가. 안전 처리: 경고 표시 후 종료 (IWS 폴백 제거).
            ToastHelper.showWarning('알림 정보를 확인할 수 없습니다.');
          }
        }
        break;

      case NotificationType.contractRenewed:
      case NotificationType.contractTerminating:
        // CF screen='mySchedule' — 갱신/종료 후 남은 근무 일정 확인 (FCMService와 동일)
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;

      // ═══════════════════════════════════════════════════════════
      // 계약해지 / 퇴사 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.terminationRequested:
        if (isUser) {
          _showMyRequestsDialog(context, userProvider.currentUser?.uid);
        } else {
          // [F-11-3 수정] 권한 회수 후 탭 시 무효화 — resignRequested와 동일 패턴
          // [PATCH-NOTIF-B1] IWS → ResignRequestManagementDialog(B)
          final termBizId = notification.data?['businessId']?.toString();
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: termBizId,
            requiredPermission: (p) => p.canManageWorkers,
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            if (termBizId != null && termBizId.isNotEmpty) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => ResignRequestManagementDialog(
                  businessId: termBizId,
                  onChanged: () {},
                ),
              );
            } else {
              // validator step2 가 noBusinessId 반환하므로 실질적으로 도달 불가.
              // 안전 처리: 경고 표시 후 종료.
              ToastHelper.showWarning('알림 정보를 확인할 수 없습니다.');
            }
          }
        }
        break;

      // [PATCH-NOTIF-B2] 계약해지/퇴사 완료 결과 — 최종 상태, 추가 관리자 액션 없음
      // 완료된 결과를 보여주는 canonical screen 없음 → 피드백만 제공 후 종료 (no navigation)
      case NotificationType.terminationApproved:
      case NotificationType.resignApproved:
        if (isUser) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
          );
        } else {
          final outcomeBizId = notification.data?['businessId']?.toString();
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: outcomeBizId,
            requiredPermission: (p) => p.canManageWorkers,
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            ToastHelper.showSuccess(
              notification.type == NotificationType.terminationApproved
                  ? '계약해지가 완료되었습니다.'
                  : '퇴사 요청이 승인되었습니다.',
            );
          }
        }
        break;

      // [PATCH-NOTIF-B2] 계약해지 거절 결과 — 거절 사유는 알림 카드 body에 포함됨 (no navigation)
      case NotificationType.terminationRejected:
        if (isUser) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
          );
        } else {
          final rejBizId = notification.data?['businessId']?.toString();
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: rejBizId,
            requiredPermission: (p) => p.canManageWorkers,
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            ToastHelper.showWarning('계약해지 요청이 거절되었습니다.');
          }
        }
        break;

      // [PATCH-NOTIF-B2] resignRejected — DEAD_ADMIN_HANDLER: callableRejectResignation은 workerUid에게만 발송
      // 관리자는 정상 경로에서 이 알림을 수신하지 않음 — 혹시 수신 시 안전 처리
      case NotificationType.resignRejected:
        if (isUser) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
          );
        } else {
          // DEAD_ADMIN_HANDLER: validator 불필요 — business context 없음, 안전 피드백 후 종료
          ToastHelper.showWarning('현재 처리할 수 없는 알림입니다.');
        }
        break;

      // resignRequested: 근로자→관리자 퇴직 요청, resignReminder: D+1/D+2 미처리 경고
      // 두 타입 모두 항상 관리자 수신 — USER 수신 시 에러 토스트 (navigation 없음)
      // [PATCH-NOTIF-B1] IWS → ResignRequestManagementDialog(B)
      case NotificationType.resignRequested:
      case NotificationType.resignReminder:
        {
          final resignBizId = notification.data?['businessId']?.toString();
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: resignBizId,
            requiredPermission: (p) => p.canManageWorkers,
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            if (resignBizId != null && resignBizId.isNotEmpty) {
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => ResignRequestManagementDialog(
                  businessId: resignBizId,
                  onChanged: () {},
                ),
              );
            } else {
              // validator step2 가 noBusinessId 반환하므로 실질적으로 도달 불가.
              // 안전 처리: 경고 표시 후 종료.
              ToastHelper.showWarning('알림 정보를 확인할 수 없습니다.');
            }
          }
        }
        break;

      // contractRequested: 근무자→관리자 계약서 작성 요청 — 항상 관리자 수신
      // USER 수신 시 에러 토스트 (navigation 없음)
      // [PATCH-NOTIF-A1-CONTRACT] IWS → AdminContractManagementScreen(Tab 1 = 미발송)
      // [GAPFIX-NOTIF-CONTRACTREQUESTED-NULL-BIZ-01] businessId null/empty 명시 차단
      case NotificationType.contractRequested:
        {
          final contractReqBusinessId = notification.data?['businessId']?.toString();
          if (contractReqBusinessId == null || contractReqBusinessId.isEmpty) {
            ToastHelper.showWarning('알림 정보를 확인할 수 없습니다.');
            return;
          }
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: contractReqBusinessId,
            requiredPermission: (p) => p.canManageContract,
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => AdminContractManagementScreen(
                businessId: contractReqBusinessId,
                initialTab: 1,
              )),
            );
          }
        }
        break;

      // ═══════════════════════════════════════════════════════════
      // 신분증 열람 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.idCardAccessRequested:
        // 이 알림은 근무자에게 전송됨 — 관리자가 신분증 열람 요청 시 근무자에게 발송
        if (isUser) {
          _showMyRequestsDialog(context, userProvider.currentUser?.uid);
        } else {
          // [PATCH-NOTIF-C2] DEAD_ADMIN_HANDLER — 현재 producer가 근무자(targetUserId)에게만 발송함
          // legacy/stale notification 안전 처리: validator 불필요, business context 없음
          ToastHelper.showWarning('현재 처리할 수 없는 알림입니다.');
        }
        break;

      case NotificationType.idCardAccessApproved:
      case NotificationType.idCardAccessRejected:
      case NotificationType.idCardAccessExpiringSoon:
      case NotificationType.idCardConsentGranted: // [ID-CONSENT] 사전동의 Grant 활성화 → 내 지원 목록
        if (isUser) {
          _showMyRequestsDialog(context, userProvider.currentUser?.uid);
        } else {
          // [F-11-3 수정] 관리자 수신 시 권한 재검증 — canManageWorkers
          final businessId = notification.data?['businessId']?.toString();
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: businessId,
            requiredPermission: (p) => p.canManageWorkers,
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            final workerId = notification.data?['workerId']?.toString();
            if (workerId != null && workerId.isNotEmpty) {
              await _openWorkerDetailFromNotification(context, workerId, businessId);
            } else {
              // [PATCH-NOTIF-C1] workerId 없음 — worker 특정 불가, IWS fallback 제거
              ToastHelper.showWarning('알림 정보를 확인할 수 없습니다.');
            }
          }
        }
        break;

      // ═══════════════════════════════════════════════════════════
      // 근무 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.workReminder:
      case NotificationType.workCanceled:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;

      // ═══════════════════════════════════════════════════════════
      // 출퇴근 재확인 관련 알림 (근무 당일 H-2/H-1 스케줄러)
      // ═══════════════════════════════════════════════════════════
      // reconfirmRequest: 근로자에게 오늘 근무 확인 요청
      // [E-1 수정] FCMService와 동일하게 AttendanceCheckScreen으로 이동.
      // 이전: MyScheduleScreen (FCM과 불일치). 수정 후: AttendanceCheckScreen (일관성 확보).
      // 스테일 방어: reconfirmRespondedAt != null → "이미 처리된 요청" 안내 후 MyScheduleScreen 이동
      case NotificationType.reconfirmRequest:
        await _openReconfirmFromNotification(context, notification);
        break;

      // reconfirmAdminWarning: 출근 미확인 경고 → 관리자에게만 발송 — ADMIN_ONLY
      // reconfirmDeclined: 재확인 거절(근무 취소) → 관리자에게만 발송 — ADMIN_ONLY
      // USER 수신 시 에러 토스트 (MyScheduleScreen 폴백 금지)
      case NotificationType.reconfirmAdminWarning:
      case NotificationType.reconfirmDeclined:
        if (isUser) {
          ToastHelper.showWarning('현재 처리할 수 없는 알림입니다.');
        } else {
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: notification.data?['businessId']?.toString(),
            requiredPermission: (p) => p.canManageWorkers,
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
                initialBusinessId: notification.data?['businessId']?.toString(),
                notificationType: notification.type.name,
              )),
            );
          }
        }
        break;

      // ═══════════════════════════════════════════════════════════
      // 멤버 초대 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.memberInvitationReceived:
        await _handleMemberInvitation(context, notification);
        break;

      case NotificationType.memberInvitationAccepted:
      case NotificationType.memberInvitationRejected:
        // 초대 수락/거절 결과는 통합 인력 관리 화면에서 확인 — 의도된 설계.
        // SubAdmin은 알림 발송 후 권한이 취소됐을 수 있으므로 businessId 멤버십 재검증.
        {
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: notification.data?['businessId']?.toString(),
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
                initialBusinessId: notification.data?['businessId']?.toString(),
                notificationType: notification.type.name,
              )),
            );
          }
        }
        break;

      // ═══════════════════════════════════════════════════════════
      // 급여 관련 알림 — 모두 MyScheduleScreen으로 통일
      // · wageConfirmed / wageCancelConfirmed / retroactiveDeductionAlert / wageTransferred
      //   → 근무 일정·확정 금액·송금 내역 확인 목적
      // ═══════════════════════════════════════════════════════════
      case NotificationType.wageConfirmed:
      case NotificationType.wageCancelConfirmed:
      case NotificationType.retroactiveDeductionAlert:
      case NotificationType.wageTransferred:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;

      case NotificationType.reviewReceived:
        if (isUser) {
          // "리뷰 받았습니다" → 내 근무 평가 화면에서 직접 확인
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyReviewsScreen()),
          );
        } else {
          // AdminReviewListScreen은 별도 businessId 파라미터 없이 목록 조회 — businessIdRequired: false
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: notification.data?['businessId']?.toString(),
            requiredPermission: (p) => p.canManageWorkers,
            businessIdRequired: false,
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AdminReviewListScreen()),
            );
          }
        }
        break;

      // 리뷰 작성 요청 — requestKey로 review_requests 조회 후 다이얼로그 직접 표시
      case NotificationType.reviewRequest:
        await _openReviewDialogFromNotification(context, notification, isUser);
        break;
      // ═══════════════════════════════════════════════════════════
      // 중간정산 관련 알림
      // · interimSettlementRequested → 관리자에게 발송
      // · interimSettlementApproved / Rejected → 근로자에게 발송
      // ═══════════════════════════════════════════════════════════
      // interimSettlementRequested: 근로자→관리자 발송 — ADMIN_ONLY
      // USER 수신 시 에러 토스트 (MyRequestsDialog 폴백 금지)
      // [FCM-ROUTE-01] destination 교체: IntegratedWorkforceScreen → PayrollPaymentDashboardScreen(tab 3)
      case NotificationType.interimSettlementRequested:
        if (isUser) {
          ToastHelper.showWarning('현재 처리할 수 없는 알림입니다.');
        } else {
          final targetBusinessId = notification.data?['businessId']?.toString();
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: targetBusinessId,
            requiredPermission: (p) => p.canManageWage,
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            // 중간정산 관리 canonical destination: 급여 지급 현황 대시보드 tab 3
            // year/month: settlement tab query는 businessId 기준(month-free), DateTime.now() fallback 안전.
            final now = DateTime.now();
            final route = MaterialPageRoute<void>(
              builder: (_) => PayrollPaymentDashboardScreen(
                businessId: targetBusinessId ?? '',
                year: now.year,
                month: now.month,
                initialTab: 3,
                showPendingSettlementOnly: true,
              ),
            );
            // Settlement tab canonical routing (Back: Dashboard → PayrollOverview)
            if (!AdminTabSwitcher.instance.switchToTabAndPush(AdminTabSwitcher.payrollTab, route)) {
              // Shell 미등록 fallback (NotificationScreen은 통상 Shell 내부라 비상용)
              Navigator.push(context, route);
            }
          }
        }
        break;

      case NotificationType.interimSettlementApproved:
      case NotificationType.interimSettlementRejected:
        // 승인/거절 결과 — MyScheduleScreen에서 급여·일정 확인 (FCM routing과 통일)
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;

      // 중간정산 완료 (관리자 직접 처리 경로) — 근로자에게 발송
      case NotificationType.interimSettlementCompleted:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;

      // 공고 만료 임박/만료됨 — 관리자(creatorUID)에게만 발송
      // USER가 혹시 수신한 경우 관리자 전용 화면 진입 차단
      // [DECOMMISSION] 연장하기 제거 — 다시 모집하기 → JobsRootScreen
      case NotificationType.toPostingExpiringTomorrow:
      case NotificationType.toPostingExpired:
        if (isUser) {
          ToastHelper.showWarning('관리자 전용 알림입니다.');
        } else {
          final access = await _validateAdminNotificationAccess(
            context,
            businessId: notification.data?['businessId']?.toString(),
            requiredPermission: (p) => p.canManageTo,
          );
          if (!context.mounted) return;
          if (_handleAdminAccess(access)) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const JobsRootScreen()),
            );
          }
        }
        break;

      // ═══════════════════════════════════════════════════════════
      // 일자리 발견 알림 — [Phase 8.1C] toMatch
      // FCMService와 동일: toId 있으면 공고 상세 직접 진입, 없으면 전체 공고 목록 폴백
      // ═══════════════════════════════════════════════════════════
      case NotificationType.toMatch:
        {
          final toMatchToId = notification.data?['toId']?.toString();
          if (toMatchToId != null && toMatchToId.isNotEmpty) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => JobPostingScreen(toId: toMatchToId)),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const AllTOListScreen()),
            );
          }
        }
        break;

      case NotificationType.systemNotice:
      case NotificationType.other:
        // 시스템 공지·기타: 내용은 알림 카드에 이미 표시됨 — 별도 화면 이동 없음
        break;
    }
    } finally {
      // 예외·정상 완료 모두 플래그 해제 — mounted 여부와 무관하게 해제해야
      // 동일 인스턴스가 재마운트됐을 때 첫 탭이 영구 차단되는 문제를 막는다.
      _isHandlingTap = false;
    }
  }

  /// 알림에서 계약서 서명 화면 열기 (근무자용)
  Future<void> _openContractSignFromNotification(
    BuildContext context,
    NotificationModel notification,
  ) async {
    final contractId = notification.data?['contractId']?.toString();
    final applicationId = notification.data?['applicationId']?.toString();

    // contractId / applicationId 둘 다 없으면 내 지원 목록으로 이동
    if ((contractId == null || contractId.isEmpty) &&
        (applicationId == null || applicationId.isEmpty)) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
      );
      return;
    }

    // async gap 이전에 context 의존 값 추출
    final currentUser = context.read<UserProvider>().currentUser;
    final nav = Navigator.of(context, rootNavigator: true); // 언마운트 후에도, showDialog와 동일한 루트 내비게이터로 팝

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: LoadingWidget()),
    );

    try {
      EmploymentContractModel? contract;

      // contractId 우선 — get 단건 조회, list 복합 쿼리 권한 문제 없음
      if (contractId != null && contractId.isNotEmpty) {
        contract = await ContractService().getById(contractId);
        // 본인 계약서인지 검증 (타인 contractId 주입 방어)
        if (contract != null && contract.workerId != currentUser?.uid) {
          if (nav.canPop()) nav.pop();
          if (context.mounted) ToastHelper.showError('본인의 계약서가 아닙니다');
          return;
        }
      }

      // fallback: contractId 없으면 계약서 조회 불가 (USER list 권한 없음)
      // contractId는 계약서 서명 요청 알림 생성 시 항상 포함되어야 함
      if (contract == null && applicationId != null && applicationId.isNotEmpty) {
        // contractId로 조회 실패 = 계약서 삭제됐거나 권한 없음 → 안내 + 내 지원 목록으로 이동
        if (nav.canPop()) nav.pop();
        if (context.mounted) {
          ToastHelper.showError('계약서를 찾을 수 없습니다. 삭제됐거나 권한이 없습니다.');
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
          );
        }
        return;
      }

      if (nav.canPop()) nav.pop();
      if (!context.mounted) return;

      if (contract == null) {
        ToastHelper.showError('계약서를 찾을 수 없습니다');
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
        );
        return;
      }

      // [D-1 수정] 계약서 현재 상태 재확인 — 알림 발송 후 상태가 변경된 경우 방어
      // 알림이 발송된 뒤 관리자가 계약서를 취소/수정했거나 근무자가 이미 서명한 경우를 처리
      if (contract.status == ContractStatus.voided) {
        ToastHelper.showWarning('취소된 계약서입니다. 계약서 목록에서 확인하세요.');
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserContractsScreen()),
        );
        return;
      }
      if (!contract.needsWorkerSignature) {
        // pendingEmployer(관리자 서명 대기) 또는 completed(이미 양쪽 서명 완료) 상태
        ToastHelper.showInfo('이미 서명이 완료된 계약서입니다. 계약서 목록에서 확인하세요.');
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserContractsScreen()),
        );
        return;
      }

      // [B-5] 서명 완료 후 알림 읽음 처리 — pop 반환값으로 서명 완료 여부 확인
      final nonNullContract = contract; // null 체크 통과 후 — 람다 내 타입 승격 불가 우회
      final notifProvider = context.read<NotificationProvider>(); // async gap 전 참조 고정
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ContractSignScreen(contract: nonNullContract, role: 'worker'),
        ),
      ).then((result) {
        if (mounted && result != null) {
          notifProvider.markAsRead(notification.id);
        }
      });
    } catch (e) {
      if (nav.canPop()) nav.pop();
      if (context.mounted) ToastHelper.showError('계약서를 불러오는데 실패했습니다');
    }
  }

  /// [E-1 수정] 재확인 요청 알림 탭 — AttendanceCheckScreen으로 이동
  ///
  /// 스테일 방어: applicationId로 현재 지원 상태를 재조회해
  /// `reconfirmRespondedAt`이 이미 설정된 경우 "이미 처리된 요청" 안내 후 MyScheduleScreen으로 이동.
  ///
  /// FCMService의 `reconfirmRequest` 케이스도 AttendanceCheckScreen으로 이동하므로,
  /// 이 메서드와 동일한 목적지를 사용해 FCM 탭 / 알림함 탭 일관성을 보장한다.
  Future<void> _openReconfirmFromNotification(
    BuildContext context,
    NotificationModel notification,
  ) async {
    final applicationId = notification.data?['applicationId']?.toString();

    // applicationId가 있으면 스테일 상태 체크 (없으면 바로 AttendanceCheckScreen 이동)
    if (applicationId != null && applicationId.isNotEmpty) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('applications')
            .doc(applicationId)
            .get();

        if (!context.mounted) return;

        if (doc.exists) {
          final data = doc.data();
          final respondedAt = data?['reconfirmRespondedAt'];
          if (respondedAt != null) {
            // 이미 처리된 요청 — 안내 후 MyScheduleScreen 이동
            ToastHelper.showInfo('이미 처리된 근무 확인 요청입니다.');
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
            );
            return;
          }
        }
      } catch (e) {
        // Firestore 조회 실패 시 스테일 체크 생략 — AttendanceCheckScreen 계속 진행
        debugPrint('[_openReconfirmFromNotification] applicationId 조회 실패: $e');
      }
    }

    if (!context.mounted) return;
    // 처리되지 않은 요청 → AttendanceCheckScreen (오늘 근무 로드, 재확인 UI 포함)
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AttendanceCheckScreen()),
    );
  }

  /// 리뷰 작성 요청 알림 탭 — requestKey로 review_requests 조회 후 다이얼로그 직접 표시
  Future<void> _openReviewDialogFromNotification(
    BuildContext context,
    NotificationModel notification,
    bool isUser,
  ) async {
    final requestKey = notification.data?['requestKey']?.toString();

    // requestKey 없으면 목록 화면으로 폴백
    if (requestKey == null || requestKey.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => isUser ? const MyScheduleScreen() : const AdminReviewListScreen(),
        ),
      );
      return;
    }

    final navReview = Navigator.of(context, rootNavigator: true); // 언마운트 후에도, showDialog와 동일한 루트 내비게이터로 팝

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: LoadingWidget()),
    );

    try {
      final reviewService = MonthlyReviewService();
      final ReviewRequestModel? req = await reviewService.getReviewRequest(requestKey);

      if (req == null) {
        if (navReview.canPop()) navReview.pop();
        if (context.mounted) {
          ToastHelper.showError('리뷰 요청 정보를 찾을 수 없습니다');
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => isUser ? const MyScheduleScreen() : const AdminReviewListScreen(),
            ),
          );
        }
        return;
      }

      if (!context.mounted) {
        if (navReview.canPop()) navReview.pop();
        return;
      }

      // [G-13 UX guard] 이미 작성한 리뷰 알림을 재탭했을 때 빈 폼이 열리지 않도록 클라이언트 차단.
      // 서버는 결정론적 reviewKey + Firestore 트랜잭션으로 중복 생성을 원천 차단함.
      // 여기서의 차단은 UX 개선 레이어이며 서버 검증을 대체하지 않는다.
      final bool alreadySubmitted = isUser
          ? req.workerStatus == ReviewPartyStatus.submitted
          : req.adminStatus == ReviewPartyStatus.submitted;
      if (alreadySubmitted) {
        if (navReview.canPop()) navReview.pop();
        if (context.mounted) ToastHelper.showInfo('이미 작성한 리뷰입니다.');
        return;
      }

      final currentUser = context.read<UserProvider>().currentUser;
      if (currentUser == null) {
        if (navReview.canPop()) navReview.pop();
        if (context.mounted) ToastHelper.showError('사용자 정보를 찾을 수 없습니다');
        return;
      }
      if (!context.mounted) {
        if (navReview.canPop()) navReview.pop();
        return;
      }

      final yearMonthStr =
          '${req.reviewYear}-${req.reviewMonth.toString().padLeft(2, '0')}';

      // attendance 기반 실제 근무일 수 조회 (로딩 유지)
      int workDaysInMonth = 0;
      String? workerGender;
      int? workerAge;

      try {
        if (!isUser) {
          // 관리자: worker 프로필 + attendance CF 경유 병렬 조회
          final attendanceCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('callableGetAdminAttendances',
                  options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
          final results = await Future.wait([
            FirebaseFirestore.instance.collection('users').doc(req.workerId).get(),
            attendanceCallable.call<Map<String, dynamic>>({
              'businessId': req.businessId,
              'yearMonth': yearMonthStr,
              'userId': req.workerId,
            }),
          ]);
          final userSnap = results[0] as DocumentSnapshot<Map<String, dynamic>>;
          if (userSnap.exists && userSnap.data() != null) {
            final worker = UserModel.fromMap(userSnap.data()!, userSnap.id);
            workerGender = worker.gender;
            workerAge = worker.age;
          }
          final cfResult = results[1] as HttpsCallableResult<Map<String, dynamic>>;
          final cfItems = (cfResult.data['items'] as List<dynamic>? ?? []);
          workDaysInMonth = cfItems.whereType<Map>().where((e) {
            final status = e['wageStatus'] as String?;
            return status == 'confirmed' || status == 'transferred';
          }).length;
        } else {
          // 근무자: CF 프록시로 조회 (직접 list 불허 — Firestore 규칙)
          final attendances = await FirestoreService().getMyMonthlyAttendances(
            userId: currentUser.uid,
            year: req.reviewYear,
            month: req.reviewMonth,
          );
          workDaysInMonth = attendances
              .where((a) =>
                  a.businessId == req.businessId &&
                  (a.isWageConfirmed || a.isWageTransferred))
              .length;
        }
      } catch (e) {
        debugPrint('❌ 리뷰 요청 정보 로드 실패: $e');
        if (context.mounted) {
          if (navReview.canPop()) navReview.pop();
          ToastHelper.showError('리뷰 정보를 불러오는데 실패했습니다');
        }
        return; // 불완전한 데이터로 리뷰 다이얼로그 열지 않음
      }

      if (navReview.canPop()) navReview.pop(); // 로딩 닫기 — 모든 데이터 준비 후
      if (!context.mounted) return;

      if (!isUser) {
        // 관리자 → 근무자 리뷰 다이얼로그
        await showMonthlyReviewDialog(
          context,
          reviewerId: currentUser.uid,
          reviewerName: currentUser.name,
          businessId: req.businessId,
          businessName: req.businessName,
          targetUserId: req.workerId,
          targetUserName: req.workerName,
          targetUserGender: workerGender,
          targetUserAge: workerAge,
          reviewYear: req.reviewYear,
          reviewMonth: req.reviewMonth,
          workDaysInMonth: workDaysInMonth,
          requestId: req.id,
        );
      } else {
        // 근무자 → 사업장 리뷰 다이얼로그
        await showBusinessReviewDialog(
          context,
          reviewerId: currentUser.uid,
          businessId: req.businessId,
          businessName: req.businessName,
          reviewYear: req.reviewYear,
          reviewMonth: req.reviewMonth,
          workDaysInMonth: workDaysInMonth,
          requestId: req.id,
        );
      }
    } catch (e) {
      if (navReview.canPop()) navReview.pop();
      if (context.mounted) ToastHelper.showError('리뷰 정보를 불러오는데 실패했습니다');
    }
  }

  /// 내 요청 다이얼로그 표시
  void _showMyRequestsDialog(BuildContext context, String? uid) {
    if (uid == null) {
      ToastHelper.showError('사용자 정보를 찾을 수 없습니다');
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => MyRequestsDialog(
        applicantUid: uid,
        onChanged: () {},
      ),
    );
  }

  /// 신분증 열람 승인/거절 알림 → 해당 근무자 상세 다이얼로그
  Future<void> _openWorkerDetailFromNotification(
    BuildContext context,
    String workerId,
    String? businessId,
  ) async {
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: LoadingWidget()),
    );
    UserModel? user;
    Object? loadError;
    try {
      user = await AuthService().getUserData(workerId);
    } catch (e) {
      loadError = e;
    } finally {
      if (nav.mounted && nav.canPop()) nav.pop();
    }

    if (loadError != null) {
      if (context.mounted) ToastHelper.showError('근무자 정보를 불러오는 중 오류가 발생했습니다');
      return;
    }
    if (!context.mounted) return;
    if (user == null) {
      ToastHelper.showError('근무자 정보를 불러올 수 없습니다');
      return;
    }
    await WorkerDetailDialog.show(
      context: context,
      user: user,
      businessId: businessId,
    );
  }

  /// 하위 관리자 초대 수락/거절 처리
  Future<void> _handleMemberInvitation(
    BuildContext context,
    NotificationModel notification,
  ) async {
    final invitationId = notification.data?['invitationId']?.toString();
    if (invitationId == null || invitationId.isEmpty) {
      ToastHelper.showError('초대 정보를 찾을 수 없습니다');
      return;
    }

    final navInvite = Navigator.of(context, rootNavigator: true); // 언마운트 후에도, showDialog와 동일한 루트 내비게이터로 팝

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: LoadingWidget()),
    );

    try {
      final invitation = await MemberService().getInvitation(invitationId);

      if (navInvite.canPop()) navInvite.pop();
      if (!context.mounted) return;

      // [BUG-M-01 수정] 만료 초대도 여기서 차단 — acceptInvitation 서버 레이어도 막지만
      // 팝업을 보여준 뒤 오류 토스트로 끝나는 불필요한 UX를 방지
      final isExpired = invitation != null &&
          DateTime.now().isAfter(invitation.createdAt.add(const Duration(days: 3)));
      if (invitation == null || !invitation.isPending || isExpired) {
        ToastHelper.showError(
          isExpired ? '초대 유효기간(3일)이 만료되었습니다.' : '이미 처리된 초대입니다',
        );
        return;
      }

      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StyledDialog(
          title: '${invitation.businessName} 초대',
          icon: Icons.person_add_outlined,
          headerColor: AppColors.teal,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${invitation.invitedByName}님이 하위 관리자로 초대했습니다.',
                style: ResponsiveHelper.bodyStyle(ctx),
              ),
              SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
              StyledDialogInfoCard.info(
                '부여 권한\n${invitation.permissions.summaryText}',
              ),
            ],
          ),
          actions: [
            StyledDialogButton.cancel(
              text: '거절',
              onPressed: () => Navigator.pop(ctx, false),
            ),
            StyledDialogButton.primary(
              text: '수락',
              onPressed: () => Navigator.pop(ctx, true),
            ),
          ],
        ),
      );

      if (result == null || !context.mounted) return;

      final navInvite2 = Navigator.of(context, rootNavigator: true); // 두 번째 다이얼로그용 사전 캡처

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const PopScope(canPop: false, child: LoadingWidget()),
      );

      if (result) {
        await MemberService().acceptInvitation(invitation);
        if (navInvite2.canPop()) navInvite2.pop();
        if (!context.mounted) return;

        // onMemberInvitationAccepted CF 트리거가 subAdminBusinessIds를 기록하기 전에
        // refreshUserData()를 호출하면 isSubAdmin=false 상태로 읽힘.
        // UserProvider를 사전 캡처해 await 후에도 context 없이 접근 가능하게 함.
        final userProvider = context.read<UserProvider>();
        await userProvider.refreshUserData();

        // CF 트리거 완료까지 최대 6초(4회 × 1.5초) 폴링 — isSubAdmin이 true가 되면 즉시 종료
        if (!userProvider.isSubAdmin) {
          for (int i = 0; i < 4; i++) {
            await Future.delayed(const Duration(milliseconds: 1500));
            await userProvider.refreshUserData();
            if (userProvider.isSubAdmin) break;
          }
        }

        if (!context.mounted) return;
        if (userProvider.isSubAdmin) {
          // [PD-01] 초대 수락 완료 → 관리자 모드 전환 CTA 다이얼로그
          final switchNow = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (ctx) => StyledDialog(
              title: '초대 수락 완료',
              icon: Icons.admin_panel_settings_outlined,
              headerColor: AppColors.teal,
              content: Text(
                '${invitation.businessName} 관리자로 초대를 수락했습니다.\n지금 관리자 모드로 전환하시겠습니까?',
                style: ResponsiveHelper.bodyStyle(ctx),
              ),
              actions: [
                StyledDialogButton.cancel(
                  text: '나중에',
                  onPressed: () => Navigator.pop(ctx, false),
                ),
                StyledDialogButton.primary(
                  text: '관리자 모드로 전환',
                  onPressed: () => Navigator.pop(ctx, true),
                ),
              ],
            ),
          );
          if (switchNow == true && context.mounted) {
            await userProvider.switchToAdminMode(invitation.businessId);
            // switchToAdminMode → notifyListeners() → AuthWrapper 반응형 라우팅 → BusinessAdminShell
          }
        } else {
          ToastHelper.showSuccess('초대를 수락했습니다. 잠시 후 앱을 재시작하면 관리자 모드를 사용할 수 있어요.');
        }
      } else {
        await MemberService().rejectInvitation(invitation);
        if (navInvite2.canPop()) navInvite2.pop();
        if (context.mounted) ToastHelper.showSuccess('초대를 거절했습니다');
      }
    } catch (e) {
      if (navInvite.canPop()) navInvite.pop();
      if (context.mounted) {
        // [D05] 만료·이미처리된 초대는 Exception 메시지를 그대로 표시 (acceptInvitation 참고)
        final message = e is Exception
            ? e.toString().replaceFirst('Exception: ', '')
            : '초대 처리 중 오류가 발생했습니다';
        ToastHelper.showError(message);
      }
    }
  }

  /// 알림에서 지원자 관리 다이얼로그 열기
  // workDate가 있는 알림 → DayApplicantsDialog (날짜 기준 지원자 관리)
  Future<void> _openDayApplicantsDialog(
    BuildContext context,
    DateTime date,
    String? preferredBusinessId,
  ) async {
    final up = context.read<UserProvider>();
    final uid = up.currentUser?.uid;
    if (uid == null) return;

    final nav = Navigator.of(context, rootNavigator: true);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: LoadingWidget()),
    );

    try {
      final fsService = FirestoreService();
      List<BusinessModel> businesses;
      if (up.isSubAdmin && up.effectiveBusinessId != null) {
        final biz = await fsService.getBusinessById(up.effectiveBusinessId!);
        businesses = biz != null ? [biz] : [];
      } else {
        businesses = await fsService.getMyBusiness(uid);
      }

      if (nav.canPop()) nav.pop();
      if (!context.mounted) return;

      if (businesses.isEmpty) {
        ToastHelper.showWarning('등록된 사업장이 없습니다');
        return;
      }

      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => DayApplicantsDialog(
          date: date,
          businessIds: businesses.map((b) => b.id).toList(),
          businesses: businesses,
        ),
      );
    } catch (e) {
      if (nav.canPop()) nav.pop();
      debugPrint('❌ DayApplicantsDialog 로드 실패: $e');
      if (!context.mounted) return;
      ToastHelper.showError('데이터를 불러오는데 실패했습니다');
    }
  }

  // ══════════════════════════════════════════════════════════════════
  // 관리자 알림 접근 검증 헬퍼
  // ══════════════════════════════════════════════════════════════════

  /// 관리자 알림 탭 시 접근 권한을 3단계로 재검증한다.
  ///
  /// 검증 순서:
  ///   1. 순수 USER(SubAdmin 아님) 차단 → invalidContext
  ///   2. businessId 필수이나 누락 → noBusinessId
  ///   3. BUSINESS_ADMIN → 항상 허용
  ///   4. SubAdmin: businessId가 현재 subAdminBusinessIds에 포함되는지 → noBusinessAccess
  ///   5. SubAdmin: 해당 사업장의 현재 MemberPermissions 확인 → noPermission
  ///      * 현재 선택된 사업장과 일치하고 권한이 로드됐으면 캐시 사용
  ///      * 다른 사업장이거나 캐시 미로드 → Firestore에서 직접 조회 (다중 사업장 정확도 보장)
  ///
  /// [requiredPermission] null이면 멤버십만 확인하고 permission 체크 생략.
  /// [businessIdRequired] false면 businessId 누락 시에도 허용.
  Future<_AdminAccessResult> _validateAdminNotificationAccess(
    BuildContext context, {
    required String? businessId,
    bool Function(MemberPermissions p)? requiredPermission,
    bool businessIdRequired = true,
  }) async {
    final up = context.read<UserProvider>();

    // 1. 순수 USER(SubAdmin 아님) → invalidContext
    if (up.isUser && !up.isSubAdmin) return _AdminAccessResult.invalidContext;

    // 2. businessId 필수이나 누락 → noBusinessId
    if (businessIdRequired && (businessId == null || businessId.isEmpty)) {
      return _AdminAccessResult.noBusinessId;
    }

    // 3. BUSINESS_ADMIN → 항상 허용 (권한 재검증 불필요)
    if (!up.isSubAdmin) return _AdminAccessResult.allowed;

    // 4. SubAdmin: businessId 멤버십 재검증
    if (businessId != null && businessId.isNotEmpty) {
      final inList = up.currentUser?.subAdminBusinessIds.contains(businessId) ?? false;
      if (!inList) return _AdminAccessResult.noBusinessAccess;
    }

    // 5. SubAdmin: 해당 사업장 현재 Permission 재검증
    if (requiredPermission != null && businessId != null && businessId.isNotEmpty) {
      final uid = up.currentUser?.uid;
      if (uid == null) return _AdminAccessResult.noPermission;

      // 현재 선택된 사업장 = 알림 사업장이고 권한이 이미 로드됐으면 캐시 사용 (네트워크 절약)
      if (up.permissionsLoaded && up.selectedSubAdminBusinessId == businessId) {
        if (!up.can(requiredPermission)) return _AdminAccessResult.noPermission;
      } else {
        // 다른 사업장이거나 캐시 미로드 → Firestore 직접 조회 (다중 사업장 정확도 보장)
        try {
          final perms = await MemberService().getMemberPermissions(businessId, uid);
          if (perms == null || !requiredPermission(perms)) {
            return _AdminAccessResult.noPermission;
          }
        } catch (e) {
          debugPrint('[_validateAdminNotificationAccess] 권한 조회 실패: $e');
          return _AdminAccessResult.noPermission;
        }
      }
    }

    return _AdminAccessResult.allowed;
  }

  /// 검증 결과에 따른 사용자 메시지 표시 후 접근 허용 여부 반환.
  /// true → 화면 이동 진행, false → 차단.
  bool _handleAdminAccess(_AdminAccessResult result) {
    switch (result) {
      case _AdminAccessResult.allowed:
        return true;
      case _AdminAccessResult.noBusinessAccess:
        ToastHelper.showWarning('해당 사업장에 대한 관리자 권한이 없습니다.');
        return false;
      case _AdminAccessResult.noPermission:
        ToastHelper.showWarning('이 업무를 처리할 권한이 없습니다.');
        return false;
      case _AdminAccessResult.noBusinessId:
        ToastHelper.showWarning('알림 정보를 확인할 수 없습니다.');
        return false;
      case _AdminAccessResult.invalidContext:
        ToastHelper.showWarning('현재 처리할 수 없는 알림입니다.');
        return false;
    }
  }

  Future<void> _openWorkApplicantsFromNotification(
    BuildContext context,
    NotificationModel notification,
  ) async {
    // 심층 방어: 호출부 isUser && !isSubAdmin 가드 외 함수 진입부에서도 재차 확인
    // tos 직접 GET을 수행하므로 순수 USER 역할이 도달하면 데이터 노출 위험이 있다.
    // SubAdmin은 role==USER이지만 관리자 알림을 수신하므로 통과 (isSubAdmin 제외 필수)
    final up = context.read<UserProvider>();
    if (up.isUser && !up.isSubAdmin) return;


    final data = notification.data;
    final fallbackBusinessId = data?['businessId']?.toString();

    // workDate가 있는 경우 → 날짜 기준 지원자 관리 다이얼로그로 직행
    final workDateStr = data?['workDate']?.toString();
    final workDate = workDateStr != null ? DateTime.tryParse(workDateStr) : null;
    if (workDate != null) {
      await _openDayApplicantsDialog(context, workDate, fallbackBusinessId);
      return;
    }

    if (data == null) {
      ToastHelper.showWarning('알림 정보를 확인할 수 없습니다.');
      return;
    }

    final toId = data['toId']?.toString();
    final workDetailId = data['workDetailId']?.toString();

    if (toId == null || toId.isEmpty || workDetailId == null || workDetailId.isEmpty) {
      ToastHelper.showWarning('알림 정보를 확인할 수 없습니다.');
      return;
    }

    final navWA = Navigator.of(context, rootNavigator: true); // 언마운트 후에도, showDialog와 동일한 루트 내비게이터로 팝

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(canPop: false, child: LoadingWidget()),
    );

    try {
      final toDoc = await FirebaseFirestore.instance.collection('tos').doc(toId).get();

      if (!toDoc.exists) {
        if (navWA.canPop()) navWA.pop();
        if (!context.mounted) return;
        ToastHelper.showError('공고를 찾을 수 없습니다');
        return;
      }

      final toData = toDoc.data();
      if (toData == null) {
        if (navWA.canPop()) navWA.pop();
        if (!context.mounted) return;
        ToastHelper.showError('공고 데이터를 불러올 수 없습니다');
        return;
      }
      final to = TOModel.tryFromMap(toData, toId);
      if (to == null) {
        if (navWA.canPop()) navWA.pop();
        if (!context.mounted) return;
        ToastHelper.showError('공고 데이터를 불러올 수 없습니다');
        return;
      }

      // workDetails는 tos/{toId}의 배열 필드 — 서브컬렉션이 아님.
      // 알림의 workDetailId는 id(workType_start_end 합성키) 또는 legacyId(workType)일 수 있음.
      final workDetail = to.workDetails.cast<WorkDetailModel?>().firstWhere(
        (wd) => wd?.id == workDetailId || wd?.legacyId == workDetailId,
        orElse: () => null,
      );

      if (workDetail == null) {
        if (navWA.canPop()) navWA.pop();
        if (!context.mounted) return;
        ToastHelper.showError('업무 정보를 찾을 수 없습니다');
        return;
      }

      final toItem = TOItem(
        to: to,
        workDetails: [workDetail],
        confirmedCount: workDetail.currentCount,
        pendingCount: workDetail.pendingCount,
        totalRequired: workDetail.requiredCount,
        isWorkDetailLoaded: true,
      );

      if (navWA.canPop()) navWA.pop();
      if (!context.mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) return;
        // workDate: 알림 data에 저장된 ISO 문자열 → 파싱 실패 시 null(헤더 TO 날짜 폴백)
        final workDateStr = data['workDate']?.toString();
        final initialDate = workDateStr != null
            ? DateTime.tryParse(workDateStr)
            : null;
        await showDialog<WorkApplicantsDialogResult>(
          context: context,
          barrierDismissible: false,
          builder: (_) => WorkApplicantsDialog(
            work: workDetail,
            toItem: toItem,
            onChanged: () {},
            // 지원/지원취소 알림에서 특정 지원자를 맨 앞에 하이라이트
            initialApplicationId: data['applicationId']?.toString(),
            initialDate: initialDate,
          ),
        );
      });
    } catch (e) {
      if (navWA.canPop()) navWA.pop();
      debugPrint('❌ 알림 네비게이션 실패: $e');
      if (!context.mounted) return;
      ToastHelper.showError('데이터를 불러오는데 실패했습니다');
    }
  }
}
