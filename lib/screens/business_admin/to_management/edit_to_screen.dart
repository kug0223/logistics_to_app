import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// Models
import '../../../models/core/to_model.dart';
import '../../../models/core/slot_model.dart';
import '../../../models/core/work_detail_data.dart';
import '../../../models/core/business_work_type_model.dart';

// Services & Providers
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';

// Utils
import '../../../utils/toast_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/responsive_helper.dart';

// Widgets
import '../../../widgets/pickers/create&edit_work_detail_dialog.dart';
import '../../../widgets/dialogs/styled_dialog.dart';

// 공통 위젯
import 'widgets/to_widgets.dart';
import '../../../theme/app_colors.dart';

class AdminEditTOScreen extends StatefulWidget {
  final TOModel to;
  final SlotModel? slot;             // 단일 슬롯 수정
  final List<SlotModel>? batchSlots; // 배치 슬롯 수정 (일괄수정)
  final DateTime? newSlotDate;       // 새 날짜 슬롯 추가

  const AdminEditTOScreen({
    super.key,
    required this.to,
    this.slot,
    this.batchSlots,
    this.newSlotDate,
  });

  bool get isBatchMode => batchSlots != null && batchSlots!.isNotEmpty;
  bool get isNewSlot => newSlotDate != null;
  bool get isSlotMode => slot != null || isBatchMode || isNewSlot;

  @override
  State<AdminEditTOScreen> createState() => _AdminEditTOScreenState();
}

class _AdminEditTOScreenState extends State<AdminEditTOScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();

  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _slotTitleController; // 슬롯 개별 공고 제목

  bool _isLoading = true;
  bool _isSaving = false;
  List<WorkDetailData> _workDetails = [];
  List<BusinessWorkTypeModel> _businessWorkTypes = [];
  DateTime? _firstSlotDate; // 단기 TO 예약 공개 기준일용

  int _hoursBeforeStart = 2;
  DateTime? _fixedDeadline;

  String _publishMode = 'immediate';
  int _publishDaysBefore = 1;
  String _publishTime = '14:00';

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.to.title);
    _descriptionController =
        TextEditingController(text: widget.to.description ?? '');
    _slotTitleController = TextEditingController();
    _hoursBeforeStart = widget.to.hoursBeforeStart ?? 2;
    _fixedDeadline =
        widget.to.isContractType ? widget.to.applicationDeadline : null;
    _publishMode = widget.to.publishMode;
    _publishDaysBefore = widget.to.publishDaysBefore ?? 1;
    _publishTime = widget.to.publishTime ?? '14:00';
    _loadData();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _slotTitleController.dispose();
    super.dispose();
  }

  // ============================================================
  // 데이터 로딩 — workDetails는 TO 문서에 내장되어 있으므로 바로 사용
  // ============================================================

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final workTypes = await _firestoreService
          .getBusinessWorkTypes(widget.to.businessId);

      if (widget.isBatchMode) {
        setState(() {
          _workDetails = List<WorkDetailData>.from(widget.batchSlots!.first.workDetails);
          _businessWorkTypes = workTypes;
          _isLoading = false;
        });
        return;
      }

      if (widget.slot != null) {
        _slotTitleController.text = widget.slot!.title ?? widget.to.title;
        setState(() {
          _workDetails = List<WorkDetailData>.from(widget.slot!.workDetails);
          _businessWorkTypes = workTypes;
          _isLoading = false;
        });
        return;
      }

      if (widget.isNewSlot) {
        final slots = await _firestoreService.getSlots(widget.to.id);
        final template = slots.isNotEmpty ? slots.first : null;
        _slotTitleController.text = template?.title ?? widget.to.title;
        setState(() {
          _workDetails = List<WorkDetailData>.from(
              template?.workDetails ?? widget.to.workDetails);
          _businessWorkTypes = workTypes;
          _isLoading = false;
        });
        return;
      }

      DateTime? firstSlotDate;
      if (!widget.to.isContractType) {
        final slots = await _firestoreService.getSlots(widget.to.id);
        if (slots.isNotEmpty) {
          slots.sort((a, b) => a.date.compareTo(b.date));
          firstSlotDate = slots.first.date;
        }
      }

      setState(() {
        _workDetails = List<WorkDetailData>.from(widget.to.workDetails);
        _businessWorkTypes = workTypes;
        _firstSlotDate = firstSlotDate;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 데이터 로드 실패: $e');
      ToastHelper.showError('데이터를 불러오는데 실패했습니다');
      setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // 저장 — TO 문서의 workDetails 배열을 통째로 업데이트
  // ============================================================

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      // ── 슬롯 수정 모드 ──────────────────────────────────────
      if (widget.isNewSlot) {
        await _saveNewSlotChanges();
        return;
      }
      if (widget.isBatchMode) {
        await _saveBatchSlotChanges();
        return;
      }
      if (widget.slot != null) {
        await _saveSlotChanges();
        return;
      }

      // ── 공개 시각 계산 ──────────────────────────────────────
      // 이미 공개된 TO는 수정해도 비공개로 되돌리지 않음
      DateTime? publishAt;
      bool shouldPublishImmediately =
          widget.to.isPublished || _publishMode == 'immediate';

      if (!widget.to.isPublished && _publishMode == 'scheduled') {
        // 장기: rangeStart 기준 / 단기: 첫 슬롯 날짜 기준
        final refDate = widget.to.isContractType
            ? (widget.to.rangeStart ?? widget.to.createdAt)
            : (_firstSlotDate ?? widget.to.createdAt);
        final targetDate =
            refDate.subtract(Duration(days: _publishDaysBefore));
        final timeParts = _publishTime.split(':');
        publishAt = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          int.parse(timeParts[0]),
          int.parse(timeParts[1]),
        );
        if (publishAt.isBefore(DateTime.now())) {
          shouldPublishImmediately = true;
          publishAt = null;
          ToastHelper.showInfo('공개 예정 시간이 지나 즉시 공개로 전환됩니다');
        }
      }

      final totalRequired =
          _workDetails.fold<int>(0, (s, d) => s + d.requiredCount);

      final wasManualClosed = widget.to.isManualClosed;

      final updates = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'workDetails': WorkDetailData.listToFirestore(_workDetails),
        'totalRequired': totalRequired,
        'hoursBeforeStart': _hoursBeforeStart,
        'publishMode': _publishMode,
        'publishAt': publishAt != null
            ? Timestamp.fromDate(publishAt)
            : FieldValue.delete(),
        'isPublished': shouldPublishImmediately,
        'publishDaysBefore':
            _publishMode == 'scheduled' ? _publishDaysBefore : null,
        'publishTime': _publishMode == 'scheduled' ? _publishTime : null,
        if (wasManualClosed) ...{
          'isManualClosed': false,
          'closedAt': FieldValue.delete(),
          'closedBy': FieldValue.delete(),
          'status': 'ACTIVE',
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        },
      };

      if (widget.to.isContractType && _fixedDeadline != null) {
        updates['applicationDeadline'] =
            Timestamp.fromDate(_fixedDeadline!.toUtc());
      }

      if (wasManualClosed) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        updates['reopenedBy'] = userProvider.currentUser?.uid;
        updates['reopenedAt'] = FieldValue.serverTimestamp();
      }

      await _firestoreService.updateTO(widget.to.id, updates);

      // ── 단기 TO: 슬롯 일괄 갱신 ──────────────────────────────
      if (!widget.to.isContractType) {
        // publish 설정 변경 → 슬롯별 visibleFrom 재계산
        final publishSettingsChanged =
            _publishMode != widget.to.publishMode ||
            _publishDaysBefore != (widget.to.publishDaysBefore ?? 1) ||
            _publishTime != (widget.to.publishTime ?? '14:00');

        if (publishSettingsChanged) {
          await _firestoreService.updateSlotsPublishSettings(
            toId: widget.to.id,
            publishMode: _publishMode,
            publishDaysBefore: _publishDaysBefore,
            publishTime: _publishTime,
          );
        }

        // 업무 구성 변경 감지 (추가/삭제)
        final oldWorkTypes =
            widget.to.workDetails.map((d) => d.workType).toSet();
        final newWorkTypes = _workDetails.map((d) => d.workType).toSet();
        final workTypesChanged = oldWorkTypes.length != newWorkTypes.length ||
            !oldWorkTypes.containsAll(newWorkTypes);

        // 근무시간 or 마감 기준 변경 → 슬롯별 applicationDeadline 재계산
        final oldEarliestStart = widget.to.workDetails.isNotEmpty
            ? (widget.to.workDetails.map((d) => d.startTime).toList()..sort()).first
            : null;
        final newEarliestStart = _workDetails.isNotEmpty
            ? (_workDetails.map((d) => d.startTime).toList()..sort()).first
            : null;

        final deadlineSettingsChanged =
            _hoursBeforeStart != (widget.to.hoursBeforeStart ?? 2) ||
            oldEarliestStart != newEarliestStart;

        // 임금·인원 변경 감지 (임금만 바뀌어도 슬롯 동기화 필요)
        final wageOrCountChanged = _workDetails.any((newD) {
          final oldD = widget.to.workDetails.where((d) => d.workType == newD.workType).firstOrNull;
          if (oldD == null) return true;
          return oldD.wage != newD.wage ||
              oldD.wageType != newD.wageType ||
              oldD.requiredCount != newD.requiredCount;
        });

        // 업무 구성·마감·임금·인원 변경 시 슬롯 workDetails 일괄 동기화
        if (workTypesChanged || deadlineSettingsChanged || wageOrCountChanged) {
          await _firestoreService.updateSlotsDeadlines(
            toId: widget.to.id,
            deadlineType: 'HOURS_BEFORE',
            hoursBeforeStart: _hoursBeforeStart,
            newWorkDetails: _workDetails,
          );
        }
      }

      _firestoreService.clearCache(toId: widget.to.id);

      ToastHelper.showSuccess('TO가 수정되었습니다');
      if (mounted) NavigationHelper.popWithChange(context);
    } catch (e) {
      debugPrint('❌ TO 수정 실패: $e');
      ToastHelper.showError('수정에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ============================================================
  // 슬롯 수정 저장
  // ============================================================

  Future<void> _saveSlotChanges() async {
    try {
      final slot = widget.slot!;

      // 가장 이른 startTime 기준으로 applicationDeadline 계산
      DateTime? slotDeadline;
      if (_workDetails.isNotEmpty) {
        final earliestStart =
            (_workDetails.map((d) => d.startTime).toList()..sort()).first;
        final parts = earliestStart.split(':');
        final startDt = DateTime(
          slot.date.year, slot.date.month, slot.date.day,
          int.parse(parts[0]), int.parse(parts[1]),
        );
        slotDeadline = startDt.subtract(Duration(hours: _hoursBeforeStart));
      }

      await _firestoreService.updateSlotFull(
        toId: widget.to.id,
        slotId: slot.id,
        workDetails: _workDetails,
        applicationDeadline: slotDeadline,
        title: _slotTitleController.text.trim(),
        oldTotalRequired: slot.totalRequired,
      );

      _firestoreService.clearCache(toId: widget.to.id);
      ToastHelper.showSuccess('수정되었습니다');
      if (mounted) NavigationHelper.popWithChange(context);
    } catch (e) {
      debugPrint('❌ 슬롯 수정 실패: $e');
      ToastHelper.showError('수정에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveNewSlotChanges() async {
    try {
      await _firestoreService.addSlot(
        to: widget.to,
        date: widget.newSlotDate!,
        workDetails: _workDetails,
        hoursBeforeStart: _hoursBeforeStart,
        title: _slotTitleController.text.trim(),
      );
      _firestoreService.clearCache(toId: widget.to.id);
      ToastHelper.showSuccess(
          '${widget.newSlotDate!.month}/${widget.newSlotDate!.day} 날짜가 추가되었습니다');
      if (mounted) NavigationHelper.popWithChange(context);
    } catch (e) {
      debugPrint('❌ 날짜 추가 실패: $e');
      ToastHelper.showError('날짜 추가에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _saveBatchSlotChanges() async {
    try {
      final slots = widget.batchSlots!;

      await Future.wait(slots.map((slot) async {
        DateTime? slotDeadline;
        if (_workDetails.isNotEmpty) {
          final earliestStart =
              (_workDetails.map((d) => d.startTime).toList()..sort()).first;
          final parts = earliestStart.split(':');
          final startDt = DateTime(
            slot.date.year, slot.date.month, slot.date.day,
            int.parse(parts[0]), int.parse(parts[1]),
          );
          slotDeadline = startDt.subtract(Duration(hours: _hoursBeforeStart));
        }
        await _firestoreService.updateSlotFull(
          toId: widget.to.id,
          slotId: slot.id,
          workDetails: _workDetails,
          applicationDeadline: slotDeadline,
          oldTotalRequired: slot.totalRequired,
        );
      }));

      _firestoreService.clearCache(toId: widget.to.id);
      ToastHelper.showSuccess('${slots.length}개 날짜가 수정되었습니다');
      if (mounted) NavigationHelper.popWithChange(context);
    } catch (e) {
      debugPrint('❌ 일괄 슬롯 수정 실패: $e');
      ToastHelper.showError('수정에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ============================================================
  // 업무 관리 — Firestore 서브컬렉션 없이 로컬 리스트만 수정 후 저장 시 반영
  // ============================================================

  Future<void> _showAddWorkDialog() async {
    final result = await WorkDetailDialog.showAddDialog(
      context: context,
      businessWorkTypes: _businessWorkTypes,
    );
    if (result != null) {
      setState(() {
        _workDetails.add(WorkDetailData(
          workType: result.workType!,
          workTypeIcon: result.workTypeIcon,
          workTypeColor: result.workTypeColor,
          workTypeBackgroundColor: result.workTypeBackgroundColor ?? '#E3F2FD',
          wage: result.wage!,
          wageType: result.wageType,
          requiredCount: result.requiredCount!,
          startTime: result.startTime!,
          endTime: result.endTime!,
          order: _workDetails.length,
        ));
      });
      ToastHelper.showInfo('업무가 추가되었습니다 (저장 버튼을 눌러주세요)');
    }
  }

  Future<void> _showEditWorkDialog(WorkDetailData work) async {
    final result = await WorkDetailDialog.showEditDialog(
      context: context,
      work: work,
      businessWorkTypes: _businessWorkTypes,
    );
    if (result != null) {
      final index = _workDetails.indexOf(work);
      if (index != -1) {
        setState(() {
          _workDetails[index] = _workDetails[index].copyWith(
            workType: result['workType'],
            workTypeIcon: result['workTypeIcon'],
            workTypeColor: result['workTypeColor'],
            workTypeBackgroundColor: result['workTypeBackgroundColor'],
            wage: result['wage'],
            wageType: result['wageType'],
            requiredCount: result['requiredCount'],
            startTime: result['startTime'],
            endTime: result['endTime'],
          );
        });
      }
      ToastHelper.showInfo('업무가 수정되었습니다 (저장 버튼을 눌러주세요)');
    }
  }

  Future<void> _deleteWork(WorkDetailData work) async {
    final confirmed = await _showDeleteConfirmDialog(work);
    if (confirmed == true) {
      setState(() => _workDetails.remove(work));
      ToastHelper.showInfo('업무가 삭제되었습니다 (저장 버튼을 눌러주세요)');
    }
  }

  // ============================================================
  // UI 빌드
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final d = widget.newSlotDate;
    final appBarTitle = widget.isNewSlot
        ? '${d!.month}/${d.day} 날짜 추가'
        : widget.isBatchMode
            ? '${widget.batchSlots!.length}개 날짜 일괄수정'
            : widget.slot != null
                ? '${widget.slot!.formattedDate} 수정'
                : 'TO 수정';

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(appBarTitle)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(appBarTitle)),
      body: Container(
        color: AppColors.grey50,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: ResponsiveHelper.cardPadding(context),
            children: [
              if (widget.isNewSlot) ...[
                _buildNewSlotBanner(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              ] else if (widget.isBatchMode) ...[
                _buildBatchInfoBanner(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              ],
              // 슬롯 개별 공고 제목 (단일 슬롯 수정 or 새 날짜 추가)
              if (widget.slot != null || widget.isNewSlot) ...[
                _buildSlotTitleField(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              ],
              if (!widget.isSlotMode) ...[
                TODateSelector(
                  isLongTerm: widget.to.isContractType,
                  isReadOnly: true,
                  rangeStart: widget.to.rangeStart,
                  rangeEnd: widget.to.rangeEnd,
                  displayWorkDays: widget.to.workDays,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                TOTitleSection(titleController: _titleController),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              ],

              TOWorkDetailsSection(
                workDetailData: _workDetails,
                onAddWork: _showAddWorkDialog,
                onEditWorkData: _showEditWorkDialog,
                onDeleteWorkData: _deleteWork,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              TODeadlineSection(
                isLongTerm: widget.isSlotMode ? false : widget.to.isContractType,
                hoursBeforeStart: _hoursBeforeStart,
                onHoursChanged: (h) => setState(() => _hoursBeforeStart = h),
                fixedDeadline: widget.isSlotMode ? null : _fixedDeadline,
                onFixedDeadlineChanged: widget.isSlotMode
                    ? null
                    : (dt) => setState(() => _fixedDeadline = dt),
                rangeStartDate: widget.isSlotMode ? null : widget.to.rangeStart,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),

              if (!widget.isSlotMode) ...[
                TOPublishSection(
                  publishMode: _publishMode,
                  onPublishModeChanged: (m) => setState(() => _publishMode = m),
                  publishDaysBefore: _publishDaysBefore,
                  onDaysBeforeChanged: (d) =>
                      setState(() => _publishDaysBefore = d),
                  publishTime: _publishTime,
                  onTimeChanged: (t) => setState(() => _publishTime = t),
                  previewDates: widget.to.isContractType
                      ? (widget.to.rangeStart != null ? [widget.to.rangeStart!] : [])
                      : (_firstSlotDate != null ? [_firstSlotDate!] : []),
                  isLongTerm: widget.to.isContractType,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                TODescriptionSection(controller: _descriptionController),
                SizedBox(height: ResponsiveHelper.spacing(context, 24)),
              ],

              TOActionButton.save(
                onPressed: _saveChanges,
                isLoading: _isSaving,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 40)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSlotTitleField(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '공고 제목',
            style: ResponsiveHelper.subtitleStyle(context)
                .copyWith(fontWeight: FontWeight.bold),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          TextFormField(
            controller: _slotTitleController,
            style: ResponsiveHelper.bodyStyle(context),
            decoration: InputDecoration(
              hintText: '이 날짜의 공고 제목을 입력하세요',
              hintStyle: ResponsiveHelper.smallStyle(
                  context, color: AppColors.grey400),
              prefixIcon: Icon(Icons.title,
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 22)),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.grey300)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.grey300)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      BorderSide(color: theme.primaryColor, width: 2)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewSlotBanner(BuildContext context) {
    final d = widget.newSlotDate!;
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final label = '${d.month}/${d.day} (${weekdays[d.weekday - 1]})';
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Row(
        children: [
          Icon(Icons.event_available,
              size: ResponsiveHelper.iconSize(context, 16),
              color: AppColors.infoDark),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              '$label 날짜 추가 — 업무 내용을 확인 후 저장하세요',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchInfoBanner(BuildContext context) {
    final slots = widget.batchSlots!;
    final dateLabels = slots.map((s) => s.formattedDate).join(', ');
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
        border: Border.all(color: AppColors.warningLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: AppColors.warningDark),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '${slots.length}개 날짜 일괄 수정',
                style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.warningDark)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          Text(
            '선택한 모든 날짜에 동일하게 적용됩니다.\n$dateLabels',
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.warningDark),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showDeleteConfirmDialog(WorkDetailData work) {
    return showDialog<bool>(
      context: context,
      builder: (context) => StyledDialog(
        title: '업무 삭제',
        subtitle: '${work.workType} 업무를 삭제하시겠습니까?',
        icon: Icons.delete_outline,
        headerColor: AppColors.error,
        content: const SizedBox.shrink(),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context, false),
          ),
          StyledDialogButton.danger(
            text: '삭제',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );
  }
}
