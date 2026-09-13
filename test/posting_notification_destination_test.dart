// [POSTING-V2-03A.1] 알림 → 정확한 대상까지
//
// 03A READ에서 확인된 precision gap 3건:
//   ① toPostingExpired — container 불일치
//        NotificationScreen → standalone JobsRootScreen (Shell 밖)
//        FCM               → Shell Jobs root
//      양쪽 모두 payload의 toId를 버려 어느 공고가 만료됐는지 알려주지 않았다.
//   ② toInviteAccepted / toInviteDeclined — entity 불일치
//        NotificationScreen → WorkApplicantsDialog + application focus
//        FCM               → Jobs root (어느 초대인지 알 수 없음)
//   ③ standalone JobsRootScreen (BUSINESS_ADMIN / SUB_ADMIN)
//        하단 탭·back 소실, 두 번째 WorkforceController, Shell Jobs stale
//
// 사전 확인으로 드러난 두 전제:
//   A. _navigateToNotificationScreen()은 payload를 dispatch하지 않는다
//      → 단순 위임만으로는 precision fix가 아니다
//   B. NotificationScreen은 Shell 위 root route다 — switchToTab만 부르면
//      overlay가 남아 사용자는 아무 변화를 보지 못한다
//
// 라우팅은 위젯 트리 없이 재현할 수 없으므로 계약을 소스로 고정하고,
// reveal 판정 로직은 순수 replica로 검증한다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _notifPath = 'lib/screens/common/notification_screen.dart';
const _fcmPath = 'lib/services/fcm_service.dart';
const _switcherPath = 'lib/utils/admin_tab_switcher.dart';
const _jobsPath = 'lib/screens/business_admin/jobs_root_screen.dart';
const _listPath =
    'lib/screens/business_admin/workforce_management/workforce_list_view.dart';
const _ctrlPath = 'lib/controllers/workforce_controller.dart';

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), true, reason: '$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

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

/// switch case 블록 — 다음 `case ` 또는 `break;` 까지.
String _caseBlock(String source, String caseLabel) {
  final start = source.indexOf(caseLabel);
  if (start == -1) throw StateError('$caseLabel 을 찾지 못함');
  final end = source.indexOf('break;', start);
  if (end == -1) throw StateError('$caseLabel 의 break를 찾지 못함');
  return source.substring(start, end);
}

// ── reveal 판정 replica ──────────────────────────────────────────
// WorkforceListView의 1회성 reveal 계약을 그대로 옮긴다.

typedef _Item = ({String id, bool isClosed, bool matchesFilters});

/// 필터 술어를 1회성으로 우회하고 target을 맨 위로 올린다.
List<String> _renderedIds(
  List<_Item> all, {
  required bool closedTab,
  String? revealToId,
}) {
  final source =
      all.where((g) => closedTab ? g.isClosed : !g.isClosed).toList();
  final filtered = source
      .where((g) => g.id == revealToId || g.matchesFilters)
      .toList();
  if (revealToId != null) {
    final idx = filtered.indexWhere((g) => g.id == revealToId);
    if (idx > 0) {
      final t = filtered.removeAt(idx);
      filtered.insert(0, t);
    }
  }
  return filtered.map((g) => g.id).toList();
}

void main() {
  // ── §10.A 사전 확인 고정 ────────────────────────────────────────
  group('NAV-00 사전 확인', () {
    test('00-a _navigateToNotificationScreen이 payload를 dispatch할 수 있다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_fcmPath), 'void _navigateToNotificationScreen(')));
      expect(
          body.contains(
              'NotificationScreen(autoDispatchPayload: autoDispatchPayload)'),
          true,
          reason: '목록만 열면 사용자가 같은 알림을 한 번 더 눌러야 한다');
    });

    test('00-b NotificationScreen이 payload를 canonical handler로 흘린다', () {
      final code = _codeOf(_src(_notifPath));
      expect(code.contains('final Map<String, dynamic>? autoDispatchPayload;'),
          true);
      final body = _flat(_codeOf(
          _bodyOf(_src(_notifPath), 'Future<void> _dispatchInitialPayload(')));
      expect(body.contains('await _handleNotificationTap(context, synthetic, provider);'),
          true, reason: '새 라우팅 로직을 복제하면 안 된다 — 기존 dispatcher 재사용');
      expect(body.contains("(payload['type'] ?? payload['screen'])?.toString()"),
          true);
    });

    test('00-c id가 없을 때만 읽음 처리를 건너뛴다', () {
      final body = _codeOf(_bodyOf(_src(_notifPath), 'Future<void> _handleNotificationTap('));
      expect(
          _flat(body).contains('if (notification.id.isNotEmpty) { '
              'provider.markAsRead(notification.id).catchError((_) {}); }'),
          true,
          reason: 'Firestore 문서 id가 없는 합성 모델로 write를 시도하면 안 된다');
    });

    test('00-d Shell 탭 전환 후 알림 overlay를 닫는다', () {
      final block = _flat(_codeOf(
          _caseBlock(_src(_notifPath), 'case NotificationType.toPostingExpiringTomorrow:')));
      expect(block.contains('if (switched) { Navigator.of(context).pop();'), true,
          reason: 'overlay가 남으면 사용자는 Jobs 탭을 보지 못한다');
    });
  });

  // ── §2 invite exact entity ──────────────────────────────────────
  group('NAV-01 초대 알림이 정확한 지원자까지 간다', () {
    test('01-a FCM이 Jobs root로 가지 않는다', () {
      final block = _flat(_codeOf(_caseBlock(_src(_fcmPath), "case 'toInviteAccepted':")));
      expect(block.contains('switchToTab(AdminTabSwitcher.jobsTab)'), false,
          reason: 'root만 열면 어느 초대인지 알 수 없다');
      expect(
          block.contains('_navigateToNotificationScreen(autoDispatchPayload: data)'),
          true);
    });

    test('01-b NotificationScreen의 exact resolver가 canonical로 남아 있다', () {
      final code = _codeOf(_src(_notifPath));
      expect(code.contains('Future<void> _openWorkApplicantsFromNotification('), true);
      final block = _codeOf(
          _caseBlock(_src(_notifPath), 'case NotificationType.toInviteAccepted:'));
      expect(block.contains('_openWorkApplicantsFromNotification(context, notification)'),
          true);
    });

    test('01-c applicationId 역추적 fallback 무변경', () {
      final body = _codeOf(_bodyOf(
          _src(_notifPath), 'Future<void> _openWorkApplicantsFromNotification('));
      expect(body.contains("var toId = data['toId']?.toString();"), true);
      expect(body.contains("final applicationId = data['applicationId']?.toString();"),
          true);
      expect(body.contains("collection('applications')"), true,
          reason: 'CALLER1-PATCH 역추적 경로가 사라졌다');
      // businessId 바인딩 보안 검증 유지
      expect(body.contains('appBusinessId != fallbackBusinessId'), true);
    });

    test('01-d 두 진입이 같은 resolver로 수렴한다', () {
      // FCM → autoDispatch → _handleNotificationTap → 같은 case → 같은 resolver
      final fcmBlock =
          _flat(_codeOf(_caseBlock(_src(_fcmPath), "case 'toInviteAccepted':")));
      expect(fcmBlock.contains('autoDispatchPayload: data'), true);
      final notifCode = _flat(_codeOf(_src(_notifPath)));
      expect(
          notifCode.contains('case NotificationType.toInviteAccepted: '
              'case NotificationType.toInviteDeclined:'),
          true,
          reason: '두 타입이 한 case로 묶여 있어야 결과가 같다');
    });
  });

  // ── §3 posting expired exact TO ─────────────────────────────────
  group('NAV-02 공고 만료 알림이 해당 공고까지 간다', () {
    test('02-a NotificationScreen이 toId를 소비한다', () {
      final block = _flat(_codeOf(_caseBlock(
          _src(_notifPath), 'case NotificationType.toPostingExpiringTomorrow:')));
      expect(block.contains("final expiredToId = notification.data?['toId']?.toString();"),
          true);
      expect(block.contains('switchToJobsWithTarget(expiredToId)'), true);
    });

    test('02-b FCM도 toId를 소비한다', () {
      final block = _flat(_codeOf(_caseBlock(_src(_fcmPath), "case 'toDetail':")));
      expect(block.contains("final expiredToId = data['toId']?.toString();"), true);
      expect(block.contains('switchToJobsWithTarget(expiredToId)'), true);
    });

    test('02-c BUSINESS_ADMIN / SUB_ADMIN은 Shell 탭으로 통일된다', () {
      final block = _flat(_codeOf(_caseBlock(
          _src(_notifPath), 'case NotificationType.toPostingExpiringTomorrow:')));
      expect(block.contains('final switched = !isSuper &&'), true);
      expect(block.contains('AdminTabSwitcher.instance .switchToJobsWithTarget(expiredToId)'),
          true);
    });

    test('02-d SUPER_ADMIN은 standalone 유지', () {
      final block = _flat(_codeOf(_caseBlock(
          _src(_notifPath), 'case NotificationType.toPostingExpiringTomorrow:')));
      expect(
          block.contains(
              'final isSuper = context.read<UserProvider>().currentUser?.isSuperAdmin == true;'),
          true);
      expect(
          block.contains(
              'builder: (_) => JobsRootScreen(initialTargetToId: expiredToId),'),
          true,
          reason: 'standalone에도 target을 전달해야 확인 가능하다');
    });

    test('02-e 07 expiringTomorrow emitter를 만들지 않았다', () {
      final fns = _src('functions/src/index.ts');
      expect(fns.contains('type: "toPostingExpiringTomorrow"'), false,
          reason: '[BACKLOG-POSTING-EXPIRING-TOMORROW-NO-EMITTER] 유지');
      // 공통 lifecycle case에 함께 존재하는 것은 허용
      expect(
          _codeOf(_src(_notifPath))
              .contains('case NotificationType.toPostingExpiringTomorrow:'),
          true);
    });
  });

  // ── §3, §8 filter 비파괴 ────────────────────────────────────────
  group('NAV-03 1회성 reveal이 persistent filter를 바꾸지 않는다', () {
    const items = [
      (id: 'A', isClosed: false, matchesFilters: true),
      (id: 'B', isClosed: false, matchesFilters: false), // 필터에 가려진 target
      (id: 'C', isClosed: false, matchesFilters: true),
    ];

    test('03-a 필터에 가려진 target이 보인다', () {
      expect(_renderedIds(items, closedTab: false), ['A', 'C']);
      expect(_renderedIds(items, closedTab: false, revealToId: 'B'),
          ['B', 'A', 'C'],
          reason: 'target이 보이고 맨 위에 온다');
    });

    test('03-b reveal 해제 후 원래 필터 결과로 돌아온다', () {
      expect(_renderedIds(items, closedTab: false, revealToId: null),
          ['A', 'C']);
    });

    test('03-c controller의 filter 값을 건드리지 않는다', () {
      final body = _codeOf(_bodyOf(
          _src(_listPath), 'List<TOGroupItem> _computeFilteredItems('));
      for (final forbidden in [
        'setBusinessIdFilter',
        'setDateRangeFilter',
        'setTOTypeFilter',
        'setPublishStatusFilter',
        'clearFilters',
      ]) {
        expect(body.contains(forbidden), false,
            reason: 'reveal이 사용자의 persistent filter를 $forbidden 로 바꾼다');
      }
      expect(
          _flat(body).contains(
              '.where((g) => g.id == reveal || _matchesFilters(g, controller));'),
          true);
    });

    test('03-d Jobs target 경로 어디에도 filter setter가 없다', () {
      final switcher = _codeOf(_bodyOf(_src(_switcherPath), 'bool switchToJobsWithTarget('));
      expect(switcher.contains('Filter'), false);
      final jobs = _codeOf(_src(_jobsPath));
      final handlerIdx = jobs.indexOf('_onJobsTarget = (toId)');
      expect(handlerIdx, greaterThan(-1));
      final handler = jobs.substring(handlerIdx, handlerIdx + 200);
      expect(handler.contains('setBusinessIdFilter'), false);
      expect(handler.contains('setDateRangeFilter'), false);
    });

    test('03-e 사용자가 탭·필터를 건드리면 reveal이 해제된다', () {
      final code = _flat(_codeOf(_src(_listPath)));
      // 탭 전환 / 새로고침 / 필터 변경 4종
      expect('_clearReveal();'.allMatches(code).length, greaterThanOrEqualTo(6));
      final clear = _flat(_codeOf(_bodyOf(_src(_listPath), 'void _clearReveal(')));
      expect(clear.contains('_revealToId = null;'), true);
      expect(clear.contains('Filter'), false,
          reason: 'reveal 해제가 사용자 필터까지 초기화하면 안 된다');
    });
  });

  // ── §4 target 식별 / 탭 / 펼침 ──────────────────────────────────
  group('NAV-04 target 식별과 reveal 동작', () {
    test('04-a 마감된 공고면 마감됨 탭으로 맞춘다', () {
      const closedTarget = [
        (id: 'A', isClosed: false, matchesFilters: true),
        (id: 'B', isClosed: true, matchesFilters: true),
      ];
      // 진행중 탭에서는 B가 렌더되지 않는다 → 탭 전환이 필요하다
      expect(_renderedIds(closedTarget, closedTab: false, revealToId: 'B'),
          ['A']);
      expect(_renderedIds(closedTarget, closedTab: true, revealToId: 'B'),
          ['B']);
      final body = _flat(_codeOf(
          _bodyOf(_src(_listPath), 'void _resolveRevealTarget(')));
      expect(
          body.contains(
              'final targetTab = found.isClosed ? TOStatus.closed : TOStatus.active;'),
          true);
    });

    test('04-b target 카드를 펼친다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_listPath), 'void _resolveRevealTarget(')));
      expect(body.contains('_expandedGroups ..clear() ..add(foundItem.id);'), true);
      expect(body.contains('_activeGroupKey = foundItem.id;'), true);
    });

    test('04-c 로드 완료 후 1회만 해석한다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_listPath), 'void _resolveRevealTarget(')));
      expect(body.contains('if (target == null || _revealResolved) return;'), true);
      expect(body.contains('if (controller.isLoading) return;'), true);
      expect(body.contains('_revealResolved = true;'), true);
    });

    test('04-d GlobalKey/ensureVisible 대신 순서를 바꾼다 (§4 최소 구현)', () {
      final code = _codeOf(_src(_listPath));
      expect(code.contains('ensureVisible'), false);
      expect(code.contains('GlobalKey'), false);
      final lift = _flat(_codeOf(_bodyOf(_src(_listPath), 'void _liftRevealTarget(')));
      expect(lift.contains('items.insert(0, target);'), true);
    });
  });

  // ── §5 not found fallback ───────────────────────────────────────
  group('NAV-05 target을 찾지 못하면 명시적으로 알린다', () {
    test('05-a 기존 알림 경로와 같은 문구를 쓴다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_listPath), 'void _resolveRevealTarget(')));
      expect(body.contains("'공고를 찾을 수 없습니다'"), true);
      expect(body.contains("'공고 데이터를 불러올 수 없습니다'"), true);
      // 원본 문구와 일치하는지
      final notif = _codeOf(_src(_notifPath));
      expect(notif.contains("ToastHelper.showError('공고를 찾을 수 없습니다')"), true);
      expect(notif.contains("ToastHelper.showError('공고 데이터를 불러올 수 없습니다')"),
          true);
    });

    test('05-b 다른 공고를 추측해서 열지 않는다', () {
      final body = _codeOf(_bodyOf(_src(_listPath), 'void _resolveRevealTarget('));
      expect(body.contains('.first'), false);
      expect(body.contains('found == null'), true);
      expect(_flat(body).contains('setState(_clearReveal);'), true,
          reason: '실패 후 reveal 상태가 남으면 안 된다');
    });

    test('05-c 조용히 root를 여는 것으로 실패를 숨기지 않는다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_listPath), 'void _resolveRevealTarget(')));
      final nullIdx = body.indexOf('if (found == null)');
      final toastIdx = body.indexOf('ToastHelper.showError', nullIdx);
      expect(nullIdx, greaterThan(-1));
      expect(toastIdx, greaterThan(nullIdx));
    });
  });

  // ── §4 standalone 핸들러 충돌 ───────────────────────────────────
  group('NAV-06 standalone 인스턴스가 Shell 등록을 지우지 않는다', () {
    test('06-a target 핸들러는 identity 기반으로 해제된다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_switcherPath), 'void unregisterJobsTargetHandler(')));
      expect(body.contains('if (identical(_jobsTargetFn, fn)) _jobsTargetFn = null;'),
          true);
    });

    test('06-b JobsRootScreen이 자기 핸들러를 넘겨 해제한다', () {
      final code = _flat(_codeOf(_src(_jobsPath)));
      expect(code.contains('registerJobsTargetHandler(_onJobsTarget)'), true);
      expect(code.contains('unregisterJobsTargetHandler(_onJobsTarget)'), true);
    });

    test('06-c 기존 dead intent(_jobsNavFn)는 건드리지 않았다 (§9)', () {
      final code = _codeOf(_src(_switcherPath));
      expect(code.contains('void unregisterJobsNavHandler() => _jobsNavFn = null;'),
          true);
      expect(
          code.contains(
              'bool switchToJobsWithIntent({ required DateTimeRange dateRange, String? businessId, })') ||
              code.contains('bool switchToJobsWithIntent({'),
          true,
          reason: 'dead intent를 삭제하거나 재설계하지 않는다');
    });
  });

  // ── BLOCKER 1: lifecycle READ gate가 02G canonical과 맞는가 ─────
  group('NAV-10 공고 만료 알림은 READ gate를 쓴다', () {
    test('10-a lifecycle은 membership만 검증한다', () {
      final block = _flat(_codeOf(_caseBlock(
          _src(_notifPath), 'case NotificationType.toPostingExpiringTomorrow:')));
      expect(block.contains('_validateAdminNotificationAccess('), true,
          reason: '멤버십 검증까지 없애면 scope 밖 사업장이 열린다');
      expect(block.contains('requiredPermission:'), false,
          reason: '공고를 여는 것은 READ다 — canManageTo를 요구하면 '
              'membership만 있는 사업장이 FCM과 다른 결과를 낸다');
    });

    test('10-b requiredPermission이 없으면 permission 단계가 생략된다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_notifPath),
          'Future<_AdminAccessResult> _validateAdminNotificationAccess(')));
      // 멤버십은 항상 검증
      expect(body.contains('subAdminBusinessIds.contains(businessId)'), true);
      expect(body.contains('return _AdminAccessResult.noBusinessAccess;'), true);
      // permission 단계는 requiredPermission이 있을 때만
      expect(body.contains('if (requiredPermission != null &&'), true);
    });

    test('10-c BUSINESS_ADMIN / SUPER_ADMIN은 그대로 통과한다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_notifPath),
          'Future<_AdminAccessResult> _validateAdminNotificationAccess(')));
      expect(body.contains('if (!up.isSubAdmin) return _AdminAccessResult.allowed;'),
          true);
    });

    test('10-d application 계열 알림의 권한은 건드리지 않았다', () {
      final code = _flat(_codeOf(_src(_notifPath)));
      // newApplication / toInviteAccepted 등은 여전히 canManageTo를 요구한다
      expect(
          'requiredPermission: (p) => p.canManageTo,'.allMatches(code).length,
          greaterThanOrEqualTo(3),
          reason: 'lifecycle 외 알림의 권한 계약까지 바뀌었다');
      final invite = _flat(_codeOf(
          _caseBlock(_src(_notifPath), 'case NotificationType.toInviteAccepted:')));
      expect(invite.contains('requiredPermission: (p) => p.canManageTo,'), true);
      final newApp = _flat(_codeOf(
          _caseBlock(_src(_notifPath), 'case NotificationType.newApplication:')));
      expect(newApp.contains('requiredPermission: (p) => p.canManageTo,'), true);
    });

    test('10-e mutation은 여전히 canManageTo가 막는다', () {
      final card =
          _codeOf(_src('lib/widgets/admin/cards/admin_to_group_card.dart'));
      expect(
          card.contains('up.canForBusiness(widget.groupItem.businessId, '
              '(p) => p.canManageTo)'),
          true,
          reason: 'READ gate를 풀면서 WRITE gate까지 풀리면 안 된다');
    });
  });

  // ── BLOCKER 2: 읽음 처리 parity ─────────────────────────────────
  group('NAV-11 FCM tap과 알림함 tap의 읽음 처리가 같다', () {
    test('11-a 서버가 payload에 notificationId를 싣는다', () {
      final fns = _src('functions/src/index.ts');
      expect(fns.contains('document: "users/{userId}/notifications/{notificationId}"'),
          true);
      expect(
          _flat(fns).contains('const fcmData: Record<string, string> = { '
              'notificationId: notificationId,'),
          true,
          reason: 'client-only 수정의 전제가 사라졌다');
    });

    test('11-b 합성 모델이 그 id를 쓴다', () {
      final body = _flat(_codeOf(
          _bodyOf(_src(_notifPath), 'Future<void> _dispatchInitialPayload(')));
      expect(body.contains("payload['notificationId']?.toString() ?? ''"), true);
    });

    test('11-c 알림함을 거치지 않는 FCM 경로도 읽음 처리한다', () {
      final block = _flat(_codeOf(_caseBlock(_src(_fcmPath), "case 'toDetail':")));
      expect(block.contains('if (switched) { _markNotificationReadFromPayload(data);'),
          true);
    });

    test('11-d id가 없으면 아무 문서도 읽음 처리하지 않는다 (§CASE C 금지)', () {
      final body = _flat(_codeOf(_bodyOf(
          _src(_fcmPath), 'void _markNotificationReadFromPayload(')));
      expect(
          body.contains(
              'if (uid == null || notificationId == null || notificationId.isEmpty) return;'),
          true);
      // 추정 query 금지 — 최신 unread 하나 고르기 등
      for (final forbidden in [
        'orderBy',
        'where(',
        'limit(',
        'isRead',
      ]) {
        expect(body.contains(forbidden), false,
            reason: '$forbidden — 어느 알림인지 추측하면 엉뚱한 문서를 읽음 처리한다');
      }
      expect(body.contains('markNotificationAsRead(uid, notificationId)'), true);
    });

    test('11-e 다른 FCM route의 읽음 처리를 바꾸지 않았다', () {
      final code = _codeOf(_src(_fcmPath));
      expect('_markNotificationReadFromPayload('.allMatches(code).length, 2,
          reason: '정의 1 + toDetail 1 — unrelated 타입까지 손대면 안 된다');
    });
  });

  // ── §6 permission 무회귀 ────────────────────────────────────────
  group('NAV-07 02G permission 계약 무회귀', () {
    test('07-a 접근 검증 자체는 남아 있다', () {
      final block = _flat(_codeOf(_caseBlock(
          _src(_notifPath), 'case NotificationType.toPostingExpiringTomorrow:')));
      expect(block.contains('_validateAdminNotificationAccess('), true);
      expect(block.contains('if (_handleAdminAccess(access))'), true);
    });

    test('07-b SubAdmin 사업장별 검증 무변경', () {
      final body = _codeOf(_bodyOf(
          _src(_notifPath), 'Future<_AdminAccessResult> _validateAdminNotificationAccess('));
      expect(body.contains('subAdminBusinessIds.contains(businessId)'), true);
      expect(body.contains('MemberService().getMemberPermissions(businessId, uid)'),
          true);
    });

    test('07-c 카드 권한은 여전히 대상 사업장 기준 (02G.1)', () {
      final card =
          _codeOf(_src('lib/widgets/admin/cards/admin_to_group_card.dart'));
      expect(
          card.contains('up.canForBusiness(widget.groupItem.businessId, '
              '(p) => p.canManageTo)'),
          true,
          reason: 'navigation 경로가 permission context를 우회하면 안 된다');
    });

    test('07-d application 계열의 read-only 차단은 유지된다', () {
      // lifecycle(READ)만 membership으로 풀었다. 관리 action surface를 여는
      // application 계열은 여전히 대상 사업장 canManageTo를 요구한다.
      // → [BACKLOG-NOTIFICATION-READONLY-BUSINESS-BLOCKED]는 그 범위로 축소된다.
      final body = _codeOf(_bodyOf(
          _src(_notifPath), 'Future<void> _openWorkApplicantsFromNotification('));
      expect(body.contains('canManageTo'), true);
    });
  });

  // ── §8 freshness / 중복 controller ──────────────────────────────
  group('NAV-08 Shell 통일 효과', () {
    test('08-a BUSINESS_ADMIN/SUB_ADMIN은 standalone을 만들지 않는다', () {
      final block = _flat(_codeOf(_caseBlock(
          _src(_notifPath), 'case NotificationType.toPostingExpiringTomorrow:')));
      // standalone push는 switched == false 일 때만 — SUPER_ADMIN/Shell 미활성
      final elseIdx = block.indexOf('} else {');
      final pushIdx = block.indexOf('Navigator.push(');
      expect(elseIdx, greaterThan(-1));
      expect(pushIdx, greaterThan(elseIdx),
          reason: 'standalone이 기본 경로로 남아 있다');
    });

    test('08-b mutation invalidation 계약 무변경', () {
      final code = _codeOf(_src(_ctrlPath));
      expect(
          code.contains(
              'static void notifyDataChanged({required AdminMutationOrigin origin})'),
          true);
      final jobs = _codeOf(_src(_jobsPath));
      expect(
          jobs.contains(
              'if (WorkforceController.lastMutationOrigin == AdminMutationOrigin.jobs)'),
          true,
          reason: '02B.2 계약을 바꾸지 않는다 — 중복 인스턴스 제거로 해소한다');
    });

    test('08-c JobsRootScreen 생성 지점이 둘뿐이다', () {
      var hits = 0;
      for (final f in Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))) {
        final code = _codeOf(f.readAsStringSync());
        hits += 'JobsRootScreen('.allMatches(code).length;
      }
      // const ctor 1 + Shell 탭 1 + NotificationScreen fallback 1
      expect(hits, 3, reason: 'standalone 진입점이 늘었다');
    });
  });

  // ── §9 범위 밖 무변경 ───────────────────────────────────────────
  group('NAV-09 범위 밖 무변경', () {
    test('09-a Functions 무변경', () {
      final fns = _src('functions/src/index.ts');
      expect(fns.contains('type: "toPostingExpired"'), true);
      expect(fns.contains('screen: "toDetail"'), true);
      expect(fns.contains('type:      "toInviteAccepted"'), true);
    });

    test('09-b payload를 확장하지 않았다', () {
      final fns = _src('functions/src/index.ts');
      final idx = fns.indexOf('type: "toPostingExpired"');
      final block = fns.substring(idx, idx + 320);
      expect(block.contains('toId: doc.id'), true);
      expect(block.contains('businessId: d.businessId'), true);
    });

    test('09-c 다른 FCM route를 건드리지 않았다', () {
      final code = _codeOf(_src(_fcmPath));
      for (final keep in [
        "case 'newApplication':",
        "case 'applicationCanceled':",
        "case 'confirmationCanceled':",
        "case 'interimSettlementAdmin':",
      ]) {
        expect(code.contains(keep), true, reason: '$keep 이 사라졌다');
      }
    });

    test('09-d read scope / empty state / scope label 무변경', () {
      final ctrl = _flat(_codeOf(_bodyOf(_src(_ctrlPath), 'Future<void> load(')));
      expect(ctrl.contains('businessIds = user.subAdminBusinessIds;'), true);
      final list = _codeOf(_src(_listPath));
      expect(list.contains('_PostingEmptyKind.root'), true);
      expect(list.contains("title = '등록된 공고가 없습니다';") ||
              list.contains("'등록된 공고가 없습니다',"),
          true);
      final jobs = _codeOf(_src(_jobsPath));
      expect(jobs.contains('resolveAdminBusinessScopeLabel('), true);
    });
  });
}
