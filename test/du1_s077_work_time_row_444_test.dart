// ignore_for_file: depend_on_referenced_packages
// [DU444 · 자체 판정 셀 · 표시만] DU-S077 일자리 탭 공고 카드(계약 · 펼침) — 업무 행 시각 줄 B 넘침(DU443 진단에서 찾은 기존 결함).
//   before = 현재 A(user_to_card bc66d70f) / strict = 후보(66a1abf2). harness 는 DU443 시험(2cbb067f)과 같고 측정만 바꿨다. 진입은 user_to_card_expired_relation_test(UTC-3/4)와 같은 seam
//   (UserTOCard 직접 · workDetails 주입 · selectedNotifier = to.id 로 펼침). 시각 줄 줄 수 · '~' 뒤 줄바꿈 · 색 · 대비 · 아이콘 첫 줄 · 넘침만 본다.
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du444-tb/DU_BEFORE_OBSERVE=444 · TA after/du444-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/user/cards/user_to_card.dart';

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

class _UserDouble extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER, accountStatus: 'active');
}

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

// 업무 5개 — 이름 · 시작 시각이 서로 달라 _appForWork(업무명 + 시작 시각)가 하나씩만 잇는다.
const _works = [
  WorkDetailData(wdId: 'wdA', workType: '분류', wage: 12000, requiredCount: 3, startTime: '09:00', endTime: '13:00'),
  WorkDetailData(wdId: 'wdB', workType: '상차', wage: 13000, requiredCount: 2, startTime: '10:00', endTime: '14:00', isEmergencyOpen: true),
  WorkDetailData(wdId: 'wdC', workType: '하차', wage: 12500, requiredCount: 1, startTime: '11:00', endTime: '15:00', runtimeFull: true),
  WorkDetailData(wdId: 'wdD', workType: '포장', wage: 11000, requiredCount: 2, startTime: '12:00', endTime: '16:00'),
  WorkDetailData(wdId: 'wdE', workType: '검수', wage: 14000, requiredCount: 1, startTime: '13:00', endTime: '17:00'),
];

final _to = TOModel(
  id: 'L', businessId: 'biz1', businessName: '골든패스 테스트 사업장', businessCity: '평택시', type: 'contract',
  title: '물류센터 장기 근무', creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
  workDetails: _works, slotDateKeys: const [], totalSlots: 0,
  totalRequired: 9, totalConfirmed: 0, totalPending: 0, isPublished: true, publishMode: 'immediate',
  rangeStart: _day(2), rangeEnd: _day(30), createdAt: _day(-3), statusUpdatedAt: _day(-3),
);

ApplicationModel _app(WorkDetailData w, String status) => ApplicationModel(
      id: 'L_slot_${w.wdId}_u1_$status', toId: 'L', slotId: null, wdId: w.wdId, businessId: 'biz1',
      businessName: '골든패스 테스트 사업장', toTitle: '물류센터 장기 근무', uid: 'u1', applicantName: '김근로', status: status,
      appliedAt: _day(-1), workDate: _day(2), selectedWorkType: w.workType, startTime: w.startTime, endTime: w.endTime,
      wage: w.wage, wageType: 'hourly', applicationType: AppType.longTerm,
    );

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '444';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du444-tb' && _env['DU_BEFORE_OBSERVE'] == '444') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du444-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textSecondary': AppColors.textSecondary, 'textTertiary': AppColors.textTertiary,
  'success': AppColors.success, 'successBg': AppColors.successBg, 'successDark': AppColors.successDark,
  'info': AppColors.info, 'infoBg': AppColors.infoBg, 'infoDark': AppColors.infoDark, 'infoDeep': AppColors.infoDeep,
  'error': AppColors.error, 'errorBg': AppColors.errorBg, 'errorDark': AppColors.errorDark,
  'grey50': AppColors.grey50, 'grey100': AppColors.grey100, 'grey400': AppColors.grey400,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

// 업무 행 5개(이름 → 키).
const _rows = [
  (key: 'open', work: '분류'),
  (key: 'urgent', work: '상차'),
  (key: 'full', work: '하차'),
  (key: 'pending', work: '포장'),
  (key: 'confirmed', work: '검수'),
];

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S077WT-${v.id}-WORK 일자리 공고 카드(계약 · 펼침) — 업무 행 시각 줄 넘침 0 · ~ 뒤 줄바꿈 · 글자 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S077WT-${v.id}-WORK';
        final mode = _before ? 'before' : 'strict';
        _out('D444 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        final overflows = <String>[];
        final fwErrors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            overflows.add(m.split('\n').first);
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
          child: ChangeNotifierProvider<UserProvider>.value(
            value: _UserDouble(),
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: RoleTheme.workerTheme,
              builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
              home: Scaffold(
                backgroundColor: AppColors.background,
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: UserTOCard(
                    to: _to,
                    myApplications: [_app(_works[3], AppStatus.pending), _app(_works[4], AppStatus.confirmed)],
                    onApplySuccess: () {},
                    workDetails: _works,
                    selectedNotifier: ValueNotifier<String?>('L'),
                  ),
                ),
              ),
            ),
          ),
        ));
        for (var i = 0; i < 8; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        var shots = 0;
        Future<void> shot(String sub, String state) async {
          _out('D444 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'WORK',
            'state': state,
          });
          shots++;
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        await shot('1top', 'card-expanded');

        // ── 업무 행 시각 줄(값은 즉시) — 행 상자 = 업무명의 첫 '테두리 있는' 조상 Container 중 시각 글을 함께 품은 것 ──
        final timeRe = RegExp(r'^\d\d:\d\d ?~ ?\d\d:\d\d$');
        final got = <String, ({int lines, bool breakOk, String first, String color, String rowBg, double cr, double dFirst})>{};
        for (final r in _rows) {
          final rowsFound = <Element>[];
          for (final e in rt((p) => p == r.work).evaluate()) {
            Element? box;
            e.visitAncestorElements((a) {
              final w = a.widget;
              if (w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).border != null) {
                box = a;
                return false;
              }
              return true;
            });
            final b = box;
            if (b == null) continue;
            final has = find
                .descendant(of: find.byElementPredicate((x) => identical(x, b), skipOffstage: false), matching: rt((p) => timeRe.hasMatch(p)), skipOffstage: false)
                .evaluate()
                .length;
            if (has == 1 && !rowsFound.any((x) => identical(x, b))) rowsFound.add(b);
          }
          if (rowsFound.length != 1) {
            continue;
          }
          final row = rowsFound.single;
          final rowBg = (row.widget as Container).decoration is BoxDecoration ? ((row.widget as Container).decoration! as BoxDecoration).color : null;
          final tF = find.descendant(
              of: find.byElementPredicate((x) => identical(x, row), skipOffstage: false), matching: rt((p) => timeRe.hasMatch(p)), skipOffstage: false);
          final rp = t.renderObject(tF) as RenderParagraph;
          final s = rp.text.toPlainText(includeSemanticsLabels: false);
          // 줄 수 · 첫 줄 글 — 글자마다 상자 위 끝으로 줄을 가른다(이 SDK 의 RenderParagraph 에는 줄 측정 API 가 없다 · 진단 1 컴파일 실패).
          final tops = <double>[];
          final firstBuf = StringBuffer();
          double? top0;
          for (var i = 0; i < s.length; i++) {
            final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
            if (bx.isEmpty) continue;
            final tp = bx.first.top;
            if (!tops.any((x) => (x - tp).abs() < 0.5)) tops.add(tp);
            top0 ??= tp;
            if ((tp - top0).abs() < 0.5) firstBuf.write(s[i]);
          }
          final lines = tops.length;
          final first = TextLayout.plain(firstBuf.toString()).trim();
          final breakOk = lines == 1 || first.endsWith('~');
          final color = (t.widget(tF) as RichText).text.style?.color;
          final cr = _cr(color, rowBg);
          final iF = find.descendant(
              of: find.byElementPredicate((x) => identical(x, row), skipOffstage: false), matching: find.byIcon(Icons.access_time, skipOffstage: false), skipOffstage: false);
          var dFirst = double.nan;
          if (iF.evaluate().length == 1) {
            final tr = t.getRect(tF);
            final b0 = rp.getBoxesForSelection(const TextSelection(baseOffset: 0, extentOffset: 1)).first;
            dFirst = t.getRect(iF).center.dy - (tr.top + (b0.top + b0.bottom) / 2);
          }
          got[r.key] = (lines: lines, breakOk: breakOk, first: first.replaceAll(' ', '_'), color: _tok(color), rowBg: _tok(rowBg), cr: cr, dFirst: dFirst);
        }
        // 줄 이름 · 키는 글자 그대로 — cell lines 대조(preflight)가 보간된 이름 · 키를 읽지 못한다. 못 찾은 행은 found=false · 값 null.
        _out('D444 $tok att open found=${got.containsKey('open')} lines=${got['open']?.lines} breakOk=${got['open']?.breakOk} first=${got['open']?.first} color=${got['open']?.color} '
            'rowBg=${got['open']?.rowBg} cr=${_f(got['open']?.cr ?? double.nan)} dFirst=${_f(got['open']?.dFirst ?? double.nan)}');
        _out('D444 $tok att urgent found=${got.containsKey('urgent')} lines=${got['urgent']?.lines} breakOk=${got['urgent']?.breakOk} first=${got['urgent']?.first} color=${got['urgent']?.color} '
            'rowBg=${got['urgent']?.rowBg} cr=${_f(got['urgent']?.cr ?? double.nan)} dFirst=${_f(got['urgent']?.dFirst ?? double.nan)}');
        _out('D444 $tok att full found=${got.containsKey('full')} lines=${got['full']?.lines} breakOk=${got['full']?.breakOk} first=${got['full']?.first} color=${got['full']?.color} '
            'rowBg=${got['full']?.rowBg} cr=${_f(got['full']?.cr ?? double.nan)} dFirst=${_f(got['full']?.dFirst ?? double.nan)}');
        _out('D444 $tok att pending found=${got.containsKey('pending')} lines=${got['pending']?.lines} breakOk=${got['pending']?.breakOk} first=${got['pending']?.first} color=${got['pending']?.color} '
            'rowBg=${got['pending']?.rowBg} cr=${_f(got['pending']?.cr ?? double.nan)} dFirst=${_f(got['pending']?.dFirst ?? double.nan)}');
        _out('D444 $tok att confirmed found=${got.containsKey('confirmed')} lines=${got['confirmed']?.lines} breakOk=${got['confirmed']?.breakOk} first=${got['confirmed']?.first} color=${got['confirmed']?.color} '
            'rowBg=${got['confirmed']?.rowBg} cr=${_f(got['confirmed']?.cr ?? double.nan)} dFirst=${_f(got['confirmed']?.dFirst ?? double.nan)}');

        // 업무 행 묶음이 보이게 굴려 한 장 더 — 측정은 위에서 끝났다.
        await t.ensureVisible(rt((p) => p == '검수'));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        await shot('2rows', 'work-rows');

        must('업무 행 시각 5 찾음', got.length == 5, '찾음 ${got.keys}');
        if (_before) {
          if (v.id == 'B') {
            // 음성 기대 — base B 는 시각 묶음이 행 칸보다 넓어 넘친다(DU443 진단 관측 6 · 코드 같음).
            must('before B 넘침 검출', overflows.isNotEmpty, '넘침 ${overflows.length}');
          }
        } else {
          for (final r in _rows) {
            final g = got[r.key];
            must('strict ${r.key} 시각 ≤ 2줄 · ~ 뒤 줄바꿈 · textSecondary ≥ 4.5 · 아이콘 첫 줄(±2)',
                g != null && g.lines <= 2 && g.breakOk && g.color == 'textSecondary' && g.cr >= 4.5 && g.dFirst.abs() <= 2, '관측 $g');
          }
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D444 $tok done state=WORK mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
