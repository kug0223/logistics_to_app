import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:provider/provider.dart';
import '../../models/core/legal_terms_model.dart';
import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../services/legal_terms_service.dart';
import '../../utils/toast_helper.dart';
import '../../theme/app_colors.dart';
import 'foreign_register_screen.dart';

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
  const RegistrationRecoveryScreen({super.key});

  @override
  State<RegistrationRecoveryScreen> createState() =>
      _RegistrationRecoveryScreenState();
}

enum _RecoveryCase { loading, termsOnly, needForeignDoc, error }

class _RegistrationRecoveryScreenState
    extends State<RegistrationRecoveryScreen> {
  final LegalTermsService _legalTermsService = LegalTermsService();
  final _db = FirebaseFirestore.instance;

  _RecoveryCase _case = _RecoveryCase.loading;
  bool _isRecording = false;
  LegalTerms? _legalTerms;
  String? _errorMessage;
  UserRole _userRole = UserRole.USER;

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

    final uid = FirebaseAuth.instance.currentUser?.uid;
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
      final doc = await _db.collection('users').doc(uid).get();
      await termsFuture;

      if (!mounted) return;

      if (!doc.exists) {
        setState(() {
          _case = _RecoveryCase.error;
          _errorMessage = '계정 정보를 찾을 수 없습니다. 다시 로그인해주세요.';
        });
        return;
      }

      final data = doc.data()!;
      final hasFingerprint = data['foreignIdentityFingerprint'] != null;
      final hasIdCard = data['idCardImagePath'] != null || data['idCardImageUrl'] != null;
      final roleStr = data['role'] as String?;
      _userRole = roleStr == 'BUSINESS_ADMIN' ? UserRole.BUSINESS_ADMIN : UserRole.USER;

      // [CASE C] fingerprint 없음 + 기존 idCardImagePath 있음
      // → ForeignRegisterScreen에 전달하여 Storage 파일 재사용 시도 (재업로드 최소화)
      _existingIdCardPath = data['idCardImagePath'] as String?;

      setState(() {
        // CASE A/E: fingerprint + idCard 완료 → 약관만 재기록
        // CASE B/C/D: idCard 또는 fingerprint 없음 → ForeignRegisterScreen 재진입
        _case = (hasFingerprint && hasIdCard)
            ? _RecoveryCase.termsOnly
            : _RecoveryCase.needForeignDoc;
      });
    } catch (e) {
      debugPrint('❌ [RecoveryScreen] 케이스 판단 실패: $e');
      if (!mounted) return;
      // 폴백: 약관 재호출 시도 (idempotent — 이미 완료된 경우 무해)
      setState(() => _case = _RecoveryCase.termsOnly);
    }
  }

  Future<void> _loadTerms() async {
    try {
      final terms = await _legalTermsService.getTerms();
      if (mounted) setState(() => _legalTerms = terms);
    } catch (_) {
      if (mounted) setState(() => _legalTerms = LegalTerms.defaultTerms());
    }
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
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _errorMessage = 'Auth 세션이 만료되었습니다. 다시 로그인해주세요.');
      return;
    }

    setState(() { _isRecording = true; _errorMessage = null; });

    try {
      final consentRecord = <String, dynamic>{};
      for (final item in terms.activeItems) {
        consentRecord[item.id] = {'agreed': true, 'version': item.version};
      }

      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableRecordTermsConsent',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 15)))
          .call({'consentRecord': consentRecord});

      if (!mounted) return;

      // 계정 상태 재확인 — active 전환 여부 확인
      final doc = await _db.collection('users').doc(uid).get();
      final newStatus = doc.data()?['accountStatus'] as String?;

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

  // ── CASE A/E: 약관 재기록 ────────────────────────────────────
  Widget _buildTermsStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildIcon(Icons.assignment_late_outlined, Colors.orange),
          const SizedBox(height: 20),
          Text('가입 완료가 필요합니다',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text('이전 가입 시 약관 동의 기록이 완료되지 않았습니다.\n아래 버튼을 눌러 완료해주세요.'),
          const SizedBox(height: 24),
          _buildErrorBanner(),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isRecording ? null : _recordTermsConsent,
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              child: _isRecording
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('가입 완료하기'),
            ),
          ),
          const SizedBox(height: 12),
          _buildSignOutButton(),
        ],
      ),
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
