// ignore_for_file: depend_on_referenced_packages
// [DU450 · 자체 판정 셀 · 표시만] DU-S077 일자리 탭 공고 카드(계약 · 접힘) — 머리 B 결함 묶음: 제목 음절 끊김 · 급여 줄 요약/인원 · 행동 버튼 줄 넘침.
//   before = 현재 A(user_to_card bc66d70f) / strict = 후보(ac705ddd). harness 는 DU443 시험(2cbb067f)과 같다(UserTOCard 직접).
//   카드를 펼치지 않는다(selectedNotifier 값 null · 다른 카드가 펼쳐지면 0.5 로 흐려지므로 null) — 업무 행(DU444 영역)의 넘침이 섞이지 않게. 넘침은 출처(파일:줄)와 함께 남긴다.
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du450-tb/DU_BEFORE_OBSERVE=450 · TA after/du450-ta/없음.
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '450';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du450-tb' && _env['DU_BEFORE_OBSERVE'] == '450') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du450-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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

/// 글자 상자 top 으로 줄을 가른다 — 줄바꿈이 공백 · NBSP · 이름 가운데 표시(ZWSP) 뒤에서만 일어났는가.
({int lines, bool ok}) _breaks(RenderParagraph rp) {
  final s = rp.text.toPlainText(includeSemanticsLabels: false);
  final tops = <double>[];
  double? prevTop;
  var ok = true;
  for (var i = 0; i < s.length; i++) {
    final bx = rp.getBoxesForSelection(TextSelection(baseOffset: i, extentOffset: i + 1));
    if (bx.isEmpty) continue;
    final tp = bx.first.top;
    if (!tops.any((x) => (x - tp).abs() < 0.5)) tops.add(tp);
    if (prevTop != null && (tp - prevTop).abs() >= 0.5) {
      final raw = s.substring(0, i);
      if (!(raw.endsWith(' ') || raw.endsWith(String.fromCharCode(0x00A0)) || raw.endsWith(String.fromCharCode(0x200B)))) ok = false;
    }
    prevTop = tp;
  }
  return (lines: tops.length, ok: ok);
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S077CH-${v.id}-CARD 일자리 공고 카드(계약 · 접힘) — 제목 낱말 경계 · 급여 줄 두 줄 · 행동 버튼 쌓기 · 넘침 0', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S077CH-${v.id}-CARD';
        final mode = _before ? 'before' : 'strict';
        _out('D450 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
        await t.runAsync(vqLoadFonts);
        final overflows = <String>[];
        final fwErrors = <String>[];
        final prev = FlutterError.onError;
        FlutterError.onError = (d) {
          final m = d.exceptionAsString();
          if (m.contains('overflowed')) {
            // 넘침 출처(파일:줄)를 함께 남긴다(DU446 · 447 교훈).
            final full = d.toString();
            final k = full.indexOf('The relevant error-causing widget was');
            final loc = k < 0 ? '' : full.substring(k).split('\n').skip(1).firstWhere((l) => l.trim().isNotEmpty, orElse: () => '').trim();
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
                    selectedNotifier: ValueNotifier<String?>(null),
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
          _out('D450 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'CARD',
            'state': state,
          });
          shots++;
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        await shot('1card', 'card-collapsed');

        // ── 접힌 카드 머리(값은 즉시) ──
        final cardR = t.getRect(find.byType(UserTOCard));
        final titleF = rt((p) => p == '물류센터 장기 근무');
        must('제목 1', titleF.evaluate().length == 1, '개수 ${titleF.evaluate().length}');
        final tj = _breaks(t.renderObject(titleF) as RenderParagraph);
        final hintF = rt((p) => p == '분류 외 4개');
        final recruitF = rt((p) => RegExp(r'^\d+/\d+명$').hasMatch(p));
        must('요약 · 인원 1/1', hintF.evaluate().length == 1 && recruitF.evaluate().length == 1,
            '${hintF.evaluate().length}/${recruitF.evaluate().length}');
        final hintColor = (t.widget(hintF) as RichText).text.style?.color;
        final recruitColor = (t.widget(recruitF) as RichText).text.style?.color;
        final hintRp = t.renderObject(hintF) as RenderParagraph;
        final hintCut = hintRp.didExceedMaxLines || hintRp.getMaxIntrinsicWidth(double.infinity) > hintRp.constraints.maxWidth + 0.5;
        final rR = t.getRect(recruitF);
        final recruitIn = rR.right <= cardR.right - 1;
        _out('D450 $tok att wage hintCut=$hintCut hint=${_tok(hintColor)} recruit=${_tok(recruitColor)} recruitIn=$recruitIn '
            'cr=${_f(math.min(_cr(hintColor, AppColors.surface), _cr(recruitColor, AppColors.surface)))}');
        final detailF = rt((p) => p == '상세보기');
        final applyF = rt((p) => p == '지원관리');
        must('행동 버튼 1/1', detailF.evaluate().length == 1 && applyF.evaluate().length == 1,
            '${detailF.evaluate().length}/${applyF.evaluate().length}');
        final dR = t.getRect(find.ancestor(of: detailF, matching: find.byType(InkWell, skipOffstage: false)).first);
        final aR = t.getRect(find.ancestor(of: applyF, matching: find.byType(InkWell, skipOffstage: false)).first);
        final btnStacked = aR.top >= dR.bottom - 0.5;
        final btnIn = dR.right <= cardR.right - 1 && aR.right <= cardR.right - 1;
        final sameW = (dR.width - aR.width).abs() <= 0.5;
        _out('D450 $tok att action stacked=$btnStacked inside=$btnIn sameW=$sameW detailW=${_f(dR.width)} applyW=${_f(aR.width)} '
            'applyRight=${_f(aR.right)} cardRight=${_f(cardR.right)}');
        _out('D450 $tok att title lines=${tj.lines} ok=${tj.ok}');

        if (_before) {
          if (v.id == 'B') {
            // 음성 기대 — base B 는 행동 줄 넘침(DU443 진단 · DU444 TA 원PNG) · 제목 음절 끊김('근 / 무').
            must('before B 행동 줄 넘침 · 제목 음절 끊김 검출', overflows.isNotEmpty && !tj.ok, '넘침 ${overflows.length} 제목 ${tj.ok}');
          }
        } else {
          must('strict 제목 낱말 경계', tj.ok, '줄 ${tj.lines}');
          must('strict 요약 · 인원 textTertiary · 인원 카드 안', hintColor == AppColors.textTertiary && recruitColor == AppColors.textTertiary && recruitIn,
              '${_tok(hintColor)} ${_tok(recruitColor)} $recruitIn');
          if (v.id == 'B') {
            must('strict B 요약 말줄임 0 · 버튼 위아래 전체 폭 · 같은 폭 · 카드 안', !hintCut && btnStacked && sameW && btnIn,
                '말줄임 $hintCut 쌓기 $btnStacked 같은 폭 $sameW 안 $btnIn');
          } else {
            must('strict W 버튼 한 줄 · 카드 안', !btnStacked && btnIn, '쌓기 $btnStacked 안 $btnIn');
          }
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D450 $tok done state=CARD mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
