// lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart
//
// 급여 지급(송금) 현황 대시보드
// - 탭: 미이체 / 이체완료
// - 근무자별 합산 카드 (이름·금액·계좌·버튼)
// - 단건 이체 완료 처리
// - 일괄 이체 완료 처리
// - CSV 내보내기 (은행 일괄이체용)
// - 변경 요청 / 중간정산 요청 탭

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/core/attendance_model.dart';
import '../../../models/core/payment_change_request_model.dart';
import '../../../models/core/interim_settlement_request_model.dart';
import '../../../providers/user_provider.dart';
import '../../../services/payroll_payment_service.dart';
import '../../../services/firestore_service.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/payroll_excel_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../utils/payment_due_date_calculator.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/common/gradient_scaffold.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_search_bar.dart';
import '../../../widgets/common/app_tab_label.dart';
// app_summary_header 대신 _DashboardSummaryHeader 로 대체
import '../../../widgets/common/app_batch_action_bar.dart';
import '../../../widgets/common/app_filter_chip.dart';

enum _PendingFilter { all, overdue, today, noAccount }

class PayrollPaymentDashboardScreen extends StatefulWidget {
  final String businessId;
  final String? businessName; // 없으면 businessId 사용
  final int year;
  final int month;

  const PayrollPaymentDashboardScreen({
    super.key,
    required this.businessId,
    this.businessName,
    required this.year,
    required this.month,
  });

  @override
  State<PayrollPaymentDashboardScreen> createState() =>
      _PayrollPaymentDashboardScreenState();
}

class _PayrollPaymentDashboardScreenState
    extends State<PayrollPaymentDashboardScreen>
    with SingleTickerProviderStateMixin {

  final _payService = PayrollPaymentService();
  final _fsService  = FirestoreService();

  late final TabController _tabCtrl;

  // 탭 0: 미이체 / 탭 1: 이체완료 / 탭 2: 변경요청 / 탭 3: 중간정산
  bool _isLoading = false;
  bool _isExporting = false;
  List<AttendanceModel> _pendingRecords    = [];  // 미이체
  List<AttendanceModel> _transferredRecords = []; // 이체완료
  List<PaymentChangeRequestModel>     _changeRequests    = [];
  List<InterimSettlementRequestModel> _settlementRequests = [];

  // 일괄 선택 (미이체 탭)
  final Set<String> _selectedIds = {};
  bool _batchMode = false;
  bool _isTransferring = false;

  // 검색
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // 미이체 탭 퀵필터
  _PendingFilter _pendingFilter = _PendingFilter.all;

  // 탭 라벨용 카운트 캐시 (빌드마다 _groupByWorker 재호출 방지)
  int _pendingWorkerCount = 0;
  int _transferredWorkerCount = 0;

  // 페이지네이션 (급여 기록 — 미이체 / 이체완료)
  DocumentSnapshot? _lastDocPending;
  DocumentSnapshot? _lastDocTransferred;
  bool _hasMorePending = false;
  bool _hasMoreTransferred = false;
  bool _isLoadingMorePending = false;
  bool _isLoadingMoreTransferred = false;

  // 사용자 계좌 정보 캐시 (uid → bankInfo)
  final Map<String, Map<String, String>> _userBankCache = {};

  // 마지막 이체 메모 (다음 호출 시 자동 채움)
  String _lastTransferNote = '';

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        // 미이체 탭 떠날 때 배치모드 자동 해제
        if (_batchMode && _tabCtrl.index != 0) {
          setState(() {
            _batchMode = false;
            _selectedIds.clear();
          });
        }
      }
    });
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim());
    });
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── 데이터 로드 ────────────────────────────────────────────
  Future<void> _load() async {
    if (!mounted || _isLoading) return;
    setState(() {
      _isLoading = true;
      _lastDocPending = null;
      _lastDocTransferred = null;
      _hasMorePending = false;
      _hasMoreTransferred = false;
    });

    try {
      final results = await Future.wait([
        _payService.getPayrollRecords(
            businessId: widget.businessId,
            year: widget.year, month: widget.month,
            wageStatus: AttendanceModel.wageConfirmed),
        _payService.getPayrollRecords(
            businessId: widget.businessId,
            year: widget.year, month: widget.month,
            wageStatus: AttendanceModel.wageTransferred),
        _payService.getPendingChangeRequests(widget.businessId),
        _payService.getPendingSettlementRequests(widget.businessId),
      ]);

      if (!mounted) return;

      final pendingPage     = results[0] as PayrollPage<AttendanceModel>;
      final transferredPage = results[1] as PayrollPage<AttendanceModel>;

      // 계좌 정보 캐시 로딩 (미이체 + 이체완료 모두)
      final uids = {
        ...pendingPage.records.map((r) => r.userId),
        ...transferredPage.records.map((r) => r.userId),
      };
      await _loadBankInfo(uids);

      if (!mounted) return;
      // (근무자+지급일) 그룹 카운트 캐시 (탭 라벨용 — 빌드마다 재계산 방지)
      final pendingGrouped     = <String, bool>{};
      final transferredGrouped = <String, bool>{};
      for (final r in pendingPage.records) {
        final due = r.paymentDueDate;
        final duePart = due != null
            ? '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}'
            : 'no_date';
        pendingGrouped['${r.userId}::$duePart'] = true;
      }
      for (final r in transferredPage.records) {
        final due = r.paymentDueDate;
        final duePart = due != null
            ? '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}'
            : 'no_date';
        transferredGrouped['${r.userId}::$duePart'] = true;
      }

      if (mounted) {
        setState(() {
          _pendingRecords         = pendingPage.records;
          _transferredRecords     = transferredPage.records;
          _pendingWorkerCount     = pendingGrouped.length;
          _transferredWorkerCount = transferredGrouped.length;
          _changeRequests         = results[2] as List<PaymentChangeRequestModel>;
          _settlementRequests     = results[3] as List<InterimSettlementRequestModel>;
          _lastDocPending         = pendingPage.cursor;
          _lastDocTransferred     = transferredPage.cursor;
          _hasMorePending         = pendingPage.hasMore;
          _hasMoreTransferred     = transferredPage.hasMore;
          _selectedIds.clear();
          _batchMode = false;
        });
      }
    } catch (e) {
      debugPrint('❌ 급여 대시보드 로드 실패: $e');
      if (mounted) ToastHelper.showError('데이터를 불러오지 못했습니다');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── 추가 페이지 로드 ───────────────────────────────────────
  Future<void> _loadMorePending() async {
    if (_isLoadingMorePending || !_hasMorePending) return;
    setState(() => _isLoadingMorePending = true);
    try {
      final page = await _payService.getPayrollRecords(
        businessId: widget.businessId,
        year: widget.year,
        month: widget.month,
        wageStatus: AttendanceModel.wageConfirmed,
        cursor: _lastDocPending,
      );
      await _loadBankInfo(page.records.map((r) => r.userId).toSet());
      if (!mounted) return;
      setState(() {
        _pendingRecords = [..._pendingRecords, ...page.records];
        _hasMorePending = page.hasMore;
        _lastDocPending = page.cursor;
        final grouped = <String, bool>{};
        for (final r in _pendingRecords) {
          final due = r.paymentDueDate;
          final duePart = due != null
              ? '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}'
              : 'no_date';
          grouped['${r.userId}::$duePart'] = true;
        }
        _pendingWorkerCount = grouped.length;
      });
    } catch (e) {
      debugPrint('❌ 미이체 추가 로드 실패: $e');
      if (mounted) ToastHelper.showError('추가 데이터 로드에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoadingMorePending = false);
    }
  }

  Future<void> _loadMoreTransferred() async {
    if (_isLoadingMoreTransferred || !_hasMoreTransferred) return;
    setState(() => _isLoadingMoreTransferred = true);
    try {
      final page = await _payService.getPayrollRecords(
        businessId: widget.businessId,
        year: widget.year,
        month: widget.month,
        wageStatus: AttendanceModel.wageTransferred,
        cursor: _lastDocTransferred,
      );
      await _loadBankInfo(page.records.map((r) => r.userId).toSet());
      if (!mounted) return;
      setState(() {
        _transferredRecords = [..._transferredRecords, ...page.records];
        _hasMoreTransferred = page.hasMore;
        _lastDocTransferred = page.cursor;
        final grouped = <String, bool>{};
        for (final r in _transferredRecords) {
          final due = r.paymentDueDate;
          final duePart = due != null
              ? '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}'
              : 'no_date';
          grouped['${r.userId}::$duePart'] = true;
        }
        _transferredWorkerCount = grouped.length;
      });
    } catch (e) {
      debugPrint('❌ 이체완료 추가 로드 실패: $e');
      if (mounted) ToastHelper.showError('추가 데이터 로드에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isLoadingMoreTransferred = false);
    }
  }

  Future<void> _loadBankInfo(Set<String> uids) async {
    final uncached = uids.where((u) => !_userBankCache.containsKey(u)).toList();
    if (uncached.isEmpty) return;
    try {
      // getUsersBatch: 30개 청크 + limit(chunk.length) 처리, 보안 규칙 준수
      final userMap = await _fsService.getUsersBatch(uncached, businessId: widget.businessId);
      for (final uid in uncached) {
        final user = userMap[uid];
        if (user == null) continue;
        _userBankCache[uid] = {
          'name':          user.name,
          'bankName':      user.bankName     ?? '',
          'accountNumber': user.accountNumber != null
              ? _maskAccount(user.accountNumber!)
              : '',
          'accountHolder': user.accountHolder ?? user.name,
        };
      }
    } catch (e) {
      debugPrint('❌ 계좌 정보 배치 로드 실패: $e');
    }
  }

  String _maskAccount(String raw) {
    // 복호화 후 뒤 4자리만 표시
    try {
      final clean = raw.replaceAll('-', '');
      if (clean.length < 4) return '****';
      return '****${clean.substring(clean.length - 4)}';
    } catch (_) { return '****'; }
  }

  // ── (근무자 + 지급일) 기준 그룹 집계 ──────────────────────────
  // 키 형식: "uid::YYYY-MM-DD" (지급일 미설정이면 "uid::no_date")
  // - 당일/익일: 각 레코드가 다른 날짜 → 레코드마다 별도 카드
  // - 주급/월급: 같은 지급일이면 묶음 → 하나의 카드
  Map<String, List<AttendanceModel>> _groupByWorker(
      List<AttendanceModel> records) {
    final map = <String, List<AttendanceModel>>{};
    for (final r in records) {
      final due = r.paymentDueDate;
      final duePart = due != null
          ? '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}'
          : 'no_date';
      final key = '${r.userId}::$duePart';
      (map[key] ??= []).add(r);
    }
    // 검색 쿼리가 있으면 이름으로 필터
    if (_searchQuery.isEmpty) return map;
    final q = _searchQuery.toLowerCase();
    return Map.fromEntries(map.entries.where((e) {
      final uid  = e.key.split('::').first;
      final name = _userBankCache[uid]?['name'] ?? uid;
      return name.toLowerCase().contains(q);
    }));
  }

  /// 그룹 키에서 uid만 추출
  String _uidFromKey(String key) => key.split('::').first;

  /// 그룹 키에서 지급일만 추출
  DateTime? _dueDateFromKey(String key) {
    final part = key.split('::').last;
    if (part == 'no_date') return null;
    return DateTime.tryParse(part);
  }

  // ── 검색 바 위젯 ──────────────────────────────────────────
  Widget _buildSearchBar() {
    return AppSearchBar(
      controller: _searchCtrl,
      hintText: '근무자 이름으로 검색',
    );
  }

  // ── 지급일·연체 헬퍼 ──────────────────────────────────────
  // getter로 호출 시점마다 계산 — 앱이 자정을 넘겨도 정확함
  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  DateTime? _earliestDue(List<AttendanceModel> recs) {
    final dates = recs
        .map((r) => r.paymentDueDate)
        .whereType<DateTime>()
        .map((d) => DateTime(d.year, d.month, d.day))
        .toList()
      ..sort();
    return dates.isEmpty ? null : dates.first;
  }

  bool _groupIsOverdue(List<AttendanceModel> recs) {
    final due = _earliestDue(recs);
    return due != null && due.isBefore(_today);
  }

  bool _groupIsDueToday(List<AttendanceModel> recs) {
    final due = _earliestDue(recs);
    return due != null && due == _today;
  }

  int _overdueCount(List<AttendanceModel> recs) {
    final today = _today;
    return recs
        .where((r) =>
            r.paymentDueDate != null &&
            DateTime(r.paymentDueDate!.year, r.paymentDueDate!.month,
                    r.paymentDueDate!.day)
                .isBefore(today))
        .length;
  }

  String? _scheduleLabel(List<AttendanceModel> recs) {
    for (final r in recs) {
      final t = r.wageDetail?.payScheduleType;
      if (t != null) return PaymentDueDateCalculator.label(t);
    }
    return null;
  }

  int _sumNet(List<AttendanceModel> recs) => recs.fold(0, (acc, r) {
    final wd = r.wageDetail;
    if (wd == null) return acc;
    return acc + wd.effectiveNetWage;
  });

  // ── 통계 ─────────────────────────────────────────────────
  int get _totalPending     => _sumNet(_pendingRecords);
  int get _totalTransferred => _sumNet(_transferredRecords);
  int get _selectedNet      =>
      _sumNet(_pendingRecords.where((r) => _selectedIds.contains(r.id)).toList());

  String get _uid =>
      context.read<UserProvider>().currentUser?.uid ?? '';

  // ── 이체 처리 ─────────────────────────────────────────────
  /// 근무자 1인의 모든 레코드를 송금 처리 (단건/복수 자동 분기)
  Future<void> _markWorker(List<AttendanceModel> recs) async {
    if (_isTransferring || recs.isEmpty) return;
    setState(() => _isTransferring = true); // 다이얼로그 대기 중 연타 방지

    try {
      final uid = context.read<UserProvider>().currentUser?.uid ?? '';
      if (uid.isEmpty) {
        ToastHelper.showError('로그인 정보를 확인해주세요');
        return;
      }

      // ① 확인 다이얼로그
      final workerName =
          _userBankCache[recs.first.userId]?['name'] ?? recs.first.userId;
      final net = _sumNet(recs);
      final confirmed = await DialogHelper.showConfirm(
        context,
        title: '송금 처리',
        message: '$workerName님께\n${FormatHelper.formatWage(net)} (${recs.length}건)을\n송금 처리하시겠습니까?',
        confirmText: '송금 처리',
        cancelText: '취소',
        icon: Icons.payment_outlined,
      );
      if (confirmed != true || !mounted) return;

      // ② 메모 입력 (선택)
      final note = await _showTransferNoteDialog();
      if (!mounted) return;

      // ③ 이체 실행
      if (recs.length == 1) {
        final r = recs.first;
        final wd = r.wageDetail;
        final net = wd?.effectiveNetWage ?? 0;
        // [BUG-수정] 급여 이체 완료 후 지원자 알림 발송
        await _payService.markTransferred(
          attendanceId:  r.id,
          processedBy:   uid,
          transferNote:  note,
          workerUserId:  r.userId,
          workerName:    workerName,
          businessName:  r.businessName,
          businessId:    r.businessId,
          finalWage:     net,
          applicationId: r.applicationId,
        );
      } else {
        // [BUG-수정] 급여 이체 완료 후 지원자 알림 발송
        final nameByUid = Map.fromEntries(
          _userBankCache.entries.map((e) => MapEntry(e.key, e.value['name'] ?? e.key)),
        );
        await _payService.markTransferredBatch(
          attendanceIds:     recs.map((r) => r.id).toList(),
          processedBy:       uid,
          transferNote:      note,
          notificationInfos: buildTransferNotificationInfos(
            records:         recs,
            workerNameByUid: nameByUid,
          ),
        );
      }
      if (mounted) {
        ToastHelper.showSuccess('${recs.length}건 송금 처리되었습니다');
        _load();
      }
    } catch (e) {
      debugPrint('❌ 송금 처리 실패: $e');
      if (mounted) ToastHelper.showError('송금 처리에 실패했습니다\n$e');
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  Future<void> _markBatch() async {
    if (_isTransferring || _selectedIds.isEmpty) return;
    setState(() => _isTransferring = true); // 다이얼로그 대기 중 연타 방지

    try {
      final ok = await DialogHelper.showConfirm(
        context,
        title: '일괄 이체 완료',
        message: '선택된 ${_selectedIds.length}건 (${FormatHelper.formatWage(_selectedNet)})을\n이체 완료 처리하시겠습니까?',
        confirmText: '이체 완료',
        cancelText: '취소',
      );
      if (ok != true || !mounted) return;
      final uid = context.read<UserProvider>().currentUser?.uid ?? '';
      if (uid.isEmpty) {
        ToastHelper.showError('로그인 정보를 확인해주세요');
        return;
      }
      final note = await _showTransferNoteDialog();
      if (!mounted) return;
      // [BUG-수정] 급여 이체 완료 후 지원자 알림 발송 — 선택된 레코드 목록 수집
      final selectedRecords =
          _pendingRecords.where((r) => _selectedIds.contains(r.id)).toList();
      final nameByUid = Map.fromEntries(
        _userBankCache.entries.map((e) => MapEntry(e.key, e.value['name'] ?? e.key)),
      );

      await _payService.markTransferredBatch(
        attendanceIds:     _selectedIds.toList(),
        processedBy:       uid,
        transferNote:      note,
        notificationInfos: buildTransferNotificationInfos(
          records:         selectedRecords,
          workerNameByUid: nameByUid,
        ),
      );
      if (mounted) {
        ToastHelper.showSuccess('${_selectedIds.length}건 이체 완료 처리되었습니다');
        _load();
      }
    } catch (e) {
      debugPrint('❌ 일괄 이체 실패: $e');
      if (mounted) ToastHelper.showError('일괄 처리에 실패했습니다\n$e');
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  Future<String?> _showTransferNoteDialog() async {
    final ctrl = TextEditingController(text: _lastTransferNote);
    final primaryColor = Theme.of(context).primaryColor;

    final note = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 헤더
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryColor, primaryColor.withValues(alpha: 0.85)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.edit_note_rounded,
                        color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('이체 메모',
                            style: ResponsiveHelper.subtitleStyle(ctx)
                                .copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                        Text('선택 입력',
                            style: ResponsiveHelper.tinyStyle(ctx,
                                color: Colors.white.withValues(alpha: 0.75))),
                      ],
                    ),
                  ),
                ]),
              ),
              // 본문
              Container(
                color: AppColors.grey50,
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 6, offset: const Offset(0, 2))],
                    ),
                    child: TextField(
                      controller: ctrl,
                      autofocus: true,
                      maxLines: 3,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
                      style: ResponsiveHelper.bodyStyle(ctx),
                      decoration: InputDecoration(
                        hintText: _lastTransferNote.isNotEmpty
                            ? '이전: $_lastTransferNote'
                            : '이체 번호, 참고사항 등 자유롭게 입력',
                        hintStyle: ResponsiveHelper.smallStyle(ctx, color: AppColors.grey400),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.all(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryColor,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('확인',
                          style: ResponsiveHelper.bodyStyle(ctx)
                              .copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, ''),
                    child: Text('건너뛰기',
                        style: ResponsiveHelper.smallStyle(ctx, color: AppColors.grey400)),
                  ),
                ]),
              ),
            ],
          ),
        ),
      ),
    );

    ctrl.dispose();
    final result = (note == null || note.isEmpty) ? null : note;
    if (result != null) _lastTransferNote = result;
    return result;
  }

  // ── 엑셀 내보내기 → 공통 헬퍼 위임 ─────────────────────────
  Future<void> _exportCsv() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final bizName = widget.businessName ?? widget.businessId;
      await PayrollExcelHelper.exportAndShare(
        context: context,
        records: _pendingRecords,
        title: '$bizName ${widget.year}년 ${widget.month}월 이체목록',
        filename: '${bizName}_${widget.year}년${widget.month}월_이체목록.xlsx',
        businessId: widget.businessId,
      );
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // ── 중간정산 승인 ─────────────────────────────────────────
  Future<void> _approveSettlement(InterimSettlementRequestModel req) async {
    if (_isTransferring) return;
    final ok = await DialogHelper.showConfirm(
      context,
      title: '중간정산 승인',
      message: '${req.workerName}님의 중간정산 요청을 승인하시겠습니까?\n'
          '기간: ${req.periodLabel} (${req.recordCount}건)\n'
          '금액: ${FormatHelper.formatWage(req.netAmount)}',
      confirmText: '승인 및 이체완료',
      cancelText: '취소',
    );
    if (ok != true || !mounted) return;
    final note = await _showTransferNoteDialog();
    if (!mounted) return;
    setState(() => _isTransferring = true);
    try {
      await _payService.approveInterimSettlement(
        req: req, processedBy: _uid, transferNote: note);
      // [D-BUG-01] async gap 후 mounted 체크
      if (mounted) {
        ToastHelper.showSuccess('중간정산이 처리되었습니다');
        _load();
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  Future<void> _rejectSettlement(InterimSettlementRequestModel req) async {
    if (_isTransferring) return;
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('중간정산 거절'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '거절 사유를 입력하세요'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('거절'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;
    setState(() => _isTransferring = true);
    try {
      await _payService.rejectInterimSettlement(
        requestId: req.id, processedBy: _uid, rejectReason: reason);
      // [D-BUG-02] async gap 후 mounted 체크
      if (mounted) {
        ToastHelper.showSuccess('거절 처리되었습니다');
        _load();
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  // ── 변경요청 처리 ─────────────────────────────────────────
  Future<void> _approveChangeRequest(PaymentChangeRequestModel req) async {
    if (_isTransferring) return;
    final ok = await DialogHelper.showConfirm(
      context,
      title: '지급방식 변경 승인',
      message: '${req.workerName}님의 변경 요청을 승인하시겠습니까?\n'
          '${req.changeDescription}\n'
          '효력: ${req.effectiveFrom}부터 (다음 지급 주기)',
      confirmText: '승인',
      cancelText: '취소',
    );
    if (ok != true || !mounted) return;
    setState(() => _isTransferring = true);
    try {
      await _payService.approveChangeRequest(
          requestId: req.id, processedBy: _uid);
      // [D-BUG-03] async gap 후 mounted 체크
      if (mounted) {
        ToastHelper.showSuccess('변경 요청이 승인되었습니다');
        _load();
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  Future<void> _rejectChangeRequest(PaymentChangeRequestModel req) async {
    if (_isTransferring) return;
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('지급방식 변경 거절'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(hintText: '거절 사유'),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('거절'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (reason == null || reason.isEmpty || !mounted) return;
    setState(() => _isTransferring = true);
    try {
      await _payService.rejectChangeRequest(
        requestId: req.id, processedBy: _uid, rejectReason: reason);
      // [D-BUG-04] async gap 후 mounted 체크
      if (mounted) {
        ToastHelper.showSuccess('거절 처리되었습니다');
        _load();
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  // ══════════════════════════════════════════════════════════
  // UI Build
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientScaffold(
      title: '급여 지급 현황 · ${widget.month}월',
      onRefresh: _load,
      body: _isLoading
          ? const LoadingWidget(message: '급여 현황 불러오는 중...')
          : Column(
              children: [
                // 검색바
                _buildSearchBar(),
                // 탭 (흰 영역)
                Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabCtrl,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelColor: theme.primaryColor,
                    unselectedLabelColor: AppColors.grey500,
                    indicatorColor: theme.primaryColor,
                    indicatorWeight: 2.5,
                    dividerColor: AppColors.grey100,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                    labelStyle: ResponsiveHelper.smallStyle(context,
                        fontWeight: FontWeight.w600),
                    unselectedLabelStyle:
                        ResponsiveHelper.smallStyle(context),
                    tabs: [
                      Tab(child: AppTabLabel(label: '미이체',
                          count: _pendingWorkerCount,
                          badgeColor: AppColors.warning,
                          urgent: _pendingWorkerCount > 0)),
                      Tab(child: AppTabLabel(label: '이체완료',
                          count: _transferredWorkerCount,
                          badgeColor: AppColors.success)),
                      Tab(child: AppTabLabel(label: '변경요청',
                          count: _changeRequests.length,
                          badgeColor: AppColors.info)),
                      Tab(child: AppTabLabel(label: '중간정산',
                          count: _settlementRequests.length,
                          badgeColor: AppColors.grey500)),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabCtrl,
                    children: [
                      _buildPendingTab(),
                      _buildTransferredTab(),
                      _buildChangeRequestTab(),
                      _buildSettlementTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ─── 탭 0: 미이체 ─────────────────────────────────────────

  Widget _buildPendingTab() {
    final grouped = _groupByWorker(_pendingRecords);
    if (grouped.isEmpty) {
      return _buildEmptyState(
        _searchQuery.isNotEmpty ? '"$_searchQuery" 검색 결과 없음' : '미이체 내역이 없습니다',
        _searchQuery.isNotEmpty ? '다른 이름으로 검색해 보세요' : '이번 달 모든 급여가 처리되었습니다',
      );
    }

    // 연체→오늘→예정 순 정렬
    final allEntries = grouped.entries.toList()
      ..sort((a, b) {
        final aOver  = _groupIsOverdue(a.value);
        final bOver  = _groupIsOverdue(b.value);
        final aToday = _groupIsDueToday(a.value);
        final bToday = _groupIsDueToday(b.value);
        if (aOver  && !bOver)  return -1;
        if (!aOver &&  bOver)  return 1;
        if (aToday && !bToday) return -1;
        if (!aToday && bToday) return 1;
        return 0;
      });

    // 퀵필터 적용
    final entries = allEntries.where((e) {
      switch (_pendingFilter) {
        case _PendingFilter.overdue:   return _groupIsOverdue(e.value);
        case _PendingFilter.today:     return _groupIsDueToday(e.value);
        case _PendingFilter.noAccount:
          final uid = _uidFromKey(e.key);
          return (_userBankCache[uid]?['bankName'] ?? '').isEmpty;
        case _PendingFilter.all:       return true;
      }
    }).toList();

    final overdueTotal    = allEntries.where((e) => _groupIsOverdue(e.value)).length;
    final todayTotal      = allEntries.where((e) => _groupIsDueToday(e.value)).length;
    final noAccountTotal  = allEntries.where((e) {
      final uid = _uidFromKey(e.key);
      return (_userBankCache[uid]?['bankName'] ?? '').isEmpty;
    }).length;
    final allIds          = allEntries.expand((e) => e.value.map((r) => r.id)).toSet();

    return Column(
      children: [
        // ── 요약 헤더 2×2 그리드
        _DashboardSummaryHeader(
          pendingAmount:  _totalPending,
          transferredAmount: _totalTransferred,
          pendingCount:   grouped.length,
          overdueCount:   overdueTotal,
          onExportCsv:    _exportCsv,
        ),

        // ── 퀵필터 칩 행
        Container(
          color: Colors.white,
          padding: EdgeInsets.fromLTRB(
            ResponsiveHelper.spacing(context, 12),
            ResponsiveHelper.spacing(context, 6),
            ResponsiveHelper.spacing(context, 12),
            ResponsiveHelper.spacing(context, 6),
          ),
          child: Row(
            children: [
              // 퀵필터 칩 — 좁은 화면에서 넘칠 수 있으므로 Expanded + 수평 스크롤
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      AppFilterChip(
                        label: '전체',
                        count: allEntries.length,
                        isSelected: _pendingFilter == _PendingFilter.all,
                        color: AppColors.grey600,
                        onTap: () => setState(() => _pendingFilter = _PendingFilter.all),
                      ),
                      const SizedBox(width: 6),
                      AppFilterChip(
                        label: '연체',
                        count: overdueTotal,
                        isSelected: _pendingFilter == _PendingFilter.overdue,
                        color: AppColors.error,
                        onTap: () => setState(() => _pendingFilter = _PendingFilter.overdue),
                      ),
                      const SizedBox(width: 6),
                      AppFilterChip(
                        label: '오늘마감',
                        count: todayTotal,
                        isSelected: _pendingFilter == _PendingFilter.today,
                        color: AppColors.warning,
                        onTap: () => setState(() => _pendingFilter = _PendingFilter.today),
                      ),
                      const SizedBox(width: 6),
                      AppFilterChip(
                        label: '계좌없음',
                        count: noAccountTotal,
                        isSelected: _pendingFilter == _PendingFilter.noAccount,
                        color: AppColors.grey600,
                        onTap: () => setState(() => _pendingFilter = _PendingFilter.noAccount),
                      ),
                    ],
                  ),
                ),
              ),
              // 구분선
              Container(
                width: 1,
                height: 20,
                color: AppColors.grey200,
                margin: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8)),
              ),
              // 일괄선택 토글 — 필터 칩과 시각적으로 분리
              GestureDetector(
                onTap: _toggleBatchMode,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _batchMode ? Icons.close : Icons.check_box_outlined,
                      size: 15,
                      color: _batchMode ? AppColors.error : AppColors.grey600,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      _batchMode ? '취소' : '일괄선택',
                      style: ResponsiveHelper.smallStyle(context,
                        color: _batchMode ? AppColors.error : AppColors.grey600,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── 일괄선택 바 (배치모드일 때만)
        if (_batchMode)
          AppBatchActionBar(
            selectedCount: _selectedIds.length,
            selectedAmount: _selectedNet,
            onSelectAll: () => setState(() => _selectedIds.addAll(allIds)),
            onDeselectAll: () => setState(() => _selectedIds.clear()),
            onAction: _selectedIds.isNotEmpty && _selectedNet > 0 ? _markBatch : null,
            actionLabel: '송금',
            actionIcon: Icons.send,
          ),

        // ── 카드 목록
        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            child: entries.isEmpty
                ? _buildEmptyState(
                    switch (_pendingFilter) {
                      _PendingFilter.overdue   => '연체 건이 없습니다',
                      _PendingFilter.today     => '오늘 마감 건이 없습니다',
                      _PendingFilter.noAccount => '계좌 정보 없는 근무자가 없습니다',
                      _PendingFilter.all       => '미이체 내역이 없습니다',
                    },
                    '',
                  )
                : ListView.builder(
                    padding: ResponsiveHelper.listPadding(context),
                    itemCount: entries.length + (_hasMorePending ? 1 : 0),
                    itemBuilder: (ctx, i) {
                      if (i == entries.length) {
                        return _buildLoadMoreButton(
                          isLoading: _isLoadingMorePending,
                          onTap: _loadMorePending,
                        );
                      }
                      final groupKey = entries[i].key;
                      final uid      = _uidFromKey(groupKey);
                      final recs     = entries[i].value;
                      final net      = _sumNet(recs);
                      final bank     = _userBankCache[uid];
                      final allSelected =
                          recs.every((r) => _selectedIds.contains(r.id));
                      final isOverdue  = _groupIsOverdue(recs);
                      final isDueToday = _groupIsDueToday(recs);
                      // 그룹 키에서 지급일 추출 (일관성 보장)
                      final dueDate    = _dueDateFromKey(groupKey) ?? _earliestDue(recs);
                      final overdueCnt = _overdueCount(recs);
                      final schLabel   = _scheduleLabel(recs);
                      final daysUntilDue = dueDate?.difference(_today).inDays;

                      return _WorkerPayCard(
                        workerName:   bank?['name'] ?? uid,
                        bankInfo:     bank?['bankName'] != null
                            ? '${bank!['bankName']} ${bank['accountNumber']}'
                            : '계좌 정보 없음',
                        businessName: recs.first.businessName,
                        netAmount:    net,
                        recordCount:  recs.length,
                        isTransferred: false,
                        isBatchMode:  _batchMode,
                        isSelected:   allSelected,
                        isOverdue:    isOverdue,
                        isDueToday:   isDueToday,
                        dueDate:      dueDate,
                        overdueCount: overdueCnt,
                        scheduleLabel: schLabel,
                        daysUntilDue: daysUntilDue,
                        onSelect: _batchMode ? () {
                          setState(() {
                            if (allSelected) {
                              _selectedIds.removeAll(recs.map((r) => r.id));
                            } else {
                              _selectedIds.addAll(recs.map((r) => r.id));
                            }
                          });
                        } : null,
                        onMarkTransferred: !_batchMode
                            ? () => _markWorker(recs)
                            : null,
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }

  // ── "더 불러오기" 버튼 ────────────────────────────────────
  Widget _buildLoadMoreButton({
    required bool isLoading,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 16)),
      child: Center(
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2))
            : OutlinedButton.icon(
                onPressed: onTap,
                icon: const Icon(Icons.expand_more, size: 18),
                label: const Text('더 불러오기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.grey600,
                  side: const BorderSide(color: AppColors.grey200),
                ),
              ),
      ),
    );
  }

  // 배치모드 토글 (AppBar 액션용)
  void _toggleBatchMode() {
    setState(() {
      _batchMode = !_batchMode;
      if (!_batchMode) _selectedIds.clear();
    });
  }

  // ─── 탭 1: 이체완료 ───────────────────────────────────────

  Widget _buildTransferredTab() {
    final grouped = _groupByWorker(_transferredRecords);
    if (grouped.isEmpty) {
      return _buildEmptyState(
        _searchQuery.isNotEmpty ? '"$_searchQuery" 검색 결과 없음' : '이체 완료 내역이 없습니다',
        _searchQuery.isNotEmpty ? '다른 이름으로 검색해 보세요' : '',
      );
    }
    return ListView(
      padding: ResponsiveHelper.listPadding(context),
      children: [
        _DashboardSummaryHeader(
          pendingAmount:     _totalPending,
          transferredAmount: _totalTransferred,
          pendingCount:      _pendingWorkerCount,
          overdueCount:      0,
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        ...grouped.entries.map((entry) {
          final uid  = _uidFromKey(entry.key);
          final recs = entry.value;
          final date = recs.last.transferDate;
          return _WorkerPayCard(
            workerName:   _userBankCache[uid]?['name'] ?? uid,
            bankInfo:     date != null ? '이체: ${FormatHelper.formatDateDot(date)}' : '',
            businessName: recs.first.businessName,
            netAmount:    _sumNet(recs),
            recordCount:  recs.length,
            isTransferred: true,
          );
        }),
        if (_hasMoreTransferred)
          _buildLoadMoreButton(
            isLoading: _isLoadingMoreTransferred,
            onTap: _loadMoreTransferred,
          ),
      ],
    );
  }

  // ─── 탭 2: 지급방식 변경 요청 ─────────────────────────────

  Widget _buildChangeRequestTab() {
    if (_changeRequests.isEmpty) {
      return _buildEmptyState('지급방식 변경 요청이 없습니다', '');
    }
    return ListView(
      padding: ResponsiveHelper.listPadding(context),
      children: _changeRequests.map((req) => _RequestCard(
        title: '${req.workerName} · 지급방식 변경',
        subtitle: req.changeDescription,
        detail: '효력: ${req.effectiveFrom}부터 · 사유: ${req.requestReason ?? '-'}',
        onApprove: () => _approveChangeRequest(req),
        onReject:  () => _rejectChangeRequest(req),
      )).toList(),
    );
  }

  // ─── 탭 3: 중간정산 요청 ──────────────────────────────────

  Widget _buildSettlementTab() {
    if (_settlementRequests.isEmpty) {
      return _buildEmptyState('중간정산 요청이 없습니다', '');
    }
    return ListView(
      padding: ResponsiveHelper.listPadding(context),
      children: _settlementRequests.map((req) => _RequestCard(
        title: '${req.workerName} · 중간정산 요청',
        subtitle: '${req.periodLabel} · ${req.recordCount}건',
        detail: '요청금액: ${FormatHelper.formatWage(req.requestedAmount)}'
            ' → 실수령: ${FormatHelper.formatWage(req.netAmount)}',
        onApprove: req.isPending ? () => _approveSettlement(req) : null,
        onReject:  req.isPending ? () => _rejectSettlement(req)  : null,
        statusLabel: req.statusLabel,
      )).toList(),
    );
  }

  Widget _buildEmptyState(String title, String subtitle) {
    return AppEmptyState(
      icon: Icons.inbox_outlined,
      title: title,
      subtitle: subtitle.isNotEmpty ? subtitle : null,
    );
  }
}


// ─── 근무자별 급여 카드 ───────────────────────────────────────────

class _WorkerPayCard extends StatelessWidget {
  final String workerName;
  final String bankInfo;
  final String? businessName; // 사업장명
  final int netAmount;
  final int recordCount;
  final bool isTransferred;
  final bool isBatchMode;
  final bool isSelected;
  // 미이체 전용 추가 필드
  final bool isOverdue;
  final bool isDueToday;
  final DateTime? dueDate;
  final int overdueCount;
  final String? scheduleLabel;
  final int? daysUntilDue;   // 양수=남은 일수, 0=오늘, 음수=연체
  final VoidCallback? onSelect;
  final VoidCallback? onMarkTransferred;

  const _WorkerPayCard({
    required this.workerName,
    required this.bankInfo,
    this.businessName,
    required this.netAmount,
    required this.recordCount,
    required this.isTransferred,
    this.isBatchMode = false,
    this.isSelected = false,
    this.isOverdue = false,
    this.isDueToday = false,
    this.dueDate,
    this.overdueCount = 0,
    this.scheduleLabel,
    this.daysUntilDue,
    this.onSelect,
    this.onMarkTransferred,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = isOverdue
        ? AppColors.error
        : isDueToday
            ? AppColors.warning
            : Colors.transparent;

    return GestureDetector(
      onTap: isBatchMode ? onSelect : null,
      child: Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primaryColor.withValues(alpha: 0.05)
              : isOverdue
                  ? AppColors.errorBg.withValues(alpha: 0.4)
                  : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.primaryColor
                : isOverdue
                    ? AppColors.error.withValues(alpha: 0.3)
                    : AppColors.grey200,
            width: (isSelected || isOverdue) ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 왼쪽 컬러 인디케이터
                if (!isTransferred) Container(width: 4, color: accentColor),

                // 카드 본문 (compact 2행)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 배치 체크박스
                        if (isBatchMode) ...[
                          Icon(
                            isSelected
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            color: isSelected
                                ? theme.primaryColor
                                : AppColors.grey400,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                        ],

                        // 이름 + 상태칩 + 계좌 (2행, 아바타 없음)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // 1행: 이름 + 지급일 인라인 칩
                              Row(children: [
                                Flexible(
                                  child: Text(
                                    workerName,
                                    style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w700),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (dueDate != null) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: _DueDateChip(
                                      dueDate: dueDate!,
                                      isOverdue: isOverdue,
                                      isDueToday: isDueToday,
                                      scheduleLabel: scheduleLabel,
                                      daysUntilDue: daysUntilDue,
                                    ),
                                  ),
                                ] else if (dueDate == null) ...[
                                  const SizedBox(width: 6),
                                  Flexible(
                                    child: Text('지급일 미설정',
                                        overflow: TextOverflow.ellipsis,
                                        style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400)),
                                  ),
                                ],
                              ]),
                              // 2행: 사업장 · 계좌 + 건수
                              const SizedBox(height: 3),
                              Row(children: [
                                Expanded(
                                  child: Text(
                                    [
                                      if (businessName != null && businessName!.isNotEmpty)
                                        businessName!,
                                      if (bankInfo.isNotEmpty) bankInfo,
                                    ].join(' · ').isNotEmpty
                                        ? [
                                            if (businessName != null && businessName!.isNotEmpty)
                                              businessName!,
                                            if (bankInfo.isNotEmpty) bankInfo,
                                          ].join(' · ')
                                        : '계좌 정보 없음',
                                    style: ResponsiveHelper.tinyStyle(context,
                                        color: bankInfo.isNotEmpty
                                            ? AppColors.grey400
                                            : AppColors.error),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text('$recordCount건',
                                    style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400)),
                              ]),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),

                        // 금액 + 버튼
                        Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              FormatHelper.formatWage(netAmount),
                              style: ResponsiveHelper.bodyStyle(context).copyWith(
                                fontWeight: FontWeight.bold,
                                color: isTransferred
                                    ? AppColors.successDark
                                    : AppColors.grey800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            if (isTransferred)
                              Row(mainAxisSize: MainAxisSize.min, children: [
                                const Icon(Icons.check_circle,
                                    size: 12, color: AppColors.success),
                                const SizedBox(width: 3),
                                Text('완료',
                                    style: ResponsiveHelper.tinyStyle(context,
                                        color: AppColors.success)),
                              ])
                            else if (!isBatchMode && onMarkTransferred != null)
                              SizedBox(
                                height: 28,
                                child: OutlinedButton(
                                  onPressed: onMarkTransferred,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.successDark,
                                    side: const BorderSide(
                                        color: AppColors.success, width: 1.2),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10),
                                    textStyle: ResponsiveHelper.tinyStyle(context, fontWeight: FontWeight.w600),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(6)),
                                  ),
                                  child: const Text('송금'),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── 요청 카드 (변경요청/중간정산) ────────────────────────────────

class _RequestCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String detail;
  final VoidCallback? onApprove;
  final VoidCallback? onReject;
  final String? statusLabel;

  const _RequestCard({
    required this.title,
    required this.subtitle,
    required this.detail,
    this.onApprove,
    this.onReject,
    this.statusLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(fontWeight: FontWeight.w700),
                    overflow: TextOverflow.ellipsis),
              ),
              if (statusLabel != null)
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 2),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.infoBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(statusLabel!,
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.infoDark,
                          fontWeight: FontWeight.w600)),
                ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(subtitle,
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey700)),
          SizedBox(height: ResponsiveHelper.spacing(context, 2)),
          Text(detail,
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.grey500)),
          if (onApprove != null || onReject != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (onReject != null)
                  OutlinedButton(
                    onPressed: onReject,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 14),
                        vertical: ResponsiveHelper.spacing(context, 6),
                      ),
                    ),
                    child: const Text('거절'),
                  ),
                if (onApprove != null) ...[
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  ElevatedButton(
                    onPressed: onApprove,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 14),
                        vertical: ResponsiveHelper.spacing(context, 6),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('승인'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── 2×2 요약 헤더 ──────────────────────────────────────────────

class _DashboardSummaryHeader extends StatelessWidget {
  final int pendingAmount;
  final int transferredAmount;
  final int pendingCount;
  final int overdueCount;
  final VoidCallback? onExportCsv;

  const _DashboardSummaryHeader({
    required this.pendingAmount,
    required this.transferredAmount,
    required this.pendingCount,
    required this.overdueCount,
    this.onExportCsv,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      color: theme.primaryColor.withValues(alpha: 0.06),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 1행: 미이체(히어로) + 연체(경고) ──────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.send_outlined,
                    size: 16, color: AppColors.warningDark),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    FormatHelper.formatWage(pendingAmount),
                    style: ResponsiveHelper.titleStyle(context,
                        color: AppColors.warningDark),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
              const SizedBox(width: 6),
              Text('미이체',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey700)),
              const Spacer(),
              if (overdueCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.errorBg,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 13, color: AppColors.errorDark),
                    const SizedBox(width: 4),
                    Text(
                      '연체 $overdueCount명',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.errorDark,
                          fontWeight: FontWeight.bold),
                    ),
                  ]),
                )
              else
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_circle_outline,
                      size: 12, color: AppColors.success),
                  const SizedBox(width: 4),
                  Text('연체 없음',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.success)),
                ]),
            ],
          ),
          const SizedBox(height: 10),
          const Divider(height: 1, color: AppColors.grey200),
          const SizedBox(height: 8),
          // ── 2행: 이체완료 | 건수 + CSV 버튼 ──────────────────
          Row(children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.check_circle_outline,
                  size: 12, color: AppColors.success),
              const SizedBox(width: 4),
              Text(
                FormatHelper.formatWage(transferredAmount),
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.successDark,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              Text('이체완료',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey700)),
            ]),
            Container(
                width: 1, height: 14,
                color: AppColors.grey200,
                margin: const EdgeInsets.symmetric(horizontal: 12)),
            Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.receipt_outlined,
                  size: 12, color: theme.primaryColor),
              const SizedBox(width: 4),
              Text(
                '$pendingCount건',
                style: ResponsiveHelper.smallStyle(context,
                    color: theme.primaryColor,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 4),
              Text('송금 건수',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey700)),
            ]),
            if (onExportCsv != null) ...[
              const Spacer(),
              SizedBox(
                height: 28,
                child: TextButton.icon(
                  onPressed: onExportCsv,
                  icon: const Icon(Icons.download_outlined, size: 14),
                  label: const Text('엑셀'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.infoDark,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 0),
                    textStyle: ResponsiveHelper.tinyStyle(context, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ]),
        ],
      ),
    );
  }
}


// ─── 지급일 인라인 칩 ─────────────────────────────────────────────

class _DueDateChip extends StatelessWidget {
  final DateTime dueDate;
  final bool isOverdue;
  final bool isDueToday;
  final String? scheduleLabel;
  final int? daysUntilDue;

  const _DueDateChip({
    required this.dueDate,
    required this.isOverdue,
    required this.isDueToday,
    this.scheduleLabel,
    this.daysUntilDue,
  });

  @override
  Widget build(BuildContext context) {
    // MM.dd 짧은 날짜
    final shortDate =
        '${dueDate.month}.${dueDate.day.toString().padLeft(2, '0')}';

    final bool isDue1 = !isOverdue && !isDueToday && daysUntilDue == 1;
    final bool isDue2 = !isOverdue && !isDueToday && daysUntilDue == 2;

    final Color chipColor = isOverdue
        ? AppColors.error
        : isDueToday
            ? AppColors.warning
            : isDue1
                ? AppColors.warningMedium
                : isDue2
                    ? AppColors.warningSoft
                    : AppColors.grey500;

    final String dateText = isOverdue
        ? '$shortDate 초과'
        : isDueToday
            ? '오늘 지급'
            : isDue1
                ? 'D-1  $shortDate'
                : isDue2
                    ? 'D-2  $shortDate'
                    : shortDate;

    final String chipText = scheduleLabel != null
        ? '$scheduleLabel · $dateText'
        : dateText;

    final bool isUrgent = isOverdue || isDueToday || isDue1 || isDue2;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (isUrgent)
          Padding(
            padding: const EdgeInsets.only(right: 2),
            child: Icon(
              isOverdue
                  ? Icons.warning_amber_rounded
                  : Icons.schedule,
              size: 10,
              color: chipColor,
            ),
          ),
        Flexible(
          child: Text(
            chipText,
            style: ResponsiveHelper.tinyStyle(context,
                color: chipColor,
                fontWeight: isUrgent
                    ? FontWeight.w700
                    : FontWeight.normal),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ]),
    );
  }
}
