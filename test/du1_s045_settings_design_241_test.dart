// ignore_for_file: depend_on_referenced_packages
// [DU241 S045 관리 탭(설정) 시안 정렬 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU241_RUN=1 이고 DU241_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   standalone(MaterialApp home: const SettingsScreen()). 역할 2(사업장 관리자·슈퍼관리자) × W360/1.0·B320/2.0.
//   외부: 알림 권한 채널(거부로 고정 → 사용자 문서 get 없음), PackageInfo 대역, Functions 채널(callableGetMyBusiness 만 허용),
//   그 밖 Firestore·Functions 는 막고 기록한다. tap·push·토글·로그아웃·탈퇴 0.
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

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/theme_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/settings_screen.dart';
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

const kBiz = 'biz-local-d241';

class _Role extends UserProvider {
  _Role(this.role);
  final UserRole role;
  @override
  UserModel? get currentUser => UserModel(uid: 'u-d241', username: 'qa_admin', name: 'QA 관리자', email: 'qa@test.local',
      role: role, managedBusinessIds: role == UserRole.BUSINESS_ADMIN ? const [kBiz] : const [], createdAt: DateTime(2026, 1, 1));
  @override
  bool get isAdminMode => false;
  @override
  bool get isSuperAdmin => role == UserRole.SUPER_ADMIN;
  @override
  bool get isBusinessAdmin => role == UserRole.BUSINESS_ADMIN;
  @override
  bool get isSubAdmin => false;
  @override
  String? get effectiveBusinessId => null;
  @override
  bool get permissionsLoaded => true;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
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
  final phase = Platform.environment['DU241_PHASE'] ?? '';
  final run = Platform.environment['DU241_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
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

  void stubChannels() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMethodCallHandler(const MethodChannel('flutter.baseflow.com/permissions/methods'), (call) async {
      events.add('permission ${call.method}');
      return 0; // denied → 사용자 문서 get 없음
    });
    const codec = FirebaseFirestoreHostApi.codec;
    for (final op in const ['queryGet', 'documentReferenceGet', 'documentReferenceSet', 'documentReferenceUpdate',
      'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'transactionStoreResult', 'transactionGet',
      'querySnapshot', 'documentReferenceSnapshot', 'aggregateQuery']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        blocked.add('firestore $op');
        return codec.encodeMessage(<Object?>['du241-blocked', '$op 차단', null]);
      });
    }
    m.setMockMessageHandler(fnChannel, (msg) async {
      const c = StandardMessageCodec();
      final args = (c.decodeMessage(msg) as List).first as Map;
      final name = args['functionName'];
      if (name != 'callableGetMyBusiness') {
        blocked.add('fn $name');
        return c.encodeMessage(<Object?>['not-found', 'du241-blocked', null]);
      }
      events.add('fn $name@${args['region']}');
      return c.encodeMessage(<Object?>[
        <String, Object?>{
          'businesses': [
            {'id': kBiz, 'name': 'QA 물류센터', 'businessNumber': '000-00-00000', 'category': '물류', 'subCategory': '상하차',
              'address': '서울시 QA구 1', 'ownerId': 'u-d241', 'adminIds': ['u-d241'], 'isApproved': true,
              'createdAt': {'_seconds': 1790000000, '_nanoseconds': 0}},
          ],
        },
      ]);
    });
  }

  // 실행 전 고정 reader(순서 무관 multiset).
  final wantEvents = <String, List<String>>{
    'ba': (['permission checkPermissionStatus', 'fn callableGetMyBusiness@asia-northeast3']..sort()),
    'sa': ['permission checkPermissionStatus'],
  };
  const titles = <String, List<String>>{
    'ba': ['프로필 관리', '사업장 서류 관리', '사업장 정보', '업무 관리', '팀원 관리', '계약 관리', '계약서 템플릿', '통계', '리뷰 관리',
      '시스템 알림 설정', '도움말 (Q&A)', '가이드 다시 보기', '서비스 이용약관', '개인정보 처리방침', '위치정보 이용 동의'],
    'sa': ['프로필 관리', '전체 사용자 관리', '전체 사업장 관리', '약관 관리', '도움말 FAQ 관리', 'Application 마이그레이션',
      '총 근무시간 마이그레이션', '시스템 알림 설정', '도움말 (Q&A)', '가이드 다시 보기', '서비스 이용약관', '개인정보 처리방침',
      '위치정보 이용 동의'],
  };
  const sections = <String, List<String>>{
    'ba': ['내 정보', '사업장 관리', '계약', '분석', '알림', '앱 정보', '도움말', '법적 고지'],
    'sa': ['내 정보', '관리자 메뉴', '개발자 도구', '알림', '앱 정보', '도움말', '법적 고지'],
  };

  testWidgets('D241 $phase', (t) async {
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
    // DU241 phase 한도: pump+mount ≤800, tap 0, drag ≤8, PNG ≤12.
    const maxFrames = 800, maxDrag = 8, maxPng = 12;
    var cur = '(시작)';
    Map<String, int> counts() => {'pump': nPump, 'pumpWidget': nMount, 'tap': 0, 'drag': nDrag, 'png': nPng};
    Never stop(String why) {
      _out('D241-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors, 'appErrors': appErrors, 'counts': counts(), 'events': events, 'blocked': blocked})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    void budget() => need(nPump + nMount <= maxFrames && nDrag <= maxDrag && nPng <= maxPng, '사용량 한도 초과 ${counts()}');
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
        for (final sc in const ['ba', 'sa']) {
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
          stubChannels();
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          nMount++;
          budget();
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(create: (_) => _Role(sc == 'ba' ? UserRole.BUSINESS_ADMIN : UserRole.SUPER_ADMIN)),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
              ChangeNotifierProvider<ThemeProvider>(create: (_) => ThemeProvider()),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                navigatorKey: navigatorKey,
                theme: sc == 'ba' ? RoleTheme.businessAdminTheme : RoleTheme.superAdminTheme,
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                home: const SettingsScreen(),
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

          final sf = firstOf(find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable)))!;
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
              'bg': _hex(bg.color), 'contrast': fg == null ? null : double.parse(_contrast(fg, bg.color).toStringAsFixed(2)),
            };
          }

          // 메뉴 행 아이콘 — 제목 문단이 든 InkWell 안의 첫 Icon 색.
          Map<String, Object?> iconOf(String title) {
            final tf = firstOf(rich((p) => p == title));
            if (tf == null) return {'title': title, 'present': false};
            final ink = find.ancestor(of: tf, matching: find.byType(InkWell));
            if (ink.evaluate().isEmpty) return {'title': title, 'present': false};
            final icons = find.descendant(of: ink.first, matching: find.byType(Icon), skipOffstage: false);
            if (icons.evaluate().isEmpty) return {'title': title, 'present': false};
            final ic = t.widget<Icon>(icons.first);
            final r = t.getRect(tf);
            return {'title': title, 'present': true, 'color': ic.color == null ? null : _hex(ic.color!),
              'visible': inside(r, screen) && inside(r, t.getRect(sf))};
          }

          List<Map<String, Object?>> measure() => [
                for (final s in sections[sc]!) textInfo('섹션 $s', firstOf(rich((p) => p == s))),
                textInfo('아이디', firstOf(rich((p) => p == '@qa_admin'))),
                textInfo('알림 상태', firstOf(rich((p) => p == '알림이 꺼져 있습니다'))),
                textInfo('앱 버전 값', firstOf(rich((p) => p == '1.0.0'))),
                textInfo('회원탈퇴', firstOf(rich((p) => p == '회원탈퇴'))),
                if (sc == 'sa') textInfo('마이그레이션 설명', firstOf(rich((p) => p == 'totalWorkHours 0 오류 복구'))),
              ];
          List<Map<String, Object?>> icons() => [for (final ti in titles[sc]!) iconOf(ti)];

          void afterChecks(List<Map<String, Object?>> xs, List<Map<String, Object?>> ics, String at) {
            if (!after) return;
            for (final x in xs) {
              if (x['present'] != true || x['visible'] != true) continue;
              final n = x['name']! as String;
              // [DU245] 회원탈퇴는 중립 보조색(#60646F)이다 — 위험색은 탈퇴를 강조한다(사용자 11-10).
              final want = n.startsWith('섹션') ? '#21242D' : '#60646F';
              final cst = x['contrast'];
              need(x['fg'] == want && cst is double && cst >= 4.5, '$at 읽기색 $x');
              if (n.startsWith('섹션')) need(x['fontSize'] == 16, '$at 섹션 제목 크기 $x');
            }
            for (final ic in ics) {
              if (ic['present'] != true || ic['visible'] != true) continue;
              need(ic['color'] == '#757575', '$at 중립 아이콘 $ic');
            }
          }

          final shots = <Map<String, Object?>>[];
          final shot = 'D241-$phase-${c.id}_$sc';
          Future<void> snap(String suffix) async {
            final xs = measure();
            final ics = icons();
            afterChecks(xs, ics, suffix.isEmpty ? '첫 화면' : suffix);
            nPng++;
            budget();
            await vqCapture(t, key, '$shot$suffix', conditions: {
              'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaleFactor(기기)': c.s,
              'locale': locale, 'clock': '미주입(now=${_kst(DateTime.now())})',
            });
            shots.add({'shot': suffix.isEmpty ? 'top' : suffix, 'texts': xs, 'icons': ics,
              'pixels': r1(t.state<ScrollableState>(sf).position.pixels)});
          }

          await snap('');
          for (var k = 1; k <= 2; k++) {
            final vp = t.getRect(sf);
            final pos = t.state<ScrollableState>(sf).position;
            if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
            nDrag++;
            budget();
            await t.dragFrom(Offset(vp.left + 24, vp.bottom - 12), Offset(0, -(vp.height * 0.8)));
            await frames(6);
            match(sc, 'drag $k 뒤');
            await snap('_d$k');
          }
          _out('D241 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'events': [...events]..sort(), 'overflow': overflow, 'shots': shots,
                'counts': counts(), 'kst': _kst(DateTime.now())})}');
        }
      }
      nMount++;
      budget();
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      match(prevScene, 'END 전');
      _out('D241-END ${jsonEncode({'counts': counts(), 'startKstDate': startKstDate, 'endKst': _kst(DateTime.now())})}');
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
