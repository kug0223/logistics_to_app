// ignore_for_file: depend_on_referenced_packages
// [DU1 후속92] 선정 B 320×640@2.0(inset 0) — 후속91 과 같은 fixture·host. 준비사항 연속 읽기는 프레임별 보인 세로 구간의 합집합이 전체 높이를 덮는지로 판정.
// [DU1 후속91] S012 BusinessDetailScreen — BUSINESS_ADMIN 소유자 · 승인/활성 사업장 1개 · 준비사항 있음 · 정상 읽기 N.
//   host: LOCAL dummy route → NavigationHelper.push 와 같은 일반 MaterialPageRoute 로 BusinessDetailScreen(business: fixture)
//     (실제 settings→BusinessList/auth/원격 조회 통과 아님). Theme RoleTheme.getThemeByRole('BUSINESS_ADMIN').
//   fixture: 사진·지도 없음(mainImageUrl=null·imageUrls 없음·좌표 null) — 이미지 플레이스홀더·지도 미표시 범위. 준비사항 2문단.
//   읽기 seam: initState 는 전달 모델만 쓴다(재조회는 수정 복귀 true 일 때만). Firestore 10 op·Functions 는 막고 계수(0 단언) — 그 밖 채널 미계측.
//   수정/저장/삭제/지도/전화/주소복사/홈/알림/뒤로는 누르지 않는다(hitTest 만).
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_detail_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';

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

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'owner1', username: 'owner1', name: 'QA 사장', email: 'owner1@alfit.local',
        role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const ['biz1']);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
}

const _precautions = '작업 중에는 안전화를 꼭 착용해 주세요. 현장 입구에서 출입 명부를 작성합니다.\n'
    '휴게 시간에는 지정된 휴게실만 이용할 수 있으며, 작업장 안에서는 음식물 섭취가 금지됩니다.';

BusinessModel _biz() => BusinessModel(
      id: 'biz1',
      name: '중앙물류센터 수도권 1센터',
      ownerId: 'owner1',
      businessNumber: '0000000000',
      category: '물류',
      subCategory: '창고',
      address: '경기도 화성시 동탄순환대로 1길 23',
      detailAddress: '3층 물류동 A구역',
      phone: '031-000-0000',
      precautions: _precautions,
      isApproved: true,
      createdAt: DateTime(2026, 1, 1),
    );

void main() {
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  const fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('S012-B 사업장 상세 소유자 준비사항 320×640@2.0 — 전체·실제 drag 연속 읽기·receiver', (t) async {
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
    t.view.physicalSize = const Size(320, 640);
    t.view.devicePixelRatio = 1.0;
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
    final biz = _biz();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _Owner()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.getThemeByRole('BUSINESS_ADMIN'),
          builder: (ctx, child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: const TextScaler.linear(2.0)), child: child!),
          home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => BusinessDetailScreen(business: biz))),
              child: const Text('host'))))),
        ),
      ),
    ));
    await t.tap(find.text('host'));
    for (var i = 0; i < 14; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(t.takeException(), isNull);
    final screen = find.byType(BusinessDetailScreen);
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
      'fixture 승인=${biz.isApproved} 비활성=${biz.deactivatedAt} 보관=${biz.archivedAt} owner=${biz.ownerId} 사진=${biz.mainImageUrl}/${biz.imageUrls} 좌표=${biz.latitude},${biz.longitude}',
    ];
    final seenPrec = <String>{};
    final precSpans = <List<double>>[]; // 준비사항 Text 안 좌표계 [위, 아래] 보인 구간
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
          if (s == _precautions && v.height >= r.height - 0.5) seenPrec.add(when);
          if (s == _precautions) {
            precH = r.height;
            precSpans.add([v.top - r.top, v.bottom - r.top]);
          }
          parts.add('"${s.replaceAll('\n', '⏎')}"(${v.height.toStringAsFixed(0)}/${r.height.toStringAsFixed(0)})');
        }
      }
      return '$when off=${pos.pixels.toStringAsFixed(1)} 보이는 글 ${parts.length}: ${parts.join(' ')}';
    }
    // [구현91 current 관찰] 툴바 아래 제목 줄(AppPageScaffold _TitleBelow)의 글자 아래가 잘려 보였다 — 제목 Text·담는 상자·AppBar rect
    final titleBelow = find.descendant(of: find.byType(AppBar), matching: find.byWidgetPredicate((w) => w is Text && w.semanticsLabel == biz.name));
    if (titleBelow.evaluate().isNotEmpty) {
      final tr = t.getRect(titleBelow.first);
      final box = find.ancestor(of: titleBelow.first, matching: find.byType(SizedBox)).first;
      final para = t.renderObject<RenderParagraph>(find.descendant(of: titleBelow.first, matching: find.byType(RichText)).first);
      out.add('툴바 아래 제목 Text $tr h=${tr.height.toStringAsFixed(1)} · 담는 SizedBox ${t.getRect(box)} h=${t.getRect(box).height.toStringAsFixed(1)} · '
          'paragraph size=${para.size} didExceed=${para.didExceedMaxLines} · AppBar ${t.getRect(find.byType(AppBar))} · 본문 top=${vp.top}');
    } else {
      out.add('툴바 아래 제목 없음(툴바 안 제목)');
    }
    // 머리 행동(AppBar) — 뒤로(leading)·홈·알림·수정
    final appBarButtons = find.descendant(of: find.byType(AppBar), matching: find.byType(IconButton));
    for (var i = 0; i < appBarButtons.evaluate().length; i++) {
      final b = appBarButtons.at(i);
      final r = t.getRect(b);
      final icon = t.widget<IconButton>(b).icon;
      final ic = icon is Icon ? icon.icon : null;
      out.add('AppBar IconButton[$i] icon=${ic?.codePoint.toRadixString(16)} $r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} hit=${hits(b, r.center)}');
      expect(r.width >= 48 - 0.01 && r.height >= 48 - 0.01 && hits(b, r.center), isTrue, reason: 'AppBar receiver[$i]');
    }
    // 본문 안 조작 receiver(주소 복사 등) — 화면에 보이는 InkWell/IconButton/버튼류
    final bodyActs = <String, String>{};
    var copyRect = Rect.zero;
    var copyHit = false;
    void actFrame(String when) {
      final f = find.descendant(of: scroll, matching: find.byWidgetPredicate((w) => w is IconButton || w is ButtonStyleButton || (w is InkWell && w.onTap != null)));
      for (var i = 0; i < f.evaluate().length; i++) {
        final r = t.getRect(f.at(i));
        if (r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5 && r.width > 0) {
          final label = t.widgetList<Text>(find.descendant(of: f.at(i), matching: find.byType(Text))).map((x) => x.data ?? '').join('/');
          final k = '${f.evaluate().elementAt(i).widget.runtimeType}"$label"@${(r.top + pos.pixels).toStringAsFixed(0)}';
          bodyActs.putIfAbsent(k, () => '$when $r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} hit=${hits(f.at(i), r.center)}');
          if (label.contains('주소 복사') && copyRect == Rect.zero) {
            copyRect = r;
            copyHit = hits(f.at(i), r.center);
          }
        }
      }
    }
    out.add(visible('초기'));
    actFrame('초기');
    await vqCapture(t, key, 'S012-B_business_detail_320x2_top', conditions: {
      'screen': 'BusinessDetailScreen(business: fixture) — dummy route → MaterialPageRoute push(BusinessList·auth 아님)',
      'theme': "RoleTheme.getThemeByRole('BUSINESS_ADMIN')", 'viewport': '320x640', 'dpr': 1.0, 'textScaler': 2.0,
      'inset': '모두 0', 'prefs': '{}', 'fonts': 'vqLoadFonts 근사',
      'fixture': '소유자·승인·활성·준비사항 2문단·사진/지도 없음', 'scroll': 'off 0', 'measure': out.join(' | ')});
    var k = 0;
    while (pos.pixels < pos.maxScrollExtent - 0.5 && k < 60) {
      await t.dragFrom(Offset(vp.left + 4, vp.center.dy), const Offset(0, -150));
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      k++;
      out.add(visible('drag$k'));
      actFrame('drag$k');
      if (k == 1) {
        await vqCapture(t, key, 'S012-B_business_detail_320x2_mid', conditions: {
          'viewport': '320x640', 'textScaler': 2.0, 'scroll': '본문 실제 dragFrom(left+4,center) -150 × 1 · off ${pos.pixels.toStringAsFixed(1)}',
          'measure': out.last});
      }
    }
    final atEnd = (pos.pixels - pos.maxScrollExtent).abs() < 0.5;
    // [구현91 after] 주소 복사 receiver ≥48 단언(current 68.2×19.0)
    final copyKey = bodyActs.keys.firstWhere((k) => k.contains('주소 복사'), orElse: () => '');
    out.add('주소 복사 기록=${copyKey.isEmpty ? '없음' : bodyActs[copyKey]}');
    out.add('본문 조작 receiver: ${bodyActs.entries.map((e) => '${e.key} ${e.value}').join(' · ')}');
    out.add('말단=$atEnd off=${pos.pixels.toStringAsFixed(1)} max=${pos.maxScrollExtent.toStringAsFixed(1)} drag=$k · 준비사항 전체 보인 프레임=$seenPrec · calls=$calls · overflows=${overflows.length}');
    for (final l in out) {
      // ignore: avoid_print
      print('S012-B $l');
    }
    expect(find.text('준비사항'), findsOneWidget, reason: '준비사항 섹션');
    expect(copyRect.height >= 48 - 0.01 && copyHit, isTrue, reason: '주소 복사 receiver 48');
    final phoneKey = bodyActs.keys.where((k) => k.startsWith('IconButton')).toList();
    // ignore: avoid_print
    print('S012-B 전화 IconButton 기록=${phoneKey.map((k) => '$k ${bodyActs[k]}').join(' · ')}');
    expect(phoneKey, isNotEmpty, reason: '전화 IconButton 이 표시 영역 안에 들어온 프레임이 있다');
    expect(find.text('031-000-0000'), findsOneWidget, reason: '마지막 연락처');
    // 큰 글씨: 한 프레임 전문을 요구하지 않는다 — 보인 구간 합집합이 0..높이 를 빈틈없이 덮어야 한다
    precSpans.sort((a, b) => a[0].compareTo(b[0]));
    var covered = 0.0;
    for (final sp in precSpans) {
      if (sp[0] <= covered + 0.5) covered = sp[1] > covered ? sp[1] : covered;
    }
    // ignore: avoid_print
    print('S012-B 준비사항 높이=${precH.toStringAsFixed(1)} 덮은 연속 구간=0..${covered.toStringAsFixed(1)} 프레임 구간=${precSpans.map((e) => '${e[0].toStringAsFixed(0)}-${e[1].toStringAsFixed(0)}').join(',')} 한프레임전문=$seenPrec');
    expect(precH > 0 && covered >= precH - 0.5, isTrue, reason: '준비사항 전체가 중첩 프레임으로 연속해 보였다');
    expect(atEnd || pos.maxScrollExtent < 0.5, isTrue, reason: '말단');
    expect(calls, isEmpty, reason: 'Firestore·Functions 0');
    expect(overflows, isEmpty, reason: overflows.join(' | '));
    expect(t.takeException(), isNull);
    await vqCapture(t, key, 'S012-B_business_detail_320x2_end', conditions: {
      'viewport': '320x640', 'textScaler': 2.0, 'scroll': '본문 실제 drag → 말단 off ${pos.pixels.toStringAsFixed(1)}', 'measure': out.last});
  });
}
