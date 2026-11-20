// [NS-PENDING-DEST] 노쇼 원장 보류 — 슈퍼관리자 처리 화면.
//
//   보류 경보 알림(type noShowLedgerPending, data {pendingId, occurrence, uid, reason})을
//   누르면 온다. 알림이 가리키는 것은 (보류 키, 발생 번호) 한 건이다.
//     · 열 때마다 서버에서 현재 상태를 다시 읽는다(알림에 적힌 값으로 판단하지 않는다).
//     · 그 발생이 지금도 OPEN 일 때만 해소 동작을 연다. 같은 키가 새 발생으로 다시
//       열렸으면(__o0 → __o1) 이 알림에서는 새 발생의 해소를 열지 않는다.
//     · 해소는 사용자 단위라 그 사용자의 열린 보류를 모두 닫는다 — 확인 단계에서 함께 처리될
//       보류 전부(id·원인·시작 시각·서버 미리보기 결과)를 보이고, 사용자가 본 그 집합을
//       expectedOpenPending 으로 그대로 보낸다. 서버가 같은 TX 에서 집합을 다시 비교한다.
//       requestId 는 한 결정에 하나 — 응답이 불명확하면 같은 requestId 로만 다시 보낸다.
//     · 해소 방법은 기본 선택하지 않는다. 근거 판정은 서버가 원본 기록으로 한다.
//       근거 부족(수동 조사 중) 보류나 한 해소로 다룰 수 없는 원인이 섞이면 해소 버튼을 두지 않는다.
//   벌점 원장은 클라이언트가 쓰지 않는다.
import 'dart:math';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../providers/user_provider.dart';
import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/common_widgets.dart';
import 'noshow_pending_reads.dart';

/// 서버가 돌려준 보류 한 건(읽기 전용 요약).
class NoShowPendingSummary {
  const NoShowPendingSummary({
    required this.id,
    required this.status,
    required this.occurrence,
    this.reason,
    this.cause,
    this.applicationId,
    this.day,
    this.at,
    this.firstSeenAt,
    this.resolvedAt,
    this.resolvedBy,
    this.manualWhy,
  });

  final String id;
  final String status;
  final int occurrence;
  final String? reason;
  final String? cause;
  final String? applicationId;
  final String? day;
  final DateTime? at;
  final DateTime? firstSeenAt;
  final DateTime? resolvedAt;
  final String? resolvedBy;
  final String? manualWhy;

  bool get isOpen => status == 'OPEN';

  static DateTime? _ms(Object? v) =>
      v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt(), isUtc: true) : null;

  static NoShowPendingSummary? tryFrom(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    if (id is! String || id.isEmpty) return null;
    final mi = raw['manualInvestigation'];
    return NoShowPendingSummary(
      id: id,
      status: (raw['status'] as String?) ?? 'UNKNOWN',
      occurrence: (raw['occurrence'] as num?)?.toInt() ?? 0,
      reason: raw['reason'] as String?,
      cause: raw['cause'] as String?,
      applicationId: raw['applicationId'] as String?,
      day: raw['day'] as String?,
      at: _ms(raw['atMs']),
      firstSeenAt: _ms(raw['firstSeenAtMs']),
      resolvedAt: _ms(raw['resolvedAtMs']),
      resolvedBy: raw['resolvedBy'] as String?,
      manualWhy: mi is Map ? mi['why'] as String? : null,
    );
  }
}

/// 원인 코드 → 사람이 읽는 설명(서버 srvNsLedgerForWrite 의 판정 이유).
String noShowPendingReasonText(String? code) => switch (code) {
      'LEGACY_COUNT_DATES_MISMATCH' => '기존 노쇼 횟수와 날짜 수가 맞지 않습니다',
      'LEGACY_RESET_DATES_REMAIN' => '리셋된 횟수인데 이전 날짜가 남아 있습니다',
      'LEGACY_RECENT_WITHOUT_DATES' => '최근 90일 횟수는 있는데 날짜가 없습니다',
      'LEGACY_SLOTS_EXIST' => '이관 전 기록 형식이 남아 있습니다',
      'MIGRATION_EQUALITY_FAILED' => '원장으로 옮긴 결과가 기존 값과 같지 않습니다',
      null || '' || 'UNKNOWN' => '원인을 특정하지 못했습니다',
      _ => '서버 판정: $code',
    };

/// 보류를 만든 쓰기 경로.
String noShowPendingCauseText(String? cause) => switch (cause) {
      'cancel' => '늦은 확정 취소의 벌점',
      'apply' => '당일 취소 노쇼 벌점',
      'trigger-on' => '근태 노쇼 처리의 벌점',
      'trigger-off' => '근태 노쇼 정정(벌점 되돌림)',
      final c? when c.startsWith('reconcile') => '장기 근무 노쇼 정합 판정',
      null || '' => '알 수 없음',
      _ => cause,
    };

/// 서버 해소 정의(SRV_NS_RESOLUTIONS)와 같은 표 — 서버가 다시 검증한다.
const Map<String, ({String label, String meaning, List<String> reasons})> kNoShowResolutions = {
  'COUNT_FROM_DATES': (
    label: '날짜가 사실',
    meaning: '남은 날짜가 원본 기록과 하나씩 맞으면, 횟수를 그 날짜 수로 맞춥니다.',
    reasons: ['LEGACY_COUNT_DATES_MISMATCH', 'LEGACY_RESET_DATES_REMAIN'],
  ),
  'CLEAR_STALE_DATES': (
    label: '리셋이 사실',
    meaning: '리셋 감사 기록이 있으면, 마지막 리셋 이전 날짜만 비우고 이후 벌점은 남깁니다.',
    reasons: ['LEGACY_RESET_DATES_REMAIN', 'LEGACY_COUNT_DATES_MISMATCH'],
  ),
  'RECENT_STALE': (
    label: '최근 90일 값이 낡음',
    meaning: '최근 90일에 노쇼 근태·벌점 표시·원장 항목이 하나도 없을 때만 0으로 맞춥니다.',
    reasons: ['LEGACY_RECENT_WITHOUT_DATES'],
  ),
};

enum _View { loading, failed, forbidden, badLink, notFound, otherOccurrence, closed, open }

class NoShowPendingReviewScreen extends StatefulWidget {
  const NoShowPendingReviewScreen({
    super.key,
    required this.pendingId,
    required this.occurrence,
    required this.targetUid,
    this.reads,
  });

  /// 알림 data.pendingId / data.occurrence / data.uid
  final String? pendingId;
  final int? occurrence;
  final String? targetUid;
  final NoShowPendingReads? reads;

  @override
  State<NoShowPendingReviewScreen> createState() => _NoShowPendingReviewScreenState();
}

class _NoShowPendingReviewScreenState extends State<NoShowPendingReviewScreen> {
  late final NoShowPendingReads _reads = widget.reads ?? NoShowPendingReads.of();
  final _reasonCtrl = TextEditingController();

  _View _view = _View.loading;
  NoShowPendingSummary? _pending;
  String? _planStatus;
  String? _planReason;
  int? _count;
  int? _dates;
  int? _recent;
  /// 이 사용자의 열린 보류 전부(알림의 발생이 맨 앞). 해소는 이 전부를 닫는다.
  List<NoShowPendingSummary> _openAll = const [];
  String? _failMessage;

  String? _selected; // 기본 선택 없음
  bool _submitting = false;
  String? _requestId; // 한 결정에 하나 — 결과가 불명확하면 그대로 다시 보낸다
  bool _outcomeUnknown = false;
  String? _resultText;
  bool _resultIsWarning = false;

  /// 확인 단계 — 서버 미리보기(dryRun)와 그때 본 열린 보류 집합. 이 집합 그대로 제출한다.
  List<NoShowPendingSummary>? _confirmSet;
  String? _previewStatus; // MIGRATED(닫힘) | EVIDENCE_INSUFFICIENT(바꾸지 않음) | 그 밖
  String? _previewWhy;
  String? _previewKey; // 미리보기 당시 (해소|사유) — 바뀌면 확인을 버린다
  /// [.56] 서버 미리보기의 처리 효과(해소 전·후 횟수·최근 90일·이용 제한). 서버 값을 그대로 보인다.
  Map? _previewBefore;
  Map? _previewAfter;

  /// [.56] 대상 근로자(이름·아이디). null 이면 아직 모르거나 읽지 못함.
  String? _targetLabel;
  bool _targetTried = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (context.read<UserProvider>().currentUser?.isSuperAdmin != true) {
        setState(() => _view = _View.forbidden);
        return;
      }
      _load();
    });
  }

  @override
  void dispose() {
    _reasonCtrl.dispose();
    super.dispose();
  }

  bool get _linkOk =>
      (widget.pendingId ?? '').isNotEmpty && (widget.targetUid ?? '').isNotEmpty && widget.occurrence != null;

  Future<void> _load() async {
    if (!_linkOk) {
      setState(() => _view = _View.badLink);
      return;
    }
    setState(() {
      _view = _View.loading;
      _failMessage = null;
    });
    try {
      final r = await _reads.migrate({
        'uids': [widget.targetUid],
        'dryRun': true,
        'includePending': true,
      });
      if (!mounted) return;
      _apply(r);
      if (!_targetTried) _loadTarget();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() {
        _view = e.code == 'permission-denied' ? _View.forbidden : _View.failed;
        _failMessage = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _view = _View.failed);
    }
  }

  /// [.56] 대상 근로자 이름 — 한 번만 읽는다(결정과 무관한 표시용). 실패해도 해소 흐름은 막지 않는다.
  Future<void> _loadTarget() async {
    _targetTried = true;
    final f = _reads.targetLabel;
    final uid = widget.targetUid;
    if (f == null || uid == null) return;
    try {
      final label = await f(uid);
      if (mounted) setState(() => _targetLabel = label);
    } catch (_) {
      // 표시만 '확인하지 못함'으로 남긴다.
    }
  }

  /// 서버 응답 → 화면 상태. 조회·해소 응답 모두 같은 모양(report + pending)이다.
  void _apply(Map<String, dynamic> r) {
    final report = (r['report'] as List?) ?? const [];
    final first = report.isNotEmpty && report.first is Map ? report.first as Map : const {};
    final status = first['status'] as String?;
    final before = first['before'];
    final pendings = ((r['pending'] as List?) ?? const [])
        .map(NoShowPendingSummary.tryFrom)
        .whereType<NoShowPendingSummary>()
        .toList();
    final target = pendings.where((p) => p.id == widget.pendingId).firstOrNull;
    setState(() {
      // 조회 응답의 report 는 지금 사용자 상태(불명확이면 SKIPPED+이유). 해소 응답이면 결정 결과다.
      if (status == 'SKIPPED' || status == 'MIGRATED' || status == 'ALREADY') {
        _planStatus = status;
        _planReason = first['reason'] as String?;
      }
      if (before is Map) {
        _count = (before['count'] as num?)?.toInt();
        _dates = (before['datesMs'] as List?)?.length;
        _recent = (before['recent'] as num?)?.toInt();
      }
      _pending = target;
      _openAll = pendings.where((p) => p.isOpen).toList()
        ..sort((a, b) => a.id == widget.pendingId ? -1 : (b.id == widget.pendingId ? 1 : a.id.compareTo(b.id)));
      // 다시 읽으면 이전 확인은 무효 — 집합이 같아도 사용자가 다시 확인한다.
      _confirmSet = null;
      _previewStatus = null;
      _previewWhy = null;
      _previewKey = null;
      _previewBefore = null;
      _previewAfter = null;
      if (target == null) {
        _view = _View.notFound;
      } else if (target.occurrence != widget.occurrence &&
          // 서버 해소(srvNsResolvePending)는 닫으면서 occurrence 를 +1 한다 — 닫힌 문서의 번호가
          //   알림 발생 + 1 이면 닫힌 것은 바로 이 알림의 발생이다(다른 발생이 생긴 것이 아니다).
          !(!target.isOpen && target.occurrence == widget.occurrence! + 1)) {
        _view = _View.otherOccurrence;
      } else if (!target.isOpen) {
        _view = _View.closed;
      } else {
        _view = _View.open;
      }
    });
  }

  /// 해소 뒤 지금 값 다시 읽기(쓰지 않는 조회). 실패하면 낡은 값을 '지금'으로 두지 않고 확인하지 못함으로 바꾼다.
  Future<void> _refreshNowValues() async {
    try {
      final r = await _reads.migrate({
        'uids': [widget.targetUid],
        'dryRun': true,
        'includePending': true,
      });
      if (!mounted) return;
      _apply(r);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _count = null;
        _dates = null;
        _recent = null;
        _planStatus = null;
      });
    }
  }

  String _newRequestId() {
    final rnd = Random.secure();
    final hex = List.generate(12, (_) => rnd.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
    return 'nsp-$hex';
  }

  bool get _formLocked => _submitting || _outcomeUnknown;

  String get _decisionKey => '${_selected ?? ''}|${_reasonCtrl.text.trim()}';

  /// 결정 입력이 바뀌면 확인 단계를 버린다(결과가 불명확한 동안에는 입력이 잠겨 있다).
  void _invalidateConfirm() {
    if (_outcomeUnknown) return;
    _confirmSet = null;
    _previewStatus = null;
    _previewWhy = null;
    _previewKey = null;
    _previewBefore = null;
    _previewAfter = null;
    _requestId = null;
  }

  List<Map<String, Object>> _setPayload(List<NoShowPendingSummary> set) =>
      [for (final p in set) {'id': p.id, 'occurrence': p.occurrence}];

  Map<String, dynamic> _firstReport(Map<String, dynamic> r) {
    final report = (r['report'] as List?) ?? const [];
    return report.isNotEmpty && report.first is Map ? Map<String, dynamic>.from(report.first as Map) : <String, dynamic>{};
  }

  /// 서버 거절을 해석한다. 집합이 바뀌었으면 결정을 적용하지 않고 다시 읽는다.
  Future<void> _onRejected(FirebaseFunctionsException e) async {
    final details = e.details;
    final changed = details is Map && details['code'] == 'PENDING_CHANGED';
    final definitive = changed || const {'failed-precondition', 'invalid-argument', 'permission-denied', 'already-exists'}.contains(e.code);
    setState(() {
      if (definitive) {
        _requestId = null;
        _outcomeUnknown = false;
        _resultText = changed
            ? '확인한 뒤 열린 보류가 바뀌어 해소하지 않았습니다. 현재 상태를 다시 불러왔습니다.'
            : (e.message ?? '요청이 거절됐습니다.');
      } else {
        // 응답 불명확 — 서버에 기록됐을 수 있다. 같은 requestId·같은 집합으로만 다시 확인한다.
        _outcomeUnknown = true;
        _resultText = '결과를 확인하지 못했어요. 같은 요청으로 다시 확인해 주세요(두 번 기록되지 않습니다).';
      }
      _resultIsWarning = true;
    });
    if (definitive) await _load();
  }

  /// 확인 단계 — 지금 열린 보류 전부를 대상으로 서버 미리보기(dryRun). 쓰기 없음.
  Future<void> _preview() async {
    final sel = _selected;
    final why = _reasonCtrl.text.trim();
    if (sel == null || _view != _View.open || _submitting) return;
    if (why.length < 2 || why.length > 500) {
      setState(() {
        _resultText = '사유를 2~500자로 적어 주세요.';
        _resultIsWarning = true;
      });
      return;
    }
    final set = List<NoShowPendingSummary>.of(_openAll);
    _requestId ??= _newRequestId();
    setState(() {
      _submitting = true;
      _resultText = null;
    });
    try {
      final r = await _reads.migrate({
        'uids': [widget.targetUid],
        'dryRun': true,
        'includePending': true,
        'resolution': sel,
        'reason': why,
        'requestId': _requestId,
        'expectedOpenPending': _setPayload(set),
      });
      if (!mounted) return;
      final first = _firstReport(r);
      final st = first['status'] as String?;
      if (st == 'REPLAY') {
        // 이 requestId 의 결정이 이미 서버에 있다 — 그 결과를 보여 주고 다시 읽는다.
        _requestId = null;
        setState(() {
          _resultText = '이미 처리된 요청입니다(결과: ${first['result'] ?? '알 수 없음'}).';
          _resultIsWarning = true;
        });
        await _load();
        return;
      }
      setState(() {
        _confirmSet = set;
        _previewStatus = st;
        _previewWhy = first['why'] as String?;
        _previewKey = _decisionKey;
        _previewBefore = first['before'] is Map ? first['before'] as Map : null;
        _previewAfter = first['after'] is Map ? first['after'] as Map : null;
      });
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      _outcomeUnknown = false; // 미리보기는 쓰지 않는다 — 불명확해도 다시 미리보면 된다
      final details = e.details;
      if (details is Map && details['code'] == 'PENDING_CHANGED' || e.code == 'failed-precondition') {
        await _onRejected(e);
      } else {
        setState(() {
          _resultText = '확인 화면을 만들지 못했어요. 다시 시도해 주세요.';
          _resultIsWarning = true;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resultText = '확인 화면을 만들지 못했어요. 다시 시도해 주세요.';
        _resultIsWarning = true;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// 제출 — 확인 단계에서 본 집합 그대로. 서버가 같은 TX 에서 다시 비교한다.
  Future<void> _commit() async {
    final set = _confirmSet;
    final sel = _selected;
    if (set == null || sel == null || _submitting) return; // 중복 탭
    if (!_outcomeUnknown && (_previewStatus != 'MIGRATED' || _previewKey != _decisionKey)) return;
    _requestId ??= _newRequestId();
    setState(() {
      _submitting = true;
      _resultText = null;
    });
    try {
      final r = await _reads.migrate({
        'uids': [widget.targetUid],
        'dryRun': false,
        'includePending': true,
        'resolution': sel,
        'reason': _reasonCtrl.text.trim(),
        'requestId': _requestId,
        'expectedOpenPending': _setPayload(set),
      });
      if (!mounted) return;
      final first = _firstReport(r);
      final st = first['status'] as String?;
      final outcome = st == 'REPLAY' ? first['result'] as String? : st;
      _requestId = null; // 결정이 서버에 남았다 — 다음 결정은 새 requestId
      _outcomeUnknown = false;
      final closed = set.length;
      setState(() {
        if (outcome == 'MIGRATED' || outcome == 'RESOLVED') {
          _resultText = closed > 1 ? '해소했습니다. 확인한 보류 $closed건이 모두 닫혔습니다.' : '해소했습니다. 이 보류는 닫혔습니다.';
          _resultIsWarning = false;
        } else if (outcome == 'EVIDENCE_INSUFFICIENT') {
          _resultText = '근거가 부족해 바꾸지 않았습니다(수동 조사로 남김)'
              '${first['why'] != null ? ': ${first['why']}' : '.'}';
          _resultIsWarning = true;
        } else {
          _resultText = '서버 결과: ${outcome ?? '알 수 없음'}';
          _resultIsWarning = true;
        }
      });
      _apply(r);
      // 해소 응답의 report.before 는 해소 '전' 사용자 값이다 — '지금 사용자 값'은 다시 읽어 채운다.
      await _refreshNowValues();
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      await _onRejected(e);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _outcomeUnknown = true;
        _resultText = '결과를 확인하지 못했어요. 같은 요청으로 다시 확인해 주세요(두 번 기록되지 않습니다).';
        _resultIsWarning = true;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ── UI ─────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppPageScaffold(
      title: '노쇼 원장 보류',
      body: switch (_view) {
        _View.loading => const Center(child: CircularProgressIndicator()),
        _View.forbidden => _message(Icons.lock_outline, '슈퍼관리자만 볼 수 있습니다.', null),
        _View.badLink => _message(Icons.link_off, '알림에 보류 정보가 없어 열 수 없습니다.', '보류 키·발생 번호·대상 사용자가 필요합니다.'),
        _View.failed => _message(Icons.cloud_off_rounded, '보류 상태를 확인하지 못했어요.', _failMessage, retry: true),
        _ => _content(),
      },
    );
  }

  Widget _message(IconData icon, String title, String? sub, {bool retry = false}) {
    return Center(
      child: Padding(
        padding: ResponsiveHelper.cardPadding(context),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: ResponsiveHelper.iconSize(context, 40), color: AppColors.grey400),
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          Text(title, textAlign: TextAlign.center, style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary)),
          if (sub != null) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 6)),
            Text(sub, textAlign: TextAlign.center, style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary)),
          ],
          if (retry) ...[
            SizedBox(height: ResponsiveHelper.spacing(context, 12)),
            OutlinedButton(onPressed: _load, child: const Text('다시 시도')),
          ],
        ]),
      ),
    );
  }

  Widget _content() {
    final p = _pending;
    return SingleChildScrollView(
      padding: ResponsiveHelper.cardPadding(context),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _statusBanner(),
        SizedBox(height: ResponsiveHelper.spacing(context, 12)),
        if (p != null) _detailCard(p),
        if (_view == _View.open) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          _resolveCard(),
        ],
        if (_resultText != null && _view != _View.open) ...[
          SizedBox(height: ResponsiveHelper.spacing(context, 12)),
          _resultLine(),
        ],
      ]),
    );
  }

  Widget _statusBanner() {
    final p = _pending;
    final (Color bg, Color fg, IconData icon, String text) = switch (_view) {
      _View.open => (AppColors.warningBg, AppColors.warningDark, Icons.pending_actions, '열린 보류 — 발생 ${p!.occurrence}'),
      _View.closed => (AppColors.successBg, AppColors.successDark, Icons.check_circle_outline,
          '이미 해소된 보류입니다${p?.resolvedAt != null ? ' (${FormatHelper.formatKstMonthDayTime(p!.resolvedAt!)})' : ''}'),
      _View.otherOccurrence => (AppColors.infoBg, AppColors.infoDark, Icons.history,
          '이 알림은 이전 발생(${widget.occurrence})입니다. 현재는 발생 ${p?.occurrence} · ${p?.isOpen == true ? '열림' : '닫힘'}'),
      _ => (AppColors.grey100, AppColors.textSecondary, Icons.search_off, '이 보류를 찾을 수 없습니다'),
    };
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.compactCardDecoration(color: bg, borderOnly: false),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: ResponsiveHelper.iconSize(context, 20), color: fg),
        SizedBox(width: ResponsiveHelper.spacing(context, 8)),
        Expanded(child: Text(text, style: ResponsiveHelper.bodyStyle(context, color: fg).copyWith(fontWeight: FontWeight.w600))),
      ]),
    );
  }

  /// [.56] 큰 글자(392·2.0)에서 고정 폭 이름 칸이 '대상 근|로자'·'최근 90|일' 로 끊기고, 옆 값과 붙어
  ///   '최근 902 → 3' 처럼 읽혔다. 글자 배율이 크면 이름 위·값 아래로 쌓고, 글자는 낱말 단위로 바꾼다(표시만).
  Widget _row(String label, String value) {
    final labelText = Text(TextLayout.keepWords(label), semanticsLabel: label,
        style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary));
    final valueText = Text(TextLayout.keepWords(value), semanticsLabel: value,
        style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary));
    final stacked = MediaQuery.textScalerOf(context).scale(10) > 12.5;
    return Padding(
      padding: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 6)),
      child: stacked
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [labelText, valueText])
          : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: ResponsiveHelper.spacing(context, 92), child: labelText),
              Expanded(child: valueText),
            ]),
    );
  }

  Widget _detailCard(NoShowPendingSummary p) {
    final mismatch = _count != null && _dates != null
        ? '횟수 $_count · 날짜 $_dates개${_count != _dates ? ' — ${(_count! - _dates!).abs()}개 차이' : ''}'
            '${_recent != null ? ' · 최근 90일 $_recent' : ''}'
        : '확인하지 못함';
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.compactCardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('보류 근거', style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.w700)),
        SizedBox(height: ResponsiveHelper.spacing(context, 10)),
        // [.56] 누구에 대한 결정인지 — 이름이 같은 사람을 가르도록 아이디도 함께 보인다.
        if (_reads.targetLabel != null) _row('대상 근로자', _targetLabel ?? (_targetTried ? '확인하지 못함' : '불러오는 중')),
        _row('원인', noShowPendingReasonText(p.reason)),
        _row('발생 경로', noShowPendingCauseText(p.cause)),
        if (p.day != null) _row('근무일', '${p.day!.substring(0, 4)}.${p.day!.substring(4, 6)}.${p.day!.substring(6, 8)}'),
        _row('보류 시작', p.at != null ? FormatHelper.formatKstDateTimeKorean(p.at!) : '알 수 없음'),
        if (p.firstSeenAt != null) _row('경보 확인', FormatHelper.formatKstDateTimeKorean(p.firstSeenAt!)),
        _row('지금 사용자 값', mismatch),
        if (_planStatus != null)
          _row('지금 판정', _planStatus == 'SKIPPED'
              ? '불명확 — ${noShowPendingReasonText(_planReason)}'
              : '불일치 없음(이관 가능)'),
        if (p.manualWhy != null) _row('이전 해소 시도', '근거 부족 — ${p.manualWhy}'),
        if (_openAll.length > 1) _row('같은 사용자', '열린 보류 ${_openAll.length}건 — 해소는 사용자 단위라 모두 함께 처리됩니다(확인 단계에서 전부 보여 줍니다)'),
      ]),
    );
  }

  /// 수동 조사 중(이전 해소가 근거 부족)인 열린 보류 — 섞여 있으면 앱에서 해소하지 않는다.
  bool get _hasInsufficient => _openAll.any((p) => p.manualWhy != null);

  /// 지금 판정 이유와 열린 보류 **모두**의 원인에 쓸 수 있는 해소만(서버도 같은 기준으로 다시 막는다).
  List<String> get _available {
    if (_planStatus != 'SKIPPED' || _hasInsufficient) return const [];
    return kNoShowResolutions.entries
        .where((e) => e.value.reasons.contains(_planReason) && _openAll.every((p) => e.value.reasons.contains(p.reason)))
        .map((e) => e.key)
        .toList();
  }

  String get _noOptionText {
    if (_planStatus != 'SKIPPED') return '지금은 불명확 상태가 아니어서 해소할 것이 없습니다.';
    if (_hasInsufficient) return '근거 부족으로 수동 조사 중인 보류가 있어 앱에서 해소하지 않습니다.';
    final planOk = kNoShowResolutions.values.any((d) => d.reasons.contains(_planReason));
    if (planOk && _openAll.length > 1) return '원인이 다른 보류가 섞여 있어 한 해소로 처리할 수 없습니다. 수동 조사가 필요합니다.';
    return '이 원인에 앱에서 고를 수 있는 해소가 없습니다. 수동 조사가 필요합니다.';
  }

  /// 확인 단계 — 함께 처리될 보류 전부와 서버가 미리 본 결과.
  Widget _confirmPanel() {
    final set = _confirmSet!;
    final ok = _previewStatus == 'MIGRATED';
    final expected = ok ? '닫힘 — 원장으로 옮겨 해소' : (_previewStatus == 'EVIDENCE_INSUFFICIENT' ? '바꾸지 않음 — 근거 부족' : '알 수 없음(${_previewStatus ?? '-'})');
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.compactCardDecoration(color: ok ? AppColors.infoBg : AppColors.warningBg),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('해소 확인 — 「${kNoShowResolutions[_selected]?.label ?? '-'}」로 아래 ${set.length}건을 함께 처리합니다',
            style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary).copyWith(fontWeight: FontWeight.w700)),
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        for (final p in set)
          Container(
            key: ValueKey('confirm-${p.id}'),
            width: double.infinity,
            margin: EdgeInsets.only(bottom: ResponsiveHelper.spacing(context, 8)),
            padding: EdgeInsets.all(ResponsiveHelper.spacing(context, 10)),
            decoration: CommonWidgets.compactCardDecoration(
                color: p.id == widget.pendingId ? AppColors.warningLight : AppColors.surface),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.id == widget.pendingId ? '이 알림의 보류 · 발생 ${p.occurrence}' : '함께 처리될 다른 보류 · 발생 ${p.occurrence}',
                  style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary).copyWith(fontWeight: FontWeight.w700)),
              SizedBox(height: ResponsiveHelper.spacing(context, 4)),
              _row('보류 id', p.id),
              _row('원인', noShowPendingReasonText(p.reason)),
              _row('발생 경로', noShowPendingCauseText(p.cause)),
              _row('보류 시작', p.at != null ? FormatHelper.formatKstDateTimeKorean(p.at!) : '알 수 없음'),
              _row('예상 결과', expected),
            ]),
          ),
        // [.56] 처리 효과 — 서버 미리보기의 해소 전·후 값을 그대로. 제한 예측이 없는 서버(원본)에서는 '제한 없음'으로 단정하지 않는다.
        if (ok && _previewAfter != null) ...[
          if (_reads.targetLabel != null) _row('대상 근로자', _targetLabel ?? '확인하지 못함'),
          _row('노쇼 횟수', '${_previewBefore?['count'] ?? '-'} → ${_previewAfter!['count'] ?? '-'}'),
          _row('최근 90일', '${_previewBefore?['recent'] ?? '-'} → ${_previewAfter!['recent'] ?? '-'}'),
          _row('이용 제한', _restrictionText(_previewBefore?['restriction'], _previewAfter!['restriction'])),
        ],
        if (!ok && _previewWhy != null)
          Text('서버 확인: $_previewWhy', style: ResponsiveHelper.smallStyle(context, color: AppColors.warningDark)),
        if (_resultText != null) ...[SizedBox(height: ResponsiveHelper.spacing(context, 6)), _resultLine()],
        SizedBox(height: ResponsiveHelper.spacing(context, 8)),
        Row(children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _submitting || _outcomeUnknown ? null : () => setState(_invalidateConfirm),
              child: Text(TextLayout.keepWords('다시 고르기'), semanticsLabel: '다시 고르기', textAlign: TextAlign.center),
            ),
          ),
          if (ok || _outcomeUnknown) ...[
            SizedBox(width: ResponsiveHelper.spacing(context, 8)),
            Expanded(
              child: ElevatedButton(
                onPressed: _submitting ? null : _commit,
                child: Text(TextLayout.keepWords(_submitting ? '요청 중…' : (_outcomeUnknown ? '같은 요청으로 결과 확인' : '이대로 해소')),
                    textAlign: TextAlign.center),
              ),
            ),
          ],
        ]),
      ]),
    );
  }

  Widget _resolveCard() {
    final options = _available;
    return Container(
      padding: ResponsiveHelper.cardPadding(context),
      decoration: CommonWidgets.compactCardDecoration(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('해소', style: ResponsiveHelper.subtitleStyle(context).copyWith(fontWeight: FontWeight.w700)),
        SizedBox(height: ResponsiveHelper.spacing(context, 6)),
        if (options.isEmpty)
          Text(_noOptionText, style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary))
        else if (_confirmSet != null)
          _confirmPanel()
        else ...[
          Text('원본 기록으로 확인할 해석을 고르세요. 기본 선택은 없습니다.',
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary)),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          RadioGroup<String>(
            groupValue: _selected,
            onChanged: (v) {
              if (_formLocked) return;
              setState(() {
                _selected = v;
                _invalidateConfirm();
              });
            },
            child: Column(children: [
              for (final k in options)
                RadioListTile<String>(
                  value: k,
                  enabled: !_formLocked,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(kNoShowResolutions[k]!.label, style: ResponsiveHelper.bodyStyle(context, color: AppColors.textPrimary)),
                  subtitle: Text(kNoShowResolutions[k]!.meaning, style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary)),
                ),
            ]),
          ),
          SizedBox(height: ResponsiveHelper.spacing(context, 6)),
          TextField(
            controller: _reasonCtrl,
            enabled: !_formLocked,
            maxLength: 500,
            maxLines: 3,
            minLines: 1,
            onChanged: (_) => setState(_invalidateConfirm),
            decoration: const InputDecoration(labelText: '사유(2~500자)', border: OutlineInputBorder()),
          ),
          if (_resultText != null) ...[SizedBox(height: ResponsiveHelper.spacing(context, 8)), _resultLine()],
          SizedBox(height: ResponsiveHelper.spacing(context, 8)),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: (_submitting || _selected == null || _reasonCtrl.text.trim().length < 2) ? null : _preview,
              child: Text(_submitting ? '확인 중…' : '함께 처리될 보류 확인'),
            ),
          ),
        ],
      ]),
    );
  }

  /// [.56] 이용 제한 전·후. 서버가 준 시각(ms)만 쓰고 앱이 정책으로 계산하지 않는다.
  String _restrictionText(Object? before, Object? after) {
    String at(Object v) => FormatHelper.formatKstDateTimeKorean(
        DateTime.fromMillisecondsSinceEpoch((v as num).toInt(), isUtc: true));
    if (after is num) {
      return before is num && before == after ? '그대로 — ${at(after)}까지' : '${at(after)}까지 제한됩니다';
    }
    if (before is num) return '해소 뒤 서버 미리보기에 제한 없음(지금은 ${at(before)}까지)';
    return '서버 미리보기에 제한 표시 없음';
  }

  Widget _resultLine() => Text(
        _resultText!,
        style: ResponsiveHelper.smallStyle(context, color: _resultIsWarning ? AppColors.warningDark : AppColors.successDark),
      );
}
