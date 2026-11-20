// ignore_for_file: depend_on_referenced_packages
// [DU476 · 자체 판정 셀 · 표시만] DU-S080 사용자 홈 — 서류 보완 할 일 카드(급여 사유) '등록하기' · 화살표 warningDark · 급여 안내 textTertiary.
//   before = 현재 A(user_home_screen c0307dd3 · DU474 후보) / strict = 후보. harness 는 DU474 시험(539c1db5)과 같고 사례 · 측정 · 놓인 면 합성만 바꿨다. harness 는 home_full_flex_visibility_test 의 홈 렌더
//   (UserHomeScreen + UserHomeReads 메모리 대역 · 둘러보기 안내 끝남)에 DU 캡처 · 측정을 붙였다.
//   상태 1개(TASK 급여 사유 보완 요청 1(MISSING_BANKBOOK) + 공고 1건).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du476-tb/DU_BEFORE_OBSERVE=476 · TA after/du476-ta/없음.
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
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/id_card_access_request_model.dart';
import 'package:ALfit/models/core/renewal_proposal_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/user_home_reads.dart';
import 'package:ALfit/screens/user/user_home_screen.dart';
import 'package:ALfit/services/payroll_correction_service.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/theme/role_theme.dart';

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

const _region = UserRegion(province: '서울특별시', city: '강남구', district: '역삼동');

class _UserDouble extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1', username: 'u1', name: '김근로', email: 'u1@alfit.local', role: UserRole.USER,
        homeRegion: _region, accountStatus: 'active', passVerifiedAt: DateTime.now().subtract(const Duration(days: 30)),
      );
  @override
  Future<void> refreshPendingContracts({bool joinInFlight = false}) async {}
}

DateTime _day(int offset) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day).add(Duration(days: offset));
}

String _key(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, "0")}-${d.day.toString().padLeft(2, "0")}';

const _wd = WorkDetailData(wdId: 'wd1', workType: '상하차', wage: 12000, requiredCount: 1, startTime: '10:00', endTime: '11:00');

TOModel _flexTo(String id, {String? city}) => TOModel(
      id: id, businessId: 'biz1', businessName: '송파 물류센터', businessCity: city ?? _region.city, type: 'flex',
      title: '물류센터 상하차 $id', creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
      workDetails: const [_wd], slotDateKeys: [_key(_day(3))], totalSlots: 1, totalRequired: 1,
      totalConfirmed: 0, totalPending: 0, isPublished: true, publishMode: 'immediate',
      createdAt: _day(-2), statusUpdatedAt: _day(-2),
    );

UserHomeReads _reads({bool appsFail = false, bool postsFail = false, List<TOModel> tos = const [],
        DocumentCorrectionSurface corr = DocumentCorrectionSurface.empty}) =>
    UserHomeReads(
      slotsForTO: (toId) async => const <SlotModel>[],
      myContracts: (uid) async => const [],
      myApplications: (uid) async {
        if (appsFail) throw StateError('du476 apps read failed');
        return const <ApplicationModel>[];
      },
      myMonthlyAttendances: ({required String userId, required int year, required int month}) async => const <AttendanceModel>[],
      publishedTOs: () async {
        if (postsFail) throw StateError('du476 posts read failed');
        return tos;
      },
      pendingIdCardRequests: (uid) async => const <IdCardAccessRequestModel>[],
      invalidatePublishedTOsCache: () {},
      documentCorrections: () async => corr,
      myRenewalProposals: () async => const <RenewalProposalModel>[],
      businessById: (id) async => null,
    );

const _note = '확정된 급여 금액은 그대로 유지돼요';

final _cases = <({String id, UserHomeReads Function() reads})>[
  (id: 'TASK', reads: () => _reads(tos: [_flexTo('open')], corr: const DocumentCorrectionSurface.loaded([
        DocumentCorrectionTask(requestId: 'cr1', businessId: 'biz1', businessName: '강남 물류센터', documentType: 'BANKBOOK',
            sourceDomain: 'PAYROLL', payrollReadinessState: 'MISSING_BANKBOOK'),
      ]))),
];

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _f(double v) => v.toStringAsFixed(2);
String _hex(Color? c) => c == null ? 'none' : c.toARGB32().toRadixString(16).padLeft(8, '0');
String _plainOf(Widget w) => w is RichText ? w.text.toPlainText(includeSemanticsLabels: false) : '';

double _cr(Color? a, Color? b) {
  if (a == null || b == null) return 0;
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '476';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du476-tb' && _env['DU_BEFORE_OBSERVE'] == '476') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du476-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textSecondary': AppColors.textSecondary, 'textTertiary': AppColors.textTertiary,
  'grey400': AppColors.grey400, 'background': AppColors.background, 'surface': AppColors.surface, 'grey50': AppColors.grey50,
  'warning': AppColors.warning, 'warningDark': AppColors.warningDark,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

/// 놓인 면 — 조상의 칠한 색(Container color · BoxDecoration color · ColoredBox · Material(투명 아님))을 불투명 층까지 모아 합성한다.
///   카드 면은 accent.withValues(alpha: 0.08)(반투명)이라 아래 면과 섞어야 대비가 맞다.
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

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });
  setUp(() => SharedPreferences.setMockInitialValues({'tour_completed_user_home': true}));

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    for (final c in _cases) {
      testWidgets('S080TK-${v.id}-${c.id} 사용자 홈 — 서류 보완 카드 행동 글자 · 급여 안내 대비', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S080TK-${v.id}-${c.id}';
          final mode = _before ? 'before' : 'strict';
          _out('D476 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
          await t.runAsync(vqLoadFonts);
          final overflows = <String>[];
          final fwErrors = <String>[];
          final prev = FlutterError.onError;
          FlutterError.onError = (d) {
            final m = d.exceptionAsString();
            if (m.contains('overflowed')) {
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
            child: MultiProvider(
              providers: [
                ChangeNotifierProvider<UserProvider>.value(value: _UserDouble()),
                ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
              ],
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.workerTheme,
                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: UserHomeScreen(reads: c.reads()),
              ),
            ),
          ));
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          Finder rt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);

          {
            final noteF = rt((p) => p == _note);
            must('급여 안내 1', noteF.evaluate().length == 1, '개수 ${noteF.evaluate().length}');
            // 카드 전체가 보이게 카드(가장 가까운 GestureDetector 조상) 위를 화면 위에 맞춘다 — 안내에 맞추면 B 큰 글자에서 행동 글자가 잘린다(진단 B 원PNG).
            await t.ensureVisible(find.ancestor(of: noteF, matching: find.byType(GestureDetector, skipOffstage: false)).first);
            for (var i = 0; i < 4; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            _out('D476 $tok shot 1task ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_1task', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
              'state': 'task',
            });
            // 배치는 끝났다 — 넘침 수집기를 먼저 되돌린다(바꾼 채 expect 가 실패하면 tearDownAll 이 멈춘다 · DU475 진단).
            FlutterError.onError = prev;
            // 카드 가로 줄 — 급여 안내에서 가장 가까운 Row 조상(위치 기준 · 홈의 다른 '등록하기' · 화살표와 섞이지 않게).
            final cardRow = find.ancestor(of: noteF, matching: find.byType(Row, skipOffstage: false)).first;
            final ctaF = find.descendant(of: cardRow, matching: rt((p) => p == '등록하기'), skipOffstage: false);
            final chevF = find.descendant(of: cardRow, matching: find.byIcon(Icons.chevron_right, skipOffstage: false), skipOffstage: false);
            must('행동 글자 1', ctaF.evaluate().length == 1, '개수 ${ctaF.evaluate().length}');
            must('화살표 1', chevF.evaluate().length == 1, '개수 ${chevF.evaluate().length}');
            final noteCol = (t.widget(noteF) as RichText).text.style?.color;
            final noteBg = _bgOf(noteF.evaluate().first);
            final noteCr = _cr(noteCol, noteBg);
            final ctaCol = (t.widget(ctaF) as RichText).text.style?.color;
            final ctaBg = _bgOf(ctaF.evaluate().first);
            final ctaCr = _cr(ctaCol, ctaBg);
            final chevCol = (t.widget(chevF) as Icon).color;
            final chevBg = _bgOf(chevF.evaluate().first);
            final chevCr = _cr(chevCol, chevBg);
            _out('D476 $tok att note text=${_tok(noteCol)} bg=${_tok(noteBg)} cr=${_f(noteCr)}');
            _out('D476 $tok att cta text=${_tok(ctaCol)} bg=${_tok(ctaBg)} cr=${_f(ctaCr)}');
            _out('D476 $tok att chev icon=${_tok(chevCol)} bg=${_tok(chevBg)} cr=${_f(chevCr)}');
            if (_before) {
              // 음성 기대(코드 확정) — grey400 약 1.8 · warning 약 2.0(옅은 주황 면).
              must('before 급여 안내 grey400 · 대비 미달 검출', noteCol == AppColors.grey400 && noteCr < 4.5, '${_tok(noteCol)} ${_f(noteCr)}');
              must('before 행동 글자 warning · 대비 미달 검출', ctaCol == AppColors.warning && ctaCr < 4.5, '${_tok(ctaCol)} ${_f(ctaCr)}');
              must('before 화살표 warning · 대비 3 미만 검출', chevCol == AppColors.warning && chevCr < 3, '${_tok(chevCol)} ${_f(chevCr)}');
            } else {
              must('strict 급여 안내 textTertiary · 대비 ≥ 4.5', noteCol == AppColors.textTertiary && noteCr >= 4.5, '${_tok(noteCol)} ${_f(noteCr)}');
              must('strict 행동 글자 warningDark · 대비 ≥ 4.5', ctaCol == AppColors.warningDark && ctaCr >= 4.5, '${_tok(ctaCol)} ${_f(ctaCr)}');
              must('strict 화살표 warningDark · 대비 ≥ 4.5', chevCol == AppColors.warningDark && chevCr >= 4.5, '${_tok(chevCol)} ${_f(chevCr)}');
            }
          }
          if (!_before) must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
          final exc = t.takeException();
          _out('D476 $tok done state=${c.id} mode=$mode captures=1 overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
          must('끝 예외 0', exc == null, '예외 $exc');
          await t.pumpWidget(const SizedBox.shrink());
          await t.pump(const Duration(milliseconds: 50));
        } catch (e) {
          _anyFail = true;
          rethrow;
        }
      }, skip: !_optIn);
    }
  }
}
