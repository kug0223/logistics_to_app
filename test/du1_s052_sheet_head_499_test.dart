// ignore_for_file: depend_on_referenced_packages
// [DU499 · 자체 판정 셀 · 표시만] DU-O107 사용자 상세 시트(S052) — 머리 B 배치: 부제 '@아이디 · 역할' 의 '·' 줄 머리 · 역할 칩 위치.
//   before = 현재 A(all_users_screen 1408e842 · DU498 후보) / strict = 후보(좁으면 칩을 부제 아래로 · 부제 phrases).
//   harness · 대역은 DU498 시험(a3bcbfb3)과 같다. 위치 비교는 한 상태에서만 잰다(DU395 · DU498 교훈).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du499-tb/DU_BEFORE_OBSERVE=499 · TA after/du499-ta/없음.
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/all_users_reads.dart';
import 'package:ALfit/screens/super_admin/all_users_screen.dart';
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

/// RR57 과 같은 슈퍼관리자 대역.
class _Super extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'sa1', username: 'sa1', name: '운영자', email: 'sa@alfit.local',
        role: UserRole.SUPER_ADMIN, createdAt: DateTime(2026, 1, 1));
  @override
  bool get isSuperAdmin => true;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
}

// callable 응답 모양 그대로(RR57) — Timestamp 는 {_seconds, _nanoseconds}.
Map<String, int> _ts(DateTime t) => {'_seconds': t.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};
final _auto = DateTime.fromMillisecondsSinceEpoch((DateTime.now().add(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000) * 1000);

/// 지원자 1명 — 통계 색 다섯(success 근무 · error 노쇼 · grey400 지각 0 · purple 평점 · info 리뷰) · 노쇼 자동 제한(warning 상태 카드).
Map<String, dynamic> _worker() => {
      'uid': 'w1', 'username': 'worker01', 'name': '박근로', 'email': 'worker01@alfit.local', 'role': 'USER',
      'createdAt': _ts(DateTime(2026, 1, 1)),
      'totalWorkDays': 12, 'averageRating': 4.5, 'reviewCount': 3, 'recentLateCount': 0,
      'noShowCount': 3, 'recentNoShowCount': 3,
      'restrictedUntil': _ts(_auto), 'restrictionSource': 'auto', 'restrictionParts': {'auto': _ts(_auto)},
    };

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

final String _zwsp = String.fromCharCode(0x200B);
final String _wj = String.fromCharCode(0x2060);
final String _nbsp = String.fromCharCode(0x00A0);
bool _visible(String ch) => ch.trim().isNotEmpty && ch != _zwsp && ch != _wj && ch != _nbsp;

({List<String> lines, bool ok}) _lines(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  final lineOf = List<int>.filled(s.length, -1);
  var missing = 0;
  for (var i = 0; i < s.length; i++) {
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.isEmpty) {
      if (_visible(s[i])) missing++;
      continue;
    }
    var k = tops.indexWhere((x) => (x - boxes.first.top).abs() < 0.5);
    if (k < 0) {
      tops.add(boxes.first.top);
      k = tops.length - 1;
    }
    lineOf[i] = k;
  }
  if (tops.isEmpty) return (lines: const <String>[], ok: false);
  final order = List<int>.generate(tops.length, (i) => i)..sort((a, b) => tops[a].compareTo(tops[b]));
  final rank = List<int>.filled(tops.length, 0);
  for (var r = 0; r < order.length; r++) {
    rank[order[r]] = r;
  }
  final buf = List<StringBuffer>.generate(tops.length, (_) => StringBuffer());
  var ok = true;
  var prev = -1;
  var cur = 0;
  for (var i = 0; i < s.length; i++) {
    if (lineOf[i] >= 0) {
      final ln = rank[lineOf[i]];
      if (prev >= 0 && ln != prev) {
        final b = i > 0 ? s[i - 1] : '';
        if (!(b == ' ' || b == _zwsp || b == '\n' || s[i] == ' ' || s[i] == '\n')) ok = false;
      }
      prev = ln;
      cur = ln;
    }
    buf[cur].write(s[i]);
  }
  return (lines: [for (final b in buf) TextLayout.plain(b.toString()).trim()], ok: ok && missing == 0);
}

/// 놓인 면 — 조상의 칠한 색을 불투명 층까지 모아 합성한다(DU476 과 같다). 면이 없으면 흰 바탕(MaterialApp 기본 Scaffold)으로 본다.

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '499';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du499-tb' && _env['DU_BEFORE_OBSERVE'] == '499') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du499-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S052UH-${v.id}-SHEET 사용자 상세 시트 — 머리 B 배치', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S052UH-${v.id}-SHEET';
        final mode = _before ? 'before' : 'strict';
        _out('D499 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        final overflows = <String>[];
        final fwErrors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            final full = d.toString();
            final k = full.indexOf('The relevant error-causing widget was');
            final loc = k < 0 ? '' : full.substring(k).split('\n').skip(1).where((l) => l.trim().isNotEmpty).take(2).map((l) => l.trim()).join(' ');
            overflows.add('${m.split('\n').first} @ $loc');
          } else {
            fwErrors.add(m.split('\n').first);
            prev?.call(d);
          }
        };
        addTearDown(() => FlutterError.onError = prev);
        t.view.physicalSize = Size(v.w, v.h);
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        void must(String k, bool ok, [String why = '']) => expect(ok, isTrue, reason: '$tok $k $why');

        final key = GlobalKey();
        await t.pumpWidget(RepaintBoundary(
          key: key,
          child: ChangeNotifierProvider<UserProvider>(
            create: (_) => _Super(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: AllUsersScreen(reads: AllUsersReads(allUsersRaw: () async => [_worker()])),
            ),
          ),
        ));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        // 목록 행 이름을 눌러 상세 시트를 연다(RR57 과 같은 경로).
        final nameF = find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '박근로');
        must('목록 이름 1', nameF.evaluate().length == 1, '개수 ${nameF.evaluate().length}');
        await t.tap(nameF);
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        final sheet = find.byType(BottomSheet);
        must('상세 시트 1', sheet.evaluate().length == 1, '개수 ${sheet.evaluate().length}');
        Finder rt(bool Function(String p) p) => find.descendant(
            of: sheet, matching: find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false), skipOffstage: false);
        final scroll = find.descendant(of: sheet, matching: find.byType(Scrollable, skipOffstage: false), skipOffstage: false).first;
        var shots = 0;
        _out('D499 $tok shot 1head ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1head', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'SHEET',
          'state': 'user-detail-head',
        });
        shots++;
        // 한 글자 — 시트 안 정확히 1개(차례로 내려 닿게 한다) · 글자색 · 놓인 면 · 대비.
        // 글자 하나 — 시트 안 정확히 1개 · 닿게 내린 뒤 · 줄 수 · 낱말 경계 · '·' 줄 머리 · 사각형.
        Future<(int, bool, bool, Rect)> lay(String what, bool Function(String p) p) async {
          final f = rt(p);
          await t.scrollUntilVisible(f, 120, scrollable: scroll, maxScrolls: 40);
          await t.pump(const Duration(milliseconds: 50));
          must('$what 1', f.evaluate().length == 1, '개수 ${f.evaluate().length}');
          final j = _lines(t.renderObject(f) as RenderParagraph);
          return (j.lines.length, j.ok, j.lines.any((l) => l.startsWith('·')), t.getRect(f));
        }

        final hd = await lay('머리 부제', (p) => p == '@worker01 · 지원자');
        final nm = await lay('머리 이름', (p) => p == '박근로');
        // 역할 칩 — 부제와 같은 상태에서 잰다(머리는 스크롤 밖 고정 영역).
        final chipF = rt((p) => p == '지원자');
        must('역할 칩 1', chipF.evaluate().length == 1, '개수 ${chipF.evaluate().length}');
        final cr = t.getRect(chipF);
        final hr = t.getRect(rt((p) => p == '@worker01 · 지원자'));
        final pos = cr.top >= hr.bottom - 0.5 ? 'below' : (cr.left >= hr.right - 0.5 ? 'right' : 'other');
        _out('D499 $tok att head n=${hd.$1} ok=${hd.$2} lead=${hd.$3} name=${nm.$1} chip=$pos');
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        if (_before) {
          // 음성 기대(DU498 TB · 진단 실측) — 두 보기 모두 칩은 오른쪽. B 는 부제가 '·' 줄 머리.
          must('before 칩 오른쪽', pos == 'right', pos);
          if (v.id == 'B') {
            must('before B 부제 · 줄 머리 검출', hd.$3, 'lead ${hd.$3}');
          }
        } else {
          must('strict 부제 · 줄 머리 없음 · 경계', !hd.$3 && hd.$2, 'lead ${hd.$3} ok ${hd.$2}');
          must('strict 이름 한 줄', nm.$1 == 1, 'name ${nm.$1}');
          must('strict 칩 W 오른쪽 · B 아래', pos == (v.id == 'B' ? 'below' : 'right'), pos);
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D499 $tok done state=SHEET mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
