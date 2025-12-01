import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../models/core/user_model.dart';
import '../../../services/firestore_service.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../widgets/work_type_icon.dart';
import '../../../widgets/dialogs/styled_dialog.dart';
import '../../../models/ui/admin_to_list_ui_models.dart';
import '../../../theme/app_colors.dart';

class ConfirmedListDialog {
  final BuildContext context;
  final TOItem toItem;
  final FirestoreService firestoreService;

  ConfirmedListDialog({
    required this.context,
    required this.toItem,
    required this.firestoreService,
  });

  void show() {
    showDialog(
      context: context,
      builder: (context) => _ConfirmedListDialogWidget(
        toItem: toItem,
        firestoreService: firestoreService,
      ),
    );
  }
}

class _ConfirmedListDialogWidget extends StatefulWidget {
  final TOItem toItem;
  final FirestoreService firestoreService;

  const _ConfirmedListDialogWidget({
    required this.toItem,
    required this.firestoreService,
  });

  @override
  State<_ConfirmedListDialogWidget> createState() =>
      _ConfirmedListDialogWidgetState();
}

class _ConfirmedListDialogWidgetState
    extends State<_ConfirmedListDialogWidget> {
  bool _isLoading = true;
  Map<String, List<Map<String, dynamic>>> _confirmedByWork = {};
  String? _error;
  int _totalConfirmed = 0;

  @override
  void initState() {
    super.initState();
    _loadConfirmedApplicants();
  }

  Future<void> _loadConfirmedApplicants() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final applications = await widget.firestoreService.getApplicationsByTO(
        widget.toItem.to.businessId,
        widget.toItem.to.title,
        widget.toItem.to.date,
      );

      final confirmed =
          applications.where((app) => app.status == 'CONFIRMED').toList();

      final futures = confirmed.map((app) async {
        final user = await widget.firestoreService.getUser(app.uid);
        return {
          'application': app,
          'user': user,
          'workType': app.selectedWorkType,
        };
      }).toList();

      final results = await Future.wait(futures);

      final Map<String, List<Map<String, dynamic>>> groupedByWork = {};

      for (var result in results) {
        if (result['user'] != null) {
          final workType = result['workType'] as String;
          groupedByWork.putIfAbsent(workType, () => []);
          groupedByWork[workType]!.add(result);
        }
      }

      setState(() {
        _confirmedByWork = groupedByWork;
        _totalConfirmed = confirmed.length;
        _isLoading = false;
      });
    } catch (e) {
      print('❌ 확정 명단 로드 실패: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MM/dd (E)', 'ko_KR');

    return StyledDialog(
      title: '확정 명단',
      subtitle:
          '${dateFormat.format(widget.toItem.to.date)} · ${widget.toItem.to.title}',
      icon: Icons.check_circle,
      headerColor: AppColors.success,
      maxHeightRatio: 0.85,
      content: _buildContent(),
      actions: [
        StyledDialogButton.cancel(
          text: '닫기',
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return SizedBox(
        height: ResponsiveHelper.spacing(context, 200),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(
                color: AppColors.success,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Text(
                '확정 명단을 불러오는 중...',
                style: ResponsiveHelper.bodyStyle(
                  context,
                  color: AppColors.grey600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return SizedBox(
        height: ResponsiveHelper.spacing(context, 200),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: ResponsiveHelper.iconSize(context, 48),
                color: AppColors.error,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Text(
                '데이터를 불러오는데 실패했습니다',
                style: ResponsiveHelper.bodyStyle(
                  context,
                  color: AppColors.grey600,
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              TextButton.icon(
                onPressed: _loadConfirmedApplicants,
                icon: const Icon(Icons.refresh),
                label: const Text('다시 시도'),
              ),
            ],
          ),
        ),
      );
    }

    if (_confirmedByWork.isEmpty) {
      return SizedBox(
        height: ResponsiveHelper.spacing(context, 200),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.people_outline,
                size: ResponsiveHelper.iconSize(context, 48),
                color: AppColors.grey400,
              ),
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              Text(
                '확정된 인원이 없습니다',
                style: ResponsiveHelper.bodyStyle(
                  context,
                  color: AppColors.grey600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 총 인원 배지
        _buildTotalBadge(),
        SizedBox(height: ResponsiveHelper.spacing(context, 16)),

        // 업무별 목록
        ..._confirmedByWork.entries.map((entry) {
          final workType = entry.key;
          final workers = entry.value;
          final workDetail = widget.toItem.workDetails.firstWhere(
            (w) => w.workType == workType,
            orElse: () => widget.toItem.workDetails.first,
          );

          return _buildWorkSection(workType, workers, workDetail);
        }),
      ],
    );
  }

  Widget _buildTotalBadge() {
    final theme = Theme.of(context);

    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.success.withOpacity(0.1),
            AppColors.success.withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.success.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.groups,
              color: AppColors.success,
              size: ResponsiveHelper.iconSize(context, 24),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 16)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '총 확정 인원',
                  style: ResponsiveHelper.smallStyle(
                    context,
                    color: AppColors.grey600,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                Text(
                  '$_totalConfirmed명',
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.success,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 6),
            ),
            decoration: BoxDecoration(
              color: AppColors.success,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_confirmedByWork.length}개 업무',
              style: ResponsiveHelper.smallStyle(
                context,
                color: Colors.white,
              ).copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkSection(
    String workType,
    List<Map<String, dynamic>> workers,
    WorkDetailModel workDetail,
  ) {
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // 업무 헤더
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                WorkTypeIcon.buildWithBackground(
                  iconString: workDetail.workTypeIcon,
                  backgroundColor: workDetail.workTypeBackgroundColor,
                  size: ResponsiveHelper.iconSize(context, 32),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        workType,
                        style: ResponsiveHelper.subtitleStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '${workDetail.startTime} ~ ${workDetail.endTime}',
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: AppColors.grey600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 10),
                    vertical: ResponsiveHelper.spacing(context, 4),
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${workers.length}명',
                    style: ResponsiveHelper.bodyStyle(
                      context,
                      color: AppColors.success,
                    ).copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),

          // 근무자 목록
          ...workers.asMap().entries.map((entry) {
            final index = entry.key;
            final worker = entry.value;
            final user = worker['user'] as UserModel;
            final application = worker['application'] as ApplicationModel;
            final isLast = index == workers.length - 1;

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _showWorkerDetailDialog(context, user, application, workDetail),
                borderRadius: isLast 
                    ? const BorderRadius.only(
                        bottomLeft: Radius.circular(16),
                        bottomRight: Radius.circular(16),
                      )
                    : null,
                child: Container(
                  padding: ResponsiveHelper.cardPadding(context),
                  decoration: BoxDecoration(
                    border: isLast
                        ? null
                        : Border(
                            bottom: BorderSide(color: AppColors.grey100),
                          ),
                  ),
                  child: Row(
                    children: [
                      // 순번
                      Container(
                        width: ResponsiveHelper.spacing(context, 28),
                        height: ResponsiveHelper.spacing(context, 28),
                        decoration: BoxDecoration(
                          color: AppColors.grey100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '${index + 1}',
                            style: ResponsiveHelper.smallStyle(
                              context,
                              color: AppColors.grey700,
                            ).copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),

                      // 이름 + 정보
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  user.name,
                                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                                Icon(
                                  Icons.chevron_right,
                                  size: ResponsiveHelper.iconSize(context, 16),
                                  color: AppColors.grey400,
                                ),
                              ],
                            ),
                            SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                            Row(
                              children: [
                                if (user.gender != null) ...[
                                  Text(
                                    user.gender!,
                                    style: ResponsiveHelper.tinyStyle(
                                      context,
                                      color: AppColors.grey600,
                                    ),
                                  ),
                                  if (user.age != null)
                                    Text(
                                      ' · ${user.age}세',
                                      style: ResponsiveHelper.tinyStyle(
                                        context,
                                        color: AppColors.grey600,
                                      ),
                                    ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),

                      // 연락처
                      if (user.phone != null)
                        Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 10),
                            vertical: ResponsiveHelper.spacing(context, 6),
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.infoBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.phone,
                                size: ResponsiveHelper.iconSize(context, 14),
                                color: AppColors.info,
                              ),
                              SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                              Text(
                                FormatHelper.formatPhone(user.phone!),
                                style: ResponsiveHelper.smallStyle(
                                  context,
                                  color: AppColors.info,
                                ).copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  /// ✨ 근무자 상세정보 다이얼로그
  void _showWorkerDetailDialog(
    BuildContext context,
    UserModel user,
    ApplicationModel application,
    WorkDetailModel workDetail,
  ) {
    showDialog(
      context: context,
      builder: (context) => StyledDialog(
        title: '근무자 상세정보',
        subtitle: user.name,
        icon: Icons.person,
        headerColor: AppColors.info,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 기본 정보 섹션
            _buildDetailSection(
              context,
              title: '기본 정보',
              icon: Icons.badge,
              children: [
                _buildDetailRow(context, '이름', user.name),
                _buildDetailRow(
                  context, 
                  '성별 · 나이', 
                  user.gender != null && user.age != null
                      ? '${user.gender} · ${user.age}세'
                      : '-',
                ),
                _buildDetailRow(context, '연락처', user.phone ?? '-', isPhone: true),
                _buildDetailRow(
                  context, 
                  '주소', 
                  user.address != null 
                      ? '${user.address}${user.detailAddress != null ? ' ${user.detailAddress}' : ''}'
                      : '-',
                ),
              ],
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 근무 통계 섹션
            _buildDetailSection(
              context,
              title: '근무 통계',
              icon: Icons.bar_chart,
              children: [
                _buildStatRow(context, '총 근무', '${user.totalWorkDays}일', Icons.calendar_today, AppColors.info),
                _buildStatRow(context, '평균 평점', '${user.averageRating.toStringAsFixed(1)}점', Icons.star, Colors.amber),
                _buildStatRow(context, '무단결근', '${user.noShowCount}회', Icons.cancel, AppColors.error),
                _buildStatRow(context, '지각', '${user.lateCount}회', Icons.schedule, AppColors.warning),
              ],
            ),
            
            // 자기소개 (있는 경우만)
            if (user.bio != null && user.bio!.isNotEmpty) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 16)),
              _buildDetailSection(
                context,
                title: '자기소개',
                icon: Icons.description,
                children: [
                  Text(
                    user.bio!,
                    style: ResponsiveHelper.bodyStyle(context),
                  ),
                ],
              ),
            ],
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 급여 정보 섹션
            _buildDetailSection(
              context,
              title: '급여 정보',
              icon: Icons.account_balance,
              children: [
                _buildDetailRow(context, '은행', user.bankName ?? '-'),
                _buildDetailRow(context, '계좌번호', user.accountNumber ?? '-'),
                _buildDetailRow(context, '예금주', user.accountHolder ?? '-'),
              ],
            ),
            
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            
            // 인증 상태
            Container(
              padding: ResponsiveHelper.cardPadding(context),
              decoration: BoxDecoration(
                color: user.isIdVerified == true
                    ? AppColors.successBg
                    : AppColors.warningBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: user.isIdVerified == true
                      ? AppColors.success.withOpacity(0.3)
                      : AppColors.warning.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    user.isIdVerified == true ? Icons.verified : Icons.warning_amber,
                    color: user.isIdVerified == true
                        ? AppColors.success
                        : AppColors.warning,
                    size: ResponsiveHelper.iconSize(context, 20),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Text(
                      user.isIdVerified == true
                          ? '신분증 인증 완료'
                          : '신분증 미인증',
                      style: ResponsiveHelper.bodyStyle(
                        context,
                        color: user.isIdVerified == true
                            ? AppColors.success
                            : AppColors.warning,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          // 전화걸기 버튼
          if (user.phone != null)
            StyledDialogButton.primary(
              text: '전화 걸기',
              backgroundColor: AppColors.success,
              onPressed: () => _callPhone(user.phone!),
            ),
          StyledDialogButton.cancel(
            text: '닫기',
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  /// 통계 행 빌더 (아이콘 + 색상)
  Widget _buildStatRow(
    BuildContext context,
    String label,
    String value,
    IconData icon,
    Color color,
  ) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              size: ResponsiveHelper.iconSize(context, 16),
              color: color,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Text(
              label,
              style: ResponsiveHelper.bodyStyle(
                context,
                color: AppColors.grey600,
              ),
            ),
          ),
          Text(
            value,
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// 상세정보 섹션 빌더
  Widget _buildDetailSection(
    BuildContext context, {
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 섹션 헤더
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 16),
              vertical: ResponsiveHelper.spacing(context, 12),
            ),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: ResponsiveHelper.iconSize(context, 18),
                  color: theme.primaryColor,
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  title,
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
          // 섹션 내용
          Padding(
            padding: ResponsiveHelper.cardPadding(context),
            child: Column(children: children),
          ),
        ],
      ),
    );
  }

  /// 상세정보 행 빌더
  Widget _buildDetailRow(
    BuildContext context,
    String label,
    String value, {
    bool isPhone = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ResponsiveHelper.spacing(context, 80),
            child: Text(
              label,
              style: ResponsiveHelper.smallStyle(
                context,
                color: AppColors.grey600,
              ),
            ),
          ),
          Expanded(
            child: isPhone && value != '-'
                ? GestureDetector(
                    onTap: () => _callPhone(value),
                    child: Text(
                      FormatHelper.formatPhone(value),
                      style: ResponsiveHelper.bodyStyle(
                        context,
                        color: AppColors.info,
                      ).copyWith(
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  )
                : Text(
                    value,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 전화 걸기
  Future<void> _callPhone(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      ToastHelper.showError('전화 앱을 열 수 없습니다');
    }
  }
}