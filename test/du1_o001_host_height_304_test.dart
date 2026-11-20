// ignore_for_file: depend_on_referenced_packages
// [DU304 DU-O001-HOST-HEIGHT] 당일명단 host 높이 배분(1안: 상단 상한 0.5 + 넘칠 때만 상단 스크롤) — before/after.
//   근거: reports/DU_audit_304.md §3·§5, requests/DU_prep_304_r1.md. production 편집 0(시험은 관측만).
//   DU304_RUN=1, DU304_PHASE=before|after, DU304_DAY=YYYY-MM-DD(실행일 KST, 시작 때 한 번 pin) 일 때만 실행한다(기본 skip).
//   BASE(두 phase): DU303 과 같은 fixture·직접 mount(W360×780/1.0·B320×640/2.0 × IN·OUT)의 load → 정상 탭 → 전체 선택.
//     before 수치는 기존 원자료(DU303 TAR3 D303-HOST)에만 잇는다: W 분할 고정값, B 넘침 27.85/22.75/96.25·목록 0.
//     before 의 B 행·버튼 도달은 이미 알려진 결함이라 성공 도달로 요구하지 않는다(기록만).
//   LONG·ROUTE(after 전용): 검토 빠른 선택 칩·긴 목록·조건부 선택 확인 바·검색, 그리고 실제 showDialog route 의 host X 닫힘(false).
//   실제 tap/drag/enterText 만 쓴다. 값 주입·강제 tap·Navigator 직접 호출·pumpAndSettle·scrollUntilVisible·ensureVisible·jumpTo 0.
//   오류는 mount~teardown 연속 수집하고 매 pump·행동 뒤 분류한다. 허용은 before B 의 host :1186 load 최초 1건뿐이다.
import 'dart:convert';
import 'dart:io';

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
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/common/app_checkbox.dart';
import 'package:ALfit/widgets/dialogs/styled_dialog.dart';

import 'support/du1_vq_capture.dart';

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
    throw StateError('DU304 network guard');
  }
}

void _out(String l) {
  // ignore: avoid_print
  print(l);
}

const _biz = 'biz303'; // BASE 는 DU303 fixture 를 그대로 쓴다(기존 원자료와 같은 화면)
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
const _hostLine = 1186; // 원본 host Column(before 오류 소유 줄)
const _kTopShare = 0.5; // 후보 상한 비율(감사304 §3 고정, 자동 조정 0)
// 기존 원자료(DU303 TAR3 D303-HOST, 원본 host) — BASE 에만 쓴다
const _kWH = 569.2;
const _kBH = 325.4;
const _kBaseW = <String, ({double top, double list})>{
  'load': (top: 239.9, list: 329.3),
  'tab': (top: 234.49999999999997, list: 334.70000000000005),
  'select': (top: 273.9, list: 295.30000000000007),
};
const _kBaseB = <String, ({double top, double over})>{
  'load': (top: 353.25000000000006, over: 27.85000000000008),
  'tab': (top: 348.15000000000003, over: 22.750000000000057),
  'select': (top: 421.65000000000003, over: 96.25000000000006),
};

Map<String, dynamic> _ts(DateTime d) => {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

void main() {
  final phase = Platform.environment['DU304_PHASE'] ?? '';
  final dayArg = Platform.environment['DU304_DAY'] ?? '';
  final run = Platform.environment['DU304_RUN'] == '1' && (phase == 'before' || phase == 'after') &&
      RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(dayArg);
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    if (!run) return;
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('D304 $phase', (t) async {
    // ── 실행일 pin: DU304_DAY 를 시작 때 한 번 고정한다(이후 today 재계산으로 바꾸지 않는다) ──
    final dp = dayArg.split('-').map(int.parse).toList();
    final day = DateTime(dp[0], dp[1], dp[2]);
    final dayKey = FormatHelper.kstDayKeyOfCivil(day);
    DateTime kstNow() => DateTime.now().toUtc().add(const Duration(hours: 9));

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
        return const StandardMessageCodec().encodeMessage(<Object?>['du304-blocked', 'firestore $op 차단', null]);
      });
    }
    for (final op in _fnOps) {
      m.setMockMessageHandler('$_fnBase.$op', (msg) async {
        biz['fn.$op'] = (biz['fn.$op'] ?? 0) + 1;
        return const StandardMessageCodec().encodeMessage(<Object?>['du304-blocked', 'functions $op 차단', null]);
      });
    }
    m.setMockMethodCallHandler(const MethodChannel(_fnLegacy), (call) async {
      biz['fn.legacy.${call.method}'] = (biz['fn.legacy.${call.method}'] ?? 0) + 1;
      throw PlatformException(code: 'du304-blocked', message: 'functions legacy ${call.method} 차단');
    });

    // 실행량(phase 상한 — 보고 §6 표와 같다. 각 bounded drag 의 최대 횟수를 모두 쓴 경우의 합)
    //   before: mount ≤8·pump+mount ≤240·tap ≤12·drag ≤38·route open 0·enterText 0·PNG ≤4
    //   after : mount ≤16·pump+mount ≤1060·tap ≤24·drag ≤262·route open ≤2·enterText ≤2·PNG ≤8
    //   (enterText 안의 showKeyboard pump·idle 는 nPump 에 들지 않는다 — enterText 1회로 센다)
    //   실패 정리(finally, 실패 때만): mount ≤1·pump ≤2 를 따로 센다(budget 밖 — 원 실패를 덮지 않으려고 중단 검사를 하지 않는다)
    var nPump = 0, nMount = 0, nTap = 0, nDrag = 0, nOpen = 0, nText = 0, nPng = 0;
    Map<String, Object?> counts() => {'phase': phase, 'pump': nPump, 'mount': nMount, 'pumpMount': nPump + nMount, 'tap': nTap,
      'drag': nDrag, 'routeOpen': nOpen, 'enterText': nText, 'png': nPng};

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
    var hostErrCount = 0; // mount 마다 host 최초 보고 수(before B 만 1 허용)
    final visited = <String>[];
    var live = false; // 화면이 mount 돼 있다(teardown 의 SizedBox mount 뒤 false) — 실패 정리 판단용
    var completed = false; // 모든 단계와 최종 단언을 통과했다

    Never stop(String why) {
      _out('D304-STOP ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'stage': stage, 'why': why,
        'pendingErrors': errors.map((e) => '${e.cond}/${e.stage}#${e.pump}: ${e.first}').toList(), 'counts': counts(),
        'http': net.created, 'business': biz, 'readsAfterFreeze': afterFreeze})}');
      for (final e in errors) {
        _out('D304-STOPERR ${jsonEncode({'cond': e.cond, 'stage': e.stage, 'pump': e.pump, 'full': e.full})}');
      }
      fail('$phase/$scen/$cond/$stage: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    void budget() {
      final ok = after
          ? nMount <= 16 && nPump + nMount <= 1060 && nTap <= 24 && nDrag <= 262 && nOpen <= 2 && nText <= 2 && nPng <= 8
          : nMount <= 8 && nPump + nMount <= 240 && nTap <= 12 && nDrag <= 38 && nOpen == 0 && nText == 0 && nPng <= 4;
      need(ok, '한도 ${counts()}');
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

    // host `_buildContent` Column = TabBar 위로 두 번째 Column(원본 :1186, 후보에서도 같은 순서 — 첫째는 상단 Column :1194)
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

    // 상단 Column(:1194)과 그 Padding(:1190) — 자연 높이 T
    Element? topColEl() {
      final tb = find.byType(TabBar).evaluate();
      if (tb.length != 1) return null;
      return nearest(tb.first, (w) => w is Column);
    }

    // 셸 Column(styled_dialog :930) = AppModalShell 아래 첫 Column
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

    Map<String, Object?> scrollInfo(Element? se) {
      if (se == null) return {'present': false};
      final pos = ((se as StatefulElement).state as ScrollableState).position;
      return {'present': true, 'pixels': pos.pixels, 'min': pos.minScrollExtent, 'max': pos.maxScrollExtent, 'viewport': pos.viewportDimension,
        'rect': rectL(t.getRect(fe(se)))};
    }

    // 실제 paint clip chain — DU303 t8 의 정확 지원범위(계획 v4 §2)에 **RenderViewport 조건부 1개**를 더했다(보고 r1 §4 판정 대상):
    //   목록 행은 TabBarView(PageView) 의 RenderViewport 아래에 있다. 그 describe 는 자식 sliver 의 overlap == 0 이고
    //   viewportMainAxisExtent 가 유한이면 정확히 Offset.zero & size 다(SDK viewport.dart:738–763). paint 는 넘칠 때 같은 사각을
    //   clip 하고(:821–832), 넘치지 않으면 자식이 창 안이라 교차해도 가시 영역이 줄지 않는다(보수적). 그 밖 조건의 Viewport 는 지원 밖이다.
    //   지원 밖 clip 은 unsupported 로 남기고 중단 대상
    const rectClipTypes = <String>{
      'RenderFlex', 'RenderConstraintsTransformBox', 'RenderStack', 'RenderIndexedStack', '_RenderTheater', '_RenderSingleChildViewport',
      'RenderClipRect',
    };
    Map<String, Object?> clipInfo(Finder f, Rect screen) {
      final ro = t.renderObject(f);
      if (ro is! RenderBox) return {'supported': false, 'reason': 'RenderBox 아님 ${ro.runtimeType}', 'full': false, 'unsupported': ['not-box']};
      final rect = MatrixUtils.transformRect(ro.getTransformTo(null), Offset.zero & ro.size);
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

    // 매 pump·mount·행동 뒤: 예외·오류 분류(before B host load 최초 1건만 허용)·네트워크/업무 채널·동결 뒤 Reads
    void guard(String where) {
      final ex = t.takeException();
      need(ex == null, '$where 예외: $ex');
      final he = hostEl();
      final host = he?.renderObject;
      final hostHash = host is RenderFlex ? shortHash(host) : null;
      for (final e in errors) {
        final o = owner(e.first, e.full);
        var kind = 'OTHER';
        double? raw;
        var ok = false;
        if (o.dir == 'bottom' && o.lines.contains(_hostLine) && o.hash != null && o.hash == hostHash && host is RenderFlex) {
          kind = 'host:1186';
          raw = flexInfo(host)['over'] as double;
          ok = !after && isB && scen == 'BASE' && e.stage == 'load' && o.val == '28' && near(raw, _kBaseB['load']!.over, _kTol) && hostErrCount == 0;
          if (ok) hostErrCount++;
        }
        final r = {'phase': phase, 'scen': scen, 'cond': e.cond, 'stage': e.stage, 'pump': e.pump, 'first': e.first, 'dir': o.dir, 'val': o.val,
          'ownerLines': o.lines, 'hash': o.hash, 'kind': kind, 'raw': raw, 'allowed': ok, 'full': e.full};
        errLog.add(r);
        _out('D304-ERR ${jsonEncode(r)}');
        if (!ok) stop('예외표 밖 오류 $kind ${e.first} raw $raw at $where');
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
    Map<String, dynamic> attMap(String id, String appId, String uid, String checkIn, {String? checkOut}) => {
          'id': id, 'applicationId': appId, 'uid': uid, 'businessId': _biz, 'status': 'present', 'checkIn': checkIn,
          if (checkOut != null) 'checkOut': checkOut,
          'workDate': _ts(dayKey), 'createdAt': _ts(dayKey),
        };
    final up = UserProvider()..debugSetCurrentUser(user('owner303', 'DU303 사장', UserRole.BUSINESS_ADMIN));
    final (ds, de) = FormatHelper.kstDayRange(dayKey);

    // ── fixture ──
    // BASE(DU303 t8 와 같은 값): IN = 22:00/22:30 시작·근태 없음, OUT = 06:00/07:00 출근·23:00/23:30 퇴근 예정.
    //   실제 시각 08:00–21:30 에서 둘 다 정상 탭(검토 0)이다. 이름순이 아니라 업무명순 그룹이라 목록은 포장(박포장) → 피킹(김피킹).
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
    // LONG(after 전용): 검토 2(rv-01 미출근 = 시작 06:00 지남·근태 없음, rv-02 = 06:00 출근·종료 07:30 지남·퇴근 없음 → 퇴근미기록),
    //   정상 14(포장 6·피킹 6 = 22:00 시작 미출근, 하차 2 = 06:00–07:00 정시 출퇴근 → 근태 확인 대상).
    //   정상 탭 목록 순서(업무명 → 상태 → 이름): 포장01–06 → 피킹01–06 → 하차01–02. 첫 = 포장01, 끝 = 하차02.
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

    // ── Reads 대역·사전표(9함수 10호출) — mount 마다 새로 만든다 ──
    ({AttendanceReads reads, Map<String, List<Object?>> calls, String Function() actual, String expected, void Function() freeze})
        makeReads(String tag, List<Map<String, dynamic>> apps, List<Map<String, dynamic>> atts, Map<String, String> names) {
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
          return const {};
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
      _out('D304-READS ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'actual': r.calls, 'match': match})}');
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

    // 화면 안·clip 전부·중심 hit 를 같은 frame 에서 본다(단언 전 출력)
    void visibleHit(Finder f, String what, Rect screen) {
      need(f.evaluate().length == 1, '$what 대상 수 ${f.evaluate().length}');
      final ci = clipInfo(f, screen);
      final hit = f.hitTestable().evaluate().length;
      _out('D304-VIS ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'stage': stage, 'what': what, 'hit': hit, ...ci})}');
      need((ci['unsupported'] as List).isEmpty, '$what 지원 밖 clip ${ci['unsupported']}');
      need(ci['full'] == true && hit == 1, '$what 가시/hit 아님 full=${ci['full']} hit=$hit');
    }

    // bounded 세로 drag: 대상이 스크롤 창 밖이면 창 중심에서 요청 거리만큼, 대상마다 최대 2회. 그래도 밖이면 중단.
    //   [DU304 수리 r1 — requests/DU_repair_304.md §1] 요청 거리 = d + a, a = max(0, min(16, (창 높이 − 대상 높이)/2)).
    //   첫 시도의 요청량과 요청 방향 실제 이동(pixels)의 차를 재고, 그 차가 0..20 이며 extent 끝 clamp·반대 방향·
    //   레이아웃 변화(maxScrollExtent 변화)가 없을 때만 둘째 시도에 보정 c 로 더한다(그 밖은 c = 0). 요청·이동·차·보정은 D304-REACH 에 남긴다.
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
        final dy = below ? -req : req;
        final pos = ((se! as StatefulElement).state as ScrollableState).position;
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
        _out('D304-REACH ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'what': what, 'axis': 'v', 'try': i, 'start': [vp.center.dx, vp.center.dy],
          'd': d, 'a': a, 'c': c, 'req': req, 'dy': dy, 'before': p0, 'after': p1, 'moved': moved, 'diff': diff, 'clamped': clamped,
          'layoutChanged': layoutChanged, 'nextCorrection': i == 0 ? (usable ? diff : 0.0) : null, 'max': pos.maxScrollExtent})}');
      }
      visibleHit(target, what, screen);
    }

    // 되돌림: 세로 스크롤을 0 으로(창 중심에서 pixels + slop + 16 아래로, 최대 2회)
    Future<void> backTop(Element? se, String what) async {
      if (se == null) return;
      for (var i = 0; i < 2; i++) {
        final pos = ((se as StatefulElement).state as ScrollableState).position;
        if (pos.pixels <= _kEps) return;
        final vp = t.getRect(fe(se));
        final p0 = pos.pixels;
        nDrag++;
        budget();
        await t.dragFrom(vp.center, Offset(0, p0 + kDragSlopDefault + 16));
        guard('back:$what');
        await frames(3, 'back:$what');
        _out('D304-REACH ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'what': 'back:$what', 'axis': 'v', 'try': i, 'before': p0, 'after': pos.pixels})}');
      }
      final pos = ((se as StatefulElement).state as ScrollableState).position;
      need(pos.pixels <= _kEps, '$what 되돌림 실패 ${pos.pixels}');
    }

    // 탭 4개: TabBar 가 가로 스크롤이면 bounded 가로 drag(대상마다 최대 2회) 뒤 가시·hit, 끝나면 처음으로 되돌린다
    Future<void> checkTabs(Rect screen) async {
      final hs = find.descendant(of: find.byType(TabBar), matching: find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right))
          .evaluate().toList();
      final se = hs.isEmpty ? null : hs.first;
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
          final pos = ((se! as StatefulElement).state as ScrollableState).position;
          _out('D304-REACH ${jsonEncode({'phase': phase, 'scen': scen, 'cond': cond, 'what': 'tab:$label', 'axis': 'h', 'try': i, 'dx': dx, 'after': pos.pixels})}');
        }
        visibleHit(f, '탭 $label', screen);
      }
      if (se != null) {
        final pos = ((se as StatefulElement).state as ScrollableState).position;
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

    // ── 기하 기록·단언(단언 전에 D304-HOST 출력) ──
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
      final names = find.descendant(of: find.byType(TabBarView), matching: find.byType(RichText)).evaluate().toList();
      final listScroll = names.isEmpty ? null : vScrollOf(names.first);
      final hRaw = hf.constraints.maxHeight;
      final rec = {'phase': phase, 'scen': scen, 'cond': cond, 'tag': tag, 'pump': nPump, 'H': hRaw.isFinite ? hRaw : 'inf', 'T': topT,
        'topViewport': kids.isEmpty ? null : kids.first, 'list': kids.length < 2 ? null : kids[1], 'host': hi, 'shell': shi,
        'topScroll': scrollInfo(topScroll), 'listScroll': scrollInfo(listScroll), 'selectedBadge': selectedBadge()};
      _out('D304-HOST ${jsonEncode(rec)}');
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
      if (scen == 'BASE' && !after) {
        if (!isB) {
          final w = _kBaseW[tag]!;
          need(near(hh, _kWH, _kTol) && near(view, w.top, _kTol) && near(list, w.list, _kTol) && over <= _kEps, 'before W 기준 불일치 at $tag');
        } else {
          final b = _kBaseB[tag]!;
          need(near(hh, _kBH, _kTol) && near(topT, b.top, _kTol) && near(over, b.over, _kTol) && list <= _kEps, 'before B 기준 불일치 at $tag');
        }
      } else {
        need(after, 'before 는 BASE 만');
        need(over <= _kEps, 'host 넘침 $over at $tag');
        need(near(view, topT <= cap ? topT : cap, _kTol), '상단 창 $view ≠ min(T $topT, 상한 $cap) at $tag');
        need(near(list, hh - view, _kTol) && list > _kEps, '목록 $list ≠ H − 상단 at $tag');
        final ts = scrollInfo(topScroll);
        need(ts['present'] == true, '상단 스크롤 없음 at $tag');
        final mx = ts['max'] as double;
        need(topT <= cap + _kEps ? mx <= _kEps : near(mx, topT - cap, _kTol), '상단 스크롤 범위 $mx at $tag');
        if (scen == 'BASE') {
          if (!isB) {
            final w = _kBaseW[tag]!;
            need(near(hh, _kWH, _kTol) && near(view, w.top, _kTol) && near(list, w.list, _kTol), 'after W 분할이 before 와 다름 at $tag');
          } else {
            final b = _kBaseB[tag]!;
            need(near(hh, _kBH, _kTol) && near(topT, b.top, _kTol) && near(view, _kBH * _kTopShare, _kTol), 'after B 기대 불일치 at $tag');
          }
        }
      }
      return rec;
    }

    Map<String, Object?> sidecar(String step, double w, double h, double s) => {'phase': phase, 'scen': scen, 'cond': cond,
      'viewport': '${w.toInt()}x${h.toInt()}', 'textScaleFactor(기기)': s, 'step': step, 'realNow': DateTime.now().toIso8601String(), 'pinDay': dayArg};

    Future<void> png(String step, double w, double h, double s) async {
      nPng++;
      budget();
      await vqCapture(t, capKey, 'D304-$phase-$cond-$step', conditions: sidecar(step, w, h, s));
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

    try {
      clockGuard('start');
      _out('D304-ENV ${jsonEncode({'phase': phase, 'pinDay': dayArg, 'realNow': DateTime.now().toIso8601String(), 'kst': kstNow().toIso8601String(),
        'window': '$dayArg KST 08:00–21:30', 'dpr': 1.0, 'locale': 'ko_KR', 'theme': 'RoleTheme.businessAdminTheme',
        'topShare': _kTopShare, 'fonts': 'vqLoadFonts(번들 NotoSansKR Regular/Bold, MaterialIcons)'})}');

      // ═══ BASE(두 phase): 기존 fixture·직접 mount ═══
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
        hostErrCount = 0;
        hostHash0 = null;
        final md = baseModes[c.mode]!;
        setView(c.w, c.h, c.s);
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);
        final r = makeReads(c.id, md.apps, md.atts, md.names);
        stage = 'load';
        await mount(app(Scaffold(body: AttendanceStatusDialog(date: day, businessIds: const [_biz], initialBusinessId: _biz, reads: r.reads)),
            'D304-$phase-BASE-${c.id}'));
        await waitLoad(r);
        measure('load');
        // before 에는 상단 스크롤이 없어(null) 대상이 화면 안·hit 일 때만 통과한다. after 는 상단 창 안으로 bounded drag.
        stage = 'tab';
        final tabTop = vScrollOf(topColEl()!, stopAt: hostEl());
        await reachV(richExact('정상', within: find.byType(TabBar)), tabTop, '정상 탭', screen);
        await tapAt(richExact('정상', within: find.byType(TabBar)), '정상 탭');
        await frames(8, 'tab');
        measure('tab');
        stage = 'select';
        await reachV(allBox(), tabTop, '전체', screen);
        await tapAt(allBox(), '전체');
        await frames(2, 'select');
        measure('select');
        need(selectedBadge() == '2', '선택 2건 아님 ${selectedBadge()}');
        final stepB = button(md.stepIcon, md.step);
        need(buttonCount(stepB) == '2건', '${md.step} 2건 아님 ${buttonCount(stepB)}');
        if (after || !isB) {
          // 도달·가시·hit(before B 는 알려진 결함이라 기록만)
          stage = 'reach';
          final topScroll = vScrollOf(topColEl()!, stopAt: hostEl());
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
          // 목록 순서: 포장(박포장) → 피킹(김피킹)
          await reachV(rowReceiver('박포장'), listScroll, '첫 행 박포장 receiver', screen);
          await reachV(nameF('박포장'), listScroll, '첫 행 박포장 이름', screen);
          await reachV(rowReceiver('김피킹'), listScroll, '끝 행 김피킹 receiver', screen);
          await reachV(nameF('김피킹'), listScroll, '끝 행 김피킹 이름', screen);
          need(selectedBadge() == '2', '스크롤 뒤 선택 유지 아님 ${selectedBadge()}');
          await backTop(listScroll, '목록');
          visibleHit(hostX(), 'host X', screen);
          visibleHit(richExact('당일명단'), '머리 제목', screen);
          visibleHit(richExact('명단 출력'), 'footer 명단 출력', screen);
          visibleHit(richExact('급여관리'), 'footer 급여관리', screen);
          measure('select');
        }
        await png('select', c.w, c.h, c.s);
        need(hostErrCount == (!after && isB ? 1 : 0), 'host 최초 보고 수 $hostErrCount');
        await teardown();
        visited.add('BASE:${c.id}');
      }

      if (after) {
        // ═══ LONG(after 전용): 검토 칩·긴 목록·조건부 선택 확인 바·검색 ═══
        scen = 'LONG';
        const longConds = [
          (id: 'W360_L', w: 360.0, h: 780.0, s: 1.0),
          (id: 'B320_L', w: 320.0, h: 640.0, s: 2.0),
        ];
        for (final c in longConds) {
          cond = c.id;
          isB = c.s == 2.0;
          hostErrCount = 0;
          hostHash0 = null;
          setView(c.w, c.h, c.s);
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          final r = makeReads(c.id, longApps, longAtts, longNames);
          stage = 'load';
          await mount(app(Scaffold(body: AttendanceStatusDialog(date: day, businessIds: const [_biz], initialBusinessId: _biz, reads: r.reads)),
              'D304-$phase-LONG-${c.id}'));
          await waitLoad(r);
          measure('load');
          // 검토 탭(초기): 빠른 선택 칩 두 개·검토 행 두 개
          stage = 'review';
          final topScroll0 = vScrollOf(topColEl()!, stopAt: hostEl());
          await reachV(richExact('미출근 1건'), topScroll0, '칩 미출근 1건', screen);
          await reachV(richExact('퇴근미기록 1건'), topScroll0, '칩 퇴근미기록 1건', screen);
          // tap 직전 실제 frame 의 full/clip/hit(둘째 칩 도달로 첫 칩이 움직였을 수 있다)
          await reachV(richExact('미출근 1건'), topScroll0, '칩 미출근 1건(tap 직전)', screen);
          await tapAt(richExact('미출근 1건'), '칩 미출근 1건');
          await frames(2, 'chip');
          stage = 'chip';
          measure('chip');
          need(selectedBadge() == '1', '칩 선택 1 아님 ${selectedBadge()}');
          need(buttonCount(button(Icons.login, '출근')) == '1건', '출근 1건 아님');
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
          // 정상 탭: 탭 전환은 선택을 초기화한다(production :1210–1219)
          stage = 'tab';
          await reachV(richExact('정상', within: find.byType(TabBar)), topScroll0, '정상 탭', screen);
          await tapAt(richExact('정상', within: find.byType(TabBar)), '정상 탭');
          await frames(8, 'tab');
          measure('tab');
          need(selectedBadge() == null, '탭 전환 뒤 선택이 남음 ${selectedBadge()}');
          need(buttonCount(button(Icons.login, '출근')) == null, '탭 전환 뒤 버튼 건수가 남음');
          // 전체 선택: 정상 14명 → 선택 확인 바(근태 확인 2건 = 하차 2명) 표시, H 감소
          stage = 'select';
          await reachV(allBox(), topScroll0, '전체', screen);
          await tapAt(allBox(), '전체');
          await frames(2, 'select');
          final sel = measure('select');
          need(selectedBadge() == '14', '선택 14 아님 ${selectedBadge()}');
          need((sel['listScroll'] as Map)['present'] == true && ((sel['listScroll'] as Map)['max'] as double) > _kEps, '목록 스크롤 범위 0(fixture 부족)');
          visibleHit(richExact('근태 확인 2건'), '선택 확인 바 근태 확인 2건', screen);
          visibleHit(hostX(), 'host X', screen);
          visibleHit(richExact('당일명단'), '머리 제목', screen);
          visibleHit(richExact('명단 출력'), 'footer 명단 출력', screen);
          visibleHit(richExact('급여관리'), 'footer 급여관리', screen);
          await png('select', c.w, c.h, c.s);
          // 목록 첫·끝(고유 이름 + 행 선택 receiver)
          stage = 'listEnd';
          final listScroll = vScrollOf(nameF('포장01').evaluate().first);
          await reachV(rowReceiver('포장01'), listScroll, '첫 행 포장01 receiver', screen);
          await reachV(nameF('포장01'), listScroll, '첫 행 포장01 이름', screen);
          await reachV(rowReceiver('하차02'), listScroll, '끝 행 하차02 receiver', screen);
          await reachV(nameF('하차02'), listScroll, '끝 행 하차02 이름', screen);
          final topScroll1 = vScrollOf(topColEl()!, stopAt: hostEl());
          await reachV(button(Icons.logout, '퇴근'), topScroll1, '퇴근(2×2)', screen);
          need(selectedBadge() == '14', '목록·상단 스크롤 뒤 선택 유지 아님 ${selectedBadge()}');
          visibleHit(richExact('근태 확인 2건'), '선택 확인 바 유지', screen);
          measure('listEnd');
          await png('listEnd', c.w, c.h, c.s);
          await backTop(topScroll1, '상단');
          // 검색: focus·입력·필터·선택 유지·닫기·복원(inset 0, 키보드 미관측)
          stage = 'search';
          await reachV(searchBox(), topScroll1, '검색 버튼', screen);
          await tapAt(searchBox(), '검색 열기');
          await frames(2, 'search');
          final field = find.byType(TextField);
          need(field.evaluate().length == 1, '검색창 수 ${field.evaluate().length}');
          await reachV(field, topScroll1, '검색창', screen);
          nText++;
          budget();
          await t.enterText(field, '피킹03');
          guard('enterText');
          await frames(4, 'search');
          final shown = find.descendant(of: find.byType(TabBarView), matching: find.byType(AppCheckbox)).evaluate().length;
          _out('D304-SEARCH ${jsonEncode({'phase': phase, 'cond': cond, 'query': '피킹03', 'checkboxes': shown, 'badge': selectedBadge(),
            'viewInsets': MediaQuery.of(t.element(field)).viewInsets.bottom})}');
          need(richExact('피킹03').evaluate().length == 1 && richExact('포장01').evaluate().isEmpty && richExact('하차02').evaluate().isEmpty, '검색 필터 결과 아님');
          need(selectedBadge() == '14', '검색 중 선택 유지 아님 ${selectedBadge()}');
          measure('search');
          await reachV(searchBox(), topScroll1, '검색 닫기 버튼', screen);
          await tapAt(searchBox(), '검색 닫기');
          await frames(4, 'searchClose');
          need(find.byType(TextField).evaluate().isEmpty, '검색창 남음');
          need(richExact('포장01').evaluate().length == 1 && richExact('하차02').evaluate().length == 1, '검색 닫기 뒤 목록 복원 아님');
          need(selectedBadge() == '14', '검색 닫기 뒤 선택 유지 아님 ${selectedBadge()}');
          measure('searchClosed');
          need(hostErrCount == 0, 'host 최초 보고 수 $hostErrCount');
          await teardown();
          visited.add('LONG:${c.id}');
        }

        // ═══ ROUTE(after 전용): production 진입과 같은 showDialog<bool>(barrierDismissible: false) → host X → false ═══
        scen = 'ROUTE';
        const routeConds = [
          (id: 'W360_R', w: 360.0, h: 780.0, s: 1.0),
          (id: 'B320_R', w: 320.0, h: 640.0, s: 2.0),
        ];
        for (final c in routeConds) {
          cond = c.id;
          isB = c.s == 2.0;
          hostErrCount = 0;
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
                      child: const Text('DU304 열기'),
                    ),
                  ),
                ),
              ),
              'D304-$phase-ROUTE-${c.id}'));
          nOpen++;
          await tapAt(find.text('DU304 열기'), 'route 열기');
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
          need(hostErrCount == 0, 'host 최초 보고 수 $hostErrCount');
          _out('D304-ROUTE ${jsonEncode({'phase': phase, 'cond': cond, 'popped': routePopped, 'result': routeResult})}');
          await teardown();
          visited.add('ROUTE:${c.id}');
        }
      }

      final want = after
          ? 'BASE:W360_IN|BASE:W360_OUT|BASE:B320_IN|BASE:B320_OUT|LONG:W360_L|LONG:B320_L|ROUTE:W360_R|ROUTE:B320_R'
          : 'BASE:W360_IN|BASE:W360_OUT|BASE:B320_IN|BASE:B320_OUT';
      need(visited.join('|') == want, '방문 $visited');
      need(nPng == (after ? 8 : 4) && nOpen == (after ? 2 : 0) && nText == (after ? 2 : 0), '실행량 ${counts()}');
      clockGuard('end');
      // 성공 완료의 최종 단언(마지막 teardown 뒤): HTTP 0·업무 채널 {}·동결 뒤 Reads []·대기 오류 0·화면 해제
      need(net.created == 0 && biz.isEmpty && afterFreeze.isEmpty && errors.isEmpty && !live,
          '최종 상태 http=${net.created} business=$biz reads=$afterFreeze pending=${errors.length} live=$live');
      _out('D304-END ${jsonEncode({...counts(), 'visited': visited, 'http': net.created, 'business': biz, 'readsAfterFreeze': afterFreeze,
        'errors': errLog.map((e) => '${e['cond']}/${e['stage']}#${e['pump']}: ${e['kind']} ${e['first']} raw ${e['raw']}').toList()})}');
      completed = true;
    } finally {
      // 실패 정리: 아직 mount 돼 있으면(중간 stop·예외) 유한 teardown(mount 1 + pump 2)을 한 번 시도한다.
      //   원 실패를 덮지 않도록 여기서는 need/stop/fail 을 부르지 않고 결과·정리 중 오류를 FINAL 에만 남긴다.
      //   한도·시각 이탈로 멈췄어도 같은 경계(mount 1 + pump 2)만 쓴다. 성공 경로는 이미 해제돼 정리가 없다.
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
      _out('D304-FINAL ${jsonEncode({...counts(), 'outcome': completed ? 'completed' : 'failed', 'cleanup': cleanup,
        'cleanupMount': cleanMount, 'cleanupPump': cleanPump, 'stillMounted': live, 'visited': visited, 'http': net.created,
        'business': biz, 'readsAfterFreeze': afterFreeze, 'errorsLogged': errLog.length, 'cleanupErrors': cleanErrors})}');
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
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
