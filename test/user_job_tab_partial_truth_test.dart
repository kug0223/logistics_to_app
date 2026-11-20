import 'support/visible_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/to_filter_state.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/job_posting_screen.dart';
import 'package:ALfit/screens/user/tabs/user_job_tab.dart';
import 'package:ALfit/screens/user/tabs/user_job_tab_reads.dart';
import 'package:ALfit/screens/user/user_tab_scope.dart';
import 'package:ALfit/utils/format_helper.dart';
// [DU208/209 K1] 이번 진단·교정 전용 import — 기존 시험은 쓰지 않는다.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/widgets/calendar/carrot_style_calendar.dart';

/// [R7-P2-2 P22-L/N] 일자리 탭이 **부분 결과를 "없음"으로 말하지 않는가**,
/// 그리고 목록에서 고른 하루가 상세까지 살아 있는가.
///
///   production 위젯을 읽기 경계 한 칸만 갈아끼워 돌린다. 페이지는 서버가
///   나눠 주고 날짜는 클라이언트가 거른다 — 그 사이가 이번 검증 대상이다.

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp(
          {String? name, FirebaseOptions? options}) async =>
      _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
        accountStatus: 'active',
      );
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

final DateTime _today = FormatHelper.toKstDate(DateTime.now());
DateTime _day(int o) => _today.add(Duration(days: o));

/// 장기(contract) 공고 — 목록의 날짜 필터는 `date ~ endDate` 겹침으로 본다.
TOModel _to({
  required String id,
  required String title,
  required DateTime start,
  required DateTime end,
}) =>
    TOModel(
      id: id,
      businessId: 'biz1',
      businessName: '강남 물류센터',
      type: 'contract',
      title: title,
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 3,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      rangeStart: start,
      rangeEnd: end,
      createdAt: _day(-5),
      statusUpdatedAt: _day(-5),
    );

/// 페이지를 나눠 주는 서버 흉내 — 날짜는 **서버가 거르지 않는다**(현행 계약).
UserJobTabReads _reads({
  required List<List<TOModel>> pages,
  Map<String, int>? calls,
  Object? firstPageError,
}) {
  return UserJobTabReads(
    publishedTOsPaged: ({String? lastToId, TOFilterState? filter}) async {
      calls?['paged'] = (calls?['paged'] ?? 0) + 1;
      if (lastToId == null && firstPageError != null) throw firstPageError;
      final idx = lastToId == null ? 0 : int.parse(lastToId);
      final items = idx < pages.length ? pages[idx] : <TOModel>[];
      final hasMore = idx + 1 < pages.length;
      return {
        'items': items,
        'lastToId': hasMore ? '${idx + 1}' : null,
        'hasMore': hasMore,
      };
    },
    myApplications: (uid) async => const <ApplicationModel>[],
    tosByIds: (ids) async => const <TOModel>[],
  );
}

Future<void> _pump(
  WidgetTester tester, {
  required UserJobTabReads reads,
  DateTime? pendingJobDate,
  Size size = const Size(390, 1400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));

  DateTime? pending = pendingJobDate;
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        // 홈 날짜 CTA 와 같은 경로 — root 가 넘겨 주고 탭이 소비한다.
        home: UserTabScope(
          switchToTab: (_) {},
          switchToTabWithDate: (_, __) {},
          pendingJobDate: pending,
          clearPendingJobDate: () => pending = null,
          pendingScheduleMonth: null,
          clearPendingScheduleMonth: () {},
          switchToScheduleNow: () {},
          child: UserJobTab(reads: reads),
        ),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  // 1페이지에는 **그 날짜가 없는** 공고만, 2페이지에 있다.
  List<List<TOModel>> twoPages() => [
        [
          _to(id: 'p1a', title: '1페이지 공고 A', start: _day(20), end: _day(30)),
          _to(id: 'p1b', title: '1페이지 공고 B', start: _day(21), end: _day(31)),
        ],
        [
          _to(id: 'p2a', title: '2페이지 공고', start: _day(1), end: _day(3)),
        ],
      ];

  testWidgets('UJT-1 첫 페이지가 다 걸러져도 "없습니다"라고 말하지 않는다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(pages: twoPages()),
      pendingJobDate: _day(2), // 홈 날짜 CTA — 1페이지에는 없는 날
    );

    expect(tester.takeException(), isNull);
    expect(findVisibleText('필터 조건에 맞는 공고가 없습니다'), findsNothing,
        reason: '읽지 않은 페이지가 남아 있는데 "없다"고 말하면 지원 기회를 잃는다');
  });

  testWidgets('UJT-2 남은 페이지를 이어 읽어 그 날짜의 공고를 찾아낸다',
      (tester) async {
    final calls = <String, int>{};
    await _pump(
      tester,
      reads: _reads(pages: twoPages(), calls: calls),
      pendingJobDate: _day(2),
    );

    expect(calls['paged'], greaterThanOrEqualTo(2),
        reason: '조건이 첫 페이지를 다 걸러 냈으면 다음 페이지를 읽어야 한다');
    expect(findVisibleText('2페이지 공고'), findsOneWidget,
        reason: '홈에서 고른 날짜의 공고가 목록에 나타나야 한다');
  });

  testWidgets('UJT-3 정말 없을 때(더 읽을 페이지 없음)는 "없습니다"라고 말한다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(pages: [
        [
          _to(id: 'only', title: '유일 공고', start: _day(20), end: _day(30)),
        ],
      ]),
      pendingJobDate: _day(2),
    );

    expect(findVisibleText('필터 조건에 맞는 공고가 없습니다'), findsOneWidget,
        reason: '읽을 것이 남지 않았으면 없다고 말해야 한다 — 양성 대조');
  });

  testWidgets('UJT-4 조회 실패는 "없음"이 아니라 "못 읽음"이다', (tester) async {
    await _pump(
      tester,
      reads: _reads(pages: twoPages(), firstPageError: Exception('network')),
    );

    expect(findVisibleText('공고를 불러오지 못했습니다'), findsOneWidget);
    expect(findVisibleText('등록된 공고가 없습니다'), findsNothing);
    expect(findVisibleText('필터 조건에 맞는 공고가 없습니다'), findsNothing);
    // [DU1 R6] 머리말도 '0개'라고 말하지 않는다 — 오류 본문과 같은 사실
    expect(findVisibleTextContaining('일자리 0개'), findsNothing);
    expect(findVisibleText('일자리를 확인하지 못했어요'), findsOneWidget);
  });

  testWidgets('UJT-5 머리말이 말하는 조건·모집단이 목록과 같다', (tester) async {
    await _pump(
      tester,
      reads: _reads(pages: twoPages()),
      pendingJobDate: _day(2),
    );

    final d = _day(2);
    expect(findVisibleTextContaining('${d.month}월 ${d.day}일'), findsWidgets,
        reason: '보이는 날짜가 실제 적용된 조건이어야 한다');
  });

  testWidgets('UJT-6 목록에서 고른 하루가 공고 상세까지 살아 있다', (tester) async {
    await _pump(
      tester,
      reads: _reads(pages: twoPages()),
      pendingJobDate: _day(2),
    );

    await tester.tap(findVisibleText('2페이지 공고'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final pushed = tester.widget<JobPostingScreen>(
        find.byType(JobPostingScreen, skipOffstage: false));
    expect(pushed.to?.id, 'p2a', reason: '탭한 공고가 그대로 열려야 한다');
    expect(pushed.slotDate, isNotNull,
        reason: '목록이 하루를 고르고 있었으면 상세도 그 하루를 받아야 한다');
    expect(FormatHelper.toKstDate(pushed.slotDate!),
        FormatHelper.toKstDate(_day(2)));
  });

  testWidgets('UJT-7 날짜를 고르지 않았으면 상세에 하루를 넘기지 않는다', (tester) async {
    await _pump(tester, reads: _reads(pages: twoPages()));

    await tester.tap(findVisibleText('1페이지 공고 A'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    final pushed = tester.widget<JobPostingScreen>(
        find.byType(JobPostingScreen, skipOffstage: false));
    expect(pushed.to?.id, 'p1a');
    expect(pushed.slotDate, isNull,
        reason: '고르지 않은 날짜를 상세가 고른 것처럼 만들지 않는다');
  });

  // ══════════════════════════════════════════════════════════
  // N1 — 상세에서 돌아오면 고른 날짜·조건이 그대로인가
  // ══════════════════════════════════════════════════════════

  testWidgets('UJT-8 상세 → 뒤로 → 목록의 선택 날짜·조건·결과가 그대로다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(pages: twoPages()),
      pendingJobDate: _day(2),
    );

    final d = _day(2);
    // 돌아왔을 때와 비교할 "떠나기 전" 상태.
    expect(findVisibleTextContaining('${d.month}월 ${d.day}일'), findsWidgets);
    expect(findVisibleText('2페이지 공고'), findsOneWidget);

    await tester.tap(findVisibleText('2페이지 공고'));
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(JobPostingScreen, skipOffstage: false), findsOneWidget);

    // 실제 navigator 로 뒤로.
    final nav = tester.state<NavigatorState>(find.byType(Navigator).first);
    nav.pop();
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.byType(JobPostingScreen, skipOffstage: false), findsNothing);
    expect(findVisibleTextContaining('${d.month}월 ${d.day}일'), findsWidgets,
        reason: '돌아왔는데 고른 날짜가 풀려 있으면 다시 찾아야 한다');
    expect(findVisibleText('2페이지 공고'), findsOneWidget,
        reason: '조건에 맞던 결과가 그대로여야 한다');
    // 홈이 넘긴 날짜는 **한 번만** 소비된다 — 재진입으로 다시 걸리지 않는다.
    expect(findVisibleText('1페이지 공고 A'), findsNothing);
  });

  for (final size in const [Size(320, 1400), Size(412, 1400)]) {
    for (final scale in const [1.3, 2.0]) {
      testWidgets(
          'UJT-R ${size.width.toInt()}dp × $scale — 조건·목록·CTA 가 예외 없이 그려진다',
          (tester) async {
        await _pump(
          tester,
          reads: _reads(pages: twoPages()),
          pendingJobDate: _day(2),
          size: size,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(findVisibleText('2페이지 공고'), findsOneWidget);
      });
    }
  }

  // [DU209 K1] O100 필터 시트 결과 수(countOf) 교정 — 감사208·후속209.
  //   before: J 교정 전 현재 동작(208 관측)을 guard 로 확인하고 P1–P4 를 캡처한다.
  //   after : K1 6그룹 결과 단언 + 같은 P1–P4 캡처. 208 관측용 블록은 이것으로
  //           바뀌었다(208 판 원본은 E209/baseline/T.before.dart 사본).
  testWidgets('K1-209-before P1–P4 현재 동작 guard·캡처', (tester) async {
    await _k1Before(tester);
  });
  testWidgets('K1-209-after K1 6그룹 결과 단언·P1–P4 캡처', (tester) async {
    await _k1After(tester);
  });

  // [DU210 C209-1] S077 본문 첫 페이지 재조회 실패 진실성 — 감사209·후속210.
  //   before: J 교정 전 현재 동작(이전 목록·이전 수 요약 유지)을 guard 로 확인, F1·F2 캡처.
  //   after : F1 조건 변경 실패 / F2 같은 조건 새로고침 실패 / F3 추가 페이지 실패 보존 단언.
  testWidgets('C210-before F1·F2 현재 동작 guard·캡처', (tester) async {
    await _c210Before(tester);
  });
  testWidgets('C210-after F1–F3 결과 단언·F1·F2 캡처', (tester) async {
    await _c210After(tester);
  });
}

// ═══════════════════════════════════════════════════════════════════
// [DU209 K1] 교정 전/후 공용 helper — 기존 _reads/_pump 와 분리한다.
//   fake 는 서버 재조회 조건(type 등)·로컬 날짜·입력/반환 cursor·응답 ID/날짜·
//   hasMore 를 기록하고, 조건별로 다른 결정적 응답을 준다. 계약 밖 호출은
//   violation 으로 남기고 throw 한다(화면 catch 가 그것을 '조회 실패'로 바꾸지
//   못하게 guard 가 본다). failOn: 그 번호의 호출만 network 예외(fail-once).
//   hold: 그 번호의 응답을 Completer 가 풀릴 때까지 늦춘다(로딩 중 시트).
// ═══════════════════════════════════════════════════════════════════

String _k1Key(DateTime d) => FormatHelper.toKstDateKey(d);

class _K1Srv {
  _K1Srv(this.pagesByType,
      {this.failOn = const {},
      this.hold = const {},
      this.pagesByCall = const {}});

  final Map<String?, List<List<TOModel>>> pagesByType;
  final Set<int> failOn;
  final Map<int, Completer<void>> hold;

  /// [DU210] 그 번호의 **첫 페이지 호출**에만 쓰는 응답(새 성공 ID 확인용).
  ///   cursor 가 있는 호출에 걸리면 계약 위반이다.
  final Map<int, List<List<TOModel>>> pagesByCall;
  final List<Map<String, Object?>> log = [];
  final List<String> violations = [];

  Never _bad(Map<String, Object?> e, String why) {
    violations.add(why);
    e['result'] = 'violation:$why';
    print('K1SRV ${jsonEncode(e)}');
    throw StateError('K1 fake contract: $why');
  }

  UserJobTabReads reads() => UserJobTabReads(
        publishedTOsPaged: ({String? lastToId, TOFilterState? filter}) async {
          final f = filter ?? const TOFilterState();
          final n = log.length + 1;
          final dr = f.dateRange;
          final e = <String, Object?>{
            'n': n,
            'type': f.type,
            'city': f.city,
            'district': f.district,
            'keyword': f.keyword,
            'fav': f.showFavoritesOnly,
            'localDate':
                dr == null ? null : '${_k1Key(dr.start)}~${_k1Key(dr.end)}',
            'cursor': lastToId,
          };
          log.add(e);
          if (f.city != null ||
              f.district != null ||
              (f.keyword ?? '').isNotEmpty ||
              f.showFavoritesOnly) {
            _bad(e, 'unexpected-condition');
          }
          final h = hold[n];
          if (h != null) {
            e['held'] = true;
            await h.future;
          }
          if (failOn.contains(n)) {
            e['result'] = 'throw-network';
            print('K1SRV ${jsonEncode(e)}');
            throw Exception('k1-network');
          }
          final override = pagesByCall[n];
          if (override != null) {
            e['override'] = true;
            if (lastToId != null) _bad(e, 'override-with-cursor');
          }
          final pages = override ??
              pagesByType[f.type] ??
              _bad(e, 'no-fixture-${f.type}');
          if (pages.isEmpty) _bad(e, 'no-pages');
          final tag = f.type ?? 'all';
          var idx = 0;
          if (lastToId != null) {
            final parts = lastToId.split(':');
            if (parts.length != 2 || parts[0] != tag) {
              _bad(e, 'cursor-mismatch');
            }
            // [DU210] 음수·범위 밖·형식 오류 index 도 계약 위반이다(감사209:16).
            final k = int.tryParse(parts[1]);
            if (k == null || k < 1 || k >= pages.length) {
              _bad(e, 'cursor-range');
            }
            idx = k;
          }
          final items = pages[idx];
          final hasMore = idx + 1 < pages.length;
          final next = hasMore ? '$tag:${idx + 1}' : null;
          e['ids'] = items.map((t) => t.id).toList();
          e['dates'] = items.map((t) {
            final end = t.endDate;
            return '${_k1Key(t.date)}~${end == null ? '-' : _k1Key(end)}';
          }).toList();
          e['hasMore'] = hasMore;
          e['nextCursor'] = next;
          e['result'] = 'ok';
          print('K1SRV ${jsonEncode(e)}');
          return <String, dynamic>{
            'items': items,
            'lastToId': next,
            'hasMore': hasMore,
          };
        },
        myApplications: (uid) async => const <ApplicationModel>[],
        tosByIds: (ids) async {
          violations.add('tosByIds');
          throw StateError('K1 fake contract: tosByIds');
        },
      );
}

TOModel _k1C(String id) =>
    _to(id: id, title: 'K1 공고 $id', start: _day(1), end: _day(30));
TOModel _k1One(String id, int o) =>
    _to(id: id, title: 'K1 공고 $id', start: _day(o), end: _day(o));

const _k1FontsNote = 'NotoSansKR Regular+Bold(NotoSansKR·Roboto 이름) · '
    'FlutterTest=NotoSansKR Regular · MaterialIcons(SDK) — 기기 글꼴 아님(근사)';

Future<void> _k1LoadFonts() async {
  Future<ByteData> f(String p) =>
      File(p).readAsBytes().then((b) => ByteData.view(b.buffer));
  const reg = 'assets/fonts/NotoSansKR-Regular.ttf';
  const bold = 'assets/fonts/NotoSansKR-Bold.ttf';
  const icons = 'C:/Users/kug02/flutter/bin/cache/artifacts/material_fonts/'
      'materialicons-regular.otf';
  await (FontLoader('NotoSansKR')
        ..addFont(f(reg))
        ..addFont(f(bold)))
      .load();
  await (FontLoader('Roboto')
        ..addFont(f(reg))
        ..addFont(f(bold)))
      .load();
  await (FontLoader('FlutterTest')..addFont(f(reg))).load();
  await (FontLoader('MaterialIcons')..addFont(f(icons))).load();
}

/// [DU209 K1] 교정 전/후가 같은 하네스·fixture·조작으로 P1–P4 에 도달하게 하는 묶음.
class _K1H {
  _K1H(this.tester, {required this.mode, required this.pumpLimit, required this.tapLimit});

  final WidgetTester tester;
  final String mode;
  final int pumpLimit;
  final int tapLimit;
  static const double vw = 390;
  static const double vh = 844;
  final GlobalKey key = GlobalKey();
  late _K1Srv srv;
  int pumps = 0;
  int taps = 0;
  int pngs = 0;
  List<String> titles = [];
  final List<String> steps = [];
  final DateTime d0 = FormatHelper.toKstDate(DateTime.now());
  final DateTime d2 = _day(2);

  Finder get sheetF => find.byType(BottomSheet);
  Finder inSheet(Finder m) => find.descendant(of: sheetF.first, matching: m);
  Finder quick(String label) => find.descendant(
      of: find.byWidgetPredicate((w) =>
          w is SingleChildScrollView && w.scrollDirection == Axis.horizontal),
      matching: find.text(label));
  Finder get applyBtn => inSheet(find.byType(ElevatedButton));
  bool vis(String s) => findVisibleText(s).evaluate().isNotEmpty;
  String get d2Row => '${d2.month}/${d2.day} ~ ${d2.month}/${d2.day}';

  void budget() {
    pumps++;
    expect(pumps, lessThanOrEqualTo(pumpLimit),
        reason: 'K1 $mode pump 예산 $pumpLimit 초과');
  }

  Future<void> settle(int n) async {
    for (var i = 0; i < n; i++) {
      budget();
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  void guard(String step) {
    expect(tester.takeException(), isNull, reason: 'K1 $step 예외·overflow');
    expect(srv.violations, isEmpty, reason: 'K1 $step fake 계약 위반');
  }

  Future<void> start() async {
    tester.view.physicalSize = const Size(vw, vh);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.runAsync(_k1LoadFonts);
    expect(tester.takeException(), isNull, reason: 'K1 글꼴 등록');
    final dev = DateTime.now();
    print('K1ENV ${jsonEncode({
          'mode': mode,
          'utc': dev.toUtc().toIso8601String(),
          'tz': dev.timeZoneName,
          'offsetMin': dev.timeZoneOffset.inMinutes,
          'd0': _k1Key(d0),
          'd1': _k1Key(_day(1)),
          'd2': _k1Key(d2),
          'viewport': '390x844@1.0',
          'textScale': 1.0,
          'theme': 'ThemeData()',
          'fonts': _k1FontsNote,
          'out': Platform.environment['K1_209_OUT'] ?? '',
        })}');
    expect(d0, _today, reason: 'K1 D0 가 파일 D0 와 다르다(자정 경계)');
  }

  void end() {
    expect(FormatHelper.toKstDate(DateTime.now()), d0,
        reason: 'K1 자정 경계를 넘었다');
    print('K1END ${jsonEncode({
          'mode': mode,
          'pumps': pumps,
          'taps': taps,
          'pngs': pngs,
          'utc': DateTime.now().toUtc().toIso8601String(),
        })}');
  }

  Future<void> mount(_K1Srv s) async {
    srv = s;
    steps.clear();
    budget();
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(1);
    budget();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
          ChangeNotifierProvider<NotificationProvider>(
              create: (_) => NotificationProvider()),
        ],
        child: RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            locale: const Locale('ko', 'KR'),
            supportedLocales: const [Locale('ko', 'KR'), Locale('en', 'US')],
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            theme: ThemeData(),
            builder: (ctx, child) => MediaQuery(
              data: MediaQuery.of(ctx)
                  .copyWith(textScaler: TextScaler.linear(1.0)),
              child: child!,
            ),
            home: UserTabScope(
              switchToTab: (_) {},
              switchToTabWithDate: (_, __) {},
              pendingJobDate: null,
              clearPendingJobDate: () {},
              pendingScheduleMonth: null,
              clearPendingScheduleMonth: () {},
              switchToScheduleNow: () {},
              child: UserJobTab(reads: s.reads()),
            ),
          ),
        ),
      ),
    );
    await settle(10);
    expect(Localizations.localeOf(tester.element(find.byType(UserJobTab))),
        const Locale('ko', 'KR'),
        reason: 'K1 resolved locale');
    guard('mount');
  }

  String sheetType() {
    for (final l in const ['전체', '단기', '장기']) {
      final f = inSheet(find.text(l));
      if (f.evaluate().length == 1 &&
          tester.widget<Text>(f).style?.color == Colors.white) {
        return l;
      }
    }
    return 'none';
  }

  String dateRowText() {
    if (inSheet(find.text('전체 날짜')).evaluate().isNotEmpty) return '전체 날짜';
    if (inSheet(find.text(d2Row)).evaluate().isNotEmpty) return d2Row;
    return 'other';
  }

  Map<String, Object?> sheetState() {
    if (sheetF.evaluate().isEmpty) return {'open': false};
    expect(applyBtn, findsOneWidget, reason: 'K1 시트 적용 버튼은 1개');
    final b = tester.widget<ElevatedButton>(applyBtn);
    final t = tester.widget<Text>(
        find.descendant(of: applyBtn, matching: find.byType(Text)));
    return {
      'open': true,
      'label': t.data,
      'enabled': b.onPressed != null,
      'type': sheetType(),
      'dateRow': dateRowText(),
    };
  }

  void obs(String kase, String step) {
    print('K1OBS ${jsonEncode({
          'mode': mode,
          'case': kase,
          'step': step,
          'utc': DateTime.now().toUtc().toIso8601String(),
          'pumps': pumps,
          'taps': taps,
          'calls': srv.log.length,
          'last': srv.log.isEmpty ? null : srv.log.last,
          'steps': List<String>.from(steps),
          'sheet': sheetState(),
          'main': {
            'empty_none': vis('등록된 공고가 없습니다'),
            'empty_filter': vis('필터 조건에 맞는 공고가 없습니다'),
            'fail': vis('공고를 불러오지 못했습니다'),
            'partial': vis('아직 이 조건의 공고를 찾지 못했어요'),
            'more': vis('더 많은 공고 보기'),
            'retry': vis('다시 시도'),
          },
          'titles': titles.where(vis).toList(),
        })}');
  }

  void tapCount(String what) {
    taps++;
    steps.add(what);
    expect(taps, lessThanOrEqualTo(tapLimit),
        reason: 'K1 $mode tap 예산 $tapLimit 초과');
  }

  Future<void> tapOn(Finder f, String what, {int wait = 2}) async {
    expect(f, findsOneWidget, reason: 'K1 $what 후보는 1개');
    final r = tester.getRect(f);
    expect(r.left >= 0 && r.top >= 0 && r.right <= vw && r.bottom <= vh,
        isTrue,
        reason: 'K1 $what 이 화면 밖 $r');
    tapCount(what);
    await tester.tap(f);
    await settle(wait);
    guard(what);
  }

  Future<void> openSheet(String kase) async {
    await tapOn(find.byIcon(Icons.tune), '$kase 필터 열기', wait: 5);
    expect(sheetF, findsOneWidget, reason: 'K1 $kase 시트가 열려야 한다');
  }

  Future<void> closeSheet(String kase) async {
    tapCount('$kase 바깥 탭 닫기');
    await tester.tapAt(const Offset(vw / 2, 8));
    await settle(5);
    expect(sheetF, findsNothing, reason: 'K1 $kase 시트가 닫혀야 한다');
    guard('$kase 닫기');
  }

  void expectSheet(String kase, String label, bool enabled) {
    final s = sheetState();
    expect(s['open'], isTrue, reason: 'K1 $kase 시트 열림');
    expect(s['label'], label, reason: 'K1 $kase 라벨');
    expect(s['enabled'], enabled, reason: 'K1 $kase 활성');
    obs(kase, 'sheet');
  }

  Future<void> apply(String kase) async {
    expect(sheetState()['enabled'], isTrue, reason: 'K1 $kase 적용 가능');
    await tapOn(applyBtn, '$kase 적용', wait: 8);
    expect(sheetF, findsNothing, reason: 'K1 $kase 적용 뒤 시트 닫힘');
    obs(kase, 'applied');
  }

  void expectCall(String kase, int calls,
      {String? type, String? cursor, String result = 'ok', List<String>? ids}) {
    expect(srv.log.length, calls, reason: 'K1 $kase 호출 수');
    final l = srv.log.last;
    expect(l['type'], type, reason: 'K1 $kase 요청 type');
    expect(l['cursor'], cursor, reason: 'K1 $kase 입력 cursor');
    expect(l['result'], result, reason: 'K1 $kase 결과');
    if (ids != null) expect(l['ids'], ids, reason: 'K1 $kase 응답 ID');
  }

  /// 달력에서 D+2 를 하루 범위로 고른다. 같은 숫자 칸 중 **포커스 달** 칸만 남긴다
  ///   (다른 달 칸은 grey300 — carrot_style_calendar.dart:401–402). 고른 뒤 시작·종료
  ///   날짜 전문('M월 d일')과 시트 날짜 행 전문을 확인한다.
  Future<void> pickD2(String kase, Finder opener) async {
    await tapOn(opener, '$kase 날짜 열기', wait: 5);
    final cal = find.byType(CarrotStyleCalendar);
    expect(cal, findsOneWidget, reason: 'K1 $kase 달력');
    final picker = find.ancestor(of: cal, matching: find.byType(BottomSheet));
    Finder cell() {
      final all = find.descendant(of: cal, matching: find.text('${d2.day}'));
      final mine = all.evaluate().where((el) =>
          (el.widget as Text).style?.color != AppColors.grey300).toList();
      expect(mine.length, 1,
          reason: 'K1 $kase 포커스 달 D+2 칸은 1개(전체 후보 ${all.evaluate().length})');
      final target = mine.single;
      return find.byElementPredicate((el) => identical(el, target));
    }

    steps.add('$kase D+2 후보 ${find.descendant(of: cal, matching: find.text('${d2.day}')).evaluate().length}');
    await tapOn(cell(), '$kase D+2 시작');
    await tapOn(cell(), '$kase D+2 끝');
    final full = '${d2.month}월 ${d2.day}일';
    expect(find.descendant(of: picker, matching: find.text(full)),
        findsNWidgets(2),
        reason: 'K1 $kase 시작·종료가 $full');
    final done = find.widgetWithText(ElevatedButton, '선택 완료');
    expect(tester.widget<ElevatedButton>(done).onPressed, isNotNull,
        reason: 'K1 $kase 하루 범위 확정');
    await tapOn(done, '$kase 선택 완료', wait: 5);
    expect(cal, findsNothing, reason: 'K1 $kase 달력 닫힘');
  }

  Map<String, Object?> geometry(String id) {
    List<double> r(Finder f) {
      final x = tester.getRect(f);
      return [x.left, x.top, x.right, x.bottom];
    }

    final textF = find.descendant(of: applyBtn, matching: find.byType(RichText));
    final rp = tester.renderObject<RenderParagraph>(textF);
    final plain = rp.text.toPlainText();
    final boxes = rp.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: plain.length));
    final scrolls = tester
        .stateList<ScrollableState>(find.byType(Scrollable))
        .map((s) => s.position.hasPixels ? s.position.pixels : -1.0)
        .toList();
    final pad = tester.view.padding;
    final ins = tester.view.viewInsets;
    return {
      'id': id,
      'mode': mode,
      'utc': DateTime.now().toUtc().toIso8601String(),
      'd0': _k1Key(d0),
      'd2': _k1Key(d2),
      'viewport': '390x844',
      'dpr': tester.view.devicePixelRatio,
      'textScaler': 1.0,
      'inset': [pad.left, pad.top, pad.right, pad.bottom, ins.left, ins.top, ins.right, ins.bottom],
      'theme': 'ThemeData()',
      'fonts': _k1FontsNote,
      'locale': Localizations.localeOf(tester.element(find.byType(UserJobTab)))
          .toString(),
      'sheet': sheetState(),
      'calls': srv.log.length,
      'last': srv.log.isEmpty ? null : srv.log.last,
      'steps': List<String>.from(steps),
      'rects': {
        'bottomSheet': r(sheetF.first),
        'applyButton': r(applyBtn),
        'applyText': r(textF),
        'dateRowLabel': r(inSheet(find.text(dateRowText()))),
        'sortLatest': r(inSheet(find.text('최신순'))),
        'sortDeadline': r(inSheet(find.text('마감임박순'))),
        'typeAll': r(inSheet(find.text('전체'))),
      },
      'labelPlain': plain,
      'labelLines': boxes.map((b) => b.top.round()).toSet().length,
      'labelExceed': rp.didExceedMaxLines,
      'scrolls': scrolls,
    };
  }

  /// 적용 전 정지 화면을 PNG 로 남긴다(잉크·전환이 끝나도록 1.5초 정지 뒤).
  Future<void> capture(String id) async {
    await settle(15);
    guard('$id 캡처 전');
    expect(pngs, lessThan(4), reason: 'K1 $mode PNG 예산 4 초과');
    final dir = Platform.environment['K1_209_OUT'] ?? '';
    expect(dir.isNotEmpty, isTrue, reason: 'K1 K1_209_OUT 없음');
    final meta = geometry(id);
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = File('$dir/$id.png');
      if (out.existsSync()) throw StateError('K1 캡처를 덮지 않는다: ${out.path}');
      out.writeAsBytesSync(bytes!.buffer.asUint8List());
      final side = File('$dir/$id.json');
      if (side.existsSync()) throw StateError('K1 sidecar 를 덮지 않는다: ${side.path}');
      side.writeAsStringSync(jsonEncode(meta));
    });
    pngs++;
    guard('$id 캡처');
    expect(File('$dir/$id.png').existsSync(), isTrue, reason: 'K1 $id PNG 기록');
    print('K1PNG ${jsonEncode({'id': id, 'label': (meta['sheet'] as Map)['label']})}');
  }

  // ── P1–P4 도달(교정 전/후 공용 — 같은 fixture·같은 조작) ──

  Future<void> toP1() async {
    titles = ['K1 공고 k2a', 'K1 공고 k2b', 'K1 공고 k2c'];
    await mount(_K1Srv({
      null: [
        [_k1C('k2a'), _k1C('k2b'), _k1C('k2c')]
      ],
      'flex': [<TOModel>[]],
      'contract': [
        [_k1C('k2a'), _k1C('k2b'), _k1C('k2c')]
      ],
    }));
    expectCall('P1 mount', 1, ids: ['k2a', 'k2b', 'k2c']);
    expect(titles.every(vis), isTrue, reason: 'P1 초기 양수 3');
    obs('P1', 'mounted');
    await tapOn(quick('단기'), 'P1 빠른 칩 단기', wait: 6);
    expectCall('P1 단기', 2, type: 'flex', ids: const []);
    expect(vis('필터 조건에 맞는 공고가 없습니다'), isTrue, reason: 'P1 성공 0 도달');
    await openSheet('P1');
    expect(sheetType(), '단기', reason: 'P1 시트 임시 유형=단기');
    await tapOn(inSheet(find.text('초기화')), 'P1 시트 초기화');
    expect(sheetType(), '전체', reason: 'P1 초기화 뒤 임시 유형=전체');
    expect(dateRowText(), '전체 날짜');
    expect(srv.log.length, 2, reason: 'P1 선택만으로 조회 0');
    obs('P1', 'sheet-reset');
  }

  Future<void> toP2() async {
    titles = ['K1 공고 k3a', 'K1 공고 k3b'];
    await mount(_K1Srv({
      null: [
        [_k1One('k3a', 1)],
        [_k1One('k3b', 2)]
      ],
    }));
    expectCall('P2 mount', 1, ids: ['k3a']);
    expect(srv.log.last['nextCursor'], 'all:1');
    expect(vis('K1 공고 k3a') && !vis('K1 공고 k3b') && vis('더 많은 공고 보기'),
        isTrue,
        reason: 'P2 부분 상태(첫 페이지 D+1·남은 페이지)');
    obs('P2', 'mounted');
    await openSheet('P2');
    await pickD2('P2', inSheet(find.text('전체 날짜')));
    expect(dateRowText(), d2Row, reason: 'P2 시트 날짜 행 전문');
    expect(sheetType(), '전체');
    expect(srv.log.length, 1, reason: 'P2 선택만으로 조회 0');
    obs('P2', 'sheet-d2');
  }

  Future<void> toP3() async {
    titles = ['K1 공고 k5a'];
    await mount(_K1Srv({
      null: [
        [_k1C('k5a')]
      ],
    }, failOn: const {1}));
    expectCall('P3 mount', 1, result: 'throw-network');
    expect(vis('공고를 불러오지 못했습니다') && vis('다시 시도'), isTrue,
        reason: 'P3 실패 상태');
    obs('P3', 'mounted');
    await openSheet('P3');
    expect(sheetType(), '전체', reason: 'P3 같은 조건(전체)');
    expect(dateRowText(), '전체 날짜');
    obs('P3', 'sheet');
  }

  Future<void> toP4() async {
    titles = ['K1 공고 k4a', 'K1 공고 k4b', 'K1 공고 k4c'];
    await mount(_K1Srv({
      null: [
        [_k1C('k4a'), _k1C('k4b'), _k1C('k4c')]
      ],
      'flex': [<TOModel>[]],
    }));
    expectCall('P4 mount', 1, ids: ['k4a', 'k4b', 'k4c']);
    expect(titles.every(vis), isTrue, reason: 'P4 현재 모집단 양수 3');
    obs('P4', 'mounted');
    await openSheet('P4');
    await tapOn(inSheet(find.text('단기')), 'P4 시트 단기');
    expect(sheetType(), '단기', reason: 'P4 임시 유형=단기(미조회)');
    expect(srv.log.length, 1, reason: 'P4 선택만으로 조회 0');
    obs('P4', 'sheet-flex');
  }
}

/// before: J 교정 전. 208 관측(현재 동작)을 guard 로 확인하고 P1–P4 를 찍는다.
///   교정 기대를 일부러 실패시키지 않는다.
Future<void> _k1Before(WidgetTester tester) async {
  final h = _K1H(tester, mode: 'before', pumpLimit: 300, tapLimit: 15);
  await h.start();
  void cur(String p, String label, bool enabled) {
    final s = h.sheetState();
    expect(s['label'], label, reason: 'before $p 현재 라벨(208 관측)');
    expect(s['enabled'], enabled, reason: 'before $p 현재 활성(208 관측)');
  }

  await h.toP1();
  cur('P1', '조건에 맞는 공고 없음', false);
  await h.capture('P1-before');
  await h.toP2();
  cur('P2', '조건에 맞는 공고 없음', false);
  await h.capture('P2-before');
  await h.toP3();
  cur('P3', '조건에 맞는 공고 없음', false);
  await h.capture('P3-before');
  await h.toP4();
  cur('P4', '3개 일자리 보기', true);
  await h.capture('P4-before');
  h.end();
}

/// after: J 교정 후. K1 6그룹 결과 단언 + 같은 P1–P4 캡처.
Future<void> _k1After(WidgetTester tester) async {
  final h = _K1H(tester, mode: 'after', pumpLimit: 450, tapLimit: 40);
  await h.start();

  // ── K1-1 성공·현재·완전 0 = 알려진 0 ──
  h.titles = [];
  await h.mount(_K1Srv({null: [<TOModel>[]]}));
  h.expectCall('K1-1 mount', 1, ids: const []);
  await h.openSheet('K1-1');
  h.expectSheet('K1-1', '조건에 맞는 공고 없음', false);
  await h.closeSheet('K1-1');
  expect(h.srv.log.length, 1, reason: 'K1-1 추가조회 0');

  // ── K1-2 (P1) flex 성공 0 → 초기화 / 다시 flex 0 → 장기 ──
  await h.toP1();
  h.expectSheet('K1-2 초기화', '적용하기', true);
  await h.capture('P1-after');
  await h.apply('K1-2 초기화');
  h.expectCall('K1-2 초기화 적용', 3, ids: ['k2a', 'k2b', 'k2c']);
  expect(h.titles.every(h.vis), isTrue, reason: 'K1-2 초기화 적용 → 3건');
  await h.tapOn(h.quick('단기'), 'K1-2 빠른 칩 단기(재진입)', wait: 6);
  h.expectCall('K1-2 다시 단기', 4, type: 'flex', ids: const []);
  expect(h.vis('필터 조건에 맞는 공고가 없습니다'), isTrue, reason: 'K1-2 다시 flex 0');
  await h.openSheet('K1-2 재진입');
  h.expectSheet('K1-2 재진입 현재 flex(알려진 0)', '조건에 맞는 공고 없음', false);
  await h.tapOn(h.inSheet(find.text('장기')), 'K1-2 시트 장기');
  expect(h.sheetType(), '장기');
  h.expectSheet('K1-2 장기', '적용하기', true);
  await h.apply('K1-2 장기');
  h.expectCall('K1-2 장기 적용', 5, type: 'contract', ids: ['k2a', 'k2b', 'k2c']);
  expect(h.titles.every(h.vis), isTrue, reason: 'K1-2 장기 적용 → 3건');

  // ── K1-3 (P2) 부분 모집단 시트 D+2 → 시트 적용 자체로 이어읽기 ──
  await h.toP2();
  h.expectSheet('K1-3 D+2', '적용하기', true);
  await h.capture('P2-after');
  await h.apply('K1-3 D+2');
  h.expectCall('K1-3 이어읽기', 2, cursor: 'all:1', ids: ['k3b']);
  expect(h.srv.log.last['localDate'], '${_k1Key(h.d2)}~${_k1Key(h.d2)}');
  expect(h.vis('K1 공고 k3b') && !h.vis('K1 공고 k3a'), isTrue,
      reason: 'K1-3 시트 적용으로 D+2 공고 도달');
  expect(find.text('${h.d2.month}/${h.d2.day}~${h.d2.month}/${h.d2.day}'),
      findsOneWidget,
      reason: 'K1-3 적용된 날짜 칩 전문');

  // ── K1-4 (P4) 서버조건 변경 → 이전 수 미표시 → 적용 → 실제 0 → 알려진 0 ──
  await h.toP4();
  h.expectSheet('K1-4 단기', '적용하기', true);
  expect(h.inSheet(find.textContaining('3개')).evaluate(), isEmpty,
      reason: 'K1-4 이전 모집단 3개 미표시');
  await h.capture('P4-after');
  await h.apply('K1-4 단기');
  h.expectCall('K1-4 flex 조회', 2, type: 'flex', ids: const []);
  expect(h.vis('필터 조건에 맞는 공고가 없습니다'), isTrue, reason: 'K1-4 실제 0');
  await h.openSheet('K1-4 재열기');
  h.expectSheet('K1-4 재열기(알려진 0)', '조건에 맞는 공고 없음', false);
  await h.closeSheet('K1-4 재열기');
  expect(h.srv.log.length, 2, reason: 'K1-4 재열기 조회 0');

  // ── K1-5 (P3) fail-once 초기 실패 → 같은 조건 적용 → 첫 페이지 재조회 ──
  await h.toP3();
  h.expectSheet('K1-5 실패', '적용하기', true);
  await h.capture('P3-after');
  await h.apply('K1-5 같은 조건');
  h.expectCall('K1-5 재조회', 2, ids: ['k5a']);
  expect(h.vis('공고를 불러오지 못했습니다'), isFalse, reason: 'K1-5 실패 문구 해제');
  expect(h.vis('K1 공고 k5a'), isTrue, reason: 'K1-5 재조회 결과');
  //   변형: 이전 양수 뒤 전체재조회 실패 — [DU210] 이전 목록을 지우고 실패 본문으로 간다
  h.titles = ['K1 공고 k5b', 'K1 공고 k5c', 'K1 공고 k5d', 'K1 공고 k5e'];
  await h.mount(_K1Srv({
    null: [
      [_k1C('k5b'), _k1C('k5c'), _k1C('k5d')]
    ],
    'contract': [
      [_k1C('k5e')]
    ],
  }, failOn: const {2}));
  h.expectCall('K1-5b mount', 1, ids: ['k5b', 'k5c', 'k5d']);
  await h.tapOn(h.quick('장기'), 'K1-5b 빠른 칩 장기(실패)', wait: 6);
  h.expectCall('K1-5b 장기 실패', 2, type: 'contract', result: 'throw-network');
  // [DU210] 첫 페이지 실패는 이전 목록을 지우고 기존 실패 본문·다시 시도로 간다
  //   (원209 기대 '실패 문구 없음'은 E209/baseline·candidate 에 보존).
  expect(h.vis('공고를 불러오지 못했습니다') && h.vis('다시 시도'), isTrue,
      reason: 'K1-5b 첫 페이지 실패 → 실패 본문·다시 시도');
  expect(['K1 공고 k5b', 'K1 공고 k5c', 'K1 공고 k5d'].any(h.vis), isFalse,
      reason: 'K1-5b 이전 제목 비노출');
  expect(h.vis('더 많은 공고 보기'), isFalse, reason: 'K1-5b 더 보기 없음');
  h.obs('K1-5b', 'contract-failed');
  await h.openSheet('K1-5b');
  expect(h.sheetType(), '장기');
  h.expectSheet('K1-5b 첫 페이지 실패', '적용하기', true);
  await h.apply('K1-5b 같은 조건');
  h.expectCall('K1-5b 재조회', 3, type: 'contract', ids: ['k5e']);
  expect(h.vis('K1 공고 k5e'), isTrue, reason: 'K1-5b 재조회 결과');

  // ── K1-6 완전 N / 부분 N 이상 / 같은 조건 적용 재조회 0 / 로딩 중 snapshot ──
  h.titles = ['K1 공고 k6a', 'K1 공고 k6b'];
  await h.mount(_K1Srv({
    null: [
      [_k1C('k6a'), _k1C('k6b')]
    ],
  }));
  h.expectCall('K1-6 완전 mount', 1, ids: ['k6a', 'k6b']);
  await h.openSheet('K1-6 완전');
  h.expectSheet('K1-6 완전', '2개 일자리 보기', true);
  await h.closeSheet('K1-6 완전');
  h.titles = ['K1 공고 k6c', 'K1 공고 k6d', 'K1 공고 k6e'];
  await h.mount(_K1Srv({
    null: [
      [_k1C('k6c'), _k1C('k6d')],
      [_k1C('k6e')]
    ],
  }));
  h.expectCall('K1-6 부분 mount', 1, ids: ['k6c', 'k6d']);
  await h.openSheet('K1-6 부분');
  h.expectSheet('K1-6 부분', '2개 이상의 일자리 보기', true);
  await h.apply('K1-6 부분 같은 조건');
  expect(h.srv.log.length, 1, reason: 'K1-6 같은 성공 조건 적용의 전체재조회 0');
  expect(h.vis('K1 공고 k6c') && h.vis('K1 공고 k6d'), isTrue);
  final gate = Completer<void>();
  h.titles = ['K1 공고 k6f', 'K1 공고 k6g'];
  await h.mount(_K1Srv({
    null: [
      [_k1C('k6f'), _k1C('k6g')]
    ],
  }, hold: {1: gate}));
  expect(h.srv.log.length, 1);
  expect(h.srv.log.last['held'], isTrue, reason: 'K1-6 로딩 중(응답 보류)');
  expect(h.titles.any(h.vis), isFalse, reason: 'K1-6 로딩 중 목록 없음');
  await h.openSheet('K1-6 로딩');
  h.expectSheet('K1-6 로딩 중', '적용하기', true);
  gate.complete();
  await h.settle(5);
  h.guard('K1-6 응답 도착');
  expect(h.srv.log.last['result'], 'ok');
  h.expectSheet('K1-6 개방 중 응답 도착(개방 시 고정)', '적용하기', true);
  await h.closeSheet('K1-6 로딩');
  expect(h.titles.every(h.vis), isTrue, reason: 'K1-6 응답 반영');
  await h.openSheet('K1-6 재열기');
  h.expectSheet('K1-6 재열기', '2개 일자리 보기', true);
  await h.closeSheet('K1-6 재열기');
  expect(h.srv.log.length, 1, reason: 'K1-6 로딩 단계 추가조회 0');
  h.end();
}

// ═══════════════════════════════════════════════════════════════════
// [DU210 C209-1] S077 본문 첫 페이지 재조회 실패 진실성 — 교정 전/후 공용.
//   _K1H(DU209 하네스)·_K1Srv 를 그대로 쓰고, 본문 캡처·기하만 여기 둔다.
//   mask(실행 전 고정): 209 PNG 의 검색 헤더 끝 구분선(y=202) 다음 줄부터
//   화면 하단까지, 반열림 [0,390)x[203,844).
// ═══════════════════════════════════════════════════════════════════

class _C210 {
  _C210(this.h);

  final _K1H h;
  int pngs = 0;

  WidgetTester get t => h.tester;
  Finder get listF => find.byType(ListView);
  Finder get retryF => find.text('다시 시도');
  Finder get moreF => find.text('더 많은 공고 보기');

  List<double> r(Finder f) {
    final x = t.getRect(f);
    return [x.left, x.top, x.right, x.bottom];
  }

  List<double>? r1(Finder f) => f.evaluate().length == 1 ? r(f) : null;

  /// 결과 요약 머리말 — 정상('… 일자리 N개[ 이상]')이거나 실패('일자리를 확인하지 못했어요').
  ///   시트가 닫혀 있을 때만 읽는다(시트 버튼 'N개 일자리 보기'와 섞이지 않게).
  Finder get summaryF => find.byWidgetPredicate((w) {
        if (w is! Text) return false;
        final s = w.data;
        return s != null &&
            (s == '일자리를 확인하지 못했어요' ||
                s.contains(' 일자리 ') ||
                s.startsWith('조건에 맞는 일자리 '));
      });

  String summary() {
    expect(h.sheetF, findsNothing, reason: 'C210 머리말은 시트가 닫힌 뒤 읽는다');
    final els = summaryF.evaluate().toList();
    expect(els.length, 1, reason: 'C210 머리말 후보 1개');
    return (els.single.widget as Text).data!;
  }

  bool chipWhite(String label) {
    final f = h.quick(label);
    return f.evaluate().length == 1 &&
        t.widget<Text>(f).style?.color == Colors.white;
  }

  Map<String, Object?> textInfo(Finder textF) {
    final rp = t.renderObject<RenderParagraph>(
        find.descendant(of: textF, matching: find.byType(RichText)));
    final plain = rp.text.toPlainText();
    final boxes = rp.getBoxesForSelection(
        TextSelection(baseOffset: 0, extentOffset: plain.length));
    return {
      'rect': r(textF),
      'lines': boxes.map((b) => b.top.round()).toSet().length,
      'exceed': rp.didExceedMaxLines,
    };
  }

  void obs(String kase, String step) {
    print('C210OBS ${jsonEncode({
          'mode': h.mode,
          'case': kase,
          'step': step,
          'utc': DateTime.now().toUtc().toIso8601String(),
          'pumps': h.pumps,
          'taps': h.taps,
          'calls': h.srv.log.length,
          'last': h.srv.log.isEmpty ? null : h.srv.log.last,
          'summary': h.sheetF.evaluate().isEmpty ? summary() : '(시트 열림)',
          'fail': h.vis('공고를 불러오지 못했습니다'),
          'retry': h.vis('다시 시도'),
          'more': h.vis('더 많은 공고 보기'),
          'titles': h.titles.where(h.vis).toList(),
          'chips': {for (final l in const ['단기', '장기']) l: chipWhite(l)},
        })}');
  }

  Map<String, Object?> geometry(String id) {
    final chips = <String, Object?>{};
    for (final l in const ['즐겨찾기', '단기', '장기', '날짜', '지역']) {
      final f = h.quick(l);
      if (f.evaluate().length == 1) {
        chips[l] = {'rect': r(f), 'white': chipWhite(l)};
      }
    }
    final failF = findVisibleText('공고를 불러오지 못했습니다');
    final subF = findVisibleTextContaining('네트워크 상태를 확인하고');
    final retryBtn = find.ancestor(
        of: retryF, matching: find.byWidgetPredicate((w) => w is TextButton));
    final scrolls = t
        .stateList<ScrollableState>(find.byType(Scrollable))
        .map((s) => {
              'axis': s.position.axis.name,
              'pixels': s.position.hasPixels ? s.position.pixels : -1.0,
            })
        .toList();
    final pad = t.view.padding;
    final ins = t.view.viewInsets;
    return {
      'id': id,
      'mode': h.mode,
      'utc': DateTime.now().toUtc().toIso8601String(),
      'd0': _k1Key(h.d0),
      'viewport': '390x844',
      'dpr': t.view.devicePixelRatio,
      'textScaler': 1.0,
      'inset': [pad.left, pad.top, pad.right, pad.bottom, ins.left, ins.top, ins.right, ins.bottom],
      'theme': 'ThemeData()',
      'fonts': _k1FontsNote,
      'locale':
          Localizations.localeOf(t.element(find.byType(UserJobTab))).toString(),
      'mask': [0, 203, 390, 844],
      'calls': h.srv.log.length,
      'last': h.srv.log.isEmpty ? null : h.srv.log.last,
      'steps': List<String>.from(h.steps),
      'summary': summary(),
      'summaryText': textInfo(summaryF),
      'unchanged': {
        'appBarTitle': r1(find.text('일자리')),
        'tabBar': r1(find.byType(TabBar)),
        'filterIcon': r1(find.byIcon(Icons.tune)),
        'searchHint': r1(find.text('공고 제목, 사업장명 검색')),
        'chips': chips,
      },
      'failTitle': failF.evaluate().length == 1 ? textInfo(failF) : null,
      'failSub': subF.evaluate().length == 1 ? textInfo(subF) : null,
      'retryButton': retryBtn.evaluate().length == 1 ? r(retryBtn) : null,
      'more': h.vis('더 많은 공고 보기'),
      'titles': h.titles.where(h.vis).toList(),
      'scrolls': scrolls,
    };
  }

  /// 실패 직후 본문 정지 화면을 PNG 로 남긴다(전환·잉크가 끝나도록 1.5초 정지 뒤).
  Future<void> capture(String id) async {
    await h.settle(15);
    h.guard('$id 캡처 전');
    expect(pngs, lessThan(2), reason: 'C210 ${h.mode} PNG 예산 2 초과');
    final dir = Platform.environment['C210_OUT'] ?? '';
    expect(dir.isNotEmpty, isTrue, reason: 'C210 C210_OUT 없음');
    final meta = geometry(id);
    final boundary =
        h.key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = File('$dir/$id.png');
      if (out.existsSync()) throw StateError('C210 캡처를 덮지 않는다: ${out.path}');
      out.writeAsBytesSync(bytes!.buffer.asUint8List());
      final side = File('$dir/$id.json');
      if (side.existsSync()) throw StateError('C210 sidecar 를 덮지 않는다: ${side.path}');
      side.writeAsStringSync(jsonEncode(meta));
    });
    pngs++;
    h.guard('$id 캡처');
    expect(File('$dir/$id.png').existsSync(), isTrue, reason: 'C210 $id PNG 기록');
    print('C210PNG ${jsonEncode({'id': id, 'summary': meta['summary']})}');
  }

  // ── F1·F2 실패 상태 도달(교정 전/후 공용 — 같은 fixture·같은 조작) ──

  Future<void> toF1Failed() async {
    h.titles = ['K1 공고 f1a', 'K1 공고 f1b', 'K1 공고 f1c', 'K1 공고 f1x', 'K1 공고 f1y'];
    await h.mount(_K1Srv({
      null: [
        [_k1C('f1a'), _k1C('f1b'), _k1C('f1c')]
      ],
      'contract': [
        [_k1C('f1x'), _k1C('f1y')]
      ],
    }, failOn: const {2}));
    h.expectCall('F1 mount', 1, ids: ['f1a', 'f1b', 'f1c']);
    expect(summary(), '조건에 맞는 일자리 3개', reason: 'F1 성공 양수');
    obs('F1', 'mounted');
    await h.tapOn(h.quick('장기'), 'F1 빠른 칩 장기', wait: 6);
    h.expectCall('F1 장기 첫 페이지 실패', 2,
        type: 'contract', result: 'throw-network');
    expect(chipWhite('장기'), isTrue, reason: 'F1 현재 칩 장기');
    obs('F1', 'failed');
  }

  Future<void> toF2Failed() async {
    const ids = ['f2a', 'f2b', 'f2c', 'f2d', 'f2e', 'f2f', 'f2g', 'f2h'];
    h.titles = [for (final i in ids) 'K1 공고 $i', 'K1 공고 f2i', 'K1 공고 f2j'];
    await h.mount(_K1Srv({
      null: [
        [for (final i in ids) _k1C(i)]
      ],
    }, failOn: const {2}, pagesByCall: {
      3: [
        [_k1C('f2i'), _k1C('f2j')]
      ],
    }));
    h.expectCall('F2 mount', 1, ids: ids);
    expect(summary(), '조건에 맞는 일자리 8개', reason: 'F2 성공 양수');
    expect(listF, findsOneWidget, reason: 'F2 목록 1개');
    final sc = t.state<ScrollableState>(
        find.descendant(of: listF, matching: find.byType(Scrollable)).first);
    expect(sc.position.pixels, 0.0, reason: 'F2 목록 맨 위');
    expect(sc.position.maxScrollExtent, greaterThan(0.0),
        reason: 'F2 목록이 화면보다 길다(실제 overscroll 당김)');
    final lr = t.getRect(listF);
    expect(lr.top >= 0 && lr.bottom <= _K1H.vh, isTrue, reason: 'F2 목록 화면 안');
    print('C210PULL ${jsonEncode({
          'listRect': [lr.left, lr.top, lr.right, lr.bottom],
          'pixels': sc.position.pixels,
          'maxScrollExtent': sc.position.maxScrollExtent,
          'gesture': 'fling(0,300) v1000 from list center',
        })}');
    obs('F2', 'mounted');
    h.tapCount('F2 목록 당겨 새로고침');
    await t.fling(listF, const Offset(0, 300), 1000);
    await h.settle(20);
    h.guard('F2 새로고침');
    h.expectCall('F2 같은 조건 새로고침 실패', 2, result: 'throw-network');
    obs('F2', 'failed');
  }
}

/// before: J 교정 전. 현재 동작(이전 목록·이전 수 요약 유지)을 guard 로 확인하고 F1·F2 를 찍는다.
///   교정 기대를 일부러 실패시키지 않는다.
Future<void> _c210Before(WidgetTester tester) async {
  final h = _K1H(tester, mode: 'before', pumpLimit: 250, tapLimit: 15);
  final c = _C210(h);
  await h.start();
  print('C210ENV ${jsonEncode({'mode': 'before', 'out': Platform.environment['C210_OUT'] ?? '', 'mask': [0, 203, 390, 844]})}');
  await c.toF1Failed();
  expect(c.summary(), '장기 일자리 3개 이상', reason: 'before F1 현재 머리말(이전 목록 수)');
  expect(['K1 공고 f1a', 'K1 공고 f1b', 'K1 공고 f1c'].every(h.vis), isTrue,
      reason: 'before F1 이전 제목 남음');
  expect(h.vis('공고를 불러오지 못했습니다'), isFalse, reason: 'before F1 실패 본문 없음');
  await c.capture('F1-before');
  await c.toF2Failed();
  expect(c.summary(), '조건에 맞는 일자리 8개 이상', reason: 'before F2 현재 머리말');
  expect(h.vis('K1 공고 f2a'), isTrue, reason: 'before F2 이전 제목 남음');
  expect(h.vis('공고를 불러오지 못했습니다'), isFalse, reason: 'before F2 실패 본문 없음');
  await c.capture('F2-before');
  h.end();
  print('C210END ${jsonEncode({'mode': 'before', 'pumps': h.pumps, 'taps': h.taps, 'pngs': c.pngs})}');
}

/// after: J 교정 후. F1–F3 결과 단언 + 같은 F1·F2 캡처.
Future<void> _c210After(WidgetTester tester) async {
  final h = _K1H(tester, mode: 'after', pumpLimit: 400, tapLimit: 30);
  final c = _C210(h);
  await h.start();
  print('C210ENV ${jsonEncode({'mode': 'after', 'out': Platform.environment['C210_OUT'] ?? '', 'mask': [0, 203, 390, 844]})}');

  void failState(String kase, List<String> oldTitles, List<String> normal) {
    expect(c.summary(), '일자리를 확인하지 못했어요', reason: '$kase 실패 머리말');
    for (final s in normal) {
      expect(h.vis(s), isFalse, reason: '$kase 정상 수 요약 "$s" 비노출');
    }
    expect(oldTitles.any(h.vis), isFalse, reason: '$kase 이전 제목 비노출');
    expect(h.vis('공고를 불러오지 못했습니다') && h.vis('다시 시도'), isTrue,
        reason: '$kase 실패 본문·다시 시도');
    expect(h.vis('더 많은 공고 보기'), isFalse, reason: '$kase 더 보기 없음');
  }

  // ── F1 조건 변경 실패 → 본문 다시 시도 ──
  await c.toF1Failed();
  failState('F1', ['K1 공고 f1a', 'K1 공고 f1b', 'K1 공고 f1c'],
      ['장기 일자리 3개 이상', '장기 일자리 3개']);
  expect(c.chipWhite('장기'), isTrue, reason: 'F1 현재 칩 장기 유지');
  await c.capture('F1-after');
  await h.tapOn(c.retryF, 'F1 다시 시도', wait: 8);
  h.expectCall('F1 다시 시도', 3, type: 'contract', ids: ['f1x', 'f1y']);
  expect(c.summary(), '장기 일자리 2개', reason: 'F1 새 성공 조건·수');
  expect(h.vis('K1 공고 f1x') && h.vis('K1 공고 f1y'), isTrue, reason: 'F1 새 성공 ID');
  expect(h.vis('공고를 불러오지 못했습니다'), isFalse, reason: 'F1 실패 표시 해제');
  c.obs('F1', 'retried');

  // ── F2 같은 조건 새로고침 실패 → 시트 중립 적용 재조회 ──
  await c.toF2Failed();
  failState('F2', [
    for (final i in const ['f2a', 'f2b', 'f2c', 'f2d', 'f2e', 'f2f', 'f2g', 'f2h'])
      'K1 공고 $i'
  ], [
    '조건에 맞는 일자리 8개 이상',
    '조건에 맞는 일자리 8개'
  ]);
  expect(c.listF, findsNothing, reason: 'F2 목록 없음');
  await c.capture('F2-after');
  await h.openSheet('F2');
  h.expectSheet('F2 실패 뒤(알려진 0 아님)', '적용하기', true);
  await h.tapOn(h.inSheet(find.text('단기')), 'F2 시트 단기(선택만)');
  await h.tapOn(h.inSheet(find.text('전체')), 'F2 시트 전체(선택만)');
  await h.closeSheet('F2');
  expect(h.srv.log.length, 2, reason: 'F2 선택·닫기만으로 조회 0');
  await h.openSheet('F2 재열기');
  h.expectSheet('F2 재열기', '적용하기', true);
  await h.apply('F2 같은 조건');
  h.expectCall('F2 같은 조건 재조회', 3, ids: ['f2i', 'f2j']);
  expect(h.srv.log.last['override'], isTrue, reason: 'F2 새 응답(호출 3)');
  expect(h.vis('K1 공고 f2i') && h.vis('K1 공고 f2j'), isTrue, reason: 'F2 새 성공 ID');
  expect(c.summary(), '조건에 맞는 일자리 2개');
  await h.openSheet('F2 성공 뒤');
  h.expectSheet('F2 성공 뒤(확인된 N)', '2개 일자리 보기', true);
  await h.closeSheet('F2 성공 뒤');
  expect(h.srv.log.length, 3, reason: 'F2 재열기 조회 0');

  // ── F3 추가 페이지 실패 보존 ──
  h.titles = ['K1 공고 f3a', 'K1 공고 f3b', 'K1 공고 f3c'];
  await h.mount(_K1Srv({
    null: [
      [_k1C('f3a'), _k1C('f3b')],
      [_k1C('f3c')]
    ],
  }, failOn: const {2}));
  h.expectCall('F3 mount', 1, ids: ['f3a', 'f3b']);
  expect(c.summary(), '조건에 맞는 일자리 2개 이상');
  await h.tapOn(c.moreF, 'F3 더 보기(실패)', wait: 6);
  h.expectCall('F3 추가 실패', 2, cursor: 'all:1', result: 'throw-network');
  expect(h.vis('K1 공고 f3a') && h.vis('K1 공고 f3b'), isTrue, reason: 'F3 확인된 일부 유지');
  expect(c.summary(), '조건에 맞는 일자리 2개 이상', reason: 'F3 현재 요약 유지');
  expect(h.vis('더 많은 공고 보기'), isTrue, reason: 'F3 추가읽기 행동 유지');
  expect(h.vis('공고를 불러오지 못했습니다'), isFalse, reason: 'F3 본문 실패 아님');
  c.obs('F3', 'more-failed');
  await h.openSheet('F3');
  h.expectSheet('F3 부분(추가 실패 뒤)', '2개 이상의 일자리 보기', true);
  await h.closeSheet('F3');
  await h.tapOn(c.moreF, 'F3 더 보기(재시도)', wait: 6);
  h.expectCall('F3 추가 재시도', 3, cursor: 'all:1', ids: ['f3c']);
  for (final ttl in h.titles) {
    expect(findVisibleText(ttl), findsOneWidget, reason: 'F3 $ttl 1회(중복 없음)');
  }
  expect(h.srv.log.where((e) => e['cursor'] == null).length, 1,
      reason: 'F3 첫 페이지 재조회 0');
  expect(c.summary(), '조건에 맞는 일자리 3개');
  c.obs('F3', 'more-retried');
  h.end();
  print('C210END ${jsonEncode({'mode': 'after', 'pumps': h.pumps, 'taps': h.taps, 'pngs': c.pngs})}');
}
