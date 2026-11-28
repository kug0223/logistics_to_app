// ignore_for_file: depend_on_referenced_packages
// [DU262 S074 계약 연장 제안 시안 정렬 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU262_RUN=1 이고 DU262_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   reads 주입(DU262 R0 — baseline 도 주입 자리 반영본에서 돈다). 수락·거절 호출(쓰기) 없음 — 대화는 '취소'로 닫는다.
//   장면 4(list · accept(연장 수락 탭 → 확인 대화) · decline(거절 탭 → 확인 대화) · error) × W360/1.0·B320/2.0.
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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/screens/user/renewal_proposal_reads.dart';
import 'package:ALfit/screens/user/renewal_proposal_screen.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

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

const _bizLong = '강남 물류센터 제2물류동 야간 분류팀';
final DateTime _today = FormatHelper.toKstDate(DateTime.now());

final _proposals = [
  RenewalProposalModel(
    id: 'p1', businessId: 'b1', businessName: _bizLong, workerUid: 'u1', oldApplicationId: 'a1',
    status: RenewalProposalStatus.pending, effectiveStart: _today.add(const Duration(days: 3)),
    effectiveEnd: _today.add(const Duration(days: 92)), selectedWorkType: '상하차 및 분류 보조',
    workDays: const ['월', '수', '금'], startTime: '09:00', endTime: '18:00', wage: 12000, wageType: 'hourly'),
  RenewalProposalModel(
    id: 'p2', businessId: 'b2', businessName: '판교 카페', workerUid: 'u1', oldApplicationId: 'a2',
    status: RenewalProposalStatus.pending, effectiveStart: _today.add(const Duration(days: 5)),
    effectiveEnd: _today.add(const Duration(days: 35))),
];

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '서울특별시', city: '강남구'), accountStatus: 'active');
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

/// 글자 단위 줄 나눔 — 줄마다 보이는 글자, 그리고 '낱말 안에서 끊긴' 곳 수(DU256 과 같은 규칙).
({List<String> lines, int sylBreaks}) _lineInfo(RenderParagraph rp) {
  final raw = rp.text.toPlainText();
  final wj = String.fromCharCode(0x2060);
  final zw = String.fromCharCode(0x200B);
  bool word(String ch) {
    final u = ch.codeUnitAt(0);
    return (u >= 0xAC00 && u <= 0xD7A3) || (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
  }

  final lines = <String>[];
  var buf = StringBuffer();
  int? lastTop;
  var lastIdx = -1;
  var breaks = 0;
  for (var i = 0; i < raw.length; i++) {
    final ch = raw[i];
    if (ch == wj) continue;
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty || ch == ' ' || ch == zw || ch == String.fromCharCode(10)) {
      buf.write(ch);
      continue;
    }
    final top = bx.first.top.round();
    if (lastTop != null && top != lastTop) {
      lines.add(TextLayout.plain(buf.toString()).trim());
      buf = StringBuffer();
      final gap = raw.substring(lastIdx, i + 1);
      final sep = gap.contains(' ') || gap.contains(zw) || gap.contains(String.fromCharCode(10)) ||
          RegExp('[·,./()~-]').hasMatch(gap);
      if (!sep && word(raw[lastIdx]) && word(ch)) breaks++;
    }
    buf.write(ch);
    lastTop = top;
    lastIdx = i;
  }
  lines.add(TextLayout.plain(buf.toString()).trim());
  return (lines: lines, sylBreaks: breaks);
}

void main() {
  final phase = Platform.environment['DU262_PHASE'] ?? '';
  final run = Platform.environment['DU262_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('D262 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nDrag = 0, nPng = 0, nTap = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D262-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 900 && nDrag <= 40 && nPng <= 60 && nTap <= 12, '사용량 한도');
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
    Finder inList(Finder f) => find.descendant(of: find.byType(ListView), matching: f, skipOffstage: false);
    Finder? nth(Finder f, int i) {
      final els = f.evaluate().toList();
      if (els.isEmpty) return null;
      final e = i < 0 ? els.last : (i < els.length ? els[i] : null);
      if (e == null) return null;
      return find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    }

    // [r1] 아이콘 측정이 없는 화면이라 glyph 도우미를 뺐다(unused_element).
    Finder? anc(Finder? f, bool Function(Widget w) p) =>
        f == null ? null : find.ancestor(of: f, matching: find.byWidgetPredicate(p, skipOffstage: false));

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
        for (final sc in const ['list', 'accept', 'decline', 'error']) {
          cur = '${c.id} $sc';
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          safe('장면 종료');
          overflow.clear();
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
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
                home: RenewalProposalScreen(
                  reads: RenewalProposalReads(myRenewalProposals: () async {
                    if (sc == 'error') throw Exception('du262-read-failed');
                    return _proposals;
                  }),
                ),
              ),
            ),
          ));
          await frames(14);
          safe('첫 화면');
          if (sc != 'error') need(find.byType(ListView).evaluate().isNotEmpty, '목록이 없다');
          if (sc == 'accept' || sc == 'decline') {
            final f = find.text(sc == 'accept' ? '연장 수락' : '거절').first;
            await t.ensureVisible(f);
            await frames(4);
            nTap++;
            await t.tap(f);
            await frames(8);
            safe('대화 열림');
            need(find.byType(Dialog).evaluate().isNotEmpty || find.byType(AlertDialog).evaluate().isNotEmpty, '확인 대화가 없다');
          }

          Finder? sfOf() {
            final f = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable), skipOffstage: false);
            return f.evaluate().isEmpty ? null : nth(f, 0);
          }

          Map<String, Object?> info(String nm, Finder? f, {String? kind, bool lines = false, Finder? box, bool deco = false}) {
            if (f == null) return {'name': nm, 'kind': kind, 'present': false};
            final rp = t.renderObject<RenderParagraph>(f);
            final r = t.getRect(f);
            final fg = rp.text.style?.color;
            final bg = bgOf(f.evaluate().first);
            final sf = sfOf();
            final inSf = sf != null && find.descendant(of: sf, matching: f, skipOffstage: false).evaluate().isNotEmpty;
            final vp = inSf ? t.getRect(sf) : screen;
            final li = lines ? _lineInfo(rp) : null;
            Rect? br;
            if (box != null && box.evaluate().isNotEmpty) br = t.getRect(box.first);
            String? radius, side, face;
            if (deco) {
              f.evaluate().first.visitAncestorElements((a) {
                final w = a.widget;
                if (w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).borderRadius != null) {
                  final d = w.decoration as BoxDecoration;
                  radius = (d.borderRadius! as BorderRadius).topLeft.x.toString();
                  side = d.border == null ? 'none' : _hex((d.border! as Border).top.color);
                  face = d.color == null ? null : _hex(d.color!);
                  return false;
                }
                return true;
              });
            }
            return {
              'name': nm, 'kind': kind, 'present': true, 'rect': lt(r), 'visible': inside(r, screen) && inside(r, vp),
              'fontSize': rp.text.style?.fontSize, 'weight': rp.text.style?.fontWeight?.value,
              'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
              'didExceedMaxLines': rp.didExceedMaxLines, 'maxLines': rp.maxLines,
              if (li != null) 'lines': li.lines,
              if (li != null) 'sylBreaks': li.sylBreaks,
              if (br != null) 'boxH': r1(br.height),
              if (br != null) 'boxL': r1(br.left),
              if (br != null) 'boxR': r1(br.right), // [r1] 버튼 좌우 위치
              if (deco) 'radius': radius,
              if (deco) 'side': side,
              if (deco) 'face': face,
            };
          }

          List<Map<String, Object?>> measure() {
            Finder? btn(Finder? f) => anc(f, (w) => w is ButtonStyleButton);
            final acc = nth(rich((p) => p == '연장 수락'), 0);
            final dec = nth(inList(rich((p) => p == '거절')), 0);
            final dlgAcc = (sc == 'accept') ? nth(rich((p) => p == '수락'), -1) : null;
            final dlgDec = (sc == 'decline') ? nth(rich((p) => p == '거절'), -1) : null;
            final dlgCancel = (sc == 'accept' || sc == 'decline') ? nth(rich((p) => p == '취소'), -1) : null;
            return [
              info('사업장명', nth(rich((p) => p == _bizLong), 0), kind: 'name', lines: true, deco: true),
              info('안내', nth(rich((p) => p == '계약 연장을 제안했습니다.'), 0), kind: 'aux', lines: true), // [r2] 줄바꿈도 본다
              for (final l in ['기간', '업무', '근무요일', '근무시간', '임금'])
                info('라벨 $l', nth(rich((p) => p == l), 0), kind: 'aux', lines: true),
              info('값 업무', nth(rich((p) => p == '상하차 및 분류 보조'), 0), kind: 'value'),
              info('값 임금', nth(rich((p) => p.contains('12,000원')), 0), kind: 'value'),
              info('카드 수락', acc, kind: 'accept', lines: true, box: btn(acc)),
              info('카드 거절', dec, kind: 'decline', box: btn(dec)),
              info('대화 수락', dlgAcc, kind: 'dlgAccept', box: btn(dlgAcc)),
              info('대화 거절', dlgDec, kind: 'dlgDecline', box: btn(dlgDec)),
              info('대화 취소', dlgCancel),
              info('오류 제목', nth(rich((p) => p == '연장 제안을 불러오지 못했어요'), 0)),
            ];
          }

          void afterChecks(List<Map<String, Object?>> xs, String at) {
            if (!after) return;
            for (final x in xs) {
              if (x['present'] != true || x['visible'] != true) continue;
              final k = x['kind'];
              final cst = x['contrast'];
              need(x['didExceedMaxLines'] != true, '$at 말줄임/잘림 $x');
              final sb = x['sylBreaks'];
              if (sb is int) need(sb == 0, '$at 음절 끊김 $x');
              final h = x['boxH'] as double?;
              switch (k) {
                case 'name':
                  need(x['fg'] == '#21242D' && x['fontSize'] == 16.0 && x['maxLines'] == null, '$at 사업장명 $x');
                  need(x['radius'] == '16.0' && x['side'] == '#EEEEEE' && x['face'] == '#FFFFFF', '$at 카드 면 $x');
                case 'aux':
                  need(x['fg'] == '#60646F' && cst is double && cst >= 4.5, '$at 보조·라벨 $x');
                case 'value':
                  need(x['fg'] == '#21242D', '$at 값 $x');
                case 'accept':
                  need(x['fg'] == '#FFFFFF' && x['bg'] == '#3859E8' && (h ?? 0) >= 48, '$at 카드 수락 $x');
                case 'decline':
                  need(x['fg'] == '#21242D' && (h ?? 0) >= 48, '$at 카드 거절 $x');
                case 'dlgAccept':
                  need(x['fg'] == '#FFFFFF' && x['bg'] == '#3859E8', '$at 대화 수락 $x');
                case 'dlgDecline':
                  need(cst is double && cst >= 4.5, '$at 대화 거절 $x');
              }
            }
          }

          final shots = <Map<String, Object?>>[];
          Future<void> snap(String suffix) async {
            final xs = measure();
            afterChecks(xs, suffix.isEmpty ? '첫 화면' : suffix);
            nPng++;
            await vqCapture(t, key, 'D262-$phase-${c.id}_$sc$suffix', conditions: {
              'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
            });
            final sf = sfOf();
            shots.add({'shot': suffix.isEmpty ? 'top' : suffix, 'texts': xs,
              'pixels': sf == null ? null : r1(t.state<ScrollableState>(sf).position.pixels)});
          }

          // 첫 화면은 맨 위에서 찍는다(칩 탭 때 ensureVisible 로 내려갔을 수 있다).
          final sf0 = sfOf();
          if (sf0 != null) {
            t.state<ScrollableState>(sf0).position.jumpTo(0);
            await frames(2);
          }
          await snap('');
          var atEnd = true;
          // [TB 뒤 보정] 확인 대화가 열린 장면은 끌지 않는다(장벽 위 끌기는 목록을 움직이지 않아 끝 도달이 거짓이 된다).
          if (sfOf() != null && sc != 'accept' && sc != 'decline') {
            var k = 0;
            while (k < 12) {
              final sf = sfOf()!;
              final vp = t.getRect(sf);
              final pos = t.state<ScrollableState>(sf).position;
              if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
              k++;
              nDrag++;
              await t.dragFrom(Offset(vp.left + 24, vp.top + vp.height * 0.6), Offset(0, -(vp.height * 0.5)));
              await frames(8);
              safe('drag $k 뒤');
              await snap('_d$k');
            }
            final pos = t.state<ScrollableState>(sfOf()!).position;
            atEnd = pos.pixels >= pos.maxScrollExtent - 0.5;
          }
          if (after) need(atEnd, '끝 도달 실패');
          if (sc == 'accept' || sc == 'decline') {
            nTap++;
            await t.tap(findVisibleText('취소').last);
            await frames(6);
            safe('대화 닫힘');
          }
          _out('D262 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'overflow': overflow, 'atEnd': atEnd, 'shots': shots,
                'counts': {'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap}})}');
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D262-END ${jsonEncode({'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 5)));
}
