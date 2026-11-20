// ignore_for_file: depend_on_referenced_packages
// [DU1 후속94] S033 WorkTypeDetailScreen — 동일 BUSINESS_ADMIN·동일 활성 피킹 업무(구현93 fixture 그대로)에서 **실제 수정 아이콘 탭**으로 편집 진입 직후,
//   값 미변경·키보드 닫힘 정상 편집 N.
//   host: LOCAL dummy route → 일반 MaterialPageRoute 로 WorkTypeDetailScreen(workType: fixture, initialEditMode: false) — 실제 목록/auth/read 아님.
//   권한: UserProvider()..debugSetCurrentUser(owner). 진입 전 edit 있음/close 없음, 진입 뒤 제목 '업무 수정'·close 있음/edit 없음 단언.
//   본문 owner: TextField 안 Scrollable 을 제외한 세로 Scrollable(가장 큰 것) — `.first` 를 그대로 쓰지 않는다.
//   Firestore 10 op·Functions 막고 계수(0 단언) — Storage 등 그 밖 채널 미계측. 허용 action 은 edit 탭 1회뿐(저장·취소·사진·환경 변경·홈/알림/뒤로 없음).
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

// 구현93 fixture 원문 그대로(E93 src/du1_s033_work_type_detail_visual_test.run.dart:46~67)
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

// [구현94] N(392×851@1.0, 상30/하24) · B(320×640@2.0, inset 0) 공용 셀
Future<void> _cell(WidgetTester t, {required String id, required Size size, required double scale, required bool insets, required double dragDy}) async {
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
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1.0;
    if (insets) {
      t.view.padding = const FakeViewPadding(top: 30, bottom: 24);
      t.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
    }
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
    final wt = _wt();
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
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                  builder: (_) => WorkTypeDetailScreen(workType: wt, initialEditMode: false))),
              child: const Text('host'))))),
        ),
      ),
    ));
    await t.tap(find.text('host'));
    for (var i = 0; i < 14; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    // 진입 전: 비편집
    // r1: '업무 상세' 는 머리 제목과 본문 섹션 제목 두 곳 — 머리(AppBar) 안에서만 본다
    // run4 B: 좁은 폭·2배 글자에선 AppPageScaffold 가 제목을 bar 아래(_TitleBelow, keepWords 결합자)로 옮긴다 — 보이는 글자로 찾는다
    expect(find.descendant(of: find.byType(AppBar), matching: findVisibleText('업무 상세')), findsOneWidget);
    expect(find.byIcon(Icons.edit), findsOneWidget);
    expect(find.byIcon(Icons.close), findsNothing);
    // 실제 수정 아이콘 탭(허용 action 1회)
    final editBtn = find.ancestor(of: find.byIcon(Icons.edit), matching: find.byType(IconButton)).first;
    await t.tapAt(t.getRect(editBtn).center);
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull);
    final editTitle = find.descendant(of: find.byType(AppBar), matching: findVisibleText('업무 수정'));
    expect(editTitle, findsOneWidget, reason: '편집 진입 제목');
    final titleRect = t.getRect(editTitle);
    final titleH = (t.renderObject(editTitle) as RenderBox).size.height;
    expect(find.byIcon(Icons.close), findsOneWidget, reason: '취소 아이콘');
    expect(find.byIcon(Icons.edit), findsNothing, reason: '수정 아이콘 사라짐');
    final screen = find.byType(WorkTypeDetailScreen);
    final mq = MediaQuery.of(t.element(screen));
    bool hits(Finder f, Offset p) {
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => e.target == t.renderObject(f));
    }
    // 본문 owner: TextField 밖의 세로 Scrollable 중 가장 큰 것
    final allScroll = find.descendant(of: screen, matching: find.byType(Scrollable));
    final cands = [
      for (var i = 0; i < allScroll.evaluate().length; i++) allScroll.at(i)
    ].where((f) =>
        t.state<ScrollableState>(f).position.axis == Axis.vertical &&
        find.ancestor(of: f, matching: find.byType(TextField)).evaluate().isEmpty).toList()
      ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
    final scroll = cands.first;
    final pos = t.state<ScrollableState>(scroll).position;
    final vp = t.getRect(scroll);
    final out = <String>[
      'mq padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} size=${mq.size} (키보드 닫힘 = viewInsets.bottom ${mq.viewInsets.bottom})',
      '편집 제목 "업무 수정" rect=$titleRect h=${titleH.toStringAsFixed(1)} AppBar=${t.getRect(find.byType(AppBar))}',
      '세로 Scrollable 총 ${allScroll.evaluate().length}개 · TextField 밖 후보 ${cands.length} · 본문 $vp max=${pos.maxScrollExtent.toStringAsFixed(1)} off=${pos.pixels.toStringAsFixed(1)}',
    ];
    // TextField 값·rect·내부 scroll(표시 범위) — 값은 바꾸지 않는다
    // [구현94] 입력란별 안쪽 scroll 최대값(프레임 합집합) — 기존 값이 입력란 안쪽에 숨으면 > 0
    final innerMax = <String, double>{};
    String fields(String when) {
      final parts = <String>[];
      final tf = find.descendant(of: screen, matching: find.byType(TextField));
      for (var i = 0; i < tf.evaluate().length; i++) {
        final w = t.widget<TextField>(tf.at(i));
        final r = t.getRect(tf.at(i));
        final v = r.intersect(vp);
        if (v.height <= 0) continue;
        final inner = find.descendant(of: tf.at(i), matching: find.byType(Scrollable));
        final ip = inner.evaluate().isEmpty ? null : t.state<ScrollableState>(inner.first).position;
        final ed = find.descendant(of: tf.at(i), matching: find.byType(EditableText));
        final er = ed.evaluate().isEmpty ? Rect.zero : t.getRect(ed.first);
        final lbl = w.decoration?.labelText ?? w.decoration?.hintText?.split('\n').first ?? '-';
        if (ip != null) innerMax['$i:$lbl'] = ip.maxScrollExtent;
        parts.add('TF[${w.decoration?.labelText ?? w.decoration?.hintText?.split('\n').first ?? '-'}] "${(w.controller?.text ?? '').replaceAll('\n', '⏎')}" rect=$r 보임=${v.height.toStringAsFixed(0)}/${r.height.toStringAsFixed(0)} '
            '입력영역=${er.height.toStringAsFixed(0)} 내부scroll max=${ip?.maxScrollExtent.toStringAsFixed(1)} off=${ip?.pixels.toStringAsFixed(1)} maxLines=${w.maxLines}');
      }
      return '$when TextField ${parts.length}: ${parts.join(' · ')}';
    }
    String visible(String when) {
      final parts = <String>[];
      for (final e in find.descendant(of: screen, matching: find.byType(Text)).evaluate()) {
        final w = e.widget as Text;
        final s = (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll('⁠', '');
        if (s.trim().isEmpty) continue;
        final box = e.renderObject as RenderBox;
        final r = box.localToGlobal(Offset.zero) & box.size;
        final v = r.intersect(vp);
        if (v.width > 0 && v.height > 0) {
          parts.add('"${s.replaceAll('\n', '⏎')}"(${v.height.toStringAsFixed(0)}/${r.height.toStringAsFixed(0)})');
        }
      }
      return '$when off=${pos.pixels.toStringAsFixed(1)} 보이는 글 ${parts.length}: ${parts.join(' ')}';
    }
    // 머리 행동
    final appBarButtons = find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton));
    for (var i = 0; i < appBarButtons.evaluate().length; i++) {
      final b = appBarButtons.at(i);
      final r = t.getRect(b);
      final icon = t.widget<IconButton>(b).icon;
      final ic = icon is Icon ? icon.icon : null;
      out.add('AppBar IconButton[$i] icon=${ic?.codePoint.toRadixString(16)} $r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} hit=${hits(b, r.center)}');
      expect(r.width >= 48 - 0.01 && r.height >= 48 - 0.01 && hits(b, r.center), isTrue, reason: 'AppBar receiver[$i]');
    }
    final bodyActs = <String, ({Rect r, bool hit, String when})>{};
    void actFrame(String when) {
      final f = find.descendant(of: scroll, matching: find.byWidgetPredicate((w) =>
          w is IconButton || w is ButtonStyleButton || w is ChoiceChip || w is FilterChip ||
          (w is InkWell && w.onTap != null) || (w is GestureDetector && w.onTap != null)));
      for (var i = 0; i < f.evaluate().length; i++) {
        final r = t.getRect(f.at(i));
        // r2: 버튼·칩·IconButton 안쪽 InkWell/GestureDetector 는 잉크(40)일 뿐 바깥 receiver 가 탭 영역(48)을 가진다 — 바깥만 receiver 로 센다
        final w0 = f.evaluate().elementAt(i).widget;
        if ((w0 is InkWell || w0 is GestureDetector) &&
            find.ancestor(of: f.at(i), matching: find.byWidgetPredicate((w) =>
                w is ButtonStyleButton || w is ChoiceChip || w is FilterChip || w is IconButton)).evaluate().isNotEmpty) {
          continue;
        }
        if (r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && r.width > 0) {
          final label = t.widgetList<Text>(find.descendant(of: f.at(i), matching: find.byType(Text))).map((x) => x.data ?? '').join('/');
          final k = '${f.evaluate().elementAt(i).widget.runtimeType}"$label"@${(r.top + pos.pixels).toStringAsFixed(0)}';
          bodyActs.putIfAbsent(k, () => (r: r, hit: hits(f.at(i), r.center), when: when));
        }
      }
    }
    out.add(visible('초기'));
    out.add(fields('초기'));
    actFrame('초기');
    await vqCapture(t, key, '${id}_top', conditions: {
      'screen': 'WorkTypeDetailScreen(initialEditMode:false) → 실제 수정 아이콘 tapAt 1회 → 편집 진입 직후 · dummy route(목록·auth 아님)',
      'theme': "RoleTheme.getThemeByRole('BUSINESS_ADMIN')", 'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'dpr': 1.0, 'textScaler': scale,
      'inset': insets ? '선언 padding/viewPadding top30 bottom24 · viewInsets 0' : '모두 0', 'prefs': '{}', 'fonts': 'vqLoadFonts 근사',
      'fixture': '구현93 동일 — 활성 피킹·준비사항 2문단·실내(상온)·사진 없음 · 값 미변경 · 키보드 닫힘', 'scroll': 'off 0',
      'measure': out.join(' | ')});
    var k = 0;
    while (pos.pixels < pos.maxScrollExtent - 0.5 && k < 60) {
      await t.dragFrom(Offset(vp.left + 4, vp.center.dy), Offset(0, -dragDy));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      k++;
      out.add(visible('drag$k'));
      out.add(fields('drag$k'));
      actFrame('drag$k');
      if (k == 2) {
        await vqCapture(t, key, '${id}_mid', conditions: {
          'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale, 'scroll': '본문 실제 dragFrom(left+4,center) -${dragDy.toInt()} × 2 · off ${pos.pixels.toStringAsFixed(1)}',
          'measure': out[out.length - 2]});
      }
    }
    final atEnd = (pos.pixels - pos.maxScrollExtent).abs() < 0.5;
    out.add('본문 조작 receiver: ${bodyActs.entries.map((e) => '${e.key} ${e.value.when} ${e.value.r} ${e.value.r.width.toStringAsFixed(1)}×${e.value.r.height.toStringAsFixed(1)} hit=${e.value.hit}').join(' · ')}');
    // 저장 — CommonWidgets.primaryButton(Container > InkWell)
    final saveTxt = find.text('저장');
    final save = find.ancestor(of: saveTxt, matching: find.byType(InkWell)).first;
    final rs = t.getRect(save);
    final saveHit = hits(save, rs.center);
    final saveIn = rs.top >= vp.top - 0.5 && rs.bottom <= vp.bottom + 0.5;
    out.add('저장 InkWell $rs ${rs.width.toStringAsFixed(1)}×${rs.height.toStringAsFixed(1)} hit=$saveHit inBodyViewport=$saveIn onTap=${t.widget<InkWell>(save).onTap == null ? 'null' : '활성'}');
    out.add('말단=$atEnd off=${pos.pixels.toStringAsFixed(1)} max=${pos.maxScrollExtent.toStringAsFixed(1)} drag=$k · calls=$calls · overflows=${overflows.length}');
    // 값 미변경(controller 원문 그대로)
    final texts = t.widgetList<TextField>(find.descendant(of: screen, matching: find.byType(TextField))).map((w) => w.controller?.text ?? '').toList();
    out.add('controller 값=${texts.map((s) => s.replaceAll('\n', '⏎')).toList()}');
    for (final l in out) {
      // ignore: avoid_print
      print('$id $l');
    }
    out.add('입력란 안쪽 scroll max: $innerMax');
    // ignore: avoid_print
    print('$id 입력란 안쪽 scroll max: $innerMax');
    expect(innerMax.length, 5, reason: '입력란 5개 모두 본문 표시 영역에 들어온 프레임이 있다');
    for (final e in innerMax.entries) {
      expect(e.value, lessThanOrEqualTo(0.5), reason: '입력란 "${e.key}" 기존 값이 안쪽 스크롤에 숨지 않는다');
    }
    for (final v in [_intro, _description, _requirements, _duties, _precautions]) {
      expect(texts.contains(v), isTrue, reason: '값 미변경: ${v.substring(0, 8)}…');
    }
    expect(mq.viewInsets.bottom, 0, reason: '키보드 닫힘');
    expect(atEnd || pos.maxScrollExtent < 0.5, isTrue, reason: '말단');
    expect(saveIn && saveHit && rs.height >= 52 - 0.01 && rs.width >= 48, isTrue, reason: '저장 receiver 52·hit·보임');
    for (final e in bodyActs.entries) {
      expect(e.value.r.width >= 48 - 0.01 && e.value.r.height >= 48 - 0.01, isTrue, reason: '본문 receiver 48: ${e.key}');
    }
    expect(calls, isEmpty, reason: 'Firestore·Functions 0');
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await vqCapture(t, key, '${id}_end', conditions: {
      'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'textScaler': scale, 'scroll': '본문 실제 drag → 말단 off ${pos.pixels.toStringAsFixed(1)}', 'measure': out[out.length - 4]});
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('S033-E 업무 수정 진입 직후 미변경 392×851@1.0 — 전체·실제 drag·저장 receiver', (t) async {
    await _cell(t, id: 'S033-E_work_type_edit_392x1', size: const Size(392, 851), scale: 1.0, insets: true, dragDy: 200);
  });

  testWidgets('S033-EB 업무 수정 진입 직후 미변경 320×640@2.0 — 연속 읽기·저장 receiver·overflow 0', (t) async {
    await _cell(t, id: 'S033-EB_work_type_edit_320x2', size: const Size(320, 640), scale: 2.0, insets: false, dragDy: 150);
  });

  // [구현94] 한 줄 소개는 표시만 감싸 늘어나고 입력은 한 줄 그대로인가 — 저장은 누르지 않는다(controller 값만 본다)
  testWidgets('S033-EI 한 줄 소개 입력 규칙 — 줄바꿈 제거·완료 키·50자 한도 유지', (t) async {
    final calls = <String, int>{};
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMessageHandler(fnChannel, (msg) async {
      calls['functions'] = (calls['functions'] ?? 0) + 1;
      return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'blocked', <String, Object?>{'code': 'not-found'}]);
    });
    for (final op in const ['documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate',
      'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$fsBase.$op', (msg) async {
        calls['firestore $op'] = (calls['firestore $op'] ?? 0) + 1;
        return null;
      });
    }
    SharedPreferences.setMockInitialValues({});
    t.view.physicalSize = const Size(392, 851);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final owner = UserModel(
        uid: 'owner1', username: 'owner1', name: 'QA 사장', email: 'owner1@alfit.local',
        role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const ['biz1']);
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>.value(value: UserProvider()..debugSetCurrentUser(owner)),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        theme: RoleTheme.getThemeByRole('BUSINESS_ADMIN'),
        home: WorkTypeDetailScreen(workType: _wt(), initialEditMode: true),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final intro = find.byWidgetPredicate((w) => w is TextField && w.decoration?.labelText == '한 줄 소개');
    expect(intro, findsOneWidget);
    final w = t.widget<TextField>(intro);
    await t.showKeyboard(intro);
    await t.pump();
    final args = t.testTextInput.setClientArgs ?? const {};
    final type = (args['inputType'] as Map?)?['name'];
    final action = args['inputAction'];
    await t.enterText(intro, '첫 줄\n둘째 줄');
    await t.pump();
    final afterNewline = w.controller!.text;
    await t.enterText(intro, '가' * 60);
    await t.pump();
    final afterLong = w.controller!.text.length;
    // ignore: avoid_print
    print('S033-EI keyboardType=${w.keyboardType} maxLines=${w.maxLines} minLines=${w.minLines} maxLength=${w.maxLength} '
        'formatters=${w.inputFormatters} · 플랫폼 설정 inputType=$type inputAction=$action · '
        '"첫 줄⏎둘째 줄" 입력 → "$afterNewline" · 60자 입력 → $afterLong자 · calls=$calls');
    expect(type, 'TextInputType.text', reason: '키보드 종류 = 한 줄 글자(줄바꿈 키 아님)');
    expect(action, 'TextInputAction.done', reason: '완료 키');
    expect(afterNewline, '첫 줄둘째 줄', reason: '붙여넣은 줄바꿈도 제거(maxLines 1 시절과 같음)');
    expect(afterLong, 50, reason: '50자 한도');
    expect(calls, isEmpty, reason: 'Firestore·Functions 0');
    expect(t.takeException(), isNull);
  });
}
