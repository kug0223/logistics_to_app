// [E1-AMBIGUOUS-INVITE] 초대 저장 시도 뒤 응답이 불명확한 경우를 취소와
// 구분하고, 대상 지원서를 **다시 읽어 확인한 경우에만** 상위로 반영한다.
//
// ── 무엇이 끊겨 있었나 ────────────────────────────────────────────────
//   직접 초대 창은 저장 중 오류가 나면 닫히지 않았고, 사용자가 닫으면
//   `false`(=취소)를 돌려줬다. 실제로는 서버가 저장했을 수 있는데도
//   공고 카드·목록이 반영하지 않았다. 가능일 시트는 같은 경우를
//   "제안 전송에 실패했습니다"로 단정했다.
//
// ── 이 테스트가 실행하는 것 ───────────────────────────────────────────
//   IAS-A  불명확/명확 오류 분류
//   IAS-B  대상 지원서 확인(saved / notSaved / unknown)과 닫힘 결과 확정
//   IAS-C  직접 초대 창 — 성공·취소·명확한 실패·타임아웃 후 저장·
//          재조회 실패·재시도(중복 방지)·좁은 화면
//   IAS-D  가능일 시트 — 타임아웃 후 저장·재조회 실패·`다시 확인`
import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/available_worker_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/ui/invite_refresh_outcome.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/available_workers_bottom_sheet.dart';
import 'package:ALfit/screens/business_admin/dialogs/invite_worker_dialog.dart';
import 'package:ALfit/services/available_workers_service.dart';
import 'package:ALfit/services/invite_save_verifier.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

// ── Firebase core 대역(다른 테스트와 같은 레시피) ─────────────────────────
class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _Admin extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'admin1',
        username: 'admin1',
        name: '관리자',
        email: 'admin1@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        createdAt: DateTime(2026, 1, 1),
      );
}

const kBiz = 'biz1';
const kTo = 'to1';
const kSlot = 'slot1';
const kWorker = 'w1';

FirebaseFunctionsException _ffe(String code) =>
    FirebaseFunctionsException(message: 'm-$code', code: code);

Map<String, dynamic> _invitedRow({String slotId = kSlot, String uid = kWorker}) =>
    {
      'uid': uid,
      'toId': kTo,
      'slotId': slotId,
      'status': 'INVITED',
      'invitedAt': '2026-10-15T09:00:00Z',
    };

/// 대상 지원서 읽기 대역 — 순서대로 응답한다. 호출 기록을 남긴다.
class _Reader {
  _Reader(this.responses);
  final List<Object> responses; // List<Map> 또는 Exception
  final calls = <Map<String, dynamic>>[];
  Future<List<Map<String, dynamic>>> call(Map<String, dynamic> p) async {
    calls.add(p);
    final r = responses.isEmpty ? <Map<String, dynamic>>[] : responses.removeAt(0);
    if (r is Exception) throw r;
    return (r as List).cast<Map<String, dynamic>>();
  }
}

void main() {
  setUpAll(() {
    FirebasePlatform.instance = _FakeCore();
  });
  tearDown(() {
    InviteSaveVerifier.debugReader = null;
    InviteWorkerDialog.debugFindUser = null;
    InviteWorkerDialog.debugSendInvite = null;
  });

  group('IAS-A 오류 분류', () {
    test('IAS-01 서버가 쓰기 전에 거절하는 코드는 명확한 실패다', () {
      for (final c in [
        'invalid-argument',
        'failed-precondition',
        'permission-denied',
        'not-found',
        'already-exists',
        'resource-exhausted',
        'unauthenticated',
      ]) {
        expect(isAmbiguousInviteError(_ffe(c)), isFalse, reason: c);
      }
    });

    test('IAS-02 시간 초과·연결·internal·알 수 없는 예외는 불명확하다', () {
      for (final c in ['deadline-exceeded', 'unavailable', 'internal', 'unknown', 'aborted']) {
        expect(isAmbiguousInviteError(_ffe(c)), isTrue, reason: c);
      }
      expect(isAmbiguousInviteError(TimeoutException('t')), isTrue);
      expect(isAmbiguousInviteError(Exception('socket')), isTrue);
    });
  });

  group('IAS-B 대상 지원서 확인', () {
    Future<InviteSaveCheck> check(_Reader r, {String? slotId = kSlot}) {
      InviteSaveVerifier.debugReader = r.call;
      return InviteSaveVerifier.check(
          businessId: kBiz, toId: kTo, targetUid: kWorker, slotId: slotId);
    }

    test('IAS-03 INVITED + invitedAt + 같은 슬롯 → saved, 조회 조건은 대상 한 명', () async {
      final r = _Reader([
        [_invitedRow()]
      ]);
      expect(await check(r), InviteSaveCheck.saved);
      expect(r.calls.single, {
        'businessId': kBiz,
        'toId': kTo,
        'uid': kWorker,
        'purpose': 'applicantReview',
        'limit': 20,
      });
    });

    test('IAS-04 다른 슬롯의 초대·초대 아닌 지원서는 이 저장의 증거가 아니다', () async {
      expect(
          await check(_Reader([
            [_invitedRow(slotId: 'other')]
          ])),
          InviteSaveCheck.notSaved);
      expect(
          await check(_Reader([
            [
              {'uid': kWorker, 'toId': kTo, 'slotId': kSlot, 'status': 'PENDING'}
            ]
          ])),
          InviteSaveCheck.notSaved);
      expect(await check(_Reader([<Map<String, dynamic>>[]])),
          InviteSaveCheck.notSaved);
    });

    test('IAS-05 조회 실패는 unknown — 0건이나 저장 실패로 접지 않는다', () async {
      expect(await check(_Reader([_ffe('unavailable')])), InviteSaveCheck.unknown);
    });

    test('IAS-06 unconfirmed 닫힘 → saved 일 때만 전파, unknown 은 전파 없이 읽기만', () async {
      const t = InviteVerifyTarget(toId: kTo, targetUid: kWorker, slotId: kSlot);
      final o = inviteDialogOutcome(const InviteDialogResult.unconfirmed(t));

      InviteSaveVerifier.debugReader = _Reader([
        [_invitedRow()]
      ]).call;
      var r = await InviteSaveVerifier.resolve(o, businessId: kBiz);
      expect(r.check, InviteSaveCheck.saved);
      expect(r.outcome, const InviteRefreshOutcome(propagate: true, reload: true));

      InviteSaveVerifier.debugReader = _Reader([_ffe('unavailable')]).call;
      r = await InviteSaveVerifier.resolve(o, businessId: kBiz);
      expect(r.check, InviteSaveCheck.unknown);
      expect(r.outcome, const InviteRefreshOutcome(propagate: false, reload: true));

      InviteSaveVerifier.debugReader = _Reader([<Map<String, dynamic>>[]]).call;
      r = await InviteSaveVerifier.resolve(o, businessId: kBiz);
      expect(r.check, InviteSaveCheck.notSaved);
      expect(r.outcome.propagate, isFalse);
    });

    test('IAS-07 sent·canceled 는 다시 읽지 않는다', () async {
      final r = _Reader([]);
      InviteSaveVerifier.debugReader = r.call;
      for (final d in [
        const InviteDialogResult.sent(),
        const InviteDialogResult.canceled(),
        null,
      ]) {
        final res =
            await InviteSaveVerifier.resolve(inviteDialogOutcome(d), businessId: kBiz);
        expect(res.check, isNull);
      }
      expect(r.calls, isEmpty);
    });
  });

  group('IAS-C 직접 초대 창', () {
    late List<Map<String, dynamic>> sends;
    late List<Object?> sendResults; // null = 성공, 그 외 = throw
    late _Reader reader;
    InviteDialogResult? popped;
    var poppedCalled = false;

    Future<void> openDialog(WidgetTester tester,
        {Size size = const Size(390, 844), double textScale = 1.0}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      sends = [];
      popped = null;
      poppedCalled = false;
      InviteWorkerDialog.debugFindUser = (_) async =>
          {'uid': kWorker, 'name': '김근로', 'phone': '01012345678'};
      InviteWorkerDialog.debugSendInvite = (p) async {
        sends.add(p);
        final r = sendResults.isEmpty ? null : sendResults.removeAt(0);
        if (r != null) throw r;
      };
      InviteSaveVerifier.debugReader = reader.call;
      await tester.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => _Admin(),
        child: MaterialApp(
          navigatorKey: navigatorKey,
          builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    popped = await showDialog<InviteDialogResult>(
                      context: ctx,
                      barrierDismissible: false,
                      builder: (_) => InviteWorkerDialog.contextual(
                        toId: kTo,
                        businessId: kBiz,
                        businessName: '테스트 사업장',
                        date: DateTime(2026, 10, 20),
                        slotId: kSlot,
                        workType: '피킹',
                        startTime: '09:00',
                        endTime: '18:00',
                      ),
                    );
                    poppedCalled = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '01012345678');
      await tester.tap(find.text('검색'));
      await tester.pumpAndSettle();
      expect(find.text('김근로'), findsOneWidget);
    }

    Finder sendBtn() => find.widgetWithText(ElevatedButton, '근무 제안');
    Finder recheckBtn() => find.widgetWithText(ElevatedButton, '다시 확인');

    Future<void> drainToasts(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    }

    testWidgets('IAS-08 성공 — sent 로 닫히고 다시 읽지 않는다', (tester) async {
      sendResults = [null];
      reader = _Reader([]);
      await openDialog(tester);
      await tester.tap(sendBtn());
      await tester.pumpAndSettle();
      expect(poppedCalled, isTrue);
      expect(popped?.status, InviteDialogStatus.sent);
      expect(sends.length, 1);
      expect(sends.single['slotId'], kSlot);
      expect(reader.calls, isEmpty);
      await drainToasts(tester);
    });

    testWidgets('IAS-09 명시적 취소 — canceled, 요청 0', (tester) async {
      sendResults = [];
      reader = _Reader([]);
      await openDialog(tester);
      await tester.tap(find.widgetWithText(OutlinedButton, '취소'));
      await tester.pumpAndSettle();
      expect(popped?.status, InviteDialogStatus.canceled);
      expect(sends, isEmpty);
    });

    testWidgets('IAS-10 명확한 실패 뒤 닫기 — canceled(쓰기 없음), 확인 읽기 0', (tester) async {
      sendResults = [_ffe('failed-precondition')];
      reader = _Reader([]);
      await openDialog(tester);
      await tester.tap(sendBtn());
      await tester.pumpAndSettle();
      expect(poppedCalled, isFalse, reason: '실패하면 창은 남는다');
      expect(reader.calls, isEmpty);
      await tester.tap(find.widgetWithText(OutlinedButton, '취소'));
      await tester.pumpAndSettle();
      expect(popped?.status, InviteDialogStatus.canceled);
      await drainToasts(tester);
    });

    testWidgets('IAS-11 타임아웃 후 실제 저장 — 다시 읽어 확인하고 sent', (tester) async {
      sendResults = [_ffe('deadline-exceeded')];
      reader = _Reader([
        [_invitedRow()]
      ]);
      await openDialog(tester);
      await tester.tap(sendBtn());
      await tester.pumpAndSettle();
      expect(popped?.status, InviteDialogStatus.sent);
      expect(sends.length, 1, reason: '재발송 없이 확인만 했다');
      expect(reader.calls.single['uid'], kWorker);
      expect(find.text('응답이 늦었지만 초대가 저장된 것을 확인했어요.'), findsOneWidget);
      await drainToasts(tester);
    });

    testWidgets('IAS-12 타임아웃 + 재조회 실패 — 창 유지, 발송 대신 `다시 확인`, 대상 잠금',
        (tester) async {
      sendResults = [_ffe('unavailable')];
      reader = _Reader([
        _ffe('unavailable'),
        [_invitedRow()]
      ]);
      await openDialog(tester);
      await tester.tap(sendBtn());
      await tester.pumpAndSettle();
      expect(poppedCalled, isFalse);
      expect(find.textContaining('초대 저장 여부를 아직 확인하지 못했어요.'), findsOneWidget);
      expect(sendBtn(), findsNothing, reason: '모르는 채로 재발송을 권하지 않는다');
      expect(recheckBtn(), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse,
          reason: '확인할 대상이 바뀌지 않게 한다');
      expect(find.widgetWithText(OutlinedButton, '닫기'), findsOneWidget);

      await tester.tap(recheckBtn());
      await tester.pumpAndSettle();
      expect(popped?.status, InviteDialogStatus.sent);
      expect(sends.length, 1, reason: '`다시 확인`은 읽기만 한다');
      expect(reader.calls.length, 2);
      await drainToasts(tester);
    });

    testWidgets('IAS-13 재조회 실패 상태에서 닫으면 canceled 가 아니라 unconfirmed', (tester) async {
      sendResults = [_ffe('internal')];
      reader = _Reader([_ffe('unavailable')]);
      await openDialog(tester);
      await tester.tap(sendBtn());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '닫기'));
      await tester.pumpAndSettle();
      expect(popped?.status, InviteDialogStatus.unconfirmed);
      expect(popped?.verify,
          const InviteVerifyTarget(toId: kTo, targetUid: kWorker, slotId: kSlot));
      await drainToasts(tester);
    });

    testWidgets('IAS-14 미저장 확인 뒤 재시도 → already-exists 는 실패가 아니라 확인 대상',
        (tester) async {
      // 1회차: 타임아웃 → 읽어 보니 아직 없음(notSaved) → 창 유지, 재발송 허용
      // 2회차: 서버가 이미 커밋해 둔 상태 → already-exists → 다시 읽어 saved
      sendResults = [_ffe('deadline-exceeded'), _ffe('already-exists')];
      reader = _Reader([
        <Map<String, dynamic>>[],
        [_invitedRow()]
      ]);
      await openDialog(tester);
      await tester.tap(sendBtn());
      await tester.pumpAndSettle();
      expect(poppedCalled, isFalse);
      expect(find.textContaining('앞선 초대는 저장되지 않은 것으로 확인됐어요.'), findsOneWidget);
      expect(sendBtn(), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));

      await tester.tap(sendBtn());
      await tester.pumpAndSettle();
      expect(popped?.status, InviteDialogStatus.sent);
      expect(sends.length, 2);
      expect(reader.calls.length, 2);
      await drainToasts(tester);
    });

    testWidgets('IAS-15 미저장 확인 뒤 그냥 닫아도 unconfirmed — 늦은 커밋을 호출자가 다시 확인',
        (tester) async {
      sendResults = [_ffe('deadline-exceeded')];
      reader = _Reader([<Map<String, dynamic>>[]]);
      await openDialog(tester);
      await tester.tap(sendBtn());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(OutlinedButton, '닫기'));
      await tester.pumpAndSettle();
      expect(popped?.status, InviteDialogStatus.unconfirmed);
      await drainToasts(tester);
    });

    testWidgets('IAS-16 확인 중에는 버튼이 눌리지 않고 진행 표시가 보인다', (tester) async {
      sendResults = [_ffe('deadline-exceeded')];
      final gate = Completer<List<Map<String, dynamic>>>();
      reader = _Reader([]);
      await openDialog(tester);
      InviteSaveVerifier.debugReader = (p) {
        reader.calls.add(p);
        return gate.future;
      };
      await tester.tap(sendBtn());
      await tester.pump();
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final close = tester.widget<OutlinedButton>(
          find.ancestor(of: findVisibleText('닫기'), matching: find.byType(OutlinedButton)));
      expect(close.onPressed, isNull, reason: '확인 중에 닫으면 결과가 사라진다');
      gate.complete([_invitedRow()]);
      await tester.pumpAndSettle();
      expect(popped?.status, InviteDialogStatus.sent);
      await drainToasts(tester);
    });

    for (final w in [360.0, 320.0]) {
      testWidgets('IAS-17 좁은 화면 ${w.toInt()}dp · 글자 1.3배 — 안내 배너가 넘치지 않는다',
          (tester) async {
        sendResults = [_ffe('unavailable')];
        reader = _Reader([_ffe('unavailable')]);
        await openDialog(tester, size: Size(w, 700), textScale: 1.3);
        await tester.tap(sendBtn());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(recheckBtn(), findsOneWidget);
        await drainToasts(tester);
      });
    }
  });

  group('IAS-D 가능일 시트', () {
    late _FakeSvc svc;
    late _Reader reader;
    late int succeeded;

    Future<void> openSheet(WidgetTester tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      succeeded = 0;
      InviteSaveVerifier.debugReader = reader.call;
      await tester.pumpWidget(MaterialApp(
        navigatorKey: navigatorKey,
        home: Scaffold(
          body: AvailableWorkersBottomSheet(
            toId: kTo,
            slotId: kSlot,
            businessId: kBiz,
            date: DateTime(2026, 10, 20),
            workType: '피킹',
            startTime: '09:00',
            endTime: '18:00',
            requiredCount: 2,
            confirmedCount: 0,
            onInviteSucceeded: () => succeeded++,
            service: svc,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('김*로'), findsOneWidget);
    }

    Future<void> propose(WidgetTester tester) async {
      await tester.tap(find.widgetWithText(OutlinedButton, '근무 제안'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('제안 보내기'));
      await tester.pumpAndSettle();
    }

    testWidgets('IAS-18 타임아웃 후 실제 저장 — `제안 보냄` + 성공 콜백 1회', (tester) async {
      svc = _FakeSvc([_ffe('deadline-exceeded')]);
      reader = _Reader([
        [_invitedRow()]
      ]);
      await openSheet(tester);
      await propose(tester);
      expect(find.text('제안 보냄'), findsOneWidget);
      expect(succeeded, 1);
      expect(svc.invites, 1);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('IAS-19 타임아웃 + 재조회 실패 — 실패로 단정하지 않고 `다시 확인`만, 콜백 0',
        (tester) async {
      svc = _FakeSvc([_ffe('unavailable')]);
      reader = _Reader([
        _ffe('unavailable'),
        [_invitedRow()]
      ]);
      await openSheet(tester);
      await propose(tester);
      expect(find.text('제안 전송에 실패했습니다. 다시 시도해주세요.'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, '근무 제안'), findsNothing,
          reason: '모르는 채로 재발송 버튼을 두지 않는다');
      expect(find.widgetWithText(OutlinedButton, '다시 확인'), findsOneWidget);
      expect(succeeded, 0);
      await tester.pump(const Duration(seconds: 5));

      await tester.tap(find.widgetWithText(OutlinedButton, '다시 확인'));
      await tester.pumpAndSettle();
      expect(find.text('제안 보냄'), findsOneWidget);
      expect(succeeded, 1);
      expect(svc.invites, 1, reason: '`다시 확인`은 읽기만 한다');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('IAS-20 명확한 실패는 기존 문구 그대로, 확인 읽기 0', (tester) async {
      svc = _FakeSvc([_ffe('failed-precondition')]);
      reader = _Reader([]);
      await openSheet(tester);
      await propose(tester);
      expect(find.text('제안 전송에 실패했습니다. 다시 시도해주세요.'), findsOneWidget);
      expect(reader.calls, isEmpty);
      expect(find.widgetWithText(OutlinedButton, '근무 제안'), findsOneWidget);
      expect(succeeded, 0);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('IAS-21 미저장 확인 뒤 재발송 already-exists → 다시 읽어 저장 확인', (tester) async {
      svc = _FakeSvc([_ffe('deadline-exceeded'), _ffe('already-exists')]);
      reader = _Reader([
        <Map<String, dynamic>>[],
        [_invitedRow()]
      ]);
      await openSheet(tester);
      await propose(tester);
      expect(find.widgetWithText(OutlinedButton, '근무 제안'), findsOneWidget);
      expect(succeeded, 0);
      await tester.pump(const Duration(seconds: 5));
      await propose(tester);
      expect(find.text('제안 보냄'), findsOneWidget);
      expect(find.text('이미 지원하거나 초대된 근로자입니다.'), findsNothing);
      expect(succeeded, 1);
      await tester.pump(const Duration(seconds: 5));
    });
  });
}

class _FakeSvc implements AvailableWorkersService {
  _FakeSvc(this.inviteResults);
  final List<Object?> inviteResults;
  int invites = 0;

  @override
  Future<AvailableWorkersResult> getAvailableWorkers({
    required String toId,
    required String slotId,
    String? workDetailId,
    int pageSize = 20,
    String? cursor,
  }) async =>
      AvailableWorkersResult(
        candidates: const [
          AvailableWorkerModel(uid: kWorker, maskedName: '김*로', city: '서울'),
        ],
        hasMore: false,
        nextCursor: null,
        poolComplete: true,
        weeklyContextAvailable: false,
      );

  @override
  Future<String> inviteWorker({
    required String toId,
    required String businessId,
    required String targetUid,
    required DateTime workDate,
    String? slotId,
    String? selectedWorkType,
    String? workDetailStartTime,
    String? workDetailEndTime,
  }) async {
    invites++;
    final r = inviteResults.isEmpty ? null : inviteResults.removeAt(0);
    if (r != null) throw r;
    return 'app1';
  }
}
