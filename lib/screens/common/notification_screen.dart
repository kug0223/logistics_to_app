import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/notification_provider.dart';
import '../../models/core/notification_model.dart';
import '../../widgets/common/notification_card.dart';
import '../../widgets/common/app_tab_label.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../providers/user_provider.dart';
// 네비게이션 대상 화면들
import '../user/my_applications_screen.dart';
import '../user/my_schedule_screen.dart';
import '../user/user_contracts_screen.dart';
import '../user/dialogs/my_requests_dialog.dart';
import '../business_admin/workforce_management/integrated_workforce_screen.dart';
import '../contract/contract_sign_screen.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../models/core/to_model.dart';
import '../../models/core/work_detail_model.dart';
import '../../models/ui/admin_to_list_ui_models.dart';
import '../business_admin/dialogs/work_applicants_dialog.dart';
import '../business_admin/dialogs/fixed_worker_management_dialog.dart';
import '../../models/core/employment_contract_model.dart';
import '../../services/contract_service.dart';
import '../../services/member_service.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/loading_widget.dart';
import '../business_admin/admin_review_list_screen.dart';
import '../business_admin/admin_contract_management_screen.dart';
import '../../services/monthly_review_service.dart';
import '../../models/core/review_request_model.dart';
import '../../models/core/user_model.dart';
import '../../widgets/dialogs/monthly_review_dialog.dart';
import '../../widgets/dialogs/business_review_dialog.dart';
import '../../services/firestore_service.dart';

/// 알림 목록 화면 (전체 / 미읽음 탭)
class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _isHandlingTap = false;
  bool _isMarkingAllRead = false;

  @override
  Widget build(BuildContext context) {
    return Consumer<NotificationProvider>(
      builder: (context, provider, _) {
        if (provider.loadMoreFailed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && provider.loadMoreFailed) {
              ToastHelper.showError('알림을 더 불러오지 못했습니다');
              provider.clearLoadMoreError();
            }
          });
        }
        final unreadList = provider.notifications.where((n) => !n.isRead).toList();

        return DefaultTabController(
          length: 2,
          child: GradientScaffold(
            title: '알림',
            showNotificationBell: false,
            headerBottom: TabBar(
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: Colors.white,
              indicatorWeight: 2.5,
              dividerColor: Colors.transparent,
              tabs: [
                Tab(
                  child: AppTabLabel(
                    label: '전체',
                    count: provider.notifications.length,
                    countSuffix: provider.hasMore ? '+' : '',
                    badgeColor: Colors.white,
                  ),
                ),
                Tab(
                  child: AppTabLabel(
                    label: '미읽음',
                    count: provider.unreadCount,
                    badgeColor: AppColors.error,
                    urgent: provider.hasUnread,
                  ),
                ),
              ],
            ),
            actions: [
              if (provider.hasUnread)
                TextButton(
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
                          } finally {
                            if (mounted) setState(() => _isMarkingAllRead = false);
                          }
                        },
                  child: Text(
                    '모두 읽음',
                    style: ResponsiveHelper.smallStyle(context, color: Colors.white),
                  ),
                ),
            ],
            body: _buildBody(context, provider, unreadList),
          ),
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    NotificationProvider provider,
    List<NotificationModel> unreadList,
  ) {
    if (provider.isLoading) {
      return const LoadingWidget(message: '알림 불러오는 중...');
    }
    if (provider.hasError) {
      return _buildErrorState(context, provider);
    }

    // [PERF-2026-07-16] rebuild당 _buildGroupedItems를 _buildBody에서 한 번만 계산
    final groupedAll = _buildGroupedItems(provider.notifications);
    final groupedUnread = _buildGroupedItems(unreadList);

    return TabBarView(
      children: [
        _buildList(
          context, provider, provider.notifications,
          grouped: groupedAll,
          hasMore: provider.hasMore,
          isLoadingMore: provider.isLoadingMore,
          onLoadMore: provider.loadMore,
        ),
        _buildList(
          context, provider, unreadList,
          grouped: groupedUnread,
          emptyMessage: '미읽음 알림이 없습니다',
          // 미읽음 탭은 클라이언트 필터 결과 — 별도 페이지네이션 없음
          // 전체 탭에 더 불러올 알림이 있으면 안내 문구만 표시
          hasMore: false,
          showLoadMoreHint: provider.hasMore,
        ),
      ],
    );
  }

  /// 날짜 기준으로 섹션 헤더(String) + 알림(NotificationModel) 혼합 리스트 생성
  List<Object> _buildGroupedItems(List<NotificationModel> notifications) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekAgo = today.subtract(const Duration(days: 7));

    final todayItems = <NotificationModel>[];
    final thisWeekItems = <NotificationModel>[];
    final olderItems = <NotificationModel>[];

    for (final n in notifications) {
      final date = DateTime(n.createdAt.year, n.createdAt.month, n.createdAt.day);
      if (!date.isBefore(today)) {
        todayItems.add(n);
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
        top: ResponsiveHelper.spacing(context, 16),
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
    bool hasMore = false,
    bool isLoadingMore = false,
    VoidCallback? onLoadMore,
    bool showLoadMoreHint = false,
  }) {
    if (notifications.isEmpty) {
      return AppEmptyState(
        icon: Icons.notifications_none,
        title: emptyMessage,
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        provider.reload();
        await Future.delayed(const Duration(milliseconds: 400));
      },
      child: ListView.builder(
        itemCount: grouped.length + (hasMore || showLoadMoreHint ? 1 : 0),
        padding: ResponsiveHelper.listPadding(context),
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
          return NotificationCard(
            key: Key(notification.id),
            notification: notification,
            onTap: () => _handleNotificationTap(context, notification, provider),
            onDismiss: () async {
              final success = await provider.deleteNotification(notification.id);
              if (!mounted) return;
              if (success) {
                ToastHelper.showSuccess('알림이 삭제되었습니다');
              } else {
                ToastHelper.showError('알림 삭제에 실패했습니다');
              }
            },
          );
        },
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
      case NotificationType.confirmationCanceled:
        if (isUser) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
          );
        } else {
          await _openWorkApplicantsFromNotification(context, notification);
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
      // USER가 이 타입의 알림을 수신한 경우(데이터 불일치 등) 관리자 다이얼로그 접근 차단.
      case NotificationType.newApplication:
      case NotificationType.applicationCanceled:
        if (isUser) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
          );
        } else {
          await _openWorkApplicantsFromNotification(context, notification);
        }
        break;

      // ═══════════════════════════════════════════════════════════
      // 스케줄 변경 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.scheduleChangeRequested:
        if (isUser) {
          _showMyRequestsDialog(context, userProvider.currentUser?.uid);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
              initialBusinessId: notification.data?['businessId']?.toString(),
            )),
          );
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

      // 근무자 서명 완료 — 관리자에게만 발송, 해당 사업장 계약서 관리 화면으로 이동
      // USER가 이 알림을 수신한 경우(데이터 불일치 등) 관리자 화면 접근 차단.
      // USER는 UserContractsScreen으로 폴백한다.
      case NotificationType.contractSigned:
        {
          if (isUser) {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const UserContractsScreen()),
            );
          } else {
            final businessId = notification.data?['businessId']?.toString();
            if (businessId != null && businessId.isNotEmpty) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminContractManagementScreen(businessId: businessId),
                ),
              );
            } else {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
                  initialBusinessId: notification.data?['businessId']?.toString(),
                )),
              );
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
          // 알림 data의 businessId 우선 — 다중 사업장 관리자가 다른 사업장 선택 중일 때 정확한 대화상자 표시
          final notifBusinessId = notification.data?['businessId']?.toString();
          final businessId = (notifBusinessId != null && notifBusinessId.isNotEmpty)
              ? notifBusinessId
              : userProvider.effectiveBusinessId;
          if (businessId != null) {
            showDialog(
              context: context,
              builder: (_) => FixedWorkerManagementDialog(
                initialBusinessId: businessId,
                onChanged: () {},
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
                initialBusinessId: notification.data?['businessId']?.toString(),
              )),
            );
          }
        }
        break;

      case NotificationType.contractRenewed:
      case NotificationType.contractTerminating:
        // 계약 연장·종료 통보는 근무자(isUser)에게만 발송되므로 isUser 분기 불필요 — 의도된 설계.
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
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
              initialBusinessId: notification.data?['businessId']?.toString(),
            )),
          );
        }
        break;

      case NotificationType.terminationApproved:
      case NotificationType.resignApproved:
      // terminationRejected: 계약해지 거절 전용 타입 — resignRejected와 라우팅은 같지만 알림 표시 분리
      case NotificationType.terminationRejected:
      case NotificationType.resignRejected:
        if (isUser) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyApplicationsScreen()),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
              initialBusinessId: notification.data?['businessId']?.toString(),
            )),
          );
        }
        break;

      case NotificationType.resignRequested:
      // contractRequested: 근무자→관리자 방향 알림 — 수신자는 항상 관리자이므로
      //           isUser 분기 없이 IntegratedWorkforceScreen 단일 경로로 처리.
      case NotificationType.contractRequested:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
            initialBusinessId: notification.data?['businessId']?.toString(),
          )),
        );
        break;

      // ═══════════════════════════════════════════════════════════
      // 신분증 열람 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.idCardAccessRequested:
        _showMyRequestsDialog(context, userProvider.currentUser?.uid);
        break;

      case NotificationType.idCardAccessApproved:
      case NotificationType.idCardAccessRejected:
      case NotificationType.idCardAccessExpiringSoon:
        if (isUser) {
          _showMyRequestsDialog(context, userProvider.currentUser?.uid);
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
              initialBusinessId: notification.data?['businessId']?.toString(),
            )),
          );
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
      // 멤버 초대 관련 알림
      // ═══════════════════════════════════════════════════════════
      case NotificationType.memberInvitationReceived:
        await _handleMemberInvitation(context, notification);
        break;

      case NotificationType.memberInvitationAccepted:
      case NotificationType.memberInvitationRejected:
        // 초대 수락/거절 결과는 통합 인력 관리 화면에서 확인 — 의도된 설계.
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
            initialBusinessId: notification.data?['businessId']?.toString(),
          )),
        );
        break;

      // ═══════════════════════════════════════════════════════════
      // 급여 관련 알림
      // · wageConfirmed(확정) / wageCancelConfirmed / retroactiveDeductionAlert
      //   → MyScheduleScreen: 근무 일정·확정 금액 확인 목적
      // · wageTransferred(실송금 완료) → UserContractsScreen: 급여 내역·이체 확인 목적
      //   [FCM-04 수정] fcm_service.dart M-001 수정(wageTransferred→UserContractsScreen)과
      //   이 화면의 라우팅(MyScheduleScreen)이 불일치하던 버그 수정
      // ═══════════════════════════════════════════════════════════
      case NotificationType.wageConfirmed:
      case NotificationType.wageCancelConfirmed:
      case NotificationType.retroactiveDeductionAlert:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
        );
        break;
      case NotificationType.wageTransferred:
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const UserContractsScreen()),
        );
        break;

      case NotificationType.reviewReceived:
        // [B-10] 관리자에게 reviewReceived 발송 시 탭 무반응 버그 수정
        if (isUser) {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const MyScheduleScreen()),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminReviewListScreen()),
          );
        }
        break;

      // 리뷰 작성 요청 — requestKey로 review_requests 조회 후 다이얼로그 직접 표시
      case NotificationType.reviewRequest:
        await _openReviewDialogFromNotification(context, notification, isUser);
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
    final nav = Navigator.of(context); // 언마운트 후에도 다이얼로그 닫기 위해 사전 캡처

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingWidget(),
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
        // getByApplication은 USER 역할에서 PERMISSION_DENIED 발생 — 단건 get 불가, 안내만 제공
        if (nav.canPop()) nav.pop();
        if (context.mounted) ToastHelper.showError('계약서 정보를 불러올 수 없습니다. 관리자에게 문의하세요.');
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

    final navReview = Navigator.of(context); // 언마운트 후에도 다이얼로그 닫기 위해 사전 캡처

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingWidget(),
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
          workDaysInMonth = cfItems.where((e) {
            final status = (e as Map)['wageStatus'] as String?;
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
          Navigator.pop(context);
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
      builder: (_) => MyRequestsDialog(
        applicantUid: uid,
        onChanged: () {},
      ),
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

    final navInvite = Navigator.of(context); // 언마운트 후에도 다이얼로그 닫기 위해 사전 캡처

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingWidget(),
    );

    try {
      final invitation = await MemberService().getInvitation(invitationId);

      if (navInvite.canPop()) navInvite.pop();
      if (!context.mounted) return;

      // [BUG-M-01 수정] 만료 초대도 여기서 차단 — acceptInvitation 서버 레이어도 막지만
      // 팝업을 보여준 뒤 오류 토스트로 끝나는 불필요한 UX를 방지
      final isExpired = invitation != null &&
          DateTime.now().isAfter(invitation.createdAt.add(const Duration(days: 30)));
      if (invitation == null || !invitation.isPending || isExpired) {
        ToastHelper.showError(
          isExpired ? '초대 유효기간(30일)이 만료되었습니다.' : '이미 처리된 초대입니다',
        );
        return;
      }

      final result = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('${invitation.businessName} 초대'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${invitation.invitedByName}님이 하위 관리자로 초대했습니다.'),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.grey50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '부여 권한',
                      style: ResponsiveHelper.smallStyle(ctx, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(invitation.permissions.summaryText),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('거절'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('수락'),
            ),
          ],
        ),
      );

      if (result == null || !context.mounted) return;

      final navInvite2 = Navigator.of(context); // 두 번째 다이얼로그용 사전 캡처

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const LoadingWidget(),
      );

      if (result) {
        await MemberService().acceptInvitation(invitation);
        if (navInvite2.canPop()) navInvite2.pop();
        if (!context.mounted) return;
        // context.read<>()는 await 전 동기 호출이므로 안전 — await 후 context.mounted 체크로 보호
        await context.read<UserProvider>().refreshUserData();
        if (!context.mounted) return;
        ToastHelper.showSuccess('초대를 수락했습니다. 잠시 후 관리자 모드를 사용할 수 있어요!');
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
    if (data == null) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
          initialBusinessId: fallbackBusinessId,
        )),
      );
      return;
    }

    final toId = data['toId']?.toString();
    final workDetailId = data['workDetailId']?.toString();

    if (toId == null || toId.isEmpty || workDetailId == null || workDetailId.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
          initialBusinessId: fallbackBusinessId,
        )),
      );
      return;
    }

    final navWA = Navigator.of(context); // 언마운트 후에도 다이얼로그 닫기 위해 사전 캡처

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const LoadingWidget(),
    );

    try {
      final toDoc = await FirebaseFirestore.instance.collection('tos').doc(toId).get();

      if (!toDoc.exists) {
        if (navWA.canPop()) navWA.pop();
        if (!context.mounted) return;
        ToastHelper.showError('공고를 찾을 수 없습니다');
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
            initialBusinessId: fallbackBusinessId,
          )),
        );
        return;
      }

      final toData = toDoc.data();
      if (toData == null) {
        if (navWA.canPop()) navWA.pop();
        if (!context.mounted) return;
        ToastHelper.showError('공고 데이터를 불러올 수 없습니다');
        Navigator.push(context, MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
          initialBusinessId: fallbackBusinessId,
        )));
        return;
      }
      final to = TOModel.tryFromMap(toData, toId);
      if (to == null) {
        if (navWA.canPop()) navWA.pop();
        if (!context.mounted) return;
        ToastHelper.showError('공고 데이터를 불러올 수 없습니다');
        Navigator.push(context, MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
          initialBusinessId: fallbackBusinessId,
        )));
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
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
            initialBusinessId: fallbackBusinessId,
          )),
        );
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
        await showDialog<WorkApplicantsDialogResult>(
          context: context,
          builder: (_) => WorkApplicantsDialog(
            work: workDetail,
            toItem: toItem,
            onChanged: () {},
            // 지원/지원취소 알림에서 특정 지원자를 맨 앞에 하이라이트
            initialApplicationId: data['applicationId']?.toString(),
          ),
        );
      });
    } catch (e) {
      if (navWA.canPop()) navWA.pop();
      debugPrint('❌ 알림 네비게이션 실패: $e');
      if (!context.mounted) return;
      ToastHelper.showError('데이터를 불러오는데 실패했습니다');
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => IntegratedWorkforceScreen(
          initialBusinessId: fallbackBusinessId,
        )),
      );
    }
  }
}
