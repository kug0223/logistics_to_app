// ignore_for_file: depend_on_referenced_packages
// [DU478 · 자체 판정 셀 · 표시만] DU-S013 사업장 수정 2단계(기본 정보) — 대표 이미지 · 사업자등록증 빈 칸 글자 대비(면 grey200).
//   before = 현재 A(business_form_screen 8f8714ea · DU473 후보) / strict = 후보. harness 는 DU473 시험(9bdc215a)과 같고('다음' 1번 · 2단계) 측정만 바꿨다.
//   harness 는 business_form_responsive_render_test(BF-R-01)와 같다(수정 모드 · 좌표 있는 사업장 · '다음' 2번).
//   출근 방식을 'both' 로 두어 GPS · 비콘 카드가 함께 그려진다(기존 시험은 'gps' 라 비콘 카드를 그린 적이 없다).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du478-tb/DU_BEFORE_OBSERVE=478 · TA after/du478-ta/없음.
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '478';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du478-tb' && _env['DU_BEFORE_OBSERVE'] == '478') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du478-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S013IM-${v.id}-EMPTY 사업장 수정 2단계 — 대표 이미지 · 등록증 빈 칸 글자 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S013IM-${v.id}-EMPTY';
        final mode = _before ? 'before' : 'strict';
        _out('D478 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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

        // 넘침은 2단계만 센다 — 1단계 넘침은 이 셀 범위 밖이라 비운다(원문은 출력 · DU455 실측 0).
        _out('D478 $tok att prior overflows=${overflows.length}');
        overflows.clear();
        must('1 → 2단계', await goNext());

        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D478 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'EMPTY',
            'state': state,
          });
          shots++;
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);

        // ── 2단계 대표 이미지 · 사업자등록증 빈 칸 글자(값은 캡처 뒤 즉시) — 글자색 · 놓인 면(grey200) · 대비 ──
        final mainF = rt((p) => p == '대표 이미지 추가 (선택)');
        final licF = rt((p) => p == '사업자등록증 이미지 업로드');
        final fmtF = rt((p) => p == 'JPG / PNG');
        must('대표 이미지 1 · 등록증 1 · 형식 1', mainF.evaluate().length == 1 && licF.evaluate().length == 1 && fmtF.evaluate().length == 1,
            '${mainF.evaluate().length}/${licF.evaluate().length}/${fmtF.evaluate().length}');
        await t.ensureVisible(mainF);
        await settle(4);
        await shot('1main', 'step2-main-image');
        await t.ensureVisible(licF);
        await settle(4);
        await shot('2lic', 'step2-license');
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

        String tk(Color? c) => c == AppColors.grey600 ? 'grey600' : c == AppColors.grey500 ? 'grey500' : c == AppColors.textSecondary
            ? 'textSecondary' : c == AppColors.textTertiary ? 'textTertiary' : c == AppColors.grey200 ? 'grey200' : 'x${hex(c)}';
        final mainC = (t.widget(mainF) as RichText).text.style?.color;
        final mainBg = bgOf(mainF.evaluate().first);
        final mainCr = cr(mainC, mainBg);
        final licC = (t.widget(licF) as RichText).text.style?.color;
        final licBg = bgOf(licF.evaluate().first);
        final licCr = cr(licC, licBg);
        final fmtC = (t.widget(fmtF) as RichText).text.style?.color;
        final fmtBg = bgOf(fmtF.evaluate().first);
        final fmtCr = cr(fmtC, fmtBg);
        _out('D478 $tok att main text=${tk(mainC)} bg=${tk(mainBg)} cr=${mainCr.toStringAsFixed(2)}');
        _out('D478 $tok att lic text=${tk(licC)} bg=${tk(licBg)} cr=${licCr.toStringAsFixed(2)}');
        _out('D478 $tok att fmt text=${tk(fmtC)} bg=${tk(fmtBg)} cr=${fmtCr.toStringAsFixed(2)}');
        final crs = '${mainCr.toStringAsFixed(2)}/${licCr.toStringAsFixed(2)}/${fmtCr.toStringAsFixed(2)}';
        if (_before) {
          // 음성 기대(코드 확정) — grey200 면 위 grey600(3.97) · grey500(약 2.3).
          must('before 대표 이미지 · 등록증 grey600 · 형식 grey500 · 대비 미달 검출',
              mainC == AppColors.grey600 && licC == AppColors.grey600 && fmtC == AppColors.grey500 && mainCr < 4.5 && licCr < 4.5 && fmtCr < 4.5,
              '${tk(mainC)} ${tk(licC)} ${tk(fmtC)} $crs');
        } else {
          must('strict 대표 이미지 · 등록증 textSecondary · 형식 textTertiary · 대비 ≥ 4.5',
              mainC == AppColors.textSecondary && licC == AppColors.textSecondary && fmtC == AppColors.textTertiary &&
                  mainCr >= 4.5 && licCr >= 4.5 && fmtCr >= 4.5,
              '${tk(mainC)} ${tk(licC)} ${tk(fmtC)} $crs');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D478 $tok done state=EMPTY mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
