// ignore_for_file: depend_on_referenced_packages
// [DU1-B2 · followup_5 §3] 근로자 급여 명세(screens/user/wage_detail_screen) '급여 내역' 통상시급 배지 —
//   실제 320×640 viewport 에서 2.0 · 스크롤로 배지에 닿아 **배지 전체**가 화면 안·잘림 없음·넘침 0.
//   (D2 사진은 배지가 viewport 밖이었다.) 관리자 wage_detail_dialog 와 다른 표면이다.
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/screens/user/wage_detail_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/wage_calculator.dart';

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

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR');
    final f = File('assets/fonts/NotoSansKR-Regular.ttf');
    if (f.existsSync()) {
      final loader = FontLoader('NotoSansKR')..addFont(f.readAsBytes().then((b) => ByteData.view(b.buffer)));
      await loader.load();
    }
  });

  for (final c in const [(Size(320, 640), 2.0), (Size(392, 844), 1.0)]) {
    testWidgets('통상시급 배지 ${c.$1.width.toInt()}×${c.$1.height.toInt()}@${c.$2} — 스크롤로 닿아 전체가 화면 안', (t) async {
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
      t.view.physicalSize = c.$1;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MaterialApp(
        theme: RoleTheme.workerTheme,
        builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.$2)), child: child!),
        home: WageDetailScreen(application: _app(), attendance: _att()),
      ));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      final badge = findVisibleTextContaining('통상시급');
      expect(badge, findsOneWidget);
      // 첫 화면 밖이면 실제 스크롤로 닿는다
      await t.scrollUntilVisible(badge, 120, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
      for (var i = 0; i < 4; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      final r = t.getRect(badge);
      expect(r.left, greaterThanOrEqualTo(0));
      expect(r.right, lessThanOrEqualTo(c.$1.width), reason: '배지 글자 전체가 화면 폭 안');
      expect(r.top, greaterThanOrEqualTo(0));
      expect(r.bottom, lessThanOrEqualTo(c.$1.height), reason: '세로 viewport 안');
      // [DU1 followup_6 §1] 글자만이 아니라 padding·아이콘을 포함한 **배지 Container 외곽**이 스크롤 viewport 안에 온전히.
      final box = find.ancestor(
          of: badge,
          matching: find.byWidgetPredicate((w) =>
              w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color == AppColors.grey100)).first;
      final icon = find.descendant(of: box, matching: find.byIcon(Icons.schedule_outlined));
      expect(icon, findsOneWidget, reason: '배지 안 아이콘');
      final vp = t.getRect(find.byType(Scrollable).first);
      final br = t.getRect(box);
      // ignore: avoid_print
      print('BADGE ${c.$1.width.toInt()}x${c.$1.height.toInt()}@${c.$2}: box=$br viewport=$vp');
      expect(br.left, greaterThanOrEqualTo(vp.left - 0.5));
      expect(br.right, lessThanOrEqualTo(vp.right + 0.5), reason: '배지 외곽 오른쪽이 viewport 안');
      expect(br.top, greaterThanOrEqualTo(vp.top - 0.5));
      expect(br.bottom, lessThanOrEqualTo(vp.bottom + 0.5), reason: '배지 외곽 아래가 viewport 안');
      expect(t.getRect(icon).left, greaterThanOrEqualTo(br.left));
      final para = t.renderObject<RenderParagraph>(badge);
      expect(para.didExceedMaxLines, isFalse);
      expect(visibleText(para.text.toPlainText()), contains('12,000'), reason: '금액까지 그려진다');
      expect(findVisibleText('급여 내역'), findsOneWidget);
      expect(overflows, isEmpty, reason: overflows.join(' | '));
    });
  }
}
