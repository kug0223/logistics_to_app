// [CONFIRM-BUSINESSID] 확정 payload 의 businessId — 두 호출부.
//
// ── 재현 (2026-10-19, LOCAL 에뮬레이터 · 배포 확정 번들 g185) ──────────
//   callableConfirmApplication 은 businessId 가 없거나 빈 값이면
//   invalid-argument("businessId가 필요합니다.")로 거절하고 원장을 바꾸지 않는다.
//   그런데 두 호출부가 보내지 않았다(설치 APK 6e23a650 도 같다):
//     · work_applicants_dialog 일괄 확정+계약 발송 processOne
//     · worker_detail_dialog 승인
//   그래서 두 경로는 한 건도 확정하지 못했다.
//
// ── 고친 것 ───────────────────────────────────────────────────────────
//   두 곳 모두 **지원서 자신의** businessId 를 보낸다(같은 창 개별 확정과 같은 값).
//   여러 사업장 관리자라도 지원서마다 제 사업장이 가므로 섞이지 않는다.
//
// 아래 가짜 서버는 LOCAL 에서 본 서버 규칙을 그대로 따른다.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_member_model.dart' show MemberPermissions;
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/services/applicant_document_review_service.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/dialogs/worker_detail_dialog.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'dart:io';

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

const _biz = 'biz1';
const _worker = 'w9';

class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'owner1', username: 'owner1', name: '관리자',
      email: 'owner1@test.local', role: UserRole.BUSINESS_ADMIN);
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      true;
  // checkForBusiness 는 오버라이드한 currentUser 가 아니라 내부 필드를 읽는다 —
  //   소유자는 언제나 allowed(실제 구현과 같은 결과)라고 대역이 직접 말한다.
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

/// 서브관리자 — 확정 권한(canManageTo) 판정을 테스트가 정한다.
///   서버 규칙: 확정·거절 = canManageTo, 서류 열람 = canManageTo + canManageWage.
///   서류 열람 자격은 서버 응답(canReviewDocuments)으로 따로 준다.
class _SubP extends UserProvider {
  _SubP(this.confirm);
  final PermissionCheck confirm;
  @override
  UserModel? get currentUser => UserModel(
      uid: 'sub1', username: 'sub1', name: '서브관리자',
      email: 'sub1@test.local', role: UserRole.USER,
      subAdminBusinessIds: const [_biz]);
  @override
  bool get isSubAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      confirm;
  @override
  bool can(bool Function(MemberPermissions p) check) =>
      confirm == PermissionCheck.allowed;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      confirm == PermissionCheck.allowed;
}

final _date = DateTime(2026, 10, 20);

ApplicationModel _pending() => ApplicationModel(
      id: 'app1',
      uid: _worker,
      toId: 'to1',
      slotId: 'slot1',
      wdId: 'wd1',
      businessId: _biz,
      businessName: '테스트 사업장',
      toTitle: '테스트 공고',
      selectedWorkType: 'QA 분류',
      startTime: '10:00',
      endTime: '11:00',
      wage: 12000,
      wageType: 'hourly',
      status: AppStatus.pending,
      workDate: _date,
      appliedAt: _date.subtract(const Duration(days: 1)),
    );

Map<String, dynamic> _map({
  bool canReview = true,
  String? consentBlock,
  bool matchingReady = false,
  String state = 'ID_UNASSESSED',
  String idDecision = 'NOT_REVIEWED',
  bool idStale = false,
  String bankDecision = 'NOT_REVIEWED',
}) =>
    {
      'workerUid': _worker,
      'canReviewDocuments': canReview,
      'consentBlock': consentBlock,
      'versions': {'id': 2, 'bankbook': 1, 'account': 1},
      'readiness': {
        'ready': false,
        'idDecision': idDecision,
        'bankDecision': bankDecision,
        'idStale': idStale,
      },
      'documents': {'hasIdCard': true, 'hasBankbook': true},
      if (canReview)
        'bank': {
          'bankName': 'QA테스트은행',
          'accountNumber': '0000000000',
          'accountHolder': '큐에이일',
        },
      'matchingReadiness': {
        'ready': matchingReady,
        'state': matchingReady ? state : state,
        'reason': matchingReady
            ? null
            : '신분증 확인이 필요합니다. 지원자 상세에서 확인해주세요.',
      },
    };

/// 응답을 순서대로 준다. Completer 면 그것을 기다린다(조회 중), Exception 이면 던진다.
class _FakeReview extends Fake implements ApplicantDocumentReviewService {
  _FakeReview(this.responses);
  final List<Object> responses;
  int loads = 0;
  @override
  Future<ApplicantDocumentReview> load({
    required String applicationId,
    required String businessId,
  }) async {
    loads++;
    final r = responses.length > 1 ? responses.removeAt(0) : responses.first;
    if (r is Completer<Map<String, dynamic>>) {
      return ApplicantDocumentReview.fromMap(await r.future);
    }
    if (r is Exception) throw r;
    return ApplicantDocumentReview.fromMap(r as Map<String, dynamic>);
  }
}

final _errors = <String>[];

Future<void> _open(WidgetTester t,
    {double width = 411,
    double height = 860,
    double scale = 1.0,
    UserProvider Function()? provider}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final prevOnError = FlutterError.onError;
  FlutterError.onError = (d) {
    final x = d.toString();
    if (x.contains('overflowed')) {
      // ignore: avoid_print
      print('OVFD ${x.split(String.fromCharCode(10)).take(40).join(' | ')}');
    }
    prevOnError?.call(d);
  };
  addTearDown(() => FlutterError.onError = prevOnError);
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => (provider ?? _AdminP.new)(),
    child: MaterialApp(
      navigatorKey: navigatorKey,
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Scaffold(
        body: WorkerDetailDialog(
          user: UserModel(uid: _worker, username: _worker, name: '큐에이일',
              email: 'w9@test.local', role: UserRole.USER),
          application: _pending(),
          businessId: _biz,
          showApprovalButtons: true,
        ),
      ),
    ),
  ));
  await _settle(t);
}

Future<void> _settle(WidgetTester t, [int n = 30]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  _drain(t);
}

/// 상세의 다른 조회(근무 이력·리뷰)는 이 하네스에서 플랫폼이 없어 실패한다.
/// 그 예외는 버리되 **레이아웃 넘침은 모아 둔다**.
void _drain(WidgetTester t) {
  Object? e;
  while ((e = t.takeException()) != null) {
    final s = e.toString();
    if (s.contains('overflowed')) {
      _errors.add(s.split('\n').first);
    }
  }
}

Future<void> _finish(WidgetTester t) async {
  await t.pump(const Duration(seconds: 5));
  _drain(t);
}

String _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .join(' | ');

Finder _approveBtn() => find.ancestor(
    of: find.text('확정').hitTestable(), matching: find.byType(InkWell));


const _channel =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

/// 서버 대역 — LOCAL(g185)에서 본 규칙: businessId 없음·빈 값 → invalid-argument,
///   지원서 사업장과 다름 → not-found, 권한 거절 모드 → permission-denied.
class _ConfirmServer {
  final Map<String, String> appBusiness = {'app1': _biz};
  final List<Map<Object?, Object?>> payloads = [];
  bool deny = false;
  Future<ByteData?> handle(ByteData? message) async {
    final args = (const StandardMessageCodec().decodeMessage(message) as List)
        .first as Map;
    if (args['functionName'] != 'callableConfirmApplication') {
      return _err('unavailable');
    }
    final p = Map<Object?, Object?>.from(args['parameters'] as Map? ?? const {});
    payloads.add(p);
    final biz = p['businessId'];
    if (biz is! String || biz.isEmpty) return _err('invalid-argument');
    if (deny) return _err('permission-denied');
    if (appBusiness[p['applicationId']] != biz) return _err('not-found');
    return const StandardMessageCodec().encodeMessage(<Object?>[
      <String, Object?>{
        'success': true,
        'alreadyConfirmed': false,
        'autoCanceledDetails': <Object?>[],
        'appInfo': <String, Object?>{},
      }
    ]);
  }

  ByteData? _err(String code) => const StandardMessageCodec().encodeMessage(
      <Object?>[code, 'mock $code', <String, Object?>{'code': code}]);
}

void _install(WidgetTester t, _ConfirmServer s) {
  t.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, s.handle);
  addTearDown(() =>
      t.binding.defaultBinaryMessenger.setMockMessageHandler(_channel, null));
}

Future<void> _approve(WidgetTester t) async {
  await t.tap(_approveBtn().first);
  await _settle(t, 10);
  expect(find.text('지원자 확정'), findsOneWidget, reason: '확인창이 떠야 한다');
  await t.tap(find.text('확정').last);
  await _settle(t, 20);
}

/// 일괄 경로 processOne 이 넘기는 인자 그대로(CB-7 이 그 인자를 소스에서 고정한다).
Future<Object?> _bulkConfirm(ApplicationModel app,
    {required bool withBusinessId}) async {
  try {
    await FirestoreService().updateApplicationStatus(
      applicationId: app.id,
      businessId: withBusinessId ? app.businessId : null,
      status: AppStatus.confirmed,
      confirmedBy: 'owner1',
    );
    return 'OK';
  } on FirebaseFunctionsException catch (e) {
    return e.code;
  }
}

ApplicationModel _appIn(String id, String biz) {
  final a = _pending();
  return ApplicationModel(
    id: id,
    uid: a.uid,
    toId: a.toId,
    slotId: a.slotId,
    wdId: a.wdId,
    businessId: biz,
    businessName: a.businessName,
    toTitle: a.toTitle,
    selectedWorkType: a.selectedWorkType,
    startTime: a.startTime,
    endTime: a.endTime,
    wage: a.wage,
    wageType: a.wageType,
    status: a.status,
    workDate: a.workDate,
    appliedAt: a.appliedAt,
  );
}

Future<void> _pumpHost(WidgetTester t) async {
  await t.pumpWidget(
      MaterialApp(navigatorKey: navigatorKey, home: const Scaffold()));
  await t.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(() => ApplicantDocumentReviewService.debugOverride = null);

  group('CB-UI 근로자 상세 승인 (실제 화면 handler)', () {
    testWidgets('CB-1 승인 payload 에 지원서의 businessId 가 실려 서버가 받는다',
        (t) async {
      final s = _ConfirmServer();
      _install(t, s);
      ApplicantDocumentReviewService.debugOverride =
          _FakeReview([_map(matchingReady: true, state: 'READY_AUTO')]);
      await _open(t);
      await _approve(t);
      expect(s.payloads, hasLength(1));
      expect(s.payloads.single['applicationId'], 'app1');
      expect(s.payloads.single['businessId'], _biz);
      await _finish(t);
    });

    testWidgets('CB-2 권한 거절은 그대로 거절이다(payload 는 같다)', (t) async {
      final s = _ConfirmServer()..deny = true;
      _install(t, s);
      ApplicantDocumentReviewService.debugOverride =
          _FakeReview([_map(matchingReady: true, state: 'READY_AUTO')]);
      await _open(t);
      await _approve(t);
      expect(s.payloads, hasLength(1));
      expect(s.payloads.single['businessId'], _biz);
      expect(_texts(t).contains('확정되었습니다. 계약서를 보내야 근무자가 동의할 수 있어요.'), isFalse);
      // [UI-3] 확정 실패는 상세를 닫지 않는다 — 같은 사람에게 다시 시도할 수 있게 남는다.
      expect(findVisibleText('큐에이일'), findsWidgets);
      expect(_approveBtn(), findsWidgets);
      await _finish(t);
    });

    testWidgets('CB-3 확인창에서 승인을 연타해도 요청은 1번', (t) async {
      final s = _ConfirmServer();
      _install(t, s);
      ApplicantDocumentReviewService.debugOverride =
          _FakeReview([_map(matchingReady: true, state: 'READY_AUTO')]);
      await _open(t);
      await t.tap(_approveBtn().first);
      await _settle(t, 10);
      final btn = find.text('확정').last;
      await t.tap(btn);
      await t.tap(btn, warnIfMissed: false);
      await _settle(t, 20);
      expect(s.payloads, hasLength(1));
      await _finish(t);
    });
  });

  group('CB-SVC 일괄 확정 경로 인자 (서비스 → callable)', () {
    testWidgets('CB-4 수정 전 모양(businessId 없음)은 거절, 수정 후 모양은 성공',
        (t) async {
      final s = _ConfirmServer();
      _install(t, s);
      await _pumpHost(t);
      final app = _pending();
      Object? before, after;
      await t.runAsync(() async {
        before = await _bulkConfirm(app, withBusinessId: false);
        after = await _bulkConfirm(app, withBusinessId: true);
      });
      await t.pump(const Duration(seconds: 1));
      expect(before, 'invalid-argument');
      expect(s.payloads.first.containsKey('businessId'), isFalse,
          reason: '래퍼는 null 이면 키를 뺀다');
      expect(after, 'OK');
      expect(s.payloads.last['businessId'], _biz);
    });

    testWidgets('CB-5 여러 사업장 지원서를 한 번에 확정해도 각자 제 사업장이 간다',
        (t) async {
      final s = _ConfirmServer()
        ..appBusiness.addAll({'a1': 'bizA', 'a2': 'bizB', 'a3': 'bizA'});
      _install(t, s);
      await _pumpHost(t);
      final apps = [_appIn('a1', 'bizA'), _appIn('a2', 'bizB'), _appIn('a3', 'bizA')];
      final results = <Object?>[];
      await t.runAsync(() async {
        results.addAll(await Future.wait(
            apps.map((a) => _bulkConfirm(a, withBusinessId: true))));
      });
      await t.pump(const Duration(seconds: 1));
      expect(results, ['OK', 'OK', 'OK']);
      final sent = {for (final p in s.payloads) p['applicationId']: p['businessId']};
      expect(sent, {'a1': 'bizA', 'a2': 'bizB', 'a3': 'bizA'});
    });
  });

  group('CB-SRC 확정 호출부 소스 가드', () {
    Iterable<(String, String)> confirmCalls() sync* {
      final files = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'));
      for (final f in files) {
        final src = f.readAsStringSync();
        var i = src.indexOf('updateApplicationStatus(');
        while (i >= 0) {
          // 주석 안의 언급(예: `updateApplicationStatus(confirmed) → …`)은 호출이 아니다.
          final lineStart = src.lastIndexOf('\n', i) + 1;
          if (src.substring(lineStart, i).trimLeft().startsWith('//')) {
            i = src.indexOf('updateApplicationStatus(', i + 1);
            continue;
          }
          final end = src.indexOf(');', i);
          final block = src.substring(i, end < 0 ? src.length : end);
          final isDecl = src.substring(i > 40 ? i - 40 : 0, i).contains('Future<');
          final confirmCapable = block.contains('status: AppStatus.confirmed') ||
              block.contains('status: newStatus') ||
              block.contains("status: 'CONFIRMED'");
          if (!isDecl && confirmCapable) yield (f.path.replaceAll('\\', '/'), block);
          i = src.indexOf('updateApplicationStatus(', i + 1);
        }
      }
    }

    test('CB-6 화면의 확정 호출은 모두 businessId 를 보낸다', () {
      // 서비스 내부 batchConfirmApplications 는 제품 호출자가 없다(이번 범위 밖).
      final missing = [
        for (final (path, block) in confirmCalls())
          if (!block.contains('businessId:') &&
              !path.endsWith('application_firestore.dart'))
            path,
      ];
      expect(missing, isEmpty);
    });

    test('CB-7 두 호출부는 지원서 자신의 사업장을 보낸다', () {
      final wa = File('lib/screens/business_admin/dialogs/work_applicants_dialog.dart')
          .readAsStringSync();
      final p1 = wa.indexOf('Future<String> processOne(');
      final call = wa.indexOf('updateApplicationStatus(', p1);
      expect(wa.substring(call, wa.indexOf(');', call)),
          contains('businessId: app.businessId,'));
      final wd = File('lib/widgets/dialogs/worker_detail_dialog.dart')
          .readAsStringSync();
      expect(wd, contains('businessId: widget.application!.businessId,'));
    });

    // [UI-2/UI-3] 확정이 서버에서 끝난 뒤 템플릿만 닫으면 상세에 `대기중`·확정
    //   버튼이 남아 재확정을 부르던 회귀. 닫고·확정 안내·목록 갱신을 한다.
    test('CB-8 확정 후 템플릿 닫힘은 상세를 닫고 확정 안내 뒤 목록을 갱신한다', () {
      final wd = File('lib/widgets/dialogs/worker_detail_dialog.dart')
          .readAsStringSync();
      final fn = wd.indexOf('Future<void> _createContractAndSign()');
      final sel = wd.indexOf('ContractTemplateSelectorDialog.show(', fn);
      final branch = wd.indexOf('if (articles == null) {', sel);
      expect(branch, greaterThan(sel));
      final body = wd.substring(branch, wd.indexOf('return;', branch));
      final pop = body.indexOf('Navigator.pop(context);');
      final toast = body.indexOf(
          "ToastHelper.showSuccess('확정되었습니다. 계약서를 보내야 근무자가 동의할 수 있어요.');");
      final refresh = body.indexOf('callback?.call();');
      expect(pop, greaterThanOrEqualTo(0));
      expect(toast, greaterThan(pop));
      expect(refresh, greaterThan(toast),
          reason: '목록 갱신은 확정 안내 뒤 — 갱신 실패가 확정 결과를 뒤집지 않는다');
      // 이 함수는 확정 성공 뒤에만 불린다(호출부 하나).
      expect(RegExp(r'_createContractAndSign\(\)').allMatches(wd).length, 2);
    });

    test('CB-9 확정 호출 실패는 성공 안내·상세 닫기로 가지 않는다', () {
      final wd = File('lib/widgets/dialogs/worker_detail_dialog.dart')
          .readAsStringSync();
      final call = wd.indexOf('await _firestoreService.updateApplicationStatus(');
      final c = wd.indexOf('} catch (e) {', call);
      final handler = wd.substring(c, wd.indexOf('\n  }\n', c));
      expect(handler, isNot(contains('Navigator.pop')));
      expect(handler, isNot(contains('showSuccess')));
      expect(handler, contains('showError'));
    });
  });
}
