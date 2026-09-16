import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/employment_contract_model.dart';
import '../../providers/user_provider.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../screens/user/user_contracts_screen.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';

/// 서명 대기 계약서 배너 — 근로자 전 화면 공용.
///
/// [PREDEVICE-CONTRACT-CONTEXT] 이 배너는 원래 두 곳(UserRootScreen,
/// GradientScaffold)에 각각 구현돼 있었고 문구·이동 경로가 따로 놀 수 있었다.
/// 계약 안내는 근로자가 가장 자주 마주치는 문장이므로 한 곳에서만 만든다.
///
/// 보여주는 것:
///   · 한 건  → '계약서 서명이 필요해요' + '9월 22일 · 오산센터'
///   · 여러 건 → '서명할 계약서 3건이 있어요' + '가장 가까운 근무 …'
/// 목록을 배너에 펼치지 않는다 — 대표 한 건의 context와 개수까지다.
///
/// 이동:
///   · 한 건이면 그 계약서로 바로 (목록을 한 번 더 거치게 하지 않는다)
///   · 여러 건이면 계약서 목록
/// 복귀 시 목록을 다시 받는다 — 다른 기기에서 서명했을 수 있다.
class PendingContractBar extends StatelessWidget {
  /// true면 하단 시스템 inset을 스스로 처리한다.
  /// UserRootScreen처럼 BottomNavigationBar 위에 놓일 때는 false.
  final bool useSafeArea;

  const PendingContractBar({super.key, this.useSafeArea = false});

  @override
  Widget build(BuildContext context) {
    // 가용성 체크 — Provider가 없는 트리에서도 안전하게 비표시.
    try {
      Provider.of<UserProvider>(context, listen: false);
    } catch (_) {
      return const SizedBox.shrink();
    }

    return Selector<UserProvider,
        ({bool show, int count, EmploymentContractModel? nearest})>(
      selector: (_, p) => (
        show: p.isUser && !p.isAdminMode && p.hasPendingContract,
        count: p.pendingContractCount,
        nearest: p.nearestPendingContract,
      ),
      builder: (ctx, data, _) {
        if (!data.show) return const SizedBox.shrink();

        final isSingle = data.count == 1;
        final contextLabel = data.nearest?.contextLabel;
        final title = isSingle
            ? '계약서 서명이 필요해요'
            : '서명할 계약서 ${data.count}건이 있어요';
        final subtitle = contextLabel == null
            ? null
            : (isSingle ? contextLabel : '가장 가까운 근무 $contextLabel');

        final bar = GestureDetector(
          onTap: () {
            final only = isSingle ? data.nearest : null;
            // context가 async gap을 넘지 않도록 먼저 잡아 둔다.
            final provider = ctx.read<UserProvider>();
            Navigator.push(
              ctx,
              MaterialPageRoute(
                builder: (_) => only == null
                    ? const UserContractsScreen()
                    : ContractSignScreen(contract: only, role: 'worker'),
              ),
            ).then((_) => provider.refreshPendingContracts());
          },
          child: Container(
            width: double.infinity,
            color: AppColors.yellowWarnBg,
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(ctx, 16),
              vertical: ResponsiveHelper.spacing(ctx, 12),
            ),
            child: Row(children: [
              const Icon(Icons.draw_outlined,
                  color: AppColors.yellowWarnDark, size: 18),
              SizedBox(width: ResponsiveHelper.spacing(ctx, 8)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: ResponsiveHelper.smallStyle(ctx).copyWith(
                        color: AppColors.yellowWarnText,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null) ...[
                      SizedBox(height: ResponsiveHelper.spacing(ctx, 2)),
                      Text(
                        subtitle,
                        style: ResponsiveHelper.smallStyle(ctx)
                            .copyWith(color: AppColors.yellowWarnText),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: AppColors.yellowWarnDark, size: 18),
            ]),
          ),
        );

        return useSafeArea ? SafeArea(top: false, child: bar) : bar;
      },
    );
  }
}
