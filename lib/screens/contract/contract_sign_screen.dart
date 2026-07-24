import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/core/contract_template_model.dart';
import '../../models/core/to_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../models/core/insurance_rate_model.dart';
import '../../providers/user_provider.dart';
import '../../services/contract_service.dart';
import '../../theme/app_colors.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/contract/signature_pad_widget.dart';
import 'contract_pdf_builder.dart';
import '../../widgets/common/gradient_scaffold.dart';
import '../common/settings_screen.dart';
import '../../utils/dialog_helper.dart';

/// 계약서 확인 + 서명 화면 (사업주 / 근무자 공용)
///
/// [role] : 'employer' 또는 'worker'
class ContractSignScreen extends StatefulWidget {
  final EmploymentContractModel contract;
  final String role; // 'employer' | 'worker'

  const ContractSignScreen({
    super.key,
    required this.contract,
    required this.role,
  });

  @override
  State<ContractSignScreen> createState() => _ContractSignScreenState();
}

class _ContractSignScreenState extends State<ContractSignScreen> {
  final _service = ContractService();
  final _scrollController = ScrollController();

  bool _hasReadAll = false;
  bool _agreed = false;
  bool _isSigning = false;
  bool _isSharingPdf = false;

  // 근무자 사전 등록 서명 (base64)
  String? _savedSignatureBase64;
  // 사업주 인감 (base64)
  String? _businessSealBase64;
  // 날인 방식: 'stamp'(도장) | 'signature'(서명)
  String _businessSealType = 'stamp';
  // 대표자 이름 (snapshot.ownerName이 비어있을 때 Firestore에서 조회)
  String? _resolvedOwnerName;
  // TO 타입 기반 isLongTerm override (구 계약서 데이터 보정)
  bool? _toIsContract;

  bool get isEmployer => widget.role == 'employer';
  // 실제 표시용 isLongTerm: TO 타입이 'contract'이면 항상 true
  bool get _effectiveIsLongTerm =>
      _toIsContract == true || widget.contract.snapshot.isLongTerm;
  bool get _hasSavedSignature => _savedSignatureBase64 != null && _savedSignatureBase64!.isNotEmpty;
  bool get _hasSeal => _businessSealBase64 != null && _businessSealBase64!.isNotEmpty;
  // 현재 역할이 서명해야 할 차례인지 — false면 이미 서명했거나 대기 순서가 아님
  bool get _needsMySignature => isEmployer
      ? widget.contract.needsEmployerSignature
      : widget.contract.needsWorkerSignature;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (isEmployer) {
        // 사업주: 사업자 인감 로드 (내부에서 TO 타입도 확인)
        await _loadBusinessSeal();
      } else {
        // 근무자: 사전 등록 서명 로드 + 사업주 인감 로드 + TO 타입 확인
        final user = context.read<UserProvider>().currentUser;
        if (user?.signatureBase64 != null) {
          if (mounted) setState(() => _savedSignatureBase64 = user!.signatureBase64);
        }
        await _loadBusinessSeal(); // 근로자 화면에도 사업주 인감 표시
      }
      // 스크롤이 불필요한 경우 자동 해제
      if (mounted && !_hasReadAll &&
          _scrollController.hasClients &&
          _scrollController.position.maxScrollExtent <= 0) {
        setState(() => _hasReadAll = true);
      }
    });
  }

  Future<void> _loadBusinessSeal() async {
    // 근무자 경로: businesses 문서 조회 없이 ownerId 노출 방지
    // ownerName은 계약서 스냅샷에서만 참조
    if (widget.role != 'employer') {
      if (widget.contract.snapshot.ownerName.isNotEmpty && mounted) {
        setState(() => _resolvedOwnerName = widget.contract.snapshot.ownerName.trim());
      }
      await _checkTOType();
      return;
    }
    // TO 타입 조회는 businesses/users 순차 fetch와 독립적 — 병렬 실행으로 RTT 1회 절약
    final toTypeFuture = _checkTOType();
    try {
      final doc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.contract.businessId)
          .get();
      final data = doc.data();
      if (!mounted || data == null) return;

      final ownerId = data['ownerId'] as String?;
      String? sealBase64;
      String sealType = 'stamp';
      String? ownerName;

      // 날인은 users/{ownerId}에서 로드 — 사업주 경로에서만 실행
      if (ownerId != null) {
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(ownerId)
              .get();
          final ud = userDoc.data();
          sealBase64 = ud?['sealBase64'] as String?;
          sealType = ud?['sealType'] as String? ?? 'stamp';
          // ownerName: snapshot에 없으면 business→user 순으로 폴백
          if (widget.contract.snapshot.ownerName.isEmpty) {
            ownerName = data['ownerName'] as String?;
            if (ownerName == null || ownerName.trim().isEmpty) {
              final ceo = ud?['ceoName'] as String?;
              ownerName = (ceo?.trim().isNotEmpty == true) ? ceo : ud?['name'] as String?;
            }
          }
        } catch (e) {
          debugPrint('⚠️ 사업주 정보 조회 실패: $e');
          if (mounted) ToastHelper.showError('사업주 정보를 불러오는데 실패했습니다.');
        }
      }

      if (!mounted) return;
      setState(() {
        if (sealBase64 != null && sealBase64.isNotEmpty) {
          _businessSealBase64 = sealBase64;
        }
        _businessSealType = sealType;
        if (ownerName != null && ownerName.trim().isNotEmpty) {
          _resolvedOwnerName = ownerName.trim();
        }
      });

      await toTypeFuture;
    } catch (e) {
      debugPrint('인감/대표자 로드 실패: $e');
      if (mounted) ToastHelper.showError('계약서 정보를 불러오는데 실패했습니다.');
    }
  }

  /// 구 계약서 isLongTerm 오류 보정: TO 타입이 'contract'이면 _toIsContract = true
  Future<void> _checkTOType() async {
    if (widget.contract.snapshot.isLongTerm || widget.contract.toId.isEmpty) return;
    try {
      final toDoc = await FirebaseFirestore.instance
          .collection('tos')
          .doc(widget.contract.toId)
          .get();
      if (mounted && toDoc.data()?['type'] == TOType.contract) {
        setState(() => _toIsContract = true);
      }
    } catch (e) {
      debugPrint('⚠️ TO 타입 확인 실패 (${widget.contract.toId}): $e');
    }
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_hasReadAll) return;
    final pos = _scrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 60) {
      setState(() => _hasReadAll = true);
    }
  }

  // ── PDF 공유 ─────────────────────────────────────────────────

  Future<void> _sharePdf() async {
    final url = widget.contract.pdfUrl;
    if (url == null) return;
    setState(() => _isSharingPdf = true);
    try {
      final resp = await http.get(Uri.parse(url));
      if (!mounted) return;
      if (resp.statusCode != 200) {
        ToastHelper.showError('PDF를 불러오지 못했습니다.');
        return;
      }
      await Printing.sharePdf(bytes: resp.bodyBytes, filename: '근로계약서.pdf');
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('PDF 공유 중 오류가 발생했습니다.');
    } finally {
      if (mounted) setState(() => _isSharingPdf = false);
    }
  }

  // ── 서명 진입점 ──────────────────────────────────────────────

  Future<void> _sign() async {
    if (!_agreed) {
      ToastHelper.showWarning('내용 확인 동의가 필요합니다');
      return;
    }
    // [BUG-수정] CS-M-1: _sign() 진입 즉시 락 설정 — 바텀시트/서명 패드 await 구간 동안
    // 버튼이 활성 상태로 남아 이중 탭 시 _performSign이 두 번 실행되는 문제 방지.
    // _performSign finally에서 _isSigning = false로 복원됨.
    if (_isSigning) return;
    setState(() => _isSigning = true);
    if (isEmployer) {
      await _signAsEmployer();
    } else {
      if (_hasSavedSignature) {
        await _showSignatureOptions();
      } else {
        await _signWithPad(askToSave: true);
      }
    }
  }

  // ── 사업주: 인감 날인 ─────────────────────────────────────────

  Future<void> _signAsEmployer() async {
    if (!_hasSeal) {
      if (!mounted) return;
      final goToSettings = await DialogHelper.showConfirm(
        context,
        title: '사업주 날인 미등록',
        message: '계약서 발송을 위해 사업주 날인이 필요합니다.\n설정 > 사업주 날인에서 도장 또는 서명을 먼저 등록해주세요.',
        confirmText: '설정으로 이동',
        icon: Icons.verified_outlined,
        iconColor: AppColors.warning,
      );
      // [BUG-수정] CS-M-1: 인감 미등록으로 조기 반환 시 락 해제
      if (mounted) setState(() => _isSigning = false);
      if (goToSettings && mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const SettingsScreen()),
        );
        // 설정에서 날인 등록 후 돌아오면 사업장 정보 새로고침
        if (mounted) _loadBusinessSeal();
      }
      return;
    }
    // 인감 등록됨 → 바로 날인
    final bytes = base64Decode(_businessSealBase64!);
    await _performSign(bytes);
  }

  // 저장 서명 있을 때 선택 바텀시트 (근무자 전용)
  Future<void> _showSignatureOptions() async {
    // [BUG-수정] F-05: void + .then() → Future<void> + async/await 변환.
    // .then()은 await 없이 fire-and-forget으로 실행되어 _isSigning이 영구적으로
    // true 상태에 고착되는 버그 수정. await로 바텀시트 결과를 받고,
    // finally 블록에서 취소 시 락 해제, 서명 진행 시 _performSign finally에서 해제됨.
    // true = 저장 서명, false = 새 서명, null = 취소(드래그 다운 등)
    final choice = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true, // 가로 모드에서 콘텐츠 잘림 방지
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      // [BUG-L1 수정 2026-07-15] useSafeArea: true 와 내부 SafeArea 이중 래핑 제거 (CLAUDE.md 규칙)
      builder: (ctx) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            ResponsiveHelper.spacing(ctx, 24),
            ResponsiveHelper.spacing(ctx, 20),
            ResponsiveHelper.spacing(ctx, 24),
            ResponsiveHelper.spacing(ctx, 16),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('서명 방법 선택',
                  style: ResponsiveHelper.subtitleStyle(ctx)
                      .copyWith(fontWeight: FontWeight.bold)),
              SizedBox(height: ResponsiveHelper.spacing(ctx, 16)),
              // 저장된 서명 미리보기 — 가로 모드 고려해 고정 height 완화
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 80),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.grey300),
                    borderRadius: BorderRadius.circular(10),
                    color: AppColors.grey50,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.memory(
                      base64Decode(_savedSignatureBase64!),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(ctx, 12)),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: ElevatedButton.styleFrom(
                    padding: EdgeInsets.symmetric(
                        vertical: ResponsiveHelper.spacing(ctx, 14)),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('저장된 서명으로 서명'),
                ),
              ),
              SizedBox(height: ResponsiveHelper.spacing(ctx, 8)),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: Text('새 서명 그리기',
                      style: ResponsiveHelper.bodyStyle(ctx,
                          color: AppColors.grey600)),
                ),
              ),
            ],
          ),
        ),
    );
    if (!mounted) return;
    if (choice == null) {
      // 취소(드래그 다운 등) — 락 해제
      setState(() => _isSigning = false);
    } else if (choice) {
      await _signWithSaved();
    } else {
      await _signWithPad(askToSave: true);
    }
  }

  // 저장된 서명으로 서명 처리
  Future<void> _signWithSaved() async {
    final bytes = base64Decode(_savedSignatureBase64!);
    await _performSign(bytes);
  }

  // 서명 패드로 서명 처리
  Future<void> _signWithPad({required bool askToSave}) async {
    final bytes = await showSignaturePad(
      context,
      title: isEmployer ? '사업주 서명' : '근무자 서명',
    );
    if (bytes == null) {
      // [BUG-수정] CS-M-1: 서명 패드 취소 시 락 해제
      if (mounted) setState(() => _isSigning = false);
      return;
    }
    if (!mounted) return;

    // 서명 저장 여부 묻기
    if (askToSave) {
      final save = await _askSaveSignature();
      if (save && mounted) {
        final userProvider = context.read<UserProvider>();
        final uid = userProvider.currentUser?.uid;
        if (uid != null) {
          final b64 = base64Encode(bytes);
          bool signatureSaved = false;
          try {
            await _service.saveUserSignature(uid: uid, base64: b64);
            signatureSaved = true;
          } catch (e) {
            debugPrint('⚠️ 서명 저장 실패: $e');
            if (mounted) ToastHelper.showWarning('서명 저장에 실패했습니다. 계약 서명은 계속 진행합니다.');
          }
          if (!mounted) return;
          if (signatureSaved) {
            setState(() => _savedSignatureBase64 = b64);
            try {
              await userProvider.refreshCurrentUser();
            } catch (e) {
              debugPrint('⚠️ 사용자 정보 갱신 실패 (서명은 저장됨): $e');
            }
          }
        }
      }
    }

    if (mounted) await _performSign(bytes);
  }

  Future<bool> _askSaveSignature() async {
    if (!mounted) return false;
    return DialogHelper.showConfirm(
      context,
      title: '서명 저장',
      message: '이 서명을 저장해두면 다음 계약서 서명 시 바로 사용할 수 있습니다.',
      confirmText: '저장',
      cancelText: '저장 안 함',
      icon: Icons.save_outlined,
      iconColor: Theme.of(context).primaryColor,
    );
  }

  // 실제 서명 저장 + 화면 완료 처리
  Future<void> _performSign(Uint8List bytes) async {
    if (!mounted) return;
    // _sign()에서 이미 _isSigning=true를 설정하지만 _performSign 진입 전
    //           바텀시트/서명패드 다이얼로그 dismiss 과정에서 mounted 상태 변경 가능성이 있어
    //           방어적으로 재설정. _performSign finally에서 false로 복원됨.
    setState(() => _isSigning = true);
    try {
      if (isEmployer) {
        final updated = await _service.saveEmployerSignature(
          contract: widget.contract,
          signatureBytes: bytes,
        );
        if (mounted) {
          ToastHelper.showSuccess('서명이 완료되었습니다. 근무자에게 계약서가 발송됩니다.');
          Navigator.pop(context, updated);
        }
      } else {
        final pdfBytes = await ContractPdfBuilder.build(
          snapshot: widget.contract.snapshot,
          slots: widget.contract.slots,
          articles: widget.contract.articles,
          contractDate: widget.contract.createdAt,
          employerSignatureUrl: widget.contract.employerSignatureUrl,
          workerSignatureBytes: bytes,
          ownerNameOverride: _resolvedOwnerName,
          isLongTermOverride: _effectiveIsLongTerm,
          employerSealType: _businessSealType,
        );
        final updated = await _service.saveWorkerSignature(
          contract: widget.contract,
          signatureBytes: bytes,
          pdfBytes: pdfBytes,
        );
        if (mounted) {
          // 노란 바·출근 차단 즉시 해제 (서명 완료 직후 동기 갱신 필요)
          await Provider.of<UserProvider>(context, listen: false)
              .refreshPendingContracts();
        }
        if (mounted) {
          ToastHelper.showSuccess('계약서 서명이 완료되었습니다!');
          Navigator.pop(context, updated);
        }
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString().replaceFirst('Exception: ', '');
        ToastHelper.showError(msg.isNotEmpty ? msg : '서명 저장에 실패했습니다');
      }
    } finally {
      if (mounted) setState(() => _isSigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final snap = widget.contract.snapshot;

    return GradientScaffold(
      title: '근로계약서',
      showPendingContractBar: false,
      body: Column(
        children: [
          // 안내 배너
          _buildBanner(theme),

          // 계약서 본문 (스크롤)
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
              child: ContractTemplateWidget(
                snapshot: snap,
                contractDate: widget.contract.createdAt,
                slots: widget.contract.slots,
                articles: widget.contract.articles,
                // 서명 시점 고정 URL 우선 — 인감/서명 변경 후에도 계약서가 불변
                employerSignatureUrl: widget.contract.employerSignatureUrl,
                employerSealBase64: _businessSealBase64,
                employerSealType: _businessSealType,
                workerSignatureUrl: widget.contract.workerSignatureUrl,
                ownerNameOverride: _resolvedOwnerName,
                isLongTermOverride: _effectiveIsLongTerm,
              ),
            ),
          ),

          // 하단 동의 + 서명 버튼
          _buildBottomBar(theme),
        ],
      ),
    );
  }

  Widget _buildBanner(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 20),
        vertical: ResponsiveHelper.spacing(context, 12),
      ),
      color: theme.primaryColor.withValues(alpha: 0.06),
      child: Row(
        children: [
          Icon(Icons.info_outline,
              color: theme.primaryColor,
              size: ResponsiveHelper.iconSize(context, 16)),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              _needsMySignature
                  ? (isEmployer
                      ? '내용을 검토 후 서명하면 근무자에게 발송됩니다.'
                      : '내용을 끝까지 확인하신 후 서명해주세요.')
                  // [C-M2-FIX] voided 계약서 딥링크 진입 시 "서명 완료" 오표시 방지
                  : (widget.contract.status == ContractStatus.voided
                      ? '이 계약서는 무효 처리되었습니다.'
                      : (widget.contract.isCompleted
                          ? '쌍방 서명이 완료된 계약서입니다.'
                          : isEmployer
                              ? '서명 완료 — 근무자의 서명을 기다리고 있습니다.'
                              : '서명 완료 — 계약이 확정됩니다.')),
              style: ResponsiveHelper.smallStyle(context,
                  color: theme.primaryColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    return SafeArea(
      top: false,
      child: Container(
      padding: EdgeInsets.fromLTRB(
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 12),
        ResponsiveHelper.spacing(context, 20),
        ResponsiveHelper.spacing(context, 12),
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 동의 체크박스 — 서명이 필요한 경우에만 표시
          if (_needsMySignature) GestureDetector(
            onTap: _hasReadAll
                ? () => setState(() => _agreed = !_agreed)
                : null,
            child: Row(
              children: [
                Icon(
                  _agreed
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  color: _agreed ? theme.primaryColor : AppColors.grey400,
                  size: ResponsiveHelper.iconSize(context, 22),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                Expanded(
                  child: Text(
                    '위 근로계약서의 내용을 모두 확인하였으며 동의합니다.',
                    style: ResponsiveHelper.smallStyle(context).copyWith(
                      color:
                          _hasReadAll ? AppColors.grey800 : AppColors.grey400,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_needsMySignature && !_hasReadAll)
            Padding(
              padding: EdgeInsets.only(
                  left: ResponsiveHelper.spacing(context, 32),
                  top: 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '계약서를 끝까지 읽으면 동의가 가능합니다',
                  style: ResponsiveHelper.tinyStyle(context,
                      color: AppColors.warning),
                ),
              ),
            ),

          SizedBox(height: ResponsiveHelper.spacing(context, 14)),

          // 서명 버튼 또는 완료 표시
          if (_needsMySignature)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_agreed && !_isSigning) ? _sign : null,
                icon: _isSigning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(isEmployer
                        ? Icons.verified_outlined
                        : (_hasSavedSignature
                            ? Icons.check_circle_outline
                            : Icons.draw_outlined)),
                label: Text(_isSigning
                    ? '처리 중...'
                    : isEmployer
                        ? '인감 날인 → 근무자에게 발송'
                        : '서명 완료 → 계약 확정'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  disabledBackgroundColor: AppColors.grey200,
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 16)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  elevation: 0,
                  textStyle: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.bold),
                  foregroundColor: Colors.white,
                ),
              ),
            )
          else
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                      vertical: ResponsiveHelper.spacing(context, 14)),
                  decoration: BoxDecoration(
                    color: AppColors.successBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_rounded,
                          color: AppColors.successDark,
                          size: ResponsiveHelper.iconSize(context, 20)),
                      SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                      Text(
                        widget.contract.isCompleted
                            ? '쌍방 서명이 완료된 계약서입니다'
                            : isEmployer
                                ? '서명 완료 — 근무자 서명 대기 중'
                                : '서명 완료 — 계약이 확정됩니다',
                        style: ResponsiveHelper.bodyStyle(context).copyWith(
                          color: AppColors.successDark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.contract.isCompleted && widget.contract.pdfUrl != null) ...[
                  SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isSharingPdf ? null : _sharePdf,
                      icon: _isSharingPdf
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.primaryColor),
                            )
                          : const Icon(Icons.share_outlined),
                      label: Text(_isSharingPdf ? 'PDF 불러오는 중...' : 'PDF 공유'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.primaryColor,
                        side: BorderSide(color: theme.primaryColor),
                        padding: EdgeInsets.symmetric(
                            vertical: ResponsiveHelper.spacing(context, 12)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle: ResponsiveHelper.bodyStyle(context)
                            .copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ],
            ),
        ],
      ),
      ),  // Container
    );   // SafeArea
  }
}

// ─── 계약서 본문 템플릿 위젯 ─────────────────────────────────────

class ContractTemplateWidget extends StatelessWidget {
  final ContractSnapshot snapshot;
  final DateTime contractDate;
  final List<ContractSlot> slots;
  final List<ContractArticle> articles;
  /// 서명 시점에 Storage에 저장된 사업주 서명 URL — 있으면 base64보다 우선 (불변 보장)
  final String? employerSignatureUrl;
  /// 미서명 상태의 사업주 인감 미리보기용 base64
  final String? employerSealBase64;
  /// 날인 방식: 'stamp'(도장) | 'signature'(서명)
  final String employerSealType;
  /// 서명 시점에 Storage에 저장된 근로자 서명 URL
  final String? workerSignatureUrl;
  final String? ownerNameOverride;
  /// 구 계약서 isLongTerm 오류 보정용 override
  final bool? isLongTermOverride;

  const ContractTemplateWidget({
    super.key,
    required this.snapshot,
    required this.contractDate,
    this.slots = const [],
    this.articles = const [],
    this.employerSignatureUrl,
    this.employerSealBase64,
    this.employerSealType = 'stamp',
    this.workerSignatureUrl,
    this.ownerNameOverride,
    this.isLongTermOverride,
  });

  String get _ownerName {
    if (snapshot.ownerName.isNotEmpty) return snapshot.ownerName;
    return ownerNameOverride ?? '';
  }

  bool get _isLongTerm => isLongTermOverride ?? snapshot.isLongTerm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 24)),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.grey200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 제목
          Center(
            child: Column(
              children: [
                Text(
                  '근 로 계 약 서',
                  style: ResponsiveHelper.titleStyle(context).copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 4,
                  ),
                ),
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Container(
                    height: 2,
                    width: 120,
                    color: theme.primaryColor),
              ],
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 28)),

          _Section(title: '제1조 (근로계약 당사자)', children: [
            _InfoRow(label: '사업장명', value: snapshot.businessName),
            _InfoRow(label: '대표자', value: _ownerName),
            _InfoRow(label: '사업자번호', value: snapshot.businessNumber),
            _InfoRow(label: '소재지', value: snapshot.businessAddress),
            if (snapshot.businessPhone != null)
              _InfoRow(label: '연락처', value: snapshot.businessPhone!),
            _Divider(),
            _InfoRow(label: '근로자 성명', value: snapshot.workerName),
            if (snapshot.workerBirthDate != null)
              _InfoRow(label: '생년월일', value: snapshot.workerBirthDate!),
            if (snapshot.workerPhone != null)
              _InfoRow(label: '연락처', value: snapshot.workerPhone!),
            if (snapshot.workerAddress != null)
              _InfoRow(label: '주소', value: snapshot.workerAddress!),
          ]),

          SizedBox(height: ResponsiveHelper.spacing(context, 20)),

          _Section(title: '제2조 (근무 조건)', children: [
            _InfoRow(label: '근무 장소', value: snapshot.workPlace),
            _InfoRow(label: '담당 업무', value: snapshot.workType),
            if (_isLongTerm) ...[
              _InfoRow(label: '근무 기간', value: snapshot.workPeriodText),
              if (snapshot.workDays != null)
                _InfoRow(label: '근무 요일', value: snapshot.workDaysText),
              _InfoRow(label: '근무 시간', value: snapshot.workTimeText),
            ] else ...[
              _InfoRow(
                label: '근무 형태',
                value: '단기 (${slots.length}일)',
              ),
              _InfoRow(label: '기본 근무 시간', value: snapshot.workTimeText),
              if (slots.isNotEmpty) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                _SlotsTable(slots: slots),
              ],
            ],
          ]),

          SizedBox(height: ResponsiveHelper.spacing(context, 20)),

          _Section(title: '제3조 (임금)', children: [
            _InfoRow(
                label: snapshot.wageTypeLabel,
                value: snapshot.formattedWage),
            if (snapshot.hourlyWage != null)
              _InfoRow(label: '통상시급', value: snapshot.formattedHourlyWage),
            _InfoRow(label: '지급 방법', value: snapshot.paymentMethod),
            if (snapshot.payScheduleTypeLabel.isNotEmpty)
              _InfoRow(label: '지급 방식', value: snapshot.payScheduleTypeLabel),
            _InfoRow(label: '지급 일정', value: snapshot.payScheduleLabel),
            if (snapshot.taxDeductionType != InsuranceRateModel.typeNone)
              _InfoRow(
                label: '공제 방식',
                value: InsuranceRateModel.typeLabel(snapshot.taxDeductionType),
              ),
          ]),

          // 템플릿 조항 (관리자가 설정한 자유 조항)
          ...articles.map((article) => Padding(
            padding: EdgeInsets.only(
                top: ResponsiveHelper.spacing(context, 20)),
            child: _Section(title: article.title, children: [
              _Paragraph(article.content),
            ]),
          )),

          SizedBox(height: ResponsiveHelper.spacing(context, 32)),

          // 날짜
          Center(
            child: Text(
              _today(),
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(color: AppColors.grey600),
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 24)),

          // 서명란
          Row(
            children: [
              Expanded(
                child: _SignBlock(
                  label: '사업주 (갑)',
                  name: _ownerName,
                  imageUrl: employerSignatureUrl,
                  imageBase64: employerSealBase64,
                  stampLabel: employerSealType == 'signature' ? '(서명)' : '(인감)',
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 16)),
              Expanded(
                child: _SignBlock(
                  label: '근로자 (을)',
                  name: snapshot.workerName,
                  imageUrl: workerSignatureUrl,
                  stampLabel: '(서명)',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _today() {
    return '${contractDate.year}년 ${contractDate.month}월 ${contractDate.day}일';
  }
}

// ─── 내부 서브 위젯 ───────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(fontWeight: FontWeight.bold)),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
          decoration: BoxDecoration(
            color: AppColors.grey50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.grey200),
          ),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 6)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: ResponsiveHelper.spacing(context, 76),
            child: Text(label,
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey500)),
          ),
          Expanded(
            child: Text(value,
                style: ResponsiveHelper.smallStyle(context)
                    .copyWith(fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }
}

class _Paragraph extends StatelessWidget {
  final String text;
  const _Paragraph(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: ResponsiveHelper.smallStyle(context),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(
          vertical: ResponsiveHelper.spacing(context, 8)),
      child: const Divider(height: 1, color: AppColors.grey300),
    );
  }
}

class _SlotsTable extends StatelessWidget {
  final List<ContractSlot> slots;
  const _SlotsTable({required this.slots});

  @override
  Widget build(BuildContext context) {
    return Table(
      border: TableBorder.all(color: AppColors.grey300, width: 0.5),
      columnWidths: const {
        0: FlexColumnWidth(2.5),
        1: FlexColumnWidth(1.8),
        2: FlexColumnWidth(1.8),
        3: FlexColumnWidth(2.2),
      },
      children: [
        // 헤더
        TableRow(
          decoration: BoxDecoration(color: AppColors.grey100),
          children: ['근무일', '시작', '종료', '임금'].map((h) =>
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
              child: Text(h,
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey600)
                    .copyWith(fontWeight: FontWeight.bold)),
            ),
          ).toList(),
        ),
        // 슬롯 행
        ...slots.map((s) => TableRow(
          children: [s.workDate, s.startTime, s.endTime, s.formattedWage]
              .map((v) => Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 5, horizontal: 6),
                    child: Text(v,
                        style: ResponsiveHelper.tinyStyle(context)),
                  ))
              .toList(),
        )),
      ],
    );
  }
}

class _SignBlock extends StatelessWidget {
  final String label;
  final String name;
  /// 서명 시점에 Storage에 저장된 URL — 있으면 base64보다 우선 표시 (불변 보장)
  final String? imageUrl;
  /// 미서명 상태의 미리보기용 base64 — imageUrl이 없을 때만 사용
  final String? imageBase64;
  final String stampLabel;

  const _SignBlock({
    required this.label,
    required this.name,
    this.imageUrl,
    this.imageBase64,
    this.stampLabel = '(서명)',
  });

  @override
  Widget build(BuildContext context) {
    final hasUrl = imageUrl != null && imageUrl!.isNotEmpty;
    final hasBase64 = imageBase64 != null && imageBase64!.isNotEmpty;

    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.grey300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(label,
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey500)),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          SizedBox(
            height: 48,
            child: hasUrl
                // 서명 시점 고정 이미지 (Storage URL, 캐시 적용)
                ? CachedNetworkImage(
                    imageUrl: imageUrl!,
                    fit: BoxFit.contain,
                    placeholder: (_, __) => const SizedBox.shrink(),
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  )
                : hasBase64
                    // 미서명 상태 미리보기 (base64)
                    ? Image.memory(base64Decode(imageBase64!), fit: BoxFit.contain)
                    : const SizedBox.shrink(),
          ),
          const Divider(color: AppColors.grey400),
          Text(name,
              style: ResponsiveHelper.smallStyle(context)
                  .copyWith(fontWeight: FontWeight.w500)),
          Text(stampLabel,
              style: ResponsiveHelper.tinyStyle(context,
                  color: AppColors.grey400)),
        ],
      ),
    );
  }
}
