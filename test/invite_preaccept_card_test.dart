// [INVITE-PREACCEPT] 초대 카드가 **지금 무엇을 해야 하는지** 말한다.
//
// ── 무엇이 막혀 있었나 (2026-10-15 DEV 실측) ──────────────────────────
//   자동 판정이 MATCHED 가 아닌 근로자는 초대를 수락할 수 없었다. 서버가
//   사업장 검토를 요구하는데, 사업장은 근로자가 동의해야 검토할 수 있고,
//   초대의 동의는 수락할 때만 기록됐다. 화면은 이 사실을 모른 채
//   `수락하기`를 띄웠고, 누르면 관리자용 문구로 거절됐다.
//   또 `수락하기`를 누른 뒤 확인창이 뜰 때까지(2.4~6.4초) 아무 표시가 없었다.
//
// ── 이 테스트가 보는 것 (실제 MyApplicationsScreen 렌더) ───────────────
//   PC-A  다섯 상태: 동의 필요 · 확인 대기 · 신분증 없음 · 수락 가능 · 모름
//   PC-B  기한이 지난 초대는 준비 상태와 무관하게 수락 비활성
//   PC-C  누르는 즉시 진행 표시 + 중복 탭이 확인창을 두 번 열지 않는다
//   PC-D  동의 창: 수락이 아니라고 말하고, 공식 V3 문구를 **그대로** 보여준다
//   PC-E  320dp × 글자 2.0 에서 문구·버튼이 넘치지 않는다
//   PC-F  서버 값 파싱 — 모르는 값은 unknown
import 'dart:io';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart';
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
/// 요건이 비면 수락 흐름이 서류 등록 화면으로 갈라져 확인창에 닿지 못한다.
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
final DateTime _beforeStart = _start.subtract(const Duration(hours: 3));

ApplicationModel _invite(InviteAcceptReadiness r, {bool consented = false}) =>
    ApplicationModel(
      id: 'inv1',
      toId: 'to1',
      slotId: 'slot1',
      wdId: 'wd-1',
      uid: _kUid,
      businessId: 'biz1',
      businessName: 'QA 사업장',
      toTitle: 'QA 공고',
      status: AppStatus.invited,
      selectedWorkType: 'QA 분류',
      startTime: '20:00',
      endTime: '22:00',
      wage: 13000,
      workDate: _day,
      appliedAt: _day.subtract(const Duration(days: 1)),
      inviteExpiresAt: _start,
      workInstanceCapacityState: InviteCapacityState.available,
      inviteAcceptReadiness: r,
      documentAccessConsentGiven: consented,
      documentAccessConsentVersion: consented ? DocumentAccessConsent.version : null,
    );

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: 'QA 사업장',
      type: 'flex',
      title: 'QA 공고',
      creatorUID: 'admin1',
      status: TOStatus.active,
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
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: MyApplicationsScreen(
          reads: _reads([app]),
          clock: () => clock ?? _beforeStart,
          initialTabIndex: 6,
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

/// 라벨을 품은 가장 가까운 GestureDetector 의 onTap — null 이면 비활성.
VoidCallback? _onTapOf(WidgetTester t, String label) {
  final f = find.text(label);
  if (f.evaluate().isEmpty) return null;
  final gd = find.ancestor(of: f, matching: find.byType(GestureDetector));
  return t.widget<GestureDetector>(gd.first).onTap;
}

bool _overflowed(WidgetTester t) {
  final e = t.takeException();
  return e != null && e.toString().contains('overflowed');
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

  group('PC-A 다섯 상태', () {
    testWidgets('PC-01 동의 필요 → `서류 열람 동의`, 수락 버튼 없음', (t) async {
      await _pump(t, _invite(InviteAcceptReadiness.consentRequired));
      final texts = _texts(t);
      expect(texts, contains('서류 열람 동의'));
      expect(texts.contains('수락하기'), isFalse,
          reason: '서버가 거절할 수락을 먼저 권하지 않는다');
      expect(texts.any((s) => s.startsWith('사업장이 서류를 확인해야 수락할 수 있어요')),
          isTrue);
      expect(_onTapOf(t, '서류 열람 동의'), isNotNull);
      expect(_onTapOf(t, '거절'), isNotNull, reason: '거절은 언제나 할 수 있다');
    });

    testWidgets('PC-02 확인 대기 → 안내 + `수락하기` 비활성', (t) async {
      await _pump(t, _invite(InviteAcceptReadiness.reviewPending, consented: true));
      expect(_texts(t), contains('사업장이 서류를 확인하고 있어요. 확인이 끝나면 수락할 수 있어요.'));
      expect(_onTapOf(t, '수락하기'), isNull);
    });

    testWidgets('PC-03 신분증 없음 → `서류 등록하기`', (t) async {
      await _pump(t, _invite(InviteAcceptReadiness.documentRequired));
      expect(_texts(t), contains('신분증을 등록해야 수락할 수 있어요.'));
      expect(_onTapOf(t, '서류 등록하기'), isNotNull);
      expect(_texts(t).contains('수락하기'), isFalse);
    });

    testWidgets('PC-04 수락 가능 → `수락하기` 활성, 덧붙이는 안내 없음', (t) async {
      await _pump(t, _invite(InviteAcceptReadiness.ready, consented: true));
      expect(_onTapOf(t, '수락하기'), isNotNull);
      final texts = _texts(t);
      expect(texts.any((s) => s.startsWith('사업장이 서류를')), isFalse);
    });

    testWidgets('PC-05 모름(구버전 서버: 필드 없음) → 수락 비활성 + 이유 + 다시 확인',
        (t) async {
      await _pump(t, _invite(InviteAcceptReadiness.unknown));
      expect(_onTapOf(t, '수락하기'), isNull,
          reason: '[INVITE-PARITY] 확인되지 않은 상태로 수락하게 두지 않는다');
      expect(_onTapOf(t, '다시 확인'), isNotNull);
      expect(_texts(t),
          contains('지금은 수락 가능 여부를 확인할 수 없어요. 잠시 후 다시 확인해 주세요.'));
      expect(_texts(t).any((s) => s.startsWith('사업장이 서류를')), isFalse,
          reason: '모르는 것을 확인 대기라고 말하지 않는다');
    });
  });

  group('PC-B 기한 종료', () {
    for (final r in InviteAcceptReadiness.values) {
      testWidgets('PC-06 기한이 지나면 ${r.name} 이어도 수락 비활성', (t) async {
        await _pump(t, _invite(r), clock: _start.add(const Duration(minutes: 1)));
        expect(_texts(t).any((s) => s.startsWith('수락 기한이 지났어요')), isTrue);
        expect(_onTapOf(t, '수락하기'), isNull);
        expect(_texts(t).contains('서류 열람 동의'), isFalse,
            reason: '끝난 초대에 동의를 권하지 않는다(서버도 거절한다)');
      });
    }
  });

  group('PC-C 진행 표시·중복 탭', () {
    testWidgets('PC-07 누른 첫 프레임에 진행 표시가 보이고 버튼이 잠긴다', (t) async {
      await _pump(t, _invite(InviteAcceptReadiness.ready, consented: true));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await t.tap(find.text('수락하기'));
      await t.pump();
      expect(
          find.descendant(
              of: find.ancestor(
                  of: find.text('수락하기'), matching: find.byType(GestureDetector)).first,
              matching: find.byType(CircularProgressIndicator)),
          findsOneWidget,
          reason: '확인창이 뜨기 전에도 눌렸다는 사실이 보여야 한다');
      expect(_onTapOf(t, '수락하기'), isNull, reason: '진행 중에는 다시 누를 수 없다');
    });

    testWidgets('PC-08 두 번 눌러도 확인창은 하나', (t) async {
      await _pump(t, _invite(InviteAcceptReadiness.ready, consented: true));
      await t.tap(find.text('수락하기'));
      await t.pump();
      await t.tap(find.text('수락하기'), warnIfMissed: false);
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('초대 수락'), findsOneWidget);
      // 취소하면 잠금이 풀린다.
      await t.tap(find.text('취소'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(_onTapOf(t, '수락하기'), isNotNull);
    });
  });

  group('PC-D 동의 창', () {
    testWidgets('PC-09 수락이 아니라고 말하고 **초대 문구**를 그대로 보인다', (t) async {
      await _pump(t, _invite(InviteAcceptReadiness.consentRequired));
      await t.tap(find.text('서류 열람 동의'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final texts = _texts(t);
      expect(texts.any((s) => s.contains('동의만으로 근무가 확정되지는 않아요')), isTrue);
      // 초대 화면은 초대 문구(초대 v1)를 보인다 — "지원하기"가 없는 문장.
      for (final part in DocumentAccessConsent.invitePartsFor('QA 사업장')) {
        expect(findVisibleTextContaining(part), findsWidgets, reason: part); // [DU288] 보이는 글자
      }
      expect(texts.any((s) => s.contains('지원하기를 누르면')), isFalse,
          reason: '초대 화면에 지원 문구(V3)를 보이지 않는다');
      expect(find.text('동의하기'), findsOneWidget);
      // 취소 → 아무것도 보내지 않고 닫힌다.
      await t.tap(find.text('취소'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.text('동의하기'), findsNothing);
      expect(_onTapOf(t, '서류 열람 동의'), isNotNull);
    });
  });

  group('PC-E 좁은 화면 · 큰 글자', () {
    for (final r in [
      InviteAcceptReadiness.consentRequired,
      InviteAcceptReadiness.reviewPending,
      InviteAcceptReadiness.documentRequired,
      InviteAcceptReadiness.ready,
    ]) {
      testWidgets('PC-10 320dp × 2.0 — ${r.name} 넘침 0', (t) async {
        await _pump(t, _invite(r, consented: r == InviteAcceptReadiness.reviewPending),
            size: const Size(320, 2400), textScale: 2.0);
        expect(_overflowed(t), isFalse);
      });
    }
    testWidgets('PC-11 320dp × 2.0 — 동의 창 넘침 0, 버튼 보임', (t) async {
      await _pump(t, _invite(InviteAcceptReadiness.consentRequired),
          size: const Size(320, 900), textScale: 2.0);
      await t.tap(find.text('서류 열람 동의'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(_overflowed(t), isFalse);
      expect(find.text('동의하기'), findsOneWidget);
      expect(find.text('동의하기').hitTestable(), findsOneWidget,
          reason: '좁은 화면에서도 동의 버튼을 누를 수 있어야 한다');
      // 동의 내용 끝까지 스크롤해 읽을 수 있다(잘린 채 버튼만 남지 않는다).
      final last = DocumentAccessConsent.invitePartsFor('QA 사업장').last;
      await t.ensureVisible(findVisibleTextContaining(last).first); // [DU288] 보이는 글자
      await t.pump();
      expect(findVisibleTextContaining(last).first.hitTestable(), findsOneWidget);
    });

    testWidgets('PC-17 320dp × 2.0 — 초대 수락 확인창: 초대 문구 끝까지·CTA 접근', (t) async {
      await _pump(t, _invite(InviteAcceptReadiness.ready, consented: true),
          size: const Size(320, 900), textScale: 2.0);
      await t.tap(find.text('수락하기'));
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(_overflowed(t), isFalse);
      expect(findVisibleText('동의하고 초대 수락').hitTestable(), findsOneWidget);
      final last = DocumentAccessConsent.invitePartsFor('QA 사업장').last;
      await t.ensureVisible(findVisibleTextContaining(last).first); // [DU288] 보이는 글자
      await t.pump();
      expect(findVisibleTextContaining(last).first.hitTestable(), findsOneWidget);
      expect(_texts(t).any((s) => s.contains('지원하기를 누르면')), isFalse);
    });
  });

  group('PC-G 조회 실패 · canonical 마감', () {
    testWidgets('PC-15 조회 실패(UNAVAILABLE)는 READY 와 다르다 — 다시 확인할 수 있다',
        (t) async {
      await _pump(t, _invite(InviteAcceptReadiness.unavailable));
      final texts = _texts(t);
      expect(texts, contains('수락할 수 있는지 확인하지 못했어요. 다시 확인해 주세요.'));
      expect(_onTapOf(t, '다시 확인'), isNotNull);
      expect(_onTapOf(t, '수락하기'), isNull,
          reason: '[INVITE-PARITY] 조회 실패는 수락 가능이 아니다');
    });

    testWidgets('PC-20 구 서버(필드 없음)와 조회 실패(UNAVAILABLE)는 서로 다른 이유를 말한다',
        (t) async {
      Map<String, dynamic> raw(String? r) => {
            'toId': 'to1', 'slotId': 'slot1', 'wdId': 'wd-1', 'uid': _kUid,
            'businessId': 'biz1', 'businessName': 'QA 사업장', 'toTitle': 'QA 공고',
            'status': 'INVITED', 'selectedWorkType': 'QA 분류',
            'startTime': '20:00', 'endTime': '22:00', 'wage': 13000,
            'workDate': Timestamp.fromDate(_day),
            'appliedAt': Timestamp.fromDate(_day.subtract(const Duration(days: 1))),
            'inviteExpiresAt': Timestamp.fromDate(_start),
            'workInstanceCapacityState': 'available',
            if (r != null) 'inviteAcceptReadiness': r,
          };
      final oldServer = ApplicationModel.tryFromMap(raw(null), 'inv1')!;
      final failed = ApplicationModel.tryFromMap(raw('UNAVAILABLE'), 'inv1')!;
      expect(oldServer.inviteAcceptReadiness, InviteAcceptReadiness.unknown);
      expect(failed.inviteAcceptReadiness, InviteAcceptReadiness.unavailable);

      await _pump(t, oldServer);
      final a = _texts(t);
      await _pump(t, failed);
      final b = _texts(t);
      expect(a, contains('지금은 수락 가능 여부를 확인할 수 없어요. 잠시 후 다시 확인해 주세요.'));
      expect(b, contains('수락할 수 있는지 확인하지 못했어요. 다시 확인해 주세요.'));
      expect(a.contains('수락할 수 있는지 확인하지 못했어요. 다시 확인해 주세요.'), isFalse);
    });

    testWidgets('PC-21 `다시 확인` 은 목록을 다시 읽는다', (t) async {
      var reads = 0;
      final r = MyApplicationsReads(
        myApplicationsPaged: ({required String uid, required int pageSize,
            String? startAfterDocId}) async {
          reads++;
          return {'items': [_invite(InviteAcceptReadiness.unavailable)],
            'lastDocId': null, 'hasMore': false};
        },
        toOrFailure: (id) async => (to: _to(), failed: false),
        contractsByWorker: (uid) async => const <EmploymentContractModel>[],
        autoExpirePending: (uid) async {},
        monthlyAttendances: ({required String userId, required int year,
            required int month}) async => const <AttendanceModel>[],
        reviewById: (key) async => null,
        taxStatus: () async => const TaxIdentityStatus.unknown(),
      );
      t.view.physicalSize = const Size(390, 2400);
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      await t.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<UserProvider>(create: (_) => _P()),
          ChangeNotifierProvider<NotificationProvider>(
              create: (_) => NotificationProvider()),
        ],
        child: MaterialApp(home: MyApplicationsScreen(
            reads: r, clock: () => _beforeStart, initialTabIndex: 6)),
      ));
      for (var i = 0; i < 25; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      final before = reads;
      await t.tap(find.text('다시 확인'));
      for (var i = 0; i < 25; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(reads, greaterThan(before));
    });

    testWidgets('PC-16 서버 canonical 마감이 snapshot 보다 이르면 그 시각을 따른다',
        (t) async {
      // slot 상 업무가 18:00 에 시작 — snapshot(20:00)보다 이르다.
      final serverDeadline = FormatHelper.kstWallClockInstant(_day, '18:00')!;
      final app = _invite(InviteAcceptReadiness.ready, consented: true)
          .copyWith(inviteAcceptDeadline: serverDeadline);
      await _pump(t, app, clock: serverDeadline.add(const Duration(minutes: 1)));
      expect(_texts(t).any((s) => s.startsWith('수락 기한이 지났어요')), isTrue);
      expect(_texts(t).any((s) => s.contains('10.20 18:00')), isTrue);
      expect(_onTapOf(t, '수락하기'), isNull);
    });

    test('PC-18 V3 문구는 그대로, 초대 문구는 "지원하기"가 없다 — 한 토큰 = 한 문장', () {
      expect(DocumentAccessConsent.version, '2026-09-18-v3');
      expect(DocumentAccessConsent.copyFor('X').startsWith('지원하기를 누르면 [X]'), isTrue,
          reason: 'V3 를 본 사람들의 기록이 거짓이 되지 않게 V3 는 바꾸지 않는다');
      expect(DocumentAccessConsent.inviteVersion, isNot(DocumentAccessConsent.version));
      expect(DocumentAccessConsent.inviteCopyFor('X').contains('지원하기'), isFalse);
      expect(DocumentAccessConsent.inviteCopyFor('X').startsWith('동의하면 [X]'), isTrue);
      expect(DocumentAccessConsent.invitePartsFor('X').join('\n'),
          DocumentAccessConsent.inviteCopyFor('X'));
      expect(DocumentAccessConsent.reviewPurposeVersions,
          {DocumentAccessConsent.version, DocumentAccessConsent.inviteVersion});
    });

    test('PC-19 초대 수락 경로 두 곳(내 지원·공고 상세)은 초대 문구·초대 버전을 보낸다', () {
      for (final p in ['lib/screens/user/my_applications_screen.dart',
        'lib/screens/common/job_posting_screen.dart']) {
        final s = File(p).readAsStringSync();
        final i = s.indexOf("httpsCallable('callableAcceptTOInvitation')");
        expect(i, greaterThan(0), reason: p);
        final around = s.substring(i, i + 700);
        expect(around.contains('DocumentAccessConsent.inviteVersion'), isTrue, reason: p);
        expect(around.contains('DocumentAccessConsent.version,'), isFalse, reason: p);
      }
    });
  });

  group('PC-F 서버 값', () {
    test('PC-12 문자열 → 상태, 모르는 값은 unknown', () {
      expect(parseInviteAcceptReadiness('READY'), InviteAcceptReadiness.ready);
      expect(parseInviteAcceptReadiness('CONSENT_REQUIRED'),
          InviteAcceptReadiness.consentRequired);
      expect(parseInviteAcceptReadiness('REVIEW_PENDING'),
          InviteAcceptReadiness.reviewPending);
      expect(parseInviteAcceptReadiness('DOCUMENT_REQUIRED'),
          InviteAcceptReadiness.documentRequired);
      expect(parseInviteAcceptReadiness('UNAVAILABLE'),
          InviteAcceptReadiness.unavailable);
      for (final x in [null, '', 'ready', 'MATCHED', 1]) {
        expect(parseInviteAcceptReadiness(x), InviteAcceptReadiness.unknown, reason: '$x');
      }
    });

    test('PC-13 fromMap 은 서버 필드를 읽고, 없으면 unknown', () {
      final base = {
        'toId': 't', 'uid': 'u', 'businessId': 'b', 'businessName': 'B',
        'toTitle': 'T', 'status': 'INVITED', 'selectedWorkType': 'W',
        'startTime': '20:00', 'endTime': '22:00', 'wage': 1,
        'workDate': Timestamp.fromDate(DateTime.utc(2026, 10, 20)),
        'appliedAt': Timestamp.fromDate(DateTime.utc(2026, 10, 19)),
      };
      final a = ApplicationModel.tryFromMap(
          {...base, 'inviteAcceptReadiness': 'REVIEW_PENDING'}, 'x');
      expect(a?.inviteAcceptReadiness, InviteAcceptReadiness.reviewPending);
      final b = ApplicationModel.tryFromMap(base, 'y');
      expect(b?.inviteAcceptReadiness, InviteAcceptReadiness.unknown);
    });

    test('PC-14 V3 동의 판정은 공식 버전 문자열 하나를 본다', () {
      expect(_invite(InviteAcceptReadiness.unknown, consented: true)
          .hasReviewPurposeConsent, isTrue);
      final v2 = _invite(InviteAcceptReadiness.unknown, consented: true)
          .copyWith(documentAccessConsentVersion: '2026-09-12-v2');
      expect(v2.hasReviewPurposeConsent, isFalse);
    });
  });
}
