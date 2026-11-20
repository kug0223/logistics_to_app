// ignore_for_file: depend_on_referenced_packages
// [DU445 · 자체 판정 셀 · 표시만] DU-S013 사업장 수정 3단계 — 근태 위치 카드: GPS 눈금 글자 · 비콘 '인식 거리' 머리 · 비콘 눈금.
//   before = 현재 A(business_form_screen 71bdc337) / strict = 후보(c5f2227b).
//   harness 는 business_form_responsive_render_test(BF-R-01)와 같다(수정 모드 · 좌표 있는 사업장 · '다음' 2번).
//   출근 방식을 'both' 로 두어 GPS · 비콘 카드가 함께 그려진다(기존 시험은 'gps' 라 비콘 카드를 그린 적이 없다).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du445-tb/DU_BEFORE_OBSERVE=445 · TA after/du445-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

String _f(double v) => v.toStringAsFixed(2);
String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '445';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du445-tb' && _env['DU_BEFORE_OBSERVE'] == '445') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du445-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textTertiary': AppColors.textTertiary, 'grey400': AppColors.grey400, 'infoDark': AppColors.infoDark,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

/// 글자 상자 top 으로 줄을 가른다 — 줄 수 · 줄바꿈이 공백 뒤에서만 일어났는가.
({int lines, bool ok}) _breaks(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  double? prevTop;
  var ok = true;
  for (var i = 0; i < s.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final tp = bx.first.top;
    if (!tops.any((x) => (x - tp).abs() < 0.5)) tops.add(tp);
    if (prevTop != null && (tp - prevTop).abs() >= 0.5) {
      final before = TextLayout.plain(s.substring(0, i)).trimRight();
      final raw = s.substring(0, i);
      if (!(raw.endsWith(' ') || raw.endsWith(String.fromCharCode(0x00A0)) || before.isEmpty)) ok = false;
    }
    prevTop = tp;
  }
  return (lines: tops.length, ok: ok);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S013AT-${v.id}-ATTEND 사업장 수정 3단계 근태 위치 — GPS 눈금 글자 · 비콘 머리 배치 · 비콘 눈금 세 칸', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S013AT-${v.id}-ATTEND';
        final mode = _before ? 'before' : 'strict';
        _out('D445 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        must('2 → 3단계', await goNext());
        // 넘침은 3단계 근태 위치 카드만 센다 — 앞 단계 넘침은 이 셀 범위 밖이라 비운다(원문은 출력).
        _out('D445 $tok att prior overflows=${overflows.length}');
        overflows.clear();

        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D445 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'ATTEND',
            'state': state,
          });
          shots++;
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        final gpsTitle = rt((p) => p == 'GPS 허용 반경');
        must('GPS 카드 1', gpsTitle.evaluate().length == 1, '${gpsTitle.evaluate().length}개');
        await t.ensureVisible(gpsTitle);
        await settle(4);

        // ── GPS 눈금(값은 즉시) ──
        // 같은 글자가 위 값 칩에도 있다(기본 반경 '100m' · 진단 1 W 1/2/1) — 같은 글자 중 가장 아래(눈금 줄)의 것을 고른다.
        Element? lowest(Finder f) {
          Element? best;
          var bestTop = double.negativeInfinity;
          for (final e in f.evaluate()) {
            final top = t.getRect(find.byElementPredicate((x) => identical(x, e), skipOffstage: false)).top;
            if (top > bestTop) {
              bestTop = top;
              best = e;
            }
          }
          return best;
        }
        final gpsFinders = [for (final x in const ['30m', '100m', '500m']) rt((p) => p == x)];
        final gpsN = gpsFinders.map((f) => f.evaluate().length).join('/');
        final gpsPicked = [for (final f in gpsFinders) lowest(f)];
        final gpsColors = [for (final e in gpsPicked) e == null ? null : (e.widget as RichText).text.style?.color];
        final gpsCr = gpsColors.map((c) => _cr(c, AppColors.surface)).reduce(math.min);
        _out('D445 $tok att gps n=$gpsN color=${_tok(gpsColors.first)} same=${gpsColors.toSet().length == 1} cr=${_f(gpsCr)}');
        await shot('1gps', 'gps-card');

        // ── 비콘 머리 · 눈금(값은 즉시) ──
        final bTitle = rt((p) => p == '인식 거리');
        final bChip = rt((p) => p == '보통 (3~8m)');
        must('비콘 머리 제목 · 값 칩 1/1', bTitle.evaluate().length == 1 && bChip.evaluate().length == 1,
            '${bTitle.evaluate().length}/${bChip.evaluate().length}');
        await t.ensureVisible(bTitle);
        await settle(4);
        final tR = t.getRect(bTitle);
        final cR = t.getRect(bChip);
        final stacked = cR.top >= tR.bottom - 0.5;
        final tj = _breaks(t.renderObject(bTitle) as RenderParagraph);
        final cj = _breaks(t.renderObject(bChip) as RenderParagraph);
        _out('D445 $tok att head stacked=$stacked titleLines=${tj.lines} titleOk=${tj.ok} chipLines=${cj.lines} chipOk=${cj.ok} '
            'chipColor=${_tok((t.widget(bChip) as RichText).text.style?.color)}');
        final tickRe = [RegExp(r'^멀리 ?\(~10m\)$'), RegExp(r'^보통 ?\(~5m\)$'), RegExp(r'^가까이 ?\(~1m\)$')];
        final ticks = [for (final r in tickRe) rt((p) => r.hasMatch(p))];
        final tickN = ticks.map((f) => f.evaluate().length).join('/');
        must('비콘 눈금 1/1/1', tickN == '1/1/1', tickN);
        final tickJ = [for (final f in ticks) _breaks(t.renderObject(f) as RenderParagraph)];
        final tickColors = [for (final f in ticks) (t.widget(f) as RichText).text.style?.color];
        final tickCr = tickColors.map((c) => _cr(c, AppColors.surface)).reduce(math.min);
        final tickR = [for (final f in ticks) t.getRect(f)];
        final ordered = tickR[0].right <= tickR[1].left + 0.5 && tickR[1].right <= tickR[2].left + 0.5;
        _out('D445 $tok att ticks lines=${tickJ.map((j) => j.lines).join('/')} ok=${tickJ.every((j) => j.ok)} ordered=$ordered '
            'color=${_tok(tickColors.first)} same=${tickColors.toSet().length == 1} cr=${_f(tickCr)}');
        await shot('2beacon', 'beacon-card');

        must('GPS 눈금 세 글 모두 있음', gpsPicked.every((e) => e != null), gpsN);
        if (_before) {
          // 음성 기대(코드 확정) — 눈금 grey400 · 비콘 눈금 grey400.
          must('before 옅은 눈금 검출', gpsColors.first == AppColors.grey400 && tickColors.first == AppColors.grey400,
              '${_tok(gpsColors.first)} ${_tok(tickColors.first)}');
        } else {
          must('strict GPS 눈금 textTertiary · 대비 ≥ 4.5', gpsColors.every((c) => c == AppColors.textTertiary) && gpsCr >= 4.5, _f(gpsCr));
          must('strict 비콘 눈금 textTertiary · 대비 ≥ 4.5', tickColors.every((c) => c == AppColors.textTertiary) && tickCr >= 4.5, _f(tickCr));
          must('strict 비콘 눈금 줄바꿈은 공백에서만 · 세 칸 순서', tickJ.every((j) => j.ok) && ordered, '${tickJ.map((j) => j.ok)} $ordered');
          must('strict 비콘 머리(W 한 줄 · B 값 칩 아래 줄) · 제목/칩 낱말 경계', stacked == (v.id == 'B') && tj.ok && cj.ok,
              '쌓기 $stacked ${tj.ok} ${cj.ok}');
          must('strict 넘침 0(3단계)', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D445 $tok done state=ATTEND mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
