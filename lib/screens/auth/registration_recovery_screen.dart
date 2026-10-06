import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/core/legal_terms_model.dart';
import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../utils/terms_consent_plan.dart';
import '../../utils/toast_helper.dart';
import '../../theme/app_colors.dart';
import '../../widgets/auth/legal_consent_list.dart';
import 'foreign_register_screen.dart';
import 'registration_recovery_reads.dart';

/// [V3 FOREIGN-DOCUMENT-FIRST] 외국인 가입 미완료 복구 화면
///
/// auth_service.signIn()이 IncompleteRegistrationException throw →
/// user_provider가 _hasIncompleteRegistration = true → AuthWrapper가 이 화면으로 라우팅.
///
/// Firestore를 직접 읽어 CASE 판단 (user_provider는 pending 계정의 _currentUser를 null로 설정).
///
/// CASE A/E: fingerprint + idCard 있음 → callableRecordTermsConsent 재호출
/// CASE B:   fingerprint 있음, idCard 없음 → ForeignRegisterScreen으로 복귀
/// CASE C/D: fingerprint 없음 → ForeignRegisterScreen으로 복귀 (OCR/입력 재시도)
class RegistrationRecoveryScreen extends StatefulWidget {
  const RegistrationRecoveryScreen({super.key, this.reads});

  /// 테스트에서 갈아끼우는 읽기·기록 경계. 운영에서는 null.
  final RegistrationRecoveryReads? reads;

  @override
  State<RegistrationRecoveryScreen> createState() =>
      _RegistrationRecoveryScreenState();
}

enum _RecoveryCase { loading, termsOnly, needForeignDoc, error }

class _RegistrationRecoveryScreenState
    extends State<RegistrationRecoveryScreen> {
  late final RegistrationRecoveryReads _reads =
      widget.reads ?? RegistrationRecoveryReads.of();

  _RecoveryCase _case = _RecoveryCase.loading;
  bool _isRecording = false;
  LegalTerms? _legalTerms;
  String? _errorMessage;
  UserRole _userRole = UserRole.USER;

  /// 이미 받아 둔 동의. 다시 묻지도, 덮어쓰지도 않는다.
  Map<String, StoredConsent> _stored = const {};

  /// 이 화면에서 사용자가 실제로 고른 값.
  Map<String, bool> _choices = const {};

  /// 본문을 연 적 있는 항목 — 보지 않은 약관에 체크부터 하게 두지 않는다.
  final Set<String> _viewed = <String>{};

  /// CASE C: fingerprint 없음 + 기존 idCard 있음
  /// ForeignRegisterScreen에 전달 → OCR 재실행으로 재업로드 불필요
  String? _existingIdCardPath;

  @override
  void initState() {
    super.initState();
    _detectCase();
  }

  // ============================================================
  // CASE 판단 — Firestore 직접 읽기
  // ============================================================

  Future<void> _detectCase() async {
    setState(() { _case = _RecoveryCase.loading; _errorMessage = null; });

    final uid = _reads.currentUid();
    if (uid == null) {
      setState(() {
        _case = _RecoveryCase.error;
        _errorMessage = 'Auth 세션이 만료되었습니다. 다시 로그인해주세요.';
      });
      return;
    }

    try {
      // 약관 데이터 로드 (병렬)
      final termsFuture = _loadTerms();

      // Firestore 직접 읽기 (user_provider pending guard 우회)
      final data = await _reads.userDoc(uid);
      await termsFuture;

      if (!mounted) return;

      if (data == null) {
        setState(() {
          _case = _RecoveryCase.error;
          _errorMessage = '계정 정보를 찾을 수 없습니다. 다시 로그인해주세요.';
        });
        return;
      }

      // [LEGAL-1A] 이미 받아 둔 동의를 먼저 읽는다. 이것을 모르면 다시 묻게
      //   되고, 다시 물으면 최초 동의 시각이 지금으로 밀린다.
      _stored = StoredConsent.parseMap(data['termsConsent']);

      final hasFingerprint = data['foreignIdentityFingerprint'] != null;
      final hasIdCard = data['idCardImagePath'] != null || data['idCardImageUrl'] != null;
      final roleStr = data['role'] as String?;
      _userRole = roleStr == 'BUSINESS_ADMIN' ? UserRole.BUSINESS_ADMIN : UserRole.USER;

      // [CASE C] fingerprint 없음 + 기존 idCardImagePath 있음
      // → ForeignRegisterScreen에 전달하여 Storage 파일 재사용 시도 (재업로드 최소화)
      _existingIdCardPath = data['idCardImagePath'] as String?;

      setState(() {
        _seedChoices();
        // CASE A/E: fingerprint + idCard 완료 → 약관 동의를 받는다
        // CASE B/C/D: idCard 또는 fingerprint 없음 → ForeignRegisterScreen 재진입
        _case = (hasFingerprint && hasIdCard)
            ? _RecoveryCase.termsOnly
            : _RecoveryCase.needForeignDoc;
      });
    } catch (e) {
      debugPrint('❌ [RecoveryScreen] 케이스 판단 실패: $e');
      if (!mounted) return;
      // 폴백: 약관 동의 단계로 보낸다. 기존 동의를 읽지 못했으므로 전부
      //   물어야 한다 — 모르는 것을 "이미 동의함"으로 그리지 않는다.
      setState(() {
        _stored = const {};
        _seedChoices();
        _case = _RecoveryCase.termsOnly;
      });
    }
  }

  Future<void> _loadTerms() async {
    try {
      final terms = await _reads.terms();
      if (mounted) setState(() => _legalTerms = terms);
    } catch (_) {
      if (mounted) setState(() => _legalTerms = LegalTerms.defaultTerms());
    }
  }

  /// 체크박스 초기값을 세운다. `_stored` 와 `_legalTerms` 가 모두 있어야
  /// 뜻이 생기므로 둘이 모인 뒤 한 번만 세운다.
  void _seedChoices() {
    final terms = _legalTerms;
    if (terms == null) return;
    _choices = TermsConsentPlan.initialChoices(
      activeItems: terms.activeItems,
      stored: _stored,
    );
  }

  // ============================================================
  // CASE A/E: callableRecordTermsConsent 재호출
  // ============================================================

  Future<void> _recordTermsConsent() async {
    final terms = _legalTerms;
    if (terms == null) {
      ToastHelper.showWarning('약관 정보를 불러오는 중입니다. 잠시 후 다시 시도해주세요.');
      return;
    }
    final uid = _reads.currentUid();
    if (uid == null) {
      setState(() => _errorMessage = 'Auth 세션이 만료되었습니다. 다시 로그인해주세요.');
      return;
    }

    // [LEGAL-1A] 필수 항목을 고르지 않았으면 아무것도 보내지 않는다.
    //   버튼이 이미 막혀 있지만, 기록 경로에서도 한 번 더 막는다 — 동의는
    //   화면 상태가 아니라 사용자의 선택이어야 한다.
    if (!TermsConsentPlan.allRequiredChosen(
        activeItems: terms.activeItems, stored: _stored, choices: _choices)) {
      setState(() => _errorMessage = '필수 약관에 동의해야 가입을 완료할 수 있습니다.');
      return;
    }

    setState(() { _isRecording = true; _errorMessage = null; });

    try {
      // 사용자가 **이 화면에서 고른 것**만 보낸다. 이미 같은 버전으로 동의한
      //   항목은 빠진다 — 다시 보내면 최초 동의 시각이 지금으로 밀린다.
      final consentRecord = TermsConsentPlan.buildPayload(
        activeItems: terms.activeItems,
        stored: _stored,
        choices: _choices,
      );

      if (consentRecord.isNotEmpty) {
        await _reads.recordConsent(consentRecord);
      }

      if (!mounted) return;

      // 계정 상태 재확인 — active 전환 여부 확인
      final fresh = await _reads.userDoc(uid);
      final newStatus = fresh?['accountStatus'] as String?;

      if (!mounted) return;

      if (newStatus == 'active') {
        ToastHelper.showSuccess('가입이 완료되었습니다!');
        // UserProvider 갱신 후 AuthWrapper가 HOME으로 라우팅
        await context.read<UserProvider>().refreshUserData();
        if (!mounted) return;
        Navigator.of(context).popUntil((route) => route.isFirst);
      } else {
        // 여전히 pending → idCard 또는 fingerprint 부족
        setState(() {
          _isRecording = false;
          _case = _RecoveryCase.needForeignDoc;
        });
        ToastHelper.showWarning('추가 정보 등록이 필요합니다.');
      }
    } catch (e) {
      debugPrint('❌ [RecoveryScreen] 약관 동의 기록 실패: $e');
      if (mounted) {
        setState(() {
          _isRecording = false;
          _errorMessage = '서버 통신에 실패했습니다.\n인터넷 연결을 확인하고 다시 시도해주세요.';
        });
      }
    }
  }

  Future<void> _handleSignOut() async {
    await context.read<UserProvider>().signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // ============================================================
  // Build
  // ============================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('가입 완료'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: switch (_case) {
          _RecoveryCase.loading        => const Center(child: CircularProgressIndicator()),
          _RecoveryCase.error          => _buildError(),
          _RecoveryCase.termsOnly      => _buildTermsStep(),
          _RecoveryCase.needForeignDoc => _buildForeignDocStep(),
        },
      ),
    );
  }

  // ── CASE A/E: 약관 동의 ──────────────────────────────────────
  //
  // 예전에는 여기서 "아래 버튼을 눌러 완료해주세요" 한 줄만 보여 주고,
  // 활성 약관 전부를 `agreed: true` 로 만들어 보냈다. 사용자는 본문도 못 보고
  // 고르지도 못했으며, 선택 항목인 마케팅 수신까지 동의로 기록됐다.
  // 이제 가입 화면과 같은 것을 묻는다 — 보고, 고르고, 그 선택만 보낸다.
  Widget _buildTermsStep() {
    final terms = _legalTerms;
    if (terms == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final items = terms.activeItems;
    final canProceed = TermsConsentPlan.allRequiredChosen(
        activeItems: items, stored: _stored, choices: _choices);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            children: [
              _buildIcon(Icons.assignment_late_outlined, Colors.orange),
              const SizedBox(height: 20),
              Text('약관 동의가 필요합니다',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              const Text('이전 가입에서 약관 동의가 기록되지 않았습니다.\n'
                  '내용을 확인하고 직접 선택해주세요.'),
              const SizedBox(height: 20),
              LegalConsentList(
                items: items,
                stored: _stored,
                choices: _choices,
                viewed: _viewed,
                enabled: !_isRecording,
                onChanged: (id, v) =>
                    setState(() => _choices = {..._choices, id: v}),
                onViewed: (id) => setState(() => _viewed.add(id)),
              ),
              const SizedBox(height: 16),
              _buildErrorBanner(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  // 필수 항목을 고르기 전에는 진행할 수 없다.
                  onPressed: (_isRecording || !canProceed)
                      ? null
                      : _recordTermsConsent,
                  style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _isRecording
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Text('동의하고 가입 완료'),
                ),
              ),
              const SizedBox(height: 12),
              _buildSignOutButton(),
            ],
          ),
        ),
      ],
    );
  }

  // ── CASE B/C/D: 외국인등록증 재입력 ──────────────────────────
  Widget _buildForeignDocStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildIcon(Icons.credit_card_outlined, Colors.blue),
          const SizedBox(height: 20),
          Text('외국인등록증 정보 등록 필요',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text(
            '외국인등록증 정보나 이미지가 아직 등록되지 않았습니다.\n'
            '외국인 가입 화면에서 이어서 등록해주세요.',
          ),
          const SizedBox(height: 24),
          _buildErrorBanner(),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => ForeignRegisterScreen(
                    role: _userRole,
                    isResume: true,              // 기존 uid 유지 — 새 계정 생성 금지
                    existingIdCardPath: _existingIdCardPath, // CASE C: 재업로드 없이 OCR 재실행
                  ),
                ),
              ),
              icon: const Icon(Icons.credit_card),
              label: const Text('외국인 가입 이어서 완료'),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ),
          const SizedBox(height: 12),
          _buildSignOutButton(),
        ],
      ),
    );
  }

  // ── 오류 화면 ────────────────────────────────────────────────
  Widget _buildError() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildIcon(Icons.error_outline, Colors.red),
          const SizedBox(height: 20),
          Text('상태 확인 실패',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(_errorMessage ?? '알 수 없는 오류가 발생했습니다.'),
          const Spacer(),
          SizedBox(width: double.infinity, child: ElevatedButton(onPressed: _detectCase, child: const Text('다시 시도'))),
          const SizedBox(height: 12),
          _buildSignOutButton(),
        ],
      ),
    );
  }

  // ── 공통 위젯 ────────────────────────────────────────────────

  Widget _buildIcon(IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), shape: BoxShape.circle),
      child: Icon(icon, size: 40, color: color),
    );
  }

  Widget _buildErrorBanner() {
    if (_errorMessage == null) return const SizedBox.shrink();
    return Column(children: [
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(_errorMessage!, style: TextStyle(color: Colors.red.shade700))),
        ]),
      ),
      const SizedBox(height: 16),
    ]);
  }

  Widget _buildSignOutButton() {
    return SizedBox(
      width: double.infinity,
      child: TextButton(
        onPressed: _isRecording ? null : _handleSignOut,
        child: const Text('로그인 화면으로 돌아가기', style: TextStyle(color: AppColors.grey500)),
      ),
    );
  }
}
