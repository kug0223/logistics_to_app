// ignore_for_file: depend_on_referenced_packages
// [DU436 · 후속113 N2 · 자체 판정 셀 · 표시만] DU-O090 멤버 초대 창 머리.
//   후보: 넓은 그라데이션 띠 · 흰 제목 → 흰 면 · 작은 brand 타일 · 진한 제목 · 사업장명 textSecondary(전문) · 중립 닫기 · 아래 grey200,
//     좁거나 큰 글자에서 옆 칸 < 120×배율이면 타일 · 닫기 줄 아래로 제목 · 사업장명(DU433 기준). 검색 · 권한 · 초대 처리 · 닫기 동작은 그대로다.
//   before = 현재 A(member_management_screen 45276712) / strict = 후보(faf00b65). 준비 렌더 진단 diag(1회) W/B/M/BL 4/4 통과.
//   진입: MemberManagementScreen(LOCAL reads · S024 415 harness 와 같은 seam) → 단일 사업장 머리 '+ 멤버 초대' 탭.
//   tok 접두 'S990IV' — 공용 lkit tok_prefix 형식(^S\d{3}[A-Z]{1,2}$)에 맞추려고 O090 에 900 을 더했다(S990 화면 없음).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du436-tb/DU_BEFORE_OBSERVE=436 · TA after/du436-ta/없음.
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

final String _zwsp = String.fromCharCode(0x200B);
final String _wj = String.fromCharCode(0x2060);
final String _nbsp = String.fromCharCode(0x00A0);
bool _visible(String ch) => ch.trim().isNotEmpty && ch != _zwsp && ch != _wj && ch != _nbsp;

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

({List<String> lines, bool ok}) _lines(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  final lineOf = List<int>.filled(s.length, -1);
  var missing = 0;
  for (var i = 0; i < s.length; i++) {
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.isEmpty) {
      if (_visible(s[i])) missing++;
      continue;
    }
    var k = tops.indexWhere((x) => (x - boxes.first.top).abs() < 0.5);
    if (k < 0) {
      tops.add(boxes.first.top);
      k = tops.length - 1;
    }
    lineOf[i] = k;
  }
  if (tops.isEmpty) return (lines: const <String>[], ok: false);
  final order = List<int>.generate(tops.length, (i) => i)..sort((a, b) => tops[a].compareTo(tops[b]));
  final rank = List<int>.filled(tops.length, 0);
  for (var r = 0; r < order.length; r++) {
    rank[order[r]] = r;
  }
  final buf = List<StringBuffer>.generate(tops.length, (_) => StringBuffer());
  var ok = true;
  var prev = -1;
  var cur = 0;
  for (var i = 0; i < s.length; i++) {
    if (lineOf[i] >= 0) {
      final ln = rank[lineOf[i]];
      if (prev >= 0 && ln != prev) {
        final b = i > 0 ? s[i - 1] : '';
        if (!(b == ' ' || b == _zwsp || b == '\n' || s[i] == ' ' || s[i] == '\n')) ok = false;
      }
      prev = ln;
      cur = ln;
    }
    buf[cur].write(s[i]);
  }
  return (lines: [for (final b in buf) TextLayout.plain(b.toString()).trim()], ok: ok && missing == 0);
}

({Color? c, bool grad, Border? border}) _fillBehind(Element e) {
  Color? c;
  Border? border;
  var grad = false;
  e.visitAncestorElements((a) {
    final w = a.widget;
    if (w is Container && w.decoration is BoxDecoration) {
      final d = w.decoration! as BoxDecoration;
      if (d.gradient != null) {
        grad = true;
        return false;
      }
      if (d.color != null && d.color!.a > 0.99) {
        c = d.color;
        border = d.border is Border ? d.border! as Border : null;
        return false;
      }
    }
    if (w is Material && w.color != null && w.color!.a > 0.99) {
      c = w.color;
      return false;
    }
    return true;
  });
  return (c: c, grad: grad, border: border);
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '436';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du436-tb' && _env['DU_BEFORE_OBSERVE'] == '436') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du436-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textPrimary': AppColors.textPrimary, 'textSecondary': AppColors.textSecondary, 'brand': AppColors.brand,
  'brandSurface': AppColors.brandSurface, 'grey600': AppColors.grey600, 'grey200': AppColors.grey200,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

String _w(List<String> lines) => lines.map((x) => x.replaceAll(' ', '_')).join('|');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    const codec = StandardMessageCodec();
    for (final m in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$m',
          (_) async => codec.encodeMessage(<Object?>['du436.fake.$m']));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du436.fake.$m'), (_) async => null);
    }
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'SHORT', name: '강남 물류센터', title: '초대 창 머리(짧은 사업장명) — 띠 제거 · 진한 제목 · brand 타일 · 중립 닫기 · 좁으면 쌓기'),
    (key: 'LONG', name: 'QA 송파 물류센터 제2캠퍼스 상하차동', title: '초대 창 머리(긴 사업장명) — 사업장명 전문 · 낱말 경계 · 좁으면 쌓기'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S990IV-${v.id}-${st.key} ${st.title}', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S990IV-${v.id}-${st.key}';
          final mode = _before ? 'before' : 'strict';
          _out('D436 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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

          var reads = 0;
          final r = MemberManagementReads(
            businessesByIds: (ids) async {
              reads++;
              return [if (ids.contains('b1')) _biz('b1', st.name)];
            },
            members: (id) async {
              reads++;
              return [_member('b1', 'm1', '김민준')];
            },
            sentPendingInvitations: (id) async {
              reads++;
              return const [];
            },
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
            _out('D436 $tok shot $sub ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_$sub', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key,
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
          final titleF = inD(find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '멤버 초대', skipOffstage: false));
          final nameF = inD(find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == st.name, skipOffstage: false));
          final tileIconF = inD(find.byIcon(Icons.person_add_outlined, skipOffstage: false));
          final closeF = inD(find.byIcon(Icons.close, skipOffstage: false));
          final ns = '${titleF.evaluate().length}/${nameF.evaluate().length}/${tileIconF.evaluate().length}/${closeF.evaluate().length}';
          must('머리 요소 1/1/1/1', ns == '1/1/1/1', ns);
          await shot('1open', 'dialog-open');

          // ── 머리 측정(값은 즉시) ──
          final trp = t.renderObject(titleF) as RenderParagraph;
          final tj = _lines(trp);
          final tEx = trp.didExceedMaxLines;
          final nrp = t.renderObject(nameF) as RenderParagraph;
          final nj = _lines(nrp);
          final nEx = nrp.didExceedMaxLines;
          final nMax = nrp.constraints.maxWidth;
          final tColor = (t.widget(titleF) as RichText).text.style?.color;
          final nColor = (t.widget(nameF) as RichText).text.style?.color;
          final tFill = _fillBehind(titleF.evaluate().first);
          Color? tileBg;
          tileIconF.evaluate().first.visitAncestorElements((a) {
            final w = a.widget;
            if (w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color != null) {
              tileBg = (w.decoration! as BoxDecoration).color;
              return false;
            }
            return true;
          });
          final tileFg = (t.widget(tileIconF) as Icon).color;
          final closeColor = (t.widget(closeF) as Icon).color;
          final closeFill = _fillBehind(closeF.evaluate().first);
          final stacked = t.getRect(titleF).top >= t.getRect(tileIconF).bottom - 0.5;
          final gradN = inD(find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).gradient != null,
              skipOffstage: false)).evaluate().length;
          final bottom = tFill.border?.bottom.color;
          final titleCr = tFill.grad ? 0.0 : _cr(tColor, tFill.c);
          final nameCr = tFill.grad ? 0.0 : _cr(nColor, tFill.c);
          final closeCr = closeFill.grad ? 0.0 : _cr(closeColor, closeFill.c);
          final nameFull = nj.lines.join(' ') == st.name;
          _out('D436 $tok att head stacked=$stacked lines=${tj.lines.length} ok=${tj.ok} exceeded=$tEx nameLines=${nj.lines.length} nameOk=${nj.ok} '
              'nameEx=$nEx nameFull=$nameFull nameMaxW=${_f(nMax)} gradN=$gradN text=${_w(nj.lines)}');
          _out('D436 $tok att color title=${_tok(tColor)} grad=${tFill.grad} fill=${_tok(tFill.c)} border=${_tok(bottom)} titleCr=${_f(titleCr)} '
              'name=${_tok(nColor)} nameCr=${_f(nameCr)} tile=${_tok(tileBg)} tileIcon=${_tok(tileFg)} tileCr=${_f(_cr(tileFg, tileBg))} '
              'close=${_tok(closeColor)} closeCr=${_f(closeCr)}');

          // ── 닫기 → 창 닫힘 · 다시 읽기 0 ──
          final before = reads;
          final closeInk = find.ancestor(of: closeF, matching: find.byType(InkWell, skipOffstage: false)).first;
          await t.tapAt(t.getRect(closeInk).center);
          await settle(12);
          final closed = find.byType(Dialog).evaluate().isEmpty;
          final rereads = reads - before;
          _out('D436 $tok att close closed=$closed rereads=$rereads');

          must('닫기 → 창 닫힘 · 다시 읽기 0', closed && rereads == 0, '닫힘 $closed 다시 읽기 $rereads');
          if (_before) {
            // 음성 기대 — base 머리는 넓은 그라데이션 띠(코드 확정) · 제목 흰 글자.
            must('before 그라데이션 머리 · 흰 제목 검출', gradN >= 1 && tFill.grad && tColor == const Color(0xFFFFFFFF), '그라데이션 $gradN ${_tok(tColor)}');
          } else {
            must('strict 그라데이션 0', gradN == 0, '그라데이션 $gradN');
            must('strict 배치(W 가로 · B 쌓기)', stacked == (v.id == 'B'), '쌓기 $stacked');
            must('strict 제목 · 사업장명 경계 · 말줄임 0 · 전문', tj.ok && !tEx && nj.ok && !nEx && nameFull, '${_w(tj.lines)} ${_w(nj.lines)} $nEx');
            must('strict 제목 textPrimary · 대비 ≥ 4.5', tColor == AppColors.textPrimary && titleCr >= 4.5, '${_tok(tColor)} ${_f(titleCr)}');
            must('strict 사업장명 textSecondary · 대비 ≥ 4.5', nColor == AppColors.textSecondary && nameCr >= 4.5, '${_tok(nColor)} ${_f(nameCr)}');
            must('strict 머리 흰 면 · 아래 grey200', tFill.c == AppColors.surface && bottom == AppColors.grey200, '${_tok(tFill.c)} ${_tok(bottom)}');
            must('strict 타일 brandSurface/brand · 대비 ≥ 3', tileBg == AppColors.brandSurface && tileFg == AppColors.brand && _cr(tileFg, tileBg) >= 3,
                '${_tok(tileBg)} ${_tok(tileFg)}');
            must('strict 닫기 grey600 · 대비 ≥ 3', closeColor == AppColors.grey600 && closeCr >= 3, '${_tok(closeColor)} ${_f(closeCr)}');
            must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          }
          must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
          final exc = t.takeException();
          _out('D436 $tok done state=${st.key} mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
          must('끝 예외 0', exc == null, '예외 $exc');
          await t.pumpWidget(const SizedBox.shrink());
        } catch (e) {
          _anyFail = true;
          rethrow;
        }
      }, skip: !_optIn);
    }
  }
}
