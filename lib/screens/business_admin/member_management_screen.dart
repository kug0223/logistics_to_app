import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/business_member_model.dart';
import '../../models/core/member_invitation_model.dart';
import '../../providers/user_provider.dart';
import '../../services/firestore_service.dart';
import '../../services/member_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_menu_sheet.dart';
import '../../widgets/common/loading_widget.dart';

// 사업장별 멤버/초대 데이터 묶음
class _BizSection {
  final String id;
  final String name;
  final List<BusinessMemberModel> members;
  final List<MemberInvitationModel> pendingInvitations;

  _BizSection({
    required this.id,
    required this.name,
    required this.members,
    required this.pendingInvitations,
  });
}

class MemberManagementScreen extends StatefulWidget {
  const MemberManagementScreen({super.key});

  @override
  State<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

class _MemberManagementScreenState extends State<MemberManagementScreen> {
  final _service = MemberService();
  final _firestoreService = FirestoreService();
  List<_BizSection> _sections = [];
  // CF 오류 등으로 _sections = [] 상태여도 초대 버튼 표시용 — _load 성공 전반부에 저장
  List<String> _bizIds = [];
  Map<String, String> _bizNameMap = {};
  bool _loading = false;
  bool _isProcessing = false;
  bool _isSubAdmin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
    });
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final user = context.read<UserProvider>().currentUser;
      if (user == null) {
        setState(() { _sections = []; _loading = false; });
        return;
      }

      final isSubAdmin = user.isSubAdmin;
      final bizIds = isSubAdmin
          ? user.subAdminBusinessIds
          : user.managedBusinessIds;

      if (bizIds.isEmpty) {
        setState(() { _sections = []; _isSubAdmin = isSubAdmin; _loading = false; });
        return;
      }

      // 사업장 이름 병렬 조회
      final businesses = await _firestoreService.getBusinessesByIds(bizIds);
      final bizNameMap = {for (final b in businesses) b.id: b.name};
      // 조기 저장 — 이후 CF 오류가 나도 _buildEmpty에서 초대 버튼 표시 가능
      if (mounted) setState(() { _bizIds = bizIds; _bizNameMap = bizNameMap; _isSubAdmin = isSubAdmin; });

      // 사업장별 멤버+초대 병렬 조회
      // SubAdmin은 초대 권한 없음 — getSentPendingInvitations 호출 스킵
      // M1: 각 사업장 내에서도 getMembers + getSentPendingInvitations 병렬 실행
      List<_BizSection> sectionResults = [];
      sectionResults = await Future.wait(
        bizIds.map((id) async {
          final pair = await Future.wait([
            _service.getMembers(id),
            isSubAdmin
                ? Future.value(<MemberInvitationModel>[])
                : _service.getSentPendingInvitations(id),
          ]);
          return _BizSection(
            id: id,
            name: bizNameMap[id] ?? id,
            members: pair[0] as List<BusinessMemberModel>,
            pendingInvitations: pair[1] as List<MemberInvitationModel>,
          );
        }),
      );

      // M2: 이전 setState(() => _sections) + finally setState(() => _loading=false) 병합
      if (!mounted) return;
      setState(() { _sections = sectionResults; _loading = false; });
    } catch (e) {
      if (mounted) {
        ToastHelper.showError('멤버 목록을 불러오지 못했습니다');
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _cancelInvitation(MemberInvitationModel invitation) async {
    if (_isProcessing) return;
    final ok = await DialogHelper.showDeleteConfirm(
      context,
      itemName: '"${invitation.targetName}" 초대',
      additionalMessage: '취소하면 상대방이 더 이상 수락할 수 없습니다.',
    );
    if (ok != true || !mounted) return;
    setState(() => _isProcessing = true);
    try {
      await _service.cancelInvitation(invitation);
      if (!mounted) return;
      ToastHelper.showSuccess('초대를 취소했습니다');
      _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('초대 취소에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _invite(String businessId, String businessName) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _InviteDialog(
        businessId: businessId,
        businessName: businessName,
      ),
    );
    if (result == true && mounted) _load();
  }

  Future<void> _editPermissions(
      String businessId, BusinessMemberModel member) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final result = await DialogHelper.showSheet<MemberPermissions>(
        context,
        isScrollControlled: true,
        builder: (_) => _PermissionSheet(
          memberName: member.name,
          memberInitial: member.name.isNotEmpty ? member.name[0] : '?',
          current: member.permissions,
        ),
      );
      if (result == null || !mounted) return;
      await _service.updatePermissions(
        businessId: businessId,
        uid: member.uid,
        permissions: result,
      );
      if (!mounted) return;
      ToastHelper.showSuccess('권한이 업데이트되었습니다');
      _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('권한 업데이트에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _remove(String businessId, BusinessMemberModel member) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final ok = await DialogHelper.showDeleteConfirm(
        context,
        itemName: '"${member.name}" 멤버',
      );
      if (ok != true || !mounted) return;
      await _service.removeMember(
        businessId: businessId,
        uid: member.uid,
      );
      if (!mounted) return;
      ToastHelper.showSuccess('멤버가 제거되었습니다');
      _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('멤버 제거에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  bool get _isSingleBiz => _sections.length == 1;

  bool get _isEmpty => _sections.every(
      (s) => s.members.isEmpty && s.pendingInvitations.isEmpty);

  @override
  Widget build(BuildContext context) {
    final isEmpty = _isEmpty; // L2: build() 내 2회 중복 평가 방지
    return GradientScaffold(
      title: '멤버 관리',
      onRefresh: _load,
      // 사업장 1개일 때만 FAB — 멤버가 있어야 표시 (empty 상태는 _buildEmpty의 버튼 사용)
      // SubAdmin은 초대 권한 없음
      floatingActionButton: !_isSubAdmin && _isSingleBiz && _sections.isNotEmpty && !isEmpty
          ? FloatingActionButton.extended(
              onPressed: () =>
                  _invite(_sections.first.id, _sections.first.name),
              icon: const Icon(Icons.person_add_outlined),
              label: const Text('멤버 초대'),
            )
          : null,
      body: _loading
          ? const LoadingWidget()
          : _sections.isEmpty || isEmpty
              ? _buildEmpty(context)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Builder(builder: (context) {
                    final items = [
                      for (final s in _sections) ..._buildSection(context, s),
                    ];
                    return ListView.builder(
                      padding: ResponsiveHelper.listPadding(context),
                      itemCount: items.length,
                      itemBuilder: (_, i) => items[i],
                    );
                  }),
                ),
    );
  }

  List<Widget> _buildSection(BuildContext context, _BizSection section) {
    final hasPending = section.pendingInvitations.isNotEmpty;
    final hasMembers = section.members.isNotEmpty;

    if (!hasPending && !hasMembers) {
      return [
        if (!_isSingleBiz)
          _buildBizHeader(context, section)
        else
          _buildSingleBizHeader(context, section),
        Padding(
          padding: EdgeInsets.only(
            bottom: ResponsiveHelper.spacing(context, 16),
          ),
          child: Center(
            child: Text(
              '등록된 멤버가 없습니다',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey400),
            ),
          ),
        ),
      ];
    }

    return [
      if (!_isSingleBiz)
        _buildBizHeader(context, section)
      else
        _buildSingleBizHeader(context, section),
      if (hasPending) ...[
        _buildSectionHeader(
          context,
          '초대 대기 중 (${section.pendingInvitations.length}건)',
          AppColors.warningDark,
        ),
        ...section.pendingInvitations.map((inv) => _PendingInvitationCard(
              invitation: inv,
              onCancel: () => _cancelInvitation(inv),
            )),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
      ],
      if (hasMembers) ...[
        if (hasPending)
          _buildSectionHeader(
            context,
            '등록된 멤버 (${section.members.length}명)',
            AppColors.successDark,
          ),
        ...section.members.map((m) => _MemberCard(
              member: m,
              businessName: _isSingleBiz ? null : section.name,
              canEdit: !_isSubAdmin,
              onEdit: () => _editPermissions(section.id, m),
              onRemove: () => _remove(section.id, m),
            )),
      ],
      if (!_isSingleBiz)
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
    ];
  }

  // 단일 사업장 시 간결한 사업장 이름 표시 (섹션 헤더 없이 맥락 제공)
  Widget _buildSingleBizHeader(BuildContext context, _BizSection section) {
    return Padding(
      padding: EdgeInsets.only(
        top: ResponsiveHelper.spacing(context, 4),
        bottom: ResponsiveHelper.spacing(context, 10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.storefront_outlined,
            size: ResponsiveHelper.iconSize(context, 13),
            color: AppColors.grey500,
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 5)),
          Flexible(
            child: Text(
              section.name,
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // 다중 사업장 그룹 헤더 (+초대 버튼 포함)
  Widget _buildBizHeader(BuildContext context, _BizSection section) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        top: ResponsiveHelper.spacing(context, 16),
        bottom: ResponsiveHelper.spacing(context, 8),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 16,
            decoration: BoxDecoration(
              color: theme.primaryColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              section.name,
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.w800,
                color: theme.primaryColor,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (!_isSubAdmin)
            TextButton.icon(
              onPressed: () => _invite(section.id, section.name),
              icon: Icon(Icons.person_add_outlined,
                  size: ResponsiveHelper.iconSize(context, 15)),
              label: Text('초대',
                  style: ResponsiveHelper.smallStyle(context,
                      color: theme.primaryColor,
                      fontWeight: FontWeight.w600)),
              style: TextButton.styleFrom(
                foregroundColor: theme.primaryColor,
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: ResponsiveHelper.spacing(context, 4),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(
      BuildContext context, String title, Color color) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 8),
        top: ResponsiveHelper.spacing(context, 4),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            title,
            style: ResponsiveHelper.smallStyle(context).copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final theme = Theme.of(context);
    // _sections 우선, CF 오류 등으로 비었으면 _bizIds/_bizNameMap으로 폴백
    final bizList = _sections.isNotEmpty
        ? _sections.map((s) => (id: s.id, name: s.name)).toList()
        : _bizIds
            .where((id) => id.isNotEmpty)
            .map((id) => (id: id, name: _bizNameMap[id] ?? id))
            .toList();

    Widget? action;
    if (_isSubAdmin) {
      // SubAdmin은 초대 권한 없음 — 버튼 미표시
    } else if (bizList.length == 1) {
      // 단일 사업장 — 기존 전체폭 버튼
      final biz = bizList.first;
      action = Padding(
        padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _invite(biz.id, biz.name),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: EdgeInsets.symmetric(vertical: ResponsiveHelper.spacing(context, 20)),
              decoration: BoxDecoration(
                border: Border.all(color: theme.primaryColor.withValues(alpha: 0.3), width: 2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_add_outlined, color: theme.primaryColor, size: ResponsiveHelper.iconSize(context, 24)),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Text('멤버 초대', style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: theme.primaryColor, fontWeight: FontWeight.bold,
                  )),
                ],
              ),
            ),
          ),
        ),
      );
    } else if (bizList.length > 1) {
      // 다중 사업장 — 사업장별 초대 버튼 나열
      action = Padding(
        padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
        child: Column(
          children: bizList.map((biz) => Padding(
            padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => _invite(biz.id, biz.name),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 16),
                    vertical: ResponsiveHelper.spacing(context, 14),
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.primaryColor.withValues(alpha: 0.3), width: 1.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.business_outlined, color: theme.primaryColor, size: ResponsiveHelper.iconSize(context, 18)),
                      SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                      Expanded(
                        child: Text(biz.name, style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: theme.primaryColor, fontWeight: FontWeight.w600,
                        ), overflow: TextOverflow.ellipsis),
                      ),
                      Icon(Icons.person_add_outlined, color: theme.primaryColor, size: ResponsiveHelper.iconSize(context, 16)),
                      SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                      Text('초대', style: ResponsiveHelper.smallStyle(context, color: theme.primaryColor).copyWith(fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ),
          )).toList(),
        ),
      );
    }

    return AppEmptyState(
      icon: Icons.group_outlined,
      title: '등록된 멤버가 없습니다',
      subtitle: _isSubAdmin
          ? '관리자에게 문의하여 멤버를 초대받으세요'
          : bizList.length > 1
              ? '초대할 사업장을 선택하세요'
              : '멤버를 초대하고 사업장을 함께 관리해보세요',
      action: action,
    );
  }
}

// ─── 멤버 카드 ─────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  final BusinessMemberModel member;
  final String? businessName; // 다중 사업장 시 소속 사업장명, 단일 시 null
  final VoidCallback onEdit;
  final VoidCallback onRemove;
  final bool canEdit; // false이면 편집·삭제 메뉴 숨김 (SubAdmin은 읽기 전용)

  const _MemberCard({
    required this.member,
    this.businessName,
    required this.onEdit,
    required this.onRemove,
    this.canEdit = true,
  });

  List<String> _activePerms() {
    final p = member.permissions;
    return [
      if (p.canManageTo) '공고',
      if (p.canManageWorkers) '근무자',
      if (p.canManageWage) '급여',
      if (p.canManageContract) '계약서',
      if (p.canCancelTransfer) '이체취소',
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activePerms = _activePerms();

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 14),
          vertical: ResponsiveHelper.spacing(context, 12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: theme.primaryColor.withValues(alpha: 0.12),
              child: Text(
                member.name.isNotEmpty ? member.name[0] : '?',
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: theme.primaryColor, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.name,
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.w700),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (member.phone != null) ...[
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        Flexible(
                          child: Text(
                            FormatHelper.formatPhone(member.phone!),
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.grey500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (businessName != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    Row(
                      children: [
                        Icon(
                          Icons.storefront_outlined,
                          size: ResponsiveHelper.iconSize(context, 11),
                          color: AppColors.grey500,
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 3)),
                        Flexible(
                          child: Text(
                            businessName!,
                            style: ResponsiveHelper.tinyStyle(context,
                                color: AppColors.grey500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: ResponsiveHelper.spacing(context, 5)),
                  if (activePerms.isNotEmpty)
                    Wrap(
                      spacing: ResponsiveHelper.spacing(context, 4),
                      runSpacing: ResponsiveHelper.spacing(context, 3),
                      children: activePerms
                          .map((label) => Container(
                                padding: EdgeInsets.symmetric(
                                  horizontal:
                                      ResponsiveHelper.spacing(context, 7),
                                  vertical:
                                      ResponsiveHelper.spacing(context, 2),
                                ),
                                decoration: BoxDecoration(
                                  color: theme.primaryColor
                                      .withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color: theme.primaryColor
                                          .withValues(alpha: 0.25)),
                                ),
                                child: Text(
                                  label,
                                  style: ResponsiveHelper.tinyStyle(context,
                                          color: theme.primaryColor)
                                      .copyWith(fontWeight: FontWeight.w600),
                                ),
                              ))
                          .toList(),
                    )
                  else
                    Text(
                      '권한 없음',
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey400),
                    ),
                ],
              ),
            ),
            if (canEdit)
              InkWell(
                onTap: () => AppMenuSheet.show(
                  context: context,
                  headerTitle: member.name,
                  headerSubtitle: member.phone != null
                      ? FormatHelper.formatPhone(member.phone!)
                      : null,
                  headerAvatarLetter:
                      member.name.isNotEmpty ? member.name[0] : '?',
                  headerAvatarColor: theme.primaryColor,
                  itemGroups: [
                    [
                      AppMenuSheetItem(
                        icon: Icons.tune,
                        label: '권한 수정',
                        color: theme.primaryColor,
                        onTap: onEdit,
                      ),
                    ],
                    [
                      AppMenuSheetItem(
                        icon: Icons.person_remove_outlined,
                        label: '멤버 제거',
                        color: AppColors.error,
                        isDanger: true,
                        onTap: onRemove,
                      ),
                    ],
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
                  child: Icon(Icons.more_vert,
                      color: AppColors.grey400,
                      size: ResponsiveHelper.iconSize(context, 20)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── 초대 대기 카드 ──────────────────────────────────────────────

class _PendingInvitationCard extends StatelessWidget {
  final MemberInvitationModel invitation;
  final VoidCallback onCancel;

  const _PendingInvitationCard({
    required this.invitation,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(invitation.createdAt);
    final elapsedLabel = elapsed.inHours < 1
        ? '방금 전'
        : elapsed.inHours < 24
            ? '${elapsed.inHours}시간 전'
            : '${elapsed.inDays}일 전';

    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      decoration: BoxDecoration(
        color: AppColors.warningBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: AppColors.warningDark.withValues(alpha: 0.3)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: ResponsiveHelper.spacing(context, 16),
          vertical: ResponsiveHelper.spacing(context, 12),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor:
                  AppColors.warningDark.withValues(alpha: 0.15),
              child: Icon(
                Icons.schedule,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.warningDark,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    invitation.targetName,
                    style: ResponsiveHelper.bodyStyle(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  if (invitation.targetPhone != null)
                    Text(
                      FormatHelper.formatPhone(invitation.targetPhone!),
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.grey500),
                    ),
                  Text(
                    '초대 발송 $elapsedLabel · 3일 내 미수락 시 자동 만료',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.warningDark),
                  ),
                ],
              ),
            ),
            TextButton(
              onPressed: onCancel,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.errorMedium,
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 8),
                ),
              ),
              child: Text('취소',
                  style: ResponsiveHelper.smallStyle(context,
                          color: AppColors.errorMedium)
                      .copyWith(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── 초대 다이얼로그 ──────────────────────────────────────────────

class _InviteDialog extends StatefulWidget {
  final String businessId;
  final String businessName;

  const _InviteDialog({required this.businessId, required this.businessName});

  @override
  State<_InviteDialog> createState() => _InviteDialogState();
}

class _InviteDialogState extends State<_InviteDialog> {
  final _service = MemberService();
  final _phoneCtrl = TextEditingController();
  final _phoneFmt = PhoneNumberFormatter(); // L3: rebuild마다 새 인스턴스 방지
  Map<String, dynamic>? _found;
  bool _searching = false;
  bool _sending = false;
  MemberPermissions _permissions = MemberPermissions.none();

  @override
  void dispose() {
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final phone = _phoneCtrl.text.replaceAll('-', '').trim();
    if (phone.isEmpty) return;
    setState(() {
      _searching = true;
      _found = null;
    });
    try {
      final result = await _service.findUserByPhone(phone);
      if (!mounted) return;
      setState(() => _found = result);
      if (result == null) {
        ToastHelper.showError('해당 전화번호로 가입된 근무자를 찾을 수 없습니다');
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('검색 중 오류가 발생했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _send() async {
    if (_found == null || !_permissions.hasAnyPermission) return;
    setState(() => _sending = true);

    try {
      final userProvider = context.read<UserProvider>();
      final currentUser = userProvider.currentUser;
      if (currentUser == null) {
        ToastHelper.showError('로그인 정보를 찾을 수 없습니다');
        setState(() => _sending = false);
        return;
      }

      final checkResults = await Future.wait([
        _service.isAlreadyMember(widget.businessId, _found!['uid']),
        _service.hasPendingInvitation(widget.businessId, _found!['uid']),
      ]);
      if (!mounted) return;
      if (checkResults[0]) {
        ToastHelper.showError('이미 멤버로 등록된 사용자입니다');
        return; // L1: finally가 _sending=false 처리
      }
      if (checkResults[1]) {
        ToastHelper.showError('이미 초대가 발송된 사용자입니다');
        return; // L1: finally가 _sending=false 처리
      }

      await _service.sendInvitation(
        businessId: widget.businessId,
        businessName: widget.businessName,
        targetUid: _found!['uid'],
        targetName: _found!['name'],
        targetPhone: _found!['phone'],
        invitedBy: currentUser.uid,
        invitedByName: currentUser.name,
        permissions: _permissions,
      );

      if (!mounted) return;
      FocusManager.instance.primaryFocus?.unfocus();
      ToastHelper.showSuccess('${_found!['name']}님에게 초대를 발송했습니다');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('초대 발송 중 오류가 발생했습니다');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSend =
        _found != null && _permissions.hasAnyPermission && !_sending;

    return PopScope(
      canPop: !_sending,
      child: Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── 헤더 ──
              Container(
                padding: EdgeInsets.fromLTRB(
                  ResponsiveHelper.spacing(context, 20),
                  ResponsiveHelper.spacing(context, 18),
                  ResponsiveHelper.spacing(context, 16),
                  ResponsiveHelper.spacing(context, 18),
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.primaryColor,
                      theme.colorScheme.secondary
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(
                          ResponsiveHelper.spacing(context, 8)),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.person_add_outlined,
                          color: Colors.white,
                          size: ResponsiveHelper.iconSize(context, 20)),
                    ),
                    SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('멤버 초대',
                              style: ResponsiveHelper.subtitleStyle(context)
                                  .copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold)),
                          Text(widget.businessName,
                              style: ResponsiveHelper.tinyStyle(context,
                                  color: Colors.white
                                      .withValues(alpha: 0.85))),
                        ],
                      ),
                    ),
                    Material(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        onTap: () {
                          FocusManager.instance.primaryFocus?.unfocus();
                          Navigator.pop(context, false);
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: EdgeInsets.all(
                              ResponsiveHelper.spacing(context, 6)),
                          child: Icon(Icons.close,
                              color: Colors.white,
                              size: ResponsiveHelper.iconSize(context, 18)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // ── 본문 ──
              Container(
                color: AppColors.grey50,
                child: Padding(
                  padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 전화번호 검색
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Padding(
                              padding: EdgeInsets.only(
                                  left: ResponsiveHelper.spacing(context, 14),
                                  right:
                                      ResponsiveHelper.spacing(context, 8)),
                              child: Icon(Icons.phone_outlined,
                                  color: AppColors.grey400,
                                  size:
                                      ResponsiveHelper.iconSize(context, 18)),
                            ),
                            Expanded(
                              child: TextField(
                                controller: _phoneCtrl,
                                keyboardType: TextInputType.phone,
                                inputFormatters: [_phoneFmt],
                                style: ResponsiveHelper.bodyStyle(context),
                                decoration: InputDecoration(
                                  hintText: '010-0000-0000',
                                  hintStyle: ResponsiveHelper.bodyStyle(
                                      context,
                                      color: AppColors.grey400),
                                  border: InputBorder.none,
                                  contentPadding: EdgeInsets.symmetric(
                                      vertical: ResponsiveHelper.spacing(
                                          context, 14)),
                                ),
                                onSubmitted: (_) {
                                  if (!_searching) _search();
                                },
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal:
                                      ResponsiveHelper.spacing(context, 8)),
                              child: Material(
                                color: _searching
                                    ? AppColors.grey200
                                    : theme.primaryColor,
                                borderRadius: BorderRadius.circular(10),
                                child: InkWell(
                                  onTap: _searching ? null : _search,
                                  borderRadius: BorderRadius.circular(10),
                                  child: Padding(
                                    padding: EdgeInsets.all(
                                        ResponsiveHelper.spacing(
                                            context, 10)),
                                    child: _searching
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Colors.white))
                                        : Icon(Icons.search_rounded,
                                            color: Colors.white,
                                            size: ResponsiveHelper.iconSize(
                                                context, 20)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      if (_found == null && !_searching) ...[
                        SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                        Center(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.manage_search_rounded,
                                    size:
                                        ResponsiveHelper.iconSize(context, 44),
                                    color: AppColors.grey300),
                                SizedBox(
                                    height: ResponsiveHelper.spacing(
                                        context, 8)),
                                Text('전화번호를 입력하고 검색하세요',
                                    style: ResponsiveHelper.smallStyle(
                                        context,
                                        color: AppColors.grey400)),
                              ]),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                      ],

                      if (_found != null) ...[
                        SizedBox(
                            height: ResponsiveHelper.spacing(context, 14)),
                        Container(
                          padding: EdgeInsets.all(
                              ResponsiveHelper.spacing(context, 14)),
                          decoration: BoxDecoration(
                            color: AppColors.successBg,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color:
                                    AppColors.success.withValues(alpha: 0.3)),
                          ),
                          child: Row(children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor:
                                  AppColors.success.withValues(alpha: 0.2),
                              child: Text(
                                ((_found!['name'] as String?) ?? '')
                                        .isNotEmpty
                                    ? ((_found!['name'] as String?) ?? '')[0]
                                    : '?',
                                style: ResponsiveHelper.bodyStyle(context)
                                    .copyWith(
                                        color: AppColors.successDark,
                                        fontWeight: FontWeight.bold),
                              ),
                            ),
                            SizedBox(
                                width: ResponsiveHelper.spacing(context, 12)),
                            Expanded(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(_found!['name'],
                                        style:
                                            ResponsiveHelper.bodyStyle(context)
                                                .copyWith(
                                                    fontWeight:
                                                        FontWeight.w700,
                                                    color:
                                                        AppColors.successDark)),
                                    const SizedBox(height: 2),
                                    Text(
                                        FormatHelper.formatPhone(
                                            _found!['phone'] ?? ''),
                                        style: ResponsiveHelper.tinyStyle(
                                                context,
                                                color: AppColors.successDark
                                                    .withValues(alpha: 0.6))),
                                  ]),
                            ),
                            Icon(Icons.verified_rounded,
                                color: AppColors.success,
                                size: ResponsiveHelper.iconSize(context, 22)),
                          ]),
                        ),

                        SizedBox(
                            height: ResponsiveHelper.spacing(context, 18)),

                        Row(children: [
                          Text('권한 설정',
                              style: ResponsiveHelper.bodyStyle(context)
                                  .copyWith(fontWeight: FontWeight.w700)),
                          const Spacer(),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal:
                                  ResponsiveHelper.spacing(context, 8),
                              vertical:
                                  ResponsiveHelper.spacing(context, 3),
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.warningBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('1개 이상 선택',
                                style: ResponsiveHelper.tinyStyle(context,
                                    color: AppColors.warningDark,
                                    fontWeight: FontWeight.w600)),
                          ),
                        ]),
                        SizedBox(
                            height: ResponsiveHelper.spacing(context, 10)),
                        _PermissionToggleList(
                          permissions: _permissions,
                          onChanged: (p) =>
                              setState(() => _permissions = p),
                        ),
                      ],

                      SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                      Container(
                        decoration: BoxDecoration(
                          border: Border(
                              top: BorderSide(color: AppColors.grey100)),
                        ),
                        padding: EdgeInsets.only(
                            top: ResponsiveHelper.spacing(context, 12)),
                        child: Column(children: [
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: canSend ? _send : null,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: theme.primaryColor,
                                foregroundColor: Colors.white,
                                disabledBackgroundColor: AppColors.grey200,
                                disabledForegroundColor: AppColors.grey400,
                                elevation: 0,
                                padding: EdgeInsets.symmetric(
                                    vertical: ResponsiveHelper.spacing(
                                        context, 15)),
                                shape: RoundedRectangleBorder(
                                    borderRadius:
                                        BorderRadius.circular(14)),
                              ),
                              icon: _sending
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white))
                                  : Icon(Icons.send_rounded,
                                      size: ResponsiveHelper.iconSize(
                                          context, 16)),
                              label: Text(
                                _sending ? '발송 중...' : '초대 발송',
                                style: ResponsiveHelper.bodyStyle(context)
                                    .copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              Navigator.pop(context, false);
                            },
                            child: Text('취소',
                                style: ResponsiveHelper.smallStyle(context,
                                    color: AppColors.grey400)),
                          ),
                        ]),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── 권한 토글 리스트 ─────────────────────────────────────────────

class _PermissionToggleList extends StatelessWidget {
  final MemberPermissions permissions;
  final ValueChanged<MemberPermissions> onChanged;

  const _PermissionToggleList(
      {required this.permissions, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = [
      (
        Icons.campaign_outlined,
        '공고 관리',
        '공고 등록·수정·삭제',
        permissions.canManageTo,
        (v) => permissions.copyWith(canManageTo: v),
      ),
      (
        Icons.people_outline,
        '근무자 관리',
        '승인·출퇴근·확정 관리',
        permissions.canManageWorkers,
        (v) => permissions.copyWith(canManageWorkers: v),
      ),
      (
        Icons.payments_outlined,
        '급여 관리',
        '급여 확인·정산',
        permissions.canManageWage,
        (v) => permissions.copyWith(canManageWage: v),
      ),
      (
        Icons.description_outlined,
        '계약서 관리',
        '계약서 작성·템플릿',
        permissions.canManageContract,
        (v) => permissions.copyWith(canManageContract: v),
      ),
      (
        Icons.undo_outlined,
        '이체 취소',
        '잘못 처리된 이체완료 되돌리기',
        permissions.canCancelTransfer,
        (v) => permissions.copyWith(canCancelTransfer: v),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: List.generate(items.length, (index) {
          final (icon, title, subtitle, value, updater) = items[index];
          final isLast = index == items.length - 1;
          return Column(
            children: [
              InkWell(
                onTap: () => onChanged(updater(!value)),
                borderRadius: BorderRadius.vertical(
                  top: index == 0 ? const Radius.circular(12) : Radius.zero,
                  bottom:
                      isLast ? const Radius.circular(12) : Radius.zero,
                ),
                child: Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 14),
                    vertical: ResponsiveHelper.spacing(context, 10),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(
                            ResponsiveHelper.spacing(context, 6)),
                        decoration: BoxDecoration(
                          color: value
                              ? theme.primaryColor.withValues(alpha: 0.1)
                              : AppColors.grey100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon,
                            size: ResponsiveHelper.iconSize(context, 16),
                            color: value
                                ? theme.primaryColor
                                : AppColors.grey400),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: ResponsiveHelper.bodyStyle(context)
                                    .copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: value
                                            ? null
                                            : AppColors.grey500)),
                            Text(subtitle,
                                style: ResponsiveHelper.tinyStyle(context,
                                    color: AppColors.grey400)),
                          ],
                        ),
                      ),
                      Switch(
                        value: value,
                        onChanged: (v) => onChanged(updater(v)),
                        activeThumbColor: theme.primaryColor,
                        activeTrackColor:
                            theme.primaryColor.withValues(alpha: 0.4),
                        materialTapTargetSize:
                            MaterialTapTargetSize.shrinkWrap,
                      ),
                    ],
                  ),
                ),
              ),
              if (!isLast)
                Divider(
                    height: 1,
                    indent: ResponsiveHelper.spacing(context, 14),
                    endIndent: ResponsiveHelper.spacing(context, 14),
                    color: AppColors.grey100),
            ],
          );
        }),
      ),
    );
  }
}

// ─── 권한 수정 바텀시트 ───────────────────────────────────────────

class _PermissionSheet extends StatefulWidget {
  final String memberName;
  final String memberInitial;
  final MemberPermissions current;

  const _PermissionSheet({
    required this.memberName,
    required this.memberInitial,
    required this.current,
  });

  @override
  State<_PermissionSheet> createState() => _PermissionSheetState();
}

class _PermissionSheetState extends State<_PermissionSheet> {
  late MemberPermissions _permissions;

  @override
  void initState() {
    super.initState();
    _permissions = widget.current;
  }

  static const _items = [
    (Icons.campaign_outlined,   '공고 관리',   '공고 등록·수정·삭제'),
    (Icons.people_outline,      '근무자 관리', '승인·출퇴근·확정 관리'),
    (Icons.payments_outlined,   '급여 관리',   '급여 확인·정산'),
    (Icons.description_outlined,'계약서 관리', '계약서 작성·템플릿'),
    (Icons.undo_outlined,       '이체 취소',   '잘못 처리된 이체완료 되돌리기'),
  ];

  bool _getValue(int i) => [
    _permissions.canManageTo,
    _permissions.canManageWorkers,
    _permissions.canManageWage,
    _permissions.canManageContract,
    _permissions.canCancelTransfer,
  ][i];

  MemberPermissions _setValue(int i, bool v) => switch (i) {
    0 => _permissions.copyWith(canManageTo: v),
    1 => _permissions.copyWith(canManageWorkers: v),
    2 => _permissions.copyWith(canManageWage: v),
    3 => _permissions.copyWith(canManageContract: v),
    _ => _permissions.copyWith(canCancelTransfer: v),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSave = _permissions.hasAnyPermission;

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 드래그 핸들
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // 헤더 — 아바타 + 이름
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Container(
                  width: ResponsiveHelper.spacing(context, 48),
                  height: ResponsiveHelper.spacing(context, 48),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      widget.memberInitial,
                      style: ResponsiveHelper.subtitleStyle(context).copyWith(
                        color: theme.primaryColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.memberName,
                        style: ResponsiveHelper.subtitleStyle(context)
                            .copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '권한 수정',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey500),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.grey100),

          // 권한 항목 — 평면 리스트 (외부 카드 없음)
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(_items.length, (i) {
                  final (icon, title, subtitle) = _items[i];
                  final value = _getValue(i);
                  return Column(
                    children: [
                      InkWell(
                        onTap: () =>
                            setState(() => _permissions = _setValue(i, !value)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                width: ResponsiveHelper.spacing(context, 40),
                                height: ResponsiveHelper.spacing(context, 40),
                                decoration: BoxDecoration(
                                  color: value
                                      ? theme.primaryColor.withValues(alpha: 0.1)
                                      : AppColors.grey100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  icon,
                                  size: ResponsiveHelper.iconSize(context, 18),
                                  color: value
                                      ? theme.primaryColor
                                      : AppColors.grey400,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: ResponsiveHelper.bodyStyle(context)
                                          .copyWith(
                                        fontWeight: FontWeight.w600,
                                        color: value
                                            ? AppColors.grey800
                                            : AppColors.grey500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      subtitle,
                                      style: ResponsiveHelper.tinyStyle(context,
                                          color: AppColors.grey400),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: value,
                                onChanged: (v) => setState(
                                    () => _permissions = _setValue(i, v)),
                                activeThumbColor: Colors.white,
                                activeTrackColor: theme.primaryColor,
                                inactiveThumbColor: Colors.white,
                                inactiveTrackColor: AppColors.grey300,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (i < _items.length - 1)
                        const Divider(
                            height: 1,
                            indent: 74,
                            endIndent: 20,
                            color: AppColors.grey100),
                    ],
                  );
                }),
              ),
            ),
          ),

          const Divider(height: 1, color: AppColors.grey100),
          const SizedBox(height: 16),

          // 버튼 영역
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.grey600,
                      side: const BorderSide(color: AppColors.grey300),
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 14)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text('취소',
                        style: ResponsiveHelper.bodyStyle(context)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: canSave
                        ? () => Navigator.pop(context, _permissions)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.grey200,
                      disabledForegroundColor: AppColors.grey400,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 14)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(
                      '저장',
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: canSave ? Colors.white : AppColors.grey400,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
