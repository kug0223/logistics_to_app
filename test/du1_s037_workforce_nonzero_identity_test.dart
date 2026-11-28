// ignore_for_file: depend_on_referenced_packages
// [DU1 구현65 · 감사64 §5.2 · 감사65 §5] S037-WORKFORCE-NONZERO-ATTENDANCE-IDENTITY-B/W — 실제 shell 근무 탭의 비0 근무·근태 연결.
//   하네스는 du1_s037_workforce_entry_failure_retry_test.dart(구현63) 의 진입·Firebase 대역·계수 방식을 따른다.
//   production BusinessAdminShell() 루트(첫 탭 홈) → bottom-nav '근무' 중심 tapAt 1회 → WorkforceRootScreen → WorkforceOperationalView. Jobs 미방문.
//   fixture(감사65 §5.1): owner 사업장1 · 같은 근로자 UID · KST 선택일(오늘)의 confirmed 단기 지원서 2건
//     A: app-c65-a / to-c65-a / slot-c65-a / wd-c65-a · 업무 '상하차' 00:00~00:01 · 근태 없음
//     B: app-c65-b / to-c65-b / slot-c65-b / wd-c65-b · 업무 '분류'   00:02~00:03 · 명시 applicationId 근태 1건(00:02 출근·00:03 퇴근)
//   응답 고정(실행 전): 홈 단계의 day 단기/장기·근태 = 정상 empty(홈은 판정 대상 아님 · 비0 을 주지 않아 WorkDetailTimeService slot 조회 0) ·
//     근무 단계 day 단기 = A·B · day 장기 = empty · 근태 = B 근태 1 · marker 단기 = A·B · marker 장기 = empty · 모두 hasMore=false.
//   gate 순서(감사65 §5.4): 사업장(MyBusiness) → day 단기 → 사용자 directory(getUsersBatch) → 정상 해제.
//   요약 정상값 확정2/출근1/미출근1/노쇼0, 행별 격리, 출근칩→B 1행·미출근칩→A 1행·확정(전체)칩→2행. 행/다이얼로그/쓰기 탭 없음.
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

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/business_admin_shell.dart';
import 'package:ALfit/screens/business_admin/workforce_management/workforce_operational_view.dart';
import 'package:ALfit/services/business_posting_readiness.dart';
import 'package:ALfit/services/firestore_service.dart';
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

const kBiz = 'biz-local-c65';
const kOwner = 'owner-local-c65';
const kWorker = 'worker-local-c65';
const kWorkerName = 'QA 근로자 김하나'; // directory(정상 parse) 이름
const kSnapshotName = 'QA 지원 스냅샷'; // 지원서 snapshot — directory 실패 fallback 이면 이 이름이 보인다

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
  // BUSINESS_ADMIN 은 production 에서도 항상 허용(user_provider 각 판정의 첫 분기). 대역은 private _currentUser 를 못 채워 직접 돌려준다.
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

void main() {
  var phase = 'home';
  final phaseCalls = <String, Map<String, int>>{'home': {}, 'entry': {}, 'chips': {}};
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
  final civilToday = DateTime(todayK.year, todayK.month, todayK.day);
  final (dayStart, dayEnd) = FormatHelper.kstDayRange(FormatHelper.kstDayKeyOfCivil(civilToday));
  final anchor = DateTime(civilToday.year, civilToday.month, 1);
  final (markerStart, _) = FormatHelper.kstDayRange(FormatHelper.kstDayKeyOfCivil(anchor.subtract(const Duration(days: 7))));
  final (_, markerEnd) = FormatHelper.kstDayRange(
      FormatHelper.kstDayKeyOfCivil(DateTime(anchor.year, anchor.month + 1, 1).add(const Duration(days: 7))));
  DateTime kstAt(int h, int m) => dayStart.add(Duration(hours: h, minutes: m));

  ApplicationModel app(String id, String toId, String slotId, String wdId, String workType, String start, String end) => ApplicationModel(
        id: id, toId: toId, slotId: slotId, workDetailId: wdId, uid: kWorker, applicantName: kSnapshotName,
        businessId: kBiz, businessName: 'QA 물류센터', toTitle: 'QA $workType 공고', status: AppStatus.confirmed,
        selectedWorkType: workType, startTime: start, endTime: end, wage: 12000, wageType: 'hourly',
        workDate: dayStart, appliedAt: dayStart.subtract(const Duration(days: 2)),
      );
  final appA = app('app-c65-a', 'to-c65-a', 'slot-c65-a', 'wd-c65-a', '상하차', '00:00', '00:01');
  final appB = app('app-c65-b', 'to-c65-b', 'slot-c65-b', 'wd-c65-b', '분류', '00:02', '00:03');
  final attB = AttendanceModel(
    id: 'app-c65-b_day', applicationId: appB.id, userId: kWorker, businessId: kBiz, businessName: 'QA 물류센터',
    workDate: dayStart, workType: '분류', checkInAt: kstAt(0, 2), checkOutAt: kstAt(0, 3),
    status: AttendanceModel.statusPresent, wageStatus: 'pending', createdAt: dayStart,
  );
  List<Object?> appsWire() => [
        for (final a in [appA, appB]) Map<String, Object?>.from(_wire(a.toMap()) as Map)..['id'] = a.id,
      ];

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
        return codec.encodeMessage(<Object?>['du65-blocked', 'get 차단: $path', null]);
      }
      return codec.encodeMessage(<Object?>[PigeonDocumentSnapshot(path: path, data: data, metadata: meta)]);
    });
    m.setMockMessageHandler('$base.queryGet', (msg) async {
      final raw = String.fromCharCodes(msg!.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes));
      final String key;
      final List<PigeonDocumentSnapshot> docs;
      if (raw.contains('businesses/$kBiz/workTypes')) {
        key = 'query businesses/$kBiz/workTypes';
        docs = [
          PigeonDocumentSnapshot(path: 'businesses/$kBiz/workTypes/wt-c65', data: <String?, Object?>{
            'businessId': kBiz, 'name': '상하차', 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
            'displayOrder': 0, 'isActive': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
          }, metadata: meta),
        ];
      } else if (raw.contains('businesses/$kBiz/contract_templates')) {
        key = 'query businesses/$kBiz/contract_templates';
        docs = [
          PigeonDocumentSnapshot(path: 'businesses/$kBiz/contract_templates/tpl-c65', data: <String?, Object?>{
            'businessId': kBiz, 'name': '단기 근무 기본', 'templateType': 'daily', 'articles': const [],
            'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
          }, metadata: meta),
        ];
      } else {
        inc('query other');
        // ignore: avoid_print
        print('BLOCKED-QUERY ${raw.replaceAll(RegExp(r'[^\x20-\x7e]'), '.')}');
        return codec.encodeMessage(<Object?>['du65-blocked', 'query 차단', null]);
      }
      inc(key);
      return codec.encodeMessage(<Object?>[PigeonQuerySnapshot(documents: docs, documentChanges: const [], metadata: meta)]);
    });
    for (final op in const ['documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit',
      'transactionCreate', 'transactionStoreResult', 'transactionGet', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        inc(op);
        return codec.encodeMessage(<Object?>['du65-blocked', '$op 차단', null]);
      });
    }
  }

  final fnRequests = <({String phase, String key, Map<Object?, Object?> params})>[];
  final bizGates = <Completer<void>>[];
  final dayShortGates = <Completer<void>>[];
  final dirGates = <Completer<void>>[];
  String classifyWorkerOp(Map p) {
    if (p['businessId'] != kBiz || p['purpose'] != 'workerOperation' || p['limit'] != 2000) return 'workerOperation?unexpected-shape';
    final keys = p.keys.toSet();
    if (keys.containsAll({'workDateGteMs', 'workDateLtMs'}) && !keys.contains('workEndDateGteMs') && keys.length == 5) {
      if (p['workDateGteMs'] == dayStart.millisecondsSinceEpoch && p['workDateLtMs'] == dayEnd.millisecondsSinceEpoch) return 'day-short';
      if (p['workDateGteMs'] == markerStart.millisecondsSinceEpoch && p['workDateLtMs'] == markerEnd.millisecondsSinceEpoch) return 'marker-short';
      return 'short?unexpected-range';
    }
    if (keys.contains('workEndDateGteMs') && !keys.contains('workDateGteMs') && keys.length == 4) {
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
      } else if (name == 'callableGetUsersBatch') {
        final uids = params['uids'];
        final ok = params['businessId'] == kBiz && params['purpose'] == FirestoreService.purposeWorkerDirectory &&
            uids is List && uids.length == 1 && uids.single == kWorker && params.length == 3;
        key = 'fn callableGetUsersBatch ${ok ? 'workerDirectory[$kWorker]' : '?unexpected'}';
      } else if (const {'callableGetMyBusiness', 'callableGetAdminTOs', 'callableGetAdminHomeSummary',
          'callableGetStaffingReadiness', 'callableGetLegalReadiness'}.contains(name)) {
        key = 'fn $name';
      } else {
        key = 'functions.other $name@$region';
      }
      inc(key);
      fnRequests.add((phase: phase, key: key, params: params));
      ByteData? ok(Object? v) => c.encodeMessage(<Object?>[v]);
      ByteData? err(String code, String m) => c.encodeMessage(<Object?>[code, m, <String, Object?>{'code': code, 'message': m}]);
      if (key.contains('unexpected') || key.startsWith('functions.other')) return err('not-found', 'du65-blocked');
      final home = phase == 'home';
      switch (name) {
        case 'callableGetMyBusiness':
          final g = Completer<void>();
          bizGates.add(g);
          await g.future;
          return ok({'businesses': [bizMap()]});
        case 'callableGetAdminTOs':
          return ok({'items': const <Object?>[]});
        case 'callableGetAdminAttendances':
          return ok({
            'items': home ? const <Object?>[] : [Map<String, Object?>.from(_wire(attB.toMap()) as Map)..['id'] = attB.id],
            'limitReached': false,
          });
        case 'callableGetApplicationsByBiz':
          if (home || key.endsWith('-long')) return ok({'applications': const <Object?>[], 'hasMore': false});
          if (key == 'fn workerOperation day-short') {
            final g = Completer<void>();
            dayShortGates.add(g);
            await g.future;
          }
          return ok({'applications': appsWire(), 'hasMore': false}); // day-short · marker-short
        case 'callableGetUsersBatch':
          final g = Completer<void>();
          dirGates.add(g);
          await g.future;
          return ok({
            'users': {
              kWorker: {'name': kWorkerName, 'role': 'USER', 'username': 'worker', 'email': 'w@test.local'},
            },
          });
        default:
          return err('unavailable', 'LOCAL-HOME-ONLY');
      }
    });
  }

  // ── 실행 전 고정 사전(소스 근거) ──
  //   홈: 구현63 과 같은 10종(홈의 오늘 근태·확정자 조회는 이번에도 정상 empty 로 응답 → WorkDetailTimeService 대상 0 → slot get 0).
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
  //   근무 진입: 구현63 의 7 + 근무자 2건(같은 UID) → _loadDayData 의 getUsersBatch(purpose=workerDirectory) — UID set 중복 제거로 uids=[kWorker] 1회.
  //     FirestoreService 목적별 사용자 cache 는 셀 시작에 clearCache() 로 비운다(B 의 응답이 W 호출을 생략시키지 않게).
  const expectedEntryBizHeld = {'fn callableGetAdminTOs': 1, 'fn callableGetMyBusiness': 1};
  const expectedEntryDayHeld = {
    'fn callableGetAdminTOs': 1,
    'fn callableGetMyBusiness': 1,
    'fn workerOperation day-short': 1,
    'fn workerOperation day-long': 1,
    'fn callableGetAdminAttendances day': 1,
    'fn workerOperation marker-short': 1,
    'fn workerOperation marker-long': 1,
  };
  const expectedEntry = {...expectedEntryDayHeld, 'fn callableGetUsersBatch workerDirectory[$kWorker]': 1};
  //   칩 탭: setState 필터만(_activeFilter) — 추가 조회 0.
  const expectedChips = <String, int>{};

  for (final c in const [
    (id: 'S037-WORKFORCE-NONZERO-ATTENDANCE-IDENTITY-B', w: 320.0, h: 640.0, s: 2.0),
    (id: 'S037-WORKFORCE-NONZERO-ATTENDANCE-IDENTITY-W', w: 360.0, h: 780.0, s: 1.0),
  ]) {
    testWidgets('${c.id} shell 근무 탭 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 같은 근로자 두 근무·근태 1건 연결·칩 필터', (t) async {
      await t.runAsync(vqLoadFonts);
      FirstPostingReadinessStore.reset();
      PostingQuotaStore.reset();
      PostingQuotaStore.fetchCount = 0;
      FirestoreService().clearCache(); // 목적별 사용자 cache 차갑게 — 셀 간 공유 방지
      phase = 'home';
      for (final m in phaseCalls.values) {
        m.clear();
      }
      fnRequests.clear();
      bizGates.clear();
      dayShortGates.clear();
      dirGates.clear();
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
      // 실제 clock 유효조건(감사65 §5.2): 같은 KST 선택일 · 00:03 이후
      final kstNowStart = DateTime.now().toUtc().add(const Duration(hours: 9));
      out('${c.id} 실행 local=${DateTime.now().toIso8601String()} utc=${DateTime.now().toUtc().toIso8601String()} tz=${now.timeZoneName}(${now.timeZoneOffset}) · KST now=${_kst(DateTime.now())}');
      out('   선택일(KST civil)=${civilToday.toIso8601String().substring(0, 10)} · day 창 [${_kst(dayStart)}, ${_kst(dayEnd)}) · marker 창 [${_kst(markerStart)}, ${_kst(markerEnd)})');
      out('   A ${appA.id}/${appA.toId}/${appA.slotId}/${appA.workDetailId} 상하차 00:00~00:01 · B ${appB.id}/${appB.toId}/${appB.slotId}/${appB.workDetailId} 분류 00:02~00:03'
          ' · B 근태 checkIn=${_kst(attB.checkInAt!)} checkOut=${_kst(attB.checkOutAt!)} · worker=$kWorker');
      expect(kstNowStart.hour * 60 + kstNowStart.minute >= 3, isTrue, reason: '00:03 KST 이후에만 정상 2/1/1/0 증거로 쓴다');
      expect(DateTime(kstNowStart.year, kstNowStart.month, kstNowStart.day), civilToday, reason: '선택일 = 실행 KST 일자');
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
      final countF = find.descendant(of: view, matching: find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == 20));
      List<String> summaryCounts() => view.evaluate().isEmpty ? const [] : t.widgetList<Text>(countF).map((w) => w.data ?? '').toList();
      final dayLoading = findVisibleText('근무 인력을 불러오는 중...');
      final errText = find.text('데이터를 불러오지 못했습니다. 다시 시도해 주세요.');
      final emptyToday = findVisibleText('오늘 확정된 인력이 없습니다.');
      const hA = '00:00–00:01';
      const hB = '00:02–00:03';
      Finder headerF(String h) => find.descendant(of: view, matching: find.byWidgetPredicate((w) => w is Text && visibleText(w.data ?? w.textSpan?.toPlainText() ?? '').contains(h)));
      Finder scroll() => find.descendant(of: find.descendant(of: view, matching: find.byType(CustomScrollView)), matching: find.byType(Scrollable)).first;
      double offset() => t.state<ScrollableState>(scroll()).position.pixels;
      Rect vp() => t.getRect(scroll());
      bool inVp(Rect r) => r.top >= vp().top - 0.5 && r.bottom <= vp().bottom + 0.5;
      Future<String> bring(Finder f, String when) async {
        final a = offset();
        final r0 = t.getRect(f.first);
        for (var k = 0; k < 60; k++) {
          final r = t.getRect(f.first);
          if (inVp(r)) break;
          final dy = r.top < vp().top ? 60.0 : -60.0;
          await t.dragFrom(Offset(vp().left + 8, vp().center.dy), Offset(0, dy));
          await frames(2);
        }
        await frames(2);
        final s = '직후 offset=${a.toStringAsFixed(1)} 대상 $r0 inVp=${inVp(r0)} → 끌기 뒤 offset=${offset().toStringAsFixed(1)} 대상 ${t.getRect(f.first)} inVp=${inVp(t.getRect(f.first))}';
        out('   $when $s');
        return s;
      }
      // lazy sliver — 대상이 만들어질 때까지 실제 끌기로 내려간 뒤 viewport 로 맞춘다
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
      Future<void> toTop() async {
        for (var k = 0; k < 60 && offset() > 0.5; k++) {
          await t.dragFrom(Offset(vp().left + 8, vp().center.dy), const Offset(0, 80));
          await frames(2);
        }
        await frames(2);
      }
      Future<List<String>> summaryShown(String when) async {
        final a = offset();
        await toTop();
        final s = summaryCounts();
        out('   $when 요약=$s (직후 offset=${a.toStringAsFixed(1)} → 맨 위 ${offset().toStringAsFixed(1)})');
        return s;
      }
      /// 위에서 아래까지 실제로 끌어 내려가며 보이는 근무 머리(시간대)를 모은다 — lazy Text 존재만으로 결과를 단정하지 않는다.
      Future<Set<String>> rowsSeen(String when) async {
        await toTop();
        final seen = <String>{};
        for (var k = 0; k < 60; k++) {
          for (final h in const [hA, hB]) {
            final f = headerF(h);
            if (f.evaluate().isNotEmpty && inVp(t.getRect(f.first))) seen.add(h);
          }
          final pos = t.state<ScrollableState>(scroll()).position;
          if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
          await t.dragFrom(Offset(vp().left + 8, vp().center.dy), const Offset(0, -60));
          await frames(2);
        }
        out('   $when 실제 viewport 안에서 본 근무 머리=$seen (끝 offset=${offset().toStringAsFixed(1)})');
        return seen;
      }
      /// 한 근무 행 — 그 머리(시간대)부터 다음 시간대 머리 전까지의 Text.
      String rowOf(String header) {
        final s = viewTexts();
        final i = s.indexWhere((x) => x.contains(header));
        if (i < 0) return '';
        final rest = s.sublist(i + 1);
        var j = rest.indexWhere((x) => RegExp(r'\d{2}:\d{2}–\d{2}:\d{2}').hasMatch(x));
        // [r2] 다음 그룹의 업무 라벨(시간 머리 바로 앞)은 그 그룹 것이다 — 이 행에서 뺀다. 이 그룹의 라벨은 머리 바로 앞에서 가져온다.
        const labels = {'상하차', '분류'};
        if (j >= 1 && labels.contains(rest[j - 1])) j -= 1;
        final own = i >= 1 && labels.contains(s[i - 1]) ? [s[i - 1]] : const <String>[];
        return [...own, s[i], ...(j < 0 ? rest : rest.sublist(0, j))].join(' | ');
      }
      Finder chipOf(String label) => find.ancestor(
          of: find.descendant(of: view, matching: find.text(label)),
          matching: find.byWidgetPredicate((w) => w is GestureDetector && w.child is AnimatedContainer)).first;
      String rendered() => '요약=${summaryCounts()} · 인력로딩=${dayLoading.evaluate().length} 오류=${errText.evaluate().length} 오늘0명=${emptyToday.evaluate().length}'
          ' · A머리=${headerF(hA).evaluate().length} B머리=${headerF(hB).evaluate().length} · 근로자명=${find.descendant(of: view, matching: find.textContaining(kWorkerName)).evaluate().length} 스냅샷명=${find.descendant(of: view, matching: find.textContaining(kSnapshotName)).evaluate().length}';
      Map<String, Object?> cond(String state) {
        final m = MediaQuery.of(t.element(find.byType(BusinessAdminShell)));
        return {
          'entry': 'LOCAL MaterialApp(home: BusinessAdminShell()) · 첫 탭 홈 → bottom-nav 근무 실제 tapAt 1회 → WorkforceRootScreen → WorkforceOperationalView · Jobs 미방문',
          'theme': 'RoleTheme.businessAdminTheme', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
          'mqNow': 'size=${m.size} padding=${m.padding} viewPadding=${m.viewPadding} viewInsets=${m.viewInsets}',
          'physicalInsetBottomNow': t.view.viewInsets.bottom,
          'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK)', 'prefs': 'setMockInitialValues({})',
          'clock': '미주입(KST ${_kst(DateTime.now())})',
          'selectedDay': '${civilToday.toIso8601String().substring(0, 10)}(KST 오늘·화면 기본값) day창 ${dayStart.millisecondsSinceEpoch}~${dayEnd.millisecondsSinceEpoch} marker창 ${markerStart.millisecondsSinceEpoch}~${markerEnd.millisecondsSinceEpoch}',
          'fixture': 'owner $kOwner · biz $kBiz · 공고0(AdminTOs items=[]) · worker $kWorker(directory 이름 "$kWorkerName", 지원서 snapshot "$kSnapshotName") · '
              'A ${appA.id}/${appA.toId}/${appA.slotId}/${appA.workDetailId} 상하차 00:00~00:01 근태 없음 · B ${appB.id}/${appB.toId}/${appB.slotId}/${appB.workDetailId} 분류 00:02~00:03 근태 ${attB.id}(applicationId=${appB.id}) 00:02 출근·00:03 퇴근',
          'responses': '홈 단계 day 단기/장기·근태=empty · 근무 단계 day 단기=[A,B](gate) · day 장기=[] · 근태=[B 근태] · marker 단기=[A,B] · marker 장기=[] · hasMore=false · '
              'MyBusiness=[biz](gate) · getUsersBatch(workerDirectory)=[$kWorker:"$kWorkerName"](gate) · 홈 전용 요약/인력준비/약관준비=unavailable/LOCAL-HOME-ONLY',
          'gates': 'business=${bizGates.map((g) => g.isCompleted).toList()} dayShort=${dayShortGates.map((g) => g.isCompleted).toList()} directory=${dirGates.map((g) => g.isCompleted).toList()}',
          'state': state, 'phase': phase, 'calls': phaseCalls.toString()};
      }

      // ── ① 홈 ──
      await frames(40);
      out('① 홈 단계 calls=${phaseCalls['home']}');
      expect(view, findsNothing);
      expect(phaseCalls['home'], expectedHome, reason: '홈 단계 정확 사전');
      final navItem = find.ancestor(of: find.text('근무'), matching: find.byType(InkResponse)).first;
      out('   근무 탭 ${rr(navItem)}');
      await vqCapture(t, key, '${c.id}_1_home', conditions: cond('shell 진입 · 홈 · 근무 탭 전'));

      // ── ② 근무 탭 → 사업장 gate 보류 ──
      phase = 'entry';
      await t.tapAt(t.getRect(navItem).center);
      await frames(6);
      out('② 근무 탭 · entry=${phaseCalls['entry']} · 그림 ${rendered()}');
      expect(phaseCalls['entry'], expectedEntryBizHeld, reason: '사업장 보류 — AdminTOs1+MyBusiness1 만');
      expect(bizGates.length, 1);
      await vqCapture(t, key, '${c.id}_2_business_held', conditions: cond('callableGetMyBusiness gate 보류'));

      // ── ③ 사업장 해제 → day 단기 gate 보류 ──
      bizGates[0].complete();
      await frames(6);
      out('③ 사업장 해제 · entry=${phaseCalls['entry']} · 그림 ${rendered()}');
      expect(phaseCalls['entry'], expectedEntryDayHeld, reason: 'day 보류 — directory 0');
      expect(dayShortGates.length, 1);
      final s3 = await summaryShown('day 보류');
      if (s3.any((x) => x != '-')) deferred.add('day 보류 중 요약이 "-" 아님($s3)');
      final h3 = await show(dayLoading, 'day 보류 로딩');
      if (dayLoading.evaluate().isEmpty) deferred.add('day 보류 중 로딩 표시 없음');
      await vqCapture(t, key, '${c.id}_3_day_held', conditions: cond('day 단기 gate 보류 · $h3 · ${rendered()}'));

      // ── ④ day 해제 → directory gate 보류 ──
      final beforeDay = snap('entry');
      dayShortGates[0].complete();
      await frames(6);
      out('④ day 해제 · delta=${delta('entry', beforeDay)} · 그림 ${rendered()}');
      expect(delta('entry', beforeDay), {'fn callableGetUsersBatch workerDirectory[$kWorker]': 1}, reason: '같은 UID 2근무 → directory 1(uids 중복 제거)');
      expect(dirGates.length, 1);
      final s4 = await summaryShown('directory 보류');
      if (s4.any((x) => x != '-')) deferred.add('directory 보류 중 요약 정상값 선확정($s4)');
      final h4 = await show(dayLoading, 'directory 보류 로딩');
      if (dayLoading.evaluate().isEmpty) deferred.add('directory 보류 중 로딩 표시 없음');
      if (headerF(hA).evaluate().isNotEmpty || headerF(hB).evaluate().isNotEmpty) deferred.add('directory 보류 중 근무 행을 먼저 그림');
      await vqCapture(t, key, '${c.id}_4_directory_held', conditions: cond('getUsersBatch(workerDirectory) gate 보류 · $h4 · ${rendered()}'));

      // ── ⑤ directory 정상 해제 → 확정2/출근1/미출근1/노쇼0 ──
      final beforeDir = snap('entry');
      dirGates[0].complete();
      await frames(10);
      out('⑤ directory 해제 · delta=${delta('entry', beforeDir)}');
      expect(delta('entry', beforeDir), isEmpty);
      expect(phaseCalls['entry'], expectedEntry, reason: '근무 진입 정확 사전');
      final sum = await summaryShown('정상');
      out('   그림 ${rendered()}');
      expect(sum, ['2', '1', '1', '0'], reason: '확정2/출근1/미출근1/노쇼0');
      await vqCapture(t, key, '${c.id}_5a_summary', conditions: cond('정상 · 요약 ${sum.join('/')} · offset=${offset().toStringAsFixed(1)}'));
      // 행별: A(상하차 00:00–00:01, 근태 없음) / B(분류 00:02–00:03, 00:02 출근·00:03 퇴근, 퇴근 완료)
      // [r2] 머리만 viewport 에 넣으면 B(320@2.0)에서 아래 근로자 행 Text 가 아직 없다(r1) — 행의 상태 Text 까지 실제 끌기로 넣는다.
      Future<String> showRow(String header, String statusText, String when) async {
        final s1 = await show(headerF(header), '$when 머리');
        final st = find.descendant(of: view, matching: find.text(statusText));
        final s2 = await show(st, '$when 상태("$statusText")');
        final hr = headerF(header).evaluate().isEmpty ? null : t.getRect(headerF(header).first);
        final sr = st.evaluate().isEmpty ? null : t.getRect(st.first);
        final s = '$s1 / $s2 · 머리 inVp=${hr != null && inVp(hr)} 상태 inVp=${sr != null && inVp(sr)}';
        if (sr == null || !inVp(sr)) deferred.add('$when 상태 "$statusText" 가 viewport 에 도달하지 않음');
        return s;
      }
      final ha = await showRow(hA, '근태 처리', 'A 행');
      final rowA = rowOf(hA);
      out('   A 행="$rowA"');
      await vqCapture(t, key, '${c.id}_5b_row_a', conditions: cond('정상 · A 행 · $ha · "$rowA"'));
      final hb = await showRow(hB, '퇴근 완료', 'B 행');
      final rowB = rowOf(hB);
      out('   B 행="$rowB"');
      await vqCapture(t, key, '${c.id}_5c_row_b', conditions: cond('정상 · B 행 · $hb · "$rowB"'));
      expect(rowA, contains(kWorkerName), reason: 'A 행 근로자명(directory)');
      expect(rowB, contains(kWorkerName), reason: 'B 행 근로자명(directory)');
      if (rowA.contains(kSnapshotName) || rowB.contains(kSnapshotName)) deferred.add('directory 성공인데 snapshot 이름 표시');
      expect(rowA, contains('상하차'));
      expect(rowB, contains('분류'));
      expect(rowB, contains('00:02 출근 · 00:03 퇴근'), reason: 'B 자기 근태');
      expect(rowB, contains('퇴근 완료'));
      if (rowA.contains('출근 ·') || rowA.contains('퇴근 완료')) deferred.add('A 행에 다른 근무(B)의 출퇴근/퇴근완료 전파: $rowA');
      expect(rowA, contains('00:00 출근 예정'));
      expect(rowA, contains('미출근'));
      final allRows = await rowsSeen('전체');
      expect(allRows, {hA, hB}, reason: '두 canonical 근무가 합쳐지지 않고 2행');

      // ── ⑥ 칩: 출근 → B 1행, 미출근 → A 1행, 확정(전체) → 2행 ──
      phase = 'chips';
      Future<void> tapChip(String label, Set<String> want, String capId) async {
        await toTop();
        final chip = chipOf(label);
        // [r3] B(320@2.0)는 2×2 칩 아랫줄이 맨 위 offset 에서도 viewport 아래에 걸친다(r2) — 실제 끌기로 넣고 누른다.
        final cb = await bring(chip, '칩 "$label"');
        final r = t.getRect(chip);
        out('⑥ 칩 "$label" ${rr(chip)} inVp=${inVp(r)} · $cb');
        if (r.width < 48 || r.height < 48) deferred.add('칩 "$label" 터치 ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} < 48');
        if (!hits(chip, r.center)) deferred.add('칩 "$label" 중심 hit 실패');
        expect(inVp(r), isTrue, reason: '칩 viewport 안');
        final before = snap('chips');
        await t.tapAt(r.center);
        await frames(4);
        expect(delta('chips', before), isEmpty, reason: '칩 탭 추가 조회 0');
        final seen = await rowsSeen('칩 "$label" 뒤');
        expect(seen, want, reason: '칩 "$label" 결과 행');
        await toTop();
        await vqCapture(t, key, '${c.id}_6${capId}_chip', conditions: cond('칩 "$label" 탭 뒤 · 본 행=$seen · ${rendered()}'));
        final last = want.length == 1 ? want.single : hB;
        final hl = await show(headerF(last), '칩 "$label" 결과 행');
        await vqCapture(t, key, '${c.id}_6${capId}_row', conditions: cond('칩 "$label" 결과 행 · $hl · "${rowOf(last)}"'));
      }
      await tapChip('출근', {hB}, 'a');
      await tapChip('미출근', {hA}, 'b');
      await tapChip('확정', {hA, hB}, 'c');

      // ── 종료선 ──
      await frames(10);
      final kstNowEnd = DateTime.now().toUtc().add(const Duration(hours: 9));
      expect(DateTime(kstNowEnd.year, kstNowEnd.month, kstNowEnd.day), civilToday, reason: '종료까지 같은 KST 일자(자정 통과 실행은 증거로 쓰지 않는다)');
      out('최종 phaseCalls=$phaseCalls · KST 종료=${_kst(DateTime.now())}');
      for (final r in fnRequests) {
        out('   fn[${r.phase}] ${r.key} params=${r.params}');
      }
      expect(phaseCalls['home'], expectedHome);
      expect(phaseCalls['entry'], expectedEntry);
      expect(phaseCalls['chips'], expectedChips);
      expect(PostingQuotaStore.fetchCount, 0);
      expect(bizGates.every((g) => g.isCompleted) && dayShortGates.every((g) => g.isCompleted) && dirGates.every((g) => g.isCompleted), isTrue);
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
