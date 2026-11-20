// ignore_for_file: depend_on_referenced_packages
// [DU334] S083 근로자 급여 명세(WageDetailScreen) 렌더 관측 — 픽스처는 du1_worker_wage_badge_viewport_test 와 같다(확정 근무 1건).
//   W 392x844 1.0 / B 320x640 2.0, 위 · 가운데 · 끝 캡처. 문단별 피할 수 있는 음절 끊김과 흰 바탕 대비 < 4.5 글자를 기록한다.
//   단언(기본): 넘침 0 · 예외 0. 이 셀에서 고친 결함은 아래 KNOWN(기본 단언, DU_BEFORE_OBSERVE=334 이면 기록)으로 잇는다.
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/screens/user/wage_detail_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/wage_calculator.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

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

DateTime _kst(int d, [int h = 0]) => DateTime.utc(2026, 10, d, h).subtract(const Duration(hours: 9));

ApplicationModel _app() => ApplicationModel(
    id: 'a1', businessId: 'b1', businessName: '[QA] 아주 긴 이름의 골든패스 테스트 물류센터 사업장', toTitle: 'QA',
    workDate: _kst(17), startTime: '09:00', endTime: '18:00', uid: 'u1', selectedWorkType: 'QA 분류',
    wage: 12000, wageType: 'hourly', status: 'CONFIRMED', appliedAt: _kst(1));

AttendanceModel _att() => AttendanceModel(
    id: 'a1_att', applicationId: 'a1', userId: 'u1', businessId: 'b1', businessName: '[QA] 아주 긴 이름의 골든패스 테스트 물류센터 사업장',
    workDate: _kst(17), workType: 'QA 분류', status: AttendanceModel.statusPresent,
    wageStatus: AttendanceModel.wageConfirmed, adminConfirmed: true, finalWage: 96000,
    checkInAt: _kst(17, 9), checkOutAt: _kst(17, 18), createdAt: _kst(17),
    wageDetail: WageCalculator.calculate(
        wageType: 'hourly', baseWage: 12000, workDate: _kst(17), scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60));

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '334';

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a), y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

List<String> _avoidable(RenderParagraph rp) {
  final plain = rp.text.toPlainText();
  final ws = RegExp(r'[\s ]');
  final out = <String>[];
  double? lastTop;
  var lastIdx = -1;
  var line = StringBuffer();
  for (var i = 0; i < plain.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    if (lastTop == null || top > lastTop + 1) {
      if (lastTop != null && !ws.hasMatch(plain.substring(lastIdx, i + 1)) && ws.hasMatch(line.toString().trim())) {
        out.add('${visibleText(line.toString())}|${plain[i]}');
      }
      line = StringBuffer();
      lastTop = top;
    }
    line.write(plain[i]);
    lastIdx = i;
  }
  return out;
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  for (final c in const [(id: 'S083-W', w: 392.0, h: 844.0, s: 1.0), (id: 'S083-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 급여 명세 ${c.w.toInt()}x${c.h.toInt()}@${c.s}', (t) async {
      await t.runAsync(vqLoadFonts);
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          overflows.add(m.split('\n').first);
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);
      try {
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        final key = GlobalKey();
        void out(String l) {
          // ignore: avoid_print
          print(l);
        }

        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: WageDetailScreen(application: _app(), attendance: _att()),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        expect(overflows, isEmpty, reason: '${c.id} 넘침');
        var avoid = 0, low = 0;
        final seen = <String>{};
        void dump(String tag) {
          for (final e in find.byType(RichText).evaluate()) {
            final rp = e.renderObject! as RenderParagraph;
            final s = visibleText(rp.text.toPlainText());
            if (s.length < 2 || seen.contains(s)) continue;
            final r = t.getRect(find.byElementPredicate((x) => identical(x, e)));
            if (r.bottom < 0 || r.top > c.h) continue;
            seen.add(s);
            final av = _avoidable(rp);
            final col = rp.text.style?.color;
            final cst = col == null ? 99.0 : _contrast(col, Colors.white);
            if (av.isNotEmpty) avoid += av.length;
            if (cst < 4.5) low++;
            if (av.isNotEmpty || cst < 4.5) {
              out('$tag "$s" avoidable=$av color=$col contrastOnWhite=${cst.toStringAsFixed(2)} size=${rp.text.style?.fontSize}');
            }
          }
        }

        dump('${c.id}_top');
        await vqCapture(t, key, '${c.id}_1_top', conditions: {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
        final sc = find.byType(Scrollable).first;
        await t.drag(sc, Offset(0, -c.h * 0.6));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        dump('${c.id}_mid');
        await vqCapture(t, key, '${c.id}_2_mid', conditions: {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
        await t.drag(sc, Offset(0, -c.h * 3));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        dump('${c.id}_end');
        await vqCapture(t, key, '${c.id}_3_end', conditions: {'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
        expect(overflows, isEmpty, reason: '${c.id} 넘침(스크롤 뒤)');
        out('${c.id} summary avoidable=$avoid lowContrastTexts=$low beforeObs=$_beforeObs');
        // [DU334] 기본 실행 단언(현재 제품 정답) — 옛 결함('골 / 든패스')은 DU_BEFORE_OBSERVE=334 일 때만 기록
        out('KNOWN ${avoid == 0 ? 'ok' : 'NG'} ${c.id} 피할 수 있는 끊김 0(실측 $avoid)');
        if (!_beforeObs) expect(avoid, 0, reason: '${c.id} 피할 수 있는 끊김');
        expect(low, 0, reason: '${c.id} 흰 바탕 대비 4.5 미만 글자');
        await t.pumpWidget(const SizedBox.shrink());
      } finally {
        FlutterError.onError = prev;
      }
    });
  }
}
