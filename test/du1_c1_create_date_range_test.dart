// ignore_for_file: depend_on_referenced_packages
// [DU1 구현50 · 감사50 §5] S030 C1-CREATE-DATE-RANGE-B/W — 공고 등록(단기) 실제 진입 → 첫 날짜 탭 → 범위 안내 → 끝 날짜 탭.
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

/// [date1 · F268-SAT-CLOCK/F269-C1-ROW-CLOCK] 자정 가드 — 로컬 또는 KST 자정까지 [margin] 보다 적게 남았으면 자정을 넘길 때까지 실제로 기다린다.
///   setUp(실시간 영역)에서 부른다. 그 뒤 잡은 '오늘'은 이 시험이 끝날 때까지(< margin) 화면의 DateTime.now() 와 같은 날이다.
Future<void> _midnightGuard(Duration margin) async {
  Duration left(DateTime n) => DateTime(n.year, n.month, n.day + 1).difference(n);
  final local = DateTime.now();
  final k = local.toUtc().add(const Duration(hours: 9));
  final kst = DateTime(k.year, k.month, k.day, k.hour, k.minute, k.second, k.millisecond);
  final wait = [left(local), left(kst)].where((d) => d < margin).fold<Duration>(Duration.zero, (a, b) => b > a ? b : a);
  if (wait > Duration.zero) {
    // ignore: avoid_print
    print('[date1] 자정 가드 — ${wait.inSeconds + 1}초 기다림(로컬 $local)');
    await Future<void>.delayed(wait + const Duration(seconds: 1));
  }
}

void main() {
  final calls = <String, int>{};
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUp(() => _midnightGuard(const Duration(seconds: 180)));
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
    (id: 'C1-CREATE-DATE-RANGE-B', w: 320.0, h: 640.0, s: 2.0, off: 3),
    (id: 'C1-CREATE-DATE-RANGE-W', w: 360.0, h: 780.0, s: 1.0, off: 3),
    // [구현52 · 감사51 §5·감사52 §5] 달력 식별·조작·첫 탭 피드백 — 두 자리 날짜(d,d+1,d+2) 대표
    (id: 'C1-CREATE-CALENDAR-READABILITY-B', w: 320.0, h: 640.0, s: 2.0, off: 10),
    (id: 'C1-CREATE-CALENDAR-READABILITY-W', w: 360.0, h: 780.0, s: 1.0, off: 10),
  ]) {
    testWidgets('${c.id} 공고 등록 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 첫 날짜→범위 안내→끝 날짜', (t) async {
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
      // [date1 · F269-C1-ROW-CLOCK] 같은 달 안 미래 3일(off=10 은 두 자리) — 이번 달에 안 들어가면 다음 달(달력 '다음 달' 단추)에서 같은 조건으로.
      //   옛: 이번 달에 안 들어가면 전제 expect 실패(READABILITY 2 건 · 월말 실행 때마다).
      var start = today.add(Duration(days: c.off));
      if (start.month != today.month || start.add(const Duration(days: 2)).month != today.month) {
        start = DateTime(today.year, today.month + 1, c.off == 10 ? 10 : 1);
      }
      final nextMonth = start.month != today.month;
      final end = start.add(const Duration(days: 2));
      out('${c.id} 실행 시각=$now tz=${now.timeZoneName}(${now.timeZoneOffset}) 선택=${start.toIso8601String().substring(0, 10)}~${end.toIso8601String().substring(0, 10)}');
      expect(start.isAfter(today) && start.month == end.month, isTrue, reason: '같은 달 안 미래 3일(실행일 기준 · 이번 달에 없으면 다음 달 $nextMonth)');
      if (c.off == 10) {
        expect(start.day >= 10 && end.day >= 10, isTrue, reason: '두 자리 날짜 d,d+1,d+2(감사52 §5)');
      }
      final deferred = <String>[]; // 캡처를 남긴 뒤 마지막에 판정할 조건(before 에서도 증거가 남게)

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
      List<String> lineSegs(Finder rich) {
        final rp = t.renderObject<RenderParagraph>(rich);
        final plain = rp.text.toPlainText(includeSemanticsLabels: false); // 표시 글자 기준(접근성 이름 아님)
        final tp = TextPainter(text: rp.text, textDirection: TextDirection.ltr, textScaler: rp.textScaler)..layout(maxWidth: rp.size.width);
        final segs = <String>[];
        var s0 = 0;
        for (final lm in tp.computeLineMetrics()) {
          final e = tp.getLineBoundary(tp.getPositionForOffset(Offset(tp.width, lm.baseline - lm.ascent + lm.height / 2))).end;
          segs.add(plain.substring(s0, e).replaceAll('⁠', ''));
          s0 = e;
        }
        final full = tp.height;
        tp.dispose();
        segs.add('(필요높이 ${full.toStringAsFixed(1)} · 실제 ${rp.size.height.toStringAsFixed(1)})');
        return segs;
      }

      final selector = find.byType(TODateSelector);
      final body = find.descendant(of: find.byType(AdminCreateTOScreen), matching: find.byType(Scrollable)).first;
      // 날짜 조작 영역 — 목록 배치(구현52)면 그 날짜 줄의 InkWell, 7열 달력이면 그 칸의 GestureDetector
      Finder listRowText(DateTime d) => find.descendant(
          of: selector,
          matching: find.byWidgetPredicate((w) => w is Text && (w.data ?? '').replaceAll('⁠', '') == FormatHelper.formatDateKorean(d)));
      bool listMode() => listRowText(start).evaluate().isNotEmpty;
      Finder dayCell(DateTime d) => listMode()
          ? find.ancestor(of: listRowText(d), matching: find.byType(InkWell)).first
          : find.descendant(
              of: selector,
              matching: find.ancestor(of: find.text('${d.day}'), matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null))).first;
      Finder dayText(DateTime d) => listMode() ? listRowText(d).first : find.descendant(of: selector, matching: find.text('${d.day}')).first;
      if (nextMonth) {
        // [date1] 다음 달로 — 달력 머리 '다음 달' 단추(chevron_right) 1 개를 실제로 누른다
        final nextBtn = find.descendant(of: selector, matching: find.byIcon(Icons.chevron_right));
        expect(nextBtn, findsOneWidget, reason: '다음 달 단추 1');
        await t.ensureVisible(nextBtn);
        await _settle(t, 2);
        await t.tap(nextBtn);
        await _settle(t, 6);
        out('${c.id} 다음 달로 이동 → ${start.year}-${start.month}');
      }
      await t.scrollUntilVisible(dayCell(end), 120, scrollable: body, maxScrolls: 80);
      await t.ensureVisible(dayCell(start)); // 시작일 조작 영역 전체를 본문 안으로(가림 없는 탭)
      await _settle(t, 4);
      await _settle(t, 2);
      final headerTitle = findVisibleText('근무 날짜 선택');
      out('① 첫 탭 전 헤더 ${headerTitle.evaluate().isEmpty ? '없음' : rr(headerTitle.first)} · 배치=${listMode() ? '목록' : '7열 달력'} · 시작 셀 ${rr(dayCell(start))} · 끝 셀 ${rr(dayCell(end))}');
      // [구현52 F50-1] 식별·조작 영역 — 시작일과 다음 날의 글·조작 영역 경계
      final mid = start.add(const Duration(days: 1));
      final aR = t.getRect(dayCell(start)), bR = t.getRect(dayCell(mid));
      final aT = t.getRect(dayText(start)), bT = t.getRect(dayText(mid));
      final areasOverlap = aR.overlaps(bR) && aR.intersect(bR).width > 0.5 && aR.intersect(bR).height > 0.5;
      // [date1 · F269-C1-ROW-CLOCK] 7열 달력은 일요일부터 새 줄 — 토→일이면 다음 날 글은 다음 줄. 같은 줄 = 수평 간격 · 다음 줄 = 수직 간격 + 글 겹침 0 을 따로 잰다.
      //   옛: 무조건 bT.left - aT.right(토→일이면 -268.5 같은 값이 '간격'으로 읽혀 거짓 실패).
      final sameRow = listMode() || (bT.center.dy - aT.center.dy).abs() < aT.height / 2;
      if (!listMode()) {
        expect(sameRow, start.weekday != DateTime.saturday, reason: 'F50-1 줄 판정 = 달력 규칙(토요일 다음 날만 다음 줄) · 시작 요일 ${start.weekday}');
      }
      final textsOverlap = aT.overlaps(bT) && aT.intersect(bT).width > 0.5 && aT.intersect(bT).height > 0.5;
      if (textsOverlap) deferred.add('F50-1 인접 날짜 글 겹침');
      final textGap = listMode() ? (bT.top - aT.bottom) : (sameRow ? (bT.left - aT.right) : (bT.top - aT.bottom));
      final minSide = [aR.width, aR.height, bR.width, bR.height].reduce((x, y) => x < y ? x : y);
      out('   F50-1 시작 글 $aT · 다음 날 글 $bT · 글 사이 간격=${textGap.toStringAsFixed(1)} · 조작 영역 겹침=$areasOverlap · 최소 변=${minSide.toStringAsFixed(1)}');
      if (areasOverlap) deferred.add('F50-1 인접 날짜 조작 영역 겹침');
      if (textGap < 4) deferred.add('F50-1 인접 날짜 글 간격 ${textGap.toStringAsFixed(1)} < 4(이어 보임)');
      if (!listMode()) {
        // [date1] 실행일과 무관한 고정 경계 — 보이는 달의 첫 토→일 쌍 · 말일(날짜 선택과 별개로 매 실행 같은 규칙을 잰다)
        final last = DateTime(start.year, start.month + 1, 0);
        var sat = DateTime(start.year, start.month, 1);
        while (sat.weekday != DateTime.saturday) {
          sat = sat.add(const Duration(days: 1));
        }
        final sun = sat.add(const Duration(days: 1));
        final sR = t.getRect(dayText(sat)), uR = t.getRect(dayText(sun));
        out('   경계 토(${sat.day}) $sR → 일(${sun.day}) $uR · 말일 ${last.day} ${t.getRect(dayText(last))}');
        expect(uR.top >= sR.bottom - 0.5 && uR.left < sR.left, isTrue, reason: '토(${sat.day})→일(${sun.day}) = 다음 줄 맨 왼쪽 쪽');
        expect(sR.overlaps(uR), isFalse, reason: '토→일 글 겹침 0');
        expect(uR.top - sR.bottom, greaterThanOrEqualTo(4.0), reason: '토→일 줄 사이 수직 간격 4 이상');
        final lR = t.getRect(dayText(last));
        for (var dd = 1; dd < last.day; dd++) {
          expect(t.getRect(dayText(DateTime(start.year, start.month, dd))).top <= lR.top + 0.5, isTrue, reason: '말일 ${last.day} 이 마지막 줄($dd일 이 그 아래 0)');
        }
      }
      // 7열 달력은 320·360 폭에서 칸 너비 48 이 불가능(7×48=336) — 목록 배치가 아닌 7열이면 48 미달을 **남는 제약**으로 기록하고 해소로 쓰지 않는다
      if (minSide < 48) {
        if (listMode()) {
          deferred.add('F50-1 조작 영역 최소 변 ${minSide.toStringAsFixed(1)} < 48');
        } else {
          out('   F50-1 잔여 제약(7열 달력): 조작 영역 최소 변 ${minSide.toStringAsFixed(1)} < 48');
        }
      }
      await vqCapture(t, key, '${c.id}_1_before', conditions: cond('첫 날짜 탭 전'));
      // [구현51 · 후속51 §2-3] 선택 배열 0 → 1 → 3 을 civil 날짜로 명시 assertion
      List<String> civil() => t.widget<TODateSelector>(selector).selectedDates.map((d) => '${d.year}-${d.month}-${d.day}').toList();
      String ymd(DateTime d) => '${d.year}-${d.month}-${d.day}';
      expect(civil(), isEmpty, reason: '첫 탭 전 선택 0');

      // ② 첫 날짜 탭 → 범위 안내. 다음 날 쪽 경계 3px 안쪽을 눌러 오탭 없이 시작일만 바뀌는지 본다.
      final tapAt = listMode() ? Offset(aR.center.dx, aR.bottom - 3) : Offset(aR.right - 3, aR.center.dy);
      out('② 탭 지점(다음 날 쪽 경계 3px 안) $tapAt');
      await t.tapAt(tapAt);
      await _settle(t, 8);
      expect(civil(), [ymd(start)], reason: '첫 탭 → 시작일 1개(첫 탭도 선택에 추가)·경계 탭이 다음 날로 새지 않음');
      out('② 첫 탭 → selectedDates=${civil()}');
      // [구현52 F50-2] 하네스 추가 스크롤 없이 — 본문 viewport(AppBar·고정 CTA 제외) 안에 끝 날짜 지시가 보이는가
      final vp = t.getRect(body);
      final inline = find.byKey(const ValueKey('inline-range-hint'));
      final headBox = find.byKey(const ValueKey('hint'));
      bool inside(Rect r) => r.top >= vp.top - 0.5 && r.bottom <= vp.bottom + 0.5;
      final headVisible = headBox.evaluate().isNotEmpty && inside(t.getRect(headBox));
      final inlineVisible = inline.evaluate().isNotEmpty && inside(t.getRect(inline));
      out('   F50-2 본문 viewport=$vp · 머리 안내 ${headBox.evaluate().isEmpty ? '없음' : t.getRect(headBox)} 보임=$headVisible · 탭 자리 안내 ${inline.evaluate().isEmpty ? '없음' : t.getRect(inline)} 보임=$inlineVisible · 시작 셀 ${t.getRect(dayCell(start))} 보임=${inside(t.getRect(dayCell(start)))}');
      if (!headVisible && !inlineVisible) deferred.add('F50-2 첫 탭 직후 끝 날짜 지시가 본문 viewport 밖');
      if (!inside(t.getRect(dayCell(start)))) deferred.add('F50-2 첫 탭 직후 시작일이 viewport 밖');
      final hintRich = find.descendant(of: headBox, matching: find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText(includeSemanticsLabels: false).replaceAll('⁠', '').contains('종료 날짜를 탭하세요')));
      expect(hintRich, findsOneWidget, reason: '범위 안내 표시');
      final hintBox = headBox;
      // 닫기 = 실제 누르는 GestureDetector 영역(아이콘 자체 아님)
      final close = find.ancestor(of: find.descendant(of: hintBox, matching: find.byIcon(Icons.close)), matching: find.byWidgetPredicate((w) => w is GestureDetector && w.onTap != null)).first;
      out('② 안내 전문="${t.widget<RichText>(hintRich).text.toPlainText(includeSemanticsLabels: false).replaceAll('⁠', '')}" rect=${t.getRect(hintRich)} 상자=${t.getRect(hintBox)}');
      out('   줄=[${lineSegs(hintRich).join(' / ')}]');
      out('   닫기 ${rr(close)} · 시작 셀(선택) ${rr(dayCell(start))}');
      // [구현51 · 후속51 §2-2] 실제 Semantics 트리의 접근성 이름 — 원문 그대로·표시 전용 문자 없음·중복 없음
      final expectedName = '${FormatHelper.formatDateKorean(start)} · 종료 날짜를 탭하세요';
      final labels = <String>[];
      void walk(SemanticsNode n) {
        if (n.label.isNotEmpty) labels.add(n.label);
        n.visitChildren((ch) {
          walk(ch);
          return true;
        });
      }
      walk(t.getSemantics(find.byType(AdminCreateTOScreen))); // 화면 루트 Semantics 노드부터
      // 안내 글은 같은 경계 안 다른 글(달력 제목·요일·날짜)과 한 Semantics 노드로 합쳐진다(기존 트리 구조) —
      //   노드 이름을 줄로 나눠 안내 줄을 본다.
      final ctrl = RegExp('[\u2060\u200B\u00A0]');
      final hintNodes = labels.where((l) => l.replaceAll(ctrl, '').contains('종료 날짜를 탭하세요')).toList();
      out('   Semantics 안내 노드 수=${hintNodes.length}');
      expect(hintNodes.length, 1, reason: '안내를 담은 접근성 노드 1개(중복 없음)');
      final nodeLines = hintNodes.single.split('\n');
      final hintLines = nodeLines.where((l) => l.replaceAll(ctrl, '').contains('종료 날짜를 탭하세요')).toList();
      out('   안내 줄=${hintLines.map((l) => '"$l" len=${l.length} U+2060=${l.contains('⁠')} U+200B=${l.contains('​')} U+00A0=${l.contains(' ')}').toList()} · 노드 전체 줄수=${nodeLines.length} 노드 전체 제어문자=${ctrl.hasMatch(hintNodes.single)} 노드 앞 3줄=${nodeLines.take(3).toList()}');
      expect(hintLines.length, 1, reason: '안내 문장 1번만(중복 없음)');
      expect(ctrl.hasMatch(hintLines.single), isFalse, reason: '안내 접근성 이름에 표시 전용 문자 없음');
      expect(hintLines.single, expectedName, reason: '원문 그대로');
      // 안내 내용 높이 보존 · 닫기 48·중심 hit
      final hp = t.renderObject<RenderParagraph>(hintRich);
      final need = (TextPainter(text: hp.text, textDirection: TextDirection.ltr, textScaler: hp.textScaler)..layout(maxWidth: hp.size.width)).height;
      expect(hp.size.height + 0.5 >= need, isTrue, reason: '안내 글 잘림 없음(필요 $need · 실제 ${hp.size.height})');
      final cr = t.getRect(close);
      expect(cr.width >= 48 && cr.height >= 48, isTrue, reason: '닫기 48×48');
      await vqCapture(t, key, '${c.id}_2_hint', conditions: cond('첫 날짜 탭 → 범위 안내(탭 위치 그대로)'));
      // 안내 상자를 화면에 올려 실제 표시·잘림·닫기 크기를 본다(위로 실제 스크롤)
      await t.scrollUntilVisible(hintBox, -120, scrollable: body, maxScrolls: 80);
      await _settle(t, 2);
      out('②b 안내 보이게 스크롤 → 상자 ${rr(hintBox)} · 글 ${t.getRect(hintRich)} · 닫기 ${rr(close)}');
      await vqCapture(t, key, '${c.id}_2b_hint_view', conditions: cond('범위 안내 상자 화면 안'));
      await t.scrollUntilVisible(dayCell(end), 120, scrollable: body, maxScrolls: 80);
      await _settle(t, 2);

      // ③ 끝 날짜 탭 → 정확 3일
      await t.tap(dayCell(end));
      await _settle(t, 10);
      expect(hintRich, findsNothing, reason: '안내 소멸');
      final badge = findVisibleText('3일');
      expect(badge, findsOneWidget, reason: '선택 3일 배지');
      final sel = t.widget<TODateSelector>(selector).selectedDates.map((d) => '${d.year}-${d.month}-${d.day}').toList();
      out('③ 끝 탭 → selectedDates=$sel 배지 ${rr(badge)}');
      expect(sel, ['${start.year}-${start.month}-${start.day}', '${start.year}-${start.month}-${start.day + 1}', '${end.year}-${end.month}-${end.day}']);
      expect(find.byType(AdminCreateTOScreen), findsOneWidget, reason: '폼 유지');
      await vqCapture(t, key, '${c.id}_3_range', conditions: cond('끝 날짜 탭 → 3일 선택'));

      // ④ 업무 목록 헤더(공용 위젯) — 실제 스크롤해 제목/추가 배치·크기
      final addText = findVisibleText('업무 추가');
      await t.scrollUntilVisible(addText, 120, scrollable: body, maxScrolls: 80);
      await _settle(t, 2);
      final addBtn = find.ancestor(of: addText.first, matching: find.byType(InkWell)).first;
      final hr = t.getRect(findVisibleTextContaining('업무 목록').first);
      final br = t.getRect(addBtn);
      out('④ 업무 목록 글 $hr · 업무 추가 ${rr(addBtn)} · 같은 줄=${(hr.center.dy - br.center.dy).abs() < 8}');
      await vqCapture(t, key, '${c.id}_4_workheader', conditions: cond('업무 목록 헤더'));

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
