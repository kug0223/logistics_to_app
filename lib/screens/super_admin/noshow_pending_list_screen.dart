// [.67 NS-PENDING-LIST] 노쇼 원장 보류 — 열린 보류 목록(슈퍼관리자).
//
//   보류 처리 화면의 입구가 SA 개인 알림뿐이었다. 알림을 지우면 같은 발생은 다시 보내지 않으므로
//   열린 보류에 닿을 길이 사라졌다(Notification != Task). 이 목록은 알림과 무관하게 업무 원장
//   `noshow_ledger_pending`(status OPEN)을 그대로 읽는다.
//     · 읽기 전용이다. 해소·검증은 기존 처리 화면(NoShowPendingReviewScreen)과 서버 callable 이 한다.
//     · 규칙 후보(RHOLD: 슈퍼관리자 읽기)가 배포되기 전에는 읽기가 거절된다 — 0건으로 보이지 않고 실패로 말한다.
//     · 이름 조회 실패는 그 행의 표시만 바꾼다(보류를 숨기지 않는다).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../utils/format_helper.dart';
import '../../utils/responsive_helper.dart';
import '../../utils/text_layout.dart';
import '../../widgets/common/app_empty_state.dart';
import '../../widgets/common/app_page_scaffold.dart';
import '../../widgets/common/common_widgets.dart';
import 'noshow_pending_reads.dart';
import 'noshow_pending_review_screen.dart';

/// 목록 한 행 — 보류 문서의 읽기 전용 요약.
class NoShowOpenPending {
  const NoShowOpenPending({required this.id, required this.uid, required this.occurrence, this.reason, this.cause, this.since});
  final String id;
  final String uid;
  final int occurrence;
  final String? reason;
  final String? cause;
  final DateTime? since;

  static NoShowOpenPending? tryFrom(String id, Map<String, dynamic> d) {
    final uid = d['uid'];
    if (uid is! String || uid.isEmpty || d['status'] != 'OPEN') return null;
    final occ = d['occurrence'];
    final ts = d['firstSeenAt'] ?? d['at'];
    return NoShowOpenPending(
      id: id,
      uid: uid,
      occurrence: occ is num ? occ.toInt() : 0,
      reason: d['reason'] as String?,
      cause: d['cause'] as String?,
      since: ts is Timestamp ? ts.toDate() : null,
    );
  }
}

/// 한 번에 보이는 최대 건수. 넘으면 '일부만 보임'을 말한다(전체 수를 지어내지 않는다).
const int kNoShowPendingListLimit = 100;

class NoShowPendingListScreen extends StatefulWidget {
  const NoShowPendingListScreen({super.key, this.loadOpen, this.reads});

  /// 시험용 — null 이면 Firestore 에서 status OPEN 을 limit+1 건 읽는다.
  final Future<List<NoShowOpenPending>> Function()? loadOpen;

  /// 처리 화면과 이름 조회에 그대로 넘긴다(null 이면 실제 호출).
  final NoShowPendingReads? reads;

  @override
  State<NoShowPendingListScreen> createState() => _NoShowPendingListScreenState();
}

class _NoShowPendingListScreenState extends State<NoShowPendingListScreen> {
  List<NoShowOpenPending>? _items;
  Object? _error;
  final Map<String, String?> _labels = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<List<NoShowOpenPending>> _defaultLoad() async {
    final snap = await FirebaseFirestore.instance
        .collection('noshow_ledger_pending')
        .where('status', isEqualTo: 'OPEN')
        .limit(kNoShowPendingListLimit + 1)
        .get();
    return snap.docs.map((d) => NoShowOpenPending.tryFrom(d.id, d.data())).whereType<NoShowOpenPending>().toList();
  }

  Future<void> _load() async {
    setState(() {
      _items = null;
      _error = null;
    });
    try {
      final items = [...await (widget.loadOpen ?? _defaultLoad)()];
      // 오래된 보류가 먼저(같은 날 건별 심사 — 오래 열린 것부터)
      items.sort((a, b) => (a.since ?? DateTime(9999)).compareTo(b.since ?? DateTime(9999)));
      if (!mounted) return;
      setState(() => _items = items);
      _loadLabels(items.map((e) => e.uid).toSet());
    } catch (e) {
      debugPrint('❌ 노쇼 원장 보류 목록 조회 실패: $e');
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Future<void> _loadLabels(Set<String> uids) async {
    final label = (widget.reads ?? NoShowPendingReads.of()).targetLabel;
    if (label == null) return;
    await Future.wait(uids.where((u) => !_labels.containsKey(u)).map((u) async {
      String? v;
      try {
        v = await label(u);
      } catch (_) {
        v = null;
      }
      if (!mounted) return;
      setState(() => _labels[u] = v);
    }));
  }

  Future<void> _open(NoShowOpenPending p) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NoShowPendingReviewScreen(
          pendingId: p.id,
          occurrence: p.occurrence,
          targetUid: p.uid,
          reads: widget.reads,
        ),
      ),
    );
    // 처리 화면에서 해소했거나 그 사이 다른 관리자가 해소했을 수 있다 — 지금 상태를 다시 읽는다.
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final items = _items;
    return AppPageScaffold(
      title: '노쇼 원장 보류',
      body: _error != null
          ? AppEmptyState(
              icon: Icons.cloud_off_rounded,
              iconColor: AppColors.warning,
              title: '보류 목록을 불러오지 못했습니다',
              subtitle: '열린 보류가 없다는 뜻이 아닙니다. 다시 시도해 주세요.',
              action: TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('다시 시도')),
            )
          : items == null
              ? const Center(child: CircularProgressIndicator())
              : items.isEmpty
                  ? const AppEmptyState(
                      icon: Icons.task_alt,
                      title: '열린 보류가 없습니다',
                      subtitle: '자동으로 판정하지 못해 심사를 기다리는 노쇼 기록이 없습니다.',
                    )
                  : RefreshIndicator(onRefresh: _load, child: _list(items)),
    );
  }

  Widget _list(List<NoShowOpenPending> all) {
    final over = all.length > kNoShowPendingListLimit;
    final items = over ? all.sublist(0, kNoShowPendingListLimit) : all;
    final sp = ResponsiveHelper.spacing(context, 1);
    return ListView(
      padding: EdgeInsets.all(sp * 16),
      children: [
        Text(
          TextLayout.keepWords(over
              ? '열린 보류 $kNoShowPendingListLimit건 이상 — 오래된 순으로 $kNoShowPendingListLimit건만 보입니다. 처리하면 다음 건이 나타납니다.'
              : '열린 보류 ${items.length}건 — 알림을 지웠거나 읽었어도 여기서 처리할 수 있습니다.'),
          style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
        ),
        SizedBox(height: sp * 12),
        for (final p in items) ...[_row(p), SizedBox(height: sp * 8)],
      ],
    );
  }

  Widget _row(NoShowOpenPending p) {
    final sp = ResponsiveHelper.spacing(context, 1);
    final known = _labels.containsKey(p.uid);
    final name = _labels[p.uid];
    final who = name ?? (known ? '이름을 확인하지 못함 · ${p.uid}' : p.uid);
    return Semantics(
      button: true,
      child: InkWell(
        onTap: () => _open(p),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.all(sp * 14),
          decoration: CommonWidgets.compactCardDecoration(),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(TextLayout.keepWords(who), style: ResponsiveHelper.bodyStyle(context, fontWeight: FontWeight.w600)),
            SizedBox(height: sp * 4),
            Text(TextLayout.keepWords(noShowPendingReasonText(p.reason)), style: ResponsiveHelper.smallStyle(context, color: AppColors.textPrimary)),
            SizedBox(height: sp * 2),
            Text(
              TextLayout.keepWords([
                noShowPendingCauseText(p.cause),
                '발생 ${p.occurrence}',
                if (p.since != null) '보류 시작 ${FormatHelper.formatKstMonthDayTime(p.since!)}',
              ].join(' · ')),
              style: ResponsiveHelper.smallStyle(context, color: AppColors.textSecondary),
            ),
          ]),
        ),
      ),
    );
  }
}
