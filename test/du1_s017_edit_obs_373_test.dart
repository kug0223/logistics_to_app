// [DU373] S017 계약서 템플릿 편집(ContractTemplateEditScreen) — seam(templateService 주입, DU344 방식) 뒤 before 관측.
//   하네스는 du1_s018_load_truth_353 바탕. 제품 표시 변경 0 — 이 셀의 단언은 흐름 · seam 계약만, 나머지는 KNOWN 기록.
//   W 392x844@1.0 · B 320x640@2.0. 합성 서비스는 저장(create/update)만 대신한다(Completer 로 저장 중을 붙잡는다).
//   N(새 템플릿 · 단기): 첫 화면 · 끝까지 스크롤 · 터치 영역 → 빈 이름 저장 → 이름 입력 → 저장 중 → 실패 → 변경 버림 확인창(계속 편집) → 다시 저장 → 성공.
//   E(기존 · 기간제 · 긴 조항): 첫 화면 → 조항 내용 칸 초점 + 키보드(가상 viewInsets 0.4h).
//   O(새 템플릿 · 도급): 유형 배지.
//   기록: 넘침 · 대비 < 4.5 · 낱말 안 끊김 · 터치 < 48 · 저장 중 편집 가능 여부 · 확인창 '나가기' 대비.
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

class _Svc extends ContractTemplateService {
  final creates = <Completer<ContractTemplateModel>>[];
  final createdNames = <String>[];
  final updates = <Completer<void>>[];
  @override
  Future<ContractTemplateModel> createTemplate({
    required String businessId,
    required String name,
    required String templateType,
    required List<ContractArticle> articles,
  }) {
    createdNames.add(name);
    final c = Completer<ContractTemplateModel>();
    creates.add(c);
    return c.future;
  }

  @override
  Future<void> updateTemplate(ContractTemplateModel template) {
    final c = Completer<void>();
    updates.add(c);
    return c.future;
  }
}

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

ContractTemplateModel _periodLong() => ContractTemplateModel(
      id: 'tp1',
      businessId: kBiz,
      name: '기간제 장기 근무 기본 양식(물류센터 야간 분류 · 상하차 겸용)',
      templateType: ContractTemplateType.period,
      articles: [
        ...ContractTemplateModel.defaultArticlesFor(ContractTemplateType.period),
        const ContractArticle(
          title: '제9조 (연장 · 야간 · 휴일근로 및 가산수당 지급 기준)',
          content: '근로자가 사용자의 지시에 따라 소정근로시간을 넘어 일하거나 야간(오후 10시부터 오전 6시까지) 또는 '
              '휴일에 일한 경우, 사용자는 근로기준법에서 정한 바에 따라 통상임금의 50퍼센트 이상을 가산하여 지급한다. '
              '연장근로는 당사자 사이의 합의가 있어야 하며, 1주 12시간을 넘지 않는다.',
        ),
      ],
      createdAt: DateTime(2026, 11, 1),
    );

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
          (_) async => codec.encodeMessage(<Object?>['du373.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du373.fake.$m'), (_) async => null);
    }
  });

  test('SEAM 정적: 주입이 없으면 기존 ContractTemplateService() · 세 호출부는 주입하지 않는다', () {
    final src = File('lib/screens/business_admin/contract_template_edit_screen.dart').readAsStringSync();
    // [수리 1/3] 주석(seam 설명)에 든 글은 세지 않는다 — 코드 줄만
    final code = src.split('\n').where((l) => !l.trimLeft().startsWith('//')).join('\n');
    final checks = <String, bool>{
      '기본 경로': code.contains('widget.templateService ?? ContractTemplateService()'),
      '생성 호출 하나': 'ContractTemplateService()'.allMatches(code).length == 1,
    };
    for (final p in const [
      'lib/screens/business_admin/contract_template_list_screen.dart',
      'lib/screens/business_admin/contract_import_result_screen.dart',
      'lib/widgets/dialogs/contract_template_selector_dialog.dart',
    ]) {
      final s = File(p).readAsStringSync();
      var i = s.indexOf('ContractTemplateEditScreen(');
      var n = 0;
      var injected = false;
      while (i >= 0) {
        n++;
        final end = s.indexOf('),', i);
        if (s.substring(i, end < 0 ? s.length : end).contains('templateService')) injected = true;
        i = s.indexOf('ContractTemplateEditScreen(', i + 1);
      }
      checks['${p.split('/').last} 호출 $n · 주입 없음'] = n > 0 && !injected;
    }
    _out('SEAM checks=$checks');
    for (final e in checks.entries) {
      expect(e.value, isTrue, reason: e.key);
    }
  });

  Widget app(GlobalKey key, double s, Widget Function() screen, void Function(Object?) onResult) => RepaintBoundary(
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
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(s)), child: child!),
            home: Builder(
              builder: (ctx) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () async {
                      final r = await Navigator.of(ctx).push<Object?>(MaterialPageRoute(builder: (_) => screen()));
                      onResult(r);
                    },
                    child: const Text('시험 열기'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    final cond = <String, Object?>{'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};

    Future<void> run(WidgetTester t, String flow) async {
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
      final svc = _Svc();
      Object? result = 'not-popped';
      Widget screen() => switch (flow) {
            'E' => ContractTemplateEditScreen(businessId: kBiz, template: _periodLong(), templateService: svc),
            'O' => ContractTemplateEditScreen(
                businessId: kBiz, initialTemplateType: ContractTemplateType.outsource, templateService: svc),
            _ => ContractTemplateEditScreen(
                businessId: kBiz, initialTemplateType: ContractTemplateType.daily, templateService: svc),
          };
      await t.pumpWidget(app(key, c.s, screen, (r) => result = r));
      Future<void> settle([int n = 10]) async {
        for (var i = 0; i < n; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }

      await settle();
      await t.tap(find.text('시험 열기'));
      await settle(14);
      final tagBase = 'S017-${c.id}_$flow';

      var low = 0, avoid = 0;
      final seen = <String>{};
      void dump(String tg) {
        for (final e in find.byType(RichText).evaluate()) {
          final rp = e.renderObject! as RenderParagraph;
          final s = visibleText(rp.text.toPlainText());
          if (s.trim().isEmpty) continue;
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
              _out('$tg avoidable "$s" $b');
            }
          }
          final cst = col == null ? 99.0 : _contrast(_overWhite(col), bg);
          if (cst < 4.5) {
            low++;
            _out('$tg low "${s.length > 40 ? s.substring(0, 40) : s}" contrast=${cst.toStringAsFixed(2)} color=0x${col!.toARGB32().toRadixString(16)}');
          }
        }
        // 입력 칸 예시 글(hint) — RichText 가 아니라 InputDecorator 가 그린다
        for (final e in find.byType(TextField).evaluate()) {
          final tf = e.widget as TextField;
          final hint = tf.decoration?.hintText;
          final hc = tf.decoration?.hintStyle?.color;
          if (hint == null || hc == null) continue;
          final k = 'hint:$hint';
          if (seen.contains(k)) continue;
          final r = t.getRect(find.byWidget(tf));
          if (r.bottom < 0 || r.top > c.h) continue;
          seen.add(k);
          final cst = _contrast(_overWhite(hc), _bgOf(e));
          if (cst < 4.5) {
            low++;
            _out('$tg low hint "${hint.length > 30 ? hint.substring(0, 30) : hint}" contrast=${cst.toStringAsFixed(2)}');
          }
        }
      }

      void targets(String tg) {
        final rows = <String>[];
        Rect? rectOf(Finder f) => f.evaluate().isEmpty ? null : t.getRect(f.first);
        final del = rectOf(find.ancestor(of: find.byIcon(Icons.close), matching: find.byType(GestureDetector)));
        final drag = rectOf(find.ancestor(of: find.byIcon(Icons.drag_handle), matching: find.byType(ReorderableDragStartListener)));
        final save = rectOf(find.ancestor(of: findVisibleText('저장'), matching: find.byType(TextButton)));
        for (final (n, r) in [('문단 삭제', del), ('끌기 손잡이', drag), ('저장', save)]) {
          if (r == null) continue;
          final ok = r.width >= 48 - 0.01 && r.height >= 48 - 0.01;
          rows.add('$n ${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}${ok ? '' : ' <48'}');
        }
        _out('$tg targets $rows');
      }

      if (flow == 'N') {
        // ① 첫 화면
        dump('${tagBase}_1top');
        targets('${tagBase}_1top');
        await vqCapture(t, key, '${tagBase}_1top', conditions: {...cond, 'state': '새 템플릿(단기) 첫 화면'});
        // ② 끝까지 스크롤
        await t.drag(find.byType(ListView).first, const Offset(0, -3000));
        await settle(8);
        dump('${tagBase}_2end');
        await vqCapture(t, key, '${tagBase}_2end', conditions: {...cond, 'state': '끝까지 스크롤(조항 추가)'});
        await t.drag(find.byType(ListView).first, const Offset(0, 3000));
        await settle(8);
        // ③ 빈 이름 저장 → 경고
        await t.tap(find.ancestor(of: findVisibleText('저장'), matching: find.byType(TextButton)).first);
        await t.pump(const Duration(milliseconds: 150));
        final warn = findVisibleText('템플릿 이름을 입력해주세요');
        _out('$tagBase empty-name toast=${warn.evaluate().isNotEmpty} creates=${svc.creates.length}');
        expect(svc.creates, isEmpty, reason: '빈 이름은 저장 호출 없음(흐름)');
        await vqCapture(t, key, '${tagBase}_3empty', conditions: {...cond, 'state': '빈 이름 저장 → 경고'});
        await t.pump(const Duration(seconds: 3));
        // ④ 이름 입력 → 저장 중
        await t.enterText(find.byType(TextField).first, '냉장분류 계약서');
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(4);
        await t.tap(find.ancestor(of: findVisibleText('저장'), matching: find.byType(TextButton)).first);
        await settle(4);
        expect(svc.creates, hasLength(1), reason: '저장 1회(흐름)');
        final spinner = find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        final enabledFields = find.byType(TextField).evaluate().where((e) => (e.widget as TextField).enabled != false).length;
        _out('$tagBase saving spinner=$spinner editableFields=$enabledFields/${find.byType(TextField).evaluate().length}');
        await vqCapture(t, key, '${tagBase}_4saving', conditions: {...cond, 'state': '저장 중'});
        // 저장 중 다시 눌러도 1회
        final saveBtn = find.byType(TextButton).evaluate().map((e) => e.widget as TextButton).where((b) => b.child is SizedBox);
        _out('$tagBase saving saveButtonDisabled=${saveBtn.isNotEmpty && saveBtn.first.onPressed == null}');
        // ⑤ 실패
        svc.creates.first.completeError(Exception('합성: 저장 실패'));
        await settle(4);
        final failToast = findVisibleText('저장에 실패했습니다').evaluate().isNotEmpty;
        final stillHere = find.byType(ContractTemplateEditScreen).evaluate().isNotEmpty;
        _out('$tagBase fail toast=$failToast stillHere=$stillHere saveAgain=${findVisibleText('저장').evaluate().isNotEmpty}');
        expect(stillHere, isTrue, reason: '실패하면 화면에 남는다(흐름)');
        dump('${tagBase}_5fail');
        await vqCapture(t, key, '${tagBase}_5fail', conditions: {...cond, 'state': '저장 실패 토스트'});
        await t.pump(const Duration(seconds: 5));
        // ⑥ 변경 버림 확인창 → 계속 편집
        unawaited(navigatorKey.currentState!.maybePop());
        await settle(8);
        // [DU377 추종] 확인창 셸이 기본 AlertDialog → 공용 셸(DialogHelper)로 바뀌었다 — 위젯 형식이 아니라 제목 글로 찾는다(같은 계약)
        final dlg = findVisibleText('편집 취소').evaluate().isNotEmpty;
        _out('$tagBase discard dialog=$dlg');
        expect(dlg, isTrue, reason: '변경이 있으면 확인창(흐름)');
        dump('${tagBase}_6discard');
        await vqCapture(t, key, '${tagBase}_6discard', conditions: {...cond, 'state': '변경 버림 확인창'});
        await t.tap(findVisibleText('계속 편집'));
        await settle(6);
        expect(find.byType(ContractTemplateEditScreen), findsOneWidget, reason: '계속 편집 → 남음(흐름)');
        // ⑦ 다시 저장 → 성공
        await t.tap(find.ancestor(of: findVisibleText('저장'), matching: find.byType(TextButton)).first);
        await settle(4);
        expect(svc.creates, hasLength(2), reason: '재시도 저장(흐름)');
        svc.creates.last.complete(ContractTemplateModel(
            id: 'new1', businessId: kBiz, name: '냉장분류 계약서', templateType: ContractTemplateType.daily,
            articles: const [], createdAt: DateTime(2026, 11, 15)));
        await settle(10);
        _out('$tagBase success popped=${find.byType(ContractTemplateEditScreen).evaluate().isEmpty} result=$result names=${svc.createdNames}');
        expect(result, true, reason: '성공 → true 로 닫힘(흐름)');
        await t.pump(const Duration(seconds: 3));
      } else if (flow == 'E') {
        dump('${tagBase}_1top');
        targets('${tagBase}_1top');
        await vqCapture(t, key, '${tagBase}_1top', conditions: {...cond, 'state': '기존 템플릿(기간제 · 긴 이름) 첫 화면'});
        // 긴 조항 내용 칸 초점 + 키보드
        final longField = find.byWidgetPredicate((w) => w is TextField && (w.controller?.text.startsWith('근로자가 사용자의 지시에') ?? false));
        // [수리 1/3] B 에서는 그 카드가 화면 밖이라 아직 만들어지지 않았다 — 목록을 내려 만든 뒤 보이게 한다
        await t.scrollUntilVisible(longField, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
        await settle(4);
        await t.ensureVisible(longField);
        await settle(4);
        await t.tap(longField);
        await settle(4);
        final kb = (c.h * 0.4).roundToDouble();
        t.view.viewInsets = FakeViewPadding(bottom: kb);
        await settle(10);
        final r = t.getRect(longField);
        final cursorVisible = r.top < c.h - kb;
        _out('$tagBase keyboard field=${r.top.toStringAsFixed(1)}–${r.bottom.toStringAsFixed(1)} limit=${(c.h - kb).toStringAsFixed(1)} topVisible=$cursorVisible');
        dump('${tagBase}_2kb');
        await vqCapture(t, key, '${tagBase}_2keyboard', conditions: {...cond, 'state': '긴 조항 내용 칸 + 키보드 ${kb.toInt()}'});
        t.view.resetViewInsets();
        await settle(4);
      } else {
        dump('${tagBase}_1top');
        await vqCapture(t, key, '${tagBase}_1top', conditions: {...cond, 'state': '새 템플릿(도급) 유형 배지'});
      }
      _out('KNOWN ${overflows.isEmpty ? 'ok' : 'NG'} $tagBase 넘침 ${overflows.length} ${overflows.toSet()}');
      _out('KNOWN ${low == 0 ? 'ok' : 'NG'} $tagBase 대비 미달 $low');
      _out('KNOWN ${avoid == 0 ? 'ok' : 'NG'} $tagBase 낱말 안 끊김 $avoid');
      expect(t.takeException(), isNull);
      await t.pump(const Duration(seconds: 5));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 5));
    }

    for (final flow in const ['N', 'E', 'O']) {
      testWidgets('S017-${c.id} $flow 관측 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) => run(t, flow));
    }
  }
}
