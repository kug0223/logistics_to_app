// [DU425 · 소급 셀 · 표시만] S028 근태 통계 목록(StatsAttendanceListScreen) — 범위 · 시각 · 상태 칩 · 빈 상태 글자 대비 토큰.
//   before = 현재 A(f325c88f) / strict = 후보(grey500·grey600 → textSecondary/textTertiary · 칩 error → errorDark · purple → purpleDark).
//   기본 skip — lkit 단계 env 정확 조합(TB before/du425-tb/DU_BEFORE_OBSERVE=425 · TA after/du425-ta/없음)일 때만 돈다.
//   host: stats_to_attendance_link_test(fd95686b) 의 _pump 와 같은 MultiProvider(UserProvider 대역 · NotificationProvider) → MaterialApp.
//     화면은 initial 스냅숏(조회 0)으로 연다. 탭 · 정정 · 권한 행동은 하지 않는다(표시만).
//   장면: 뷰 W 390x844@1.0 · B 320x640@2.0 × LIST(결근 · 확인 필요 · 퇴근 미확인 · 확정 지각 · 연결 없음 5행) · EMPTY = 공개 4.
//   출력 줄: 'D425 <tok> <kind> [<sub>] k=v …'.
// ignore_for_file: depend_on_referenced_packages
import 'dart:convert';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/stats_attendance_list_screen.dart';
import 'package:ALfit/services/admin_stats_service.dart';
import 'package:ALfit/theme/app_colors.dart';
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

class _Provider extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'admin1', username: 'admin1', name: '김관리', email: 'a@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const ['biz1']);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
}

DateTime _kst(int d) => DateTime.utc(2026, 10, d).subtract(const Duration(hours: 9));
AttendanceModel _att(String id, String uid, int day, String status, {String app = 'linked', String wage = 'pending', DateTime? inAt}) =>
    AttendanceModel(
      id: id, applicationId: app == 'linked' ? 'app_$id' : app, userId: uid, businessId: 'biz1', businessName: '평택 센터',
      workDate: _kst(day), workType: '분류', status: status, wageStatus: wage, checkInAt: inAt, createdAt: DateTime.utc(2026, 10, 1));

final _rows = <AttendanceModel>[
  _att('a1', 'abs', 5, AttendanceModel.statusAbsent),
  _att('u1', 'unk', 6, AttendanceModel.statusUnconfirmed),
  _att('m1', 'miss', 7, AttendanceModel.statusMissedCheckout, inAt: _kst(7).add(const Duration(hours: 9))),
  _att('p1', 'paid', 8, AttendanceModel.statusLate, wage: AttendanceModel.wageConfirmed, inAt: _kst(8).add(const Duration(hours: 9, minutes: 12))),
  _att('x1', 'nolink', 9, AttendanceModel.statusPresent, app: '', inAt: _kst(9).add(const Duration(hours: 9))),
];
const _info = {
  'abs': UserInfo(name: '합성 결근', personNo: 'P-301'),
  'unk': UserInfo(name: '합성 확인필요', personNo: 'P-302'),
  'miss': UserInfo(name: '합성 퇴근미확인', personNo: 'P-303'),
  'paid': UserInfo(name: '합성 확정지각', personNo: 'P-304'),
  'nolink': UserInfo(name: '합성 연결없음', personNo: 'P-305'),
};
const _scope = '2026년 10월 · 평택 센터 · 전체';
const _empty = '조건에 맞는 근무가 없어요';
const _unlinked = '원본 근무와 연결되지 않아 열 수 없어요';

Future<void> _loadFonts() async {
  Future<ByteData> b(String p) => File(p).readAsBytes().then((x) => ByteData.view(x.buffer));
  for (final fam in const ['NotoSansKR', 'Roboto']) {
    final l = FontLoader(fam)
      ..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'))
      ..addFont(b('assets/fonts/NotoSansKR-Bold.ttf'));
    await l.load();
  }
  final testDefault = FontLoader('FlutterTest')..addFont(b('assets/fonts/NotoSansKR-Regular.ttf'));
  await testDefault.load();
  final icons = FontLoader('MaterialIcons')..addFont(b('C:/Users/kug02/flutter/bin/cache/artifacts/material_fonts/materialicons-regular.otf'));
  await icons.load();
}

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '425';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du425-tb' && _env['DU_BEFORE_OBSERVE'] == '425') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du425-ta' && _env['DU_BEFORE_OBSERVE'] == null);
var _anyFail = false;
final String _manifest = Platform.environment['DUL_MANIFEST'] ?? '(unset)';
const _envKeys = ['DU_BEFORE_OBSERVE', 'DU1_VQ_PHASE', 'DU1_VQ_OUT', 'DU1_VQ_RUN', 'DU1_VQ_DATE', 'DU397_DIAG', 'DU397_MANIFEST', 'DU400_MANIFEST',
  'DU401_MANIFEST', 'DU398_MANIFEST', 'DU406_MANIFEST', 'DU407_MANIFEST', 'DU296_PHASE', 'DUL_MANIFEST'];
final String _envLine = [for (final k in _envKeys) '$k:${Platform.environment[k] ?? '(unset)'}'].join(',');

void _out(String s) {
  // ignore: avoid_print
  print(s);
}

String _plainOf(Widget w) => w is RichText ? TextLayout.plain(w.text.toPlainText(includeSemanticsLabels: false)) : '';

const _tokens = <String, Color>{
  'grey500': AppColors.grey500, 'grey600': AppColors.grey600, 'error': AppColors.error, 'errorDark': AppColors.errorDark,
  'purple': AppColors.purple, 'purpleDark': AppColors.purpleDark, 'textSecondary': AppColors.textSecondary,
  'textTertiary': AppColors.textTertiary,
};
String _tok(Color? c) {
  if (c == null) return 'null';
  for (final e in _tokens.entries) {
    if (e.value.toARGB32() == c.toARGB32()) return e.key;
  }
  return 'x${c.toARGB32().toRadixString(16)}';
}

void main() {
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  const views = [(id: 'W', w: 390.0, h: 844.0, s: 1.0), (id: 'B', w: 320.0, h: 640.0, s: 2.0)];
  const states = [
    (key: 'LIST', title: '근태 통계 목록 5행(결근 · 확인 필요 · 퇴근 미확인 · 확정 지각 · 연결 없음) — 범위 · 시각 · 칩 글자 대비'),
    (key: 'EMPTY', title: '근태 통계 목록 0행 — 빈 안내 글자 대비'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S028CT-${v.id}-${st.key} ${st.title}', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S028CT-${v.id}-${st.key}';
          final mode = _before ? 'before' : 'strict';
          _out('D425 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
          await t.runAsync(_loadFonts);
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
          final list = st.key == 'LIST' ? _rows : const <AttendanceModel>[];
          await t.pumpWidget(MultiProvider(
            providers: [
              ChangeNotifierProvider<UserProvider>(create: (_) => _Provider()),
              ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
            ],
            child: RepaintBoundary(
              key: key,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: RoleTheme.businessAdminTheme,
                builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(v.s)), child: child!),
                home: StatsAttendanceListScreen(
                  title: '근태 내역',
                  scopeLabel: _scope,
                  load: () async => null,
                  matches: (_) => true,
                  initial: StatsAttendanceSnapshot(records: list, userInfo: _info),
                ),
              ),
            ),
          ));
          for (var i = 0; i < 10; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          Color? colorOf(Finder f) => (t.widget(f) as RichText).text.style?.color;
          Finder rich(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)));
          final scopeF = rich((p) => p == _scope);
          must('범위 문구 1', scopeF.evaluate().length == 1);
          final scope = _tok(colorOf(scopeF));
          _out('D425 $tok shot 1main ovf=${overflows.length}');
          await vqCapture(t, key, '${tok}_1main', conditions: {
            'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key,
            'state': st.key == 'LIST' ? 'list-top' : 'empty',
          });
          if (st.key == 'LIST') {
            // 행마다 보이게 굴린 뒤 그 행 안의 글자색을 읽는다(캡처는 위 첫 화면).
            final scrollable = find.byType(Scrollable).first;
            var minH = true; // 행을 처음 보이게 할 때마다 그 행 높이를 잰다(위로 되돌아가지 않는다)
            Future<Finder> row(String id) async {
              final f = find.byKey(ValueKey('att-row-$id'));
              await t.scrollUntilVisible(f, 80, scrollable: scrollable);
              await t.pump();
              minH = minH && t.getRect(f).height >= 56 - 0.01;
              return f;
            }

            String chip(Finder rowF, {bool last = false}) {
              final chips = find.descendant(
                  of: rowF,
                  matching: find.byWidgetPredicate((w) =>
                      w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).borderRadius == BorderRadius.circular(4)));
              final els = chips.evaluate().toList();
              if (els.isEmpty) return 'none';
              final el = last ? els.last : els.first;
              final r = find.descendant(of: find.byElementPredicate((e) => identical(e, el)), matching: find.byType(RichText)).first;
              return _tok(colorOf(r));
            }

            final rA = await row('a1');
            final chipAbs = chip(rA);
            final rU = await row('u1');
            final chipUnk = chip(rU);
            final rM = await row('m1');
            final chipMiss = chip(rM);
            final timesF = find.descendant(of: rM, matching: rich((p) => p.startsWith('출근 ')));
            must('퇴근 미확인 행 시각 줄 1', timesF.evaluate().length == 1);
            final times = _tok(colorOf(timesF));
            final rP = await row('p1');
            final chipPaid = chip(rP, last: true);
            final rX = await row('x1');
            final unlF = find.descendant(of: rX, matching: rich((p) => p == _unlinked));
            must('연결 없음 안내 1', unlF.evaluate().length == 1);
            final unlinked = _tok(colorOf(unlF));
            _out('D425 $tok att color scope=$scope times=$times chipAbs=$chipAbs chipUnk=$chipUnk chipMiss=$chipMiss chipPaid=$chipPaid unlinked=$unlinked');
            _out('D425 $tok att geo rows=5 minH=$minH');
            must('행 최소 56', minH);
            if (!_before) {
              must('strict 토큰', scope == 'textSecondary' && times == 'textSecondary' && chipAbs == 'errorDark' && chipUnk == 'purpleDark' &&
                  chipMiss == 'textSecondary' && chipPaid == 'textSecondary' && unlinked == 'textTertiary',
                  '$scope $times $chipAbs $chipUnk $chipMiss $chipPaid $unlinked');
            }
          } else {
            final eF = rich((p) => p == _empty);
            must('빈 안내 1', eF.evaluate().length == 1);
            final empty = _tok(colorOf(eF));
            _out('D425 $tok att empty scope=$scope color=$empty');
            if (!_before) must('strict 빈 안내 · 범위 textSecondary', empty == 'textSecondary' && scope == 'textSecondary', '$empty $scope');
          }
          if (!_before) must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          must('미처리 framework 예외 0', fwErrors.isEmpty, '$fwErrors');
          final exc = t.takeException();
          _out('D425 $tok done state=${st.key} mode=$mode captures=1 overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
          must('끝 예외 0', exc == null, '$exc');
        } catch (e) {
          _anyFail = true;
          rethrow;
        }
      }, skip: !_optIn);
    }
  }
}
