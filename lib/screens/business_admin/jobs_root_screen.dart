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
import '../../services/business_posting_readiness.dart';
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
          child: ValueListenableBuilder<FirstPostingReadiness?>(
            valueListenable: FirstPostingReadinessBroadcast.current,
            builder: (ctx, readiness, _) {
              final setupRequired = readiness != null && !readiness.allReady;
              return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 헤더: 제목 + 필터 + 공고등록 + scope chip
              // Consumer<WorkforceController>가 내부에서 context를 해석 — provider scope 안
              _buildHeader(s, setupRequired),
              // [R7-P4.4E.2] 준비가 끝나지 않았으면 운영 목록을 그리지 않는다.
              //
              //   예전에는 사업장이 생기는 순간 바로 "진행중 0 / 등록된 공고가
              //   없습니다 / + 새 공고 등록" 으로 들어갔다. 그런데 Home 은 같은
              //   시점에 "공고 등록까지 3단계 남았어요" 라고 말하고 있었고,
              //   실제로 + 를 눌러도 서버 gate 에서 막힌다. 사용자를 할 수 없는
              //   행동으로 안내한 것이다.
              //
              //   `null` 은 **아직 모른다**는 뜻이라 지금 화면을 바꾸지 않는다 —
              //   모르는 동안 setup 을 그리면 준비가 끝난 관리자에게 거짓이 된다.
              Expanded(
                child: setupRequired
                    ? _JobsSetupRequiredView(readiness: readiness, scale: s)
                    : WorkforceListView(targetToId: _targetToId),
              ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 헤더 — white base, Home 디자인 언어 통일
  // ─────────────────────────────────────────────────────────────
  Widget _buildHeader(double s, bool setupRequired) {
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
              // [CROSS-DOMAIN-R5.1F.1] read가 아니라 구독이다.
              //   탭 루트는 Shell의 const child라 Shell이 다시 그려져도 여기까지
              //   오지 않는다. read로 읽으면 권한이 회수돼도 이 버튼이 남는다.
              // [CROSS-DOMAIN-R5.1F.5] bool이 아니라 4상태를 구독한다 —
              //   허용 값은 그대로인데 전송 상태만 나빠진 전이(verified→error)도
              //   선택값을 바꾸므로 여기까지 닿는다. allowed만 통과시킨다.
              // [R7-P4.4E.2 §11] 준비가 끝나지 않았으면 이 버튼을 **없앤다.**
              //   disabled 로 두면 왜 안 되는지 말하지 못하고, 같은 화면에 이미
              //   '준비 단계 보기' 가 있으므로 두 번째 recovery 를 겹치지 않는다.
              //   readiness 를 아직 모르면(null) 지금 동작을 바꾸지 않는다.
              if (context.select<UserProvider, PermissionCheck>(
                          (p) => p.checkCurrentBusiness((x) => x.canManageTo)) ==
                          PermissionCheck.allowed &&
                  !setupRequired)
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
          //
          // [POSTING-V2-03P.1] isLoading 가드를 두지 않는다. scope label은
          //   knownBusinessNames 캐시에서 만들어지므로 refresh 중에도 이미 알고
          //   있는 값이다. 가드가 있으면 새로고침할 때마다 헤더의 사업장 줄이
          //   통째로 사라졌다가 되돌아오면서 아래 내용이 위아래로 흔들렸다.
          //   아직 이름을 모르는 사업장은 label 자체가 id fallback으로 잠깐
          //   달라질 수 있는데, 그 작은 text 변화를 없애려고 preload를 넣지는
          //   않는다 — 추가 read를 만들 만한 문제가 아니다.
          Consumer<WorkforceController>(
            builder: (ctx, controller, _) {
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

/// [R7-P4.4E.2 §7] 공고 root 의 준비 미완료 surface.
///
///   Home 이 setup owner 다(P4.2C). 그래서 여기서는 **같은 목록을 다시
///   나열하지 않는다** — 무엇이 남았는지 짧게 말하고 Home 으로 보낸다.
///   Home 과 별도의 task owner 가 되면 두 곳이 서로 다른 개수를 말하게 된다.
class _JobsSetupRequiredView extends StatelessWidget {
  const _JobsSetupRequiredView({required this.readiness, required this.scale});

  final FirstPostingReadiness? readiness;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final r = readiness;
    final remaining =
        r == null ? 0 : FirstPostingReadiness.totalTasks - r.completedCount;
    final s = scale;

    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24 * s),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56 * s,
              height: 56 * s,
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.checklist_rounded,
                  size: 28 * s, color: AppColors.info),
            ),
            SizedBox(height: 16 * s),
            Text(
              '아직 공고를 등록할 준비가 끝나지 않았어요',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: 8 * s),
            Text(
              remaining > 0
                  ? '$remaining가지 준비가 남아 있습니다.\n준비를 마치면 공고를 등록할 수 있어요.'
                  : '준비 상태를 확인해 주세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: AppColors.textSecondary,
              ),
            ),
            SizedBox(height: 20 * s),
            // 목적지는 Home — readiness 카드가 첫 화면 상단에 있으므로
            // 별도 deep-link 대상을 새로 만들지 않는다(§17).
            FilledButton(
              onPressed: () =>
                  AdminTabSwitcher.instance.switchToTab(AdminTabSwitcher.homeTab),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.info,
                padding: EdgeInsets.symmetric(horizontal: 22 * s, vertical: 12 * s),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('준비 단계 보기',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
