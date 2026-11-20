// [UI-INTEGRATION.33] 대량 사업장 — 급여 화면의 큰 금액(억 단위)·건수(만 단위)·인원(천 단위)이
//   잘리거나(말줄임) 줄어들거나(FittedBox) 넘치지(RenderFlex overflow) 않는다.
//
// 기기 관찰(392·1.0, 합성 fixture 1,234명·12,345건·1,322,099,341원):
//   월 상세 머리 금액 `1,322,099,3…`, 지급 현황 미이체 요약 392·2.0 `RIGHT OVERFLOWED BY 15px`,
//   탭 배지 `8,230` 이 `823` 으로 잘림, 건수에 천 단위 구분 없음.
//
// 측정 자: 번들 NotoSansKR(기본 테스트 폰트는 한글을 30% 넓게 잰다). 배치: 320·1.3 / 392·2.0.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'support/visible_text.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_overview_reads.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_overview_screen.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';
import 'package:ALfit/utils/text_layout.dart';
import 'package:ALfit/widgets/common/app_batch_action_bar.dart';
import 'package:ALfit/widgets/common/app_tab_label.dart';

class _FakeApp extends Fake with MockPlatformInterfaceMixin implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options =>
      const FirebaseOptions(apiKey: 'k', appId: 'a', messagingSenderId: 's', projectId: 'p');
}

class _FakeCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) => _FakeApp();
  @override
  Future<FirebaseAppPlatform> initializeApp({String? name, FirebaseOptions? options}) async => _FakeApp();
  @override
  List<FirebaseAppPlatform> get apps => [_FakeApp()];
}

const _biz = 'biz1';

class _WageAdmin extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'admin1', username: 'admin1', name: '김관리', email: 'admin1@alfit.local',
      role: UserRole.BUSINESS_ADMIN, managedBusinessIds: const [_biz]);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  String? get effectiveBusinessId => null;
  @override
  PermissionCheck checkCurrentBusiness(bool Function(MemberPermissions p) check) => PermissionCheck.allowed;
  @override
  PermissionCheck checkForBusiness(String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
  @override
  bool canForBusiness(String businessId, bool Function(MemberPermissions p) check) => true;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
}

const _font = 'NotoSansKR';
const _layouts = [(Size(320, 1400), 1.3), (Size(392, 1400), 2.0)];

const _total = 1322099341;
const _records = 12345;
const _workers = 1234;
const _pending = 8230; // 미이체 건수(원장)
const _bigOne = 205925891; // 한 사람 합계

Future<void> _loadFont() async {
  final loader = FontLoader(_font);
  for (final f in const ['Regular', 'Bold']) {
    loader.addFont(rootBundle
        .load('assets/fonts/NotoSansKR-$f.ttf')
        .then((b) => ByteData.sublistView(b.buffer.asUint8List())));
  }
  await loader.load();
}

Widget _app(Widget home, double scale) => MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _WageAdmin()),
        ChangeNotifierProvider<NotificationProvider>(create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        theme: ThemeData(fontFamily: _font),
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    );

void _setView(WidgetTester t, Size size) {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
}

Future<void> _settle(WidgetTester t, [int frames = 20]) async {
  for (var i = 0; i < frames; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// 보이는 글자로 [text] 가 있고, 말줄임·줄 수 초과 없이 전부 그려졌다.
void _expectWhole(WidgetTester t, String text) {
  final f = findVisibleText(text);
  expect(f, findsWidgets, reason: '`$text` 가 화면에 없다');
  for (final w in t.widgetList<Text>(f)) {
    expect(w.overflow, isNot(TextOverflow.ellipsis), reason: '`$text` 말줄임');
    final rp = t.renderObject<RenderParagraph>(
        find.descendant(of: find.byWidget(w), matching: find.byType(RichText), matchRoot: true).first);
    expect(rp.didExceedMaxLines, isFalse, reason: '`$text` 잘림');
    // 축소 금지 — 조상에 FittedBox 가 없다.
    expect(find.ancestor(of: find.byWidget(w), matching: find.byType(FittedBox)), findsNothing,
        reason: '`$text` 가 FittedBox 로 줄어든다');
  }
}

// ── 급여 개요·월 상세 ─────────────────────────────────────────────
final int _y = DateTime.now().year;
final int _m = DateTime.now().month;
String get _ym => '$_y-${_m.toString().padLeft(2, '0')}';

PayrollOverviewReads _overviewReads() => PayrollOverviewReads(
      businesses: ({required bool isSubAdmin, required String? effectiveBusinessId, required List<String> managedIds}) async => [
        BusinessModel(id: _biz, name: '합성 대량 사업장', ownerId: 'admin1', businessNumber: '000-00-00000',
            address: '서울', category: '물류', subCategory: '창고', isApproved: true, createdAt: DateTime(2026, 1, 1)),
      ],
      payrollSummaries: ({required String businessId, required int year}) async => [
        {
          'id': '${_biz}_$_ym', 'businessId': _biz, 'yearMonth': _ym, 'year': _y, 'month': _m,
          'totalPayout': _total, 'confirmedCount': _records, 'workerCount': _workers,
          'notTransferredCount': _pending, 'updatedAt': DateTime.now().toIso8601String(),
        }
      ],
      adminAttendances: ({required String businessId, required String yearMonthGte, required String yearMonthLte}) async => (
        items: [
          for (var i = 0; i < _records; i++)
            {
              'id': 'r$i', 'yearMonth': _ym, 'status': 'present', 'userId': 'u${i % _workers}',
              'wageStatus': i < _pending ? 'confirmed' : 'transferred', 'finalWage': 100000,
            }
        ],
        limitReached: false,
      ),
      workerSummaries: (summaryId) async => [
        (id: 'u0', data: {'name': '합성 대량 큰손', 'totalPayout': _bigOne, 'workDays': 32}),
        (id: 'u1', data: {'name': '합성 대량0001', 'totalPayout': 900000, 'workDays': 10}),
      ],
      repairSummary: ({required String businessId, required String yearMonth}) async {},
      todayPaymentCount: (_) async => 0,
    );

// ── 지급 현황(callable 모의) ──────────────────────────────────────
const _ch = 'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
Map<String, Object?> _ts(DateTime d) => {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

/// 두 사람 합계 1,322,099,341원 — 한 사람 9억, 한 사람 4억대.
///   (근태 1건 실수령은 모델이 999,999,999원에서 막는다 — effectiveNetWage clamp. 합계는 막지 않는다.)
List<Map<String, Object?>> _rows() => [
      for (final r in [
        ('A', 'u1', DateTime(2026, 10, 10), DateTime(2026, 10, 13), 900000000, 'weekly'),
        ('B', 'u2', DateTime(2026, 10, 17), DateTime(2026, 10, 18), 422099341, 'next_day'),
      ])
        {
          'id': r.$1, 'userId': r.$2, 'businessId': _biz, 'businessName': '합성 대량 사업장',
          'workDate': _ts(r.$3), 'workType': '분류', 'status': 'present', 'wageStatus': 'confirmed',
          'adminConfirmed': true, 'createdAt': _ts(r.$3), 'paymentDueDate': _ts(r.$4),
          'wageDetail': {'totalAmount': r.$5, 'wageType': 'daily', 'payScheduleType': r.$6},
          'wageAccountSourceBankAccountVersion': 1, 'wageAccountSourceBankbookDocumentVersion': 1,
        }
    ];

Future<ByteData?> _handle(ByteData? data) async {
  final args = (const StandardMessageCodec().decodeMessage(data) as List).first as Map;
  final fn = args['functionName'] as String;
  final p = Map<Object?, Object?>.from(args['parameters'] as Map? ?? const {});
  Object? body;
  switch (fn) {
    case 'callableGetAdminAttendances':
      final s = p['startMs'] as int?, e = p['endMs'] as int?;
      final ws = p['wageStatus'] as String?;
      body = {
        'items': [
          for (final r in _rows())
            if ((s == null || ((r['workDate'] as Map)['_seconds'] as int) * 1000 >= s) &&
                (e == null || ((r['workDate'] as Map)['_seconds'] as int) * 1000 < e) &&
                (ws == null || r['wageStatus'] == ws))
              r
        ],
        'limitReached': false,
      };
    case 'callableGetUsersBatch':
      body = {
        'users': {
          'u1': {'name': '합성 대량 큰손', 'username': 'w1', 'role': 'USER'},
          'u2': {'name': '합성 대량0002', 'username': 'w2', 'role': 'USER'},
        }
      };
    case 'callableGetPayrollReadinessBatch':
      body = {
        'readiness': {
          for (final u in (p['workerUids'] as List).cast<String>())
            u: {'ready': true, 'state': 'READY_AUTO', 'actor': 'NONE', 'accountVersion': 1, 'bankbookVersion': 1}
        },
        'failed': <String>[],
      };
    default:
      body = {'requests': <Object?>[], 'items': <Object?>[]};
  }
  return const StandardMessageCodec().encodeMessage(<Object?>[body]);
}

Future<void> _mountDashboard(WidgetTester t, Size size, double scale, {required bool all}) async {
  _setView(t, size);
  t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, _handle);
  addTearDown(() => t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, null));
  await t.pumpWidget(_app(
      PayrollPaymentDashboardScreen(
          businessId: _biz, businessName: '합성 대량 사업장', year: 2026, month: 10, showAllOutstanding: all),
      scale));
  await _settle(t, 40);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await _loadFont();
  });

  test('LN-0 TextLayout.amount — 쉼표 뒤에서만 끊고 보이는 글자는 그대로', () {
    const s = '1,322,099,341원';
    final shown = TextLayout.amount(s);
    expect(visibleText(shown), s);
    expect(TextLayout.plain(shown), s);
    // 끊을 수 있는 자리(ZWSP)는 쉼표 바로 뒤에만 있다.
    final breaks = RegExp('​').allMatches(shown).map((m) => shown[m.start - 1]).toSet();
    expect(breaks, {','});
  });

  for (final (size, scale) in _layouts) {
    final tag = '${size.width.toInt()}·$scale';

    testWidgets('LN-1 $tag 급여 개요 월 카드 — 12억대 금액·천 단위 인원/건수가 잘리지 않는다', (t) async {
      _setView(t, size);
      await t.pumpWidget(_app(PayrollOverviewScreen(reads: _overviewReads()), scale));
      await _settle(t);
      expect(t.takeException(), isNull, reason: '월 카드 넘침');
      _expectWhole(t, '1,322,099,341원');
      _expectWhole(t, '1,234명 · 12,345건');
      _expectWhole(t, '미이체 8,230');
    });

    testWidgets('LN-2 $tag 월 상세 머리·근로자 행 — 금액 말줄임 없음, 건수 구분', (t) async {
      _setView(t, size);
      await t.pumpWidget(_app(PayrollOverviewScreen(reads: _overviewReads()), scale));
      await _settle(t);
      await t.tap(findVisibleText('미이체 8,230'));
      await _settle(t, 15);
      expect(t.takeException(), isNull, reason: '월 상세 넘침');
      _expectWhole(t, '1,322,099,341원');
      _expectWhole(t, '8,230건'); // 미이체
      _expectWhole(t, '4,115건'); // 이체 완료 = 12,345 − 8,230
      _expectWhole(t, '1,234명');
      _expectWhole(t, '205,925,891원');
      _expectWhole(t, '확정 근무 32건');
    });

    testWidgets('LN-3 $tag 지급 현황(전체 미이체) — 미이체 요약 금액·인원이 넘치지 않는다', (t) async {
      await _mountDashboard(t, size, scale, all: true);
      expect(t.takeException(), isNull, reason: '미이체 요약 넘침(기기 392·2.0 RIGHT OVERFLOWED 15px)');
      _expectWhole(t, '1,322,099,341원');
      _expectWhole(t, '900,000,000원');
      _expectWhole(t, '422,099,341원');
    });

    testWidgets('LN-4 $tag 지급 현황(월) — 탭 4개는 잘리지 않고, 넘치면 가로 스크롤', (t) async {
      final errs = <String>[];
      final prev = FlutterError.onError;
      FlutterError.onError = (d) => errs.add(d.toString());
      await _mountDashboard(t, size, scale, all: false);
      FlutterError.onError = prev;
      expect(errs, isEmpty, reason: '날짜 줄 넘침(392·2.0 1.9px) 등');
      final bar = t.widget<TabBar>(find.byType(TabBar));
      final fits = TextLayout.tabsFit(t.element(find.byType(TabBar)), size.width, 4, perTab: 92);
      expect(bar.isScrollable, !fits);
      for (final name in const ['미이체', '이체현황', '변경요청', '중간정산']) {
        final rp = t.renderObject<RenderParagraph>(
            find.descendant(of: find.byType(TabBar), matching: find.text(name)).first);
        expect(rp.didExceedMaxLines, isFalse, reason: '$name 탭 이름 잘림');
      }
    });

    testWidgets('LN-5 $tag 탭 배지·일괄 선택 바 — 네 자리 이상 건수와 억 단위 선택 금액', (t) async {
      _setView(t, size);
      await t.pumpWidget(DefaultTabController(length: 1, child: MaterialApp(
        theme: ThemeData(fontFamily: _font),
        builder: (ctx, child) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        home: Scaffold(
          appBar: AppBar(
            bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
              Tab(child: AppTabLabel(label: '미이체', count: _pending, urgent: true)),
            ]),
          ),
          body: Column(children: [
            AppBatchActionBar(
              selectedCount: _records,
              selectedAmount: _total,
              onSelectAll: () {},
              onDeselectAll: () {},
              onAction: () {},
              actionLabel: '송금 처리',
            ),
          ]),
        ),
      )));
      await t.pump();
      expect(t.takeException(), isNull, reason: '일괄 선택 바 넘침');
      _expectWhole(t, '8,230');
      _expectWhole(t, '1,322,099,341원');
      expect(findVisibleText('12,345건 송금 처리'), findsOneWidget); // [DU257 r1] 바 실행 글자는 keepWords — 보이는 글자로 찾는다
    });
  }
}
