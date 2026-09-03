import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/core/business_member_model.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../services/firestore_service.dart';
import '../../../controllers/workforce_controller.dart';
import 'workforce_list_view.dart';
import 'workforce_calendar_view.dart';
import '../../../widgets/common/gradient_scaffold.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/skeleton_widget.dart';
import '../../../theme/app_colors.dart';
import '../../../services/fcm_service.dart';
import '../business_list_screen.dart';


/// ✨ 세련된 통합 인력 관리 화면 (business_home_screen 테마 적용)
class IntegratedWorkforceScreen extends StatefulWidget {
  /// 알림 딥링크 등에서 특정 사업장을 초기 선택할 때 전달. null이면 effectiveBusinessId 사용.
  final String? initialBusinessId;

  /// [AUDIT.2R5] FCM·알림함 경유 진입 시 type 기반 세분화 권한 검사에 사용.
  /// null → 일반 탭·버튼 진입 (generic OR guard 적용).
  /// non-null → 해당 notification domain의 canonical permission만 허용.
  /// FCMService는 payload `screen` 문자열을 그대로 전달.
  /// NotificationScreen은 notification.type.name (Dart enum name)을 전달.
  final String? notificationType;

  const IntegratedWorkforceScreen({
    super.key,
    this.initialBusinessId,
    this.notificationType,
  });

  @override
  State<IntegratedWorkforceScreen> createState() =>
      _IntegratedWorkforceScreenState();
}

class _IntegratedWorkforceScreenState extends State<IntegratedWorkforceScreen>
    with WidgetsBindingObserver {
  final FirestoreService _firestoreService = FirestoreService();
  final WorkforceController _controller = WorkforceController();
  List<String> _allBusinessIds = [];
  String? _selectedBusinessId;
  bool _isCalendarView = false;
  static const _prefKey = 'workforce_view_is_calendar';
  bool _isLoading = true;
  bool _fetchInProgress = false;
  DateTime? _lastResumedAt; // 앱 복귀 시 2분 쿨다운 — 매 복귀마다 CF reload 방지

  late final VoidCallback _fcmRefreshCallback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // [AUDIT.2R2/2R3] 비동기 guard — FCM·notification 경로 포함 모든 진입 방어.
    // async FrameCallback: Future<void>를 void로 업캐스트 (Flutter 표준 패턴).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final up = context.read<UserProvider>();

      // ── [AUDIT.2R3] SUB_ADMIN 멀티 사업장 context 정렬 ──────────────────
      // FCMService / NotificationScreen이 initialBusinessId=A로 IWS를 push했지만
      // effectiveBusinessId=B인 경우, switchToAdminMode(A)로 context를 A로 전환한 뒤
      // A의 fresh permissions로 권한을 검사하고 A의 데이터를 로드한다.
      //
      // Invariant (SUB_ADMIN):
      //   Notification.businessId = Permission checked businessId
      //                           = Destination businessId = Loaded data businessId
      //
      // switchToAdminMode 내부: subAdminBusinessIds 포함 검증 + Firestore fresh load.
      // BUSINESS_ADMIN: isSubAdmin=false → 블록 전체 skip → can() 항상 true.
      final initialBizId = widget.initialBusinessId;
      if (up.isSubAdmin && initialBizId != null) {
        final inList = up.currentUser?.subAdminBusinessIds.contains(initialBizId) ?? false;
        if (!inList) {
          // 알림 businessId가 이 SUB_ADMIN의 사업장 목록에 없음 → 잘못된 알림 or 권한 회수
          ToastHelper.showWarning('이 업무를 처리할 권한이 없습니다.');
          Navigator.of(context).pop();
          return;
        }
        if (initialBizId != up.effectiveBusinessId) {
          // 다른 사업장 알림 → switchToAdminMode로 A로 전환 (fresh permissions 포함)
          await up.switchToAdminMode(initialBizId);
          if (!mounted) return;
        }
      }

      // ── [AUDIT.2R5] screen-level permission guard ─────────────────────
      // • notificationType != null (FCM·알림함 경유):
      //     _permissionForNotificationType()로 type별 canonical permission 검사.
      //     예: toInviteAccepted → canManageTo만 허용.
      //         canManageWorkers를 가진 SUB_ADMIN이라도 canManageTo 없으면 차단.
      //
      // • notificationType == null (일반 탭·버튼 진입):
      //     R4 generic OR guard — 4개 도메인 중 하나 이상 보유 시 허용.
      //
      // _permissionForNotificationType 반환값:
      //   non-null check → up.can(check) 결과로 허용·차단
      //   (p) => false   → up.can()이 BUSINESS_ADMIN에서 단락 true → OWNER-only 구현
      //   null           → generic OR guard로 fall through
      //
      // BUSINESS_ADMIN → up.can() 항상 true → 어떤 check에도 통과.
      // SUB_ADMIN 권한 0개 → generic OR 전체 false → 차단.
      final notifType = widget.notificationType;
      final bool hasPermission;
      if (notifType != null) {
        final specificCheck = _permissionForNotificationType(notifType);
        hasPermission = specificCheck != null
            ? up.can(specificCheck)
            : _hasGenericIwsPermission(up);
      } else {
        hasPermission = _hasGenericIwsPermission(up);
      }
      if (!hasPermission) {
        ToastHelper.showWarning('이 업무를 처리할 권한이 없습니다.');
        Navigator.of(context).pop();
        return;
      }
      _loadBusinessIds();
    });
    _fcmRefreshCallback = () { if (mounted) _controller.reload(context); };
    FCMService().addAdminRefreshListener(_fcmRefreshCallback);
  }

  // ── [AUDIT.2R5] 정적 권한 헬퍼 ─────────────────────────────────────
  // IWS는 FCMService·NotificationScreen 양쪽에서 진입 가능.
  // Notification 경유 시 type별 canonical permission을 단일 정의로 유지.

  /// 4개 도메인 중 하나라도 권한 있으면 허용 — 일반(탭·버튼) 진입용 generic guard.
  static bool _hasGenericIwsPermission(UserProvider up) =>
      up.can((p) => p.canManageTo) ||
      up.can((p) => p.canManageWorkers) ||
      up.can((p) => p.canManageContract) ||
      up.can((p) => p.canManageWage);

  /// Notification type string → canonical required MemberPermissions check.
  ///
  /// FCMService의 `screen` 값과 NotificationScreen의 `notification.type.name` 양쪽을 처리.
  /// (일부 type은 FCM screen key와 Dart enum name이 다름 — 예: 'contractRenewal' vs 'contractExpiringReminder')
  ///
  /// 반환값:
  ///   non-null check → 해당 permission 검사 (canManageTo / canManageWorkers / canManageContract / canManageWage)
  ///   (p) => false   → OWNER(BUSINESS_ADMIN) 전용 — up.can()의 단락 평가 활용 (SUB_ADMIN 전체 차단)
  ///   null           → generic guard로 fall through (알 수 없는 type)
  static bool Function(MemberPermissions)? _permissionForNotificationType(
      String type) {
    switch (type) {
      // ── TO 도메인 ──────────────────────────────────────────────────
      case 'toInviteAccepted':
      case 'toInviteDeclined':
      case 'toDetail': // TO 만료 임박 알림 IWS 폴백
        return (p) => p.canManageTo;

      // ── 계약 도메인 ────────────────────────────────────────────────
      // FCM key: 'contractRenewal'  ↔  enum name: 'contractExpiringReminder'
      case 'contractSigned':
      case 'contractRenewal':           // FCMService screen key
      case 'contractExpiringReminder':  // NotificationScreen enum name
      case 'contractRequested':
        return (p) => p.canManageContract;

      // ── 임금 도메인 ────────────────────────────────────────────────
      // FCM key: 'interimSettlementAdmin'  ↔  enum name: 'interimSettlementRequested'
      case 'interimSettlementAdmin':      // FCMService screen key
      case 'interimSettlementRequested':  // NotificationScreen enum name
        return (p) => p.canManageWage;

      // ── 인력 도메인 ────────────────────────────────────────────────
      case 'fixedWorker':
      case 'scheduleChangeRequested':
      case 'terminationRequested':
      case 'terminationApproved':
      case 'terminationRejected':
      case 'resignRequested':
      case 'resignApproved':
      case 'resignRejected':
      case 'resignReminder':
      case 'reconfirmAdminWarning':
      case 'reconfirmDeclined':
      case 'idCardAccessRequested':
      case 'idCardAccessApproved':
      case 'idCardAccessRejected':
        return (p) => p.canManageWorkers;

      // ── OWNER(BUSINESS_ADMIN) 전용 ────────────────────────────────
      // SUB_ADMIN은 멤버 초대를 발송할 수 없으므로 수신도 정상 경로에서 없음.
      // (p) => false: up.can()이 BUSINESS_ADMIN → 항상 true 단락, SUB_ADMIN → false.
      case 'memberInvitationAccepted':
      case 'memberInvitationRejected':
        return (p) => false;

      default:
        return null; // generic guard로 fall through
    }
  }

  Future<void> _setViewMode(bool isCalendar) async {
    setState(() => _isCalendarView = isCalendar);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKey, isCalendar);
  }

  @override
  void dispose() {
    FCMService().removeAdminRefreshListener(_fcmRefreshCallback);
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      final last = _lastResumedAt;
      if (last != null && now.difference(last) < const Duration(minutes: 2)) return;
      _lastResumedAt = now;
      if (mounted) _controller.reload(context);
    }
  }

  /// 관리자의 모든 사업장 ID 로드
  Future<void> _loadBusinessIds() async {
    if (_fetchInProgress) return;
    _fetchInProgress = true;
    if (!_isLoading) setState(() => _isLoading = true);
    try {
      final userProvider = context.read<UserProvider>();
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showWarning('로그인 정보를 찾을 수 없습니다.');
        return;
      }

      // 뷰 모드를 먼저 로드해서 _selectedBusinessId와 같은 setState에 묶는다 — 토글 애니메이션 방지
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      final savedIsCalendar = prefs.getBool(_prefKey) ?? false;

      // SubAdmin은 effectiveBusinessId로 직접 사용 (adminIds에 없으므로 CF 호출 불필요)
      final effectiveBizId = userProvider.effectiveBusinessId;
      if (userProvider.isSubAdmin && effectiveBizId != null) {
        setState(() {
          _isCalendarView = savedIsCalendar;
          _allBusinessIds = [effectiveBizId];
          _selectedBusinessId = effectiveBizId;
        });
        if (mounted) _controller.load(context);
        return;
      }

      // BUSINESS_ADMIN: 로그인 시 이미 UserProvider에 로드된 managedBusinessIds 즉시 사용.
      // callableGetMyBusiness CF 호출을 건너뛰어 첫 진입 레이턴시를 CF 1회로 줄인다.
      final cachedIds = userProvider.currentUser?.managedBusinessIds ?? [];
      if (cachedIds.isNotEmpty) {
        final preferred = widget.initialBusinessId;
        setState(() {
          _isCalendarView = savedIsCalendar;
          _allBusinessIds = cachedIds;
          _selectedBusinessId = (preferred != null && cachedIds.contains(preferred))
              ? preferred
              : cachedIds.first;
          _isLoading = false;
        });
        if (mounted) _controller.load(context);
        return;
      }

      // managedBusinessIds가 비어 있는 경우(신규 관리자 등)만 CF로 확인
      final businesses = await _firestoreService.getMyBusiness(uid);

      if (!mounted) return;

      if (businesses.isEmpty) {
        ToastHelper.showWarning('등록된 사업장이 없습니다.');
        return;
      }

      setState(() {
        _isCalendarView = savedIsCalendar;
        _allBusinessIds = businesses.map((b) => b.id).toList();
        final preferred = widget.initialBusinessId;
        _selectedBusinessId = (preferred != null && _allBusinessIds.contains(preferred))
            ? preferred
            : _allBusinessIds.first;
      });

      if (mounted) _controller.load(context);
      debugPrint('✅ 관리 사업장: ${_allBusinessIds.length}개 (CF 조회)');
    } catch (e) {
      debugPrint('❌ 사업장 조회 실패: $e');
      if (mounted) ToastHelper.showError('사업장 정보를 불러올 수 없습니다.');
    } finally {
      _fetchInProgress = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_selectedBusinessId == null) {
      // 빈 상태(사업장 미등록)에도 메인 화면과 동일한 '공고 관리' 타이틀 유지
      return GradientScaffold(
        title: '공고 관리',
        body: _isLoading
            ? const WorkforceListSkeleton()
            : AppEmptyState(
                icon: Icons.business_center,
                title: '등록된 사업장이 없습니다',
                subtitle: '사업장을 먼저 등록해주세요',
                action: FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const BusinessListScreen()),
                  ),
                  icon: const Icon(Icons.add_business, size: 18),
                  label: const Text('사업장 등록'),
                ),
              ),
      );
    }

    return GradientScaffold(
      title: '공고 관리',
      onRefresh: _loadBusinessIds,
      body: ChangeNotifierProvider.value(
        value: _controller,
        child: Column(
          children: [
            _buildViewToggleBar(),
            Expanded(
              child: _isCalendarView
                  ? const WorkforceCalendarView()
                  : const WorkforceListView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildViewToggleBar() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 10),
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 6),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 3)),
            decoration: BoxDecoration(
              color: AppColors.grey100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildViewToggleButton(
                  icon: Icons.view_list,
                  label: '목록',
                  isSelected: !_isCalendarView,
                  onTap: () => _setViewMode(false),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                _buildViewToggleButton(
                  icon: Icons.calendar_month,
                  label: '캘린더',
                  isSelected: _isCalendarView,
                  onTap: () => _setViewMode(true),
                ),
              ],
            ),
          ),
          const Spacer(),
          if (!_isCalendarView)
            Selector<WorkforceController, ({bool hasFilters, int count})>(
              selector: (_, c) => (hasFilters: c.hasActiveFilters, count: c.activeFilterCount),
              builder: (ctx, data, _) => _buildFilterButton(ctx, data.hasFilters, data.count),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterButton(BuildContext ctx, bool hasFilters, int filterCount) {
    final theme = Theme.of(ctx);

    return Material(
      color: hasFilters
          ? theme.primaryColor.withValues(alpha: 0.1)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () => ctx.read<WorkforceController>().requestShowFilter(),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(ctx, 12),
            vertical: ResponsiveHelper.spacing(ctx, 6),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Icon(
                Icons.filter_list,
                color: hasFilters ? theme.primaryColor : AppColors.grey600,
                size: ResponsiveHelper.iconSize(ctx, 24),
              ),
              if (hasFilters)
                Positioned(
                  right: -6,
                  top: -6,
                  child: Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(ctx, 4)),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.primaryColor,
                          theme.primaryColor.withValues(alpha: 0.8),
                        ],
                      ),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: theme.primaryColor.withValues(alpha: 0.4),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    constraints: BoxConstraints(
                      minWidth: ResponsiveHelper.spacing(ctx, 18),
                      minHeight: ResponsiveHelper.spacing(ctx, 18),
                    ),
                    child: Center(
                      child: Text(
                        '$filterCount',
                        style: ResponsiveHelper.tinyStyle(
                          ctx,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildViewToggleButton({
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      // 두 버튼이 항상 같은 최소 너비 유지 — "캘린더"(더 긴 텍스트) 기준
      constraints: BoxConstraints(minWidth: ResponsiveHelper.spacing(context, 76)),
      child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeInOut,
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 6),
        ),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(7),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 15),
              color: isSelected ? theme.primaryColor : AppColors.grey500,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 5)),
            Text(
              label,
              style: ResponsiveHelper.smallStyle(
                context,
                color: isSelected ? theme.primaryColor : AppColors.grey500,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}