// ignore_for_file: depend_on_referenced_packages
// [DU224 N2] T223(0559bcfa)에서 승계: 이름·env 를 D224 로 바꾸고 전체보기 action 토큰·chevron·줄 배치 계측과 after 단언만 더했다.
// [DU222 S078-D224] MY K1(같은 수준 섹션 제목 위계)·K2(이니셜 온전성) — 명시 선택 시험. 같은 시험으로 baseline 1·after 1.
//   env D224_PHASE=baseline|after, D224_OUT=<dir>. D224_PHASE 가 없으면 skip 한다(일반 실행에서 새 실패 0).
//   production UserMyTab 단독 mount(root·하단 탭 없음), provider fake, live Firebase 0, 쓰기 채널 차단.
//   진단 허용 목록 0 — FlutterError.onError 를 바꾸지 않는다(두 모드 모두 오류가 나면 실패).
//   c360(360x780@1)·c320(320x640@2) x fixture a·b·c. scene 당 offset 0 PNG 1, c320-b 는 초점 PNG 2(활동·내 정보/설정 최초 전체 도달).
//   baseline 은 K1/K2 미충족을 관측값으로만 남기고, after 에서만 K1/K2 종료선을 단언한다.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/settings/trust_settings_model.dart';
import 'package:ALfit/providers/badge_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_activity_screen.dart';
import 'package:ALfit/screens/user/tabs/user_my_tab.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';

class _FakeApp222 extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore222 extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp222();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp222();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp222()];
}

const kUid222 = 'worker-local-d222';

class _User222 extends UserProvider {
  _User222(this._u);
  final UserModel _u;
  @override
  UserModel? get currentUser => _u;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
}

class _Badges222 extends ChangeNotifier implements BadgeProvider {
  _Badges222(this._list);
  final List<BadgeModel> _list;
  @override
  List<BadgeModel> get badges => _list;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
    FirebasePlatform.instance = _FakeCore222();
    await Firebase.initializeApp();
  });

  testWidgets('S078-D224 my N2 전체보기 action·K1/K2 유지', (t) async {
    await _d222Run(t);
  }, skip: Platform.environment['D224_PHASE'] == null);
}

Future<void> _d222Run(WidgetTester t) async {
  final phase = Platform.environment['D224_PHASE'] ?? '';
  expect(phase == 'baseline' || phase == 'after', isTrue, reason: 'D224_PHASE 는 baseline|after');
  final after = phase == 'after';
  final outRoot = Platform.environment['D224_OUT'] ?? '';
  expect(outRoot.isNotEmpty, isTrue, reason: 'D224_OUT');
  final outDir = Directory('$outRoot/$phase');
  await t.runAsync(vqLoadFonts);
  expect(t.takeException(), isNull, reason: 'D224 글꼴 등록');

  // ── 쓰기 채널 차단 ──
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  const fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const fsOps = [
    'documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate',
    'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'aggregateQuery',
    'querySnapshot', 'documentReferenceSnapshot',
  ];
  final blocked = <String>[];
  final msgr = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  msgr.setMockMessageHandler(fnChannel, (msg) async {
    blocked.add('functions');
    return const StandardMessageCodec().encodeMessage(
        <Object?>['not-found', 'blocked', <String, Object?>{'code': 'not-found'}]);
  });
  for (final op in fsOps) {
    msgr.setMockMessageHandler('$fsBase.$op', (msg) async {
      blocked.add('firestore $op');
      return null;
    });
  }
  addTearDown(() {
    msgr.setMockMessageHandler(fnChannel, null);
    for (final op in fsOps) {
      msgr.setMockMessageHandler('$fsBase.$op', null);
    }
  });

  var vw = 360.0;
  var vh = 780.0;
  var scale = 1.0;
  void setView(double w, double h, double s) {
    t.view.physicalSize = Size(w, h);
    t.view.devicePixelRatio = 1.0;
    vw = w;
    vh = h;
    scale = s;
  }

  setView(360, 780, 1.0);
  addTearDown(t.view.reset);

  var curScene = '';
  var pumps = 0;
  var taps = 0;
  var drags = 0;
  var pngs = 0;
  var entries = 0;
  void budget() {
    pumps++;
    expect(pumps, lessThanOrEqualTo(600), reason: 'D224 pump 예산 600');
  }

  Future<void> frames(int n) async {
    for (var i = 0; i < n; i++) {
      budget();
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  void guard(String step) {
    expect(t.takeException(), isNull, reason: 'D224 $step 예외');
    expect(blocked, isEmpty, reason: 'D224 $step 쓰기·원격 채널 0');
  }

  // ── fixture(T219 와 같은 값) ──
  final created = DateTime(2025, 1, 1);
  final cat = <BadgeModel>[
    BadgeModel(id: 'b-100', name: '100회 근무', icon: '', type: BadgeType.experience,
        conditionType: BadgeConditionType.workDays, conditionValue: 100, order: 1, createdAt: created),
    BadgeModel(id: 'b-200', name: '200회 근무', icon: '', type: BadgeType.experience,
        conditionType: BadgeConditionType.workDays, conditionValue: 200, order: 2, createdAt: created),
    BadgeModel(id: 'b-consec', name: '연속 출근', icon: '', type: BadgeType.attendance,
        conditionType: BadgeConditionType.consecutive, conditionValue: 10, order: 3, createdAt: created),
    BadgeModel(id: 'b-unique', name: '5곳 경험', icon: '', type: BadgeType.experience,
        conditionType: BadgeConditionType.uniqueBusinesses, conditionValue: 5, order: 4, createdAt: created),
  ];
  const badgeIds = ['b-100', 'b-200', 'b-consec', 'b-unique'];
  UserModel user(String name, int days, int hours, int noShow, List<String> badges) => UserModel(
        uid: kUid222, username: 'worker', name: name, email: 'w@test.local', role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '송파구'), accountStatus: 'active',
        createdAt: DateTime(2025, 3, 1), totalWorkDays: days, totalWorkHours: hours, noShowCount: noShow,
        badges: badges,
      );
  final fixtures = <String, UserModel>{
    'a': user('김민지', 0, 0, 0, const []),
    'b': user('남궁가나다라마바사아자차카타파하', 200, 1600, 2, badgeIds),
    'c': user('이서준', 0, 0, 1, const []),
  };
  const initials = {'a': '김', 'b': '남', 'c': '이'};
  const expectRate = {'a': '—', 'b': '99%', 'c': '0%'};

  final key = GlobalKey();
  Future<void> mount(UserModel u) async {
    budget();
    await t.pumpWidget(const SizedBox.shrink());
    await frames(1);
    budget();
    await t.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _User222(u)),
        ChangeNotifierProvider<BadgeProvider>(create: (_) => _Badges222(cat)),
      ],
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          theme: RoleTheme.workerTheme,
          builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: const UserMyTab(),
        ),
      ),
    ));
    await frames(8);
    guard('$curScene mount');
  }

  // ── 측정 helper ──
  List<Element> texts(String s) => find
      .byWidgetPredicate((w) {
        if (w is! Text) return false;
        final d = w.data ?? w.textSpan?.toPlainText();
        return d == s;
      })
      .evaluate()
      .toList();
  Finder el(Element e) => find.byElementPredicate((x) => identical(x, e));
  List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom];
  Rect rr(Object? v) {
    final l = (v! as List).cast<double>();
    return Rect.fromLTRB(l[0], l[1], l[2], l[3]);
  }

  bool inside(Rect r, Rect c) =>
      r.left >= c.left - 0.5 && r.top >= c.top - 0.5 && r.right <= c.right + 0.5 && r.bottom <= c.bottom + 0.5;
  String? hex(Color? c) => c?.toARGB32().toRadixString(16);
  Finder scrollF() => find.descendant(of: find.byType(UserMyTab), matching: find.byType(Scrollable));
  Rect clip() => t.getRect(scrollF()).intersect(Rect.fromLTWH(0, 0, vw, vh));
  bool inInk(Element e) => find.ancestor(of: el(e), matching: find.byType(InkWell)).evaluate().isNotEmpty;
  Element? titleEl(String n) {
    final ts = texts(n).where((e) => !inInk(e)).toList();
    return ts.length == 1 ? ts.first : null;
  }

  Element? rowEl(String n) {
    final ts = texts(n).where(inInk).toList();
    return ts.length == 1 ? ts.first : null;
  }

  // 같은 Scrollable 안의 흰 표면(Container color → ColoredBox) 중 가장 가까운 조상.
  Element? surfaceOf(Element e) {
    final inScroll = find.descendant(of: scrollF(), matching: find.byType(ColoredBox)).evaluate().toSet();
    for (final a in find.ancestor(of: el(e), matching: find.byType(ColoredBox)).evaluate()) {
      if (inScroll.contains(a)) return a;
    }
    return null;
  }

  // 실제 문단과 같은 입력으로 복제 TextPainter 를 만든다(줄수·폭 계측용).
  TextPainter replica(RenderParagraph rp) => TextPainter(
        text: rp.text,
        textDirection: rp.textDirection,
        textAlign: rp.textAlign,
        textScaler: rp.textScaler,
        maxLines: rp.maxLines,
        locale: rp.locale,
        strutStyle: rp.strutStyle,
        textWidthBasis: rp.textWidthBasis,
        textHeightBehavior: rp.textHeightBehavior,
      )..layout(maxWidth: rp.constraints.maxWidth);
  RenderParagraph paraOf(Element e) =>
      t.renderObject<RenderParagraph>(find.descendant(of: el(e), matching: find.byType(RichText)));

  Map<String, Object?> titleInfo(String n, Element e, Rect c) {
    final rp = paraOf(e);
    final tp = replica(rp);
    final lines = tp.computeLineMetrics().length;
    final tw = tp.width;
    tp.dispose();
    final st = rp.text.style;
    final r = t.getRect(el(e));
    return {
      'text': n, 'rect': lt(r), 'visible': inside(r, c), 'lines': lines, 'didExceed': rp.didExceedMaxLines,
      'textW': tw, 'maxW': rp.constraints.maxWidth.isFinite ? rp.constraints.maxWidth : null, 'fontSize': st?.fontSize, 'weight': st?.fontWeight?.value,
      'color': hex(st?.color), 'height': st?.height, 'onSurface': surfaceOf(e) != null,
    };
  }

  Map<String, Object?>? statCell(String label) {
    final ls = texts(label).where((e) => ((e.widget as Text).style?.fontSize ?? 0) == 12).toList();
    if (ls.length != 1) return null;
    final col = find.ancestor(of: el(ls.first), matching: find.byType(Column)).first;
    final ts = find.descendant(of: col, matching: find.byType(Text)).evaluate().toList();
    final v = ts.first.widget as Text;
    return {
      'label': label, 'value': v.data, 'color': hex(v.style?.color),
      'valueRect': lt(t.getRect(el(ts.first))), 'labelRect': lt(t.getRect(el(ls.first))), 'cellRect': lt(t.getRect(col)),
    };
  }

  Map<String, Object?> measure() {
    final c = clip();
    final pos = t.state<ScrollableState>(scrollF()).position;
    final out = <String, Object?>{'offset': pos.pixels, 'max': pos.maxScrollExtent, 'clip': lt(c)};
    final cells = <Map<String, Object?>>[];
    for (final l in const ['완료 근무', '총 시간', '출근율']) {
      final m = statCell(l);
      if (m != null) cells.add(m);
    }
    out['statCells'] = cells;
    final rate = cells.where((m) => m['label'] == '출근율').toList();
    if (rate.isNotEmpty) {
      out['rateValueRect'] = rate.first['valueRect'];
      out['rateText'] = rate.first['value'];
      out['rateColor'] = rate.first['color'];
    }
    final done = texts('완료 근무').where((e) => ((e.widget as Text).style?.fontSize ?? 0) == 12).toList();
    if (done.length == 1) {
      final col = find.ancestor(of: el(done.first), matching: find.byType(Column)).first;
      final rowF = find.ancestor(of: col, matching: find.byWidgetPredicate((w) => w is Row || w is Wrap)).first;
      out['statRowRect'] = lt(t.getRect(rowF));
      out['statLayout'] = rowF.evaluate().first.widget is Wrap ? 'wrap' : 'row';
    }
    // 제목 다섯과 각 섹션의 흰 표면(내용 기준점의 가장 가까운 ColoredBox)
    final titles = <Map<String, Object?>>[];
    for (final n in const ['근무 기록', '나의 활동', '근무 관리', '내 정보', '설정']) {
      final e = titleEl(n);
      if (e != null) titles.add(titleInfo(n, e, c));
    }
    out['titles'] = titles;
    final anchors = <String, Element?>{
      '근무 기록': done.length == 1 ? done.first : null,
      '나의 활동': texts('100회 근무').length == 1 ? texts('100회 근무').first : null,
      '근무 관리': rowEl('계약서'),
      '내 정보': rowEl('프로필 관리'),
      '설정': rowEl('설정'),
    };
    final surfaces = <String, Object?>{};
    for (final e in anchors.entries) {
      final a = e.value;
      if (a == null) continue;
      final s = surfaceOf(a);
      if (s != null) surfaces[e.key] = lt(t.getRect(el(s)));
    }
    out['surfaces'] = surfaces;
    final rows = <Map<String, Object?>>[];
    for (final n in const ['계약서', '내 서류 관리', '내 서명', '받은 평가', '프로필 관리', '설정']) {
      final e = rowEl(n);
      if (e == null) continue;
      final ink = find.ancestor(of: el(e), matching: find.byType(InkWell)).first;
      rows.add({'label': n, 'rect': lt(t.getRect(ink)), 'textRect': lt(t.getRect(el(e)))});
    }
    out['rows'] = rows;
    final act = titleEl('나의 활동');
    final activity = <String, Object?>{'present': act != null};
    if (act != null) {
      final all = texts('전체보기');
      if (all.length == 1) {
        final hitF = find
            .ancestor(of: el(all.first), matching: find.byWidgetPredicate((w) => w is GestureDetector || w is InkWell))
            .first;
        activity['hitRect'] = lt(t.getRect(hitF));
        activity['hitWidget'] = hitF.evaluate().first.widget.runtimeType.toString();
        activity['textRect'] = lt(t.getRect(el(all.first)));
        // [DU224 N2] 전체보기 실효 스타일·줄수·배율과 chevron 색·크기.
        final ap = paraOf(all.first);
        final ast = ap.text.style;
        final atp = replica(ap);
        activity['actionStyle'] = {
          'fontSize': ast?.fontSize, 'weight': ast?.fontWeight?.value, 'color': hex(ast?.color),
          'lines': atp.computeLineMetrics().length, 'didExceed': ap.didExceedMaxLines, 'scaler': ap.textScaler.scale(1),
        };
        atp.dispose();
        final chev = find.descendant(of: hitF, matching: find.byType(Icon));
        if (chev.evaluate().length == 1) {
          final ic = t.widget<Icon>(chev);
          activity['chevron'] = {'color': hex(ic.color), 'size': ic.size, 'rect': lt(t.getRect(chev))};
        }
      }
      final chips = <Map<String, Object?>>[];
      for (final n in const ['100회 근무', '200회 근무', '연속 출근', '5곳 경험']) {
        final ns = texts(n);
        if (ns.length != 1) continue;
        final chipF = find.ancestor(of: el(ns.first), matching: find.byType(Container)).first;
        final rp = paraOf(ns.first);
        chips.add({
          'name': n, 'chipRect': lt(t.getRect(chipF)), 'nameRect': lt(t.getRect(el(ns.first))),
          'didExceedMaxLines': rp.didExceedMaxLines,
        });
      }
      activity['chips'] = chips;
      final more = texts('+1');
      if (more.length == 1) {
        activity['moreRect'] = lt(t.getRect(find.ancestor(of: el(more.first), matching: find.byType(Container)).first));
      }
    }
    out['activity'] = activity;
    return out;
  }

  // ── K2 이니셜: 원·문단·이름 기하와, 같은 입력으로 offscreen 에 그린 잉크 화소의 원 밖 개수 ──
  Future<Map<String, Object?>> avatarInk(String initial, String name) async {
    final avs = texts(initial).where((e) => ((e.widget as Text).style?.fontSize ?? 0) == 22).toList();
    expect(avs.length, 1, reason: 'D224 $curScene 이니셜 Text 하나');
    final av = avs.first;
    final circleF = find
        .ancestor(
            of: el(av),
            matching: find.byWidgetPredicate((wd) =>
                wd is Container && wd.decoration is BoxDecoration && (wd.decoration! as BoxDecoration).shape == BoxShape.circle))
        .first;
    final circle = t.getRect(circleF);
    final rp = paraOf(av);
    final origin = rp.localToGlobal(Offset.zero);
    final paraSize = rp.size;
    final textSize = rp.textSize;
    final tp = replica(rp);
    expect((tp.width - textSize.width).abs() < 0.01 && (tp.height - textSize.height).abs() < 0.01, isTrue,
        reason: 'D224 $curScene 이니셜 복제 계측 일치');
    const m = 24.0;
    final w = (tp.width + 2 * m).ceil();
    final h = (tp.height + 2 * m).ceil();
    final rec = ui.PictureRecorder();
    tp.paint(Canvas(rec), const Offset(m, m));
    final pic = rec.endRecording();
    final need = (tp.height > tp.width ? tp.height : tp.width) + 16;
    final tpW = tp.width;
    final tpH = tp.height;
    tp.dispose();
    final rgba = await t.runAsync(() async {
      final img = await pic.toImage(w, h);
      final bd = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      img.dispose();
      return bd!.buffer.asUint8List();
    });
    pic.dispose();
    final px = rgba!;
    final clipped = textSize.height > paraSize.height + 0.01 || textSize.width > paraSize.width + 0.01;
    final cx = circle.center.dx;
    final cy = circle.center.dy;
    final r = circle.width / 2;
    var total = 0;
    var outside = 0;
    var cut = 0;
    var l0 = double.infinity;
    var t0 = double.infinity;
    var r0 = -double.infinity;
    var b0 = -double.infinity;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        if (px[(y * w + x) * 4 + 3] == 0) continue;
        total++;
        final gx = origin.dx + x + 0.5 - m;
        final gy = origin.dy + y + 0.5 - m;
        if (gx < l0) l0 = gx;
        if (gy < t0) t0 = gy;
        if (gx > r0) r0 = gx;
        if (gy > b0) b0 = gy;
        final dx = gx - cx;
        final dy = gy - cy;
        if (dx * dx + dy * dy > r * r) outside++;
        if (clipped &&
            (gx < origin.dx || gy < origin.dy || gx > origin.dx + paraSize.width || gy > origin.dy + paraSize.height)) {
          cut++;
        }
      }
    }
    final names = texts(name);
    final joins = texts('2025.03 가입');
    final out = <String, Object?>{
      'initial': initial, 'circle': lt(circle), 'para': lt(origin & paraSize), 'textSize': [textSize.width, textSize.height],
      'replica': [tpW, tpH], 'need': need, 'paraClipped': clipped, 'inkTotal': total, 'inkOutside': outside,
      'inkCutByPara': cut, 'inkBox': total == 0 ? null : [l0 - 0.5, t0 - 0.5, r0 + 0.5, b0 + 0.5],
      'nameRect': names.length == 1 ? lt(t.getRect(el(names.first))) : null,
      'joinRect': joins.length == 1 ? lt(t.getRect(el(joins.first))) : null,
    };
    print('D224K ${jsonEncode({'phase': phase, 'scene': curScene, ...out})}');
    return out;
  }

  Future<Map<String, Object?>> dragUpBy(double need, Rect c, String next, int i, List<String> missing) async {
    final p0 = Offset(8, vh - 40);
    expect(c.contains(p0), isTrue, reason: 'D224 $curScene 시작점 clip 안');
    // DU220 과 같은 조작: 첫 20px 인식 구간, 둘째 이동 min(max(need,48), maxStep). 실제 이동량은 매회 실측한다.
    final maxStep = p0.dy - 20 - (c.top + 8);
    expect(maxStep >= 48, isTrue, reason: 'D224 $curScene maxStep $maxStep');
    final want = need < 48 ? 48.0 : need;
    final second = want > maxStep ? maxStep : want;
    final p2 = Offset(p0.dx, p0.dy - 20 - second);
    expect(c.contains(p2), isTrue, reason: 'D224 $curScene 끝점 $p2 clip 안');
    final pos0 = t.state<ScrollableState>(scrollF()).position;
    final before = pos0.pixels;
    final maxBefore = pos0.maxScrollExtent;
    final hitPath = t.hitTestOnBinding(p0).path.map((e) => e.target.runtimeType.toString()).toList();
    drags++;
    expect(drags, lessThanOrEqualTo(24), reason: 'D224 drag 예산 24');
    final g = await t.startGesture(p0);
    var upSent = false;
    try {
      await g.moveBy(const Offset(0, -20));
      await g.moveBy(Offset(0, -second));
      upSent = true;
      await g.up();
    } finally {
      if (!upSent) {
        upSent = true;
        await g.up();
      }
    }
    await frames(4);
    guard('$curScene drag');
    final pos1 = t.state<ScrollableState>(scrollF()).position;
    final raw = <String, Object?>{
      'phase': phase, 'scene': curScene, 'i': i, 'next': next, 'need': need, 'clip': lt(c),
      'start': [p0.dx, p0.dy], 'end': [p2.dx, p2.dy], 'first': 20, 'second': second, 'maxStep': maxStep,
      'pixelsBefore': before, 'pixelsAfter': pos1.pixels, 'maxBefore': maxBefore, 'maxAfter': pos1.maxScrollExtent,
      'delta': pos1.pixels - before, 'missing': missing, 'hitPath': hitPath,
      'pumps': pumps, 'taps': taps, 'drags': drags,
    };
    print('D224D ${jsonEncode(raw)}');
    return raw;
  }

  bool sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> capture(String id) async {
    await frames(8);
    guard('$id 캡처 전');
    expect(pngs, lessThan(8), reason: 'D224 PNG 예산 8');
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      outDir.createSync(recursive: true);
      final img = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
      final png = File('${outDir.path}/$id.png');
      if (png.existsSync()) throw StateError('D224 캡처를 덮지 않는다: ${png.path}');
      png.writeAsBytesSync(bytes!.buffer.asUint8List());
    });
    pngs++;
    guard('$id 캡처');
  }

  // 도달 그룹: 근무 기록(제목+표면), 나의 활동(제목+전체보기+칩+1+표면), 근무 관리, 꼬리(내 정보+설정). 꼬리는 c320-b 초점2와 같다.
  Map<String, List<Rect>> groupsOf(Map<String, Object?> m) {
    final g = <String, List<Rect>>{};
    final titles = <String, Rect>{};
    for (final x in (m['titles']! as List).cast<Map<String, Object?>>()) {
      titles[x['text']! as String] = rr(x['rect']);
    }
    final surf = <String, Rect>{};
    for (final e in (m['surfaces']! as Map<String, Object?>).entries) {
      surf[e.key] = rr(e.value);
    }
    List<Rect>? sec(String n) => titles[n] == null || surf[n] == null ? null : [titles[n]!, surf[n]!];
    final career = sec('근무 기록');
    if (career != null) g['career'] = career;
    final act = m['activity']! as Map<String, Object?>;
    if (act['present'] == true && act['hitRect'] != null && titles['나의 활동'] != null && surf['나의 활동'] != null) {
      g['activity'] = [
        titles['나의 활동']!,
        rr(act['hitRect']),
        ...(act['chips']! as List).cast<Map<String, Object?>>().map((x) => rr(x['chipRect'])),
        if (act['moreRect'] != null) rr(act['moreRect']),
        surf['나의 활동']!,
      ];
    }
    for (final n in const ['근무 관리', '내 정보', '설정']) {
      final s = sec(n);
      if (s != null) g['sec:$n'] = s;
    }
    final a = sec('내 정보');
    final b = sec('설정');
    if (a != null && b != null) g['tail'] = [...a, ...b];
    return g;
  }

  final results = <String, Object?>{};
  for (final cond in const ['c360', 'c320']) {
    if (cond == 'c360') setView(360, 780, 1.0);
    if (cond == 'c320') setView(320, 640, 2.0);
    for (final fx in const ['a', 'b', 'c']) {
      curScene = '$cond-$fx';
      final u = fixtures[fx]!;
      await mount(u);
      expect(find.byType(UserMyTab), findsOneWidget, reason: 'D224 $curScene MY');
      expect(scrollF(), findsOneWidget, reason: 'D224 $curScene scrollable 하나');
      final atCapture = measure();
      final k2 = await avatarInk(initials[fx]!, u.name);
      await capture(curScene);
      final focus = <String, Object?>{};
      final reached = <String, Object?>{};
      var sceneDrags = 0;
      double? lastDelta;
      for (var i = 0;; i++) {
        final m = measure();
        final c = rr(m['clip']);
        final groups = groupsOf(m);
        final fresh = <String>[];
        for (final e in groups.entries) {
          if (!reached.containsKey(e.key) && e.value.every((r) => r.top >= c.top - 0.5 && r.bottom <= c.bottom + 0.5)) {
            reached[e.key] = {'at': i, 'offset': m['offset'], 'm': m};
            fresh.add(e.key);
          }
        }
        // c320-b 초점 PNG: 활동 그룹·꼬리(내 정보+설정)가 처음 전부 보인 순간 1장씩(같은 앵커 규칙을 두 모드에 쓴다).
        if (curScene == 'c320-b') {
          for (final f in const ['activity', 'tail']) {
            if (fresh.contains(f)) {
              final id = f == 'activity' ? 'c320-b-f1' : 'c320-b-f2';
              await capture(id);
              focus[id] = {'group': f, 'at': i, 'offset': m['offset']};
            }
          }
        }
        // 전체보기 진입 검사(after c360-b, 활동이 처음 전부 보인 순간 1회).
        if (after && curScene == 'c360-b' && fresh.contains('activity')) {
          final act = m['activity']! as Map<String, Object?>;
          final hit = rr(act['hitRect']);
          final tp = Offset(hit.center.dx, hit.bottom - 4);
          entries++;
          expect(entries, lessThanOrEqualTo(1), reason: 'D224 진입 검사 1');
          taps++;
          await t.tapAt(tp);
          await frames(10);
          guard('$curScene 전체보기 진입');
          final scr = find.byType(MyActivityScreen);
          expect(scr, findsOneWidget, reason: 'D224 $curScene MyActivityScreen 진입');
          final ids = (t.widget(scr) as MyActivityScreen).userBadgeIds;
          expect(sameList(ids, badgeIds), isTrue, reason: 'D224 $curScene 목적지 인자 raw ID');
          taps++;
          await t.tap(find.byType(BackButton));
          await frames(10);
          guard('$curScene 복귀');
          expect(find.byType(MyActivityScreen), findsNothing, reason: 'D224 $curScene 복귀');
          reached['entry'] = {'tap': [tp.dx, tp.dy], 'ids': ids};
          print('D224E ${jsonEncode({'phase': phase, 'scene': curScene, 'i': i, 'tap': [tp.dx, tp.dy], 'hit': lt(hit), 'ids': ids, 'returned': find.byType(MyActivityScreen).evaluate().isEmpty, 'pumps': pumps, 'taps': taps})}');
        }
        final want = <String>['career', if (fx == 'b') 'activity', 'sec:근무 관리', 'tail'];
        final missing = want.where((k) => !reached.containsKey(k)).toList();
        final posM = t.state<ScrollableState>(scrollF()).position;
        print('D224M ${jsonEncode({'phase': phase, 'scene': curScene, 'i': i, 'offset': m['offset'], 'max': m['max'], 'extentAfter': posM.extentAfter, 'fresh': fresh, 'missing': missing, 'lastDelta': lastDelta, 'pumps': pumps, 'drags': drags})}');
        if (missing.isEmpty) break;
        if (lastDelta != null) {
          expect(lastDelta > 0.5, isTrue, reason: 'D224 $curScene 무진행 $missing delta $lastDelta');
        }
        expect(posM.extentAfter > 0.5, isTrue, reason: 'D224 $curScene 아래 여유 없음·미도달 $missing');
        expect(sceneDrags < 4, isTrue, reason: 'D224 $curScene 도달 상한 4 미도달 $missing');
        final next = missing.first;
        final rs = groups[next];
        double need;
        if (rs == null) {
          need = 10000;
        } else {
          var bottom = rs.first.bottom;
          for (final r in rs) {
            if (r.bottom > bottom) bottom = r.bottom;
          }
          need = bottom - (c.bottom - 8);
        }
        expect(need > 0, isTrue, reason: 'D224 $curScene $next 이미 위로 지나감');
        sceneDrags++;
        final dr = await dragUpBy(need, c, next, i, missing);
        lastDelta = dr['delta']! as double;
      }
      Map<String, Object?> mAt(String k) => (reached[k]! as Map<String, Object?>)['m']! as Map<String, Object?>;
      Map<String, Object?> titleAt(String k, String n) =>
          (mAt(k)['titles']! as List).cast<Map<String, Object?>>().firstWhere((x) => x['text'] == n);
      final secKey = <String, String>{
        '근무 기록': 'career', '나의 활동': 'activity', '근무 관리': 'sec:근무 관리', '내 정보': 'tail', '설정': 'tail',
      };
      final names = <String>['근무 기록', if (fx == 'b') '나의 활동', '근무 관리', '내 정보', '설정'];
      // ── 관측(두 모드) ──
      final sm = mAt('career');
      final titleObs = [
        for (final n in names)
          {
            'text': n,
            'fontSize': titleAt(secKey[n]!, n)['fontSize'],
            'weight': titleAt(secKey[n]!, n)['weight'],
            'color': titleAt(secKey[n]!, n)['color'],
            'onSurface': titleAt(secKey[n]!, n)['onSurface'],
            'lines': titleAt(secKey[n]!, n)['lines'],
          },
      ];
      final judge = <String, Object?>{
        'K1_uniform': titleObs.every((x) =>
            x['fontSize'] == 20.0 && x['weight'] == 700 && x['color'] == hex(AppColors.textPrimary) && x['onSurface'] == false),
        'K1_titles': titleObs,
        'K2_inkOutside': k2['inkOutside'],
        'K2_paraClipped': k2['paraClipped'],
        'K2_circle': k2['circle'],
        'rateText': sm['rateText'],
        'rateColor': sm['rateColor'],
        'statLayout': sm['statLayout'],
      };
      if (fx == 'b') {
        // [DU224 N2] 전체보기 action 관측: 실효 스타일·chevron·제목/행동이 같은 줄인지·좌표(활동 최초 전체 도달 시점).
        final am0 = mAt('activity');
        final a0 = am0['activity']! as Map<String, Object?>;
        final head0 = rr(titleAt('activity', '나의 활동')['rect']);
        final hit0 = rr(a0['hitRect']);
        judge['N2'] = {
          'style': a0['actionStyle'], 'chevron': a0['chevron'], 'title': lt(head0), 'hit': lt(hit0),
          'text': a0['textRect'], 'sameLine': hit0.top < head0.bottom - 0.5, 'offset': am0['offset'],
        };
      }
      print('D224C ${jsonEncode({'phase': phase, 'scene': curScene, 'judge': judge, 'focus': focus})}');
      // ── 신원·계측 유효성(두 모드) ──
      expect(sm['rateText'], expectRate[fx], reason: 'D224 $curScene 출근율 표시');
      expect(sm['rateColor'],
          fx == 'a' ? hex(AppColors.textSecondary) : (fx == 'b' ? hex(AppColors.successDark) : hex(AppColors.error)),
          reason: 'D224 $curScene 출근율 색');
      final cellsAt = (sm['statCells']! as List).cast<Map<String, Object?>>();
      final doneV = cellsAt.where((x) => x['label'] == '완료 근무').map((x) => x['value']).toList();
      expect(doneV, [fx == 'b' ? '200회' : '0회'], reason: 'D224 $curScene 완료 근무');
      double absTop(String n) {
        final mm = mAt(secKey[n]!);
        return rr(titleAt(secKey[n]!, n)['rect']).top + (mm['offset']! as double);
      }

      for (var p = 0; p + 1 < names.length; p++) {
        expect(absTop(names[p]) < absTop(names[p + 1]), isTrue, reason: 'D224 $curScene 섹션 순서 ${names[p]}');
      }
      expect((k2['inkTotal']! as int) > 0, isTrue, reason: 'D224 $curScene 이니셜 잉크 계측');
      if (curScene == 'c320-b') {
        expect(focus.length, 2, reason: 'D224 c320-b 초점 2');
      }
      // ── after 단언: K1·K2 종료선과 기존 교정 새 배치 영향 ──
      if (after) {
        for (final n in names) {
          final x = titleAt(secKey[n]!, n);
          final r = rr(x['rect']);
          final s = rr((mAt(secKey[n]!)['surfaces']! as Map<String, Object?>)[n]);
          expect(x['fontSize'] == 20.0 && x['weight'] == 700 && x['color'] == hex(AppColors.textPrimary) && x['height'] == 1.2,
              isTrue, reason: 'D224 after $curScene K1 $n 공용 위계 $x');
          expect(x['onSurface'], isFalse, reason: 'D224 after $curScene K1 $n 표면 밖');
          expect(x['lines'] == 1 && x['didExceed'] == false, isTrue, reason: 'D224 after $curScene K1 $n 잘림·줄바꿈 0 $x');
          expect(r.left >= 20 - 0.5 && r.right <= vw - 20 + 0.5, isTrue, reason: 'D224 after $curScene K1 $n 가로 포함 $r');
          expect(r.bottom <= s.top + 0.5, isTrue, reason: 'D224 after $curScene K1 $n 제목 아래 표면 $r $s');
          for (final row in (mAt(secKey[n]!)['rows']! as List).cast<Map<String, Object?>>()) {
            expect(rr(row['rect']).overlaps(r), isFalse, reason: 'D224 after $curScene K1 $n 메뉴 행 겹침 0');
          }
        }
        for (final k in const ['sec:근무 관리', 'tail']) {
          final mm = mAt(k);
          final surf = (mm['surfaces']! as Map<String, Object?>).map((a, b) => MapEntry(a, rr(b)));
          for (final row in (mm['rows']! as List).cast<Map<String, Object?>>()) {
            final rowR = rr(row['rect']);
            expect(surf.values.any((s) => inside(rowR, s)), isTrue, reason: 'D224 after $curScene ${row['label']} 행 표면 안');
          }
        }
        // R5: 통계 셀·값·라벨이 근무 기록 표면 안쪽(좌우 20 제외) 가로에 있고 셀끼리 겹침 0.
        final cs = rr((sm['surfaces']! as Map<String, Object?>)['근무 기록']);
        final cellRects = <Rect>[];
        for (final x in cellsAt) {
          for (final k in const ['cellRect', 'valueRect', 'labelRect']) {
            final r = rr(x[k]);
            expect(r.left >= cs.left + 20 - 0.5 && r.right <= cs.right - 20 + 0.5, isTrue,
                reason: 'D224 after $curScene R5 ${x['label']} $k 본문 안');
          }
          cellRects.add(rr(x['cellRect']));
        }
        for (var p = 0; p < cellRects.length; p++) {
          for (var q = p + 1; q < cellRects.length; q++) {
            expect(cellRects[p].overlaps(cellRects[q]), isFalse, reason: 'D224 after $curScene R5 셀 겹침 0');
          }
        }
        if (fx == 'b') {
          final am = mAt('activity');
          final a = am['activity']! as Map<String, Object?>;
          final chipsAt = (a['chips']! as List).cast<Map<String, Object?>>();
          expect(chipsAt.map((x) => x['name']).toList(), ['100회 근무', '200회 근무', '연속 출근'], reason: 'D224 after 미리보기 3·순서');
          expect(a['moreRect'] != null, isTrue, reason: 'D224 after +1 유지');
          final s = rr((am['surfaces']! as Map<String, Object?>)['나의 활동']);
          final head = rr(titleAt('activity', '나의 활동')['rect']);
          final hitR = rr(a['hitRect']);
          final rects = [...chipsAt.map((x) => rr(x['chipRect'])), rr(a['moreRect'])];
          for (var p = 0; p < rects.length; p++) {
            expect(rects[p].left >= s.left + 20 - 0.5 && rects[p].right <= s.right - 20 + 0.5, isTrue,
                reason: 'D224 after $curScene R6 배지 본문 가로 안 ${rects[p]}');
            for (var q = p + 1; q < rects.length; q++) {
              expect(rects[p].overlaps(rects[q]), isFalse, reason: 'D224 after $curScene R6 배지 겹침 0');
            }
          }
          expect(hitR.width >= 48 - 0.01 && hitR.height >= 48 - 0.01, isTrue, reason: 'D224 after $curScene R8 hit 48 $hitR');
          expect(hitR.left >= 20 - 0.5 && hitR.right <= vw - 20 + 0.5, isTrue, reason: 'D224 after $curScene K1 전체보기 가로 포함 $hitR');
          expect(hitR.overlaps(head), isFalse, reason: 'D224 after $curScene K1 전체보기·제목 겹침 0');
          expect(hitR.bottom <= s.top + 0.5, isTrue, reason: 'D224 after $curScene K1 전체보기 표면 위 $hitR $s');
          for (final r in rects) {
            expect(hitR.overlaps(r), isFalse, reason: 'D224 after $curScene R8 hit 배지 겹침 0');
          }
          // [DU224 N2] 공용 action 토큰(15/w600/brand)·chevron(brand·14)·전체 글자 한 줄·배율 그대로, 글자는 receiver 안, 후속 메뉴 행 겹침 0.
          final ast = a['actionStyle']! as Map<String, Object?>;
          expect(ast['fontSize'] == 15.0 && ast['weight'] == 600 && ast['color'] == hex(AppColors.brand), isTrue,
              reason: 'D224 after $curScene N2 action 토큰 $ast');
          expect(ast['lines'] == 1 && ast['didExceed'] == false && ast['scaler'] == scale, isTrue,
              reason: 'D224 after $curScene N2 전체 글자·배율 $ast');
          final ch = a['chevron'] as Map<String, Object?>?;
          expect(ch != null && ch['color'] == hex(AppColors.brand) && ch['size'] == 14.0, isTrue,
              reason: 'D224 after $curScene N2 chevron $ch');
          final txR = rr(a['textRect']);
          expect(txR.left >= hitR.left - 0.5 && txR.right <= hitR.right + 0.5 && txR.top >= hitR.top - 0.5 && txR.bottom <= hitR.bottom + 0.5,
              isTrue, reason: 'D224 after $curScene N2 글자 receiver 안 $txR $hitR');
          for (final row in (am['rows']! as List).cast<Map<String, Object?>>()) {
            expect(rr(row['rect']).overlaps(hitR), isFalse, reason: 'D224 after $curScene N2 후속 행 겹침 0');
          }
        }
        // K2: 지름 = max(56, ceil(max(문단 높이, 폭) + 16)), 정사각, 문단 잘림 0, 원 밖 잉크 0, 이름·가입일 겹침 0.
        final circle = rr(k2['circle']);
        final needD = k2['need']! as double;
        final wantD = needD > 56 ? needD.ceilToDouble() : 56.0;
        expect((circle.width - wantD).abs() < 0.01 && (circle.height - wantD).abs() < 0.01, isTrue,
            reason: 'D224 after $curScene K2 지름 $circle 기대 $wantD');
        if (cond == 'c360') {
          expect((circle.width - 56).abs() < 0.01, isTrue, reason: 'D224 after $curScene K2 1.0 배율 56 유지');
        }
        expect(k2['paraClipped'], isFalse, reason: 'D224 after $curScene K2 문단 잘림 0');
        expect(k2['inkOutside'], 0, reason: 'D224 after $curScene K2 원 밖 잉크 0');
        for (final k in const ['nameRect', 'joinRect']) {
          expect(k2[k] != null, isTrue, reason: 'D224 after $curScene K2 $k 있음');
          expect(rr(k2[k]).overlaps(circle), isFalse, reason: 'D224 after $curScene K2 $k 겹침 0');
        }
      }
      // ── sidecar ──
      await t.runAsync(() async {
        final js = File('${outDir.path}/$curScene.json');
        if (js.existsSync()) throw StateError('D224 sidecar 를 덮지 않는다: ${js.path}');
        js.writeAsStringSync(jsonEncode({
          'phase': phase, 'scene': curScene, 'viewport': [vw, vh], 'dpr': 1.0, 'textScaler': scale, 'inset': 0,
          'theme': 'RoleTheme.workerTheme', 'locale': 'ko_KR', 'fonts': 'vqLoadFonts',
          ...atCapture, 'k2': k2, 'focus': focus, 'reached': reached, 'judge': judge,
        }));
      });
      guard('$curScene sidecar');
      results[curScene] = {'K1_uniform': judge['K1_uniform'], 'K2_inkOutside': k2['inkOutside'], 'K2_paraClipped': k2['paraClipped']};
    }
  }
  setView(360, 780, 1.0);
  print('D224END ${jsonEncode({'phase': phase, 'pumps': pumps, 'taps': taps, 'drags': drags, 'pngs': pngs, 'entries': entries, 'blocked': blocked.length, 'results': results})}');
}
