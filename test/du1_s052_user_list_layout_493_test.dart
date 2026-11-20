// ignore_for_file: depend_on_referenced_packages
// [DU493 · 자체 판정 셀 · 표시만] DU-S052 전체 사용자 목록(슈퍼관리자) — 카드 배치(이름 줄 · 상태 칩 줄).
//   before = 현재 A(all_users_screen 26f8f1ae · DU492 후보 · B 기존 넘침 1 · 이름 세로 쌓임) / strict = 후보(좁으면 칩을 이름 아래로 · 칩 줄 Wrap).
//   harness · fixture 는 DU492 시험(b983a789)과 같다. 앱 테마(RoleTheme.superAdminTheme).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du493-tb/DU_BEFORE_OBSERVE=493 · TA after/du493-ta/없음.
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
import 'package:ALfit/theme/role_theme.dart';
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

/// 네 사람 — 역할 칩 셋(지원자 success · 사업장관리자 purple · 슈퍼관리자 error) · 미니 칩 셋(블랙리스트 error · 제재중 warning · 승인대기 info).
List<Map<String, dynamic>> _users() => [
      {'uid': 'u1', 'username': 'worker01', 'name': '김지원', 'email': 'u1@alfit.local', 'role': 'USER', 'createdAt': _ts(DateTime(2026, 1, 1)),
       'totalWorkDays': 12, 'noShowCount': 3, 'recentNoShowCount': 3, 'isBlacklisted': true, 'blacklistReason': '시험',
       'restrictedUntil': _ts(_auto), 'restrictionSource': 'auto', 'restrictionParts': {'auto': _ts(_auto)}},
      {'uid': 'u2', 'username': 'worker02', 'name': '이대기', 'email': 'u2@alfit.local', 'role': 'USER', 'createdAt': _ts(DateTime(2026, 2, 1)),
       'accountStatus': 'registration_pending'},
      {'uid': 'b1', 'username': 'boss01', 'name': '박사장', 'email': 'b1@alfit.local', 'role': 'BUSINESS_ADMIN', 'createdAt': _ts(DateTime(2026, 3, 1))},
      {'uid': 's1', 'username': 'ops01', 'name': '최운영', 'email': 's1@alfit.local', 'role': 'SUPER_ADMIN', 'createdAt': _ts(DateTime(2026, 4, 1))},
    ];

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f(double v) => v.toStringAsFixed(2);
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

/// 글자 줄 수 — 글자마다 선택 상자의 top 을 모아 서로 다른 줄을 센다(DU436 _lines 단순판 · TextPainter 전용 API 없음).
int _lineCount(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  for (var i = 0; i < s.length; i++) {
    final boxes = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (boxes.isEmpty) continue;
    if (!tops.any((x) => (x - boxes.first.top).abs() < 0.5)) tops.add(boxes.first.top);
  }
  return tops.length;
}

/// 놓인 면 — 조상의 칠한 색을 불투명 층까지 모아 합성한다(DU476 과 같다). 면이 없으면 흰 바탕(MaterialApp 기본 Scaffold)으로 본다.

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '493';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du493-tb' && _env['DU_BEFORE_OBSERVE'] == '493') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du493-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S052UK-${v.id}-USERS 전체 사용자 목록 — 카드 배치', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S052UK-${v.id}-USERS';
        final mode = _before ? 'before' : 'strict';
        _out('D493 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
              theme: RoleTheme.superAdminTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: AllUsersScreen(reads: AllUsersReads(allUsersRaw: () async => _users())),
            ),
          ),
        ));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 100));
        }
        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        final firstName = rt((p) => p == '김지원');
        must('첫 카드 이름 1', firstName.evaluate().length == 1, '개수 ${firstName.evaluate().length}');
        final scroll = find.ancestor(of: firstName, matching: find.byType(Scrollable, skipOffstage: false)).first;
        var shots = 0;
        _out('D493 $tok shot 1list ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1list', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'USERS',
          'state': 'user-list-layout',
        });
        shots++;
        // 한 카드 — 이름 줄 수 · 역할 칩이 이름과 같은 줄인지(칩 top < 이름 bottom) 아래인지. 값은 닿은 즉시.
        Future<(int, String)> card(String what, String name, String role) async {
          final nameF = rt((p) => p == name);
          await t.scrollUntilVisible(nameF, 120, scrollable: scroll, maxScrolls: 40);
          await t.pump(const Duration(milliseconds: 50));
          final cardF = find.ancestor(of: nameF, matching: find.byType(Card, skipOffstage: false));
          must('$what 카드 1', cardF.evaluate().length == 1, '개수 ${cardF.evaluate().length}');
          final roleF = find.descendant(of: cardF, matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == role, skipOffstage: false), skipOffstage: false);
          must('$what 역할 칩 1', roleF.evaluate().length == 1, '개수 ${roleF.evaluate().length}');
          final lines = _lineCount(t.renderObject(nameF) as RenderParagraph);
          final nr = t.getRect(nameF);
          final cr = t.getRect(roleF);
          return (lines, cr.top < nr.bottom - 0.5 ? 'row' : 'stack');
        }

        final nu = await card('김지원', '김지원', '지원자');
        _out('D493 $tok att nameu lines=${nu.$1} layout=${nu.$2}');
        // 김지원 카드의 근무일 글자 — Row 에서는 B 에서 폭이 눌렸다.
        final daysF = find.descendant(
            of: find.ancestor(of: rt((p) => p == '김지원'), matching: find.byType(Card, skipOffstage: false)),
            matching: find.byWidgetPredicate((w) => w is RichText && _plainOf(w) == '12일 근무', skipOffstage: false),
            skipOffstage: false);
        must('근무일 글자 1', daysF.evaluate().length == 1, '개수 ${daysF.evaluate().length}');
        final daysRp = t.renderObject(daysF) as RenderParagraph;
        final daysW = daysRp.size.width;
        final daysL = _lineCount(daysRp);
        final daysEx = daysRp.didExceedMaxLines;
        _out('D493 $tok att days w=${_f(daysW)} lines=$daysL ex=$daysEx');
        final np = await card('이대기', '이대기', '지원자');
        _out('D493 $tok att namep lines=${np.$1} layout=${np.$2}');
        final nb = await card('박사장', '박사장', '사업장관리자');
        _out('D493 $tok att nameb lines=${nb.$1} layout=${nb.$2}');
        final ns = await card('최운영', '최운영', '슈퍼관리자');
        _out('D493 $tok att names lines=${ns.$1} layout=${ns.$2}');
        _out('D493 $tok shot 2end ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_2end', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'USERS',
          'state': 'user-list-layout-end',
        });
        shots++;
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        final all = [nu, np, nb, ns];
        if (_before) {
          // 음성 기대(DU492 실측 · 코드 확정) — B: 칩 줄 Row 넘침 1 · '박사장' 여러 줄. W: 넘침 0 · 모두 한 줄. 두 보기 모두 칩은 이름 옆(Row).
          if (v.id == 'B') {
            must('before B 넘침 1(오른쪽 · Row)', overflows.length == 1 && overflows.every((o) => o.contains('on the right') && o.contains('@ Row')), overflows.join(' | '));
            must('before B 박사장 세로 쌓임 검출', nb.$1 > 1, 'lines ${nb.$1}');
          } else {
            must('before W 넘침 0', overflows.isEmpty, overflows.join(' | '));
            must('before W 이름 모두 한 줄', all.every((x) => x.$1 == 1), all.map((x) => x.$1).join(','));
          }
          must('before 칩은 이름 옆', all.every((x) => x.$2 == 'row'), all.map((x) => x.$2).join(','));
        } else {
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          must('strict 이름 모두 한 줄', all.every((x) => x.$1 == 1), all.map((x) => x.$1).join(','));
          final want = v.id == 'B' ? 'stack' : 'row';
          must('strict 칩 위치 W 옆 · B 아래', all.every((x) => x.$2 == want), all.map((x) => x.$2).join(','));
          must('strict 근무일 한 줄 · 폭 > 0 · 넘침 없음', daysL == 1 && daysW > 0 && !daysEx, '${_f(daysW)} $daysL $daysEx');
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D493 $tok done state=USERS mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
