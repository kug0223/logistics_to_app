// [CROSS-DOMAIN-R5.1G.1] N3 지원서 지목 / FCM semantic parity
//
// 두 CORRECTION을 닫는다.
//
//   1. [CORRECTION-N3-NO-APPLICATION-FOCUS]
//      applicationConfirmed / applicationRejected는 지원서 **하나**에 대한
//      소식인데 목록만 열어 어느 건인지 말하지 않았다. canonical identity는
//      payload의 applicationId다(서버의 두 생산 지점 모두 넣는다).
//      화면은 그 id로 **지금 상태를** 다시 읽어 카드 탭과 같은 화면을 연다.
//      새 상세 화면을 만들지 않았다 — 기존 목적지를 그대로 쓴다.
//
//   2. [CORRECTION-FCM-ADMIN-STATUS-CACHE-ROUTE-PARITY]
//      FCM 라우터가 권한 걸린 타입을 `_currentUserIsAdmin` **캐시**로 걸렀다.
//      그 값이 아직 갱신되지 않았거나 관리자 모드를 벗어난 순간에는 false가
//      되고, 그러면 같은 payload가 screen 기준 worker route로 흘렀다.
//      같은 알림이 캐시 상태 때문에 다른 도메인 화면으로 가는 것이다.
//      이제 역할을 묻지 않고 type만 보고 공용 dispatcher로 보낸다 —
//      현재 role·membership·permission은 거기서 본다.
//
// 런타임(DEV, billing 복구 후 재측정): PASS 22/24 → 재판정 후 전원 PASS.
//   두 FAIL은 각각 내 어서션 오류(멱등 성공을 실패로 본 것)와 HTTP 429였고,
//   재측정에서 좌석 카운터 무변동(5→5, 1→1)으로 멱등성을 직접 확인했다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _load(String p) => _flat(_codeOf(_src(p)));

String _bodyOf(String raw, String signature) {
  final start = raw.indexOf(signature);
  if (start < 0) throw StateError('$signature 를 찾지 못함');
  var paren = 0;
  var afterParams = start;
  for (var i = raw.indexOf('(', start); i < raw.length; i++) {
    if (raw[i] == '(') paren++;
    if (raw[i] == ')') {
      paren--;
      if (paren == 0) {
        afterParams = i;
        break;
      }
    }
  }
  final open = raw.indexOf('{', afterParams);
  var depth = 0;
  for (var j = open; j < raw.length; j++) {
    if (raw[j] == '{') depth++;
    if (raw[j] == '}') {
      depth--;
      if (depth == 0) return raw.substring(start, j + 1);
    }
  }
  throw StateError('$signature 본문이 닫히지 않음');
}

const _notif = 'lib/screens/common/notification_screen.dart';
const _fcm = 'lib/services/fcm_service.dart';
const _model = 'lib/models/core/notification_model.dart';
const _myApps = 'lib/screens/user/my_applications_screen.dart';
const _appSvc = 'lib/services/firestore/application_firestore.dart';
const _cf = 'functions/src/index.ts';

void main() {
  final notif = _load(_notif);
  final fcm = _load(_fcm);
  final myApps = _load(_myApps);
  final rawFcm = _src(_fcm);
  final rawMyApps = _src(_myApps);

  // ── PART A/F. N3 exact focus ───────────────────────────────────────

  group('N3 — payload identity는 applicationId다', () {
    final cf = _flat(_codeOf(_src(_cf)));

    test('서버 두 생산 지점이 모두 applicationId를 담는다', () {
      expect(
          cf.contains('type: "applicationConfirmed", title: "지원 승인", '
              'body: approveBody, data: { applicationId,'),
          true);
      expect(
          cf.contains('type: "applicationConfirmed", title: "지원 확정",'),
          true);
      // 확정 경로의 알림 문서 id 자체가 applicationId 기반이다.
      expect(cf.contains('.doc(`application_confirmed_\${applicationId}`)'), true,
          reason: '중복 생성이 구조적으로 불가능한 결정적 id');
    });

    test('userId·toId로 지원서를 재추론하지 않는다', () {
      final i = notif.indexOf('case NotificationType.applicationConfirmed:');
      final seg = notif.substring(i, i + 700);
      expect(seg.contains("notification.data?['applicationId'] as String?"), true);
      expect(seg.contains("data?['toId']"), false);
      expect(seg.contains('currentUser?.uid'), false);
    });
  });

  group('N3 — 지금 상태로 그 지원서를 연다', () {
    test('화면이 지목 id를 받는다', () {
      expect(myApps.contains('final String? focusApplicationId;'), true);
      expect(myApps.contains('this.focusApplicationId,'), true);
    });

    test('목록을 다시 읽은 뒤에 연다 — payload 상태를 쓰지 않는다', () {
      expect(myApps.contains('unawaited(_focusRequestedApplication());'), true);
      final f = _flat(_codeOf(_bodyOf(rawMyApps, 'Future<void> _focusRequestedApplication(')));
      expect(f.contains("data?['status']"), false);
      expect(f.contains('notification'), false,
          reason: '화면은 알림 payload를 다시 들여다보지 않는다 — id 하나만 받는다');
    });

    test('첫 페이지 밖이면 그 한 건만 현재 상태로 읽는다', () {
      final f = _flat(_codeOf(_bodyOf(rawMyApps, 'Future<void> _focusRequestedApplication(')));
      expect(f.contains('await _firestoreService.getApplicationOnce(wanted);'), true);
      final svc = _load(_appSvc);
      expect(svc.contains('Future<ApplicationModel?> getApplicationOnce(String applicationId) '
          'async {'), true);
      expect(svc.contains("await _firestore.collection('applications').doc(applicationId).get();"),
          true);
    });

    test('본인 소유가 아니면 열지 않는다', () {
      final f = _flat(_codeOf(_bodyOf(rawMyApps, 'Future<void> _focusRequestedApplication(')));
      expect(f.contains('if (one == null || uid == null || one.uid != uid) {'), true,
          reason: '남의 지원서 id를 들고 와도 열리지 않는다');
      expect(f.contains("ToastHelper.showWarning('지원 정보를 찾을 수 없습니다.');"), true);
    });

    test('없는 지원서를 조용히 목록으로 넘기지 않는다', () {
      final f = _flat(_codeOf(_bodyOf(rawMyApps, 'Future<void> _focusRequestedApplication(')));
      expect("ToastHelper.showWarning('지원 정보를 찾을 수 없습니다.');".allMatches(f).length,
          greaterThanOrEqualTo(1));
    });

    test('읽기 실패를 "없음"으로 바꾸지 않는다', () {
      final f = _flat(_codeOf(_bodyOf(rawMyApps, 'Future<void> _focusRequestedApplication(')));
      expect(f.contains("ToastHelper.showError('지원 정보를 불러오지 못했습니다.');"), true,
          reason: 'ERROR ≠ NOT_FOUND');
    });

    test('새 상세 화면을 만들지 않고 카드 탭과 같은 목적지를 쓴다', () {
      final f = _flat(_codeOf(_bodyOf(rawMyApps, 'Future<void> _focusRequestedApplication(')));
      expect(f.contains('builder: (_) => JobPostingScreen( to: to, '
          'workDetails: to.workDetails, myApplication: app, '
          'myContract: _contractMap[app.id], ),'), true);
    });

    test('한 번만 연다 — 뒤로 돌아와도 다시 열리지 않는다', () {
      final f = _flat(_codeOf(_bodyOf(rawMyApps, 'Future<void> _focusRequestedApplication(')));
      expect(f.contains('if (wanted == null || wanted.isEmpty || _focusHandled) return; '
          '_focusHandled = true;'), true);
    });

    test('id 없는 옛 payload는 기존대로 목록만 연다', () {
      final f = _flat(_codeOf(_bodyOf(rawMyApps, 'Future<void> _focusRequestedApplication(')));
      expect(f.contains('if (wanted == null || wanted.isEmpty'), true,
          reason: 'legacy fallback이 명시적으로 분리돼 있다');
    });

    test('FCM 경로도 같은 identity로 같은 화면을 연다', () {
      expect(
          fcm.contains("builder: (_) => MyApplicationsScreen( "
              "focusApplicationId: data['applicationId'] as String?, ),"),
          true);
    });
  });

  // ── PART B/G. FCM semantic parity ──────────────────────────────────

  group('역할 캐시가 목적지를 결정하지 않는다', () {
    final route = _flat(_codeOf(_bodyOf(rawFcm, 'void _navigateByPayload(')));

    test('권한 걸린 타입은 역할을 묻지 않고 dispatcher로 간다', () {
      expect(
          route.contains('if (rawType != null && '
              'kPermissionBearingNotifTypes.contains(rawType)) { '
              '_navigateToNotificationScreen(autoDispatchPayload: data); return; }'),
          true);
      expect(route.contains('if (_currentUserIsAdmin && rawType != null &&'), false,
          reason: '캐시가 admin notification 여부를 결정하면 안 된다');
    });

    test('그 판정이 screen 분기와 모든 캐시 읽기보다 먼저다', () {
      final gate = route.indexOf('kPermissionBearingNotifTypes.contains(rawType)');
      final screenAt = route.indexOf("final screen = (data['screen'] as String?)");
      final firstCache = route.indexOf('_currentUserIsAdmin', gate);
      expect(gate, greaterThan(-1));
      expect(gate < screenAt, true);
      expect(firstCache == -1 || firstCache > screenAt, true,
          reason: '남은 캐시 사용은 screen 분기 안쪽(비권한 타입 전용)뿐이어야 한다');
    });

    test('권한 걸린 29종 전부가 이 게이트에 걸린다', () {
      final set = RegExp(r"kPermissionBearingNotifTypes = \{([^}]*)\}")
          .firstMatch(_codeOf(_src(_model)))!
          .group(1)!;
      final types = RegExp(r"'([A-Za-z]+)'").allMatches(set).map((m) => m.group(1)!).toSet();
      expect(types.length, greaterThanOrEqualTo(28));
      // 게이트는 집합 멤버십 하나로 판정하므로, 집합에 있으면 예외 없이 걸린다.
      expect(route.contains('kPermissionBearingNotifTypes.contains(rawType)'), true);
      // 그리고 그 29종은 전부 dispatcher에 case가 있다.
      final screen = _codeOf(_src(_notif));
      for (final t in types) {
        expect(screen.contains('case NotificationType.$t:'), true, reason: t);
      }
    });

    test('dispatcher가 현재 맥락으로 다시 판정한다', () {
      // 순수 USER / 배정 없음 / 권한 없음 / 확인 실패가 각각 다른 결과다.
      final v = _flat(_codeOf(
          _bodyOf(_src(_notif), 'Future<_AdminAccessResult> _validateAdminNotificationAccess(')));
      expect(v.contains('if (up.isUser && !up.isSubAdmin) return _AdminAccessResult.invalidContext;'),
          true, reason: '순수 USER는 관리자 목적지로 가지 않는다');
      expect(v.contains('if (!inList) return _AdminAccessResult.noBusinessAccess;'), true,
          reason: '배정이 회수된 SUB_ADMIN은 fail-closed');
      expect(v.contains('return _AdminAccessResult.permissionUnknown;'), true);
    });

    test('dual-recipient 타입은 현재 역할로 갈린다', () {
      // 서버가 근로자와 관리자 양쪽에 보내는 타입들 — dispatcher의 isUser 분기가 받는다.
      for (final t in ['terminationApproved', 'resignApproved', 'terminationRejected']) {
        final i = notif.indexOf('case NotificationType.$t:');
        expect(i, greaterThan(-1), reason: t);
        final seg = notif.substring(i, i + 900);
        expect(seg.contains('if (isUser) {'), true, reason: '$t — 근로자 분기');
        expect(seg.contains('_validateAdminNotificationAccess('), true,
            reason: '$t — 관리자 분기는 현재 권한을 본다');
      }
    });

    test('비권한(근로자) 타입의 라우팅은 그대로다', () {
      expect(fcm.contains("case 'mySchedule':"), true);
      expect(fcm.contains("case 'wageTransferred':"), true);
      expect(fcm.contains("destinationKey: 'my_schedule',"), true);
    });
  });

  // ── PART C. 같은 payload → 같은 목적지 ─────────────────────────────

  group('같은 payload가 두 입구에서 같은 곳으로 간다', () {
    test('applicationConfirmed — 같은 화면·같은 identity', () {
      // in-app
      expect(
          notif.contains('builder: (_) => MyApplicationsScreen( focusApplicationId: '
              "notification.data?['applicationId'] as String?, ),"),
          true);
      // FCM
      expect(
          fcm.contains("builder: (_) => MyApplicationsScreen( focusApplicationId: "
              "data['applicationId'] as String?, ),"),
          true);
    });

    test('권한 걸린 타입은 FCM이 in-app dispatcher를 그대로 재사용한다', () {
      expect(fcm.contains('_navigateToNotificationScreen(autoDispatchPayload: data);'), true);
      expect(_load(_notif).contains('final payload = widget.autoDispatchPayload;'), true);
    });
  });
}
