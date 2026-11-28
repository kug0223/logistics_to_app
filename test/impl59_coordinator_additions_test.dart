// ignore_for_file: depend_on_referenced_packages
// [impl_59 · 조정자 지시] 추가 셀.
//   2. 거절 코드 — **실제 플러그인 변환 경로**(pigeon 오류 envelope → PlatformException → FirebaseFunctionsException)에서
//      details.code 판정이 맞는가. 근거: cloud_functions_platform_interface 5.8.2
//      lib/src/method_channel/utils/exception.dart `platformExceptionToFirebaseFunctionsException`
//        code = details['code'] ?? 'unknown' · message = details['message'] ?? message · details = details['additionalData']
//      (Android FlutterFirebaseFunctionsPlugin.getExceptionDetails: details = {code(소문자-하이픈), message, additionalData(서버 HttpsError details)}).
//   3. 업무별 마감 창 — 리스트 모드 공고 카드 메뉴에서 열린다(슬롯 1개일 때만 · canManageTo).
//   4. 빈자리 다시 모집 실패 안내 — 보여도 되는 서버 사유는 그대로 · 개발 문장·결과 모름은 기본 안내.
import 'dart:io';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/slot_model.dart' show SlotModel, SlotStatus;
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/to_list_dialogs.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/utils/request_relation_error.dart';
import 'package:ALfit/utils/server_reject_codes.dart';
import 'package:ALfit/widgets/admin/cards/admin_to_group_card.dart';

import 'support/visible_text.dart'; // 메뉴 글은 줄바꿈 연결 문자(U+2060)를 넣어 그린다

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

const _channel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// 가짜 서버가 돌려줄 pigeon 오류 응답 [code, message, details] 로 callable 을 한 번 부르고 앱이 받는 예외를 돌려준다.
Future<Object> _callWith(List<Object?> envelope) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMessageHandler(_channel, (_) async => const StandardMessageCodec().encodeMessage(envelope));
  try {
    await FirebaseFunctions.instanceFor(region: 'asia-northeast3').httpsCallable('callableX').call(<String, Object?>{});
  } catch (e) {
    return e;
  }
  fail('예외가 나와야 한다');
}

/// 실제 꼴 — Android 플러그인이 만드는 details: code(HttpsError) · message · additionalData(서버 details).
List<Object?> _real(String httpCode, String message, [Map<String, Object?>? additional]) => <Object?>[
      httpCode, message, <String, Object?>{'code': httpCode, 'message': message, if (additional != null) 'additionalData': additional}];

String _src(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

// ── 3. 공고 카드 fixture ──
const _wd = WorkDetailData(wdId: 'wd1', workType: '상하차', startTime: '09:00', endTime: '18:00', requiredCount: 2, wage: 12000, wageType: 'hourly');
TOModel _to({String type = TOType.flex}) => TOModel(
    id: 'TO1', businessId: 'BIZ', businessName: '강남 물류센터', type: type, title: '물류 단기', creatorUID: 'OWNER',
    status: 'ACTIVE', workDetails: const [_wd], totalRequired: 2, totalConfirmed: 0, totalPending: 0,
    isPublished: true, publishMode: 'immediate', createdAt: DateTime(2026, 11, 20), totalSlots: 1);
TOItem _slotItem(TOModel to, String id, DateTime d) => TOItem(
    to: to,
    slot: SlotModel(id: id, toId: to.id, date: d, status: SlotStatus.open, workDetails: const [_wd], createdAt: DateTime(2026, 11, 20)),
    workDetails: const [_wd], confirmedCount: 0, pendingCount: 0, totalRequired: 2,
    workDetailStats: const {'wd1': {'confirmed': 0, 'pending': 0}}, isWorkDetailLoaded: true, workDetailStatsFailed: false);

class _P extends UserProvider {
  _P(this.allowed);
  final bool allowed;
  @override
  UserModel? get currentUser => UserModel(uid: 'OWNER', username: 'owner', name: '관리자', email: 'o@test.local',
      role: allowed ? UserRole.BUSINESS_ADMIN : UserRole.USER);
  @override
  bool can(bool Function(MemberPermissions p) check) => allowed;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => allowed;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      allowed ? PermissionCheck.allowed : PermissionCheck.denied;
}

Future<void> _pumpCard(WidgetTester t, TOGroupItem group, {bool allowed = true}) async {
  t.view.physicalSize = const Size(411, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final svc = FirestoreService();
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _P(allowed),
    child: MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: Builder(builder: (ctx) => TOGroupCard(
                groupItem: group,
                firestoreService: svc,
                onRetryWorkDetailStats: (_) async {},
                onRetryGroupWorkDetailStats: (_) async {},
                dialogs: TOListDialogs(context: ctx, firestoreService: svc, onChanged: () {}),
                onChanged: () {},
                isExpanded: false,
                expandedTOs: const <String>{},
                onToggleExpand: () {},
                onToggleTOExpand: (_) {},
              )),
        ),
      ),
    ),
  ));
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _openMenu(WidgetTester t) async {
  await t.tap(find.byTooltip('메뉴').first);
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(_channel, null));

  group('2 거절 코드 — 실제 플러그인 변환 경로', () {
    test('실제 꼴: code = HttpsError 코드 · details = 서버 details → 화면 판정이 details.code 로 맞다', () async {
      final e1 = await _callWith(_real('failed-precondition', '요청 정보가 맞지 않습니다.', {'code': 'SCR_RELATION_MISMATCH', 'reason': 'BUSINESS'}));
      expect(e1, isA<FirebaseFunctionsException>());
      final f1 = e1 as FirebaseFunctionsException;
      expect((f1.code, (f1.details as Map)['code']), ('failed-precondition', 'SCR_RELATION_MISMATCH'));
      expect(serverRejectCodeOf(f1), 'SCR_RELATION_MISMATCH');
      expect(requestHeldMessageOf(f1), requestRelationHeldMessage);

      final e2 = await _callWith(_real('failed-precondition', '겹침 확인 실패', {'code': 'OVERLAP_CHECK_INCOMPLETE'})) as FirebaseFunctionsException;
      expect(overlapCheckIncompleteMessageOf(e2), overlapCheckIncompleteMessage);
      final e3 = await _callWith(_real('permission-denied', '맞지 않습니다', {'code': 'APPLICATION_MISMATCH'})) as FirebaseFunctionsException;
      expect(idCardRequestRejectMessageOf(e3), applicationMismatchMessage);
      final e4 = await _callWith(_real('invalid-argument', '정원', {'code': 'REQUIRED_COUNT_INVALID'})) as FirebaseFunctionsException;
      expect(postingInputRejectMessageOf(e4), requiredCountInvalidMessage);
      final e5 = await _callWith(_real('failed-precondition', '계약 확인 실패', {'code': 'CONTRACT_SCAN_TRUNCATED'})) as FirebaseFunctionsException;
      expect(contractScanTruncatedMessageOf(e5), contractScanTruncatedMessage);
      // 확정 취소 결과 — 서버 details 가 없으면 HttpsError code(예: not-found)로 고른다
      final e6 = await _callWith(_real('not-found', '지원서를 찾을 수 없습니다.')) as FirebaseFunctionsException;
      expect((e6.code, e6.details), ('not-found', null));
      expect(ConfirmCancelResult.fromError(e6).message, confirmCancelNotFoundMessage);
      final e7 = await _callWith(_real('deadline-exceeded', 'DEADLINE_EXCEEDED')) as FirebaseFunctionsException;
      expect(ConfirmCancelResult.fromError(e7).outcomeUnknown, isTrue);
    });

    test('잘못된 꼴(가짜 함정): details 자리에 {code: X} 만 → X 가 e.code 로 오르고 details 는 null — 실제에는 없는 꼴 · 판정 함수는 받지 않는다', () async {
      final e = await _callWith(<Object?>['failed-precondition', 'x', <String, Object?>{'code': 'SCR_RELATION_MISMATCH'}]) as FirebaseFunctionsException;
      expect((e.code, e.details), ('SCR_RELATION_MISMATCH', null));
      expect(serverRejectCodeOf(e), isNull, reason: 'e.code 쪽의 X 를 거절 코드로 받지 않는다');
      expect(requestHeldMessageOf(e), isNull);
    });

    test('details 가 null 인 가짜 envelope → e.code 는 unknown(첫 칸 code 가 아니다)', () async {
      final e = await _callWith(<Object?>['unavailable', '주입 실패', null]) as FirebaseFunctionsException;
      expect(e.code, 'unknown');
      expect(e.message, '주입 실패');
    });
  });

  group('4 빈자리 다시 모집 실패 안내', () {
    test('보여도 되는 서버 사유는 그대로 · 개발 문장은 기본 안내', () {
      const reopen = '종료된 근무일입니다. 대체 인력을 충원하려면 먼저 날짜를 재오픈해주세요.';
      final ok = FirebaseFunctionsException(code: 'failed-precondition', message: reopen);
      expect(adminActionErrorMessage(ok, fallback: noshowReleaseFailedMessage), reopen);
      final dev = FirebaseFunctionsException(code: 'failed-precondition', message: 'NO_SHOW 출근 기록이 없는 지원서입니다.');
      expect(adminActionErrorMessage(dev, fallback: noshowReleaseFailedMessage), noshowReleaseFailedMessage);
    });
    test('서비스 배선 — 결과 모름 갈래 · 거절 갈래 · 공용 안내', () {
      final s = _src('lib/services/firestore/application_firestore.dart');
      final i = s.indexOf('Future<bool> releaseNoshowSeat(');
      expect(i, greaterThan(0));
      final body = s.substring(i, s.indexOf('\n  }\n', i));
      expect(body, contains("final releaseFallback = serverOutcomeUnknownCodes.contains(e.code)\n          ? '빈자리 다시 모집 처리 결과를 확인하지 못했어요'\n          : noshowReleaseFailedMessage;"));
      expect(body, contains('ToastHelper.showError(adminActionErrorMessage(e, fallback: releaseFallback));'));
      expect(body.contains('e.message ??'), isFalse);
      expect(body, contains("if (e.code == 'already-exists')"), reason: '멱등 성공 갈래 그대로');
    });
  });

  group('3 업무별 마감 — 리스트 모드 진입', () {
    testWidgets('슬롯 1개 단기 공고 · 권한 있음 → 메뉴에 있고 누르면 업무별 마감 관리 창이 열린다', (t) async {
      final to = _to();
      final group = TOGroupItem(singleTO: to)..setGroupTOs([_slotItem(to, 'S1', DateTime(2026, 12, 1))]);
      await _pumpCard(t, group);
      await _openMenu(t);
      expect(findVisibleText('업무별 마감'), findsOneWidget);
      await t.tap(findVisibleText('업무별 마감'));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(findVisibleText('업무별 마감 관리'), findsOneWidget);
    });
    testWidgets('여러 날짜(슬롯 2개) → 메뉴에 없다(날짜를 고르는 단계 없음)', (t) async {
      final to = _to();
      final group = TOGroupItem(singleTO: to)
        ..setGroupTOs([_slotItem(to, 'S1', DateTime(2026, 12, 1)), _slotItem(to, 'S2', DateTime(2026, 12, 2))]);
      await _pumpCard(t, group);
      await _openMenu(t);
      expect(findVisibleText('업무별 마감'), findsNothing);
    });
    testWidgets('슬롯 미로드 → 메뉴에 없다', (t) async {
      await _pumpCard(t, TOGroupItem(singleTO: _to()));
      await _openMenu(t);
      expect(findVisibleText('업무별 마감'), findsNothing);
    });
    testWidgets('권한 없음(canManageTo 거부) → 메뉴에 없다', (t) async {
      final to = _to();
      final group = TOGroupItem(singleTO: to)..setGroupTOs([_slotItem(to, 'S1', DateTime(2026, 12, 1))]);
      await _pumpCard(t, group, allowed: false);
      final menu = find.byTooltip('메뉴');
      if (menu.evaluate().isNotEmpty) {
        await _openMenu(t);
      }
      expect(findVisibleText('업무별 마감'), findsNothing);
    });
    test('원문 — 같은 권한 · 같은 항목 꼴 · 슬롯 기준 읽기', () {
      final c = _src('lib/widgets/admin/cards/admin_to_group_card.dart');
      expect(c, contains('if (canManageTo && _listModeWorkDetailTarget() != null)'));
      expect(c, contains("final calSlotForManage = widget.calendarSlot ??\n                (toItemForManage.slot != null ? toItemForManage : null);"));
      expect(RegExp("label: '업무별 마감'").allMatches(c).length, 2, reason: '캘린더 메뉴 1 + 리스트 메뉴 1');
    });
  });
}
