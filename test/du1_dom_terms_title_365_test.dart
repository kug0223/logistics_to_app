// [DU365] 내국인 약관 항목 제목 낱말 조판(소급 12 §3) — 하네스는 du1_s001_basic_confirm_350_test 의 main 앞 바탕(생성기 work/du365-dom-terms-title/mk.py).
//   RegisterScreen(termsLoaderForTest · initialUserTermsStepForTest)로 약관 단계를 그리고 W · B 에서 항목 제목의 피할 수 있는 끊김 · 대비를 잰다.
//   원문 찾기(find.text) · Text 하나(findVisibleText) · 원문 낭독도 단언한다. DU_BEFORE_OBSERVE=365 이면 끊김은 기록만.
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/register_screen.dart';
import 'package:ALfit/services/foreign_id_ocr_service.dart';
import 'package:ALfit/theme/role_theme.dart';

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



final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '365';

LegalTermsItem _item(String id, String title, bool req, int order) => LegalTermsItem(
    id: id, title: title, content: '$title 본문입니다.', isRequired: req, version: 'v1', revisionId: '${id}__v1', order: order);

final _terms = EffectiveLegalTerms(serverNow: DateTime.utc(2026, 11, 15), upcoming: const [], items: [
  _item('service', '서비스 이용약관', true, 1),
  _item('privacy', '개인정보 수집 및 이용 동의', true, 2),
  _item('location', '위치기반 서비스 이용약관', true, 3),
  _item('marketing', '마케팅 정보 수신 동의', false, 4),
]);

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  for (final c in const [(id: 'DTT-W', w: 392.0, h: 844.0, s: 1.0), (id: 'DTT-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 내국인 약관 항목 제목 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
      await t.runAsync(vqLoadFonts);
      final sem = t.ensureSemantics();
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
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: RegisterScreen(termsLoaderForTest: () async => _terms, initialUserTermsStepForTest: true),
          ),
        ),
      ));
      await _settle(t, 10);
      var avoid = 0, low = 0;
      final found = <String, bool>{};
      for (final it in _terms.activeItems) {
        final f = findVisibleText(it.title);
        await t.scrollUntilVisible(f, 120, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
        await _settle(t, 2);
        found[it.title] = f.evaluate().length == 1 && find.text(it.title).evaluate().length == 1;
        final rt = find.descendant(of: f.first, matching: find.byType(RichText), matchRoot: true).first;
        final e = rt.evaluate().first;
        final rp = t.renderObject<RenderParagraph>(rt);
        final col = rp.text.style?.color ?? Colors.black;
        final bg = _bgOf(e);
        final cst = _contrast(Color.alphaBlend(col, bg), bg);
        final br = wordBreaks(rp).where((b) => !b.forced).toList();
        avoid += br.length;
        if (cst < 4.5) low++;
        out('${c.id} "${it.title}" contrast=${cst.toStringAsFixed(2)} avoidable=${br.length} $br');
      }
      await t.scrollUntilVisible(findVisibleText('서비스 이용약관'), -120, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
      await _settle(t, 2);
      await vqCapture(t, key, '${c.id}_terms', conditions: {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'state': '내국인 약관 항목'});
      final semOk = find.bySemanticsLabel(RegExp('서비스 이용약관')).evaluate().isNotEmpty;
      out('${c.id} found=$found semanticsOriginal=$semOk summary avoidable=$avoid low=$low beforeObs=$_beforeObs');
      out('KNOWN ${avoid == 0 && low == 0 ? 'ok' : 'NG'} ${c.id} 제목 끊김 $avoid · 대비 $low');
      expect(t.takeException(), isNull);
      for (final e in found.entries) {
        expect(e.value, isTrue, reason: '${c.id} 원문 찾기 1개 · Text 하나: ${e.key}');
      }
      expect(semOk, isTrue, reason: '${c.id} 원문 낭독');
      expect(low, 0, reason: '${c.id} 대비');
      if (!_beforeObs) expect(avoid, 0, reason: '${c.id} 제목 끊김');
      sem.dispose();
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
}
