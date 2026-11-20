// [DU349] S001 외국인 가입 등록증 스캔 단계 — 기본 엄격 시험(하네스는 du1_s001_foreign_348_test main 앞을 글자 그대로, 생성기 work/du349-s001-scan/mk.py).
//   단언(기본): 예외 0 · 넘침 0 · writer hook 0 · 피할 수 있는 끊김 0 · 대비 미달 0(가장 가까운 바탕, 고유 문자열 기준).
//   DU_BEFORE_OBSERVE=349 이면 끊김 · 대비는 기록만 한다.
// ignore_for_file: depend_on_referenced_packages, unused_element
// [DU348] S001 외국인 가입(ForeignRegisterScreen) 단계별 렌더 관측 — 기록 전용(제품 무변경, 소급 9 범위 판정 전 사전 관측).
//   하네스는 du1_c0_foreign_resume_test 와 같다: ForeignRegisterHooks 로 사진 선택 · OCR · 업로드 · 사용자 읽기 · finalize · mark 합성
//   (writer 계열은 호출 수만), 약관 자동 read(CloudFunctionsHostApi.call)는 오류 응답으로 차단, FirebaseAuth 등록 채널 stub.
//   사례: ① 기본 정보(신규, basicInfo) ② 등록증 스캔(복구, documentScan) ③ 정보 확인(복구 → 갤러리 → 고정 정상 OCR, ocrConfirm).
//   W 392x844 1.0 / B 320x640 2.0. 가장 가까운 바탕 대비(아이콘 제외) · 공용 판정기(DU338) · 넘침 · writer hook 0 을 기록한다.
//   단언: 예외 0 · writer hook(upload · finalize · mark) 0. 시각 수치는 기록만(DU348 은 관측 셀).
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/foreign_register_screen.dart';
import 'package:ALfit/services/foreign_id_ocr_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

import 'support/du1_vq_capture.dart';
import 'support/du_word_break.dart';
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

const kOcrOk = ForeignIdOcrResult(legalName: 'NGUYEN VAN AN', foreignIdRaw: '9001015123456', visaType: 'E-9',
    stayExpiryDate: '2028-12-31', legalNameFailed: false, foreignIdFailed: false, visaTypeFailed: false, stayExpiryFailed: false);

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

Color _overWhite(Color c) => Color.alphaBlend(c, Colors.white);

Color _bgOf(Element e) {
  Color? found;
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is ButtonStyleButton) {
      c = w.style?.backgroundColor?.resolve(w.enabled ? <WidgetState>{} : {WidgetState.disabled});
      if (c == null && w is ElevatedButton) c = Theme.of(a).colorScheme.primary;
      if (c == null) return true;
    } else if (w is Container && w.decoration is BoxDecoration) {
      c = (w.decoration! as BoxDecoration).color;
    } else if (w is Container && w.color != null) {
      c = w.color;
    } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
      c = (w.decoration as BoxDecoration).color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color ?? Theme.of(a).colorScheme.surface;
    } else if (w is ColoredBox) {
      c = w.color;
    }
    if (c == null || c.a == 0) return true;
    found = _overWhite(c);
    return false;
  });
  return found ?? Colors.white;
}

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}


final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '349';

void main() {
  var functionsCalls = 0;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMessageHandler('dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call', (_) async {
      functionsCalls++;
      return const StandardMessageCodec().encodeMessage(<Object?>['du349-blocked', 'functions 호출 차단(시험)', null]);
    });
    const codec = StandardMessageCodec();
    for (final x in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      m.setMockMessageHandler('dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$x',
          (_) async => codec.encodeMessage(<Object?>['du349.fake.$x']));
      m.setMockMethodCallHandler(MethodChannel('du349.fake.$x'), (_) async => null);
    }
  });
  tearDown(ForeignRegisterHooks.reset);

  for (final c in const [(id: 'S001S-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S001S-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 외국인 가입 등록증 스캔 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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
        functionsCalls = 0;
        var uploadCalls = 0, finalizeCalls = 0, markCalls = 0;
        ForeignRegisterHooks.reuseOcr = (p) async => throw Exception('합성: 재사용 없음');
        ForeignRegisterHooks.pickAndOcr = () async => (path: '/local/synthetic_pick.jpg', result: kOcrOk);
        ForeignRegisterHooks.currentUid = () => 'u-local-fr-349';
        ForeignRegisterHooks.upload = (a, b) async => uploadCalls++;
        ForeignRegisterHooks.readUser = (_) async => <String, dynamic>{};
        ForeignRegisterHooks.finalize = (a, b, c2, d, e) async {
          finalizeCalls++;
          return 'fp';
        };
        ForeignRegisterHooks.mark = (_) async => markCalls++;
        ForeignRegisterHooks.collectionEnabled = () => false;
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        void out(String l) {
          // ignore: avoid_print
          print(l);
        }

        await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
          create: (_) => UserProvider(),
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              navigatorKey: navigatorKey,
              theme: RoleTheme.workerTheme,
              builder: (ctx, child) =>
                  MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
              home: const ForeignRegisterScreen(role: UserRole.USER, isResume: true),
            ),
          ),
        ));
        await _settle(t, 12);
        var avoid = 0, low = 0;
        final seen = <String>{};
        void dump(String tg) {
          for (final e in find.byType(RichText).evaluate()) {
            final rp = e.renderObject! as RenderParagraph;
            final s = visibleText(rp.text.toPlainText());
            if (s.isEmpty) continue;
            final self = find.byElementPredicate((x) => identical(x, e));
            final r = t.getRect(self);
            if (r.bottom < 0 || r.top > c.h || r.width == 0) continue;
            if (find.ancestor(of: self, matching: find.byType(Icon)).evaluate().isNotEmpty) continue;
            final col = rp.text.style?.color;
            final bg = _bgOf(e);
            final k = '$s@${bg.toARGB32()}@${col?.toARGB32()}';
            if (seen.contains(k)) continue;
            seen.add(k);
            for (final b in wordBreaks(rp)) {
              if (!b.forced) {
                avoid++;
                out('$tg avoidable $b');
              }
            }
            final cst = col == null ? 99.0 : _contrast(_overWhite(col), bg);
            if (cst < 4.5) {
              low++;
              out('$tg low "$s" color=0x${col?.toARGB32().toRadixString(16)} bg=0x${bg.toARGB32().toRadixString(16)} contrast=${cst.toStringAsFixed(2)}');
            }
          }
        }

        final tag = c.id;
        dump(tag);
        await vqCapture(t, key, '${tag}_1_top', conditions: {'step': 'documentScan', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
        final pos = t.state<ScrollableState>(find.descendant(of: find.byType(ForeignRegisterScreen), matching: find.byType(Scrollable)).first).position;
        var guard = 0;
        while (pos.pixels < pos.maxScrollExtent - 0.5 && guard++ < 30) {
          pos.jumpTo(math.min(pos.pixels + c.h * 0.5, pos.maxScrollExtent));
          await t.pump(const Duration(milliseconds: 50));
          dump('${tag}_walk');
        }
        await vqCapture(t, key, '${tag}_2_end', conditions: {'step': 'documentScan 끝', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
        expect(t.takeException(), isNull);
        out('$tag summary overflows=${overflows.length} avoidable=$avoid low=$low writer=${uploadCalls + finalizeCalls + markCalls} functions=$functionsCalls beforeObs=$_beforeObs');
        out('KNOWN ${avoid == 0 ? 'ok' : 'NG'} $tag 피할 수 있는 끊김 0(실측 $avoid)');
        out('KNOWN ${low == 0 ? 'ok' : 'NG'} $tag 대비 미달 0(실측 $low)');
        expect(overflows, isEmpty, reason: '$tag 넘침');
        expect(uploadCalls + finalizeCalls + markCalls, 0, reason: '$tag writer hook 미진입');
        if (!_beforeObs) {
          expect(avoid, 0, reason: '$tag 피할 수 있는 끊김');
          expect(low, 0, reason: '$tag 대비 미달');
        }
        await t.pumpWidget(const SizedBox.shrink());
      } finally {
        FlutterError.onError = prev;
      }
    });
  }
}
