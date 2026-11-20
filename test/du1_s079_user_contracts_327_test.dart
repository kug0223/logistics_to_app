// ignore_for_file: depend_on_referenced_packages
// [DU327] S079 내 계약서(근로자) — 조회 실패 상태 렌더 관측(11-15 자체검토 셀).
//   하네스는 e2_render_regression_test RR-A7 과 같다(가짜 Firebase · 사용자 대역) — 조회가 실패해 '불러오지 못했습니다' 상태가 된다.
//   목록 · 빈 상태(조회 성공 0건)는 주입 지점이 없어 이번 범위 밖이다.
//   단언(기본 실행 = 현재 제품 정답): 넘침 0 · 오류 제목 · 이유 문장 보임 · 이유 문장 대비 ≥ 4.5 · 다시 시도 행동(≥ 48, hit, 누르면 다시 조회) ·
//   피할 수 있는 음절 끊김 0. DU_BEFORE_OBSERVE=327 이면 대비 · 다시 시도 · 끊김을 KNOWN 으로 기록.
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_contracts_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

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
        uid: 'u1',
        username: 'u1',
        name: 'QA 지원자',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'),
        accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 9, 1),
      );
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
}

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '327';
const kReason = '계약서가 없다는 뜻이 아닙니다. 잠시 후 다시 시도해주세요.';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

List<String> _avoidable(RenderParagraph rp) {
  final plain = rp.text.toPlainText();
  final ws = RegExp(r'[\s ]');
  final out = <String>[];
  double? lastTop;
  var lastIdx = -1;
  var line = StringBuffer();
  for (var i = 0; i < plain.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    if (lastTop == null || top > lastTop + 1) {
      if (lastTop != null && !ws.hasMatch(plain.substring(lastIdx, i + 1)) && ws.hasMatch(line.toString().trim())) {
        out.add('${visibleText(line.toString())}|${plain[i]}');
      }
      line = StringBuffer();
      lastTop = top;
    }
    line.write(plain[i]);
    lastIdx = i;
  }
  return out;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
        (data) async => const StandardMessageCodec().encodeMessage(<Object?>['unavailable', 'test harness', null]));
  });

  for (final c in const [(id: 'S079-W', w: 360.0, h: 780.0, s: 1.0), (id: 'S079-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 내 계약서 조회 실패 ${c.w.toInt()}×${c.h.toInt()}@${c.s}', (t) async {
      await t.runAsync(vqLoadFonts);
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          overflows.add(m.split('\n').first);
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);
      try {
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        void out(String l) {
          // ignore: avoid_print
          print(l);
        }

        void known(bool ok, String what) {
          out('KNOWN ${ok ? 'ok' : 'NG'} $what beforeObs=$_beforeObs');
          if (!_beforeObs) expect(ok, isTrue, reason: what);
        }

        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.workerTheme,
              builder: (ctx, child) =>
                  MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
              home: const UserContractsScreen(),
            ),
          ),
        ));
        for (var i = 0; i < 25; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(overflows, isEmpty, reason: '${c.id} 넘침');
        expect(findVisibleText('계약서를 불러오지 못했습니다'), findsOneWidget, reason: '조회 실패 제목');
        final reason = findVisibleText(kReason);
        expect(reason, findsOneWidget, reason: '이유 문장');
        final rp = t.renderObject<RenderParagraph>(find.descendant(of: reason, matching: find.byType(RichText)));
        final col = rp.text.style?.color ?? Colors.black;
        final bg = Theme.of(t.element(find.byType(UserContractsScreen))).scaffoldBackgroundColor;
        final cst = _contrast(col, bg);
        out('${c.id} reason color=$col bg=$bg contrast=${cst.toStringAsFixed(2)} rect=${t.getRect(reason)}');
        known(cst >= 4.5, '${c.id} 이유 문장 대비 ≥ 4.5(실측 ${cst.toStringAsFixed(2)})');
        for (final s in const ['계약서를 불러오지 못했습니다', kReason]) {
          final e = find.descendant(of: findVisibleText(s), matching: find.byType(RichText));
          final av = _avoidable(t.renderObject<RenderParagraph>(e));
          out('${c.id} "$s" avoidable=$av');
          known(av.isEmpty, '${c.id} 피할 수 있는 음절 끊김 0: "$s"');
        }
        final retry = findVisibleText('다시 시도');
        final hasRetry = retry.evaluate().isNotEmpty;
        known(hasRetry, '${c.id} 다시 시도 행동이 보인다');
        await vqCapture(t, key, '${c.id}_error', conditions: {
          'entry': 'UserContractsScreen(가짜 Firebase — 조회 실패)', 'theme': 'RoleTheme.workerTheme',
          'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'beforeObserve': _beforeObs});
        if (hasRetry) {
          final btn = find.ancestor(of: retry.first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
          final r = t.getRect(btn);
          final hit = HitTestResult();
          WidgetsBinding.instance.hitTestInView(hit, r.center, t.view.viewId);
          out('${c.id} retry rect=$r h=${r.height.toStringAsFixed(1)} hit=${hit.path.any((e) => e.target == t.renderObject(btn))}');
          expect(r.height, greaterThanOrEqualTo(48 - 1e-6), reason: '다시 시도 높이');
          // [DU327 b] 있는 것만으로는 부족하다 — 화면 안에 실제로 보이고 눌려야 한다(a 캡처에서 320·2.0 잘림을 놓쳤다).
          final inScreen = r.top >= -0.5 && r.bottom <= c.h + 0.5;
          expect(inScreen, isTrue, reason: '${c.id} 다시 시도가 화면 안(실측 $r)');
          expect(hit.path.any((e) => e.target == t.renderObject(btn)), isTrue, reason: '${c.id} 다시 시도 hit');
          final rr = t.getRect(reason);
          expect(rr.bottom <= c.h + 0.5, isTrue, reason: '${c.id} 이유 문장이 화면 안(실측 $rr)');
          await t.tap(btn);
          for (var i = 0; i < 15; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          expect(t.takeException(), isNull);
          expect(findVisibleText('계약서를 불러오지 못했습니다'), findsOneWidget, reason: '다시 조회 뒤에도 실패면 같은 상태(가짜 Firebase)');
        }
        out('${c.id} done beforeObs=$_beforeObs bgToken=${AppColors.background}');
        await t.pumpWidget(const SizedBox.shrink());
      } finally {
        FlutterError.onError = prev;
      }
    });
  }
}
