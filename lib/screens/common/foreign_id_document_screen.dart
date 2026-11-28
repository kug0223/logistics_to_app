// lib/screens/common/foreign_id_document_screen.dart
//
// [ALFIT-AUTH-KAKAO-ONBOARDING.1 · impl_plan §5 · C277-02] 가입 후 외국인등록증 정보 등록(새 흐름 계정).
//
//   가입 직후 국적 미확정(nationalityStatus 'unknown') 사용자가 '외국인등록증' 을 고르면 먼저 여기서
//   등록번호 · 영문 이름을 서버(callableRegisterForeignIdDocument)에 보낸다. 서버가 번호 구조 · 본인확인
//   생년월일 대조 뒤 nationalityStatus='foreign' 을 쓰면, 이어서 기존 등록증 사진 올리기(5~8 규칙)로 간다.
//
//   · 옛 가입 함수(callableFinalizeForeignIdentity)를 쓰지 않는다 — 옛 가입 sentinel 을 만들지 않는다(clean cutover).
//   · 13자리 번호는 메모리 → HTTPS 로만 보내고 저장 · 로그 · 화면 재표시 0. 화면을 떠나면 지운다.
//   · 이 입력은 서류 등록 보조다. 국적 · 진위 · 취업자격을 확인한다는 뜻이 아니다(문구도 그렇게 쓰지 않는다).
//   · 사진의 글자 읽기(OCR)는 다음 단계(사진 올리기)에서 기존 도구가 입력 보조로만 한다.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../services/auth/signup_api.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../widgets/common/common_widgets.dart';

/// 서버 호출 경계(시험 대역 가능). 성공이면 null, 실패면 사용자 문장.
typedef ForeignIdRegistrar = Future<String?> Function(Map<String, dynamic> payload);

/// 앱 쪽 1차 형식 확인(서버가 다시 확인한다). 13자리 · 7번째 자리 5~8.
String? foreignIdFormatProblem(String digits) {
  if (digits.length != 13) return '외국인등록번호 13자리를 입력해 주세요';
  final g = int.tryParse(digits[6]);
  if (g == null || g < 5 || g > 8) return '외국인등록번호 뒤 7자리의 첫 숫자를 확인해 주세요';
  return null;
}

class ForeignIdDocumentScreen extends StatefulWidget {
  const ForeignIdDocumentScreen({super.key, this.registrar});

  final ForeignIdRegistrar? registrar;

  @override
  State<ForeignIdDocumentScreen> createState() => _ForeignIdDocumentScreenState();
}

class _ForeignIdDocumentScreenState extends State<ForeignIdDocumentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _idCtrl = TextEditingController();
  final _legalCtrl = TextEditingController();
  final _koreanCtrl = TextEditingController();
  final _visaCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _idCtrl.clear();
    _idCtrl.dispose();
    _legalCtrl.dispose();
    _koreanCtrl.dispose();
    _visaCtrl.dispose();
    super.dispose();
  }

  static Future<String?> _serverRegistrar(Map<String, dynamic> payload) async {
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableRegisterForeignIdDocument',
              options: HttpsCallableOptions(timeout: const Duration(seconds: 20)))
          .call(payload);
      return null;
    } on FirebaseFunctionsException catch (e) {
      final d = e.details;
      final reason = d is Map ? d['reason'] : null;
      debugPrint('⚠️ [foreignIdDoc] ${e.code} reason=$reason'); // 번호 · 이름은 찍지 않는다
      return SignupCopy.reasonMessage(reason is String ? reason : null, code: e.code);
    } catch (e) {
      return SignupCopy.reasonMessage(null);
    }
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    final payload = <String, dynamic>{
      'rawForeignId': _idCtrl.text.replaceAll(RegExp(r'[^0-9]'), ''),
      'legalName': _legalCtrl.text.trim(),
      if (_koreanCtrl.text.trim().isNotEmpty) 'koreanName': _koreanCtrl.text.trim(),
      if (_visaCtrl.text.trim().isNotEmpty) 'visaType': _visaCtrl.text.trim().toUpperCase(),
    };
    final err = await (widget.registrar ?? _serverRegistrar)(payload);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _error = err;
      });
      return;
    }
    _idCtrl.clear();
    // 서버가 nationalityStatus 를 바꿨다 — 사진 단계가 새 값(외국인 규칙)을 쓰도록 다시 읽는다.
    await context.read<UserProvider>().refreshCurrentUser();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  InputDecoration _dec(String label, {String? hint, String? helper}) => InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        helperMaxLines: 3,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      );

  @override
  Widget build(BuildContext context) {
    final gap = ResponsiveHelper.spacing(context, 14);
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('외국인등록증 정보'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
          children: [
            Text(
              TextLayout.keepWords('외국인등록증에 적힌 대로 입력해 주세요'),
              semanticsLabel: '외국인등록증에 적힌 대로 입력해 주세요',
              style: ResponsiveHelper.subtitleStyle(context,
                  color: AppColors.textPrimary, fontWeight: FontWeight.w700),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(
              TextLayout.keepWords('입력한 번호는 화면에 다시 보이지 않아요. 다음 단계에서 등록증 사진을 올려요.'),
              semanticsLabel: '입력한 번호는 화면에 다시 보이지 않아요. 다음 단계에서 등록증 사진을 올려요.',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
            TextFormField(
              controller: _idCtrl,
              enabled: !_busy,
              obscureText: true,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(13),
              ],
              autofillHints: const <String>[],
              enableSuggestions: false,
              autocorrect: false,
              decoration: _dec('외국인등록번호', hint: '숫자 13자리', helper: '- 없이 숫자만 입력해요'),
              validator: (v) => foreignIdFormatProblem(v ?? ''),
            ),
            SizedBox(height: gap),
            TextFormField(
              controller: _legalCtrl,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              decoration: _dec('영문 이름', hint: '등록증의 성명(영문)'),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return '영문 이름을 입력해 주세요';
                if (t.length > 100) return '이름이 너무 길어요';
                return null;
              },
            ),
            SizedBox(height: gap),
            TextFormField(
              controller: _koreanCtrl,
              enabled: !_busy,
              decoration: _dec('한국어 이름(선택)', helper: '앱에서 부를 이름이에요. 비워 두어도 돼요'),
              validator: (v) => (v ?? '').trim().length > 100 ? '이름이 너무 길어요' : null,
            ),
            SizedBox(height: gap),
            TextFormField(
              controller: _visaCtrl,
              enabled: !_busy,
              textCapitalization: TextCapitalization.characters,
              decoration: _dec('체류자격(선택)', hint: '예: E-9, F-4'),
              validator: (v) => (v ?? '').trim().length > 10 ? '체류자격을 확인해 주세요' : null,
            ),
            if (_error != null) ...[
              SizedBox(height: gap),
              Container(
                padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
                decoration: CommonWidgets.compactCardDecoration(color: AppColors.warningBg),
                child: Text(
                  TextLayout.keepWords(_error!),
                  semanticsLabel: _error,
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.warningInk),
                ),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
          child: ElevatedButton(
            onPressed: _busy ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.brand,
              foregroundColor: AppColors.textOnDark,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: 0,
            ),
            child: _busy
                ? const SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text('다음 · 사진 올리기',
                    style: ResponsiveHelper.bodyStyle(context,
                        color: AppColors.textOnDark, fontWeight: FontWeight.w600)),
          ),
        ),
      ),
    );
  }
}
