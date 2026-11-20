// ignore_for_file: depend_on_referenced_packages
// [DU1 구현46 · 감사46 §4 우선 셀] C0 S005 RegistrationRecoveryScreen — 문서 없음 → 실제 '다시 시도' → 복구 판정(termsOnly).
//   seam: RegistrationRecoveryScreen(reads:) — 첫 userDoc=null(문서 없음, 통신 실패 아님), 둘째 userDoc=fingerprint+idCard·빈 termsConsent.
//   LOCAL seam 렌더이며 login signIn → 복구 라우팅 실증이 아니다. recordConsent 는 호출 수만 센다(기대 0). 가입 완료·로그아웃은 누르지 않는다.
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/legal_terms_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/auth/registration_recovery_reads.dart';
import 'package:ALfit/screens/auth/registration_recovery_screen.dart';
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

// 약관 자료 — 구현43~45 의 kItems 와 같은 필수2/선택1 구성(긴 대상 약관 포함)
const kLongTitle = '[QA] 서비스 이용약관 (위치기반 근무 매칭 및 급여 정산 이용 조건 포함)';
String longContent() {
  final b = StringBuffer('[QA-첫문장] 이 약관은 ALfit 이 제공하는 근무 매칭 서비스의 이용 조건과 절차를 정합니다.\n');
  for (var n = 1; n <= 8; n++) {
    b.writeln('제$n조 (QA 조문 $n — 이용 조건과 책임의 범위)');
    b.writeln('① 회원은 서비스를 이용할 때 관계 법령과 이 약관의 내용을 지켜야 하며, 회사가 안내하는 이용 방법을 따라야 합니다.');
  }
  b.write('[QA-끝문장] 본 약관은 2026년 11월 1일부터 시행하며, 이전 약관은 이 날부터 효력을 잃습니다.');
  return b.toString();
}
EffectiveLegalTerms kTerms() => EffectiveLegalTerms(serverNow: DateTime.utc(2026, 11, 1), upcoming: const [], items: [
      LegalTermsItem(id: 'service_terms', title: kLongTitle, content: longContent(), isRequired: true, version: '2026-11-01',
          revisionId: 'service_terms__2026-11-01', order: 1),
      const LegalTermsItem(id: 'privacy', title: '개인정보 수집·이용 동의', content: '개인정보 수집·이용 동의 본문입니다.', isRequired: true,
          version: 'b', revisionId: 'privacy__b', order: 2),
      const LegalTermsItem(id: 'marketing', title: '마케팅 수신', content: '마케팅 수신 본문입니다.', isRequired: false, version: 'b',
          revisionId: 'marketing__b', order: 3),
    ]);
const kSecondDoc = <String, dynamic>{
  'role': 'USER',
  'accountStatus': 'registration_pending',
  'foreignIdentityFingerprint': 'fp',
  'idCardImagePath': 'id_cards/local-recovery/synthetic.jpg',
  'termsConsent': <String, dynamic>{},
};

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  for (final c in const [(id: 'C0-RR-B', w: 320.0, h: 640.0, s: 2.0), (id: 'C0-RR-N', w: 320.0, h: 640.0, s: 1.0)]) {
    testWidgets('${c.id} 가입 복구 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 문서 없음 → 다시 시도 → 약관 동의 단계(recordConsent 0)', (t) async {
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
      final size = Size(c.w, c.h);
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      var docCalls = 0;
      var recordCalls = 0;
      final reads = RegistrationRecoveryReads(
        currentUid: () => 'u-local-recovery',
        userDoc: (uid) async {
          docCalls++;
          return docCalls == 1 ? null : Map<String, dynamic>.from(kSecondDoc);
        },
        terms: () async => kTerms(),
        recordConsent: (record) async {
          recordCalls++;
        },
      );
      final key = GlobalKey();
      await t.pumpWidget(ChangeNotifierProvider<UserProvider>(
        create: (_) => UserProvider(),
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: RoleTheme.workerTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: RegistrationRecoveryScreen(reads: reads),
          ),
        ),
      ));
      await _settle(t);
      void out(String l) {
        // ignore: avoid_print
        print(l);
      }
      final mq = MediaQuery.of(t.element(find.byType(RegistrationRecoveryScreen)));
      out('${c.id} screenMQ padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} · physical ${t.view.padding.top},${t.view.padding.bottom},${t.view.viewInsets.bottom}');
      Map<String, Object?> cond(String state) => {
            'entry': 'RegistrationRecoveryScreen(reads seam) — LOCAL(login 라우팅 실증 아님)', 'theme': 'RoleTheme.workerTheme',
            'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
            'mq': 'padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}', 'keyboard': '닫힘(inset 0)',
            'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록',
            'data': 'userDoc#1=null · userDoc#2={role USER, registration_pending, fingerprint fp, idCardImagePath synthetic, termsConsent {}} · 약관 필수2/선택1(긴 service_terms)',
            'prefs': 'setMockInitialValues({})', 'clock': '미주입', 'state': state, 'docCalls': docCalls, 'recordCalls': recordCalls};
      bool hits(Finder f, Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        return hit.path.any((e) => e.target == t.renderObject(f));
      }
      String rr(Finder f) {
        final r = t.getRect(f);
        return '$r(${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}) hit=${hits(f, r.center)} inScreen=${r.top >= 0 && r.bottom <= c.h && r.left >= 0 && r.right <= c.w}';
      }
      Finder btn(String label) => find.ancestor(of: findVisibleText(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)).first;

      // ① 문서 없음 → 오류 화면
      expect(findVisibleText('상태 확인 실패'), findsOneWidget);
      final msg = findVisibleText('계정 정보를 찾을 수 없습니다. 다시 로그인해주세요.');
      expect(msg, findsOneWidget);
      out('① error docCalls=$docCalls title=${t.getRect(findVisibleText('상태 확인 실패'))} msg=${t.getRect(msg)} retry=${rr(btn('다시 시도'))} '
          'signOut(로그인 화면으로 돌아가기)=${rr(btn('로그인 화면으로 돌아가기'))} '
          'overflowsSoFar=${overflows.length}');
      await vqCapture(t, key, '${c.id}_1_error', conditions: cond('문서 없음 → 상태 확인 실패'));
      // ② 실제 다시 시도
      await t.tap(btn('다시 시도'));
      await _settle(t, 10);
      expect(docCalls, 2, reason: '실제 _detectCase 재호출');
      expect(findVisibleText('약관 동의가 필요합니다'), findsOneWidget, reason: 'fingerprint+idCard → termsOnly');
      final cta = btn('동의하고 가입 완료');
      final list = find.descendant(of: find.byType(RegistrationRecoveryScreen), matching: find.byType(Scrollable)).first;
      out('② termsOnly docCalls=$docCalls cta=${rr(cta)} ctaEnabled=${t.widget<ElevatedButton>(cta).onPressed != null} listViewport=${t.getRect(list)} '
          'pixels=${t.state<ScrollableState>(list).position.pixels.toStringAsFixed(1)}/${t.state<ScrollableState>(list).position.maxScrollExtent.toStringAsFixed(1)}');
      expect(t.widget<ElevatedButton>(cta).onPressed, isNull, reason: '필수 미선택 — 가입 CTA 비활성');
      await vqCapture(t, key, '${c.id}_2_terms_top', conditions: cond('다시 시도 → 약관 동의 단계 첫 화면'));
      // ③ 마케팅 행까지 실제 스크롤 → 정착 말단 확인 후 캡처(구현147 진단: 원 _3 은 범위 밖 · 스크롤 중 프레임이었다)
      final lastRow = findVisibleTextContaining('마케팅 수신');
      // [r2] ListView 는 화면 밖 행을 아직 만들지 않는다 — .first 없이 스크롤하며 찾는다(r1 No element)
      await t.scrollUntilVisible(lastRow, 120, scrollable: list, maxScrolls: 80);
      await _settle(t, 2);
      final lr = t.getRect(lastRow.first);
      final vp = t.getRect(list);
      final viewBtns = find.descendant(of: find.ancestor(of: lastRow.first, matching: find.byType(Row)).first, matching: find.byType(TextButton));
      final cbs = find.descendant(of: find.ancestor(of: lastRow.first, matching: find.byType(Row)).first, matching: find.byType(Checkbox));
      out('③ 마케팅 행 도달(정착 전) marketing=$lr listViewport=$vp 보임=${lr.top >= vp.top - 0.5 && lr.bottom <= vp.bottom + 0.5} pixels=${t.state<ScrollableState>(list).position.pixels.toStringAsFixed(1)} cta=${rr(cta)} 보기=${rr(viewBtns.first)} checkbox=${rr(cbs.first)} signOut=${rr(btn('로그인 화면으로 돌아가기'))}');
      // [DU1 구현148 ④ 하네스 · 후속148 §2] 마케팅 행 도달(위 50ms×2) 뒤, _3 캡처 전에만 유한 정착 · 말단을 확인한다.
      //   같은 ScrollPosition 의 6 수치 + 마케팅 Text · Row · viewport · CTA · 복귀 rect 20 성분(=26)을 50ms×최대20 표본으로 읽고,
      //   최근 3표본 max−min ≤ 0.1 · 같은 position · 유효 dimensions · inRange · idle 이면 안정 → 고정 50ms 1회 hold → extentAfter ≤ 0.5.
      //   추가 scroll/drag/jump/animate/ensureVisible/pumpAndSettle 0. 147 의 _3(정착 전 범위 밖 프레임)과 다른 시점이다.
      final settlePos = t.state<ScrollableState>(list).position;
      final settleRow = find.ancestor(of: lastRow.first, matching: find.byType(Row)).first;
      final settleSignOut = btn('로그인 화면으로 돌아가기');
      List<double> settleNums() {
        final p = t.state<ScrollableState>(list).position;
        final rs = <Rect>[t.getRect(lastRow.first), t.getRect(settleRow), t.getRect(list), t.getRect(cta), t.getRect(settleSignOut)];
        return <double>[
          p.pixels, p.minScrollExtent, p.maxScrollExtent, p.viewportDimension, p.extentBefore, p.extentAfter,
          for (final r in rs) ...<double>[r.left, r.top, r.right, r.bottom],
        ];
      }
      bool settleFlags() {
        final p = t.state<ScrollableState>(list).position;
        return identical(p, settlePos) && p.hasContentDimensions && !p.outOfRange && !p.isScrollingNotifier.value;
      }
      double spreadOf(List<List<double>> w) {
        var s = 0.0;
        for (var k = 0; k < w[0].length; k++) {
          var hi = w[0][k];
          var lo = w[0][k];
          for (final v in w) {
            if (v[k] > hi) hi = v[k];
            if (v[k] < lo) lo = v[k];
          }
          if (hi - lo > s) s = hi - lo;
        }
        return s;
      }
      String settleLine(String tag) {
        final p = t.state<ScrollableState>(list).position;
        return '$tag samePosition=${identical(p, settlePos)} pixels=${p.pixels} min=${p.minScrollExtent} max=${p.maxScrollExtent} '
            'viewportDimension=${p.viewportDimension} extentBefore=${p.extentBefore} extentAfter=${p.extentAfter} '
            'hasContentDimensions=${p.hasContentDimensions} outOfRange=${p.outOfRange} isScrolling=${p.isScrollingNotifier.value} '
            'nums=${settleNums().join(',')} docCalls=$docCalls recordCalls=$recordCalls overflows=${overflows.length}';
      }
      out(settleLine('③ 정착 탐색 시작'));
      final settleSamples = <List<double>>[];
      final settleOk = <bool>[];
      var stableAt = 0;
      for (var i = 1; i <= 20; i++) {
        await t.pump(const Duration(milliseconds: 50));
        final n = settleNums();
        settleSamples.add(n);
        settleOk.add(settleFlags() && n.every((v) => v.isFinite));
        if (settleSamples.length >= 3 &&
            settleOk.sublist(settleOk.length - 3).every((f) => f) &&
            spreadOf(settleSamples.sublist(settleSamples.length - 3)) <= 0.1) {
          stableAt = i;
          break;
        }
      }
      out('③ 정착 탐색 samples=${settleSamples.length} stableWindow=${stableAt == 0 ? '없음' : '#${stableAt - 2}~#$stableAt'}');
      expect(stableAt, greaterThan(0), reason: '50ms×20 안에 같은 ScrollPosition 이 안정 창(3표본 ≤0.1 · inRange · idle)에 들지 않았다');
      final settled = settleSamples.last;
      await t.pump(const Duration(milliseconds: 50));
      final held = settleNums();
      final holdDelta = spreadOf([settled, held]);
      out('${settleLine('③ hold(+50ms)')} holdDelta=$holdDelta');
      expect(settleFlags() && held.every((v) => v.isFinite) && holdDelta <= 0.1, isTrue, reason: '안정 후보 뒤 50ms 에 위치 · rect · 상태가 유지되지 않았다');
      expect(t.state<ScrollableState>(list).position.extentAfter, lessThanOrEqualTo(0.5), reason: '정착 위치가 목록 말단이 아니다');
      out(settleLine('③ 캡처 전'));
      await vqCapture(t, key, '${c.id}_3_terms_list', conditions: cond('마케팅 행 도달 → 정착 말단 확인 후 캡처'));
      final afterCapture = settleNums();
      final captureDelta = spreadOf([held, afterCapture]);
      out('${settleLine('③ 캡처 후')} captureDelta=$captureDelta');
      expect(settleFlags() && afterCapture.every((v) => v.isFinite) && captureDelta <= 0.1 && t.state<ScrollableState>(list).position.extentAfter <= 0.5, isTrue,
          reason: '정착 대표 캡처 전후로 말단 상태가 유지되지 않았다');
      expect(recordCalls, 0, reason: '동의 기록 writer 미호출');
      FlutterError.onError = prev;
      out('overflows(${overflows.length})=${overflows.join(' | ')} recordCalls=$recordCalls');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
    });
  }
}
