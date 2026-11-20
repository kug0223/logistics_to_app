// [DU380] S017 저장 중 잠금 · 순서 변경 dirty(소급 16 §2) — 하네스는 du1_s017_discard_377 바탕(seam templateService · 시험 열기 화면에서 push).
//   합성 서비스는 create/update 를 Completer 로 붙잡고 호출마다 payload(이름 · 조항 제목 순서)를 기록한다.
//   L(새 · W/B): 이름 입력 → 저장(대기) → 입력 칸 읽기 전용 · 조항 추가/삭제/순서 0 · 뒤로/홈/알림 막음 · 저장 1회
//     → 그 사이 위에 다른 화면 push → 성공 → 편집 route 만 true 1회로 닫힘 · 위 화면 그대로.
//   F(새 · W/B): 저장(대기) → 실패 → 입력 · 순서 그대로 · 잠금 해제 · 같은 payload 로 재시도.
//   D(기존 · 변경 없음 · W/B): 저장(대기) 중 뒤로 → 나가지 않음 → 성공 → true 1회.
//   R-E · R-N(W): 순서만 바꿈 → 뒤로 → 버림 확인 → 계속 편집 → 저장 payload 순서 = 바꾼 순서.
//   S 정적: 제자리 놓기(newIndex == oldIndex)는 변경 아님 · semantics '조항 삭제'.
//   제품 기대(기본 단언, DU_BEFORE_OBSERVE=380 은 기록만). 흐름(화면 도달 · 저장 호출 · 넘침 0)은 항상 단언.
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:async';
import 'dart:io';

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
final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '380';

class _Svc extends ContractTemplateService {
  final pending = <Completer<Object?>>[];
  final payloads = <String>[];
  @override
  Future<ContractTemplateModel> createTemplate({
    required String businessId,
    required String name,
    required String templateType,
    required List<ContractArticle> articles,
  }) async {
    payloads.add('$name|${articles.map((a) => a.title).join('/')}');
    final c = Completer<Object?>();
    pending.add(c);
    await c.future;
    return ContractTemplateModel(
        id: 'new1', businessId: businessId, name: name, templateType: templateType, articles: articles, createdAt: DateTime(2026, 11, 15));
  }

  @override
  Future<void> updateTemplate(ContractTemplateModel template) async {
    payloads.add('${template.name}|${template.articles.map((a) => a.title).join('/')}');
    final c = Completer<Object?>();
    pending.add(c);
    await c.future;
  }
}

ContractTemplateModel _existing() => ContractTemplateModel(
    id: 'tp1',
    businessId: kBiz,
    name: '기간제 장기 근무 기본 양식',
    templateType: ContractTemplateType.period,
    articles: ContractTemplateModel.defaultArticlesFor(ContractTemplateType.period),
    createdAt: DateTime(2026, 11, 1));

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
          (_) async => codec.encodeMessage(<Object?>['du380.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du380.fake.$m'), (_) async => null);
    }
  });

  test('S 정적: 제자리 놓기는 변경 아님 · semantics 조항 삭제', () {
    final src = File('lib/screens/business_admin/contract_template_edit_screen.dart').readAsStringSync();
    final checks = {
      '제자리 놓기 return': src.contains('if (newIndex == oldIndex) return;'),
      '순서 변경 dirty': src.contains('_hasChanges = true; // [DU380] 순서만 바꿔도 변경'),
      "semantics '조항 삭제'": src.contains("label: '조항 삭제'") && !src.contains("label: '문단 삭제'"),
    };
    _out('S checks=$checks beforeObs=$_beforeObs');
    _out('KNOWN ${checks.values.every((v) => v) ? 'ok' : 'NG'} S 정적');
    if (!_beforeObs) {
      for (final e in checks.entries) {
        expect(e.value, isTrue, reason: e.key);
      }
    }
  });

  Future<({GlobalKey key, _Svc svc, List<Object?> results})> mount(WidgetTester t, ({String id, double w, double h, double s}) c,
      {ContractTemplateModel? template}) async {
    await t.runAsync(vqLoadFonts);
    t.view.physicalSize = Size(c.w, c.h);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    final key = GlobalKey();
    final svc = _Svc();
    final results = <Object?>[];
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
                  onPressed: () async {
                    final r = await Navigator.of(ctx).push<Object?>(MaterialPageRoute(
                        builder: (_) => template == null
                            ? ContractTemplateEditScreen(
                                businessId: kBiz, initialTemplateType: ContractTemplateType.daily, templateService: svc)
                            : ContractTemplateEditScreen(businessId: kBiz, template: template, templateService: svc)));
                    results.add(r);
                  },
                  child: const Text('시험 열기'),
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    await t.tap(find.text('시험 열기'));
    for (var i = 0; i < 14; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
    return (key: key, svc: svc, results: results);
  }

  Future<void> settle(WidgetTester t, [int n = 10]) async {
    for (var i = 0; i < n; i++) {
      await t.pump(const Duration(milliseconds: 50));
    }
  }

  bool onEdit() => find.byType(ContractTemplateEditScreen).evaluate().isNotEmpty;
  int cards() => find.byIcon(Icons.drag_handle).evaluate().length + 0;
  int titleFields() =>
      find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == '조항 제목 (예: 제4조 (연장·야간근로 수당))').evaluate().length;
  List<String> titles() => find
      .byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == '조항 제목 (예: 제4조 (연장·야간근로 수당))')
      .evaluate()
      .map((e) => (e.widget as TextField).controller!.text)
      .toList();
  Finder saveBtn() => find.ancestor(of: findVisibleText('저장').first, matching: find.byType(TextButton)).first;
  Finder saveAny() => find.byWidgetPredicate((w) => w is TextButton && (w.child is SizedBox || (w.child is Text && (w.child as Text).data == '저장')));

  Future<void> tapSave(WidgetTester t) async {
    await t.tap(saveBtn());
    await settle(t, 4);
  }

  IconButton iconBtn(WidgetTester t, IconData icon) =>
      t.widget<IconButton>(find.ancestor(of: find.byIcon(icon), matching: find.byType(IconButton)).first);

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    final cond = <String, Object?>{'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};

    testWidgets('S017S-${c.id} L 저장 중 잠금 · 위 화면 · 성공 true 1회 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
      final m = await mount(t, c);
      final tag = 'S017S-${c.id}_L';
      await t.enterText(find.byType(TextField).first, '냉장분류 계약서');
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(t, 4);
      await tapSave(t);
      expect(m.svc.payloads, hasLength(1), reason: '저장 호출(흐름)');
      final checks = <String, bool>{};
      // 입력 칸 읽기 전용
      final fields = find.byType(TextField).evaluate().map((e) => e.widget as TextField).toList();
      checks['입력 칸 모두 읽기 전용'] = fields.isNotEmpty && fields.every((f) => f.readOnly);
      await vqCapture(t, m.key, '${tag}_1saving', conditions: {...cond, 'state': '저장 중'});
      // 조항 추가 — [수리 1/3] 버튼이 목록 아래라 아직 만들어지지 않았다. 내려서 만든 뒤 센다(안쪽 목록은 shrinkWrap 이라 통째로 만들어진다)
      await t.scrollUntilVisible(findVisibleText('조항 추가'), 200, scrollable: find.byType(Scrollable).first, maxScrolls: 80);
      await settle(t, 4);
      final cardsBefore = titleFields();
      final add = find.ancestor(of: findVisibleText('조항 추가').first, matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;
      await t.ensureVisible(add);
      await settle(t, 2);
      await t.tap(add, warnIfMissed: false);
      await settle(t, 6);
      checks['조항 추가 0'] = titleFields() == cardsBefore;
      // 조항 삭제 — [수리 2/3] 버튼에 가까운 마지막 카드를 가운데로(첫 카드까지 올리면 B 에서 안쪽 목록이 캐시 밖으로 나간다).
      //   판정은 추가 시도 뒤 수와 비교한다(추가 +1 · 삭제 -1 이 우연히 같아지는 것 방지).
      final afterAdd = titleFields();
      await t.drag(find.byType(Scrollable).first, Offset(0, c.h / 2 - t.getCenter(find.byIcon(Icons.close).last).dy));
      await settle(t, 6);
      await t.tap(find.byIcon(Icons.close).last, warnIfMissed: false);
      await settle(t, 6);
      checks['조항 삭제 0'] = titleFields() == afterAdd;
      // 뒤로 · 홈 · 알림
      unawaited(navigatorKey.currentState!.maybePop());
      await settle(t, 10);
      checks['뒤로 → 남음 · 버림 창 0'] = onEdit() && findVisibleText('편집 취소').evaluate().isEmpty;
      checks['홈 · 알림 비활성'] = iconBtn(t, Icons.home_outlined).onPressed == null && iconBtn(t, Icons.notifications_outlined).onPressed == null;
      // 저장 다시 눌러도 1회
      final sv = t.widget<TextButton>(saveAny().first);
      checks['저장 버튼 비활성 · 호출 1'] = sv.onPressed == null && m.svc.payloads.length == 1;
      // 위에 다른 화면 push → 성공
      unawaited(navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => const Scaffold(body: Center(child: Text('위 화면'))))));
      await settle(t, 14);
      m.svc.pending.first.complete(null);
      await settle(t, 16);
      checks['성공 → 편집 route true 1회'] = m.results.length == 1 && m.results.first == true;
      checks['위 화면 그대로'] = find.text('위 화면').evaluate().isNotEmpty;
      checks['편집 화면 닫힘'] = !onEdit();
      _out('$tag checks=$checks results=${m.results} payloads=${m.svc.payloads} beforeObs=$_beforeObs');
      final ok = checks.values.every((v) => v);
      _out('KNOWN ${ok ? 'ok' : 'NG'} $tag ${checks.entries.where((e) => !e.value).map((e) => e.key).toList()}');
      expect(t.takeException(), isNull);
      if (!_beforeObs) {
        for (final e in checks.entries) {
          expect(e.value, isTrue, reason: '$tag ${e.key}');
        }
      }
      await t.pump(const Duration(seconds: 3));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('S017S-${c.id} F 실패 보존 · 재시도 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
      final m = await mount(t, c);
      final tag = 'S017S-${c.id}_F';
      await t.enterText(find.byType(TextField).first, '냉장분류 계약서');
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(t, 4);
      final before = titles();
      await tapSave(t);
      expect(m.svc.payloads, hasLength(1), reason: '저장 호출(흐름)');
      m.svc.pending.first.completeError(Exception('합성: 저장 실패'));
      await settle(t, 6);
      final checks = <String, bool>{};
      checks['남음'] = onEdit();
      checks['이름 · 순서 그대로'] =
          (find.byType(TextField).evaluate().first.widget as TextField).controller!.text == '냉장분류 계약서' && titles().join('/') == before.join('/');
      checks['잠금 해제'] = find.byType(TextField).evaluate().every((e) => !(e.widget as TextField).readOnly);
      checks['오류 안내'] = findVisibleText('저장에 실패했습니다').evaluate().isNotEmpty;
      await vqCapture(t, m.key, '${tag}_1fail', conditions: {...cond, 'state': '저장 실패 뒤'});
      await t.pump(const Duration(seconds: 5));
      await tapSave(t);
      checks['재시도 같은 payload'] = m.svc.payloads.length == 2 && m.svc.payloads[0] == m.svc.payloads[1];
      m.svc.pending.last.complete(null);
      await settle(t, 16);
      checks['재시도 성공 true 1회'] = m.results.length == 1 && m.results.first == true;
      _out('$tag checks=$checks results=${m.results} beforeObs=$_beforeObs');
      final ok = checks.values.every((v) => v);
      _out('KNOWN ${ok ? 'ok' : 'NG'} $tag ${checks.entries.where((e) => !e.value).map((e) => e.key).toList()}');
      expect(t.takeException(), isNull);
      if (!_beforeObs) {
        for (final e in checks.entries) {
          expect(e.value, isTrue, reason: '$tag ${e.key}');
        }
      }
      await t.pump(const Duration(seconds: 3));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
    });

    testWidgets('S017S-${c.id} D 변경 없음 저장 중 뒤로 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
      final m = await mount(t, c, template: _existing());
      final tag = 'S017S-${c.id}_D';
      await tapSave(t);
      expect(m.svc.payloads, hasLength(1), reason: '저장 호출(흐름)');
      unawaited(navigatorKey.currentState!.maybePop());
      await settle(t, 12);
      final checks = <String, bool>{};
      checks['변경 없어도 저장 중 남음'] = onEdit() && m.results.isEmpty;
      m.svc.pending.first.complete(null);
      await settle(t, 16);
      checks['성공 true 1회'] = m.results.length == 1 && m.results.first == true;
      _out('$tag checks=$checks results=${m.results} beforeObs=$_beforeObs');
      final ok = checks.values.every((v) => v);
      _out('KNOWN ${ok ? 'ok' : 'NG'} $tag ${checks.entries.where((e) => !e.value).map((e) => e.key).toList()}');
      expect(t.takeException(), isNull);
      if (!_beforeObs) {
        for (final e in checks.entries) {
          expect(e.value, isTrue, reason: '$tag ${e.key}');
        }
      }
      await t.pump(const Duration(seconds: 3));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
    });
  }

  for (final flow in const ['E', 'N']) {
    testWidgets('S017S-W R-$flow 순서만 변경 dirty 392x844@1.0', (t) async {
      const c = (id: 'W', w: 392.0, h: 844.0, s: 1.0);
      final m = await mount(t, c, template: flow == 'E' ? _existing() : null);
      final tag = 'S017S-W_R$flow';
      // 새 템플릿도 이름을 치기 전에는 변경이 아니다 — 순서만 바꾼 뒤 뒤로를 본다(이름은 저장 직전에 넣는다)
      await t.scrollUntilVisible(find.text('제5조'), 150, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
      await settle(t, 4);
      final before = titles();
      final g = await t.startGesture(t.getCenter(find.byIcon(Icons.drag_handle).at(1)));
      await t.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(0, -40));
        await t.pump(const Duration(milliseconds: 30));
      }
      await g.up();
      await settle(t, 16);
      final after = titles();
      final moved = before.join('/') != after.join('/');
      expect(moved, isTrue, reason: '순서 바뀜(흐름)');
      final checks = <String, bool>{};
      unawaited(navigatorKey.currentState!.maybePop());
      await settle(t, 10);
      checks['순서만 변경 → 뒤로 → 버림 확인'] = findVisibleText('편집 취소').evaluate().isNotEmpty;
      if (findVisibleText('계속 편집').evaluate().isNotEmpty) {
        await t.tap(findVisibleText('계속 편집'));
        await settle(t, 8);
      }
      checks['남음'] = onEdit();
      if (flow == 'N' && onEdit()) {
        // [수리 3/3] `TextField.first` 는 늘 무언가를 찾아 스크롤하지 않고 조항 제목 칸에 쳤다 — 이름 칸 예시 글로 찾는다
        final name = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == '예) 냉장분류 계약서, 일반 단기 계약서');
        await t.scrollUntilVisible(name, -200, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
        await t.enterText(name, '냉장분류 계약서');
        FocusManager.instance.primaryFocus?.unfocus();
        await settle(t, 4);
      }
      if (!onEdit()) {
        _out('$tag 편집 화면이 이미 닫혔다(확인창 없이 나감) — 저장 순서 확인 불가');
      } else {
        await tapSave(t);
      }
      final pl = m.svc.payloads.isEmpty ? '' : m.svc.payloads.last;
      final savedOrder = pl.contains('|') ? pl.split('|')[1] : '';
      checks['저장 순서 = 바꾼 순서'] = savedOrder == after.where((s) => s.isNotEmpty).join('/');
      if (m.svc.pending.isNotEmpty) m.svc.pending.last.complete(null);
      await settle(t, 16);
      _out('$tag before=$before after=$after saved=$savedOrder checks=$checks beforeObs=$_beforeObs');
      final ok = checks.values.every((v) => v);
      _out('KNOWN ${ok ? 'ok' : 'NG'} $tag ${checks.entries.where((e) => !e.value).map((e) => e.key).toList()}');
      expect(t.takeException(), isNull);
      if (!_beforeObs) {
        for (final e in checks.entries) {
          expect(e.value, isTrue, reason: '$tag ${e.key}');
        }
      }
      await t.pump(const Duration(seconds: 3));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
    });
  }
}
