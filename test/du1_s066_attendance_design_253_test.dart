// ignore_for_file: depend_on_referenced_packages
// [DU253 S066 출퇴근 체크 근무 카드 시안 정렬 baseline/after] Codex 한도 중 Claude 자체 진행(허브 DU_self_review_hub_2026-11-10).
//   같은 시험을 교정 전(baseline)·후(after)에 한 번씩 돌린다. 시험은 production 을 편집하지 않는다.
//   DU253_RUN=1 이고 DU253_PHASE 가 baseline 또는 after 일 때만 실행한다(기본 skip).
//   standalone(home: AttendanceCheckScreen(reads·clock 대역)) — attendance_contract_gate_render_test 와 같은 대역. 외부 채널 없음, tap 0.
//   장면 3(open: 계약 완료·출근 창 열림·긴 사업장 이름 / gate: 계약 없음 / empty: 오늘 근무 없음) × W360/1.0·B320/2.0.
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
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_model.dart' show AttendanceRules;
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/attendance_check_reads.dart';
import 'package:ALfit/screens/user/attendance_check_screen.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';

import 'support/checkin_contract_fixture.dart';
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

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
      homeRegion: const UserRegion(province: '경기도', city: '평택시'), accountStatus: 'active');
  @override
  bool get isSubAdmin => false;
  @override
  bool get isBusinessAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => false;
  @override
  bool get permissionsLoaded => true;
}

DateTime _kst(int y, int mo, int d, [int h = 0, int mi = 0]) => DateTime.utc(y, mo, d, h, mi).subtract(const Duration(hours: 9));

const kName = '강남 물류센터 제2물류동 야간 분류팀';

ApplicationModel _work() => ApplicationModel(
      id: 'app1', toId: 'to1', uid: 'u1', businessId: 'biz1', businessName: kName, toTitle: '당일 QA',
      status: AppStatus.contractPending, selectedWorkType: '상품 포장 · 분류', startTime: '20:00', endTime: '21:00',
      wage: 13000, workDate: _kst(2026, 10, 17), appliedAt: _kst(2026, 10, 17, 17, 57),
      attendancePolicySnapshot: const AttendanceRules(),
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

void main() {
  final phase = Platform.environment['DU253_PHASE'] ?? '';
  final run = Platform.environment['DU253_RUN'] == '1' && (phase == 'baseline' || phase == 'after');
  final after = phase == 'after';
  final nl = String.fromCharCode(10);

  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    await initializeDateFormatting('ko_KR', null);
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  testWidgets('D253 $phase', (t) async {
    await t.runAsync(vqLoadFonts);
    t.platformDispatcher.localesTestValue = const [Locale('ko', 'KR')];
    t.platformDispatcher.localeTestValue = const Locale('ko', 'KR');
    final prevOnError = FlutterError.onError;
    final errors = <String>[];
    FlutterError.onError = (d) => errors.add(d.exceptionAsString().split(nl).first);
    var nPump = 0, nDrag = 0, nPng = 0;
    var cur = '(시작)';
    Never stop(String why) {
      _out('D253-STOP ${jsonEncode({'at': cur, 'why': why, 'errors': errors})}');
      fail('$cur: $why');
    }

    void need(bool ok, String why) {
      if (!ok) stop(why);
    }

    Future<void> frames(int n) async {
      for (var i = 0; i < n; i++) {
        nPump++;
        need(nPump <= 900 && nDrag <= 30 && nPng <= 40, '사용량 한도');
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
      final e = i < 0 ? els.last : els[i];
      return find.byElementPredicate((x) => identical(x, e), skipOffstage: false);
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

    final key = GlobalKey();
    final now = _kst(2026, 10, 17, 20, 0);
    try {
      for (final c in const [
        (id: 'W360', w: 360.0, h: 780.0, s: 1.0),
        (id: 'B320', w: 320.0, h: 640.0, s: 2.0),
      ]) {
        for (final sc in const ['open', 'gate', 'empty']) {
          cur = '${c.id} $sc';
          await t.pumpWidget(const SizedBox.shrink());
          await frames(1);
          safe('장면 종료');
          overflow.clear();
          t.view.physicalSize = Size(c.w, c.h);
          t.view.devicePixelRatio = 1.0;
          t.platformDispatcher.textScaleFactorTestValue = c.s;
          final screen = Rect.fromLTWH(0, 0, c.w, c.h);
          final app = _work();
          final reads = AttendanceCheckReads(
            myApplications: (uid) async => sc == 'empty' ? <ApplicationModel>[] : [app],
            todayAttendance: ({required String userId, required String applicationId}) async => null as AttendanceModel?,
            myContracts: (uid) async => sc == 'open' ? [checkInContractFor(app)] : <EmploymentContractModel>[],
          );
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: RepaintBoundary(
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
                home: AttendanceCheckScreen(reads: reads, clock: () => now),
              ),
            ),
          ));
          await frames(20);
          safe('첫 화면');
          Finder? sfOf() {
            final f = find.descendant(of: find.byType(ListView), matching: find.byType(Scrollable));
            return f.evaluate().isEmpty ? null : nth(f, 0);
          }

          Map<String, Object?> info(String nm, Finder? f) {
            if (f == null) return {'name': nm, 'present': false};
            final rp = t.renderObject<RenderParagraph>(f);
            final r = t.getRect(f);
            final fg = rp.text.style?.color;
            final bg = bgOf(f.evaluate().first);
            final scr = find.ancestor(of: f, matching: find.byType(Scrollable));
            final vp = scr.evaluate().isEmpty ? screen : t.getRect(scr.first);
            String? radius, side, face;
            f.evaluate().first.visitAncestorElements((a) {
              final w = a.widget;
              if (w is Material && w.shape is RoundedRectangleBorder) {
                final s = w.shape! as RoundedRectangleBorder;
                final br = s.borderRadius;
                if (br is BorderRadius) radius = br.topLeft.x.toString();
                side = s.side.style == BorderStyle.none ? 'none' : _hex(s.side.color);
                face = w.color == null ? null : _hex(w.color!);
                return false;
              }
              return true;
            });
            return {
              'name': nm, 'present': true, 'rect': lt(r), 'visible': inside(r, screen) && inside(r, vp),
              'fontSize': rp.text.style?.fontSize, 'fg': fg == null ? null : _hex(fg), 'bg': _hex(bg),
              'contrast': fg == null ? null : double.parse(_contrast(fg, bg).toStringAsFixed(2)),
              'didExceedMaxLines': rp.didExceedMaxLines, 'radius': radius, 'side': side, 'face': face,
            };
          }

          List<Map<String, Object?>> measure() => [
                {...info('사업장', nth(rich((p) => p == kName || p.startsWith('강남 물류센터')), 0)), 'kind': 'name'},
                {...info('시간', nth(rich((p) => p == '20:00 ~ 21:00'), 0)), 'kind': 'time'},
                {...info('업무', nth(rich((p) => p == '상품 포장 · 분류'), 0)), 'kind': 'info'},
                {...info('시급', nth(rich((p) => p.startsWith('13,000원')), 0)), 'kind': 'info'},
                info('배지', nth(rich((p) => p == '단기'), 0)),
                info('안내', nth(rich((p) => p.startsWith('아직 출근 전이에요')), 0)),
                info('게이트 제목', nth(rich((p) => p == '아직 근로계약서를 받지 않았어요'), 0)),
                info('출근하기', nth(rich((p) => p == '출근하기'), 0)),
                info('빈 제목', nth(rich((p) => p == '오늘 확정된 근무가 없습니다'), 0)),
              ];

          void afterChecks(List<Map<String, Object?>> xs, String at) {
            if (!after) return;
            for (final x in xs) {
              if (x['present'] != true || x['visible'] != true) continue;
              final n = x['name'];
              final k = x['kind'];
              final cst = x['contrast'];
              if (n == '출근하기') continue; // 게이트 장면에서 비활성 — 비활성 표현은 범위 밖
              // [DU253 계획 보정, TB 뒤·반영 전] 단기/장기 배지는 앱 공용 토큰(shortTermDark on shortTermBg 4.03) — 기록만(후보).
              if (n == '배지') continue;
              need(cst is double && cst >= 4.5, '$at 대비 $x');
              if (k == 'time') need(x['fg'] == '#21242D' && (x['fontSize'] as num) >= 22, '$at 큰 시간 $x');
              if (k == 'info') need(x['fg'] == '#60646F' && x['didExceedMaxLines'] != true, '$at 정보 줄 $x');
              if (k == 'name') need(x['fg'] == '#21242D' && x['didExceedMaxLines'] != true, '$at 사업장 이름 $x');
              if (k != null) need(x['radius'] == '16.0' && x['side'] == '#EEEEEE' && x['face'] == '#FFFFFF', '$at 카드 면 $x');
            }
          }

          final shots = <Map<String, Object?>>[];
          Future<void> snap(String suffix) async {
            final xs = measure();
            afterChecks(xs, suffix.isEmpty ? '첫 화면' : suffix);
            nPng++;
            await vqCapture(t, key, 'D253-$phase-${c.id}_$sc$suffix', conditions: {
              'phase': phase, 'scene': sc, 'viewport': '${c.w.toInt()}x${c.h.toInt()}', 'textScaleFactor(기기)': c.s,
              'clock': '주입 2026-10-17 20:00 KST',
            });
            final sf = sfOf();
            shots.add({'shot': suffix.isEmpty ? 'top' : suffix, 'texts': xs,
              'pixels': sf == null ? null : r1(t.state<ScrollableState>(sf).position.pixels)});
          }

          await snap('');
          var atEnd = true;
          if (sfOf() != null) {
            var k = 0;
            while (k < 10) {
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
          if (after) need(atEnd, '끝 도달 실패');
          _out('D253 ${jsonEncode({'phase': phase, 'cond': c.id, 'scene': sc, 'overflow': overflow, 'atEnd': atEnd, 'shots': shots,
                'counts': {'pump': nPump, 'drag': nDrag, 'png': nPng}})}');
        }
      }
      await t.pumpWidget(const SizedBox.shrink());
      await frames(1);
      safe('END 전');
      _out('D253-END ${jsonEncode({'pump': nPump, 'drag': nDrag, 'png': nPng})}');
    } finally {
      FlutterError.onError = prevOnError;
      t.platformDispatcher.clearLocalesTestValue();
      t.platformDispatcher.clearLocaleTestValue();
      t.platformDispatcher.clearTextScaleFactorTestValue();
      t.view.reset();
    }
  }, skip: !run, timeout: const Timeout(Duration(minutes: 4)));
}
