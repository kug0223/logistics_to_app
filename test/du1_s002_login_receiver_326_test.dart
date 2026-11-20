// ignore_for_file: depend_on_referenced_packages
// [DU326] S002 로그인 receiver 48 × 48 + LG-2 한 화면(소급 3 인계 §3 S002) — 측정 · 캡처.
//   조건: LG-2 일곱(392x851 1.0/1.3/2.0 · 320x693 1.3/1.0 · 360x640 1.0/1.3) + 320x640 2.0(참고, LG-2 밖).
//   receiver: '아이디 저장'(체크 + 글자) · '아이디 찾기' · '비밀번호 찾기' · '회원가입' — 실제 누를 수 있는 상자(hit 대상)의 크기 · 서로 겹침 없음.
//   단언(기본 실행 = 현재 제품 정답): LG-2 조건 스크롤 0 · receiver ≥ 48×48 · 겹침 0. DU_BEFORE_OBSERVE=326 이면 receiver · 겹침만 기록.
//   캡처(VQ 켬일 때만): 392x851 1.0 정상 · 아이디 칸 초점(입력 안내 보임) · 아이디 찾기 시트.
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/login_screen.dart';
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

final bool _beforeObs = Platform.environment['DU_BEFORE_OBSERVE'] == '326';

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const conds = [
    (id: 'LG2-392x851-1.0', w: 392.0, h: 851.0, s: 1.0, lg2: true, shot: true),
    (id: 'LG2-392x851-1.3', w: 392.0, h: 851.0, s: 1.3, lg2: true, shot: false),
    (id: 'LG2-392x851-2.0', w: 392.0, h: 851.0, s: 2.0, lg2: true, shot: true),
    (id: 'LG2-320x693-1.3', w: 320.0, h: 693.0, s: 1.3, lg2: true, shot: false),
    (id: 'LG2-320x693-1.0', w: 320.0, h: 693.0, s: 1.0, lg2: true, shot: false),
    (id: 'LG2-360x640-1.0', w: 360.0, h: 640.0, s: 1.0, lg2: true, shot: false),
    (id: 'LG2-360x640-1.3', w: 360.0, h: 640.0, s: 1.3, lg2: true, shot: true),
    (id: 'REF-320x640-2.0', w: 320.0, h: 640.0, s: 2.0, lg2: false, shot: true),
  ];

  for (final c in conds) {
    testWidgets('${c.id} 로그인 receiver · 한 화면', (t) async {
      if (c.shot) await t.runAsync(vqLoadFonts);
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      t.view.padding = const FakeViewPadding(top: 30, bottom: 24);
      t.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
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

      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => UserProvider(),
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.getThemeByRole(null),
            builder: (ctx, child) =>
                MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: const LoginScreen(),
          ),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      // 참고 조건(320x640 2.0)은 before 에서 찾기 묶음 Row 가 57px 넘쳤다(TB 실측) — 옛 결함 관측 대상. LG-2 조건은 늘 단언.
      final ex = t.takeException();
      if (c.lg2) {
        expect(ex, isNull);
      } else {
        known(ex == null, '${c.id} 넘침 · 예외 없음(실측 $ex)');
      }
      final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
      out('${c.id} maxScroll=${pos.maxScrollExtent.toStringAsFixed(1)}');
      if (c.lg2) expect(pos.maxScrollExtent, 0, reason: '${c.id} LG-2 한 화면 스크롤 0');

      // receiver: 글자에서 가장 가까운 '누르는' 조상(InkWell · ButtonStyleButton · GestureDetector · Checkbox 포함 Row)
      Rect receiverOf(String label) {
        final txt = findVisibleText(label);
        expect(txt, findsWidgets, reason: label);
        final anc = find.ancestor(
            of: txt.first,
            matching: find.byWidgetPredicate((w) => w is InkWell || w is ButtonStyleButton || w is GestureDetector));
        return t.getRect(anc.first);
      }

      bool hits(Rect r) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, r.center, t.view.viewId);
        return hit.path.isNotEmpty;
      }

      final rs = <String, Rect>{
        for (final l in const ['아이디 저장', '아이디 찾기', '비밀번호 찾기', '회원가입']) l: receiverOf(l),
      };
      // 체크박스 자체 상자(아이디 저장 묶음의 다른 receiver)
      final cb = find.byType(Checkbox);
      final cbRect = cb.evaluate().isEmpty ? null : t.getRect(cb.first);
      out('${c.id} checkbox=${cbRect?.toString()}');
      for (final e in rs.entries) {
        final r = e.value;
        out('${c.id} receiver "${e.key}" rect=$r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} hit=${hits(r)}');
        known(r.width >= 48 - 1e-6 && r.height >= 48 - 1e-6, '${c.id} ${e.key} receiver ≥ 48×48(실측 ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)})');
      }
      final keys = rs.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        for (var j = i + 1; j < keys.length; j++) {
          final ov = rs[keys[i]]!.intersect(rs[keys[j]]!);
          final overlap = ov.width > 0.5 && ov.height > 0.5;
          known(!overlap, '${c.id} ${keys[i]} ↔ ${keys[j]} 겹침 없음');
        }
      }
      final btn = find.widgetWithText(ElevatedButton, '로그인');
      out('${c.id} loginBtn=${t.getRect(btn)} signupBottom=${rs['회원가입']!.bottom.toStringAsFixed(1)} limit=${(c.h - 24).toStringAsFixed(1)}');
      if (c.lg2) expect(rs['회원가입']!.bottom, lessThanOrEqualTo(c.h - 24 + 0.01), reason: '${c.id} 회원가입이 화면 아래로 잘림');

      if (c.shot) {
        await vqCapture(t, key, '${c.id}_1_normal', conditions: {'state': '초기 · 입력 비어 있음', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s, 'beforeObserve': _beforeObs});
        if (c.id == 'LG2-392x851-1.0') {
          // 아이디 칸 초점 → 입력 안내 보임
          await t.tap(find.byType(TextFormField).first);
          for (var i = 0; i < 6; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          expect(findVisibleText('아이디를 입력하세요'), findsWidgets, reason: '초점 입력 안내');
          await vqCapture(t, key, '${c.id}_2_focus_hint', conditions: {'state': '아이디 칸 초점 · 입력 안내', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
          FocusManager.instance.primaryFocus?.unfocus();
          await t.pump(const Duration(milliseconds: 200));
          // 아이디 찾기 시트
          await t.tap(findVisibleText('아이디 찾기').first);
          for (var i = 0; i < 10; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          out('${c.id} sheet=${find.byType(BottomSheet).evaluate().length} exc=${t.takeException()}');
          await vqCapture(t, key, '${c.id}_3_find_id_sheet', conditions: {'state': '아이디 찾기 시트', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaler': c.s});
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
    });
  }

  // [DU332] hit 증거 보완(소급 4 인계 §3) — 네 receiver 의 실제 target 일치(중심 · 늘어난 영역 좌/우 안쪽 2px) ·
  //   '아이디 저장' 체크 · 글자 · 확장부 각 탭 1회 토글 · REF 는 스크롤 뒤 회원가입 도달. 8조건 전체 사슬은 반복하지 않는다.
  for (final h in const [(id: 'HIT-392x851-1.0', w: 392.0, h: 851.0, s: 1.0), (id: 'HIT-REF-320x640-2.0', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${h.id} receiver 실제 hit 대상 · 저장 토글', (t) async {
      SharedPreferences.setMockInitialValues({});
      t.view.physicalSize = Size(h.w, h.h);
      t.view.devicePixelRatio = 1.0;
      t.view.padding = const FakeViewPadding(top: 30, bottom: 24);
      t.view.viewPadding = const FakeViewPadding(top: 30, bottom: 24);
      addTearDown(t.view.reset);
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => UserProvider(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.getThemeByRole(null),
          builder: (ctx, child) =>
              MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(h.s)), child: child!),
          home: const LoginScreen(),
        ),
      ));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(t.takeException(), isNull);
      void out(String l) {
        // ignore: avoid_print
        print(l);
      }

      Finder recv(String label) => find
          .ancestor(of: findVisibleText(label).first, matching: find.byWidgetPredicate((w) => w is InkWell || w is ButtonStyleButton))
          .first;
      bool targets(Finder f, Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        final ro = t.renderObject(f);
        return hit.path.any((e) => identical(e.target, ro));
      }

      Future<void> reach(String label) async {
        final r = t.getRect(recv(label));
        if (r.bottom > h.h - 24 || r.top < 0) {
          await t.scrollUntilVisible(findVisibleText(label).first, 80, scrollable: find.byType(Scrollable).first, maxScrolls: 30);
          await t.pump(const Duration(milliseconds: 200));
        }
      }

      final rects = <String, Rect>{};
      for (final label in const ['아이디 저장', '아이디 찾기', '비밀번호 찾기', '회원가입']) {
        await reach(label);
        final f = recv(label);
        final r = t.getRect(f);
        rects[label] = r;
        final pts = <Offset>[r.center, Offset(r.left + 2, r.center.dy), Offset(r.right - 2, r.center.dy), Offset(r.center.dx, r.top + 2), Offset(r.center.dx, r.bottom - 2)];
        final ok = [for (final p in pts) targets(f, p)];
        out('${h.id} "$label" receiver=$r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} targets(center,L,R,T,B)=$ok');
        expect(r.top >= -0.5 && r.bottom <= h.h + 0.5, isTrue, reason: '${h.id} $label 화면 안(도달 뒤)');
        expect(ok.every((x) => x), isTrue, reason: '${h.id} $label 중심 · 늘어난 영역 모두 그 receiver 가 hit 대상');
      }
      // 서로 다른 행동 비겹침(같은 스크롤 위치에서 잰 것만 비교 — 회원가입은 REF 에서 스크롤 뒤라 위 세 개와 따로)
      for (final pair in const [('아이디 저장', '아이디 찾기'), ('아이디 저장', '비밀번호 찾기'), ('아이디 찾기', '비밀번호 찾기')]) {
        final ov = rects[pair.$1]!.intersect(rects[pair.$2]!);
        expect(ov.width > 0.5 && ov.height > 0.5, isFalse, reason: '${h.id} ${pair.$1} ↔ ${pair.$2} 겹침');
      }
      // '아이디 저장' — 체크 · 글자 · 확장부 각 탭이 상태를 한 번씩 바꾼다
      await t.scrollUntilVisible(findVisibleText('아이디 저장').first, -80, scrollable: find.byType(Scrollable).first, maxScrolls: 30);
      await t.pump(const Duration(milliseconds: 200));
      bool checked() => t.widget<Checkbox>(find.byType(Checkbox)).value ?? false;
      final save = t.getRect(recv('아이디 저장'));
      final cb = t.getRect(find.byType(Checkbox));
      final txt = t.getRect(findVisibleText('아이디 저장').first);
      final spots = <String, Offset>{
        '체크': cb.center,
        '글자': txt.center,
        '확장부(위)': Offset(txt.center.dx, save.top + 2),
        '확장부(아래)': Offset(txt.center.dx, save.bottom - 2),
      };
      var expect0 = checked();
      for (final e in spots.entries) {
        await t.tapAt(e.value);
        await t.pump(const Duration(milliseconds: 200));
        final now = checked();
        out('${h.id} 저장 탭 ${e.key} @${e.value} $expect0 → $now');
        expect(now, !expect0, reason: '${h.id} 저장 ${e.key} 탭은 한 번 토글');
        expect0 = now;
      }
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }
}
