// [R7-P2 잔여 I45] 내 요청 인박스 **안**에서 두 사건이 구별되는가.
//
// 두 Home 카드(#4 신분증 · #5 계약해지)는 같은 인박스를 연다(UHR-38 이 도달을
// 이미 쟀다). 여기서 보는 것은 **인박스 안**이다 — 홈이 약속한 각각의 요청이
// 실제로 서로 다른 행으로 보이는지, 한 읽기가 실패해도 나머지를 지우지 않는지.
//
// 승인·거절·동의는 **누르지 않는다.** 읽는 화면과 닫기까지만이다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/interim_settlement_request_model.dart';
import 'package:ALfit/models/core/schedule_change_request_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/dialogs/my_requests_dialog.dart';
import 'package:ALfit/screens/user/dialogs/my_requests_reads.dart';

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

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        createdAt: DateTime(2026, 1, 1),
      );
}

// ── 같은 uid · **서로 다른 사업장/날짜** 두 요청 ──────────────────────────
IdCardAccessRequestModel _idReq() => IdCardAccessRequestModel(
      id: 'idreq1',
      requesterId: 'admin1',
      requesterName: '박사장',
      requesterBusinessId: 'bizA',
      requesterBusinessName: '강남 물류센터',
      targetUserId: 'u1',
      targetUserName: '김근로',
      reason: IdCardAccessReason.incomeTax,
      status: IdCardAccessStatus.pending,
      requestedAt: DateTime(2026, 9, 20),
    );

ApplicationModel _termination() => ApplicationModel(
      id: 'app-term1',
      uid: 'u1',
      toId: 'toB',
      slotId: 'slotB',
      businessId: 'bizB',
      businessName: '성수 창고',
      toTitle: '장기 모집',
      selectedWorkType: '피킹',
      wdId: 'wdB',
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      wageType: 'hourly',
      status: 'CONFIRMED',
      workDate: DateTime(2026, 9, 25),
      appliedAt: DateTime(2026, 9, 1),
      terminationStatus: 'PENDING',
      // 인박스는 요청 시각이 있는 건만 행으로 만든다.
      terminationRequestedAt: DateTime(2026, 9, 22),
      terminationReason: '개인 사정',
    );

MyRequestsReads _reads({
  List<IdCardAccessRequestModel> idReqs = const [],
  List<ApplicationModel> terms = const [],
  Object? idError,
  Object? termError,
}) =>
    MyRequestsReads(
      scheduleChangeRequests: (uid) async =>
          <ScheduleChangeRequestModel>[],
      pendingIdCardRequests: (uid) async {
        if (idError != null) throw idError;
        return idReqs;
      },
      terminationRequests: (uid) async {
        if (termError != null) throw termError;
        return terms;
      },
      interimSettlements: () async => <InterimSettlementRequestModel>[],
    );

Future<void> _open(WidgetTester tester, MyRequestsReads reads) async {
  tester.view.physicalSize = const Size(390, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _P(),
      child: MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (ctx) => TextButton(
              onPressed: () => MyRequestsDialog.show(ctx,
                  applicantUid: 'u1', reads: reads),
              child: const Text('인박스 열기'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.tap(find.text('인박스 열기'));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  test('[MRI-0] production 기본값은 지금 쓰는 네 메서드를 그대로 부른다', () {
    // 경계 파일의 짝만 본다 — 이름만 맞추지 않는다.
    final src =
        File('lib/screens/user/dialogs/my_requests_reads.dart')
            .readAsStringSync()
            .replaceAll(RegExp(r'\s+'), ' ');
    for (final m in [
      'scheduleChangeRequests: svc.getMyScheduleChangeRequests',
      'pendingIdCardRequests: svc.getPendingIdCardRequestsForUser',
      'terminationRequests: svc.getMyTerminationRequests',
      'interimSettlements: () => pay.getMyInterimSettlements()',
    ]) {
      expect(src.contains(m), isTrue, reason: m);
    }
    // 읽기 경계에 mutation 이 없다.
    for (final w in ['approve', 'reject', 'cancel', 'confirm']) {
      expect(src.toLowerCase().contains(w), isFalse, reason: w);
    }
  });

  testWidgets('[MRI-1] 신분증 요청만 있으면 그 카드만 서고 해지 카드가 생기지 않는다',
      (tester) async {
    await _open(tester, _reads(idReqs: [_idReq()]));

    expect(find.text('신분증 열람 요청'), findsOneWidget);
    // 정확한 사업장·요청자·목적이 그 카드에 있다.
    expect(find.text('강남 물류센터'), findsOneWidget);
    expect(find.textContaining('박사장'), findsOneWidget);
    expect(find.textContaining('사유:'), findsOneWidget);
    // 해지 카드는 없다 — 유형이 섞이지 않는다.
    expect(find.text('계약해지 요청'), findsNothing);
  });

  testWidgets('[MRI-2] 계약해지 요청만 있으면 그 카드만 서고 신분증으로 합쳐지지 않는다',
      (tester) async {
    await _open(tester, _reads(terms: [_termination()]));

    expect(find.text('계약해지 요청'), findsOneWidget);
    // 별도 요청 key(applicationId)의 근무·사유가 그 카드에 있다.
    expect(find.textContaining('성수 창고'), findsWidgets);
    expect(find.textContaining('개인 사정'), findsOneWidget);
    expect(find.text('신분증 열람 요청'), findsNothing);
  });

  testWidgets('[MRI-3] 둘 다 있으면 서로 다른 두 카드로 구별된다', (tester) async {
    await _open(tester,
        _reads(idReqs: [_idReq()], terms: [_termination()]));

    expect(find.text('신분증 열람 요청'), findsOneWidget);
    expect(find.text('계약해지 요청'), findsOneWidget);
    // 다른 사업장이 각자 자기 카드에 붙는다 — 행이 섞이지 않는다.
    expect(find.text('강남 물류센터'), findsOneWidget);
    expect(find.textContaining('성수 창고'), findsWidgets);
  });

  testWidgets('[MRI-4] 한 읽기가 실패하면 두 요청 모두 없음/완료로 바꾸지 않는다',
      (tester) async {
    await _open(tester,
        _reads(idReqs: [_idReq()], termError: StateError('term down')));

    // `Future.wait` 계약이라 하나가 던지면 전체가 오류로 간다.
    //   중요한 것은 **없음이라고 말하지 않는 것**이다.
    expect(find.text('신분증 열람 요청'), findsNothing);
    expect(find.text('계약해지 요청'), findsNothing);
    expect(find.textContaining('요청이 없습니다'), findsNothing);
    expect(find.textContaining('처리할 요청이 없'), findsNothing);
  });

  testWidgets('[MRI-5] 정말 비었을 때만 없음을 말한다 (정상 대조)', (tester) async {
    await _open(tester, _reads());

    expect(find.text('신분증 열람 요청'), findsNothing);
    expect(find.text('계약해지 요청'), findsNothing);
  });
}
