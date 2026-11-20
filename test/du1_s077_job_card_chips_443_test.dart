// ignore_for_file: depend_on_referenced_packages
// [DU443 · 자체 판정 셀 · 표시만] DU-S077 일자리 탭 공고 카드(계약 · 펼침) — 업무 행 상태 칩 5종 짝 · 마감 행 반투명 제거 · 'N일 전' 글자.
//   before = 현재 A(user_to_card bc66d70f) / strict = 후보(621f6720). 진입은 user_to_card_expired_relation_test(UTC-3/4)와 같은 seam
//   (UserTOCard 직접 · workDetails 주입 · selectedNotifier = to.id 로 펼침). 상태 판정 · 문구는 그대로이고 색 짝 · 반투명만 본다.
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du443-tb/DU_BEFORE_OBSERVE=443 · TA after/du443-ta/없음.
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '443';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du443-tb' && _env['DU_BEFORE_OBSERVE'] == '443') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du443-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
  'grey50': AppColors.grey50, 'grey100': AppColors.grey100, 'grey200': AppColors.grey200, 'grey400': AppColors.grey400,
  'infoLight': AppColors.infoLight, 'successLight': AppColors.successLight,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

// 기대 짝(strict) — 지원 대화 업무 카드(WorkSelectionCard · DU274 WC3)와 같다.
// [DU443d · 후속115 §2-2] att 이름을 출력 글자 그대로 적는다(유한 5개 · _rows 와 같은 순서). 성공 줄 바이트는 rd 판과 같다. 부재 줄은 성공 줄과 같은 키에 값 - (정상값 아님 · lkit 이 실패로 잡는다 · 뒤의 5개 must 도 그대로 실패).
void _attMissing(String tok, String key) {
  switch (key) {
    case 'open':
      _out('D443 $tok att open found=false label=- text=- bg=- cr=- op=- rowBg=- rowLine=-');
    case 'urgent':
      _out('D443 $tok att urgent found=false label=- text=- bg=- cr=- op=- rowBg=- rowLine=-');
    case 'full':
      _out('D443 $tok att full found=false label=- text=- bg=- cr=- op=- rowBg=- rowLine=-');
    case 'pending':
      _out('D443 $tok att pending found=false label=- text=- bg=- cr=- op=- rowBg=- rowLine=-');
    case 'confirmed':
      _out('D443 $tok att confirmed found=false label=- text=- bg=- cr=- op=- rowBg=- rowLine=-');
    default:
      throw StateError('att 키 밖: $key');
  }
}

void _attFound(String tok, String key, String label, String text, String bg, String cr, String op, String rowBg, String rowLine) {
  switch (key) {
    case 'open':
      _out('D443 $tok att open found=true label=$label text=$text bg=$bg cr=$cr op=$op rowBg=$rowBg rowLine=$rowLine');
    case 'urgent':
      _out('D443 $tok att urgent found=true label=$label text=$text bg=$bg cr=$cr op=$op rowBg=$rowBg rowLine=$rowLine');
    case 'full':
      _out('D443 $tok att full found=true label=$label text=$text bg=$bg cr=$cr op=$op rowBg=$rowBg rowLine=$rowLine');
    case 'pending':
      _out('D443 $tok att pending found=true label=$label text=$text bg=$bg cr=$cr op=$op rowBg=$rowBg rowLine=$rowLine');
    case 'confirmed':
      _out('D443 $tok att confirmed found=true label=$label text=$text bg=$bg cr=$cr op=$op rowBg=$rowBg rowLine=$rowLine');
    default:
      throw StateError('att 키 밖: $key');
  }
}

const _rows = [
  (key: 'open', work: '분류', label: '모집중', bg: 'infoBg', text: 'infoDeep'),
  (key: 'urgent', work: '상차', label: '긴급', bg: 'errorBg', text: 'errorDark'),
  (key: 'full', work: '하차', label: '마감', bg: 'grey100', text: 'textSecondary'),
  (key: 'pending', work: '포장', label: '대기중', bg: 'infoBg', text: 'infoDeep'),
  (key: 'confirmed', work: '검수', label: '확정', bg: 'successBg', text: 'successDark'),
];

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S077JC-${v.id}-WORK 일자리 공고 카드(계약 · 펼침) — 업무 행 상태 칩 짝 · 마감 행 반투명 0 · N일 전 글자', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S077JC-${v.id}-WORK';
        final mode = _before ? 'before' : 'strict';
        _out('D443 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
          _out('D443 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'WORK',
            'state': state,
          });
          shots++;
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        await shot('1top', 'card-expanded');

        // ── 머리 'N일 전'(값은 즉시) ──
        final timeF = rt((p) => RegExp(r'^\d+(분|시간|일) 전$').hasMatch(p));
        must('N일 전 1', timeF.evaluate().length == 1, '${timeF.evaluate().length}개');
        final timeColor = (t.widget(timeF) as RichText).text.style?.color;
        final timeCr = _cr(timeColor, AppColors.surface);
        _out('D443 $tok att time color=${_tok(timeColor)} cr=${_f(timeCr)} text=${_plainOf(t.widget(timeF)).replaceAll(' ', '_')}');

        // ── 업무 행 칩(값은 즉시) ──
        final got = <String, ({String text, String bg, double cr, double op, String rowBg, String rowLine})>{};
        for (final r in _rows) {
          // 업무명 글이 여러 곳(머리 요약 등)에 있어도 '테두리 있는 행 상자 안에 이 칩 글이 함께 있는' 것 하나만 고른다.
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
                .descendant(of: find.byElementPredicate((x) => identical(x, b), skipOffstage: false), matching: rt((p) => p == r.label), skipOffstage: false)
                .evaluate()
                .length;
            if (has == 1 && !rowsFound.any((x) => identical(x, b))) rowsFound.add(b);
          }
          if (rowsFound.length != 1) {
            _attMissing(tok, r.key);
            continue;
          }
          final row = rowsFound.single;
          // [DU443e] 행 상자(테두리 있는 Container)의 면 · 선 토큰 — 값은 즉시 문자열로.
          final rowDec = (row.widget as Container).decoration! as BoxDecoration;
          final rowBg = _tok(rowDec.color);
          final rowLine = _tok((rowDec.border! as Border).top.color);
          final chipF = find.descendant(
              of: find.byElementPredicate((x) => identical(x, row), skipOffstage: false),
              matching: rt((p) => p == r.label),
              skipOffstage: false);
          final text = (t.widget(chipF) as RichText).text.style?.color;
          Color? bg;
          var op = 1.0;
          chipF.evaluate().first.visitAncestorElements((a) {
            final w = a.widget;
            if (bg == null && w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).color != null) {
              bg = (w.decoration! as BoxDecoration).color;
            }
            if (w is Opacity) op *= w.opacity;
            if (w is UserTOCard) return false;
            return true;
          });
          final cr = _cr(text, bg);
          got[r.key] = (text: _tok(text), bg: _tok(bg), cr: cr, op: op, rowBg: rowBg, rowLine: rowLine);
          _attFound(tok, r.key, r.label, _tok(text), _tok(bg), _f(cr), _f(op), rowBg, rowLine);
        }

        // 업무 행 묶음이 보이게 굴려 한 장 더 — 측정은 위에서 끝났다.
        await t.ensureVisible(rt((p) => p == '검수'));
        for (var i = 0; i < 6; i++) {
          await t.pump(const Duration(milliseconds: 50));
        }
        await shot('2rows', 'work-rows');

        must('업무 행 칩 5 찾음', got.length == 5, '찾음 ${got.keys}');
        if (_before) {
          // [DU443e r2] base = 443d 채택판(37632435) — 칩 5종은 이미 엷은 면 + 진한 글자 짝 · 마감 반투명 0(443d TA · e TB 관측).
          //   음성 기대는 행 면만: 대기중 행 infoBg/infoLight · 확정 행 successBg/successLight 로 칩 면과 같다.
          for (final r in _rows) {
            final g = got[r.key];
            must('before ${r.key} 칩 짝 ${r.bg}/${r.text} 그대로 · 반투명 0', g != null && g.bg == r.bg && g.text == r.text && g.op > 0.99, '관측 $g');
          }
          must('before 대기중 · 확정 행 상태색 면 = 칩 면(음성) · N일 전 textTertiary',
              got['pending']?.rowBg == 'infoBg' && got['pending']?.rowLine == 'infoLight' &&
                  got['confirmed']?.rowBg == 'successBg' && got['confirmed']?.rowLine == 'successLight' &&
                  timeColor == AppColors.textTertiary,
              '$got ${_tok(timeColor)}');
        } else {
          for (final r in _rows) {
            final g = got[r.key];
            must('strict ${r.key} 짝 ${r.bg}/${r.text} · 대비 ≥ 4.5 · 반투명 0',
                g != null && g.bg == r.bg && g.text == r.text && g.cr >= 4.5 && g.op > 0.99 &&
                    // [DU443e] 행은 중립(흰 면 + grey200 선) · 칩 면이 행 면과 달라 알약이 보인다.
                    g.rowBg == 'white' && g.rowLine == 'grey200' && g.bg != g.rowBg, '관측 $g');
          }
          must('strict N일 전 textTertiary · 대비 ≥ 4.5', timeColor == AppColors.textTertiary && timeCr >= 4.5, '${_tok(timeColor)} ${_f(timeCr)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D443 $tok done state=WORK mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
