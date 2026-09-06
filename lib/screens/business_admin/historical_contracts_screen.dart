import 'package:flutter/material.dart';

import '../../models/core/historical_contract_summary.dart';
import '../../services/historical_contract_service.dart';
import 'historical_contract_detail_screen.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';

/// 보관된 계약서 목록 화면.
///
/// 현재 사업장과 무관하게 로그인한 BUSINESS_ADMIN이 과거 소유했던
/// 사업장의 보존 계약서를 열람한다. P3 callable 기반 read-only 조회.
///
/// - 검색/필터 없음 (V1)
/// - 무한 스크롤 (pageSize: 20)
/// - 카드 탭 → HistoricalContractDetailScreen
class HistoricalContractsScreen extends StatefulWidget {
  const HistoricalContractsScreen({super.key});

  @override
  State<HistoricalContractsScreen> createState() =>
      _HistoricalContractsScreenState();
}

class _HistoricalContractsScreenState extends State<HistoricalContractsScreen> {
  final _service = HistoricalContractService();
  final _scrollController = ScrollController();

  List<HistoricalContractSummary> _contracts = [];
  bool _isInitialLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = false;
  String? _lastDocId;

  /// 초기 로드 실패 시 저장. null이면 성공(또는 미실행).
  Object? _initialError;

  /// 추가 페이지 로드 실패 시 저장. null이면 없음.
  Object? _loadMoreError;

  // ─── 생명주기 ──────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitial();
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  // ─── 스크롤 트리거 ─────────────────────────────────────────

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  // ─── 초기 로드 ────────────────────────────────────────────

  Future<void> _loadInitial() async {
    if (!mounted) return;
    setState(() {
      _isInitialLoading = true;
      _initialError = null;
      _loadMoreError = null;
    });
    try {
      final result = await _service.getHistoricalContracts(pageSize: 20);
      if (!mounted) return;
      setState(() {
        _contracts = result.contracts;
        _lastDocId = result.lastDocId;
        _hasMore = result.hasMore;
        _isInitialLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _initialError = e;
        _isInitialLoading = false;
      });
    }
  }

  // ─── 새로고침 ─────────────────────────────────────────────

  Future<void> _refresh() async {
    if (!mounted) return;
    setState(() {
      _initialError = null;
      _loadMoreError = null;
      _contracts = [];
      _lastDocId = null;
      _hasMore = false;
    });
    try {
      final result = await _service.getHistoricalContracts(pageSize: 20);
      if (!mounted) return;
      setState(() {
        _contracts = result.contracts;
        _lastDocId = result.lastDocId;
        _hasMore = result.hasMore;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _initialError = e);
    }
  }

  // ─── 추가 페이지 로드 ─────────────────────────────────────

  Future<void> _loadMore() async {
    if (_isInitialLoading) return;
    if (_isLoadingMore) return;
    if (!_hasMore) return;
    if (_lastDocId == null) return;

    setState(() {
      _isLoadingMore = true;
      _loadMoreError = null;
    });
    try {
      final result = await _service.getHistoricalContracts(
        pageSize: 20,
        lastDocId: _lastDocId,
      );
      if (!mounted) return;
      setState(() {
        _contracts = [..._contracts, ...result.contracts];
        _lastDocId = result.lastDocId;
        _hasMore = result.hasMore;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadMoreError = e;
        _isLoadingMore = false;
      });
    }
  }

  // ─── 빌드 ─────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: '보관된 계약서',
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    // 초기 로딩
    if (_isInitialLoading) {
      return const LoadingWidget(message: '보관된 계약서를 불러오는 중...');
    }

    // 초기 오류 — empty state와 명확히 분리
    if (_initialError != null) {
      return _buildInitialError(context);
    }

    // 정상 목록 또는 성공 빈 상태 — RefreshIndicator 안에서 처리.
    // AlwaysScrollableScrollPhysics로 빈 상태에서도 pull-to-refresh 활성화.
    return RefreshIndicator(
      onRefresh: _refresh,
      child: _contracts.isEmpty
          ? CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: const AppEmptyState(
                    icon: Icons.archive_outlined,
                    title: '보관된 계약서가 없습니다',
                    subtitle: '보존된 계약 기록이 생기면 이곳에 표시됩니다.',
                  ),
                ),
              ],
            )
          : ListView.builder(
              controller: _scrollController,
              padding: ResponsiveHelper.listPadding(context),
              itemCount: _contracts.length + 1, // +1 for footer
              itemBuilder: (ctx, i) {
                if (i < _contracts.length) {
                  return _HistoricalContractCard(summary: _contracts[i]);
                }
                // 푸터
                return _LoadMoreFooter(
                  isLoadingMore: _isLoadingMore,
                  hasError: _loadMoreError != null,
                  onRetry: _loadMore,
                );
              },
            ),
    );
  }

  Widget _buildInitialError(BuildContext context) {
    return AppEmptyState(
      icon: Icons.error_outline,
      title: '보관된 계약서를 불러오지 못했습니다.',
      subtitle: '잠시 후 다시 시도해 주세요.',
      action: OutlinedButton(
        onPressed: _loadInitial,
        child: const Text('다시 시도'),
      ),
    );
  }
}

// ─── 계약서 카드 ───────────────────────────────────────────────────

class _HistoricalContractCard extends StatelessWidget {
  final HistoricalContractSummary summary;

  const _HistoricalContractCard({required this.summary});

  // 이름 fallback
  String get _workerDisplayName {
    final n = summary.workerName;
    if (n == null || n.trim().isEmpty) return '근로자 정보 없음';
    return n;
  }

  String get _businessDisplayName {
    final n = summary.businessName;
    if (n == null || n.trim().isEmpty) return '사업장 정보 없음';
    return n;
  }

  // status-aware 날짜 + 레이블
  ({String label, DateTime? date}) _resolveDate() {
    switch (summary.status) {
      case 'completed':
        return (
          label: '완료일',
          date: summary.workerSignedAt ??
              summary.employerSignedAt ??
              summary.createdAt,
        );
      case 'voided':
        return (
          label: '무효화일',
          date: summary.contractVoidedAt ?? summary.createdAt,
        );
      default:
        return (label: '등록일', date: summary.createdAt);
    }
  }

  // 상태 배지 색상
  ({Color bg, Color fg}) _statusColors() {
    switch (summary.status) {
      case 'completed':
        return (bg: AppColors.successBg, fg: AppColors.successDark);
      case 'pending_employer':
      case 'pending_worker':
        return (bg: AppColors.warningBg, fg: AppColors.warningDark);
      case 'voided':
        return (bg: AppColors.grey100, fg: AppColors.grey600);
      default:
        return (bg: AppColors.grey100, fg: AppColors.grey600);
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateInfo = _resolveDate();
    final colors = _statusColors();
    final formattedDate = dateInfo.date != null
        ? FormatHelper.formatDateDot(dateInfo.date!)
        : null;

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (_) => HistoricalContractDetailScreen(
              contractId: summary.contractId,
            ),
          )),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 14),
              vertical: ResponsiveHelper.spacing(context, 12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더: 근로자명 + 상태 배지
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        _workerDisplayName,
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    _ArchiveStatusBadge(
                      label: summary.displayStatus,
                      bg: colors.bg,
                      fg: colors.fg,
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Icon(
                      Icons.chevron_right,
                      size: ResponsiveHelper.iconSize(context, 16),
                      color: AppColors.grey400,
                    ),
                  ],
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 4)),

                // 사업장명
                Text(
                  _businessDisplayName,
                  style: ResponsiveHelper.captionStyle(context)
                      .copyWith(color: AppColors.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                const Divider(height: 1, color: AppColors.grey100),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                // 날짜 + PDF 표시
                Row(
                  children: [
                    if (formattedDate != null) ...[
                      Icon(
                        Icons.calendar_today_outlined,
                        size: ResponsiveHelper.iconSize(context, 13),
                        color: AppColors.textSecondary,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                      Expanded(
                        child: Text(
                          '${dateInfo.label}  $formattedDate',
                          style: ResponsiveHelper.captionStyle(context)
                              .copyWith(color: AppColors.textSecondary),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ] else
                      const Expanded(child: SizedBox.shrink()),

                    // PDF 표시 — 비활성 아이콘만 (P4.2 액션 없음)
                    if (summary.pdfAvailable) ...[
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Icon(
                        Icons.picture_as_pdf_outlined,
                        size: ResponsiveHelper.iconSize(context, 15),
                        color: AppColors.textSecondary,
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                      Text(
                        'PDF',
                        style: ResponsiveHelper.tinyStyle(context)
                            .copyWith(color: AppColors.textSecondary),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ), // Padding
        ), // InkWell
      ), // Material
    );
  }
}

// ─── 상태 배지 ─────────────────────────────────────────────────────

class _ArchiveStatusBadge extends StatelessWidget {
  final String label;
  final Color bg;
  final Color fg;

  const _ArchiveStatusBadge({
    required this.label,
    required this.bg,
    required this.fg,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 3),
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.tinyStyle(context).copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ─── 로드 더 푸터 ──────────────────────────────────────────────────

class _LoadMoreFooter extends StatelessWidget {
  final bool isLoadingMore;
  final bool hasError;
  final VoidCallback onRetry;

  const _LoadMoreFooter({
    required this.isLoadingMore,
    required this.hasError,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoadingMore) {
      return Padding(
        padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 16),
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (hasError) {
      return Padding(
        padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 12),
          horizontal: ResponsiveHelper.spacing(context, 16),
        ),
        child: Column(
          children: [
            Text(
              '추가 계약서를 불러오지 못했습니다.',
              style: ResponsiveHelper.captionStyle(context)
                  .copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            TextButton(
              onPressed: onRetry,
              child: const Text('다시 시도'),
            ),
          ],
        ),
      );
    }
    // 페이지 끝 / 상태 없음 — 여백만
    return SizedBox(height: ResponsiveHelper.spacing(context, 16));
  }
}
