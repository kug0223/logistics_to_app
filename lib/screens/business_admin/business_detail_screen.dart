import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

// Models
import '../../models/core/business_model.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';

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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.business.publicName),
        actions: [
          // 수정 버튼
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => BusinessFormScreen(
                    business: widget.business,
                  ),
                ),
              );
              if (result == true && mounted) {
                Navigator.pop(context, true);  // 리스트 화면으로 돌아가면서 새로고침
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
                  // 사업장명 + 평점
                  _buildHeader(context, theme),

                  SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                  // 기본 정보
                  _buildBasicInfo(context, theme),

                  SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                  // 시설 및 환경
                  _buildFacilities(context, theme),

                  // 사업장 사진들
                  if (widget.business.imageUrls != null &&
                      widget.business.imageUrls!.isNotEmpty) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                    _buildPhotoGallery(context, theme),
                  ],

                  SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                  // 오시는 길
                  _buildLocation(context, theme),

                  // 상세 안내
                  if (widget.business.detailedDescription != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                    _buildDescription(context, theme),
                  ],

                  // 주의사항
                  if (widget.business.precautions != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                    _buildPrecautions(context, theme),
                  ],

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
    if (widget.business.mainImageUrl != null) {
      images.add(widget.business.mainImageUrl!);
    }
    
    // 추가 이미지들
    if (widget.business.imageUrls != null) {
      images.addAll(widget.business.imageUrls!);
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
          widget.business.publicName,
          style: ResponsiveHelper.titleStyle(context).copyWith(
            fontSize: ResponsiveHelper.getFontSize(context, 22),
            fontWeight: FontWeight.bold,
          ),
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 8)),

        // 평점
        if (widget.business.rating != null)
          Row(
            children: [
              ...List.generate(
                5,
                (index) => Icon(
                  index < widget.business.rating!.floor()
                      ? Icons.star
                      : Icons.star_border,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: Colors.amber,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '${widget.business.rating!.toStringAsFixed(1)}',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              if (widget.business.reviewCount != null)
                Text(
                  ' (${widget.business.reviewCount}명)',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: Colors.grey[600],
                  ),
                ),
            ],
          ),

        // 한 줄 소개
        if (widget.business.oneLineIntro != null) ...[
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
                    widget.business.oneLineIntro!,
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
              _buildInfoRow(context, '업종', widget.business.category),
              if (widget.business.subCategory.isNotEmpty) ...[
                Divider(height: ResponsiveHelper.spacing(context, 24)),
                _buildInfoRow(context, '세부 업종', widget.business.subCategory),
              ],
              Divider(height: ResponsiveHelper.spacing(context, 24)),
              _buildInfoRow(
                context,
                '사업자번호',
                widget.business.formattedBusinessNumber,
              ),
              if (widget.business.phone != null) ...[
                Divider(height: ResponsiveHelper.spacing(context, 24)),
                _buildInfoRow(
                  context,
                  '연락처',
                  widget.business.phone!,
                  trailing: IconButton(
                    icon: Icon(
                      Icons.phone,
                      color: theme.primaryColor,
                      size: ResponsiveHelper.iconSize(context, 20),
                    ),
                    onPressed: () => _callPhone(widget.business.phone!),
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
                widget.business.parkingAvailable ? '가능' : '불가',
                widget.business.parkingAvailable,
              ),

              // 식사
              if (widget.business.mealProvided != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                _buildFacilityItem(
                  context,
                  Icons.restaurant,
                  '식사 제공',
                  widget.business.mealProvided!,
                  widget.business.mealProvided != '없음',
                ),
              ],

              // 복장
              if (widget.business.uniformProvided != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                _buildFacilityItem(
                  context,
                  Icons.checkroom,
                  '복장',
                  widget.business.uniformProvided!,
                  widget.business.uniformProvided != '없음',
                ),
              ],

              // 편의시설
              if (widget.business.facilities != null &&
                  widget.business.facilities!.isNotEmpty) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                _buildFacilityItem(
                  context,
                  Icons.star_outline,
                  '편의시설',
                  widget.business.facilities!.join(', '),
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
            itemCount: widget.business.imageUrls!.length,
            itemBuilder: (context, index) {
              return Container(
                width: 120,
                margin: EdgeInsets.only(
                  right: ResponsiveHelper.spacing(context, 12),
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  image: DecorationImage(
                    image: NetworkImage(widget.business.imageUrls![index]),
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
              // 주소
              Row(
                children: [
                  Icon(
                    Icons.location_on,
                    size: ResponsiveHelper.iconSize(context, 20),
                    color: theme.primaryColor,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      widget.business.address,
                      style: ResponsiveHelper.bodyStyle(context),
                    ),
                  ),
                ],
              ),

              // 지하철
              if (widget.business.nearestStation != null) ...[
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
                        '${widget.business.nearestStation}${widget.business.walkingMinutes != null ? " 도보 ${widget.business.walkingMinutes}분" : ""}',
                        style: ResponsiveHelper.bodyStyle(context),
                      ),
                    ),
                  ],
                ),
              ],

              // 버스
              if (widget.business.busInfo != null) ...[
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
                        widget.business.busInfo!,
                        style: ResponsiveHelper.bodyStyle(context),
                      ),
                    ),
                  ],
                ),
              ],

              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              // 버튼들
              Row(
                children: [
                  Expanded(
                    child: CommonWidgets.outlineButton(
                      context: context,
                      text: '지도 보기',
                      icon: Icons.map,
                      onPressed: () => _openMap(),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: CommonWidgets.outlineButton(
                      context: context,
                      text: '길찾기',
                      icon: Icons.directions,
                      onPressed: () => _openDirections(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
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
            widget.business.detailedDescription!,
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
          message: widget.business.precautions!,
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

  /// 지도 열기 (Kakao Map)
  void _openMap() async {
    if (widget.business.latitude == null || widget.business.longitude == null) {
      ToastHelper.showError('위치 정보가 없습니다');
      return;
    }

    final uri = Uri.parse(
      'https://map.kakao.com/link/map/${widget.business.publicName},${widget.business.latitude},${widget.business.longitude}',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ToastHelper.showError('지도를 열 수 없습니다');
    }
  }

  /// 길찾기
  void _openDirections() async {
    if (widget.business.latitude == null || widget.business.longitude == null) {
      ToastHelper.showError('위치 정보가 없습니다');
      return;
    }

    final uri = Uri.parse(
      'https://map.kakao.com/link/to/${widget.business.publicName},${widget.business.latitude},${widget.business.longitude}',
    );

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      ToastHelper.showError('길찾기를 열 수 없습니다');
    }
  }
}