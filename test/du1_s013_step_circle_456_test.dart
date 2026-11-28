// ignore_for_file: depend_on_referenced_packages
// [DU456 r4 · 후속117] 후보 b5db2309(painter maxLines 1 삭제만) · 독립 측정(pCtx 제품 context painter · pRp 숫자 문단 painter · 줄 상자 네 변/중심) 추가 — 기존 strict 그대로.
// [DU456 · 자체 판정 셀 · 표시만] DU-S013 사업장 수정 단계 표시 — 숫자 원 지름을 숫자 줄 높이에 맞춘다(B '3' 원 밖 · W 28 그대로).
//   before = 현재 A(business_form_screen c9ae7e82 · DU455 후보) / strict = 후보(5f6f98a1). harness 는 DU455 시험(e3b75902)과 같고 측정만 바꿨다.
//   harness 는 business_form_responsive_render_test(BF-R-01)와 같다(수정 모드 · 좌표 있는 사업장 · '다음' 2번).
//   출근 방식을 'both' 로 두어 GPS · 비콘 카드가 함께 그려진다(기존 시험은 'gps' 라 비콘 카드를 그린 적이 없다).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du456-tb/DU_BEFORE_OBSERVE=456 · TA after/du456-ta/없음.
import 'dart:convert';
import 'dart:io';

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
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '456';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du456-tb' && _env['DU_BEFORE_OBSERVE'] == '456') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du456-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S013SC-${v.id}-STEPS 사업장 수정 단계 표시 — 숫자 원 안 · 지름 숫자 줄 높이', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S013SC-${v.id}-STEPS';
        final mode = _before ? 'before' : 'strict';
        _out('D456 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        _out('D456 $tok att prior overflows=${overflows.length}');
        overflows.clear();

        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D456 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'STEPS',
            'state': state,
          });
          shots++;
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);

        // ── 단계 표시(값은 즉시) — 원 3개 지름 · 현재 숫자 '3'이 원 안에 있는가 ──
        // 단계 원 = 모양이 원(BoxShape.circle)인 AnimatedContainer — 출근 방식 칩도 AnimatedContainer(둥근 사각형)라 진단 1 에서 6개로 잡혔다.
        final circles = find
            .byWidgetPredicate((w) => w is AnimatedContainer && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).shape == BoxShape.circle,
                skipOffstage: false)
            .evaluate()
            .toList();
        final digitEls = rt((p) => p == '3').evaluate().where((e) {
          var inCircle = false;
          e.visitAncestorElements((a) {
            if (a.widget is AnimatedContainer) {
              inCircle = true;
              return false;
            }
            return true;
          });
          return inCircle;
        }).toList();
        var circleW = <double>[];
        var inside = false;
        var digitH = 0.0;
        var pad = -1.0;
        var dy = -1.0;
        var padX = -1.0;
        // [DU456 r4 · 후속117] 독립 측정 — pH(= 원 − 6 파생값)는 기록만. 아래 값들은 각각 따로 잰다.
        //   pCtx  : 제품과 같은 계산(숫자 13 굵게 · DefaultTextStyle 병합 · 방향 · 배율 · locale)을 제품이 쓰는 context 에서 재현한 painter 높이
        //           (strict = 후보의 Builder context · before = State context — base 는 painter 가 없어 기록만).
        //   pRp   : 숫자 RenderParagraph 자신의 글(text · 방향 · 배율 · locale · strut)로 만든 painter 높이.
        //   lineH : 숫자 RenderParagraph 의 실제 줄 상자(getBoxesForSelection) 높이. padT/B/L/R · dx/dy0 = 줄 상자 대 원 네 변 여유 · 중심 어긋남.
        var pCtx = -1.0, pRp = -1.0, lineH = -1.0, padT = -1.0, padB = -1.0, padL = -1.0, padR = -1.0, dx0 = -1.0, dy0 = -1.0;
        if (digitEls.length == 1) {
          final de = digitEls.single;
          final dR = t.getRect(find.byElementPredicate((x) => identical(x, de), skipOffstage: false));
          final rp = de.renderObject! as RenderParagraph;
          // 상자는 원 안으로 제한된다(TB STOP) — 글자에 필요한 높이로 잰다.
          digitH = rp.getMaxIntrinsicHeight(double.infinity);
          final tpRp = TextPainter(
            text: rp.text,
            textDirection: rp.textDirection,
            textScaler: rp.textScaler,
            locale: rp.locale,
            strutStyle: rp.strutStyle,
            textHeightBehavior: rp.textHeightBehavior,
          )..layout();
          pRp = tpRp.height;
          tpRp.dispose();
          Element? owner;
          de.visitAncestorElements((a) {
            if (a.widget is AnimatedContainer) {
              owner = a;
              return false;
            }
            return true;
          });
          final o = owner;
          if (o != null) {
            final cR = t.getRect(find.byElementPredicate((x) => identical(x, o), skipOffstage: false));
            inside = digitH <= cR.height + 0.5 && dR.left >= cR.left - 0.5 && dR.right <= cR.right + 0.5;
            pad = (cR.height - digitH) / 2;
            dy = (dR.center.dy - cR.center.dy).abs();
            padX = (cR.width - dR.width) / 2;
            final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: rp.text.toPlainText().length));
            if (boxes.isNotEmpty) {
              final lb = boxes.first.toRect();
              final tl = rp.localToGlobal(lb.topLeft), br = rp.localToGlobal(lb.bottomRight);
              final line = Rect.fromPoints(tl, br);
              lineH = line.height;
              padT = line.top - cR.top;
              padB = cR.bottom - line.bottom;
              padL = line.left - cR.left;
              padR = cR.right - line.right;
              dx0 = (line.center.dx - cR.center.dx).abs();
              dy0 = (line.center.dy - cR.center.dy).abs();
            }
            // 제품이 쓰는 context — strict 는 원의 가장 가까운 Builder(후보가 넣은 것), before 는 BusinessFormScreen State.
            Element? mctx;
            if (_before) {
              mctx = find.byType(BusinessFormScreen, skipOffstage: false).evaluate().first;
            } else {
              o.visitAncestorElements((a) {
                if (a.widget.runtimeType == Builder) {
                  mctx = a;
                  return false;
                }
                return true;
              });
            }
            final mc = mctx;
            if (mc != null) {
              const digitStyle = TextStyle(fontWeight: FontWeight.bold, fontSize: 13);
              final tpC = TextPainter(
                text: TextSpan(text: '3', style: DefaultTextStyle.of(mc).style.merge(digitStyle)),
                textDirection: Directionality.of(mc),
                textScaler: MediaQuery.textScalerOf(mc),
                locale: Localizations.maybeLocaleOf(mc),
              )..layout();
              pCtx = tpC.height;
              tpC.dispose();
            }
          }
        }
        circleW = [for (final c in circles) t.getRect(find.byElementPredicate((x) => identical(x, c), skipOffstage: false)).width];
        final same = circleW.isNotEmpty && circleW.every((w) => (w - circleW.first).abs() <= 0.01);
        _out('D456 $tok att step circles=${circles.length} digits=${digitEls.length} circleW=${_f(circleW.isEmpty ? -1 : circleW.first)} '
            'same=$same inside=$inside digitH=${_f(digitH)} pad=${_f(pad)} dy=${_f(dy)} padX=${_f(padX)} '
            'pH=${_f(circleW.isNotEmpty && circleW.first > 28.01 ? circleW.first - 6 : -1)}');
        _out('D456 $tok att measure pCtx=${_f(pCtx)} pRp=${_f(pRp)} lineH=${_f(lineH)} padT=${_f(padT)} padB=${_f(padB)} padL=${_f(padL)} padR=${_f(padR)} dx=${_f(dx0)} dy=${_f(dy0)}');
        await shot('1steps', 'step-indicator');

        must('단계 원 3 · 현재 숫자 1', circles.length == 3 && digitEls.length == 1, '원 ${circles.length} 숫자 ${digitEls.length}');
        if (_before) {
          if (v.id == 'B') {
            // 음성 기대 — base B 는 원 28 고정 · 숫자 줄 높이(26px 글) > 28 이라 원 밖으로 나간다(DU445/448/455 B 합성 '3' 잘림).
            must('before B 숫자 원 밖 검출', !inside, '안 $inside 숫자 높이 ${_f(digitH)}');
          }
        } else {
          final ok = v.id == 'B' ? circleW.first > 28.5 : (circleW.first - 28).abs() <= 0.01;
          must('strict 숫자 원 안 · 원 3개 같은 지름 · W 28 그대로 / B 커짐 · 위아래 여유 ≥ 2.5 · 가운데', inside && same && ok && pad >= 2.5 && dy <= 0.5 && padX >= 2.5,
              '안 $inside 같음 $same 지름 ${_f(circleW.first)} 여유 ${_f(pad)} 어긋남 ${_f(dy)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          // [r4] 독립 측정 — 줄 상자 네 변 여유 · 중심 · 원 지름 = max(28, 제품 context painter + 6)(pH 파생값을 쓰지 않는다).
          must('strict r4 줄 상자 네 변 여유 ≥ 2.5 · 중심 어긋남 ≤ 0.5 · 원 = max(28, pCtx + 6)',
              padT >= 2.5 && padB >= 2.5 && padL >= 2.5 && padR >= 2.5 && dx0 <= 0.5 && dy0 <= 0.5 &&
                  (circleW.first - (pCtx + 6 > 28 ? pCtx + 6 : 28.0)).abs() <= 0.01,
              'pad ${_f(padT)}/${_f(padB)}/${_f(padL)}/${_f(padR)} 중심 ${_f(dx0)}/${_f(dy0)} 원 ${_f(circleW.first)} pCtx ${_f(pCtx)}');
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D456 $tok done state=STEPS mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
