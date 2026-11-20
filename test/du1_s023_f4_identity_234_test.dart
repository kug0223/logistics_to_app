// ignore_for_file: depend_on_referenced_packages
// [DU234 S023 F4 identity baseline/after] 큰 글자 배치 전환(요약이 목록 맨 앞에 들어오고 빠짐)에서 공고 카드 State 가
//   같은 공고에 남는가. DU234_RUN=1 이고 DU234_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip). production 편집 0.
//   233 시험에서 바꾼 부분(감사233·요청234 허용 범위 — 새 셀 식별자 외 이 둘뿐):
//   ⑦ 앱 오류는 debugPrint 호출 메시지 원문 전체를 저장하고, 각 메시지의 첫 줄(첫 줄바꿈 앞) 목록을 건수·순서·중복까지
//      정확 비교한다(trim·부분포함·정렬·중복제거 없음, 스택 줄 수·경로는 고정하지 않고 원문을 STOP/원출력에 남긴다).
//   ⑧ 같은 비교를 매 캡처 전뿐 아니라 흐름 종료(unmount 직후·appErrors.clear 직전)와 최종 END 전에도 한다.
//   (승계) 232 시험에서 바꾼 하네스 부분(감사232·요청233 허용 범위):
//   ① queryGet 인자를 플러그인 코덱(FieldPath tag 192 를 읽지 못함) 대신 시험 안의 작은 해독기(_QueryWireCodec)로 읽는다.
//   ② 첫 마운트 전에 실제 플러그인 경로(cloud_firestore Query.get)로 FieldPath 가 든 where/orderBy query 2개를 보내
//      새 대역이 해독·정확 대조하는지 자가확인한다.
//   ③ 대역 예외는 원바이트(base64)·예외·스택으로 남기고 공통 guard 가 본다.
//   ④ 앱이 catch 해 debugPrint 로만 남기는 reader 오류(❌·⚠️)도 흐름별 허용 목록과 정확 대조한다.
//   ⑤ baseline 은 'index 를 따라 State 가 재사용됨'(사전 예상 결함)만 허용하고, 그 밖의 State 변화는 즉시 중단한다.
//      after 는 '공고 ID 를 따라 State 유지'를 단언한다. 계산한 identity 는 STOP 에도 남긴다.
//   ⑥ 카드별 연속 마운트·정상 lazy disposal 직접 근거(직전 State.mounted, sliver 실제 생성 범위)를 기록한다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' as cf;
import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/foundation.dart';
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

/// queryGet 메시지 해독기 — 설치된 6.6.12 의 쓰기 형식에 맞춘다.
///   pigeon 사용자 타입 130·131·135·136·137 은 공개 decode(), FieldPath(192)는 크기+구성요소 문자열, documentId(191)는 표식.
///   그 밖의 tag 는 표준 코덱으로 넘긴다(모르는 tag 면 예외 → 대역 오류로 기록·중단).
class _QueryWireCodec extends StandardMessageCodec {
  const _QueryWireCodec();
  @override
  Object? readValueOfType(int type, ReadBuffer buffer) {
    switch (type) {
      case 130:
        return DocumentReferenceRequest.decode(readValue(buffer)!);
      case 131:
        return FirestorePigeonFirebaseApp.decode(readValue(buffer)!);
      case 135:
        return PigeonFirebaseSettings.decode(readValue(buffer)!);
      case 136:
        return PigeonGetOptions.decode(readValue(buffer)!);
      case 137:
        return PigeonQueryParameters.decode(readValue(buffer)!);
      case 191:
        return const _DocIdPath();
      case 192:
        final n = readSize(buffer);
        return FieldPath([for (var i = 0; i < n; i++) readValue(buffer)! as String]);
      default:
        return super.readValueOfType(type, buffer);
    }
  }
}

class _DocIdPath {
  const _DocIdPath();
}

const kBiz = 'biz-local-d234';
const kOwner = 'owner-local-d234';
const kToA = 'to-local-d234-a';
const kToB = 'to-local-d234-b';
const kWd = 'wd-local-d234';
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
  if (v is _DocIdPath) return 'FP(__documentId__)';
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

String _b64(ByteData? msg) =>
    msg == null ? 'null' : base64Encode(msg.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes));

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

void main() {
  final phase = Platform.environment['DU234_PHASE'] ?? '';
  final run = Platform.environment['DU234_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  final events = <String>[];
  final blocked = <String>[];
  final harness = <Map<String, Object?>>[]; // 대역 자체 예외(원바이트·예외·스택)
  final appErrors = <String>[]; // 앱이 catch 해 debugPrint 로 남긴 ❌·⚠️ 줄
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
        wdId: kWd, workType: kWorkType, workTypeId: 'wt-d234', startTime: '10:00', endTime: '13:00',
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
      try {
        // get 은 FieldPath 가 없어 플러그인 코덱으로 해독된다(232 원출력에서 get event 정상 기록).
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
          return codec.encodeMessage(<Object?>['du234-blocked', 'get 차단: $path', null]);
        }
        events.add('get $path');
        return codec.encodeMessage(<Object?>[PigeonDocumentSnapshot(path: path, data: data, metadata: meta)]);
      } catch (e, st) {
        harness.add({'handler': 'documentReferenceGet', 'bytes': _b64(msg), 'error': '$e', 'stack': '$st'.split(nl).take(8).toList()});
        return codec.encodeMessage(<Object?>['du234-harness', '대역 오류', null]);
      }
    });
    m.setMockMessageHandler('$base.queryGet', (msg) async {
      try {
        final args = const _QueryWireCodec().decodeMessage(msg) as List;
        final app = args[0] as FirestorePigeonFirebaseApp;
        final path = args[1] as String;
        final p = args[3] as PigeonQueryParameters;
        final o = args[4] as PigeonGetOptions;
        final filters = (p.filters == null || p.filters!.isEmpty) ? null : p.filters;
        final sig = 'query $path cg=${args[2]} where=${_canon(_orEmpty(p.where))} orderBy=${_canon(_orEmpty(p.orderBy))} '
            'limit=${p.limit} limitToLast=${p.limitToLast} '
            'cursors=${_canon([_orEmpty(p.startAt), _orEmpty(p.startAfter), _orEmpty(p.endAt), _orEmpty(p.endBefore)])} '
            'filters=${_canon(filters)} app=${app.appName} opts=${o.source.name}/${o.serverTimestampBehavior.name}';
        final List<PigeonDocumentSnapshot> docs;
        if (path == 'businesses/$kBiz/workTypes') {
          docs = [
            PigeonDocumentSnapshot(path: 'businesses/$kBiz/workTypes/wt-d234', data: <String?, Object?>{
              'businessId': kBiz, 'name': kWorkType, 'icon': 'box', 'color': '#3859E8', 'backgroundColor': '#EEF2FF',
              'displayOrder': 0, 'isActive': true, 'createdAt': Timestamp.fromDate(DateTime(2026, 10, 1)),
            }, metadata: meta),
          ];
        } else if (path == 'businesses/$kBiz/contract_templates') {
          docs = [
            PigeonDocumentSnapshot(path: 'businesses/$kBiz/contract_templates/tpl-d234', data: <String?, Object?>{
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
          return codec.encodeMessage(<Object?>['du234-blocked', 'query 차단', null]);
        }
        events.add(sig);
        return codec.encodeMessage(<Object?>[PigeonQuerySnapshot(documents: docs, documentChanges: const [], metadata: meta)]);
      } catch (e, st) {
        harness.add({'handler': 'queryGet', 'bytes': _b64(msg), 'error': '$e', 'stack': '$st'.split(nl).take(8).toList()});
        return codec.encodeMessage(<Object?>['du234-harness', '대역 오류', null]);
      }
    });
    for (final op in const ['documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete', 'writeBatchCommit',
      'transactionCreate', 'transactionStoreResult', 'transactionGet', 'aggregateQuery', 'querySnapshot', 'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        blocked.add('write $op');
        return codec.encodeMessage(<Object?>['du234-blocked', '$op 차단', null]);
      });
    }
  }

  // 목록 callable 응답 계획 — 'two'(공고 A·B) / 'error'(일반 네트워크 실패). 비면 'error'.
  final listPlan = <String>[];
  void stubFunctions() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(fnChannel, (msg) async {
      const c = StandardMessageCodec();
      try {
        final args = (c.decodeMessage(msg) as List).first as Map;
        final name = args['functionName'];
        final region = args['region'];
        final sig = 'fn $name@$region ${_canon(args['parameters'])}';
        const allowed = {'callableGetPostingQuotaSummary', 'callableGetAdminTOs'};
        if (region != 'asia-northeast3' || !allowed.contains(name)) {
          blocked.add(sig);
          return c.encodeMessage(<Object?>['not-found', 'du234-blocked', <String, Object?>{'code': 'not-found'}]);
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
          return c.encodeMessage(<Object?>['unavailable', 'du234 local network failure',
            <String, Object?>{'code': 'unavailable', 'message': 'du234 local network failure'}]);
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
      } catch (e, st) {
        harness.add({'handler': 'functions', 'bytes': _b64(msg), 'error': '$e', 'stack': '$st'.split(nl).take(8).toList()});
        return c.encodeMessage(<Object?>['internal', 'du234-harness', null]);
      }
    });
  }

  // ── 실행 전 고정한 정확 reader(정규형 multiset). 배율 왕복·펼침은 추가 0 이어야 한다. ──
  const qtail = 'limitToLast=null cursors=[[],[],[],[]] filters=null app=[DEFAULT] opts=serverAndCache/none';
  const qWorkTypes = 'query businesses/$kBiz/workTypes cg=false where=[[FP(isActive),"==",true]] orderBy=[[FP(displayOrder),false]] limit=100 $qtail';
  const qTemplates = 'query businesses/$kBiz/contract_templates cg=false where=[] orderBy=[[FP(createdAt),true]] limit=100 $qtail';
  const fnQuota = 'fn callableGetPostingQuotaSummary@asia-northeast3 {businessIds:["$kBiz"]}';
  const fnList = 'fn callableGetAdminTOs@asia-northeast3 {activeOnly:false,businessIds:["$kBiz"],closedOnly:false}';
  const readyEvents = [
    'get businesses/$kBiz',
    'get users/$kOwner',
    qWorkTypes,
    qTemplates,
    fnQuota,
    fnList,
    'query tos/$kToA/slots cg=false where=[] orderBy=[[FP(date),false]] limit=501 $qtail',
    'query tos/$kToB/slots cg=false where=[] orderBy=[[FP(date),false]] limit=501 $qtail',
  ];
  final predicted = <String, List<String>>{
    'normal': [...readyEvents]..sort(),
    'stale': [...readyEvents, fnQuota, fnList]..sort(),
  };
  // ⑦ 앱이 catch 해 debugPrint 한 오류 메시지의 첫 줄(첫 줄바꿈 앞) — 정상 0건, stale 은 명시 reload 실패 1회의
  //   service(getTOGroupItemsLight) → controller(load) 두 메시지. 메시지 원문은 첫 줄 뒤에 빈 줄·예외 스택이 붙는다(233 STOP).
  const failLine = '[firebase_functions/unavailable] du234 local network failure';
  final allowedAppErrors = <String, List<String>>{
    'normal': const [],
    'stale': const ['❌ getTOGroupItemsLight 실패: $failLine', '❌ WorkforceController.load 실패: $failLine'],
  };
  List<String> firstLines(List<String> messages) => [for (final m in messages) m.split(nl).first];

  testWidgets('D234 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final prevDebugPrint = debugPrint;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    debugPrint = (String? m, {int? wrapWidth}) {
      if (m != null && (m.contains('❌') || m.contains('⚠️'))) appErrors.add(m);
      prevDebugPrint(m, wrapWidth: wrapWidth);
    };

    var nPump = 0, nMount = 0, nTap = 0, nDrag = 0, nPng = 0;
    const maxFrames = 800, maxTap = 8, maxDrag = 8, maxPng = 6;
    final tapLog = <String>[];
    var cur = '(시작)';
    Object? lastIdentity; // 가장 최근 계산한 identity — 다음 guard 가 실패해도 STOP 에 남긴다.
    Map<String, int> counts() => {'pump': nPump, 'pumpWidget': nMount, 'tap': nTap, 'drag': nDrag, 'png': nPng};
    Never stop(String why) {
      _out('D234-STOP ${jsonEncode({
            'phase': phase, 'at': cur, 'why': why, 'errors': errors, 'appErrors': appErrors, 'harness': harness,
            'counts': counts(), 'events': events, 'blocked': blocked, 'lastIdentity': lastIdentity,
          })}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    // ⑦·⑧ 앱 오류 메시지 비교 — 첫 줄 목록 정확(건수·순서·중복). 원문 전체는 STOP 의 appErrors 에 남는다.
    void appErrorsMatch(String flowId, String at) => need(jsonEncode(firstLines(appErrors)) == jsonEncode(allowedAppErrors[flowId]),
        '$at 앱 오류 메시지 첫 줄이 허용 목록과 다름 ${firstLines(appErrors)}');
    String? prevFlow;

    void budget() => need(nPump + nMount <= maxFrames && nTap <= maxTap && nDrag <= maxDrag && nPng <= maxPng, '사용량 한도 초과 ${counts()}');
    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        budget();
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    // 공통 실패 guard — 대역 예외·차단·프레임워크 예외/overflow.
    void safe(String at) {
      need(harness.isEmpty, '$at 대역 오류: $harness');
      need(blocked.isEmpty, '$at 쓰기·허용 밖 호출·차단 읽기: $blocked');
      final ex = t.takeException();
      need(errors.isEmpty && ex == null, '$at 예외/overflow: ${errors.take(3).toList()} / $ex');
    }

    Finder rich(bool Function(String p) f, {Finder? within}) {
      final m = find.byWidgetPredicate((w) => w is RichText && f(TextLayout.plain(w.text.toPlainText())), skipOffstage: false);
      return within == null ? m : find.descendant(of: within, matching: m, skipOffstage: false);
    }

    Finder cardOf(String id) => find.byWidgetPredicate((w) => w is TOGroupCard && w.groupItem.id == id, skipOffstage: false);
    final key = GlobalKey();

    try {
      // ── ② 자가확인: 실제 플러그인 전송 형식(FieldPath 든 where·orderBy)을 새 대역이 해독·정확 대조하는가 ──
      cur = '자가확인';
      stubFirestore();
      events.clear();
      final selfCheck = await t.runAsync(() async {
        final db = cf.FirebaseFirestore.instance;
        final a = await db.collection('businesses').doc(kBiz).collection('workTypes')
            .where('isActive', isEqualTo: true).orderBy('displayOrder').limit(100).get();
        final b = await db.collection('businesses').doc(kBiz).collection('contract_templates')
            .orderBy('createdAt', descending: true).limit(100).get();
        return [a.docs.length, b.docs.length];
      });
      _out('D234-SELFCHECK ${jsonEncode({'events': events, 'docs': selfCheck, 'harness': harness, 'blocked': blocked})}');
      need(harness.isEmpty && blocked.isEmpty, '자가확인 대역 오류');
      need(jsonEncode(events) == jsonEncode([qWorkTypes, qTemplates]), '자가확인 정확값 불일치 $events');
      need(jsonEncode(selfCheck) == jsonEncode([1, 1]), '자가확인 응답 문서 수 $selfCheck');
      events.clear();

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
          safe('unmount');
          appErrorsMatch(prevFlow!, '${prevFlow!} 흐름 종료(unmount 직후·clear 직전)');
        }
        FirstPostingReadinessStore.reset();
        PostingQuotaStore.reset();
        PostingQuotaStore.fetchCount = 0;
        events.clear();
        blocked.clear();
        appErrors.clear();
        prevFlow = flow.id;
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
        need(appErrors.isEmpty, '진입 앱 reader 오류: $appErrors');
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
          // 공고 A(사흘)를 공개 tap 으로 펼친다 — 슬롯은 이미 읽혀 있어 추가 reader 가 없다(펼침은 목록 State 의 ID 집합).
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
        Map<String, State> prevById = {};
        Map<int, State> prevByIndex = {};
        final ownerOf = <State, String>{}; // 한 번이라도 본 State → 마지막으로 그 State 를 가진 공고 ID
        final serial = <State, int>{}; // 기록용 State 번호(처음 본 순서)
        int sn(State s) => serial.putIfAbsent(s, () => serial.length + 1);

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

          // ── 카드 State·sliver index·실제 생성 범위(먼저 계산해 STOP 에 남긴다) ──
          final states = <String, State>{};
          final index = <String, int>{};
          RenderSliverMultiBoxAdaptor? sliver;
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
            sliver = r.parent as RenderSliverMultiBoxAdaptor?;
          }
          List<int>? built;
          if (sliver != null && sliver.firstChild != null) {
            built = [sliver.indexOf(sliver.firstChild!), sliver.indexOf(sliver.lastChild!)];
          }
          final prevMounted = {for (final e in prevById.entries) e.key: e.value.mounted};
          final identity = {
            'cards': {for (final e in states.entries) e.key: {'state': sn(e.value), 'index': index[e.key]}},
            'prevStatesStillMounted': prevMounted, 'builtIndexRange': built,
          };
          lastIdentity = identity;

          // ── 트리 identity ──
          need(identical(t.state(find.byType(JobsRootScreen)), rootState), 'root State 교체');
          need(identical(t.state(find.byType(WorkforceListView)), listState), 'list State 교체');
          need(identical(ctl(), controller0), 'controller 교체');
          final sc = scrollCtl();
          need(identical(sc, scroll0) && sc.positions.length == 1, 'ScrollController 교체/중복 부착 (${sc.positions.length})');

          // ── 요약 자리(배치 전환)·ID→index ──
          final summaryInList = find
              .descendant(of: find.byType(WorkforceListView), matching: find.byType(PostingQuotaSummaryBar), skipOffstage: false)
              .evaluate()
              .isNotEmpty;
          need(summaryInList == flow.summaryAt[k], '요약 자리 예측과 다름(목록 안=$summaryInList)');
          final lead = summaryInList ? 1 : 0;
          need(states.containsKey(kToA), '추적 공고 A 가 마운트되지 않음');
          if (flow.id == 'normal') need(states.containsKey(kToB), '공고 B 가 마운트되지 않음(정상 흐름은 전 구간 생존 계획)');
          for (final e in index.entries) {
            need(e.value == lead + (e.key == kToA ? 0 : 1), 'ID→index 불일치 ${e.key}=${e.value} lead=$lead');
          }

          // ── State 연속성: after = 공고 ID 를 따름 / baseline = index 를 따름(사전 예상 결함) ──
          final judged = <String, String>{};
          for (final e in states.entries) {
            final id = e.key;
            final st = e.value;
            final byId = prevById[id];
            final byIndex = prevByIndex[index[id]];
            final seenBefore = ownerOf.containsKey(st);
            if (k == 0) {
              judged[id] = 'first';
              continue;
            }
            if (after) {
              if (byId != null) {
                need(identical(st, byId), '$id State 가 유지되지 않음(after)');
                judged[id] = 'preserved';
              } else {
                // 직전 시점에 마운트되지 않았던 카드 — 새 State 여야 하고, 보존 성공에 넣지 않는다.
                need(!seenBefore, '$id 가 다른 공고의 State 를 받음(after)');
                judged[id] = 'newMount';
              }
            } else {
              // baseline 허용 결함: 같은 index 에 직전 카드가 있었으면 그 카드의 State 를 그대로 받는다(공고가 바뀌어도).
              //   직전 그 index 가 카드가 아니었으면 새 State. 이와 다른 변화는 사전 결함 밖이라 중단한다.
              if (byIndex != null) {
                need(identical(st, byIndex), '$id baseline: 같은 index 의 직전 State 를 받지 않음(사전 예상과 다름)');
                judged[id] = identical(byIndex, byId) ? 'sameIdSameIndex' : 'tookIndexState(${ownerOf[st]})';
              } else {
                need(!seenBefore, '$id baseline: 새 index 인데 본 적 있는 State');
                judged[id] = byId == null ? 'newMount' : 'lostState';
              }
            }
          }
          // 직전 시점 State 중 지금 마운트되지 않은 것 — 정상 lazy disposal 근거(생성 범위 밖)와 함께 기록한다.
          final disposed = <String, Object?>{};
          for (final e in prevById.entries) {
            if (!states.containsKey(e.key)) {
              final expectedIndex = lead + (e.key == kToA ? 0 : 1);
              disposed[e.key] = {
                'prevStateMounted': e.value.mounted, 'expectedIndex': expectedIndex,
                'outsideBuilt': built == null || expectedIndex < built[0] || expectedIndex > built[1],
              };
              if (after) need(disposed[e.key] is Map && (disposed[e.key]! as Map)['outsideBuilt'] == true, '${e.key} 가 생성 범위 안인데 마운트되지 않음');
            }
          }
          (identity as Map<String, Object?>)['judged'] = judged;
          identity['disposed'] = disposed;
          for (final e in states.entries) {
            ownerOf[e.value] = e.key;
          }
          prevById = Map.of(states);
          prevByIndex = {for (final e in states.entries) index[e.key]!: e.value};

          // ── 공개 상태 유지: 펼침(정상, 목록 State 의 ID 집합) / 경고(stale) ──
          bool expanded(String id) => rich((p) => p == '날짜별 현황', within: cardOf(id)).evaluate().isNotEmpty;
          final expandedA = expanded(kToA);
          final expandedB = states.containsKey(kToB) ? expanded(kToB) : null;
          if (flow.id == 'normal') need(expandedA && expandedB != true, '펼침이 공고 A 에 남지 않음 A=$expandedA B=$expandedB');
          final staleF = rich((p) => p == '최신 정보를 불러오지 못했습니다. 다시 시도해 주세요.');
          final staleVisible = staleF.evaluate().isNotEmpty && screen.overlaps(t.getRect(staleF.first));
          if (flow.id == 'stale') need(staleVisible, '오래된 데이터 경고가 사라짐');

          // ── reader: 정확값 multiset(추가 0)·앱이 잡은 reader 오류 ──
          final got = [...events]..sort();
          need(jsonEncode(got) == jsonEncode(predicted[flow.id]), 'reader 정확값 불일치 got=$got');
          appErrorsMatch(flow.id, '캡처 전');
          safe('캡처 전');

          final shotId = 'D234-$phase-${flow.id}_p${k + 1}';
          nPng++;
          budget();
          await vqCapture(t, key, shotId, conditions: {
            'phase': phase, 'flow': flow.id, 'point': k + 1, 'textScaleFactor(기기)': s, 'viewport': '${flow.w.toInt()}x${flow.h.toInt()}',
            'dpr': 1.0, 'locale': locale, 'summaryInList': summaryInList, 'clock': '미주입(now=${_kst(now)})',
            'fixture': 'A=${datesOf(kToA).map(_key).join(',')} B=${datesOf(kToB).map(_key).join(',')}', 'steps': steps.join(' / '),
          });
          _out('D234 ${jsonEncode({
                'phase': phase, 'flow': flow.id, 'point': k + 1, 'scale': s, 'env': env, 'summaryInList': summaryInList, 'lead': lead,
                'root': identityHashCode(rootState), 'list': identityHashCode(listState), 'controller': identityHashCode(controller0),
                'scrollController': identityHashCode(scroll0), 'scrollPositions': sc.positions.length, 'scrollPixels': sc.offset,
                'identity': identity, 'expandedA': expandedA, 'expandedB': expandedB, 'staleVisible': staleVisible,
                'events': got, 'appErrors': appErrors, 'steps': steps, 'counts': counts(), 'taps': tapLog,
                'kst': _kst(DateTime.now()),
              })}');
        }
      }
      nMount++;
      budget();
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('끝');
      appErrorsMatch(prevFlow!, 'END 전');
      _out('D234-END ${jsonEncode({'phase': phase, 'counts': counts(), 'taps': tapLog})}');
    } finally {
      FlutterError.onError = prevOnError;
      debugPrint = prevDebugPrint;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
