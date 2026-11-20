// [CONSENT-CLOSEOUT.30] 큰 글자 계약 동의 영역 — 읽기 공간·체크·버튼 도달성, 상태 보존 (RENDER)
//
// 긴 동의 문장·체크는 본문 끝으로 옮기고, 하단 고정 영역에는 한 줄 안내 + 서명 버튼만 남겼다.
//   CA-1  끝까지 읽기 전: 체크 불가·버튼 꺼짐·안내 문구. 끝에 닿아도 자동 체크하지 않는다.
//   CA-2  392·2.0 / 320·1.3 에서 고정 영역이 화면의 1/3 을 넘지 않고, 스크롤→동의→버튼이 켜진다.
//   CA-3  동의 뒤 글자 크기·폭이 바뀌어(relayout) 도 읽음·동의가 그대로다.
//   CA-4  같은 화면이 다른 계약을 받으면 앞 계약의 읽음·동의를 넘기지 않는다.
//   CA-5  서명 시트를 닫거나 뒤로 가면 서명 호출 0.
//
// 미디어는 합성 바이트만 쓴다.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:ALfit/theme/role_theme.dart';
import 'package:signature/signature.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart'; // [후속40] 문구가 keepWords(낱말 결합자)로 바뀌어 find.text 대신 보이는 글자로 찾는다

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

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

EmploymentContractModel _contract(String id) => EmploymentContractModel(
      id: id,
      applicationId: 'app_$id',
      businessId: 'biz1',
      workerId: 'wk1',
      isLongTerm: false,
      toId: '',
      workDetailId: 'wd1',
      status: ContractStatus.pendingWorker,
      snapshot: ContractSnapshot(
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
      ),
      createdAt: DateTime(2026, 10, 17),
    );

const _consent = '위 근로계약서의 내용을 모두 확인하였으며 동의합니다.';
const _hintBefore = '계약서를 끝까지 읽으면 동의할 수 있어요';
const _hintAfter = '본문 끝에서 동의에 체크하면 서명할 수 있어요';
const _signLabel = '서명 완료 → 계약 확정';

class _Host extends StatefulWidget {
  const _Host({required this.service, required this.scale, required this.contractId});
  final ContractService service;
  final double scale;
  final String contractId;
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  Widget build(BuildContext context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(widget.scale)),
        child: ContractSignScreen(
            contract: _contract(widget.contractId), role: 'worker', service: widget.service),
      );
}

int _calls = 0;
ContractService _service() => ContractService(
      workerSignatureCall: (data) async {
        _calls++;
        return {'success': true};
      },
      contractDocReader: (id) async => null,
      employerSignatureRecheckDelay: Duration.zero,
    );

Future<void> _settle(WidgetTester t, {int rounds = 10}) async {
  for (var i = 0; i < rounds; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pump(WidgetTester t, ContractService svc,
    {required double width, required double height, required double scale, String id = 'ctA'}) async {
  t.view.physicalSize = Size(width, height);
  t.view.devicePixelRatio = 1.0;
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
      ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      navigatorKey: navigatorKey,
      home: _Host(service: svc, scale: scale, contractId: id),
    ),
  ));
  await _settle(t);
}

ScrollPosition _body(WidgetTester t) => t
    .stateList<ScrollableState>(find.byType(Scrollable))
    .map((s) => s.position)
    .where((p) => p.axis == Axis.vertical)
    .reduce((a, b) => a.maxScrollExtent >= b.maxScrollExtent ? a : b);

Future<void> _scrollToEnd(WidgetTester t) async {
  final p = _body(t);
  p.jumpTo(p.maxScrollExtent);
  await _settle(t, rounds: 3);
}

ElevatedButton _button(WidgetTester t) => t.widget<ElevatedButton>(find
    .ancestor(of: findVisibleText(_signLabel), matching: find.byWidgetPredicate((w) => w is ElevatedButton))
    .first);

bool _checked(WidgetTester t) => find
    .descendant(
        of: find.byKey(const ValueKey('contract-consent-section')),
        matching: find.byIcon(Icons.check_box_rounded))
    .evaluate()
    .isNotEmpty;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    _calls = 0;
  });
  setUpAll(() async {
    await initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  for (final c in const [(392.0, 820.0, 1.0), (392.0, 820.0, 2.0), (320.0, 640.0, 1.3)]) {
    final (w, h, s) = c;
    testWidgets('CA-1·2 ${w.toInt()}·$s — 읽기 전 잠금, 끝에서 수동 동의, 고정 영역 1/3 이하', (t) async {
      addTearDown(t.view.reset);
      final svc = _service();
      await _pump(t, svc, width: w, height: h, scale: s);

      // 읽기 전: 안내·버튼 꺼짐, 체크 영역은 눌러도 바뀌지 않는다
      expect(find.text(_hintBefore), findsOneWidget);
      expect(_button(t).onPressed, isNull);
      expect(_body(t).maxScrollExtent, greaterThan(0), reason: '본문은 스크롤된다');

      // 고정 영역(안내 줄 윗변~화면 아래) ≤ 화면 1/3
      final fixedTop = t.getTopLeft(find.text(_hintBefore)).dy;
      expect(h - fixedTop, lessThanOrEqualTo(h / 3), reason: '읽기 공간을 고정 영역이 가리지 않는다');
      expect(t.getBottomLeft(findVisibleText(_signLabel)).dy, lessThanOrEqualTo(h), reason: '버튼이 화면 안');

      // 끝까지: 자동 체크하지 않는다
      await _scrollToEnd(t);
      expect(find.text(_hintAfter), findsOneWidget);
      expect(_checked(t), isFalse, reason: '자동 체크 없음');
      expect(_button(t).onPressed, isNull);

      // 동의 영역은 화면 안에서 눌린다
      final consent = findVisibleText(_consent);
      expect(t.getBottomLeft(consent).dy, lessThan(h));
      await t.tap(consent);
      await _settle(t, rounds: 2);
      expect(_checked(t), isTrue);
      expect(find.text(_hintAfter), findsNothing, reason: '동의 후 안내는 접힌다');
      expect(_button(t).onPressed, isNotNull);
      expect(_calls, 0);
    });
  }

  testWidgets('CA-1b 읽기 전 동의 영역을 눌러도 체크되지 않는다', (t) async {
    addTearDown(t.view.reset);
    await _pump(t, _service(), width: 392, height: 820, scale: 2.0);
    await t.tap(findVisibleText(_consent), warnIfMissed: false);
    await t.tap(find.text(_hintBefore), warnIfMissed: false);
    await _settle(t, rounds: 2);
    expect(_checked(t), isFalse);
    expect(_body(t).pixels, 0, reason: '읽기 전 안내는 끝으로 건너뛰는 수단이 아니다');
    expect(_button(t).onPressed, isNull);
  });

  testWidgets('CA-3 동의 뒤 글자 크기·폭 relayout — 읽음·동의 유지', (t) async {
    addTearDown(t.view.reset);
    final svc = _service();
    await _pump(t, svc, width: 392, height: 820, scale: 1.0);
    await _scrollToEnd(t);
    await t.tap(findVisibleText(_consent));
    await _settle(t, rounds: 2);
    expect(_button(t).onPressed, isNotNull);

    await _pump(t, svc, width: 320, height: 640, scale: 2.0); // 같은 계약, 다른 배치
    expect(_checked(t), isTrue);
    expect(_button(t).onPressed, isNotNull);
    expect(find.text(_hintBefore), findsNothing);
  });

  testWidgets('CA-4 다른 계약을 받으면 앞 계약의 읽음·동의를 넘기지 않는다', (t) async {
    addTearDown(t.view.reset);
    final svc = _service();
    await _pump(t, svc, width: 392, height: 820, scale: 1.0, id: 'ctA');
    await _scrollToEnd(t);
    await t.tap(findVisibleText(_consent));
    await _settle(t, rounds: 2);
    expect(_button(t).onPressed, isNotNull);

    await _pump(t, svc, width: 392, height: 820, scale: 1.0, id: 'ctB');
    expect(_checked(t), isFalse);
    expect(_button(t).onPressed, isNull);
    // 위치가 끝에 남아 있어도 새 계약의 '읽음'은 다음 스크롤에서 다시 판정한다
    _body(t).jumpTo(0);
    await _settle(t, rounds: 2);
    expect(find.text(_hintBefore), findsOneWidget);
  });

  testWidgets('CA-5 서명 시트 닫기·뒤로 → 서명 호출 0', (t) async {
    addTearDown(t.view.reset);
    final svc = _service();
    await _pump(t, svc, width: 392, height: 820, scale: 2.0);
    await _scrollToEnd(t);
    await t.tap(findVisibleText(_consent));
    await _settle(t, rounds: 2);
    await t.tap(findVisibleText(_signLabel));
    await _settle(t, rounds: 6);
    expect(find.text('저장된 서명으로 서명'), findsOneWidget);
    // 시트 밖(장벽)을 눌러 닫는다
    await t.tapAt(const Offset(20, 20));
    await _settle(t, rounds: 6);
    expect(find.text('저장된 서명으로 서명'), findsNothing);
    expect(_calls, 0);
    expect(_button(t).onPressed, isNotNull, reason: '취소 뒤 잠기지 않는다');
    // 뒤로
    await t.binding.handlePopRoute();
    await _settle(t, rounds: 6);
    expect(_calls, 0);
  });

  // ── [DU1 후속40 §2] B2-C — DU-S048/DU-O044 계약 서명·서명 패드 시각/행동 셀.
  //   기존 _Worker(합성 저장서명)·_service(호출 수 세기)·_Host·navigatorKey 그대로, 계약만 긴 값 + [QA] 자유조항 1개(_contractLong).
  //   캡처 boundary = MaterialApp 바깥(root Navigator overlay — 방법 시트·패드 시트 포함). theme RoleTheme.workerTheme(기존 CA 는 기본 theme).
  //   글꼴 vqLoadFonts(NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons; FlutterTest 미등록). DU1_VQ_OUT 직접.
  //   writer 경계: 계약 CTA 는 방법 시트 열기까지, '저장된 서명으로 서명'·패드 '서명 완료' 는 누르지 않는다(rect·hit·활성만).
  //   날짜: 본문 끝 날짜(_today)는 contractDate(createdAt 2026-10-17)의 KST 날짜 — 실행 시계와 무관(후속41 §1 정정).
  EmploymentContractModel contractLong(String id) => EmploymentContractModel(
        id: id, applicationId: 'app_$id', businessId: 'biz1', workerId: 'wk1', isLongTerm: false, toId: '', workDetailId: 'wd1',
        status: ContractStatus.pendingWorker,
        snapshot: ContractSnapshot(
          businessName: '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장', businessNumber: '000-00-00000',
          businessAddress: '경기도 평택시 포승읍 평택항만길 123 물류단지 B동 2층', ownerName: '사업주',
          workerName: '아주긴이름의지원자홍길동', workType: '냉장 피킹·검수 보조',
          workPlace: '경기도 평택시 포승읍 평택항만길 123 물류단지 B동 2층', isLongTerm: false,
          contractStart: '2026-10-20', contractEnd: '2026-10-20', workDays: const [], startTime: '10:00', endTime: '11:00',
          breakMinutes: 0, wage: 12000, wageType: 'hourly', paymentMethod: '계좌이체', wagePaymentDay: 10, taxDeductionType: 'none'),
        articles: const [
          ContractArticle(title: '[QA] 특약 사항',
              content: '[QA] 근무 중 안전화 착용을 원칙으로 하며, 냉장 구역 작업 시 지급된 방한 장비를 반드시 착용한다. '
                  '작업 구역 이동은 관리자 안내에 따르고, 지게차 통로에서는 지정된 보행로만 이용한다.'),
        ],
        createdAt: DateTime(2026, 10, 17),
      );

  Future<GlobalKey> b2cPump(WidgetTester t, ContractService svc, Size size, double scale) async {
    await t.runAsync(vqLoadFonts);
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          navigatorKey: navigatorKey,
          theme: RoleTheme.workerTheme,
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: ContractSignScreen(contract: contractLong('ctL'), role: 'worker', service: svc),
        ),
      ),
    ));
    await _settle(t);
    return key;
  }

  String mq(WidgetTester t) {
    final m = MediaQuery.of(t.element(find.byType(ContractSignScreen)));
    return 'screenMQ padding=${m.padding} viewPadding=${m.viewPadding} viewInsets=${m.viewInsets} · view physical padding=${t.view.padding.top},${t.view.padding.bottom} viewInsets=${t.view.viewInsets.bottom}';
  }

  Rect bodyViewport(WidgetTester t) {
    final st = t.stateList<ScrollableState>(find.byType(Scrollable)).where((s) => s.position.axis == Axis.vertical)
        .reduce((a, b) => a.position.maxScrollExtent >= b.position.maxScrollExtent ? a : b);
    return t.getRect(find.byWidget(st.widget));
  }

  bool hits(WidgetTester t, Finder target, Offset p) {
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
    return hit.path.any((e) => e.target == t.renderObject(target));
  }

  // ElevatedButton.icon 등은 하위 클래스라 runtimeType 비교가 빗나갔다(r2) — is 로 판별
  Finder btnOf(String label, Type type) => find.ancestor(of: findVisibleText(label), matching: find.byWidgetPredicate((w) =>
      type == ElevatedButton ? w is ElevatedButton : type == TextButton ? w is TextButton : type == OutlinedButton ? w is OutlinedButton : false)).first;

  Future<void> scrollBodyTo(WidgetTester t, Finder f) async {
    final st = t.stateList<ScrollableState>(find.byType(Scrollable)).where((s) => s.position.axis == Axis.vertical)
        .reduce((a, b) => a.position.maxScrollExtent >= b.position.maxScrollExtent ? a : b);
    await t.scrollUntilVisible(f, 200, scrollable: find.byWidget(st.widget), maxScrolls: 200);
    await _settle(t, rounds: 2);
  }

  // ── [DU1 후속41 §2] B2-C-B 읽기 보완 — 320×640@2.0 같은 화면·자료. 방법 시트·패드는 열지 않는다(writer 전부 미진입).
  //   본문을 순차 스크롤해 ① 긴 값(사업장명·근로자명·소재지/근무장소·업무) ② 자유조항 제목·첫 문장 / 마지막 문장 끝 ③ 본문 날짜·갑/을 서명란
  //   각각을 실제 본문 표시 영역(body Scrollable global rect) 안에 두고 offset·rect·PNG 를 남긴다. 큰 Text 는 시작 정렬과 **끝 정렬**을 따로 한다.
  testWidgets('B2-C-B-READ 계약 320×640@2.0 — 긴 값·자유조항 처음/끝·날짜·서명란 읽기 위치(writer 0)', (t) async {
    final overflows = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed')) {
        overflows.add(m.split('\n').first);
      } else {
        prev?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prev);
    final svc = _service();
    const size = Size(320, 640);
    final key = await b2cPump(t, svc, size, 2.0);
    final log = <String>['B2-C-B-READ ${mq(t)}'];
    final pos = _body(t);
    Future<({Rect vp, Rect r, double off})> align(Finder f, {required bool end}) async {
      await scrollBodyTo(t, f.first); // 같은 값이 둘 이상(예: 소재지·근무장소) — 첫 출현 기준(r1 Too many elements)
      var vp = bodyViewport(t);
      var r = t.getRect(f.first);
      // 시작 정렬: rect top 을 표시 영역 top+4 에 / 끝 정렬: rect bottom 을 표시 영역 bottom−4 에
      final delta = end ? r.bottom - (vp.bottom - 4) : r.top - (vp.top + 4);
      pos.jumpTo((pos.pixels + delta).clamp(pos.minScrollExtent, pos.maxScrollExtent));
      await _settle(t, rounds: 2);
      vp = bodyViewport(t);
      r = t.getRect(f.first);
      return (vp: vp, r: r, off: pos.pixels);
    }
    bool inV(Rect r, Rect vp) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5;
    Map<String, Object?> cond(String state) => {
          'screen': 'ContractSignScreen(role worker, pendingWorker) + root overlay', 'theme': 'RoleTheme.workerTheme', 'viewport': '320x640',
          'dpr': 1.0, 'textScaler': 2.0, 'mq': mq(t), 'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록',
          'data': 'contractLong(ctL) — 구현40 과 같은 자료', 'prefs': 'setMockInitialValues({})',
          'clock': '본문 끝 날짜 = contractDate(createdAt 2026-10-17) KST — 실행 시계 무관', 'state': state};
    // ① 긴 값 — 각 값 Text 전체(처음·끝)가 표시 영역 안
    final values = {
      '사업장명': '[QA] 아주 긴 이름의 강남 물류센터 평택 2공장',
      '근로자명': '아주긴이름의지원자홍길동',
      '소재지/근무장소': '경기도 평택시 포승읍 평택항만길 123 물류단지 B동 2층',
      '업무': '냉장 피킹·검수 보조',
    };
    var shot = 0;
    for (final e in values.entries) {
      final f = findVisibleTextContaining(e.value);
      expect(f, findsWidgets, reason: e.key);
      final a = await align(f, end: false);
      final ok = inV(a.r, a.vp);
      log.add('value ${e.key} rect=${a.r} viewport=${a.vp} offset=${a.off.toStringAsFixed(1)} 전체보임=$ok');
      expect(ok, isTrue, reason: '${e.key} 값 처음·끝이 표시 영역 안');
      shot++;
      await vqCapture(t, key, 'B2-C-B-READ_1_value_${shot}_${e.key.replaceAll('/', '_')}', conditions: cond('${e.key} 값 전체 보임 offset=${a.off.toStringAsFixed(1)} rect=${a.r}'));
    }
    // ② 자유조항 — 제목+첫 문장(시작 정렬) / 마지막 문장 끝(끝 정렬)
    // [DU335 시험 추종] 조항 제목 · 본문이 낱말 단위 표시 문자열이 됐다 — 보이는 글자 기준 finder(DU255)
    final title = findVisibleText('[QA] 특약 사항');
    final a1 = await align(title, end: false);
    final content = findVisibleTextContaining('[QA] 근무 중 안전화');
    final cr1 = t.getRect(content.first);
    log.add('article title=${a1.r} content=$cr1 viewport=${a1.vp} offset=${a1.off.toStringAsFixed(1)} 제목보임=${inV(a1.r, a1.vp)} 첫줄보임=${cr1.top >= a1.vp.top - 0.5 && cr1.top + 30 <= a1.vp.bottom}');
    expect(inV(a1.r, a1.vp), isTrue);
    await vqCapture(t, key, 'B2-C-B-READ_2_article_start', conditions: cond('자유조항 제목·첫 문장 offset=${a1.off.toStringAsFixed(1)}'));
    final a2 = await align(content, end: true);
    log.add('article end content=${a2.r} viewport=${a2.vp} offset=${a2.off.toStringAsFixed(1)} 끝보임=${a2.r.bottom <= a2.vp.bottom + 0.5 && a2.r.bottom >= a2.vp.top}');
    expect(a2.r.bottom <= a2.vp.bottom + 0.5 && a2.r.bottom > a2.vp.top, isTrue, reason: '마지막 문장 끝이 표시 영역 안');
    await vqCapture(t, key, 'B2-C-B-READ_3_article_end', conditions: cond('자유조항 마지막 문장 끝(끝 정렬) offset=${a2.off.toStringAsFixed(1)} content=${a2.r}'));
    // ③ 본문 날짜 + 갑/을 서명란
    final date = find.text('2026년 10월 17일');
    expect(date, findsOneWidget);
    final a3 = await align(date, end: false);
    final gap = t.getRect(find.text('사업주 (갑)'));
    final eul = t.getRect(find.text('근로자 (을)'));
    log.add('date=${a3.r} 갑=$gap 을=$eul viewport=${a3.vp} offset=${a3.off.toStringAsFixed(1)} 날짜보임=${inV(a3.r, a3.vp)} 갑보임=${inV(gap, a3.vp)} 을보임=${inV(eul, a3.vp)}');
    expect(inV(a3.r, a3.vp), isTrue, reason: '날짜가 고정 안내 아래 표시 영역 안');
    await vqCapture(t, key, 'B2-C-B-READ_4_date_signblocks', conditions: cond('본문 날짜·서명란 offset=${a3.off.toStringAsFixed(1)} date=${a3.r} 갑=$gap 을=$eul'));
    expect(_calls, 0);
    // ignore: avoid_print
    for (final l in log) { print(l); }
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
  });

  // ── [DU1 후속42 §2] B2-C-B-READ2 — READ 승계 뒤 남은 행: 근로자 성명·담당 업무·근무 장소(소재지와 별도 행) label↔값,
  //   갑/을 서명란 label + 사람 표시 전문. 행 단위(_InfoRow / _SignBlock 위젯) 전체 rect 를 표시 영역 안에 두고 잰다. writer 미진입.
  testWidgets('B2-C-B-READ2 계약 320×640@2.0 — 근로자 성명·담당 업무·근무 장소 행 · 갑/을 서명란 전문(writer 0)', (t) async {
    final overflows = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final m = d.exceptionAsString();
      if (m.contains('overflowed')) {
        overflows.add(m.split('\n').first);
      } else {
        prev?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prev);
    final svc = _service();
    final key = await b2cPump(t, svc, const Size(320, 640), 2.0);
    final log = <String>['B2-C-B-READ2 ${mq(t)}'];
    final pos = _body(t);
    Finder rowOf(String label, String typeName) => find.ancestor(
        of: findVisibleText(label), matching: find.byWidgetPredicate((w) => w.runtimeType.toString() == typeName)).first;
    Future<({Rect vp, Rect r, double off})> showWhole(Finder row) async {
      await scrollBodyTo(t, row);
      var vp = bodyViewport(t);
      var r = t.getRect(row);
      pos.jumpTo((pos.pixels + (r.top - (vp.top + 4))).clamp(pos.minScrollExtent, pos.maxScrollExtent));
      await _settle(t, rounds: 2);
      vp = bodyViewport(t);
      r = t.getRect(row);
      return (vp: vp, r: r, off: pos.pixels);
    }
    bool inV(Rect r, Rect vp) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5;
    Map<String, Object?> cond(String state) => {
          'screen': 'ContractSignScreen(role worker, pendingWorker) + root overlay', 'theme': 'RoleTheme.workerTheme', 'viewport': '320x640',
          'dpr': 1.0, 'textScaler': 2.0, 'mq': mq(t), 'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록',
          'data': 'contractLong(ctL) — 구현40/41 과 같은 자료', 'prefs': 'setMockInitialValues({})',
          'clock': '본문 끝 날짜 = contractDate(createdAt 2026-10-17) KST — 실행 시계 무관', 'state': state};
    final rows = <(String, String, String)>[
      ('근로자 성명', '아주긴이름의지원자홍길동', '_InfoRow'),
      ('근무 장소', '경기도 평택시 포승읍 평택항만길 123 물류단지 B동 2층', '_InfoRow'),
      ('담당 업무', '냉장 피킹·검수 보조', '_InfoRow'),
      ('사업주 (갑)', '사업주', '_SignBlock'),
      ('근로자 (을)', '아주긴이름의지원자홍길동', '_SignBlock'),
    ];
    var i = 0;
    for (final (label, value, type) in rows) {
      final row = rowOf(label, type);
      final a = await showWhole(row);
      // [r3] 값은 **정확히 같은** 문자열(r2: '사업주' 가 레이블 '사업주 (갑)' 에 부분 일치했다)
      final valueInRow = find.descendant(of: row, matching: findVisibleText(value));
      final hasValue = valueInRow.evaluate().isNotEmpty;
      final vr = hasValue ? t.getRect(valueInRow.first) : Rect.zero;
      // [r3] 서명란은 표시 영역보다 키가 크다(을 337.6 > 272.5) — 레이블 위치(블록 top 정렬)와 사람 표시 전문 위치를 따로 잰다
      var nameOff = a.off;
      var nameR = vr;
      if (type == '_SignBlock' && hasValue && !inV(vr, a.vp)) {
        pos.jumpTo((pos.pixels + (vr.bottom - (a.vp.bottom - 4))).clamp(pos.minScrollExtent, pos.maxScrollExtent));
        await _settle(t, rounds: 2);
        nameOff = pos.pixels;
        nameR = t.getRect(valueInRow.first);
        log.add('  └ "$label" 사람 표시 전문 정렬 nameRect=$nameR offset=${nameOff.toStringAsFixed(1)} 보임=${inV(nameR, bodyViewport(t))}');
        // ignore: avoid_print
        print(log.last);
        await vqCapture(t, key, 'B2-C-B-READ2_${i + 1}b_${label.replaceAll(' ', '').replaceAll('(', '').replaceAll(')', '')}_name',
            conditions: cond('$label 사람 표시 전문 offset=${nameOff.toStringAsFixed(1)} name=$nameR'));
        pos.jumpTo(a.off);
        await _settle(t, rounds: 2);
      }
      final labelR = t.getRect(findVisibleText(label).first);
      final ok = type == '_SignBlock'
          ? inV(labelR, a.vp) && hasValue && inV(nameR, bodyViewport(t))
          : inV(a.r, a.vp) && hasValue && inV(vr, a.vp);
      log.add('row "$label" type=$type rowRect=${a.r} value="$value" valueRect=$vr viewport=${a.vp} offset=${a.off.toStringAsFixed(1)} 행전체보임=${inV(a.r, a.vp)} 값보임=${hasValue && inV(vr, a.vp)}');
      // ignore: avoid_print
      print(log.last); // [r2] 실패해도 측정값이 남게 즉시 출력
      expect(ok, isTrue, reason: '$label 행(label+값 전문)이 표시 영역 안');
      i++;
      await vqCapture(t, key, 'B2-C-B-READ2_${i}_${label.replaceAll(' ', '').replaceAll('(', '').replaceAll(')', '')}',
          conditions: cond('$label 행 전체 offset=${a.off.toStringAsFixed(1)} row=${a.r} value=$vr'));
    }
    // 소재지 행과 근무 장소 행은 다른 행(같은 주소 문자열)
    final so = rowOf('소재지', '_InfoRow');
    final ga = rowOf('근무 장소', '_InfoRow');
    log.add('소재지행≠근무장소행 ${t.element(so) != t.element(ga)}');
    expect(t.element(so) != t.element(ga), isTrue);
    expect(_calls, 0);
    FlutterError.onError = prev;
    // ignore: avoid_print
    for (final l in log) { print(l); }
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
  });

  for (final c in const [(id: 'B2-C-A', w: 392.0, h: 844.0, s: 1.0), (id: 'B2-C-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 계약 서명 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 첫 화면→조항→본문 끝→수동 동의→방법 선택→패드(빈→그리기→지우기→재입력→취소) · writer 0', (t) async {
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          overflows.add(m.split('\n').first);
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);
      final svc = _service();
      final size = Size(c.w, c.h);
      final key = await b2cPump(t, svc, size, c.s);
      final log = <String>['${c.id} ${mq(t)}'];
      Map<String, Object?> cond(String state) => {
            'screen': 'ContractSignScreen(role worker, pendingWorker) + root overlay', 'theme': 'RoleTheme.workerTheme',
            'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s, 'mq': mq(t),
            'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록 — 기기 글꼴 아님',
            'data': '_contractLong(ctL): 사업장 [QA] 아주 긴 이름의 강남 물류센터 평택 2공장 · 근로자 아주긴이름의지원자홍길동 · 업무 냉장 피킹·검수 보조 · 주소 긴 문자열 · [QA] 특약 사항 1조 · createdAt 2026-10-17 · 저장서명=합성 1x1 PNG',
            'prefs': 'setMockInitialValues({})', 'clock': '본문 끝 날짜 = contractDate(createdAt 2026-10-17) KST — 실행 시계 무관(후속41 정정)', 'state': state};

      // ① 첫 화면 — 잠금
      final vp = bodyViewport(t);
      expect(find.text(_hintBefore), findsOneWidget);
      expect(_button(t).onPressed, isNull);
      log.add('top bodyViewport=$vp');
      await vqCapture(t, key, '${c.id}_1_top', conditions: cond('첫 화면 offset 0 · 읽기 전 잠금'));
      // ② 자유조항 처음·끝
      // [DU335 시험 추종] 조항 제목 · 본문 낱말 단위 표시 문자열 — 보이는 글자 기준 finder(DU255)
      await scrollBodyTo(t, findVisibleText('[QA] 특약 사항'));
      final art = findVisibleTextContaining('[QA] 근무 중 안전화');
      await scrollBodyTo(t, art);
      log.add('article title/content=${t.getRect(art.first)} offset=${_body(t).pixels.toStringAsFixed(1)}');
      await vqCapture(t, key, '${c.id}_2_article', conditions: cond('자유조항 도달 offset=${_body(t).pixels.toStringAsFixed(1)}'));
      // ③ 본문 끝: 날짜·쌍방 서명란·동의 — 자동 체크 없음
      await scrollBodyTo(t, find.text('근로자 (을)'));
      log.add('signBlocks 갑=${t.getRect(find.text('사업주 (갑)'))} 을=${t.getRect(find.text('근로자 (을)'))} offset=${_body(t).pixels.toStringAsFixed(1)}');
      final consent = findVisibleText(_consent);
      await scrollBodyTo(t, consent);
      _body(t).jumpTo(_body(t).maxScrollExtent);
      await _settle(t, rounds: 3);
      expect(find.text(_hintAfter), findsOneWidget);
      expect(_checked(t), isFalse, reason: '자동 체크 없음');
      final consentBox = find.byKey(const ValueKey('contract-consent-section'));
      final cr = t.getRect(consentBox);
      final vp2 = bodyViewport(t);
      log.add('consent section=$cr bodyViewport=$vp2 inside=${cr.top >= vp2.top - 0.5 && cr.bottom <= vp2.bottom + 0.5}');
      await t.tap(consent);
      await _settle(t, rounds: 2);
      expect(_checked(t), isTrue);
      expect(_button(t).onPressed, isNotNull, reason: '수동 동의 후 CTA 활성');
      final cta = btnOf(_signLabel, ElevatedButton);
      final ctaR = t.getRect(cta);
      final rp = t.renderObject<RenderParagraph>(findVisibleText(_signLabel));
      log.add('CTA labelColor=${rp.text.style?.color} (렌더된 글자색)');
      await _settle(t, rounds: 10);
      log.add('CTA labelColor+1s=${t.renderObject<RenderParagraph>(findVisibleText(_signLabel)).text.style?.color}');
      log.add('CTA=$ctaR h=${ctaR.height.toStringAsFixed(1)} hitCenter=${hits(t, cta, ctaR.center)} overlapsBody=${ctaR.top < vp2.bottom - 0.5}');
      expect(hits(t, cta, ctaR.center), isTrue);
      await vqCapture(t, key, '${c.id}_3_end_consented', conditions: cond('본문 끝·수동 동의 후 offset=${_body(t).pixels.toStringAsFixed(1)} CTA=$ctaR'));
      // ④ 방법 선택 시트 (저장된 서명으로 서명 은 누르지 않음)
      await t.tap(cta);
      await _settle(t, rounds: 6);
      final saved = btnOf('저장된 서명으로 서명', ElevatedButton);
      final draw = btnOf('새 서명 그리기', TextButton);
      final sr = t.getRect(saved), dr = t.getRect(draw);
      log.add('method saved=$sr h=${sr.height.toStringAsFixed(1)} hit=${hits(t, saved, sr.center)} draw=$dr h=${dr.height.toStringAsFixed(1)} hit=${hits(t, draw, dr.center)}');
      expect(sr.bottom <= c.h && dr.bottom <= c.h, isTrue, reason: '두 행동 화면 안');
      await vqCapture(t, key, '${c.id}_4_method_sheet', conditions: cond('서명 방법 선택 시트'));
      // ⑤ 패드 — 빈 상태
      await t.tap(draw);
      await _settle(t, rounds: 8);
      expect(find.text('여기에 서명'), findsOneWidget, reason: 'placeholder');
      final clear = btnOf('지우기', TextButton);
      final done = btnOf('서명 완료', ElevatedButton);
      final cancel = btnOf('취소', OutlinedButton);
      // [후속40 after r2] 아이콘(20×20)이 아니라 실제 누르는 IconButton 외곽을 잰다(after r1 은 Icon rect 였다)
      final close = find.ancestor(of: find.byIcon(Icons.close).last, matching: find.byType(IconButton)).first;
      expect(t.widget<TextButton>(clear).onPressed, isNull);
      expect(t.widget<ElevatedButton>(done).onPressed, isNull);
      final canvas = find.byType(Signature);
      final cv = t.getRect(canvas);
      String r(Finder f) { final x = t.getRect(f); return '$x(${x.width.toStringAsFixed(1)}×${x.height.toStringAsFixed(1)}) hit=${hits(t, f, x.center)} inView=${x.top >= 0 && x.bottom <= c.h && x.left >= 0 && x.right <= c.w}'; }
      log.add('pad canvas=$cv close=${r(close)} clear=${r(clear)} cancel=${r(cancel)} done=${r(done)}');
      await vqCapture(t, key, '${c.id}_5_pad_empty', conditions: cond('패드 빈 상태'));
      // ⑥ 손가락 선 입력(canvas 안 합성 drag)
      Future<void> drawLine() async {
        final g = await t.startGesture(Offset(cv.left + cv.width * 0.2, cv.top + cv.height * 0.6));
        for (var i = 1; i <= 10; i++) {
          await g.moveTo(Offset(cv.left + cv.width * (0.2 + 0.06 * i), cv.top + cv.height * (0.6 - 0.03 * i)));
          await t.pump(const Duration(milliseconds: 16));
        }
        await g.up();
        await _settle(t, rounds: 3);
      }
      await drawLine();
      expect(find.text('여기에 서명'), findsNothing, reason: '그리면 placeholder 사라짐');
      expect(t.widget<TextButton>(clear).onPressed, isNotNull);
      expect(t.widget<ElevatedButton>(done).onPressed, isNotNull, reason: '완료 활성(누르지 않음)');
      log.add('drawn done=${r(done)} clear=${r(clear)}');
      await vqCapture(t, key, '${c.id}_6_pad_drawn', conditions: cond('패드 선 입력 후(완료 활성·누르지 않음)'));
      // ⑦ 지우기 → 빈 상태 → 재입력
      await t.tap(clear);
      await _settle(t, rounds: 3);
      expect(find.text('여기에 서명'), findsOneWidget, reason: '지우기 → placeholder');
      expect(t.widget<ElevatedButton>(done).onPressed, isNull);
      await drawLine();
      expect(t.widget<ElevatedButton>(done).onPressed, isNotNull);
      // ⑧ 취소 → 계약 화면 유지·CTA 잠금 해제·서명 호출 0
      await t.tap(cancel);
      await _settle(t, rounds: 8);
      expect(find.byType(Signature), findsNothing, reason: '패드 닫힘');
      expect(find.byType(ContractSignScreen), findsOneWidget);
      expect(_button(t).onPressed, isNotNull, reason: '취소 뒤 잠금 해제');
      expect(_calls, 0, reason: 'worker 서명 호출 0');
      log.add('cancel ok calls=$_calls');
      // ignore: avoid_print
      for (final l in log) { print(l); }
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
    });
  }
}
