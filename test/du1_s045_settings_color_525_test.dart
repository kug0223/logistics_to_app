// ignore_for_file: depend_on_referenced_packages
// [DU525 · 표시만] 설정 화면(lib/screens/common/settings_screen.dart) 본문 색 예산 — 진입 단계의 빨강(서브관리자 탈퇴 행 아이콘 면 ·
//   서명/날인 '삭제' 외곽선 버튼)과 분류색 아이콘 면(날인 카드 머리 warning)을 중립으로. 최종 확인창의 빨강은 그대로(이 셀 밖).
//   before = 현재 A(settings_screen e928b5bf) 기록 · strict = 후보. 역할 BA(사업장 관리자 · 날인 등록) · USER(서명 등록) · SUB(서브관리자 · 지원자 모드) × W/B.
//   하네스 = test/settings_broken_image_fallback_test.dart(env 없이 도는 기존 시험)의 provider 대역 + lkit 줄 형식. 누르는 것 0(끌기만).
//   [r2] 화면 initState 가 부르는 플랫폼 채널 둘(알림 권한 조회 · 앱 버전)에 응답을 준다 — r1 은 응답이 없어 MissingPluginException 이
//   onError 를 바꿔 둔 동안 zone 으로 올라와 binding 단언(binding.dart:1018)으로 실패했다. 방식 = du1_s045_settings_design_241_test 와 같다.
//   기본 skip — TB before/du525-tb/DU_BEFORE_OBSERVE=525 · TA after/du525-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/settings_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/du1_vq_capture.dart';

/// 1×1 PNG(유효) — settings_broken_image_fallback_test.dart 와 같은 값.
const _png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAC'
    'hwGA60e6kgAAAABJRU5ErkJggg==';

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

/// 역할 대역 — BA = 사업장 관리자(날인 등록) · USER = 지원자(서명 등록) · SUB = 서브관리자(지원자 모드 · 서명 등록).
class _P extends UserProvider {
  _P(this.scene);

  final String scene;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: 'QA 관리자',
        email: 'u1@alfit.local',
        role: scene == 'BA' ? UserRole.BUSINESS_ADMIN : UserRole.USER,
        managedBusinessIds: scene == 'BA' ? const ['biz1'] : const [],
        subAdminBusinessIds: scene == 'SUB' ? const ['biz1'] : const [],
        sealBase64: scene == 'BA' ? _png : null,
        sealType: 'stamp',
        signatureBase64: scene == 'BA' ? null : _png,
      );

  @override
  bool get isAdminMode => false;

  @override
  String? get effectiveBusinessId => 'biz1';

  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;

  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _enc(String s) => s.isEmpty ? '-' : base64Url.encode(utf8.encode(s)).replaceAll('=', '');
String _hex(Color? c) => c == null ? 'none' : (c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

/// 시각 오류 수집 — 넘침은 원문 + 위치, 그 밖 framework 오류도 원문.
class _Seen {
  final overflows = <String>[];
  final other = <String>[];

  void add(FlutterErrorDetails d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      final full = d.toString();
      final k = full.indexOf('The relevant error-causing widget was');
      final loc = k < 0
          ? ''
          : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
      overflows.add('${m.split('\n').first} @ $loc');
    } else {
      other.add(m);
    }
  }
}

typedef _V = ({String id, double w, double h, double s});
const _views = <_V>[(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
const _cases = <({String id, int shots})>[(id: 'BA', shots: 2), (id: 'USER', shots: 2), (id: 'SUB', shots: 2)];

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '525';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du525-tb' && _env['DU_BEFORE_OBSERVE'] == '525') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du525-ta' && _env['DU_BEFORE_OBSERVE'] == null);
String? _halt;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  // [r2] 플랫폼 응답 — 알림 권한 = 거부(0 → 사용자 문서 조회 없음 · settings_screen :195–201) · 앱 버전 = 대역 값.
  //   이 화면이 누르지 않고 부르는 채널은 이 둘뿐이다(_loadNotificationStatus · _loadAppVersion · _loadBusinessSeal 은 effectiveBusinessId 가 있어 호출 0).
  const permChannel = MethodChannel('flutter.baseflow.com/permissions/methods');
  final permCalls = <String>[];
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
        appName: 'ALfit', packageName: 'com.alfit.app', version: '1.0.0', buildNumber: '1', buildSignature: '');
    permCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(permChannel, (call) async {
      permCalls.add(call.method);
      return 0;
    });
  });
  tearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(permChannel, null));
  setUpAll(() async {
    await initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  for (final v in _views) {
    for (final c in _cases) {
      testWidgets('S045SC-${v.id}-${c.id} 설정 본문 색 예산 — 진입 단계 빨강 · 분류색 아이콘 면을 중립으로', (t) async {
        final tok = 'S045SC-${v.id}-${c.id}';
        if (_halt != null) fail('$tok 진입 0 — 앞 실패: $_halt');
        await t.runAsync(vqLoadFonts);
        final prevOnError = FlutterError.onError;
        addTearDown(() => FlutterError.onError = prevOnError);
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final mode = _before ? 'before' : 'strict';
        _out('D525 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        final seen = _Seen();
        void need(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');
        final checks = <(String, bool, String)>[];
        void chk(String k, bool ok, [String why = '']) => checks.add((k, ok, why));
        Object? failure;
        StackTrace? failureSt;
        var shots = 0;
        var raw = '';
        try {
          FlutterError.onError = seen.add;
          final key = GlobalKey();
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>.value(value: _P(c.id)),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: c.id == 'BA' ? RoleTheme.businessAdminTheme : RoleTheme.workerTheme,
                locale: const Locale('ko', 'KR'),
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                builder: (ctx, child) =>
                    MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: const SettingsScreen(),
              ),
            ),
          ));
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 80));
          }
          final nScreen = find.byType(SettingsScreen).evaluate().length;
          need('설정 화면 1', nScreen == 1, '개수 $nScreen');
          Future<void> shot(String id, String state) async {
            _out('D525 $tok shot $id ovf=${seen.overflows.length}');
            await vqCapture(t, key, '${tok}_$id', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode,
              'fixture': c.id, 'state': state,
            });
            shots++;
          }

          await shot('1top', 'top');
          final listF = find.descendant(of: find.byType(SettingsScreen), matching: find.byType(Scrollable), skipOffstage: true).first;
          // 목록은 보이는 부분만 짓는다 — 대상이 나올 때까지 실제로 끈다.
          Future<void> bring(Finder f) async {
            await t.scrollUntilVisible(f, 120, scrollable: listF, maxScrolls: 80, duration: const Duration(milliseconds: 50));
            for (var i = 0; i < 6; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
          }

          Finder label(String s) => find.byWidgetPredicate((w) => w is Text && TextLayout.plain(w.data ?? '') == s, skipOffstage: true);

          if (c.id == 'SUB') {
            // ① '서브관리자 탈퇴' 행 — 아이콘 색 · 아이콘 면 색(진입 단계 · 빨강 0)
            final titleF = label('서브관리자 탈퇴');
            await bring(titleF);
            final nTitle = titleF.evaluate().length;
            need('서브관리자 탈퇴 행 1', nTitle == 1, '개수 $nTitle');
            final rowF = find.ancestor(of: titleF, matching: find.byType(Row)).first;
            final iconF = find.descendant(of: rowF, matching: find.byIcon(Icons.logout_outlined), skipOffstage: true);
            final nIcon = iconF.evaluate().length;
            need('탈퇴 행 아이콘 1', nIcon == 1, '개수 $nIcon');
            final icon = t.widget<Icon>(iconF).color;
            final boxW = t.widget<Container>(find.ancestor(of: iconF, matching: find.byType(Container)).first);
            final dec = boxW.decoration;
            final face = dec is BoxDecoration ? dec.color : boxW.color;
            final rowInk = find.ancestor(of: titleF, matching: find.byType(InkWell)).first;
            final rr = t.getRect(rowInk);
            raw = 'leave icon ${_hex(icon)} face ${_hex(face)} row $rr';
            _out('D525 $tok att leave icon=${_hex(icon)} face=${_hex(face)} h=${rr.height.toStringAsFixed(1)}');
            if (!_before) {
              chk('strict 서브관리자 탈퇴 행 — 아이콘 grey600 · 면 grey100(빨강 0)', icon == AppColors.grey600 && face == AppColors.grey100, raw);
            }
            await shot('2leave', 'subadmin-leave-row');
          } else {
            // ① '삭제' 외곽선 버튼(BA = 날인 카드 · USER = 서명 카드) — 글 · 아이콘 · 테두리 색 · 대비 · 받는 자리(기록)
            final delText = label('삭제');
            await bring(delText);
            final nDel = delText.evaluate().length;
            need('삭제 버튼 글 1', nDel == 1, '개수 $nDel');
            final btnF = find.ancestor(of: delText, matching: find.byWidgetPredicate((w) => w is OutlinedButton)).first;
            final btn = t.widget<OutlinedButton>(btnF);
            final ro = t.renderObject<RenderParagraph>(find.descendant(of: delText, matching: find.byType(RichText), skipOffstage: true).first);
            final fg = ro.text.style?.color;
            final icoF = find.descendant(of: btnF, matching: find.byIcon(Icons.delete_outline), skipOffstage: true);
            final nIco = icoF.evaluate().length;
            need('삭제 버튼 아이콘 1', nIco == 1, '개수 $nIco');
            final ico = t.widget<Icon>(icoF).color;
            final side = btn.style?.side?.resolve(<WidgetState>{})?.color;
            final ratio = fg == null ? 0.0 : _contrast(fg, Colors.white);
            final br = t.getRect(btnF);
            raw = 'del text ${_hex(fg)} icon ${_hex(ico)} side ${_hex(side)} ratio ${ratio.toStringAsFixed(2)} rect $br';
            _out('D525 $tok att del text=${_hex(fg)} icon=${_hex(ico)} side=${_hex(side)} ratio=${ratio.toStringAsFixed(2)} '
                'h=${br.height.toStringAsFixed(1)}');
            if (!_before) {
              chk('strict 삭제 진입 버튼 — 글 · 아이콘 textSecondary · 테두리 grey300(빨강 0) · 대비 ≥4.5',
                  fg == AppColors.textSecondary && ico == AppColors.textSecondary && side == AppColors.grey300 && ratio >= 4.5, raw);
            }
            if (c.id == 'BA') {
              // ② 날인 카드 머리 아이콘 상자 — 분류색 면 0
              final vF = find.byIcon(Icons.verified_outlined, skipOffstage: true);
              final nV = vF.evaluate().length;
              need('날인 카드 머리 아이콘 1', nV == 1, '개수 $nV');
              final vIcon = t.widget<Icon>(vF).color;
              final vBox = t.widget<Container>(find.ancestor(of: vF, matching: find.byType(Container)).first);
              final vDec = vBox.decoration;
              final vFace = vDec is BoxDecoration ? vDec.color : vBox.color;
              raw = '$raw | chip icon ${_hex(vIcon)} face ${_hex(vFace)}';
              _out('D525 $tok att chip icon=${_hex(vIcon)} face=${_hex(vFace)}');
              if (!_before) {
                chk('strict 날인 카드 머리 아이콘 상자 — 아이콘 grey600 · 면 grey100', vIcon == AppColors.grey600 && vFace == AppColors.grey100, raw);
              }
            }
            await shot('2del', 'delete-entry-button');
          }

          // ③ 본문 전체 — 빨강 채움 버튼 수(지어진 범위)
          var redFill = 0;
          for (final e in find
              .descendant(of: find.byType(SettingsScreen), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton), skipOffstage: true)
              .evaluate()) {
            final bg = (e.widget as ButtonStyleButton).style?.backgroundColor?.resolve(<WidgetState>{});
            if (bg == AppColors.error || bg == AppColors.errorDark) redFill++;
          }
          _out('D525 $tok att scan redfill=$redFill');
          if (!_before) chk('strict 본문 빨강 채움 버튼 0', redFill == 0, 'redFill $redFill');
        } catch (e, st) {
          failure = e;
          failureSt = st;
        } finally {
          FlutterError.onError = prevOnError;
        }

        // 공통 정리 — 화면을 내리고 남은 timer 가 끝날 시간을 준다.
        var cleanupErr = '';
        try {
          await t.pumpWidget(const SizedBox.shrink());
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(seconds: 1));
          }
        } catch (e, st) {
          cleanupErr = e.toString();
          if (failure == null) {
            failure = e;
            failureSt = st;
          }
        }
        final exc = t.takeException();
        if (exc != null && failure == null) {
          failure = exc;
          failureSt = StackTrace.current;
        }
        final nOvf = seen.overflows.length;
        final nFw = seen.other.length;
        final ovfRaw = seen.overflows.join('\n----\n');
        final fwRaw = seen.other.join('\n----\n');
        _out('R525 $tok raw m64=${_enc(raw)} ovf64=${_enc(ovfRaw)} fw64=${_enc(fwRaw)} cleanup64=${_enc(cleanupErr)} '
            'fail64=${_enc(failure?.toString() ?? '')} perm64=${_enc(permCalls.join(','))}');
        _out('D525 $tok done state=${c.id} mode=$mode captures=$shots overflows=$nOvf exc=${exc != null}');

        final f0 = failure;
        if (f0 != null) {
          _halt ??= '$tok ${f0.toString().split('\n').first}';
          Error.throwWithStackTrace(f0, failureSt ?? StackTrace.current);
        }
        if (!_before) chk('strict 넘침 0', nOvf == 0, ovfRaw);
        // [r2] 응답 없는 플랫폼 채널이 남아 있으면 두 모드 모두 멈춘다(r1 원인의 재발 방지).
        chk('미처리 framework 예외 0', nFw == 0, fwRaw);
        chk('캡처 수 = 선언', shots == c.shots, 'shots $shots want ${c.shots}');
        final bad = checks.where((x) => !x.$2).toList();
        if (bad.isNotEmpty) _halt ??= '$tok ${bad.first.$1}';
        for (final x in checks) {
          expect(x.$2, isTrue, reason: '$tok ${x.$1} ${x.$3}');
        }
      }, skip: !_optIn);
    }
  }
}
