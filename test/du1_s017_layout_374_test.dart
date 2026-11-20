// [DU374] S017 계약서 템플릿 편집 B 넘침 — 유형 배지 · 고정 상단 행 · '편집 가능 조항' 머리(배치만, 문구 · 색 그대로).
//   하네스는 du1_s017_edit_obs_373 바탕(seam templateService). W 392x844@1.0 · B 320x640@2.0.
//   흐름: N(새 · 단기) · E(기존 · 기간제) · O(새 · 도급 '기타').
//   제품 기대(기본 단언, DU_BEFORE_OBSERVE=374 는 기록만):
//     ① 넘침 0(화면 전체) ② 배지 · 고정 행 6글 · 머리 2글이 화면 폭 안 ③ 그 글들의 낱말 안 끊김 0
//     ④ 고정 행 자물쇠 중심 ↔ 제목 첫 줄 중심 ≤ 1px.
// ignore_for_file: depend_on_referenced_packages, unused_element
import 'dart:async';
import 'dart:io';

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
final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '374';

class _Svc extends ContractTemplateService {}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

const _fixed = [
  '제1조 (근로계약 당사자)', '사업장 정보 + 근로자 정보 자동 입력',
  '제2조 (근무 조건)', '공고 데이터 자동 입력',
  '제3조 (임금)', '업무상세 임금 정보 자동 입력',
];

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    const codec = StandardMessageCodec();
    for (final m in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$m',
          (_) async => codec.encodeMessage(<Object?>['du374.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du374.fake.$m'), (_) async => null);
    }
  });

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    for (final flow in const ['N', 'E', 'O']) {
      testWidgets('S017L-${c.id} $flow 배치 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
        await t.runAsync(vqLoadFonts);
        final overflows = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            final at = RegExp(r'contract_template_edit_screen\.dart:(\d+)').firstMatch(d.toString())?.group(1) ?? '?';
            overflows.add('${m.split('\n').first} @L$at');
          } else {
            prev?.call(d);
          }
        };
        addTearDown(() => FlutterError.onError = prev);
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        final type = switch (flow) {
          'E' => ContractTemplateType.period,
          'O' => ContractTemplateType.outsource,
          _ => ContractTemplateType.daily,
        };
        final screen = flow == 'E'
            ? ContractTemplateEditScreen(
                businessId: kBiz,
                template: ContractTemplateModel(
                    id: 'tp1', businessId: kBiz, name: '기간제 장기 근무 기본 양식', templateType: type,
                    articles: ContractTemplateModel.defaultArticlesFor(type), createdAt: DateTime(2026, 11, 1)),
                templateService: _Svc())
            : ContractTemplateEditScreen(businessId: kBiz, initialTemplateType: type, templateService: _Svc());
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
        for (var i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final tag = 'S017L-${c.id}_$flow';
        final scroll = find.byType(Scrollable).first;

        var outside = 0, avoid = 0;
        Future<void> measure(String text) async {
          final f = find.text(text);
          await t.scrollUntilVisible(f, 120, scrollable: scroll, maxScrolls: 80);
          for (var i = 0; i < 4; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          final rt = find.descendant(of: f.first, matching: find.byType(RichText), matchRoot: true).first;
          final rp = t.renderObject<RenderParagraph>(rt);
          final r = t.getRect(rt);
          final inside = r.left >= -0.5 && r.right <= c.w + 0.5;
          final br = wordBreaks(rp).where((b) => !b.forced).toList();
          if (!inside) outside++;
          avoid += br.length;
          _out('$tag "$text" rect=${r.left.toStringAsFixed(1)}–${r.right.toStringAsFixed(1)} inside=$inside avoidable=${br.length} $br');
        }

        final label = ContractTemplateType.label(type);
        final desc = ContractTemplateType.description(type);
        await measure(label);
        if (desc.isNotEmpty) await measure(desc);
        await vqCapture(t, key, '${tag}_1badge', conditions: {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'state': '유형 배지 · 고정 상단'});
        var iconGap = 0.0;
        for (final x in _fixed) {
          await measure(x);
        }
        // ④ 자물쇠 중심 ↔ 제목 첫 줄 중심
        for (final ttl in const ['제1조 (근로계약 당사자)', '제2조 (근무 조건)', '제3조 (임금)']) {
          final f = find.text(ttl);
          await t.scrollUntilVisible(f, 120, scrollable: scroll, maxScrolls: 80);
          final rt = find.descendant(of: f.first, matching: find.byType(RichText), matchRoot: true).first;
          final rp = t.renderObject<RenderParagraph>(rt);
          final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: 1));
          final top = t.getRect(rt).top;
          final firstCenter = top + (boxes.isEmpty ? 0 : (boxes.first.top + boxes.first.bottom) / 2);
          final row = find.ancestor(of: f.first, matching: find.byType(Row)).first;
          final lock = find.descendant(of: row, matching: find.byIcon(Icons.lock_outline));
          final lc = t.getCenter(lock.first).dy;
          final d = (lc - firstCenter).abs();
          if (d > iconGap) iconGap = d;
        }
        await vqCapture(t, key, '${tag}_2fixed', conditions: {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'state': '고정 상단 행'});
        await measure('편집 가능 조항');
        await measure('드래그로 순서 변경');
        await vqCapture(t, key, '${tag}_3head', conditions: {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'state': '편집 가능 조항 머리'});
        // 끝까지 내려 남은 넘침을 모은다
        await t.drag(scroll, const Offset(0, -6000));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        _out('$tag overflows=${overflows.length} ${overflows.toSet()} lockGap=${iconGap.toStringAsFixed(2)} beforeObs=$_beforeObs');
        final ok = overflows.isEmpty && outside == 0 && avoid == 0 && iconGap <= 1.0;
        _out('KNOWN ${ok ? 'ok' : 'NG'} $tag 넘침 ${overflows.length} · 폭 밖 $outside · 끊김 $avoid · 자물쇠 ${iconGap.toStringAsFixed(2)}');
        expect(t.takeException(), isNull);
        if (!_beforeObs) {
          expect(overflows, isEmpty, reason: '$tag 넘침');
          expect(outside, 0, reason: '$tag 폭 밖 글');
          expect(avoid, 0, reason: '$tag 낱말 안 끊김');
          expect(iconGap, lessThanOrEqualTo(1.0), reason: '$tag 자물쇠 ↔ 제목 첫 줄');
        }
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 1));
      });
    }
  }
}
