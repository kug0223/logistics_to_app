// [INVITE-CLOSURE-PROJECTION] 공개 지원 접수가 자동으로 끝나도 **이미 받은 초대**는
// 유효 기한까지 수락할 수 있다 — 근로자 카드가 서버 수락 판정과 같은 말을 한다.
//
// ── 무엇이 틀려 있었나 (2026-10-15 에뮬레이터 실번들 CX-4) ─────────────────
//   지원 마감 시각에 스케줄러가 업무 closedAt·슬롯 closed(TIME_EXPIRED)를 쓰면
//   근로자 목록 응답이 사유와 무관하게 `closed` 를 보냈고, 카드는
//   `모집이 종료된 초대예요` + `초대 정리` 만 보였다. 서버는 수락을 받는데
//   근로자는 누를 버튼이 없었고, `초대 정리` 를 누르면 **유효한 초대가
//   REJECTED(근로자 거절)** 로 기록됐다.
//
// ── 이 테스트가 보는 것 (실제 MyApplicationsScreen 렌더 → 누를 수 있는 행동) ──
//   IC-A  자동 접수 마감 후 유효 초대: 준비 상태별 행동(수락·검토 대기·모름)
//   IC-B  초대 효력 종료(수동 마감·삭제): 사유 문구, 어떤 쓰기 버튼도 없다
//   IC-C  정원 소진: 끝난 초대가 아니다 — `거절`(본인 결정), `초대 정리` 아님
//   IC-D  근무 시작 정각·만료
//   IC-E  역검증: 유효한 초대에서 `초대 정리` 가 어디에도 없다
//   IC-F  320dp × 글자 2.0 넘침 없음 · 서버 필드 파싱
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/attendance_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/ui/invite_accept_readiness.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/user/my_applications_reads.dart';
import 'package:ALfit/screens/user/my_applications_screen.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/widgets/dialogs/apply/document_access_consent.dart';

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

/// 지원 요건을 갖춘 **테스트용** 사용자 — 실제 신원·계좌 검증이 아니다.
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

final DateTime _day = FormatHelper.toKstDate(DateTime.utc(2026, 10, 20));
final DateTime _start = FormatHelper.kstWallClockInstant(_day, '20:00')!;
/// 지원 마감(19:00)은 지났고 근무 시작(20:00) 전 — 자동 접수 마감과 수락 기한 사이.
final DateTime _afterIntake = _start.subtract(const Duration(minutes: 30));

ApplicationModel _invite({
  InviteCapacityState cap = InviteCapacityState.available,
  InviteAcceptReadiness r = InviteAcceptReadiness.ready,
  bool intakeClosed = true,
  String? ended,
  String status = AppStatus.invited,
}) =>
    ApplicationModel(
      id: 'inv1',
      toId: 'to1',
      slotId: 'slot1',
      wdId: 'wd-1',
      uid: _kUid,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toTitle: 'QA 공고',
      status: status,
      selectedWorkType: 'QA 분류',
      startTime: '20:00',
      endTime: '22:00',
      wage: 13000,
      workDate: _day,
      appliedAt: _day.subtract(const Duration(days: 1)),
      invitedAt: _day.subtract(const Duration(hours: 4)),
      inviteExpiresAt: _start,
      inviteAcceptDeadline: cap == InviteCapacityState.closed ? null : _start,
      workInstanceCapacityState: cap,
      inviteAcceptReadiness: r,
      publicIntakeClosed: intakeClosed,
      inviteEndedReason: ended,
      documentAccessConsentGiven: true,
      documentAccessConsentVersion: DocumentAccessConsent.version,
    );

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: 'QA 사업장',
      type: 'flex',
      title: 'QA 공고',
      creatorUID: 'admin1',
      status: TOStatus.closed,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 3,
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

Future<void> _pump(
  WidgetTester t,
  ApplicationModel app, {
  DateTime? clock,
  Size size = const Size(390, 2400),
  double textScale = 1.0,
}) async {
  t.view.physicalSize = size;
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
        theme: ThemeData(fontFamily: 'NotoSansKR'),
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: MyApplicationsScreen(
          reads: _reads([app]),
          clock: () => clock ?? _afterIntake,
          initialTabIndex: app.status == AppStatus.invited ? 6 : 0,
        ),
      ),
    ),
  );
  for (var i = 0; i < 25; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

List<String> _texts(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? '')
    .where((s) => s.isNotEmpty)
    .toList();

VoidCallback? _onTapOf(WidgetTester t, String label) {
  final f = find.text(label);
  if (f.evaluate().isEmpty) return null;
  final gd = find.ancestor(of: f, matching: find.byType(GestureDetector));
  return t.widget<GestureDetector>(gd.first).onTap;
}

const _intakeLine = '공개 모집은 마감됐지만, 받은 초대는 기한까지 수락할 수 있어요';

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

  group('IC-A 자동 접수 마감 후 유효한 초대', () {
    testWidgets('IC-01 준비 완료 → `수락하기` 활성 + 공개 모집 마감 안내 + 기한', (t) async {
      await _pump(t, _invite());
      final texts = _texts(t);
      expect(texts, contains(_intakeLine));
      expect(texts.any((s) => s.startsWith('~') && s.endsWith('만료')), isTrue,
          reason: '정확한 수락 기한을 말한다');
      expect(_onTapOf(t, '수락하기'), isNotNull);
      expect(texts.contains('모집이 마감된 초대예요'), isFalse);
      expect(texts.contains('초대 정리'), isFalse);
    });

    testWidgets('IC-02 서류 검토 대기 → 검토 안내 + `수락하기` 비활성', (t) async {
      await _pump(t, _invite(r: InviteAcceptReadiness.reviewPending));
      final texts = _texts(t);
      expect(texts, contains(_intakeLine));
      expect(texts, contains('사업장이 서류를 확인하고 있어요. 확인이 끝나면 수락할 수 있어요.'));
      expect(_onTapOf(t, '수락하기'), isNull);
    });

    testWidgets('IC-03 준비 상태 조회 실패(UNAVAILABLE) → 수락 가능으로 단정하지 않는다', (t) async {
      await _pump(t, _invite(r: InviteAcceptReadiness.unavailable));
      expect(_onTapOf(t, '수락하기'), isNull);
      expect(_onTapOf(t, '다시 확인'), isNotNull);
    });

    testWidgets('IC-04 준비 상태 모름(UNKNOWN) → 수락 비활성', (t) async {
      await _pump(t, _invite(r: InviteAcceptReadiness.unknown));
      expect(_onTapOf(t, '수락하기'), isNull);
    });

    testWidgets('IC-05 공개 모집이 열려 있으면 마감 안내를 붙이지 않는다', (t) async {
      await _pump(t, _invite(intakeClosed: false));
      expect(_texts(t).contains(_intakeLine), isFalse);
      expect(_onTapOf(t, '수락하기'), isNotNull);
    });
  });

  group('IC-B 초대 효력 종료', () {
    testWidgets('IC-06 수동 마감(RECRUIT_ENDED) → 사유 문구, 수락·거절·정리 버튼 없음', (t) async {
      await _pump(t, _invite(cap: InviteCapacityState.closed, ended: 'RECRUIT_ENDED'));
      final texts = _texts(t);
      expect(texts, contains('모집이 마감된 초대예요'));
      expect(texts, contains('사업장이 모집을 마감해 수락할 수 없어요'));
      expect(texts, contains('초대 기한이 지나면 목록에서 자동으로 정리돼요'));
      for (final label in const ['수락하기', '거절', '초대 정리', '서류 열람 동의']) {
        expect(_onTapOf(t, label), isNull, reason: '$label 이 눌린다 — 원장 사유와 다른 기록이 생긴다');
      }
    });

    testWidgets('IC-07 공고 삭제(POSTING_DELETED) → 삭제 문구', (t) async {
      await _pump(t, _invite(cap: InviteCapacityState.closed, ended: 'POSTING_DELETED'));
      final texts = _texts(t);
      expect(texts, contains('삭제된 공고의 초대예요'));
      expect(texts, contains('이 근무는 더 이상 진행되지 않아요'));
      expect(texts.contains('모집이 마감된 초대예요'), isFalse);
    });
  });

  group('IC-C 정원 소진', () {
    testWidgets('IC-08 끝난 초대가 아니다 — `거절`(본인 결정)만, `초대 정리`·`수락하기` 없음', (t) async {
      await _pump(t, _invite(cap: InviteCapacityState.full));
      final texts = _texts(t);
      expect(texts, contains('모집 인원이 찼어요'));
      expect(texts, contains('자리가 다시 생기면 수락할 수 있어요'));
      expect(_onTapOf(t, '거절'), isNotNull);
      expect(texts.contains('초대 정리'), isFalse);
      expect(_onTapOf(t, '수락하기'), isNull);
    });
  });

  group('IC-D 근무 시작 정각·만료', () {
    testWidgets('IC-09 시작 1분 전 → 수락 가능', (t) async {
      await _pump(t, _invite(), clock: _start.subtract(const Duration(minutes: 1)));
      expect(_onTapOf(t, '수락하기'), isNotNull);
    });
    testWidgets('IC-10 시작 정각 → 기한 종료, 수락 비활성(서버 `근무가 이미 시작` 과 같다)', (t) async {
      await _pump(t, _invite(), clock: _start);
      expect(_texts(t).any((s) => s.startsWith('수락 기한이 지났어요')), isTrue);
      expect(_onTapOf(t, '수락하기'), isNull);
      expect(_texts(t).contains(_intakeLine), isFalse, reason: '기한이 지난 초대에 수락 가능을 말하지 않는다');
    });
    testWidgets('IC-11 EXPIRED → 유효기간 종료 문구, 행동 없음', (t) async {
      await _pump(t, _invite(status: AppStatus.expired));
      expect(_texts(t), contains('초대 유효기간이 종료되었어요'));
      expect(_onTapOf(t, '수락하기'), isNull);
      expect(_onTapOf(t, '초대 정리'), isNull);
    });
  });

  group('IC-E 역검증 — 유효한 초대를 정리(거절 기록)할 수 없다', () {
    for (final cap in const [InviteCapacityState.available, InviteCapacityState.full,
        InviteCapacityState.unknown]) {
      for (final r in InviteAcceptReadiness.values) {
        testWidgets('IC-12 ${cap.name}·${r.name} — `초대 정리` 없음', (t) async {
          await _pump(t, _invite(cap: cap, r: r));
          expect(_texts(t).contains('초대 정리'), isFalse);
        });
      }
    }
  });

  group('IC-F 레이아웃·파싱', () {
    for (final c in [
      ('자동 마감 유효 초대', _invite(r: InviteAcceptReadiness.reviewPending)),
      ('수동 마감', _invite(cap: InviteCapacityState.closed, ended: 'RECRUIT_ENDED')),
      ('정원 소진', _invite(cap: InviteCapacityState.full)),
    ]) {
      testWidgets('IC-13 320dp × 2.0 — ${c.$1} 넘침 없음', (t) async {
        final errors = <FlutterErrorDetails>[];
        final prev = FlutterError.onError;
        FlutterError.onError = errors.add;
        await _pump(t, c.$2, size: const Size(320, 2400), textScale: 2.0);
        FlutterError.onError = prev;
        expect(errors.where((e) => e.toString().contains('overflowed')), isEmpty);
      });
    }

    test('IC-14 서버 필드 파싱 — 없으면 false/null(구버전 서버)', () {
      final base = {
        'toId': 't', 'uid': 'u', 'businessId': 'b', 'businessName': 'B',
        'toTitle': 'T', 'status': 'INVITED', 'selectedWorkType': 'W',
        'startTime': '20:00', 'endTime': '22:00', 'wage': 1,
        'workDate': Timestamp.fromDate(DateTime.utc(2026, 10, 20)),
        'appliedAt': Timestamp.fromDate(DateTime.utc(2026, 10, 19)),
      };
      final a = ApplicationModel.tryFromMap({...base, 'workInstanceCapacityState': 'available',
        'publicIntakeClosed': true}, 'x')!;
      expect(a.publicIntakeClosed, isTrue);
      expect(a.inviteEndedReason, isNull);
      final b = ApplicationModel.tryFromMap({...base, 'workInstanceCapacityState': 'closed',
        'publicIntakeClosed': true, 'inviteEndedReason': 'POSTING_DELETED'}, 'y')!;
      expect(b.workInstanceCapacityState, InviteCapacityState.closed);
      expect(b.inviteEndedReason, 'POSTING_DELETED');
      final c = ApplicationModel.tryFromMap(base, 'z')!;
      expect(c.publicIntakeClosed, isFalse);
      expect(c.inviteEndedReason, isNull);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // [IC-OLD] 새 앱 × **구 서버(DEV 배포본)** 응답 모양 — 설치 앱 관찰이 아니다.
  //   구 서버는 publicIntakeClosed·inviteEndedReason 을 내리지 않는다(없음 = false/null).
  //   capacity 값은 로컬 에뮬레이터에서 DEV 배포본이 실제로 돌려준 값이다
  //   (scripts/invite-matrix-runtime.js BUNDLE=e06c).
  // ══════════════════════════════════════════════════════════════
  group('IC-OLD 새 앱 + 구 서버 응답', () {
    testWidgets('IC-OLD-1 자동 접수 마감 뒤 유효한 초대 — 구 서버는 closed 로 내린다 → 마감 안내, 버튼 없음', (t) async {
      await _pump(t, _invite(cap: InviteCapacityState.closed, intakeClosed: false));
      final s = _texts(t);
      expect(s, contains('모집이 마감된 초대예요'));
      expect(find.text('수락하기'), findsNothing);
      expect(find.text('거절'), findsNothing);
      expect(find.text('초대 정리'), findsNothing);
    });
    testWidgets('IC-OLD-2 정원 찬 초대 — full → 인원 찼음 안내 + `거절`만', (t) async {
      await _pump(t, _invite(cap: InviteCapacityState.full, intakeClosed: false));
      expect(_texts(t), contains('모집 인원이 찼어요'));
      expect(find.text('거절'), findsOneWidget);
      expect(find.text('수락하기'), findsNothing);
      expect(find.text('초대 정리'), findsNothing);
    });
    testWidgets('IC-OLD-3 원인 불명 종료 — 구 서버는 available 로 내린다 → `수락하기`가 보이고 누르면 서버가 거절한다', (t) async {
      await _pump(t, _invite(cap: InviteCapacityState.available, intakeClosed: false));
      expect(find.text('수락하기'), findsOneWidget,
          reason: '구 서버의 오판(available)을 새 앱이 그대로 보여 준다 — 수락은 서버가 거절(행렬 실측)');
      expect(find.text(_intakeLine), findsNothing, reason: '구 서버엔 공개 마감 표시가 없다');
    });
    testWidgets('IC-OLD-4 판정 불가(unknown) → 확인 실패 안내 + `거절`', (t) async {
      await _pump(t, _invite(cap: InviteCapacityState.unknown, intakeClosed: false));
      expect(_texts(t), contains('근무 가능 여부를 확인하지 못했어요'));
      expect(find.text('거절'), findsOneWidget);
      expect(find.text('수락하기'), findsNothing);
    });
  });
}
