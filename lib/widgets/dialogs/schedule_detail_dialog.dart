import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/core/application_model.dart';
import '../../models/core/business_model.dart';
import '../../models/core/business_work_type_model.dart';
import '../../models/core/to_model.dart';
import '../../models/core/work_detail_data.dart';
import '../../models/core/insurance_rate_model.dart';
import '../../services/firestore_service.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/image_helper.dart';
import '../../utils/toast_helper.dart';
import '../../theme/app_colors.dart';
import 'styled_dialog.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/tax_deduction_badge.dart';
import '../../widgets/work_type_icon.dart';

/// 내 스케줄 → 근무 상세 BottomSheet
///
/// "공고 상세"가 아니라 "내가 실제로 근무할 일정"을 확인하는 화면.
/// ApplicationModel이 최우선 소스 — 지원/확정 당시 서버 스냅샷 데이터.
///
/// 데이터 우선순위:
///   wage/wageType     → CF가 Slot/TO에서 추출한 서버 스냅샷 (CASE A)
///   startTime/endTime → 클라이언트 제공, HH:MM 검증 (CASE C, 정상 흐름에서 Slot과 일치)
///   정산/공제/입금    → WorkDetailData (TOModel 배열 내 매칭)
///   주소/편의시설     → BusinessModel
///   업무 안내        → BusinessWorkTypeModel
class ScheduleDetailDialog extends StatefulWidget {
  final ApplicationModel application;

  const ScheduleDetailDialog({super.key, required this.application});

  @override
  State<ScheduleDetailDialog> createState() => _ScheduleDetailDialogState();
}

class _ScheduleDetailDialogState extends State<ScheduleDetailDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  bool _isLoading = true;
  BusinessModel? _business;
  BusinessWorkTypeModel? _workType;
  WorkDetailData? _workDetail;
  String _netTime = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        _firestoreService.getBusinessById(widget.application.businessId),
        _firestoreService.getTOByApplication(widget.application),
        _firestoreService.getBusinessWorkTypes(widget.application.businessId),
      ]);
      final biz = results[0] as BusinessModel?;
      final to  = results[1] as TOModel?;
      final wts = results[2] as List<BusinessWorkTypeModel>;

      BusinessWorkTypeModel? wt;
      try {
        wt = wts.firstWhere(
          (w) => w.name == widget.application.selectedWorkType,
          orElse: () => wts.isEmpty ? throw StateError('empty') : wts.first,
        );
      } catch (_) {}

      final wd = _resolveWorkDetail(to);
      final app = widget.application;
      final nt = FormatHelper.calcNetWorkTime(
        app.startTime, app.endTime,
        breakMinutes: wd?.breakMinutes ?? 0,
      );

      if (!mounted) return;
      setState(() {
        _business = biz;
        _workType = wt;
        _workDetail = wd;
        _netTime = nt;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 상세 정보 로드 실패: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
      ToastHelper.showError('일정 정보를 불러오는데 실패했습니다.');
    }
  }

  // WorkDetail 매칭: workType + startTime 우선, 레거시 폴백, 최종 ApplicationModel 복원
  WorkDetailData? _resolveWorkDetail(TOModel? to) {
    if (to == null) return null;
    final app = widget.application;

    final exact = to.workDetails
        .where((d) => d.workType == app.selectedWorkType && d.startTime == app.startTime)
        .firstOrNull;
    if (exact != null) return exact;

    final sameType = to.workDetails
        .where((d) => d.workType == app.selectedWorkType)
        .toList();
    if (sameType.length == 1) return sameType.first;

    // 매칭 실패 시 지원 당시 저장된 값으로 복원
    return WorkDetailData(
      workType: app.selectedWorkType,
      wage: app.wage,
      wageType: app.wageType ?? 'daily',
      requiredCount: 0,
      startTime: app.startTime,
      endTime: app.endTime,
    );
  }

  // ─── 상태 배지 ────────────────────────────────────────────
  ({String label, Color bg, Color fg}) get _statusInfo {
    final status = widget.application.status;
    if (status == AppStatus.contractPending) {
      return (label: '계약 진행 중', bg: AppColors.infoBg, fg: AppColors.infoDark);
    }
    if (AppStatus.confirmedStatuses.contains(status)) {
      return (label: '확정', bg: AppColors.successBg, fg: AppColors.successDark);
    }
    if (status == AppStatus.pending) {
      return (label: '대기', bg: AppColors.warningBg, fg: AppColors.warningDark);
    }
    if (status == AppStatus.rejected) {
      return (label: '거절', bg: AppColors.errorBg, fg: AppColors.errorDark);
    }
    return (label: '취소', bg: AppColors.grey100, fg: AppColors.grey500);
  }

  // ─── 편의 계산 ─────────────────────────────────────────────
  bool get _hasTransportInfo =>
      _business != null &&
      (_business!.transportDescription?.isNotEmpty == true ||
          _business!.transportImageUrls?.isNotEmpty == true);

  bool get _hasWorkGuide {
    final wt = _workType;
    final biz = _business;
    return (wt != null &&
            (wt.description != null ||
                wt.thumbnailUrl != null ||
                wt.images?.isNotEmpty == true ||
                wt.duties != null ||
                wt.workEnvironment != null ||
                wt.requirements != null ||
                wt.precautions != null)) ||
        (biz?.precautions?.isNotEmpty == true);
  }

  String get _confirmMessage =>
      widget.application.confirmMessage?.trim() ?? '';

  String _attendanceLabel(String type) => switch (type) {
        'gps'    => 'GPS 위치 인증',
        'beacon' => '비콘 출근 인증',
        'both'   => 'GPS + 비콘 인증',
        _        => '',
      };

  // ═══════════════════════════════════════════════════════════
  // Build
  // ═══════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 12)),
            width: ResponsiveHelper.spacing(context, 40),
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          _buildHeader(context),
          // Scrollable content
          Flexible(
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: LoadingWidget(),
                  )
                : SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(
                      ResponsiveHelper.spacing(context, 20),
                      0,
                      ResponsiveHelper.spacing(context, 20),
                      ResponsiveHelper.spacing(context, 32),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                        _buildWorkInfoSection(context),
                        _Divider(),
                        _buildLocationSection(context),
                        if (_hasWorkGuide) ...[
                          _Divider(),
                          _buildWorkGuideSection(context),
                        ],
                        if (_confirmMessage.isNotEmpty) ...[
                          _Divider(),
                          _buildManagerNoteSection(context),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ─── 헤더 ────────────────────────────────────────────────
  Widget _buildHeader(BuildContext context) {
    final app = widget.application;
    final si = _statusInfo;
    final isLong = app.isLongTermApplication;

    return Container(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 14),
        ResponsiveHelper.spacing(context, 4),
        ResponsiveHelper.spacing(context, 14),
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE8E9ED))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 날짜 배지 + 상태 배지
                Row(
                  children: [
                    // 날짜 배지
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 8),
                        vertical: ResponsiveHelper.spacing(context, 3),
                      ),
                      decoration: BoxDecoration(
                        color: isLong ? AppColors.longTermBg : AppColors.shortTermBg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        isLong
                            ? (app.workDaysDisplay ?? '장기')
                            : FormatHelper.formatDateCompact(app.workDate),
                        style: ResponsiveHelper.tinyStyle(context,
                            color: isLong
                                ? AppColors.longTermDark
                                : AppColors.shortTermDark,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    // 상태 배지
                    Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 8),
                        vertical: ResponsiveHelper.spacing(context, 3),
                      ),
                      decoration: BoxDecoration(
                        color: si.bg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        si.label,
                        style: ResponsiveHelper.tinyStyle(context,
                            color: si.fg, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                // 사업장명
                Text(
                  app.businessName,
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                // 업무명
                Row(
                  children: [
                    if (app.workTypeIcon != null)
                      WorkTypeIcon.buildWithBackground(
                        iconString: app.workTypeIcon!,
                        iconColor: app.workTypeColor ?? '#2196F3',
                        backgroundColor: app.workTypeBackgroundColor ?? '#E3F2FD',
                        size: 10,
                        containerSize: 18,
                      )
                    else
                      Icon(Icons.work_outline,
                          size: ResponsiveHelper.iconSize(context, 14),
                          color: AppColors.grey500),
                    SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                    Flexible(
                      child: Text(
                        app.selectedWorkType,
                        style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700)
                            .copyWith(fontWeight: FontWeight.w600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.close),
            color: AppColors.grey400,
          ),
        ],
      ),
    );
  }

  // ─── Section 1: 근무 정보 ────────────────────────────────
  Widget _buildWorkInfoSection(BuildContext context) {
    final app = widget.application;
    final wd = _workDetail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, '근무 정보'),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),

        // 근무일 (단기) 또는 근무 기간+요일 (장기)
        if (app.isLongTermApplication) ...[
          _infoRow(context, '근무 기간',
              Text(app.workPeriodDisplay, style: _valueStyle(context))),
          if (app.workDaysDisplay != null)
            _infoRow(context, '근무 요일',
                Text(app.workDaysDisplay!, style: _valueStyle(context))),
        ] else
          _infoRow(context, '근무일',
              Text(FormatHelper.formatDateLong(app.workDate), style: _valueStyle(context))),

        // 근무 시간
        _infoRow(
          context,
          '근무시간',
          Row(
            children: [
              Text('${app.startTime} ~ ${app.endTime}', style: _valueStyle(context)),
              if (_netTime.isNotEmpty) ...[
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Text(
                  '· 실근무 $_netTime',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                ),
              ],
            ],
          ),
        ),

        // 급여
        _infoRow(
          context,
          '급여',
          Text(
            '${FormatHelper.formatNumber(app.wage)}원 / ${app.wageTypeLabel}',
            style: _valueStyle(context),
          ),
        ),

        // 정산 주기
        if (wd?.payScheduleTypeLabel.isNotEmpty == true)
          _infoRow(context, '정산',
              Text(wd!.payScheduleTypeLabel, style: _valueStyle(context))),

        // 입금 예정
        if (wd?.payScheduleDetail.isNotEmpty == true)
          _infoRow(context, '입금 예정',
              Text(wd!.payScheduleDetail, style: _valueStyle(context))),

        // 공제 방식 — chip을 Align으로 감싸 Expanded 전체 채움 방지
        if (wd != null &&
            wd.taxDeductionType != InsuranceRateModel.typeNone)
          _infoRow(
            context,
            '공제',
            Align(
              alignment: Alignment.centerLeft,
              child: TaxDeductionBadge.chip(taxDeductionType: wd.taxDeductionType),
            ),
          ),
      ],
    );
  }

  // ─── Section 2: 근무 장소 ────────────────────────────────
  Widget _buildLocationSection(BuildContext context) {
    final app = widget.application;
    final biz = _business;
    // 로컬 변수로 추출 — Dart flow analysis가 if 블록 안에서 non-null로 승격
    final bizAddress = biz?.address;
    final bizPhone = biz?.phone;
    final attendLabel = _attendanceLabel(biz?.attendanceType ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, '근무 장소'),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),

        // 사업장명
        Text(
          app.businessName,
          style: ResponsiveHelper.bodyStyle(context)
              .copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
        ),

        // 주소
        if (bizAddress != null && bizAddress.isNotEmpty) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            bizAddress,
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
          ),
        ],

        // 전화 버튼
        if (bizPhone != null && bizPhone.isNotEmpty) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _call(bizPhone),
              icon: const Icon(Icons.phone_outlined, size: 18),
              label: Text('전화하기  $bizPhone'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.success,
                side: const BorderSide(color: AppColors.success),
                padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 12),
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],

        // 출근 인증 방식 (GPS/비콘 — 수동은 표시 안 함)
        if (attendLabel.isNotEmpty) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          _infoRow(context, '출근 인증',
              Text(attendLabel, style: _valueStyle(context))),
        ],

        // 찾아오는 길 (접혀 있음 → 탭 시 서브 시트)
        if (_hasTransportInfo) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          InkWell(
            onTap: () => _showTransportSheet(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 10),
                horizontal: ResponsiveHelper.spacing(context, 12),
              ),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE8E9ED)),
              ),
              child: Row(
                children: [
                  Icon(Icons.directions_transit_outlined,
                      size: ResponsiveHelper.iconSize(context, 16),
                      color: AppColors.infoDark),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      '찾아오는 길',
                      style: ResponsiveHelper.bodyStyle(context, color: AppColors.infoDark)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: ResponsiveHelper.iconSize(context, 18),
                      color: AppColors.grey400),
                ],
              ),
            ),
          ),
        ],

        // 편의 정보 칩 (주차 / 식사)
        if (_hasConvenienceInfo(biz)) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          _buildConvenienceChips(context, biz!),
        ],
      ],
    );
  }

  bool _hasConvenienceInfo(BusinessModel? biz) =>
      biz != null &&
      (biz.parkingAvailable ||
          (biz.mealsProvided?.isNotEmpty == true));

  Widget _buildConvenienceChips(BuildContext context, BusinessModel biz) {
    final chips = <Widget>[];
    if (biz.parkingAvailable) {
      chips.add(_chip(context, Icons.local_parking_outlined, '주차 가능', AppColors.info));
    }
    final mealsProvided = biz.mealsProvided;
    if (mealsProvided != null && mealsProvided.isNotEmpty) {
      chips.add(_chip(context, Icons.restaurant_outlined,
          '식사 ${mealsProvided.join("·")}', AppColors.success));
    }
    return Wrap(spacing: ResponsiveHelper.spacing(context, 8), children: chips);
  }

  Widget _chip(BuildContext context, IconData icon, String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 5),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 13), color: color),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: color,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ─── Section 3: 업무 안내 ────────────────────────────────
  Widget _buildWorkGuideSection(BuildContext context) {
    final wt = _workType;
    final biz = _business;
    final app = widget.application;

    final images = <String>[
      if (wt?.thumbnailUrl != null) wt!.thumbnailUrl!,
      if (wt?.images != null) ...wt!.images!,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, '업무 안내'),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),

        // 이미지 슬라이더
        // - 1장: full width, 복수: carousel(다음 사진 일부 노출 → affordance)
        if (images.isNotEmpty) ...[
          SizedBox(
            height: 130,
            child: images.length == 1
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: ImageHelper.buildCachedImage(
                      images[0],
                      fit: BoxFit.cover,
                      memCacheWidth: 800,
                      memCacheHeight: 520,
                    ),
                  )
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    clipBehavior: Clip.none,  // 오른쪽 잘림 없이 다음 사진 affordance
                    itemCount: images.length,
                    itemBuilder: (_, i) => Container(
                      width: 200,  // 컨테이너 너비 < 화면 → 다음 사진 일부 노출
                      margin: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 10)),
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
                      child: ImageHelper.buildCachedImage(
                        images[i],
                        fit: BoxFit.cover,
                        memCacheWidth: 600,
                        memCacheHeight: 390,
                      ),
                    ),
                  ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
        ],

        // 한 줄 소개 (selectedWorkType은 header에 이미 표시 — 중복 생략)
        // oneLineIntro가 없으면 이 블록 전체 생략 → 바로 상세 항목으로 시작
        if (wt?.oneLineIntro?.isNotEmpty == true) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              if (app.workTypeIcon != null)
                WorkTypeIcon.buildWithBackground(
                  iconString: app.workTypeIcon!,
                  iconColor: app.workTypeColor ?? '#2196F3',
                  backgroundColor: app.workTypeBackgroundColor ?? '#E3F2FD',
                  size: 12,
                  containerSize: 22,
                )
              else
                Icon(Icons.work_outline,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: AppColors.grey500),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: Text(
                  wt!.oneLineIntro!,
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600),
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        ],

        // 업무 설명
        if (wt?.description?.isNotEmpty == true) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 14)),
          _guideItem(context, '업무 설명', wt!.description!),
        ],

        // 주요 업무
        if (wt?.duties?.isNotEmpty == true) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          _guideItem(context, '주요 업무', wt!.duties!),
        ],

        // 근무 환경
        if (wt?.workEnvironment?.isNotEmpty == true) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          _guideItem(context, '근무 환경', wt!.workEnvironment!),
        ],

        // 자격 요건
        if (wt?.requirements?.isNotEmpty == true) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          _guideItem(context, '자격 요건', wt!.requirements!),
        ],

        // 업무 주의사항 (BusinessWorkType)
        if (wt?.precautions?.isNotEmpty == true) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          _guideItem(context, '주의사항', wt!.precautions!),
        ],

        // 준비사항 (Business — neutral, 경고색 없음)
        // 아이콘+진한 레이블로 다른 섹션과 구분감 강화
        if (biz?.precautions?.isNotEmpty == true) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          _guideItemPreparation(context, biz!.precautions!),
        ],
      ],
    );
  }

  Widget _guideItem(BuildContext context, String label, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500,
              fontWeight: FontWeight.w600),
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        Text(
          content,
          style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700)
              .copyWith(height: 1.55),
        ),
      ],
    );
  }

  /// 준비사항 전용 — 아이콘 + 진한 레이블로 다른 업무 설명 항목과 구분
  Widget _guideItemPreparation(BuildContext context, String content) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.checklist_rounded,
              size: ResponsiveHelper.iconSize(context, 13),
              color: AppColors.grey600,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            Text(
              '준비사항',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey700, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        Text(
          content,
          style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700)
              .copyWith(height: 1.55),
        ),
      ],
    );
  }

  // ─── Section 4: 관리자 안내 ─────────────────────────────
  Widget _buildManagerNoteSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, '관리자 안내'),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
          decoration: BoxDecoration(
            color: AppColors.grey50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE8E9ED)),
          ),
          child: Text(
            _confirmMessage,
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700)
                .copyWith(height: 1.55),
          ),
        ),
      ],
    );
  }

  // ─── 찾아오는 길 서브 시트 ──────────────────────────────
  Future<void> _showTransportSheet(BuildContext context) async {
    final biz = _business;
    if (biz == null) return;

    await DialogHelper.showSheet<void>(
      context,
      isScrollControlled: true,
      useRootNavigator: true,  // 루트 네비게이터로 열어 BottomNav dim 유지
      builder: (ctx) => _TransportSheet(business: biz),
    );
  }

  // ─── 공통 위젯 ─────────────────────────────────────────
  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: ResponsiveHelper.subtitleStyle(context)
          .copyWith(fontWeight: FontWeight.bold, color: AppColors.textPrimary),
    );
  }

  /// 평탄한 Label / Value 행
  Widget _infoRow(BuildContext context, String label, Widget value) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ResponsiveHelper.spacing(context, 80),
            child: Text(
              label,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }

  TextStyle _valueStyle(BuildContext context) =>
      ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary)
          .copyWith(fontWeight: FontWeight.w500);

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }
}

// ─── 구분선 ────────────────────────────────────────────────
class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 20),
      ),
      child: const Divider(height: 1, color: Color(0xFFE8E9ED)),
    );
  }
}

// ─── 찾아오는 길 서브 시트 ─────────────────────────────────
class _TransportSheet extends StatelessWidget {
  final BusinessModel business;

  const _TransportSheet({required this.business});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.75,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 12)),
            width: ResponsiveHelper.spacing(context, 40),
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 20),
              vertical: ResponsiveHelper.spacing(context, 16),
            ),
            child: Row(
              children: [
                Icon(Icons.directions_transit_outlined,
                    size: ResponsiveHelper.iconSize(context, 20),
                    color: AppColors.infoDark),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Expanded(
                  child: Text(
                    '찾아오는 길',
                    style: ResponsiveHelper.subtitleStyle(context)
                        .copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                  color: AppColors.grey400,
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE8E9ED)),
          // Content
          Flexible(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 20),
                ResponsiveHelper.spacing(context, 20),
                ResponsiveHelper.spacing(context, 20),
                ResponsiveHelper.spacing(context, 32),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 주소
                  if (business.address.isNotEmpty) ...[
                    Text(
                      '주소',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey500, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                    Text(
                      business.address,
                      style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                  ],

                  // 교통편 이미지
                  if (business.transportImageUrls?.isNotEmpty == true) ...[
                    SizedBox(
                      height: 160,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: business.transportImageUrls!.length,
                        itemBuilder: (_, i) => Container(
                          width: 220,
                          margin: EdgeInsets.only(
                              right: ResponsiveHelper.spacing(context, 10)),
                          clipBehavior: Clip.hardEdge,
                          decoration:
                              BoxDecoration(borderRadius: BorderRadius.circular(12)),
                          child: ImageHelper.buildCachedImage(
                            business.transportImageUrls![i],
                            fit: BoxFit.cover,
                            memCacheWidth: 660,
                            memCacheHeight: 480,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  ],

                  // 찾아오는 길 안내 텍스트 (transportDescription = 교통/경로 자유서술)
                  if (business.transportDescription?.isNotEmpty == true) ...[
                    Text(
                      '찾아오는 길 안내',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.grey500, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                    Text(
                      business.transportDescription!,
                      style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700)
                          .copyWith(height: 1.55),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  ],

                  // 주차 안내
                  Row(
                    children: [
                      Icon(
                        business.parkingAvailable
                            ? Icons.check_circle_outline
                            : Icons.cancel_outlined,
                        size: ResponsiveHelper.iconSize(context, 16),
                        color: business.parkingAvailable
                            ? AppColors.success
                            : AppColors.grey400,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                      Text(
                        business.parkingAvailable ? '주차 가능' : '주차 불가',
                        style: ResponsiveHelper.bodyStyle(
                          context,
                          color: business.parkingAvailable
                              ? AppColors.success
                              : AppColors.grey500,
                        ).copyWith(fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
