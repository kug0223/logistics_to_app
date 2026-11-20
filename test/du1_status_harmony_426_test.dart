// [DU426 · 소급 셀 · 표시만] 근태 상태 글자색 앱 조화 — S028 근태 목록 칩과 월 상세(AdminMonthDetailScreen) 직원 배지를 같은 진한 짝으로,
//   그리고 월 상세 같은 화면의 옅은 글자(grey400/500/600 · amber · success 글자)를 읽히는 짝으로(같은 화면을 다시 쪼개지 않는다).
//   규칙: 글자 = 진한 짝(지각 warningDark · 퇴근미확인 textSecondary · 확인필요 purple · 결근 errorDark), 막대 · 범례 점 · 별(채움) = 기본색.
//   before = 현재 A(목록 742864ff · 월 상세 5981b974) / strict = 후보(목록 7767bf63 · 월 상세 c9104a57).
//   기본 skip — lkit 단계 env 정확 조합(TB before/du426-tb/DU_BEFORE_OBSERVE=426 · TA after/du426-ta/없음)일 때만 돈다.
//   host · 대역 · 근태 원본은 stats_to_attendance_link_test(fd95686b) 의 _Provider · _FakeStats(월 집계 = 실제 buildMonthDetail) · _att 와 같은 꼴.
//   장면: 뷰 W 390x844@1.0 · B 320x640@2.0 × LIST · MONTH = 공개 4. 탭 · 정정 · 조회 흐름은 하지 않는다(표시만).
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
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/admin_month_detail_screen.dart';
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

/// stats_to_attendance_link_test :37–59 와 같은 관리자 대역(권한 모두 허용)
class _Provider extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(uid: 'admin1', username: 'admin1', name: '김관리', email: 'a@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const ['biz1']);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

DateTime _kst(int d) => DateTime.utc(2026, 10, d).subtract(const Duration(hours: 9));
AttendanceModel _att(String id, String uid, int day, String status, {String wage = 'pending', DateTime? inAt}) => AttendanceModel(
    id: id, applicationId: 'app_$id', userId: uid, businessId: 'biz1', businessName: '평택 센터', workDate: _kst(day),
    workType: '분류', status: status, wageStatus: wage, checkInAt: inAt, createdAt: DateTime.utc(2026, 10, 1));

final _rows = <AttendanceModel>[
  _att('a1', 'abs', 5, AttendanceModel.statusAbsent),
  _att('u1', 'unk', 6, AttendanceModel.statusUnconfirmed),
  _att('m1', 'miss', 7, AttendanceModel.statusMissedCheckout, inAt: _kst(7).add(const Duration(hours: 9))),
  _att('l1', 'late', 8, AttendanceModel.statusLate, inAt: _kst(8).add(const Duration(hours: 9, minutes: 12))),
  _att('p1', 'ok', 9, AttendanceModel.statusPresent, inAt: _kst(9).add(const Duration(hours: 9))),
];
const _info = {
  'abs': UserInfo(name: '합성 결근', personNo: 'P-401'),
  'unk': UserInfo(name: '합성 확인필요', personNo: 'P-402'),
  'miss': UserInfo(name: '합성 퇴근미확인', personNo: 'P-403'),
  'late': UserInfo(name: '합성 지각', personNo: 'P-404'),
  'ok': UserInfo(name: '합성 정상', personNo: 'P-405'),
};

/// 월 집계는 실제 buildMonthDetail. [review] = W 에서만 리뷰 줄(평점 · 재고용 · 건수 · 태그)을 그린다 —
///   B 320@2.0 의 리뷰 줄(Row + Spacer)은 배치 셀 몫이라 이번 색 셀에서 넣지 않는다(B 리뷰 줄 넘침 여부는 미관측).
class _FakeStats extends AdminStatsService {
  _FakeStats(this.review);
  final bool review;
  @override
  Future<List<BusinessOption>> getBusinessOptions(List<String> ids) async => const [BusinessOption(id: 'biz1', name: '평택 센터')];
  @override
  Future<MonthDetailData> getMonthDetail({required List<String> businessIds, String? filterBusinessId, required int year, required int month}) async =>
      review
          ? AdminStatsService.buildMonthDetail(year: 2026, month: 10, attendance: _rows, infoMap: _info, avgRating: 4.6, rehireCount: 3,
              noRehireCount: 1, posTagFreq: const {'성실': 2}, reviewStatsState: ReviewStatsState.available)
          : AdminStatsService.buildMonthDetail(year: 2026, month: 10, attendance: _rows, infoMap: _info);
  @override
  Future<StatsAttendanceSnapshot?> getAttendanceSnapshot({required List<String> businessIds, String? filterBusinessId, required int year, int? month}) async =>
      StatsAttendanceSnapshot(records: _rows, userInfo: _info);
}

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

final bool _before = Platform.environment['DU_BEFORE_OBSERVE'] == '426';
final Map<String, String> _env = Platform.environment;
final bool _optIn =
    (_env['DU1_VQ_PHASE'] == 'before' && _env['DU1_VQ_RUN'] == 'du426-tb' && _env['DU_BEFORE_OBSERVE'] == '426') ||
        (_env['DU1_VQ_PHASE'] == 'after' && _env['DU1_VQ_RUN'] == 'du426-ta' && _env['DU_BEFORE_OBSERVE'] == null);
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
  'warning': AppColors.warning, 'warningDark': AppColors.warningDark, 'grey600': AppColors.grey600, 'textSecondary': AppColors.textSecondary,
  'purple': AppColors.purple, 'purpleDark': AppColors.purpleDark, 'error': AppColors.error, 'errorDark': AppColors.errorDark,
  'grey400': AppColors.grey400, 'grey500': AppColors.grey500, 'textTertiary': AppColors.textTertiary, 'textPrimary': AppColors.textPrimary,
  'amber': AppColors.amber, 'success': AppColors.success, 'successDark': AppColors.successDark,
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
    (key: 'LIST', title: '근태 통계 목록 칩 — 지각 · 퇴근 미확인 · 확인 필요 · 결근 글자색'),
    (key: 'MONTH', title: '월 상세 — 직원 배지 · 같은 화면 보조 글자 · 리뷰 줄(W만) 글자색'),
  ];
  for (final v in views) {
    for (final st in states) {
      testWidgets('S028HM-${v.id}-${st.key} ${st.title}', (t) async {
        if (_anyFail) fail('앞 사례 실패 — 이 사례 본문 실행 0 · 캡처 0');
        try {
          final tok = 'S028HM-${v.id}-${st.key}';
          final mode = _before ? 'before' : 'strict';
          _out('D426 $tok begin mode=$mode phase=${Platform.environment['DU1_VQ_PHASE'] ?? '(unset)'} env=$_envLine manifest=$_manifest');
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
          final isList = st.key == 'LIST';
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
                home: isList
                    ? StatsAttendanceListScreen(
                        title: '근태 내역', scopeLabel: '2026년 10월 · 평택 센터 · 전체', load: () async => null, matches: (_) => true,
                        initial: StatsAttendanceSnapshot(records: _rows, userInfo: _info))
                    : AdminMonthDetailScreen(
                        businessIds: const ['biz1'], filterBusinessId: null, year: 2026, month: 10,
                        businesses: const [BusinessOption(id: 'biz1', name: '평택 센터')], service: _FakeStats(v.id == 'W'),
                        debugOpenAttendance: (_) async => false),
              ),
            ),
          ));
          for (var i = 0; i < 20; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
          // 본문 세로 Scrollable 중 가장 큰 것(DU421 :368–372 와 같은 고름)
          final all = find.byType(Scrollable);
          final vs = [for (var i = 0; i < all.evaluate().length; i++) all.at(i)]
              .where((f) => t.state<ScrollableState>(f).position.axis == Axis.vertical)
              .toList()
            ..sort((a, b) => t.getRect(b).height.compareTo(t.getRect(a).height));
          must('세로 Scrollable 있음', vs.isNotEmpty);
          final scrollable = vs.first;
          // 대상은 skipOffstage:false 로 찾고, 매번 맨 위로 되돌린 뒤 아래로 굴려 닿는다(순서 · 캐시 범위에 기대지 않는다).
          Future<Finder> reach(Finder f) async {
            t.state<ScrollableState>(scrollable).position.jumpTo(0);
            await t.pump();
            await t.scrollUntilVisible(f, 80, scrollable: scrollable);
            await t.pump();
            return f;
          }

          String colorIn(Finder host) =>
              _tok((t.widget(find.descendant(of: host, matching: find.byType(RichText), skipOffstage: false).first) as RichText).text.style?.color);
          Finder txt(bool Function(String p) p) => find.byWidgetPredicate((w) => w is RichText && p(_plainOf(w)), skipOffstage: false);
          Future<String> colorOfText(String label, bool Function(String p) p) async {
            final f = txt(p);
            await reach(f.first);
            must('$label 글자 있음', f.evaluate().isNotEmpty);
            return _tok((t.widget(f.first) as RichText).text.style?.color);
          }

          var shots = 0;
          Future<void> shot(String sub, String state) async {
            _out('D426 $tok shot $sub ovf=${overflows.length}');
            await vqCapture(t, key, '${tok}_$sub', conditions: {
              'viewport': '${v.w.toInt()}x${v.h.toInt()}', 'textScaler': v.s, 'run': vqRun, 'manifest': _manifest, 'mode': mode, 'fixture': st.key,
              'state': state,
            });
            shots++;
          }

          final String cLate, cMiss, cUnk, cAbs;
          if (isList) {
            Finder chipOf(String id) => find.descendant(
                of: find.byKey(ValueKey('att-row-$id'), skipOffstage: false),
                matching: find.byWidgetPredicate((w) =>
                    w is Container && w.decoration is BoxDecoration && (w.decoration! as BoxDecoration).borderRadius == BorderRadius.circular(4),
                    skipOffstage: false),
                skipOffstage: false).first;
            Future<String> rowChip(String id) async {
              await reach(find.byKey(ValueKey('att-row-$id'), skipOffstage: false));
              return colorIn(chipOf(id));
            }

            await shot('1main', 'list-top');
            cAbs = await rowChip('a1');
            cUnk = await rowChip('u1');
            cMiss = await rowChip('m1');
            cLate = await rowChip('l1');
            _out('D426 $tok att chip late=$cLate miss=$cMiss unk=$cUnk abs=$cAbs');
          } else {
            await shot('1top', 'month-top');
            // 같은 화면 글자(위 → 아래). '근무일' · '임금' 은 정렬 칩과 표 머리에 겹치므로 겹치지 않는 '이름' 칩 · '출결 현황' 머리를 고른다.
            // 사업장 1곳이면 범위 줄에 이름이 붙는다(_bizNameForTitle :388–393 · TR-2b 기대와 같다).
            final scope = await colorOfText('범위 줄', (p) => p == '2026년 10월 · 평택 센터');
            final total = await colorOfText('총 인건비', (p) => p == '총 인건비');
            final stat = await colorOfText('근태 칸 지각 비율', (p) => p.startsWith('지각 ') && p.endsWith('%'));
            final review = v.id == 'W';
            final rating = review ? await colorOfText('평점', (p) => p == '4.6') : 'na';
            final rehire = review ? await colorOfText('재고용', (p) => p == '재고용 75%') : 'na';
            final cnt = review ? await colorOfText('리뷰 건수', (p) => p == '(4건)') : 'na';
            final sort = await colorOfText('정렬', (p) => p == '정렬');
            final chip = await colorOfText('정렬 칩 미선택', (p) => p == '이름');
            final pno = await colorOfText('인력번호', (p) => p == 'P-404');
            final stacked = txt((p) => p == '근무일 1일').evaluate().isNotEmpty;
            final tabled = txt((p) => p == '1일').evaluate().isNotEmpty;
            final layout = stacked ? 'stacked' : (tabled ? 'table' : 'none');
            must('직원 행 배치 확인', layout != 'none');
            final days = await colorOfText('근무일', (p) => p == (stacked ? '근무일 1일' : '1일'));
            final hdr = layout == 'table' ? await colorOfText('표 머리', (p) => p == '출결 현황') : 'na';
            final unset = await colorOfText('미확정', (p) => p == '미확정');
            _out('D426 $tok att text scope=$scope total=$total stat=$stat sort=$sort chip=$chip pno=$pno days=$days unset=$unset layout=$layout hdr=$hdr');
            _out('D426 $tok att review shown=$review rating=$rating rehire=$rehire cnt=$cnt');
            if (!_before) {
              must('strict 같은 화면 글자', scope == 'textSecondary' && total == 'textSecondary' && stat == 'textSecondary' && sort == 'textSecondary' &&
                  chip == 'textSecondary' && pno == 'textSecondary' && days == 'textSecondary' && unset == 'textTertiary' &&
                  (hdr == 'textSecondary' || (layout == 'stacked' && hdr == 'na')),
                  '$scope $total $stat $sort $chip $pno $days $unset $layout $hdr');
              must('strict 리뷰 줄', review ? (rating == 'textPrimary' && rehire == 'successDark' && cnt == 'textTertiary') : rating == 'na',
                  '$rating $rehire $cnt');
            }
            Finder badge(String uid, String b) => find.byKey(ValueKey('worker-badge-$uid-$b'), skipOffstage: false);
            // 닿은 그 순간에 개수 · 글자를 읽는다(굴린 뒤 화면 밖 행은 해제될 수 있다).
            String badgeColor(String name, Finder f) {
              must('$name 배지 정확 1', f.evaluate().length == 1);
              return colorIn(f);
            }

            await reach(badge('late', 'late'));
            await shot('2badge', 'worker-badges');
            final lateF = await reach(badge('late', 'late'));
            cLate = badgeColor('지각', lateF);
            final plainLate = _plainOf(t.widget(find.descendant(of: lateF, matching: find.byType(RichText), skipOffstage: false).first));
            must('지각 배지 문구 원문', plainLate == '지각 1 ›', plainLate);
            cMiss = badgeColor('퇴근미확인', await reach(badge('miss', 'missedCheckout')));
            cUnk = badgeColor('확인필요', await reach(badge('unk', 'unconfirmed')));
            cAbs = badgeColor('결근', await reach(badge('abs', 'absent')));
            _out('D426 $tok att badge late=$cLate miss=$cMiss unk=$cUnk abs=$cAbs');
          }
          if (!_before) {
            must('strict 같은 진한 짝', cLate == 'warningDark' && cMiss == 'textSecondary' && cUnk == 'purple' && cAbs == 'errorDark',
                '$cLate $cMiss $cUnk $cAbs');
            must('strict 넘침 0', overflows.isEmpty, overflows.join(' | '));
          }
          must('미처리 framework 예외 0', fwErrors.isEmpty, '$fwErrors');
          final exc = t.takeException();
          _out('D426 $tok done state=${st.key} mode=$mode captures=$shots overflows=${overflows.length} exc=${exc != null} ovfRaw=${overflows.isEmpty ? '-' : base64Url.encode(utf8.encode(overflows.join('\n'))).replaceAll('=', '')}');
          must('끝 예외 0', exc == null, '$exc');
        } catch (e) {
          _anyFail = true;
          rethrow;
        }
      }, skip: !_optIn);
    }
  }
}
