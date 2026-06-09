import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

// Models
import '../../../models/core/business_model.dart';
import '../../../models/core/to_model.dart';
import '../../../models/core/business_work_type_model.dart';
import '../../../models/core/work_detail_data.dart';
import '../../../models/work_detail_input.dart';

// Services & Providers
import '../../../services/firestore_service.dart';
import '../../../services/analytics_service.dart';
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
  DateTime? _fixedDeadline;

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
    _titleController.addListener(() {
      if (_titleController.text.isNotEmpty && !_hasChanges) {
        setState(() => _hasChanges = true);
      }
    });
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
    setState(() => _isLoading = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // SubAdmin은 adminIds에 없으므로 effectiveBusinessId로 직접 조회
      final effectiveBizId = userProvider.effectiveBusinessId;
      final List<BusinessModel> allBusinesses;
      if (userProvider.isSubAdmin && effectiveBizId != null) {
        final biz = await _firestoreService.getBusinessById(effectiveBizId);
        allBusinesses = biz != null ? [biz] : [];
      } else {
        allBusinesses = await _firestoreService.getMyBusiness(uid);
      }
      final approvedBusinesses = allBusinesses.where((b) => b.isApproved).toList();

      if (!mounted) return;
      setState(() {
        _myBusinesses = approvedBusinesses;
        if (_myBusinesses.isNotEmpty) {
          _selectedBusiness = _myBusinesses.first;
          _loadWorkTypes();
        }
        _isLoading = false;
      });

      if (approvedBusinesses.isEmpty) {
        final msg = allBusinesses.isNotEmpty
            ? '승인된 사업장이 없습니다.\n관리자 승인 후 공고를 등록할 수 있습니다.'
            : '사업장을 먼저 등록해야 합니다.';
        ToastHelper.showWarning(msg);
        // 사전 조건 미충족 시 화면에서 자동 복귀
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.of(context).pop();
          });
        }
      }
    } catch (e) {
      debugPrint('❌ 사업장 로드 실패: $e');
      if (mounted) setState(() => _isLoading = false);
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
    }
  }

  Future<void> _loadWorkTypes() async {
    if (_selectedBusiness == null) return;
    try {
      final workTypes = await _firestoreService.getBusinessWorkTypes(_selectedBusiness!.id);
      if (!mounted) return;
      setState(() => _businessWorkTypes = workTypes);
    } catch (e) {
      debugPrint('❌ 업무 유형 로드 실패: $e');
      ToastHelper.showError('업무 유형을 불러올 수 없습니다');
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
      ToastHelper.showError('공고 목록을 불러올 수 없습니다');
      return;
    }

    if (!mounted) return;
    Navigator.pop(context);

    final selectedTO = await showDialog<TOModel>(
      context: context,
      builder: (context) => _buildLoadFromExistingDialog(),
    );

    if (selectedTO != null) {
      _loadDataFromTO(selectedTO);
    }
  }

  void _loadDataFromTO(TOModel to) {
    setState(() {
      _titleController.text = to.title;
      _descriptionController.text = to.description ?? '';
      _hoursBeforeStart = to.hoursBeforeStart ?? 2;
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

    if (result != null) {
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
      description: detail.description,
    );

    final result = await WorkDetailDialog.showEditDialog(
      context: context,
      work: tempData,
      businessWorkTypes: _businessWorkTypes,
    );

    if (result != null) {
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
      });
    }
  }

  void _removeWorkDetail(int index) {
    setState(() => _workDetails.removeAt(index));
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
    });
  }

  void _onJobTypeChanged(String newType) {
    setState(() {
      _hasChanges = true;
      _selectedJobType = newType;
      _selectedDates.clear();
      _selectedWeekdays.clear();
      _rangeStart = null;
      _rangeEnd = null;
      _contractPeriodType = null;
      _postingDurationDays = 7;
      _fixedDeadline = null;
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
    if (!_formKey.currentState!.validate()) return;

    if (_selectedBusiness == null) {
      ToastHelper.showError('사업장을 선택해주세요');
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
      if (_selectedWeekdays.isEmpty) {
        ToastHelper.showError('근무 요일을 선택해주세요');
        return;
      }
      // contract 타입은 지원 마감일 필수
      if (_fixedDeadline == null) {
        ToastHelper.showError('지원 마감일을 설정해주세요');
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

    if (_workDetails.any((w) => (w.requiredCount ?? 0) <= 0)) {
      ToastHelper.showError('필요 인원은 1명 이상이어야 합니다');
      return;
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

    setState(() => _isCreating = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

      if (uid == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        setState(() => _isCreating = false);
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
        deadlineType: _selectedJobType == TOType.flex ? 'HOURS_BEFORE' : 'FIXED_TIME',
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
        contractDeadline:
            _selectedJobType == TOType.contract ? _fixedDeadline?.toUtc() : null,
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
      }
    } catch (e) {
      debugPrint('❌ TO 생성 실패: $e');
      ToastHelper.showError('공고 등록에 실패했습니다');
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

    if (_myBusinesses.isEmpty) {
      return _buildEmptyBusinessState();
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
          IconButton(
            icon: Icon(Icons.file_copy_outlined,
                color: Colors.white,
                size: ResponsiveHelper.iconSize(context, 24)),
            onPressed: _selectedBusiness != null ? _showLoadFromExistingDialog : null,
            tooltip: '기존 공고 불러오기',
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

              // 마감 설정: flex = 시간기준(HOURS_BEFORE), contract = 날짜지정(FIXED_TIME)
              TODeadlineSection(
                isLongTerm: _selectedJobType == TOType.contract,
                hoursBeforeStart: _hoursBeforeStart,
                onHoursChanged: (h) => setState(() => _hoursBeforeStart = h),
                fixedDeadline: _fixedDeadline,
                onFixedDeadlineChanged: (dt) => setState(() => _fixedDeadline = dt),
                rangeStartDate: _selectedJobType == TOType.contract ? _rangeStart : null,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              TOPublishSection(
                publishMode: _publishMode,
                onPublishModeChanged: (m) => setState(() => _publishMode = m),
                publishDaysBefore: _publishDaysBefore,
                onDaysBeforeChanged: (d) => setState(() => _publishDaysBefore = d),
                publishTime: _publishTime,
                onTimeChanged: (t) => setState(() => _publishTime = t),
                previewDates: _selectedJobType == TOType.contract
                    ? (_rangeStart != null ? [_rangeStart!] : [])
                    : _selectedDates,
                isLongTerm: _selectedJobType == TOType.contract,
                postingDurationDays: _postingDurationDays,
                onPostingDurationChanged: (d) => setState(() => _postingDurationDays = d),
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

  Widget _buildEmptyBusinessState() {
    return GradientScaffold(
      title: '공고 등록',
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.business_outlined,
                  size: ResponsiveHelper.iconSize(context, 64),
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.5)),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 24)),
            Text('등록된 사업장이 없습니다',
                style: ResponsiveHelper.titleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold)),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text('사업장을 먼저 등록해주세요',
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey600)),
          ],
        ),
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
      onTap: () => _onJobTypeChanged(value),
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
      onRangeStartChanged: (date) => setState(() => _rangeStart = date.year == 0 ? null : date),
      onRangeEndChanged: (date) => setState(() => _rangeEnd = date),
      onWeekdayToggle: _onWeekdayToggle,
      contractPeriodType: _contractPeriodType,
      onContractPeriodTypeChanged: (type) => setState(() {
        _contractPeriodType = type;
        if (type != 'custom') _rangeEnd = null;
      }),
    );
  }
}
