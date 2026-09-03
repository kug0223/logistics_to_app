// lib/screens/user/user_contracts_screen.dart
//
// 사용자 계약서 관리 화면
// - 상태별 pill 필터 (전체 / 서명 필요 / 완료 / 무효)
// - 서명 필요 계약서에만 Primary CTA 표시
// - ContractSignScreen 진입
//
// ── 절대 변경 금지 ────────────────────────────────────────────────
// ContractStatus enum · Firestore status 문자열 · status 전환 조건
// callableFinalize* · callableVoidContract · 자동연장/퇴사/비활성화 처리
// completed 법적 보존 규칙 · ContractSignScreen 흐름 · PDF 로직
// pagination · tab cache · stale response 방지 · _openContract 갱신 로직
// ─────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/employment_contract_model.dart';
import '../../providers/user_provider.dart';
import '../../services/contract_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/toast_helper.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../widgets/common/loading_widget.dart';

class UserContractsScreen extends StatefulWidget {
  const UserContractsScreen({super.key});

  @override
  State<UserContractsScreen> createState() => _UserContractsScreenState();
}

class _UserContractsScreenState extends State<UserContractsScreen> {
  final _contractService = ContractService();
  final _scrollCtrl = ScrollController();

  // null = 전체. pendingEmployer 탭 없음:
  // 계약서는 사업주 서명(callableFinalizeEmployerSignature) 시 pendingWorker로 최초 저장.
  // pendingEmployer는 장기 자동연장 케이스에만 발생 — "전체" 탭에서 표시.
  static const _tabs = <ContractStatus?>[
    null,
    ContractStatus.pendingWorker, // 내 서명 필요
    ContractStatus.completed,
    ContractStatus.voided,
  ];
  static const _tabLabels = ['전체', '서명 필요', '서명 완료', '무효'];

  int _selectedTab = 0;
  ContractStatus? get _currentFilter => _tabs[_selectedTab];

  List<EmploymentContractModel> _items = [];
  bool _isLoading = true;
  bool _fetchInProgress = false;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  bool _isContractOpening = false;
  String? _lastDocId;

  // 탭별 캐시 — 동일 탭 재방문 시 CF 재호출 없이 즉시 표시
  final Map<
      int,
      ({
        List<EmploymentContractModel> items,
        String? lastDocId,
        bool hasMore
      })> _tabCache = {};

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
            _scrollCtrl.position.maxScrollExtent - 200 &&
        _hasMore &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  String? get _uid =>
      Provider.of<UserProvider>(context, listen: false).currentUser?.uid;

  Future<void> _load({bool useCache = true}) async {
    if (!mounted || _fetchInProgress) return;
    final uid = _uid;
    if (uid == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final tabIdx = _selectedTab;

    // 캐시 히트: 스피너 없이 즉시 표시
    if (useCache) {
      final cached = _tabCache[tabIdx];
      if (cached != null) {
        setState(() {
          _items = List.from(cached.items);
          _lastDocId = cached.lastDocId;
          _hasMore = cached.hasMore;
          _isLoading = false;
        });
        return;
      }
    }

    _fetchInProgress = true;
    setState(() {
      _isLoading = true;
      _items = [];
      _lastDocId = null;
      _hasMore = false;
    });
    try {
      final requestFilter = _currentFilter; // 호출 시점 필터 스냅샷
      final result = await _contractService.getByWorkerPaged(
        uid,
        statusFilter: requestFilter,
      );
      if (!mounted) return;
      // CF 호출 중 탭이 바뀐 경우: 결과는 요청 탭 캐시에만 저장
      _tabCache[tabIdx] = (
        items: List.from(result.items),
        lastDocId: result.lastDocId,
        hasMore: result.hasMore,
      );
      if (_selectedTab == tabIdx) {
        setState(() {
          _items = result.items;
          _lastDocId = result.lastDocId;
          _hasMore = result.hasMore;
        });
      }
    } catch (e) {
      debugPrint('❌ 계약 목록 로드 실패: $e');
      if (mounted) ToastHelper.showError('계약서 목록을 불러오지 못했습니다');
    } finally {
      _fetchInProgress = false;
      if (mounted) setState(() => _isLoading = false);
    }
    // 탭이 바뀐 경우 현재 탭 데이터 재로드 (_fetchInProgress 해제 후 재진입)
    if (mounted && _selectedTab != tabIdx) _load();
  }

  // pull-to-refresh: 현재 탭 캐시만 무효화
  Future<void> _refresh() {
    _tabCache.remove(_selectedTab);
    return _load(useCache: false);
  }

  Future<void> _loadMore() async {
    final uid = _uid;
    if (_isLoadingMore || !_hasMore || _lastDocId == null || uid == null) {
      return;
    }
    if (!mounted) return;
    // [F-08-1 수정] await 전에 탭 인덱스를 캡처 — _load()와 동일한 race condition 방지 패턴
    final tabIdx = _selectedTab;
    setState(() => _isLoadingMore = true);
    try {
      final result = await _contractService.getByWorkerPaged(
        uid,
        statusFilter: _currentFilter,
        startAfter: _lastDocId,
      );
      if (!mounted) return;
      // [F-08-1 수정] CF 응답 중 탭이 전환된 경우 stale 결과 폐기
      // 현재 탭 데이터에 이전 탭 결과가 append되는 오염 방지
      if (_selectedTab != tabIdx) return;
      setState(() {
        _items.addAll(result.items);
        _lastDocId = result.lastDocId;
        _hasMore = result.hasMore;
      });
      _tabCache[tabIdx] = (
        items: List.from(_items),
        lastDocId: _lastDocId,
        hasMore: _hasMore,
      );
    } catch (e) {
      debugPrint('❌ 계약 목록 추가 로드 실패: $e');
      if (mounted) ToastHelper.showError('계약서를 더 불러오지 못했습니다');
    } finally {
      if (mounted) setState(() => _isLoadingMore = false);
    }
  }

  Future<void> _openContract(EmploymentContractModel c) async {
    if (_isContractOpening || !mounted) return;
    setState(() => _isContractOpening = true);
    // rootNavigator: true — BottomNavigationBar 위에 전체화면 push.
    // 근로계약서는 법적 문서 열람 화면이므로 앱 내비게이션을 잠시 숨긴다.
    final nav = Navigator.of(context, rootNavigator: true);
    try {
      await nav.push(MaterialPageRoute(
        builder: (_) => ContractSignScreen(contract: c, role: 'worker'),
      ));
      if (!mounted) return;
      // 단건 갱신: getById 완료 전까지 _isContractOpening=true 유지
      // (finally가 nav.push 직후 실행되면 getById 동안 중복 push 가능)
      final updated = await _contractService.getById(c.id);
      if (!mounted) return;
      setState(() {
        final idx = _items.indexWhere((item) => item.id == c.id);
        if (idx < 0) return;
        if (updated == null) {
          _items.removeAt(idx);
        } else if (_currentFilter != null &&
            updated.status != _currentFilter) {
          _items.removeAt(idx);
        } else {
          _items[idx] = updated;
        }
      });
      // 단건 변경 → 다른 탭은 stale → 전체 클리어 후 현재 탭만 캐시 복원
      final currentIdx = _selectedTab;
      _tabCache.clear();
      _tabCache[currentIdx] = (
        items: List.from(_items),
        lastDocId: _lastDocId,
        hasMore: _hasMore,
      );
    } finally {
      if (mounted) setState(() => _isContractOpening = false);
    }
  }

  // ── 탭 전환 ────────────────────────────────────────────────────

  void _onTabChange(int index) {
    if (_selectedTab == index) return;
    setState(() => _selectedTab = index);
    _load();
  }

  // 숫자 없이 레이블만 표시 — 계약서 화면은 건수보다 상태가 중요
  String _pillLabel(int tabIdx) => _tabLabels[tabIdx];

  // ── Build ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          '내 계약서',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.borderLight),
        ),
      ),
      body: Column(
        children: [
          // ── Pill 필터 ─────────────────────────────────────────
          _buildPillFilter(),
          Container(height: 1, color: AppColors.borderLight),
          // ── 본문 ──────────────────────────────────────────────
          Expanded(
            child: _isLoading
                ? const LoadingWidget(message: '계약서 목록을 불러오는 중...')
                : RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      controller: _scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
                      itemCount: _items.isEmpty
                          ? 1
                          : _items.length + (_isLoadingMore ? 1 : 0),
                      itemBuilder: (ctx, i) {
                        if (_items.isEmpty) {
                          return _buildEmptyContent(context);
                        }
                        if (i == _items.length) return const LoadingWidget();
                        return RepaintBoundary(
                          child: _ContractCard(
                            contract: _items[i],
                            onTap: () => _openContract(_items[i]),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ── Pill 필터 ────────────────────────────────────────────────────

  Widget _buildPillFilter() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < _tabs.length; i++) ...[
              _PillChip(
                label: _pillLabel(i),
                selected: _selectedTab == i,
                onTap: () => _onTabChange(i),
              ),
              if (i < _tabs.length - 1) const SizedBox(width: 8),
            ],
          ],
        ),
      ),
    );
  }

  // ── Empty State ──────────────────────────────────────────────────

  Widget _buildEmptyContent(BuildContext context) {
    final (icon, title, subtitle) = switch (_currentFilter) {
      null => (
          Icons.description_outlined,
          '등록된 계약서가 없어요',
          '확정된 공고에서 계약서를 받을 수 있어요',
        ),
      ContractStatus.pendingWorker => (
          Icons.draw_outlined,
          '서명이 필요한 계약서가 없어요',
          '모든 계약서에 서명이 완료됐어요',
        ),
      ContractStatus.completed => (
          Icons.task_alt_outlined,
          '서명 완료된 계약서가 없어요',
          '양측 서명이 완료되면 여기에 표시돼요',
        ),
      ContractStatus.voided => (
          Icons.block_outlined,
          '무효 처리된 계약서가 없어요',
          '',
        ),
      _ => (
          Icons.description_outlined,
          '계약서가 없어요',
          '',
        ),
    };

    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.5,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: AppColors.grey300),
          const SizedBox(height: 14),
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textHint,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ],
      ),
    );
  }
}

// ── Pill 필터 칩 ─────────────────────────────────────────────────

class _PillChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _PillChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.infoDark : AppColors.background,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
            letterSpacing: -0.2,
          ),
        ),
      ),
    );
  }
}

// ── 계약서 카드 ──────────────────────────────────────────────────
//
// 시각 우선순위 3단계:
//   1. pendingWorker  — 강조 테두리 + 행동 안내 텍스트 + 셰브론 (서명 필요)
//   2. completed / pendingEmployer — 조용한 정보 카드 (서명 완료 또는 준비 중)
//   3. voided         — 배경/텍스트 모두 흐리게 처리 (무효)
//
// 레이아웃: 사업장 + 상태배지 → 업무명 → 날짜·시간 → 급여 → [행동 안내(pendingWorker)]

class _ContractCard extends StatelessWidget {
  final EmploymentContractModel contract;
  final VoidCallback onTap;
  const _ContractCard({required this.contract, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final status = contract.status;
    final needSign = status == ContractStatus.pendingWorker;
    final isVoided = status == ContractStatus.voided;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        // voided: 배경을 살짝 흐리게 — 비활성 시각 신호
        color: isVoided ? AppColors.background : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          // needSign: 파란 강조 테두리 — 첫눈에 행동이 필요함을 전달
          color: needSign
              ? AppColors.infoDark.withValues(alpha: 0.28)
              : AppColors.borderLight,
          width: needSign ? 1.5 : 1.0,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            // needSign 카드는 행동 안내 행이 추가되므로 위아래 패딩 통일
            // 나머지는 compact (vertical: 12)
            padding: EdgeInsets.fromLTRB(16, 13, 16, needSign ? 13 : 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── 사업장명 + 상태 뱃지 ──────────────────────────
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        contract.snapshot.businessName,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: isVoided
                              ? AppColors.textHint
                              : AppColors.textPrimary,
                          letterSpacing: -0.4,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(status),
                  ],
                ),
                const SizedBox(height: 2),

                // ── 업무명 ──────────────────────────────────────
                Text(
                  contract.snapshot.workType,
                  style: TextStyle(
                    fontSize: 13,
                    color: isVoided
                        ? AppColors.textHint
                        : AppColors.textSecondary,
                    letterSpacing: -0.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                // needSign: 업무명과 날짜 사이에 더 큰 호흡 — 시각적 강조
                SizedBox(height: needSign ? 10 : 7),

                // ── 날짜 · 시간 ──────────────────────────────────
                Text(
                  _dateTimeLabel(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isVoided
                        ? AppColors.textHint
                        : AppColors.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 3),

                // ── 급여 · 급여유형 (장기계약 표기 포함) ─────────────
                Text(
                  _wageLabel(),
                  style: TextStyle(
                    fontSize: 13,
                    color: isVoided
                        ? AppColors.textHint
                        : AppColors.textSecondary,
                  ),
                ),

                // ── pendingWorker 전용: 행동 안내 텍스트 + 셰브론 ────
                // 버튼 대신 텍스트+아이콘으로 카드 높이를 줄이고
                // 카드 전체가 탭 영역임을 InkWell ripple로 전달
                if (needSign) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1, thickness: 1, color: AppColors.borderLight),
                  const SizedBox(height: 9),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '계약서를 확인하고 서명해주세요',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.infoDark,
                            letterSpacing: -0.2,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: AppColors.infoDark,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 날짜 + 시간 합성 ──────────────────────────────────────────────

  String _dateTimeLabel() {
    final date = _dateLabel();
    final time = _timeLabel();
    if (time != null) return '$date · $time';
    return date;
  }

  // ── 날짜 ─────────────────────────────────────────────────────────

  String _dateLabel() {
    if (contract.isLongTerm) {
      // 장기계약: 슬롯이 있으면 첫~마지막 날짜 범위, 없으면 생성일
      if (contract.slots.isNotEmpty) {
        final sorted = [...contract.slots]
          ..sort((a, b) => a.workDate.compareTo(b.workDate));
        final first = _shortDateStr(sorted.first.workDate);
        final last = _shortDateStr(sorted.last.workDate);
        return '$first ~ $last';
      }
      return _koreanDateTime(contract.createdAt);
    }
    // 단기계약
    if (contract.slots.isNotEmpty) {
      // [FIX-LOW] 슬롯은 확정 순서로 저장 — 역순 방지를 위해 날짜순 정렬
      final sorted = [...contract.slots]
        ..sort((a, b) => a.workDate.compareTo(b.workDate));
      final first = sorted.first.workDate;
      final last = sorted.last.workDate;
      if (first == last) return _koreanDateStr(first); // 단일 날짜: 요일 포함
      return '${_shortDateStr(first)} ~ ${_shortDateStr(last)}'; // 범위: 간결하게
    }
    return _koreanDateTime(contract.createdAt);
  }

  // ── 시간 (단기 단일 슬롯만, 다일 범위·장기는 null) ──────────────────

  String? _timeLabel() {
    if (contract.isLongTerm) return null;
    if (contract.slots.isEmpty) return null;
    final sorted = [...contract.slots]
      ..sort((a, b) => a.workDate.compareTo(b.workDate));
    final slot = sorted.first;
    final s = slot.startTime;
    final e = slot.endTime;
    if (s.isEmpty || e.isEmpty) return null;
    return '$s~$e';
  }

  // ── 급여 표시 ────────────────────────────────────────────────────

  String _wageLabel() {
    final wage =
        '${FormatHelper.formatNumber(contract.snapshot.wage)}원 · ${_wageTypeLabel()}';
    // 장기계약은 급여 줄에 "장기 계약" 표기, 단기계약은 생략
    return contract.isLongTerm ? '$wage · 장기 계약' : wage;
  }

  // ── 포맷 헬퍼 ────────────────────────────────────────────────────

  /// 'yyyy-MM-dd' → 'M월 D일' (요일 생략 — 날짜 범위 전용)
  String _shortDateStr(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    final m = int.tryParse(parts[1]) ?? 0;
    final d = int.tryParse(parts[2]) ?? 0;
    return '$m월 $d일'; // Dart는 한글 앞에서 식별자를 정확히 종료
  }

  /// 'yyyy-MM-dd' → 'M월 D일(요일)'
  String _koreanDateStr(String iso) {
    final parts = iso.split('-');
    if (parts.length != 3) return iso;
    final m = int.tryParse(parts[1]) ?? 0;
    final d = int.tryParse(parts[2]) ?? 0;
    final y = int.tryParse(parts[0]) ?? 2024;
    return _koreanDateTime(DateTime(y, m, d));
  }

  /// DateTime → 'M월 D일(요일)'
  String _koreanDateTime(DateTime dt) {
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    return '${dt.month}월 ${dt.day}일(${weekdays[dt.weekday - 1]})';
  }

  String _wageTypeLabel() {
    return switch (contract.snapshot.wageType) {
      'hourly'  => '시급',
      'daily'   => '일급',
      'monthly' => '월급',
      _         => contract.snapshot.wageType,
    };
  }
}

// ── 상태 뱃지 ────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final ContractStatus status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (status) {
      ContractStatus.pendingEmployer => (
          '계약서 준비 중',
          AppColors.warningBg,
          AppColors.warningDark,
        ),
      ContractStatus.pendingWorker => (
          '서명 필요',
          AppColors.infoBg,
          AppColors.infoDark,
        ),
      ContractStatus.completed => (
          '서명 완료',
          AppColors.successBg,
          AppColors.successDark,
        ),
      ContractStatus.voided => (
          '무효',
          AppColors.grey100,
          AppColors.grey500,
        ),
    };

    if (label.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}
