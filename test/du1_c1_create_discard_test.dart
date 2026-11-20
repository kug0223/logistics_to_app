// ignore_for_file: depend_on_referenced_packages
// [DU1 구현55 · 감사55 §6] C1-CREATE-DISCARD-B/W — 깨끗한 뒤로 · 공통 안내 입력 → 뒤로 경고 → 계속 작성(보존) → 뒤로 → 나가기 → 재진입 빈 값(구현54 하네스 복사).
//   LOCAL host route 에서 production AdminCreateTOScreen(initialBusinessId: biz) push. 정상 reader 4개를 고정 응답:
//     businesses/biz doc.get · users/owner doc.get(날인) · businesses/biz/workTypes queryGet · businesses/biz/contract_templates queryGet.
//   등록증은 canonical businessLicenseImageUrl 로 owner 재읽기 없이 READY. 그 밖 Firestore/Functions 는 오류 응답으로 명시 차단·계수.
//   private _formUnlocked 직접 설정·날짜 위젯 단독 pump 없음. 등록 CTA 미탭(writer 0).
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/to_management/create_to_screen.dart';
import 'package:ALfit/screens/business_admin/to_management/widgets/to_description_section.dart';
import 'package:ALfit/screens/business_admin/to_management/widgets/to_date_selector.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';

import 'support/du1_vq_capture.dart';

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

const kBiz = 'biz-local-c50';
const kOwner = 'owner-local-c50';

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: kOwner, username: 'owner', name: 'QA 사장', email: 'o@test.local',
      role: UserRole.BUSINESS_ADMIN, businessId: kBiz, managedBusinessIds: const [kBiz], createdAt: DateTime(2026, 1, 1));
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
  // BUSINESS_ADMIN 은 production 에서도 항상 true(user_provider canForBusiness) — 테스트 대역은 _currentUser 를 못 채워 같은 값을 직접 돌려준다
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
}

Future<void> _settle(WidgetTester t, [int n = 8]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  final calls = <String, int>{};
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  void inc(String k) => calls[k] = (calls[k] ?? 0) + 1;
  final meta = PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false);

  void stubFirestore() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = FirebaseFirestoreHostApi.codec;
    m.setMockMessageHandler('$base.documentReferenceGet', (msg) async {
      final args = codec.decodeMessage(msg) as List;
      final path = (args[1] as DocumentReferenceRequest).path;
      inc('get $path');
      Map<String?, Object?>? data;
      if (path == 'businesses/$kBiz') {
        data = {
          'name': 'QA 물류센터', 'businessNumber': '000-00-00000', 'category': '물류', 'subCategory': '포장', 'address': '서울시 QA구 1',
          'ownerId': kOwner, 'adminIds': [kOwner], 'isApproved': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
          'businessLicenseImageUrl': 'https://example.invalid/qa-license.png',
        };
      } else if (path == 'users/$kOwner') {
        data = {'role': 'BUSINESS_ADMIN', 'name': 'QA 사장', 'sealBase64': 'LOCAL-QA-SEAL'};
      } else {
        return codec.encodeMessage(<Object?>['du50-blocked', 'get 차단: $path', null]);
      }
      return codec.encodeMessage(<Object?>[PigeonDocumentSnapshot(path: path, data: data, metadata: meta)]);
    });
    m.setMockMessageHandler('$base.queryGet', (msg) async {
      // 요청 본문은 codec 으로 되읽을 수 없다(구현48 r2) — 원본 바이트의 ASCII 경로 substring 으로 구분(한정 stub)
      final raw = String.fromCharCodes(msg!.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes));
      final String key;
      final List<PigeonDocumentSnapshot> docs;
      if (raw.contains('businesses/$kBiz/workTypes')) {
        key = 'query businesses/$kBiz/workTypes';
        docs = [
          PigeonDocumentSnapshot(path: 'businesses/$kBiz/workTypes/wt-c50', data: <String?, Object?>{
            'businessId': kBiz, 'name': '포장', 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
            'displayOrder': 0, 'isActive': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
          }, metadata: meta),
        ];
      } else if (raw.contains('businesses/$kBiz/contract_templates')) {
        key = 'query businesses/$kBiz/contract_templates';
        docs = [
          PigeonDocumentSnapshot(path: 'businesses/$kBiz/contract_templates/tpl-c50', data: <String?, Object?>{
            'businessId': kBiz, 'name': '단기 근무 기본', 'templateType': 'daily', 'articles': const [],
            'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
          }, metadata: meta),
        ];
      } else {
        inc('query other');
        return codec.encodeMessage(<Object?>['du50-blocked', 'query 차단', null]);
      }
      inc(key);
      return codec.encodeMessage(<Object?>[PigeonQuerySnapshot(documents: docs, documentChanges: const [], metadata: meta)]);
    });
    for (final op in const ['documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit',
      'transactionCreate', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        inc(op);
        return codec.encodeMessage(<Object?>['du50-blocked', '$op 차단', null]);
      });
    }
    m.setMockMessageHandler('dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call', (msg) async {
      inc('functions.call');
      return const StandardMessageCodec().encodeMessage(<Object?>['du50-blocked', 'functions 차단', null]);
    });
  }

  const allowed = {
    'get businesses/$kBiz': 1,
    'get users/$kOwner': 1,
    'query businesses/$kBiz/workTypes': 1,
    'query businesses/$kBiz/contract_templates': 1,
  };

  for (final c in const [
    (id: 'C1-CREATE-DISCARD-B', w: 320.0, h: 640.0, s: 2.0),
    (id: 'C1-CREATE-DISCARD-W', w: 360.0, h: 780.0, s: 1.0),
  ]) {
    testWidgets('${c.id} 공고 등록 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 깨끗한 뒤로·입력 뒤 경고·계속 작성·나가기·재진입', (t) async {
      await t.runAsync(vqLoadFonts);
      calls.clear();
      stubFirestore();
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          overflows.add(m.split('\n').first);
          // ignore: avoid_print
          print('OVERFLOW-DETAIL ${d.toString().split('\n').where((l) => l.contains('file:///') || l.contains('overflowed')).take(4).join(' / ')}');
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);
      t.view.physicalSize = Size(c.w, c.h);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      void out(String l) {
        // ignore: avoid_print
        print(l);
      }
      final now = DateTime.now();
      out('${c.id} 실행 시각=$now tz=${now.timeZoneName}(${now.timeZoneOffset})');
      final deferred = <String>[];
      final results = <Object?>[]; // host 가 받은 route 결과(진입마다 1개)
      final key = GlobalKey();
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(create: (_) => _Owner()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()), // setUser 없음
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            navigatorKey: navigatorKey,
            theme: RoleTheme.businessAdminTheme,
            builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
            home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
                onPressed: () async {
                  final r = await Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const AdminCreateTOScreen(initialBusinessId: kBiz)));
                  results.add(r);
                },
                child: const Text('host'))))),
          ),
        ),
      ));
      await t.pump();
      bool hits(Finder f, Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        return hit.path.any((e) => e.target == t.renderObject(f));
      }
      String rr(Finder f) {
        final r = t.getRect(f);
        return '$r(${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}) hit=${hits(f, r.center)} inScreen=${r.top >= 0 && r.bottom <= c.h && r.left >= 0 && r.right <= c.w}';
      }
      // 단계마다 **현재** MQ·물리 inset 을 sidecar 에 쓴다(감사55: 초기 상수 재사용 금지)
      Map<String, Object?> cond(String state, {String input = ''}) {
        final scr = find.byType(AdminCreateTOScreen);
        final m = scr.evaluate().isEmpty ? MediaQuery.of(t.element(find.text('host'))) : MediaQuery.of(t.element(scr));
        return {
          'entry': 'LOCAL host → Navigator.push(AdminCreateTOScreen(initialBusinessId: $kBiz)) — 진입마다 새 route',
          'theme': 'RoleTheme.businessAdminTheme', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
          'mqNow': 'padding=${m.padding} viewPadding=${m.viewPadding} viewInsets=${m.viewInsets}',
          'physicalInsetBottomNow': t.view.viewInsets.bottom, 'keyboard': '합성 없음(inset 0)',
          'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK)',
          'data': 'biz $kBiz approved·license canonical·owner seal·workTypes 1·daily template 1 · flex(기본)',
          'prefs': 'setMockInitialValues({})', 'clock': '미주입(DateTime.now=$now)', 'input': input,
          'state': state, 'calls': calls.toString(), 'routeResults': results.toString()};
      }
      Finder backBtn() => find.descendant(
          of: find.byType(AdminCreateTOScreen),
          matching: find.byWidgetPredicate((w) =>
              w is BackButton ||
              (w is IconButton &&
                  w.icon is Icon &&
                  ((w.icon as Icon).icon == Icons.arrow_back ||
                      (w.icon as Icon).icon == Icons.arrow_back_ios_new ||
                      (w.icon as Icon).icon == Icons.arrow_back_ios)))).first;
      Future<void> enter(String tag) async {
        calls.clear();
        await t.tap(find.text('host'));
        await _settle(t, 20);
        expect(find.byType(AdminCreateTOScreen), findsOneWidget, reason: '$tag 진입');
        for (final e in allowed.entries) {
          expect(calls[e.key], e.value, reason: '$tag 허용 reader ${e.key}');
        }
        expect(calls.keys.where((k) => !allowed.containsKey(k)), isEmpty, reason: '$tag 허용 외 0');
        out('$tag 진입 · calls=$calls');
      }
      final body = find.descendant(of: find.byType(AdminCreateTOScreen), matching: find.byType(Scrollable)).first;
      final descSection = find.byType(TODescriptionSection);
      Finder field() => find.descendant(of: descSection, matching: find.byType(TextFormField));
      Finder edit() => find.descendant(of: field(), matching: find.byType(EditableText));
      Future<void> toDescription() async {
        await t.scrollUntilVisible(find.byType(TODateSelector), 120, scrollable: body, maxScrolls: 80);
        await t.scrollUntilVisible(descSection, 160, scrollable: body, maxScrolls: 160);
        await t.ensureVisible(field());
        await _settle(t, 4);
      }
      String descText() => t.widget<EditableText>(edit()).controller.text;
      const warnTitle = '입력 중인 내용이 있습니다';
      const warnMsg = '공고 등록을 취소하시겠습니까?\n입력한 내용이 모두 사라집니다.';
      Finder textNorm(String s) => find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll('⁠', '') == s);
      Finder actionBtn(String label) => find.ancestor(of: textNorm(label), matching: find.byType(InkWell)).first;
      void dialogMeasure(String tag) {
        final dlg = find.byType(Dialog);
        expect(dlg, findsOneWidget, reason: '$tag 경고 표시');
        expect(textNorm(warnTitle), findsOneWidget, reason: '$tag 경고 제목 전문');
        expect(textNorm(warnMsg), findsOneWidget, reason: '$tag 경고 본문 전문');
        final keep = actionBtn('계속 작성'), leave = actionBtn('나가기');
        out('   [$tag] 경고 ${t.getRect(dlg)} · 제목 ${t.getRect(textNorm(warnTitle))} · 본문 ${t.getRect(textNorm(warnMsg))} · 계속 작성 ${rr(keep)} · 나가기 ${rr(leave)}');
        for (final (n, f) in [('계속 작성', keep), ('나가기', leave)]) {
          final r = t.getRect(f);
          if (r.width < 48 || r.height < 48) deferred.add('$tag $n 터치 ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} < 48');
          if (!hits(f, r.center)) deferred.add('$tag $n 중심 hit 실패');
          if (r.top < 0 || r.bottom > c.h || r.left < 0 || r.right > c.w) deferred.add('$tag $n 화면 밖');
        }
      }

      // ① 깨끗한 진입 → 입력 없이 앱 뒤로 → 경고 없이 복귀
      await enter('① 첫 진입');
      out('   뒤로 ${rr(backBtn())}');
      await vqCapture(t, key, '${c.id}_1_clean', conditions: cond('첫 진입 · 변경 없음'));
      await t.tap(backBtn());
      await _settle(t, 10);
      expect(find.byType(Dialog), findsNothing, reason: '변경 없음 → 경고 없음');
      expect(find.byType(AdminCreateTOScreen), findsNothing, reason: '변경 없음 → 바로 복귀');
      expect(results, [null], reason: '깨끗한 복귀 결과 null 1회');
      out('① 깨끗한 뒤로 → host · results=$results');

      // ② 재진입 → 공통 안내 실탭·3줄 입력
      await enter('② 재진입');
      await toDescription();
      await t.tap(field());
      await _settle(t, 4);
      const text3 = '준비물은 안전화입니다.\n긴 바지를 착용해 주세요.\n정문 안내데스크에서 모입니다.';
      await t.enterText(field(), text3);
      await _settle(t, 4);
      expect(descText(), text3);
      FocusManager.instance.primaryFocus?.unfocus();
      await _settle(t, 4);
      out('② 입력 → "${descText().replaceAll('\n', '⏎')}" · 물리 inset=${t.view.viewInsets.bottom}');
      await vqCapture(t, key, '${c.id}_2_dirty', conditions: cond('공통 안내 입력 뒤', input: text3));

      // ③ 앱 뒤로 → 경고 → 계속 작성
      out('   뒤로 ${rr(backBtn())}');
      await t.tap(backBtn());
      await _settle(t, 10);
      dialogMeasure('③ 첫 경고');
      await vqCapture(t, key, '${c.id}_3_warn', conditions: cond('뒤로 → 미저장 경고', input: text3));
      await t.tap(actionBtn('계속 작성'));
      await _settle(t, 10);
      expect(find.byType(Dialog), findsNothing, reason: '계속 작성 → 경고만 닫힘');
      expect(find.byType(AdminCreateTOScreen), findsOneWidget, reason: '계속 작성 → create 유지');
      expect(descText(), text3, reason: '계속 작성 → 원문 보존');
      expect(descSection, findsOneWidget, reason: '폼 유지(현재 보이는 공통 안내 섹션 — 날짜 위젯은 지연 목록에서 화면 밖이라 해제됨)');
      expect(results, [null], reason: '계속 작성 → route 결과 추가 없음');
      out('③ 계속 작성 → create 유지 · 원문 보존 · results=$results');
      await vqCapture(t, key, '${c.id}_4_keep', conditions: cond('계속 작성 뒤', input: text3));

      // ④ 다시 뒤로 → 경고 → 나가기
      await t.tap(backBtn());
      await _settle(t, 10);
      dialogMeasure('④ 재경고');
      await vqCapture(t, key, '${c.id}_5_rewarn', conditions: cond('다시 뒤로 → 경고', input: text3));
      await t.tap(actionBtn('나가기'));
      await _settle(t, 12);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(AdminCreateTOScreen), findsNothing, reason: '나가기 → create 제거');
      expect(results, [null, null], reason: '나가기 → host 정확히 1회 복귀·결과 null');
      out('④ 나가기 → host · results=$results');
      await vqCapture(t, key, '${c.id}_6_host', conditions: cond('나가기 → host'));

      // ⑤ 새 재진입 → 공통 안내 빈 값(폐기 원문 복원 없음) → 깨끗한 뒤로
      await enter('⑤ 새 재진입');
      await toDescription();
      expect(descText(), isEmpty, reason: '폐기한 원문 복원 없음');
      out('⑤ 새 재진입 공통 안내="${descText()}"');
      await vqCapture(t, key, '${c.id}_7_reenter', conditions: cond('새 재진입 · 공통 안내 빈 값'));
      await t.tap(backBtn());
      await _settle(t, 10);
      expect(find.byType(Dialog), findsNothing);
      expect(results, [null, null, null]);

      out('최종 calls(마지막 진입 이후)=$calls · results=$results');
      expect(calls.keys.where((k) => !allowed.containsKey(k)), isEmpty, reason: '허용 외 read/write/Functions 0');
      FlutterError.onError = prev;
      out('overflows(${overflows.length})=${overflows.join(' | ')}');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
      out('deferred(${deferred.length})=${deferred.join(' | ')}');
      expect(deferred, isEmpty, reason: deferred.join(' | '));
    });
  }
}
