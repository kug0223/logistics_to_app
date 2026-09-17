// [CROSS-DOMAIN-R5.1G] 알림 런타임 / stale / 목적지 / DTO 계약
//
// 이 Phase의 런타임 측정은 **DEV 결제 비활성화**로 막혔다(모든 callable이
// Google 프런트엔드의 500/503 HTML을 돌려주고, 함수 로그가
// "The request failed because billing is disabled for this project."를 남긴다).
// 그래서 서버에서 재볼 수 없는 항목은 PASS로 적지 않고, 소스에서 확정할 수
// 있는 계약만 여기 고정한다. 나머지는 보고서에 BLOCKED로 남긴다.
//
// 이번에 고친 것 하나:
//   알림 접근 검증의 캐시 경로가 `can()`을 쓰고 있었다. 선택 사업장 구독이
//   죽어 있으면 캐시에 남은 허용은 마지막으로 본 값일 뿐인데, 그 값으로
//   목적지를 열면 알림이 권한을 부여하는 셈이 된다. R5.1F.5의 4상태로 바꿨다 —
//   확인하지 못한 상태는 거부가 아니라 permissionUnknown이다.

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

/// 파라미터 목록을 먼저 건너뛴다 — 명명 파라미터의 `{`를 본문으로 오인하지
/// 않기 위해서다(이 파일의 대상 함수들이 전부 명명 파라미터를 쓴다).
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
const _cf = 'functions/src/index.ts';

void main() {
  final rawNotif = _src(_notif);
  final notif = _load(_notif);
  final fcm = _load(_fcm);

  // ── PART B. permissionUnknown 분기 ─────────────────────────────────

  group('확인하지 못한 권한은 권한 없음이 아니다', () {
    final v = _flat(_codeOf(
        _bodyOf(rawNotif, 'Future<_AdminAccessResult> _validateAdminNotificationAccess(')));

    test('조회 실패는 permissionUnknown이다', () {
      expect(v.contains('} catch (e) {'), true);
      expect(v.contains('return _AdminAccessResult.permissionUnknown;'), true);
    });

    test('조회 실패를 noPermission으로 말하지 않는다', () {
      final catchAt = v.indexOf('} catch (e) {');
      expect(catchAt, greaterThan(-1));
      final unknownAt = v.indexOf('return _AdminAccessResult.permissionUnknown;', catchAt);
      expect(unknownAt, greaterThan(catchAt), reason: 'catch가 곧바로 unknown으로 간다');
      expect(v.substring(catchAt, unknownAt).contains('noPermission'), false);
    });

    test('[R5.1G] 캐시 경로도 신선도를 본다', () {
      expect(v.contains('switch (up.checkCurrentBusiness(requiredPermission)) {'), true,
          reason: '캐시에 남은 허용이 지금 검증된 값이라는 보장이 없다');
      expect(
          v.contains('case PermissionCheck.error: case PermissionCheck.unknown: '
              'return _AdminAccessResult.permissionUnknown;'),
          true);
      expect(v.contains('if (!up.can(requiredPermission)) return _AdminAccessResult.noPermission;'),
          false, reason: 'bool 하나로는 stale allow가 통과한다');
    });

    test('확인 실패와 거부가 서로 다른 문구다', () {
      final h = _flat(_codeOf(_bodyOf(rawNotif, 'bool _handleAdminAccess(')));
      expect(h.contains("ToastHelper.showWarning('이 업무를 처리할 권한이 없습니다.'); return false;"),
          true);
      expect(
          h.contains("ToastHelper.showError('권한 정보를 확인하지 못했습니다. "
              "잠시 후 다시 시도해주세요.'); return false;"),
          true);
    });

    test('어느 쪽이든 fail-closed다 — 목적지로 가지 않는다', () {
      final h = _flat(_codeOf(_bodyOf(rawNotif, 'bool _handleAdminAccess(')));
      final allowed = 'case _AdminAccessResult.allowed: return true;';
      expect(h.contains(allowed), true);
      expect('return true;'.allMatches(h).length, 1,
          reason: 'allowed 외에는 어떤 경로도 true를 돌려주지 않는다');
    });

    test('NOT_FOUND/EMPTY로 표현하지 않는다', () {
      final h = _flat(_codeOf(_bodyOf(rawNotif, 'bool _handleAdminAccess(')));
      for (final bad in ['찾을 수 없습니다', '없습니다.0', '0건']) {
        expect(h.contains(bad), false, reason: bad);
      }
    });
  });

  // ── PART D. FCM vs in-app 목적지 parity ────────────────────────────

  group('같은 payload는 같은 목적지로 간다', () {
    test('권한이 걸린 타입은 FCM도 type으로 판정한다', () {
      expect(
          fcm.contains('if (_currentUserIsAdmin && rawType != null && '
              'kPermissionBearingNotifTypes.contains(rawType)) { '
              '_navigateToNotificationScreen(autoDispatchPayload: data); return; }'),
          true,
          reason: 'screen 필드를 먼저 보면 payload drift에서 목적지가 갈린다');
    });

    test('그 판정이 screen 분기보다 먼저다', () {
      final body = _flat(_codeOf(_bodyOf(_src(_fcm), 'void _navigateByPayload(')));
      expect(body.indexOf('kPermissionBearingNotifTypes') <
              body.indexOf("final screen = (data['screen'] as String?)"),
          true);
    });

    test('in-app dispatcher가 같은 payload를 받는다', () {
      expect(_load(_notif).contains('final payload = widget.autoDispatchPayload;'), true);
      expect(fcm.contains('_navigateToNotificationScreen(autoDispatchPayload: data);'), true);
    });

    test('권한 목록이 화면의 라우팅 표와 같은 출처다', () {
      final m = _load(_model);
      expect(m.contains('const Set<String> kPermissionBearingNotifTypes = {'), true);
      // 목록의 모든 타입이 실제로 화면의 switch에 존재해야 한다.
      final set = RegExp(r"kPermissionBearingNotifTypes = \{([^}]*)\}")
          .firstMatch(_codeOf(_src(_model)))!
          .group(1)!;
      final types = RegExp(r"'([A-Za-z]+)'")
          .allMatches(set)
          .map((x) => x.group(1)!)
          .toList();
      expect(types.length, greaterThanOrEqualTo(28));
      final screen = _codeOf(_src(_notif));
      for (final t in types) {
        expect(screen.contains('case NotificationType.$t:'), true, reason: t);
      }
    });
  });

  // ── PART A/J. N-라벨과 actionable 목적지 ───────────────────────────
  //
  // 원본 정의(R5.1 §35 / R5.1A K):
  //   N1  newApplication          → exact PENDING applicationId focus
  //   N3  applicationConfirmed    → exact current Application, CONFIRMED/CONTRACT_PENDING
  //   N8  notification read/delete→ Home task unchanged; domain mutation 후에만 감소
  //   N9  reconfirmAdminWarning / reconfirmDeclined
  //                               → exact application focus, WorkApplicantsDialog, canManageTo

  group('N1 — newApplication은 지원서 하나를 지목한다', () {
    test('canManageTo로 막는다', () {
      final i = notif.indexOf('case NotificationType.newApplication:');
      final seg = notif.substring(i, i + 700);
      expect(seg.contains('requiredPermission: (p) => p.canManageTo,'), true);
    });
  });

  group('N3 — applicationConfirmed의 현재 목적지', () {
    // [CROSS-DOMAIN-R5.1G] 원본 N3는 "exact current Application"을 요구한다.
    //   실제 구현은 수신자(근로자) 본인의 지원 목록을 열 뿐, 특정 지원서로
    //   초점을 맞추지 않는다. 이것이 현재 사실이다.
    //
    //   보안 영향은 없다 — 본인 목록이고 남의 지원서가 보이지 않는다.
    //   다만 "지목한다"는 요구는 충족되지 않았다. 조용히 충족된 것처럼
    //   지나가지 않도록 그 사실을 여기 고정한다.
    //   ([CORRECTION-N3-NO-APPLICATION-FOCUS] — 보고서에 별도 항목)
    test('수신자 본인의 목록으로 간다 (초점 없음)', () {
      expect(
          notif.contains('case NotificationType.applicationConfirmed: '
              'case NotificationType.applicationRejected: Navigator.push( context, '
              'MaterialPageRoute(builder: (_) => const MyApplicationsScreen()), );'),
          true);
    });

    test('관리자 권한을 요구하지 않는다 — 근로자 수신 알림이다', () {
      final i = notif.indexOf('case NotificationType.applicationConfirmed:');
      // 다음 case 직전까지만 본다 — 이웃 case의 권한 검사를 끌어오지 않는다.
      final next = notif.indexOf('case NotificationType.', i + 10);
      final seg = notif.substring(i, notif.indexOf('case NotificationType.', next + 10));
      expect(seg.contains('requiredPermission'), false);
      expect(seg.contains('_validateAdminNotificationAccess'), false);
    });
  });

  group('N9 — reconfirm 계열은 canManageTo로 WorkApplicants를 연다', () {
    test('두 타입이 같은 목적지다', () {
      expect(
          notif.contains('case NotificationType.reconfirmAdminWarning: '
              'case NotificationType.reconfirmDeclined:'),
          true);
      expect(notif.contains('await _openWorkApplicantsFromNotification(context, notification);'),
          true);
    });

    test('대상 사업장 canManageTo를 직접 읽어 fail-closed한다', () {
      final body = _flat(_codeOf(
          _bodyOf(rawNotif, 'Future<void> _openWorkApplicantsFromNotification(')));
      expect(body.contains('targetPermissions = await MemberService().getMemberPermissions('),
          true);
      expect(
          body.contains('if (targetPermissions == null || !targetPermissions.canManageTo) {'),
          true);
    });

    test('USER가 받으면 근로자 화면으로 폴백하지 않는다', () {
      final i = notif.indexOf('case NotificationType.reconfirmAdminWarning:');
      final seg = notif.substring(i, i + 400);
      expect(seg.contains("ToastHelper.showWarning('현재 처리할 수 없는 알림입니다.');"), true);
    });
  });

  // ── PART H. 알림은 권한이 아니다 ───────────────────────────────────

  group('알림 존재가 권한을 만들지 않는다', () {
    test('목적지 이동 전에 현재 권한을 다시 본다', () {
      // 권한이 걸린 목적지는 전부 validator를 통과한다.
      expect('_validateAdminNotificationAccess('.allMatches(notif).length,
          greaterThanOrEqualTo(16));
      expect('_handleAdminAccess('.allMatches(notif).length, greaterThanOrEqualTo(16));
    });

    test('멤버십도 매번 다시 본다', () {
      final v = _flat(_codeOf(
          _bodyOf(rawNotif, 'Future<_AdminAccessResult> _validateAdminNotificationAccess(')));
      expect(
          v.contains('final inList = up.currentUser?.subAdminBusinessIds.contains(businessId) '
              '?? false; if (!inList) return _AdminAccessResult.noBusinessAccess;'),
          true);
    });

    test('멤버 초대 결과는 SUB_ADMIN에게 열리지 않는다', () {
      expect(notif.contains('requiredPermission: (p) => false,'), true,
          reason: '멤버 관리는 소유자 전용이다');
    });
  });

  // ── PART C. stale 상태는 서버가 현재 상태로 다시 판정한다 ──────────

  group('stale payload가 과거 상태를 복원하지 못한다', () {
    final cf = _flat(_codeOf(_src(_cf)));

    test('계약 서명 — 서명 가능한 상태만 통과', () {
      expect(
          cf.contains('throw new HttpsError("failed-precondition", '
              '`서명할 수 없는 계약서 상태입니다: \${preStatus}`);'),
          true,
          reason: 'completed/voided는 여기서 걸린다');
      expect('서명할 수 없는 계약서 상태입니다'.allMatches(cf).length, 4,
          reason: '사업주·근로자 두 경로 � (사전 검증 + 트랜잭션 내 재검증) — TOCTOU까지 막는다');
    });

    test('계약 서명 — 이미 서명된 계약을 다시 서명하지 않는다', () {
      expect(cf.contains('"이미 사업주 서명이 완료된 계약서입니다."'), true);
      expect(cf.contains('"이미 근무자 서명이 완료된 계약서입니다."'), true);
    });

    test('계약 서명 — 상태 검증이 업로드 부작용보다 먼저다', () {
      final raw = _codeOf(_src(_cf));
      final i = raw.indexOf('export const callableFinalizeEmployerSignature');
      final seg = raw.substring(i, i + 9000);
      expect(seg.indexOf('서명할 수 없는 계약서 상태입니다') <
              seg.indexOf('서명 이미지 업로드에 실패했습니다'),
          true,
          reason: 'stale 계약이 Storage에 흔적을 남기면 안 된다');
    });

    test('지원서 확정 — 계약 가능한 상태만 통과', () {
      expect(
          cf.contains('if (!["CONFIRMED", "CONTRACT_PENDING"].includes(appData.status as string)) '
              '{ throw new HttpsError("failed-precondition", '
              '"해당 지원서는 계약서 작성 가능한 상태가 아닙니다."); }'),
          true);
    });

    test('초대 수락 — 마감된 슬롯은 서버가 막는다 (N2)', () {
      expect(cf.contains('"종료된 근무일입니다.') || cf.contains('"종료된 공고입니다'), true);
    });
  });

  // ── PART K. read/delete ≠ Task ─────────────────────────────────────

  group('알림을 읽거나 지워도 Task는 그대로다', () {
    test('Home Task는 알림이 아니라 domain summary에서 나온다', () {
      final raw = _src('lib/screens/business_admin/business_admin_home_screen.dart');
      final rows = _flat(_codeOf(_bodyOf(raw, '_makeActionRows(BuildContext context')));
      expect(rows.contains('cs?.actions.'), true);
      expect(rows.contains('notification'), false,
          reason: 'Notification ≠ Task — Task 목록이 알림을 보면 안 된다');
      final unknown = _flat(_codeOf(_bodyOf(raw, 'int _unknownTaskCount(')));
      expect(unknown.contains('notification'), false);
    });

    test('서버 summary도 알림 컬렉션을 세지 않는다', () {
      final raw = _codeOf(_src(_cf));
      final i = raw.indexOf('export const callableGetAdminHomeSummary');
      expect(i, greaterThan(-1));
      final seg = raw.substring(i, i + 4000);
      expect(seg.contains('collection("notifications")'), false);
    });

    test('읽음 처리는 알림 문서만 바꾼다', () {
      const p = 'lib/services/firestore/notification_firestore.dart';
      final svc = _load(p);
      expect(svc.contains("'isRead': true,"), true);
      // 이 파일은 알림 하위컬렉션 외의 컬렉션을 건드리지 않는다.
      final others = RegExp(r"collection\('([A-Za-z_]+)'\)")
          .allMatches(_codeOf(_src(p)))
          .map((m) => m.group(1)!)
          .where((c) => c != 'notifications' && c != 'users')
          .toSet();
      expect(others, isEmpty,
          reason: '읽음이 도메인 상태를 건드리면 Task가 알림에 끌려간다 — $others');
    });
  });
}
