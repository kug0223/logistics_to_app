// ignore_for_file: depend_on_referenced_packages
// [DU1 구현63 · 감사63 §5] S037-WORKFORCE-ENTRY-FAILURE-RETRY-B/W — 실제 shell 의 '근무' 탭 진입 → 선택일 단기 근무자 조회 실패 → 실제 재시도 → 정상 empty.
//   LOCAL 에서 production BusinessAdminShell() 을 앱 루트로 둔다(owner=BUSINESS_ADMIN, 사업장1). 처음 보이는 탭은 홈이다.
//   bottom-nav '근무' 중심 tapAt 1회 → WorkforceRootScreen(공유 posting controller 최초 load 포함) → WorkforceOperationalView.
//   Jobs 선행 방문 없음. private callback/controller/error 주입 없음. 선택일 = 실행 시각의 KST 오늘(화면 기본값, 다른 날짜 탭 없음).
//   사건: 사업장 조회(callableGetMyBusiness) gate 보류(day/marker 공유 확인) → 해제 → day 단기 workerOperation gate 보류 → 명시 실패.
//         같은 회차 day 장기·attendance·marker 단기/장기는 정상 empty. '다시 시도' 실제 중심 tapAt 1회 →
//         사업장 gate#2 보류 → 해제 → day 단기#2 gate 보류 → 정상 empty.
//   reader 사전(실행 전 고정, 소스 근거는 아래 expected* 주석): 홈 단계 / 근무 진입 단계 / 재시도 단계로 나눠 정확 일치 단언.
//   허용 외 Firestore read/write/batch/transaction·Functions 는 차단·계수하고 0 을 단언한다. 서버 성공/권한/DEVICE 검증이 아니다.
import 'dart:async';

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

import 'package:ALfit/controllers/workforce_controller.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_admin_shell.dart';
import 'package:ALfit/screens/business_admin/workforce_management/workforce_operational_view.dart';
import 'package:ALfit/screens/business_admin/workforce_management/workforce_root_screen.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/services/posting_quota_summary.dart';
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

const kBiz = 'biz-local-c63';
const kOwner = 'owner-local-c63';

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
  // BUSINESS_ADMIN 은 production 에서도 항상 허용(user_provider 각 판정의 첫 분기 `isBusinessAdmin → allowed/true`).
  //   대역은 private _currentUser 를 못 채워 같은 값을 직접 돌려준다.
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  bool canForAnyBusiness(bool Function(MemberPermissions p) check, {required bool whenUnknown}) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
}

String _kst(DateTime d) {
  final k = d.toUtc().add(const Duration(hours: 9));
  String p(int x) => x.toString().padLeft(2, '0');
  return '${k.year}-${p(k.month)}-${p(k.day)} ${p(k.hour)}:${p(k.minute)} KST(ms=${d.millisecondsSinceEpoch})';
}

void main() {
  // 단계별 계수 — 'home'(shell 진입~근무 탭 전) / 'entry'(근무 탭~첫 실패) / 'retry'(다시 시도~복구)
  var phase = 'home';
  final phaseCalls = <String, Map<String, int>>{'home': {}, 'entry': {}, 'retry': {}};
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  void inc(String k) {
    final m = phaseCalls[phase]!;
    m[k] = (m[k] ?? 0) + 1;
  }
  final meta = PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false);

  // ── 선택일·범위(실행 시각 기준, production 과 같은 helper 로 만든 KST 창) ──
  final now = DateTime.now();
  final todayK = FormatHelper.toKstDate(now);
  final civilToday = DateTime(todayK.year, todayK.month, todayK.day); // 화면 _today() 와 같은 civil 축
  final (dayStart, dayEnd) = FormatHelper.kstDayRange(FormatHelper.kstDayKeyOfCivil(civilToday));
  final anchor = DateTime(civilToday.year, civilToday.month, 1);
  final (markerStart, _) = FormatHelper.kstDayRange(FormatHelper.kstDayKeyOfCivil(anchor.subtract(const Duration(days: 7))));
  final (_, markerEnd) = FormatHelper.kstDayRange(
      FormatHelper.kstDayKeyOfCivil(DateTime(anchor.year, anchor.month + 1, 1).add(const Duration(days: 7))));

  Map<String, Object?> bizMap() => {
        'id': kBiz, 'name': 'QA 물류센터', 'businessNumber': '000-00-00000', 'category': '물류', 'subCategory': '상하차',
        'address': '서울시 QA구 1', 'ownerId': kOwner, 'isApproved': true,
        'createdAt': {'_seconds': DateTime(2026, 10, 1).millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0},
        'businessLicenseImageUrl': 'https://example.invalid/qa-license.png',
      };

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
          'name': 'QA 물류센터', 'businessNumber': '000-00-00000', 'category': '물류', 'subCategory': '상하차', 'address': '서울시 QA구 1',
          'ownerId': kOwner, 'adminIds': [kOwner], 'isApproved': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
          'businessLicenseImageUrl': 'https://example.invalid/qa-license.png',
        };
      } else if (path == 'users/$kOwner') {
        data = {'role': 'BUSINESS_ADMIN', 'name': 'QA 사장', 'sealBase64': 'LOCAL-QA-SEAL'};
      } else {
        return codec.encodeMessage(<Object?>['du63-blocked', 'get 차단: $path', null]);
      }
      return codec.encodeMessage(<Object?>[PigeonDocumentSnapshot(path: path, data: data, metadata: meta)]);
    });
    m.setMockMessageHandler('$base.queryGet', (msg) async {
      // 요청 본문은 codec 으로 되읽을 수 없다(구현48 r2) — 원본 바이트의 ASCII 경로 substring 으로 구분(raw 한정 검사)
      final raw = String.fromCharCodes(msg!.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes));
      final String key;
      final List<PigeonDocumentSnapshot> docs;
      if (raw.contains('businesses/$kBiz/workTypes')) {
        key = 'query businesses/$kBiz/workTypes';
        docs = [
          PigeonDocumentSnapshot(path: 'businesses/$kBiz/workTypes/wt-c63', data: <String?, Object?>{
            'businessId': kBiz, 'name': '상하차', 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
            'displayOrder': 0, 'isActive': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
          }, metadata: meta),
        ];
      } else if (raw.contains('businesses/$kBiz/contract_templates')) {
        key = 'query businesses/$kBiz/contract_templates';
        docs = [
          PigeonDocumentSnapshot(path: 'businesses/$kBiz/contract_templates/tpl-c63', data: <String?, Object?>{
            'businessId': kBiz, 'name': '단기 근무 기본', 'templateType': 'daily', 'articles': const [],
            'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
          }, metadata: meta),
        ];
      } else {
        inc('query other');
        // ignore: avoid_print
        print('BLOCKED-QUERY ${raw.replaceAll(RegExp(r'[^\x20-\x7e]'), '.')}');
        return codec.encodeMessage(<Object?>['du63-blocked', 'query 차단', null]);
      }
      inc(key);
      return codec.encodeMessage(<Object?>[PigeonQuerySnapshot(documents: docs, documentChanges: const [], metadata: meta)]);
    });
    for (final op in const ['documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit',
      'transactionCreate', 'transactionStoreResult', 'transactionGet', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        inc(op);
        return codec.encodeMessage(<Object?>['du63-blocked', '$op 차단', null]);
      });
    }
  }

  // ── Functions 대역 ──
  final fnRequests = <({String phase, String key, Map<Object?, Object?> params})>[];
  final bizGates = <Completer<void>>[];
  final dayShortGates = <Completer<void>>[];
  /// workerOperation 호출을 KST 범위 인자로 구분한다(day 와 marker 는 같은 callable 이름).
  String classifyWorkerOp(Map p) {
    if (p['businessId'] != kBiz || p['purpose'] != 'workerOperation' || p['limit'] != 2000) return 'workerOperation?unexpected-shape';
    final keys = p.keys.toSet();
    if (keys.containsAll({'workDateGteMs', 'workDateLtMs'}) && !keys.contains('workEndDateGteMs')) {
      if (p['workDateGteMs'] == dayStart.millisecondsSinceEpoch && p['workDateLtMs'] == dayEnd.millisecondsSinceEpoch) return 'day-short';
      if (p['workDateGteMs'] == markerStart.millisecondsSinceEpoch && p['workDateLtMs'] == markerEnd.millisecondsSinceEpoch) return 'marker-short';
      return 'short?unexpected-range';
    }
    if (keys.contains('workEndDateGteMs') && !keys.contains('workDateGteMs')) {
      if (p['workEndDateGteMs'] == dayStart.millisecondsSinceEpoch) return 'day-long';
      if (p['workEndDateGteMs'] == markerStart.millisecondsSinceEpoch) return 'marker-long';
      return 'long?unexpected-range';
    }
    return 'workerOperation?unexpected-keys';
  }
  void stubFunctions() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(fnChannel, (msg) async {
      const c = StandardMessageCodec();
      final args = (c.decodeMessage(msg) as List).first as Map;
      final name = args['functionName'] as String?;
      final region = args['region'];
      final params = Map<Object?, Object?>.from((args['parameters'] as Map?) ?? const {});
      String key;
      if (region != 'asia-northeast3') {
        key = 'functions.other $name@$region';
      } else if (name == 'callableGetApplicationsByBiz') {
        key = 'fn workerOperation ${classifyWorkerOp(params)}';
      } else if (name == 'callableGetAdminAttendances') {
        final ok = params['businessId'] == kBiz && params['startMs'] == dayStart.millisecondsSinceEpoch &&
            params['endMs'] == dayEnd.millisecondsSinceEpoch && params.length == 3;
        key = 'fn callableGetAdminAttendances ${ok ? 'day' : '?unexpected'}';
      } else if (const {'callableGetMyBusiness', 'callableGetAdminTOs', 'callableGetAdminHomeSummary',
          'callableGetStaffingReadiness', 'callableGetLegalReadiness'}.contains(name)) {
        key = 'fn $name';
      } else {
        key = 'functions.other $name@$region';
      }
      inc(key);
      fnRequests.add((phase: phase, key: key, params: params));
      Object? ok(Object? v) => c.encodeMessage(<Object?>[v]);
      Object? err(String code, String m) => c.encodeMessage(<Object?>[code, m, <String, Object?>{'code': code, 'message': m}]);
      if (key.contains('unexpected') || key.startsWith('functions.other')) return err('not-found', 'du63-blocked') as ByteData?;
      switch (name) {
        case 'callableGetMyBusiness':
          final g = Completer<void>();
          bizGates.add(g);
          await g.future;
          return ok({'businesses': [bizMap()]}) as ByteData?;
        case 'callableGetAdminTOs':
          return ok({'items': const <Object?>[]}) as ByteData?; // 공유 posting controller 최초 load — 공고 0건 정상
        case 'callableGetAdminAttendances':
          return ok({'items': const <Object?>[], 'limitReached': false}) as ByteData?;
        case 'callableGetApplicationsByBiz':
          if (phase != 'home' && key == 'fn workerOperation day-short') {
            final g = Completer<void>();
            dayShortGates.add(g);
            final n = dayShortGates.length;
            await g.future;
            if (n == 1) return err('internal', 'LOCAL-S037-DAY-SHORT-FAILURE') as ByteData?;
          }
          return ok({'applications': const <Object?>[], 'hasMore': false}) as ByteData?;
        default:
          // 홈 전용 reader(요약·인력 준비·약관 준비) — 계수만 하고 명시 LOCAL 오류로 응답(홈 표면은 이 셀의 판정 대상 아님)
          return err('unavailable', 'LOCAL-HOME-ONLY') as ByteData?;
      }
    });
  }

  // ── 실행 전 고정 사전(소스 근거) ──
  //   홈(BusinessAdminHomeScreen initState postFrame): _loadApprovedBusinessStatus → businesses get1(admin_home_reads businessesByIds) →
  //     요약 callableGetAdminHomeSummary1 · callableGetStaffingReadiness1 · 오늘 근태(attendanceByDate → AdminAttendances day1,
  //     confirmedWorkers → workerOperation 오늘 단기1/장기1, workDetailTimes 빈 목록 0) · 공고 준비(owner get1·workTypes query1·template query1) ·
  //     LegalTaskCard → callableGetLegalReadiness1. 홈의 '오늘' = 근무 화면 선택일(KST 오늘) 이라 같은 KST 창 인자다 — 단계로 구분한다.
  const expectedHome = {
    'get businesses/$kBiz': 1,
    'get users/$kOwner': 1,
    'query businesses/$kBiz/workTypes': 1,
    'query businesses/$kBiz/contract_templates': 1,
    'fn callableGetAdminHomeSummary': 1,
    'fn callableGetStaffingReadiness': 1,
    'fn callableGetLegalReadiness': 1,
    'fn callableGetAdminAttendances day': 1,
    'fn workerOperation day-short': 1,
    'fn workerOperation day-long': 1,
  };
  //   근무 진입: WorkforceRootScreen initState → 공유 posting controller 최초 load(callableGetAdminTOs1, 공고0이라 slots0).
  //     WorkforceOperationalView initState postFrame → _loadDayData + _loadMarkerRange 가 같은 _ensureBusinesses in-flight 공유 →
  //     callableGetMyBusiness1 → day 단기1·장기1·AdminAttendances1 + marker 단기1·장기1. 근무자 0이라 getUsersBatch 0.
  const expectedEntry = {
    'fn callableGetAdminTOs': 1,
    'fn callableGetMyBusiness': 1,
    'fn workerOperation day-short': 1,
    'fn workerOperation day-long': 1,
    'fn callableGetAdminAttendances day': 1,
    'fn workerOperation marker-short': 1,
    'fn workerOperation marker-long': 1,
  };
  //   재시도: _reload → _businessesStale=true → day + marker(force) 가 다시 _ensureBusinesses 공유 → 같은 6.
  const expectedRetry = {
    'fn callableGetMyBusiness': 1,
    'fn workerOperation day-short': 1,
    'fn workerOperation day-long': 1,
    'fn callableGetAdminAttendances day': 1,
    'fn workerOperation marker-short': 1,
    'fn workerOperation marker-long': 1,
  };

  for (final c in const [
    (id: 'S037-WORKFORCE-ENTRY-FAILURE-RETRY-B', w: 320.0, h: 640.0, s: 2.0),
    (id: 'S037-WORKFORCE-ENTRY-FAILURE-RETRY-W', w: 360.0, h: 780.0, s: 1.0),
  ]) {
    testWidgets('${c.id} shell 근무 탭 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 단기 조회 실패→실제 재시도→정상 empty', (t) async {
      await t.runAsync(vqLoadFonts);
      FirstPostingReadinessStore.reset();
      PostingQuotaStore.reset();
      PostingQuotaStore.fetchCount = 0;
      phase = 'home';
      for (final m in phaseCalls.values) {
        m.clear();
      }
      fnRequests.clear();
      bizGates.clear();
      dayShortGates.clear();
      stubFirestore();
      stubFunctions();
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
      out('${c.id} 실행 now=${now.toIso8601String()} utc=${now.toUtc().toIso8601String()} tz=${now.timeZoneName}(${now.timeZoneOffset}) · KST now=${_kst(now)}');
      out('   선택일(KST civil)=${civilToday.toIso8601String().substring(0, 10)} · day 창 ${_kst(dayStart)} ~ ${_kst(dayEnd)}'
          ' · marker anchor=${anchor.toIso8601String().substring(0, 10)} 창 ${_kst(markerStart)} ~ ${_kst(markerEnd)} · scope=owner $kOwner managedBusinessIds=[$kBiz]');
      final deferred = <String>[];
      final observations = <String>[];
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
            home: const BusinessAdminShell(),
          ),
        ),
      ));
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
        return hit.path.take(4).map((e) => e.target.runtimeType.toString()).join('>');
      }
      String rr(Finder f) {
        final r = t.getRect(f);
        final ok48 = r.width >= 48 && r.height >= 48;
        return '$r(${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} 48=${ok48 ? 'OK' : 'NG'}) centerHit=${hits(f, r.center)} path=${topHit(r.center)}';
      }
      Map<String, int> snap(String p) => Map<String, int>.from(phaseCalls[p]!);
      Map<String, int> delta(String p, Map<String, int> a) => {
            for (final k in {...a.keys, ...phaseCalls[p]!.keys})
              if ((phaseCalls[p]![k] ?? 0) != (a[k] ?? 0)) k: (phaseCalls[p]![k] ?? 0) - (a[k] ?? 0)};
      final view = find.byType(WorkforceOperationalView);
      List<String> viewTexts() => view.evaluate().isEmpty
          ? const []
          : t.widgetList<Text>(find.descendant(of: view, matching: find.byType(Text)))
              .map((w) => visibleText(w.data ?? w.textSpan?.toPlainText() ?? ''))
              .where((s) => s.trim().isNotEmpty)
              .toList();
      // 요약 칩 숫자 Text(fontSize 20) — 확정/출근/미출근/노쇼 순
      List<String> summaryCounts() => view.evaluate().isEmpty
          ? const []
          : t.widgetList<Text>(find.descendant(of: view, matching: find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == 20)))
              .map((w) => w.data ?? '')
              .toList();
      const errMsg = '데이터를 불러오지 못했습니다. 다시 시도해 주세요.';
      final errText = findVisibleText(errMsg);
      final retryText = findVisibleText('다시 시도');
      final dayLoading = findVisibleText('근무 인력을 불러오는 중...');
      final rootLoading = find.text('인력 정보를 불러오는 중...');
      const noBizTitle = '아직 근무를 관리할 사업장이 없어요';
      final emptyToday = findVisibleText('오늘 확정된 인력이 없습니다.'); // [DU604b] 빈 상태 글 keepWords — 보이는 글자로 찾는다(DU255 꼴)
      final markerFail = findVisibleText('근무가 있는 날짜를 표시하지 못했어요');
      String rendered() => '요약=${summaryCounts()} · 오류문구=${errText.evaluate().length} 다시시도=${retryText.evaluate().length}'
          ' · 인력로딩=${dayLoading.evaluate().length} 루트로딩=${rootLoading.evaluate().length}'
          ' · 사업장없음=${find.text(noBizTitle).evaluate().length} 오늘0명=${emptyToday.evaluate().length} marker실패=${markerFail.evaluate().length}'
          ' · scope="${t.widgetList<Text>(find.descendant(of: find.byType(WorkforceRootScreen), matching: find.byType(Text))).map((w) => w.data).where((s) => s == 'QA 물류센터' || s == '내 사업장').join(',')}"';
      Finder scroll() => find.descendant(of: find.descendant(of: view, matching: find.byType(CustomScrollView)), matching: find.byType(Scrollable)).first;
      double offset() => t.state<ScrollableState>(scroll()).position.pixels;
      Rect vp() => t.getRect(scroll());
      bool inVp(Rect r) => r.top >= vp().top - 0.5 && r.bottom <= vp().bottom + 0.5;
      Future<String> bring(Finder f, String when) async {
        final a = offset();
        final r0 = t.getRect(f);
        for (var k = 0; k < 60; k++) {
          final r = t.getRect(f);
          if (inVp(r)) break;
          final dy = r.top < vp().top ? 60.0 : -60.0;
          await t.dragFrom(Offset(vp().left + 8, vp().center.dy), Offset(0, dy));
          await frames(2);
        }
        await frames(2);
        final s = '직후 offset=${a.toStringAsFixed(1)} 대상 $r0 inVp=${inVp(r0)} → 끌기 뒤 offset=${offset().toStringAsFixed(1)} 대상 ${t.getRect(f)} inVp=${inVp(t.getRect(f))}';
        out('   $when $s');
        return s;
      }
      // [r2] B 에서 아래 sliver(로딩/오류/빈 상태)는 viewport 밖이면 아직 만들어지지 않는다(lazy) — finder 0 은 '표시 없음'이 아니다.
      //   대상이 나타날 때까지 실제 끌기로 내려가고(최대 끝까지), 나타나면 viewport 안으로 맞춘다. 직후/끌기 뒤 offset 구분.
      Future<String> show(Finder f, String when) async {
        final a = offset();
        for (var k = 0; k < 40 && f.evaluate().isEmpty; k++) {
          final pos = t.state<ScrollableState>(scroll()).position;
          if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
          await t.dragFrom(Offset(vp().left + 8, vp().center.dy), const Offset(0, -60));
          await frames(2);
        }
        if (f.evaluate().isEmpty) {
          final s = '직후 offset=${a.toStringAsFixed(1)} → 끝까지 끌어도 대상 없음 offset=${offset().toStringAsFixed(1)}';
          out('   $when $s');
          return s;
        }
        final s = await bring(f, when);
        return a == offset() ? s : '처음 offset=${a.toStringAsFixed(1)} · $s';
      }
      // 요약 칩(맨 위)을 viewport 로 올려 읽는다 — 아래로 끌어 둔 상태에서 lazy 로 빠지면 빈 목록이 '0 아님'으로 오판된다.
      Future<List<String>> summaryShown(String when) async {
        final first = find.descendant(of: view, matching: find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == 20));
        for (var k = 0; k < 40 && (first.evaluate().isEmpty || !inVp(t.getRect(first.first))); k++) {
          if (offset() <= 0.5) break;
          await t.dragFrom(Offset(vp().left + 8, vp().center.dy), const Offset(0, 60));
          await frames(2);
        }
        final s = summaryCounts();
        out('   $when 요약=$s offset=${offset().toStringAsFixed(1)}');
        return s;
      }
      // sidecar — 이 셀의 실제 fixture/응답/게이트만 적는다(감사63 §3 지적: 복사 잔재 금지)
      Map<String, Object?> cond(String state) {
        final m = MediaQuery.of(t.element(find.byType(BusinessAdminShell)));
        return {
          'entry': 'LOCAL MaterialApp(home: BusinessAdminShell()) · 첫 탭 홈 → bottom-nav 근무 실제 tapAt 1회 → WorkforceRootScreen(공유 posting controller) → WorkforceOperationalView · Jobs 미방문',
          'theme': 'RoleTheme.businessAdminTheme', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
          'mqNow': 'size=${m.size} padding=${m.padding} viewPadding=${m.viewPadding} viewInsets=${m.viewInsets}',
          'physicalInsetBottomNow': t.view.viewInsets.bottom,
          'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK)', 'prefs': 'setMockInitialValues({})',
          'clock': '미주입(DateTime.now=$now · KST ${_kst(now)})',
          'selectedDay': '${civilToday.toIso8601String().substring(0, 10)}(KST 오늘·화면 기본값) day창 ${dayStart.millisecondsSinceEpoch}~${dayEnd.millisecondsSinceEpoch} marker창 ${markerStart.millisecondsSinceEpoch}~${markerEnd.millisecondsSinceEpoch}',
          'fixture': 'owner $kOwner · biz $kBiz approved/license/owner seal · workType1 · template1 · 공고0(AdminTOs items=[]) · 근무자0(모든 workerOperation applications=[])',
          'responses': 'MyBusiness=[biz](호출마다 gate) · day-short#1 gate→internal/LOCAL-S037-DAY-SHORT-FAILURE · day-short#2 gate→applications=[] · 그 밖 workerOperation/AdminAttendances 즉시 empty · 홈 전용 요약/인력준비/약관준비=unavailable/LOCAL-HOME-ONLY',
          'gates': 'business=${bizGates.map((g) => g.isCompleted).toList()} daySh=${dayShortGates.map((g) => g.isCompleted).toList()}',
          'state': state, 'phase': phase, 'calls': phaseCalls.toString()};
      }

      // ── ① shell 진입(홈) ──
      await frames(40);
      out('① 홈 단계 calls=${phaseCalls['home']}');
      expect(view, findsNothing, reason: '근무 탭 미방문 — 운영 화면 미생성');
      expect(phaseCalls['home'], expectedHome, reason: '홈 단계 정확 사전');
      final navLabel = find.text('근무');
      expect(navLabel, findsOneWidget, reason: 'bottom-nav 근무 라벨');
      final navItem = find.ancestor(of: navLabel, matching: find.byType(InkResponse)).first;
      out('   근무 탭 ${rr(navItem)}');
      await vqCapture(t, key, '${c.id}_1_home', conditions: cond('shell 진입 · 홈 · 근무 탭 전'));

      // ── ② 근무 탭 실제 중심 1회 → 사업장 gate#1 보류 ──
      phase = 'entry';
      await t.tapAt(t.getRect(navItem).center);
      await frames(6);
      out('② 근무 탭 · entry calls=${phaseCalls['entry']} · bizGates=${bizGates.length}');
      out('   그림 ${rendered()}');
      expect(find.byType(WorkforceRootScreen), findsOneWidget);
      expect(view, findsOneWidget);
      expect(phaseCalls['entry'], {'fn callableGetAdminTOs': 1, 'fn callableGetMyBusiness': 1},
          reason: '사업장 보류 중 — day/marker 가 한 in-flight 를 공유(근무자 조회 0)');
      expect(bizGates.length, 1);
      final ctl = Provider.of<WorkforceController>(t.element(view), listen: false);
      out('   공유 posting controller hasLoadedOnce=${ctl.hasLoadedOnce} items=${ctl.items.length} loadError=${ctl.loadError}');
      await vqCapture(t, key, '${c.id}_2_business_held', conditions: cond('근무 진입 · callableGetMyBusiness gate#1 보류'));

      // ── ③ 사업장 해제 → day 단기#1 보류 ──
      bizGates[0].complete();
      await frames(6);
      out('③ 사업장 해제 · entry calls=${phaseCalls['entry']} · dayShortGates=${dayShortGates.length}');
      out('   그림 ${rendered()}');
      expect(phaseCalls['entry'], expectedEntry, reason: '근무 진입 한 회차 정확 사전');
      expect(dayShortGates.length, 1);
      final sum3 = await summaryShown('day#1 보류');
      if (sum3.any((s) => s == '0')) deferred.add('day#1 보류 중 요약 0 표시');
      final h1 = await show(dayLoading, 'day#1 보류 로딩');
      if (dayLoading.evaluate().isEmpty) deferred.add('day#1 보류 중 근무 인력 로딩 표시 없음');
      await vqCapture(t, key, '${c.id}_3_day1_held', conditions: cond('day 단기#1 gate 보류 · $h1 · ${rendered()}'));

      // ── ④ day 단기#1 명시 실패 → 오류 ──
      final beforeFail = snap('entry');
      dayShortGates[0].complete();
      await frames(10);
      out('④ day#1 실패 해제 · delta=${delta('entry', beforeFail)}');
      out('   그림 ${rendered()}');
      out('   화면 글=${viewTexts()}');
      expect(delta('entry', beforeFail), isEmpty, reason: '실패 해제 추가조회 0');
      final counts1 = await summaryShown('실패');
      await show(errText, '실패 문구');
      expect(errText, findsOneWidget, reason: '실패 문구 실제 도달');
      expect(findVisibleText(noBizTitle), findsNothing, reason: '사업장 없음으로 확정하지 않는다');
      expect(emptyToday, findsNothing, reason: '정상 근무자 0 으로 확정하지 않는다');
      if (counts1.any((s) => s == '0')) {
        deferred.add('조회 실패인데 요약 칩이 확인된 0 을 표시(${counts1.join('/')})');
      }
      final retryBtn = find.ancestor(of: retryText, matching: find.byType(TextButton)).first;
      final errP = t.renderObject<RenderParagraph>(find.descendant(of: errText, matching: find.byType(RichText)).first); // [DU255 r1]
      final fb = await bring(retryBtn, '실패/다시시도');
      final retryR = t.getRect(retryBtn);
      out('   오류 문구 rect=${t.getRect(errText)} inVp=${inVp(t.getRect(errText))} didExceedMaxLines=${errP.didExceedMaxLines} maxLines=${t.widget<Text>(errText).maxLines}');
      out('   다시 시도 TextButton ${rr(retryBtn)} · 글 ${t.getRect(retryText)}');
      if (retryR.width < 48 || retryR.height < 48) deferred.add('다시 시도 터치 ${retryR.width.toStringAsFixed(1)}×${retryR.height.toStringAsFixed(1)} < 48');
      if (!hits(retryBtn, retryR.center)) deferred.add('다시 시도 중심 hit 실패');
      if (errP.didExceedMaxLines) deferred.add('오류 문구 말줄임');
      if (!inVp(t.getRect(errText))) observations.add('B 오류 문구와 다시 시도가 같은 viewport 에 함께 있지 않음(끌기 뒤)');
      expect(inVp(retryR), isTrue);
      await vqCapture(t, key, '${c.id}_4_failure', conditions: cond('day 단기#1 명시 실패 · $fb · 다시시도 ${rr(retryBtn)} · ${rendered()}'));

      // ── ⑤ 다시 시도 실제 중심 1회 → 사업장 gate#2 보류 ──
      phase = 'retry';
      await t.tapAt(retryR.center);
      await frames(6);
      out('⑤ 다시 시도 · retry calls=${phaseCalls['retry']} · bizGates=${bizGates.length}');
      out('   그림 ${rendered()}');
      expect(phaseCalls['retry'], {'fn callableGetMyBusiness': 1}, reason: '재시도 사업장 재검증 1(공유)');
      expect(bizGates.length, 2);
      final sum5 = await summaryShown('사업장#2 보류');
      if (sum5.any((s) => s == '0')) deferred.add('재시도 사업장 보류 중 요약 0 표시');
      final hb = await show(dayLoading, '사업장#2 보류 로딩');
      if (errText.evaluate().isNotEmpty) deferred.add('재시도 사업장 보류 중 이전 실패 문구 유지');
      if (dayLoading.evaluate().isEmpty) deferred.add('재시도 사업장 보류 중 로딩 표시 없음');
      await vqCapture(t, key, '${c.id}_5_business2_held', conditions: cond('재시도 · callableGetMyBusiness gate#2 보류 · $hb · ${rendered()}'));

      // ── ⑥ 사업장 해제 → day 단기#2 보류 ──
      bizGates[1].complete();
      await frames(6);
      out('⑥ 사업장#2 해제 · retry calls=${phaseCalls['retry']} · dayShortGates=${dayShortGates.length}');
      out('   그림 ${rendered()}');
      expect(phaseCalls['retry'], expectedRetry, reason: '재시도 한 회차 정확 사전');
      expect(dayShortGates.length, 2);
      final sum6 = await summaryShown('day#2 보류');
      if (sum6.any((s) => s == '0')) deferred.add('day#2 보류 중 요약 0 표시');
      final h2 = await show(dayLoading, 'day#2 보류 로딩');
      if (errText.evaluate().isNotEmpty) deferred.add('day#2 보류 중 이전 실패 문구 유지');
      if (dayLoading.evaluate().isEmpty) deferred.add('day#2 보류 중 로딩 표시 없음');
      if (emptyToday.evaluate().isNotEmpty) deferred.add('day#2 보류 중 정상 0 확정');
      await vqCapture(t, key, '${c.id}_6_day2_held', conditions: cond('day 단기#2 gate 보류 · $h2 · ${rendered()}'));

      // ── ⑦ day 단기#2 정상 empty → 정상 0 ──
      final beforeOk = snap('retry');
      dayShortGates[1].complete();
      await frames(10);
      out('⑦ day#2 정상 해제 · delta=${delta('retry', beforeOk)}');
      out('   그림 ${rendered()}');
      out('   화면 글=${viewTexts()}');
      expect(delta('retry', beforeOk), isEmpty);
      expect(errText, findsNothing, reason: '복구 뒤 실패 문구 제거');
      expect(find.text(noBizTitle), findsNothing, reason: '등록 사업장 1 유지');
      final sum7 = await summaryShown('복구');
      final rb = await show(emptyToday, '복구 정상0');
      expect(emptyToday, findsOneWidget, reason: '확인된 정상 0(오늘 확정된 인력이 없습니다.)');
      expect(markerFail, findsNothing, reason: 'marker 정상 empty — 실패 표시 없음');
      expect(sum7, ['0', '0', '0', '0'], reason: '정상 0 요약');
      final scopeTexts = t.widgetList<Text>(find.descendant(of: find.byType(WorkforceRootScreen), matching: find.byType(Text)))
          .map((w) => w.data ?? '').toList();
      if (scopeTexts.contains('내 사업장') && !scopeTexts.contains('QA 물류센터')) {
        observations.add('머리 사업장 칩이 "내 사업장" — 이름 출처가 공유 posting controller(공고 0건)라 MyBusiness 로 읽은 "QA 물류센터" 를 쓰지 않음(판정 대상 아님·기록)');
      }
      await vqCapture(t, key, '${c.id}_7_recovered', conditions: cond('day 단기#2 정상 empty · $rb · ${rendered()}'));

      // ── 종료선 ──
      await frames(10);
      out('최종 phaseCalls=$phaseCalls');
      for (final r in fnRequests) {
        out('   fn[${r.phase}] ${r.key} params=${r.params}');
      }
      expect(phaseCalls['home'], expectedHome, reason: '홈 단계 그 뒤로 증가 0');
      expect(phaseCalls['entry'], expectedEntry);
      expect(phaseCalls['retry'], expectedRetry);
      expect(PostingQuotaStore.fetchCount, 0, reason: 'Jobs 미방문 — quota 0');
      expect(bizGates.every((g) => g.isCompleted) && dayShortGates.every((g) => g.isCompleted), isTrue);
      FlutterError.onError = prev;
      out('observations(${observations.length})=${observations.join(' | ')}');
      out('overflows(${overflows.length})=${overflows.join(' | ')}');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
      out('deferred(${deferred.length})=${deferred.join(' | ')}');
      expect(deferred, isEmpty, reason: deferred.join(' | '));
    });
  }
}
