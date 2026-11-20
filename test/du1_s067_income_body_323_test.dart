// ignore_for_file: depend_on_referenced_packages
// [DU323] S067 수입 상세 본체 — 빈 달(지원 · 근태 0) 첫 화면 렌더 관측(11-15 자체검토 셀).
//   하네스는 du1_o104_income_month_picker_292_test 와 같다(가짜 Firebase · 사용자 대역 · IncomeDetailReads 빈 주입 · ko_KR).
//   Register 잔여 '화면 본체 큰 글자 연월 칩 두 줄'을 본다. 시트는 열지 않는다.
//   기록: 문단별 줄 · 피할 수 있는 음절 끊김 · 넘침. 단언(현재 제품 정답, 기본 실행): 화면이 그려짐 · 연월 칩 보임.
//   연월 칩 안 음절 끊김 0 은 단언(DU_BEFORE_OBSERVE=323 이면 기록). 칩 두 줄(낱말 경계)은 허용.
//   공용 SectionHeader 제목 끊김은 공용 부품 결정 전이라 CANDIDATE 로 기록만 한다(기본 실행을 빨갛게 만들지 않는다).
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/income_detail_reads.dart';
import 'package:ALfit/screens/user/income_detail_screen.dart';
import 'package:ALfit/theme/role_theme.dart';

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

class _UserDouble extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '테스트하나',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시', district: '마산리'),
        accountStatus: 'active',
        passVerifiedAt: DateTime.now().subtract(const Duration(days: 30)),
      );
  @override
  bool get isUser => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
}

IncomeDetailReads _emptyReads() => IncomeDetailReads(
      myApplications: (uid) async => const <ApplicationModel>[],
      myMonthlyAttendances: ({required String userId, required int year, required int month}) async => const <AttendanceModel>[],
    );

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '323';

({List<String> lines, List<String> avoidable}) _lines(RenderParagraph rp) {
  final plain = rp.text.toPlainText();
  final lines = <StringBuffer>[];
  final avoidable = <String>[];
  final ws = RegExp(r'[\s ]');
  double? lastTop;
  var lastIdx = -1;
  for (var i = 0; i < plain.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final top = bx.first.top;
    if (lastTop == null || top > lastTop + 1) {
      if (lastTop != null && !ws.hasMatch(plain.substring(lastIdx, i + 1)) && ws.hasMatch(lines.last.toString().trim())) {
        avoidable.add('${visibleText(lines.last.toString())}|${visibleText(plain.substring(i, (i + 3).clamp(0, plain.length)))}');
      }
      lines.add(StringBuffer());
      lastTop = top;
    }
    lines.last.write(plain[i]);
    lastIdx = i;
  }
  return (lines: [for (final b in lines) visibleText(b.toString())], avoidable: avoidable);
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    SharedPreferences.setMockInitialValues({});
    await initializeDateFormatting('ko_KR', null);
  });

  for (final c in const [(id: 'S067-A', w: 392.0, h: 844.0, s: 1.0), (id: 'S067-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 수입 상세 빈 달 ${c.w.toInt()}×${c.h.toInt()}@${c.s}', (t) async {
      await t.runAsync(vqLoadFonts);
      t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
      t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
      addTearDown(t.platformDispatcher.clearLocaleTestValue);
      addTearDown(t.platformDispatcher.clearLocalesTestValue);
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

        void known(bool ok, String what) {
          out('KNOWN ${ok ? 'ok' : 'NG'} $what beforeObs=$_beforeObs');
          if (!_beforeObs) expect(ok, isTrue, reason: what);
        }

        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>.value(value: _UserDouble()),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.workerTheme,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ko', 'KR')],
              builder: (ctx, child) =>
                  MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
              home: Scaffold(body: IncomeDetailScreen(initialYear: 2026, initialMonth: 10, reads: _emptyReads())),
            ),
          ),
        ));
        for (var i = 0; i < 20; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        final chip = findVisibleText('2026년 10월');
        expect(chip, findsWidgets, reason: '연월 칩');
        out('${c.id} overflows=${overflows.length} $overflows');
        var avoidTotal = 0;
        List<String> chipLines = const [];
        List<String> chipAvoid = const [];
        for (final e in find.descendant(of: find.byType(IncomeDetailScreen), matching: find.byType(RichText)).evaluate()) {
          final rp = e.renderObject! as RenderParagraph;
          final s = visibleText(rp.text.toPlainText());
          if (s.length < 2) continue;
          final l = _lines(rp);
          final rect = t.getRect(find.byElementPredicate((x) => identical(x, e)));
          if (rect.bottom < 0 || rect.top > c.h) continue;
          if (s == '2026년 10월') {
            chipLines = l.lines;
            chipAvoid = l.avoidable;
          }
          avoidTotal += l.avoidable.length;
          out('${c.id} text "$s" rect=$rect lines=${l.lines} avoidable=${l.avoidable} color=${rp.text.style?.color} size=${rp.text.style?.fontSize}');
        }
        out('${c.id} chipLines=$chipLines avoidTotal=$avoidTotal');
        expect(overflows, isEmpty, reason: '${c.id} 넘침');
        // 연월 칩: 두 줄이어도 낱말 경계면 허용(글자를 줄이지 않는다) — 칩 안 음절 끊김 0 만 단언.
        known(chipAvoid.isEmpty, '${c.id} 연월 칩 음절 끊김 0(실측 줄 $chipLines)');
        // [DU330] 섹션 제목 keepWords 채택(소급 4) — 화면 전체 피할 수 있는 음절 끊김 0 을 기본 엄격으로 단언한다.
        //   (이전 주석의 '13파일 60곳'은 틀렸다 — 실제 소비는 income_detail_screen 한 곳, 보완기록 4)
        known(avoidTotal == 0, '${c.id} 화면 전체 피할 수 있는 음절 끊김 0(실측 $avoidTotal)');
        await vqCapture(t, key, '${c.id}_empty_month', conditions: {
          'entry': 'IncomeDetailScreen(initialYear 2026, initialMonth 10, reads: 빈 지원 · 빈 근태)',
          'theme': 'RoleTheme.workerTheme', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
          'locale': 'ko_KR', 'fonts': 'vqLoadFonts', 'beforeObserve': _beforeObs});
        await t.pumpWidget(const SizedBox.shrink());
      } finally {
        FlutterError.onError = prev;
      }
    });
  }
}
