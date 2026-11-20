// ignore_for_file: depend_on_referenced_packages
// [DU240 S062 슈퍼관리자 홈 시안 정렬 교정 baseline/after] 자체검토239(Codex 한도 중 Claude 판정) + 사용자 11-10 '디자인 시안도 같이'.
//   v2: 흰 머리·굵은 섹션 제목·흰 묶음 카드(S010 체계)로 바꾼 후보를 baseline(구 화면)과 같은 조건에서 잰다.
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU240_RUN=1 이고 DU240_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   standalone(MaterialApp home: const AdminHomeScreen()) — main.dart 역할 분기·shell 은 관측하지 않는다.
//   reader: production 에 주입 seam 이 없어 Firestore pigeon `aggregateQuery` 채널을 대역한다(users·businesses count).
//   그 밖 Firestore·Functions 채널은 막고 기록한다. 탭·push·로그아웃·FCM 이동 실행 0.
//   장면 3(정상·실패·긴 이름+알림 25+) × W360/1.0·B320/2.0 = phase 당 6 조건.
//   baseline 에서 머리 1행 RenderFlex overflow 는 사전 예상 결함값으로 기록만 한다(그 밖 예외는 중단). after 는 0 이어야 한다.
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
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/super_admin_home_screen.dart';
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

const kSA = 'sa-local-d240';
const kLongName = '알렉산드로 크리스티아누 페르난데스 김';
const kFail = 'du240 local network failure';

class _SA extends UserProvider {
  _SA(this.n);
  final String n;
  @override
  UserModel? get currentUser => UserModel(uid: kSA, username: 'sa', name: n, email: 'sa@test.local',
      role: UserRole.SUPER_ADMIN, createdAt: DateTime(2026, 1, 1));
  @override
  bool get isSuperAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => false;
}

/// 알림 배지 값만 고정한다(구독·조회 없음).
class _Notif extends NotificationProvider {
  _Notif(this.u, this.more, this.err);
  final int u;
  final bool more;
  final bool err;
  @override
  int get unreadCount => u;
  @override
  bool get hasMore => more;
  @override
  bool get hasError => err;
}

String _kst(DateTime d) {
  final k = d.toUtc().add(const Duration(hours: 9));
  String p(int x) => x.toString().padLeft(2, '0');
  return '${k.year}-${p(k.month)}-${p(k.day)} ${p(k.hour)}:${p(k.minute)} KST';
}

String _b64(ByteData? msg) =>
    msg == null ? 'null' : base64Encode(msg.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes));

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
  final phase = Platform.environment['DU240_PHASE'] ?? '';
  final run = Platform.environment['DU240_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  final events = <String>[];
  final blocked = <String>[];
  final harness = <Map<String, Object?>>[];
  final appErrors = <String>[];
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  var scene = '';
  void stubChannels() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = FirebaseFirestoreHostApi.codec;
    m.setMockMessageHandler('$base.aggregateQuery', (msg) async {
      try {
        final args = codec.decodeMessage(msg) as List;
        final path = args[1] as String;
        final qs = (args[4] as List).map((q) => (q as AggregateQuery).type.name).join(',');
        events.add('count $path [$qs] source=${args[3]} group=${args[5]}');
        if (scene == 'fail' && path == 'businesses') {
          return codec.encodeMessage(<Object?>['unavailable', kFail, null]);
        }
        final n = switch (path) { 'users' => 123456, 'businesses' => 1234, _ => -1 };
        if (n < 0) {
          blocked.add('count $path');
          return codec.encodeMessage(<Object?>['du240-blocked', 'count 차단: $path', null]);
        }
        return codec.encodeMessage(<Object?>[
          <Object?>[AggregateQueryResponse(type: AggregateType.count, value: n.toDouble())],
        ]);
      } catch (e, st) {
        harness.add({'handler': 'aggregateQuery', 'bytes': _b64(msg), 'error': '$e', 'stack': '$st'.split(nl).take(8).toList()});
        return codec.encodeMessage(<Object?>['du240-harness', '대역 오류', null]);
      }
    });
    for (final op in const ['queryGet', 'documentReferenceGet', 'documentReferenceSet', 'documentReferenceUpdate',
      'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult', 'transactionGet',
      'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        blocked.add('firestore $op');
        return codec.encodeMessage(<Object?>['du240-blocked', '$op 차단', null]);
      });
    }
    m.setMockMessageHandler(fnChannel, (msg) async {
      blocked.add('functions call');
      return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'du240-blocked', null]);
    });
  }

  // ── 실행 전 고정 reader(정규형 multiset, 순서 무관) ──
  final wantEvents = (['count users [count] source=0 group=false', 'count businesses [count] source=0 group=false']..sort());
  bool appErrorsOk(String sc, List<String> firsts) {
    if (sc != 'fail') return firsts.isEmpty;
    return firsts.length == 1 && firsts.first.startsWith('❌ 슈퍼관리자 통계 로드 실패: ') && firsts.first.contains(kFail);
  }

  testWidgets('D240 $phase', (t) async {
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
    // DU240 v2 phase 한도: pump+mount ≤800, tap 0, drag ≤2(B320 정상만), PNG ≤8.
    const maxFrames = 800, maxTap = 0, maxDrag = 2, maxPng = 8;
    var cur = '(시작)';
    Map<String, int> counts() => {'pump': nPump, 'pumpWidget': nMount, 'tap': nTap, 'drag': nDrag, 'png': nPng};
    Never stop(String why) {
      _out('D240-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors, 'appErrors': appErrors, 'harness': harness, 'counts': counts(), 'events': events, 'blocked': blocked})}');
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

    // 예외: baseline 의 RenderFlex overflow 만 결함값으로 남기고(장면 기록), 그 밖은 중단. after 는 모두 중단.
    final overflow = <String>[];
    void safe(String at) {
      need(harness.isEmpty, '$at 대역 오류: $harness');
      need(blocked.isEmpty, '$at 허용 밖 채널 호출: $blocked');
      final ex = t.takeException();
      need(ex == null, '$at 예외: $ex');
      for (final e in errors) {
        if (!after && e.startsWith('A RenderFlex overflowed by')) {
          overflow.add(e);
        } else {
          stop('$at 예외/overflow: $e');
        }
      }
      errors.clear();
    }

    void match(String sc, String at) {
      final got = [...events]..sort();
      need(jsonEncode(got) == jsonEncode(wantEvents), '$at reader 정확값 불일치 got=$got');
      final firsts = [for (final m in appErrors) m.split(nl).first];
      need(appErrorsOk(sc, firsts), '$at 앱 오류 첫 줄 불일치 $firsts');
      safe(at);
    }

    Finder rich(bool Function(String p) f, {Finder? within}) {
      final m = find.byWidgetPredicate((w) => w is RichText && f(TextLayout.plain(w.text.toPlainText())), skipOffstage: false);
      return within == null ? m : find.descendant(of: within, matching: m, skipOffstage: false);
    }

    Finder? firstOf(Finder f) {
      final els = f.evaluate().toList();
      if (els.isEmpty) return null;
      final e = els.first;
      return find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    }

    bool inInkWell(Element e) {
      var found = false;
      e.visitAncestorElements((a) {
        if (a.widget is InkWell) {
          found = true;
          return false;
        }
        return true;
      });
      return found;
    }

    // 메뉴 타일 밖(섹션 라벨)과 안(부제)을 가른다 — '준비 중'은 둘 다 있다.
    Finder? richWhere(String s, {required bool tile, int index = 0}) {
      final els = rich((p) => p == s).evaluate().where((e) => inInkWell(e) == tile).toList();
      if (els.length <= index) return null;
      final e = els[index];
      return find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    }

    double r1(double v) => double.parse(v.toStringAsFixed(1));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    bool inside(Rect r, Rect box) =>
        r.left >= box.left - 0.5 && r.top >= box.top - 0.5 && r.right <= box.right + 0.5 && r.bottom <= box.bottom + 0.5;

    // 실제 배경 — 조상의 칠을 불투명한 것까지 모아 합성. 그라데이션은 첫 색(위쪽)으로 근사하고 표시한다.
    ({Color color, List<String> layers}) bgOf(Element e) {
      final layers = <Color>[];
      final tags = <String>[];
      e.visitAncestorElements((a) {
        final w = a.widget;
        Color? c;
        var tag = '';
        if (w is ColoredBox) {
          c = w.color;
        } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
          final d = w.decoration as BoxDecoration;
          c = d.color;
          if (c == null && d.gradient is LinearGradient) {
            c = (d.gradient! as LinearGradient).colors.first;
            tag = '(gradient-top)';
          }
        } else if (w is Material && w.type != MaterialType.transparency) {
          c = w.color ?? Theme.of(a).canvasColor;
        } else if (w is Scaffold) {
          c = w.backgroundColor ?? Theme.of(a).scaffoldBackgroundColor;
        }
        if (c == null || c.a == 0) return true;
        layers.add(c);
        tags.add('${_hex(c)}@${c.a.toStringAsFixed(2)}$tag');
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
        for (final sc in const ['normal', 'fail', 'long']) {
          cur = '${c.id} $sc';
          if (nMount > 0) {
            nMount++;
            budget();
            await t.pumpWidget(const SizedBox.shrink());
            await frames(1);
            match(prevScene, '$prevScene 장면 종료(unmount 직후)');
          }
          need(_kst(DateTime.now()).substring(0, 10) == startKstDate, 'KST 날짜가 실행 중 바뀜');
          scene = sc;
          prevScene = sc;
          events.clear();
          blocked.clear();
          appErrors.clear();
          overflow.clear();
          stubChannels();
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          final name = sc == 'long' ? kLongName : '김관리';
          nMount++;
          budget();
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(create: (_) => _SA(name)),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => sc == 'long' ? _Notif(25, true, false) : _Notif(0, false, false)),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: navigatorKey,
                theme: RoleTheme.superAdminTheme,
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                home: const AdminHomeScreen(),
              ),
            ),
          ));
          await frames(20);

          final sctx = t.element(find.byType(Scaffold).first);
          final mq = MediaQuery.of(sctx);
          final locale = Localizations.localeOf(sctx).toString();
          final env = {
            'locale': locale, 'size': '${mq.size.width.toInt()}x${mq.size.height.toInt()}', 'dpr': mq.devicePixelRatio,
            'scaler': mq.textScaler.scale(14) / 14, 'padding': '${mq.padding}', 'viewInsets': '${mq.viewInsets}',
            'orientation': '${MediaQuery.orientationOf(sctx)}', 'themeFont': Theme.of(sctx).textTheme.bodyMedium?.fontFamily,
          };
          need(locale == 'ko_KR', 'locale $locale');
          need(mq.size == Size(c.w, c.h) && mq.devicePixelRatio == 1.0 && (mq.textScaler.scale(14) / 14 - c.s).abs() < 1e-9 &&
              mq.padding == EdgeInsets.zero && mq.viewInsets == EdgeInsets.zero, '조건 불일치 $env');
          match(sc, '캡처 전');
          need(rich((p) => p == '모든 사업장').evaluate().isNotEmpty && rich((p) => p == '전체 회원').evaluate().isNotEmpty, '장면 문구 누락');

          Finder? scrollF() {
            final f = find.descendant(of: find.byType(AdminHomeScreen), matching: find.byType(Scrollable));
            return f.evaluate().isEmpty ? null : firstOf(f);
          }

          Map<String, Object?> textInfo(String nm, Finder? f) {
            if (f == null) return {'name': nm, 'present': false};
            final rp = t.renderObject<RenderParagraph>(f);
            final r = t.getRect(f);
            final plain = TextLayout.plain(rp.text.toPlainText());
            final display = rp.text.toPlainText();
            final byLine = <int, StringBuffer>{};
            final lineBoxes = <int, Rect>{};
            for (var i = 0; i < display.length; i++) {
              final bs = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
              if (bs.isEmpty) continue;
              final k = bs.first.top.round();
              byLine.putIfAbsent(k, () => StringBuffer()).write(display[i]);
              final box = bs.first.toRect().shift(r.topLeft);
              lineBoxes.update(k, (v) => v.expandToInclude(box), ifAbsent: () => box);
            }
            final keys = byLine.keys.toList()..sort();
            Color? fg = rp.text.style?.color;
            if (rp.text is TextSpan) {
              for (final ch in (rp.text as TextSpan).children ?? const <InlineSpan>[]) {
                fg = ch.style?.color ?? fg;
              }
            }
            final el = f.evaluate().first;
            final bg = bgOf(el);
            final textAnc = find.ancestor(of: f, matching: find.byType(Text));
            final sem = textAnc.evaluate().isEmpty ? null : t.widget<Text>(textAnc.first).semanticsLabel;
            final inScroll = find.ancestor(of: f, matching: find.byType(Scrollable)).evaluate().isNotEmpty;
            final sf = scrollF();
            final vp = sf == null ? null : t.getRect(sf);
            return {
              'name': nm, 'present': true, 'plain': plain, 'ctl': display != plain, 'semanticsLabel': sem, 'rect': lt(r), 'inScreen': inside(r, screen),
              'scrollBody': inScroll, 'inViewport': inScroll && vp != null ? inside(r, vp) : null,
              'maxLines': rp.maxLines, 'didExceedMaxLines': rp.didExceedMaxLines,
              'lines': [for (final k in keys) TextLayout.plain(byLine[k]!.toString())],
              'lineBoxes': [for (final k in keys) lt(lineBoxes[k]!)],
              'fontSize': rp.text.style?.fontSize, 'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg.color), 'bgLayers': bg.layers,
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg.color).toStringAsFixed(2)),
            };
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

            final inner = r.deflate(2);
            return {
              'name': nm, 'present': true, 'rect': lt(r), 'w': r1(r.width), 'h': r1(r.height),
              'centerHit': inside(r, screen) && hitsAt(r.center),
              'edgeHits': inside(r, screen) && [inner.topLeft, inner.topRight, inner.bottomLeft, inner.bottomRight].every(hitsAt),
              // [r1] 둥근 버튼(반경 12)은 모서리 안쪽 점이 원래 hit 영역 밖이다 — 네 변의 가운데(2px 안쪽)로 경계 hit 를 잰다.
              'edgeMidHits': inside(r, screen) &&
                  [inner.topCenter, inner.bottomCenter, inner.centerLeft, inner.centerRight].every(hitsAt),
              'ge48': r.width >= 48 - 0.01 && r.height >= 48 - 0.01, 'inScreen': inside(r, screen),
            };
          }

          final head = [
            recv('알림', firstOf(find.ancestor(of: find.byIcon(Icons.notifications_outlined), matching: find.byType(InkWell)))),
            recv('로그아웃', firstOf(find.ancestor(of: find.byIcon(Icons.logout), matching: find.byType(InkWell)))),
          ];
          // [r2] 값 finder 는 잴 때마다 새로 찾는다 — drag 로 멀리 스크롤하면 이전 요소가 해제된다.
          Finder? valueUsers() => sc == 'fail' ? null : firstOf(rich((p) => p.replaceAll(',', '') == '123456명'));
          Finder? valueBiz() => sc == 'fail' ? null : firstOf(rich((p) => p.replaceAll(',', '') == '1234개'));
          List<Map<String, Object?>> texts() => [
                textInfo('ALfit', firstOf(rich((p) => p == 'ALfit'))),
                textInfo('E7 최고', firstOf(rich((p) => p == '최고' || p == '최고관리자'))),
                textInfo('인사', firstOf(rich((p) => p == '안녕하세요,'))),
                textInfo('E3 이름', firstOf(rich((p) => p == '$name님'))),
                textInfo('E6 회원 값', valueUsers()),
                textInfo('E6 사업장 값', valueBiz()),
                textInfo('실패 값', sc == 'fail' ? firstOf(rich((p) => p == '확인 못함')) : null),
                textInfo('E5 통계 라벨 회원', firstOf(rich((p) => p == '전체 회원'))),
                textInfo('E5 통계 라벨 사업장', firstOf(rich((p) => p == '전체 사업장'))),
                textInfo('E5 섹션 플랫폼 현황', richWhere('플랫폼 현황', tile: false)),
                textInfo('E5 섹션 관리', richWhere('관리', tile: false)),
                textInfo('E5 섹션 시스템', richWhere('시스템', tile: false)),
                textInfo('E5 섹션 개인', richWhere('개인', tile: false)),
                textInfo('E5 섹션 준비 중', richWhere('준비 중', tile: false)),
                textInfo('E4 부제 모든 사업장', firstOf(rich((p) => p == '전체 사업장 현황 및 관리'))),
                textInfo('E4 부제 사용자', firstOf(rich((p) => p == '회원 목록 조회 및 정보 관리'))),
                textInfo('E4 부제 시스템 설정', firstOf(rich((p) => p == '신뢰도 규칙·배지·임금·공고 설정 관리'))),
                textInfo('E4 부제 설정', firstOf(rich((p) => p == '개인 설정 및 테마'))),
                textInfo('준비 중 설명 공고 모니터링', firstOf(rich((p) => p == '전체 공고 현황 분석'))),
                textInfo('E4 부제 준비 중(전체 통계)', richWhere('준비 중', tile: true, index: 1)),
                textInfo('준비 중 제목 전체 통계', firstOf(rich((p) => p == '전체 통계'))),
              ];
          Map<String, Object?> named(List<Map<String, Object?>> xs, String n) => xs.firstWhere((x) => x['name'] == n);

          // 줄 경계가 공백이거나 허용 구분자(·, 쉼표) 바로 뒤일 때만 참 — 낱말·숫자 중간 끊김을 잡는다.
          bool wordSafe(List<String> lines, String plain, Set<String> after) {
            var pos = 0;
            for (var i = 0; i < lines.length; i++) {
              final seg = lines[i].trim();
              while (pos < plain.length && plain[pos] == ' ') {
                pos++;
              }
              if (!plain.startsWith(seg, pos)) return false;
              pos += seg.length;
              if (i < lines.length - 1) {
                final ok = (pos < plain.length && plain[pos] == ' ') || (pos > 0 && after.contains(plain[pos - 1]));
                if (!ok) return false;
              }
            }
            while (pos < plain.length && plain[pos] == ' ') {
              pos++;
            }
            return pos == plain.length;
          }

          // after 성공조건(캡처 전). baseline 은 같은 값을 결함값으로 기록만 한다.
          void afterChecks(List<Map<String, Object?>> xs, String at, {bool all = false}) {
            if (!after) return;
            for (final x in xs) {
              final n = x['name']! as String;
              if (x['present'] != true) continue;
              final visible = x['scrollBody'] == true ? x['inViewport'] == true : x['inScreen'] == true;
              if (!all && !visible) continue;
              final cst = x['contrast'];
              // v2 색: 섹션 제목·이름은 본문색, 통계 라벨·설명·준비 중 표시·준비 중 제목은 보조색.
              final wantFg = n.startsWith('E5 섹션') || n == 'E3 이름'
                  ? '#21242D'
                  : (n.startsWith('E5') || n.startsWith('E4') || n.startsWith('준비 중') ? '#60646F' : null);
              if (wantFg != null) need(x['fg'] == wantFg && cst is double && cst >= 4.5, '$at 읽기색 $x');
              if (n.startsWith('E4') || n.startsWith('E6') || n == 'E3 이름' || n == '실패 값') {
                final lines = (x['lines']! as List).cast<String>();
                final seps = n.startsWith('E6') ? const {','} : const {'·'};
                need(x['maxLines'] == null && x['didExceedMaxLines'] == false && wordSafe(lines, x['plain']! as String, seps),
                    '$at 전문·낱말 줄바꿈 $x');
                if (x['ctl'] == true) need(x['semanticsLabel'] == x['plain'], '$at semantics 원문 $x');
              }
              if (n == 'E7 최고') need(x['plain'] == '최고관리자' && cst is double && cst >= 4.5 && x['inScreen'] == true, '$at 역할 배지 $x');
              if (n == 'ALfit' || n == 'E3 이름') need(x['inScreen'] == true, '$at 머리 글자 화면 밖 $x');
            }
          }

          final t0 = texts();
          if (after) {
            for (final h in head) {
              need(h['present'] == true && h['ge48'] == true && h['inScreen'] == true && h['centerHit'] == true && h['edgeMidHits'] == true,
                  'E1·E2 머리 행동 $h');
            }
            final a = head[0]['rect']! as List<double>;
            final b = head[1]['rect']! as List<double>;
            need(!Rect.fromLTRB(a[0], a[1], a[2], a[3]).deflate(0.5).overlaps(Rect.fromLTRB(b[0], b[1], b[2], b[3]).deflate(0.5)),
                'E2 receiver 겹침');
            if (sc != 'fail') {
              need(named(t0, 'E6 회원 값')['plain'] == '123,456명' && named(t0, 'E6 사업장 값')['plain'] == '1,234개', 'E6 쉼표 ${named(t0, 'E6 회원 값')}');
            }
          }
          if (sc == 'fail') {
            need(rich((p) => p == '확인 못함').evaluate().length == 2 && valueUsers() == null, '실패 장면 값: 확인 못함 2');
          }
          afterChecks(t0, '첫 화면');
          final shot = 'D240-$phase-${c.id}_$sc';
          nPng++;
          budget();
          await vqCapture(t, key, shot, conditions: {
            'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaleFactor(기기)': c.s,
            'locale': locale, 'theme': 'RoleTheme.superAdminTheme', 'clock': '미주입(now=${_kst(DateTime.now())})',
            'fixture': 'users 123456 · businesses 1234${sc == 'fail' ? ' · businesses count 실패' : ''}${sc == 'long' ? ' · 긴 이름 · 알림 25+' : ''}',
          });

          // ── 지정 읽기 도달(정상 장면, 큰 글자 두 조건만, drag ≤2, drag 마다 PNG) ──
          final reach = <String, int>{};
          final passed = <String>[];
          final details = <Map<String, Object?>>[];
          if (sc == 'normal' && c.id == 'B320') {
            final order = <String, Finder? Function()>{
              '시스템 설정 부제': () => firstOf(rich((p) => p == '신뢰도 규칙·배지·임금·공고 설정 관리')),
              '설정 부제': () => firstOf(rich((p) => p == '개인 설정 및 테마')),
              '섹션 준비 중': () => richWhere('준비 중', tile: false),
              '전체 통계 제목': () => firstOf(rich((p) => p == '전체 통계')),
              '전체 통계 부제': () => richWhere('준비 중', tile: true, index: 1),
            };
            void look(int k) {
              final sf = scrollF();
              if (sf == null) return;
              final vp = t.getRect(sf);
              for (final e in order.entries) {
                if (reach.containsKey(e.key)) continue;
                final f = e.value();
                if (f == null) continue;
                final r = t.getRect(f);
                if (inside(r, vp) && inside(r, screen)) reach[e.key] = k;
              }
            }

            look(0);
            for (var k = 1; k <= 2; k++) {
              if (reach.length + passed.length == order.length) break;
              final sf = scrollF();
              if (sf == null) break;
              final vp = t.getRect(sf);
              final pos = t.state<ScrollableState>(sf).position;
              if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
              // 아직 못 본 대상 중 첫 것: 아랫변을 viewport 안 8px 로, 단 그 대상의 윗변이 viewport 위로 나가지 않게.
              //   이미 위로 지나간 대상은 '지나감'으로 기록하고 다음 대상을 기준으로 삼는다(238 결손 교정).
              double? want;
              for (final e in order.entries) {
                if (reach.containsKey(e.key) || passed.contains(e.key)) continue;
                final f = e.value();
                if (f == null) continue;
                final r = t.getRect(f);
                if (r.top < vp.top - 0.5) {
                  passed.add(e.key);
                  continue;
                }
                // [r1] 첫 미도달 대상을 viewport 위쪽 8px 로 올린다(최대 진행) — 아래 대상들이 함께 들어온다.
                final room = r.top - (vp.top + 8);
                want = room + 20;
                break;
              }
              if (want == null || want <= 20) break;
              final from = Offset(vp.left + 24, vp.bottom - 12);
              final d = math.min(want, from.dy - vp.top - 12);
              nDrag++;
              budget();
              final px0 = pos.pixels;
              await t.dragFrom(from, Offset(0, -d));
              await frames(6);
              match(sc, '상세 drag 뒤');
              final px1 = t.state<ScrollableState>(sf).position.pixels;
              look(k);
              final dt = texts();
              afterChecks(dt, 'drag $k');
              details.add({'drag': k, 'request': r1(d), 'pixels': [r1(px0), r1(px1)], 'texts': dt});
              nPng++;
              budget();
              await vqCapture(t, key, '${shot}_d$k', conditions: {'phase': phase, 'scene': '$sc-detail', 'drag': k, 'textScaleFactor(기기)': c.s});
            }
            if (after) need(reach.length == order.length, '지정 도달 reach=$reach passed=$passed');
          }
          need(_kst(DateTime.now()).substring(0, 10) == startKstDate, 'KST 날짜가 실행 중 바뀜');
          _out('D240 ${jsonEncode({
                'phase': phase, 'cond': c.id, 'scene': sc, 'env': env, 'events': [...events]..sort(), 'appErrors': appErrors,
                'overflow': overflow, 'head': head, 'texts': t0, 'reach': reach, 'passed': passed, 'details': details,
                'counts': counts(), 'kst': _kst(DateTime.now()),
              })}');
        }
      }
      nMount++;
      budget();
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      match(prevScene, 'END 전');
      _out('D240-END ${jsonEncode({'counts': counts(), 'startKstDate': startKstDate, 'endKst': _kst(DateTime.now())})}');
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
