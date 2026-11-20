// [R7-P1-2 DEVICE.1H.1 후속] 확정 명단 행이 320dp·배율 2.0 에서 잘리던 것.
//
// P3-2 의 IHK-5 가 넘침 3건(62/14/104px)을 재현했고, 그 상태를 **사실로** 고정해
// 두었다. 여기서 그 셋을 production 부모(`DayApplicantsDialog`) 안에서 다시 세우고
// **넘침 0** 을 새 기대값으로 만든다.
//
// 부모를 실제와 다르게 넓히지 않는다 — 320dp 물리 폭을 그대로 주고 화면이
// 스스로 만드는 제약을 쓴다. 실제 writer(초대·확정취소·거절)는 실행하지 않는다.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/services/contract_service.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/business_member_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/day_staffing_row.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_dialog.dart';
import 'package:ALfit/screens/business_admin/dialogs/day_applicants_reads.dart';

import 'package:ALfit/theme/role_theme.dart';

import 'support/du1_vq_capture.dart';
import 'support/visible_text.dart';

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

const kBiz = 'biz1';
final kDate = DateTime(2026, 9, 29);
final kInvitedAt = DateTime(2026, 9, 27, 10);

class _Owner extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: 'owner1',
        username: 'owner1',
        name: '박사장',
        email: 'owner1@alfit.local',
        role: UserRole.BUSINESS_ADMIN,
        businessId: kBiz,
        createdAt: DateTime(2026, 1, 1),
      );
  @override
  bool get isBusinessAdmin => true;
  @override
  bool get isSubAdmin => false;
  @override
  bool get isSuperAdmin => false;
  @override
  bool get isAdminMode => true;
  @override
  bool get permissionsLoaded => true;
  @override
  bool can(bool Function(MemberPermissions p) c) => true;
  @override
  bool canForBusiness(String b, bool Function(MemberPermissions p) c) => true;
}

BusinessModel _business() => BusinessModel(
      id: kBiz,
      name: '강남 물류센터',
      businessNumber: '000-00-00000',
      category: '음식점',
      subCategory: '한식',
      address: '서울특별시 강남구 테헤란로 1',
      ownerId: 'owner1',
      createdAt: DateTime(2026, 9, 1),
    );

ApplicationModel _app(String id, String uid, String status,
        {DateTime? invitedAt}) =>
    ApplicationModel(
      id: id,
      uid: uid,
      toId: 'to1',
      slotId: 'slot1',
      businessId: kBiz,
      businessName: '강남 물류센터',
      toTitle: '단기 모집',
      selectedWorkType: '홀서빙',
      wdId: 'wd1',
      startTime: '09:00',
      endTime: '18:00',
      wage: 12000,
      wageType: 'hourly',
      status: status,
      workDate: kDate,
      appliedAt: kDate,
      invitedAt: invitedAt,
    );

DayStaffingRow _row() => DayStaffingRow(
      toId: 'to1',
      toTitle: '단기 모집',
      slotId: 'slot1',
      wdId: 'wd1',
      workType: '홀서빙',
      startTime: '09:00',
      endTime: '18:00',
      requiredCount: 3,
      confirmedCount: 1,
      pendingCount: 0,
    );

/// IHK-5 가 넘침을 낸 바로 그 표본: 확정 1건(초대 수락) + 초대 응답 2건.
DayApplicantsReads _reads({
  List<ApplicationModel> pending = const [],
  List<ApplicationModel> confirmed = const [],
  List<ApplicationModel> invites = const [],
  Map<String, int> caps = const {'wd1': 3},
}) =>
    DayApplicantsReads(
      pendingApplications: ({required date, required businessId, purpose}) async =>
          pending,
      confirmedWorkers: ({required date, required businessId}) async => confirmed,
      dayStaffing: ({required businessId, required dayStartMs}) async => [_row()],
      dayInvitations: ({required date, required businessId}) async => invites,
      hasWorkedMap: ({required businessId, required date}) async => const {},
      noShowApplicationIds: ({required businessId, required date}) async =>
          <String>{},
      usersBatch: (uids, {required businessId, purpose}) async => {
        for (final u in uids)
          u: UserModel(
              uid: u,
              username: u,
              name: '근로자 $u',
              email: '$u@test.local',
              role: UserRole.USER),
      },
      weeklyAttendance: (
              {required businessId,
              required weekStart,
              required weekEnd}) async =>
          <String, List<AttendanceModel>>{},
      slotWorkDetailCapacities: (toId, slotId) async => caps,
      slotWorkDetails: (toId, slotId) async => <WorkDetailData>[],
      to: (toId) async => null,
      contractStatusBatch: (ids, {required businessId}) async =>
          const ContractStatusBatch(),
      // [NOSHOW-CONTRACT-GUARD] 근태를 읽었고 그 날 기록이 없다 — 계약서 작성 대상.
      contractAttendances: ({required businessId, required date}) async =>
          const <AttendanceModel>[],
    );

/// 넘침 메시지를 모은다 — `takeException` 은 첫 건만 주므로 직접 센다.
Future<List<String>> _pumpCollect(
  WidgetTester tester,
  DayApplicantsReads reads, {
  required Size size,
  required double textScale,
}) async {
  final overflows = <String>[];
  final prev = FlutterError.onError;
  FlutterError.onError = (d) {
    final s = d.exception.toString();
    if (s.contains('overflowed')) {
      overflows.add(s.split('\n').first);
    } else {
      prev?.call(d);
    }
  };
  addTearDown(() => FlutterError.onError = prev);

  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _Owner(),
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: DayApplicantsDialog(
            key: ValueKey('$size-$textScale'),
            date: kDate,
            businessIds: const [kBiz],
            businesses: [_business()],
            reads: reads,
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  FlutterError.onError = prev;
  return overflows;
}

/// 표본 1 — 확정(초대 수락) 1건 + 초대 응답 2건. IHK-5 의 그 조합.
DayApplicantsReads _sampleAccepted() => _reads(
      confirmed: [_app('c1', 'u1', 'CONFIRMED', invitedAt: kInvitedAt)],
      invites: [
        _app('i1', 'u3', 'REJECTED', invitedAt: kInvitedAt),
        _app('i2', 'u4', 'CANCELED', invitedAt: kInvitedAt),
      ],
    );

/// 표본 2 — 스스로 지원해 확정된 행(초대 구역 없음).
DayApplicantsReads _sampleDirect() =>
    _reads(confirmed: [_app('c2', 'u2', 'CONFIRMED')]);

/// 표본 3 — 대기 행(승인·거절 버튼이 가장 많은 줄).
///   [UI-2] 같은 슬롯에 다른 업무(wd2)가 있어야 `다른 업무 제안` 이 보인다.
DayApplicantsReads _samplePending() => _reads(
    pending: [_app('p1', 'u5', 'PENDING')], caps: const {'wd1': 3, 'wd2': 3});

/// 표본 3b — 슬롯의 업무가 지원한 그 업무 하나뿐(id 로 증명).
DayApplicantsReads _samplePendingSingleWork() =>
    _reads(pending: [_app('p1', 'u5', 'PENDING')]);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
    // [DU1 후속38 §2.1] FirebaseAuth 가 생성될 때 pigeon 채널로 token/auth listener 를 등록한다. 시험 환경에는 그 채널이 없어
    //   PlatformException(channel-error) 로 끝나고, 캡처의 runAsync(실제 비동기)가 이것을 첫 캡처 시험의 실패로 드러냈다(B2-L-A before r1~r3).
    //   두 등록 채널에만 '등록됨(이벤트 채널 이름)' 응답을 준다 — 로그인 상태·자료·화면 동작은 바꾸지 않는다(이벤트는 오지 않는다).
    const codec = StandardMessageCodec();
    for (final m in const ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMessageHandler(
          'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$m',
          (_) async => codec.encodeMessage(<Object?>['du38.fake.$m']));
      // 돌려준 이벤트 채널의 listen/cancel — 성공만 응답하고 이벤트는 보내지 않는다
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel('du38.fake.$m'), (_) async => null);
    }
  });

  // ══ 세 표본 · 320dp × 2.0 ═════════════════════════════════════════════════

  testWidgets('[ARO-1] 표본1(초대 수락 확정) 320dp×2.0 — 넘침 0', (tester) async {
    final o = await _pumpCollect(tester, _sampleAccepted(),
        size: const Size(320, 3200), textScale: 2.0);
    expect(o, isEmpty, reason: o.join(' | '));
  });

  testWidgets('[ARO-2] 표본2(직접 지원 확정) 320dp×2.0 — 넘침 0', (tester) async {
    final o = await _pumpCollect(tester, _sampleDirect(),
        size: const Size(320, 3200), textScale: 2.0);
    expect(o, isEmpty, reason: o.join(' | '));
  });

  testWidgets('[ARO-3] 표본3(대기 행) 320dp×2.0 — 넘침 0', (tester) async {
    final o = await _pumpCollect(tester, _samplePending(),
        size: const Size(320, 3200), textScale: 2.0);
    expect(o, isEmpty, reason: o.join(' | '));
  });

  // ══ 정보와 조작이 살아 있는지 ══════════════════════════════════════════════

  testWidgets('[ARO-4] 320dp×2.0 에서도 이름·상태·행동이 그대로 읽힌다',
      (tester) async {
    await _pumpCollect(tester, _sampleAccepted(),
        size: const Size(320, 3200), textScale: 2.0);

    // 누구인지
    expect(find.text('근로자 u1'), findsWidgets);
    // 무슨 상태인지 — 잘려서 다른 말이 되지 않는다
    expect(find.text('초대 수락 · 확정'), findsOneWidget);
    expect(find.text('초대 거절'), findsOneWidget);
    expect(find.text('초대 철회'), findsOneWidget);
    // 무엇을 할 수 있는지
    expect(find.text('계약서 작성'), findsOneWidget);
    expect(find.text('확정취소'), findsOneWidget);
    // 배지의 값이 잘리지 않는다
    expect(find.text('계약서 작성 필요'), findsOneWidget);
  });

  testWidgets('[ARO-5] 대기 행의 세 버튼이 모두 남는다', (tester) async {
    await _pumpCollect(tester, _samplePending(),
        size: const Size(320, 3200), textScale: 2.0);

    // 묶음 머리줄에도 '확정' 이라는 통계 라벨이 있으므로 **버튼만** 센다.
    expect(find.widgetWithText(InkWell, '다른 업무 제안'), findsOneWidget);
    expect(find.widgetWithText(InkWell, '거절'), findsOneWidget);
    expect(find.widgetWithText(InkWell, '확정'), findsOneWidget);
  });

  testWidgets('[ARO-5b] 제안할 다른 업무가 없다고 증명되면 제안 버튼만 숨긴다',
      (tester) async {
    await _pumpCollect(tester, _samplePendingSingleWork(),
        size: const Size(320, 3200), textScale: 2.0);

    expect(find.widgetWithText(InkWell, '다른 업무 제안'), findsNothing);
    expect(find.widgetWithText(InkWell, '거절'), findsOneWidget);
    expect(find.widgetWithText(InkWell, '확정'), findsOneWidget);
  });

  testWidgets('[ARO-6] 버튼이 실제로 눌린다 — 확정취소는 확인창까지만',
      (tester) async {
    await _pumpCollect(tester, _sampleAccepted(),
        size: const Size(320, 3200), textScale: 2.0);

    final btn = find.text('확정취소');
    expect(btn, findsOneWidget);
    await tester.ensureVisible(btn);
    await tester.tap(btn);
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // 확인 단계가 열린다 — 여기서 멈춘다. 실제 확정취소 writer 는 부르지 않는다.
    expect(find.text('확정취소'), findsWidgets);
  });

  testWidgets('[ARO-7] 행이 길어져도 목록 스크롤로 마지막 행동에 닿는다',
      (tester) async {
    await _pumpCollect(tester, _sampleAccepted(),
        size: const Size(320, 640), textScale: 2.0); // 실제 높이로 좁힌다

    final btn = find.text('확정취소');
    expect(btn, findsOneWidget);
    await tester.ensureVisible(btn);
    await tester.pump();
    expect(tester.getRect(btn).top, lessThan(640));
  });

  // ══ 정상 대조 ═════════════════════════════════════════════════════════════

  for (final size in [const Size(360, 3200), const Size(412, 3200)]) {
    testWidgets('[ARO-C] ${size.width.toInt()}dp × 1.3 — 넘침 0 (정상 대조)',
        (tester) async {
      final o = await _pumpCollect(tester, _sampleAccepted(),
          size: size, textScale: 1.3);
      expect(o, isEmpty, reason: o.join(' | '));
    });
  }

  testWidgets('[ARO-C0] 390dp × 기본 배율 — 넘침 0 (정상 대조)', (tester) async {
    final o = await _pumpCollect(tester, _sampleAccepted(),
        size: const Size(390, 3200), textScale: 1.0);
    expect(o, isEmpty, reason: o.join(' | '));
  });
  // [DU1-B2 R5] 긴 명단 대표(LOCAL 모델 주입) — 대기 30명·확정 3명, 긴 한글 이름. 공통 Theme(NotoSansKR·카드·버튼) 뒤에도
  //   320dp×2.0 / 392dp×1.0 넘침 0, 마지막 사람까지 스크롤로 닿는다. writer 는 실행하지 않는다.
  for (final c in const [(Size(320, 3200), 2.0), (Size(392, 844), 1.0)]) {
    testWidgets('[ARO-L] 긴 명단 ${c.$1.width.toInt()}dp×${c.$2} — 넘침 0 · 필수 수치 · 마지막까지 도달 · 마지막 행 확정 hit', (tester) async {
      final pending = [for (var i = 0; i < 30; i++) _app('p$i', '아주긴이름의지원자홍길동$i', 'PENDING')];
      final confirmed = [for (var i = 0; i < 3; i++) _app('c$i', '확정된긴이름근로자$i', 'CONFIRMED')];
      final o = await _pumpCollect(tester, _reads(pending: pending, confirmed: confirmed, caps: const {'wd1': 40}),
          size: c.$1, textScale: c.$2);
      expect(o, isEmpty, reason: o.join(' | '));
      // [DU1 followup_5 §3] 필수 수치 — 확정/정원·지원 건수가 긴 명단에서도 그려진다(RichText 평문 기준)
      expect(findVisibleTextContaining('3/3명'), findsWidgets);
      expect(findVisibleTextContaining('지원 (30건)'), findsWidgets);
      final last = find.textContaining('아주긴이름의지원자홍길동29');
      await tester.scrollUntilVisible(last, 400, scrollable: find.byType(Scrollable).first, maxScrolls: 200);
      expect(last, findsWidgets);
      // 마지막 지원자 행의 '확정' 행동이 실제로 눌리는 자리에 있다(hit-test — 누르지 않는다, writer 미호출)
      final lastTop = tester.getRect(last.first).top;
      final btns = find.widgetWithText(InkWell, '확정');
      final below = [for (var k = 0; k < btns.evaluate().length; k++) btns.at(k)]
          .where((b) => tester.getRect(b).top >= lastTop - 1)
          .toList()
        ..sort((a, b) => tester.getRect(a).top.compareTo(tester.getRect(b).top));
      expect(below, isNotEmpty, reason: '마지막 행 확정 버튼');
      final target = below.first;
      await tester.ensureVisible(target);
      await tester.pump();
      final hit = HitTestResult();
      WidgetsBinding.instance.hitTestInView(hit, tester.getCenter(target), tester.view.viewId);
      expect(hit.path.any((e) => e.target == tester.renderObject(target)), isTrue, reason: '가려지지 않고 눌린다');
      expect(tester.takeException(), isNull);
    });
  }

  // ── [DU1 후속38 §2] B2-L 긴 인력 현황 시각 셀 — ARO-L 자료(대기30·확정3·긴 이름·owner·단일사업장) 그대로.
  //   host: production 과 같은 showDialog(barrierDismissible:false) — Scaffold body 직접 배치(ARO-L)와 다르다.
  //   theme: RoleTheme.businessAdminTheme · 글꼴: vqLoadFonts(NotoSansKR Regular+Bold, Roboto=NotoSansKR, MaterialIcons; FlutterTest 미등록).
  //   기준 날짜: fixture kDate=2026-09-29(고정) — 화면 내부 직접 DateTime.now 경로는 주입하지 않는다(메타데이터로만 기록).
  Future<({GlobalKey key, List<String> overflows})> b2Open(WidgetTester tester, {required Size size, required double scale}) async {
    await tester.runAsync(vqLoadFonts);
    final overflows = <String>[];
    final prev = FlutterError.onError;
    FlutterError.onError = (d) {
      final s = d.exception.toString();
      if (s.contains('overflowed')) {
        overflows.add(s.split('\n').first);
      } else {
        prev?.call(d);
      }
    };
    addTearDown(() => FlutterError.onError = prev);
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final pending = [for (var i = 0; i < 30; i++) _app('p$i', '아주긴이름의지원자홍길동$i', 'PENDING')];
    final confirmed = [for (var i = 0; i < 3; i++) _app('c$i', '확정된긴이름근로자$i', 'CONFIRMED')];
    final reads = _reads(pending: pending, confirmed: confirmed, caps: const {'wd1': 40});
    final key = GlobalKey();
    await tester.pumpWidget(ChangeNotifierProvider<UserProvider>(
      create: (_) => _Owner(),
      child: RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: RoleTheme.businessAdminTheme,
          builder: (ctx, child) => MediaQuery(data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)), child: child!),
          home: Builder(builder: (ctx) => Scaffold(body: Center(child: TextButton(
              onPressed: () => showDialog<bool>(context: ctx, barrierDismissible: false,
                  builder: (_) => DayApplicantsDialog(date: kDate, businessIds: const [kBiz], businesses: [_business()], reads: reads)),
              child: const Text('open'))))),
        ),
      ),
    ));
    await tester.pump();
    await tester.tap(find.text('open'));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return (key: key, overflows: overflows);
  }
  Map<String, Object?> b2Cond(WidgetTester tester, Size size, double scale, String scroll) => {
        'screen': 'DayApplicantsDialog via showDialog(barrierDismissible:false)', 'theme': 'RoleTheme.businessAdminTheme',
        'viewport': '${size.width.toInt()}x${size.height.toInt()}', 'dpr': 1.0, 'textScaler': scale,
        'inset': 'padding(${tester.view.padding.top},${tester.view.padding.bottom}) viewInsets(${tester.view.viewInsets.bottom})',
        'fonts': 'vqLoadFonts: NotoSansKR Regular+Bold · Roboto=NotoSansKR · MaterialIcons(SDK) · FlutterTest 미등록 — 기기 글꼴 아님',
        'data': 'ARO-L: 대기30(아주긴이름의지원자홍길동0..29)·확정3·cap wd1=40·owner·단일사업장 · fixture date 2026-09-29(고정) · 화면 직접 시계 미주입',
        'scroll': scroll};

  testWidgets('B2-L-A 인력 현황 392×844@1.0 첫 화면 — 필수 수치·넘침 0', (tester) async {
    const size = Size(392, 844);
    final o = await b2Open(tester, size: size, scale: 1.0);
    expect(find.byType(DayApplicantsDialog), findsOneWidget);
    expect(findVisibleTextContaining('3/3명'), findsWidgets);
    expect(findVisibleTextContaining('지원 (30건)'), findsWidgets);
    expect(o.overflows, isEmpty, reason: o.overflows.join(' | '));
    expect(tester.takeException(), isNull);
    await vqCapture(tester, o.key, 'B2-L-A_day_applicants_392x1', conditions: b2Cond(tester, size, 1.0, 'none — 첫 화면(내부 ListView offset 0)'));
  });

  // [DU1 후속74 §2] 반복 사람행 구간 — 같은 자료·392×844@1.0, 모달 내부 목록을 실제 drag(목록 왼쪽 여백)로 내린 위치.
  testWidgets('B2-L-R 인력 현황 392×844@1.0 반복 사람행 — 내부 목록 실제 drag', (tester) async {
    const size = Size(392, 844);
    final o = await b2Open(tester, size: size, scale: 1.0);
    final list = find.descendant(of: find.byType(DayApplicantsDialog), matching: find.byType(Scrollable)).last;
    final pos = tester.state<ScrollableState>(list).position;
    final vp = tester.getRect(list);
    final before = pos.pixels;
    for (var k = 0; k < 6; k++) {
      await tester.dragFrom(Offset(vp.left + 6, vp.bottom - 40), const Offset(0, -90));
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    final after = pos.pixels;
    final ok = find.widgetWithText(InkWell, '확정');
    final no = find.widgetWithText(InkWell, '거절');
    final okR = [for (var k = 0; k < ok.evaluate().length; k++) tester.getRect(ok.at(k))].where((r) => r.top >= vp.top && r.bottom <= vp.bottom).toList();
    final noR = [for (var k = 0; k < no.evaluate().length; k++) tester.getRect(no.at(k))].where((r) => r.top >= vp.top && r.bottom <= vp.bottom).toList();
    // ignore: avoid_print
    print('B2-L-R listViewport=$vp offset ${before.toStringAsFixed(1)}→${after.toStringAsFixed(1)} max=${pos.maxScrollExtent.toStringAsFixed(1)} 보이는 확정=${okR.take(2).toList()} 거절=${noR.take(2).toList()}');
    expect(after, greaterThan(before), reason: '실제 drag 로 내려갔다');
    expect(o.overflows, isEmpty, reason: o.overflows.join(' | '));
    expect(tester.takeException(), isNull);
    await vqCapture(tester, o.key, 'B2-L-R_day_applicants_392x1_repeat', conditions: b2Cond(tester, size, 1.0,
        '내부 목록 실제 dragFrom(left+6, bottom-40) -90×6 — offset ${before.toStringAsFixed(1)}→${after.toStringAsFixed(1)} · viewport=$vp'));
  });

  // [DU1 후속75 F75-1] 거절(위험 글자 행동) 실제 InkWell 전체 target ≥ 48×48 · 중앙/새 여백 hit 가 거절 InkWell 로 간다 ·
  //   확정과 비중첩. 첫 화면 첫 행 + 내부 목록 실제 drag 반복 위치. writer(확정/거절)는 누르지 않는다(hitTest 만).
  String b2HitReport(WidgetTester tester, Finder target, Offset p) {
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, p, tester.view.viewId);
    final ro = tester.renderObject(target);
    return 'p=$p in=${hit.path.any((e) => e.target == ro)}';
  }
  bool b2Hits(WidgetTester tester, Finder target, Offset p) {
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, p, tester.view.viewId);
    return hit.path.any((e) => e.target == tester.renderObject(target));
  }
  Future<void> b2RejectCheck(WidgetTester tester, String where, Rect vp) async {
    final no = find.widgetWithText(InkWell, '거절');
    final ok = find.widgetWithText(InkWell, '확정');
    final idx = [for (var k = 0; k < no.evaluate().length; k++) k]
        .where((k) { final r = tester.getRect(no.at(k)); return r.top >= vp.top && r.bottom <= vp.bottom; }).toList();
    expect(idx, isNotEmpty, reason: '$where 표시 영역 안 거절');
    for (final k in idx.take(2)) {
      final t = no.at(k);
      final r = tester.getRect(t);
      final pts = {
        'center': r.center,
        'left+2': Offset(r.left + 2, r.center.dy),
        'right-2': Offset(r.right - 2, r.center.dy),
        'top+2': Offset(r.center.dx, r.top + 2),
        'bottom-2': Offset(r.center.dx, r.bottom - 2),
      };
      // 같은 행 확정(거절과 세로로 겹치는 확정)
      final okRs = [for (var j = 0; j < ok.evaluate().length; j++) tester.getRect(ok.at(j))]
          .where((o) => o.top < r.bottom && o.bottom > r.top).toList();
      final overlap = okRs.any((o) => o.overlaps(r));
      final gap = okRs.isEmpty ? double.nan : okRs.first.left - r.right;
      // ignore: avoid_print
      print('F75-1 $where 거절[$k] rect=$r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} · 같은 행 확정=${okRs.isEmpty ? '-' : okRs.first} gap=${gap.toStringAsFixed(1)} overlap=$overlap · '
          '${pts.entries.map((e) => '${e.key}:${b2HitReport(tester, t, e.value)}').join(' ')}');
      expect(r.width, greaterThanOrEqualTo(48), reason: '$where 거절 폭');
      expect(r.height, greaterThanOrEqualTo(48), reason: '$where 거절 높이');
      for (final e in pts.entries) {
        expect(b2Hits(tester, t, e.value), isTrue, reason: '$where 거절 ${e.key} hit');
      }
      expect(overlap, isFalse, reason: '$where 거절·확정 비중첩');
    }
  }

  testWidgets('F75-1 거절 target 392×844@1.0 — 첫 화면·반복 위치 ≥48 · hit · 확정 비중첩', (tester) async {
    final o = await b2Open(tester, size: const Size(392, 844), scale: 1.0);
    final list = find.descendant(of: find.byType(DayApplicantsDialog), matching: find.byType(Scrollable)).last;
    final vp = tester.getRect(list);
    await b2RejectCheck(tester, '첫 화면', vp);
    for (var k = 0; k < 6; k++) {
      await tester.dragFrom(Offset(vp.left + 6, vp.bottom - 40), const Offset(0, -90));
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    // ignore: avoid_print
    print('F75-1 반복 offset=${tester.state<ScrollableState>(list).position.pixels.toStringAsFixed(1)}');
    await b2RejectCheck(tester, '반복', vp);
    expect(o.overflows, isEmpty, reason: o.overflows.join(' | '));
    expect(tester.takeException(), isNull);
  });

  testWidgets('F75-1 거절 target 320×640@2.0 — 마지막 지원자 거절 전체가 내부 목록 표시 영역 안 · 중앙 hit · ≥48', (tester) async {
    final o = await b2Open(tester, size: const Size(320, 640), scale: 2.0);
    final list = find.descendant(of: find.byType(DayApplicantsDialog), matching: find.byType(Scrollable)).last;
    final pos = tester.state<ScrollableState>(list).position;
    final before = pos.pixels;
    final last = find.textContaining('아주긴이름의지원자홍길동29');
    await tester.scrollUntilVisible(last, 300, scrollable: list, maxScrolls: 300);
    await tester.pump(const Duration(milliseconds: 50));
    final vp = tester.getRect(list);
    final lastTop = tester.getRect(last.first).top;
    final nos = find.widgetWithText(InkWell, '거절');
    final below = [for (var k = 0; k < nos.evaluate().length; k++) nos.at(k)]
        .where((b) => tester.getRect(b).top >= lastTop - 1).toList()
      ..sort((a, b) => tester.getRect(a).top.compareTo(tester.getRect(b).top));
    expect(below, isNotEmpty, reason: '마지막 행 거절');
    final target = below.first;
    var r = tester.getRect(target);
    final adjusted = r.bottom > vp.bottom - 4 || r.top < vp.top + 4;
    if (r.bottom > vp.bottom - 4) pos.jumpTo((pos.pixels + (r.bottom - (vp.bottom - 4))).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    if (r.top < vp.top + 4) pos.jumpTo((pos.pixels - (vp.top + 4 - r.top)).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    await tester.pump(const Duration(milliseconds: 50));
    r = tester.getRect(target);
    final inside = r.top >= vp.top && r.bottom <= vp.bottom && r.left >= vp.left && r.right <= vp.right;
    // ignore: avoid_print
    print('F75-1 B listViewport=$vp 거절=$r ${r.width.toStringAsFixed(1)}×${r.height.toStringAsFixed(1)} offset ${before.toStringAsFixed(1)}→${pos.pixels.toStringAsFixed(1)} '
        'scrollUntilVisible 뒤 jumpTo 보정=$adjusted inside=$inside centerHit=${b2Hits(tester, target, r.center)}');
    expect(inside, isTrue);
    expect(b2Hits(tester, target, r.center), isTrue);
    expect(r.width >= 48 && r.height >= 48, isTrue);
    expect(o.overflows, isEmpty, reason: o.overflows.join(' | '));
    expect(tester.takeException(), isNull);
  });

  Future<void> b2LastTop(WidgetTester tester, {required String id, required Size size}) async {
    final o = await b2Open(tester, size: size, scale: 2.0);
    expect(o.overflows, isEmpty, reason: o.overflows.join(' | '));
    final dlgScroll = find.descendant(of: find.byType(DayApplicantsDialog), matching: find.byType(Scrollable));
    // ignore: avoid_print
    print('$id scrollables=${dlgScroll.evaluate().length} rects=${[for (var i = 0; i < dlgScroll.evaluate().length; i++) tester.getRect(dlgScroll.at(i))]}');
    await vqCapture(tester, o.key, '${id}_top', conditions: b2Cond(tester, size, 2.0, 'none — 첫 화면'));
  }

  // [후속38 §2.3] 주 행동(_actionButton '확정') 실측 — 정적 후보(InkWell+padding, 최소 높이 미명시)를 실제 크기로 기록만 한다(수정 판단 근거).
  testWidgets('B2-L-M 인력 현황 392×844@1.0 — 확정/거절 행동 실측(기록)', (tester) async {
    await b2Open(tester, size: const Size(392, 844), scale: 1.0);
    final ok = find.widgetWithText(InkWell, '확정').first;
    final no = find.widgetWithText(InkWell, '거절').first;
    // ignore: avoid_print
    print('B2-L-M 확정=${tester.getRect(ok)} h=${tester.getSize(ok).height.toStringAsFixed(1)} 거절=${tester.getRect(no)} h=${tester.getSize(no).height.toStringAsFixed(1)}');
    expect(tester.takeException(), isNull);
  });

  testWidgets('B2-L-B 인력 현황 320×640@2.0 첫 화면 — 헤더/통계 읽기·넘침 0', (tester) async {
    await b2LastTop(tester, id: 'B2-L-B_day_applicants_320x2', size: const Size(320, 640));
    expect(tester.takeException(), isNull);
  });

  testWidgets('B2-L-B2 인력 현황 320×640@2.0 — 마지막 지원자 확정 행동 모양 전체가 내부 목록 표시 영역 안 · 중앙 hit', (tester) async {
    const size = Size(320, 640);
    final o = await b2Open(tester, size: size, scale: 2.0);
    final list = find.descendant(of: find.byType(DayApplicantsDialog), matching: find.byType(Scrollable)).last;
    final pos = tester.state<ScrollableState>(list).position;
    final before = pos.pixels;
    final last = find.textContaining('아주긴이름의지원자홍길동29');
    await tester.scrollUntilVisible(last, 300, scrollable: list, maxScrolls: 300);
    await tester.pump(const Duration(milliseconds: 50));
    final vp = tester.getRect(list);
    final lastTop = tester.getRect(last.first).top;
    final btns = find.widgetWithText(InkWell, '확정');
    final below = [for (var k = 0; k < btns.evaluate().length; k++) btns.at(k)]
        .where((b) => tester.getRect(b).top >= lastTop - 1).toList()
      ..sort((a, b) => tester.getRect(a).top.compareTo(tester.getRect(b).top));
    expect(below, isNotEmpty, reason: '마지막 행 확정 행동');
    final target = below.first;
    var r = tester.getRect(target);
    if (r.bottom > vp.bottom - 4) pos.jumpTo((pos.pixels + (r.bottom - (vp.bottom - 4))).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    if (r.top < vp.top + 4) pos.jumpTo((pos.pixels - (vp.top + 4 - r.top)).clamp(pos.minScrollExtent, pos.maxScrollExtent));
    await tester.pump(const Duration(milliseconds: 50));
    r = tester.getRect(target);
    final inside = r.top >= vp.top && r.bottom <= vp.bottom && r.left >= vp.left && r.right <= vp.right;
    final hit = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hit, r.center, tester.view.viewId);
    final hitOk = hit.path.any((e) => e.target == tester.renderObject(target));
    // ignore: avoid_print
    print('B2-L-B2 listViewport=$vp target=$r offset ${before.toStringAsFixed(1)}→${pos.pixels.toStringAsFixed(1)} inside=$inside hit=$hitOk targetH=${r.height.toStringAsFixed(1)}');
    expect(inside, isTrue, reason: '확정 행동 모양 전체가 내부 목록 표시 영역 안');
    expect(hitOk, isTrue, reason: '중앙 hit');
    expect(o.overflows, isEmpty, reason: o.overflows.join(' | '));
    expect(tester.takeException(), isNull);
    await vqCapture(tester, o.key, 'B2-L-B2_day_applicants_320x2_last', conditions: b2Cond(tester, size, 2.0,
        '내부 목록 마지막 지원자 확정 행동까지 실제 스크롤 — offset ${before.toStringAsFixed(1)}→${pos.pixels.toStringAsFixed(1)} · target=$r · viewport=$vp'));
  });
}
