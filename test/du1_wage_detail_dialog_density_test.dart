// [DU1-B2 · followup_5 §3] 관리자 급여 명세(wage_detail_dialog) 공제 행·실수령 — 320@1.3 / 392@2.0 LOCAL 렌더.
//   저장 base(TaxDeductionService.applyDeduction 결과)를 그대로 넘기고 화면은 effectiveNetWage 만 보인다 — 금액·공제 유형·F1 동작 변경 없음.
// ignore_for_file: depend_on_referenced_packages
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/insurance_rate_model.dart';
import 'package:ALfit/models/core/wage_detail_model.dart';
import 'package:ALfit/services/tax_deduction_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/wage_calculator.dart';
import 'package:ALfit/widgets/dialogs/wage/wage_detail_dialog.dart';

import 'package:flutter/rendering.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

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

final kDate = DateTime(2026, 11, 3);

ApplicationModel _app() => ApplicationModel(
      id: 'wa1', uid: 'wu1', toId: 'to1', slotId: 'slot1', businessId: 'biz1', businessName: '강남 물류센터',
      toTitle: '단기 모집', selectedWorkType: '상하차', wdId: 'wd1', startTime: '09:00', endTime: '18:00',
      wage: 25000, wageType: 'hourly', status: 'CONFIRMED', workDate: kDate, appliedAt: DateTime(2026, 11, 1));

AttendanceModel _att() => AttendanceModel(
      id: 'att_wa1', applicationId: 'wa1', userId: 'wu1', businessId: 'biz1', businessName: '강남 물류센터',
      workDate: kDate, workType: '상하차', status: AttendanceModel.statusPresent,
      wageStatus: AttendanceModel.wageCalculated, adminConfirmed: true,
      checkInAt: DateTime(2026, 11, 3, 9), checkOutAt: DateTime(2026, 11, 3, 18), createdAt: kDate);

WageDetailModel _stored(String type) => TaxDeductionService.applyDeduction(
    base: WageCalculator.calculate(
        wageType: 'hourly', baseWage: 25000, workDate: kDate, scheduledStart: '09:00', scheduledEnd: '18:00',
        actualStart: '09:00', actualEnd: '18:00', breakMinutes: 60),
    taxDeductionType: type,
    workYear: 2026);

/// 넘침은 따로 모아 기록한다(이 시험의 판정 대상 아님 — 기존 공제 행 등, 보고서 OPEN 항목). 다른 오류는 그대로 실패시킨다.
final overflowLog = <String>[];

Future<void> _pump(WidgetTester tester, String type,
    {double textScale = 1.0, Size size = const Size(392, 844), WageDialogMode mode = WageDialogMode.calculated}) async {
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final msg = d.exceptionAsString();
    if (msg.contains('overflowed')) {
      final loc = RegExp(r'[a-z_]+.dart:d+').firstMatch((d.informationCollector?.call() ?? const <DiagnosticsNode>[]).map((e) => e.toString()).join(' '))?.group(0);
      overflowLog.add('$type ${size.width.toInt()}@$textScale $msg $loc');
    } else {
      prev?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = prev);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    // 앱 UI 는 fontFamily 미지정(기기 기본 한글 폰트) — 측정은 번들 NotoSansKR 로 근사한다.
    theme: RoleTheme.businessAdminTheme.copyWith(
        textTheme: RoleTheme.businessAdminTheme.textTheme.apply(fontFamily: 'NotoSansKR')),
    builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(textScale)), child: child!),
    home: Scaffold(
      body: WageDetailDialog(
          app: _app(), user: null, attendance: _att(), wage: _stored(type), mode: mode),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
}


Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    final f = File('assets/fonts/NotoSansKR-Regular.ttf');
    if (f.existsSync()) {
      final loader = FontLoader('NotoSansKR')..addFont(f.readAsBytes().then((b) => ByteData.view(b.buffer)));
      await loader.load();
    }
  });

  for (final type in const [InsuranceRateModel.typeFreelancer33, InsuranceRateModel.typeDailyAuto8]) {
    for (final c in const [(Size(320, 640), 1.3), (Size(392, 844), 2.0)]) {
      testWidgets('[DU1-B2] 관리자 명세 공제 펼침·실수령 $type ${c.$1.width.toInt()}@${c.$2} — 넘침 0·금액 화면 안', (t) async {
        overflowLog.clear();
        await _pump(t, type, size: c.$1, textScale: c.$2);
        final header = findVisibleTextContaining('공제 (');
        await t.ensureVisible(header.first);
        await _settle(t);
        await t.tap(header.first);
        await _settle(t);
        final w = _stored(type);
        final net = find.text(FormatHelper.formatWage(w.effectiveNetWage));
        await t.ensureVisible(net);
        await _settle(t);
        expect(findVisibleText('실수령액'), findsOneWidget);
        final r = t.getRect(net);
        expect(r.right, lessThanOrEqualTo(c.$1.width), reason: '금액이 화면 밖으로 나가지 않는다');
        expect(r.left, greaterThanOrEqualTo(0));
        expect(overflowLog, isEmpty, reason: overflowLog.join(' | '));
        expect(t.takeException(), isNull);
      });
    }
  }

  // ── [DU1 후속41 §3] B2-W — DU-O026 관리자 급여 명세(WageDetailDialog.show) 시각·도달 셀.
  //   자료: 기존 _app/_att/_stored(freelancer_3_3) · 2026-11-03 · 시급 25,000 · 09–18 · 휴게 60 · calculated · mode calculated.
  //   host: 실제 WageDetailDialog.show(showDialog barrierDismissible:false) · theme RoleTheme.businessAdminTheme(기존 시험의 fontFamily apply 없음)
  //   글꼴 vqLoadFonts(NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons; FlutterTest 미등록) · boundary = MaterialApp 바깥(root overlay 포함).
  //   writer: '저장'(update)·확정·되돌리기·명세서/PDF/공유는 누르지 않는다 — rect·hit·활성만. UI '취소' 로 result==null·닫힘 확인(급여 취소 action 아님).
  //   prefs·clock: 이 셀 경로에서 미사용·미주입(날짜는 fixture workDate). writer spy 없음 → 미진입은 정적 확인.
  for (final c in const [(id: 'B2-W-A', w: 392.0, h: 844.0, s: 1.0), (id: 'B2-W-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 급여 명세 show ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 첫 화면→공제 펼침→실수령→편집부·footer 도달 · UI 취소 result null', (t) async {
      await t.runAsync(vqLoadFonts);
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          // [r3] 넘침 위치 — 오류를 낸 위젯의 생성 위치(file:line)
          final info = (d.informationCollector?.call() ?? const <DiagnosticsNode>[]).map((e) => e.toString()).join(' ');
          final loc = RegExp(r'wage_detail_dialog\.dart:\d+').allMatches(info).map((x) => x.group(0)).toSet().join(',');
          overflows.add('${m.split('\n').first} @ $loc');
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);
      final size = Size(c.w, c.h);
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      final w = _stored(InsuranceRateModel.typeFreelancer33);
      WageDialogResult? result;
      var closed = false;
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.businessAdminTheme,
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
          home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
              onPressed: () async {
                result = await WageDetailDialog.show(context: ctx, app: _app(), user: null, attendance: _att(), wage: w, mode: WageDialogMode.calculated);
                closed = true;
              },
              child: const Text('open'))))),
        ),
      ));
      await t.pump();
      await t.tap(find.text('open'));
      await _settle(t);
      final log = <String>[];
      final dlg = find.byType(WageDetailDialog);
      final mqv = MediaQuery.of(t.element(dlg));
      log.add('${c.id} screenMQ padding=${mqv.padding} viewPadding=${mqv.viewPadding} viewInsets=${mqv.viewInsets} · view physical padding=${t.view.padding.top},${t.view.padding.bottom} viewInsets=${t.view.viewInsets.bottom}');
      log.add('data net=${FormatHelper.formatWage(w.effectiveNetWage)} type=${InsuranceRateModel.typeFreelancer33}');
      Map<String, Object?> cond(String state) => {
            'screen': 'WageDetailDialog.show(mode calculated) + root overlay', 'theme': 'RoleTheme.businessAdminTheme',
            'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
            'mq': 'padding=${mqv.padding} viewPadding=${mqv.viewPadding} viewInsets=${mqv.viewInsets}',
            'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록 — 기기 글꼴 아님',
            'data': '_app/_att/_stored(freelancer_3_3) 2026-11-03 시급25,000 09:00–18:00 휴게60 calculated · user null',
            'prefs': '미사용', 'clock': '미주입(fixture workDate)', 'state': state};
      final body = find.descendant(of: dlg, matching: find.byType(Scrollable)).first;
      Rect vp() => t.getRect(body);
      bool hits(Finder f, Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        return hit.path.any((e) => e.target == t.renderObject(f));
      }
      String rr(Finder f) {
        final r = t.getRect(f);
        return '$r(${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}) hit=${hits(f, r.center)} inScreen=${r.top >= 0 && r.bottom <= c.h && r.left >= 0 && r.right <= c.w}';
      }
      // ① 첫 화면 + 고정 영역 target
      final save = find.ancestor(of: findVisibleText('저장'), matching: find.byWidgetPredicate((x) => x is ElevatedButton)).first;
      final cancel = find.ancestor(of: findVisibleText('취소'), matching: find.byWidgetPredicate((x) => x is OutlinedButton)).first;
      final close = find.ancestor(of: find.byIcon(Icons.close), matching: find.byType(IconButton)).first;
      log.add('top bodyViewport=${vp()} save=${rr(save)} cancel=${rr(cancel)} close=${rr(close)} saveEnabled=${t.widget<ElevatedButton>(save).onPressed != null}');
      log.add('footer vs body overlap=${t.getRect(save).top < vp().bottom - 0.5}');
      await vqCapture(t, key, '${c.id}_1_top', conditions: cond('첫 화면'));
      // ② 공제 펼침
      final header = findVisibleTextContaining('공제 (');
      await t.ensureVisible(header.first);
      await _settle(t);
      await t.tap(header.first);
      await _settle(t);
      log.add('deduction header=${t.getRect(header.first)} bodyViewport=${vp()}');
      await vqCapture(t, key, '${c.id}_2_deduction_open', conditions: cond('공제 펼침'));
      // ③ 실수령
      final net = find.text(FormatHelper.formatWage(w.effectiveNetWage));
      await t.ensureVisible(net.first);
      await _settle(t);
      final nr = t.getRect(net.first);
      log.add('net=$nr label=${t.getRect(findVisibleText('실수령액'))} inBody=${nr.top >= vp().top - 0.5 && nr.bottom <= vp().bottom + 0.5}');
      await vqCapture(t, key, '${c.id}_3_net', conditions: cond('실수령액'));
      // ④ 편집부 — 추가수당/추가공제/메모
      final addF = find.byWidgetPredicate((x) => x is TextField && x.decoration?.suffixText == '원').first;
      final memo = find.byWidgetPredicate((x) => x is TextField && x.decoration?.hintText == '메모 입력 (선택)');
      // [after r2] 각 입력을 먼저 화면에 넣고 잰다 — r1 은 메모로 스크롤한 뒤 추가수당을 재서 머리 밑(hit false)이었다
      await t.ensureVisible(addF);
      await _settle(t);
      final dedF = find.byWidgetPredicate((x) => x is TextField && x.decoration?.suffixText == '원').at(1);
      log.add('edit-add add=${rr(addF)} inBody=${t.getRect(addF).top >= vp().top - 0.5 && t.getRect(addF).bottom <= vp().bottom + 0.5} bodyViewport=${vp()}');
      await t.ensureVisible(dedF);
      await _settle(t);
      log.add('edit-ded ded=${rr(dedF)} inBody=${t.getRect(dedF).top >= vp().top - 0.5 && t.getRect(dedF).bottom <= vp().bottom + 0.5}');
      await t.ensureVisible(memo);
      await _settle(t);
      log.add('edit add=${rr(addF)} memo=${rr(memo)} title추가수당=${t.getRect(findVisibleText('추가수당'))} 추가공제=${t.getRect(findVisibleText('추가공제'))} bodyViewport=${vp()}');
      await vqCapture(t, key, '${c.id}_4_edit', conditions: cond('편집부(추가수당·추가공제·메모)'));
      // ⑤ UI 취소 → result null · 닫힘(저장·확정 미진입)
      log.add('footer final save=${rr(save)} cancel=${rr(cancel)}');
      await t.tap(cancel);
      await _settle(t);
      expect(find.byType(WageDetailDialog), findsNothing, reason: '닫힘');
      expect(closed, isTrue);
      expect(result, isNull, reason: 'UI 취소 → result null(급여 writer 경로 아님)');
      log.add('cancel ok result=$result');
      // [r2] expect 전에 onError 를 되돌린다 — r1 에서 넘침이 있는 상태로 expect 가 실패해 프레임워크 단언 → 10분 정지
      FlutterError.onError = prev;
      log.add('overflows(${overflows.length})=${overflows.join(' | ')}');
      // ignore: avoid_print
      for (final l in log) { print(l); }
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
    });
  }

  // ── [DU1 후속42 §3] B2-W2 — 같은 calculated/3.3 자료, show 에 **businessName = _app().businessName** 전달(하네스 누락 보완 — 과거 B2-W 는 null).
  //   위치마다 실제 내부 ScrollPosition.pixels·표시 영역·대상 rect·PNG. 공제 상세 행(소득세·지방세)·실수령 label+금액·추가수당/추가공제 제목+입력 각각,
  //   공제 펼침·계산 기준 보기·휴게 연필의 **실제 클릭 외곽**(GestureDetector) 실측. writer(저장·확정·되돌리기·명세서) 미탭, UI 취소 → result null.
  for (final c in const [(id: 'B2-W2-A', w: 392.0, h: 844.0, s: 1.0), (id: 'B2-W2-B', w: 320.0, h: 640.0, s: 2.0)]) {
    testWidgets('${c.id} 급여 명세 ${c.w.toInt()}×${c.h.toInt()}@${c.s} — 사업장·공제 상세·실수령·편집 제목/입력·클릭 외곽', (t) async {
      await t.runAsync(vqLoadFonts);
      final overflows = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        final m = d.exceptionAsString();
        if (m.contains('overflowed')) {
          overflows.add(m.split('\n').first);
        } else {
          prev?.call(d);
        }
      };
      addTearDown(() => FlutterError.onError = prev);
      final size = Size(c.w, c.h);
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      final key = GlobalKey();
      final w = _stored(InsuranceRateModel.typeFreelancer33);
      WageDialogResult? result;
      var closed = false;
      await t.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.businessAdminTheme,
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(c.s)), child: child!),
          home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
              onPressed: () async {
                result = await WageDetailDialog.show(context: ctx, app: _app(), user: null, attendance: _att(), wage: w,
                    mode: WageDialogMode.calculated, businessName: _app().businessName);
                closed = true;
              },
              child: const Text('open'))))),
        ),
      ));
      await t.pump();
      await t.tap(find.text('open'));
      await _settle(t);
      final dlg = find.byType(WageDetailDialog);
      final mqv = MediaQuery.of(t.element(dlg));
      final log = <String>['${c.id} screenMQ padding=${mqv.padding} viewPadding=${mqv.viewPadding} viewInsets=${mqv.viewInsets} · physical ${t.view.padding.top},${t.view.padding.bottom},${t.view.viewInsets.bottom} · businessName=${_app().businessName}'];
      final body = find.descendant(of: dlg, matching: find.byType(Scrollable)).first;
      final pos = t.state<ScrollableState>(body).position;
      Rect vp() => t.getRect(body);
      bool inV(Rect r) => r.top >= vp().top - 0.5 && r.bottom <= vp().bottom + 0.5;
      bool hits(Finder f, Offset p) {
        final hit = HitTestResult();
        WidgetsBinding.instance.hitTestInView(hit, p, t.view.viewId);
        return hit.path.any((e) => e.target == t.renderObject(f));
      }
      Future<void> topAlign(Finder f) async {
        await t.ensureVisible(f);
        await _settle(t);
        final r = t.getRect(f);
        pos.jumpTo((pos.pixels + (r.top - (vp().top + 4))).clamp(pos.minScrollExtent, pos.maxScrollExtent));
        await _settle(t);
      }
      Map<String, Object?> cond(String state) => {
            'screen': 'WageDetailDialog.show(mode calculated, businessName=강남 물류센터) + root overlay', 'theme': 'RoleTheme.businessAdminTheme',
            'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'dpr': 1.0, 'textScaler': c.s,
            'mq': 'padding=${mqv.padding} viewPadding=${mqv.viewPadding} viewInsets=${mqv.viewInsets}',
            'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록',
            'data': '_app/_att/_stored(freelancer_3_3) 2026-11-03 시급25,000 09:00–18:00 휴게60 calculated · user null · businessName 강남 물류센터',
            'prefs': '미사용', 'clock': '미주입', 'state': state, 'offset': pos.pixels.toStringAsFixed(1)};
      String rr(Finder f) {
        final r = t.getRect(f);
        return '$r(${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)}) hit=${hits(f, r.center)}';
      }
      // ① 사업장·업무 메타
      final meta = findVisibleTextContaining('강남 물류센터');
      await topAlign(meta.first);
      log.add('meta rect=${t.getRect(meta.first)} inBody=${inV(t.getRect(meta.first))} offset=${pos.pixels.toStringAsFixed(1)} viewport=${vp()}');
      await vqCapture(t, key, '${c.id}_1_meta', conditions: cond('사업장·업무 메타'));
      // 클릭 외곽: 휴게 연필
      final pencil = find.ancestor(of: find.byIcon(Icons.edit_outlined), matching: find.byType(GestureDetector)).first;
      await t.ensureVisible(pencil);
      await _settle(t);
      log.add('pencil gesture=${rr(pencil)} offset=${pos.pixels.toStringAsFixed(1)}');
      // ② 공제 펼침 + 클릭 외곽
      final dHeader = findVisibleTextContaining('공제 (');
      final dTap = find.ancestor(of: dHeader.first, matching: find.byType(GestureDetector)).first;
      await topAlign(dTap);
      log.add('deductionToggle gesture=${rr(dTap)} offset=${pos.pixels.toStringAsFixed(1)}');
      await t.tap(dHeader.first);
      await _settle(t);
      final item = findVisibleText('소득세·지방세');
      final itemRow = find.ancestor(of: item.first, matching: find.byType(Padding)).first;
      final amountTxt = find.descendant(of: itemRow, matching: find.textContaining('6,600'));
      log.add('deductionDetail label=${t.getRect(item.first)} row=${t.getRect(itemRow)} amount=${t.getRect(amountTxt.first)} rowInBody=${inV(t.getRect(itemRow))} offset=${pos.pixels.toStringAsFixed(1)}');
      await vqCapture(t, key, '${c.id}_2_deduction_detail', conditions: cond('공제 펼침·상세 행'));
      // ③ 실수령 label + 금액(같은 위치)
      final netLabel = findVisibleText('실수령액');
      final net = find.text(FormatHelper.formatWage(w.effectiveNetWage));
      await topAlign(netLabel.first);
      log.add('net label=${t.getRect(netLabel.first)} amount=${t.getRect(net.first)} 둘다보임=${inV(t.getRect(netLabel.first)) && inV(t.getRect(net.first))} offset=${pos.pixels.toStringAsFixed(1)}');
      await vqCapture(t, key, '${c.id}_3_net', conditions: cond('실수령 label+금액'));
      // 클릭 외곽: 계산 기준 보기
      final guide = find.ancestor(of: findVisibleText('계산 기준 보기'), matching: find.byType(GestureDetector)).first;
      await t.ensureVisible(guide);
      await _settle(t);
      log.add('guideToggle gesture=${rr(guide)} offset=${pos.pixels.toStringAsFixed(1)}');
      // ④ 추가수당 / ⑤ 추가공제 — 각 제목 + 입력
      final fields = find.byWidgetPredicate((x) => x is TextField && x.decoration?.suffixText == '원');
      for (final (i, title) in [(0, '추가수당'), (1, '추가공제')]) {
        final ti = findVisibleText(title);
        await topAlign(ti.first);
        final f = fields.at(i);
        final tr = t.getRect(ti.first), fr = t.getRect(f);
        log.add('edit $title title=$tr field=${rr(f)} 제목보임=${inV(tr)} 입력보임=${inV(fr)} offset=${pos.pixels.toStringAsFixed(1)}');
        await vqCapture(t, key, '${c.id}_${4 + i}_edit_$title', conditions: cond('$title 제목+입력'));
      }
      // UI 취소 → result null
      final cancel = find.ancestor(of: findVisibleText('취소'), matching: find.byWidgetPredicate((x) => x is OutlinedButton)).first;
      await t.tap(cancel);
      await _settle(t);
      expect(find.byType(WageDetailDialog), findsNothing);
      expect(closed, isTrue);
      expect(result, isNull);
      log.add('cancel ok result=$result');
      FlutterError.onError = prev;
      log.add('overflows(${overflows.length})=${overflows.join(' | ')}');
      // ignore: avoid_print
      for (final l in log) { print(l); }
      expect(overflows, isEmpty, reason: overflows.join(' | '));
      expect(t.takeException(), isNull);
    });
  }
}
