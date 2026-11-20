// ignore_for_file: depend_on_referenced_packages
// [DU340] S083 근로자 급여 명세 — 짧은 업무명만 조건부로 한 덩어리(소급 감사 6 §3 채택).
//   실제 문단 가용 폭에 업무명 전체가 한 줄로 들어가면 업무명 안에서 줄을 바꾸지 않고(`· QA / 분류` 해소),
//   길면 지금처럼 낱말 단위(phrases). 빈 업무명은 구분점 없이 사업장만. 원문 semantics 보존.
//   사례: W 392x844 1.0 / B 320x640 2.0 × {짧음 'QA 분류', 김 '냉동창고 상하차 및 피킹 검수 보조 작업', 빈 ''}.
//   단언(기본): 예외 0 · 넘침 0 · 낭독 이름 = 원문 · 공용 판정기 avoidable 0 · 짧은 업무명은 한 줄(모든 글자 같은 줄) ·
//   빈 업무명은 구분점 없음. DU_BEFORE_OBSERVE=340 이면 '짧은 업무명 한 줄'은 KNOWN 으로 기록만 한다.
import 'dart:io';

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
import 'support/du_word_break.dart';
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

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '340';
const _biz = '[QA] 아주 긴 이름의 골든패스 테스트 물류센터 사업장';

DateTime _kst(int d, [int h = 0]) => DateTime.utc(2026, 10, d, h).subtract(const Duration(hours: 9));

ApplicationModel _app(String wt) => ApplicationModel(
    id: 'a1', businessId: 'b1', businessName: _biz, toTitle: 'QA',
    workDate: _kst(17), startTime: '09:00', endTime: '18:00', uid: 'u1', selectedWorkType: wt,
    wage: 12000, wageType: 'hourly', status: 'CONFIRMED', appliedAt: _kst(1));

AttendanceModel _att(String wt) => AttendanceModel(
    id: 'a1_att', applicationId: 'a1', userId: 'u1', businessId: 'b1', businessName: _biz,
    workDate: _kst(17), workType: wt, status: AttendanceModel.statusPresent,
    wageStatus: AttendanceModel.wageConfirmed, adminConfirmed: true, finalWage: 96000,
    checkInAt: _kst(17, 9), checkOutAt: _kst(17, 18), createdAt: _kst(17),
    wageDetail: WageCalculator.calculate(
        wageType: 'hourly', baseWage: 12000, workDate: _kst(17), scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60));

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
  });

  const views = [(id: 'W', w: 392.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const kinds = [(k: 'short', wt: 'QA 분류'), (k: 'long', wt: '냉동창고 상하차 및 피킹 검수 보조 작업'), (k: 'empty', wt: '')];
  for (final v in views) {
    for (final kd in kinds) {
      final id = 'S083U-${v.id}-${kd.k}';
      testWidgets('$id 업무명 ${kd.k} ${v.w.toInt()}x${v.h.toInt()}@${v.s}', (t) async {
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
          t.view.physicalSize = Size(v.w, v.h);
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
                  MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: WageDetailScreen(application: _app(kd.wt), attendance: _att(kd.wt)),
            ),
          ));
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          expect(t.takeException(), isNull);
          final full = kd.wt.isEmpty ? _biz : '$_biz · ${kd.wt}';
          final f = findVisibleText(full);
          expect(f, findsOneWidget, reason: '$id 사업장 · 업무 줄(보이는 글자 = 원문)');
          final txt = t.widget<Text>(f);
          final sem = txt.semanticsLabel ?? txt.data;
          expect(sem, full, reason: '$id 낭독 이름 = 원문');
          final rp = t.renderObject<RenderParagraph>(find.descendant(of: f, matching: find.byType(RichText)));
          final breaks = wordBreaks(rp);
          final avoid = breaks.where((b) => !b.forced).toList();
          // 업무명 글자들이 한 줄에 있는가(짧은 업무명 사례)
          var oneLine = true;
          String lineInfo = '';
          if (kd.wt.isNotEmpty) {
            final plain = rp.text.toPlainText();
            final tops = <double>{};
            // 표시 문자열에서 업무명 글자 위치: 끝에서부터 업무명 보이는 글자 수만큼(표시 제어 문자 건너뜀)
            var need = kd.wt.replaceAll(' ', '').length;
            for (var i = plain.length - 1; i >= 0 && need > 0; i--) {
              final ch = plain[i];
              if (ch == '⁠' || ch == '​' || ch == ' ' || ch == ' ') continue;
              final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
              if (bx.isNotEmpty) tops.add(bx.first.top.roundToDouble());
              need--;
            }
            oneLine = tops.length == 1;
            lineInfo = 'wtLines=${tops.length}';
          }
          final sepShown = visibleText(rp.text.toPlainText()).contains('·');
          out('$id avoidable=${avoid.length} $avoid forced=${breaks.where((b) => b.forced).length} $lineInfo sep=$sepShown semOk=${sem == full}');
          await vqCapture(t, key, '${id}_top', conditions: {'workType': kd.wt, 'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s});
          expect(overflows, isEmpty, reason: '$id 넘침');
          expect(avoid, isEmpty, reason: '$id 피할 수 있는 끊김');
          if (kd.wt.isEmpty) expect(sepShown, isFalse, reason: '$id 빈 업무명은 구분점 없음');
          if (kd.k == 'short') {
            out('KNOWN ${oneLine ? 'ok' : 'NG'} $id 짧은 업무명 한 줄($lineInfo)');
            if (!_beforeObs) expect(oneLine, isTrue, reason: '$id 짧은 업무명은 한 줄');
          }
          await t.pumpWidget(const SizedBox.shrink());
        } finally {
          FlutterError.onError = prev;
        }
      });
    }
  }
}
