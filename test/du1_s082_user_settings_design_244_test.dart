// ignore_for_file: depend_on_referenced_packages
// [DU244 S082 근로자 설정 시안 정렬 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU244_RUN=1 이고 DU244_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   standalone(MaterialApp home: const UserSettingsScreen()). 장면 2(off: 알림 권한 거부 / on: 허용 + 사용자 문서 대역
//   + '알림 세부 설정' 펼침 tap 1회) × W360/1.0·B320/2.0.
//   외부: 알림 권한 채널, PackageInfo 대역, on 장면의 users/u-d244 get 만 허용한다. 그 밖 Firestore·Functions 는 막고 기록한다.
//   스위치·로그아웃·탈퇴·약관·도움말 tap 0.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_settings_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

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

const kUid = 'u-d244';

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: kUid, username: 'qa_worker', name: 'QA 근로자', email: 'qa@test.local',
      role: UserRole.USER, createdAt: DateTime(2026, 1, 1));
  @override
  bool get isAdminMode => false;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  String? get effectiveBusinessId => null;
}

String _kst(DateTime d) {
  final k = d.toUtc().add(const Duration(hours: 9));
  String p(int x) => x.toString().padLeft(2, '0');
  return '${k.year}-${p(k.month)}-${p(k.day)} ${p(k.hour)}:${p(k.minute)} KST';
}

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

void main() {
  final phase = Platform.environment['DU244_PHASE'] ?? '';
  final run = Platform.environment['DU244_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  final events = <String>[];
  final blocked = <String>[];
  final appErrors = <String>[];
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'ALfit', packageName: 'com.alfit.app', version: '1.0.0', buildNumber: '1', buildSignature: '');
  });
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  void stubChannels(String sc) {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), (call) async {
      events.add('permission ${call.method}');
      return sc == 'on' ? 1 : 0; // 1 granted → 사용자 문서 get / 0 denied → get 없음
    });
    const codec = FirebaseFirestoreHostApi.codec;
    final meta = PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false);
    for (final op in const ['queryGet', 'documentReferenceGet', 'documentReferenceSet', 'documentReferenceUpdate',
      'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult', 'transactionGet',
      'querySnapshot', 'documentReferenceSnapshot', 'aggregateQuery']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        if (op == 'documentReferenceGet' && sc == 'on') {
          final args = codec.decodeMessage(msg) as List;
          final path = (args[1] as DocumentReferenceRequest).path;
          if (path == 'users/$kUid') {
            events.add('get $path');
            return codec.encodeMessage(<Object?>[
              PigeonDocumentSnapshot(path: path, metadata: meta, data: <String?, Object?>{
                'fcmToken': 'tok-local-d244',
                'notifPrefs': <String, Object?>{UserModel.notifToMatchAlert: false},
              }),
            ]);
          }
          blocked.add('firestore get $path');
          return codec.encodeMessage(<Object?>['du244-blocked', 'get 차단: $path', null]);
        }
        blocked.add('firestore $op');
        return codec.encodeMessage(<Object?>['du244-blocked', '$op 차단', null]);
      });
    }
    m.setMockMessageHandler(fnChannel, (msg) async {
      const c = StandardMessageCodec();
      final args = (c.decodeMessage(msg) as List).first as Map;
      blocked.add('fn ${args['functionName']}');
      return c.encodeMessage(<Object?>['not-found', 'du244-blocked', null]);
    });
  }

  // 실행 전 고정 reader(순서 무관 multiset).
  final wantEvents = <String, List<String>>{
    'off': ['permission checkPermissionStatus'],
    'on': (['get users/$kUid', 'permission checkPermissionStatus']..sort()),
  };
  const sections = ['알림', '앱 정보', '도움말', '법적 고지', '계정'];
  const rows = ['푸시 알림', '시스템 알림 설정', '앱 버전', '도움말 (Q&A)', '가이드 다시 보기', '서비스 이용약관', '개인정보 처리방침',
    '위치정보 이용 동의', '로그아웃'];
  const onRows = ['알림 세부 설정'];
  const cats = ['근무 알림', '지원 현황 알림', '리뷰 알림', '계약서 알림', '급여 알림', '새 일자리 알림'];
  const tapRows = ['알림 세부 설정', '시스템 알림 설정', '도움말 (Q&A)', '가이드 다시 보기', '서비스 이용약관', '개인정보 처리방침',
    '위치정보 이용 동의', '로그아웃'];

  testWidgets('D244 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final prevDebugPrint = debugPrint;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    debugPrint = (String? m, {int? wrapWidth}) {
      if (m != null && (m.contains('❌') || m.contains('⚠️'))) appErrors.add(m);
      prevDebugPrint(m, wrapWidth: wrapWidth);
    };

    var nPump = 0, nMount = 0, nTap = 0, nDrag = 0, nPng = 0;
    // DU244 phase 한도: pump+mount ≤900, tap ≤2, drag ≤20, PNG ≤28.
    const maxFrames = 900, maxTap = 2, maxDrag = 20, maxPng = 28;
    var cur = '(시작)';
    Map<String, int> counts() => {'pump': nPump, 'pumpWidget': nMount, 'tap': nTap, 'drag': nDrag, 'png': nPng};
    Never stop(String why) {
      _out('D244-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors, 'appErrors': appErrors, 'counts': counts(), 'events': events, 'blocked': blocked})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    void budget() => need(nPump + nMount <= maxFrames && nTap <= maxTap && nDrag <= maxDrag && nPng <= maxPng, '사용량 한도 초과 ${counts()}');
    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        budget();
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    // baseline 의 RenderFlex overflow 는 결함값으로 기록만 한다(그 밖 예외는 중단). after 는 모두 중단.
    final overflow = <String>[];
    void safe(String at) {
      need(blocked.isEmpty, '$at 허용 밖 호출: $blocked');
      final ex = t.takeException();
      need(ex == null, '$at 예외: $ex');
      for (final e in errors) {
        if (!after && e.startsWith('A RenderFlex overflowed by')) {
          overflow.add('$at $e');
        } else {
          stop('$at 예외/overflow: $e');
        }
      }
      errors.clear();
      need(appErrors.isEmpty, '$at 앱 오류: ${[for (final m in appErrors) m.split(nl).first]}');
    }

    void match(String sc, String at) {
      final got = [...events]..sort();
      need(jsonEncode(got) == jsonEncode(wantEvents[sc]), '$at reader 정확값 불일치 got=$got');
      safe(at);
    }

    Finder rich(bool Function(String p) f) =>
        find.byWidgetPredicate((w) => w is RichText && f(TextLayout.plain(w.text.toPlainText())), skipOffstage: false);
    Finder? firstOf(Finder f) {
      final els = f.evaluate().toList();
      if (els.isEmpty) return null;
      final e = els.first;
      return find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    }

    double r1(double v) => double.parse(v.toStringAsFixed(1));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    bool inside(Rect r, Rect box) =>
        r.left >= box.left - 0.5 && r.top >= box.top - 0.5 && r.right <= box.right + 0.5 && r.bottom <= box.bottom + 0.5;

    ({Color color, List<String> layers}) bgOf(Element e) {
      final layers = <Color>[];
      final tags = <String>[];
      e.visitAncestorElements((a) {
        final w = a.widget;
        Color? c;
        if (w is ColoredBox) {
          c = w.color;
        } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
          c = (w.decoration as BoxDecoration).color;
        } else if (w is Material && w.type != MaterialType.transparency) {
          c = w.color ?? Theme.of(a).canvasColor;
        } else if (w is Scaffold) {
          c = w.backgroundColor ?? Theme.of(a).scaffoldBackgroundColor;
        }
        if (c == null || c.a == 0) return true;
        layers.add(c);
        tags.add('${_hex(c)}@${c.a.toStringAsFixed(2)}');
        return c.a < 1.0;
      });
      var out = layers.isEmpty ? Colors.white : layers.last;
      for (final c in layers.reversed.skip(1)) {
        out = Color.alphaBlend(c, out);
      }
      return (color: out, layers: tags);
    }

    final key = GlobalKey();
    final startKstDate = _kst(DateTime.now()).substring(0, 10);
    var prevScene = '';

    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        for (final sc in const ['off', 'on']) {
          cur = '${c.id} $sc';
          if (nMount > 0) {
            nMount++;
            budget();
            await t.pumpWidget(const SizedBox.shrink());
            await frames(1);
            match(prevScene, '$prevScene 장면 종료(unmount 직후)');
          }
          need(_kst(DateTime.now()).substring(0, 10) == startKstDate, 'KST 날짜가 실행 중 바뀜');
          prevScene = sc;
          events.clear();
          blocked.clear();
          appErrors.clear();
          overflow.clear();
          stubChannels(sc);
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          nMount++;
          budget();
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(create: (_) => _Worker()),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: navigatorKey,
                theme: RoleTheme.workerTheme,
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                home: const UserSettingsScreen(),
              ),
            ),
          ));
          await frames(20);

          final sctx = t.element(find.byType(Scaffold).first);
          final mq = MediaQuery.of(sctx);
          final locale = Localizations.localeOf(sctx).toString();
          need(locale == 'ko_KR' && mq.size == Size(c.w, c.h) && (mq.textScaler.scale(14) / 14 - c.s).abs() < 1e-9 &&
              mq.padding == EdgeInsets.zero, '조건 불일치');
          match(sc, '첫 화면');
          need(find.byType(Switch).evaluate().length == 1, '마스터 스위치 1개가 아니다');
          final pushOn = t.widget<Switch>(find.byType(Switch).first).value;
          need(pushOn == (sc == 'on'), '푸시 상태 기대와 다름 $pushOn');

          final sf = firstOf(find.descendant(of: find.byType(UserSettingsScreen), matching: find.byType(Scrollable)))!;

          if (sc == 'on') {
            // '알림 세부 설정' 펼침 — 화면 상태(setState)만 바꾼다. 저장·권한 요청 없음.
            final ex = firstOf(rich((p) => p == '알림 세부 설정'));
            need(ex != null, '세부 설정 행 없음');
            nTap++;
            budget();
            await t.tap(ex!);
            await frames(6);
            match(sc, '펼침 tap 뒤');
            need(firstOf(rich((p) => p == '근무 알림')) != null, '펼침 실패');
          }

          Map<String, Object?> textInfo(String nm, Finder? f) {
            if (f == null) return {'name': nm, 'present': false};
            final rp = t.renderObject<RenderParagraph>(f);
            final r = t.getRect(f);
            Color? fg = rp.text.style?.color;
            if (rp.text is TextSpan) {
              for (final ch in (rp.text as TextSpan).children ?? const <InlineSpan>[]) {
                fg = ch.style?.color ?? fg;
              }
            }
            final bg = bgOf(f.evaluate().first);
            final vp = t.getRect(sf);
            final inScroll = find.ancestor(of: f, matching: find.byType(Scrollable)).evaluate().isNotEmpty;
            return {
              'name': nm, 'present': true, 'plain': TextLayout.plain(rp.text.toPlainText()), 'rect': lt(r),
              'visible': inside(r, screen) && (!inScroll || inside(r, vp)), 'maxLines': rp.maxLines,
              'didExceedMaxLines': rp.didExceedMaxLines, 'fontSize': rp.text.style?.fontSize, 'fg': fg == null ? null : _hex(fg),
              'bg': _hex(bg.color), 'bgLayers': bg.layers,
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg.color).toStringAsFixed(2)),
            };
          }

          // 행 아이콘 — 제목 문단이 든 가장 가까운 Row 안의 첫 Icon 색. 묶음 면 — 가장 가까운 둥근 면(Material 또는 BoxDecoration).
          Map<String, Object?> rowOf(String title) {
            final tf = firstOf(rich((p) => p == title));
            if (tf == null) return {'title': title, 'present': false};
            // [r1] 뷰포트 밖 cache 영역에 그려진 행은 offstage 다 — 조상 matcher 도 skipOffstage: false 로 찾는다.
            final rowF = firstOf(find.ancestor(of: tf, matching: find.byType(Row, skipOffstage: false)));
            if (rowF == null) return {'title': title, 'present': false, 'why': 'row 없음'};
            final icons = find.descendant(of: rowF, matching: find.byType(Icon), skipOffstage: false);
            final ic = icons.evaluate().isEmpty ? null : t.widget<Icon>(icons.first);
            String? radius, side, face;
            tf.evaluate().first.visitAncestorElements((a) {
              final w = a.widget;
              if (w is Material && w.shape is RoundedRectangleBorder) {
                final s = w.shape! as RoundedRectangleBorder;
                radius = (s.borderRadius as BorderRadius).topLeft.x.toString();
                side = s.side.style == BorderStyle.none ? 'none' : _hex(s.side.color);
                face = w.color == null ? null : _hex(w.color!);
                return false;
              }
              if (w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).borderRadius != null) {
                final d = w.decoration as BoxDecoration;
                radius = (d.borderRadius! as BorderRadius).topLeft.x.toString();
                side = d.border == null ? 'none' : _hex((d.border! as Border).top.color);
                face = d.color == null ? null : _hex(d.color!);
                return false;
              }
              return true;
            });
            final r = t.getRect(tf);
            return {'title': title, 'present': true, 'icon': ic?.color == null ? null : _hex(ic!.color!), 'iconSize': ic?.size,
              'radius': radius, 'side': side, 'face': face, 'visible': inside(r, screen) && inside(r, t.getRect(sf))};
          }

          Map<String, Object?> recv(String nm, Finder? f) {
            if (f == null) return {'name': nm, 'present': false};
            final r = t.getRect(f);
            final ro = t.renderObject(f);
            bool hitsAt(Offset p) {
              final h = HitTestResult();
              WidgetsBinding.instance.hitTestInView(h, p, t.view.viewId);
              return h.path.any((e) => e.target == ro);
            }

            final vis = inside(r, screen) && inside(r, t.getRect(sf));
            final inner = r.deflate(2);
            return {
              'name': nm, 'present': true, 'rect': lt(r), 'w': r1(r.width), 'h': r1(r.height), 'visible': vis,
              'centerHit': vis && hitsAt(r.center),
              'edgeMidHits': vis && [inner.topCenter, inner.bottomCenter, inner.centerLeft, inner.centerRight].every(hitsAt),
              'ge48': r.width >= 48 - 0.01 && r.height >= 48 - 0.01,
            };
          }

          List<Map<String, Object?>> measure() => [
                for (final s in sections) textInfo('섹션 $s', firstOf(rich((p) => p == s))),
                textInfo('앱 버전 값', firstOf(rich((p) => p == '1.0.0'))),
                textInfo('로그아웃', firstOf(rich((p) => p == '로그아웃'))),
                textInfo('회원탈퇴', firstOf(rich((p) => p == '회원탈퇴'))),
                if (sc == 'on')
                  for (final cat in cats) textInfo('세부 $cat', firstOf(rich((p) => p == cat))),
              ];
          List<Map<String, Object?>> rowsNow() => [for (final ti in [...rows, if (sc == 'on') ...onRows]) rowOf(ti)];
          List<Map<String, Object?>> recvs() {
            final out = <Map<String, Object?>>[];
            for (final ti in tapRows) {
              final tf = firstOf(rich((p) => p == ti));
              out.add(recv('행 $ti',
                  tf == null ? null : firstOf(find.ancestor(of: tf, matching: find.byType(InkWell, skipOffstage: false)))));
            }
            final sw = find.byType(Switch).evaluate().toList();
            for (var i = 0; i < sw.length; i++) {
              final e = sw[i];
              out.add(recv('스위치 $i', find.byElementPredicate((x) => identical(x, e), skipOffstage: false)));
            }
            final del = firstOf(rich((p) => p == '회원탈퇴'));
            out.add(recv('회원탈퇴 링크',
                del == null ? null : firstOf(find.ancestor(of: del, matching: find.byType(TextButton, skipOffstage: false)))));
            return out;
          }

          void afterChecks(List<Map<String, Object?>> xs, List<Map<String, Object?>> rs, List<Map<String, Object?>> vs, String at) {
            if (!after) return;
            for (final x in xs) {
              if (x['present'] != true || x['visible'] != true) continue;
              final n = x['name']! as String;
              // [DU245] 회원탈퇴는 중립 보조색(#60646F)이다 — 위험색은 탈퇴를 강조한다(사용자 11-10).
              // [DU247] 로그아웃도 중립 행이다(본문색 #21242D) — 진입 메뉴에는 위험색을 쓰지 않는다.
              final want = (n.startsWith('섹션') || n == '로그아웃') ? '#21242D' : '#60646F';
              final cst = x['contrast'];
              need(x['fg'] == want && cst is double && cst >= 4.5, '$at 읽기색 $x');
              if (n.startsWith('섹션')) need(x['fontSize'] == 16, '$at 섹션 제목 크기 $x');
            }
            for (final r in rs) {
              if (r['present'] != true || r['visible'] != true) continue;
              need(r['icon'] == '#757575', '$at 아이콘 $r'); // [DU247] 로그아웃 포함 모두 중립
              need(r['radius'] == '16.0' && r['side'] == '#EEEEEE' && r['face'] == '#FFFFFF', '$at 묶음 면 $r');
            }
            for (final v in vs) {
              if (v['present'] != true || v['visible'] != true) continue;
              need(v['ge48'] == true && v['centerHit'] == true && v['edgeMidHits'] == true, '$at 수신자 $v');
            }
          }

          final shots = <Map<String, Object?>>[];
          final shot = 'D244-$phase-${c.id}_$sc';
          Future<void> snap(String suffix) async {
            final xs = measure();
            final rs = rowsNow();
            final vs = recvs();
            afterChecks(xs, rs, vs, suffix.isEmpty ? '첫 화면' : suffix);
            nPng++;
            budget();
            await vqCapture(t, key, '$shot$suffix', conditions: {
              'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaleFactor(기기)': c.s,
              'locale': locale, 'clock': '미주입(now=${_kst(DateTime.now())})',
            });
            shots.add({'shot': suffix.isEmpty ? 'top' : suffix, 'texts': xs, 'rows': rs, 'recv': vs,
              'pixels': r1(t.state<ScrollableState>(sf).position.pixels)});
          }

          await snap('');
          // 끝까지 0.7 viewport 씩 내린다(겹쳐 보므로 건너뛰는 행이 없다). 최대 5회.
          var k = 0;
          while (k < 5) {
            final vp = t.getRect(sf);
            final pos = t.state<ScrollableState>(sf).position;
            if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
            k++;
            nDrag++;
            budget();
            await t.dragFrom(Offset(vp.left + 24, vp.bottom - 12), Offset(0, -(vp.height * 0.7)));
            await frames(6);
            match(sc, 'drag $k 뒤');
            await snap('_d$k');
          }
          final endPos = t.state<ScrollableState>(sf).position;
          final atEnd = endPos.pixels >= endPos.maxScrollExtent - 0.5;
          // 모든 측정 대상이 한 번은 viewport 안에 보였는지(끝 도달 포함).
          final seen = <String>{};
          for (final s in shots) {
            for (final x in (s['texts']! as List).cast<Map<String, Object?>>()) {
              if (x['visible'] == true) seen.add(x['name']! as String);
            }
            for (final r in (s['rows']! as List).cast<Map<String, Object?>>()) {
              if (r['visible'] == true) seen.add('행 ${r['title']}');
            }
          }
          final wantSeen = [
            for (final s in sections) '섹션 $s', '앱 버전 값', '로그아웃', '회원탈퇴',
            if (sc == 'on') for (final k2 in cats) '세부 $k2',
            for (final ti in [...rows, if (sc == 'on') ...onRows]) '행 $ti',
          ];
          final missed = [for (final w in wantSeen) if (!seen.contains(w)) w];
          if (after) need(atEnd && missed.isEmpty, '끝 도달/관측 누락 atEnd=$atEnd missed=$missed');
          _out('D244 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'events': [...events]..sort(), 'overflow': overflow,
                'atEnd': atEnd, 'missed': missed, 'shots': shots, 'counts': counts(), 'kst': _kst(DateTime.now())})}');
        }
      }
      nMount++;
      budget();
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      match(prevScene, 'END 전');
      _out('D244-END ${jsonEncode({'counts': counts(), 'startKstDate': startKstDate, 'endKst': _kst(DateTime.now())})}');
    } finally {
      FlutterError.onError = prevOnError;
      debugPrint = prevDebugPrint;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
