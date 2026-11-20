// lib/screens/user/signature_screen.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/core/user_model.dart';
import '../../providers/user_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/dialog_helper.dart';
import '../../utils/toast_helper.dart';
import '../../utils/text_layout.dart';
import '../../widgets/contract/signature_pad_widget.dart';

/// 사용자 개인 서명 관리 화면
///
/// MY 탭 > 근무 관리 > 내 서명 에서 진입.
///
/// ## 책임
/// - 등록된 서명 미리보기
/// - 서명 등록 / 변경 / 삭제
///
/// ## 서명 저장 경로
/// CF `callableSaveUserSignature` → Firestore users/{uid}.signatureBase64
/// 서명 이미지는 base64로 Firestore 문서에 직접 저장 (500 KB 제한).
///
/// ## 이 화면에 없는 것
/// 사업주 날인(sealBase64) 관리는 SettingsScreen 에서만 처리한다.
class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  // [PERF] base64 변경 시에만 재디코딩 — build 마다 decode 방지
  String? _cachedBase64;
  Uint8List? _cachedBytes;

  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          '내 서명',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: AppColors.borderLight),
        ),
      ),
      body: Selector<UserProvider, UserModel?>(
        selector: (_, p) => p.currentUser,
        builder: (context, user, _) {
          final signatureBase64 = user?.signatureBase64;
          final hasSignature =
              signatureBase64 != null && signatureBase64.isNotEmpty;

          // 캐시 갱신
          if (hasSignature && signatureBase64 != _cachedBase64) {
            _cachedBase64 = signatureBase64;
            _cachedBytes = base64Decode(signatureBase64);
          } else if (!hasSignature) {
            _cachedBase64 = null;
            _cachedBytes = null;
          }

          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
            children: [
              _buildSignatureCard(context, hasSignature),
              const SizedBox(height: 16),
              _buildHelpText(),
            ],
          );
        },
      ),
    );
  }

  // ── 서명 카드 ──────────────────────────────────────────────────

  Widget _buildSignatureCard(BuildContext context, bool hasSignature) {
    final subtitle = hasSignature ? '계약서 서명 시 자동 사용' : '계약서 서명에 사용됩니다';
    return Container(
      padding: const EdgeInsets.all(20),
      // [DU261] 흰·grey200 선, 반경 14 → 16(앱 카드 기준)
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── 헤더 ──────────────────────────────────────────────
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                // [DU261] 파랑 상자 → S082 설정 아이콘 상자와 같은 중립(grey100·grey600)
                decoration: BoxDecoration(
                  color: AppColors.grey100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.draw_outlined,
                    color: AppColors.grey600, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '내 서명',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      TextLayout.keepWords(subtitle),
                      semanticsLabel: subtitle,
                      style: const TextStyle(
                        fontSize: 13,
                        // 완료 상태는 right-side badge로만 표현 — 텍스트에 green 중복 금지
                        // [DU261] grey500 12(2.68) → 보조색 13, 낱말 단위 줄바꿈
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              if (hasSignature)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.successBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    '등록됨',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.successDark,
                    ),
                  ),
                ),
            ],
          ),

          // ── 서명 미리보기 ──────────────────────────────────────
          // ── 서명 미리보기 ──────────────────────────────────────
          if (hasSignature && _cachedBytes != null) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              height: 110,
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.grey200),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(
                  _cachedBytes!,
                  fit: BoxFit.contain,
                  semanticLabel: '등록된 서명 이미지',
                ),
              ),
            ),
          ],

          // ── 미등록 상태 빈 영역 안내 ────────────────────────────
          if (!hasSignature) ...[
            const SizedBox(height: 16),
            // [DU261 r1] 고정 높이 80 → 최소 80(큰 글자에서 잘리지 않게), 낱말 단위 줄바꿈·가운데 정렬
            //   (B320 에서 '없습니/다' 로 끊겼다).
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.grey200),
              ),
              child: Text(
                TextLayout.keepWords('등록된 서명이 없습니다'),
                semanticsLabel: '등록된 서명이 없습니다',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary), // [DU261] grey400(1.8)
              ),
            ),
          ],

          // ── 액션 ───────────────────────────────────────────────
          // [DU261] UI-1 버튼 기준 — 주 행동은 대표색, 보조·위험은 테두리 없는 중립 글자(왼쪽). 터치 48 이상.
          //   이전: 회색 12 글자·padding 0·최소 크기 0(터치 17), 삭제는 연한 빨강(진입에 위험색 — 빨강은 확인 대화에만).
          //   서명 없음: 전체 폭 대표색 채움 '서명 등록'(이 화면의 주 행동).
          //   서명 있음: 왼쪽 '삭제'(중립), 오른쪽 '서명 변경'(대표색). 좁은 폭·큰 글자에서는 다음 줄로 내려간다(Wrap).
          if (!hasSignature) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : () => _register(context, isChange: false),
                    icon: const Icon(Icons.add_outlined, size: 18),
                    label: const Text('서명 등록'),
                  ),
                ),
                if (_isSaving) ...[
                  const SizedBox(width: 12),
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                ],
              ],
            ),
          ] else ...[
            const SizedBox(height: 12),
            const Divider(height: 1, color: AppColors.borderLight),
            const SizedBox(height: 4),
            // [DU261 r1] Wrap 이 내용 폭으로 줄어 양 끝 정렬이 안 됐다(삭제·변경이 모두 왼쪽) — 카드 폭으로 편다.
            SizedBox(
              width: double.infinity,
              child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _isSaving ? null : () => _delete(context),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('삭제'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    minimumSize: const Size(48, 48),
                    textStyle: const TextStyle(
                        fontFamily: 'NotoSansKR', fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isSaving) ...[
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 1.5),
                      ),
                      const SizedBox(width: 8),
                    ],
                    TextButton.icon(
                      onPressed: _isSaving ? null : () => _register(context, isChange: true),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('서명 변경'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.brand,
                        minimumSize: const Size(48, 48),
                        textStyle: const TextStyle(
                            fontFamily: 'NotoSansKR', fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            ),
          ],

          const SizedBox(height: 2),
        ],
      ),
    );
  }

  // ── 안내 텍스트 ────────────────────────────────────────────────

  static const _helpText = '서명은 계약서·근무확인서 서명 시 자동으로 사용됩니다. '
      '본인 서명만 등록해 주세요.';

  Widget _buildHelpText() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline,
            size: 14, color: AppColors.textTertiary), // [DU261] textHint(1.75) → textTertiary
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            TextLayout.keepWords(_helpText),
            semanticsLabel: _helpText,
            // [DU261] textHint 12(1.75) → 보조색 13, 낱말 단위 줄바꿈
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ),
      ],
    );
  }

  // ── 액션 ──────────────────────────────────────────────────────

  Future<void> _register(BuildContext context, {bool isChange = false}) async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    if (uid == null) return;

    final bytes = await showSignaturePad(
      context,
      title: isChange ? '내 서명 변경' : '내 서명 등록',
    );
    if (bytes == null || !mounted) return;

    // [SEC-SS01] 서명 이미지 크기 제한 — Firestore 문서 1MB 한계 방어
    if (bytes.length > 500000) {
      if (mounted) ToastHelper.showError('서명 이미지가 너무 큽니다. 더 작게 그려주세요.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      final b64 = base64Encode(bytes);
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableSaveUserSignature')
          .call({'signatureBase64': b64});
      // [F-07-3] CF 성공 확정 — refresh 실패가 서명 등록 실패로 오인되지 않도록 별도 처리
      try {
        await userProvider.refreshUserData();
      } catch (e) {
        debugPrint('⚠️ 사용자 정보 갱신 실패 (서명은 저장됨): $e');
      }
      if (mounted) ToastHelper.showSuccess('서명이 등록되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('서명 등록에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final userProvider = context.read<UserProvider>();
    final uid = userProvider.currentUser?.uid;
    if (uid == null) return;

    final confirm = await DialogHelper.showDangerConfirm(
      context,
      title: '서명 삭제',
      message: '삭제하면 계약서 서명 시 자동으로 사용할 수 없습니다.\n등록된 서명을 삭제하시겠습니까?',
      confirmText: '삭제',
    );
    if (confirm != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableSaveUserSignature')
          .call({'signatureBase64': null});
      // [F-07-3] CF 성공 확정 — refresh 실패가 서명 삭제 실패로 오인되지 않도록 별도 처리
      try {
        await userProvider.refreshUserData();
      } catch (e) {
        debugPrint('⚠️ 사용자 정보 갱신 실패 (서명은 삭제됨): $e');
      }
      if (mounted) ToastHelper.showSuccess('서명이 삭제되었습니다');
    } catch (e) {
      if (mounted) ToastHelper.showError('서명 삭제에 실패했습니다');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}
