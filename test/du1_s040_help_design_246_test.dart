// ignore_for_file: depend_on_referenced_packages
// [DU246 S040 도움말 시안 정렬 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU246_RUN=1 이고 DU246_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   standalone(MaterialApp home: HelpScreen(load: 대역)) — FAQ 읽기는 주입 대역이라 Firebase 채널을 쓰지 않는다.
//   장면 5(user·admin 내장 FAQ / server 긴 분류·질문 / error / empty) × W360/1.0·B320/2.0.
//   tap 은 질문 펼침만(user·server 첫 질문, 화면 상태).
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

import 'package:ALfit/models/core/help_faq_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/help_screen.dart';
import 'package:ALfit/services/help_faq_service.dart';
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

class _Role extends UserProvider {
  _Role(this.role);
  final UserRole role;
  @override
  UserModel? get currentUser => UserModel(uid: 'u-d246', username: 'qa', name: 'QA', email: 'qa@test.local', role: role,
      createdAt: DateTime(2026, 1, 1));
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => false;
}

const kLongCat = '🧾 야간 물류센터 연장 근무와 급여 반영 안내';
const kLongQ = '야간 물류센터에서 분류 작업을 마친 뒤 연장 근무를 했는데 그 시간이 급여에 어떻게 반영되는지 알고 싶어요';
const kLongA = '연장 근무는 관리자가 실제 퇴근 시간을 확인해 급여 확정 때 반영합니다.\n\n'
    '확정 뒤에는 근무 일정의 임금명세서에서 반영된 시간과 금액을 확인할 수 있습니다.';

HelpFaqModel _h(int o, String c) =>
    HelpFaqModel(id: 'h$o', role: 'user', order: o, category: c, question: c, answer: '', isHeader: true, isActive: true);
HelpFaqModel _q(int o, String c, String q, String a) =>
    HelpFaqModel(id: 'q$o', role: 'user', order: o, category: c, question: q, answer: a, isHeader: false, isActive: true);

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
  final phase = Platform.environment['DU246_PHASE'] ?? '';
  final run = Platform.environment['DU246_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const userCats = ['공고 & 지원', '출퇴근 체크', '근로계약서', '급여 & 임금명세서', '노쇼 & 제재', '계정 & 서류'];
  const adminCats = ['공고 등록 & 관리', '근로계약서', '당일 출퇴근 관리', '급여 관리', '인력 & 멤버 관리', '사업장 설정'];
  const groupIcons = [Icons.work_outline, Icons.schedule_outlined, Icons.description_outlined, Icons.payments_outlined,
    Icons.warning_amber_outlined, Icons.group_outlined, Icons.settings_outlined, Icons.badge_outlined, Icons.help_outline];

  testWidgets('D246 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);

    var nPump = 0, nMount = 0, nTap = 0, nDrag = 0, nPng = 0;
    // DU246 phase 한도: pump+mount ≤1200, tap ≤4, drag ≤60, PNG ≤80.
    const maxFrames = 1200, maxTap = 4, maxDrag = 60, maxPng = 80;
    var cur = '(시작)';
    final loads = <String>[];
    Map<String, int> counts() => {'pump': nPump, 'pumpWidget': nMount, 'tap': nTap, 'drag': nDrag, 'png': nPng};
    Never stop(String why) {
      _out('D246-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors, 'counts': counts(), 'loads': loads})}');
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
    final startKstDate = _kst(DateTime.now()).substring(0, 10);

    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        for (final sc in const ['user', 'admin', 'server', 'error', 'empty']) {
          cur = '${c.id} $sc';
          if (nMount > 0) {
            nMount++;
            budget();
            await t.pumpWidget(const SizedBox.shrink());
            await frames(1);
            safe('장면 종료');
          }
          need(_kst(DateTime.now()).substring(0, 10) == startKstDate, 'KST 날짜가 실행 중 바뀜');
          loads.clear();
          overflow.clear();
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          Future<HelpFaqLoad> load(String role) async {
            loads.add(role);
            switch (sc) {
              case 'error':
                throw Exception('du246-read-failed');
              case 'empty':
                return const HelpFaqLoad([], configured: true);
              case 'server':
                return HelpFaqLoad([
                  _h(0, kLongCat),
                  _q(1, kLongCat, kLongQ, kLongA),
                  _q(2, kLongCat, '연장 근무 기록은 어디서 보나요?', '일정 탭의 근무 카드에서 확인합니다.'),
                ], configured: true);
              default:
                return const HelpFaqLoad([], configured: false);
            }
          }

          nMount++;
          budget();
          await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
            create: (_) => _Role(sc == 'admin' ? UserRole.BUSINESS_ADMIN : UserRole.USER),
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: sc == 'admin' ? RoleTheme.businessAdminTheme : RoleTheme.workerTheme,
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                home: HelpScreen(load: load),
              ),
            ),
          ));
          await frames(10);
          final sctx = t.element(find.byType(Scaffold).first);
          final mq = MediaQuery.of(sctx);
          need(Localizations.localeOf(sctx).toString() == 'ko_KR' && mq.size == Size(c.w, c.h) &&
              (mq.textScaler.scale(14) / 14 - c.s).abs() < 1e-9, '조건 불일치');
          need(jsonEncode(loads) == jsonEncode([sc == 'admin' ? 'admin' : 'user']), 'reader 정확값 불일치 $loads');
          safe('첫 화면');

          final list = sc == 'error' || sc == 'empty' ? <String>[] : (sc == 'admin' ? adminCats : sc == 'user' ? userCats : [kLongCat.substring(3)]);
          Finder? sfOf() => firstOf(find.descendant(of: find.byType(HelpScreen), matching: find.byType(Scrollable)));

          if (sc == 'user' || sc == 'server') {
            final q = firstOf(rich((p) => p == (sc == 'user' ? '공고에 어떻게 지원하나요?' : kLongQ)));
            need(q != null, '첫 질문 없음');
            nTap++;
            budget();
            await t.tap(q!);
            await frames(6);
            safe('펼침 tap 뒤');
          }

          Map<String, Object?> textInfo(String nm, Finder? f) {
            if (f == null) return {'name': nm, 'present': false};
            final rp = t.renderObject<RenderParagraph>(f);
            final r = t.getRect(f);
            final fg = rp.text.style?.color;
            final bg = bgOf(f.evaluate().first);
            final sf = sfOf();
            final inScroll = find.ancestor(of: f, matching: find.byType(Scrollable)).evaluate().isNotEmpty;
            final vis = inside(r, screen) && (!inScroll || sf == null || inside(r, t.getRect(sf)));
            return {
              'name': nm, 'present': true, 'rect': lt(r), 'visible': vis, 'maxLines': rp.maxLines,
              'didExceedMaxLines': rp.didExceedMaxLines, 'fontSize': rp.text.style?.fontSize, 'weight': rp.text.style?.fontWeight?.value,
              'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg), 'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
            };
          }

          Map<String, Object?> shapeOf(Finder f) {
            String? radius, side, face;
            f.evaluate().first.visitAncestorElements((a) {
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
            return {'radius': radius, 'side': side, 'face': face};
          }

          Map<String, Object?> recv(String nm, Finder f) {
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
              'name': nm, 'rect': lt(r), 'w': r1(r.width), 'h': r1(r.height), 'visible': vis,
              'centerHit': vis && hitsAt(r.center),
              'edgeMidHits': vis && [inner.topCenter, inner.bottomCenter, inner.centerLeft, inner.centerRight].every(hitsAt),
              'ge48': r.width >= 48 - 0.01 && r.height >= 48 - 0.01,
            };
          }

          // 질문 행 = 목록 안 InkWell. 질문 글 = 그 InkWell 안 첫 RichText.
          List<Map<String, Object?>> questions() {
            final out = <Map<String, Object?>>[];
            final inks = find.descendant(of: find.byType(HelpScreen), matching: find.byType(InkWell), skipOffstage: false).evaluate().toList();
            for (final e in inks) {
              final inkF = find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
              final rt = firstOf(find.descendant(of: inkF, matching: find.byType(RichText), skipOffstage: false));
              if (rt == null) continue;
              final plain = TextLayout.plain(t.widget<RichText>(rt).text.toPlainText());
              if (plain == '다시 시도') continue;
              out.add({...textInfo('Q $plain', rt), ...shapeOf(rt), 'recv': recv('행 $plain', inkF)});
            }
            return out;
          }

          List<Map<String, Object?>> measure() => [
                for (final cat in list) textInfo('분류 $cat', firstOf(rich((p) => p == cat))),
                if (sc == 'user') textInfo('답변 첫 질문', firstOf(rich((p) => p.startsWith('홈 화면의')))),
                if (sc == 'server') textInfo('답변 긴 질문', firstOf(rich((p) => p.startsWith('연장 근무는 관리자가')))),
                if (sc == 'error') ...[
                  textInfo('오류 제목', firstOf(rich((p) => p == '도움말을 불러오지 못했습니다'))),
                  textInfo('오류 부제', firstOf(rich((p) => p == '연결을 확인한 뒤 다시 시도해 주세요.'))),
                  textInfo('다시 시도', firstOf(rich((p) => p == '다시 시도'))),
                ],
                if (sc == 'empty') textInfo('빈 제목', firstOf(rich((p) => p == '등록된 도움말이 없습니다'))),
              ];
          int groupIconCount() => find
              .descendant(of: find.byType(HelpScreen), matching: find.byWidgetPredicate((w) => w is Icon && groupIcons.contains(w.icon)),
                  skipOffstage: false)
              .evaluate()
              .length;

          void afterChecks(List<Map<String, Object?>> xs, List<Map<String, Object?>> qs, int icons, String at) {
            if (!after) return;
            if (sc != 'empty') need(icons == 0, '$at 분류 아이콘이 남았다 $icons');
            for (final x in xs) {
              if (x['present'] != true || x['visible'] != true) continue;
              final n = x['name']! as String;
              // [DU246 계획 보정, TB 뒤·반영 전] 공용 AppEmptyState 제목(grey600, 4.3)은 38파일 공용 기본값이라
              //   이 셀 범위 밖이다 — 기록만 하고 단언하지 않는다(후보).
              if (n == '오류 제목' || n == '빈 제목') continue;
              final want = n.startsWith('분류')
                  ? '#21242D'
                  : n == '다시 시도'
                      ? null
                      : '#60646F';
              final cst = x['contrast'];
              need(cst is double && cst >= 4.5 && (want == null || x['fg'] == want), '$at 읽기색 $x');
              if (n.startsWith('분류')) need(x['fontSize'] == 16, '$at 분류 제목 크기 $x');
            }
            for (final q in qs) {
              if (q['visible'] != true) continue;
              final cst = q['contrast'];
              need(q['fg'] == '#21242D' && cst is double && cst >= 4.5, '$at 질문색 $q');
              need(q['radius'] == '16.0' && q['side'] == '#EEEEEE' && q['face'] == '#FFFFFF', '$at 묶음 면 $q');
              final v = q['recv']! as Map<String, Object?>;
              if (v['visible'] == true) need(v['ge48'] == true && v['centerHit'] == true && v['edgeMidHits'] == true, '$at 수신자 $v');
            }
          }

          final shots = <Map<String, Object?>>[];
          final shot = 'D246-$phase-${c.id}_$sc';
          Future<void> snap(String suffix) async {
            final xs = measure();
            final qs = questions();
            final ic = groupIconCount();
            afterChecks(xs, qs, ic, suffix.isEmpty ? '첫 화면' : suffix);
            nPng++;
            budget();
            await vqCapture(t, key, '$shot$suffix', conditions: {
              'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaleFactor(기기)': c.s,
              'locale': 'ko_KR', 'clock': '미주입(now=${_kst(DateTime.now())})',
            });
            final sf = sfOf();
            shots.add({'shot': suffix.isEmpty ? 'top' : suffix, 'texts': xs, 'questions': qs, 'groupIcons': ic,
              'pixels': sf == null ? null : r1(t.state<ScrollableState>(sf).position.pixels)});
          }

          await snap('');
          var atEnd = true;
          final sf0 = sfOf();
          if (sf0 != null) {
            var k = 0;
            while (k < 8) {
              final sf = sfOf()!;
              final vp = t.getRect(sf);
              final pos = t.state<ScrollableState>(sf).position;
              if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
              k++;
              nDrag++;
              budget();
              await t.dragFrom(Offset(vp.left + 24, vp.bottom - 12), Offset(0, -(vp.height * 0.7)));
              await frames(6);
              safe('drag $k 뒤');
              await snap('_d$k');
            }
            final pos = t.state<ScrollableState>(sfOf()!).position;
            atEnd = pos.pixels >= pos.maxScrollExtent - 0.5;
          }
          final seen = <String>{};
          for (final s in shots) {
            for (final x in (s['texts']! as List).cast<Map<String, Object?>>()) {
              if (x['visible'] == true) seen.add(x['name']! as String);
            }
          }
          final missed = [for (final cat in list) if (!seen.contains('분류 $cat')) '분류 $cat'];
          if (after) need(atEnd && missed.isEmpty, '끝 도달/관측 누락 atEnd=$atEnd missed=$missed');
          _out('D246 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'loads': loads, 'overflow': overflow, 'atEnd': atEnd,
                'missed': missed, 'shots': shots, 'counts': counts(), 'kst': _kst(DateTime.now())})}');
        }
      }
      nMount++;
      budget();
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D246-END ${jsonEncode({'counts': counts(), 'startKstDate': startKstDate, 'endKst': _kst(DateTime.now())})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 5)));
}
