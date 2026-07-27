// lib/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart
//
// 급여 지급(송금) 현황 대시보드 — 연/월 자유 탐색, 통합 이체현황 탭
// - 헤더: ← 년 → | ← 월 →
// - 필터: [월급] [주급] [일급] + 서브필터(주차/날짜)
// - 통합 이체현황 탭: 미이체(🔴) + 이체완료(🟢) 한 목록
// - 변경요청 / 중간정산 탭

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:intl/intl.dart';
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
import '../../../widgets/calendar/carrot_style_calendar.dart';
import '../../../utils/payment_due_date_calculator.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/common/gradient_scaffold.dart';
import '../../../widgets/common/app_empty_state.dart';
import '../../../widgets/common/app_search_bar.dart';
import '../../../widgets/common/app_tab_label.dart';
import '../../../widgets/common/app_batch_action_bar.dart';
import '../../../widgets/common/app_filter_chip.dart';

class PayrollPaymentDashboardScreen extends StatefulWidget {
  final String businessId;
  final String? businessName;
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

  // ── 연/월 탐색
  late int _selectedYear;
  late int _selectedMonth;

  // ── 데이터
  bool _isLoading = true;
  bool _fetchInProgress = false;
  bool _pendingReload = false;
  bool _isExporting = false;
  List<AttendanceModel> _allRecords = [];      // confirmed + transferred 합산
  List<PaymentChangeRequestModel>     _changeRequests    = [];
  List<InterimSettlementRequestModel> _settlementRequests = [];

  // ── 미이체 탭 날짜 (기본: 오늘)
  late DateTime _selectedTransferDate;

  // ── 급여형태 필터 (null=전체)
  String? _selectedPayType;  // 'monthly' | 'weekly' | 'daily' | null
  int?    _selectedWeek;     // 1‒N (주급 서브필터)
  DateTime? _selectedDay;    // 일급 서브필터

  // ── 일괄 선택
  final Set<String> _selectedIds = {};
  bool _batchMode = false;
  bool _isTransferring = false;

  // ── 검색
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // ── 계좌 정보 캐시
  final Map<String, Map<String, String>> _userBankCache = {};
  String _lastTransferNote = '';

  // ─────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _selectedYear  = widget.year;
    _selectedMonth = widget.month;
    final now = DateTime.now();
    _selectedTransferDate = DateTime(now.year, now.month, now.day);
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() {
      if (!_tabCtrl.indexIsChanging) {
        setState(() {
          _batchMode = false;
          _selectedIds.clear();
        });
      }
    });
    _searchCtrl.addListener(() =>
        setState(() => _searchQuery = _searchCtrl.text.trim()));
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ══════════════════════════════════════════════════════════
  // 데이터 로드
  // ══════════════════════════════════════════════════════════

  Future<void> _load() async {
    if (!mounted) return;
    if (_fetchInProgress) { _pendingReload = true; return; }
    _pendingReload = false;
    _fetchInProgress = true;
    if (!_isLoading) setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _payService.getPayrollRecords(
            businessId: widget.businessId,
            year: _selectedYear, month: _selectedMonth,
            wageStatus: AttendanceModel.wageConfirmed),
        _payService.getPayrollRecords(
            businessId: widget.businessId,
            year: _selectedYear, month: _selectedMonth,
            wageStatus: AttendanceModel.wageTransferred),
        _payService.getPendingChangeRequests(widget.businessId),
        _payService.getPendingSettlementRequests(widget.businessId),
      ]);

      final confirmedPage   = results[0] as PayrollPage<AttendanceModel>;
      final transferredPage = results[1] as PayrollPage<AttendanceModel>;
      final allRecs = [...confirmedPage.records, ...transferredPage.records];

      final uids = allRecs.map((r) => r.userId).toSet();
      await _loadBankInfo(uids);

      if (!mounted) return;
      setState(() {
        _allRecords         = allRecs;
        _changeRequests     = results[2] as List<PaymentChangeRequestModel>;
        _settlementRequests = results[3] as List<InterimSettlementRequestModel>;
        _selectedIds.clear();
        _batchMode = false;
      });
    } catch (e) {
      debugPrint('❌ 급여 대시보드 로드 실패: $e');
      if (mounted) ToastHelper.showError('데이터를 불러오지 못했습니다');
    } finally {
      _fetchInProgress = false;
      if (mounted) setState(() => _isLoading = false);
      // 연/월 변경으로 새 로드 요청이 밀린 경우 최신 상태로 재실행
      if (_pendingReload) _load();
    }
  }

  Future<void> _loadBankInfo(Set<String> uids) async {
    final uncached = uids.where((u) => !_userBankCache.containsKey(u)).toList();
    if (uncached.isEmpty) return;
    try {
      final userMap = await _fsService.getUsersBatch(uncached,
          businessId: widget.businessId);
      for (final uid in uncached) {
        final user = userMap[uid];
        if (user == null) continue;
        _userBankCache[uid] = {
          'name':          user.name,
          'bankName':      user.bankName      ?? '',
          'accountNumber': user.accountNumber ?? '',
          'accountHolder': user.accountHolder ?? user.name,
        };
      }
    } catch (e) {
      debugPrint('❌ 계좌 정보 배치 로드 실패: $e');
    }
  }

  // ══════════════════════════════════════════════════════════
  // 연/월 네비게이션
  // ══════════════════════════════════════════════════════════

  void _changeYear(int delta) {
    setState(() {
      _selectedYear += delta;
      _resetFilters();
    });
    _load();
  }

  void _changeMonth(int delta) {
    setState(() {
      var m = _selectedMonth + delta;
      if (m > 12) { m = 1;  _selectedYear++; }
      if (m < 1)  { m = 12; _selectedYear--; }
      _selectedMonth = m;
      _resetFilters();
    });
    _load();
  }

  void _setPayType(String? type) {
    setState(() {
      _selectedPayType = (_selectedPayType == type) ? null : type;
      _selectedWeek = null;
      _selectedDay  = null;
      _selectedIds.clear();
    });
  }

  void _resetFilters() {
    _selectedPayType = null;
    _selectedWeek    = null;
    _selectedDay     = null;
    _selectedIds.clear();
    _batchMode = false;
  }

  // ══════════════════════════════════════════════════════════
  // 주차 계산 (월~일 기준)
  // ══════════════════════════════════════════════════════════

  static List<DateTimeRange> _calcWeekRanges(int year, int month) {
    final lastDay = DateTime(year, month + 1, 0);

    // 1일이 포함된 주의 월요일부터 시작 (첫째 주가 이전 달로 넘어갈 수 있음)
    final firstDay = DateTime(year, month, 1);
    final daysToMonday = (firstDay.weekday - 1) % 7; // 이전 월요일까지 역산
    DateTime weekStart = firstDay.subtract(Duration(days: daysToMonday));

    final ranges = <DateTimeRange>[];
    while (!weekStart.isAfter(lastDay)) {
      // 일요일까지 — 다음 달로 넘어가도 클립하지 않음 (주는 항상 월~일 전체)
      final weekEnd = weekStart.add(const Duration(days: 6));
      ranges.add(DateTimeRange(start: weekStart, end: weekEnd));
      weekStart = weekStart.add(const Duration(days: 7));
    }

    while (ranges.length < 4) {
      final next = ranges.last.start.add(const Duration(days: 7));
      ranges.add(DateTimeRange(start: next, end: next.add(const Duration(days: 6))));
    }
    return ranges;
  }

  static String _weekRangeLabel(DateTimeRange range, int baseMonth) {
    final s = range.start;
    final e = range.end;
    final startLabel = '${s.day}';
    final endLabel = e.month != baseMonth ? '${e.month}/${e.day}' : '${e.day}';
    return '$startLabel~$endLabel';
  }

  // ══════════════════════════════════════════════════════════
  // 필터링 + 그룹핑
  // ══════════════════════════════════════════════════════════

  List<MapEntry<String, List<AttendanceModel>>> _getFilteredGroups() {
    var recs = _allRecords.toList();

    // 1. 급여형태 필터
    if (_selectedPayType != null) {
      recs = recs.where((r) {
        final t = r.wageDetail?.payScheduleType;
        if (t == null) return false;
        return switch (_selectedPayType!) {
          'monthly' => t == 'monthly',
          'weekly'  => t == 'weekly',
          'daily'   => t == 'same_day' || t == 'next_day',
          _         => true,
        };
      }).toList();
    }

    // 2. 서브필터 (workDate 기준 — 실제 근무한 날짜로 필터)
    if (_selectedPayType == 'weekly' && _selectedWeek != null) {
      final weeks = _calcWeekRanges(_selectedYear, _selectedMonth);
      final idx = _selectedWeek! - 1;
      if (idx >= 0 && idx < weeks.length) {
        final range = weeks[idx];
        recs = recs.where((r) {
          final wd = r.workDate;
          final d = DateTime(wd.year, wd.month, wd.day);
          return !d.isBefore(range.start) && !d.isAfter(range.end);
        }).toList();
      }
    } else if (_selectedPayType == 'daily' && _selectedDay != null) {
      final day = _selectedDay!;
      recs = recs.where((r) {
        final wd = r.workDate;
        return wd.year == day.year && wd.month == day.month && wd.day == day.day;
      }).toList();
    }

    // 3. 그룹핑 (uid::YYYY-MM-DD)
    final map = <String, List<AttendanceModel>>{};
    for (final r in recs) {
      final due = r.paymentDueDate;
      final duePart = due != null
          ? '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}'
          : 'no_date';
      (map['${r.userId}::$duePart'] ??= []).add(r);
    }

    // 4. 검색 필터
    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      map.removeWhere((key, _) {
        final uid  = key.split('::').first;
        final name = (_userBankCache[uid]?['name'] ?? uid).toLowerCase();
        return !name.contains(q);
      });
    }

    // 5. 정렬: 미이체(연체→오늘→예정) → 이체완료
    return map.entries.toList()
      ..sort((a, b) {
        final aXfer = a.value.every((r) => r.wageStatus == AttendanceModel.wageTransferred);
        final bXfer = b.value.every((r) => r.wageStatus == AttendanceModel.wageTransferred);
        if (!aXfer &&  bXfer) return -1;
        if ( aXfer && !bXfer) return 1;
        if (!aXfer) {
          final aOver  = _groupIsOverdue(a.value);
          final bOver  = _groupIsOverdue(b.value);
          final aToday = _groupIsDueToday(a.value);
          final bToday = _groupIsDueToday(b.value);
          if ( aOver && !bOver)  return -1;
          if (!aOver &&  bOver)  return 1;
          if ( aToday && !bToday) return -1;
          if (!aToday &&  bToday) return 1;
        }
        return 0;
      });
  }

  // ── 미이체 날짜별 인원 수 계산 ────────────────────────────
  Map<DateTime, int> _buildPendingCountByDate() {
    final usersByDate = <DateTime, Set<String>>{};
    for (final r in _allRecords) {
      if (r.wageStatus != AttendanceModel.wageConfirmed) continue;
      final due = r.paymentDueDate;
      if (due == null) continue;
      final key = DateTime(due.year, due.month, due.day);
      (usersByDate[key] ??= {}).add(r.userId);
    }
    return usersByDate.map((k, v) => MapEntry(k, v.length));
  }

  // 이체현황 탭 일급 날짜 필터 — CarrotStyleCalendar 바텀시트
  Future<void> _showDayCalendar() async {
    final firstDay = DateTime(_selectedYear, _selectedMonth, 1);
    final lastDay  = DateTime(_selectedYear, _selectedMonth + 1, 0);
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            CarrotStyleCalendar(
              mode: CalendarMode.single,
              focusedMonth: firstDay,
              selectedDate: _selectedDay,
              minDate: firstDay,
              maxDate: lastDay,
              allowPastDates: true,
              onDateSelected: (date) => Navigator.pop(ctx, date),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDay = picked);
    }
  }

  Future<void> _showPendingCalendar() async {
    final countByDate = _buildPendingCountByDate();
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PendingCalendarSheet(
        initialDate: _selectedTransferDate,
        countByDate: countByDate,
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedTransferDate =
          DateTime(picked.year, picked.month, picked.day));
    }
  }

  // ── 미이체 탭: paymentDueDate 기준 필터 ──────────────────
  List<MapEntry<String, List<AttendanceModel>>> _getPendingGroups() {
    final target = _selectedTransferDate;
    final recs = _allRecords.where((r) {
      if (r.wageStatus != AttendanceModel.wageConfirmed) return false;
      final due = r.paymentDueDate;
      if (due == null) return false;
      return due.year == target.year &&
             due.month == target.month &&
             due.day == target.day;
    }).toList();

    final map = <String, List<AttendanceModel>>{};
    for (final r in recs) {
      final due = r.paymentDueDate!;
      final duePart =
          '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
      (map['${r.userId}::$duePart'] ??= []).add(r);
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      map.removeWhere((key, _) {
        final uid  = key.split('::').first;
        final name = (_userBankCache[uid]?['name'] ?? uid).toLowerCase();
        return !name.contains(q);
      });
    }

    return map.entries.toList();
  }

  // ── 그룹 헬퍼 ────────────────────────────────────────────
  static DateTime get _today {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  String _uidFromKey(String key) => key.split('::').first;

  DateTime? _dueDateFromKey(String key) {
    final part = key.split('::').last;
    if (part == 'no_date') return null;
    return DateTime.tryParse(part);
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

  String? _scheduleLabel(List<AttendanceModel> recs) {
    for (final r in recs) {
      final t = r.wageDetail?.payScheduleType;
      if (t != null) return PaymentDueDateCalculator.label(t);
    }
    return null;
  }

  int _sumNet(List<AttendanceModel> recs) => recs.fold(0, (acc, r) {
    final wd = r.wageDetail;
    return wd == null ? acc : acc + wd.effectiveNetWage;
  });

  int get _selectedNet =>
      _sumNet(_allRecords.where((r) => _selectedIds.contains(r.id)).toList());

  String get _uid => context.read<UserProvider>().currentUser?.uid ?? '';

  // ══════════════════════════════════════════════════════════
  // 이체 처리
  // ══════════════════════════════════════════════════════════

  Future<void> _markWorker(List<AttendanceModel> recs) async {
    if (_isTransferring || recs.isEmpty) return;
    setState(() => _isTransferring = true);
    try {
      final uid = context.read<UserProvider>().currentUser?.uid ?? '';
      if (uid.isEmpty) { ToastHelper.showError('로그인 정보를 확인해주세요'); return; }

      final workerName = _userBankCache[recs.first.userId]?['name'] ?? recs.first.userId;
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

      final note = await _showTransferNoteDialog();
      if (!mounted) return;

      if (recs.length == 1) {
        final r  = recs.first;
        final wd = r.wageDetail;
        await _payService.markTransferred(
          attendanceId:  r.id,
          businessId:    r.businessId,
          transferNote:  note,
          workerUserId:  r.userId,
          workerName:    workerName,
          businessName:  r.businessName,
          finalWage:     wd?.effectiveNetWage ?? 0,
          applicationId: r.applicationId,
        );
      } else {
        final nameByUid = Map.fromEntries(
          _userBankCache.entries.map((e) => MapEntry(e.key, e.value['name'] ?? e.key)));
        await _payService.markTransferredBatch(
          attendanceIds:     recs.map((r) => r.id).toList(),
          businessId:        recs.first.businessId,
          transferNote:      note,
          notificationInfos: buildTransferNotificationInfos(
            records: recs, workerNameByUid: nameByUid),
        );
      }
      if (mounted) {
        ToastHelper.showSuccess('${recs.length}건 송금 처리되었습니다');
        _load();
      }
    } catch (e) {
      debugPrint('❌ 송금 처리 실패: $e');
      if (mounted) ToastHelper.showError('송금 처리에 실패했습니다\n$e');
      if (mounted) _load();
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  Future<void> _markBatch() async {
    if (_isTransferring || _selectedIds.isEmpty) return;
    setState(() => _isTransferring = true);
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
      if (uid.isEmpty) { ToastHelper.showError('로그인 정보를 확인해주세요'); return; }

      final note = await _showTransferNoteDialog();
      if (!mounted) return;

      final selectedRecords = _allRecords.where((r) => _selectedIds.contains(r.id)).toList();
      if (selectedRecords.isEmpty) {
        if (mounted) ToastHelper.showError('이체할 항목을 찾을 수 없습니다. 화면을 새로고침하세요');
        return;
      }
      final nameByUid = Map.fromEntries(
        _userBankCache.entries.map((e) => MapEntry(e.key, e.value['name'] ?? e.key)));

      await _payService.markTransferredBatch(
        attendanceIds:     _selectedIds.toList(),
        businessId:        selectedRecords.first.businessId,
        transferNote:      note,
        notificationInfos: buildTransferNotificationInfos(
          records: selectedRecords, workerNameByUid: nameByUid),
      );
      if (mounted) {
        ToastHelper.showSuccess('${_selectedIds.length}건 이체 완료 처리되었습니다');
        _load();
      }
    } catch (e) {
      debugPrint('❌ 일괄 이체 실패: $e');
      if (mounted) ToastHelper.showError('일괄 처리에 실패했습니다\n$e');
      if (mounted) _load();
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
              Container(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryColor, primaryColor.withValues(alpha: 0.85)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
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
                    child: const Icon(Icons.edit_note_rounded, color: Colors.white, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('이체 메모',
                          style: ResponsiveHelper.subtitleStyle(ctx)
                              .copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                      Text('선택 입력',
                          style: ResponsiveHelper.tinyStyle(ctx,
                              color: Colors.white.withValues(alpha: 0.75))),
                    ]),
                  ),
                ]),
              ),
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
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    final result = (note == null || note.isEmpty) ? null : note;
    if (result != null) _lastTransferNote = result;
    return result;
  }

  // ── 엑셀 내보내기 ─────────────────────────────────────────
  // 이체현황 탭 — 회계/세무용 건별 상세 시트
  Future<void> _exportCsv(
      List<AttendanceModel> pendingRecs,
      List<AttendanceModel> allFilteredRecs,
  ) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final bizName   = widget.businessName ?? widget.businessId;
      final typeLabel = _payTypeDisplayLabel(_selectedPayType);
      final suffix    = typeLabel != null ? '_$typeLabel' : '';
      await PayrollExcelHelper.exportPayrollDetail(
        context:    context,
        records:    allFilteredRecs,
        title:      '$bizName $_selectedYear년 $_selectedMonth월 급여현황$suffix',
        filename:   '${bizName}_$_selectedYear년$_selectedMonth월_급여현황$suffix.xlsx',
        businessId: widget.businessId,
      );
    } catch (e) {
      debugPrint('❌ 엑셀 내보내기 실패: $e');
      if (mounted) ToastHelper.showError('엑셀 내보내기에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  // 미이체 탭 — 은행 이체 전용 단순 시트
  Future<void> _exportPendingCsv(List<AttendanceModel> pendingRecs) async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final d       = _selectedTransferDate;
      final bizName = widget.businessName ?? widget.businessId;
      await PayrollExcelHelper.exportTransferList(
        context:    context,
        records:    pendingRecs,
        title:      '$bizName ${d.year}년 ${d.month}월 ${d.day}일 미이체 목록',
        filename:   '${bizName}_${d.year}년${d.month}월${d.day}일_미이체목록.xlsx',
        businessId: widget.businessId,
      );
    } catch (e) {
      debugPrint('❌ 미이체 엑셀 내보내기 실패: $e');
      if (mounted) ToastHelper.showError('엑셀 내보내기에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  static String? _payTypeDisplayLabel(String? type) => switch (type) {
    'monthly' => '월급',
    'weekly'  => '주급',
    'daily'   => '일급',
    _         => null,
  };

  // ── 중간정산 ──────────────────────────────────────────────

  /// PENDING → APPROVED (이체예정일 지정 + 근로자 FCM)
  Future<void> _approveSettlement(InterimSettlementRequestModel req) async {
    if (_isTransferring) return;
    setState(() => _isTransferring = true);
    try {
      // 1단계: 이체예정일 선택
      final today = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: today,
        firstDate: today,
        lastDate: today.add(const Duration(days: 90)),
        helpText: '이체 예정일 선택',
        confirmText: '확인',
        cancelText: '취소',
      );
      if (picked == null || !mounted) return;

      // 2단계: 확인 다이얼로그
      final ok = await DialogHelper.showConfirm(
        context,
        title: '중간정산 승인',
        message: '${req.workerName}님의 중간정산을 승인합니다.\n'
            '기간: ${req.periodLabel} (${req.recordCount}건)\n'
            '금액: ${FormatHelper.formatWage(req.netAmount)}\n'
            '이체 예정일: ${DateFormat('yyyy년 MM월 dd일').format(picked)}\n\n'
            '승인 시 근로자에게 알림이 전송됩니다.',
        confirmText: '승인',
        cancelText: '취소',
      );
      if (ok != true || !mounted) return;

      await _payService.approveInterimSettlementWithDate(
        req: req,
        scheduledTransferDate: picked,
      );
      if (mounted) { ToastHelper.showSuccess('중간정산 승인 완료 — 이체 예정일: ${DateFormat('MM/dd').format(picked)}'); _load(); }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리에 실패했습니다\n$e');
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  /// APPROVED → PROCESSED (출근기록 wageTransferred 원자 처리)
  Future<void> _processSettlement(InterimSettlementRequestModel req) async {
    if (_isTransferring) return;
    setState(() => _isTransferring = true);
    try {
      final ok = await DialogHelper.showConfirm(
        context,
        title: '중간정산 이체 처리',
        message: '${req.workerName}님의 중간정산을 이체 완료 처리합니다.\n'
            '기간: ${req.periodLabel} (${req.recordCount}건)\n'
            '금액: ${FormatHelper.formatWage(req.netAmount)}\n\n'
            '처리 시 해당 출근기록이 모두 이체완료 상태로 변경됩니다.',
        confirmText: '이체 처리',
        cancelText: '취소',
      );
      if (ok != true || !mounted) return;
      final note = await _showTransferNoteDialog();
      if (!mounted) return;
      await _payService.processInterimSettlement(req: req, transferNote: note);
      if (mounted) { ToastHelper.showSuccess('이체 처리 완료'); _load(); }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리에 실패했습니다\n$e');
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  Future<void> _rejectSettlement(InterimSettlementRequestModel req) async {
    if (_isTransferring) return;
    final ctrl = TextEditingController();
    setState(() => _isTransferring = true);
    try {
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
      if (reason == null || reason.isEmpty || !mounted) return;
      await _payService.rejectInterimSettlement(
          req: req, processedBy: _uid, rejectReason: reason);
      if (mounted) { ToastHelper.showSuccess('거절 처리되었습니다'); _load(); }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리에 실패했습니다\n$e');
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  // ── 변경요청 ──────────────────────────────────────────────
  Future<void> _approveChangeRequest(PaymentChangeRequestModel req) async {
    if (_isTransferring) return;
    setState(() => _isTransferring = true);
    try {
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
      await _payService.approveChangeRequest(requestId: req.id, processedBy: _uid);
      if (mounted) { ToastHelper.showSuccess('변경 요청이 승인되었습니다'); _load(); }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리에 실패했습니다\n$e');
    } finally {
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  Future<void> _rejectChangeRequest(PaymentChangeRequestModel req) async {
    if (_isTransferring) return;
    final ctrl = TextEditingController();
    setState(() => _isTransferring = true);
    try {
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
      if (reason == null || reason.isEmpty || !mounted) return;
      await _payService.rejectChangeRequest(
          requestId: req.id, processedBy: _uid, rejectReason: reason);
      if (mounted) { ToastHelper.showSuccess('거절 처리되었습니다'); _load(); }
    } catch (e) {
      if (mounted) ToastHelper.showError('처리에 실패했습니다\n$e');
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
      if (mounted) setState(() => _isTransferring = false);
    }
  }

  void _toggleBatchMode() {
    setState(() {
      _batchMode = !_batchMode;
      if (!_batchMode) _selectedIds.clear();
    });
  }

  // ══════════════════════════════════════════════════════════
  // UI
  // ══════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientScaffold(
      title: '급여 지급 현황',
      onRefresh: _load,
      body: _isLoading
          ? const LoadingWidget(message: '급여 현황 불러오는 중...')
          : Column(children: [
              // ── 검색바
              AppSearchBar(controller: _searchCtrl, hintText: '근무자 이름으로 검색'),
              // ── 탭바
              Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabCtrl,
                  isScrollable: false,
                  labelColor: theme.primaryColor,
                  unselectedLabelColor: AppColors.grey500,
                  indicatorColor: theme.primaryColor,
                  indicatorWeight: 2.5,
                  dividerColor: AppColors.grey100,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                  labelStyle: ResponsiveHelper.smallStyle(context, fontWeight: FontWeight.w600),
                  unselectedLabelStyle: ResponsiveHelper.smallStyle(context),
                  tabs: [
                    Tab(child: AppTabLabel(
                        label: '미이체',
                        count: _allRecords
                            .where((r) => r.wageStatus == AttendanceModel.wageConfirmed)
                            .map((r) => r.userId)
                            .toSet()
                            .length,
                        badgeColor: AppColors.error,
                        urgent: _allRecords.any((r) => r.wageStatus == AttendanceModel.wageConfirmed))),
                    Tab(child: AppTabLabel(label: '이체현황')),
                    Tab(child: AppTabLabel(
                        label: '변경요청',
                        count: _changeRequests.length,
                        badgeColor: AppColors.info)),
                    Tab(child: AppTabLabel(
                        label: '중간정산',
                        count: _settlementRequests.length,
                        badgeColor: AppColors.grey500)),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabCtrl,
                  children: [
                    _buildPendingTransferTab(),
                    _buildTransferTab(),
                    _buildChangeRequestTab(),
                    _buildSettlementTab(),
                  ],
                ),
              ),
            ]),
    );
  }

  // ─── 연/월 헤더 ───────────────────────────────────────────
  Widget _buildYearMonthHeader(ThemeData theme) {
    return Container(
      color: theme.primaryColor.withValues(alpha: 0.04),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // ← 년도 →
          _NavArrow(onTap: () => _changeYear(-1), icon: Icons.chevron_left),
          Text('$_selectedYear년',
              style: ResponsiveHelper.subtitleStyle(context,
                  fontWeight: FontWeight.w700)),
          _NavArrow(onTap: () => _changeYear(1), icon: Icons.chevron_right),
          const SizedBox(width: 16),
          Container(width: 1, height: 16, color: AppColors.grey300),
          const SizedBox(width: 16),
          // ← 월 →
          _NavArrow(onTap: () => _changeMonth(-1), icon: Icons.chevron_left),
          Text('$_selectedMonth월',
              style: ResponsiveHelper.subtitleStyle(context,
                  fontWeight: FontWeight.w700)),
          _NavArrow(onTap: () => _changeMonth(1), icon: Icons.chevron_right),
        ],
      ),
    );
  }

  // ─── 미이체 탭 ───────────────────────────────────────────
  Widget _buildPendingTransferTab() {
    final groups      = _getPendingGroups();
    final pendingRecs = groups.expand((e) => e.value).toList();
    final totalNet    = _sumNet(pendingRecs);
    final allIds      = groups.expand((e) => e.value.map((r) => r.id)).toSet();
    final d           = _selectedTransferDate;
    final isToday     = d == _today;

    // 이체 예정일이 선택 날짜 이하인 APPROVED 중간정산 → 미이체 탭 상단 표시
    final approvedSettlements = _settlementRequests.where((req) {
      if (!req.isApproved) return false;
      final sd = req.scheduledTransferDate;
      if (sd == null) return false;
      final sdDay = DateTime(sd.year, sd.month, sd.day);
      return !sdDay.isAfter(d);
    }).toList();

    return Column(children: [
      // ── 날짜 피커
      _buildPendingDatePicker(d, isToday),

      // ── 요약 헤더 — 이체현황 탭과 동일한 배경색
      Container(
        color: Theme.of(context).primaryColor.withValues(alpha: 0.04),
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 액션 버튼 행
            Row(children: [
              const Spacer(),
              SizedBox(
                height: 26,
                child: TextButton.icon(
                  onPressed: _isExporting ? null : () => _exportPendingCsv(pendingRecs),
                  icon: _isExporting
                      ? const SizedBox(width: 11, height: 11,
                          child: CircularProgressIndicator(strokeWidth: 1.5))
                      : const Icon(Icons.download_outlined, size: 13),
                  label: const Text('엑셀'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.infoDark,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    textStyle: ResponsiveHelper.tinyStyle(context, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                height: 26,
                child: OutlinedButton.icon(
                  onPressed: _toggleBatchMode,
                  icon: Icon(_batchMode ? Icons.close : Icons.checklist_outlined, size: 13),
                  label: Text(_batchMode ? '취소' : '일괄'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _batchMode ? AppColors.error : AppColors.grey600,
                    side: BorderSide(
                        color: _batchMode ? AppColors.error : AppColors.grey300),
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    textStyle: ResponsiveHelper.tinyStyle(context, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            // 미이체 요약 박스 — 이체현황 오렌지 카드와 동일 스타일
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.errorBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
              ),
              child: Row(children: [
                const Icon(Icons.schedule_outlined, size: 16, color: AppColors.error),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('미이체',
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.errorDark, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(
                      FormatHelper.formatWage(totalNet),
                      style: ResponsiveHelper.titleStyle(context, color: AppColors.errorDark)
                          .copyWith(fontSize: 22, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.error,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text('${groups.length}명',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ],
        ),
      ),

      // ── 일괄 선택 바
      if (_batchMode)
        AppBatchActionBar(
          selectedCount:  _selectedIds.length,
          selectedAmount: _selectedNet,
          onSelectAll:    () => setState(() => _selectedIds.addAll(allIds)),
          onDeselectAll:  () => setState(() => _selectedIds.clear()),
          onAction: _selectedIds.isNotEmpty && _selectedNet > 0 ? _markBatch : null,
          actionLabel: '송금',
          actionIcon: Icons.send,
        ),

      // ── 목록
      Expanded(
        child: (groups.isEmpty && approvedSettlements.isEmpty)
            ? AppEmptyState(
                icon: Icons.check_circle_outline,
                title: isToday
                    ? '오늘 이체할 내역이 없습니다'
                    : '${d.month}월 ${d.day}일 이체할 내역이 없습니다',
                subtitle: '미이체 건이 없거나 모두 처리되었습니다',
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: ResponsiveHelper.listPadding(context).copyWith(top: 8),
                  // approvedSettlements 섹션 헤더 + 카드들 + 일반 그룹
                  itemCount: (approvedSettlements.isEmpty ? 0 : approvedSettlements.length + 1) + groups.length,
                  itemBuilder: (ctx, i) {
                    // ── 중간정산 APPROVED 섹션 ──
                    final settlementOffset = approvedSettlements.isEmpty ? 0 : approvedSettlements.length + 1;
                    if (approvedSettlements.isNotEmpty) {
                      if (i == 0) {
                        // 섹션 헤더
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6, top: 4),
                          child: Row(children: [
                            Container(width: 3, height: 14, color: AppColors.teal,
                                margin: const EdgeInsets.only(right: 6)),
                            Text('중간정산 이체 대기',
                                style: ResponsiveHelper.smallStyle(ctx,
                                    color: AppColors.tealDark,
                                    fontWeight: FontWeight.w700)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.tealBg,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('${approvedSettlements.length}건',
                                  style: ResponsiveHelper.tinyStyle(ctx, color: AppColors.tealDark)),
                            ),
                          ]),
                        );
                      }
                      if (i <= approvedSettlements.length) {
                        final req = approvedSettlements[i - 1];
                        final sdLabel = req.scheduledTransferDate != null
                            ? DateFormat('MM/dd').format(req.scheduledTransferDate!)
                            : '-';
                        return _RequestCard(
                          title:       '${req.workerName} · 중간정산',
                          subtitle:    '${req.periodLabel} · ${req.recordCount}건  ·  이체 예정일 $sdLabel',
                          detail:      '실수령: ${FormatHelper.formatWage(req.netAmount)}',
                          onProcess:   () => _processSettlement(req),
                          statusLabel: '이체 대기',
                        );
                      }
                    }

                    // ── 일반 미이체 그룹 ──
                    final entry    = groups[i - settlementOffset];
                    final uid      = _uidFromKey(entry.key);
                    final recs     = entry.value;
                    final bank     = _userBankCache[uid];
                    final net      = _sumNet(recs);
                    final dueDate  = _dueDateFromKey(entry.key) ?? _earliestDue(recs);
                    final isOver   = _groupIsOverdue(recs);
                    final isToday2 = _groupIsDueToday(recs);
                    final schLabel = _scheduleLabel(recs);
                    final daysUntil= dueDate?.difference(_today).inDays;
                    final allSel   = recs.every((r) => _selectedIds.contains(r.id));
                    final bankStr  = bank?['bankName'] != null
                        ? '${bank!['bankName']} ${bank['accountNumber']}'
                        : '계좌 정보 없음';

                    final workerName = bank?['name'] ?? uid;
                    return _WorkerPayCard(
                      workerName:    workerName,
                      bankInfo:      bankStr,
                      businessName:  recs.first.businessName,
                      netAmount:     net,
                      recordCount:   recs.length,
                      isTransferred: false,
                      isPending:     true,
                      isBatchMode:   _batchMode,
                      isSelected:    allSel,
                      isOverdue:     isOver,
                      isDueToday:    isToday2,
                      dueDate:       dueDate,
                      scheduleLabel: schLabel,
                      daysUntilDue:  daysUntil,
                      onCardTap: !_batchMode ? () async {
                        final up = Provider.of<UserProvider>(context, listen: false);
                        final canCancel = up.isBusinessAdmin ||
                            (up.memberPermissions?.canCancelTransfer ?? false);
                        final result = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _WorkerPayDetailScreen(
                              workerName: workerName,
                              records:    recs,
                              bankInfo:   bankStr,
                              canCancelTransfer: canCancel,
                            ),
                          ),
                        );
                        if (result == true && mounted) _load();
                      } : null,
                      onSelect: _batchMode ? () {
                        setState(() {
                          if (allSel) {
                            _selectedIds.removeAll(recs.map((r) => r.id));
                          } else {
                            _selectedIds.addAll(recs.map((r) => r.id));
                          }
                        });
                      } : null,
                      onMarkTransferred: !_batchMode ? () => _markWorker(recs) : null,
                    );
                  },
                ),
              ),
      ),
    ]);
  }

  Widget _buildPendingDatePicker(DateTime d, bool isToday) {
    return Container(
      color: AppColors.grey50,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Row(children: [
        _NavArrow(
          onTap: () => setState(() =>
              _selectedTransferDate = d.subtract(const Duration(days: 1))),
          icon: Icons.chevron_left,
        ),
        Expanded(
          child: GestureDetector(
            onTap: _showPendingCalendar,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.calendar_today, size: 14, color: AppColors.grey600),
                const SizedBox(width: 6),
                Text(
                  '${d.year}년 ${d.month}월 ${d.day}일',
                  style: ResponsiveHelper.bodyStyle(context,
                      fontWeight: FontWeight.w700),
                ),
                if (isToday) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text('오늘',
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.warningDark,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ],
            ),
          ),
        ),
        _NavArrow(
          onTap: () => setState(() =>
              _selectedTransferDate = d.add(const Duration(days: 1))),
          icon: Icons.chevron_right,
        ),
      ]),
    );
  }

  // ─── 이체현황 탭 ──────────────────────────────────────────
  Widget _buildTransferTab() {
    final groups = _getFilteredGroups();

    final pendingGroups  = groups.where((e) =>
        !e.value.every((r) => r.wageStatus == AttendanceModel.wageTransferred)).toList();
    final completedGroups = groups.where((e) =>
        e.value.every((r) => r.wageStatus == AttendanceModel.wageTransferred)).toList();

    final pendingRecords   = pendingGroups.expand((e) => e.value).toList();
    final allFilteredRecs  = groups.expand((e) => e.value).toList();

    // 연체 카운트 (미이체 그룹만)
    final overdueCount = pendingGroups.where((e) => _groupIsOverdue(e.value)).length;

    return Column(children: [
      // ── 연/월 헤더 (이체현황 탭 전용)
      _buildYearMonthHeader(Theme.of(context)),
      // ── 급여형태 필터 칩
      _buildPayTypeChips(allFilteredRecs),

      // ── 서브필터 (주급→주차, 일급→날짜)
      if (_selectedPayType == 'weekly') _buildWeekSubFilter(),
      if (_selectedPayType == 'daily')  _buildDaySubFilter(),

      // ── 요약 헤더 (필터 적용된 금액 기준, 일괄선택 없음)
      // 부분이체 근로자: wageTransferred/wageConfirmed 기록이 혼재하므로
      // 상태별로 직접 필터링해야 정확한 금액이 나온다.
      _DashboardSummaryHeader(
        pendingAmount:     _sumNet(allFilteredRecs.where((r) => r.wageStatus == AttendanceModel.wageConfirmed).toList()),
        transferredAmount: _sumNet(allFilteredRecs.where((r) => r.wageStatus == AttendanceModel.wageTransferred).toList()),
        pendingCount:      pendingGroups.length,
        completedCount:    completedGroups.length,
        overdueCount:      overdueCount,
        isExporting:       _isExporting,
        onExportCsv:       () => _exportCsv(pendingRecords, allFilteredRecs),
      ),

      // ── 목록
      Expanded(
        child: groups.isEmpty
            ? AppEmptyState(
                icon: Icons.inbox_outlined,
                title: _searchQuery.isNotEmpty
                    ? '"$_searchQuery" 검색 결과 없음'
                    : '$_selectedYear년 $_selectedMonth월 이체 내역이 없습니다',
                subtitle: _searchQuery.isNotEmpty
                    ? '다른 이름으로 검색해 보세요'
                    : '확정된 급여가 없거나 모두 처리되었습니다',
              )
            : RefreshIndicator(
                onRefresh: _load,
                child: ListView.builder(
                  padding: ResponsiveHelper.listPadding(context).copyWith(top: 8),
                  itemCount: groups.length,
                  itemBuilder: (ctx, i) {
                    final entry      = groups[i];
                    final groupKey   = entry.key;
                    final uid        = _uidFromKey(groupKey);
                    final recs       = entry.value;
                    final bank       = _userBankCache[uid];
                    final isXfer     = recs.every((r) => r.wageStatus == AttendanceModel.wageTransferred);
                    final isPartial  = !isXfer && recs.any((r) => r.wageStatus == AttendanceModel.wageTransferred);
                    final net        = _sumNet(recs);
                    final dueDate    = _dueDateFromKey(groupKey) ?? _earliestDue(recs);
                    final isOverdue  = !isXfer && _groupIsOverdue(recs);
                    final isDueToday = !isXfer && _groupIsDueToday(recs);
                    final schLabel   = _scheduleLabel(recs);
                    final daysUntil  = dueDate?.difference(_today).inDays;

                    // 이체완료인 경우 bankInfo 대신 이체일 표시
                    final bankInfoStr = isXfer
                        ? (recs.last.transferDate != null
                            ? '이체: ${FormatHelper.formatDateDot(recs.last.transferDate!)}'
                            : '이체완료')
                        : isPartial
                            ? '부분이체 완료'
                            : (bank?['bankName'] != null
                                ? '${bank!['bankName']} ${bank['accountNumber']}'
                                : '계좌 정보 없음');

                    return _WorkerPayCard(
                      workerName:              bank?['name'] ?? uid,
                      bankInfo:                bankInfoStr,
                      businessName:            recs.first.businessName,
                      netAmount:               net,
                      recordCount:             recs.length,
                      isTransferred:           isXfer,
                      isPartiallyTransferred:  isPartial,
                      isOverdue:               isOverdue,
                      isDueToday:              isDueToday,
                      dueDate:                 dueDate,
                      scheduleLabel:           schLabel,
                      daysUntilDue:            daysUntil,
                      onCardTap: () async {
                        final up = Provider.of<UserProvider>(context, listen: false);
                        final canCancel = up.isBusinessAdmin ||
                            (up.memberPermissions?.canCancelTransfer ?? false);
                        final result = await Navigator.push<bool>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _WorkerPayDetailScreen(
                              workerName: bank?['name'] ?? uid,
                              records:    recs,
                              bankInfo:   bank?['bankName'] != null
                                  ? '${bank!['bankName']} ${bank['accountNumber'] ?? ''}'.trim()
                                  : null,
                              canCancelTransfer: canCancel,
                            ),
                          ),
                        );
                        if (result == true && mounted) _load();
                      },
                    );
                  },
                ),
              ),
      ),
    ]);
  }

  // ─── 급여형태 필터 칩 ─────────────────────────────────────
  Widget _buildPayTypeChips(List<AttendanceModel> filtered) {
    // 각 유형 카운트 — 인원 수(distinct userId) 기준
    int countOf(String payType) => _allRecords.where((r) {
      final t = r.wageDetail?.payScheduleType;
      return switch (payType) {
        'monthly' => t == 'monthly',
        'weekly'  => t == 'weekly',
        'daily'   => t == 'same_day' || t == 'next_day',
        _         => false,
      };
    }).map((r) => r.userId).toSet().length;

    final totalCount = countOf('monthly') + countOf('weekly') + countOf('daily');

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          AppFilterChip(
            label: '전체',
            count: totalCount,
            isSelected: _selectedPayType == null,
            color: AppColors.grey800,
            onTap: () => _setPayType(null),
          ),
          const SizedBox(width: 6),
          AppFilterChip(
            label: '월급',
            count: countOf('monthly'),
            isSelected: _selectedPayType == 'monthly',
            color: AppColors.successDark,
            onTap: () => _setPayType('monthly'),
          ),
          const SizedBox(width: 6),
          AppFilterChip(
            label: '주급',
            count: countOf('weekly'),
            isSelected: _selectedPayType == 'weekly',
            color: AppColors.infoDark,
            onTap: () => _setPayType('weekly'),
          ),
          const SizedBox(width: 6),
          AppFilterChip(
            label: '일급',
            count: countOf('daily'),
            isSelected: _selectedPayType == 'daily',
            color: AppColors.warningDark,
            onTap: () => _setPayType('daily'),
          ),
        ]),
      ),
    );
  }

  // ─── 주급 서브필터 (주차 칩) ──────────────────────────────
  Widget _buildWeekSubFilter() {
    final weeks = _calcWeekRanges(_selectedYear, _selectedMonth);
    return Padding(
      padding: EdgeInsets.only(
        left: ResponsiveHelper.spacing(context, 12),
        right: ResponsiveHelper.spacing(context, 12),
        bottom: ResponsiveHelper.spacing(context, 2),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(weeks.length, (i) {
            final weekNum = i + 1;
            final range   = weeks[i];
            final isSelected = _selectedWeek == weekNum;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: AppFilterChip(
                label: '$weekNum주 (${_weekRangeLabel(range, _selectedMonth)})',
                isSelected: isSelected,
                color: AppColors.infoDark,
                onTap: () => setState(() {
                  _selectedWeek = isSelected ? null : weekNum;
                }),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ─── 일급 서브필터 (날짜 선택) ───────────────────────────
  Widget _buildDaySubFilter() {
    return Padding(
      padding: EdgeInsets.only(
        left: ResponsiveHelper.spacing(context, 12),
        right: ResponsiveHelper.spacing(context, 12),
        bottom: ResponsiveHelper.spacing(context, 2),
      ),
      child: Row(children: [
        GestureDetector(
          onTap: _showDayCalendar,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _selectedDay != null ? AppColors.infoBg : AppColors.grey100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _selectedDay != null ? AppColors.info : AppColors.grey300),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.calendar_today, size: 13,
                  color: _selectedDay != null ? AppColors.infoDark : AppColors.grey500),
              const SizedBox(width: 5),
              Text(
                _selectedDay != null
                    ? '${_selectedDay!.month}월 ${_selectedDay!.day}일'
                    : '날짜 선택',
                style: ResponsiveHelper.smallStyle(context,
                    color: _selectedDay != null ? AppColors.infoDark : AppColors.grey500,
                    fontWeight: _selectedDay != null ? FontWeight.w600 : FontWeight.normal),
              ),
              if (_selectedDay != null) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => setState(() => _selectedDay = null),
                  child: const Icon(Icons.close, size: 13, color: AppColors.grey500),
                ),
              ],
            ]),
          ),
        ),
      ]),
    );
  }

  // ─── 변경요청 탭 ──────────────────────────────────────────
  Widget _buildChangeRequestTab() {
    if (_changeRequests.isEmpty) {
      return const AppEmptyState(
          icon: Icons.swap_horiz_outlined, title: '지급방식 변경 요청이 없습니다');
    }
    return ListView(
      padding: ResponsiveHelper.listPadding(context),
      children: _changeRequests.map((req) => _RequestCard(
        title:     '${req.workerName} · 지급방식 변경',
        subtitle:  req.changeDescription,
        detail:    '효력: ${req.effectiveFrom}부터 · 사유: ${req.requestReason ?? '-'}',
        onApprove: () => _approveChangeRequest(req),
        onReject:  () => _rejectChangeRequest(req),
      )).toList(),
    );
  }

  // ─── 중간정산 탭 ──────────────────────────────────────────
  Widget _buildSettlementTab() {
    if (_settlementRequests.isEmpty) {
      return const AppEmptyState(
          icon: Icons.account_balance_wallet_outlined, title: '중간정산 요청이 없습니다');
    }
    return ListView(
      padding: ResponsiveHelper.listPadding(context),
      children: _settlementRequests.map((req) {
        final scheduledLabel = req.scheduledTransferDate != null
            ? '이체 예정일: ${DateFormat('MM/dd').format(req.scheduledTransferDate!)}'
            : null;
        return _RequestCard(
          title:        '${req.workerName} · 중간정산 요청',
          subtitle:     '${req.periodLabel} · ${req.recordCount}건',
          detail:       '실수령: ${FormatHelper.formatWage(req.netAmount)}'
              '${scheduledLabel != null ? '  ·  $scheduledLabel' : ''}',
          onApprove:    req.isPending  ? () => _approveSettlement(req)  : null,
          onReject:     req.isPending  ? () => _rejectSettlement(req)   : null,
          onProcess:    req.isApproved ? () => _processSettlement(req)  : null,
          statusLabel:  req.statusLabel,
        );
      }).toList(),
    );
  }
}

// ─── 네비게이션 화살표 버튼 ──────────────────────────────────────
class _NavArrow extends StatelessWidget {
  final VoidCallback onTap;
  final IconData icon;
  const _NavArrow({required this.onTap, required this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Icon(icon, size: 20, color: AppColors.grey600),
      ),
    );
  }
}

// ─── 근무자별 급여 카드 ───────────────────────────────────────────
class _WorkerPayCard extends StatelessWidget {
  final String workerName;
  final String bankInfo;
  final String? businessName;
  final int netAmount;
  final int recordCount;
  final bool isTransferred;
  final bool isPartiallyTransferred; // 일부 이체 완료 (중간정산)
  final bool isPending;              // 미이체 탭 전용 — 기한 여유 항목도 빨간 바 표시
  final bool isBatchMode;
  final bool isSelected;
  final bool isOverdue;
  final bool isDueToday;
  final DateTime? dueDate;
  final String? scheduleLabel;
  final int? daysUntilDue;
  final VoidCallback? onSelect;
  final VoidCallback? onMarkTransferred;
  final VoidCallback? onCardTap;

  const _WorkerPayCard({
    required this.workerName,
    required this.bankInfo,
    this.businessName,
    required this.netAmount,
    required this.recordCount,
    required this.isTransferred,
    this.isPartiallyTransferred = false,
    this.isPending = false,
    this.isBatchMode = false,
    this.isSelected = false,
    this.isOverdue = false,
    this.isDueToday = false,
    this.dueDate,
    this.scheduleLabel,
    this.daysUntilDue,
    this.onSelect,
    this.onMarkTransferred,
    this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Color leftBarColor = isTransferred
        ? AppColors.success
        : isPartiallyTransferred
            ? AppColors.teal
            : isOverdue
                ? AppColors.error
                : isDueToday
                    ? AppColors.warning
                    : isPending
                        ? AppColors.error.withValues(alpha: 0.45) // 미이체 탭 — 기한 여유 항목도 빨간 바
                        : AppColors.grey300;

    return GestureDetector(
      onTap: isBatchMode ? onSelect : onCardTap,
      child: Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primaryColor.withValues(alpha: 0.05)
              : isOverdue && !isTransferred
                  ? AppColors.errorBg.withValues(alpha: 0.4)
                  : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.primaryColor
                : isOverdue && !isTransferred
                    ? AppColors.error.withValues(alpha: 0.3)
                    : AppColors.grey200,
            width: (isSelected || (isOverdue && !isTransferred)) ? 1.5 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6, offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 왼쪽 컬러 인디케이터 (🔴/🟢 역할)
                Container(width: 4, color: leftBarColor),

                // 카드 본문
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // 배치 체크박스
                        if (isBatchMode) ...[
                          Icon(
                            isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                            color: isSelected ? theme.primaryColor : AppColors.grey400,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                        ],

                        // 이름 + 지급일 칩 + 계좌
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              // 1행: 이름 + 지급일/이체상태 칩
                              Row(children: [
                                Flexible(
                                  child: Text(workerName,
                                      style: ResponsiveHelper.bodyStyle(context)
                                          .copyWith(fontWeight: FontWeight.w700),
                                      overflow: TextOverflow.ellipsis),
                                ),
                                const SizedBox(width: 6),
                                if (isTransferred)
                                  Flexible(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: AppColors.successBg,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                                        const Icon(Icons.check_circle, size: 10, color: AppColors.success),
                                        const SizedBox(width: 3),
                                        Text('이체완료',
                                            style: ResponsiveHelper.tinyStyle(context,
                                                color: AppColors.successDark,
                                                fontWeight: FontWeight.w600)),
                                      ]),
                                    ),
                                  )
                                else if (dueDate != null)
                                  Flexible(
                                    child: _DueDateChip(
                                      dueDate: dueDate!,
                                      isOverdue: isOverdue,
                                      isDueToday: isDueToday,
                                      scheduleLabel: scheduleLabel,
                                      daysUntilDue: daysUntilDue,
                                    ),
                                  )
                                else
                                  Flexible(
                                    child: Text('지급일 미설정',
                                        overflow: TextOverflow.ellipsis,
                                        style: ResponsiveHelper.tinyStyle(context,
                                            color: AppColors.grey400)),
                                  ),
                              ]),
                              // 2행: 사업장 · 계좌 + 건수
                              const SizedBox(height: 3),
                              Row(children: [
                                Expanded(
                                  child: Text(
                                    [
                                      if (businessName != null && businessName!.isNotEmpty) businessName!,
                                      if (bankInfo.isNotEmpty) bankInfo,
                                    ].join(' · ').isNotEmpty
                                        ? [
                                            if (businessName != null && businessName!.isNotEmpty) businessName!,
                                            if (bankInfo.isNotEmpty) bankInfo,
                                          ].join(' · ')
                                        : '계좌 정보 없음',
                                    style: ResponsiveHelper.tinyStyle(context,
                                        color: bankInfo.isNotEmpty || isTransferred
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
                                color: isTransferred ? AppColors.successDark : AppColors.grey800,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 6),
                            if (!isTransferred && !isBatchMode && onMarkTransferred != null)
                              SizedBox(
                                height: 28,
                                child: ElevatedButton(
                                  onPressed: onMarkTransferred,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    foregroundColor: Colors.white,
                                    elevation: 0,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                    textStyle: ResponsiveHelper.tinyStyle(context,
                                        fontWeight: FontWeight.w600),
                                    shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6)),
                                  ),
                                  child: const Text('이체처리'),
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
  /// APPROVED 상태 중간정산 이체 처리 버튼 — null이면 미표시
  final VoidCallback? onProcess;
  final String? statusLabel;

  const _RequestCard({
    required this.title,
    required this.subtitle,
    required this.detail,
    this.onApprove,
    this.onReject,
    this.onProcess,
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
          Row(children: [
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
                  vertical:   ResponsiveHelper.spacing(context, 2),
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
          ]),
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(subtitle,
              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700)),
          SizedBox(height: ResponsiveHelper.spacing(context, 2)),
          Text(detail,
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
          if (onApprove != null || onReject != null || onProcess != null) ...[
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
                        vertical:   ResponsiveHelper.spacing(context, 6),
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
                        vertical:   ResponsiveHelper.spacing(context, 6),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('승인'),
                  ),
                ],
                if (onProcess != null) ...[
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  ElevatedButton(
                    onPressed: onProcess,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.teal,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 14),
                        vertical:   ResponsiveHelper.spacing(context, 6),
                      ),
                      elevation: 0,
                    ),
                    child: const Text('이체 처리'),
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

// ─── 요약 헤더 ───────────────────────────────────────────────────
class _DashboardSummaryHeader extends StatelessWidget {
  final int pendingAmount;
  final int transferredAmount;
  final int pendingCount;
  final int completedCount;
  final int overdueCount;
  final bool isExporting;
  final VoidCallback? onExportCsv;

  const _DashboardSummaryHeader({
    required this.pendingAmount,
    required this.transferredAmount,
    required this.pendingCount,
    required this.completedCount,
    required this.overdueCount,
    this.isExporting = false,
    this.onExportCsv,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasPending    = pendingAmount > 0;
    final pendingColor  = hasPending ? AppColors.warningDark : AppColors.grey400;
    final pendingBg     = hasPending
        ? AppColors.warning.withValues(alpha: 0.08)
        : AppColors.grey100;
    final pendingBorder = hasPending
        ? AppColors.warning.withValues(alpha: 0.35)
        : AppColors.grey200;

    return Container(
      color: theme.primaryColor.withValues(alpha: 0.04),
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 상단 행: 연체 상태 + 엑셀 버튼
          Row(
            children: [
              if (overdueCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.errorBg,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 11, color: AppColors.errorDark),
                    const SizedBox(width: 3),
                    Text('연체 $overdueCount명',
                        style: ResponsiveHelper.tinyStyle(context,
                            color: AppColors.errorDark,
                            fontWeight: FontWeight.bold)),
                  ]),
                )
              else
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.check_circle_outline,
                      size: 11, color: AppColors.success),
                  const SizedBox(width: 3),
                  Text('연체 없음',
                      style: ResponsiveHelper.tinyStyle(
                          context, color: AppColors.success)),
                ]),
              const Spacer(),
              if (onExportCsv != null)
                SizedBox(
                  height: 26,
                  child: TextButton.icon(
                    onPressed: isExporting ? null : onExportCsv,
                    icon: isExporting
                        ? const SizedBox(
                            width: 11, height: 11,
                            child: CircularProgressIndicator(strokeWidth: 1.5))
                        : const Icon(Icons.download_outlined, size: 13),
                    label: const Text('엑셀'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.infoDark,
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      textStyle: ResponsiveHelper.tinyStyle(context,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          // ── 투 카드
          Row(
            children: [
              // 미이체 카드 (보조)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: pendingBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: pendingBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(
                          hasPending
                              ? Icons.schedule_outlined
                              : Icons.check_circle_outline,
                          size: 11,
                          color: pendingColor,
                        ),
                        const SizedBox(width: 3),
                        Text('미이체',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: pendingColor,
                                fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          FormatHelper.formatWage(pendingAmount),
                          style: ResponsiveHelper.titleStyle(context,
                                  color: pendingColor)
                              .copyWith(
                                  fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(children: [
                        Icon(Icons.person_outline,
                            size: 11, color: AppColors.grey500),
                        const SizedBox(width: 2),
                        Text('$pendingCount명',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.grey600,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 이체완료 카드 (주인공)
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.success.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.check_circle_outline,
                            size: 11, color: AppColors.successDark),
                        const SizedBox(width: 3),
                        Text('이체완료',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.successDark,
                                fontWeight: FontWeight.w600)),
                      ]),
                      const SizedBox(height: 4),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          FormatHelper.formatWage(transferredAmount),
                          style: ResponsiveHelper.titleStyle(context,
                                  color: AppColors.successDark)
                              .copyWith(
                                  fontSize: 22, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 3),
                      Row(children: [
                        const Icon(Icons.person_outline,
                            size: 11, color: AppColors.grey500),
                        const SizedBox(width: 2),
                        Text('$completedCount명',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.grey600,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── 지급일 칩 ───────────────────────────────────────────────────
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
    final shortDate = '${dueDate.month}.${dueDate.day.toString().padLeft(2, '0')}';
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

    final String chipText = scheduleLabel != null ? '$scheduleLabel · $dateText' : dateText;
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
              isOverdue ? Icons.warning_amber_rounded : Icons.schedule,
              size: 10, color: chipColor,
            ),
          ),
        Flexible(
          child: Text(chipText,
              style: ResponsiveHelper.tinyStyle(context,
                  color: chipColor,
                  fontWeight: isUrgent ? FontWeight.w700 : FontWeight.normal),
              overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }
}

// ─── 미이체 날짜 선택 캘린더 바텀시트 ────────────────────────────────
class _PendingCalendarSheet extends StatefulWidget {
  final DateTime initialDate;
  final Map<DateTime, int> countByDate;

  const _PendingCalendarSheet({
    required this.initialDate,
    required this.countByDate,
  });

  @override
  State<_PendingCalendarSheet> createState() => _PendingCalendarSheetState();
}

class _PendingCalendarSheetState extends State<_PendingCalendarSheet> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 핸들바
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // 헤더
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(children: [
              Icon(Icons.calendar_month_outlined,
                  size: 20, color: theme.primaryColor),
              const SizedBox(width: 8),
              Text('날짜 선택',
                  style: ResponsiveHelper.subtitleStyle(context,
                      fontWeight: FontWeight.bold)),
              const Spacer(),
              Text('날짜를 선택하면 이동합니다',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey400)),
            ]),
          ),
          // 선택된 날짜 표시
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: Row(children: [
              Text(
                '${_selectedDate.year}년 ${_selectedDate.month}월 ${_selectedDate.day}일',
                style: ResponsiveHelper.titleStyle(context,
                    color: theme.primaryColor)
                    .copyWith(fontSize: 22, fontWeight: FontWeight.w800),
              ),
            ]),
          ),
          // 캘린더
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CarrotStyleCalendar(
              mode: CalendarMode.single,
              selectedDate: _selectedDate,
              allowPastDates: true,
              focusedMonth: DateTime(_selectedDate.year, _selectedDate.month),
              onDateSelected: (date) => Navigator.pop(context, date),
              dayBadgeBuilder: (date) {
                final key = DateTime(date.year, date.month, date.day);
                final count = widget.countByDate[key] ?? 0;
                if (count == 0) return null;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    '$count명',
                    style: const TextStyle(
                      fontSize: 9,
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                      height: 1.1,
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─── 급여 상세 화면 (공용 — 미이체/부분이체/이체완료 모두 사용) ─────────
class _WorkerPayDetailScreen extends StatefulWidget {
  final String workerName;
  final List<AttendanceModel> records;
  final String? bankInfo;
  final bool canCancelTransfer;

  const _WorkerPayDetailScreen({
    required this.workerName,
    required this.records,
    this.bankInfo,
    this.canCancelTransfer = false,
  });

  @override
  State<_WorkerPayDetailScreen> createState() => _WorkerPayDetailScreenState();
}

class _WorkerPayDetailScreenState extends State<_WorkerPayDetailScreen> {
  bool _deductionExpanded = false;
  bool _isCancelling = false;
  final _payService = PayrollPaymentService();

  Future<void> _cancelTransfer(AttendanceModel r) async {
    final note = await DialogHelper.showTextInput(
      context,
      title: '이체 취소',
      message: '이체완료 상태를 미이체(확정)로 되돌립니다.\n실제 송금이 취소되지 않으니 별도 처리하세요.',
      hintText: '예) 잘못된 금액으로 이체, 계좌 오입력 등',
      maxLength: 200,
      maxLines: 2,
      confirmText: '취소 처리',
      cancelText: '닫기',
      confirmColor: AppColors.error,
      icon: Icons.undo_outlined,
      iconColor: AppColors.error,
      validator: (v) => v != null && v.trim().isNotEmpty,
    );
    if (note == null || note.trim().isEmpty || !mounted) return;

    setState(() => _isCancelling = true);
    try {
      await _payService.cancelTransfer(
        attendanceId: r.id,
        businessId: r.businessId,
        cancelNote: note,
      );
      if (!mounted) return;
      ToastHelper.showSuccess('이체가 취소되었습니다.');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('이체 취소 실패: ${e.toString().replaceFirst("Exception: ", "")}');
    } finally {
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  String _payTypeLabel(String? type) => switch (type) {
    'monthly'               => '월급',
    'weekly'                => '주급',
    'same_day' || 'next_day' => '일급',
    _                       => '',
  };

  // 주급 주차 + 날짜 범위 계산
  // 예: records의 workDate 중 가장 이른 날의 월요일~일요일을 기준으로
  //     해당 월의 몇 주차인지와 MM/DD ~ MM/DD 범위를 반환
  ({String weekLabel, String rangeLabel})? _weekInfo() {
    final isWeekly = widget.records.any((r) => r.wageDetail?.payScheduleType == 'weekly');
    if (!isWeekly) return null;

    final dates = widget.records.map((r) => r.workDate).toList()..sort();
    final anchor     = dates.first;
    final weekStart  = anchor.subtract(Duration(days: anchor.weekday - 1)); // 해당 주 월요일
    final weekEnd    = weekStart.add(const Duration(days: 6));              // 해당 주 일요일

    // 주차: 월요일 기준으로 해당 월의 몇 번째 주인지
    final firstMonday = DateTime(weekStart.year, weekStart.month, 1).subtract(
      Duration(days: (DateTime(weekStart.year, weekStart.month, 1).weekday - 1) % 7),
    );
    final weekNum = ((weekStart.difference(firstMonday).inDays) ~/ 7) + 1;

    final startLabel = '${weekStart.month}/${weekStart.day}';
    final endLabel   = '${weekEnd.month}/${weekEnd.day}';

    return (
      weekLabel: '${weekStart.month}월 $weekNum주차',
      rangeLabel: '$weekNum주차 · $startLabel ~ $endLabel',
    );
  }

  Widget _buildDeductionSection(BuildContext context, List<AttendanceModel> records) {
    // 전체 records의 공제 합산
    final nationalPension = records.fold(0, (a, r) => a + (r.wageDetail?.nationalPensionDeduction ?? 0));
    final healthInsurance = records.fold(0, (a, r) => a + (r.wageDetail?.healthInsuranceDeduction ?? 0));
    final ltcInsurance    = records.fold(0, (a, r) => a + (r.wageDetail?.ltcInsuranceDeduction ?? 0));
    final employment      = records.fold(0, (a, r) => a + (r.wageDetail?.employmentInsuranceDeduction ?? 0));
    final incomeTax       = records.fold(0, (a, r) => a + (r.wageDetail?.incomeTaxDeduction ?? 0));
    final retroactive     = records.fold(0, (a, r) => a + (r.wageDetail?.retroactiveDeduction ?? 0));
    final manualDeduction = records.fold(0, (a, r) => a + (r.wageDetail?.deductionAmount ?? 0));
    final totalDeduction  = nationalPension + healthInsurance + ltcInsurance +
                            employment + incomeTax + retroactive + manualDeduction;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _deductionExpanded = !_deductionExpanded),
          borderRadius: BorderRadius.circular(6),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              const Icon(Icons.remove_circle_outline, size: 13, color: AppColors.grey400),
              const SizedBox(width: 5),
              RichText(
                text: TextSpan(
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                  children: [
                    const TextSpan(text: '공제  '),
                    TextSpan(
                      text: totalDeduction > 0
                          ? FormatHelper.formatWage(totalDeduction)
                          : '없음',
                      style: TextStyle(
                        color: totalDeduction > 0 ? AppColors.grey800 : AppColors.grey400,
                        fontWeight: totalDeduction > 0 ? FontWeight.w700 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                _deductionExpanded ? Icons.expand_less : Icons.expand_more,
                size: 16,
                color: AppColors.grey400,
              ),
            ]),
          ),
        ),
        if (_deductionExpanded) ...[
          const SizedBox(height: 6),
          if (totalDeduction == 0)
            Padding(
              padding: const EdgeInsets.only(left: 18, bottom: 4),
              child: Text('공제 없음',
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400)),
            )
          else ...[
            _deductRow(context, '국민연금', nationalPension),
            _deductRow(context, '건강보험', healthInsurance),
            _deductRow(context, '장기요양', ltcInsurance),
            _deductRow(context, '고용보험', employment),
            _deductRow(context, '소득세',   incomeTax),
            if (retroactive > 0) _deductRow(context, '소급공제', retroactive),
            if (manualDeduction > 0) _deductRow(context, '추가공제', manualDeduction),
          ],
        ],
      ],
    );
  }

  Widget _deductRow(BuildContext context, String label, int amount) {
    if (amount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 3, left: 18),
      child: Row(children: [
        SizedBox(
          width: 60,
          child: Text(label,
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
        ),
        Text('- ${FormatHelper.formatWage(amount)}',
            style: ResponsiveHelper.tinyStyle(context,
                color: AppColors.error, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final records    = widget.records;
    final workerName = widget.workerName;
    final weekInfo   = _weekInfo();
    final dueDate    = records.map((r) => r.paymentDueDate).whereType<DateTime>().firstOrNull;
    final titleSuffix = weekInfo != null
        ? weekInfo.weekLabel
        : (dueDate != null ? '${dueDate.month}월' : '');

    final totalNet    = records.fold(0, (a, r) => a + (r.wageDetail?.effectiveNetWage ?? 0));
    final xferRecs    = records.where((r) => r.wageStatus == AttendanceModel.wageTransferred).toList();
    final pendRecs    = records.where((r) => r.wageStatus != AttendanceModel.wageTransferred).toList();
    final transferred = xferRecs.fold(0, (a, r) => a + (r.wageDetail?.effectiveNetWage ?? 0));
    final pending     = totalNet - transferred;
    final isPartial   = xferRecs.isNotEmpty && pendRecs.isNotEmpty;

    final totalMinutes = records.fold(0, (a, r) => a + (r.wageDetail?.workMinutes ?? 0));

    // 섹션 구분: 부분이체일 때 이체완료/잔여 그룹으로 나눔, 아니면 평탄 목록
    // 아이템 타입: String(섹션 헤더) | AttendanceModel(기록 카드)
    final List<dynamic> items;
    if (isPartial) {
      items = [
        '이체완료 ${xferRecs.length}건',
        ...xferRecs,
        '잔여 ${pendRecs.length}건',
        ...pendRecs,
      ];
    } else {
      items = [...records];
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          color: AppColors.textPrimary,
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('$workerName · $titleSuffix',
            style: ResponsiveHelper.subtitleStyle(context,
                fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Column(children: [
        // ── 요약 헤더
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 상태 배지
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: isPartial
                      ? AppColors.tealBg
                      : (xferRecs.isEmpty ? AppColors.warningBg : AppColors.successBg),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isPartial ? '부분이체' : (xferRecs.isEmpty ? '미이체' : '이체완료'),
                  style: ResponsiveHelper.smallStyle(context,
                      color: isPartial
                          ? AppColors.teal
                          : (xferRecs.isEmpty ? AppColors.warningDark : AppColors.successDark),
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              // 총액
              Text(
                FormatHelper.formatWage(totalNet),
                style: ResponsiveHelper.titleStyle(context,
                    color: pending > 0 ? AppColors.warningDark : AppColors.successDark)
                    .copyWith(fontSize: 30, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                isPartial ? '실수령 합계 (중간정산 포함)' : '실수령 합계',
                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
              ),
              // 부분이체일 때만 이체/잔여 분리 표시
              if (isPartial) ...[
                const SizedBox(height: 8),
                Row(children: [
                  const Icon(Icons.circle, size: 7, color: AppColors.success),
                  const SizedBox(width: 5),
                  Text('이체 ${FormatHelper.formatWage(transferred)}',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.successDark, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 14),
                  const Icon(Icons.circle, size: 7, color: AppColors.warning),
                  const SizedBox(width: 5),
                  Text('잔여 ${FormatHelper.formatWage(pending)}',
                      style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.warningDark, fontWeight: FontWeight.w600)),
                ]),
              ],
              const SizedBox(height: 12),
              // 통계 한 줄 (• 구분자)
              Text(
                [
                  '${records.length}일 근무',
                  '${totalMinutes ~/ 60}h',
                  if (weekInfo != null) weekInfo.rangeLabel,
                ].join('  •  '),
                style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey700),
              ),
              // 계좌 정보
              if (widget.bankInfo != null) ...[
                const SizedBox(height: 6),
                Row(children: [
                  const Icon(Icons.account_balance_outlined, size: 13, color: AppColors.grey500),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(widget.bankInfo!,
                        style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: widget.bankInfo!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('계좌번호가 복사되었습니다'),
                          duration: Duration(seconds: 1),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    child: const Icon(Icons.copy, size: 14, color: AppColors.grey500),
                  ),
                ]),
              ],
              // 공제 내역 접기/펼치기
              const SizedBox(height: 12),
              _buildDeductionSection(context, records),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.grey100),

        // ── 레코드 목록 (섹션 헤더 포함)
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final item = items[i];

              // 섹션 헤더
              if (item is String) {
                final isXferSection = item.startsWith('이체완료');
                return Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Row(children: [
                    Container(
                      width: 3, height: 14,
                      decoration: BoxDecoration(
                        color: isXferSection ? AppColors.success : AppColors.warning,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(item,
                        style: ResponsiveHelper.smallStyle(ctx,
                            color: isXferSection ? AppColors.successDark : AppColors.warningDark,
                            fontWeight: FontWeight.w700)),
                  ]),
                );
              }

              // 기록 카드
              final r      = item as AttendanceModel;
              final wd     = r.wageDetail;
              final net    = wd?.effectiveNetWage ?? 0;
              final isXfer = r.wageStatus == AttendanceModel.wageTransferred;
              final d      = r.workDate;
              final dayLabel   = '${d.month}/${d.day} (${_weekdays[(d.weekday - 1) % 7]})';
              final minutes    = wd?.workMinutes ?? 0;
              final payLabel   = _payTypeLabel(wd?.payScheduleType);
              final xferDate   = r.transferDate;

              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isXfer ? AppColors.successBg : AppColors.grey200),
                  boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 6, offset: const Offset(0, 2))],
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 날짜 + 업무유형 + 급여유형 칩
                    SizedBox(
                      width: 76,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(dayLabel,
                              style: ResponsiveHelper.bodyStyle(ctx,
                                  fontWeight: FontWeight.w600)),
                          if (r.workType.isNotEmpty)
                            Text(r.workType,
                                style: ResponsiveHelper.smallStyle(ctx,
                                    color: AppColors.grey600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          if (payLabel.isNotEmpty)
                            Container(
                              margin: const EdgeInsets.only(top: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.grey100,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(payLabel,
                                  style: ResponsiveHelper.tinyStyle(ctx,
                                      color: AppColors.grey600,
                                      fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    // 사업장 + 시간 + 실근무
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (r.businessName.isNotEmpty)
                            Text(r.businessName,
                                style: ResponsiveHelper.smallStyle(ctx,
                                    color: AppColors.grey600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis),
                          if (r.checkIn != null && r.checkOut != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('${r.checkIn} ~ ${r.checkOut}',
                                  style: ResponsiveHelper.smallStyle(ctx,
                                      color: AppColors.grey700)),
                            ),
                          if (wd != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text('실근무 ${minutes ~/ 60}h ${minutes % 60}m',
                                  style: ResponsiveHelper.smallStyle(ctx,
                                      color: AppColors.grey500)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // 금액 + 상태 배지 + 이체일
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(net > 0 ? FormatHelper.formatWage(net) : '-',
                            style: ResponsiveHelper.subtitleStyle(ctx,
                                fontWeight: FontWeight.w700,
                                color: isXfer
                                    ? AppColors.successDark
                                    : AppColors.grey800)
                                .copyWith(fontSize: 17)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: isXfer ? AppColors.successBg : AppColors.warningBg,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(isXfer ? '이체완료' : '잔여',
                              style: ResponsiveHelper.tinyStyle(ctx,
                                  color: isXfer
                                      ? AppColors.successDark
                                      : AppColors.warningDark,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (isXfer && xferDate != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            '${xferDate.month}/${xferDate.day} 이체',
                            style: ResponsiveHelper.tinyStyle(ctx,
                                color: AppColors.grey400),
                          ),
                        ],
                        if (isXfer && widget.canCancelTransfer) ...[
                          const SizedBox(height: 6),
                          GestureDetector(
                            onTap: _isCancelling ? null : () => _cancelTransfer(r),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.error.withValues(alpha: 0.5)),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text('이체 취소',
                                  style: ResponsiveHelper.tinyStyle(ctx,
                                      color: AppColors.error,
                                      fontWeight: FontWeight.w600)),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ]),
    );
  }
}
