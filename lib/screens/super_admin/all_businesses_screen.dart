import 'dart:async';

import 'package:flutter/material.dart';
// [R7-P1-7 P17-A] GradientScaffold → AppPageScaffold(D0 flat admin shell).
//   이 화면의 Colors.white 는 전부 **본문**이다(버튼 전경색·전체화면 이미지 뷰어
//   오버레이) — 헤더에 의존하는 색이 없어 위젯 이름만 바뀐다. 가로 스크롤 표의
//   열·행동·현재 선택 접근성은 좁은 폭 렌더로 따로 확인한다.
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../theme/app_colors.dart';
import '../../providers/user_provider.dart';
import '../../models/core/business_model.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/common/styled_container.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/format_helper.dart';
import '../../utils/text_layout.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../utils/loading_state_mixin.dart';
import '../../utils/action_guard.dart';
import '../../utils/keep_content_refresh.dart';
import '../../widgets/common/keep_content_body.dart';

/// ✅ 모든 사업장 조회·관리 화면 (최고관리자 전용)
class AllBusinessesScreen extends StatefulWidget {
  const AllBusinessesScreen({super.key});

  @override
  State<AllBusinessesScreen> createState() => _AllBusinessesScreenState();
}

class _AllBusinessesScreenState extends State<AllBusinessesScreen>
    with LoadingStateMixin, KeepContentRefreshMixin {
  final _listCF = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
      .httpsCallable('callableGetAllBusinesses',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
  final _bizCF = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
      .httpsCallable('callableManageBusiness',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));
  final _ownerInfoCF = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
      .httpsCallable('callableGetOwnerInfosByIds',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 30)));
  // [REG-2 SEC] 사업자등록증 Signed URL — license/ 경로는 Storage rules allow get: if false
  //   → CachedNetworkImage 직접 로드 불가. CF가 1시간 Signed URL 발급.
  final _licenseCF = FirebaseFunctions.instanceFor(region: 'asia-northeast3')
      .httpsCallable('callableGetBusinessLicenseSignedUrl',
          options: HttpsCallableOptions(timeout: const Duration(seconds: 15)));

  List<_BusinessWithOwner> _businesses = [];
  String _statusFilter = 'ALL'; // 'ALL' | 'PENDING' | 'ACTIVE' | 'DEACTIVATED'
  bool _isProcessing = false;

  static const _statusLabels = {
    'ALL': '전체',
    'PENDING': '승인대기',
    'ACTIVE': '활성',
    'DEACTIVATED': '비활성',
  };

  @override
  void initState() {
    super.initState();
    // 방어 심층화: AuthWrapper 분기 외 2차 역할 확인
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!context.read<UserProvider>().isSuperAdmin) {
        Navigator.pop(context);
        return;
      }
      _loadAllBusinesses();
    });
  }

  // [BA-53] 승인·처리 실패 뒤 다시 읽기가 사용자의 새로고침과 겹칠 수 있다 — 늦게 온 이전 결과가 최신 목록을 덮지 않게 한다.
  int _loadSeq = 0;

  Future<void> _loadAllBusinesses() async {
    // [L48 · impl_28] 처리 뒤 다시 읽기는 목록을 유지한다(잠금 + 얇은 진행 표시 · KeepContentRefreshMixin) — 첫 읽기·실패 화면만 전체 로딩 · 늦은 옛 응답 착지 0.
    //   실패하면 이전 목록을 그대로 둔다(예전 의미) — 그래서 실패 뒤에도 유지 대상이다.
    final seq = ++_loadSeq;
    final t = beginContentLoad(canKeep: true);
    if (!t.keep) setLoading(true);
    try {
      // [SA-01-CF] 슈퍼어드민 businesses list → callableGetAllBusinesses (Admin SDK, rate limiting 강제)
      final cfResult = await _listCF.call<Map<String, dynamic>>({});
      final rawList = (cfResult.data['businesses'] as List? ?? []).whereType<Map>().toList();

      final businesses = rawList.map((raw) {
        final id = raw['id'] as String? ?? '';
        final data = Map<String, dynamic>.from(raw)..remove('id');
        try { return BusinessModel.fromMap(data, id); } catch (_) { return null; }
      }).whereType<BusinessModel>().toList();

      // [CF-MIGRATED] USER list CF 정책 — callableGetOwnerInfosByIds
      final ownerIds = businesses.map((b) => b.ownerId).toSet().toList();
      // [REG-2] ownerMap에 legacy businessLicenseImageUrl 포함
      //   1순위: business.businessLicenseImageUrl (신규 — CF Signed URL 경유)
      //   2순위: owner.businessLicenseImageUrl (legacy — users/{uid} 토큰 URL 직접 접근 가능)
      final ownerMap = <String, ({String name, String email, String? licenseUrl})>{};
      if (ownerIds.isNotEmpty) {
        try {
          final result = await _ownerInfoCF
              .call<Map<String, dynamic>>({'ownerIds': ownerIds});
          final raw = result.data['owners'] as Map? ?? {};
          raw.forEach((k, v) {
            if (v is Map) {
              ownerMap[k.toString()] = (
                name: v['name'] as String? ?? '알 수 없음',
                email: v['email'] as String? ?? '',
                licenseUrl: v['businessLicenseImageUrl'] as String?,
              );
            }
          });
        } catch (_) {}
      }

      final ownerInfos = businesses
          .map((b) => ownerMap[b.ownerId] ??
              (name: '알 수 없음', email: '', licenseUrl: null))
          .toList();

      final result = List.generate(businesses.length, (i) {
        return _BusinessWithOwner(
          business: businesses[i],
          ownerName: ownerInfos[i].name,
          ownerEmail: ownerInfos[i].email,
          adminCount: businesses[i].adminIds.length,
          ownerLicenseUrl: ownerInfos[i].licenseUrl,
        );
      });

      if (!mounted || seq != _loadSeq) return;
      if (!isCurrentContentLoad(t.gen)) return; // [impl_28] 공용 차례 번호(위 _loadSeq 와 같은 뜻 · 7 화면 같은 꼴)
      setState(() => _businesses = result);
      setLoading(false);
      finishContentLoad(t.gen, shown: true);
    } catch (e) {
      if (!mounted || seq != _loadSeq) return;
      if (!isCurrentContentLoad(t.gen)) return; // [impl_28] 공용 차례 번호(위 _loadSeq 와 같은 뜻 · 7 화면 같은 꼴)
      debugPrint('⚠️ 사업장 목록 불러오기 실패: $e');
      // 이전 목록은 그대로 둔다(0건으로 바꾸지 않는다). 예외 원문 대신 다시 시도를 권한다.
      ToastHelper.showError('사업장 목록을 불러오지 못했습니다. 새로고침으로 다시 시도해 주세요.');
      setLoading(false);
      finishContentLoad(t.gen, shown: true); // 이전 목록이 그대로 보인다
    }
  }

  List<_BusinessWithOwner> get _filtered {
    return switch (_statusFilter) {
      'PENDING' => _businesses
          .where((b) => !b.business.isApproved && !b.business.isDeactivated)
          .toList(),
      'ACTIVE' => _businesses
          .where((b) => b.business.isApproved && !b.business.isDeactivated)
          .toList(),
      'DEACTIVATED' => _businesses.where((b) => b.business.isDeactivated).toList(),
      _ => _businesses,
    };
  }

  // ── 관리 액션 ──────────────────────────────────────────────────

  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_deactivateBusinessLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _deactivateBusiness(_BusinessWithOwner item) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('allBusinesses._isProcessing', this), () => _deactivateBusinessLocked(item));

  Future<void> _deactivateBusinessLocked(_BusinessWithOwner item) async {
    if (_isProcessing) return;
    final confirmed = await DialogHelper.showDangerConfirm(
      context,
      title: '사업장 비활성화',
      // [SA-AUDIT.49] 실제 결과와 다르던 안내('노출되지 않습니다' · '수동으로 마감')를 고쳤다.
      //   서버: 새 지원은 바로 막힌다. 진행 중 공고 마감·대기 지원 반려·시작 전 확정 근무 취소는
      //   비활성 트리거가 처리하는데, 사업장 문서 상태에 따라 실행되지 않을 수 있다(LOCAL 확인).
      //   어느 쪽이든 정리된 것은 재활성으로 되살아나지 않는다.
      // [SA-DEACT.50] 320·1.3 기기에서 '마감되/고'·'근/무'로 낱말 가운데가 끊겼다 — 낱말 단위 줄바꿈.
      message: TextLayout.keepWords('「${item.business.name}」을 비활성화하시겠습니까?\n\n'
          '• 새 지원이 바로 막힙니다.\n'
          '• 진행 중인 공고가 마감되고, 대기 중인 지원은 반려될 수 있습니다.\n'
          // [SA-DEACT.50] 정리 기준은 날짜가 아니라 출근 기록·정산이다(c50/dc50b.json) — 지난 근무도 기록이 없으면 취소된다.
          '• 출근 기록이 없는 확정 근무(지난 날짜 포함)가 취소되고, 서명 전 계약서는 무효가 될 수 있습니다. '
          '출근했거나 급여 정산이 시작된 근무는 그대로 둡니다.\n'
          '• 이렇게 정리된 공고·근무는 재활성화해도 되살아나지 않습니다.'),
      confirmText: '비활성화',
    );
    if (!confirmed || !mounted) return;
    setState(() => _isProcessing = true);

    try {
      // [V9-FIX] CF 이전 — deactivatedBy 감사 추적 서버 강제
      final res = await _bizCF.call<Map<String, dynamic>>({
        'action': 'deactivate',
        'businessId': item.business.id,
      });
      if (!mounted) return;
      // [SA-DEACT.50] 저장 성공 ≠ 정리 완료 — 정리는 서버 트리거가 뒤이어 한다. 반복 요청(서버 후보)은 새 처리처럼 말하지 않는다.
      ToastHelper.showSuccess(res.data['alreadyDeactivated'] == true
          ? '이미 비활성화된 사업장입니다'
          : '사업장을 비활성화했습니다. 공고·근무 정리는 서버에서 이어서 진행됩니다');
      await _loadAllBusinesses();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ToastHelper.showError('처리 실패: ${e.message}');
    } catch (e) {
      // [SA-AUDIT.49] 응답을 못 받았어도 서버는 반영했을 수 있다 — 예외 원문 대신 확인을 권하고 목록을 다시 읽는다.
      if (mounted) ToastHelper.showError('처리 결과를 확인하지 못했습니다. 목록에서 현재 상태를 확인해 주세요.');
      if (mounted) unawaited(_loadAllBusinesses());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_approveBusinessLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _approveBusiness(_BusinessWithOwner item) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('allBusinesses._isProcessing', this), () => _approveBusinessLocked(item));

  Future<void> _approveBusinessLocked(_BusinessWithOwner item) async {
    if (_isProcessing) return;
    // [REG-2] 사업자등록증이 전혀 없는 경우 warning confirm (CF 서버 차단 아님 — SUPER_ADMIN 재량 허용)
    // 1순위: business.businessLicenseImageUrl (신규), 2순위: ownerLicenseUrl (legacy)
    final hasLicense = item.business.businessLicenseImageUrl != null ||
        item.ownerLicenseUrl != null;
    final bool confirmed;
    // [BA-53] 대상이 분명하도록 사업자번호를 함께 보인다.
    final who = '「${item.business.name}」(사업자번호 ${item.business.formattedBusinessNumber})';
    if (!hasLicense) {
      // [BA-53] 서버는 등록증 파일이 없으면 승인하지 않는다(재량 승인 없음) — '그래도 승인'은 사실과 달랐다.
      confirmed = await DialogHelper.showConfirm(
        context,
        title: '사업자등록증 미확인',
        message: TextLayout.keepWords('$who의 사업자등록증을 이 화면에서 찾지 못했습니다.\n'
            '서버가 등록증 파일을 다시 확인하며, 없으면 승인되지 않습니다.'),
        confirmText: '확인 요청',
      );
    } else {
      confirmed = await DialogHelper.showConfirm(
        context,
        title: '사업장 승인',
        message: TextLayout.keepWords('$who을 승인하시겠습니까?\n승인 후 관리자가 공고를 등록할 수 있습니다.'),
        confirmText: '승인',
      );
    }
    if (!confirmed || !mounted) return;
    setState(() => _isProcessing = true);

    try {
      // [V9-FIX] CF 이전 — isApproved 법적 상태 전이 + approvedBy 서버 강제
      // [BA-53] 이 화면이 본 값(등록증·사업자번호·사업장명)을 함께 보낸다 — 그 사이 바뀌었으면 서버가 승인하지 않는다.
      final res = await _bizCF.call<Map<String, dynamic>>({
        'action': 'approve',
        'businessId': item.business.id,
        'expected': {
          'licenseUrl': item.business.businessLicenseImageUrl,
          'businessNumber': item.business.businessNumber,
          'name': item.business.name,
        },
      });
      if (!mounted) return;
      ToastHelper.showSuccess(res.data['alreadyApproved'] == true ? '이미 승인된 사업장입니다' : '사업장이 승인되었습니다');
      await _loadAllBusinesses();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      // 서버 문장(등록증 없음·검토 후 변경·운영 중지)을 그대로 보이고, 목록을 다시 읽어 현재 값으로 다시 검토하게 한다.
      ToastHelper.showError(TextLayout.keepWords(e.message ?? '승인하지 못했습니다.'));
      unawaited(_loadAllBusinesses());
    } catch (e) {
      // [SA-AUDIT.49] 응답을 못 받았어도 서버는 반영했을 수 있다 — 예외 원문 대신 확인을 권하고 목록을 다시 읽는다.
      if (mounted) ToastHelper.showError('처리 결과를 확인하지 못했습니다. 목록에서 현재 상태를 확인해 주세요.');
      if (mounted) unawaited(_loadAllBusinesses());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // [I9 · impl_16] 확인·선택 창(첫 await) **전에** 같은 화면의 같은 잠금 묶음을 잠근다 — 창이 뜨기 전 연타의
  //   두 번째 진입이 창·mutation 을 한 번 더 내지 않게(본문 `_reactivateBusinessLocked` 은 그대로 · 화면 플래그는 진행 표시로 유지).
  Future<void> _reactivateBusiness(_BusinessWithOwner item) =>
      ActionGuard.runVoid(ActionGuard.ownerKey('allBusinesses._isProcessing', this), () => _reactivateBusinessLocked(item));

  Future<void> _reactivateBusinessLocked(_BusinessWithOwner item) async {
    if (_isProcessing) return;
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: '사업장 재활성화',
      message: TextLayout.keepWords('「${item.business.name}」을 재활성화하시겠습니까?\n재활성화 후 다시 공고를 등록할 수 있습니다.\n'
          '비활성화 때 마감·취소된 공고와 근무는 되살아나지 않습니다.'),
      confirmText: '재활성화',
    );
    if (!confirmed || !mounted) return;
    setState(() => _isProcessing = true);

    try {
      // [V9-FIX] CF 이전 — reactivatedBy 감사 추적 서버 강제
      final res = await _bizCF.call<Map<String, dynamic>>({
        'action': 'reactivate',
        'businessId': item.business.id,
      });
      if (!mounted) return;
      ToastHelper.showSuccess(res.data['alreadyActive'] == true ? '이미 활성 상태인 사업장입니다' : '사업장이 재활성화되었습니다');
      await _loadAllBusinesses();
    } on FirebaseFunctionsException catch (e) {
      if (mounted) ToastHelper.showError('처리 실패: ${e.message}');
    } catch (e) {
      // [SA-AUDIT.49] 응답을 못 받았어도 서버는 반영했을 수 있다 — 예외 원문 대신 확인을 권하고 목록을 다시 읽는다.
      if (mounted) ToastHelper.showError('처리 결과를 확인하지 못했습니다. 목록에서 현재 상태를 확인해 주세요.');
      if (mounted) unawaited(_loadAllBusinesses());
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ── UI ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    int pendingCount = 0, activeCount = 0, deactivatedCount = 0;
    for (final b in _businesses) {
      if (b.business.isDeactivated) {
        deactivatedCount++;
      } else if (b.business.isApproved) {
        activeCount++;
      } else {
        pendingCount++;
      }
    }
    final filtered = _filtered;

    return AppPageScaffold(
      title: '전체 사업장 관리',
      // [R7-P1-7 P17-A] GradientScaffold 가 헤더에 그려 주던 새로고침을
      //   flat shell 의 actions 로 옮긴다 — 행동과 자리는 그대로다.
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          color: AppColors.textSecondary,
          tooltip: '새로고침',
          onPressed: _loadAllBusinesses,
        ),
      ],
      body: KeepContentBody(
        refreshing: refreshingKeep,
        child: isLoading
          ? const LoadingWidget(message: '사업장 목록을 불러오는 중...')
          : _businesses.isEmpty
              ? _buildEmptyState()
              : Column(
                  children: [
                    _buildFilterBar(pendingCount, activeCount, deactivatedCount),
                    Expanded(child: _buildBusinessList(filtered)),
                  ],
                ),
      ),
    );
  }

  Widget _buildFilterBar(int pendingCount, int activeCount, int deactivatedCount) {
    final counts = {'ALL': _businesses.length, 'PENDING': pendingCount, 'ACTIVE': activeCount, 'DEACTIVATED': deactivatedCount};
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      color: Theme.of(context).colorScheme.surface,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _statusLabels.entries.map((e) {
            final active = _statusFilter == e.key;
            return Padding(
              padding: EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
              child: FilterChip(
                label: Text('${e.value} (${counts[e.key]})'),
                selected: active,
                onSelected: (_) => setState(() => _statusFilter = e.key),
                selectedColor: Theme.of(context).primaryColor.withValues(alpha: 0.15),
                checkmarkColor: Theme.of(context).primaryColor,
                labelStyle: ResponsiveHelper.smallStyle(
                  context,
                  color: active ? Theme.of(context).primaryColor : null,
                ).copyWith(fontWeight: active ? FontWeight.bold : null),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const AppEmptyState(
      icon: Icons.business_outlined,
      title: '등록된 사업장이 없습니다',
    );
  }

  Widget _buildBusinessList(List<_BusinessWithOwner> list) {
    if (list.isEmpty) {
      return AppEmptyState(
        icon: Icons.business_outlined,
        title: switch (_statusFilter) {
          'PENDING' => '승인 대기 중인 사업장이 없습니다',
          'DEACTIVATED' => '비활성화된 사업장이 없습니다',
          _ => '활성 사업장이 없습니다',
        },
      );
    }
    // RefreshIndicator 제거: GradientScaffold.onRefresh와 중첩되면
    // 내부 것이 제스처를 가로채 외부 콜백 무력화 또는 중복 실행 경쟁 발생
    return ListView.builder(
      padding: ResponsiveHelper.listPadding(context),
      itemCount: list.length,
      itemBuilder: (context, index) => _buildBusinessCard(list[index]),
    );
  }

  Widget _buildBusinessCard(_BusinessWithOwner item) {
    final business = item.business;
    final isDeactivated = business.isDeactivated;

    return Card(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 16)),
      elevation: isDeactivated ? 0 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isDeactivated
            ? BorderSide(color: AppColors.grey300, width: 1)
            : BorderSide.none,
      ),
      child: Padding(
        padding: ResponsiveHelper.cardPadding(context),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 사업장명 + 상태 + 액션 메뉴
            Row(
              children: [
                Expanded(
                  child: Text(
                    business.name,
                    style: ResponsiveHelper.titleStyle(context).copyWith(
                      color: isDeactivated ? AppColors.grey400 : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // 상태 배지 — 비활성 / 승인대기 / 활성 3단계
                if (isDeactivated)
                  StyledBadge(
                    label: '비활성',
                    backgroundColor: AppColors.grey200,
                    textColor: AppColors.grey500,
                    fontSize: ResponsiveHelper.tinyStyle(context).fontSize!,
                  )
                else if (!business.isApproved)
                  StyledBadge(
                    label: '승인대기',
                    backgroundColor: AppColors.warning.withValues(alpha: 0.12),
                    textColor: AppColors.warning,
                    fontSize: ResponsiveHelper.tinyStyle(context).fontSize!,
                  )
                else
                  StyledBadge(
                    label: '활성',
                    backgroundColor: AppColors.success.withValues(alpha: 0.1),
                    textColor: AppColors.success,
                    fontSize: ResponsiveHelper.tinyStyle(context).fontSize!,
                  ),
                SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                // 관리 메뉴
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_vert,
                    size: ResponsiveHelper.iconSize(context, 20),
                    color: AppColors.grey500,
                  ),
                  onSelected: (value) {
                    if (value == 'approve') _approveBusiness(item);
                    if (value == 'deactivate') _deactivateBusiness(item);
                    if (value == 'reactivate') _reactivateBusiness(item);
                  },
                  itemBuilder: (ctx) => [
                    if (!isDeactivated && !business.isApproved)
                      const PopupMenuItem(
                        value: 'approve',
                        child: Row(
                          children: [
                            Icon(Icons.check_circle_outline, color: AppColors.textSecondary),
                            SizedBox(width: 8),
                            Text('승인'),
                          ],
                        ),
                      ),
                    if (!isDeactivated)
                      const PopupMenuItem(
                        value: 'deactivate',
                        child: Row(
                          children: [
                            Icon(Icons.pause_circle_outline, color: AppColors.textSecondary),
                            SizedBox(width: 8),
                            Text('비활성화'),
                          ],
                        ),
                      ),
                    if (isDeactivated)
                      const PopupMenuItem(
                        value: 'reactivate',
                        child: Row(
                          children: [
                            Icon(Icons.play_circle_outline, color: AppColors.textSecondary),
                            SizedBox(width: 8),
                            Text('재활성화'),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),

            // 비활성화 날짜 표시
            if (isDeactivated && business.deactivatedAt != null) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              Text(
                '비활성화: ${FormatHelper.formatDateISO(business.deactivatedAt!)}',
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.textTertiary),
              ),
            ],

            Divider(height: ResponsiveHelper.spacing(context, 24)),

            _buildInfoRow(
              icon: Icons.person,
              label: '관리자',
              value: '${item.ownerName}${item.ownerEmail.isNotEmpty ? " (${item.ownerEmail})" : ""}${item.adminCount > 1 ? " 외 ${item.adminCount - 1}명" : ""}',
              color: AppColors.textSecondary,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildInfoRow(
              icon: Icons.numbers,
              label: '사업자번호',
              value: business.formattedBusinessNumber,
              color: AppColors.textSecondary,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildLicenseRow(item),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildInfoRow(
              icon: Icons.category,
              label: '업종',
              value: '${business.category} / ${business.subCategory}',
              color: AppColors.textSecondary,
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            _buildInfoRow(
              icon: Icons.location_on,
              label: '주소',
              value: business.address,
              color: AppColors.textSecondary,
            ),
            if (business.phone != null) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 12)),
              _buildInfoRow(
                icon: Icons.phone,
                label: '연락처',
                value: business.phone!,
                color: AppColors.textSecondary,
              ),
            ],
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Text(
              '등록일: ${FormatHelper.formatDateISO(business.createdAt)}',
              style: ResponsiveHelper.tinyStyle(
                context,
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 사업자등록증 행
  ///
  /// [REG-2 SEC] 소스 우선순위:
  ///   1순위: business.businessLicenseImageUrl (신규 — license/ 경로, 토큰 없음)
  ///          → Storage rules allow get: if false → CachedNetworkImage 직접 불가
  ///          → "보기" 탭 시 callableGetBusinessLicenseSignedUrl CF → Signed URL
  ///   2순위: item.ownerLicenseUrl (legacy — users/{uid} 토큰 URL)
  ///          → 토큰 URL이므로 CachedNetworkImage 직접 로드 가능
  ///   둘 다 없으면: "미제출"
  Widget _buildLicenseRow(_BusinessWithOwner item) {
    final hasBusinessLicense = item.business.businessLicenseImageUrl != null;
    final hasOwnerLicense = item.ownerLicenseUrl != null;
    final hasAnyLicense = hasBusinessLicense || hasOwnerLicense;

    final labelText = hasBusinessLicense
        ? '제출됨'
        : hasOwnerLicense
            ? '제출됨 (레거시)'
            : '미제출';
    final labelColor = hasAnyLicense ? AppColors.success : AppColors.grey500;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          Icons.description_outlined,
          size: ResponsiveHelper.iconSize(context, 18),
          color: hasAnyLicense ? AppColors.success : AppColors.grey400,
        ),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Expanded(
          child: RichText(
            textScaler: MediaQuery.textScalerOf(context), // [SCALE-BALANCE.34] RichText 는 배율을 스스로 받지 않는다
            text: TextSpan(
              style: ResponsiveHelper.bodyStyle(
                context,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
              children: [
                const TextSpan(
                  text: '사업자등록증: ',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(
                  text: labelText,
                  style: TextStyle(color: labelColor),
                ),
              ],
            ),
          ),
        ),
        if (hasBusinessLicense)
          // 신규: Signed URL CF 경유
          GestureDetector(
            onTap: () => _showLicenseImageSigned(item.business.id),
            child: _buildViewButton(),
          )
        else if (hasOwnerLicense)
          // 레거시: 토큰 URL 직접 접근
          GestureDetector(
            onTap: () => _showLicenseImage(item.ownerLicenseUrl!),
            child: _buildViewButton(),
          ),
      ],
    );
  }

  Widget _buildViewButton() {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 8),
        vertical: ResponsiveHelper.spacing(context, 4),
      ),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
      ),
      child: Text(
        '보기',
        style: ResponsiveHelper.smallStyle(
          context,
          color: AppColors.success,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 신규 사업자등록증 Signed URL 조회 → 이미지 다이얼로그 표시
  Future<void> _showLicenseImageSigned(String businessId) async {
    if (!mounted) return;
    final rootNav = Navigator.of(context, rootNavigator: true);
    // 로딩 다이얼로그 표시
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    String? signedUrl;
    String? errorMsg;
    try {
      final result = await _licenseCF
          .call<Map<String, dynamic>>({'businessId': businessId});
      signedUrl = result.data['signedUrl'] as String?;
    } on FirebaseFunctionsException catch (e) {
      errorMsg = e.code == 'not-found'
          ? '사업자등록증이 등록되지 않은 사업장입니다'
          : '이미지를 불러오는데 실패했습니다: ${e.message}';
    } catch (e) {
      errorMsg = '이미지를 불러오는데 실패했습니다';
    } finally {
      if (rootNav.mounted && rootNav.canPop()) rootNav.pop();
    }
    if (!mounted) return;
    if (errorMsg != null) {
      ToastHelper.showError(errorMsg);
      return;
    }
    if (signedUrl == null) {
      ToastHelper.showError('이미지를 불러올 수 없습니다');
      return;
    }
    _showLicenseImage(signedUrl);
  }

  /// 사업자등록증 이미지 전체화면 다이얼로그
  void _showLicenseImage(String url) {
    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black87,
        insetPadding: const EdgeInsets.all(16),
        child: Stack(
          children: [
            InteractiveViewer(
              // [AUD-10 M3 · impl_70] 사업자등록증(대표자 개인정보 포함)은 디스크 캐시에 남기지 않는다 —
              //   신분증·통장사본 뷰어(ImageHelper noCache)와 같은 계약. 예전 CachedNetworkImage 는 Signed URL
              //   이미지를 기본 디스크 캐시에 최대 30일 남겼다. Image.network = 메모리 캐시만.
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : const Center(
                        child: CircularProgressIndicator(color: Colors.white),
                      ),
                errorBuilder: (_, __, ___) => const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, color: Colors.white54, size: 48),
                      SizedBox(height: 8),
                      Text(
                        '이미지를 불러올 수 없습니다',
                        style: TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.close, color: Colors.white, size: 20),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: ResponsiveHelper.iconSize(context, 18), color: color),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Expanded(
          child: RichText(
            textScaler: MediaQuery.textScalerOf(context), // [SCALE-BALANCE.34] RichText 는 배율을 스스로 받지 않는다
            text: TextSpan(
              style: ResponsiveHelper.bodyStyle(
                context,
                color: Theme.of(context).textTheme.bodyMedium?.color,
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                TextSpan(text: value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BusinessWithOwner {
  final BusinessModel business;
  final String ownerName;
  final String ownerEmail;
  final int adminCount;
  // [REG-2] legacy 사업자등록증 URL — users/{uid}.businessLicenseImageUrl
  // business.businessLicenseImageUrl(신규)이 없는 레거시 사업장 SUPER_ADMIN 폴백 표시용
  final String? ownerLicenseUrl;

  _BusinessWithOwner({
    required this.business,
    required this.ownerName,
    required this.ownerEmail,
    required this.adminCount,
    this.ownerLicenseUrl,
  });
}
