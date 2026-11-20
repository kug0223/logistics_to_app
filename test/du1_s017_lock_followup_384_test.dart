// [DU384] S017 저장 중 잠금 후속 — 하네스는 du1_s017_save_lock_380 바탕(seam templateService · 시험 열기 화면에서 push).
//   W 392x844@1.0 · B 320x640@2.0. 새 템플릿 이름 입력 → 저장(대기) 상태에서:
//   제품 기대(기본 단언, DU_BEFORE_OBSERVE=384 는 기록만):
//     ① 기본 끌기 시작 경로 꺼짐 — ReorderableListView.buildDefaultDragHandles == false,
//        카드 본문 길게 눌러 끌 때 끌기 프록시(같은 번호 칩 2개) 0
//     ② 진행 막대(LinearProgressIndicator) 본문 위 · 삭제 · 끌기 아이콘 비활성 모양(grey300)
//     ③ 실패 → 잠금 해제: 막대 0 · 기본 끌기 켜짐 · 아이콘 textTertiary.
//   불변(항상 단언): 저장 1회 · 실패 뒤 남음 · 넘침 0.
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
import 'package:ALfit/theme/app_colors.dart';
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
final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '384';

class _Svc extends ContractTemplateService {
  final pending = <Completer<Object?>>[];
  int calls = 0;
  @override
  Future<ContractTemplateModel> createTemplate({
    required String businessId,
    required String name,
    required String templateType,
    required List<ContractArticle> articles,
  }) async {
    calls++;
    final c = Completer<Object?>();
    pending.add(c);
    await c.future;
    return ContractTemplateModel(
        id: 'n', businessId: businessId, name: name, templateType: templateType, articles: articles, createdAt: DateTime(2026, 11, 16));
  }
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
          (_) async => codec.encodeMessage(<Object?>['du384.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du384.fake.$m'), (_) async => null);
    }
  });

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('S017K-${c.id} 저장 중 기본 끌기 · 상태 표시 · 비활성 모양 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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
                            businessId: kBiz, initialTemplateType: ContractTemplateType.daily, templateService: svc))),
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

      await settle();
      await t.tap(find.text('시험 열기'));
      await settle(14);
      final tag = 'S017K-${c.id}';
      final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};
      await t.enterText(find.byType(TextField).first, '냉장분류 계약서');
      FocusManager.instance.primaryFocus?.unfocus();
      await settle(4);
      await t.tap(find.ancestor(of: findVisibleText('저장').first, matching: find.byType(TextButton)).first);
      await settle(4);
      expect(svc.calls, 1, reason: '저장 1회(불변)');

      final checks = <String, bool>{};
      // ② 진행 막대 · 아이콘 모양
      checks['진행 막대'] = find.byType(LinearProgressIndicator).evaluate().isNotEmpty;
      await vqCapture(t, key, '${tag}_1saving', conditions: {...cond, 'state': '저장 중'});
      // 카드가 보이게(제5조 = 둘째 카드)
      await t.scrollUntilVisible(find.text('제5조'), 150, scrollable: find.byType(Scrollable).first, maxScrolls: 60);
      await t.drag(find.byType(Scrollable).first, Offset(0, c.h / 2 - t.getCenter(find.text('제5조')).dy));
      await settle(6);
      Color? iconColor(IconData i) => t.widget<Icon>(find.byIcon(i).first).color;
      checks['아이콘 비활성 모양'] = iconColor(Icons.drag_handle) == AppColors.grey300 && iconColor(Icons.close) == AppColors.grey300;
      // ① 기본 끌기 경로
      final rl = t.widget<ReorderableListView>(find.byType(ReorderableListView));
      checks['buildDefaultDragHandles 꺼짐'] = !rl.buildDefaultDragHandles;
      final cardBody = find.text('제5조');
      // [수리 1/3] 칩 아래 60 은 제목 입력 칸이라 길게 누르기를 입력 칸이 가져갔다(원본에서도 끌기 0 — 판별력 없음) — 번호 칩 자체를 길게 누른다
      final g = await t.startGesture(t.getCenter(cardBody));
      await t.pump(const Duration(milliseconds: 700)); // 길게 누르기
      await g.moveBy(const Offset(0, -30));
      await t.pump(const Duration(milliseconds: 100));
      await g.moveBy(const Offset(0, -30));
      await t.pump(const Duration(milliseconds: 100));
      // [수리 2/3] 끄는 항목은 제자리에서 빠지고 프록시로 그려져 칩 수가 그대로다 — 기본 프록시 장식(높이 있는 Material)의 유무로 판정한다
      final chips = find
          .ancestor(of: find.text('제5조'), matching: find.byWidgetPredicate((w) => w is Material && w.elevation > 0))
          .evaluate()
          .length;
      checks['길게 눌러 끌기 프록시 0'] = chips == 0;
      await g.up();
      await settle(16);
      await vqCapture(t, key, '${tag}_2card', conditions: {...cond, 'state': '저장 중 카드 머리'});

      // ③ 실패 → 잠금 해제
      svc.pending.first.completeError(Exception('합성: 저장 실패'));
      await settle(8);
      expect(find.byType(ContractTemplateEditScreen), findsOneWidget, reason: '실패 뒤 남음(불변)');
      final rl2 = t.widget<ReorderableListView>(find.byType(ReorderableListView));
      checks['실패 → 막대 0 · 기본 끌기 켜짐 · 아이콘 원래'] = find.byType(LinearProgressIndicator).evaluate().isEmpty &&
          rl2.buildDefaultDragHandles &&
          iconColor(Icons.drag_handle) == AppColors.textTertiary;

      _out('$tag checks=$checks chipsDuringDrag=$chips overflows=${overflows.length} beforeObs=$_beforeObs');
      final ok = checks.values.every((v) => v);
      _out('KNOWN ${ok ? 'ok' : 'NG'} $tag ${checks.entries.where((e) => !e.value).map((e) => e.key).toList()}');
      final exc = t.takeException();
      await t.pump(const Duration(seconds: 5));
      await t.pumpWidget(const SizedBox.shrink());
      await t.pump(const Duration(seconds: 1));
      expect(exc, isNull);
      expect(overflows, isEmpty, reason: '$tag 넘침(불변)');
      if (!_beforeObs) {
        for (final e in checks.entries) {
          expect(e.value, isTrue, reason: '$tag ${e.key}');
        }
      }
    });
  }
}
