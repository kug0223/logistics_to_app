import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_functions/cloud_functions.dart';

// Models
import '../../models/core/business_model.dart';

// Providers
import '../../providers/user_provider.dart';

// Services

// Utils
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/image_helper.dart';
import '../../utils/text_layout.dart';

// Widgets
import '../../widgets/common/common_widgets.dart';
import '../../widgets/common/first_line_icon.dart';
import '../../widgets/common/keep_words_text.dart';
import '../../utils/navigation_helper.dart';

// Screen
import 'business_detail_screen.dart';
import 'business_form_screen.dart';
import 'business_list_reads.dart';
import 'to_management/create_to_screen.dart';
import '../../widgets/common/app_menu_sheet.dart';
import '../../theme/app_colors.dart';
import '../../theme/concept_tokens.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/notification_badge.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/loading_widget.dart';
import '../common/notification_screen.dart';

/// 📋 내 사업장 관리 화면 (관리자 전용)
class BusinessListScreen extends StatefulWidget {
  /// [BUSINESS-ARCHIVE] 서버 운영 종료 호출 — 테스트가 바꿔 끼울 수 있다.
  ///   두 번째 인자는 사용자가 확인한 사전 조회다. 서버는 실행 직전 원장을 다시 세어
  ///   이것과 다르면 종료하지 않는다.
  @visibleForTesting
  static Future<void> Function(String businessId, Map<String, dynamic> expected)?
      debugArchive;

  /// [BUSINESS-ARCHIVE] 서버 사전 조회(preview) — 테스트가 바꿔 끼울 수 있다.
  @visibleForTesting
  static Future<Map<String, dynamic>> Function(String businessId)? debugPreview;

  /// 사전 조회의 건수 키 — 하나라도 없으면 "모른다".
  static const _previewKeys = <String>[
    'inProgressShifts', 'ongoingLongTerm', 'contractPendingWorked',
    'openPostings', 'pendingApplications', 'invites', 'futureConfirmed', 'contractsVoided',
    'keptStarted', 'contractsKept', 'unpaidWages', 'workedUncalculated',
    'interimPending', 'interimApproved',
  ];

  static Map<String, int>? _counts(Map<String, dynamic>? preview) {
    if (preview == null || preview['truncated'] is! bool) return null;
    final out = <String, int>{};
    for (final k in _previewKeys) {
      final v = preview[k];
      if (v is! int || v < 0) return null;
      out[k] = v;
    }
    return out;
  }

  /// [BUSINESS-ARCHIVE] 사전 해결이 필요하면 그 안내, 아니면 null(순수 함수).
  ///
  ///   진행 중 출근(퇴근 전)과 진행 중 장기 근무는 종료가 일괄 취소하지 않는다 —
  ///   장기 근무를 어떻게 끝낼지 정해진 규칙이 없다. 기존 경로로 먼저 정리해야 한다.
  ///   건수를 모르면(키 누락·상한 초과) 역시 종료할 수 없다.
  @visibleForTesting
  static String? archiveBlockedMessage(Map<String, dynamic>? preview) {
    final c = _counts(preview);
    if (c == null) return '정리할 근무를 모두 확인하지 못해 지금은 종료할 수 없어요.\n잠시 후 다시 시도해 주세요.';
    if (preview!['truncated'] == true) {
      // [4단계 정정] 사용자가 처리할 일이 아니다 — 서버가 건수를 끝까지 세지 못한 "판정 불가"다.
      return '기록이 많아 정리 대상을 끝까지 확인하지 못했어요.\n'
          '확인되지 않은 상태로는 운영을 종료하지 않아요. 따로 처리하실 일은 없어요.';
    }
    final lines = <String>[];
    if (c['inProgressShifts']! > 0) {
      lines.add('· 출근 후 아직 퇴근하지 않은 근무 ${c['inProgressShifts']}건 — 퇴근 처리 후 종료할 수 있어요');
    }
    if (c['ongoingLongTerm']! > 0) {
      // [4단계 정정] 기존 해지는 종료일이 계약 종료일(workEndDate)로 고정돼 앞당길 수 없다 —
      //   실행할 수 없는 해결 경로를 안내하지 않는다. 앞당겨 끝내는 절차는 제품 결정 전이다.
      lines.add('· 진행 중인 장기 근무 ${c['ongoingLongTerm']}건 — 지금은 계약 기간 중에 '
          '앞당겨 끝내는 기능이 없어요. 계약 기간이 끝나거나 근로자의 퇴사가 처리된 뒤 '
          '운영을 종료할 수 있어요');
    }
    if (c['contractPendingWorked']! > 0) {
      // [ARCHIVE-CLOSED-TO-PREFLIGHT] 실제로 일했는데 계약서 서명 전(계약 대기)인 근무.
      //   종료 뒤에는 서명·확정·취소 어느 것도 할 수 없다 — 지금 실행할 수 있는 길은
      //   계약서를 보내 근로자 서명을 받는 것 하나다(계약 관리 → 미발송·서명 대기).
      lines.add('· 계약서 서명 전에 이미 일한 근무 ${c['contractPendingWorked']}건 — 계약 관리에서 '
          '계약서를 보내 근로자 서명을 받은 뒤 운영을 종료할 수 있어요');
    }
    if (lines.isEmpty) return null;
    return '운영을 종료하기 전에 먼저 정리해야 할 근무가 있어요.\n\n${lines.join('\n')}';
  }

  /// [BUSINESS-ARCHIVE] 사전 조회 결과로 확인 문구를 만든다(순수 함수).
  ///
  ///   건수 중 하나라도 없거나 0 이상의 정수가 아니면 null — 모르는 것을 0건으로
  ///   말하지 않는다. 사전 해결 항목이 남아 있어도 null(확인창을 띄우지 않는다).
  @visibleForTesting
  static String? archiveConfirmMessage(String name, Map<String, dynamic>? preview) {
    final c = _counts(preview);
    if (c == null || archiveBlockedMessage(preview) != null) return null;
    final b = StringBuffer()
      ..writeln('$name 운영을 종료할까요? 일시 정지가 아니라 앞으로의 운영을 마치는 거예요.') // [DU400 후보] 해요체
      ..writeln()
      ..writeln('종료하면서 정리되는 것 (근로자에게 알림)')
      ..writeln('· 모집 중·예약 공고 ${c['openPostings']}건 마감')
      ..writeln('· 대기 중인 지원 ${c['pendingApplications']}건 마감 (마감된 공고 포함)')
      ..writeln('· 초대 ${c['invites']}건 철회')
      ..writeln('· 시작 전 확정·계약 대기 근무 ${c['futureConfirmed']}건 취소')
      ..writeln('· 취소되는 근무의 미서명 계약 ${c['contractsVoided']}건 무효')
      ..writeln()
      ..writeln('종료 후에도 남아 계속 처리하는 것')
      ..writeln('· 이미 시작했거나 지난 확정 근무 ${c['keptStarted']}건 · 그 미서명 계약 ${c['contractsKept']}건')
      ..writeln('· 미지급 급여 ${c['unpaidWages']}건 · 계산 전 근무 ${c['workedUncalculated']}건')
      ..writeln('· 중간정산 대기 ${c['interimPending']}건 · 승인 후 미이체 ${c['interimApproved']}건')
      ..write('기록은 지워지지 않고, 급여 탭과 계약 관리에서 계속 처리할 수 있어요.'); // [DU400 후보] 해요체
    return b.toString();
  }

  const BusinessListScreen({super.key, this.reads});

  /// [R7-PREDEVICE-STABILIZATION.1A] 읽기 경계. production 은 null —
  ///   기존 서비스 호출을 그대로 쓴다. 테스트만 주입해 **실패와 0개**를
  ///   각각 재현한다.
  final BusinessListReads? reads;

  @override
  State<BusinessListScreen> createState() => _BusinessListScreenState();
}

class _BusinessListScreenState extends State<BusinessListScreen> {
  // 읽기는 전부 이 경계를 지난다 — 화면이 서비스를 직접 쥐지 않는다.
  late final BusinessListReads _reads =
      widget.reads ?? BusinessListReads.of();
  List<BusinessModel> _businesses = [];
  bool _isLoading = true; // 첫 빌드부터 로딩 표시 — 빈 상태 flash 방지

  /// [R7-PREDEVICE-STABILIZATION.1A] 조회 **실패**와 사업장 **0개**는 다르다.
  ///   이 값이 없던 동안 읽기 실패는 "등록된 사업장이 없습니다" 로 보였고,
  ///   SubAdmin 에게는 거기에 등록 CTA 까지 붙어 있었다.
  bool _loadFailed = false;
  bool _isDeleting = false;
  bool _fetchInProgress = false; // 중복 호출 방지 (_isLoading과 분리)

  // [H-3 E N2] 운영 종료 결과 — overlay 토스트 대신 본문 위 결과 띠 하나(둘째 카드 · 버튼 가림 0).
  //   성공 2s(successBg 면 · successDark 글 · check) / 오류 4s(errorBg 면 · errorDark 글 · error_outline) · 다음 결과가 바로 교체 · 만료 · dispose 로만 정리.
  //   성공 뒤 재조회(로딩 · 목록 교체)는 이 결과를 지우지 않는다 — 결과는 행동의 것이지 조회의 것이 아니다.
  ({String text, bool error})? _archiveResult;
  Timer? _archiveResultTimer;

  void _showArchiveResult(String text, {required bool error}) {
    _archiveResultTimer?.cancel();
    setState(() => _archiveResult = (text: text, error: error));
    _archiveResultTimer = Timer(Duration(seconds: error ? 4 : 2), () {
      if (mounted) setState(() => _archiveResult = null);
    });
  }

  // [판정51] 옅은 의미 바탕 + 진한 글 · 아이콘(원문 label 1) — Standards §12.2 넓은 면은 진한 의미색으로 채우지 않는다. 본문 안이라 다른 내용을 덮지 않는다.
  //   successDark / successBg 6.47:1 · errorDark / errorBg 5.80:1. 반경 · 패딩 · 아이콘 · 간격 · 글 · 줄바꿈 그대로(테두리 추가 0).
  Widget _archiveResultBand(({String text, bool error}) r) {
    final ink = r.error ? AppColors.errorDark : AppColors.successDark;
    final style = TextStyle(color: ink, fontSize: 14, fontWeight: FontWeight.w500);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: r.error ? AppColors.errorBg : AppColors.successBg, borderRadius: BorderRadius.circular(12)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FirstLineIcon(r.error ? Icons.error_outline : Icons.check_circle_outline, size: 20, color: ink, textStyle: style),
          const SizedBox(width: 12),
          Expanded(child: KeepWordsText(r.text, style: style)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _archiveResultTimer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _loadBusinesses();
  }

  /// 사업장 목록 로드
  Future<void> _loadBusinesses({bool forceServer = false}) async {
    if (!mounted || _fetchInProgress) return;
    _fetchInProgress = true;
    if (!_isLoading) setState(() => _isLoading = true);

    try {
      final userProvider = context.read<UserProvider>();
      final ownerId = userProvider.currentUser?.uid;

      if (ownerId == null) {
        // [R7-PREDEVICE-STABILIZATION.1A] 로그인 정보를 읽지 못한 것은
        //   "사업장 0개" 가 아니다. 예전에는 그냥 return 해서 빈 상태가
        //   그려졌고, 화면은 "등록된 사업장이 없습니다" 라고 말했다.
        if (mounted) setState(() => _loadFailed = true);
        return;
      }

      List<BusinessModel> businesses;

      // SubAdmin은 adminIds에 없으므로 effectiveBusinessId로 직접 조회
      //
      // [R7-PREDEVICE-STABILIZATION.1A] `OrThrow` 변형을 쓴다.
      //   `getBusinessById`/`getBusinessesByIds` 는 실패를 각각 null·빈
      //   목록으로 바꿔 삼킨다. 그래서 조회가 깨져도 catch 가 돌지 않고,
      //   토스트조차 뜨지 않은 채 "사업장 없음" 이 그려졌다 — 읽기 실패가
      //   전혀 다른 사실로 번지는 경로다. 서비스 주석도 "실패와 0개를
      //   구분해야 하는 호출부는 OrThrow 를 쓴다" 고 적어 두었다.
      final effectiveBizId = userProvider.effectiveBusinessId;
      if (userProvider.isSubAdmin && effectiveBizId != null) {
        // null 은 **부재**다(문서 없음) — 실패는 throw 로 올라온다.
        final biz = await _reads.businessById(effectiveBizId);
        businesses = biz != null ? [biz] : [];
      } else {
        final managedIds = userProvider.currentUser?.managedBusinessIds ?? [];
        businesses = await _reads.businessesByIds(managedIds);
      }

      if (!mounted) return;
      setState(() {
        _businesses = businesses;
        _loadFailed = false;
      });
    } catch (e) {
      debugPrint('❌ 사업장 로드 실패: $e');
      if (mounted) {
        setState(() => _loadFailed = true);
        // [DU410] 토스트를 띄우지 않는다 — `_loadFailed` 면 오류 본문(제목 · 부제 · 다시 시도)이 늘 그려져
        //   같은 말을 두 번 하게 된다. 로그인 정보를 읽지 못한 경로(위 ownerId == null)도 토스트가 없다.
      }
    } finally {
      _fetchInProgress = false;
      if (mounted) setState(() => _isLoading = false);
    }
  }


  /// [BUSINESS-ARCHIVE] 사업장 운영 종료(비활성화·보관).
  ///
  /// 이전에는 사업장 문서를 앱이 직접 지웠고, 서버 cascade 가 공고를 하드 삭제해
  /// 모든 지원서(확정·실근무 포함)와 중간정산·급여 변경 이력까지 사라졌다. 이제
  /// 서버(callableArchiveOwnBusiness)가 비활성화하고, 진행 중인 공고·지원·초대·
  /// 미서명 계약은 감사 가능한 상태 전이로 정리된다. 기록은 지우지 않는다.
  Future<void> _archiveBusiness(BusinessModel business) async {
    if (_isDeleting) return;
    setState(() => _isDeleting = true);
    try {
      // 1) 사전 조회 — 실패하면 0건으로 보이지 않고 여기서 멈춘다.
      Map<String, dynamic>? preview;
      try {
        final fetch = BusinessListScreen.debugPreview ??
            (String id) async {
              final r = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                  .httpsCallable('callableArchiveOwnBusiness')
                  .call<Map<String, dynamic>>({'businessId': id, 'preview': true});
              final p = r.data['preview'];
              return p is Map ? Map<String, dynamic>.from(p) : <String, dynamic>{};
            };
        preview = await fetch(business.id);
      } catch (e) {
        debugPrint('❌ 운영 종료 사전 조회 실패: $e');
      }
      if (!mounted) return;
      // 2) 확인 → 실행. 서버가 실행 직전 다시 센 결과가 다르면 새 결과로 다시 묻는다
      //    (최대 3번 — 계속 바뀌면 멈춘다).
      for (var round = 0; round < 3; round++) {
        final blocked = BusinessListScreen.archiveBlockedMessage(preview);
        if (blocked != null) {
          await DialogHelper.showError(context, title: '사업장 운영 종료', message: blocked);
          return;
        }
        final message = BusinessListScreen.archiveConfirmMessage(business.name, preview);
        if (message == null) {
          _showArchiveResult('정리될 공고·지원·근무를 확인하지 못했어요. 잠시 후 다시 시도해 주세요', error: true); // [H-3 E N2]
          return;
        }
        final confirmed = await DialogHelper.showDangerConfirm(
          context,
          title: round == 0 ? '사업장 운영 종료' : '정리 대상이 바뀌었어요',
          message: message,
          confirmText: '운영 종료',
        );
        if (confirmed != true || !mounted) return;
        final archive = BusinessListScreen.debugArchive ??
            (String id, Map<String, dynamic> expected) =>
                FirebaseFunctions.instanceFor(region: 'asia-northeast3')
                    .httpsCallable('callableArchiveOwnBusiness')
                    .call<Map<String, dynamic>>({'businessId': id, 'expected': expected});
        try {
          await archive(business.id, preview!);
        } on FirebaseFunctionsException catch (e) {
          final d = e.details;
          final code = d is Map ? d['code'] : null;
          final fresh = d is Map && d['preview'] is Map
              ? Map<String, dynamic>.from(d['preview'] as Map)
              : null;
          if ((code == 'ARCHIVE_PREVIEW_CHANGED' || code == 'ARCHIVE_BLOCKED') && fresh != null) {
            if (!mounted) return;
            preview = fresh; // 새 결과로 다시 보여 준다
            continue;
          }
          rethrow;
        }
        if (!mounted) return;
        _showArchiveResult('사업장 운영을 종료했어요', error: false); // [H-3 E N2]
        _loadBusinesses(forceServer: true);
        return;
      }
      if (mounted) _showArchiveResult('정리 대상이 계속 바뀌고 있어요. 잠시 후 다시 시도해 주세요', error: true); // [H-3 E N2]
    } catch (e) {
      debugPrint('❌ 사업장 운영 종료 실패: $e');
      if (mounted) _showArchiveResult('사업장 운영을 종료하지 못했어요', error: true); // [H-3 E N2]
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final userProvider = context.read<UserProvider>();
    final isSubAdmin = userProvider.isSubAdmin;

    return AppPageScaffold(
      title: '내 사업장 관리',
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => _loadBusinesses(forceServer: true),
          color: AppColors.textSecondary,
          tooltip: '새로고침',
        ),
        IconButton(
          icon: const Icon(Icons.home_outlined),
          onPressed: () => NavigationHelper.goHome(context),
          color: AppColors.textSecondary,
          tooltip: '홈',
        ),
        NotificationBadge(
          child: IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationScreen()),
            ),
            color: AppColors.textSecondary,
          ),
        ),
      ],
      // [R7-PREDEVICE-STABILIZATION.1A] ERROR → SUCCESS_ZERO → 목록 순서.
      //   실패를 먼저 가려내야 "없음" 이 **정말 없음** 을 뜻한다.
      // [H-3 E N2] 본문 트리는 늘 Column[결과 띠?, Expanded(기존 본문)] — 성공 뒤 재조회 로딩 중에도 띠가 남는다.
      body: Column(
        children: [
          if (_archiveResult != null)
            Padding(
              padding: EdgeInsets.fromLTRB(ResponsiveHelper.spacing(context, 16), ResponsiveHelper.spacing(context, 8), ResponsiveHelper.spacing(context, 16), 0),
              child: _archiveResultBand(_archiveResult!),
            ),
          Expanded(
            child: _isLoading
                ? const LoadingWidget()
                : _loadFailed
                    ? _buildErrorState(context)
                    : _businesses.isEmpty
                        ? _buildEmptyState(context, isSubAdmin)
                        : _buildBusinessList(context, theme, isSubAdmin),
          ),
        ],
      ),
    );
  }

  /// 조회 실패 — 역할과 무관하다. 다시 시도할 수 있게 해 준다.
  ///
  ///   여기서 역할별로 다른 말을 하지 않는다. 실패는 권한 문제일 수도
  ///   있지만 네트워크일 수도 있고, 화면은 그 둘을 구별할 수 없다.
  ///   **모르는 것을 아는 척하지 않는다.**
  Widget _buildErrorState(BuildContext context) {
    return AppEmptyState(
      icon: Icons.cloud_off_outlined,
      iconColor: AppColors.warning,
      title: '사업장 목록을 불러오지 못했어요',
      subtitle: '잠시 후 다시 시도해 주세요',
      action: CommonWidgets.primaryButton(
        context: context,
        text: '다시 시도',
        icon: Icons.refresh,
        onPressed: () => _loadBusinesses(forceServer: true),
      ),
    );
  }

  /// 빈 상태
  ///
  /// [R7-PREDEVICE-STABILIZATION.1] SubAdmin 에게 사업장 등록 CTA 를 보여주고
  ///   있었다. 눌러서 양식을 끝까지 채워도 저장되지 않는다 —
  ///   `firestore.rules` 의 `businesses` create 는 `isBusinessAdmin()`,
  ///   update 는 `isAdminOf()` 를 요구하므로 SubAdmin 은 서버에서 거부된다.
  ///   나머지 네 진입구(목록 추가 타일·카드 수정 메뉴·상세 수정·홈 STATE A
  ///   배너·홈 설정 타일)는 이미 `isSubAdmin` 으로 막혀 있었고 이 빈 상태만
  ///   빠져 있었다.
  ///
  ///   SubAdmin 이 빈 상태에 도달하는 경로는 셋이다 — 배정이 없음, 배정된
  ///   사업장이 사라짐, **조회 실패**(`_loadBusinesses` catch 는 `_businesses`
  ///   를 비운 채로 둔다). 어느 쪽이든 할 수 있는 일이 "사업장 등록" 은
  ///   아니므로, 권한을 준 관리자에게 확인하라고 말한다.
  Widget _buildEmptyState(BuildContext context, bool isSubAdmin) {
    if (isSubAdmin) {
      return const AppEmptyState(
        icon: Icons.business_outlined,
        title: '배정된 사업장이 없어요',
        subtitle: '권한을 부여한 관리자에게 사업장 배정을 확인해 주세요',
      );
    }
    return AppEmptyState(
      icon: Icons.business_outlined,
      title: '등록된 사업장이 없어요',
      subtitle: '사업장을 등록하고 공고를 관리해 보세요',
      action: CommonWidgets.primaryButton(
        context: context,
        text: '사업장 등록하기',
        icon: Icons.add_business,
        onPressed: _navigateToBusinessForm,
      ),
    );
  }

  /// 사업장 리스트
  Widget _buildBusinessList(BuildContext context, ThemeData theme, bool isSubAdmin) {
    // SubAdmin은 사업장 추가 버튼 불필요
    final itemCount = isSubAdmin ? _businesses.length : _businesses.length + 1;
    return ListView.builder(
      key: const PageStorageKey<String>('business_list'), // [H-3 E] 재조회로 다시 붙어도 이전 offset(위쪽 기준 · 새 길이에 clamp)
      padding: ResponsiveHelper.listPadding(context),
      itemCount: itemCount,
      itemBuilder: (context, index) {
        if (index == _businesses.length) {
          return _buildAddButton(context, theme);
        }

        final business = _businesses[index];
        return _buildBusinessCard(context, theme, business);
      },
    );
  }

  /// 사업장 카드
  Widget _buildBusinessCard(
    BuildContext context,
    ThemeData theme,
    BusinessModel business,
  ) {
    return Container(
      margin: EdgeInsets.only(
        bottom: ResponsiveHelper.spacing(context, 16),
      ),
      // [DU392] 카드 표면 = 시안 raised(흰 · 반경 16 · 옅은 테두리 1 · 낮은 그림자 1). 승인 대기는 배지가 말한다(빨강 외곽선 제거).
      decoration: ConceptSurface.raised(),
      child: InkWell(
        onTap: () {
          NavigationHelper.push<bool>(
            context,
            destination: BusinessDetailScreen(business: business),
            onReturn: (result) {
              if (result == true && mounted) _loadBusinesses(forceServer: true);
            },
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: ResponsiveHelper.listPadding(context),
          // [DU387] 큰 글자(배율 ≥ 1.3)에서는 한 줄 [이미지 · 정보 · 더보기]가 정보 칸을 거의 없앴다(B 이름 폭 20–49px · 이름이 보이지 않음).
          //   그때는 [이미지 · 더보기] 줄 아래로 정보를 카드 폭으로 쌓는다 — 글자를 줄이지 않는 배치 전환.
          child: Builder(builder: (context) {
            final info = _buildBusinessInfo(context, theme, business);
            final large = MediaQuery.textScalerOf(context).scale(16) / 16 >= 1.3;
            if (large) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildBusinessImage(context, business),
                      const Spacer(),
                      _buildMoreMenu(context, theme, business),
                    ],
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  info,
                ],
              );
            }
            return Row(
              children: [
                // 이미지
                _buildBusinessImage(context, business),
                SizedBox(width: ResponsiveHelper.spacing(context, 16)),
                // 정보
                Expanded(child: info),
                // 더보기 메뉴
                _buildMoreMenu(context, theme, business),
              ],
            );
          }),
        ),
      ),
    );
  }

  /// [DU387] 사업장 카드 정보 — 이름 · 상태 배지 / 주소 / 빠른 정보. 글자 크기 · 색 · 문구는 그대로, 배치만 바꾼다.
  ///   사업장명은 말줄임 없이 낱말 단위로 줄을 바꾼다(identity 표시 · 의미는 원문).
  ///   상태 배지는 이름 뒤에 들어가면 같은 줄, 아니면 다음 줄(Wrap). 주소도 말줄임 없이 낱말 사이에서 줄을 바꾼다.
  Widget _buildBusinessInfo(BuildContext context, ThemeData theme, BusinessModel business) {
    final addressStyle = ResponsiveHelper.smallStyle(context).copyWith(
      color: AppColors.grey600,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 사업장명 + 승인 상태
        Wrap(
          spacing: ResponsiveHelper.spacing(context, 8),
          runSpacing: ResponsiveHelper.spacing(context, 4),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              TextLayout.identity(business.name),
              semanticsLabel: business.name,
              style: ResponsiveHelper.subtitleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            // 승인 상태 배지
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: ResponsiveHelper.spacing(context, 8),
                vertical: ResponsiveHelper.spacing(context, 4),
              ),
              // [DU392] 상태 필 — 반경 8 · 13/700, 의미 짝(승인 = 낮은 강조 brand · 승인 대기 = 주의 · 운영 종료/중지 = 중립)
              decoration: BoxDecoration(
                color: business.isDeactivated
                    ? AppColors.grey100
                    : business.isApproved
                        ? AppColors.brandSurface
                        : AppColors.warningBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                // [BUSINESS-ARCHIVE] 운영 종료를 '승인대기'로 말하지 않는다.
                business.operationStatusLabel,
                style: ConceptText.pill(business.isDeactivated
                    ? AppColors.textSecondary
                    : business.isApproved
                        ? AppColors.brand
                        : AppColors.warningDark),
              ),
            ),
          ],
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 6)),

        // 주소
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FirstLineIcon(
              Icons.location_on_outlined,
              size: ResponsiveHelper.iconSize(context, 14),
              color: AppColors.grey600,
              textStyle: addressStyle,
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
            Expanded(
              child: Text(
                TextLayout.keepWords(business.address),
                semanticsLabel: business.address,
                style: addressStyle,
              ),
            ),
          ],
        ),

        SizedBox(height: ResponsiveHelper.spacing(context, 8)),

        // 빠른 정보 (평점, 주차, 식사)
        _buildQuickInfo(context, business),
      ],
    );
  }

  /// 사업장 이미지
  Widget _buildBusinessImage(BuildContext context, BusinessModel business) {
    final size = ResponsiveHelper.iconSize(context, 80);

    if (business.mainImageUrl == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: AppColors.grey200,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(Icons.business, size: ResponsiveHelper.iconSize(context, 40), color: AppColors.grey400),
      );
    }

    return ImageHelper.buildCachedImage(
      business.mainImageUrl!,
      width: size,
      height: size,
      fit: BoxFit.cover,
      borderRadius: BorderRadius.circular(12),
      memCacheWidth: (size * 2).toInt(),
      fadeInDuration: const Duration(milliseconds: 150),
    );
  }

  /// 빠른 정보 (평점, 주차, 식사)
  ///   [DU395] 라벨 = '주차 가능/불가' · '식사 제공/미제공'(소급 24 §3 — 판정식 그대로). 세 항목이 한 줄에 들어가면
  ///   구분선 있는 한 줄(원 배치), 안 들어가면(좁은 폭 · 큰 글자) 구분선 없이 항목 단위로 다음 줄로 흐른다.
  ///   말줄임 · 글자 축소 0, 구분선이 줄 끝/처음에 혼자 남지 않는다. 라벨 안은 낱말 사이에서만 줄을 바꾼다.
  Widget _buildQuickInfo(BuildContext context, BusinessModel business) {
    final hasMeal = business.mealsProvided != null && business.mealsProvided!.isNotEmpty;
    final parkingLabel = business.parkingAvailable ? '주차 가능' : '주차 불가';
    final mealLabel = hasMeal ? '식사 제공' : '식사 미제공';
    final ratingText = business.rating?.toStringAsFixed(1);
    final ratingStyle = ResponsiveHelper.smallStyle(context).copyWith(
      fontWeight: FontWeight.bold,
    );
    final parkingStyle = ResponsiveHelper.smallStyle(context).copyWith(
      color: AppColors.textTertiary /* [판정55 · DU418] 단순 사실(주차 가능/불가) = 중립 메타색 — 긍정 · 부정 같은 색, 흰 카드 위 5.25 */,
    );
    final mealStyle = ResponsiveHelper.smallStyle(context).copyWith(
      color: AppColors.textTertiary /* [판정55 · DU418] 단순 사실(식사 제공/미제공) = 중립 메타색 — 긍정 · 부정 같은 색, 흰 카드 위 5.25 */,
    );
    final iconSize = ResponsiveHelper.iconSize(context, 14);
    final starGap = ResponsiveHelper.spacing(context, 2);
    final gap = ResponsiveHelper.spacing(context, 8);

    final items = <Widget>[
      // 평점
      if (ratingText != null)
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star,
              size: iconSize,
              color: AppColors.amberDark,
            ),
            SizedBox(width: starGap),
            Text(ratingText, style: ratingStyle),
          ],
        ),
      // 주차
      Text(TextLayout.keepWords(parkingLabel), semanticsLabel: parkingLabel, style: parkingStyle),
      // 식사
      Text(TextLayout.keepWords(mealLabel), semanticsLabel: mealLabel, style: mealStyle),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Text 가 그리는 기준과 같게 잰다 — 둘레 기본 글자 병합 · 실제 배율 · locale(DU284 교훈)
        double oneLine(String text, TextStyle style) {
          final eff = style.inherit ? DefaultTextStyle.of(context).style.merge(style) : style;
          final tp = TextPainter(
            text: TextSpan(text: text, style: eff),
            textDirection: TextDirection.ltr,
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.maybeLocaleOf(context),
          )..layout();
          final w = tp.width;
          tp.dispose();
          return w;
        }

        final divider = gap * 2 + 1;
        final need = (ratingText != null ? iconSize + starGap + oneLine(ratingText, ratingStyle) + divider : 0) +
            oneLine(parkingLabel, parkingStyle) +
            divider +
            oneLine(mealLabel, mealStyle);
        if (need + 1 <= constraints.maxWidth) {
          // 한 줄 — 원 배치(항목 사이 구분선)
          return Row(
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) ...[
                  SizedBox(width: gap),
                  Container(
                    width: 1,
                    height: 12,
                    color: AppColors.grey300,
                  ),
                  SizedBox(width: gap),
                ],
                items[i],
              ],
            ],
          );
        }
        // 줄바꿈 — 구분선 없이 항목 단위로 흐른다(혼자 남는 구분선 0)
        return Wrap(
          spacing: gap * 1.5,
          runSpacing: ResponsiveHelper.spacing(context, 4),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: items,
        );
      },
    );
  }

  /// 더보기 메뉴
  Widget _buildMoreMenu(BuildContext context, ThemeData theme, BusinessModel business) {
    return IconButton(
      icon: Icon(
        Icons.more_vert,
        size: ResponsiveHelper.iconSize(context, 24),
        color: AppColors.grey600, // [DU396] 보조 행동(메뉴 열기) 중립 — 흰 위 4.61
      ),
      tooltip: '메뉴',
      onPressed: () => _showMoreMenuSheet(context, theme, business),
    );
  }

  void _showMoreMenuSheet(BuildContext context, ThemeData theme, BusinessModel business) {
    final userProvider = context.read<UserProvider>();
    final isSubAdmin = userProvider.isSubAdmin;
    final canManageTo = userProvider.checkCurrentBusiness((p) => p.canManageTo) ==
        PermissionCheck.allowed;

    AppMenuSheet.show(
      context: context,
      itemGroups: [
        if (business.isApproved && canManageTo)
          [
            AppMenuSheetItem(
              icon: Icons.add_circle_outline,
              label: '공고 등록',
              color: theme.primaryColor,
              onTap: () => _handleCreateTO(context, business),
            ),
          ],
        [
          AppMenuSheetItem(
            icon: Icons.info_outline,
            label: '상세보기',
            color: AppColors.brand, // [DU396] 탐색 = brand 계열(정보 파랑 상태색 아님)
            onTap: () => NavigationHelper.push<bool>(
              context,
              destination: BusinessDetailScreen(business: business),
              onReturn: (result) {
                if (result == true && mounted) _loadBusinesses(forceServer: true);
              },
            ),
          ),
          if (!isSubAdmin)
            AppMenuSheetItem(
              icon: Icons.edit,
              label: '수정',
              color: AppColors.brand, // [DU396] 일반 진행 = brand 계열(주의 주황 상태색 아님)
              onTap: () => NavigationHelper.push<bool>(
                context,
                destination: BusinessFormScreen(business: business),
                onReturn: (result) {
                  if (result == true && mounted) _loadBusinesses(forceServer: true);
                },
              ),
            ),
        ],
        // [BUSINESS-ARCHIVE] 소유자만(서버도 같은 주체), 이미 종료된 사업장에는 없다.
        if (!isSubAdmin &&
            business.ownerId == context.read<UserProvider>().currentUser?.uid &&
            !business.isDeactivated)
          [
            AppMenuSheetItem(
              icon: Icons.storefront_outlined,
              label: '운영 종료',
              // [DU396] 진입은 중립 — 사전 조회 → 위험 확인창(최종 '운영 종료' errorDark)으로 이어진다. 확인 · 실행 경로 그대로
              color: AppColors.grey600,
              isDanger: false,
              onTap: () => _archiveBusiness(business),
            ),
          ],      ],
    );
  }

  Future<void> _handleCreateTO(BuildContext context, BusinessModel business) async {
    if (!context.mounted) return;
    // [HOTFIX HOME.POSTING.ENTRY.1-R1] BusinessList는 이미 특정 사업장 컨텍스트 —
    // 해당 사업장을 CreateTO 초기 선택으로 전달한다.
    await NavigationHelper.push<bool>(
      context,
      destination: AdminCreateTOScreen(initialBusinessId: business.id),
      useRootNavigator: true,
      onReturn: (result) {
        if (result == true && mounted) _loadBusinesses(forceServer: true);
      },
    );
  }

  /// 새 사업장 추가 버튼
  Widget _buildAddButton(BuildContext context, ThemeData theme) {
    return Container(
      margin: EdgeInsets.only(
        top: ResponsiveHelper.spacing(context, 8),
        bottom: ResponsiveHelper.spacing(context, 16),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _navigateToBusinessForm,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: EdgeInsets.symmetric(
              vertical: ResponsiveHelper.spacing(context, 20),
            ),
            decoration: BoxDecoration(
              border: Border.all(
                color: theme.primaryColor.withValues(alpha: 0.3),
                width: 2,
                style: BorderStyle.solid,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_circle_outline,
                  color: theme.primaryColor,
                  size: ResponsiveHelper.iconSize(context, 24),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                Text(
                  '새 사업장 추가',
                  style: ResponsiveHelper.bodyStyle(context).copyWith(
                    color: AppColors.brandDark, // [DU396] 읽는 라벨 = brandDark(아이콘 · outline 은 brand 그대로)
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
  /// 사업자등록증 체크 후 사업장 등록 화면으로 이동
  Future<void> _navigateToBusinessForm() async {
    final userProvider = context.read<UserProvider>();
    
    // 최신 사용자 정보 가져오기
    await userProvider.refreshCurrentUser();
    if (!mounted) return;

    final user = userProvider.currentUser;

    if (user == null) {
      ToastHelper.showError('로그인이 필요합니다.');
      return;
    }

    // 사업자등록증 체크 제거 — BusinessFormScreen._validateStep2()에서
    // 신규 등록 시 사업자등록증 업로드를 강제하므로 여기서 사전 차단 불필요.
    // 신규: business.businessLicenseImageUrl (Form 내 업로드)
    // legacy: user.businessLicenseImageUrl (서류관리 화면 유지)
    await NavigationHelper.push<bool>(
      context,
      destination: const BusinessFormScreen(),
      onReturn: (result) {
        if (result == true && mounted) _loadBusinesses(forceServer: true);
      },
    );
  }
}
