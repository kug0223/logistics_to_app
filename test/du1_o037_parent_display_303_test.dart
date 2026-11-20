// ignore_for_file: depend_on_referenced_packages
// [DU303 DU-O037-PARENT-DISPLAY-303] 부모 파트별 일괄 확인창 — 정규 before/after(reports/DU_diag_303_d2_audit_2026-11-12.md §3·§4).
//   DU303_RUN=1 이고 DU303_PHASE 가 before 또는 after 일 때만 실행한다(기본 skip). production 편집 0(시험은 관측만).
//   조건: W360×780/1.0·B320×640/2.0 × IN(22:00/22:30 시작, 근태 없음)·OUT(06:00/07:00 출근 기록, 23:00/23:30 퇴근 예정) = 4.
//   흐름(조건마다): 진입(정상 → 전체 → 단계 버튼) → 부모 → 피킹 `변경` → 자식(예정 칩 → +10 → 확정)
//     → 부모 피킹 22:10/23:10 갱신·포장 불변 → 피킹 `변경` 다시 → 자식 W 취소 / B X → 부모 값 유지 → 부모 W 취소 / B X.
//   부모 최종 처리 tap 0(처리 경로 :4360·:4463 진입 0). 실제 tap/drag 만 쓰고 값 주입·강제 tap·Navigator.pop 직접 호출 0.
//   오류는 load~teardown 연속 수집하고 매 pump·행동 뒤 즉시 분류한다. 허용은 D2 감사 §3 예외표뿐이다(±0.01).
// [t3 — 준비물 감사(reports/DU_prep_303_audit_2026-11-12.md) §2 보완]
//   ① 도달 대상 = 파트 시각 줄(상자 ∪ 시각 글자 ∪ 변경)의 세로 범위. ② 모든 frame 의 Flex 원자료를 단언 전에 출력(자식 포함),
//   part1again·keep 도 부모 frame 검사. ③ host 부재·다른 RenderObject·선택 해제는 중단(단계 표 명시). ④ 실제 조상 clip chain 과
//   공통 가시·hit·이름·말줄임 검사를 before 에도 적용(before 예외는 옛 색·최소치 미달·B 돌출/겹침 고정값뿐). ⑤ host 최초 보고 1건/mount,
//   부모 최초 보고는 피킹·포장 각 1건, 부모·자식 route 의 popped 결과(부모 null·자식 확정값/null)를 직접 단언.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

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
    throw StateError('DU303 network guard');
  }
}

void _out(String l) {
  // ignore: avoid_print
  print(l);
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

const _biz = 'biz303';
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

// D2 감사 §3 예외표(logical px, 비교 공차 ±0.01) — B320/2.0 한정
const _kParentRaw = 24.23998489379879; // before 부모 원본 :4665 innerRow right(파트마다)
const _kHostLoad = 27.85000000000008; // before·after host :1186 bottom, load
const _kHostTab = 22.750000000000057; // 정상 탭 뒤
const _kHostSel = 96.25000000000006; // 전체 선택 뒤(그 뒤 상태 포함 — 계획 §6 의 미관측 상태는 판정 대상)
const _kOverhang = 11.33998489379879; // before B 도달 frame: 시각 글자가 상자 우측을 넘는 양
const _kOverlap = 4.53998489379879; // before B 도달 frame: 시각 글자와 변경 receiver 가로 겹침
const _kTol = 0.01;
const _kEps = 1e-6;
const _hostLine = 1186;
const _origInnerLine = 4665;

Map<String, dynamic> _ts(DateTime d) => {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

void main() {
  final phase = Platform.environment['DU303_PHASE'] ?? '';
  final run = Platform.environment['DU303_RUN'] == '1' && (phase == 'before' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    if (!run) return;
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('D303 $phase', (t) async {
    // ── 실행일·실제 시각 구간: 2026-11-12 KST 08:00–21:30 ──
    final day = DateTime(2026, 11, 12);
    final dayKey = FormatHelper.kstDayKeyOfCivil(day);
    final realNow = DateTime.now();
    final kst = realNow.toUtc().add(const Duration(hours: 9));
    final kstMin = kst.hour * 60 + kst.minute;

    await t.runAsync(vqLoadFonts);
    final sem = t.ensureSemantics();
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
        return const StandardMessageCodec().encodeMessage(<Object?>['du303-blocked', 'firestore $op 차단', null]);
      });
    }
    for (final op in _fnOps) {
      m.setMockMessageHandler('$_fnBase.$op', (msg) async {
        biz['fn.$op'] = (biz['fn.$op'] ?? 0) + 1;
        return const StandardMessageCodec().encodeMessage(<Object?>['du303-blocked', 'functions $op 차단', null]);
      });
    }
    m.setMockMethodCallHandler(const MethodChannel(_fnLegacy), (call) async {
      biz['fn.legacy.${call.method}'] = (biz['fn.legacy.${call.method}'] ?? 0) + 1;
      throw PlatformException(code: 'du303-blocked', message: 'functions legacy ${call.method} 차단');
    });

    // 실행량(phase 상한): 부모 open ≤4·자식 open ≤8·mount ≤16·pump+mount ≤800·tap ≤80·drag ≤16·PNG ≤10쌍
    var nPump = 0, nMount = 0, nTap = 0, nParent = 0, nChild = 0, nDrag = 0, nPng = 0;
    Map<String, Object?> counts() => {'phase': phase, 'pump': nPump, 'mount': nMount, 'pumpMount': nPump + nMount, 'tap': nTap,
      'parentOpen': nParent, 'childOpen': nChild, 'drag': nDrag, 'png': nPng};

    // 오류: load~teardown 연속 수집(조건·단계·pump 번호·첫 줄·원문 전체)
    var cond = '-';
    var stage = 'start';
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
    final reportedParentHashes = <String>{};
    var hostErrCount = 0; // 조건(mount)마다 host 최초 보고 수
    final parentErrParts = <String>[]; // 조건마다 부모 최초 보고 파트
    final rows = <Map<String, Object?>>[];
    final visited = <String>[];

    Never stop(String why) {
      _out('D303-STOP ${jsonEncode({'phase': phase, 'cond': cond, 'stage': stage, 'why': why,
        'pendingErrors': errors.map((e) => '${e.cond}/${e.stage}#${e.pump}: ${e.first}').toList(), 'counts': counts(),
        'http': net.created, 'business': biz, 'readsAfterFreeze': afterFreeze})}');
      for (final e in errors) {
        _out('D303-STOPERR ${jsonEncode({'cond': e.cond, 'stage': e.stage, 'pump': e.pump, 'full': e.full})}');
      }
      fail('$phase/$cond/$stage: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    void budget() => need(nParent <= 4 && nChild <= 8 && nMount <= 16 && nPump + nMount <= 800 && nTap <= 80 && nDrag <= 16 && nPng <= 10,
        '한도 ${counts()}');

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
      final mm = RegExp(r'^A RenderFlex overflowed by ([0-9.]+) pixels on the (right|bottom|left|top)\.$').firstMatch(first);
      final lines = RegExp(r'attendance_status_dialog\.dart:(\d+):\d+').allMatches(full).map((x) => int.parse(x.group(1)!)).toList();
      final h = RegExp(r'RenderFlex#([0-9a-f]{5})').firstMatch(full);
      return (dir: mm?.group(2), val: mm?.group(1), lines: lines, hash: h?.group(1));
    }

    // host `_buildContent` Column(:1186) = TabBar 위로 두 번째 Column
    RenderFlex? hostFlex() {
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
      return hit?.renderObject as RenderFlex?;
    }

    // 부모(Dialog) 안 시각 줄 안쪽 Row 들(원본 :4665 대응) — 파트 카드(반경 14) 안, 시각 글자의 가장 가까운 Row
    Map<String, String> parentInnerRows() {
      final out = <String, String>{};
      final titles = find.byWidgetPredicate((w) => w is RichText && TextLayout.plain(w.text.toPlainText()).startsWith('파트별 일괄 ')).evaluate();
      if (titles.isEmpty) return out;
      final dlg = nearest(titles.first, (w) => w is Dialog);
      if (dlg == null) return out;
      for (final e in find.descendant(of: fe(dlg), matching: find.byType(RichText)).evaluate()) {
        if (!RegExp(r'^[0-9]{2}:[0-9]{2}$').hasMatch(plainOf(e))) continue;
        final row = nearest(e, (w) => w is Row);
        final card = nearest(e, (w) => w is DecoratedBox && w.decoration is BoxDecoration &&
            ((w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(14)));
        if (row == null || card == null) continue;
        final names = find.descendant(of: fe(card), matching: find.byType(RichText)).evaluate().map(plainOf).toList();
        out[shortHash(row.renderObject as RenderFlex)] = names.firstWhere((s) => s == '피킹' || s == '포장', orElse: () => '?');
      }
      return out;
    }

    // 매 pump·mount·행동 뒤 즉시 검사: 예외·오류 분류(예외표만 허용)·네트워크/업무 채널·동결 뒤 Reads
    void guard(String where) {
      final ex = t.takeException();
      need(ex == null, '$where 예외: $ex');
      final host = hostFlex();
      final hostHash = host == null ? null : shortHash(host);
      final inner = parentInnerRows();
      for (final e in errors) {
        final o = owner(e.first, e.full);
        String kind = 'OTHER';
        double? raw;
        var ok = false;
        if (o.dir == 'bottom' && o.lines.contains(_hostLine) && o.hash != null && o.hash == hostHash && host != null) {
          kind = 'host:1186';
          raw = (flexInfo(host)['over'] as double);
          // host 는 B 의 load 단계에서 mount 마다 최초 1건만(원문 28·raw 27.85 ±0.01)
          ok = isB && e.stage == 'load' && o.val == '28' && near(raw, _kHostLoad, _kTol) && hostErrCount == 0;
          if (ok) hostErrCount++;
        } else if (o.dir == 'right' && o.lines.contains(_origInnerLine) && o.hash != null && inner.containsKey(o.hash)) {
          kind = 'parent:4665';
          final rows0 = find.byWidgetPredicate((w) => w is Row).evaluate().where((x) =>
              x.renderObject is RenderFlex && shortHash(x.renderObject as RenderFlex) == o.hash).toList();
          raw = rows0.length == 1 ? (flexInfo(rows0.first.renderObject as RenderFlex)['over'] as double) : null;
          final part = inner[o.hash];
          // 부모는 before B 에서 피킹·포장 innerRow 마다 최초 1건만(원문 24·raw 24.24 ±0.01). '?' 파트는 허용하지 않는다.
          ok = !after && isB && o.val == '24' && raw != null && near(raw, _kParentRaw, _kTol) &&
              (part == '피킹' || part == '포장') && !parentErrParts.contains(part) && reportedParentHashes.add(o.hash!);
          if (ok) parentErrParts.add(part!);
        }
        final r = {'phase': phase, 'cond': e.cond, 'stage': e.stage, 'pump': e.pump, 'first': e.first, 'dir': o.dir, 'val': o.val,
          'ownerLines': o.lines, 'hash': o.hash, 'kind': kind, 'raw': raw, 'part': o.hash == null ? null : inner[o.hash], 'allowed': ok, 'full': e.full};
        errLog.add(r);
        _out('D303-ERR ${jsonEncode(r)}');
        if (!ok) stop('예외표 밖 오류 $kind ${e.first} raw $raw at $where');
      }
      errors.clear();
      need(net.created == 0, '$where HttpClient ${net.created}');
      need(biz.isEmpty, '$where 업무 채널 $biz');
      need(afterFreeze.isEmpty, '$where 초기 로드 뒤 Reads $afterFreeze');
    }

    Future<void> frames(int n, String where, [Duration d = const Duration(milliseconds: 50)]) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        budget();
        await t.pump(d);
        guard('$where#$i');
      }
    }

    Future<void> mount(Widget w) async {
      nMount++;
      budget();
      await t.pumpWidget(w);
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

    // host :1186 단계 표(B 는 D2 감사 §3 + 준비물 감사 §3 의 소스 기반 예측, W 는 0). 표 밖 태그·부재·다른 RenderObject·선택 해제는 중단.
    //   D2 관측: load·tab·select(·open/paint/도달). 준비물 감사 수용(예측): child1·return·child2·parentClosed.
    //   같은 전제(같은 mount·선택 2건 유지)로 관측하는 추가 태그: parentOpen·part1·child1After·end·part1again·keep.
    const hostTable = <String, double>{
      'load': _kHostLoad, 'tab': _kHostTab, 'select': _kHostSel, 'parentOpen': _kHostSel, 'part1': _kHostSel, 'child1': _kHostSel,
      'child1After': _kHostSel, 'return': _kHostSel, 'end': _kHostSel, 'part1again': _kHostSel, 'child2': _kHostSel, 'keep': _kHostSel,
      'parentClosed': _kHostSel,
    };
    String? hostHash0; // 이 mount 의 host RenderObject(load 에서 고정)
    IconData? stepIcon; // 선택 유지 확인용(단계 버튼 `N건`)
    String? stepLabel;
    Map<String, Object?> checkHost(String tag) {
      need(hostTable.containsKey(tag), 'host 단계 표 밖 태그 $tag');
      final rf = hostFlex();
      final selected = (stepIcon == null || stepLabel == null)
          ? -1
          : find.byType(InkWell).evaluate().where((e) =>
              find.descendant(of: fe(e), matching: find.byIcon(stepIcon!)).evaluate().length == 1 &&
              richExact(stepLabel!, within: fe(e)).evaluate().length == 1 &&
              richExact('2건', within: fe(e)).evaluate().length == 1).length;
      final info = rf == null ? <String, Object?>{'present': false} : {'present': true, ...flexInfo(rf)};
      final expect = isB ? hostTable[tag]! : 0.0;
      final rec0 = {'phase': phase, 'cond': cond, 'tag': tag, 'pump': nPump, 'expect': expect, 'hostHash0': hostHash0,
        'selectedStep2': selected, ...info};
      _out('D303-HOST ${jsonEncode(rec0)}');
      need(rf != null, 'host 관측 불가 at $tag');
      final h = shortHash(rf!);
      if (tag == 'load') {
        hostHash0 = h;
      } else {
        need(h == hostHash0, 'host RenderObject 바뀜 $h ≠ $hostHash0 at $tag');
      }
      if (tag != 'load' && tag != 'tab') need(selected == 1, '선택 2건 유지 아님($selected) at $tag');
      final over = info['over'] as double;
      if (!isB) {
        need(over <= _kEps, 'W host 넘침 $over at $tag');
      } else {
        need(near(over, expect, _kTol), 'B host raw $over ≠ $expect at $tag');
      }
      return rec0;
    }

    // [t4] 실제 paint clip chain — 대상부터 RenderView 까지 실제 parent–child 쌍을 모두 따라가며 `parent.describeApproximatePaintClip(child)`
    //   (SDK object.dart:3605 의 공개 API)를 묻는다. null 이 아니면 그 경계(부모 좌표)를 부모의 전역 변환으로 옮겨 기록하고,
    //   현재 SDK 에서 describe 반환과 실제 paint clip 이 **같은 사각**(Offset.zero & size)임을 소스로 확인한 경우만 교차해 `full` 판정에 쓴다:
    //     RenderFlex·RenderConstraintsTransformBox·RenderStack/IndexedStack(넘침 + clip≠none 일 때만 반환·paint),
    //     _RenderTheater(Overlay, clip≠none), _RenderSingleChildViewport(SingleChildScrollView, _shouldClipAtPaintOffset 같은 조건),
    //     RenderClipRect 는 **clipper == null 인 기본 사각만**(custom clipper 는 paint 가 getClip, describe 가 근사라 다를 수 있음).
    //   [t5 — r3 감사 §2] RenderViewport·ShrinkWrappingViewport 는 describe 가 overlap·semantics 조건으로 paint 와 달라질 수 있어 정확 목록에서 뺐다.
    //   그 밖(custom ClipRect·Viewport·RRect/Oval/Path·PhysicalModel/Shape 등)이 null 이 아닌 clip 을 내면 `unsupported` 로 남기고 판정에서 중단한다.
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
          // RenderClipRect 는 clipper 가 null(기본 사각)일 때만 정확 사각으로 인정한다
          final clipperNull = p is RenderClipRect ? p.clipper == null : null;
          final exact = rectClipTypes.contains(type) && (clipperNull ?? true);
          chain.add({'parent': type, 'child': child.runtimeType.toString(), 'local': rectL(local), 'global': rectL(global), 'rectExact': exact,
            'clipperNull': clipperNull});
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
    Map<String, dynamic> attMap(String id, String appId, String uid, String checkIn) => {
          'id': id, 'applicationId': appId, 'uid': uid, 'businessId': _biz, 'status': 'present', 'checkIn': checkIn,
          'workDate': _ts(dayKey), 'createdAt': _ts(dayKey),
        };
    final up = UserProvider()..debugSetCurrentUser(user('owner303', 'DU303 사장', UserRole.BUSINESS_ADMIN));
    final (ds, de) = FormatHelper.kstDayRange(dayKey);
    final modes = {
      'IN': (
        icon: Icons.login, step: '출근', title: '파트별 일괄 출근', cta: '출근 처리 (2명)',
        apps: [appMap('in-a', 'u-in-a', 'wd-pick', '피킹', '22:00', '23:00'), appMap('in-b', 'u-in-b', 'wd-pack', '포장', '22:30', '23:30')],
        atts: <Map<String, dynamic>>[], ids: ['in-a', 'in-b'], uids: ['u-in-a', 'u-in-b'],
        pick: '22:00', other: '22:30', picked: '22:10', childTitle: '피킹 출근 시간', iconFg: AppColors.successDark, face: AppColors.success,
      ),
      'OUT': (
        icon: Icons.logout, step: '퇴근', title: '파트별 일괄 퇴근', cta: '퇴근 처리 (2명)',
        apps: [appMap('out-a', 'u-out-a', 'wd-pick', '피킹', '06:00', '23:00'), appMap('out-b', 'u-out-b', 'wd-pack', '포장', '07:00', '23:30')],
        atts: [attMap('att-out-a', 'out-a', 'u-out-a', '06:00'), attMap('att-out-b', 'out-b', 'u-out-b', '07:00')],
        ids: ['out-a', 'out-b'], uids: ['u-out-a', 'u-out-b'],
        pick: '23:00', other: '23:30', picked: '23:10', childTitle: '피킹 퇴근 시간', iconFg: AppColors.purple, face: AppColors.purple,
      ),
    };
    const conds = [
      (id: 'W360_IN', w: 360.0, h: 780.0, s: 1.0, mode: 'IN'),
      (id: 'W360_OUT', w: 360.0, h: 780.0, s: 1.0, mode: 'OUT'),
      (id: 'B320_IN', w: 320.0, h: 640.0, s: 2.0, mode: 'IN'),
      (id: 'B320_OUT', w: 320.0, h: 640.0, s: 2.0, mode: 'OUT'),
    ];
    final capKey = GlobalKey();

    try {
      need(FormatHelper.toKstDate(realNow) == dayKey, '실행일 이탈 now=$realNow kst=$kst');
      need(kstMin >= 8 * 60 && kstMin < 21 * 60 + 30, '실행 시각 구간 이탈 kst=$kst');
      _out('D303-ENV ${jsonEncode({'phase': phase, 'realNow': realNow.toIso8601String(), 'realNowUtc': realNow.toUtc().toIso8601String(),
        'kst': kst.toIso8601String(), 'window': '2026-11-12 KST 08:00–21:30', 'fixtureDay': '2026-11-12', 'dpr': 1.0, 'locale': 'ko_KR',
        'theme': 'RoleTheme.businessAdminTheme', 'fonts': 'vqLoadFonts(번들 NotoSansKR Regular/Bold, MaterialIcons)'})}');

      for (final c in conds) {
        cond = c.id;
        isB = c.s == 2.0;
        final md = modes[c.mode]!;
        final row = <String, Object?>{'phase': phase, 'cond': c.id};
        final hostRec = <Map<String, Object?>>[];
        reportedParentHashes.clear();
        hostErrCount = 0;
        parentErrParts.clear();
        hostHash0 = null;
        stepIcon = md.icon;
        stepLabel = md.step;
        // route 의 popped 결과(공개 경로) — 부모는 null, 자식은 확정값/null 을 직접 단언한다
        var parentPopped = false;
        Object? parentResult = 'unset';
        final childPopped = <String, bool>{};
        final childResults = <String, Object?>{};
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        t.platformDispatcher.textScaleFactorTestValue = c.s;
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);
        Map<String, Object?> sidecar(String step) => {'phase': phase, 'cond': c.id, 'viewport': '${c.w.toInt()}x${c.h.toInt()}',
          'textScaleFactor(기기)': c.s, 'step': step, 'realNow': DateTime.now().toIso8601String(), 'fixtureDay': '2026-11-12'};

        // ── 조건별 Reads 대역·사전표(9함수 10호출) ──
        final readCalls = <String, List<Object?>>{};
        var frozen = false;
        void rec(String name, Object? args) {
          (readCalls[name] ??= []).add(args);
          if (frozen) afterFreeze.add('${c.id}:$name');
        }

        final reads = AttendanceReads(
          applicationsPaged: (payload) async {
            rec('applicationsPaged', Map<String, dynamic>.of(payload));
            if (payload['type'] != null) return const [];
            return [for (final a in md.apps) Map<String, dynamic>.of(a)];
          },
          workTypeDocs: (id) async {
            rec('workTypeDocs', id);
            return const {};
          },
          adminAttendances: ({required businessId, required startMs, required endMs}) async {
            rec('adminAttendances', {'businessId': businessId, 'startMs': startMs, 'endMs': endMs});
            return [for (final a in md.atts) Map<String, dynamic>.of(a)];
          },
          workDetailTimes: (workers) async {
            rec('workDetailTimes', workers.map((w) => w.id).toList()..sort());
            return const {};
          },
          usersBatch: ({required uids, required businessId}) async {
            rec('usersBatch', {'uids': [...uids]..sort(), 'businessId': businessId});
            return {md.uids[0]: user(md.uids[0], '김피킹', UserRole.USER), md.uids[1]: user(md.uids[1], '박포장', UserRole.USER)};
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
        final expectedReads = <String, List<Object?>>{
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
            {'uids': md.uids, 'businessId': _biz}
          ],
          'workDetailTimes': [md.ids],
          'contractStatus': [
            {'appIds': md.ids, 'businessId': _biz}
          ],
        };
        String canon(Map<String, List<Object?>> x) => jsonEncode({for (final k in (x.keys.toList()..sort())) k: x[k]});

        // ── load ──
        stage = 'load';
        await mount(RepaintBoundary(
          key: capKey,
          child: ChangeNotifierProvider<UserProvider>.value(
            value: up,
            child: MaterialApp(
              key: ValueKey('D303-$phase-${c.id}'),
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.businessAdminTheme,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ko', 'KR')],
              home: Scaffold(
                body: AttendanceStatusDialog(date: day, businessIds: const [_biz], initialBusinessId: _biz, reads: reads),
              ),
            ),
          ),
        ));
        final tabNormal = richExact('정상', within: find.byType(TabBar));
        for (var i = 0; i < 16; i++) {
          final n = readCalls.values.fold<int>(0, (a, b) => a + b.length);
          if (n >= 10 && tabNormal.evaluate().length == 1 && richExact('전체').evaluate().isNotEmpty) break;
          await frames(1, 'load');
        }
        await frames(1, 'load');
        frozen = true;
        final match = canon(readCalls) == canon(expectedReads);
        _out('D303-READS ${jsonEncode({'phase': phase, 'cond': c.id, 'actual': readCalls, 'expected': expectedReads, 'match': match})}');
        need(match, 'Reads 사전표 불일치');
        hostRec.add(checkHost('load'));

        // ── 진입: 정상 탭 → 전체 → 단계 버튼 ──
        stage = 'tab';
        await tapAt(tabNormal, '정상 탭');
        await frames(8, 'tab');
        hostRec.add(checkHost('tab'));
        stage = 'select';
        final allEls = richExact('전체').evaluate().where((e) {
          final g = nearest(e, (w) => w is GestureDetector);
          return g != null && find.descendant(of: fe(g), matching: find.byType(AppCheckbox)).evaluate().length == 1;
        }).toList();
        need(allEls.length == 1, '전체 선택 수 ${allEls.length}');
        await tapAt(fe(allEls.first), '전체');
        await frames(2, 'select');
        hostRec.add(checkHost('select'));
        stage = 'step';
        final stepEls = find.byType(InkWell).evaluate().where((e) =>
            find.descendant(of: fe(e), matching: find.byIcon(md.icon)).evaluate().length == 1 &&
            richExact(md.step, within: fe(e)).evaluate().length == 1 &&
            richExact('2건', within: fe(e)).evaluate().length == 1).toList();
        need(stepEls.length == 1, '${md.step} 단계 버튼 수 ${stepEls.length}');
        need((stepEls.first.widget as InkWell).onTap != null, '${md.step} 단계 버튼 비활성');
        stage = 'parentOpen';
        nParent++;
        await tapAt(fe(stepEls.first), '${md.step} 단계 버튼');
        final titleF = richExact(md.title);
        for (var i = 0; i < 3 && titleF.evaluate().isEmpty; i++) {
          nPump++;
          budget();
          await t.pump();
          guard('open#$i');
        }
        need(titleF.evaluate().length == 1, '부모 제목 ${titleF.evaluate().length}');
        final dialogEl0 = nearest(titleF.evaluate().first, (w) => w is Dialog);
        need(dialogEl0 != null, '부모 Dialog 없음');
        final Element dialogEl = dialogEl0!;
        final dialogF = fe(dialogEl);
        final route0 = ModalRoute.of(t.element(titleF));
        need(route0 != null && route0.animation != null, '부모 route 없음');
        final Animation<double> routeAnim = route0!.animation!;
        route0.popped.then((v) {
          parentPopped = true;
          parentResult = v;
        });
        for (var i = 0; i < 6 && routeAnim.status != AnimationStatus.completed; i++) {
          await frames(1, 'parentAnim');
        }
        need(routeAnim.status == AnimationStatus.completed, '부모 route 애니메이션 미완료');
        final cardF = find.descendant(of: dialogF, matching: find.byType(Material)).first;
        final scrollF = find.descendant(of: dialogF, matching: find.byType(SingleChildScrollView));
        need(scrollF.evaluate().length == 1, '부모 본문 스크롤 수 ${scrollF.evaluate().length}');
        final closeF = find.descendant(of: dialogF, matching: find.widgetWithIcon(IconButton, Icons.close));
        final cancelF = find.descendant(of: dialogF, matching: find.widgetWithText(OutlinedButton, '취소'));
        final ctaF = find.descendant(of: dialogF, matching: find.byWidgetPredicate((w) => w is ElevatedButton));
        need(closeF.evaluate().length == 1 && cancelF.evaluate().length == 1 && ctaF.evaluate().length == 1,
            '부모 X/취소/CTA 수 ${closeF.evaluate().length}/${cancelF.evaluate().length}/${ctaF.evaluate().length}');
        ScrollPosition pos() => t.state<ScrollableState>(find.descendant(of: scrollF, matching: find.byType(Scrollable)).first).position;

        // 부모 frame 기록·검사: 모든 Flex 원자료를 먼저 출력하고 그 뒤 단언한다
        //   (before B 는 피킹·포장 두 innerRow 만 예외 raw 24.24 ±0.01, 그 밖과 after 는 넘침 ≤1e−6)
        // [t4] 측정·출력(parentFrameRec)과 단언(assertParentFrame)을 나눈다 — 파트 단언·도달 중단보다 먼저 전체 Flex 를 남기기 위해
        Map<String, Object?> parentFrameRec(String tag) {
          final inner = parentInnerRows();
          final flexAll = <Map<String, Object?>>[];
          for (final e in find.descendant(of: dialogF, matching: find.byWidgetPredicate((w) => w is Flex)).evaluate()) {
            final info = flexInfo(e.renderObject as RenderFlex);
            info['innerPart'] = inner[info['hash']];
            flexAll.add(info);
          }
          final p = pos();
          final fr = <String, Object?>{'phase': phase, 'cond': cond, 'tag': tag, 'pump': nPump, 'screen': rectL(screen),
            'cardRect': rectL(t.getRect(cardF)), 'viewportRect': rectL(t.getRect(scrollF)),
            'scroll': {'pixels': p.pixels, 'min': p.minScrollExtent, 'max': p.maxScrollExtent, 'vpDim': p.viewportDimension},
            'innerParts': inner.values.toList(), 'flexAll': flexAll, 'counts': counts()};
          _out('D303-FRAME ${jsonEncode(fr)}');
          return fr;
        }

        Map<String, Object?> assertParentFrame(Map<String, Object?> fr) {
          final tag = fr['tag'];
          final flexAll = (fr['flexAll'] as List).cast<Map<String, Object?>>();
          final innerParts = (fr['innerParts'] as List).cast<String>();
          for (final info in flexAll) {
            final over = info['over'] as double;
            if (!after && isB && info['innerPart'] != null) {
              need(near(over, _kParentRaw, _kTol), 'before B 부모 innerRow raw $over at $tag');
            } else {
              need(over <= _kEps, '부모 Flex 넘침 ${info['hash']} $over at $tag');
            }
          }
          if (!after && isB) {
            need(innerParts.length == 2 && innerParts.toSet().containsAll({'피킹', '포장'}), 'before B innerRow 파트 $innerParts at $tag');
          }
          return fr;
        }

        Map<String, Object?> parentFrame(String tag) => assertParentFrame(parentFrameRec(tag));

        // 자식 시트가 있으면 모든 Flex 를 출력한다(중단 직전 원자료 보존용, 단언 없음)
        void dumpChild(String tag) {
          final s = find.byType(BottomSheet);
          if (s.evaluate().length != 1) {
            _out('D303-CHILDDUMP ${jsonEncode({'phase': phase, 'cond': cond, 'tag': tag, 'pump': nPump, 'sheets': s.evaluate().length})}');
            return;
          }
          final flexAll = [
            for (final e in find.descendant(of: s, matching: find.byWidgetPredicate((w) => w is Flex)).evaluate()) flexInfo(e.renderObject as RenderFlex)
          ];
          _out('D303-CHILDDUMP ${jsonEncode({'phase': phase, 'cond': cond, 'tag': tag, 'pump': nPump, 'sheets': 1, 'flexAll': flexAll})}');
        }

        // 중단 전에 현재 부모·자식 원자료를 모두 남기고 멈춘다
        Never stopWithFrames(String why, String tag) {
          if (dialogF.evaluate().length == 1) {
            parentFrameRec('stop:$tag');
          } else {
            _out('D303-FRAME ${jsonEncode({'phase': phase, 'cond': cond, 'tag': 'stop:$tag', 'pump': nPump, 'dialog': dialogF.evaluate().length})}');
          }
          dumpChild('stop:$tag');
          stop(why);
        }

        // 파트 요소: 카드·시각 상자·시각 글자·아이콘·변경
        ({Element card, Element box, Element time, Element change, Element? icon})? partEls(String part) {
          for (final ce in find.descendant(of: dialogF, matching: find.byWidgetPredicate((w) => w is OutlinedButton)).evaluate()) {
            if (richExact('변경', within: fe(ce)).evaluate().length != 1) continue;
            final card = nearest(ce, (w) => w is DecoratedBox && w.decoration is BoxDecoration &&
                ((w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(14)));
            if (card == null) continue;
            if (richExact(part, within: fe(card)).evaluate().length != 1) continue;
            final times = find.descendant(of: fe(card), matching: find.byType(RichText)).evaluate().where((e) =>
                RegExp(r'^[0-9]{2}:[0-9]{2}$').hasMatch(plainOf(e))).toList();
            if (times.length != 1) return null;
            final box = nearest(times.first, (w) => w is DecoratedBox);
            if (box == null) return null;
            final icons = find.descendant(of: fe(card), matching: find.byIcon(Icons.check_circle_outline)).evaluate().toList();
            return (card: card, box: box, time: times.first, change: ce, icon: icons.isEmpty ? null : icons.first);
          }
          return null;
        }

        Map<String, Object?> recv(Finder f) {
          final r = t.getRect(f);
          return {'rect': rectL(r), 'w': r.width, 'h': r.height, 'hit': f.hitTestable().evaluate().length == 1,
            'inScreen': inside(r, screen), 'inCard': inside(r, t.getRect(cardF))};
        }

        // 바깥에서 실제 drag 로 대상을 본문 창 안에 둔다(거리 = 그 frame 의 rect·창으로 계산 + slop 20 + 16, 대상마다 최대 2회)
        Future<void> reachIn(Finder target, Finder scroll, String what) async {
          for (var i = 0; i < 2; i++) {
            final vp = t.getRect(scroll);
            final r = t.getRect(target);
            if (inside(r, vp) && target.hitTestable().evaluate().length == 1) return;
            final below = r.bottom > vp.bottom;
            final d = below ? r.bottom - vp.bottom : vp.top - r.top;
            final dy = below ? -(d + kDragSlopDefault + 16) : (d + kDragSlopDefault + 16);
            final st = t.state<ScrollableState>(find.descendant(of: scroll, matching: find.byType(Scrollable)).first).position;
            final before0 = st.pixels;
            nDrag++;
            budget();
            await t.drag(scroll, Offset(0, dy));
            guard('drag:$what');
            await frames(3, 'drag:$what');
            _out('D303-REACH ${jsonEncode({'phase': phase, 'cond': c.id, 'what': what, 'try': i, 'd': d, 'dy': dy, 'before': before0, 'after': st.pixels})}');
          }
          final vp = t.getRect(scroll);
          need(inside(t.getRect(target), vp) && target.hitTestable().evaluate().length == 1, '$what 비도달');
        }

        // 파트 시각 줄(상자 ∪ 시각 글자 ∪ 변경)의 세로 범위를 본문 창 안에 둔다. 거리는 그 frame 의 합집합·창으로 계산하고,
        //   여유는 min(16, (창 − 줄)/2). 대상마다 최대 2회. 줄이 창보다 높으면 중단한다.
        Future<void> reachRow(String part, String what) async {
          Rect unionOf(({Element card, Element box, Element time, Element change, Element? icon}) pe) =>
              t.getRect(fe(pe.box)).expandToInclude(t.getRect(fe(pe.time))).expandToInclude(t.getRect(fe(pe.change)));
          // [t4] 높이 초과·요소 없음·최종 비도달은 현재 합집합·창·스크롤과 전체 Flex(부모·자식)를 먼저 출력한 뒤 멈춘다
          Never reachFail(String why, Rect? u) {
            final p = pos();
            _out('D303-REACHFAIL ${jsonEncode({'phase': phase, 'cond': cond, 'what': what, 'pump': nPump, 'why': why,
              'union': u == null ? null : rectL(u), 'viewport': rectL(t.getRect(scrollF)),
              'scroll': {'pixels': p.pixels, 'min': p.minScrollExtent, 'max': p.maxScrollExtent, 'vpDim': p.viewportDimension}})}');
            stopWithFrames(why, 'reach:$what');
          }

          for (var i = 0; i < 2; i++) {
            final pe = partEls(part);
            if (pe == null) reachFail('$part 요소 없음($what)', null);
            final u = unionOf(pe);
            final vp = t.getRect(scrollF);
            if (u.height > vp.height + 0.5) reachFail('$part 시각 줄 높이 ${u.height} > 창 ${vp.height}', u);
            if (inside(u, vp) && fe(pe.change).hitTestable().evaluate().length == 1) return;
            final margin = ((vp.height - u.height) / 2) < 16 ? (vp.height - u.height) / 2 : 16.0;
            final below = u.bottom > vp.bottom;
            final d = below ? u.bottom - vp.bottom : vp.top - u.top;
            final dy = below ? -(d + kDragSlopDefault + margin) : (d + kDragSlopDefault + margin);
            final st = pos();
            final before0 = st.pixels;
            nDrag++;
            budget();
            await t.drag(scrollF, Offset(0, dy));
            guard('drag:$what');
            await frames(3, 'drag:$what');
            _out('D303-REACH ${jsonEncode({'phase': phase, 'cond': c.id, 'what': what, 'try': i, 'union': rectL(u), 'viewport': rectL(vp),
              'd': d, 'margin': margin, 'dy': dy, 'before': before0, 'after': st.pixels})}');
          }
          final pe = partEls(part);
          if (pe == null) reachFail('$part 요소 없음($what)', null);
          final u = unionOf(pe);
          if (!(inside(u, t.getRect(scrollF)) && fe(pe.change).hitTestable().evaluate().length == 1)) {
            reachFail('$part 시각 줄 비도달 ${rectL(u)}', u);
          }
        }

        // 부모 열림 frame(애니메이션 완료) — 머리·고정 행동·색
        stage = 'parentOpen';
        final f0 = parentFrame('open');
        final headIcon = find.descendant(of: dialogF, matching: find.byWidgetPredicate((w) => w is Icon && w.icon == md.icon));
        need(headIcon.evaluate().length == 1, '머리 아이콘 수 ${headIcon.evaluate().length}');
        final cardMat = t.widget<Material>(cardF).color ?? Colors.white;
        final faceBg = Color.alphaBlend(md.face.withValues(alpha: 0.15), Color.alphaBlend(md.face.withValues(alpha: 0.1), cardMat));
        final hiFg = t.widget<Icon>(headIcon).color;
        final closeIcon = t.widget<Icon>(find.descendant(of: closeF, matching: find.byType(Icon)));
        final ctaMat = t.widget<Material>(find.descendant(of: ctaF, matching: find.byType(Material)).first);
        final ctaRp = t.renderObject<RenderParagraph>(find.descendant(of: ctaF, matching: find.byType(RichText)).first);
        final ctaFg = ctaRp.text.style?.color;
        final titleRichF = find.descendant(of: dialogF, matching: richExact(md.title));
        // [r2 — TB 중단 판정 §3] 읽기 이름 원자료: 부모 제목 RichText(titleRichF, 이 Dialog 안)를 앵커로 그 글을 담은 실제
        //   SemanticsNode(소유 노드 또는 병합 조상, SDK SemanticsController.find)를 찾는다. 판정에는 find.bySemanticsLabel 과 같은
        //   node.label 을 쓰고, 줄바꿈(nl)으로 나눈 줄 하나가 제목과 정확히 같아야 한다. trim·정규화·부분 일치·fallback 은 없다.
        Map<String, Object?> semNodeOf(Finder f) {
          final n = f.evaluate().length;
          try {
            final node = t.semantics.find(f);
            return {'anchorCount': n, 'found': true, 'nodeId': node.id, 'label': node.label, 'mergedIntoParent': node.isMergedIntoParent};
          } on StateError catch (e) {
            return {'anchorCount': n, 'found': false, 'error': e.message};
          }
        }
        final semTitleExact = find.bySemanticsLabel(md.title).evaluate().length;
        final semCtaExact = find.bySemanticsLabel(md.cta).evaluate().length;
        final semTitleNode = semNodeOf(titleRichF);
        final semTitleLabel = semTitleNode['label'];
        final semTitleLine = semTitleLabel is String && semTitleLabel.split(nl).any((line) => line == md.title);
        final semCtaNode = semNodeOf(ctaF);
        row['open'] = {
          ...f0,
          'clip': {'title': clipInfo(titleRichF, screen), 'close': clipInfo(closeF, screen), 'cancel': clipInfo(cancelF, screen),
            'cta': clipInfo(ctaF, screen), 'ctaLabel': clipInfo(find.descendant(of: ctaF, matching: find.byType(RichText)).first, screen)},
          'headIcon': {'fg': hiFg == null ? null : _hex(hiFg), 'bg': _hex(faceBg), 'contrast': hiFg == null ? null : _contrast(hiFg, faceBg),
            'cardMaterial': _hex(cardMat)},
          // [r3 — TA 중단 감사 §4-2] X 의 RenderBox.size 원자료(같은 closeF, 단언 전, 추가 pump 없음)
          'close': {...recv(closeF), 'iconColor': closeIcon.color == null ? null : _hex(closeIcon.color!),
            'renderBoxSize': [t.getSize(closeF).width, t.getSize(closeF).height]},
          'cancel': recv(cancelF),
          'cta': {...recv(ctaF), 'label': TextLayout.plain(ctaRp.text.toPlainText()), 'fill': ctaMat.color == null ? null : _hex(ctaMat.color!),
            'fg': ctaFg == null ? null : _hex(ctaFg), 'contrast': (ctaMat.color == null || ctaFg == null) ? null : _contrast(ctaFg, ctaMat.color!),
            'ellipsis': ctaRp.didExceedMaxLines},
          'semTitle': semTitleExact,
          'semCta': semCtaExact,
          'semTitleLine': semTitleLine,
          'semTitleNode': semTitleNode,
          'ellipsis': find.descendant(of: dialogF, matching: find.byType(RichText)).evaluate()
              .where((e) => (e.renderObject as RenderParagraph).didExceedMaxLines).length,
        };
        _out('D303-OPEN ${jsonEncode({'phase': phase, 'cond': cond, 'pump': nPump, ...(row['open'] as Map<String, Object?>)})}');
        // [r2] 읽기 이름 단언 전에 원문 출력(노드·라벨이 없으면 그 부재도 출력)
        _out('D303-SEM ${jsonEncode({'phase': phase, 'cond': cond, 'pump': nPump, 'expectTitle': md.title, 'expectCta': md.cta,
          'titleAnchor': 'titleRichF(이 Dialog 안 제목 RichText) → SemanticsController.find', 'title': semTitleNode,
          'titleExactCount': semTitleExact, 'titleLineMatch': semTitleLine, 'cta': semCtaNode, 'ctaExactCount': semCtaExact})}');
        hostRec.add(checkHost('parentOpen'));
        nPng++;
        budget();
        await vqCapture(t, capKey, 'D303-$phase-${c.id}-open', conditions: sidecar('parent-open(anim completed)'));
        {
          final o = row['open'] as Map<String, Object?>;
          final hi = o['headIcon'] as Map<String, Object?>;
          final cl = o['close'] as Map<String, Object?>;
          final cn = o['cancel'] as Map<String, Object?>;
          final ct = o['cta'] as Map<String, Object?>;
          final cp = o['clip'] as Map<String, Object?>;
          bool fullOf(String k) => (cp[k] as Map<String, Object?>)['full'] == true;
          for (final k in const ['title', 'close', 'cancel', 'cta', 'ctaLabel']) {
            need(((cp[k] as Map<String, Object?>)['unsupported'] as List).isEmpty, '열림 $k 지원 밖 clip ${(cp[k] as Map)['unsupported']}');
          }
          // 공통(before·after): 고정 행동 hit·화면 안·실제 clip 전부 보임, 제목·CTA 읽기 이름, 말줄임 0
          need(cl['hit'] == true && cl['inScreen'] == true && fullOf('close'), 'X 가시/hit $cl');
          need(cn['hit'] == true && cn['inScreen'] == true && fullOf('cancel'), '취소 가시/hit $cn');
          need(ct['hit'] == true && ct['inScreen'] == true && fullOf('cta') && fullOf('ctaLabel') && ct['ellipsis'] == false, '최종 처리 가시/hit $ct');
          need(fullOf('title'), '제목 clip ${cp['title']}');
          need(o['semTitleLine'] == true && (o['semCta'] as int) >= 1,
              '읽기 이름 제목(완전줄)/CTA(정확) ${o['semTitleLine']}/${o['semCta']} 제목 노드 ${o['semTitleNode']}');
          need(o['ellipsis'] == 0, '부모 말줄임 ${o['ellipsis']}');
          if (after) {
            // after 만: 색·대비·최소 크기(before 의 옛 색·최소치 미달은 기록 차이)
            need(hi['fg'] == _hex(md.iconFg) && (hi['contrast'] as double) >= 3.0, '머리 아이콘 $hi');
            // [r3 — 사용자 예외 승인] 최소 크기 네 단언에만 _kEps(1e-6) 공차: 전역 rect 차의 부동소수 잔차를 흡수한다. 색·대비는 그대로.
            need(cl['iconColor'] == _hex(AppColors.textSecondary) && (cl['w'] as double) >= 48 - _kEps && (cl['h'] as double) >= 48 - _kEps, 'X $cl');
            need((cn['w'] as double) >= 64 - _kEps && (cn['h'] as double) >= 52 - _kEps, '취소 $cn');
            need((ct['w'] as double) >= 64 - _kEps && (ct['h'] as double) >= 52 - _kEps && ct['fill'] == _hex(AppColors.brand) && ct['fg'] == _hex(Colors.white) &&
                (ct['contrast'] as double) >= 4.5, '최종 처리 $ct');
          }
        }

        // 피킹 파트 시각 줄 도달·검사
        Future<Map<String, Object?>> partFrame(String part, String tag, {required String expectTime}) async {
          await reachRow(part, '$part 시각 줄($tag)');
          // [t4] 이 frame 의 전체 Flex 를 먼저 출력하고(단언 없음), 파트 원자료 출력 뒤에 둘 다 단언한다
          final frame = parentFrameRec(tag);
          final pe0 = partEls(part);
          if (pe0 == null) stopWithFrames('$part 파트 요소 없음 at $tag', 'part:$tag');
          final pe = pe0;
          final box = t.getRect(fe(pe.box));
          final time = t.getRect(fe(pe.time));
          final ch = t.getRect(fe(pe.change));
          final vp = t.getRect(scrollF);
          final timeText = plainOf(pe.time);
          final timeRp = pe.time.renderObject as RenderParagraph;
          final boxDeco = (pe.box.widget as DecoratedBox).decoration as BoxDecoration;
          final ob = pe.change.widget as OutlinedButton;
          final sideColor = ob.style?.side?.resolve(const <WidgetState>{})?.color;
          final chRp = t.renderObject<RenderParagraph>(richExact('변경', within: fe(pe.change)));
          final branchColumn = ch.top >= box.bottom - 0.5;
          final rec0 = <String, Object?>{
            'part': part, 'tag': tag, 'time': timeText, 'boxRect': rectL(box), 'timeRect': rectL(time), 'changeRect': rectL(ch),
            'viewportRect': rectL(vp), 'branch': branchColumn ? 'column' : 'row', 'overhang': time.right - box.right,
            'overlapWithChange': branchColumn ? 0.0 : time.right - ch.left, 'timeInBox': inside(time, box), 'timeInViewport': inside(time, vp),
            'timeInScreen': inside(time, screen), 'change': recv(fe(pe.change)), 'boxBg': boxDeco.color == null ? null : _hex(boxDeco.color!),
            'timeFg': timeRp.text.style?.color == null ? null : _hex(timeRp.text.style!.color!),
            'timeContrast': (boxDeco.color == null || timeRp.text.style?.color == null) ? null : _contrast(timeRp.text.style!.color!, boxDeco.color!),
            'iconColor': pe.icon == null ? null : ((pe.icon!.widget as Icon).color == null ? null : _hex((pe.icon!.widget as Icon).color!)),
            'changeSide': sideColor == null ? null : _hex(sideColor),
            'changeFg': chRp.text.style?.color == null ? null : _hex(chRp.text.style!.color!),
            'clipTime': clipInfo(fe(pe.time), screen),
            'clipChange': clipInfo(fe(pe.change), screen),
            'clipChangeLabel': clipInfo(richExact('변경', within: fe(pe.change)), screen),
          };
          _out('D303-PART ${jsonEncode({'phase': phase, 'cond': cond, 'pump': nPump, ...rec0})}');
          // 여기부터 단언(이 frame 의 전체 Flex·파트 원자료는 위에서 이미 출력됨)
          assertParentFrame(frame);
          need(timeText == expectTime, '$part 시각 $timeText ≠ $expectTime at $tag');
          // 공통(before·after): 시각 글자·변경의 실제 paint clip 전부 보임(지원 밖 clip 없음)·창/화면 안, 변경 hit
          final cv0 = rec0['change'] as Map<String, Object?>;
          for (final k in const ['clipTime', 'clipChange', 'clipChangeLabel']) {
            need(((rec0[k] as Map<String, Object?>)['unsupported'] as List).isEmpty, '$part $k 지원 밖 clip ${(rec0[k] as Map)['unsupported']} at $tag');
          }
          need((rec0['clipTime'] as Map<String, Object?>)['full'] == true && rec0['timeInViewport'] == true && rec0['timeInScreen'] == true,
              '$part 시각 전문 가시 at $tag');
          need((rec0['clipChange'] as Map<String, Object?>)['full'] == true && (rec0['clipChangeLabel'] as Map<String, Object?>)['full'] == true &&
              cv0['hit'] == true && cv0['inScreen'] == true, '$part 변경 가시/hit at $tag');
          if (after) {
            need(branchColumn == isB, '$part 배치 ${rec0['branch']}(B 는 column, W 는 row) at $tag');
            if (branchColumn) {
              need((ch.right - box.right).abs() <= 0.5 && ch.width < box.width, '$part 세로 배치 변경 끝쪽 정렬·전폭 아님 at $tag');
            }
            final cv = rec0['change'] as Map<String, Object?>;
            need(rec0['timeInBox'] == true && (branchColumn || time.right <= ch.left + 0.5), '$part 시각 상자 안·변경과 분리 at $tag');
            need((cv['w'] as double) >= 64 - _kEps && (cv['h'] as double) >= 48 - _kEps, '$part 변경 receiver $cv');
            need(rec0['boxBg'] == _hex(AppColors.grey100) && rec0['timeFg'] == _hex(AppColors.textPrimary) &&
                (rec0['timeContrast'] as double) >= 4.5 && rec0['iconColor'] == _hex(AppColors.textSecondary), '$part 시각 상자 색 $rec0');
            need(rec0['changeSide'] == _hex(AppColors.brand) && rec0['changeFg'] == _hex(AppColors.brand), '$part 변경 색 $rec0');
          } else if (isB) {
            // before B 알려진 baseline(D2 감사 §3): 상자 우측 돌출·변경 겹침(그 밖의 가시·hit 조건은 위 공통 검사로 면제하지 않음)
            need(near(time.right - box.right, _kOverhang, _kTol) && near(time.right - ch.left, _kOverlap, _kTol),
                'before B baseline 돌출/겹침 ${time.right - box.right}/${time.right - ch.left} at $tag');
          } else {
            // before W: 예외 0 — 시각 글자는 상자 안, 변경과 겹치지 않아야 한다
            need(rec0['timeInBox'] == true && time.right <= ch.left + 0.5, 'before W 시각 상자 안·분리 at $tag');
          }
          return {...rec0, 'frame': frame};
        }

        // 자식 시트 도달·검사·행동
        Finder sheet() => find.byType(BottomSheet);
        Map<String, Object?> childFrame(String tag) {
          final s = sheet();
          need(s.evaluate().length == 1, '자식 시트 수 ${s.evaluate().length} at $tag');
          final flexAll = <Map<String, Object?>>[];
          for (final e in find.descendant(of: s, matching: find.byWidgetPredicate((w) => w is Flex)).evaluate()) {
            flexAll.add(flexInfo(e.renderObject as RenderFlex));
          }
          final fr = <String, Object?>{'phase': phase, 'cond': cond, 'tag': tag, 'pump': nPump, 'sheetRect': rectL(t.getRect(s)),
            'title': richExact(md.childTitle, within: s).evaluate().length, 'flexAll': flexAll};
          _out('D303-CHILD ${jsonEncode(fr)}');
          for (final info in flexAll) {
            need((info['over'] as double) <= _kEps, '자식 Flex 넘침 ${info['hash']} ${info['over']} at $tag');
          }
          need(fr['title'] == 1, '자식 제목 ${md.childTitle} ${fr['title']} at $tag');
          return fr;
        }

        Future<void> childOpen(String part, String tag) async {
          final pe = partEls(part)!;
          nChild++;
          await tapAt(fe(pe.change), '$part 변경');
          for (var i = 0; i < 10; i++) {
            await frames(1, '$tag:childAnim');
            if (sheet().evaluate().length == 1) {
              final r = ModalRoute.of(t.element(sheet()));
              if (r != null && r.animation != null && r.animation!.status == AnimationStatus.completed) break;
            }
          }
          if (sheet().evaluate().length != 1) stopWithFrames('자식 시트 열림 실패 at $tag', 'childOpen:$tag');
          final cr = ModalRoute.of(t.element(sheet()));
          if (!(cr != null && cr.animation != null && cr.animation!.status == AnimationStatus.completed)) {
            stopWithFrames('자식 애니메이션 미완료 at $tag', 'childOpen:$tag');
          }
          childPopped[tag] = false;
          childResults[tag] = 'unset';
          cr.popped.then((v) {
            childPopped[tag] = true;
            childResults[tag] = v;
          });
        }

        Future<void> childClosed(String tag) async {
          for (var i = 0; i < 10 && sheet().evaluate().isNotEmpty; i++) {
            await frames(1, '$tag:childClose');
          }
          await frames(2, '$tag:settle');
          if (sheet().evaluate().isNotEmpty) stopWithFrames('자식 시트 닫힘 실패 at $tag', 'childClosed:$tag');
          if (dialogF.evaluate().length != 1) stopWithFrames('부모가 남아 있지 않음 at $tag', 'childClosed:$tag');
        }

        Finder childScroll() => find.descendant(of: sheet(), matching: find.byType(SingleChildScrollView));
        Future<void> childReachTap(Finder f, String what) async {
          if (childScroll().evaluate().length == 1 && find.ancestor(of: f, matching: find.byType(SingleChildScrollView)).evaluate().isNotEmpty) {
            await reachIn(f, childScroll(), what);
          }
          await tapAt(f, what);
          await frames(3, what);
        }

        // ── 1) 피킹 변경 → 자식(예정 칩 → +10 → 확정) ──
        stage = 'part1';
        row['part1'] = await partFrame('피킹', 'part1', expectTime: md.pick);
        hostRec.add(checkHost('part1'));
        stage = 'child1';
        await childOpen('피킹', 'child1');
        row['child1'] = childFrame('child1');
        hostRec.add(checkHost('child1'));
        final chip = find.descendant(of: sheet(), matching: find.byWidgetPredicate((w) => w is InkWell)).evaluate().where((e) =>
            richExact('예정  ${md.pick}', within: fe(e)).evaluate().length == 1).toList();
        need(chip.length == 1, '예정 칩 수 ${chip.length}');
        await childReachTap(fe(chip.first), '예정 칩');
        final plus = find.descendant(of: sheet(), matching: find.byWidgetPredicate((w) => w is InkWell)).evaluate().where((e) =>
            find.descendant(of: fe(e), matching: find.byIcon(Icons.add)).evaluate().length == 1).toList();
        need(plus.length == 1, '+10 수 ${plus.length}');
        await childReachTap(fe(plus.first), '+10');
        row['child1After'] = childFrame('child1After');
        hostRec.add(checkHost('child1After'));
        final confirm = find.descendant(of: sheet(), matching: find.byWidgetPredicate((w) => w is ElevatedButton));
        need(confirm.evaluate().length == 1, '자식 확정 수 ${confirm.evaluate().length}');
        final confirmLabel = TextLayout.plain(t.renderObject<RenderParagraph>(find.descendant(of: confirm, matching: find.byType(RichText)).first)
            .text.toPlainText());
        need(confirmLabel.startsWith('${md.picked} 로 '), '자식 확정 글 $confirmLabel');
        await tapAt(confirm, '자식 확정');
        await childClosed('child1');
        need(childPopped['child1'] == true && childResults['child1'] == md.picked, '자식1 반환 ${childPopped['child1']}/${childResults['child1']}');

        // ── 2) 부모 갱신·불변 확인 ──
        stage = 'return';
        row['return'] = await partFrame('피킹', 'return', expectTime: md.picked);
        final other = partEls('포장');
        need(other != null && plainOf(other.time) == md.other, '포장 시각 불변 ${other == null ? null : plainOf(other.time)}');
        hostRec.add(checkHost('return'));
        nPng++;
        budget();
        await vqCapture(t, capKey, 'D303-$phase-${c.id}-return', conditions: sidecar('parent-after-child-confirm(${md.picked})'));
        if (isB) {
          // B 끝 장면: 포장 시각 줄까지 실제 drag 로 도달
          stage = 'end';
          row['end'] = await partFrame('포장', 'end', expectTime: md.other);
          hostRec.add(checkHost('end'));
          nPng++;
          budget();
          await vqCapture(t, capKey, 'D303-$phase-${c.id}-end', conditions: sidecar('parent-second-part-reached'));
        }

        // ── 3) 피킹 변경 다시 → 자식 W 취소 / B X → 부모 값 유지 ──
        stage = 'part1again';
        row['part1again'] = await partFrame('피킹', 'part1again', expectTime: md.picked);
        hostRec.add(checkHost('part1again'));
        stage = 'child2';
        await childOpen('피킹', 'child2');
        row['child2'] = childFrame('child2');
        hostRec.add(checkHost('child2'));
        if (isB) {
          final x = find.descendant(of: sheet(), matching: find.widgetWithIcon(IconButton, Icons.close));
          await tapAt(x, '자식 X');
        } else {
          final cancel = find.descendant(of: sheet(), matching: find.widgetWithText(OutlinedButton, '취소'));
          await childReachTap(cancel, '자식 취소');
        }
        await childClosed('child2');
        need(childPopped['child2'] == true && childResults['child2'] == null, '자식2 반환 ${childPopped['child2']}/${childResults['child2']}');
        stage = 'keep';
        row['keep'] = await partFrame('피킹', 'keep', expectTime: md.picked);
        final other2 = partEls('포장');
        need(other2 != null && plainOf(other2.time) == md.other, '포장 시각 불변(keep)');
        hostRec.add(checkHost('keep'));

        // ── 4) 부모 W 취소 / B X → 닫힘(null, 처리 0) ──
        stage = 'parentClose';
        if (isB) {
          await tapAt(closeF, '부모 X');
        } else {
          await tapAt(cancelF, '부모 취소');
        }
        for (var i = 0; i < 8 && titleF.evaluate().isNotEmpty; i++) {
          await frames(1, 'parentClose');
        }
        await frames(2, 'parentClose:settle');
        need(titleF.evaluate().isEmpty, '부모 닫힘 실패');
        need(find.byType(BottomSheet).evaluate().isEmpty, '자식 시트 잔존');
        need(parentPopped && parentResult == null, '부모 반환 $parentPopped/$parentResult(null 이어야 처리 경로 0)');
        hostRec.add(checkHost('parentClosed'));
        // 최초 보고 건수: host B 1건/W 0건, 부모 before B 는 피킹·포장 각 1건, 그 밖 0건
        need(hostErrCount == (isB ? 1 : 0), 'host 최초 보고 수 $hostErrCount');
        if (!after && isB) {
          need(parentErrParts.length == 2 && parentErrParts.toSet().containsAll({'피킹', '포장'}), '부모 최초 보고 파트 $parentErrParts');
        } else {
          need(parentErrParts.isEmpty, '부모 오류 $parentErrParts');
        }
        row['firstReports'] = {'host': hostErrCount, 'parent': parentErrParts.toList()};
        row['popped'] = {'parent': {'popped': parentPopped, 'result': parentResult}, 'child': {
          for (final k in childPopped.keys) k: {'popped': childPopped[k], 'result': childResults[k]}}};
        row['host'] = hostRec;
        row['counts'] = counts();
        rows.add(row);
        _out('D303 ${jsonEncode(row)}');

        // ── host teardown(닫기·null 반환 성공으로 세지 않는다) ──
        stage = 'teardown';
        await mount(const SizedBox.shrink());
        await frames(2, 'teardown');
        visited.add(c.id);
      }
      need(visited.join('|') == 'W360_IN|W360_OUT|B320_IN|B320_OUT', '방문 $visited');
      need(nParent == 4 && nChild == 8, '부모/자식 열기 $nParent/$nChild');
      need(nPng == 10, 'PNG $nPng');
      _out('D303-END ${jsonEncode({...counts(), 'visited': visited, 'http': net.created, 'business': biz, 'readsAfterFreeze': afterFreeze,
        'errors': errLog.map((e) => '${e['cond']}/${e['stage']}#${e['pump']}: ${e['kind']} ${e['first']} raw ${e['raw']}').toList()})}');
    } finally {
      _out('D303-FINAL ${jsonEncode({...counts(), 'visited': visited, 'http': net.created, 'business': biz, 'readsAfterFreeze': afterFreeze,
        'errorsLogged': errLog.length, 'errorsPending': errors.length})}');
      for (final op in _fsOps) {
        m.setMockMessageHandler('$_fsBase.$op', null);
      }
      for (final op in _fnOps) {
        m.setMockMessageHandler('$_fnBase.$op', null);
      }
      m.setMockMethodCallHandler(const MethodChannel(_fnLegacy), null);
      sem.dispose();
      FlutterError.onError = prevOnError;
      HttpOverrides.global = prevHttp;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
