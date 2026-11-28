import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
// [R7-P1-7 P17-A] GradientScaffold → AppPageScaffold(D0 flat admin shell).
//   이 화면의 Colors.white 는 전부 **본문**이다(버튼 전경색·전체화면 이미지 뷰어
//   오버레이) — 헤더에 의존하는 색이 없어 위젯 이름만 바뀐다. 가로 스크롤 표의
//   열·행동·현재 선택 접근성은 좁은 폭 렌더로 따로 확인한다.
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';
import 'all_users_reads.dart';
import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_text_styles.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/format_helper.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../../utils/loading_state_mixin.dart';
// badge_service, flutter/services: [5A.2A] trustScore 관련 제거로 불필요
import '../../widgets/dialogs/styled_dialog.dart';
import '../../utils/action_guard.dart';
import '../../utils/keep_content_refresh.dart';
import '../../widgets/common/keep_content_body.dart';

/// 모든 사용자 조회·관리 화면 (최고관리자 전용)
class AllUsersScreen extends StatefulWidget {
  const AllUsersScreen({super.key, this.reads});

  /// [R7-P3-2 P32-X1] 목록을 만드는 읽기 경계. production 은 null.
  final AllUsersReads? reads;

  @override
  State<AllUsersScreen> createState() => _AllUsersScreenState();
}

class _AllUsersScreenState extends State<AllUsersScreen>
    with LoadingStateMixin, KeepContentRefreshMixin {
  late final AllUsersReads _reads = widget.reads ?? AllUsersReads.of();
  List<UserModel> _users = [];
  /// [.57] uid → 제한 성분(자동·수동/영구). 해제 확인 창이 '무엇이 풀리고 무엇이 남는지' 를 서버 값으로 말한다.
  Map<String, _Restriction> _restrictions = {};
  Object? _loadError;
  String _roleFilter = 'ALL';
  String _searchQuery = '';
  List<UserModel> _cachedFiltered = []; // 필터 결과 캐시 — build()마다 재계산 방지
  bool _isProcessing = false;
  final _searchController = TextEditingController();

  static const _roleLabels = {
    'ALL': '전체',
    'USER': '지원자',
    // [DU588b · ncb52l D4] 필터 이름을 목록 · 시트 · 확인창 역할명('사업장관리자')과 같게 — 저장 role 분류 · 필터 집합 · 건수는 그대로다.
    'BUSINESS_ADMIN': '사업장관리자',
    'SUPER_ADMIN': '슈퍼관리자',
  };

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
        _rebuildFilter();
      });
    });
    // 방어 심층화: AuthWrapper 분기 외 2차 역할 확인 (context는 postFrameCallback에서만 안전하게 접근)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<UserProvider>().isSuperAdmin) {
        Navigator.pop(context);
        return;
      }
      _loadAllUsers();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadAllUsers() async {
    // [L48 · impl_28] 처리 뒤 다시 읽기는 목록을 유지한다(잠금 + 얇은 진행 표시 · KeepContentRefreshMixin) — 첫 읽기·실패 화면만 전체 로딩 · 늦은 옛 응답 착지 0.
    final t = beginContentLoad(canKeep: _loadError == null);
    if (!t.keep) setLoading(true);
    if (mounted) setState(() => _loadError = null);
    try {
      final rawList = await _reads.allUsersRaw();

      if (!isCurrentContentLoad(t.gen)) return;
      final restrictions = <String, _Restriction>{};
      final users = rawList.whereType<Map>().map((data) {
        try {
          // [.57] callable 은 Timestamp 를 {_seconds, _nanoseconds} 맵으로 보낸다. 그대로 넘기면
          //   UserModel 이 restrictedUntil 을 읽지 못해(null) 제재 중인 사람이 '정상'으로 보였고 해제 버튼도 없었다(기기 확인).
          final d = Map<String, dynamic>.from(_reviveTimestamps(data) as Map);
          final uid = d['uid'] as String? ?? '';
          final r = _Restriction.tryFrom(d);
          if (r != null) restrictions[uid] = r;
          return UserModel.fromMap(d, uid);
        } catch (_) { return null; }
      }).whereType<UserModel>().toList();
      setState(() { _users = users; _restrictions = restrictions; _rebuildFilter(); });
      setLoading(false);
      finishContentLoad(t.gen, shown: true);
    } catch (e) {
      if (!isCurrentContentLoad(t.gen)) return;
      // [R7-P3-2 P32-X1] 조회 실패를 **대상 없음**으로 말하지 않는다.
      //   토스트는 사라지고 화면에는 `해당하는 사용자가 없습니다` 만 남았다 —
      //   문의 대상이 정말 없는 것과 못 읽은 것은 다른 사실이다.
      ToastHelper.showError('사용자 목록 불러오기 실패: $e');
      setState(() => _loadError = e);
      setLoading(false);
      finishContentLoad(t.gen, shown: false);
    }
  }

  /// _users / _roleFilter / _searchQuery 변경 시 호출 — build()마다 재계산하지 않음
  void _rebuildFilter() {
    var list = _roleFilter == 'ALL'
        ? _users
        : _users.where((u) => u.role.name == _roleFilter).toList();

    if (_searchQuery.isNotEmpty) {
      list = list.where((u) {
        final name = u.name.toLowerCase();
        final username = u.username.toLowerCase();
        final phone = u.effectivePhone?.toLowerCase() ?? '';
        return name.contains(_searchQuery) ||
            username.contains(_searchQuery) ||
            phone.contains(_searchQuery);
      }).toList();
    }
    _cachedFiltered = list;
  }

  // ── 관리 액션 ───────────────────────────────────────────────────

  /// [SA-AUDIT.49] callableGetAllUsers 의 limit — 이만큼 받으면 더 있을 수 있다.
  static const int _serverListCap = 500;

  /// [SA-AUDIT.49] 실패 안내 — 서버가 준 문장을 쓰고, 모르는 실패는 결과를 확인하라고 말한다.
  String _failureText(Object e) {
    // [.58] 시간 초과·연결 끊김·내부 오류는 서버가 이미 반영했을 수도 있다 — '처리하지 못했습니다' 라고 단정하지 않는다.
    if (e is FirebaseFunctionsException &&
        const {'deadline-exceeded', 'unavailable', 'internal', 'unknown', 'cancelled'}.contains(e.code)) {
      return '처리 결과를 확인하지 못했어요. 목록에서 현재 상태를 확인해 주세요.';
    }
    if (e is FirebaseFunctionsException && (e.message?.isNotEmpty ?? false)) {
      return '처리하지 못했어요: ${e.message}';
    }
    return '처리 결과를 확인하지 못했어요. 목록에서 현재 상태를 확인해 주세요.';
  }

  /// [R7-P3-3 P33-X1] 쓰기 직전 **대상을 다시 말한다**.
  ///
  ///   상세 시트는 확인창을 띄우기 전에 `Navigator.pop` 으로 닫힌다. 그래서
  ///   시트 안에만 있던 `@아이디` 가 정작 실행 직전에는 사라져 있었고,
  ///   이름이 같은 계정이면 확인창 문구가 **글자 하나 다르지 않았다**.
  ///   목록 행에 긴 식별자를 강제하지 않고, 되돌릴 수 없는 순간에만 붙인다.
  ///   연락처·신분번호는 더하지 않는다 — 이미 상세에 있는 정보만 옮긴다.
  String _targetLine(UserModel u) {
    final role = switch (u.role) {
      UserRole.SUPER_ADMIN => '슈퍼관리자',
      UserRole.BUSINESS_ADMIN => '사업장관리자',
      UserRole.USER => '지원자',
    };
    final biz = u.businessName;
    return '${u.name} · @${u.username} · $role'
        '${biz != null && biz.isNotEmpty ? ' · $biz' : ''}';
  }

  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_toggleBlacklistLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _toggleBlacklist(UserModel user) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('allUsers._isProcessing', this), () => _toggleBlacklistLocked(user));

  Future<void> _toggleBlacklistLocked(UserModel user) async {
    if (_isProcessing) return;
    if (user.isBlacklisted) {
      // [.57] 블랙리스트 해제(callableUnblacklistUser)는 이용 제한(노쇼 자동·수동)을 건드리지 않는다(LOCAL 확인).
      //   제한이 남아 있으면 '로그인이 가능해집니다' 라고 하지 않는다.
      final left = user.restrictedUntil;
      final stillRestricted = left != null && left.isAfter(DateTime.now());
      final confirmed = await DialogHelper.showDangerConfirm(
        context,
        title: '계정 이용 차단 해제',
        message: TextLayout.keepWords('${_targetLine(user)}\n\n이 계정의 이용 차단을 해제할까요?\n'
            '${stillRestricted ? '이용 제한(${_untilText(left)})은 이 버튼으로 풀리지 않아 해제 뒤에도 로그인·지원이 제한돼요.' : '해제하면 다시 로그인할 수 있어요.'}'),
        confirmText: '해제',
      );
      if (!confirmed || !mounted) return;
      setState(() => _isProcessing = true);

      try {
        await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableUnblacklistUser')
            .call({'targetUid': user.uid});
        if (!mounted) return;
        ToastHelper.showSuccess('계정 이용 차단을 해제했어요');
        await _loadAllUsers();
      } catch (e) {
        // [SA-AUDIT.49] 예외 원문을 그대로 보이지 않는다. 응답을 못 받았어도 서버는 반영했을 수 있으니
        //   목록을 다시 읽어 실제 상태를 보인다(자동 재전송은 하지 않는다).
        if (mounted) ToastHelper.showError(_failureText(e));
        if (mounted) unawaited(_loadAllUsers());
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    } else {
      // 등록: 사유 입력
      final reason = await _showReasonDialog(
        subject: _targetLine(user),
        title: '계정 이용 차단',
        hint: '예: 반복 노쇼, 이용 약관 위반 등',
        confirmLabel: '차단',
        confirmColor: AppColors.error,
        // [DU581 · 판정156 Q4] 효과 · 기한 · 남는 확정 근무를 실행 전에 말한다(callableBlacklistUser = 표시 · 토큰 회수뿐 · 지원 취소 0 · PP-SA-BLACKLIST).
        detail: '차단하면 해제 전까지 로그인·지원이 막혀요. 이미 확정된 근무는 자동으로 취소되지 않아요.',
        // [SA-AUDIT.49] 사유는 당사자의 로그인·지원 거절 안내에 그대로 보인다(LOCAL 확인).
        visibilityNote: '입력한 사유는 로그인·지원이 막힐 때 이 사용자에게 그대로 보여요. 신고자 정보 같은 내부 메모는 적지 마세요.',
      );
      if (reason == null || !mounted) return;
      setState(() => _isProcessing = true);

      try {
        await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
            .httpsCallable('callableBlacklistUser')
            .call({'targetUid': user.uid, 'blacklistReason': reason});
        if (!mounted) return;
        ToastHelper.showSuccess('계정 이용을 차단했어요');
        await _loadAllUsers();
      } catch (e) {
        // [SA-AUDIT.49] 예외 원문을 그대로 보이지 않는다. 응답을 못 받았어도 서버는 반영했을 수 있으니
        //   목록을 다시 읽어 실제 상태를 보인다(자동 재전송은 하지 않는다).
        if (mounted) ToastHelper.showError(_failureText(e));
        if (mounted) unawaited(_loadAllUsers());
      } finally {
        if (mounted) setState(() => _isProcessing = false);
      }
    }
  }

  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_clearRestrictionLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _clearRestriction(UserModel user) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('allUsers._isProcessing', this), () => _clearRestrictionLocked(user));

  Future<void> _clearRestrictionLocked(UserModel user) async {
    if (_isProcessing) return;
    final restrictedUntil = user.restrictedUntil;
    if (restrictedUntil == null) return;

    // [.57] 이 버튼(callableResetPenalty)은 **노쇼 제재만** 푼다 — 노쇼 기록·원장과 자동 제한.
    //   수동·영구 제한은 서버가 그대로 둔다. 예전 문구 '해제 후 즉시 이용 가능해집니다' 는 수동 제한이
    //   겹치면 사실이 아니었다(LOCAL 확인). 무엇이 풀리고 무엇이 남는지 서버 값으로 말한다.
    final r = _restrictions[user.uid];
    final message = '${_targetLine(user)}\n\n${_resetEffectText(user, r)}';

    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '노쇼 제한 해제',
      message: TextLayout.keepWords(message),
      confirmText: '해제',
    );
    if (!confirmed || !mounted) return;
    setState(() => _isProcessing = true);

    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableResetPenalty')
          .call({'targetUid': user.uid});
      if (!mounted) return;
      await _toastFromReloaded(user.uid, '노쇼 제한을 해제했어요');
    } catch (e) {
      if (mounted) ToastHelper.showError(_failureText(e));
      if (mounted) unawaited(_loadAllUsers());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  /// [.57] 노쇼 제재 해제(리셋)의 효과 — 서버 계약(callableResetPenalty 00079): 노쇼 횟수·날짜·최근 90일·원장과
  ///   자동 제한(auto)을 비우고, 수동·영구 제한(base)은 남긴다.
  String _resetEffectText(UserModel user, _Restriction? r) {
    final lines = <String>[];
    final auto = r?.auto;
    lines.add(auto != null && auto.isAfter(DateTime.now())
        ? '풀리는 것: 노쇼 자동 제한(${_untilText(auto)})'
        : '풀리는 것: 노쇼 자동 제한 없음');
    lines.add('노쇼 기록 초기화: ${user.noShowCount}회(최근 90일 ${user.recentNoShowCount}회) → 0회');
    final base = r?.base;
    final remain = <String>[
      if (base != null && base.isAfter(DateTime.now())) _baseText(r!),
      if (user.isBlacklisted) '계정 이용 차단',
    ];
    return (lines..addAll(_remainLines(remain))).join('\n');
  }

  /// [.58] '남는 것' 과 결론 한 줄 — 해제 행동마다 같은 모양으로 말한다.
  List<String> _remainLines(List<String> remain) => [
        for (final x in remain) '남는 것: $x — 이 버튼으로는 풀리지 않아요',
        remain.isNotEmpty ? '해제 뒤에도 로그인·지원이 제한돼요.' : '해제 뒤 바로 로그인·지원할 수 있어요.',
      ];

  /// [.58] 수동·영구 제한 해제(callableReleaseManualRestriction, A 묶음 00001-yex)의 효과.
  ///   서버 계약: base(수동·영구·기존) 성분만 지운다 — 노쇼 자동 제한·원장·블랙리스트는 그대로.
  String _releaseEffectText(UserModel user, _Restriction r) {
    final auto = r.auto;
    return [
      '해제할 것: ${_baseText(r)}',
      ..._remainLines([
        if (auto != null && auto.isAfter(DateTime.now())) '노쇼 자동 제한(${_untilText(auto)})',
        if (user.isBlacklisted) '계정 이용 차단',
      ]),
      '사유는 감사 기록에만 남고 이 사용자에게는 보이지 않아요.',
    ].join('\n');
  }

  /// [.58] 쓰기 뒤 목록을 다시 읽고 **다시 읽은 상태로** 말한다. 다시 읽기에 실패하면 성공 여부와 현재 상태를
  ///   섞지 않는다 — 요청은 처리됐지만 지금 상태는 모른다고 말한다.
  Future<void> _toastFromReloaded(String uid, String done) async {
    await _loadAllUsers();
    if (!mounted) return;
    if (_loadError != null) {
      ToastHelper.showError(TextLayout.keepWords('$done. 현재 상태를 다시 읽지 못했어요 — 새로고침해 확인해 주세요'));
      return;
    }
    final now = _users.where((u) => u.uid == uid).firstOrNull;
    final left = now?.restrictedUntil;
    final blocked = <String>[
      if (left != null && left.isAfter(DateTime.now())) '이용 제한(${_untilText(left)})',
      if (now?.isBlacklisted ?? false) '계정 이용 차단',
    ];
    ToastHelper.showSuccess(TextLayout.keepWords(blocked.isEmpty
        ? done
        : '$done. 아직 남은 제한: ${blocked.join(', ')}'));
  }

  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_releaseManualLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _releaseManual(UserModel user) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('allUsers._isProcessing', this), () => _releaseManualLocked(user));

  Future<void> _releaseManualLocked(UserModel user) async {
    if (_isProcessing) return;
    final r = _restrictions[user.uid];
    // 읽은 base 가 없으면 실행하지 않는다 — expectedBaseUntilMs 를 모르는 요청은 보내지 않는다.
    if (r == null || r.unreadable || r.baseMs == null || r.base == null) return;
    final reason = await _showReasonDialog(
      subject: _targetLine(user),
      detail: _releaseEffectText(user, r),
      title: '${r.baseLabel} 해제',
      hint: '예: 이의 신청 확인, 잘못 설정한 제한 등',
      confirmLabel: '해제',
      // [DU588b · 판정114 S052 해제] 수동 · 기간 제한 해제는 복구 행동 — 최종 단추 · 머리 아이콘 warning → brand(차단 등록 errorDark · 차단 해제/노쇼 리셋 빨강은 ncb52d D4 그대로).
      confirmColor: AppColors.brand,
      minLength: 2,
    );
    if (reason == null || !mounted) return;
    setState(() => _isProcessing = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableReleaseManualRestriction')
          .call({
        'targetUid': user.uid,
        // 낡은 화면 방지: 본 제한과 지금 제한이 다르면 서버가 BASE_RESTRICTION_CHANGED 로 거절한다.
        'expectedBaseUntilMs': r.baseMs,
        'reason': reason,
        // 이 확인 한 번의 멱등 키 — 자동 재전송은 하지 않는다.
        'requestId': _newRequestId('rel'),
      });
      if (!mounted) return;
      await _toastFromReloaded(user.uid, '${r.baseLabel}을 해제했어요');
    } catch (e) {
      if (mounted) ToastHelper.showError(_failureText(e));
      if (mounted) unawaited(_loadAllUsers());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  static String _newRequestId(String prefix) {
    final rnd = Random.secure();
    return '$prefix-${List.generate(16, (_) => rnd.nextInt(16).toRadixString(16)).join()}';
  }

  String _untilText(DateTime t) =>
      _isPermanentInstant(t) ? '기한 없음' : '${FormatHelper.formatKstDateTimeKorean(t)}까지';

  /// [DU581 · 판정156 Q4] 기한 있는 제한 = '이름(…까지)' · 기한 없음(permanent base) = 이름만('이용 제한(기한 없음)' 겹침 0).
  String _baseText(_Restriction r) => _isPermanentInstant(r.base!) ? r.baseLabel : '${r.baseLabel}(${_untilText(r.base!)})';

  // [5A.2A] _adjustTrustScore 제거 — callableAdjustTrustScore 폐기

  Future<String?> _showReasonDialog({
    required String subject,
    required String title,
    required String hint,
    required String confirmLabel,
    required Color confirmColor,
    String? visibilityNote,
    String? detail,
    int minLength = 1,
  }) {
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ReasonDialog(
        subject: subject,
        title: title,
        hint: hint,
        confirmLabel: confirmLabel,
        confirmColor: confirmColor,
        visibilityNote: visibilityNote,
        detail: detail,
        minLength: minLength,
      ),
    );
  }

  // ── 사용자 상세 바텀시트 ────────────────────────────────────────

  void _showUserDetailSheet(UserModel user) {
    // [SA-SHEET-BG] 공용 시트로 연다(흰 배경·상단 20 radius·SafeArea).
    //   투명 배경으로 직접 띄우면 DraggableScrollableSheet 안의 Column 에 배경이 없어
    //   뒤 목록이 비쳐 겹쳐 보였다(Pixel 5 10-23). 같은 구성인 BusinessActionDrillDownSheet 와 같은 방식.
    DialogHelper.showSheet<void>(
      context,
      isScrollControlled: true,
      builder: (ctx) => _UserDetailSheet(
        user: user,
        restriction: _restrictions[user.uid],
        onToggleBlacklist: () {
          Navigator.pop(ctx);
          _toggleBlacklist(user);
        },
        onClearRestriction: () {
          Navigator.pop(ctx);
          _clearRestriction(user);
        },
        onReleaseManual: () {
          Navigator.pop(ctx);
          _releaseManual(user);
        },
        // [5A.2A] onAdjustTrustScore 제거
      ),
    );
  }

  // ── UI ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      // [SA-AUDIT.49] 서버(callableGetAllUsers)는 가입 최신순 500명까지만 준다(잘림 신호 없음).
      //   그만큼 받았으면 전체 수처럼 말하지 않는다.
      title: _users.length >= _serverListCap
          ? '전체 사용자 관리 (최근 ${_users.length}명까지)'
          : '전체 사용자 관리 (${_users.length}명)',
      // [R7-P1-7 P17-A] 헤더 새로고침 → flat shell 의 actions (행동 동일).
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          color: AppColors.textSecondary,
          tooltip: '새로고침',
          onPressed: _loadAllUsers,
        ),
      ],
      body: Column(
        children: [
          _buildSearchBar(),
          _buildRoleFilter(),
          Expanded(
            child: Builder(builder: (context) {
              if (isLoading) return const LoadingWidget(message: '사용자 목록을 불러오는 중...');
              final filtered = _cachedFiltered;
              return KeepContentBody(
                refreshing: refreshingKeep,
                child: filtered.isEmpty ? _buildEmptyState() : _buildUserList(filtered),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 16),
        ResponsiveHelper.spacing(context, 8),
        ResponsiveHelper.spacing(context, 16),
        0,
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          // [DU588b · 판정114 S052 검색] B(320@2.0)에서 '이름 · 아이디 …' 로 잘리던 안내를 두 줄까지 구분점 뒤에서 바꿔 전문을 보인다(문구 그대로 ·
          //   DU507 공고 한도 안내와 같은 방식 · 값이 든 칸은 숨은 안내 높이를 잡지 않는다).
          hintText: TextLayout.phrases('이름 · 아이디 · 연락처 검색'),
          hintMaxLines: 2,
          maintainHintSize: false,
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => _searchController.clear(),
                )
              : null,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          contentPadding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 10),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleFilter() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _roleLabels.entries.map((e) {
            final active = _roleFilter == e.key;
            final count = e.key == 'ALL'
                ? _users.length
                : _users.where((u) => u.role.name == e.key).length;
            return Padding(
              padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
              child: FilterChip(
                label: Text('${e.value} ($count)'),
                selected: active,
                onSelected: (_) => setState(() { _roleFilter = e.key; _rebuildFilter(); }),
                // [NCB-52L] 선택 = brand(옅은 brand 면 · brand 테두리 · 체크 · 굵은 brand 글자), 미선택 = 흰 면 · 옅은 테두리 · 보조 글자
                //   (DU242 알림 필터와 같은 짝). 이전에는 선택에 빨강(errorDark 15%)을 썼고, 미선택 grey600 글자는 테마 칩 면 위 약 4.1 이었다.
                backgroundColor: AppColors.surface,
                selectedColor: AppColors.brandSurface,
                checkmarkColor: AppColors.brand,
                side: BorderSide(color: active ? AppColors.brand : AppColors.grey200),
                labelStyle: ResponsiveHelper.smallStyle(
                  context,
                  color: active ? AppColors.brand : AppColors.textSecondary,
                ).copyWith(fontWeight: active ? FontWeight.bold : null),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    // [R7-P3-2 P32-X1] 못 읽은 것은 없는 것이 아니다.
    // [DU588c · 판정174 §3 :32] 남은 합니다체 3문장 → 해요체(뜻 그대로) — 오류/빈 목록 분기 · 다시 시도 · 데이터는 그대로다.
    if (_loadError != null) {
      return AppEmptyState(
        icon: Icons.error_outline,
        title: '사용자 목록을 불러오지 못했어요',
        subtitle: '해당하는 사용자가 없다는 뜻은 아니에요.',
        action: TextButton(
          onPressed: _loadAllUsers,
          child: const Text('다시 시도'),
        ),
      );
    }
    return const AppEmptyState(
      icon: Icons.people_outline,
      title: '해당하는 사용자가 없어요',
    );
  }

  Widget _buildUserList(List<UserModel> list) {
    return RefreshIndicator(
      onRefresh: _loadAllUsers,
      child: ListView.builder(
        padding: ResponsiveHelper.listPadding(context),
        itemCount: list.length,
        itemBuilder: (context, i) => _buildUserCard(list[i]),
      ),
    );
  }

  Widget _buildUserCard(UserModel user) {
    final roleLabel = switch (user.role) {
      UserRole.SUPER_ADMIN => '슈퍼관리자',
      UserRole.BUSINESS_ADMIN => '사업장관리자',
      UserRole.USER => '지원자',
    };

    return Card(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 10)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showUserDetailSheet(user),
        child: Padding(
          padding: ResponsiveHelper.cardPadding(context),
          child: Row(
            children: [
              // [NCB-52L] 아바타 = 한 가지(옅은 brand 원 · brand 사람 아이콘 · 시안 참여자 원). 역할색(빨강 · 보라 · 초록)과
              //   블랙리스트 빨강 면을 걷었다 — 블랙리스트 · 제재중 · 승인대기는 아래 작은 상태 칩이 글자로 말한다(C3 · C7).
              const CircleAvatar(
                backgroundColor: AppColors.brandSurface,
                child: Icon(Icons.person, color: AppColors.brand),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // [DU493] 좁은 폭 · 큰 글자에서 역할 칩이 이름 칸을 눌러 이름이 한 음절씩 세로로 쌓였다(B 320@2.0 '박/사/장').
                    //   이름 + 칩 한 줄(배율 1.0 기준 170)이 안 들어가면 칩을 이름 아래로 내린다. 넓은 화면은 그대로 한 줄이다.
                    LayoutBuilder(builder: (context, c) {
                      final nameText = Text(
                        user.name,
                        style: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.bold),
                      );
                      final roleChip = Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 8),
                          vertical: ResponsiveHelper.spacing(context, 3),
                        ),
                        // [NCB-52L] 역할 칩 = 세 역할 같은 중립 칩(StatusBadge.neutral 짝 grey200 면 · grey700 글자 · 약 5.3).
                        //   역할별 색 면 · 테두리를 걷었다(C7). 역할 이름 · 글자 크기 · 굵기 · 배치(DU493)는 그대로다.
                        decoration: BoxDecoration(
                          color: AppColors.grey200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          roleLabel,
                          style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey700)
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                      );
                      if (TextLayout.fits(context, c.maxWidth, 170)) {
                        return Row(children: [Expanded(child: nameText), roleChip]);
                      }
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          nameText,
                          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                          roleChip,
                        ],
                      );
                    }),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    if (user.effectivePhone != null)
                      Text(
                        user.effectivePhone!,
                        style: ResponsiveHelper.smallStyle(
                          context,
                          color: Theme.of(context).textTheme.bodyMedium?.color,
                        ),
                      ),
                    // 상태 칩 행
                    // [DU493] Row(근무일 Flexible + 칩)는 B(320@2.0)에서 오른쪽으로 넘쳤다(9.1px · '제재중' 잘림 · 근무일 글자 폭 0).
                    //   Wrap 으로 자리가 없으면 다음 줄로 보낸다. 간격 6 은 그대로다.
                    Wrap(
                      spacing: ResponsiveHelper.spacing(context, 6),
                      runSpacing: ResponsiveHelper.spacing(context, 4),
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          '${user.totalWorkDays}일 근무',
                          style: ResponsiveHelper.tinyStyle(
                            context,
                            color: Theme.of(context).textTheme.bodySmall?.color,
                          ),
                        ),
                        // [DU588b · ncb52l D4] USER + 서브관리자 배정 = 역할 칩(저장 role '지원자') 옆 보조 표기 — 역할 칩과 같은 중립 짝(grey200 · grey700) · 필터 · 건수 그대로.
                        if (user.isSubAdmin) _miniChip('서브관리자', AppColors.grey700, face: AppColors.grey200, ink: AppColors.grey700),
                        if (user.isBlacklisted) _miniChip('계정 이용 차단', AppColors.error),
                        if (user.isRestricted) _miniChip('이용 제한', AppColors.warning),
                        // [NCB-52L D1] 승인대기 = 일반 상태 정보 → brand 짝(brandSurface 면 · brand 글자 · 약 5.0). 조건 · 라벨은 그대로다.
                        //   블랙리스트 error · 제재중 warning 은 그대로 둔다(목록 상태 계열 2).
                        // [DU588b · 판정114 S052 가입대기] 이름 '승인대기' → '가입 미완료'(V3: 운영자 승인 단계 없음 · 조건 isPending · 색 짝 그대로).
                        if (user.isPending)
                          _miniChip('가입 미완료', AppColors.brand, face: AppColors.brandSurface, ink: AppColors.brand),
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.grey400,
                size: ResponsiveHelper.iconSize(context, 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// [NCB-52L D1] [face] · [ink] 는 목록 전용 면 · 글자 지정이다(승인대기 brand 짝). 없으면 예전 그대로 [color] 의 짝을 쓴다.
  ///   공용 `_chipBg` · `_onTintInk`(시트도 씀)의 fallback 은 brand 12% · textPrimary 라 brand 를 넘기기만 해서는 의도 짝이 안 나온다.
  Widget _miniChip(String label, Color color, {Color? face, Color? ink}) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 6),
        vertical: ResponsiveHelper.spacing(context, 1),
      ),
      // [DU492] 같은 색 12% 면 위 같은 색 글자 → Bg 짝 면 + 진한 짝 글자(StatusBadge · DU427).
      decoration: BoxDecoration(
        color: face ?? _chipBg(color),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: ResponsiveHelper.tinyStyle(context, color: ink ?? _onTintInk(color))
            .copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

// ── 사용자 상세 바텀시트 ─────────────────────────────────────────

/// [.57] 서버 제한 성분 — `restrictionParts`(auto·base·baseSource)와 `restrictionSource`.
class _Restriction {
  const _Restriction({this.auto, this.base, this.baseMs, this.baseSource, this.source, this.unreadable = false});
  final DateTime? auto;
  final DateTime? base;
  /// [.58] 서버가 비교하는 base 만료 시각(ms) — Timestamp 에서 그대로 계산한다(DateTime 왕복 없이).
  final int? baseMs;
  final String? baseSource;
  final String? source;
  /// [.58] 제한 값이 있는데 시각으로 읽지 못했다 — '정상'으로 보이거나 실행 버튼을 열지 않는다.
  final bool unreadable;

  String get baseLabel => (base != null && _isPermanentInstant(base!)) || baseSource == 'permanent'
      ? '이용 제한(기한 없음)'
      : (baseSource == 'manual' ? '관리자 수동 제한' : '기존 제한');

  static DateTime? _t(Object? v) => v is Timestamp ? v.toDate() : null;

  static _Restriction? tryFrom(Map<String, dynamic> d) {
    final p = d['restrictionParts'];
    final src = d['restrictionSource'] as String?;
    final ru = d['restrictedUntil'];
    if (p is! Map && src == null && ru == null) return null;
    final m = p is Map ? p : const {};
    bool bad(Object? v) => v != null && v is! Timestamp;
    if (bad(ru) || bad(m['auto']) || bad(m['base'])) return const _Restriction(unreadable: true);
    if (p is Map) {
      final b = m['base'] as Timestamp?;
      return _Restriction(auto: _t(m['auto']), base: b?.toDate(), baseMs: b?.millisecondsSinceEpoch,
          baseSource: m['baseSource'] as String?, source: src);
    }
    // 성분 기록이 없는 문서(원장 이전) — 서버(srvBasePartFromUntil)와 같이 해석한다: auto 출처면 자동, 그 밖은 base.
    final t = ru as Timestamp?;
    if (t == null) return _Restriction(source: src);
    if (src == 'auto') return _Restriction(auto: t.toDate(), source: src);
    final permanent = _isPermanentInstant(t.toDate());
    return _Restriction(base: t.toDate(), baseMs: t.millisecondsSinceEpoch,
        baseSource: src ?? (permanent ? 'permanent' : 'legacy'), source: src);
  }
}

/// [.58] 영구 제한 경계 — 서버(SRV_PERMANENT_RESTRICTION_MS)와 같은 절대 시각 KST 9999-01-01 00:00.
///   `year >= 9999` 는 기기 시간대가 GMT 면(QA 기기) 영구 값이 9998년이라 놓친다.
bool _isPermanentInstant(DateTime t) =>
    t.millisecondsSinceEpoch >= DateTime.utc(9998, 12, 31, 15).millisecondsSinceEpoch;

/// [.57] callable 응답의 {_seconds, _nanoseconds} 맵을 Timestamp 로 되살린다(안쪽 맵까지).
Object? _reviveTimestamps(Object? v) {
  if (v is Map) {
    final s = v['_seconds'];
    final n = v['_nanoseconds'];
    if (v.length == 2 && s is num && n is num) return Timestamp(s.toInt(), n.toInt());
    return v.map((k, x) => MapEntry(k.toString(), _reviveTimestamps(x)));
  }
  if (v is List) return v.map(_reviveTimestamps).toList();
  return v;
}

/// [DU491] 같은 색 옅은 면(8–10%) 위 글자 — 4.5 를 넘는 진한 짝으로 쓴다(StatusBadge 짝 · DU425–427).
///   purple 은 그대로 넘는다. info 진한 짝(infoDark)은 info 옅은 면 위 약 4.2 라 본문색으로 둔다.
///   0 같은 중립 값(grey400)은 보조 글자색이다. 면 · 테두리 · 아이콘은 원래 색 그대로다.
Color _onTintInk(Color c) {
  if (c == AppColors.success) return AppColors.successDark;
  if (c == AppColors.warning) return AppColors.warningDark;
  if (c == AppColors.error) return AppColors.errorDark;
  if (c == AppColors.purple) return AppColors.purple;
  if (c == AppColors.grey400) return AppColors.textSecondary;
  return AppColors.textPrimary;
}

/// [DU492] 상태 미니 칩 면 — StatusBadge Bg 짝(DU427). 같은 색 12% 면은 warningDark 가 4.46 이라 미달이었다.
Color _chipBg(Color c) {
  if (c == AppColors.error) return AppColors.errorBg;
  if (c == AppColors.warning) return AppColors.warningBg;
  if (c == AppColors.info) return AppColors.infoBg;
  return c.withValues(alpha: 0.12);
}

class _UserDetailSheet extends StatelessWidget {
  final UserModel user;
  final _Restriction? restriction;
  final VoidCallback onToggleBlacklist;
  final VoidCallback onClearRestriction;
  final VoidCallback onReleaseManual;

  const _UserDetailSheet({
    required this.user,
    this.restriction,
    required this.onToggleBlacklist,
    required this.onClearRestriction,
    required this.onReleaseManual,
  });

  bool get _unreadable => restriction?.unreadable ?? false;

  /// [.58] 노쇼 리셋으로 풀 것이 있는가 — 자동 제한·노쇼 기록이 모두 없으면(수동만 남음) 버튼을 열지 않는다.
  ///   (DEV 리셋은 이때도 감사를 다시 남긴다 — 서버 후보 RST.) 성분을 모르면 기존처럼 연다.
  bool get _canReset {
    if (_unreadable || !user.isRestricted) return false;
    final r = restriction;
    if (r == null) return true;
    final auto = r.auto != null && r.auto!.isAfter(DateTime.now());
    return auto || user.noShowCount > 0 || user.recentNoShowCount > 0;
  }

  bool get _canReleaseBase {
    final r = restriction;
    return !_unreadable && r != null && r.baseMs != null && r.base!.isAfter(DateTime.now());
  }

  static String _restrictionLines(UserModel user, _Restriction? r) {
    String until(DateTime t) => _isPermanentInstant(t) ? '기한 없음' : '${FormatHelper.formatKstDateTimeKorean(t)}까지';
    final now = DateTime.now();
    final lines = <String>[
      if (r?.auto != null && r!.auto!.isAfter(now)) '노쇼 자동 제한 ${until(r.auto!)}',
      // [.58] 영구는 '영구 제한' 한 번만(만료 시각이 없다).
      if (r?.base != null && r!.base!.isAfter(now))
        _isPermanentInstant(r.base!) ? r.baseLabel : '${r.baseLabel} ${until(r.base!)}',
    ];
    return lines.isNotEmpty ? lines.join('\n') : until(user.restrictedUntil!);
  }

  @override
  Widget build(BuildContext context) {
    final roleLabel = switch (user.role) {
      UserRole.SUPER_ADMIN => '슈퍼관리자',
      UserRole.BUSINESS_ADMIN => '사업장관리자',
      UserRole.USER => '지원자',
    };

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, controller) => Column(
        children: [
          // 핸들
          Center(
            child: Container(
              margin: EdgeInsets.symmetric(
                vertical: ResponsiveHelper.spacing(context, 12),
              ),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // 헤더
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 20),
            ),
            // [DU499] B(320@2.0)에서 역할 칩이 부제 칸을 눌러 '· 지원자' 가 줄 머리가 됐다 — 한 줄(배율 1.0 기준 280)이
            //   안 들어가면 칩을 부제 아래로 내려 칸을 넓히고, 부제는 구분점을 앞 조각에 붙인다. 넓은 화면은 칩 오른쪽 그대로다.
            child: LayoutBuilder(builder: (context, c) {
              final fits = TextLayout.fits(context, c.maxWidth, 280);
              final chip = Container(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveHelper.spacing(context, 10),
                  vertical: ResponsiveHelper.spacing(context, 4),
                ),
                // [NCB-52D] 역할 칩 = 목록(NCB-52L)과 같은 중립 칩(grey200 면 · grey700 글자 · 약 5.3). 역할별 색 면 · 테두리를 걷었다(C7).
                decoration: BoxDecoration(
                  color: AppColors.grey200,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  roleLabel,
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey700)
                      .copyWith(fontWeight: FontWeight.bold),
                ),
              );
              return Row(
                crossAxisAlignment: fits ? CrossAxisAlignment.center : CrossAxisAlignment.start,
                children: [
                  // [NCB-52D] 아바타 = 목록과 같은 한 가지(옅은 brand 원 · brand 사람 아이콘). 역할색 면을 걷었다(C7 · D2 와 같은 국소 적용).
                  CircleAvatar(
                    radius: ResponsiveHelper.spacing(context, 22),
                    backgroundColor: AppColors.brandSurface,
                    child: Icon(Icons.person, color: AppColors.brand, size: ResponsiveHelper.iconSize(context, 24)),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          style: ResponsiveHelper.titleStyle(context)
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          // [DU588b · ncb52l D4] 서브관리자 배정이면 부제에 보조 표기(역할 칩 = 저장 role 그대로 · 목록 보조 칩과 같은 말).
                          TextLayout.phrases('@${user.username} · $roleLabel${user.isSubAdmin ? ' · 서브관리자' : ''}'),
                          // [DU491] grey500(흰 면 약 2.7) → 보조 글자색.
                          style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                        ),
                        if (!fits) ...[
                          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                          chip,
                        ],
                      ],
                    ),
                  ),
                  if (fits) chip,
                ],
              );
            }),
          ),
          Divider(height: ResponsiveHelper.spacing(context, 24)),
          Expanded(
            child: ListView(
              controller: controller,
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 20),
              ),
              children: [
                // 기본 정보
                _sectionTitle(context, '기본 정보'),
                _infoRow(context, Icons.phone_outlined, '연락처', user.effectivePhone ?? '-'),
                _infoRow(context, Icons.cake_outlined, '생년월일',
                  user.birthDate != null ? FormatHelper.formatDateISO(user.birthDate!) : '-'),
                _infoRow(context, Icons.person_outline, '성별', user.gender ?? '-'),
                if (user.businessName != null)
                  _infoRow(context, Icons.business_outlined, '사업체명', user.businessName!),
                _infoRow(context, Icons.calendar_today_outlined, '가입일',
                  user.createdAt != null ? FormatHelper.formatDateISO(user.createdAt!) : '-'),

                SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                // 신뢰도 & 근무 통계
                _sectionTitle(context, '신뢰도 & 근무'),
                _statsGrid(context),

                SizedBox(height: ResponsiveHelper.spacing(context, 16)),

                // 현재 상태
                _sectionTitle(context, '계정 상태'),
                // [NCB-52D] 상태 행 = 중립 면(background) · 중립 아이콘 · 설명 보조 글자 + 상태 이름만 작은 칩(C3).
                //   블랙리스트 error · 제한 warning · 확인 불가 warning · 승인대기 brand(목록 D1 과 같은 짝) · 정상 중립.
                //   조건 · 상태 이름 · 근거(사유) · 기간(KST) 문구는 그대로다.
                if (user.isBlacklisted)
                  _statusCard(
                    context,
                    icon: Icons.block,
                    chipBg: AppColors.errorBg,
                    chipInk: AppColors.errorDark,
                    label: '계정 이용 차단',
                    // [DU581 · 판정156 Q4] 자동 만료 없음 = '해제 전까지' · 당사자에게 보이는 사유(PP-SA-BLACKLIST)를 함께 적는다.
                    description: TextLayout.keepWords('해제 전까지 로그인·지원이 막혀요.\n사유: ${user.blacklistReason ?? '없음'}'),
                  ),
                if (user.isRestricted)
                  _statusCard(
                    context,
                    icon: Icons.timer_off_outlined,
                    chipBg: AppColors.warningBg,
                    chipInk: AppColors.warningDark,
                    label: '이용 제한 중',
                    // [.57] 어떤 제한이 언제까지인지 — 노쇼 자동과 수동·영구를 나눠 적는다(KST).
                    description: TextLayout.keepWords(_restrictionLines(user, restriction)),
                  ),
                if (_unreadable)
                  _statusCard(
                    context,
                    icon: Icons.help_outline,
                    chipBg: AppColors.warningBg,
                    chipInk: AppColors.warningDark,
                    label: '제한 상태 확인 불가',
                    description: TextLayout.keepWords('저장된 제한 값을 읽지 못했어요. 새로고침 후 다시 확인해 주세요.'),
                  ),
                if (user.isPending)
                  _statusCard(
                    context,
                    icon: Icons.hourglass_top_outlined,
                    chipBg: AppColors.brandSurface,
                    chipInk: AppColors.brand,
                    // [DU588b · 판정114 S052 가입대기] V3 는 조건이 갖춰지면 가입이 자동으로 끝난다(운영자 승인 단계 없음) — 사실대로 '가입 미완료' · 본인 절차 안내.
                    //   외국인 · 구체 원인은 단정하지 않는다(isPending 조건 · 상태 · 권한 그대로).
                    label: '가입 미완료',
                    description: TextLayout.keepWords('본인 가입 절차 확인 필요'),
                  ),
                if (!user.isBlacklisted && !user.isRestricted && !user.isPending && !_unreadable)
                  _statusCard(
                    context,
                    icon: Icons.check_circle_outline,
                    chipBg: AppColors.grey200,
                    chipInk: AppColors.grey700,
                    label: '정상',
                    description: '이용 제한 없음',
                  ),

                SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                // 계정 관리 — [DU588b · 판정169:69] 구역 제목 외래어 '액션' 정리(위 '계정 상태'와 짝 · 행동 단추 · 순서 그대로).
                _sectionTitle(context, '계정 관리'),
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),

                // SUPER_ADMIN 계정에 블랙리스트 버튼 노출 금지 — 자기 자신 또는 동급 계정 차단 방지
                // [NCB-52D] 이 버튼들은 확인 창을 여는 **진입**이다 — 중립 외곽선(C5). 위험색은 확인 창의 최종 실행 버튼에만 남는다.
                if (user.role != UserRole.SUPER_ADMIN)
                  _actionButton(
                    context,
                    icon: user.isBlacklisted ? Icons.lock_open : Icons.block,
                    label: user.isBlacklisted ? '계정 이용 차단 해제' : '계정 이용 차단하기',
                    onTap: onToggleBlacklist,
                  ),

                if (_canReset) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  _actionButton(
                    context,
                    icon: Icons.timer_off_outlined,
                    label: '노쇼 제한 해제 (기록 초기화)',
                    onTap: onClearRestriction,
                  ),
                ],
                // [.58] 수동·영구 제한은 노쇼 리셋·블랙리스트 해제와 다른 행동이다(서버도 따로).
                if (_canReleaseBase) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  _actionButton(
                    context,
                    icon: Icons.lock_clock_outlined,
                    label: '${restriction!.baseLabel} 해제',
                    onTap: onReleaseManual,
                  ),
                ],

                SizedBox(height: ResponsiveHelper.spacing(context, 24)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      child: Text(
        title,
        style: ResponsiveHelper.subtitleStyle(context).copyWith(
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _infoRow(BuildContext context, IconData icon, String label, String value) {
    final iconW = Icon(icon, size: ResponsiveHelper.iconSize(context, 16), color: AppColors.grey400);
    final gap = ResponsiveHelper.spacing(context, 8);
    final labelW = Text(
      label,
      // [DU491] grey500(흰 면 약 2.7) → 보조 글자색.
      style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
    );
    final valueW = Text(
      value,
      style: ResponsiveHelper.smallStyle(
        context,
        color: Theme.of(context).textTheme.bodyMedium?.color,
      ),
      overflow: TextOverflow.ellipsis,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      // [DU498] 라벨 칸이 고정 폭(64)이라 큰 글자에서 '연락/처' · '생년/월일' 로 음절이 끊겼다(B 320@2.0).
      //   한 줄(아이콘 + 라벨 64 + 값 · 배율 1.0 기준 220)이 안 들어가면 라벨을 값 위로 올린다. 넓은 화면은 그대로다.
      child: LayoutBuilder(builder: (context, c) {
        if (TextLayout.fits(context, c.maxWidth, 220)) {
          return Row(
            children: [
              iconW,
              SizedBox(width: gap),
              SizedBox(width: ResponsiveHelper.spacing(context, 64), child: labelW),
              Expanded(child: valueW),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [iconW, SizedBox(width: gap), Expanded(child: labelW)]),
            Padding(
              padding: EdgeInsets.only(left: ResponsiveHelper.iconSize(context, 16) + gap),
              child: valueW,
            ),
          ],
        );
      }),
    );
  }

  Widget _statsGrid(BuildContext context) {
    // [NCB-52D] 통계 칸 = 중립 면(background) · 값 textPrimary · 라벨 textSecondary(C1 · C2). 분류색 면(근무 초록 · 노쇼 빨강 ·
    //   지각 주황 · 평점 보라 · 리뷰 하늘)을 걷었다. 예전에 회색(grey400)으로 낮춰 보이던 값(노쇼 0 · 지각 3 이하)만 보조 글자로 남긴다(muted).
    //   값 · 단위 · '-' · 기준(노쇼 > 0 · 지각 > 3)은 그대로다.
    final items = [
      ('총 근무', '${user.totalWorkDays}일', false),
      ('노쇼', '${user.noShowCount}회', user.noShowCount <= 0),
      ('지각(90일)', '${user.recentLateCount}회', user.recentLateCount <= 3),
      ('평점', user.averageRating > 0 ? '${user.averageRating.toStringAsFixed(1)}점' : '-', false),
      ('리뷰', '${user.reviewCount}건', false),
    ];

    // [R7-P3-3 P33-X1] 타일 비율이 2.2 로 고정이라 글자 배율을 키우면 값·라벨
    //   두 줄이 타일보다 커졌다 — 320dp · 배율 2.0 에서 아래로 70~104px 넘쳤다.
    //   이 시트는 조치 대상을 확인하는 자리라 수치를 지우지 않는다. 대신
    //   글자가 커진 만큼 타일을 낮춘다.
    final textScale = MediaQuery.textScalerOf(context).scale(1.0);

    // [DU500] B(320@2.0)에서 3열 칸 폭이 라벨보다 좁아 '지각(9…' 로 말줄임됐다 — 한 줄 3칸(배율 1.0 기준 260)이
    //   안 들어가면 2열로 바꾼다(글자는 줄이지 않는다). 칸이 3/2 배 넓어지므로 비율도 3/cols 배 — 3열은 예전 식과 같다.
    return LayoutBuilder(builder: (context, c) {
    final cols = TextLayout.fits(context, c.maxWidth, 260) ? 3 : 2;
    final ratio = (2.2 * 3 / cols / (textScale <= 0 ? 1.0 : textScale)).clamp(1.0, 2.2 * 3 / cols);
    return GridView.count(
      crossAxisCount: cols,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: ResponsiveHelper.spacing(context, 8),
      crossAxisSpacing: ResponsiveHelper.spacing(context, 8),
      childAspectRatio: ratio,
      children: items.map((item) {
        final (label, value, muted) = item;
        return Container(
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ResponsiveHelper.bodyStyle(context).copyWith(
                  color: muted ? AppColors.textSecondary : AppColors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                // [DU491] grey500 → 보조 글자색.
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
              ),
            ],
          ),
        );
      }).toList(),
    );
    });
  }

  /// [NCB-52D] 상태 행 — 면 · 테두리 · 아이콘은 중립이고, 상태 이름만 [chipBg] 면 · [chipInk] 글자의 작은 칩이다(StatusBadge 짝).
  Widget _statusCard(
    BuildContext context, {
    required IconData icon,
    required Color chipBg,
    required Color chipInk,
    required String label,
    required String description,
  }) {
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Row(
        children: [
          Icon(icon, color: AppColors.textSecondary, size: ResponsiveHelper.iconSize(context, 20)),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 8),
                    vertical: ResponsiveHelper.spacing(context, 2),
                  ),
                  decoration: BoxDecoration(
                    color: chipBg,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    label,
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      color: chipInk,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  description,
                  semanticsLabel: TextLayout.plain(description),
                  // [DU491] grey600(경고 옅은 면 약 4.3) → 보조 글자색. [DU581] 13 → 보조 역할 14/1.45(PP-TYPOGRAPHY · 색 textSecondary 그대로).
                  style: AppTextStyles.roleSupport(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// [NCB-52D] 관리 행동 진입 — 모두 같은 중립 외곽선(흰 면 · border 선 · textPrimary 글자/아이콘 · C5).
  ///   예전 '블랙리스트 등록' 빨강 채움(흰 글자 약 3.7) · 해제류 주황/빨강 외곽선(약 2.2 · 3.7)을 걷었다. 최종 실행 버튼(확인 창)은 그대로다.
  Widget _actionButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: ResponsiveHelper.iconSize(context, 18)),
        // [DU581] 행동 이름이 길어져 큰 글자에서 낱말 안 줄바꿈을 막는다(읽는 이름 = 원문).
        label: Text(TextLayout.keepWords(label), semanticsLabel: label),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          padding: EdgeInsets.symmetric(
            vertical: ResponsiveHelper.spacing(context, 12),
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      ),
    );
  }
}

// [5A.2A] _TrustScoreDialog 제거 — 신뢰도 점수 시스템 폐기

// ── 사유 입력 다이얼로그 (블랙리스트/제재) ──────────────────────────────
class _ReasonDialog extends StatefulWidget {
  /// [R7-P3-3 P33-X1] 되돌리기 어려운 쓰기의 **대상**. 제목만으로는
  ///   누구에게 하는 일인지 알 수 없었다.
  final String subject;
  final String title;
  final String hint;
  final String confirmLabel;
  final Color confirmColor;

  /// [SA-AUDIT.49] 입력한 사유가 누구에게 보이는가 — 블랙리스트 사유는 로그인·지원 거절 안내에
  ///   그대로 실린다(서버 callableApplyToTO · 앱 로그인). null 이면 말하지 않는다.
  final String? visibilityNote;

  /// [.58] 대상 아래에 보일 처리 효과(해제할 것·남는 것). null 이면 없다.
  final String? detail;

  /// [.58] 서버가 요구하는 사유 최소 길이(수동 제한 해제 = 2자).
  final int minLength;

  const _ReasonDialog({
    required this.subject,
    required this.title,
    required this.hint,
    required this.confirmLabel,
    required this.confirmColor,
    this.visibilityNote,
    this.detail,
    this.minLength = 1,
  });

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
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
      title: widget.title,
      icon: Icons.edit_note_outlined,
      headerColor: widget.confirmColor,
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [R7-P3-3 P33-X1] 대상 먼저 — 이름이 같은 계정이 있어도 여기서 갈린다.
          // [.58] 큰 글자에서 '지원/자'처럼 음절이 끊겼다(Pixel 5 392·2.0) — 낱말 단위로 묶는다.
          Text(
            TextLayout.keepWords(widget.subject),
            semanticsLabel: widget.subject,
            // [DU581 · PP-TYPOGRAPHY] 대상 = 판단 글 16/1.5/700(13 grey700 → 본문 역할) · 효과 = 16 · 주의 = 보조 14.
            style: AppTextStyles.roleBody().copyWith(fontWeight: FontWeight.w700),
          ),
          if (widget.detail != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              TextLayout.keepWords(widget.detail!),
              semanticsLabel: widget.detail,
              style: AppTextStyles.roleBody(),
            ),
          ],
          if (widget.visibilityNote != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              TextLayout.keepWords(widget.visibilityNote!),
              semanticsLabel: widget.visibilityNote,
              style: AppTextStyles.roleSupport(color: AppColors.errorDark),
            ),
          ],
          SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          StyledDialogTextField(
            controller: _controller,
            labelText: '사유',
            hintText: widget.hint,
            prefixIcon: Icons.notes_outlined,
            maxLines: 3,
            maxLength: 500,
            autofocus: true,
          ),
        ],
      ),
      actions: [
        // [FC-06 FIX] autofocus: true — cancel도 unfocus 필수
        StyledDialogButton.cancel(onPressed: () {
          FocusManager.instance.primaryFocus?.unfocus();
          Navigator.pop(context);
        }),
        StyledDialogButton(
          text: widget.confirmLabel,
          onPressed: () {
            if (_controller.text.trim().length < widget.minLength) {
              ToastHelper.showError(widget.minLength > 1 ? '사유를 ${widget.minLength}자 이상 입력하세요' : '사유를 입력하세요');
              return;
            }
            // [FC-06 FIX] confirm도 unfocus 후 pop
            FocusManager.instance.primaryFocus?.unfocus();
            Navigator.pop(context, _controller.text.trim());
          },
          backgroundColor: widget.confirmColor,
          foregroundColor: Colors.white,
        ),
      ],
    );
  }
}
