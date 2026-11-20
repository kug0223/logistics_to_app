// ignore_for_file: depend_on_referenced_packages
// [DU460 · 자체 판정 셀 · 표시만] DU-S077 일자리 탭 공고 카드(계약 · 접힘) — 펼치기 바 이름표 · 화살표 textSecondary.
//   before = 현재 A(user_to_card 1513254f · DU458 후보) / strict = 후보. harness 는 DU458 시험(38fdfe23)과 같고 측정만 바꿨다.
//   카드를 펼치지 않는다(selectedNotifier 값 null · 다른 카드가 펼쳐지면 0.5 로 흐려지므로 null) — 업무 행(DU444 영역)의 넘침이 섞이지 않게. 넘침은 출처(파일:줄)와 함께 남긴다.
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du460-tb/DU_BEFORE_OBSERVE=460 · TA after/du460-ta/없음.
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '460';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du460-tb' && _env['DU_BEFORE_OBSERVE'] == '460') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du460-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
  'grey50': AppColors.grey50, 'grey100': AppColors.grey100, 'grey300': AppColors.grey300, 'grey400': AppColors.grey400,
  'grey500': AppColors.grey500, 'surface': AppColors.surface,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

/// 글자 상자 top 으로 줄을 가른다 — 줄바꿈이 공백 · NBSP · 이름 가운데 표시(ZWSP) 뒤에서만 일어났는가.

/// 놓인 면 — 가장 가까운 조상의 칠한 색(Container color · BoxDecoration color · ColoredBox · Material(투명 아님)).
Color? _bgOf(Element e) {
  Color? found;
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
    if (c != null) {
      found = c;
      return false;
    }
    return true;
  });
  return found;
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    testWidgets('S077EB-${v.id}-CARD 일자리 공고 카드(계약 · 접힘) — 펼치기 바 이름표 · 화살표 색 · 대비', (t) async {
      if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
      try {
        final tok = 'S077EB-${v.id}-CARD';
        final mode = _before ? 'before' : 'strict';
        _out('D460 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
          _out('D460 $tok shot $sub ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_$sub', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': 'CARD',
            'state': state,
          });
          shots++;
        }

        Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
        await shot('1card', 'card-collapsed');

        // ── 접힌 카드 펼치기 바(값은 즉시) — 이름표 '업무 상세' · 화살표(expand_more) 색과 놓인 면(grey50) 대비 ──
        final barF = rt((p) => p == '업무 상세');
        must('업무 상세 1', barF.evaluate().length == 1, '개수 ${barF.evaluate().length}');
        final barText = (t.widget(barF) as RichText).text.style?.color;
        final barBg = _bgOf(barF.evaluate().first);
        final barCr = _cr(barText, barBg);
        _out('D460 $tok att bar text=${_tok(barText)} bg=${_tok(barBg)} cr=${_f(barCr)}');

        final arrowF = find.byIcon(Icons.expand_more, skipOffstage: false);
        must('화살표 1', arrowF.evaluate().length == 1, '개수 ${arrowF.evaluate().length}');
        final arrowColor = t.widget<Icon>(arrowF).color;
        final arrowBg = _bgOf(arrowF.evaluate().first);
        final arrowCr = _cr(arrowColor, arrowBg);
        _out('D460 $tok att arrow color=${_tok(arrowColor)} bg=${_tok(arrowBg)} cr=${_f(arrowCr)}');

        if (_before) {
          // 음성 기대(코드 확정) — 이름표 grey500 · 화살표 grey400(grey50 위 비글자 기준 3.0 미달).
          must('before 이름표 grey500 · 대비 미달 검출', barText == AppColors.grey500 && barCr < 4.5, '${_tok(barText)} ${_f(barCr)}');
          must('before 화살표 grey400 · 대비 3.0 미달 검출', arrowColor == AppColors.grey400 && arrowCr < 3.0, '${_tok(arrowColor)} ${_f(arrowCr)}');
        } else {
          must('strict 이름표 textSecondary · 대비 ≥ 4.5', barText == AppColors.textSecondary && barCr >= 4.5, '${_tok(barText)} ${_f(barCr)}');
          must('strict 화살표 textSecondary · 대비 ≥ 4.5', arrowColor == AppColors.textSecondary && arrowCr >= 4.5, '${_tok(arrowColor)} ${_f(arrowCr)}');
          must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
        }
        must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
        final exc = t.takeException();
        _out('D460 $tok done state=CARD mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
        must('끝 예외 0', exc == null, '예외 $exc');
        await t.pumpWidget(const SizedBox.shrink());
      } catch (e) {
        _anyFail = true;
        rethrow;
      }
    }, skip: !_optIn);
  }
}
