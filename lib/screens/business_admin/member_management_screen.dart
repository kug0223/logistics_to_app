import 'dart:async';

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
import '../../utils/navigation_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_menu_sheet.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/first_line_icon.dart';
import '../../widgets/common/keep_words_text.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/notification_badge.dart';
import '../common/notification_screen.dart';
import 'member_management_reads.dart';

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
  const MemberManagementScreen({super.key, this.reads});

  /// [DU401] 읽기 경계(관측 seam). production 은 null — 아래 기존 서비스 호출 그대로.
  final MemberManagementReads? reads;

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

  /// [impl_27b · L48 같은 꼴] 전체 읽기 중에 들어온 다시 읽기 요청(권한 변경·초대 뒤) — 버리지 않고 끝난 뒤 한 번 더.
  ///   예전에는 진행 중이면 return(전체)·건너뜀(사업장 하나) 해, 처리 **전에** 출발한 읽기가 앉았다.
  bool _reloadAgain = false;

  /// [impl_27b] 사업장별 다시 읽기 차례 — 같은 사업장의 두 다시 읽기 중 늦게 끝난 옛 것이 새 것을 덮지 않게.
  final Map<String, int> _sectionGen = {};
  bool _isProcessing = false;
  bool _isSubAdmin = false;
  // [ERROR-AS-EMPTY] fetch 실패 여부 — false=초기/성공, true=오류
  // _sections == [] 와 조합해 "멤버 없음" vs "로드 실패" 구분 (UNKNOWN != ZERO)
  bool _hasError = false;
  // [H-2 E] 화면이 남는 새로고침 실패 — overlay 토스트 대신 화면 안 결과 띠 하나(목록 위 N2′ · 성공 EMPTY 부제 아래 N3).
  //   원문 · 오류 의미색/아이콘 · 4s · 재실패 교체 · 성공 로드/이탈 시 정리. 첫/재시도 실패의 오류 본문 정책은 그대로다.
  String? _refreshError;
  Timer? _refreshErrorTimer;

  void _showRefreshError(String message) {
    _refreshErrorTimer?.cancel();
    setState(() => _refreshError = message);
    _refreshErrorTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _refreshError = null);
    });
  }

  // [판정51] 옅은 의미 바탕 + 진한 글 · 아이콘(원문 label 1) — Standards §12.2 넓은 면은 진한 의미색으로 채우지 않는다. 본문 안에 놓여 다른 내용을 덮지 않는다.
  //   errorDark / errorBg 5.80:1. 반경 · 패딩 · 아이콘 · 간격 · 글 · 줄바꿈은 그대로(테두리 추가 0).
  Widget _refreshErrorBand(BuildContext context, String message) {
    const style = TextStyle(color: AppColors.errorDark, fontSize: 14, fontWeight: FontWeight.w500);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: AppColors.errorBg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const FirstLineIcon(Icons.error_outline, size: 20, color: AppColors.errorDark, textStyle: style),
          const SizedBox(width: 12),
          Expanded(child: KeepWordsText(message, style: style)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _refreshErrorTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // [AUDIT.2-L001] screen-level guard — Settings 메뉴 외 직접 진입 경로 방어 (OWNER-only 화면)
      final up = context.read<UserProvider>();
      if (!(up.currentUser?.isBusinessAdmin == true)) {
        Navigator.of(context).pop();
        return;
      }
      _load();
    });
  }

  Future<void> _load() async {
    if (_loading) {
      _reloadAgain = true;
      return;
    }
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
      final businesses = await (widget.reads?.businessesByIds ?? _firestoreService.getBusinessesByIds)(bizIds); // [DU401] null = 기존 관대한 조회 그대로
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
            (widget.reads?.members ?? _service.getMembers)(id), // [DU401] null = 기존 그대로
            isSubAdmin
                ? Future.value(<MemberInvitationModel>[])
                : (widget.reads?.sentPendingInvitations ?? _service.getSentPendingInvitations)(id), // [DU401] null = 기존 CF 읽기 그대로
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
      if (_reloadAgain) {
        // [impl_27b] 이 결과는 다시 읽기 요청보다 먼저 출발했다 — 앉히지 않고 한 번 더 읽는다(로딩 유지).
        _reloadAgain = false;
        _loading = false;
        unawaited(_load());
        return;
      }
      _refreshErrorTimer?.cancel(); // [H-2 E] 성공 로드면 남은 결과 띠를 지운다
      setState(() { _sections = sectionResults; _loading = false; _hasError = false; _refreshError = null; });
    } catch (e) {
      if (mounted) {
        // [DU407 후보] 오류 본문이 같은 사실을 말하는 첫/재시도 로드 실패(_sections 비어 있음)에는 토스트를 겹쳐 띄우지 않는다.
        //   오류 본문 없이 성공 섹션 화면(비어 있지 않은 목록 · 성공 EMPTY)이 남는 새로고침 실패만 토스트로 알린다.
        //   [H-2 E] 화면이 남는 새로고침 실패는 overlay 토스트 대신 화면 안 결과 띠로 같은 문장을 보인다(FAB · 멤버 · 초대 가림 0).
        if (_sections.isNotEmpty) _showRefreshError('멤버 목록을 불러오지 못했어요'); // [DU406 후보] 해요체(오류 본문과 같은 문장)
        setState(() { _loading = false; _hasError = true; });
      }
    }
  }

  Future<void> _cancelInvitation(MemberInvitationModel invitation) async {
    if (_isProcessing) return;
    // [P12 · LATE-LOCK] 첫 await(확인 창) 전에 잠근다 — 창이 뜨기 전 연타로 취소가 두 번 나가지 않게. 닫으면 finally 가 푼다.
    setState(() => _isProcessing = true);
    try {
    // [판정52 §6 · 54 §5-4 · DU417] 초대 취소 확인 — 공용 삭제 결합 문구('초대을(를) 삭제') 대신 이 업무의 말(제목 · 최종 '초대 취소' · 닫기 '닫기').
    //   위험 확인창 형식 · 최종 위험색 · ok 이후 writer 는 그대로. 공용 showDeleteConfirm 은 바꾸지 않는다.
    final ok = await DialogHelper.showDangerConfirm(
      context,
      title: '초대 취소',
      message: '${invitation.targetName}님에게 보낸 초대를 취소하시겠습니까?\n\n취소하면 상대방이 더 이상 수락할 수 없습니다.',
      confirmText: '초대 취소',
      cancelText: '닫기',
    );
    if (ok != true || !mounted) return;
      await _service.cancelInvitation(invitation);
      if (!mounted) return;
      ToastHelper.showSuccess('초대를 취소했습니다');
      // [PERF-L52] 바뀐 것은 그 사업장의 초대 목록뿐이다 — 그 사업장만 다시 읽는다.
      unawaited(_reloadSection(invitation.businessId));
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
    // [PERF-L52] 초대가 바꾼 것은 그 사업장의 대기 초대뿐이다 — 전 사업장(이름 + 멤버 + 초대)을 다시 읽지 않는다.
    if (result == true && mounted) unawaited(_reloadSection(businessId));
  }

  /// [PERF-L52] 한 사업장의 멤버 + 대기 초대만 다시 읽어 그 섹션을 바꾼다.
  ///   전체 로드가 진행 중이면 그것이 이 사업장도 읽으므로 건너뛴다. 섹션이 아직 없으면(첫 로드 전 · 오류 뒤) 전체를 읽는다.
  ///   실패하면 이전 섹션을 두고 화면 안 결과 띠로 알린다(전체 로드의 새로고침 실패와 같은 표현).
  Future<void> _reloadSection(String businessId) async {
    if (_loading) {
      _reloadAgain = true; // [impl_27b] 진행 중인 전체 읽기는 이 처리보다 먼저 출발했다 — 끝난 뒤 한 번 더
      return;
    }
    final idx = _sections.indexWhere((s) => s.id == businessId);
    if (idx < 0) {
      await _load();
      return;
    }
    final g = (_sectionGen[businessId] ?? 0) + 1;
    _sectionGen[businessId] = g;
    try {
      final pair = await Future.wait([
        (widget.reads?.members ?? _service.getMembers)(businessId),
        _isSubAdmin
            ? Future.value(<MemberInvitationModel>[])
            : (widget.reads?.sentPendingInvitations ?? _service.getSentPendingInvitations)(businessId),
      ]);
      if (!mounted || _loading || _sectionGen[businessId] != g) return;
      final i = _sections.indexWhere((s) => s.id == businessId);
      if (i < 0) return;
      final old = _sections[i];
      setState(() {
        _sections = [
          for (var k = 0; k < _sections.length; k++)
            k == i
                ? _BizSection(
                    id: old.id,
                    name: old.name,
                    members: pair[0] as List<BusinessMemberModel>,
                    pendingInvitations: pair[1] as List<MemberInvitationModel>,
                  )
                : _sections[k],
        ];
      });
    } catch (e) {
      debugPrint('⚠️ 사업장 멤버 다시 읽기 실패: $e');
      if (mounted) _showRefreshError('멤버 목록을 불러오지 못했어요');
    }
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
      // [판정54 §5-4 · DU417] 멤버 제거 확인 — 공용 삭제 결합 문구('멤버을(를) 삭제') 대신 실제 업무 '제거'(결과 토스트 '멤버가 제거되었습니다' 와 같은 동사).
      //   위험 확인창 형식 · 최종 위험색 · ok 이후 writer 는 그대로. 공용 showDeleteConfirm 은 바꾸지 않는다.
      final ok = await DialogHelper.showDangerConfirm(
        context,
        title: '멤버 제거',
        message: '${member.name}님을 멤버에서 제거하시겠습니까?',
        confirmText: '멤버 제거',
        cancelText: '닫기',
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
    return AppPageScaffold(
      title: '팀원 관리', // [DU406 후보] 실제 진입 이름(설정 '팀원 관리')에 맞춤 — 멤버 도메인명 · 서버 필드 · 다른 caller 무변경
      actions: [
        // GradientScaffold.onRefresh 대응 — empty 상태에서도 수동 새로고침 가능하도록 유지
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          color: AppColors.textSecondary,
          onPressed: _load,
          tooltip: '새로고침',
        ),
        IconButton(
          icon: const Icon(Icons.home_outlined),
          color: AppColors.textSecondary,
          onPressed: () => NavigationHelper.goHome(context),
          tooltip: '홈',
        ),
        NotificationBadge(
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined),
            color: AppColors.textSecondary,
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
            tooltip: '알림',
          ),
        ),
      ],
      // [S024 초대 · 감사48 (가)] 떠 있는 FAB 를 두지 않는다 — 단일 사업장 목록은 사업장 머리 옆 '+ 멤버 초대' 글자 행동(_buildSingleBizHeader),
      //   정상 단일 빈 화면은 내용 안 공용 주 버튼(_buildEmpty). SubAdmin 무초대 · 다중 사업장 머리 '초대' 는 그대로다.
      // [H-2 E N2′] 본문 트리는 늘 Column[결과 띠?, Expanded(기존 본문)] — 띠가 들고 나도 목록이 다시 붙지 않는다(스크롤 유지).
      body: Column(
        children: [
          if (_refreshError != null && !_loading && _sections.isNotEmpty && !isEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(ResponsiveHelper.spacing(context, 16), ResponsiveHelper.spacing(context, 8), ResponsiveHelper.spacing(context, 16), 0),
              child: _refreshErrorBand(context, _refreshError!),
            ),
          Expanded(
            child: _loading
          ? const LoadingWidget()
          : _sections.isEmpty || isEmpty
              ? _buildEmpty(context)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: Builder(builder: (context) {
                    final items = [
                      for (final s in _sections) ..._buildSection(context, s),
                    ];
                    // AppPageScaffold는 body에 하단 SafeArea를 적용하지 않는다.
                    // GradientScaffold 내장 SafeArea 제거분을 보상하기 위해
                    // listPadding의 bottom에 기기 하단 인셋을 추가한다.
                    final lp = ResponsiveHelper.listPadding(context);
                    // [S024 초대] FAB 를 없애 FAB 전용 말단 여백(+72)도 없앤다 — 기본 목록 padding · 하단 inset 은 그대로.
                    // [H-2 E] 목록 identity/스크롤 보존 — 새로고침 중 LoadingWidget 로 목록이 다시 붙어도 PageStorage 가 이전 offset 을 되살린다
                    //   (새 내용 길이에 clamp · 위쪽 기준). 결과 띠가 들고 날 때는 같은 목록이라 offset(pixels) 그대로 · 띠 높이만큼 아래로 밀렸다 돌아온다.
                    return ListView.builder(
                      key: const PageStorageKey<String>('member_management_list'),
                      padding: lp.copyWith(
                        bottom: lp.bottom + MediaQuery.paddingOf(context).bottom,
                      ),
                      itemCount: items.length,
                      itemBuilder: (_, i) => items[i],
                    );
                  }),
                ),
          ),
        ],
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
  // [S024 초대 · 감사48 (가)] 같은 맥락 머리 옆 '+ 멤버 초대' 글자 행동(시안 '+ 근무 요청 등록' 형식 · 다중 사업장 머리 '초대' 와 같은 TextButton 계열).
  //   한 줄에 모자라면(큰 글자 · 좁은 폭) 같은 묶음의 다음 줄로 내려간다 — 이름 · 행동 글자를 줄이거나 자르지 않는다(이름 말줄임은 기존 그대로).
  Widget _buildSingleBizHeader(BuildContext context, _BizSection section) {
    final theme = Theme.of(context);
    final padding = EdgeInsets.only(
      top: ResponsiveHelper.spacing(context, 4),
      bottom: ResponsiveHelper.spacing(context, 10),
    );
    Widget nameRow(MainAxisSize size) => Row(
          mainAxisSize: size,
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
                    color: AppColors.textSecondary), // [DU406 후보] grey600 4.30 → 5.52(화면 바탕)
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
    if (_isSubAdmin) {
      return Padding(padding: padding, child: nameRow(MainAxisSize.max)); // SubAdmin 무초대 — 기존 머리 그대로
    }
    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, c) => Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: ResponsiveHelper.spacing(context, 4),
          children: [
            ConstrainedBox(constraints: BoxConstraints(maxWidth: c.maxWidth), child: nameRow(MainAxisSize.min)),
            TextButton.icon(
              onPressed: () => _invite(section.id, section.name),
              icon: Icon(Icons.add, size: ResponsiveHelper.iconSize(context, 16)),
              label: Text('멤버 초대',
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

  // [판정51] 섹션 제목은 중립 진한 글(시안 '오늘의 근무' · '처리할 일' 과 같은 위계) — 의미색 글 · 색 막대 제거. 문구 · 수 · 굵기 · 크기 · 간격 그대로.
  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 8),
        top: ResponsiveHelper.spacing(context, 4),
      ),
      child: Text(
        title,
        style: ResponsiveHelper.smallStyle(context).copyWith(
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
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

    // [ERROR-AS-EMPTY] 오류 시 "멤버 없음"이 아닌 "로드 실패" 표시 (UNKNOWN != ZERO) — [S024 초대] 진입 선택에도 쓰려고 위로 옮겼다
    final bool isError = _hasError && _sections.isEmpty;
    Widget? action;
    if (_isSubAdmin) {
      // SubAdmin은 초대 권한 없음 — 버튼 미표시
    } else if (bizList.length == 1) {
      // 단일 사업장 — [S024 초대 · 감사48 (가)] 정상 빈 화면 = 다음 주행동 → 공용 전체 폭 주 버튼. 오류 화면은 기존 테두리형 진입 그대로.
      final biz = bizList.first;
      action = !isError
          ? Padding(
              padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
              child: CommonWidgets.primaryButton(
                context: context,
                text: '멤버 초대',
                icon: Icons.person_add_outlined,
                onPressed: () => _invite(biz.id, biz.name),
              ),
            )
          : Padding(
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

    // [ERROR-AS-EMPTY] isError 는 위(진입 선택)에서 계산했다
    // [H-2 E N3] 정상 빈 화면(제목 · 안내)은 그대로 두고, 새로고침 실패만 부제 아래 · 초대 진입 위에 결과 띠(공용 AppEmptyState 변경 0).
    if (!isError && _refreshError != null) {
      final band = Padding(
        padding: EdgeInsets.symmetric(horizontal: ResponsiveHelper.spacing(context, 16)),
        child: _refreshErrorBand(context, _refreshError!),
      );
      action = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          band,
          if (action != null) ...[SizedBox(height: ResponsiveHelper.spacing(context, 12)), action],
        ],
      );
    }
    return AppEmptyState(
      icon: isError ? Icons.cloud_off_rounded : Icons.group_outlined,
      title: isError
          ? '멤버 목록을 불러오지 못했어요' // [DU406 후보] 해요체
          : '등록된 멤버가 없습니다',
      subtitle: isError
          ? (bizList.isNotEmpty
              ? '아래에서 새 멤버를 초대하거나 새로고침을 시도해 보세요'
              : '네트워크 상태를 확인한 후 새로고침해 보세요')
          : _isSubAdmin
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
        color: AppColors.surface,
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
                  // [DU406 후보 r2] 이름 줄 = [이름 · 메뉴 48](초대 카드와 같은 구조) — 전화 · 칩 행이 메뉴 폭만큼 넓어져 B 에서 전화 전문이 한 줄에 들어간다.
                  //   이름은 말줄임 없이 자연 분할(긴 한 낱말은 가운데에서만), 전화는 별도 행에서 전문(번호 안 줄바꿈 0) · 읽기 색.
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          TextLayout.identity(member.name),
                          semanticsLabel: member.name,
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.w700),
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
                          // [DU406 후보] 누르는 영역 48×48(아이콘 크기 · 중앙 그대로), 아이콘 색 grey400 → textTertiary(흰 카드 5.25)
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: Center(
                              child: Icon(Icons.more_vert,
                                  color: AppColors.textTertiary,
                                  size: ResponsiveHelper.iconSize(context, 20)),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (member.phone != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 2)),
                    Text(
                      TextLayout.unit(FormatHelper.formatPhone(member.phone!)),
                      semanticsLabel: FormatHelper.formatPhone(member.phone!),
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.textSecondary),
                    ),
                  ],
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
                          color: AppColors.textTertiary), // [DU406 후보] grey400 1.88 → 5.25(흰 카드)
                    ),
                ],
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
      // [판정51] 초대 대기 카드 = 흰 면 · 중립 테두리(같은 화면 멤버 카드와 같음) — 노란 전체 면 대신 작은 시계 칸 · 안내 글만 따뜻한 경고 강조
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.grey200),
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
              backgroundColor: AppColors.conceptAmberSurface,
              child: Icon(
                Icons.schedule,
                size: ResponsiveHelper.iconSize(context, 18),
                color: AppColors.conceptAmberInk,
              ),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 12)),
            // [DU406 후보] 이름 줄 = [이름 · '취소'], 전화 · 안내는 아래에서 넓은 폭(취소 동작 · 색 · 크기 그대로)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          TextLayout.identity(invitation.targetName),
                          semanticsLabel: invitation.targetName,
                          style: ResponsiveHelper.bodyStyle(context)
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      TextButton(
                        onPressed: onCancel,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary, // [판정52] 확인창 진입 = 중립(흰 위 5.92) — 위험색은 확인창 최종 실행에만
                          padding: EdgeInsets.symmetric(
                            horizontal: ResponsiveHelper.spacing(context, 8),
                          ),
                        ),
                        child: Text('취소',
                            style: ResponsiveHelper.smallStyle(context,
                                    color: AppColors.textSecondary)
                                .copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                  if (invitation.targetPhone != null)
                    Text(
                      TextLayout.unit(FormatHelper.formatPhone(invitation.targetPhone!)),
                      semanticsLabel: FormatHelper.formatPhone(invitation.targetPhone!),
                      style: ResponsiveHelper.tinyStyle(context,
                          color: AppColors.textSecondary),
                    ),
                  Text(
                    TextLayout.keepWords('초대 발송 $elapsedLabel · 3일 내 미수락 시 자동 만료'),
                    semanticsLabel: '초대 발송 $elapsedLabel · 3일 내 미수락 시 자동 만료',
                    style: ResponsiveHelper.tinyStyle(context,
                        color: AppColors.conceptAmberInk), // [판정51] 발송 · 자동 만료 안내 = 작은 따뜻한 경고 강조
                  ),
                ],
              ),
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
              // [DU436 · 후속113 N2 · DU433 선례] 넓은 그라데이션 띠 · 흰 제목을 걷었다.
              //   흰 면 · 작은 brand 타일 · 진한 제목 · 사업장명 textSecondary(전문 · 말줄임 없음) · 중립 닫기(grey600) ·
              //   아래 옅은 구분선(공용 AppModalHeader 와 같은 grey200). 좁거나 큰 글자에서 제목 옆 칸이 모자라면
              //   타일 · 닫기 줄 아래로 제목 · 사업장명을 내린다(DU433 과 같은 기준). 닫기 동작(unfocus → pop false)은 그대로다.
              Container(
                padding: EdgeInsets.fromLTRB(
                  ResponsiveHelper.spacing(context, 20),
                  ResponsiveHelper.spacing(context, 18),
                  ResponsiveHelper.spacing(context, 16),
                  ResponsiveHelper.spacing(context, 18),
                ),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(bottom: BorderSide(color: AppColors.grey200)),
                ),
                child: LayoutBuilder(builder: (_, box) {
                  final tilePad = ResponsiveHelper.spacing(context, 8);
                  final tileIcon = ResponsiveHelper.iconSize(context, 20);
                  final gap = ResponsiveHelper.spacing(context, 12);
                  final closePad = ResponsiveHelper.spacing(context, 6);
                  final closeIcon = ResponsiveHelper.iconSize(context, 18);
                  final tile = Container(
                    padding: EdgeInsets.all(tilePad),
                    decoration: BoxDecoration(
                      color: AppColors.brandSurface,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.person_add_outlined,
                        color: AppColors.brand, size: tileIcon),
                  );
                  final close = Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                        Navigator.pop(context, false);
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: EdgeInsets.all(closePad),
                        child: Icon(Icons.close,
                            color: AppColors.grey600, size: closeIcon),
                      ),
                    ),
                  );
                  final titles = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(TextLayout.keepWords('멤버 초대'),
                          semanticsLabel: '멤버 초대',
                          style: ResponsiveHelper.subtitleStyle(context)
                              .copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold)),
                      Text(TextLayout.keepWords(widget.businessName),
                          semanticsLabel: widget.businessName,
                          style: ResponsiveHelper.tinyStyle(context,
                              color: AppColors.textSecondary)),
                    ],
                  );
                  final side = box.maxWidth - tilePad * 2 - tileIcon - gap - closePad * 2 - closeIcon;
                  if (TextLayout.fits(context, side, 120)) {
                    return Row(children: [tile, SizedBox(width: gap), Expanded(child: titles), close]);
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [tile, const Spacer(), close]),
                      SizedBox(height: gap),
                      titles,
                    ],
                  );
                }),
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
                      // [DU441] 그림자 카드 안에 테마 입력 테두리가 한 겹 더 그려져 틀이 이중이었다(W · B).
                      //   B(320 · 2.0)는 안내 '010-0000-0000'이 '010-000…'으로 잘렸다. 다음처럼 바꾼다.
                      //   - 입력 칸 하나가 틀이다(흰 면 + 테마 테두리 · 포커스 테두리). 그림자 카드는 걷었다.
                      //   - 안내 grey400(흰 위 1.88) → textTertiary, 전화 아이콘 grey400 → grey600(공용 AppSearchBar 와 같다).
                      //   - 칸 안 글 자리가 안내 폭(배율 1.0 · 102)보다 좁으면 전화 아이콘을 빼고 검색 버튼을 칸 아래 줄(전체 폭 · '검색')로 내린다.
                      //   검색 동작 · 입력 형식 · 진행 표시 · 활성 조건은 그대로다.
                      LayoutBuilder(builder: (_, box) {
                        final iconPadL = ResponsiveHelper.spacing(context, 14);
                        final iconPadR = ResponsiveHelper.spacing(context, 8);
                        final phoneIcon = ResponsiveHelper.iconSize(context, 18);
                        final btnGap = ResponsiveHelper.spacing(context, 8);
                        final btnPad = ResponsiveHelper.spacing(context, 10);
                        final searchIcon = ResponsiveHelper.iconSize(context, 20);
                        final textRoom = box.maxWidth -
                            (iconPadL + phoneIcon + iconPadR) -
                            (btnGap * 2 + btnPad * 2 + searchIcon);
                        final inline = TextLayout.fits(context, textRoom, 102);
                        final searchBtn = Material(
                          color: _searching
                              ? AppColors.grey200
                              : theme.primaryColor,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            onTap: _searching ? null : _search,
                            borderRadius: BorderRadius.circular(10),
                            child: Padding(
                              padding: EdgeInsets.all(btnPad),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  _searching
                                      ? const SizedBox(
                                          width: 18,
                                          height: 18,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white))
                                      : Icon(Icons.search_rounded,
                                          color: Colors.white,
                                          size: searchIcon),
                                  if (!inline) ...[
                                    SizedBox(
                                        width: ResponsiveHelper.spacing(
                                            context, 6)),
                                    Text('검색',
                                        style: ResponsiveHelper.bodyStyle(
                                            context,
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600)),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                        final field = TextField(
                          controller: _phoneCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [_phoneFmt],
                          style: ResponsiveHelper.bodyStyle(context),
                          decoration: InputDecoration(
                            hintText: '010-0000-0000',
                            hintStyle: ResponsiveHelper.bodyStyle(context,
                                color: AppColors.textTertiary),
                            filled: true,
                            fillColor: AppColors.surface,
                            prefixIcon: inline
                                ? Padding(
                                    padding: EdgeInsets.only(
                                        left: iconPadL, right: iconPadR),
                                    child: Icon(Icons.phone_outlined,
                                        color: AppColors.grey600,
                                        size: phoneIcon),
                                  )
                                : null,
                            prefixIconConstraints: const BoxConstraints(),
                            suffixIcon: inline
                                ? Padding(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: btnGap),
                                    child: searchBtn,
                                  )
                                : null,
                            suffixIconConstraints: const BoxConstraints(),
                            contentPadding: EdgeInsets.symmetric(
                                vertical: ResponsiveHelper.spacing(context, 14),
                                horizontal: inline ? 0 : iconPadL),
                          ),
                          onSubmitted: (_) {
                            if (!_searching) _search();
                          },
                        );
                        if (inline) return field;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            field,
                            SizedBox(height: btnGap),
                            searchBtn,
                          ],
                        );
                      }),
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
                                // [DU441] 안내 grey400(옅은 면 위 1.8) → textTertiary.
                                Text('전화번호를 입력하고 검색하세요',
                                    style: ResponsiveHelper.smallStyle(
                                        context,
                                        color: AppColors.textTertiary)),
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
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color:
                                    AppColors.borderLight),
                          ),
                          child: Row(children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundColor:
                                  AppColors.grey100,
                              child: Text(
                                ((_found!['name'] as String?) ?? '')
                                        .isNotEmpty
                                    ? ((_found!['name'] as String?) ?? '')[0]
                                    : '?',
                                style: ResponsiveHelper.bodyStyle(context)
                                    .copyWith(
                                        color: AppColors.textSecondary,
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
                                                        AppColors.textPrimary)),
                                    const SizedBox(height: 2),
                                    Text(
                                        FormatHelper.formatPhone(
                                            _found!['phone'] ?? ''),
                                        style: ResponsiveHelper.tinyStyle(
                                                context,
                                                color: AppColors.textSecondary
                                                    )),
                                  ]),
                            ),
                            Icon(Icons.verified_rounded,
                                color: AppColors.successDark,
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
                          // [DU449] 비활성 라벨을 흰색으로 직접 지정해 grey200 위 흰 글(≈ 1.2)이었다 · 반경 14 · 패딩 15 → 공용 주 버튼
                          //   (평면 brand · 최소 52 · 반경 12 · 비활성 grey200/grey500 · 진행 중 회전 표시). 눌림 조건 · 동작 · 아이콘은 그대로다.
                          CommonWidgets.primaryButton(
                            context: context,
                            text: '초대 발송',
                            icon: Icons.send_rounded,
                            isLoading: _sending,
                            onPressed: canSend ? _send : null,
                          ),
                          TextButton(
                            onPressed: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              Navigator.pop(context, false);
                            },
                            // [DU441] '취소' grey400(옅은 면 위 1.8) → textSecondary(보조 행동 글자 · DU437 하단 바와 같다).
                            child: Text('취소',
                                style: ResponsiveHelper.smallStyle(context,
                                    color: AppColors.textSecondary)),
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
    // [AUDIT.2R1] canCancelTransfer는 canManageWage 하위 권한 (MODEL B)
    // canManageWage=false일 때 canCancelTransfer toggle 비활성화
    final cancelTransferDisabled = !permissions.canManageWage;
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
        // canManageWage OFF 시 canCancelTransfer 자동 해제
        (v) => v
            ? permissions.copyWith(canManageWage: true)
            : permissions.copyWith(canManageWage: false, canCancelTransfer: false),
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
        '이체 완료 처리 취소',
        cancelTransferDisabled ? '급여 관리 권한이 필요합니다' : '잘못 처리된 이체완료 되돌리기',
        permissions.canCancelTransfer,
        (v) => permissions.copyWith(canCancelTransfer: v),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
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
          // canCancelTransfer(index 4)는 canManageWage=false 시 비활성
          final isDisabled = index == 4 && cancelTransferDisabled;
          return Column(
            children: [
              InkWell(
                onTap: isDisabled ? null : () => onChanged(updater(!value)),
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
                          color: (value && !isDisabled)
                              ? theme.primaryColor.withValues(alpha: 0.1)
                              : AppColors.grey100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(icon,
                            size: ResponsiveHelper.iconSize(context, 16),
                            color: (value && !isDisabled)
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
                                        color: (value && !isDisabled)
                                            ? null
                                            : AppColors.grey500)),
                            Text(subtitle,
                                style: ResponsiveHelper.tinyStyle(context,
                                    color: isDisabled
                                        ? AppColors.grey300
                                        : AppColors.grey400)),
                          ],
                        ),
                      ),
                      Switch(
                        value: isDisabled ? false : value,
                        onChanged: isDisabled ? null : (v) => onChanged(updater(v)),
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
    (Icons.undo_outlined,       '이체 완료 처리 취소', '잘못 처리된 이체완료 되돌리기'),
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
    // [AUDIT.2R1] canManageWage OFF 시 canCancelTransfer 자동 해제 (MODEL B)
    2 => v
        ? _permissions.copyWith(canManageWage: true)
        : _permissions.copyWith(canManageWage: false, canCancelTransfer: false),
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
                  // [AUDIT.2R1] canCancelTransfer(i==4)는 canManageWage=false 시 비활성 (MODEL B)
                  final isDisabled = i == 4 && !_permissions.canManageWage;
                  return Column(
                    children: [
                      InkWell(
                        onTap: isDisabled
                            ? null
                            : () => setState(
                                () => _permissions = _setValue(i, !value)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 14),
                          child: Row(
                            children: [
                              Container(
                                width: ResponsiveHelper.spacing(context, 40),
                                height: ResponsiveHelper.spacing(context, 40),
                                decoration: BoxDecoration(
                                  color: (value && !isDisabled)
                                      ? theme.primaryColor.withValues(alpha: 0.1)
                                      : AppColors.grey100,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  icon,
                                  size: ResponsiveHelper.iconSize(context, 18),
                                  color: (value && !isDisabled)
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
                                        color: (value && !isDisabled)
                                            ? AppColors.grey800
                                            : AppColors.grey500,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      // 비활성 시 의존성 힌트 표시
                                      isDisabled ? '급여 관리 권한이 필요합니다' : subtitle,
                                      style: ResponsiveHelper.tinyStyle(context,
                                          color: isDisabled
                                              ? AppColors.grey300
                                              : AppColors.grey400),
                                    ),
                                  ],
                                ),
                              ),
                              Switch(
                                value: isDisabled ? false : value,
                                onChanged: isDisabled
                                    ? null
                                    : (v) => setState(
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
