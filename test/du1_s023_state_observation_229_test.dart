// ignore_for_file: depend_on_referenced_packages
// [DU229 S023 관측] 공고 탭 미관측 8상태 × W360/B320 — production 편집 0. DU229_OBSERVE=1 일 때만 실행(기본 skip).
//   상태: 권한거부·UNKNOWN(일관된 SubAdmin 권한 대역) / 준비필요·빈root·필터0·탭0·목록오류·stale(BUSINESS_ADMIN 대역).
//   진입은 LOCAL host → Navigator.push(JobsRootScreen()) — 실제 공개 load/reload/filter/tab 경로만 쓴다.
//   쓰기·허용 밖 callable 은 차단·계수해 0 을 단언한다. 읽기 횟수는 사전 예측표와 비교해 기록한다(관측 셀).
//   H2: 머리 필터·+ InkWell, 탭 GestureDetector 의 실제 receiver rect·중심 hit. H3: stale 카드 근무 줄 RenderParagraph·한도 줄.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

const kBiz = 'biz-local-d229';
const kOwner = 'owner-local-d229';
const kSub = 'sub-local-d229';
const kTo = 'to-local-d229';
const kSlot = 'slot-local-d229';
const kWd = 'wd-local-d229';
const kTitle = '송파 물류센터 주말 오전 상하차·분류 보조 단기 인력 모집 안전화 지참 필수';
// H3 — 긴 근무 줄(업무명 + 남은 기간)이 maxLines 1 에서 잘리는지 관측한다.
const kWorkType = '상하차·분류·검수 보조 및 출고 정리 단기 야간';

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
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
}

/// SubAdmin 권한 대역 — checkCurrentBusiness·checkForBusiness·subAdminBusinessesFor 가 같은 판정을 말한다.
///   denied: 배정 kBiz 가 확인된 거부(허용 0·미확인 0) / unknown: 배정 kBiz 를 확인하지 못함(허용 0·미확인 1).
class _Sub extends UserProvider {
  _Sub(this.verdict);
  final PermissionCheck verdict;
  @override
  UserModel? get currentUser => UserModel(uid: kSub, username: 'sub', name: 'QA 서브', email: 's@test.local',
      role: UserRole.USER, subAdminBusinessIds: const [kBiz], createdAt: DateTime(2026, 1, 1));
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => true;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
  @override
  String? get effectiveBusinessId => kBiz;
  @override
  Map<String, String> get subAdminBusinessNames => const {kBiz: 'QA 물류센터'};
  @override
  bool can(bool Function(MemberPermissions p) check) => false;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => false;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => verdict;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => verdict;
  @override
  ({List<String> allowed, List<String> unresolved}) subAdminBusinessesFor(bool Function(MemberPermissions p) check) =>
      verdict == PermissionCheck.denied
          ? (allowed: const <String>[], unresolved: const <String>[])
          : (allowed: const <String>[], unresolved: const <String>[kBiz]);
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

String _kst(DateTime d) {
  final k = d.toUtc().add(const Duration(hours: 9));
  String p(int x) => x.toString().padLeft(2, '0');
  return '${k.year}-${p(k.month)}-${p(k.day)} ${p(k.hour)}:${p(k.minute)} KST';
}

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

int _lines(RenderParagraph p) {
  final len = p.text.toPlainText().length;
  final boxes = p.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len));
  return boxes.map((b) => b.top.round()).toSet().length;
}

void _out(String l) {
  // ignore: avoid_print
  print(l);
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

  // 실행 시계 기준 fixture — 근무일 = 오늘(KST)+7 의 KST 자정. 지원 마감 = 그날 08:00 KST(비만료).
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
        wdId: kWd, workType: kWorkType, workTypeId: 'wt-d229', startTime: '10:00', endTime: '13:00',
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

  var templatesEmpty = false;
  void stubFirestore() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = FirebaseFirestoreHostApi.codec;
    m.setMockMessageHandler('$base.documentReferenceGet', (msg) async {
      final args = codec.decodeMessage(msg) as List;
      final path = (args[1] as DocumentReferenceRequest).path;
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
        inc('get.blocked $path');
        return codec.encodeMessage(<Object?>['du229-blocked', 'get 차단: $path', null]);
      }
      inc('get $path');
      return codec.encodeMessage(<Object?>[PigeonDocumentSnapshot(path: path, data: data, metadata: meta)]);
    });
    m.setMockMessageHandler('$base.queryGet', (msg) async {
      final bytes = msg!.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes);
      final raw = String.fromCharCodes(bytes);
      final String key;
      final List<PigeonDocumentSnapshot> docs;
      if (raw.contains('businesses/$kBiz/workTypes')) {
        key = 'query businesses/$kBiz/workTypes';
        queryChecks.add('$key isActive=${raw.contains('isActive')} displayOrder=${raw.contains('displayOrder')} limit100=${_hasInt32(bytes, 100)}');
        docs = [
          PigeonDocumentSnapshot(path: 'businesses/$kBiz/workTypes/wt-d229', data: <String?, Object?>{
            'businessId': kBiz, 'name': kWorkType, 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
            'displayOrder': 0, 'isActive': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
          }, metadata: meta),
        ];
      } else if (raw.contains('businesses/$kBiz/contract_templates')) {
        key = 'query businesses/$kBiz/contract_templates';
        queryChecks.add('$key createdAt=${raw.contains('createdAt')} limit100=${_hasInt32(bytes, 100)} empty=$templatesEmpty');
        docs = templatesEmpty
            ? const []
            : [
                PigeonDocumentSnapshot(path: 'businesses/$kBiz/contract_templates/tpl-d229', data: <String?, Object?>{
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
        inc('query.blocked');
        _out('D229-BLOCKED-QUERY ${raw.replaceAll(RegExp(r'[^ -~]'), '.')}');
        return codec.encodeMessage(<Object?>['du229-blocked', 'query 차단', null]);
      }
      inc(key);
      return codec.encodeMessage(<Object?>[PigeonQuerySnapshot(documents: docs, documentChanges: const [], metadata: meta)]);
    });
    for (final op in const ['documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit',
      'transactionCreate', 'transactionStoreResult', 'transactionGet', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        inc('write.blocked $op');
        return codec.encodeMessage(<Object?>['du229-blocked', '$op 차단', null]);
      });
    }
  }

  // 목록 callable 응답 계획 — 호출마다 하나씩 쓴다: 'one'(카드1) / 'empty'(성공 0) / 'error'(일반 네트워크 실패).
  final listPlan = <String>[];
  final fnLog = <String>[];
  void stubFunctions() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(fnChannel, (msg) async {
      const c = StandardMessageCodec();
      final args = (c.decodeMessage(msg) as List).first as Map;
      final name = args['functionName'];
      final region = args['region'];
      fnLog.add('$name@$region ${args['parameters']}');
      const allowed = {'callableGetPostingQuotaSummary', 'callableGetAdminTOs'};
      if (region != 'asia-northeast3' || !allowed.contains(name)) {
        inc('functions.blocked $name@$region');
        return c.encodeMessage(<Object?>['not-found', 'du229-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      inc('functions $name');
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
      final plan = listPlan.isEmpty ? 'error' : listPlan.removeAt(0);
      if (plan == 'error') {
        return c.encodeMessage(<Object?>['unavailable', 'du229 local network failure',
          <String, Object?>{'code': 'unavailable', 'message': 'du229 local network failure'}]);
      }
      final items = plan == 'empty'
          ? const <Object?>[]
          : <Object?>[
              Map<String, Object?>.from(_wire(master().toMap()) as Map)
                ..['dates'] = [workKey]
                ..['id'] = kTo,
            ];
      return c.encodeMessage(<Object?>[
        <String, Object?>{'items': items}
      ]);
    });
  }

  // 사전 예측 읽기표(관측 전 고정, 비교·기록만).
  const ready = {
    'get businesses/$kBiz': 1, 'get users/$kOwner': 1,
    'query businesses/$kBiz/workTypes': 1, 'query businesses/$kBiz/contract_templates': 1,
    'functions callableGetPostingQuotaSummary': 1, 'functions callableGetAdminTOs': 1,
  };
  final predicted = <String, Map<String, int>>{
    'denied': const {},
    'unknown': const {},
    'setup': {...ready, 'get businesses/$kBiz': 2},
    'emptyRoot': ready,
    'filter0': {...ready, 'query tos/$kTo/slots': 1},
    'tab0': {...ready, 'query tos/$kTo/slots': 1},
    'listError': ready,
    'stale': {...ready, 'query tos/$kTo/slots': 1, 'functions callableGetAdminTOs': 2, 'functions callableGetPostingQuotaSummary': 2},
  };
  const expectText = {
    'denied': '접근 권한이 없습니다',
    'unknown': '권한을 확인하지 못했습니다',
    'setup': null,
    'emptyRoot': '등록된 공고가 없습니다',
    'filter0': '조건에 맞는 공고가 없습니다',
    'tab0': '마감된 공고가 없습니다',
    'listError': '공고 목록을 불러오지 못했습니다',
    'stale': '최신 정보를 불러오지 못했습니다. 다시 시도해 주세요.',
  };

  for (final c in const [
    (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
    (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
  ]) {
    for (final state in const ['denied', 'unknown', 'setup', 'emptyRoot', 'filter0', 'tab0', 'listError', 'stale']) {
      testWidgets('D229 ${c.id} $state', (t) async {
        await t.runAsync(vqLoadFonts);
        FirstPostingReadinessStore.reset();
        PostingQuotaStore.reset();
        PostingQuotaStore.fetchCount = 0;
        calls.clear();
        fnLog.clear();
        queryChecks.clear();
        listPlan
          ..clear()
          ..addAll(switch (state) {
            'setup' || 'emptyRoot' => const ['empty'],
            'filter0' || 'tab0' => const ['one'],
            'listError' => const ['error'],
            'stale' => const ['one', 'error'],
            _ => const <String>[],
          });
        templatesEmpty = state == 'setup';
        stubFirestore();
        stubFunctions();
        final overflows = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            overflows.add(m.split(String.fromCharCode(10)).first);
          } else {
            prev?.call(d);
          }
        };
        addTearDown(() => FlutterError.onError = prev);
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        var pumps = 0;
        Future<void> frames([int n = 8]) async {
          for (var i = 0; i < n; i++) {
            pumps++;
            await t.pump(const Duration(milliseconds: 50));
          }
        }

        final provider = switch (state) {
          'denied' => _Sub(PermissionCheck.denied),
          'unknown' => _Sub(PermissionCheck.unknown),
          _ => _Owner(),
        };
        final key = GlobalKey();
        await t.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => provider),
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

        List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map((v) => double.parse(v.toStringAsFixed(1))).toList();
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);
        // 빈 후보에 .first 를 쓰면 예외다 — 첫 원소를 직접 고른다(없으면 null).
        Finder? firstOf(Finder f) {
          final els = f.evaluate().toList();
          if (els.isEmpty) return null;
          final e = els.first;
          return find.byElementPredicate((x) => identical(x, e));
        }

        Map<String, Object?> recv(String name, Finder? f) {
          if (f == null) return {'name': name, 'present': false};
          final r = t.getRect(f);
          return {
            'name': name, 'present': true, 'rect': lt(r), 'w': double.parse(r.width.toStringAsFixed(1)),
            'h': double.parse(r.height.toStringAsFixed(1)), 'ge48': r.width >= 48 && r.height >= 48,
            'centerHit': hits(f, r.center), 'path': topHit(r.center),
            'inScreen': r.left >= -0.5 && r.top >= -0.5 && r.right <= screen.right + 0.5 && r.bottom <= screen.bottom + 0.5,
          };
        }

        List<String> visibleTexts() {
          final scr = find.byType(JobsRootScreen);
          if (scr.evaluate().isEmpty) return const ['(JobsRootScreen 없음)'];
          return t
              .widgetList<RichText>(find.descendant(of: scr, matching: find.byType(RichText)))
              .map((w) => w.text.toPlainText().replaceAll(String.fromCharCode(10), ' '))
              .where((s) => s.trim().isNotEmpty)
              .toList();
        }

        // ── 진입 ──
        await t.tap(find.text('host'));
        await frames(24);
        final hasList = find.byType(WorkforceListView).evaluate().isNotEmpty;
        WorkforceController? ctl() =>
            hasList ? Provider.of<WorkforceController>(t.element(find.byType(WorkforceListView)), listen: false) : null;
        final steps = <String>[];
        final cardBefore = find.byType(TOGroupCard).evaluate().length;
        if (state == 'filter0') {
          final cc = ctl();
          if (cc != null) {
            cc.setDateRangeFilter(DateTimeRange(start: workDate.add(const Duration(days: 60)), end: workDate.add(const Duration(days: 90))));
            steps.add('setDateRangeFilter(+60d..+90d)');
          } else {
            steps.add('filter0 미도달: WorkforceListView 없음');
          }
          await frames(10);
        } else if (state == 'tab0') {
          final closed = find.text('마감됨');
          if (closed.evaluate().isNotEmpty) {
            await t.tap(closed.first);
            steps.add('tap 마감됨');
          } else {
            steps.add('tab0 미도달: 마감됨 탭 없음');
          }
          await frames(10);
        } else if (state == 'stale') {
          final cc = ctl();
          if (cc != null) {
            unawaited(cc.reload(t.element(find.byType(WorkforceListView))));
            steps.add('controller.reload()');
          } else {
            steps.add('stale 미도달: WorkforceListView 없음');
          }
          await frames(24);
        }
        await frames(8);

        // ── 관측 ──
        final want = expectText[state];
        final reached = want == null
            ? find.byType(WorkforceListView).evaluate().isEmpty && find.byType(JobsRootScreen).evaluate().isNotEmpty
            : find.textContaining(want).evaluate().isNotEmpty;
        final h2 = <Map<String, Object?>>[
          recv('filter', firstOf(find.ancestor(of: find.byIcon(Icons.filter_list_rounded), matching: find.byType(InkWell)))),
          recv('create', firstOf(find.ancestor(of: find.byIcon(Icons.add_rounded), matching: find.byType(InkWell)))),
          recv('tabActive', firstOf(find.ancestor(
              of: find.byWidgetPredicate((w) => w is Text && (w.data ?? '').startsWith('진행중')),
              matching: find.byType(GestureDetector)))),
          recv('tabClosed', firstOf(find.ancestor(of: find.text('마감됨'), matching: find.byType(GestureDetector)))),
        ];
        final present = h2.where((x) => x['present'] == true).toList();
        final overlaps = <String>[];
        for (var i = 0; i < present.length; i++) {
          for (var j = i + 1; j < present.length; j++) {
            final a = present[i]['rect']! as List<double>;
            final b = present[j]['rect']! as List<double>;
            if (Rect.fromLTRB(a[0], a[1], a[2], a[3]).overlaps(Rect.fromLTRB(b[0], b[1], b[2], b[3]))) {
              overlaps.add('${present[i]['name']}×${present[j]['name']}');
            }
          }
        }
        Map<String, Object?> para(String label, Finder f) {
          if (f.evaluate().isEmpty) return {'name': label, 'present': false};
          final rp = t.renderObject<RenderParagraph>(f.first);
          final r = t.getRect(f.first);
          return {
            'name': label, 'present': true, 'text': rp.text.toPlainText(), 'maxLines': rp.maxLines,
            'didExceedMaxLines': rp.didExceedMaxLines, 'lines': _lines(rp), 'rect': lt(r),
            'inScreen': r.top >= -0.5 && r.bottom <= screen.bottom + 0.5,
          };
        }

        Finder richContaining(String s) => find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains(s));
        final quota = para('quota', richContaining('진행 중 공고'));
        Map<String, Object?> work = para('workLine', find.descendant(of: find.byType(TOGroupCard), matching: richContaining(kWorkType)));
        final shot = '${c.id}_$state';
        await vqCapture(t, key, 'D229-$shot', conditions: {
          'state': state, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
          'theme': 'RoleTheme.businessAdminTheme', 'locale': Localizations.localeOf(t.element(find.byType(Scaffold).first)).toString(),
          'clock': '미주입(now=${_kst(now)})', 'fixture': 'workDate=${_kst(workDate)} deadline=${_kst(wdDeadline)}',
          'steps': steps.join(' / '),
        });
        var h3Extra = false;
        if (state == 'stale' && work['present'] == true && work['inScreen'] != true) {
          final sc = find.byWidgetPredicate((w) => w is ListView && w.scrollDirection == Axis.vertical && w.controller != null);
          if (sc.evaluate().isNotEmpty) {
            final vp = t.getRect(find.descendant(of: sc, matching: find.byType(Scrollable)).first);
            for (var k = 0; k < 2; k++) {
              await t.dragFrom(Offset(vp.left + 8, vp.center.dy), const Offset(0, -160));
              await frames(4);
              work = para('workLine', find.descendant(of: find.byType(TOGroupCard), matching: richContaining(kWorkType)));
              if (work['inScreen'] == true) break;
            }
            await vqCapture(t, key, 'D229-${shot}_h3', conditions: {'state': 'stale-h3', 'textScaler': c.s});
            h3Extra = true;
          }
        }
        final pred = predicted[state]!;
        final reads = Map<String, int>.from(calls)..removeWhere((k, _) => k.startsWith('write.') || k.startsWith('functions.blocked'));
        final readDiff = <String>[
          for (final k in {...pred.keys, ...reads.keys})
            if ((pred[k] ?? 0) != (reads[k] ?? 0)) '$k 예측${pred[k] ?? 0}/실제${reads[k] ?? 0}',
        ];
        final out = {
          'cond': c.id, 'state': state, 'reached': reached, 'expectText': want, 'steps': steps,
          'cardsBefore': cardBefore, 'cardsAfter': find.byType(TOGroupCard).evaluate().length,
          'readiness': '${FirstPostingReadinessStore.current.value.status} allReady=${FirstPostingReadinessStore.current.value.value?.allReady}',
          'quotaStatus': '${PostingQuotaStore.current.value.status}', 'quotaFetch': PostingQuotaStore.fetchCount,
          'calls': calls, 'readDiff': readDiff, 'fn': fnLog, 'queryChecks': queryChecks,
          'h2': h2, 'h2Overlaps': overlaps, 'quotaLine': quota, 'workLine': work, 'h3ExtraPng': h3Extra,
          'overflows': overflows, 'pumps': pumps, 'texts': visibleTexts(),
          'kst': _kst(DateTime.now()),
        };
        _out('D229 ${jsonEncode(out)}');
        // ── 안전 단언: 쓰기 0 · 허용 밖 callable 0 · 예외 0 ──
        expect(calls.keys.where((k) => k.startsWith('write.')).toList(), isEmpty, reason: '쓰기 시도 0');
        expect(calls.keys.where((k) => k.startsWith('functions.blocked')).toList(), isEmpty, reason: '허용 밖 callable 0');
        expect(pumps, lessThanOrEqualTo(600));
        FlutterError.onError = prev;
        expect(t.takeException(), isNull);
      }, skip: Platform.environment['DU229_OBSERVE'] != '1');
    }
  }
}
