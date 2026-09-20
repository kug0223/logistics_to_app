// [CROSS-DOMAIN-R5.3B] 다른 업무 제안 / PENDING 재배치
//
// R5.3A는 `callableChangeApplicationWorkType`을 얼렸다. 그 경로가 근로자가
// 동의한 적 없는 조건으로 지원서를 덮어썼기 때문이다. 이 Phase는 그 자리에
// **제안**을 놓는다:
//
//   관리자는 A(PENDING)에게 같은 슬롯의 다른 업무 B를 제안한다.
//   A는 그대로 살아 있다. 근로자가 B를 수락하는 **그 순간에만**
//   서버가 같은 트랜잭션에서 B를 확정하고 A를 접는다.
//
// 이 파일이 고정하는 것은 그 구조다:
//
//   · 금액·관계는 서버가 정한다 — client payload는 대상만 고른다.
//   · 수락은 하나의 commit boundary다: B CONFIRMED + A PENDING ❌ /
//     A AUTO_CANCELED + B INVITED ❌
//   · A의 종료는 '지원 취소'가 아니다 — REASSIGNMENT_ACCEPTED 하나로 판정한다.
//   · 거절하면 A는 손대지 않는다.
//   · 관계 카운터를 사람 수로 말하지 않는다.

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

String _callableBody(String raw, String name) {
  final start = raw.indexOf('export const $name = onCall(');
  if (start < 0) throw StateError('$name 을 찾지 못함');
  final end = raw.indexOf('\n);', start);
  if (end < 0) throw StateError('$name 본문 끝을 찾지 못함');
  return raw.substring(start, end);
}

/// `await db.runTransaction(async (tx) => {` 부터 짝이 맞는 `});` 까지.
///
/// 수락의 원자성은 "어느 쓰기가 **이 블록 안에** 있는가"로만 증명된다.
/// 함수 전체를 검색하면 트랜잭션 밖 쓰기도 통과해 버린다.
String _txBody(String body) {
  final start = body.indexOf('await db.runTransaction(async (tx) => {');
  if (start < 0) throw StateError('accept 트랜잭션을 찾지 못함');
  var depth = 0;
  var i = body.indexOf('{', start);
  final open = i;
  for (; i < body.length; i++) {
    if (body[i] == '{') depth++;
    if (body[i] == '}') {
      depth--;
      if (depth == 0) return body.substring(open, i + 1);
    }
  }
  throw StateError('accept 트랜잭션 끝을 찾지 못함');
}

const _cf = 'functions/src/index.ts';
const _notifModel = 'lib/models/core/notification_model.dart';
const _notifScreen = 'lib/screens/common/notification_screen.dart';
const _fcm = 'lib/services/fcm_service.dart';
const _myApps = 'lib/screens/user/my_applications_screen.dart';
const _appModel = 'lib/models/core/application_model.dart';
const _offerSheet = 'lib/widgets/dialogs/alternative_work_offer_sheet.dart';
const _workDlg = 'lib/screens/business_admin/dialogs/work_applicants_dialog.dart';
const _dayDlg = 'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';

void main() {
  final rawCf = _codeOf(_src(_cf));
  final cf = _flat(rawCf);
  final offerRaw = _callableBody(rawCf, 'callableOfferAlternativeWork');
  final offer = _flat(offerRaw);
  final acceptRaw = _callableBody(rawCf, 'callableAcceptTOInvitation');
  final accept = _flat(acceptRaw);
  final acceptTx = _flat(_txBody(acceptRaw));
  final decline = _flat(_callableBody(rawCf, 'callableDeclineTOInvitation'));

  // ══════════════════════════════════════════════════════════════════
  // PART A/F — 제안 writer: 서버가 조건을 정한다
  // ══════════════════════════════════════════════════════════════════

  group('제안은 서버가 조건을 정한다', () {
    test('payload는 대상과 옵션만 받는다 — 금액은 받지 않는다', () {
      expect(
          offer.contains('const {sourceApplicationId, targetWdId, '
              'compensationOption} = request.data'),
          true);
      // 임의 금액 payload 금지 — request.data에서 wage를 꺼내는 경로가 없다.
      expect(offer.contains('request.data as { wage'), false);
      expect(RegExp(r'request\.data[^;]*\bwage\b').hasMatch(offer), false,
          reason: 'client가 보낸 금액을 쓰면 아무도 승인하지 않은 조건이 생긴다');
    });

    // [R5.3C.1] Core v1의 TARGET_BASE-only 제한은 MATCH_SOURCE_WAGE로 열렸다.
    //   자세한 계약은 compensation_snapshot_authority_test가 고정한다.
    //   여기서는 **allowlist라는 사실**과 legacy 이름 거부만 지킨다.
    test('옵션은 서버 allowlist다 — legacy SOURCE_WAGE 금지', () {
      expect(
          offer.contains('const OFFER_COMPENSATION_OPTIONS = '
              '["TARGET_BASE", "MATCH_SOURCE_WAGE"];'),
          true);
      expect(offer.contains('"SOURCE_WAGE"'), false,
          reason: 'source Application의 wage만 뜻하는 이름은 확장할 수 없다');
    });

    test('근로조건은 언제나 target WorkDetail에서 읽는다', () {
      expect(offer.contains('const targetBaseWage = targetWD["wage"]'), true);
      expect(offer.contains('const offeredSnapshot = buildCompensationSnapshot(targetWD);'),
          true, reason: '다른 경로와 같은 snapshot builder를 써야 한다');
      // [R5.3C.1] MATCH에서 source가 주는 것은 **금액 하나**다.
      //   휴게·야간·공제를 A에서 옮기면 A 8시간 휴게 60분이 B 5시간에 붙는다.
      for (final f in [
        'srcData.breakMinutes', 'srcData.nightAllowanceApplied',
        'srcData.nightIncluded', 'srcData.taxDeductionType',
        'srcData.baseHourlyWage',
      ]) {
        expect(offer.contains(f), false, reason: 'source에서 가져오면 안 되는 것: $f');
      }
    });

    test('canManageTo 게이트 — 공고 관리와 같은 권한이다', () {
      expect(offer.contains('await assertBizAdmin(callerUid, offerBizId)'), true);
      expect(offer.contains('if (offerPerms.canManageTo !== true) {'), true);
      expect(offer.contains('"TO 관리 권한이 없습니다."'), true);
    });

    test('source는 PENDING만 — 확정된 약속은 대상이 아니다', () {
      expect(
          offer.contains('if ((srcData.status as string | undefined) !== "PENDING") {'),
          true);
      expect(
          offer.contains('"지원 대기 중인 지원자에게만 다른 업무를 제안할 수 있습니다."'),
          true);
    });

    test('같은 업무로는 제안하지 않는다', () {
      expect(offer.contains('if (srcWdId && srcWdId === targetWdId) {'), true);
    });

    test('대상 업무는 지금 읽어서 마감·정원을 본다', () {
      expect(offer.contains('"마감된 공고에는 제안할 수 없습니다."'), true);
      expect(offer.contains('"마감된 근무일에는 제안할 수 없습니다."'), true);
      expect(offer.contains('const targetCounts = getWorkDetailCount('), true);
      expect(offer.contains('"제안할 업무의 정원이 이미 찼습니다."'), true);
    });

    test('대상 근로자 상태는 초대와 같은 안전장치를 쓴다', () {
      expect(offer.contains('offerTargetData.isBlacklisted === true'), true);
      expect(offer.contains('"비활성 계정의 근로자에게는 제안할 수 없습니다."'), true);
      expect(offer.contains('offerRestricted.toDate() > new Date()'), true);
    });

    test('worker_availability를 제안의 필수조건으로 강제하지 않는다', () {
      expect(offer.contains('worker_availability'), false,
          reason: '가능일 미등록이 제안을 막는 조건이 되면 안 된다');
    });
  });

  group('제안 문서는 canonical 자연키를 따른다', () {
    test('targetAppId = toId_slotId_wdId_uid', () {
      expect(
          offer.contains('const targetAppId = '
              '`\${offerToId}_\${offerSlotId}_\${targetWdId}_\${offerUid}`;'),
          true);
    });

    test('source의 wdId를 rewrite하지 않는다', () {
      // A는 만들어질 때의 자연키 그대로다 — 옮기는 것은 새 문서 B다.
      expect(offer.contains('srcRef.update({ wdId'), false);
      expect(RegExp(r'srcRef[^;]*wdId:').hasMatch(offer), false);
    });

    test('관계 출처는 서버가 적는다', () {
      for (final f in [
        'offerKind: "ALTERNATIVE_WORK",',
        'offerId,',
        'sourceApplicationId,',
        'sourceWdId: srcWdId ?? null,',
        'compensationOption,',
        'offeredBy: callerUid,',
      ]) {
        expect(offer.contains(f), true, reason: '제안 메타데이터 누락: $f');
      }
    });

    test('offerId는 재시도와 재제안을 구분한다', () {
      expect(
          offer.contains('const offerId = `\${targetAppId}_\${offerTime.toMillis()}`;'),
          true);
      // [R5.3B.1] 알림 identity는 **커밋된** offerId로만 만든다. 재시도는
      //   새로 계산하지 않고 저장된 값을 읽어 쓰므로 같은 문서가 된다 —
      //   timestamp 자체가 결정적인 것이 아니다.
      expect(
          offer.contains('.doc(`work_reassignment_offered_'
              '\${committedOfferId}`) .create({'),
          true,
          reason: '같은 제안의 재시도는 같은 알림 문서라 두 번 생기지 않는다');
    });

    test('생성과 카운터는 한 트랜잭션이다', () {
      expect(offer.contains('await db.runTransaction(async (offerTx) => {'), true);
      expect(offer.contains('offerTx.set(targetRef, offerAppData);'), true);
      expect(offer.contains('pendingCount: admin.firestore.FieldValue.increment(1),'),
          true);
      expect(
          offer.contains('[`workDetailCounts.\${targetWdId}.pendingCount`]: '
              'admin.firestore.FieldValue.increment(1),'),
          true);
      expect(offer.contains('totalPending: admin.firestore.FieldValue.increment(1),'),
          true);
    });

    test('트랜잭션 안에서 source가 아직 PENDING인지 다시 본다', () {
      expect(offer.contains('const freshSrc = await offerTx.get(srcRef);'), true);
      expect(offer.contains('"지원 상태가 바뀌어 제안할 수 없습니다."'), true);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // PART H/I — 수락 원자성
  // ══════════════════════════════════════════════════════════════════

  group('수락 요청은 관계를 바꾸지 못한다', () {
    test('sourceApplicationId는 저장된 메타데이터에서 읽는다', () {
      expect(
          accept.contains('const reassignSourceId = '
              'freshData.sourceApplicationId as string | undefined;'),
          true);
      // client payload에 sourceApplicationId가 들어올 자리가 없다.
      final payload = accept.substring(
          accept.indexOf('request.data as'),
          accept.indexOf('request.data as') + 400);
      expect(payload.contains('sourceApplicationId'), false,
          reason: 'client가 보낸 source를 믿으면 남의 지원서를 접을 수 있다');
    });

    test('같은 사람·같은 근무 단위인지 서버가 다시 확인한다', () {
      expect(acceptTx.contains('const reassignSameParty ='), true);
      for (final axis in ['uid', 'businessId', 'toId', 'slotId', 'workDate']) {
        expect(acceptTx.contains('reassignSrcData.$axis'), true,
            reason: '동일성 축 누락: $axis');
      }
      expect(acceptTx.contains('"제안 정보가 일치하지 않아 수락할 수 없습니다."'), true);
    });
  });

  group('수락은 하나의 commit boundary다', () {
    test('source 읽기가 트랜잭션 안에 있다', () {
      expect(acceptTx.contains('const reassignSrcSnap = await tx.get(reassignSrcRef);'),
          true, reason: '트랜잭션 밖에서 읽으면 읽기 집합에 들어가지 않는다');
    });

    test('A 종료 쓰기가 같은 트랜잭션 안에 있다', () {
      expect(acceptTx.contains('tx.update(reassignSourceRef, { status: "AUTO_CANCELED",'),
          true);
      expect(acceptTx.contains('cancelReason: "REASSIGNMENT_ACCEPTED",'), true);
      expect(acceptTx.contains('reassignedToApplicationId: applicationId,'), true);
      expect(acceptTx.contains('reassignedAt: confirmedAt,'), true);
    });

    test('B 확정도 같은 트랜잭션 안에 있다', () {
      expect(acceptTx.contains('tx.update(appRef, acceptUpdate);'), true);
      expect(acceptTx.contains('status: "CONFIRMED", confirmedAt,'), true);
    });

    test('A 종료가 트랜잭션 밖의 별도 commit이 아니다', () {
      // 함수 전체에는 있는데 트랜잭션 블록에는 없다면 반쪽 성공이 가능하다.
      final outside = accept.replaceAll(acceptTx, '');
      expect(outside.contains('REASSIGNMENT_ACCEPTED'), false);
      expect(outside.contains('reassignedToApplicationId'), false);
    });

    test('source가 이미 확정이면 수락하지 않는다', () {
      expect(
          acceptTx.contains('"원 지원이 이미 확정되어 제안을 수락할 수 없습니다."'),
          true);
    });

    test('source가 없거나 링크가 깨졌으면 아무것도 하지 않는다', () {
      expect(acceptTx.contains('"제안 정보가 손상되어 수락할 수 없습니다."'), true);
      expect(
          acceptTx.contains('"원 지원서를 찾을 수 없어 제안을 수락할 수 없습니다."'),
          true);
    });
  });

  group('정원은 수락이 들어가는 WorkDetail 단위로 본다', () {
    test('wdId로 찾고, 없을 때만 workType 폴백', () {
      expect(
          acceptTx.contains('const acceptTargetWd = acceptWdId ? '
              '(rawWDs as Record<string, unknown>[]) '
              '.find((w) => w["wdId"] === acceptWdId) : '
              '(rawWDs as Record<string, unknown>[]) '
              '.find((w) => w["workType"] === freshSelectedWorkType);'),
          true);
    });

    test('workType 이름으로 첫 항목만 보고 break하지 않는다', () {
      // 한 슬롯에 같은 이름의 업무가 둘 있으면(오전/오후 파트) 수락하는 자리가
      // 아니라 엉뚱한 자리의 정원을 보게 된다 — 다른 업무 제안이 정확히 그 모양이다.
      expect(
          acceptTx.contains('if (wdMap.workType !== freshSelectedWorkType) continue;'),
          false);
    });
  });

  group('A는 한 가지 규칙으로만 끝난다', () {
    test('일반 겹침 정리 대상에서 제외한다', () {
      expect(
          acceptTx.contains('acceptOverlapPlan.toCancel = '
              'acceptOverlapPlan.toCancel.filter((d) => d.id !== reassignSourceId);'),
          true,
          reason: '같은 슬롯이라 시간이 겹치면 SCHEDULE_CONFLICT로도 접힌다 — '
              '사유가 두 벌 생기면 표현이 갈린다');
    });

    test('SCHEDULE_CONFLICT와 REASSIGNMENT_ACCEPTED는 다른 사유다', () {
      expect(cf.contains('cancelReason: "SCHEDULE_CONFLICT",'), true);
      expect(cf.contains('cancelReason: "REASSIGNMENT_ACCEPTED",'), true);
    });

    test('A에 패널티를 붙이지 않는다', () {
      // 제안 수락은 근로자의 변심이 아니다 — 신뢰도·노쇼·취소 누적 대상이 아니다.
      final aBlock = acceptTx.substring(
          acceptTx.indexOf('tx.update(reassignSourceRef,'),
          acceptTx.indexOf('tx.update(reassignSourceRef,') + 700);
      for (final penalty in [
        'noShowCount', 'lateCount', 'trustScore', 'cancellationCount',
        'recentNoShowCount', 'penalt',
      ]) {
        expect(aBlock.contains(penalty), false, reason: 'A에 $penalty 부과');
      }
    });
  });

  group('A가 잡고 있던 대기 자리를 같은 commit에서 돌려준다', () {
    test('TO totalPending은 B분 + A분을 함께 내린다', () {
      expect(
          acceptTx.contains('totalPending: admin.firestore.FieldValue.increment( '
              '-1 - reassignPendingBack),'),
          true);
    });

    test('slot pendingCount도 같은 식이다', () {
      expect(
          acceptTx.contains('pendingCount: admin.firestore.FieldValue.increment( '
              '-1 - reassignPendingBack),'),
          true);
    });

    test('A의 wdId 자리도 내린다', () {
      expect(
          acceptTx.contains('if (reassignSourceWdId && '
              'reassignSourceWdId !== inviteAcceptWdId) {'),
          true);
      expect(
          acceptTx.contains('slotUpdate[`workDetailCounts.\${reassignSourceWdId}'
              '.pendingCount`] = admin.firestore.FieldValue.increment(-1);'),
          true);
    });

    test('A가 이미 종료돼 있으면 카운터를 건드리지 않는다', () {
      expect(acceptTx.contains('const reassignPendingBack = reassignSourceActive ? 1 : 0;'),
          true);
      expect(
          acceptTx.contains('if (reassignSrcStatus === "PENDING") { '
              'reassignSourceActive = true;'),
          true);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // PART K — 거절
  // ══════════════════════════════════════════════════════════════════

  group('제안을 거절하면 A는 그대로 PENDING이다', () {
    test('거절 경로는 source를 읽지도 쓰지도 않는다', () {
      expect(decline.contains('sourceApplicationId'), true,
          reason: '알림 payload에는 실린다');
      expect(decline.contains('AUTO_CANCELED'), false);
      expect(decline.contains('REASSIGNMENT'), false,
          reason: 'A 상태를 바꾸는 경로가 있으면 안 된다');
    });

    test('관리자에게 제안 거절임을 알린다', () {
      expect(
          decline.contains('type: declineIsReassign ? '
              '"workReassignmentDeclined" : "toInviteDeclined",'),
          true);
      expect(decline.contains('"기존 지원은 그대로 대기 중입니다."'), true);
    });
  });

  group('수락 알림은 초대 수락과 구분된다', () {
    test('관리자 알림 타입이 갈린다', () {
      expect(
          accept.contains('type: acceptIsReassign ? '
              '"workReassignmentAccepted" : "toInviteAccepted",'),
          true);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // PART M — 알림 타입 등록과 라우팅
  // ══════════════════════════════════════════════════════════════════

  group('알림 타입이 canonical하게 등록돼 있다', () {
    final m = _load(_notifModel);

    for (final t in [
      'workReassignmentOffered',
      'workReassignmentAccepted',
      'workReassignmentDeclined',
    ]) {
      test('$t — enum / parser / serializer', () {
        expect(m.contains('$t,'), true, reason: 'enum 누락');
        expect(m.contains("case '$t': return NotificationType.$t;"), true,
            reason: 'parser 누락 — 알림을 읽지 못한다');
        expect(m.contains("case NotificationType.$t: return '$t';"), true,
            reason: 'serializer 누락');
      });
    }

    test('관리자 수신분만 permission-bearing이다', () {
      expect(m.contains("'workReassignmentAccepted',"), true);
      expect(m.contains("'workReassignmentDeclined',"), true);
      // 제안 자체는 근로자가 받는다 — 관리자 권한 집합에 들어가면 안 된다.
      expect(m.contains("'workReassignmentOffered',"), false,
          reason: '근로자 수신 알림을 관리자 권한 집합에 넣지 않는다');
    });

    test('관리자 카테고리에도 결과 알림만 들어간다', () {
      expect(m.contains('NotificationType.workReassignmentAccepted,'), true);
      expect(m.contains('NotificationType.workReassignmentDeclined,'), true);
    });

    test('제안은 근로자가 선택해야 끝나는 알림이다', () {
      expect(m.contains('NotificationType.workReassignmentOffered, };'), true,
          reason: '_actionRequiredTypes 마지막 항목으로 등록');
    });
  });

  group('인앱과 FCM이 같은 목적지를 연다', () {
    final s = _load(_notifScreen);
    final f = _load(_fcm);

    test('제안 → 대상 Application을 정확히 지목한다', () {
      expect(
          s.contains('case NotificationType.workReassignmentOffered: '
              'Navigator.push( context, MaterialPageRoute( builder: (_) => '
              "MyApplicationsScreen( focusApplicationId: "
              "notification.data?['applicationId']?.toString(),"),
          true);
      expect(
          f.contains("case 'workReassignmentOffered': _pushFcmScreen( "
              "destinationKey: 'my_applications', builder: (_) => "
              "MyApplicationsScreen( focusApplicationId: "
              "data['applicationId']?.toString(),"),
          true,
          reason: 'FCM과 인앱이 다른 화면을 열면 안 된다');
    });

    test('결과 알림은 관리자 경로 — canManageTo 게이트를 탄다', () {
      expect(
          s.contains('case NotificationType.workReassignmentAccepted: '
              'case NotificationType.workReassignmentDeclined:'),
          true);
      expect(
          s.contains('requiredPermission: (p) => p.canManageTo,'), true);
      expect(
          f.contains("case 'workReassignmentAccepted': "
              "case 'workReassignmentDeclined': case 'toInviteAccepted':"),
          true,
          reason: '초대 결과와 같은 관리자 경로를 공유한다');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // PART P — 근로자 화면
  // ══════════════════════════════════════════════════════════════════

  group('근로자는 제안과 초대를 구분해서 본다', () {
    final a = _load(_appModel);
    final s = _load(_myApps);

    test('모델이 서버 메타데이터를 읽는다', () {
      expect(a.contains("offerKind: data['offerKind'] as String?,"), true);
      expect(
          a.contains("sourceApplicationId: data['sourceApplicationId'] as String?,"),
          true);
      expect(
          a.contains("reassignedToApplicationId: "
              "data['reassignedToApplicationId'] as String?,"),
          true);
    });

    test('제안 판정은 offerKind 하나로 한다', () {
      expect(
          a.contains("bool get isAlternativeWorkOffer => "
              "offerKind == 'ALTERNATIVE_WORK';"),
          true);
    });

    test('A 종료 판정은 cancelReason 하나로 한다', () {
      expect(
          a.contains("bool get isReassignedAway => status == 'AUTO_CANCELED' "
              "&& cancelReason == 'REASSIGNMENT_ACCEPTED';"),
          true,
          reason: '링크 필드 유무로 추측하지 않는다');
    });

    test("A는 '지원 취소'가 아니라 '다른 업무로 확정됨'이다", () {
      expect(a.contains("if (isReassignedAway) return '다른 업무로 확정됨';"), true);
      expect(
          s.contains("case 'REASSIGNMENT_ACCEPTED': return '제안받은 다른 업무로 확정됐어요';"),
          true);
    });

    test('제안 카드는 무엇을 포기하는지 먼저 말한다', () {
      expect(s.contains("isOffer ? '다른 업무 제안이 도착했어요' : '근무 초대가 도착했어요'"),
          true);
      expect(s.contains('은 자동으로 정리돼요'), true);
    });

    test('CTA는 [거절] [제안 조건으로 수락]이다', () {
      expect(s.contains("label: isOffer ? '제안 조건으로 수락' : '수락하기',"), true);
      expect(s.contains("label: '거절',"), true);
    });

    test('수락 전에 A와 B를 나란히 보여준다', () {
      expect(s.contains("label: '기존 지원',"), true);
      expect(s.contains('label: offerApp.hasIndividualCompensation'), true,
          reason: '개별 급여면 그 사실을 라벨이 말한다');
      expect(s.contains("'제안받은 업무'"), true);
      // [R5.3D.1] 이력은 남는다 — 사라지는 것은 불이익이다.
      expect(s.contains('취소·노쇼 불이익은 적용되지 않습니다.'), true);
      expect(s.contains('취소 이력이나 불이익은 남지 않아요'), false);
    });

    test('동의는 이 건에 대해 지금 받는다', () {
      expect(
          s.contains("'documentAccessConsentVersion': DocumentAccessConsent.version,"),
          true);
      expect(s.contains("isOfferAccept ? '동의하고 제안 수락' : '동의하고 초대 수락'"), true);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // PART O — 관리자 화면
  // ══════════════════════════════════════════════════════════════════

  group('관리자는 바꾸지 않고 제안한다', () {
    final sheet = _load(_offerSheet);
    final w = _load(_workDlg);
    final d = _load(_dayDlg);

    test("'업무를 바로 변경'이라고 말하지 않는다", () {
      for (final s in [sheet, w, d]) {
        expect(s.contains('업무를 바로 변경'), false);
        expect(s.contains("label: '파트변경',"), false);
      }
    });

    test('제안은 근로자가 선택한다고 말한다', () {
      expect(sheet.contains('제안을 보내면 근로자가 조건을 보고 직접 선택합니다.'), true);
      expect(sheet.contains('지금 지원은 그대로 유지되고, 근로자가 제안을 수락할 때만 정리됩니다.'),
          true);
      expect(sheet.contains('거절하면 기존 지원은 대기 상태 그대로입니다.'), true);
    });

    test('A와 B를 같은 축으로 보여준다 — 시간·기본임금·휴게·남은 자리', () {
      expect(sheet.contains(r"'${work.startTime}~${work.endTime} · ${work.formattedWage}'"),
          true);
      expect(sheet.contains(r"'휴게 ${work.breakMinutes}분',"), true);
      expect(sheet.contains(r"if (remain != null) '남은 자리 $remain명',"), true);
    });

    test('정원을 모르면 남은 자리를 말하지 않는다', () {
      expect(
          sheet.contains('final remain = work.requiredCount > 0 ? '
              'work.requiredCount - confirmedCount : null;'),
          true,
          reason: '모름을 0으로 쓰지 않는다');
    });

    test('후보 판정은 한 곳에 있다', () {
      expect(sheet.contains('static List<WorkDetailModel> offerableFrom('), true);
      expect(w.contains('AlternativeWorkOfferSheet.offerableFrom('), true);
      expect(d.contains('AlternativeWorkOfferSheet.offerableFrom('), true);
    });

    test('마감된 업무와 wdId 없는 legacy는 후보가 아니다', () {
      expect(sheet.contains('if (w.id.isEmpty) return false;'), true);
      expect(sheet.contains('if (w.isClosed) return false;'), true);
    });

    test('CTA는 PENDING 지원자에게만 뜬다', () {
      expect(
          w.contains('if (isPending && !_isBatchMode && _canManageTo()) ...['),
          true);
      expect(w.contains("label: '다른 업무 제안',"), true);
      expect(d.contains('if (isPending && !_isBatchMode && canManageTo) ...['), true);
      expect(d.contains("label: '다른 업무 제안',"), true);
    });

    test('제안할 업무가 있을 때만 CTA를 띄운다', () {
      expect(w.contains('if (_offerableWorkDetails(app).isNotEmpty) ...['), true);
    });

    test('클라이언트는 금액을 보내지 않는다 — 옵션만 보낸다', () {
      expect(sheet.contains("'compensationOption': option,"), true);
      // 임의 금액 입력란이 없다.
      expect(sheet.contains('TextField'), false);
      expect(sheet.contains('TextEditingController'), false);
      expect(sheet.contains("'sourceApplicationId': sourceApplicationId,"), true);
      expect(sheet.contains("'targetWdId': target.id,"), true);
      expect(RegExp(r"'wage'\s*:").hasMatch(sheet), false);
    });

    test('상시 listener나 polling을 추가하지 않는다', () {
      expect(d.contains('await _svc.getSlotWorkDetails(toId, slotId);'), true,
          reason: '눌렀을 때만 읽는다');
      for (final s in [sheet, d]) {
        expect(s.contains('Timer.periodic'), false);
        expect(s.contains('.snapshots()'), false);
      }
    });

    test('슬롯 읽기 실패를 "제안할 업무 없음"으로 바꾸지 않는다', () {
      expect(d.contains("ToastHelper.showError('업무 목록을 불러오지 못했습니다. 다시 시도해주세요.');"),
          true);
      expect(
          _load('lib/services/firestore/to_firestore.dart')
              .contains('Future<List<WorkDetailData>> getSlotWorkDetails('),
          true);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // PART N — 관계 카운터를 사람 수로 말하지 않는다
  // ══════════════════════════════════════════════════════════════════

  group('대기 카운터는 건수이지 사람 수가 아니다', () {
    test('관리자 홈 일자 요약', () {
      expect(
          _load('lib/screens/business_admin/business_admin_home_screen.dart')
              .contains(r"parts.add('지원 대기 ${day.pendingCount}건');"),
          true);
    });

    test('승인 대기 캘린더', () {
      expect(
          _load('lib/screens/business_admin/dialogs/pending_approval_calendar_dialog.dart')
              .contains(r"'$count건 대기',"),
          true);
    });

    test('날짜별 지원자 섹션', () {
      expect(_load(_dayDlg).contains(r"'지원 (${g.pendingApps.length}건)'"), true);
    });

    test('충원 가능 판단만은 사람 수로 센다', () {
      expect(
          _load(_dayDlg).contains('final isPendingSufficient = '
              'g.pendingApps.map((a) => a.uid).toSet().length >= shortage;'),
          true,
          reason: '한 사람이 A·B 두 건이어도 메울 수 있는 자리는 하나다');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // [R5.3B.1] PART O — 알림 identity / dedupe
  // ══════════════════════════════════════════════════════════════════

  group('제안 재시도는 복구다 (POST_COMMIT_IDEMPOTENT_RECONCILABLE)', () {
    test('알림 쓰기가 커밋된 offerId만 쓴다', () {
      expect(
          offer.contains('const writeOfferedNotification = async ( '
              'committedOfferId: string ): '
              'Promise<"created" | "exists" | "failed"> => {'),
          true);
      expect(
          offer.contains('.doc(`work_reassignment_offered_'
              '\${committedOfferId}`) .create({'),
          true,
          reason: '.create()이므로 같은 id로 두 번 만들어지지 않는다');
    });

    test('retry-stable identity는 Application 자연키다', () {
      // 재시도는 offerId를 새로 만들지 않고 **저장된 값을 읽어** 쓴다.
      // offerId 안의 timestamp 자체가 결정적인 것이 아니다.
      expect(
          offer.contains("const tOfferId = tExisting[\"offerId\"] as string | undefined;"),
          true);
      expect(offer.contains('const repaired = await writeOfferedNotification(tOfferId);'),
          true);
    });

    test('같은 source의 살아 있는 제안만 멱등 재시도로 본다', () {
      expect(
          offer.contains('const sameLiveOffer = '
              'tExisting["offerKind"] === "ALTERNATIVE_WORK" && '
              'tExisting["sourceApplicationId"] === sourceApplicationId && '
              '!!tOfferId;'),
          true);
      expect(
          offer.contains('if (!sameLiveOffer) { throw new HttpsError( '
              '"already-exists", "이미 이 업무를 제안했습니다.");'),
          true,
          reason: '일반 초대나 다른 출처는 재시도가 아니다');
    });

    test('멱등 분기는 상태도 카운터도 건드리지 않는다', () {
      final branch = offer.substring(
          offer.indexOf('const sameLiveOffer'),
          offer.indexOf('alreadyOffered: true,'));
      for (final w in ['increment(', 'tx.update', 'offerTx', 'status:']) {
        expect(branch.contains(w), false, reason: '멱등 분기에서 $w');
      }
    });

    test('멱등 응답이 같은 offerId를 돌려준다', () {
      expect(
          offer.contains('return { success: true, offerId: tOfferId, '
              'targetApplicationId: targetAppId, alreadyOffered: true,'),
          true);
    });

    test('정상 경로도 알림 결과를 숨기지 않는다', () {
      expect(
          offer.contains('const notifResult = await writeOfferedNotification(offerId);'),
          true);
      expect(offer.contains('notificationDelivered: notifResult !== "failed",'), true,
          reason: '실패를 성공처럼 반환하지 않는다');
    });
  });

  group('알림 payload는 상태를 싣지 않는다', () {
    test('offered payload에 7개 식별자가 있다', () {
      final block = offer.substring(
          offer.indexOf('type: "workReassignmentOffered"'),
          offer.indexOf('action: "alternativeWorkOffer",'));
      for (final f in [
        'offerId: committedOfferId,', 'applicationId: targetAppId,',
        'targetApplicationId: targetAppId,', 'sourceApplicationId,',
        'businessId: offerBizId,', 'toId: offerToId,',
        'slotId: offerSlotId,', 'targetWdId,',
      ]) {
        expect(block.contains(f), true, reason: 'payload 누락: $f');
      }
      // 상태를 실으면 dispatcher가 그것을 믿게 된다 — 지금 읽어야 한다.
      expect(block.contains('status:'), false);
      expect(block.contains('actionable'), false);
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // [R5.3B.1] 공고 상세의 수락도 같은 문턱을 쓴다
  // ══════════════════════════════════════════════════════════════════

  group('두 수락 경로가 같은 payload를 보낸다', () {
    final posting = _load('lib/screens/common/job_posting_screen.dart');

    test('상세 화면도 서류 전제조건을 본다', () {
      // [PII-B4-R1.4] 세무 축이 인자로 더해졌다 — 게이트는 여전히 하나다.
      expect(posting.contains('meetsApplyPrerequisites(user,'), true);
      expect(
          posting.contains('isFlexType: isFlex, taxStatus: acceptTax)'), true);
    });

    test('상세 화면도 이 건에 대한 동의를 받는다', () {
      expect(posting.contains('DocumentAccessConsent.card(app.businessName),'), true);
      expect(
          posting.contains("'documentAccessConsentGiven': true, "
              "'documentAccessConsentVersion': DocumentAccessConsent.version,"),
          true,
          reason: 'R5.2 이후 applicationId만 보내면 서버가 거부한다');
    });

    test('상세 화면도 제안과 초대를 구분해 말한다', () {
      expect(
          posting.contains("title: isOffer ? '다른 업무 제안 수락' : '초대 수락',"), true);
      expect(posting.contains("은 '다른 업무로 확정됨'으로 정리됩니다."), true);
      expect(
          posting.contains("? '제안 수락' : '초대 수락'),"), true,
          reason: 'CTA 라벨도 사실을 말한다');
    });

    test('원 지원서를 못 찾으면 비교만 생략한다', () {
      final mine = _load(_myApps);
      expect(
          mine.contains('final one = await _firestoreService '
              '.getApplicationOnce(offerApp.sourceApplicationId!); '
              'if (one != null && one.uid == uid) sourceApp = one;'),
          true,
          reason: '첫 페이지 밖의 A도 비교에 쓴다');
      expect(mine.contains("debugPrint('⚠️ [R5.3B.1] 원 지원서 조회 실패: \$e');"), true,
          reason: '읽지 못한 것을 없다고 말하지 않는다');
    });
  });

  // ══════════════════════════════════════════════════════════════════
  // 얼린 경로는 얼린 채로 남는다
  // ══════════════════════════════════════════════════════════════════

  group('R5.3A freeze는 유지된다', () {
    test('파트변경 direct mutation은 여전히 거절한다', () {
      expect(
          cf.contains('"파트변경은 더 이상 지원되지 않습니다. 지원자에게 \'다른 업무 제안\'을 보내 "'),
          true);
    });

    test('confirmed 조건변경 경로를 만들지 않았다', () {
      // source가 CONFIRMED면 거절한다(PENDING만 허용) — 위 테스트가 고정한다.
      // 대상 업무에 이미 확정된 관계가 있어도 새 제안을 만들지 않는다.
      expect(
          offer.contains('if (tStatus === "CONFIRMED" || '
              'tStatus === "CONTRACT_PENDING") { throw new HttpsError( '
              '"already-exists", "이미 이 업무에 확정된 근로자입니다.");'),
          true);
      // 확정된 Application의 조건을 고쳐 쓰는 경로는 없다.
      expect(offer.contains('status: "CONFIRMED"'), false,
          reason: '제안 writer가 확정을 만들지 않는다 — 확정은 수락에서만 일어난다');
    });
  });
}
