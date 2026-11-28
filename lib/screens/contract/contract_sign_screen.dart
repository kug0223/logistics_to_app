import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../models/core/contract_template_model.dart';
import '../../models/core/to_model.dart';
import '../../models/core/employment_contract_model.dart';
import '../../models/core/insurance_rate_model.dart';
import '../../providers/user_provider.dart';
import '../../services/contract_service.dart';
import '../../services/business_posting_readiness.dart';
import '../../theme/app_colors.dart';
import '../../utils/attendance_policy_disclosure.dart';
import '../../utils/text_layout.dart';
import '../../widgets/common/attendance_rule_guide_view.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/toast_helper.dart';
import '../../widgets/contract/signature_pad_widget.dart';
import 'contract_pdf_builder.dart';
import '../common/settings_screen.dart';
import '../../utils/dialog_helper.dart';

/// 계약서 확인 + 서명 화면 (사업주 / 근무자 공용)
///
/// [role] : 'employer' 또는 'worker'
class ContractSignScreen extends StatefulWidget {
  final EmploymentContractModel contract;
  final String role; // 'employer' | 'worker'

  /// [E2-SIGNATURE-OUTCOME-UI] 테스트용 선택적 주입. 넘기지 않으면 기존과 같이
  ///   `ContractService()` 를 쓴다 — 기존 호출부는 바뀌지 않는다.
  final ContractService? service;

  const ContractSignScreen({
    super.key,
    required this.contract,
    required this.role,
    this.service,
  });

  /// [UI-4] 지금 열려 있는 계약서 화면 수. 근로자 셸의 `서명이 필요해요` 배너는
  ///   이 화면 위에서도 떠 있어, 보고 있는 그 계약으로 다시 가라고 말하며 읽을
  ///   영역을 가렸다(LOCAL 실측). 배너가 이 값을 보고 스스로 내려간다.
  static final ValueNotifier<int> openCount = ValueNotifier<int>(0);

  @override
  State<ContractSignScreen> createState() => _ContractSignScreenState();
}

class _ContractSignScreenState extends State<ContractSignScreen> {
  late final ContractService _service = widget.service ?? ContractService();
  final _scrollController = ScrollController();

  bool _hasReadAll = false;
  bool _agreed = false;
  bool _isSigning = false;

  /// [E2-EMPLOYER-SIG-LOST-RESPONSE · E2-WORKER-SIG-LOST-RESPONSE] 사업주·근로자 서명 응답을
  ///   못 받았고 커밋도 확인하지 못했다.
  ///   이 화면에서 같은 계약을 바로 다시 보내지 않는다 — 목록에서 상태를 확인하게 한다.
  bool _signOutcomeUnknown = false;
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
    // 빌드·폐기 도중 다른 위젯(배너)을 다시 그리게 하지 않도록 한 박자 뒤에 바꾼다.
    Future.microtask(() => ContractSignScreen.openCount.value++);
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
        _prefetchEmployerSignature(); // [PERF-L41] 읽는 동안 PDF 에 넣을 사업주 서명을 미리 받는다
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
  void didUpdateWidget(covariant ContractSignScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // [CONSENT-CLOSEOUT.30] 같은 State 가 다른 계약을 받으면 앞 계약의 '끝까지 읽음'·'동의'를
    //   넘기지 않는다. 글자 크기·폭이 바뀌는 relayout 은 같은 계약이므로 그대로 둔다.
    if (oldWidget.contract.id != widget.contract.id) {
      _hasReadAll = false;
      _agreed = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _hasReadAll || !_scrollController.hasClients) return;
        if (_scrollController.position.maxScrollExtent <= 0) {
          setState(() => _hasReadAll = true);
        }
      });
    }
  }

  @override
  void dispose() {
    Future.microtask(() => ContractSignScreen.openCount.value--);
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
    // [R8P6-PDF-REMEDIATION] 계약 문서의 영구 URL 을 열지 않는다.
    //   열 때마다 서버가 **지금의** 권한을 확인한 뒤 15분 링크를 낸다.
    //   받은 URL 은 들고 있지 않는다 — 만료되면 다시 받는다.
    if (!widget.contract.hasPdf) return;
    setState(() => _isSharingPdf = true);
    try {
      final url = await _service.fetchContractPdfUrl(widget.contract.id);
      if (!mounted) return;
      final resp = await http.get(Uri.parse(url));
      if (!mounted) return;
      if (resp.statusCode != 200) {
        // 만료·회수된 링크도 여기로 온다 — 다시 시도하면 새 링크를 받는다.
        ToastHelper.showError('PDF를 불러오지 못했습니다. 다시 시도해 주세요.');
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
      // [CONTRACT-DISPATCH-B1] owner 문서를 못 읽는 관리자(공동관리자·SubAdmin)는 늘 여기로 왔다 —
      //   users 문서는 본인만 읽는다. 서버에 있는지 묻고, 있으면 바이트 없이 보낸다(서버가 owner 날인을 찍는다).
      final ready =
          await BusinessPostingReadiness.employerSealReady(widget.contract.businessId);
      if (!mounted) return;
      if (ready == true) {
        await _performSign(null);
        return;
      }
      if (ready == null) {
        ToastHelper.showError('사업주 날인 상태를 확인하지 못했어요. 잠시 후 다시 시도해 주세요.');
        setState(() => _isSigning = false);
        return;
      }
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
    final choice = await DialogHelper.showSheet<bool>(
      context,
      isScrollControlled: true, // 가로 모드에서 콘텐츠 잘림 방지
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
                    // [DU1 후속40 B2-C] 주 행동 실측 48.2 → 기준 52
                    minimumSize: const Size.fromHeight(52),
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

  /// [PERF-L41 · 판정291 §4] PDF 에 넣을 사업주 서명 **바이트** — 근로자가 계약서를 읽는 동안 미리 받아 둔다.
  ///   예전에는 '동의하고 서명'을 누른 뒤에야 링크 발급(callable) + 내려받기를 기다렸다.
  ///   받은 경로·권한 검사는 같다(`fetchContractSignatureBytes`). 아직 못 받았거나 실패했으면 누를 때 예전처럼 받는다 —
  ///   기다리지 않는다(누를 때 새로 받는 것이 예전 동작 그대로다). 서명 시각·PDF 해시·보관은 서버 그대로다.
  Uint8List? _employerSigPrefetched;

  void _prefetchEmployerSignature() {
    if (isEmployer || !widget.contract.hasEmployerSignature) return;
    _service.fetchContractSignatureBytes(widget.contract.id, 'employer').then(
        (b) => _employerSigPrefetched = b,
        onError: (Object e) => debugPrint('⚠️ 사업주 서명 미리 받기 실패(누를 때 다시 받는다): $e'));
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
    // [PERF-L41] 서명 저장은 계약 서명과 **서로 독립**이다(내 서명 보관 vs 이 계약의 서명) — 저장을 기다린 뒤에
    //   서명하던 것을 함께 진행한다. 저장 실패는 예전처럼 안내만 하고 계약 서명은 계속한다.
    Future<void>? saveSignature;
    if (askToSave) {
      final save = await _askSaveSignature();
      if (save && mounted) {
        final userProvider = context.read<UserProvider>();
        final uid = userProvider.currentUser?.uid;
        if (uid != null) {
          final b64 = base64Encode(bytes);
          saveSignature = () async {
            try {
              await _service.saveUserSignature(uid: uid, base64: b64);
            } catch (e) {
              debugPrint('⚠️ 서명 저장 실패: $e');
              ToastHelper.showWarning('서명 저장에 실패했습니다. 계약 서명은 계속 진행합니다.');
              return;
            }
            if (mounted) setState(() => _savedSignatureBase64 = b64);
            try {
              await userProvider.refreshCurrentUser();
            } catch (e) {
              debugPrint('⚠️ 사용자 정보 갱신 실패 (서명은 저장됨): $e');
            }
          }();
        }
      }
    }

    if (mounted) await _performSign(bytes);
    await saveSignature;
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
  /// [bytes] 가 null 이면 사업주 서명을 서버가 owner 등록 날인으로 찍는다(사업주 경로 전용).
  Future<void> _performSign(Uint8List? bytes) async {
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
        // [R8P6-SIG-CUTOVER] 사업주 서명 **바이트**를 먼저 확보한다.
        //
        //   예전에는 영구 토큰 URL 을 빌더에 넘겼고, 그 URL 이 없으면
        //   사업주 서명란이 빈 PDF 가 **조용히** 만들어졌다. 서명란이 빈
        //   계약서가 완료 처리되는 셈이다. 이제는 "서명이 있다"고 아는 계약에서
        //   바이트를 못 받으면 여기서 예외가 나고, 서명이 완료되지 않는다.
        final workerBytes = bytes!; // 근로자 서명은 항상 손서명 바이트가 있다
        Uint8List? employerSigBytes;
        if (widget.contract.hasEmployerSignature) {
          // [PERF-L41] 미리 받아 둔 바이트가 있으면 쓴다 — 없으면(아직·실패) 예전처럼 지금 받는다.
          employerSigBytes = _employerSigPrefetched ??
              await _service.fetchContractSignatureBytes(
                widget.contract.id,
                'employer',
              );
        }
        final pdfBytes = await ContractPdfBuilder.build(
          snapshot: widget.contract.snapshot,
          slots: widget.contract.slots,
          articles: widget.contract.articles,
          contractDate: widget.contract.createdAt,
          employerSignatureBytes: employerSigBytes,
          workerSignatureBytes: workerBytes,
          ownerNameOverride: _resolvedOwnerName,
          isLongTermOverride: _effectiveIsLongTerm,
          employerSealType: _businessSealType,
          // [PERF-L41] 무거운 PDF 만들기를 별도 isolate 에서(실패·시간 초과면 이 isolate 에서 같은 방식으로).
          offMain: true,
        );
        final updated = await _service.saveWorkerSignature(
          contract: widget.contract,
          signatureBytes: workerBytes,
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
      if (e is SignatureOutcomeUnknown && mounted) {
        setState(() => _signOutcomeUnknown = true);
      }
      if (mounted) {
        // [ARCHIVE-CLOSED-TO-PREFLIGHT] 서버 거절(운영 종료 사업장의 계약 등)은 서버 문구를
        //   그대로 보인다. toString() 은 "[firebase_functions/failed-precondition] …" 접두어가 붙는다.
        final msg = e is FirebaseFunctionsException
            ? (e.message ?? '')
            : e.toString().replaceFirst('Exception: ', '');
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

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text(
          '근로계약서',
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
      body: Column(
        children: [
          // 안내 배너
          _buildBanner(theme),

          // 계약서 본문 (스크롤)
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 20)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              ContractTemplateWidget(
                snapshot: snap,
                contractDate: widget.contract.createdAt,
                slots: widget.contract.slots,
                articles: widget.contract.articles,
                // 서명 이미지는 그때의 권한으로 받는다 — 계약과 역할만 넘긴다.
                contractId: widget.contract.id,
                hasEmployerSignature: widget.contract.hasEmployerSignature,
                hasWorkerSignature: widget.contract.hasWorkerSignature,
                employerSealBase64: _businessSealBase64,
                employerSealType: _businessSealType,
                ownerNameOverride: _resolvedOwnerName,
                isLongTermOverride: _effectiveIsLongTerm,
              ),
                  // [CONSENT-CLOSEOUT.30] 긴 동의 문장·체크는 본문을 다 읽은 자리(끝)에 둔다 —
                  //   큰 글자에서 고정 영역이 본문을 가리지 않게.
                  if (_needsMySignature) _buildConsentSection(theme),
                ],
              ),
            ),
          ),

          // 하단 고정 — 한 줄 안내 + 서명 버튼만(동의 체크는 본문 끝)
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

  /// 본문 끝 동의 영역 — 끝까지 읽어야 체크할 수 있다. 자동 체크 없음.
  Widget _buildConsentSection(ThemeData theme) {
    final enabled = _hasReadAll && !_isSigning && !_signOutcomeUnknown;
    return Padding(
      padding: EdgeInsets.only(top: ResponsiveHelper.spacing(context, 24)),
      child: Semantics(
        key: const ValueKey('contract-consent-section'),
        checked: _agreed,
        enabled: enabled,
        child: Material(
          color: _agreed
              ? theme.primaryColor.withValues(alpha: 0.06)
              : AppColors.grey50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
                color: _agreed ? theme.primaryColor : AppColors.borderLight),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? () => setState(() => _agreed = !_agreed) : null,
            child: Padding(
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _agreed
                        ? Icons.check_box_rounded
                        : Icons.check_box_outline_blank_rounded,
                    color: _agreed ? theme.primaryColor : AppColors.grey400,
                    size: ResponsiveHelper.iconSize(context, 24),
                  ),
                  SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                  Expanded(
                    // [DU1 후속40 B2-C] 320·2.0 에서 '확인|하였으며'·'동의합니|다.' 로 낱말이 끊겼다 — 단어 단위 줄바꿈(문구 그대로)
                    child: Text(
                      TextLayout.keepWords('위 근로계약서의 내용을 모두 확인하였으며 동의합니다.'),
                      style: ResponsiveHelper.bodyStyle(context).copyWith(
                        color: _hasReadAll
                            ? AppColors.grey800
                            : AppColors.grey400,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 고정 영역 한 줄 안내. 다 읽은 뒤에는 누르면 본문 끝 동의 영역으로 내려간다
  /// (읽기 전에는 건너뛰기 수단이 되지 않도록 누를 수 없다).
  Widget _buildConsentHint(ThemeData theme) {
    final readAll = _hasReadAll;
    final text = readAll
        ? '본문 끝에서 동의에 체크하면 서명할 수 있어요'
        : '계약서를 끝까지 읽으면 동의할 수 있어요';
    final row = Row(
      children: [
        Icon(readAll ? Icons.arrow_downward_rounded : Icons.menu_book_outlined,
            size: ResponsiveHelper.iconSize(context, 16),
            color: readAll ? theme.primaryColor : AppColors.warningDark), // [DU328 ①] warning(2.1:1) → warningDark
        SizedBox(width: ResponsiveHelper.spacing(context, 6)),
        Expanded(
          child: Text(
            text,
            style: ResponsiveHelper.smallStyle(context,
                color: readAll ? theme.primaryColor : AppColors.warningDark), // [DU328 ①]
          ),
        ),
      ],
    );
    if (!readAll) return row;
    return InkWell(
      onTap: () {
        if (!_scrollController.hasClients) return;
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: row,
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
          // [CONSENT-CLOSEOUT.30] 고정 영역은 '지금 무엇이 남았는지' 한 줄만 — 동의 체크는 본문 끝.
          //   동의 전에는 버튼이 꺼져 있고, 무엇을 해야 켜지는지 여기서 말한다(조건을 숨기지 않는다).
          if (_needsMySignature && !_agreed) ...[
            _buildConsentHint(theme),
            SizedBox(height: ResponsiveHelper.spacing(context, 10)),
          ],

          // 서명 버튼 또는 완료 표시
          if (_needsMySignature)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: (_agreed && !_isSigning && !_signOutcomeUnknown) ? _sign : null,
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
                // [DU1 후속40 B2-C] 320·2.0 에서 '계약 확|정' 으로 낱말이 끊겼다 — 단어 단위 줄바꿈(문구·상태 분기 그대로).
                //   기본 392·1.0 높이 50.8 → 공통 기준 주 버튼 52(minimumSize). 배율이 크면 내용만큼 커진다.
                label: Text(TextLayout.keepWords(_isSigning
                    ? '처리 중...'
                    : _signOutcomeUnknown
                        ? '저장 결과 확인 필요 — 계약서 목록을 확인하세요'
                        : isEmployer
                        ? '인감 날인 → 근무자에게 발송'
                        : '서명 완료 → 계약 확정')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  disabledBackgroundColor: AppColors.grey200,
                  minimumSize: const Size.fromHeight(52),
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
          // _needsMySignature == false: 상단 배너가 상태를 이미 안내한다.
          // 초록 완료 배너 제거 — 상단 "쌍방 서명이 완료된 계약서입니다." 와 중복.
          // completed + PDF 있을 때만 하단에 PDF 공유 버튼 표시.
          //   [R8P6-PDF-REMEDIATION] 판단 근거가 영구 URL 에서 `hasPdf` 로 바뀌었다
          //   (신규는 pdfStoragePath, 레거시는 pdfUrl).
          else if (widget.contract.isCompleted && widget.contract.hasPdf)
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
  /// [R8P6-SIG-CUTOVER] 서명 이미지의 출처 — URL 대신 **계약 id + 존재 여부**.
  ///
  ///   `contractId` 가 null 이면 계약이 없는 화면(템플릿 미리보기)이다 —
  ///   서명 링크를 받으려 하지 않고 인감 base64 미리보기만 그린다.
  final String? contractId;
  final bool hasEmployerSignature;
  final bool hasWorkerSignature;

  /// 미서명 상태의 사업주 인감 미리보기용 base64
  final String? employerSealBase64;
  /// 날인 방식: 'stamp'(도장) | 'signature'(서명)
  final String employerSealType;
  final String? ownerNameOverride;
  /// 렌더 테스트용 — 비우면 `ContractService` 가 CF 를 부른다.
  final ContractSignatureResolver? signatureResolver;
  /// 구 계약서 isLongTerm 오류 보정용 override
  final bool? isLongTermOverride;

  const ContractTemplateWidget({
    super.key,
    required this.snapshot,
    required this.contractDate,
    this.slots = const [],
    this.articles = const [],
    this.contractId,
    this.hasEmployerSignature = false,
    this.hasWorkerSignature = false,
    this.employerSealBase64,
    this.employerSealType = 'stamp',
    this.ownerNameOverride,
    this.isLongTermOverride,
    this.signatureResolver,
  });

  String get _ownerName {
    if (snapshot.ownerName.isNotEmpty) return snapshot.ownerName;
    return ownerNameOverride ?? '';
  }

  bool get _isLongTerm => isLongTermOverride ?? snapshot.isLongTerm;

  @override
  Widget build(BuildContext context) {
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
            child: Text(
              '근 로 계 약 서',
              style: ResponsiveHelper.titleStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                letterSpacing: 4,
              ),
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
            // [R7-PAYROLL-POLICY.4] 임금 계산의 **시간 기준**도 임금 조건이다.
            //   근로자가 이 숫자를 계약서에서 확인할 수 없으면, 지각 1분이
            //   30분 공제가 되는 이유를 알 수 없다.
            //   값은 Application snapshot 에서만 온다 — 없으면 적지 않는다.
            // [R7-PAYROLL-POLICY.4B] 다섯 줄에서 **7개 전부**로. 빠져 있던
            //   조출 단위·늦게 퇴근 인정 범위도 지급액을 바꾼다.
            //   항목·문구는 근로자 수락 화면·PDF 와 같은 곳에서 온다.
            if (snapshot.attendancePolicy case final policy?) ...[
              // [ATTENDANCE-RULE-GUIDE.29-A1] 임금 조항 아래 '근태 인정 기준' — 근무시간 → 출근/퇴근 기준,
              //   기준마다 바로 아래에 이 근무 시각의 사례. 값은 계약 snapshot 그대로다(현재 사업장 기준으로
              //   바꾸지 않는다). 서명 완료 계약의 PDF 는 서명 때 만들어 보관한 파일이라 이 표시가 바꾸지 않는다.
              SizedBox(height: ResponsiveHelper.spacing(context, 14)),
              Text(kAttendanceRuleGuideTitle,
                  style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary)
                      .copyWith(fontWeight: FontWeight.w800)),
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              AttendanceRuleGuideView(
                guide: attendanceRuleGuide(policy,
                    startHHmm: snapshot.startTime, endHHmm: snapshot.endTime),
              ),
            ],
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
                  contractId: contractId,
                  role: 'employer',
                  hasSignature: hasEmployerSignature,
                  imageBase64: employerSealBase64,
                  stampLabel: employerSealType == 'signature' ? '(서명)' : '(인감)',
                  signatureResolver: signatureResolver,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 16)),
              Expanded(
                child: _SignBlock(
                  label: '근로자 (을)',
                  name: snapshot.workerName,
                  contractId: contractId,
                  role: 'worker',
                  hasSignature: hasWorkerSignature,
                  stampLabel: '(서명)',
                  signatureResolver: signatureResolver,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _today() {
    // [UI-4] createdAt 은 instant 다 — KST 달력 날짜로 읽는다. GMT 기기에서 KST 10-29
    //   02:25 에 만든 계약이 `2026년 10월 28일` 로 보였다(LOCAL 실측, 저장값은 정상).
    final d = FormatHelper.toKstDate(contractDate);
    return '${d.year}년 ${d.month}월 ${d.day}일';
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
        // [DU335] 조항 제목 낱말 단위('제1조 (근로계약 당 / 사자)' 해소) — 원문은 낭독용
        Text(TextLayout.keepWords(title),
            semanticsLabel: title,
            style: ResponsiveHelper.bodyStyle(context)
                .copyWith(fontWeight: FontWeight.bold)),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Container(
          width: double.infinity,
          padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 14)),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.grey100),
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
    // [.29-A1] 띄어쓰기 없는 라벨('사업자번호')이 상한보다 길면(392dp·2.0) '사업자번 / 호' 로 강제 줄바꿈됐다.
    //   실제 글자 배율로 재서 상한을 넘으면 라벨을 값 위 한 줄로 올린다(쪼개지 않는다).
    // [DU1 R5-1] 라벨은 읽어야 하는 정보 — grey500(흰 바탕 2.68:1) → textSecondary(5.92:1). 본문·서명·snapshot·PDF 불변
    final labelStyle = ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary);
    final maxLabel = ResponsiveHelper.spacing(context, 124) - ResponsiveHelper.spacing(context, 8);
    final painter = TextPainter(
      text: TextSpan(text: label, style: DefaultTextStyle.of(context).style.merge(labelStyle)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final stacked = painter.width > maxLabel;
    painter.dispose();
    if (stacked) {
      return Padding(
        padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 6)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(TextLayout.keepWords(label), semanticsLabel: label, style: labelStyle),
            Text(TextLayout.keepWords(value), semanticsLabel: value,
                style: ResponsiveHelper.smallStyle(context)
                    .copyWith(fontWeight: FontWeight.w500)),
          ],
        ),
      );
    }
    return Padding(
      padding:
          EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 6)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [DEVICE-GP-INFOROW] 라벨 칸을 **고정폭**으로 두면 칸보다 긴 라벨이
          //   칸 안에서 줄바꿈되어 값과 뒤섞여 읽힌다. 기기(393dp·배율 0.9)에서
          //   `기본 근무 시간` 이 `기본 근무 시` + 값 + `간` 으로 보였다.
          //   짧은 라벨의 **정렬은 그대로** 두되(최소폭), 칸을 넘는 라벨은
          //   한 줄로 늘어나게 한다. 최대폭은 값 칸을 지키는 상한이다.
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: ResponsiveHelper.spacing(context, 76),
              maxWidth: ResponsiveHelper.spacing(context, 124),
            ),
            child: Padding(
              padding:
                  EdgeInsets.only(right: ResponsiveHelper.spacing(context, 8)),
              // [TEXT-LAYOUT-CONSUMER.29] 상한(124)을 넘는 라벨이 320dp·1.3 에서 '기본 근무 …' 로 잘렸다.
              //   자르지 않고 **띄어쓰기에서만** 줄을 바꾼다('기본 근무' / '시간') — 예전처럼 음절 단위로
              //   쪼개져 값과 뒤섞이지(DEVICE-GP-INFOROW) 않는다.
              child: Text(TextLayout.keepWords(label),
                  semanticsLabel: label,
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.textSecondary)),
            ),
          ),
          Expanded(
            child: Text(TextLayout.keepWords(value), semanticsLabel: value,
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
    // [DU335] 조항 본문 낱말 단위 조판(S048 · S019 본문 후속, 소급 5 채택) — 줄바꿈 · 번호 · 원문 그대로,
    //   화면 글자에만 줄바꿈 제어 문자를 둔다. 낭독은 원문이다. PDF(contract_pdf_builder)는 이 위젯을 쓰지 않는다.
    //   한 낱말이 칸보다 길면('기간제및단시간근로자보호법,') Flutter 가 낱말 안에서 강제로 끊으므로 잘리지는 않는다.
    return Text(
      TextLayout.phrases(text),
      semanticsLabel: text,
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

  static const Map<int, double> _flex = {0: 2.5, 1: 1.8, 2: 1.8, 3: 2.2};
  static const double _cellPad = 12; // 좌우 6 + 6

  @override
  Widget build(BuildContext context) {
    // [TEXT-LAYOUT-CONSUMER.29] 기기 320dp·글자 1.3 에서 칸이 좁아 '2026-1 / 0-29', '17:3 / 5',
    //   '10,32 / 0원' 으로 갈렸다 — 날짜·시각·금액은 쪼개지 않는다. 각 칸의 가장 긴 값을 **실제 글자 배율로
    //   재서** 모든 칸에 들어가면 표, 하나라도 모자라면 근무일마다 한 덩어리(날짜 / 시간 · 임금).
    //   상수 폭으로 정하면 글꼴마다(기기·시험) 판단이 갈린다.
    return LayoutBuilder(builder: (context, c) {
      if (!c.hasBoundedWidth || _tableFits(context, c.maxWidth)) return _table(context);
      return _stacked(context);
    });
  }

  bool _tableFits(BuildContext context, double width) {
    final style = DefaultTextStyle.of(context).style.merge(ResponsiveHelper.tinyStyle(context));
    final header = DefaultTextStyle.of(context).style.merge(ResponsiveHelper.tinyStyle(context)
        .copyWith(fontWeight: FontWeight.bold));
    final scaler = MediaQuery.textScalerOf(context);
    double w(String t, TextStyle st) {
      final p = TextPainter(
          text: TextSpan(text: t, style: st), textDirection: TextDirection.ltr, textScaler: scaler, maxLines: 1)
        ..layout();
      final v = p.width;
      p.dispose();
      return v;
    }
    const heads = ['근무일', '시작', '종료', '임금'];
    final total = _flex.values.fold<double>(0, (a, b) => a + b);
    for (var i = 0; i < 4; i++) {
      var need = w(heads[i], header);
      for (final sl in slots) {
        final v = [sl.workDate, sl.startTime, sl.endTime, sl.formattedWage][i];
        need = need < w(v, style) ? w(v, style) : need;
      }
      if (width * _flex[i]! / total < need + _cellPad + 1) return false;
    }
    return true;
  }

  Widget _stacked(BuildContext context) {
    final value = ResponsiveHelper.tinyStyle(context);
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.grey300, width: 0.5)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < slots.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              decoration: BoxDecoration(
                border: i == 0
                    ? null
                    : const Border(top: BorderSide(color: AppColors.grey300, width: 0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(slots[i].workDate, softWrap: false,
                      style: value.copyWith(fontWeight: FontWeight.w600)),
                  Wrap(spacing: 10, children: [
                    Text(TextLayout.range(slots[i].startTime, slots[i].endTime),
                        semanticsLabel: '${slots[i].startTime} ~ ${slots[i].endTime}',
                        style: value),
                    Text(slots[i].formattedWage, softWrap: false, style: value),
                  ]),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _table(BuildContext context) {
    return Table(
      border: TableBorder.all(color: AppColors.grey300, width: 0.5),
      columnWidths: {
        for (final e in _flex.entries) e.key: FlexColumnWidth(e.value),
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

  /// [R8P6-SIG-CUTOVER] 서명 이미지의 출처 — URL 이 아니라 **계약과 역할**이다.
  ///
  ///   예전에는 계약 문서의 영구 토큰 URL 을 그대로 받아 그렸다. 그 URL 은
  ///   만료도 로그인도 없어서 한 번 본 사람이 계속 열 수 있었다. 이제는
  ///   `계약 id + 역할`만 받고, 링크는 열 때마다 서버가 권한을 보고 낸다.
  ///
  ///   `contractId` 가 없으면 계약이 아직 없는 화면(템플릿 미리보기)이다 —
  ///   그때는 인감 base64 미리보기만 그린다.
  final String? contractId;
  final String? role;

  /// 서명 이미지가 존재하는가 — 없으면 링크를 받으려 시도하지 않는다.
  final bool hasSignature;

  /// 미서명 상태의 미리보기용 base64 — 서명 이미지가 없을 때만 사용
  final String? imageBase64;
  final String stampLabel;
  final ContractSignatureResolver? signatureResolver;

  const _SignBlock({
    required this.label,
    required this.name,
    this.contractId,
    this.role,
    this.hasSignature = false,
    this.imageBase64,
    this.stampLabel = '(서명)',
    this.signatureResolver,
  });

  @override
  Widget build(BuildContext context) {
    final hasUrl = hasSignature &&
        contractId != null && contractId!.isNotEmpty && role != null;
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
                  color: AppColors.textSecondary)), // [DU328 ②] grey500(2.68) → textSecondary — 읽어야 하는 서명란 라벨
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          SizedBox(
            height: 48,
            child: hasUrl
                // 서명 시점 고정 이미지 — 링크는 그때의 권한으로 받는다
                ? _ContractSignatureImage(
                    contractId: contractId!,
                    role: role!,
                    resolver: signatureResolver,
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
                  color: AppColors.textTertiary)), // [DU328 ②] grey400(1.88) → textTertiary
        ],
      ),
    );
  }
}

/// [R8P6-SIG-CUTOVER] 서명 이미지 1칸 — 링크를 **그때의 권한으로** 받아 그린다.
///
///   ## 캐시 키가 왜 URL 이 아닌가
///
///   받은 링크는 15분 뒤 만료되므로 매번 다른 문자열이다. `CachedNetworkImage` 는
///   `cacheKey` 를 주지 않으면 `imageUrl` 을 키로 쓰기 때문에, 그냥 두면 **같은
///   서명 이미지를 열 때마다 다시 내려받는다.**
///
///   그래서 서버가 함께 주는 `signatureVersion`(서명이 저장된 attempt)을 키에 쓴다.
///   `계약 id + 역할`만으로 키를 만들면 안 된다 — 같은 계약을 **재서명**하면 새
///   attempt 경로에 새 파일이 저장되므로, 옛 키가 옛 이미지를 계속 돌려준다.
///
///   ## 실패를 숨기지 않는다
///
///   예전에는 로드 실패가 `SizedBox.shrink()` 였다 — 서명란이 조용히 비었고,
///   근로자는 사업주가 서명을 안 한 것인지 화면이 못 가져온 것인지 알 수 없었다.
///   지금은 못 가져왔다고 말하고, 한 번 더 시도할 수 있게 한다.
class _ContractSignatureImage extends StatefulWidget {
  final String contractId;
  final String role;
  final ContractSignatureResolver? resolver;

  const _ContractSignatureImage({
    required this.contractId,
    required this.role,
    this.resolver,
  });

  @override
  State<_ContractSignatureImage> createState() =>
      _ContractSignatureImageState();
}

class _ContractSignatureImageState extends State<_ContractSignatureImage> {
  ContractSignatureLink? _link;
  bool _loading = true;
  bool _failed = false;

  /// 만료된 링크로 이미지가 깨졌을 때 **한 번만** 다시 받는다.
  bool _retriedAfterExpiry = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final resolve = widget.resolver ??
          (String c, String r) => ContractService().fetchContractSignature(c, r);
      final link = await resolve(widget.contractId, widget.role);
      if (!mounted) return;
      setState(() {
        _link = link;
        _loading = false;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('서명 이미지 링크 발급 실패: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(
        child: SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final link = _link;
    if (_failed || link == null) return _retry(context);

    return CachedNetworkImage(
      imageUrl: link.url,
      // 링크는 15분마다 바뀌지만 **이미지는 그대로**다 — 판으로 캐시한다.
      cacheKey: 'contract_sig_${widget.contractId}_'
          '${widget.role}_${link.version}',
      fit: BoxFit.contain,
      placeholder: (_, __) => const SizedBox.shrink(),
      errorWidget: (_, __, ___) {
        // 캐시가 비었는데 링크가 이미 만료된 경우다 — 한 번 다시 받는다.
        if (!_retriedAfterExpiry) {
          _retriedAfterExpiry = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _resolve();
          });
          return const SizedBox.shrink();
        }
        return _retry(context);
      },
    );
  }

  Widget _retry(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: _resolve,
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        child: Text(
          '서명 불러오기 실패 · 다시 시도',
          textAlign: TextAlign.center,
          style: ResponsiveHelper.tinyStyle(context, color: AppColors.error),
        ),
      ),
    );
  }
}
