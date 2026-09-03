// lib/screens/user/subadmin_leave_screen.dart
//
// 서브관리자 직책 해제 화면
// - 서브관리자로 등록된 사업장 목록 표시
// - 사업장별 '탈퇴하기' 버튼 → callableLeaveAsSubAdmin CF 호출
// - 회원탈퇴 체크리스트의 SUBADMIN_MEMBERSHIP 블로커 해소 경로이기도 함

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../services/member_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/gradient_scaffold.dart';

class SubadminLeaveScreen extends StatefulWidget {
  const SubadminLeaveScreen({super.key});

  @override
  State<SubadminLeaveScreen> createState() => _SubadminLeaveScreenState();
}

class _SubadminLeaveScreenState extends State<SubadminLeaveScreen> {
  /// businessId → 사업장명
  final Map<String, String> _names = {};
  bool _isLoading = true;

  /// 처리 중인 businessId 집합 (버튼 개별 로딩)
  final Set<String> _processing = {};

  @override
  void initState() {
    super.initState();
    _loadNames();
  }

  /// 현재 사용자의 subAdminBusinessIds 기준으로 사업장 이름 일괄 조회
  Future<void> _loadNames() async {
    final ids =
        context.read<UserProvider>().currentUser?.subAdminBusinessIds ?? [];
    if (ids.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      final snaps = await Future.wait(
        ids.map((id) =>
            FirebaseFirestore.instance.collection('businesses').doc(id).get()),
      );
      final result = <String, String>{};
      for (var i = 0; i < ids.length; i++) {
        result[ids[i]] = snaps[i].data()?['name'] as String? ?? '알 수 없는 사업장';
      }
      if (mounted) {
        setState(() {
          _names.addAll(result);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 특정 사업장에서 서브관리자 탈퇴
  Future<void> _leave(BuildContext ctx, String bizId) async {
    final name = _names[bizId] ?? bizId;

    final confirmed = await DialogHelper.showConfirm(
      ctx,
      title: '서브관리자 탈퇴',
      message: '$name에서 서브관리자 직책을 해제합니다.\n\n해당 사업장의 모든 관리 권한이 즉시 제거됩니다.',
      confirmText: '탈퇴',
      confirmColor: AppColors.error,
      icon: Icons.logout_outlined,
      iconColor: AppColors.error,
    );
    if (confirmed != true) return;

    setState(() => _processing.add(bizId));
    try {
      await MemberService().leaveAsSubAdmin(bizId);
      // [F-16-4 수정] leaveAsSubAdmin 완료 후 로컬 캐시 즉시 갱신
      // UserProvider는 authStateChanges 기반 — subAdminBusinessIds를 자동 갱신하지 않으므로 직접 refresh 필요
      if (mounted) {
        await context.read<UserProvider>().refreshCurrentUser();
      }
    } catch (_) {
      if (mounted) {
        ToastHelper.showError('탈퇴 중 오류가 발생했습니다. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _processing.remove(bizId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ResponsiveHelper.getScale(context);
    final theme = Theme.of(context);

    return GradientScaffold(
      title: '서브관리자 탈퇴',
      showHomeButton: false,
      showNotificationBell: false,
      body: Selector<UserProvider, List<String>>(
        selector: (_, p) =>
            List.from(p.currentUser?.subAdminBusinessIds ?? const []),
        builder: (ctx, bizIds, _) {
          // 로딩 중
          if (_isLoading) {
            return const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            );
          }

          // 서브관리자 직책 없음
          if (bizIds.isEmpty) {
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24 * s),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline,
                        size: 48 * s, color: AppColors.grey400),
                    SizedBox(height: 16 * s),
                    Text(
                      '서브관리자로 등록된 사업장이 없습니다',
                      textAlign: TextAlign.center,
                      style: ResponsiveHelper.bodyStyle(ctx,
                          color: AppColors.grey600),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView.builder(
            padding: ResponsiveHelper.listPadding(ctx),
            itemCount: bizIds.length,
            itemBuilder: (ctx, i) {
              final bizId = bizIds[i];
              final name = _names[bizId];
              final isProc = _processing.contains(bizId);

              return Container(
                margin: EdgeInsets.only(bottom: 12 * s),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                      horizontal: 16 * s, vertical: 14 * s),
                  child: Row(
                    children: [
                      // 사업장 아이콘
                      Container(
                        width: 40 * s,
                        height: 40 * s,
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.business_outlined,
                            size: 20 * s, color: theme.primaryColor),
                      ),
                      SizedBox(width: 12 * s),

                      // 사업장명 + 역할
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // 이름 로딩 중일 때 placeholder
                            if (name == null)
                              Container(
                                width: 120 * s,
                                height: 16 * s,
                                decoration: BoxDecoration(
                                  color: AppColors.grey200,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              )
                            else
                              Text(
                                name,
                                style: ResponsiveHelper.subtitleStyle(ctx),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            SizedBox(height: 3 * s),
                            Text(
                              '서브관리자',
                              style: ResponsiveHelper.smallStyle(ctx,
                                  color: AppColors.grey500),
                            ),
                          ],
                        ),
                      ),

                      // 탈퇴 버튼 / 로딩
                      if (isProc)
                        SizedBox(
                          width: 20 * s,
                          height: 20 * s,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.error),
                        )
                      else
                        TextButton(
                          onPressed: () => _leave(ctx, bizId),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                            padding: EdgeInsets.symmetric(
                                horizontal: 12 * s, vertical: 8 * s),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: Text('탈퇴하기',
                              style: ResponsiveHelper.smallStyle(ctx,
                                  color: AppColors.error,
                                  fontWeight: FontWeight.w600)),
                        ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
