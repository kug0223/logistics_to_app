// ignore_for_file: depend_on_referenced_packages
// [DU1 구현60 · 감사60 §5] C2-CAPACITY-FAILURE-RETRY-B/W — S035 정상1개 목록 → 실제 펼침 → capacity 실패 → 실제 재시도 → 복구.
//   하네스는 du1_c2_posting_list_entry_test.dart(구현59) 복사. 진입·fixture·reader 경계 동일.
//   LOCAL host route 에서 production JobsRootScreen()(postingController 미주입 → 자체 신규 WorkforceController,
//   initialTargetToId=null, 필터 없음) 을 owner(BUSINESS_ADMIN) 로 push 한다.
//   readiness·quota 정상 → 목록 gate 보류(캡처) → 정상1 → 슬롯 선로딩 → 화살표 실제 탭 →
//   capacity gate1 보류(캡처) → 명시 오류 envelope(internal/LOCAL-C2-CAPACITY-FAILURE) 해제 → 실패 문구·재시도(캡처) →
//   재시도 버튼 실제 중심 tapAt 1회(callback 직접 호출 없음) → capacity gate2 보류(캡처) → applications=[]/hasMore=false → 확인된 0 복구.
//   허용 reader 외 Firestore read/write/batch/transaction·Functions 는 모두 차단·계수하고 0 을 단언한다
//   (production 이 오류를 catch 하므로 exception 0 만으로 시도 0 을 대신하지 않는다).
//   '인력 현황' 은 식별·rect·48 만 재고 누르지 않는다. 서버 성공/권한/DEVICE 검증이 아니다.
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
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/jobs_root_screen.dart';
import 'package:ALfit/screens/business_admin/workforce_management/workforce_list_view.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/services/posting_quota_summary.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/admin/cards/admin_to_group_card.dart';

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

const kBiz = 'biz-local-c59';
const kOwner = 'owner-local-c59';
const kTo = 'to-local-c59';
const kSlot = 'slot-local-c59';
const kWd = 'wd-local-c59';
// 고정 긴 한글 제목 — 끝 문구 `안전화 지참 필수` 로 전문 가시성을 판정한다.
const kTitleEnd = '안전화 지참 필수';
const kTitle = '송파 물류센터 주말 오전 상하차·분류 보조 단기 인력 모집 $kTitleEnd';

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
  // BUSINESS_ADMIN 은 production 에서도 항상 허용(user_provider canForBusiness/checkForBusiness/checkCurrentBusiness 첫 분기).
  //   대역은 private _currentUser 를 못 채워 같은 값을 직접 돌려준다.
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
}

/// Firestore 대역 응답에 쓰는 Timestamp/DateTime → callable wire({_seconds,_nanoseconds}).
Object? _wire(Object? v) {
  if (v is Timestamp) return {'_seconds': v.seconds, '_nanoseconds': v.nanoseconds};
  if (v is DateTime) {
    final ms = v.millisecondsSinceEpoch;
    return {'_seconds': ms ~/ 1000, '_nanoseconds': (ms % 1000) * 1000000};
  }
  if (v is Map) return v.map((k, x) => MapEntry(k, _wire(x)));
  if (v is List) return v.map(_wire).toList();
  return v;
}

String _kst(DateTime d) {
  final k = d.toUtc().add(const Duration(hours: 9));
  String p(int x) => x.toString().padLeft(2, '0');
  return '${k.year}-${p(k.month)}-${p(k.day)} ${p(k.hour)}:${p(k.minute)} KST(epoch=${d.millisecondsSinceEpoch ~/ 1000})';
}

/// StandardMessageCodec int32 LE 인코딩(type 3) — query 원본 바이트에서 limit 값을 확인한다(한정 검사).
bool _hasInt32(List<int> b, int v) {
  final pat = [3, v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
  for (var i = 0; i + pat.length <= b.length; i++) {
    var ok = true;
    for (var j = 0; j < pat.length; j++) {
      if (b[i + j] != pat[j]) {
        ok = false;
        break;
      }
    }
    if (ok) return true;
  }
  return false;
}

void main() {
  final calls = <String, int>{};
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  void inc(String k) => calls[k] = (calls[k] ?? 0) + 1;
  final meta = PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false);
  final queryChecks = <String>[];

  // ── 실행 시계 기준 fixture(셀마다 같은 값) ──
  //   근무일 = 오늘(KST)+7 의 KST 자정 instant. 지원 마감 = 그날 08:00 KST, 근무 10:00~13:00.
  final now = DateTime.now();
  final kstNow = now.toUtc().add(const Duration(hours: 9));
  final workDate = DateTime.utc(kstNow.year, kstNow.month, kstNow.day)
      .add(const Duration(days: 7))
      .subtract(const Duration(hours: 9))
      .toLocal();
  final created = now.subtract(const Duration(days: 1));
  final wdDeadline = workDate.add(const Duration(hours: 8));
  final workKey = () {
    final k = workDate.toUtc().add(const Duration(hours: 9));
    return '${k.year}-${k.month.toString().padLeft(2, '0')}-${k.day.toString().padLeft(2, '0')}';
  }();

  WorkDetailData wd() => WorkDetailData(
        wdId: kWd, workType: '상하차', workTypeId: 'wt-c59', startTime: '10:00', endTime: '13:00',
        requiredCount: 3, wage: 12000, wageType: 'hourly', applicationDeadline: wdDeadline,
      );
  TOModel master() => TOModel(
        id: kTo, businessId: kBiz, businessName: 'QA 물류센터', type: 'flex', title: kTitle, creatorUID: kOwner,
        status: TOStatus.active, workDetails: [wd()], totalSlots: 1, slotDateKeys: [workKey],
        totalRequired: 3, totalConfirmed: 0, totalPending: 0,
        isPublished: true, publishMode: 'immediate', rangeStart: workDate, rangeEnd: workDate,
        deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2,
        createdAt: created, statusUpdatedAt: created,
      );
  SlotModel slot() => SlotModel(
        id: kSlot, toId: kTo, date: workDate, workDetails: [wd()],
        workDetailCounts: const {kWd: SlotWorkTypeCount(confirmedCount: 0, pendingCount: 0)},
        status: SlotStatus.open, confirmedCount: 0, pendingCount: 0,
        applicationDeadline: wdDeadline, visibleFrom: created, createdAt: created,
      );

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
        return codec.encodeMessage(<Object?>['du59-blocked', 'get 차단: $path', null]);
      }
      return codec.encodeMessage(<Object?>[PigeonDocumentSnapshot(path: path, data: data, metadata: meta)]);
    });
    m.setMockMessageHandler('$base.queryGet', (msg) async {
      // 요청 본문은 codec 으로 되읽을 수 없다(구현48 r2) — 원본 바이트의 ASCII 경로/필드 substring 과 int32 limit 으로 구분(한정 검사)
      final bytes = msg!.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes);
      final raw = String.fromCharCodes(bytes);
      final String key;
      final List<PigeonDocumentSnapshot> docs;
      if (raw.contains('businesses/$kBiz/workTypes')) {
        key = 'query businesses/$kBiz/workTypes';
        queryChecks.add('$key isActive=${raw.contains('isActive')} displayOrder=${raw.contains('displayOrder')} limit100=${_hasInt32(bytes, 100)}');
        docs = [
          PigeonDocumentSnapshot(path: 'businesses/$kBiz/workTypes/wt-c59', data: <String?, Object?>{
            'businessId': kBiz, 'name': '상하차', 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
            'displayOrder': 0, 'isActive': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
          }, metadata: meta),
        ];
      } else if (raw.contains('businesses/$kBiz/contract_templates')) {
        key = 'query businesses/$kBiz/contract_templates';
        queryChecks.add('$key createdAt=${raw.contains('createdAt')} limit100=${_hasInt32(bytes, 100)}');
        docs = [
          PigeonDocumentSnapshot(path: 'businesses/$kBiz/contract_templates/tpl-c59', data: <String?, Object?>{
            'businessId': kBiz, 'name': '단기 근무 기본', 'templateType': 'daily', 'articles': const [],
            'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
          }, metadata: meta),
        ];
      } else if (raw.contains('tos/$kTo/slots')) {
        key = 'query tos/$kTo/slots';
        queryChecks.add('$key date=${raw.contains('date')} limit501=${_hasInt32(bytes, 501)}');
        docs = [
          PigeonDocumentSnapshot(path: 'tos/$kTo/slots/$kSlot', data: Map<String?, Object?>.from(slot().toMap()), metadata: meta),
        ];
      } else {
        inc('query other');
        // ignore: avoid_print
        print('BLOCKED-QUERY ${raw.replaceAll(RegExp(r'[^\x20-\x7e]'), '.')}');
        return codec.encodeMessage(<Object?>['du59-blocked', 'query 차단', null]);
      }
      inc(key);
      return codec.encodeMessage(<Object?>[PigeonQuerySnapshot(documents: docs, documentChanges: const [], metadata: meta)]);
    });
    for (final op in const ['documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit',
      'transactionCreate', 'transactionStoreResult', 'transactionGet', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        inc(op);
        return codec.encodeMessage(<Object?>['du59-blocked', '$op 차단', null]);
      });
    }
  }

  // ── Functions 대역: 허용 3종(이름·region 정확 일치)만 응답, 목록·capacity 는 호출마다 gate 보류 ──
  final fnRequests = <Map<Object?, Object?>>[];
  final listGates = <Completer<void>>[];
  final capGates = <Completer<void>>[];
  void stubFunctions() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(fnChannel, (msg) async {
      const c = StandardMessageCodec();
      final args = (c.decodeMessage(msg) as List).first as Map;
      final name = args['functionName'];
      final region = args['region'];
      fnRequests.add(Map<Object?, Object?>.from(args));
      final key = 'functions $name@$region';
      const allowed = {'callableGetPostingQuotaSummary', 'callableGetAdminTOs', 'callableGetApplicationsByBiz'};
      if (region != 'asia-northeast3' || !allowed.contains(name)) {
        inc('functions.other $name@$region');
        return c.encodeMessage(<Object?>['not-found', 'du59-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      inc(key);
      if (name == 'callableGetPostingQuotaSummary') {
        return c.encodeMessage(<Object?>[
          <String, Object?>{
            'scopes': [
              {'scopeToken': 'owner:$kOwner', 'businessIds': [kBiz], 'used': 1, 'limit': 10, 'remaining': 9},
            ],
            'denied': const [],
            'failed': const [],
          }
        ]);
      }
      if (name == 'callableGetAdminTOs') {
        final g = Completer<void>();
        listGates.add(g);
        await g.future;
        final item = Map<String, Object?>.from(_wire(master().toMap()) as Map)
          ..['dates'] = [workKey]
          ..['id'] = kTo;
        return c.encodeMessage(<Object?>[
          <String, Object?>{'items': <Object?>[item]}
        ]);
      }
      // callableGetApplicationsByBiz(capacity) — 1번째: 명시 오류 envelope, 2번째: 정상 empty. 호출마다 새 gate.
      final g = Completer<void>();
      capGates.add(g);
      final n = capGates.length;
      await g.future;
      if (n == 1) {
        return c.encodeMessage(<Object?>[
          'internal',
          'LOCAL-C2-CAPACITY-FAILURE',
          <String, Object?>{'code': 'internal', 'message': 'LOCAL-C2-CAPACITY-FAILURE'},
        ]);
      }
      return c.encodeMessage(<Object?>[
        <String, Object?>{'applications': const <Object?>[], 'hasMore': false}
      ]);
    });
  }

  // 사전 고정 허용사전(감사59 §5.2 예상 — 관측 복사 아님). quota=1 근거는 아래 out() 로그와 보고에 적는다.
  const expectedAtLoading = {
    'get businesses/$kBiz': 1,
    'get users/$kOwner': 1,
    'query businesses/$kBiz/workTypes': 1,
    'query businesses/$kBiz/contract_templates': 1,
    'functions callableGetPostingQuotaSummary@asia-northeast3': 1,
    'functions callableGetAdminTOs@asia-northeast3': 1,
  };
  const expectedList1 = {...expectedAtLoading, 'query tos/$kTo/slots': 1};
  const expectedAfterFail = {...expectedList1, 'functions callableGetApplicationsByBiz@asia-northeast3': 1};
  const expectedFinal = {...expectedList1, 'functions callableGetApplicationsByBiz@asia-northeast3': 2};

  for (final c in const [
    (id: 'C2-CAPACITY-FAILURE-RETRY-B', w: 320.0, h: 640.0, s: 2.0),
    (id: 'C2-CAPACITY-FAILURE-RETRY-W', w: 360.0, h: 780.0, s: 1.0),
  ]) {
    testWidgets('${c.id} 공고 카드 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 실제 펼침→capacity 실패→실제 재시도→보류→확인된 0 복구', (t) async {
      await t.runAsync(vqLoadFonts);
      // §5.1-4 셀 경계: 두 store reset + fetchCount 0(reset 이 지우지 않는다) + 새 controller(JobsRoot 자체 생성)
      FirstPostingReadinessStore.reset();
      PostingQuotaStore.reset();
      PostingQuotaStore.fetchCount = 0;
      calls.clear();
      fnRequests.clear();
      listGates.clear();
      capGates.clear();
      queryChecks.clear();
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
      out('   fixture: slot.date=${_kst(workDate)} civil=$workKey · rangeStart/End=${_kst(workDate)} · wd.applicationDeadline=${_kst(wdDeadline)}'
          ' · slot.applicationDeadline=${_kst(wdDeadline)} · slot.visibleFrom=${_kst(created)} · createdAt/statusUpdatedAt=${_kst(created)}'
          ' · deadlineType=HOURS_BEFORE(2h) · publishMode=immediate·isPublished=true · totalSlots=1 dates=[$workKey]');
      expect(wdDeadline.isAfter(now), isTrue, reason: '지원 마감이 미래(비만료 fixture)');
      final deferred = <String>[];
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
                onPressed: () => Navigator.of(ctx).push(MaterialPageRoute(builder: (_) => const JobsRootScreen())),
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
        return hit.path.take(4).map((e) => e.target.runtimeType.toString()).join('>');
      }
      String rr(Finder f) {
        final r = t.getRect(f);
        final ok = r.width >= 48 && r.height >= 48;
        return '$r(${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} 48=${ok ? 'OK' : 'NG'}) centerHit=${hits(f, r.center)} path=${topHit(r.center)}';
      }
      Map<String, int> snapCalls() => Map<String, int>.from(calls);
      Map<String, int> delta(Map<String, int> a) => {
            for (final k in {...a.keys, ...calls.keys})
              if ((calls[k] ?? 0) != (a[k] ?? 0)) k: (calls[k] ?? 0) - (a[k] ?? 0)};
      WorkforceController ctl() => Provider.of<WorkforceController>(t.element(find.byType(WorkforceListView)), listen: false);
      Finder listScrollable() => find.descendant(
          of: find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.vertical && w.controller != null),
          matching: find.byType(Scrollable)).first;
      double scrollOffset() => t.state<ScrollableState>(listScrollable()).position.pixels;
      Map<String, Object?> cond(String state) {
        final scr = find.byType(JobsRootScreen);
        final m = scr.evaluate().isEmpty ? MediaQuery.of(t.element(find.text('host'))) : MediaQuery.of(t.element(scr));
        return {
          'entry': 'LOCAL host → Navigator.push(JobsRootScreen()) · postingController 미주입(자체 신규 WorkforceController) · initialTargetToId=null · 필터 없음 · FCM/revision/lifecycle 추가 갱신 없음',
          'theme': 'RoleTheme.businessAdminTheme', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
          'mqNow': 'size=${m.size} padding=${m.padding} viewPadding=${m.viewPadding} viewInsets=${m.viewInsets} textScaler=${m.textScaler}',
          'physicalInsetBottomNow': t.view.viewInsets.bottom,
          'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK)',
          'prefs': 'setMockInitialValues({})',
          'clock': '미주입(DateTime.now=$now · KST ${_kst(now)}) — StaffingClock/controller/seatDay 모두 실제 시계',
          'fixture': 'owner $kOwner·biz $kBiz approved/license/owner seal·workType 1·daily template 1 · TO $kTo flex title="$kTitle" · slot $kSlot ${_kst(workDate)} · wd $kWd 상하차 10:00~13:00 필요3/충원0/대기0 · 마감 ${_kst(wdDeadline)}',
          'capacity': '1번째 → internal/LOCAL-C2-CAPACITY-FAILURE envelope · 2번째 → {applications: [], hasMore: false} · 호출마다 새 gate',
          'gates': 'list=${listGates.map((g) => g.isCompleted).toList()} capacity=${capGates.map((g) => g.isCompleted).toList()}',
          'state': state, 'calls': calls.toString(), 'quotaFetchCount': PostingQuotaStore.fetchCount};
      }

      // ── ① 진입 → readiness/quota 완료 · 목록 gate 보류 ──
      await t.tap(find.text('host'));
      await frames(20);
      expect(find.byType(JobsRootScreen), findsOneWidget);
      expect(listGates.length, 1, reason: '목록 reader 1회 도달·보류');
      expect(listGates.single.isCompleted, isFalse);
      final readiness = FirstPostingReadinessStore.current.value;
      out('① 진입 · readiness=${readiness.status} allReady=${readiness.value?.allReady} · quota=${PostingQuotaStore.current.value.status} fetchCount=${PostingQuotaStore.fetchCount} · controller.isLoading=${ctl().isLoading} hasLoadedOnce=${ctl().hasLoadedOnce}');
      expect(readiness.isResolved, isTrue, reason: 'readiness 정상 완료');
      expect(readiness.value?.allReady, isTrue, reason: '정상 readiness(목록 표면)');
      expect(PostingQuotaStore.current.value.status, PostingQuotaStatus.loaded, reason: 'quota 정상 완료');
      final loadingText = find.text('공고 목록을 불러오는 중...');
      expect(loadingText, findsOneWidget, reason: '목록 loading(readiness spinner 와 별개)');
      expect(find.byType(WorkforceListView), findsOneWidget, reason: 'readiness 통과 뒤 목록 표면');
      expect(find.byType(TOGroupCard), findsNothing);
      out('① loading 글 ${t.getRect(loadingText)} · calls=$calls');
      expect(calls, expectedAtLoading, reason: 'loading 시점 정확 누적 사전');
      await vqCapture(t, key, '${c.id}_1_list_loading', conditions: cond('목록 reader gate 보류(공고 목록을 불러오는 중...)'));

      // ── ② 목록 정상 1개 → 슬롯 선로딩 → 카드 1 ──
      final beforeList = snapCalls();
      listGates.single.complete();
      await frames(20);
      expect(loadingText, findsNothing);
      final card = find.byType(TOGroupCard);
      expect(card, findsOneWidget, reason: '정상 카드 1');
      final listDelta = delta(beforeList);
      out('② 목록 해제 delta=$listDelta · calls=$calls · queryChecks=$queryChecks');
      expect(calls, expectedList1, reason: '목록1 정확 누적 사전');
      final g = ctl().items.single;
      final item = g.groupTOs.single;
      out('   group id=${g.id} groupName="${g.groupName}" master.title="${g.masterTO.title}" slot.title=${item.slot?.title} isGroupDetailLoaded=${g.isGroupDetailLoaded} slotDates=${g.slotDates.map(_kst).toList()} needsWorkDetailLoad=${item.needsWorkDetailLoad}');
      expect(g.groupName, kTitle);
      expect(g.isGroupDetailLoaded, isTrue, reason: '슬롯 선로딩 완료(펼침 때 슬롯 재조회 없음)');
      for (final q in queryChecks) {
        expect(q.contains('=false'), isFalse, reason: 'query 계약: $q');
      }
      List<String> cardTexts() => [
            ...t.widgetList<Text>(find.descendant(of: card, matching: find.byType(Text))).map((w) => w.data ?? w.textSpan?.toPlainText() ?? ''),
          ].map(visibleText).where((s) => s.trim().isNotEmpty).toList();
      out('   카드 글=${cardTexts()}');

      // 제목 전문 가시성
      final titleF = find.descendant(of: card, matching: find.text(kTitle));
      expect(titleF, findsOneWidget, reason: '원문 제목(semantics/finder 존재만으로 통과시키지 않는다)');
      final viewportR = t.getRect(listScrollable());
      String titleReport() {
        final p = t.renderObject<RenderParagraph>(titleF);
        final lines = _lines(p);
        final r = t.getRect(titleF);
        final w = t.widget<Text>(titleF);
        final inVp = r.top >= viewportR.top - 0.5 && r.bottom <= viewportR.bottom + 0.5;
        return 'rect=$r lines=$lines maxLines=${w.maxLines} overflow=${w.overflow} didExceedMaxLines=${p.didExceedMaxLines} inViewport=$inVp(viewport $viewportR)';
      }
      final titleP = t.renderObject<RenderParagraph>(titleF);
      out('   제목 ${titleReport()}');
      if (titleP.didExceedMaxLines) deferred.add('제목 끝 문구 "$kTitleEnd" 말줄임(didExceedMaxLines=true, ${_lines(titleP)}줄)');

      // 행동 영역(펼침 전)
      final header = find.ancestor(of: titleF, matching: find.byType(InkWell)).first;
      final arrowIcon = find.descendant(of: card, matching: find.byIcon(Icons.keyboard_arrow_down));
      expect(arrowIcon, findsOneWidget);
      final arrow = find.ancestor(of: arrowIcon, matching: find.byType(InkWell)).first;
      final staffText = find.descendant(of: card, matching: find.text('지원·근무 현황'));
      expect(staffText, findsOneWidget, reason: '다음 행동 라벨 = 인력 현황');
      final staff = find.ancestor(of: staffText, matching: find.byType(InkWell)).first;
      out('   header InkWell ${rr(header)}');
      out('   arrow InkWell ${rr(arrow)} · icon ${t.getRect(arrowIcon)}');
      out('   인력 현황 InkWell ${rr(staff)} · 글 ${t.getRect(staffText)} didExceedMaxLines=${t.renderObject<RenderParagraph>(staffText).didExceedMaxLines}');
      await vqCapture(t, key, '${c.id}_2_list_one', conditions: cond('정상 1개 · 펼침 전 · 제목 ${titleReport()} · arrow ${rr(arrow)} · 인력 현황 ${rr(staff)}'));

      // 화살표가 목록 viewport 밖이면 실제 끌기로 올린다(B 큰 글씨) — 기록만, 판정 아님
      final offBefore = scrollOffset();
      for (var k = 0; k < 40; k++) {
        final r = t.getRect(arrow);
        if (r.top >= viewportR.top - 0.5 && r.bottom <= viewportR.bottom + 0.5) break;
        await t.dragFrom(Offset(viewportR.left + 8, viewportR.center.dy), const Offset(0, -80));
        await frames(2);
      }
      await frames(4);
      final arrowR = t.getRect(arrow);
      final headerR = t.getRect(header);
      final staffR = t.getRect(staff);
      out('   탭 전 scroll ${offBefore.toStringAsFixed(1)} → ${scrollOffset().toStringAsFixed(1)} · arrow ${rr(arrow)} · header ${rr(header)}');
      if (arrowR.width < 48 || arrowR.height < 48) deferred.add('펼침 화살표 터치 ${arrowR.width.toStringAsFixed(1)}×${arrowR.height.toStringAsFixed(1)} < 48');
      if (!hits(arrow, arrowR.center)) deferred.add('펼침 화살표 중심 hit 실패');
      // [r2] 헤더는 B 에서 목록 viewport 보다 길다(448px) — 기하 중심이 목록 위 고정 머리(탭 바 등) 아래에 깔린다.
      //   사용자가 실제로 누를 수 있는 **보이는 부분**의 중심으로 판정한다(r1 harness 결함).
      final headerVis = headerR.intersect(viewportR);
      out('   header 보이는 부분 $headerVis center hit=${hits(header, headerVis.center)} path=${topHit(headerVis.center)} · 기하 중심 ${headerR.center} hit=${hits(header, headerR.center)}');
      if (headerVis.isEmpty || !hits(header, headerVis.center)) deferred.add('헤더 보이는 부분 중심 hit 실패');
      if (staffR.width < 48 || staffR.height < 48) deferred.add('인력 현황 터치 ${staffR.width.toStringAsFixed(1)}×${staffR.height.toStringAsFixed(1)} < 48');
      if (!hits(staff, staffR.center)) deferred.add('인력 현황 중심 hit 실패');

      // ── ③ 실제 펼침(화살표 중심 1회 탭) → capacity gate 보류 ──
      final beforeExpand = snapCalls();
      await t.tapAt(arrowR.center);
      await frames(6); // 300ms — 350ms 자동 scroll 타이머 전
      expect(capGates.length, 1, reason: 'capacity callable 1회 도달·보류');
      expect(capGates.single.isCompleted, isFalse);
      final expandHeldDelta = delta(beforeExpand);
      out('③ 펼침 탭 · capacity 보류 delta=$expandHeldDelta · item.needsWorkDetailLoad=${item.needsWorkDetailLoad} hasLoadedStats=${item.hasLoadedStats} statsFailed=${item.workDetailStatsFailed}');
      expect(expandHeldDelta, {'functions callableGetApplicationsByBiz@asia-northeast3': 1}, reason: '펼침 = capacity 1 · 슬롯 재조회 0');
      out('   보류 중 카드 글=${cardTexts()}');
      // 보류(미확인)를 실패로 말하지 않는다 — 감사59 §5.2 통계 해석(보류/미확인 → 정상 empty → 확인된 0 구분)
      final heldFail = find.descendant(of: card, matching: findVisibleText('지원 현황을 불러오지 못했습니다'));
      final heldLoading = find.descendant(of: card, matching: find.byType(CircularProgressIndicator));
      out('   보류 중 실패 문구=${heldFail.evaluate().length} · 카드 안 spinner=${heldLoading.evaluate().length} · 0 숫자 노출(충원 0 행)=${find.descendant(of: card, matching: find.text('미충원 3')).evaluate().length}');
      if (heldFail.evaluate().isNotEmpty) deferred.add('capacity 보류(요청 진행 중)인데 "지원 현황을 불러오지 못했습니다"+재시도 표시');
      expect(find.descendant(of: card, matching: find.text('미충원 3')), findsNothing, reason: '보류 중 확인되지 않은 0 을 숫자로 말하지 않는다');
      await vqCapture(t, key, '${c.id}_3_capacity_held', conditions: cond('펼침 · capacity gate1 보류(미확인)'));

      // 요약 counter(slot.workDetailCounts → TOItem.confirmedCount/pendingCount) 와 업무별 capacity 결과(workDetailStats) 출처 구분
      String sources() => '요약counter(slot): confirmed=${item.confirmedCount} pending=${item.pendingCount} required=${item.totalRequired}'
          ' slot.workDetailCounts[$kWd]=${item.slot?.countForDetail(kWd).confirmedCount}/${item.slot?.countForDetail(kWd).pendingCount}'
          ' · 업무별capacity: stats=${item.workDetailStats} statsFailed=${item.workDetailStatsFailed} hasLoadedStats=${item.hasLoadedStats} isWorkDetailLoaded=${item.isWorkDetailLoaded}';
      bool inVp(Rect r) => r.top >= viewportR.top - 0.5 && r.bottom <= viewportR.bottom + 0.5;
      // 실제 끌기로 대상을 목록 viewport 안으로(B). 위에 있으면 내리고 아래 있으면 올린다.
      Future<void> bring(Finder f) async {
        for (var k = 0; k < 60; k++) {
          final r = t.getRect(f);
          if (inVp(r)) break;
          final dy = r.top < viewportR.top ? 60.0 : -60.0;
          await t.dragFrom(Offset(viewportR.left + 8, viewportR.center.dy), Offset(0, dy));
          await frames(2);
        }
        await frames(4);
      }
      final failText = find.descendant(of: card, matching: findVisibleText('지원 현황을 불러오지 못했습니다'));
      final retryText = find.descendant(of: card, matching: find.text('재시도'));
      final loadingInCard = find.descendant(of: card, matching: find.text('불러오는 중...'));
      String phase() => '실패문구=${failText.evaluate().length} 재시도=${retryText.evaluate().length} 불러오는중=${loadingInCard.evaluate().length} 미충원3=${find.descendant(of: card, matching: find.text('미충원 3')).evaluate().length}';
      out('   gate1 보류 ${sources()} · ${phase()}');

      // ── ④ gate1 명시 오류 해제 → 실패 문구·재시도 ──
      final beforeFail = snapCalls();
      capGates[0].complete();
      await frames(40); // 350ms 자동 scroll + 300ms ensureVisible + AnimatedSize 300ms 이후
      out('④ gate1 오류 해제 · delta=${delta(beforeFail)} · ${sources()} · ${phase()}');
      expect(delta(beforeFail), isEmpty, reason: '실패 해제는 새 호출 없음');
      expect(calls, expectedAfterFail);
      expect(item.workDetailStatsFailed, isTrue, reason: '첫 실패는 오류로 남는다');
      expect(item.hasLoadedStats, isFalse, reason: '실패를 0 으로 확정하지 않는다');
      expect(failText, findsOneWidget, reason: '카드 실패 문구');
      expect(retryText, findsOneWidget, reason: '재시도 노출');
      expect(find.descendant(of: card, matching: find.text('미충원 3')), findsNothing, reason: '실패를 0 숫자로 말하지 않는다');
      out('   실패 카드 글=${cardTexts()}');
      final autoOff = scrollOffset();
      out('   자동 정렬 직후 scroll=${autoOff.toStringAsFixed(1)} · 실패 문구 ${t.getRect(failText)} inViewport=${inVp(t.getRect(failText))}');
      await bring(failText);
      final retryBtn = find.ancestor(of: retryText, matching: find.byType(TextButton)).first;
      await bring(retryBtn);
      final manualOff = scrollOffset();
      final retryR = t.getRect(retryBtn);
      out('   수동 끌기 뒤 scroll=${manualOff.toStringAsFixed(1)} · 실패 문구 ${t.getRect(failText)} inViewport=${inVp(t.getRect(failText))}');
      out('   재시도 TextButton ${rr(retryBtn)} · 글 ${t.getRect(retryText)} · inViewport=${inVp(retryR)}');
      if (retryR.width < 48 || retryR.height < 48) deferred.add('재시도 터치 ${retryR.width.toStringAsFixed(1)}×${retryR.height.toStringAsFixed(1)} < 48');
      if (!hits(retryBtn, retryR.center)) deferred.add('재시도 중심 hit 실패');
      expect(inVp(retryR), isTrue, reason: '재시도가 실제 끌기로 viewport 안');
      // [r2] 실패 문구 전문 가시성 — before r1 PNG(B)에서 `지원 현황을 …` 말줄임 관측. finder 존재만으로 통과시키지 않는다.
      final failP = t.renderObject<RenderParagraph>(failText);
      out('   실패 문구 전문: lines=${_lines(failP)} maxLines=${t.widget<Text>(failText).maxLines} didExceedMaxLines=${failP.didExceedMaxLines} rect=${t.getRect(failText)} inViewport=${inVp(t.getRect(failText))}');
      if (failP.didExceedMaxLines) deferred.add('실패 문구 "지원 현황을 불러오지 못했습니다" 말줄임(didExceedMaxLines=true)');
      if (!inVp(t.getRect(failText))) deferred.add('재시도와 실패 문구가 함께 viewport 안에 있지 않음');
      await vqCapture(t, key, '${c.id}_4_capacity_failure', conditions: cond('gate1 오류 해제 · 실패 문구/재시도 · 자동 scroll=${autoOff.toStringAsFixed(1)} → 수동 ${manualOff.toStringAsFixed(1)} · 재시도 ${rr(retryBtn)}'));

      // ── ⑤ 재시도 실제 중심 1회 → gate2 보류 ──
      final beforeRetry = snapCalls();
      await t.tapAt(retryR.center);
      await frames(6);
      final retryDelta = delta(beforeRetry);
      out('⑤ 재시도 탭 · delta=$retryDelta · capGates=${capGates.length} · ${sources()} · ${phase()}');
      expect(retryDelta, {'functions callableGetApplicationsByBiz@asia-northeast3': 1}, reason: '재시도 = capacity 정확 1회 증가');
      expect(capGates.length, 2);
      expect(capGates[1].isCompleted, isFalse);
      out('   gate2 보류 카드 글=${cardTexts()}');
      if (failText.evaluate().isNotEmpty) deferred.add('재시도 요청 진행 중(gate2 보류)인데 "지원 현황을 불러오지 못했습니다"+재시도 표시 유지');
      if (loadingInCard.evaluate().isEmpty) deferred.add('재시도 요청 진행 중 읽는 중 표시 없음');
      expect(find.descendant(of: card, matching: find.text('미충원 3')), findsNothing, reason: '보류 중 확인되지 않은 0 을 숫자로 말하지 않는다');
      await vqCapture(t, key, '${c.id}_5_retry_held', conditions: cond('재시도 → gate2 보류 · scroll=${scrollOffset().toStringAsFixed(1)}'));

      // ── ⑥ gate2 정상 empty → 확인된 0 복구 ──
      final beforeOk = snapCalls();
      capGates[1].complete();
      await frames(40);
      out('⑥ gate2 정상 해제 · delta=${delta(beforeOk)} · ${sources()} · ${phase()}');
      expect(delta(beforeOk), isEmpty);
      expect(item.workDetailStatsFailed, isFalse);
      expect(item.hasLoadedStats, isTrue);
      expect(item.workDetailStats?[kWd], {'confirmed': 0, 'pending': 0}, reason: 'seed wdId 확인된 0');
      expect(failText, findsNothing, reason: '복구 뒤 실패 문구 제거');
      final texts = cardTexts();
      out('   복구 카드 글=$texts');
      final joined = texts.join(' | ');
      for (final s in const ['충원 0', '필요 3', '부족 3', '대기 0', '미충원 3', '0/3']) {
        expect(joined.contains(s), isTrue, reason: '통계 라벨 "$s": $joined');
      }
      final rowF = find.descendant(of: card, matching: find.text('미충원 3'));
      final okAuto = scrollOffset();
      out('   복구 직후 scroll=${okAuto.toStringAsFixed(1)} · 업무 행 미충원 ${t.getRect(rowF)} inViewport=${inVp(t.getRect(rowF))}');
      await bring(rowF);
      final okManual = scrollOffset();
      final pos = t.state<ScrollableState>(listScrollable()).position;
      out('   수동 끌기 뒤 scroll=${okManual.toStringAsFixed(1)} max=${pos.maxScrollExtent.toStringAsFixed(1)} viewport=${pos.viewportDimension} · 업무 행 미충원 ${t.getRect(rowF)} inViewport=${inVp(t.getRect(rowF))}');
      expect(inVp(t.getRect(rowF)), isTrue, reason: '복구 통계 행이 실제 끌기로 viewport 안');
      final staff2 = find.ancestor(of: find.descendant(of: card, matching: find.text('지원·근무 현황')), matching: find.byType(InkWell)).first;
      out('   인력 현황(미탭) ${rr(staff2)}');
      await vqCapture(t, key, '${c.id}_6_recovered', conditions: cond('gate2 정상 · 확인된 0 · 자동 ${okAuto.toStringAsFixed(1)} → 수동 ${okManual.toStringAsFixed(1)}'));

      // ── 종료선: 정확 누적 사전 · 차단 시도 0 · gate 완료 ──
      await frames(10);
      out('최종 calls=$calls · fnRequests=${fnRequests.length} · quota.fetchCount=${PostingQuotaStore.fetchCount}');
      for (final r in fnRequests) {
        out('   fn ${r['functionName']}@${r['region']} params=${r['parameters']}');
      }
      expect(calls, expectedFinal, reason: '최종 정확 누적 사전(그 밖 read/write/callable 0)');
      expect(PostingQuotaStore.fetchCount, 1);
      String p(String name) => fnRequests.where((r) => r['functionName'] == name).map((r) => '${r['region']}:${r['parameters']}').join(' ; ');
      expect(p('callableGetPostingQuotaSummary'), 'asia-northeast3:${{'businessIds': [kBiz]}}');
      expect(p('callableGetAdminTOs'), 'asia-northeast3:${{'activeOnly': false, 'closedOnly': false, 'businessIds': [kBiz]}}');
      const capP = {'businessId': kBiz, 'toId': kTo, 'slotId': kSlot, 'purpose': 'capacity', 'limit': 2000};
      expect(p('callableGetApplicationsByBiz'), 'asia-northeast3:$capP ; asia-northeast3:$capP', reason: '두 capacity 요청 동일 payload');
      expect(listGates.every((g) => g.isCompleted) && capGates.every((g) => g.isCompleted), isTrue);
      FlutterError.onError = prev;
      out('overflows(${overflows.length})=${overflows.join(' | ')}');
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
      out('deferred(${deferred.length})=${deferred.join(' | ')}');
      expect(deferred, isEmpty, reason: deferred.join(' | '));
    });
  }
}

/// 실제 배치된 줄 수 — 전체 선택 상자의 서로 다른 top 개수(말줄임이면 보이는 줄까지만).
int _lines(RenderParagraph p) {
  final len = p.text.toPlainText().length;
  final boxes = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len));
  return boxes.map((b) => b.top.round()).toSet().length;
}
