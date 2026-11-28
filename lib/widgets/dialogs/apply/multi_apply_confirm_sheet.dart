// lib/widgets/dialogs/apply/multi_apply_confirm_sheet.dart
//
// JPS 전용 단기공고 Multi-Apply Confirm Sheet
//
// ─ 책임 ─────────────────────────────────────────────────────────────────────
//   Selection Owner    : JobPostingScreen (caller — 날짜·업무 선택)
//   Confirmation Owner : THIS WIDGET (conflict check + consent + submit + result)
//   Submit Owner       : ApplicationFirestore / callableApplyToTO (FirestoreService 위임)
//
// ─ 이 Sheet에 포함 ──────────────────────────────────────────────────────────
//   • 선택 item별 conflict / already-applied 분류
//   • documentAccessConsent 표시 (documentAccessConsentVersion: "2026-09-12-v2")
//   • N개 업무 일괄 지원 (applyToTOWithWorkType × N)
//   • 부분 실패 결과 표시
//
// ─ 이 Sheet에서 제외 ─────────────────────────────────────────────────────────
//   • 지원 취소 / 확정 취소 — 기존 지원 관리 UI 담당
//   • 날짜 선택 — JPS selection UI 담당 (items는 날짜가 이미 확정된 상태)
//   • 장기공고 — LongTermApplySheet 담당
//   • UserTOCard 경로 — ApplyWorkDialog → ApplyConfirmDialog 유지
//
// ─ Conflict 정책 ─────────────────────────────────────────────────────────────
//   BLOCKED  : 기존 CONFIRMED / CONTRACT_PENDING과 시간 겹침 → 지원 불가, submit 대상 제외
//   WARNING  : 이전 근무 종료 직후 (딱 붙는 경우) → 경고 표시, 지원 허용
//   AVAILABLE: 충돌 없음
//   ALREADY_APPLIED: 동일 (toId, slotId, workType)에 PENDING/CONTRACT_PENDING/CONFIRMED 존재
//                    → 표시만, submit 대상 제외. 중복지원 서버 gate도 유지됨.
//
// ─ PENDING↔PENDING 허용 ──────────────────────────────────────────────────────
//   선택한 PENDING 후보끼리 시간이 겹쳐도 BLOCK하지 않는다. (Product Policy)
//   ScheduleConflictService는 CONFIRMED/CONTRACT_PENDING만 조회한다.
//
// ─ Partial Failure ────────────────────────────────────────────────────────────
//   All success  → Toast + sheet close
//   Partial fail → sheet 내 결과 표시 (성공/실패 항목 구분)
//   All fail     → sheet 내 결과 표시

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/core/to_model.dart';
import '../../../models/core/slot_model.dart';
import '../../../models/core/work_detail_model.dart';
import '../../../models/core/application_model.dart';
import '../../../services/firestore_service.dart';
import '../../../services/schedule_conflict_service.dart';
import '../../../providers/user_provider.dart';
import '../../../models/core/business_model.dart' show AttendanceRules;
import '../../../utils/attendance_policy_disclosure.dart';
import '../../../utils/format_helper.dart';
import '../../../utils/responsive_helper.dart';
import '../../../utils/toast_helper.dart';
import '../../../theme/app_colors.dart';
import '../../../utils/text_layout.dart';
import '../../../utils/expected_daily_wage.dart';
import '../../../widgets/common/common_widgets.dart';
import 'application_relation.dart';
import 'document_access_consent.dart';

// ─ 결과 타입 ──────────────────────────────────────────────────────────────────

class MultiApplyResult {
  final bool hasChanges;
  final int appliedCount;

  /// [R7-PAYROLL-POLICY.4C] 보는 동안 기준이 바뀌어 막힌 건이 있었는가.
  ///   이미 성공한 건은 그대로다 — 전체를 실패로 말하지 않는다.
  final bool policyChanged;
  const MultiApplyResult({
    required this.hasChanges,
    required this.appliedCount,
    this.policyChanged = false,
  });
}

// ─ 내부 item 분류 ─────────────────────────────────────────────────────────────

enum _ItemStatus {
  checking,       // 충돌 체크 중
  available,      // 지원 가능 (충돌 없음)
  warning,        // 경고 (시간 붙음 등) — 지원 허용
  blocked,        // CONFIRMED/CONTRACT_PENDING 시간 겹침 — 지원 불가
  alreadyApplied, // 이미 지원/확정 중 — 중복지원 서버 게이트도 유지됨
}

class _ItemMeta {
  final ({SlotModel? slot, WorkDetailModel work}) item;
  _ItemStatus status = _ItemStatus.checking;
  ConflictInfo conflictInfo = ConflictInfo.ok;
  String? applyError; // null = 아직 미제출 또는 성공, non-null = 실패/미확인 메시지
  bool submitted = false;

  /// [R8-P3A.1] 서버가 준 결과의 성격. null = 아직 제출 전.
  ///   실패와 "결과를 모름"을 같은 칸에 넣지 않기 위해 따로 둔다.
  ApplyOutcome? outcome;

  /// [R7-P4.4E.7A] 제출 전 이미 존재하던 관계. 초대와 지원을 구별해 말하기
  ///   위해 둔다 — 초대는 수락·거절로 답하는 것이지 다시 지원하는 게 아니다.
  WorkApplyRelation relation = WorkApplyRelation.none;

  bool get applyOk => outcome == ApplyOutcome.success ||
      outcome == ApplyOutcome.alreadyApplied;
  bool get applyUnknown => outcome == ApplyOutcome.unknown;

  _ItemMeta({required this.item});

  /// submit 대상 여부 (alreadyApplied / blocked 제외)
  bool get isSubmittable =>
      status == _ItemStatus.available || status == _ItemStatus.warning;
}

// ─ Widget ────────────────────────────────────────────────────────────────────

class MultiApplyConfirmSheet extends StatefulWidget {
  final List<({SlotModel? slot, WorkDetailModel work})> items;
  final TOModel to;
  final List<ApplicationModel> myApplications;

  /// [R7-PAYROLL-POLICY.4C] 공고 상세가 보여준 근태·급여 기준(새 읽기 없음).
  final AttendanceRules? policyRules;

  const MultiApplyConfirmSheet({
    super.key,
    required this.items,
    required this.to,
    required this.myApplications,
    this.policyRules,
  });

  @override
  State<MultiApplyConfirmSheet> createState() => _MultiApplyConfirmSheetState();
}

class _MultiApplyConfirmSheetState extends State<MultiApplyConfirmSheet> {
  // [L19 · 판정289 탭 분석 §3-6] 시트 한 번 열림 = 내 약속 목록 조회 1회.
  //   예전에는 근무 날짜마다 `checkConflictsForWorkDetails` 가 같은 목록(확정 200)을 따로 읽었다(D회).
  //   이제 첫 날짜의 조회 Future 를 나머지 날짜가 함께 받는다 — 시트가 열릴 때 1회라는 신선도는 그대로이고,
  //   날짜별 겹침 판정·실패 시 '확인하지 못함' 표시는 각 날짜에서 그대로 한다.
  Future<List<ApplicationModel>>? _commitmentsOnce;
  late final ScheduleConflictService _conflictService = ScheduleConflictService(
    commitmentsSource: () =>
        _commitmentsOnce ??= ScheduleConflictService.fetchMyCommitments(),
  );
  final _firestoreService = FirestoreService();

  late List<_ItemMeta> _metas;
  bool _isCheckingConflicts = true;
  bool _isSubmitting = false;
  bool _submitDone = false;

  @override
  void initState() {
    super.initState();
    _metas = widget.items.map((item) => _ItemMeta(item: item)).toList();
    _initAlreadyApplied(); // conflict check 전 선제 분류
    _loadConflicts();
  }

  // ─ 초기화 ────────────────────────────────────────────────────────────────

  /// myApplications 기반 already-applied 선분류
  ///
  /// [R7-P4.4E.7A] 여기 있던 자체 matcher 를 지웠다. `selectedWorkType` 하나로
  ///   비교해서, 같은 업무명이 시간대만 다른 **별개 근무**를 하나로 뭉쳤다 —
  ///   하나에 지원한 뒤 다른 하나를 고르면 `alreadyApplied` 로 분류돼
  ///   **제출에서 조용히 빠졌다**. 서버는 (uid, toId, slotId, wdId) 로 보고,
  ///   그 함수 주석이 workType 단독 매칭을 이미 경고해 뒀다.
  ///   이제 공고 상세와 **같은** `ApplicationRelationResolver` 를 쓴다.
  void _initAlreadyApplied() {
    for (final meta in _metas) {
      final relation = ApplicationRelationResolver.resolve(
        myApplications: widget.myApplications,
        toId: widget.to.id,
        slotId: meta.item.slot?.id,
        work: meta.item.work,
      );
      meta.relation = relation;
      if (relation.blocksNewApplication) {
        meta.status = _ItemStatus.alreadyApplied;
      }
    }
  }

  // ─ Conflict 체크 ─────────────────────────────────────────────────────────

  Future<void> _loadConflicts() async {
    // alreadyApplied 항목은 conflict check 불필요
    final toCheck = _metas.where((m) => m.status != _ItemStatus.alreadyApplied).toList();

    if (toCheck.isEmpty) {
      if (mounted) setState(() => _isCheckingConflicts = false);
      return;
    }

    try {
      // 날짜별로 grouping → 같은 날짜는 CF 1회 호출로 처리 (비용 절감)
      // Flex TO: slot.date 사용 / Contract TO: to.date 사용
      final byDate = <DateTime, List<_ItemMeta>>{};
      for (final meta in toCheck) {
        final raw = meta.item.slot?.date ?? widget.to.date;
        // [SIM-ADJ-1] 저장된 근무일(KST 자정 instant)의 **KST 달력일**로 묶고 묻는다.
        //   예전 `DateTime(raw.year, raw.month, raw.day)` 는 기기 local 성분이라
        //   GMT 기기에서 10/20 지원을 10/19 확정 근무와 비교했다(겹침을 놓치고,
        //   없는 겹침으로 막았다). 그 날의 KST 자정 instant 로 넘긴다.
        final key =
            FormatHelper.kstMidnightOfKstDay(FormatHelper.toKstDate(raw));
        byDate.putIfAbsent(key, () => []).add(meta);
      }

      // 날짜별 conflict check 병렬 실행
      await Future.wait(byDate.entries.map((entry) async {
        final date = entry.key;
        final metas = entry.value;
        final works = metas.map((m) => m.item.work).toList();
        try {
          final conflictMap = await _conflictService.checkConflictsForWorkDetails(
            workDate: date,
            workDetails: works,
          );
          if (!mounted) return;
          setState(() {
            for (final meta in metas) {
              final info = conflictMap[meta.item.work.id] ?? ConflictInfo.ok;
              meta.conflictInfo = info;
              switch (info.level) {
                case ConflictLevel.blocked:
                  meta.status = _ItemStatus.blocked;
                case ConflictLevel.warning:
                  meta.status = _ItemStatus.warning;
                case ConflictLevel.ok:
                  meta.status = _ItemStatus.available;
              }
            }
          });
        } catch (_) {
          // [R7-APPLICATION-LIFECYCLE.1C] 읽기 실패를 `available` 로 바꾸지
          //   않는다. 예전에는 조용히 `지원 가능` 이 됐고, 사용자는 겹침을
          //   모른 채 제출해 서버 거부를 받았다. 제출 자체는 막지 않는다
          //   (서버가 최종 판정한다) — 다만 **확인하지 못했다는 사실**을
          //   화면이 말한다.
          if (mounted) {
            setState(() {
              for (final meta in metas) {
                if (meta.status == _ItemStatus.checking) {
                  meta.status = _ItemStatus.warning;
                  meta.conflictInfo = const ConflictInfo(
                    level: ConflictLevel.warning,
                    message: '확정 일정과 겹치는지 확인할 수 없어요. 지원 후 내 지원 내역에서 확인해주세요.',
                  );
                }
              }
            });
          }
        }
      }));
    } finally {
      if (mounted) setState(() => _isCheckingConflicts = false);
    }
  }

  // ─ 제출 ──────────────────────────────────────────────────────────────────

  List<_ItemMeta> get _submitTargets =>
      _metas.where((m) => m.isSubmittable).toList();

  /// [R8-P3A] 동시에 보내는 지원 요청 수 상한.
  ///
  ///   DEV 실측에서 4까지는 실패·재시도 없이 선형에 가깝게 빨라졌다.
  ///   그 이상은 관리자 알림 쓰기까지 같이 몰리므로 여기서 묶는다.
  static const int _applyConcurrency = 4;

  /// 한 항목을 서버에 보낸다. 성공 여부는 서버 응답으로만 정한다(§50).
  Future<ApplyResult> _applyOne(String uid, _ItemMeta meta) {
    final work = meta.item.work;
    final slot = meta.item.slot;
    // Flex: slot.date / Contract: to.date (AWD의 workDate: date ?? to.date 와 동일)
    final workDate = slot?.date ?? widget.to.date;
    return _firestoreService.applyToTOWithWorkType(
      // [R7-PAYROLL-POLICY.4C] 공고 상세가 보여준 기준의 토큰.
      expectedAttendancePolicy:
          attendancePolicyFingerprint(widget.policyRules),
      uid: uid,
      businessId: widget.to.businessId,
      businessName: widget.to.businessName,
      toTitle: widget.to.title,
      workDate: workDate,
      selectedWorkType: work.workType,
      workDetailId: work.id,
      wage: work.wage,
      wageType: work.wageType,
      workTypeIcon: work.workTypeIcon,
      workTypeColor: work.workTypeColor,
      workTypeBackgroundColor: work.workTypeBackgroundColor,
      startTime: work.startTime,
      endTime: work.endTime,
      workEndDate: widget.to.endDate,
      workDays: widget.to.workDays,
      type: widget.to.type,
      toId: widget.to.id,
      slotId: slot?.id,
    );
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    final targets = _submitTargets;
    if (targets.isEmpty) return;

    final user = context.read<UserProvider>().currentUser;
    if (user == null) return;

    setState(() => _isSubmitting = true);

    int successCount = 0;

    // [R8-P3A] 선택한 업무들을 한 번에 하나씩 기다리지 않는다.
    //
    //   지원 하나는 DEV 실측 700ms 안팎이다. 7건을 고르면 그대로 7번을
    //   줄 세워 기다렸다 — 7.5초. 그런데 각 지원은 서로 독립이다.
    //   다음 호출의 payload가 앞 호출의 결과를 쓰지 않고, 정원·마감·중복은
    //   전부 서버 트랜잭션이 그 순간에 다시 본다. 클라이언트 순서가
    //   정답을 만들지 않는다.
    //
    //   그렇다고 전부 한꺼번에 던지지는 않는다. 지원마다 같은 공고 문서의
    //   totalPending을 올리고 관리자 알림도 함께 쓴다. 동시 요청 수를
    //   묶어두면 그 부담이 선형으로 커지지 않는다.
    //   (DEV 실측: 7건 기준 1→7544ms, 2→2888, 3→2147, 4→1553, 모두 실패 0)
    var policyChangedCount = 0;
    var nextIndex = 0;
    Future<void> worker() async {
      for (;;) {
        final i = nextIndex++;
        if (i >= targets.length) return;
        final meta = targets[i];
        ApplyResult result;
        try {
          result = await _applyOne(user.uid, meta);
        } catch (e) {
          // 서비스가 결과로 돌려주지 못한 예외 — 보냈는지조차 알 수 없다.
          result = ApplyResult.unknown(_friendlyError(e));
        }
        if (result.isNewlyApplied) successCount++;
        // [R7-PAYROLL-POLICY.4C] 기준 변경은 실패와 다른 상태다. 이 건만
        //   막히고 **이미 성공한 건은 유지된다** — 자동 재지원도 없다.
        if (result.isPolicyChanged) policyChangedCount++;
        // [§21] 시트를 닫아도 이미 보낸 지원은 취소되지 않는다.
        //   화면 표시만 건너뛰고 나머지 항목도 끝까지 보낸다 —
        //   중간에 멈추면 사용자가 볼 수 없는 반쪽 상태가 남는다.
        if (!mounted) {
          meta.outcome = result.outcome;
          continue;
        }
        setState(() {
          meta.submitted = true;
          meta.outcome = result.outcome;
          meta.applyError = result.isApplied ? null : result.message;
        });
      }
    }

    // [§40·§42] 하나가 실패해도 나머지를 취소하지 않는다 — 각 결과를 따로 담는다.
    await Future.wait(List.generate(
      targets.length < _applyConcurrency ? targets.length : _applyConcurrency,
      (_) => worker(),
    ));

    // [R8-P3A.1] 결과를 못 들은 건만 canonical 상태로 되묻는다.
    //
    //   정상 성공 경로에는 읽기를 한 번도 더하지 않는다. 모르는 건이 있을
    //   때만, 그것도 항목마다가 아니라 내 지원 목록을 **한 번** 새로 읽어
    //   전부 대조한다. 문서 id 를 계산해 맞춰보지 않는다 — 서버가 초대·제안이
    //   만든 기존 문서로 수렴시킬 수 있어 클라이언트 계산과 다를 수 있다.
    final unknowns = targets.where((m) => m.applyUnknown).toList();
    if (unknowns.isNotEmpty) {
      try {
        final mine = await _firestoreService.getMyApplicationsForTOFresh(widget.to.id);
        for (final meta in unknowns) {
          final landed = _firestoreService.hasLandedApplication(
            mine,
            toId: widget.to.id,
            slotId: meta.item.slot?.id,
            workType: meta.item.work.workType,
          );
          if (!landed) continue; // 아직 모른다 — 실패로 바꾸지 않는다
          meta.outcome = ApplyOutcome.success;
          meta.applyError = null;
          successCount++;
        }
      } catch (e) {
        debugPrint('⚠️ 지원 결과 재확인 실패: $e'); // UNKNOWN 그대로 둔다
      }
    }

    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _submitDone = true;
    });

    // [R8-P3A.1] 전부 지원된 상태일 때만 닫는다.
    //   '이미 지원중'도 사용자 관점에서는 지원된 것이라 남겨둘 이유가 없다.
    //   반대로 결과를 모르는 건이 하나라도 있으면 닫지 않는다 — 시트에서
    //   무엇이 미확인인지 그대로 보여준다.
    if (targets.every((m) => m.applyOk)) {
      final msg = successCount == 0
          ? '이미 지원한 업무예요'
          : (targets.length == 1
              ? '지원이 완료되었습니다'
              : '${targets.length}개 업무에 지원했어요.');
      ToastHelper.showSuccess(msg);
      if (mounted) {
        Navigator.pop(
          context,
          MultiApplyResult(
              hasChanges: successCount > 0,
              appliedCount: successCount,
              policyChanged: policyChangedCount > 0),
        );
      }
    }
    // Partial / 미확인 / 실패 → sheet 내 결과 표시 (_submitDone == true)
  }

  String _friendlyError(Object e) {
    final msg = e.toString().toLowerCase();
    if (msg.contains('already') || msg.contains('duplicate') || msg.contains('중복')) {
      return '이미 지원한 업무입니다';
    }
    if (msg.contains('capacity') || msg.contains('정원')) return '정원이 마감되었습니다';
    if (msg.contains('closed') || msg.contains('마감')) return '모집이 마감되었습니다';
    if (msg.contains('conflict') || msg.contains('시간 충돌') || msg.contains('schedule')) {
      return '확정된 근무와 시간이 겹칩니다';
    }
    if (msg.contains('offline') || msg.contains('network') || msg.contains('인터넷')) {
      return '인터넷 연결을 확인해주세요';
    }
    return '지원에 실패했습니다';
  }

  // ─ Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // [R7-P4.4E.6C] 하단 여백은 `DialogHelper.showSheet` 가 **이미** 넣는다
    //   (`useSafeArea: true` + `Padding(bottom: sheetBottomInset)`).
    //   여기서 `viewPadding.bottom` 을 또 읽어 더하고 있었다 — 같은 inset 을
    //   두 번 센 것이다. 공용 `sheetBottomInset` 은 건드리지 않고 이쪽의
    //   중복만 걷는다.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [R7-P4.4E.6C] 본문 **하나**만 스크롤한다.
          //
          //   예전에는 업무 목록만 `ConstrainedBox(0.42×화면높이)` 안에서
          //   따로 스크롤했고, 동의 안내와 헤더·CTA 는 전부 intrinsic 이었다.
          //   root `Column(mainAxisSize: min)` 에 `Flexible` 이 하나도 없어
          //   합이 시트 높이를 넘는 순간 그대로 잘렸다 —
          //   실측 360×800 3건 **87px**, 320×640 3건 **290px**, 5건 145px.
          //   게다가 본문 scroll owner 가 없어 **스크롤로 볼 수도 없었다**.
          //
          //   `Flexible` 이라 내용이 적으면 시트는 내용 크기대로 작게 뜨고
          //   (1건: 시트 701.9 < 800 — 고정 높이로 키우지 않는다),
          //   많아지면 이 안에서 스크롤된다. 중첩 스크롤도 없다.
          //
          // [DU508 r3 · 후속120 §2-1] 머리(제목 · '나머지 N개는 …' 안내)도 이 스크롤 **안**에 둔다.
          //   머리가 고정 칸에 남아 있으면 B(320 · 글자 2.0)에서 제목 2줄 · 안내 3줄이 세로를 먼저 가져가
          //   본문 스크롤 칸이 40px 남짓만 남았다 — 날짜 행이 '11월 23' 까지만 보였다(r2 TA B BLOCK 원PNG).
          //   고정은 아래 하단(지원 안내 · 지원하기 · 취소 / 결과)뿐이다. 처음 열면 스크롤 위치 0 이라
          //   제목이 맨 위에 그대로 보이고, 내용이 적으면 시트가 작아지는 것도 그대로다(Flexible · min).
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(context),
                  SizedBox(height: ResponsiveHelper.spacing(context, 14)),

                  ..._metas.map((meta) => _buildItemCard(context, meta)),

                  // 서류 접근 사전동의 — submit 전에만 표시 (result 후 불필요)
                  if (!_submitDone) ...[
                    SizedBox(height: ResponsiveHelper.spacing(context, 12)),
                    _buildConsent(context),
                  ],
                ],
              ),
            ),
          ),

          SizedBox(height: ResponsiveHelper.spacing(context, 16)),

          _submitDone ? _buildResult(context) : _buildCTA(context),
        ],
      ),
    );
  }

  // ─ 헤더 ──────────────────────────────────────────────────────────────────

  Widget _buildHeader(BuildContext context) {
    if (_submitDone) {
      final successCount = _submitTargets.where((m) => m.applyError == null).length;
      final String title;
      if (_submitTargets.isEmpty) {
        title = '지원할 업무가 없었어요';
      } else if (successCount == _submitTargets.length) {
        title = '지원 완료';
      } else if (successCount == 0) {
        title = '지원하지 못했어요';
      } else {
        title = '일부 지원이 완료됐어요';
      }
      return Text(
        title,
        style: ResponsiveHelper.subtitleStyle(context)
            .copyWith(fontWeight: FontWeight.bold),
      );
    }

    final totalCount = widget.items.length;
    final submitCount =
        _isCheckingConflicts ? totalCount : _submitTargets.length;
    final blockedCount = totalCount - submitCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          blockedCount > 0
              ? '$totalCount개 중 $submitCount개 업무에 지원할 수 있어요'
              : '$totalCount개 업무에 지원합니다',
          style: ResponsiveHelper.subtitleStyle(context)
              .copyWith(fontWeight: FontWeight.bold),
        ),
        // [F293-WAGE-01] 실제로 보낼 근무 집합의 근무별 예상 금액 합(근무별 반올림 뒤 합산) — '하루' 라고 부르지 않는다.
        //   하나라도 금액이 없으면(일급 · 확인 필요) 합계를 만들지 않는다.
        if (!_isCheckingConflicts)
          ...() {
            final ests = _submitTargets.map((m) => ExpectedDailyWage.forWorkDetail(m.item.work)).toList();
            final total = ExpectedWageText.selectedTotal(ests);
            final anyEstimate = ests.any((e) => e.isEstimate);
            return <Widget>[
              if (total != null) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  TextLayout.keepWords('$total · ${ExpectedWageText.shortNote}'),
                  semanticsLabel: '$total ${ExpectedWageText.shortNote}',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
                ),
              ],
              // 하루 예상 금액이 있으면 계산 범위 고지(정본 문구 그대로).
              if (anyEstimate) ...[
                SizedBox(height: ResponsiveHelper.spacing(context, 4)),
                Text(
                  ExpectedWageText.disclosure,
                  style: ResponsiveHelper.tinyStyle(context).copyWith(color: AppColors.textTertiary),
                ),
              ],
            ];
          }(),
        if (blockedCount > 0 && !_isCheckingConflicts) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 4)),
          Text(
            // [DU508] B(320 · 2.0)에서 '겹쳐 / 요.'처럼 음절 안에서 끊겼다 — 낱말 조판(원문 semantics).
            TextLayout.keepWords('나머지 $blockedCount개는 이미 지원 중이거나 확정된 근무와 겹쳐요.'),
            semanticsLabel: '나머지 $blockedCount개는 이미 지원 중이거나 확정된 근무와 겹쳐요.',
            // [DU471] 보조 안내 grey500(2.68) → textTertiary.
            style: ResponsiveHelper.tinyStyle(context)
                .copyWith(color: AppColors.textTertiary),
          ),
        ],
      ],
    );
  }

  // ─ 업무 카드 ─────────────────────────────────────────────────────────────

  Widget _buildItemCard(BuildContext context, _ItemMeta meta) {
    final work = meta.item.work;
    final slot = meta.item.slot;
    final weekDays = ['월', '화', '수', '목', '금', '토', '일'];
    String dateStr = '';
    if (slot != null) {
      // [SIM-B] 저장된 근무일은 KST 자정 instant 다 — 기기 local 성분으로 읽으면
      //   GMT 기기에서 10/20 근무가 10/19(월)이 된다. KST 달력일로 말한다.
      //   보내는 값(_applyOne 의 workDate)은 instant 그대로라 바꾸지 않는다.
      final d = FormatHelper.toKstDate(slot.date);
      dateStr = '${d.month}월 ${d.day}일(${weekDays[d.weekday - 1]}) · ';
    }

    final isDisabled = meta.status == _ItemStatus.blocked ||
        meta.status == _ItemStatus.alreadyApplied;
    final isChecking =
        !_submitDone && (_isCheckingConflicts || meta.status == _ItemStatus.checking);

    // 색상 / 배지 결정
    late Color borderColor;
    late Color bgColor;
    String? badgeText;
    Color? badgeColor;
    String? subMsg;
    Color? subColor;

    if (_submitDone) {
      // ── 제출 후 상태 ──────────────────────────────────────────────────────
      if (isDisabled) {
        borderColor = AppColors.grey200;
        bgColor = AppColors.grey50;
      } else if (meta.applyOk) {
        borderColor = AppColors.success.withValues(alpha: 0.5);
        bgColor = AppColors.success.withValues(alpha: 0.04);
        badgeText = meta.outcome == ApplyOutcome.alreadyApplied
            ? '이미 지원중'
            : '지원 완료';
        badgeColor = AppColors.success;
      } else if (meta.applyUnknown) {
        // [R8-P3A.1] 모르는 것을 실패라고 말하지 않는다.
        borderColor = AppColors.warning.withValues(alpha: 0.45);
        bgColor = AppColors.warning.withValues(alpha: 0.05);
        badgeText = '확인 필요';
        badgeColor = AppColors.warning;
        subMsg = '${meta.applyError} 내 지원 목록에서 확인해주세요.';
        subColor = AppColors.warningDark;
      } else {
        borderColor = AppColors.error.withValues(alpha: 0.4);
        bgColor = AppColors.error.withValues(alpha: 0.04);
        badgeText = '지원 불가';
        badgeColor = AppColors.error;
        subMsg = meta.applyError;
        subColor = AppColors.error;
      }
    } else {
      // ── 제출 전 상태 ──────────────────────────────────────────────────────
      switch (meta.status) {
        case _ItemStatus.checking:
          borderColor = AppColors.grey200;
          bgColor = AppColors.grey50;
        case _ItemStatus.available:
          borderColor = AppColors.grey200;
          bgColor = AppColors.grey50;
        case _ItemStatus.warning:
          borderColor = AppColors.warning.withValues(alpha: 0.4);
          bgColor = AppColors.warning.withValues(alpha: 0.05);
          badgeText = '주의';
          badgeColor = AppColors.warning;
          subMsg = meta.conflictInfo.message ??
              '이전 근무 종료 직후입니다. 이동 시간을 고려하세요.';
          subColor = AppColors.warningDark;
        case _ItemStatus.blocked:
          borderColor = AppColors.error.withValues(alpha: 0.3);
          bgColor = AppColors.error.withValues(alpha: 0.04);
          badgeText = '지원 불가';
          badgeColor = AppColors.error;
          subMsg = '이미 확정된 근무와 시간이 겹쳐 지원할 수 없어요.';
          subColor = AppColors.error;
        case _ItemStatus.alreadyApplied:
          borderColor = AppColors.grey300;
          bgColor = AppColors.grey50;
          // [R7-P4.4E.7A] 초대와 지원을 같은 말로 덮지 않는다 — 서버도
          //   초대에는 "내 지원 내역에서 초대를 확인해주세요" 를 준다.
          if (meta.relation.isInvitation) {
            badgeText = '초대 확인';
            subMsg = '초대받은 근무예요. 내 지원 내역에서 수락·거절해주세요.';
            subColor = AppColors.grey600;
          } else {
            badgeText = '이미 지원중';
          }
          badgeColor = AppColors.grey500;
      }
    }

    // [DU508 r3 · 후속120 §2-1 · F120-2] 날짜 · 업무명 줄 — 글자 모양 · 상태별 색은 그대로다.
    final rowStyle = ResponsiveHelper.bodyStyle(context).copyWith(
      fontWeight: FontWeight.bold,
      color: isDisabled ? AppColors.grey400 : AppColors.textPrimary,
    );
    // [DU508 r3] 업무명 — 띄어쓰기가 없고 5자 이하인 이름은 원문 그대로 둔다: 아래 Wrap 이 이름을 **통째로**
    //   다음 줄로 옮기고, B(320 · 2.0) 한 줄(≈257px)에 5자(≈150px)가 다 들어가 낱말 안에서 끊길 일이 없다.
    //   띄어쓰기가 있거나 6자 이상인 이름은 식별 이름 규칙(TextLayout.identity — 공백 · 가운데에서만 줄바꿈)으로 끊는다.
    final workName = work.workType;
    final workNameShown =
        workName.contains(' ') || workName.characters.length >= 6
            ? TextLayout.identity(workName)
            : workName;

    return Container(
      // [DU508 r4 · 후속121 F121-1] 카드 바탕/테두리는 본문 폭을 다 쓴다 — r3 에서 Row(Expanded)를 걷은 뒤 W 카드가 내용 폭(≈206px)으로 줄었다.
      width: double.infinity,
      margin:
          EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
      padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // [DU508 r3 · 후속120 §2-1 · F120-2] 날짜 덩어리와 업무명을 **따로** 놓고 Wrap 이 줄을 나눈다.
          //   업무명이 날짜 줄에 다 들어가지 않으면 업무명 전체가 다음 줄로 간다('11월 23일(일) ·' / '냉장분류') —
          //   r2 TA 에서 B 날짜가 '11월 2 / 3일' · '23일(일)' 안에서 끊긴 것을 막는다. 날짜 덩어리(≈214px)는
          //   B 카드 안쪽 폭(≈257px — 상태 표시를 아래 줄로 옮겨 생긴 온 폭)보다 짧아 한 줄에 든다.
          //   화면 글자는 원문이라 날짜 · 짧은 업무명을 원문으로 찾는 기존 시험(MAC-30 · KD-1)이 그대로 맞는다.
          //   읽기 이름은 한 덩어리 원문('11월 23일(일) · 냉장분류') 그대로다.
          Semantics(
            label: '$dateStr${work.workType}',
            excludeSemantics: true,
            child: Wrap(
              children: [
                if (dateStr.isNotEmpty) Text(dateStr, style: rowStyle),
                Text(workNameShown, style: rowStyle),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 3)),
          Text(
            // [DU1-F2] 금액 단위 — 저장 급여 형태 라벨(시급/일급)을 붙인다. 새 계산 없음.
            // [F293-WAGE-01] 시급 업무는 이 날짜·업무 1회의 하루 예상 + 시급.
            '${work.startTime} ~ ${work.endTime}  ·  ${ExpectedWageText.combined(ExpectedDailyWage.forWorkDetail(work)) ?? '${work.wageTypeLabel} ${ExpectedWageText.rawWage(work.wage)}'}',
            style: ResponsiveHelper.smallStyle(context).copyWith(
              color: isDisabled
                  ? AppColors.grey400
                  : AppColors.grey600,
            ),
          ),
          // [DU508 r3 · 후속120 §2-1] 상태 표시(확인 중 · 완료 표시 · 배지)는 날짜 · 시간 **아래 줄**이다.
          //   예전에는 날짜 칸 오른쪽에 붙어 B(320 · 2.0)에서 '이미 지원중' 배지가 날짜 칸 폭을 차지했고,
          //   날짜가 덩어리 안에서 끊겼다(r2 TA B BLOCK ok=false · 3줄). 세 표시 모두 같은 자리로 옮긴다 —
          //   판정 순서 · 문구 · 색 · 크기는 그대로다(배치만 바꾼다).
          if (isChecking) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: AppColors.grey400,
              ),
            ),
          ] else if (_submitDone && meta.applyError == null && !isDisabled) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            const Icon(Icons.check_circle, color: AppColors.success, size: 20),
          ] else if (badgeText != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: badgeColor!.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                badgeText,
                style: ResponsiveHelper.tinyStyle(context).copyWith(
                  color: badgeColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          if (subMsg != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(
              subMsg,
              style: ResponsiveHelper.tinyStyle(context)
                  .copyWith(color: subColor ?? AppColors.grey500),
            ),
          ],
        ],
      ),
    );
  }

  // ─ 서류 접근 사전동의 ─────────────────────────────────────────────────────
  //
  // [DOCUMENT-CONSENT] 서류 접근 사전동의 (V3: 신분증+급여계좌+통장사본)
  // documentAccessConsentVersion: "2026-09-12-v2"
  // [LEGAL-REVIEW-ID-CONSENT] 동의 문구 및 방식의 법적 적절성은 별도 법무 검토 필요

  Widget _buildConsent(BuildContext context) {
    return DocumentAccessConsent.card(widget.to.businessName);
  }

  // ─ CTA ───────────────────────────────────────────────────────────────────

  Widget _buildCTA(BuildContext context) {
    final targets = _submitTargets;
    final isAllDisabled = targets.isEmpty && !_isCheckingConflicts;

    return Column(
      children: [
        // 지원 안내 문구 (지원 가능 항목 있을 때만)
        if (!_isCheckingConflicts && !isAllDisabled) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.symmetric(
              horizontal: ResponsiveHelper.spacing(context, 12),
              vertical: ResponsiveHelper.spacing(context, 10),
            ),
            decoration: BoxDecoration(
              color: AppColors.grey50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.grey200),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline,
                    size: 14, color: AppColors.grey600),
                SizedBox(width: ResponsiveHelper.spacing(context, 6)),
                Flexible(
                  child: Text(
                    // [DU508] B 에서 '지원 / 을'처럼 끊겼다 — 낱말 조판(원문 semantics).
                    TextLayout.keepWords('지원 후 관리자의 근무 확정을 기다려주세요. '
                        '근무 확정 전까지 지원을 취소할 수 있습니다.'),
                    semanticsLabel: '지원 후 관리자의 근무 확정을 기다려주세요. '
                        '근무 확정 전까지 지원을 취소할 수 있습니다.',
                    style: ResponsiveHelper.tinyStyle(context)
                        .copyWith(color: AppColors.grey700),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        ],

        // 전체 지원 불가 안내
        if (isAllDisabled) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
            ),
            child: Text(
              '선택한 업무 모두 이미 지원 중이거나 확정된 근무와 시간이 겹쳐요.',
              style: ResponsiveHelper.smallStyle(context)
                  .copyWith(color: AppColors.error),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        ],

        // 지원하기 버튼
        CommonWidgets.primaryButton(
          context: context,
          text: isAllDisabled
              ? '지원 불가'
              : _isSubmitting
                  ? '지원 중...'
                  : _isCheckingConflicts
                      ? '확인 중...'
                      : targets.length > 1
                          ? '${targets.length}개 업무 지원하기'
                          : '지원하기',
          onPressed: (isAllDisabled || _isSubmitting || _isCheckingConflicts)
              ? null
              : _submit,
          icon: Icons.send,
        ),

        // 취소
        Center(
          child: TextButton(
            onPressed: _isSubmitting ? null : () => Navigator.pop(context),
            style: TextButton.styleFrom(
              // [DU471] 취소 grey400(1.88) → textSecondary(DU441 취소 · UI-1 보조 글자 버튼). 처리 중(비활성)은 아래 글자색이 grey400 을 지킨다.
              foregroundColor: AppColors.textSecondary,
              padding: EdgeInsets.symmetric(
                  vertical: ResponsiveHelper.spacing(context, 8)),
            ),
            child: Text(
              '취소',
              style: ResponsiveHelper.bodyStyle(context)
                  .copyWith(color: _isSubmitting ? AppColors.grey400 : AppColors.textSecondary),
            ),
          ),
        ),
      ],
    );
  }

  // ─ 결과 표시 ─────────────────────────────────────────────────────────────

  Widget _buildResult(BuildContext context) {
    final targets = _submitTargets;
    final okCount = targets.where((m) => m.applyOk).length;
    final unknownCount = targets.where((m) => m.applyUnknown).length;
    final failCount = targets.length - okCount - unknownCount;

    return Column(
      children: [
        // [R8-P3A.1] 결과를 모르는 건은 실패 칸에 넣지 않고 따로 말한다.
        if (unknownCount > 0) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
            ),
            child: Text(
              '$unknownCount개 업무는 지원 결과를 확인하지 못했어요.\n'
              '지원이 접수됐을 수 있으니 내 지원 목록에서 확인해주세요.',
              style: ResponsiveHelper.smallStyle(context).copyWith(
                color: AppColors.warningDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        ],
        if (failCount > 0) ...[
          Container(
            width: double.infinity,
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 12)),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: AppColors.error.withValues(alpha: 0.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  failCount == targets.length
                      ? '지원에 실패했어요'
                      : '${targets.length}개 중 $failCount개 업무 지원에 실패했어요',
                  style: ResponsiveHelper.smallStyle(context).copyWith(
                    color: AppColors.error,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ...targets
                    .where((m) => !m.applyOk && !m.applyUnknown)
                    .map((m) => Padding(
                          padding: EdgeInsets.only(
                              top: ResponsiveHelper.spacing(context, 4)),
                          child: Text(
                            '· ${m.item.work.workType}: ${m.applyError}',
                            style: ResponsiveHelper.tinyStyle(context)
                                .copyWith(color: AppColors.error),
                          ),
                        )),
              ],
            ),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        ],
        CommonWidgets.primaryButton(
          context: context,
          text: '확인',
          onPressed: () => Navigator.pop(
            context,
            MultiApplyResult(
              // [R8-P3A.1] 새로 기록된 건만 센다 — '이미 지원중'은 변화가 아니다.
              hasChanges: targets.any((m) => m.outcome == ApplyOutcome.success),
              appliedCount:
                  targets.where((m) => m.outcome == ApplyOutcome.success).length,
              // [R7-PAYROLL-POLICY.4C] 결과 화면을 닫을 때도 알린다 —
              //   공고 화면이 최신 기준을 다시 읽어 보여준다.
              policyChanged: targets
                  .any((m) => m.outcome == ApplyOutcome.policyChanged),
            ),
          ),
        ),
      ],
    );
  }
}
