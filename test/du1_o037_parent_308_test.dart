// ignore_for_file: depend_on_referenced_packages
// [DU308 DU-O037-PARENT-PREP-308] O037 부모 확인창 표면·짧은 행동명 — before/after 같은 순서. **초안 r2(정적, 실행일 미정)**.
//   r2(11-13 Codex 읽기전용 검토 반영): 고정 대상 가시/hit·포함·겹침 양 phase 단언, 단락 자체 잘림·글자 상자 범위, after CTA 가운데 정렬,
//   before 아이콘 대비의 실제 머리 면 합성, 줄 경계 원자료(raw code unit·제어문자 대응·line metrics) 출력, 피킹 카드 정확 1, load 주석 정정.
//   근거: requests/DU_implementation_308.md §1–§3, reports/DU_audit_308.md, reports/DU_audit_308_r3base.md,
//     work/du308-prep-audit-20261112/agent-test/review.md §2–§3, 새 base 판정(11-13 읽기 전용: base 6986dee1 · cand 19d4ccf8).
//   DU308_RUN=1, DU308_PHASE=before|after, DU308_DAY=_kDay 일 때만 실행(기본 skip). 실제 KST 날짜·08:00–21:30 도 검증한다.
//   조건: W360×780/1.0·B320×640/2.0 × IN(22:00/22:30 시작, 근태 없음)·OUT(06:00/07:00 출근, 23:00/23:30 퇴근 예정) = 4(DU303 fixture 축약 복사).
//   흐름(조건마다): load → 정상 탭 → 전체 → (DU305 맞춤 ≥250ms) → 단계 버튼 → 부모 열림(애니메이션 완료, 고정 대상 검사·PNG 1)
//     → 첫 파트(피킹) 시각 줄 도달·검사 → W 취소 / B X → null 반환 → 선택 2 유지 → 빈 teardown.
//   변경·전체설정·주 CTA·자식 시트·검색·barrier/back tap 0. 실제 tap/drag 만 쓰고 callback 직접 호출·값 주입·Navigator.pop 직접 호출 0.
//   DU303 의 B host·부모 overflow 예외표는 승계하지 않는다 — 두 phase 모두 FlutterError/overflow 0.
//   PNG 는 DU1_VQ_PHASE 를 쓰지 않는다(회귀 캡처 비활성). DU308_OUT/<phase>/ 에만 쓴다(덮어쓰기 거부).
//   after 는 흰 Dialog·머리 장식 0·타일 α.15·실제 줄 경계(낱말/구분점)·색을 단언하고, before 는 같은 측정을 같은 순서로 기록만 한다.
//   두 phase 공통 단언: 오류·네트워크·업무 채널·동결 뒤 읽기 0, 읽기 사전표, 도달 한도, 고정 대상 가시/hit, 의미 이름 원문,
//     기존 receiver(닫기 48·변경 시각 ≥64×48·취소/CTA 시각 높이 ≥52·receiver ≥48×48), null 닫힘, 계측(재구성) 유효.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

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

import 'support/du1_vq_capture.dart' show vqLoadFonts;

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
    throw StateError('DU308 network guard');
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

String _argb(Color c) => c.toARGB32().toRadixString(16).padLeft(8, '0').toUpperCase();

// [초안] 실행일은 Codex 실행 지시로 확정한다. fixture 날짜 = 실행일(DU303 와 같다 — host 가 실제 now 로 상태를 나누므로 22:00 전 실행).
const _kDay = '2026-11-15'; // [11-15 자체검토 허브] 실행일 고정
const _biz = 'biz308';
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
// phase 상한 C(요청 §4) — (pump, host mount, tap+dispatch, drag, 명시 route, text, PNG). 정상 빈 teardown 은 nEmpty 로 따로 센다.
//   산식(agent-test review §3): 조건당 load ≤17 + tab 8 + select 8 + open(발견 ≤3 + 애니메이션 ≤6) + close(≤8 + settle 2) + teardown 2 = 54,
//   4조건 216 + B drag(정상 가로 ≤2·전체 세로 ≤2·첫 파트 세로 ≤2)×2조건×3frame 36 = 252 ≤ 260.
const _kC = (pump: 260, mount: 4, tap: 16, drag: 12, route: 4, text: 0, png: 4);
const _wj = 0x2060, _zwsp = 0x200B, _nbsp = 0x00A0, _dot = 0x00B7, _space = 0x20;

Map<String, dynamic> _ts(DateTime d) => {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

void main() {
  final env = Platform.environment;
  final phase = env['DU308_PHASE'] ?? '';
  final dayArg = env['DU308_DAY'] ?? '';
  final outDir = env['DU308_OUT'] ?? '';
  final run = env['DU308_RUN'] == '1' && (phase == 'before' || phase == 'after') && dayArg == _kDay;
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    if (!run) return;
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('D308 $phase', (t) async {
    final day = DateTime.parse(_kDay);
    final dayKey = FormatHelper.kstDayKeyOfCivil(day);
    DateTime kstNow() => DateTime.now().toUtc().add(const Duration(hours: 9));

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
        return const StandardMessageCodec().encodeMessage(<Object?>['du308-blocked', 'firestore $op 차단', null]);
      });
    }
    for (final op in _fnOps) {
      m.setMockMessageHandler('$_fnBase.$op', (msg) async {
        biz['fn.$op'] = (biz['fn.$op'] ?? 0) + 1;
        return const StandardMessageCodec().encodeMessage(<Object?>['du308-blocked', 'functions $op 차단', null]);
      });
    }
    m.setMockMethodCallHandler(const MethodChannel(_fnLegacy), (call) async {
      biz['fn.legacy.${call.method}'] = (biz['fn.legacy.${call.method}'] ?? 0) + 1;
      throw PlatformException(code: 'du308-blocked', message: 'functions legacy ${call.method} 차단');
    });

    var nPump = 0, nMount = 0, nEmpty = 0, nTap = 0, nDrag = 0, nRoute = 0, nText = 0, nPng = 0;
    Map<String, Object?> counts() => {'phase': phase, 'pump': nPump, 'hostMount': nMount, 'emptyMount': nEmpty, 'tap': nTap,
      'drag': nDrag, 'route': nRoute, 'text': nText, 'png': nPng};

    var cond = '-';
    var stage = 'start';
    final errors = <({String cond, String stage, int pump, String first, String full})>[];
    FlutterError.onError = (d) => errors.add((
          cond: cond,
          stage: stage,
          pump: nPump,
          first: d.exceptionAsString().split(nl).first,
          full: TextTreeRenderer(wrapWidth: 400).render(d.toDiagnosticsNode(style: DiagnosticsTreeStyle.error)).trimRight(),
        ));
    final afterFreeze = <String>[];
    final visited = <String>[];
    var live = false;
    var completed = false;

    Never stop(String why) {
      _out('D308-STOP ${jsonEncode({'phase': phase, 'cond': cond, 'stage': stage, 'why': why,
        'pendingErrors': errors.map((e) => '${e.cond}/${e.stage}#${e.pump}: ${e.first}').toList(), 'counts': counts(),
        'http': net.created, 'business': biz, 'readsAfterFreeze': afterFreeze})}');
      for (final e in errors) {
        _out('D308-STOPERR ${jsonEncode({'cond': e.cond, 'stage': e.stage, 'pump': e.pump, 'full': e.full})}');
      }
      fail('$phase/$cond/$stage: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    // after 만 단언, before 는 같은 측정을 기록만 한다
    void check(bool ok, String what, [Object? detail]) {
      _out('D308-CHECK ${jsonEncode({'phase': phase, 'cond': cond, 'stage': stage, 'what': what, 'ok': ok, 'assert': after, 'detail': detail})}');
      if (after) need(ok, '$what ${detail ?? ''}');
    }

    void budget() {
      final ok = nPump <= _kC.pump && nMount <= _kC.mount && nTap <= _kC.tap && nDrag <= _kC.drag && nRoute <= _kC.route &&
          nText <= _kC.text && nPng <= _kC.png && nEmpty <= 4;
      need(ok, '한도 C 초과 ${counts()}');
    }

    void clockGuard(String where) {
      final k = kstNow();
      final min = k.hour * 60 + k.minute;
      final key = '${k.year.toString().padLeft(4, '0')}-${k.month.toString().padLeft(2, '0')}-${k.day.toString().padLeft(2, '0')}';
      need(key == _kDay, '$where 실행일 이탈 kst=$k pin=$dayArg');
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
    Rect rectOf(Element e) {
      final ro = e.renderObject! as RenderBox;
      return MatrixUtils.transformRect(ro.getTransformTo(null), Offset.zero & ro.size);
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

    Map<String, Object?> flexInfo(RenderFlex rf) {
      final kids = <double>[];
      var ch = rf.firstChild;
      while (ch != null) {
        kids.add(rf.direction == Axis.horizontal ? ch.size.width : ch.size.height);
        ch = rf.childAfter(ch);
      }
      final mainExt = rf.direction == Axis.horizontal ? rf.size.width : rf.size.height;
      final sum = kids.fold<double>(0, (a, b) => a + b) + (kids.isEmpty ? 0 : rf.spacing * (kids.length - 1));
      return {'hash': shortHash(rf), 'dir': rf.direction.name, 'main': mainExt, 'sum': sum, 'over': sum - mainExt};
    }

    // 매 pump·mount·행동 뒤 즉시 검사: 예외·오류(예외표 없음 — DU303 B host/부모 예외 불허)·네트워크/업무 채널·동결 뒤 Reads
    void guard(String where) {
      final ex = t.takeException();
      need(ex == null, '$where 예외: $ex');
      for (final e in errors) {
        _out('D308-ERR ${jsonEncode({'phase': phase, 'cond': e.cond, 'stage': e.stage, 'pump': e.pump, 'first': e.first, 'full': e.full})}');
        stop('FlutterError(허용 0) ${e.first} at $where');
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

    Future<void> tapAt(Finder f, String what) async {
      need(f.evaluate().length == 1, '$what 대상 수 ${f.evaluate().length}');
      need(f.hitTestable().evaluate().length == 1, '$what 중심 hit 아님');
      nTap++;
      budget();
      await t.tap(f);
      guard('tap:$what');
    }

    // [DU303 t4·t5] 실제 paint clip chain(정확 사각 목록만 교차, 그 밖은 unsupported)
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
      RenderObject child = ro;
      RenderObject? p = ro.parent;
      while (p != null) {
        final local = p.describeApproximatePaintClip(child);
        if (local != null) {
          final type = p.runtimeType.toString();
          final global = MatrixUtils.transformRect(p.getTransformTo(null), local);
          final clipperNull = p is RenderClipRect ? p.clipper == null : null;
          final exact = rectClipTypes.contains(type) && (clipperNull ?? true);
          chain.add({'parent': type, 'global': rectL(global), 'rectExact': exact});
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
      return {'rect': rectL(rect), 'visible': shown ? rectL(vis) : null, 'full': full, 'clipChain': chain, 'unsupported': unsupported};
    }

    // [요청 §2:22 · agent-test review §2] 실제 RenderParagraph 재구성(±0.01)과 raw UTF16 줄 경계.
    //   WJ·ZWSP 는 표시 0, NBSP 는 공백으로 시험 안에서 독립 매핑한다(production helper 재호출 0). 경계 허용:
    //   낱말(제목·전체설정·CTA) = 경계 앞 표시 글자가 일반 공백, 구분(부제) = 같은 조건 + 다음 줄 첫 표시 글자가 '·' 아님.
    Map<String, Object?> lineRec(Element e, String what, String original, {required bool phrases}) {
      final ro = e.renderObject;
      need(ro is RenderParagraph, '$what RenderParagraph 아님');
      final p = ro! as RenderParagraph;
      var placeholder = false;
      p.text.visitChildren((s) {
        if (s is PlaceholderSpan) {
          placeholder = true;
          return false;
        }
        return true;
      });
      need(!placeholder, '$what placeholder — 치수 없이 재구성하지 않는다(계측 실패)');
      final ellipsis = p.overflow == TextOverflow.ellipsis;
      final tp = TextPainter(
        text: p.text, textAlign: p.textAlign, textDirection: p.textDirection, textScaler: p.textScaler, maxLines: p.maxLines,
        ellipsis: ellipsis ? '…' : null, locale: p.locale, strutStyle: p.strutStyle, textWidthBasis: p.textWidthBasis,
        textHeightBehavior: p.textHeightBehavior,
      )..layout(minWidth: p.constraints.minWidth, maxWidth: (p.softWrap || ellipsis) ? p.constraints.maxWidth : double.infinity);
      final ts = p.textSize;
      final tsz = tp.size;
      final cs = p.constraints.constrain(tsz);
      final ok = near(tsz.width, ts.width, _kTol) && near(tsz.height, ts.height, _kTol) && near(cs.width, p.size.width, _kTol) &&
          near(cs.height, p.size.height, _kTol);
      final units = tp.plainText.codeUnits;
      final ranges = <List<int>>[];
      final metrics = tp.computeLineMetrics();
      for (final lm in metrics) {
        final b = tp.getLineBoundary(tp.getPositionForOffset(Offset(lm.left + lm.width / 2, lm.baseline - lm.ascent / 2)));
        ranges.add([b.start, b.end]);
      }
      tp.dispose();
      // 단락 자체 잘림(SDK paragraph.dart:992 의 clip 조건)과 글자 줄 상자가 단락 상자 안인지 — 조상 clip(clipInfo)과 구분한다
      final selfOverflow = ts.width > p.size.width + _kEps || ts.height > p.size.height + _kEps || p.didExceedMaxLines;
      final toGlobal = p.getTransformTo(null);
      final glyphLocal = [for (final lm in metrics) Rect.fromLTRB(lm.left, lm.baseline - lm.ascent, lm.left + lm.width, lm.baseline + lm.descent)];
      // [11-15 자체검토 r1] 줄 상자(lineMetrics: baseline−ascent … +descent, left … left+width)는 폰트 계측상 단락 상자를
      //   부분 화소만큼 넘을 수 있다(TB 실측: 제목 top −0.31 · right +0.125, selfOverflow false). 잘림 판정은 selfOverflow(SDK clip 조건)가
      //   맡고, 이 줄 상자 대조는 0.5 화소 안을 허용한다(1 화소 이상 벗어나면 그대로 실패).
      const glyphEps = 0.5;
      final glyphInBox = glyphLocal.every((g) => g.left >= -glyphEps && g.top >= -glyphEps && g.right <= p.size.width + glyphEps &&
          g.bottom <= p.size.height + glyphEps);
      // 제어문자 → 원문 대응: raw 각 위치의 표시 위치(제거되면 -1), NBSP 위치
      final rawToVis = <int>[];
      final nbspAt = <int>[];
      var vi = 0;
      for (var i = 0; i < units.length; i++) {
        if (units[i] == _wj || units[i] == _zwsp) {
          rawToVis.add(-1);
        } else {
          if (units[i] == _nbsp) nbspAt.add(i);
          rawToVis.add(vi++);
        }
      }
      String vis(int s, int end) {
        final sb = StringBuffer();
        for (var i = s; i < end; i++) {
          final u = units[i];
          if (u == _wj || u == _zwsp) continue;
          sb.writeCharCode(u == _nbsp ? _space : u);
        }
        return sb.toString();
      }

      var contiguous = ranges.isNotEmpty && ranges.first[0] == 0 && ranges.last[1] == units.length;
      final breaks = <Map<String, Object?>>[];
      for (var i = 0; i + 1 < ranges.length; i++) {
        if (ranges[i][1] != ranges[i + 1][0]) contiguous = false;
        final b = ranges[i][1];
        var k = b - 1;
        while (k >= 0 && (units[k] == _wj || units[k] == _zwsp)) {
          k--;
        }
        var n = b;
        while (n < units.length && (units[n] == _wj || units[n] == _zwsp || units[n] == _space)) {
          n++;
        }
        final before = k >= 0 ? units[k] : -1;
        final next = n < units.length ? units[n] : -1;
        final allowed = before == _space && (!phrases || next != _dot);
        breaks.add({'offset': b, 'before': before, 'next': next, 'allowed': allowed});
      }
      final lines = [for (final r in ranges) vis(r[0], r[1])];
      final textW = nearest(e, (w) => w is Text);
      final st = p.text.style;
      final rec = <String, Object?>{'phase': phase, 'cond': cond, 'what': what, 'original': original, 'plain': vis(0, units.length),
        'rawUnits': [for (final u in units) u.toRadixString(16)], 'rawToVis': rawToVis, 'nbspAt': nbspAt,
        'lineMetrics': [for (final lm in metrics) {'n': lm.lineNumber, 'left': lm.left, 'width': lm.width, 'baseline': lm.baseline,
          'ascent': lm.ascent, 'descent': lm.descent, 'height': lm.height, 'hard': lm.hardBreak}],
        'glyphGlobal': [for (final g in glyphLocal) rectL(MatrixUtils.transformRect(toGlobal, g))], 'glyphInBox': glyphInBox,
        'selfOverflow': selfOverflow, 'textAlign': p.textAlign.name, 'paraGlobal': rectL(MatrixUtils.transformRect(toGlobal, Offset.zero & p.size)),
        'lines': lines, 'ranges': ranges, 'contiguous': contiguous, 'breaks': breaks, 'allBreaksAllowed': breaks.every((x) => x['allowed'] == true),
        'scale10': p.textScaler.scale(10), 'locale': p.locale?.toLanguageTag(), 'direction': p.textDirection.name, 'family': st?.fontFamily,
        'fontSize': st?.fontSize, 'weight': st?.fontWeight?.value, 'color': st?.color == null ? null : _argb(st!.color!),
        'size': [p.size.width, p.size.height], 'textSize': [ts.width, ts.height], 'maxLines': p.maxLines, 'overflow': p.overflow.name,
        'didExceedMaxLines': p.didExceedMaxLines, 'intrinsicH': p.getMinIntrinsicHeight(p.size.width),
        'semanticsLabel': textW == null ? null : (textW.widget as Text).semanticsLabel, 'reconstructOk': ok};
      _out('D308-LINES ${jsonEncode(rec)}');
      need(ok, '$what TextPainter 재구성 불일치(계측 실패)');
      need(contiguous, '$what 줄 범위가 연속이 아님 $ranges');
      need(!selfOverflow && glyphInBox, '$what 단락 자체 잘림/글자 줄 상자 밖 ${rec['selfOverflow']}/${rec['glyphInBox']}');
      return rec;
    }

    void textChecks(Map<String, Object?> r, String what) {
      final original = r['original'];
      // 두 phase 공통: 전문·말줄임 0·원문 접근성 이름(표시 문자열이 아니라 원문)
      need(r['plain'] == original, '$what 전문 ${r['plain']}');
      need(r['maxLines'] == null && r['didExceedMaxLines'] == false && r['overflow'] != 'ellipsis', '$what 말줄임/잘림');
      if (r['semanticsLabel'] != null) need(r['semanticsLabel'] == original, '$what 의미 이름 ${r['semanticsLabel']}');
      final sz = r['size'] as List;
      check(near(sz[1] as double, r['intrinsicH'] as double, 0.5), '$what 자연 높이', [sz[1], r['intrinsicH']]);
      // after: 낱말 내부 분할 0 / 부제는 구분점이 다음 줄 첫머리에 오지 않는다
      check(r['allBreaksAllowed'] == true, '$what 줄 경계', r['breaks']);
    }

    Map<String, Object?> semNodeOf(Finder f) {
      final n = f.evaluate().length;
      try {
        final node = t.semantics.find(f);
        return {'anchorCount': n, 'found': true, 'nodeId': node.id, 'label': node.label, 'mergedIntoParent': node.isMergedIntoParent};
      } on StateError catch (e) {
        return {'anchorCount': n, 'found': false, 'error': e.message};
      }
    }

    // 버튼 시각 상자(안쪽 Material)와 실제 receiver(버튼 바깥 상자) 분리
    Map<String, Object?> btnRec(Finder btn, Rect screen) {
      need(btn.evaluate().length == 1, '버튼 수 ${btn.evaluate().length}');
      final recv = t.getRect(btn);
      final mats = find.descendant(of: btn, matching: find.byType(Material)).evaluate().toList();
      need(mats.length == 1, '버튼 Material 수 ${mats.length}');
      final vis = rectOf(mats.single);
      return {'receiver': rectL(recv), 'rw': recv.width, 'rh': recv.height, 'visual': rectL(vis), 'vw': vis.width, 'vh': vis.height,
        'hit': btn.hitTestable().evaluate().length == 1, 'visualInReceiver': inside(vis, recv), 'clip': clipInfo(btn, screen)};
    }

    final capKey = GlobalKey();
    Future<void> png(String step, Map<String, Object?> sidecar) async {
      nPng++;
      budget();
      need(outDir.isNotEmpty, 'DU308_OUT 없음');
      final dir = Directory('$outDir/$phase')..createSync(recursive: true);
      final base = '${dir.path}/D308-$phase-$cond-$step';
      final out = File('$base.png');
      final rj = File('$base.run.txt');
      need(!out.existsSync() && !rj.existsSync(), '이미 있는 캡처를 덮지 않는다 $base');
      final boundary = capKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1.0);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        out.writeAsBytesSync(bytes!.buffer.asUint8List());
      });
      rj.writeAsStringSync(sidecar.entries.map((e) => '${e.key}=${e.value}').join('\n'));
    }

    final business = BusinessModel(
      id: _biz, name: 'DU308 물류센터', businessNumber: '000-00-00000', category: '물류', subCategory: '포장',
      address: '경기도 평택시 서정동 1', ownerId: 'owner308', createdAt: DateTime(2026, 1, 1),
    );
    UserModel user(String uid, String name, UserRole role) =>
        UserModel(uid: uid, username: name, name: name, email: '$uid@example.invalid', role: role, createdAt: DateTime(2026, 1, 1));
    Map<String, dynamic> appMap(String id, String uid, String wd, String type, String start, String end) => {
          'id': id, 'uid': uid, 'toId': 'to308', 'slotId': 'slot308', 'businessId': _biz, 'wdId': wd, 'workDetailId': wd,
          'status': 'CONFIRMED', 'type': 'short_term', 'selectedWorkType': type, 'startTime': start, 'endTime': end,
          'workDate': _ts(dayKey), 'createdAt': _ts(dayKey), 'appliedAt': _ts(dayKey),
        };
    Map<String, dynamic> attMap(String id, String appId, String uid, String checkIn) => {
          'id': id, 'applicationId': appId, 'uid': uid, 'businessId': _biz, 'status': 'present', 'checkIn': checkIn,
          'workDate': _ts(dayKey), 'createdAt': _ts(dayKey),
        };
    final up = UserProvider()..debugSetCurrentUser(user('owner308', 'DU308 사장', UserRole.BUSINESS_ADMIN));
    final (ds, de) = FormatHelper.kstDayRange(dayKey);
    // DU303 fixture 복사(업무·예정 시각·순서·읽기 사전표 유지). 색 기대: 후보 :4762–4766(actionColor/actionIconColor).
    final modes = {
      'IN': (
        icon: Icons.login, step: '출근', title: '파트별 일괄 출근', subtitle: '2건 선택 · 2개 파트', cta: '출근 처리 (2명)',
        apps: [appMap('in-a', 'u-in-a', 'wd-pick', '피킹', '22:00', '23:00'), appMap('in-b', 'u-in-b', 'wd-pack', '포장', '22:30', '23:30')],
        atts: <Map<String, dynamic>>[], ids: ['in-a', 'in-b'], uids: ['u-in-a', 'u-in-b'], pick: '22:00',
        tile: AppColors.success, iconFg: AppColors.successDark,
      ),
      'OUT': (
        icon: Icons.logout, step: '퇴근', title: '파트별 일괄 퇴근', subtitle: '2건 선택 · 2개 파트', cta: '퇴근 처리 (2명)',
        apps: [appMap('out-a', 'u-out-a', 'wd-pick', '피킹', '06:00', '23:00'), appMap('out-b', 'u-out-b', 'wd-pack', '포장', '07:00', '23:30')],
        atts: [attMap('att-out-a', 'out-a', 'u-out-a', '06:00'), attMap('att-out-b', 'out-b', 'u-out-b', '07:00')],
        ids: ['out-a', 'out-b'], uids: ['u-out-a', 'u-out-b'], pick: '23:00', tile: AppColors.purple, iconFg: AppColors.purple,
      ),
    };
    const conds = [
      (id: 'W360_IN', w: 360.0, h: 780.0, s: 1.0, mode: 'IN'),
      (id: 'W360_OUT', w: 360.0, h: 780.0, s: 1.0, mode: 'OUT'),
      (id: 'B320_IN', w: 320.0, h: 640.0, s: 2.0, mode: 'IN'),
      (id: 'B320_OUT', w: 320.0, h: 640.0, s: 2.0, mode: 'OUT'),
    ];
    const allSetLabel = '현재 시간으로 전체 설정';

    try {
      clockGuard('start');
      need((env['DU1_VQ_PHASE'] ?? '').isEmpty, 'DU1_VQ_PHASE 가 설정됨(요청 §3: unset)');
      _out('D308-ENV ${jsonEncode({'phase': phase, 'pinDay': dayArg, 'realNow': DateTime.now().toIso8601String(), 'kst': kstNow().toIso8601String(),
        'window': '$_kDay KST 08:00–21:30', 'fixtureDay': _kDay, 'C': '$_kC', 'out': outDir, 'vqPhase': env['DU1_VQ_PHASE'] ?? '(unset)'})}');

      for (final c in conds) {
        cond = c.id;
        stage = 'mount';
        clockGuard('mount ${c.id}');
        final isB = c.s == 2.0;
        final md = modes[c.mode]!;
        final row = <String, Object?>{'phase': phase, 'cond': c.id};
        var parentPopped = false;
        Object? parentResult = 'unset';
        t.view.physicalSize = Size(c.w, c.h);
        t.view.devicePixelRatio = 1.0;
        t.platformDispatcher.textScaleFactorTestValue = c.s;
        final screen = Rect.fromLTWH(0, 0, c.w, c.h);

        // 도달(요청 §2:17): 대상의 가장 가까운 Scrollable 안에서 실제 drag. W 는 한도 0, B 는 대상마다 한도. 이미 full/hit 이면 0.
        //   area 가 있으면 그 합집합(예: 파트 시각 상자 ∪ 시각 글자 ∪ 변경 — DU303 reachRow 와 같은 대상)이 창 안이어야 한다.
        Future<int> reach(Finder target, String what, {required int maxDrag, Rect Function()? area}) async {
          var used = 0;
          for (var i = 0; i <= maxDrag; i++) {
            need(target.evaluate().length == 1, '$what 대상 수 ${target.evaluate().length}');
            final el = target.evaluate().single;
            final se = nearest(el, (w) => w is Scrollable);
            need(se != null, '$what 스크롤 조상 없음');
            final ss = (se! as StatefulElement).state as ScrollableState;
            final horiz = ss.position.axis == Axis.horizontal;
            final vp = rectOf(se).intersect(screen);
            final r = area == null ? rectOf(el) : area();
            need((horiz ? r.width : r.height) <= (horiz ? vp.width : vp.height) + 0.5, '$what 대상 ${rectL(r)} 이 창 ${rectL(vp)} 보다 크다');
            final clip = clipInfo(target, screen);
            if (inside(r, vp) && clip['full'] == true && target.hitTestable().evaluate().length == 1) return used;
            if (i == maxDrag) break;
            final forward = horiz ? r.right > vp.right : r.bottom > vp.bottom;
            final d = horiz ? (forward ? r.right - vp.right : vp.left - r.left) : (forward ? r.bottom - vp.bottom : vp.top - r.top);
            final slack = ((horiz ? vp.width - r.width : vp.height - r.height) / 2).clamp(0.0, 16.0).toDouble();
            final dist = d + kDragSlopDefault + slack;
            final delta = horiz ? Offset(forward ? -dist : dist, 0) : Offset(0, forward ? -dist : dist);
            final p0 = ss.position.pixels;
            nDrag++;
            used++;
            budget();
            await t.drag(fe(se), delta);
            guard('drag:$what');
            await frames(3, 'drag:$what');
            _out('D308-REACH ${jsonEncode({'phase': phase, 'cond': cond, 'what': what, 'try': i, 'axis': horiz ? 'h' : 'v', 'target': rectL(r),
              'viewport': rectL(vp), 'd': d, 'slack': slack, 'delta': [delta.dx, delta.dy], 'before': p0, 'after': ss.position.pixels,
              'extent': [ss.position.minScrollExtent, ss.position.maxScrollExtent]})}');
          }
          stop('$what 비도달(drag $used/$maxDrag)');
        }

        // ── 조건별 Reads 대역·사전표(DU303 와 같은 9함수 10호출) ──
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
        nMount++;
        budget();
        await t.pumpWidget(RepaintBoundary(
          key: capKey,
          child: ChangeNotifierProvider<UserProvider>.value(
            value: up,
            child: MaterialApp(
              key: ValueKey('D308-$phase-${c.id}'),
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
        live = true;
        guard('mount');
        final tabNormal = richExact('정상', within: find.byType(TabBar));
        // `전체`(소스 :1536 한 곳)는 체크 상자를 가진 GestureDetector 안의 것 정확 1개만 쓴다(통계·칩의 비슷한 글자 배제)
        Finder allSelect() {
          final els = richExact('전체').evaluate().where((e) {
            final g = nearest(e, (w) => w is GestureDetector);
            return g != null && find.descendant(of: fe(g), matching: find.byType(AppCheckbox)).evaluate().length == 1;
          }).toList();
          need(els.length == 1, '전체 선택 수 ${els.length}');
          return fe(els.single);
        }
        // 16 회 안에서 읽기 10호출·정상 탭·전체가 생기면 멈춘다(+1 frame). host 의 350ms 지연 포커스 스크롤(:731–739)은
        //   focused application 이 있을 때의 조건부 경로다 — 이 fixture 에서 일어나는지는 정적으로 단정하지 않는다(원점 offset 기록으로 본다).
        for (var i = 0; i < 16; i++) {
          final n = readCalls.values.fold<int>(0, (a, b) => a + b.length);
          if (n >= 10 && tabNormal.evaluate().length == 1 && richExact('전체').evaluate().isNotEmpty) break;
          await frames(1, 'load');
        }
        await frames(1, 'load');
        frozen = true;
        final match = canon(readCalls) == canon(expectedReads);
        _out('D308-READS ${jsonEncode({'phase': phase, 'cond': c.id, 'actual': readCalls, 'expected': expectedReads, 'match': match})}');
        need(match, 'Reads 사전표 불일치');
        {
          // load 원점 기록: 상단(탭·통계·일괄 행동) 스크롤 offset 과 범위 — 조건부 포커스 스크롤 발생 여부를 관측으로 남긴다(판정 0)
          final topScroll = nearest(allSelect().evaluate().single, (w) => w is Scrollable);
          final tp0 = topScroll == null ? null : ((topScroll as StatefulElement).state as ScrollableState).position;
          _out('D308-LOAD ${jsonEncode({'phase': phase, 'cond': c.id, 'pump': nPump, 'topScroll': tp0 == null ? null : {'pixels': tp0.pixels,
            'min': tp0.minScrollExtent, 'max': tp0.maxScrollExtent, 'vp': tp0.viewportDimension, 'axis': tp0.axis.name}})}');
        }

        // ── 진입: 정상 탭(B 가로 ≤2) → 전체(B 세로 ≤2) → (DU305 맞춤 ≥250ms) → 단계 버튼(별도 drag 0) ──
        stage = 'tab';
        need(tabNormal.evaluate().length == 1, '정상 탭 수 ${tabNormal.evaluate().length}');
        final tabDrag = await reach(tabNormal, '정상 탭', maxDrag: isB ? 2 : 0);
        await tapAt(tabNormal, '정상 탭');
        await frames(8, 'tab');
        stage = 'select';
        final allDrag = await reach(allSelect(), '전체', maxDrag: isB ? 2 : 0);
        await tapAt(allSelect(), '전체');
        await frames(8, 'select'); // 400ms ≥ DU305 맞춤 animateTo 250ms(:3762)
        stage = 'step';
        // 단계 버튼 = 아이콘·단계 이름·`2건`을 모두 가진 InkWell 정확 1개(선택 2 유지의 표시이기도 하다). 맞춤 뒤 매번 다시 찾는다.
        Finder stepBtn() {
          final els = find.byType(InkWell).evaluate().where((e) =>
              find.descendant(of: fe(e), matching: find.byIcon(md.icon)).evaluate().length == 1 &&
              richExact(md.step, within: fe(e)).evaluate().length == 1 &&
              richExact('2건', within: fe(e)).evaluate().length == 1).toList();
          need(els.length == 1, '${md.step} 단계 버튼(2건) 수 ${els.length}');
          return fe(els.single);
        }

        need(t.widget<InkWell>(stepBtn()).onTap != null, '${md.step} 단계 버튼 비활성');
        final stepClip = clipInfo(stepBtn(), screen);
        need(stepClip['full'] == true, '${md.step} 단계 버튼 가시 아님(단계 탐색 drag 0) ${stepClip['visible']}');
        row['entry'] = {'tabDrag': tabDrag, 'allDrag': allDrag, 'stepRect': stepClip['rect']};
        stage = 'parentOpen';
        nRoute++;
        budget();
        await tapAt(stepBtn(), '${md.step} 단계 버튼');
        final titleF = richExact(md.title);
        for (var i = 0; i < 3 && titleF.evaluate().isEmpty; i++) {
          nPump++;
          budget();
          await t.pump();
          guard('open#$i');
        }
        need(titleF.evaluate().length == 1, '부모 제목 ${titleF.evaluate().length}');
        final dialogEl0 = nearest(titleF.evaluate().single, (w) => w is Dialog);
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

        // ── 부모 열림: 고정 대상(제목·부제·닫기·전체설정·취소·CTA)을 먼저 검사·캡처한다(B 첫 파트 도달은 그 뒤) ──
        // Dialog 의 Material 은 Dialog 안 다른 모든 Material(버튼 안쪽)의 조상이라 전위 순회 첫 번째다(DU303 :676 과 같은 선택).
        final cardF = find.descendant(of: dialogF, matching: find.byType(Material)).first;
        final scrollF = find.descendant(of: dialogF, matching: find.byType(SingleChildScrollView));
        need(scrollF.evaluate().length == 1, '부모 본문 스크롤 수 ${scrollF.evaluate().length}');
        final closeF = find.descendant(of: dialogF, matching: find.widgetWithIcon(IconButton, Icons.close));
        final cancelF = find.descendant(of: dialogF, matching: find.widgetWithText(OutlinedButton, '취소'));
        final ctaF = find.descendant(of: dialogF, matching: find.byWidgetPredicate((w) => w is ElevatedButton));
        final titleRichF = richExact(md.title, within: dialogF);
        final subRichF = richExact(md.subtitle, within: dialogF);
        final allSetRichF = richExact(allSetLabel, within: dialogF);
        final ctaRichF = richExact(md.cta, within: ctaF);
        for (final (f, w) in [(closeF, '닫기'), (cancelF, '취소'), (ctaF, 'CTA'), (titleRichF, '제목'), (subRichF, '부제'), (allSetRichF, '전체설정'),
          (ctaRichF, 'CTA 글자')]) {
          need(f.evaluate().length == 1, '부모 $w 수 ${f.evaluate().length}');
        }
        final allSetBtn = fe(nearest(allSetRichF.evaluate().single, (w) => w is OutlinedButton)!);
        final titleEl = titleRichF.evaluate().single;
        // 실제 환경값(제목 단락 context) — 상수 출력이 아니다
        {
          final hp = titleEl.renderObject! as RenderParagraph;
          final th = Theme.of(titleEl);
          final mq = MediaQuery.of(titleEl);
          _out('D308-RUNTIME ${jsonEncode({'phase': phase, 'cond': c.id, 'textScaler10': hp.textScaler.scale(10), 'locale': hp.locale?.toLanguageTag(),
            'appLocale': Localizations.localeOf(titleEl).toLanguageTag(), 'direction': hp.textDirection.name, 'fontFamily': hp.text.style?.fontFamily,
            'fontWeight': hp.text.style?.fontWeight?.value, 'boldText': mq.boldText, 'mqTextScaler10': mq.textScaler.scale(10), 'dpr': mq.devicePixelRatio,
            'platform': th.platform.name, 'visualDensity': [th.visualDensity.horizontal, th.visualDensity.vertical],
            'materialTapTargetSize': th.materialTapTargetSize.name, 'useMaterial3': th.useMaterial3})}');
          need(near(hp.textScaler.scale(10) / 10, c.s, 1e-6), '실제 배율 ${c.s} 아님');
        }
        // 표면·머리·타일·구분선(색은 after 단언, before 기록)
        final cardMat = t.widget<Material>(cardF).color;
        final headRow = nearest(titleEl, (w) => w is Row);
        need(headRow != null, '머리 Row 없음');
        final headBox = nearest(headRow!, (w) => w is Container);
        need(headBox != null, '머리 Container 없음');
        final headDeco = (headBox!.widget as Container).decoration;
        final iconF = find.descendant(of: dialogF, matching: find.byWidgetPredicate((w) => w is Icon && w.icon == md.icon));
        need(iconF.evaluate().length == 1, '머리 아이콘 수 ${iconF.evaluate().length}');
        final tileEl = nearest(iconF.evaluate().single, (w) => w is Container && w.decoration is BoxDecoration);
        need(tileEl != null, '아이콘 타일 없음');
        final tileColor = ((tileEl!.widget as Container).decoration! as BoxDecoration).color;
        final iconColor = t.widget<Icon>(iconF).color;
        // 타일 아래 실제 바탕 = Dialog Material → (있으면) 머리 Container 면 → 타일. before 의 머리 α.10 면을 빼지 않는다(고정 합성식 0).
        final base0 = cardMat ?? Colors.white;
        final headColor = headDeco is BoxDecoration ? headDeco.color : null;
        final underTile = headColor == null ? base0 : Color.alphaBlend(headColor, base0);
        final tileOnCard = tileColor == null ? underTile : Color.alphaBlend(tileColor, underTile);
        final dividers = find.descendant(of: dialogF, matching: find.byType(Divider)).evaluate().length;
        final dialogFlexOver = find.descendant(of: dialogF, matching: find.byWidgetPredicate((w) => w is Flex)).evaluate()
            .map((e) => flexInfo(e.renderObject! as RenderFlex)['over'] as double).fold<double>(0, math.max);
        final surface = {'cardMaterial': cardMat == null ? null : _argb(cardMat), 'headDecoration': headDeco?.toString(),
          'headColor': headColor == null ? null : _argb(headColor), 'tileBackdrop': _argb(tileOnCard),
          'tile': tileColor == null ? null : _argb(tileColor), 'iconFg': iconColor == null ? null : _argb(iconColor),
          'iconContrast': iconColor == null ? null : _contrast(iconColor, tileOnCard), 'dividers': dividers, 'maxFlexOver': dialogFlexOver};
        _out('D308-SURFACE ${jsonEncode({'phase': phase, 'cond': c.id, ...surface})}');
        need(dialogFlexOver <= _kEps, '부모 Flex 넘침 $dialogFlexOver');
        check(cardMat == AppColors.surface, '부모 Dialog Material = surface', surface['cardMaterial']);
        check(headDeco == null, '머리 Container decoration null', surface['headDecoration']);
        check(tileColor == md.tile.withValues(alpha: 0.15) && iconColor == md.iconFg && (surface['iconContrast'] as double? ?? 0) >= 3.0,
            '아이콘 타일 α.15·전경·대비≥3', surface);
        check(dividers == 0, '부모 구분선 0', dividers);

        // 네 글자(제목·부제·전체설정·CTA): 실제 줄 경계·전문·원문 의미 이름
        final lr = <String, Map<String, Object?>>{
          'title': lineRec(titleEl, '제목', md.title, phrases: false),
          'subtitle': lineRec(subRichF.evaluate().single, '부제', md.subtitle, phrases: true),
          'allSet': lineRec(allSetRichF.evaluate().single, '전체설정', allSetLabel, phrases: false),
          'cta': lineRec(ctaRichF.evaluate().single, 'CTA', md.cta, phrases: false),
        };
        for (final e in lr.entries) {
          textChecks(e.value, e.key);
        }
        // 의미 이름: 제목·부제는 각 RichText 를 담은 실제 SemanticsNode(소유 또는 병합 조상)의 label 을 개행으로 나눈 줄 하나와 정확히 같다
        //   (DU303 방식 — 병합 여부와 무관, trim·부분 일치 0). CTA·전체설정은 버튼 노드 label 이 원문과 정확히 같다.
        List<String> linesOf(Map<String, Object?> n) => n['label'] is String ? (n['label'] as String).split(nl) : const <String>[];
        final semTitle = semNodeOf(titleRichF);
        final semSub = semNodeOf(subRichF);
        final semCta = semNodeOf(ctaF);
        final semAll = semNodeOf(allSetBtn);
        _out('D308-SEM ${jsonEncode({'phase': phase, 'cond': c.id, 'title': semTitle, 'subtitle': semSub, 'cta': semCta, 'allSet': semAll})}');
        need(linesOf(semTitle).contains(md.title) && linesOf(semSub).contains(md.subtitle),
            '제목/부제 의미 줄(정확) ${linesOf(semTitle)}/${linesOf(semSub)}');
        need(semCta['label'] == md.cta && semAll['label'] == allSetLabel, 'CTA/전체설정 의미 이름 ${semCta['label']}/${semAll['label']}');

        // 고정 행동: 닫기 48×48, 취소/CTA 시각 높이 ≥52·receiver ≥48×48(분리), 가시/hit, 버튼 안 글자
        final closeR = t.getRect(closeF);
        final closeClip = clipInfo(closeF, screen);
        final cancelB = btnRec(cancelF, screen);
        final ctaB = btnRec(ctaF, screen);
        final ctaMat = t.widget<Material>(find.descendant(of: ctaF, matching: find.byType(Material)));
        final ctaFg = (ctaRichF.evaluate().single.renderObject! as RenderParagraph).text.style?.color;
        final cancelSide = t.widget<OutlinedButton>(cancelF).style?.side?.resolve(const <WidgetState>{})?.color;
        final fixed = {'close': {'rect': rectL(closeR), 'w': closeR.width, 'h': closeR.height, 'hit': closeF.hitTestable().evaluate().length == 1,
            'clip': closeClip}, 'cancel': cancelB, 'cta': ctaB,
          'ctaFill': ctaMat.color == null ? null : _argb(ctaMat.color!), 'ctaFg': ctaFg == null ? null : _argb(ctaFg),
          'ctaContrast': (ctaMat.color == null || ctaFg == null) ? null : _contrast(ctaFg, ctaMat.color!),
          'cancelSide': cancelSide == null ? null : _argb(cancelSide),
          'titleClip': clipInfo(titleRichF, screen), 'ctaLabelClip': clipInfo(ctaRichF, screen), 'allSet': btnRec(allSetBtn, screen)};
        _out('D308-FIXED ${jsonEncode({'phase': phase, 'cond': c.id, 'pump': nPump, ...fixed})}');
        need(closeR.width >= 48 - _kEps && closeR.height >= 48 - _kEps && closeClip['full'] == true && closeF.hitTestable().evaluate().length == 1,
            '닫기 48×48·가시/hit ${fixed['close']}');
        for (final (b, w) in [(cancelB, '취소'), (ctaB, 'CTA')]) {
          need((b['vh'] as double) >= 52 - _kEps && (b['rw'] as double) >= 48 - _kEps && (b['rh'] as double) >= 48 - _kEps &&
              b['hit'] == true && (b['clip'] as Map)['full'] == true, '$w 시각≥52·receiver≥48·가시/hit $b');
        }
        need((fixed['titleClip'] as Map)['full'] == true && (fixed['ctaLabelClip'] as Map)['full'] == true, '제목/CTA 글자 가시');
        // [r2] 양 phase 필수 기하(요청 §2:22): 전체설정 가시/hit, 부제 clip, 버튼 시각 상자 ⊂ receiver, 버튼 글자 ⊂ 시각 상자, 제목↔닫기 겹침 0
        Rect visOf(Map<String, Object?> b) {
          final v = (b['visual'] as List).cast<double>();
          return Rect.fromLTRB(v[0], v[1], v[2], v[3]);
        }

        final allB = fixed['allSet'] as Map<String, Object?>;
        final subClip = clipInfo(subRichF, screen);
        final allLabelClip = clipInfo(allSetRichF, screen);
        final cancelLabelF = richExact('취소', within: cancelF);
        need(cancelLabelF.evaluate().length == 1, '취소 글자 수 ${cancelLabelF.evaluate().length}');
        final titleR = rectOf(titleEl);
        final geo = <String, Object?>{'subClip': subClip, 'allSetLabelClip': allLabelClip, 'title': rectL(titleR),
          'ctaLabelInVisual': inside(rectOf(ctaRichF.evaluate().single), visOf(ctaB)),
          'cancelLabelInVisual': inside(rectOf(cancelLabelF.evaluate().single), visOf(cancelB)),
          'allSetLabelInVisual': inside(rectOf(allSetRichF.evaluate().single), visOf(allB)),
          'titleCloseOverlap': titleR.overlaps(closeR)};
        _out('D308-GEO ${jsonEncode({'phase': phase, 'cond': c.id, 'pump': nPump, ...geo})}');
        need(allB['hit'] == true && (allB['clip'] as Map)['full'] == true && allLabelClip['full'] == true, '전체설정 가시/hit $allB');
        need(subClip['full'] == true, '부제 가시 ${subClip['visible']}');
        for (final (b, w) in [(cancelB, '취소'), (ctaB, 'CTA'), (allB, '전체설정')]) {
          need(b['visualInReceiver'] == true, '$w 시각 상자 ⊂ receiver 아님 $b');
        }
        need(geo['ctaLabelInVisual'] == true && geo['cancelLabelInVisual'] == true && geo['allSetLabelInVisual'] == true, '버튼 글자 ⊂ 시각 상자 $geo');
        need(geo['titleCloseOverlap'] == false, '제목·닫기 겹침 ${rectL(titleR)} ${rectL(closeR)}');
        // [r2] after CTA 가운데 정렬(Standards :328): textAlign center 이고 각 글자 줄 중심 = 시각 상자 중심(±0.01). before 는 기록.
        final ctaLines = lr['cta']!;
        final ctaVis = visOf(ctaB);
        final centers = [for (final g in (ctaLines['glyphGlobal'] as List)) (((g as List)[0] as double) + (g[2] as double)) / 2];
        check(ctaLines['textAlign'] == 'center' && centers.every((x) => near(x, ctaVis.center.dx, _kTol)), 'CTA 가운데 정렬',
            {'align': ctaLines['textAlign'], 'lineCenters': centers, 'visualCx': ctaVis.center.dx});
        check(fixed['ctaFill'] == _argb(AppColors.brand) && fixed['ctaFg'] == _argb(Colors.white) && (fixed['ctaContrast'] as double? ?? 0) >= 4.5,
            'CTA brand·흰 글자·대비≥4.5', [fixed['ctaFill'], fixed['ctaFg'], fixed['ctaContrast']]);
        check(fixed['cancelSide'] == _argb(AppColors.grey300), '취소 테두리 grey300 보존', fixed['cancelSide']);
        row['open'] = {'surface': surface, 'lines': lr, 'fixed': fixed};

        // 열림 애니메이션 완료 PNG 1(부모 drag 전)
        await png('open', {'phase': phase, 'cond': c.id, 'step': 'parent-open(anim completed, before part reach)',
          'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s, 'locale': 'ko_KR', 'realNow': DateTime.now().toIso8601String(),
          'pinDay': dayArg});

        // ── 첫 파트(피킹) 시각 줄: W drag 0, B 세로 ≤2 → 가시/hit·포함/분리·색·최소 크기 ──
        stage = 'part1';
        // [r2] 파트 카드(반경 14) 중 `변경` 1·파트 이름 1을 가진 것을 모두 모아 정확 1개만 쓴다(첫 일치 반환 0)
        ({Element card, Element box, Element time, Element change})? partEls(String part) {
          final hits = <({Element card, Element box, Element time, Element change})>[];
          for (final ce in find.descendant(of: dialogF, matching: find.byWidgetPredicate((w) => w is OutlinedButton)).evaluate()) {
            if (richExact('변경', within: fe(ce)).evaluate().length != 1) continue;
            final card = nearest(ce, (w) => w is DecoratedBox && w.decoration is BoxDecoration &&
                ((w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(14)));
            if (card == null) continue;
            if (richExact(part, within: fe(card)).evaluate().length != 1) continue;
            final times = find.descendant(of: fe(card), matching: find.byType(RichText)).evaluate().where((e) =>
                RegExp(r'^[0-9]{2}:[0-9]{2}$').hasMatch(plainOf(e))).toList();
            need(times.length == 1, '$part 시각 글자 수 ${times.length}');
            final box = nearest(times.single, (w) => w is DecoratedBox);
            need(box != null, '$part 시각 상자 없음');
            hits.add((card: card, box: box!, time: times.single, change: ce));
          }
          need(hits.length <= 1, '$part 파트 카드 ${hits.length}개(정확 1 아님)');
          return hits.isEmpty ? null : hits.single;
        }

        final pe0 = partEls('피킹');
        need(pe0 != null, '피킹 파트 요소 없음');
        final changeF = fe(pe0!.change);
        Rect partArea() {
          final p = partEls('피킹');
          need(p != null, '피킹 파트 요소 없음(도달 중)');
          return rectOf(p!.box).expandToInclude(rectOf(p.time)).expandToInclude(rectOf(p.change));
        }

        final partDrag = await reach(changeF, '피킹 시각 줄', maxDrag: isB ? 2 : 0, area: partArea);
        final pe = partEls('피킹');
        need(pe != null, '피킹 파트 요소 없음(도달 뒤)');
        final box = rectOf(pe!.box), time = rectOf(pe.time);
        final chB = btnRec(fe(pe.change), screen);
        final boxDeco = (pe.box.widget as DecoratedBox).decoration as BoxDecoration;
        final timeFg = (pe.time.renderObject! as RenderParagraph).text.style?.color;
        final ob = pe.change.widget as OutlinedButton;
        final sideColor = ob.style?.side?.resolve(const <WidgetState>{})?.color;
        final chFg = (richExact('변경', within: fe(pe.change)).evaluate().single.renderObject! as RenderParagraph).text.style?.color;
        final chVis = visOf(chB);
        final part = {'drag': partDrag, 'time': plainOf(pe.time), 'box': rectL(box), 'timeRect': rectL(time), 'change': chB,
          'timeInBox': inside(time, box), 'timeClip': clipInfo(fe(pe.time), screen), 'boxChangeOverlap': box.overlaps(chVis),
          'boxBg': boxDeco.color == null ? null : _argb(boxDeco.color!), 'timeFg': timeFg == null ? null : _argb(timeFg),
          'timeContrast': (boxDeco.color == null || timeFg == null) ? null : _contrast(timeFg, boxDeco.color!),
          'changeSide': sideColor == null ? null : _argb(sideColor), 'changeFg': chFg == null ? null : _argb(chFg)};
        _out('D308-PART ${jsonEncode({'phase': phase, 'cond': c.id, 'pump': nPump, ...part})}');
        need(part['time'] == md.pick, '피킹 시각 ${part['time']} ≠ ${md.pick}');
        need((part['timeClip'] as Map)['full'] == true && chB['hit'] == true && (chB['clip'] as Map)['full'] == true, '피킹 시각/변경 가시/hit');
        need((chB['vw'] as double) >= 64 - _kEps && (chB['vh'] as double) >= 48 - _kEps && (chB['rw'] as double) >= 48 - _kEps &&
            (chB['rh'] as double) >= 48 - _kEps, '변경 시각 ≥64×48·receiver ≥48×48 $chB');
        need(part['timeInBox'] == true, '시각 글자 상자 안');
        need(part['boxChangeOverlap'] == false && chB['visualInReceiver'] == true, '시각 상자↔변경 겹침 0·변경 시각 ⊂ receiver $part');
        check(part['boxBg'] == _argb(AppColors.grey100) && part['timeFg'] == _argb(AppColors.textPrimary) &&
            (part['timeContrast'] as double? ?? 0) >= 4.5, '시각 상자 grey100·textPrimary 보존', part);
        check(part['changeSide'] == _argb(AppColors.brand) && part['changeFg'] == _argb(AppColors.brand), '변경 brand 보존', part);
        row['part1'] = part;

        // ── 부모 닫기: W 취소 / B X → null 반환·처리 경로 0 → 선택 2 유지 ──
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
        need(parentPopped && parentResult == null, '부모 반환 $parentPopped/$parentResult(null 이어야 처리 경로 0)');
        need(stepBtn().evaluate().length == 1, '선택 2 유지 아님');
        row['popped'] = {'popped': parentPopped, 'result': parentResult};
        row['counts'] = counts();
        _out('D308 ${jsonEncode(row)}');

        // ── 정상 빈 teardown(닫기·null 반환 성공으로 세지 않는다) ──
        stage = 'teardown';
        nEmpty++;
        budget();
        await t.pumpWidget(const SizedBox.shrink());
        live = false;
        guard('teardown');
        await frames(2, 'teardown');
        visited.add(c.id);
      }
      need(visited.join('|') == 'W360_IN|W360_OUT|B320_IN|B320_OUT', '방문 $visited');
      need(nMount == 4 && nEmpty == 4 && nRoute == 4 && nTap == 16 && nPng == 4 && nText == 0 && nDrag <= _kC.drag, '실행량 ${counts()}');
      clockGuard('end');
      need(net.created == 0 && biz.isEmpty && errors.isEmpty && afterFreeze.isEmpty && !live,
          '최종 상태 http=${net.created} business=$biz pending=${errors.length} reads=$afterFreeze live=$live');
      _out('D308-END ${jsonEncode({...counts(), 'visited': visited, 'http': net.created, 'business': biz, 'readsAfterFreeze': afterFreeze})}');
      completed = true;
    } finally {
      // 실패 정리 F=(pump 2, 빈 mount ≤1) — 원 실패를 덮지 않고 FINAL 을 guard 복원 전에 남긴다
      var cleanup = 'not-needed';
      var cleanPump = 0, cleanEmpty = 0;
      final cleanErrors = <String>[for (final e in errors) 'pending-before-cleanup ${e.cond}/${e.stage}#${e.pump}: ${e.first}'];
      errors.clear();
      if (live) {
        try {
          cleanEmpty++;
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
      _out('D308-FINAL ${jsonEncode({...counts(), 'outcome': completed ? 'completed' : 'failed', 'cleanup': cleanup, 'cleanupEmptyMount': cleanEmpty,
        'cleanupPump': cleanPump, 'stillMounted': live, 'visited': visited, 'http': net.created, 'business': biz, 'readsAfterFreeze': afterFreeze,
        'cleanupErrors': cleanErrors})}');
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
