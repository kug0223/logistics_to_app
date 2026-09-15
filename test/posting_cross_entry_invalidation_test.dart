import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/controllers/workforce_controller.dart';

// ═══════════════════════════════════════════════════════════════
// POSTING-V2-02B.2 PRECISE CROSS-ENTRY INVALIDATION
//
// dataRevision은 reload synchronization 신호였다 —
// reload() caller 10곳 중 mutation이 보장되는 건 4곳뿐이고
// FCM·resume·pull-refresh·에러 재시도도 revision을 올렸다.
//
// 이제:
//   reload()             = local only
//   notifyDataChanged()  = 성공한 business mutation 전용 producer
//   origin == self       = 자기 신호 무시 (이미 local refresh를 끝냈다)
//
// 그리고 mutation이라고 모든 consumer를 깨우지 않는다 —
// Home full refresh는 2 callable + 약 4N query라
// Home truth에 영향이 없는 action(공고 탭 초대·DRAFT 삭제)은 알리지 않는다.
// ═══════════════════════════════════════════════════════════════

const _ctrlPath = 'lib/controllers/workforce_controller.dart';
const _homePath = 'lib/screens/business_admin/business_admin_home_screen.dart';
const _jobsRootPath = 'lib/screens/business_admin/jobs_root_screen.dart';
const _wfRootPath =
    'lib/screens/business_admin/workforce_management/workforce_root_screen.dart';
const _wfOpsPath =
    'lib/screens/business_admin/workforce_management/workforce_operational_view.dart';
const _listPath =
    'lib/screens/business_admin/workforce_management/workforce_list_view.dart';
const _cardPath = 'lib/widgets/admin/cards/admin_to_group_card.dart';
const _rowPath = 'lib/widgets/admin/cards/admin_work_detail.dart';
const _dialogsPath = 'lib/screens/business_admin/dialogs/to_list_dialogs.dart';
const _inviteDialogPath =
    'lib/screens/business_admin/dialogs/invite_worker_dialog.dart';
const _fnPath = 'functions/src/index.ts';

String _src(String p) => File(p).readAsStringSync();

/// `//` 주석 줄 제거 — 주석 안의 문자열이 코드로 오탐되는 것을 막는다.
String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

/// 공백 1칸 평탄화.
String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _bodyOf(String source, String signature) {
  final start = source.indexOf(signature);
  if (start == -1) throw StateError('$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = source.indexOf('(', start); i < source.length; i++) {
    if (source[i] == '(') paren++;
    if (source[i] == ')') {
      paren--;
      if (paren == 0) {
        afterParams = i;
        break;
      }
    }
  }
  final open = source.indexOf('{', afterParams);
  var depth = 0;
  for (var i = open; i < source.length; i++) {
    if (source[i] == '{') depth++;
    if (source[i] == '}') {
      depth--;
      if (depth == 0) return source.substring(start, i + 1);
    }
  }
  throw StateError('$signature 본문의 끝을 찾지 못함');
}

/// `case 'x':` 부터 다음 `break;` 까지.
String _caseOf(String source, String label) {
  final start = source.indexOf("case '$label':");
  if (start == -1) throw StateError("case '$label' 을 찾지 못함");
  final end = source.indexOf('break;', start);
  return source.substring(start, end == -1 ? source.length : end);
}

// ── consumer 재현 ─────────────────────────────────────────────
//
// 실제 WorkforceController.dataRevision / lastMutationOrigin에 붙어
// origin suppression을 동작으로 검증한다.

class _Consumer {
  final AdminMutationOrigin self;
  int refreshCount = 0;
  int _lastSeen = 0;

  _Consumer(this.self) {
    _lastSeen = WorkforceController.dataRevision.value;
    WorkforceController.dataRevision.addListener(_onRevision);
  }

  void _onRevision() {
    final rev = WorkforceController.dataRevision.value;
    if (rev <= _lastSeen) return;
    _lastSeen = rev;
    if (WorkforceController.lastMutationOrigin == self) return;
    refreshCount++;
  }

  void dispose() =>
      WorkforceController.dataRevision.removeListener(_onRevision);
}

void main() {
  final ctrl = _src(_ctrlPath);
  final ctrlCode = _codeOf(ctrl);
  final home = _src(_homePath);
  final card = _src(_cardPath);
  final cardCode = _codeOf(card);

  // ═════════════════════════════════════════════════════════════
  // 의미 분리 — reload는 local, notify만 producer
  // ═════════════════════════════════════════════════════════════
  group('dataRevision 의미 분리', () {
    test('reload()가 더 이상 revision을 올리지 않는다', () {
      final body = _codeOf(_bodyOf(ctrl, 'Future<void> reload('));
      expect(body.contains('_bumpDataRevision'), isFalse);
      expect(body.contains('dataRevision.value'), isFalse);
      expect(body.contains('_globalReloadCounter'), isFalse);
      // local reload 계약은 유지
      expect(_flat(body).contains('_onExternalReloadCallback?.call(); '
          'return load(context);'), isTrue);
    });

    test('notifyDataChanged가 유일한 producer다', () {
      // revision 증가 지점이 notifyDataChanged 안에 하나뿐
      expect(
        r'dataRevision.value = ++_globalReloadCounter;'
            .allMatches(ctrlCode)
            .length,
        1,
      );
      final notify = _codeOf(
          _bodyOf(ctrl, 'static void notifyDataChanged('));
      expect(notify.contains('_lastMutationOrigin = origin;'), isTrue);
      expect(notify.contains('dataRevision.value = ++_globalReloadCounter;'),
          isTrue);
    });

    test('origin이 필수 인자다 (무명 호출 불가)', () {
      expect(
        ctrlCode.contains(
            'static void notifyDataChanged({required AdminMutationOrigin origin})'),
        isTrue,
      );
    });

    test('load()는 revision을 올리지 않는다 — 루프 차단', () {
      final body = _codeOf(_bodyOf(ctrl, 'Future<void> _runOneLoad('));
      expect(body.contains('dataRevision'), isFalse);
      expect(body.contains('notifyDataChanged'), isFalse);
    });

    test('옛 self-bump 방어가 제거됐다 (origin으로 대체)', () {
      expect(ctrlCode.contains('wasLastGlobalBumpByMe'), isFalse);
      expect(ctrlCode.contains('_myLastBumpId'), isFalse);
      expect(ctrlCode.contains('enum AdminMutationOrigin'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // self-origin suppression — 실제 notifier로 검증
  // ═════════════════════════════════════════════════════════════
  group('self-origin suppression', () {
    late _Consumer homeC;
    late _Consumer jobsC;
    late _Consumer wfC;

    setUp(() {
      homeC = _Consumer(AdminMutationOrigin.home);
      jobsC = _Consumer(AdminMutationOrigin.jobs);
      wfC = _Consumer(AdminMutationOrigin.workforce);
    });

    tearDown(() {
      homeC.dispose();
      jobsC.dispose();
      wfC.dispose();
    });

    test('notify(home) → Home 0, Jobs 1, Workforce 1', () {
      WorkforceController.notifyDataChanged(
          origin: AdminMutationOrigin.home);
      expect(homeC.refreshCount, 0);
      expect(jobsC.refreshCount, 1);
      expect(wfC.refreshCount, 1);
    });

    test('notify(jobs) → Jobs 0, Home 1, Workforce 1', () {
      WorkforceController.notifyDataChanged(
          origin: AdminMutationOrigin.jobs);
      expect(jobsC.refreshCount, 0);
      expect(homeC.refreshCount, 1);
      expect(wfC.refreshCount, 1);
    });

    test('notify(workforce) → Workforce 0, Home 1, Jobs 1', () {
      WorkforceController.notifyDataChanged(
          origin: AdminMutationOrigin.workforce);
      expect(wfC.refreshCount, 0);
      expect(homeC.refreshCount, 1);
      expect(jobsC.refreshCount, 1);
    });

    test('연속 notify에서 각자 자기 차례의 origin을 읽는다 (동기 통지)', () {
      WorkforceController.notifyDataChanged(
          origin: AdminMutationOrigin.home);
      WorkforceController.notifyDataChanged(
          origin: AdminMutationOrigin.jobs);
      WorkforceController.notifyDataChanged(
          origin: AdminMutationOrigin.workforce);
      // home: jobs + workforce = 2
      expect(homeC.refreshCount, 2);
      // jobs: home + workforce = 2
      expect(jobsC.refreshCount, 2);
      // workforce: home + jobs = 2
      expect(wfC.refreshCount, 2);
    });

    test('ValueNotifier가 동기 통지임을 고정한다', () {
      var fired = false;
      void cb() => fired = true;
      WorkforceController.dataRevision.addListener(cb);
      WorkforceController.notifyDataChanged(
          origin: AdminMutationOrigin.jobs);
      // await 없이 이미 발화돼 있어야 한다 — 비동기 origin read 금지
      expect(fired, isTrue);
      WorkforceController.dataRevision.removeListener(cb);
    });

    test('revision은 단조 증가한다', () {
      final before = WorkforceController.dataRevision.value;
      WorkforceController.notifyDataChanged(
          origin: AdminMutationOrigin.home);
      WorkforceController.notifyDataChanged(
          origin: AdminMutationOrigin.home);
      expect(WorkforceController.dataRevision.value, before + 2);
    });

    test('dataRevision은 ValueNotifier<int> 그대로다 (새 notifier 없음)', () {
      expect(WorkforceController.dataRevision, isA<ValueNotifier<int>>());
    });
  });

  // ═════════════════════════════════════════════════════════════
  // consumer 배선
  // ═════════════════════════════════════════════════════════════
  group('consumer 배선', () {
    test('Jobs는 origin == jobs를 skip하고 load()를 쓴다', () {
      final body =
          _codeOf(_bodyOf(_src(_jobsRootPath), 'void _onDataRevisionChanged('));
      expect(
        _flat(body).contains('if (WorkforceController.lastMutationOrigin == '
            'AdminMutationOrigin.jobs) { return; }'),
        isTrue,
      );
      expect(body.contains('_controller.load(context);'), isTrue);
      expect(body.contains('_controller.reload('), isFalse,
          reason: 'consumer가 reload를 쓰면 외부 콜백까지 돈다');
    });

    // [POSTING-V2-03O.1 재작성] 공고 목록 revision consumer는 JobsRoot 하나다.
    //   두 Root가 각각 controller를 들고 같은 revision에 반응하던 구조를
    //   없앴다 — Workforce는 공유 controller를 구독만 한다.
    //   origin self-skip 계약 자체는 Jobs·Home에 그대로 남아 있다.
    test('Workforce는 공고 revision consumer가 아니다', () {
      final wf = _codeOf(_src(_wfRootPath));
      expect(wf.contains('_onDataRevisionChanged'), isFalse);
      expect(wf.contains('dataRevision.addListener'), isFalse);
      // Jobs가 workforce-origin mutation을 받는 쪽이다
      final jobs = _flat(_codeOf(
          _bodyOf(_src(_jobsRootPath), 'void _onDataRevisionChanged(')));
      expect(
        jobs.contains('if (WorkforceController.lastMutationOrigin == '
            'AdminMutationOrigin.jobs) { return; }'),
        isTrue,
      );
      expect(jobs.contains('_controller.load(context);'), isTrue);
    });

    test('Home consumer가 추가되고 origin == home을 skip한다', () {
      expect(
        home.contains(
            'WorkforceController.dataRevision.addListener(_onAdminMutation);'),
        isTrue,
      );
      expect(
        home.contains(
            'WorkforceController.dataRevision.removeListener(_onAdminMutation);'),
        isTrue,
        reason: 'dispose에서 해제하지 않으면 리스너가 샌다',
      );
      final body = _codeOf(_bodyOf(home, 'void _onAdminMutation('));
      expect(
        _flat(body).contains('if (WorkforceController.lastMutationOrigin == '
            'AdminMutationOrigin.home) { return; }'),
        isTrue,
      );
    });

    test('Home은 _autoRefresh를 재사용한다 (새 orchestration 없음)', () {
      final body = _codeOf(_bodyOf(home, 'void _onAdminMutation('));
      expect(body.contains('if (mounted) _autoRefresh();'), isTrue);
      expect(body.contains('_refresh()'), isFalse,
          reason: 'cooldown 없는 _refresh를 직접 부르면 연속 mutation에서 증폭된다');
      expect(body.contains('_loadCanonicalSummary'), isFalse);
      expect(body.contains('_loadStaffingReadiness'), isFalse);
    });

    test('Home 30초 쿨다운이 그대로다', () {
      final body = _codeOf(_bodyOf(home, 'void _autoRefresh('));
      expect(
        _flat(body).contains('if (_lastAutoRefreshAt != null && '
            'now.difference(_lastAutoRefreshAt!) < const Duration(seconds: 30)) '
            '{ return; }'),
        isTrue,
      );
    });

    test('Home pull-to-refresh는 revision을 emit하지 않는다', () {
      final body = _codeOf(_bodyOf(home, 'Future<void> _refresh('));
      expect(body.contains('notifyDataChanged'), isFalse);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // 비-mutation 경로에서 global bump 제거
  // ═════════════════════════════════════════════════════════════
  group('비-mutation 경로', () {
    // [POSTING-V2-03O.1] 공고 목록 FCM·resume owner는 JobsRoot 하나다.
    test('FCM 콜백이 revision을 만들지 않는다', () {
      final s = _codeOf(_src(_jobsRootPath));
      final idx = s.indexOf('_fcmRefreshCallback = () {');
      expect(idx, isNot(-1));
      final block = s.substring(idx, idx + 200);
      expect(block.contains('notifyDataChanged'), isFalse,
          reason: 'FCM 콜백이 global invalidation을 낸다');
      // Workforce에는 공고 FCM listener 자체가 없다
      expect(_codeOf(_src(_wfRootPath)).contains('addAdminRefreshListener'),
          isFalse);
    });

    test('resume이 revision을 만들지 않는다', () {
      final body = _codeOf(
          _bodyOf(_src(_jobsRootPath), 'void didChangeAppLifecycleState('));
      expect(body.contains('notifyDataChanged'), isFalse);
      expect(body.contains('_controller.reload(context)'), isTrue,
          reason: 'local reload 자체는 유지돼야 한다');
      // Workforce에는 공고 resume 경로가 없다
      expect(
          _codeOf(_src(_wfRootPath)).contains('didChangeAppLifecycleState'),
          isFalse);
    });

    test('공고 탭 pull-to-refresh가 revision을 만들지 않는다', () {
      final body =
          _codeOf(_bodyOf(_src(_listPath), 'Future<void> _reload('));
      expect(body.contains('notifyDataChanged'), isFalse);
      expect(body.contains('controller.reload(context)'), isTrue);
    });

    test('에러 재시도가 revision을 만들지 않는다', () {
      final body =
          _codeOf(_bodyOf(_src(_listPath), 'Widget _buildErrorState('));
      expect(body.contains('notifyDataChanged'), isFalse);
      expect(body.contains('onPressed: _reload,'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // producer — action별 설치, generic 콜백 금지
  // ═════════════════════════════════════════════════════════════
  group('producer 설치 지점', () {
    test('Home DayApplicantsDialog 성공에서 알린다', () {
      final body = _codeOf(
          _bodyOf(home, 'Future<void> _navigateToDayApplicantsForDate('));
      final flat = _flat(body);
      expect(flat.contains('unawaited(_loadStaffingReadiness());'), isTrue,
          reason: 'Home 자신의 local refresh가 사라졌다');
      expect(
        flat.contains('WorkforceController.notifyDataChanged( '
            'origin: AdminMutationOrigin.home, );'),
        isTrue,
      );
      // 성공 분기 안에만 있다
      expect('notifyDataChanged'.allMatches(body).length, 1);
      expect(flat.contains('if ((changed ?? false) && mounted) {'), isTrue);
    });

    test('Home SupportReviewQueue 성공에서 알린다', () {
      final flat = _flat(_codeOf(home));
      expect(
        flat.contains('if (changed == true && mounted) { '
            'unawaited(_loadCanonicalSummary()); '
            'WorkforceController.notifyDataChanged( '
            'origin: AdminMutationOrigin.home, ); }'),
        isTrue,
      );
    });

    test('Home 당일명단 경로는 좌석 반납 때문에 알린다', () {
      // [HOME-V2-07.1] 이 자리는 원래 '근태는 공고 카운터에 영향이 없다'는
      //   이유로 producer 부재를 고정했다. 순수 근태 편집에 대해서는 지금도
      //   맞는 말이지만, 이 다이얼로그는 NO_SHOW 좌석 반납(대체 인력 충원)
      //   경로를 함께 갖고 있다. 좌석 반납은 slot confirmed를 줄이므로
      //   공고·근무 탭과 Home의 `부족`이 같이 움직인다 — 근태 mutation이
      //   아니라 staffing mutation이다.
      final att =
          _flat(_codeOf(_bodyOf(home, 'Future<void> _openTodayAttendanceDialog(')));
      expect(att.contains('unawaited(_loadTodayAttendance());'), isTrue);
      expect(att.contains('unawaited(_loadStaffingReadiness());'), isTrue,
          reason: '좌석 반납 후 옆 숫자(부족)가 낡은 채로 남는다');
      expect(
        att.contains('WorkforceController.notifyDataChanged( '
            'origin: AdminMutationOrigin.home, );'),
        isTrue,
      );
      // 성공 분기 안에만 — 단순 열기/닫기는 아무것도 하지 않는다
      expect('notifyDataChanged'.allMatches(att).length, 1);
      expect(att.contains('if ((changed ?? false) && mounted) {'), isTrue);
    });

    test('마감 큐 / 계약 경로에는 여전히 producer가 없다', () {
      // UnclosedActionQueue 분기는 canonical summary만 갱신한다
      final flat = _flat(_codeOf(home));
      expect(
        flat.contains('final changed = await Navigator.push<bool>(context, '
            'UnclosedActionQueueScreen.route()); '
            'if (changed == true && mounted) unawaited(_loadCanonicalSummary());'),
        isTrue,
        reason: '마감 큐에 불필요한 global invalidation이 붙었다',
      );
    });

    test('Home producer 총 3곳 — 무분별 배선 아님', () {
      // DayApplicantsDialog · SupportReviewQueue
      // [HOME-V2-07.1] + 당일명단(좌석 반납) — 셋 다 실제 staffing을 바꾼다
      expect('notifyDataChanged'.allMatches(_codeOf(home)).length, 3);
    });

    test('Workforce 지원명단 성공에서 알린다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_wfOpsPath), 'Future<void> _openApplicantsDialog(')));
      expect(
        body.contains('if (changed == true && mounted) { _reload(); '
            'WorkforceController.notifyDataChanged( '
            'origin: AdminMutationOrigin.workforce, ); }'),
        isTrue,
      );
    });

    test('Posting 확정/거절(업무 row)에서 알린다', () {
      // 이 줄에는 trailing `//` 주석이 붙어 있어 _codeOf가 지우지 못한다 —
      // 두 조각을 따로 확인한다.
      final body = _flat(_codeOf(
          _bodyOf(_src(_rowPath), 'Future<void> _showApplicantsDialog(')));
      expect(body.contains('if (result != null && result.hasChanges && mounted)'),
          isTrue);
      expect(body.contains('widget.onChanged();'), isTrue);
      expect(
        body.contains('WorkforceController.notifyDataChanged( '
            'origin: AdminMutationOrigin.jobs, );'),
        isTrue,
      );
    });

    test('Posting 당일 명단 성공에서 알린다', () {
      final body =
          _flat(_codeOf(_bodyOf(card, 'Future<void> _showSlotRoster(')));
      expect(
        body.contains('if (hasChanges == true && mounted) { widget.onChanged(); '
            'WorkforceController.notifyDataChanged( '
            'origin: AdminMutationOrigin.jobs, ); }'),
        isTrue,
      );
    });

    test('공고 종료 / 재오픈 성공에서 알린다', () {
      final dialogs = _src(_dialogsPath);
      for (final sig in [
        'Future<void> showCloseTODialog(',
        'Future<void> showReopenTODialog(',
      ]) {
        final body = _flat(_codeOf(_bodyOf(dialogs, sig)));
        expect(
          body.contains('onChanged(); WorkforceController.notifyDataChanged( '
              'origin: AdminMutationOrigin.jobs, );'),
          isTrue,
          reason: '$sig 성공 분기에 invalidation이 없다',
        );
      }
    });

    test('일괄 종료 / 일괄 재오픈 성공에서 알린다', () {
      for (final label in ['batchClose', 'batchReopen']) {
        final body = _flat(_codeOf(_caseOf(card, label)));
        expect(
          body.contains('widget.onChanged(); '
              'WorkforceController.notifyDataChanged( '
              'origin: AdminMutationOrigin.jobs, );'),
          isTrue,
          reason: '$label 성공 분기에 invalidation이 없다',
        );
      }
    });

    test('공고 생성 성공에서 알린다', () {
      final body = _flat(_codeOf(_src(_jobsRootPath)));
      expect(
        body.contains('onChanged: () { if (!mounted) return; '
            '_controller.reload(context); '
            'WorkforceController.notifyDataChanged( '
            'origin: AdminMutationOrigin.jobs, ); },'),
        isTrue,
      );
    });

    test('generic onChanged 콜백에는 global notify를 달지 않았다', () {
      final list = _codeOf(_src(_listPath));
      expect(list.contains('notifyDataChanged'), isFalse,
          reason: 'workforce_list_view의 범용 _reload/onChanged에 붙었다');
      // TOGroupCard에 넘기는 onChanged 자체는 순수 local reload
      expect(_flat(list).contains('onChanged: _reload,'), isTrue);
      expect(_flat(list).contains('onAffectedTOsChanged: (_) => _reload(),'),
          isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // Home over-refresh 방지
  // ═════════════════════════════════════════════════════════════
  group('Home over-refresh 방지', () {
    test('공고 탭 인력 초대는 Home에 알리지 않는다', () {
      final body =
          _codeOf(_bodyOf(card, 'Future<void> _showInviteWorkerDialog('));
      expect(body.contains('notifyDataChanged'), isFalse,
          reason: 'Home staffing은 confirmed 기준이라 초대로 바뀌지 않는다');
      // 대신 local refresh는 복구됐다
      expect(body.contains('if (invited == true && mounted) widget.onChanged();'),
          isTrue);
    });

    test('DRAFT 삭제는 Home에 알리지 않는다', () {
      for (final label in ['batchDelete', 'delete']) {
        final body = _codeOf(_caseOf(card, label));
        expect(body.contains('notifyDataChanged'), isFalse,
            reason: '$label 이 Home full refresh를 유발한다');
      }
      final dialogs = _codeOf(
          _bodyOf(_src(_dialogsPath), 'Future<void> showDeleteTODialog('));
      expect(dialogs.contains('notifyDataChanged'), isFalse);
    });

    test('수정 / 카드명 변경 / 보낸 초대 관리도 알리지 않는다', () {
      for (final label in ['edit', 'batchEdit', 'renameCard']) {
        final body = _codeOf(_caseOf(card, label));
        expect(body.contains('notifyDataChanged'), isFalse,
            reason: '$label 에 불필요한 invalidation이 붙었다');
      }
      final sheet =
          _codeOf(_bodyOf(card, 'Future<void> _showSentInvitesSheet('));
      expect(sheet.contains('notifyDataChanged'), isFalse);
    });

    test('카드 전체에서 producer는 Home 영향 action에만 있다', () {
      // _showSlotRoster · batchClose · batchReopen · repost
      // [POSTING-V2-03R.1] + _openApplicants — collapsed `지원 현황` CTA의
      //   CONTRACT 경로. 확정·거절이 Home 인력 현황을 바꾸는 것은
      //   WorkDetailRow._showApplicantsDialog와 같은 이유다.
      expect('notifyDataChanged'.allMatches(cardCode).length, 5);
      // 새로 늘어난 자리가 실제로 지원자 처리 경로인지 확인한다.
      final opened = _codeOf(_bodyOf(card, 'Future<void> _openApplicants('));
      expect(opened.contains('WorkApplicantsDialog('), isTrue);
      expect(opened.contains('notifyDataChanged'), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // Posting local stale gap
  // ═════════════════════════════════════════════════════════════
  group('Posting local stale gap', () {
    test('초대 성공 시에만 local refresh가 돈다', () {
      final body =
          _flat(_codeOf(_bodyOf(card, 'Future<void> _showInviteWorkerDialog(')));
      expect(body.contains('final invited = await showDialog<bool>('), isTrue,
          reason: '결과를 await하지 않으면 성공을 알 수 없다');
      expect(body.contains('if (invited == true && mounted) widget.onChanged();'),
          isTrue);
    });

    test('InviteWorkerDialog가 성공 결과를 반환한다 (기존 계약)', () {
      final d = _codeOf(_src(_inviteDialogPath));
      expect(d.contains('Navigator.pop(context, true);'), isTrue);
      // 취소는 false
      expect(d.contains('Navigator.pop(context, false);'), isTrue);
    });

    test('다시 모집 성공 시 local refresh + Home invalidation', () {
      final body = _flat(_codeOf(_caseOf(card, 'repost')));
      expect(body.contains('onChanged: () { if (!mounted) return; '
          'widget.onChanged(); '
          'WorkforceController.notifyDataChanged( '
          'origin: AdminMutationOrigin.jobs, ); },'), isTrue);
    });

    test('NavigationHelper.onChanged는 result == true에서만 호출된다', () {
      final nav = _codeOf(_src('lib/utils/navigation_helper.dart'));
      expect(
        _flat(nav).contains('if (onChanged != null && result == true) { onChanged(); }'),
        isTrue,
        reason: 'success-after-write invariant의 근거가 사라졌다',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════
  // success-after-write invariant
  // ═════════════════════════════════════════════════════════════
  group('success-after-write invariant', () {
    test('모든 producer가 성공 신호 분기 안에 있다', () {
      // Home 2곳: changed == true / (changed ?? false)
      final homeCode = _codeOf(home);
      for (final m in 'notifyDataChanged'.allMatches(homeCode)) {
        final before = homeCode.substring(0, m.start);
        final lastIf = before.lastIndexOf('if (');
        expect(lastIf, isNot(-1));
        final cond = before.substring(lastIf);
        expect(cond.contains('changed'), isTrue,
            reason: 'Home producer가 성공 조건 밖에 있다');
      }
    });

    test('Workforce producer가 성공 조건 안에 있다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_wfOpsPath), 'Future<void> _openApplicantsDialog(')));
      final idx = body.indexOf('notifyDataChanged');
      expect(body.substring(0, idx).contains('if (changed == true && mounted) {'),
          isTrue);
    });

    // [POSTING-V2-03E.1 재작성] invariant는 그대로다 — 서버가 성공한 뒤에만
    // 알린다. 다만 실패를 bool false로 표현하던 삼분기(`if (success) … else`)가
    // 사라지고 early-return guard가 그 자리를 대신한다. 실패는 이제 예외다.
    test('종료/재오픈 producer가 success 분기 안에 있다', () {
      final dialogs = _src(_dialogsPath);
      for (final sig in [
        'Future<void> showCloseTODialog(',
        'Future<void> showReopenTODialog(',
      ]) {
        final body = _flat(_codeOf(_bodyOf(dialogs, sig)));
        final idx = body.indexOf('notifyDataChanged');
        expect(idx, isNot(-1));
        expect(body.substring(0, idx).contains('if (success != true) return;'),
            isTrue,
            reason: '$sig 가 서버 성공 전에 알린다');
        // 실패 경로가 producer에 도달할 수 없다
        final guardIdx = body.indexOf('if (success != true) return;');
        expect(body.substring(guardIdx, idx).contains('showError'), isFalse,
            reason: '$sig — guard 이후에는 실패 처리가 남아 있으면 안 된다');
      }
    });

    test('optimistic counter write 정책은 그대로다', () {
      final appFs = _codeOf(_src('lib/services/firestore/application_firestore.dart'));
      expect(appFs.contains('await counterBatch.commit();'), isTrue);
      expect(appFs.contains('_decrementTOConfirmed('), isTrue);
    });
  });

  // ═════════════════════════════════════════════════════════════
  // scope guard
  // ═════════════════════════════════════════════════════════════
  group('scope guard', () {
    test('새 notifier / snapshot listener 없음', () {
      for (final p in [_ctrlPath, _homePath, _jobsRootPath, _wfRootPath]) {
        final s = _codeOf(_src(p));
        expect(s.contains('.snapshots('), isFalse, reason: '$p 에 snapshot listener');
      }
      // ValueNotifier는 dataRevision 하나뿐
      expect('ValueNotifier'.allMatches(ctrlCode).length, 2,
          reason: '선언 1 + 타입 1 외에 새 notifier가 생겼다');
    });

    test('typed event taxonomy를 만들지 않았다', () {
      for (final forbidden in [
        'STAFFING_CHANGED',
        'ATTENDANCE_CHANGED',
        'APPLICATION_CHANGED',
        'MutationType',
      ]) {
        expect(ctrlCode.contains(forbidden), isFalse);
      }
    });

    test('FCM refresh type 무변경', () {
      final fcm = _codeOf(_src('lib/services/fcm_service.dart'));
      expect(
        fcm.contains("const adminRefreshTypes = {'newApplication', "
            "'applicationCanceled', 'contractSigned', 'confirmationCanceled'};"),
        isTrue,
      );
    });

    test('sent invites sheet result 계약을 만들지 않았다', () {
      // [BACKLOG-SENT-INVITES-SHEET-RESULT]
      final body =
          _codeOf(_bodyOf(card, 'Future<void> _showSentInvitesSheet('));
      expect(body.contains('DialogHelper.showSheet<void>('), isTrue);
    });

    test('FUNCTIONS 무변경', () {
      final fn = _codeOf(_src(_fnPath));
      expect(fn.contains('async function assertNoPostingRelations('), isTrue);
      expect(fn.contains('.where("status", "in", ["ACTIVE", "FULL"]),'), isTrue);
    });

    test('POSTING-V2-01A 회귀 없음', () {
      final d = _flat(_codeOf(_src(_inviteDialogPath)));
      expect(
        d.contains("'selectedWorkType': generalWd!.workType, "
            "'workDetailStartTime': generalWd.startTime, "
            "'workDetailEndTime': generalWd.endTime,"),
        isTrue,
      );
    });

    test('POSTING-V2-01B 회귀 없음', () {
      expect(ctrlCode.contains('_loadError = e;'), isTrue);
      expect(ctrlCode.contains('Object? get loadError => _loadError;'), isTrue);
      expect(_codeOf(_src(_listPath)).contains('return _buildErrorState();'),
          isTrue);
    });

    test('POSTING-V2-01C 회귀 없음', () {
      expect(cardCode.contains('if (canDelete && isDraft)'), isTrue);
    });

    test('POSTING-V2-02A 회귀 없음', () {
      expect(ctrlCode.contains('activeToCount'), isFalse);
      expect(ctrlCode.contains('maxActiveTOs'), isFalse);
      expect(_codeOf(_src(_listPath)).contains('int _visibleActiveCount('),
          isTrue);
    });
  });
}
