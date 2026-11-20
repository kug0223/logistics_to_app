// [PILOT-INVITE-FENCE-UI] 시범 일반 제안 차단이 "전송 실패 — 다시 시도"로 보였다
//
// 시범 펜스 후보(callableInviteWorker cand-invite)는 차단 시
//   FirebaseFunctionsException(code: 'failed-precondition',
//     message: '시범 운영 기간에는 새 근무 제안을 보낼 수 없습니다.',
//     details: {'reason': 'PILOT_INVITE_CREATE_BLOCKED'})
// 를 앱에 준다(cloud_functions 플러그인이 서버 details 를 그대로 `details` 로 넘긴다).
// '근무 가능 인력' 시트는 오류 문자열에 정원·이미·권한 단어가 있는지만 보고 문구를 골라,
// 이 차단을 "제안 전송에 실패했습니다. 다시 시도해주세요."로 보였다 — 다시 눌러도 같은 결과다.
//
// 고치는 범위: **그 reason 하나만** 재시도 없는 안내로 바꾼다.
//   일반 failed-precondition 전체를 차단으로 보지 않는다.
//
//   PIF-1  reason=PILOT_INVITE_CREATE_BLOCKED → 시범 안내(재시도 문구 없음), 확인 읽기 0, 콜백 0
//   PIF-2  같은 code·다른 reason / reason 없음 → 기존 일반 문구 그대로
//   PIF-3  권한 없음 · 정원 초과 · 이미 제안함 → 기존 문구 그대로
//   PIF-4  연결 끊김(unavailable) → 기존 확인 경로(재조회) 그대로, 시범 안내 없음
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:ALfit/models/core/available_worker_model.dart';
import 'package:ALfit/screens/business_admin/dialogs/available_workers_bottom_sheet.dart';
import 'package:ALfit/services/available_workers_service.dart';
import 'package:ALfit/services/invite_save_verifier.dart';
import 'package:ALfit/utils/navigation_key.dart';

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
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

const _generic = '제안 전송에 실패했습니다. 다시 시도해주세요.';
const _pilot = '시범 운영 기간에는 새 근무 제안을 보낼 수 없습니다.';

/// 플러그인이 넘기는 모양: details 는 Map(플랫폼 채널을 지나 키가 Object? 일 수 있다).
FirebaseFunctionsException _fx(String code, String message, [Object? details]) =>
    FirebaseFunctionsException(code: code, message: message, details: details);

class _Reader {
  final calls = <Map<String, dynamic>>[];
  Future<List<Map<String, dynamic>>> call(Map<String, dynamic> p) async {
    calls.add(p);
    return const [];
  }
}

class _FakeSvc implements AvailableWorkersService {
  _FakeSvc(this.error);
  final Object error;
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
        candidates: const [AvailableWorkerModel(uid: 'w1', maskedName: '김*로', city: '서울')],
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
    throw error;
  }
}

void main() {
  setUpAll(() => FirebasePlatform.instance = _FakeCore());
  tearDown(() => InviteSaveVerifier.debugReader = null);

  late _Reader reader;
  late int succeeded;

  /// 제안 → 확인 → 진행 중 한 번이라도 보인 문구를 모은다(토스트는 몇 초 뒤 사라진다).
  Future<Set<String>> proposeWith(WidgetTester tester, _FakeSvc svc, List<String> watch) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    succeeded = 0;
    reader = _Reader();
    InviteSaveVerifier.debugReader = reader.call;
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        body: AvailableWorkersBottomSheet(
          toId: 'to1', slotId: 'slot1', businessId: 'biz1', date: DateTime(2026, 10, 20),
          workType: '피킹', startTime: '09:00', endTime: '18:00', requiredCount: 2, confirmedCount: 0,
          onInviteSucceeded: () => succeeded++, service: svc,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '근무 제안'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('제안 보내기'));
    final seen = <String>{};
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      for (final w in watch) {
        if (find.text(w).evaluate().isNotEmpty) seen.add(w);
      }
    }
    await tester.pump(const Duration(seconds: 5)); // 토스트 타이머 소진
    return seen;
  }

  const allMsgs = [
    _pilot, _generic, '초대 권한이 없습니다.', '정원이 초과되어 제안을 보낼 수 없습니다.', '이미 지원하거나 초대된 근로자입니다.',
  ];

  testWidgets('PIF-1 시범 차단 reason → 재시도 없는 시범 안내', (tester) async {
    final svc = _FakeSvc(_fx('failed-precondition', _pilot, <Object?, Object?>{'reason': 'PILOT_INVITE_CREATE_BLOCKED'}));
    final seen = await proposeWith(tester, svc, allMsgs);
    expect(seen, {_pilot}, reason: '일반 실패·재시도 문구 없이 시범 안내만');
    expect(reader.calls, isEmpty, reason: '명확한 거절 — 저장 확인 읽기 없음');
    expect(succeeded, 0);
    expect(svc.invites, 1);
  });

  // PIF-2 — 같은 failed-precondition 이라도 reason 이 다르거나 없으면 기존 문구
  final pif2 = <String, FirebaseFunctionsException>{
    '다른 reason': _fx('failed-precondition', '마감된 공고에는 초대를 보낼 수 없습니다.', <Object?, Object?>{'reason': 'SOMETHING_ELSE'}),
    'reason 없음': _fx('failed-precondition', '이 근로자가 해당 날짜의 근무 가능일을 등록하지 않았습니다.'),
  };
  for (final c in pif2.entries) {
    testWidgets('PIF-2 ${c.key} → 기존 일반 문구', (tester) async {
      final seen = await proposeWith(tester, _FakeSvc(c.value), allMsgs);
      expect(seen, {_generic});
    });
  }

  // PIF-3 — 권한 없음 · 정원 초과 · 이미 제안함 → 기존 문구 그대로
  final pif3 = <String, (FirebaseFunctionsException, String)>{
    '권한 없음': (_fx('permission-denied', 'TO 관리 권한이 없습니다.'), '초대 권한이 없습니다.'),
    '정원 초과': (_fx('failed-precondition', '정원이 찬 업무에는 초대를 보낼 수 없습니다.'), '정원이 초과되어 제안을 보낼 수 없습니다.'),
    '이미 제안함': (_fx('already-exists', '이미 이 공고에 초대가 발송된 근로자입니다.'), '이미 지원하거나 초대된 근로자입니다.'),
  };
  for (final c in pif3.entries) {
    testWidgets('PIF-3 ${c.key} → 기존 문구', (tester) async {
      final seen = await proposeWith(tester, _FakeSvc(c.value.$1), allMsgs);
      expect(seen, {c.value.$2});
    });
  }

  testWidgets('PIF-4 연결 끊김 → 기존 저장 확인 경로, 시범 안내 없음', (tester) async {
    final seen = await proposeWith(tester, _FakeSvc(_fx('unavailable', 'UNAVAILABLE')), allMsgs);
    expect(seen.contains(_pilot), isFalse);
    expect(reader.calls, isNotEmpty, reason: '불명확 → 다시 읽어 확인한다(기존 동작)');
  });
}
