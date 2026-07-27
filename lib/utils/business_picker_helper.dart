import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/core/business_model.dart';
import '../providers/user_provider.dart';
import '../services/firestore_service.dart';
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
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 20),
              vertical: ResponsiveHelper.spacing(context, 16),
            ),
            child: Text(
              title,
              style: ResponsiveHelper.titleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const Divider(height: 1),
          ...businesses.map((biz) => ListTile(
                leading: biz.mainImageUrl != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ImageHelper.buildCachedImage(
                          biz.mainImageUrl!,
                          width: 40,
                          height: 40,
                          fit: BoxFit.cover,
                          memCacheWidth: 80,
                        ),
                      )
                    : Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.primaryColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(Icons.business,
                            color: theme.primaryColor, size: 20),
                      ),
                title: Text(
                  biz.name,
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                onTap: () => Navigator.pop(context, biz),
              )),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        ],
      ),
    );
  }
}
