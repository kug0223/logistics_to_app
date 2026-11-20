// [DU376] S017 조항 카드 머리 — 하네스는 du1_s017_contrast_375 바탕(seam templateService).
//   W 392x844@1.0 · B 320x640@2.0 × N(새 · 단기 기본 조항 3) · E(기존 · 기간제 + 긴 제목 조항).
//   제품 기대(기본 단언, DU_BEFORE_OBSERVE=376 은 기록만):
//     ① 끌기 · 삭제 receiver ≥ 48×48 ② 두 아이콘 색 ↔ 카드 면 ≥ 3.0(UI 요소)
//     ③ 화면 안 조항 제목 칸의 마지막 글자 caret 이 칸 안(잘림 0) ④ 삭제 receiver 모서리 탭 → 조항 1개 줄어듦
//   불변(항상 단언): ⑤ 제목 칸에 줄바꿈 입력 → 줄바꿈 없이 저장 값(한 줄 칸과 같은 데이터) ⑥ 넘침 0 · 예외 0.
//   기록: 끌기로 순서 바꾸기(첫 · 둘째 제목 순서).
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
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
final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '376';
const _longTitle = '제9조 (연장 · 야간 · 휴일근로 및 가산수당 지급 기준)';
const _titleHint = '조항 제목 (예: 제4조 (연장·야간근로 수당))';

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

Finder _titleFields() =>
    find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == _titleHint);

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    const codec = StandardMessageCodec();
    for (final m in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$m',
          (_) async => codec.encodeMessage(<Object?>['du376.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du376.fake.$m'), (_) async => null);
    }
  });

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    for (final flow in const ['N', 'E']) {
      testWidgets('S017H-${c.id} $flow 조항 카드 머리 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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
        final screen = flow == 'E'
            ? ContractTemplateEditScreen(
                businessId: kBiz,
                template: ContractTemplateModel(
                    id: 'tp1',
                    businessId: kBiz,
                    name: '기간제 장기 근무 기본 양식',
                    templateType: ContractTemplateType.period,
                    articles: [
                      const ContractArticle(title: _longTitle, content: '연장근로는 당사자 사이의 합의가 있어야 한다.'),
                      ...ContractTemplateModel.defaultArticlesFor(ContractTemplateType.period),
                    ],
                    createdAt: DateTime(2026, 11, 1)),
                templateService: _Svc())
            : ContractTemplateEditScreen(
                businessId: kBiz, initialTemplateType: ContractTemplateType.daily, templateService: _Svc());
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
              home: screen,
            ),
          ),
        ));
        Future<void> settle([int n = 6]) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }

        await settle(12);
        final tag = 'S017H-${c.id}_$flow';
        final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};
        final list = find.byType(Scrollable).first;
        // 첫 조항 카드가 보이게 — [수리 1/3] B 에서는 카드가 아직 만들어지지 않아 `.first` 찾기가 비었다. 번호 칩 글(유일)로 찾는다
        await t.scrollUntilVisible(find.text('제4조'), 150, scrollable: list, maxScrolls: 80);
        await t.drag(list, const Offset(0, -60));
        await settle(6);
        final countBefore = _titleFields().evaluate().length;

        // ① receiver
        final dragR = t.getRect(find.ancestor(of: find.byIcon(Icons.drag_handle).first, matching: find.byType(ReorderableDragStartListener)).first);
        final delGd = find.ancestor(of: find.byIcon(Icons.close).first, matching: find.byType(GestureDetector)).first;
        final delR = t.getRect(delGd);
        final recvOk = dragR.width >= 47.99 && dragR.height >= 47.99 && delR.width >= 47.99 && delR.height >= 47.99;
        // ② 아이콘 색
        final dragC = (t.widget<Icon>(find.byIcon(Icons.drag_handle).first)).color ?? Colors.black;
        final delC = (t.widget<Icon>(find.byIcon(Icons.close).first)).color ?? Colors.black;
        final iconCst = math.min(_contrast(dragC, Colors.white), _contrast(delC, Colors.white));
        // ③ 화면 안 제목 칸 잘림
        var cut = 0;
        final cutList = <String>[];
        for (final e in _titleFields().evaluate()) {
          final tf = e.widget as TextField;
          final r = t.getRect(find.byWidget(tf));
          if (r.bottom < 80 || r.top > c.h) continue;
          final ed = t.state<EditableTextState>(find.descendant(of: find.byWidget(tf), matching: find.byType(EditableText)).first);
          final re = ed.renderEditable;
          final text = tf.controller!.text;
          final caret = re.getLocalRectForCaret(TextPosition(offset: text.length));
          final inside = caret.right <= re.size.width + 0.5 && caret.bottom <= re.size.height + 0.5 && caret.left >= -0.5;
          if (!inside) {
            cut++;
            cutList.add('"${text.length > 16 ? text.substring(0, 16) : text}" caret=${caret.left.toStringAsFixed(1)},${caret.bottom.toStringAsFixed(1)} box=${re.size.width.toStringAsFixed(1)}x${re.size.height.toStringAsFixed(1)}');
          }
        }
        await vqCapture(t, key, '${tag}_1head', conditions: {...cond, 'state': '첫 조항 카드 머리'});
        // 긴 제목(E)
        if (flow == 'E') {
          final lf = find.byWidgetPredicate((w) => w is TextField && w.controller?.text == _longTitle);
          await t.scrollUntilVisible(lf, 120, scrollable: list, maxScrolls: 40);
          await settle(4);
          final tf = t.widget<TextField>(lf);
          final re = t.state<EditableTextState>(find.descendant(of: lf, matching: find.byType(EditableText)).first).renderEditable;
          final caret = re.getLocalRectForCaret(const TextPosition(offset: _longTitle.length));
          final inside = caret.right <= re.size.width + 0.5 && caret.bottom <= re.size.height + 0.5;
          if (!inside) {
            cut++;
            cutList.add('LONG caret=${caret.left.toStringAsFixed(1)},${caret.bottom.toStringAsFixed(1)} box=${re.size.width.toStringAsFixed(1)}x${re.size.height.toStringAsFixed(1)} maxLines=${tf.maxLines}');
          }
          await vqCapture(t, key, '${tag}_2long', conditions: {...cond, 'state': '긴 제목 조항'});
          await t.scrollUntilVisible(find.byIcon(Icons.drag_handle).first, -120, scrollable: list, maxScrolls: 40);
          await settle(4);
        }

        // ④ 삭제 receiver 모서리 탭
        // [수리 1/3] 아이콘 밖 · 48 상자 안(아이콘 중심에서 왼쪽 위 20) — 아이콘만 누르는 receiver 와 48 receiver 를 가른다
        // [수리 2/3] 높아진 머리에서 삭제 아이콘이 앱 바 바로 아래에 걸려 탭이 앱 바로 갔다 — 탭 전에 화면 가운데로 옮긴다
        await t.drag(list, Offset(0, c.h / 2 - t.getCenter(find.byIcon(Icons.close).first).dy));
        await settle(6);
        final iconNow = t.getRect(find.byIcon(Icons.close).first);
        final corner = iconNow.center + const Offset(-20, -20);
        await t.tapAt(corner);
        await settle(6);
        final countAfter = _titleFields().evaluate().length;
        final cornerDeleted = countAfter == countBefore - 1;

        // ⑤ 줄바꿈 입력 → 저장 값
        final firstTitle = _titleFields().first;
        await t.ensureVisible(firstTitle);
        await settle(2);
        await t.enterText(firstTitle, '시험 제목\n둘째 줄');
        await settle(2);
        final stored = t.widget<TextField>(firstTitle).controller!.text;
        final noNewline = !stored.contains('\n');
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(2);

        // 기록: 순서 바꾸기
        var reorder = 'n/a';
        if (find.byIcon(Icons.drag_handle).evaluate().length >= 2) {
          final before = _titleFields().evaluate().map((e) => (e.widget as TextField).controller!.text).take(2).toList();
          final g = await t.startGesture(t.getCenter(find.byIcon(Icons.drag_handle).at(1)));
          await t.pump(const Duration(milliseconds: 100));
          for (var i = 0; i < 10; i++) {
            await g.moveBy(const Offset(0, -40));
            await t.pump(const Duration(milliseconds: 30));
          }
          await g.up();
          await settle(16);
          final after = _titleFields().evaluate().map((e) => (e.widget as TextField).controller!.text).take(2).toList();
          reorder = '${before.join(' / ')} → ${after.join(' / ')}';
        }

        _out('$tag drag=${dragR.width.toStringAsFixed(1)}x${dragR.height.toStringAsFixed(1)} delete=${delR.width.toStringAsFixed(1)}x${delR.height.toStringAsFixed(1)} iconContrast=${iconCst.toStringAsFixed(2)} cut=$cut $cutList cornerTap=$corner deleted=$cornerDeleted($countBefore→$countAfter) stored="$stored" overflows=${overflows.length} reorder=[$reorder] beforeObs=$_beforeObs');
        final ok = recvOk && iconCst >= 3.0 && cut == 0 && cornerDeleted;
        _out('KNOWN ${ok ? 'ok' : 'NG'} $tag receiver $recvOk · 아이콘 ${iconCst.toStringAsFixed(2)} · 제목 잘림 $cut · 모서리 삭제 $cornerDeleted');
        expect(t.takeException(), isNull);
        expect(overflows, isEmpty, reason: '$tag 넘침(불변)');
        expect(noNewline, isTrue, reason: '$tag 제목 줄바꿈 없음(불변)');
        if (!_beforeObs) {
          expect(recvOk, isTrue, reason: '$tag 끌기 · 삭제 48');
          expect(iconCst, greaterThanOrEqualTo(3.0), reason: '$tag 아이콘 대비');
          expect(cut, 0, reason: '$tag 제목 잘림');
          expect(cornerDeleted, isTrue, reason: '$tag 삭제 receiver 모서리');
        }
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 1));
      });
    }
  }
}
