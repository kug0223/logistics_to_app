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
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/workforce_controller.dart';
import '../../../providers/user_provider.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/admin_business_scope_label.dart';
import 'workforce_operational_view.dart';

class WorkforceRootScreen extends StatefulWidget {
  /// [POSTING-V2-03O.1] Shell이 소유하는 공유 공고 controller.
  ///
  /// 이 화면은 **소비만** 한다 — 로딩 상태와 사업장 이름만 읽는다.
  /// null이면 standalone 진입이라 자체 인스턴스를 만들고 직접 정리한다.
  final WorkforceController? postingController;

  const WorkforceRootScreen({super.key, this.postingController});

  @override
  State<WorkforceRootScreen> createState() => _WorkforceRootScreenState();
}

class _WorkforceRootScreenState extends State<WorkforceRootScreen> {
  /// [POSTING-V2-03O.1] 공유 controller. Shell 경로에서는 주입된다.
  late final WorkforceController _controller =
      widget.postingController ?? WorkforceController();

  bool get _ownsController => widget.postingController == null;

  // [POSTING-V2-03O.1] 공고 목록 lifecycle은 JobsRootScreen 하나가 맡는다.
  //
  //   이전에는 이 화면도 initState load · FCM listener · resume reload ·
  //   dataRevision listener를 각각 갖고 있었다. Shell의 IndexedStack이 두
  //   Root를 동시에 mount하므로, 같은 event 하나가 callableGetAdminTOs와
  //   전 FLEX 슬롯 preload를 두 벌씩 돌렸다.
  //
  //   이 화면이 그 결과에서 실제로 쓰는 것은 controller의 로딩 상태와
  //   사업장 이름뿐이다. 공유 controller를 구독만 하면 충분하고,
  //   자기 운영 데이터(_reload 등)는 이 파일 밖의 기존 경로 그대로다.
  @override
  void dispose() {
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  /// standalone 진입에서만 자체 초기 로드가 필요하다.
  @override
  void initState() {
    super.initState();
    if (!_ownsController) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.load(context);
    });
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
                  fontSize: 20,
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
                          fontSize: 12,
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

  /// 사업장 scope label 계산 — [POSTING-V2-02F.1] 공고 탭과 같은 resolver를 쓴다.
  ///
  /// 두 Root는 같은 데이터 범위(managedBusinessIds / subAdminBusinessIds)를
  /// 조회하므로 같은 문구로 설명해야 한다. 이 화면의 query·filter·permission·
  /// layout은 바뀌지 않는다 — 표시 문구만 공용 규칙을 따른다.
  /// - controller.knownBusinessNames: items 0건이어도 마지막 로드 이름 유지
  String _computeScopeLabel(WorkforceController controller, UserProvider up) {
    final user = up.currentUser;
    return resolveAdminBusinessScopeLabel(
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
