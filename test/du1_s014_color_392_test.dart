// [DU418 추종 · 판정55 §4-1] 빠른 정보 긍정 라벨('주차 가능' · '식사 제공') 기대색 successDark → textTertiary(단순 사실 중립 메타색). 그 밖 변경 0.
// [DU392] S014 사업장 카드 색 · 대비/표면(소급 23 §8 채택 설계) — 하네스는 du1_s014_card_layout_387 바탕(_Provider · 4곳 fixture).
//   W 392x844@1.0 · B 320x640@2.0. 카드마다 카드 위로 실제 스크롤해 맞춘 뒤 단언한다.
//   제품 기대(기본 단언, DU_BEFORE_OBSERVE=392 는 기록만):
//     ① 카드 장식 = ConceptSurface.raised()(흰 · 반경 16 · conceptCardBorder 1 · 낮은 그림자 1) — 승인 대기 빨강 외곽선 0
//     ② 상태 배지 = 반경 8 · 13/700 · 승인 brandSurface/brand · 승인 대기 warningBg/warningDark · 운영 종료 grey100/textSecondary
//     ③ 빠른 정보 'X' = textTertiary, 'O' = successDark(그대로)
//     ④ 배지 글자 · 'X' 글자의 실제 바탕 대비 ≥ 4.5
//   불변(항상 단언): 4곳 도달 · 넘침 0 · 예외 0. 이름 전문 · 배지 · 메뉴 48/hit · 시트는 du1_s014_card_layout_387 이 맡는다.
// ignore_for_file: depend_on_referenced_packages, unused_element
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

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_list_reads.dart';
import 'package:ALfit/screens/business_admin/business_list_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/concept_tokens.dart';
import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p', storageBucket: 'p.appspot.com');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _Provider extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김사장',
        email: 'u1@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: const ['b1', 'b2', 'b3', 'b4'],
      );
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => true;
  @override
  String? get effectiveBusinessId => null;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
}

BusinessModel _biz(String id, String name,
        {bool approved = true,
        String address = '서울특별시 강남구 테헤란로 152',
        double? rating,
        bool parking = false,
        List<String>? meals,
        bool closed = false}) =>
    BusinessModel(
      id: id,
      businessNumber: '000-00-00000',
      name: name,
      category: '물류',
      subCategory: '창고',
      address: address,
      ownerId: 'u1',
      isApproved: approved,
      createdAt: DateTime(2026, 10, 1),
      rating: rating,
      parkingAvailable: parking,
      mealsProvided: meals,
      deactivatedAt: closed ? DateTime(2026, 11, 1) : null,
      archivedAt: closed ? DateTime(2026, 11, 1) : null,
    );

final _four = [
  _biz('b1', '강남 물류센터', rating: 4.6, parking: true, meals: const ['중식']),
  _biz('b2', '송파 신선 분류센터', approved: false),
  _biz('b3', '성수 소형 창고', closed: true),
  _biz('b4', '[QA] 아주 긴 이름의 강남 물류센터 평택 제2공장 냉장 분류동',
      address: '경기도 평택시 포승읍 평택항로 268번길 45-12 물류단지 B동 3층', rating: 3.9, parking: true),
];

// 상태별 배지 기대(독립): (면, 글자)
(Color, Color) _badgeExpect(BusinessModel b) => b.isDeactivated
    ? (AppColors.grey100, AppColors.textSecondary)
    : b.isApproved
        ? (AppColors.brandSurface, AppColors.brand)
        : (AppColors.warningBg, AppColors.warningDark);

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '392';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

// 글자의 실제 바탕 — 가장 가까운 불투명(흰 위 합성) 면
Color _bgOf(Element e) {
  Color? found;
  e.visitAncestorElements((a) {
    final w = a.widget;
    Color? c;
    if (w is Container && w.decoration is BoxDecoration) {
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
    found = Color.alphaBlend(c, Colors.white);
    return false;
  });
  return found ?? Colors.white;
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    const codec = StandardMessageCodec();
    for (final m in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$m',
          (_) async => codec.encodeMessage(<Object?>['du392.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du392.fake.$m'), (_) async => null);
    }
  });

  for (final c in const [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('S014C-${c.id} 사업장 카드 색 · 대비/표면 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
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
            ChangeNotifierProvider<UserProvider>(create: (_) => _Provider()),
            ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.businessAdminTheme,
            builder: (ctx, child) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: BusinessListScreen(reads: BusinessListReads(businessById: (_) async => null, businessesByIds: (_) async => _four)),
          ),
        ),
      ));
      Future<void> settle([int n = 10]) async {
        for (var i = 0; i < n; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }

      await settle(16);
      final tag = 'S014C-${c.id}';
      final cond = {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s};
      await vqCapture(t, key, '${tag}_1top', conditions: {...cond, 'state': '관리자 4곳 첫 화면'});
      final scroll = find.byType(Scrollable).first;
      final checks = <String, bool>{};
      final raised = ConceptSurface.raised();
      for (final b in _four) {
        final name = findVisibleText(b.name);
        await t.scrollUntilVisible(name, 120, scrollable: scroll, maxScrolls: 40);
        await settle(4);
        expect(name, findsOneWidget, reason: '${b.id} 도달(불변)');
        final ink = find.ancestor(of: name, matching: find.byType(InkWell)).first;
        await t.ensureVisible(ink);
        await settle(6);
        // ① 카드 장식 — InkWell 을 감싼 가장 가까운 장식 Container
        final cardBox = find.ancestor(of: ink, matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration)).first;
        final deco = t.widget<Container>(cardBox).decoration! as BoxDecoration;
        checks['${b.id} 카드 = raised'] = deco == raised;
        // ② 배지
        final badgeText = find.descendant(of: ink, matching: findVisibleText(b.operationStatusLabel));
        final badgeBox = find.ancestor(of: badgeText, matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration)).first;
        final bdeco = t.widget<Container>(badgeBox).decoration! as BoxDecoration;
        final rp = t.renderObject<RenderParagraph>(find.descendant(of: badgeText, matching: find.byType(RichText), matchRoot: true).first);
        final st = rp.text.style;
        final (wantBg, wantFg) = _badgeExpect(b);
        final bfg = st?.color ?? Colors.black;
        final bbg = _bgOf(t.element(find.descendant(of: badgeText, matching: find.byType(RichText), matchRoot: true).first));
        final bc = _contrast(bfg, bbg);
        checks['${b.id} 배지 반경 8 · 면'] = bdeco.borderRadius == BorderRadius.circular(8) && bdeco.color == wantBg;
        checks['${b.id} 배지 13/700 · 글자색'] = st?.fontSize == 13 && st?.fontWeight == FontWeight.w700 && st?.color == wantFg;
        checks['${b.id} 배지 대비 ≥ 4.5'] = bc >= 4.5;
        // ③ ④ 빠른 정보 — [DU395] 문구 계약 변경(소급 24 §3·§4): fixture 판정식으로 정확 기대 라벨 · 기대 색을 정한다.
        //   각 카드 주차 · 식사 2개가 반드시 있어야 하고, 색 · 대비 2건을 실제로 검사했다는 단언을 둔다(빈 map 통과 0).
        final quickTexts = <String, (Color?, double, Color)>{};
        final quickWant = <(String, Color)>[
          b.parkingAvailable ? ('주차 가능', AppColors.textTertiary) : ('주차 불가', AppColors.textTertiary),
          (b.mealsProvided != null && b.mealsProvided!.isNotEmpty)
              ? ('식사 제공', AppColors.textTertiary)
              : ('식사 미제공', AppColors.textTertiary),
        ];
        for (final (lbl, want) in quickWant) {
          final f = find.descendant(of: ink, matching: findVisibleText(lbl));
          checks['${b.id} $lbl 존재 1'] = f.evaluate().length == 1;
          if (f.evaluate().length != 1) continue;
          final qrp = t.renderObject<RenderParagraph>(find.descendant(of: f, matching: find.byType(RichText), matchRoot: true).first);
          final col = qrp.text.style?.color;
          quickTexts[lbl] = (col, _contrast(col ?? Colors.black, _bgOf(t.element(f))), want);
        }
        for (final e in quickTexts.entries) {
          checks['${b.id} ${e.key} 색'] = e.value.$1 == e.value.$3;
          checks['${b.id} ${e.key} 대비 ≥ 4.5'] = e.value.$2 >= 4.5;
        }
        checks['${b.id} 빠른 정보 주차 · 식사 2건 색 · 대비 실제 검사'] = quickTexts.length == 2;
        _out('$tag ${b.id} card=${deco == raised ? 'raised' : 'other(border=${deco.border} shadows=${deco.boxShadow?.length})'} '
            'badge=bg 0x${(bdeco.color ?? Colors.transparent).toARGB32().toRadixString(16)} r=${bdeco.borderRadius} '
            'fg 0x${bfg.toARGB32().toRadixString(16)} ${st?.fontSize}/${st?.fontWeight} contrast=${bc.toStringAsFixed(2)} '
            'quick=${quickTexts.map((k, v) => MapEntry(k, '0x${(v.$1 ?? Colors.black).toARGB32().toRadixString(16)}/${v.$2.toStringAsFixed(2)}'))}');
        if (b.id == 'b2') {
          await vqCapture(t, key, '${tag}_2pending', conditions: {...cond, 'state': '승인 대기 · 운영 종료 카드'});
        }
      }
      await t.scrollUntilVisible(findVisibleText('새 사업장 추가'), 200, scrollable: scroll, maxScrolls: 40);
      await settle(6);
      await vqCapture(t, key, '${tag}_3end', conditions: {...cond, 'state': '끝'});
      _out('$tag checks=$checks overflows=${overflows.length} beforeObs=$_beforeObs');
      final ok = checks.values.every((v) => v);
      _out('KNOWN ${ok ? 'ok' : 'NG'} $tag ${checks.entries.where((e) => !e.value).map((e) => e.key).toList()}');
      final exc = t.takeException();
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
