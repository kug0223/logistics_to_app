// ignore_for_file: depend_on_referenced_packages
// [DU236 S037 국소 교정 baseline/after] 230 관측 시험(r3 `173ded69…`)을 셀 표식만 바꿔 옮기고, 아래만 더했다:
//   baseline/after phase 선택, after 성공조건(J1·J2 읽기색, J3 낱말 단위 줄바꿈, J4 선택 사업장 문구, K1·K3 머리 배치,
//   K2 receiver 48·경계 안쪽 hit), B320 zero/error 본문 도달 drag, 정확 reader·앱 오류 재확인(상세 drag 뒤·장면 종료·END).
//   시험 자체는 production 을 편집하지 않는다(교정은 셀의 정확 diff 로 baseline 과 after 사이에 반영한다).
//   DU236_RUN=1 이고 DU236_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip). 표준 shell(BusinessAdminShell) 없이 standalone 으로 연다
//   (postingController 없음 → 화면이 자기 WorkforceController 를 만든다). shell denied gate 는 관측하지 않는다.
//   reader: callable 이름·지역·payload 정규형 multiset 과 문서 get 경로를 실행 전 고정값과 정확 대조한다(query 는 0).
//   앱이 catch 해 debugPrint 한 ❌·⚠️ 메시지는 첫 줄로 대조한다. 첫 조회 실패 장면의 두 메시지는 병렬 Future 의 완료 순서가
//   제품 계약이 아니어서 multiset(정렬 비교)으로, 나머지 장면은 0건 정확으로 본다(계획에 고정).
//   시계는 주입하지 않는다(production _today/_isBeforeStart 는 실제 DateTime.now). 근무는 오늘(KST) 22:00 이후 시작이라
//   실행 시각이 22:00 KST 전이어야 '출근 전' fixture 가 유효하다 — 아니면 그 자리에서 멈춘다.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/workforce_management/workforce_operational_view.dart';
import 'package:ALfit/screens/business_admin/workforce_management/workforce_root_screen.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/navigation_key.dart';
import 'package:ALfit/utils/text_layout.dart';

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

const kBiz = 'biz-local-d236';
const kBizA = 'biz-local-d236-a';
const kBizB = 'biz-local-d236-b';
const kOwner = 'owner-local-d236';
const kSub = 'sub-local-d236';
const kLongTitle = '송파 물류센터 평일 야간 상하차·분류 보조 단기 인력 모집 안전화 지참 필수';
const kLongName = '알렉산드로 크리스티아누 페르난데스 김';

/// SubAdmin 배정 2곳의 권한 — A 는 근무자 관리만, B 는 없음. 공고 관리(canManageTo)는 둘 다 없음.
MemberPermissions _permsOf(String biz) => biz == kBizA ? const MemberPermissions(canManageWorkers: true) : const MemberPermissions();

class _Owner extends UserProvider {
  _Owner(this.bizIds);
  final List<String> bizIds;
  @override
  UserModel? get currentUser => UserModel(uid: kOwner, username: 'owner', name: 'QA 사장', email: 'o@test.local',
      role: UserRole.BUSINESS_ADMIN, businessId: bizIds.isEmpty ? null : bizIds.first, managedBusinessIds: bizIds,
      createdAt: DateTime(2026, 1, 1));
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

/// 배정 2곳(A·B), 유효 선택 A. 권한 판정은 _permsOf 에 실제 predicate 를 적용해 세 API 가 같은 답을 낸다.
class _Sub extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: kSub, username: 'sub', name: 'QA 서브', email: 's@test.local',
      role: UserRole.USER, subAdminBusinessIds: const [kBizA, kBizB], createdAt: DateTime(2026, 1, 1));
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => true;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
  @override
  String? get effectiveBusinessId => kBizA;
  @override
  Map<String, String> get subAdminBusinessNames => const {kBizA: 'QA 물류센터 A', kBizB: 'QA 물류센터 B'};
  @override
  bool can(bool Function(MemberPermissions p) check) => check(_permsOf(kBizA));
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => check(_permsOf(businessId));
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      check(_permsOf(businessId)) ? PermissionCheck.allowed : PermissionCheck.denied;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) =>
      check(_permsOf(kBizA)) ? PermissionCheck.allowed : PermissionCheck.denied;
  @override
  ({List<String> allowed, List<String> unresolved}) subAdminBusinessesFor(bool Function(MemberPermissions p) check) =>
      (allowed: [for (final id in const [kBizA, kBizB]) if (check(_permsOf(id))) id], unresolved: const <String>[]);
}

String _kst(DateTime d) {
  final k = d.toUtc().add(const Duration(hours: 9));
  String p(int x) => x.toString().padLeft(2, '0');
  return '${k.year}-${p(k.month)}-${p(k.day)} ${p(k.hour)}:${p(k.minute)} KST';
}

/// reader 인자 정규형 — 맵은 키 정렬, 문자열은 JSON 따옴표.
String _canon(Object? v) {
  if (v == null) return 'null';
  if (v is String) return jsonEncode(v);
  if (v is num || v is bool) return '$v';
  if (v is List) return '[${v.map(_canon).join(',')}]';
  if (v is Map) {
    final keys = v.keys.map((k) => '$k').toList()..sort();
    return '{${keys.map((k) => '$k:${_canon(v.entries.firstWhere((e) => '${e.key}' == k).value)}').join(',')}}';
  }
  return '${v.runtimeType}($v)';
}

String _b64(ByteData? msg) =>
    msg == null ? 'null' : base64Encode(msg.buffer.asUint8List(msg.offsetInBytes, msg.lengthInBytes));

double _lum(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final x = _lum(a);
  final y = _lum(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

String _hex(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

void main() {
  final phase = Platform.environment['DU236_PHASE'] ?? '';
  final run = Platform.environment['DU236_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  final events = <String>[];
  final blocked = <String>[];
  final harness = <Map<String, Object?>>[];
  final appErrors = <String>[];
  const base = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  const fnChannel = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });
  final meta = PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false);

  // ── 날짜: 실행 시점의 KST 오늘. 저장 관례(DATE_ONLY) = 그 날 KST 자정 instant. ──
  final now = DateTime.now();
  final kstNow = now.toUtc().add(const Duration(hours: 9));
  int kstMidnightMs(int y, int m, int d) =>
      DateTime.utc(y, m, d).subtract(const Duration(hours: 9)).millisecondsSinceEpoch;
  final d0 = kstMidnightMs(kstNow.year, kstNow.month, kstNow.day);
  final d1 = d0 + 86400000;
  // 날짜 표식 범위: 그 달 1일 −7일 KST 자정 ~ (다음 달 1일 +7일)의 다음 KST 자정.
  final monthFirst = DateTime(kstNow.year, kstNow.month, 1);
  final mStart = monthFirst.subtract(const Duration(days: 7));
  final mEnd = DateTime(kstNow.year, kstNow.month + 1, 1).add(const Duration(days: 7));
  final m0 = kstMidnightMs(mStart.year, mStart.month, mStart.day);
  final m1 = kstMidnightMs(mEnd.year, mEnd.month, mEnd.day) + 86400000;

  Map<String, Object?> app(String id, String uid, String biz, String bizName, String toId, String slot, String wd,
          String workType, String start, String end, String toTitle, String status, String applicant) =>
      {
        'id': id, 'uid': uid, 'businessId': biz, 'businessName': bizName, 'toId': toId, 'slotId': slot, 'workDetailId': wd,
        'selectedWorkType': workType, 'startTime': start, 'endTime': end, 'toTitle': toTitle, 'status': status,
        'type': 'short', 'applicantName': applicant, 'wage': 12000, 'wageType': 'hourly',
        'workDate': {'_seconds': d0 ~/ 1000, '_nanoseconds': 0},
        'appliedAt': {'_seconds': d0 ~/ 1000 - 86400 * 3, '_nanoseconds': 0},
        'confirmedAt': {'_seconds': d0 ~/ 1000 - 86400 * 2, '_nanoseconds': 0},
      };
  // 장면 1 정상 다수(사업장 kBiz): 그룹 2 — 긴 공고 제목·계약 미작성·긴 이름·출근 전.
  final manyApps = [
    app('app-d236-1', 'u-d236-1', kBiz, 'QA 물류센터', 'to-d236-1', 'slot-d236-1', 'wd-d236-1', '상하차·분류 보조', '22:00', '23:30',
        kLongTitle, 'CONFIRMED', '김민수'),
    app('app-d236-2', 'u-d236-2', kBiz, 'QA 물류센터', 'to-d236-1', 'slot-d236-1', 'wd-d236-1', '상하차·분류 보조', '22:00', '23:30',
        kLongTitle, 'CONTRACT_PENDING', '이서연'),
    app('app-d236-3', 'u-d236-3', kBiz, 'QA 물류센터', 'to-d236-1', 'slot-d236-1', 'wd-d236-1', '상하차·분류 보조', '22:00', '23:30',
        kLongTitle, 'CONFIRMED', kLongName),
    app('app-d236-4', 'u-d236-4', kBiz, 'QA 물류센터', 'to-d236-2', 'slot-d236-2', 'wd-d236-2', '검수', '23:00', '23:50',
        '검수 보조 야간', 'CONFIRMED', '박지훈'),
  ];
  // 장면 5 SubAdmin(유효 사업장 A): 그룹 1.
  final subApps = [
    app('app-d236-5', 'u-d236-5', kBizA, 'QA 물류센터 A', 'to-d236-a', 'slot-d236-a', 'wd-d236-a', '포장 보조', '22:30', '23:30',
        'A 사업장 야간 포장 보조', 'CONFIRMED', '최유진'),
    app('app-d236-6', 'u-d236-6', kBizA, 'QA 물류센터 A', 'to-d236-a', 'slot-d236-a', 'wd-d236-a', '포장 보조', '22:30', '23:30',
        'A 사업장 야간 포장 보조', 'CONFIRMED', '정하늘'),
  ];
  final names = {for (final a in [...manyApps, ...subApps]) a['uid']! as String: a['applicantName']! as String};
  Map<String, Object?> bizMap(String id, String name) => {
        'id': id, 'name': name, 'businessNumber': '000-00-00000', 'category': '물류', 'subCategory': '상하차',
        'address': '서울시 QA구 1', 'ownerId': kOwner, 'adminIds': [kOwner], 'isApproved': true,
        // callable(JSON) 응답의 Timestamp 직렬형 — BusinessModel 은 createdAt 이 없으면 파싱을 거부한다.
        'createdAt': {'_seconds': DateTime.utc(2026, 10, 1).millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0},
      };

  var scene = '';
  void stubFirestore() {
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const codec = FirebaseFirestoreHostApi.codec;
    m.setMockMessageHandler('$base.documentReferenceGet', (msg) async {
      try {
        final args = codec.decodeMessage(msg) as List;
        final path = (args[1] as DocumentReferenceRequest).path;
        if (scene == 'subadmin' && path == 'businesses/$kBizA') {
          events.add('get $path');
          // 문서 get 은 Firestore 가 Timestamp 로 돌려준다.
          final data = Map<String?, Object?>.from(bizMap(kBizA, 'QA 물류센터 A'))
            ..remove('id')
            ..['createdAt'] = Timestamp.fromDate(DateTime.utc(2026, 10, 1));
          return codec.encodeMessage(<Object?>[PigeonDocumentSnapshot(path: path, data: data, metadata: meta)]);
        }
        blocked.add('get $path');
        return codec.encodeMessage(<Object?>['du236-blocked', 'get 차단: $path', null]);
      } catch (e, st) {
        harness.add({'handler': 'documentReferenceGet', 'bytes': _b64(msg), 'error': '$e', 'stack': '$st'.split(nl).take(8).toList()});
        return codec.encodeMessage(<Object?>['du236-harness', '대역 오류', null]);
      }
    });
    for (final op in const ['queryGet', 'documentReferenceSet', 'documentReferenceUpdate', 'documentReferenceDelete',
      'writeBatchCommit', 'transactionCreate', 'transactionStoreResult', 'transactionGet', 'aggregateQuery', 'querySnapshot',
      'documentReferenceSnapshot']) {
      m.setMockMessageHandler('$base.$op', (msg) async {
        blocked.add('firestore $op');
        return codec.encodeMessage(<Object?>['du236-blocked', '$op 차단', null]);
      });
    }
  }

  void stubFunctions() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(fnChannel, (msg) async {
      const c = StandardMessageCodec();
      try {
        final args = (c.decodeMessage(msg) as List).first as Map;
        final name = args['functionName'];
        final region = args['region'];
        final p = (args['parameters'] as Map?) ?? const {};
        final sig = 'fn $name@$region ${_canon(p)}';
        const allowed = {
          'callableGetAdminTOs', 'callableGetMyBusiness', 'callableGetApplicationsByBiz', 'callableGetAdminAttendances',
          'callableGetUsersBatch',
        };
        if (region != 'asia-northeast3' || !allowed.contains(name)) {
          blocked.add(sig);
          return c.encodeMessage(<Object?>['not-found', 'du236-blocked', <String, Object?>{'code': 'not-found'}]);
        }
        events.add(sig);
        ByteData? ok(Object? data) => c.encodeMessage(<Object?>[data]);
        switch (name) {
          case 'callableGetAdminTOs':
            return ok(<String, Object?>{'items': const <Object?>[]});
          case 'callableGetMyBusiness':
            return ok(<String, Object?>{
              'businesses': scene == 'nobiz' ? const <Object?>[] : [bizMap(kBiz, 'QA 물류센터')],
            });
          case 'callableGetApplicationsByBiz':
            if (scene == 'error') {
              return c.encodeMessage(<Object?>['unavailable', 'du236 local network failure',
                <String, Object?>{'code': 'unavailable', 'message': 'du236 local network failure'}]);
            }
            final shortQuery = p.containsKey('workDateLtMs');
            final List<Map<String, Object?>> rows = !shortQuery
                ? const []
                : switch (scene) { 'many' => manyApps, 'subadmin' => subApps, _ => const <Map<String, Object?>>[] };
            return ok(<String, Object?>{'applications': rows});
          case 'callableGetAdminAttendances':
            return ok(<String, Object?>{'items': const <Object?>[], 'limitReached': false});
          default: // callableGetUsersBatch
            final uids = (p['uids'] as List).cast<String>();
            return ok(<String, Object?>{
              'users': {for (final u in uids) u: <String, Object?>{'name': names[u] ?? '?', 'role': 'USER'}},
            });
        }
      } catch (e, st) {
        harness.add({'handler': 'functions', 'bytes': _b64(msg), 'error': '$e', 'stack': '$st'.split(nl).take(8).toList()});
        return c.encodeMessage(<Object?>['internal', 'du236-harness', null]);
      }
    });
  }

  // ── 실행 전 고정 reader(정규형 multiset) ──
  String fnApps(String biz, {required bool short, required bool marker}) {
    final lo = marker ? m0 : d0;
    return short
        ? 'fn callableGetApplicationsByBiz@asia-northeast3 {businessId:"$biz",limit:2000,purpose:"workerOperation",workDateGteMs:$lo,workDateLtMs:${marker ? m1 : d1}}'
        : 'fn callableGetApplicationsByBiz@asia-northeast3 {businessId:"$biz",limit:2000,purpose:"workerOperation",workEndDateGteMs:$lo}';
  }

  String fnAtt(String biz) => 'fn callableGetAdminAttendances@asia-northeast3 {businessId:"$biz",endMs:$d1,startMs:$d0}';
  String fnUsers(String biz, List<String> uids) =>
      'fn callableGetUsersBatch@asia-northeast3 {businessId:"$biz",purpose:"workerDirectory",uids:${_canon(uids)}}';
  const fnTOs = 'fn callableGetAdminTOs@asia-northeast3 {activeOnly:false,businessIds:["$kBiz"],closedOnly:false}';
  const fnMyBiz = 'fn callableGetMyBusiness@asia-northeast3 {}';
  List<String> dayAndMarker(String biz) => [
        fnApps(biz, short: true, marker: false), fnApps(biz, short: false, marker: false), fnAtt(biz),
        fnApps(biz, short: true, marker: true), fnApps(biz, short: false, marker: true),
      ];
  final predicted = <String, List<String>>{
    'many': [fnTOs, fnMyBiz, ...dayAndMarker(kBiz), fnUsers(kBiz, ['u-d236-1', 'u-d236-2', 'u-d236-3', 'u-d236-4'])]..sort(),
    'zero': [fnTOs, fnMyBiz, ...dayAndMarker(kBiz)]..sort(),
    'error': [fnTOs, fnMyBiz, ...dayAndMarker(kBiz)]..sort(),
    'nobiz': [fnMyBiz],
    'subadmin': ['get businesses/$kBizA', ...dayAndMarker(kBizA), fnUsers(kBizA, ['u-d236-5', 'u-d236-6'])]..sort(),
  };
  const failLine = '[firebase_functions/unavailable] du236 local network failure';
  final allowedAppErrors = <String, List<String>>{
    'error': ['❌ [WorkforceOperationalView] 데이터 로드 실패: $failLine', '❌ 근무 날짜 marker 조회 실패: $failLine']..sort(),
  };
  const reachText = {
    'many': '계약 미작성',
    'zero': '오늘 확정된 인력이 없습니다.',
    'error': '데이터를 불러오지 못했습니다. 다시 시도해 주세요.',
    'nobiz': '아직 근무를 관리할 사업장이 없어요',
    'subadmin': '포장 보조',
  };

  testWidgets('D236 $phase', (t) async {
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
    // 요청236 phase 한도: pump+mount ≤1400, tap 0, drag ≤12, PNG ≤18(최초 10 + 상세 ≤8).
    const maxFrames = 1400, maxTap = 0, maxDrag = 12, maxPng = 18;
    var cur = '(시작)';
    Map<String, int> counts() => {'pump': nPump, 'pumpWidget': nMount, 'tap': nTap, 'drag': nDrag, 'png': nPng};
    Never stop(String why) {
      _out('D236-STOP ${jsonEncode({
            'at': cur, 'why': why, 'errors': errors, 'appErrors': appErrors, 'harness': harness, 'counts': counts(),
            'events': events, 'blocked': blocked,
          })}');
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

    void safe(String at) {
      need(harness.isEmpty, '$at 대역 오류: $harness');
      need(blocked.isEmpty, '$at 쓰기·허용 밖 호출·query·차단 읽기: $blocked');
      final ex = t.takeException();
      need(errors.isEmpty && ex == null, '$at 예외/overflow: ${errors.take(3).toList()} / $ex');
    }

    List<String> firstLines() => [for (final m in appErrors) m.split(nl).first];
    void appErrorsMatch(String sc, String at) {
      final got = firstLines();
      final want = allowedAppErrors[sc] ?? const <String>[];
      final sortedGot = [...got]..sort();
      need(jsonEncode(sortedGot) == jsonEncode(want), '$at 앱 오류 메시지 첫 줄이 허용 목록과 다름 $got');
    }

    // 정확 reader 재확인 — 캡처 전뿐 아니라 상세 drag 뒤·장면 종료·END 전에도 같은 multiset 이어야 한다(추가 조회 0).
    void readerMatch(String sc, String at) {
      final got = [...events]..sort();
      need(jsonEncode(got) == jsonEncode(predicted[sc]), '$at reader 정확값 불일치 got=$got');
    }

    Finder rich(bool Function(String p) f, {Finder? within}) {
      final m = find.byWidgetPredicate((w) => w is RichText && f(TextLayout.plain(w.text.toPlainText())), skipOffstage: false);
      return within == null ? m : find.descendant(of: within, matching: m, skipOffstage: false);
    }

    Finder? firstOf(Finder f) {
      final els = f.evaluate().toList();
      if (els.isEmpty) return null;
      final e = els.first;
      // 원 finder 가 화면 밖(캐시 영역) 요소까지 찾았으므로 되돌려 주는 finder 도 같은 범위를 쓴다.
      return find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    }

    double r1(double v) => double.parse(v.toStringAsFixed(1));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    bool inside(Rect r, Rect box) =>
        r.left >= box.left - 0.5 && r.top >= box.top - 0.5 && r.right <= box.right + 0.5 && r.bottom <= box.bottom + 0.5;

    final key = GlobalKey();
    String? prevScene;
    final startKstDate = _kst(DateTime.now()).substring(0, 10);

    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        for (final sc in const ['many', 'zero', 'error', 'nobiz', 'subadmin']) {
          cur = '${c.id} $sc';
          if (nMount > 0) {
            nMount++;
            budget();
            await t.pumpWidget(const SizedBox.shrink());
            await frames(1);
            safe('unmount');
            appErrorsMatch(prevScene ?? '', '$prevScene 장면 종료(unmount 직후)');
            readerMatch(prevScene ?? '', '$prevScene 장면 종료(unmount 직후)');
          }
          scene = sc;
          prevScene = sc;
          FirestoreService().clearCache();
          events.clear();
          blocked.clear();
          appErrors.clear();
          stubFirestore();
          stubFunctions();
          final kstHour = DateTime.now().toUtc().add(const Duration(hours: 9)).hour;
          need(kstHour < 22, "'출근 전' fixture 가 유효하지 않다(KST $kstHour시 — 22시 시작 근무)");
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          final UserProvider provider = switch (sc) {
            'nobiz' => _Owner(const []),
            'subadmin' => _Sub(),
            _ => _Owner(const [kBiz]),
          };
          nMount++;
          budget();
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
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
                home: const WorkforceRootScreen(),
              ),
            ),
          ));
          await frames(30);
          safe('진입');

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
          need(mq.size == Size(c.w, c.h) && mq.devicePixelRatio == 1.0 && (mq.textScaler.scale(14) / 14 - c.s).abs() < 1e-9 &&
              mq.padding == EdgeInsets.zero && mq.viewInsets == EdgeInsets.zero, '조건 불일치 $env');

          // ── 도달·reader·앱 오류(캡처 전) ──
          need(firstOf(rich((p) => p == reachText[sc])) != null, '장면 문구 미도달: ${reachText[sc]}');
          final got = [...events]..sort();
          need(jsonEncode(got) == jsonEncode(predicted[sc]), 'reader 정확값 불일치 got=$got');
          appErrorsMatch(sc, '캡처 전');
          safe('캡처 전');

          // ── 머리 행동 receiver(그림이 아닌 InkWell/GestureDetector, tap 0) ──
          Map<String, Object?> recv(String name, Finder? f) {
            if (f == null) return {'name': name, 'present': false};
            final r = t.getRect(f);
            final ro = t.renderObject(f);
            final hit = HitTestResult();
            WidgetsBinding.instance.hitTestInView(hit, r.center, t.view.viewId);
            bool hitsAt(Offset p) {
              final h = HitTestResult();
              WidgetsBinding.instance.hitTestInView(h, p, t.view.viewId);
              return h.path.any((e) => e.target == ro);
            }

            final inner = r.deflate(2);
            return {
              'name': name, 'present': true, 'rect': lt(r), 'w': r1(r.width), 'h': r1(r.height),
              'edgeHits': [inner.topLeft, inner.topRight, inner.bottomLeft, inner.bottomRight].every(hitsAt),
              'ge48': r.width >= 48 - 0.01 && r.height >= 48 - 0.01, 'centerHit': hit.path.any((e) => e.target == ro),
              'path': hit.path.take(4).map((e) => e.target.runtimeType.toString()).join('>'), 'inScreen': inside(r, screen),
            };
          }

          final head = [
            recv('일괄 근태', firstOf(find.ancestor(of: rich((p) => p == '일괄 근태'), matching: find.byType(GestureDetector)))),
            recv('지원자 명단', firstOf(find.descendant(of: find.byTooltip('지원자 명단'), matching: find.byType(InkWell)))),
            recv('고정 근로자', firstOf(find.descendant(of: find.byTooltip('고정 근로자'), matching: find.byType(InkWell)))),
          ];

          // ── 글자·색(J1·J2·J3) — 토큰 값과 rect(화소 표본은 PNG 에서 따로 잰다) ──
          Map<String, Object?> textInfo(String name, Finder? f, {Color? bgToken}) {
            if (f == null) return {'name': name, 'present': false};
            final rp = t.renderObject<RenderParagraph>(f);
            final r = t.getRect(f);
            final plain = TextLayout.plain(rp.text.toPlainText());
            final display = rp.text.toPlainText();
            // 줄별 글자 — 글자마다 선택 상자의 윗변으로 줄을 묶는다(RenderParagraph 에는 getLineBoundary 가 없다).
            final byLine = <int, StringBuffer>{};
            for (var i = 0; i < display.length; i++) {
              final bs = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
              if (bs.isEmpty) continue;
              byLine.putIfAbsent(bs.first.top.round(), () => StringBuffer()).write(display[i]);
            }
            final lines = [for (final k in byLine.keys.toList()..sort()) TextLayout.plain(byLine[k]!.toString())];
            Color? fg = rp.text.style?.color;
            if (rp.text is TextSpan) {
              for (final ch in (rp.text as TextSpan).children ?? const <InlineSpan>[]) {
                fg = ch.style?.color ?? fg;
              }
            }
            return {
              'name': name, 'present': true, 'plain': plain, 'rect': lt(r), 'inScreen': inside(r, screen),
              'maxLines': rp.maxLines, 'didExceedMaxLines': rp.didExceedMaxLines, 'lines': lines,
              'fontSize': rp.text.style?.fontSize, 'fg': fg == null ? null : _hex(fg),
              'bgToken': bgToken == null ? null : _hex(bgToken),
              'tokenContrast': fg == null || bgToken == null ? null : double.parse(_contrast(fg, bgToken).toStringAsFixed(2)),
            };
          }

          final texts = <Map<String, Object?>>[];
          if (sc == 'many' || sc == 'subadmin') {
            texts.add(textInfo('J1 공고 제목', firstOf(rich((p) => p == (sc == 'many' ? kLongTitle : 'A 사업장 야간 포장 보조'))),
                bgToken: AppColors.grey50));
            texts.add(textInfo('J1 출근 전 칩', firstOf(rich((p) => p == '출근 전')), bgToken: AppColors.grey50));
          }
          if (sc == 'many') {
            texts.add(textInfo('계약 미작성', firstOf(rich((p) => p == '계약 미작성')), bgToken: Colors.white));
            texts.add(textInfo('긴 이름', firstOf(rich((p) => p == kLongName)), bgToken: Colors.white));
          }
          if (sc == 'zero') texts.add(textInfo('J2 빈 문구', firstOf(rich((p) => p == reachText['zero'])), bgToken: Colors.white));
          if (sc == 'error') texts.add(textInfo('J2·J3 오류 문구', firstOf(rich((p) => p == reachText['error'])), bgToken: Colors.white));
          if (sc == 'nobiz') {
            texts.add(textInfo('사업장0 부제', firstOf(rich((p) => p.startsWith('사업장을 등록하면'))), bgToken: Colors.white));
          }
          if (sc == 'error') {
            texts.add(textInfo('J3 marker 문구', firstOf(rich((p) => p == '근무가 있는 날짜를 표시하지 못했어요')), bgToken: Colors.white));
          }
          if (sc != 'nobiz') texts.add(textInfo('K3 날짜 머리', firstOf(rich((p) => p.startsWith('오늘 ·'))), bgToken: Colors.white));
          if (sc == 'many') texts.add(textInfo('K1 첫 그룹', firstOf(rich((p) => p == '상하차·분류 보조')), bgToken: AppColors.grey50));
          Map<String, Object?>? textNamed(String n) {
            for (final x in texts) {
              if (x['name'] == n) return x;
            }
            return null;
          }
          final scopeLabel = firstOf(find.descendant(
              of: find.byType(WorkforceRootScreen),
              matching: find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == 12 && w.data != null && w.maxLines == 1)));
          final visible = t
              .widgetList<RichText>(find.descendant(of: find.byType(WorkforceRootScreen), matching: find.byType(RichText)))
              .map((w) => TextLayout.plain(w.text.toPlainText()).replaceAll(nl, ' '))
              .where((s) => s.trim().isNotEmpty)
              .toList();

          final scopeText = scopeLabel == null ? null : t.widget<Text>(scopeLabel).data;

          // ── after 성공조건(캡처 전) — baseline 은 같은 값을 결함값으로 기록만 한다 ──
          if (after) {
            final present = head.where((h) => h['present'] == true).toList();
            for (final h in present) {
              need(h['ge48'] == true && h['inScreen'] == true && h['centerHit'] == true && h['edgeHits'] == true, 'K2 receiver $h');
            }
            for (var i = 0; i < present.length; i++) {
              for (var j = i + 1; j < present.length; j++) {
                final a = present[i]['rect']! as List<double>;
                final b = present[j]['rect']! as List<double>;
                need(!Rect.fromLTRB(a[0], a[1], a[2], a[3]).deflate(0.5).overlaps(Rect.fromLTRB(b[0], b[1], b[2], b[3]).deflate(0.5)),
                    'K2 receiver 겹침 ${present[i]['name']}×${present[j]['name']}');
              }
            }
            const wantFg = {
              'J1 공고 제목': '#686C77', 'J1 출근 전 칩': '#686C77', 'J2 빈 문구': '#60646F', 'J2·J3 오류 문구': '#60646F',
              '사업장0 부제': '#60646F',
            };
            for (final e in wantFg.entries) {
              final x = textNamed(e.key);
              if (x == null) continue;
              final tc = x['tokenContrast'];
              need(x['present'] == true && x['fg'] == e.value && tc is double && tc >= 4.5, 'J1·J2 읽기색 $x');
            }
            final title = textNamed('J1 공고 제목');
            if (title != null) need(title['maxLines'] == null && title['didExceedMaxLines'] == false, 'J1 공고 제목 말줄임 $title');
            for (final n in const ['J2·J3 오류 문구', 'J3 marker 문구']) {
              final x = textNamed(n);
              if (x == null) continue;
              need(x['present'] == true, 'J3 문단 누락 $n');
              final lines = (x['lines']! as List).cast<String>();
              need(lines.map((l) => l.trim()).join(' ') == x['plain'], 'J3 낱말 안 줄바꿈 $n $lines');
            }
            if (sc == 'subadmin') need(scopeText == 'QA 물류센터 A', 'J4 머리 문구 $scopeText');
            if (c.id == 'B320' && sc != 'nobiz') {
              final kd = textNamed('K3 날짜 머리');
              need(kd != null && kd['present'] == true, 'K3 날짜 머리 문단 누락');
              final dateLines = (kd!['lines']! as List).length;
              need(dateLines <= 2, 'K3 날짜 머리 $dateLines줄');
            }
            if (c.id == 'B320' && sc == 'many') {
              final g1 = textNamed('K1 첫 그룹');
              need(g1 != null && g1['present'] == true, 'K1 첫 그룹 문단 누락');
              need((g1!['rect']! as List<double>)[1] < screen.bottom, 'K1 첫 그룹 식별 정보가 첫 화면에서 시작하지 않음 $g1');
            }
          }

          final shot = 'D236-$phase-${c.id}_$sc';
          nPng++;
          budget();
          await vqCapture(t, key, shot, conditions: {
            'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaleFactor(기기)': c.s,
            'locale': locale, 'theme': 'RoleTheme.businessAdminTheme', 'clock': '미주입(now=${_kst(DateTime.now())})',
            'fixture': 'KST 오늘 근무 22:00 이후 시작',
          });

          // ── 상세 도달(공개 drag 최대 2, drag 마다 PNG): many W·B / zero·error B ──
          final details = <Map<String, Object?>>[];
          final reach = <String, int>{};
          final scrollF = find.descendant(of: find.byType(WorkforceOperationalView), matching: find.byType(Scrollable));
          final scroll = scrollF.evaluate().isEmpty ? null : scrollF.first;
          Map<String, Finder Function()> targets = {};
          if (sc == 'many') {
            Finder firstRich(String s) => firstOf(rich((p) => p == s)) ?? rich((p) => p == s);
            targets = {
              '첫 근무자 이름': () => firstRich('김민수'),
              '첫 근무자 시각': () => firstRich('22:00 출근 예정'),
              '그룹1 공고 제목 전문': () => firstRich(kLongTitle),
              '긴 이름': () => firstRich(kLongName),
              '그룹2 공고 제목': () => firstRich('검수 보조 야간'),
            };
          } else if (c.id == 'B320' && sc == 'zero') {
            targets = {'빈 문구 전문': () => rich((p) => p == reachText['zero'])};
          } else if (c.id == 'B320' && sc == 'error') {
            targets = {
              '오류 문구 전문': () => rich((p) => p == reachText['error']),
              '본문 다시 시도': () => find.ancestor(of: rich((p) => p == '다시 시도'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)),
            };
          }
          void look(int k) {
            if (scroll == null) return;
            final vp = t.getRect(scroll);
            for (final e in targets.entries) {
              if (reach.containsKey(e.key)) continue;
              final f = e.value();
              if (f.evaluate().isEmpty) continue;
              final r = t.getRect(f.first);
              if (inside(r, vp) && inside(r, screen)) reach[e.key] = k;
            }
          }

          look(0);
          if (scroll != null && targets.isNotEmpty) {
            for (var k = 1; k <= 2; k++) {
              if (reach.length == targets.length) break;
              final vp = t.getRect(scroll);
              final pos = t.state<ScrollableState>(scroll).position;
              if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
              final from = Offset(vp.left + 24, vp.bottom - 12);
              var want = vp.height * 0.7;
              if (sc != 'many') {
                // zero·error: 아직 못 본 대상의 아랫변을 viewport 안 8px 로(끌기 시작 slop 보정 +24).
                final miss = targets.entries.firstWhere((e) => !reach.containsKey(e.key)).value();
                if (miss.evaluate().isNotEmpty) want = t.getRect(miss.first).bottom - (vp.bottom - 8) + 24;
              }
              final d = want < from.dy - 12 ? want : from.dy - 12;
              if (d <= 0) break;
              nDrag++;
              budget();
              final px0 = pos.pixels;
              await t.dragFrom(from, Offset(0, -d));
              await frames(6);
              safe('상세 drag');
              readerMatch(sc, '상세 drag 뒤');
              appErrorsMatch(sc, '상세 drag 뒤');
              final px1 = t.state<ScrollableState>(scroll).position.pixels;
              look(k);
              final g2 = textInfo('J1 공고 제목(그룹2)', firstOf(rich((p) => p == '검수 보조 야간')), bgToken: AppColors.grey50);
              nPng++;
              budget();
              await vqCapture(t, key, '${shot}_d$k', conditions: {'phase': phase, 'scene': '$sc-detail', 'drag': k, 'textScaleFactor(기기)': c.s});
              details.add({'drag': k, 'request': r1(d), 'pixels': [r1(px0), r1(px1)], 'group2Title': g2});
            }
          }
          if (after && c.id == 'B320' && targets.isNotEmpty) {
            for (final n in targets.keys) {
              final limit = n.startsWith('첫 근무자') ? 1 : 2;
              need(reach.containsKey(n) && reach[n]! <= limit, 'K1·J3 도달 $n reach=$reach');
            }
          }
          need(_kst(DateTime.now()).substring(0, 10) == startKstDate, 'KST 날짜가 실행 중 바뀜');
          _out('D236 ${jsonEncode({
                'phase': phase, 'cond': c.id, 'scene': sc, 'env': env, 'events': got, 'appErrors': appErrors, 'head': head,
                'texts': texts, 'scopeLabel': scopeText, 'visible': visible, 'reach': reach, 'details': details,
                'counts': counts(), 'kst': _kst(DateTime.now()),
              })}');
        }
      }
      nMount++;
      budget();
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('끝');
      appErrorsMatch(prevScene ?? '', 'END 전');
      readerMatch(prevScene ?? '', 'END 전');
      _out('D236-END ${jsonEncode({'counts': counts(), 'startKstDate': startKstDate, 'endKst': _kst(DateTime.now())})}');
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
