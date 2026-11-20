// [DEVICE-MISMATCH-FIX] 급여 지급 현황 카드 — 지급일 칩·사업장 줄을 자르지 않는다.
//
// DEVICE 관찰(Pixel 5, 새 APK md5 728502a9…, 10-20 17:01): 전체 미이체 화면 카드에서
//   `⚠ 주급 · 10.13 …` · `⚠ 익일 · 10.18 …` — 잘린 말이 **`초과`(연체)** 였다.
//   사업장 줄도 `[QA QAMV2EF85P] 골든패스 테스트 …` 로 잘렸다.
//
// root cause: 1행 `Row[Flexible(이름), Flexible(칩)]` — 같은 flex 둘이 남는 폭을 반씩
//   나눠 칩이 절반만 받았다(이름이 짧아도 그 몫이 칩에 돌아오지 않는다). 칩 글자와
//   사업장 줄은 한 줄 말줄임이었다.
//
// 측정 자: 번들 NotoSansKR + Pixel 5 폭(411.43dp). 기본 테스트 폰트는 한글을 넓게 잰다.
import 'support/visible_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/business_member_model.dart'
    show MemberPermissions;
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/payroll/payroll_payment_dashboard_screen.dart';

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

class _AdminP extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
      uid: 'OWNER', username: 'owner', name: '관리자',
      email: 'owner@test.local', role: UserRole.BUSINESS_ADMIN);
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool can(bool Function(MemberPermissions p) check) => true;
  @override
  bool canForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      true;
  @override
  PermissionCheck checkForBusiness(
          String businessId, bool Function(MemberPermissions p) check) =>
      PermissionCheck.allowed;
}

const _font = 'NotoSansKR';
const _pixel5Width = 1080 / 2.625;
const _ch =
    'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call';
const _biz = 'BIZ';
const _bizName = '[QA QAMV2EF85P] 골든패스 테스트 사업장';

Future<void> _loadFont() async {
  final loader = FontLoader(_font);
  for (final f in const ['Regular', 'Bold']) {
    loader.addFont(rootBundle
        .load('assets/fonts/NotoSansKR-$f.ttf')
        .then((b) => ByteData.sublistView(b.buffer.asUint8List())));
  }
  await loader.load();
}

Map<String, Object?> _ts(DateTime d) =>
    {'_seconds': d.millisecondsSinceEpoch ~/ 1000, '_nanoseconds': 0};

/// DEV 10-20 과 같은 두 건: JYAe(주급, 지급일 10-13) · 6HB9(익일, 지급일 10-18) — 둘 다 연체.
List<Map<String, Object?>> _rows() => [
      for (final r in [
        ('JYAe', 'u7oZZ', DateTime(2026, 10, 10), DateTime(2026, 10, 13), 51251, 'weekly'),
        ('6HB9', 'uxZah', DateTime(2026, 10, 17), DateTime(2026, 10, 18), 12000, 'next_day'),
      ])
        {
          'id': r.$1, 'userId': r.$2, 'businessId': _biz, 'businessName': _bizName,
          'workDate': _ts(r.$3), 'workType': 'QA 분류', 'status': 'present',
          'wageStatus': 'confirmed', 'adminConfirmed': true,
          'createdAt': _ts(r.$3), 'paymentDueDate': _ts(r.$4),
          'wageDetail': {
            'totalAmount': r.$5, 'wageType': 'daily', 'payScheduleType': r.$6,
          },
          'wageAccountSourceBankAccountVersion': 1,
          'wageAccountSourceBankbookDocumentVersion': 1,
        }
    ];

Future<ByteData?> _handle(ByteData? data) async {
  final args = (const StandardMessageCodec().decodeMessage(data) as List)
      .first as Map;
  final fn = args['functionName'] as String;
  final p = Map<Object?, Object?>.from(args['parameters'] as Map? ?? const {});
  Object? body;
  switch (fn) {
    case 'callableGetAdminAttendances':
      final s = p['startMs'] as int, e = p['endMs'] as int;
      final ws = p['wageStatus'] as String?;
      body = {
        'items': [
          for (final r in _rows())
            if (((r['workDate'] as Map)['_seconds'] as int) * 1000 >= s &&
                ((r['workDate'] as Map)['_seconds'] as int) * 1000 < e &&
                (ws == null || r['wageStatus'] == ws))
              r
        ],
        'limitReached': false,
      };
    case 'callableGetUsersBatch':
      body = {
        'users': {
          'u7oZZ': {'name': 'QA 지원자1', 'username': 'w1', 'role': 'USER'},
          'uxZah': {'name': 'QA 지원자2', 'username': 'w2', 'role': 'USER'},
        }
      };
    case 'callableGetPayrollReadinessBatch':
      body = {
        'readiness': {
          for (final u in (p['workerUids'] as List).cast<String>())
            u: {
              'ready': true, 'state': 'READY_AUTO', 'actor': 'NONE',
              'accountVersion': 1, 'bankbookVersion': 1,
            }
        },
        'failed': <String>[],
      };
    default:
      body = {'requests': <Object?>[], 'items': <Object?>[]};
  }
  return const StandardMessageCodec().encodeMessage(<Object?>[body]);
}

Future<void> _mount(WidgetTester t, {double textScale = 1.0}) async {
  t.view.physicalSize = const Size(_pixel5Width, 1400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, _handle);
  addTearDown(
      () => t.binding.defaultBinaryMessenger.setMockMessageHandler(_ch, null));
  await t.pumpWidget(MultiProvider(
    providers: [
      ChangeNotifierProvider<UserProvider>(create: (_) => _AdminP()),
      ChangeNotifierProvider<NotificationProvider>(
          create: (_) => NotificationProvider()),
    ],
    child: MaterialApp(
      theme: ThemeData(fontFamily: _font),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: const PayrollPaymentDashboardScreen(
        businessId: _biz, businessName: 'QA 사업장',
        year: 2026, month: 10, showAllOutstanding: true,
      ),
    ),
  ));
  for (var i = 0; i < 40; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

/// 문단이 전부 그려졌는가 — 말줄임·잘림 없음.
void _expectWhole(WidgetTester t, String text) {
  final f = find.text(text);
  expect(f, findsOneWidget, reason: '`$text` 가 화면에 없다');
  final rp = t.renderObject<RenderParagraph>(f);
  expect(rp.didExceedMaxLines, isFalse, reason: '`$text` 가 잘렸다');
  final boxes = rp.getBoxesForSelection(
      TextSelection(baseOffset: 0, extentOffset: text.length));
  final drawn = boxes.fold<double>(0, (a, b) => a + (b.right - b.left));
  expect(drawn, greaterThan(0));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await _loadFont();
  });

  for (final scale in const [1.0, 1.3]) {
    testWidgets('PL-1 [DEVICE 재현] 배율 $scale — 지급일 칩 `… 초과` 가 잘리지 않는다',
        (t) async {
      await _mount(t, textScale: scale);
      expect(t.takeException(), isNull);
      expect(findVisibleText('전체 미이체'), findsOneWidget);
      _expectWhole(t, '주급 · 10.13 초과');
      _expectWhole(t, '익일 · 10.18 초과');
    });

    testWidgets('PL-2 배율 $scale — 사업장 줄을 말줄임으로 자르지 않는다', (t) async {
      await _mount(t, textScale: scale);
      expect(t.takeException(), isNull);
      final infos = t
          .widgetList<Text>(find.byType(Text))
          .where((w) => (w.data ?? '').startsWith(_bizName))
          .toList();
      expect(infos, hasLength(2), reason: '근로자 카드 두 장의 사업장 줄');
      for (final w in infos) {
        expect(w.overflow, isNot(TextOverflow.ellipsis));
        // [.29] semanticsLabel 을 준 Text 는 Semantics 로 감싸진다 — 글자 배치는 안쪽 RichText 에서 본다.
        final rp = t.renderObject<RenderParagraph>(
            find.descendant(of: find.byWidget(w), matching: find.byType(RichText), matchRoot: true).first);
        expect(rp.didExceedMaxLines, isFalse);
      }
    });
  }

  testWidgets('PL-3 금액·건수는 그대로 보인다(회귀)', (t) async {
    await _mount(t);
    expect(find.text('63,251원'), findsOneWidget);
    expect(find.text('51,251원'), findsOneWidget);
    expect(find.text('12,000원'), findsOneWidget);
  });
}
