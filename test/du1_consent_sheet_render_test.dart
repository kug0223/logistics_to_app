// [CONSENT-R4d 후보 사본] 원본 A/test/du1_consent_sheet_render_test.dart sha256=e1c1b06f4d83968b5f7a04c73bf7bb4fbcb2db4e6baa648b2e0dd1911187489e · 바뀐 자리는 R/work/consent-copy-preparation-r4d-20261119/manifests/test_change_map.tsv
// ignore_for_file: depend_on_referenced_packages
// [DU1-F2 · R4 · followup_6] 지원 확인 시트(동의 안내) LOCAL 실제 위젯 렌더 — 기본/큰 글씨, 본문 스크롤 끝(마지막 동의 문구 viewport 안), 본문 대비 토큰, 취소 실제 탭.
//   [정정] 하단 취소·CTA 는 스크롤 밖이라 항상 보인다 — 구현5 의 "끝까지 스크롤해 하단 행동 도달"은 실제 관측이 아니었다.
//   제출하지 않는다(Firestore 는 응답하지 않는 가짜 플랫폼). 모든 warning/info 소비처의 RUNTIME 통과를 뜻하지 않는다.
//   [g5 · 판정 consentr2stop §1-1 · §2] 끝 프레임 문단 전체 포함(원 :119)은 W · 자세히 단추와 함께 들어가는 B 에만 둔다 — 안 들어가는 B 는
//   같은 본문 scroll owner 를 실제 drag 해 기간 문단의 모든 줄이 온전히 보인 적이 있고 가시 구간이 이어짐을 증명한다. 끝(max)에서는 마지막 줄 · 자세히 단추 상자 · 48 을 본다.
import 'dart:async';
import 'dart:ui' as ui show BoxHeightStyle;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';
import 'package:ALfit/widgets/dialogs/apply/multi_apply_confirm_sheet.dart';

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

final kDay = DateTime(2026, 11, 8);
final _nav = GlobalKey<NavigatorState>();

TOModel _to() => TOModel(
    id: 'to1', businessId: 'biz1', businessName: '[QA] 아주 긴 이름의 물류센터 사업장 평택 2공장', type: 'flex', title: '단기 모집',
    creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0, workDetails: const [],
    totalRequired: 2, totalConfirmed: 0, totalPending: 0, isPublished: true, publishMode: 'immediate',
    createdAt: DateTime(2026, 11, 1), statusUpdatedAt: DateTime(2026, 11, 1));

WorkDetailData _wd() => WorkDetailData(
    wdId: 'wd1', workType: 'QA 분류', workTypeIcon: 'box', workTypeColor: '#000000', workTypeBackgroundColor: '#FFFFFF',
    wage: 13000, wageType: 'hourly', requiredCount: 2, startTime: '15:30', endTime: '18:30', order: 0);

SlotModel _slot() => SlotModel(id: 's1', toId: 'to1', date: kDay, workDetails: [_wd()], status: SlotStatus.open, createdAt: DateTime(2026, 11, 1));

// ── [g5 · 판정 consentr2stop §2] 측정 — consent_r4d_six_surface_harness_test.dart :388–:420(DU571 r2 측정 블록) 국소 사본(바이트 그대로) + 줄 상자 ──
/// [a] 가 [b] **안**에 있는가(0.5px 허용).
bool _inside(Rect a, Rect b) => a.left >= b.left - 0.5 && a.top >= b.top - 0.5 && a.right <= b.right + 0.5 && a.bottom <= b.bottom + 0.5;

final String _wj = String.fromCharCode(0x2060);
final String _zw = String.fromCharCode(0x200B);

bool _gap(String ch) => ch == ' ' || ch == '\n' || ch == '\t' || ch == _zw;

/// 글 전문이 그려졌는가 — 마지막 글자까지 자리(box)가 문단 크기 안에 있다(말줄임으로 잘린 글자는 자리가 없다).
bool _fullShown(RenderParagraph rp, Size size) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  for (var i = s.length - 1; i >= 0; i--) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    // [DU571 r2 · 판정167 시험 STOP 수리 · 판정159/161/162 방식] 세로는 줄 배치(max 상자) · 가로는 tight right(종전) · 공차 0.5 그대로.
    //   tight 세로는 run 글꼴 높이라 줄 높이 1.3 < 글꼴 원래 1.448em 이면 줄 상자 밖으로 나온다(DU559 nmraw: h+1.258). 잉크/clip 증명 아님.
    final sel = TextSelection(baseOffset: i, extentOffset: i + 1);
    final tight = rp.getBoxesForSelection(sel);
    final mx = rp.getBoxesForSelection(sel, boxHeightStyle: ui.BoxHeightStyle.max);
    return tight.isNotEmpty && mx.isNotEmpty && mx.first.bottom <= size.height + 0.5 && tight.first.right <= size.width + 0.5;
  }
  return false;
}

/// [f] 가 실제로 보일 수 있는 칸 — 화면 ∩ 조상 스크롤 칸 전부.
Rect _area(Finder f, Rect screen) {
  var a = screen;
  for (final e in find.ancestor(of: f, matching: find.byType(Scrollable)).evaluate()) {
    final ro = e.renderObject;
    if (ro is RenderBox && ro.hasSize) a = a.intersect(ro.localToGlobal(Offset.zero) & ro.size);
  }
  return a;
}

/// [g5] 문단의 줄 상자(문단 좌표) — 보이는 글자마다 max 상자(줄 배치 세로 · tight 가로)를 같은 줄끼리 합친다(공백 · 낱말 묶음 문자 제외).
List<Rect> _lineRects(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final out = <Rect>[];
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (ch == _wj || _gap(ch)) continue;
    for (final b in rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1), boxHeightStyle: ui.BoxHeightStyle.max)) {
      final r = b.toRect();
      final k = out.indexWhere((x) => (x.top - r.top).abs() <= 0.5);
      if (k < 0) {
        out.add(r);
      } else {
        out[k] = out[k].expandToInclude(r);
      }
    }
  }
  out.sort((a, b) => a.top.compareTo(b.top));
  return out;
}

Future<List<String>> _pump(WidgetTester tester, {required Size size, required double scale}) async {
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
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: RoleTheme.workerTheme,
    builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
    navigatorKey: _nav,
    home: const Scaffold(body: Text('공고 상세')),
  ));
  // 실제 사용처처럼 별도 route 로 연다 — 하단 '취소'가 Navigator.pop 으로 닫히는지까지 본다
  unawaited(_nav.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(body: MultiApplyConfirmSheet(items: [(slot: _slot(), work: _wd())], to: _to(), myApplications: const [])))));
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  return overflows;
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  for (final c in const [(Size(392, 844), 1.0), (Size(320, 640), 2.0)]) {
    testWidgets('동의 시트 ${c.$1.width.toInt()}dp×${c.$2} — 넘침 0 · 본문 중립 textPrimary(D-CB-CONSENT) · 본문 스크롤 끝의 마지막 동의 문구가 viewport 안 · 취소가 실제로 닫는다', (tester) async {
      final o = await _pump(tester, size: c.$1, scale: c.$2);
      // [CONSENT-R4b] 문단 1 = 공통 행동 문장(r4 감사 §4 · 다건 지원 시트의 실제 버튼 '지원하기'를 포함하는 '지원·동의·수락').
      final body = findVisibleTextContaining('아래 지원·동의·수락 버튼을 누르면'); // [DU288] 보이는 글자(낱말 묶음 문자 제외)
      expect(body, findsOneWidget);
      // [CONSENT-R4] 정상 사전동의 전문은 경고 안내(E-NOTICE)가 아니다 — 중립 면 위 중립 본문(후속121 §3).
      expect(tester.widget<Text>(body).style?.color, AppColors.textPrimary, reason: 'D-CB-CONSENT — 중립 본문');

      // [DU1 followup_6 §1] 하단 '취소'·CTA 는 스크롤 **밖**(항상 보임)이다 — 그 존재로 스크롤 도달을 판정하지 않는다.
      //   본문 SingleChildScrollView 를 끝(maxScrollExtent)까지 실제로 끌고, 마지막 동의 문구가 그 viewport 안에 온전히 있는지 본다.
      final bodyScroll = find.descendant(of: find.byType(MultiApplyConfirmSheet), matching: find.byType(Scrollable)).first;
      final pos = tester.state<ScrollableState>(bodyScroll).position;
      var drags = 0;
      while (pos.pixels < pos.maxScrollExtent && drags < 60) {
        await tester.drag(bodyScroll, const Offset(0, -200));
        await tester.pump(const Duration(milliseconds: 50));
        drags++;
      }
      expect(pos.pixels, moreOrLessEquals(pos.maxScrollExtent, epsilon: 0.5), reason: '본문 스크롤 끝에 도달');
      // ignore: avoid_print
      print('CONSENT-SCROLL ${c.$1.width.toInt()}x${c.$1.height.toInt()}@${c.$2}: max=${pos.maxScrollExtent.toStringAsFixed(1)} drags=$drags');
      final lastPart = DocumentAccessConsent.partsFor(_to().businessName).last.trim();
      final last = find.byWidgetPredicate((w) =>
          w is Text && (w.data ?? w.textSpan?.toPlainText() ?? '').replaceAll('\u2060', '').contains(lastPart.substring(0, 12)));
      expect(last, findsOneWidget, reason: '마지막 동의 문구');
      final vp = tester.getRect(bodyScroll);
      final r = tester.getRect(last);
      // [g5 · 판정 consentr2stop §1-1 · §2] 마지막 문단 = 카드의 **기간 문단**(partsFor(...).last · 상세는 닫힌 채 · 이 시험은 열지 않는다).
      //   같은 원문 · 읽기 이름 · 중립 색 · 같은 본문 scroll owner · viewport/배율 · 공차 0.5 그대로. 측정 = 하네스 DU571 r2 블록(_fullShown · _area · _inside) 국소 사본.
      final lastW = tester.widget<Text>(last);
      expect((lastW.data ?? '').replaceAll(_wj, ''), lastPart, reason: '기간 문단 원문 그대로(낱말 묶음 문자 제외)');
      expect(lastW.semanticsLabel?.trim(), lastPart, reason: '기간 문단 읽기 이름 = 원문');
      expect(lastW.style?.color, AppColors.textPrimary, reason: 'D-CB-CONSENT — 기간 문단도 중립 본문');
      // [g6 · 판정173 §5 :57] semanticsLabel 있는 Text 의 바깥 렌더는 RenderSemanticsAnnotations — 그 Text 아래 정확한 RichText 1 개에서 RenderParagraph 를 얻는다(Text 는 원문/semantics 확인에 그대로).
      final lastRich = find.descendant(of: last, matching: find.byType(RichText));
      expect(lastRich, findsOneWidget, reason: '기간 문단 Text 아래 RichText 정확히 1');
      final rp = tester.renderObject<RenderParagraph>(lastRich);
      final toggle = find.byKey(const ValueKey('documentAccessConsentDetailsToggle'));
      expect(toggle, findsOneWidget, reason: '자세히 단추');
      final screen = Offset.zero & (tester.view.physicalSize / tester.view.devicePixelRatio);
      final area = _area(last, screen);
      final tr = tester.getRect(toggle);
      final lines = _lineRects(rp);
      final h = rp.size.height;
      final span = tr.bottom - r.top;
      final isW = c.$1 == const Size(392, 844) && c.$2 == 1.0;
      final fits = span <= area.height + 0.5;
      final prof = '${c.$1.width.toInt()}x${c.$1.height.toInt()}@${c.$2}';
      // 끝 프레임(max) 실측 — 기간 문단 rect · 높이 · 줄 수 · 본문 viewport · 유효 칸(화면 ∩ 조상 스크롤 칸) · 문단 위 → 자세히 단추 아래 영역 · offset/max.
      // ignore: avoid_print
      print('CONSENT-READ $prof end offset=${pos.pixels.toStringAsFixed(1)} max=${pos.maxScrollExtent.toStringAsFixed(1)} '
          'para=$r h=${h.toStringAsFixed(1)} lines=${lines.length} vp=$vp area=$area areaH=${area.height.toStringAsFixed(1)} '
          'toggle=$tr span=${span.toStringAsFixed(1)} fits=$fits paraFitsArea=${h <= area.height + 0.5}');
      expect(area.isEmpty, isFalse, reason: '본문 보이는 칸이 비었다');
      expect(_fullShown(rp, rp.size), isTrue, reason: '기간 문단 전문(말줄임 · 문단 상자 밖 0)');
      expect(lines, isNotEmpty, reason: '기간 문단 줄 상자');
      final lastLine = lines.last.shift(rp.localToGlobal(Offset.zero));
      expect(_inside(lastLine, area), isTrue, reason: '끝에서 기간 문단 마지막 줄 $lastLine 이 유효 칸 $area 안');
      expect(_inside(tr, area), isTrue, reason: '끝에서 자세히 단추 전체 상자 $tr 가 유효 칸 $area 안');
      expect(toggle.hitTestable(), findsOneWidget, reason: '끝에서 자세히 단추를 누를 수 있다');
      expect(tr.height >= 48 - 0.01 && tr.width >= 48 - 0.01, isTrue, reason: '자세히 터치 $tr');
      // W · 자세히 단추와 함께 들어가는 B = 기존 끝 프레임 문단 전체 포함 그대로(원 :119).
      if (isW || fits) {
        expect(r.top, greaterThanOrEqualTo(vp.top - 0.5));
      }
      expect(r.bottom, lessThanOrEqualTo(vp.bottom + 0.5), reason: '마지막 동의 문구가 본문 viewport 안에 온전히');
      // [g5 · §2] B 에서 함께 들어가지 않을 때만 도달 프레임을 나눈다 — 같은 본문 scroll owner 를 실제 drag(손가락 아래 = 위 내용 쪽)하며
      //   이동마다 문단 rect · offset · 유효 칸을 다시 읽는다. 줄마다 온전히 보인 프레임 · 문단 ≤ 칸이면 문단 전체 한 프레임 · 문단 좌표 가시 구간 연속.
      if (!(isW || fits)) {
        final needWhole = h <= area.height + 0.5;
        final stepPx = needWhole ? ((area.height - h) / 2).clamp(1.0, 8.0).toDouble() : 8.0;
        final seen = List<bool>.filled(lines.length, false);
        final spans = <(double, double)>[];
        var wholeSeen = false;
        var topSeen = false;
        void read(String tag) {
          final a = _area(last, screen);
          expect(a.isEmpty, isFalse, reason: '$tag 보이는 칸이 비었다');
          final o = rp.localToGlobal(Offset.zero);
          final vTop = (a.top - o.dy).clamp(0.0, h).toDouble();
          final vBot = (a.bottom - o.dy).clamp(0.0, h).toDouble();
          if (vBot > vTop) {
            spans.add((vTop, vBot));
            if (vTop <= 0.5) topSeen = true;
          }
          for (var i = 0; i < lines.length; i++) {
            final g = lines[i].shift(o);
            expect(g.left >= a.left - 0.5 && g.right <= a.right + 0.5, isTrue,
                reason: '$tag 기간 문단 줄 ${i + 1} 가로 잘림 $g / $a — 제품 접근성 실패');
            if (g.top >= a.top - 0.5 && g.bottom <= a.bottom + 0.5) seen[i] = true;
          }
          if (_inside(o & rp.size, a)) wholeSeen = true;
          // ignore: avoid_print
          print('CONSENT-READ $prof $tag offset=${pos.pixels.toStringAsFixed(1)} para=${o & rp.size} area=$a '
              'vis=${vTop.toStringAsFixed(1)}-${vBot.toStringAsFixed(1)} seen=${seen.where((x) => x).length}/${lines.length} whole=$wholeSeen');
        }

        read('end');
        final drag = await tester.startGesture(tester.getCenter(bodyScroll));
        await drag.moveBy(const Offset(0, 24)); // 끌기 인식(터치 슬롭 넘김)
        await tester.pump(const Duration(milliseconds: 16));
        read('drag0');
        var moves = 0;
        while (moves < 600 && pos.pixels > 0 && !(seen.every((x) => x) && topSeen && (!needWhole || wholeSeen))) {
          await drag.moveBy(Offset(0, stepPx));
          await tester.pump(const Duration(milliseconds: 16));
          moves++;
          read('drag$moves');
        }
        await tester.pump(const Duration(milliseconds: 150)); // 놓기 전 멈춤 — 튕김 없이 놓는다
        await drag.up();
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        // ignore: avoid_print
        print('CONSENT-READ $prof sweep moves=$moves step=${stepPx.toStringAsFixed(1)} needWhole=$needWhole offset=${pos.pixels.toStringAsFixed(1)}');
        expect(pos.pixels, lessThan(pos.maxScrollExtent - 0.5), reason: '같은 본문 scroll owner 가 실제로 끌려 움직였다');
        final miss = [for (var i = 0; i < lines.length; i++) if (!seen[i]) i + 1];
        expect(miss, isEmpty,
            reason: '기간 문단 첫 줄 · 마지막 줄 · 중간 모든 줄이 적어도 한 번 온전히 보인다(안 보인 줄 $miss / ${lines.length}) — 제품 접근성 실패');
        if (needWhole) {
          expect(wholeSeen, isTrue,
              reason: '기간 문단(${h.toStringAsFixed(1)})이 유효 칸(${area.height.toStringAsFixed(1)})에 들어가면 어느 도달 프레임에서 문단 전체가 온전히 보인다');
        }
        spans.sort((x, y) => x.$1.compareTo(y.$1));
        var covered = 0.0;
        var hole = -1.0;
        for (final s in spans) {
          if (s.$1 > covered + 0.5) {
            hole = covered;
            break;
          }
          if (s.$2 > covered) covered = s.$2;
        }
        expect(hole < 0 && covered >= h - 0.5, isTrue,
            reason: '문단 좌표 가시 구간이 0-${h.toStringAsFixed(1)} 를 공백 없이 잇는다(구멍 $hole · 끝 $covered · 프레임 ${spans.length})');
      }

      // 실제로 눌린다 — 시트 route 가 닫히고 공고 상세로 돌아온다(제출 writer 는 부르지 않는다)
      await tester.tap(find.widgetWithText(TextButton, '취소'));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('공고 상세'), findsOneWidget);
      expect(find.byType(MultiApplyConfirmSheet), findsNothing);
      expect(o, isEmpty, reason: o.join(' | '));
    });
  }
}
