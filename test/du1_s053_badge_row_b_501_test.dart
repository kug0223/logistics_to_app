// ignore_for_file: depend_on_referenced_packages
// [DU501 · 자체 판정 셀 · 표시만] DU-S053 배지 설정(슈퍼관리자) — 목록 행 B 조판: 비활성 이름 세로 쌓임 · 조건 설명 음절 끊김.
//   before = 현재 A(badge_settings_screen ffb9e299 · DU490 후보) / strict = 후보(제목 Wrap · 조건 설명 keepWords).
//   harness · 대역은 DU489 시험(4f93b1b0)과 같다. 낱말 경계는 DU436 _lines 를 옮겼다.
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du501-tb/DU_BEFORE_OBSERVE=501 · TA after/du501-ta/없음.
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
import 'package:ALfit/models/settings/trust_settings_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/badge_settings_screen.dart';
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

/// badge_settings_61_test 와 같은 슈퍼관리자 대역.
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

const _inactiveName = '야간 근무 휴면 배지';
final _inactive = BadgeModel(
  id: 'custom_off', name: _inactiveName, icon: '🌙', type: BadgeType.experience,
  conditionType: BadgeConditionType.workDays, conditionValue: 5, isActive: false, createdAt: DateTime(2026, 10, 1), order: 0);

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '501';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du501-tb' && _env['DU_BEFORE_OBSERVE'] == '501') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du501-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S053BR-${v.id}-LIST 배지 설정 — 목록 행 B 조판', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S053BR-${v.id}-LIST';
        final mode = _before ? 'before' : 'strict';
        _out('D501 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
              home: BadgeSettingsScreen(load: () async => [_inactive, ...BadgeModel.defaultBadges()]),
            ),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        final list = find.descendant(of: find.byType(BadgeSettingsScreen), matching: find.byType(Scrollable, skipOffstage: false), skipOffstage: false).first;
        var shots = 0;
        // 배지 행 하나 — 이름까지 내린 뒤 같은 상태에서 이름 줄 · 경계 · 조건 설명 줄 · 경계 · (비활성 칩 위치)를 잰다.
        Future<(int, bool, int, bool, String)> row(String what, String name, String condHead) async {
          final nameF = rt((p) => p == name);
          await t.scrollUntilVisible(nameF, 200, scrollable: list, maxScrolls: 60);
          for (var i = 0; i < 2; i++) {
            await t.pump(const Duration(milliseconds: 50));
          }
          must('$what 이름 1', nameF.evaluate().length == 1, '개수 ${nameF.evaluate().length}');
          final tile = find.ancestor(of: nameF, matching: find.byType(ListTile, skipOffstage: false)).first;
          final condF = find.descendant(of: tile, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w).startsWith(condHead), skipOffstage: false), skipOffstage: false);
          must('$what 조건 설명 1', condF.evaluate().length == 1, '개수 ${condF.evaluate().length}');
          final nj = _lines(t.renderObject(nameF) as RenderParagraph);
          final cj = _lines(t.renderObject(condF) as RenderParagraph);
          final chipF = find.descendant(of: tile, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '비활성', skipOffstage: false), skipOffstage: false);
          var pos = 'none';
          if (chipF.evaluate().length == 1) {
            final nr = t.getRect(nameF);
            final cr = t.getRect(chipF);
            pos = cr.top >= nr.bottom - 0.5 ? 'below' : (cr.left >= nr.right - 0.5 ? 'right' : 'other');
          }
          return (nj.lines.length, nj.ok, cj.lines.length, cj.ok, pos);
        }

        final bz = await row('브론즈', '브론즈', '신뢰도');
        _out('D501 $tok att bronze n=${bz.$1} ok=${bz.$2} cn=${bz.$3} cok=${bz.$4}');
        _out('D501 $tok shot 1trust ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1trust', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'LIST',
          'state': 'badge-row-trust',
        });
        shots++;
        final ia = await row('비활성 배지', _inactiveName, '총 근무');
        _out('D501 $tok att inactive n=${ia.$1} ok=${ia.$2} cn=${ia.$3} cok=${ia.$4} chip=${ia.$5}');
        _out('D501 $tok shot 2inactive ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_2inactive', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'LIST',
          'state': 'badge-row-inactive',
        });
        shots++;
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        if (_before) {
          // 음성 기대(DU489 · DU490 B 합성) — B: 비활성 이름 세로 쌓임 · 브론즈 조건 설명 '이/상'. 칩은 이름 오른쪽(Row).
          must('before 칩 이름 오른쪽', ia.$5 == 'right', ia.$5);
          if (v.id == 'B') {
            must('before B 비활성 이름 쌓임 검출', ia.$1 > 2 && !ia.$2, 'n ${ia.$1} ok ${ia.$2}');
            must('before B 조건 설명 음절 끊김 검출', !bz.$4, 'cok ${bz.$4}');
          }
        } else {
          must('strict 이름 낱말 경계', bz.$2 && ia.$2, '${bz.$2} ${ia.$2}');
          must('strict 조건 설명 낱말 경계', bz.$4 && ia.$4, '${bz.$4} ${ia.$4}');
          must('strict 비활성 이름 2줄 이하', ia.$1 <= 2, 'n ${ia.$1}');
          must('strict 칩은 옆 또는 아래', ia.$5 == 'right' || ia.$5 == 'below', ia.$5);
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D501 $tok done state=LIST mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
