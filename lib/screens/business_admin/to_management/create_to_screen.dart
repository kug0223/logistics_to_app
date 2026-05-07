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
import '../../../providers/user_provider.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/dialog_helper.dart';

// Theme
import '../../../theme/app_colors.dart';

// Widgets
import '../../../widgets/pickers/create&edit_work_detail_dialog.dart';

// 공통 위젯
import 'widgets/to_widgets.dart';

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

  // 사업장 관련
  List<BusinessModel> _myBusinesses = [];
  BusinessModel? _selectedBusiness;
  List<BusinessWorkTypeModel> _businessWorkTypes = [];

  // TO 설정 — 'flex' 단기 / 'contract' 장기
  String _selectedJobType = 'flex';

  // 날짜 선택 (flex용)
  final List<DateTime> _selectedDates = [];

  // 계약 기간 (contract용)
  final List<String> _selectedWeekdays = [];
  DateTime? _rangeStart;
  DateTime? _rangeEnd;

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
        return;
      }

      final allBusinesses = await _firestoreService.getMyBusiness(uid);
      final approvedBusinesses = allBusinesses.where((b) => b.isApproved).toList();

      setState(() {
        _myBusinesses = approvedBusinesses;
        if (_myBusinesses.isNotEmpty) {
          _selectedBusiness = _myBusinesses.first;
          _loadWorkTypes();
        }
        _isLoading = false;
      });

      if (allBusinesses.isNotEmpty && approvedBusinesses.isEmpty) {
        ToastHelper.showWarning('승인된 사업장이 없습니다\n관리자 승인 후 공고를 등록할 수 있습니다');
      } else if (approvedBusinesses.isEmpty) {
        ToastHelper.showInfo('등록된 사업장이 없습니다');
      }
    } catch (e) {
      debugPrint('❌ 사업장 로드 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('사업장 정보를 불러올 수 없습니다');
    }
  }

  Future<void> _loadWorkTypes() async {
    if (_selectedBusiness == null) return;
    try {
      final workTypes = await _firestoreService.getBusinessWorkTypes(_selectedBusiness!.id);
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
      final allTOs = await _firestoreService.getTOsByBusiness(_selectedBusiness!.id);
      allTOs.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _recentTOsForLoad = allTOs.take(30).toList();
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

        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: Container(
            width: double.maxFinite,
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
              maxWidth: 500,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                  decoration: BoxDecoration(
                    color: Theme.of(context).primaryColor,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(16),
                      topRight: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.file_copy_outlined,
                          color: Colors.white,
                          size: ResponsiveHelper.iconSize(context, 24)),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        child: Text(
                          '기존 공고 불러오기',
                          style: ResponsiveHelper.subtitleStyle(context)
                              .copyWith(color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close,
                            color: Colors.white,
                            size: ResponsiveHelper.iconSize(context, 24)),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
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
                      Text('제목, 업무상세, 설명만 불러옵니다',
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.grey600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildTOListTile(TOModel to) {
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
                  DateFormat('MM/dd').format(displayDate),
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
      final isDuplicate = _workDetails.any((w) => w.workType == result.workType);
      if (isDuplicate) {
        ToastHelper.showWarning('이미 추가된 업무 유형입니다');
        return;
      }
      setState(() => _workDetails.add(result));
    }
  }

  Future<void> _editWorkDetail(int index) async {
    final detail = _workDetails[index];

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
      _selectedJobType = newType;
      _selectedDates.clear();
      _selectedWeekdays.clear();
      _rangeStart = null;
      _rangeEnd = null;
      _fixedDeadline = null;
      _publishMode = 'immediate';
      _publishDaysBefore = 1;
      _publishTime = '14:00';
    });
  }

  // ============================================================
  // TO 생성
  // ============================================================

  Future<void> _createTO() async {
    if (!_formKey.currentState!.validate()) return;

    if (_selectedBusiness == null) {
      ToastHelper.showError('사업장을 선택해주세요');
      return;
    }

    if (_selectedJobType == 'flex') {
      if (_selectedDates.isEmpty) {
        ToastHelper.showError('날짜를 선택해주세요');
        return;
      }
    } else {
      if (_rangeStart == null || _rangeEnd == null) {
        ToastHelper.showError('계약 기간을 설정해주세요');
        return;
      }
      if (_selectedWeekdays.isEmpty) {
        ToastHelper.showError('근무 요일을 선택해주세요');
        return;
      }
      if (_fixedDeadline == null) {
        ToastHelper.showError('지원 마감 시간을 설정해주세요');
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

    setState(() => _isCreating = true);

    try {
      final userProvider = Provider.of<UserProvider>(context, listen: false);
      final uid = userProvider.currentUser?.uid;

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
        dates: _selectedJobType == 'flex' ? _selectedDates : null,
        deadlineType: _selectedJobType == 'flex' ? 'HOURS_BEFORE' : 'FIXED_TIME',
        hoursBeforeStart: _hoursBeforeStart,
        // contract 전용
        rangeStart: _selectedJobType == 'contract' ? _rangeStart : null,
        rangeEnd: _selectedJobType == 'contract' ? _rangeEnd : null,
        workDays: _selectedJobType == 'contract' ? _selectedWeekdays : null,
        contractDeadline:
            _selectedJobType == 'contract' ? _fixedDeadline?.toUtc() : null,
        // 예약 공개
        publishMode: _publishMode,
        publishDaysBefore: _publishMode == 'scheduled' ? _publishDaysBefore : null,
        publishTime: _publishMode == 'scheduled' ? _publishTime : null,
      );

      if (toId != null && mounted) {
        final label = _selectedJobType == 'contract'
            ? '고정 근무 공고가 등록되었습니다'
            : _selectedDates.length > 1
                ? '${_selectedDates.length}일 공고가 등록되었습니다'
                : '공고가 등록되었습니다';
        ToastHelper.showSuccess(label);
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
      return Scaffold(
        appBar: AppBar(title: const Text('공고 등록')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_myBusinesses.isEmpty) {
      return _buildEmptyBusinessState();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('공고 등록'),
        actions: [
          IconButton(
            icon: Icon(Icons.file_copy_outlined,
                size: ResponsiveHelper.iconSize(context, 24)),
            onPressed: _selectedBusiness != null ? _showLoadFromExistingDialog : null,
            tooltip: '기존 공고 불러오기',
          ),
        ],
      ),
      body: Container(
        color: AppColors.grey50,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: ResponsiveHelper.cardPadding(context),
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

              TODeadlineSection(
                isLongTerm: _selectedJobType == 'contract',
                hoursBeforeStart: _hoursBeforeStart,
                onHoursChanged: (h) => setState(() => _hoursBeforeStart = h),
                fixedDeadline: _fixedDeadline,
                onFixedDeadlineChanged: (dt) => setState(() => _fixedDeadline = dt),
                rangeStartDate: _rangeStart,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              TOPublishSection(
                publishMode: _publishMode,
                onPublishModeChanged: (m) => setState(() => _publishMode = m),
                publishDaysBefore: _publishDaysBefore,
                onDaysBeforeChanged: (d) => setState(() => _publishDaysBefore = d),
                publishTime: _publishTime,
                onTimeChanged: (t) => setState(() => _publishTime = t),
                previewDates: _selectedJobType == 'contract'
                    ? (_rangeStart != null ? [_rangeStart!] : [])
                    : _selectedDates,
                isLongTerm: _selectedJobType == 'contract',
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              TODescriptionSection(controller: _descriptionController),
              SizedBox(height: ResponsiveHelper.spacing(context, 24)),

              TOActionButton.create(
                onPressed: _createTO,
                isLoading: _isCreating,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 40)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyBusinessState() {
    return Scaffold(
      appBar: AppBar(title: const Text('공고 등록')),
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
      child: DropdownButtonFormField<BusinessModel>(
        initialValue: _selectedBusiness,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: '사업장 선택',
          labelStyle: ResponsiveHelper.bodyStyle(context),
          prefixIcon: Icon(Icons.business,
              color: Theme.of(context).primaryColor,
              size: ResponsiveHelper.iconSize(context, 24)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.grey300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.grey300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
          ),
        ),
        items: _myBusinesses
            .map((b) => DropdownMenuItem(value: b, child: Text(b.name)))
            .toList(),
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
                    label: '단기 근무', value: 'flex', icon: Icons.today),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: _buildJobTypeChip(
                    label: '고정 근무', value: 'contract', icon: Icons.event_note),
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
            Text(label,
                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                  color: isSelected ? Colors.white : AppColors.grey700,
                  fontWeight: FontWeight.bold,
                )),
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
      isLongTerm: _selectedJobType == 'contract',
      selectedDates: _selectedDates,
      onDateToggle: _onDateToggle,
      onClearAll: _clearAllDates,
      rangeStart: _rangeStart,
      rangeEnd: _rangeEnd,
      selectedWeekdays: _selectedWeekdays,
      onRangeStartChanged: (date) => setState(() => _rangeStart = date),
      onRangeEndChanged: (date) => setState(() => _rangeEnd = date),
      onWeekdayToggle: _onWeekdayToggle,
    );
  }
}
