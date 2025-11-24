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

// Screen
import 'business_detail_screen.dart';
import 'business_form_screen.dart';

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
  Future<void> _loadBusinesses() async {
    setState(() => _isLoading = true);

    try {
      final userProvider = context.read<UserProvider>();
      final ownerId = userProvider.currentUser?.uid;

      if (ownerId == null) return;

      final businesses = await _firestoreService.getMyBusiness(ownerId);

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
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BusinessFormScreen(),
                ),
              );
              if (result == true) _loadBusinesses();
            },
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
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const BusinessFormScreen(),
                ),
              );
              if (result == true) _loadBusinesses();
            },
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
      decoration: CommonWidgets.cardDecoration(),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => BusinessDetailScreen(
                business: business,
              ),
            ),
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
                    // 사업장명
                    Text(
                      business.publicName,
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
          business.mealProvided != null && business.mealProvided != '없음' 
              ? '식사O' 
              : '식사X',
          style: ResponsiveHelper.smallStyle(context).copyWith(
            color: business.mealProvided != null && business.mealProvided != '없음'
                ? Colors.green[700] 
                : Colors.grey[500],
          ),
        ),
      ],
    );
  }

  /// 더보기 메뉴
  Widget _buildMoreMenu(
    BuildContext context,
    ThemeData theme,
    BusinessModel business,
  ) {
    return PopupMenuButton<String>(
      icon: Icon(
        Icons.more_vert,
        size: ResponsiveHelper.iconSize(context, 24),
        color: theme.primaryColor,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'detail',
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: ResponsiveHelper.iconSize(context, 20),
                color: Colors.blue[600],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('자세히 보기'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(
                Icons.edit_outlined,
                size: ResponsiveHelper.iconSize(context, 20),
                color: Colors.orange[600],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('수정하기'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: ResponsiveHelper.iconSize(context, 20),
                color: Colors.red[600],
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              const Text('삭제하기'),
            ],
          ),
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'detail':
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BusinessDetailScreen(
                  business: business,
                ),
              ),
            );
            break;
          case 'edit':
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => BusinessFormScreen(
                  business: business,
                ),
              ),
            ).then((result) {
              if (result == true) _loadBusinesses();
            });
            break;
          case 'delete':
            _deleteBusiness(business);
            break;
        }
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
          onTap: () async {
            final result = await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const BusinessFormScreen(),
              ),
            );
            if (result == true) _loadBusinesses();
          },
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
}