// ignore_for_file: depend_on_referenced_packages
// [DU479 · 자체 판정 셀 · 표시만] DU-S013 사업장 신규 등록 2단계 — 사업자등록증 필수 안내 글자 대비.
//   before = 현재 A(business_form_screen e91b0a0b · DU478 후보) / strict = 후보. harness 는 DU478 시험(c243fddb)을 신규 모드(BusinessFormScreen() · 업종 선택 → '다음' 1번)로 바꾸고 측정만 바꿨다.
//   harness 는 business_form_responsive_render_test(BF-R-01)와 같다(수정 모드 · 좌표 있는 사업장 · '다음' 2번).
//   출근 방식을 'both' 로 두어 GPS · 비콘 카드가 함께 그려진다(기존 시험은 'gps' 라 비콘 카드를 그린 적이 없다).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du479-tb/DU_BEFORE_OBSERVE=479 · TA after/du479-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_form_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  // storageBucket 필수 — 폼이 StorageService() 를 필드로 든다(기존 시험 주석).
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

class _AdminProvider extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'admin1', username: 'admin1', name: '김사장', email: 'admin1@alfit.local', role: UserRole.BUSINESS_ADMIN,
        managedBusinessIds: const ['biz1'],
      );
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
}

const _need = '신규 사업장 등록 시 사업자등록증 이미지가 필요합니다.';

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '479';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du479-tb' && _env['DU_BEFORE_OBSERVE'] == '479') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du479-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

/// 글자 상자 top 으로 줄을 가른다 — 줄 수 · 줄바꿈이 공백 뒤에서만 일어났는가.

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S013NL-${v.id}-NEW 사업장 신규 등록 2단계 — 사업자등록증 필수 안내 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S013NL-${v.id}-NEW';
        final mode = _before ? 'before' : 'strict';
        _out('D479 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
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
        Future<void> settle([int n = 12]) async {
          for (var i = 0; i < n; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }

        final key = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(create: (_) => _AdminProvider()),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: const BusinessFormScreen(),
            ),
          ),
        ));
        await settle();
        Future<bool> goNext() async {
          final next = find.text('다음');
          if (next.evaluate().isEmpty) return false;
          await t.ensureVisible(next.first);
          await t.pump();
          await t.tap(next.first, warnIfMissed: false);
          await settle();
          return true;
        }

        // 넘침은 2단계만 센다 — 1단계 넘침은 이 셀 범위 밖이라 비운다(원문은 출력 · DU455 실측 0).
        _out('D479 $tok att prior overflows=${overflows.length}');
        overflows.clear();
        // 신규 모드 1단계 — 업종(펼침 목록) '회사' → 세부 '물류센터' 를 고른다(_validateStep1 · 업종 · 세부 업종 필수).
        Future<void> tapText(String s) async {
          final f = find.text(s);
          must('글자 $s 1', f.evaluate().length == 1, '개수 ${f.evaluate().length}');
          await t.ensureVisible(f);
          await t.pump();
          await t.tap(f, warnIfMissed: false);
          await settle();
        }

        await tapText('회사');
        await tapText('물류센터');
        must('1 → 2단계', await goNext());

        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D479 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'NEW',
            'state': state,
          });
          shots++;
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);

        // ── 신규 2단계 사업자등록증 필수 안내(값은 캡처 뒤 즉시) — 글자색 · 놓인 면 · 대비 ──
        final needF = rt((p) => p == _need);
        must('필수 안내 1', needF.evaluate().length == 1, '개수 ${needF.evaluate().length}');
        await t.ensureVisible(needF);
        await settle(4);
        await shot('1need', 'step2-new-license');
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        Color? bgOf(Element e) {
          Color? found;
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
            if (c != null && c.a > 0) {
              found = c;
              return false;
            }
            return true;
          });
          return found;
        }

        String hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
        double cr(Color? a, Color? b) {
          if (a == null || b == null) return 0;
          final la = a.computeLuminance(), lb = b.computeLuminance();
          return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
        }

        String tk(Color? c) => c == AppColors.warning ? 'warning' : c == AppColors.warningDark ? 'warningDark' : c == AppColors.background
            ? 'background' : c == AppColors.surface ? 'surface' : c == Colors.white ? 'white' : 'x${hex(c)}';
        final needC = (t.widget(needF) as RichText).text.style?.color;
        final needBg = bgOf(needF.evaluate().first);
        final needCr = cr(needC, needBg);
        _out('D479 $tok att need text=${tk(needC)} bg=${tk(needBg)} cr=${needCr.toStringAsFixed(2)}');
        if (_before) {
          // 음성 기대(코드 확정) — warning(#FF9800) 글자 · 밝은 바탕 위 약 2.0.
          must('before 필수 안내 warning · 대비 미달 검출', needC == AppColors.warning && needCr < 4.5, '${tk(needC)} ${tk(needBg)} ${needCr.toStringAsFixed(2)}');
        } else {
          must('strict 필수 안내 warningDark · 대비 ≥ 4.5', needC == AppColors.warningDark && needCr >= 4.5, '${tk(needC)} ${tk(needBg)} ${needCr.toStringAsFixed(2)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D479 $tok done state=NEW mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
