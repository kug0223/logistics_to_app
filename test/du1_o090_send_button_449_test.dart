// ignore_for_file: depend_on_referenced_packages
// [DU449 · 자체 판정 셀 · 표시만] DU-O090 멤버 초대 창 — '초대 발송' 버튼(비활성): 흰 라벨 · 반경 14 → 공용 주 버튼(52 · 12 · grey500 라벨).
//   before = 현재 A(member_management_screen 96378549 · DU441 후보) / strict = 후보(72ba7ff8). 진입은 DU441 시험(cd1fef2d)과 같다.
//   누르기 0 · 입력 0 · 쓰기 0. tok 접두 'S990SB'(O090 + 900 · S990 화면 없음).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du449-tb/DU_BEFORE_OBSERVE=449 · TA after/du449-ta/없음.
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
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
import 'package:ALfit/screens/business_admin/member_management_reads.dart';
import 'package:ALfit/screens/business_admin/member_management_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/text_layout.dart';

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
        uid: 'u1', username: 'u1', name: '김사장', email: 'u1@alfit.local', role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: ids, subAdminBusinessIds: const [],
      );
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => true;
  @override
  String? get effectiveBusinessId => null;
}

BusinessModel _biz(String id, String name) => BusinessModel(
      id: id, businessNumber: '000-00-00000', name: name, category: '물류', subCategory: '창고',
      address: '서울특별시 강남구 테헤란로 152', ownerId: 'u1', isApproved: true, createdAt: DateTime(2026, 10, 1),
    );

BusinessMemberModel _member(String biz, String uid, String name) =>
    BusinessMemberModel(uid: uid, businessId: biz, name: name, permissions: const MemberPermissions(), addedAt: DateTime(2026, 11, 1), addedBy: 'u1');


void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f(double v) => v.toStringAsFixed(2);
String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '449';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du449-tb' && _env['DU_BEFORE_OBSERVE'] == '449') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du449-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textPrimary': AppColors.textPrimary, 'textSecondary': AppColors.textSecondary, 'textTertiary': AppColors.textTertiary,
  'brand': AppColors.brand, 'grey50': AppColors.grey50, 'grey200': AppColors.grey200, 'grey300': AppColors.grey300, 'grey400': AppColors.grey400, 'grey500': AppColors.grey500,
  'grey600': AppColors.grey600,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
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
          (_) async => codec.encodeMessage(<Object?>['du441.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du441.fake.$m'), (_) async => null);
    }
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S990SB-${v.id}-BODY 초대 창 초대 발송 버튼 — 공용 주 버튼 52 · 12 · 비활성 grey500 라벨', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S990SB-${v.id}-BODY';
        final mode = _before ? 'before' : 'strict';
        _out('D449 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        final overflows = <String>[];
        final fwErrors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            // 넘침 출처(파일:줄)를 함께 남긴다 — 진단 한 번으로 모든 넘침 위치를 안다(DU446 · 447 교훈).
            final full = d.toString();
            final k = full.indexOf('The relevant error-causing widget was');
            final loc = k < 0 ? '' : full.substring(k).split('\n').skip(1).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
            overflows.add('${m.split('\n').first} @ $loc');
          } else {
            fwErrors.add(m.split('\n').first);
            prev?.call(d);
          }
        };
        addTearDown(() => FlutterError.onError = prev);
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        Future<void> settle([int n = 10]) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
        }

        final r = MemberManagementReads(
          businessesByIds: (ids) async => [if (ids.contains('b1')) _biz('b1', '강남 물류센터')],
          members: (id) async => [_member('b1', 'm1', '김민준')],
          sentPendingInvitations: (id) async => const [],
        );
        final key = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(create: (_) => _Provider(ids: const ['b1'])),
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
        unawaited(navigatorKey.currentState!.push(MaterialPageRoute(builder: (_) => MemberManagementScreen(reads: r))));
        await settle(12);
        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D449 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'BODY',
            'state': state,
          });
          shots++;
        }

        final scaf = find.byType(MemberManagementScreen);
        final heads = [
          for (final e in find.descendant(of: scaf, matching: find.byWidgetPredicate((w) => w is TextButton), skipOffstage: false).evaluate())
            if (find.descendant(of: find.byElementPredicate((x) => identical(x, e), skipOffstage: false),
                    matching: find.byWidgetPredicate((w) => w is Text && visibleText(w.data ?? '') == '멤버 초대', skipOffstage: false), skipOffstage: false)
                .evaluate()
                .isNotEmpty)
              e
        ];
        must('머리 초대 행동 1', heads.length == 1, '행동 ${heads.length}');
        final target = find.byElementPredicate((x) => identical(x, heads.single), skipOffstage: false);
        await t.ensureVisible(target);
        await settle(4);
        await t.tap(target);
        await settle(12);
        final dlg = find.byType(Dialog);
        must('창 1', dlg.evaluate().length == 1, '창 ${dlg.evaluate().length}');
        Finder inD(Finder f) => find.descendant(of: dlg, matching: f, skipOffstage: false);
        Finder rt(String s) => inD(find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == s, skipOffstage: false));
        await shot('1open', 'dialog-open');

        // ── '초대 발송' 버튼(비활성 · 값은 즉시) — 라벨의 첫 불투명 면(Material 또는 Container BoxDecoration)이 버튼 면 ──
        final labelF = rt('초대 발송');
        must('초대 발송 1', labelF.evaluate().length == 1, '개수 ${labelF.evaluate().length}');
        final labelColor = (t.widget(labelF) as RichText).text.style?.color;
        Element? face;
        Color? faceColor;
        double radius = -1;
        labelF.evaluate().first.visitAncestorElements((a) {
          final w = a.widget;
          if (w is Material && w.color != null && w.color!.a > 0.99) {
            face = a;
            faceColor = w.color;
            final sh = w.shape;
            if (sh is RoundedRectangleBorder && sh.borderRadius is BorderRadius) radius = (sh.borderRadius as BorderRadius).topLeft.x;
            return false;
          }
          if (w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color != null) {
            final d = w.decoration! as BoxDecoration;
            face = a;
            faceColor = d.color;
            if (d.borderRadius is BorderRadius) radius = (d.borderRadius! as BorderRadius).topLeft.x;
            return false;
          }
          return true;
        });
        final f = face;
        final bR = f == null ? Rect.zero : t.getRect(find.byElementPredicate((x) => identical(x, f), skipOffstage: false));
        final sendIcon = inD(find.byIcon(Icons.send_rounded, skipOffstage: false));
        final iconColor = sendIcon.evaluate().length == 1 ? (t.widget(sendIcon) as Icon).color : null;
        final cr = _cr(labelColor, faceColor);
        _out('D449 $tok att send label=${_tok(labelColor)} face=${_tok(faceColor)} cr=${_f(cr)} h=${_f(bR.height)} w=${_f(bR.width)} r=${_f(radius)} '
            'icon=${_tok(iconColor)}');

        must('버튼 면 찾음', f != null, '면 없음');
        if (_before) {
          // 음성 기대(코드 확정) — 비활성 라벨 흰색 · 면 grey200 · 반경 14.
          must('before 흰 라벨 · 반경 14 검출', labelColor == const Color(0xFFFFFFFF) && faceColor == AppColors.grey200 && radius == 14,
              '${_tok(labelColor)} ${_tok(faceColor)} ${_f(radius)}');
        } else {
          must('strict 비활성 라벨 grey500 · 면 grey200 · 아이콘 grey500', labelColor == AppColors.grey500 && faceColor == AppColors.grey200 && iconColor == AppColors.grey500,
              '${_tok(labelColor)} ${_tok(faceColor)} ${_tok(iconColor)}');
          must('strict 높이 ≥ 52 · 반경 12 · 전체 폭', bR.height >= 51.99 && radius == 12, '${_f(bR.height)} ${_f(radius)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D449 $tok done state=BODY mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
