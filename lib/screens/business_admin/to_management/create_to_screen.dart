import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
import '../../../providers/user_provider.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/dialog_helper.dart';

// Theme
import '../../../theme/app_colors.dart';

// Widgets
import '../../../widgets/pickers/create_edit_work_detail_dialog.dart';
import '../../../widgets/dialogs/styled_dialog.dart';

// 공통 위젯
import 'widgets/to_widgets.dart';
import '../../../widgets/app_select_field.dart';
import '../../../widgets/common/gradient_scaffold.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../common/settings_screen.dart';
import '../contract_template_list_screen.dart';
import '../work_type_management_screen.dart';
import '../Business_form_screen.dart';

/// 사업장별 사전조건 충족 여부
class _BizReadiness {
  final BusinessModel business;
  final bool workTypesReady;
  const _BizReadiness({
    required this.business,
    required this.workTypesReady,
  });
}

class AdminCreateTOScreen extends StatefulWidget {
  const AdminCreateTOScreen({super.key});

  @override
  State<AdminCreateTOScreen> createState() => _AdminCreateTOScreenState();
}

class _AdminCreateTOScreenState extends State<AdminCreateTOScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _groupTitleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();

  // 로딩 상태
  bool _isLoading = true;
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
  List<_BizReadiness> _businessReadinessList = []; // 멀티 사업장 결핍 정보
  bool get _allPrerequisitesMet =>
      _businessApproved && _workTypesReady && _contractTemplatesReady && _hasLicense;

  // TO 설정 — 'flex' 단기 / 'contract' 장기
  String _selectedJobType = TOType.flex;

  // 날짜 선택 (flex용)
  final List<DateTime> _selectedDates = [];

  // 계약 기간 (contract용)
  final List<String> _selectedWeekdays = [];
  DateTime? _rangeStart;
  DateTime? _rangeEnd;
  String? _contractPeriodType; // '15days' | '1month' | '3months' | '6months' | '1year' | 'custom'
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

      final effectiveBizId = userProvider.effectiveBusinessId;
      final List<BusinessModel> allBusinesses;
      if (userProvider.isSubAdmin && effectiveBizId != null) {
        final biz = await _firestoreService.getBusinessById(effectiveBizId);
        allBusinesses = biz != null ? [biz] : [];
      } else {
        allBusinesses = await _firestoreService.getMyBusiness(uid);
      }
      final approvedBusinesses = allBusinesses.where((b) => b.isApproved).toList();
      final bool hasLicense =
          (userProvider.currentUser?.businessLicenseImageUrl?.isNotEmpty ?? false);

      if (!mounted) return;

      if (approvedBusinesses.isEmpty) {
        setState(() {
          _hasAnyBusiness = allBusinesses.isNotEmpty;
          _businessApproved = false;
          _workTypesReady = false;
          _contractTemplatesReady = false;
          _hasLicense = hasLicense;
          _businessReadinessList = [];
          _isLoading = false;
        });
        return;
      }

      // 모든 승인 사업장의 업무목록 + 계약서 병렬 로드
      final checks = await Future.wait(
        approvedBusinesses.map((biz) async {
          final res = await Future.wait([
            _firestoreService.getBusinessWorkTypes(biz.id),
            _contractTemplateService.getTemplates(biz.id),
          ]);
          return (
            business: biz,
            workTypes: res[0] as List<BusinessWorkTypeModel>,
            templates: res[1] as List<ContractTemplateModel>,
          );
        }),
      );

      if (!mounted) return;

      // 계약서 템플릿은 사업장 무관 전역 체크 — 모든 사업장 합산
      final allTemplates =
          checks.expand((c) => c.templates).toList();

      // 업무유형만 충족한 첫 번째 사업장 자동선택 (계약서는 전역)
      final ready = checks.where((c) => c.workTypes.isNotEmpty);

      if (ready.isNotEmpty) {
        final sel = ready.first;
        setState(() {
          _myBusinesses = approvedBusinesses;
          _selectedBusiness = sel.business;
          _businessWorkTypes = sel.workTypes;
          _hasAnyBusiness = true;
          _businessApproved = true;
          _workTypesReady = true;
          _contractTemplatesReady = allTemplates.isNotEmpty;
          _hasLicense = hasLicense;
          _businessReadinessList = [];
          if (_allPrerequisitesMet) _formUnlocked = true;
          _isLoading = false;
        });
      } else {
        // 어느 사업장도 업무유형 미충족 — 결핍 정보 보존
        final first = checks.first;
        setState(() {
          _myBusinesses = approvedBusinesses;
          _selectedBusiness = first.business;
          _businessWorkTypes = first.workTypes;
          _hasAnyBusiness = true;
          _businessApproved = true;
          _workTypesReady = first.workTypes.isNotEmpty;
          _contractTemplatesReady = allTemplates.isNotEmpty;
          _hasLicense = hasLicense;
          _businessReadinessList = checks
              .map((c) => _BizReadiness(
                    business: c.business,
                    workTypesReady: c.workTypes.isNotEmpty,
                  ))
              .toList();
          _isLoading = false;
        });
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
      setState(() {
        _businessWorkTypes = workTypes;
        _workTypesReady = workTypes.isNotEmpty;
        _contractTemplatesReady = allTemplates.isNotEmpty;
        _hasLicense = (Provider.of<UserProvider>(context, listen: false)
                .currentUser
                ?.businessLicenseImageUrl
                ?.isNotEmpty ??
            false);
        if (_allPrerequisitesMet) {
          _formUnlocked = true;
          _businessReadinessList = [];
        }
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 사전조건 재체크 실패: $e');
      if (mounted) setState(() => _isLoading = false);
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

    DialogHelper.showLoading(context, message: '공고 목록 불러오는 중...');

    try {
      _recentTOsForLoad = await _firestoreService.getTOsByBusiness(
        _selectedBusiness!.id,
        limit: 30,
      );
    } catch (e) {
      debugPrint('❌ TO 목록 로드 실패: $e');
      if (mounted) Navigator.pop(context);
      if (mounted) ToastHelper.showError('공고 목록을 불러올 수 없습니다');
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    final selectedTO = await showDialog<TOModel>(
      context: context,
      builder: (context) => _buildLoadFromExistingDialog(),
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

  Widget _buildLoadFromExistingDialog() {
    String searchQuery = '';

    return StatefulBuilder(
      builder: (context, setDialogState) {
        final filteredTOs = searchQuery.isEmpty
            ? _recentTOsForLoad
            : _recentTOsForLoad
                .where((to) => to.title.toLowerCase().contains(searchQuery.toLowerCase()))
                .toList();

        return StyledDialog(
          title: '기존 공고 불러오기',
          icon: Icons.file_copy_outlined,
          showCloseButton: true,
          maxHeightRatio: 0.7,
          fillHeight: true,
          content: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  ResponsiveHelper.spacing(context, 16),
                  ResponsiveHelper.spacing(context, 12),
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
                  onChanged: (v) => setDialogState(() => searchQuery = v),
                ),
              ),
              Expanded(
                child: filteredTOs.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.inbox_outlined,
                                size: ResponsiveHelper.iconSize(context, 48),
                                color: AppColors.grey400),
                            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                            Text(
                              searchQuery.isEmpty ? '등록된 공고가 없습니다' : '검색 결과가 없습니다',
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
                            Divider(height: 1, color: AppColors.divider),
                        itemBuilder: (context, index) =>
                            _buildTOListTile(filteredTOs[index]),
                      ),
              ),
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                color: AppColors.grey100,
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: ResponsiveHelper.iconSize(context, 16),
                        color: AppColors.grey600),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Text('제목, 업무상세, 설명, 마감시간 설정을 불러옵니다',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey600)),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTOListTile(TOModel to) {
    final isFlexNoRange = to.isFlexType && to.rangeStart == null;
    final displayDate = to.rangeStart ?? to.createdAt;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.pop(context, to),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 4),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: ResponsiveHelper.spacing(context, 6),
                ),
                decoration: BoxDecoration(
                  color: to.isContractType
                      ? AppColors.longTermBg
                      : Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isFlexNoRange
                      ? '${to.totalSlots}일'
                      : DateFormat('MM/dd').format(displayDate),
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: to.isContractType
                        ? AppColors.longTermDark
                        : Theme.of(context).primaryColor,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      to.title,
                      style: ResponsiveHelper.bodyStyle(context)
                          .copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                    Row(
                      children: [
                        if (to.isContractType) ...[
                          Icon(Icons.repeat,
                              size: ResponsiveHelper.iconSize(context, 12),
                              color: AppColors.longTermDark),
                          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                          Text('장기',
                              style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.longTermDark)),
                          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        ],
                        Icon(Icons.people_outline,
                            size: ResponsiveHelper.iconSize(context, 12),
                            color: AppColors.grey500),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                        Text('${to.totalRequired}명',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.grey600)),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right,
                  color: AppColors.grey400,
                  size: ResponsiveHelper.iconSize(context, 20)),
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
      final normalized = DateTime(date.year, date.month, date.day);
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
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);

    // 어제 이전 날짜는 무조건 만료
    if (dateOnly.isBefore(today)) return true;

    // 오늘 날짜: 업무별 마감시각 확인
    if (!DateUtils.isSameDay(date, now)) return false;
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
      ToastHelper.showError('제목을 입력해주세요');
      return;
    }

    if (_selectedBusiness == null) {
      ToastHelper.showError('사업장을 선택해주세요');
      return;
    }

    if (_businessWorkTypes.isEmpty) {
      ToastHelper.showError('업무목록을 먼저 등록해주세요.\n사업장 설정에서 업무목록을 추가할 수 있습니다.');
      return;
    }

    if (_selectedJobType == TOType.flex) {
      if (_selectedDates.isEmpty) {
        ToastHelper.showError('날짜를 선택해주세요');
        return;
      }
      // 과거 날짜 포함 여부 경고 — _someSlotExpired 조건과 독립적으로 항상 표시
      final today = DateTime.now();
      final todayOnly = DateTime(today.year, today.month, today.day);
      final hasPastDate = _selectedDates.any((d) =>
          DateTime(d.year, d.month, d.day).isBefore(todayOnly));
      if (hasPastDate && !_allSlotsExpired) {
        ToastHelper.showWarning('과거 날짜가 포함되어 있습니다. 해당 날짜는 즉시 마감됩니다');
      }
    } else {
      if (_contractPeriodType == null) {
        ToastHelper.showError('계약 기간을 선택해주세요');
        return;
      }
      if (_contractPeriodType == 'custom' && (_rangeStart == null || _rangeEnd == null)) {
        ToastHelper.showError('계약 시작일과 종료일을 설정해주세요');
        return;
      }
      if (_contractPeriodType == 'custom' &&
          _rangeStart != null && _rangeEnd != null &&
          _rangeStart!.isAfter(_rangeEnd!)) {
        ToastHelper.showError('계약 시작일이 종료일보다 이후일 수 없습니다');
        return;
      }
      if (_contractPeriodType == 'custom' && _rangeEnd != null) {
        final todayOnly = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
        if (_rangeEnd!.isBefore(todayOnly)) {
          ToastHelper.showWarning('계약 종료일이 과거 날짜입니다. 즉시 마감 처리됩니다');
        }
      }
      // [D-3 수정] custom 기간에서 rangeStart가 과거 날짜인 경우 경고
      // 저장 자체는 허용하나 관리자에게 의도 재확인 유도
      if (_contractPeriodType == 'custom' && _rangeStart != null) {
        final todayOnly = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
        if (_rangeStart!.isBefore(todayOnly)) {
          ToastHelper.showWarning('계약 시작일이 과거 날짜입니다. 게시 즉시 활성 상태로 시작됩니다');
        }
      }
      if (_selectedWeekdays.isEmpty) {
        ToastHelper.showError('근무 요일을 선택해주세요');
        return;
      }
    }

    if (_workDetails.isEmpty) {
      ToastHelper.showError('최소 1개의 업무를 추가해주세요');
      return;
    }

    if (_workDetails.any((w) => !w.isValid)) {
      ToastHelper.showError('모든 업무 정보를 입력해주세요');
      return;
    }

    if (_workDetails.any((w) => (w.wage ?? 0) <= 0)) {
      ToastHelper.showError('급여는 0원보다 커야 합니다');
      return;
    }
    // 최저임금(2026: 10,320원) 미달 여부를 앱에서 하드 차단하지 않는다.
    // 임금 결정은 사업주 권한이며, 수습·단순가산 등 예외 케이스가 다양하다.
    // 최저임금법 준수 책임은 사업주에게 있고, 앱은 경영 도구로서 개입하지 않는다.

    if (_workDetails.any((w) => (w.wage ?? 0) > 50000000)) {
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

    // 사업주 날인 미등록 차단 — 근로계약서 서명에 필요 (전역 체크)
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;

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
                return DateTime(d.year, d.month, d.day);
              }()
            : null,
        rangeEnd: _selectedJobType == TOType.contract && _contractPeriodType == 'custom' ? _rangeEnd : null,
        workDays: _selectedJobType == TOType.contract ? _selectedWeekdays : null,
        contractDeadline: null,
        contractPeriodType: _selectedJobType == TOType.contract ? _contractPeriodType : null,
        postingDurationDays: _postingDurationDays, // flex·contract 모두 저장
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
        if (e.toString().contains('MAX_ACTIVE_TO_LIMIT')) {
          final parts = e.toString().split(':');
          final limitStr = parts.length >= 2 ? parts.last : '4';
          ToastHelper.showError('진행중인 공고가 최대 $limitStr개입니다.\n기존 공고를 마감 후 새 공고를 등록해주세요.');
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
      return GradientScaffold(
        title: '공고 등록',
        body: const LoadingWidget(),
      );
    }

    if (!_formUnlocked) {
      return _buildPrerequisiteScreen();
    }

    return PopScope(
      canPop: !_isCreating && !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !_hasChanges) return;
        final leave = await DialogHelper.showConfirm(
          context,
          title: '입력 중인 내용이 있습니다',
          message: '공고 등록을 취소하시겠습니까?\n입력한 내용이 모두 사라집니다.',
          confirmText: '나가기',
          cancelText: '계속 작성',
        );
        if (leave && context.mounted) Navigator.pop(context);
      },
      child: GradientScaffold(
        title: '공고 등록',
        actions: [
          TextButton(
            onPressed: _selectedBusiness != null ? _showLoadFromExistingDialog : null,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white,
              disabledForegroundColor: Colors.white38,
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.file_copy_outlined,
                    size: ResponsiveHelper.iconSize(context, 20)),
                Text(
                  '불러오기',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: _selectedBusiness != null
                          ? Colors.white
                          : Colors.white38,
                      fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
        ],
        body: Form(
          key: _formKey,
          child: ListView(
            padding: ResponsiveHelper.listPadding(context),
            children: [
              _buildBusinessSelector(),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              _buildJobTypeSelector(),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              TOTitleSection(titleController: _titleController),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              _buildGroupTitleField(context),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              _buildDateSelector(),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              TOWorkDetailsSection(
                workDetailInputs: _workDetails,
                onAddWork: _showAddWorkDetailDialog,
                onEditWorkByIndex: _editWorkDetail,
                onRemoveWorkByIndex: _removeWorkDetail,
                showNoWorkTypeWarning: _businessWorkTypes.isEmpty,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              // 단기(flex)만 지원마감 설정 — 고정근무(contract)는 게시기간이 곧 지원기간
              if (_selectedJobType != TOType.contract) ...[
                TODeadlineSection(
                  isLongTerm: false,
                  hoursBeforeStart: _hoursBeforeStart,
                  onHoursChanged: (h) => setState(() { _hoursBeforeStart = h; _hasChanges = true; }),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
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
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              TODescriptionSection(controller: _descriptionController),
              SizedBox(height: ResponsiveHelper.spacing(context, 24)),

              TOActionButton.create(
                onPressed: _isCreating ? null : _createTO,
                isLoading: _isCreating,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 40)),
            ],
          ),
        ),
      ),
    );     // PopScope
  }

  /// 공고 등록 사전조건 체크 화면 — 3가지를 한 번에 보여줌
  Widget _buildPrerequisiteScreen() {
    final theme = Theme.of(context);
    return GradientScaffold(
      title: '공고 등록',
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
                        Text('아래 3가지를 모두 완료해야 공고를 등록할 수 있습니다.',
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
            _buildPrerequisiteCard(
              index: 1,
              title: '사업장 등록 & 승인',
              isReady: _businessApproved,
              readyDescription: '승인된 사업장이 있습니다',
              notReadyDescription: _hasAnyBusiness
                  ? '사업장이 아직 승인되지 않았습니다.\n관리자 승인을 기다려주세요.'
                  : '사업장이 등록되어 있지 않습니다.',
              actionLabel: _hasAnyBusiness ? null : '사업장 등록하기',
              onAction: _hasAnyBusiness
                  ? null
                  : () async {
                      await NavigationHelper.push<void>(context,
                          destination: const BusinessFormScreen());
                      if (!mounted) return;
                      await _loadMyBusinesses();
                    },
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
            _buildPrerequisiteCard(
              index: 3,
              title: '근로계약서 템플릿',
              isReady: _contractTemplatesReady,
              readyDescription: '계약서 템플릿이 등록되어 있습니다',
              notReadyDescription: _businessApproved
                  ? '등록된 계약서 템플릿이 없습니다.'
                  : '사업장 승인 후 확인 가능합니다.',
              actionLabel: _businessApproved ? '계약서 관리' : null,
              onAction: _businessApproved && _selectedBusiness != null
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

  Widget _buildBusinessSelector() {
    return TOSectionContainer(
      child: AppSelectField<BusinessModel>(
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
    );
  }

  Widget _buildJobTypeSelector() {
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('근무 유형',
              style: ResponsiveHelper.subtitleStyle(context)
                  .copyWith(fontWeight: FontWeight.bold)),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Row(
            children: [
              Expanded(
                child: _buildJobTypeChip(
                    label: '단기 근무', value: TOType.flex, icon: Icons.today),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
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

  Widget _buildJobTypeChip({
    required String label,
    required String value,
    required IconData icon,
  }) {
    final isSelected = _selectedJobType == value;
    return GestureDetector(
      onTap: () async => _onJobTypeChanged(value),
      child: Container(
        padding:
            EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 16)),
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

  Widget _buildGroupTitleField(BuildContext context) {
    final theme = Theme.of(context);
    return TOSectionContainer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
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
      }),
    );
  }
}
