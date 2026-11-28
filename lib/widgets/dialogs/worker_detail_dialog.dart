// lib/widgets/dialogs/worker_detail_dialog.dart
// 공통 근무자/지원자 상세 다이얼로그
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/core/application_model.dart';
import '../../models/core/attendance_model.dart';
import '../../models/core/user_model.dart';
import '../../models/core/user_region.dart';
import '../../models/core/id_card_access_request_model.dart';
import '../../models/ui/admin_to_list_ui_models.dart';
import '../../models/core/employment_contract_model.dart';
import '../../models/core/work_detail_data.dart';
import '../../screens/contract/contract_sign_screen.dart';
import '../../services/contract_service.dart';
import 'contract_template_selector_dialog.dart';
import '../../services/firestore_service.dart';
import '../../providers/user_provider.dart';
import '../../utils/toast_helper.dart';
import '../../utils/work_detail_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../utils/format_helper.dart';
import '../../utils/dialog_helper.dart';
import '../../theme/app_colors.dart';
import '../../screens/business_admin/dialogs/fixed_worker_management_dialog.dart';
import '../../utils/image_helper.dart';
import 'monthly_review_dialog.dart';
import 'styled_dialog.dart';
import '../../models/core/monthly_review_model.dart';
import '../../models/core/review_request_model.dart';
import '../../services/monthly_review_service.dart';
import '../../widgets/common/loading_widget.dart';
import '../../services/applicant_document_review_service.dart';
import '../../services/tax_identity_review_service.dart';
import '../../services/worker_payroll_account_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../utils/server_reject_codes.dart';

/// [UI-3] 상세 머리줄의 성별·나이 조각. 저장 계약('남성'·'여성')이 아닌 성별 값은
///   추정하지 않고 뺀다. 나이는 생년월일로 계산된 1세 이상만 쓴다(판정 정책은 그대로).
@visibleForTesting
List<String> workerProfileFacts(UserModel user) {
  final g = user.gender;
  final age = user.age;
  return [
    if (g == '남성' || g == '여성') g!,
    if (age != null && age > 0) '$age세',
  ];
}

/// 공통 근무자/지원자 상세 다이얼로그
/// 
/// [isConfirmed] - 확정자 여부 (true: 확정명단에서 호출, false: 지원자 관리에서 호출)
/// [application] - 지원서 정보 (대기중일 때 승인/거절용)
/// [showApprovalButtons] - 승인/거절 버튼 표시 여부
class WorkerDetailDialog extends StatefulWidget {
  final UserModel user;
  final ApplicationModel? application;
  final TOItem? toItem;
  final String? businessId;
  final bool isConfirmed;
  final bool showApprovalButtons;
  final VoidCallback? onStatusChanged;
  final String? attendanceStatus;  // ✅ 추가: 출퇴근/급여 상태

  const WorkerDetailDialog({
    super.key,
    required this.user,
    this.application,
    this.toItem,
    this.businessId,
    this.isConfirmed = false,
    this.showApprovalButtons = false,
    this.onStatusChanged,
    this.attendanceStatus,  // ✅ 추가
  });

  /// 다이얼로그 표시 헬퍼
  static Future<bool?> show({
    required BuildContext context,
    required UserModel user,
    ApplicationModel? application,
    TOItem? toItem,
    String? businessId,
    bool isConfirmed = false,
    bool showApprovalButtons = false,
    VoidCallback? onStatusChanged,
    String? attendanceStatus,  // ✅ 추가
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => WorkerDetailDialog(
        user: user,
        application: application,
        toItem: toItem,
        businessId: businessId,
        isConfirmed: isConfirmed,
        showApprovalButtons: showApprovalButtons,
        onStatusChanged: onStatusChanged,
        attendanceStatus: attendanceStatus,  // ✅ 추가
      ),
    );
  }

  @override
  State<WorkerDetailDialog> createState() => _WorkerDetailDialogState();
}

class _WorkerDetailDialogState extends State<WorkerDetailDialog> {
  final FirestoreService _firestoreService = FirestoreService();
  // [ADMIN-APPROVAL-PERMISSION] 두 뜻을 나눈다.
  //   _auxLoading — 근무 이력·리뷰·계약 등 **부가 조회** 중(확정 조건이 아니다)
  //   _isLoading  — 승인·거절·계약·취소 **처리 중**(이중 탭 방지)
  //   예전에는 하나였다 — 그래서 부가 조회가 느리면 승인이 조용히 막혔다.
  bool _auxLoading = true;
  bool _isLoading = false;
  bool _hasChanges = false;  // ⭐ 변경사항 추적 플래그 추가
  // [PII-B4-R1] 주민번호 표시 토글 제거 — generic 화면에서 전체값을
  //   보여주지 않는다. 세무 대조는 전용 확인 시트에서 한다.
  
  // 추가 데이터
  Map<String, dynamic>? _businessHistory;
  // [R1.2] 추가 데이터 로드 실패 — '이력 없음'과 구분한다.
  //   Future.wait가 하나라도 throw하면 _businessHistory/_recentReviews가 초기값으로
  //   남는데, 그걸 그대로 그리면 조회 실패가 '근무한 적 없음'으로 둔갑한다.
  bool _loadFailed = false;
  String? _workTime;  // 🔥 근무 시간 (장기용)
  List<MonthlyReviewModel> _recentReviews = [];
  IdCardAccessRequestModel? _idCardAccess;
  // 다이얼로그가 열린 상태에서 신분증 열람 권한이 만료/철회되어도 UI에 반영되지 않는 문제.
  // 60초마다 Firestore 재조회로 만료(시간 경과)·철회(상태 변경) 모두 감지한다.
  Timer? _accessRefreshTimer;
  // [PII-B4-R1] 신분증 Signed URL 캐시 제거 — 다이얼로그가 원본을 들고
  //   있지 않는다. 확인 시트가 열릴 때만 발급받아 그 안에서만 쓴다.
  // 세무 identity 확인 상태 (사업장 × 근로자 × 현재 값)
  TaxIdentityReview? _taxReview;
  bool _taxReviewLoading = false;
  // [V3 BANKBOOK-SECURE-ACCESS] 통장사본 Signed URL 상태 (1시간 만료, 매 열람 시 재발급)
  bool _bankbookLoading = false;
  // [CONSENT-R4b · C-R4-4] '급여 정보' 현재 계좌 — 목적별 reader 결과(null = 아직 안 읽음).
  //   목적 미지정 batch 의 widget.user 계좌 필드는 더 이상 쓰지 않는다(H11 뒤 비어 있다).
  WorkerPayrollAccountResult? _payrollAccount;
  bool _payrollAccountLoading = false;
  // [R1.2] 지원자 서류 검토 상태 — 서버가 계산한 값을 그대로 담는다.
  ApplicantDocumentReview? _docReview;
  bool _docReviewLoading = false;
  // [ADMIN-DOC-REVIEW-UX] 조회 실패(모름) — 아직 안 읽은 것과 구분한다.
  bool _docReviewFailed = false;

  /// [impl_27b · L48 같은 꼴] 서류 검토 상태 읽기 차례 — 늦게 끝난 옛 판정이 새 판정을 덮지 않게(승인 열림의 근거다).
  int _docReviewGen = 0;

  // [ADMIN-APPROVAL-PERMISSION] 입력은 확정 권한·서류 조회·신분 확인뿐이다.
  //   부가 조회(_auxLoading)는 확정 조건이 아니라 넣지 않는다.
  ApprovalGate _approvalGateWith(PermissionCheck permission) => approvalGateOf(
      loading: _docReviewLoading,
      failed: _docReviewFailed,
      review: _docReview,
      permission: permission);

  /// 확정 권한(서버 callableConfirmApplication 과 같은 규칙: 소유자·관리자 허용,
  ///   서브관리자는 canManageTo). 네 상태 — 모름·오류를 허용으로 접지 않는다.
  PermissionCheck _confirmPermission({bool listen = false}) {
    final bizId = widget.application?.businessId ?? widget.businessId;
    if (bizId == null || bizId.isEmpty) return PermissionCheck.unknown;
    return Provider.of<UserProvider>(context, listen: listen)
        .checkForBusiness(bizId, (p) => p.canManageTo);
  }

  ApprovalGate get _approvalGate => _approvalGateWith(_confirmPermission());

  /// [impl_58] 리뷰 작성·확인 권한 — rules monthly_reviews(ADMIN_TO_USER create · get)와 같은 축:
  ///   소유자·관리자 허용, 서브관리자는 canManageWorkers. 네 상태 — 모름·오류를 허용으로 접지 않는다.
  PermissionCheck _reviewPermission({bool listen = false}) {
    final bizId = widget.businessId;
    if (bizId == null || bizId.isEmpty) return PermissionCheck.unknown;
    return Provider.of<UserProvider>(context, listen: listen)
        .checkForBusiness(bizId, (p) => p.canManageWorkers);
  }

  static const String _noReviewPermissionText = '리뷰는 인력 관리 권한이 있어야 작성·확인할 수 있어요';
  bool? _hasAttendance;  // 출퇴근 기록 여부 (null=로딩중, true=있음, false=없음)
  bool? _hasWrittenReview;     // 리뷰 작성 여부 (null=미확인)
  EmploymentContractModel? _contract;

  @override
  void initState() {
    super.initState();
    // addPostFrameCallback으로 첫 프레임 이후 로드
    // Firestore 캐시 히트 시 _loadAdditionalData()가 첫 프레임 전에 완료되어
    // _isLoading=false 상태로 빈 프로필이 1~2프레임 노출되는 플래시 방지
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadAdditionalData();
    });
  }

  Future<void> _loadAdditionalData() async {
    // [INVITE-PREACCEPT] 서류 검토 상태는 **다른 부가 정보와 무관하게** 먼저
    //   시작한다. 예전에는 아래 Future.wait 가 끝난 뒤에만 불렀다 — 근무 이력
    //   같은 무관한 조회 하나가 실패하면 서류 검토 영역이 아예 로드되지 않아,
    //   관리자가 초대받은 사람의 서류에 닿을 수 없었다. 판정은 서버가 한다.
    if (!widget.isConfirmed) {
      unawaited(_loadApplicantDocumentReview());
    }
    // [r4c · PP-R4B-ACCOUNT-READ] 상세를 여는 것과 현재 계좌를 요청하는 것을 나눈다 —
    //   계좌는 '급여계좌 보기'를 눌렀을 때만 목적별 reader 로 요청한다(자동 조회 0).

    try {
      final userProvider = context.read<UserProvider>();
      final currentUserId = userProvider.currentUser?.uid ?? '';
      final businessId = widget.businessId ?? widget.toItem?.to.businessId;
      final app = widget.application;

      final results = await Future.wait([
        // 0: 우리 사업장 이력
        businessId != null
            ? _firestoreService.getBusinessWorkHistory(
                businessId: businessId,
                userId: widget.user.uid,
                // [R1.2.1] 검토 단계 조회는 purpose-scoped — 서버가 canManageTo를 재검증한다.
                // [HISTORY-CLOSEOUT.30] 확정자 화면은 purpose 없이 불러 서버(R7-P1-2.3 목적 필수)가
                //   invalid-argument 로 거절했다 → '이력 없음'으로 보였다. 확정자를 다루는 일은 서버 허용
                //   목록의 workerOperation(canManageWorkers)이다. 권한은 서버가 그대로 판정한다.
                purpose: widget.isConfirmed
                    ? FirestoreService.purposeWorkerOperation
                    : FirestoreService.purposeApplicantReview)
            : Future.value(null),

        // 1: 최근 리뷰 (monthly_reviews 컬렉션) — CF 경유 (callableGetReviewsForUser)
        MonthlyReviewService().getPublishedReviewsForUser(targetUserId: widget.user.uid, limit: 5),

        // 2: 신분증 열람 권한 (확정자만)
        widget.isConfirmed
            ? _firestoreService.checkIdCardAccess(
                requesterId: currentUserId, targetUserId: widget.user.uid)
            : Future.value(null),

        // 3: 출퇴근 기록 여부 (확정자 전체 — 장기/단기 공통)
        //    장기: 고정근무 관리 버튼 전환 조건에 사용
        //    단기: 확정취소 버튼 비활성화 조건에 사용
        (app != null && widget.isConfirmed)
            ? _firestoreService.hasAttendanceRecord(app.id, businessId: app.businessId)
            : Future.value(false),

        // 4: 근무 시간 (toItem 없을 때)
        (app != null && widget.toItem == null)
            ? _fetchWorkTime(app)
            : Future.value(null),

        // 5: 리뷰 작성 여부 (확정자 + businessId 있을 때)
        //    [impl_58] 권한 없는 서브관리자는 rules 가 읽기를 막아 '미작성'으로 보였다 — 확인된 거부면 읽지 않는다.
        (widget.isConfirmed && app != null && widget.businessId != null &&
                _reviewPermission() != PermissionCheck.denied)
            ? _checkReviewWritten(app)
            : Future.value(null),

        // 6: 계약서 (확정자 + application 있을 때) — 관리자 컨텍스트이므로 businessId 전달
        (widget.isConfirmed && app != null)
            ? ContractService().getByApplication(app.id, businessId: app.businessId)
            : Future.value(null),

        // 7: [PII-B4-R1] 신분증 Signed URL 선제 발급 제거.
        //    다이얼로그를 여는 것은 원본을 볼 이유가 아니다.
        Future<String?>.value(null),
      ]);

      // [R1.2] 확정 전 지원자의 서류 검토 로드는 위(함수 첫머리)로 옮겼다.

      _businessHistory = results[0] as Map<String, dynamic>?;
      _recentReviews = (results[1] as List).whereType<MonthlyReviewModel>().toList();
      _idCardAccess = results[2] as IdCardAccessRequestModel?;
      _hasAttendance = results[3] as bool?;
      _workTime = results[4] as String?;
      _hasWrittenReview = results[5] as bool?;
      _contract = results[6] as EmploymentContractModel?;

      // [M-10 수정 2026-07-17] Future.wait 완료 후 mounted 체크
      //   dispose 중 Future.wait가 완료되면 타이머가 생성되어 _WorkerDetailDialogState GC 불가 → 메모리 누수
      if (!mounted) return;
      if (_idCardAccess?.isValidAccess == true) _startAccessRefreshTimer();
      // [PII-B4-R1 §22] 다이얼로그를 여는 것만으로 원본을 요청하지 않는다.
      //   확인 상태만 읽는다 — 이미지는 관리자가 누를 때 발급된다.
      if (widget.isConfirmed) unawaited(_loadTaxIdentityReview());

      if (mounted) setState(() => _auxLoading = false);
    } catch (e) {
      debugPrint('❌ 추가 데이터 로드 실패: $e');
      if (mounted) {
        setState(() {
          _auxLoading = false;
          _loadFailed = true;
        });
        ToastHelper.showError('데이터를 불러오는데 실패했습니다.');
      }
    }
  }

  // ── [R1.2] 지원자 서류 검토 핸들러 ──────────────────────────────────────

  Future<void> _loadApplicantDocumentReview() async {
    final app = widget.application;
    final bizId = app?.businessId ?? widget.businessId;
    if (app == null || bizId == null || bizId.isEmpty) {
      // 읽을 수 없다 — 승인 가능 여부를 모른다.
      if (mounted) setState(() => _docReviewFailed = true);
      return;
    }
    final gen = ++_docReviewGen;
    if (mounted) {
      setState(() {
        _docReviewLoading = true;
        _docReviewFailed = false;
      });
    }
    try {
      final r = await ApplicantDocumentReviewService.instance
          .load(applicationId: app.id, businessId: bizId);
      if (!mounted || gen != _docReviewGen) return;
      setState(() {
        _docReview = r;
        _docReviewLoading = false;
      });
    } catch (e) {
      debugPrint('[R1.2] 서류 검토 상태 로드 실패: $e');
      if (!mounted || gen != _docReviewGen) return;
      // 실패를 '서류 없음'으로 바꾸지 않는다 — null로 두고 화면이 그렇게 말한다.
      // [ADMIN-DOC-REVIEW-UX] 이전 성공값도 버린다 — 낡은 판정으로 승인을 열지 않는다.
      setState(() {
        _docReview = null;
        _docReviewLoading = false;
        _docReviewFailed = true;
      });
    }
  }

  Future<void> _viewApplicantDocument({required bool isId}) async {
    final app = widget.application;
    final bizId = app?.businessId ?? widget.businessId;
    final r = _docReview;
    if (app == null || bizId == null || r == null) return;
    final url = await ApplicantDocumentReviewService.instance.documentUrl(
      applicationId: app.id,
      businessId: bizId,
      targetUid: r.workerUid,
      documentType: isId ? 'ID' : 'BANKBOOK',
    );
    if (url == null || !mounted) return;
    await ImageHelper.showFullScreenViewer(
      context,
      imageUrl: url,
      title: isId ? '신분증' : '통장사본',
      // [DOC-S1A] 신분증·통장사본 원본은 관리자 기기 disk 에 남기지 않는다.
      //   Signed URL 은 1시간이면 만료되는데 CachedNetworkImage 가 이미지를
      //   영구 캐시에 써 두면 만료 뒤에도 파일이 남는다. _viewBankbook 과
      //   세무 대조 시트는 이미 같은 계약을 지키고 있었다.
      noCache: true,
    );
  }

  Future<void> _reviewApplicantDocument(
      {required bool isId, required bool ok}) async {
    final app = widget.application;
    final bizId = app?.businessId ?? widget.businessId;
    final r = _docReview;
    if (app == null || bizId == null || r == null) return;
    final confirmed = await DialogHelper.showConfirm(
      context,
      title: isId ? '신분증 확인 완료' : '계좌·통장 확인 완료',
      message: isId
          ? '등록된 신분증을 확인했습니다.\n'
              '이것은 서류 확인 기록이며 정부기관 진위 확인이 아닙니다.'
          : '등록된 급여계좌와 통장사본을 확인했습니다.\n'
              '확인한 계좌가 급여 지급에 그대로 사용됩니다.',
      confirmText: '확인 완료',
      cancelText: '취소',
    );
    if (confirmed != true || !mounted) return;
    final done = await ApplicantDocumentReviewService.instance.review(
      applicationId: app.id,
      businessId: bizId,
      targetUid: r.workerUid,
      documentType: isId ? 'ID' : 'BANKBOOK',
      decision: 'REVIEWED_OK',
      expectedVersion: isId ? r.idVersion : r.bankbookVersion,
      expectedAccountVersion: isId ? null : r.accountVersion,
    );
    if (!mounted) return;
    if (done) ToastHelper.showSuccess('확인 완료로 기록했습니다.');
    await _loadApplicantDocumentReview();
  }

  Future<void> _requestApplicantCorrection({required bool isId}) async {
    final app = widget.application;
    final bizId = app?.businessId ?? widget.businessId;
    final r = _docReview;
    if (app == null || bizId == null || r == null) return;
    const reasons = <String, String>{
      'BLURRY': '이미지가 흐려요',
      'UNREADABLE': '정보를 확인할 수 없어요',
      'MISMATCH': '등록정보와 달라요',
      'WRONG_DOCUMENT': '다른 서류가 등록되어 있어요',
      'OTHER': '기타',
    };
    // [UI-3] 320dp·글자 1.3 에서 시트가 81px 넘쳐 마지막 사유(`다른 서류…`·`기타`)가
    //   잘렸다(기기 실측). 높이를 내용에 맞춰 키우고 넘치면 스크롤한다. 사유를 누르면
    //   바로 요청이 가므로 맨 아래에 `취소` 를 둔다.
    final picked = await DialogHelper.showSheet<String>(
      context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        top: false,
        child: SingleChildScrollView(
         child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
              child: Text(
                isId ? '신분증 재등록 요청' : '통장사본 재등록 요청',
                style: ResponsiveHelper.subtitleStyle(ctx)
                    .copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '지원은 그대로 유지됩니다. 근로자에게 다시 등록해달라고 알립니다.',
                style: ResponsiveHelper.smallStyle(ctx, color: AppColors.grey600),
              ),
            ),
            ...reasons.entries.map((e) => ListTile(
                  title: Text(e.value, style: ResponsiveHelper.bodyStyle(ctx)),
                  onTap: () => Navigator.pop(ctx, e.key),
                )),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text('취소',
                      style: ResponsiveHelper.bodyStyle(ctx,
                          color: AppColors.textSecondary)),
                ),
              ),
            ),
          ],
         ),
        ),
      ),
    );
    if (picked == null || !mounted) return;
    final done = await ApplicantDocumentReviewService.instance.requestCorrection(
      applicationId: app.id,
      businessId: bizId,
      targetUid: r.workerUid,
      documentType: isId ? 'ID' : 'BANKBOOK',
      reasonCode: picked,
    );
    if (!mounted) return;
    if (done) ToastHelper.showSuccess('재등록을 요청했습니다.');
    await _loadApplicantDocumentReview();
  }

  // [PII-B4-R1] _loadIdCardSignedUrl 제거 — 다이얼로그가 원본을 들고
  //   있지 않는다. 확인 시트가 열릴 때만 발급받는다.

  /// [CONSENT-R4b · C-R4-4 · r4c] '급여계좌 보기'(또는 다시 불러오기)를 눌렀을 때만 확정 관계의
  ///   현재 급여계좌를 목적별 reader 로 읽는다. 급여 권한이 없으면 부르지 않는다(섹션 자체가 숨는다).
  ///   지원서가 없는 호출처는 관계를 특정할 수 없으므로 서버를 부르지 않고 그 사실을 보인다.
  ///   이미 받은 계좌를 화면에서 회수하거나 자동으로 닫지는 않는다(약속 0).
  Future<void> _loadPayrollAccount() async {
    if (_payrollAccountLoading) return;
    if (context.read<UserProvider>().checkCurrentBusiness((p) => p.canManageWage) !=
        PermissionCheck.allowed) {
      return;
    }
    final app = widget.application;
    final bizId = app?.businessId;
    if (app == null || app.id.isEmpty || bizId == null || bizId.isEmpty) {
      setState(() => _payrollAccount = WorkerPayrollAccountResult.noRelation);
      return;
    }
    setState(() => _payrollAccountLoading = true);
    final r = await WorkerPayrollAccountService()
        .fetch(businessId: bizId, applicationId: app.id);
    if (!mounted) return;
    setState(() {
      _payrollAccount = r;
      _payrollAccountLoading = false;
    });
  }

  /// [V3 BANKBOOK-SECURE-ACCESS] 통장사본 열람
  /// - 매 호출 시 CF callableGetBankbookSignedUrl로 1시간 Signed URL 발급
  /// - 캐싱 없음 (보안 목적) — 신분증과 달리 URL을 상태 변수에 저장하지 않는다
  Future<void> _viewBankbook() async {
    final appId = widget.application?.id;
    if (appId == null || appId.isEmpty) {
      ToastHelper.showError('지원서 정보가 없습니다.');
      return;
    }
    // [CROSS-DOMAIN-R5.2A] 대상 사업장을 명시한다 — 서버가 그 사업장 기준으로
    //   먼저 인가하고, 지원서는 그 뒤에 읽는다.
    final bizId = widget.application?.businessId;
    if (bizId == null || bizId.isEmpty) {
      ToastHelper.showError('사업장 정보가 없습니다.');
      return;
    }
    if (!mounted) return;
    setState(() => _bankbookLoading = true);
    try {
      final result = await FirebaseFunctions.instanceFor(region: 'asia-northeast3')
          .httpsCallable('callableGetBankbookSignedUrl')
          .call({'applicationId': appId, 'businessId': bizId});
      if (!mounted) return;
      final signedUrl = result.data['signedUrl'] as String?;
      if (signedUrl == null || signedUrl.isEmpty) {
        ToastHelper.showError('통장사본 URL을 가져오지 못했습니다.');
        return;
      }
      await ImageHelper.showFullScreenViewer(
        context,
        imageUrl: signedUrl,
        title: '통장사본',
        noCache: true, // [BANKBOOK-SEC] Signed URL — disk cache 금지
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      // [CONSENT-R4b] 열람 기간으로 닫힌 경우는 권한 없음과 다른 문장(계좌 칸과 같은 문장).
      final details = e.details;
      final windowClosed = details is Map && details['code'] == 'BANK_WINDOW_CLOSED';
      final closedKind = windowClosed ? details['closedKind'] as String? : null;
      final msg = windowClosed ? '통장사본: ${bankWindowClosedText(closedKind)}' : switch (e.code) {
        'permission-denied' => '열람 권한이 없습니다.',
        'not-found' => '통장사본 파일을 찾을 수 없습니다.',
        'failed-precondition' => e.message ?? '열람 조건을 충족하지 않습니다.',
        _ => '통장사본 열람에 실패했습니다: ${e.message}',
      };
      ToastHelper.showError(msg);
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError('통장사본 열람에 실패했습니다.');
      debugPrint('⚠️ [BANKBOOK] _viewBankbook error: $e');
    } finally {
      if (mounted) setState(() => _bankbookLoading = false);
    }
  }

  void _startAccessRefreshTimer() {
    _accessRefreshTimer?.cancel();
    _accessRefreshTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (!mounted) return;
      final currentUserId = context.read<UserProvider>().currentUser?.uid ?? '';
      final updated = await _firestoreService.checkIdCardAccess(
        requesterId: currentUserId,
        targetUserId: widget.user.uid,
      );
      if (!mounted) return;
      setState(() => _idCardAccess = updated);
      if (updated?.isValidAccess != true) _accessRefreshTimer?.cancel();
    });
  }

  @override
  void dispose() {
    _accessRefreshTimer?.cancel();
    super.dispose();
  }

  Future<String?> _fetchWorkTime(ApplicationModel app) async {
    if (app.startTime.isNotEmpty && app.endTime.isNotEmpty) {
      return '${app.startTime} ~ ${app.endTime}';
    }
    final to = await _firestoreService.getTOByApplication(app);
    if (to == null) return null;
    final workDetails = await _firestoreService.getWorkDetails(to.id);
    final matched = workDetails
        .where((w) => w.workType == app.selectedWorkType)
        .firstOrNull;
    if (matched == null) return null;
    return '${matched.startTime} ~ ${matched.endTime}';
  }

  Future<bool> _checkReviewWritten(ApplicationModel app) async {
    final now = DateTime.now();
    int reviewYear;
    int reviewMonth;
    if (app.isLongTermApplication) {
      if (now.month == 1) {
        reviewYear = now.year - 1;
        reviewMonth = 12;
      } else {
        reviewYear = now.year;
        reviewMonth = now.day < 5 ? now.month - 1 : now.month;
      }
    } else {
      reviewYear = app.workDate.year;
      reviewMonth = app.workDate.month;
    }
    final reviewKey = MonthlyReviewModel.generateKeyForUser(
      businessId: widget.businessId!,
      targetUserId: widget.user.uid,
      year: reviewYear,
      month: reviewMonth,
    );
    final existing = await MonthlyReviewService().getReviewById(reviewKey);
    return existing != null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPending = widget.application?.status == AppStatus.pending;

   return Dialog(
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
      ),
      insetPadding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 16),
        vertical: AppDialogSize.insetV,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * AppDialogSize.maxHeightRatio,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 헤더
            _buildHeader(context, theme),
            
            // 내용
            Flexible(
              child: (_auxLoading || _isLoading)
                  // [INVITE-PREACCEPT] 확정 전 지원자는 **서류 확인을 먼저** 보여준다.
                  //   서류 검토 상태는 부가 정보와 따로 로드되는데, 로딩 화면이
                  //   그것까지 가리면 근무 이력 같은 느린 조회 하나 때문에
                  //   관리자가 서류에 닿지 못한다. 로딩이 끝난 뒤 배치는 그대로다.
                  ? (widget.isConfirmed
                      ? const LoadingWidget()
                      : SingleChildScrollView(
                          padding: ResponsiveHelper.cardPadding(context),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildApplicantDocumentReviewSection(context),
                              const SizedBox(
                                  height: 80, child: LoadingWidget()),
                            ],
                          ),
                        ))
                  : SingleChildScrollView(
                      padding: ResponsiveHelper.cardPadding(context),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildBasicInfo(context),
                          SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                          if (widget.isConfirmed) ...[
                            _buildPaymentInfo(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildContractStatusSection(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildIdCardSection(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildWorkStats(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildBusinessHistory(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildRecentReviews(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildSelfIntro(context),
                          ] else ...[
                            // [DOCUMENT-VERIFICATION-INTEGRITY-R1.2]
                            //   확정 전에 서류를 한 화면에서 확인한다.
                            //   확정 뒤에 처음 보면 "확정 → 서류 불량 →
                            //   확정취소"가 정상 경로가 되어 버린다.
                            _buildApplicantDocumentReviewSection(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildWorkStats(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildBusinessHistory(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildSelfIntro(context),
                            SizedBox(height: ResponsiveHelper.spacing(context, 20)),
                            _buildRecentReviews(context),
                          ],
                        ],
                      ),
                    ),
            ),
            
            // 하단 버튼
            _buildBottomButtons(context, isPending),
          ],
        ),
      ),
    );
  }

  /// 헤더 (프로필 + 전화 버튼)
  Widget _buildHeader(BuildContext context, ThemeData theme) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(ResponsiveHelper.spacing(context, 20)),
          topRight: Radius.circular(ResponsiveHelper.spacing(context, 20)),
        ),
        border: const Border(bottom: BorderSide(color: AppColors.grey200)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              // 프로필 이미지 — [PH-WORKER-DETAIL-1B] soft brand bg (흰색 배경 → 이니셜이 허공에 뜨는 현상 수정)
              CircleAvatar(
                radius: ResponsiveHelper.spacing(context, 28),
                backgroundColor: theme.primaryColor.withValues(alpha: 0.10),
                child: widget.user.profileImageUrl != null
                    ? ClipOval(
                        child: CachedNetworkImage(
                          imageUrl: widget.user.profileImageUrl!,
                          width: ResponsiveHelper.spacing(context, 56),
                          height: ResponsiveHelper.spacing(context, 56),
                          fit: BoxFit.cover,
                          placeholder: (_, __) => const SizedBox.shrink(),
                          errorWidget: (_, __, ___) => Text(
                            widget.user.name.isNotEmpty ? widget.user.name[0] : '?',
                            style: ResponsiveHelper.titleStyle(context).copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.primaryColor,
                            ),
                          ),
                        ),
                      )
                    : Text(
                        widget.user.name.isNotEmpty ? widget.user.name[0] : '?',
                        style: ResponsiveHelper.titleStyle(context).copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor,
                        ),
                      ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 12)),
              
              // 이름 + 정보
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // [COMMON-TEXT-LAYOUT.28] 식별 정보인 이름이 '남궁아리아…' 로 잘렸다 — 줄 수 제한 없이 다 보인다
                        //   (기기 392dp·글자 2.0 에서 세 줄 제한도 '스티나합성근…' 로 잘렸다).
                        //   띄어쓰기 없는 긴 이름은 가운데에서만 끊는다(마지막 한 음절만 남지 않게).
                        Flexible(
                          child: Text(
                            TextLayout.identity(widget.user.name),
                            semanticsLabel: widget.user.name,
                            style: ResponsiveHelper.titleStyle(context).copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                        // 상태 배지
                        if (widget.application != null)
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: ResponsiveHelper.spacing(context, 8),
                              vertical: ResponsiveHelper.spacing(context, 2),
                            ),
                            decoration: BoxDecoration(
                              color: _getStatusColor(widget.application!.status).bg,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _getStatusLabel(widget.application!.status),
                              style: ResponsiveHelper.tinyStyle(context, color: _getStatusColor(widget.application!.status).fg).copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                    // [UI-3] 저장값이 제품 용어('남성'·'여성')일 때만 성별을, 생년월일이
                    //   있을 때만 나이를 쓴다. 없는 값을 `-세`·빈 구분점으로 만들지 않는다.
                    Builder(builder: (context) {
                      final facts = _profileFacts(widget.user);
                      return Text(
                        facts.isEmpty ? '성별·나이 정보 없음' : facts.join(' · '),
                        style: ResponsiveHelper.bodyStyle(context,
                            color: facts.isEmpty
                                ? AppColors.grey500
                                : AppColors.textSecondary),
                      );
                    }),
                  ],
                ),
              ),
              
              // [5A.2A] 신뢰도 점수 컨테이너 제거
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          
          // 연락처 + 전화 버튼
          // [UI-3] 번호가 없으면 테두리 상자(전화 버튼처럼 보임) 대신 사실만 적는다.
          if (widget.user.effectivePhone?.isNotEmpty != true)
            Row(
              children: [
                Icon(Icons.phone_disabled_outlined,
                    size: ResponsiveHelper.iconSize(context, 16),
                    color: AppColors.grey400),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text('연락처 정보 없음',
                    style: ResponsiveHelper.smallStyle(context,
                        color: AppColors.grey500)),
              ],
            )
          else
          Container(
            // [DU550 F138-WORKERDETAIL-B-LAYOUT] 칸 폭은 이전 Row 가 채우던 폭 그대로. 번호 묶음과 전화 칩이 한 줄에 안 들어가면
            //   (좁은 폭 · 큰 글자) 칩이 번호 아래 줄 가운데로 내려간다 — 번호 전문 · 글자 크기 · 칩 동작 그대로.
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 8),
            ),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: ResponsiveHelper.spacing(context, 12),
              runSpacing: ResponsiveHelper.spacing(context, 4),
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phone, size: ResponsiveHelper.iconSize(context, 16), color: AppColors.grey600),
                    SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                    Flexible(
                      child: Text(
                        widget.user.effectivePhone ?? '-',
                        style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
                if (widget.user.effectivePhone != null && widget.user.effectivePhone!.isNotEmpty)
                  Material(
                    color: theme.primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () => _makePhoneCall(widget.user.effectivePhone),
                      borderRadius: BorderRadius.circular(20),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: ResponsiveHelper.spacing(context, 12),
                          vertical: ResponsiveHelper.spacing(context, 4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.call,
                              size: ResponsiveHelper.iconSize(context, 14),
                              color: theme.primaryColor,
                            ),
                            SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                            Text(
                              '전화',
                              style: ResponsiveHelper.smallStyle(context, color: theme.primaryColor),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<String> _profileFacts(UserModel user) => workerProfileFacts(user);

  // [DU541] 상태 이름 칩 — 옅은 짝 면 + 진한 짝 글(StatusBadge 짝 · 원색 채움 위 흰 글은 대비 미달).
  ({Color bg, Color fg}) _getStatusColor(String status) {
    switch (status) {
      case AppStatus.pending:
        return (bg: AppColors.warningBg, fg: AppColors.warningDark);
      case AppStatus.confirmed:
        return (bg: AppColors.successBg, fg: AppColors.successDark);
      case AppStatus.rejected:
        return (bg: AppColors.errorBg, fg: AppColors.errorDark);
      // [DU541b R8] 계약 대기 = 중앙 정의(getStatusBackground/Text)와 같은 확정 짝 — 그 밖 갈래는 중립 그대로.
      case AppStatus.contractPending:
        return (bg: AppColors.confirmedBg, fg: AppColors.confirmedDark);
      default:
        return (bg: AppColors.grey200, fg: AppColors.grey700);
    }
  }

  // [PII-B4-R1] 주민번호 복사 감사 로그·포맷터 제거 — 복사 기능 자체가
  //   없어졌다. 대조만 필요하면 복사는 필요하지 않다(§25).

  String _getStatusLabel(String status) {
    switch (status) {
      case AppStatus.pending:
        return '대기중';
      case AppStatus.confirmed:
        return '확정';
      case AppStatus.contractPending:
        return '계약 대기';
      case AppStatus.rejected:
        return '거절';
      case AppStatus.canceled:
        return '취소됨';
      case AppStatus.autoCanceled:
        return '자동 취소됨';
      // [INVITE-PREACCEPT] 초대받은 사람의 상세가 이제 열린다 — 원문 enum
      //   (`INVITED`)을 그대로 보이지 않는다.
      case AppStatus.invited:
        return '초대 중';
      case AppStatus.expired:
        return '초대 만료';
      default:
        return status;
    }
  }

  /// 기본 정보
  Widget _buildBasicInfo(BuildContext context) {
    final app = widget.application;
    
    return _buildSection(
      context,
      title: '기본 정보',
      icon: Icons.person_outline,
      child: Column(
        children: [
          // [R1.2.1] 검토 단계에서는 정확한 주거 주소를 쓰지 않는다.
          //   통근 판단에 필요한 것은 시/군/구 수준이고 homeRegion이 이미 그 값이다.
          //   서버도 purpose=applicantReview 응답에서 address/detailAddress를 뺀다.
          if (!widget.isConfirmed)
            if (widget.user.homeRegion != null)
              _buildInfoRow(context, '거주 지역', _coarseRegionLabel(widget.user.homeRegion!))
            else
              const SizedBox.shrink()
          else if (widget.user.address != null)
            _buildInfoRow(context, '주소',
              '${widget.user.address}${widget.user.detailAddress != null ? ' ${widget.user.detailAddress}' : ''}'),
          // [E2-DETAIL-KST] 사건 시각은 KST 로 그린다(기기 시간대 무관) — 날짜별
          //   명단의 `MM/dd HH:mm 발송` 과 같은 시각이 나와야 한다.
          //   초대는 지원이 아니다. 아직 응답하지 않은 초대는 `초대 발송` 으로 말한다.
          if (app != null)
            widget.isConfirmed && app.confirmedAt != null
                ? _buildInfoRow(context, '확정일', FormatHelper.formatDateTimeFull(app.confirmedAt!))
                : (app.status == AppStatus.invited && app.invitedAt != null)
                    ? _buildInfoRow(context, '초대 발송', FormatHelper.formatDateTimeFull(app.invitedAt!))
                    : _buildInfoRow(context, '지원일', FormatHelper.formatDateTimeFull(app.appliedAt)),
          if (app != null &&
              app.status == AppStatus.invited &&
              app.effectiveInviteDeadline != null)
            _buildInfoRow(context, '수락 기한',
                FormatHelper.formatDateTimeFull(app.effectiveInviteDeadline!)),
          if (app != null)
            _buildInfoRow(context, '지원 업무', app.selectedWorkType),
          // 근무 시간 표시
          if (app != null) ...[
            Builder(builder: (context) {
              if (widget.toItem != null) {
                final workDetail = widget.toItem!.workDetails.where(
                  (w) => w.workType == app.selectedWorkType,
                ).firstOrNull;
                if (workDetail != null) {
                  return _buildInfoRow(context, '근무 시간', '${workDetail.startTime} ~ ${workDetail.endTime}');
                }
              }
              if (_workTime != null) {
                return _buildInfoRow(context, '근무 시간', _workTime!);
              }
              return const SizedBox.shrink();
            }),
          ],
          if (app != null && app.isLongTermApplication) ...[
            _buildInfoRow(context, '근무 기간', app.workPeriodDisplay),
            // ✅ 희망 시작일 강조 표시
            if (app.desiredStartDate != null)
              _buildInfoRow(
                context, 
                '희망 시작일', 
                '${app.desiredStartDate!.month}/${app.desiredStartDate!.day} (${_getWeekdayName(app.desiredStartDate!)})',
                highlight: true,
              ),
        ],
        ],
      ),
      
    );
  }
  String _getWeekdayName(DateTime date) => FormatHelper.weekday(date);

  /// [R1.2.1] 시/군/구까지만. district(동)는 붙이지 않는다 —
  /// 통근 판단에 필요한 정밀도를 넘어선다.
  String _coarseRegionLabel(UserRegion r) =>
      r.province != null && r.province!.isNotEmpty ? '${r.province} ${r.city}' : r.city;

  /// 근무 통계
  Widget _buildWorkStats(BuildContext context) {
    final user = widget.user;
    return _buildSection(
      context,
      title: '근무 통계',
      icon: Icons.bar_chart,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  icon: Icons.work_history_outlined,
                  label: '총 근무',
                  value: '${user.totalWorkDays}일',
                  // neutral — 근무일수는 semantic 강조 대상이 아님
                  color: AppColors.textPrimary,
                  bgColor: AppColors.grey100,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: _buildStatCard(
                  context,
                  icon: Icons.star_rounded,
                  label: '평균 평점',
                  value: user.averageRating > 0
                      ? user.averageRating.toStringAsFixed(1)
                      : '-',
                  // [DU541] 평점도 집계 칸 — 면 · 숫자 중립(DU426 평점 amber → textPrimary 와 같다)
                  color: AppColors.textPrimary,
                  bgColor: AppColors.grey100,
                ),
              ),
            ],
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  context,
                  icon: Icons.cancel_outlined,
                  label: '노쇼(90일)',
                  value: '${user.recentNoShowCount}회',
                  color: user.recentNoShowCount > 0 ? AppColors.errorDark : AppColors.textPrimary,
                  bgColor: AppColors.grey100,
                ),
              ),
              SizedBox(width: ResponsiveHelper.spacing(context, 8)),
              Expanded(
                child: _buildStatCard(
                  context,
                  icon: Icons.schedule_outlined,
                  label: '지각(90일)',
                  value: '${user.recentLateCount}회',
                  color: user.recentLateCount > 0 ? AppColors.warningDark : AppColors.textPrimary,
                  bgColor: AppColors.grey100,
                ),
              ),
            ],
          ),
          if (user.reviewCount > 0) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            _buildRehireRateBadge(context, user.rehireRate, user.reviewCount),
          ],
        ],
      ),
    );
  }

  Widget _buildRehireRateBadge(BuildContext context, double rate, int reviewCount) {
    final pct = (rate * 100).round();
    final IconData icon;
    if (rate >= 0.7) {
      icon = Icons.thumb_up_rounded;
    } else if (rate >= 0.4) {
      icon = Icons.thumbs_up_down_rounded;
    } else {
      icon = Icons.thumb_down_rounded;
    }

    // [PH-WORKER-DETAIL] 재고용 추천률 — metric이므로 full colored bg 대신
    // neutral surface + subtle border. [DU541b R2] 집계값 · 아이콘 · 선도 중립(구간은 엄지 모양이 말한다).
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: ResponsiveHelper.spacing(context, 12),
        vertical: ResponsiveHelper.spacing(context, 8),
      ),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 14), color: AppColors.grey600),
          SizedBox(width: ResponsiveHelper.spacing(context, 6)),
          // [DU550 F138-WORKERDETAIL-B-LAYOUT] 라벨이 남은 폭(이전 빈 칸 자리)을 채운다 — 좁으면 라벨이 낱말 사이에서 줄을 바꾸고 % · 건수는 오른쪽 끝 그대로.
          Expanded(
            child: Text(
              TextLayout.keepWords('재고용 추천률'),
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
            ),
          ),
          Text(
            '$pct%',
            style: ResponsiveHelper.bodyStyle(context).copyWith(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 4)),
          Text(
            '($reviewCount건)',
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    Color? bgColor,
  }) {
    final bg = bgColor ?? color.withValues(alpha: 0.1);
    return Container(
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 20), color: AppColors.grey600),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          Text(
            value,
            style: ResponsiveHelper.subtitleStyle(context).copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 2)),
          Text(
            label,
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// [R1.2] 이력 섹션의 안내 행 — '없음'과 '확인하지 못함'이 같은 모양을 쓰되
  /// 문구와 색으로 구분된다.
  Widget _buildHistoryNotice(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String message,
  }) {
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: ResponsiveHelper.iconSize(context, 16)),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Flexible(
            child: Text(
              message,
              style: ResponsiveHelper.smallStyle(context, color: color),
            ),
          ),
        ],
      ),
    );
  }

  /// '2026.10.29 · 분류' — 날짜·업무 중 있는 것만. 둘 다 없으면 '-'.
  static String _lastWorkLabel(Map<String, dynamic> h) {
    final d = h['lastWorkDate'];
    final type = h['lastWorkType'] as String?;
    final label = [
      if (d is DateTime) FormatHelper.formatDateDot(d),
      if (type != null && type.isNotEmpty) type,
    ].join(' · ');
    return label.isEmpty ? '-' : label;
  }

  /// 우리 사업장 이력
  Widget _buildBusinessHistory(BuildContext context) {
    return _buildSection(
      context,
      title: '우리 사업장 이력',
      icon: Icons.business,
      // [R1.2] 조회 실패는 '이력 없음'이 아니다 — 모른다고 말한다.
      // [HISTORY-CLOSEOUT.30] 이력 조회만 실패해도(권한 거부·요청 실패) 따로 말한다 — 다른 영역은 그대로.
      child: _loadFailed || _businessHistory?['error'] == 'failed'
          ? _buildHistoryNotice(
              context,
              icon: Icons.error_outline,
              color: AppColors.errorDark,
              message: '근무 이력을 확인하지 못했어요',
            )
          : _businessHistory?['error'] == 'denied'
          ? _buildHistoryNotice(
              context,
              icon: Icons.lock_outline,
              color: AppColors.grey600,
              message: '근무 이력을 볼 권한이 없어요 (근무자 관리 권한 필요)',
            )
          : _businessHistory == null || (_businessHistory!['workCount'] ?? 0) == 0
          ? _buildHistoryNotice(
              context,
              icon: Icons.info_outline,
              color: AppColors.grey500,
              message: '이 사업장에서 근무한 이력이 없습니다',
            )
          : Column(
              children: [
                _buildInfoRow(context, '근무 횟수', '${_businessHistory!['workCount']}회'),
                // [HISTORY-CLOSEOUT.30] 서비스가 돌려주는 키는 lastWorkDate·lastWorkType·averageRating 이다
                //   ('lastWork'·'avgRating' 을 읽어 최근 근무가 늘 '-', 평점이 늘 빠졌다).
                _buildInfoRow(context, '최근 근무', _lastWorkLabel(_businessHistory!)),
                if (_businessHistory!['averageRating'] is num && (_businessHistory!['averageRating'] as num) > 0)
                  _buildInfoRow(context, '평균 평점', '${(_businessHistory!['averageRating'] as num).toDouble().toStringAsFixed(1)}점'),
              ],
            ),
    );
  }

  /// 자기소개
  Widget _buildSelfIntro(BuildContext context) {
    // 지원서 메시지 또는 사용자 bio
    final message = widget.application?.applicationMessage ?? widget.user.bio;
    
    if (message == null || message.isEmpty) {
      return SizedBox.shrink();
    }
    
    return _buildSection(
      context,
      title: '자기소개',
      icon: Icons.chat_bubble_outline,
      child: Container(
        width: double.infinity,
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          color: AppColors.grey50,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          message,
          style: ResponsiveHelper.bodyStyle(context),
        ),
      ),
    );
  }

  /// 최근 리뷰
  Widget _buildRecentReviews(BuildContext context) {
    return _buildSection(
      context,
      title: '최근 리뷰',
      icon: Icons.rate_review,
      // [R1.2] 조회 실패를 '리뷰 없음'으로 표시하지 않는다.
      child: _loadFailed
          ? _buildHistoryNotice(
              context,
              icon: Icons.error_outline,
              color: AppColors.errorDark,
              message: '리뷰를 확인하지 못했어요',
            )
          : _recentReviews.isEmpty
          ? _buildHistoryNotice(
              context,
              icon: Icons.info_outline,
              color: AppColors.grey500,
              message: '아직 등록된 리뷰가 없습니다',
            )
          : Column(
              children: _recentReviews.map((review) => _buildReviewItem(context, review)).toList(),
            ),
    );
  }

  Widget _buildReviewItem(BuildContext context, MonthlyReviewModel review) {
    return Container(
      margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: AppColors.grey50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 별점 — [DU541b R4] 채움/윤곽으로 구분 · 색은 중립 grey600(새 amber 예외 0)
              Row(
                children: List.generate(5, (index) => Icon(
                  index < review.rating ? Icons.star : Icons.star_border,
                  size: ResponsiveHelper.iconSize(context, 14),
                  color: AppColors.grey600,
                )),
              ),
              const Spacer(),
              Text(
                DateFormat('yy.MM.dd').format(review.createdAt),
                style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
              ),
            ],
          ),
          if (review.comment?.isNotEmpty == true) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(
              review.comment!,
              style: ResponsiveHelper.smallStyle(context),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            '${review.businessName} · ${review.reviewYear}년 ${review.reviewMonth}월',
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500),
          ),
        ],
      ),
    );
  }

  // ── [DOCUMENT-VERIFICATION-INTEGRITY-R1.2] 지원자 서류 확인 ──────────────
  //
  //   신분증과 통장사본을 한 섹션에 둔다. 두 화면으로 갈라 두면 관리자가
  //   하나만 보고 확정하고, 나머지는 급여 단계에서 처음 발견된다.
  //
  //   판정은 전부 서버가 준 값이다 — 여기서 낡음을 다시 계산하지 않는다.

  Widget _buildApplicantDocumentReviewSection(BuildContext context) {
    final app = widget.application;
    final bizId = app?.businessId ?? widget.businessId;
    if (app == null || bizId == null || bizId.isEmpty) {
      return const SizedBox.shrink();
    }
    final r = _docReview;
    return _buildSection(
      context,
      title: '서류 확인',
      icon: Icons.assignment_ind_outlined,
      child: _docReviewLoading
          ? Padding(
              padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 12)),
              child: const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))),
            )
          : r == null
              // 실패를 '서류 없음'으로 말하지 않는다.
              // [ADMIN-DOC-REVIEW-UX] 모르면 승인도 닫혀 있다 — 여기서 다시 읽게 한다.
              ? Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: ResponsiveHelper.spacing(context, 8),
                  children: [
                    Text('서류 상태를 불러오지 못해 확정할 수 없어요.',
                        style: ResponsiveHelper.smallStyle(context,
                            color: AppColors.grey600)),
                    TextButton(
                      onPressed: _loadApplicantDocumentReview,
                      child: Text('다시 불러오기',
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.brand)),
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // [ADMIN-DOC-REVIEW-UX] 확정 조건을 **먼저** 말한다 — 하단
                    //   `승인` 버튼이 따르는 바로 그 판정(matchingReadiness)이다.
                    _approvalStatusBanner(context, r),
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    if (r.consentBlock != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.grey100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(r.consentBlockLabel!,
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.textPrimary)),
                      ),
                      SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                    // [ADMIN-APPROVAL-PERMISSION] 확정이 막힌 경우엔 위 배너가 이미
                    //   "누가 확인할 수 있는지"를 말한다 — 같은 문장을 두 번 쓰지 않는다.
                    ] else if (!r.canReviewDocuments && r.matchingReady) ...[
                      Text('서류를 확인하려면 TO 관리와 급여 관리 권한이 모두 필요합니다.',
                          style: ResponsiveHelper.smallStyle(context,
                              color: AppColors.grey600)),
                      SizedBox(height: ResponsiveHelper.spacing(context, 10)),
                    ],
                    _docRow(context, r, isId: true),
                    Padding(
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 10)),
                      child: const Divider(height: 1, thickness: 0.5),
                    ),
                    _docRow(context, r, isId: false),
                  ],
                ),
    );
  }

  /// [ADMIN-DOC-REVIEW-UX] 확정 조건 요약 — 하단 `승인` 과 같은 판정.
  ///
  ///   [PII-DOC-R1.5] 확정은 신분 확인만 본다. 급여계좌는 지급 단계의
  ///   문제이므로 확정을 막는 사유로 말하지 않는다.
  Widget _approvalStatusBanner(BuildContext context, ApplicantDocumentReview r) {
    // [E2-INVITE-NEXT-ACTION] 초대는 관리자가 확정하지 않는다 — 근로자가 수락한다.
    //   직접 지원의 `확정할 수 있어요` 문장을 초대 상세에 쓰지 않는다.
    final app = widget.application;
    final bool isInvite = app != null && app.status == AppStatus.invited;
    final deadline = isInvite ? app.effectiveInviteDeadline : null;
    final inviteExpired = deadline != null && !DateTime.now().isBefore(deadline);
    final ready = r.matchingReady && !inviteExpired;
    final String text;
    if (isInvite) {
      text = r.inviteNextActionText(
        expired: inviteExpired,
        deadlineLabel:
            deadline == null ? null : FormatHelper.formatDateTime(deadline),
      );
    } else if (ready) {
      // [ADMIN-REJECT-PERMISSION] "확정할 수 있어요"는 확정 권한까지 있을 때만
      //   말한다 — 하단 승인이 회색인데 배너만 가능하다고 하면 위계가 어긋난다.
      final perm = _confirmPermission(listen: true);
      final String idLine;
      if (perm == PermissionCheck.allowed) {
        idLine = r.matchedAutomatically
            ? '신분증 정보가 자동 대조로 일치해 확정할 수 있어요.'
            : '신분증 확인이 끝나 확정할 수 있어요.';
      } else {
        final idFact = r.matchedAutomatically
            ? '신분증 정보가 자동 대조로 일치해요.'
            : '신분증 확인은 끝났어요.';
        final permLine = switch (perm) {
          PermissionCheck.unknown => '확정 권한을 확인하고 있어요.',
          PermissionCheck.error => '확정 권한을 확인하지 못했어요.',
          _ => '확정은 TO 관리 권한이 있는 관리자가 할 수 있어요.',
        };
        idLine = '$idFact\n$permLine';
      }
      text = r.okFor(isId: false)
          ? idLine
          : '$idLine\n급여계좌는 지급 전까지 확인하면 돼요.';
    } else {
      text = r.approvalBlockText ?? '아직 확정할 수 없어요.';
    }
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
      decoration: BoxDecoration(
        // [DU541] 확정 가능(정상)은 중립 띠 · 확정 불가(실제 주의)는 이 창의 대표 안내(E-NOTICE)로 둔다.
        color: ready ? AppColors.grey100 : AppColors.warningBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(ready ? Icons.check_circle_outline : Icons.info_outline,
              size: ResponsiveHelper.iconSize(context, 16),
              color: ready ? AppColors.grey600 : AppColors.warningDark),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(text,
                style: ResponsiveHelper.smallStyle(context,
                    color: ready ? AppColors.textPrimary : AppColors.warningDark)),
          ),
        ],
      ),
    );
  }

  Widget _docRow(BuildContext context, ApplicantDocumentReview r,
      {required bool isId}) {
    final has = isId ? r.hasIdCard : r.hasBankbook;
    final ok = r.okFor(isId: isId);
    final canAct = r.canReviewDocuments && r.consentBlock == null && has;
    // 상태 글자색과 같은 판정 — 자동 대조 일치(낡지 않음)면 수동 확인은 선택이다.
    final manualNeeded =
        isId && !ok && !(r.matchedAutomatically && !r.idStale);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // [ADMIN-DOC-REVIEW-UX] 제목과 상태가 한 줄에 들어가지 않으면(좁은 폭·
        //   큰 글자) 상태가 줄을 바꾼다 — 잘리지 않는다.
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Text(isId ? '신분증' : '급여계좌 · 통장사본',
                  style: ResponsiveHelper.bodyStyle(context)
                      .copyWith(fontWeight: FontWeight.w600)),
            ),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            // 상태는 남은 폭의 2/5 까지 — Align 으로 그 칸의 오른쪽 끝에
            //   붙인다(그냥 두면 상태가 행 가운데에 떠 있었다).
            Flexible(
              flex: 2,
              child: Align(
                alignment: Alignment.topRight,
                child: Text(
                  // [DOC-APP-CLOSEOUT.10] 응답에 등록 기록이 없으면 '미등록'이 아니라 모름이다.
                  has ? r.labelFor(isId: isId) : (isId && !r.idPresenceKnown ? '확인 불가' : '미등록'),
                  textAlign: TextAlign.end,
                  style: ResponsiveHelper.smallStyle(context,
                      // [ADMIN-APPROVAL-PERMISSION] 자동 대조 일치(`서류 정보 일치`)는
                      //   확정을 허용하는 상태다 — 위 배너가 초록인데 여기만
                      //   경고색이면 같은 사실을 두 색으로 말한다.
                      color: !has
                          ? AppColors.grey500
                          : ((ok || (isId && r.matchedAutomatically && !r.idStale))
                              ? AppColors.successDark
                              : AppColors.warningDark),
                      fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
        // 이 서류가 무엇에 쓰이는가 — 확정 조건인지, 지급 조건인지.
        Text(isId ? '근무 확정 전에 확인' : '급여 지급 전까지 확인',
            style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey500)),
        // 계좌 원문은 자격이 있을 때만 서버가 준다. 없으면 여기에도 없다.
        if (!isId && r.bankName != null) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text('${r.bankName} · ${r.accountNumber ?? '-'} · ${r.accountHolder ?? '-'}',
              style: ResponsiveHelper.smallStyle(context,
                  color: AppColors.grey600)),
        ],
        if (canAct) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          // [ADMIN-DOC-REVIEW-UX] Row + Spacer 는 360dp 에서 19·31px,
          //   320dp 에서 55·67px 넘쳐 `다시 등록 요청` 이 잘렸다(기기 실측).
          //   Wrap 은 자리가 모자라면 다음 줄로 보낸다 — 버튼이 사라지지 않는다.
          // [UI-3] 화면의 주된 행동은 하단 `확정` 이다. 서류 행동 셋은 같은 높이·
          //   모서리·테두리의 보조 행동으로 맞춘다(채움·그림자 반복 없음).
          //   수동 확인이 **확정 전에 필요한** 신분증일 때만 `확인 완료` 를 브랜드
          //   테두리로 드러낸다 — 자동 대조 일치·급여계좌는 선택 절차처럼 중립.
          Wrap(
            spacing: ResponsiveHelper.spacing(context, 8),
            runSpacing: ResponsiveHelper.spacing(context, 8),
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _docAction(context, isId ? '신분증 보기' : '통장사본 보기',
                  color: AppColors.textPrimary,
                  onPressed: () => _viewApplicantDocument(isId: isId)),
              if (!ok)
                _docAction(context, '확인 완료',
                    color: manualNeeded
                        ? AppColors.brand
                        : AppColors.textSecondary,
                    required: manualNeeded,
                    onPressed: () =>
                        _reviewApplicantDocument(isId: isId, ok: true)),
              _docAction(context, '다시 등록 요청',
                  color: AppColors.errorDark,
                  onPressed: () => _requestApplicantCorrection(isId: isId)),
            ],
          ),
        ],
      ],
    );
  }

  /// [UI-3] 서류 행동 한 칸 — 셋 모두 같은 높이(36)·모서리(8)·테두리.
  Widget _docAction(BuildContext context, String label,
      {required Color color,
      required VoidCallback onPressed,
      bool required = false}) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        minimumSize: const Size(0, 36),
        padding: EdgeInsets.symmetric(
            horizontal: ResponsiveHelper.spacing(context, 12)),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        side: BorderSide(color: required ? AppColors.brand : AppColors.grey300),
      ),
      child: Text(label,
          style: ResponsiveHelper.smallStyle(context, color: color).copyWith(
              fontWeight: required ? FontWeight.w600 : FontWeight.w500)),
    );
  }

  /// 급여 정보 (확정자 + canManageWage 권한자만)
  Widget _buildPaymentInfo(BuildContext context) {
    // [SEC-01] 계좌 정보는 급여 담당 권한자만 열람 가능
    if (context.read<UserProvider>().checkCurrentBusiness((p) => p.canManageWage) != PermissionCheck.allowed) {
      return const SizedBox.shrink();
    }

    // [V3 BANKBOOK-SECURE-ACCESS] 통장사본 버튼 표시 조건:
    //   1) 확정(CONFIRMED) 지원서가 있어야 함
    //   2) documentAccessConsentGiven == true (V3) 또는 idCardConsentGiven == true (legacy)
    //   3) 통장사본 파일이 존재해야 함 (bankbookImagePath OR bankbookImageUrl)
    final app = widget.application;
    // [4J.0B] CONTRACT_PENDING은 CONFIRMED와 다름 — CF callableGetBankbookSignedUrl이
    // appStatus !== "CONFIRMED" 시 permission-denied 반환하므로 클라이언트도 동일하게 제한
    // confirmedStatuses.contains()는 contractPending을 포함하여 UI 버튼이 노출되지만 CF가 차단하는 불일치 수정
    final isConfirmedApp = app != null &&
        app.status == AppStatus.confirmed;
    // [V3] 통장사본은 documentAccessConsentGiven 전용 — idCardConsentGiven(legacy)는 신분증 접근만 허용
    // CF callableGetBankbookSignedUrl도 documentAccessConsentGiven만 검증하므로 UI와 일치시킴
    final hasConsent = app != null && app.documentAccessConsentGiven;
    final hasBankbookFile = widget.user.hasBankbookDocument;
    final canViewBankbook = isConfirmedApp && hasConsent && hasBankbookFile;

    return _buildSection(
      context,
      title: '급여 정보',
      icon: Icons.account_balance,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [CONSENT-R4b · C-R4-4] 목적별 reader 결과만 그린다. 예금주를 이름으로 대신 채우지 않는다
          //   (accountHolder 는 서버 저장값 — 정책 레지스트리 §4).
          ..._buildPayrollAccountRows(context),
          // [V3] 통장사본 보기 — bankbookImageUrl 직접 노출 금지, Signed URL 전용
          if (canViewBankbook) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _bankbookLoading ? null : _viewBankbook,
                icon: _bankbookLoading
                    ? SizedBox(
                        width: ResponsiveHelper.iconSize(context, 16),
                        height: ResponsiveHelper.iconSize(context, 16),
                        child: const CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.account_balance_wallet_outlined,
                        size: ResponsiveHelper.iconSize(context, 16)),
                label: Text(
                  _bankbookLoading ? '불러오는 중...' : '통장사본 보기',
                  style: ResponsiveHelper.bodyStyle(context),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// [CONSENT-R4b] '급여 정보' 계좌 줄 — 상태마다 다른 한 줄(같은 '-' 로 숨기지 않는다).
  List<Widget> _buildPayrollAccountRows(BuildContext context) {
    final r = _payrollAccount;
    if (r == null && !_payrollAccountLoading) {
      // [r4c] 명시 요청 버튼(48×48 이상) — 누르기 전에는 서버 호출 0.
      return [
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            key: const ValueKey('payrollAccountRequest'),
            onPressed: _loadPayrollAccount,
            style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
            icon: Icon(Icons.account_balance_outlined, size: ResponsiveHelper.iconSize(context, 16)),
            label: Text('급여계좌 보기', style: ResponsiveHelper.bodyStyle(context)),
          ),
        ),
      ];
    }
    if (_payrollAccountLoading || r == null) {
      return [
        Padding(
          key: const ValueKey('payrollAccountLoading'),
          padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
          child: Text('급여계좌를 불러오는 중…',
              style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary)),
        ),
      ];
    }
    if (r.kind == WorkerPayrollAccountKind.ok) {
      return [
        _buildInfoRow(context, '은행', r.bankName ?? '-'),
        _buildInfoRow(context, '계좌번호', r.accountNumber ?? '-'),
        _buildInfoRow(context, '예금주', r.accountHolder ?? '-'),
      ];
    }
    return [
      Padding(
        key: ValueKey('payrollAccountStatus_${r.kind.name}_${r.reason ?? r.errorCode ?? ''}'),
        padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
        child: Text(TextLayout.keepWords(r.statusText ?? '지금은 계좌를 볼 수 없어요.'),
            semanticsLabel: r.statusText,
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.textSecondary)),
      ),
      if (r.kind == WorkerPayrollAccountKind.error)
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('payrollAccountRetry'),
            onPressed: _loadPayrollAccount,
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            child: Text('다시 불러오기',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.brand, fontWeight: FontWeight.w600)),
          ),
        ),
    ];
  }

  /// 근로계약서 섹션 (확정자만)
  Widget _buildContractStatusSection(BuildContext context) {
    return _buildSection(
      context,
      title: '근로계약서',
      icon: Icons.description_outlined,
      child: _buildContractContent(context),
    );
  }

  /// [PERM-CONTRACT-DEADEND-01] 계약 생성/서명은 canManageContract 전용 액션.
  /// 서버(callableGetContractsByBiz·callableFinalizeEmployerSignature)와 rules가
  /// 모두 canManageContract를 요구하므로 UI 진입도 동일 기준으로 정렬한다.
  /// BUSINESS_ADMIN은 UserProvider.can()이 항상 true.
  bool _canManageContract() =>
      context.read<UserProvider>().checkCurrentBusiness((p) => p.canManageContract) == PermissionCheck.allowed;

  Widget _buildContractContent(BuildContext context) {
    final contract = _contract;

    if (contract == null) {
      // [PERM-CONTRACT-DEADEND-01] 승인/근무자 관리 권한만 있는 SUB_ADMIN에게
      // 계약서 작성 CTA를 노출하면 템플릿 선택·서명까지 진행 후 서버에서 거부된다.
      final canCreateBase = widget.isConfirmed &&
          widget.application != null &&
          (widget.toItem != null ||
              widget.application!.toId?.isNotEmpty == true);
      final canCreate = canCreateBase && _canManageContract();
      return Column(
        children: [
          Container(
            padding: ResponsiveHelper.cardPadding(context),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: AppColors.grey400, size: ResponsiveHelper.iconSize(context, 16)),
                SizedBox(width: ResponsiveHelper.spacing(context, 8)),
                Text(
                  '계약서가 없습니다',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
                ),
              ],
            ),
          ),
          // [PERM-CONTRACT-DEADEND-01] 계약 권한 없는 관리자 안내 —
          // CTA 대신 요청 경로만 알린다 (별도 modal 없음).
          if (canCreateBase && !canCreate) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            Text(
              '계약서 발송 권한이 없습니다.\n계약 관리 권한이 있는 관리자에게 요청해주세요.',
              style:
                  ResponsiveHelper.smallStyle(context, color: AppColors.grey500),
            ),
          ],
          if (canCreate) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            SizedBox(
              width: double.infinity,
              child: _buildDialogButton(
                label: '계약서 작성하기',
                icon: Icons.draw_outlined,
                bgColor: Theme.of(context).primaryColor.withValues(alpha: 0.08),
                textColor: Theme.of(context).primaryColor,
                onTap: _createContractAndSign,
              ),
            ),
          ],
        ],
      );
    }

    if (contract.status == ContractStatus.pendingEmployer) {
      return SizedBox(
        width: double.infinity,
        child: _buildDialogButton(
          label: '계약서 서명하기 (사업주)',
          icon: Icons.draw,
          bgColor: Theme.of(context).primaryColor.withValues(alpha: 0.08),
          textColor: Theme.of(context).primaryColor,
          onTap: () => _openExistingContractSign(contract),
        ),
      );
    }

    if (contract.status == ContractStatus.pendingWorker) {
      return Container(
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.hourglass_top, color: AppColors.grey600, size: ResponsiveHelper.iconSize(context, 20)),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // [DU541b R7] 근로자 응답 대기 — 관리자 할 일이 아니라 제목도 중립.
                  Text(
                    '근무자 서명 대기 중',
                    style: ResponsiveHelper.bodyStyle(context).copyWith(
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '근무자에게 서명 요청 알림이 발송되었습니다',
                    style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (contract.status == ContractStatus.completed) {
      return Container(
        padding: ResponsiveHelper.cardPadding(context),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Icon(Icons.verified, color: AppColors.grey600, size: ResponsiveHelper.iconSize(context, 20)),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Text(
              '계약서 서명 완료',
              style: ResponsiveHelper.bodyStyle(context).copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
      );
    }

    // voided — [DU541b R3] 바깥 면 중립 + 작은 무효 표시(errorBg 원 · errorDark 아이콘) · 글 textPrimary(넓은 빨강 띠 0).
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            decoration: const BoxDecoration(color: AppColors.errorBg, shape: BoxShape.circle),
            child: Icon(Icons.cancel_outlined, color: AppColors.errorDark, size: ResponsiveHelper.iconSize(context, 20)),
          ),
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Text(
            '계약 무효 처리됨',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }

  Future<void> _openExistingContractSign(EmploymentContractModel contract) async {
    var c = contract;

    // 조항 없는 구 계약서 → 서명 전에 템플릿 선택 유도
    if (c.articles.isEmpty) {
      final businessId = widget.businessId ?? widget.toItem?.to.businessId;
      if (businessId != null && mounted) {
        final articles = await ContractTemplateSelectorDialog.show(
          context,
          businessId: businessId,
        );
        if (articles == null || !mounted) return; // 취소 → 중단
        if (articles.isNotEmpty) {
          await ContractService().updateArticles(
            contractId: c.id,
            articles: articles,
          );
          if (!mounted) return;
          c = c.copyWith(articles: articles);
        }
      }
    }

    if (!mounted) return;
    final nav = Navigator.of(context, rootNavigator: true);
    Navigator.pop(context, _hasChanges);
    widget.onStatusChanged?.call();
    await nav.push(MaterialPageRoute(
      builder: (_) => ContractSignScreen(contract: c, role: 'employer'),
    ));
  }

  /// 신분증 섹션 (확정자만)
  Widget _buildIdCardSection(BuildContext context) {
    return _buildSection(
      context,
      title: '신분증',
      icon: Icons.badge,
      child: _buildIdCardContent(context),
    );
  }

  /// [PII-B4-R1] 세무 identity 확인 상태.
  ///
  ///   이 섹션이 답하는 질문은 하나다 — 소득신고에 쓸 등록 정보가
  ///   지금 제출된 신분증과 맞는가. 다이얼로그를 여는 것만으로 원본이
  ///   열리지 않는다(§22). 관리자가 [신분증 확인]을 누를 때만 연다.
  Widget _buildIdCardContent(BuildContext context) {
    final r = _taxReview;
    if (_taxReviewLoading && r == null) {
      return const Center(child: LoadingWidget());
    }
    if (r == null) {
      return Text('확인 상태를 불러오지 못했습니다. 다시 시도해주세요.',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500));
    }
    if (!r.hasIdDocument) {
      return Text('신분증이 등록되어 있지 않습니다.',
          style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500));
    }

    final ok = r.state == TaxReviewState.reviewedOk;
    final color = ok ? AppColors.successDark : AppColors.warningDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(ok ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 18, color: color),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            Text(r.state.label,
                style: ResponsiveHelper.smallStyle(context,
                    color: color, fontWeight: FontWeight.w700)),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 4)),
        Text(r.state.description,
            style: ResponsiveHelper.smallStyle(context, color: AppColors.grey500)),
        if (ok && r.reviewedAt != null) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text('마지막 확인 ${FormatHelper.formatDateDot(r.reviewedAt!)}',
              style: ResponsiveHelper.tinyStyle(context, color: AppColors.grey400)),
        ],
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        SizedBox(
          width: double.infinity,
          child: _buildDialogButton(
            label: ok ? '다시 보기' : '신분증 확인',
            icon: Icons.badge_outlined,
            bgColor: Theme.of(context).primaryColor.withValues(alpha: 0.08),
            textColor: Theme.of(context).primaryColor,
            onTap: _openTaxIdentityReview,
          ),
        ),
      ],
    );
  }

  /// [§22·§23] 명시적 요청 시에만 원본을 열고, 등록 정보와 나란히 보여준다.
  Future<void> _openTaxIdentityReview() async {
    final r = _taxReview;
    final bizId = widget.application?.businessId ?? widget.businessId;
    if (r == null || bizId == null || bizId.isEmpty) return;

    String url;
    try {
      url = await TaxIdentityReviewService.idCardUrl(
        businessId: bizId,
        targetUid: widget.user.uid,
        expectedIdDocumentVersion: r.idDocumentVersion,
      );
    } catch (e) {
      debugPrint('❌ 신분증 열람 실패: $e');
      if (mounted) {
        ToastHelper.showError(e is FirebaseFunctionsException && e.code == 'aborted'
            ? (e.message ?? '신분증이 변경되었습니다. 다시 시도해주세요.')
            : '신분증을 열지 못했습니다');
      }
      return;
    }
    if (!mounted || url.isEmpty) return;

    final decision = await DialogHelper.showSheet<String>(
      context,
      isScrollControlled: true,
      builder: (ctx) => _TaxIdentityReviewSheet(
        review: r, imageUrl: url,
        businessId: bizId, targetUid: widget.user.uid,
      ),
    );
    if (decision == null || !mounted) return;

    try {
      final res = await TaxIdentityReviewService.submit(
        businessId: bizId,
        targetUid: widget.user.uid,
        decision: decision,
        expectedIdDocumentVersion: r.idDocumentVersion,
        expectedTaxIdentityFingerprint: r.taxIdentityFingerprint,
      );
      if (!mounted) return;
      ToastHelper.showSuccess(res.correctionOpened
          ? '근로자에게 정보 수정을 요청했습니다'
          : '확인 완료했습니다');
      await _loadTaxIdentityReview();
    } catch (e) {
      if (!mounted) return;
      ToastHelper.showError(e is FirebaseFunctionsException && e.code == 'aborted'
          ? (e.message ?? '정보가 변경되었습니다. 다시 확인해주세요.')
          : '확인 결과를 저장하지 못했습니다');
      debugPrint('❌ 세무 identity 확인 저장 실패: $e');
    }
  }

  Future<void> _loadTaxIdentityReview() async {
    final bizId = widget.application?.businessId ?? widget.businessId;
    if (bizId == null || bizId.isEmpty) return;
    if (mounted) setState(() => _taxReviewLoading = true);
    final r = await TaxIdentityReviewService.load(
        businessId: bizId, targetUid: widget.user.uid);
    if (!mounted) return;
    setState(() {
      _taxReview = r;
      _taxReviewLoading = false;
    });
  }

  /// 공통 섹션 빌더
  Widget _buildSection(BuildContext context, {required String title, required IconData icon, required Widget child}) {
    // [DU550 PP-WORKERDETAIL-SECTION] 구역 머리 막대(상태 · 행동을 말하지 않는 반복 장식) 제거 — 기능 아이콘 grey600(DU541b R5) · 제목 · 크기 · 읽기 순서 그대로.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: ResponsiveHelper.iconSize(context, 15), color: AppColors.grey600),
            SizedBox(width: ResponsiveHelper.spacing(context, 6)),
            // [ADMIN-DOC-REVIEW-UX] 큰 글자(2.0x)·좁은 폭에서 제목이 줄을
            //   바꾼다 — Flexible 이 없어 320dp 에서 70px 넘쳤다.
            Flexible(
              child: Text(
                title,
                style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        child,
      ],
    );
  }

  /// [E2-DETAIL-NARROW] 라벨 칸 폭 — 가장 긴 라벨이 **지금 글자 배율로** 한 줄에
  ///   들어가는 폭과 기본 80 중 큰 값.
  ///
  ///   80 고정이었다. 320dp × 1.3 에서 `거주 지/역`, `지원 업/무` 처럼 글자 단위로
  ///   잘렸고, 411dp × 1.3 에서는 라벨이 칸을 꽉 채워 값과 붙었다. 모든 행이
  ///   같은 폭을 써야 값의 시작선이 맞으므로 행마다 재지 않고 기준 라벨로 잰다.
  ///   (이 화면 라벨은 모두 공백 포함 5자 이하다.)
  double _infoLabelWidth(BuildContext context, TextStyle style) {
    // Text 위젯은 DefaultTextStyle(테마 글꼴 등)에 style 을 합쳐 그린다 —
    //   같은 스타일로 재야 잰 폭과 그린 폭이 같다.
    final painter = TextPainter(
      text: TextSpan(
          text: '근무 시간',
          style: DefaultTextStyle.of(context).style.merge(style)),
      // 이 파일은 intl 을 import 해 `TextDirection` 이름이 겹친다 — 문맥 값을 쓴다.
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final measured = painter.width.ceilToDouble();
    painter.dispose();
    final base = ResponsiveHelper.spacing(context, 80);
    // 아주 큰 배율(2.0)에서 라벨이 값의 자리를 다 먹지 않게 화면 폭의 35% 로
    //   막는다. 그때는 라벨이 **단어 경계**(`근무`/`시간`)에서 줄을 바꾼다.
    final cap = MediaQuery.sizeOf(context).width * 0.35;
    final wanted = measured > base ? measured : base;
    return wanted > cap ? cap : wanted;
  }

  Widget _buildInfoRow(BuildContext context, String label, String value, {bool highlight = false}) {
    final theme = Theme.of(context);
    final labelStyle =
        ResponsiveHelper.bodyStyle(context, color: AppColors.grey500);
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _infoLabelWidth(context, labelStyle),
            child: Text(
              label,
              style: labelStyle,
            ),
          ),
          // 라벨과 값 사이 간격 — 라벨이 칸을 다 써도 값과 붙지 않는다.
          SizedBox(width: ResponsiveHelper.spacing(context, 8)),
          Expanded(
            child: Text(
              value,
              style: ResponsiveHelper.bodyStyle(
                context, 
                color: highlight ? theme.primaryColor : null,
              ).copyWith(
                fontWeight: highlight ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 하단 버튼
  Widget _buildDialogButton({
    required String label,
    required IconData icon,
    required Color bgColor,
    required Color textColor,
    required VoidCallback onTap,
    double verticalPadding = 12,
  }) {
    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: verticalPadding, horizontal: 4),
          // [COMMON-TEXT-LAYOUT.28] 예전엔 FittedBox 로 줄였다 — 사용자가 키운 글자까지 되돌려 작아졌다.
          //   글자는 그대로 두고, 한 줄에 다 안 들어가면 하단 바가 버튼을 쌓는다(_buildBottomButtons).
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: textColor),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomButtons(BuildContext context, bool isPending) {
    final isConfirmed = AppStatus.confirmedStatuses.contains(widget.application?.status);
    final isLongTerm = widget.toItem?.to.isLongTerm ??
                       widget.application?.isLongTermApplication ??
                       false;
    final primary = Theme.of(context).primaryColor;

    // [COMMON-TEXT-LAYOUT.28] 칸(버튼·안내)을 모은 뒤, 한 줄에 칸당 [_footerCellMinWidth] × 글자 배율이
    //   들어가면 지금처럼 나란히, 아니면 칸마다 한 줄로 쌓는다(글자를 줄이지 않는다).
    final cells = <({Widget child, int flex})>[];
    final row = Row(
        children: [
          // 닫기 버튼 (항상)
          Expanded(
            child: _buildDialogButton(
              label: '닫기',
              icon: Icons.close,
              bgColor: AppColors.grey100,
              textColor: AppColors.grey600,
              onTap: () => Navigator.pop(context, _hasChanges),
            ),
          ),

          // 승인/거절 버튼 (대기중이고 showApprovalButtons가 true일 때만)
          // 블랙리스트 근무자는 승인 버튼 숨김 (지원 후 블랙리스트 등록된 경우 방어)
          // [ADMIN-APPROVAL-PERMISSION] 확정 권한이 **확인된 거부**면 두 버튼 대신
          //   이유를 말한다(감추는 것은 확인된 거부일 때뿐 — 모름·오류는 아래
          //   게이트가 `확인 중`/회색으로 지킨다).
          if (isPending && widget.showApprovalButtons && widget.application != null &&
              !widget.user.isBlacklisted &&
              _confirmPermission(listen: true) == PermissionCheck.denied) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              flex: 2,
              child: Text(_noConfirmPermissionText,
                  style: ResponsiveHelper.smallStyle(context,
                      color: AppColors.grey600)),
            ),
          ] else if (isPending && widget.showApprovalButtons && widget.application != null &&
              !widget.user.isBlacklisted) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(child: _buildRejectButton()),
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            // [ADMIN-DOC-REVIEW-UX] 서버 확정 조건(신분 확인)을 **알 때만** 연다.
            //   조회 중·조회 실패·확정 불가에서는 회색으로 두고 이유만 말한다
            //   (같은 파일의 `확정취소` 와 같은 방식).
            Expanded(
              child: Builder(builder: (context) {
                final gate =
                    _approvalGateWith(_confirmPermission(listen: true));
                final open = gate == ApprovalGate.ready;
                // [UI-APPLICANTS-AND-INVITATIONS.2] 채용 행동은 '확정'(인력 현황·지원 검토와 같은 말).
                //   이 화면의 다음 일이므로 유일한 채움 버튼 — 열렸을 때만. 닫힘·확인 중은 회색 그대로.
                return _buildDialogButton(
                  label: gate == ApprovalGate.checking ? '확인 중' : '확정',
                  icon: gate == ApprovalGate.checking
                      ? Icons.hourglass_empty
                      : Icons.check_circle_outline,
                  bgColor: open ? AppColors.brand : AppColors.grey100,
                  textColor: open ? Colors.white : AppColors.grey400,
                  onTap: () => _onApproveTap(gate),
                );
              }),
            ),
          ] else if (isPending && widget.showApprovalButtons && widget.application != null &&
              widget.user.isBlacklisted) ...[
            // 블랙리스트 경고 배너 (거절만 허용)
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: ResponsiveHelper.spacing(context, 8),
                        vertical: ResponsiveHelper.spacing(context, 4)),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.block, color: AppColors.errorDark, size: 14),
                        SizedBox(width: ResponsiveHelper.spacing(context, 4)),
                        Text('이용 제한 근무자',
                            style: ResponsiveHelper.smallStyle(context,
                                color: AppColors.errorDark, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                  _buildRejectButton(),
                ],
              ),
            ),
          ],

          // 리뷰 버튼 (확정자 + businessId 있을 때)
          // [PH-WORKER-DETAIL] 리뷰 확인/작성은 navigation action — success green이 아닌 brand secondary
          if (isConfirmed && widget.application != null && widget.businessId != null) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              // [impl_58] 확인된 권한 거부면 작성 입구 대신 '권한 없음'(누르면 이유) — rules 가 저장을 거절하는 길로 보내지 않는다.
              child: _reviewPermission(listen: true) == PermissionCheck.denied
                  ? _buildDialogButton(
                      label: '리뷰 권한 없음',
                      icon: Icons.lock_outline,
                      bgColor: AppColors.grey100,
                      textColor: AppColors.grey500,
                      onTap: () => ToastHelper.showInfo(_noReviewPermissionText),
                    )
                  : _buildDialogButton(
                      label: _hasWrittenReview == true ? '리뷰 확인' : '리뷰 작성',
                      icon: _hasWrittenReview == true
                          ? Icons.rate_review
                          : Icons.rate_review_outlined,
                      bgColor: primary.withValues(alpha: 0.08),
                      textColor: primary,
                      onTap: _openReviewDialog,
                    ),
            ),
          ],

          // 확정자 액션 버튼
          if (isConfirmed && widget.application != null) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),

            // 장기 + 로딩 중
            if ((_auxLoading || _isLoading) && isLongTerm) ...[
              Expanded(
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.grey100,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.grey400),
                    ),
                  ),
                ),
              ),
            // 장기 + 출퇴근 있음: 고정근무 관리 — [DU541b R1] 관리 창 진입 = 중립(O003 같은 진입과 같다).
            ] else if (isLongTerm && _hasAttendance == true) ...[
              Expanded(
                child: _buildDialogButton(
                  label: '고정근무 관리',
                  icon: Icons.settings_outlined,
                  bgColor: Colors.transparent,
                  textColor: AppColors.textSecondary,
                  onTap: _openFixedWorkerManagement,
                ),
              ),
            // 장기 + 출퇴근 없음 OR 단기: 확정취소
            ] else ...[
              Expanded(
                child: Builder(
                  builder: (context) {
                    // _hasAttendance: Firestore에서 직접 확인한 출퇴근 기록 여부
                    //   → 호출처에서 attendanceStatus를 넘기지 않아도 항상 정확하게 동작
                    // attendanceStatus: 당일명단에서 넘기는 실시간 상태 (보조 가드)
                    // null = 로딩중 → 버튼 비활성 (플래시 방지)
                    final canCancel = _hasAttendance == false &&
                                      (widget.attendanceStatus == null ||
                                       widget.attendanceStatus == 'pending');
                    // [DU614b F199-WD-CANCEL-ENTRY] 사유창을 여는 진입 = 중립 행동 글/아이콘(textSecondary · 같은 줄 '고정근무 관리' 진입과 같은 꼴 · 판정199 :69).
                    //   빨강은 실제 손실 실행 순간(사유창 '확정 취소' errorDark 채움)에만. 활성 조건(canCancel) · 비활성 grey · 누를 때 동작 그대로.
                    return _buildDialogButton(
                      label: '확정취소',
                      icon: Icons.cancel_outlined,
                      bgColor: canCancel ? Colors.transparent : AppColors.grey100,
                      textColor: canCancel ? AppColors.textSecondary : AppColors.grey400,
                      onTap: () {
                        if (canCancel) {
                          _cancelConfirmation();
                        } else {
                          ToastHelper.showWarning('확정취소는 미출근 상태일 때만 가능합니다');
                        }
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        ],
      );
    for (final w in row.children) {
      if (w is Expanded) cells.add((child: w.child, flex: w.flex));
    }
    return AppModalFooter(
      child: LayoutBuilder(builder: (context, c) {
        final fits = TextLayout.fits(context, c.maxWidth, _footerCellMinWidth * cells.length);
        if (fits) return row;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 쌓을 때는 다음 행동이 위, 닫기가 맨 아래.
            for (var i = cells.length - 1; i >= 0; i--) ...[
              cells[i].child,
              if (i > 0) SizedBox(height: ResponsiveHelper.spacing(context, 8)),
            ],
          ],
        );
      }),
    );
  }

  /// 하단 버튼 한 칸이 아이콘+이름을 한 줄로 담는 폭(글자 배율 1.0, 논리 px).
  static const double _footerCellMinWidth = 88;

  /// 전화 걸기
  Future<void> _makePhoneCall(String? phone) async {
    if (phone == null || phone.isEmpty) {
      ToastHelper.showWarning('전화번호가 없습니다');
      return;
    }
    
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      if (mounted) ToastHelper.showInfo('전화: $phone');
    }
  }

  /// [ADMIN-DOC-REVIEW-UX] `승인` 탭 — 확정 조건을 모르거나 충족하지 않으면
  ///   서버를 부르지 않고 이유를 말한다.
  void _onApproveTap(ApprovalGate gate) {
    // 같은 checking/unknown 이라도 원인이 권한인지 서류인지에 따라 말이 다르다.
    final perm = _confirmPermission();
    switch (gate) {
      case ApprovalGate.ready:
        _updateStatus(AppStatus.confirmed);
      case ApprovalGate.denied:
        ToastHelper.showWarning(_noConfirmPermissionText);
      case ApprovalGate.checking:
        ToastHelper.showInfo(perm == PermissionCheck.unknown
            ? '확정 권한을 확인하고 있어요. 잠시만 기다려 주세요.'
            : '서류 상태를 확인하고 있어요. 잠시만 기다려 주세요.');
      case ApprovalGate.unknown:
        ToastHelper.showWarning(perm == PermissionCheck.error
            ? '확정 권한을 확인하지 못해 확정할 수 없어요. 잠시 후 다시 열어 주세요.'
            : '서류 상태를 불러오지 못해 확정할 수 없어요. 서류 확인에서 다시 불러와 주세요.');
      case ApprovalGate.blocked:
        ToastHelper.showWarning(
            _docReview?.approvalBlockText ?? '아직 확정할 수 없어요.');
    }
  }

  /// [ADMIN-REJECT-PERMISSION] 거절도 서버(callableRejectApplication)는 확정과
  ///   같은 권한(canManageTo)을 본다. 승인과 **같은 권한 상태**를 따른다 —
  ///   모름·조회 실패에서 실행 가능한 빨간 버튼으로 두지 않는다.
  Widget _buildRejectButton() {
    final perm = _confirmPermission(listen: true);
    final open = perm == PermissionCheck.allowed;
    // [UI-APPLICANTS-AND-INVITATIONS.2] 위험 행동은 채움·연한 빨강 바탕 없이 글자로 — 확정과 경쟁하지 않게.
    return _buildDialogButton(
      label: '거절',
      icon: Icons.cancel_outlined,
      bgColor: open ? Colors.transparent : AppColors.grey100,
      textColor: open ? AppColors.errorDark : AppColors.grey400,
      onTap: () => _onRejectTap(perm),
    );
  }

  void _onRejectTap(PermissionCheck perm) {
    switch (perm) {
      case PermissionCheck.allowed:
        _updateStatus(AppStatus.rejected);
      case PermissionCheck.denied:
        ToastHelper.showWarning(_noConfirmPermissionText);
      case PermissionCheck.unknown:
        ToastHelper.showInfo('확정 권한을 확인하고 있어요. 잠시만 기다려 주세요.');
      case PermissionCheck.error:
        ToastHelper.showWarning('확정 권한을 확인하지 못해 거절할 수 없어요. 잠시 후 다시 열어 주세요.');
    }
  }

  static const _noConfirmPermissionText =
      '확정·거절은 TO 관리 권한이 있는 관리자만 할 수 있어요.';

  /// 상태 업데이트
  Future<void> _updateStatus(String newStatus) async {
    if (widget.application == null || _isLoading) return;
    // [ADMIN-DOC-REVIEW-UX] 버튼이 열린 뒤 판정이 바뀌었을 수 있다(재조회 실패 등).
    if (newStatus == AppStatus.confirmed &&
        _approvalGate != ApprovalGate.ready) {
      _onApproveTap(_approvalGate);
      return;
    }
    // [ADMIN-APPROVAL-PERMISSION] 거절도 서버는 canManageTo 를 본다.
    if (newStatus == AppStatus.rejected &&
        _confirmPermission() != PermissionCheck.allowed) {
      _onRejectTap(_confirmPermission());
      return;
    }
    setState(() => _isLoading = true);

    final actionText = newStatus == AppStatus.confirmed ? '확정' : '거절';
    final adminUID = context.read<UserProvider>().currentUser?.uid;
    String? rejectReason;

    if (newStatus == AppStatus.confirmed) {
      // 승인
      final confirm = await DialogHelper.showConfirm(
        context,
        title: '지원자 확정',
        message: '${widget.user.name}님을 확정하시겠습니까?\n계약 대기 상태가 되고, 계약서를 보내 근무자가 동의해야 출근할 수 있어요.',
        confirmText: '확정',
        confirmColor: AppColors.brand,
        icon: Icons.check_circle,
        iconColor: AppColors.brand,
      );

      if (confirm != true || !mounted) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    } else {
      // 거절 - 사유 선택
      rejectReason = await DialogHelper.showRejectReasonPicker(
        context,
        title: '지원자 거절',
        targetName: widget.user.name,
      );

      if (rejectReason == null || !mounted) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
    }

    if (!mounted) return;
    try {
      await _firestoreService.updateApplicationStatus(
        applicationId: widget.application!.id,
        // [CONFIRM-BUSINESSID] 확정 CF 는 businessId 가 없으면 invalid-argument 로
        //   거절한다. 지원서 자신의 사업장을 보낸다(거절 경로는 이 값을 쓰지 않는다).
        businessId: widget.application!.businessId,
        status: newStatus,
        confirmedBy: newStatus == AppStatus.confirmed ? adminUID : null,
        rejectedBy: newStatus == AppStatus.rejected ? adminUID : null,
        message: rejectReason,
      );

      if (mounted) {
        if (newStatus == AppStatus.confirmed) {
          setState(() => _isLoading = false); // _createContractAndSign 진입 가드 해제
          // [PERM-CONTRACT-DEADEND-01] 승인(canManageTo)과 계약 생성(canManageContract) 분리.
          // 승인은 이미 서버에서 완료됐으므로 그대로 성공 처리하고,
          // 계약 권한이 없을 때만 후속 계약 flow를 열지 않는다.
          if (!_canManageContract()) {
            final callback = widget.onStatusChanged; // pop 전에 캡처
            Navigator.pop(context);
            ToastHelper.showSuccess('확정되었습니다. 계약서를 보내야 근무자가 동의할 수 있어요.');
            callback?.call();
            return;
          }
          await _createContractAndSign();
        } else {
          Navigator.pop(context);
          ToastHelper.showSuccess('$actionText 처리되었습니다');
          widget.onStatusChanged?.call();
        }
      }
    } catch (e) {
      debugPrint('❌ 상태 업데이트 실패: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        // [impl_58 · server_297] 겹침 확인 미완료(OVERLAP_CHECK_INCOMPLETE · 확정 0)는 다시 시도하라고 말한다.
        ToastHelper.showError(overlapCheckIncompleteMessageOf(e) ?? '$actionText 처리 중 오류가 발생했습니다');
      }
    }
  }

  Future<void> _createContractAndSign() async {
    if (_isLoading) return; // 이중 탭 방지
    final app = widget.application!;
    final businessId = widget.businessId ?? widget.toItem?.to.businessId;

    if (businessId == null) {
      final callback = widget.onStatusChanged; // pop 전에 캡처
      Navigator.pop(context);
      ToastHelper.showSuccess('확정되었습니다. 계약서를 보내야 근무자가 동의할 수 있어요.');
      callback?.call();
      return;
    }

    setState(() => _isLoading = true); // 첫 번째 await 이전 설정으로 이중 탭 방지

    // 템플릿 선택 먼저 — 취소하면 계약 생성 중단
    if (!mounted) return;
    final articles = await ContractTemplateSelectorDialog.show(
      context,
      businessId: businessId,
    );
    if (!mounted) return;
    if (articles == null) {
      // [UI-2] 이 함수는 확정이 서버에서 끝난 뒤에만 불린다. 템플릿만 닫았을 때
      //   상세를 그대로 두면 '대기중'·확정 버튼이 남아 다시 누르게 된다 —
      //   계약 권한 없음 경로와 같이 닫고 알리고 목록을 새로 읽는다.
      final callback = widget.onStatusChanged; // pop 전에 캡처
      Navigator.pop(context);
      ToastHelper.showSuccess('확정되었습니다. 계약서를 보내야 근무자가 동의할 수 있어요.');
      callback?.call();
      return;
    }

    try {
    // 해당 지원서에 맞는 WorkDetailData 찾기
    // toItem이 없을 때는 app.toId로 Firestore에서 직접 조회
    List<WorkDetailData> workDetails;
    if (widget.toItem != null) {
      workDetails = widget.toItem!.workDetails;
      if (workDetails.isEmpty) {
        workDetails = await _firestoreService.getWorkDetails(widget.toItem!.to.id);
      }
    } else {
      final toId = app.toId ?? '';
      workDetails = toId.isNotEmpty
          ? await _firestoreService.getWorkDetails(toId)
          : [];
    }

    if (!mounted) return;

    if (workDetails.isEmpty) {
      setState(() => _isLoading = false);
      ToastHelper.showError('업무 정보를 불러올 수 없습니다');
      return;
    }

    final workDetail = WorkDetailHelper.contractWorkDetailFor(app, workDetails);
    if (workDetail == null) {
      setState(() => _isLoading = false);
      ToastHelper.showError('이 근무의 업무를 공고에서 찾지 못해 계약서를 만들지 못했어요.');
      return;
    }

      final business = await _firestoreService.getBusinessById(businessId);
      if (!mounted) return;

      if (business == null) {
        final callback = widget.onStatusChanged; // pop 전에 캡처
        Navigator.pop(context);
        ToastHelper.showSuccess('확정되었습니다. 계약서를 보내야 근무자가 동의할 수 있어요.');
        callback?.call();
        return;
      }

      // [BUG-수정 M-1] updateApplicationStatus 완료 후 Firestore에는 computedWorkEndDate가
      // 저장되지만 로컬 app 객체는 구버전이라 workEndDate가 null일 수 있음.
      // 서버에서 최신 데이터를 재조회해 contractEnd 공백 발급 버그를 방지.
      final freshAppDoc = await FirebaseFirestore.instance
          .collection('applications')
          .doc(app.id)
          .get(const GetOptions(source: Source.server));
      // 승인 처리 직후 문서가 삭제된 경쟁 상태 방어 (catch(e)로 에러 토스트 처리됨)
      if (!freshAppDoc.exists) throw Exception('지원서를 찾을 수 없습니다');
      // [CRASH-GUARD] tryFromMap — 손상된 Firestore 문서에서 크래시 방지
      final freshApp = ApplicationModel.tryFromMap(freshAppDoc.data()!, freshAppDoc.id);
      if (freshApp == null) throw Exception('지원서 데이터가 손상되었습니다');

      // findOrCreateContract: 기존 번들 계약서가 있으면 슬롯 추가,
      // 없으면 신규 생성. 중복 방지 + 단기 번들링 처리.
      final contract = await ContractService().findOrCreateContract(
        application: freshApp,
        business: business,
        worker: widget.user,
        workDetail: workDetail,
        articles: articles,
      );

      if (!mounted) return;

      // 항상 서명 화면으로 이동 — 사업주가 계약서 내용 확인 후 직접 날인
      final nav = Navigator.of(context, rootNavigator: true);
      final callback = widget.onStatusChanged; // pop 전에 캡처
      Navigator.pop(context);
      callback?.call();
      await nav.push(MaterialPageRoute(
        builder: (_) => ContractSignScreen(contract: contract, role: 'employer'),
      ));
    } catch (e) {
      debugPrint('❌ 계약서 생성 실패: $e');
      if (mounted) {
        // 승인(status=confirmed)은 이미 완료됐지만 계약서 생성에 실패한 경우.
        // showSuccess가 아닌 showWarning으로 사용자에게 계약서 미생성 사실을 알림.
        final callback = widget.onStatusChanged; // pop 전에 캡처
        Navigator.pop(context);
        ToastHelper.showWarning('확정은 완료됐지만 계약서 생성에 실패했습니다.\n계약서 탭에서 다시 시도해주세요.');
        callback?.call();
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 신분증 열람 요청 다이얼로그
  // [PII-B4-R1] 근로자 상세의 개별 신분증 열람 요청 진입점 제거.
  //   이 화면의 신분증 섹션은 이제 세무 identity 확인 하나만 다룬다.
  //   근로자 승인 기반 수동 요청은 지원자 목록의 일괄 요청 경로에 남아 있다.

  /// 확정 취소 (CONFIRMED / CONTRACT_PENDING 모두 처리)
  Future<void> _cancelConfirmation() async {
    if (widget.application == null) return;
    // 확정자 기능 — 부가 조회(_hasAttendance 등)가 끝난 뒤에만(기존과 같다).
    if (_auxLoading || _isLoading) return; // 중복 실행 방어
    // [BUG-FIX 2026-07-16] _isLoading 설정 누락 — _showCancelReasonPicker() await 중 재진입 가능
    setState(() => _isLoading = true);

    final adminUID = context.read<UserProvider>().currentUser?.uid;

    final cancelReason = await _showCancelReasonPicker();
    if (cancelReason == null || !mounted) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    try {
      // [impl_59] 결과판 — 예전: 서비스가 사유 토스트를 띄운 뒤 false, 여기서 '확정 취소 처리 중 오류가 발생했습니다'가 그 사유를 덮었다.
      final cancel = await _firestoreService.cancelConfirmedApplicationWithResult(
        widget.application!.id,
        applyNoShowPenalty: false,
        canceledBy: adminUID,
        cancelReason: cancelReason,
      );

      if (mounted && cancel.success) {
        Navigator.pop(context, true);
        ToastHelper.showSuccess('확정이 취소되었습니다');
        widget.onStatusChanged?.call();
      } else if (mounted && !cancel.success) {
        // 결과 모름이면 부모 목록이 서버 상태를 다시 읽게 한다(취소됐을 수도 있다). 창은 그대로 둔다.
        if (cancel.outcomeUnknown) widget.onStatusChanged?.call();
        ToastHelper.showError(cancel.message);
      }
    } catch (e) {
      debugPrint('❌ 확정 취소 실패: $e');
      if (mounted) {
        ToastHelper.showError('확정 취소 중 오류가 발생했습니다');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// 확정취소 사유 선택 다이얼로그
  Future<String?> _showCancelReasonPicker() async {
    String? selectedReason;
    final customReasonController = TextEditingController();
    // ignore: unawaited_futures — result awaited below; controller disposed after

    final reasons = [
      '일정 변경',
      '인원 조정',
      '업무 취소',
      '근무자 요청',
      '기타',
    ];

    final result = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Container(
              width: double.maxFinite,
              constraints: const BoxConstraints(maxWidth: 400),
              child: SingleChildScrollView(
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 헤더
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                    // [DU611b R9] 머리 = 중립(판정138 :52) — 빨강 채움 → 창 바탕 그대로 + 아래 선(같은 창 하단 버튼 칸 윗선과 같은 border).
                    //   아이콘 · 닫기 = textSecondary · 제목 = textPrimary · 부제 = textSecondary(DU264 흰 머리 꼴) · 글 · 배치 · 닫기 동작 그대로.
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.cancel_outlined,
                          color: AppColors.textSecondary,
                          size: ResponsiveHelper.iconSize(context, 24),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '확정 취소',
                                style: ResponsiveHelper.subtitleStyle(context).copyWith(
                                  color: AppColors.textPrimary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${widget.user.name}님',
                                style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: Icon(
                            Icons.close,
                            color: AppColors.textSecondary,
                            size: ResponsiveHelper.iconSize(context, 24),
                          ),
                          onPressed: () {
                            FocusManager.instance.primaryFocus?.unfocus();
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  ),

                  // 사유 선택
                  Padding(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '취소 사유를 선택해주세요',
                          style: ResponsiveHelper.bodyStyle(context).copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        SizedBox(height: ResponsiveHelper.spacing(context, 12)),

                        // 사유 목록
                        ...reasons.map((reason) => Padding(
                          padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
                          child: InkWell(
                            onTap: () => setDialogState(() => selectedReason = reason),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 12),
                                vertical: ResponsiveHelper.spacing(context, 12),
                              ),
                              // [DU611b R9] 고른 사유 = brand 짝(brandSurface 면 · brand 선 · 라디오) — 고르기는 손실 실행이 아니다(판정138 :52 · C2).
                              //   안 고른 줄(grey100 · grey300 · grey400) · 누를 때 동작 · 기타 입력 그대로.
                              decoration: BoxDecoration(
                                color: selectedReason == reason
                                    ? AppColors.brandSurface
                                    : AppColors.grey100,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: selectedReason == reason
                                      ? AppColors.brand
                                      : AppColors.grey300,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    selectedReason == reason
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_off,
                                    color: selectedReason == reason
                                        ? AppColors.brand
                                        : AppColors.grey400,
                                    size: ResponsiveHelper.iconSize(context, 20),
                                  ),
                                  SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                                  Text(
                                    reason,
                                    style: ResponsiveHelper.bodyStyle(context),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )),

                        // 기타 사유 입력
                        if (selectedReason == '기타') ...[
                          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
                          TextField(
                            controller: customReasonController,
                            decoration: InputDecoration(
                              hintText: '취소 사유를 입력하세요',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: ResponsiveHelper.spacing(context, 12),
                                vertical: ResponsiveHelper.spacing(context, 12),
                              ),
                            ),
                            style: ResponsiveHelper.bodyStyle(context),
                            maxLines: 2,
                          ),
                        ],
                      ],
                    ),
                  ),

                  // 하단 버튼
                  Container(
                    padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 16)),
                    decoration: BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.border)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              FocusManager.instance.primaryFocus?.unfocus();
                              Navigator.pop(context);
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.grey600,
                              side: BorderSide(color: AppColors.grey300),
                              padding: EdgeInsets.symmetric(
                                vertical: ResponsiveHelper.spacing(context, 12),
                              ),
                            ),
                            child: const Text('취소'),
                          ),
                        ),
                        SizedBox(width: ResponsiveHelper.spacing(context, 12)),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: selectedReason != null
                                ? () {
                                    final reason = selectedReason == '기타' &&
                                            customReasonController.text.trim().isNotEmpty
                                        ? customReasonController.text.trim()
                                        : selectedReason;
                                    FocusManager.instance.primaryFocus?.unfocus();
                                    Navigator.pop(context, reason);
                                  }
                                : null,
                            // [DU611b R9 · PF8 #076] 마지막 '확정 취소' = 사유 반환 뒤 곧바로 취소 호출(다음 확인창 0) — 빨강 채움 유지 ·
                            //   대비만 error(흰 글 3.68) → errorDark(흰 글 6.57 · fixed_worker_management 해지 요청과 같은 교정). 비활성 조건 · 반환값 그대로.
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.errorDark,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(
                                vertical: ResponsiveHelper.spacing(context, 12),
                              ),
                            ),
                            // [DU614b F199-WD-CANCEL-WORDS] B(320·2.0)에서 '확정 취 / 소' 음절 분리 → 낱말 경계(공백)에서만 줄바꿈(TextLayout.keepWords · 판정199 :68).
                            //   글 크기 · 말줄임 · 한 줄 강제 · 단추 폭/배치 변경 0. 화면 읽기 이름 = 원문(semanticsLabel). 비활성 조건 · 반환값 · 채움 그대로.
                            child: Text(
                              TextLayout.keepWords('확정 취소'),
                              semanticsLabel: '확정 취소',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              ),
            ),
          );
        },
      ),
    );
    Future<void>.delayed(const Duration(milliseconds: 400)).then((_) {
      customReasonController.dispose();
    });
    return result;
  }

  /// 🆕 리뷰 작성 다이얼로그 열기
  Future<void> _openReviewDialog() async {
    if (_auxLoading || _isLoading) return;
    final app = widget.application;
    if (app == null || widget.businessId == null) return;
    // [impl_58] 실행 시점 재확인 — 권한이 확인되지 않으면 작성 폼을 열지 않는다(저장은 rules 가 거절한다).
    switch (_reviewPermission()) {
      case PermissionCheck.allowed:
        break;
      case PermissionCheck.denied:
        ToastHelper.showInfo(_noReviewPermissionText);
        return;
      case PermissionCheck.unknown:
        ToastHelper.showInfo('리뷰 권한을 확인하고 있어요. 잠시만 기다려 주세요.');
        return;
      case PermissionCheck.error:
        ToastHelper.showWarning('리뷰 권한을 확인하지 못했어요. 잠시 뒤 다시 시도해 주세요.');
        return;
    }

    final reviewer = context.read<UserProvider>().currentUser;
    if (reviewer == null) return;

    final now = DateTime.now();

    // 리뷰 기준 월: 단기는 실제 근무일, 장기는 직전 완료 달
    int reviewYear;
    int reviewMonth;
    if (app.isLongTermApplication) {
      // 장기: 당월 5일 이전이면 전달, 이후면 이번달
      if (now.month == 1) {
        reviewYear = now.year - 1;
        reviewMonth = 12;
      } else {
        reviewYear = now.year;
        reviewMonth = now.day < 5 ? now.month - 1 : now.month;
      }
    } else {
      reviewYear = app.workDate.year;
      reviewMonth = app.workDate.month;
    }

    final requestKey = ReviewRequestModel.generateKey(
      businessId: widget.businessId!,
      workerId: widget.user.uid,
      year: reviewYear,
      month: reviewMonth,
    );
    final reviewRequest =
        await MonthlyReviewService().getReviewRequest(requestKey);

    // review_request가 있으면 해당 년/월로 보정 (CF 기준이 정확)
    if (reviewRequest != null) {
      reviewYear = reviewRequest.reviewYear;
      reviewMonth = reviewRequest.reviewMonth;
    }

    if (!mounted) return;

    // [R7-RER.2 §5] 급여 마감을 되돌린 달은 작성 폼을 열지 않는다.
    //   요청을 못 읽은 경우(null)는 보류가 아니다 — 기존 동작 유지.
    if (reviewRequest?.isEligibilitySuspended == true) {
      ToastHelper.showInfo(MonthlyReviewService.eligibilitySuspendedMessage);
      return;
    }

    // 기작성 리뷰 확인: monthly_reviews 직접 조회 (review_requests.adminStatus 갱신 여부 무관)
    final reviewKey = MonthlyReviewModel.generateKeyForUser(
      businessId: widget.businessId!,
      targetUserId: widget.user.uid,
      year: reviewYear,
      month: reviewMonth,
    );
    final existingReview =
        await MonthlyReviewService().getReviewById(reviewKey);
    if (!mounted) return;

    if (existingReview != null) {
      await showMonthlyReviewViewDialog(context, review: existingReview);
      return;
    }

    // 실제 근무일 수: wageStatus confirmed/transferred 출근기록 건수
    // [P2-WF-ATT-01] canManageTo-only 경로: callableGetAdminAttendances → callableGetWorkerReviewSummary
    // raw attendance 없이 count aggregate만 반환 (GPS/체크인 시간 등 미포함)
    int workDaysInMonth = 0;
    // [REVIEW-WORKER-SUMMARY] 정시·지각 — 모르면 null(작성창 `확인 불가`). 조회 실패도 모름이다.
    int? onTimeDays;
    int? lateDays;
    try {
      final yearMonthStr =
          '$reviewYear-${reviewMonth.toString().padLeft(2, '0')}';
      final summaryCallable =
          FirebaseFunctions.instanceFor(region: 'asia-northeast3')
              .httpsCallable('callableGetWorkerReviewSummary',
                  options: HttpsCallableOptions(
                      timeout: const Duration(seconds: 30)));
      final cfResult =
          await summaryCallable.call<Map<String, dynamic>>({
        'businessId': widget.businessId!,
        'workerId': widget.user.uid,
        'yearMonth': yearMonthStr,
      });
      // 서버 v2 는 목록·알림과 같은 실근무 기준(노쇼·결근 제외)으로 센다.
      //   구 서버면 근무일만 오고 정시·지각은 모른다 — 근무일 전체를 정시로 추측하지 않는다.
      final summary = AttendanceModel.parseWorkerReviewSummary(cfResult.data);
      workDaysInMonth = summary.workDays;
      onTimeDays = summary.onTime;
      lateDays = summary.late;
    } catch (e) {
      debugPrint('❌ 근무일 조회 실패: $e');
    }
    if (!mounted) return;

    final result = await showMonthlyReviewDialog(
      context,
      reviewerId: reviewer.uid,
      reviewerName: reviewer.name,
      businessId: widget.businessId!,
      businessName: widget.toItem?.to.businessName ?? '',
      targetUserId: widget.user.uid,
      targetUserName: widget.user.name,
      reviewYear: reviewYear,
      reviewMonth: reviewMonth,
      workDaysInMonth: workDaysInMonth,
      normalAttendanceDays: onTimeDays,
      lateDays: lateDays,
      requestId: reviewRequest?.id,
    );

    if (result == true && mounted) {
      setState(() {
        _hasChanges = true;
        _hasWrittenReview = true;
      });
      widget.onStatusChanged?.call();
    }
  }

  /// 고정근무 관리 다이얼로그 열기
  void _openFixedWorkerManagement() {
    final businessId = widget.businessId ?? widget.application?.businessId;
    
    if (businessId == null) {
      ToastHelper.showError('사업장 정보를 찾을 수 없습니다');
      return;
    }

    // 루트 Navigator context를 팝 이전에 캡처 (pop 이후 context는 unmount됨)
    final rootNav = Navigator.of(context, rootNavigator: true);
    final onStatusChanged = widget.onStatusChanged;
    Navigator.pop(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: rootNav.context,
        barrierDismissible: false,
        builder: (context) => FixedWorkerManagementDialog(
          businessIds: [businessId],
          initialBusinessId: businessId,
          onChanged: () {
            onStatusChanged?.call();
          },
        ),
      );
    });
  }
}
/// [PII-B4-R1 §23] 세무 identity 대조 시트.
///
///   여기서 하는 판단은 하나다 — 소득신고에 쓸 등록 정보가 지금 제출된
///   신분증과 맞는가. 확정·공고·급여는 이 자리에 오지 않는다.
///
///   사람이 두 값을 비교했다는 기록이지 정부기관의 진위 인증이 아니다.
class _TaxIdentityReviewSheet extends StatelessWidget {
  const _TaxIdentityReviewSheet({
    required this.review,
    required this.imageUrl,
    required this.businessId,
    required this.targetUid,
  });

  final String businessId;
  final String targetUid;

  final TaxIdentityReview review;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final rows = <({String label, String value})>[
      (label: '등록 성명', value: review.officialName ?? '-'),
      if ((review.koreanName ?? '').isNotEmpty)
        (label: '한국 이름', value: review.koreanName!),
      (
        label: '생년월일',
        value: review.birthDate != null
            ? FormatHelper.formatDateDot(review.birthDate!)
            : '-'
      ),
    ];

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          ResponsiveHelper.spacing(context, 20),
          ResponsiveHelper.spacing(context, 20),
          ResponsiveHelper.spacing(context, 20),
          ResponsiveHelper.spacing(context, 12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('신분증 정보 확인',
                style: ResponsiveHelper.subtitleStyle(context)
                    .copyWith(fontWeight: FontWeight.bold)),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text('아래 등록 정보가 신분증과 같은지 확인해주세요.',
                style: ResponsiveHelper.smallStyle(context,
                    color: AppColors.grey500)),
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
              decoration: BoxDecoration(
                color: AppColors.grey50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.grey200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final r in rows) ...[
                    Row(
                      children: [
                        SizedBox(
                          width: ResponsiveHelper.spacing(context, 72),
                          child: Text(r.label,
                              style: ResponsiveHelper.tinyStyle(context,
                                  color: AppColors.grey500)),
                        ),
                        Expanded(
                          child: Text(r.value,
                              style: ResponsiveHelper.smallStyle(context,
                                  fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ),
                    if (r != rows.last)
                      SizedBox(height: ResponsiveHelper.spacing(context, 6)),
                  ],
                ],
              ),
            ),
            // [PII-B4-R1.4 §39·§48] 신고용 번호는 여기서만, 누를 때만 열린다.
            if (review.hasTaxIdentity) ...[
              SizedBox(height: ResponsiveHelper.spacing(context, 10)),
              _TaxIdentifierReveal(
                businessId: businessId,
                targetUid: targetUid,
                idDocumentVersion: review.idDocumentVersion,
                fingerprint: review.taxIdentityFingerprint,
                isForeign:
                    review.taxIdentifierType == 'FOREIGN_REGISTRATION_NUMBER',
              ),
            ],
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.38),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: InteractiveViewer(
                  // 신분증은 disk cache 금지 — memory-only 렌더링.
                  child: Image.network(imageUrl, fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                            height: 160,
                            alignment: Alignment.center,
                            color: AppColors.grey100,
                            child: Text('이미지를 불러오지 못했습니다',
                                style: ResponsiveHelper.smallStyle(context,
                                    color: AppColors.grey500)),
                          )),
                ),
              ),
            ),
            SizedBox(height: ResponsiveHelper.spacing(context, 16)),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, 'REUPLOAD_REQUIRED'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                      side: const BorderSide(color: AppColors.border),
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 13)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('정보 수정 요청'),
                  ),
                ),
                SizedBox(width: ResponsiveHelper.spacing(context, 10)),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, 'REVIEWED_OK'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.brand,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(
                          vertical: ResponsiveHelper.spacing(context, 13)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('확인 완료'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════
// [PII-B4-R1.4 §39·§48] 신고용 식별번호 — 누를 때만 열린다
//
//   조회 응답에는 번호가 실리지 않는다. 관리자가 신분증과 대조하겠다고
//   누른 그 순간에만 서버가 복호화해서 내려주고, 화면은 메모리로만
//   들고 있는다. 저장·복사·로그를 남기지 않는다.
// ══════════════════════════════════════════════════════════════
class _TaxIdentifierReveal extends StatefulWidget {
  const _TaxIdentifierReveal({
    required this.businessId,
    required this.targetUid,
    required this.idDocumentVersion,
    required this.fingerprint,
    required this.isForeign,
  });

  final String businessId;
  final String targetUid;
  final int idDocumentVersion;
  final String fingerprint;
  final bool isForeign;

  @override
  State<_TaxIdentifierReveal> createState() => _TaxIdentifierRevealState();
}

class _TaxIdentifierRevealState extends State<_TaxIdentifierReveal> {
  String? _value;
  bool _loading = false;

  String get _label => widget.isForeign ? '외국인등록번호' : '주민등록번호';

  Future<void> _reveal() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final v = await TaxIdentityReviewService.fullIdentifier(
        businessId: widget.businessId,
        targetUid: widget.targetUid,
        expectedIdDocumentVersion: widget.idDocumentVersion,
        expectedTaxIdentityFingerprint: widget.fingerprint,
      );
      if (!mounted) return;
      setState(() => _value = v);
    } catch (e) {
      // 번호는 로그에 남기지 않는다 — 실패 종류만 남긴다.
      debugPrint('❌ 세무 식별번호 열람 실패: ${e.runtimeType}');
      if (!mounted) return;
      ToastHelper.showError(
          e is FirebaseFunctionsException && e.code == 'aborted'
              ? (e.message ?? '등록 정보가 변경되었습니다. 다시 확인해주세요.')
              : '세무정보를 열지 못했습니다');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_value != null) {
      return Container(
        width: double.infinity,
        padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
        decoration: BoxDecoration(
          color: AppColors.grey50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.grey200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_label,
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey500)),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            // 선택·복사를 열지 않는다 — 대조에 필요한 것은 보는 것뿐이다.
            Text(_value!,
                style: ResponsiveHelper.bodyStyle(context)
                    .copyWith(fontWeight: FontWeight.w700, letterSpacing: 1)),
            SizedBox(height: ResponsiveHelper.spacing(context, 4)),
            Text('이 값은 저장되지 않으며 화면을 닫으면 사라집니다.',
                style: ResponsiveHelper.tinyStyle(context,
                    color: AppColors.grey400)),
          ],
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: _loading ? null : _reveal,
      icon: _loading
          ? const SizedBox(
              width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.visibility_outlined, size: 16),
      label: Text(_loading ? '여는 중…' : '$_label 확인'),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(double.infinity, 40),
        foregroundColor: AppColors.brand,
      ),
    );
  }
}
