// [CROSS-DOMAIN-R5.1] 알림은 도메인 상태의 투영이지, 도메인 상태가 아니다.
//
// 두 가지를 고쳤다.
//
//   1. 푸시로 들어온 관리자 알림이 권한 검사를 건너뛰었다.
//      인앱 경로(NotificationScreen)는 알림마다 canManageContract /
//      canManageWorkers / canManageWage 를 **지금** 다시 읽는다. FCM 경로는
//      `_currentUserIsAdmin` 하나만 보고 관리자 화면을 바로 밀었다.
//      그 플래그는 관리자 모드로 전환한 SUB_ADMIN에도 true다
//      (UserProvider.switchToAdminMode → FCMService.updateAdminStatus(true)).
//      그리고 중간정산 알림은 canManageWage 서브어드민에게 팬아웃된다
//      (callableRequestInterimSettlement). 즉 권한이 회수된 뒤에도 옛 푸시로
//      급여·계약·리뷰 화면에 들어갈 수 있었다. 판정은 한 곳에만 둔다 —
//      이제 관리자 목적지는 전부 canonical dispatcher를 거친다.
//
//   2. 인력 현황이 "권한 없음"을 "부족한 자리 없음"으로 답했다.
//      권한이 하나도 없는 member에게 `available: true · days: []` 를 돌려줬다.
//      같은 응답의 홈 요약은 이미 available:false로 구분하고 있었다.
//      실측(수정 전 → 후): available true → false.
//
// DEV 실측:
//   권한 전부 false인 member의 목적지 호출
//     인력 현황 200 available=false · 당일 상세 403 · 미발송 계약 403
//     지원자 목록 403 · 홈 요약 200 actions.*.available=false
//   B사업장 관리자가 A사업장 payload로 호출 → 403 두 건
//   NO_SHOW만 있는 달 → review_request 0건 · 알림 0건
//   실제 근무가 있는 달 → review_request 1건 · reviewRequest 알림 1건

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fnsPath = 'functions/src/index.ts';
const _fcmPath = 'lib/services/fcm_service.dart';
const _notifPath = 'lib/screens/common/notification_screen.dart';

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('$p 를 찾지 못함');
  return f.readAsStringSync();
}

String _codeOf(String b) =>
    b.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');

String _flat(String b) => b.replaceAll(RegExp(r'\s+'), ' ');

String _callableOf(String source, String name) {
  final start = source.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final next = source.indexOf('\nexport ', start + 10);
  return source.substring(start, next == -1 ? source.length : next);
}

void main() {
  final raw = _src(_fnsPath);
  final fcm = _flat(_codeOf(_src(_fcmPath)));
  final notif = _flat(_codeOf(_src(_notifPath)));

  group('푸시와 인앱이 같은 권한을 요구한다', () {
    test('관리자 목적지는 푸시에서 바로 열리지 않는다', () {
      // 이 화면들은 인앱에서 각각 canManageContract / canManageWorkers /
      // canManageWage 를 요구한다. 푸시 라우터가 직접 밀면 그 검사가 없다.
      for (final s in [
        'AdminContractManagementScreen',
        'AdminReviewListScreen',
        'PayrollPaymentDashboardScreen',
      ]) {
        expect(fcm.contains(s), false,
            reason: '$s 을 FCM 라우터가 직접 열면 권한 판정이 두 벌이 된다');
      }
    });

    test('관리자 알림은 canonical dispatcher로 넘긴다', () {
      for (final c in [
        "case 'contractSigned':",
        "case 'contractRenewal':",
        "case 'contractRequested':",
        "case 'reviewReceived':",
        "case 'interimSettlementAdmin':",
      ]) {
        final i = fcm.indexOf(c);
        expect(i > 0, true, reason: '$c 이 사라졌다');
        final body = fcm.substring(i, i + 420);
        expect(body.contains('_navigateToNotificationScreen(autoDispatchPayload: data)'),
            true, reason: '$c 이 dispatcher를 거치지 않는다');
      }
    });

    test('dispatcher는 알림 타입을 먼저 읽는다', () {
      expect(notif.contains("final rawType = (payload['type'] ?? payload['screen'])?.toString();"),
          true, reason: 'type이 canonical identity다 — screen은 폴백');
    });

    test('푸시 payload에는 언제나 type이 실린다', () {
      expect(_flat(_codeOf(raw)).contains('notificationId: notificationId, type: type || "general",'),
          true, reason: 'type이 없으면 dispatcher가 목적지를 정할 수 없다');
    });
  });

  group('권한은 알림이 아니라 지금 상태로 판정한다', () {
    test('다른 사업장 알림이면 현재 권한을 다시 읽는다', () {
      expect(notif.contains('final perms = await MemberService().getMemberPermissions(businessId, uid);'),
          true, reason: '알림 당시 권한이 아니라 지금 권한이어야 한다');
      expect(notif.contains('if (perms == null || !requiredPermission(perms)) { return _AdminAccessResult.noPermission; }'),
          true);
    });

    test('사업장 소속도 다시 확인한다', () {
      expect(notif.contains("final inList = up.currentUser?.subAdminBusinessIds.contains(businessId) ?? false; "
          'if (!inList) return _AdminAccessResult.noBusinessAccess;'), true,
          reason: 'payload businessId만으로 열면 소속이 끊긴 뒤에도 들어간다');
    });

    test('거절 사유를 한 덩어리로 뭉개지 않는다', () {
      for (final r in ['noBusinessAccess', 'noPermission', 'noBusinessId', 'invalidContext']) {
        expect(notif.contains('_AdminAccessResult.$r'), true);
      }
      expect(notif.contains("ToastHelper.showWarning('해당 사업장에 대한 관리자 권한이 없습니다.');"), true);
      expect(notif.contains("ToastHelper.showWarning('이 업무를 처리할 권한이 없습니다.');"), true);
    });
  });

  // 권한 없음을 어떤 필드로 말하는가 — 두 callable이 서로 다른 필드를 쓴다.
  // readiness의 `available`은 조회 성공 플래그이고(AH-V2-03.1), 권한 0개는
  // ERROR가 아니라 빈 scope로 답하도록 이미 결정돼 있다
  // (admin_home_staffing_rollout_contract_test CONTRACT-06).
  // Task 단위 권한은 홈 요약의 actions.*.available이 맡는다.
  // 두 의미를 한 필드에 겹치지 않는 것이 현재 계약이다.
  group('권한 표현은 정해진 필드로만 한다', () {
    test('readiness의 available은 조회 성공 플래그로 유지된다', () {
      final r = _flat(_codeOf(_callableOf(raw, 'callableGetStaffingReadiness')));
      expect(
        'return {available: true, partial: false, failedBusinessCount: 0, days: []};'
            .allMatches(r).length,
        2,
        reason: '사업장 0개 / 권한 사업장 0개 두 경로 모두 ERROR가 아니다',
      );
    });

    test('Task 권한은 홈 요약이 available:false로 말한다', () {
      final h = _flat(_codeOf(_callableOf(raw, 'callableGetAdminHomeSummary')));
      expect(h.contains('available'), true,
          reason: '권한 없는 Task를 0건으로 내리면 처리할 일이 없다고 읽힌다');
    });
  });

  group('알림을 읽거나 지워도 할 일은 남는다', () {
    test('삭제는 알림 문서만 지운다', () {
      final n = _flat(_codeOf(_src('lib/services/firestore/notification_firestore.dart')));
      expect(n.contains('await _notificationsFor(userId).doc(notificationId).delete();'), true);
      for (final c in ['applications', 'employment_contracts', 'attendance', 'tos']) {
        expect(n.contains("collection('$c')"), false,
            reason: '알림 정리가 $c 를 건드리면 할 일이 사라진다');
      }
    });

    test('읽음 처리도 알림 문서만 바꾼다', () {
      final n = _flat(_codeOf(_src('lib/services/firestore/notification_firestore.dart')));
      expect(n.contains("batch.update(doc.reference, { 'isRead': true,"), true);
    });
  });

  group('리뷰 요청은 실제 근무가 있어야 생긴다', () {
    test('실제 근무 + 마감된 근태만 센다', () {
      final f = _flat(_codeOf(raw));
      expect(f.contains('const ACTUAL_WORK_STATUSES = ["present", "late", "early_leave"];'), true,
          reason: 'NO_SHOW·결근은 근무 경험이 아니다');
      expect(f.contains('const FINALIZED_WAGE_STATUSES = ["confirmed", "transferred"];'), true);
      expect(f.contains('srvIsActualFinalizedWork(d.get("status"), d.get("wageStatus"))'), true);
    });

    test('월 단위 판정을 한 helper가 맡는다', () {
      final f = _flat(_codeOf(raw));
      expect(f.contains('if (!(await srvHasActualWorkInMonth(businessId, workerId, ymKey)))'), true,
          reason: '시간이 지났다는 이유만으로 리뷰를 요청하지 않는다');
    });
  });

  group('계약 서명 완료 알림은 실재한다', () {
    // [VERIFY-CONTRACT-NOTIFICATION-INVENTORY] — 과거 기록의 모순을 source로 확정.
    test('근로자 서명 후 관리자에게 보낸다', () {
      final c = _flat(_codeOf(_src('lib/services/contract_service.dart')));
      expect(c.contains('NotificationModel.createContractSigned('), true);
      expect(c.contains("final adminIds = List<String>.from(data?['adminIds'] as List? ?? []);"), true,
          reason: '수신자는 그 사업장의 관리자들이다');
    });

    test('payload가 application과 contract를 모두 들고 간다', () {
      final m = _flat(_codeOf(_src('lib/models/core/notification_model.dart')));
      final i = m.indexOf('type: NotificationType.contractSigned,');
      expect(i > 0, true);
      final body = m.substring(i, i + 300);
      expect(body.contains("'contractId': contractId"), true);
      expect(body.contains("'applicationId': applicationId"), true,
          reason: 'userId만으로 행을 찾으면 같은 근로자의 다른 지원서를 연다');
      expect(body.contains("'businessId': businessId"), true);
    });

    test('인앱 목적지는 계약 권한을 요구한다', () {
      final i = notif.indexOf('case NotificationType.contractSigned:');
      expect(i > 0, true);
      expect(notif.substring(i, i + 700).contains('requiredPermission: (p) => p.canManageContract'),
          true);
    });
  });

  group('자동 NO_SHOW는 알림을 만들지 않는다', () {
    test('emitter 없음이 현재 사실이다', () {
      // 시간이 지났다는 이유로 새 알림을 만들지 않는다 — 의도된 N/A다.
      // 함수 본문만 본다 — 고정 길이로 자르면 옆 함수의 알림 write를 잘못 잡는다.
      final start = raw.indexOf('async function processAutoNoShow(');
      expect(start > 0, true);
      final rest = raw.substring(start + 10);
      final endRel = RegExp(r'\n(async function |function |export const )').firstMatch(rest);
      final body = endRel == null ? rest : rest.substring(0, endRel.start);
      expect(body.contains('collection("notifications")'), false,
          reason: 'NO_SHOW 자체에는 발신자가 없다. 생겼다면 정책 변경이므로 알아차려야 한다');
    });
  });
}
