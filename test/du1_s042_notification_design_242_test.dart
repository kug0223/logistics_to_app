// ignore_for_file: depend_on_referenced_packages
// [DU242 S042 알림 화면 시안 정렬 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU242_RUN=1 이고 DU242_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   standalone(MaterialApp home: NotificationScreen()). provider 대역(기존 notification_screen_render_test 와 같은 방식)이라
//   Firebase 채널은 열지 않는다(열면 막고 기록). 장면 4(지원자·관리자·빈 목록·오류) × W360/1.0·B320/2.0. tap·스와이프 0.
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
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/notification_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/notification_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/common/notification_card.dart';

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

class _Notif extends NotificationProvider {
  _Notif(this.items, {this.error = false});
  final List<NotificationModel> items;
  final bool error;
  @override
  List<NotificationModel> get notifications => items;
  @override
  bool get isLoading => false;
  @override
  bool get hasError => error;
  @override
  bool get hasMore => false;
  @override
  bool get isLoadingMore => false;
  @override
  bool get loadMoreFailed => false;
}

class _User extends UserProvider {
  _User(this.role);
  final UserRole role;
  @override
  UserModel? get currentUser => UserModel(uid: 'u-d242', name: '김근무', username: 'qa_d242', email: 'qa@test.local',
      role: role, createdAt: DateTime(2026, 1, 1));
  @override
  bool get isUser => role == UserRole.USER;
  @override
  bool get isBusinessAdmin => role == UserRole.BUSINESS_ADMIN;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => role == UserRole.BUSINESS_ADMIN;
  @override
  bool get permissionsLoaded => true;
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
  final phase = Platform.environment['DU242_PHASE'] ?? '';
  final run = Platform.environment['DU242_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);
  final blocked = <String>[];
  final appErrors = <String>[];
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';

  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  void stubChannels() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = FirebaseFirestoreHostApi.codec;
    for (final op in const ['queryGet', 'documentReferenceGet', 'documentReferenceSet', 'documentReferenceUpdate',
      'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult', 'transactionGet',
      'querySnapshot', 'documentReferenceSnapshot', 'aggregateQuery']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        blocked.add('firestore $op');
        return codec.encodeMessage(<Object?>['du242-blocked', '$op 차단', null]);
      });
    }
    m.setMockMessageHandler(fnChannel, (msg) async {
      blocked.add('functions call');
      return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'du242-blocked', null]);
    });
  }

  final now = DateTime.now();
  NotificationModel n(String id, NotificationType type, String title, String body,
          {bool read = false, int daysAgo = 0, bool known = true, String? biz}) =>
      NotificationModel(id: id, userId: 'u-d242', type: type, title: title, body: body, isRead: read,
          createdAt: now.subtract(Duration(days: daysAgo, minutes: 5)), createdAtKnown: known,
          data: biz == null ? null : {'businessName': biz});
  const kSignBody = '송파 물류센터 평일 야간 상하차·분류 보조 근로계약서를 확인하고 서명해 주세요.';
  final scenes = <String, List<NotificationModel>>{
    'user': [
      n('d242-1', NotificationType.contractSignRequested, '근로계약서 서명 요청', kSignBody, biz: 'QA 물류센터'),
      n('d242-2', NotificationType.applicationConfirmed, '지원이 확정되었습니다', '11월 12일 상하차 근무가 확정되었습니다.'),
      n('d242-3', NotificationType.workReminder, '내일 근무가 있어요', '내일 22:00 QA 물류센터 상하차 근무가 있습니다.', read: true, daysAgo: 1),
      n('d242-4', NotificationType.applicationRejected, '지원하신 송파 물류센터 평일 야간 상하차 공고가 마감되어 다음 기회에 연락드릴게요',
          '다른 공고를 확인해 보세요.', read: true, daysAgo: 3),
      n('d242-5', NotificationType.systemNotice, '서비스 점검 안내', '11월 20일 새벽 2시부터 4시까지 점검이 있습니다.', read: true, known: false),
    ],
    'admin': [
      n('d242-a1', NotificationType.newApplication, '새 지원자가 있어요', '김민수 님이 상하차 공고에 지원했습니다.', biz: 'QA 물류센터 A'),
      n('d242-a2', NotificationType.terminationRequested, '근로자 퇴사 요청', '이서연 님이 퇴사를 요청했습니다.', biz: 'QA 물류센터 A'),
      n('d242-a3', NotificationType.applicationCanceled, '지원이 취소되었어요', '박지훈 님이 지원을 취소했습니다.', read: true, daysAgo: 1, biz: 'QA 물류센터 A'),
    ],
    'empty': [],
    'error': [],
  };
  const groupLabels = ['오늘', '어제', '이번 주', '이전'];
  const lightTokens = {'#4CAF50', '#F44336', '#FF9800', '#FFC107', '#009688', '#2196F3', '#9E9E9E'};

  testWidgets('D242 $phase', (t) async {
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

    var nPump = 0, nMount = 0, nDrag = 0, nPng = 0;
    // DU242 phase 한도: pump+mount ≤600, tap 0, drag ≤2, PNG ≤10.
    const maxFrames = 600, maxDrag = 2, maxPng = 10;
    var cur = '(시작)';
    Map<String, int> counts() => {'pump': nPump, 'pumpWidget': nMount, 'tap': 0, 'drag': nDrag, 'png': nPng};
    Never stop(String why) {
      _out('D242-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors, 'appErrors': appErrors, 'counts': counts(), 'blocked': blocked})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    void budget() => need(nPump + nMount <= maxFrames && nDrag <= maxDrag && nPng <= maxPng, '사용량 한도 초과 ${counts()}');
    Future<void> frames(int k) async {
      for (var i = 0; i < k; i++) {
        nPump++;
        budget();
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    final overflow = <String>[];
    void safe(String at) {
      need(blocked.isEmpty, '$at 허용 밖 채널 호출: $blocked');
      need(appErrors.isEmpty, '$at 앱 오류: ${[for (final m in appErrors) m.split(nl).first]}');
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
        for (final sc in const ['user', 'admin', 'empty', 'error']) {
          cur = '${c.id} $sc';
          if (nMount > 0) {
            nMount++;
            budget();
            await t.pumpWidget(const SizedBox.shrink());
            await frames(1);
            safe('unmount');
          }
          need(_kst(DateTime.now()).substring(0, 10) == startKstDate, 'KST 날짜가 실행 중 바뀜');
          blocked.clear();
          appErrors.clear();
          overflow.clear();
          stubChannels();
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          final role = sc == 'admin' ? UserRole.BUSINESS_ADMIN : UserRole.USER;
          nMount++;
          budget();
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<NotificationProvider>(create: (_) => _Notif(scenes[sc]!, error: sc == 'error')),
              ChangeNotifierProvider<UserProvider>(create: (_) => _User(role)),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: navigatorKey,
                theme: role == UserRole.BUSINESS_ADMIN ? RoleTheme.businessAdminTheme : RoleTheme.workerTheme,
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                home: const NotificationScreen(),
              ),
            ),
          ));
          await frames(12);
          final sctx = t.element(find.byType(Scaffold).first);
          final mq = MediaQuery.of(sctx);
          need(Localizations.localeOf(sctx).toString() == 'ko_KR' && mq.size == Size(c.w, c.h) &&
              (mq.textScaler.scale(14) / 14 - c.s).abs() < 1e-9, '조건 불일치');
          safe('첫 화면');

          Rect? viewport() {
            final f = find.descendant(of: find.byType(NotificationScreen), matching: find.byType(Scrollable));
            return f.evaluate().isEmpty ? null : t.getRect(f.first);
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
            final vp = viewport();
            final inScroll = find.ancestor(of: f, matching: find.byType(Scrollable)).evaluate().isNotEmpty;
            return {
              'name': nm, 'present': true, 'plain': TextLayout.plain(rp.text.toPlainText()), 'rect': lt(r),
              'visible': inside(r, screen) && (!inScroll || vp == null || inside(r, vp)), 'fontSize': rp.text.style?.fontSize,
              'maxLines': rp.maxLines, 'didExceedMaxLines': rp.didExceedMaxLines,
              'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg), 'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
            };
          }

          // 카드 면·아이콘 — 각 NotificationCard 안의 첫 꾸밈 상자(카드 바탕)와 첫 Icon.
          List<Map<String, Object?>> cards() {
            final out = <Map<String, Object?>>[];
            for (final el in find.byType(NotificationCard, skipOffstage: false).evaluate()) {
              final cf = find.byElementPredicate((x) => identical(x, el), skipOffstage: false);
              final card = t.widget<NotificationCard>(cf);
              final decos = find.descendant(of: cf, matching: find.byWidgetPredicate((w) =>
                  w is DecoratedBox && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).border != null), skipOffstage: false);
              final icons = find.descendant(of: cf, matching: find.byType(Icon), skipOffstage: false);
              BoxDecoration? d;
              if (decos.evaluate().isNotEmpty) d = t.widget<DecoratedBox>(decos.first).decoration as BoxDecoration;
              Color? ic;
              for (final ie in icons.evaluate()) {
                final iw = ie.widget as Icon;
                // 스와이프 패널(흰 아이콘)은 빼고 본체 아이콘을 쓴다.
                if (iw.color != null && iw.color != Colors.white) {
                  ic = iw.color;
                  break;
                }
              }
              final cardColor = d?.color ?? Colors.white;
              out.add({
                'id': card.notification.id, 'read': card.notification.isRead,
                'radius': d?.borderRadius is BorderRadius ? (d!.borderRadius! as BorderRadius).topLeft.x : 0,
                'border': d?.border is Border ? _hex((d!.border! as Border).top.color) : null,
                'color': _hex(cardColor), 'icon': ic == null ? null : _hex(ic),
                'iconContrast': ic == null ? null : double.parse(_contrast(ic, cardColor).toStringAsFixed(2)),
                'rect': lt(t.getRect(cf)), 'visible': inside(t.getRect(cf), screen),
              });
            }
            return out;
          }

          List<Map<String, Object?>> measure() {
            final xs = <Map<String, Object?>>[
              for (final g in groupLabels) textInfo('묶음 $g', firstOf(rich((p) => p == g))),
              textInfo('묶음 날짜 확인 불가', firstOf(rich((p) => p == kUnknownTimeGroup))),
              textInfo('칩 미읽음만', firstOf(rich((p) => p == '미읽음만'))),
              textInfo('끝 안내', firstOf(rich((p) => p.startsWith('최근 ')))),
              textInfo('빈 부제', firstOf(rich((p) => p == '새로운 알림이 오면 여기에서 확인할 수 있어요.'))),
              textInfo('오류 부제', firstOf(rich((p) => p == '네트워크 상태를 확인하고 다시 시도해주세요'))),
            ];
            for (final nm in scenes[sc]!) {
              xs.add(textInfo('본문 ${nm.id}', firstOf(rich((p) => p == nm.body))));
              final cardF = find.byWidgetPredicate((w) => w is NotificationCard && w.notification.id == nm.id, skipOffstage: false);
              if (cardF.evaluate().isEmpty) continue;
              final times = find.descendant(of: cardF.first, matching: find.byWidgetPredicate((w) {
                if (w is! RichText) return false;
                final p = TextLayout.plain(w.text.toPlainText());
                return p.endsWith('분 전') || p.endsWith('시간 전') || p.endsWith('일 전') || p == '방금 전';
              }), skipOffstage: false);
              xs.add(textInfo('시간 ${nm.id}', times.evaluate().isEmpty ? null : firstOf(times)));
            }
            xs.add(textInfo('CTA 서명하기', firstOf(rich((p) => p == '서명하기'))));
            return xs;
          }

          void afterChecks(List<Map<String, Object?>> xs, List<Map<String, Object?>> cs, String at) {
            if (!after) return;
            for (final x in xs) {
              if (x['present'] != true || x['visible'] != true) continue;
              final nm = x['name']! as String;
              final cst = x['contrast'];
              String? want;
              if (nm.startsWith('묶음 ') && nm != '묶음 날짜 확인 불가') {
                want = '#21242D';
                need(x['fontSize'] == 16, '$at 묶음 제목 크기 $x');
              } else if (nm.startsWith('시간 ')) {
                want = '#686C77';
              } else if (nm == 'CTA 서명하기') {
                want = '#3859E8';
              } else {
                want = '#60646F';
              }
              need(x['fg'] == want && cst is double && cst >= 4.5, '$at 읽기색 $x');
            }
            for (final cd in cs) {
              if (cd['visible'] != true) continue;
              need(cd['radius'] == 16 && cd['border'] == '#EEEEEE', '$at 카드 면 $cd');
              need(!lightTokens.contains(cd['icon']) && (cd['iconContrast'] as double? ?? 0) >= 3.0, '$at 카드 아이콘 $cd');
            }
          }

          final shots = <Map<String, Object?>>[];
          final shot = 'D242-$phase-${c.id}_$sc';
          Future<void> snap(String suffix) async {
            final xs = measure();
            final cs = cards();
            afterChecks(xs, cs, suffix.isEmpty ? '첫 화면' : suffix);
            nPng++;
            budget();
            await vqCapture(t, key, '$shot$suffix', conditions: {
              'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaleFactor(기기)': c.s,
              'clock': '미주입(now=${_kst(DateTime.now())})',
            });
            shots.add({'shot': suffix.isEmpty ? 'top' : suffix, 'texts': xs, 'cards': cs});
          }

          await snap('');
          if (sc == 'user') {
            final vp = viewport();
            if (vp != null) {
              nDrag++;
              budget();
              await t.dragFrom(Offset(vp.left + 24, vp.bottom - 12), Offset(0, -(vp.height * 0.8)));
              await frames(6);
              safe('drag 뒤');
              await snap('_d1');
            }
          }
          _out('D242 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'overflow': overflow, 'shots': shots,
                'counts': counts(), 'kst': _kst(DateTime.now())})}');
        }
      }
      nMount++;
      budget();
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D242-END ${jsonEncode({'counts': counts(), 'startKstDate': startKstDate, 'endKst': _kst(DateTime.now())})}');
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
