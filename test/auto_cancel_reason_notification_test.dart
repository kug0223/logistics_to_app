// [R7-APPLICATION-LIFECYCLE.1E] 일정 겹침으로 접힌 지원 —
// 근로자가 **왜** 끝났는지 알고, 알림은 **입구와 무관하게 한 번** 생긴다.
//
// ── 고친 결함 둘 ────────────────────────────────────────────────
//   ① 이유: canonical 상태 라벨(`ApplicationModel.statusText`)이
//      `AUTO_CANCELED` 를 전부 `자동 취소됨` 으로 말했다. 탈퇴·재배치는 이미
//      사건을 구분했는데 **일정 겹침만** generic 이었다. 그 라벨을 쓰는 모든
//      화면(홈 최근 지원·공고 상세 배지 등)에서 근로자는 자기가 무엇을
//      잘못했는지 짐작해야 했다.
//   ② 알림: 접힌 지원자에게 가는 알림의 주인이 **확정한 관리자의 기기**였다.
//      `callableConfirmApplication` 이 `autoCanceledDetails` 를 돌려주고
//      관리자 클라이언트가 `createNotification` 을 호출하는 구조.
//        · 검토 승인·초대 수락·재배치 수락·연장 수락에서는 알림 코드가 없었다
//        · 다른 사업장 건은 `createNotification` 이 권한으로 거부했다
//          ("해당 사업장 관리자와 근무자 간 알림만 허용됩니다")
//        · 관리자 앱이 죽으면 알림 계약도 사라졌다
//
// ── 고정하는 계약 ───────────────────────────────────────────────
//   · 이유 문장은 canonical 사전 하나(`workerEndReasonSentence`)에서 온다.
//   · 알림은 좌석 계약의 **쓰기 단계**에서 취소와 같은 트랜잭션에 만든다 →
//     다섯 writer 가 모두 그 함수를 지나므로 입구에 무관하다.
//   · id 가 결정적이므로 재시도·트랜잭션 재실행에도 문서는 하나다.
//   · 수신자는 접힌 지원서의 주인이다(확정한 관리자 아님).
//   · 관리자 화면에는 다른 사업장 이름·시간을 넣지 않는다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('없는 파일: $p');
  return f.readAsStringSync();
}

const _kFn = 'functions/src/index.ts';
const _kModel = 'lib/models/core/application_model.dart';
const _kMyApps = 'lib/screens/user/my_applications_screen.dart';
const _kAppSvc = 'lib/services/firestore/application_firestore.dart';
const _kMgrDialog =
    'lib/screens/business_admin/dialogs/day_applicants_dialog.dart';

ApplicationModel _app({
  String status = AppStatus.autoCanceled,
  String? cancelReason,
  String? conflictingBusiness,
  String? conflictingTime,
  String? resignStatus,
  String? terminationStatus,
}) =>
    ApplicationModel(
      id: 'app1',
      uid: 'worker1',
      toId: 'to1',
      businessId: 'biz1',
      businessName: '내 사업장',
      toTitle: '공고',
      selectedWorkType: '홀서빙',
      startTime: '13:00',
      endTime: '22:00',
      wage: 12000,
      wageType: 'hourly',
      status: status,
      cancelReason: cancelReason,
      conflictingBusiness: conflictingBusiness,
      conflictingTime: conflictingTime,
      resignStatus: resignStatus,
      terminationStatus: terminationStatus,
      workDate: DateTime.utc(2026, 11, 10),
      appliedAt: DateTime(2026, 11, 1),
    );

void main() {
  // ══ R1~R6 근로자/관리자 이유 표현 ═══════════════════════════════════════
  group('ACR-R 이유 표현', () {
    test('R1 SCHEDULE_CONFLICT 는 generic 라벨이 아니다', () {
      final a = _app(cancelReason: 'SCHEDULE_CONFLICT');
      expect(a.statusText, isNot('자동 취소됨'));
      expect(a.statusText, '일정 겹침으로 자동 취소');
      expect(a.workerEndReasonSentence, '확정된 일정과 시간이 겹쳐 자동 취소됐어요');
    });

    test('R2 REASSIGNMENT_ACCEPTED 전용 문구가 그대로다', () {
      final a = _app(cancelReason: 'REASSIGNMENT_ACCEPTED');
      expect(a.workerEndReasonSentence, '제안받은 다른 업무로 확정됐어요');
    });

    test('R2b 확정 재배치의 A 쪽도 취소가 아니라고 말한다', () {
      // DEV 실측에서 나온 코드다 — `callableAcceptConfirmedReassignment` 가
      //   source 지원서에 `CONFIRMED_REASSIGNMENT_ACCEPTED` 를 남긴다.
      final a = _app(cancelReason: 'CONFIRMED_REASSIGNMENT_ACCEPTED');
      expect(a.workerEndReasonSentence, '같은 사업장의 다른 업무로 변경 확정됐어요');
      expect(a.workerEndReasonSentence, isNot('취소된 지원이에요'));
      // 상태 라벨은 기존 술어가 이미 구분한다 — 사전과 라벨이 따로 놀지 않는다.
      expect(a.isConfirmedReassignedAway, isTrue);
      expect(a.statusText, '다른 업무로 변경 확정');
    });

    test('R3 ACCOUNT_DELETED 전용 문구가 그대로다', () {
      final a = _app(cancelReason: 'ACCOUNT_DELETED');
      expect(a.statusText, '탈퇴로 종료');
      expect(a.workerEndReasonSentence, '탈퇴 처리로 종료된 지원이에요');
    });

    test('R4 모르는/없는 이유는 generic fallback 이다', () {
      expect(_app(cancelReason: null).statusText, '자동 취소됨');
      expect(_app(cancelReason: 'SOME_LEGACY_CODE').statusText, '자동 취소됨');
      expect(_app(cancelReason: null).workerEndReasonSentence, '취소된 지원이에요');
      expect(_app(cancelReason: 'SOME_LEGACY_CODE').workerEndReasonSentence,
          '취소된 지원이에요');
    });

    test('R4b 기존 이유 사전이 빠짐없이 옮겨졌다', () {
      const expected = {
        'USER_CANCELED': '지원이 취소되었어요',
        'SAME_DAY_CANCEL': '당일 취소 처리된 지원이에요',
        'ADMIN_CANCELED': '사업장 사정으로 근무가 취소되었어요',
        'WORK_DETAIL_EXPIRED': '해당 업무 모집이 마감되었어요',
        'SLOT_WORK_DETAIL_EXPIRED': '해당 업무 모집이 마감되었어요',
        'TO_EXPIRED': '모집 기간이 종료되어 자동 취소되었어요',
        'TO_DELETED': '공고가 삭제되어 자동 취소되었어요',
      };
      for (final e in expected.entries) {
        expect(_app(cancelReason: e.key).workerEndReasonSentence, e.value,
            reason: e.key);
      }
    });

    test('R4c 불이익을 말하는 어휘를 쓰지 않는다', () {
      final a = _app(cancelReason: 'SCHEDULE_CONFLICT');
      for (final banned in ['불이익', '신뢰도', '노쇼', '패널티', '제한']) {
        expect(a.statusText.contains(banned), isFalse, reason: banned);
        expect(a.workerEndReasonSentence.contains(banned), isFalse,
            reason: banned);
      }
    });

    test('R5 내 다른 약속의 맥락 — 저장된 값이 있을 때만', () {
      final withBoth = _app(
          cancelReason: 'SCHEDULE_CONFLICT',
          conflictingBusiness: '다른 사업장',
          conflictingTime: '09:00~18:00');
      expect(withBoth.scheduleConflictContext, '확정된 근무: 다른 사업장 · 09:00~18:00');

      // 일부만 있어도 있는 것만 말한다.
      expect(
          _app(cancelReason: 'SCHEDULE_CONFLICT', conflictingTime: '09:00~18:00')
              .scheduleConflictContext,
          '확정된 근무: 09:00~18:00');
      expect(
          _app(cancelReason: 'SCHEDULE_CONFLICT', conflictingBusiness: 'A')
              .scheduleConflictContext,
          '확정된 근무: A');
      // 아무것도 없으면 만들지 않는다.
      expect(_app(cancelReason: 'SCHEDULE_CONFLICT').scheduleConflictContext,
          isNull);
      // 다른 이유에는 맥락이 없다.
      expect(_app(cancelReason: 'USER_CANCELED', conflictingBusiness: 'A')
          .scheduleConflictContext, isNull);
    });

    test('R6 관리자 화면에는 다른 사업장 이름·시간을 넣지 않는다', () {
      final mgr = _read(_kMgrDialog);
      // 관리자는 비민감 문구만 쓴다.
      expect(mgr.contains("'SCHEDULE_CONFLICT' => '일정 겹침 종료'"), isTrue);
      // 근로자용 맥락/문장 helper 를 관리자 화면이 쓰지 않는다.
      expect(mgr.contains('scheduleConflictContext'), isFalse);
      expect(mgr.contains('workerEndReasonSentence'), isFalse);
      expect(mgr.contains('conflictingBusiness'), isFalse);
      expect(mgr.contains('conflictingTime'), isFalse);
    });
  });

  // ══ 소스 계약 — 이유 ════════════════════════════════════════════════════
  group('ACR-S 이유 소스 계약', () {
    test('S1 사전은 한 곳이다 — 화면 사본 0', () {
      final m = _read(_kModel);
      expect(m.contains('String get workerEndReasonSentence'), isTrue);
      final my = _read(_kMyApps);
      expect(my.contains('String _cancelReasonText('), isFalse,
          reason: '화면에 사본이 남으면 한쪽만 고쳐진다');
      expect(my.contains('app.workerEndReasonSentence'), isTrue);
      expect(my.contains('app.scheduleConflictContext'), isTrue);
    });

    test('S2 canonical 라벨이 일정 겹침을 구분한다', () {
      final m = _read(_kModel);
      expect(
          m.contains(
              "if (status == 'AUTO_CANCELED' && cancelReason == 'SCHEDULE_CONFLICT')"),
          isTrue);
      // 기존 분기(탈퇴·재배치)도 그대로다.
      expect(m.contains("cancelReason == 'ACCOUNT_DELETED'"), isTrue);
      expect(m.contains('if (isReassignedAway) return'), isTrue);
    });
  });

  // ══ N1~N16 알림 owner / parity / dedupe ═════════════════════════════════
  group('ACR-N 알림 계약', () {
    late String fn;
    late String applyFn;

    setUpAll(() {
      fn = _read(_kFn);
      final start = fn.indexOf('function srvApplySeatCommitOverlap(');
      expect(start, greaterThan(-1));
      final end = fn.indexOf('⏰ 지각 처리', start);
      expect(end, greaterThan(start));
      applyFn = fn.substring(start, end);
    });

    test('N1 알림 owner 는 공용 좌석 계약 한 곳이다', () {
      expect(applyFn.contains('srvPersistNotificationInTx('), isTrue);
      expect(applyFn.contains('schedule_conflict_autocancel_'), isTrue);
      // 전역에서도 이 이벤트를 만드는 자리는 하나다.
      expect(
          RegExp(r'schedule_conflict_autocancel_').allMatches(fn).length, 1);
      // 좌석 계약이 notifications 컬렉션을 직접 쓰지 않는다 — writer 가
      // 흩어지면 탈퇴 barrier 같은 공통 판단이 한쪽에만 적용된다.
      expect(applyFn.contains('.collection("notifications")'), isFalse);
    });

    test('N1b canonical in-tx writer 가 비동기 버전과 같은 판단을 한다', () {
      final i = fn.indexOf('function srvPersistNotificationInTx(');
      expect(i, greaterThan(-1));
      final w = fn.substring(i, fn.indexOf('\n}', i));
      // 수신자/ id 형식 검증은 비동기 버전과 동일하다.
      expect(w.contains('recipientUid.includes("/")'), isTrue);
      expect(w.contains('notificationId.includes("/")'), isTrue);
      // 쓰기는 set 이다 — create 는 호출자의 도메인 커밋을 실패시킨다.
      expect(w.contains('tx.set('), isTrue);
      expect(w.contains('tx.create('), isFalse);
      // 트랜잭션 안에서 읽거나 네트워크를 타지 않는다.
      expect(w.contains('await '), isFalse);
      expect(w.contains('tx.get('), isFalse);
    });

    test('N1c 탈퇴 barrier 를 건너뛰지 않는다 — 읽기 단계에서 읽는다', () {
      final c = fn.indexOf('async function srvCollectSeatCommitOverlap(');
      final cEnd = fn.indexOf('function srvApplySeatCommitOverlap(', c);
      final collect = fn.substring(c, cEnd);
      expect(collect.contains('srvDeletionBarrierExistsInTx(tx, applicantUid)'),
          isTrue);
      expect(collect.contains('notifySuppressed'), isTrue);
      // 쓰기 단계는 그 판정을 조건으로 쓴다.
      expect(applyFn.contains('!plan.notifySuppressed'), isTrue);
      // barrier 는 알림만 막는다 — 취소·카운터는 그대로 간다.
      final guardAt = applyFn.indexOf('if (loserUid && !plan.notifySuppressed)');
      expect(guardAt, greaterThan(applyFn.indexOf('increment(-1)')));
      // 루프 앞에서 판정을 보지 않는다 — 그러면 취소 자체가 막힌다.
      expect(applyFn.indexOf('notifySuppressed'),
          greaterThan(applyFn.indexOf('for (const doc of plan.toCancel)')));
    });

    test('N2 다섯 writer 가 모두 그 함수를 지난다', () {
      for (final name in [
        'callableConfirmApplication',
        'callableApproveApplicationForReview',
        'callableAcceptTOInvitation',
        'callableAcceptConfirmedReassignment',
        'callableAcceptRenewalProposal',
      ]) {
        final i = fn.indexOf('export const $name');
        expect(i, greaterThan(-1), reason: name);
        final body = fn.substring(i, (i + 60000).clamp(0, fn.length));
        expect(body.contains('srvApplySeatCommitOverlap('), isTrue,
            reason: name);
      }
    });

    test('N3 취소와 같은 트랜잭션에 쓴다 — 관리자 기기와 무관', () {
      // 같은 `tx` 로 쓴다(별도 커밋·후처리가 아니다).
      expect(applyFn.contains('srvPersistNotificationInTx(\n        tx, loserUid,'),
          isTrue);
      expect(applyFn.contains('tx.update(doc.ref,'), isTrue);
      // 트랜잭션 안에서 푸시(네트워크)를 하지 않는다 — 재시도 중복 방지.
      expect(applyFn.contains('messaging()'), isFalse);
      expect(applyFn.contains('sendEachForMulticast'), isFalse);
      expect(applyFn.contains('await '), isFalse, reason: '쓰기 단계는 동기다');
    });

    test('N4 푸시는 기존 디스패처가 맡는다 — 새 트리거 0', () {
      expect(
          fn.contains('document: "users/{userId}/notifications/{notificationId}"'),
          isTrue);
      final triggers = RegExp(
              r'document: "users/\{userId\}/notifications/\{notificationId\}"')
          .allMatches(fn)
          .length;
      expect(triggers, 1, reason: '디스패처를 새로 만들지 않는다');
    });

    test('N5 dedupe — id 가 결정적이고 create 가 아니라 set 이다', () {
      expect(
          applyFn.contains('`schedule_conflict_autocancel_\${doc.id}`'), isTrue);
      expect(applyFn.contains('tx.create('), isFalse,
          reason: 'create 는 재시도에서 확정 자체를 실패시킨다');
    });

    test('N6 수신자는 접힌 지원서의 주인이다', () {
      expect(applyFn.contains('const loserUid = d.uid as string | undefined;'),
          isTrue);
      expect(applyFn.contains('tx, loserUid,'), isTrue);
      expect(applyFn.contains('userId: loserUid,'), isTrue);
      // 확정한 관리자(callerUid)에게 보내지 않는다.
      expect(applyFn.contains('callerUid'), isFalse);
    });

    test('N7 loser 가 없으면 알림도 없다', () {
      // 알림 쓰기가 toCancel 루프 **안에** 있다.
      final loopAt = applyFn.indexOf('for (const doc of plan.toCancel)');
      final notifAt = applyFn.indexOf('srvPersistNotificationInTx(');
      expect(loopAt, greaterThan(-1));
      expect(notifAt, greaterThan(loopAt));
    });

    test('N7b 조건은 loser·barrier 둘뿐이다 — dead-code 로 꺼지지 않는다', () {
      // `if (false) ...` 처럼 문자열은 남고 실행만 꺼지는 변경을 존재 검사로는
      // 잡을 수 없다. 그래서 guard 사슬을 직접 고정한다.
      const guard = 'if (loserUid && !plan.notifySuppressed) {';
      final guardAt = applyFn.indexOf(guard);
      final notifAt = applyFn.indexOf('srvPersistNotificationInTx(');
      expect(guardAt, greaterThan(-1));
      expect(notifAt, greaterThan(guardAt));
      final between = applyFn.substring(guardAt + guard.length, notifAt);
      expect(between.contains('if ('), isFalse, reason: '추가 조건이 알림을 꺼뜨린다');
      expect(between.contains('return'), isFalse);
      expect(between.contains('continue'), isFalse);
      // 루프와 guard 사이에도 알림만 건너뛰는 조건이 없다.
      final loopAt = applyFn.indexOf('for (const doc of plan.toCancel)');
      final toGuard = applyFn.substring(loopAt, guardAt);
      expect(toGuard.contains('continue;'), isFalse);
    });

    test('N8 레거시 클라이언트 emitter 가 제거됐다', () {
      final svc = _read(_kAppSvc);
      expect(svc.contains('_sendApplicationAutoCanceledNotification'), isTrue,
          reason: '제거 사실을 설명하는 주석은 남는다');
      expect(svc.contains('Future<void> _sendApplicationAutoCanceledNotification('),
          isFalse, reason: '함수 정의가 남아 있으면 다시 불릴 수 있다');
      expect(svc.contains('NotificationModel.createApplicationAutoCanceled'),
          isFalse);
      // 응답 필드는 유지한다 — 캐시 무효화가 그 값을 쓰고, 구버전 호환이다.
      expect(svc.contains("data['autoCanceledDetails']"), isTrue);
      expect(fn.contains('autoCanceledDetails:'), isTrue);
    });

    test('N9 알림 본문에 불이익 어휘가 없다', () {
      final bodyAt = applyFn.indexOf('body:');
      expect(bodyAt, greaterThan(-1));
      final body = applyFn.substring(bodyAt, bodyAt + 300);
      for (final banned in ['불이익', '신뢰도', '노쇼', '패널티']) {
        expect(body.contains(banned), isFalse, reason: banned);
      }
      expect(body.contains('확정된 일정과 시간이 겹쳐'), isTrue);
    });

    test('N10 딥링크는 접힌 지원서를 가리킨다', () {
      expect(applyFn.contains('applicationId: doc.id,'), isTrue);
      expect(applyFn.contains('action: "applicationDetail"'), isTrue);
      expect(applyFn.contains('reason: "SCHEDULE_CONFLICT"'), isTrue);
    });

    test('N11 기존 타입을 재사용한다 — 클라이언트 파서 변경 0', () {
      expect(applyFn.contains('type: "confirmationCanceled"'), isTrue);
      final model = _read('lib/models/core/notification_model.dart');
      expect(model.contains("case 'confirmationCanceled':"), isTrue);
    });

    test('N12 취소 메타데이터는 그대로 저장된다', () {
      expect(applyFn.contains('cancelReason: "SCHEDULE_CONFLICT"'), isTrue);
      expect(applyFn.contains('conflictingBusiness: plan.businessName'), isTrue);
      expect(applyFn.contains('conflictingTime:'), isTrue);
      // 신뢰도 패널티를 쓰지 않는다.
      expect(applyFn.contains('reliability'), isFalse);
      expect(applyFn.contains('noShow'), isFalse);
    });

    test('N13 좌석 카운터 계약이 그대로다', () {
      expect(
          applyFn.contains('`workDetailCounts.\${cWdId}.pendingCount`'), isTrue);
      expect(applyFn.contains('increment(-1)'), isTrue);
    });
  });

  // ══ 렌더 — 근로자 화면에 이유가 보인다 ═════════════════════════════════
  group('ACR-V 렌더', () {
    Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('V1 일정 겹침 이유와 맥락이 글자로 보인다', (tester) async {
      final a = _app(
          cancelReason: 'SCHEDULE_CONFLICT',
          conflictingBusiness: '다른 사업장',
          conflictingTime: '09:00~18:00');
      await tester.pumpWidget(wrap(Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(a.statusText),
          Text(a.workerEndReasonSentence),
          if (a.scheduleConflictContext != null)
            Text(a.scheduleConflictContext!),
        ],
      )));
      expect(find.text('일정 겹침으로 자동 취소'), findsOneWidget);
      expect(find.text('확정된 일정과 시간이 겹쳐 자동 취소됐어요'), findsOneWidget);
      expect(find.text('확정된 근무: 다른 사업장 · 09:00~18:00'), findsOneWidget);
      expect(find.text('자동 취소됨'), findsNothing);
    });

    testWidgets('V2 좁은 폭·큰 배율에서도 이유를 가리지 않는다', (tester) async {
      final a = _app(
          cancelReason: 'SCHEDULE_CONFLICT',
          conflictingBusiness: '아주 긴 사업장 이름을 가진 강남 물류센터 제2창고',
          conflictingTime: '09:00~18:00');
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(
              size: Size(320, 800), textScaler: TextScaler.linear(2.0)),
          child: Scaffold(
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.workerEndReasonSentence),
                Text(a.scheduleConflictContext!),
              ],
            ),
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      // 핵심 이유가 ellipsis 로 숨지 않는다.
      final t = tester.widget<Text>(find.text(a.workerEndReasonSentence));
      expect(t.overflow, anyOf(isNull, TextOverflow.clip));
    });
  });
}
