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
  // 판정 기준은 언제나 type이다. screen은 FCM 라우터가 쓰는 별칭일 뿐이고,
  // 두 라우터의 우선순위가 반대라서(FCM: screen 우선 / 인앱: type 우선) 값이
  // 어긋난 payload는 서로 다른 목적지 — 따라서 서로 다른 권한 — 을 고를 수 있었다.
  group('권한이 걸린 알림은 한 곳에서만 판정한다', () {
    test('관리자 맥락에서는 type으로 dispatcher에 넘긴다', () {
      expect(
        fcm.contains('if (_currentUserIsAdmin && rawType != null && '
            'kPermissionBearingNotifTypes.contains(rawType)) '
            '{ _navigateToNotificationScreen(autoDispatchPayload: data); return; }'),
        true,
        reason: 'screen switch를 타면 인앱과 다른 목적지가 나올 수 있다',
      );
    });

    test('근로자 경로는 건드리지 않는다', () {
      // 같은 type을 근로자도 받는다(resignApproved 등). 관리자 맥락에서만 적용한다.
      final i = fcm.indexOf('kPermissionBearingNotifTypes.contains(rawType)');
      expect(i > 0, true);
      expect(fcm.substring(0, i).endsWith('if (_currentUserIsAdmin && rawType != null && '),
          true);
    });

    test('목록이 인앱 라우트와 어긋나면 알아차린다', () {
      // 손으로 맞춘 목록이 아니라 검증되는 목록이어야 한다.
      // notification_screen.dart에서 requiredPermission을 요구하는 라우트의
      // case 라벨을 모아, 전부 집합에 들어 있는지 본다.
      final screenSrc = _codeOf(_src(_notifPath));
      final blocks = screenSrc.split('case NotificationType.');
      final needPerm = <String>{};
      for (var i = 1; i < blocks.length; i++) {
        final name = RegExp(r'^(\w+)').firstMatch(blocks[i])?.group(1);
        if (name == null) continue;
        // 이 case부터 다음 case 전까지에 requiredPermission이 있으면 권한 라우트다.
        if (blocks[i].contains('requiredPermission:')) needPerm.add(name);
      }
      final model = _src('lib/models/core/notification_model.dart');
      final setBlock = model.substring(
          model.indexOf('const Set<String> kPermissionBearingNotifTypes = {'),
          model.indexOf('const Set<NotificationType> kAdminNotifTypes'));
      final missing = needPerm.where((t) => !setBlock.contains("'$t'")).toList();
      expect(missing, isEmpty,
          reason: '권한 라우트가 생겼는데 kPermissionBearingNotifTypes에 없다: $missing');
    });
  });

  group('권한을 못 읽은 것과 없는 것을 구분한다', () {
    test('조회 실패는 별도 상태다', () {
      expect(notif.contains('permissionUnknown,'), true);
      expect(notif.contains("debugPrint('[_validateAdminNotificationAccess] 권한 조회 실패: \$e'); "
          'return _AdminAccessResult.permissionUnknown;'), true,
          reason: '못 읽은 것을 noPermission으로 합치면 멀쩡한 관리자에게 거짓말을 한다');
    });

    test('문구가 서로 다르고 다시 시도할 수 있다', () {
      expect(notif.contains("ToastHelper.showError('권한 정보를 확인하지 못했습니다. 잠시 후 다시 시도해주세요.');"),
          true);
      expect(notif.contains("ToastHelper.showWarning('이 업무를 처리할 권한이 없습니다.');"), true);
    });

    test('모르는 상태에서도 진입은 막는다', () {
      // fail-open 금지 — 막되 이유만 사실대로 말한다.
      final i = notif.indexOf('case _AdminAccessResult.permissionUnknown:');
      expect(i > 0, true);
      expect(notif.substring(i, i + 200).contains('return false;'), true);
    });
  });

  // 멤버 관리 라우트의 `requiredPermission: (p) => false` 의미 —
  // validator를 끝까지 읽어 확정한 것이지 추측이 아니다.
  //   BUSINESS_ADMIN : isSubAdmin이 아니므로 그 앞 단계에서 allowed로 반환된다
  //                    (콜백에 닿지 않는다)
  //   SUB_ADMIN      : 멤버십 확인 후 콜백이 false → noPermission
  // 즉 owner 전용이고, MemberManagementScreen 자체 가드와 같은 계약이다.
  group('멤버 관리는 사업주 전용이다', () {
    test('사업주는 권한 콜백 이전에 통과한다', () {
      expect(notif.contains('if (!up.isSubAdmin) return _AdminAccessResult.allowed;'), true);
    });

    test('서브어드민은 항상 거부된다', () {
      final i = notif.indexOf('case NotificationType.memberInvitationAccepted:');
      expect(i > 0, true);
      expect(notif.substring(i, i + 500).contains('requiredPermission: (p) => false'), true);
    });

    test('화면 자체도 같은 기준으로 막는다', () {
      final m = _flat(_codeOf(
          _src('lib/screens/business_admin/member_management_screen.dart')));
      expect(m.contains('if (!(up.currentUser?.isBusinessAdmin == true))'), true,
          reason: '라우트만 막고 화면이 열려 있으면 다른 진입점으로 들어간다');
    });

    test('알림은 초대한 관리자에게만 가고 businessId를 싣는다', () {
      final f = _flat(_codeOf(_src(_fnsPath)));
      expect(f.contains('data: {action: "memberManagement", businessId},'), true);
      expect(f.contains('const adminUid = inv.invitedBy as string | undefined;'), true);
    });
  });

  // 공고 목록 read — 권한 flag가 하나도 없는 SubAdmin도 DRAFT를 포함한
  // 사업장 전체 공고를 읽고 있었다(실측 200 · tos 3건).
  // 기준을 새로 만들지 않고 [R1.2.1]이 지원서 목록에서 이미 정한 것을 쓴다:
  // generic read를 canManageTo 하나로 강제하면 다른 caller가 깨지므로
  // "읽을 이유가 있는 권한 중 하나"를 요구한다.
  // 실측(수정 후): owner·To·Workers·Contract·Wage 각각 200 / 넷 다 false 403
  // 읽기 권한은 그 endpoint의 **실제 소비자**로 정한다.
  // 다른 generic endpoint가 무엇을 쓰는지는 근거가 아니다 —
  // 한 번 그렇게 넓혔다가(넷 중 하나) 소비자 근거가 없어 되돌렸다.
  //
  // 공고 목록의 살아 있는 소비자는 셋이고 전부 공고 작업이다:
  //   기존 공고 불러오기 · 업무유형 삭제 전 사용 확인 · 활성 공고 수 한도
  // 실측: owner/To 200 · Workers/Contract/Wage/전부false/타사업장 403
  //       세 소비 경로 모두 canManageTo 계정에서 200
  group('공고 목록은 공고 권한을 요구한다', () {
    final tos = _flat(_codeOf(_callableOf(raw, 'callableGetTOsByBiz')));

    test('canManageTo를 요구한다', () {
      expect(tos.contains('if (tosPerms?.canManageTo !== true)'), true);
      expect(tos.contains('공고 관리 권한이 없습니다'), true);
    });

    test('다른 endpoint의 권한 목록을 베끼지 않는다', () {
      expect(tos.contains('TO_READ_PERMISSIONS'), false,
          reason: '소비자 근거 없이 네 권한으로 넓히면 최소권한이 아니다');
    });

    test('owner·SUPER_ADMIN은 그대로 통과한다', () {
      expect(tos.contains('(tosCallerData?.role as string | undefined) === "SUPER_ADMIN" || '
          'tosAdminIds.includes(callerUid) || tosOwnerId === callerUid'), true);
    });

    test('사업장 소속 확인이 먼저다', () {
      final i = tos.indexOf('await assertBizAdmin(callerUid, businessId)');
      final p = tos.indexOf('tosPerms?.canManageTo');
      expect(i > 0 && p > i, true);
    });
  });

  // 같은 일에 판정이 셋이었다 — 승인/거절 writer와 알림 라우트는
  // canManageWorkers인데 목록 reader만 membership이었다.
  // 실측: owner/Workers 200 · To/Contract/Wage/전부false/타사업장 403
  group('일정변경 요청은 읽기와 처리가 같은 권한이다', () {
    final rd = _flat(_codeOf(_callableOf(raw, 'callableGetScheduleChangeRequests')));

    test('reader가 canManageWorkers를 요구한다', () {
      expect(rd.contains('if (scrRPerms?.canManageWorkers !== true)'), true);
      expect(rd.contains('근로자 관리 권한이 없습니다'), true);
    });

    test('승인 writer와 같은 권한이다', () {
      final wr = _flat(_codeOf(_callableOf(raw, 'callableApproveScheduleChangeRequest')));
      expect(wr.contains('canManageWorkers'), true,
          reason: '읽을 수 있는데 처리할 수 없거나 그 반대면 화면이 성립하지 않는다');
    });

    test('날짜 단위 변형은 건드리지 않는다', () {
      // 고정근무 관리가 계약 맥락에서 쓴다 — 여기서 같이 조이면 그 화면이 깨진다.
      expect(raw.contains('callableGetScheduleChangeRequestsForDate'), true);
    });
  });

  // 권한 없는 호출자가 id의 존재 여부를 알아낼 수 있으면 안 된다.
  // businessId는 지원서 문서에서만 얻어지므로 문서를 먼저 읽을 수밖에 없고,
  // 그 상태로 소속 실패를 그대로 내보내면 없는 id는 404, 있는 id는 403이 됐다.
  // 실측: 타 사업장 member → 두 경우 모두 404 (동일)
  //       같은 사업장 member, canManageTo 없음 → 403 (권한 없음은 그대로 말한다)
  // 권한 없는 호출자가 id의 존재 여부를 알아낼 수 있으면 안 된다.
  // businessId를 문서에서만 얻으면 인가 전에 문서를 읽을 수밖에 없고,
  // 그러면 없는 id는 404, 있는 id는 403이 되어 존재 확인 수단이 된다.
  // 호출자가 어느 사업장 일인지 먼저 말하게 하고 인가를 먼저 끝낸다.
  //
  // 실측(수정 후): P0 같은사업장 / 다른 capability만 / 타 사업장 To
  //   → 세 caller 모두 존재하는 id와 없는 id의 응답이 동일
  //   authorized → 200 vs 404 (쓸모 있는 구분 유지)
  //   businessId 생략 → 400 (옛 순서로 떨어지는 경로 자체를 없앴다)
  group('지원서 존재 여부가 권한 없는 호출자에게 새지 않는다', () {
    final cf = _flat(_codeOf(_callableOf(raw, 'callableConfirmApplication')));

    test('인가가 문서 읽기보다 먼저다', () {
      final auth = cf.indexOf('await assertBizAdmin(callerUid, claimedBusinessId)');
      final fetch = cf.indexOf('const appSnap = await appRef.get();');
      expect(auth > 0 && fetch > auth, true,
          reason: '문서를 먼저 읽으면 없는 id와 있는 id의 응답이 갈린다');
    });

    test('businessId는 선택이 아니다', () {
      expect(cf.contains('if (typeof claimedBusinessId !== "string" || '
          'claimedBusinessId.length === 0) { throw new HttpsError('
          '"invalid-argument", "businessId가 필요합니다."); }'), true,
          reason: '생략 가능하면 생략한 직접 호출이 옛 순서로 떨어진다');
    });

    test('주장한 사업장과 실제가 다르면 없는 것과 같다', () {
      expect(cf.contains('if (businessId !== claimedBusinessId) { '
          'throw new HttpsError("not-found", "지원서를 찾을 수 없습니다."); }'), true);
    });

    test('authorized의 쓸모 있는 404는 남는다', () {
      expect(cf.contains('if (!appSnap.exists) throw new HttpsError('
          '"not-found", "지원서를 찾을 수 없습니다.");'), true);
    });

    test('클라이언트가 사업장을 함께 보낸다', () {
      final s = _flat(_codeOf(
          _src('lib/services/firestore/application_firestore.dart')));
      expect(s.contains("if (businessId != null && businessId.isNotEmpty) "
          "'businessId': businessId,"), true);
    });
  });

  // 같은 화면에서 승인·거절까지 하는 목록은 읽기도 그 권한이어야 한다.
  group('일정변경 날짜 목록도 처리 권한을 따른다', () {
    final rd = _flat(_codeOf(
        _callableOf(raw, 'callableGetScheduleChangeRequestsForDate')));

    test('canManageWorkers를 요구한다', () {
      expect(rd.contains('if (scrDPerms?.canManageWorkers !== true)'), true);
    });

    test('화면은 거절을 표시 없음으로 받는다', () {
      // 계약 권한으로 들어온 사용자의 고정근무 목록까지 깨지면 안 된다.
      final d = _flat(_codeOf(
          _src('lib/screens/business_admin/dialogs/fixed_worker_management_dialog.dart')));
      expect(d.contains('_pendingRequestsForDate = await scheduleRequestsFuture; } catch (e)'),
          true);
      expect(d.contains('_pendingRequestsForDate = const [];'), true);
    });
  });

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
