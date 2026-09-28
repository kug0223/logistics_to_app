import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/interim_settlement_reads.dart';
import 'package:ALfit/screens/user/interim_settlement_request_screen.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/widgets/common/app_batch_action_bar.dart';

/// [R7-P2-4 P24-Q/E] 돈을 다루는 화면이 **못 읽은 것을 "없다"로 말하지 않는가.**
///
///   정산 신청(쓰기)은 하지 않는다 — 후보 목록과 상태 문구까지만 본다.

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

const _biz = 'biz1';

ApplicationModel _app() => ApplicationModel(
      id: 'a1',
      toId: 'to1',
      uid: 'u1',
      businessId: _biz,
      businessName: '강남 물류센터',
      toTitle: '단기 공고',
      status: AppStatus.confirmed,
      selectedWorkType: '상하차',
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      workDate: _day(-3),
      appliedAt: _day(-10),
    );

/// 급여가 **확정된** 출근기록 — 정산 후보가 되는 유일한 모양.
AttendanceModel _confirmedAtt({
  required String id,
  required DateTime workDate,
  int finalWage = 90000,
  String businessId = _biz,
}) =>
    AttendanceModel(
      id: id,
      applicationId: 'a1',
      userId: 'u1',
      businessId: businessId,
      businessName: '강남 물류센터',
      workDate: workDate,
      workType: '상하차',
      status: AttendanceModel.statusPresent,
      wageStatus: AttendanceModel.wageConfirmed,
      adminConfirmed: true,
      finalWage: finalWage,
      checkInAt: workDate,
      checkOutAt: workDate.add(const Duration(hours: 9)),
      createdAt: workDate,
    );

InterimSettlementReads _reads({
  List<AttendanceModel> atts = const [],
  Object? error,
}) =>
    InterimSettlementReads(
      myMonthlyAttendances: (
          {required String userId, required int year, required int month}) async {
        if (error != null) throw error;
        return atts
            .where((a) =>
                a.workDate.year == year && a.workDate.month == month)
            .toList();
      },
    );

Future<void> _pump(
  WidgetTester tester, {
  required InterimSettlementReads reads,
  Size size = const Size(390, 1600),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 50));
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
        home: InterimSettlementRequestScreen(app: _app(), reads: reads),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _emptyTitle = '정산 가능한 출근기록이 없습니다';
const _emptyReason = '급여 확정된 근무일이 없거나\n이미 모두 정산 처리되었습니다.';
const _errorTitle = '정산 가능한 근무를 확인하지 못했습니다';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    await initializeDateFormatting('ko_KR', null);
  });

  testWidgets('MMR-1 조회 실패를 "정산 가능한 출근기록이 없습니다"로 말하지 않는다',
      (tester) async {
    await _pump(tester, reads: _reads(error: Exception('network')));

    expect(tester.takeException(), isNull);
    expect(find.text(_errorTitle), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    expect(find.text(_emptyTitle), findsNothing,
        reason: '못 읽은 것을 "정산할 근무 없음" 으로 말하면 받을 돈을 포기한다');
    expect(find.text(_emptyReason), findsNothing,
        reason: '이유까지 단정하면 더 나쁘다 — 조회 실패는 그 이유가 아니다');
  });

  testWidgets('MMR-2 정말 후보가 없을 때는 없다고 말한다(양성 대조)',
      (tester) async {
    await _pump(tester, reads: _reads(atts: const []));

    expect(find.text(_emptyTitle), findsOneWidget);
    expect(find.text(_errorTitle), findsNothing);
  });

  testWidgets('MMR-3 급여 확정된 근무가 있으면 후보로 나온다', (tester) async {
    await _pump(
      tester,
      reads: _reads(atts: [
        _confirmedAtt(id: 'w1', workDate: _day(-3)),
      ]),
    );

    expect(tester.takeException(), isNull);
    expect(find.text(_emptyTitle), findsNothing);
    expect(find.text(_errorTitle), findsNothing);
    // 후보가 있으면 선택 바가 뜬다 — 목록이 실제로 만들어졌다는 뜻.
    expect(find.byType(AppBatchActionBar), findsOneWidget,
        reason: '정산 후보가 있으면 선택·요청 컨트롤이 있어야 한다');
  });

  testWidgets('MMR-4 다른 사업장의 확정 근무는 이 요청의 후보가 아니다',
      (tester) async {
    await _pump(
      tester,
      reads: _reads(atts: [
        _confirmedAtt(id: 'other', workDate: _day(-3), businessId: 'biz-other'),
      ]),
    );

    expect(find.text(_emptyTitle), findsOneWidget,
        reason: '요청은 이 사업장의 근무에 대한 것이다');
  });

  testWidgets('MMR-5 신청 전 안내가 지급을 보장하지 않는다', (tester) async {
    await _pump(
      tester,
      reads: _reads(atts: [_confirmedAtt(id: 'w1', workDate: _day(-3))]),
    );

    // 승인 이후 절차가 남아 있음을 말한다 — 즉시 지급/송금 완료로 말하지 않는다.
    expect(find.textContaining('관리자 승인 후'), findsWidgets);
    expect(find.textContaining('입금 완료'), findsNothing);
    expect(find.textContaining('송금 완료'), findsNothing);
  });

  for (final size in const [Size(320, 1600), Size(412, 1600)]) {
    for (final scale in const [1.3, 2.0]) {
      testWidgets(
          'MMR-R ${size.width.toInt()}dp × $scale — 금액·상태·CTA 가 예외 없이 그려진다',
          (tester) async {
        await _pump(
          tester,
          reads: _reads(atts: [
            _confirmedAtt(id: 'w1', workDate: _day(-3), finalWage: 1250000),
          ]),
          size: size,
          textScale: scale,
        );
        expect(tester.takeException(), isNull);
        expect(find.byType(AppBatchActionBar), findsOneWidget);
        expect(find.text('전체선택'), findsOneWidget);
      });
    }
  }
}
