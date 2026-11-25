// ignore_for_file: depend_on_referenced_packages
// [DU1 구현66 · 감사66 §5] S037-WORKFORCE-MARKER-FAILURE-RETRY-B/W — 근무 탭 달력 marker 조회만 실패 → 실제 재시도 → marker 복구(명단 불변).
//   하네스·fixture·진입은 du1_s037_workforce_nonzero_identity_test.dart(구현65) 복사.
//   production BusinessAdminShell() 루트(첫 탭 홈) → bottom-nav '근무' 중심 tapAt 1회 → WorkforceRootScreen → WorkforceOperationalView. Jobs 미방문.
//   fixture(구현65 동일): owner 사업장1 · 같은 근로자 UID · KST 오늘의 confirmed 단기 2건
//     A: app-c65-a … 상하차 00:00~00:01 근태 없음 · B: app-c65-b … 분류 00:02~00:03 명시 applicationId 근태 1건(00:02 출근·00:03 퇴근).
//   응답 고정(실행 전): 홈 day/근태 empty · AdminTOs empty · 근무 day 단기=[A,B] · day 장기=[] · 근태=[B] · directory=정상 이름(즉시) ·
//     marker 단기#1 gate→internal/LOCAL-S037-MARKER-FAILURE · marker 장기#1 즉시 [] · 재시도 marker 단기#2 gate→[A,B] · 장기#2 gate→[] · hasMore=false.
//   gate: 사업장(공유 확인) · marker 단기#1 · marker 단기#2/장기#2. day·directory 는 정상 해제(명단 먼저 보존).
//   marker 전용 안내 '근무가 있는 날짜를 표시하지 못했어요 / 다시 시도' 의 실제 탭 대상(GestureDetector 줄 전체)을 rect/48/hit 로 재고 중심 tapAt 1회.
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
  final markerShortGates = <Completer<void>>[];
  final markerLongGates = <Completer<void>>[];
  var markerShortN = 0;
  var markerLongN = 0;
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
          if (home || key == 'fn workerOperation day-long') return ok({'applications': const <Object?>[], 'hasMore': false});
          if (key == 'fn workerOperation marker-short') {
            final n = ++markerShortN;
            final g = Completer<void>();
            markerShortGates.add(g);
            await g.future;
            if (n == 1) return err('internal', 'LOCAL-S037-MARKER-FAILURE'); // 단기#1 명시 실패
            return ok({'applications': appsWire(), 'hasMore': false}); // 단기#2 [A,B]
          }
          if (key == 'fn workerOperation marker-long') {
            final n = ++markerLongN;
            if (n >= 2) {
              final g = Completer<void>();
              markerLongGates.add(g);
              await g.future;
            }
            return ok({'applications': const <Object?>[], 'hasMore': false}); // 장기#1 즉시 [] · 장기#2 gate→[]
          }
          return ok({'applications': appsWire(), 'hasMore': false}); // day-short [A,B]
        case 'callableGetUsersBatch':
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
  //   사업장 해제 뒤: day(단기·장기·근태)와 marker(단기#1 보류·장기#1)가 같은 회차에 나가고, day 성공 → directory 1(같은 UID 중복 제거) = 8.
  const expectedEntry = {
    'fn callableGetAdminTOs': 1,
    'fn callableGetMyBusiness': 1,
    'fn workerOperation day-short': 1,
    'fn workerOperation day-long': 1,
    'fn callableGetAdminAttendances day': 1,
    'fn workerOperation marker-short': 1,
    'fn workerOperation marker-long': 1,
    'fn callableGetUsersBatch workerDirectory[$kWorker]': 1,
  };
  //   재시도: 안내줄 onTap → _loadMarkerRange(force:true) 만. _ensureBusinesses 는 같은 scope 캐시(stale 아님)를 그대로 쓰므로
  //     MyBusiness/day/근태/directory/AdminTOs 추가 0 → marker 단기1·장기1 = 2. 홈10+진입8+재시도2 = 20.
  const expectedRetry = {'fn workerOperation marker-short': 1, 'fn workerOperation marker-long': 1};

  for (final c in const [
    (id: 'S037-WORKFORCE-MARKER-FAILURE-RETRY-B', w: 320.0, h: 640.0, s: 2.0),
    (id: 'S037-WORKFORCE-MARKER-FAILURE-RETRY-W', w: 360.0, h: 780.0, s: 1.0),
  ]) {
    testWidgets('${c.id} shell 근무 탭 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — marker 만 실패→실제 재시도→복구·명단 불변', (t) async {
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
      markerShortGates.clear();
      markerLongGates.clear();
      markerShortN = 0;
      markerLongN = 0;
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
      final dayLoading = find.text('근무 인력을 불러오는 중...');
      final errText = findVisibleText('데이터를 불러오지 못했습니다. 다시 시도해 주세요.');
      final emptyToday = findVisibleText('오늘 확정된 인력이 없습니다.'); // [DU604b] 빈 상태 글 keepWords — 보이는 글자로 찾는다(DU255 꼴)
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
          'responses': '홈 day 단기/장기·근태=empty · 근무 day 단기=[A,B] · day 장기=[] · 근태=[B 근태] · directory=[$kWorker:"$kWorkerName"](즉시) · marker 단기#1 gate→internal/LOCAL-S037-MARKER-FAILURE · marker 장기#1 즉시 [] · marker 단기#2 gate→[A,B] · 장기#2 gate→[] · hasMore=false · MyBusiness=[biz](gate) · 홈 전용 요약/인력준비/약관준비=unavailable/LOCAL-HOME-ONLY',
          'gates': 'business=${bizGates.map((g) => g.isCompleted).toList()} markerShort=${markerShortGates.map((g) => g.isCompleted).toList()} markerLong=${markerLongGates.map((g) => g.isCompleted).toList()}',
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
      // ── 공통: marker 안내·dot·명단 관측 ──
      final markerFail = find.descendant(of: view, matching: findVisibleText('근무가 있는 날짜를 표시하지 못했어요'));
      Finder markerRetry() => find.ancestor(of: markerFail, matching: find.byType(GestureDetector)).first;
      // 선택일(=오늘) 칩의 근무 marker — 선택 칩 안의 흰 4px 원(오늘 표시는 선택 시 그리지 않는다: _buildDayChip)
      final markerDot = find.descendant(of: view, matching: find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration && d.shape == BoxShape.circle && d.color == Colors.white &&
            w.constraints?.maxWidth == 4 && w.constraints?.maxHeight == 4;
      }));
      String markerState() => 'marker안내=${markerFail.evaluate().length} 선택일dot=${markerDot.evaluate().length}';
      Future<void> listIntact(String when) async {
        final sum = await summaryShown(when);
        expect(sum, ['2', '1', '1', '0'], reason: '$when: 요약 2/1/1/0 유지');
        final sa = await showRow(hA, '근태 처리', '$when A 행');
        final rowA = rowOf(hA);
        final sb = await showRow(hB, '퇴근 완료', '$when B 행');
        final rowB = rowOf(hB);
        out('   $when A="$rowA" · B="$rowB"');
        expect(rowA, contains(kWorkerName));
        expect(rowA, contains('00:00 출근 예정'));
        expect(rowA, contains('미출근'));
        expect(rowB, contains(kWorkerName));
        expect(rowB, contains('00:02 출근 · 00:03 퇴근'));
        expect(rowB, contains('퇴근 완료'));
        if (rowA.contains('출근 ·')) deferred.add('$when: A 행에 B 근태 전파');
        expect(errText, findsNothing, reason: '$when: 화면 전체 오류로 바꾸지 않는다');
        expect(emptyToday, findsNothing, reason: '$when: 오늘 0명으로 바꾸지 않는다');
        expect(findVisibleText('아직 근무를 관리할 사업장이 없어요'), findsNothing, reason: '$when: 사업장 없음으로 바꾸지 않는다');
        await vqCapture(t, key, '${c.id}_${when}_rows', conditions: cond('$when · 명단 · A $sa · B $sb · ${markerState()}'));
      }
      // 맨 위(주간 strip·marker 안내·요약)를 viewport 로 올려 marker 상태를 읽는다
      Future<String> topState(String when) async {
        final a = offset();
        await toTop();
        final s = '$when ${markerState()} · 요약=${summaryCounts()} · 직후 offset=${a.toStringAsFixed(1)} → 맨 위 ${offset().toStringAsFixed(1)}';
        out('   $s');
        await vqCapture(t, key, '${c.id}_${when}_top', conditions: cond(s));
        return s;
      }

      // ── ③ 사업장 해제 → day·directory 정상 · marker 단기#1 보류 ──
      bizGates[0].complete();
      await frames(10);
      out('③ 사업장 해제 · entry=${phaseCalls['entry']} · markerShortGates=${markerShortGates.length} · 그림 ${rendered()} · ${markerState()}');
      expect(phaseCalls['entry'], expectedEntry, reason: '근무 진입 정확 사전(marker 단기#1 보류 중)');
      expect(markerShortGates.length, 1);
      expect(markerShortGates.single.isCompleted, isFalse);
      await topState('3m');
      expect(markerFail, findsNothing, reason: '보류 중 — 아직 실패가 아니다');
      if (markerDot.evaluate().isNotEmpty) deferred.add('marker 보류 중 dot 표시(모름을 일 있음으로)');
      await listIntact('3m');

      // ── ④ marker 단기#1 명시 실패 ──
      final beforeFail = snap('entry');
      markerShortGates[0].complete();
      await frames(10);
      out('④ marker 단기#1 실패 해제 · delta=${delta('entry', beforeFail)}');
      expect(delta('entry', beforeFail), isEmpty, reason: '실패 해제 추가 조회 0');
      final t4 = await topState('4f');
      expect(markerFail, findsOneWidget, reason: 'marker 전용 실패 안내');
      expect(markerDot, findsNothing, reason: '실패 — dot 없음(일 없음 확정이 아니라 모름 + 안내)');
      final failP = t.renderObject<RenderParagraph>(find.descendant(of: markerFail, matching: find.byType(RichText)).first); // [DU255 r1]
      final retryTextF = find.descendant(of: markerRetry(), matching: find.text('다시 시도'));
      expect(retryTextF, findsOneWidget, reason: '안내 줄의 다시 시도');
      final mb = await bring(markerRetry(), '4f marker 재시도 줄');
      final retryR = t.getRect(markerRetry());
      out('   marker 안내 lines=${_lines(failP)} didExceedMaxLines=${failP.didExceedMaxLines} rect=${t.getRect(markerFail)} · 다시시도 글 ${t.getRect(retryTextF)}');
      out('   marker 재시도 탭 대상(GestureDetector 줄) ${rr(markerRetry())} · inVp=${inVp(retryR)} · $mb');
      if (retryR.width < 48 || retryR.height < 48) deferred.add('marker 재시도 터치 ${retryR.width.toStringAsFixed(1)}×${retryR.height.toStringAsFixed(1)} < 48');
      if (!hits(markerRetry(), retryR.center)) deferred.add('marker 재시도 중심 hit 실패');
      if (failP.didExceedMaxLines) deferred.add('marker 안내 말줄임');
      expect(inVp(retryR), isTrue);
      await vqCapture(t, key, '${c.id}_4f_retry_target', conditions: cond('marker 실패 · $t4 · 재시도 ${rr(markerRetry())} · $mb'));
      await listIntact('4f');

      // ── ⑤ 재시도 실제 중심 1회 → marker 단기#2·장기#2 보류 ──
      await toTop();
      await bring(markerRetry(), '5r 재시도 직전');
      final tapR = t.getRect(markerRetry());
      phase = 'retry';
      await t.tapAt(tapR.center);
      await frames(6);
      out('⑤ marker 재시도 탭 · retry=${phaseCalls['retry']} · markerShortGates=${markerShortGates.length} markerLongGates=${markerLongGates.length}');
      expect(phaseCalls['retry'], expectedRetry, reason: '재시도 = marker 단기1·장기1 · 그 밖 0');
      expect(markerShortGates.length, 2);
      expect(markerLongGates.length, 1);
      await topState('5r');
      // 현재 소스는 요청 시작에 _markerFailed 를 지우지 않는다 — 안내 유지/즉시 삭제 어느 쪽도 새 정책으로 기대하지 않고 관측만 남긴다.
      observations.add('재시도 보류 중 marker 안내=${markerFail.evaluate().length} · dot=${markerDot.evaluate().length}');
      if (markerDot.evaluate().isNotEmpty) deferred.add('marker 재시도 보류 중 dot 표시(아직 모름)');
      await listIntact('5r');

      // ── ⑥ marker 장기#2·단기#2 정상 해제 → 복구 ──
      final beforeOk = snap('retry');
      markerLongGates[0].complete();
      markerShortGates[1].complete();
      await frames(10);
      out('⑥ marker 정상 해제 · delta=${delta('retry', beforeOk)}');
      expect(delta('retry', beforeOk), isEmpty);
      await topState('6ok');
      expect(markerFail, findsNothing, reason: '복구 — 실패 안내 제거');
      expect(markerDot, findsOneWidget, reason: '복구 — 선택일(오늘) 근무 marker');
      await listIntact('6ok');

      // ── 종료선 ──
      await frames(10);
      final kstNowEnd = DateTime.now().toUtc().add(const Duration(hours: 9));
      expect(DateTime(kstNowEnd.year, kstNowEnd.month, kstNowEnd.day), civilToday, reason: '종료까지 같은 KST 일자');
      out('최종 phaseCalls=$phaseCalls · KST 종료=${_kst(DateTime.now())}');
      for (final r in fnRequests) {
        out('   fn[${r.phase}] ${r.key} params=${r.params}');
      }
      expect(phaseCalls['home'], expectedHome);
      expect(phaseCalls['entry'], expectedEntry);
      expect(phaseCalls['retry'], expectedRetry);
      final total = phaseCalls.values.fold<int>(0, (a, m) => a + m.values.fold<int>(0, (x, y) => x + y));
      expect(total, 20, reason: '홈10+진입8+재시도2');
      expect(PostingQuotaStore.fetchCount, 0);
      expect(bizGates.every((g) => g.isCompleted) && markerShortGates.every((g) => g.isCompleted) && markerLongGates.every((g) => g.isCompleted), isTrue);
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

/// 실제 배치된 줄 수 — 전체 선택 상자의 서로 다른 top 개수.
int _lines(RenderParagraph p) {
  final len = p.text.toPlainText().length;
  final boxes = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len));
  return boxes.map((b) => b.top.round()).toSet().length;
}
