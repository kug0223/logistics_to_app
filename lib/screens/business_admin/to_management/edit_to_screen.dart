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
import '../../../utils/format_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/navigation_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';

// Widgets
import '../../../widgets/pickers/create_edit_work_detail_dialog.dart';
import '../../../widgets/dialogs/styled_dialog.dart';

// 공통 위젯
import 'widgets/to_widgets.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/common/app_page_scaffold.dart'; // PATCH-1 (ADMIN-DESIGN-5)
import '../../common/notification_screen.dart';
import '../../../widgets/common/notification_badge.dart';

/// [POSTING-V2-03G.1 TC2] 편집 화면이 지원 관계를 읽는 두 가지 방식.
///
/// 둘은 목적이 다르고, 그래서 신선도 요구도 다르다. 한 캐시로 합치면
/// 더 약한 쪽(안내)의 신선도가 더 강한 쪽(방어)에 그대로 적용된다.
///
/// · [advisory] — 업무를 바꾸려 할 때 미리 알려 주기 위한 조회.
///   낡아도 된다. 저장 시 서버가 같은 것을 다시 검사해 최종 판정하므로,
///   여기서 놓친 지원자는 서버가 잡는다. 세션 동안 재사용한다.
///
/// · [fresh] — 임금 경고처럼 **클라이언트가 마지막 방어선**인 판단.
///   FLEX 슬롯 임금에는 서버 가드가 없어서, 몇 분 전 스냅샷으로 "확정자
///   없음"이라고 판단하면 그 사이 확정된 근무자의 급여 조건이 경고 없이
///   바뀐다. 캐시가 있어도 매번 다시 읽는다.
@visibleForTesting
class EditApplicationRelations {
  EditApplicationRelations(this._fetch);

  final Future<List<Map<String, dynamic>>> Function() _fetch;

  List<Map<String, dynamic>>? _cached;

  /// 안내용 조회가 실패했다. 필드를 만질 때마다 재시도하지 않는다.
  /// [fresh]에는 적용되지 않는다 — 저장은 다시 눌러 볼 수 있어야 한다.
  bool _advisoryFailed = false;

  /// 세션 캐시를 쓰는 안내용 조회. 실패하면 null(= 안내 생략).
  Future<List<Map<String, dynamic>>?> advisory() async {
    final cached = _cached;
    if (cached != null) return cached;
    if (_advisoryFailed) return null;
    try {
      final apps = await _fetch();
      _cached = apps;
      return apps;
    } catch (e) {
      debugPrint('⚠️ 지원 현황 조회 실패 (사전 안내 생략): $e');
      _advisoryFailed = true;
      return null;
    }
  }

  /// 캐시를 건너뛰는 조회. 실패해도 기억하지 않는다 —
  /// 일시적 실패 뒤 사용자가 다시 저장을 누르면 다시 시도해야 한다.
  Future<List<Map<String, dynamic>>?> fresh() async {
    try {
      final apps = await _fetch();
      // 더 새 값이므로 안내용도 함께 갱신한다. 이전 실패도 해소된다.
      _cached = apps;
      _advisoryFailed = false;
      return apps;
    } catch (e) {
      debugPrint('⚠️ 지원 현황 조회 실패: $e');
      return null;
    }
  }
}

class AdminEditTOScreen extends StatefulWidget {
  final TOModel to;
  final SlotModel? slot;             // 단일 슬롯 수정
  final List<SlotModel>? batchSlots; // 배치 슬롯 수정 (일괄수정)
  const AdminEditTOScreen({
    super.key,
    required this.to,
    this.slot,
    this.batchSlots,
  });

  bool get isBatchMode => batchSlots != null && batchSlots!.isNotEmpty;
  bool get isSlotMode => slot != null || isBatchMode;

  @override
  State<AdminEditTOScreen> createState() => _AdminEditTOScreenState();
}

class _AdminEditTOScreenState extends State<AdminEditTOScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firestoreService = FirestoreService();

  // 섹션 스크롤용 GlobalKey (scroll-to-error)
  final _workDetailSectionKey = GlobalKey();

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

  // ── [POSTING-V2-03G.1] 업무 변경 사전 확인 ───────────────────────────
  //
  // 서버는 지원자가 걸린 업무의 구성 변경을 거부한다. 그런데 그 거부는
  // 관리자가 업무를 다 고치고 저장을 누른 뒤에야 나타났다.
  //
  // 화면에 들어왔다는 이유만으로 지원 현황을 조회하지는 않는다 — 제목만
  // 고치고 나가는 경우가 많고, 그 경우 조회는 순수한 낭비다. 업무를 실제로
  // 바꾸려는 첫 순간에 한 번만 읽고, 이 편집 세션 동안 재사용한다.
  late final EditApplicationRelations _applicationRelations =
      EditApplicationRelations(_fetchApplications);

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
        final diff = FormatHelper.toKstDate(slot.date).difference(FormatHelper.toKstDate(vf)).inDays;
        _publishDaysBefore = diff.clamp(1, 14);
        final vfKst = vf.toUtc().add(const Duration(hours: 9));
        _publishTime = '${vfKst.hour.toString().padLeft(2, '0')}:${vfKst.minute.toString().padLeft(2, '0')}';
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
      // getSlots는 batchMode·slot 지정·contractType 케이스에서 불필요하므로
      // 해당 조건이 아닌 경우에만 선제 시작하여 getBusinessWorkTypes와 병렬화
      final slotsFuture = (!widget.isBatchMode && widget.slot == null && !widget.to.isContractType)
          ? _firestoreService.getSlots(widget.to.id)
          : null;

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

      DateTime? firstSlotDate;
      if (slotsFuture != null) {
        final slots = await slotsFuture; // 이미 병렬로 실행 중
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
    // [UX-FIX 2026-08-10] 키보드 포커스 해제 — unfocus 없으면 Navigator.pop 후 _dependents.isEmpty crash
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    // 공통 업무상세 검증 (슬롯/TO 모두)
    if (_workDetails.isEmpty) {
      ToastHelper.showError('최소 1개의 업무를 추가해주세요');
      _scrollToSection(_workDetailSectionKey);
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
      if ((_publishMode != 'draft' || isExistingSlotEdit) &&
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
        await _firestoreService.updateTO(widget.to.id, draftUpdates,
            expectedEditRevision: widget.to.editRevision);
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
      // [POSTING-V2-03G.1] 업무를 건드리지 않았으면 payload에서 뺀다.
      //   서버의 확정자 guard는 값이 바뀌었는지가 아니라 `workDetails` 키가
      //   실렸는지를 본다. 늘 함께 보내던 탓에, 확정 근무자가 있는 공고는
      //   제목 한 글자만 고쳐도 '근무 조건은 수정할 수 없습니다'로 거부됐다.
      //   서버 정책은 그대로다 — 정책이 허용하는 수정을 실제로 가능하게 할 뿐이다.
      final workDetailsChanged = _hasWorkDetailsChanged();
      final updates = <String, dynamic>{
        'title': _titleController.text.trim(),
        'description': _descriptionController.text.trim(),
        if (workDetailsChanged) ...{
          'workDetails': WorkDetailData.listToFirestore(_workDetails),
          'totalRequired': totalRequired,
        },
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

      await _firestoreService.updateTO(widget.to.id, updates,
          expectedEditRevision: widget.to.editRevision);

      // [PUB-CF] 첫 공개: CF callablePublishTO (maxActiveTOs 서버 강제)
      if (shouldPublish) {
        try {
          await _firestoreService.publishTO(widget.to.id);
        } on FirebaseFunctionsException catch (e) {
          // [5D.2A] failed-precondition → 서버 메시지 그대로 노출 (readiness 실패 등)
          if (e.code == 'failed-precondition' && (e.message?.isNotEmpty ?? false)) {
            if (mounted) ToastHelper.showError(e.message!);
          } else if (e.toString().contains('MAX_ACTIVE_TO_LIMIT')) {
            final parts = e.toString().split(':');
            final limitStr = parts.length >= 2 ? parts.last : '4';
            if (mounted) ToastHelper.showError('진행 중인 공고가 $limitStr개를 초과할 수 없습니다');
          } else {
            if (mounted) ToastHelper.showError('공개 전환에 실패했습니다. 잠시 후 다시 시도해주세요');
          }
          if (mounted) setState(() { _isSaving = false; _hasChanges = true; });
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
            deadlineType: widget.to.deadlineType,
            hoursBeforeStart: _hoursBeforeStart,
            fixedDeadline: widget.to.deadlineType == 'FIXED_TIME' ? _fixedDeadline : null,
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
        ToastHelper.showWarning('공고가 수정되었으나 슬롯 동기화에 실패했습니다. 다시 저장해 주세요.');
        // 슬롯 동기화 실패 시 화면에 남아 재저장 가능하도록 팝하지 않음
        setState(() => _hasChanges = true);
      } else {
        ToastHelper.showSuccess('공고가 수정되었습니다');
        NavigationHelper.popWithChange(context);
      }
    } catch (e) {
      debugPrint('❌ TO 수정 실패: $e');
      if (mounted) {
        if (_isStaleEditConflict(e)) {
          setState(() => _isSaving = false);
          await _showStaleEditDialog();
          return;
        }
        final msg = _cfErrorMessage(e) ?? '수정에 실패했습니다';
        ToastHelper.showError(msg);
        setState(() => _hasChanges = true);
      }
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
        // startTime은 항상 KST — DateTime.utc()로 생성 후 KST→UTC(-9h) 변환
        final deadline = DateTime.utc(
          slot.date.year, slot.date.month, slot.date.day,
          int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0,
        ).subtract(const Duration(hours: 9)).subtract(Duration(hours: _hoursBeforeStart));
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

      // [4H.0C-SINGLE-GUARD] updateSlotFull → callableUpdateSlotWorkDetails (서버 identity guard)
      final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableUpdateSlotWorkDetails',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
      await callable.call({
        'toId': widget.to.id,
        'slotId': slot.id,
        'workDetails': WorkDetailData.listToCFPayload(updatedWorkDetails),
        'applicationDeadlineMs': slotDeadline?.millisecondsSinceEpoch,
        'title': _slotTitleController.text.trim(),
        'visibleFromMs': visibleFrom?.millisecondsSinceEpoch,
        'clearVisibleFrom': clearVisibleFrom,
        'expectedEditRevision': slot.editRevision, // [STALE-EDIT]
      });

      _firestoreService.clearCache(toId: widget.to.id);
      if (!mounted) return;
      ToastHelper.showSuccess('수정되었습니다');
      NavigationHelper.popWithChange(context);
    } catch (e) {
      debugPrint('❌ 슬롯 수정 실패: $e');
      if (mounted) {
        if (_isStaleEditConflict(e)) {
          setState(() => _isSaving = false);
          await _showStaleEditDialog();
          return;
        }
        ToastHelper.showError(_cfErrorMessage(e) ?? '수정에 실패했습니다');
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }


  // ============================================================
  // [POSTING-V2-03G.1] 업무 변경 사전 확인
  // ============================================================

  /// 이 공고의 지원 현황 원본 조회. 캐시 정책은 [EditApplicationRelations]가 정한다.
  ///
  /// 화면을 닫으면 함께 사라진다 — 전역 캐시로 승격하지 않는다.
  Future<List<Map<String, dynamic>>> _fetchApplications() async {
    // [CF 이전 2026-07-13] callableGetApplicationsByBiz (Admin SDK, businessId+toId)
    final callable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableGetApplicationsByBiz',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
    final result = await callable.call<Map<String, dynamic>>({
      'businessId': widget.to.businessId,
      'toId': widget.to.id,
      'limit': 2000,
    });
    return (result.data['applications'] as List? ?? [])
        .whereType<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
  }

  /// 서버가 지원서를 업무에 매칭하는 세 가지 방식을 그대로 따른다.
  ///   · 신규: workDetailId == '업무_시작_종료'
  ///   · 레거시: workDetailId == 업무명 (시간대 구분 없음 — 보수적으로 일치로 본다)
  ///   · wdId 직접 매칭
  bool _appMatchesWork(Map<String, dynamic> app, WorkDetailData work) {
    final workDetailId = app['workDetailId'];
    if (workDetailId == work.id) return true;
    if (workDetailId == work.workType) return true;
    final wdId = work.wdId;
    if (wdId != null && app['wdId'] == wdId) return true;
    return false;
  }

  bool _isForSlot(Map<String, dynamic> app, String slotId) =>
      app['slotId'] == slotId;

  /// 슬롯 경로 identity guard가 보는 상태 — 확정까지 포함한다.
  static const _slotIdentityStatuses = [
    AppStatus.pending,
    AppStatus.invited,
    AppStatus.contractPending,
    AppStatus.confirmed,
  ];

  /// 마스터(TO) 경로 identity guard가 보는 상태. 확정은 아래 blanket guard가 따로 본다.
  static const _toIdentityStatuses = [
    AppStatus.pending,
    AppStatus.invited,
    AppStatus.contractPending,
  ];

  /// 정원을 차지한 상태 — requiredCount 하한.
  static const _occupancyStatuses = [
    AppStatus.confirmed,
    AppStatus.contractPending,
  ];

  /// [next]로 바꾸려 할 때 서버가 거부할 이유. 막을 이유가 없으면 null.
  ///
  /// 스냅샷이 없으면(아직 못 읽었거나 실패) null을 돌려준다 — 사전 안내를
  /// 포기하는 것이지 허가가 아니다. 서버가 최종 판정을 그대로 한다.
  String? _workChangeBlockReason(
    List<Map<String, dynamic>> apps,
    List<WorkDetailData> next,
  ) {
    final nextIds = next.map((w) => w.id).toSet();
    final removed =
        _originalWorkDetails.where((w) => !nextIds.contains(w.id)).toList();

    if (widget.isSlotMode) {
      // 슬롯 경로 — 날짜별로 독립이다. 다른 날짜의 지원자는 이 날짜를 묶지 않는다.
      final slotIds = widget.isBatchMode
          ? widget.batchSlots!.map((s) => s.id).toList()
          : [widget.slot!.id];

      for (final work in removed) {
        final blocked = apps.any((app) =>
            _slotIdentityStatuses.contains(app['status']) &&
            slotIds.any((id) => _isForSlot(app, id)) &&
            _appMatchesWork(app, work));
        if (blocked) {
          return '해당 업무 시간대에 활성 지원자가 있어 업무 구성을 변경할 수 없습니다. '
              '해당 지원을 먼저 처리해주세요.';
        }
      }

      // 필요 인원은 "지원자 존재"가 아니라 **확정 인원 미만**일 때만 막힌다.
      for (final work in next) {
        final occupied = apps
            .where((app) =>
                _occupancyStatuses.contains(app['status']) &&
                slotIds.any((id) => _isForSlot(app, id)) &&
                _appMatchesWork(app, work))
            .length;
        if (occupied > 0 && work.requiredCount < occupied) {
          return "'${work.workType}' 업무의 필요 인원(${work.requiredCount})은 "
              '현재 확정 인원($occupied)보다 작게 설정할 수 없습니다.';
        }
      }
      return null;
    }

    // 마스터(TO) 경로 — 서버는 확정자가 하나라도 있으면 workDetails 변경 전체를
    // 거부한다. 사라진 업무만 보는 판정으로는 이 범위를 재현하지 못한다.
    final confirmed =
        apps.where((app) => _occupancyStatuses.contains(app['status'])).length;
    if (confirmed > 0) {
      return '확정된 지원자가 있는 공고의 근무 조건은 수정할 수 없습니다.';
    }

    // 확정자가 없어도, 사라지는 업무에 진행 중인 지원이 걸려 있으면 막힌다.
    // 서버는 이 경로에서 업무명(selectedWorkType)으로 본다.
    for (final work in removed) {
      final blocked = apps.any((app) =>
          _toIdentityStatuses.contains(app['status']) &&
          app['selectedWorkType'] == work.workType);
      if (blocked) {
        return "'${work.workType}' 업무에 활성 지원자가 있어 업무 구성을 변경할 수 없습니다. "
            '해당 지원을 먼저 처리해주세요.';
      }
    }
    return null;
  }

  /// 업무를 [next]로 바꾸는 것이 허용되는지 확인하고, 아니면 안내 후 false.
  ///
  /// **form에 반영하기 전에** 호출한다 — 다 고쳐 놓고 돌려받는 것이 원래 문제였다.
  Future<bool> _canApplyWorkChange(List<WorkDetailData> next) async {
    // 안내용 — 세션 캐시를 쓴다. 낡아도 저장에서 서버가 최종 판정한다.
    final apps = await _applicationRelations.advisory();
    if (!mounted) return false;
    if (apps == null) return true; // 사전 확인 불가 — 서버가 최종 판정한다
    final reason = _workChangeBlockReason(apps, next);
    if (reason == null) return true;
    ToastHelper.showError(reason);
    return false;
  }

  /// 저장 payload에 workDetails를 실을지 결정한다.
  ///
  /// 서버의 확정자 guard는 **값이 바뀌었는지가 아니라 키가 실렸는지**를 본다.
  /// 그래서 제목만 고쳐도 workDetails를 늘 함께 보내면, 서버가 허용하는
  /// 수정까지 '근무 조건 수정'으로 거부됐다.
  bool _hasWorkDetailsChanged() {
    final before = WorkDetailData.listToCFPayload(_originalWorkDetails);
    final after = WorkDetailData.listToCFPayload(_workDetails);
    if (before.length != after.length) return true;
    for (var i = 0; i < before.length; i++) {
      final a = before[i];
      final b = after[i];
      if (a.length != b.length) return true;
      for (final entry in a.entries) {
        if (!b.containsKey(entry.key) || b[entry.key] != entry.value) return true;
      }
    }
    return false;
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
          cur.taxDeductionType != orig.taxDeductionType ||
          cur.startTime != orig.startTime ||
          cur.endTime != orig.endTime ||
          cur.requiredCount != orig.requiredCount) {
        return true;
      }
    }
    return false;
  }

  Future<bool> _showWageGuardWarning() async {
    // [POSTING-V2-03G.1 TC2] **매번 다시 읽는다.** 안내용 세션 캐시를 쓰지 않는다.
    //   FLEX 슬롯 임금에는 서버 가드가 없어 이 경고가 마지막 방어선인데,
    //   업무를 고치던 몇 분 전 스냅샷으로 '확정자 없음'이라 판단하면
    //   그 사이 확정된 근무자의 급여 조건이 경고 없이 바뀐다.
    //   읽기 한 번을 아끼는 것보다 확정 관계의 최신성이 우선이다.
    final appsRaw = await _applicationRelations.fresh();
    if (!mounted) return false;
    if (appsRaw == null) {
      // [4H.0B-WAGE-01] FAIL CLOSE — 조회 실패 시 저장 차단 (SINGLE/BATCH 서버 가드 없으므로)
      //   실패를 기억하지 않으므로 다시 저장을 누르면 다시 조회한다.
      debugPrint('⚠️ WAGE-GUARD 쿼리 실패 (저장 차단)');
      ToastHelper.showError('지원자 상태를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.');
      return false;
    }
    const confirmedStatuses = [AppStatus.confirmed, AppStatus.contractPending];
    final hasConfirmed =
        appsRaw.any((m) => confirmedStatuses.contains(m['status']));
    if (!hasConfirmed) return true; // 미확정 근무자 없음 — 경고 불필요

    if (!mounted) return false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StyledDialog(
        title: '급여 계산 조건 변경',
        subtitle: '이 공고에 확정된 근무자가 있습니다',
        icon: Icons.warning_amber_rounded,
        headerColor: AppColors.warning,
        content: Text(
          '급여 유형·휴게시간·야간 설정을 변경하면\n미확정 급여 계산에 영향을 줄 수 있습니다.\n\n계속 저장하시겠습니까?',
          style: ResponsiveHelper.bodyStyle(ctx, color: AppColors.grey700),
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

  Future<void> _saveBatchSlotChanges() async {
    try {
      final slots = widget.batchSlots!;

      // [4H.0B-BATCH-01] 배치 저장 전 명시적 확인 — 기존 업무 구성이 교체됨을 고지
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => StyledDialog(
          title: '${slots.length}개 날짜 일괄 적용',
          icon: Icons.edit_calendar_outlined,
          headerColor: AppColors.info,
          content: Text(
            '선택한 ${slots.length}개 날짜의 기존 업무 설정이 현재 설정으로 교체됩니다.\n\n'
            '날짜별로 다르게 설정된 업무·시간·급여도 동일하게 변경됩니다.',
            style: ResponsiveHelper.bodyStyle(ctx, color: AppColors.grey700),
          ),
          actions: [
            StyledDialogButton.cancel(
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            StyledDialogButton.primary(
              text: '일괄 적용',
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      );
      if (!mounted || confirmed != true) return;

      // 공개 설정을 명시적으로 변경했을 때만 draft TO 자동 전환 (이중 호출 방지를 위해 결과 캐싱)
      if (_slotPublishChanged && widget.to.publishMode == 'draft') {
        final visibleFroms = slots.map((s) => _calcSlotVisibleFrom(s.date).$1).toList();
        final anyImmediate = visibleFroms.any((vf) => vf == null);
        final earliestVisibleFrom = visibleFroms
            .whereType<DateTime>()
            .fold<DateTime?>(null, (e, vf) => e == null || vf.isBefore(e) ? vf : e);
        if (!await _applyTODraftTransition(anyImmediate ? null : earliestVisibleFrom)) return;
      }

      // [4H.0C-BATCH-GUARD] WriteBatch → callableUpdateSlotWorkDetails (서버 identity guard)
      // 서버에서 isClosed / duplicate ID / ACTIVE 지원자 검증 후 원자적으로 저장.
      final batchPayload = <Map<String, dynamic>>[];
      for (final slot in slots) {
        final updatedWorkDetails = _workDetails.map((work) {
          final parts = work.startTime.split(':');
          if (parts.length != 2) return work;
          // startTime은 항상 KST — DateTime.utc()로 생성 후 KST→UTC(-9h) 변환
          final deadline = DateTime.utc(
            slot.date.year, slot.date.month, slot.date.day,
            int.tryParse(parts[0]) ?? 0, int.tryParse(parts[1]) ?? 0,
          ).subtract(const Duration(hours: 9)).subtract(Duration(hours: _hoursBeforeStart));
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

        batchPayload.add({
          'slotId': slot.id,
          'workDetails': WorkDetailData.listToCFPayload(updatedWorkDetails),
          'applicationDeadlineMs': slotDeadline?.millisecondsSinceEpoch,
          'visibleFromMs': visibleFrom?.millisecondsSinceEpoch,
          'clearVisibleFrom': clearVisibleFrom,
          'expectedEditRevision': slot.editRevision, // [STALE-EDIT]
        });
      }

      final batchCallable = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableUpdateSlotWorkDetails',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 60)));
      await batchCallable.call({
        'toId': widget.to.id,
        'batchUpdates': batchPayload,
      });

      _firestoreService.clearCache(toId: widget.to.id);
      if (!mounted) return;
      ToastHelper.showSuccess('${slots.length}개 날짜가 수정되었습니다');
      NavigationHelper.popWithChange(context);
    } catch (e) {
      debugPrint('❌ 일괄 슬롯 수정 실패: $e');
      if (mounted) {
        if (_isStaleEditConflict(e)) {
          setState(() => _isSaving = false);
          await _showStaleEditDialog();
          return;
        }
        ToastHelper.showError(_cfErrorMessage(e) ?? '수정에 실패했습니다');
      }
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
      // [4H.0C-DUP-01] 클라이언트 duplicate composite ID 검증
      final candidateId =
          '${result.workType!}_${result.startTime!}_${result.endTime!}';
      if (_workDetails.any((w) => w.id == candidateId)) {
        ToastHelper.showError('같은 업무와 근무 시간이 이미 있습니다.');
        return;
      }
      // [POSTING-V2-03G.1] 업무를 더하는 것만으로도 막히는 경우가 있다 —
      //   마스터 경로는 확정자가 있으면 근무 조건 변경 자체를 거부한다.
      final candidate = WorkDetailData(
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
      );
      if (!await _canApplyWorkChange([..._workDetails, candidate])) return;
      if (!mounted) return;
      setState(() {
        _hasChanges = true; // [B-4] workDetails 변경 감지
        _workDetails.add(candidate);
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
      // [4H.0C-DUP-02] 클라이언트 duplicate composite ID 검증 (자신 제외)
      final candidateWorkType = (result['workType'] as String?) ?? work.workType;
      final candidateStart = (result['startTime'] as String?) ?? work.startTime;
      final candidateEnd = (result['endTime'] as String?) ?? work.endTime;
      final candidateId = '${candidateWorkType}_${candidateStart}_$candidateEnd';
      if (_workDetails.where((w) => w != work).any((w) => w.id == candidateId)) {
        ToastHelper.showError('같은 업무와 근무 시간이 이미 있습니다.');
        return;
      }
      final index = _workDetails.indexOf(work);
      if (index != -1) {
        final updated = _workDetails[index].copyWith(
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
        // [POSTING-V2-03G.1] 고쳐 놓고 저장에서 되돌려받지 않는다.
        final next = List<WorkDetailData>.from(_workDetails)..[index] = updated;
        if (!await _canApplyWorkChange(next)) return;
        if (!mounted) return;
        setState(() {
          _hasChanges = true; // [B-4] workDetails 변경 감지
          _workDetails[index] = updated;
        });
      }
      if (!mounted) return;
      ToastHelper.showInfo('업무가 수정되었습니다 (저장 버튼을 눌러주세요)');
    }
  }

  Future<void> _deleteWork(WorkDetailData work) async {
    final confirmed = await _showDeleteConfirmDialog(work);
    if (confirmed != true || !mounted) return;
    // [POSTING-V2-03G.1] 지원자가 걸린 업무는 삭제가 거부된다 — 목록에서 지웠다가
    //   저장에서 되살아나는 대신, 지우기 전에 알린다.
    final next = _workDetails.where((w) => w != work).toList();
    if (!await _canApplyWorkChange(next)) return;
    if (!mounted) return;
    setState(() { _hasChanges = true; _workDetails.remove(work); }); // [B-4] workDetails 변경 감지
    ToastHelper.showInfo('업무가 삭제되었습니다 (저장 버튼을 눌러주세요)');
  }

  // ============================================================
  // UI 빌드
  // ============================================================

  // PATCH-2 (ADMIN-DESIGN-5): 알림 버튼 헬퍼 — 로딩·저장 상태별 disabled 분리
  Widget _buildNotificationAction({bool disabled = false}) {
    return NotificationBadge(
      child: IconButton(
        icon: const Icon(Icons.notifications_outlined),
        color: AppColors.textSecondary,
        onPressed: disabled
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const NotificationScreen()),
                ),
        tooltip: '알림',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appBarTitle = widget.isBatchMode
        ? '${widget.batchSlots!.length}개 날짜 일괄수정'
        : widget.slot != null
            ? '${widget.slot!.formattedDate} 수정'
            : '공고 수정';

    if (_isLoading) {
      // PATCH-3 (ADMIN-DESIGN-5): Scaffold → AppPageScaffold (로딩 상태)
      return AppPageScaffold(
        title: appBarTitle,
        actions: [_buildNotificationAction()],
        body: const LoadingWidget(),
      );
    }

    return PopScope(
      // [F-01-4 수정] 저장 진행 중에는 뒤로가기 차단
      // _saveChanges()에서 _hasChanges=false를 즉시 설정하므로 기존 canPop:!_hasChanges만으로는
      // _isSaving=true인 동안도 canPop=true가 되어 Firestore 작업 중 화면 이탈 허용됨
      canPop: !_hasChanges && !_isSaving,
      onPopInvokedWithResult: (didPop, _) async {
        // [M1-FIX] 저장 진행 중(_isSaving)에는 다이얼로그 없이 즉시 차단
        if (didPop || _isSaving) return;
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
      // PATCH-4 (ADMIN-DESIGN-5): Scaffold → AppPageScaffold (메인 폼)
      child: AppPageScaffold(
        title: appBarTitle,
        actions: [
          // [M1-FIX] 저장 진행 중에는 알림 화면 이동 차단
          _buildNotificationAction(disabled: _isSaving),
        ],
        bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 8),
              ResponsiveHelper.spacing(context, 16),
              ResponsiveHelper.spacing(context, 12),
            ),
            child: TOActionButton.save(
              onPressed: _isSaving ? null : _saveChanges,
              isLoading: _isSaving,
            ),
          ),
        ),
        body: Form(
          key: _formKey,
          child: ListView(
            // bottomNavigationBar의 SafeArea가 시스템 inset을 처리하므로
            // paddingOf.bottom 중복 추가 없이 CTA 위 콘텐츠 여백만 확보한다.
            // CreateTO body(bottom:108)와 동등한 clearance 적용.
            padding: ResponsiveHelper.listPadding(context).copyWith(bottom: 108),
            children: [
              if (widget.isBatchMode) ...[
                _buildBatchInfoBanner(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              ],
              // 슬롯 개별 공고 제목 (단일 슬롯 수정)
              if (widget.slot != null) ...[
                _buildSlotTitleField(context),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              ],
              if (!widget.isSlotMode) ...[
                TODateSelector(
                  isLongTerm: widget.to.isContractType,
                  isReadOnly: true,
                  rangeStart: widget.to.rangeStart,
                  rangeEnd: widget.to.rangeEnd,
                  displayWorkDays: widget.to.workDays,
                  contractPeriodType: widget.to.contractPeriodType,
                  workStartAvailableFrom: widget.to.workStartAvailableFrom,
                  workStartAvailableUntil: widget.to.workStartAvailableUntil,
                ),
                Padding(
                  padding: EdgeInsets.only(
                      left: ResponsiveHelper.spacing(context, 4),
                      bottom: ResponsiveHelper.spacing(context, 4)),
                  child: Text(
                    '날짜·근무요일은 공고 생성 후 변경할 수 없습니다',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey500),
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                TOTitleSection(titleController: _titleController),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              ],

              TOWorkDetailsSection(
                key: _workDetailSectionKey,
                workDetailData: _workDetails,
                onAddWork: _showAddWorkDialog,
                onEditWorkData: _showEditWorkDialog,
                onDeleteWorkData: _deleteWork,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),

              if (!widget.to.isContractType) ...[
                TODeadlineSection(
                  isLongTerm: false,
                  hoursBeforeStart: _hoursBeforeStart,
                  onHoursChanged: (h) => setState(() => _hoursBeforeStart = h),
                  fixedDeadline: _fixedDeadline,
                  onFixedDeadlineChanged: (dt) => setState(() => _fixedDeadline = dt),
                  rangeStartDate: null,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
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
                  rangeEnd: widget.to.isContractType ? widget.to.rangeEnd : null,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                TODescriptionSection(controller: _descriptionController),
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
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
                      : (widget.slot != null ? [widget.slot!.date] : []),
                  isLongTerm: false,
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
              ],

              SizedBox(height: ResponsiveHelper.spacing(context, 8)),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '이 날짜의 공고 제목',
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

  // ============================================================
  // 유틸리티 메서드
  // ============================================================

  /// GlobalKey로 등록된 섹션으로 자동 스크롤
  void _scrollToSection(GlobalKey key) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = key.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(ctx,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeInOut,
          alignment: 0.1);
    });
  }

  /// FirebaseFunctionsException에서 사용자에게 표시할 메시지 추출.
  /// 안전한 코드('failed-precondition', 'invalid-argument', 'not-found')만 노출.
  String? _cfErrorMessage(Object e) {
    if (e is FirebaseFunctionsException) {
      const safeCodes = ['failed-precondition', 'invalid-argument', 'not-found'];
      if (safeCodes.contains(e.code) && (e.message?.isNotEmpty ?? false)) {
        return e.message;
      }
    }
    return null;
  }

  /// [STALE-EDIT] failed-precondition + "다른 관리자" 메시지 → stale edit 충돌
  bool _isStaleEditConflict(Object e) {
    if (e is FirebaseFunctionsException && e.code == 'failed-precondition') {
      final msg = e.message ?? '';
      return msg.contains('다른 관리자');
    }
    return false;
  }

  /// [STALE-EDIT] 충돌 다이얼로그 — 이전 화면으로 돌아가서 새로고침 유도
  Future<void> _showStaleEditDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StyledDialog(
        title: '수정 내용 충돌',
        subtitle: '다른 관리자가 이미 저장했습니다',
        icon: Icons.sync_problem_rounded,
        headerColor: AppColors.warning,
        content: Text(
          '저장하는 동안 다른 관리자가 먼저 공고를 수정했습니다.\n'
          '화면을 다시 열어 최신 내용을 확인한 후 수정해 주세요.',
          style: ResponsiveHelper.bodyStyle(ctx, color: AppColors.grey700),
        ),
        actions: [
          StyledDialogButton.primary(
            text: '확인 (뒤로가기)',
            onPressed: () => Navigator.pop(ctx),
          ),
        ],
      ),
    );
    if (mounted) NavigationHelper.popWithChange(context);
  }

  Widget _buildBatchInfoBanner(BuildContext context) {
    final slots = widget.batchSlots!;
    final dateLabels = slots.map((s) => s.formattedDate).join(', ');
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 10)),
        border: Border.all(color: AppColors.infoLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.edit_calendar_outlined,
                  size: ResponsiveHelper.iconSize(context, 16),
                  color: AppColors.infoDark),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Text(
                '${slots.length}개 날짜 일괄 수정',
                style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.infoDark)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          Text(
            '선택한 모든 날짜에 동일하게 적용됩니다.\n$dateLabels',
            style: ResponsiveHelper.smallStyle(context,
                color: AppColors.infoDark),
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
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return (null, true);
    // [TZ-02 FIX] DateTime.utc()로 KST→UTC 명시 변환 — TZ-01(updateSlotsPublishSettings)과 동일 패턴
    // DateTime(y,m,d,h,m)은 기기 로컬 타임존 기준 → UTC 시뮬레이터에서 9시간 오차
    // DateTime.utc(y,m,d,h-9,m)은 "KST h시"를 UTC로 직접 표현 (Dart가 언더플로 자동 처리)
    var vf = DateTime.utc(
      slotDate.year, slotDate.month, slotDate.day, h - 9, m,
    ).subtract(Duration(days: _publishDaysBefore));
    // isBefore 체크: UX 안내 전용 (실제 공개는 CF 서버 시간 기준)
    if (vf.isBefore(DateTime.now().toUtc())) {
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
      }, expectedEditRevision: widget.to.editRevision);
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
      barrierDismissible: false,
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
