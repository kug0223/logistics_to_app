// lib/screens/business_admin/workforce_management/workforce_root_screen.dart
//
// 인력 Root — 5-tab Bottom Nav의 "인력" 탭 (PHASE 4B foundation, PHASE 4C UI)
//
// 역할: 날짜/사람 중심 workforce 운영
//   - 지원자 / 근무 현황 / 고정 근로자 (날짜 선택 후 접근)
//   - 마감관리는 이 Root에서 제외 — Home·Jobs에 canonical route 유지
//
// [설계 원칙]
//   - WorkforceController 전용 인스턴스 — JobsRootScreen과 state 격리
//   - FCM listener + lifecycle refresh 독립 운영
//   - Cross-tab invalidation: WorkforceController.dataRevision 리스너로
//     Jobs에서 TO가 변경되면 이 controller도 갱신. reload()를 직접 호출하지 않으므로
//     global revision이 재증가하지 않아 무한루프 없음.
//   - 화이트 헤더: Home/Jobs와 동일한 design system
//   - Bottom safe area: Scaffold+BottomNav가 처리하므로 body에서 추가 처리 없음
//
// [사업장 scope]
//   BUSINESS_ADMIN (단일): 사업장명 (controller.knownBusinessNames 캐시 사용)
//   BUSINESS_ADMIN (복수): 전체 사업장
//   SubAdmin: 배정 사업장 (up.subAdminBusinessNames)
//   미로드 시: '내 사업장' fallback
//
// [마감관리 canonical route]
//   WorkforceCalendarView(hideCloseManagement: true)로 숨김.
//   IntegratedWorkforceScreen(legacy)에서는 4개 버튼 모두 유지.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/workforce_controller.dart';
import '../../../providers/user_provider.dart';
import '../../../services/fcm_service.dart';
import '../../../theme/app_colors.dart';
// workforce_calendar_view.dart는 IntegratedWorkforceScreen에서 계속 사용됨 — 삭제 금지
import 'workforce_operational_view.dart';

class WorkforceRootScreen extends StatefulWidget {
  const WorkforceRootScreen({super.key});

  @override
  State<WorkforceRootScreen> createState() => _WorkforceRootScreenState();
}

class _WorkforceRootScreenState extends State<WorkforceRootScreen>
    with WidgetsBindingObserver {
  /// 이 Root 전용 WorkforceController — JobsRootScreen과 공유하지 않음
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

    // Cross-tab invalidation: Jobs 탭에서 TO 변경 → 이 controller도 갱신
    _lastSeenRevision = WorkforceController.dataRevision.value;
    WorkforceController.dataRevision.addListener(_onDataRevisionChanged);
  }

  @override
  void dispose() {
    WorkforceController.dataRevision.removeListener(_onDataRevisionChanged);
    FCMService().removeAdminRefreshListener(_fcmRefreshCallback);
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
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
      backgroundColor: Colors.white,
      body: SafeArea(
        bottom: false,
        child: ChangeNotifierProvider.value(
          value: _controller,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHeader(s),
              const Expanded(
                // PHASE 5B.1: WorkforceOperationalView — Date/Worker 운영 UX
                // (기존 WorkforceCalendarView는 IntegratedWorkforceScreen에서 유지)
                child: WorkforceOperationalView(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 헤더 — white base, scope chip ──────────────────────────────────
  Widget _buildHeader(double s) {
    return Consumer<WorkforceController>(
      builder: (ctx, controller, _) {
        final up = ctx.read<UserProvider>();
        final scopeLabel = _computeScopeLabel(controller, up);
        return Container(
          padding: EdgeInsets.fromLTRB(20 * s, 12 * s, 16 * s, 10 * s),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              bottom: BorderSide(color: AppColors.grey100, width: 1),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '인력',
                style: TextStyle(
                  fontSize: 20 * s,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              if (scopeLabel.isNotEmpty) ...[
                SizedBox(height: 3 * s),
                Row(
                  children: [
                    Icon(
                      Icons.business_outlined,
                      size: 12 * s,
                      color: AppColors.grey500,
                    ),
                    SizedBox(width: 4 * s),
                    Flexible(
                      child: Text(
                        scopeLabel,
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
              ],
            ],
          ),
        );
      },
    );
  }

  /// 사업장 scope label 계산
  /// - 로딩 중이면 호출되지 않음 (Consumer에서 isLoading 체크 불필요 — 항상 scope 표시)
  /// - controller.knownBusinessNames: items 0건이어도 마지막 로드 이름 유지
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
