// ignore_for_file: depend_on_referenced_packages
// [DU448 · 자체 판정 셀 · 표시만] DU-S013 사업장 수정 3단계 — 근태 규칙 7행 이름 · 설명 낱말 경계 · 설명 글자, 비콘 안내 글자.
//   before = 현재 A(business_form_screen c5f2227b · DU445 후보) / strict = 후보(f873260a). harness 는 DU445 시험(57480d64)과 같고 측정만 바꿨다.
//   harness 는 business_form_responsive_render_test(BF-R-01)와 같다(수정 모드 · 좌표 있는 사업장 · '다음' 2번).
//   출근 방식을 'both' 로 두어 GPS · 비콘 카드가 함께 그려진다(기존 시험은 'gps' 라 비콘 카드를 그린 적이 없다).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du448-tb/DU_BEFORE_OBSERVE=448 · TA after/du448-ta/없음.
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
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '448';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du448-tb' && _env['DU_BEFORE_OBSERVE'] == '448') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du448-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textTertiary': AppColors.textTertiary, 'grey400': AppColors.grey400, 'grey500': AppColors.grey500,
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
    testWidgets('S013RT-${v.id}-RULES 사업장 수정 3단계 — 근태 규칙 이름 · 설명 낱말 경계 · 설명 글자 · 비콘 안내', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S013RT-${v.id}-RULES';
        final mode = _before ? 'before' : 'strict';
        _out('D448 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
          final next = findVisibleText('다음');
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
        _out('D448 $tok att prior overflows=${overflows.length}');
        overflows.clear();

        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D448 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'RULES',
            'state': state,
          });
          shots++;
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);

        // ── 근태 규칙 7행(값은 즉시) — 이름 · 설명 줄바꿈 경계 · 설명 색 · 대비 ──
        const rules = [
          ('조출 인정 범위', '정시 N분 전까지는 정시 처리, 넘겨서 도착하면 조출 인정'),
          ('조출 반올림 단위', '조출 시간을 N분 단위로 내림 처리'),
          ('지각 유예 시간', '정시 후 N분 이내 도착은 지각 없이 정시 처리'),
          ('지각 반올림 단위', '지각 시간을 N분 단위로 올림 처리'),
          ('정시 퇴근 인정 범위', '퇴근 예정 후 N분 이내 퇴근도 정시로 처리'),
          ('연장 반올림 단위', '연장 근무 시간을 N분 단위로 내림 처리'),
          ('조퇴 반올림 단위', '조퇴 시간을 N분 단위로 올림 처리'),
        ];
        final first = rt((p) => p == rules.first.$1);
        must('규칙 첫 행 1', first.evaluate().length == 1, '개수 ${first.evaluate().length}');
        await t.ensureVisible(first);
        await settle(4);
        var found = 0;
        var labelOk = true;
        var descOk = true;
        var descLines = 0;
        var minCr = double.infinity;
        Color? descColor;
        var sameColor = true;
        for (final (label, desc) in rules) {
          final lf = rt((p) => p == label);
          final df = rt((p) => p == desc);
          if (lf.evaluate().length != 1 || df.evaluate().length != 1) continue;
          found++;
          if (!_breaks(t.renderObject(lf) as RenderParagraph).ok) labelOk = false;
          final dj = _breaks(t.renderObject(df) as RenderParagraph);
          if (!dj.ok) descOk = false;
          descLines += dj.lines;
          final c = (t.widget(df) as RichText).text.style?.color;
          if (descColor != null && c != descColor) sameColor = false;
          descColor = c;
          minCr = math.min(minCr, _cr(c, AppColors.surface));
        }
        _out('D448 $tok att rules found=$found labelOk=$labelOk descOk=$descOk descLines=$descLines color=${_tok(descColor)} same=$sameColor cr=${_f(minCr)}');
        await shot('1rules', 'rule-rows');

        // ── 비콘 카드 안내 ──
        final helpF = rt((p) => p == '사업장에 설치된 iBeacon/Eddystone 기기 정보를 입력하세요.');
        must('비콘 안내 1', helpF.evaluate().length == 1, '개수 ${helpF.evaluate().length}');
        await t.ensureVisible(helpF);
        await settle(4);
        final hj = _breaks(t.renderObject(helpF) as RenderParagraph);
        final hColor = (t.widget(helpF) as RichText).text.style?.color;
        final hCr = _cr(hColor, AppColors.surface);
        _out('D448 $tok att help lines=${hj.lines} ok=${hj.ok} color=${_tok(hColor)} cr=${_f(hCr)}');
        await shot('2help', 'beacon-help');

        must('규칙 7행 찾음', found == 7, '찾음 $found');
        if (_before) {
          if (v.id == 'W') {
            // 음성 기대 — base W '… 조출 인 / 정' 음절 끊김(DU445 W 합성 관측) · 설명 grey500(코드).
            must('before W 음절 끊김 · grey500 검출', !descOk && descColor == AppColors.grey500 && hColor == AppColors.grey500,
                '경계 $descOk ${_tok(descColor)} ${_tok(hColor)}');
          }
        } else {
          must('strict 규칙 이름 · 설명 낱말 경계', labelOk && descOk, '이름 $labelOk 설명 $descOk');
          must('strict 설명 textTertiary · 대비 ≥ 4.5', sameColor && descColor == AppColors.textTertiary && minCr >= 4.5, '${_tok(descColor)} ${_f(minCr)}');
          must('strict 비콘 안내 낱말 경계 · textTertiary ≥ 4.5', hj.ok && hColor == AppColors.textTertiary && hCr >= 4.5, '${hj.ok} ${_tok(hColor)} ${_f(hCr)}');
          must('strict 넘침 0(3단계)', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D448 $tok done state=RULES mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
