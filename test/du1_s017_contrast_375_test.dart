// [DU375] S017 계약서 템플릿 편집 대비 · 아이콘 — 하네스는 du1_s017_layout_374 바탕(seam templateService).
//   W 392x844@1.0 · B 320x640@2.0 × N(새 · 단기) · E(기존 · 기간제) · O(새 · 도급 '기타').
//   목록을 끝까지 내리며 화면 안의 모든 글(RichText) · 입력 칸 예시 글(hint)의 대비를 실제 가까운 바탕 위에서 잰다.
//   제품 기대(기본 단언, DU_BEFORE_OBSERVE=375 는 기록만):
//     ① 대비 < 4.5 인 글 · 예시 글 0 ② 두 안내 글 낱말 안 끊김 0 ③ 배지 이모지 글 0 · 배지 아이콘 = Icons.description_outlined
//     ④ 배지 · 재사용 안내 아이콘 중심 ↔ 옆 글 첫 줄 중심 ≤ 1px ⑤ 이름 칸 예시 글 잘림 0(B 말줄임 → 두 줄까지).
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
final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '375';

class _Svc extends ContractTemplateService {}

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

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

const _notes = [
  '저장한 템플릿은 이후 계약서를 만들 때 다시 불러와 사용할 수 있어요.',
  '사업장에 필요한 내용이 있다면 조항을 추가하거나 수정할 수 있어요.',
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
          (_) async => codec.encodeMessage(<Object?>['du375.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du375.fake.$m'), (_) async => null);
    }
  });

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    for (final flow in const ['N', 'E', 'O']) {
      testWidgets('S017C-${c.id} $flow 대비 · 아이콘 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
        await t.runAsync(vqLoadFonts);
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
        Future<void> settle([int n = 6]) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }

        await settle(12);
        final tag = 'S017C-${c.id}_$flow';
        final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};

        // ③ 배지 이모지 · 아이콘
        final emoji = find.byWidgetPredicate((w) => w is Text && const ['📋', '📄', '📃'].contains(w.data)).evaluate().length;
        final docIcon = find.byIcon(Icons.description_outlined).evaluate().length;
        // ⑤ 이름 칸 예시 글 잘림(새 템플릿 — 이름이 비어 있을 때만 예시 글이 보인다)
        var hintCut = false;
        if (flow != 'E') {
          final hintText = find.descendant(
              of: find.byType(TextField).first,
              matching: find.byWidgetPredicate((w) => w is Text && w.data == '예) 냉장분류 계약서, 일반 단기 계약서'));
          if (hintText.evaluate().isNotEmpty) {
            final rp = t.renderObject<RenderParagraph>(
                find.descendant(of: hintText.first, matching: find.byType(RichText), matchRoot: true).first);
            hintCut = rp.didExceedMaxLines;
          }
        }
        // ④ 아이콘 ↔ 옆 글 첫 줄
        double gapOf(IconData icon, Finder text) {
          if (text.evaluate().isEmpty || find.byIcon(icon).evaluate().isEmpty) return -1;
          final rt = find.descendant(of: text.first, matching: find.byType(RichText), matchRoot: true).first;
          final rp = t.renderObject<RenderParagraph>(rt);
          final b = rp.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1));
          final mid = t.getRect(rt).top + (b.isEmpty ? 0 : (b.first.top + b.first.bottom) / 2);
          return (t.getCenter(find.byIcon(icon).first).dy - mid).abs();
        }

        final badgeGap = gapOf(Icons.description_outlined, find.text(ContractTemplateType.label(type)));
        final reuseGap = gapOf(Icons.autorenew, find.text(_notes[0]));
        await vqCapture(t, key, '${tag}_1top', conditions: {...cond, 'state': '첫 화면(배지 · 이름 · 안내)'});

        // ① · ② 끝까지 내리며 모은다
        var low = 0, noteBreaks = 0;
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
            if (_notes.contains(s)) {
              final br = wordBreaks(rp).where((b) => !b.forced).toList();
              noteBreaks += br.length;
              if (br.isNotEmpty) _out('$tg note-break "$s" $br');
            }
            final cst = col == null ? 99.0 : _contrast(_overWhite(col), bg);
            if (cst < 4.5) {
              low++;
              _out('$tg low "${s.length > 40 ? s.substring(0, 40) : s}" contrast=${cst.toStringAsFixed(2)} color=0x${col!.toARGB32().toRadixString(16)} bg=0x${bg.toARGB32().toRadixString(16)}');
            }
          }
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

        final list = find.byType(Scrollable).first;
        dump(tag);
        var steps = 0;
        double last = -1;
        while (steps < 60) {
          final pos = t.state<ScrollableState>(list).position;
          if ((pos.pixels - last).abs() < 0.5 && steps > 0) break;
          last = pos.pixels;
          await t.drag(list, Offset(0, -(c.h * 0.5)));
          await settle(4);
          dump(tag);
          steps++;
        }
        await vqCapture(t, key, '${tag}_2end', conditions: {...cond, 'state': '끝까지 스크롤'});
        // 고정 상단이 보이는 자리
        await t.scrollUntilVisible(find.text('제2조 (근무 조건)'), -200, scrollable: list, maxScrolls: 80);
        await settle(4);
        await vqCapture(t, key, '${tag}_3fixed', conditions: {...cond, 'state': '고정 상단 · 편집 가능 조항 머리'});

        _out('$tag emoji=$emoji docIcon=$docIcon badgeGap=${badgeGap.toStringAsFixed(2)} reuseGap=${reuseGap.toStringAsFixed(2)} hintCut=$hintCut scrolls=$steps beforeObs=$_beforeObs');
        final iconOk = badgeGap >= 0 && badgeGap <= 1.0 && (flow == 'E' || (reuseGap >= 0 && reuseGap <= 1.0));
        final ok = low == 0 && noteBreaks == 0 && emoji == 0 && docIcon == 1 && iconOk && !hintCut;
        _out('KNOWN ${ok ? 'ok' : 'NG'} $tag 대비 미달 $low · 안내 끊김 $noteBreaks · 이모지 $emoji · 문서 아이콘 $docIcon · 아이콘 정렬 $iconOk · 예시 글 잘림 $hintCut');
        expect(t.takeException(), isNull);
        if (!_beforeObs) {
          expect(low, 0, reason: '$tag 대비 미달');
          expect(noteBreaks, 0, reason: '$tag 안내 낱말 안 끊김');
          expect(emoji, 0, reason: '$tag 배지 이모지');
          expect(docIcon, 1, reason: '$tag 배지 문서 아이콘');
          expect(iconOk, isTrue, reason: '$tag 아이콘 ↔ 첫 줄');
          expect(hintCut, isFalse, reason: '$tag 이름 예시 글 잘림');
        }
        await t.pumpWidget(const SizedBox.shrink());
        await t.pump(const Duration(seconds: 1));
      });
    }
  }
}
