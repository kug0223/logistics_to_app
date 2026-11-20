// [DU377] S017 변경 버림 확인창 — 하네스는 du1_s017_edit_obs_373 바탕(seam templateService · 시험 열기 화면에서 push).
//   W 392x844@1.0 · B 320x640@2.0. 흐름: 이름 입력(변경) → 뒤로 → 확인창 → 계속 편집 → 뒤로 → 바깥 탭(기록) → 뒤로 → 나가기.
//   불변(항상 단언): 변경 없으면 뒤로 → 확인창 없이 닫힘 · 계속 편집 → 남음 · 나가기 → 닫힘 · 넘침 0.
//   제품 기대(기본 단언, DU_BEFORE_OBSERVE=377 은 기록만):
//     ① 공용 확인창 셸(머리 아이콘 exit_to_app_outlined) ② 두 버튼 높이 ≥ 48
//     ③ '나가기' = errorDark 채움 · 글자 대비 ≥ 4.5 ④ 본문 낱말 안 끊김 0.
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
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/contract_template_edit_screen.dart';
import 'package:ALfit/services/contract_template_service.dart';
import 'package:ALfit/theme/app_colors.dart';
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

const kBiz = 'biz1';
final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '377';

class _Svc extends ContractTemplateService {}

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    const codec = StandardMessageCodec();
    for (final m in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$m',
          (_) async => codec.encodeMessage(<Object?>['du377.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du377.fake.$m'), (_) async => null);
    }
  });

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('S017D-${c.id} 변경 버림 확인창 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => UserProvider()),
            ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: RoleTheme.businessAdminTheme,
            builder: (ctx, child) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(
                        builder: (_) => ContractTemplateEditScreen(
                            businessId: kBiz, initialTemplateType: ContractTemplateType.daily, templateService: _Svc()))),
                    child: const Text('시험 열기'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      Future<void> settle([int n = 10]) async {
        for (var i = 0; i < n; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }

      final tag = 'S017D-${c.id}';
      final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};
      bool onEdit() => find.byType(ContractTemplateEditScreen).evaluate().isNotEmpty;
      bool dialogOpen() => findVisibleText('편집 취소').evaluate().isNotEmpty;

      // 불변: 변경 없으면 확인창 없이 닫힘
      await settle();
      await t.tap(find.text('시험 열기'));
      await settle(14);
      unawaited(navigatorKey.currentState!.maybePop());
      await settle(10);
      final cleanPop = !onEdit() && !dialogOpen();
      expect(cleanPop, isTrue, reason: '$tag 변경 없음 → 확인창 없이 닫힘(불변)');

      // 변경 → 뒤로 → 확인창
      await t.tap(find.text('시험 열기'));
      await settle(14);
      await t.enterText(find.byType(TextField).first, '냉장분류 계약서');
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(4);
      unawaited(navigatorKey.currentState!.maybePop());
      await settle(10);
      expect(dialogOpen(), isTrue, reason: '$tag 변경 있음 → 확인창(불변)');

      // ① 셸 ② 버튼 높이 ③ 나가기 색 ④ 본문 끊김
      final shell = find.byIcon(Icons.exit_to_app_outlined).evaluate().isNotEmpty;
      // [수리 1/3] 공용 셸 버튼은 ButtonStyleButton 이 아니라 Material + InkWell 이다 — 가장 가까운 누름 영역(InkWell/버튼)을 잰다
      Finder btnOf(String l) => find
          .ancestor(of: findVisibleText(l).first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton || w is InkWell))
          .first;
      // 바탕: 버튼 스타일 → 채운 Material → DecoratedBox 순(가장 가까운 것)
      Color? bgOf(Finder f) {
        Color? found;
        t.element(findVisibleText('나가기').first).visitAncestorElements((a) {
          final w = a.widget;
          Color? c;
          if (w is ButtonStyleButton) {
            c = w.style?.backgroundColor?.resolve(<WidgetState>{});
          } else if (w is Material && w.type != MaterialType.transparency && (w.color?.a ?? 0) > 0) {
            c = w.color;
          } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
            c = (w.decoration as BoxDecoration).color;
          } else if (w is Dialog) {
            return false;
          }
          if (c == null || c.a == 0) return true;
          found = c;
          return false;
        });
        return found;
      }

      final keepR = t.getRect(btnOf('계속 편집'));
      final leaveR = t.getRect(btnOf('나가기'));
      final leaveBg = bgOf(btnOf('나가기'));
      final leaveText = find.descendant(of: findVisibleText('나가기').first, matching: find.byType(RichText), matchRoot: true).first;
      final leaveFg = t.renderObject<RenderParagraph>(leaveText).text.style?.color ?? Colors.black;
      final dlgBg = Theme.of(t.element(find.byType(Dialog).first)).dialogTheme.backgroundColor ??
          Theme.of(t.element(find.byType(Dialog).first)).colorScheme.surface;
      final leaveCst = _contrast(Color.alphaBlend(leaveFg, leaveBg ?? dlgBg), leaveBg ?? dlgBg);
      final filledErrorDark = leaveBg != null && leaveBg.toARGB32() == AppColors.errorDark.toARGB32();
      var breaks = 0;
      final brList = <String>[];
      for (final e in find.byType(RichText).evaluate()) {
        final rp = e.renderObject! as RenderParagraph;
        final s = visibleText(rp.text.toPlainText());
        if (!s.contains('저장하지 않은')) continue;
        final br = wordBreaks(rp).where((b) => !b.forced).toList();
        breaks += br.length;
        brList.addAll(br.map((b) => '$b'));
      }
      await vqCapture(t, key, '${tag}_1dialog', conditions: {...cond, 'state': '변경 버림 확인창'});

      // 계속 편집 → 남음
      await t.tap(findVisibleText('계속 편집'));
      await settle(10);
      final kept = onEdit() && !dialogOpen();
      expect(kept, isTrue, reason: '$tag 계속 편집 → 남음(불변)');

      // 바깥 탭(기록)
      unawaited(navigatorKey.currentState!.maybePop());
      await settle(10);
      await t.tapAt(const Offset(8, 8));
      await settle(10);
      final outside = 'dialog=${dialogOpen()} onEdit=${onEdit()}';
      if (dialogOpen()) {
        await t.tap(findVisibleText('계속 편집'));
        await settle(10);
      }

      // 나가기 → 닫힘
      unawaited(navigatorKey.currentState!.maybePop());
      await settle(10);
      await t.tap(findVisibleText('나가기'));
      await settle(14);
      final left = !onEdit();
      expect(left, isTrue, reason: '$tag 나가기 → 닫힘(불변)');

      _out('$tag shell=$shell keep=${keepR.height.toStringAsFixed(1)} leave=${leaveR.height.toStringAsFixed(1)} leaveBg=${leaveBg == null ? 'null' : '0x${leaveBg.toARGB32().toRadixString(16)}'} leaveFg=0x${leaveFg.toARGB32().toRadixString(16)} leaveContrast=${leaveCst.toStringAsFixed(2)} breaks=$breaks $brList outside[$outside] overflows=${overflows.length} beforeObs=$_beforeObs');
      final ok = shell && keepR.height >= 47.99 && leaveR.height >= 47.99 && filledErrorDark && leaveCst >= 4.5 && breaks == 0;
      _out('KNOWN ${ok ? 'ok' : 'NG'} $tag 셸 $shell · 버튼 ${keepR.height.toStringAsFixed(1)}/${leaveR.height.toStringAsFixed(1)} · 나가기 errorDark $filledErrorDark ${leaveCst.toStringAsFixed(2)} · 끊김 $breaks');
      expect(t.takeException(), isNull);
      expect(overflows, isEmpty, reason: '$tag 넘침(불변)');
      if (!_beforeObs) {
        expect(shell, isTrue, reason: '$tag 공용 셸');
        expect(keepR.height, greaterThanOrEqualTo(47.99), reason: '$tag 계속 편집 높이');
        expect(leaveR.height, greaterThanOrEqualTo(47.99), reason: '$tag 나가기 높이');
        expect(filledErrorDark, isTrue, reason: '$tag 나가기 errorDark 채움');
        expect(leaveCst, greaterThanOrEqualTo(4.5), reason: '$tag 나가기 글자 대비');
        expect(breaks, 0, reason: '$tag 본문 낱말 안 끊김');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
    });
  }
}
