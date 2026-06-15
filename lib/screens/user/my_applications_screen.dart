import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/core/application_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../models/core/to_model.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../screens/user/user_contracts_screen.dart';
import '../../screens/common/job_posting_screen.dart';
import '../../services/contract_service.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/work_type_icon.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_filter_chip.dart';

/// 내 지원 내역 화면 (리팩토링 버전)
class MyApplicationsScreen extends StatefulWidget {
  const MyApplicationsScreen({super.key});

  @override
  State<MyApplicationsScreen> createState() => _MyApplicationsScreenState();
}

class _MyApplicationsScreenState extends State<MyApplicationsScreen> {
  final FirestoreService _firestoreService = FirestoreService();
  final ContractService _contractService = ContractService();
  final ScrollController _scrollController = ScrollController();

  List<_ApplicationWithTO> _applications = [];
  Map<String, EmploymentContractModel> _contractMap = {};

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDoc;

  String _selectedFilter = 'ALL';

  static const int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadApplications();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore &&
        _hasMore) {
      _loadMore();
    }
  }

  Future<void> _loadApplications() async {
    setState(() {
      _isLoading = true;
      _applications = [];
      _lastDoc = null;
      _hasMore = true;
    });

    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) {
      ToastHelper.showError('로그인이 필요합니다.');
      setState(() => _isLoading = false);
      return;
    }

    try {
      // 만료된 PENDING 자동 처리
      await _firestoreService.autoExpirePendingApplications(uid);

      final page = await _firestoreService.getMyApplicationsPaged(
        uid: uid, pageSize: _pageSize,
      );
      final items = page['items'] as List<ApplicationModel>;
      final appWithTOs = await _attachTOInfo(items);

      // 계약서 로드
      final contractMap = await _loadContracts(uid, appWithTOs);

      if (mounted) {
        setState(() {
          _applications = appWithTOs;
          _contractMap = contractMap;
          _lastDoc = page['lastDoc'] as DocumentSnapshot?;
          _hasMore = page['hasMore'] as bool;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ 지원 내역 로드 실패: $e');
      if (mounted) {
        ToastHelper.showError('지원 내역을 불러오는데 실패했습니다.');
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    if (!mounted) return;
    final uid = Provider.of<UserProvider>(context, listen: false).currentUser?.uid;
    if (uid == null) return;

    setState(() => _isLoadingMore = true);
    try {
      final page = await _firestoreService.getMyApplicationsPaged(
        uid: uid, pageSize: _pageSize, startAfter: _lastDoc,
      );
      final items = page['items'] as List<ApplicationModel>;
      final appWithTOs = await _attachTOInfo(items);
      // 신규 확정 지원서에 대한 계약서만 추가 로드
      final newContracts = await _loadContracts(uid, appWithTOs);

      if (mounted) {
        setState(() {
          _applications = [..._applications, ...appWithTOs];
          _contractMap = {..._contractMap, ...newContracts};
          _lastDoc = page['lastDoc'] as DocumentSnapshot?;
          _hasMore = page['hasMore'] as bool;
          _isLoadingMore = false;
        });
        if (_filteredApplications.isEmpty && _hasMore && !_isLoadingMore) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _filteredApplications.isEmpty && _hasMore && !_isLoadingMore) {
              _loadMore();
            }
          });
        }
      }
    } catch (e) {
      debugPrint('❌ 추가 로드 실패: $e');
      if (mounted) {
        setState(() => _isLoadingMore = false);
        ToastHelper.showError('추가 데이터를 불러오지 못했습니다');
      }
    }
  }

  /// 지원서 목록에 TO 정보 결합
  /// TO가 삭제됐더라도 지원서는 표시 (to=null로 폴백)
  Future<List<_ApplicationWithTO>> _attachTOInfo(List<ApplicationModel> apps) async {
    final toIds = apps.map((a) => a.toId).whereType<String>().toSet().toList();
    if (toIds.isEmpty) return apps.map((a) => _ApplicationWithTO(application: a, to: null)).toList();
    final toList = await Future.wait(toIds.map((id) => _firestoreService.getTO(id)));
    final toMap = {for (final to in toList.whereType<TOModel>()) to.id: to};
    return apps
        .map((a) => _ApplicationWithTO(
              application: a,
              to: a.toId != null ? toMap[a.toId!] : null, // TO 삭제 시 null로 폴백
            ))
        .toList();
  }

  /// 확정/계약 대기 지원서의 계약서 로드
  Future<Map<String, EmploymentContractModel>> _loadContracts(
    String uid,
    List<_ApplicationWithTO> items,
  ) async {
    final hasConfirmed = items.any((a) =>
        a.application.status == AppStatus.confirmed ||
        a.application.status == AppStatus.contractPending);
    if (!hasConfirmed) return {};
    final contracts = await _contractService.getByWorker(uid);
    return {for (final c in contracts) c.applicationId: c};
  }

  List<_ApplicationWithTO> get _filteredApplications {
    if (_selectedFilter == 'ALL') return _applications;
    return _applications.where((item) {
      final status = item.application.status;
      if (_selectedFilter == AppStatus.canceled) {
        return AppStatus.inactiveStates.contains(status) && status != AppStatus.rejected;
      }
      if (_selectedFilter == AppStatus.confirmed) {
        return AppStatus.confirmedStatuses.contains(status);
      }
      return status == _selectedFilter;
    }).toList();
  }

  Future<void> _cancelApplication(String applicationId) async {
    final userProvider = Provider.of<UserProvider>(context, listen: false);
    final uid = userProvider.currentUser?.uid;

    if (uid == null) {
      ToastHelper.showError('로그인이 필요합니다.');
      return;
    }

    final confirmed = await DialogHelper.showCancelConfirm(
      context,
      title: '지원 취소',
      message: '정말 지원을 취소하시겠습니까?',
    );

    if (!confirmed) return;

    final success = await _firestoreService.cancelApplication(applicationId, uid);
    if (!mounted) return;
    if (success) {
      ToastHelper.showSuccess('지원이 취소되었습니다.');
      _loadApplications();
    } else {
      ToastHelper.showError('취소에 실패했습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '내 지원 내역',
      onRefresh: _loadApplications,
      body: Column(
        children: [
          _buildFilterSection(),
          Expanded(
            child: _isLoading
                ? const LoadingWidget(message: '지원 내역을 불러오는 중...')
                : _filteredApplications.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        onRefresh: _loadApplications,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: ResponsiveHelper.listPadding(context),
                          // +1 for bottom loading indicator
                          itemCount: _filteredApplications.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _filteredApplications.length) {
                              return _isLoadingMore
                                  ? const LoadingWidget()
                                  : const SizedBox.shrink();
                            }
                            return _buildApplicationCard(_filteredApplications[index]);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 필터 섹션
  // ═══════════════════════════════════════════════════════════

  Widget _buildFilterSection() {
    return Container(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.spacing(context, 10),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: AppColors.grey200, width: 1),
        ),
      ),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: {PointerDeviceKind.touch, PointerDeviceKind.mouse},
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 16),
          ),
          child: Row(
            children: [
              _buildFilterChip('전체', 'ALL', Icons.list_alt, AppColors.info),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('대기중', AppStatus.pending, Icons.schedule, AppColors.warning),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('확정', AppStatus.confirmed, Icons.check_circle, AppColors.success),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('거절', AppStatus.rejected, Icons.cancel, AppColors.error),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              _buildFilterChip('취소', AppStatus.canceled, Icons.remove_circle_outline, AppColors.grey500),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value, IconData icon, Color color) {
    return AppFilterChip(
      label: label,
      isSelected: _selectedFilter == value,
      onTap: () {
        setState(() => _selectedFilter = value);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _filteredApplications.isEmpty && _hasMore && !_isLoadingMore) {
            _loadMore();
          }
        });
      },
      color: color,
      leadingIcon: icon,
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 빈 상태
  // ═══════════════════════════════════════════════════════════

  Widget _buildEmptyState() {
    return AppEmptyState(
      icon: Icons.assignment_outlined,
      title: _selectedFilter == 'ALL' ? '지원 내역이 없습니다' : '해당 상태의 지원이 없습니다',
      subtitle: 'TO에 지원해보세요!',
    );
  }

  // ═══════════════════════════════════════════════════════════
  // 지원서 카드 (간소화된 디자인)
  // ═══════════════════════════════════════════════════════════

  Widget _buildApplicationCard(_ApplicationWithTO item) {
    final app = item.application;
    final to = item.to;
    final statusInfo = _getStatusInfo(app.status);

    // TO가 삭제된 경우 간소화 카드 표시
    if (to == null) {
      return Container(
        margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
        decoration: BoxDecoration(
          color: AppColors.grey50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.grey200),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 14),
          vertical: ResponsiveHelper.spacing(context, 10),
        ),
        child: Row(children: [
          Icon(Icons.info_outline, color: AppColors.grey400,
              size: ResponsiveHelper.iconSize(context, 18)),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('삭제된 공고',
                  style: ResponsiveHelper.bodyStyle(context,
                      color: AppColors.grey500)),
              Text('${app.businessName} · ${statusInfo.label}',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.grey400)),
            ]),
          ),
        ]),
      );
    }

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: statusInfo.color.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.grey300.withValues(alpha: 0.4),
            blurRadius: 3,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => JobPostingScreen(
                to: to,
                workDetails: to.workDetails,
              ),
            ),
          ),
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 14),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1줄: 사업장명 + 상태 배지
                _buildCardHeader(app, to, statusInfo),

                SizedBox(height: ResponsiveHelper.spacing(context, 4)),

                // 2줄: TO 제목
                Text(
                  to.title,
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 6)),

                // 3줄: 근무일 · 근무시간
                _buildDateTimeRow(app, to),

                SizedBox(height: ResponsiveHelper.spacing(context, 4)),

                // 4줄: 업무유형 · 급여
                _buildWorkWageRow(app),

                // 지원일
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  '지원일: ${DateFormat('yyyy.MM.dd HH:mm').format(app.appliedAt)}',
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
                ),
                
                // 자동 취소인 경우 충돌 정보
                if (app.status == AppStatus.autoCanceled && app.conflictingBusiness != null)
                  _buildAutoCanceledInfo(app),

                // 대기 중인 경우 취소 버튼
                if (app.status == AppStatus.pending)
                  _buildCancelButton(app),

                // 확정/계약대기인 경우 계약서 섹션
                if (app.status == AppStatus.confirmed ||
                    app.status == AppStatus.contractPending)
                  _buildContractSection(app),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCardHeader(ApplicationModel app, TOModel to, _StatusInfo statusInfo) {
    return Row(
      children: [
        Icon(
          Icons.business,
          size: ResponsiveHelper.iconSize(context, 16),
          color: AppColors.grey600,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Expanded(
          child: Text(
            to.businessName,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        _buildStatusBadge(statusInfo),
      ],
    );
  }

  Widget _buildDateTimeRow(ApplicationModel app, TOModel to) {
    final timeDisplay = (app.startTime.isNotEmpty && app.endTime.isNotEmpty)
        ? '${app.startTime} ~ ${app.endTime}'
        : '--:-- ~ --:--';

    // 장기 근무: 희망 시작일 또는 TO 근무 기간 표시
    final String dateDisplay;
    if (app.isLongTermApplication) {
      final start = app.desiredStartDate ?? to.startDate ?? app.workDate;
      final end = to.endDate;
      dateDisplay = end != null
          ? '${FormatHelper.formatDateCompact(start)} ~ ${FormatHelper.formatDateCompact(end)}'
          : FormatHelper.formatDateLong(start);
    } else {
      dateDisplay = FormatHelper.formatDateLong(app.workDate);
    }

    return Row(
      children: [
        Icon(
          app.isLongTermApplication ? Icons.date_range : Icons.calendar_today,
          size: ResponsiveHelper.iconSize(context, 14),
          color: AppColors.grey500,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
        Flexible(
          child: Text(
            dateDisplay,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!app.isLongTermApplication) ...[
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Icon(
            Icons.access_time,
            size: ResponsiveHelper.iconSize(context, 14),
            color: AppColors.grey500,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            timeDisplay,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
          ),
        ],
      ],
    );
  }

  Widget _buildWorkWageRow(ApplicationModel app) {
    return Row(
      children: [
        // 업무유형 아이콘
        if (app.workTypeIcon != null)
          WorkTypeIcon.buildWithBackground(
            iconString: app.workTypeIcon!,
            iconColor: app.workTypeColor,
            backgroundColor: app.workTypeBackgroundColor,
            size: ResponsiveHelper.iconSize(context, 14),
            containerSize: ResponsiveHelper.spacing(context, 24),
          )
        else
          Icon(
            Icons.work_outline,
            size: ResponsiveHelper.iconSize(context, 14),
            color: AppColors.grey500,
          ),
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Flexible(
          child: Text(
            app.selectedWorkType,
            overflow: TextOverflow.ellipsis,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700),
          ),
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
        // 급여
        Flexible(
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 8),
              vertical: ResponsiveHelper.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              app.formattedWage,
              overflow: TextOverflow.ellipsis,
              style: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.successDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusBadge(_StatusInfo statusInfo) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 10),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: statusInfo.bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        statusInfo.label,
        style: ResponsiveHelper.tinyStyle(
          context,
          color: statusInfo.color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 자동 취소 충돌 정보 (간소화)
  Widget _buildAutoCanceledInfo(ApplicationModel app) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
      padding: ResponsiveHelper.listPadding(context),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warningLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.info_outline,
                size: ResponsiveHelper.iconSize(context, 16),
                color: AppColors.warningDark,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
              Text(
                '시간 충돌로 자동 취소됨',
                style: ResponsiveHelper.smallStyle(
                  context,
                  color: AppColors.warningDark,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          // 충돌 공고 정보 (한 줄로 간소화)
          Row(
            children: [
              Icon(
                Icons.business,
                size: ResponsiveHelper.iconSize(context, 12),
                color: AppColors.grey600,
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
              Expanded(
                child: Text(
                  [app.conflictingBusiness, app.conflictingTime]
                      .where((s) => s != null && s.isNotEmpty)
                      .join(' · '),
                  style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 6),
                  vertical: ResponsiveHelper.spacing(context, 2),
                ),
                decoration: BoxDecoration(
                  color: AppColors.successBg,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '확정됨',
                  style: ResponsiveHelper.tinyStyle(
                    context,
                    color: AppColors.successDark,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 취소 버튼
  Widget _buildCancelButton(ApplicationModel app) {
    return Container(
      margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _cancelApplication(app.id),
        icon: Icon(
          Icons.close,
          size: ResponsiveHelper.iconSize(context, 16),
        ),
        label: Text(
          '지원 취소',
          style: ResponsiveHelper.smallStyle(context),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.error,
          side: const BorderSide(color: AppColors.error),
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 8),
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  /// 계약서 섹션 (확정된 지원서용)
  Widget _buildContractSection(ApplicationModel app) {
    final contract = _contractMap[app.id];

    if (contract == null) return const SizedBox.shrink();

    if (contract.status == ContractStatus.pendingWorker) {
      return Container(
        margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: () => _openContractSign(contract),
          icon: Icon(Icons.draw, size: ResponsiveHelper.iconSize(context, 16)),
          label: Text(
            '근로계약서 서명하기',
            style: ResponsiveHelper.smallStyle(context).copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).primaryColor,
            foregroundColor: Colors.white,
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            elevation: 0,
          ),
        ),
      );
    }

    if (contract.status == ContractStatus.completed) {
      return Column(
        children: [
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            decoration: BoxDecoration(
              color: AppColors.successBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.verified,
                    size: ResponsiveHelper.iconSize(context, 14),
                    color: AppColors.successDark),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Expanded(
                  child: Text(
                    '근로계약서 서명 완료',
                    style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.successDark)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const UserContractsScreen()),
                  ),
                  child: Text(
                    '전체 보기',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.infoDark),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (contract.status == ContractStatus.pendingEmployer) {
      return Container(
        margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 10),
        ),
        decoration: BoxDecoration(
          color: AppColors.warningBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_top, size: ResponsiveHelper.iconSize(context, 14), color: AppColors.warningDark),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(
              '사업주 서명 대기 중',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark),
            ),
          ],
        ),
      );
    }

    if (contract.status == ContractStatus.voided) {
      return Container(
        margin: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 10)),
        width: double.infinity,
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 12),
          vertical: ResponsiveHelper.spacing(context, 10),
        ),
        decoration: BoxDecoration(
          color: AppColors.grey100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.grey300),
        ),
        child: Row(
          children: [
            Icon(Icons.block_outlined,
                size: ResponsiveHelper.iconSize(context, 14),
                color: AppColors.grey500),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Expanded(
              child: Text(
                '계약서가 무효 처리되었습니다. 사업주에게 문의하세요.',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey500),
              ),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  Future<void> _openContractSign(EmploymentContractModel contract) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ContractSignScreen(contract: contract, role: 'worker'),
      ),
    );
    // 서명 완료 후 화면 갱신
    if (mounted) _loadApplications();
  }

  // ═══════════════════════════════════════════════════════════
  // 상태 정보 헬퍼
  // ═══════════════════════════════════════════════════════════

  _StatusInfo _getStatusInfo(String status) {
    switch (status) {
      case AppStatus.confirmed:
        return _StatusInfo(
          label: '확정',
          color: AppColors.successDark,
          bgColor: AppColors.successBg,
        );
      case AppStatus.contractPending:
        return _StatusInfo(
          label: '계약 대기',
          color: Theme.of(context).primaryColor,
          bgColor: Theme.of(context).primaryColor.withValues(alpha: 0.08),
        );
      case AppStatus.pending:
        return _StatusInfo(
          label: '대기중',
          color: AppColors.warningDark,
          bgColor: AppColors.warningBg,
        );
      case AppStatus.rejected:
        return _StatusInfo(
          label: '거절',
          color: AppColors.errorDark,
          bgColor: AppColors.errorBg,
        );
      case AppStatus.canceled:
        return _StatusInfo(
          label: '취소',
          color: AppColors.grey600,
          bgColor: AppColors.grey200,
        );
      case AppStatus.autoCanceled:
        return _StatusInfo(
          label: '자동 취소',
          color: AppColors.warningDark,
          bgColor: AppColors.warningBg,
        );
      default:
        return _StatusInfo(
          label: '알 수 없음',
          color: AppColors.grey600,
          bgColor: AppColors.grey200,
        );
    }
  }
}

// ═══════════════════════════════════════════════════════════
// 데이터 클래스
// ═══════════════════════════════════════════════════════════

class _ApplicationWithTO {
  final ApplicationModel application;
  final TOModel? to; // TO 삭제 시 null 가능

  _ApplicationWithTO({
    required this.application,
    this.to,
  });
}

class _StatusInfo {
  final String label;
  final Color color;
  final Color bgColor;

  _StatusInfo({
    required this.label,
    required this.color,
    required this.bgColor,
  });
}
