import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';

// Models
import '../../models/core/business_model.dart';
import '../../models/core/to_model.dart';
import '../../models/core/work_detail_model.dart';
import '../../models/core/business_work_type_model.dart';

// Services
import '../../services/firestore_service.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/toast_helper.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/work_type_icon.dart';
import '../../widgets/maps/kakao_map_widget.dart';
import '../../widgets/maps/full_map_dialog.dart';

/// 📋 TO 공고 상세보기 화면
/// - 지원자 모드: 공고 확인 + 지원하기
/// - 관리자 미리보기 모드: 공고 확인만
enum TODetailMode {
  applicant,    // 지원자 모드 (지원하기 버튼 표시)
  adminPreview, // 관리자 미리보기 (닫기 버튼만)
}

class JobPostingScreen extends StatefulWidget {
  final String? toId;           // Firestore에서 로드할 경우
  final TOModel? to;            // 직접 전달할 경우
  final List<WorkDetailModel>? workDetails;  // 직접 전달할 경우
  final BusinessModel? business;  // 직접 전달할 경우
  final TODetailMode mode;

  const JobPostingScreen({
    super.key,
    this.toId,
    this.to,
    this.workDetails,
    this.business,
    this.mode = TODetailMode.applicant,
  }) : assert(toId != null || to != null, 'toId 또는 to 중 하나는 필수입니다');

  @override
  State<JobPostingScreen> createState() => _JobPostingScreenState();
}

class _JobPostingScreenState extends State<JobPostingScreen> {
  final FirestoreService _firestoreService = FirestoreService();

  bool _isLoading = true;
  TOModel? _to;
  BusinessModel? _business;
  List<WorkDetailModel> _workDetails = [];
  Map<String, BusinessWorkTypeModel> _workTypeMap = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // 직접 전달받은 경우
      if (widget.to != null) {
        _to = widget.to;
        _workDetails = widget.workDetails ?? [];
        _business = widget.business;
      } else {
        // Firestore에서 로드
        _to = await _firestoreService.getTO(widget.toId!);
        if (_to != null) {
          _workDetails = await _firestoreService.getWorkDetails(_to!.id);
        }
      }

      // 사업장 정보 로드
      if (_business == null && _to != null) {
        _business = await _firestoreService.getBusinessById(_to!.businessId);
      }

      // 업무유형 상세 정보 로드 (이미지, 설명 등)
      if (_business != null) {
        await _loadWorkTypes();
      }

      setState(() => _isLoading = false);
    } catch (e) {
      print('❌ 데이터 로드 실패: $e');
      ToastHelper.showError('데이터를 불러오는데 실패했습니다');
      setState(() => _isLoading = false);
    }
  }

  /// 업무유형 상세 정보 로드
  Future<void> _loadWorkTypes() async {
    try {
      final workTypes = await _firestoreService.getBusinessWorkTypes(_business!.id);
      _workTypeMap = {for (var wt in workTypes) wt.name: wt};
    } catch (e) {
      print('⚠️ 업무유형 로드 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const LoadingWidget(message: '공고 정보를 불러오는 중...')
          : _to == null
              ? _buildErrorState(context)
              : CustomScrollView(
                  slivers: [
                    // 사업장 이미지 & 앱바
                    _buildSliverAppBar(context, theme),

                    // 컨텐츠
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          // 사업장 정보 카드
                          _buildBusinessInfoCard(context, theme),

                          // TO 정보 카드
                          _buildTOInfoCard(context, theme),

                          // 준비사항 (업무 상세 위에 강조 표시)
                          if (_business?.precautions != null && _business!.precautions!.isNotEmpty)
                            Container(
                              margin: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
                              child: CommonWidgets.infoCard(
                                context: context,
                                message: _business!.precautions!,
                                icon: Icons.warning_amber_outlined,
                                color: Colors.orange[700],
                              ),
                            ),

                          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                          // 업무 상세 섹션
                          _buildWorkDetailsSection(context, theme),

                          // 시설 및 환경
                          if (_business != null)
                            _buildFacilitiesSection(context, theme),

                          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                          // 상세 설명
                          if (_to?.description != null && _to!.description!.isNotEmpty)
                            _buildDescriptionSection(context, theme),

                          // 찾아오시는 길 (지도 포함)
                          if (_business != null)
                            _buildTransportSection(context, theme),

                          // 하단 여백
                          SizedBox(height: ResponsiveHelper.spacing(context, 100)),
                        ],
                      ),
                    ),
                  ],
                ),
      // 하단 버튼
      bottomNavigationBar: _isLoading || _to == null
          ? null
          : _buildBottomBar(context, theme),
    );
  }

  /// 에러 상태
  Widget _buildErrorState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            size: ResponsiveHelper.iconSize(context, 64),
            color: Colors.grey[400],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            '공고를 찾을 수 없습니다',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              color: Colors.grey[600],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 24)),
          CommonWidgets.outlineButton(
            context: context,
            text: '돌아가기',
            onPressed: () => Navigator.pop(context),
            icon: Icons.arrow_back,
          ),
        ],
      ),
    );
  }

  /// 슬리버 앱바 (사업장 이미지)
  Widget _buildSliverAppBar(BuildContext context, ThemeData theme) {
    final hasImage = _business?.mainImageUrl != null;

    return SliverAppBar(
      expandedHeight: hasImage ? 200 : 120,
      pinned: true,
      backgroundColor: theme.primaryColor,
      foregroundColor: Colors.white,
      flexibleSpace: FlexibleSpaceBar(
        background: hasImage
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    _business!.mainImageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: theme.primaryColor.withOpacity(0.8),
                      child: Icon(
                        Icons.business,
                        size: ResponsiveHelper.iconSize(context, 64),
                        color: Colors.white.withOpacity(0.5),
                      ),
                    ),
                  ),
                  // 그라데이션 오버레이
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withOpacity(0.3),
                          Colors.transparent,
                          Colors.black.withOpacity(0.5),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      theme.primaryColor,
                      theme.primaryColor.withOpacity(0.8),
                    ],
                  ),
                ),
              ),
      ),
      leading: IconButton(
        icon: Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.3),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.arrow_back,
            size: ResponsiveHelper.iconSize(context, 20),
          ),
        ),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        if (widget.mode == TODetailMode.adminPreview)
          Container(
            margin: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 6),
            ),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.visibility,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: Colors.white,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '미리보기',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 사업장 정보 카드
  Widget _buildBusinessInfoCard(BuildContext context, ThemeData theme) {
    return Container(
      margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 사업장명
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                decoration: BoxDecoration(
                  color: theme.primaryColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.business,
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              // 사업장명 + 한줄소개
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _business!.name,
                      style: ResponsiveHelper.titleStyle(context).copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (_business!.oneLineIntro != null) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                      Text(
                        _business!.oneLineIntro!,
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          // 사업장 소개
          if (_business!.detailedDescription != null && _business!.detailedDescription!.isNotEmpty) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Divider(height: 1, color: Colors.grey[200]),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: Colors.grey[500],
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    _business!.detailedDescription!,
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      color: Colors.grey[700],
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ],
           ],
          ),
        );
  }

  // TO 정보 카드
  Widget _buildTOInfoCard(BuildContext context, ThemeData theme) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TO 제목
          Text(
            _to!.title,
              style: ResponsiveHelper.titleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),

            SizedBox(height: ResponsiveHelper.spacing(context, 16)),

            // 날짜 정보
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.primaryColor.withOpacity(0.1)),
              ),
              child: Column(
                children: [
                  // 근무일 (장기: 기간 범위 / 단기: 단일 날짜)
                  _buildTOInfoRow(
                    context,
                    Icons.calendar_today,
                    _to!.isLongTerm ? '근무기간' : '근무일',
                    _to!.isLongTerm 
                        ? (_to!.groupDateRangeDisplay ?? _to!.formattedDate)  // 장기: "11/1 ~ 11/30" (없으면 단일 날짜)
                        : _to!.formattedDate,                                  // 단기: "11/27 (목)"
                    theme.primaryColor,
                  ),

                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                  // 근무 유형
                  _buildTOInfoRow(
                    context,
                    _to!.isLongTerm ? Icons.work_history : Icons.work_outline,
                    '근무 유형',
                    _to!.jobTypeLabel,
                    _to!.isLongTerm ? Colors.purple : Colors.blue,
                  ),

                  // 장기 근무 요일
                  if (_to!.isLongTerm && _to!.workDays != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    _buildTOInfoRow(
                      context,
                      Icons.date_range,
                      '근무 요일',
                      _to!.workDaysLabel,
                      Colors.purple,
                    ),
                  ],

                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                  // 마감 규칙
                  _buildTOInfoRow(
                    context,
                    Icons.timer_outlined,
                    '지원 마감',
                    _to!.deadlineType == 'HOURS_BEFORE'
                        ? '업무시작 ${_to!.hoursBeforeStart ?? 2}시간 전'
                        : _to!.formattedDeadline,
                    _to!.isDeadlineSoon ? Colors.red : Colors.grey[600]!,
                  ),
                ],
              ),
            ),

            SizedBox(height: ResponsiveHelper.spacing(context, 16)),

            // 모집 현황
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    context,
                    Icons.people_outline,
                    '모집 인원',
                    '${_to!.totalRequired}명',
                    Colors.blue,
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: _buildStatCard(
                    context,
                    Icons.check_circle_outline,
                    '확정 인원',
                    '${_to!.totalConfirmed}명',
                    Colors.green,
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: _buildStatCard(
                    context,
                    Icons.hourglass_empty,
                    '남은 자리',
                    '${_to!.availableSlots}명',
                    _to!.availableSlots > 0 ? Colors.orange : Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
    );
  }

  /// 업무 상세 섹션
  Widget _buildWorkDetailsSection(BuildContext context, ThemeData theme) {
    return Container(
      margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommonWidgets.sectionHeader(
            context: context,
            title: '업무 상세',
            icon: Icons.work_outline,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          // 업무 카드 목록
          ..._workDetails.map((work) => _buildWorkDetailCard(context, theme, work)),
        ],
      ),
    );
  }

  /// 업무 상세 카드
  Widget _buildWorkDetailCard(BuildContext context, ThemeData theme, WorkDetailModel work) {
    final workType = _workTypeMap[work.workType];
    final hasDetailInfo = workType != null &&
        (workType.description != null ||
            workType.thumbnailUrl != null ||
            workType.images?.isNotEmpty == true);

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      decoration: CommonWidgets.cardDecoration(),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: hasDetailInfo ? () => _showWorkTypeDetail(context, work, workType!) : null,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더 (아이콘 + 업무명 + 인원)
                Row(
                  children: [
                    // 아이콘 배경 컨테이너
                    Container(
                      width: ResponsiveHelper.iconSize(context, 44),
                      height: ResponsiveHelper.iconSize(context, 44),
                      decoration: BoxDecoration(
                        color: FormatHelper.parseColor(work.workTypeBackgroundColor ?? work.workTypeColor),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: WorkTypeIcon.buildFromString(
                          work.workTypeIcon,
                          color: FormatHelper.parseColor(work.workTypeColor),
                          size: ResponsiveHelper.iconSize(context, 24),
                        ),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                work.workType,
                                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (hasDetailInfo) ...[
                                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                Icon(
                                  Icons.info_outline,
                                  size: ResponsiveHelper.iconSize(context, 16),
                                  color: theme.primaryColor,
                                ),
                              ],
                            ],
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                          Text(
                            work.timeRange,
                            style: ResponsiveHelper.smallStyle(context).copyWith(
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 인원 배지
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 12),
                        vertical: ResponsiveHelper.spacing(context, 6),
                      ),
                      decoration: BoxDecoration(
                        color: work.isFull
                            ? Colors.red.withOpacity(0.1)
                            : theme.primaryColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        work.countInfo,
                        style: ResponsiveHelper.smallStyle(context).copyWith(
                          color: work.isFull ? Colors.red : theme.primaryColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                Divider(height: 1, color: Colors.grey[200]),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),

                // 급여 정보
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.payments_outlined,
                          size: ResponsiveHelper.iconSize(context, 18),
                          color: Colors.green[600],
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Text(
                          '${work.wageTypeLabel} ${work.formattedWage}',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            fontWeight: FontWeight.bold,
                            color: Colors.green[700],
                          ),
                        ),
                      ],
                    ),
                    if (hasDetailInfo)
                      Text(
                        '상세보기 →',
                        style: ResponsiveHelper.smallStyle(context).copyWith(
                          color: theme.primaryColor,
                        ),
                      ),
                  ],
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                // 실제 마감시간
                Row(
                  children: [
                    Icon(
                      Icons.schedule,
                      size: ResponsiveHelper.iconSize(context, 16),
                      color: work.isClosed ? Colors.red[400] : Colors.orange[600],
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Text(
                      '마감: ${work.applicationDeadline != null ? FormatHelper.formatDateTime(work.applicationDeadline!) : '미정'}',
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: work.isClosed ? Colors.red[400] : Colors.orange[700],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 업무유형 상세 BottomSheet
  void _showWorkTypeDetail(
    BuildContext context,
    WorkDetailModel work,
    BusinessWorkTypeModel workType,
  ) {
    final theme = Theme.of(context);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(ResponsiveHelper.spacing(context, 24)),
            ),
          ),
          child: Column(
            children: [
              // 드래그 핸들
              Container(
                margin: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 12),
                ),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 컨텐츠
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: ResponsiveHelper.cardPadding(context),
                  children: [
                    // 헤더
                    Row(
                      children: [
                        // 아이콘 배경 컨테이너
                        Container(
                          width: ResponsiveHelper.iconSize(context, 56),
                          height: ResponsiveHelper.iconSize(context, 56),
                          decoration: BoxDecoration(
                            color: FormatHelper.parseColor(workType.backgroundColor ?? workType.color),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: WorkTypeIcon.buildFromString(
                              workType.icon,
                              color: FormatHelper.parseColor(workType.color ?? '#FFFFFF'),
                              size: ResponsiveHelper.iconSize(context, 28),
                            ),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                workType.name,
                                style: ResponsiveHelper.titleStyle(context).copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (workType.oneLineIntro != null) ...[
                                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                                Text(
                                  workType.oneLineIntro!,
                                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: ResponsiveHelper.spacing(context, 24)),

                    // 이미지 갤러리
                    if (workType.thumbnailUrl != null ||
                        (workType.images?.isNotEmpty == true))
                      _buildWorkTypeImages(context, workType),

                    // 상세 설명
                    if (workType.description != null) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                      _buildDetailItem(
                        context,
                        Icons.description_outlined,
                        '업무 설명',
                        workType.description!,
                      ),
                    ],

                    // 근무 환경
                    if (workType.workEnvironment != null) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      _buildDetailItem(
                        context,
                        Icons.thermostat_outlined,
                        '근무 환경',
                        workType.workEnvironment!,
                      ),
                    ],

                    // 자격 요건
                    if (workType.requirements != null) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      _buildDetailItem(
                        context,
                        Icons.checklist_outlined,
                        '자격 요건',
                        workType.requirements!,
                      ),
                    ],

                    // 주요 업무
                    if (workType.duties != null) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      _buildDetailItem(
                        context,
                        Icons.task_alt_outlined,
                        '주요 업무',
                        workType.duties!,
                      ),
                    ],

                    // 준비사항
                    if (workType.precautions != null) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      CommonWidgets.infoCard(
                        context: context,
                        message: workType.precautions!,
                        icon: Icons.warning_amber_outlined,
                        color: Colors.orange[700],
                      ),
                    ],

                    SizedBox(height: ResponsiveHelper.spacing(context, 32)),

                    // 닫기 버튼
                    CommonWidgets.outlineButton(
                      context: context,
                      text: '닫기',
                      onPressed: () => Navigator.pop(context),
                      icon: Icons.close,
                    ),

                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 업무유형 이미지 갤러리
  Widget _buildWorkTypeImages(BuildContext context, BusinessWorkTypeModel workType) {
    final images = <String>[];
    if (workType.thumbnailUrl != null) images.add(workType.thumbnailUrl!);
    if (workType.images != null) images.addAll(workType.images!);

    if (images.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 180,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: images.length,
        itemBuilder: (context, index) => Container(
          width: 240,
          margin: EdgeInsets.only(
            right: ResponsiveHelper.spacing(context, 12),
          ),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            image: DecorationImage(
              image: NetworkImage(images[index]),
              fit: BoxFit.cover,
            ),
          ),
        ),
      ),
    );
  }

  /// 시설 및 환경 섹션 (사업장 상세 스타일)
  Widget _buildFacilitiesSection(BuildContext context, ThemeData theme) {
    final hasFacilities = _business!.parkingAvailable ||
        (_business!.mealsProvided?.isNotEmpty == true) ||
        _business!.uniformProvided != null ||
        (_business!.facilities?.isNotEmpty == true);

    if (!hasFacilities) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommonWidgets.sectionHeader(
            context: context,
            title: '시설 및 환경',
            icon: Icons.check_circle_outline,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: CommonWidgets.cardDecoration(),
            child: Column(
              children: [
                // 주차
                _buildFacilityItem(
                  context,
                  Icons.local_parking,
                  '주차',
                  _business!.parkingAvailable ? '가능' : '불가',
                  _business!.parkingAvailable,
                ),
                
                // 식사
                if (_business!.mealsProvided?.isNotEmpty == true) ...[
                  Divider(height: ResponsiveHelper.spacing(context, 24)),
                  _buildFacilityItem(
                    context,
                    Icons.restaurant,
                    '식사',
                    _business!.mealsProvided!.join(', '),
                    true,
                  ),
                ],
                
                // 유니폼
                if (_business!.uniformProvided != null) ...[
                  Divider(height: ResponsiveHelper.spacing(context, 24)),
                  _buildFacilityItem(
                    context,
                    Icons.checkroom,
                    '유니폼',
                    _business!.uniformProvided!,
                    _business!.uniformProvided != '없음',
                  ),
                ],
                
                // 편의시설
                if (_business!.facilities?.isNotEmpty == true) ...[
                  Divider(height: ResponsiveHelper.spacing(context, 24)),
                  _buildFacilityItem(
                    context,
                    Icons.weekend,
                    '편의시설',
                    _business!.facilities!.join(', '),
                    true,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 찾아오시는 길 섹션 (교통편 + 지도)
  Widget _buildTransportSection(BuildContext context, ThemeData theme) {
    return Container(
      margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommonWidgets.sectionHeader(
            context: context,
            title: '찾아오시는 길',
            icon: Icons.location_on,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: CommonWidgets.cardDecoration(),
            child: Column(
              children: [
                // 주소 + 복사 버튼
                Row(
                  children: [
                    Expanded(
                      child: _buildTransportRow(
                        context,
                        Icons.place,
                        _business!.address,
                        _business!.detailAddress,
                      ),
                    ),
                    IconButton(
                      onPressed: () {
                        final fullAddress = _business!.detailAddress != null
                            ? '${_business!.address} ${_business!.detailAddress}'
                            : _business!.address;
                        Clipboard.setData(ClipboardData(text: fullAddress));
                        ToastHelper.showSuccess('주소가 복사되었습니다');
                      },
                      icon: Icon(
                        Icons.copy,
                        size: ResponsiveHelper.iconSize(context, 18),
                        color: theme.primaryColor,
                      ),
                      tooltip: '주소 복사',
                    ),
                  ],
                ),

                // 전화번호
                if (_business!.phone != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTransportRow(
                          context,
                          Icons.phone,
                          FormatHelper.formatPhone(_business!.phone!),
                          null,
                        ),
                      ),
                      IconButton(
                        onPressed: () => _callPhone(_business!.phone!),
                        icon: Icon(
                          Icons.call,
                          size: ResponsiveHelper.iconSize(context, 18),
                          color: theme.primaryColor,
                        ),
                        tooltip: '전화 걸기',
                      ),
                    ],
                  ),
                ],
                // 지하철
                if (_business!.nearestStation != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  _buildTransportRow(
                    context,
                    Icons.subway,
                    _business!.nearestStation!,
                    _business!.walkingMinutes != null
                        ? '도보 ${_business!.walkingMinutes}분'
                        : null,
                  ),
                ],
                
                // 버스
                if (_business!.busInfo != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  _buildTransportRow(
                    context,
                    Icons.directions_bus,
                    '버스',
                    _business!.busInfo,
                  ),
                ],
                
                // 지도
                if (_business!.latitude != null && _business!.longitude != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  GestureDetector(
                    onTap: () => _showFullMap(context),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 180,
                        child: KakaoMapWidget(
                          latitude: _business!.latitude!,
                          longitude: _business!.longitude!,
                          placeName: _business!.name,
                          showControls: false,
                        ),
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
      ),
    );
  }

  /// 상세 설명 섹션
  Widget _buildDescriptionSection(BuildContext context, ThemeData theme) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CommonWidgets.sectionHeader(
            context: context,
            title: '상세 설명',
            icon: Icons.description_outlined,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

          Container(
            width: double.infinity,
            padding: ResponsiveHelper.cardPadding(context),
            decoration: CommonWidgets.cardDecoration(),
            child: Text(
              _to!.description!,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                height: 1.6,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 하단 버튼 바
  Widget _buildBottomBar(BuildContext context, ThemeData theme) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: widget.mode == TODetailMode.applicant
            ? CommonWidgets.primaryButton(
                context: context,
                text: _to!.isClosed ? '마감된 공고입니다' : '지원하기',
                onPressed: _to!.isClosed ? () {} : () => _applyTO(context),
                icon: _to!.isClosed ? Icons.block : Icons.send,
              )
            : CommonWidgets.outlineButton(
                context: context,
                text: '닫기',
                onPressed: () => Navigator.pop(context),
                icon: Icons.close,
              ),
      ),
    );
  }

  // ============================================================
  // 헬퍼 위젯
  // ============================================================

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String text, {
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Row(
        children: [
          Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 18),
            color: theme.primaryColor,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Text(
              text,
              style: ResponsiveHelper.bodyStyle(context),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _buildTOInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Row(
      children: [
        Icon(
          icon,
          size: ResponsiveHelper.iconSize(context, 18),
          color: color,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Text(
          label,
          style: ResponsiveHelper.smallStyle(context).copyWith(
            color: Colors.grey[600],
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: ResponsiveHelper.bodyStyle(context).copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color color,
  ) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 20),
            color: color,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            value,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 2)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context).copyWith(
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailItem(
    BuildContext context,
    IconData icon,
    String title,
    String content,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 18),
              color: theme.primaryColor,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              title,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            content,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              height: 1.5,
              color: Colors.grey[700],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFacilityChip(BuildContext context, IconData icon, String label) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: theme.primaryColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 16),
            color: theme.primaryColor,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Text(
            label,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: theme.primaryColor,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransportRow(
    BuildContext context,
    IconData icon,
    String title,
    String? subtitle,
  ) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: theme.primaryColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 20),
            color: theme.primaryColor,
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (subtitle != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  subtitle,
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  // ============================================================
  // 헬퍼 함수
  // ============================================================

  bool _hasTransportInfo() {
    return _business?.nearestStation != null || 
          _business?.busInfo != null ||
          (_business?.latitude != null && _business?.longitude != null);
  }

  /// 시설 항목 (사업장 상세 스타일)
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
            color: isAvailable ? Colors.green[600] : Colors.grey[400],
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
        Icon(
          isAvailable ? Icons.check_circle : Icons.cancel,
          size: ResponsiveHelper.iconSize(context, 20),
          color: isAvailable ? Colors.green : Colors.grey[400],
        ),
      ],
    );
  }

  /// 전체 화면 지도 보기
  void _showFullMap(BuildContext context) {
    if (_business?.latitude == null || _business?.longitude == null) {
      ToastHelper.showError('위치 정보가 없습니다');
      return;
    }

    showDialog(
      context: context,
      builder: (context) => FullMapDialog(business: _business!),
    );
  }

  void _openMap() async {
    if (_business?.address == null) return;

    final query = Uri.encodeComponent(_business!.address);
    final url = 'https://map.kakao.com/link/search/$query';

    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (e) {
      ToastHelper.showError('지도를 열 수 없습니다');
    }
  }

  void _callPhone(String phone) async {
    final url = 'tel:$phone';
    try {
      await launchUrl(Uri.parse(url));
    } catch (e) {
      ToastHelper.showError('전화를 걸 수 없습니다');
    }
  }

  void _applyTO(BuildContext context) {
    // TODO: 지원 화면으로 이동 또는 지원 다이얼로그 표시
    ToastHelper.showInfo('지원하기 기능은 추후 구현 예정입니다');
  }
}