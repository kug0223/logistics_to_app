// ignore_for_file: depend_on_referenced_packages
// [DU252 S072 내 근무 평가 요약 영역 시안 정렬 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU252_RUN=1 이고 DU252_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   standalone(home: MyReviewsScreen(reads: 대역)) + UserProvider·NotificationProvider. 외부 채널 없음, tap 0.
//   장면 3(list·empty·error) × W360/1.0·B320/2.0.
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

import 'package:ALfit/models/core/monthly_review_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_reviews_reads.dart';
import 'package:ALfit/screens/user/my_reviews_screen.dart';
import 'package:ALfit/services/monthly_review_service.dart';
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

MonthlyReviewModel _review(String id, int rating, int month) => MonthlyReviewModel(
    id: id, reviewKey: id, reviewType: ReviewType.ADMIN_TO_USER, reviewerId: 'A', reviewerName: '관리자',
    businessId: 'B', businessName: 'QA 물류센터', targetUserId: 'u1', targetUserName: '김근로',
    reviewYear: 2026, reviewMonth: month, workDaysInMonth: 4, rating: rating, wouldRehire: rating >= 4,
    positiveTags: ['시간 엄수'], improvementTags: const [], comment: '성실하게 근무했습니다.',
    isPublished: true, createdAt: DateTime(2026, month, 28));

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
  final phase = Platform.environment['DU252_PHASE'] ?? '';
  final run = Platform.environment['DU252_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUp(() => SharedPreferences.setMockInitialValues({'tooltip_shown_first_review': true}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  final reviews = [_review('r1', 5, 10), _review('r2', 4, 9), _review('r3', 4, 8)];
  const stars = '★★★★☆';

  testWidgets('D252 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nDrag = 0, nPng = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D252-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 800 && nDrag <= 30 && nPng <= 40, '사용량 한도');
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
        for (final sc in const ['list', 'empty', 'error']) {
          cur = '${c.id} $sc';
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          safe('장면 종료');
          overflow.clear();
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          final reads = MyReviewsReads(reviewsForUserPaged: ({required targetUserId, startAfterId, pageSize = 30}) async {
            if (sc == 'error') throw Exception('du252-read-failed');
            if (sc == 'empty') return const ReviewPage<MonthlyReviewModel>(records: [], hasMore: false);
            return ReviewPage<MonthlyReviewModel>(records: reviews, cursor: 'r3', hasMore: true);
          });
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
                home: MyReviewsScreen(reads: reads),
              ),
            ),
          ));
          await frames(12);
          safe('첫 화면');
          Finder? sfOf() {
            final f = find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable));
            return f.evaluate().isEmpty ? null : nth(f, 0);
          }

          Map<String, Object?> info(String nm, Finder? f) {
            if (f == null) return {'name': nm, 'present': false};
            final rp = t.renderObject<RenderParagraph>(f);
            final r = t.getRect(f);
            final fg = rp.text.style?.color;
            final bg = bgOf(f.evaluate().first);
            final sf = sfOf();
            final inScroll = find.ancestor(of: f, matching: find.byType(Scrollable)).evaluate().isNotEmpty;
            final vp = (inScroll && sf != null) ? t.getRect(sf) : screen;
            String? radius, side, face;
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
            // [v2] 줄 수 — 글자 상자들의 서로 다른 top 개수(v1 합성에서 별이 두 줄로 갈라진 것을 단언으로 남긴다).
            final plainLen = rp.text.toPlainText().length;
            final lines = rp
                .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: plainLen))
                .map((b) => b.top.round())
                .toSet()
                .length;
            return {
              'name': nm, 'present': true, 'rect': lt(r), 'visible': inside(r, screen) && inside(r, vp), 'lines': lines,
              'fontSize': rp.text.style?.fontSize, 'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
              'didExceedMaxLines': rp.didExceedMaxLines, 'maxLines': rp.maxLines,
              'radius': radius, 'side': side, 'face': face,
            };
          }

          List<Map<String, Object?>> measure() => [
                {...info('수치 총 평가', nth(rich((p) => p == '3건'), 0)), 'kind': 'value'},
                {...info('수치 평균', nth(rich((p) => p == '4.3'), 0)), 'kind': 'value'},
                {...info('수치 별', nth(rich((p) => p == stars || p.startsWith('★')), 0)), 'kind': 'stars'},
                for (final l in ['총 평가', '평균 별점', '별점']) {...info('라벨 $l', nth(rich((p) => p == l), 0)), 'kind': 'label'},
                info('카드 사업장', nth(rich((p) => p.contains('QA 물류센터')), 0)),
                info('카드 코멘트', nth(rich((p) => p == '성실하게 근무했습니다.'), 0)),
                info('더 보기', nth(rich((p) => p == '더 보기'), 0)),
                info('빈 제목', nth(rich((p) => p == '아직 받은 평가가 없습니다'), 0)),
                info('빈 부제', nth(rich((p) => p.startsWith('근무 완료 후 사업장에서')), 0)),
                info('오류 제목', nth(rich((p) => p == '리뷰를 불러오지 못했습니다'), 0)),
              ];

          void afterChecks(List<Map<String, Object?>> xs, String at) {
            if (!after) return;
            for (final x in xs) {
              if (x['present'] != true || x['visible'] != true) continue;
              final k = x['kind'];
              if (k == null) continue;
              final want = k == 'value' ? '#21242D' : k == 'stars' ? '#946200' : '#60646F';
              final cst = x['contrast'];
              need(x['fg'] == want && cst is double && cst >= 4.5 && x['didExceedMaxLines'] != true, '$at 요약 글자 $x');
              need(x['radius'] == '16.0' && x['side'] == '#EEEEEE' && x['face'] == '#FFFFFF', '$at 요약 카드 면 $x');
              if (k == 'stars' && c.s == 1.0) need(x['lines'] == 1, '$at 보통 폭에서 별이 한 줄이 아니다 $x');
            }
          }

          final shots = <Map<String, Object?>>[];
          Future<void> snap(String suffix) async {
            final xs = measure();
            afterChecks(xs, suffix.isEmpty ? '첫 화면' : suffix);
            nPng++;
            await vqCapture(t, key, 'D252-$phase-${c.id}_$sc$suffix', conditions: {
              'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
            });
            final sf = sfOf();
            shots.add({'shot': suffix.isEmpty ? 'top' : suffix, 'texts': xs,
              'pixels': sf == null ? null : r1(t.state<ScrollableState>(sf).position.pixels)});
          }

          await snap('');
          var atEnd = true;
          if (sc == 'list' && sfOf() != null) {
            var k = 0;
            while (k < 10) {
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
          _out('D252 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'overflow': overflow, 'atEnd': atEnd, 'shots': shots,
                'counts': {'pump': nPump, 'drag': nDrag, 'png': nPng}})}');
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D252-END ${jsonEncode({'pump': nPump, 'drag': nDrag, 'png': nPng})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
