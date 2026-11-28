// [ALFIT-E2-INVITED-READER-INTEGRATION-AND-DEVICE-RECHECK.1 §3] 렌더 회귀.
//
//   RR-W  근로자 초대 카드 — **실제 MyApplicationsScreen**(번들 NotoSansKR 로드)
//         에서 320/360/411dp × 1.0/1.3/2.0. 근무 시작·종료 시각이 잘리지 않고,
//         넘침 0, 거절 CTA 에 닿는다. (관리자 업무 행 시급은 통합 테스트 IR-7.)
//   RR-A  흰 배경 AppBar — **실제 앱 테마(RoleTheme.workerTheme)** 아래에서
//         수정한 5곳의 제목·아이콘 색과 흰 배경 대비(WCAG 4.5:1)를 잰다.
//         기존 정상 화면 표본 2곳이 그대로인지도 같은 식으로 잰다.
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/theme/app_colors.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/ui/invitation_projection.dart';
import 'package:ALfit/models/ui/invite_accept_readiness.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/help_screen.dart';
import 'package:ALfit/screens/legal/legal_consent_screen.dart';
import 'package:ALfit/screens/user/invite_region_settings_screen.dart';
import 'package:ALfit/screens/user/my_applications_reads.dart';
import 'package:ALfit/screens/user/my_applications_screen.dart';
import 'package:ALfit/screens/user/tabs/user_my_tab.dart';
import 'package:ALfit/screens/user/user_contracts_screen.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/theme/role_theme.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';
import 'package:ALfit/widgets/user/invitation_promise_card.dart';
import 'support/visible_text.dart'; // [impl_21] TextLayout 문구는 보이는 글자로 찾는다

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

const _kUid = 'u1';

class _P extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: _kUid,
        username: _kUid,
        name: 'QA 지원자',
        email: '$_kUid@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '경기도', city: '평택시'),
        accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 9, 1),
        idCardImagePath: 'id_cards/$_kUid/front.jpg',
        isIdVerified: true,
        bankName: '국민은행',
        accountNumber: '000000000000',
        accountHolder: 'QA 지원자',
        bankbookImagePath: 'bankbooks/$_kUid/b.jpg',
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

// DEV QA-W2 초대와 같은 모양: 10/19 14:00~15:00, 확인 대기(동의함).
final DateTime _day = FormatHelper.toKstDate(DateTime.utc(2026, 10, 19));
final DateTime _start = FormatHelper.kstWallClockInstant(_day, '14:00')!;
final DateTime _clock = _start.subtract(const Duration(days: 2));

ApplicationModel _invite() => ApplicationModel(
      id: 'inv1',
      toId: 'to1',
      slotId: 'slot1',
      wdId: 'wd-1',
      uid: _kUid,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toTitle: 'QA-N E2 consent 1019 1400-1500',
      status: AppStatus.invited,
      selectedWorkType: 'QA 분류',
      startTime: '14:00',
      endTime: '15:00',
      wage: 12000,
      wageType: 'hourly',
      workDate: _day,
      appliedAt: _clock,
      invitedAt: _clock,
      inviteExpiresAt: _clock.add(const Duration(hours: 24)),
      workInstanceCapacityState: InviteCapacityState.available,
      inviteAcceptReadiness: InviteAcceptReadiness.reviewPending,
      documentAccessConsentGiven: true,
      documentAccessConsentVersion: DocumentAccessConsent.inviteVersion,
    );

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: 'QA 사업장',
      type: 'flex',
      title: 'QA-N E2 consent 1019 1400-1500',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 1,
      totalConfirmed: 0,
      totalPending: 1,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: _day.subtract(const Duration(days: 10)),
      statusUpdatedAt: _day.subtract(const Duration(days: 10)),
    );

MyApplicationsReads _reads(List<ApplicationModel> apps) => MyApplicationsReads(
      myApplicationsPaged: (
              {required String uid,
              required int pageSize,
              String? startAfterDocId}) async =>
          {'items': apps, 'lastDocId': null, 'hasMore': false},
      toOrFailure: (id) async => (to: _to(), failed: false),
      contractsByWorker: (uid) async => const <EmploymentContractModel>[],
      autoExpirePending: (uid) async {},
      monthlyAttendances: (
              {required String userId,
              required int year,
              required int month}) async =>
          const <AttendanceModel>[],
      reviewById: (key) async => null,
      taxStatus: () async => const TaxIdentityStatus.unknown(),
    );

Future<void> _pumpScreen(WidgetTester t, Widget home,
    {double width = 411, double scale = 1.0, bool theme = false}) async {
  t.view.physicalSize = Size(width, 2400);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(milliseconds: 50));
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        theme: theme ? RoleTheme.workerTheme : null,
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

List<String> _overflows(WidgetTester t) {
  final out = <String>[];
  Object? e;
  while ((e = t.takeException()) != null) {
    if (e.toString().contains('overflowed')) out.add(e.toString().split('\n').first);
  }
  return out;
}

/// WCAG 상대 휘도.
double _lum(Color c) {
  double ch(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _lum(a), lb = _lum(b);
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// AppBar 안의 실제 렌더 색 — 제목 문단 색 · 아이콘 글리프 색 · 바 배경.
({Color? title, List<Color> icons, Color bg}) _appBarColors(
    WidgetTester t, String title) {
  final bar = find.byType(AppBar).first;
  final appBar = t.widget<AppBar>(bar);
  final titleFinder = find.descendant(of: bar, matching: find.text(title));
  Color? titleColor;
  if (titleFinder.evaluate().isNotEmpty) {
    final rp = t.renderObject<RenderParagraph>(titleFinder.first);
    titleColor = rp.text.style?.color;
  }
  final icons = <Color>[];
  for (final e in find
      .descendant(of: bar, matching: find.byType(Icon))
      .evaluate()) {
    final rp = find.descendant(
        of: find.byWidget(e.widget), matching: find.byType(RichText));
    for (final r in rp.evaluate()) {
      final c = (r.renderObject as RenderParagraph).text.style?.color;
      if (c != null) icons.add(c);
    }
  }
  return (
    title: titleColor,
    icons: icons,
    bg: appBar.backgroundColor ?? Colors.white,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
    final f = File('assets/fonts/NotoSansKR-Regular.ttf');
    if (f.existsSync()) {
      final loader = FontLoader('NotoSansKR')
        ..addFont(f.readAsBytes().then((b) => ByteData.view(b.buffer)));
      await loader.load();
    }
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
            'dev.flutter.pigeon.cloud_functions_platform_interface.CloudFunctionsHostApi.call',
            (data) async => const StandardMessageCodec()
                .encodeMessage(<Object?>['unavailable', 'test harness', null]));
  });

  group('RR-W 근로자 초대 카드', () {
    for (final (w, scale) in const [
      (320.0, 1.0), (320.0, 1.3), (320.0, 2.0),
      (360.0, 1.0), (360.0, 1.3), (360.0, 2.0),
      (411.0, 1.0), (411.0, 1.3), (411.0, 2.0),
    ]) {
      testWidgets('RR-W ${w.toInt()}dp × $scale — 시작·종료 시각 온전 · 넘침 0 · 거절 CTA',
          (t) async {
        await _pumpScreen(
            t,
            MyApplicationsScreen(
              reads: _reads([_invite()]),
              clock: () => _clock,
              initialTabIndex: 6,
            ),
            width: w,
            scale: scale,
            theme: true);
        expect(_overflows(t), isEmpty);
        final time = find.textContaining('14:00~15:00');
        expect(time, findsWidgets, reason: '종료 시각까지 한 덩어리로 그려진다');
        final txt = t.widget<Text>(time.first);
        expect(txt.overflow, isNot(TextOverflow.ellipsis));
        final rp = t.renderObject<RenderParagraph>(time.first);
        expect(rp.didExceedMaxLines, isFalse, reason: '잘린 줄이 없다');
        final reject = findVisibleText('거절');
        expect(reject, findsWidgets);
        await t.ensureVisible(reject.first);
        await t.pump();
        expect(reject.first.hitTestable(), findsOneWidget, reason: 'CTA 에 닿는다');
        expect(_overflows(t), isEmpty);
      });
    }
  });

  group('RR-A 흰 배경 AppBar — 실제 테마 대비', () {
    void expectReadable(
        WidgetTester t, String title, {required bool expectIcon}) {
      final c = _appBarColors(t, title);
      expect(c.title, isNotNull, reason: '$title 제목을 찾지 못했다');
      expect(_contrast(c.title!, c.bg), greaterThanOrEqualTo(4.5),
          reason: '$title 제목 대비 (색 ${c.title})');
      if (expectIcon) {
        expect(c.icons, isNotEmpty, reason: '$title 뒤로가기 아이콘');
      }
      for (final ic in c.icons) {
        expect(_contrast(ic, c.bg), greaterThanOrEqualTo(3.0),
            reason: '$title 아이콘 대비 (색 $ic) — 비텍스트 3:1');
      }
    }

    testWidgets('RR-A1 내 지원 내역 — 제목·뒤로가기', (t) async {
      await _pumpScreen(
          t,
          MyApplicationsScreen(
              reads: _reads([_invite()]), clock: () => _clock),
          theme: true);
      expectReadable(t, '내 지원 내역', expectIcon: true);
      _overflows(t);
    });

    testWidgets('RR-A2 MY 탭 — 제목', (t) async {
      await _pumpScreen(t, const UserMyTab(), theme: true);
      expectReadable(t, 'MY', expectIcon: false);
      _overflows(t);
    });

    testWidgets('RR-A3 약관 동의 — 제목·뒤로가기', (t) async {
      await _pumpScreen(
          t,
          Builder(
              builder: (ctx) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).push(
                            MaterialPageRoute(
                                builder: (_) => const LegalConsentScreen())),
                        child: const Text('open'),
                      ),
                    ),
                  )),
          theme: true);
      await t.tap(find.text('open'));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expectReadable(t, '약관 동의', expectIcon: true);
      _overflows(t);
    });

    testWidgets('RR-A4 근무 초대 받기 — 제목·뒤로가기', (t) async {
      await _pumpScreen(
          t,
          Builder(
              builder: (ctx) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    const InviteRegionSettingsScreen())),
                        child: const Text('open'),
                      ),
                    ),
                  )),
          theme: true);
      await t.tap(find.text('open'));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expectReadable(t, '근무 초대 받기', expectIcon: true);
      _overflows(t);
    });

    testWidgets('RR-A5 업무 초대(대체 상세) — 제목·뒤로가기', (t) async {
      final p = InvitationProjection.of(
          application: _invite(), postingLoaded: false);
      await _pumpScreen(
          t,
          Builder(
              builder: (ctx) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    InvitationFallbackDetail(projection: p))),
                        child: const Text('open'),
                      ),
                    ),
                  )),
          theme: true);
      await t.tap(find.text('open'));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expectReadable(t, '업무 초대', expectIcon: true);
      _overflows(t);
    });

    // 표본 대조 — 손대지 않은 정상 화면이 같은 테마에서 그대로 읽힌다.
    testWidgets('RR-A6 표본: 도움말 (수정 안 함)', (t) async {
      await _pumpScreen(
          t,
          Builder(
              builder: (ctx) => Scaffold(
                    body: Center(
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).push(
                            MaterialPageRoute(
                                builder: (_) => const HelpScreen())),
                        child: const Text('open'),
                      ),
                    ),
                  )),
          theme: true);
      await t.tap(find.text('open'));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expectReadable(t, '도움말', expectIcon: true);
      _overflows(t);
    });

    testWidgets('RR-A7 표본: 내 계약서 (수정 안 함)', (t) async {
      await _pumpScreen(t, const UserContractsScreen(), theme: true);
      expectReadable(t, '내 계약서', expectIcon: false);
      _overflows(t);
    });

    test('RR-A8 [DU1] 앱 테마 AppBar = 흰 배경 + 어두운 제목·아이콘', () {
      final th = RoleTheme.workerTheme.appBarTheme;
      // [DU1] 공통 기준 v1 — 앱 테마 AppBar 를 흰 배경·어두운 제목으로 바꿨다(사용자 승인 디자인 범위). LightAppBarStyle 보호는 같은 값이 된다.
      expect(th.titleTextStyle?.color, AppColors.textPrimary);
      expect(th.iconTheme?.color, AppColors.textPrimary);
    });
  });
}
