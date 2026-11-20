// ignore_for_file: depend_on_referenced_packages
// [DU232 S023 F4 identity baseline/after] 큰 글자 배치 전환(요약이 목록 맨 앞에 들어오고 빠짐)에서 공고 카드 State 가
//   같은 공고에 남는가. DU232_RUN=1 이고 DU232_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip). production 편집 0.
//   phase 하나 = testWidgets 하나, 흐름 둘(정상 목록 360×780 배율 1.3→1.6→1.3 / stale 320×640 배율 2→1→2).
//   각 흐름은 한 번만 마운트하고 왕복 중 같은 root/list/controller 트리를 유지한다(배율은 기기 글자 설정으로 바꾼다).
//   reader 는 전체 경로·query 필터/정렬/limit·callable payload 를 실행 전 고정한 정확값 multiset 과 대조한다.
//   baseline 의 카드 State 교체·유실은 사전 지정 결함값으로 기록만 하고, 그 밖 실패와 after 성공조건 실패는 그 자리에서 멈춘다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/admin/cards/admin_to_group_card.dart';
import 'package:ALfit/widgets/admin/posting_quota_summary_bar.dart';

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

const kBiz = 'biz-local-d232';
const kOwner = 'owner-local-d232';
const kToA = 'to-local-d232-a';
const kToB = 'to-local-d232-b';
const kWd = 'wd-local-d232';
const kTitleA = 'QA 공고 A 주말 오전 상하차 보조';
const kTitleB = 'QA 공고 B 평일 오후 검수 보조';
const kWorkType = '상하차 보조';

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

String _key(DateTime d) {
  final k = d.toUtc().add(const Duration(hours: 9));
  return '${k.year}-${k.month.toString().padLeft(2, '0')}-${k.day.toString().padLeft(2, '0')}';
}

/// reader 인자 정규형 — 맵은 키 정렬, FieldPath 는 FP(구성요소), 문자열은 JSON 따옴표.
String _canon(Object? v) {
  if (v == null) return 'null';
  if (v is FieldPath) return 'FP(${v.components.join('.')})';
  if (v is String) return jsonEncode(v);
  if (v is num || v is bool) return '$v';
  if (v is List) return '[${v.map(_canon).join(',')}]';
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return '{${keys.map((k) => '$k:${_canon(v.entries.firstWhere((e) => '${e.key}' == k).value)}').join(',')}}';
  }
  return '${v.runtimeType}($v)';
}

List<Object?> _orEmpty(List<Object?>? l) => l ?? const [];

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

void main() {
  final phase = Platform.environment['DU232_PHASE'] ?? '';
  final run = Platform.environment['DU232_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  final events = <String>[];
  final blocked = <String>[];
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  final meta = PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false);

  // 실행 시계 기준 fixture(시계 미주입) — 공고 A = KST 오늘+7·+8·+9 (사흘), 공고 B = 오늘+10 (하루). 마감 = 각 날 08:00 KST.
  final now = DateTime.now();
  final kstNow = now.toUtc().add(const Duration(hours: 9));
  DateTime day(int plus) => DateTime.utc(kstNow.year, kstNow.month, kstNow.day)
      .add(Duration(days: plus))
      .subtract(const Duration(hours: 9))
      .toLocal();
  final created = now.subtract(const Duration(days: 1));
  List<DateTime> datesOf(String to) => to == kToA ? [day(7), day(8), day(9)] : [day(10)];
  WorkDetailData wd(DateTime d) => WorkDetailData(
        wdId: kWd, workType: kWorkType, workTypeId: 'wt-d232', startTime: '10:00', endTime: '13:00',
        requiredCount: 2, wage: 12000, wageType: 'hourly', applicationDeadline: d.add(const Duration(hours: 8)),
      );
  TOModel masterOf(String to) {
    final ds = datesOf(to);
    return TOModel(
      id: to, businessId: kBiz, businessName: 'QA 물류센터', type: TOType.flex, title: to == kToA ? kTitleA : kTitleB,
      creatorUID: kOwner, status: TOStatus.active, workDetails: [wd(ds.first)], totalSlots: ds.length,
      slotDateKeys: ds.map(_key).toList(), totalRequired: 2 * ds.length, totalConfirmed: 0, totalPending: 0,
      isPublished: true, publishMode: 'immediate', rangeStart: ds.first, rangeEnd: ds.last,
      deadlineType: 'HOURS_BEFORE', hoursBeforeStart: 2, createdAt: created, statusUpdatedAt: created,
    );
  }

  SlotModel slotOf(String to, int i, DateTime d) => SlotModel(
        id: '$to-slot-$i', toId: to, date: d, workDetails: [wd(d)],
        workDetailCounts: const {kWd: SlotWorkTypeCount(confirmedCount: 0, pendingCount: 0)},
        status: SlotStatus.open, confirmedCount: 0, pendingCount: 0,
        applicationDeadline: d.add(const Duration(hours: 8)), visibleFrom: created, createdAt: created,
      );

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
        blocked.add('get $path');
        return codec.encodeMessage(<Object?>['du232-blocked', 'get 차단: $path', null]);
      }
      events.add('get $path');
      return codec.encodeMessage(<Object?>[PigeonDocumentSnapshot(path: path, data: data, metadata: meta)]);
    });
    m.setMockMessageHandler('$base.queryGet', (msg) async {
      final args = codec.decodeMessage(msg) as List;
      final path = args[1] as String;
      final p = args[3] as PigeonQueryParameters;
      final filters = (p.filters == null || p.filters!.isEmpty) ? null : p.filters;
      final sig = 'query $path cg=${args[2]} where=${_canon(_orEmpty(p.where))} orderBy=${_canon(_orEmpty(p.orderBy))} '
          'limit=${p.limit} limitToLast=${p.limitToLast} cursors=${_canon([_orEmpty(p.startAt), _orEmpty(p.startAfter), _orEmpty(p.endAt), _orEmpty(p.endBefore)])} '
          'filters=${_canon(filters)}';
      final List<PigeonDocumentSnapshot> docs;
      if (path == 'businesses/$kBiz/workTypes') {
        docs = [
          PigeonDocumentSnapshot(path: 'businesses/$kBiz/workTypes/wt-d232', data: <String?, Object?>{
            'businessId': kBiz, 'name': kWorkType, 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
            'displayOrder': 0, 'isActive': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
          }, metadata: meta),
        ];
      } else if (path == 'businesses/$kBiz/contract_templates') {
        docs = [
          PigeonDocumentSnapshot(path: 'businesses/$kBiz/contract_templates/tpl-d232', data: <String?, Object?>{
            'businessId': kBiz, 'name': '단기 근무 기본', 'templateType': 'daily', 'articles': const [],
            'createdAt': Timestamp.fromDate(DateTime(2026, 10, 2)),
          }, metadata: meta),
        ];
      } else if (path == 'tos/$kToA/slots' || path == 'tos/$kToB/slots') {
        final to = path.split('/')[1];
        final ds = datesOf(to);
        docs = [
          for (var i = 0; i < ds.length; i++)
            PigeonDocumentSnapshot(
                path: '$path/$to-slot-$i', data: Map<String?, Object?>.from(slotOf(to, i, ds[i]).toMap()), metadata: meta),
        ];
      } else {
        blocked.add(sig);
        return codec.encodeMessage(<Object?>['du232-blocked', 'query 차단', null]);
      }
      events.add(sig);
      return codec.encodeMessage(<Object?>[PigeonQuerySnapshot(documents: docs, documentChanges: const [], metadata: meta)]);
    });
    for (final op in const ['documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit',
      'transactionCreate', 'transactionStoreResult', 'transactionGet', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        blocked.add('write $op');
        return codec.encodeMessage(<Object?>['du232-blocked', '$op 차단', null]);
      });
    }
  }

  // 목록 callable 응답 계획 — 'two'(공고 A·B) / 'error'(일반 네트워크 실패). 비면 'error'.
  final listPlan = <String>[];
  void stubFunctions() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(fnChannel, (msg) async {
      const c = StandardMessageCodec();
      final args = (c.decodeMessage(msg) as List).first as Map;
      final name = args['functionName'];
      final region = args['region'];
      final sig = 'fn $name@$region ${_canon(args['parameters'])}';
      const allowed = {'callableGetPostingQuotaSummary', 'callableGetAdminTOs'};
      if (region != 'asia-northeast3' || !allowed.contains(name)) {
        blocked.add(sig);
        return c.encodeMessage(<Object?>['not-found', 'du232-blocked', <String, Object?>{'code': 'not-found'}]);
      }
      events.add(sig);
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
      final plan = listPlan.isEmpty ? 'error' : listPlan.removeAt(0);
      if (plan == 'error') {
        return c.encodeMessage(<Object?>['unavailable', 'du232 local network failure',
          <String, Object?>{'code': 'unavailable', 'message': 'du232 local network failure'}]);
      }
      return c.encodeMessage(<Object?>[
        <String, Object?>{
          'items': [
            for (final to in const [kToA, kToB])
              Map<String, Object?>.from(_wire(masterOf(to).toMap()) as Map)
                ..['id'] = to
                ..['dates'] = datesOf(to).map(_key).toList(),
          ],
        }
      ]);
    });
  }

  // ── 실행 전 고정한 정확 reader(정규형 multiset). 배율 왕복·펼침은 추가 0 이어야 한다. ──
  const none = 'limitToLast=null cursors=[[],[],[],[]] filters=null';
  const readyEvents = [
    'get businesses/$kBiz',
    'get users/$kOwner',
    'query businesses/$kBiz/workTypes cg=false where=[[FP(isActive),"==",true]] orderBy=[[FP(displayOrder),false]] limit=100 $none',
    'query businesses/$kBiz/contract_templates cg=false where=[] orderBy=[[FP(createdAt),true]] limit=100 $none',
    'fn callableGetPostingQuotaSummary@asia-northeast3 {businessIds:["$kBiz"]}',
    'fn callableGetAdminTOs@asia-northeast3 {activeOnly:false,businessIds:["$kBiz"],closedOnly:false}',
    'query tos/$kToA/slots cg=false where=[] orderBy=[[FP(date),false]] limit=501 $none',
    'query tos/$kToB/slots cg=false where=[] orderBy=[[FP(date),false]] limit=501 $none',
  ];
  final predicted = <String, List<String>>{
    'normal': [...readyEvents]..sort(),
    'stale': [
      ...readyEvents,
      'fn callableGetPostingQuotaSummary@asia-northeast3 {businessIds:["$kBiz"]}',
      'fn callableGetAdminTOs@asia-northeast3 {activeOnly:false,businessIds:["$kBiz"],closedOnly:false}',
    ]..sort(),
  };

  testWidgets('D232 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);

    var nPump = 0, nMount = 0, nTap = 0, nDrag = 0, nPng = 0;
    const maxFrames = 800, maxTap = 8, maxDrag = 8, maxPng = 6;
    final tapLog = <String>[];
    var cur = '(시작)';
    Map<String, int> counts() => {'pump': nPump, 'pumpWidget': nMount, 'tap': nTap, 'drag': nDrag, 'png': nPng};
    Never stop(String why) {
      _out('D232-STOP ${jsonEncode({'phase': phase, 'at': cur, 'why': why, 'errors': errors, 'counts': counts(), 'events': events, 'blocked': blocked})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    void budget() => need(nPump + nMount <= maxFrames && nTap <= maxTap && nDrag <= maxDrag && nPng <= maxPng, '사용량 한도 초과 ${counts()}');
    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        budget();
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    void noErrors(String at) {
      final ex = t.takeException();
      need(errors.isEmpty && ex == null, '$at 예외/overflow: ${errors.take(3).toList()} / $ex');
    }

    void safe(String at) {
      need(blocked.isEmpty, '$at 쓰기·허용 밖 호출·차단 읽기: $blocked');
      noErrors(at);
    }

    Finder rich(bool Function(String p) f, {Finder? within}) {
      final m = find.byWidgetPredicate((w) => w is RichText && f(TextLayout.plain(w.text.toPlainText())), skipOffstage: false);
      return within == null ? m : find.descendant(of: within, matching: m, skipOffstage: false);
    }

    Finder cardOf(String id) => find.byWidgetPredicate((w) => w is TOGroupCard && w.groupItem.id == id, skipOffstage: false);
    final key = GlobalKey();

    try {
      for (final flow in const [
        (id: 'normal', w: 360.0, h: 780.0, scales: [1.3, 1.6, 1.3], summaryAt: [false, true, false]),
        (id: 'stale', w: 320.0, h: 640.0, scales: [2.0, 1.0, 2.0], summaryAt: [true, false, true]),
      ]) {
        cur = '${flow.id} 마운트';
        if (nMount > 0) {
          nMount++;
          budget();
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          noErrors('unmount');
        }
        FirstPostingReadinessStore.reset();
        PostingQuotaStore.reset();
        PostingQuotaStore.fetchCount = 0;
        events.clear();
        blocked.clear();
        listPlan
          ..clear()
          ..addAll(flow.id == 'stale' ? const ['two', 'error'] : const ['two']);
        stubFirestore();
        stubFunctions();
        t.view.physicalSize = Size(flow.w, flow.h);
        t.view.devicePixelRatio = 1.0;
        t.platformDispatcher.textScaleFactorTestValue = flow.scales[0];
        final screen = Rect.fromLTWH(0, 0, flow.w, flow.h);
        nMount++;
        budget();
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
              // 앱(main.dart)과 같은 delegate·supportedLocales — locale 은 기기(ko_KR), 글자 배율도 기기 설정에서 온다.
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
              home: const JobsRootScreen(),
            ),
          ),
        ));
        await frames(24);
        safe('진입');
        need(find.byType(WorkforceListView).evaluate().length == 1, '목록 없음');
        WorkforceController ctl() => Provider.of<WorkforceController>(t.element(find.byType(WorkforceListView)), listen: false);
        final steps = <String>[];
        if (flow.id == 'stale') {
          // 두 번째 목록 조회가 실패해 마지막 성공 목록 위에 경고가 남는다(231 과 같은 공개 reload 경로).
          unawaited(ctl().reload(t.element(find.byType(WorkforceListView))));
          steps.add('controller.reload() → 실패');
          await frames(24);
          safe('stale 만들기');
        } else {
          // 공고 A(사흘)를 공개 tap 으로 펼친다 — 슬롯은 이미 읽혀 있어 추가 reader 가 없다(목록 State _expandedGroups).
          final title = rich((p) => p == kTitleA, within: cardOf(kToA));
          need(title.evaluate().length == 1, '공고 A 제목 누락');
          nTap++;
          budget();
          tapLog.add('${flow.id} 공고 A 제목(펼침)');
          await t.tapAt(t.getRect(title).center);
          await frames(12);
          steps.add('tap 공고 A 펼침');
          safe('펼침');
        }

        // 고정 identity — 이 흐름 동안 바뀌면 안 된다.
        final rootState = t.state(find.byType(JobsRootScreen));
        final listState = t.state(find.byType(WorkforceListView));
        final controller0 = ctl();
        ScrollController scrollCtl() => t
            .widget<ListView>(find.descendant(
                of: find.byType(WorkforceListView),
                matching: find.byWidgetPredicate((w) => w is ListView && w.controller != null && w.scrollDirection == Axis.vertical)).first)
            .controller!;
        final scroll0 = scrollCtl();
        final seen = <String, List<State>>{}; // 공고 ID → 시점별 State(마운트된 시점만)
        final allStates = <State, String>{}; // 한 번이라도 본 State → 그때의 공고 ID

        for (var k = 0; k < 3; k++) {
          final s = flow.scales[k];
          cur = '${flow.id} p${k + 1} 배율$s';
          if (k > 0) {
            t.platformDispatcher.textScaleFactorTestValue = s;
            steps.add('배율 $s');
            await frames(10);
            safe('배율 전환');
          }
          // ── 조건 ──
          final sctx = t.element(find.byType(Scaffold).first);
          final mq = MediaQuery.of(sctx);
          final locale = Localizations.localeOf(sctx).toString();
          final env = {
            'locale': locale, 'size': '${mq.size.width.toInt()}x${mq.size.height.toInt()}', 'dpr': mq.devicePixelRatio,
            'scaler': mq.textScaler.scale(14) / 14, 'padding': '${mq.padding}', 'viewInsets': '${mq.viewInsets}',
            'themeFont': Theme.of(sctx).textTheme.bodyMedium?.fontFamily,
          };
          need(locale == 'ko_KR', 'locale $locale');
          need(mq.size == Size(flow.w, flow.h) && mq.devicePixelRatio == 1.0 && (mq.textScaler.scale(14) / 14 - s).abs() < 1e-9 &&
              mq.padding == EdgeInsets.zero && mq.viewInsets == EdgeInsets.zero, '조건 불일치 $env');

          // ── 트리 identity ──
          need(identical(t.state(find.byType(JobsRootScreen)), rootState), 'root State 교체');
          need(identical(t.state(find.byType(WorkforceListView)), listState), 'list State 교체');
          need(identical(ctl(), controller0), 'controller 교체');
          final sc = scrollCtl();
          need(identical(sc, scroll0) && sc.positions.length == 1, 'ScrollController 교체/중복 부착 (${sc.positions.length})');

          // ── 요약 자리(배치 전환) ──
          final summaryInList = find
              .descendant(of: find.byType(WorkforceListView), matching: find.byType(PostingQuotaSummaryBar), skipOffstage: false)
              .evaluate()
              .isNotEmpty;
          need(summaryInList == flow.summaryAt[k], '요약 자리 예측과 다름(목록 안=$summaryInList)');
          final lead = summaryInList ? 1 : 0;

          // ── 카드 State·sliver index ──
          final states = <String, State>{};
          final index = <String, int>{};
          for (final e in find.byType(TOGroupCard, skipOffstage: false).evaluate()) {
            final id = (e.widget as TOGroupCard).groupItem.id;
            need(!states.containsKey(id), '같은 공고 카드 2개: $id');
            states[id] = (e as StatefulElement).state;
            RenderObject? r = e.renderObject;
            while (r != null && r.parentData is! SliverMultiBoxAdaptorParentData) {
              r = r.parent;
            }
            need(r != null, 'sliver 자식 없음: $id');
            index[id] = (r!.parentData! as SliverMultiBoxAdaptorParentData).index!;
          }
          need(states.containsKey(kToA), '추적 공고 A 가 마운트되지 않음');
          if (flow.id == 'normal' && k == 0) need(states.containsKey(kToB), '공고 B 가 첫 시점에 마운트되지 않음');
          // ID → index 연결: 공고 A·B 순서 + 요약 lead (양 phase 공통 계약).
          for (final e in index.entries) {
            need(e.value == lead + (e.key == kToA ? 0 : 1), 'ID→index 불일치 ${e.key}=${e.value} lead=$lead');
          }

          // ── State 연속성(after 성공조건 / baseline 결함 기록) ──
          final keptSame = <String, bool>{};
          final tookOther = <String, String>{};
          for (final e in states.entries) {
            final prev = seen[e.key];
            if (prev != null && prev.isNotEmpty) keptSame[e.key] = identical(prev.last, e.value);
            final owner = allStates[e.value];
            if (owner != null && owner != e.key) tookOther[e.key] = owner;
          }
          final continuityOk = keptSame.values.every((x) => x) && tookOther.isEmpty;
          if (after) need(continuityOk, '카드 State 연속성 실패 kept=$keptSame took=$tookOther');
          for (final e in states.entries) {
            seen.putIfAbsent(e.key, () => []).add(e.value);
            allStates[e.value] = e.key;
          }

          // ── 공개 상태 유지: 펼침(정상) / 경고(stale) ──
          bool expanded(String id) => rich((p) => p == '날짜별 현황', within: cardOf(id)).evaluate().isNotEmpty;
          final expandedA = expanded(kToA);
          final expandedB = states.containsKey(kToB) ? expanded(kToB) : null;
          if (flow.id == 'normal') need(expandedA && expandedB != true, '펼침이 공고 A 에 남지 않음 A=$expandedA B=$expandedB');
          final staleF = rich((p) => p == '최신 정보를 불러오지 못했습니다. 다시 시도해 주세요.');
          final staleVisible = staleF.evaluate().isNotEmpty && screen.overlaps(t.getRect(staleF.first));
          if (flow.id == 'stale') need(staleVisible, '오래된 데이터 경고가 사라짐');

          // ── reader: 정확값 multiset(추가 0) ──
          final got = [...events]..sort();
          final want = predicted[flow.id]!;
          need(jsonEncode(got) == jsonEncode(want), 'reader 정확값 불일치 got=$got');
          safe('캡처 전');

          final shotId = 'D232-$phase-${flow.id}_p${k + 1}';
          nPng++;
          budget();
          await vqCapture(t, key, shotId, conditions: {
            'phase': phase, 'flow': flow.id, 'point': k + 1, 'textScaleFactor(기기)': s, 'viewport': '${flow.w.toInt()}x${flow.h.toInt()}',
            'dpr': 1.0, 'locale': locale, 'summaryInList': summaryInList, 'clock': '미주입(now=${_kst(now)})',
            'fixture': 'A=${datesOf(kToA).map(_key).join(',')} B=${datesOf(kToB).map(_key).join(',')}', 'steps': steps.join(' / '),
          });
          _out('D232 ${jsonEncode({
                'phase': phase, 'flow': flow.id, 'point': k + 1, 'scale': s, 'env': env, 'summaryInList': summaryInList, 'lead': lead,
                'root': identityHashCode(rootState), 'list': identityHashCode(listState), 'controller': identityHashCode(controller0),
                'scrollController': identityHashCode(scroll0), 'scrollPositions': sc.positions.length, 'scrollPixels': sc.offset,
                'cardStates': {for (final e in states.entries) e.key: identityHashCode(e.value)}, 'sliverIndex': index,
                'keptSame': keptSame, 'tookOther': tookOther, 'continuityOk': continuityOk,
                'expandedA': expandedA, 'expandedB': expandedB, 'staleVisible': staleVisible,
                'events': got, 'steps': steps, 'counts': counts(), 'taps': tapLog, 'kst': _kst(DateTime.now()),
              })}');
        }
      }
      nMount++;
      budget();
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      noErrors('끝');
      _out('D232-END ${jsonEncode({'phase': phase, 'counts': counts(), 'taps': tapLog})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
