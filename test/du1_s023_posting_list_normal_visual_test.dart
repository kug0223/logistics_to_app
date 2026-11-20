// ignore_for_file: depend_on_referenced_packages
// [DU1 후속73 §2] S023 관리자 공고 TAB + S035 WorkforceListView INLINE_VIEW **정상 목록** 기본 시각.
//   하네스는 du1_c2_multislot_capacity_failure_retry_test.dart(구현61) 진입·reader 경계를 복사하고, 보류·실패·재시도 사건을 뺐다.
//   LOCAL host → Navigator.push(JobsRootScreen()) · owner BUSINESS_ADMIN · 단일 approved 사업장 · license/owner seal · 업무1·템플릿1.
//   fixture: 같은 사업장 진행중 공고 2개 — A(flex, 2날짜 +7/+8, 상하차 10:00~13:00 필요3씩, 긴 제목) · B(flex, 1날짜 +9, 상하차 14:00~18:00 필요2, 시급 13,000).
//     counter 전부 0/0 이고 capacity 응답도 applications=[] — 같은 사실(확인된 0). quota used2/limit10.
//   장면: ① 정상 첫 화면 ② 실제 drag 뒤 두 번째 공고 ③ A 실제 펼침(날짜칩) ④ A 날짜1(+8) 실제 칩 탭 → capacity 정상 → 상세.
//   허용 reader 외 Firestore/Functions 는 차단·계수 0. 서버 성공/권한/DEVICE 검증이 아니다.
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
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/widgets/admin/cards/admin_to_group_card.dart';

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

const kBiz = 'biz-local-c59';
const kOwner = 'owner-local-c59';
const kTo = 'to-local-c59';
const kSlot = 'slot-local-c61-t'; // 대상(+8)
const kSlotO = 'slot-local-c61-o'; // 다른 날짜(+7)
const kWd = 'wd-local-c61-t';
const kWdO = 'wd-local-c61-o';
const kWdMaster = 'wd-local-c61-master';
// 고정 긴 한글 제목 — 끝 문구 `안전화 지참 필수` 로 전문 가시성을 판정한다.
const kTitleEnd = '안전화 지참 필수';
const kTitle = '송파 물류센터 주말 오전 상하차·분류 보조 단기 인력 모집 $kTitleEnd';
const kTo2 = 'to-local-c73b';
const kSlot2 = 'slot-local-c73b';
const kWd2 = 'wd-local-c73b';
const kTitle2 = '평택 2공장 평일 오후 상하차 단기';

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

  // ── 실행 시계 기준 fixture(셀마다 같은 값) — 감사61 §5.1 ──
  //   슬롯 2개: 다른 날짜 O = 오늘(KST)+7, 대상 날짜 T = 오늘(KST)+8 (각 KST 자정 instant).
  //   각 슬롯 상하차 1개/필요3, 지원 마감 = 그날 08:00 KST, 근무 10:00~13:00.
  //   counter: T 0/0 · O 0/0 · master 합 confirmed0/pending0/required6 · B 0/0/required2.
  //   [DU1 후속105 · 감사74 §4-1] 이전 주석·출력의 confirmed1/totalConfirmed=1 은 앞 시험에서 남은 낡은 설명이었다 —
  //   실제 선언(아래 counter·workDetailCounts·status)은 모두 0 이다. 설명만 실데이터에 맞췄다(fixture 무변경).
  final now = DateTime.now();
  final kstNow = now.toUtc().add(const Duration(hours: 9));
  DateTime kstDay(int plus) => DateTime.utc(kstNow.year, kstNow.month, kstNow.day)
      .add(Duration(days: plus))
      .subtract(const Duration(hours: 9))
      .toLocal();
  String keyOf(DateTime d) {
    final k = d.toUtc().add(const Duration(hours: 9));
    return '${k.year}-${k.month.toString().padLeft(2, '0')}-${k.day.toString().padLeft(2, '0')}';
  }
  final otherDate = kstDay(7);
  final workDate = kstDay(8); // 대상
  final created = now.subtract(const Duration(days: 1));
  final otherDeadline = otherDate.add(const Duration(hours: 8));
  final wdDeadline = workDate.add(const Duration(hours: 8));
  final otherKey = keyOf(otherDate);
  final workKey = keyOf(workDate);

  WorkDetailData wdOf(String id, DateTime deadline) => WorkDetailData(
        wdId: id, workType: '상하차', workTypeId: 'wt-c59', startTime: '10:00', endTime: '13:00',
        requiredCount: 3, wage: 12000, wageType: 'hourly', applicationDeadline: deadline,
      );
  WorkDetailData wd() => wdOf(kWd, wdDeadline);
  TOModel master() => TOModel(
        id: kTo, businessId: kBiz, businessName: 'QA 물류센터', type: 'flex', title: kTitle, creatorUID: kOwner,
        status: TOStatus.active, workDetails: [wdOf(kWdMaster, otherDeadline)], totalSlots: 2, slotDateKeys: [otherKey, workKey],
        totalRequired: 6, totalConfirmed: 0, totalPending: 0,
        isPublished: true, publishMode: 'immediate', rangeStart: otherDate, rangeEnd: workDate,
        deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2,
        createdAt: created, statusUpdatedAt: created,
      );
  SlotModel slot() => SlotModel(
        id: kSlot, toId: kTo, date: workDate, workDetails: [wd()],
        workDetailCounts: const {kWd: SlotWorkTypeCount(confirmedCount: 0, pendingCount: 0)},
        status: SlotStatus.open, confirmedCount: 0, pendingCount: 0,
        applicationDeadline: wdDeadline, visibleFrom: created, createdAt: created,
      );
  SlotModel otherSlot() => SlotModel(
        id: kSlotO, toId: kTo, date: otherDate, workDetails: [wdOf(kWdO, otherDeadline)],
        workDetailCounts: const {kWdO: SlotWorkTypeCount(confirmedCount: 0, pendingCount: 0)},
        status: SlotStatus.open, confirmedCount: 0, pendingCount: 0,
        applicationDeadline: otherDeadline, visibleFrom: created, createdAt: created,
      );

  final date2 = kstDay(9);
  final deadline2 = date2.add(const Duration(hours: 12));
  final key2 = keyOf(date2);
  WorkDetailData wd2() => WorkDetailData(
        wdId: kWd2, workType: '상하차', workTypeId: 'wt-c59', startTime: '14:00', endTime: '18:00',
        requiredCount: 2, wage: 13000, wageType: 'hourly', applicationDeadline: deadline2,
      );
  TOModel master2() => TOModel(
        id: kTo2, businessId: kBiz, businessName: 'QA 물류센터', type: 'flex', title: kTitle2, creatorUID: kOwner,
        status: TOStatus.active, workDetails: [wd2()], totalSlots: 1, slotDateKeys: [key2],
        totalRequired: 2, totalConfirmed: 0, totalPending: 0,
        isPublished: true, publishMode: 'immediate', rangeStart: date2, rangeEnd: date2,
        deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2,
        createdAt: created, statusUpdatedAt: created,
      );
  SlotModel slot2() => SlotModel(
        id: kSlot2, toId: kTo2, date: date2, workDetails: [wd2()],
        workDetailCounts: const {kWd2: SlotWorkTypeCount(confirmedCount: 0, pendingCount: 0)},
        status: SlotStatus.open, confirmedCount: 0, pendingCount: 0,
        applicationDeadline: deadline2, visibleFrom: created, createdAt: created,
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
      } else if (raw.contains('tos/$kTo2/slots')) {
        key = 'query tos/$kTo2/slots';
        queryChecks.add('$key date=${raw.contains('date')} limit501=${_hasInt32(bytes, 501)}');
        docs = [
          PigeonDocumentSnapshot(path: 'tos/$kTo2/slots/$kSlot2', data: Map<String?, Object?>.from(slot2().toMap()), metadata: meta),
        ];
      } else if (raw.contains('tos/$kTo/slots')) {
        key = 'query tos/$kTo/slots';
        queryChecks.add('$key date=${raw.contains('date')} limit501=${_hasInt32(bytes, 501)}');
        docs = [
          PigeonDocumentSnapshot(path: 'tos/$kTo/slots/$kSlotO', data: Map<String?, Object?>.from(otherSlot().toMap()), metadata: meta),
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
              {'scopeToken': 'owner:$kOwner', 'businessIds': [kBiz], 'used': 2, 'limit': 10, 'remaining': 8},
            ],
            'denied': const [],
            'failed': const [],
          }
        ]);
      }
      if (name == 'callableGetAdminTOs') {
        final item = Map<String, Object?>.from(_wire(master().toMap()) as Map)
          ..['dates'] = [otherKey, workKey]
          ..['id'] = kTo;
        return c.encodeMessage(<Object?>[
          <String, Object?>{'items': <Object?>[
            item,
            Map<String, Object?>.from(_wire(master2().toMap()) as Map)
              ..['dates'] = [key2]
              ..['id'] = kTo2,
          ]}
        ]);
      }
      // callableGetApplicationsByBiz(capacity) — 정상 empty(확인된 0) 즉시
      return c.encodeMessage(<Object?>[
        <String, Object?>{'applications': const <Object?>[], 'hasMore': false}
      ]);
    });
  }

  // 실행 전 고정 사전(관측 복사 아님): readiness 4 + quota 1 + 목록 1 → 공고 2개 각각 slots 선로딩 1 · A 다중슬롯 펼침 0 · A 날짜칩(+8) capacity 1.
  const expectedList = {
    'get businesses/$kBiz': 1,
    'get users/$kOwner': 1,
    'query businesses/$kBiz/workTypes': 1,
    'query businesses/$kBiz/contract_templates': 1,
    'functions callableGetPostingQuotaSummary@asia-northeast3': 1,
    'functions callableGetAdminTOs@asia-northeast3': 1,
    'query tos/$kTo/slots': 1,
    'query tos/$kTo2/slots': 1,
  };
  const expectedFinal = {...expectedList, 'functions callableGetApplicationsByBiz@asia-northeast3': 1};

  for (final c in const [
    (id: 'S023-N', w: 360.0, h: 780.0, s: 1.0),
  ]) {
    testWidgets('${c.id} 공고 정상 목록 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 첫 화면 · drag · A 펼침 · 날짜칩 → 상세', (t) async {
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
      out('   fixture: 다른날 O slot $kSlotO wd $kWdO date=${_kst(otherDate)} civil=$otherKey 마감=${_kst(otherDeadline)} counter 0/0'
          ' · 대상 T slot $kSlot wd $kWd date=${_kst(workDate)} civil=$workKey 마감=${_kst(wdDeadline)} counter confirmed0/pending0'
          ' · master range=${_kst(otherDate)}~${_kst(workDate)} totalSlots=2 dates=[$otherKey, $workKey] totalRequired=6 totalConfirmed=0 totalPending=0 master.wdId=$kWdMaster'
          ' · visibleFrom/createdAt/statusUpdatedAt=${_kst(created)} · deadlineType=HOURS_BEFORE(2h) · publishMode=immediate·isPublished=true');
      expect(otherDeadline.isAfter(now), isTrue, reason: '지원 마감이 미래(비만료 fixture)');
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
          'fixture': 'owner $kOwner·biz $kBiz approved/license/owner seal·workType 1·daily template 1 · A $kTo flex "$kTitle" 슬롯 $kSlotO ${_kst(otherDate)} · $kSlot ${_kst(workDate)} 상하차 10:00~13:00 필요3씩 counter 0/0 · B $kTo2 flex "$kTitle2" 슬롯 $kSlot2 ${_kst(date2)} 상하차 14:00~18:00 필요2 시급13,000 counter 0/0 · quota used2/10',
          'capacity': '즉시 {applications: [], hasMore: false}(확인된 0) · gate 없음',
          'gates': 'list=${listGates.map((g) => g.isCompleted).toList()} capacity=${capGates.map((g) => g.isCompleted).toList()}',
          'state': state, 'calls': calls.toString(), 'quotaFetchCount': PostingQuotaStore.fetchCount};
      }

      // ── ① 진입 → 정상 목록(공고 2) ──
      await t.tap(find.text('host'));
      await frames(30);
      expect(find.byType(JobsRootScreen), findsOneWidget);
      expect(ctl().items.length, 2, reason: '정상 공고 2');
      out('① calls=$calls · queryChecks=$queryChecks');
      expect(calls, expectedList, reason: '목록 정확 누적 사전');
      for (final q in queryChecks) {
        expect(q.contains('=false'), isFalse, reason: 'query 계약: $q');
      }
      final viewportR = t.getRect(listScrollable());
      bool inVp(Rect r) => r.top >= viewportR.top - 0.5 && r.bottom <= viewportR.bottom + 0.5;
      Finder cardOf(String title) => find.ancestor(of: find.text(title), matching: find.byType(TOGroupCard)).first;
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
      out('   viewport=$viewportR · A 카드 ${t.getRect(cardOf(kTitle))}');
      await vqCapture(t, key, '${c.id}_1_first', conditions: cond('정상 첫 화면 · 공고 2 · offset=${scrollOffset().toStringAsFixed(1)}'));

      // ── ② 실제 drag 로 두 번째 공고 B 전체 ──
      for (var k = 0; k < 40; k++) {
        final f = find.text(kTitle2);
        if (f.evaluate().isNotEmpty && inVp(t.getRect(cardOf(kTitle2)))) break;
        final pos = t.state<ScrollableState>(listScrollable()).position;
        if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
        await t.dragFrom(Offset(viewportR.left + 8, viewportR.center.dy), const Offset(0, -80));
        await frames(2);
      }
      await frames(4);
      expect(find.text(kTitle2), findsOneWidget, reason: 'B 공고');
      out('② B 카드 ${t.getRect(cardOf(kTitle2))} inVp=${inVp(t.getRect(cardOf(kTitle2)))} offset=${scrollOffset().toStringAsFixed(1)}');
      await vqCapture(t, key, '${c.id}_2_second', conditions: cond('drag 뒤 B 공고 · offset=${scrollOffset().toStringAsFixed(1)} · B ${t.getRect(cardOf(kTitle2))}'));

      // ── ③ A 실제 펼침(화살표 중심 탭) — 다중 슬롯 펼침 read 0 ──
      final cardA = cardOf(kTitle);
      final arrow = find.ancestor(of: find.descendant(of: cardA, matching: find.byIcon(Icons.keyboard_arrow_down)), matching: find.byType(InkWell)).first;
      await bring(arrow);
      out('   A 화살표 ${rr(arrow)}');
      final b3 = snapCalls();
      await t.tapAt(t.getRect(arrow).center);
      await frames(20);
      out('③ A 펼침 delta=${delta(b3)} offset=${scrollOffset().toStringAsFixed(1)}');
      expect(delta(b3), isEmpty, reason: '다중 슬롯 펼침 추가 read 0');
      await vqCapture(t, key, '${c.id}_3_expanded', conditions: cond('A 펼침 · 날짜칩 2 · offset=${scrollOffset().toStringAsFixed(1)}'));

      // ── ④ A 날짜칩(+8) 실제 탭 → capacity 정상 empty → 확인된 0 상세 ──
      final chipRow = find.descendant(of: cardOf(kTitle), matching: find.byWidgetPredicate((w) => w is SingleChildScrollView && w.scrollDirection == Axis.horizontal));
      final chip = find.ancestor(of: find.descendant(of: chipRow, matching: find.text(FormatHelper.formatDateShort(workDate))), matching: find.byType(GestureDetector)).first;
      await bring(chip);
      final b4 = snapCalls();
      await t.tapAt(t.getRect(chip).center);
      await frames(40);
      out('④ 칩 탭 delta=${delta(b4)}');
      expect(delta(b4), {'functions callableGetApplicationsByBiz@asia-northeast3': 1}, reason: '날짜칩 = capacity 1');
      expect((fnRequests.last['parameters'] as Map)['slotId'], kSlot);
      final row = find.descendant(of: cardOf(kTitle), matching: find.text('미충원 3'));
      expect(row, findsOneWidget, reason: '대상 날짜 업무 행 확인된 0');
      await bring(row);
      out('   업무 행 ${t.getRect(row)} offset=${scrollOffset().toStringAsFixed(1)}');
      await vqCapture(t, key, '${c.id}_4_date_detail', conditions: cond('A 날짜칩 ${FormatHelper.formatDateShort(workDate)} 탭 · capacity 정상 empty · 업무 행 ${t.getRect(row)} · offset=${scrollOffset().toStringAsFixed(1)}'));

      // ── 종료선 ──
      await frames(10);
      out('최종 calls=$calls · fnRequests=${fnRequests.map((r) => '${r['functionName']} ${r['parameters']}').toList()}');
      expect(calls, expectedFinal, reason: '최종 정확 누적 사전(writer·기타 read 0)');
      expect(PostingQuotaStore.fetchCount, 1);
      FlutterError.onError = prev;
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
      expect(deferred, isEmpty, reason: deferred.join(' | '));
    });
  }
}
