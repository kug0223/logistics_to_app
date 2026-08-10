import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

// Models
import '../../models/core/business_model.dart';
import '../../providers/user_provider.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/image_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/maps/kakao_map_widget.dart';
import '../../widgets/maps/full_map_dialog.dart';

// Screen
import 'business_form_screen.dart';
import '../../utils/navigation_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/gradient_scaffold.dart';


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
  bool _hasChanges = false;
  
  @override
  void initState() {
    super.initState();
    _currentBusiness = widget.business;
  }

  // Firestore에서 최신 데이터 다시 가져오기
  Future<void> _reloadBusiness() async {
    try {
      debugPrint('🔄 사업장 데이터 재조회 시작: ${_currentBusiness.id}');
      
      final doc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(_currentBusiness.id)
          .get(const GetOptions(source: Source.server));
      
      final docData = doc.data();
      if (doc.exists && docData != null && mounted) {
        setState(() {
          _currentBusiness = BusinessModel.fromMap(docData, doc.id);
          _hasChanges = true;  // 변경 발생 표시
        });
        debugPrint('✅ 사업장 데이터 업데이트 완료!');
        ToastHelper.showSuccess('사업장 정보가 업데이트되었습니다');
      }
    } catch (e) {
      debugPrint('❌ 사업장 재조회 실패: $e');
      if (mounted) ToastHelper.showError('업데이트된 정보를 불러오는데 실패했습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop && _hasChanges) {
          // 이미 pop 되었고, 변경사항이 있으면 이전 화면에서 처리하도록
          // Navigator.pop의 result로는 전달 안되므로 별도 처리 필요 없음
          // business_list_screen에서 무조건 _loadBusinesses() 호출하는 방식 유지
        }
      },
      child: GradientScaffold(
        title: _currentBusiness.name,
        onBack: () => NavigationHelper.pop(context, changed: _hasChanges),
        actions: [
          if (!context.select<UserProvider, bool>((p) => p.isSubAdmin))
            IconButton(
              icon: const Icon(Icons.edit_outlined, color: Colors.white),
              onPressed: () async {
                await NavigationHelper.push<bool>(
                  context,
                  destination: BusinessFormScreen(business: _currentBusiness),
                  onReturn: (result) async {
                    if (result == true && mounted) await _reloadBusiness();
                  },
                );
              },
            ),
        ],
        body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 이미지 슬라이드
                _buildImageSlider(context),

                Padding(
                  padding: ResponsiveHelper.listPadding(context),
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

                      // 6. 근태 반올림 규칙
                      _buildAttendanceRules(context, theme),

                      SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                      // 7. 오시는 길
                      _buildLocation(context, theme),

                      SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                      // 8. 기본 정보 (맨 아래)
                      _buildBasicInfo(context, theme),

                      SizedBox(height: ResponsiveHelper.spacing(context, 32)),
                    ],
                  ),
                ),
              ],
            ),
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
      return ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 250),
        child: Container(
          color: AppColors.grey200,
          child: Center(
            child: Icon(
              Icons.business,
              size: ResponsiveHelper.iconSize(context, 80),
              color: AppColors.grey400,
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        // 이미지 (탭 → 전체화면 미리보기)
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 250),
          child: SizedBox(
            child: PageView.builder(
              itemCount: images.length,
              onPageChanged: (index) {
                setState(() => _currentImageIndex = index);
              },
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: () => CommonWidgets.showImagePreview(
                    context,
                    images,
                    initialIndex: index,
                  ),
                  child: ImageHelper.buildCachedImage(
                    images[index],
                    fit: BoxFit.cover,
                    height: 250,
                  ),
                );
              },
            ),
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
                        : Colors.white.withValues(alpha: 0.4),
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
                  color: AppColors.amberDark,
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
                    color: AppColors.grey600,
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
              color: theme.primaryColor.withValues(alpha: 0.1),
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
          padding: ResponsiveHelper.listPadding(context),
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
              // 상호명 (사업자번호 바로 밑)
              if (_currentBusiness.companyName != null && _currentBusiness.companyName!.isNotEmpty) ...[
                Divider(height: ResponsiveHelper.spacing(context, 24)),
                _buildInfoRow(context, '상호명', _currentBusiness.companyName!),
              ],
              if (_currentBusiness.phone != null) ...[
                Divider(height: ResponsiveHelper.spacing(context, 24)),
                _buildInfoRow(
                  context,
                  '연락처',
                  FormatHelper.formatPhone(_currentBusiness.phone!),
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
          padding: ResponsiveHelper.listPadding(context),
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
                  _currentBusiness.mealsProvided!.join(', '),
                  true,
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
              return GestureDetector(
                onTap: () => CommonWidgets.showImagePreview(
                  context,
                  _currentBusiness.imageUrls!,
                  initialIndex: index,
                ),
                child: Container(
                  width: 120,
                  margin: EdgeInsets.only(
                    right: ResponsiveHelper.spacing(context, 12),
                  ),
                  child: ImageHelper.buildCachedImage(
                    _currentBusiness.imageUrls![index],
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(12),
                    memCacheWidth: 240,
                    fadeInDuration: const Duration(milliseconds: 150),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// ⏱️ 근태 반올림 규칙
  Widget _buildAttendanceRules(BuildContext context, ThemeData theme) {
    final rules = _currentBusiness.attendanceRules ?? AttendanceRules.defaults();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.sectionHeader(
          context: context,
          title: '근태 반올림 규칙',
          icon: Icons.tune_outlined,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Container(
          decoration: CommonWidgets.cardDecoration(),
          padding: ResponsiveHelper.listPadding(context),
          child: Column(
            children: [
              _buildRulesGroup(context, '출근 규칙', [
                ('조출 인정 범위', '${rules.earlyWindow}분'),
                ('조출 반올림 단위', '${rules.earlyArrivalUnit}분'),
                ('지각 유예 시간', '${rules.lateGrace}분'),
                ('지각 반올림 단위', '${rules.lateUnit}분'),
              ]),
              Divider(height: ResponsiveHelper.spacing(context, 24)),
              _buildRulesGroup(context, '퇴근 규칙', [
                ('정시 퇴근 인정 범위', '${rules.lateWindow}분'),
                ('연장 반올림 단위', '${rules.overtimeUnit}분'),
                ('조퇴 반올림 단위', '${rules.earlyLeaveUnit}분'),
              ]),
            ],
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Container(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12),
            vertical: ResponsiveHelper.spacing(context, 10),
          ),
          decoration: BoxDecoration(
            color: AppColors.infoBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.info.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: ResponsiveHelper.iconSize(context, 15), color: AppColors.infoDark),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: Text(
                  rules.summary,
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRulesGroup(BuildContext context, String title, List<(String, String)> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: ResponsiveHelper.smallStyle(context)
                .copyWith(fontWeight: FontWeight.bold, color: AppColors.grey600)),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        ...rows.map((row) => Padding(
              padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 4)),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Text(row.$1,
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey600)),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(row.$2,
                        textAlign: TextAlign.right,
                        style: ResponsiveHelper.smallStyle(context)
                            .copyWith(fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            )),
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
          padding: ResponsiveHelper.listPadding(context),
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

              // 교통편 사진 — 신규 필드
              if (_currentBusiness.transportImageUrls != null &&
                  _currentBusiness.transportImageUrls!.isNotEmpty) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                SizedBox(
                  height: 100,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _currentBusiness.transportImageUrls!.length,
                    itemBuilder: (ctx, i) => GestureDetector(
                      onTap: () => CommonWidgets.showImagePreview(
                        context,
                        _currentBusiness.transportImageUrls!,
                        initialIndex: i,
                      ),
                      child: Container(
                        width: 100,
                        height: 100,
                        margin: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
                        clipBehavior: Clip.hardEdge,
                        decoration: BoxDecoration(borderRadius: BorderRadius.circular(10)),
                        child: ImageHelper.buildCachedImage(
                          _currentBusiness.transportImageUrls![i],
                          width: 100,
                          height: 100,
                          fit: BoxFit.cover,
                          memCacheWidth: 200,
                          fadeInDuration: const Duration(milliseconds: 150),
                        ),
                      ),
                    ),
                  ),
                ),
              ],

              // 교통편 상세설명 — 신규 필드 우선, 레거시 폴백
              if (_currentBusiness.transportDescription != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.directions, size: ResponsiveHelper.iconSize(context, 20), color: AppColors.infoDark),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(_currentBusiness.transportDescription!, style: ResponsiveHelper.bodyStyle(context)),
                    ),
                  ],
                ),
              ] else ...[
                // 레거시 필드 폴백
                if (_currentBusiness.nearestStation != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Row(
                    children: [
                      Icon(Icons.subway, size: ResponsiveHelper.iconSize(context, 20), color: AppColors.infoDark),
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
                if (_currentBusiness.busInfo != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Row(
                    children: [
                      Icon(Icons.directions_bus, size: ResponsiveHelper.iconSize(context, 20), color: AppColors.successDark),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Expanded(
                        child: Text(_currentBusiness.busInfo!, style: ResponsiveHelper.bodyStyle(context)),
                      ),
                    ],
                  ),
                ],
              ],

              // 지도 미리보기
              if (_currentBusiness.latitude != null && _currentBusiness.longitude != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                RepaintBoundary(
                  child: GestureDetector(
                    onTap: () => _showFullMap(context),
                    child: KakaoMapWidget(
                      latitude: _currentBusiness.latitude!,
                      longitude: _currentBusiness.longitude!,
                      placeName: _currentBusiness.name,
                      height: ResponsiveHelper.spacing(context, 250),
                      showControls: false,
                    ),
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
      barrierDismissible: false,
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
          padding: ResponsiveHelper.listPadding(context),
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
          color: AppColors.warningDark,
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
              color: AppColors.grey600,
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
            color: isAvailable ? AppColors.successBg : AppColors.grey100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 20),
            color: isAvailable ? AppColors.successDark : AppColors.grey600,
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
                  color: AppColors.grey600,
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
          color: isAvailable ? AppColors.successDark : AppColors.grey400,
          size: ResponsiveHelper.iconSize(context, 20),
        ),
      ],
    );
  }

  /// 전화 걸기
  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) ToastHelper.showError('전화를 걸 수 없습니다');
    }
  }
}
