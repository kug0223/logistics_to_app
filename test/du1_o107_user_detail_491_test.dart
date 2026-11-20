// ignore_for_file: depend_on_referenced_packages
// [DU491 · 자체 판정 셀 · 표시만] DU-O107 사용자 상세 시트(슈퍼관리자 · all_users_screen) — 글자 대비.
//   before = 현재 A(all_users_screen 681e96fe) / strict = 후보(같은 색 면 위 글자 → 진한 짝 · grey500/600 → 보조색).
//   harness 는 DU490 시험(4ecfd2ad)과 같고, 시트는 RR57 과 같은 경로(AllUsersReads 주입 → 이름 탭)로 연다.
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du491-tb/DU_BEFORE_OBSERVE=491 · TA after/du491-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/super_admin/all_users_reads.dart';
import 'package:ALfit/screens/super_admin/all_users_screen.dart';
import 'package:ALfit/theme/app_colors.dart';
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

String _f(double v) => v.toStringAsFixed(2);
String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textPrimary': AppColors.textPrimary, 'textSecondary': AppColors.textSecondary,
  'grey400': AppColors.grey400, 'grey500': AppColors.grey500, 'grey600': AppColors.grey600,
  'success': AppColors.success, 'successDark': AppColors.successDark, 'error': AppColors.error, 'errorDark': AppColors.errorDark,
  'warning': AppColors.warning, 'warningDark': AppColors.warningDark, 'info': AppColors.info, 'purple': AppColors.purple,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

/// 놓인 면 — 조상의 칠한 색을 불투명 층까지 모아 합성한다(DU476 과 같다). 면이 없으면 흰 바탕(MaterialApp 기본 Scaffold)으로 본다.
Color? _bgOf(Element e) {
  final layers = <Color>[];
  e.visitAncestorElements((x) {
    final w = x.widget;
    Color? c;
    if (w is Container) {
      c = w.color ?? (w.decoration is BoxDecoration ? (w.decoration! as BoxDecoration).color : null);
    } else if (w is ColoredBox) {
      c = w.color;
    } else if (w is Material && w.type != MaterialType.transparency) {
      c = w.color;
    }
    // preflight v16 — 투명(알파 0) Material 은 칠한 면이 아니다.
    if (c != null && c.a > 0) {
      layers.add(c);
      if (c.a >= 1) return false;
    }
    return true;
  });
  if (layers.isEmpty) return null;
  var out = layers.last;
  for (final c in layers.reversed.skip(1)) {
    out = Color.alphaBlend(c, out);
  }
  return out;
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '491';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du491-tb' && _env['DU_BEFORE_OBSERVE'] == '491') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du491-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
    testWidgets('S052UD-${v.id}-SHEET 사용자 상세 시트 — 글자 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S052UD-${v.id}-SHEET';
        final mode = _before ? 'before' : 'strict';
        _out('D491 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
        _out('D491 $tok shot 1head ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_1head', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'SHEET',
          'state': 'user-detail-head',
        });
        shots++;
        // 한 글자 — 시트 안 정확히 1개(차례로 내려 닿게 한다) · 글자색 · 놓인 면 · 대비.
        Future<(Color?, Color?, double)> meas(String what, bool Function(String p) p) async {
          final f = rt(p);
          await t.scrollUntilVisible(f, 120, scrollable: scroll, maxScrolls: 40);
          await t.pump(const Duration(milliseconds: 50));
          must('$what 1', f.evaluate().length == 1, '개수 ${f.evaluate().length}');
          final c = (t.widget(f) as RichText).text.style?.color;
          final bg = _bgOf(f.evaluate().first);
          return (c, bg, _cr(c, bg));
        }

        final handle = await meas('머리 부제', (p) => p == '@worker01 · 지원자');
        _out('D491 $tok att handle text=${_tok(handle.$1)} bg=${_tok(handle.$2)} cr=${_f(handle.$3)}');
        final chip = await meas('역할 칩', (p) => p == '지원자');
        _out('D491 $tok att chip text=${_tok(chip.$1)} bg=${_tok(chip.$2)} cr=${_f(chip.$3)}');
        final label = await meas('정보 라벨', (p) => p == '연락처');
        _out('D491 $tok att label text=${_tok(label.$1)} bg=${_tok(label.$2)} cr=${_f(label.$3)}');
        final work = await meas('근무 값', (p) => p == '12일');
        final workL = await meas('근무 라벨', (p) => p == '총 근무');
        _out('D491 $tok att work text=${_tok(work.$1)} bg=${_tok(work.$2)} cr=${_f(work.$3)} ltext=${_tok(workL.$1)} lcr=${_f(workL.$3)}');
        final noshow = await meas('노쇼 값', (p) => p == '3회');
        final noshowL = await meas('노쇼 라벨', (p) => p == '노쇼');
        _out('D491 $tok att noshow text=${_tok(noshow.$1)} bg=${_tok(noshow.$2)} cr=${_f(noshow.$3)} ltext=${_tok(noshowL.$1)} lcr=${_f(noshowL.$3)}');
        final lateV = await meas('지각 값', (p) => p == '0회');
        final lateL = await meas('지각 라벨', (p) => p == '지각(90일)');
        _out('D491 $tok att late text=${_tok(lateV.$1)} bg=${_tok(lateV.$2)} cr=${_f(lateV.$3)} ltext=${_tok(lateL.$1)} lcr=${_f(lateL.$3)}');
        final rate = await meas('평점 값', (p) => p == '4.5점');
        final rateL = await meas('평점 라벨', (p) => p == '평점');
        _out('D491 $tok att rate text=${_tok(rate.$1)} bg=${_tok(rate.$2)} cr=${_f(rate.$3)} ltext=${_tok(rateL.$1)} lcr=${_f(rateL.$3)}');
        final review = await meas('리뷰 값', (p) => p == '3건');
        final reviewL = await meas('리뷰 라벨', (p) => p == '리뷰');
        _out('D491 $tok att review text=${_tok(review.$1)} bg=${_tok(review.$2)} cr=${_f(review.$3)} ltext=${_tok(reviewL.$1)} lcr=${_f(reviewL.$3)}');
        final status = await meas('상태 제목', (p) => p == '이용 제한 중');
        final statusD = await meas('상태 설명', (p) => p.startsWith('노쇼 자동 제한'));
        _out('D491 $tok att status text=${_tok(status.$1)} bg=${_tok(status.$2)} cr=${_f(status.$3)} dtext=${_tok(statusD.$1)} dcr=${_f(statusD.$3)}');
        // 상태 카드 전체가 보이게 — 설명까지 내려가면 B 에서 제목이 위로 잘린다(진단 PNG). 캡처 위치만 바꾼다.
        final cards = find.ancestor(
            of: rt((p) => p == '이용 제한 중'),
            matching: find.byWidgetPredicate((w) => w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).border != null,
                skipOffstage: false));
        if (cards.evaluate().isNotEmpty) {
          await t.ensureVisible(cards.first);
          await t.pump(const Duration(milliseconds: 50));
        }
        _out('D491 $tok shot 2status ovf=${overflows.length}');
        await vqCapture(t, key, '${tok}_2status', conditions: {
          'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'SHEET',
          'state': 'user-detail-status',
        });
        shots++;
        // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
        FlutterError.onError = prev;
        final vals = [work, noshow, lateV, rate, review];
        final labs = [workL, noshowL, lateL, rateL, reviewL];
        if (_before) {
          // 음성 기대(코드 확정) — 같은 색 면 위 같은 색 · 흰 면 grey500. purple 평점은 이미 넘는다.
          final want = [AppColors.success, AppColors.error, AppColors.grey400, AppColors.purple, AppColors.info];
          final valsOk = [for (var i = 0; i < 5; i++) vals[i].$1 == want[i] && (i == 3 ? vals[i].$3 >= 4.5 : vals[i].$3 < 4.5)].every((x) => x);
          must('before 통계 값 = 같은 색 · 미달 검출(평점 제외)', valsOk, vals.map((x) => '${_tok(x.$1)}/${_f(x.$3)}').join(','));
          must('before 통계 라벨 grey500', labs.every((x) => x.$1 == AppColors.grey500 && x.$3 < 4.5), labs.map((x) => _f(x.$3)).join(','));
          must('before 머리 부제 grey500 미달', handle.$1 == AppColors.grey500 && handle.$3 < 4.5, _f(handle.$3));
          must('before 역할 칩 success 미달', chip.$1 == AppColors.success && chip.$3 < 4.5, _f(chip.$3));
          must('before 정보 라벨 grey500 미달', label.$1 == AppColors.grey500 && label.$3 < 4.5, _f(label.$3));
          must('before 상태 제목 warning 미달', status.$1 == AppColors.warning && status.$3 < 4.5, _f(status.$3));
          must('before 상태 설명 grey600', statusD.$1 == AppColors.grey600, _tok(statusD.$1));
        } else {
          final want = [AppColors.successDark, AppColors.errorDark, AppColors.textSecondary, AppColors.purple, AppColors.textPrimary];
          final valsOk = [for (var i = 0; i < 5; i++) vals[i].$1 == want[i] && vals[i].$3 >= 4.5].every((x) => x);
          must('strict 통계 값 진한 짝 · 대비 ≥ 4.5', valsOk, vals.map((x) => '${_tok(x.$1)}/${_f(x.$3)}').join(','));
          must('strict 통계 라벨 textSecondary ≥ 4.5', labs.every((x) => x.$1 == AppColors.textSecondary && x.$3 >= 4.5), labs.map((x) => _f(x.$3)).join(','));
          must('strict 머리 부제 textSecondary ≥ 4.5', handle.$1 == AppColors.textSecondary && handle.$3 >= 4.5, _f(handle.$3));
          must('strict 역할 칩 successDark ≥ 4.5', chip.$1 == AppColors.successDark && chip.$3 >= 4.5, _f(chip.$3));
          must('strict 정보 라벨 textSecondary ≥ 4.5', label.$1 == AppColors.textSecondary && label.$3 >= 4.5, _f(label.$3));
          must('strict 상태 제목 warningDark ≥ 4.5', status.$1 == AppColors.warningDark && status.$3 >= 4.5, _f(status.$3));
          must('strict 상태 설명 textSecondary ≥ 4.5', statusD.$1 == AppColors.textSecondary && statusD.$3 >= 4.5, _f(statusD.$3));
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D491 $tok done state=SHEET mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
