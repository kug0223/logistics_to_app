import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/core/business_model.dart';
import '../providers/user_provider.dart';
import '../services/firestore_service.dart';
import '../theme/app_colors.dart';
import '../utils/dialog_helper.dart';
import '../utils/toast_helper.dart';
import '../utils/responsive_helper.dart';
import '../utils/image_helper.dart';

/// 공통 사업장 선택 헬퍼
///
/// 0개 → 경고 토스트 + null 반환
/// 1개 → 즉시 반환
/// 2개+ → 바텀시트 피커 후 반환
class BusinessPickerHelper {
  static Future<BusinessModel?> pick(
    BuildContext context, {
    bool approvedOnly = true,
    String dialogTitle = '사업장 선택',
  }) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;
    if (uid == null) {
      ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
      return null;
    }

    List<BusinessModel> businesses;
    if (userProvider.isSubAdmin) {
      final bizId = userProvider.effectiveBusinessId;
      if (bizId == null) {
        ToastHelper.showWarning('사업장 정보를 찾을 수 없습니다');
        return null;
      }
      final biz = await FirestoreService().getBusinessById(bizId);
      businesses = biz != null ? [biz] : [];
    } else {
      // CF callableGetMyBusiness 대신 UserProvider에 이미 있는 managedBusinessIds로
      // 병렬 doc.get — CF 콜드스타트(1–3초) 제거, Firestore 오프라인 캐시 활용
      final managedIds = userProvider.currentUser?.managedBusinessIds ?? [];
      businesses = await FirestoreService().getBusinessesByIds(managedIds);
    }

    if (approvedOnly) {
      businesses = businesses.where((b) => b.isApproved).toList();
    }

    if (businesses.isEmpty) {
      ToastHelper.showWarning('등록된 사업장이 없습니다');
      return null;
    }

    if (businesses.length == 1) return businesses.first;

    if (!context.mounted) return null;
    return _showPickerSheet(context, businesses, title: dialogTitle);
  }

  /// 이미 조회된 목록에서 선택 — Firestore 재쿼리 없음
  /// 0개 → 경고 토스트 + null, 1개 → 즉시 반환, 2개+ → 피커
  static Future<BusinessModel?> pickFromList(
    BuildContext context,
    List<BusinessModel> businesses, {
    String dialogTitle = '사업장 선택',
  }) async {
    if (businesses.isEmpty) {
      ToastHelper.showWarning('등록된 사업장이 없습니다');
      return null;
    }
    if (businesses.length == 1) return businesses.first;
    if (!context.mounted) return null;
    return _showPickerSheet(context, businesses, title: dialogTitle);
  }

  static Future<BusinessModel?> _showPickerSheet(
    BuildContext context,
    List<BusinessModel> businesses, {
    required String title,
  }) {
    return DialogHelper.showSheet<BusinessModel>(
      context,
      builder: (ctx) => _BusinessPickerSheet(businesses: businesses, title: title),
    );
  }
}

class _BusinessPickerSheet extends StatelessWidget {
  final List<BusinessModel> businesses;
  final String title;

  const _BusinessPickerSheet({required this.businesses, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 핸들바
        const SizedBox(height: 12),
        Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: AppColors.grey300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 16),
        // 헤더
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                visualDensity: VisualDensity.compact,
                color: AppColors.grey600,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Divider(height: 1, color: AppColors.grey100),
        const SizedBox(height: 4),
        // 사업장 목록
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final biz in businesses)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(context, biz),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        child: Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: biz.mainImageUrl != null
                                  ? ImageHelper.buildCachedImage(
                                      biz.mainImageUrl!,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      memCacheWidth: 88,
                                    )
                                  : Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: theme.primaryColor
                                            .withValues(alpha: 0.1),
                                        borderRadius:
                                            BorderRadius.circular(14),
                                      ),
                                      child: Icon(Icons.business,
                                          color: theme.primaryColor,
                                          size: 22),
                                    ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Text(
                                biz.name,
                                style: ResponsiveHelper.bodyStyle(context)
                                    .copyWith(fontWeight: FontWeight.w600),
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                color: AppColors.grey300, size: 20),
                          ],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
