// lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart
// 고정근무자 관리 다이얼로그 - 리뉴얼 버전
// 
// 기능:
// - 고정근무자 목록 조회
// - 근무자 상세 정보 (WorkerDetailDialog 연동)
// - 추가 근무 요청
// - 미출근 요청
// - 계약해지 요청 (NEW)

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/schedule_change_request_model.dart';
import '../../../models/core/user_model.dart';
import '../../../services/firestore_service.dart';
import '../../../providers/user_provider.dart';
import '../../../utils/toast_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/dialog_helper.dart';
import '../../../widgets/common/loading_widget.dart';
import '../../../widgets/dialogs/worker_detail_dialog.dart';
import '../../../theme/app_colors.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/dialogs/styled_dialog.dart';

/// 고정근무자 관리 다이얼로그
class FixedWorkerManagementDialog extends StatefulWidget {
  final List<String>? businessIds;  // 여러 사업장 (캘린더에서 호출 시)
  final String? initialBusinessId;  // 초기 선택 사업장
  final VoidCallback onChanged;

  const FixedWorkerManagementDialog({
    super.key,
    this.businessIds,
    this.initialBusinessId,
    required this.onChanged,
  });

  @override
  State<FixedWorkerManagementDialog> createState() => _FixedWorkerManagementDialogState();
}

class _FixedWorkerManagementDialogState extends State<FixedWorkerManagementDialog> {
  final FirestoreService _firestoreService = FirestoreService();

  // 고정근무자 목록 (사용자 정보 포함)
  List<_FixedWorkerItem> _fixedWorkers = [];
  bool _isLoading = true;
  
  // 사업장 선택
  String? _selectedBusinessId;
  Map<String, String> _businessNameMap = {};
  List<String> _businessIds = [];
  bool _showBusinessSelector = false;

  @override
  void initState() {
    super.initState();
    _initBusinessData();
  }

  /// 사업장 데이터 초기화
  Future<void> _initBusinessData() async {
    if (widget.businessIds != null && widget.businessIds!.isNotEmpty) {
      // 여러 사업장 모드 (캘린더에서 호출)
      _businessIds = widget.businessIds!;
      _selectedBusinessId = widget.initialBusinessId ?? _businessIds.first;
      _showBusinessSelector = true;  // ✅ 드롭다운 표시
      await _loadBusinessNames();
    } else if (widget.initialBusinessId != null) {
      // 단일 사업장 모드 (기존 호출)
      _businessIds = [widget.initialBusinessId!];
      _selectedBusinessId = widget.initialBusinessId;
      _showBusinessSelector = false;  // ✅ 드롭다운 숨김
      await _loadBusinessNames();
    }
    
    _loadFixedWorkers();
  }

  /// 사업장명 조회
  Future<void> _loadBusinessNames() async {
    try {
      final nameMap = <String, String>{};
      for (final id in _businessIds) {
        final doc = await FirebaseFirestore.instance
            .collection('businesses')
            .doc(id)
            .get();
        if (doc.exists) {
          nameMap[id] = doc.data()?['name'] ?? 'Unknown';
        } else {
          nameMap[id] = 'Unknown';
        }
      }
      if (mounted) {
        setState(() {
          _businessNameMap = nameMap;
        });
      }
    } catch (e) {
      debugPrint('❌ 사업장명 조회 실패: $e');
    }
  }

  /// 고정근무자 로드
  Future<void> _loadFixedWorkers() async {
    if (_selectedBusinessId == null) {
      setState(() => _isLoading = false);
      return;
    }
    
    setState(() => _isLoading = true);

    try {
      final allApps = await _firestoreService.getApplicationsByBusinessId(_selectedBusinessId!);

      // 장기 근무 확정자만 필터 (퇴사/해지 완료 제외)
      final filtered = allApps.where((app) {
        return app.status == 'CONFIRMED' &&
            app.isLongTermApplication &&  // ✅ 장기 TO 여부 확인
            app.resignStatus != 'APPROVED' &&
            app.resignStatus != 'AUTO_APPROVED' &&
            app.terminationStatus != 'APPROVED' &&      // 🔥 계약해지 완료 제외
            app.terminationStatus != 'AUTO_APPROVED';   // 🔥 자동해지 완료 제외
      }).toList();

      // ✅ 1. 업무유형 정보 한 번만 조회 (중복 제거!)
      final businessWorkTypes = await _firestoreService.getBusinessWorkTypes(_selectedBusinessId!);
      final workTypeMap = { for (var w in businessWorkTypes) w.name: w };
      
      // ✅ 2. 중복 제거된 UID 목록
      final uniqueUids = filtered.map((app) => app.uid).toSet().toList();
      
      // ✅ 3. 사용자 정보 병렬 조회 (중복 없이)
      final userFutures = uniqueUids.map((uid) async {
        final user = await _firestoreService.getUser(uid);
        return MapEntry(uid, user);
      });
      final userEntries = await Future.wait(userFutures);
      final userMap = Map.fromEntries(userEntries);
      
      // ✅ 4. 결과 매핑 (추가 조회 없음)
      final results = filtered.map((app) {
        final matched = workTypeMap[app.selectedWorkType];
        
        return _FixedWorkerItem(
          application: app, 
          user: userMap[app.uid],
          workTypeIcon: matched?.icon,
          workTypeColor: matched?.color,
          workTypeBackgroundColor: matched?.backgroundColor,
        );
      }).toList();

      // 최신 확정순 정렬
      results.sort((a, b) => b.application.confirmedAt!.compareTo(a.application.confirmedAt!));

      setState(() {
        _fixedWorkers = results;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('❌ 고정근무자 로드 실패: $e');
      setState(() => _isLoading = false);
      ToastHelper.showError('고정근무자 목록을 불러올 수 없습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ResponsiveHelper.spacing(context, 20))),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.92,
        height: MediaQuery.of(context).size.height * 0.85,
        constraints: BoxConstraints(maxWidth: ResponsiveHelper.spacing(context, 500)),
        child: Column(
          children: [
            // 헤더
            _buildHeader(context, theme),

            // 통계 바
            _buildStatsBar(context),

            // 목록
            Expanded(
              child: _isLoading
                  ? const LoadingWidget(message: '고정근무자 로딩 중...')
                  : _fixedWorkers.isEmpty
                      ? _buildEmptyState(context)
                      : _buildWorkerList(context),
            ),

            // 하단 버튼
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  /// 헤더
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: AppColors.longTermDark,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(ResponsiveHelper.spacing(context, 20)),
          topRight: Radius.circular(ResponsiveHelper.spacing(context, 20)),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목 행
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.manage_accounts,
                  color: Colors.white,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Text(
                  '고정근무자 관리',
                  style: ResponsiveHelper.subtitleStyle(context).copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // 닫기 버튼
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close, color: Colors.white),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          
          // 사업장 드롭다운 (여러 사업장일 때만 표시)
          if (_showBusinessSelector) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildBusinessDropdown(context),
          ],
        ],
      ),
    );
  }

  /// 사업장 선택 드롭다운
  Widget _buildBusinessDropdown(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: _selectedBusinessId,
          isExpanded: true,
          icon: Icon(
            Icons.keyboard_arrow_down,
            color: AppColors.longTermDark,
          ),
          items: _businessIds.map((id) {
            return DropdownMenuItem<String>(
              value: id,
              child: Row(
                children: [
                  Icon(
                    Icons.business,
                    size: ResponsiveHelper.iconSize(context, 18),
                    color: AppColors.longTermDark,
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                  Expanded(
                    child: Text(
                      _businessNameMap[id] ?? 'Loading...',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null && value != _selectedBusinessId) {
              setState(() {
                _selectedBusinessId = value;
              });
              _loadFixedWorkers();
            }
          },
        ),
      ),
    );
  }

  /// 통계 바
  Widget _buildStatsBar(BuildContext context) {
    final activeCount = _fixedWorkers.where((w) => w.application.resignStatus == null).length;
    final pendingResignCount = _fixedWorkers.where((w) => w.application.resignStatus == 'PENDING').length;
    final terminationPendingCount = _fixedWorkers.where((w) => w.application.terminationStatus == 'PENDING').length;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          _buildStatChip(context, '전체', _fixedWorkers.length, AppColors.longTermDark),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          _buildStatChip(context, '정상', activeCount, AppColors.success),
          if (pendingResignCount > 0) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            _buildStatChip(context, '퇴사대기', pendingResignCount, AppColors.warning),
          ],
          if (terminationPendingCount > 0) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            _buildStatChip(context, '해지대기', terminationPendingCount, AppColors.error),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip(BuildContext context, String label, int count, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 6),
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: ResponsiveHelper.smallStyle(context, color: color),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 6),
              vertical: ResponsiveHelper.spacing(context, 2),
            ),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: ResponsiveHelper.tinyStyle(context, color: Colors.white).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 빈 상태
  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: ResponsiveHelper.iconSize(context, 64),
            color: AppColors.grey400,
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 16)),
          Text(
            '고정근무자가 없습니다',
            style: ResponsiveHelper.subtitleStyle(context, color: AppColors.grey600),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Text(
            '장기 공고에서 지원자를 확정하면\n이곳에 표시됩니다',
            textAlign: TextAlign.center,
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  /// 근무자 목록
  Widget _buildWorkerList(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      itemCount: _fixedWorkers.length,
      separatorBuilder: (_, __) => SizedBox(height: ResponsiveHelper.spacing(context, 12)),
      itemBuilder: (context, index) {
        return _buildWorkerCard(_fixedWorkers[index]);
      },
    );
  }

  /// 근무자 카드
  Widget _buildWorkerCard(_FixedWorkerItem item) {
    final app = item.application;
    final user = item.user;
    final name = user?.name ?? '이름 없음';

    // 상태 판단
    final hasResignRequest = app.resignStatus == 'PENDING';
    final hasTerminationRequest = app.terminationStatus == 'PENDING';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      child: InkWell(
        onTap: () => _showWorkerActions(item),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
          child: Column(
            children: [
              // 상태 배너 (퇴사/해지 요청 중일 때)
              if (hasResignRequest || hasTerminationRequest)
                _buildStatusBanner(app, hasResignRequest, hasTerminationRequest),

              // 기본 정보
              Row(
                children: [
                  // 프로필
                  CircleAvatar(
                    radius: ResponsiveHelper.spacing(context, 24),
                    backgroundColor: AppColors.longTermBg,
                    child: Text(
                      name.isNotEmpty ? name[0] : '?',
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        color: AppColors.longTermDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),

                  // 정보
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              name,
                              style: ResponsiveHelper.bodyStyle(context).copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (user?.gender != null) ...[
                              SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                              Text(
                                '${user!.gender}${user.age != null ? ' · ${user.age}세' : ''}',
                                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                              ),
                            ],
                          ],
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                        // 업무 정보
                        Row(
                          children: [
                            // 업무 아이콘
                            if (item.workTypeIcon != null)
                              WorkTypeIcon.buildWithBackground(
                                iconString: item.workTypeIcon!,
                                iconColor: item.workTypeColor,
                                backgroundColor: item.workTypeBackgroundColor,
                                size: 12,
                                containerSize: 20,
                              )
                            else
                              Icon(
                                Icons.work_outline,
                                size: ResponsiveHelper.iconSize(context, 14),
                                color: AppColors.grey500,
                              ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            Text(
                              app.selectedWorkType,
                              style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                            ),
                          ],
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                        // 요일 (별도 Row)
                        Row(
                          children: [
                            Icon(
                              Icons.calendar_today_outlined,
                              size: ResponsiveHelper.iconSize(context, 12),
                              color: AppColors.grey400,
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            Flexible(
                              child: Text(
                                _formatWorkDays(app.workDays),
                                style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                        // 🔥 시작일: 희망시작일 우선, 종료일: 퇴사일 우선
                        Builder(builder: (_) {
                          final effectiveStartDate = app.desiredStartDate ?? app.workDate;
                          final effectiveEndDate = app.actualResignDate ?? app.workEndDate;
                          return Text(
                            '${DateFormat('M/d').format(effectiveStartDate)} ~ ${effectiveEndDate != null ? DateFormat('M/d').format(effectiveEndDate) : '미정'}',
                          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
                        );
                        }),
                      ],
                    ),
                  ),

                  // 더보기 아이콘
                  Icon(
                    Icons.chevron_right,
                    color: AppColors.grey400,
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 상태 배너
  Widget _buildStatusBanner(ApplicationModel app, bool hasResignRequest, bool hasTerminationRequest) {
    Color bgColor;
    Color textColor;
    IconData icon;
    String statusText;

    if (hasTerminationRequest) {
      bgColor = AppColors.errorBg;
      textColor = AppColors.errorDark;
      icon = Icons.cancel_outlined;
      final daysLeft = 3 - DateTime.now().difference(app.terminationRequestedAt!).inDays;
      statusText = '계약해지 요청중 (${daysLeft > 0 ? '$daysLeft일 후 자동 해지' : '오늘 자동 해지'})';
    } else {
      bgColor = AppColors.warningBg;
      textColor = AppColors.warningDark;
      icon = Icons.exit_to_app;
      final daysLeft = 3 - DateTime.now().difference(app.resignRequestedAt!).inDays;
      statusText = '퇴사 요청중 (${daysLeft > 0 ? '$daysLeft일 후 자동 승인' : '오늘 자동 승인'})';
    }

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 16), color: textColor),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              statusText,
              style: ResponsiveHelper.smallStyle(context, color: textColor).copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 하단 버튼
  Widget _buildBottomBar(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(20),
          bottomRight: Radius.circular(20),
        ),
      ),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton(
          onPressed: () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.grey600,
            side: BorderSide(color: AppColors.grey300),
            padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 14)),
          ),
          child: const Text('닫기'),
        ),
      ),
    );
  }

  /// 근무 요일 포맷
  String _formatWorkDays(List<String>? workDays) {
    if (workDays == null || workDays.isEmpty) return '매일';
    if (workDays.length == 7) return '매일';
    return workDays.join(', ');
  }

  // ============================================================
  // 📋 액션 메서드
  // ============================================================

  /// 근무자 액션 선택 바텀시트
  void _showWorkerActions(_FixedWorkerItem item) {
    final app = item.application;
    final user = item.user;
    final name = user?.name ?? '이름 없음';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 헤더
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppColors.longTermBg,
                      child: Text(
                        name.isNotEmpty ? name[0] : '?',
                        style: TextStyle(
                          color: AppColors.longTermDark,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: ResponsiveHelper.subtitleStyle(context).copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${app.selectedWorkType} · ${_formatWorkDays(app.workDays)}',
                            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                Divider(height: 1, color: AppColors.border),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                // 메뉴 항목들
                _buildActionItem(
                  context,
                  icon: Icons.person_outline,
                  title: '상세 정보 보기',
                  subtitle: '근무자의 상세 정보 확인',
                  color: AppColors.info,
                  onTap: () {
                    Navigator.pop(context);
                    _showWorkerDetail(item);
                  },
                ),

                _buildActionItem(
                  context,
                  icon: Icons.add_circle_outline,
                  title: '추가 근무 요청',
                  subtitle: '휴무일에 추가 근무 요청',
                  color: AppColors.success,
                  onTap: () {
                    Navigator.pop(context);
                    _showExtraWorkRequestDialog(app);
                  },
                ),

                _buildActionItem(
                  context,
                  icon: Icons.remove_circle_outline,
                  title: '미출근 요청',
                  subtitle: '특정 날짜 근무 제외 요청',
                  color: AppColors.warning,
                  onTap: () {
                    Navigator.pop(context);
                    _showNoWorkRequestDialog(app);
                  },
                ),

                // 계약해지 요청 (퇴사 요청이 없을 때만)
                if (app.resignStatus != 'PENDING' && app.terminationStatus != 'PENDING')
                  _buildActionItem(
                    context,
                    icon: Icons.cancel_outlined,
                    title: '계약해지 요청',
                    subtitle: '고정 근무 계약 해지 요청',
                    color: AppColors.error,
                    onTap: () {
                      Navigator.pop(context);
                      _showTerminationRequestDialog(item);
                    },
                  ),

                // 해지 요청 취소 (요청 중일 때만)
                if (app.terminationStatus == 'PENDING')
                  _buildActionItem(
                    context,
                    icon: Icons.undo,
                    title: '해지 요청 취소',
                    subtitle: '계약해지 요청 철회',
                    color: AppColors.grey600,
                    onTap: () {
                      Navigator.pop(context);
                      _cancelTerminationRequest(app);
                    },
                  ),

                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
              ],
            ),
          ),
        );
      },
    );
  }

  /// 액션 아이템 빌더
  Widget _buildActionItem(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 8),
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          child: Row(
            children: [
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: ResponsiveHelper.iconSize(context, 22)),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 14)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.grey400,
                size: ResponsiveHelper.iconSize(context, 20),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 근무자 상세 정보 (WorkerDetailDialog 활용)
  void _showWorkerDetail(_FixedWorkerItem item) {
    if (item.user == null) {
      ToastHelper.showError('사용자 정보를 불러올 수 없습니다');
      return;
    }

    WorkerDetailDialog.show(
      context: context,
      user: item.user!,
      application: item.application,
      businessId: _selectedBusinessId!,
      isConfirmed: true,
      showApprovalButtons: false,
      onStatusChanged: () {
        widget.onChanged();
        _loadFixedWorkers();
      },
    );
  }

  /// 추가 근무 요청 다이얼로그
  Future<void> _showExtraWorkRequestDialog(ApplicationModel app) async {
    // 🔥 실제 근무 기간 계산 (희망시작일/퇴사일 우선)
    final effectiveStartDate = app.desiredStartDate ?? app.workDate;
    final effectiveEndDate = app.actualResignDate ?? app.workEndDate;
    
    if (effectiveEndDate == null) {
      ToastHelper.showError('근무 종료일 정보가 없습니다');
      return;
    }
    
    // 선택 가능한 첫 날짜 찾기
    DateTime? findFirstSelectableDate() {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final workStart = DateTime(effectiveStartDate.year, effectiveStartDate.month, effectiveStartDate.day);
      final workEnd = DateTime(effectiveEndDate.year, effectiveEndDate.month, effectiveEndDate.day);

      DateTime checkDate = now.isAfter(workStart) ? today : workStart;

      while (!checkDate.isAfter(workEnd)) {
        bool isOriginalWorkDay = false;
        if (app.workDays != null && app.workDays!.isNotEmpty) {
          final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
          final dayOfWeek = weekdays[checkDate.weekday - 1];
          isOriginalWorkDay = app.workDays!.contains(dayOfWeek);
        } else {
          isOriginalWorkDay = true;
        }

        if (!isOriginalWorkDay) {
          final alreadyExtra = app.extraWorkDates?.any((d) =>
              d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day) ?? false;
          if (!alreadyExtra) return checkDate;
        } else if (app.leaveDates != null) {
          final isLeaveDay = app.leaveDates!.any((d) =>
              d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day);
          if (isLeaveDay) return checkDate;
        }

        checkDate = checkDate.add(const Duration(days: 1));
      }

      return null;
    }

    final initialDate = findFirstSelectableDate();

    if (initialDate == null) {
      ToastHelper.showWarning('추가 근무 요청 가능한 날짜가 없습니다');
      return;
    }

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: effectiveEndDate,  // 🔥 퇴사일 우선 적용
      locale: const Locale('ko', 'KR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.success,
            ),
          ),
          child: child!,
        );
      },
      selectableDayPredicate: (date) {
        final workStart = DateTime(effectiveStartDate.year, effectiveStartDate.month, effectiveStartDate.day);
        final workEnd = DateTime(effectiveEndDate.year, effectiveEndDate.month, effectiveEndDate.day);
        final targetDate = DateTime(date.year, date.month, date.day);

        if (targetDate.isBefore(workStart) || targetDate.isAfter(workEnd)) return false;

        bool isOriginalWorkDay = false;
        if (app.workDays != null && app.workDays!.isNotEmpty) {
          final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
          final dayOfWeek = weekdays[date.weekday - 1];
          isOriginalWorkDay = app.workDays!.contains(dayOfWeek);
        } else {
          isOriginalWorkDay = true;
        }

        if (isOriginalWorkDay) {
          if (app.leaveDates != null) {
            return app.leaveDates!.any((d) =>
                d.year == date.year && d.month == date.month && d.day == date.day);
          }
          return false;
        }

        if (app.extraWorkDates != null) {
          final alreadyExtra = app.extraWorkDates!.any((d) =>
              d.year == date.year && d.month == date.month && d.day == date.day);
          if (alreadyExtra) return false;
        }

        return true;
      },
    );

    if (selectedDate == null || !mounted) return;

    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StyledDialog(
        title: '추가 근무 요청',
        icon: Icons.add_circle_outline,
        headerColor: AppColors.success,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StyledDialogInfoCard.success(
              DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(selectedDate),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '요청 사유 (선택)',
              style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: '추가 근무 요청 사유를 입력하세요',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context, false),
          ),
          StyledDialogButton.primary(
            text: '요청',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final reason = reasonController.text.trim();
    reasonController.dispose();

    await _submitExtraWorkRequest(app, selectedDate, reason);
  }

  /// 추가 근무 요청 제출
  Future<void> _submitExtraWorkRequest(ApplicationModel app, DateTime date, String reason) async {
    final userProvider = context.read<UserProvider>();
    final adminUid = userProvider.currentUser?.uid;

    if (adminUid == null) {
      ToastHelper.showError('관리자 정보를 찾을 수 없습니다');
      return;
    }

    final worker = await _firestoreService.getUser(app.uid);
    final workerName = worker?.name ?? '이름 없음';

    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: _selectedBusinessId!,
      applicationId: app.id,
      applicantUid: app.uid,
      applicantName: workerName,
      targetDate: DateTime(date.year, date.month, date.day),
      requestType: RequestType.EXTRA_WORK,
      requestedBy: RequesterType.ADMIN,
      requestedByUid: adminUid,
      requestedAt: DateTime.now(),
      reason: reason.isEmpty ? null : reason,
      wageAmount: app.wage,
    );

    final requestId = await _firestoreService.createScheduleChangeRequest(request);

    if (requestId != null) {
      ToastHelper.showSuccess('추가 근무 요청이 전송되었습니다');
      widget.onChanged();
    } else {
      ToastHelper.showError('추가 근무 요청 실패');
    }
  }

  /// 미출근 요청 다이얼로그
  Future<void> _showNoWorkRequestDialog(ApplicationModel app) async {
    // 🔥 실제 근무 기간 계산 (희망시작일/퇴사일 우선)
    final effectiveStartDate = app.desiredStartDate ?? app.workDate;
    final effectiveEndDate = app.actualResignDate ?? app.workEndDate;
    
    if (effectiveEndDate == null) {
      ToastHelper.showError('근무 종료일 정보가 없습니다');
      return;
    }
    
    // 선택 가능한 첫 날짜 찾기
    DateTime? findFirstSelectableDate() {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final workStart = DateTime(effectiveStartDate.year, effectiveStartDate.month, effectiveStartDate.day);
      final workEnd = DateTime(effectiveEndDate.year, effectiveEndDate.month, effectiveEndDate.day);

      DateTime checkDate = now.isAfter(workStart) ? today : workStart;

      while (!checkDate.isAfter(workEnd)) {
        bool isWorkDay = false;
        if (app.workDays != null && app.workDays!.isNotEmpty) {
          final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
          final dayOfWeek = weekdays[checkDate.weekday - 1];
          isWorkDay = app.workDays!.contains(dayOfWeek);
        } else {
          isWorkDay = true;
        }

        if (isWorkDay) {
          final isLeaveDay = app.leaveDates?.any((d) =>
              d.year == checkDate.year && d.month == checkDate.month && d.day == checkDate.day) ?? false;
          if (!isLeaveDay) return checkDate;
        }

        checkDate = checkDate.add(const Duration(days: 1));
      }

      return null;
    }

    final initialDate = findFirstSelectableDate();

    if (initialDate == null) {
      ToastHelper.showWarning('미출근 요청 가능한 날짜가 없습니다');
      return;
    }

    final selectedDate = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime.now(),
      lastDate: effectiveEndDate,  // 🔥 퇴사일 우선 적용
      locale: const Locale('ko', 'KR'),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: AppColors.warning,
            ),
          ),
          child: child!,
        );
      },
      selectableDayPredicate: (date) {
        final workStart = DateTime(effectiveStartDate.year, effectiveStartDate.month, effectiveStartDate.day);
        final workEnd = DateTime(effectiveEndDate.year, effectiveEndDate.month, effectiveEndDate.day);
        final targetDate = DateTime(date.year, date.month, date.day);

        if (targetDate.isBefore(workStart) || targetDate.isAfter(workEnd)) return false;

        bool isWorkDay = false;
        if (app.workDays != null && app.workDays!.isNotEmpty) {
          final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
          final dayOfWeek = weekdays[date.weekday - 1];
          isWorkDay = app.workDays!.contains(dayOfWeek);
        } else {
          isWorkDay = true;
        }

        if (!isWorkDay) return false;

        if (app.leaveDates != null) {
          final isLeaveDay = app.leaveDates!.any((d) =>
              d.year == date.year && d.month == date.month && d.day == date.day);
          if (isLeaveDay) return false;
        }

        return true;
      },
    );

    if (selectedDate == null || !mounted) return;

    final reasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StyledDialog(
        title: '미출근 요청',
        icon: Icons.remove_circle_outline,
        headerColor: AppColors.warning,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            StyledDialogInfoCard.warning(
              DateFormat('yyyy년 M월 d일 (E)', 'ko_KR').format(selectedDate),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Text(
              '요청 사유',
              style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.bold),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            TextField(
              controller: reasonController,
              decoration: InputDecoration(
                hintText: '미출근 요청 사유를 입력하세요',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              maxLines: 2,
            ),
          ],
        ),
        actions: [
          StyledDialogButton.cancel(
            onPressed: () => Navigator.pop(context, false),
          ),
          StyledDialogButton.primary(
            text: '요청',
            onPressed: () => Navigator.pop(context, true),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await _submitNoWorkRequest(app, selectedDate, reasonController.text.trim());
    reasonController.dispose();
  }

  /// 미출근 요청 제출
  Future<void> _submitNoWorkRequest(ApplicationModel app, DateTime date, String reason) async {
    final userProvider = context.read<UserProvider>();
    final adminUid = userProvider.currentUser?.uid;

    if (adminUid == null) {
      ToastHelper.showError('관리자 정보를 찾을 수 없습니다');
      return;
    }

    final worker = await _firestoreService.getUser(app.uid);
    final workerName = worker?.name ?? '이름 없음';

    final request = ScheduleChangeRequestModel(
      id: '',
      businessId: _selectedBusinessId!,
      applicationId: app.id,
      applicantUid: app.uid,
      applicantName: workerName,
      targetDate: DateTime(date.year, date.month, date.day),
      requestType: RequestType.NO_WORK,
      requestedBy: RequesterType.ADMIN,
      requestedByUid: adminUid,
      requestedAt: DateTime.now(),
      reason: reason.isEmpty ? null : reason,
      wageAmount: app.wage,
    );

    final requestId = await _firestoreService.createScheduleChangeRequest(request);

    if (requestId != null) {
      ToastHelper.showSuccess('미출근 요청이 전송되었습니다');
      widget.onChanged();
    } else {
      ToastHelper.showError('미출근 요청 실패');
    }
  }

  // ============================================================
  // 🔥 계약해지 요청 (NEW)
  // ============================================================

  /// 계약해지 요청 다이얼로그
  Future<void> _showTerminationRequestDialog(_FixedWorkerItem item) async {
    final app = item.application;
    final user = item.user;
    final name = user?.name ?? '이름 없음';

    String? selectedReason;
    final customReasonController = TextEditingController();

    final reasons = [
      '업무 능력 부족',
      '근태 불량 (지각/결근)',
      '업무 태도 불량',
      '인력 구조 조정',
      '계약 조건 불일치',
      '기타',
    ];

    final result = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 헤더
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cancel_outlined,
                          color: Colors.white,
                          size: ResponsiveHelper.iconSize(context, 24),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '계약해지 요청',
                                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '$name님',
                                style: ResponsiveHelper.smallStyle(context, color: Colors.white70),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(Icons.close, color: Colors.white, size: ResponsiveHelper.iconSize(context, 24)),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // 안내
                  Container(
                    margin: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                    decoration: BoxDecoration(
                      color: AppColors.infoBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, size: ResponsiveHelper.iconSize(context, 20), color: AppColors.infoDark),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Expanded(
                          child: Text(
                            '근무자가 3일 이내 승인/거절하지 않으면\n자동으로 계약이 해지됩니다.',
                            style: ResponsiveHelper.smallStyle(context, color: AppColors.infoDark),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 사유 선택
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '해지 사유를 선택해주세요',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

                        ...reasons.map((reason) => Padding(
                          padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
                          child: InkWell(
                            onTap: () => setDialogState(() => selectedReason = reason),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 12),
                                vertical: ResponsiveHelper.spacing(context, 12),
                              ),
                              decoration: BoxDecoration(
                                color: selectedReason == reason ? AppColors.errorBg : AppColors.grey100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selectedReason == reason ? AppColors.error : AppColors.grey300,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selectedReason == reason
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    color: selectedReason == reason ? AppColors.error : AppColors.grey400,
                                    size: ResponsiveHelper.iconSize(context, 20),
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                                  Text(reason, style: ResponsiveHelper.bodyStyle(context)),
                                ],
                              ),
                            ),
                          ),
                        )),

                        // 기타 사유 입력
                        if (selectedReason == '기타') ...[
                          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                          TextField(
                            controller: customReasonController,
                            decoration: InputDecoration(
                              hintText: '상세 사유를 입력하세요',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 12),
                                vertical: ResponsiveHelper.spacing(context, 12),
                              ),
                            ),
                            style: ResponsiveHelper.bodyStyle(context),
                            maxLines: 2,
                          ),
                        ],
                      ],
                    ),
                  ),

                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                  // 하단 버튼
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.grey600,
                              side: BorderSide(color: AppColors.grey300),
                              padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                            ),
                            child: const Text('취소'),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedReason != null
                                ? () {
                                    final reason = selectedReason == '기타' &&
                                            customReasonController.text.trim().isNotEmpty
                                        ? customReasonController.text.trim()
                                        : selectedReason;
                                    Navigator.pop(context, reason);
                                  }
                                : null,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.error,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 12)),
                            ),
                            child: const Text('해지 요청'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    customReasonController.dispose();

    if (result == null || !mounted) return;

    await _submitTerminationRequest(app, result);
  }

  /// 계약해지 요청 제출
  Future<void> _submitTerminationRequest(ApplicationModel app, String reason) async {
    final userProvider = context.read<UserProvider>();
    final adminUid = userProvider.currentUser?.uid;

    if (adminUid == null) {
      ToastHelper.showError('관리자 정보를 찾을 수 없습니다');
      return;
    }

    try {
      // TODO: FirestoreService에 requestTermination 메서드 추가 필요
      // 현재는 임시로 application 필드 업데이트
      final success = await _firestoreService.requestTermination(
        applicationId: app.id,
        reason: reason,
        requestedByUid: adminUid,
      );

      if (success && mounted) {
        ToastHelper.showSuccess('계약해지 요청이 전송되었습니다');
        widget.onChanged();
        _loadFixedWorkers();
      } else if (mounted) {
        ToastHelper.showError('계약해지 요청에 실패했습니다');
      }
    } catch (e) {
      debugPrint('❌ 계약해지 요청 실패: $e');
      if (mounted) {
        ToastHelper.showError('계약해지 요청 중 오류가 발생했습니다');
      }
    }
  }

  /// 해지 요청 취소
  Future<void> _cancelTerminationRequest(ApplicationModel app) async {
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '해지 요청 취소',
      message: '계약해지 요청을 취소하시겠습니까?',
      confirmText: '취소하기',
      confirmColor: AppColors.warning,
    );

    if (confirmed != true || !mounted) return;

    try {
      // TODO: FirestoreService에 cancelTerminationRequest 메서드 추가 필요
      final success = await _firestoreService.cancelTerminationRequest(app.id);

      if (success && mounted) {
        ToastHelper.showSuccess('해지 요청이 취소되었습니다');
        widget.onChanged();
        _loadFixedWorkers();
      } else if (mounted) {
        ToastHelper.showError('해지 요청 취소에 실패했습니다');
      }
    } catch (e) {
      debugPrint('❌ 해지 요청 취소 실패: $e');
      if (mounted) {
        ToastHelper.showError('해지 요청 취소 중 오류가 발생했습니다');
      }
    }
  }
}

class _FixedWorkerItem {
  final ApplicationModel application;
  final UserModel? user;
  final String? workTypeIcon;
  final String? workTypeColor;
  final String? workTypeBackgroundColor;  // 🔥 추가

  _FixedWorkerItem({
    required this.application,
    this.user,
    this.workTypeIcon,
    this.workTypeColor,
    this.workTypeBackgroundColor,  // 🔥 추가
  });
}