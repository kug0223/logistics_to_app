// lib/screens/common/deletion_reauth_screen.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · 판정280 B280-02] 카카오(비밀번호 없는) 계정의 탈퇴 · 삭제 재개 화면.
//
//   서버 requestId → KG 창 → verifyPassAuth(account_deletion) → 10분 증명 → **기존 삭제 파이프라인**
//   (AuthService.deleteAccountAfterKgProof — 비밀번호 탈퇴와 같은 PreData → Applications → Final).
//   비밀번호 대용 흐름은 없다. 상태는 취소 · 실패 · 확인 중 · 삭제 중 · 만료(다시 본인확인)를 나눠 말한다.
//   증명이 아직 살아 있으면(10분) 삭제 단계만 다시 시도한다 — KG 를 또 요구하지 않는다.
//
//   카카오 연결 해제 범위(server_api_1 §5A): 서버 Final 이 providerUnlink 'ALLOWED'(이 카카오에 남은 역할 없음)
//   일 때만 파이프라인이 카카오 SDK unlink 를 부른다. 'KEEP_OTHER_ROLE' 이면 끊지 않고 로그아웃만 한다 —
//   같은 카카오의 다른 역할 계정 로그인을 보존한다. 탈퇴한 UID 의 서버 링크는 서버가 UID 단위로 정리한다.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../services/auth/deletion_reauth_api.dart';
import '../../services/auth/signup_api.dart';
import '../../services/auth_service.dart';
import '../../services/pass_verification_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/withdraw_preview.dart';
import '../auth/signup/signup_flow_controller.dart' show KgLauncher;
import '../auth/signup/signup_flow_screen.dart' show SignupNote, SignupNoteTone;

enum DeletionReauthIntent {
  /// 설정에서 시작하는 회원 탈퇴.
  withdraw,

  /// 탈퇴가 끝나지 않은 계정의 삭제 재개(users 문서가 없어도 같은 길).
  resume,
}

enum DeletionReauthPhase {
  idle,
  checking,
  inWindow,
  canceled,
  failed,
  verifying,
  deleting,
  expired,
  done,
}

/// [판정281 C281-01] 삭제 재확인 증명(서버 10분)의 앱 쪽 기억 — 메모리만 · UID 별.
///   BEGIN 뒤 실패로 탈퇴 화면이 걷히고 삭제 재개 화면이 새로 서도, 증명이 살아 있으면 KG 를 다시 요구하지 않는다.
class DeletionProofMemo {
  DeletionProofMemo._();
  static final Map<String, DateTime> _until = {};
  static DateTime? get(String? key) => key == null ? null : _until[key];
  static void set(String? key, DateTime? until) {
    if (key == null) return;
    if (until == null) {
      _until.remove(key);
    } else {
      _until[key] = until;
    }
  }
}

/// 탈퇴 전 서버 차단 사유 확인(있으면 문장, 없으면 null). KG 유료 호출 전에 막는다.
typedef WithdrawPrecheck = Future<String?> Function();

class DeletionReauthController extends ChangeNotifier {
  DeletionReauthController({
    required DeletionReauthApi api,
    required Future<String?> Function() pipeline,
    KgLauncher? kgLauncher,
    WithdrawPrecheck? precheck,
    DateTime Function()? clock,
    String? proofKey,
  })  : _api = api,
        _proofKey = proofKey,
        _provenUntil = DeletionProofMemo.get(proofKey),
        _pipeline = pipeline,
        _kg = kgLauncher ?? ((id) => PassVerificationService.launchCertification(requestId: id)),
        _precheck = precheck,
        _clock = clock ?? DateTime.now;

  final DeletionReauthApi _api;
  final Future<String?> Function() _pipeline;
  final KgLauncher _kg;
  final WithdrawPrecheck? _precheck;
  final DateTime Function() _clock;

  final String? _proofKey;

  bool _disposed = false;
  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  DeletionReauthPhase _phase = DeletionReauthPhase.idle;
  DeletionReauthPhase get phase => _phase;
  String? _message;
  String? get message => _message;
  DateTime? _provenUntil;

  bool get busy =>
      _phase == DeletionReauthPhase.checking ||
      _phase == DeletionReauthPhase.inWindow ||
      _phase == DeletionReauthPhase.verifying ||
      _phase == DeletionReauthPhase.deleting;

  /// 증명이 아직 유효한가(서버 만료 시각 기준 · 1분 여유).
  bool get proofAlive =>
      _provenUntil != null && _clock().isBefore(_provenUntil!.subtract(const Duration(minutes: 1)));

  void _set(DeletionReauthPhase p, [String? m]) {
    _phase = p;
    _message = m;
    notifyListeners();
  }

  /// 본인확인(필요할 때만) → 삭제. 끝나면 phase = done.
  Future<void> run() async {
    if (busy || _phase == DeletionReauthPhase.done) return;
    if (!proofAlive) {
      final pre = _precheck;
      if (pre != null) {
        _set(DeletionReauthPhase.checking);
        final block = await pre();
        if (block != null) {
          _set(DeletionReauthPhase.failed, block);
          return;
        }
      }
      final DeletionReauthTicket ticket;
      try {
        _set(DeletionReauthPhase.checking);
        ticket = await _api.start();
      } on SignupApiException catch (e) {
        _set(DeletionReauthPhase.failed, e.userMessage);
        return;
      } catch (_) {
        _set(DeletionReauthPhase.failed, SignupCopy.reasonMessage(null));
        return;
      }
      _set(DeletionReauthPhase.inWindow);
      final out = await _kg(ticket.requestId);
      switch (out.status) {
        case PassLaunchStatus.canceled:
          _set(DeletionReauthPhase.canceled);
          return;
        case PassLaunchStatus.failed:
        case PassLaunchStatus.unavailable:
          _set(DeletionReauthPhase.failed, '본인확인 창에서 문제가 생겼어요. 다시 시도해 주세요.');
          return;
        case PassLaunchStatus.returned:
          break;
      }
      _set(DeletionReauthPhase.verifying);
      try {
        _provenUntil = await _api.verify(out.impUid!) ??
            _clock().add(const Duration(minutes: 10));
        DeletionProofMemo.set(_proofKey, _provenUntil);
      } on SignupApiException catch (e) {
        _set(DeletionReauthPhase.failed, e.userMessage);
        return;
      } catch (_) {
        _set(DeletionReauthPhase.failed, SignupCopy.reasonMessage(null));
        return;
      }
    }
    _set(DeletionReauthPhase.deleting);
    final err = await _pipeline();
    if (err == null) {
      DeletionProofMemo.set(_proofKey, null);
      _set(DeletionReauthPhase.done);
      return;
    }
    if (err == kDeletionReauthExpiredMessage) {
      _provenUntil = null; // 증명이 서버에서 만료 — 다음 시도는 본인확인부터
      DeletionProofMemo.set(_proofKey, null);
      _set(DeletionReauthPhase.expired, err);
      return;
    }
    // 삭제 단계 실패 — 증명이 살아 있으면 다음 시도는 삭제만 다시 한다(멱등 파이프라인).
    _set(DeletionReauthPhase.failed, err);
  }
}

/// 설정 탈퇴 전 서버 차단 사유(서브관리자 직책 · 미서명 계약 등). 기존 설정 화면과 같은 callable · 같은 문구.
Future<String?> defaultWithdrawPrecheck() async {
  try {
    final r = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
        .httpsCallable('callableGetWithdrawBlockers',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 25)))
        .call<Map<String, dynamic>>({});
    final hard = (r.data['hardBlocks'] as List<dynamic>? ?? []).cast<Map<String, dynamic>>();
    if (hard.isEmpty) return null;
    // [impl_64] 차단 문구는 비밀번호 탈퇴 경로와 같은 함수(PENDING_WAGES 안내 포함).
    return withdrawHardBlockMessage(hard.first);
  } catch (_) {
    // 확인을 못 했다고 막지 않는다 — 최종 판정은 서버 Final 이 한다(기존 설정 화면과 같은 권위).
    return null;
  }
}

class DeletionReauthScreen extends StatefulWidget {
  const DeletionReauthScreen({
    super.key,
    required this.intent,
    this.api,
    this.kgLauncher,
    this.pipeline,
    this.precheck,
    this.warningsLoader,
    this.onDone,
    this.onSignOut,
    this.proofKey,
  });

  final DeletionReauthIntent intent;
  final DeletionReauthApi? api;
  final KgLauncher? kgLauncher;
  final Future<String?> Function()? pipeline;
  final WithdrawPrecheck? precheck;

  /// [impl_64 · 판정296 P2] 탈퇴 확인창에 함께 보일 서버 경고 줄(미서명 계약 무효 · 진행 중 장기 근무 등).
  ///   생략하면 탈퇴(withdraw)는 서버 미리보기를 읽는다 — 단, 시험 대역 precheck 를 넣은 경우는 읽지 않는다.
  ///   실패는 빈 목록(경고 없이 기존 확인창) — 차단은 precheck · 서버가 막는다.
  final Future<List<String>> Function()? warningsLoader;

  /// 삭제 완료 뒤(재개 화면 — 로그아웃 등). 탈퇴(withdraw)는 화면을 true 로 닫는다.
  final Future<void> Function()? onDone;

  /// 재개 화면의 '로그아웃'(삭제를 포기할 수는 없지만 나중에 올 수 있다).
  final Future<void> Function()? onSignOut;

  /// 증명 기억 키(UID). 생략하면 현재 Auth UID.
  final String? proofKey;

  @override
  State<DeletionReauthScreen> createState() => _DeletionReauthScreenState();
}

class _DeletionReauthScreenState extends State<DeletionReauthScreen> {
  late final DeletionReauthController _c = DeletionReauthController(
    api: widget.api ?? FirebaseDeletionReauthApi(),
    pipeline: widget.pipeline ?? AuthService().deleteAccountAfterKgProof,
    kgLauncher: widget.kgLauncher,
    precheck: widget.precheck ??
        (widget.intent == DeletionReauthIntent.withdraw ? defaultWithdrawPrecheck : null),
    proofKey: widget.proofKey ?? _currentUid(),
  );

  static String? _currentUid() {
    try {
      return AuthService().currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  bool get _withdraw => widget.intent == DeletionReauthIntent.withdraw;

  @override
  void initState() {
    super.initState();
    _c.addListener(_onPhase);
  }

  Future<void> _onPhase() async {
    if (_c.phase != DeletionReauthPhase.done) return;
    if (_withdraw) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    await widget.onDone?.call();
  }

  @override
  void dispose() {
    _c.removeListener(_onPhase);
    _c.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    if (_c.busy) return;
    if (_withdraw && !_c.proofAlive) {
      // [impl_64] 서버 경고(warnings)를 확인창에 함께 보인다 — 예전에는 버려 근로자가 모른 채 탈퇴했다.
      final loader = widget.warningsLoader ??
          (widget.precheck == null ? () async => (await fetchWithdrawPreview()).warningLines : null);
      var warnings = const <String>[];
      if (loader != null) {
        try {
          warnings = await loader();
        } catch (_) {}
      }
      if (!mounted) return;
      final ok = await DialogHelper.showDangerConfirm(
        context,
        title: '정말 탈퇴하시겠습니까?',
        message: warnings.isEmpty
            ? '탈퇴 후 계정 및 모든 데이터가 삭제되며 복구할 수 없습니다.'
            : '탈퇴 후 계정 및 모든 데이터가 삭제되며 복구할 수 없습니다.'
                '\n\n탈퇴 전 확인'
                '\n${warnings.map((l) => '• $l').join('\n')}',
        confirmText: '탈퇴하기',
      );
      if (ok != true || !mounted) return;
    }
    await _c.run();
  }

  String get _primaryLabel {
    if (_c.proofAlive) return _withdraw ? '탈퇴 다시 시도' : '삭제 다시 시도';
    switch (_c.phase) {
      case DeletionReauthPhase.canceled:
      case DeletionReauthPhase.failed:
      case DeletionReauthPhase.expired:
        return '본인확인 다시 하기';
      default:
        return _withdraw ? '본인확인하고 탈퇴하기' : '본인확인하고 마무리하기';
    }
  }

  Widget? _note() {
    switch (_c.phase) {
      case DeletionReauthPhase.idle:
      case DeletionReauthPhase.done:
        return null;
      case DeletionReauthPhase.checking:
        return const SignupNote(tone: SignupNoteTone.progress, text: '준비하고 있어요.');
      case DeletionReauthPhase.inWindow:
        return const SignupNote(tone: SignupNoteTone.progress, text: '본인확인 창에서 진행해 주세요.');
      case DeletionReauthPhase.verifying:
        return const SignupNote(
            tone: SignupNoteTone.progress, title: '확인 결과를 받고 있어요', text: '잠시만 기다려 주세요.');
      case DeletionReauthPhase.deleting:
        return const SignupNote(
            tone: SignupNoteTone.progress, title: '계정을 정리하고 있어요', text: '창을 닫지 마세요.');
      case DeletionReauthPhase.canceled:
        return const SignupNote(
            tone: SignupNoteTone.neutral, title: '본인확인을 취소했어요', text: '탈퇴는 진행되지 않았어요.');
      case DeletionReauthPhase.expired:
        return SignupNote(tone: SignupNoteTone.caution, text: _c.message ?? kDeletionReauthExpiredMessage);
      case DeletionReauthPhase.failed:
        return SignupNote(
            tone: SignupNoteTone.caution,
            title: _c.proofAlive ? '정리를 마치지 못했어요' : '본인확인을 마치지 못했어요',
            text: _c.message ?? '잠시 후 다시 시도해 주세요.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _withdraw ? '회원 탈퇴' : '계정 삭제를 마무리하고 있어요';
    final desc = _withdraw
        ? '카카오로 가입한 계정은 휴대폰 본인확인으로 탈퇴해요. 탈퇴하면 계정과 데이터가 삭제되며 복구할 수 없어요.'
        : '이전 탈퇴 처리가 끝나지 않았어요. 휴대폰 본인확인을 한 번 더 하면 남은 정리를 마쳐요.';
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final note = _note();
        final h = ResponsiveHelper.spacing(context, 20);
        return PopScope(
          canPop: !_c.busy && _withdraw,
          child: Scaffold(
            backgroundColor: AppColors.surface,
            appBar: _withdraw
                ? AppBar(
                    title: const Text('회원 탈퇴'),
                    backgroundColor: AppColors.surface,
                    foregroundColor: AppColors.textPrimary,
                    elevation: 0,
                  )
                : null,
            body: SafeArea(
              child: ListView(
                padding: EdgeInsets.all(h),
                children: [
                  if (!_withdraw) SizedBox(height: ResponsiveHelper.spacing(context, 24)),
                  Text(
                    TextLayout.keepWords(title),
                    semanticsLabel: title,
                    style: ResponsiveHelper.subtitleStyle(context,
                        color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                  Text(
                    TextLayout.keepWords(desc),
                    semanticsLabel: desc,
                    style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary),
                  ),
                  if (note != null) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                    note,
                  ],
                  if (_withdraw) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 16)),
                    const SignupNote(
                      tone: SignupNoteTone.neutral,
                      text: '같은 카카오로 쓰는 다른 역할 계정이 남아 있으면 카카오 연결은 그대로 두어요.',
                    ),
                  ],
                ],
              ),
            ),
            bottomNavigationBar: SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ElevatedButton(
                      onPressed: _c.busy ? null : _start,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand, // 위험색은 확인창에서만(파괴적 진입에 빨강 금지)
                        foregroundColor: AppColors.textOnDark,
                        disabledBackgroundColor: AppColors.grey200,
                        disabledForegroundColor: AppColors.textSecondary,
                        minimumSize: const Size.fromHeight(52),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text(
                        TextLayout.keepWords(_primaryLabel),
                        semanticsLabel: _primaryLabel,
                        textAlign: TextAlign.center,
                        style: ResponsiveHelper.bodyStyle(context,
                            color: _c.busy ? AppColors.textSecondary : AppColors.textOnDark,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                    if (!_withdraw && widget.onSignOut != null)
                      TextButton(
                        onPressed: _c.busy ? null : () => widget.onSignOut!(),
                        style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        child: const Text('로그아웃'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
