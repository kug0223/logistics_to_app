// [ADMIN-DOC-REVIEW-UX] 관리자 지원자 상세의 서류 확인 · 승인 계약.
//
// ── writer → state → reader ────────────────────────────────────────────
//   신분증 `확인 완료`  → callableReviewApplicantDocument(ID, REVIEWED_OK)
//                        → businessApplicantDocumentReviews.idDecision
//                        → srvResolveMatchingReadiness → READY_MANUAL
//   통장 `확인 완료`    → 같은 callable(BANKBOOK) → bankDecision
//                        → 확정 조건 아님(지급 준비만)
//   `승인`              → callableConfirmApplication(PENDING)
//                        → confirmReviewGate = srvResolveMatchingReadiness
//   화면은 callableGetApplicantDocumentReview 의 matchingReadiness 를 그대로
//   읽는다. 이 파일은 **그 값을 모를 때 승인을 열지 않는지**와 **좁은 화면에서
//   버튼이 사라지지 않는지**를 실행으로 본다.
//
//   DRU-A  판정·문구 순수 함수
//   DRU-B  네 상태(조회 중·조회 실패·확정 불가·확정 가능)와 권한 없음의 승인 동작
//   DRU-C  320/360/411dp × 글자 1.0/1.3/2.0 — 넘침 0, 버튼 3개 도달, 하단 고정 영역
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart'; // [DU255] keepWords 문구는 보이는 글자로 찾는다
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
    String name = '큐에이일',
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
          user: UserModel(uid: _worker, username: _worker, name: name,
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  // 상세의 부가 조회(근무 이력·리뷰 = callable)는 플랫폼이 없으면 **영원히
  //   기다린다** — 그러면 `_isLoading` 이 풀리지 않는다. 실제 앱의
  //   "조회 실패"처럼 오류로 끝나게 한다.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
            'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
            (data) async {
      return const StandardMessageCodec()
          .encodeMessage(<Object?>['unavailable', 'test harness', null]);
    });
  });
  setUp(_errors.clear);
  tearDown(() => ApplicantDocumentReviewService.debugOverride = null);

  group('DRU-A 판정·문구', () {
    ApplicantDocumentReview r(Map<String, dynamic> m) =>
        ApplicantDocumentReview.fromMap(m);

    test('DRU-01 승인 상태는 서버 판정을 알 때만 ready 다', () {
      expect(approvalGateOf(loading: true, failed: false, review: null),
          ApprovalGate.checking);
      expect(approvalGateOf(loading: false, failed: false, review: null),
          ApprovalGate.checking, reason: '아직 첫 조회 전');
      expect(approvalGateOf(loading: false, failed: true, review: null),
          ApprovalGate.unknown);
      expect(approvalGateOf(loading: false, failed: false, review: r(_map())),
          ApprovalGate.blocked);
      expect(
          approvalGateOf(
              loading: false,
              failed: false,
              review: r(_map(matchingReady: true, state: 'READY_AUTO'))),
          ApprovalGate.ready);
      // 재조회 중이면 이전 ready 도 ready 가 아니다.
      expect(
          approvalGateOf(
              loading: true,
              failed: false,
              review: r(_map(matchingReady: true, state: 'READY_AUTO'))),
          ApprovalGate.checking);
    });

    test('DRU-01b 확정 권한이 먼저다 — 거부·모름·오류는 신분 확인보다 앞선다', () {
      final ready = r(_map(matchingReady: true, state: 'READY_AUTO'));
      expect(
          approvalGateOf(loading: false, failed: false, review: ready,
              permission: PermissionCheck.denied),
          ApprovalGate.denied);
      expect(
          approvalGateOf(loading: false, failed: false, review: ready,
              permission: PermissionCheck.unknown),
          ApprovalGate.checking);
      expect(
          approvalGateOf(loading: false, failed: false, review: ready,
              permission: PermissionCheck.error),
          ApprovalGate.unknown);
      // 권한이 있어도 신분 확인을 모르면 계속 막는다.
      expect(
          approvalGateOf(loading: false, failed: true, review: null,
              permission: PermissionCheck.allowed),
          ApprovalGate.unknown);
    });

    test('DRU-02 상세 문구는 자기 자신(지원자 상세)을 가리키지 않는다', () {
      for (final s in ['ID_UNASSESSED', 'ID_MISMATCH', 'ID_OCR_UNCERTAIN', 'ID_MISSING', 'X']) {
        for (final m in [
          _map(state: s),
          _map(state: s, canReview: false),
          _map(state: s, consentBlock: '동의 필요'),
          _map(state: s, idStale: true),
        ]) {
          final text = r(m).approvalBlockText!;
          expect(text.contains('지원자 상세'), isFalse, reason: '$s → $text');
        }
      }
      expect(r(_map(matchingReady: true, state: 'READY_MANUAL')).approvalBlockText,
          isNull);
    });

    test('DRU-02b [DOC-LATE-DELETE.7] 등록돼 있지만 사진 파일 확인 중/없음 → "등록되어 있지 않아" 가 아니다', () {
      Map<String, dynamic> m(String reason, {bool has = true}) {
        final x = _map(state: 'ID_MISSING');
        (x['matchingReadiness'] as Map)['reason'] = reason;
        (x['documents'] as Map)['hasIdCard'] = has;
        return x;
      }
      final pending = r(m('신분증 파일을 확인하고 있습니다. 잠시 후 다시 시도해주세요.')).approvalBlockText!;
      final missing = r(m('신분증 파일을 찾을 수 없습니다. 신분증을 다시 등록해야 합니다.')).approvalBlockText!;
      final none = r(m('신분증이 등록되어 있지 않습니다.', has: false)).approvalBlockText!;
      expect(pending, contains('확인하는 중'));
      expect(missing, contains('[다시 등록 요청]'));
      // [DOC-DEV-ROLLOUT.9 갱신] 예전 기대: '신분증이 등록되어 있지 않아 확정할 수 없어요.'
      //   제품 결정 — 미등록은 할 사람(지원자)과 다음 조건을 말한다. 버튼·요청은 붙이지 않는다.
      expect(none, '지원자가 아직 신분증을 등록하지 않았어요.\n등록이 완료되면 다시 진행할 수 있어요.');
      expect(none.contains('[다시 등록 요청]'), isFalse);
      for (final t in [pending, missing]) {
        expect(t.contains('등록되어 있지 않아'), isFalse, reason: t);
        expect(t.contains('지원자 상세'), isFalse, reason: t);
      }
    });

    test('DRU-02c [DOC-APP-CLOSEOUT.10] 근거가 없으면 미등록·파일 없음으로 추정하지 않는다', () {
      Map<String, dynamic> m(String reason, {bool? has}) {
        final x = _map(state: 'ID_MISSING');
        (x['matchingReadiness'] as Map)['reason'] = reason;
        x['documents'] = {if (has != null) 'hasIdCard': has, 'hasBankbook': true};
        return x;
      }
      final old = r(m('신분증이 등록되어 있지 않습니다.'));          // 구 응답 — 등록 기록 필드 없음
      final odd = r(m('알 수 없는 사유', has: true));                 // 등록 기록은 있는데 사유를 모름
      expect(old.idMissingKind, IdMissingKind.unknown);
      expect(odd.idMissingKind, IdMissingKind.unknown);
      for (final t in [old.approvalBlockText!, odd.approvalBlockText!]) {
        expect(t, startsWith('신분증 상태를 확인하지 못해'));
        expect(t.contains('등록하지 않았어요') || t.contains('찾을 수 없어'), isFalse, reason: t);
      }
      expect(r(m('x', has: false)).idMissingKind, IdMissingKind.unregistered);
      expect(r(_map(state: 'ID_MISMATCH')).idMissingKind, isNull);
    });

    test('DRU-03 다음 행동은 누가 할 수 있는지에 따라 다르다', () {
      expect(r(_map()).approvalBlockText, contains('[확인 완료]'));
      expect(r(_map(canReview: false)).approvalBlockText,
          contains('급여 관리 권한이 모두 있는 관리자'));
      expect(r(_map(consentBlock: '동의 필요')).approvalBlockText,
          contains('서류 열람에 동의하면'));
      expect(r(_map(idStale: true)).approvalBlockText, contains('바뀌어'));
      expect(r(_map(state: 'ID_MISMATCH')).approvalBlockText,
          startsWith('등록된 신원정보와 신분증이 일치하지 않아요.'));
    });
  });

  group('DRU-B 승인 동작', () {
    testWidgets('DRU-04 조회 중 — `확인 중`, 눌러도 확인창이 뜨지 않는다', (t) async {
      final gate = Completer<Map<String, dynamic>>();
      ApplicantDocumentReviewService.debugOverride = _FakeReview([gate]);
      await _open(t);
      expect(find.text('확인 중'), findsOneWidget);
      expect(findVisibleText('확정'), findsNothing);
      await t.tap(find.text('확인 중'));
      await _settle(t, 10);
      expect(findVisibleText('지원자 확정'), findsNothing);
      gate.complete(_map(matchingReady: true, state: 'READY_AUTO'));
      await _settle(t);
      expect(find.text('확정'), findsOneWidget);
      await _finish(t);
    });

    testWidgets('DRU-04b 부가 조회가 멈춰도(지연) 신분 확인이 되면 승인은 바로 열린다',
        (t) async {
      // 부가 조회(근무 이력·리뷰 callable)가 응답하지 않는다 — 확정 조건이 아니다.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
              'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
              (data) => Completer<ByteData?>().future);
      ApplicantDocumentReviewService.debugOverride =
          _FakeReview([_map(matchingReady: true, state: 'READY_AUTO')]);
      await _open(t);
      expect(_texts(t), contains('신분증 정보가 자동 대조로 일치해 확정할 수 있어요.'));
      expect(find.text('확인 중'), findsNothing, reason: '부가 조회를 기다리지 않는다');
      await t.tap(find.text('확정'));
      await _settle(t, 10);
      expect(find.text('지원자 확정'), findsOneWidget);
      await t.tap(find.text('취소'));
      await _settle(t, 10);
      await _finish(t);
    });

    testWidgets('DRU-04c 부가 조회가 실패해도 신분 확인이 되면 승인은 열린다', (t) async {
      ApplicantDocumentReviewService.debugOverride =
          _FakeReview([_map(matchingReady: true, state: 'READY_AUTO')]);
      await _open(t); // 기본 하네스: 부가 callable 은 unavailable 로 실패
      await t.tap(find.text('확정'));
      await _settle(t, 10);
      expect(find.text('지원자 확정'), findsOneWidget);
      await t.tap(find.text('취소'));
      await _settle(t, 10);
      await _finish(t);
    });

    testWidgets('DRU-05 조회 실패 — 승인 닫힘 + `다시 불러오기` 로 회복', (t) async {
      final fake = _FakeReview([
        Exception('unavailable'),
        _map(matchingReady: true, state: 'READY_AUTO'),
      ]);
      ApplicantDocumentReviewService.debugOverride = fake;
      await _open(t);
      expect(find.text('서류 상태를 불러오지 못해 확정할 수 없어요.'), findsOneWidget);
      await t.tap(findVisibleText('확정'));
      await _settle(t, 10);
      expect(findVisibleText('지원자 확정'), findsNothing, reason: '모르는 채로 서버를 부르지 않는다');
      await _finish(t);
      await t.ensureVisible(find.text('다시 불러오기'));
      await t.tap(find.text('다시 불러오기'));
      await _settle(t);
      expect(fake.loads, 2);
      expect(_texts(t), contains('신분증 정보가 자동 대조로 일치해 확정할 수 있어요.'));
      await t.tap(find.text('확정'));
      await _settle(t, 10);
      expect(find.text('지원자 확정'), findsOneWidget, reason: 'ready 에서만 확인창');
      await t.tap(find.text('취소'));
      await _settle(t, 10);
      await _finish(t);
    });

    testWidgets('DRU-06 확정 불가 — 위쪽 요약이 이유와 다음 행동을 말하고, 승인은 닫힘',
        (t) async {
      ApplicantDocumentReviewService.debugOverride = _FakeReview([_map()]);
      await _open(t);
      final all = _texts(t);
      expect(all, contains('확정하려면 신분증 확인이 필요해요.'));
      expect(all.contains('지원자 상세에서'), isFalse, reason: '자기 참조 문구');
      expect(all, contains('근무 확정 전에 확인'));
      expect(all, contains('급여 지급 전까지 확인'));
      await t.tap(findVisibleText('확정'));
      await _settle(t, 10);
      expect(findVisibleText('지원자 확정'), findsNothing);
      await _finish(t);
    });

    testWidgets('DRU-07 확정 가능(통장 미확인) — 승인 열림, 통장은 막지 않는다고 말한다',
        (t) async {
      ApplicantDocumentReviewService.debugOverride = _FakeReview([
        _map(matchingReady: true, state: 'READY_MANUAL', idDecision: 'REVIEWED_OK')
      ]);
      await _open(t);
      final all = _texts(t);
      expect(all, contains('신분증 확인이 끝나 확정할 수 있어요.'));
      expect(all, contains('급여계좌는 지급 전까지 확인하면 돼요.'));
      // 신분증은 이미 확인 — 그 행에는 `확인 완료` 버튼이 없다.
      expect(find.widgetWithText(OutlinedButton, '확인 완료'), findsOneWidget,
          reason: '통장 행에만 남는다');
      await t.tap(find.text('확정'));
      await _settle(t, 10);
      expect(find.text('지원자 확정'), findsOneWidget);
      await t.tap(find.text('취소'));
      await _settle(t, 10);
      await _finish(t);
    });

    testWidgets('DRU-08 권한 없음 — 검토 버튼 없음, 누가 할 수 있는지 말한다, 승인 닫힘',
        (t) async {
      ApplicantDocumentReviewService.debugOverride =
          _FakeReview([_map(canReview: false)]);
      await _open(t);
      expect(find.text('신분증 보기'), findsNothing);
      expect(find.text('다시 등록 요청'), findsNothing);
      expect(_texts(t), contains('급여 관리 권한이 모두 있는 관리자가 신분증을 확인하면'));
      await t.tap(findVisibleText('확정'));
      await _settle(t, 10);
      expect(findVisibleText('지원자 확정'), findsNothing);
      await _finish(t);
    });
  });

  group('DRU-P 권한 조합', () {
    testWidgets('DRU-P1 확정 권한만(canManageTo) · 신분증 미확인 — 서류는 못 보고, 승인은 막히며 누가 확인하는지 말한다',
        (t) async {
      ApplicantDocumentReviewService.debugOverride =
          _FakeReview([_map(canReview: false)]);
      await _open(t, provider: () => _SubP(PermissionCheck.allowed));
      expect(find.text('신분증 보기'), findsNothing);
      expect(_texts(t), contains('급여 관리 권한이 모두 있는 관리자가 신분증을 확인하면'));
      expect(find.text('거절'), findsOneWidget, reason: '거절은 확정 권한으로 할 수 있다');
      await t.tap(findVisibleText('확정'));
      await _settle(t, 10);
      expect(findVisibleText('지원자 확정'), findsNothing);
      await _finish(t);
    });

    testWidgets('DRU-P2 확정 권한만 · 신분증 자동 일치 — 서류를 못 봐도 승인은 열린다',
        (t) async {
      ApplicantDocumentReviewService.debugOverride = _FakeReview(
          [_map(canReview: false, matchingReady: true, state: 'READY_AUTO')]);
      await _open(t, provider: () => _SubP(PermissionCheck.allowed));
      expect(find.text('신분증 보기'), findsNothing);
      await t.tap(find.text('확정'));
      await _settle(t, 10);
      expect(find.text('지원자 확정'), findsOneWidget,
          reason: '확정 조건은 열람 권한이 아니라 신분 확인이다');
      await t.tap(find.text('취소'));
      await _settle(t, 10);
      await _finish(t);
    });

    testWidgets('DRU-P3 반대 조합(급여 관리만 · 확정 권한 거부) — 승인·거절 대신 이유를 말한다',
        (t) async {
      // 서버는 열람에 canManageTo+canManageWage 를 둘 다 요구한다 — 급여만으로는
      //   서류도 못 본다. "서류는 보는데 확정은 못 하는" 조합은 없다.
      ApplicantDocumentReviewService.debugOverride = _FakeReview(
          [_map(canReview: false, matchingReady: true, state: 'READY_AUTO')]);
      await _open(t, provider: () => _SubP(PermissionCheck.denied));
      expect(findVisibleText('확정'), findsNothing);
      expect(_texts(t).contains('확정할 수 있어요'), isFalse);
      expect(find.text('거절'), findsNothing);
      expect(find.text('확정·거절은 TO 관리 권한이 있는 관리자만 할 수 있어요.'),
          findsOneWidget);
      expect(find.text('닫기'), findsOneWidget);
      await _finish(t);
    });

    testWidgets('DRU-P4 확정 권한을 아직 모름 — `확인 중`, 권한 확인 중이라고 말한다',
        (t) async {
      ApplicantDocumentReviewService.debugOverride =
          _FakeReview([_map(matchingReady: true, state: 'READY_AUTO')]);
      await _open(t, provider: () => _SubP(PermissionCheck.unknown));
      expect(findVisibleText('확정'), findsNothing);
      expect(_texts(t), contains('확정 권한을 확인하고 있어요.'));
      expect(_texts(t).contains('확정할 수 있어요'), isFalse,
          reason: '승인이 닫혀 있는데 배너만 가능하다고 하면 안 된다');
      await t.tap(find.text('확인 중'));
      await _settle(t, 10);
      expect(findVisibleText('지원자 확정'), findsNothing);
      expect(find.text('확정 권한을 확인하고 있어요. 잠시만 기다려 주세요.'), findsOneWidget);
      await _finish(t);
    });

    testWidgets('DRU-P5 확정 권한 확인 실패 — 회색 승인, 허용으로 접지 않는다', (t) async {
      ApplicantDocumentReviewService.debugOverride =
          _FakeReview([_map(matchingReady: true, state: 'READY_AUTO')]);
      await _open(t, provider: () => _SubP(PermissionCheck.error));
      expect(_texts(t), contains('확정 권한을 확인하지 못했어요.'));
      expect(_texts(t).contains('확정할 수 있어요'), isFalse);
      await t.tap(findVisibleText('확정'));
      await _settle(t, 10);
      expect(findVisibleText('지원자 확정'), findsNothing);
      expect(find.text('확정 권한을 확인하지 못해 확정할 수 없어요. 잠시 후 다시 열어 주세요.'),
          findsOneWidget);
      await _finish(t);
    });

    for (final c in [
      (PermissionCheck.unknown, '확정 권한을 확인하고 있어요. 잠시만 기다려 주세요.'),
      (PermissionCheck.error, '확정 권한을 확인하지 못해 거절할 수 없어요. 잠시 후 다시 열어 주세요.'),
    ]) {
      testWidgets('DRU-P7 확정 권한 ${c.$1.name} — 거절도 실행되지 않고 이유를 말한다',
          (t) async {
        ApplicantDocumentReviewService.debugOverride = _FakeReview([_map()]);
        await _open(t, provider: () => _SubP(c.$1));
        await t.tap(find.text('거절'));
        await _settle(t, 10);
        expect(findVisibleText('지원자 거절'), findsNothing, reason: '사유 선택창이 열리면 실행 가능처럼 보인다');
        expect(find.text(c.$2), findsOneWidget);
        await _finish(t);
      });
    }

    testWidgets('DRU-P8 확정 권한 허용 — 거절은 서류 상태와 무관하게 사유 선택으로 간다',
        (t) async {
      ApplicantDocumentReviewService.debugOverride =
          _FakeReview([Exception('unavailable')]);
      await _open(t, provider: () => _SubP(PermissionCheck.allowed));
      await t.tap(find.text('거절'));
      await _settle(t, 10);
      expect(find.text('지원자 거절'), findsOneWidget,
          reason: '거절의 서버 조건은 권한뿐 — 서류 조회 실패가 막지 않는다');
      await t.tap(find.text('취소').last);
      await _settle(t, 10);
      await _finish(t);
    });

    testWidgets('DRU-P6 권한 있음 · 신분 확인 조회 실패 — 계속 막고 재조회 경로를 준다',
        (t) async {
      final fake = _FakeReview([Exception('unavailable'), _map()]);
      ApplicantDocumentReviewService.debugOverride = fake;
      await _open(t, provider: () => _SubP(PermissionCheck.allowed));
      expect(find.text('다시 불러오기'), findsOneWidget);
      await t.tap(findVisibleText('확정'));
      await _settle(t, 10);
      expect(findVisibleText('지원자 확정'), findsNothing);
      await _finish(t);
      await t.ensureVisible(find.text('다시 불러오기'));
      await t.tap(find.text('다시 불러오기'));
      await _settle(t);
      expect(fake.loads, 2);
      expect(_texts(t), contains('확정하려면 신분증 확인이 필요해요.'));
      await _finish(t);
    });
  });

  group('DRU-C 좁은 화면 매트릭스', () {
    for (final w in [320.0, 360.0, 411.0]) {
      for (final s in [1.0, 1.3, 2.0]) {
        testWidgets('DRU-09 ${w.toInt()}dp × ${s}x — 넘침 0, 버튼 3개 도달, 하단 고정',
            (t) async {
          ApplicantDocumentReviewService.debugOverride = _FakeReview([_map()]);
          await _open(t, width: w, height: 760, scale: s);
          expect(_errors, isEmpty, reason: '넘침: $_errors');
          for (final label in ['신분증 보기', '확인 완료', '다시 등록 요청']) {
            final f = find.text(label).first;
            await t.ensureVisible(f);
            await _settle(t, 4);
            expect(f.hitTestable(), findsOneWidget,
                reason: '$label 이 스크롤로 닿아야 한다 (${w}dp ${s}x)');
          }
          // 하단 고정 버튼(닫기·거절·승인)은 스크롤과 무관하게 화면 안에 있다.
          for (final label in ['닫기', '거절', '확정']) {
            final rect = t.getRect(find.text(label).last);
            expect(rect.bottom <= 760 && rect.top >= 0, isTrue,
                reason: '$label 화면 밖: $rect');
          }
          expect(_approveBtn(), findsWidgets);
          await _finish(t);
          expect(_errors, isEmpty, reason: '넘침: $_errors');
        });
      }
    }

    // [COMMON-TEXT-LAYOUT.28] 하단 버튼은 칸당 88 × 글자 배율이 들어가면 한 줄, 아니면 쌓는다(다음 행동 위·닫기 아래).
    //   글자를 줄이지 않는다(FittedBox 없음). 띄어쓰기 없는 긴 이름은 줄 수 제한 없이 다 보인다.
    for (final c in [(411.0, 1.0, true), (411.0, 2.0, false)]) {
      testWidgets('DRU-10 ${c.$1.toInt()}dp × ${c.$2}x — 하단 ${c.$3 ? '한 줄' : '쌓음'}, 긴 이름 말줄임 없음',
          (t) async {
        ApplicantDocumentReviewService.debugOverride = _FakeReview([_map()]);
        await _open(t, width: c.$1, height: 760, scale: c.$2, name: '남궁아리아나크리스티나합성근로자');
        expect(_errors, isEmpty, reason: '넘침: $_errors');
        final close = t.getCenter(find.text('닫기').last);
        final approve = t.getCenter(find.text('확정').last);
        if (c.$3) {
          expect((close.dy - approve.dy).abs(), lessThan(4), reason: '한 줄');
        } else {
          expect(approve.dy, lessThan(close.dy - 10), reason: '쌓을 때 다음 행동이 위');
        }
        final name = find.byWidgetPredicate((w) =>
            w is Text && (w.data ?? '').replaceAll('\u2060', '').replaceAll('\u200B', '') ==
                '남궁아리아나크리스티나합성근로자');
        expect(name, findsWidgets);
        for (final e in name.evaluate()) {
          final w = e.widget as Text;
          expect(w.maxLines, isNull, reason: '이름 줄 수 제한 없음');
          expect(w.overflow, isNot(TextOverflow.ellipsis));
        }
        await _finish(t);
      });
    }
  });
}
