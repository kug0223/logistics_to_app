import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/loading_state_mixin.dart';
import '../../widgets/dialogs/styled_dialog.dart';

/// 슈퍼관리자 전용 — 외국인 근로자 가입 승인/거절 화면
class ForeignWorkerApprovalScreen extends StatefulWidget {
  const ForeignWorkerApprovalScreen({super.key});

  @override
  State<ForeignWorkerApprovalScreen> createState() =>
      _ForeignWorkerApprovalScreenState();
}

class _ForeignWorkerApprovalScreenState
    extends State<ForeignWorkerApprovalScreen> with LoadingStateMixin {
  final _fn = FirebaseFunctions.instanceFor(region: 'asia-northeast3');

  List<UserModel> _pending = [];
  String _statusFilter = 'pending'; // 'pending' | 'active' | 'rejected'
  bool _isProcessing = false;

  static const _tabs = [
    ('pending', '대기 중'),
    ('active', '승인됨'),
    ('rejected', '거절됨'),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<UserProvider>().isSuperAdmin) {
        Navigator.pop(context);
        return;
      }
      _loadUsers();
    });
  }

  Future<void> _loadUsers() async {
    setLoading(true);
    try {
      // Firestore 인덱스 필요: users → role(ASC) + createdAt(DESC)
      // Firebase Console에서 복합 인덱스가 없으면 첫 실행 시 인덱스 생성 링크가 에러에 포함됨.
      // foreignIdNumber isNull 조건은 단독 whereIn 쿼리와 복합 불가 → 클라이언트 필터로 분리.
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .where('role', isEqualTo: 'USER')
          .where('accountStatus', whereIn: ['pending', 'active', 'rejected'])
          .orderBy('createdAt', descending: true)
          .limit(300)
          .get();

      if (!mounted) return;
      setState(() {
        _pending = snap.docs
            .map((d) => UserModel.tryFromMap(d.data(), d.id))
            .whereType<UserModel>()
            .where((u) => u.foreignIdNumber != null) // 외국인만
            .toList();
      });
      setLoading(false);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('목록 불러오기 실패: $e');
      setLoading(false);
    }
  }

  List<UserModel> get _filtered =>
      _pending.where((u) => u.accountStatus == _statusFilter).toList();

  Future<void> _approve(UserModel user) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final confirmed = await _showConfirmDialog(
        title: '승인 확인',
        message: '${user.name}님의 가입을 승인하시겠습니까?\n승인 후 앱 사용이 가능해집니다.',
        confirmLabel: '승인',
        confirmColor: AppColors.success,
      );
      if (!confirmed || !mounted) return;

      await _fn.httpsCallable('approveForeignWorker').call({'userId': user.uid});
      if (!mounted) return;
      ToastHelper.showSuccess('${user.name}님이 승인되었습니다');
      await _loadUsers();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ToastHelper.showError(e.message ?? '승인에 실패했습니다');
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('오류가 발생했습니다. 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _reject(UserModel user) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final reason = await _showRejectDialog(user.name);
      if (reason == null || !mounted) return;

      await _fn.httpsCallable('rejectForeignWorker').call({
        'userId': user.uid,
        'reason': reason,
      });
      if (!mounted) return;
      ToastHelper.showSuccess('${user.name}님이 거절되었습니다');
      await _loadUsers();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ToastHelper.showError(e.message ?? '거절 처리에 실패했습니다');
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('오류가 발생했습니다. 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _resetPassword(UserModel user) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      final confirmed = await _showConfirmDialog(
        title: '비밀번호 초기화',
        message: '${user.name}님의 비밀번호를 임시 비밀번호로 초기화합니다.\n초기화 후 임시 비밀번호를 해당 근무자에게 전달해주세요.',
        confirmLabel: '초기화',
        confirmColor: AppColors.warning,
      );
      if (!confirmed || !mounted) return;
      final result = await _fn.httpsCallable('adminResetForeignPassword').call({'userId': user.uid});
      if (!mounted) return;
      final tempPassword = result.data['tempPassword'] as String?;
      if (tempPassword != null) await _showTempPasswordDialog(user.name, tempPassword);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      ToastHelper.showError(e.message ?? '비밀번호 초기화에 실패했습니다');
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('오류가 발생했습니다. 다시 시도해주세요');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _showTempPasswordDialog(String name, String tempPassword) async {
    await showDialog<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => AlertDialog(
        title: const Text('임시 비밀번호 발급'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$name님의 임시 비밀번호:'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: AppColors.grey100,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.grey300),
              ),
              child: SelectableText(
                tempPassword,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              '이 비밀번호를 해당 근무자에게 전달해주세요.\n로그인 후 반드시 비밀번호를 변경하도록 안내해주세요.',
              style: ResponsiveHelper.smallStyle(ctx).copyWith(color: AppColors.grey600),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  // 승인 확인 다이얼로그 — true: 확인, false: 취소
  Future<bool> _showConfirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: confirmColor,
              foregroundColor: Colors.white,
            ),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  // 거절 사유 입력 다이얼로그 — null: 취소
  Future<String?> _showRejectDialog(String name) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _RejectReasonDialog(name: name),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GradientScaffold(
      title: '외국인 근로자 가입 승인',
      onRefresh: _loadUsers,
      body: Column(
        children: [
          _buildTabBar(),
          Expanded(
            child: isLoading
                ? const LoadingWidget(message: '목록을 불러오는 중...')
                : _filtered.isEmpty
                    ? AppEmptyState(
                        icon: Icons.people_outline,
                        title: _statusFilter == 'pending'
                            ? '대기 중인 신청이 없습니다'
                            : _statusFilter == 'active'
                                ? '승인된 사용자가 없습니다'
                                : '거절된 사용자가 없습니다',
                        subtitle: _statusFilter == 'pending'
                            ? '외국인 근로자가 가입하면 여기 표시됩니다'
                            : '',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) => _buildUserCard(_filtered[i]),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final pendingCount = _pending.where((u) => u.accountStatus == 'pending').length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: _tabs.map((tab) {
          final (value, label) = tab;
          final isSelected = _statusFilter == value;
          final count = _pending.where((u) => u.accountStatus == value).length;
          final showBadge = value == 'pending' && pendingCount > 0;

          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _statusFilter = value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? Theme.of(context).primaryColor : AppColors.grey100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      label,
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: isSelected ? Colors.white : AppColors.grey600,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                      ),
                    ),
                    if (count > 0) ...[
                      const SizedBox(width: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: showBadge
                              ? AppColors.error
                              : (isSelected ? Colors.white.withValues(alpha: 0.3) : AppColors.grey300),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$count',
                          style: ResponsiveHelper.smallStyle(context).copyWith(
                            color: showBadge ? Colors.white : (isSelected ? Colors.white : AppColors.grey600),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUserCard(UserModel user) {
    final createdAt = user.createdAt;
    final dateStr = createdAt != null
        ? '${createdAt.year}.${createdAt.month.toString().padLeft(2, '0')}.${createdAt.day.toString().padLeft(2, '0')}'
        : '날짜 미상';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 이름 + 상태 뱃지
            Row(
              children: [
                Expanded(
                  child: Text(
                    user.name,
                    style: ResponsiveHelper.subtitleStyle(context)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                _buildStatusBadge(user.accountStatus),
              ],
            ),
            const SizedBox(height: 8),

            // 기본 정보
            _infoRow(Icons.account_circle_outlined, '아이디', user.username),
            _infoRow(Icons.phone_outlined, '전화번호', user.phone ?? '-'),
            _infoRow(Icons.calendar_today_outlined, '가입일', dateStr),
            if (user.businessId != null)
              _infoRow(Icons.business_outlined, '사업체', user.businessId!),

            // 거절 사유 표시 (rejected 상태)
            if (user.isRejected && user.rejectionReason != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.errorBg,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline, color: AppColors.error, size: 14),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '거절 사유: ${user.rejectionReason}',
                        style: ResponsiveHelper.smallStyle(context)
                            .copyWith(color: AppColors.errorDark),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 신분증 이미지 링크
            if (user.idCardImageUrl != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () async => _showIdCardImage(user),
                child: Row(
                  children: [
                    Icon(Icons.image_outlined, size: 16, color: Theme.of(context).primaryColor),
                    const SizedBox(width: 6),
                    Text(
                      '신분증 이미지 보기',
                      style: ResponsiveHelper.smallStyle(context).copyWith(
                        color: Theme.of(context).primaryColor,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 비밀번호 초기화 버튼 (active 상태 외국인 전용 — ISSUE-03)
            if (user.accountStatus == 'active') ...[
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _resetPassword(user),
                  icon: const Icon(Icons.lock_reset, size: 18),
                  label: const Text('비밀번호 초기화'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.warning,
                    side: const BorderSide(color: AppColors.warning),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],

            // 승인/거절 버튼 (pending 상태만)
            if (user.isPending) ...[
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _reject(user),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.error,
                        side: const BorderSide(color: AppColors.error),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text('거절'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: () => _approve(user),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.success,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                      ),
                      child: const Text('승인', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String status) {
    final (label, bg, fg) = switch (status) {
      'pending' => ('대기 중', AppColors.warningBg, AppColors.warning),
      'active' => ('승인됨', AppColors.successBg, AppColors.successDark),
      'rejected' => ('거절됨', AppColors.errorBg, AppColors.error),
      _ => ('알 수 없음', AppColors.grey100, AppColors.grey500),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.smallStyle(context).copyWith(
          color: fg,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppColors.grey400),
          const SizedBox(width: 6),
          SizedBox(
            width: 56,
            child: Text(
              label,
              style: ResponsiveHelper.smallStyle(context)
                  .copyWith(color: AppColors.grey500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: ResponsiveHelper.smallStyle(context)
                  .copyWith(color: AppColors.grey800),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showIdCardImage(UserModel user) async {
    // ID-1 보안: CF callableGetIdCardSignedUrl 경유로 1시간 만료 Signed URL 발급
    // SUPER_ADMIN은 CF 내부에서 role 확인 후 무조건 허용
    // 감사 로그 병렬 처리 — 실패 시 UX 차단 없이 콘솔 기록만
    final viewerId = FirebaseAuth.instance.currentUser?.uid ?? '';
    String? signedUrl;

    try {
      final results = await Future.wait([
        // 감사 로그
        FirebaseFirestore.instance.collection('id_card_copy_logs').add({
          'viewerId': viewerId,
          'targetUserId': user.uid,
          'businessId': '',
          'action': 'view_id_card_image',
          'timestamp': FieldValue.serverTimestamp(),
        }),
        // Signed URL 발급
        _fn.httpsCallable('callableGetIdCardSignedUrl').call<Map<String, dynamic>>(
          {'targetUserId': user.uid},
        ),
      ]);
      final fnResult = results[1] as HttpsCallableResult<Map<String, dynamic>>;
      signedUrl = fnResult.data['signedUrl'] as String?;
    } catch (e) {
      debugPrint('⚠️ [_showIdCardImage] Signed URL 발급 실패: $e');
      if (mounted) ToastHelper.showError('신분증 이미지 로드 실패');
      return;
    }

    if (!mounted || signedUrl == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${user.name}님 신분증',
                style: ResponsiveHelper.subtitleStyle(ctx)
                    .copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
              child: Image.network(
                signedUrl!,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const SizedBox(
                        height: 200,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                errorBuilder: (_, __, ___) => const SizedBox(
                  height: 200,
                  child: Center(
                    child: Text('이미지를 불러올 수 없습니다',
                        style: TextStyle(color: AppColors.grey500)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('닫기'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

// ── 거절 사유 입력 다이얼로그 ─────────────────────────────────────────
class _RejectReasonDialog extends StatefulWidget {
  final String name;

  const _RejectReasonDialog({required this.name});

  @override
  State<_RejectReasonDialog> createState() => _RejectReasonDialogState();
}

class _RejectReasonDialogState extends State<_RejectReasonDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StyledDialog(
      title: '${widget.name}님 거절',
      subtitle: '거절 사유는 해당 사용자에게 전달됩니다',
      icon: Icons.cancel_outlined,
      headerColor: AppColors.error,
      content: StyledDialogTextField(
        controller: _controller,
        labelText: '거절 사유',
        hintText: '예: 제출 서류 미비, 외국인등록번호 불일치 등',
        prefixIcon: Icons.notes_outlined,
        maxLines: 3,
        maxLength: 500,
        autofocus: true,
      ),
      actions: [
        StyledDialogButton.cancel(onPressed: () => Navigator.pop(context)),
        StyledDialogButton.danger(
          text: '거절',
          onPressed: () {
            if (_controller.text.trim().isEmpty) return;
            Navigator.pop(context, _controller.text.trim());
          },
        ),
      ],
    );
  }
}
