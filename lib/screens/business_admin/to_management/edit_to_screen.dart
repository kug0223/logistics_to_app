import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

// Models
import '../../../models/core/to_model.dart';
import '../../../models/core/slot_model.dart';
import '../../../models/core/work_detail_data.dart';
import '../../../models/core/business_work_type_model.dart';
import '../../../models/core/application_model.dart';

// Services
import '../../../services/firestore_service.dart';

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

  bool _isLoading = false; // initState → _loadData() 가드 통과를 위해 false 초기화
  bool _isSaving = false;
  bool _hasChanges = false;
  List<WorkDetailData> _workDetails = [];
  List<WorkDetailData> _originalWorkDetails = [];
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
    _fixedDeadline = widget.to.isContractType ? null : widget.to.applicationDeadline;
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
    if (_isLoading) return;
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
        final batchWork = List<WorkDetailData>.from(batchSlots.first.workDetails);
        setState(() {
          _workDetails = batchWork;
          _originalWorkDetails = List<WorkDetailData>.from(batchWork);
          _businessWorkTypes = workTypes;
          _isLoading = false;
        });
        return;
      }

      if (widget.slot != null) {
        _slotTitleController.text = widget.slot!.title ?? widget.to.title;
        final slotWork = List<WorkDetailData>.from(widget.slot!.workDetails);
        setState(() {
          _workDetails = slotWork;
          _originalWorkDetails = List<WorkDetailData>.from(slotWork);
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
        final newSlotWork = List<WorkDetailData>.from(
            template?.workDetails ?? widget.to.workDetails);
        setState(() {
          _workDetails = newSlotWork;
          _originalWorkDetails = List<WorkDetailData>.from(newSlotWork);
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

      final masterWork = List<WorkDetailData>.from(widget.to.workDetails);
      setState(() {
        _workDetails = masterWork;
        _originalWorkDetails = List<WorkDetailData>.from(masterWork);
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
    if (_isSaving) return; // WAGE-GUARD 다이얼로그 대기 중 중복 저장 방지
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 공통 업무상세 검증 (슬롯/TO 모두)
    if (_workDetails.isEmpty) {
      ToastHelper.showError('최소 1개의 업무를 추가해주세요');
      return;
    }
    if (_workDetails.any((w) => w.wage <= 0)) {
      ToastHelper.showError('급여는 0원보다 커야 합니다');
      return;
    }
    // 최저임금(2026: 10,320원) 미달 여부를 앱에서 하드 차단하지 않는다.
    // 임금 결정은 사업주 권한이며, 수습·단순가산 등 예외 케이스가 다양하다.
    // 최저임금법 준수 책임은 사업주에게 있고, 앱은 경영 도구로서 개입하지 않는다.
    if (_workDetails.any((w) => w.requiredCount <= 0)) {
      ToastHelper.showError('필요 인원은 1명 이상이어야 합니다');
      return;
    }


    // [WAGE-GUARD] 임금 관련 필드가 실제로 변경됐을 때만 경고 표시
    // draft 제외 의도: TO 최초 공개 전 draft 수정에는 확정 근무자가 없으므로 경고 불필요.
    // 단, slot != null이면 이미 공개된 슬롯을 수정하는 것이므로 확정 근무자가 존재할 수 있음.
    final isExistingSlotEdit = widget.slot != null || widget.isBatchMode;

    setState(() { _isSaving = true; _hasChanges = false; });

    try {
      if (!widget.isNewSlot &&
          (_publishMode != 'draft' || isExistingSlotEdit) &&
          _hasWageFieldsChanged()) {
        final proceed = await _showWageGuardWarning();
        if (!mounted) return;
        if (!proceed) {
          // [M1-FIX] WAGE-GUARD 취소 시 _hasChanges 복원 — finally가 _isSaving만 복원하므로
          // _hasChanges = false가 유지되면 PopScope.canPop이 true가 되어 미저장 경고 없이 이탈.
          setState(() => _hasChanges = true);
          return;
        }
      }
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
          'publishAt': null,  // null → CF가 FieldValue.delete() 처리
          'title': _titleController.text.trim(),
          'description': _descriptionController.text.trim(),
          'workDetails': WorkDetailData.listToFirestore(_workDetails),
          'postingDurationDays': _postingDurationDays,
          'hoursBeforeStart': _hoursBeforeStart,
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
        if (timeParts.length < 2) {
          ToastHelper.showError('공개 시간 형식이 올바르지 않습니다 (HH:mm)');
          return;
        }
        publishAt = DateTime(
          targetDate.year,
          targetDate.month,
          targetDate.day,
          int.tryParse(timeParts[0]) ?? 0,
          int.tryParse(timeParts[1]) ?? 0,
        );
        if (publishAt.isBefore(DateTime.now())) {
          shouldPublishImmediately = true;
          publishAt = null;
          ToastHelper.showInfo('공개 예정 시간이 지나 즉시 공개로 전환됩니다');
        }
      }

      // flex TO는 슬롯 수 × 슬롯당 요구인원; contract TO는 슬롯 1개 구조이므로 합산만
      final perSlotRequired =
          _workDetails.fold<int>(0, (s, d) => s + d.requiredCount);
      // [M-15] totalSlots 스테일 방지 — 저장 직전 서버 최신값 조회 (flex TO만)
      int freshTotalSlots = widget.to.totalSlots;
      if (!widget.to.isContractType) {
        final freshToSnap = await FirebaseFirestore.instance
            .collection('tos')
            .doc(widget.to.id)
            .get(const GetOptions(source: Source.server));
        freshTotalSlots = (freshToSnap.data()?['totalSlots'] as int?) ?? widget.to.totalSlots;
        if (!mounted) return;
      }
      final numSlots = widget.to.isContractType ? 1 : (freshTotalSlots > 0 ? freshTotalSlots : 1);
      final totalRequired = perSlotRequired * numSlots;

      // isManualClosed가 아닌 isClosed 기준 — CF 자동마감(isManualClosed=false) 포함
      final wasClosed = widget.to.isClosed;
      // [PUB-CF] 첫 공개 전환은 callablePublishTO CF로 처리 (maxActiveTOs 서버 강제)
      final shouldPublish = shouldPublishImmediately && !widget.to.isPublished;

      // workDetails(임금 포함)를 통째로 덮어씀 → 이미 확정된 지원자가 있어도
      // 슬롯의 wage 수정이 가능하다. CLAUDE.md "시급/일급 TO 레벨에서 고정" 원칙은
      // application 스냅샷(지원 시점 복사)으로 보호되나, 슬롯 기준 wage 재조회가 일어날 경우
      // 불일치 발생 가능. 확정 지원자가 있고 임금 필드가 실제 변경된 경우 WAGE-GUARD 경고 발동됨.
      final updates = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        'workDetails': WorkDetailData.listToFirestore(_workDetails),
        'totalRequired': totalRequired,
        'hoursBeforeStart': _hoursBeforeStart,
        'publishMode': _publishMode,
        // null → CF가 FieldValue.delete() 처리; ms epoch → CF가 Timestamp 변환
        'publishAt': publishAt?.toUtc().millisecondsSinceEpoch,
        // 첫 공개(shouldPublish=true)는 callablePublishTO CF가 처리 — 여기선 제외
        if (!shouldPublish) 'isPublished': shouldPublishImmediately,
        'publishDaysBefore':
            _publishMode == 'scheduled' ? _publishDaysBefore : null,
        'publishTime': _publishMode == 'scheduled' ? _publishTime : null,
        'postingDurationDays': _postingDurationDays,
        // 재개: isManualClosed=false 전달 → CF가 reopenedBy/reopenedAt/closedAt/closedBy 처리
        if (wasClosed) ...{
          'isManualClosed': false,
          'status': TOStatus.active,
        },
      };

      if (widget.to.isContractType) {
        // 고정근무는 지원마감 없음 — null → CF가 FieldValue.delete() 처리
        updates['applicationDeadline'] = null;
      }

      await _firestoreService.updateTO(widget.to.id, updates);

      // [PUB-CF] 첫 공개: CF callablePublishTO (maxActiveTOs 서버 강제)
      if (shouldPublish) {
        try {
          await _firestoreService.publishTO(widget.to.id);
        } on Exception catch (e) {
          if (e.toString().contains('MAX_ACTIVE_TO_LIMIT')) {
            final parts = e.toString().split(':');
            final limitStr = parts.length >= 2 ? parts.last : '4';
            if (mounted) ToastHelper.showError('진행 중인 공고가 $limitStr개를 초과할 수 없습니다');
          } else {
            if (mounted) ToastHelper.showError('공개 전환에 실패했습니다. 잠시 후 다시 시도해주세요');
          }
          if (mounted) setState(() => _isSaving = false);
          return;
        }
        if (!mounted) return;
      }

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

      if (!mounted) return;
      if (slotSyncFailed) {
        ToastHelper.showWarning('TO가 수정되었으나 슬롯 동기화에 실패했습니다. 다시 저장해 주세요.');
        // 슬롯 동기화 실패 시 화면에 남아 재저장 가능하도록 팝하지 않음
        setState(() => _hasChanges = true);
      } else {
        ToastHelper.showSuccess('TO가 수정되었습니다');
        NavigationHelper.popWithChange(context);
      }
    } catch (e) {
      debugPrint('❌ TO 수정 실패: $e');
      if (mounted) ToastHelper.showError('수정에 실패했습니다');
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
          int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0,
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
        if (!await _applyTODraftTransition(visibleFrom)) return;
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
      if (!mounted) return;
      ToastHelper.showSuccess('수정되었습니다');
      NavigationHelper.popWithChange(context);
    } catch (e) {
      debugPrint('❌ 슬롯 수정 실패: $e');
      if (mounted) ToastHelper.showError('수정에 실패했습니다');
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
        int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0,
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

  // [WAGE-GUARD] TO workDetails 변경 전 미확정 근무자 경고 다이얼로그
  // wageType·breakMinutes·야간설정은 저장 시점 TO값 재참조 — 확정 전 근무자 급여에 영향
  bool _hasWageFieldsChanged() {
    if (_workDetails.length != _originalWorkDetails.length) return true;
    for (int i = 0; i < _workDetails.length; i++) {
      final cur = _workDetails[i];
      final orig = _originalWorkDetails[i];
      if (cur.wage != orig.wage ||
          cur.wageType != orig.wageType ||
          cur.breakMinutes != orig.breakMinutes ||
          cur.nightAllowanceApplied != orig.nightAllowanceApplied ||
          cur.nightIncluded != orig.nightIncluded ||
          cur.baseHourlyWage != orig.baseHourlyWage ||
          cur.taxDeductionType != orig.taxDeductionType) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _showWageGuardWarning() async {
    try {
      // [CF 이전 2026-07-13] callableGetApplicationsByBiz (Admin SDK, businessId+toId)
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetApplicationsByBiz',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
      final result = await callable.call<Map<String, dynamic>>({
        'businessId': widget.to.businessId,
        'toId': widget.to.id,
        'limit': 2000,
      });
      final appsRaw = (result.data['applications'] as List? ?? [])
          .whereType<Map>()
          .toList();
      const confirmedStatuses = [AppStatus.confirmed, AppStatus.contractPending];
      final hasConfirmed = appsRaw.any(
          (m) => confirmedStatuses.contains(m['status']));
      if (!hasConfirmed) return true; // 미확정 근무자 없음 — 경고 불필요
    } catch (e) {
      debugPrint('⚠️ WAGE-GUARD 쿼리 실패 (진행 허용): $e');
      return true; // 조회 실패 시 강제 차단 금지
    }

    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StyledDialog(
        title: '급여 계산 조건 변경',
        subtitle: '이 공고에 확정된 근무자가 있습니다',
        icon: Icons.warning_amber_rounded,
        headerColor: AppColors.warning,
        content: Text(
          '급여 유형·휴게시간·야간 설정을 변경하면\n미확정 급여 계산에 영향을 줄 수 있습니다.\n\n계속 저장하시겠습니까?',
          style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700),
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(ctx, false),
          ),
          StyledDialogButton.primary(
            text: '계속 저장',
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
        if (!await _applyTODraftTransition(newSlotVisibleFrom)) return;
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
      if (!mounted) return;
      ToastHelper.showSuccess(
          '${widget.newSlotDate!.month}/${widget.newSlotDate!.day} 날짜가 추가되었습니다');
      NavigationHelper.popWithChange(context);
    } catch (e) {
      debugPrint('❌ 날짜 추가 실패: $e');
      if (mounted) ToastHelper.showError('날짜 추가에 실패했습니다');
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
        if (!await _applyTODraftTransition(anyImmediate ? null : earliestVisibleFrom)) return;
      }

      final firestore = FirebaseFirestore.instance;
      final batch = firestore.batch();
      int totalRequiredDelta = 0;

      // [V7-FIX] 동시 편집 방지: 슬롯 workDetails를 Firestore에서 신선 조회해 정확한 delta 계산
      //   스크린 로드 이후 다른 관리자가 같은 슬롯을 수정하면 로컬 totalRequired가 스테일해짐.
      final freshSnaps = await Future.wait(
        slots.map((s) => firestore
            .collection('tos').doc(widget.to.id)
            .collection('slots').doc(s.id)
            .get(const GetOptions(source: Source.server))),
      );
      if (!mounted) return;
      final freshSlotRequired = <String, int>{};
      for (final snap in freshSnaps) {
        if (snap.exists) {
          final details = (snap.data()?['workDetails'] as List? ?? []);
          freshSlotRequired[snap.id] = details.fold<int>(
            0, (acc, d) => acc + ((d as Map)['requiredCount'] as int? ?? 0));
        }
      }

      for (final slot in slots) {
        final updatedWorkDetails = _workDetails.map((work) {
          final parts = work.startTime.split(':');
          if (parts.length != 2) return work;
          final deadline = DateTime(
            slot.date.year, slot.date.month, slot.date.day,
            int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0,
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
        final newTotalRequired = updatedWorkDetails.fold<int>(0, (s, d) => s + d.requiredCount);

        final slotRef = firestore
            .collection('tos').doc(widget.to.id)
            .collection('slots').doc(slot.id);
        batch.update(slotRef, {
          'workDetails': WorkDetailData.listToFirestore(updatedWorkDetails),
          'applicationDeadline': slotDeadline != null
              ? Timestamp.fromDate(slotDeadline.toUtc())
              : FieldValue.delete(),
          if (clearVisibleFrom) 'visibleFrom': FieldValue.delete()
          else if (visibleFrom != null) 'visibleFrom': Timestamp.fromDate(visibleFrom.toUtc()),
        });

        final currentRequired = freshSlotRequired[slot.id] ?? slot.totalRequired;
        if (currentRequired != newTotalRequired) {
          totalRequiredDelta += newTotalRequired - currentRequired;
        }
      }

      // TO의 totalRequired 동기화
      if (totalRequiredDelta != 0) {
        batch.update(firestore.collection('tos').doc(widget.to.id), {
          'totalRequired': FieldValue.increment(totalRequiredDelta),
        });
      }

      await batch.commit();

      _firestoreService.clearCache(toId: widget.to.id);
      if (!mounted) return;
      ToastHelper.showSuccess('${slots.length}개 날짜가 수정되었습니다');
      NavigationHelper.popWithChange(context);
    } catch (e) {
      debugPrint('❌ 일괄 슬롯 수정 실패: $e');
      if (mounted) ToastHelper.showError('수정에 실패했습니다');
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
    if (result != null && mounted) {
      setState(() {
        _hasChanges = true; // [B-4] workDetails 변경 감지
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
    if (result != null && mounted) {
      final index = _workDetails.indexOf(work);
      if (index != -1) {
        setState(() {
          _hasChanges = true; // [B-4] workDetails 변경 감지
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
    if (confirmed == true && mounted) {
      setState(() { _hasChanges = true; _workDetails.remove(work); }); // [B-4] workDetails 변경 감지
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
                : '공고 수정';

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
    if (parts.length < 2) return (null, true);
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

  /// TO가 draft일 때 공개 설정에 따라 자동 전환.
  /// [H1-FIX] draft→active 한도 우회 차단 — _applyTODraftTransition 경로에서도 assertActiveTOLimit 체크
  /// 반환값: true = 전환 성공(또는 예약 설정), false = 한도 초과로 차단됨
  Future<bool> _applyTODraftTransition(DateTime? visibleFrom) async {
    if (visibleFrom == null) {
      // [PUB-CF] draft → 즉시공개(active) 전환: CF callablePublishTO (maxActiveTOs 서버 강제)
      try {
        await _firestoreService.publishTO(widget.to.id);
      } on FirebaseFunctionsException catch (fe) {
        if (mounted) ToastHelper.showError('공고를 공개할 수 없습니다: ${fe.message ?? ''}');
        return false;
      } on Exception catch (e) {
        if (e.toString().contains('MAX_ACTIVE_TO_LIMIT')) {
          final parts = e.toString().split(':');
          final limitStr = parts.length >= 2 ? parts.last : '4';
          if (mounted) ToastHelper.showError('진행 중인 공고가 $limitStr개를 초과할 수 없습니다');
        } else {
          if (mounted) ToastHelper.showError('공고를 공개할 수 없습니다');
        }
        return false;
      }
      if (!mounted) return false;
      if (mounted) ToastHelper.showInfo('미공개 공고가 즉시 공개로 전환되었습니다');
    } else {
      final m = visibleFrom.month;
      final d = visibleFrom.day;
      final h = visibleFrom.hour.toString().padLeft(2, '0');
      final min = visibleFrom.minute.toString().padLeft(2, '0');
      await _firestoreService.updateTO(widget.to.id, {
        'publishMode': 'scheduled',
        'publishAt': visibleFrom.toUtc().millisecondsSinceEpoch,  // ms → CF가 Timestamp 변환
        'isPublished': false,
        'status': TOStatus.scheduled,
      });
      if (mounted) ToastHelper.showInfo('미공개 → 예약공개 전환 ($m/$d $h:$min 공개 예정)');
    }
    return true;
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
