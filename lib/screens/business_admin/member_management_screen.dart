import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/business_member_model.dart';
import '../../providers/user_provider.dart';
import '../../services/member_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/loading_widget.dart';

class MemberManagementScreen extends StatefulWidget {
  final String businessId;
  final String businessName;

  const MemberManagementScreen({
    super.key,
    required this.businessId,
    required this.businessName,
  });

  @override
  State<MemberManagementScreen> createState() => _MemberManagementScreenState();
}

class _MemberManagementScreenState extends State<MemberManagementScreen> {
  final _service = MemberService();
  List<BusinessMemberModel> _members = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await _service.getMembers(widget.businessId);
      if (!mounted) return;
      setState(() => _members = result);
    } catch (e) {
      if (mounted) ToastHelper.showError('멤버 목록을 불러오지 못했습니다');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _invite() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => _InviteDialog(
        businessId: widget.businessId,
        businessName: widget.businessName,
      ),
    );
    if (result == true && mounted) _load();
  }

  Future<void> _editPermissions(BusinessMemberModel member) async {
    final result = await showDialog<MemberPermissions>(
      context: context,
      builder: (_) => _PermissionDialog(
        memberName: member.name,
        current: member.permissions,
      ),
    );
    if (result == null || !mounted) return;
    try {
      await _service.updatePermissions(
        businessId: widget.businessId,
        uid: member.uid,
        permissions: result,
      );
      if (!mounted) return;
      ToastHelper.showSuccess('권한이 업데이트되었습니다');
      _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('권한 업데이트에 실패했습니다');
    }
  }

  Future<void> _remove(BusinessMemberModel member) async {
    final ok = await DialogHelper.showDeleteConfirm(
      context,
      itemName: '"${member.name}" 멤버',
    );
    if (ok != true || !mounted) return;
    try {
      await _service.removeMember(
        businessId: widget.businessId,
        uid: member.uid,
      );
      if (!mounted) return;
      ToastHelper.showSuccess('멤버가 제거되었습니다');
      _load();
    } catch (e) {
      if (mounted) ToastHelper.showError('멤버 제거에 실패했습니다');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GradientScaffold(
      title: '멤버 관리',
      onRefresh: _load,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _invite,
        backgroundColor: theme.primaryColor,
        icon: const Icon(Icons.person_add, color: Colors.white),
        label: Text('멤버 초대',
            style: ResponsiveHelper.smallStyle(context, color: Colors.white)),
      ),
      body: _loading
          ? const LoadingWidget()
          : _members.isEmpty
              ? _buildEmpty(context)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: EdgeInsets.fromLTRB(
                      ResponsiveHelper.spacing(context, 16),
                      ResponsiveHelper.spacing(context, 16),
                      ResponsiveHelper.spacing(context, 16),
                      ResponsiveHelper.spacing(context, 100),
                    ),
                    itemCount: _members.length,
                    itemBuilder: (_, i) => _MemberCard(
                      member: _members[i],
                      onEdit: () => _editPermissions(_members[i]),
                      onRemove: () => _remove(_members[i]),
                    ),
                  ),
                ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.group_outlined,
      title: '등록된 멤버가 없습니다',
      subtitle: '멤버 초대 버튼으로 근무자를 관리자로 초대하세요.',
    );
  }
}

// ─── 멤버 카드 ─────────────────────────────────────────────────

class _MemberCard extends StatelessWidget {
  final BusinessMemberModel member;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _MemberCard({
    required this.member,
    required this.onEdit,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: Colors.white,
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
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: theme.primaryColor.withValues(alpha: 0.12),
                  child: Text(
                    member.name.isNotEmpty ? member.name[0] : '?',
                    style: ResponsiveHelper.subtitleStyle(context)
                        .copyWith(color: theme.primaryColor, fontWeight: FontWeight.bold),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        member.name,
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (member.phone != null)
                        Text(
                          member.phone!,
                          style: ResponsiveHelper.tinyStyle(context,
                              color: AppColors.grey500),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  icon: Icon(Icons.person_remove_outlined,
                      color: AppColors.errorMedium,
                      size: ResponsiveHelper.iconSize(context, 20)),
                  tooltip: '멤버 제거',
                ),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            // 권한 태그
            Wrap(
              spacing: ResponsiveHelper.spacing(context, 6),
              runSpacing: ResponsiveHelper.spacing(context, 4),
              children: [
                _buildPermTag(context, '공고', member.permissions.canManageTo, theme),
                _buildPermTag(context, '근무자', member.permissions.canManageWorkers, theme),
                _buildPermTag(context, '급여', member.permissions.canManageWage, theme),
                _buildPermTag(context, '계약서', member.permissions.canManageContract, theme),
              ],
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onEdit,
                icon: Icon(Icons.tune,
                    size: ResponsiveHelper.iconSize(context, 16)),
                label: Text('권한 수정',
                    style: ResponsiveHelper.smallStyle(context)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.primaryColor,
                  side: BorderSide(color: theme.primaryColor.withValues(alpha: 0.4)),
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 10)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPermTag(BuildContext context, String label, bool active, ThemeData theme) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 8), vertical: ResponsiveHelper.spacing(context, 3)),
      decoration: BoxDecoration(
        color: active
            ? theme.primaryColor.withValues(alpha: 0.1)
            : AppColors.grey100,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: active
              ? theme.primaryColor.withValues(alpha: 0.3)
              : AppColors.grey200,
        ),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.tinyStyle(
          context,
          color: active ? theme.primaryColor : AppColors.grey400,
        ).copyWith(fontWeight: FontWeight.w600),
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
    // 하이픈 제거 후 DB 쿼리 (DB에는 숫자만 저장됨)
    final phone = _phoneCtrl.text.replaceAll('-', '').trim();
    if (phone.isEmpty) return;
    setState(() {
      _searching = true;
      _found = null;
    });
    final result = await _service.findUserByPhone(phone);
    if (!mounted) return;
    setState(() {
      _searching = false;
      _found = result;
    });
    if (result == null) {
      ToastHelper.showError('해당 전화번호로 가입된 근무자를 찾을 수 없습니다');
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

      // 이미 멤버인지 확인
      final alreadyMember =
          await _service.isAlreadyMember(widget.businessId, _found!['uid']);
      if (!mounted) return;
      if (alreadyMember) {
        ToastHelper.showError('이미 멤버로 등록된 사용자입니다');
        setState(() => _sending = false); // early return 전 상태 복원
        return;
      }

      // 이미 pending 초대 있는지 확인
      final hasPending = await _service.hasPendingInvitation(
          widget.businessId, _found!['uid']);
      if (!mounted) return;
      if (hasPending) {
        ToastHelper.showError('이미 초대가 발송된 사용자입니다');
        setState(() => _sending = false); // early return 전 상태 복원
        return;
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
    final canSend = _found != null && _permissions.hasAnyPermission && !_sending;

    return PopScope(
      canPop: !_sending,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── 헤더 — 앱 디자인 언어에 맞춘 그라데이션 ──
            Container(
              padding: EdgeInsets.fromLTRB(
                ResponsiveHelper.spacing(context, 20),
                ResponsiveHelper.spacing(context, 18),
                ResponsiveHelper.spacing(context, 16),
                ResponsiveHelper.spacing(context, 18),
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [theme.primaryColor, theme.colorScheme.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 8)),
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
                                .copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
                        Text('전화번호로 근무자를 검색하세요',
                            style: ResponsiveHelper.tinyStyle(context,
                                color: Colors.white.withValues(alpha: 0.8))),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: () => Navigator.pop(context, false),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 6)),
                        child: Icon(Icons.close, color: Colors.white,
                            size: ResponsiveHelper.iconSize(context, 18)),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── 본문 — grey50 배경으로 카드 깊이 표현 ──
            Container(
              color: AppColors.grey50,
            child: Padding(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 전화번호 검색 — 흰 카드로 띄움
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
                              right: ResponsiveHelper.spacing(context, 8)),
                          child: Icon(Icons.phone_outlined,
                              color: AppColors.grey400,
                              size: ResponsiveHelper.iconSize(context, 18)),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _phoneCtrl,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [PhoneNumberFormatter()],
                            style: ResponsiveHelper.bodyStyle(context),
                            decoration: InputDecoration(
                              hintText: '010-0000-0000',
                              hintStyle: ResponsiveHelper.bodyStyle(context,
                                  color: AppColors.grey400),
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                  vertical: ResponsiveHelper.spacing(context, 14)),
                            ),
                            onSubmitted: (_) { if (!_searching) _search(); },
                          ),
                        ),
                        // 검색 아이콘 버튼 — 필드와 자연스럽게 통합
                        Padding(
                          padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 8)),
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
                                    ResponsiveHelper.spacing(context, 10)),
                                child: _searching
                                    ? SizedBox(
                                        width: 18, height: 18,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2, color: Colors.white))
                                    : Icon(Icons.search_rounded,
                                        color: Colors.white,
                                        size: ResponsiveHelper.iconSize(context, 20)),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 미검색 안내
                  if (_found == null && !_searching) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                    Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.manage_search_rounded,
                            size: ResponsiveHelper.iconSize(context, 44),
                            color: AppColors.grey300),
                        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                        Text('전화번호를 입력하고 검색하세요',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.grey400)),
                      ]),
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                  ],

                  // 검색 결과
                  if (_found != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 14)),
                    Container(
                      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
                      decoration: BoxDecoration(
                        color: AppColors.successBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: AppColors.success.withValues(alpha: 0.2),
                          child: Text(
                            (_found!['name'] as String).isNotEmpty
                                ? (_found!['name'] as String)[0]
                                : '?',
                            style: ResponsiveHelper.bodyStyle(context).copyWith(
                                color: AppColors.successDark,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(_found!['name'],
                                style: ResponsiveHelper.bodyStyle(context).copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.successDark)),
                            const SizedBox(height: 2),
                            Text(FormatHelper.formatPhone(_found!['phone'] ?? ''),
                                style: ResponsiveHelper.tinyStyle(context,
                                    color: AppColors.successDark.withValues(alpha: 0.6))),
                          ]),
                        ),
                        Icon(Icons.verified_rounded,
                            color: AppColors.success,
                            size: ResponsiveHelper.iconSize(context, 22)),
                      ]),
                    ),

                    SizedBox(height: ResponsiveHelper.spacing(context, 18)),

                    // 권한 설정
                    Row(children: [
                      Text('권한 설정',
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 8),
                          vertical: ResponsiveHelper.spacing(context, 3),
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
                    SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                    _PermissionToggleList(
                      permissions: _permissions,
                      onChanged: (p) => setState(() => _permissions = p),
                    ),
                  ],

                  SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                  // 액션 버튼 — 전체 폭 + 구분선 위 취소
                  Container(
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.grey100)),
                    ),
                    padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 12)),
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
                              vertical: ResponsiveHelper.spacing(context, 15)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: _sending
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white))
                            : Icon(Icons.send_rounded,
                                size: ResponsiveHelper.iconSize(context, 16)),
                        label: Text(
                          _sending ? '발송 중...' : '초대 발송',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                      ),  // SizedBox
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text('취소',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.grey400)),
                      ),
                    ]),  // Column
                  ),  // Container(border)
                ],
              ),
            ), // Padding
            ), // Container(grey50)
          ],
        ),
      ),
    ),   // Dialog
    );   // PopScope
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
                  bottom: isLast ? const Radius.circular(12) : Radius.zero,
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
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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

// ─── 권한 수정 다이얼로그 ─────────────────────────────────────────

class _PermissionDialog extends StatefulWidget {
  final String memberName;
  final MemberPermissions current;

  const _PermissionDialog(
      {required this.memberName, required this.current});

  @override
  State<_PermissionDialog> createState() => _PermissionDialogState();
}

class _PermissionDialogState extends State<_PermissionDialog> {
  late MemberPermissions _permissions;

  @override
  void initState() {
    super.initState();
    _permissions = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${widget.memberName}님 권한 수정',
                style: ResponsiveHelper.subtitleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold)),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text('최소 1개 이상 선택해야 저장할 수 있습니다',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey400)),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Flexible(
              child: SingleChildScrollView(
                child: _PermissionToggleList(
                  permissions: _permissions,
                  onChanged: (p) => setState(() => _permissions = p),
                ),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.grey600,
                      side: const BorderSide(color: AppColors.grey300),
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 12)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('취소',
                        style: ResponsiveHelper.bodyStyle(context)),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _permissions.hasAnyPermission
                        ? () => Navigator.pop(context, _permissions)
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: AppColors.grey200,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 12)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                    child: Text('저장',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
