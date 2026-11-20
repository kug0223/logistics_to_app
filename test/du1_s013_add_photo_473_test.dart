// ignore_for_file: depend_on_referenced_packages
// [DU473 · 자체 판정 셀 · 표시만] DU-S013 사업장 수정 3단계(상세) — '사진 추가 (복수선택)' 타일 2곳 글자 대비.
//   before = 현재 A(business_form_screen c9ae7e82 · DU455 후보) / strict = 후보. harness 는 DU455 시험과 같고('다음' 2번 · 3단계) 측정만 바꿨다.
//   harness 는 business_form_responsive_render_test(BF-R-01)와 같다(수정 모드 · 좌표 있는 사업장 · '다음' 2번).
//   출근 방식을 'both' 로 두어 GPS · 비콘 카드가 함께 그려진다(기존 시험은 'gps' 라 비콘 카드를 그린 적이 없다).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du473-tb/DU_BEFORE_OBSERVE=473 · TA after/du473-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_model.dart';
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

BusinessModel _business() => BusinessModel(
      id: 'biz1', name: '중앙물류센터 수도권 1센터', ownerId: 'admin1', companyName: '주식회사 중앙물류', ownerName: '김사장',
      businessNumber: '0000000000', address: '경기도 화성시 동탄순환대로 1길 23', detailAddress: '3층 물류동 A구역',
      category: '물류', subCategory: '창고', phone: '031-000-0000', latitude: 37.2, longitude: 127.07, city: '화성시', district: '동탄면',
      isApproved: true, createdAt: DateTime(2026, 1, 1),
      attendanceType: 'both', beaconUUID: 'E2C56DB5-DFFB-48D2-B060-D0F5A71096E0',
    );

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '473';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du473-tb' && _env['DU_BEFORE_OBSERVE'] == '473') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du473-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S013AP-${v.id}-PHOTO 사업장 수정 3단계 — 사진 추가 타일 글자 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S013AP-${v.id}-PHOTO';
        final mode = _before ? 'before' : 'strict';
        _out('D473 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
              home: BusinessFormScreen(business: _business()),
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

        must('1 → 2단계', await goNext());
        // [진단 수리 1/3] 사진 · 교통편 칸은 3단계(상세 · _buildDetailStep)에 있다 — 진단 판은 '다음' 1번(2단계 기본 정보)이라 0/0 이었다.
        must('2 → 3단계', await goNext());
        // 넘침은 3단계만 센다 — 앞 단계 넘침은 이 셀 범위 밖이라 비운다(원문은 출력 · DU455 실측 0).
        _out('D473 $tok att prior overflows=${overflows.length}');
        overflows.clear();

        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D473 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'PHOTO',
            'state': state,
          });
          shots++;
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);

        // ── 3단계 '사진 추가 (복수선택)' 타일 2곳(값은 캡처 뒤 즉시) — 글자색 · 놓인 면 · 대비 ──
        final addF = rt((p) => p == '사진 추가');
        final multiF = rt((p) => p == '(복수선택)');
        must('사진 추가 2 · 복수선택 2', addF.evaluate().length == 2 && multiF.evaluate().length == 2,
            '${addF.evaluate().length}/${multiF.evaluate().length}');
        await t.ensureVisible(addF.first);
        await settle(4);
        await shot('1photo', 'step3-add-photo');
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

        var minAdd = 99.0, minMulti = 99.0;
        Color? addC, multiC, tileBg;
        for (final e in addF.evaluate()) {
          addC = (e.widget as RichText).text.style?.color;
          tileBg = bgOf(e);
          final x = cr(addC, tileBg);
          if (x < minAdd) minAdd = x;
        }
        for (final e in multiF.evaluate()) {
          multiC = (e.widget as RichText).text.style?.color;
          final x = cr(multiC, bgOf(e));
          if (x < minMulti) minMulti = x;
        }
        String tk(Color? c) => c == AppColors.grey600 ? 'grey600' : c == AppColors.grey500 ? 'grey500' : c == AppColors.textSecondary
            ? 'textSecondary' : c == AppColors.textTertiary ? 'textTertiary' : c == AppColors.grey200 ? 'grey200' : 'x${hex(c)}';
        _out('D473 $tok att add text=${tk(addC)} bg=${tk(tileBg)} cr=${minAdd.toStringAsFixed(2)}');
        _out('D473 $tok att multi text=${tk(multiC)} cr=${minMulti.toStringAsFixed(2)}');
        if (_before) {
          // 음성 기대(코드 확정) — grey200 면 위 grey600(3.97) · grey500(약 2.3).
          must('before 사진 추가 grey600 · 복수선택 grey500 · 대비 미달 검출',
              addC == AppColors.grey600 && multiC == AppColors.grey500 && minAdd < 4.5 && minMulti < 4.5,
              '${tk(addC)} ${tk(multiC)} ${minAdd.toStringAsFixed(2)} ${minMulti.toStringAsFixed(2)}');
        } else {
          must('strict 사진 추가 textSecondary · 복수선택 textTertiary · 대비 ≥ 4.5',
              addC == AppColors.textSecondary && multiC == AppColors.textTertiary && minAdd >= 4.5 && minMulti >= 4.5,
              '${tk(addC)} ${tk(multiC)} ${minAdd.toStringAsFixed(2)} ${minMulti.toStringAsFixed(2)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D473 $tok done state=PHOTO mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
