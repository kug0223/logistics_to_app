import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Models
import '../../models/core/business_model.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/maps/kakao_map_widget.dart';
import '../../widgets/maps/full_map_dialog.dart';

// Screen
import 'business_form_screen.dart';


/// 🏢 사업장 상세 화면
class BusinessDetailScreen extends StatefulWidget {
  final BusinessModel business;

  const BusinessDetailScreen({
    super.key,
    required this.business,
  });

  @override
  State<BusinessDetailScreen> createState() => _BusinessDetailScreenState();
}

class _BusinessDetailScreenState extends State<BusinessDetailScreen> {
  int _currentImageIndex = 0;
  late BusinessModel _currentBusiness;
  
  @override
  void initState() {
    super.initState();
    _currentBusiness = widget.business;
  }

  // ✅ Firestore에서 최신 데이터 다시 가져오기
  Future<void> _reloadBusiness() async {
    try {
      print('🔄 사업장 데이터 재조회 시작: ${_currentBusiness.id}');
      
      final doc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(_currentBusiness.id)
          .get(const GetOptions(source: Source.server));
      
      if (doc.exists && mounted) {
        setState(() {
          _currentBusiness = BusinessModel.fromMap(doc.data()!, doc.id);
        });
        print('✅ 사업장 데이터 업데이트 완료!');
        ToastHelper.showSuccess('사업장 정보가 업데이트되었습니다');
      }
    } catch (e) {
      print('❌ 사업장 재조회 실패: $e');
      ToastHelper.showError('업데이트된 정보를 불러오는데 실패했습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
        appBar: AppBar(
          title: Text(_currentBusiness.name),
          actions: [
            // 수정 버튼
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                final result = await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BusinessFormScreen(
                      business: _currentBusiness,
                    ),
                  ),
                );
                if (result == true && mounted) {
                  // ✅ Firestore에서 최신 데이터 다시 가져오기!
                  await _reloadBusiness();
                }
              },
            ),
          ],
        ),
        body: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 이미지 슬라이드
              _buildImageSlider(context),

              Padding(
                padding: ResponsiveHelper.cardPadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. 사업장명 + 평점
                    _buildHeader(context, theme),

                    // 2. 사업장 소개 (상세 안내)
                    if (_currentBusiness.detailedDescription != null) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                      _buildDescription(context, theme),
                    ],

                    // 3. 사업장 사진
                    if (_currentBusiness.imageUrls != null &&
                        _currentBusiness.imageUrls!.isNotEmpty) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                      _buildPhotoGallery(context, theme),
                    ],

                    // 4. 준비사항
                    if (_currentBusiness.precautions != null) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                      _buildPrecautions(context, theme),
                    ],

                    SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                    // 5. 시설 및 환경
                    _buildFacilities(context, theme),

                    SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                    // 6. 오시는 길
                    _buildLocation(context, theme),

                    SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                    // 7. 기본 정보 (맨 아래)
                    _buildBasicInfo(context, theme),

                    SizedBox(height: ResponsiveHelper.spacing(context, 32)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
  }

  /// 📸 이미지 슬라이더
  Widget _buildImageSlider(BuildContext context) {
    final images = <String>[];
    
    // 대표 이미지 추가
    if (_currentBusiness.mainImageUrl != null) {
      images.add(_currentBusiness.mainImageUrl!);
    }
    
    // 추가 이미지들
    if (_currentBusiness.imageUrls != null) {
      images.addAll(_currentBusiness.imageUrls!);
    }

    if (images.isEmpty) {
      // 이미지가 없을 때
      return Container(
        height: 250,
        color: Colors.grey[200],
        child: Center(
          child: Icon(
            Icons.business,
            size: ResponsiveHelper.iconSize(context, 80),
            color: Colors.grey[400],
          ),
        ),
      );
    }

    return Stack(
      children: [
        // 이미지
        SizedBox(
          height: 250,
          child: PageView.builder(
            itemCount: images.length,
            onPageChanged: (index) {
              setState(() => _currentImageIndex = index);
            },
            itemBuilder: (context, index) {
              return Image.network(
                images[index],
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[200],
                    child: Icon(
                      Icons.broken_image,
                      size: ResponsiveHelper.iconSize(context, 48),
                      color: Colors.grey[400],
                    ),
                  );
                },
              );
            },
          ),
        ),

        // 인디케이터
        if (images.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                images.length,
                (index) => Container(
                  width: 8,
                  height: 8,
                  margin: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 4),
                  ),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _currentImageIndex == index
                        ? Colors.white
                        : Colors.white.withOpacity(0.4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 🏢 헤더 (사업장명 + 평점 + 한 줄 소개)
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 사업장명
        Text(
          _currentBusiness.name,
          style: ResponsiveHelper.titleStyle(context).copyWith(
            fontSize: ResponsiveHelper.getFontSize(context, 22),
            fontWeight: FontWeight.bold,
          ),
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 8)),

        // 평점
        if (_currentBusiness.rating != null)
          Row(
            children: [
              ...List.generate(
                5,
                (index) => Icon(
                  index < _currentBusiness.rating!.floor()
                      ? Icons.star
                      : Icons.star_border,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: Colors.amber,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                _currentBusiness.rating!.toStringAsFixed(1),
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (_currentBusiness.reviewCount != null)
                Text(
                  ' (${_currentBusiness.reviewCount}명)',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: Colors.grey[600],
                  ),
                ),
            ],
          ),

        // 한 줄 소개
        if (_currentBusiness.oneLineIntro != null) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: theme.primaryColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.format_quote,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: theme.primaryColor,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    _currentBusiness.oneLineIntro!,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontStyle: FontStyle.italic,
                      color: theme.primaryColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// 📊 기본 정보
  Widget _buildBasicInfo(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.sectionHeader(
          context: context,
          title: '기본 정보',
          icon: Icons.info_outline,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Container(
          decoration: CommonWidgets.cardDecoration(),
          padding: ResponsiveHelper.cardPadding(context),
          child: Column(
            children: [
              _buildInfoRow(context, '업종', _currentBusiness.category),
              if (_currentBusiness.subCategory.isNotEmpty) ...[
                Divider(height: ResponsiveHelper.spacing(context, 24)),
                _buildInfoRow(context, '세부 업종', _currentBusiness.subCategory),
              ],
              Divider(height: ResponsiveHelper.spacing(context, 24)),
              _buildInfoRow(
                context,
                '사업자번호',
                _currentBusiness.formattedBusinessNumber,
              ),
              if (_currentBusiness.phone != null) ...[
                Divider(height: ResponsiveHelper.spacing(context, 24)),
                _buildInfoRow(
                  context,
                  '연락처',
                  _formatPhoneNumber(_currentBusiness.phone!),  // ✅ 포맷 적용!
                  trailing: IconButton(
                    icon: Icon(
                      Icons.phone,
                      color: theme.primaryColor,
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                    onPressed: () => _callPhone(_currentBusiness.phone!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 🚗 시설 및 환경
  Widget _buildFacilities(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.sectionHeader(
          context: context,
          title: '시설 및 환경',
          icon: Icons.check_circle_outline,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Container(
          decoration: CommonWidgets.cardDecoration(),
          padding: ResponsiveHelper.cardPadding(context),
          child: Column(
            children: [
              // 주차
              _buildFacilityItem(
                context,
                Icons.local_parking,
                '주차',
                _currentBusiness.parkingAvailable ? '가능' : '불가',
                _currentBusiness.parkingAvailable,
              ),

              // 식사
              if (_currentBusiness.mealsProvided != null && _currentBusiness.mealsProvided!.isNotEmpty) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                _buildFacilityItem(
                  context,
                  Icons.restaurant,
                  '식사 제공',
                  _currentBusiness.mealsProvided!.join(', '),  // ⭐ List를 문자열로 조합
                  true,  // ⭐ 항목이 있으면 무조건 true
                ),
              ],

              // 복장
              if (_currentBusiness.uniformProvided != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                _buildFacilityItem(
                  context,
                  Icons.checkroom,
                  '복장',
                  _currentBusiness.uniformProvided!,
                  _currentBusiness.uniformProvided != '없음',
                ),
              ],

              // 편의시설
              if (_currentBusiness.facilities != null &&
                  _currentBusiness.facilities!.isNotEmpty) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                _buildFacilityItem(
                  context,
                  Icons.star_outline,
                  '편의시설',
                  _currentBusiness.facilities!.join(', '),
                  true,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 📸 사진 갤러리
  Widget _buildPhotoGallery(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.sectionHeader(
          context: context,
          title: '사업장 사진',
          icon: Icons.photo_library_outlined,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _currentBusiness.imageUrls!.length,
            itemBuilder: (context, index) {
              return Container(
                width: 120,
                margin: EdgeInsets.only(
                  right: ResponsiveHelper.spacing(context, 12),
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  image: DecorationImage(
                    image: NetworkImage(_currentBusiness.imageUrls![index]),
                    fit: BoxFit.cover,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 🗺️ 오시는 길
  Widget _buildLocation(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.sectionHeader(
          context: context,
          title: '오시는 길',
          icon: Icons.map_outlined,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Container(
          decoration: CommonWidgets.cardDecoration(),
          padding: ResponsiveHelper.cardPadding(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 주소 + 상세주소 + 복사 버튼
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.location_on,
                    size: ResponsiveHelper.iconSize(context, 20),
                    color: theme.primaryColor,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 기본 주소
                        Text(
                          _currentBusiness.address,
                          style: ResponsiveHelper.bodyStyle(context),
                        ),
                        // 상세주소 (있을 경우)
                        if (_currentBusiness.detailAddress != null && 
                            _currentBusiness.detailAddress!.isNotEmpty) ...[
                          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            _currentBusiness.detailAddress!,
                            style: ResponsiveHelper.bodyStyle(context),
                          ),
                        ],
                        // 📋 주소 복사 버튼
                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        InkWell(
                          onTap: () {
                            // 주소 + 상세주소 함께 복사
                            String fullAddress = _currentBusiness.address;
                            if (_currentBusiness.detailAddress != null && 
                                _currentBusiness.detailAddress!.isNotEmpty) {
                              fullAddress += ' ${_currentBusiness.detailAddress}';
                            }
                            Clipboard.setData(ClipboardData(text: fullAddress));
                            ToastHelper.showSuccess('주소가 복사되었습니다');
                          },
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.content_copy,
                                size: ResponsiveHelper.iconSize(context, 14),
                                color: theme.primaryColor,
                              ),
                              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                              Text(
                                '주소 복사',
                                style: ResponsiveHelper.smallStyle(context).copyWith(
                                  color: theme.primaryColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              // 지하철
              if (_currentBusiness.nearestStation != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                Row(
                  children: [
                    Icon(
                      Icons.subway,
                      size: ResponsiveHelper.iconSize(context, 20),
                      color: Colors.blue[700],
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        '${_currentBusiness.nearestStation}${_currentBusiness.walkingMinutes != null ? " 도보 ${_currentBusiness.walkingMinutes}분" : ""}',
                        style: ResponsiveHelper.bodyStyle(context),
                      ),
                    ),
                  ],
                ),
              ],

              // 버스
              if (_currentBusiness.busInfo != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                Row(
                  children: [
                    Icon(
                      Icons.directions_bus,
                      size: ResponsiveHelper.iconSize(context, 20),
                      color: Colors.green[700],
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        _currentBusiness.busInfo!,
                        style: ResponsiveHelper.bodyStyle(context),
                      ),
                    ),
                  ],
                ),
              ],

              // ✨ 지도 미리보기 (NEW!)
              if (_currentBusiness.latitude != null && _currentBusiness.longitude != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                GestureDetector(
                  onTap: () => _showFullMap(context),
                  child: KakaoMapWidget(
                    latitude: _currentBusiness.latitude!,
                    longitude: _currentBusiness.longitude!,
                    placeName: _currentBusiness.name,
                    height: ResponsiveHelper.spacing(context, 250),
                    showControls: false,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                Center(
                  child: TextButton.icon(
                    onPressed: () => _showFullMap(context),
                    icon: Icon(
                      Icons.zoom_out_map,
                      size: ResponsiveHelper.iconSize(context, 18),
                    ),
                    label: Text(
                      '큰 지도 보기',
                      style: ResponsiveHelper.bodyStyle(context),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// 전체 화면 지도 보기 (NEW!)
  void _showFullMap(BuildContext context) {
    if (_currentBusiness.latitude == null || _currentBusiness.longitude == null) {
      ToastHelper.showError('위치 정보가 없습니다');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => FullMapDialog(business: _currentBusiness),
    );
  }

  /// 📝 상세 안내
  Widget _buildDescription(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.sectionHeader(
          context: context,
          title: '사업장 소개',
          icon: Icons.description_outlined,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Container(
          width: double.infinity,
          decoration: CommonWidgets.cardDecoration(),
          padding: ResponsiveHelper.cardPadding(context),
          child: Text(
            _currentBusiness.detailedDescription!,
            style: ResponsiveHelper.bodyStyle(context),
          ),
        ),
      ],
    );
  }

  /// ⚠️ 주의사항
  Widget _buildPrecautions(BuildContext context, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.sectionHeader(
          context: context,
          title: '준비사항',
          icon: Icons.warning_amber_outlined,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        CommonWidgets.infoCard(
          context: context,
          message: _currentBusiness.precautions!,
          icon: Icons.info_outline,
          color: Colors.orange[700],
        ),
      ],
    );
  }

  /// 정보 행
  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value, {
    Widget? trailing,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: Colors.grey[600],
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  /// 시설 항목
  Widget _buildFacilityItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    bool isAvailable,
  ) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: isAvailable ? Colors.green[50] : Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 20),
            color: isAvailable ? Colors.green[700] : Colors.grey[600],
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  color: Colors.grey[600],
                ),
              ),
              Text(
                value,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        Icon(
          isAvailable ? Icons.check_circle : Icons.cancel,
          color: isAvailable ? Colors.green : Colors.grey,
          size: ResponsiveHelper.iconSize(context, 20),
        ),
      ],
    );
  }

  /// 전화 걸기
  void _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ToastHelper.showError('전화를 걸 수 없습니다');
    }
  }

  /// 전화번호 포맷팅 (010-1234-5678)
  String _formatPhoneNumber(String phone) {
    // 숫자만 추출
    final numbers = phone.replaceAll(RegExp(r'[^0-9]'), '');
    
    if (numbers.length == 10) {
      // 010-123-4567 (10자리)
      return '${numbers.substring(0, 3)}-${numbers.substring(3, 6)}-${numbers.substring(6)}';
    } else if (numbers.length == 11) {
      // 010-1234-5678 (11자리)
      return '${numbers.substring(0, 3)}-${numbers.substring(3, 7)}-${numbers.substring(7)}';
    } else if (numbers.length == 9) {
      // 02-123-4567 (서울 지역번호)
      return '${numbers.substring(0, 2)}-${numbers.substring(2, 5)}-${numbers.substring(5)}';
    }
    
    // 기타 형식은 그대로 반환
    return phone;
  }
}