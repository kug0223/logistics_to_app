// ignore_for_file: depend_on_referenced_packages
// [DU1 후속93] S033 WorkTypeDetailScreen — BUSINESS_ADMIN(업무 관리 허용) · 활성 업무유형 · 준비사항 있음 · 사진 없음 · initialEditMode=false 정상 읽기 N.
//   host: LOCAL dummy route → 일반 MaterialPageRoute 로 WorkTypeDetailScreen(workType: fixture, initialEditMode: false)
//     (실제 설정→업무 관리→사업장 선택→목록→상세 경로·auth·read 성공 아님). Theme RoleTheme.getThemeByRole('BUSINESS_ADMIN').
//   권한: UserProvider()..debugSetCurrentUser(owner) — 내부 _currentUser 를 채워 p.can 이 production 계약대로 BUSINESS_ADMIN=true(수정 아이콘 표시).
//   Core fake(storageBucket — StorageService 필드가 FirebaseStorage.instance 를 잡는다). NotificationProvider(setUser 미호출).
//   Firestore 10 op·Functions 는 막고 계수(0 단언) — Storage 등 그 밖 채널 미계측.
//   fixture: 공개 BusinessWorkTypeModel — S012 준비사항 2문단·피킹 설명/자격/주요업무·실내(상온). thumbnailUrl/images null(사진 placeholder 범위).
//   수정/취소/저장/삭제/사진선택/홈/알림/뒤로는 누르지 않는다(hitTest 만).
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
import 'support/visible_text.dart'; // [DU320] 낱말 묶음 표시 문자를 보이는 글자로 찾는다(DU255)

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

const _precautions = '작업 중에는 안전화를 꼭 착용해 주세요. 현장 입구에서 출입 명부를 작성합니다.\n'
    '휴게 시간에는 지정된 휴게실만 이용할 수 있으며, 작업장 안에서는 음식물 섭취가 금지됩니다.';
const _intro = '상품을 찾아 바구니에 담는 업무입니다';
const _description = '주문서에 적힌 상품을 창고 선반에서 찾아 바구니에 담고 포장 구역으로 옮깁니다. 처음 오신 분도 현장 담당자가 동선을 안내해 드립니다.';
const _requirements = '오래 서서 걷는 일이 가능하신 분, 18세 이상';
const _duties = '주문 상품 피킹, 바구니 운반, 빈 바구니 정리';

BusinessWorkTypeModel _wt() => BusinessWorkTypeModel(
      id: 'wt1',
      businessId: 'biz1',
      name: '피킹',
      icon: '📦',
      displayOrder: 0,
      isActive: true,
      createdAt: DateTime(2026, 1, 1),
      oneLineIntro: _intro,
      description: _description,
      workEnvironment: '실내(상온)',
      requirements: _requirements,
      duties: _duties,
      precautions: _precautions,
    );

void main() {
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  const fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('S033-N 업무 상세 비편집 준비사항 392×851@1.0 — 전체·실제 drag·receiver', (t) async {
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
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(1.0)), child: child!),
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
    expect(t.takeException(), isNull);
    final screen = find.byType(WorkTypeDetailScreen);
    expect(screen, findsOneWidget);
    final mq = MediaQuery.of(t.element(screen));
    bool hits(Finder f, Offset p) {
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
      return hit.path.any((e) => e.target == t.renderObject(f));
    }
    final scroll = find.descendant(of: screen, matching: find.byType(Scrollable)).first;
    final pos = t.state<ScrollableState>(scroll).position;
    final vp = t.getRect(scroll);
    final out = <String>[
      'mq padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} size=${mq.size}',
      '본문 [${pos.axis.name}] $vp max=${pos.maxScrollExtent.toStringAsFixed(1)} off=${pos.pixels.toStringAsFixed(1)}',
      'provider isBusinessAdmin=${up.isBusinessAdmin} can(manageTo)=${up.can((p) => p.canManageTo)}',
      'fixture name=${wt.name} active=${wt.isActive} env=${wt.workEnvironment} thumb=${wt.thumbnailUrl} images=${wt.images}',
    ];
    final precSpans = <List<double>>[];
    double precH = 0;
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
          if (s == _precautions) {
            precH = r.height;
            precSpans.add([v.top - r.top, v.bottom - r.top]);
          }
          parts.add('"${s.replaceAll('\n', '⏎')}"(${v.height.toStringAsFixed(0)}/${r.height.toStringAsFixed(0)})');
        }
      }
      return '$when off=${pos.pixels.toStringAsFixed(1)} 보이는 글 ${parts.length}: ${parts.join(' ')}';
    }
    // 머리 행동(AppBar) — 뒤로·홈·알림·수정(BUSINESS_ADMIN 허용) / 취소(close) 없음
    final appBarButtons = find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton));
    for (var i = 0; i < appBarButtons.evaluate().length; i++) {
      final b = appBarButtons.at(i);
      final r = t.getRect(b);
      final icon = t.widget<IconButton>(b).icon;
      final ic = icon is Icon ? icon.icon : null;
      out.add('AppBar IconButton[$i] icon=${ic?.codePoint.toRadixString(16)} $r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} hit=${hits(b, r.center)}');
      expect(r.width >= 48 - 0.01 && r.height >= 48 - 0.01 && hits(b, r.center), isTrue, reason: 'AppBar receiver[$i]');
    }
    expect(find.byIcon(Icons.edit), findsOneWidget, reason: 'BUSINESS_ADMIN 수정 아이콘(production can 계약)');
    expect(find.byIcon(Icons.close), findsNothing, reason: '비편집 — 취소 아이콘 없음');
    final bodyActs = <String, String>{};
    void actFrame(String when) {
      final f = find.descendant(of: scroll, matching: find.byWidgetPredicate((w) => w is IconButton || w is ButtonStyleButton || (w is InkWell && w.onTap != null) || (w is GestureDetector && w.onTap != null)));
      for (var i = 0; i < f.evaluate().length; i++) {
        final r = t.getRect(f.at(i));
        if (r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && r.width > 0) {
          final label = t.widgetList<Text>(find.descendant(of: f.at(i), matching: find.byType(Text))).map((x) => x.data ?? '').join('/');
          final k = '${f.evaluate().elementAt(i).widget.runtimeType}"$label"@${(r.top + pos.pixels).toStringAsFixed(0)}';
          bodyActs.putIfAbsent(k, () => '$when $r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} hit=${hits(f.at(i), r.center)}');
        }
      }
    }
    out.add(visible('초기'));
    actFrame('초기');
    await vqCapture(t, key, 'S033-N_work_type_detail_392x1_top', conditions: {
      'screen': 'WorkTypeDetailScreen(workType: fixture, initialEditMode: false) — dummy route → MaterialPageRoute push(목록·auth 아님)',
      'theme': "RoleTheme.getThemeByRole('BUSINESS_ADMIN')", 'viewport': '392x851', 'dpr': 1.0, 'textScaler': 1.0,
      'inset': '선언 padding/viewPadding top30 bottom24 · viewInsets 0', 'prefs': '{}', 'fonts': 'vqLoadFonts 근사',
      'fixture': '활성 피킹 · 준비사항 2문단 · 실내(상온) · 사진 없음', 'scroll': 'off 0', 'measure': out.join(' | ')});
    var k = 0;
    while (pos.pixels < pos.maxScrollExtent - 0.5 && k < 60) {
      await t.dragFrom(Offset(vp.left + 4, vp.center.dy), const Offset(0, -200));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      k++;
      out.add(visible('drag$k'));
      actFrame('drag$k');
      if (k == 1) {
        await vqCapture(t, key, 'S033-N_work_type_detail_392x1_mid', conditions: {
          'viewport': '392x851', 'textScaler': 1.0, 'scroll': '본문 실제 dragFrom(left+4,center) -200 × 1 · off ${pos.pixels.toStringAsFixed(1)}',
          'measure': out.last});
      }
    }
    final atEnd = (pos.pixels - pos.maxScrollExtent).abs() < 0.5;
    precSpans.sort((a, b) => a[0].compareTo(b[0]));
    var covered = 0.0;
    for (final sp in precSpans) {
      if (sp[0] <= covered + 0.5) covered = sp[1] > covered ? sp[1] : covered;
    }
    out.add('본문 조작 receiver: ${bodyActs.entries.map((e) => '${e.key} ${e.value}').join(' · ')}');
    out.add('준비사항 높이=${precH.toStringAsFixed(1)} 덮은 연속 구간=0..${covered.toStringAsFixed(1)}');
    out.add('말단=$atEnd off=${pos.pixels.toStringAsFixed(1)} max=${pos.maxScrollExtent.toStringAsFixed(1)} drag=$k · calls=$calls · overflows=${overflows.length}');
    for (final l in out) {
      // ignore: avoid_print
      print('S033-N $l');
    }
    expect(find.text('준비사항'), findsOneWidget, reason: '준비사항 섹션');
    expect(precH > 0 && covered >= precH - 0.5, isTrue, reason: '준비사항 전체가 연속해 보였다');
    expect(findVisibleText(_duties), findsOneWidget, reason: '마지막 정보(주요 업무)');
    expect(atEnd || pos.maxScrollExtent < 0.5, isTrue, reason: '말단');
    expect(calls, isEmpty, reason: 'Firestore·Functions 0');
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await vqCapture(t, key, 'S033-N_work_type_detail_392x1_end', conditions: {
      'viewport': '392x851', 'textScaler': 1.0, 'scroll': '본문 실제 drag → 말단 off ${pos.pixels.toStringAsFixed(1)}', 'measure': out.last});
  });
}
