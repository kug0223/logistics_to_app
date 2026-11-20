// ignore_for_file: depend_on_referenced_packages
// [DU305 DU-O001-USABILITY-PREP-305] 당일명단 O001 묶음 — 선택 직후 두 창 맞춤(G)·가독성·행동색, before/after 같은 순서.
//   근거: requests/DU_implementation_305.md §1–4, reports/DU_audit_305_r2.md §3–4(다섯 정정), reports/DU_preparation_305_r1.md §5,
//         reports/DU_preparation_305_r2.md §3–6. production 편집 0(시험은 관측만, 새 seam·계측 0).
//   DU305_RUN=1, DU305_PHASE=before|after, DU305_DAY=2026-11-13(실행 허용일 KST, 다른 날이면 실행하지 않는다) 일 때만 실행(기본 skip).
//   두 phase 가 같은 동작 순서를 탄다: BASE4 → LONG2 → ROUTE2 → EDGE2. before = 원 host, after = 정확 후보 host.
//   SEL·END·S2–S5·S4b·S-COLOR 는 after 단언이고, before 는 같은 대상·순서의 기록만 남긴다(기존 유효성·guard·동작 단언은 두 phase 유지).
//   실제 tap/drag/enterText 만 쓴다. 값 주입·강제 tap·Navigator 직접 호출·pumpAndSettle·scrollUntilVisible·ensureVisible·jumpTo 0.
//   오류는 mount~teardown 연속 수집하고 매 pump·행동 뒤 분류한다. 허용 오류는 없다(S6).
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/foundation.dart' show DiagnosticsTreeStyle, TextTreeRenderer, shortHash;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/attendance_reads.dart';
import 'package:ALfit/screens/business_admin/dialogs/attendance_status_dialog.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/services/firestore_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/common/app_checkbox.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';
import 'package:ALfit/widgets/pickers/icon_picker_dialog.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

/// 초기화용 platform 대역(Firebase core). 업무 호출 허용이 아니다.
class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

/// 네트워크 접근 guard(HttpClient 생성 계수·차단).
class _NoNet extends HttpOverrides {
  int created = 0;
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    created++;
    throw StateError('DU305 network guard');
  }
}

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

const _kDay = '2026-11-13'; // 실행 허용일(요청 §1). 다른 날이면 skip 이고 자동 이월하지 않는다.
const _biz = 'biz303'; // BASE·LONG 은 DU303/DU304 fixture 를 그대로 쓴다
const _fsBase = 'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
const _fsOps = [
  'aggregateQuery', 'clearPersistence', 'disableNetwork', 'documentReferenceDelete', 'documentReferenceGet',
  'documentReferenceSet', 'documentReferenceSnapshot', 'documentReferenceUpdate', 'enableNetwork', 'loadBundle',
  'namedQueryGet', 'persistenceCacheIndexManagerRequest', 'queryGet', 'querySnapshot', 'setIndexConfiguration',
  'setLoggingEnabled', 'snapshotsInSyncSetup', 'terminate', 'transactionCreate', 'transactionGet',
  'transactionStoreResult', 'waitForPendingWrites', 'writeBatchCommit',
];
const _fnBase = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi';
const _fnOps = ['call', 'registerEventChannel'];
const _fnLegacy = 'plugins.flutter.io/firebase_functions';

const _kTol = 0.01;
const _kEps = 1e-6;
const _kTopShare = 0.5; // host 상단 상한 비율(DU304 수용 host, 두 phase 같다)
// phase 동적 상한 C(요청 §3 고정표) — (pump, mount, tap+dispatch, drag, route 열기, text, PNG)
const _kC = (pump: 686, mount: 24, tap: 45, drag: 110, route: 5, text: 3, png: 12);
const _kPng = 10; // phase 정확 PNG 수(BASE4 select · LONG2×select/listEnd · EDGE2 layout)
const _kRoute = 4; // phase 정확 route 열기 수(hostOpen 2 + confirmOpen 2)

// S1 W 보존 기준(_kPrev) — DU304 R1T 원로그(같은 host = 305 before, repair/r1/test.stdout.txt D304-HOST)
const _kPrevHost = <String, ({double h, double t, double top, double list})>{
  'W360_IN|load': (h: 569.2, t: 239.9, top: 239.9, list: 329.30000000000007),
  'W360_IN|tab': (h: 569.2, t: 234.49999999999997, top: 234.49999999999997, list: 334.70000000000005),
  'W360_OUT|load': (h: 569.2, t: 239.9, top: 239.9, list: 329.30000000000007),
  'W360_OUT|tab': (h: 569.2, t: 234.49999999999997, top: 234.49999999999997, list: 334.70000000000005),
  'W360_L|load': (h: 569.2, t: 289.5, top: 284.6, list: 284.6),
  'W360_L|tab': (h: 569.2, t: 255.1, top: 255.1, list: 314.1),
};
// S1 W 보존 기준 — R1T D304-VIS 의 선택 전 상태 대상 rect(cond|stage|what 첫 기록), ±0.5
const _kPrevVis = <String, List<double>>{
  'W360_IN|tab|정상 탭': [125.82002868652343, 111.4, 149.7400421142578, 130.4],
  'W360_IN|select|전체': [34.0, 214.30000000000004, 83.62001342773438, 234.10000000000005],
  'W360_OUT|tab|정상 탭': [125.82002868652343, 111.4, 149.7400421142578, 130.4],
  'W360_OUT|select|전체': [34.0, 214.30000000000004, 83.62001342773438, 234.10000000000005],
  'W360_L|review|칩 미출근 1건': [42.2, 269.30000000000007, 98.2999755859375, 286.30000000000007],
  'W360_L|review|칩 퇴근미기록 1건': [120.09997558593751, 269.30000000000007, 198.77993774414062, 286.30000000000007],
  'W360_L|review|칩 미출근 1건(tap 직전)': [42.2, 269.30000000000007, 98.2999755859375, 286.30000000000007],
  'W360_L|tab|정상 탭': [125.82002868652343, 111.4, 149.7400421142578, 130.4],
  'W360_L|select|전체': [34.0, 234.90000000000003, 83.62001342773438, 254.70000000000005],
};

final _timeRe = RegExp(r'^[0-9]{2}:[0-9]{2} ~ [0-9]{2}:[0-9]{2}$');
final _badgeRe = RegExp(r'^출근 [0-9]+/[0-9]+$');
const _sortLabels = {'상태순', '배지순', '이름순'};

Map<String, dynamic> _ts(DateTime d) => {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

void main() {
  final phase = Platform.environment['DU305_PHASE'] ?? '';
  final dayArg = Platform.environment['DU305_DAY'] ?? '';
  final run = Platform.environment['DU305_RUN'] == '1' && (phase == 'before' || phase == 'after') && dayArg == _kDay;
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    if (!run) return;
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('D305 $phase', (t) async {
    // ── 실행일 pin: 허용일 하나로 고정한다(이후 today 재계산으로 바꾸지 않는다) ──
    final day = DateTime(2026, 11, 13);
    final dayKey = FormatHelper.kstDayKeyOfCivil(day);
    DateTime kstNow() => DateTime.now().toUtc().add(const Duration(hours: 9));

    final sem = t.ensureSemantics(); // S4/S4b 버튼 semantics label 관측(행동 아님)
    await t.runAsync(vqLoadFonts);
    SharedPreferences.setMockInitialValues({}); // 초기화용 platform 대역
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final prevHttp = HttpOverrides.current;
    final net = _NoNet();
    HttpOverrides.global = net;

    // 업무 채널 guard(차단·계수)
    final biz = <String, int>{};
    final m = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final op in _fsOps) {
      m.setMockMessageHandler('$_fsBase.$op', (msg) async {
        biz['fs.$op'] = (biz['fs.$op'] ?? 0) + 1;
        return const StandardMessageCodec().encodeMessage(<Object?>['du305-blocked', 'firestore $op 차단', null]);
      });
    }
    for (final op in _fnOps) {
      m.setMockMessageHandler('$_fnBase.$op', (msg) async {
        biz['fn.$op'] = (biz['fn.$op'] ?? 0) + 1;
        return const StandardMessageCodec().encodeMessage(<Object?>['du305-blocked', 'functions $op 차단', null]);
      });
    }
    m.setMockMethodCallHandler(const MethodChannel(_fnLegacy), (call) async {
      biz['fn.legacy.${call.method}'] = (biz['fn.legacy.${call.method}'] ?? 0) + 1;
      throw PlatformException(code: 'du305-blocked', message: 'functions legacy ${call.method} 차단');
    });

    // 실행량(phase 동적 상한 C — 어느 계수든 넘는 순간 중단). enterText 안의 showKeyboard pump·idle 은 nPump 에 들지 않는다(text 1회).
    //   실패 정리(finally, 실패 때만): mount ≤1·pump ≤2 를 따로 센다(F, 원 실패를 덮지 않으려고 중단 검사를 하지 않는다).
    var nPump = 0, nMount = 0, nTap = 0, nDrag = 0, nHostOpen = 0, nConfirmOpen = 0, nText = 0, nPng = 0;
    Map<String, Object?> counts() => {'phase': phase, 'pump': nPump, 'mount': nMount, 'tap': nTap, 'drag': nDrag,
      'route': nHostOpen + nConfirmOpen, 'hostOpen': nHostOpen, 'confirmOpen': nConfirmOpen, 'text': nText, 'png': nPng};

    var cond = '-';
    var stage = 'start';
    var scen = '-';
    var isB = false;
    final errors = <({String cond, String stage, int pump, String first, String full})>[];
    FlutterError.onError = (d) => errors.add((
          cond: cond,
          stage: stage,
          pump: nPump,
          first: d.exceptionAsString().split(nl).first,
          full: TextTreeRenderer(wrapWidth: 400).render(d.toDiagnosticsNode(style: DiagnosticsTreeStyle.error)).trimRight(),
        ));
    final afterFreeze = <String>[];
    final errLog = <Map<String, Object?>>[];
    final visited = <String>[];
    final prevSeen = <String>{};
    var live = false; // 화면이 mount 돼 있다(teardown 의 SizedBox mount 뒤 false) — 실패 정리 판단용
    var completed = false; // 모든 단계와 최종 단언을 통과했다

    Never stop(String why) {
      _out('D305-STOP ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'stage': stage, 'why': why,
        'pendingErrors': errors.map((e) => '${e.cond}/${e.stage}#${e.pump}: ${e.first}').toList(), 'counts': counts(),
        'http': net.created, 'business': biz, 'readsAfterFreeze': afterFreeze})}');
      for (final e in errors) {
        _out('D305-STOPERR ${jsonEncode({'cond': e.cond, 'stage': e.stage, 'pump': e.pump, 'full': e.full})}');
      }
      fail('$phase/$scen/$cond/$stage: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    void budget() {
      final ok = nPump <= _kC.pump && nMount <= _kC.mount && nTap <= _kC.tap && nDrag <= _kC.drag &&
          nHostOpen + nConfirmOpen <= _kC.route && nText <= _kC.text && nPng <= _kC.png;
      need(ok, '한도 C 초과 ${counts()}');
    }

    void clockGuard(String where) {
      final k = kstNow();
      final min = k.hour * 60 + k.minute;
      need(FormatHelper.toKstDate(DateTime.now()) == dayKey, '$where 실행일 이탈 kst=$k pin=$dayArg');
      need(min >= 8 * 60 && min < 21 * 60 + 30, '$where 실행 시각 구간 이탈 kst=$k');
    }

    Finder fe(Element e) => find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    String plainOf(Element e) => TextLayout.plain((e.widget as RichText).text.toPlainText());
    Finder richExact(String s, {Finder? within}) => within == null
        ? find.byWidgetPredicate((w) => w is RichText && TextLayout.plain(w.text.toPlainText()) == s)
        : find.descendant(of: within, matching: find.byWidgetPredicate((w) => w is RichText && TextLayout.plain(w.text.toPlainText()) == s));
    List<double> rectL(Rect r) => [r.left, r.top, r.right, r.bottom];
    bool inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;
    bool near(double a, double b, double tol) => (a - b).abs() <= tol;
    Rect boxRect(RenderBox b) => MatrixUtils.transformRect(b.getTransformTo(null), Offset.zero & b.size);

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

    Map<String, Object?> flexInfo(RenderFlex rf) {
      final kids = <double>[];
      var ch = rf.firstChild;
      while (ch != null) {
        kids.add(rf.direction == Axis.horizontal ? ch.size.width : ch.size.height);
        ch = rf.childAfter(ch);
      }
      final mainExt = rf.direction == Axis.horizontal ? rf.size.width : rf.size.height;
      final sum = kids.fold<double>(0, (a, b) => a + b) + (kids.isEmpty ? 0 : rf.spacing * (kids.length - 1));
      final origin = rf.localToGlobal(Offset.zero);
      return {'hash': shortHash(rf), 'dir': rf.direction.name, 'constraints': rf.constraints.toString(), 'size': rf.size.toString(),
        'rect': [origin.dx, origin.dy, origin.dx + rf.size.width, origin.dy + rf.size.height], 'kids': kids, 'spacing': rf.spacing,
        'sum': sum, 'main': mainExt, 'over': sum - mainExt, 'creator': rf.debugCreator?.toString()};
    }

    ({String? dir, String? val, List<int> lines, String? hash}) owner(String first, String full) {
      final mm = RegExp(r'^A RenderFlex overflowed by ([0-9.]+) pixels on the (right|bottom|left|top)[.]$').firstMatch(first);
      final lines = RegExp(r'attendance_status_dialog[.]dart:([0-9]+):[0-9]+').allMatches(full).map((x) => int.parse(x.group(1)!)).toList();
      final h = RegExp(r'RenderFlex#([0-9a-f]{5})').firstMatch(full);
      return (dir: mm?.group(2), val: mm?.group(1), lines: lines, hash: h?.group(1));
    }

    // host `_buildContent` Column = TabBar 위로 두 번째 Column(첫째는 상단 Column)
    Element? hostEl() {
      final tb = find.byType(TabBar).evaluate();
      if (tb.length != 1) return null;
      var seen = 0;
      Element? hit;
      tb.first.visitAncestorElements((a) {
        if (a.widget is Column) {
          seen++;
          if (seen == 2) {
            hit = a;
            return false;
          }
        }
        return true;
      });
      return hit;
    }

    // 상단 Column 과 그 Padding — 자연 높이 T
    Element? topColEl() {
      final tb = find.byType(TabBar).evaluate();
      if (tb.length != 1) return null;
      return nearest(tb.first, (w) => w is Column);
    }

    // 셸 Column = AppModalShell 아래 첫 Column
    RenderFlex? shellFlex() {
      final s = find.descendant(of: find.byType(AppModalShell), matching: find.byType(Column)).evaluate();
      if (s.isEmpty) return null;
      final ro = s.first.renderObject;
      return ro is RenderFlex ? ro : null;
    }

    // 세로 Scrollable 조상(stopAt 에 닿으면 null)
    Element? vScrollOf(Element e, {Element? stopAt}) {
      Element? hit;
      e.visitAncestorElements((a) {
        if (stopAt != null && identical(a, stopAt)) return false;
        final w = a.widget;
        if (w is Scrollable && w.axisDirection == AxisDirection.down) {
          hit = a;
          return false;
        }
        return true;
      });
      return hit;
    }

    ScrollPosition posOf(Element se) => ((se as StatefulElement).state as ScrollableState).position;

    Map<String, Object?> scrollInfo(Element? se) {
      if (se == null) return {'present': false};
      final pos = posOf(se);
      return {'present': true, 'pixels': pos.pixels, 'min': pos.minScrollExtent, 'max': pos.maxScrollExtent, 'viewport': pos.viewportDimension,
        'rect': rectL(t.getRect(fe(se)))};
    }

    Element? topScrollEl() {
      final tc = topColEl();
      return tc == null ? null : vScrollOf(tc, stopAt: hostEl());
    }

    // 현재 탭 목록 창(TabBarView 안 첫 RichText 의 세로 Scrollable)
    Element? listScrollEl() {
      final names = find.descendant(of: find.byType(TabBarView), matching: find.byType(RichText)).evaluate().toList();
      return names.isEmpty ? null : vScrollOf(names.first);
    }

    double? pixelsOf(Element? se) => se == null ? null : posOf(se).pixels;

    // 실제 paint clip chain — DU304 와 같은 정확 지원범위(RenderViewport 조건부 1개 포함). 지원 밖 clip 은 unsupported.
    const rectClipTypes = <String>{
      'RenderFlex', 'RenderConstraintsTransformBox', 'RenderStack', 'RenderIndexedStack', '_RenderTheater', '_RenderSingleChildViewport',
      'RenderClipRect',
    };
    Map<String, Object?> clipInfo(Finder f, Rect screen) {
      final ro = t.renderObject(f);
      if (ro is! RenderBox) return {'supported': false, 'reason': 'RenderBox 아님 ${ro.runtimeType}', 'full': false, 'unsupported': ['not-box']};
      final rect = boxRect(ro);
      var vis = rect.intersect(screen);
      final chain = <Map<String, Object?>>[];
      final unsupported = <String>[];
      var pairs = 0;
      RenderObject child = ro;
      RenderObject? p = ro.parent;
      while (p != null) {
        pairs++;
        final local = p.describeApproximatePaintClip(child);
        if (local != null) {
          final type = p.runtimeType.toString();
          final global = MatrixUtils.transformRect(p.getTransformTo(null), local);
          final clipperNull = p is RenderClipRect ? p.clipper == null : null;
          final vpExact = type == 'RenderViewport' && child is RenderSliver && child.constraints.overlap == 0 &&
              child.constraints.viewportMainAxisExtent.isFinite;
          final exact = (rectClipTypes.contains(type) && (clipperNull ?? true)) || vpExact;
          chain.add({'parent': type, 'child': child.runtimeType.toString(), 'local': rectL(local), 'global': rectL(global), 'rectExact': exact,
            'clipperNull': clipperNull, 'viewportExact': vpExact});
          if (exact) {
            vis = vis.intersect(global);
          } else {
            unsupported.add(type);
          }
        }
        child = p;
        p = p.parent;
      }
      final shown = vis.width > 0 && vis.height > 0;
      final full = shown && unsupported.isEmpty && (vis.left - rect.left).abs() <= 0.5 && (vis.top - rect.top).abs() <= 0.5 &&
          (vis.right - rect.right).abs() <= 0.5 && (vis.bottom - rect.bottom).abs() <= 0.5;
      return {'rect': rectL(rect), 'screen': rectL(screen), 'visible': shown ? rectL(vis) : null, 'full': full, 'pairsWalked': pairs,
        'clipChain': chain, 'unsupported': unsupported, 'root': child.runtimeType.toString()};
    }

    // 매 pump·mount·행동 뒤: 예외·오류(허용 0)·네트워크/업무 채널·동결 뒤 Reads
    void guard(String where) {
      final ex = t.takeException();
      need(ex == null, '$where 예외: $ex');
      for (final e in errors) {
        final o = owner(e.first, e.full);
        final r = {'phase': phase, 'scen': scen, 'cond': e.cond, 'stage': e.stage, 'pump': e.pump, 'first': e.first, 'dir': o.dir, 'val': o.val,
          'ownerLines': o.lines, 'hash': o.hash, 'allowed': false, 'full': e.full};
        errLog.add(r);
        _out('D305-ERR ${jsonEncode(r)}');
        stop('오류(허용 0) ${e.first} at $where');
      }
      errors.clear();
      need(net.created == 0, '$where HttpClient ${net.created}');
      need(biz.isEmpty, '$where 업무 채널 $biz');
      need(afterFreeze.isEmpty, '$where 초기 로드 뒤 Reads $afterFreeze');
    }

    Future<void> frames(int n, String where) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        budget();
        await t.pump(const Duration(milliseconds: 50));
        guard('$where#$i');
      }
    }

    Future<void> mount(Widget w) async {
      nMount++;
      budget();
      await t.pumpWidget(w);
      live = w is! SizedBox;
      guard('mount');
    }

    Future<void> tapAt(Finder f, String what) async {
      need(f.evaluate().length == 1, '$what 대상 수 ${f.evaluate().length}');
      need(f.hitTestable().evaluate().length == 1, '$what 중심 hit 아님');
      nTap++;
      budget();
      await t.tap(f);
      guard('tap:$what');
    }

    final business = BusinessModel(
      id: _biz, name: 'DU303 물류센터', businessNumber: '000-00-00000', category: '물류', subCategory: '포장',
      address: '경기도 평택시 서정동 1', ownerId: 'owner303', createdAt: DateTime(2026, 1, 1),
    );
    UserModel user(String uid, String name, UserRole role) =>
        UserModel(uid: uid, username: name, name: name, email: '$uid@example.invalid', role: role, createdAt: DateTime(2026, 1, 1));
    Map<String, dynamic> appMap(String id, String uid, String wd, String type, String start, String end) => {
          'id': id, 'uid': uid, 'toId': 'to303', 'slotId': 'slot303', 'businessId': _biz, 'wdId': wd, 'workDetailId': wd,
          'status': 'CONFIRMED', 'type': 'short_term', 'selectedWorkType': type, 'startTime': start, 'endTime': end,
          'workDate': _ts(dayKey), 'createdAt': _ts(dayKey), 'appliedAt': _ts(dayKey),
        };
    Map<String, dynamic> attMap(String id, String appId, String uid, String checkIn, {String? checkOut, bool adminConfirmed = false}) => {
          'id': id, 'applicationId': appId, 'uid': uid, 'businessId': _biz, 'status': 'present', 'checkIn': checkIn,
          if (checkOut != null) 'checkOut': checkOut,
          if (adminConfirmed) 'adminConfirmed': true,
          'workDate': _ts(dayKey), 'createdAt': _ts(dayKey),
        };
    final up = UserProvider()..debugSetCurrentUser(user('owner303', 'DU303 사장', UserRole.BUSINESS_ADMIN));
    final (ds, de) = FormatHelper.kstDayRange(dayKey);

    // ── fixture ──
    // BASE(DU303/DU304 와 같은 값): IN = 22:00/22:30 시작·근태 없음, OUT = 06:00/07:00 출근·23:00/23:30 퇴근 예정. 정상 탭(검토 0).
    //   업무명순 그룹이라 목록은 포장(박포장) → 피킹(김피킹).
    final baseModes = {
      'IN': (
        apps: [appMap('in-a', 'u-in-a', 'wd-pick', '피킹', '22:00', '23:00'), appMap('in-b', 'u-in-b', 'wd-pack', '포장', '22:30', '23:30')],
        atts: <Map<String, dynamic>>[],
        names: {'u-in-a': '김피킹', 'u-in-b': '박포장'},
        step: '출근', stepIcon: Icons.login,
      ),
      'OUT': (
        apps: [appMap('out-a', 'u-out-a', 'wd-pick', '피킹', '06:00', '23:00'), appMap('out-b', 'u-out-b', 'wd-pack', '포장', '07:00', '23:30')],
        atts: [attMap('att-out-a', 'out-a', 'u-out-a', '06:00'), attMap('att-out-b', 'out-b', 'u-out-b', '07:00')],
        names: {'u-out-a': '김피킹', 'u-out-b': '박포장'},
        step: '퇴근', stepIcon: Icons.logout,
      ),
    };
    // LONG(DU304 와 같은 값): 검토 2(rv-01 미출근, rv-02 06:00 출근·퇴근미기록), 정상 14(포장 6·피킹 6 = 22:00 시작 미출근,
    //   하차 2 = 06:00–07:00 정시 출퇴근 → 근태 확인 대상). 정상 목록: 포장01–06 → 피킹01–06 → 하차01–02.
    final longApps = <Map<String, dynamic>>[
      appMap('rv-01', 'u-rv-01', 'wd-rev', '검수', '06:00', '07:30'),
      appMap('rv-02', 'u-rv-02', 'wd-rev', '검수', '06:00', '07:30'),
      for (var i = 1; i <= 6; i++) appMap('pk-0$i', 'u-pk-0$i', 'wd-pack', '포장', '22:00', '23:00'),
      for (var i = 1; i <= 6; i++) appMap('pc-0$i', 'u-pc-0$i', 'wd-pick', '피킹', '22:00', '23:00'),
      appMap('dn-01', 'u-dn-01', 'wd-done', '하차', '06:00', '07:00'),
      appMap('dn-02', 'u-dn-02', 'wd-done', '하차', '06:00', '07:00'),
    ];
    final longAtts = <Map<String, dynamic>>[
      attMap('att-rv-02', 'rv-02', 'u-rv-02', '06:00'),
      attMap('att-dn-01', 'dn-01', 'u-dn-01', '06:00', checkOut: '07:00'),
      attMap('att-dn-02', 'dn-02', 'u-dn-02', '06:00', checkOut: '07:00'),
    ];
    final longNames = <String, String>{
      'u-rv-01': '검토01', 'u-rv-02': '검토02',
      for (var i = 1; i <= 6; i++) 'u-pk-0$i': '포장0$i',
      for (var i = 1; i <= 6; i++) 'u-pc-0$i': '피킹0$i',
      'u-dn-01': '하차01', 'u-dn-02': '하차02',
    };
    // EDGE: BASE IN 형 3명(포장·피킹·하차, 정상 탭). workTypeDocs 가 세 업무의 세 아이콘 경로를 돌려준다(payload 만 다르다):
    //   포장 icon '' → 이름 첫 글자, 피킹 '📦' → 이모지, 하차 'material:<첫 IconPicker 아이콘>' → Material.
    //   E320_20 만: adminConfirmed=true·06:00–07:00 출퇴근 완료·급여 미처리 1건(확인완료 탭, 하차)을 더한다.
    final edgeApps = <Map<String, dynamic>>[
      appMap('eg-pack', 'u-eg-pack', 'wd-pack', '포장', '22:00', '23:00'),
      appMap('eg-pick', 'u-eg-pick', 'wd-pick', '피킹', '22:00', '23:00'),
      appMap('eg-drop', 'u-eg-drop', 'wd-drop', '하차', '22:30', '23:30'),
    ];
    final edgeConfApp = appMap('eg-conf', 'u-eg-conf', 'wd-drop', '하차', '06:00', '07:00');
    final edgeConfAtt = attMap('att-eg-conf', 'eg-conf', 'u-eg-conf', '06:00', checkOut: '07:00', adminConfirmed: true);
    final edgeNames = <String, String>{'u-eg-pack': '박포장', 'u-eg-pick': '김피킹', 'u-eg-drop': '이하차', 'u-eg-conf': '정확인'};
    final materialIcon = 'material:${IconPickerDialog.getAllIcons().first.icon.codePoint}';
    Map<String, dynamic> wtDoc(String name, String icon, int order) => {
          'businessId': _biz, 'name': name, 'icon': icon, 'displayOrder': order, 'isActive': true,
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        };
    final edgeWt = <String, Map<String, dynamic>>{
      'wt-pack': wtDoc('포장', '', 1),
      'wt-pick': wtDoc('피킹', '📦', 2),
      'wt-drop': wtDoc('하차', materialIcon, 3),
    };

    // ── Reads 대역·사전표(9함수 10호출) — mount 마다 새로 만든다 ──
    ({AttendanceReads reads, Map<String, List<Object?>> calls, String Function() actual, String expected, void Function() freeze})
        makeReads(String tag, List<Map<String, dynamic>> apps, List<Map<String, dynamic>> atts, Map<String, String> names,
            {Map<String, Map<String, dynamic>> wt = const {}}) {
      final calls = <String, List<Object?>>{};
      var frozen = false;
      void rec(String name, Object? args) {
        (calls[name] ??= []).add(args);
        if (frozen) afterFreeze.add('$tag:$name');
      }

      final reads = AttendanceReads(
        applicationsPaged: (payload) async {
          rec('applicationsPaged', Map<String, dynamic>.of(payload));
          if (payload['type'] != null) return const [];
          return [for (final a in apps) Map<String, dynamic>.of(a)];
        },
        workTypeDocs: (id) async {
          rec('workTypeDocs', id);
          return {for (final e in wt.entries) e.key: Map<String, dynamic>.of(e.value)};
        },
        adminAttendances: ({required businessId, required startMs, required endMs}) async {
          rec('adminAttendances', {'businessId': businessId, 'startMs': startMs, 'endMs': endMs});
          return [for (final a in atts) Map<String, dynamic>.of(a)];
        },
        workDetailTimes: (workers) async {
          rec('workDetailTimes', workers.map((w) => w.id).toList()..sort());
          return const {};
        },
        usersBatch: ({required uids, required businessId}) async {
          rec('usersBatch', {'uids': [...uids]..sort(), 'businessId': businessId});
          return {for (final u in uids) u: user(u, names[u] ?? u, UserRole.USER)};
        },
        contractStatus: ({required appIds, required businessId}) async {
          rec('contractStatus', {'appIds': [...appIds]..sort(), 'businessId': businessId});
          return ContractStatusBatch(statuses: {for (final id in appIds) id: 'signed'});
        },
        dayStaffing: ({required businessId, required dayStartMs}) async {
          rec('dayStaffing', {'businessId': businessId, 'dayStartMs': dayStartMs});
          return const <DayStaffingRow>[];
        },
        businessById: (id) async {
          rec('businessById', id);
          return business;
        },
        businessNames: (ids) async {
          rec('businessNames', [...ids]);
          return {for (final i in ids) i: business.name};
        },
      );
      final expIds = [for (final a in apps) a['id'] as String]..sort();
      final expUids = {for (final a in apps) a['uid'] as String}.toList()..sort();
      final expected = <String, List<Object?>>{
        'businessNames': [
          [_biz]
        ],
        'applicationsPaged': [
          {'businessId': _biz, 'workDateGteMs': ds.millisecondsSinceEpoch, 'workDateLtMs': de.millisecondsSinceEpoch,
            'purpose': FirestoreService.purposeWorkerOperation, 'limit': 2000},
          {'businessId': _biz, 'type': AppType.longTerm, 'purpose': FirestoreService.purposeWorkerOperation, 'limit': 2000},
        ],
        'workTypeDocs': [_biz],
        'dayStaffing': [
          {'businessId': _biz, 'dayStartMs': ds.millisecondsSinceEpoch}
        ],
        'businessById': [_biz],
        'adminAttendances': [
          {'businessId': _biz, 'startMs': ds.subtract(const Duration(days: 1)).millisecondsSinceEpoch, 'endMs': de.millisecondsSinceEpoch}
        ],
        'usersBatch': [
          {'uids': expUids, 'businessId': _biz}
        ],
        'workDetailTimes': [expIds],
        'contractStatus': [
          {'appIds': expIds, 'businessId': _biz}
        ],
      };
      String canon(Map<String, List<Object?>> x) => jsonEncode({for (final k in (x.keys.toList()..sort())) k: x[k]});
      return (reads: reads, calls: calls, actual: () => canon(calls), expected: canon(expected), freeze: () {
        frozen = true;
      });
    }

    final capKey = GlobalKey();
    Widget app(Widget home, String key) => RepaintBoundary(
          key: capKey,
          child: ChangeNotifierProvider<UserProvider>.value(
            value: up,
            child: MaterialApp(
              key: ValueKey(key),
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ko', 'KR')],
              home: home,
            ),
          ),
        );

    // 로드 대기: Reads 10호출 + 정상 탭·전체 보임(최대 16 frame) → 1 frame → 동결 → 사전표 대조
    Future<void> waitLoad(({AttendanceReads reads, Map<String, List<Object?>> calls, String Function() actual, String expected, void Function() freeze}) r) async {
      final tabNormal = richExact('정상', within: find.byType(TabBar));
      for (var i = 0; i < 16; i++) {
        final n = r.calls.values.fold<int>(0, (a, b) => a + b.length);
        if (n >= 10 && tabNormal.evaluate().length == 1 && richExact('전체').evaluate().isNotEmpty) break;
        await frames(1, 'load');
      }
      await frames(1, 'load');
      r.freeze();
      final match = r.actual() == r.expected;
      _out('D305-READS ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'actual': r.calls, 'match': match})}');
      need(match, 'Reads 사전표 불일치');
    }

    // ── 대상 finder ──
    Finder allBox() {
      final els = richExact('전체').evaluate().where((e) {
        final g = nearest(e, (w) => w is GestureDetector);
        return g != null && find.descendant(of: fe(g), matching: find.byType(AppCheckbox)).evaluate().length == 1;
      }).toList();
      need(els.length == 1, '전체 수 ${els.length}');
      return fe(nearest(els.first, (w) => w is GestureDetector)!);
    }

    // 전체 옆 선택 수 배지(현재 탭 선택 수, 0 이면 없음)
    String? selectedBadge() {
      final g = allBox();
      final digits = find.descendant(of: g, matching: find.byType(RichText)).evaluate().map(plainOf)
          .where((s) => RegExp(r'^[0-9]+$').hasMatch(s)).toList();
      return digits.isEmpty ? null : digits.single;
    }

    Finder button(IconData icon, String label) {
      final els = find.byType(InkWell).evaluate().where((e) =>
          find.descendant(of: fe(e), matching: find.byIcon(icon)).evaluate().length == 1 &&
          richExact(label, within: fe(e)).evaluate().length == 1).toList();
      need(els.length == 1, '$label 버튼 수 ${els.length}');
      return fe(els.first);
    }

    String? buttonCount(Finder b) {
      final s = find.descendant(of: b, matching: find.byType(RichText)).evaluate().map(plainOf)
          .where((x) => RegExp(r'^[0-9]+건$').hasMatch(x)).toList();
      return s.isEmpty ? null : s.single;
    }

    Finder searchBox() {
      final els = find.byType(InkWell).evaluate().where((e) =>
          find.descendant(of: fe(e), matching: find.byIcon(Icons.search)).evaluate().length == 1 ||
          find.descendant(of: fe(e), matching: find.byIcon(Icons.search_off)).evaluate().length == 1).toList();
      need(els.length == 1, '검색 버튼 수 ${els.length}');
      return fe(els.first);
    }

    Finder nameF(String name) {
      final f = richExact(name);
      need(f.evaluate().length == 1, '$name 이름 수 ${f.evaluate().length}');
      return f;
    }

    // 행 선택 receiver = 이름과 같은 행의 AppCheckbox 를 감싼 GestureDetector(카드 tap 은 상세 열기라 쓰지 않는다)
    Finder rowReceiver(String name) {
      final n = nameF(name).evaluate().first;
      Element? rowEl;
      n.visitAncestorElements((a) {
        if (a.widget is Row && find.descendant(of: fe(a), matching: find.byType(AppCheckbox)).evaluate().length == 1) {
          rowEl = a;
          return false;
        }
        return true;
      });
      need(rowEl != null, '$name 행 없음');
      final cb = find.descendant(of: fe(rowEl!), matching: find.byType(AppCheckbox)).evaluate().first;
      final g = nearest(cb, (w) => w is GestureDetector);
      need(g != null, '$name 선택 receiver 없음');
      return fe(g!);
    }

    Finder hostX() => find.descendant(of: find.byType(AppModalHeader), matching: find.byIcon(Icons.close));

    // S1 W 보존 rect 대조(선택 전 상태 첫 기록, 두 phase 단언)
    void prevVis(String what, Map<String, Object?> ci) {
      final k = '$cond|$stage|$what';
      final want = _kPrevVis[k];
      if (want == null || prevSeen.contains(k)) return;
      prevSeen.add(k);
      final r = ci['rect'] as List<double>;
      final ok = [for (var i = 0; i < 4; i++) near(r[i], want[i], 0.5)].every((x) => x);
      _out('D305-PREV ${jsonEncode({'phase': phase, 'key': k, 'rect': r, 'r1t': want, 'ok': ok})}');
      need(ok, 'S1 W rect 가 R1T 와 다름 $k');
    }

    // 화면 안·clip 전부·중심 hit 를 같은 frame 에서 본다(단언 전 출력)
    void visibleHit(Finder f, String what, Rect screen) {
      need(f.evaluate().length == 1, '$what 대상 수 ${f.evaluate().length}');
      final ci = clipInfo(f, screen);
      final hit = f.hitTestable().evaluate().length;
      _out('D305-VIS ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'stage': stage, 'what': what, 'hit': hit, 'assert': true, ...ci})}');
      prevVis(what, ci);
      need((ci['unsupported'] as List).isEmpty, '$what 지원 밖 clip ${ci['unsupported']}');
      need(ci['full'] == true && hit == 1, '$what 가시/hit 아님 full=${ci['full']} hit=$hit');
    }

    // 같은 관측을 기록만 한다(before 의 SEL·END 등). 대상이 없으면 absent 로 남긴다.
    Map<String, Object?> visRec(Finder f, String what, Rect screen) {
      final n = f.evaluate().length;
      if (n != 1) {
        final r = {'phase': phase, 'scen': scen, 'cond': cond, 'stage': stage, 'what': what, 'assert': false, 'count': n, 'full': false};
        _out('D305-VIS ${jsonEncode(r)}');
        return r;
      }
      final ci = clipInfo(f, screen);
      final hit = f.hitTestable().evaluate().length;
      final r = {'phase': phase, 'scen': scen, 'cond': cond, 'stage': stage, 'what': what, 'hit': hit, 'assert': false, ...ci};
      _out('D305-VIS ${jsonEncode(r)}');
      return r;
    }

    // after 단언·before 기록
    void selVis(Finder f, String what, Rect screen) {
      if (after) {
        visibleHit(f, what, screen);
      } else {
        visRec(f, what, screen);
      }
    }

    // bounded 세로 drag: DU304 수리 r1 의 reachV 그대로(대상마다 최대 2회, 요청 = d + a + c).
    Future<void> reachV(Finder target, Element? se, String what, Rect screen) async {
      need(target.evaluate().length == 1, '$what 대상 수 ${target.evaluate().length}');
      var corr = 0.0;
      for (var i = 0; i < 2; i++) {
        final r = t.getRect(target);
        final vp = se == null ? screen : t.getRect(fe(se));
        if (inside(r, vp) && target.hitTestable().evaluate().length == 1) break;
        need(se != null, '$what 스크롤 없이 창 밖 rect=${rectL(r)}');
        need(r.height <= vp.height + 0.5, '$what 높이 ${r.height} > 창 ${vp.height}');
        final below = r.bottom > vp.bottom;
        final d = below ? r.bottom - vp.bottom : vp.top - r.top;
        final slack = (vp.height - r.height) / 2;
        final a = slack < 0 ? 0.0 : (slack > 16 ? 16.0 : slack);
        final c = i == 0 ? 0.0 : corr;
        final req = d + a + c;
        // [수리 r1] 요청이 터치 slop(18) 이하이면 drag 가 아니라 출발점 receiver 의 탭이 된다(TA E320_20: 17.9 → 그룹 머리 탭·이동 0).
        //   drag 로 인식되도록 크기만 slop + 2 이상으로 올린다. 요청·이동·차·보정 기록과 대상당 최대 2회는 그대로다.
        final mag = req < kDragSlopDefault + 2 ? kDragSlopDefault + 2 : req;
        final dy = below ? -mag : mag;
        final pos = posOf(se!);
        final p0 = pos.pixels;
        final max0 = pos.maxScrollExtent;
        nDrag++;
        budget();
        await t.dragFrom(vp.center, Offset(0, dy));
        guard('drag:$what');
        await frames(3, 'drag:$what');
        final p1 = pos.pixels;
        final moved = below ? p1 - p0 : p0 - p1;
        final diff = req - moved;
        final clamped = (p1 - pos.minScrollExtent).abs() <= _kEps || (pos.maxScrollExtent - p1).abs() <= _kEps;
        final layoutChanged = (pos.maxScrollExtent - max0).abs() > _kEps;
        final usable = i == 0 && moved >= 0 && diff >= 0 && diff <= 20 && !clamped && !layoutChanged;
        if (usable) corr = diff;
        _out('D305-REACH ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'what': what, 'axis': 'v', 'try': i, 'start': [vp.center.dx, vp.center.dy],
          'd': d, 'a': a, 'c': c, 'req': req, 'dy': dy, 'before': p0, 'after': p1, 'moved': moved, 'diff': diff, 'clamped': clamped,
          'layoutChanged': layoutChanged, 'nextCorrection': i == 0 ? (usable ? diff : 0.0) : null, 'max': pos.maxScrollExtent})}');
      }
      visibleHit(target, what, screen);
    }

    // 되돌림: 세로 스크롤을 0 으로(창 중심에서 pixels + slop + 16 아래로, 최대 2회)
    Future<void> backTop(Element? se, String what) async {
      if (se == null) return;
      for (var i = 0; i < 2; i++) {
        final pos = posOf(se);
        if (pos.pixels <= _kEps) return;
        final vp = t.getRect(fe(se));
        final p0 = pos.pixels;
        nDrag++;
        budget();
        await t.dragFrom(vp.center, Offset(0, p0 + kDragSlopDefault + 16));
        guard('back:$what');
        await frames(3, 'back:$what');
        _out('D305-REACH ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'what': 'back:$what', 'axis': 'v', 'try': i, 'before': p0, 'after': pos.pixels})}');
      }
      final pos = posOf(se);
      need(pos.pixels <= _kEps, '$what 되돌림 실패 ${pos.pixels}');
    }

    Element? tabHScroll() {
      final hs = find.descendant(of: find.byType(TabBar), matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right))
          .evaluate().toList();
      return hs.isEmpty ? null : hs.first;
    }

    // 탭 하나 가로 도달(DU304 checkTabs 의 대상당 로직, 최대 2 drag) — EDGE 확인완료 한 대상(감사 r2 §3-4)
    Future<void> reachTab(String label, Rect screen) async {
      final se = tabHScroll();
      final f = richExact(label, within: find.byType(TabBar));
      for (var i = 0; i < 2; i++) {
        final r = t.getRect(f);
        final vp = se == null ? t.getRect(find.byType(TabBar)) : t.getRect(fe(se));
        if (inside(r, vp) && f.hitTestable().evaluate().length == 1) break;
        need(se != null, '탭 $label 가로 스크롤 없이 창 밖');
        final right = r.right > vp.right;
        final d = right ? r.right - vp.right : vp.left - r.left;
        final dx = right ? -(d + kDragSlopDefault + 16) : (d + kDragSlopDefault + 16);
        nDrag++;
        budget();
        await t.dragFrom(vp.center, Offset(dx, 0));
        guard('tabdrag:$label');
        await frames(3, 'tabdrag:$label');
        _out('D305-REACH ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'what': 'tab:$label', 'axis': 'h', 'try': i, 'dx': dx, 'after': posOf(se!).pixels})}');
      }
      visibleHit(f, '탭 $label', screen);
    }

    // 탭 4개(DU304 checkTabs 그대로): 대상마다 최대 2 drag 뒤 가시·hit, 끝나면 처음으로 되돌린다
    Future<void> checkTabs(Rect screen) async {
      final se = tabHScroll();
      for (final label in const ['확인필요', '정상', '확인완료', '처리완료']) {
        final f = richExact(label, within: find.byType(TabBar));
        for (var i = 0; i < 2; i++) {
          final r = t.getRect(f);
          final vp = se == null ? t.getRect(find.byType(TabBar)) : t.getRect(fe(se));
          if (inside(r, vp) && f.hitTestable().evaluate().length == 1) break;
          need(se != null, '탭 $label 가로 스크롤 없이 창 밖');
          final right = r.right > vp.right;
          final d = right ? r.right - vp.right : vp.left - r.left;
          final dx = right ? -(d + kDragSlopDefault + 16) : (d + kDragSlopDefault + 16);
          nDrag++;
          budget();
          await t.dragFrom(vp.center, Offset(dx, 0));
          guard('tabdrag:$label');
          await frames(3, 'tabdrag:$label');
          _out('D305-REACH ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'what': 'tab:$label', 'axis': 'h', 'try': i, 'dx': dx, 'after': posOf(se!).pixels})}');
        }
        visibleHit(f, '탭 $label', screen);
      }
      if (se != null) {
        final pos = posOf(se);
        if (pos.pixels > _kEps) {
          final vp = t.getRect(fe(se));
          nDrag++;
          budget();
          await t.dragFrom(vp.center, Offset(pos.pixels + kDragSlopDefault + 16, 0));
          guard('tabback');
          await frames(3, 'tabback');
          need(pos.pixels <= _kEps, '탭 가로 되돌림 실패 ${pos.pixels}');
        }
      }
    }

    // ── 기하 기록·단언(단언 전에 D305-HOST 출력) — DU304 수용 host 계약은 두 phase 같다 ──
    String? hostHash0;
    Map<String, Object?> measure(String tag) {
      clockGuard(tag);
      final he = hostEl();
      final tc = topColEl();
      need(he != null && he.renderObject is RenderFlex && tc != null, 'host 관측 불가 at $tag');
      final hostE = he!;
      final topC = tc!;
      final hf = hostE.renderObject! as RenderFlex;
      final pad = nearest(topC, (w) => w is Padding);
      need(pad != null && pad.renderObject is RenderBox, '상단 Padding 없음 at $tag');
      final topT = (pad!.renderObject! as RenderBox).size.height;
      final hi = flexInfo(hf);
      final kids = hi['kids'] as List<double>;
      final topScroll = vScrollOf(topC, stopAt: hostE);
      final sh = shellFlex();
      final shi = sh == null ? null : flexInfo(sh);
      final listScroll = listScrollEl();
      final hRaw = hf.constraints.maxHeight;
      final rec = {'phase': phase, 'scen': scen, 'cond': cond, 'tag': tag, 'pump': nPump, 'H': hRaw.isFinite ? hRaw : 'inf', 'T': topT,
        'topViewport': kids.isEmpty ? null : kids.first, 'list': kids.length < 2 ? null : kids[1], 'host': hi, 'shell': shi,
        'topScroll': scrollInfo(topScroll), 'listScroll': scrollInfo(listScroll), 'selectedBadge': selectedBadge()};
      _out('D305-HOST ${jsonEncode(rec)}');
      final h = shortHash(hf);
      if (hostHash0 == null) {
        hostHash0 = h;
      } else {
        need(h == hostHash0, 'host RenderObject 바뀜 $h ≠ $hostHash0 at $tag');
      }
      final hh = hf.constraints.maxHeight;
      need(hh.isFinite && hh > 0, 'H 비유한/0 $hh at $tag');
      need(kids.length == 2, 'host 자식 수 ${kids.length} at $tag');
      need(sh != null && (shi!['over'] as double) <= _kEps, '셸 넘침 ${shi?['over']} at $tag');
      final over = hi['over'] as double;
      final view = kids.first;
      final list = kids[1];
      final cap = hh * _kTopShare;
      need(over <= _kEps, 'host 넘침 $over at $tag');
      need(near(view, topT <= cap ? topT : cap, _kTol), '상단 창 $view ≠ min(T $topT, 상한 $cap) at $tag');
      need(near(list, hh - view, _kTol) && list > _kEps, '목록 $list ≠ H − 상단 at $tag');
      final ts = scrollInfo(topScroll);
      need(ts['present'] == true, '상단 스크롤 없음 at $tag');
      final mx = ts['max'] as double;
      need(topT <= cap + _kEps ? mx <= _kEps : near(mx, topT - cap, _kTol), '상단 스크롤 범위 $mx at $tag');
      // S1 W 보존(두 phase): load/tab 의 H·T·상단·목록 = R1T ±0.01
      final pk = _kPrevHost['$cond|$tag'];
      if (pk != null && (scen == 'BASE' || scen == 'LONG')) {
        final ok = near(hh, pk.h, _kTol) && near(topT, pk.t, _kTol) && near(view, pk.top, _kTol) && near(list, pk.list, _kTol);
        _out('D305-PREV ${jsonEncode({'phase': phase, 'key': '$cond|$tag', 'H': hh, 'T': topT, 'top': view, 'list': list, 'r1t': [pk.h, pk.t, pk.top, pk.list], 'ok': ok})}');
        need(ok, 'S1 W host 기하가 R1T 와 다름 $cond|$tag');
      }
      return rec;
    }

    // ── 가독성 측정: RenderParagraph 의 실제 getter·constraints 로 TextPainter 를 재구성한다(감사 r2 §3-1) ──
    //   layout(minWidth: c.minWidth, maxWidth: softWrap||ellipsis ? c.maxWidth : ∞) — SDK paragraph.dart:845 와 같다.
    //   재구성 size = p.textSize ±0.01, c.constrain(size) = p.size ±0.01 이 아니면 측정 실패(중단). placeholder 가 있으면 재구성하지 않는다.
    Map<String, Object?> para(Element e, String what) {
      final ro = e.renderObject;
      need(ro is RenderParagraph, '$what RenderParagraph 아님 ${ro.runtimeType}');
      final p = ro! as RenderParagraph;
      var placeholder = false;
      p.text.visitChildren((s) {
        if (s is PlaceholderSpan) {
          placeholder = true;
          return false;
        }
        return true;
      });
      need(!placeholder, '$what placeholder(WidgetSpan) — 치수 없이 재구성하지 않는다');
      final ellipsis = p.overflow == TextOverflow.ellipsis;
      final tp = TextPainter(
        text: p.text,
        textAlign: p.textAlign,
        textDirection: p.textDirection,
        textScaler: p.textScaler,
        maxLines: p.maxLines,
        ellipsis: ellipsis ? '…' : null,
        locale: p.locale,
        strutStyle: p.strutStyle,
        textWidthBasis: p.textWidthBasis,
        textHeightBehavior: p.textHeightBehavior,
      )..layout(minWidth: p.constraints.minWidth, maxWidth: (p.softWrap || ellipsis) ? p.constraints.maxWidth : double.infinity);
      final ts = p.textSize;
      final tpSize = tp.size; // dispose 뒤에는 읽지 않는다
      final cs = p.constraints.constrain(tpSize);
      final okText = near(tpSize.width, ts.width, _kTol) && near(tpSize.height, ts.height, _kTol);
      final okBox = near(cs.width, p.size.width, _kTol) && near(cs.height, p.size.height, _kTol);
      final plain = tp.plainText;
      final lines = <String>[];
      final lineRanges = <List<int>>[];
      for (final lm in tp.computeLineMetrics()) {
        final pos = tp.getPositionForOffset(Offset(lm.left + lm.width / 2, lm.baseline - lm.ascent / 2));
        final b = tp.getLineBoundary(pos);
        lineRanges.add([b.start, b.end]);
        lines.add(visibleText(plain.substring(b.start, b.end)).trim());
      }
      final intrinsic = p.getMaxIntrinsicWidth(double.infinity);
      tp.dispose();
      final textW = nearest(e, (w) => w is Text);
      final semLabel = textW == null ? null : (textW.widget as Text).semanticsLabel;
      final rec = {'phase': phase, 'scen': scen, 'cond': cond, 'stage': stage, 'what': what, 'plain': visibleText(plain),
        'lines': lines, 'lineRanges': lineRanges, 'lineCount': lines.length, 'intrinsic': intrinsic, 'size': [p.size.width, p.size.height],
        'textSize': [ts.width, ts.height], 'painter': [cs.width, cs.height], 'constraints': p.constraints.toString(),
        'softWrap': p.softWrap, 'overflow': p.overflow.name, 'maxLines': p.maxLines, 'didExceedMaxLines': p.didExceedMaxLines,
        'semanticsLabel': semLabel, 'rect': rectL(boxRect(p)), 'reconstructOk': okText && okBox};
      _out('D305-PARA ${jsonEncode(rec)}');
      need(okText && okBox, '$what TextPainter 재구성 불일치 painter=$tpSize textSize=$ts size=${p.size}');
      return rec;
    }

    bool noEllipsis(Map<String, Object?> pr) => pr['overflow'] != TextOverflow.ellipsis.name && pr['didExceedMaxLines'] == false;

    // S2 통계(독립): 네 칸 렌더 폭·건수/이름 paragraph 의 독립 intrinsic·줄 수
    void statsCheck(String tag) {
      stage = tag;
      final lab = richExact('확정');
      need(lab.evaluate().length == 1, '통계 확정 수 ${lab.evaluate().length}');
      final cell0 = nearest(lab.evaluate().first, (w) => w is Column);
      need(cell0 != null, '통계 칸 없음');
      final rowEl0 = nearest(cell0!, (w) => w is Row);
      need(rowEl0 != null && rowEl0.renderObject is RenderFlex, '통계 줄 없음');
      final rowEl = rowEl0!;
      final rowRo = rowEl.renderObject! as RenderFlex;
      final cells = <Map<String, Object?>>[];
      final boxes = <RenderBox>[];
      var sumNeed = 0.0;
      var oneLine = true;
      for (final l in const ['확정', '출근', '미출근', '노쇼']) {
        final le = richExact(l, within: fe(rowEl)).evaluate().toList();
        need(le.length == 1, '통계 $l 수 ${le.length}');
        final ce = nearest(le.first, (w) => w is Column)!;
        final cb = ce.renderObject! as RenderBox;
        boxes.add(cb);
        final cnt = find.descendant(of: fe(ce), matching: find.byType(RichText)).evaluate()
            .where((k) => RegExp(r'^[0-9]+건$').hasMatch(plainOf(k))).toList();
        need(cnt.length == 1, '통계 $l 건수 수 ${cnt.length}');
        final pc = para(cnt.first, '통계 $l 건수');
        final pl = para(le.first, '통계 $l 이름');
        final ic = pc['intrinsic'] as double;
        final il = pl['intrinsic'] as double;
        final needW = ic > il ? ic : il;
        sumNeed += needW;
        if (pc['lineCount'] != 1 || pl['lineCount'] != 1) oneLine = false;
        cells.add({'label': l, 'width': cb.size.width, 'need': needW, 'countLines': pc['lineCount'], 'labelLines': pl['lineCount']});
      }
      var other = 0.0;
      var ch = rowRo.firstChild;
      while (ch != null) {
        final cur = ch;
        final isCell = boxes.any((b) => identical(b, cur) || (cur is RenderProxyBox && identical(cur.child, b)));
        if (!isCell) other += cur.size.width;
        ch = rowRo.childAfter(cur);
      }
      final avail = rowRo.size.width - other;
      final ws = [for (final c in cells) c['width'] as double];
      final equal = ws.every((w) => near(w, ws.first, _kTol));
      final fits = sumNeed <= avail + _kEps;
      final rec = {'phase': phase, 'scen': scen, 'cond': cond, 'stage': tag, 'rowWidth': rowRo.size.width, 'dividers': other, 'avail': avail,
        'sumNeed': sumNeed, 'fits': fits, 'equal': equal, 'oneLine': oneLine, 'cells': cells};
      _out('D305-STATS ${jsonEncode(rec)}');
      if (!isB && scen == 'BASE') need(equal, 'S1 W 통계 네 칸 폭이 같지 않음 $ws');
      if (after && fits) {
        need(oneLine, 'S2 Σneed ≤ 가용인데 한 줄 아님');
        for (final c in cells) {
          need((c['width'] as double) >= (c['need'] as double) - _kEps, 'S2 ${c['label']} 폭 ${c['width']} < need ${c['need']}');
        }
      }
    }

    // 그룹 머리 목록(배지 '출근 N/M' 기준) — 머리 receiver·내용 box·제목·시간·배지·정렬 칩
    List<({String title, Element gd, Element badge, Element badgeChip, Element sortChip, Element time, Element titleEl, Rect content, String mode})>
        headers() {
      final out = <({String title, Element gd, Element badge, Element badgeChip, Element sortChip, Element time, Element titleEl, Rect content, String mode})>[];
      final bs = find.byWidgetPredicate((w) => w is RichText && _badgeRe.hasMatch(TextLayout.plain(w.text.toPlainText()))).evaluate().toList();
      for (final b in bs) {
        final gd0 = nearest(b, (w) => w is GestureDetector);
        need(gd0 != null, '머리 GestureDetector 없음');
        final gd = gd0!;
        need(find.descendant(of: fe(gd), matching: find.byType(AppCheckbox)).evaluate().length == 1, '머리 체크박스 수');
        Element? time0;
        Element? sortL0;
        for (final r in find.descendant(of: fe(gd), matching: find.byType(RichText)).evaluate()) {
          final s = plainOf(r);
          if (_timeRe.hasMatch(s) || s.startsWith('시간 ')) time0 = r;
          if (_sortLabels.contains(s)) sortL0 = r;
        }
        need(time0 != null && sortL0 != null, '머리 시간/정렬 없음');
        final time = time0!;
        final sortL = sortL0!;
        final col = nearest(time, (w) => w is Column)!;
        final titleEl = find.descendant(of: fe(col), matching: find.byType(RichText)).evaluate().first;
        final padEl = find.descendant(of: fe(gd), matching: find.byType(Padding)).evaluate().first;
        final rp = padEl.renderObject;
        need(rp is RenderPadding && rp.child is RenderBox, '머리 Padding 없음');
        final content = boxRect((rp! as RenderPadding).child! as RenderBox);
        var stacked = false;
        b.visitAncestorElements((a) {
          if (identical(a, gd)) return false;
          if (a.widget is Wrap) {
            stacked = true;
            return false;
          }
          return true;
        });
        out.add((title: plainOf(titleEl), gd: gd, badge: b, badgeChip: nearest(b, (w) => w is Container)!, sortChip: nearest(sortL, (w) => w is Container)!,
          time: time, titleEl: titleEl, content: content, mode: stacked ? 'stacked' : 'row'));
      }
      return out;
    }

    // S3 머리(독립): L = 제목 열 left − 머리 내용 left, C = 배지·정렬 칩 렌더 폭 max, Ti = 시간 paragraph intrinsic, W = 내용 폭.
    //   기대: L + Ti + C ≤ W 면 Row, 아니면 쌓음(차 ±0.5 는 경계로 기록, 어느 쪽이든 허용). after: 관측 = 기대·시간 줄 경계·제목 ellipsis 0.
    void headersCheck(String tag, Rect screen, {bool chipsAssert = false}) {
      stage = tag;
      final hs = headers();
      need(hs.isNotEmpty, '그룹 머리 없음');
      for (final h in hs) {
        final tr = boxRect(h.titleEl.renderObject! as RenderBox);
        final l = tr.left - h.content.left;
        final bw = (h.badgeChip.renderObject! as RenderBox).size.width;
        final sw = (h.sortChip.renderObject! as RenderBox).size.width;
        final c = bw > sw ? bw : sw;
        final pt = para(h.time, '머리 ${h.title} 시간');
        final ptitle = para(h.titleEl, '머리 ${h.title} 제목');
        final ti = pt['intrinsic'] as double;
        final w = h.content.width;
        final lhs = l + ti + c;
        final boundary = (lhs - w).abs() <= 0.5;
        final expect = lhs <= w ? 'row' : 'stacked';
        final lines = (pt['lines'] as List).cast<String>();
        final raw = pt['plain'] as String;
        final parts = raw.split(' ~ ');
        final want2 = parts.length == 2 ? ['${parts[0]} ~', parts[1]] : null;
        final rec = {'phase': phase, 'scen': scen, 'cond': cond, 'stage': tag, 'title': h.title, 'L': l, 'C': c, 'badgeW': bw, 'sortW': sw,
          'Ti': ti, 'W': w, 'lhs': lhs, 'expect': expect, 'boundary': boundary, 'mode': h.mode, 'timeLines': lines,
          'content': rectL(h.content), 'titleEllipsis': !noEllipsis(ptitle)};
        _out('D305-HEADER ${jsonEncode(rec)}');
        if (chipsAssert && after) {
          visibleHit(fe(h.badgeChip), '머리 ${h.title} 배지', screen);
          visibleHit(fe(h.sortChip), '머리 ${h.title} 정렬 칩', screen);
        } else {
          visRec(fe(h.badgeChip), '머리 ${h.title} 배지', screen);
          visRec(fe(h.sortChip), '머리 ${h.title} 정렬 칩', screen);
        }
        if (!isB && scen == 'BASE') need(h.mode == 'row', 'S1 W 머리 ${h.title} 가 Row 가 아님');
        if (after) {
          need(boundary || h.mode == expect, 'S3 머리 ${h.title} 모드 ${h.mode} ≠ 기대 $expect');
          need(noEllipsis(ptitle), 'S3 머리 ${h.title} 제목 ellipsis');
          need(noEllipsis(pt), 'S3 머리 ${h.title} 시간 ellipsis');
          if (h.mode == 'row') {
            need(lines.length == 1, 'S3 Row 머리 ${h.title} 시간 줄 ${lines.length}');
          } else {
            need(lines.length <= 2, 'S3 쌓음 머리 ${h.title} 시간 줄 ${lines.length}');
            if (lines.length == 2) need(want2 != null && lines[0] == want2[0] && lines[1] == want2[1], 'S3 머리 ${h.title} 줄 경계 $lines');
          }
        }
      }
    }

    // S5 행 시간: 이름이 든 카드(이름의 Material 조상) 안의 시간 paragraph
    void rowTimeCheck(String name, String timeText, {required bool range}) {
      final n = nameF(name).evaluate().first;
      final card0 = nearest(n, (w) => w is Material);
      need(card0 != null, '$name 카드 없음');
      final card = card0!;
      final te = richExact(timeText, within: fe(card)).evaluate().toList();
      need(te.length == 1, '$name 시간 $timeText 수 ${te.length}');
      final pr = para(te.first, '행 $name 시간');
      final lines = (pr['lines'] as List).cast<String>();
      final cardH = (card.renderObject! as RenderBox).size.height;
      _out('D305-ROWTIME ${jsonEncode({'phase': phase, 'cond': cond, 'name': name, 'time': timeText, 'lines': lines, 'cardHeight': cardH,
        'semanticsLabel': pr['semanticsLabel'], 'plain': pr['plain']})}');
      if (!after) return;
      need(pr['plain'] == timeText, 'S5 $name 원문 아님 ${pr['plain']}');
      need(pr['semanticsLabel'] == timeText, 'S5 $name semanticsLabel ${pr['semanticsLabel']}');
      need(noEllipsis(pr), 'S5 $name ellipsis');
      if (range) {
        final parts = timeText.split(' ~ ');
        need(lines.length == 1 || (lines.length == 2 && lines[0] == '${parts[0]} ~' && lines[1] == parts[1]), 'S5 $name 범위 줄 $lines');
      } else {
        need(lines.length == 1, 'S5 $name 단일 시각 줄 $lines');
      }
    }

    // S4·S4b footer 두 버튼: box ≥48×48·아이콘/라벨 containment·겹침 0·중심 full+hit·semantics 원문·줄 수
    void footerCheck(String tag, Rect screen) {
      stage = tag;
      for (final label in const ['명단 출력', '급여관리']) {
        final lf = richExact(label);
        need(lf.evaluate().length == 1, 'footer $label 수 ${lf.evaluate().length}');
        final le = lf.evaluate().first;
        final be = nearest(le, (w) => w is OutlinedButton);
        need(be != null, 'footer $label 버튼 없음');
        final bf = fe(be!);
        final outer = t.getRect(bf);
        final mat = find.descendant(of: bf, matching: find.byType(Material)).evaluate().first;
        final visual = t.getRect(fe(mat));
        final ic = find.descendant(of: bf, matching: find.byType(Icon)).evaluate().toList();
        need(ic.length == 1, 'footer $label 아이콘 수 ${ic.length}');
        final iconR = t.getRect(fe(ic.first));
        final labelR = boxRect(le.renderObject! as RenderBox);
        final pr = para(le, 'footer $label');
        final lines = (pr['lines'] as List).cast<String>();
        final semL = t.getSemantics(bf).getSemanticsData().label;
        final ov = iconR.intersect(labelR);
        final overlap = ov.width > 0.5 && ov.height > 0.5;
        final contain = inside(iconR, visual) && inside(labelR, visual);
        final r = after ? null : visRec(bf, 'footer $label 버튼', screen);
        if (after) visibleHit(bf, 'footer $label 버튼', screen);
        _out('D305-FOOTER ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'stage': tag, 'label': label, 'outer': rectL(outer),
          'visual': rectL(visual), 'icon': rectL(iconR), 'labelRect': rectL(labelR), 'contain': contain, 'overlap': overlap, 'lines': lines,
          'semantics': semL, 'textSemanticsLabel': pr['semanticsLabel'], 'recorded': r == null ? null : r['full']})}');
        if (!after) continue;
        need(outer.width >= 48 - _kEps && outer.height >= 48 - _kEps, 'S4b $label box ${outer.size}');
        need(contain && !overlap, 'S4b $label containment/겹침 contain=$contain overlap=$overlap');
        need(semL.contains(label), 'S4b $label semantics "$semL"');
        if (label == '급여관리') {
          need(lines.length == 1, 'S4b 급여관리 줄 $lines');
        } else {
          need(pr['semanticsLabel'] == '명단 출력', 'S4 명단 출력 semanticsLabel ${pr['semanticsLabel']}');
          need(isB ? (lines.length == 2 && lines[0] == '명단' && lines[1] == '출력') : lines.length == 1, 'S4 명단 출력 줄 $lines');
        }
      }
    }

    // S-COLOR 주 행동: `근태 확인 N건` — brand 채움·흰 글자·시각 버튼 높이 ≥52·실제 receiver ≥48×48·full+hit
    void colorPrimary(String label, Rect screen) {
      final lf = richExact(label);
      need(lf.evaluate().length == 1, '$label 수 ${lf.evaluate().length}');
      final be0 = nearest(lf.evaluate().first, (w) => w is ElevatedButton);
      need(be0 != null, '$label ElevatedButton 없음');
      final be = be0!;
      final bf = fe(be);
      final mat = find.descendant(of: bf, matching: find.byType(Material)).evaluate().first;
      final matColor = (mat.widget as Material).color;
      final style = (be.widget as ElevatedButton).style;
      final bg = style?.backgroundColor?.resolve(<WidgetState>{});
      final fg = style?.foregroundColor?.resolve(<WidgetState>{});
      final textColor = ((lf.evaluate().first.widget as RichText).text as TextSpan).style?.color;
      final outer = t.getRect(bf);
      final visual = t.getRect(fe(mat));
      _out('D305-COLOR ${jsonEncode({'phase': phase, 'cond': cond, 'stage': stage, 'label': label, 'kind': 'primary', 'material': matColor?.toARGB32(),
        'styleBg': bg?.toARGB32(), 'styleFg': fg?.toARGB32(), 'text': textColor?.toARGB32(), 'brand': AppColors.brand.toARGB32(),
        'outer': rectL(outer), 'visual': rectL(visual), 'visualHeight': visual.height})}');
      selVis(bf, '$label 버튼', screen);
      if (!after) return;
      need(matColor == AppColors.brand && bg == AppColors.brand, 'S-COLOR $label 채움 brand 아님');
      need(fg == Colors.white && textColor == Colors.white, 'S-COLOR $label 글자 흰색 아님');
      need(visual.height >= 52 - _kEps, 'S-COLOR $label 시각 버튼 높이 ${visual.height} < 52(주 CTA)');
      need(outer.width >= 48 - _kEps && outer.height >= 48 - _kEps, 'S-COLOR $label receiver ${outer.size}');
    }

    // S-COLOR 보조 행동: `취소 N건` — textPrimary 글자·grey300 외곽선·실제 receiver ≥48×48·full+hit
    void colorSecondary(String label, Rect screen) {
      final lf = richExact(label);
      need(lf.evaluate().length == 1, '$label 수 ${lf.evaluate().length}');
      final be0 = nearest(lf.evaluate().first, (w) => w is OutlinedButton);
      need(be0 != null, '$label OutlinedButton 없음');
      final be = be0!;
      final bf = fe(be);
      final mat = find.descendant(of: bf, matching: find.byType(Material)).evaluate().first;
      final shape = (mat.widget as Material).shape;
      final sideColor = shape is OutlinedBorder ? shape.side.color : null;
      final style = (be.widget as OutlinedButton).style;
      final fg = style?.foregroundColor?.resolve(<WidgetState>{});
      final side = style?.side?.resolve(<WidgetState>{});
      final textColor = ((lf.evaluate().first.widget as RichText).text as TextSpan).style?.color;
      final outer = t.getRect(bf);
      final visual = t.getRect(fe(mat));
      _out('D305-COLOR ${jsonEncode({'phase': phase, 'cond': cond, 'stage': stage, 'label': label, 'kind': 'secondary', 'styleFg': fg?.toARGB32(),
        'styleSide': side?.color.toARGB32(), 'shapeSide': sideColor?.toARGB32(), 'text': textColor?.toARGB32(), 'outer': rectL(outer),
        'visual': rectL(visual), 'visualHeight': visual.height})}');
      selVis(bf, '$label 버튼', screen);
      if (!after) return;
      need(fg == AppColors.textPrimary && textColor == AppColors.textPrimary, 'S-COLOR $label 글자 textPrimary 아님');
      need(side?.color == AppColors.grey300 && sideColor == AppColors.grey300, 'S-COLOR $label 외곽선 grey300 아님');
      need(outer.width >= 48 - _kEps && outer.height >= 48 - _kEps, 'S-COLOR $label receiver ${outer.size}');
    }

    // 확인창(DialogHelper.showConfirm, 실제 showDialog 경로): 확인 버튼 채움색 기록(after brand 단언) → 취소 버튼 finder
    Finder confirmDialog(String confirmText, Rect screen) {
      final dl = find.byType(Dialog).evaluate().where((d) => richExact(confirmText, within: fe(d)).evaluate().length == 1).toList();
      need(dl.length == 1, '확인창($confirmText) 수 ${dl.length}');
      final df = fe(dl.first);
      final ce = richExact(confirmText, within: df).evaluate().first;
      final mat = nearest(ce, (w) => w is Material);
      need(mat != null, '확인창 확인 버튼 Material 없음');
      final color = (mat!.widget as Material).color;
      final cancel = richExact('취소', within: df).evaluate().toList();
      need(cancel.length == 1, '확인창 취소 수 ${cancel.length}');
      final ink0 = nearest(cancel.first, (w) => w is InkWell);
      need(ink0 != null, '확인창 취소 InkWell 없음');
      final ink = ink0!;
      _out('D305-CONFIRM ${jsonEncode({'phase': phase, 'cond': cond, 'confirmText': confirmText, 'confirmFill': color?.toARGB32(),
        'brand': AppColors.brand.toARGB32()})}');
      if (after) need(color == AppColors.brand, '확인창 $confirmText 채움 brand 아님');
      visibleHit(fe(ink), '확인창 취소', screen);
      return fe(ink);
    }

    // S-TAB(BASE load, offset 0): 선택 탭 full·선택 index/굵은 라벨, B 가로 extent > 0, 끝 엿보기 폭, 탭 InkWell 실높이(기록)
    void tabCheck(Rect screen) {
      final tc = find.byType(TabBar);
      final tb = t.widget<TabBar>(tc);
      final idx = tb.controller?.index;
      final se = tabHScroll();
      final si = se == null ? null : posOf(se);
      final vp = se == null ? t.getRect(tc) : t.getRect(fe(se));
      final tabs = <Map<String, Object?>>[];
      double? peek;
      for (final label in const ['확인필요', '정상', '확인완료', '처리완료']) {
        final f = richExact(label, within: tc);
        need(f.evaluate().length == 1, '탭 $label 수');
        final r = t.getRect(f);
        final ink = nearest(f.evaluate().first, (w) => w is InkWell);
        final ih = ink == null ? null : t.getRect(fe(ink)).height;
        final bold = (((f.evaluate().first.widget as RichText).text as TextSpan).style?.fontWeight ?? FontWeight.normal).value >= 600;
        if (peek == null && r.left < vp.right - 0.5 && r.right > vp.right + 0.5) peek = vp.right - r.left;
        tabs.add({'label': label, 'rect': rectL(r), 'inkHeight': ih, 'bold': bold});
      }
      _out('D305-TAB ${jsonEncode({'phase': phase, 'cond': cond, 'index': idx, 'hScroll': se != null, 'pixels': si?.pixels, 'max': si?.maxScrollExtent,
        'viewport': rectL(vp), 'peek': peek, 'tabs': tabs, 'inkBelow48': tabs.where((x) => (x['inkHeight'] as double? ?? 0) < 48).map((x) => x['label']).toList()})}');
      visibleHit(richExact('확인필요', within: tc), '선택 탭 확인필요(load)', screen);
      need(idx == 0 && tabs.first['bold'] == true, 'S-TAB 선택 탭 index $idx/굵게 ${tabs.first['bold']}');
      if (isB) need(se != null && si!.maxScrollExtent > _kEps, 'S-TAB B 탭 가로 extent 0');
    }

    // ORIGIN(D305-ORIGIN): 상태마다 목표·선택 수·스크롤 pixels 를 먼저 남기고, 대상마다 실관측 또는 offset 0 투영을 쓴다.
    //   투영: ct = r.top − v.top + p, cb = r.bottom − v.top + p, 가시비율 = max(0, min(v.h, cb) − max(0, ct)) / r.h,
    //   원점 거리 = max(0, cb − v.h). 그 스크롤 창 clip 만 바뀐다고 본다(상위 clip 은 현재 관측). p > 0 이면 projected=true.
    void origin(String state, Rect screen, List<(String, Finder)> targets) {
      final recs = <Map<String, Object?>>[];
      for (final (what, f) in targets) {
        final n = f.evaluate().length;
        if (n != 1) {
          recs.add({'what': what, 'count': n, 'absent': true});
          continue;
        }
        final el = f.evaluate().first;
        final r = t.getRect(f);
        final ci = clipInfo(f, screen);
        final se = vScrollOf(el);
        Map<String, Object?> proj = {'scroll': false};
        if (se != null) {
          final v = t.getRect(fe(se));
          final p = posOf(se).pixels;
          final ct = r.top - v.top + p;
          final cb = r.bottom - v.top + p;
          final top = ct > 0 ? ct : 0.0;
          final bot = cb < v.height ? cb : v.height;
          final ratio = r.height <= 0 ? 0.0 : ((bot - top) > 0 ? (bot - top) / r.height : 0.0);
          proj = {'scroll': true, 'viewport': rectL(v), 'pixels': p, 'projected': p > _kEps, 'contentTop': ct, 'contentBottom': cb,
            'ratioAt0': ratio, 'distAt0': cb - v.height > 0 ? cb - v.height : 0.0};
        }
        recs.add({'what': what, 'rect': rectL(r), 'full': ci['full'], 'visible': ci['visible'], 'hit': f.hitTestable().evaluate().length, ...proj});
      }
      _out('D305-ORIGIN ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'state': state, 'selected': selectedBadge(),
        'top': pixelsOf(topScrollEl()), 'list': pixelsOf(listScrollEl()), 'targets': recs})}');
      // W BASE 원점(load·tab)은 R1T 와 같은 full 을 단언한다(두 phase). B 는 기록만(선택 전 발견성 잔여).
      if (scen == 'BASE' && !isB && (state == 'load' || state == 'tab')) {
        for (final x in recs) {
          if (x['absent'] == true) continue;
          need(x['full'] == true && x['hit'] == 1, 'W BASE 원점 ${x['what']} full/hit 아님');
        }
      }
    }

    Map<String, Object?> sidecar(String step, double w, double h, double s) => {'phase': phase, 'scen': scen, 'cond': cond,
      'viewport': '${w.toInt()}x${h.toInt()}', 'textScaleFactor(기기)': s, 'step': step, 'realNow': DateTime.now().toIso8601String(), 'pinDay': dayArg};

    Future<void> png(String step, double w, double h, double s) async {
      nPng++;
      budget();
      await vqCapture(t, capKey, 'D305-$phase-$cond-$step', conditions: sidecar(step, w, h, s));
    }

    Future<void> teardown() async {
      stage = 'teardown';
      await mount(const SizedBox.shrink());
      await frames(2, 'teardown');
    }

    void setView(double w, double h, double s) {
      t.view.physicalSize = Size(w, h);
      t.view.devicePixelRatio = 1.0;
      t.platformDispatcher.textScaleFactorTestValue = s;
    }

    Widget host(({AttendanceReads reads, Map<String, List<Object?>> calls, String Function() actual, String expected, void Function() freeze}) r) =>
        Scaffold(body: AttendanceStatusDialog(date: day, businessIds: const [_biz], initialBusinessId: _biz, reads: r.reads));

    // SEL: 선택 tap 뒤 사용자 drag 0 — 상단 출근·퇴근, 첫 선택 이름·receiver, 선택 확인 바(있을 때). after 단언 / before 기록.
    void selCheck(String state, Rect screen, String first, {String? bar, double? top0, double? list0}) {
      stage = state;
      final top1 = pixelsOf(topScrollEl());
      final list1 = pixelsOf(listScrollEl());
      _out('D305-SEL ${jsonEncode({'phase': phase, 'cond': cond, 'state': state, 'topBefore': top0, 'topAfter': top1, 'listBefore': list0,
        'listAfter': list1, 'selected': selectedBadge()})}');
      selVis(button(Icons.login, '출근'), '$state 상단 출근', screen);
      selVis(button(Icons.logout, '퇴근'), '$state 상단 퇴근', screen);
      selVis(nameF(first), '$state 첫 선택 $first 이름', screen);
      selVis(rowReceiver(first), '$state 첫 선택 $first receiver', screen);
      if (bar != null) selVis(richExact(bar), '$state 선택 확인 바 $bar', screen);
      if (after && scen == 'BASE' && !isB) {
        need(top0 != null && top1 != null && near(top0, top1, 0.5) && list0 != null && list1 != null && near(list0, list1, 0.5),
            'W BASE 선택 뒤 이동 top $top0→$top1 list $list0→$list1');
      }
    }

    final sw = Stopwatch()..start();
    try {
      clockGuard('start');
      need(vqEnabled, 'PNG 캡처 비활성(DU1_VQ_PHASE 없음)');
      _out('D305-ENV ${jsonEncode({'phase': phase, 'pinDay': dayArg, 'realNow': DateTime.now().toIso8601String(), 'kst': kstNow().toIso8601String(),
        'window': '$_kDay KST 08:00–21:30', 'dpr': 1.0, 'locale': 'ko_KR', 'theme': 'RoleTheme.businessAdminTheme', 'boldText': false,
        'insets': 0, 'topShare': _kTopShare, 'C': '$_kC', 'fonts': 'vqLoadFonts(번들 NotoSansKR Regular/Bold, MaterialIcons)',
        'materialIcon': materialIcon})}');

      // ═══ BASE ×4 ═══
      scen = 'BASE';
      const baseConds = [
        (id: 'W360_IN', w: 360.0, h: 780.0, s: 1.0, mode: 'IN'),
        (id: 'W360_OUT', w: 360.0, h: 780.0, s: 1.0, mode: 'OUT'),
        (id: 'B320_IN', w: 320.0, h: 640.0, s: 2.0, mode: 'IN'),
        (id: 'B320_OUT', w: 320.0, h: 640.0, s: 2.0, mode: 'OUT'),
      ];
      for (final c in baseConds) {
        cond = c.id;
        isB = c.s == 2.0;
        hostHash0 = null;
        final md = baseModes[c.mode]!;
        setView(c.w, c.h, c.s);
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);
        final r = makeReads(c.id, md.apps, md.atts, md.names);
        stage = 'load';
        await mount(app(host(r), 'D305-$phase-BASE-${c.id}'));
        await waitLoad(r);
        measure('load');
        tabCheck(screen);
        List<(String, Finder)> baseTargets() => [
              ('전체', allBox()),
              ('출근', button(Icons.login, '출근')),
              ('퇴근', button(Icons.logout, '퇴근')),
              ('탭 줄', find.byType(TabBar)),
              ('첫 카드 박포장 이름', richExact('박포장')),
              ('첫 카드 박포장 receiver', richExact('박포장').evaluate().length == 1 ? rowReceiver('박포장') : richExact('박포장')),
            ];
        origin('load', screen, baseTargets());
        stage = 'tab';
        final tabTop = topScrollEl();
        await reachV(richExact('정상', within: find.byType(TabBar)), tabTop, '정상 탭', screen);
        await tapAt(richExact('정상', within: find.byType(TabBar)), '정상 탭');
        await frames(8, 'tab');
        measure('tab');
        origin('tab', screen, baseTargets());
        stage = 'select';
        await reachV(allBox(), tabTop, '전체', screen);
        final top0 = pixelsOf(topScrollEl());
        final list0 = pixelsOf(listScrollEl());
        await tapAt(allBox(), '전체');
        await frames(8, 'select'); // 맞춤 settle(8×50ms ≥ 250ms + 1 frame)
        measure('select');
        need(selectedBadge() == '2', '선택 2건 아님 ${selectedBadge()}');
        final stepB = button(md.stepIcon, md.step);
        need(buttonCount(stepB) == '2건', '${md.step} 2건 아님 ${buttonCount(stepB)}');
        selCheck('sel', screen, '박포장', top0: top0, list0: list0);
        origin('sel', screen, baseTargets());
        await png('select', c.w, c.h, c.s); // SEL 직후·첫 수동 drag 이전
        // DU304 도달 묶음(두 phase, 기존 유효성)
        stage = 'reach';
        final topScroll = topScrollEl();
        await backTop(topScroll, '상단');
        await checkTabs(screen);
        await reachV(allBox(), topScroll, '전체', screen);
        await reachV(button(Icons.login, '출근'), topScroll, '출근', screen);
        await reachV(button(Icons.logout, '퇴근'), topScroll, '퇴근', screen);
        await reachV(button(Icons.tune, '시간 조정'), topScroll, '시간 조정', screen);
        await reachV(button(Icons.refresh, '리셋'), topScroll, '리셋', screen);
        await backTop(topScroll, '상단');
        visibleHit(richExact('정상', within: find.byType(TabBar)), '정상 탭(되돌림 뒤)', screen);
        final listScroll = vScrollOf(nameF(md.names.values.last).evaluate().first);
        await reachV(rowReceiver('박포장'), listScroll, '첫 행 박포장 receiver', screen);
        await reachV(nameF('박포장'), listScroll, '첫 행 박포장 이름', screen);
        await reachV(rowReceiver('김피킹'), listScroll, '끝 행 김피킹 receiver', screen);
        await reachV(nameF('김피킹'), listScroll, '끝 행 김피킹 이름', screen);
        need(selectedBadge() == '2', '스크롤 뒤 선택 유지 아님 ${selectedBadge()}');
        await backTop(listScroll, '목록');
        visibleHit(hostX(), 'host X', screen);
        visibleHit(richExact('당일명단'), '머리 제목', screen);
        // 가독성·footer 계약
        statsCheck('read');
        headersCheck('read', screen);
        footerCheck('read', screen);
        measure('read');
        await teardown();
        visited.add('BASE:${c.id}');
      }

      // ═══ LONG ×2 ═══
      scen = 'LONG';
      const longConds = [
        (id: 'W360_L', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320_L', w: 320.0, h: 640.0, s: 2.0),
      ];
      for (final c in longConds) {
        cond = c.id;
        isB = c.s == 2.0;
        hostHash0 = null;
        setView(c.w, c.h, c.s);
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);
        final r = makeReads(c.id, longApps, longAtts, longNames);
        stage = 'load';
        await mount(app(host(r), 'D305-$phase-LONG-${c.id}'));
        await waitLoad(r);
        measure('load');
        // 검토 탭(초기): 빠른 선택 칩 → 검토01 선택
        stage = 'review';
        final topScroll0 = topScrollEl();
        await reachV(richExact('미출근 1건'), topScroll0, '칩 미출근 1건', screen);
        await reachV(richExact('퇴근미기록 1건'), topScroll0, '칩 퇴근미기록 1건', screen);
        await reachV(richExact('미출근 1건'), topScroll0, '칩 미출근 1건(tap 직전)', screen);
        final ct0 = pixelsOf(topScrollEl());
        final cl0 = pixelsOf(listScrollEl());
        await tapAt(richExact('미출근 1건'), '칩 미출근 1건');
        await frames(8, 'chip');
        stage = 'chip';
        measure('chip');
        need(selectedBadge() == '1', '칩 선택 1 아님 ${selectedBadge()}');
        need(buttonCount(button(Icons.login, '출근')) == '1건', '출근 1건 아님');
        selCheck('chipSel', screen, '검토01', top0: ct0, list0: cl0);
        origin('chipSel', screen, [
          ('출근', button(Icons.login, '출근')),
          ('퇴근', button(Icons.logout, '퇴근')),
          ('검토01 이름', nameF('검토01')),
          ('검토01 receiver', rowReceiver('검토01')),
        ]);
        stage = 'chip';
        await reachV(button(Icons.login, '출근'), topScroll0, '출근(1건)', screen);
        await reachV(button(Icons.logout, '퇴근'), topScroll0, '퇴근', screen);
        await reachV(button(Icons.tune, '시간 조정'), topScroll0, '시간 조정', screen);
        await reachV(button(Icons.refresh, '리셋'), topScroll0, '리셋', screen);
        await backTop(topScroll0, '상단');
        await checkTabs(screen);
        final rvScroll = vScrollOf(nameF('검토01').evaluate().first);
        await reachV(rowReceiver('검토01'), rvScroll, '검토 첫 행 검토01 receiver', screen);
        await reachV(nameF('검토01'), rvScroll, '검토 첫 행 검토01 이름', screen);
        await reachV(rowReceiver('검토02'), rvScroll, '검토 끝 행 검토02 receiver', screen);
        await reachV(nameF('검토02'), rvScroll, '검토 끝 행 검토02 이름', screen);
        await backTop(rvScroll, '검토 목록');
        rowTimeCheck('검토02', '06:00', range: false);
        headersCheck('reviewRead', screen);
        // 정상 탭: 탭 전환은 선택을 초기화한다
        stage = 'tab';
        await reachV(richExact('정상', within: find.byType(TabBar)), topScroll0, '정상 탭', screen);
        await tapAt(richExact('정상', within: find.byType(TabBar)), '정상 탭');
        await frames(8, 'tab');
        measure('tab');
        need(selectedBadge() == null, '탭 전환 뒤 선택이 남음 ${selectedBadge()}');
        need(buttonCount(button(Icons.login, '출근')) == null, '탭 전환 뒤 버튼 건수가 남음');
        // 전체 선택: 정상 14명 → 선택 확인 바(근태 확인 2건 = 하차 2명)
        stage = 'select';
        await reachV(allBox(), topScroll0, '전체', screen);
        final st0 = pixelsOf(topScrollEl());
        final sl0 = pixelsOf(listScrollEl());
        await tapAt(allBox(), '전체');
        await frames(8, 'select');
        final sel = measure('select');
        need(selectedBadge() == '14', '선택 14 아님 ${selectedBadge()}');
        need((sel['listScroll'] as Map)['present'] == true && ((sel['listScroll'] as Map)['max'] as double) > _kEps, '목록 스크롤 범위 0(fixture 부족)');
        selCheck('sel', screen, '포장01', bar: '근태 확인 2건', top0: st0, list0: sl0);
        origin('sel', screen, [
          ('출근', button(Icons.login, '출근')),
          ('퇴근', button(Icons.logout, '퇴근')),
          ('포장01 이름', nameF('포장01')),
          ('포장01 receiver', rowReceiver('포장01')),
          ('선택 확인 바', richExact('근태 확인 2건')),
        ]);
        stage = 'select';
        colorPrimary('근태 확인 2건', screen);
        visibleHit(hostX(), 'host X', screen);
        visibleHit(richExact('당일명단'), '머리 제목', screen);
        await png('select', c.w, c.h, c.s);
        footerCheck('selectRead', screen);
        statsCheck('selectRead');
        headersCheck('selectRead', screen);
        rowTimeCheck('하차01', '06:00 ~ 07:00', range: true);
        rowTimeCheck('하차02', '06:00 ~ 07:00', range: true);
        if (isB) {
          // B320_L: 근태 확인 확인창 열기 → 색 기록 → 확인창 취소(업무 writer 0) → 선택 14 유지
          stage = 'confirm';
          nConfirmOpen++;
          budget();
          await tapAt(richExact('근태 확인 2건'), '근태 확인 2건');
          await frames(6, 'confirm');
          final cancel = confirmDialog('근태 확인', screen);
          await tapAt(cancel, '확인창 취소');
          await frames(6, 'confirmClose');
          need(find.byType(Dialog).evaluate().where((d) => richExact('근태 확인', within: fe(d)).evaluate().isNotEmpty).isEmpty, '확인창 닫힘 실패');
          need(selectedBadge() == '14', '확인창 취소 뒤 선택 14 아님 ${selectedBadge()}');
        }
        // END: 상단 되돌림 → 목록 첫·끝 도달(DU304 유지) → 하차02 해제·재선택 → 상단 맞춤·목록 그대로
        stage = 'end';
        final topScroll1 = topScrollEl();
        await backTop(topScroll1, '상단(END)');
        final listScroll = vScrollOf(nameF('포장01').evaluate().first);
        await reachV(rowReceiver('포장01'), listScroll, '첫 행 포장01 receiver', screen);
        await reachV(nameF('포장01'), listScroll, '첫 행 포장01 이름', screen);
        await reachV(rowReceiver('하차02'), listScroll, '끝 행 하차02 receiver', screen);
        await reachV(nameF('하차02'), listScroll, '끝 행 하차02 이름', screen);
        final et0 = pixelsOf(topScrollEl());
        final el0 = pixelsOf(listScrollEl());
        await tapAt(rowReceiver('하차02'), '하차02 해제');
        await frames(2, 'end:off');
        need(selectedBadge() == '13', '하차02 해제 뒤 선택 13 아님 ${selectedBadge()}');
        await tapAt(rowReceiver('하차02'), '하차02 재선택');
        await frames(8, 'end:on');
        need(selectedBadge() == '14', '재선택 뒤 선택 14 아님 ${selectedBadge()}');
        final et1 = pixelsOf(topScrollEl());
        final el1 = pixelsOf(listScrollEl());
        _out('D305-END-STATE ${jsonEncode({'phase': phase, 'cond': cond, 'topBefore': et0, 'topAfter': et1, 'listBefore': el0, 'listAfter': el1})}');
        selVis(button(Icons.logout, '퇴근'), 'END 상단 퇴근', screen);
        selVis(nameF('하차02'), 'END 하차02 이름', screen);
        selVis(rowReceiver('하차02'), 'END 하차02 receiver', screen);
        selVis(richExact('근태 확인 2건'), 'END 선택 확인 바', screen);
        if (after) need(el0 != null && el1 != null && near(el0, el1, 0.5), 'END 목록 이동 $el0→$el1 > 0.5');
        origin('end', screen, [
          ('퇴근', button(Icons.logout, '퇴근')),
          ('하차02 이름', nameF('하차02')),
          ('하차02 receiver', rowReceiver('하차02')),
        ]);
        measure('listEnd');
        await png('listEnd', c.w, c.h, c.s);
        await backTop(topScrollEl(), '상단');
        // 검색: focus·입력·필터·선택 유지·닫기·복원(inset 0, 키보드 미관측) — DU304 그대로
        stage = 'search';
        final topScroll2 = topScrollEl();
        await reachV(searchBox(), topScroll2, '검색 버튼', screen);
        await tapAt(searchBox(), '검색 열기');
        await frames(2, 'search');
        final field = find.byType(TextField);
        need(field.evaluate().length == 1, '검색창 수 ${field.evaluate().length}');
        await reachV(field, topScroll2, '검색창', screen);
        nText++;
        budget();
        await t.enterText(field, '피킹03');
        guard('enterText');
        await frames(4, 'search');
        final shown = find.descendant(of: find.byType(TabBarView), matching: find.byType(AppCheckbox)).evaluate().length;
        _out('D305-SEARCH ${jsonEncode({'phase': phase, 'cond': cond, 'query': '피킹03', 'checkboxes': shown, 'badge': selectedBadge(),
          'viewInsets': MediaQuery.of(t.element(field)).viewInsets.bottom})}');
        need(richExact('피킹03').evaluate().length == 1 && richExact('포장01').evaluate().isEmpty && richExact('하차02').evaluate().isEmpty, '검색 필터 결과 아님');
        need(selectedBadge() == '14', '검색 중 선택 유지 아님 ${selectedBadge()}');
        measure('search');
        await reachV(searchBox(), topScroll2, '검색 닫기 버튼', screen);
        await tapAt(searchBox(), '검색 닫기');
        await frames(4, 'searchClose');
        need(find.byType(TextField).evaluate().isEmpty, '검색창 남음');
        need(richExact('포장01').evaluate().length == 1 && richExact('하차02').evaluate().length == 1, '검색 닫기 뒤 목록 복원 아님');
        need(selectedBadge() == '14', '검색 닫기 뒤 선택 유지 아님 ${selectedBadge()}');
        measure('searchClosed');
        await teardown();
        visited.add('LONG:${c.id}');
      }

      // ═══ ROUTE ×2: 실제 showDialog<bool>(barrierDismissible: false) → host X → popped=true/result=false ═══
      scen = 'ROUTE';
      const routeConds = [
        (id: 'W360_R', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320_R', w: 320.0, h: 640.0, s: 2.0),
      ];
      for (final c in routeConds) {
        cond = c.id;
        isB = c.s == 2.0;
        hostHash0 = null;
        setView(c.w, c.h, c.s);
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);
        final md = baseModes['IN']!;
        final r = makeReads(c.id, md.apps, md.atts, md.names);
        var routePopped = false;
        Object? routeResult = 'unset';
        stage = 'launcher';
        await mount(app(
            Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog<bool>(
                        context: ctx,
                        barrierDismissible: false,
                        builder: (_) => AttendanceStatusDialog(date: day, businessIds: const [_biz], initialBusinessId: _biz, reads: r.reads),
                      ).then((v) {
                        routePopped = true;
                        routeResult = v;
                      });
                    },
                    child: const Text('DU305 열기'),
                  ),
                ),
              ),
            ),
            'D305-$phase-ROUTE-${c.id}'));
        nHostOpen++;
        budget();
        await tapAt(find.text('DU305 열기'), 'route 열기');
        stage = 'load';
        await waitLoad(r);
        measure('route');
        visibleHit(hostX(), 'host X', screen);
        stage = 'close';
        await tapAt(hostX(), 'host X');
        for (var i = 0; i < 8 && find.byType(AttendanceStatusDialog).evaluate().isNotEmpty; i++) {
          await frames(1, 'close');
        }
        await frames(2, 'close:settle');
        need(find.byType(AttendanceStatusDialog).evaluate().isEmpty, 'host 닫힘 실패');
        need(routePopped && routeResult == false, 'host route 반환 $routePopped/$routeResult(false 여야 함)');
        _out('D305-ROUTE ${jsonEncode({'phase': phase, 'cond': cond, 'popped': routePopped, 'result': routeResult})}');
        await teardown();
        visited.add('ROUTE:${c.id}');
      }

      // ═══ EDGE ×2(320×640 · 1.3/2.0): 세 업무 아이콘 경로의 머리·통계, E320_20 만 정렬 순환·확인완료 `취소 1건` ═══
      scen = 'EDGE';
      const edgeConds = [
        (id: 'E320_13', w: 320.0, h: 640.0, s: 1.3, conf: false),
        (id: 'E320_20', w: 320.0, h: 640.0, s: 2.0, conf: true),
      ];
      for (final c in edgeConds) {
        cond = c.id;
        isB = true;
        hostHash0 = null;
        setView(c.w, c.h, c.s);
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);
        final apps = [...edgeApps, if (c.conf) edgeConfApp];
        final atts = <Map<String, dynamic>>[if (c.conf) edgeConfAtt];
        final r = makeReads(c.id, apps, atts, edgeNames, wt: edgeWt);
        stage = 'load';
        await mount(app(host(r), 'D305-$phase-EDGE-${c.id}'));
        await waitLoad(r);
        measure('load');
        stage = 'tab';
        final topScroll = topScrollEl();
        await reachV(richExact('정상', within: find.byType(TabBar)), topScroll, '정상 탭', screen);
        await tapAt(richExact('정상', within: find.byType(TabBar)), '정상 탭');
        await frames(8, 'tab');
        measure('tab');
        statsCheck('edgeRead');
        stage = 'groups';
        final listScroll = listScrollEl();
        for (final g in const ['포장', '피킹', '하차']) {
          final hs = headers().where((h) => h.title == g).toList();
          need(hs.length == 1, 'EDGE 머리 $g 수 ${hs.length}');
          await reachV(fe(hs.first.badgeChip), listScroll, '머리 $g 배지', screen);
          final h2 = headers().where((h) => h.title == g).toList();
          selVis(fe(h2.first.sortChip), '머리 $g 정렬 칩', screen);
        }
        headersCheck('edgeRead', screen);
        await backTop(listScroll, '목록');
        await png('layout', c.w, c.h, c.s);
        if (c.conf) {
          // 첫 그룹(포장) 정렬 칩 3 tap 순환: 상태순 → 배지순 → 이름순 → 상태순
          stage = 'sort';
          final first = headers().where((h) => h.title == '포장').toList();
          need(first.length == 1, 'EDGE 포장 머리 수');
          await reachV(fe(first.first.sortChip), listScroll, '포장 정렬 칩', screen);
          for (final want in const ['배지순', '이름순', '상태순']) {
            final hh = headers().where((h) => h.title == '포장').toList();
            await tapAt(fe(hh.first.sortChip), '포장 정렬 칩');
            await frames(2, 'sort');
            final now = headers().where((h) => h.title == '포장').toList();
            final lab = find.descendant(of: fe(now.first.sortChip), matching: find.byType(RichText)).evaluate().map(plainOf)
                .where(_sortLabels.contains).toList();
            need(lab.length == 1 && lab.first == want, '정렬 순환 $lab ≠ $want');
          }
          // 확인완료 한 대상 가로 도달(≤2 drag) → tap → 전체 → `취소 1건` 측정 → 확인창 열기·색 기록 → 확인창 취소
          stage = 'confirmedTab';
          await reachTab('확인완료', screen);
          await tapAt(richExact('확인완료', within: find.byType(TabBar)), '확인완료 탭');
          await frames(8, 'confirmedTab');
          measure('confirmedTab');
          need(selectedBadge() == null, '확인완료 탭 선택 0 아님');
          await reachV(allBox(), topScrollEl(), '전체(확인완료)', screen);
          await tapAt(allBox(), '전체(확인완료)');
          await frames(8, 'confirmedSelect');
          need(selectedBadge() == '1', '확인완료 선택 1 아님 ${selectedBadge()}');
          stage = 'cancelColor';
          colorSecondary('취소 1건', screen);
          nConfirmOpen++;
          budget();
          await tapAt(richExact('취소 1건'), '취소 1건');
          await frames(6, 'cancelConfirm');
          final cancel = confirmDialog('취소 처리', screen);
          await tapAt(cancel, '확인창 취소');
          await frames(6, 'cancelConfirmClose');
          need(find.byType(Dialog).evaluate().where((d) => richExact('취소 처리', within: fe(d)).evaluate().isNotEmpty).isEmpty, '확인창 닫힘 실패');
          need(selectedBadge() == '1', '확인창 취소 뒤 선택 1 아님 ${selectedBadge()}');
          measure('cancelClosed');
        }
        await teardown();
        visited.add('EDGE:${c.id}');
      }

      const want = 'BASE:W360_IN|BASE:W360_OUT|BASE:B320_IN|BASE:B320_OUT|LONG:W360_L|LONG:B320_L|ROUTE:W360_R|ROUTE:B320_R|EDGE:E320_13|EDGE:E320_20';
      need(visited.join('|') == want, '방문 $visited');
      need(prevSeen.length == _kPrevVis.length, 'S1 W rect 대조 누락 ${_kPrevVis.keys.where((k) => !prevSeen.contains(k)).toList()}');
      need(nPng == _kPng && nHostOpen == 2 && nConfirmOpen == 2 && nHostOpen + nConfirmOpen == _kRoute && nText == 2, '실행량 ${counts()}');
      clockGuard('end');
      // 성공 완료의 최종 단언(마지막 teardown 뒤): HTTP 0·업무 채널 {}·동결 뒤 Reads []·대기 오류 0·화면 해제
      need(net.created == 0 && biz.isEmpty && afterFreeze.isEmpty && errors.isEmpty && !live,
          '최종 상태 http=${net.created} business=$biz reads=$afterFreeze pending=${errors.length} live=$live');
      _out('D305-END ${jsonEncode({...counts(), 'visited': visited, 'http': net.created, 'business': biz, 'readsAfterFreeze': afterFreeze,
        'errors': errLog.length, 'elapsedMs': sw.elapsedMilliseconds})}');
      completed = true;
    } finally {
      // 실패 정리: 아직 mount 돼 있으면(중간 stop·예외) 유한 teardown(mount 1 + pump 2)을 한 번 시도한다.
      //   원 실패를 덮지 않도록 여기서는 need/stop/fail 을 부르지 않고 결과·정리 중 오류를 FINAL 에만 남긴다.
      var cleanup = 'not-needed';
      var cleanMount = 0, cleanPump = 0;
      final cleanErrors = <String>[];
      for (final e in errors) {
        cleanErrors.add('pending-before-cleanup ${e.cond}/${e.stage}#${e.pump}: ${e.first}');
      }
      errors.clear();
      if (live) {
        stage = 'cleanup';
        try {
          cleanMount++;
          await t.pumpWidget(const SizedBox.shrink());
          live = false;
          for (var i = 0; i < 2; i++) {
            cleanPump++;
            await t.pump(const Duration(milliseconds: 50));
          }
          final ex = t.takeException();
          if (ex != null) cleanErrors.add('cleanup-exception $ex');
          cleanup = 'done';
        } catch (e) {
          cleanup = 'failed $e';
        }
        for (final e in errors) {
          cleanErrors.add('during-cleanup ${e.cond}/${e.stage}#${e.pump}: ${e.first}');
        }
      }
      _out('D305-FINAL ${jsonEncode({...counts(), 'outcome': completed ? 'completed' : 'failed', 'cleanup': cleanup,
        'cleanupMount': cleanMount, 'cleanupPump': cleanPump, 'stillMounted': live, 'visited': visited, 'http': net.created,
        'business': biz, 'readsAfterFreeze': afterFreeze, 'errorsLogged': errLog.length, 'cleanupErrors': cleanErrors,
        'elapsedMs': sw.elapsedMilliseconds})}');
      for (final op in _fsOps) {
        m.setMockMessageHandler('$_fsBase.$op', null);
      }
      for (final op in _fnOps) {
        m.setMockMessageHandler('$_fnBase.$op', null);
      }
      m.setMockMethodCallHandler(const MethodChannel(_fnLegacy), null);
      FlutterError.onError = prevOnError;
      HttpOverrides.global = prevHttp;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
      sem.dispose();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
