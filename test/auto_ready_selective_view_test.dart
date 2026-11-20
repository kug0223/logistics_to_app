// [AUTO-READY-SELECTIVE-VIEW] 자동 대조 일치(READY_AUTO)인 지원자 — 확정과 열람은 별도 행동이다.
//
//   ARV-1 자동 준비 + 열람 권한 + 동의: `신분증 보기`·`통장사본 보기` 가 보이고, 승인은 열려 있다.
//   ARV-2 보기를 눌러도 열람 URL 요청만 간다 — 확인 완료(review) 기록을 만들지 않는다.
//   ARV-3 보지 않아도 승인은 열려 있다(열람이 확정의 조건이 아니다).
//   ARV-4 열람 권한이 없는 확정 담당자: 보기 버튼 없음 · 승인은 열려 있다(문서 권한을 넓히지 않는다).
//   ARV-5 동의 전: 보기 버튼 없음, 동의 전 안내.
import 'package:flutter/material.dart';
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
import 'package:ALfit/widgets/dialogs/worker_detail_dialog.dart';

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

const _biz = 'biz1';
const _worker = 'w1';

class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'owner1', username: 'owner1', name: '관리자',
      email: 'owner1@test.local', role: UserRole.BUSINESS_ADMIN);
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

class _FakeReview extends Fake implements ApplicantDocumentReviewService {
  _FakeReview(this.map);
  final Map<String, dynamic> map;
  final List<String> urlCalls = [];
  int reviewCalls = 0;
  @override
  Future<ApplicantDocumentReview> load({required String applicationId, required String businessId}) async =>
      ApplicantDocumentReview.fromMap(map);
  @override
  Future<String?> documentUrl({required String applicationId, required String businessId,
      required String targetUid, required String documentType}) async {
    urlCalls.add(documentType);
    return null; // 뷰어는 열지 않는다 — 요청이 간 사실만 본다
  }
  @override
  Future<bool> review({required String applicationId, required String businessId, required String targetUid,
      required String documentType, required String decision, required int expectedVersion,
      int? expectedAccountVersion, String? note}) async {
    reviewCalls++;
    return true;
  }
}

/// 서버 callableGetApplicantDocumentReview 의 자동 준비 응답 모양(사람 검토 없음).
Map<String, dynamic> _autoReady({bool canReview = true, String? consentBlock}) => {
      'workerUid': _worker,
      'canReviewDocuments': canReview,
      'consentBlock': consentBlock,
      'versions': {'id': 1, 'bankbook': 1, 'account': 1},
      'readiness': {'ready': false, 'idDecision': 'NOT_REVIEWED', 'bankDecision': 'NOT_REVIEWED'},
      'documents': {'hasIdCard': true, 'hasBankbook': true},
      'matchingReadiness': {'ready': true, 'state': 'READY_AUTO', 'reason': null},
    };

ApplicationModel _pending() => ApplicationModel(
      id: 'app1', uid: _worker, toId: 'to1', slotId: 's1', wdId: 'wd1', businessId: _biz,
      businessName: '테스트 사업장', toTitle: '테스트 공고', selectedWorkType: '홀서빙',
      startTime: '10:00', endTime: '11:00', wage: 12000, wageType: 'hourly', status: AppStatus.pending,
      workDate: DateTime(2026, 10, 29), appliedAt: DateTime(2026, 10, 23),
      documentAccessConsentGiven: true, documentAccessConsentVersion: '2026-09-18-v3',
    );

Future<void> _pump(WidgetTester t, _FakeReview fake) async {
  ApplicantDocumentReviewService.debugOverride = fake;
  t.view.physicalSize = const Size(1080, 2400);
  t.view.devicePixelRatio = 3.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => _AdminP(),
    child: MaterialApp(
      home: Scaffold(
        body: WorkerDetailDialog(
          user: UserModel(uid: _worker, username: _worker, name: '자동근로자', email: 'w1@test.local', role: UserRole.USER),
          application: _pending(),
          businessId: _biz,
          showApprovalButtons: true,
        ),
      ),
    ),
  ));
  for (var i = 0; i < 30; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
  while (t.takeException() != null) {} // 부가 조회(근무 이력 등)는 이 하네스에 플랫폼이 없어 실패한다
}

String _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .join(' | ');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  tearDown(() => ApplicantDocumentReviewService.debugOverride = null);

  testWidgets('ARV-1·3 자동 준비 — 보기 두 개가 있고, 보지 않아도 승인이 열려 있다', (t) async {
    final fake = _FakeReview(_autoReady());
    await _pump(t, fake);
    final s = _texts(t);
    expect(s, contains('신분증 정보가 자동 대조로 일치해 확정할 수 있어요.'));
    expect(s, contains('서류 정보 일치'));
    expect(find.text('신분증 보기'), findsOneWidget, reason: '자동 일치라고 숨기지 않는다');
    expect(find.text('통장사본 보기'), findsOneWidget);
    expect(findVisibleText('확정'), findsOneWidget, reason: '확인 중이 아니라 승인(열림)');
    expect(fake.urlCalls, isEmpty, reason: '열람하지 않았다');
  });

  testWidgets('ARV-2 보기를 눌러도 열람 요청만 — 확인 완료 기록은 만들지 않는다', (t) async {
    final fake = _FakeReview(_autoReady());
    await _pump(t, fake);
    await t.ensureVisible(find.text('신분증 보기'));
    await t.tap(find.text('신분증 보기'));
    await t.pump(const Duration(milliseconds: 200));
    await t.ensureVisible(find.text('통장사본 보기'));
    await t.tap(find.text('통장사본 보기'));
    await t.pump(const Duration(milliseconds: 200));
    while (t.takeException() != null) {}
    expect(fake.urlCalls, ['ID', 'BANKBOOK']);
    expect(fake.reviewCalls, 0, reason: '보기 ≠ 확인 완료');
    expect(find.text('확정'), findsOneWidget, reason: '보기 뒤에도 확정 조건은 같다');
  });

  testWidgets('ARV-4 열람 권한 없는 확정 담당자 — 보기 없음 · 승인은 열림', (t) async {
    final fake = _FakeReview(_autoReady(canReview: false));
    await _pump(t, fake);
    expect(find.text('신분증 보기'), findsNothing);
    expect(find.text('통장사본 보기'), findsNothing);
    expect(find.text('확정'), findsOneWidget);
    expect(_texts(t), contains('신분증 정보가 자동 대조로 일치해 확정할 수 있어요.'));
  });

  testWidgets('ARV-5 동의 전 — 보기 없음, 아직 동의 전 안내', (t) async {
    final fake = _FakeReview(_autoReady(consentBlock: ApplicantDocumentReview.serverConsentMissingText));
    await _pump(t, fake);
    expect(find.text('신분증 보기'), findsNothing);
    expect(_texts(t), contains('근로자가 아직 서류 열람에 동의하지 않아 지금은 서류를 볼 수 없어요.'));
  });
}
