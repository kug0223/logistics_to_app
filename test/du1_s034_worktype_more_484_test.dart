// ignore_for_file: depend_on_referenced_packages
// [DU484 · 자체 판정 셀 · 표시만] DU-S034 작업 유형 관리 — 행의 더보기(⋮) 아이콘 대비(비텍스트 3:1).
//   before = 현재 A(work_type_management_screen base) / strict = 후보(grey400 → grey600). 크기 · 위치 · 동작은 그대로다.
//   harness 는 DU482 시험(453815a3 · du1_c1_edit_discard_test 렌더 방식)의 Firestore 채널 대역(workTypes queryGet 고정 1개 · 그 밖 차단)을 쓰고
//   화면만 WorkTypeManagementScreen(businessId: biz-local-c1)으로 바꿨다. 상태 1(LIST · 작업 유형 1개 '포장').
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du484-tb/DU_BEFORE_OBSERVE=484 · TA after/du484-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/work_type_management_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

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

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'owner-local-c1', username: 'owner', name: 'QA 사장', email: 'o@test.local',
      role: UserRole.BUSINESS_ADMIN, businessId: 'biz-local-c1', createdAt: DateTime(2026, 1, 1));
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
}

/// du1_c1_edit_discard_test 와 같은 계약 마스터 공고.

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
  'white': Color(0xFFFFFFFF), 'textSecondary': AppColors.textSecondary, 'textTertiary': AppColors.textTertiary,
  'grey400': AppColors.grey400, 'grey500': AppColors.grey500, 'grey600': AppColors.grey600, 'grey50': AppColors.grey50, 'grey100': AppColors.grey100,
  'background': AppColors.background, 'surface': AppColors.surface,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

/// 놓인 면 — 조상의 칠한 색(Container color · BoxDecoration color · ColoredBox · Material(투명 아님))을 불투명 층까지 모아 합성한다(DU476 과 같다).
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '484';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du484-tb' && _env['DU_BEFORE_OBSERVE'] == '484') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du484-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  void stubFirestore() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = FirebaseFirestoreHostApi.codec;
    // workTypes query — 활성 업무 1개 고정(du1_c1_edit_discard_test 와 같다).
    m.setMockMessageHandler('$base.queryGet', (msg) async {
      final raw = String.fromCharCodes(msg!.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes));
      if (!raw.contains('businesses/biz-local-c1/workTypes')) {
        return codec.encodeMessage(<Object?>['du484-blocked', 'query 차단', null]);
      }
      return codec.encodeMessage(<Object?>[
        PigeonQuerySnapshot(
          documents: [
            PigeonDocumentSnapshot(
              path: 'businesses/biz-local-c1/workTypes/wt-c1',
              data: <String?, Object?>{
                'businessId': 'biz-local-c1', 'name': '포장', 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
                'displayOrder': 0, 'isActive': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
              },
              metadata: PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
            ),
          ],
          documentChanges: const [],
          metadata: PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false),
        ),
      ]);
    });
    for (final op in const ['documentReferenceGet', 'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete',
      'writeBatchCommit', 'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$base.$op', (msg) async => codec.encodeMessage(<Object?>['du484-blocked', '$op 차단', null]));
    }
    m.setMockMessageHandler('dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
        (msg) async => const StandardMessageCodec().encodeMessage(<Object?>['du484-blocked', 'functions 차단', null]));
  }

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S034MV-${v.id}-LIST 작업 유형 관리 — 더보기 아이콘 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S034MV-${v.id}-LIST';
        final mode = _before ? 'before' : 'strict';
        _out('D484 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        stubFirestore();
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
            await t.pump(const Duration(milliseconds: 50));
          }
        }

        final key = GlobalKey();
        await t.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => _Owner()),
            ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              navigatorKey: navigatorKey,
              theme: RoleTheme.businessAdminTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: const WorkTypeManagementScreen(businessId: 'biz-local-c1', businessName: 'QA 물류센터'),
            ),
          ),
        ));
        await settle(16);
        must('작업 유형 관리 화면 1', find.byType(WorkTypeManagementScreen).evaluate().length == 1,
            '개수 ${find.byType(WorkTypeManagementScreen).evaluate().length}');

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        // 작업 유형 행 — 이름 '포장'에서 가장 가까운 Row 조상 안의 더보기 아이콘(위치 기준 · 앱 바 아이콘과 섞이지 않게).
        final nameF = rt((p) => p == '포장');
        must('작업 유형 이름 1', nameF.evaluate().length == 1, '개수 ${nameF.evaluate().length}');
        final rowF = find.ancestor(of: nameF, matching: find.byType(Row, skipOffstage: false)).first;
        final moreF = find.descendant(of: rowF, matching: find.byIcon(Icons.more_vert, skipOffstage: false), skipOffstage: false);
        must('더보기 아이콘 1', moreF.evaluate().length == 1, '개수 ${moreF.evaluate().length}');
        await t.ensureVisible(nameF);
        await settle(4);
        _out('D484 $tok shot 1list ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1list', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'LIST',
          'state': 'work-type-list',
        });
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        final col = (t.widget(moreF) as Icon).color;
        final bg = _bgOf(moreF.evaluate().first);
        final cr = _cr(col, bg);
        _out('D484 $tok att more icon=${_tok(col)} bg=${_tok(bg)} cr=${_f(cr)}');
        if (_before) {
          // 음성 기대(코드 확정) — grey400 · 흰 행 위 약 1.9(비텍스트 3:1 미달).
          must('before 더보기 grey400 · 3:1 미달 검출', col == AppColors.grey400 && cr < 3.0, '${_tok(col)} ${_tok(bg)} ${_f(cr)}');
        } else {
          must('strict 더보기 grey600 · 비텍스트 ≥ 3:1', col == AppColors.grey600 && cr >= 3.0, '${_tok(col)} ${_tok(bg)} ${_f(cr)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D484 $tok done state=LIST mode=$mode captures=1 overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
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
