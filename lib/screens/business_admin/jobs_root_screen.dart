// lib/screens/business_admin/jobs_root_screen.dart
//
// 공고 Root — 5-tab Bottom Nav의 "공고" 탭 (PHASE 4B)
//
// 역할: TO 생성 / 조회 / 수정 / 마감 / 종료 공고 관리
//
// [설계 원칙]
//   - WorkforceListView 기반 (목록↔캘린더 toggle 없음 — 캘린더는 인력 Root 담당)
//   - 화이트 헤더: 제목 + 필터 + 공고 등록
//   - 사업장 scope chip: 단일 → 이름 표시, 복수 → "전체 사업장"
//   - WorkforceController 전용 인스턴스 — WorkforceRootScreen과 state 격리
//   - FCM listener + lifecycle refresh 독립 운영
//
// [Controller 공유 정책]
//   JobsRootScreen.WorkforceController ≠ WorkforceRootScreen.WorkforceController
//   이유: controller._selectedBusiness 등 UI 필터 state 포함 → 공유 시 state leakage
//   data level(FirestoreService)은 공유 가능. UI state는 각 Root 독립.
//
// [Multi-business]
//   WorkforceController.load()가 managedBusinessIds 전체 TO를 aggregate 로드.
//   scope chip은 로드된 items에서 businessName을 파생.
//   SubAdmin: effectiveBusinessId 고정, subAdminBusinessNames에서 이름 표시.
//
// [Cross-tab refresh]
//   FCMService 리스너로 push 수신 시 자동 reload.
//   lifecycle resume 시 2분 쿨다운 후 reload.
//   인력 Root와 별도로 각자 refresh — shared controller 없음.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/workforce_controller.dart';
import '../../providers/user_provider.dart';
import '../../services/fcm_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/admin_business_scope_label.dart';
import '../../utils/admin_tab_switcher.dart';
import '../../utils/navigation_helper.dart';
import 'to_management/create_to_screen.dart';
import 'workforce_management/workforce_list_view.dart';

class JobsRootScreen extends StatefulWidget {
  /// [POSTING-V2-03A.1] 알림에서 지정한 공고 — standalone 진입(SUPER_ADMIN,
  /// Shell 미활성 fallback)에서 target을 전달받는 경로.
  /// Shell 탭 진입은 AdminTabSwitcher.switchToJobsWithTarget이 담당한다.
  final String? initialTargetToId;

  /// [POSTING-V2-03O.1] Shell이 소유하는 공유 controller.
  ///
  /// null이면 이 화면이 standalone(알림 fallback, SUPER_ADMIN 직접 진입)이라
  /// 자기 인스턴스를 만들고 직접 정리한다. Shell 경로에서는 항상 주입된다.
  final WorkforceController? postingController;

  const JobsRootScreen({
    super.key,
    this.initialTargetToId,
    this.postingController,
  });

  @override
  State<JobsRootScreen> createState() => _JobsRootScreenState();
}

class _JobsRootScreenState extends State<JobsRootScreen>
    with WidgetsBindingObserver {
  /// [POSTING-V2-03O.1] 공유 controller. Shell이 줬으면 그것을 쓰고,
  ///   standalone 진입에서만 자체 인스턴스를 만든다.
  late final WorkforceController _controller =
      widget.postingController ?? WorkforceController();

  /// 자체 생성한 경우에만 dispose한다 — 공유 인스턴스는 Shell이 정리한다.
  bool get _ownsController => widget.postingController == null;

  DateTime? _lastResumedAt;
  late final VoidCallback _fcmRefreshCallback;

  // Cross-tab invalidation
  int _lastSeenRevision = 0;

  /// [POSTING-V2-03A.1] 알림이 지정한 공고 — WorkforceListView에 1회성으로 전달.
  String? _targetToId;
  late final void Function(String toId) _onJobsTarget;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _targetToId = widget.initialTargetToId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.load(context);
    });

    // [POSTING-V2-03A.1] 알림 → Jobs 탭 target 수신.
    //   filter를 바꾸지 않는다 — 목록이 target을 1회 보여주고 끝난다.
    _onJobsTarget = (toId) {
      if (!mounted) return;
      setState(() => _targetToId = toId);
    };
    AdminTabSwitcher.instance.registerJobsTargetHandler(_onJobsTarget);

    // [PHASE-2A] Home 인력 블록 → Jobs 탭 intent 핸들러 등록
    // businessId가 제공되면 business filter를 교체하고, 없으면 기존 filter를 유지.
    // dateRange는 항상 intent로 덮어쓴다.
    AdminTabSwitcher.instance.registerJobsNavHandler(
      ({required DateTimeRange dateRange, String? businessId}) {
        if (!mounted) return;
        if (businessId != null) _controller.setBusinessIdFilter(businessId);
        _controller.setDateRangeFilter(dateRange);
      },
    );

    _fcmRefreshCallback = () {
      if (mounted) _controller.reload(context);
    };
    FCMService().addAdminRefreshListener(_fcmRefreshCallback);

    // Cross-tab invalidation: Workforce 탭에서 지원/근태 변경 → 이 controller도 갱신
    _lastSeenRevision = WorkforceController.dataRevision.value;
    WorkforceController.dataRevision.addListener(_onDataRevisionChanged);
  }

  void _onDataRevisionChanged() {
    final rev = WorkforceController.dataRevision.value;
    if (rev <= _lastSeenRevision) return;
    _lastSeenRevision = rev;
    // [POSTING-V2-02B.2] 이 탭에서 일어난 mutation은 이미 local refresh를 끝냈다
    if (WorkforceController.lastMutationOrigin == AdminMutationOrigin.jobs) {
      return;
    }
    // [POSTING-V2-03O.1] 로딩 중이라고 caller가 먼저 버리지 않는다.
    //   진행 중인 load는 이 mutation보다 앞선 데이터를 들고 있을 수 있다.
    //   controller가 pending으로 접어 현재 사이클 뒤에 한 번 더 돈다.
    if (!mounted) return;
    // load(): revision 재증가 없음 → 무한루프 차단
    _controller.load(context);
  }

  @override
  void dispose() {
    // [PHASE-2A] Jobs 탭 intent 핸들러 해제 — Shell 해제와 별도로 관리
    AdminTabSwitcher.instance.unregisterJobsNavHandler();
    // [POSTING-V2-03A.1] 자기가 등록한 핸들러일 때만 해제 —
    //   standalone 인스턴스가 Shell의 등록을 지우지 않게 한다.
    AdminTabSwitcher.instance.unregisterJobsTargetHandler(_onJobsTarget);
    WorkforceController.dataRevision.removeListener(_onDataRevisionChanged);
    FCMService().removeAdminRefreshListener(_fcmRefreshCallback);
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final now = DateTime.now();
      final last = _lastResumedAt;
      if (last != null && now.difference(last) < const Duration(minutes: 2)) {
        return;
      }
      _lastResumedAt = now;
      if (!mounted) return;
      // [POSTING-V2-03B.1] 복귀 시 접근 상태를 먼저 맞춘다.
      //   다른 관리자·다른 기기가 바꾼 배정과 비선택 사업장 권한은
      //   realtime listener가 없어 이 지점에서만 따라잡을 수 있다.
      //   access → data 순서를 지켜야 stale scope로 서버를 부르지 않는다.
      //   동시 호출은 provider가 하나로 합친다.
      final up = context.read<UserProvider>();
      if (up.isSubAdmin) {
        up.refreshSubAdminAccessState().whenComplete(() {
          if (mounted) _controller.reload(context);
        });
      } else {
        _controller.reload(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _scale(context);
    return Scaffold(
      backgroundColor: AppColors.grey50,
      body: SafeArea(
        bottom: false,
        child: ChangeNotifierProvider.value(
          value: _controller,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 헤더: 제목 + 필터 + 공고등록 + scope chip
              // Consumer<WorkforceController>가 내부에서 context를 해석 — provider scope 안
              _buildHeader(s),
              // 공고 목록 (진행중/마감됨 탭 포함)
              Expanded(child: WorkforceListView(targetToId: _targetToId)),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 헤더 — white base, Home 디자인 언어 통일
  // ─────────────────────────────────────────────────────────────
  Widget _buildHeader(double s) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(20 * s, 12 * s, 12 * s, 10 * s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 타이틀 행
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                '공고',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const Spacer(),
              // 필터 버튼 — controller 상태 반응 (Consumer로 scope 안에서 안전하게 읽기)
              Consumer<WorkforceController>(
                builder: (ctx, controller, _) => _JobsFilterButton(
                  hasFilters: controller.hasActiveFilters,
                  filterCount: controller.activeFilterCount,
                  onTap: controller.requestShowFilter,
                  scale: s,
                ),
              ),
              SizedBox(width: 2 * s),
              // 공고 등록 CTA — SubAdmin은 canManageTo 권한 있을 때만 표시
              // [P2-A-FIX] 서버 게이트(callableCreateTO canManageTo 검증)와 동기화
              if (!context.read<UserProvider>().isSubAdmin ||
                  context.read<UserProvider>().can((p) => p.canManageTo))
                _JobsCreateButton(
                  scale: s,
                  onTap: () {
                    if (!mounted) return;
                    // [HOTFIX HOME.POSTING.ENTRY.1-R1] SUB_ADMIN: effectiveBusinessId 상속.
                    // OWNER: null → 기존 flow(ready-first) 유지.
                    final up = context.read<UserProvider>();
                    final initBizId = up.isSubAdmin ? up.effectiveBusinessId : null;
                    NavigationHelper.push<bool>(
                      context,
                      destination: AdminCreateTOScreen(initialBusinessId: initBizId),
                      useRootNavigator: true,
                      // onChanged는 result == true(생성 성공)일 때만 호출된다
                      onChanged: () {
                        if (!mounted) return;
                        _controller.reload(context);
                        // [POSTING-V2-02B.2] 새 공고는 Home의 인력 현황과
                        //   첫 공고 준비 카드에 모두 영향을 준다.
                        WorkforceController.notifyDataChanged(
                          origin: AdminMutationOrigin.jobs,
                        );
                      },
                    );
                  },
                ),
            ],
          ),
          // 사업장 scope chip — items 0건·로딩 완료 후에도 표시 (knownBusinessNames 캐시 사용)
          Consumer<WorkforceController>(
            builder: (ctx, controller, _) {
              if (controller.isLoading) return const SizedBox.shrink();
              final up = ctx.read<UserProvider>();
              final label = _computeScopeLabel(controller, up);
              if (label.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: EdgeInsets.only(top: 5 * s),
                child: Row(
                  children: [
                    Icon(
                      Icons.business_outlined,
                      size: 12 * s,
                      color: AppColors.grey500,
                    ),
                    SizedBox(width: 4 * s),
                    Flexible(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.grey500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  /// 사업장 scope label 계산 — [POSTING-V2-02F.1] 공용 resolver에 위임.
  ///
  /// 범위 판정은 businessIds만 본다. effectiveBusinessId(Home context)나
  /// 로드된 공고의 사업장 분포로 범위를 말하지 않는다.
  /// 근무 탭(WorkforceRootScreen)도 같은 resolver를 쓴다 — 같은 데이터 범위를
  /// 두 화면이 다르게 설명하지 않도록.
  String _computeScopeLabel(WorkforceController controller, UserProvider up) {
    final user = up.currentUser;
    return resolveAdminBusinessScopeLabel(
      // SUPER_ADMIN은 load()가 businessIds = null로 전체를 조회한다 —
      // 이 화면은 알림에서 직접 push될 수 있다.
      isSuperAdmin: user?.isSuperAdmin ?? false,
      isSubAdmin: up.isSubAdmin,
      managedBusinessIds: user?.managedBusinessIds ?? const [],
      subAdminBusinessIds: user?.subAdminBusinessIds ?? const [],
      subAdminBusinessNames: up.subAdminBusinessNames,
      loadedBusinessNames: controller.items.isNotEmpty
          ? controller.items.map((g) => g.businessName).toList()
          : controller.knownBusinessNames,
    );
  }

  double _scale(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    if (w < 360) return 0.82;
    if (w < 400) return 0.92;
    if (w < 480) return 1.0;
    return 1.08;
  }
}

// ─────────────────────────────────────────────────────────────
// 필터 아이콘 버튼 — gradient/shadow 제거, primary outline 뱃지
// ─────────────────────────────────────────────────────────────
class _JobsFilterButton extends StatelessWidget {
  final bool hasFilters;
  final int filterCount;
  final VoidCallback onTap;
  final double scale;

  const _JobsFilterButton({
    required this.hasFilters,
    required this.filterCount,
    required this.onTap,
    required this.scale,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: hasFilters
              ? theme.primaryColor.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: EdgeInsets.all(8 * scale),
              child: Icon(
                Icons.filter_list_rounded,
                color: hasFilters ? theme.primaryColor : AppColors.grey600,
                size: 22 * scale,
              ),
            ),
          ),
        ),
        if (hasFilters)
          Positioned(
            right: 3,
            top: 3,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: theme.primaryColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              constraints: const BoxConstraints(minWidth: 15, minHeight: 15),
              child: Center(
                child: Text(
                  '$filterCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// 공고 등록 버튼 — primary filled icon button
// ─────────────────────────────────────────────────────────────
class _JobsCreateButton extends StatelessWidget {
  final double scale;
  final VoidCallback onTap;

  const _JobsCreateButton({required this.scale, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: '공고 등록',
      child: Material(
        color: theme.primaryColor,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: EdgeInsets.all(8 * scale),
            child: Icon(
              Icons.add_rounded,
              color: Colors.white,
              size: 20 * scale,
            ),
          ),
        ),
      ),
    );
  }
}
