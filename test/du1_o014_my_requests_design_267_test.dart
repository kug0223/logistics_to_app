// ignore_for_file: depend_on_referenced_packages
// [DU267 O014 내 요청 대화 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU267_RUN=1 이고 DU267_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   실제처럼 MyRequestsDialog.show(reads: 가짜 읽기)로 연다. 장면 6(list·empty·error·c-id-ok·c-term-ok·c-term-no)
//   × W360/1.0·B320/2.0. 확인 장면은 승인/거절을 눌러 확인 대화만 보고 확인은 누르지 않는다(mutation 0).
//   측정 하네스는 DU266 계승(lines 기본 true). after 에서는 측정 이름마다 한 번 이상 화면 안에서 보였는지도 본다(빈 단언 방지).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/interim_settlement_request_model.dart';
import 'package:ALfit/models/core/schedule_change_request_model.dart';
import 'package:ALfit/screens/user/dialogs/my_requests_dialog.dart';
import 'package:ALfit/screens/user/dialogs/my_requests_reads.dart';

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

final _now = DateTime.now();
final _target = DateTime(_now.year, _now.month, _now.day).add(const Duration(days: 5));
const _reason = '가족 행사로 하루 쉬어야 합니다. 다음 주 같은 요일에 대신 근무할 수 있습니다.';

ScheduleChangeRequestModel _leave() => ScheduleChangeRequestModel(
      id: 'sc1',
      businessId: 'bizC',
      applicationId: 'appC',
      applicantUid: 'u1',
      applicantName: '김근로',
      targetDate: _target,
      requestType: RequestType.LEAVE,
      requestedBy: RequesterType.APPLICANT,
      requestedByUid: 'u1',
      requestedAt: _now.subtract(const Duration(hours: 1)),
      reason: _reason,
    );

IdCardAccessRequestModel _idReq() => IdCardAccessRequestModel(
      id: 'idreq1',
      requesterId: 'admin1',
      requesterName: '박사장',
      requesterBusinessId: 'bizA',
      requesterBusinessName: '강남 물류센터',
      targetUserId: 'u1',
      targetUserName: '김근로',
      reason: IdCardAccessReason.incomeTax,
      status: IdCardAccessStatus.pending,
      requestedAt: _now.subtract(const Duration(hours: 2)),
    );

ApplicationModel _termination() => ApplicationModel(
      id: 'app-term1',
      uid: 'u1',
      toId: 'toB',
      slotId: 'slotB',
      businessId: 'bizB',
      businessName: '성수 제2 냉동 물류창고',
      toTitle: '장기 모집',
      selectedWorkType: '피킹',
      wdId: 'wdB',
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      wageType: 'hourly',
      status: 'CONFIRMED',
      workDate: DateTime(2026, 9, 25),
      appliedAt: DateTime(2026, 9, 1),
      terminationStatus: 'PENDING',
      terminationRequestedAt: _now.subtract(const Duration(days: 1)),
      terminationReason: '개인 사정',
    );

InterimSettlementRequestModel _interim(String id, String status, int daysAgo, {DateTime? transfer}) =>
    InterimSettlementRequestModel(
      id: id,
      applicationId: 'appI',
      businessId: 'bizI',
      businessName: '평택 물류센터',
      workerId: 'u1',
      workerName: '김근로',
      periodStart: DateTime(2026, 11, 1),
      periodEnd: DateTime(2026, 11, 7),
      attendanceIds: const ['a1', 'a2', 'a3'],
      requestedAmount: 312000,
      netAmount: 301704,
      status: status,
      scheduledTransferDate: transfer,
      createdAt: _now.subtract(Duration(days: daysAgo)),
    );

MyRequestsReads _reads(String sc) => MyRequestsReads(
      scheduleChangeRequests: (uid) async => sc == 'list' ? [_leave()] : <ScheduleChangeRequestModel>[],
      pendingIdCardRequests: (uid) async =>
          (sc == 'list' || sc == 'error' || sc == 'c-id-ok') ? [_idReq()] : <IdCardAccessRequestModel>[],
      terminationRequests: (uid) async {
        if (sc == 'error') throw StateError('term down');
        return (sc == 'list' || sc.startsWith('c-term')) ? [_termination()] : <ApplicationModel>[];
      },
      interimSettlements: () async => sc == 'list'
          ? [
              _interim('is1', InterimSettlementRequestModel.statusPending, 2),
              _interim('is2', InterimSettlementRequestModel.statusApproved, 3, transfer: DateTime(2026, 11, 14)),
            ]
          : <InterimSettlementRequestModel>[],
    );

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

/// 글자 단위 줄 나눔 — 줄마다 보이는 글자, 그리고 '낱말 안에서 끊긴' 곳 수.
///   끊긴 자리 앞뒤가 모두 한글 음절·영숫자이고 그 사이에 공백·ZWSP·줄바꿈·구두점이 없으면 음절 끊김으로 센다.
({List<String> lines, int sylBreaks}) _lineInfo(RenderParagraph rp) {
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
      final sep = gap.contains(' ') || gap.contains(zw) || gap.contains(String.fromCharCode(10)) ||
          RegExp('[·,./()~-]').hasMatch(gap);
      if (!sep && word(raw[lastIdx]) && word(ch)) breaks++;
    }
    buf.write(ch);
    lastTop = top;
    lastIdx = i;
  }
  lines.add(TextLayout.plain(buf.toString()).trim());
  return (lines: lines, sylBreaks: breaks);
}

void main() {
  final phase = Platform.environment['DU267_PHASE'] ?? '';
  final run = Platform.environment['DU267_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('D267 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nDrag = 0, nPng = 0, nTap = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D267-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 1600 && nDrag <= 80 && nPng <= 120 && nTap <= 24, '사용량 한도');
        await t.pump(const Duration(milliseconds: 50));
      }
    }

    final overflow = <String>[];
    void safe(String at) {
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

    Finder rich(bool Function(String p) f) =>
        find.byWidgetPredicate((w) => w is RichText && f(TextLayout.plain(w.text.toPlainText())), skipOffstage: false);
    Finder? nth(Finder f, int i) {
      final els = f.evaluate().toList();
      if (els.isEmpty) return null;
      final e = i < 0 ? els.last : (i < els.length ? els[i] : null);
      if (e == null) return null;
      return find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
    }

    Finder? glyph(IconData icon, int i) {
      final f = find.descendant(of: find.byIcon(icon, skipOffstage: false), matching: find.byType(RichText), skipOffstage: false);
      return nth(f, i);
    }

    // 카드 틀(전: Card, 후: radius 16 Container) 안에서 그 카드 제목과 함께 있는 글자 — 같은 문구가 여러 카드에 있을 때 구별한다.
    bool isShell(Widget w) =>
        w is Card ||
        (w is Container && w.decoration is BoxDecoration && (w.decoration as BoxDecoration).borderRadius == BorderRadius.circular(16));
    Finder? inCard(String title, String text, {bool Function(String p)? match}) {
      for (final e in rich(match ?? (p) => p == text).evaluate()) {
        final f = find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
        final shells = find.ancestor(of: f, matching: find.byWidgetPredicate(isShell, skipOffstage: false)).evaluate().toList();
        if (shells.isEmpty) continue;
        final s = find.byElementPredicate((x) => identical(x, shells.first), skipOffstage: false);
        if (find.descendant(of: s, matching: rich((p) => p == title), skipOffstage: false).evaluate().isNotEmpty) return f;
      }
      return null;
    }

    double r1(double v) => double.parse(v.toStringAsFixed(1));
    List<double> lt(Rect r) => [r.left, r.top, r.right, r.bottom].map(r1).toList();
    bool inside(Rect r, Rect b) => r.left >= b.left - 0.5 && r.top >= b.top - 0.5 && r.right <= b.right + 0.5 && r.bottom <= b.bottom + 0.5;

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

    final dateLabel = FormatHelper.formatDateKorean(_target);
    final key = GlobalKey();
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        for (final sc in const ['list', 'empty', 'error', 'c-id-ok', 'c-term-ok', 'c-term-no']) {
          cur = '${c.id} $sc';
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          safe('장면 종료');
          overflow.clear();
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          await t.pumpWidget(RepaintBoundary(
            key: key,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.workerTheme,
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: const [Locale('ko', 'KR')],
              home: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (ctx) => TextButton(
                      onPressed: () => MyRequestsDialog.show(ctx, applicantUid: 'u1', reads: _reads(sc)),
                      child: const Text('열기'),
                    ),
                  ),
                ),
              ),
            ),
          ));
          await frames(2);
          nTap++;
          await t.tap(find.text('열기'));
          await frames(14);
          safe('대화 열림');
          need(find.byType(MyRequestsDialog).evaluate().length == 1, '대화가 열리지 않았다');

          if (sc.startsWith('c-')) {
            // 확인 대화만 연다 — 확인은 누르지 않는다(승인·거절 호출은 확인 뒤에만 나간다).
            final label = sc == 'c-term-no' ? '거절' : '승인';
            final target = after ? find.text(label) : find.byTooltip(label);
            need(target.evaluate().isNotEmpty, '$label 행동을 찾지 못했다');
            nTap++;
            await t.tap(target.first);
            await frames(14);
            safe('확인 대화 열림');
            need(rich((p) => p == '취소').evaluate().isNotEmpty, '확인 대화가 열리지 않았다');
          }

          Finder? sfOf() {
            final f = find.descendant(of: find.byType(MyRequestsDialog), matching: find.byType(Scrollable), skipOffstage: false);
            return f.evaluate().isEmpty ? null : nth(f, 0);
          }

          Map<String, Object?> info(String nm, Finder? f, {String? kind, bool lines = true, Finder? box}) {
            if (f == null) return {'name': nm, 'kind': kind, 'present': false};
            final rp = t.renderObject<RenderParagraph>(f);
            final r = t.getRect(f);
            final fg = rp.text.style?.color;
            final bg = bgOf(f.evaluate().first);
            final sf = sc.startsWith('c-') ? null : sfOf();
            final inSf = sf != null && find.descendant(of: sf, matching: f, skipOffstage: false).evaluate().isNotEmpty;
            final vp = inSf ? t.getRect(sf) : screen;
            final li = lines ? _lineInfo(rp) : null;
            Rect? br;
            if (box != null && box.evaluate().isNotEmpty) br = t.getRect(box.first);
            return {
              'name': nm, 'kind': kind, 'present': true, 'rect': lt(r), 'visible': inside(r, screen) && inside(r, vp),
              'fontSize': rp.text.style?.fontSize, 'weight': rp.text.style?.fontWeight?.value,
              'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
              'didExceedMaxLines': rp.didExceedMaxLines, 'maxLines': rp.maxLines,
              if (li != null) 'lines': li.lines,
              if (li != null) 'sylBreaks': li.sylBreaks,
              if (br != null) 'boxH': r1(br.height),
            };
          }

          Finder? anc(Finder? f, bool Function(Widget w) p) =>
              f == null ? null : find.ancestor(of: f, matching: find.byWidgetPredicate(p, skipOffstage: false));
          bool isBtn(Widget w) => w is ButtonStyleButton;

          List<Map<String, Object?>> measure() {
            final xs = <Map<String, Object?>>[];
            void add(String nm, Finder? f, {String? kind, Finder? box}) => xs.add(info(nm, f, kind: kind, box: box));
            if (sc.startsWith('c-')) {
              final label = switch (sc) { 'c-id-ok' => '승인', 'c-term-ok' => '승인 (해지)', _ => '거절' };
              final want = switch (sc) { 'c-id-ok' => '#166534', 'c-term-ok' => '#B42318', _ => '#1976D2' };
              add('확인 버튼', nth(rich((p) => p == label), -1), kind: 'cfm:$want');
              add('확인 취소', nth(rich((p) => p == '취소'), -1), kind: 'record');
              return xs;
            }
            final close = glyph(Icons.close, 0);
            add('머리 제목', nth(rich((p) => p == '내 알림'), 0), kind: 'title');
            add('머리 아이콘', glyph(Icons.notifications, 0), kind: 'hdrIcon');
            add('닫기', close, kind: 'closeIcon', box: anc(close, (w) => w is IconButton));
            if (sc == 'list') {
              add('건수 배지', nth(rich((p) => p == '5'), 0), kind: 'pair:#3859E8/#EEF2FF');
              for (final x in ['휴무 요청', '신분증 열람 요청', '계약해지 요청']) {
                add('제목 $x', nth(rich((p) => p == x), 0), kind: 'title');
              }
              add('제목 중간정산', inCard('중간정산 요청', '중간정산 요청'), kind: 'title');
              add('날짜', nth(rich((p) => p == dateLabel), 0), kind: 'value');
              add('사업장 신분증', nth(rich((p) => p == '강남 물류센터'), 0), kind: 'value');
              add('사업장 해지', nth(rich((p) => p == '성수 제2 냉동 물류창고'), 0), kind: 'value');
              add('사업장 정산', inCard('중간정산 요청', '평택 물류센터'), kind: 'value');
              add('요청자', nth(rich((p) => p == '요청자: 박사장'), 0), kind: 'detail');
              add('사유 휴무', nth(rich((p) => p == _reason), 0), kind: 'body');
              add('사유 신분증', nth(rich((p) => p == '사유: 소득세 신고'), 0), kind: 'body');
              add('사유 해지', nth(rich((p) => p == '사유: 개인 사정'), 0), kind: 'body');
              add('정산 기간', nth(rich((p) => p.startsWith('11/1 ~ 11/7')), 0), kind: 'detail');
              add('이체 예정일', nth(rich((p) => p.startsWith('이체 예정일')), 0), kind: 'fg:#00796B');
              add('배지 대기중', nth(rich((p) => p == '대기중'), 0), kind: 'pair:#946200/#FFF5D6');
              add('배지 신분증', inCard('신분증 열람 요청', '승인 대기'), kind: 'pair:#0D47A1/#E3F2FD');
              add('배지 자동승인', nth(rich((p) => p == '2일 후 자동승인'), 0), kind: 'pair:#946200/#FFF5D6');
              add('배지 정산 대기', inCard('중간정산 요청', '승인 대기'), kind: 'pair:#946200/#FFF5D6');
              add('배지 정산 승인됨', nth(rich((p) => p == '승인됨 · 이체 대기'), 0), kind: 'pair:#00796B/#E0F2F1');
              final cancel = nth(rich((p) => p == '요청 취소'), 0);
              add('요청 취소', cancel, kind: 'secBtn', box: anc(cancel, isBtn));
              for (final card in ['신분증 열람 요청', '계약해지 요청']) {
                final no = inCard(card, '거절');
                final ok = inCard(card, '승인');
                add('거절 $card', no, kind: 'secBtn', box: anc(no, isBtn));
                add('승인 $card', ok, kind: 'priBtn', box: anc(ok, isBtn));
              }
              add('아이콘 휴무', glyph(Icons.beach_access, 0), kind: 'fg:#946200');
              add('아이콘 신분증', glyph(Icons.badge, 0), kind: 'fg:#1976D2');
              add('아이콘 해지', glyph(Icons.warning_amber, 0), kind: 'fg:#946200');
              add('아이콘 정산 대기', glyph(Icons.hourglass_top, 0), kind: 'fg:#946200');
              add('아이콘 정산 승인됨', glyph(Icons.event_available, 0), kind: 'fg:#00796B');
            }
            if (sc == 'empty') add('빈 제목', nth(rich((p) => p == '알림이 없습니다'), 0), kind: 'empty');
            if (sc == 'error') {
              add('오류 중 빈 문구', nth(rich((p) => p == '알림이 없습니다'), 0), kind: 'record');
              add('오류 제목', nth(rich((p) => p == '알림을 불러오지 못했습니다'), 0), kind: 'empty');
              add('오류 부제', nth(rich((p) => p == '잠시 후 다시 시도해 주세요'), 0), kind: 'empty');
              final retry = nth(rich((p) => p == '다시 시도'), 0);
              add('다시 시도', retry, kind: 'outBtn', box: anc(retry, isBtn));
            }
            return xs;
          }

          void afterChecks(List<Map<String, Object?>> xs, String at) {
            if (!after) return;
            for (final x in xs) {
              if (x['present'] != true || x['visible'] != true) continue;
              final k = (x['kind'] as String?) ?? '';
              final cst = x['contrast'];
              final ok45 = cst is double && cst >= 4.5;
              need(x['didExceedMaxLines'] != true, '$at 말줄임/잘림 $x');
              final sb = x['sylBreaks'];
              if (sb is int && k != 'body') need(sb == 0, '$at 음절 끊김 $x');
              final h = x['boxH'] as double?;
              if (k == 'title' || k == 'value') {
                need(x['fg'] == '#21242D' && ok45, '$at 본문색 $x');
              } else if (k == 'detail' || k == 'body') {
                need(x['fg'] == '#60646F' && ok45, '$at 보조색 $x');
              } else if (k == 'hdrIcon') {
                need(x['fg'] == '#60646F', '$at 머리 아이콘 $x');
              } else if (k == 'closeIcon') {
                need(x['fg'] == '#60646F' && (h ?? 0) >= 48, '$at 닫기 $x');
              } else if (k == 'secBtn') {
                need(x['fg'] == '#60646F' && ok45 && (h ?? 0) >= 48, '$at 보조 행동 $x');
              } else if (k == 'priBtn') {
                need(x['fg'] == '#FFFFFF' && x['bg'] == '#3859E8' && ok45 && (h ?? 0) >= 48, '$at 주 행동 $x');
              } else if (k == 'outBtn') {
                need(ok45 && (h ?? 0) >= 48, '$at 다시 시도 $x');
              } else if (k == 'empty') {
                need(ok45, '$at 빈/오류 상태 $x');
              } else if (k.startsWith('pair:')) {
                final p = k.substring(5).split('/');
                need(x['fg'] == p[0] && x['bg'] == p[1] && ok45, '$at 배지 $x');
              } else if (k.startsWith('fg:')) {
                need(x['fg'] == k.substring(3) && cst is double && cst >= 3.0, '$at 의미색 $x');
                if (!(x['name'] as String).startsWith('아이콘')) need(ok45, '$at 의미색 글자 $x');
              } else if (k.startsWith('cfm:')) {
                need(x['fg'] == '#FFFFFF' && x['bg'] == k.substring(4) && ok45, '$at 확인 버튼 $x');
              }
            }
          }

          final shots = <Map<String, Object?>>[];
          final seen = <String>{};
          Future<void> snap(String suffix) async {
            final xs = measure();
            afterChecks(xs, suffix.isEmpty ? '첫 화면' : suffix);
            for (final x in xs) {
              if (x['present'] == true && x['visible'] == true) seen.add(x['name'] as String);
            }
            if (after && sc == 'error' && suffix.isEmpty) {
              need(rich((p) => p == '알림을 불러오지 못했습니다').evaluate().isNotEmpty, '오류 상태가 없다');
              need(rich((p) => p == '알림이 없습니다').evaluate().isEmpty, '오류를 빈 상태로 말한다');
            }
            nPng++;
            await vqCapture(t, key, 'D267-$phase-${c.id}_$sc$suffix', conditions: {
              'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
            });
            final sf = sfOf();
            shots.add({'shot': suffix.isEmpty ? 'top' : suffix, 'texts': xs,
              'pixels': sf == null ? null : r1(t.state<ScrollableState>(sf).position.pixels)});
          }

          await snap('');
          var atEnd = true;
          if (!sc.startsWith('c-') && sfOf() != null) {
            var k = 0;
            while (k < 30) {
              final sf = sfOf()!;
              final vp = t.getRect(sf);
              final pos = t.state<ScrollableState>(sf).position;
              if (pos.pixels >= pos.maxScrollExtent - 0.5) break;
              k++;
              nDrag++;
              await t.dragFrom(Offset(vp.left + 24, vp.top + vp.height * 0.6), Offset(0, -(vp.height * 0.5)));
              await frames(8);
              safe('drag $k 뒤');
              await snap('_d$k');
            }
            final pos = t.state<ScrollableState>(sfOf()!).position;
            atEnd = pos.pixels >= pos.maxScrollExtent - 0.5;
          }
          if (after) {
            need(atEnd, '끝 도달 실패');
            // 빈 단언 방지 — 이 장면에서 잰 이름(기록용 제외)은 한 번 이상 화면 안에서 보여야 한다.
            for (final x in shots.first['texts'] as List<Map<String, Object?>>) {
              final nm = x['name'] as String;
              if (x['kind'] == 'record') continue;
              need(seen.contains(nm), '한 번도 보이지 않음: $nm');
            }
          }
          _out('D267 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'overflow': overflow, 'atEnd': atEnd, 'shots': shots,
                'seen': seen.toList(), 'counts': {'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap}})}');
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D267-END ${jsonEncode({'pump': nPump, 'drag': nDrag, 'png': nPng, 'tap': nTap})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 6)));
}
