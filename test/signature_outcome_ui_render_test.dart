// [E2-SIGNATURE-OUTCOME-UI] 서명 응답 유실 — 서명 화면이 세 결과를 다르게 말하는가 (RENDER)
//
// 근로자 서명 화면을 실제로 그리고, 저장된 서명 → 바텀시트 → 서명 → 실제 PDF 빌더 → 실제
// `ContractService.saveWorkerSignature` 까지 production 경로를 그대로 탄다. 바꾸는 것은
// callable 경계(`workerSignatureCall`)와 계약 원장 읽기(`contractDocReader`) 둘뿐이다
// (화면은 선택적 `service` 주입으로 그 서비스를 받는다 — 기존 호출부 불변).
//
//   SOR-1  커밋이 증명된 응답 유실 → "계약서 서명이 완료되었습니다!" + 화면 종료(결과 completed)
//   SOR-2  SignatureOutcomeUnknown → 결과 확인 문구 · 같은 화면 버튼 잠금 · 완료로 오표시 없음 ·
//          잠금 상태 연속 탭에도 서명 callable 재호출 0
//   SOR-3  명확한 서버 거절 → 서버 문구 그대로, 버튼 원래대로(잠그지 않음)
//
// 사업주 경로는 인감을 화면이 `FirebaseFirestore.instance` 로 직접 읽어야 서명 단계에 들어간다
// (businesses/{id} → users/{ownerId}.sealBase64). 서비스 주입만으로는 도달할 수 없어
// 여기서 렌더하지 않는다 — RENDER 미검증(서비스 단 ESL-* 은 LOCAL 통과).
//
// 미디어는 합성 바이트만 쓴다. 서명·PDF 바이트나 경로를 출력하지 않는다.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart'; // [DU255] keepWords 문구는 보이는 글자로 찾는다
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/contract/contract_sign_screen.dart';
import 'package:ALfit/services/contract_service.dart';
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

/// 1x1 투명 PNG — 합성 저장 서명.
const _pngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'wk1',
        username: 'wk1',
        name: '합성근로',
        email: 'wk1@alfit.local',
        role: UserRole.USER,
        createdAt: DateTime(2026, 1, 1),
        signatureBase64: _pngB64,
      );

  @override
  Future<void> refreshPendingContracts({bool joinInFlight = false}) async {}
}

ContractSnapshot _snapshot() => ContractSnapshot(
      businessName: '합성 사업장',
      businessNumber: '000-00-00000',
      businessAddress: '서울',
      ownerName: '사업주',
      workerName: '합성근로',
      workType: '홀서빙',
      workPlace: '서울',
      isLongTerm: false,
      contractStart: '2026-10-20',
      contractEnd: '2026-10-20',
      workDays: const [],
      startTime: '10:00',
      endTime: '11:00',
      breakMinutes: 0,
      wage: 12000,
      wageType: 'hourly',
      paymentMethod: '계좌이체',
      wagePaymentDay: 10,
      taxDeductionType: 'none',
    );

EmploymentContractModel _contract() => EmploymentContractModel(
      id: 'ctW',
      applicationId: 'appZ',
      businessId: 'biz1',
      workerId: 'wk1',
      isLongTerm: false,
      toId: '', // TO 타입 조회를 건너뛴다
      workDetailId: 'wd1',
      status: ContractStatus.pendingWorker,
      snapshot: _snapshot(),
      createdAt: DateTime(2026, 10, 17),
    );

/// callable·원장 경계만 갈아끼운 **실제** 서비스.
class _Rig {
  int calls = 0;
  Object Function()? throwOnCall;
  bool committedOnServer = false; // true 면 원장에 이번 바이트의 해시로 completed 가 보인다
  Map<String, dynamic>? lastPayload;

  late final ContractService service = ContractService(
    workerSignatureCall: (data) async {
      calls++;
      lastPayload = data;
      final t = throwOnCall;
      if (t != null) throw t();
      return {'success': true, 'pdfStoragePath': 'p/contract.pdf', 'workerSignatureStoragePath': 'p/sig.png'};
    },
    contractDocReader: (id) async {
      if (!committedOnServer || lastPayload == null) return null;
      String h(String b64) => sha256.convert(base64Decode(b64)).toString();
      return {
        'applicationId': 'appZ',
        'applicationIds': ['appZ'],
        'businessId': 'biz1',
        'workerId': 'wk1',
        'status': 'completed',
        'workerSignedAt': Timestamp.fromMillisecondsSinceEpoch(1760683860000),
        'workerSignatureHash': h(lastPayload!['signatureBase64'] as String),
        'pdfHash': h(lastPayload!['pdfBase64'] as String),
        'pdfStoragePath': 'p/contract.pdf',
        'workerSignatureStoragePath': 'p/sig.png',
      };
    },
    employerSignatureRecheckDelay: Duration.zero,
  );
}

Future<void> _settle(WidgetTester t, {int rounds = 20}) async {
  for (var i = 0; i < rounds; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// 목록 화면 대역: 서명 화면을 push 하고 돌아온 결과를 적는다.
Future<List<Object?>> _open(WidgetTester t, _Rig rig) async {
  final results = <Object?>[];
  t.view.physicalSize = const Size(430, 6000); // 스크롤 없이 끝까지 보이게 → 동의 즉시 가능
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await Navigator.push(ctx, MaterialPageRoute(
                    builder: (_) => ContractSignScreen(contract: _contract(), role: 'worker', service: rig.service)));
                results.add(r);
              },
              child: const Text('목록'),
            ),
          ),
        ),
      ),
    ),
  ));
  await t.tap(find.text('목록'));
  await _settle(t);
  return results;
}

/// 서명을 진행하고, 진행 중 **한 번이라도** 화면에 나타난 문구를 모은다(토스트는 몇 초 뒤 사라진다).
Future<Set<String>> _signWithSaved(WidgetTester t, List<String> watch) async {
  final seen = <String>{};
  void look() { for (final w in watch) { if (findVisibleTextContaining(w).evaluate().isNotEmpty) seen.add(w); } } // [DU255 r1]
  await t.tap(findVisibleText('위 근로계약서의 내용을 모두 확인하였으며 동의합니다.'));
  await _settle(t, rounds: 3);
  await t.tap(findVisibleText('서명 완료 → 계약 확정')); // [DU255 r1] keepWords 버튼 글
  await _settle(t, rounds: 6);
  await t.tap(find.text('저장된 서명으로 서명'));
  // PDF 빌드는 실제 비동기 작업이다
  for (var i = 0; i < 30; i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await t.pump(const Duration(milliseconds: 100));
    look();
  }
  return seen;
}

ElevatedButton _signButton(WidgetTester t) => t.widget<ElevatedButton>(
    find.ancestor(of: findVisibleTextContaining('→ 계약 확정').evaluate().isNotEmpty
        ? findVisibleTextContaining('→ 계약 확정')
        : findVisibleTextContaining('저장 결과 확인 필요'), matching: find.byWidgetPredicate((w) => w is ElevatedButton)).first);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('SOR-1 커밋이 증명된 응답 유실 → 정상 성공 문구 + 화면 종료', (t) async {
    final rig = _Rig()
      ..throwOnCall = (() => FirebaseFunctionsException(message: 'DEADLINE_EXCEEDED', code: 'deadline-exceeded'))
      ..committedOnServer = true;
    final results = await _open(t, rig);
    final seen = await _signWithSaved(t, ['계약서 서명이 완료되었습니다!', '확인하지 못했습니다', '실패']);
    expect(rig.calls, 1);
    expect(seen, {'계약서 서명이 완료되었습니다!'}, reason: '성공 문구만 — 불명확·실패 문구 없음');
    expect(find.byType(ContractSignScreen), findsNothing, reason: '화면이 닫혔다');
    expect(results, hasLength(1));
    expect((results.single as EmploymentContractModel).status, ContractStatus.completed);
    await _settle(t, rounds: 40); // 토스트 타이머 소진
  });

  testWidgets('SOR-2 결과 불명확 → 확인 문구 · 버튼 잠금 · 완료 오표시 없음 · 연속 탭에도 재호출 0', (t) async {
    final rig = _Rig()
      ..throwOnCall = (() => FirebaseFunctionsException(message: 'DEADLINE_EXCEEDED', code: 'deadline-exceeded'))
      ..committedOnServer = false; // 원장에서 확인되지 않는다
    final results = await _open(t, rig);
    final seen = await _signWithSaved(t, ['계약서 서명이 완료되었습니다!', '서명 저장 결과를 확인하지 못했습니다']);
    expect(rig.calls, 1);
    expect(seen, {'서명 저장 결과를 확인하지 못했습니다'});
    expect(find.byType(ContractSignScreen), findsOneWidget, reason: '같은 화면에 남는다');
    expect(results, isEmpty);
    // 완료로 오표시하지 않는다
    expect(findVisibleText('계약서 서명이 완료되었습니다!'), findsNothing);
    expect(findVisibleTextContaining('쌍방 서명이 완료된 계약서입니다'), findsNothing);
    expect(findVisibleTextContaining('서명 완료 — 계약이 확정됩니다'), findsNothing);
    // 버튼은 잠겼고 문구가 바뀌었다
    expect(findVisibleTextContaining('저장 결과 확인 필요'), findsOneWidget);
    expect(findVisibleText('서명 완료 → 계약 확정'), findsNothing); // [DU255 r1] 원문으로는 늘 0개(거짓 통과)
    expect(_signButton(t).onPressed, isNull);
    for (var i = 0; i < 5; i++) {
      await t.tap(findVisibleTextContaining('저장 결과 확인 필요'), warnIfMissed: false);
      await _settle(t, rounds: 2);
    }
    expect(find.text('저장된 서명으로 서명'), findsNothing, reason: '서명 시트가 다시 열리지 않는다');
    expect(rig.calls, 1, reason: '잠금 상태에서 서명 callable 재호출 0');
    await _settle(t, rounds: 40);
  });

  testWidgets('SOR-3 명확한 서버 거절 → 서버 문구 그대로, 버튼은 잠그지 않는다', (t) async {
    final rig = _Rig()
      ..throwOnCall = (() => FirebaseFunctionsException(
          message: '본인의 계약서만 서명할 수 있습니다.', code: 'permission-denied'));
    final results = await _open(t, rig);
    final seen = await _signWithSaved(t, ['본인의 계약서만 서명할 수 있습니다.', '서명 저장 결과를 확인하지 못했습니다', '계약서 서명이 완료되었습니다!']);
    expect(rig.calls, 1);
    expect(seen, {'본인의 계약서만 서명할 수 있습니다.'}, reason: '기존 오류 표시 그대로');
    expect(find.byType(ContractSignScreen), findsOneWidget);
    expect(results, isEmpty);
    expect(findVisibleText('서명 완료 → 계약 확정'), findsOneWidget); // [DU255 r1]
    expect(_signButton(t).onPressed, isNotNull);
    await _settle(t, rounds: 40);
  });
}

