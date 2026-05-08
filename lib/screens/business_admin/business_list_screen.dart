import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';

// Models
import '../../models/core/business_model.dart';

// Providers
import '../../providers/user_provider.dart';

// Services
import '../../services/firestore_service.dart';

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
import '../common/settings_screen.dart';
import '../../widgets/dialogs/styled_dialog.dart';
import '../../theme/app_colors.dart';

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

  @override
  void initState() {
    super.initState();
    _loadBusinesses();
  }

  /// 사업장 목록 로드
  Future<void> _loadBusinesses({bool forceServer = false}) async {
    setState(() => _isLoading = true);

    try {
      final userProvider = context.read<UserProvider>();
      final ownerId = userProvider.currentUser?.uid;

      if (ownerId == null) return;

      List<BusinessModel> businesses;
      
      businesses = await _firestoreService.getMyBusiness(ownerId);

      setState(() {
        _businesses = businesses;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 사업장 로드 실패: $e');
      ToastHelper.showError('사업장 목록을 불러오는데 실패했습니다');
      setState(() => _isLoading = false);
    }
  }

  /// 사업장 삭제
  Future<void> _deleteBusiness(BusinessModel business) async {
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '사업장 삭제',
      message: '${business.name}을(를) 삭제하시겠습니까?\n모든 TO와 데이터가 함께 삭제됩니다.',
      confirmText: '삭제',
    );

    if (confirmed != true) return;

    try {
      final storage = FirebaseStorage.instance;
      
      // ✅ 1. 대표 이미지 삭제
      if (business.mainImageUrl != null) {
        try {
          await storage.refFromURL(business.mainImageUrl!).delete();
          debugPrint('✅ 대표 이미지 삭제');
        } catch (e) {
          debugPrint('⚠️ 대표 이미지 삭제 실패: $e');
        }
      }
      
      // ✅ 2. 추가 이미지들 삭제
      if (business.imageUrls != null) {
        for (var url in business.imageUrls!) {
          try {
            await storage.refFromURL(url).delete();
            debugPrint('✅ 추가 이미지 삭제');
          } catch (e) {
            debugPrint('⚠️ 추가 이미지 삭제 실패: $e');
          }
        }
      }
      
      // ✅ 3. 업무유형들의 이미지도 삭제
      final workTypesSnapshot = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(business.id)
          .collection('workTypes')
          .get();
      
      for (var doc in workTypesSnapshot.docs) {
        final data = doc.data();
        if (data['thumbnailUrl'] != null) {
          try {
            await storage.refFromURL(data['thumbnailUrl']).delete();
          } catch (e) {
            debugPrint('⚠️ 업무유형 썸네일 삭제 실패: $e');
          }
        }
        if (data['images'] != null) {
          for (var url in List<String>.from(data['images'])) {
            try {
              await storage.refFromURL(url).delete();
            } catch (e) {
              debugPrint('⚠️ 업무유형 이미지 삭제 실패: $e');
            }
          }
        }
      }

      // ✅ 4. Firestore에서 삭제
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(business.id)
          .delete();
          
      ToastHelper.showSuccess('사업장이 삭제되었습니다');
      _loadBusinesses();
    } catch (e) {
      debugPrint('❌ 사업장 삭제 실패: $e');
      ToastHelper.showError('사업장 삭제에 실패했습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('내 사업장 관리'),
        actions: [
          // 새 사업장 추가 버튼
          IconButton(
            icon: Icon(
              Icons.add_circle_outline,
              size: ResponsiveHelper.iconSize(context, 28),
            ),
            onPressed: _navigateToBusinessForm, // ✅ 변경
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _businesses.isEmpty
              ? _buildEmptyState(context)
              : _buildBusinessList(context, theme),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.business_outlined,
            size: ResponsiveHelper.iconSize(context, 80),
            color: AppColors.grey400,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          Text(
            '등록된 사업장이 없습니다',
            style: ResponsiveHelper.titleStyle(context).copyWith(
              color: AppColors.grey600,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Text(
            '사업장을 등록하고 TO를 관리해보세요',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: AppColors.grey500,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 32)),
          CommonWidgets.primaryButton(
            context: context,
            text: '사업장 등록하기',
            icon: Icons.add_business,
            onPressed: _navigateToBusinessForm, // ✅ 변경
          ),
        ],
      ),
    );
  }

  /// 사업장 리스트
  Widget _buildBusinessList(BuildContext context, ThemeData theme) {
    return ListView.builder(
      padding: ResponsiveHelper.cardPadding(context),
      itemCount: _businesses.length + 1, // +1 for "새 사업장 추가" 버튼
      itemBuilder: (context, index) {
        if (index == _businesses.length) {
          // 마지막: 새 사업장 추가 버튼
          return _buildAddButton(context, theme);
        }

        final business = _businesses[index];
        return _buildBusinessCard(context, theme, business);
      },
    );
  }

  /// ✨ 사업장 카드 (간단 버전)
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
        // ⭐ 그림자 강화
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
        // ⭐ 승인 대기중일 때 테두리 추가
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
              if (result == true) _loadBusinesses(forceServer: true);
            },
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: ResponsiveHelper.cardPadding(context),
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
                        // ⭐ 승인 상태 배지
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
          Text(
            business.rating!.toStringAsFixed(1),
            style: ResponsiveHelper.smallStyle(context).copyWith(
              fontWeight: FontWeight.bold,
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
        Text(
          business.parkingAvailable ? '주차O' : '주차X',
          style: ResponsiveHelper.smallStyle(context).copyWith(
            color: business.parkingAvailable ? AppColors.successDark : AppColors.grey500,
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
        Text(
          business.mealsProvided != null && business.mealsProvided!.isNotEmpty
              ? '식사O' 
              : '식사X',
          style: ResponsiveHelper.smallStyle(context).copyWith(
            color: business.mealsProvided != null && business.mealsProvided!.isNotEmpty
                ? AppColors.successDark 
                : AppColors.grey500,
          ),
        ),
      ],
    );
  }

  /// 더보기 메뉴
  Widget _buildMoreMenu(BuildContext context, ThemeData theme, BusinessModel business) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: ResponsiveHelper.iconSize(context, 24),
        color: theme.primaryColor,
      ),
      // ⭐ 둥근 모서리
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      // ⭐ 그림자
      elevation: 8,
      onSelected: (value) async {
        switch (value) {
          case 'create_to':
            if (!business.isApproved) {
              ToastHelper.showWarning('승인된 사업장만 TO를 등록할 수 있습니다');
              return;
            }
            // 이메일 미인증 / 사업자등록증 미등록 사전 체크
            final user = Provider.of<UserProvider>(context, listen: false).currentUser;
            if (user != null) {
              final missing = <String>[];
              if (!user.isEmailVerified) missing.add('이메일 인증');
              if (user.businessLicenseImageUrl == null) missing.add('사업자등록증 등록');

              if (missing.isNotEmpty) {
                final goToSettings = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => StyledDialog(
                    title: '공고 등록 불가',
                    subtitle: '다음 항목을 먼저 완료해주세요',
                    icon: Icons.block_outlined,
                    headerColor: AppColors.error,
                    content: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...missing.map(
                          (item) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: StyledDialogInfoCard.error(item),
                          ),
                        ),
                        const SizedBox(height: 4),
                        StyledDialogInfoCard.info('설정 화면에서 완료 후 다시 시도해주세요.'),
                      ],
                    ),
                    actions: [
                      StyledDialogButton.cancel(
                        onPressed: () => Navigator.pop(ctx, false),
                      ),
                      StyledDialogButton.primary(
                        text: '설정으로 이동',
                        onPressed: () => Navigator.pop(ctx, true),
                      ),
                    ],
                  ),
                );
                if (goToSettings == true && context.mounted) {
                  Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                }
                return;
              }
            }
            await NavigationHelper.push<bool>(
              context,
              destination: const AdminCreateTOScreen(),
              onReturn: (result) {
                if (result == true) _loadBusinesses(forceServer: true);
              },
            );
            break;
          case 'detail':
            await NavigationHelper.push<bool>(
              context,
              destination: BusinessDetailScreen(business: business),
              onReturn: (result) {
                if (result == true) _loadBusinesses(forceServer: true);
              },
            );
            break;
          case 'edit':
            NavigationHelper.push<bool>(
              context,
              destination: BusinessFormScreen(business: business),
              onReturn: (result) {
                if (result == true) _loadBusinesses(forceServer: true);
              },
            );
            break;
          case 'delete':
            await _deleteBusiness(business);
            break;
        }
      },
      itemBuilder: (context) => [
        // TO 등록
        PopupMenuItem<String>(
          value: 'create_to',
          enabled: business.isApproved,
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(
                  color: business.isApproved 
                      ? theme.primaryColor.withValues(alpha: 0.1)
                      : theme.disabledColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.add_circle_outline,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: business.isApproved 
                      ? theme.primaryColor 
                      : theme.disabledColor,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text(
                'TO 등록',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: business.isApproved 
                      ? null 
                      : theme.disabledColor,
                ),
              ),
              if (!business.isApproved) ...[
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  '(승인필요)',
                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        // 상세보기
        PopupMenuItem<String>(
          value: 'detail',
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(
                  color: AppColors.infoBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.info_outline,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: AppColors.infoDark,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text('상세보기', style: ResponsiveHelper.bodyStyle(context)),
            ],
          ),
        ),
        // 수정
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(
                  color: AppColors.warningBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.edit,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: AppColors.warningDark,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text('수정', style: ResponsiveHelper.bodyStyle(context)),
            ],
          ),
        ),
        // 삭제
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.delete,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: theme.colorScheme.error,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Text(
                '삭제',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
          ),
        ),
      ],
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
        if (result == true) _loadBusinesses(forceServer: true);
      },
    );
  }
}
