// ignore_for_file: depend_on_referenced_packages
// [DU1 후속95 · 구현97 연결] S033 WorkTypeDetailScreen — 같은 BUSINESS_ADMIN·같은 활성 피킹 업무(구현93/94 fixture 원문)에서
//   실제 수정 아이콘 탭 → 본문 실제 drag 로 준비사항까지 → 준비사항 TextField 보이는 위치 실제 탭(포커스) →
//   LOCAL 합성 키보드(viewInsets.bottom 300, padding 하 0) → 같은 포커스로 본문 drag 해 마지막 저장까지(누르지 않음).
//   허용 action: host 진입·edit 탭·본문 drag·준비사항 포커스/시험 키보드뿐. enterText·환경 변경·사진·저장·취소·뒤로·홈/알림 없음.
//   합성 300 은 시험 조건이며 기기 IME 성공이 아니다. Firestore 10 op·Functions 1채널 막고 계수(0 단언) — Storage 등 미계측.
//   [후속95 §8] 입력란 안쪽 scroll 은 마지막 관측값이 아니라 **프레임별 누적 max** 로 단언한다.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_work_type_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/work_type_detail_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p', storageBucket: 'p.appspot.com');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

// 구현94 fixture 원문 그대로(work/du94-implementation/src/du1_s033_work_type_edit_visual_test.final.dart:45~56)
const _precautions = '작업 중에는 안전화를 꼭 착용해 주세요. 현장 입구에서 출입 명부를 작성합니다.\n'
    '휴게 시간에는 지정된 휴게실만 이용할 수 있으며, 작업장 안에서는 음식물 섭취가 금지됩니다.';
const _intro = '상품을 찾아 바구니에 담는 업무입니다';
const _description = '주문서에 적힌 상품을 창고 선반에서 찾아 바구니에 담고 포장 구역으로 옮깁니다. 처음 오신 분도 현장 담당자가 동선을 안내해 드립니다.';
const _requirements = '오래 서서 걷는 일이 가능하신 분, 18세 이상';
const _duties = '주문 상품 피킹, 바구니 운반, 빈 바구니 정리';

BusinessWorkTypeModel _wt() => BusinessWorkTypeModel(
      id: 'wt1', businessId: 'biz1', name: '피킹', icon: '📦', displayOrder: 0, isActive: true,
      createdAt: DateTime(2026, 1, 1), oneLineIntro: _intro, description: _description,
      workEnvironment: '실내(상온)', requirements: _requirements, duties: _duties, precautions: _precautions);

const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('S033-K 업무 수정 준비사항 포커스·합성 키보드 300 392×851@1.0 — 실제 drag·저장 receiver·원문 미변경', (t) async {
    const id = 'S033-K_work_type_edit_keyboard_392x1';
    await t.runAsync(vqLoadFonts);
    SharedPreferences.setMockInitialValues({});
    final calls = <String, int>{};
    void inc(String k) => calls[k] = (calls[k] ?? 0) + 1;
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMessageHandler(fnChannel, (msg) async {
      inc('functions');
      return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'blocked', <String, Object?>{'code': 'not-found'}]);
    });
    for (final op in const ['documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate',
      'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$fsBase.$op', (msg) async {
        inc('firestore $op');
        return null;
      });
    }
    t.view.physicalSize = const Size(392, 851);
    t.view.devicePixelRatio = 1.0;
    t.view.padding = const FakeViewPadding(top: 30, bottom: 24);
    t.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
    addTearDown(t.view.reset);
    final overflows = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.exceptionAsString();
      if (s.contains('overflowed')) {
        overflows.add(s.split('\n').first);
      } else {
        prev?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prev);
    final key = GlobalKey();
    final owner = UserModel(
        uid: 'owner1', username: 'owner1', name: 'QA 사장', email: 'owner1@alfit.local',
        role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const ['biz1']);
    final up = UserProvider()..debugSetCurrentUser(owner);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: up),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.getThemeByRole('BUSINESS_ADMIN'),
          builder: (ctx, child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
          home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => WorkTypeDetailScreen(workType: _wt(), initialEditMode: false))),
              child: const Text('host'))))),
        ),
      ),
    ));
    await t.tap(find.text('host'));
    for (var i = 0; i < 14; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // 진입 전: 비편집 → 실제 수정 아이콘 탭
    expect(find.descendant(of: find.byType(AppBar), matching: findVisibleText('업무 상세')), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    final editBtn = find.ancestor(of: find.byIcon(Icons.edit), matching: find.byType(IconButton)).first;
    await t.tapAt(t.getRect(editBtn).center);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.descendant(of: find.byType(AppBar), matching: findVisibleText('업무 수정')), findsOneWidget, reason: '편집 진입 제목');
    expect(find.byIcon(Icons.close), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsNothing);

    final screen = find.byType(WorkTypeDetailScreen);
    bool hits(Finder f, Offset p) {
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => e.target == t.renderObject(f));
    }
    // 본문 owner: TextField 밖의 세로 Scrollable 중 가장 큰 것
    Finder bodyFinder() {
      final all = find.descendant(of: screen, matching: find.byType(Scrollable));
      final cands = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
          .where((f) =>
              t.state<ScrollableState>(f).position.axis == Axis.vertical &&
              find.ancestor(of: f, matching: find.byType(TextField)).evaluate().isEmpty)
          .toList()
        ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
      return cands.first;
    }
    final body = bodyFinder();
    final pos = t.state<ScrollableState>(body).position;
    final out = <String>[];
    // 준비사항 입력란(controller 원문으로 식별)
    final precTf = find.byWidgetPredicate((w) => w is TextField && w.controller?.text == _precautions);
    expect(precTf, findsOneWidget);
    final precEd = find.descendant(of: precTf, matching: find.byType(EditableText));

    // ① 키보드 닫힌 상태에서 본문 실제 drag 로 준비사항 입력란을 화면 안에 들인다
    var vp = t.getRect(body);
    var k0 = 0;
    while (k0 < 20) {
      final r = t.getRect(precTf);
      if (r.top >= vp.top + 8 && r.bottom <= vp.bottom - 8) break;
      await t.dragFrom(Offset(vp.left + 4, vp.center.dy), const Offset(0, -150));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      k0++;
    }
    final preRect = t.getRect(precTf);
    out.add('키보드 전 drag $k0회 → off=${pos.pixels.toStringAsFixed(1)} 준비사항 입력란 $preRect (본문 $vp 안)');
    // ② 입력란 보이는 위치 실제 탭(텍스트 영역 중심) → 포커스
    final edRect = t.getRect(precEd);
    final tapAt = Offset(edRect.center.dx, (edRect.top + 12).clamp(vp.top + 1, vp.bottom - 1));
    expect(hits(precEd, tapAt), isTrue, reason: '탭 지점이 준비사항 EditableText 위');
    await t.tapAt(tapAt);
    await t.pump();
    final focusNode = t.widget<EditableText>(precEd).focusNode;
    out.add('탭 $tapAt → focus=${focusNode.hasFocus} textInput 연결=${t.testTextInput.hasAnyClients} '
        'inputType=${(t.testTextInput.setClientArgs?['inputType'] as Map?)?['name']} inputAction=${t.testTextInput.setClientArgs?['inputAction']}');
    expect(focusNode.hasFocus, isTrue, reason: '준비사항 EditableText 포커스');
    expect(t.testTextInput.hasAnyClients, isTrue, reason: '입력 연결');
    // ③ LOCAL 합성 키보드: viewInsets 하 300, padding 하 0(키보드가 하단 인셋을 덮음), viewPadding 상30·하24 유지
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    t.view.padding = const FakeViewPadding(top: 30, bottom: 0);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    final mq = MediaQuery.of(t.element(screen));
    vp = t.getRect(body);
    const kb = Rect.fromLTRB(0, 851 - 300, 392, 851);
    out.add('mq padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} size=${mq.size} · 키보드 영역=$kb · 본문 viewport=$vp '
        '· max=${pos.maxScrollExtent.toStringAsFixed(1)} off=${pos.pixels.toStringAsFixed(1)} · focus=${focusNode.hasFocus}');
    expect(mq.viewInsets.bottom, 300, reason: '합성 키보드 300 이 MediaQuery 에 들어왔다');
    expect(vp.bottom <= kb.top + 0.5, isTrue, reason: '본문 viewport 가 키보드 위에서 끝난다(실측, 가정 아님)');
    expect(focusNode.hasFocus, isTrue, reason: '키보드 정착 뒤에도 포커스 유지');

    // 프레임 기록: 준비사항 입력란과 본문 교차·안쪽 scroll(누적 max)·포커스
    final innerMax = <String, double>{};
    final perFrame = <String>[];
    String frame(String when) {
      final parts = <String>[];
      final tf = find.descendant(of: screen, matching: find.byType(TextField));
      for (var i = 0; i < tf.evaluate().length; i++) {
        final w = t.widget<TextField>(tf.at(i));
        final r = t.getRect(tf.at(i));
        final v = r.intersect(vp);
        final inner = find.descendant(of: tf.at(i), matching: find.byType(Scrollable));
        final ip = inner.evaluate().isEmpty ? null : t.state<ScrollableState>(inner.first).position;
        final lbl = w.decoration?.labelText ?? w.decoration?.hintText?.split('\n').first ?? '-';
        if (v.height > 0 && ip != null) {
          final keyName = '$i:$lbl';
          innerMax[keyName] = (innerMax[keyName] ?? 0) > ip.maxScrollExtent ? innerMax[keyName]! : ip.maxScrollExtent;
          parts.add('TF[$lbl] 교차=${v.height.toStringAsFixed(0)}/${r.height.toStringAsFixed(0)} 안쪽max=${ip.maxScrollExtent.toStringAsFixed(1)} off=${ip.pixels.toStringAsFixed(1)}');
        }
      }
      final s = '$when off=${pos.pixels.toStringAsFixed(1)}/${pos.maxScrollExtent.toStringAsFixed(1)} focus=${focusNode.hasFocus} kb=${MediaQuery.of(t.element(screen)).viewInsets.bottom} · ${parts.join(' · ')}';
      perFrame.add(s);
      return s;
    }
    out.add(frame('키보드 정착'));
    await vqCapture(t, key, '${id}_focus', conditions: {
      'screen': 'WorkTypeDetailScreen(initialEditMode:false) → 실제 수정 아이콘 tapAt → 본문 drag → 준비사항 실제 탭(포커스) → 합성 키보드',
      'theme': "RoleTheme.getThemeByRole('BUSINESS_ADMIN')", 'viewport': '392x851', 'dpr': 1.0, 'textScaler': 1.0,
      'inset': 'viewPadding 상30·하24 · padding 상30·하0 · viewInsets 하300(LOCAL 합성 키보드, 기기 IME 아님)',
      'prefs': '{}', 'fonts': 'vqLoadFonts 근사', 'fixture': '구현94 동일 — 값 미변경', 'scroll': 'off ${pos.pixels.toStringAsFixed(1)}',
      'measure': out.join(' | ')});
    // ④ 같은 포커스로 본문 실제 drag → 마지막 저장까지
    var k = 0;
    final offs = <double>[pos.pixels];
    while (pos.pixels < pos.maxScrollExtent - 0.5 && k < 40) {
      await t.dragFrom(Offset(vp.left + 4, vp.center.dy), const Offset(0, -150));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      k++;
      offs.add(pos.pixels);
      out.add(frame('drag$k'));
      expect(focusNode.hasFocus, isTrue, reason: 'drag$k 에서 포커스가 닫히면 열린 키보드 성공으로 쓰지 않는다');
      if (k == 1) {
        await vqCapture(t, key, '${id}_mid', conditions: {
          'viewport': '392x851', 'textScaler': 1.0, 'inset': 'viewInsets 하300(합성)', 'scroll': '본문 실제 dragFrom(left+4,center) -150 × 1 · off ${pos.pixels.toStringAsFixed(1)}',
          'measure': out.last});
      }
    }
    final atEnd = (pos.pixels - pos.maxScrollExtent).abs() < 0.5;
    var maxStep = 0.0;
    for (var i = 1; i < offs.length; i++) {
      final d = offs[i] - offs[i - 1];
      if (d > maxStep) maxStep = d;
    }
    out.add('정착 offset=${offs.map((o) => o.toStringAsFixed(1)).join('/')} · 최대 이동 ${maxStep.toStringAsFixed(1)} < viewport ${vp.height.toStringAsFixed(1)} → 인접 프레임 중첩 ≥ ${(vp.height - maxStep).toStringAsFixed(1)}');
    // ⑤ 저장 receiver(누르지 않음)
    final save = find.ancestor(of: find.text('저장'), matching: find.byType(InkWell)).first;
    final rs = t.getRect(save);
    final saveHit = hits(save, rs.center);
    final saveIn = rs.top >= vp.top - 0.5 && rs.bottom <= vp.bottom + 0.5;
    out.add('저장 InkWell $rs ${rs.width.toStringAsFixed(1)}×${rs.height.toStringAsFixed(1)} hit=$saveHit 키보드 위 본문 안=$saveIn (kb.top=${kb.top})');
    // 머리 receiver(바깥 IconButton)
    final appBarButtons = find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton));
    for (var i = 0; i < appBarButtons.evaluate().length; i++) {
      final r = t.getRect(appBarButtons.at(i));
      out.add('AppBar IconButton[$i] $r hit=${hits(appBarButtons.at(i), r.center)}');
      expect(r.width >= 48 - 0.01 && r.height >= 48 - 0.01 && hits(appBarButtons.at(i), r.center), isTrue, reason: 'AppBar receiver[$i]');
    }
    // ⑥ 값 미변경 · 근무환경 선택값 · PopScope(관찰만)
    final texts = t.widgetList<TextField>(find.descendant(of: screen, matching: find.byType(TextField))).map((w) => w.controller?.text ?? '').toList();
    final selectedEnv = t.widgetList<ChoiceChip>(find.byType(ChoiceChip)).where((c) => c.selected).map((c) => (c.label as Text).data).toList();
    // r1: find.byType(PopScope) 는 제네릭 runtimeType(PopScope<Object?>)과 맞지 않아 0건(null) — 술어로 찾는다
    final pop = find.descendant(of: screen, matching: find.byWidgetPredicate((w) => w is PopScope));
    final canPop = pop.evaluate().isEmpty ? null : (t.widget(pop.first) as PopScope).canPop;
    out.add('controller 원문 5개 일치=${[_intro, _description, _precautions, _requirements, _duties].every(texts.contains)} · 선택 환경=$selectedEnv · PopScope.canPop=$canPop(관찰만, dirty 판정 아님)');
    out.add('입력란 안쪽 scroll 누적 max: $innerMax');
    out.add('말단=$atEnd drag=$k · calls=$calls · overflows=${overflows.length}');
    for (final l in out) {
      // ignore: avoid_print
      print('$id $l');
    }
    for (final v in [_intro, _description, _precautions, _requirements, _duties]) {
      expect(texts.contains(v), isTrue, reason: '원문 미변경: ${v.substring(0, 8)}…');
    }
    expect(selectedEnv, ['실내(상온)'], reason: '근무환경 선택값 미변경');
    expect(atEnd || pos.maxScrollExtent < 0.5, isTrue, reason: '말단');
    expect(maxStep < vp.height, isTrue, reason: '인접 프레임 중첩');
    expect(saveIn && saveHit && rs.height >= 52 - 0.01 && rs.width >= 48, isTrue, reason: '저장 receiver 52·hit·키보드 위 보임');
    expect(innerMax.isNotEmpty, isTrue);
    for (final e in innerMax.entries) {
      expect(e.value, lessThanOrEqualTo(0.5), reason: '입력란 "${e.key}" 안쪽 scroll 누적 max(모든 관측 프레임)');
    }
    expect(calls, isEmpty, reason: 'Firestore·Functions 0');
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await vqCapture(t, key, '${id}_end', conditions: {
      'viewport': '392x851', 'textScaler': 1.0, 'inset': 'viewInsets 하300(합성)', 'scroll': '본문 실제 drag → 말단 off ${pos.pixels.toStringAsFixed(1)}',
      'measure': out.sublist(out.length - 6).join(' | ')});
  });
}
