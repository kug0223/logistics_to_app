import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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

  // 근무자 사전 등록 서명 (base64)
  String? _savedSignatureBase64;
  // 사업주 인감 (base64)
  String? _businessSealBase64;
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
        // 근무자: 사전 등록 서명 로드 + TO 타입 확인
        final user = context.read<UserProvider>().currentUser;
        if (user?.signatureBase64 != null) {
          if (mounted) setState(() => _savedSignatureBase64 = user!.signatureBase64);
        }
        await _checkTOType();
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
    try {
      final doc = await FirebaseFirestore.instance
          .collection('businesses')
          .doc(widget.contract.businessId)
          .get();
      final data = doc.data();
      if (!mounted || data == null) return;
      final sealBase64 = data['sealBase64'] as String?;
      String? ownerName;
      // snapshot에 ownerName이 없으면 business 문서에서 조회, 그래도 없으면 ownerId로 users 조회
      if (widget.contract.snapshot.ownerName.isEmpty) {
        ownerName = data['ownerName'] as String?;
        if (ownerName == null || ownerName.trim().isEmpty) {
          final ownerId = data['ownerId'] as String?;
          if (ownerId != null) {
            try {
              final userDoc = await FirebaseFirestore.instance
                  .collection('users')
                  .doc(ownerId)
                  .get();
              final ud = userDoc.data();
              // 사업자등록증 대표자명(ceoName) 우선, 없으면 계정 이름
              final ceo = ud?['ceoName'] as String?;
              ownerName = (ceo?.trim().isNotEmpty == true)
                  ? ceo
                  : ud?['name'] as String?;
            } catch (e) {
              debugPrint('⚠️ 사업장 대표자 이름 조회 실패: $e');
            }
          }
        }
      }
      if (!mounted) return;
      setState(() {
        if (sealBase64 != null && sealBase64.isNotEmpty) {
          _businessSealBase64 = sealBase64;
        }
        if (ownerName != null && ownerName.trim().isNotEmpty) {
          _resolvedOwnerName = ownerName.trim();
        }
      });

      await _checkTOType();
    } catch (e) {
      debugPrint('인감/대표자 로드 실패: $e');
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

  // ── 서명 진입점 ──────────────────────────────────────────────

  Future<void> _sign() async {
    if (!_agreed) {
      ToastHelper.showWarning('내용 확인 동의가 필요합니다');
      return;
    }
    if (isEmployer) {
      await _signAsEmployer();
    } else {
      if (_hasSavedSignature) {
        _showSignatureOptions();
      } else {
        await _signWithPad(askToSave: true);
      }
    }
  }

  // ── 사업주: 인감 날인 ─────────────────────────────────────────

  Future<void> _signAsEmployer() async {
    if (!_hasSeal) {
      // 인감 미등록 안내
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('인감 미등록'),
          content: const Text('사업장 인감이 등록되어 있지 않습니다.\n설정 > 사업장 설정에서 인감을 먼저 등록해주세요.'),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('확인'),
            ),
          ],
        ),
      );
      return;
    }
    // 인감 등록됨 → 바로 날인
    final bytes = base64Decode(_businessSealBase64!);
    await _performSign(bytes);
  }

  // 저장 서명 있을 때 선택 바텀시트 (근무자 전용)
  void _showSignatureOptions() {
    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true, // 가로 모드에서 콘텐츠 잘림 방지
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
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
                  onPressed: () {
                    Navigator.pop(ctx);
                    _signWithSaved();
                  },
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
                  onPressed: () {
                    Navigator.pop(ctx);
                    _signWithPad(askToSave: true);
                  },
                  child: Text('새 서명 그리기',
                      style: ResponsiveHelper.bodyStyle(ctx,
                          color: AppColors.grey600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
    if (bytes == null || !mounted) return;

    // 서명 저장 여부 묻기
    if (askToSave) {
      final save = await _askSaveSignature();
      if (save && mounted) {
        final userProvider = context.read<UserProvider>();
        final uid = userProvider.currentUser?.uid;
        if (uid != null) {
          final b64 = base64Encode(bytes);
          try {
            await _service.saveUserSignature(uid: uid, base64: b64);
            if (!mounted) return;
            await userProvider.refreshCurrentUser();
            if (mounted) setState(() => _savedSignatureBase64 = b64);
          } catch (e) {
            debugPrint('⚠️ 서명 저장 실패: $e');
            if (mounted) ToastHelper.showWarning('서명 저장에 실패했습니다. 계약 서명은 계속 진행합니다.');
          }
        }
      }
    }

    if (mounted) await _performSign(bytes);
  }

  Future<bool> _askSaveSignature() async {
    if (!mounted) return false;
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Text('서명 저장'),
            content: const Text('이 서명을 저장해두면 다음 계약서 서명 시 바로 사용할 수 있습니다.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('저장 안 함'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('저장'),
              ),
            ],
          ),
        ) ??
        false;
  }

  // 실제 서명 저장 + 화면 완료 처리
  Future<void> _performSign(Uint8List bytes) async {
    if (!mounted) return;
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
        );
        final updated = await _service.saveWorkerSignature(
          contract: widget.contract,
          signatureBytes: bytes,
          pdfBytes: pdfBytes,
        );
        if (mounted) {
          ToastHelper.showSuccess('계약서 서명이 완료되었습니다!');
          Navigator.pop(context, updated);
        }
      }
    } catch (e) {
      if (mounted) ToastHelper.showError('서명 저장에 실패했습니다');
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
                employerSealBase64: _businessSealBase64,
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
              isEmployer
                  ? '내용을 검토 후 서명하면 근무자에게 발송됩니다.'
                  : '내용을 끝까지 확인하신 후 서명해주세요.',
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
          // 동의 체크박스
          GestureDetector(
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
          if (!_hasReadAll)
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

          // 서명 버튼
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  (_agreed && !_isSigning) ? _sign : null,
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
  final String? employerSealBase64;
  final String? ownerNameOverride;
  /// 구 계약서 isLongTerm 오류 보정용 override
  final bool? isLongTermOverride;

  const ContractTemplateWidget({
    super.key,
    required this.snapshot,
    required this.contractDate,
    this.slots = const [],
    this.articles = const [],
    this.employerSealBase64,
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
                  imageBase64: employerSealBase64,
                  stampLabel: '(인감)',
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 16)),
              Expanded(
                child: _SignBlock(
                  label: '근로자 (을)',
                  name: snapshot.workerName,
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
  final String? imageBase64;
  final String stampLabel;

  const _SignBlock({
    required this.label,
    required this.name,
    this.imageBase64,
    this.stampLabel = '(서명)',
  });

  @override
  Widget build(BuildContext context) {
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
          if (imageBase64 != null && imageBase64!.isNotEmpty)
            SizedBox(
              height: 48,
              child: Image.memory(
                base64Decode(imageBase64!),
                fit: BoxFit.contain,
              ),
            )
          else
            SizedBox(height: 48),
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
