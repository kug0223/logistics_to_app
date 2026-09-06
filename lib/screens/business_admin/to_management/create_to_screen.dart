import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

// Models
import '../../../models/core/business_model.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/business_work_type_model.dart';
import '../../../models/core/contract_template_model.dart';
import '../../../models/core/work_detail_data.dart';
import '../../../models/work_detail_input.dart';

// Services & Providers
import '../../../services/firestore_service.dart';
import '../../../services/analytics_service.dart';
import '../../../services/contract_template_service.dart';
import '../../../services/business_posting_readiness.dart';
import '../../../providers/user_provider.dart';

// Utils
import '../../../utils/format_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/dialog_helper.dart';

// Theme
import '../../../theme/app_colors.dart';

// Widgets
import '../../../widgets/pickers/create_edit_work_detail_dialog.dart';
// 공통 위젯
import 'widgets/to_widgets.dart';
import '../../../widgets/app_select_field.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../common/settings_screen.dart';
import '../contract_template_list_screen.dart';
import '../work_type_management_screen.dart';
import '../Business_form_screen.dart';
import '../../common/notification_screen.dart';
import '../../../widgets/common/notification_badge.dart';

/// 사업장별 사전조건 충족 여부 — [5D.2A] licenseReady 추가
class _BizReadiness {
  final BusinessModel business;
  final bool workTypesReady;
  final bool licenseReady;
  const _BizReadiness({
    required this.business,
    required this.workTypesReady,
    required this.licenseReady,
  });
}

class AdminCreateTOScreen extends StatefulWidget {
  /// [HOTFIX HOME.POSTING.ENTRY.1-R1] caller context 상속용 optional 파라미터.
  /// SUB_ADMIN Home 공고등록 진입 시 effectiveBusinessId를 전달해
  /// CreateTO 최초 사업장이 Home context와 일치하도록 한다.
  /// - 유효하면(approved 목록에 존재) → 반드시 해당 사업장 초기 선택
  /// - 유효하지 않으면 → 기존 fallback(workTypes-ready 첫 번째 / first) 사용
  /// - null → 기존 동작 유지 (OWNER, businessList, Jobs 진입 등)
  const AdminCreateTOScreen({super.key, this.initialBusinessId, this.initialTO});

  final String? initialBusinessId;
  /// [REPOST-R1] CLOSED TO에서 다시 모집하기 진입 시 설정.
  /// 사업장 확정 후 _loadDataFromTO()로 1회 자동 불러오기.
  /// sourceToId 없음 — 새 독립 공고 생성.
  final TOModel? initialTO;

  @override
  State<AdminCreateTOScreen> createState() => _AdminCreateTOScreenState();
}

class _AdminCreateTOScreenState extends State<AdminCreateTOScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _groupTitleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // Scroll-to-error 지원
  final _businessSectionKey = GlobalKey();
  final _titleSectionKey = GlobalKey();
  final _dateSectionKey = GlobalKey();
  final _workDetailSectionKey = GlobalKey();

  void _scrollToSection(GlobalKey key) {
    final ctx = key.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      alignment: 0.0,
    );
  }

  // 로딩 상태
  bool _isLoading = false; // initState에서 _loadMyBusinesses() 호출 시 가드 통과를 위해 false 초기화
  bool _isCreating = false;
  bool _hasChanges = false; // 미저장 변경 감지용

  // 사업장 관련
  List<BusinessModel> _myBusinesses = [];
  BusinessModel? _selectedBusiness;
  List<BusinessWorkTypeModel> _businessWorkTypes = [];
  final _contractTemplateService = ContractTemplateService();

  // 사전조건 상태 — 3가지 모두 충족돼야 공고 등록 가능
  bool _hasAnyBusiness = false;
  bool _businessApproved = false;
  bool _workTypesReady = false;
  bool _contractTemplatesReady = false;
  bool _formUnlocked = false;        // 한번 true가 되면 항상 폼 표시 (일방향 래치)
  bool _hasLicense = false;           // 사업자등록증 등록 여부
  bool _hasSeal = false;              // 인감/서명 등록 여부 (SubAdmin 면제)
  List<_BizReadiness> _businessReadinessList = []; // 멀티 사업장 결핍 정보
  bool get _allPrerequisitesMet =>
      _businessApproved && _workTypesReady && _contractTemplatesReady &&
      _hasLicense && _hasSeal;

  // TO 설정 — 'flex' 단기 / 'contract' 장기
  String _selectedJobType = TOType.flex;

  // 날짜 선택 (flex용)
  final List<DateTime> _selectedDates = [];

  // 계약 기간 (contract용)
  final List<String> _selectedWeekdays = [];
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  String? _contractPeriodType; // '15days' | '1month' | '3months' | '6months' | '1year' | 'custom'
  // 근무 시작 가능기간 (preset 전용)
  DateTime? _workStartAvailableFrom;
  DateTime? _workStartAvailableUntil;
  int? _postingDurationDays = 7; // 기본 7일

  // 지원 마감
  int _hoursBeforeStart = 2;

  // 예약 공개
  String _publishMode = 'immediate';
  int _publishDaysBefore = 1;
  String _publishTime = '14:00';

  // 업무 상세
  final List<WorkDetailInput> _workDetails = [];

  // 기존 공고 불러오기용
  List<TOModel> _recentTOsForLoad = [];

  // ============================================================
  // 라이프사이클
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadMyBusinesses();
    // 제목 입력 시 _hasChanges 활성화
    for (final ctrl in [_titleController, _groupTitleController, _descriptionController]) {
      ctrl.addListener(() {
        if (ctrl.text.isNotEmpty && !_hasChanges) {
          setState(() => _hasChanges = true);
        }
      });
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _groupTitleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  // ============================================================
  // 데이터 로딩
  // ============================================================

  Future<void> _loadMyBusinesses() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;
      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final List<BusinessModel> allBusinesses;
      if (userProvider.isSubAdmin) {
        final bizIds = userProvider.currentUser?.subAdminBusinessIds ?? [];
        allBusinesses = bizIds.isNotEmpty
            ? await _firestoreService.getBusinessesByIds(bizIds)
            : [];
      } else {
        final managedIds = userProvider.currentUser?.managedBusinessIds ?? [];
        allBusinesses = await _firestoreService.getBusinessesByIds(managedIds);
      }
      final approvedBusinesses = allBusinesses.where((b) => b.isApproved).toList();
      // 인감/서명: UserModel.sealBase64 기준 (SubAdmin 면제 — 계약서 날인은 사업주 계정)
      final bool hasSeal = userProvider.isSubAdmin
          ? true
          : (userProvider.currentUser?.sealBase64?.isNotEmpty ?? false);

      if (!mounted) return;

      // [HOTFIX-1C-UNAPPROVED] initialBusinessId가 미승인 사업장을 가리킬 때:
      // approved 목록 fallback(B auto-jump) 금지 — 현재 effectiveBusinessId context 상속.
      // Policy (§ HOME.POSTING.ENTRY.1-R1): 미승인이어도 membership 유효 → A 선택 + 승인 필요 안내.
      // checks는 approvedBusinesses만 포함하므로, 미승인 A의 initCheck는 null → B fallback이 발생함.
      // 이 분기가 그 auto-jump를 차단한다.
      final initBizIdForApprovalCheck = widget.initialBusinessId;
      if (initBizIdForApprovalCheck != null) {
        final initBizFromAll = allBusinesses
            .where((b) => b.id == initBizIdForApprovalCheck)
            .firstOrNull;
        if (initBizFromAll != null && !initBizFromAll.isApproved) {
          setState(() {
            _hasAnyBusiness = true;
            _businessApproved = false;
            _workTypesReady = false;
            _contractTemplatesReady = false;
            _hasLicense = false;
            _hasSeal = hasSeal;
            _businessReadinessList = [];
            _selectedBusiness = initBizFromAll;
            _myBusinesses = [];
            _isLoading = false;
          });
          return;
        }
      }

      if (approvedBusinesses.isEmpty) {
        setState(() {
          _hasAnyBusiness = allBusinesses.isNotEmpty;
          _businessApproved = false;
          _workTypesReady = false;
          _contractTemplatesReady = false;
          _hasLicense = false;
          _hasSeal = hasSeal;
          _businessReadinessList = [];
          _isLoading = false;
        });
        return;
      }

      // [5D.2A] 사업장별 readiness 병렬 로드:
      //   - 라이선스: canonical(business 문서) OR owner legacy(business.ownerId user 문서)
      //     SubAdmin/co-admin 호출자의 businessLicenseImageUrl은 사용하지 않음
      //   - workTypes: isActive==true >= 1
      //   - 계약서 템플릿: 전역 합산
      final checks = await Future.wait(
        approvedBusinesses.map((biz) async {
          // License: canonical 먼저, 없으면 ownerId 기준 legacy
          bool licenseReady = biz.businessLicenseImageUrl?.isNotEmpty == true;
          if (!licenseReady && biz.ownerId.isNotEmpty) {
            try {
              final ownerSnap = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(biz.ownerId)
                  .get();
              licenseReady =
                  (ownerSnap.data()?['businessLicenseImageUrl'] as String?)
                          ?.isNotEmpty ==
                      true;
            } catch (_) {}
          }

          final res = await Future.wait([
            _firestoreService.getBusinessWorkTypes(biz.id),
            _contractTemplateService.getTemplates(biz.id),
          ]);
          return (
            business: biz,
            workTypes: res[0] as List<BusinessWorkTypeModel>,
            templates: res[1] as List<ContractTemplateModel>,
            licenseReady: licenseReady,
          );
        }),
      );

      if (!mounted) return;

      // 계약서 템플릿은 사업장 무관 전역 체크 — 모든 사업장 합산
      final allTemplates = checks.expand((c) => c.templates).toList();

      // [HOTFIX HOME.POSTING.ENTRY.1-R1] 사업장 선택 우선순위:
      //   1. widget.initialBusinessId가 approved 목록에 존재 → 반드시 해당 사업장 선택
      //      (Home effectiveBusiness context 상속 — A incomplete여도 B로 자동 전환 금지)
      //   2. workTypes-ready 첫 번째 사업장
      //   3. checks.first (기존 fallback)
      // [5D.2A] _hasLicense는 선택된 사업장 기준 — 다른 사업장의 license가 대신하면 안 됨
      final ready = checks.where((c) => c.workTypes.isNotEmpty);

      final initBizId = widget.initialBusinessId;
      final initCheck = initBizId != null
          ? checks.where((c) => c.business.id == initBizId).firstOrNull
          : null;

      // sel: initialBusinessId 우선 → ready.first → checks.first
      final sel = initCheck ?? (ready.isNotEmpty ? ready.first : checks.first);
      final selWorkTypesReady = sel.workTypes.isNotEmpty;

      setState(() {
        _myBusinesses = approvedBusinesses;
        _selectedBusiness = sel.business;
        _businessWorkTypes = sel.workTypes;
        _hasAnyBusiness = true;
        _businessApproved = true;
        _workTypesReady = selWorkTypesReady;
        _contractTemplatesReady = allTemplates.isNotEmpty;
        _hasLicense = sel.licenseReady;
        _hasSeal = hasSeal;
        // workTypes 미충족 시 결핍 정보 보존 (readiness 안내용)
        _businessReadinessList = selWorkTypesReady
            ? []
            : checks
                .map((c) => _BizReadiness(
                      business: c.business,
                      workTypesReady: c.workTypes.isNotEmpty,
                      licenseReady: c.licenseReady,
                    ))
                .toList();
        if (_allPrerequisitesMet) _formUnlocked = true;
        _isLoading = false;
      });
      // [REPOST-R1] 사업장 확정 후 initialTO 자동 불러오기 (1회).
      // 성공 경로에서만 실행 — 미승인/빈 사업장 early-return은 여기 도달하지 않음.
      if (mounted &&
          widget.initialTO != null &&
          _selectedBusiness?.id == widget.initialTO!.businessId) {
        _loadDataFromTO(widget.initialTO!);
      }
    } catch (e) {
      debugPrint('❌ 사업장 로드 실패: $e');
      if (mounted) setState(() => _isLoading = false);
      if (mounted) ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
    }
  }

  /// 사전조건 화면에서 "다시 확인" 또는 준비 화면 복귀 시 재체크
  Future<void> _reCheckPrerequisites() async {
    if (_isLoading) return;
    if (_selectedBusiness == null) {
      await _loadMyBusinesses();
      return;
    }
    setState(() => _isLoading = true);
    try {
      // 업무유형: 선택된 사업장 기준 / 계약서: 전역 (모든 사업장 합산)
      final bizList =
          _myBusinesses.isNotEmpty ? _myBusinesses : [_selectedBusiness!];
      final allResults = await Future.wait([
        _firestoreService.getBusinessWorkTypes(_selectedBusiness!.id),
        ...bizList
            .map((b) => _contractTemplateService.getTemplates(b.id)),
      ]);
      if (!mounted) return;
      final workTypes = allResults[0] as List<BusinessWorkTypeModel>;
      final allTemplates = allResults
          .skip(1)
          .expand((r) => r as List<ContractTemplateModel>)
          .toList();
      // [5D.2A] license: 선택된 사업장의 canonical OR ownerId legacy — 호출자 uid 아님
      final bool hasLicense = await BusinessPostingReadiness
          .hasLicenseForBusiness(_selectedBusiness!);
      if (!mounted) return;
      final up = Provider.of<UserProvider>(context, listen: false);
      setState(() {
        _businessWorkTypes = workTypes;
        _workTypesReady = workTypes.isNotEmpty;
        _contractTemplatesReady = allTemplates.isNotEmpty;
        _hasLicense = hasLicense;
        _hasSeal = up.isSubAdmin
            ? true
            : (up.currentUser?.sealBase64?.isNotEmpty ?? false);
        if (_allPrerequisitesMet) {
          _formUnlocked = true;
          _businessReadinessList = [];
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 사전조건 재체크 실패: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        ToastHelper.showError('사전 조건 확인에 실패했습니다.');
      }
    }
  }

  // 드롭다운으로 사업장 변경 시 업무목록 + 계약서 템플릿 재로드
  // 사업장 전환 시 업무목록만 재로드 (계약서 템플릿은 전역 — _reCheckPrerequisites에서 관리)
  Future<void> _loadWorkTypes() async {
    final biz = _selectedBusiness;
    if (biz == null) return;
    try {
      final workTypes = await _firestoreService
          .getBusinessWorkTypes(biz.id);
      if (!mounted || _selectedBusiness?.id != biz.id) return;
      setState(() {
        _businessWorkTypes = workTypes;
        _workTypesReady = workTypes.isNotEmpty;
        if (workTypes.isEmpty) _workDetails.clear();
      });
      if (workTypes.isEmpty) {
        ToastHelper.showWarning(
            '이 사업장에 등록된 업무목록이 없습니다.\n업무목록을 먼저 추가해주세요.');
      }
    } catch (e) {
      debugPrint('❌ 사업장 정보 로드 실패: $e');
      if (mounted) ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
    }
  }

  // ============================================================
  // 기존 공고 불러오기
  // ============================================================

  Future<void> _showLoadFromExistingDialog() async {
    if (_selectedBusiness == null) {
      ToastHelper.showWarning('먼저 사업장을 선택해주세요');
      return;
    }

    final rootNav = Navigator.of(context, rootNavigator: true);
    DialogHelper.showLoading(context, message: '공고 목록 불러오는 중...');

    try {
      _recentTOsForLoad = await _firestoreService.getTOsByBusiness(
        _selectedBusiness!.id,
        limit: 30,
      );
    } catch (e) {
      debugPrint('❌ TO 목록 로드 실패: $e');
      if (mounted) ToastHelper.showError('공고 목록을 불러올 수 없습니다');
      return;
    } finally {
      if (rootNav.mounted && rootNav.canPop()) rootNav.pop();
    }

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final selectedTO = await DialogHelper.showSheet<TOModel>(
      context,
      isScrollControlled: true,
      builder: (_) => _buildLoadFromExistingSheet(),
    );

    if (selectedTO != null && mounted) {
      _loadDataFromTO(selectedTO);
    }
  }

  void _loadDataFromTO(TOModel to) {
    setState(() {
      _titleController.text = to.title;
      _groupTitleController.text = to.groupTitle ?? '';
      _descriptionController.text = to.description ?? '';
      _hoursBeforeStart = to.hoursBeforeStart ?? 2;
      // 단기/장기 타입 동기화
      _selectedJobType = to.type;
      // 장기(contract) 계약 필드 복원 (날짜는 과거이므로 제외, 구조만 복원)
      if (to.type == 'contract') {
        _contractPeriodType = to.contractPeriodType;
        _selectedWeekdays
          ..clear()
          ..addAll(to.workDays);
        // rangeStart/rangeEnd는 과거값이므로 복사하지 않음 (새 공고에 맞게 직접 입력)
      } else {
        _contractPeriodType = null;
        _selectedWeekdays.clear();
        _selectedDates.clear();
      }
      _workDetails.clear();
      for (final work in to.workDetails) {
        _workDetails.add(WorkDetailInput(
          workType: work.workType,
          workTypeIcon: work.workTypeIcon,
          workTypeColor: work.workTypeColor,
          workTypeBackgroundColor: work.workTypeBackgroundColor,
          wage: work.wage,
          wageType: work.wageType,
          requiredCount: work.requiredCount,
          startTime: work.startTime,
          endTime: work.endTime,
          shiftType: work.shiftType,
          nightAllowanceApplied: work.nightAllowanceApplied,
          nightIncluded: work.nightIncluded,
          breakMinutes: work.breakMinutes,
          baseHourlyWage: work.baseHourlyWage,
          payScheduleType: work.payScheduleType,
          payScheduleDay: work.payScheduleDay,
          payScheduleTime: work.payScheduleTime,
          taxDeductionType: work.taxDeductionType,
          description: work.description,
        ));
      }
    });
    ToastHelper.showSuccess('공고 정보를 불러왔습니다');
  }

  /// 기존 공고 불러오기 — 바텀시트 버전 (DialogHelper.showSheet 전용)
  Widget _buildLoadFromExistingSheet() {
    String searchQuery = '';
    return StatefulBuilder(
      builder: (context, setSheetState) {
        final theme = Theme.of(context);
        // MEDIUM-2: searchQuery를 소문자로 보관 → 항목마다 toLowerCase() 호출 1회 절감
        final filteredTOs = searchQuery.isEmpty
            ? _recentTOsForLoad
            : _recentTOsForLoad
                .where((to) => to.title.toLowerCase().contains(searchQuery))
                .toList();

        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.72,
          child: Column(
            children: [
              // 시트 헤더
              Padding(
                padding: EdgeInsets.fromLTRB(
                  ResponsiveHelper.spacing(context, 20),
                  ResponsiveHelper.spacing(context, 16),
                  ResponsiveHelper.spacing(context, 8),
                  ResponsiveHelper.spacing(context, 8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.file_copy_outlined,
                        color: theme.primaryColor,
                        size: ResponsiveHelper.iconSize(context, 22)),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text('기존 공고 불러오기',
                          style: ResponsiveHelper.subtitleStyle(context)
                              .copyWith(fontWeight: FontWeight.bold)),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      iconSize: ResponsiveHelper.iconSize(context, 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
              ),
              // 검색창
              Padding(
                padding: EdgeInsets.fromLTRB(
                  ResponsiveHelper.spacing(context, 16),
                  0,
                  ResponsiveHelper.spacing(context, 16),
                  ResponsiveHelper.spacing(context, 8),
                ),
                child: TextField(
                  decoration: InputDecoration(
                    hintText: '공고 제목 검색...',
                    prefixIcon: Icon(Icons.search,
                        size: ResponsiveHelper.iconSize(context, 20)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: ResponsiveHelper.spacing(context, 16),
                      vertical: ResponsiveHelper.spacing(context, 12),
                    ),
                  ),
                  style: ResponsiveHelper.bodyStyle(context),
                  onChanged: (v) =>
                      setSheetState(() => searchQuery = v.toLowerCase()),
                ),
              ),
              // 목록
              Expanded(
                child: filteredTOs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_outlined,
                                size: ResponsiveHelper.iconSize(context, 48),
                                color: AppColors.grey400),
                            SizedBox(
                                height: ResponsiveHelper.spacing(context, 12)),
                            Text(
                              searchQuery.isEmpty
                                  ? '등록된 공고가 없습니다'
                                  : '검색 결과가 없습니다',
                              style: ResponsiveHelper.bodyStyle(context,
                                  color: AppColors.grey600),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 12)),
                        itemCount: filteredTOs.length,
                        separatorBuilder: (_, __) =>
                            const Divider(height: 1, color: AppColors.divider),
                        itemBuilder: (ctx, index) =>
                            _buildTOListTile(filteredTOs[index], ctx),
                      ),
              ),
              // D: 정확한 안내 텍스트
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                color: AppColors.grey100,
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: ResponsiveHelper.iconSize(context, 16),
                        color: AppColors.grey600),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Expanded(
                      child: Text(
                        '공고 제목·관리용 카드명·공통 안내·근무유형·요일·업무 설정을 불러옵니다. 날짜와 공개 설정은 포함되지 않습니다.',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey600),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTOListTile(TOModel to, BuildContext ctx) {
    final isFlexNoRange = to.isFlexType && to.rangeStart == null;
    final displayDate = to.rangeStart ?? to.createdAt;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(ctx, to),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(ctx, 4),
            vertical: ResponsiveHelper.spacing(ctx, 12),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(ctx, 10),
                  vertical: ResponsiveHelper.spacing(ctx, 6),
                ),
                decoration: BoxDecoration(
                  color: to.isContractType
                      ? AppColors.longTermBg
                      : Theme.of(ctx).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isFlexNoRange
                      ? '${to.totalSlots}일'
                      : DateFormat('MM/dd').format(displayDate),
                  style: ResponsiveHelper.smallStyle(
                    ctx,
                    color: to.isContractType
                        ? AppColors.longTermDark
                        : Theme.of(ctx).primaryColor,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(ctx, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      to.title,
                      style: ResponsiveHelper.bodyStyle(ctx)
                          .copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(ctx, 2)),
                    Row(
                      children: [
                        // [단기] / [고정] 배지 — 항상 표시
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(ctx, 5),
                            vertical: ResponsiveHelper.spacing(ctx, 2),
                          ),
                          decoration: BoxDecoration(
                            color: to.isContractType
                                ? AppColors.longTermBg
                                : Theme.of(ctx)
                                    .primaryColor
                                    .withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            to.isContractType ? '고정' : '단기',
                            style: ResponsiveHelper.tinyStyle(
                              ctx,
                              color: to.isContractType
                                  ? AppColors.longTermDark
                                  : Theme.of(ctx).primaryColor,
                            ).copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(ctx, 6)),
                        Icon(Icons.people_outline,
                            size: ResponsiveHelper.iconSize(ctx, 12),
                            color: AppColors.grey500),
                        SizedBox(width: ResponsiveHelper.spacing(ctx, 4)),
                        Text('${to.totalRequired}명',
                            style: ResponsiveHelper.tinyStyle(ctx,
                                color: AppColors.grey600)),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppColors.grey400,
                  size: ResponsiveHelper.iconSize(ctx, 20)),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // 업무 상세 관리
  // ============================================================

  Future<void> _showAddWorkDetailDialog() async {
    if (_selectedBusiness == null) {
      ToastHelper.showWarning('사업장을 먼저 선택해주세요');
      return;
    }
    if (_businessWorkTypes.isEmpty) {
      ToastHelper.showWarning('업무 유형을 먼저 등록해주세요');
      return;
    }

    final result = await WorkDetailDialog.showAddDialog(
      context: context,
      businessWorkTypes: _businessWorkTypes,
    );

    if (result != null && mounted) {
      final isDuplicate = _workDetails.any((w) =>
          w.workType == result.workType &&
          w.startTime == result.startTime &&
          w.endTime == result.endTime);
      if (isDuplicate) {
        ToastHelper.showWarning('동일한 업무·시간대가 이미 추가되어 있습니다');
        return;
      }
      setState(() { _workDetails.add(result); _hasChanges = true; });
    }
  }

  Future<void> _editWorkDetail(int index) async {
    final detail = _workDetails[index];
    if (!detail.isValid) return;

    final tempData = WorkDetailData(
      workType: detail.workType!,
      workTypeIcon: detail.workTypeIcon,
      workTypeColor: detail.workTypeColor,
      workTypeBackgroundColor: detail.workTypeBackgroundColor ?? '#E3F2FD',
      wage: detail.wage!,
      wageType: detail.wageType,
      requiredCount: detail.requiredCount!,
      startTime: detail.startTime!,
      endTime: detail.endTime!,
      shiftType: detail.shiftType,
      nightAllowanceApplied: detail.nightAllowanceApplied,
      nightIncluded: detail.nightIncluded,
      breakMinutes: detail.breakMinutes,
      baseHourlyWage: detail.baseHourlyWage,
      payScheduleType: detail.payScheduleType,
      payScheduleDay: detail.payScheduleDay,
      payScheduleTime: detail.payScheduleTime,
      taxDeductionType: detail.taxDeductionType,
      description: detail.description,
    );

    final result = await WorkDetailDialog.showEditDialog(
      context: context,
      work: tempData,
      businessWorkTypes: _businessWorkTypes,
    );

    if (result != null && mounted) {
      setState(() {
        _workDetails[index] = WorkDetailInput(
          workType: result['workType'] ?? detail.workType,
          workTypeIcon: result['workTypeIcon'] ?? detail.workTypeIcon,
          workTypeColor: result['workTypeColor'] ?? detail.workTypeColor,
          workTypeBackgroundColor:
              result['workTypeBackgroundColor'] ?? detail.workTypeBackgroundColor,
          wage: result['wage'],
          wageType: result['wageType'],
          requiredCount: result['requiredCount'],
          startTime: result['startTime'],
          endTime: result['endTime'],
          shiftType: result['shiftType'],
          nightAllowanceApplied: result['nightAllowanceApplied'] ?? true,
          nightIncluded: result['nightIncluded'] ?? false,
          breakMinutes: result['breakMinutes'] ?? 0,
          baseHourlyWage: result['baseHourlyWage'],
          payScheduleType: result['payScheduleType'],
          payScheduleDay: result['payScheduleDay'],
          payScheduleTime: result['payScheduleTime'],
          taxDeductionType: result['taxDeductionType'] ?? detail.taxDeductionType,
          description: result['description'],
        );
        _hasChanges = true;
      });
    }
  }

  void _removeWorkDetail(int index) {
    setState(() {
      _workDetails.removeAt(index);
      _hasChanges = true;
    });
  }

  // ============================================================
  // 날짜 / 요일 선택
  // ============================================================

  void _onDateToggle(DateTime date) {
    setState(() {
      final normalized = DateTime.utc(date.year, date.month, date.day);
      if (_selectedDates.any((d) => _isSameDay(d, normalized))) {
        _selectedDates.removeWhere((d) => _isSameDay(d, normalized));
      } else {
        _selectedDates.add(normalized);
        _selectedDates.sort();
      }
      _hasChanges = true;
    });
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _clearAllDates() {
    setState(() => _selectedDates.clear());
  }

  void _onWeekdayToggle(String day) {
    setState(() {
      if (_selectedWeekdays.contains(day)) {
        _selectedWeekdays.remove(day);
      } else {
        _selectedWeekdays.add(day);
      }
      _hasChanges = true;
    });
  }

  Future<void> _onJobTypeChanged(String newType) async {
    if (newType == _selectedJobType) return;

    // 날짜/기간 데이터가 입력된 상태에서 유형 변경 시 초기화 경고
    final hasScheduleData = _selectedDates.isNotEmpty ||
        _selectedWeekdays.isNotEmpty ||
        _rangeStart != null;
    if (hasScheduleData) {
      final confirmed = await DialogHelper.showConfirm(
        context,
        title: '근무 유형 변경',
        message: '유형을 변경하면 입력한 날짜/기간 정보가 초기화됩니다.\n계속하시겠습니까?',
        confirmText: '변경',
        cancelText: '취소',
      );
      if (!confirmed || !context.mounted) return;
    }

    setState(() {
      _hasChanges = true;
      _selectedJobType = newType;
      _selectedDates.clear();
      _selectedWeekdays.clear();
      _rangeStart = null;
      _rangeEnd = null;
      _contractPeriodType = null;
      _workStartAvailableFrom = null;
      _workStartAvailableUntil = null;
      _postingDurationDays = 7;
      _publishMode = 'immediate';
      _publishDaysBefore = 1;
      _publishTime = '14:00';
    });
  }

  // ============================================================
  // TO 생성
  // ============================================================

  /// 날짜 하나가 이미 마감시간 지났는지 확인
  bool _isSlotExpired(DateTime date) {
    final now = DateTime.now();
    final today = FormatHelper.toKstDate(now);
    final dateOnly = FormatHelper.toKstDate(date);

    // 어제 이전 날짜는 무조건 만료
    if (dateOnly.isBefore(today)) return true;

    // 오늘 날짜: 업무별 마감시각 확인
    if (dateOnly != today) return false;
    if (_workDetails.isEmpty) return false;
    return _workDetails.every((w) {
      final start = w.startTime;
      if (start == null) return false;
      final parts = start.split(':');
      if (parts.length != 2) return false;
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h == null || m == null) return false;
      final deadline = DateTime(
        date.year, date.month, date.day, h, m,
      ).subtract(Duration(hours: _hoursBeforeStart));
      return now.isAfter(deadline);
    });
  }

  /// 모든 선택 날짜가 마감 경과 → 등록 즉시 전체 마감됨
  bool get _allSlotsExpired => _selectedDates.isNotEmpty && _selectedDates.every(_isSlotExpired);

  /// 일부 날짜만 마감 경과 (오늘 포함 2일 이상 공고에서 오늘만 만료)
  bool get _someSlotExpired => !_allSlotsExpired && _selectedDates.any(_isSlotExpired);

  Future<void> _createTO() async {
    if (_isCreating) return;
    // 키보드 닫기 — IME animation과 setState rebuild 타이밍 충돌 방지
    FocusScope.of(context).unfocus();
    setState(() => _isCreating = true);
    try {
    await Future.microtask(() {});
    if (!mounted) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_titleController.text.trim().isEmpty) {
      _scrollToSection(_titleSectionKey);
      ToastHelper.showError('제목을 입력해주세요');
      return;
    }

    if (_selectedBusiness == null) {
      _scrollToSection(_businessSectionKey);
      ToastHelper.showError('사업장을 선택해주세요');
      return;
    }

    if (_businessWorkTypes.isEmpty) {
      _scrollToSection(_businessSectionKey);
      ToastHelper.showError('업무목록을 먼저 등록해주세요.\n사업장 설정에서 업무목록을 추가할 수 있습니다.');
      return;
    }

    // LOW-2: DateTime.now()를 메서드 진입 시점에 한 번만 캡처
    final now = DateTime.now();
    final todayOnly = FormatHelper.toKstDate(now);

    if (_selectedJobType == TOType.flex) {
      if (_selectedDates.isEmpty) {
        _scrollToSection(_dateSectionKey);
        ToastHelper.showError('날짜를 선택해주세요');
        return;
      }
      // 과거 날짜 포함 여부 경고 — _someSlotExpired 조건과 독립적으로 항상 표시
      final hasPastDate = _selectedDates.any((d) => d.isBefore(todayOnly));
      if (hasPastDate && !_allSlotsExpired) {
        ToastHelper.showWarning('과거 날짜가 포함되어 있습니다. 해당 날짜는 즉시 마감됩니다');
      }
    } else {
      if (_contractPeriodType == null) {
        _scrollToSection(_dateSectionKey);
        ToastHelper.showError('계약 기간을 선택해주세요');
        return;
      }
      if (_contractPeriodType == 'custom' && (_rangeStart == null || _rangeEnd == null)) {
        _scrollToSection(_dateSectionKey);
        ToastHelper.showError('계약 시작일과 종료일을 설정해주세요');
        return;
      }
      if (_contractPeriodType == 'custom' &&
          _rangeStart != null && _rangeEnd != null &&
          _rangeStart!.isAfter(_rangeEnd!)) {
        _scrollToSection(_dateSectionKey);
        ToastHelper.showError('계약 시작일이 종료일보다 이후일 수 없습니다');
        return;
      }
      if (_contractPeriodType == 'custom' && _rangeEnd != null) {
        if (_rangeEnd!.isBefore(todayOnly)) {
          ToastHelper.showWarning('계약 종료일이 과거 날짜입니다. 즉시 마감 처리됩니다');
        }
      }
      // [D-3 수정] custom 기간에서 rangeStart가 과거 날짜인 경우 경고
      // 저장 자체는 허용하나 관리자에게 의도 재확인 유도
      if (_contractPeriodType == 'custom' && _rangeStart != null) {
        if (_rangeStart!.isBefore(todayOnly)) {
          ToastHelper.showWarning('계약 시작일이 과거 날짜입니다. 게시 즉시 활성 상태로 시작됩니다');
        }
      }
      // preset 장기공고: 근무 시작 가능기간 필수
      if (_contractPeriodType != null && _contractPeriodType != 'custom') {
        if (_workStartAvailableFrom == null || _workStartAvailableUntil == null) {
          _scrollToSection(_dateSectionKey);
          ToastHelper.showError('근무 시작 가능기간을 설정해주세요');
          return;
        }
        if (_workStartAvailableFrom!.isAfter(_workStartAvailableUntil!)) {
          _scrollToSection(_dateSectionKey);
          ToastHelper.showError('시작 가능기간의 시작일이 종료일보다 이후일 수 없습니다');
          return;
        }
        // 전체 기간이 과거인 경우 차단
        if (_workStartAvailableUntil!.isBefore(todayOnly)) {
          _scrollToSection(_dateSectionKey);
          ToastHelper.showError('근무 시작 가능기간이 모두 과거입니다. 종료일을 오늘 이후로 설정해주세요');
          return;
        }
      }
      if (_selectedWeekdays.isEmpty) {
        _scrollToSection(_dateSectionKey);
        ToastHelper.showError('근무 요일을 선택해주세요');
        return;
      }
    }

    if (_workDetails.isEmpty) {
      _scrollToSection(_workDetailSectionKey);
      ToastHelper.showError('최소 1개의 업무를 추가해주세요');
      return;
    }

    if (_workDetails.any((w) => !w.isValid)) {
      _scrollToSection(_workDetailSectionKey);
      ToastHelper.showError('모든 업무 정보를 입력해주세요');
      return;
    }

    if (_workDetails.any((w) => (w.wage ?? 0) <= 0)) {
      _scrollToSection(_workDetailSectionKey);
      ToastHelper.showError('급여는 0원보다 커야 합니다');
      return;
    }
    // 최저임금(2026: 10,320원) 미달 여부를 앱에서 하드 차단하지 않는다.
    // 임금 결정은 사업주 권한이며, 수습·단순가산 등 예외 케이스가 다양하다.
    // 최저임금법 준수 책임은 사업주에게 있고, 앱은 경영 도구로서 개입하지 않는다.

    if (_workDetails.any((w) => (w.wage ?? 0) > 50000000)) {
      _scrollToSection(_workDetailSectionKey);
      ToastHelper.showError('급여는 5,000만원 이하여야 합니다');
      return;
    }

    if (_workDetails.any((w) => (w.requiredCount ?? 0) <= 0)) {
      ToastHelper.showError('필요 인원은 1명 이상이어야 합니다');
      return;
    }

    if (_workDetails.any((w) => (w.requiredCount ?? 0) > 10000)) {
      ToastHelper.showError('필요 인원은 10,000명 이하여야 합니다');
      return;
    }

    // 사업주 날인 미등록 차단 — 근로계약서 서명에 필요 (BUSINESS_ADMIN 전용)
    // SubAdmin은 날인이 없음: 계약서 서명 날인은 사업주(BUSINESS_ADMIN) 계정 기준으로 CF에서 처리
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;
    if (!userProvider.isSubAdmin) {
      if (uid != null) {
        // sealBase64는 users/{uid} 문서에만 저장 — businesses 문서 폴백 불필요
        final userDoc = await FirebaseFirestore.instance
            .collection('users').doc(uid).get();
        if (!mounted) return;
        final String? sealBase64 = userDoc.data()?['sealBase64'] as String?;

        if (sealBase64 == null || sealBase64.isEmpty) {
          final goToSettings = await DialogHelper.showConfirm(
            context,
            title: '사업주 날인 미등록',
            message: '근로계약서 서명을 위해 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 이미지 또는 서명을 먼저 등록해주세요.',
            confirmText: '설정으로 이동',
            cancelText: '취소',
          );
          if (!mounted) return;
          if (goToSettings) {
            await NavigationHelper.push<void>(context, destination: const SettingsScreen());
          }
          return;
        }
      }
    }

      // flex 당일 슬롯 마감 경과 처리
      if (_selectedJobType == TOType.flex) {
        if (_allSlotsExpired) {
          // 전체 날짜 만료 → 강한 경고 (팝업)
          final proceed = await DialogHelper.showConfirm(
            context,
            title: '지원 마감 경과',
            message: '선택한 모든 날짜의 지원 마감이 이미 지났습니다.\n등록 즉시 마감 상태가 됩니다.\n그래도 등록하시겠습니까?',
            confirmText: '등록',
            cancelText: '취소',
          );
          if (!proceed || !mounted) return;
        } else if (_someSlotExpired) {
          // 일부 날짜만 만료 → 토스트 안내 후 그대로 진행
          ToastHelper.showInfo('오늘 날짜 슬롯은 마감시간이 지나 등록 즉시 마감됩니다');
        }
      }

      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        return;
      }

      final workDetailList = _workDetails
          .asMap()
          .entries
          .map((e) => WorkDetailData(
                workType: e.value.workType!,
                workTypeIcon: e.value.workTypeIcon,
                workTypeColor: e.value.workTypeColor,
                workTypeBackgroundColor:
                    e.value.workTypeBackgroundColor ?? '#E3F2FD',
                wage: e.value.wage!,
                wageType: e.value.wageType,
                requiredCount: e.value.requiredCount!,
                startTime: e.value.startTime!,
                endTime: e.value.endTime!,
                shiftType: e.value.shiftType,
                nightAllowanceApplied: e.value.nightAllowanceApplied,
                nightIncluded: e.value.nightIncluded,
                breakMinutes: e.value.breakMinutes,
                baseHourlyWage: e.value.baseHourlyWage,
                payScheduleType: e.value.payScheduleType,
                payScheduleDay: e.value.payScheduleDay,
                payScheduleTime: e.value.payScheduleTime,
                taxDeductionType: e.value.taxDeductionType,
                description: e.value.description,
                order: e.key,
              ))
          .toList();

      final toId = await _firestoreService.createTO(
        businessId: _selectedBusiness!.id,
        businessName: _selectedBusiness!.name,
        title: _titleController.text.trim(),
        groupTitle: _groupTitleController.text.trim().isNotEmpty
            ? _groupTitleController.text.trim()
            : null,
        description: _descriptionController.text.trim(),
        type: _selectedJobType,
        workDetails: workDetailList,
        creatorUID: uid,
        // flex 전용
        dates: _selectedJobType == TOType.flex ? _selectedDates : null,
        deadlineType: 'HOURS_BEFORE',
        hoursBeforeStart: _hoursBeforeStart,
        // contract 전용
        // 비-custom 계약기간은 rangeStart가 null일 수 있음 → 오늘로 기본값 (시간 제거)
        rangeStart: _selectedJobType == TOType.contract
            ? () {
                final d = _rangeStart ?? DateTime.now();
                // [TZ-FIX] DateTime(y,m,d)는 기기 로컬 자정 → UTC+12에서 epoch = 하루 이전 21:00 KST
                // DateTime.utc(y,m,d,-9,0) = KST 00:00 UTC epoch (Dart가 -9h → 전날 15:00 UTC로 정규화)
                return DateTime.utc(d.year, d.month, d.day, -9, 0);
              }()
            : null,
        // [TZ-FIX] rangeEnd/workStartAvailable* 동일 패턴 — KST 자정 UTC 기준으로 저장
        rangeEnd: _selectedJobType == TOType.contract && _contractPeriodType == 'custom' && _rangeEnd != null
            ? DateTime.utc(_rangeEnd!.year, _rangeEnd!.month, _rangeEnd!.day, -9, 0)
            : null,
        workDays: _selectedJobType == TOType.contract ? _selectedWeekdays : null,
        contractDeadline: null,
        contractPeriodType: _selectedJobType == TOType.contract ? _contractPeriodType : null,
        postingDurationDays: _postingDurationDays, // flex·contract 모두 저장
        workStartAvailableFrom: _selectedJobType == TOType.contract && _workStartAvailableFrom != null
            ? DateTime.utc(_workStartAvailableFrom!.year, _workStartAvailableFrom!.month, _workStartAvailableFrom!.day, -9, 0)
            : null,
        workStartAvailableUntil: _selectedJobType == TOType.contract && _workStartAvailableUntil != null
            ? DateTime.utc(_workStartAvailableUntil!.year, _workStartAvailableUntil!.month, _workStartAvailableUntil!.day, -9, 0)
            : null,
        // 공개 설정 (draft = 미공개 저장, scheduled = 예약공개, immediate = 즉시공개)
        publishMode: _publishMode,
        publishDaysBefore: _publishMode == 'scheduled' ? _publishDaysBefore : null,
        publishTime: _publishMode == 'scheduled' ? _publishTime : null,
      );

      if (toId != null && mounted) {
        final isDraft = _publishMode == 'draft';
        final label = isDraft
            ? '미공개로 저장되었습니다 (나중에 직접 공개하세요)'
            : _selectedJobType == TOType.contract
                ? '고정 근무 공고가 등록되었습니다'
                : _selectedDates.length > 1
                    ? '${_selectedDates.length}일 공고가 등록되었습니다'
                    : '공고가 등록되었습니다';
        ToastHelper.showSuccess(label);
        AnalyticsService.logTOCreate(toType: _selectedJobType);
        NavigationHelper.popWithChange(context);
      } else if (mounted) {
        ToastHelper.showError('공고 등록에 실패했습니다');
      }
    } catch (e) {
      debugPrint('❌ TO 생성 실패: $e');
      if (mounted) {
        final msg = e.toString();
        if (msg.contains('MAX_ACTIVE_TO_LIMIT')) {
          // 서버가 'MAX_ACTIVE_TO_LIMIT:N' 형태로 반환
          final parts = msg.split(':');
          final limitStr = parts.length >= 2 ? parts.last.trim() : '4';
          ToastHelper.showError('진행중인 공고가 최대 $limitStr개입니다.\n기존 공고를 마감 후 새 공고를 등록해주세요.');
        } else if (e is FirebaseFunctionsException && e.code == 'failed-precondition') {
          // [5D.1A] 사업장 readiness 서버 gate — 서버 메시지 직접 표시
          final serverMsg = e.message ?? '공고 등록 조건을 확인해 주세요.';
          ToastHelper.showError(serverMsg);
        } else {
          ToastHelper.showError('공고 등록에 실패했습니다');
        }
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  // ============================================================
  // UI 빌드
  // ============================================================

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          title: Text(
            '공고 등록',
            style: ResponsiveHelper.subtitleStyle(context)
                .copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          actions: [
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
          ],
        ),
        body: const LoadingWidget(),
      );
    }

    if (!_formUnlocked) {
      return _buildPrerequisiteScreen();
    }

    return PopScope(
      canPop: !_isCreating && !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        // [M1-FIX] 등록 진행 중(_isCreating)에는 다이얼로그 없이 즉시 차단
        if (didPop || _isCreating || !_hasChanges) return;
        final leave = await DialogHelper.showConfirm(
          context,
          title: '입력 중인 내용이 있습니다',
          message: '공고 등록을 취소하시겠습니까?\n입력한 내용이 모두 사라집니다.',
          confirmText: '나가기',
          cancelText: '계속 작성',
        );
        if (leave && context.mounted) Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          centerTitle: false,
          title: Text(
            '공고 등록',
            style: ResponsiveHelper.subtitleStyle(context)
                .copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          // B: 아이콘 전용 → TextButton.icon "불러오기"
          actions: [
            Padding(
              padding: EdgeInsets.only(
                  right: ResponsiveHelper.spacing(context, 8)),
              child: TextButton.icon(
                onPressed: _selectedBusiness != null
                    ? _showLoadFromExistingDialog
                    : null,
                icon: const Icon(Icons.file_copy_outlined),
                label: const Text('불러오기'),
              ),
            ),
            NotificationBadge(
              child: IconButton(
                icon: const Icon(Icons.notifications_outlined),
                color: AppColors.textSecondary,
                // [M1-FIX] 등록 진행 중에는 다른 화면 이동 차단
                onPressed: _isCreating
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => const NotificationScreen()),
                        ),
                tooltip: '알림',
              ),
            ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            // G: CTA가 bottomNavigationBar로 이동 → 하단 여유 확보
            padding: ResponsiveHelper.listPadding(context)
                .copyWith(bottom: ResponsiveHelper.spacing(context, 108)),
            children: [
              // [UI-COMPACT] 사업장 + 근무 유형 통합 카드 (카드 2개 → 1개)
              KeyedSubtree(
                key: _businessSectionKey,
                child: _buildBusinessAndTypeSection(),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),

              // [UI-COMPACT] 공고 제목 + 카드 제목 통합 카드 (카드 2개 → 1개)
              KeyedSubtree(
                key: _titleSectionKey,
                child: _buildTitleAndGroupSection(),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),

              KeyedSubtree(
                key: _dateSectionKey,
                child: _buildDateSelector(),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),

              KeyedSubtree(
                key: _workDetailSectionKey,
                child: TOWorkDetailsSection(
                  workDetailInputs: _workDetails,
                  onAddWork: _showAddWorkDetailDialog,
                  onEditWorkByIndex: _editWorkDetail,
                  onRemoveWorkByIndex: _removeWorkDetail,
                  showNoWorkTypeWarning: _businessWorkTypes.isEmpty,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),

              // 단기(flex)만 지원마감 설정 — 고정근무(contract)는 게시기간이 곧 지원기간
              if (_selectedJobType != TOType.contract) ...[
                TODeadlineSection(
                  isLongTerm: false,
                  hoursBeforeStart: _hoursBeforeStart,
                  onHoursChanged: (h) => setState(() { _hoursBeforeStart = h; _hasChanges = true; }),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              ],

              TOPublishSection(
                publishMode: _publishMode,
                onPublishModeChanged: (m) => setState(() { _publishMode = m; _hasChanges = true; }),
                publishDaysBefore: _publishDaysBefore,
                onDaysBeforeChanged: (d) => setState(() { _publishDaysBefore = d; _hasChanges = true; }),
                publishTime: _publishTime,
                onTimeChanged: (t) => setState(() { _publishTime = t; _hasChanges = true; }),
                previewDates: _selectedJobType == TOType.contract
                    ? (_rangeStart != null ? [_rangeStart!] : [])
                    : _selectedDates,
                isLongTerm: _selectedJobType == TOType.contract,
                postingDurationDays: _postingDurationDays,
                onPostingDurationChanged: (d) => setState(() { _postingDurationDays = d; _hasChanges = true; }),
                rangeEnd: _selectedJobType == TOType.contract ? _rangeEnd : null,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),

              TODescriptionSection(controller: _descriptionController),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            ],
          ),
        ),
        // G: CTA → Scaffold.bottomNavigationBar (SafeArea(top: false) 필수)
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 8),
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 16),
            ),
            child: TOActionButton.create(
              onPressed: _isCreating ? null : _createTO,
              isLoading: _isCreating,
            ),
          ),
        ),
      ),
    );     // PopScope
  }

  /// 공고 등록 사전조건 체크 화면 — 3가지를 한 번에 보여줌
  Widget _buildPrerequisiteScreen() {
    final theme = Theme.of(context);
    final isSubAdmin =
        context.read<UserProvider>().isSubAdmin;
    // [AUTHZ.2] canManageContract — OWNER는 항상 true, SUB_ADMIN은 권한 확인
    final canManageContract =
        !isSubAdmin || context.read<UserProvider>().can((p) => p.canManageContract);
    final cardCount = isSubAdmin ? 4 : 5;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        title: Text(
          '공고 등록',
          style: ResponsiveHelper.subtitleStyle(context)
              .copyWith(fontWeight: FontWeight.w700, color: AppColors.textPrimary),
        ),
        actions: [
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
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 안내 헤더
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
              decoration: BoxDecoration(
                color: theme.primaryColor.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.checklist_rounded,
                      color: theme.primaryColor,
                      size: ResponsiveHelper.iconSize(context, 28)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('공고 등록 전 준비사항',
                            style: ResponsiveHelper.subtitleStyle(context)
                                .copyWith(fontWeight: FontWeight.bold)),
                        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                        Text('아래 $cardCount가지를 모두 완료해야 공고를 등록할 수 있습니다.',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.grey600)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(height: ResponsiveHelper.spacing(context, 20)),

            // 멀티 사업장 결핍 현황 (어느 사업장도 미충족인 경우)
            if (_businessReadinessList.length > 1) ...[
              _buildBusinessDeficitCard(),
              SizedBox(height: ResponsiveHelper.spacing(context, 20)),
            ],

            // ① 사업장 등록 & 승인
            // [PH-READINESS-A] SUB_ADMIN은 사업장 자체를 등록할 수 없으므로 CTA 제거
            _buildPrerequisiteCard(
              index: 1,
              title: '사업장 등록 & 승인',
              isReady: _businessApproved,
              readyDescription: '승인된 사업장이 있습니다',
              notReadyDescription: isSubAdmin
                  ? (_hasAnyBusiness
                      ? '사업장이 아직 승인되지 않았습니다.\n사업장 관리자에게 문의해주세요.'
                      : '관리 중인 사업장이 없습니다.\n사업장 관리자에게 문의해주세요.')
                  : (_hasAnyBusiness
                      ? '사업장이 아직 승인되지 않았습니다.\n관리자 승인을 기다려주세요.'
                      : '사업장이 등록되어 있지 않습니다.'),
              actionLabel: isSubAdmin ? null : (_hasAnyBusiness ? null : '사업장 등록하기'),
              onAction: isSubAdmin
                  ? null
                  : (_hasAnyBusiness
                      ? null
                      : () async {
                          await NavigationHelper.push<void>(context,
                              destination: const BusinessFormScreen());
                          if (!mounted) return;
                          await _loadMyBusinesses();
                        }),
            ),

            SizedBox(height: ResponsiveHelper.spacing(context, 12)),

            // ② 업무목록
            _buildPrerequisiteCard(
              index: 2,
              title: '업무목록 등록',
              isReady: _workTypesReady,
              readyDescription: '업무목록이 등록되어 있습니다',
              notReadyDescription: _businessApproved
                  ? '등록된 업무목록이 없습니다.'
                  : '사업장 승인 후 확인 가능합니다.',
              actionLabel: _businessApproved ? '업무목록 관리' : null,
              onAction: _businessApproved
                  ? () async {
                      await NavigationHelper.push<void>(context,
                          destination: WorkTypeManagementScreen(
                            businessId: _selectedBusiness!.id,
                            businessName: _selectedBusiness!.name,
                          ));
                      if (!mounted) return;
                      await _reCheckPrerequisites();
                    }
                  : null,
            ),

            SizedBox(height: ResponsiveHelper.spacing(context, 12)),

            // ③ 계약서 템플릿
            // [AUTHZ.2] SUB_ADMIN canManageContract=false → CTA 제거, 관리자 요청 안내
            _buildPrerequisiteCard(
              index: 3,
              title: '근로계약서 템플릿',
              isReady: _contractTemplatesReady,
              readyDescription: '계약서 템플릿이 등록되어 있습니다',
              notReadyDescription: !canManageContract
                  ? '근로계약서 템플릿 등록이 필요합니다.\n사업장 관리자에게 준비 완료를 요청해주세요.'
                  : (_businessApproved
                      ? '등록된 계약서 템플릿이 없습니다.'
                      : '사업장 승인 후 확인 가능합니다.'),
              actionLabel:
                  canManageContract && _businessApproved ? '계약서 관리' : null,
              onAction: canManageContract &&
                      _businessApproved &&
                      _selectedBusiness != null
                  ? () async {
                      await NavigationHelper.push<void>(
                        context,
                        destination: ContractTemplateListScreen(
                            businessId: _selectedBusiness!.id),
                      );
                      if (!mounted) return;
                      await _reCheckPrerequisites();
                    }
                  : null,
            ),

            SizedBox(height: ResponsiveHelper.spacing(context, 12)),

            // ④ 사업자등록증
            // [5D.2] CTA → BusinessFormScreen (canonical: businesses/{bizId}.businessLicenseImageUrl)
            // [PH-READINESS-A] SUB_ADMIN은 BusinessFormScreen 수정 권한 없음 → CTA 제거, owner 안내 문구
            _buildPrerequisiteCard(
              index: 4,
              title: '사업자등록증',
              isReady: _hasLicense,
              readyDescription: '사업자등록증이 등록되어 있습니다',
              notReadyDescription: isSubAdmin
                  ? '사업자등록증 등록이 필요합니다.\n사업장 관리자에게 준비 완료를 요청해주세요.'
                  : '사업자등록증 이미지를 등록해주세요.\n사업장 정보에서 업로드할 수 있습니다.',
              actionLabel: isSubAdmin
                  ? null
                  : (_businessApproved && _selectedBusiness != null
                      ? '사업장 정보로 이동'
                      : '설정으로 이동'),
              onAction: isSubAdmin
                  ? null
                  : () async {
                      await NavigationHelper.push<void>(
                        context,
                        destination: _businessApproved && _selectedBusiness != null
                            ? BusinessFormScreen(business: _selectedBusiness)
                            : const SettingsScreen(),
                      );
                      if (!mounted) return;
                      await _reCheckPrerequisites();
                    },
            ),

            // ⑤ 인감/서명 (SubAdmin 면제 — 비표시)
            if (!isSubAdmin) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              _buildPrerequisiteCard(
                index: 5,
                title: '인감/서명 등록',
                isReady: _hasSeal,
                readyDescription: '인감 또는 서명이 등록되어 있습니다',
                notReadyDescription: '계약서 날인을 위한 인감 또는 서명을 등록해주세요.\n설정 → 내 정보에서 등록할 수 있습니다.',
                actionLabel: '설정으로 이동',
                onAction: () async {
                  await NavigationHelper.push<void>(
                    context,
                    destination: const SettingsScreen(),
                  );
                  if (!mounted) return;
                  await _reCheckPrerequisites();
                },
              ),
            ],

            SizedBox(height: ResponsiveHelper.spacing(context, 32)),

            // 다시 확인 + 공고 등록하기 버튼
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _reCheckPrerequisites,
                    icon: const Icon(Icons.refresh),
                    label: const Text('다시 확인'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 14)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: _allPrerequisitesMet
                        ? () => setState(() => _formUnlocked = true)
                        : null,
                    icon: const Icon(Icons.edit_note),
                    label: const Text('공고 등록하기'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.grey300,
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 14)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessDeficitCard() {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.store_outlined,
                  color: AppColors.warning,
                  size: ResponsiveHelper.iconSize(context, 20)),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text('사업장별 준비 현황',
                  style: ResponsiveHelper.subtitleStyle(context)
                      .copyWith(fontWeight: FontWeight.bold)),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          ..._businessReadinessList.map((r) => Padding(
                padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(r.business.name,
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    _readinessChip(r.licenseReady, '사업자등록증'),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    _readinessChip(r.workTypesReady, '업무유형'),
                  ],
                ),
              )),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text('준비된 사업장이 없습니다. 아래 항목을 완료 후 "다시 확인"을 눌러주세요.',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey600)),
        ],
      ),
    );
  }

  Widget _readinessChip(bool ready, String label) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 2),
      ),
      decoration: BoxDecoration(
        color: ready
            ? AppColors.success.withValues(alpha: 0.12)
            : AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            ready ? Icons.check : Icons.close,
            size: ResponsiveHelper.iconSize(context, 12),
            color: ready ? AppColors.success : AppColors.error,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 2)),
          Text(label,
              style: ResponsiveHelper.smallStyle(context,
                  color: ready ? AppColors.successDark : AppColors.errorDark)),
        ],
      ),
    );
  }

  Widget _buildPrerequisiteCard({
    required int index,
    required String title,
    required bool isReady,
    required String readyDescription,
    required String notReadyDescription,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final theme = Theme.of(context);
    final color = isReady ? AppColors.success : AppColors.error;

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isReady
              ? AppColors.success.withValues(alpha: 0.3)
              : AppColors.grey300,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.grey500.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 상태 아이콘
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                isReady ? Icons.check_circle : Icons.radio_button_unchecked,
                color: color,
                size: ResponsiveHelper.iconSize(context, 22),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),

          // 텍스트
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('$index.',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey500)),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Flexible(
                      child: Text(title,
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  isReady ? readyDescription : notReadyDescription,
                  style: ResponsiveHelper.smallStyle(context,
                      color: isReady ? AppColors.successDark : AppColors.grey600),
                ),
              ],
            ),
          ),

          // 이동 버튼 (미완료 항목만)
          if (!isReady && actionLabel != null && onAction != null) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: theme.primaryColor,
                padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 10),
                    vertical: ResponsiveHelper.spacing(context, 6)),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel,
                      style: ResponsiveHelper.smallStyle(context,
                          color: theme.primaryColor,
                          fontWeight: FontWeight.bold)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                  Icon(Icons.arrow_forward_ios,
                      size: ResponsiveHelper.iconSize(context, 12),
                      color: theme.primaryColor),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// [UI-COMPACT] 사업장 + 근무 유형 통합 카드 (카드 2개 → 1개)
  Widget _buildBusinessAndTypeSection() {
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 사업장 선택
          AppSelectField<BusinessModel>(
            value: _selectedBusiness,
            hintText: '사업장을 선택하세요',
            sheetTitle: '사업장 선택',
            items: _myBusinesses,
            labelOf: (b) => b.name,
            prefixIcon: Icons.business,
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _selectedBusiness = value;
                  _workDetails.clear();
                  _hasChanges = true;
                });
                _loadWorkTypes();
              }
            },
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          const Divider(height: 1, thickness: 0.5),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          // 근무 유형
          Text('근무 유형',
              style: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold)),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          Row(
            children: [
              Expanded(
                child: _buildJobTypeChip(
                    label: '단기 근무', value: TOType.flex, icon: Icons.today),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 10)),
              Expanded(
                child: _buildJobTypeChip(
                    label: '고정 근무', value: TOType.contract, icon: Icons.event_note),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// [UI-COMPACT] 공고 제목 + 카드 제목 통합 카드 (카드 2개 → 1개)
  Widget _buildTitleAndGroupSection() {
    final theme = Theme.of(context);
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 공고 제목
          Text(
            '공고 제목',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          TextFormField(
            controller: _titleController,
            style: ResponsiveHelper.bodyStyle(context),
            decoration: InputDecoration(
              hintText: '예: 분류작업, 피킹업무',
              hintStyle: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.grey400,
              ),
              prefixIcon: Icon(
                Icons.title,
                color: theme.primaryColor,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.grey300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.grey300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.primaryColor, width: 2),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '공고 제목을 입력해주세요';
              }
              if (value.trim().length < 2) {
                return '제목은 최소 2자 이상이어야 합니다';
              }
              if (value.trim().length > 100) {
                return '제목은 100자 이내여야 합니다';
              }
              return null;
            },
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          const Divider(height: 1, thickness: 0.5),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          // 카드 제목 (선택)
          Text(
            '공고 카드 제목 (선택)',
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            '관리자 화면에서 표시할 카드 제목입니다. 비워두면 공고 제목이 사용됩니다.',
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          TextFormField(
            controller: _groupTitleController,
            style: ResponsiveHelper.bodyStyle(context),
            decoration: InputDecoration(
              hintText: '예: 5월 분류작업 묶음',
              hintStyle: ResponsiveHelper.smallStyle(context, color: AppColors.grey400),
              prefixIcon: Icon(
                Icons.label_outline,
                color: theme.primaryColor,
                size: ResponsiveHelper.iconSize(context, 24),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.grey300),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: AppColors.grey300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: theme.primaryColor, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 근무 유형 선택 칩 (단기/고정)
  Widget _buildJobTypeChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _selectedJobType == value;
    return GestureDetector(
      onTap: () async => _onJobTypeChanged(value),
      child: Container(
        // [UI-COMPACT] 수직 패딩 16→10: 칩 높이 축소
        padding:
            EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 10)),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : AppColors.grey100,
          borderRadius: BorderRadius.circular(12),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                color: isSelected ? Colors.white : AppColors.grey700,
                size: ResponsiveHelper.iconSize(context, 20)),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Flexible(
              child: Text(label,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: isSelected ? Colors.white : AppColors.grey700,
                    fontWeight: FontWeight.bold,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSelector() {
    return TODateSelector(
      isLongTerm: _selectedJobType == TOType.contract,
      selectedDates: _selectedDates,
      onDateToggle: _onDateToggle,
      onClearAll: _clearAllDates,
      rangeStart: _rangeStart,
      rangeEnd: _rangeEnd,
      selectedWeekdays: _selectedWeekdays,
      onRangeStartChanged: (date) => setState(() { _rangeStart = date.year == 0 ? null : date; _hasChanges = true; }),
      onRangeEndChanged: (date) => setState(() { _rangeEnd = date; _hasChanges = true; }),
      onWeekdayToggle: _onWeekdayToggle,
      contractPeriodType: _contractPeriodType,
      onContractPeriodTypeChanged: (type) => setState(() {
        _contractPeriodType = type;
        _hasChanges = true;
        if (type != 'custom') _rangeEnd = null;
        // 계약 타입 변경 시 근무 시작 가능기간 초기화
        _workStartAvailableFrom = null;
        _workStartAvailableUntil = null;
      }),
      workStartAvailableFrom: _workStartAvailableFrom,
      workStartAvailableUntil: _workStartAvailableUntil,
      onWorkStartAvailableFromChanged: (date) => setState(() {
        _workStartAvailableFrom = date;
        _hasChanges = true;
      }),
      onWorkStartAvailableUntilChanged: (date) => setState(() {
        _workStartAvailableUntil = date;
        _hasChanges = true;
      }),
    );
  }
}
