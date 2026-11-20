// ignore_for_file: depend_on_referenced_packages
// [DU485 · 자체 판정 셀 · 표시만] DU-S038 내 서류 관리(사업장 관리자) — 섹션 머리 2곳 · 사업자등록증 빈 칸 글자.
//   섹션 머리('사업자 정보' · '사업자등록증'): grey500 작은 글자 + 아이콘 → 설정 화면(DU241)과 같은 16 bold textPrimary · 아이콘 없음.
//   빈 칸: '미등록' grey500 → textSecondary(USER 경로 '미등록'과 같다 · DU1 구현89) · 안내 grey400 → textTertiary.
//   before = 현재 A(document_management_screen base) / strict = 후보. harness 는 du1_s038_document_unregistered_visual_test 렌더 방식
//   (LOCAL host route push · 세무상태 Functions 대역 성공 응답 · Firestore 차단)을 사업장 관리자 대역으로 바꿨다. 상태 1(ADMIN · 등록증 없음).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du485-tb/DU_BEFORE_OBSERVE=485 · TA after/du485-ta/없음.
import 'dart:convert';
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

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/document_management_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p', storageBucket: 'p.appspot.com');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// 사업장 관리자 대역 — 사업자 정보 저장됨(번호 10자리 · 상호) · 사업자등록증 없음.
class _Admin extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'a1', username: 'a1', name: '김사장', email: 'a1@alfit.local', role: UserRole.BUSINESS_ADMIN,
        accountStatus: 'active', businessNumber: '1234567890', businessName: '중앙물류', ceoName: '김사장');
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
}

const _fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
const _sub = '위 정보와 일치하는 사업자등록증을 업로드해주세요';

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

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textPrimary': AppColors.textPrimary, 'textSecondary': AppColors.textSecondary,
  'textTertiary': AppColors.textTertiary, 'grey400': AppColors.grey400, 'grey500': AppColors.grey500, 'grey600': AppColors.grey600,
  'grey50': AppColors.grey50, 'grey100': AppColors.grey100, 'background': AppColors.background, 'surface': AppColors.surface,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

/// 놓인 면 — 조상의 칠한 색을 불투명 층까지 모아 합성한다(DU476 과 같다).
Color? _bgOf(Element e) {
  final layers = <Color>[];
  e.visitAncestorElements((x) {
    final w = x.widget;
    Color? c;
    if (w is Container) {
      c = w.color ?? (w.decoration is BoxDecoration ? (w.decoration! as BoxDecoration).color : null);
    } else if (w is ColoredBox) {
      c = w.color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color;
    }
    // preflight v16 — 투명(알파 0) Material 은 칠한 면이 아니다.
    if (c != null && c.a > 0) {
      layers.add(c);
      if (c.a >= 1) return false;
    }
    return true;
  });
  if (layers.isEmpty) return null;
  var out = layers.last;
  for (final c in layers.reversed.skip(1)) {
    out = Color.alphaBlend(c, out);
  }
  return out;
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '485';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du485-tb' && _env['DU_BEFORE_OBSERVE'] == '485') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du485-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  void stubChannels() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // 세무상태 — du1_s038 과 같은 미등록 성공 응답. 다른 Functions 는 not-found.
    m.setMockMessageHandler(_fnChannel, (msg) async {
      const c = StandardMessageCodec();
      final args = (c.decodeMessage(msg) as List).first as Map;
      if (args['functionName'] == 'callableGetTaxIdentityStatus' && args['region'] == 'asia-northeast3') {
        return c.encodeMessage(<Object?>[
          <String, Object?>{
            'registered': false, 'collectionEnabled': true, 'identifierType': null,
            'foreignRecoveryAvailable': false, 'documentMatch': 'UNASSESSED', 'documentMatchCurrent': false,
          }
        ]);
      }
      return c.encodeMessage(<Object?>['not-found', 'blocked', <String, Object?>{'code': 'not-found'}]);
    });
    for (final op in const ['documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate',
      'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$_fsBase.$op', (msg) async => null);
    }
  }

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S038AD-${v.id}-ADMIN 내 서류(관리자) — 섹션 머리 · 등록증 빈 칸 글자 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S038AD-${v.id}-ADMIN';
        final mode = _before ? 'before' : 'strict';
        _out('D485 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        SharedPreferences.setMockInitialValues({});
        stubChannels();
        final overflows = <String>[];
        final fwErrors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            final full = d.toString();
            final k = full.indexOf('The relevant error-causing widget was');
            final loc = k < 0 ? '' : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
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
        Future<void> settle([int n = 8]) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        final key = GlobalKey();
        await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
          create: (_) => _Admin(),
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.getThemeByRole('BUSINESS_ADMIN'),
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
                  onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(builder: (_) => const DocumentManagementScreen())),
                  child: const Text('host'))))),
            ),
          ),
        ));
        await t.tap(find.text('host'));
        await settle(14);
        must('내 서류 화면 1', find.byType(DocumentManagementScreen).evaluate().length == 1,
            '개수 ${find.byType(DocumentManagementScreen).evaluate().length}');

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        final list = find.descendant(of: find.byType(DocumentManagementScreen), matching: find.byType(Scrollable), skipOffstage: false).first;

        // ── 섹션 머리 1 '사업자 정보'(값은 캡처 뒤 즉시) ──
        final h1F = rt((p) => p == '사업자 정보');
        await t.scrollUntilVisible(h1F, 120, scrollable: list, maxScrolls: 40);
        await settle(2);
        must('섹션 머리 사업자 정보 1', h1F.evaluate().length == 1, '개수 ${h1F.evaluate().length}');
        _out('D485 $tok shot 1head ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1head', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'ADMIN',
          'state': 'admin-docs-head',
        });
        final h1Style = (t.widget(h1F) as RichText).text.style;
        final h1C = h1Style?.color;
        final h1Bg = _bgOf(h1F.evaluate().first);
        final h1Cr = _cr(h1C, h1Bg);
        final h1Fs = h1Style?.fontSize ?? 0;
        final h1Bold = h1Style?.fontWeight == FontWeight.bold;
        final h1Icon = find.byIcon(Icons.business, skipOffstage: false).evaluate().length;
        _out('D485 $tok att head text=${_tok(h1C)} bg=${_tok(h1Bg)} cr=${_f(h1Cr)} fs=${h1Fs.toStringAsFixed(1)} bold=$h1Bold icon=$h1Icon');

        // ── 사업자등록증 섹션 — 머리 2 · 빈 칸 '미등록' · 안내(값은 캡처 뒤 즉시) ──
        final missF = rt((p) => p == '미등록');
        await t.scrollUntilVisible(missF, 120, scrollable: list, maxScrolls: 60);
        await settle(2);
        final h2F = rt((p) => p == '사업자등록증');
        final subF = rt((p) => p == _sub);
        must('미등록 1 · 머리 사업자등록증 1 · 안내 1', missF.evaluate().length == 1 && h2F.evaluate().length == 1 && subF.evaluate().length == 1,
            '${missF.evaluate().length}/${h2F.evaluate().length}/${subF.evaluate().length}');
        await t.ensureVisible(h2F);
        await settle(2);
        _out('D485 $tok shot 2lic ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_2lic', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'ADMIN',
          'state': 'admin-docs-license-empty',
        });
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        final h2Style = (t.widget(h2F) as RichText).text.style;
        final h2C = h2Style?.color;
        final h2Cr = _cr(h2C, _bgOf(h2F.evaluate().first));
        final h2Icon = find.byIcon(Icons.description, skipOffstage: false).evaluate().length;
        final missC = (t.widget(missF) as RichText).text.style?.color;
        final missBg = _bgOf(missF.evaluate().first);
        final missCr = _cr(missC, missBg);
        final subC = (t.widget(subF) as RichText).text.style?.color;
        final subBg = _bgOf(subF.evaluate().first);
        final subCr = _cr(subC, subBg);
        _out('D485 $tok att head2 text=${_tok(h2C)} cr=${_f(h2Cr)} icon=$h2Icon');
        _out('D485 $tok att miss text=${_tok(missC)} bg=${_tok(missBg)} cr=${_f(missCr)}');
        _out('D485 $tok att sub text=${_tok(subC)} bg=${_tok(subBg)} cr=${_f(subCr)}');
        if (_before) {
          // 음성 기대(코드 확정) — 머리 grey500 + 아이콘(grey50 위 약 2.6) · '미등록' grey500 · 안내 grey400.
          must('before 머리 grey500 · 아이콘 있음 · 대비 미달 검출',
              h1C == AppColors.grey500 && h2C == AppColors.grey500 && h1Icon == 1 && h2Icon == 1 && h1Cr < 4.5 && h2Cr < 4.5,
              '${_tok(h1C)} ${_tok(h2C)} $h1Icon/$h2Icon ${_f(h1Cr)}/${_f(h2Cr)}');
          must('before 미등록 grey500 · 안내 grey400 · 대비 미달 검출', missC == AppColors.grey500 && subC == AppColors.grey400 && missCr < 4.5 && subCr < 4.5,
              '${_tok(missC)} ${_tok(subC)} ${_f(missCr)}/${_f(subCr)}');
        } else {
          must('strict 머리 textPrimary 16 bold · 아이콘 없음',
              h1C == AppColors.textPrimary && h2C == AppColors.textPrimary && h1Fs == 16 && h1Bold && h1Icon == 0 && h2Icon == 0 && h1Cr >= 4.5 && h2Cr >= 4.5,
              '${_tok(h1C)} ${_tok(h2C)} fs=$h1Fs bold=$h1Bold $h1Icon/$h2Icon');
          must('strict 미등록 textSecondary · 안내 textTertiary · 대비 ≥ 4.5',
              missC == AppColors.textSecondary && subC == AppColors.textTertiary && missCr >= 4.5 && subCr >= 4.5,
              '${_tok(missC)} ${_tok(subC)} ${_f(missCr)}/${_f(subCr)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D485 $tok done state=ADMIN mode=$mode captures=2 overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
        await settle(2);
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
