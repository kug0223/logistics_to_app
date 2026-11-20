// ignore_for_file: depend_on_referenced_packages
// [DU1 구현53 · 감사53 §6] C1-CREATE-CALENDAR-MONTH-BOUNDARY-B/W — 월말 시작 → 다음 달 이동 → 다음 달 끝 날짜(구현50 시험 하네스 복사).
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
import 'package:ALfit/screens/business_admin/to_management/widgets/to_date_selector.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
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
    (id: 'C1-CREATE-CALENDAR-MONTH-BOUNDARY-B', w: 320.0, h: 640.0, s: 2.0),
    (id: 'C1-CREATE-CALENDAR-MONTH-BOUNDARY-W', w: 360.0, h: 780.0, s: 1.0),
  ]) {
    testWidgets('${c.id} 공고 등록 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 월말 시작→다음 달→끝 날짜', (t) async {
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
      final today = DateTime(now.year, now.month, now.day);
      // [구현53 · 감사53 §6] 월말 d → 다음 달 d+2 (실행일 기준 첫 미래 월말)
      var start = DateTime(today.year, today.month + 1, 0);
      if (!start.isAfter(today)) start = DateTime(today.year, today.month + 2, 0);
      final end = DateTime(start.year, start.month, start.day + 2);
      out('${c.id} 실행 시각=$now tz=${now.timeZoneName}(${now.timeZoneOffset}) 선택=${start.toIso8601String().substring(0, 10)}~${end.toIso8601String().substring(0, 10)}');
      expect(start.isAfter(today), isTrue, reason: '미래 월말');
      expect(end.month != start.month, isTrue, reason: '월 경계를 넘는다');
      expect(!end.isAfter(today.add(const Duration(days: 60))), isTrue, reason: '오늘~60일 안');
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
            'prefs': 'setMockInitialValues({})', 'clock': '미주입(DateTime.now=$now)', 'dates': '${start.day}~${end.day}',
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

      final selector = find.byType(TODateSelector);
      final body = find.descendant(of: find.byType(AdminCreateTOScreen), matching: find.byType(Scrollable)).first;
      // 날짜 조작 영역 — 목록 배치(구현52)면 그 날짜 줄의 InkWell, 7열 달력이면 그 칸의 GestureDetector
      Finder listRowText(DateTime d) => find.descendant(
          of: selector,
          matching: find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll('⁠', '') == FormatHelper.formatDateKorean(d)));
      // 목록 배치에는 요일 머리가 없다(월이 바뀌어도 판정이 시작일 유무에 묶이지 않게)
      bool listMode() => find.descendant(of: selector, matching: find.text('수')).evaluate().isEmpty;
      Finder dayCell(DateTime d) => listMode()
          ? find.ancestor(of: listRowText(d), matching: find.byType(InkWell)).first
          : find.descendant(
              of: selector,
              matching: find.ancestor(of: find.text('${d.day}'), matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null))).first;
      await t.scrollUntilVisible(dayCell(start), 120, scrollable: body, maxScrolls: 120);
      await t.ensureVisible(dayCell(start)); // 시작일(월말) 조작 영역 전체를 본문 안으로
      await _settle(t, 4);
      final pos = t.state<ScrollableState>(body).position;
      final p0 = pos.pixels;
      out('① 첫 탭 전 배치=${listMode() ? '목록' : '7열 달력'} · 월말 시작 셀 ${rr(dayCell(start))} · 스크롤 ${p0.toStringAsFixed(1)}/${pos.maxScrollExtent.toStringAsFixed(1)}');
      final sR = t.getRect(dayCell(start));
      final sMin = sR.width < sR.height ? sR.width : sR.height;
      if (sMin < 48) {
        if (listMode()) {
          deferred.add('F50-1 조작 영역 최소 변 ${sMin.toStringAsFixed(1)} < 48');
        } else {
          out('   F50-1 잔여 제약(7열 달력): 조작 영역 최소 변 ${sMin.toStringAsFixed(1)} < 48');
        }
      }
      await vqCapture(t, key, '${c.id}_1_before', conditions: cond('월말 시작일 탭 전'));
      List<String> civil() => t.widget<TODateSelector>(selector).selectedDates.map((d) => '${d.year}-${d.month}-${d.day}').toList();
      String ymd(DateTime d) => '${d.year}-${d.month}-${d.day}';
      expect(civil(), isEmpty, reason: '첫 탭 전 선택 0');

      // ② 월말 시작일 탭 → 첫 탭 자리 안내(추가 안내 스크롤 전 관측)
      await t.tap(dayCell(start));
      await _settle(t, 8);
      expect(civil(), [ymd(start)], reason: '첫 탭 → [월말]');
      final vp = t.getRect(body);
      bool inside(Rect r) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5;
      final inline = find.byKey(const ValueKey('inline-range-hint'));
      final headBox = find.byKey(const ValueKey('hint'));
      bool guidanceVisible() =>
          (headBox.evaluate().isNotEmpty && inside(t.getRect(headBox))) || (inline.evaluate().isNotEmpty && inside(t.getRect(inline)));
      out('② 첫 탭 → ${civil()} · viewport=$vp · 탭 자리 안내 ${inline.evaluate().isEmpty ? '없음' : t.getRect(inline)} · 지시 보임=${guidanceVisible()} · 시작 셀 보임=${inside(t.getRect(dayCell(start)))}');
      if (!guidanceVisible()) deferred.add('F50-2 첫 탭 직후 끝 날짜 지시가 viewport 밖');
      final hintRich = find.descendant(of: headBox, matching: find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText(includeSemanticsLabels: false).replaceAll('⁠', '').contains('종료 날짜를 탭하세요')));
      expect(hintRich, findsOneWidget, reason: '머리 범위 안내');
      // Semantics — 원문·제어문자 없음·1회(구현51)
      void checkSemantics(String when) {
        final labels = <String>[];
        void walk(SemanticsNode n) {
          if (n.label.isNotEmpty) labels.add(n.label);
          n.visitChildren((ch) {
            walk(ch);
            return true;
          });
        }
        walk(t.getSemantics(find.byType(AdminCreateTOScreen)));
        final ctrl = RegExp('[\u2060\u200B\u00A0]');
        final lines = labels.expand((l) => l.split('\n')).where((l) => l.replaceAll(ctrl, '').contains('종료 날짜를 탭하세요')).toList();
        out('   Semantics($when) 안내 줄=$lines');
        expect(lines.length, 1, reason: '$when 안내 문장 1번');
        expect(ctrl.hasMatch(lines.single), isFalse, reason: '$when 표시 전용 문자 없음');
        expect(lines.single, '${FormatHelper.formatDateKorean(start)} · 종료 날짜를 탭하세요', reason: '$when 원문');
      }
      checkSemantics('첫 탭');
      await vqCapture(t, key, '${c.id}_2_hint', conditions: cond('월말 첫 탭 → 탭 자리 안내(추가 스크롤 전)'));

      // ③ 실제 스크롤로 월 머리에 돌아가 다음 달 화살표 탭 — 범위 시작·선택 보존
      final nextBtn = find.ancestor(of: find.descendant(of: selector, matching: find.byIcon(Icons.chevron_right)), matching: find.byType(IconButton)).first;
      var drags = 0;
      while (!(inside(t.getRect(nextBtn))) && drags < 80) {
        await t.drag(body, const Offset(0, 120));
        await _settle(t, 2);
        drags++;
      }
      final p1 = pos.pixels;
      out('③ 월 머리까지 위로 끌기 $drags회 · 이동 ${(p0 - p1).toStringAsFixed(1)}px · 다음 달 버튼 ${rr(nextBtn)}');
      expect(inside(t.getRect(nextBtn)), isTrue, reason: '다음 달 버튼 도달');
      await vqCapture(t, key, '${c.id}_3_monthhead', conditions: cond('다음 달 버튼 앞(시작일 선택 상태)'));
      await t.tap(nextBtn);
      await _settle(t, 8);
      expect(civil(), [ymd(start)], reason: '다음 달 이동 뒤 시작일 선택 보존');
      expect(hintRich, findsOneWidget, reason: '다음 달 이동 뒤 범위 시작(머리 안내) 보존');
      final monthTitle = FormatHelper.formatYearMonth(end);
      out('③ 다음 달 이동 → ${civil()} · 월 제목 "$monthTitle" ${findVisibleText(monthTitle).evaluate().isEmpty ? '없음' : t.getRect(findVisibleText(monthTitle).first)} · 이동 직후 지시 보임=${guidanceVisible()} · 탭 자리 안내 ${inline.evaluate().isEmpty ? '없음' : t.getRect(inline)}');
      if (!guidanceVisible()) deferred.add('F50-2 다음 달 이동 직후 끝 날짜 지시가 viewport 밖');
      checkSemantics('다음 달 이동');
      await vqCapture(t, key, '${c.id}_4_nextmonth', conditions: cond('다음 달 이동 직후'));

      // ④ 다음 달 끝 날짜(d+2) 실제 탭
      final p2 = pos.pixels;
      await t.scrollUntilVisible(dayCell(end), 120, scrollable: body, maxScrolls: 120);
      await t.ensureVisible(dayCell(end));
      await _settle(t, 4);
      out('④ 끝 날짜까지 이동 ${(pos.pixels - p2).toStringAsFixed(1)}px · 끝 셀 ${rr(dayCell(end))}');
      final eR = t.getRect(dayCell(end));
      final eMin = eR.width < eR.height ? eR.width : eR.height;
      if (eMin < 48 && listMode()) deferred.add('F50-1 끝 조작 영역 최소 변 ${eMin.toStringAsFixed(1)} < 48');
      await t.tap(dayCell(end));
      await _settle(t, 10);
      expect(hintRich, findsNothing, reason: '안내 소멸');
      expect(inline, findsNothing, reason: '탭 자리 안내 소멸');
      final expected = [for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) ymd(d)];
      out('④ 끝 탭 → ${civil()} (기대 $expected)');
      expect(civil(), expected, reason: '월 경계 정확 3일(DateTime 연산 기준)');
      expect(find.byType(AdminCreateTOScreen), findsOneWidget, reason: '폼 유지');
      await vqCapture(t, key, '${c.id}_5_range', conditions: cond('다음 달 끝 날짜 탭 → 3일'));

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
