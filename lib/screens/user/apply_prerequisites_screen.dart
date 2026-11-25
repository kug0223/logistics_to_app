import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../services/tax_identity_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/navigation_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/loading_widget.dart';
import '../common/document_management_screen.dart';

/// 지원 전 준비사항 체크 전체 화면.
///
/// 미충족 항목이 있으면 이 화면으로 push되고, 모든 항목 충족 후 "지원하기" 버튼을 누르면
/// `Navigator.pop(context, true)`로 복귀 — 호출자가 실제 지원 흐름을 계속 진행.
///
/// 사용법:
/// ```dart
/// final ok = await ApplyPrerequisitesScreen.show(context, isFlexType: to.isFlexType);
/// if (ok && mounted) { /* 지원 다이얼로그 열기 */ }
/// ```
class ApplyPrerequisitesScreen extends StatefulWidget {
  final bool isFlexType;

  const ApplyPrerequisitesScreen({super.key, required this.isFlexType});

  static Future<bool> show(BuildContext context, {required bool isFlexType}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => ApplyPrerequisitesScreen(isFlexType: isFlexType),
      ),
    );
    return result == true;
  }

  @override
  State<ApplyPrerequisitesScreen> createState() => _ApplyPrerequisitesScreenState();
}

class _ApplyPrerequisitesScreenState extends State<ApplyPrerequisitesScreen> {
  bool _isLoading = false;

  UserModel? get _user =>
      context.read<UserProvider>().currentUser;

  bool get _idCardReady {
    final u = _user;
    return u != null && u.hasIdDocument;
  }

  bool get _idVerified => _user?.isIdVerified ?? false;

  bool get _accountReady => _user?.hasBankAccount == true;

  bool get _bankbookReady {
    final u = _user;
    return u != null && u.hasBankbookDocument;
  }

  bool get _isBlacklisted => _user?.isBlacklisted ?? false;

  bool get _isRestricted {
    final u = _user;
    return u != null && u.isRestricted;
  }

  /// [DU571] 제한이 끝나는 시각(KST · 로그인 안내와 같은 표기) — 기한 없는 제한이면 null(남은 일수 올림 'N일' 대신 · 판정156 §5).
  String? get _restrictedUntilLabel {
    final until = _user?.restrictedUntil;
    return until == null ? null : restrictionEndLabel(until);
  }

  bool get _allPrerequisitesMet {
    if (_isBlacklisted || _isRestricted) return false;
    if (!_idCardReady) return false;
    if (widget.isFlexType && !_idVerified) return false;
    if (!_accountReady) return false;
    if (!_bankbookReady) return false;
    return true;
  }

  int get _totalItemCount => widget.isFlexType ? 4 : 3;

  Future<void> _reCheck() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
    try {
      await context.read<UserProvider>().refreshCurrentUser();
    } catch (e) {
      if (mounted) ToastHelper.showError('새로고침에 실패했습니다. 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // [R7-P2-2 P22-G] flat shell 로 전환.
    //   3축 실측: headerContent 0 · 헤더 TabBar 0 · shell onRefresh 0,
    //   흰색 상수 1개는 본문 글자가 아니라 버튼 전경색이다 →
    //   title/body 만 쓰는 **순수 교체**다. 헤더 문구·본문·뒤로는 그대로다.
    return AppPageScaffold(
      title: '지원하기',
      body: _isLoading
          ? const LoadingWidget()
          : SingleChildScrollView(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 이용제한 / 블랙리스트 배너
                  if (_isBlacklisted) ...[
                    _buildRestrictionBanner(
                      icon: Icons.block,
                      color: AppColors.errorDark, // [DU251] 글자용 진한 토큰(옅은 바탕 위 ≥4.5)
                      background: AppColors.errorBg,
                      // [DU582b · 판정156 Q4] isBlacklisted = '계정 이용 차단'(운영자 S052 · 공고 상세와 같은 말) · 자동 만료 없음 = '해제 전까지'('영구' 0).
                      message: '계정 이용 차단 상태라 해제 전까지 지원할 수 없어요.',
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  ] else if (_isRestricted) ...[
                    _buildRestrictionBanner(
                      icon: Icons.timer_off_outlined,
                      color: AppColors.warningDark, // [DU251]
                      background: AppColors.warningBg,
                      // [DU582c · 판정171 §4 · 판정166 결정②] 이미 확정된 근무도 출근 체크가 막힌다(callableCheckIn 이 restrictedUntil 을 먼저 거절)는 효과를 이 배너(읽는 안내)에 둔다 — 끝 시각 = 같은 restrictedUntil 표기 · 공고 상세 비활성 버튼 글에는 넣지 않는다 · 근무 취소 같은 효과는 말하지 않는다.
                      message: _restrictedUntilLabel != null
                          ? '$_restrictedUntilLabel까지 이용이 제한돼 지원할 수 없어요.\n이미 확정된 근무도 제한이 끝날 때까지 출근 체크를 할 수 없어요.'
                          : '이용 제한(기한 없음) 상태라 지원할 수 없어요.\n이미 확정된 근무도 해제 전까지 출근 체크를 할 수 없어요.',
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                  ],

                  // 안내 헤더
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                    // [DU615b F199-AP-HEADER-TOKENS] 안내 상자 = 앱 토큰 직접(판정199 §3 :54): 면 brandSurface · 선 brand α0.2(이전 선 강도 그대로) · 아이콘 brand.
                    //   이전 theme.primaryColor α0.08 면과 불투명 brandSurface 는 같은 색이 아니다(동등 주장 0). 전역 theme/AppColors 변경 0 · 크기/반경/여백 그대로.
                    decoration: BoxDecoration(
                      color: AppColors.brandSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.brand.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.assignment_outlined,
                            color: AppColors.brand,
                            size: ResponsiveHelper.iconSize(context, 28)),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // [DU615b F199-AP-PREP-WORDS] 큰 글자에서 낱말 단위로만 줄을 바꾼다(B '준비사 / 항' 음절 끊김 · 판정199 §3 :54). 읽기 도구에는 원문.
                              //   문구 · 가변 개수 · 글 크기/배율 · 폭 · 배치 그대로(같은 파일 배너 · 준비 항목 카드와 같은 opt-in 짝).
                              Text(TextLayout.keepWords('지원 전 준비사항'),
                                  semanticsLabel: '지원 전 준비사항',
                                  style: ResponsiveHelper.subtitleStyle(context)
                                      .copyWith(fontWeight: FontWeight.bold)),
                              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                              Text(
                                TextLayout.keepWords('아래 $_totalItemCount가지를 모두 완료해야 지원할 수 있습니다.'),
                                semanticsLabel: '아래 $_totalItemCount가지를 모두 완료해야 지원할 수 있습니다.',
                                style: ResponsiveHelper.smallStyle(context,
                                    color: AppColors.textSecondary), // [DU251]
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: ResponsiveHelper.spacing(context, 20)),

                  // [DU251] 준비 항목을 묶음 카드 하나에 행으로 담는다(S010·S082 와 같은 흰 면·반경 16·grey200).
                  _buildPrerequisiteGroup([
                  // 1. 신분증 등록
                  _buildPrerequisiteCard(
                    index: 1,
                    title: '신분증 등록',
                    isReady: _idCardReady,
                    readyDescription: '신분증이 등록되어 있습니다',
                    notReadyDescription: '신분증 등록이 필요합니다.',
                    actionLabel: '서류 관리',
                    onAction: () async {
                      await NavigationHelper.push<void>(
                          context, destination: const DocumentManagementScreen());
                      if (!mounted) return;
                      await _reCheck();
                    },
                  ),

                  // 2. 신분증 인증 (단기 공고만)
                  if (widget.isFlexType) ...[
                    _buildPrerequisiteCard(
                      index: 2,
                      title: '신분증 인증',
                      isReady: _idVerified,
                      readyDescription: '신분증 인증이 완료되었습니다',
                      notReadyDescription: '단기 공고 지원 시 신분증 인증이 필요합니다.',
                      actionLabel: '서류 관리',
                      onAction: () async {
                        await NavigationHelper.push<void>(
                            context, destination: const DocumentManagementScreen());
                        if (!mounted) return;
                        await _reCheck();
                      },
                    ),
                  ],

                  // [PII-DOC-R1.5.4] 계좌 정보·통장사본 카드 복구.
                  //   지원 전에 실제로 막는 항목이므로 여기 있어야 한다.

                  // 계좌 정보 (flex: 3번 / contract: 2번)
                  _buildPrerequisiteCard(
                    index: widget.isFlexType ? 3 : 2,
                    title: '계좌 정보 등록',
                    isReady: _accountReady,
                    readyDescription: '계좌 정보가 등록되어 있습니다',
                    notReadyDescription: '계좌 정보 등록이 필요합니다.',
                    actionLabel: '서류 관리',
                    onAction: () async {
                      await NavigationHelper.push<void>(
                          context, destination: const DocumentManagementScreen());
                      if (!mounted) return;
                      await _reCheck();
                    },
                  ),

                  // 통장사본 (flex: 4번 / contract: 3번)
                  _buildPrerequisiteCard(
                    index: widget.isFlexType ? 4 : 3,
                    title: '통장사본 등록',
                    isReady: _bankbookReady,
                    readyDescription: '통장사본이 등록되어 있습니다',
                    notReadyDescription: '통장사본 등록이 필요합니다.',
                    actionLabel: '서류 관리',
                    onAction: () async {
                      await NavigationHelper.push<void>(
                          context, destination: const DocumentManagementScreen());
                      if (!mounted) return;
                      await _reCheck();
                    },
                  ),
                  ]),
                  SizedBox(height: ResponsiveHelper.spacing(context, 32)),

                  // 하단 버튼
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _reCheck,
                          icon: const Icon(Icons.refresh),
                          label: const Text('다시 확인'),
                          style: OutlinedButton.styleFrom(
                            padding: EdgeInsets.symmetric(
                                vertical: ResponsiveHelper.spacing(context, 14)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _allPrerequisitesMet
                              ? () => Navigator.pop(context, true)
                              : null,
                          icon: const Icon(Icons.send_outlined),
                          label: const Text('지원하기'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: theme.primaryColor,
                            foregroundColor: Colors.white,
                            // [DU251] 비활성이어도 무엇을 못 하는지 읽힌다(이전 grey300 + 기본 흐린 글자).
                            disabledBackgroundColor: AppColors.grey200,
                            disabledForegroundColor: AppColors.textSecondary,
                            padding: EdgeInsets.symmetric(
                                vertical: ResponsiveHelper.spacing(context, 14)),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildRestrictionBanner({
    required IconData icon,
    required Color color,
    required Color background,
    required String message,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        // [DU251 v2] 겹침 8% 대신 정해진 옅은 바탕 토큰 — 화면 바탕 위 겹침은 경고 글자를 4.41 로 떨어뜨렸다.
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: ResponsiveHelper.iconSize(context, 20)),
          SizedBox(width: ResponsiveHelper.spacing(context, 10)),
          Expanded(
            child: Text(
              // [DU571] 큰 글자에서 낱말 단위로만 줄을 바꾼다(B 음절 끊김 0). 읽기 도구에는 원문.
              TextLayout.keepWords(message),
              semanticsLabel: message,
              style: ResponsiveHelper.smallStyle(context).copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrerequisiteCard({
    required int index,
    required String title,
    required bool isReady,
    required String readyDescription,
    required String notReadyDescription,
    String? actionLabel,
    VoidCallback? onAction,
  }) {
    final theme = Theme.of(context);
    // [DU251] 준비됨 = 진한 초록 체크(successBg 원), 미준비 = 중립 빈 원(해야 할 일 — 위험이 아니다).
    final iconColor = isReady ? AppColors.successDark : AppColors.grey600;
    final circleColor = isReady ? AppColors.successBg : AppColors.grey100;

    // [DU251] 낱개 카드(그림자·색 테두리) → 묶음 카드 안의 행(_buildPrerequisiteGroup).
    return Padding(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
      // [R7-P2-2 P22-G] 액션 버튼에 상한이 없어 320dp·배율 2.0 에서 줄이
      //   15px 넘쳤다(4개 항목 전부). 준비 항목 이름도 행동 이름도 지우지
      //   않는다 — 넘칠 때만 버튼 폭을 40% 로 묶어 글자가 줄바꿈되게 한다.
      child: LayoutBuilder(builder: (context, c) {
      final actionMax = c.maxWidth.isFinite ? c.maxWidth * 0.4 : double.infinity;
      return Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: circleColor,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(
                isReady ? Icons.check_circle : Icons.radio_button_unchecked,
                color: iconColor,
                size: ResponsiveHelper.iconSize(context, 22),
              ),
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 12)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('$index.',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.textSecondary)), // [DU251] 이전 grey500
                    SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                    Flexible(
                      // [DU251 v3] 큰 글자에서 낱말 단위로만 줄을 바꾼다. 읽기 도구에는 원문.
                      child: Text(TextLayout.keepWords(title),
                          semanticsLabel: title,
                          style: ResponsiveHelper.bodyStyle(context,
                                  color: AppColors.textPrimary) // [DU251] 이전 기본 grey700
                              .copyWith(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  TextLayout.keepWords(isReady ? readyDescription : notReadyDescription),
                  semanticsLabel: isReady ? readyDescription : notReadyDescription,
                  style: ResponsiveHelper.smallStyle(context,
                      color: isReady ? AppColors.successDark : AppColors.textSecondary), // [DU251]
                ),
              ],
            ),
          ),
          if (!isReady && actionLabel != null && onAction != null) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: actionMax),
              child: TextButton(
              onPressed: _isLoading ? null : onAction,
              style: TextButton.styleFrom(
                foregroundColor: theme.primaryColor,
                padding: EdgeInsets.symmetric(
                    horizontal: ResponsiveHelper.spacing(context, 10),
                    vertical: ResponsiveHelper.spacing(context, 6)),
                // [DU251] 터치 48(이전 shrinkWrap·최소 0).
                minimumSize: const Size(48, 48),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(actionLabel,
                        style: ResponsiveHelper.smallStyle(context,
                            color: theme.primaryColor,
                            fontWeight: FontWeight.bold)),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 2)),
                  Icon(Icons.arrow_forward_ios,
                      size: ResponsiveHelper.iconSize(context, 12),
                      color: theme.primaryColor),
                ],
              ),
              ),
            ),
          ],
        ],
      );
      }),
    );
  }

  /// [DU251] 준비 항목 묶음 카드 — 흰 면·반경 16·grey200 선, 행 사이 grey100 구분선(상태 원 뒤 글자 시작 68).
  Widget _buildPrerequisiteGroup(List<Widget> rows) {
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.grey200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            rows[i],
            if (i < rows.length - 1)
              Divider(
                  height: 1,
                  thickness: 1,
                  color: AppColors.grey100,
                  indent: ResponsiveHelper.spacing(context, 16) + 40 + ResponsiveHelper.spacing(context, 12)),
          ],
        ],
      ),
    );
  }
}

/// 지원 전 요구사항 충족 여부 순수 체크 함수.
/// 다이얼로그 없이 bool만 반환 — UI 결정은 호출자가 담당.
/// [PII-B4-R1.4 §39] 세무 축을 포함한 지원 준비 판정.
///
///   [taxStatus]는 서버가 아는 사실이므로 호출자가 조회해 넘긴다.
///   **null이면 막지 않는다** — 모르는 것을 미등록으로 읽으면 조회 한 번
///   실패했다는 이유로 정상 지원자의 버튼이 잠긴다. 최종 판단은 서버가
///   `callableApplyToTO`에서 다시 한다.
// 시그니처를 한 줄로 두는 이유: 여러 계약 테스트가 이 함수 본문을
// `'bool meetsApplyPrerequisites('` ~ `'\n}'` 로 잘라 읽는다. 매개변수를
// 여러 줄로 펴면 닫는 `})` 가 줄 맨 앞의 `}` 가 되어 본문이 잘린다.
bool meetsApplyPrerequisites(UserModel user,
    {required bool isFlexType, TaxIdentityStatus? taxStatus}) {
  // 세무 축 — 수집이 켜졌고, 미등록이거나 현재 신분증과 명시적으로
  // 어긋났을 때만 막는다. UNREADABLE·UNASSESSED는 막지 않는다(§37).
  if (taxStatus != null && !taxStatus.loadFailed) {
    if (taxStatus.collectionEnabled && !taxStatus.registered) return false;
    if (taxStatus.blocksApply) return false;
  }
  // 블랙리스트·제재 계정: 문서 갖춰도 지원 불가 — CF 차단과 동일
  // restrictedUntil 만료 체크 포함 (위젯 _isRestricted getter와 동일 로직)
  if (user.isBlacklisted || user.isRestricted) {
    return false;
  }
  // 내국인만 PASS 필수 — 외국인은 CF와 동일하게 면제
  if (!user.isForeign && !user.isPassVerified) {
    return false;
  }
  if (!user.hasIdDocument) {
    return false;
  }
  if (isFlexType && !user.isIdVerified) {
    return false;
  }
  // [PII-DOC-R1.5.4] 지원자 기본자료 — APPLICANT ONBOARDING READINESS.
  //   서버 srvMissingApplicantPayoutRegistration과 같은 질문을 한다:
  //   등록됐는가. 관리자 검수 여부나 OCR 판정은 묻지 않는다.
  //   이 함수는 지원과 초대 수락 양쪽의 게이트이므로 두 경로가 함께 닫힌다.
  if (!user.hasBankAccount) return false;
  if (!user.hasBankbookDocument) {
    return false;
  }
  return true;
}

/// [DU571] 이용 제한이 끝나는 시각 — 로그인 안내(AuthService.restrictionLoginMessage)와 같은 KST 날짜·시각 표기.
///   기한 없는 제한(서버 경계 KST 9999-01-01 00:00 이후 · all_users_screen 의 _isPermanentInstant 와 같은 경계)이면 null —
///   날짜로 말하지 않는다. 제한 판정(UserModel)은 그대로 절대 시각 비교다 — 이 함수는 표기만.
String? restrictionEndLabel(DateTime until) =>
    until.millisecondsSinceEpoch >= DateTime.utc(9998, 12, 31, 15).millisecondsSinceEpoch
        ? null
        : FormatHelper.formatKstDateTimeKorean(until);
