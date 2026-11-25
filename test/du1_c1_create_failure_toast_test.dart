// ignore_for_file: depend_on_referenced_packages
// [DU1 구현57 · 후속57] C1-CREATE-FAILURE-TOAST-B/W — 실패 토스트와 재시도 CTA 동시 노출 · 토스트 표시 중 실제 재탭(구현56 하네스 복사).
//   LOCAL host route 에서 production AdminCreateTOScreen(initialBusinessId: biz) push. 정상 reader 4개를 고정 응답:
//     businesses/biz doc.get · users/owner doc.get(날인) · businesses/biz/workTypes queryGet · businesses/biz/contract_templates queryGet.
//   등록증은 canonical businessLicenseImageUrl 로 owner 재읽기 없이 READY. 그 밖 Firestore/Functions 는 오류 응답으로 명시 차단·계수.
//   private _formUnlocked 직접 설정·날짜 위젯 단독 pump 없음. 등록 CTA 는 실탭 — LOCAL callableCreateTO 대역 2회(서버 생성·공개 없음), Firestore 쓰기 0.
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'dart:async';

import 'package:flutter/cupertino.dart';
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
import 'package:ALfit/screens/business_admin/to_management/widgets/to_action_button.dart';
import 'package:ALfit/screens/business_admin/to_management/widgets/to_date_selector.dart';
import 'package:ALfit/screens/business_admin/to_management/widgets/to_work_details_section.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/network_checker.dart';
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
      } else if (path == 'settings/wage_config') {
        data = {'minimumWages': {'2026': 10320, '2027': 10700}}; // LOCAL fixture(법정값 외부 검증 주장 아님)
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


  // ── callableCreateTO 대역: 호출마다 새 gate 로 보류 → 명시 실패 envelope ──
  final fnRequests = <Map<Object?, Object?>>[];
  final gates = <Completer<void>>[];
  void stubCreateTO() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
        'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call', (msg) async {
      final args = (const StandardMessageCodec().decodeMessage(msg) as List).first as Map;
      final name = args['functionName'];
      final region = args['region'];
      if (name != 'callableCreateTO' || region != 'asia-northeast3') {
        inc('functions.other $name@$region');
        return const StandardMessageCodec().encodeMessage(<Object?>['not-found', 'du56-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      inc('functions callableCreateTO');
      fnRequests.add(Map<Object?, Object?>.from(args));
      final g = Completer<void>();
      gates.add(g);
      await g.future;
      return const StandardMessageCodec().encodeMessage(<Object?>[
        'internal',
        'LOCAL-C1-CREATE-FAILURE',
        <String, Object?>{'code': 'internal', 'message': 'LOCAL-C1-CREATE-FAILURE'},
      ]);
    });
  }

  const allowedEntry = {
    'get businesses/$kBiz': 1,
    'get users/$kOwner': 1,
    'query businesses/$kBiz/workTypes': 1,
    'query businesses/$kBiz/contract_templates': 1,
  };

  for (final c in const [
    (id: 'C1-CREATE-FAILURE-TOAST-B', w: 320.0, h: 640.0, s: 2.0),
    (id: 'C1-CREATE-FAILURE-TOAST-W', w: 360.0, h: 780.0, s: 1.0),
  ]) {
    testWidgets('${c.id} 공고 등록 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 실패 토스트·CTA 동시 노출·토스트 중 재탭', (t) async {
      await t.runAsync(vqLoadFonts);
      calls.clear();
      fnRequests.clear();
      gates.clear();
      stubFirestore();
      stubCreateTO();
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
      final today = DateTime(now.year, now.month, now.day);
      final day = today.add(const Duration(days: 7));
      out('${c.id} 실행 시각=$now tz=${now.timeZoneName}(${now.timeZoneOffset}) 선택일=${day.toIso8601String().substring(0, 10)} · NetworkChecker.isOnline=${NetworkChecker.instance.isOnline}');
      expect(day.month == today.month, isTrue, reason: '오늘+7 이 같은 달(월 이동 없이) — 다르면 셀 재설계');
      final deferred = <String>[];
      final results = <Object?>[];
      final key = GlobalKey();
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(create: (_) => _Owner()),
          ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
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
      Future<void> frames([int n = 8]) async {
        for (var i = 0; i < n; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
      }
      bool hits(Finder f, Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        return hit.path.any((e) => e.target == t.renderObject(f));
      }
      String topHit(Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        return hit.path.take(3).map((e) => e.target.runtimeType.toString()).join('>');
      }
      String rr(Finder f) {
        final r = t.getRect(f);
        return '$r(${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}) hit=${hits(f, r.center)}';
      }
      Map<String, Object?> cond(String state) {
        final scr = find.byType(AdminCreateTOScreen);
        final m = scr.evaluate().isEmpty ? MediaQuery.of(t.element(find.text('host'))) : MediaQuery.of(t.element(scr));
        return {
          'entry': 'LOCAL host → Navigator.push(AdminCreateTOScreen(initialBusinessId: $kBiz))',
          'theme': 'RoleTheme.businessAdminTheme', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
          'mqNow': 'padding=${m.padding} viewPadding=${m.viewPadding} viewInsets=${m.viewInsets}',
          'physicalInsetBottomNow': t.view.viewInsets.bottom, 'keyboard': '합성 없음(inset 0)',
          'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK)',
          'data': 'biz approved·license canonical·owner seal·workTypes 1(포장)·daily template 1·wage_config 2026=10320/2027=10700(LOCAL fixture)',
          'createTO': 'callableCreateTO@asia-northeast3 → 호출마다 gate 보류 → internal/LOCAL-C1-CREATE-FAILURE',
          'prefs': 'setMockInitialValues({})', 'clock': '미주입(DateTime.now=$now)', 'date': '${day.year}-${day.month}-${day.day}',
          'state': state, 'calls': calls.toString(), 'fnRequests': fnRequests.length, 'routeResults': results.toString()};
      }
      Map<String, int> snapCalls() => Map<String, int>.from(calls);
      Map<String, int> delta(Map<String, int> a) => {
            for (final k in {...a.keys, ...calls.keys})
              if ((calls[k] ?? 0) != (a[k] ?? 0)) k: (calls[k] ?? 0) - (a[k] ?? 0)};

      // ── 진입 ──
      await t.tap(find.text('host'));
      await frames(20);
      expect(find.byType(AdminCreateTOScreen), findsOneWidget);
      for (final e in allowedEntry.entries) {
        expect(calls[e.key], e.value, reason: '진입 reader ${e.key}');
      }
      expect(calls.keys.where((k) => !allowedEntry.containsKey(k)), isEmpty, reason: '진입 허용 외 0');
      out('진입 calls=$calls');
      final body = find.descendant(of: find.byType(AdminCreateTOScreen), matching: find.byType(Scrollable)).first;

      // ── ① 제목 ──
      const title = 'LOCAL 저장 실패 확인';
      final titleField = find.ancestor(of: find.text('예: 분류작업, 피킹업무'), matching: find.byType(TextFormField)).first;
      await t.ensureVisible(titleField);
      await frames(2);
      await t.tap(titleField);
      await t.enterText(titleField, title);
      await frames(2);
      final titleEdit = find.byWidgetPredicate((w) => w is EditableText && w.controller.text == title); // 입력 뒤 hint 가 사라지므로 값으로 찾는다
      expect(t.widget<EditableText>(titleEdit).controller.text, title);

      // ── ② 날짜(오늘+7, 실제 날짜 UI) ──
      final selector = find.byType(TODateSelector);
      await t.scrollUntilVisible(selector, 120, scrollable: body, maxScrolls: 80);
      bool listMode() => find.descendant(of: selector, matching: find.text('수')).evaluate().isEmpty;
      Finder dayCell(DateTime d) => listMode()
          ? find.ancestor(
              of: find.descendant(of: selector, matching: find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll('⁠', '') == FormatHelper.formatDateKorean(d))),
              matching: find.byType(InkWell)).first
          : find.descendant(of: selector, matching: find.ancestor(of: find.text('${d.day}'), matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null))).first;
      await t.scrollUntilVisible(dayCell(day), 120, scrollable: body, maxScrolls: 120);
      await t.ensureVisible(dayCell(day));
      await frames(4);
      out('② 날짜 배치=${listMode() ? '목록' : '7열'} 셀 ${rr(dayCell(day))}');
      await t.tap(dayCell(day));
      await frames(6);
      List<String> civil() => t.widget<TODateSelector>(selector).selectedDates.map((d) => '${d.year}-${d.month}-${d.day}').toList();
      expect(civil(), ['${day.year}-${day.month}-${day.day}'], reason: '날짜 1개');

      // ── ③ 업무 추가(실제 전체 화면 편집기) ──
      final addText = find.descendant(of: find.byType(AdminCreateTOScreen), matching: find.text('업무 추가'));
      await t.scrollUntilVisible(addText, 120, scrollable: body, maxScrolls: 120);
      await t.ensureVisible(addText);
      await frames(2);
      final beforeWork = snapCalls();
      await t.tap(addText);
      await frames(12);
      final editor = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_WorkDetailEditorScreen');
      expect(editor, findsOneWidget, reason: '업무 편집기 진입');
      final eScroll = find.descendant(of: editor, matching: find.byType(Scrollable)).first;
      Future<void> eShow(Finder f) async {
        // 지연 목록 — 아래로 찾고, 끝까지 없으면 위로 찾는다(화면 밖 항목은 해제돼 있다)
        try {
          await t.scrollUntilVisible(f, 100, scrollable: eScroll, maxScrolls: 60);
        } on StateError {
          await t.scrollUntilVisible(f, -100, scrollable: eScroll, maxScrolls: 80);
        }
        await t.ensureVisible(f);
        await frames(2);
      }
      // 업무 유형은 선택 시트(업무를 선택하세요 → 업무 유형 선택 → 포장)
      final wtHint = find.descendant(of: editor, matching: find.text('업무를 선택하세요')).first;
      await eShow(wtHint);
      await t.tap(wtHint);
      await frames(10);
      expect(find.text('업무 유형 선택'), findsOneWidget, reason: '업무 유형 시트');
      await t.tap(find.text('포장').last);
      await frames(10);
      expect(find.descendant(of: editor, matching: find.text('포장')), findsWidgets, reason: '포장 선택 반영');
      final wageF = find.ancestor(of: find.descendant(of: editor, matching: find.text('금액을 입력하세요')), matching: find.byType(TextFormField)).first;
      await eShow(wageF);
      await t.enterText(wageF, '12000');
      await frames(2);
      final countF = find.ancestor(of: find.descendant(of: editor, matching: find.text('필요한 인원 수를 입력하세요')), matching: find.byType(TextFormField)).first;
      await eShow(countF);
      await t.enterText(countF, '1');
      await frames(2);
      FocusManager.instance.primaryFocus?.unfocus();
      await frames(2);
      final times = FormatHelper.generateTimeList();
      Future<void> pickTime(String hint, String target) async {
        final tile = find.descendant(of: editor, matching: find.text(hint)).first;
        await eShow(tile);
        await t.tap(tile);
        await frames(10);
        final picker = find.byType(CupertinoPicker);
        expect(picker, findsOneWidget, reason: '$hint 피커');
        final ctl = t.widget<CupertinoPicker>(picker).scrollController!;
        final want = times.indexOf(target);
        for (var k = 0; k < 4 && ctl.selectedItem != want; k++) {
          await t.drag(picker, Offset(0, -48.0 * (want - ctl.selectedItem)));
          await frames(16);
        }
        out('   $hint 피커 선택=${times[ctl.selectedItem]} (목표 $target)');
        expect(times[ctl.selectedItem], target, reason: '$hint 실제 스크롤 선택');
        await t.tap(find.descendant(of: find.ancestor(of: picker, matching: find.byType(Column)).first, matching: find.text('확인')));
        await frames(10);
      }
      await pickTime('시작 시간', '09:00');
      await pickTime('종료 시간', '10:00');
      final dayPayAll = find.descendant(of: editor, matching: find.text('당일')); // .first 는 빈 결과에서 throw — 존재 확인은 이걸로
      final dayPay = dayPayAll.first;
      // 급여·정산 설정은 편집기 맨 아래 한 덩어리 — 실제 drag 로 내려가 찾는다
      for (var k = 0; k < 40 && (dayPayAll.evaluate().isEmpty || t.getRect(dayPay).bottom > t.getRect(eScroll).bottom); k++) {
        await t.drag(eScroll, const Offset(0, -150));
        await frames(2);
      }
      out('   당일 칩 ${rr(dayPay)}');
      await t.tap(dayPay);
      await frames(4);
      final save = find.descendant(of: editor, matching: find.text('업무 추가')).last;
      out('③ 편집기 저장 버튼 ${rr(save)}');
      await t.tap(save);
      await frames(16);
      expect(editor, findsNothing, reason: '업무 추가 → 편집기 닫힘');
      final workDelta = delta(beforeWork);
      out('③ 업무 저장 호출 delta=$workDelta');
      expect(workDelta, {'get settings/wage_config': 1}, reason: '업무 저장 = wage_config 읽기 1');
      final section = find.byType(TOWorkDetailsSection);
      await t.scrollUntilVisible(section, 120, scrollable: body, maxScrolls: 80);
      final inputs = t.widget<TOWorkDetailsSection>(section).workDetailInputs!;
      expect(inputs.length, 1);
      final w0 = inputs.single;
      final workSnap = '${w0.workType}·${w0.wageType}·${w0.wage}·${w0.requiredCount}명·${w0.startTime}~${w0.endTime}·휴게${w0.breakMinutes}·지급${w0.payScheduleType}';
      out('   업무 snapshot=$workSnap');
      expect(workSnap, '포장·hourly·12000·1명·09:00~10:00·휴게0·지급same_day');

      // ── ④ 공통 안내 ──
      const text3 = '준비물은 안전화입니다.\n긴 바지를 착용해 주세요.\n정문 안내데스크에서 모입니다.';
      final descF = find.descendant(of: find.byType(TODescriptionSection), matching: find.byType(TextFormField));
      await t.scrollUntilVisible(find.byType(TODescriptionSection), 160, scrollable: body, maxScrolls: 160);
      await t.ensureVisible(descF);
      await frames(2);
      await t.tap(descF);
      await t.enterText(descF, text3);
      await frames(2);
      FocusManager.instance.primaryFocus?.unfocus();
      await frames(4);
      String descText() => t.widget<EditableText>(find.descendant(of: descF, matching: find.byType(EditableText))).controller.text;
      // 바깥 목록을 **페이지 왼쪽 여백**에서 끈다 — 본문 중심이 여러 줄 입력칸이면 그 칸 안쪽 스크롤이 끌기를 먹는다(구현56 관측)
      Future<void> outerScrollTo(Finder f, double dy, {bool untilExists = false}) async {
        for (var k = 0; k < 200; k++) {
          if (untilExists && f.evaluate().isNotEmpty) break; // 상태 읽기용 — 트리에 있으면 충분
          if (f.evaluate().isNotEmpty) {
            final r = t.getRect(f.first);
            final vp = t.getRect(body);
            if (r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5) break;
            if (r.height > vp.height && r.overlaps(vp)) break; // 화면보다 큰 대상(목록 배치 날짜)은 겹치면 도달
          }
          final vp = t.getRect(body);
          await t.dragFrom(Offset(vp.left + 6, vp.center.dy), Offset(0, dy));
          await frames(1);
        }
        await frames(2);
      }
      Future<String> readTitle() async {
        await outerScrollTo(titleEdit, 160); // 제목은 위쪽 — 아래로 끌어 위로 올라간다
        return t.widget<EditableText>(titleEdit).controller.text;
      }
      Future<String> readDesc() async {
        final sec = find.byType(TODescriptionSection);
        // 공통 안내는 맨 아래 — 위로 끌어 내려간다
        await outerScrollTo(sec, -160);
        return descText();
      }
      expect(await readDesc(), text3);
      final cta = find.byType(TOActionButton);
      final ctaInk = find.descendant(of: cta, matching: find.byType(InkWell)).first;
      final ctaR = t.getRect(cta);
      out('④ 유효 폼 · CTA ${rr(cta)} · 물리 inset=${t.view.viewInsets.bottom}');
      if (ctaR.height < 52 || !hits(ctaInk, ctaR.center)) deferred.add('제출 전 CTA 52/hit');
      await vqCapture(t, key, '${c.id}_0a_valid', conditions: cond('유효 폼 완성'));

      // ── ⑤ 저장중 ──
      final beforeSubmit = snapCalls();
      await t.tap(ctaInk);
      await frames(12);
      expect(fnRequests.length, 1, reason: 'callableCreateTO 도달 1');
      expect(gates.single.isCompleted, isFalse, reason: 'gate 보류 중');
      expect(find.byType(AdminCreateTOScreen), findsOneWidget);
      expect(results, isEmpty, reason: '저장중 route 결과 0');
      final loadingText = find.text('공\u2060고 등\u2060록 중\u2060.\u2060.\u2060.');
      final ctaSpinner = find.descendant(of: cta, matching: find.byType(CircularProgressIndicator));
      out('⑤ 저장중 · 전역 로딩 글=${loadingText.evaluate().length} · CTA spinner=${ctaSpinner.evaluate().length} · CTA onTap=${t.widget<InkWell>(ctaInk).onTap != null} · delta=${delta(beforeSubmit)}');
      expect(loadingText, findsOneWidget, reason: '전역 로딩 표시');
      expect(ctaSpinner, findsOneWidget, reason: 'CTA spinner');
      expect(t.widget<InkWell>(ctaInk).onTap, isNull, reason: 'CTA 비활성');
      await vqCapture(t, key, '${c.id}_0b_saving', conditions: cond('저장중(gate 보류)'));

      // ── ⑥ 저장중 재탭·뒤로·시스템 pop 차단 ──
      final backBtn = find.descendant(of: find.byType(AdminCreateTOScreen), matching: find.byType(BackButton)).first;
      final backC = t.getRect(backBtn).center;
      out('⑥ CTA 좌표 hit 경로=${topHit(ctaR.center)} · 뒤로 좌표 hit 경로=${topHit(backC)}');
      await t.tapAt(ctaR.center);
      await frames(4);
      await t.tapAt(backC);
      await frames(6);
      final popHandled = await t.binding.handlePopRoute();
      await frames(6);
      out('   재탭·뒤로·handlePopRoute($popHandled) 뒤 fnRequests=${fnRequests.length} · create=${find.byType(AdminCreateTOScreen).evaluate().length} · 경고=${find.byType(Dialog).evaluate().length} · results=$results');
      expect(fnRequests.length, 1, reason: '저장중 중복 호출 없음');
      expect(find.byType(AdminCreateTOScreen), findsOneWidget, reason: '저장중 route 유지');
      expect(find.byType(Dialog), findsNothing, reason: '저장중 폐기 경고 없음');
      expect(results, isEmpty);
      await vqCapture(t, key, '${c.id}_0c_blocked', conditions: cond('저장중 재탭·뒤로·시스템 pop 뒤'));

      // ── 실패 토스트 계측 도구 ──
      final failToast = find.text('공고 등록에 실패했습니다');
      // 색칠된 토스트 surface = 메시지 Text 의 조상 중 BoxDecoration 색이 있는 Container
      Finder toastSurface() => find.ancestor(
          of: failToast,
          matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).color != null && (w.decoration as BoxDecoration).boxShadow != null)).first;
      final ctaLabel = find.descendant(of: cta, matching: find.text('공고 등록'));
      // 공개 widget/controller 에서 읽는 UI 의미 snapshot — 지연 목록이라 각 섹션까지 실제 끌기(왼쪽 여백) 뒤 읽는다
      Future<String> uiSnap() async {
        final ti = await readTitle();
        await outerScrollTo(find.byType(TOWorkDetailsSection), -160, untilExists: true);
        final w = t.widget<TOWorkDetailsSection>(find.byType(TOWorkDetailsSection)).workDetailInputs!.single;
        final de = await readDesc();
        return 'title=$ti · desc=${de.replaceAll('\n', '⏎')} · work=${w.workType}/${w.wageType}/${w.wage}/${w.requiredCount}/${w.startTime}~${w.endTime}/휴게${w.breakMinutes}/${w.payScheduleType}';
      }
      final ui0 = 'title=$title · desc=${text3.replaceAll('\n', '⏎')} · work=포장/hourly/12000/1/09:00~10:00/휴게0/same_day';
      void judgeToastVsCta(String tag) {
        expect(failToast, findsOneWidget, reason: '$tag 실패 문구 전문');
        final sR = t.getRect(toastSurface());
        final mR = t.getRect(failToast);
        final cR = t.getRect(cta);
        final lR = t.getRect(ctaLabel);
        final overlap = sR.overlaps(cR) && sR.intersect(cR).height > 0.5 && sR.intersect(cR).width > 0.5;
        final labelCovered = sR.overlaps(lR) && sR.intersect(lR).height > 0.5;
        out('   [$tag] 토스트 surface=$sR · 메시지 Text=$mR · CTA=$cR(${cR.height.toStringAsFixed(1)}) · CTA 라벨=$lR · surface↔CTA 겹침=$overlap · 라벨 가림=$labelCovered · CTA 중심 hit 경로=${topHit(cR.center)}');
        if (overlap) deferred.add('$tag 토스트 surface 가 CTA 와 겹침($sR ↔ $cR)');
        if (labelCovered) deferred.add('$tag 토스트가 CTA 라벨을 가림');
        if (sR.top < 0 || sR.bottom > c.h) deferred.add('$tag 토스트 화면 밖');
        if (cR.height < 52) deferred.add('$tag CTA 높이 ${cR.height}');
      }

      // ── _1_failure ──
      gates[0].complete();
      await frames(12);
      out('① 첫 실패 · 로딩 글=${loadingText.evaluate().length} · spinner=${ctaSpinner.evaluate().length} · CTA onTap=${t.widget<InkWell>(ctaInk).onTap != null} · delta(제출 전 대비)=${delta(beforeSubmit)}');
      expect(loadingText, findsNothing);
      expect(ctaSpinner, findsNothing);
      expect(t.widget<InkWell>(ctaInk).onTap, isNotNull, reason: 'CTA 재활성');
      expect(find.byType(AdminCreateTOScreen), findsOneWidget);
      expect(results, isEmpty);
      expect(delta(beforeSubmit), {'get users/$kOwner': 1, 'get businesses/$kBiz': 1, 'functions callableCreateTO': 1});
      judgeToastVsCta('① 첫 실패');
      await vqCapture(t, key, '${c.id}_1_failure', conditions: cond('첫 실패 · 토스트 표시 중'));

      // ── _2_retry_while_toast: 토스트가 떠 있는 동안 같은 CTA 실제 탭 ──
      await t.pump(const Duration(milliseconds: 500));
      expect(failToast, findsOneWidget, reason: '재탭 시점 토스트 표시 중');
      final beforeRetry = snapCalls();
      final cR = t.getRect(cta);
      out('② 재탭 직전 CTA 중심 hit 경로=${topHit(cR.center)} · CTA InkWell 포함=${hits(ctaInk, cR.center)}');
      await t.tapAt(cR.center);
      await frames(12);
      expect(fnRequests.length, 2, reason: '토스트 표시 중 재탭 → 새 gate 도달');
      expect(gates[1].isCompleted, isFalse);
      expect(loadingText, findsOneWidget, reason: '재시도 로딩');
      expect(t.widget<InkWell>(ctaInk).onTap, isNull, reason: '재시도 중 CTA 비활성');
      expect(results, isEmpty);
      final oldToast = failToast.evaluate().length;
      out('② 재시도 저장중 · 이전 토스트 잔류=$oldToast(${oldToast > 0 ? t.getRect(toastSurface()) : '-'}) · 로딩 ${loadingText.evaluate().isEmpty ? '-' : t.getRect(loadingText)}');
      if (oldToast > 0) {
        final sR = t.getRect(toastSurface());
        final lgR = t.getRect(loadingText);
        if (sR.overlaps(lgR)) deferred.add('② 이전 토스트가 로딩 문구와 겹침');
      }
      await vqCapture(t, key, '${c.id}_2_retry_while_toast', conditions: cond('토스트 표시 중 재탭 → 재시도 저장중'));

      // 요청 의미 비교(사용자 의미 필드 + 날짜 wire↔KST civil)
      final p1 = Map<Object?, Object?>.from((fnRequests[0]['parameters'] as Map)['toData'] as Map);
      final p2 = Map<Object?, Object?>.from((fnRequests[1]['parameters'] as Map)['toData'] as Map);
      final diffKeys = {...p1.keys, ...p2.keys}.where((k) => p1[k].toString() != p2[k].toString()).toList();
      String kst(Object? ms) => ms is int ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).add(const Duration(hours: 9)).toIso8601String().substring(0, 16) : '$ms';
      out('   요청1 키=${p1.keys.toList()}');
      out('   요청1 title=${p1['title']} type=${p1['type']} publishMode=${p1['publishMode']}(UI immediate → wire deferred) isPublished=${p1['isPublished']} businessId=${p1['businessId']} hoursBeforeStart=${p1['hoursBeforeStart']} deadlineType=${p1['deadlineType']} postingDurationDays=${p1['postingDurationDays']}');
      out('   요청1 날짜 wire: rangeStart=${p1['rangeStart']}(KST ${kst(p1['rangeStart'])}) rangeEnd=${p1['rangeEnd']}(KST ${kst(p1['rangeEnd'])}) dates=${p1['dates']}');
      out('   요청 간 다른 키=$diffKeys');
      for (final k in const ['businessId', 'title', 'description', 'type', 'workDetails', 'publishMode', 'isPublished', 'hoursBeforeStart', 'deadlineType', 'postingDurationDays', 'rangeStart', 'rangeEnd', 'dates']) {
        expect(p2[k].toString(), p1[k].toString(), reason: '재시도 요청 $k 동일');
      }
      expect(p1['title'], title);
      expect(p1['description'], text3);

      // ── _3_retry_failure ──
      gates[1].complete();
      await frames(12);
      expect(loadingText, findsNothing);
      expect(ctaSpinner, findsNothing);
      expect(t.widget<InkWell>(ctaInk).onTap, isNotNull);
      expect(results, isEmpty, reason: '재시도 실패 뒤 route 결과 0');
      expect(delta(beforeRetry), {'get users/$kOwner': 1, 'get businesses/$kBiz': 1, 'functions callableCreateTO': 1});
      judgeToastVsCta('③ 재시도 실패');
      await vqCapture(t, key, '${c.id}_3_retry_failure', conditions: cond('재시도 실패 · 토스트 표시 중'));
      await t.pump(const Duration(seconds: 5)); // 오류 토스트 4s
      await frames(4);
      expect(failToast, findsNothing, reason: '토스트 타이머 소진');
      expect(await uiSnap(), ui0, reason: '두 실패 뒤 UI 의미 보존(제목·원문·업무)');
      expect(await readDesc(), text3);
      expect(await readTitle(), title);
      await outerScrollTo(selector, -160, untilExists: true);
      expect(civil(), ['${day.year}-${day.month}-${day.day}'], reason: '날짜 보존');

      // 정확 allowlist(셀 시작부터 누적, 지우지 않음)
      const expectedFinal = {
        'get businesses/$kBiz': 3, // 진입 1 + 제출 2
        'get users/$kOwner': 3, // 진입 1 + 제출 2(seal)
        'query businesses/$kBiz/workTypes': 1,
        'query businesses/$kBiz/contract_templates': 1,
        'get settings/wage_config': 1, // 업무 저장
        'functions callableCreateTO': 2,
      };
      out('최종 calls=$calls · fnRequests=${fnRequests.length} · gates 완료=${gates.map((g) => g.isCompleted).toList()}');
      expect(calls, expectedFinal, reason: '정확 allowlist — 그 밖 read/write/Functions 0');
      FlutterError.onError = prev;
      out('overflows(${overflows.length})=${overflows.join(' | ')}');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
      out('deferred(${deferred.length})=${deferred.join(' | ')}');
      expect(deferred, isEmpty, reason: deferred.join(' | '));
    });
  }
}
