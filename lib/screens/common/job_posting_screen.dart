import 'dart:math' show max;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../providers/user_provider.dart';

// Models
import '../../models/core/business_model.dart';
import '../../models/core/to_model.dart';
import '../../models/core/work_detail_model.dart';
import '../../models/core/business_work_type_model.dart';
import '../../models/core/insurance_rate_model.dart';
import '../../widgets/common/tax_deduction_badge.dart';

// Services
import '../../services/firestore_service.dart';

// Models (slot, application)
import '../../models/core/slot_model.dart';
import '../../models/core/application_model.dart';

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/image_helper.dart';


// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/work_type_icon.dart';
import '../../widgets/maps/kakao_map_widget.dart';
import '../../widgets/maps/full_map_dialog.dart';
import '../../widgets/dialogs/apply/apply_work_dialog.dart';
import '../../theme/app_colors.dart';
import '../user/apply_prerequisites_screen.dart';

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

  /// flex TO 슬롯별 미리보기에서 전달 — 해당 날짜 슬롯의 실제 근무일
  final DateTime? slotDate;

  /// flex TO 슬롯별 미리보기에서 전달 — 해당 슬롯의 확정/모집 인원 (null이면 마스터 TO 집계 사용)
  final int? slotTotalRequired;
  final int? slotConfirmedCount;
  final int? slotPendingCount;

  /// 업무유형별 상세 통계 — workDetailStats[workDetailId] = {confirmed, pending}
  final Map<String, Map<String, int>>? workDetailStats;

  const JobPostingScreen({
    super.key,
    this.toId,
    this.to,
    this.workDetails,
    this.business,
    this.mode = TODetailMode.applicant,
    this.slotDate,
    this.slotTotalRequired,
    this.slotConfirmedCount,
    this.slotPendingCount,
    this.workDetailStats,
  }) : assert(toId != null || to != null, 'toId 또는 to 중 하나는 필수입니다');

  @override
  State<JobPostingScreen> createState() => _JobPostingScreenState();
}

class _JobPostingScreenState extends State<JobPostingScreen>
    with WidgetsBindingObserver {
  final FirestoreService _firestoreService = FirestoreService();
  UserProvider? _userProvider; // dispose()에서 context.read() 대신 캐시 사용

  bool _isLoading = true;
  TOModel? _to;
  BusinessModel? _business;
  List<WorkDetailModel> _workDetails = [];
  Map<String, BusinessWorkTypeModel> _workTypeMap = {};

  // flex TO 슬롯 데이터
  SlotModel? _slot;       // slotDate에 해당하는 단일 슬롯 (통계용)
  List<SlotModel> _allSlots = []; // 전체 슬롯 (_applyTO 다중 지원용)

  // 내 전체 지원 목록 (내 지원 현황 섹션용)
  List<ApplicationModel> _myApplications = [];
  String? _applicantUid;

  // 지원 자격 상태
  String? _applyBlockReason;
  bool get _isApplyable => _applyBlockReason == null;
  bool _isApplying = false; // 지원 진행 중 이중 탭 방어

  void _checkApplyEligibility() {
    if (!mounted) return;
    if (widget.mode != TODetailMode.applicant) return;
    final user = context.read<UserProvider>().currentUser;
    if (user == null) {
      setState(() => _applyBlockReason = '로그인이 필요합니다');
      return;
    }
    if (user.isBlacklisted) {
      setState(() => _applyBlockReason = '이용 제한된 계정입니다');
      return;
    }
    // isRestricted(노쇼 페널티)는 선결조건보다 먼저 체크 — 선결조건 완료 후에야 제한 안내가 뜨는 문제 방지
    // restrictedUntil이 과거이면 제한 만료로 처리 (apply_prerequisites_screen._isRestricted와 동일 로직)
    if (user.isRestricted) {
      final until = user.restrictedUntil;
      final isStillRestricted = until == null || until.isAfter(DateTime.now());
      if (isStillRestricted) {
        final remainDays = until != null ? (until.difference(DateTime.now()).inDays + 1) : null;
        setState(() => _applyBlockReason = remainDays != null
            ? '무단 결근 페널티 ($remainDays일 제한)'
            : '무단 결근 페널티 (이용 제한)');
        return;
      }
    }
    if (!user.isPassVerified) {
      setState(() => _applyBlockReason = 'PASS 인증이 필요합니다');
      return;
    }
    if (user.idCardImageUrl == null || user.idCardImageUrl!.isEmpty) {
      setState(() => _applyBlockReason = '신분증 등록이 필요합니다');
      return;
    }
    // flex 공고는 신분증 인증(isIdVerified)까지 요구 (apply_prerequisites_screen과 동일 조건)
    if (_to?.jobType == TOType.flex && !user.isIdVerified) {
      setState(() => _applyBlockReason = '신분증 인증이 필요합니다');
      return;
    }
    if (user.bankName == null || user.bankName!.isEmpty ||
        user.accountNumber == null || user.accountNumber!.isEmpty) {
      setState(() => _applyBlockReason = '통장 정보 등록이 필요합니다');
      return;
    }
    if (user.bankbookImageUrl == null || user.bankbookImageUrl!.isEmpty) {
      setState(() => _applyBlockReason = '통장사본 등록이 필요합니다');
      return;
    }
    setState(() => _applyBlockReason = null);
  }

  /// TO가 실질적으로 마감됐는지 (날짜 경과·정원 초과 포함)
  bool get _isEffectivelyClosed {
    if (_to == null) return false;
    if (_to!.isClosed) return true;

    // 정원 초과 체크 — _buildTOInfoCard의 로컬 isSlotFull과 동일 로직
    final req = _slot?.workDetails.fold<int>(0, (s, wd) => s + wd.requiredCount)
        ?? widget.slotTotalRequired
        ?? _to!.totalRequired;
    final conf = _slot?.confirmedCount ?? widget.slotConfirmedCount ?? _to!.totalConfirmed;
    if (req > 0 && conf >= req) return true;

    // slotDate가 명시된 경우(특정 날짜 뷰)에만 날짜 경과 체크.
    // flex 전체 뷰: slotDate 없음 → rangeStart가 과거일 수 있어 생략.
    // contract 전체 뷰: slotDate 없음 → TO 시작일이 과거여도 게시 기간 내 지원 가능하므로 생략.
    //   마감 여부는 아래 isDeadlinePassed / isPostingExpired 로만 판단.
    if (widget.slotDate != null) {
      final today = DateTime.now();
      final d = widget.slotDate!;
      if (DateTime(d.year, d.month, d.day)
          .isBefore(DateTime(today.year, today.month, today.day))) {
        return true;
      }
    }
    if (_to!.isContractType && (_to!.isDeadlinePassed || _to!.isPostingExpired)) {
      return true;
    }
    return false;
  }

  /// 공고 마감임박 여부
  /// - contract TO: TO 레벨 applicationDeadline 기준
  /// - flex TO: 특정 슬롯 또는 열린 슬롯 중 30분 이내 마감
  bool _isAnySoonDeadline() {
    if (_to == null) return false;
    if (!_to!.isFlexType) return _to!.isDeadlineSoon;

    final now = DateTime.now();

    // 특정 슬롯 뷰
    if (_slot != null) {
      final dl = _slot!.applicationDeadline;
      if (dl == null) return false;
      final diff = dl.difference(now).inMinutes;
      return diff >= 0 && diff <= 30;
    }

    // 전체 슬롯 뷰: 열린 슬롯 중 하나라도 30분 내 마감
    return _allSlots.any((s) {
      final dl = s.applicationDeadline;
      if (dl == null) return false;
      final diff = dl.difference(now).inMinutes;
      return diff >= 0 && diff <= 30;
    });
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    // UserProvider 변경 감지 — 다른 화면에서 사전조건 완료 후 돌아올 때 자동 갱신
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _userProvider = context.read<UserProvider>();
        _userProvider!.addListener(_checkApplyEligibility);
        _checkApplyEligibility();
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _userProvider?.removeListener(_checkApplyEligibility);
    super.dispose();
  }

  Future<void> _loadData() async {
    // context 사용은 async 이전에 수행
    _applicantUid = widget.mode == TODetailMode.applicant
        ? context.read<UserProvider>().currentUser?.uid
        : null;

    setState(() => _isLoading = true);

    try {
      // 직접 전달받은 경우
      if (widget.to != null) {
        _to = widget.to;
        _workDetails = widget.workDetails ?? [];
        _business = widget.business;
      } else {
        // Firestore에서 TO 로드 후 workDetails + business 병렬 로드
        _to = await _firestoreService.getTO(widget.toId!);
        if (_to != null) {
          final results = await Future.wait([
            _firestoreService.getWorkDetails(_to!.id),
            _firestoreService.getBusinessById(_to!.businessId),
          ]);
          _workDetails = results[0] as List<WorkDetailModel>;
          _business = results[1] as BusinessModel?;
        }
      }

      // 직접 전달 시 business가 없을 수 있음
      if (_business == null && _to != null) {
        _business = await _firestoreService.getBusinessById(_to!.businessId);
      }

      // flex TO: 슬롯 데이터 로드 (통계 + _applyTO 다중 지원)
      if (_to != null && _to!.isFlexType) {
        try {
          final slots = await _firestoreService.getSlots(_to!.id, visibleOnly: false);
          final now = DateTime.now();
          _allSlots = slots
              .where((s) => !s.isEffectivelyClosed)
              .where((s) => s.visibleFrom == null || !s.visibleFrom!.isAfter(now))
              .toList();

          if (widget.slotDate != null) {
            final sd = widget.slotDate!;
            _slot = slots.where((s) =>
                s.date.year == sd.year &&
                s.date.month == sd.month &&
                s.date.day == sd.day).firstOrNull;
            // 슬롯의 workDetails를 사용 (caller가 전달 안 했을 때 대비)
            if (_workDetails.isEmpty && _slot != null) {
              _workDetails = _slot!.workDetails;
            }
          }
        } catch (e) {
          debugPrint('⚠️ 슬롯 로드 실패: $e');
        }
      }

      // 업무유형 상세 정보 로드 (이미지, 설명 등)
      if (_business != null) {
        await _loadWorkTypes();
      }

      // 내 전체 지원 목록 로드 (내 지원 현황 섹션)
      if (widget.mode == TODetailMode.applicant && _applicantUid != null) {
        _myApplications =
            await _firestoreService.getMyApplications(_applicantUid!);
      }

    } catch (e) {
      debugPrint('❌ 데이터 로드 실패: $e');
      if (mounted) ToastHelper.showError('데이터를 불러오는데 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 업무유형 상세 정보 로드
  Future<void> _loadWorkTypes() async {
    try {
      final workTypes = await _firestoreService.getBusinessWorkTypes(_business!.id);
      _workTypeMap = {for (var wt in workTypes) wt.name: wt};
    } catch (e) {
      debugPrint('⚠️ 업무유형 로드 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.grey50,
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
                          // 사업장 정보 카드 (사업장 로드 실패 시 생략)
                          if (_business != null)
                            _buildBusinessInfoCard(context, theme),

                          // TO 정보 카드
                          _buildTOInfoCard(context, theme),

                          SizedBox(height: ResponsiveHelper.spacing(context, 12)),

                          // 준비사항 (업무 상세 위에 강조 표시)
                          if (_business?.precautions != null && _business!.precautions!.isNotEmpty) ...[
                            Container(
                              margin: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
                              child: CommonWidgets.infoCard(
                                context: context,
                                message: _business!.precautions!,
                                icon: Icons.warning_amber_outlined,
                                color: AppColors.warningDark,
                              ),
                            ),
                            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                          ],

                          // 업무 상세 섹션
                          _buildWorkDetailsSection(context, theme),

                          // 시설 및 환경
                          if (_business != null)
                            _buildFacilitiesSection(context, theme),

                          // 상세 설명
                          if (_to?.description != null && _to!.description!.isNotEmpty) ...[
                            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                            _buildDescriptionSection(context, theme),
                          ],

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
            color: AppColors.grey400,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            '공고를 찾을 수 없습니다',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              color: AppColors.grey600,
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
                  ImageHelper.buildCachedImage(
                    _business!.mainImageUrl!,
                    fit: BoxFit.cover,
                    fadeInDuration: const Duration(milliseconds: 150),
                    memCacheWidth: (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context)).toInt().clamp(600, 1200),
                  ),
                  // 그라데이션 오버레이
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.5),
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
                      theme.primaryColor.withValues(alpha: 0.8),
                    ],
                  ),
                ),
              ),
      ),
      leading: IconButton(
        icon: Container(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.3),
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
              color: AppColors.warning.withValues(alpha: 0.9),
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
                  color: theme.primaryColor.withValues(alpha: 0.1),
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
                          color: AppColors.grey600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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
            Divider(height: 1, color: AppColors.grey200),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: AppColors.grey500,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    _business!.detailedDescription!,
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      color: AppColors.grey700,
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
    final h = ResponsiveHelper.spacing(context, 16);

    final slotRequired = _slot?.workDetails.fold(0, (sum, wd) => sum + wd.requiredCount);
    final effectiveRequired = slotRequired ?? widget.slotTotalRequired ?? _to!.totalRequired;
    final effectiveConfirmed = _slot?.confirmedCount ?? widget.slotConfirmedCount ?? _to!.totalConfirmed;
    final isSlotFull = effectiveRequired > 0 && effectiveConfirmed >= effectiveRequired;
    // _isEffectivelyClosed getter 사용 — 날짜 경과 체크 포함 (슬롯 마감일 경과 포함)
    final isEffectivelyClosed = _isEffectivelyClosed;

    final (statusLabel, statusColor) = isEffectivelyClosed
        ? ('마감', AppColors.grey500)
        : _isAnySoonDeadline()
            ? ('마감임박', AppColors.warning)
            : ('모집중', AppColors.success);

    return Container(
      margin: EdgeInsets.only(left: h, right: h),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // TO 제목 + 상태 배지
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  _to!.title,
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: statusColor,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  statusLabel,
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

            SizedBox(height: ResponsiveHelper.spacing(context, 16)),

            // 날짜 정보
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.primaryColor.withValues(alpha: 0.1)),
              ),
              child: Column(
                children: [
                  // 근무일 (장기: 기간 범위 / 단기: 슬롯 날짜 또는 안내)
                  _buildTOInfoRow(
                    context,
                    Icons.calendar_today,
                    _to!.isLongTerm ? '근무기간' : '근무일',
                    _to!.isLongTerm
                        ? (_to!.startDate != null && _to!.endDate != null
                            ? '${FormatHelper.formatDate(_to!.startDate!)} ~ ${FormatHelper.formatDate(_to!.endDate!)}'
                            : _to!.groupDateRangeDisplay)
                        : (widget.slotDate ?? _slot?.date) != null
                            ? FormatHelper.formatDate(widget.slotDate ?? _slot!.date)
                            : '날짜 별 상이',
                    theme.primaryColor,
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                  // 근무 유형
                  _buildTOInfoRow(
                    context,
                    _to!.isLongTerm ? Icons.work_history : Icons.work_outline,
                    '근무 유형',
                    _to!.jobTypeLabel,
                    _to!.isLongTerm ? AppColors.purple : AppColors.info,
                  ),

                  // 장기 근무 요일
                  if (_to!.isLongTerm && _to!.workDays.isNotEmpty) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    _buildTOInfoRow(
                      context,
                      Icons.date_range,
                      '근무 요일',
                      _to!.workDaysLabel,
                      AppColors.purple,
                    ),
                  ],

                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                  // 마감 규칙 — 고정근무는 게시기간이 곧 지원기간
                  if (_to!.isLongTerm)
                    _buildTOInfoRow(
                      context,
                      Icons.timer_outlined,
                      '지원 마감',
                      '게시 기간 내 지원 가능',
                      AppColors.grey600,
                    )
                  else
                    _buildTOInfoRow(
                      context,
                      Icons.timer_outlined,
                      '지원 마감',
                      '업무시작 ${_to!.hoursBeforeStart ?? 2}시간 전',
                      _to!.isDeadlineSoon ? AppColors.error : AppColors.grey600,
                    ),

                  // 출퇴근 반올림 규칙 요약
                  if (_business != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    _buildTOInfoRow(
                      context,
                      Icons.access_time_outlined,
                      '출퇴근 규칙',
                      (_business!.attendanceRules ?? AttendanceRules.defaults()).summary,
                      AppColors.info,
                    ),
                  ],
                ],
              ),
            ),

            SizedBox(height: ResponsiveHelper.spacing(context, 16)),

            // 모집 현황 헤더
            Row(
              children: [
                Icon(Icons.bar_chart, size: 16, color: AppColors.grey500),
                const SizedBox(width: 6),
                Text(
                  '모집 현황',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: AppColors.grey600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),

            // 마감 상태 안내
            if (isEffectivelyClosed) ...[
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 12),
                  vertical: ResponsiveHelper.spacing(context, 10),
                ),
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: AppColors.grey500),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Text(
                      isSlotFull ? '인원이 모두 충족되어 마감되었습니다.' : '마감된 공고입니다.',
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: AppColors.grey600,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            ],

            // 모집 현황 (슬롯별 수치 우선, 없으면 마스터 TO 집계)
            Row(
              children: [
                Expanded(
                  child: _buildStatCard(
                    context,
                    Icons.people_outline,
                    '모집 인원',
                    '$effectiveRequired명',
                    AppColors.info,
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: _buildStatCard(
                    context,
                    Icons.check_circle_outline,
                    '확정 인원',
                    '$effectiveConfirmed명',
                    AppColors.success,
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Builder(builder: (_) {
                    final effectivePending = widget.slotPendingCount ?? _to!.totalPending;
                    final rawRemaining = effectiveRequired - effectiveConfirmed;
                    final remaining = (rawRemaining - effectivePending).clamp(0, effectiveRequired);
                    final color = remaining > 0 ? AppColors.warning : AppColors.error;
                    final valueText = remaining > 0
                        ? '$remaining명'
                        : (rawRemaining > 0 ? '대기 중' : '0명');
                    return Container(
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.hourglass_empty,
                              size: ResponsiveHelper.iconSize(context, 20), color: color),
                          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                          Text(valueText,
                              style: ResponsiveHelper.subtitleStyle(context)
                                  .copyWith(fontWeight: FontWeight.bold, color: color)),
                          SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                          Text('남은 자리',
                              style: ResponsiveHelper.tinyStyle(context)
                                  .copyWith(color: AppColors.grey600)),
                          if (effectivePending > 0 && rawRemaining > 0)
                            Text('(대기 $effectivePending명)',
                                style: ResponsiveHelper.tinyStyle(context)
                                    .copyWith(color: AppColors.warning, fontSize: 9)),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            ),
          ],
        ),
    );
  }

  /// 업무 상세 섹션
  Widget _buildWorkDetailsSection(BuildContext context, ThemeData theme) {
    final s = ResponsiveHelper.spacing(context, 16);
    return Container(
      margin: EdgeInsets.fromLTRB(s, 0, s, s),
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

    final workStats = widget.workDetailStats?[work.id];
    final workConfirmed = workStats?['confirmed'] ?? 0;
    final workPending = workStats?['pending'] ?? 0;
    final workRequired = work.requiredCount;
    final workAvailable = (workRequired - workConfirmed - workPending).clamp(0, workRequired);
    final hasWorkStats = widget.workDetailStats != null;

    final slotRequired = _slot?.workDetails.fold(0, (sum, wd) => sum + wd.requiredCount);
    final effectiveRequired = slotRequired ?? widget.slotTotalRequired ?? _to!.totalRequired;
    final effectiveConfirmed = _slot?.confirmedCount ?? widget.slotConfirmedCount ?? _to!.totalConfirmed;
    final isOverallClosed = _to!.isClosed ||
        (effectiveRequired > 0 && effectiveConfirmed >= effectiveRequired);
    final isWorkFull = workConfirmed >= workRequired && workRequired > 0;
    // isTimeExpired: 해당 업무의 지원 마감 시각 경과 여부
    final isClosed = isOverallClosed || isWorkFull || work.isTimeExpired;

    final netWorkTimeStr = FormatHelper.calcNetWorkTime(
      work.startTime,
      work.endTime,
      breakMinutes: work.breakMinutes,
    );

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      decoration: CommonWidgets.cardDecoration(),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: () => _showWorkTypeDetail(context, work, workType),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더: 아이콘 + (업무명 + 배지 + 시간/마감) + chevron
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: ResponsiveHelper.iconSize(context, 44),
                      height: ResponsiveHelper.iconSize(context, 44),
                      decoration: BoxDecoration(
                        color: FormatHelper.parseColor(work.workTypeBackgroundColor),
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
                          // 업무명 + 인원 배지
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  work.workType,
                                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isClosed ? AppColors.grey500 : AppColors.textPrimary,
                                  ),
                                ),
                              ),
                              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                              Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal: ResponsiveHelper.spacing(context, 10),
                                  vertical: ResponsiveHelper.spacing(context, 4),
                                ),
                                decoration: BoxDecoration(
                                  color: isClosed
                                      ? AppColors.grey200
                                      : theme.primaryColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isClosed
                                      ? '마감'
                                      : hasWorkStats
                                          ? '$workConfirmed / $workRequired명'
                                          : '$workRequired명 모집',
                                  style: ResponsiveHelper.tinyStyle(context).copyWith(
                                    color: isClosed
                                        ? AppColors.grey500
                                        : hasWorkStats
                                            ? (workConfirmed > 0 ? AppColors.success : theme.primaryColor)
                                            : theme.primaryColor,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                          // 시간 + 마감 (WorkDetailRow 동일 형식)
                          Wrap(
                            spacing: ResponsiveHelper.spacing(context, 8),
                            runSpacing: ResponsiveHelper.spacing(context, 2),
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: ResponsiveHelper.iconSize(context, 13),
                                    color: AppColors.grey400,
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                                  Text(
                                    '${work.startTime} ~ ${work.endTime}',
                                    style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                                  ),
                                  if (netWorkTimeStr.isNotEmpty) ...[
                                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                                    Text(
                                      '($netWorkTimeStr)',
                                      style: ResponsiveHelper.tinyStyle(context).copyWith(
                                        color: AppColors.grey500,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (!_to!.isLongTerm && work.applicationDeadline != null)
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.timer_off_outlined,
                                      size: ResponsiveHelper.iconSize(context, 13),
                                      color: work.isTimeExpired ? AppColors.errorFaded : AppColors.warningDark,
                                    ),
                                    SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                                    Text(
                                      '마감 ${FormatHelper.formatTime(work.applicationDeadline!)}',
                                      style: ResponsiveHelper.smallStyle(
                                        context,
                                        color: work.isTimeExpired ? AppColors.errorFaded : AppColors.warningDark,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right,
                      size: ResponsiveHelper.iconSize(context, 20),
                      color: AppColors.grey400,
                    ),
                  ],
                ),

                // 통계 바 (workDetailStats 있을 때만)
                if (hasWorkStats && workRequired > 0) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  _buildWorkStatRow(context, workConfirmed, workPending, workAvailable, workRequired),
                ],

                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                Divider(height: 1, color: AppColors.grey200),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),

                // 급여 + 정산주기
                Row(
                  children: [
                    Icon(
                      Icons.paid,
                      size: ResponsiveHelper.iconSize(context, 14),
                      color: AppColors.successMedium,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Flexible(
                      child: Text(
                        () {
                          final base = '${work.wageTypeLabel} ${work.formattedWage}';
                          final schedule = work.payScheduleTypeLabel;
                          return schedule.isNotEmpty ? '$base · $schedule' : base;
                        }(),
                        style: ResponsiveHelper.smallStyle(context).copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.successDark,
                        ),
                      ),
                    ),
                  ],
                ),

                // 입금일 상세
                if (work.payScheduleDetail.isNotEmpty) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                  Row(
                    children: [
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        size: ResponsiveHelper.iconSize(context, 14),
                        color: AppColors.grey500,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                      Text(
                        '${work.payScheduleDetail} 입금',
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                      ),
                    ],
                  ),
                ],

                // 원천징수
                if (work.taxDeductionType != InsuranceRateModel.typeNone) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                  TaxDeductionBadge.row(taxDeductionType: work.taxDeductionType),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 업무유형 통계 바 (확정/대기/남은 미니 표시)
  Widget _buildWorkStatRow(
    BuildContext context,
    int confirmed,
    int pending,
    int available,
    int required,
  ) {
    final progress = required > 0 ? confirmed / required : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 통계 수치 행
        Row(
          children: [
            _buildWorkStatChip(context, Icons.check_circle_outline, '확정', confirmed, AppColors.success),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            _buildWorkStatChip(context, Icons.hourglass_top_outlined, '대기', pending, AppColors.warning),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            _buildWorkStatChip(
              context,
              Icons.person_add_outlined,
              '남은',
              available,
              available > 0 ? AppColors.info : AppColors.error,
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        // 진행률 바
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            minHeight: 5,
            backgroundColor: AppColors.grey200,
            valueColor: AlwaysStoppedAnimation<Color>(
              progress >= 1.0 ? AppColors.success : AppColors.info,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkStatChip(
    BuildContext context,
    IconData icon,
    String label,
    int count,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: ResponsiveHelper.iconSize(context, 13), color: color),
        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
        Text(
          '$label $count명',
          style: ResponsiveHelper.tinyStyle(context).copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// 업무유형 상세 BottomSheet
  void _showWorkTypeDetail(
    BuildContext context,
    WorkDetailModel work,
    BusinessWorkTypeModel? workType,
  ) {
    final hasDetailInfo = workType != null &&
        (workType.description != null ||
            workType.thumbnailUrl != null ||
            workType.images?.isNotEmpty == true);

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
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
                  color: AppColors.grey300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // 컨텐츠
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: () {
                    final cp = ResponsiveHelper.cardPadding(context);
                    return EdgeInsets.fromLTRB(
                      cp.left,
                      cp.top,
                      cp.right,
                      // edge-to-edge 대응: viewPaddingOf는 SafeArea 소비 무관 물리적 인셋.
                      // max로 SafeArea 정상 동작 시 이중 합산 방지.
                      max(cp.bottom, MediaQuery.viewPaddingOf(context).bottom),
                    );
                  }(),
                  children: [
                    // 헤더: 아이콘 + 업무명
                    Row(
                      children: [
                        Container(
                          width: ResponsiveHelper.iconSize(context, 56),
                          height: ResponsiveHelper.iconSize(context, 56),
                          decoration: BoxDecoration(
                            color: FormatHelper.parseColor(work.workTypeBackgroundColor),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: WorkTypeIcon.buildFromString(
                              work.workTypeIcon,
                              color: FormatHelper.parseColor(work.workTypeColor),
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
                                work.workType,
                                style: ResponsiveHelper.titleStyle(context).copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (workType?.oneLineIntro != null) ...[
                                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                                Text(
                                  workType!.oneLineIntro!,
                                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                                    color: AppColors.grey600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                    Divider(height: 1, color: AppColors.grey200),
                    SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                    // 기본 근무 정보 (항상 표시)
                    _buildDetailItem(
                      context,
                      Icons.schedule_outlined,
                      '근무 시간',
                      work.timeRange,
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    _buildDetailItem(
                      context,
                      Icons.payments_outlined,
                      '급여',
                      () {
                        final base = '${work.wageTypeLabel} ${work.formattedWage}';
                        final schedule = work.payScheduleTypeLabel;
                        return schedule.isNotEmpty ? '$base · $schedule' : base;
                      }(),
                    ),
                    if (work.payScheduleDetail.isNotEmpty) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                      _buildDetailItem(
                        context,
                        Icons.account_balance_wallet_outlined,
                        '입금일',
                        work.payScheduleDetail,
                      ),
                    ],
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    _buildDetailItem(
                      context,
                      Icons.people_outline,
                      '모집 인원',
                      '${work.requiredCount}명',
                    ),

                    // 업무유형 상세 정보 (등록된 경우)
                    if (hasDetailInfo) ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                      Divider(height: 1, color: AppColors.grey200),
                      SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                      if (workType.thumbnailUrl != null || workType.images?.isNotEmpty == true)
                        _buildWorkTypeImages(context, workType),

                      if (workType.description != null) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                        _buildDetailItem(
                          context,
                          Icons.description_outlined,
                          '업무 설명',
                          workType.description!,
                        ),
                      ],

                      if (workType.workEnvironment != null) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                        _buildDetailItem(
                          context,
                          Icons.thermostat_outlined,
                          '근무 환경',
                          workType.workEnvironment!,
                        ),
                      ],

                      if (workType.requirements != null) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                        _buildDetailItem(
                          context,
                          Icons.checklist_outlined,
                          '자격 요건',
                          workType.requirements!,
                        ),
                      ],

                      if (workType.duties != null) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                        _buildDetailItem(
                          context,
                          Icons.task_alt_outlined,
                          '주요 업무',
                          workType.duties!,
                        ),
                      ],

                      if (workType.precautions != null) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                        CommonWidgets.infoCard(
                          context: context,
                          message: workType.precautions!,
                          icon: Icons.warning_amber_outlined,
                          color: AppColors.warningDark,
                        ),
                      ],
                    ] else ...[
                      SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                      Center(
                        child: Text(
                          '업무 유형 상세 정보가 등록되지 않았습니다.',
                          style: ResponsiveHelper.smallStyle(context).copyWith(
                            color: AppColors.grey400,
                          ),
                        ),
                      ),
                    ],

                    SizedBox(height: ResponsiveHelper.spacing(context, 32)),

                    // 지원자 모드: 지원하기 + 닫기 / 관리자 모드: 닫기만
                    if (widget.mode == TODetailMode.applicant) ...[
                      Builder(builder: (sheetCtx) {
                        // _isEffectivelyClosed는 _slot?.confirmedCount를 우선 사용 — 중복 계산 불필요
                        final isClosed = _isEffectivelyClosed;
                        final isBlocked = isClosed || !_isApplyable || _isApplying;
                        return CommonWidgets.primaryButton(
                          context: sheetCtx,
                          text: isClosed
                              ? '마감된 공고입니다'
                              : _isApplying
                                  ? '처리 중...'
                                  : !_isApplyable
                                      ? _applyBlockReason ?? '지원 불가'
                                      : '지원하기',
                          icon: isBlocked ? Icons.block : Icons.send,
                          onPressed: isBlocked
                              ? null
                              : () {
                                  Navigator.pop(sheetCtx);
                                  _applyTO();
                                },
                        );
                      }),
                      SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                    ],
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
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: ImageHelper.buildCachedImage(
              images[index],
              fit: BoxFit.cover,
              memCacheWidth: 720,
              memCacheHeight: 540,
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
                // 교통편 사진 — 신규 필드
                if (_business!.transportImageUrls != null &&
                    _business!.transportImageUrls!.isNotEmpty) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  SizedBox(
                    height: 100,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _business!.transportImageUrls!.length,
                      itemBuilder: (ctx, i) => GestureDetector(
                        onTap: () => CommonWidgets.showImagePreview(
                          context,
                          _business!.transportImageUrls!,
                          initialIndex: i,
                        ),
                        child: Container(
                          width: 100,
                          height: 100,
                          margin: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: ImageHelper.buildCachedImage(
                              _business!.transportImageUrls![i],
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
                  ),
                ],

                // 교통편 상세설명 — 신규 필드 우선, 레거시 폴백
                if (_business!.transportDescription != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  _buildTransportRow(
                    context,
                    Icons.directions,
                    _business!.transportDescription!,
                    null,
                  ),
                ] else ...[
                  // 레거시 필드 폴백
                  if (_business!.nearestStation != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    _buildTransportRow(
                      context,
                      Icons.subway,
                      _business!.nearestStation!,
                      _business!.walkingMinutes != null ? '도보 ${_business!.walkingMinutes}분' : null,
                    ),
                  ],
                  if (_business!.busInfo != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    _buildTransportRow(
                      context,
                      Icons.directions_bus,
                      '버스',
                      _business!.busInfo,
                    ),
                  ],
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
                color: AppColors.grey700,
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
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false, // bottomNavigationBar 위치 — 상단 SafeArea 불필요
        child: widget.mode == TODetailMode.applicant
            ? CommonWidgets.primaryButton(
                context: context,
                text: _isEffectivelyClosed
                    ? '마감된 공고입니다'
                    : !_isApplyable
                        // _isApplyable == (_applyBlockReason == null) 이므로 논리상 non-null이나, 향후 불일치 방지용 null-coalescing
                        ? _applyBlockReason ?? ''
                        : '지원하기',
                onPressed: (_isEffectivelyClosed || !_isApplyable || _isApplying) ? null : () => _applyTO(),
                icon: (_isEffectivelyClosed || !_isApplyable) ? Icons.block : _isApplying ? Icons.hourglass_empty : Icons.send,
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
            color: AppColors.grey600,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
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
        color: color.withValues(alpha: 0.1),
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
              color: AppColors.grey600,
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
            color: AppColors.grey100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            content,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              height: 1.5,
              color: AppColors.grey700,
            ),
          ),
        ),
      ],
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
            color: theme.primaryColor.withValues(alpha: 0.1),
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
                    color: AppColors.grey600,
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
            color: isAvailable ? AppColors.successBg : AppColors.grey100,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            icon,
            size: ResponsiveHelper.iconSize(context, 20),
            color: isAvailable ? AppColors.successMedium : AppColors.grey400,
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
          color: isAvailable ? AppColors.success : AppColors.grey400,
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

  Future<void> _callPhone(String phone) async {
    final url = 'tel:$phone';
    try {
      await launchUrl(Uri.parse(url));
    } catch (e) {
      if (mounted) ToastHelper.showError('전화를 걸 수 없습니다');
    }
  }

  Future<void> _applyTO() async {
    if (_isLoading || _isApplying) return;
    if (_to == null) return;
    setState(() => _isApplying = true);
    try {
      // 지원 전 필수 서류·인증 체크 — 미완료 항목 있으면 전체 화면으로 이동
      final user = context.read<UserProvider>().currentUser;
      if (user == null) return;
      if (!meetsApplyPrerequisites(user, isFlexType: _to!.isFlexType)) {
        final ok = await ApplyPrerequisitesScreen.show(context, isFlexType: _to!.isFlexType);
        if (!ok || !mounted) return;
      }

      if (_to!.isFlexType) {
        // flex TO — 단일 슬롯(slotDate 있음) 또는 다중 슬롯
        if (widget.slotDate != null && _slot != null) {
          final slotTO = _to!.copyWith(rangeStart: _slot!.date);
          final result = await ApplyWorkDialog.show(
            context: context,
            to: slotTO,
            workDetails: _slot!.workDetails,
            businessName: _to!.businessName,
            slotId: _slot!.id,
            myApplications: _myApplications,
          );
          if (result?.hasChanges == true && mounted) Navigator.pop(context, true);
        } else {
          // 다중 슬롯 지원 다이얼로그
          final now = DateTime.now();
          final Map<DateTime, TOModel> groupTOsByDate = {};
          final Map<DateTime, List<WorkDetailModel>> groupWorkDetailsByDate = {};
          final Map<DateTime, String> groupSlotIdsByDate = {};

          for (final slot in _allSlots) {
            if (slot.isEffectivelyClosed) continue;
            if (slot.visibleFrom != null && slot.visibleFrom!.isAfter(now)) continue;
            if (slot.workDetails.isNotEmpty &&
                slot.workDetails.every((wd) => wd.isTimeExpired)) { continue; }
            final key = DateTime(slot.date.year, slot.date.month, slot.date.day);
            groupTOsByDate[key] = _to!.copyWith(rangeStart: slot.date);
            groupWorkDetailsByDate[key] = slot.workDetails.map((wd) =>
                slot.isWorkTypeFull(wd.workType)
                    ? wd.copyWith(runtimeFull: true)
                    : wd).toList();
            groupSlotIdsByDate[key] = slot.id;
          }

          if (groupTOsByDate.isEmpty) {
            if (mounted) ToastHelper.showError('지원 가능한 날짜가 없습니다');
            return;
          }

          if (!mounted) return;
          final result = await ApplyWorkDialog.show(
            context: context,
            to: _to!,
            workDetails: _workDetails,
            businessName: _to!.businessName,
            groupTOsByDate: groupTOsByDate,
            groupWorkDetailsByDate: groupWorkDetailsByDate,
            groupSlotIdsByDate: groupSlotIdsByDate,
            myApplications: _myApplications,
          );
          if (result?.hasChanges == true && mounted) Navigator.pop(context, true);
        }
        return;
      }

      // contract TO
      var details = _workDetails;
      if (details.isEmpty) {
        setState(() => _isLoading = true);
        try {
          details = await _firestoreService.getWorkDetails(_to!.id);
          if (!mounted) return;
          setState(() => _workDetails = details);
        } catch (e) {
          debugPrint('❌ 업무 정보 로드 실패: $e');
          if (mounted) ToastHelper.showError('업무 정보를 불러오지 못했습니다');
          return;
        } finally {
          if (mounted) setState(() => _isLoading = false);
        }
        if (details.isEmpty) {
          if (mounted) ToastHelper.showError('업무 정보를 불러오지 못했습니다');
          return;
        }
      }
      if (!mounted) return;
      final result = await ApplyWorkDialog.show(
        context: context,
        to: _to!,
        workDetails: details,
        businessName: _to!.businessName,
        myApplications: _myApplications,
      );
      // contract TO도 flex TO와 동일하게 true 반환 — AllTOListScreen._refreshMyApplications 트리거에 필요
      if (result?.hasChanges == true && mounted) Navigator.pop(context, true);
    } catch (e) {
      debugPrint('❌ 지원 처리 실패: $e');
      if (mounted) ToastHelper.showError('지원 처리 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _isApplying = false);
    }
  }

}
