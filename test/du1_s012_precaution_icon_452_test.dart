// ignore_for_file: depend_on_referenced_packages
// [DU452 · 자체 판정 셀 · 표시만] DU-S012 사업장 상세 — '준비사항' 카드 경고 아이콘을 본문 첫 줄 가운데에(공용 FirstLineIcon · 크기 그대로).
//   before = 현재 A(business_detail_screen) / strict = 후보. host · fixture 는 du1_s012_business_detail_b_visual_test(DU1 후속91 · 92)와 같다
//   (LOCAL host route → BusinessDetailScreen(business: fixture) · Firestore/Functions 채널 막고 계수). 누르기는 host 버튼 1회뿐.
//   값은 닿은 즉시 지역 값으로 남긴다. 넘침은 출처(error-causing widget 다음 두 줄)와 함께 남긴다.
//   기본 skip — TB before/du452-tb/DU_BEFORE_OBSERVE=452 · TA after/du452-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_detail_screen.dart';
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

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'owner1', username: 'owner1', name: 'QA 사장', email: 'owner1@alfit.local',
        role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const ['biz1']);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
}

const _precautions = '작업 중에는 안전화를 꼭 착용해 주세요. 현장 입구에서 출입 명부를 작성합니다.\n'
    '휴게 시간에는 지정된 휴게실만 이용할 수 있으며, 작업장 안에서는 음식물 섭취가 금지됩니다.';

BusinessModel _biz() => BusinessModel(
      id: 'biz1', name: '중앙물류센터 수도권 1센터', ownerId: 'owner1', businessNumber: '0000000000', category: '물류', subCategory: '창고',
      address: '경기도 화성시 동탄순환대로 1길 23', detailAddress: '3층 물류동 A구역', phone: '031-000-0000', precautions: _precautions,
      isApproved: true, createdAt: DateTime(2026, 1, 1),
    );

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f2(double v) => v.toStringAsFixed(2);
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '452';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du452-tb' && _env['DU_BEFORE_OBSERVE'] == '452') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du452-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  const fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S012PI-${v.id}-DETAIL 사업장 상세 준비사항 — 경고 아이콘 첫 줄 가운데 · 크기 그대로', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S012PI-${v.id}-DETAIL';
        final mode = _before ? 'before' : 'strict';
        _out('D452 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        SharedPreferences.setMockInitialValues({});
        final calls = <String, int>{};
        void inc(String k) => calls[k] = (calls[k] ?? 0) + 1;
        final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        m.setMockMessageHandler(fnChannel, (msg) async {
          inc('functions');
          return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'blocked', <String, Object?>{'code': 'not-found'}]);
        });
        for (final op in const ['documentReferenceGet', 'queryGet', 'documentReferenceSet', 'documentReferenceUpdate',
          'documentReferenceDelete', 'writeBatchCommit', 'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
          m.setMockMessageHandler('$fsBase.$op', (msg) async {
            inc('firestore $op');
            return null;
          });
        }
        addTearDown(() {
          m.setMockMessageHandler(fnChannel, null);
        });
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final overflows = <String>[];
        final fwErrors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final s = d.exceptionAsString();
          if (s.contains('overflowed')) {
            final full = d.toString();
            final k = full.indexOf('The relevant error-causing widget was');
            final loc = k < 0 ? '' : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
            overflows.add('${s.split('\n').first} @ $loc');
          } else {
            fwErrors.add(s.split('\n').first);
            prev?.call(d);
          }
        };
        addTearDown(() => FlutterError.onError = prev);
        void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');

        final key = GlobalKey();
        final biz = _biz();
        await t.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => _Owner()),
            ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
          ],
          child: RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.getThemeByRole('BUSINESS_ADMIN'),
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
                  onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => BusinessDetailScreen(business: biz))),
                  child: const Text('host'))))),
            ),
          ),
        ));
        await t.tap(find.text('host'));
        for (var i = 0; i < 14; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D452 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'DETAIL',
            'state': state,
          });
          shots++;
        }

        // ── 준비사항 카드 — 아이콘 · 본문(굴린 뒤 값은 즉시) ──
        final bodyF = find.byWidgetPredicate((w) => w is RichText && _plainOf(w).startsWith('작업 중에는'), skipOffstage: false);
        final iconF = find.byIcon(Icons.warning_amber_rounded, skipOffstage: false);
        must('준비사항 본문 · 아이콘 1/1', bodyF.evaluate().length == 1 && iconF.evaluate().length == 1,
            '${bodyF.evaluate().length}/${iconF.evaluate().length}');
        await t.ensureVisible(bodyF);
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 60));
        }
        final rp = t.renderObject(bodyF) as RenderParagraph;
        final bR = t.getRect(bodyF);
        final b0 = rp.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1)).first;
        final iR = t.getRect(iconF);
        final dFirst = iR.center.dy - (bR.top + (b0.top + b0.bottom) / 2);
        final size = (t.widget(iconF) as Icon).size ?? -1;
        final writes = calls.keys.where((k) => k.contains('Set') || k.contains('Update') || k.contains('Delete') || k.contains('Commit')).length;
        _out('D452 $tok att icon size=${_f2(size)} dFirst=${_f2(dFirst)} line=${_f2(b0.bottom - b0.top)} writes=$writes');
        await shot('1card', 'precaution-card');

        must('쓰기 0', writes == 0, '쓰기 $writes');
        if (_before) {
          if (v.id == 'B') {
            // 음성 기대(코드 확정) — 아이콘 위 여백 1 · 크기 iconSize(20) 고정이라 B 첫 줄(30px · 줄 높이 1.5) 가운데보다 위(≈ 13).
            must('before B 아이콘 첫 줄 벗어남 검출', dFirst.abs() > 4, _f2(dFirst));
          }
        } else {
          final want = v.id == 'B' ? 17.0 : 18.0;
          must('strict 아이콘 크기 그대로(iconSize 20)', (size - want).abs() <= 0.05, _f2(size));
          must('strict 아이콘 = 첫 줄 가운데(±1.5)', dFirst.abs() <= 1.5, _f2(dFirst));
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D452 $tok done state=DETAIL mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
