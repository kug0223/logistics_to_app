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
import '../../../utils/format_helper.dart';
import '../../../utils/dialog_helper.dart';

// Widgets
import '../../../widgets/pickers/create_edit_work_detail_dialog.dart';
import '../../../widgets/dialogs/styled_dialog.dart';

// 공통 위젯
import 'widgets/to_widgets.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/gradient_scaffold.dart';
import '../../../widgets/common/loading_widget.dart';

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
  bool _hasChanges = false;
  List<WorkDetailData> _workDetails = [];
  List<BusinessWorkTypeModel> _businessWorkTypes = [];
  DateTime? _firstSlotDate; // 단기 TO 예약 공개 기준일용

  int _hoursBeforeStart = 2;
  DateTime? _fixedDeadline;

  String _publishMode = 'immediate';
  int _publishDaysBefore = 1;
  String _publishTime = '14:00';
  int? _postingDurationDays;
  // 슬롯 모드에서 draft TO의 공개 설정을 실제로 변경했는지 추적
  bool _slotPublishChanged = false;

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
    _postingDurationDays = widget.to.postingDurationDays;

    // 슬롯 모드: 슬롯의 visibleFrom 기반으로 공개 설정 초기화
    if (widget.isSlotMode) {
      final slot = widget.slot;
      if (slot?.visibleFrom != null) {
        _publishMode = 'scheduled';
        final vf = slot!.visibleFrom!;
        final diff = slot.date.difference(DateTime(vf.year, vf.month, vf.day)).inDays;
        _publishDaysBefore = diff.clamp(1, 14);
        _publishTime = '${vf.hour.toString().padLeft(2, '0')}:${vf.minute.toString().padLeft(2, '0')}';
      } else {
        // draft면 즉시공개로, 아니면 TO 설정 유지
        if (widget.to.publishMode == 'draft') _publishMode = 'immediate';
      }
    }
    _titleController.addListener(_markChanged);
    _descriptionController.addListener(_markChanged);
    _loadData();
  }

  void _markChanged() {
    if (!_hasChanges) setState(() => _hasChanges = true);
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

      if (!mounted) return;

      if (widget.isBatchMode) {
        final batchSlots = widget.batchSlots;
        if (batchSlots == null || batchSlots.isEmpty) {
          setState(() => _isLoading = false);
          return;
        }
        setState(() {
          _workDetails = List<WorkDetailData>.from(batchSlots.first.workDetails);
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
        if (!mounted) return;
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
        if (!mounted) return;
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
      if (mounted) ToastHelper.showError('데이터를 불러오는데 실패했습니다');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ============================================================
  // 저장 — TO 문서의 workDetails 배열을 통째로 업데이트
  // ============================================================

  Future<void> _saveChanges() async {
    if (!_formKey.currentState!.validate()) return;

    // 공통 업무상세 검증 (슬롯/TO 모두)
    if (_workDetails.isEmpty) {
      ToastHelper.showError('최소 1개의 업무를 추가해주세요');
      return;
    }
    if (_workDetails.any((w) => w.wage <= 0)) {
      ToastHelper.showError('급여는 0원보다 커야 합니다');
      return;
    }
    if (_workDetails.any((w) => w.requiredCount <= 0)) {
      ToastHelper.showError('필요 인원은 1명 이상이어야 합니다');
      return;
    }

    setState(() { _isSaving = true; _hasChanges = false; });

    try {
      // ── 슬롯 수정 모드 ──────────────────────────────────────
      if (widget.isNewSlot) {
        if (_isNewSlotDeadlineExpired()) {
          final proceed = await _showExpiredDeadlineWarning();
          if (!mounted) { _isSaving = false; return; }
          if (!proceed) {
            setState(() => _isSaving = false);
            return;
          }
        }
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

      // ── 미공개(draft) 처리 ───────────────────────────────────
      if (_publishMode == 'draft') {
        final draftUpdates = <String, dynamic>{
          'publishMode': 'draft',
          'isPublished': false,
          'status': TOStatus.draft,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
          'publishAt': FieldValue.delete(),
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'workDetails': WorkDetailData.listToFirestore(_workDetails),
          'postingDurationDays': _postingDurationDays,
        };
        await _firestoreService.updateTO(widget.to.id, draftUpdates);
        if (mounted) {
          ToastHelper.showSuccess('미공개로 저장되었습니다');
          NavigationHelper.popWithChange(context);
        }
        return;
      }

      // ── 공개 시각 계산 ──────────────────────────────────────
      // 이미 공개된 TO는 수정해도 비공개로 되돌리지 않음
      DateTime? publishAt;
      bool shouldPublishImmediately =
          widget.to.isPublished || _publishMode == 'immediate';

      if (!widget.to.isPublished && _publishMode == 'scheduled') {
        // 장기: rangeStart 기준 / 단기: 첫 슬롯 날짜 기준
        // _firstSlotDate null(슬롯 없음)이면 오늘 기준으로 예약 설정
        final refDate = widget.to.isContractType
            ? (widget.to.rangeStart ?? widget.to.createdAt)
            : (_firstSlotDate ?? DateTime.now());
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

      // isManualClosed가 아닌 isClosed 기준 — CF 자동마감(isManualClosed=false) 포함
      final wasClosed = widget.to.isClosed;

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
        'postingDurationDays': _postingDurationDays,
        // SCHEDULED → 즉시공개 전환 시 status도 함께 ACTIVE로 갱신
        if (shouldPublishImmediately && !widget.to.isPublished) ...{
          'status': TOStatus.active,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        },
        if (wasClosed) ...{
          'isManualClosed': false,
          'closedAt': FieldValue.delete(),
          'closedBy': FieldValue.delete(),
          'status': TOStatus.active,
          'statusUpdatedAt': FieldValue.serverTimestamp(),
        },
      };

      if (widget.to.isContractType && _fixedDeadline != null) {
        updates['applicationDeadline'] =
            Timestamp.fromDate(_fixedDeadline!.toUtc());
      }

      if (wasClosed) {
        final userProvider = Provider.of<UserProvider>(context, listen: false);
        updates['reopenedBy'] = userProvider.currentUser?.uid;
        updates['reopenedAt'] = FieldValue.serverTimestamp();
      }

      await _firestoreService.updateTO(widget.to.id, updates);

      // ── 단기 TO: 슬롯 일괄 갱신 ──────────────────────────────
      // updateTO가 이미 커밋됐으므로 슬롯 동기화 실패는 별도 처리
      bool slotSyncFailed = false;
      if (!widget.to.isContractType) {
        try {
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

          // 슬롯 workDetails 항상 동기화
          // 외부(Firestore 콘솔 등)에서 hoursBeforeStart 변경 시 조건 감지 불가하므로
          // 저장 시 무조건 전체 동기화로 deadline 불일치 방지
          await _firestoreService.updateSlotsDeadlines(
            toId: widget.to.id,
            deadlineType: 'HOURS_BEFORE',
            hoursBeforeStart: _hoursBeforeStart,
            newWorkDetails: _workDetails,
          );
        } catch (e) {
          debugPrint('⚠️ 슬롯 동기화 실패 (TO는 저장됨): $e');
          slotSyncFailed = true;
        }
      }

      _firestoreService.clearCache(toId: widget.to.id);

      if (slotSyncFailed) {
        ToastHelper.showWarning('TO가 수정되었으나 슬롯 동기화에 실패했습니다. 다시 저장해 주세요.');
      } else {
        ToastHelper.showSuccess('TO가 수정되었습니다');
      }
      if (mounted) NavigationHelper.popWithChange(context);
    } catch (e) {
      debugPrint('❌ TO 수정 실패: $e');
      ToastHelper.showError('수정에 실패했습니다');
      if (mounted) setState(() => _hasChanges = true);
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

      // 업무별 applicationDeadline 재계산 (슬롯 수정으로 추가된 업무도 deadline 누락 방지)
      DateTime? slotDeadline;
      final updatedWorkDetails = _workDetails.map((work) {
        final parts = work.startTime.split(':');
        if (parts.length != 2) return work;
        final deadline = DateTime(
          slot.date.year, slot.date.month, slot.date.day,
          int.parse(parts[0]), int.parse(parts[1]),
        ).subtract(Duration(hours: _hoursBeforeStart));
        return work.copyWith(applicationDeadline: deadline);
      }).toList();

      // 슬롯 레벨 마감 = 가장 이른 업무 마감
      final deadlines = updatedWorkDetails
          .map((d) => d.applicationDeadline)
          .whereType<DateTime>()
          .toList();
      if (deadlines.isNotEmpty) {
        slotDeadline = deadlines.reduce((a, b) => a.isBefore(b) ? a : b);
      }

      // 슬롯 visibleFrom 계산
      final (visibleFrom, clearVisibleFrom) = _calcSlotVisibleFrom(slot.date);

      // 공개 설정을 명시적으로 변경했을 때만 draft TO 자동 전환
      if (_slotPublishChanged && widget.to.publishMode == 'draft') {
        await _applyTODraftTransition(visibleFrom);
      }

      await _firestoreService.updateSlotFull(
        toId: widget.to.id,
        slotId: slot.id,
        workDetails: updatedWorkDetails,
        applicationDeadline: slotDeadline,
        title: _slotTitleController.text.trim(),
        oldTotalRequired: slot.totalRequired,
        visibleFrom: visibleFrom,
        clearVisibleFrom: clearVisibleFrom,
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

  /// 새 슬롯의 모든 업무 마감시각이 이미 지났는지 확인
  bool _isNewSlotDeadlineExpired() {
    final slotDate = widget.newSlotDate;
    if (slotDate == null || _workDetails.isEmpty) return false;
    final now = DateTime.now();
    if (!DateUtils.isSameDay(slotDate, now)) return false;
    return _workDetails.every((d) {
      final parts = d.startTime.split(':');
      if (parts.length != 2) return false;
      final deadline = DateTime(
        slotDate.year, slotDate.month, slotDate.day,
        int.parse(parts[0]), int.parse(parts[1]),
      ).subtract(Duration(hours: _hoursBeforeStart));
      return now.isAfter(deadline);
    });
  }

  /// 마감 경과 경고 다이얼로그 — true: 그래도 등록, false: 취소
  Future<bool> _showExpiredDeadlineWarning() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StyledDialog(
        title: '지원 마감 경과',
        subtitle: '선택한 근무 시간의 지원 마감이 이미 지났습니다',
        icon: Icons.timer_off_outlined,
        headerColor: AppColors.warning,
        content: Text(
          '등록 즉시 마감 상태가 됩니다.\n그래도 등록하시겠습니까?',
          style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700),
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(ctx, false),
          ),
          StyledDialogButton.primary(
            text: '등록',
            backgroundColor: AppColors.warning,
            onPressed: () => Navigator.pop(ctx, true),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _saveNewSlotChanges() async {
    try {
      final (newSlotVisibleFrom, _) = _calcSlotVisibleFrom(widget.newSlotDate!);

      // 공개 설정을 명시적으로 변경했을 때만 draft TO 자동 전환
      if (_slotPublishChanged && widget.to.publishMode == 'draft') {
        await _applyTODraftTransition(newSlotVisibleFrom);
      }
      await _firestoreService.addSlot(
        to: widget.to,
        date: widget.newSlotDate!,
        workDetails: _workDetails,
        hoursBeforeStart: _hoursBeforeStart,
        title: _slotTitleController.text.trim(),
        visibleFrom: newSlotVisibleFrom,
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

      // 공개 설정을 명시적으로 변경했을 때만 draft TO 자동 전환 (이중 호출 방지를 위해 결과 캐싱)
      if (_slotPublishChanged && widget.to.publishMode == 'draft') {
        final visibleFroms = slots.map((s) => _calcSlotVisibleFrom(s.date).$1).toList();
        final anyImmediate = visibleFroms.any((vf) => vf == null);
        final earliestVisibleFrom = visibleFroms
            .whereType<DateTime>()
            .fold<DateTime?>(null, (e, vf) => e == null || vf.isBefore(e) ? vf : e);
        await _applyTODraftTransition(anyImmediate ? null : earliestVisibleFrom);
      }

      int successCount = 0;
      final failedSlots = <String>[];
      for (final slot in slots) {
        final updatedWorkDetails = _workDetails.map((work) {
          final parts = work.startTime.split(':');
          if (parts.length != 2) return work;
          final deadline = DateTime(
            slot.date.year, slot.date.month, slot.date.day,
            int.parse(parts[0]), int.parse(parts[1]),
          ).subtract(Duration(hours: _hoursBeforeStart));
          return work.copyWith(applicationDeadline: deadline);
        }).toList();

        DateTime? slotDeadline;
        if (updatedWorkDetails.isNotEmpty) {
          slotDeadline = updatedWorkDetails
              .where((d) => d.applicationDeadline != null)
              .map((d) => d.applicationDeadline!)
              .fold<DateTime?>(null, (earliest, dt) =>
                  earliest == null || dt.isBefore(earliest) ? dt : earliest);
        }

        final (visibleFrom, clearVisibleFrom) = _calcSlotVisibleFrom(slot.date);

        try {
          await _firestoreService.updateSlotFull(
            toId: widget.to.id,
            slotId: slot.id,
            workDetails: updatedWorkDetails,
            applicationDeadline: slotDeadline,
            oldTotalRequired: slot.totalRequired,
            visibleFrom: visibleFrom,
            clearVisibleFrom: clearVisibleFrom,
          );
          successCount++;
        } catch (e) {
          debugPrint('❌ 슬롯 [${slot.id}] 수정 실패: $e');
          failedSlots.add('${slot.date.month}/${slot.date.day}');
        }
      }
      if (failedSlots.isNotEmpty) {
        throw Exception('${failedSlots.join(', ')} 날짜 수정 실패 ($successCount/${slots.length}개 성공)');
      }

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
          shiftType: result.shiftType,
          nightAllowanceApplied: result.nightAllowanceApplied,
          nightIncluded: result.nightIncluded,
          breakMinutes: result.breakMinutes,
          baseHourlyWage: result.baseHourlyWage,
          payScheduleType: result.payScheduleType,
          payScheduleDay: result.payScheduleDay,
          payScheduleTime: result.payScheduleTime,
          taxDeductionType: result.taxDeductionType,
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
            shiftType: result['shiftType'],
            nightAllowanceApplied: result['nightAllowanceApplied'] ?? true,
            nightIncluded: result['nightIncluded'],
            breakMinutes: result['breakMinutes'],
            baseHourlyWage: result['baseHourlyWage'],
            clearBaseHourlyWage: result['baseHourlyWage'] == null,
            payScheduleType: result['payScheduleType'],
            clearPayScheduleType: result['payScheduleType'] == null,
            payScheduleDay: result['payScheduleDay'],
            clearPayScheduleDay: result['payScheduleDay'] == null,
            payScheduleTime: result['payScheduleTime'],
            clearPayScheduleTime: result['payScheduleTime'] == null,
            taxDeductionType: result['taxDeductionType'],
            description: result['description'],
            clearDescription: result['description'] == null,
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
      return GradientScaffold(
        title: appBarTitle,
        body: const LoadingWidget(),
      );
    }

    return PopScope(
      canPop: !_hasChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final nav = Navigator.of(context);
        final leave = await DialogHelper.showConfirm(
          context,
          title: '변경사항 취소',
          message: '저장하지 않은 변경사항이 있습니다.\n나가시겠습니까?',
          confirmText: '나가기',
          cancelText: '계속 수정',
          icon: Icons.exit_to_app_outlined,
        );
        if (leave && mounted) nav.pop();
      },
      child: GradientScaffold(
        title: appBarTitle,
        body: Form(
          key: _formKey,
          child: ListView(
            padding: ResponsiveHelper.listPadding(context),
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
                  contractPeriodType: widget.to.contractPeriodType,
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

              if (!widget.to.isContractType) ...[
                TODeadlineSection(
                  isLongTerm: false,
                  hoursBeforeStart: _hoursBeforeStart,
                  onHoursChanged: (h) => setState(() => _hoursBeforeStart = h),
                  fixedDeadline: _fixedDeadline,
                  onFixedDeadlineChanged: (dt) => setState(() => _fixedDeadline = dt),
                  rangeStartDate: null,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              ],

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
                  postingDurationDays: _postingDurationDays,
                  onPostingDurationChanged: (d) =>
                      setState(() => _postingDurationDays = d),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                TODescriptionSection(controller: _descriptionController),
                SizedBox(height: ResponsiveHelper.spacing(context, 24)),
              ],

              // 슬롯 모드: 개별/일괄 슬롯 공개 설정
              if (widget.isSlotMode) ...[
                if (widget.to.publishMode == 'draft')
                  _buildDraftWarningBanner(context),
                if (widget.to.publishMode == 'draft')
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                TOPublishSection(
                  slotMode: true,
                  publishMode: _publishMode,
                  onPublishModeChanged: (m) => setState(() {
                    _publishMode = m;
                    _slotPublishChanged = true;
                  }),
                  publishDaysBefore: _publishDaysBefore,
                  onDaysBeforeChanged: (d) => setState(() {
                    _publishDaysBefore = d;
                    _slotPublishChanged = true;
                  }),
                  publishTime: _publishTime,
                  onTimeChanged: (t) => setState(() {
                    _publishTime = t;
                    _slotPublishChanged = true;
                  }),
                  previewDates: widget.isBatchMode
                      ? widget.batchSlots!.map((s) => s.date).toList()
                      : widget.isNewSlot
                          ? [widget.newSlotDate!]
                          : (widget.slot != null ? [widget.slot!.date] : []),
                  isLongTerm: false,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 24)),
              ],

              TOActionButton.save(
                onPressed: _isSaving ? null : _saveChanges,
                isLoading: _isSaving,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 40)),
            ],
          ),
        ),
      ),
    );    // PopScope
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
    final label = '${d.month}/${d.day} (${FormatHelper.weekday(d)})';
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

  /// 슬롯 날짜 기준으로 visibleFrom 계산. (visibleFrom, clearVisibleFrom) 반환
  (DateTime?, bool) _calcSlotVisibleFrom(DateTime slotDate) {
    if (_publishMode != 'scheduled') return (null, true);
    final parts = _publishTime.split(':');
    var vf = DateTime(
      slotDate.year, slotDate.month, slotDate.day,
      int.parse(parts[0]), int.parse(parts[1]),
    ).subtract(Duration(days: _publishDaysBefore));
    if (vf.isBefore(DateTime.now())) {
      ToastHelper.showInfo('공개 예정 시간이 지나 즉시 공개로 전환됩니다');
      return (null, true);
    }
    return (vf, false);
  }

  /// TO가 draft일 때 공개 설정에 따라 자동 전환
  Future<void> _applyTODraftTransition(DateTime? visibleFrom) async {
    if (visibleFrom == null) {
      await _firestoreService.updateTO(widget.to.id, {
        'isPublished': true,
        'publishMode': 'immediate',
        'status': TOStatus.active,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      ToastHelper.showInfo('미공개 공고가 즉시 공개로 전환되었습니다');
    } else {
      final m = visibleFrom.month;
      final d = visibleFrom.day;
      final h = visibleFrom.hour.toString().padLeft(2, '0');
      final min = visibleFrom.minute.toString().padLeft(2, '0');
      await _firestoreService.updateTO(widget.to.id, {
        'publishMode': 'scheduled',
        'publishAt': Timestamp.fromDate(visibleFrom.toUtc()),
        'isPublished': false,
        'status': TOStatus.scheduled,
        'statusUpdatedAt': FieldValue.serverTimestamp(),
      });
      ToastHelper.showInfo('미공개 → 예약공개 전환 ($m/$d $h:$min 공개 예정)');
    }
  }

  Widget _buildDraftWarningBanner(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
        border: Border.all(color: AppColors.warningLight),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_off_outlined,
              size: ResponsiveHelper.iconSize(context, 16),
              color: AppColors.warningDark),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              '현재 공고가 미공개 상태입니다. 공개 설정 시 자동으로 전환됩니다.',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
            ),
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
