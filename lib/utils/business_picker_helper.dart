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
import '../utils/text_layout.dart';

/// 공통 사업장 선택 헬퍼
///
/// 0개 → 경고 토스트 + null 반환
/// 1개 → 즉시 반환
/// 2개+ → 바텀시트 피커 후 반환
class BusinessPickerHelper {
  ///
  /// [includeClosed] [BUSINESS-ARCHIVE] 운영을 종료한 사업장도 고를 수 있게 한다.
  ///   계약·급여·정산·통계·리뷰처럼 **지나간 기록**을 보는 화면은 true 다 —
  ///   운영 종료 뒤에도 이미 일한 건의 급여·계약은 처리해야 한다.
  ///   업무·템플릿처럼 앞으로의 운영을 설정하는 화면은 false(기본).
  static Future<BusinessModel?> pick(
    BuildContext context, {
    bool approvedOnly = true,
    bool includeClosed = false,
    String dialogTitle = '사업장 선택',
  }) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;
    if (uid == null) {
      ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
      return null;
    }

    // [R8-P7.4] 조회 실패를 '등록된 사업장이 없습니다'로 바꾸지 않는다.
    //   여기는 공고 등록으로 들어가는 길목이다 — 못 읽은 것을 0개로 말하면
    //   관리자는 사업장이 사라졌다고 읽고 다시 만들려 한다. OrThrow 변형은
    //   이 구분을 위해 이미 있다(AH-V2-01).
    List<BusinessModel> businesses;
    try {
      if (userProvider.isSubAdmin) {
        final bizIds = userProvider.currentUser?.subAdminBusinessIds ?? [];
        if (bizIds.isEmpty) {
          ToastHelper.showWarning('사업장 정보를 찾을 수 없습니다');
          return null;
        }
        businesses = await FirestoreService().getBusinessesByIdsOrThrow(bizIds);
      } else {
        // CF callableGetMyBusiness 대신 UserProvider에 이미 있는 managedBusinessIds로
        // 병렬 doc.get — CF 콜드스타트(1–3초) 제거, Firestore 오프라인 캐시 활용
        final managedIds = userProvider.currentUser?.managedBusinessIds ?? [];
        businesses =
            await FirestoreService().getBusinessesByIdsOrThrow(managedIds);
      }
    } catch (e) {
      debugPrint('❌ [BusinessPicker] 사업장 조회 실패: $e');
      ToastHelper.showError('사업장 목록을 불러오지 못했습니다. 다시 시도해주세요');
      return null;
    }

    if (approvedOnly) {
      businesses = businesses
          .where((b) => b.isApproved || (includeClosed && b.isDeactivated))
          .toList();
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
    // [DU297 BP2] 큰 글자 배치 전환 기준 — DU264·295 와 같다(1.3배 이상).
    final stacked = MediaQuery.textScalerOf(context).scale(10) >= 13;
    // [DU297 BP1] 사업장 이름은 낱말 단위(identity), 읽기 이름 원문.
    Widget nameText(BusinessModel biz) => Text(
          TextLayout.identity(biz.name),
          semanticsLabel: biz.name,
          style: ResponsiveHelper.bodyStyle(context)
              .copyWith(fontWeight: FontWeight.w600),
        );
    final closedTag = Text(
      '운영 종료',
      style: ResponsiveHelper.captionStyle(context)
          .copyWith(color: AppColors.grey600),
    );
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
                // [DU297 BP4] compact(40×40) 제거 → 누름 48
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
                            // [DU297 BP2] 큰 글자에서는 '운영 종료' 를 이름 아래로
                            //   (옆에 두면 B320 2.0 이름 칸이 95px 로 줄어 '한빛 분 | 류센터').
                            Expanded(
                              child: stacked && biz.isDeactivated
                                  ? Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [nameText(biz), closedTag],
                                    )
                                  : nameText(biz),
                            ),
                            if (!stacked && biz.isDeactivated)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: closedTag,
                              ),
                            // [DU297 BP3] 화살표 grey300(1.32) → textTertiary
                            const Icon(Icons.chevron_right,
                                color: AppColors.textTertiary, size: 20),
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
