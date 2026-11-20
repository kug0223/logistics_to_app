// ignore_for_file: depend_on_referenced_packages
// [DU441 · 자체 판정 셀 · 표시만] DU-O090 멤버 초대 창 본문 — 전화번호 칸 단일 틀 · 안내 전문(B 는 검색 버튼 아래 줄) · 빈 안내 · '취소' 대비.
//   before = 현재 A(member_management_screen faf00b65 · DU436 후보) / strict = 후보(96378549). 진입은 DU436 시험(d4a3bc40)과 같다.
//   입력은 enterText 1회(서식 확인 · 가로 밀림)만 — 검색 실행 · 제출 0. tok 접두 'S990PF'(O090 + 900 · S990 화면 없음).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du441-tb/DU_BEFORE_OBSERVE=441 · TA after/du441-ta/없음.
import 'dart:convert';
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

({Color? c, int shadows}) _behind(Element e) {
  Color? c;
  var shadows = 0;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Dialog) return false;
    if (w is Container && w.decoration is BoxDecoration) {
      final d = w.decoration! as BoxDecoration;
      if ((d.boxShadow ?? const []).isNotEmpty) shadows++;
      if (c == null && d.color != null && d.color!.a > 0.99) c = d.color;
    }
    if (c == null && w is Container && w.color != null && w.color!.a > 0.99) c = w.color;
    if (c == null && w is Material && w.color != null && w.color!.a > 0.99) c = w.color;
    return true;
  });
  return (c: c, shadows: shadows);
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '441';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du441-tb' && _env['DU_BEFORE_OBSERVE'] == '441') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du441-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textPrimary': AppColors.textPrimary, 'textSecondary': AppColors.textSecondary, 'textTertiary': AppColors.textTertiary,
  'brand': AppColors.brand, 'grey50': AppColors.grey50, 'grey200': AppColors.grey200, 'grey300': AppColors.grey300, 'grey400': AppColors.grey400,
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
    testWidgets('S990PF-${v.id}-BODY 초대 창 전화번호 칸 — 단일 틀 · 안내 전문 · 좁으면 검색 버튼 아래 줄 · 빈 안내 · 취소 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S990PF-${v.id}-BODY';
        final mode = _before ? 'before' : 'strict';
        _out('D441 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        final overflows = <String>[];
        final fwErrors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            overflows.add(m.split('\n').first);
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
          _out('D441 $tok shot $sub ovf=${overflows.length}');
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

        // ── 열린 직후 측정(값은 즉시) ──
        final fieldF = inD(find.byType(TextField));
        final decF = inD(find.byType(InputDecorator));
        final hintF = rt('010-0000-0000');
        final phoneF = inD(find.byIcon(Icons.phone_outlined, skipOffstage: false));
        final searchF = inD(find.byIcon(Icons.search_rounded, skipOffstage: false));
        final labelF = rt('검색');
        final emptyF = rt('전화번호를 입력하고 검색하세요');
        final cancelF = rt('취소');
        final ns = '${fieldF.evaluate().length}/${decF.evaluate().length}/${hintF.evaluate().length}/${searchF.evaluate().length}/'
            '${emptyF.evaluate().length}/${cancelF.evaluate().length}';
        must('본문 요소 1/1/1/1/1/1', ns == '1/1/1/1/1/1', ns);
        final fieldR = t.getRect(fieldF);
        final dec = (t.widget(decF) as InputDecorator).decoration;
        final eb = dec.enabledBorder;
        final outline = eb is OutlineInputBorder && eb.borderSide.style != BorderStyle.none;
        final outlineColor = eb is OutlineInputBorder ? eb.borderSide.color : null;
        final fb = _behind(fieldF.evaluate().first);
        final fieldFill = (dec.filled ?? false) ? dec.fillColor : fb.c;
        final hrp = t.renderObject(hintF) as RenderParagraph;
        final hintNeed = hrp.getMaxIntrinsicWidth(double.infinity);
        final hintRoom = hrp.constraints.maxWidth;
        final hintCut = hintNeed > hintRoom + 0.5 || hrp.didExceedMaxLines;
        final hintColor = (t.widget(hintF) as RichText).text.style?.color;
        final hintCr = _cr(hintColor, fieldFill);
        final phoneN = phoneF.evaluate().length;
        final phoneColor = phoneN == 1 ? (t.widget(phoneF) as Icon).color : null;
        final btnF = find.ancestor(of: searchF, matching: find.byType(InkWell, skipOffstage: false)).first;
        final btnR = t.getRect(btnF);
        final btnFill = (t.widget(find.ancestor(of: searchF, matching: find.byType(Material, skipOffstage: false)).first) as Material).color;
        final btnBelow = btnR.top >= fieldR.bottom - 0.5;
        final btnFull = (btnR.width - fieldR.width).abs() <= 1.0;
        final labelN = labelF.evaluate().length;
        final emptyColor = (t.widget(emptyF) as RichText).text.style?.color;
        final emptyBg = _behind(emptyF.evaluate().first).c;
        final emptyCr = _cr(emptyColor, emptyBg);
        final cancelColor = (t.widget(cancelF) as RichText).text.style?.color;
        final cancelBg = _behind(cancelF.evaluate().first).c;
        final cancelCr = _cr(cancelColor, cancelBg);
        _out('D441 $tok att frame shadows=${fb.shadows} outline=$outline outlineColor=${_tok(outlineColor)} fill=${_tok(fieldFill)} '
            'fieldW=${_f(fieldR.width)} fieldH=${_f(fieldR.height)}');
        _out('D441 $tok att hint cut=$hintCut need=${_f(hintNeed)} room=${_f(hintRoom)} color=${_tok(hintColor)} cr=${_f(hintCr)}');
        _out('D441 $tok att button below=$btnBelow full=$btnFull label=$labelN fill=${_tok(btnFill)} btnW=${_f(btnR.width)} btnH=${_f(btnR.height)} '
            'phone=$phoneN phoneColor=${_tok(phoneColor)}');
        _out('D441 $tok att quiet empty=${_tok(emptyColor)} emptyBg=${_tok(emptyBg)} emptyCr=${_f(emptyCr)} cancel=${_tok(cancelColor)} '
            'cancelBg=${_tok(cancelBg)} cancelCr=${_f(cancelCr)}');

        // ── 입력 — 서식 적용 · 가로 밀림(검색 실행 0 · 제출 0) ──
        await t.enterText(fieldF, '01012345678');
        await settle(6);
        final edF = inD(find.byType(EditableText));
        final typed = (t.widget(edF) as EditableText).controller.text;
        final scroll = t.state<EditableTextState>(edF).renderEditable.offset.pixels;
        final hintAfter = rt('010-0000-0000').evaluate().length;
        _out('D441 $tok att typed text=$typed scroll=${_f(scroll)} hintN=$hintAfter');
        await shot('2typed', 'typed');

        must('입력 서식 010-1234-5678', typed == '010-1234-5678', typed);
        must('입력 테두리(theme outline)', outline, 'enabledBorder ${eb.runtimeType}');
        if (_before) {
          // 음성 기대 — base 는 그림자 카드 안에 테마 테두리가 한 겹 더(코드 확정) · 안내 grey400 · 취소 grey400.
          must('before 이중 틀 검출', fb.shadows >= 1 && outline, '그림자 ${fb.shadows} 테두리 $outline');
          must('before 옅은 글자 검출', hintColor == AppColors.grey400 && cancelColor == AppColors.grey400 && emptyColor == AppColors.grey400,
              '${_tok(hintColor)} ${_tok(cancelColor)} ${_tok(emptyColor)}');
          if (v.id == 'B') {
            must('before B 안내 잘림 검출', hintCut, '필요 ${_f(hintNeed)} 자리 ${_f(hintRoom)}');
          }
        } else {
          must('strict 단일 틀(그림자 0 · 흰 면)', fb.shadows == 0 && fieldFill == AppColors.surface, '그림자 ${fb.shadows} ${_tok(fieldFill)}');
          must('strict 안내 전문 · textTertiary · 대비 ≥ 4.5', !hintCut && hintColor == AppColors.textTertiary && hintCr >= 4.5,
              '잘림 $hintCut ${_tok(hintColor)} ${_f(hintCr)}');
          if (v.id == 'B') {
            must('strict B 검색 버튼 아래 줄 · 전체 폭 · 글자 · 전화 아이콘 0', btnBelow && btnFull && labelN == 1 && phoneN == 0,
                '아래 $btnBelow 전체 $btnFull 글자 $labelN 아이콘 $phoneN');
          } else {
            must('strict W 칸 안 버튼 · 전화 아이콘 grey600', !btnBelow && labelN == 0 && phoneN == 1 && phoneColor == AppColors.grey600,
                '아래 $btnBelow 글자 $labelN 아이콘 $phoneN ${_tok(phoneColor)}');
          }
          must('strict 검색 버튼 brand', btnFill == AppColors.brand, _tok(btnFill));
          must('strict 빈 안내 textTertiary · 대비 ≥ 4.5', emptyColor == AppColors.textTertiary && emptyCr >= 4.5, '${_tok(emptyColor)} ${_f(emptyCr)}');
          must('strict 취소 textSecondary · 대비 ≥ 4.5', cancelColor == AppColors.textSecondary && cancelCr >= 4.5, '${_tok(cancelColor)} ${_f(cancelCr)}');
          must('strict 입력 가로 밀림 0', scroll <= 0.5, _f(scroll));
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D441 $tok done state=BODY mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
