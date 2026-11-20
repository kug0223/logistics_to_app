// [F58-1 사전 보완] 캡처 직전 두 라벨 공통 묶음 정렬 · 같은 frame 두 라벨 viewport/화면 안 단언 뒤 shot(추가 pump 0). 원본 02c8310f 보존.
// [S014 빠른 정보 사실색 · DU418 · 판정55 §4-1 · 57 §5-1] '주차 가능/불가' · '식사 제공/미제공' 네 라벨을 기존 중립 메타색(textTertiary)으로 통일.
//   새 파일 · 정확 2 public(W 392x844@1.0 · B 320x640@2.0 × FACTS) · 캡처 3 단계(1pos 긍정 b1 · 2neg 부정 b2 · 3mix 섞임 b4 × W/B = 6쌍 · lkit 캡처 이름 규칙 ^\d[a-z]+$).
//   하네스: du1_s014_band_color_416(DU416) 과 같은 fake core · _Provider · 4곳 fixture · 읽기 seam · 전역 navigatorKey 홈 위 push. 쓰기 0(누르는 것 없음).
//   모드: DU_BEFORE_OBSERVE=418 이면 before(현행 bb7120d8 — 긍정 successDark · 부정 textTertiary 관측), 아니면 strict(네 라벨 textTertiary).
//   카드 b1–b4 마다 두 라벨의 정확 존재 · 실제 RenderParagraph 색 · 실제 바탕(392 와 같은 _bgOf) 대비를 'quick <bN>' 줄로 낸다.
//   출력 줄: lkit 선언형 계약 'D418 <tok> <kind> [<sub>] k=v …' — 값 공백 0.
// ignore_for_file: depend_on_referenced_packages
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

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_list_reads.dart';
import 'package:ALfit/screens/business_admin/business_list_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

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
  _Provider({required this.ids});

  final List<String> ids;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김사장',
        email: 'u1@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: ids,
        subAdminBusinessIds: const [],
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

// 396 · 400 · 410 과 같은 4곳
final _four = [
  _biz('b1', '강남 물류센터', rating: 4.6, parking: true, meals: const ['중식']),
  _biz('b2', '송파 신선 분류센터', approved: false),
  _biz('b3', '성수 소형 창고', closed: true),
  _biz('b4', '[QA] 아주 긴 이름의 강남 물류센터 평택 제2공장 냉장 분류동',
      address: '경기도 평택시 포승읍 평택항로 268번길 45-12 물류단지 B동 3층', rating: 3.9, parking: true),
];

class _Reads {
  var calls = 0;
  // [⑥] 읽기 보류 — 실제 Loading frame 을 만든다(ARCHOK 재조회 구간만)
  Completer<void>? gate;

  BusinessListReads get reads => BusinessListReads(
        businessById: (_) async {
          calls++;
          final g = gate;
          if (g != null) await g.future;
          return _four.first;
        },
        businessesByIds: (_) async {
          calls++;
          final g = gate;
          if (g != null) await g.future;
          return _four;
        },
      );
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '418';
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _vt(Widget w) => w is Text ? visibleText(w.data ?? w.textSpan?.toPlainText() ?? '') : '';
Finder _el(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);

Element? _ancestor(Element e, bool Function(Widget w) p) {
  Element? out;
  e.visitAncestorElements((a) {
    if (p(a.widget)) {
      out = a;
      return false;
    }
    return true;
  });
  return out;
}

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

// 실제 바탕(392 와 같은 규칙): 가장 가까운 불투명 면 색
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

// [F58-1] 두 Element 의 가장 가까운 공통 조상(같은 카드 빠른 정보 묶음)
Element? _common(Element a, Element b) {
  final anc = <Element>{};
  a.visitAncestorElements((x) {
    anc.add(x);
    return true;
  });
  Element? out;
  b.visitAncestorElements((x) {
    if (anc.contains(x)) {
      out = x;
      return false;
    }
    return true;
  });
  return out;
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
          (_) async => codec.encodeMessage(<Object?>['du418.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du418.fake.$m'), (_) async => null);
    }
  });

  const views = [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'FACTS', title: '사업장 카드 빠른 정보 주차 식사 네 라벨 — 단순 사실 중립 메타색'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S014F-${v.id}-${st.key} ${st.title}', (t) async {
        final tok = 'S014F-${v.id}-${st.key}';
        final mode = _before ? 'before' : 'strict';
        _out('D418 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final screen = Offset.zero & Size(v.w, v.h);
        bool inR(Rect o, Rect r) => r.top >= o.top - 0.5 && r.bottom <= o.bottom + 0.5 && r.left >= o.left - 0.5 && r.right <= o.right + 0.5;
        void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        Future<void> settle([int n = 10]) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }

        var captures = 0;
        final key = GlobalKey();
        final cond = {'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key};
        Future<void> shot(String id, String stage) async {
          await vqCapture(t, key, '${tok}_$id', conditions: {...cond, 'state': stage});
          captures++;
        }

        final r = _Reads();
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(create: (_) => _Provider(ids: [for (final b in _four) b.id])),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: MaterialApp(
              navigatorKey: navigatorKey,
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: const Scaffold(body: SizedBox.expand()),
            ),
          ),
        ));
        await settle(4);
        unawaited(navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => BusinessListScreen(reads: r.reads))));
        await settle(16);

        final scr = find.byType(BusinessListScreen);
        List<Element> inside(String s) =>
            find.descendant(of: scr, matching: find.byWidgetPredicate((w) => w is Text && _vt(w) == s, skipOffstage: false), skipOffstage: false).evaluate().toList();
        // 카드가 아직 만들어지지 않았으면 목록을 끌어 도달시킨다(416 · H-3 와 같은 방식)
        Future<void> reach(BusinessModel b) async {
          var n = 0;
          while (inside(b.name).isEmpty && n < 20) {
            final sc = find.descendant(of: find.descendant(of: scr, matching: find.byType(ListView)), matching: find.byType(Scrollable)).first;
            await t.drag(sc, Offset(0, b.id == 'b1' ? 300 : -300));
            await settle(6);
            n++;
          }
          must('${b.id} 카드 도달', inside(b.name).length == 1, '$n');
        }

        String code(Color? c) => c == AppColors.textTertiary ? 'neutral' : (c == AppColors.successDark ? 'success' : 'other');
        // fixture 판정식(제품과 독립): 주차 = parkingAvailable · 식사 = mealsProvided 가 비어 있지 않음
        final plan = [(_four[0], '1pos', '긍정 두 라벨 카드(b1)'), (_four[1], '2neg', '부정 두 라벨 카드(b2)'), (_four[2], '', ''), (_four[3], '3mix', '긍정 · 부정 섞인 카드(b4)')];
        for (final (b, capId, capStage) in plan) {
          await reach(b);
          final card = _ancestor(inside(b.name).single, (w) => w is InkWell);
          must('${b.id} 카드 InkWell 1', card != null);
          final hasMeal = b.mealsProvided != null && b.mealsProvided!.isNotEmpty;
          final labels = [(b.parkingAvailable ? '주차 가능' : '주차 불가', b.parkingAvailable), (hasMeal ? '식사 제공' : '식사 미제공', hasMeal)];
          final got = <(String, double)>[];
          for (final (lbl, _) in labels) {
            final els = find
                .descendant(of: _el(card!), matching: find.byWidgetPredicate((w) => w is Text && _vt(w) == lbl, skipOffstage: false), skipOffstage: false)
                .evaluate()
                .toList();
            must('${b.id} $lbl 정확 1', els.length == 1, '${els.length}');
            await t.ensureVisible(_el(els.single));
            await settle(4);
            final rp = t.renderObject<RenderParagraph>(
                find.descendant(of: _el(els.single), matching: find.byType(RichText, skipOffstage: false), matchRoot: true, skipOffstage: false).first);
            final c = rp.text.style?.color;
            got.add((code(c), c == null ? 0.0 : _contrast(c, _bgOf(els.single))));
          }
          _out('D418 $tok quick ${b.id} park=${labels[0].$2 ? 'pos' : 'neg'} parkC=${got[0].$1} parkCr=${got[0].$2.toStringAsFixed(2)} '
              'meal=${labels[1].$2 ? 'pos' : 'neg'} mealC=${got[1].$1} mealCr=${got[1].$2.toStringAsFixed(2)}');
          final crOk = got.every((g) => g.$2 >= 4.5);
          if (_before) {
            final want = [for (final (_, pos) in labels) pos ? 'success' : 'neutral'];
            must('before ${b.id} 긍정 successDark · 부정 textTertiary · 대비 ≥ 4.5', got[0].$1 == want[0] && got[1].$1 == want[1] && crOk, '$got');
          } else {
            must('strict ${b.id} 네 라벨 모두 textTertiary · 대비 ≥ 4.5', got.every((g) => g.$1 == 'neutral') && crOk, '$got');
          }
          if (capId.isNotEmpty) {
            // [F58-1] 개별 ensureVisible 은 마지막(식사) 라벨 기준 정렬이라 B 에서 앞(주차) 라벨이 빠질 수 있었다 —
            //   같은 카드의 두 라벨 공통 묶음을 보이게 정렬하고, 같은 frame 에서 두 라벨이 목록 viewport · 화면 안인지 단언한 뒤 바로 찍는다.
            List<Element> pairEls() {
              final cardNow = _ancestor(inside(b.name).single, (w) => w is InkWell)!;
              return [
                for (final (lbl, _) in labels)
                  find
                      .descendant(of: _el(cardNow), matching: find.byWidgetPredicate((w) => w is Text && _vt(w) == lbl, skipOffstage: false), skipOffstage: false)
                      .evaluate()
                      .single
              ];
            }

            final p0 = pairEls();
            final u = _common(p0[0], p0[1]);
            must('${b.id} 두 라벨 공통 묶음 1', u != null);
            await t.ensureVisible(_el(u!));
            await settle(4);
            final p1 = pairEls();
            final vp = t.getRect(find.descendant(of: find.descendant(of: scr, matching: find.byType(ListView)), matching: find.byType(Scrollable)).first);
            final rs = [for (final e in p1) t.getRect(_el(e))];
            must('${b.id} 캡처 직전 두 라벨 목록 viewport · 화면 안(같은 frame)', rs.every((r) => inR(vp, r) && inR(screen, r)), '$rs vp=$vp');
            await shot(capId, capStage);
          }
        }

        final exc = t.takeException();
        _out('D418 $tok done state=${st.key} mode=$mode captures=$captures overflows=${overflows.length} exc=${exc != null}');
        await t.pumpWidget(const SizedBox.shrink());
        await settle(4);
        expect(exc, isNull);
        expect(overflows, isEmpty, reason: '$tok 넘침');
      });
    }
  }
}
