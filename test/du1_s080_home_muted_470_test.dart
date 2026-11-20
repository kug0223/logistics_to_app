// ignore_for_file: depend_on_referenced_packages
// [DU470 · 자체 판정 셀 · 표시만] DU-S080 사용자 홈 — 공고 카드 비활성 하트 textSecondary · 불러오기 실패 안내 2곳 textTertiary.
//   before = 현재 A(user_home_screen 31b0861f) / strict = 후보. harness 는 home_full_flex_visibility_test 의 홈 렌더
//   (UserHomeScreen + UserHomeReads 메모리 대역 · 둘러보기 안내 끝남)에 DU 캡처 · 측정을 붙였다.
//   상태 3개(HEART 공고 1건 · APPERR 지원 현황 읽기 실패 · POSTERR 공고 읽기 실패).
//   값은 닿은 즉시 지역 값으로 남긴다(preflight v6). 기본 skip — TB before/du470-tb/DU_BEFORE_OBSERVE=470 · TA after/du470-ta/없음.
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

TOModel _flexTo(String id) => TOModel(
      id: id, businessId: 'biz1', businessName: '강남 물류센터', businessCity: _region.city, type: 'flex',
      title: '물류센터 상하차 $id', creatorUID: 'admin1', status: TOStatus.active, deadlineType: 'NONE', hoursBeforeStart: 0,
      workDetails: const [_wd], slotDateKeys: [_key(_day(3))], totalSlots: 1, totalRequired: 1,
      totalConfirmed: 0, totalPending: 0, isPublished: true, publishMode: 'immediate',
      createdAt: _day(-2), statusUpdatedAt: _day(-2),
    );

UserHomeReads _reads({bool appsFail = false, bool postsFail = false, List<TOModel> tos = const []}) => UserHomeReads(
      slotsForTO: (toId) async => const <SlotModel>[],
      myContracts: (uid) async => const [],
      myApplications: (uid) async {
        if (appsFail) throw StateError('du470 apps read failed');
        return const <ApplicationModel>[];
      },
      myMonthlyAttendances: ({required String userId, required int year, required int month}) async => const <AttendanceModel>[],
      publishedTOs: () async {
        if (postsFail) throw StateError('du470 posts read failed');
        return tos;
      },
      pendingIdCardRequests: (uid) async => const <IdCardAccessRequestModel>[],
      invalidatePublishedTOsCache: () {},
      documentCorrections: () async => DocumentCorrectionSurface.empty,
      myRenewalProposals: () async => const <RenewalProposalModel>[],
      businessById: (id) async => null,
    );

const _retryHint = '잠시 후 다시 시도해 주세요';

final _cases = <({String id, UserHomeReads Function() reads})>[
  (id: 'HEART', reads: () => _reads(tos: [_flexTo('open')])),
  (id: 'APPERR', reads: () => _reads(appsFail: true, tos: [_flexTo('open')])),
  (id: 'POSTERR', reads: () => _reads(postsFail: true)),
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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '470';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du470-tb' && _env['DU_BEFORE_OBSERVE'] == '470') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du470-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

const _tokens = <String, Color>{
  'white': Color(0xFFFFFFFF), 'textSecondary': AppColors.textSecondary, 'textTertiary': AppColors.textTertiary,
  'grey400': AppColors.grey400, 'background': AppColors.background, 'surface': AppColors.surface,
};
String _tok(Color? c) {
  if (c == null) return 'none';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${_hex(c)}';
}

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
  setUp(() => SharedPreferences.setMockInitialValues({'tour_completed_user_home': true}));

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  for (final v in views) {
    for (final c in _cases) {
      testWidgets('S080HM-${v.id}-${c.id} 사용자 홈 — 비활성 하트 · 실패 안내 대비', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S080HM-${v.id}-${c.id}';
          final mode = _before ? 'before' : 'strict';
          _out('D470 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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

          if (c.id == 'HEART') {
            final heartF = find.byIcon(Icons.favorite_border_rounded, skipOffstage: false);
            final n = heartF.evaluate().length;
            must('비활성 하트 ≥ 1', n >= 1, '개수 $n');
            await t.ensureVisible(heartF.first);
            for (var i = 0; i < 4; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            _out('D470 $tok shot 1home ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_1home', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
              'state': 'home',
            });
            // 하트가 여럿이면(홈 다른 공고 묶음) 모두 같은 색이어야 한다 — 가장 낮은 대비를 기록한다.
            final cols = <Color?>[];
            var minCr = double.infinity;
            for (final e in heartF.evaluate()) {
              final col = (e.widget as Icon).color;
              cols.add(col);
              minCr = math.min(minCr, _cr(col, _bgOf(e)));
            }
            final allSame = cols.every((x) => x == cols.first);
            _out('D470 $tok att heart n=$n color=${_tok(cols.first)} same=$allSame cr=${_f(minCr)}');
            if (_before) {
              must('before 하트 grey400 · 대비 3.0 미달 검출', cols.first == AppColors.grey400 && allSame && minCr < 3.0, '${_tok(cols.first)} ${_f(minCr)}');
            } else {
              must('strict 하트 textSecondary · 대비 ≥ 4.5', cols.first == AppColors.textSecondary && allSame && minCr >= 4.5, '${_tok(cols.first)} ${_f(minCr)}');
            }
          } else {
            final hintF = rt((p) => p == _retryHint);
            must('실패 안내 1', hintF.evaluate().length == 1, '개수 ${hintF.evaluate().length}');
            await t.ensureVisible(hintF);
            for (var i = 0; i < 4; i++) {
              await t.pump(const Duration(milliseconds: 50));
            }
            _out('D470 $tok shot 1home ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_1home', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': c.id,
              'state': 'home',
            });
            final col = (t.widget(hintF) as RichText).text.style?.color;
            final bg = _bgOf(hintF.evaluate().first);
            final cr = _cr(col, bg);
            _out('D470 $tok att hint text=${_tok(col)} bg=${_tok(bg)} cr=${_f(cr)}');
            if (_before) {
              must('before 실패 안내 textHint(grey400) · 대비 미달 검출', col == AppColors.grey400 && cr < 4.5, '${_tok(col)} ${_f(cr)}');
            } else {
              must('strict 실패 안내 textTertiary · 대비 ≥ 4.5', col == AppColors.textTertiary && cr >= 4.5, '${_tok(col)} ${_f(cr)}');
            }
          }
          if (!_before) must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          must('미처리 framework 예외 0', fwErrors.isEmpty, '오류 $fwErrors');
          final exc = t.takeException();
          _out('D470 $tok done state=${c.id} mode=$mode captures=1 overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
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
