// [DU360] S001 정보 확인 예시 글 단축(소급 11 채택 · DU355 CORRECTION_OPEN) — du1_s001_scan_ocr_355_test 를 바탕으로 scan 흐름만
//   (생성기 work/du360-s001-hint-short/mk.py). DU355 가 단언 밖 잔여로 뺀 '한 줄 칸 예시 글 말줄임'을 다시 단언한다(게이트 복원).
//   키보드 기하(번호 칸이 키보드 위)와 빈 칸 높이는 DU355 와 같은 방식으로 잰다. DU_BEFORE_OBSERVE=360 이면 시각 · 예시 글은 기록만.
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:async';
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



final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '360';

typedef _Pick = ({String path, ForeignIdOcrResult? result});

const kOcrPartial = ForeignIdOcrResult(
    legalName: 'NGUYEN VAN AN',
    legalNameFailed: false,
    foreignIdFailed: true,
    visaTypeFailed: true,
    stayExpiryFailed: true,
    legalNameOcrSource: 'FULL_OCR');

void main() {
  var functionsCalls = 0;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    m.setMockMessageHandler('dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call', (_) async {
      functionsCalls++;
      return const StandardMessageCodec().encodeMessage(<Object?>['du360-blocked', 'functions 호출 차단(시험)', null]);
    });
    const codec = StandardMessageCodec();
    for (final x in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      m.setMockMessageHandler('dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$x',
          (_) async => codec.encodeMessage(<Object?>['du360.fake.$x']));
      m.setMockMethodCallHandler(MethodChannel('du360.fake.$x'), (_) async => null);
    }
  });
  tearDown(ForeignRegisterHooks.reset);

  for (final c in const [(id: 'S001O-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S001O-B', w: 320.0, h: 640.0, s: 2.0)]) {
    for (final flow in const ['scan']) {
      testWidgets('${c.id} 외국인 가입 스캔 · OCR $flow ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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
          var pickC = Completer<_Pick>();
          final reuseC = Completer<ForeignIdOcrResult>();
          var picks = 0;
          ForeignRegisterHooks.pickAndOcr = () {
            picks++;
            return pickC.future;
          };
          ForeignRegisterHooks.reuseOcr = (p) => reuseC.future;
          ForeignRegisterHooks.currentUid = () => 'u-local-fr-360';
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
                home: flow == 'scan'
                    ? const ForeignRegisterScreen(role: UserRole.USER, isResume: true)
                    : const ForeignRegisterScreen(role: UserRole.USER, isResume: true, existingIdCardPath: 'idCards/u-local-fr-355/front.jpg'),
              ),
            ),
          ));
          await _settle(t, 6);
          final tag = '${c.id}_$flow';
          final steps = <String, bool>{};
          final prod = <String, bool>{};
          final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'flow': flow};
          Finder body() => find.descendant(of: find.byType(ForeignRegisterScreen), matching: find.byType(Scrollable)).first;

          var avoid = 0, low = 0, clipped = 0, hintClipped = 0;
          final seen = <String>{};
          final lowList = <String>[];
          Future<void> dump(String tg, {bool walk = false}) async {
            void once() {
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
                if (rp.didExceedMaxLines) {
                  // [수리 1/3] 한 줄 칸의 예시 글(hintText) 말줄임은 잔여로 따로 센다(r2 에서 줄바꿈 교정 철회 — 빈 칸이 3줄로 커짐). 기록만.
                  final hints = find.byType(TextField).evaluate().map((x) => (x.widget as TextField).decoration?.hintText).whereType<String>().toSet();
                  if (hints.contains(s)) {
                    hintClipped++;
                    out('$tg hintClipped "$s" w=${r.width.toStringAsFixed(1)}');
                  } else {
                    clipped++;
                    out('$tg clipped "$s" w=${r.width.toStringAsFixed(1)}');
                  }
                }
                // [소급 10] 글자 알파를 실제 바탕 위에 합성한다(흰색 위 합성 아님)
                final cst = col == null ? 99.0 : _contrast(Color.alphaBlend(col, bg), bg);
                if (cst < 4.5) {
                  low++;
                  lowList.add(s);
                  out('$tg low "$s" color=0x${col?.toARGB32().toRadixString(16)} bg=0x${bg.toARGB32().toRadixString(16)} contrast=${cst.toStringAsFixed(2)}');
                }
              }
            }

            once();
            if (walk) {
              final pos = t.state<ScrollableState>(body()).position;
              var guard = 0;
              while (pos.pixels < pos.maxScrollExtent - 0.5 && guard++ < 30) {
                pos.jumpTo(math.min(pos.pixels + c.h * 0.5, pos.maxScrollExtent));
                await t.pump(const Duration(milliseconds: 50));
                once();
              }
              pos.jumpTo(0);
              await t.pump(const Duration(milliseconds: 50));
            }
          }

          Future<void> tapText(String s) async {
            final f = findVisibleText(s).first;
            await t.scrollUntilVisible(f, 120, scrollable: body(), maxScrolls: 60);
            await _settle(t, 2);
            await t.tap(f);
          }

          final runningFresh = findVisibleText('이미지 인식 중...');
          final runningReuse = findVisibleText('이전에 등록한 외국인등록증을 불러오는 중...');
          final reuseNotice = findVisibleTextContaining('불러오지 못했습니다');
          final scanOpts = findVisibleText('갤러리에서 선택');
          final confirmHead = findVisibleTextContaining('인식된 정보를 확인하고');

          if (flow == 'scan') {
            steps['스캔 선택지'] = scanOpts.evaluate().isNotEmpty;
            await dump('${tag}_1_scan', walk: true);
            await vqCapture(t, key, '${tag}_1_scan', conditions: {...cond, 'state': '스캔'});
            await tapText('갤러리에서 선택');
            await _settle(t, 2);
            steps['처리 중 표시(새 사진)'] = runningFresh.evaluate().isNotEmpty && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
            await dump('${tag}_2_running');
            await vqCapture(t, key, '${tag}_2_running', conditions: {...cond, 'state': '이미지 인식 중'});
            pickC.complete((path: '/local/synthetic_pick.jpg', result: kOcrPartial));
            await _settle(t, 10);
            steps['일부 인식 → 정보 확인'] = confirmHead.evaluate().isNotEmpty &&
                findVisibleTextContaining('일부 정보를 인식하지 못했습니다').evaluate().isNotEmpty &&
                findVisibleTextContaining('동일한지 확인해주세요').evaluate().isNotEmpty;
            await dump('${tag}_3_partial', walk: true);
            await vqCapture(t, key, '${tag}_3_partial', conditions: {...cond, 'state': '일부 인식 실패 + 이름 확인 안내'});
            // 긴 이름 + 번호 칸 키보드
            final fields = find.byType(TextFormField);
            await t.scrollUntilVisible(fields.at(0), 80, scrollable: body(), maxScrolls: 40);
            await t.enterText(fields.at(0), 'NGUYEN THI THANH HUONG MARIA JOSEPHINE');
            await t.scrollUntilVisible(fields.at(2), 80, scrollable: body(), maxScrolls: 40);
            await t.tap(fields.at(2));
            await _settle(t, 4);
            final kb = (c.h * 0.4).roundToDouble();
            t.view.viewInsets = FakeViewPadding(bottom: kb);
            await _settle(t, 8);
            final fr = t.getRect(fields.at(2));
            out('$tag keyboard kb=$kb idField=${fr.top.toStringAsFixed(1)}–${fr.bottom.toStringAsFixed(1)} h=${fr.height.toStringAsFixed(1)} limit=${(c.h - kb).toStringAsFixed(1)}');
            steps['키보드: 번호 칸이 키보드 위'] = fr.bottom <= c.h - kb + 0.5 && fr.top >= 0;
            await vqCapture(t, key, '${tag}_4_keyboard', conditions: {...cond, 'state': '번호 칸 키보드 ${kb.toInt()}'});
            t.view.resetViewInsets();
            FocusManager.instance.primaryFocus?.unfocus();
            await _settle(t, 6);
            // 뒤로 → 재선택
            await t.tap(find.byIcon(Icons.arrow_back).first);
            await _settle(t, 8);
            steps['뒤로 → 스캔(재선택)'] = scanOpts.evaluate().isNotEmpty;
            pickC = Completer<_Pick>();
            await tapText('갤러리에서 선택');
            await _settle(t, 2);
            pickC.complete((path: '/local/synthetic_pick2.jpg', result: null));
            await _settle(t, 10);
            steps['OCR 예외 → 정보 확인(직접 입력)'] = confirmHead.evaluate().isNotEmpty && picks == 2 &&
                findVisibleTextContaining('일부 정보를 인식하지 못했습니다').evaluate().isNotEmpty;
            await dump('${tag}_5_threw', walk: true);
            await vqCapture(t, key, '${tag}_5_threw', conditions: {...cond, 'state': 'OCR 예외 뒤 정보 확인'});
          } else {
            steps['재사용 처리 중 표시'] = runningReuse.evaluate().isNotEmpty;
            await dump('${tag}_1_reuse_running');
            await vqCapture(t, key, '${tag}_1_reuse_running', conditions: {...cond, 'state': '이전 등록증 불러오는 중'});
            reuseC.completeError(Exception('합성: 재사용 실패'));
            await _settle(t, 10);
            steps['재사용 실패 → 스캔'] = scanOpts.evaluate().isNotEmpty && runningReuse.evaluate().isEmpty;
            prod['재사용 실패 안내'] = reuseNotice.evaluate().isNotEmpty;
            await dump('${tag}_2_reuse_failed', walk: true);
            await vqCapture(t, key, '${tag}_2_reuse_failed', conditions: {...cond, 'state': '재사용 실패 뒤 스캔'});
            await tapText('갤러리에서 선택');
            await _settle(t, 2);
            final freshShown = runningFresh.evaluate().isNotEmpty;
            final reuseShown = runningReuse.evaluate().isNotEmpty;
            out('$tag newpick running fresh=$freshShown reuse=$reuseShown');
            steps['새 사진 처리 중 표시'] = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
            prod['새 사진 처리 중 문구 = 이미지 인식 중'] = freshShown && !reuseShown;
            await dump('${tag}_3_newpick_running');
            await vqCapture(t, key, '${tag}_3_newpick_running', conditions: {...cond, 'state': '재사용 실패 뒤 새 사진 처리 중'});
            pickC.complete((path: '/local/synthetic_pick.jpg', result: kOcrOk));
            await _settle(t, 10);
            steps['새 사진 → 정보 확인'] = confirmHead.evaluate().isNotEmpty;
            await t.tap(find.byIcon(Icons.arrow_back).first);
            await _settle(t, 8);
            prod['새 사진 뒤 스캔 복귀 시 재사용 실패 안내 사라짐'] = scanOpts.evaluate().isNotEmpty && reuseNotice.evaluate().isEmpty;
          }

          expect(t.takeException(), isNull);
          final flowOk = steps.values.every((v) => v);
          final prodOk = prod.values.every((v) => v);
          out('$tag steps=$steps');
          out('$tag prod=$prod');
          out('$tag summary overflows=${overflows.length} avoidable=$avoid low=$low clipped=$clipped hintClipped=$hintClipped writer=${uploadCalls + finalizeCalls + markCalls} functions=$functionsCalls lowList=$lowList beforeObs=$_beforeObs');
          out('KNOWN ${flowOk ? 'ok' : 'NG'} $tag 흐름');
          out('KNOWN ${prodOk ? 'ok' : 'NG'} $tag 제품 기대');
          out('KNOWN ${avoid == 0 && low == 0 && clipped == 0 ? 'ok' : 'NG'} $tag 끊김 $avoid · 대비 $low · 잘림 $clipped');
          out('KNOWN ${hintClipped == 0 ? 'ok' : 'NG'} $tag 잔여: 예시 글 말줄임 $hintClipped(기록만, 문구 단축 후보)');
          expect(overflows, isEmpty, reason: '$tag 넘침');
          expect(uploadCalls + finalizeCalls + markCalls, 0, reason: '$tag writer hook 미진입');
          for (final en in steps.entries) {
            expect(en.value, isTrue, reason: '$tag ${en.key}');
          }
          if (!_beforeObs) {
            expect(avoid, 0, reason: '$tag 피할 수 있는 끊김');
            expect(low, 0, reason: '$tag 대비 미달');
            expect(clipped, 0, reason: '$tag 잘림');
            expect(hintClipped, 0, reason: '$tag 예시 글 말줄임(게이트 복원)');
            for (final en in prod.entries) {
              expect(en.value, isTrue, reason: '$tag ${en.key}');
            }
          }
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(seconds: 5));
        } finally {
          FlutterError.onError = prev;
        }
      });
    }
  }
}
