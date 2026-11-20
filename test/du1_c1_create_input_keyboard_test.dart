// ignore_for_file: depend_on_referenced_packages
// [DU1 구현54 · 감사54 §6] C1-CREATE-INPUT-KEYBOARD-B/W — 공통 안내 입력 · 합성 키보드 0→300→0 · 입력 줄/공고 등록 도달(구현50 하네스 복사).
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
import 'package:ALfit/screens/business_admin/to_management/widgets/to_action_button.dart';
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
    (id: 'C1-CREATE-INPUT-KEYBOARD-B', w: 320.0, h: 640.0, s: 2.0),
    (id: 'C1-CREATE-INPUT-KEYBOARD-W', w: 360.0, h: 780.0, s: 1.0),
  ]) {
    testWidgets('${c.id} 공고 등록 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 공통 안내 입력·키보드 0→300→0', (t) async {
      await t.runAsync(vqLoadFonts);
      final semantics = t.ensureSemantics(); // [구현51] 실제 Semantics 트리 관측
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
      final deferred = <String>[];

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
                onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const AdminCreateTOScreen(initialBusinessId: kBiz))),
                child: const Text('host'))))),
          ),
        ),
      ));
      await t.pump();
      await t.tap(find.text('host'));
      await _settle(t, 20);
      expect(find.byType(AdminCreateTOScreen), findsOneWidget);
      final mq = MediaQuery.of(t.element(find.byType(AdminCreateTOScreen)));
      out('${c.id} MQ padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets} · 초기 calls=$calls');
      for (final e in allowed.entries) {
        expect(calls[e.key], e.value, reason: '초기 허용 reader ${e.key}');
      }
      expect(calls.keys.where((k) => !allowed.containsKey(k)), isEmpty, reason: '초기 허용 외 호출 0');
      // 본문이 지연 생성이면 날짜 위젯이 아직 없다 — 실제 스크롤로 내려가 찾는다
      final body0 = find.descendant(of: find.byType(AdminCreateTOScreen), matching: find.byType(Scrollable)).first;
      await t.scrollUntilVisible(find.byType(TODateSelector), 120, scrollable: body0, maxScrolls: 80);
      expect(find.byType(TODateSelector), findsOneWidget, reason: '정상 reader → 폼 열림(production gate)');

      Map<String, Object?> cond(String state) => {
            'entry': 'LOCAL host → Navigator.push(AdminCreateTOScreen(initialBusinessId: $kBiz)) — 목록/홈 경유 아님',
            'theme': 'RoleTheme.businessAdminTheme', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
            'mq': 'padding=${mq.padding} viewPadding=${mq.viewPadding} viewInsets=${mq.viewInsets}', 'keyboard': '없음',
            'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK)',
            'data': 'biz $kBiz approved·license canonical·owner seal·workTypes 1(포장)·daily template 1 · flex(기본)',
            'prefs': 'setMockInitialValues({})', 'clock': '미주입(DateTime.now=$now)', 'input': '공통 안내 3줄 고정 원문',
            'state': state, 'calls': calls.toString()};
      bool hits(Finder f, Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        return hit.path.any((e) => e.target == t.renderObject(f));
      }
      String rr(Finder f) {
        final r = t.getRect(f);
        return '$r(${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}) hit=${hits(f, r.center)} inScreen=${r.top >= 0 && r.bottom <= c.h}';
      }

      final body = find.descendant(of: find.byType(AdminCreateTOScreen), matching: find.byType(Scrollable)).first;
      final pos = t.state<ScrollableState>(body).position;
      final descSection = find.byType(TODescriptionSection);
      await t.scrollUntilVisible(descSection, 160, scrollable: body, maxScrolls: 160);
      final field = find.descendant(of: descSection, matching: find.byType(TextFormField));
      await t.ensureVisible(field);
      await _settle(t, 4);
      final edit = find.descendant(of: field, matching: find.byType(EditableText));
      final cta = find.byType(TOActionButton);
      final ctaInk = find.descendant(of: cta, matching: find.byType(InkWell)).first;
      EditableTextState es() => t.state<EditableTextState>(edit);
      Rect caretRect() {
        final re = es().renderEditable;
        final sel = re.selection;
        final p = (sel == null || !sel.isValid) ? const TextPosition(offset: 0) : sel.extent;
        final local = re.getLocalRectForCaret(p);
        return MatrixUtils.transformRect(re.getTransformTo(null), local);
      }
      // 판정: 키보드 윗변 위·본문 viewport 안
      void judge(String tag, double inset) {
        final kbTop = c.h - inset;
        final vp = t.getRect(body);
        final cr = caretRect();
        final ctaR = t.getRect(cta);
        final inkR = t.getRect(ctaInk);
        final ctaHit = hits(ctaInk, inkR.center);
        final caretOk = cr.top >= vp.top - 0.5 && cr.bottom <= kbTop + 0.5 && cr.bottom <= vp.bottom + 0.5;
        final ctaOk = ctaR.top >= 0 && ctaR.bottom <= kbTop + 0.5 && ctaR.left >= 0 && ctaR.right <= c.w && ctaR.height >= 52 && ctaHit;
        out('   [$tag] 키보드 윗변 y=${kbTop.toStringAsFixed(1)} · 본문 viewport=$vp · caret=$cr 도달=$caretOk · CTA 외곽=$ctaR(높이 ${ctaR.height.toStringAsFixed(1)}) InkWell=$inkR 중심hit=$ctaHit 도달=$ctaOk');
        if (!caretOk) deferred.add('$tag 입력 중인 줄(caret)이 키보드 위·본문 안에 없음');
        if (!ctaOk) deferred.add('$tag 주 행동(공고 등록)이 키보드 위에 닿지 않음(외곽 $ctaR)');
      }
      void snap(String tag) {
        final m = MediaQuery.of(t.element(find.byType(AdminCreateTOScreen)));
        out('$tag · MQ viewInsets=${m.viewInsets} · 물리 view inset bottom=${t.view.viewInsets.bottom} · 포커스=${es().widget.focusNode.hasFocus} · 스크롤 ${pos.pixels.toStringAsFixed(1)}/${pos.maxScrollExtent.toStringAsFixed(1)} · 필드 ${rr(field)} · CTA ${rr(cta)}');
      }
      final ctrl0 = es().widget.controller;
      expect(ctrl0.text, isEmpty, reason: '입력 전 원문 빈 값');
      snap('① 입력 전');
      await t.tap(field);
      await _settle(t, 4);
      expect(es().widget.focusNode.hasFocus, isTrue, reason: '실제 탭 → 포커스');
      const part1 = '준비물은 안전화입니다.\n긴 바지를 착용해 주세요.';
      await t.enterText(field, part1);
      await _settle(t, 4);
      expect(es().widget.controller.text, part1);
      snap('② 입력(키보드 0)');
      judge('키보드0', 0);
      await vqCapture(t, key, '${c.id}_1_input', conditions: cond('입력 중 · 키보드 0'));
      // ③ 합성 키보드 300 (물리 view inset → MQ viewInsets)
      t.view.viewInsets = const FakeViewPadding(bottom: 300);
      await _settle(t, 12);
      expect(es().widget.focusNode.hasFocus, isTrue, reason: '키보드 중 포커스 유지');
      snap('③ 키보드 300');
      judge('키보드300', 300);
      await vqCapture(t, key, '${c.id}_2_kb300', conditions: cond('키보드 300 (합성 물리 inset)'));
      const full = '$part1\n정문 안내데스크에서 모입니다.';
      await t.enterText(field, full);
      await _settle(t, 8);
      expect(es().widget.controller.text, full, reason: '키보드 중 추가 입력');
      snap('④ 키보드 300 추가 입력');
      judge('키보드300 추가입력', 300);
      await vqCapture(t, key, '${c.id}_3_kb300_more', conditions: cond('키보드 300 · 추가 입력'));
      // ⑤ 키보드 닫힘 0
      t.view.viewInsets = FakeViewPadding.zero;
      await _settle(t, 12);
      snap('⑤ 키보드 0 복귀');
      expect(es().widget.controller.text, full, reason: '복귀 후 원문 유지');
      expect(find.byType(AdminCreateTOScreen), findsOneWidget, reason: '폼 유지');
      final ctaR = t.getRect(cta);
      out('   복귀 후 CTA 아래 여백=${(c.h - ctaR.bottom).toStringAsFixed(1)}');
      await vqCapture(t, key, '${c.id}_4_kb0', conditions: cond('키보드 닫힘 복귀'));

      out('최종 calls=$calls');
      for (final e in allowed.entries) {
        expect(calls[e.key], e.value, reason: '최종 허용 reader ${e.key}');
      }
      expect(calls.keys.where((k) => !allowed.containsKey(k)), isEmpty, reason: '허용 외 read/write/Functions 0');
      FlutterError.onError = prev;
      out('overflows(${overflows.length})=${overflows.join(' | ')}');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
      out('deferred(${deferred.length})=${deferred.join(' | ')}');
      expect(deferred, isEmpty, reason: deferred.join(' | '));
      semantics.dispose(); // 시험 끝 검증 전에 해제(tearDown 은 늦다)
    });
  }
}
