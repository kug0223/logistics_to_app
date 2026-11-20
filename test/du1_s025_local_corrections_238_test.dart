// ignore_for_file: depend_on_referenced_packages
// [DU238 S025 연간 급여 탭 국소 교정 baseline/after] 감사237 §다음238.
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU238_RUN=1 이고 DU238_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   standalone(MaterialApp home: PayrollOverviewScreen(reads: …)) — 표준 shell·탭 gate 는 관측하지 않는다.
//   reader 는 PayrollOverviewReads 주입으로 기록한다(실제 Firebase·서버 채널 0). workerSummaries·personLabels·
//   repairSummary 는 부르면 즉시 실패하는 금지 대역이고 monthLedgerCounts 는 null(원장 경로만 — 실패 주입을 fallback 이 가리지 않게).
//   장면 5 × W360/B320 = phase 당 10 조건. 혼합 1년만 기존 '새로고침' tap 1(W/B 각 1)로 둘째 조회를 만든다(stale·확인 중).
//   SubAdmin 회복은 화면 진입 뒤 unknown → allowed(1) → allowed(중복) → denied → allowed 를 같은 인스턴스에 알린다(tap 0).
//   fixture 의 달 역할은 '이번 달 = 11월'(1–10 지난 달, 11 이번 달, 12 미래)에 고정이다 — 실행 날짜가 다르면 멈춘다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_overview_reads.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_overview_screen.dart';
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

const kBiz = 'biz-local-d238';
const kBizS = 'biz-local-d238-s';
const kOwner = 'owner-local-d238';
const kSub = 'sub-local-d238';
const kLongBizName = '송파 물류센터 평일 야간 상하차·분류 보조 전용 제2사업장 별관';
const kSubBizName = 'QA 물류센터 A';
const kFail = 'du238 local network failure';

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
  String? get effectiveBusinessId => null;
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

/// 급여만 가진 SubAdmin(유효 사업장 하나). 권한 판정 값은 시험이 정한 순서로만 바뀌고, 바꿀 때 한 번 알린다.
class _Sub extends UserProvider {
  _Sub(this._check);
  PermissionCheck _check;
  void push(PermissionCheck c) {
    _check = c;
    notifyListeners();
  }

  @override
  UserModel? get currentUser => UserModel(uid: kSub, username: 'sub', name: 'QA 서브', email: 's@test.local',
      role: UserRole.USER, subAdminBusinessIds: const [kBizS], createdAt: DateTime(2026, 1, 1));
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => true;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => _check != PermissionCheck.unknown;
  @override
  String? get effectiveBusinessId => kBizS;
  @override
  Map<String, String> get subAdminBusinessNames => const {kBizS: kSubBizName};
  @override
  bool can(bool Function(MemberPermissions p) check) => _check == PermissionCheck.allowed;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => _check == PermissionCheck.allowed;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => _check;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => _check;
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
  final phase = Platform.environment['DU238_PHASE'] ?? '';
  final run = Platform.environment['DU238_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  final now = DateTime.now();
  final year = now.year;
  String ym(int m) => '$year-${m.toString().padLeft(2, '0')}';

  final events = <String>[];
  final blocked = <String>[];
  final appErrors = <String>[];

  // ── fixture ──
  BusinessModel biz(String id, String name) => BusinessModel(id: id, name: name, ownerId: kOwner,
      businessNumber: '000-00-00000', address: '서울시 QA구 1', category: '물류', subCategory: '상하차', isApproved: true,
      createdAt: DateTime(2026, 10, 1));
  Map<String, dynamic> doc(int m, {required int payout, required int workers, required int confirmed}) => {
        'id': '${kBiz}_${ym(m)}', 'businessId': kBiz, 'yearMonth': ym(m), 'year': year, 'month': m,
        'totalPayout': payout, 'confirmedCount': confirmed, 'workerCount': workers, 'pendingCount': 0,
        'notTransferredCount': 0, 'workers': <String, dynamic>{},
        'updatedAt': {'_seconds': DateTime.utc(2026, 10, 1).millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0},
      };
  // 혼합 1년의 집계 문서: 1·3·4·5·9·10월.
  final mixedDocs = [
    doc(1, payout: 1850000, workers: 3, confirmed: 3),
    doc(3, payout: 1234567890, workers: 1234, confirmed: 9876),
    doc(4, payout: 2400000, workers: 4, confirmed: 4),
    doc(5, payout: 960000, workers: 2, confirmed: 2),
    doc(9, payout: 3000000, workers: 5, confirmed: 5),
    doc(10, payout: 98765432, workers: 321, confirmed: 1234),
  ];
  List<Map<String, dynamic>> items(int m, {int pending = 0, int confirmed = 0, int transferred = 0}) => [
        for (var i = 0; i < pending; i++)
          {'id': 'p${m}_$i', 'yearMonth': ym(m), 'wageStatus': 'pending', 'status': 'present', 'finalWage': 0, 'userId': 'w${i % 50}'},
        for (var i = 0; i < confirmed; i++)
          {'id': 'c${m}_$i', 'yearMonth': ym(m), 'wageStatus': 'confirmed', 'status': 'present', 'finalWage': 100000, 'userId': 'w${i % 50}'},
        for (var i = 0; i < transferred; i++)
          {'id': 't${m}_$i', 'yearMonth': ym(m), 'wageStatus': 'transferred', 'status': 'present', 'finalWage': 100000, 'userId': 'w${i % 50}'},
      ];
  FirebaseFunctionsException failure() => FirebaseFunctionsException(code: 'unavailable', message: kFail);

  var scene = '';
  final attCalls = <int, int>{};
  final hold = <int, Completer<void>>{};
  // 혼합 1년 원장 — 달마다 고정 역할. call = 이 장면에서 그 달을 몇 번째 읽는가.
  Future<({List<Map<String, dynamic>> items, bool limitReached})> mixedLedger(int m, int call) async {
    ({List<Map<String, dynamic>> items, bool limitReached}) ok(List<Map<String, dynamic>> x) => (items: x, limitReached: false);
    switch (m) {
      case 1: // 집계 문서 있음, 둘째 조회는 잡아 둔다 → '미이체 확인 중'
        if (call == 2) await hold.putIfAbsent(1, Completer<void>.new).future;
        return ok(items(1, confirmed: 2, transferred: 1));
      case 2: // 문서 없음, 첫 조회 0건, 둘째 조회는 잡아 둔다 → '확인 중'
        if (call == 2) await hold.putIfAbsent(2, Completer<void>.new).future;
        return ok(const []);
      case 3: // 긴 금액·천 단위 인원/건수, 미이체 3
        return ok(items(3, confirmed: 3, transferred: 9873));
      case 4: // 첫 조회 known(미이체 2), 둘째 조회 실패 → stale '이전 조회'
        if (call == 2) throw failure();
        return ok(items(4, confirmed: 2, transferred: 2));
      case 5: // 문서 있음, 매번 실패 → '미이체 확인 못함'
        throw failure();
      case 6: // 문서 없음, 매번 실패 → '확인 못함'
        throw failure();
      case 7: // 미확정만 있는 달(pending-only)
        return ok(items(7, pending: 2));
      case 9: // 모두 이체 — 미이체 줄 없음
        return ok(items(9, transferred: 5));
      case 10: // 미이체 1,234
        return ok(items(10, confirmed: 1234));
      default: // 8·11월: 0건
        return ok(const []);
    }
  }

  PayrollOverviewReads reads() => PayrollOverviewReads(
        businesses: ({required bool isSubAdmin, required String? effectiveBusinessId, required List<String> managedIds}) async {
          events.add('businesses ${_canon({'isSubAdmin': isSubAdmin, 'effectiveBusinessId': effectiveBusinessId, 'managedIds': managedIds})}');
          return switch (scene) {
            'nobiz' => <BusinessModel>[],
            'subadmin' || 'denied' => [biz(kBizS, kSubBizName)],
            _ => [biz(kBiz, kLongBizName)],
          };
        },
        payrollSummaries: ({required String businessId, required int year}) async {
          events.add('summaries ${_canon({'businessId': businessId, 'year': year})}');
          return scene == 'mixed' ? [for (final d in mixedDocs) Map<String, dynamic>.from(d)] : const [];
        },
        adminAttendances: ({required String businessId, required String yearMonthGte, required String yearMonthLte}) async {
          events.add('attendance ${_canon({'businessId': businessId, 'yearMonthGte': yearMonthGte, 'yearMonthLte': yearMonthLte})}');
          final m = int.parse(yearMonthGte.split('-')[1]);
          final call = attCalls.update(m, (v) => v + 1, ifAbsent: () => 1);
          if (scene == 'mixed') return mixedLedger(m, call);
          return (items: const <Map<String, dynamic>>[], limitReached: false);
        },
        workerSummaries: (id) async {
          blocked.add('workerSummaries $id');
          throw StateError('du238-blocked workerSummaries');
        },
        repairSummary: ({required String businessId, required String yearMonth}) async {
          blocked.add('repairSummary $businessId $yearMonth');
          throw StateError('du238-blocked repairSummary');
        },
        todayPaymentCount: (businessId) async {
          events.add('today ${_canon(businessId)}');
          return 0;
        },
        personLabels: ({required String businessId, required List<String> uids}) async {
          blocked.add('personLabels $businessId');
          throw StateError('du238-blocked personLabels');
        },
      );

  // ── 실행 전 고정 reader(정규형 multiset) ──
  String fBiz(bool sub, String? eff, List<String> ids) =>
      'businesses ${_canon({'isSubAdmin': sub, 'effectiveBusinessId': eff, 'managedIds': ids})}';
  String fSum(String b) => 'summaries ${_canon({'businessId': b, 'year': year})}';
  String fAtt(String b, int m) => 'attendance ${_canon({'businessId': b, 'yearMonthGte': ym(m), 'yearMonthLte': ym(m)})}';
  String fToday(String b) => 'today ${_canon(b)}';
  List<String> months(String b) => [for (var m = 1; m <= 11; m++) fAtt(b, m)];
  List<String> sorted(List<String> x) => [...x]..sort();
  final ownerSet = [fBiz(false, null, const [kBiz]), fSum(kBiz), fToday(kBiz), ...months(kBiz)];
  final subSet = [fBiz(true, kBizS, const []), fSum(kBizS), fToday(kBizS), ...months(kBizS)];
  final want = <String, List<String>>{
    'mixed-first': sorted(ownerSet),
    'mixed': sorted([...ownerSet, fSum(kBiz), ...months(kBiz)]),
    'empty': sorted(ownerSet),
    'subadmin-0': const [],
    'subadmin-1': sorted(subSet),
    'subadmin-2': sorted([...subSet, ...subSet]),
    'denied': const [],
    'nobiz': [fBiz(false, null, const [])],
  };
  String failLine(int m) => '⚠️ 월 원장 조회 실패(${ym(m)}): [firebase_functions/unavailable] $kFail';
  final wantErrors = <String, List<String>>{
    'mixed-first': sorted([failLine(5), failLine(6)]),
    'mixed': sorted([failLine(5), failLine(6), failLine(4), failLine(5), failLine(6)]),
  };

  testWidgets('D238 $phase', (t) async {
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
    // 감사237 §다음238 phase 한도: pump+mount ≤1400, tap ≤2(혼합 새로고침 W/B 각 1), drag ≤6, PNG ≤16.
    const maxFrames = 1400, maxTap = 2, maxDrag = 6, maxPng = 16;
    var cur = '(시작)';
    Map<String, int> counts() => {'pump': nPump, 'pumpWidget': nMount, 'tap': nTap, 'drag': nDrag, 'png': nPng};
    Never stop(String why) {
      _out('D238-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors, 'appErrors': appErrors, 'counts': counts(), 'events': events, 'blocked': blocked})}');
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
      need(blocked.isEmpty, '$at 금지 reader 호출: $blocked');
      final ex = t.takeException();
      need(errors.isEmpty && ex == null, '$at 예외/overflow: ${errors.take(3).toList()} / $ex');
      need(find.byType(BottomSheet, skipOffstage: false).evaluate().isEmpty, '$at 사업장 선택 시트가 떴다');
    }

    void match(String key, String at) {
      final got = sorted(events);
      need(jsonEncode(got) == jsonEncode(want[key]), '$at reader 정확값 불일치($key) got=$got');
      final gotErr = sorted([for (final m in appErrors) m.split(nl).first]);
      need(jsonEncode(gotErr) == jsonEncode(wantErrors[key] ?? const <String>[]), '$at 앱 오류 첫 줄 불일치($key) $gotErr');
      safe(at);
    }

    Finder rich(bool Function(String p) f, {Finder? within}) {
      final m = find.byWidgetPredicate((w) => w is RichText && f(TextLayout.plain(w.text.toPlainText())), skipOffstage: false);
      return within == null ? m : find.descendant(of: within, matching: m, skipOffstage: false);
    }

    Finder? firstOf(Finder f) {
      final els = f.evaluate().toList();
      if (els.isEmpty) return null;
      final e = els.first;
      return find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    }

    bool has(String s) => rich((p) => p == s).evaluate().isNotEmpty;
    double r1(double v) => double.parse(v.toStringAsFixed(1));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    bool inside(Rect r, Rect box) =>
        r.left >= box.left - 0.5 && r.top >= box.top - 0.5 && r.right <= box.right + 0.5 && r.bottom <= box.bottom + 0.5;

    // 실제 배경 — 조상의 칠(ColoredBox·DecoratedBox·Material·Scaffold)을 불투명한 것까지 모아 합성한다.
    ({Color color, List<String> layers}) bgOf(Element e) {
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
      return (color: out, layers: [for (final c in layers) '${_hex(c)}@${c.a.toStringAsFixed(2)}']);
    }

    final key = GlobalKey();
    final startKstDate = _kst(DateTime.now()).substring(0, 10);
    String? prevKey;

    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        for (final sc in const ['mixed', 'empty', 'subadmin', 'denied', 'nobiz']) {
          cur = '${c.id} $sc';
          if (nMount > 0) {
            nMount++;
            budget();
            await t.pumpWidget(const SizedBox.shrink());
            await frames(1);
            match(prevKey!, '$prevKey 장면 종료(unmount 직후)');
          }
          // 날짜 guard — 달 역할(11월 = 이번 달)과 시작·끝 같은 KST 날짜.
          final n0 = DateTime.now();
          final k0 = n0.toUtc().add(const Duration(hours: 9));
          need(n0.month == 11 && k0.month == 11 && n0.day == k0.day, '달 역할 fixture 는 이번 달 11월(로컬=KST)에서만 유효: $n0 / ${_kst(n0)}');
          need(_kst(n0).substring(0, 10) == startKstDate, 'KST 날짜가 실행 중 바뀜');
          scene = sc;
          events.clear();
          blocked.clear();
          appErrors.clear();
          attCalls.clear();
          hold.clear();
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          final UserProvider provider = switch (sc) {
            'nobiz' => _Owner(const []),
            'subadmin' => _Sub(PermissionCheck.unknown),
            'denied' => _Sub(PermissionCheck.denied),
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
                home: PayrollOverviewScreen(reads: reads()),
              ),
            ),
          ));
          await frames(30);

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

          Finder? scrollF() {
            final f = find.descendant(of: find.byType(PayrollOverviewScreen), matching: find.byType(Scrollable));
            return f.evaluate().isEmpty ? null : firstOf(f);
          }

          Finder? cardOf(int m) {
            final label = firstOf(rich((p) => p == '$m월'));
            if (label == null) return null;
            return firstOf(find.ancestor(
                of: label,
                matching: find.byWidgetPredicate((w) =>
                    w is DecoratedBox &&
                    w.decoration is BoxDecoration &&
                    (w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(12))));
          }

          Finder? inCard(int m, bool Function(String p) f) {
            final card = cardOf(m);
            return card == null ? null : firstOf(rich(f, within: card));
          }

          // 그 달 카드가 지어져 있으면(화면·캐시 범위) 그 문구가 있어야 한다. 아직 안 지어진 카드는 drag 뒤에 잰다.
          bool cardSays(int m, String s) {
            final card = cardOf(m);
            return card == null || rich((p) => p == s, within: card).evaluate().isNotEmpty;
          }

          bool gridShown() {
            final lv = find.descendant(of: find.byType(PayrollOverviewScreen), matching: find.byType(ListView));
            if (lv.evaluate().isEmpty) return false;
            final d = t.widget<ListView>(lv.first).childrenDelegate;
            return d is SliverChildBuilderDelegate && d.childCount == 6 && has('1월') && has('2월');
          }

          Map<String, Object?> textInfo(String name, Finder? f) {
            if (f == null) return {'name': name, 'present': false};
            final rp = t.renderObject<RenderParagraph>(f);
            final r = t.getRect(f);
            final plain = TextLayout.plain(rp.text.toPlainText());
            final display = rp.text.toPlainText();
            final byLine = <int, StringBuffer>{};
            final lineBoxes = <int, Rect>{};
            for (var i = 0; i < display.length; i++) {
              final bs = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
              if (bs.isEmpty) continue;
              final k = bs.first.top.round();
              byLine.putIfAbsent(k, () => StringBuffer()).write(display[i]);
              final box = bs.first.toRect().shift(r.topLeft);
              lineBoxes.update(k, (v) => v.expandToInclude(box), ifAbsent: () => box);
            }
            final keys = byLine.keys.toList()..sort();
            Color? fg = rp.text.style?.color;
            if (rp.text is TextSpan) {
              for (final ch in (rp.text as TextSpan).children ?? const <InlineSpan>[]) {
                fg = ch.style?.color ?? fg;
              }
            }
            final el = f.evaluate().first;
            final bg = bgOf(el);
            final textAnc = find.ancestor(of: f, matching: find.byType(Text));
            final sem = textAnc.evaluate().isEmpty ? null : t.widget<Text>(textAnc.first).semanticsLabel;
            final sf = scrollF();
            final vp = sf == null ? null : t.getRect(sf);
            return {
              'name': name, 'present': true, 'plain': plain, 'semanticsLabel': sem, 'rect': lt(r), 'inScreen': inside(r, screen),
              'inViewport': vp == null ? null : inside(r, vp), 'maxLines': rp.maxLines, 'didExceedMaxLines': rp.didExceedMaxLines,
              'lines': [for (final k in keys) TextLayout.plain(byLine[k]!.toString())],
              'lineBoxes': [for (final k in keys) lt(lineBoxes[k]!)],
              'fontSize': rp.text.style?.fontSize, 'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg.color), 'bgLayers': bg.layers,
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg.color).toStringAsFixed(2)),
            };
          }

          Map<String, Object?> recv(String name, Finder? f) {
            if (f == null) return {'name': name, 'present': false};
            final r = t.getRect(f);
            final ro = t.renderObject(f);
            bool hitsAt(Offset p) {
              final h = HitTestResult();
              WidgetsBinding.instance.hitTestInView(h, p, t.view.viewId);
              return h.path.any((e) => e.target == ro);
            }

            final inner = r.deflate(2);
            return {
              'name': name, 'present': true, 'rect': lt(r), 'w': r1(r.width), 'h': r1(r.height), 'centerHit': hitsAt(r.center),
              'edgeHits': [inner.topLeft, inner.topRight, inner.bottomLeft, inner.bottomRight].every(hitsAt),
              'ge48': r.width >= 48 - 0.01 && r.height >= 48 - 0.01, 'inScreen': inside(r, screen),
            };
          }

          final nameText = sc == 'subadmin' || sc == 'denied' ? kSubBizName : kLongBizName;
          Map<String, Object?> nameInfo() => textInfo('D5 사업장 이름', firstOf(rich((p) => p == nameText)));
          final states = <Map<String, Object?>>[];
          final shot = 'D238-$phase-${c.id}_$sc';
          Future<void> capture(String suffix, Map<String, Object?> extra) async {
            nPng++;
            budget();
            await vqCapture(t, key, '$shot$suffix', conditions: {
              'phase': phase, 'scene': sc, 'state': suffix, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0,
              'textScaleFactor(기기)': c.s, 'locale': locale, 'theme': 'RoleTheme.businessAdminTheme',
              'clock': '미주입(now=${_kst(DateTime.now())})', ...extra,
            });
          }

          // after 성공조건 — 지정 문단의 실제 글자색·배경·대비. baseline 은 같은 값을 결함값으로 기록만 한다.
          void wantFg(List<Map<String, Object?>> texts, Map<String, String> fgs) {
            if (!after) return;
            for (final e in fgs.entries) {
              final x = texts.firstWhere((m) => m['name'] == e.key, orElse: () => {'name': e.key, 'present': false});
              final cst = x['contrast'];
              need(x['present'] == true && x['fg'] == e.value && cst is double && cst >= 4.5, '읽기색 ${e.key} $x');
            }
          }

          void wantName(bool shown, String at) {
            if (!after) return;
            final n = nameInfo();
            if (!shown) {
              need(n['present'] == false, '$at 이름이 보이면 안 되는 상태에 이름이 있다');
              return;
            }
            final cst = n['contrast'];
            need(n['present'] == true && n['fg'] == '#60646F' && cst is double && cst >= 4.5, '$at D5 이름 $n');
            need(n['maxLines'] == null && n['didExceedMaxLines'] == false && n['inScreen'] == true, '$at D5 이름 잘림·화면 밖 $n');
            need(n['semanticsLabel'] == nameText, '$at D5 이름 semantics $n');
            final lines = (n['lines']! as List).cast<String>();
            need(lines.map((l) => l.trim()).join(' ') == nameText, '$at D5 이름 낱말 안 줄바꿈 $lines');
          }

          var r1Result = '';
          final reach = <String, int>{};
          final details = <Map<String, Object?>>[];

          if (sc == 'mixed') {
            // ── 첫 조회 ──
            need(gridShown(), '첫 조회 뒤 연간 격자 없음');
            match('mixed-first', '첫 조회');
            need(cardSays(5, '미이체 확인 못함') && cardSays(6, '확인 못함') && !has('미이체 2 · 이전 조회'), '첫 조회 상태 문구(5·6월 확인 못함)');
            // ── 둘째 조회: 같은 사업장·연도의 기존 새로고침 1 tap ──
            nTap++;
            budget();
            await t.tap(find.byTooltip('새로고침'));
            await frames(12);
            need(gridShown(), '새로고침 뒤 연간 격자 없음');
            need(hold.length == 2, '1·2월 둘째 조회가 잡혀 있지 않다 ${hold.keys}');
            match('mixed', '확인 중 캡처 전');
            final lTexts = [
              nameInfo(),
              textInfo('D2 1월 미이체 확인 중', inCard(1, (p) => p == '미이체 확인 중')),
              textInfo('D1 2월 확인 중', inCard(2, (p) => p == '확인 중')),
              textInfo('D1 2월 라벨', inCard(2, (p) => p == '2월')),
              textInfo('3월 금액', inCard(3, (p) => p.startsWith('1,234,567,890'))),
            ];
            need(lTexts[1]['present'] == true && lTexts[2]['present'] == true, '확인 중 문구 누락 $lTexts');
            wantFg(lTexts, {'D2 1월 미이체 확인 중': '#60646F', 'D1 2월 확인 중': '#60646F', 'D1 2월 라벨': '#686C77'});
            wantName(true, '확인 중');
            states.add({'state': 'L', 'texts': lTexts});
            await capture('_L', {'fixture': '새로고침 둘째 조회 — 1·2월 잡아 둠'});
            // ── 잡아 둔 두 달을 풀어 끝낸다 ──
            for (final h in hold.values) {
              h.complete();
            }
            await frames(10);
            match('mixed', '정착 캡처 전');
            need(cardOf(4) != null && cardSays(4, '미이체 2 · 이전 조회') && cardSays(5, '미이체 확인 못함') && cardSays(6, '확인 못함') &&
                    !has('확인 중') && !has('미이체 확인 중'),
                '정착 상태 문구(4월 이전 조회·5·6월 확인 못함)');
            final banner = '4월·5월·6월 미이체를 확인하지 못했어요.';
            need(has(banner), '미확인 배너 없음');
            List<Map<String, Object?>> sTexts() => [
                  nameInfo(),
                  textInfo('3월 금액', inCard(3, (p) => p.startsWith('1,234,567,890'))),
                  textInfo('D2 3월 명·건', inCard(3, (p) => p == '1,234명 · 9,876건')),
                  textInfo('D3 3월 미이체 3', inCard(3, (p) => p == '미이체 3')),
                  textInfo('D2 4월 이전 조회', inCard(4, (p) => p == '미이체 2 · 이전 조회')),
                  textInfo('D2 5월 미이체 확인 못함', inCard(5, (p) => p == '미이체 확인 못함')),
                  textInfo('D1 6월 확인 못함', inCard(6, (p) => p == '확인 못함')),
                  textInfo('D1 6월 라벨', inCard(6, (p) => p == '6월')),
                  textInfo('7월 금액(미확정만)', inCard(7, (p) => p == '-')),
                  textInfo('D2 7월 명·건(미확정만)', inCard(7, (p) => p == '0명 · 0건')),
                  textInfo('D1 8월 데이터 없음', inCard(8, (p) => p == '데이터 없음')),
                  textInfo('D1 8월 라벨', inCard(8, (p) => p == '8월')),
                  textInfo('D3 10월 미이체 1,234', inCard(10, (p) => p == '미이체 1,234')),
                  textInfo('D1 11월 데이터 없음(이번 달)', inCard(11, (p) => p == '데이터 없음')),
                  textInfo('D1 11월 라벨(이번 달)', inCard(11, (p) => p == '11월')),
                  textInfo('12월 라벨(미래)', inCard(12, (p) => p == '12월')),
                  textInfo('미확인 배너 문구', firstOf(rich((p) => p == banner))),
                ];
            final s0 = sTexts();
            final retry = recv('미확인 배너 다시 확인',
                firstOf(find.ancestor(of: rich((p) => p == '다시 확인'), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))));
            final fg0 = {
              'D2 3월 명·건': '#60646F', 'D3 3월 미이체 3': '#B42318', 'D2 4월 이전 조회': '#60646F',
              'D2 5월 미이체 확인 못함': '#60646F', 'D1 6월 확인 못함': '#60646F', 'D1 6월 라벨': '#686C77',
              'D2 7월 명·건(미확정만)': '#60646F', 'D1 8월 데이터 없음': '#60646F', 'D1 8월 라벨': '#686C77',
            };
            // 첫 화면에서 지어진 문단만 판정한다(아래 행은 drag 뒤에 다시 잰다).
            wantFg(s0, {for (final e in fg0.entries) if (s0.any((x) => x['name'] == e.key && x['present'] == true)) e.key: e.value});
            wantName(true, '정착');
            states.add({'state': 'S', 'texts': s0, 'retry': retry});
            await capture('_S', {'fixture': '둘째 조회 정착 — 4월 stale·5·6월 unknown'});

            // ── 지정 읽기 도달(공개 drag) ──
            final targets = c.id == 'B320'
                ? <String, Finder Function()>{
                    '3월 금액 전문': () => inCard(3, (p) => p.startsWith('1,234,567,890')) ?? rich((p) => false),
                    '3월 미이체 3': () => inCard(3, (p) => p == '미이체 3') ?? rich((p) => false),
                    '4월 이전 조회': () => inCard(4, (p) => p == '미이체 2 · 이전 조회') ?? rich((p) => false),
                    '5월 미이체 확인 못함': () => inCard(5, (p) => p == '미이체 확인 못함') ?? rich((p) => false),
                    '6월 확인 못함': () => inCard(6, (p) => p == '확인 못함') ?? rich((p) => false),
                  }
                : <String, Finder Function()>{
                    '11월 데이터 없음': () => inCard(11, (p) => p == '데이터 없음') ?? rich((p) => false),
                    '12월 라벨': () => inCard(12, (p) => p == '12월') ?? rich((p) => false),
                  };
            final maxK = c.id == 'B320' ? 2 : 1;
            void look(int k) {
              final sf = scrollF();
              if (sf == null) return;
              final vp = t.getRect(sf);
              for (final e in targets.entries) {
                if (reach.containsKey(e.key)) continue;
                final f = e.value();
                if (f.evaluate().isEmpty) continue;
                final r = t.getRect(f.first);
                if (inside(r, vp) && inside(r, screen)) reach[e.key] = k;
              }
            }

            look(0);
            for (var k = 1; k <= maxK; k++) {
              if (reach.length == targets.length) break;
              final sf = scrollF();
              if (sf == null) break;
              final vp = t.getRect(sf);
              final pos = t.state<ScrollableState>(sf).position;
              if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
              final from = Offset(vp.left + 24, vp.bottom - 12);
              // 아직 못 본 대상 중 가장 아래(같은 행)를 viewport 안 8px 로 — 끌기 시작 slop 보정 +24.
              var wantD = vp.height * 0.7;
              final misses = [for (final e in targets.entries) if (!reach.containsKey(e.key)) e.value()]
                  .where((f) => f.evaluate().isNotEmpty)
                  .toList();
              if (misses.isNotEmpty) {
                final firstMiss = misses.first;
                final rowTop = t.getRect(firstMiss.first).top;
                var bottom = t.getRect(firstMiss.first).bottom;
                for (final f in misses) {
                  final r = t.getRect(f.first);
                  if ((r.top - rowTop).abs() < 260 && r.bottom > bottom) bottom = r.bottom;
                }
                wantD = bottom - (vp.bottom - 8) + 24;
              }
              final d = wantD < from.dy - 12 ? wantD : from.dy - 12;
              if (d <= 0) break;
              nDrag++;
              budget();
              final px0 = pos.pixels;
              await t.dragFrom(from, Offset(0, -d));
              await frames(6);
              match('mixed', '상세 drag 뒤');
              final px1 = t.state<ScrollableState>(sf).position.pixels;
              look(k);
              final dTexts = sTexts();
              wantFg(dTexts, {for (final e in fg0.entries) if (dTexts.any((x) => x['name'] == e.key && x['present'] == true)) e.key: e.value});
              if (after) {
                for (final n in const ['D1 11월 데이터 없음(이번 달)', 'D1 11월 라벨(이번 달)']) {
                  final x = dTexts.firstWhere((m) => m['name'] == n);
                  if (x['present'] == true) {
                    final cst = x['contrast'];
                    need(x['fg'] == (n.contains('라벨') ? '#686C77' : '#60646F') && cst is double && cst >= 4.5, '읽기색 $n $x');
                  }
                }
              }
              details.add({'drag': k, 'request': r1(d), 'pixels': [r1(px0), r1(px1)], 'texts': dTexts});
              if (c.id == 'B320') await capture('_S_d$k', {'drag': k});
            }
            // 보존: 미래 달은 비활성 grey400·본문 없음(양 phase).
            final fut = inCard(12, (p) => p == '12월');
            if (fut != null) {
              need(textInfo('12월', fut)['fg'] == '#BDBDBD', '12월(미래) 라벨 색이 바뀌었다');
              final card12 = cardOf(12)!;
              need(rich((p) => p == '데이터 없음' || p == '확인 중' || p == '확인 못함', within: card12).evaluate().isEmpty, '미래 달에 상태 문구');
            }
            match('mixed', '장면 끝');
            prevKey = 'mixed';
          } else if (sc == 'empty') {
            need(gridShown(), '빈 1년 격자 없음');
            match('empty', '캡처 전');
            final eTexts = [
              nameInfo(),
              textInfo('D1 1월 데이터 없음', inCard(1, (p) => p == '데이터 없음')),
              textInfo('D1 1월 라벨', inCard(1, (p) => p == '1월')),
              textInfo('2026년', firstOf(rich((p) => p == '$year년'))),
            ];
            need(eTexts[1]['present'] == true && !has('확인 못함') && !has('미이체 확인 못함'), '빈 1년: 0 이 unknown 이 아니다');
            wantFg(eTexts, {'D1 1월 데이터 없음': '#60646F', 'D1 1월 라벨': '#686C77'});
            wantName(true, '빈 1년');
            states.add({'state': 'E', 'texts': eTexts});
            await capture('', {'fixture': '사업장 1·집계 없음·원장 0'});
            prevKey = 'empty';
          } else if (sc == 'subadmin') {
            final p = provider as _Sub;
            // ── 진입: unknown ──
            match('subadmin-0', 'unknown 진입');
            need(has('권한 정보를 확인하지 못했습니다'), 'unknown 안내 없음');
            final uTexts = [nameInfo(), textInfo('D4 확인 실패 부제', firstOf(rich((x) => x == '잠시 후 다시 시도해주세요.')))];
            wantFg(uTexts, {'D4 확인 실패 부제': '#60646F'});
            wantName(false, 'unknown');
            states.add({'state': 'U', 'texts': uTexts});
            await capture('_U', {'fixture': 'SubAdmin 진입 unknown'});
            // ── 첫 allowed(중간 unknown 알림 없음) ──
            p.push(PermissionCheck.allowed);
            await frames(30);
            final stuck = has('데이터를 불러오지 못했습니다') && events.isEmpty;
            final normal = gridShown() && jsonEncode(sorted(events)) == jsonEncode(want['subadmin-1']);
            if (after) {
              need(normal, 'after 첫 allowed 에서 회복하지 않음 events=${sorted(events)}');
              r1Result = 'recovered';
            } else if (stuck) {
              r1Result = 'repro';
            } else if (normal) {
              r1Result = 'nonrepro';
            } else {
              stop('baseline 첫 allowed 결과가 사전 두 결과 어디에도 속하지 않음 events=${sorted(events)}');
            }
            match(r1Result == 'repro' ? 'subadmin-0' : 'subadmin-1', '첫 allowed');
            final aTexts = [nameInfo(), textInfo('오류 제목', firstOf(rich((x) => x == '데이터를 불러오지 못했습니다')))];
            if (r1Result != 'repro') wantName(true, '첫 allowed');
            states.add({'state': 'A1', 'r1': r1Result, 'texts': aTexts});
            await capture('_A1', {'fixture': 'unknown → allowed 1회', 'r1': r1Result});
            // ── 같은 allowed 중복 ──
            final before = sorted(events);
            p.push(PermissionCheck.allowed);
            await frames(20);
            need(jsonEncode(sorted(events)) == jsonEncode(before), '중복 allowed 추가 읽기');
            safe('중복 allowed');
            // ── 거부 → 본문 차단 ──
            p.push(PermissionCheck.denied);
            await frames(10);
            need(has('접근 권한이 없습니다') && !gridShown() && jsonEncode(sorted(events)) == jsonEncode(before), '거부 알림 뒤 본문 차단·읽기 0');
            wantName(false, '거부 알림');
            safe('거부 알림');
            // ── 다시 allowed → 기존 재초기화 ──
            p.push(PermissionCheck.allowed);
            await frames(30);
            final finalKey = r1Result == 'repro' ? 'subadmin-1' : 'subadmin-2';
            need(gridShown(), '거부 뒤 허용에서 회복하지 않음');
            match(finalKey, '거부 뒤 허용');
            wantName(true, '거부 뒤 허용');
            states.add({'state': 'R', 'texts': [nameInfo()]});
            prevKey = finalKey;
          } else if (sc == 'denied') {
            match('denied', '캡처 전');
            need(has('접근 권한이 없습니다'), '거부 안내 없음');
            final dTexts = [nameInfo(), textInfo('D4 권한 없음 부제', firstOf(rich((x) => x == '급여 관리 권한이 있는 관리자에게 문의하세요.')))];
            wantFg(dTexts, {'D4 권한 없음 부제': '#60646F'});
            wantName(false, '거부');
            states.add({'state': 'D', 'texts': dTexts});
            await capture('', {'fixture': 'SubAdmin cold-entry denied'});
            prevKey = 'denied';
          } else {
            match('nobiz', '캡처 전');
            need(has('아직 급여를 관리할 사업장이 없어요') && has('준비 단계 보기'), '사업장0 안내 없음');
            final nTexts = [nameInfo(), textInfo('D4 사업장0 부제', firstOf(rich((x) => x == '사업장을 등록하면 근무·급여 관리를 시작할 수 있어요.')))];
            wantFg(nTexts, {'D4 사업장0 부제': '#60646F'});
            wantName(false, '사업장0');
            states.add({'state': 'N', 'texts': nTexts});
            await capture('', {'fixture': 'allowed·businesses=[]'});
            prevKey = 'nobiz';
          }
          _out('D238 ${jsonEncode({
                'phase': phase, 'cond': c.id, 'scene': sc, 'env': env, 'events': sorted(events), 'appErrors': appErrors,
                'r1': r1Result, 'states': states, 'reach': reach, 'details': details, 'counts': counts(), 'kst': _kst(DateTime.now()),
              })}');
        }
      }
      nMount++;
      budget();
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      match(prevKey!, 'END 전');
      need(_kst(DateTime.now()).substring(0, 10) == startKstDate, 'KST 날짜가 실행 중 바뀜');
      _out('D238-END ${jsonEncode({'counts': counts(), 'startKstDate': startKstDate, 'endKst': _kst(DateTime.now())})}');
    } finally {
      for (final h in hold.values) {
        if (!h.isCompleted) h.complete();
      }
      FlutterError.onError = prevOnError;
      debugPrint = prevDebugPrint;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
