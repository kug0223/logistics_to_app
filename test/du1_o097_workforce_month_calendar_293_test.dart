// ignore_for_file: depend_on_referenced_packages
// [DU293 인력 운영 월 달력(DU-O097) baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   DU236 시험(du1_s037_local_corrections_236_test.dart)의 대역·데이터(main 안 앞부분)를 그대로 가져왔다. 장면 many 만 쓴다.
//   실제 WorkforceRootScreen 을 띄우고 '月' 아이콘을 눌러 월 달력 시트를 연다(누름 1, 날짜는 고르지 않는다).
//   DU293_RUN=1 이고 DU293_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip). 시험은 production 을 편집하지 않는다.
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
  final phase = Platform.environment['DU293_PHASE'] ?? '';
  final run = Platform.environment['DU293_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
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

  testWidgets('D293 $phase', (t) async {
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
    var nPump = 0, nPng = 0, nTap = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D293-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors, 'appErrors': appErrors, 'harness': harness, 'blocked': blocked})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 1500 && nPng <= 12 && nTap <= 6, '사용량 한도');
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    final overflow = <String>[];
    void safe(String at) {
      need(harness.isEmpty, '$at 대역 오류: $harness');
      need(blocked.isEmpty, '$at 쓰기·허용 밖 호출·차단 읽기: $blocked');
      final ex = t.takeException();
      need(ex == null, '$at 예외: $ex');
      for (final e in errors) {
        if (!after && e.startsWith('A RenderFlex overflowed by')) {
          overflow.add('$at $e');
        } else {
          stop('$at 예외/overflow: $e');
        }
      }
      errors.clear();
    }

    double r1(double v) => double.parse(v.toStringAsFixed(1));
    double r2(double v) => double.parse(v.toStringAsFixed(2));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    Finder fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);

    Color bgOf(Element e) {
      final layers = <Color>[];
      e.visitAncestorElements((a) {
        final w = a.widget;
        Color? c;
        if (w is ColoredBox) {
          c = w.color;
        } else if (w is DecoratedBox && w.decoration is BoxDecoration) {
          c = (w.decoration as BoxDecoration).color;
        } else if (w is Material && w.type != MaterialType.transparency) {
          c = w.color ?? Theme.of(a).canvasColor;
        } else if (w is Scaffold) {
          c = w.backgroundColor ?? Theme.of(a).scaffoldBackgroundColor;
        }
        if (c == null || c.a == 0) return true;
        layers.add(c);
        return c.a < 1.0;
      });
      var out = layers.isEmpty ? Colors.white : layers.last;
      for (final c in layers.reversed.skip(1)) {
        out = Color.alphaBlend(c, out);
      }
      return out;
    }

    Element? nearest(Element e, bool Function(Widget w) p) {
      Element? hit;
      e.visitAncestorElements((a) {
        if (p(a.widget)) {
          hit = a;
          return false;
        }
        return true;
      });
      return hit;
    }

    // 글자 단위 줄 나눔 — '낱말 안에서 끊긴' 곳 수(DU286·288~292 시험과 같은 규칙)
    ({List<String> lines, int sylBreaks}) lineInfo(RenderParagraph rp) {
      final raw = rp.text.toPlainText();
      final wj = String.fromCharCode(0x2060);
      final zw = String.fromCharCode(0x200B);
      bool word(String ch) {
        final u = ch.codeUnitAt(0);
        return (u >= 0xAC00 && u <= 0xD7A3) || (u >= 0x30 && u <= 0x39) || (u >= 0x41 && u <= 0x5A) || (u >= 0x61 && u <= 0x7A);
      }

      final lines = <String>[];
      var buf = StringBuffer();
      int? lastTop;
      var lastIdx = -1;
      var breaks = 0;
      for (var i = 0; i < raw.length; i++) {
        final ch = raw[i];
        if (ch == wj) continue;
        final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
        if (bx.isEmpty || ch == ' ' || ch == zw) {
          buf.write(ch);
          continue;
        }
        final top = bx.first.top.round();
        if (lastTop != null && top != lastTop) {
          lines.add(TextLayout.plain(buf.toString()).trim());
          buf = StringBuffer();
          final gap = raw.substring(lastIdx, i + 1);
          final sep = gap.contains(' ') || gap.contains(zw) || gap.contains(nl) || RegExp('[·,./()~:-]').hasMatch(gap);
          if (!sep && word(raw[lastIdx]) && word(ch)) breaks++;
        }
        buf.write(ch);
        lastTop = top;
        lastIdx = i;
      }
      lines.add(TextLayout.plain(buf.toString()).trim());
      return (lines: lines, sylBreaks: breaks);
    }

    Map<String, Object?> iconInfo(Element iconEl) {
      final w = iconEl.widget as Icon;
      final fg = w.color ?? IconTheme.of(iconEl).color;
      final bg = bgOf(iconEl);
      return {'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg), 'contrast': fg == null ? null : r2(_contrast(fg, bg)), 'size': w.size};
    }

    final key = GlobalKey();
    final rows = <Map<String, Object?>>[];
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'M360', w: 360.0, h: 780.0, s: 1.5),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        cur = c.id;
        await t.pumpWidget(const SizedBox.shrink());
        await frames(1);
        scene = 'many';
        FirestoreService().clearCache();
        events.clear();
        blocked.clear();
        appErrors.clear();
        stubFirestore();
        stubFunctions();
        final kstHour = DateTime.now().toUtc().add(const Duration(hours: 9)).hour;
        need(kstHour < 22, "'출근 전' fixture 가 유효하지 않다(KST $kstHour시)");
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        t.platformDispatcher.textScaleFactorTestValue = c.s;
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);
        await t.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<UserProvider>(create: (_) => _Owner(const [kBiz])),
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
        // DU236 과 같은 데이터가 같은 호출로 실렸는가(고정 호출값·장면 문구·앱 오류 0)
        final got0 = [...events]..sort();
        need(jsonEncode(got0) == jsonEncode(predicted['many']), '진입 호출이 DU236 고정값과 다르다 $got0');
        need(find.byWidgetPredicate((w) => w is RichText && TextLayout.plain(w.text.toPlainText()) == reachText['many'], skipOffstage: false)
            .evaluate().isNotEmpty, '장면 문구 미도달 ${reachText['many']}');
        need(appErrors.length == (allowedAppErrors['many'] ?? const <String>[]).length, '앱 오류 $appErrors');

        // ── '月' 버튼과 주간 칩 ──
        final monIcon = find.byIcon(Icons.calendar_month_outlined);
        need(monIcon.evaluate().length == 1, "'月' 아이콘 수 ${monIcon.evaluate().length}");
        final monEl = monIcon.evaluate().first;
        final gd = nearest(monEl, (w) => w is GestureDetector);
        need(gd != null, "'月' 누름 대상 없음");
        final btnR = t.getRect(fe(gd!));
        final sem = nearest(monEl, (w) => w is Semantics && (w.properties.label ?? '').isNotEmpty);
        final chips = <Map<String, Object?>>[];
        for (final e in find.byType(RichText, skipOffstage: false).evaluate()) {
          if (nearest(e, (w) => w is Icon) != null) continue;
          final r = t.getRect(fe(e));
          if (r.right > btnR.left + 0.5 || (r.center.dy - btnR.center.dy).abs() > btnR.height) continue;
          final rp = t.renderObject<RenderParagraph>(fe(e));
          final li = lineInfo(rp);
          chips.add({'text': TextLayout.plain(rp.text.toPlainText()), 'rect': lt(r), 'lines': li.lines, 'sylBreaks': li.sylBreaks,
            'didExceedMaxLines': rp.didExceedMaxLines});
        }
        final mon = {'box': lt(btnR), 'w': r1(btnR.width), 'h': r1(btnR.height), 'icon': iconInfo(monEl),
          'semLabel': sem == null ? null : (sem.widget as Semantics).properties.label};
        nPng++;
        await vqCapture(t, key, 'D293-$phase-${c.id}_strip', conditions: {'phase': phase, 'scene': 'strip', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s});

        // ── 시트 열기 ──
        nTap++;
        await t.tap(fe(gd));
        await frames(12);
        safe('시트 열림');
        final sheet = find.byType(BottomSheet);
        need(sheet.evaluate().length == 1, '시트 수 ${sheet.evaluate().length}');
        final sheetR = t.getRect(sheet);
        final texts = <Map<String, Object?>>[];
        for (final e in find.descendant(of: sheet, matching: find.byType(RichText), skipOffstage: false).evaluate()) {
          if (nearest(e, (w) => w is Icon) != null) continue;
          final rp = t.renderObject<RenderParagraph>(fe(e));
          final li = lineInfo(rp);
          final r = t.getRect(fe(e));
          texts.add({'text': TextLayout.plain(rp.text.toPlainText()), 'rect': lt(r), 'lines': li.lines.length, 'sylBreaks': li.sylBreaks,
            'didExceedMaxLines': rp.didExceedMaxLines, 'visible': r.top >= -0.5 && r.bottom <= c.h + 0.5});
        }
        final closeF = find.descendant(of: sheet, matching: find.byIcon(Icons.close));
        need(closeF.evaluate().length == 1, '닫기 수 ${closeF.evaluate().length}');
        final closeEl = closeF.evaluate().first;
        final ib = nearest(closeEl, (w) => w is IconButton);
        final closeR = ib == null ? Rect.zero : t.getRect(fe(ib));
        final close = {'w': r1(closeR.width), 'h': r1(closeR.height), 'icon': iconInfo(closeEl)};
        nPng++;
        await vqCapture(t, key, 'D293-$phase-${c.id}_sheet', conditions: {'phase': phase, 'scene': 'sheet', 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s});
        final row = {
          'phase': phase, 'cond': c.id, 'mon': mon, 'chips': chips, 'sheetRect': lt(sheetR),
          'sheetInside': sheetR.top >= screen.top - 0.5 && sheetR.bottom <= screen.bottom + 0.5,
          'title': texts.where((x) => x['text'] == '날짜 선택').toList(), 'sheetTexts': texts.length,
          'sheetSyl': texts.where((x) => (x['sylBreaks'] as int) > 0).toList(), 'close': close, 'overflowSoFar': overflow.length,
        };
        if (after) {
          need((mon['w'] as double) >= 48 && (mon['h'] as double) >= 48, "'月' 누름 $mon");
          final ic = mon['icon'] as Map;
          need((ic['contrast'] as double) >= 3 && ic['fg'] == _hex(AppColors.textSecondary), "'月' 아이콘 $mon");
          need((mon['semLabel'] ?? '') == '월 달력 열기', "'月' 의미 이름 $mon");
          for (final x in chips) {
            need(x['sylBreaks'] == 0 && x['didExceedMaxLines'] != true, '주간 칩 $x');
          }
          need((close['w'] as double) >= 48 && (close['h'] as double) >= 48, '닫기 누름 $close');
          final ci = close['icon'] as Map;
          need((ci['contrast'] as double) >= 3 && ci['fg'] == _hex(AppColors.textSecondary), '닫기 아이콘 $close');
          need((row['sheetSyl'] as List).isEmpty, '시트 끊김 ${row['sheetSyl']}');
          need(row['sheetInside'] == true, '시트가 화면 밖 ${lt(sheetR)}');
        }
        rows.add(row);
        _out('D293 ${jsonEncode(rows.last)}');
        Navigator.of(t.element(sheet)).pop();
        await frames(10);
        safe('닫힘');
        need(find.byType(BottomSheet).evaluate().isEmpty, '시트가 닫히지 않았다');
      }
      if (after) {
        need(rows.length == 3, '장면 수 ${rows.length}');
        need(overflow.isEmpty, 'overflow $overflow');
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(2);
      safe('END 전');
      _out('D293-END ${jsonEncode({'pump': nPump, 'png': nPng, 'tap': nTap, 'rows': rows.length, 'overflow': overflow})}');
    } finally {
      FlutterError.onError = prevOnError;
      debugPrint = prevDebugPrint;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 8)));
}
