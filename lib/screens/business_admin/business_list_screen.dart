import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../common/document_management_screen.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/cache_manager.dart';

// Screen
import 'business_detail_screen.dart';
import 'business_form_screen.dart';
import 'to_management/create_to_screen.dart';

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
      
      if (forceServer) {
        // 서버에서 직접 조회 (캐시 무시)
        final snapshot = await CacheManager.getCollectionWhere(
          'businesses',
          field: 'ownerId',
          isEqualTo: ownerId,
        );
        businesses = snapshot.docs
            .map((doc) => BusinessModel.fromMap(doc.data(), doc.id))
            .toList();
      } else {
        businesses = await _firestoreService.getMyBusiness(ownerId);
      }

      setState(() {
        _businesses = businesses;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 사업장 로드 실패: $e');
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
      // Firestore에서 직접 삭제
      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(business.id)
          .delete();
          
      ToastHelper.showSuccess('사업장이 삭제되었습니다');
      _loadBusinesses();
    } catch (e) {
      print('❌ 사업장 삭제 실패: $e');
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
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.business_outlined,
            size: ResponsiveHelper.iconSize(context, 80),
            color: Colors.grey[400],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          Text(
            '등록된 사업장이 없습니다',
            style: ResponsiveHelper.titleStyle(context).copyWith(
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Text(
            '사업장을 등록하고 TO를 관리해보세요',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: Colors.grey[500],
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
            color: Colors.black.withOpacity(0.08),
            blurRadius: 16,
            offset: const Offset(0, 4),
            spreadRadius: 1,
          ),
          BoxShadow(
            color: theme.primaryColor.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
        // ⭐ 승인 대기중일 때 테두리 추가
        border: business.isApproved 
            ? null 
            : Border.all(
                color: theme.colorScheme.error.withOpacity(0.3),
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
                          color: Colors.grey[600],
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                        Expanded(
                          child: Text(
                            business.address,
                            style: ResponsiveHelper.smallStyle(context).copyWith(
                              color: Colors.grey[600],
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
    return Container(
      width: ResponsiveHelper.iconSize(context, 80),
      height: ResponsiveHelper.iconSize(context, 80),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
        image: business.mainImageUrl != null
            ? DecorationImage(
                image: NetworkImage(business.mainImageUrl!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: business.mainImageUrl == null
          ? Icon(
              Icons.business,
              size: ResponsiveHelper.iconSize(context, 40),
              color: Colors.grey[400],
            )
          : null,
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
            color: Colors.amber,
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
            color: Colors.grey[300],
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        ],
        
        // 주차
        Text(
          business.parkingAvailable ? '주차O' : '주차X',
          style: ResponsiveHelper.smallStyle(context).copyWith(
            color: business.parkingAvailable ? Colors.green[700] : Colors.grey[500],
          ),
        ),
        
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Container(
          width: 1,
          height: 12,
          color: Colors.grey[300],
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        
        // 식사
        Text(
          business.mealsProvided != null && business.mealsProvided!.isNotEmpty
              ? '식사O' 
              : '식사X',
          style: ResponsiveHelper.smallStyle(context).copyWith(
            color: business.mealsProvided != null && business.mealsProvided!.isNotEmpty
                ? Colors.green[700] 
                : Colors.grey[500],
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
            // 승인 체크
            if (!business.isApproved) {
              ToastHelper.showWarning('승인된 사업장만 TO를 등록할 수 있습니다');
              return;
            }
            // ✅ 직접 화면 이동으로 변경!
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AdminCreateTOScreen(),
              ),
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
                      ? theme.primaryColor.withOpacity(0.1)
                      : theme.disabledColor.withOpacity(0.1),
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
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.info_outline,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: Colors.blue,
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
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.edit,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: Colors.orange,
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
                  color: theme.colorScheme.error.withOpacity(0.1),
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
                color: theme.primaryColor.withOpacity(0.3),
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
      
      if (shouldNavigate && mounted) {
        // 서류 관리 화면으로 이동
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const DocumentManagementScreen(),
          ),
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