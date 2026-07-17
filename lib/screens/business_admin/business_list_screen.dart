import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Models
import '../../models/core/business_model.dart';

// Providers
import '../../providers/user_provider.dart';

// Services
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/image_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../common/document_management_screen.dart';
import '../../utils/navigation_helper.dart';

// Screen
import 'business_detail_screen.dart';
import 'business_form_screen.dart';
import 'to_management/create_to_screen.dart';
import '../../widgets/common/app_menu_sheet.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/loading_widget.dart';

/// 📋 내 사업장 관리 화면 (관리자 전용)
class BusinessListScreen extends StatefulWidget {
  const BusinessListScreen({super.key});

  @override
  State<BusinessListScreen> createState() => _BusinessListScreenState();
}

class _BusinessListScreenState extends State<BusinessListScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  List<BusinessModel> _businesses = [];
  bool _isLoading = true;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _loadBusinesses();
  }

  /// 사업장 목록 로드
  Future<void> _loadBusinesses({bool forceServer = false}) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final userProvider = context.read<UserProvider>();
      final ownerId = userProvider.currentUser?.uid;

      if (ownerId == null) {
        setState(() => _isLoading = false);
        return;
      }

      List<BusinessModel> businesses;

      // SubAdmin은 adminIds에 없으므로 effectiveBusinessId로 직접 조회
      final effectiveBizId = userProvider.effectiveBusinessId;
      if (userProvider.isSubAdmin && effectiveBizId != null) {
        final biz = await _firestoreService.getBusinessById(effectiveBizId);
        businesses = biz != null ? [biz] : [];
      } else {
        businesses = await _firestoreService.getMyBusiness(ownerId);
      }

      if (!mounted) return;
      setState(() {
        _businesses = businesses;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 사업장 로드 실패: $e');
      if (mounted) ToastHelper.showError('사업장 목록을 불러오는데 실패했습니다');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 사업장 삭제
  Future<void> _deleteBusiness(BusinessModel business) async {
    if (_isDeleting) return;
    setState(() => _isDeleting = true);
    try {
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '사업장 삭제',
      message: '${business.name}을(를) 삭제하시겠습니까?\n모든 TO와 데이터가 함께 삭제됩니다.',
      confirmText: '삭제',
    );

    if (confirmed != true || !mounted) return;

      final bizRef = FirebaseFirestore.instance.collection('businesses').doc(business.id);

      // 1. Storage URL 미리 수집 (Firestore 삭제 전에 읽어야 함)
      final workTypesSnapshot = await bizRef.collection('workTypes').get();

      // 2. Firestore 먼저 삭제 — 실패 시 Storage는 건드리지 않아 일관성 유지
      // onBusinessDeleted Cloud Function이 tos/applications/attendance를 추가 정리함
      final memberDocs = await bizRef.collection('members').get();
      final subBatch = FirebaseFirestore.instance.batch();
      for (final doc in workTypesSnapshot.docs) { subBatch.delete(doc.reference); }
      for (final doc in memberDocs.docs) { subBatch.delete(doc.reference); }
      // [BUG-수정] T-H-2: bizRef.delete()를 subBatch에 포함시켜 원자적 커밋.
      // 기존에는 subBatch.commit() 성공 후 별도 await bizRef.delete()를 호출해,
      // 두 번째 작업 실패 시 서브컬렉션은 삭제됐으나 비즈니스 문서가 남는 불일치 발생.
      // workTypes + members 최대합이 500 ops를 넘기 어려우므로 단일 배치로 통합.
      subBatch.delete(bizRef); // 부모 문서도 배치에 포함 — 원자적 삭제 보장
      await subBatch.commit();

      // 3. Firestore 삭제 성공 후 Storage 정리 — StorageService 경유(CF로 businesses/ 삭제)
      final urlsToDelete = <String>[
        if (business.mainImageUrl != null) business.mainImageUrl!,
        ...?business.imageUrls,
        for (final doc in workTypesSnapshot.docs) ...[
          if (doc.data()['thumbnailUrl'] != null) doc.data()['thumbnailUrl'] as String,
          ...List<String>.from(doc.data()['images'] ?? []),
        ],
      ];
      if (urlsToDelete.isNotEmpty) {
        await StorageService().deleteMultipleByUrls(urlsToDelete);
      }
          
      if (!mounted) return;
      ToastHelper.showSuccess('사업장이 삭제되었습니다');
      _loadBusinesses();
    } catch (e) {
      debugPrint('❌ 사업장 삭제 실패: $e');
      if (mounted) ToastHelper.showError('사업장 삭제에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userProvider = context.read<UserProvider>();
    final isSubAdmin = userProvider.isSubAdmin;

    return GradientScaffold(
      title: '내 사업장 관리',
      onRefresh: () => _loadBusinesses(forceServer: true),
      body: _isLoading
          ? const LoadingWidget()
          : _businesses.isEmpty
              ? _buildEmptyState(context)
              : _buildBusinessList(context, theme, isSubAdmin),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState(BuildContext context) {
    return AppEmptyState(
      icon: Icons.business_outlined,
      title: '등록된 사업장이 없습니다',
      subtitle: '사업장을 등록하고 공고를 관리해보세요',
      action: CommonWidgets.primaryButton(
        context: context,
        text: '사업장 등록하기',
        icon: Icons.add_business,
        onPressed: _navigateToBusinessForm,
      ),
    );
  }

  /// 사업장 리스트
  Widget _buildBusinessList(BuildContext context, ThemeData theme, bool isSubAdmin) {
    // SubAdmin은 사업장 추가 버튼 불필요
    final itemCount = isSubAdmin ? _businesses.length : _businesses.length + 1;
    return ListView.builder(
      padding: ResponsiveHelper.listPadding(context),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == _businesses.length) {
          return _buildAddButton(context, theme);
        }

        final business = _businesses[index];
        return _buildBusinessCard(context, theme, business);
      },
    );
  }

  /// 사업장 카드
  Widget _buildBusinessCard(
    BuildContext context,
    ThemeData theme,
    BusinessModel business,
  ) {
    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 16),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: 1,
          ),
          BoxShadow(
            color: theme.primaryColor.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        // 승인 대기 시 테두리
        border: business.isApproved 
            ? null 
            : Border.all(
                color: theme.colorScheme.error.withValues(alpha: 0.3),
                width: 1.5,
              ),
      ),
      child: InkWell(
        onTap: () {
          NavigationHelper.push<bool>(
            context,
            destination: BusinessDetailScreen(business: business),
            onReturn: (result) {
              if (result == true && mounted) _loadBusinesses(forceServer: true);
            },
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: ResponsiveHelper.listPadding(context),
          child: Row(
            children: [
              // 이미지
              _buildBusinessImage(context, business),
              
              SizedBox(width: ResponsiveHelper.spacing(context, 16)),
              
              // 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 사업장명 + 승인 상태
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            business.name,
                            style: ResponsiveHelper.subtitleStyle(context).copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        // 승인 상태 배지
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 8),
                            vertical: ResponsiveHelper.spacing(context, 4),
                          ),
                          decoration: BoxDecoration(
                            color: business.isApproved 
                                ? theme.colorScheme.primaryContainer
                                : theme.colorScheme.errorContainer,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            business.isApproved ? '승인됨' : '승인대기',
                            style: ResponsiveHelper.tinyStyle(context).copyWith(
                              color: business.isApproved 
                                  ? theme.colorScheme.onPrimaryContainer
                                  : theme.colorScheme.onErrorContainer,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                    
                    // 주소
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          size: ResponsiveHelper.iconSize(context, 14),
                          color: AppColors.grey600,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                        Expanded(
                          child: Text(
                            business.address,
                            style: ResponsiveHelper.smallStyle(context).copyWith(
                              color: AppColors.grey600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    
                    // 빠른 정보 (평점, 주차, 식사)
                    _buildQuickInfo(context, business),
                  ],
                ),
              ),
              
              // 더보기 메뉴
              _buildMoreMenu(context, theme, business),
            ],
          ),
        ),
      ),
    );
  }

  /// 사업장 이미지
  Widget _buildBusinessImage(BuildContext context, BusinessModel business) {
    final size = ResponsiveHelper.iconSize(context, 80);

    if (business.mainImageUrl == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.grey200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.business, size: ResponsiveHelper.iconSize(context, 40), color: AppColors.grey400),
      );
    }

    return ImageHelper.buildCachedImage(
      business.mainImageUrl!,
      width: size,
      height: size,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(12),
      memCacheWidth: (size * 2).toInt(),
      fadeInDuration: const Duration(milliseconds: 150),
    );
  }

  /// 빠른 정보 (평점, 주차, 식사)
  Widget _buildQuickInfo(BuildContext context, BusinessModel business) {
    return Row(
      children: [
        // 평점
        if (business.rating != null) ...[
          Icon(
            Icons.star,
            size: ResponsiveHelper.iconSize(context, 14),
            color: AppColors.amberDark,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 2)),
          Flexible(
            child: Text(
              business.rating!.toStringAsFixed(1),
              overflow: TextOverflow.ellipsis,
              style: ResponsiveHelper.smallStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Container(
            width: 1,
            height: 12,
            color: AppColors.grey300,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        ],
        
        // 주차
        Flexible(
          child: Text(
            business.parkingAvailable ? '주차O' : '주차X',
            overflow: TextOverflow.ellipsis,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: business.parkingAvailable ? AppColors.successDark : AppColors.grey500,
            ),
          ),
        ),

        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Container(
          width: 1,
          height: 12,
          color: AppColors.grey300,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),

        // 식사
        Flexible(
          child: Text(
            business.mealsProvided != null && business.mealsProvided!.isNotEmpty
                ? '식사O'
                : '식사X',
            overflow: TextOverflow.ellipsis,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: business.mealsProvided != null && business.mealsProvided!.isNotEmpty
                  ? AppColors.successDark
                  : AppColors.grey500,
            ),
          ),
        ),
      ],
    );
  }

  /// 더보기 메뉴
  Widget _buildMoreMenu(BuildContext context, ThemeData theme, BusinessModel business) {
    return IconButton(
      icon: Icon(
        Icons.more_vert,
        size: ResponsiveHelper.iconSize(context, 24),
        color: theme.primaryColor,
      ),
      tooltip: '메뉴',
      onPressed: () => _showMoreMenuSheet(context, theme, business),
    );
  }

  void _showMoreMenuSheet(BuildContext context, ThemeData theme, BusinessModel business) {
    final userProvider = context.read<UserProvider>();
    final isSubAdmin = userProvider.isSubAdmin;
    final canManageTo = !isSubAdmin || userProvider.can((p) => p.canManageTo);

    AppMenuSheet.show(
      context: context,
      itemGroups: [
        if (business.isApproved && canManageTo)
          [
            AppMenuSheetItem(
              icon: Icons.add_circle_outline,
              label: '공고 등록',
              color: theme.primaryColor,
              onTap: () => _handleCreateTO(context, business),
            ),
          ],
        [
          AppMenuSheetItem(
            icon: Icons.info_outline,
            label: '상세보기',
            color: AppColors.info,
            onTap: () => NavigationHelper.push<bool>(
              context,
              destination: BusinessDetailScreen(business: business),
              onReturn: (result) {
                if (result == true && mounted) _loadBusinesses(forceServer: true);
              },
            ),
          ),
          if (!isSubAdmin)
            AppMenuSheetItem(
              icon: Icons.edit,
              label: '수정',
              color: AppColors.warning,
              onTap: () => NavigationHelper.push<bool>(
                context,
                destination: BusinessFormScreen(business: business),
                onReturn: (result) {
                  if (result == true && mounted) _loadBusinesses(forceServer: true);
                },
              ),
            ),
        ],
        if (!isSubAdmin)
          [
            AppMenuSheetItem(
              icon: Icons.delete,
              label: '삭제',
              color: AppColors.error,
              isDanger: true,
              onTap: () => _deleteBusiness(business),
            ),
          ],
      ],
    );
  }

  Future<void> _handleCreateTO(BuildContext context, BusinessModel business) async {
    if (!context.mounted) return;
    await NavigationHelper.push<bool>(
      context,
      destination: const AdminCreateTOScreen(),
      onReturn: (result) {
        if (result == true && mounted) _loadBusinesses(forceServer: true);
      },
    );
  }

  /// 새 사업장 추가 버튼
  Widget _buildAddButton(BuildContext context, ThemeData theme) {
    return Container(
      margin: EdgeInsets.only(
        top: ResponsiveHelper.spacing(context, 8),
        bottom: ResponsiveHelper.spacing(context, 16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _navigateToBusinessForm,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 20),
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.primaryColor.withValues(alpha: 0.3),
                width: 2,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_circle_outline,
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Text(
                  '새 사업장 추가',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: theme.primaryColor,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  /// 사업자등록증 체크 후 사업장 등록 화면으로 이동
  Future<void> _navigateToBusinessForm() async {
    final userProvider = context.read<UserProvider>();
    
    // 최신 사용자 정보 가져오기
    await userProvider.refreshCurrentUser();
    if (!mounted) return;

    final user = userProvider.currentUser;

    if (user == null) {
      ToastHelper.showError('로그인이 필요합니다.');
      return;
    }

    // 사업자등록증 미등록 시 다이얼로그
    if (user.businessLicenseImageUrl == null) {
      final shouldNavigate = await DialogHelper.showDocumentRequired(
        context,
        title: '사업자등록증 등록 필요',
        missingDocuments: ['사업자등록증'],
      );
      if (!mounted) return;

      if (shouldNavigate) {
        NavigationHelper.push<bool>(
          context,
          destination: const DocumentManagementScreen(),
        );
      }
      return;
    }

    // 사업자등록증 있음 → 사업장 등록 화면으로
    await NavigationHelper.push<bool>(
      context,
      destination: const BusinessFormScreen(),
      onReturn: (result) {
        if (result == true && mounted) _loadBusinesses(forceServer: true);
      },
    );
  }
}
