// ignore_for_file: depend_on_referenced_packages
// [DU251 S065 지원 전 준비사항 시안 정렬 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU251_RUN=1 이고 DU251_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   standalone(home: ApplyPrerequisitesScreen) + UserProvider 대역. 외부 채널 없음, tap 0.
//   장면 5(none·some·ready·restricted·blacklisted) × W360/1.0·B320/2.0.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/apply_prerequisites_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
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

class _P extends UserProvider {
  _P(this.sc);
  final String sc;
  @override
  UserModel? get currentUser {
    final id = sc == 'some' || sc == 'ready';
    final acct = sc == 'some' || sc == 'ready';
    return UserModel(
      uid: 'u-d251', username: 'qa', name: '김근로', email: 'qa@test.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구'), accountStatus: 'active',
      passVerifiedAt: DateTime(2026, 1, 1),
      idCardImagePath: id ? 'users/u-d251/id.png' : null,
      isIdVerified: sc == 'ready',
      bankName: acct ? '국민은행' : null, accountNumber: acct ? '1234' : null, accountHolder: acct ? '김근로' : null,
      bankbookImagePath: sc == 'ready' ? 'users/u-d251/bb.png' : null,
      isBlacklisted: sc == 'blacklisted',
      restrictedUntil: sc == 'restricted' ? DateTime.now().add(const Duration(days: 2)) : null,
    );
  }

  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => false;
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
  final phase = Platform.environment['DU251_PHASE'] ?? '';
  final run = Platform.environment['DU251_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const titles = ['신분증 등록', '신분증 인증', '계좌 정보 등록', '통장사본 등록'];
  const readyDesc = ['신분증이 등록되어 있습니다', '신분증 인증이 완료되었습니다', '계좌 정보가 등록되어 있습니다', '통장사본이 등록되어 있습니다'];
  const notReadyDesc = ['신분증 등록이 필요합니다.', '단기 공고 지원 시 신분증 인증이 필요합니다.', '계좌 정보 등록이 필요합니다.', '통장사본 등록이 필요합니다.'];

  testWidgets('D251 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nDrag = 0, nPng = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D251-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 800 && nDrag <= 40 && nPng <= 50, '사용량 한도');
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    final overflow = <String>[];
    void safe(String at) {
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
    }

    Finder rich(bool Function(String p) f) =>
        find.byWidgetPredicate((w) => w is RichText && f(TextLayout.plain(w.text.toPlainText())), skipOffstage: false);
    Finder? nth(Finder f, int i) {
      final els = f.evaluate().toList();
      if (els.isEmpty) return null;
      final e = i < 0 ? els.last : els[i];
      return find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    }

    double r1(double v) => double.parse(v.toStringAsFixed(1));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    bool inside(Rect r, Rect b) => r.left >= b.left - 0.5 && r.top >= b.top - 0.5 && r.right <= b.right + 0.5 && r.bottom <= b.bottom + 0.5;

    Color bgOf(Element e) {
      final layers = <Color>[];
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
        return c.a < 1.0;
      });
      var out = layers.isEmpty ? Colors.white : layers.last;
      for (final c in layers.reversed.skip(1)) {
        out = Color.alphaBlend(c, out);
      }
      return out;
    }

    final key = GlobalKey();
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        for (final sc in const ['none', 'some', 'ready', 'restricted', 'blacklisted']) {
          cur = '${c.id} $sc';
          final flex = sc != 'some';
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          safe('장면 종료');
          overflow.clear();
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
            create: (_) => _P(sc),
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.workerTheme,
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [Locale('ko', 'KR')],
                home: ApplyPrerequisitesScreen(isFlexType: flex),
              ),
            ),
          ));
          await frames(8);
          safe('첫 화면');
          Finder? sfOf() {
            final f = find.descendant(of: find.byType(ApplyPrerequisitesScreen), matching: find.byType(Scrollable));
            return f.evaluate().isEmpty ? null : nth(f, 0);
          }

          Map<String, Object?> info(String nm, Finder? f) {
            if (f == null) return {'name': nm, 'present': false};
            final rp = t.renderObject<RenderParagraph>(f);
            final r = t.getRect(f);
            final fg = rp.text.style?.color;
            final bg = bgOf(f.evaluate().first);
            final sf = sfOf();
            final vp = sf == null ? screen : t.getRect(sf);
            String? radius, side, face;
            f.evaluate().first.visitAncestorElements((a) {
              final w = a.widget;
              if (w is Material && w.shape is RoundedRectangleBorder) {
                final s = w.shape! as RoundedRectangleBorder;
                final br = s.borderRadius;
                if (br is BorderRadius) radius = br.topLeft.x.toString();
                side = _hex(s.side.color);
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
            return {
              'name': nm, 'present': true, 'rect': lt(r), 'visible': inside(r, screen) && inside(r, vp),
              'fontSize': rp.text.style?.fontSize, 'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
              'radius': radius, 'side': side, 'face': face,
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

            final sf = sfOf();
            final vis = inside(r, screen) && (sf == null || inside(r, t.getRect(sf)));
            final inner = r.deflate(2);
            return {
              'name': nm, 'present': true, 'rect': lt(r), 'w': r1(r.width), 'h': r1(r.height), 'visible': vis,
              'centerHit': vis && hitsAt(r.center),
              'edgeMidHits': vis && [inner.topCenter, inner.bottomCenter, inner.centerLeft, inner.centerRight].every(hitsAt),
              'ge48': r.width >= 48 - 0.01 && r.height >= 48 - 0.01,
            };
          }

          List<Map<String, Object?>> measure() {
            final out = <Map<String, Object?>>[
              info('안내 제목', nth(rich((p) => p == '지원 전 준비사항'), 0)),
              info('안내 설명', nth(rich((p) => p.endsWith('완료해야 지원할 수 있습니다.')), 0)),
              info('배너', nth(rich((p) => p.contains('제한')), 0)),
              info('다시 확인', nth(rich((p) => p == '다시 확인'), 0)),
              info('지원하기 CTA', nth(find.descendant(of: find.byType(ElevatedButton), matching: rich((p) => p == '지원하기')), 0)),
            ];
            for (var i = 0; i < 4; i++) {
              out.add({...info('제목 ${titles[i]}', nth(rich((p) => p == titles[i]), 0)), 'kind': 'title'});
              out.add({...info('준비됨 ${titles[i]}', nth(rich((p) => p == readyDesc[i]), 0)), 'kind': 'ready'});
              out.add({...info('미준비 ${titles[i]}', nth(rich((p) => p == notReadyDesc[i]), 0)), 'kind': 'notReady'});
            }
            for (var i = 1; i <= 4; i++) {
              out.add({...info('순번 $i', nth(rich((p) => p == '$i.'), 0)), 'kind': 'index'});
            }
            // 상태 아이콘(글리프 RichText) — check_circle / radio_button_unchecked
            for (final ic in [Icons.check_circle, Icons.radio_button_unchecked]) {
              final f = find.byWidgetPredicate((w) => w is Icon && w.icon == ic, skipOffstage: false);
              var k = 0;
              for (final e in f.evaluate()) {
                final rt = nth(find.descendant(of: find.byElementPredicate((x) => identical(x, e), skipOffstage: false),
                    matching: find.byType(RichText), skipOffstage: false), 0);
                out.add({...info('상태 ${ic == Icons.check_circle ? '준비' : '미준비'} $k', rt), 'kind': 'icon'});
                k++;
              }
            }
            return out;
          }

          List<Map<String, Object?>> recvs() {
            final out = <Map<String, Object?>>[];
            final f = rich((p) => p == '서류 관리');
            var k = 0;
            for (final e in f.evaluate()) {
              final tf = find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
              final b = find.ancestor(of: tf, matching: find.byType(TextButton));
              out.add(recv('서류 관리 $k', b.evaluate().isEmpty ? null : nth(b, 0)));
              k++;
            }
            return out;
          }

          void afterChecks(List<Map<String, Object?>> xs, List<Map<String, Object?>> vs, String at) {
            if (!after) return;
            for (final x in xs) {
              if (x['present'] != true || x['visible'] != true) continue;
              final n = x['name']! as String;
              final k = x['kind'];
              final cst = x['contrast'];
              if (k == 'icon') {
                need(cst is double && cst >= 3.0, '$at 상태 아이콘 $x');
                continue;
              }
              String? want;
              if (k == 'title') want = '#21242D';
              if (k == 'ready') want = '#166534';
              if (k == 'notReady' || k == 'index' || n == '안내 설명') want = '#60646F';
              if (n == '배너') want = sc == 'blacklisted' ? '#B42318' : '#946200';
              need(cst is double && cst >= 4.5 && (want == null || x['fg'] == want), '$at 읽기색 $x');
              if (k == 'title') need(x['radius'] == '16.0' && x['side'] == '#EEEEEE' && x['face'] == '#FFFFFF', '$at 묶음 면 $x');
            }
            for (final v in vs) {
              if (v['present'] != true || v['visible'] != true) continue;
              need(v['ge48'] == true && v['centerHit'] == true && v['edgeMidHits'] == true, '$at 수신자 $v');
            }
          }

          final shots = <Map<String, Object?>>[];
          Future<void> snap(String suffix) async {
            final xs = measure();
            final vs = recvs();
            afterChecks(xs, vs, suffix.isEmpty ? '첫 화면' : suffix);
            nPng++;
            await vqCapture(t, key, 'D251-$phase-${c.id}_$sc$suffix', conditions: {
              'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
            });
            final sf = sfOf();
            shots.add({'shot': suffix.isEmpty ? 'top' : suffix, 'texts': xs, 'recv': vs,
              'pixels': sf == null ? null : r1(t.state<ScrollableState>(sf).position.pixels)});
          }

          await snap('');
          var atEnd = true;
          if (sfOf() != null) {
            var k = 0;
            while (k < 8) {
              final sf = sfOf()!;
              final vp = t.getRect(sf);
              final pos = t.state<ScrollableState>(sf).position;
              if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
              k++;
              nDrag++;
              await t.dragFrom(Offset(vp.left + 24, vp.top + vp.height * 0.6), Offset(0, -(vp.height * 0.5)));
              await frames(6);
              safe('drag $k 뒤');
              await snap('_d$k');
            }
            final pos = t.state<ScrollableState>(sfOf()!).position;
            atEnd = pos.pixels >= pos.maxScrollExtent - 0.5;
          }
          if (after) need(atEnd, '끝 도달 실패');
          _out('D251 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'overflow': overflow, 'atEnd': atEnd, 'shots': shots,
                'counts': {'pump': nPump, 'drag': nDrag, 'png': nPng}})}');
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D251-END ${jsonEncode({'pump': nPump, 'drag': nDrag, 'png': nPng})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
