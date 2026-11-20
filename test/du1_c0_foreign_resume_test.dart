// ignore_for_file: depend_on_referenced_packages
// [DU1 구현47 · 감사46/47 §4 다음 대표] C0 S001 ForeignRegisterScreen 복구 재입력 — LOCAL 직접 렌더(S005 경유 아님).
//   USER · isResume=true · 합성 기존 사진 경로. 기존 사진 재사용 실패 → 실제 '갤러리에서 선택' → 합성 OCR 실패/수동 입력 안내
//   → 빈 입력으로 '다음' → 로컬 검증 → 뒤로 → 재선택 → 고정 정상 OCR → 정보 확인 재진입에서 끝낸다(유효 입력 '다음'·finalize 미진입).
//   init 의 약관 자동 read(callableGetEffectiveLegalTerms)는 cloud_functions pigeon `call` 채널을 **명시적으로 차단**(오류 응답·호출 수 기록)한다.
//   ForeignRegisterHooks 로 사진 선택·OCR·업로드·사용자 읽기·finalize·mark 를 합성 — writer 계열 hook 은 호출 수만 센다(기대 0).
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/foreign_register_screen.dart';
import 'package:ALfit/services/foreign_id_ocr_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

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

const kExistingPath = 'id_cards/local-fr-resume/synthetic_existing.jpg';
// 고정 정상 OCR(합성) — 실제 OCR 아님
const kOcrOk = ForeignIdOcrResult(legalName: 'NGUYEN VAN AN', foreignIdRaw: '9001015123456', visaType: 'E-9',
    stayExpiryDate: '2028-12-31', legalNameFailed: false, foreignIdFailed: false, visaTypeFailed: false, stayExpiryFailed: false);

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  var functionsCalls = 0;
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    // 약관 자동 read 차단 — pigeon 오류 응답(code, message, details) → PlatformException → 화면의 약관 오류 상태(이번 흐름 밖)
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call', (_) async {
      functionsCalls++;
      return const StandardMessageCodec().encodeMessage(<Object?>['du47-blocked', 'functions 호출 차단(시험)', null]);
    });
  });
  tearDown(ForeignRegisterHooks.reset);

  for (final c in const [(id: 'C0-FR-R-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 외국인 가입 복구 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 재사용 실패→갤러리→OCR 실패·수동→빈 다음 검증→뒤로→재선택→정상 OCR 정보 확인', (t) async {
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
      functionsCalls = 0;
      var reuseCalls = 0, pickCalls = 0, uploadCalls = 0, readUserCalls = 0, finalizeCalls = 0, markCalls = 0;
      ForeignRegisterHooks.reuseOcr = (path) async {
        reuseCalls++;
        throw Exception('합성: 기존 사진 다운로드 실패');
      };
      ForeignRegisterHooks.pickAndOcr = () async {
        pickCalls++;
        return pickCalls == 1
            ? (path: '/local/synthetic_pick_1.jpg', result: null) // 사진은 골랐고 OCR 예외
            : (path: '/local/synthetic_pick_2.jpg', result: kOcrOk);
      };
      ForeignRegisterHooks.currentUid = () => 'u-local-fr-resume';
      ForeignRegisterHooks.upload = (a, b) async => uploadCalls++;
      ForeignRegisterHooks.readUser = (_) async {
        readUserCalls++;
        return <String, dynamic>{};
      };
      ForeignRegisterHooks.finalize = (a, b, c2, d, e) async {
        finalizeCalls++;
        return 'fp';
      };
      ForeignRegisterHooks.mark = (_) async => markCalls++;
      ForeignRegisterHooks.collectionEnabled = () => false;

      final size = Size(c.w, c.h);
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => UserProvider(),
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey, // ToastHelper 가 이 overlay 에 그린다
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: const ForeignRegisterScreen(role: UserRole.USER, isResume: true, existingIdCardPath: kExistingPath),
          ),
        ),
      ));
      await _settle(t, 12);
      void out(String l) {
        // ignore: avoid_print
        print(l);
      }
      String hooks() => 'reuse=$reuseCalls pick=$pickCalls upload=$uploadCalls readUser=$readUserCalls finalize=$finalizeCalls mark=$markCalls functions=$functionsCalls';
      final mq = MediaQuery.of(t.element(find.byType(ForeignRegisterScreen)));
      out('${c.id} screenMQ padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} · physical ${t.view.padding.top},${t.view.padding.bottom},${t.view.viewInsets.bottom}');
      Map<String, Object?> cond(String state) => {
            'entry': 'ForeignRegisterScreen(USER, isResume true, existingIdCardPath 합성) — LOCAL 직접 렌더(S005 경유 아님)',
            'theme': 'RoleTheme.workerTheme', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
            'mq': 'padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}', 'keyboard': '닫힘(inset 0)',
            'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록',
            'hooks': 'reuseOcr throw · pickAndOcr #1 result null / #2 고정 정상(NGUYEN VAN AN·9001015123456·E-9) · writer hook 계수만',
            'functions': 'CloudFunctionsHostApi.call 차단(오류 응답)', 'prefs': 'setMockInitialValues({})', 'clock': '미주입',
            'state': state, 'calls': hooks()};
      bool hits(Finder f, Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        return hit.path.any((e) => e.target == t.renderObject(f));
      }
      String rr(Finder f) {
        final r = t.getRect(f);
        return '$r(${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}) hit=${hits(f, r.center)} inScreen=${r.top >= 0 && r.bottom <= c.h && r.left >= 0 && r.right <= c.w}';
      }
      final body = find.descendant(of: find.byType(ForeignRegisterScreen), matching: find.byType(Scrollable)).first;
      ScrollPosition pos() => t.state<ScrollableState>(body).position;
      Finder tapOf(String label) => find.ancestor(of: findVisibleText(label), matching: find.byWidgetPredicate((w) => w is GestureDetector || w is InkWell || w is ButtonStyleButton)).first;
      final back = find.ancestor(of: find.byIcon(Icons.arrow_back), matching: find.byType(GestureDetector)).first;
      Finder nextBtn() => find.ancestor(of: findVisibleText('다음'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;

      // ① 재사용 실패 → documentScan 유지
      expect(reuseCalls, 1, reason: '기존 사진 재사용 시도');
      final gallery = findVisibleText('갤러리에서 선택');
      await t.scrollUntilVisible(gallery, 120, scrollable: body, maxScrolls: 60);
      await _settle(t, 2);
      out('① documentScan(재사용 실패) gallery=${rr(tapOf('갤러리에서 선택'))} back=${rr(back)} pixels=${pos().pixels.toStringAsFixed(1)} bodyViewport=${t.getRect(body)} ${hooks()}');
      await vqCapture(t, key, '${c.id}_1_scan_after_reuse_fail', conditions: cond('기존 사진 재사용 실패 → 등록증 스캔'));
      // ② 갤러리 → OCR 실패 → 정보 확인(수동 입력 안내)
      await t.tap(tapOf('갤러리에서 선택'));
      await _settle(t, 10);
      final notice = findVisibleText('일부 정보를 인식하지 못했습니다. 해당 항목을 직접 입력해주세요.');
      expect(notice, findsOneWidget, reason: 'OCR 실패 → 수동 입력 안내');
      out('② ocrConfirm(OCR 실패) notice=${t.getRect(notice)} title=${findVisibleText('정보 확인').evaluate().length} next=${rr(nextBtn())} pixels=${pos().pixels.toStringAsFixed(1)} ${hooks()}');
      await vqCapture(t, key, '${c.id}_2_ocr_fail_manual', conditions: cond('OCR 실패 → 정보 확인·수동 입력 안내'));
      // ③ 빈 입력으로 다음 → 로컬 검증
      await t.tap(nextBtn());
      await _settle(t, 6);
      final errs = find.byWidgetPredicate((w) => w is Text && (w.style?.color == Theme.of(t.element(find.byType(ForeignRegisterScreen))).colorScheme.error));
      final formErrs = <String>[for (final e in find.descendant(of: find.byType(Form), matching: find.byType(Text)).evaluate()) visibleText((e.widget as Text).data ?? '')]
          .where((s) => s.contains('입력') || s.contains('확인') || s.contains('필수')).toList();
      out('③ 빈 다음 → 검증 stillOcrConfirm=${findVisibleText('정보 확인').evaluate().isNotEmpty} formTexts=$formErrs errorColored=${errs.evaluate().length} '
          'toast=${find.descendant(of: find.byType(Overlay), matching: find.byIcon(Icons.warning_amber_outlined)).evaluate().length} pixels=${pos().pixels.toStringAsFixed(1)} ${hooks()}');
      expect(finalizeCalls, 0, reason: '빈 입력 — finalize 미진입');
      await vqCapture(t, key, '${c.id}_3_empty_next_validation', conditions: cond('빈 입력 다음 → 로컬 검증'));
      // 첫 검증 오류 위치로 실제 스크롤
      final firstErr = find.descendant(of: find.byType(Form), matching: find.byWidgetPredicate((w) => w is Text && (w.data ?? '').contains('입력해주세요'))).first;
      if (firstErr.evaluate().isNotEmpty) {
        await t.ensureVisible(firstErr);
        await _settle(t, 3);
        out('③b 첫 검증 오류 rect=${t.getRect(firstErr)} text="${visibleText(t.widget<Text>(firstErr).data ?? '')}" bodyViewport=${t.getRect(body)} pixels=${pos().pixels.toStringAsFixed(1)}');
        await vqCapture(t, key, '${c.id}_3b_first_error', conditions: cond('첫 검증 오류 위치'));
      }
      await _settle(t, 50); // 토스트 사라짐 대기(2s)
      // ④ 뒤로 → 스캔 → 재선택 → 정상 OCR → 정보 확인 재진입
      await t.tap(back);
      await _settle(t, 8);
      await t.scrollUntilVisible(gallery, 120, scrollable: body, maxScrolls: 60);
      await _settle(t, 2);
      out('④ 뒤로 → documentScan=${findVisibleText('갤러리에서 선택').evaluate().isNotEmpty} ${hooks()}');
      await t.tap(tapOf('갤러리에서 선택'));
      await _settle(t, 10);
      expect(findVisibleText('정보 확인'), findsWidgets, reason: '정보 확인 재진입');
      out('⑤ 정상 OCR 정보 확인 재진입 notice=${notice.evaluate().length} visaField=${find.byWidgetPredicate((w) => w is EditableText && w.controller.text == 'E-9').evaluate().length} next=${rr(nextBtn())} ${hooks()}');
      expect(notice, findsNothing, reason: '정상 OCR — 실패 안내 없음');
      await vqCapture(t, key, '${c.id}_4_ocr_ok_reentry', conditions: cond('재선택 → 고정 정상 OCR → 정보 확인'));
      expect(finalizeCalls + markCalls + uploadCalls, 0, reason: 'writer hook 미진입');
      FlutterError.onError = prev;
      out('overflows(${overflows.length})=${overflows.join(' | ')} ${hooks()}');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
    });
  }
}
