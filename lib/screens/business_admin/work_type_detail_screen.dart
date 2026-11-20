import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'dart:io';

// Providers
import '../../providers/user_provider.dart';

// Models
import '../../models/core/business_work_type_model.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/image_helper.dart';
import '../../utils/text_layout.dart';
import '../../../utils/format_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/first_line_icon.dart';
import '../../widgets/common/loading_widget.dart';
import '../../../widgets/work_type_icon.dart';

// Services
import '../../services/storage_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/notification_badge.dart';
import '../common/notification_screen.dart';

/// 📦 업무유형 상세 화면
class WorkTypeDetailScreen extends StatefulWidget {
  final BusinessWorkTypeModel workType;
  final bool initialEditMode;  // ⭐ 추가

  const WorkTypeDetailScreen({
    super.key,
    required this.workType,
    this.initialEditMode = false,  // ⭐ 기본값 false
  });

  @override
  State<WorkTypeDetailScreen> createState() => _WorkTypeDetailScreenState();
}

class _WorkTypeDetailScreenState extends State<WorkTypeDetailScreen> {
  late BusinessWorkTypeModel _currentWorkType;
  final StorageService _storageService = StorageService();
  
  bool _isLoading = false;
  bool _isEditing = false;
  bool _hasChanges = false;
  bool _isDirty = false; // 편집 중 미저장 변경사항 여부
  int _currentImageIndex = 0;

  // 수정용 컨트롤러
  final _oneLineIntroController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _requirementsController = TextEditingController();
  final _dutiesController = TextEditingController();
  final _precautionsController = TextEditingController();
  String? _selectedWorkEnvironment;

  // 이미지 관련
  File? _newThumbnail;
  final List<File> _newImages = [];
  final List<String> _imagesToDelete = [];

  @override
  void initState() {
    super.initState();
    _currentWorkType = widget.workType;
    _isEditing = widget.initialEditMode;  // ⭐ 추가
    _initControllers();
  }

  void _initControllers() {
    // 1. 먼저 리스너 제거 — text 설정 시 _markDirty 트리거 방지 (_cancelEditing에서도 호출됨)
    for (final c in [
      _oneLineIntroController, _descriptionController,
      _requirementsController, _dutiesController, _precautionsController,
    ]) {
      c.removeListener(_markDirty);
    }
    // 2. 텍스트 설정 (리스너 없으므로 _markDirty 미트리거)
    _oneLineIntroController.text = _currentWorkType.oneLineIntro ?? '';
    _descriptionController.text = _currentWorkType.description ?? '';
    _requirementsController.text = _currentWorkType.requirements ?? '';
    _dutiesController.text = _currentWorkType.duties ?? '';
    _precautionsController.text = _currentWorkType.precautions ?? '';
    _selectedWorkEnvironment = _currentWorkType.workEnvironment;
    // 3. 리스너 재등록
    for (final c in [
      _oneLineIntroController, _descriptionController,
      _requirementsController, _dutiesController, _precautionsController,
    ]) {
      c.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  @override
  void dispose() {
    // TMP-01: 저장/업로드되지 않고 남은 임시 압축 파일(compressed_xxx.jpg)
    // dispose 시점에 fire-and-forget으로 정리 — await 없이 catchError로 silently 처리.
    for (final file in [_newThumbnail, ..._newImages].whereType<File>()) {
      file.delete().ignore();
    }
    _oneLineIntroController.dispose();
    _descriptionController.dispose();
    _requirementsController.dispose();
    _dutiesController.dispose();
    _precautionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isDirty && !_hasChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isDirty) {
          _confirmDiscardChanges();
        } else if (_hasChanges) {
          NavigationHelper.popWithChange(context);
        }
      },
      child: AppPageScaffold(
        title: _isEditing ? '업무 수정' : '업무 상세',
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined),
            color: AppColors.textSecondary,
            onPressed: () => NavigationHelper.goHome(context),
            tooltip: '홈',
          ),
          NotificationBadge(
            child: IconButton(
              icon: const Icon(Icons.notifications_outlined),
              color: AppColors.textSecondary,
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const NotificationScreen()),
              ),
              tooltip: '알림',
            ),
          ),
          if (!_isEditing && context.select<UserProvider, bool>((p) => p.can((perm) => perm.canManageTo)))
            IconButton(
              icon: const Icon(Icons.edit),
              color: AppColors.textSecondary,
              onPressed: () => setState(() => _isEditing = true),
              tooltip: '수정',
            )
          else
            IconButton(
              icon: const Icon(Icons.close),
              color: AppColors.textSecondary,
              onPressed: _cancelEditing,
              tooltip: '취소',
            ),
        ],
        body: _isLoading
            ? const LoadingWidget()
            : SingleChildScrollView(
                padding: ResponsiveHelper.screenPadding(context),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // [DU1 구현97 S033 V1·V3·V8] 식별 블록(카드 없음) → 섹션마다 `제목(표면 밖) → 내용` 한 위계.
                    //   섹션 사이 24 · 제목-내용 12 · 카드 안 16(출발값). 순서는 그대로다.
                    _buildHeaderCard(context),
                    SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                    // 이미지 갤러리
                    _buildImageSection(context),
                    SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                    // 상세 설명
                    _buildDescriptionSection(context),
                    SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                    // 근무 환경
                    if (_currentWorkType.workEnvironment != null || _isEditing) ...[
                      _buildWorkEnvironmentSection(context),
                      SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                    ],

                    // 준비사항
                    if (_currentWorkType.precautions?.isNotEmpty == true || _isEditing) ...[
                      _buildPrecautionsSection(context),
                      SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                    ],

                    // 업무 상세
                    _buildDetailSection(context),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                    // 저장 버튼 (수정 모드일 때)
                    if (_isEditing) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                      _buildSaveButton(context),
                    ],

                    // AppPageScaffold는 body에 하단 SafeArea를 적용하지 않는다.
                    // 시각적 여백(32) + 기기 하단 인셋(홈 인디케이터/제스처 바)을 더해
                    // 마지막 컨텐츠가 시스템 내비게이션 영역에 가려지지 않도록 한다.
                    SizedBox(
                      height: ResponsiveHelper.spacing(context, 32) +
                          MediaQuery.paddingOf(context).bottom,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  /// [DU1 구현97 S033] 편집 입력의 공통 장식 — 표면(카드) 없이 화면 바탕 위에 놓이므로 흰 채움 + 기존 외곽선(테마)으로
  ///   입력 경계를 유지한다. 라벨·도움말·글자 수·포커스·오류 표현은 테마/TextField 기본 그대로다.
  InputDecoration _fieldDecoration({String? label, String? hint}) => InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      );

  /// 식별 블록 (아이콘 + 이름 + 한 줄 소개)
  ///
  /// [DU1 구현97 S033 V1·V6] 업무명이 식별 중심이다: 카드 없이 화면 제목급 글자(AppTextStyles.heroTitle 24),
  ///   업무 아이콘은 60 그라데이션+그림자 타일 → 44 단색 타일(사용자가 고른 업무 색·아이콘 값 그대로).
  ///   한 줄 소개는 브랜드 면·기울임 강조를 풀고 보통 부제(본문·보조색)로 둔다. 원문·편집 입력 규칙은 그대로다.
  Widget _buildHeaderCard(BuildContext context) {
    final iconBg = FormatHelper.parseColor(_currentWorkType.backgroundColor ?? '#2196F3');
    // 업무 아이콘(이모지)은 글자처럼 OS 글자 배율을 따라 커진다 — 타일도 같은 배율을 따라야 320·2.0 에서 글리프가
    //   타일 밖으로 넘치지 않는다(구현97 B 관측). 상한 88.
    final tile = MediaQuery.textScalerOf(context)
        .scale(ResponsiveHelper.spacing(context, 44))
        .clamp(ResponsiveHelper.spacing(context, 44), 88.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          // 아이콘 + 이름
          Row(
            children: [
              Container(
                width: tile,
                height: tile,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: WorkTypeIcon.build(
                    _currentWorkType,
                    size: ResponsiveHelper.spacing(context, 24),
                  ),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Text(
                  _currentWorkType.name,
                  style: AppTextStyles.heroTitle(),
                ),
              ),
            ],
          ),

          // 한 줄 소개
          if (_isEditing) ...[
            // 외곽선 입력의 떠 있는 라벨은 테두리 위로 글자 반 높이만큼 올라온다 — 간격도 글자 배율을 따라야
            //   320·2.0 에서 라벨이 아이콘 타일에 붙지 않는다(구현97 B 관측). 상한 32.
            SizedBox(
              height: MediaQuery.textScalerOf(context)
                  .scale(ResponsiveHelper.spacing(context, 16))
                  .clamp(ResponsiveHelper.spacing(context, 16), 32.0),
            ),
            TextField(
              controller: _oneLineIntroController,
              decoration: _fieldDecoration(
                label: '한 줄 소개',
                hint: '예: 상품을 찾아 바구니에 담는 업무입니다',
              ),
              // [DU1 구현94 S033] 한 줄 입력란이라 기존 값 '…업무입니다' 의 끝이 가로로 밀려 '…업무입니' 까지만 보였다(392·1.0, 내부 scroll 17.7).
              //   고정 2줄도 320·2.0 에선 4줄 값의 아래 2줄이 안쪽 scroll(48)에 숨었다 → 표시는 내용만큼 감싸 늘어난다.
              //   입력은 한 줄 그대로: keyboardType text(완료 키, 줄바꿈 키 없음) + singleLineFormatter
              //   (maxLines 1 일 때 Flutter 가 자동으로 넣던 줄바꿈 제거를 명시로 유지). 글자 수 제한·값·저장 무변경.
              keyboardType: TextInputType.text,
              inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
              minLines: 1,
              maxLines: null,
              maxLength: 50,
            ),
          ] else if (_currentWorkType.oneLineIntro?.isNotEmpty == true) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            // [DU320] 관리자 입력 문구 — 낱말 단위 표시(원문은 낭독용)
            Text(
              TextLayout.phrases(_currentWorkType.oneLineIntro!),
              semanticsLabel: _currentWorkType.oneLineIntro!,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                color: AppColors.textSecondary,
                height: 1.45,
              ),
            ),
          ],
      ],
    );
  }

  /// 이미지 섹션
  Widget _buildImageSection(BuildContext context) {
    final allImages = <dynamic>[];
    
    // 대표 이미지
    if (_newThumbnail != null) {
      allImages.add(_newThumbnail);
    } else if (_currentWorkType.thumbnailUrl != null) {
      allImages.add(_currentWorkType.thumbnailUrl);
    }
    
    // 추가 이미지 (대표 이미지와 중복 제외)
    if (_currentWorkType.images != null) {
      for (var url in _currentWorkType.images!) {
        if (!_imagesToDelete.contains(url) && url != _currentWorkType.thumbnailUrl) {
          allImages.add(url);
        }
      }
    }
    allImages.addAll(_newImages);

    // [DU1 구현97 S033 V3·V9] 제목은 표면 밖 공용 섹션 제목(편집이면 오른쪽에 기존 `추가` 행동).
    //   사진 없음은 높이 200 회색 상자 → 카드 안 한 줄 안내(아이콘 + 문구)로 낮춘다. 문구·keepWords·낭독 원문(구현94)·
    //   추가 행동(_pickImages)은 그대로이고, 사진 있음 분기의 표시·선택·삭제 의미와 순서도 그대로다.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.sectionHeader(
          context: context,
          title: '업무 사진',
          trailing: _isEditing
              ? TextButton.icon(
                  onPressed: _pickImages,
                  icon: Icon(Icons.add_photo_alternate, size: ResponsiveHelper.iconSize(context, 18)),
                  label: const Text('추가'),
                )
              : null,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        if (allImages.isEmpty)
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 14),
            ),
            decoration: CommonWidgets.cardDecoration(),
            child: Row(
              children: [
                Icon(
                  Icons.image_outlined,
                  size: ResponsiveHelper.iconSize(context, 22),
                  color: AppColors.textTertiary,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Text(
                    TextLayout.keepWords(_isEditing ? '사진을 추가해주세요' : '등록된 사진이 없습니다'),
                    semanticsLabel: _isEditing ? '사진을 추가해주세요' : '등록된 사진이 없습니다',
                    // [DU1 구현93 S033] 읽기용 보조색 textSecondary(grey500 2.457:1 교정) 유지.
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            decoration: CommonWidgets.cardDecoration(),
            padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 16)),
            child: Column(
              children: [
                // 메인 이미지
                Container(
                  height: ResponsiveHelper.spacing(context, 200),
                  margin: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 16),
                  ),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: _buildImageWidget(allImages[_currentImageIndex]),
                      ),
                      // 삭제 버튼 (수정 모드)
                      if (_isEditing)
                        Positioned(
                          top: 8,
                          right: 8,
                          child: IconButton(
                            onPressed: () => _deleteImage(_currentImageIndex, allImages),
                            icon: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: const BoxDecoration(
                                color: AppColors.error,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                // 썸네일 리스트
                if (allImages.length > 1)
                  Container(
                    height: ResponsiveHelper.spacing(context, 70),
                    // [DU1 구현97] 아래 여백 16 은 이제 카드 padding(세로 16)이 맡는다.
                    margin: EdgeInsets.only(
                      top: ResponsiveHelper.spacing(context, 12),
                    ),
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 16),
                      ),
                      itemCount: allImages.length,
                      itemBuilder: (context, index) {
                        final isSelected = index == _currentImageIndex;
                        return GestureDetector(
                          onTap: () => setState(() => _currentImageIndex = index),
                          child: Container(
                            width: ResponsiveHelper.spacing(context, 70),
                            margin: EdgeInsets.only(
                              right: ResponsiveHelper.spacing(context, 8),
                            ),
                            clipBehavior: Clip.hardEdge,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: isSelected
                                    ? Theme.of(context).primaryColor
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: _buildImageWidget(allImages[index], fit: BoxFit.cover),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildImageWidget(dynamic image, {BoxFit fit = BoxFit.cover}) {
    return ImageHelper.buildCachedImageWidget(
      image,
      fit: fit,
      width: double.infinity,
    );
  }

  /// 상세 설명 섹션
  ///
  /// [DU1 구현97 S033 V3·V4] 제목은 카드 밖, 읽기는 카드 한 겹에 본문만(안쪽 회색 상자 제거),
  ///   편집은 카드 없이 입력란(흰 채움+외곽선)만 — 카드 테두리와 입력 테두리가 겹치지 않는다.
  Widget _buildDescriptionSection(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommonWidgets.sectionHeader(
            context: context,
            title: '상세 설명',
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // 상세 설명
          if (_isEditing) ...[
            TextField(
              controller: _descriptionController,
              decoration: _fieldDecoration(
                hint: '업무에 대한 상세 설명을 입력하세요',
              ),
              // [DU1 구현94 S033] 고정 4줄이라 320·2.0 에서 기존 상세 설명의 대부분이 입력란 안쪽 scroll(288)에 숨었다 —
              //   최소 4줄, 내용만큼 늘어나 본문 페이지 스크롤로 전부 읽힌다. 글자 수 제한(500)·값·저장 무변경.
              minLines: 4,
              maxLines: null,
              maxLength: 500,
            ),
          ] else
            Container(
              width: double.infinity,
              padding: ResponsiveHelper.cardPadding(context),
              decoration: CommonWidgets.cardDecoration(),
              child: _currentWorkType.description?.isNotEmpty == true
                  // [DU320] 392·1.0 에서도 '바구니 / 에' 로 끊겼다 — 낱말 단위(줄바꿈 문자 유지, 원문은 낭독용)
                  ? Text(
                      TextLayout.phrases(_currentWorkType.description!),
                      semanticsLabel: _currentWorkType.description!,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: AppColors.grey700,
                        height: 1.5,
                      ),
                    )
                  // 빈 설명 안내: grey500 기울임(흰 바탕 2.x:1) → 같은 화면 다른 빈 안내와 같은 보조색, 기울임 없음
                  : Text(
                      '등록된 상세 설명이 없습니다',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
            ),
        ],
    );
  }
  /// 근무 환경 섹션 (사업장 상세 스타일)
  Widget _buildWorkEnvironmentSection(BuildContext context) {
    final theme = Theme.of(context);
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.sectionHeader(
          context: context,
          title: '근무 환경',
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        // [DU1 구현97 S033 V4] 편집(선택 칩)은 카드 없이 바탕 위에, 읽기는 카드 한 겹.
        //   편집 안내 글자는 카드 흰 면이 빠져 화면 바탕(#F6F7FA) 위에 놓이므로 grey600(4.6 근처) → textSecondary.
        Container(
          width: double.infinity,  // ← 너비 맞춤 추가
          decoration: _isEditing ? null : CommonWidgets.cardDecoration(),
          padding: _isEditing ? EdgeInsets.zero : ResponsiveHelper.cardPadding(context),
          child: _isEditing
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '근무 환경을 선택하세요',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    Wrap(
                      spacing: ResponsiveHelper.spacing(context, 8),
                      runSpacing: ResponsiveHelper.spacing(context, 8),  // ← 줄바꿈 간격 추가
                      children: ['실내(상온)', '실내(냉장)', '실내(냉동)', '실외', '혼합'].map((env) {
                        final isSelected = _selectedWorkEnvironment == env;
                        return ChoiceChip(
                          label: Text(env),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedWorkEnvironment = selected ? env : null;
                              _isDirty = true;
                            });
                          },
                          selectedColor: theme.primaryColor,
                          checkmarkColor: Colors.white,
                          labelStyle: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: isSelected ? Colors.white : AppColors.grey700,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          side: BorderSide(
                            color: isSelected ? theme.primaryColor : AppColors.grey300,
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                )
              : _buildEnvironmentItem(
                  context,
                  _getWorkEnvironmentIcon(_currentWorkType.workEnvironment!),
                  '근무 장소',
                  _currentWorkType.workEnvironment!,
                ),
        ),
      ],
    );
  }

  /// 환경 항목 — 아이콘 + 라벨 + 값 한 행
  ///
  /// [DU1 구현97 S033 V6·V7] 무조건 붙던 녹색 성공 체크(검증 완료처럼 읽힘)를 뺀다. 행 아이콘은 색 타일 없이
  ///   선 아이콘 하나(근무 환경별 의미 아이콘은 그대로). 라벨은 grey600 → textSecondary.
  Widget _buildEnvironmentItem(
    BuildContext context,
    IconData icon,
    String label,
    String value,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: ResponsiveHelper.iconSize(context, 22),
          color: AppColors.textSecondary,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: ResponsiveHelper.smallStyle(context).copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 2)),
              Text(
                value,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 근무환경별 아이콘 반환
  IconData _getWorkEnvironmentIcon(String env) {
    switch (env) {
      case '실내(상온)':
        return Icons.warehouse_outlined;
      case '실내(냉장)':
        return Icons.ac_unit_outlined;
      case '실내(냉동)':
        return Icons.severe_cold;
      case '실외':
        return Icons.wb_sunny_outlined;
      case '혼합':
        return Icons.sync_alt;
      default:
        return Icons.location_on_outlined;
    }
  }

  /// 업무 상세 섹션
  ///
  /// [DU1 구현97 S033 V3·V4·V7] 제목(카드 밖) → 읽기: 카드 한 겹 안에 `자격 요건`·`주요 업무` 하위 라벨+본문,
  ///   두 묶음 사이 구분선(안쪽 회색 상자·라벨 브랜드 아이콘 제거). 편집: 카드 없이 라벨+입력란.
  ///   세 그룹을 한 카드로 합치는 것(V5)은 BACKLOG 라 하지 않는다.
  Widget _buildDetailSection(BuildContext context) {
    final req = _currentWorkType.requirements;
    final duties = _currentWorkType.duties;
    final hasReq = req?.isNotEmpty == true;
    final hasDuties = duties?.isNotEmpty == true;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommonWidgets.sectionHeader(
            context: context,
            title: '업무 상세',
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          if (_isEditing) ...[
            // 자격 요건
            _buildDetailField(
              context,
              label: '자격 요건',
              controller: _requirementsController,
              hint: '예: 성인 남녀 누구나, 무거운 물건(10kg 이상) 들 수 있는 분',
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            // 주요 업무
            _buildDetailField(
              context,
              label: '주요 업무',
              controller: _dutiesController,
              hint: '예: 상품 피킹, 바코드 스캔, 포장 작업',
            ),
          ] else
            Container(
              width: double.infinity,
              padding: ResponsiveHelper.cardPadding(context),
              decoration: CommonWidgets.cardDecoration(),
              child: (hasReq || hasDuties)
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasReq) _buildDetailReadItem(context, '자격 요건', req!),
                        if (hasReq && hasDuties)
                          Divider(height: ResponsiveHelper.spacing(context, 32)),
                        if (hasDuties) _buildDetailReadItem(context, '주요 업무', duties!),
                      ],
                    )
                  : Text(
                      '등록된 업무 상세가 없습니다',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
            ),
        ],
    );
  }

  /// 읽기 — 하위 라벨(섹션 제목과 구별되는 작은 굵은 보조색) + 본문
  Widget _buildDetailReadItem(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: ResponsiveHelper.smallStyle(context).copyWith(
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary,
          ),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
        // [DU320] 자격 요건 · 주요 업무 값 — 낱말 단위(원문은 낭독용)
        Text(
          TextLayout.phrases(value),
          semanticsLabel: value,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            color: AppColors.grey700,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  /// 편집 — 하위 라벨 + 입력란
  Widget _buildDetailField(
    BuildContext context, {
    required String label,
    required TextEditingController controller,
    required String hint,
  }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          TextField(
            controller: controller,
            decoration: _fieldDecoration(hint: hint),
            // [DU1 구현94 S033] 같은 화면의 다른 입력란과 같은 규칙: 최소 3줄, 내용만큼 늘어난다.
            //   이 fixture 값은 3줄 안이라 반례는 없었지만(N·B 안쪽 scroll 0) 한도 500자에 고정 3줄이면 긴 기존 값이 안쪽에 숨는다(같은 기제·INFERRED).
            minLines: 3,
            maxLines: null,
            maxLength: 500,
          ),
        ],
      );
  }

  /// 주의사항 섹션
  ///
  /// [DU1 구현97 S033 V4·V6·V7] 읽기: 넓은 황갈색 infoCard 면(구현93 yellowWarnText) → 흰 카드 한 겹 +
  ///   주의 의미 아이콘(warningDark #946200, 흰 바탕 비문자 대비 기준 충족) + 본문(주 글자색). 경고 의미·원문은 그대로이고
  ///   색 면의 무게만 낮춘다(경고색 일괄 제거 아님). 공용 infoCard 기본값은 바꾸지 않는다.
  ///   편집: 카드 없이 입력란만(흰 채움+외곽선) — 카드·입력 이중 테두리 제거.
  Widget _buildPrecautionsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonWidgets.sectionHeader(
          context: context,
          title: '준비사항',
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

        if (_isEditing)
          TextField(
            controller: _precautionsController,
            decoration: _fieldDecoration(
              hint: '예: 냉장 3~5도(따뜻한 복장 권장)\n냉동 -18도(냉동복 제공)',
            ),
            // [DU1 구현94 S033] 고정 3줄이라 기존 준비사항(5줄)의 아래 2줄이 입력란 안쪽 스크롤(48)에 숨었다 — 최소 3줄, 내용만큼 늘어난다.
            //   본문 페이지 스크롤로 전부 읽힌다. 글자 수 제한(300)·값·저장 무변경.
            minLines: 3,
            maxLines: null,
            maxLength: 300,
          )
        else
          Container(
            width: double.infinity,
            padding: ResponsiveHelper.cardPadding(context),
            decoration: CommonWidgets.cardDecoration(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // [DU453] 위 여백 1 · 고정 크기라 큰 글자에서 아이콘이 첫 줄 가운데보다 위에 떴다(B ≈ 13 · DU452 사업장 상세와 같은 형식).
                //   공용 FirstLineIcon 으로 본문(같은 스타일 · 줄 높이 1.5) 첫 줄 가운데에 둔다 — 크기는 그대로(DU361).
                FirstLineIcon(
                  Icons.warning_amber_rounded,
                  size: ResponsiveHelper.iconSize(context, 20),
                  color: AppColors.warningDark,
                  textStyle: ResponsiveHelper.bodyStyle(context).copyWith(height: 1.5),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                Expanded(
                  // [DU320] '있 / 으며' · '금지됩 / 니다' 로 끊겼다 — 낱말 단위(줄바꿈 문자 유지, 원문은 낭독용)
                  child: Text(
                    TextLayout.phrases(_currentWorkType.precautions!),
                    semanticsLabel: _currentWorkType.precautions!,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: AppColors.textPrimary,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 저장 버튼
  Widget _buildSaveButton(BuildContext context) {
    return CommonWidgets.primaryButton(
      context: context,
      text: '저장',
      onPressed: _isLoading ? null : _saveChanges,
      isLoading: _isLoading,
      icon: Icons.save,
    );
  }

  // ==================== 기능 메서드 ====================

  /// 이미지 선택
  Future<void> _pickImages() async {
    try {
      final image = await ImageHelper.pickAndCompressImage(
        context,
        type: ImageType.general,
        useBottomSheet: true,
      );
      if (image != null) {
        if (!mounted) return; // [MOUNTED-01 수정] 이미지 피커 복귀 시 위젯 dispose 경합 방지
        setState(() { _newImages.add(image); _isDirty = true; });
      }
    } catch (e) {
      debugPrint('❌ 이미지 선택 오류: $e');
      if (mounted) ToastHelper.showError('이미지를 불러오는 데 실패했습니다.');
    }
  }

  /// 이미지 삭제
  void _deleteImage(int index, List<dynamic> allImages) {
    final image = allImages[index];

    setState(() {
      _isDirty = true;
      if (image is File) {
        // TMP-01: 선택 취소된 임시 압축 파일 즉시 정리 (fire-and-forget)
        image.delete().ignore();
        if (_newThumbnail == image) {
          _newThumbnail = null;
        } else {
          _newImages.remove(image);
        }
      } else if (image is String) {
        _imagesToDelete.add(image);
        // 대표 이미지도 삭제 목록에 포함되었는지 체크
        if (image == _currentWorkType.thumbnailUrl) {
          // 대표 이미지 삭제 시 처리됨
        }
      }
      
      // 현재 인덱스 조정
      if (_currentImageIndex >= allImages.length - 1 && _currentImageIndex > 0) {
        _currentImageIndex--;
      }
    });
  }

  Future<void> _confirmDiscardChanges() async {
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('변경사항 취소'),
        content: const Text('저장하지 않은 변경사항이 있습니다.\n나가시겠습니까?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('계속 수정')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('나가기')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _isDirty = false);
    if (_hasChanges) {
      NavigationHelper.popWithChange(context);
    } else {
      Navigator.pop(context);
    }
  }

  /// 수정 취소
  void _cancelEditing() {
    // TMP-01: 수정 취소 시 미업로드 임시 압축 파일 정리 (fire-and-forget)
    for (final file in [_newThumbnail, ..._newImages].whereType<File>()) {
      file.delete().ignore();
    }
    setState(() {
      _isEditing = false;
      _isDirty = false;
      _initControllers();
      _newThumbnail = null;
      _newImages.clear();
      _imagesToDelete.clear();
    });
  }

  /// 변경사항 저장
  ///
  /// CLAUDE.md 삭제 순서 규칙: Storage 삭제 전 Firestore를 먼저 업데이트한다.
  /// Firestore 업데이트 실패 시 Storage는 건드리지 않아 broken URL 잔류를 방지한다.
  Future<void> _saveChanges() async {
    if (_isLoading) return; // 이중 탭 방어
    setState(() => _isLoading = true);

    final List<String> newlyUploadedUrls = [];
    try {
      // 1. 새 이미지 업로드 (Firestore 업데이트 전) — 실패 시 catch에서 newlyUploadedUrls 롤백
      String? thumbnailUrl = _currentWorkType.thumbnailUrl;
      if (_imagesToDelete.contains(thumbnailUrl)) {
        thumbnailUrl = null;
      }

      if (_newThumbnail != null) {
        thumbnailUrl = await _uploadImage(_newThumbnail!, 'thumbnail');
        if (thumbnailUrl == null) {
          if (mounted) ToastHelper.showError('썸네일 업로드에 실패했습니다. 다시 시도해주세요.');
          return; // null URL로 Firestore 저장 방지, finally에서 _isLoading 초기화
        }
        newlyUploadedUrls.add(thumbnailUrl);
      }

      List<String> imageUrls = [];
      if (_currentWorkType.images != null) {
        imageUrls = _currentWorkType.images!
            .where((url) => !_imagesToDelete.contains(url))
            .toList();
      }

      // 이미지 업로드 병렬 실행
      final uploadResults = await Future.wait(
        _newImages.map((image) => _uploadImage(image, 'image')),
      );
      if (!mounted) return;
      for (final url in uploadResults) {
        if (url != null) {
          imageUrls.add(url);
          newlyUploadedUrls.add(url);
        }
      }

      // 첫 번째 이미지를 대표이미지로 (images 배열에서는 제외)
      if (thumbnailUrl == null && imageUrls.isNotEmpty) {
        thumbnailUrl = imageUrls.removeAt(0);  // 첫 번째 이미지를 꺼내서 대표로
      }

      // 2. Firestore 업데이트 (삭제 이전에 반드시 선행)
      // 이유: Firestore 실패 시 Storage는 건드리지 않아야 broken URL이 남지 않음
      final updateData = {
        'oneLineIntro': _oneLineIntroController.text.trim().isEmpty
            ? null
            : _oneLineIntroController.text.trim(),
        'description': _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        'workEnvironment': _selectedWorkEnvironment,
        'requirements': _requirementsController.text.trim().isEmpty
            ? null
            : _requirementsController.text.trim(),
        'duties': _dutiesController.text.trim().isEmpty
            ? null
            : _dutiesController.text.trim(),
        'precautions': _precautionsController.text.trim().isEmpty
            ? null
            : _precautionsController.text.trim(),
        'thumbnailUrl': thumbnailUrl,
        'images': imageUrls.isEmpty ? null : imageUrls,
      };

      await FirebaseFirestore.instance
          .collection('businesses')
          .doc(_currentWorkType.businessId)
          .collection('workTypes')
          .doc(_currentWorkType.id)
          .update(updateData);

      // 3. Firestore 성공 후에만 Storage에서 구 이미지 삭제
      // 이유: Firestore 실패 시 Storage 삭제를 했다면 broken URL이 Firestore에 남음
      // [WORKTYPE-IDENTITY] 지울 것은 "저장 전에 참조했지만 저장 후에는 참조하지 않는" 사진이다.
      //   예전에는 사용자가 지운 사진만 정리해서, 대표 사진을 새로 바꾸면 옛 대표 사진이 참조 없이
      //   남았다. 지금 참조 중인 사진은 절대 넣지 않는다(서버도 참조 중인 사진 삭제를 거절한다).
      final stillReferenced = <String>{
        if (thumbnailUrl != null) thumbnailUrl,
        ...imageUrls,
      };
      final unused = <String>{
        if (_currentWorkType.thumbnailUrl != null) _currentWorkType.thumbnailUrl!,
        ...?_currentWorkType.images,
      }.difference(stillReferenced);
      await Future.wait(unused.map((url) async {
        try {
          await _storageService.deleteImageByUrl(url);
        } catch (e) {
          debugPrint('⚠️ Storage 구 이미지 삭제 실패 (orphan): $e');
        }
      }));

      // 4. 로컬 상태 업데이트
      if (!mounted) return;
      setState(() {
        _currentWorkType = _currentWorkType.copyWith(
          oneLineIntro: updateData['oneLineIntro'] as String?,
          description: updateData['description'] as String?,
          workEnvironment: updateData['workEnvironment'] as String?,
          requirements: updateData['requirements'] as String?,
          duties: updateData['duties'] as String?,
          precautions: updateData['precautions'] as String?,
          thumbnailUrl: thumbnailUrl,
          images: imageUrls.isEmpty ? null : imageUrls,
        );
        _isEditing = false;
        _isDirty = false;
        _hasChanges = true;
        _newThumbnail = null;
        _newImages.clear();
        _imagesToDelete.clear();
      });

      if (mounted) ToastHelper.showSuccess('업무가 수정되었습니다');
    } catch (e) {
      // Firestore 실패 시 이미 업로드된 신규 파일 롤백
      await Future.wait(newlyUploadedUrls.map((url) async {
        try { await _storageService.deleteImageByUrl(url); } catch (_) {}
      }));
      debugPrint('❌ 저장 실패: $e');
      if (mounted) ToastHelper.showError('저장에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 이미지 업로드 — CF 경유 (storage.rules: businesses/ if false)
  Future<String?> _uploadImage(File imageFile, String type) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final url = await _storageService.uploadBusinessImage(
        bytes,
        _currentWorkType.businessId,
      );
      // TMP-01: pickAndCompressImage()가 생성한 임시 압축 파일은 업로드 후 즉시 삭제
      try {
        if (await imageFile.exists()) await imageFile.delete();
      } catch (_) {
        debugPrint('⚠️ 임시 이미지 파일 삭제 실패 (무시 가능)');
      }
      return url;
    } catch (e) {
      debugPrint('❌ 이미지 업로드 실패: $e');
      return null;
    }
  }
}
