// ignore_for_file: depend_on_referenced_packages
// [DU1 C0 · followup_6 §2] 첫 묶음 실제 폼 LOCAL 렌더 — 기본가입(S004)·프로필(S044). 로그인(S002)은 기존
//   login_layout_text_scale_test LG-1~4(320@1.3·392@2.0·작은 높이·키보드 synthetic inset·오류 도달)를 재사용한다.
//   RG-1 가입 0단계(이용 방법) — 헤더·두 선택지·하단 '다음' 비활성(선택 전) · 넘침 0
//   RG-2 지원자 선택 → '다음' → 1단계(기본 정보) — 빈 제출 시 검증 오류가 보인다 · 넘침 0
//   (약관 읽기 상태: 지원자 약관은 2단계에 있고 이 시험은 그 단계에 진입하지 않는다(PASS 결과 필요) — 약관 상태 렌더는
//    du1_c0_register_terms_states_test(약관 읽기 교체 seam·약관 단계 표시 seam)가 맡는다)
//   PF-1a 프로필 320×640@2.0 — 헤더·주소 입력, dirty 후 하단 저장 버튼 · PF-1b synthetic 키보드 inset 300: 저장 버튼 외곽·입력 칸 키보드 위·hit-test(수정 후 해결 조건) · PF-1c 키보드 닫힘 시 여분 공백 없음
//   실제 docked IME 성공이 아니다(synthetic inset). 가입 writer·인증 호출 없음.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/register_screen.dart';
import 'package:ALfit/screens/common/profile_edit_screen.dart';
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

class _Worker extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'w1', username: 'qaworker_long_name', name: '아주긴이름의지원자홍길동', email: 'w1@test.local', role: UserRole.USER);
}

final _overflows = <String>[];

Future<void> _pump(WidgetTester t, Widget home,
    {required Size size, required double scale, UserProvider? up, double inset = 0, bool collect = true, GlobalKey? boundaryKey}) async {
  _overflows.clear();
  // collect=false: 프레임워크 기본 처리 — 넘침이 있으면 시험이 그대로 실패한다(프로필 시험)
  if (collect) {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final m = d.exceptionAsString();
    if (m.contains('overflowed')) {
      _overflows.add(m.split('\n').first);
    } else {
      prev?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = prev);
  }
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  final app = MaterialApp(
    debugShowCheckedModeBanner: boundaryKey == null, // [후속39 §3] 캡처 셀만 배너 없음(기존 PF 렌더는 그대로)
    theme: RoleTheme.workerTheme,
    builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(
            textScaler: TextScaler.linear(scale), viewInsets: EdgeInsets.only(bottom: inset)),
        child: child!),
    home: home,
  );
  await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
    create: (_) => up ?? UserProvider(),
    // [후속39 §3] 캡처 셀만 RepaintBoundary 로 감싼다 — 같은 MaterialApp·theme·MediaQuery(synthetic viewInsets) 경로
    child: boundaryKey == null ? app : RepaintBoundary(key: boundaryKey, child: app),
  ));
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

Finder _btn(String label) => find.byWidgetPredicate((w) =>
    w is ElevatedButton &&
    w.child is Text &&
    visibleText((w.child as Text).data ?? '') == label);

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  for (final c in const [(Size(320, 640), 2.0), (Size(392, 844), 1.0)]) {
    final tag = '${c.$1.width.toInt()}x${c.$1.height.toInt()}@${c.$2}';

    testWidgets('RG-1/2 가입 0→1단계 $tag — 헤더·선택지·다음 비활성→활성·검증 오류·넘침 0', (t) async {
      await _pump(t, const RegisterScreen(), size: c.$1, scale: c.$2);
      expect(findVisibleText('이용 방법 선택'), findsOneWidget);
      expect(findVisibleTextContaining('지원자로 이용'), findsWidgets);
      expect(findVisibleTextContaining('사업장 관리자로 이용'), findsWidgets);
      final next = _btn('다음');
      expect(next, findsOneWidget);
      expect(t.widget<ElevatedButton>(next).onPressed, isNull, reason: '이용 방법 선택 전에는 다음 비활성');
      final r0 = t.getRect(next);
      expect(r0.bottom, lessThanOrEqualTo(c.$1.height), reason: '하단 행동이 화면 안');
      expect(_overflows, isEmpty, reason: _overflows.join(' | '));

      await t.tap(findVisibleTextContaining('지원자로 이용').first);
      await t.pump(const Duration(milliseconds: 100));
      expect(t.widget<ElevatedButton>(next).onPressed, isNotNull, reason: '선택 후 다음 활성');
      await t.tap(next);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(findVisibleText('기본 정보 입력'), findsOneWidget);
      // 빈 상태로 다음 → 실제 검증 오류(아이디)가 그려진다
      await t.tap(_btn('다음'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      final err = findVisibleText('아이디를 입력해주세요');
      expect(err, findsOneWidget, reason: '검증 오류가 보인다');
      await t.ensureVisible(err);
      await t.pump();
      expect(t.getRect(err).right, lessThanOrEqualTo(c.$1.width));
      expect(_overflows, isEmpty, reason: _overflows.join(' | '));
    });
  }

  final detail = find.byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == '동/호수 입력');

  testWidgets('PF-1a 프로필 320×640@2.0 — 헤더·입력·dirty 저장 버튼(넘침 시 실패)', (t) async {
    await _pump(t, const ProfileEditScreen(), size: const Size(320, 640), scale: 2.0, up: _Worker(), collect: false);
    expect(findVisibleText('프로필 관리'), findsOneWidget);
    await t.scrollUntilVisible(detail, 150, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await t.enterText(detail, '101동 1001호 아주 긴 상세주소 입력 예시');
    await t.pump(const Duration(milliseconds: 100));
    final save = findVisibleText('변경사항 저장');
    expect(save, findsOneWidget, reason: 'dirty 후 하단 저장');
    expect(t.getRect(save).bottom, lessThanOrEqualTo(640));
  });

  testWidgets('PF-1b 프로필 320×640@2.0 + synthetic 키보드 inset 300 — 저장 버튼 외곽·입력 칸 모두 키보드 위, hit-test', (t) async {
    await _pump(t, const ProfileEditScreen(), size: const Size(320, 640), scale: 2.0, up: _Worker(), inset: 300, collect: false);
    await t.scrollUntilVisible(detail, 150, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await t.enterText(detail, '101동');
    await t.pump(const Duration(milliseconds: 100));
    // 라벨 Text 가 아니라 **ElevatedButton 외곽**으로 본다
    final btn = find.ancestor(of: findVisibleText('변경사항 저장'), matching: find.byType(ElevatedButton));
    expect(btn, findsOneWidget);
    final br = t.getRect(btn);
    await t.ensureVisible(detail);
    await t.pump();
    final fr = t.getRect(detail);
    // ignore: avoid_print
    print('PF-1b button=$br field=$fr');
    const kbTop = 640.0 - 300;
    expect(br.top, greaterThanOrEqualTo(0));
    expect(br.bottom, lessThanOrEqualTo(kbTop + 0.5), reason: '저장 버튼 외곽이 키보드 위');
    expect(fr.top, greaterThanOrEqualTo(0));
    expect(fr.bottom, lessThanOrEqualTo(br.top + 0.5), reason: '입력 칸이 키보드·저장 바에 가리지 않는다');
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, br.center, t.view.viewId);
    expect(hit.path.any((e) => e.target == t.renderObject(btn)), isTrue, reason: '저장 버튼 중앙이 실제로 눌리는 자리(누르지 않음 — writer 미호출)');
  });

  testWidgets('PF-1c 같은 화면 키보드 닫힘(inset 0) — 하단 바 아래 빈 공간 없음', (t) async {
    await _pump(t, const ProfileEditScreen(), size: const Size(320, 640), scale: 2.0, up: _Worker(), collect: false);
    await t.scrollUntilVisible(detail, 150, scrollable: find.byType(Scrollable).first, maxScrolls: 40);
    await t.enterText(detail, '101동');
    await t.pump(const Duration(milliseconds: 100));
    final btn = find.ancestor(of: findVisibleText('변경사항 저장'), matching: find.byType(ElevatedButton));
    final br = t.getRect(btn);
    // ignore: avoid_print
    print('PF-1c button=$br');
    expect(br.bottom, greaterThan(640 - 40), reason: '키보드가 없으면 바는 화면 아래에 붙는다(여분 inset 없음)');
    expect(br.bottom, lessThanOrEqualTo(640));
  });

  // ── [DU1 후속39 §3] B2-I — DU-S044 ProfileEditScreen 시각 셀. 기존 _Worker·_pump(workerTheme·DPR1·synthetic MediaQuery inset) 그대로,
  //   글꼴은 vqLoadFonts(NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons; FlutterTest 미등록), PNG 는 DU1_VQ_OUT 직접.
  //   뷰 물리 inset(t.view.padding/viewInsets)은 0, 키보드는 MediaQuery synthetic viewInsets 로만 준다(구별 기록).
  //   prefs·날짜/clock: 이 화면 셀 경로는 사용하지 않음(정적) — 기록만. 저장·사진·PASS·인증 writer 는 누르지 않는다.
  Map<String, Object?> b2iCond(WidgetTester t, Size size, double scale, double synthInset, String scroll, String input) => {
        'screen': 'ProfileEditScreen (production)', 'user': '_Worker(uid w1, username qaworker_long_name, name 아주긴이름의지원자홍길동)',
        'theme': 'RoleTheme.workerTheme', 'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'dpr': 1.0, 'textScaler': scale,
        'viewPhysicalInset': 'padding(${t.view.padding.top},${t.view.padding.bottom}) viewInsets(${t.view.viewInsets.bottom})',
        'syntheticMediaQueryViewInsetsBottom': synthInset,
        'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록 — 기기 글꼴 아님',
        'prefs': '미사용(이 셀 경로)', 'clock': '미주입(화면 셀 경로에 날짜 표시 없음)', 'input': input, 'scroll': scroll};

  testWidgets('B2-I-A 프로필 392×844@1.0 — 첫 화면 / 상세주소 dirty 후 같은 표시 위치 · 저장 외곽 · 넘침 0', (t) async {
    await t.runAsync(vqLoadFonts);
    const size = Size(392, 844);
    final key = GlobalKey();
    await _pump(t, const ProfileEditScreen(), size: size, scale: 1.0, up: _Worker(), collect: false, boundaryKey: key);
    final sc = find.byType(Scrollable).first;
    final pos = t.state<ScrollableState>(sc).position;
    expect(pos.pixels, 0);
    expect(findVisibleText('프로필 관리'), findsOneWidget);
    expect(t.takeException(), isNull);
    await vqCapture(t, key, 'B2-I-A_profile_392x1_top', conditions: b2iCond(t, size, 1.0, 0, 'none — offset 0', '없음'));
    await t.scrollUntilVisible(detail, 150, scrollable: sc, maxScrolls: 40);
    await t.enterText(detail, '101동 1001호');
    await t.pump(const Duration(milliseconds: 100));
    await t.ensureVisible(detail);
    await t.pump(const Duration(milliseconds: 100));
    final btn = find.ancestor(of: findVisibleText('변경사항 저장'), matching: find.byType(ElevatedButton));
    expect(btn, findsOneWidget, reason: 'dirty 후 저장');
    final br = t.getRect(btn);
    final fr = t.getRect(detail);
    // ignore: avoid_print
    print('B2-I-A dirty offset=${pos.pixels.toStringAsFixed(1)} viewport=${t.getRect(sc)} field=$fr saveButton=$br h=${br.height.toStringAsFixed(1)}');
    expect(br.bottom <= size.height && br.left >= 0 && br.right <= size.width, isTrue);
    expect(fr.bottom <= br.top + 0.5, isTrue, reason: '입력이 저장 바 위');
    expect(t.takeException(), isNull);
    await vqCapture(t, key, 'B2-I-A_profile_392x1_dirty', conditions: b2iCond(t, size, 1.0, 0,
        "scrollUntilVisible(상세주소)→enterText→ensureVisible — offset ${pos.pixels.toStringAsFixed(1)} field=$fr save=$br", '상세주소 "101동 1001호"'));
  });

  testWidgets('B2-I-B 프로필 320×640@2.0 + synthetic inset 300 — 입력 도달·입력은 저장 바 위·저장 외곽은 키보드 위·중앙 hit · 넘침 0', (t) async {
    await t.runAsync(vqLoadFonts);
    const size = Size(320, 640);
    final key = GlobalKey();
    await _pump(t, const ProfileEditScreen(), size: size, scale: 2.0, up: _Worker(), inset: 300, collect: false, boundaryKey: key);
    final sc = find.byType(Scrollable).first;
    final pos = t.state<ScrollableState>(sc).position;
    final before = pos.pixels;
    await t.scrollUntilVisible(detail, 150, scrollable: sc, maxScrolls: 40);
    // [후속39 r3] ensureVisible(top 정렬, PF-1b 하네스 선택)을 쓰지 않는다 — 실제 입력 시 포커스 showOnScreen 이 남기는 위치를 잰다
    await t.enterText(detail, '101동');
    for (var i = 0; i < 6; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    final vp = t.getRect(sc);
    final btn = find.ancestor(of: findVisibleText('변경사항 저장'), matching: find.byType(ElevatedButton));
    final br = t.getRect(btn);
    final fr = t.getRect(detail);
    final label = findVisibleText('상세주소');
    final lr = t.getRect(label);
    final labelVisible = lr.top >= vp.top - 0.5 && lr.bottom <= vp.bottom + 0.5;
    const kbTop = 640.0 - 300;
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, br.center, t.view.viewId);
    final hitOk = hit.path.any((e) => e.target == t.renderObject(btn));
    // ignore: avoid_print
    print('B2-I-B offset ${before.toStringAsFixed(1)}→${pos.pixels.toStringAsFixed(1)} viewport=$vp label=$lr labelVisible=$labelVisible field=$fr saveButton=$br h=${br.height.toStringAsFixed(1)} kbTop=$kbTop hit=$hitOk');
    // ensureVisible 은 입력 top 을 표시 영역 top 에 정확히 맞춘다(r1: 57.0 vs 57.0 부동소수 비교 실패) — 다른 비교와 같은 0.5 허용
    expect(fr.top >= vp.top - 0.5 && fr.bottom <= vp.bottom + 0.5, isTrue, reason: '입력 전체가 실제 목록 표시 영역 안 $fr / $vp');
    expect(fr.bottom <= br.top + 0.5, isTrue, reason: '입력은 저장 바 위');
    expect(br.top >= 0 && br.bottom <= kbTop + 0.5 && br.left >= 0 && br.right <= size.width, isTrue, reason: '저장 외곽이 키보드 위·가로 화면 안');
    expect(hitOk, isTrue);
    expect(t.takeException(), isNull);
    await vqCapture(t, key, 'B2-I-B_profile_320x2_kb300', conditions: b2iCond(t, size, 2.0, 300,
        'scrollUntilVisible(상세주소)→enterText(포커스 showOnScreen) — offset ${before.toStringAsFixed(1)}→${pos.pixels.toStringAsFixed(1)} viewport=$vp label=$lr(보임=$labelVisible) field=$fr save=$br', '상세주소 "101동"'));
  });
}
