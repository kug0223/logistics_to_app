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
import '../../utils/navigation_helper.dart';
import 'to_management/create_to_screen.dart';
import 'workforce_management/workforce_list_view.dart';

class JobsRootScreen extends StatefulWidget {
  const JobsRootScreen({super.key});

  @override
  State<JobsRootScreen> createState() => _JobsRootScreenState();
}

class _JobsRootScreenState extends State<JobsRootScreen>
    with WidgetsBindingObserver {
  /// 이 Root 전용 WorkforceController — WorkforceRootScreen과 공유하지 않음
  final WorkforceController _controller = WorkforceController();

  DateTime? _lastResumedAt;
  late final VoidCallback _fcmRefreshCallback;

  // Cross-tab invalidation
  int _lastSeenRevision = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.load(context);
    });
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
    // 이 controller가 직접 revision을 발생시켰으면 skip (자기 중복 로드 방지)
    if (_controller.wasLastGlobalBumpByMe) return;
    if (!mounted || _controller.isLoading) return;
    // load(): revision 재증가 없음 → 무한루프 차단
    _controller.load(context);
  }

  @override
  void dispose() {
    WorkforceController.dataRevision.removeListener(_onDataRevisionChanged);
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
      if (last != null && now.difference(last) < const Duration(minutes: 2)) {
        return;
      }
      _lastResumedAt = now;
      if (mounted) _controller.reload(context);
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
              const Expanded(child: WorkforceListView()),
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
                  fontSize: 20 * s,
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
                      onChanged: () {
                        if (mounted) _controller.reload(context);
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
                          fontSize: 12 * s,
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

  /// 사업장 scope label 계산
  /// SubAdmin → 배정 사업장 이름
  /// 단일 사업장 관리자 → 사업장 이름 (items 0건이어도 knownBusinessNames 캐시 사용)
  /// 다중 사업장 관리자 → "전체 사업장"
  String _computeScopeLabel(WorkforceController controller, UserProvider up) {
    if (up.isSubAdmin) {
      final bizId = up.effectiveBusinessId;
      return (bizId != null ? up.subAdminBusinessNames[bizId] : null) ??
          '내 사업장';
    }
    final names = controller.items.isNotEmpty
        ? controller.items
            .map((g) => g.businessName)
            .where((n) => n.isNotEmpty)
            .toSet()
        : controller.knownBusinessNames.toSet();
    if (names.length == 1) return names.first;
    final count = up.currentUser?.managedBusinessIds.length ?? 0;
    if (count > 1) return '전체 사업장';
    if (names.isNotEmpty) return names.first;
    return count == 1 ? '내 사업장' : '';
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
                    fontSize: 9,
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
