// ignore_for_file: depend_on_referenced_packages
// [R7-PREDEVICE-DISCLOSURE-RENDER.1] 근태·급여 고지 네 화면 — **실제 렌더**.
//
// ── 왜 필요한가 ─────────────────────────────────────────────────────
//   앞선 Phase 들은 고지 문구와 소비 계약을 소스로 확인했다. 그런데 문구가
//   길어진 변경이었고, 근로자가 **지원 전·수락 전·서명 전**에 그 글을 실제로
//   읽을 수 있는지는 그리지 않고는 알 수 없다. 소스 문자열 검사만으로
//   `RENDER VERIFIED` 라고 적지 않기 위해 네 화면을 모두 pump 한다.
//
// ── 네 화면과 값의 출처 (혼동하면 약속이 바뀐다) ───────────────────
//   공고 상세      `_business.attendanceRules`           = 사업장 **현재**
//   지원 확인      `policyRules` (공고 상세가 넘긴 현재)  = 사업장 **현재**
//   내 지원(수락)  `offerApp.attendancePolicySnapshot`    = **snapshot**
//   계약 서명      `contract.snapshot.attendancePolicy`   = **snapshot**
//
//   앞의 둘은 지원 전이므로 현재 기준이고, 뒤의 둘은 이미 맺힌 약속이므로
//   그 시점에 고정된 값이다. 아래 §TRUTH 가 이 구분을 실제 렌더로 가른다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'support/visible_text.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/business_model.dart';
import 'package:ALfit/models/core/contract_template_model.dart';
import 'package:ALfit/models/core/employment_contract_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/user_region.dart';
import 'package:ALfit/models/core/work_detail_model.dart';
import 'package:ALfit/models/ui/invite_capacity_state.dart';
import 'package:ALfit/models/ui/invite_accept_readiness.dart';
import 'package:ALfit/providers/notification_provider.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/screens/common/job_posting_reads.dart';
import 'package:ALfit/services/work_type_guide_resolver.dart';
import 'package:ALfit/screens/common/job_posting_screen.dart';
import 'package:ALfit/screens/contract/contract_sign_screen.dart';
import 'package:ALfit/screens/user/my_applications_reads.dart';
import 'package:ALfit/services/tax_identity_service.dart';
import 'package:ALfit/screens/user/my_applications_screen.dart';
import 'package:ALfit/utils/attendance_policy_disclosure.dart';
import 'package:ALfit/widgets/dialogs/apply/apply_confirm_dialog.dart';

// ═══════════════════════════════════════════════════════════════
// 공통 — Firebase 가짜 코어 · 기준 설정값 · 렌더 매트릭스
// ═══════════════════════════════════════════════════════════════

class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k',
      appId: 'a',
      messagingSenderId: 's',
      projectId: 'p',
      storageBucket: 'p.appspot.com');
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

/// 기본 설정 — 유예 5분 · 단위 30분. 운영 DEV 사업장과 같은 값이다.
AttendanceRules _standard() => AttendanceRules.defaults().copyWith(
      earlyWindow: 30,
      earlyArrivalUnit: 30,
      lateGrace: 5,
      lateUnit: 30,
      lateWindow: 30,
      overtimeUnit: 30,
      earlyLeaveUnit: 30,
    );

/// 경계값 — 유예 0 · 단위 5분. 사례 숫자가 기본값과 달라져야 한다.
AttendanceRules _boundary() => AttendanceRules.defaults().copyWith(
      earlyWindow: 0,
      earlyArrivalUnit: 5,
      lateGrace: 0,
      lateUnit: 5,
      lateWindow: 0,
      overtimeUnit: 5,
      earlyLeaveUnit: 5,
    );

/// 가장 긴 문장 조합 — 두 자리 숫자 두 개가 들어간다.
AttendanceRules _longest() => AttendanceRules.defaults().copyWith(
      earlyWindow: 120,
      earlyArrivalUnit: 60,
      lateGrace: 30,
      lateUnit: 60,
      lateWindow: 60,
      overtimeUnit: 60,
      earlyLeaveUnit: 60,
    );

const _widths = <double>[320, 360, 411];
const _scales = <double>[1.0, 1.3, 2.0];

/// 화면에 실제로 그려진 Text 를 모두 모은다.
String _visible(WidgetTester t) => t
    .widgetList<Text>(find.byType(Text))
    .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
    .where((s) => s.isNotEmpty)
    .join('\n');

/// 7개 고지 줄이 **값까지** 화면에 있는지 본다. 라벨만 있으면 고지가 아니다.
void expectAllSevenLines(WidgetTester t, AttendanceRules r, String where) {
  final shown = _visible(t);
  final lines = attendancePolicyLines(r);
  expect(lines.length, 7, reason: '고지 항목 수가 7이 아니다');
  for (final l in lines) {
    expect(shown.contains(l.value), isTrue,
        reason: '$where — "${l.label}" 의 값이 화면에 없다\n'
            '  기대: ${l.value}');
  }
  // 말줄임으로 잘린 흔적이 없다.
  expect(shown.contains('…'), isFalse, reason: '$where — 고지가 말줄임됐다');
}

/// [.29-A1] 공고·초대·계약은 '근태 인정 기준' 구조다 — 기준 설명(7개 값이 모두 들어 있다)이 전부 보이고 잘리지 않는다.
List<String> _guidePoints(AttendanceRuleGuide g) =>
    g.sections.expand((s) => s.items).expand((i) => i.points).toList();

void expectRuleGuide(WidgetTester t, AttendanceRules r, String where,
    {String? start, String? end}) {
  final shown = visibleText(_visible(t));
  final points = _guidePoints(attendanceRuleGuide(r, startHHmm: start, endHHmm: end));
  expect(points.length, greaterThanOrEqualTo(4), reason: '기준 설명 수가 너무 적다');
  for (final p in points) {
    expect(shown.contains(p), isTrue, reason: '$where — 기준 설명이 화면에 없다: $p');
  }
  for (final n in [r.earlyWindow, r.earlyArrivalUnit, r.lateGrace, r.lateUnit, r.lateWindow, r.overtimeUnit, r.earlyLeaveUnit]) {
    if (n == 0) continue; // 0 은 '분' 으로 말하지 않는다(설명 형태가 바뀐다)
    expect(shown.contains('$n분'), isTrue, reason: '$where — 기준값 $n분이 화면에 없다');
  }
  expect(shown.contains('…'), isFalse, reason: '$where — 고지가 말줄임됐다');
}

/// 사례('예: 18:06 출근 →' / '인정 시작 18:30')가 보이는지 — 입력과 결과는 각각 한 덩어리 글자다.
void expectGuideExamples(WidgetTester t, AttendanceRuleGuide g, String where, {bool visible = true}) {
  final shown = visibleText(_visible(t));
  for (final e in g.sections.expand((s) => s.items).expand((i) => i.examples)) {
    expect(shown.contains('예: ${e.input} →') && shown.contains(e.result), visible,
        reason: '$where — 사례 ${visible ? '없음' : '보임'}: ${attendanceRuleExampleText(e)}');
  }
}

Future<void> _settle(WidgetTester t, {int rounds = 14}) async {
  for (var i = 0; i < rounds; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

// ═══════════════════════════════════════════════════════════════
// 모델 fixture — 합성 데이터만. 실제 개인정보를 쓰지 않는다.
// ═══════════════════════════════════════════════════════════════

class _Worker extends UserProvider {
  _Worker();

  // [DU466 · 후속115 §2-5] 넘기는 곳이 없던 선택 매개변수만 없앴다 — 값은 예전 기본값 그대로(true).
  final bool docsReady = true;

  @override
  UserModel? get currentUser => UserModel(
        uid: 'u1',
        username: 'u1',
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        homeRegion: const UserRegion(province: '서울특별시', city: '강남구'),
        accountStatus: 'active',
        // 초대 수락은 직접 지원과 같은 서류 문턱을 지난다
        // (`meetsApplyPrerequisites`). 그 문턱을 **우회하지 않고** 실제로
        // 넘을 수 있는 합성 사용자를 만든다 — 실제 개인정보는 쓰지 않는다.
        passVerifiedAt: DateTime(2026, 1, 1),
        isIdVerified: docsReady,
        idCardImagePath: docsReady ? 'users/u1/id.png' : null,
        bankName: docsReady ? '테스트은행' : null,
        accountNumber: docsReady ? '0000000000' : null,
        accountHolder: docsReady ? '김근로' : null,
        bankbookImagePath: docsReady ? 'users/u1/bankbook.png' : null,
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

DateTime _kstInstant(int y, int mo, int d) =>
    DateTime.utc(y, mo, d).subtract(const Duration(hours: 9));

/// 오늘(KST)로부터 [plusDays] 일 뒤의 KST 자정 instant — 날짜가 지나도
/// 깨지지 않는 fixture 용.
DateTime _futureKstDay(int plusDays) {
  final k = DateTime.now().toUtc().add(Duration(hours: 9, days: plusDays));
  return _kstInstant(k.year, k.month, k.day);
}

WorkDetailData _wdData() => WorkDetailData(
      wdId: 'wd1',
      workType: '냉장 분류',
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 53000,
      wageType: 'daily',
      requiredCount: 2,
      startTime: '18:00',
      endTime: '22:30',
      order: 0,
    );

WorkDetailModel _wdModel() => WorkDetailModel(
      wdId: 'wd1',
      workType: '냉장 분류',
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 53000,
      wageType: 'daily',
      requiredCount: 2,
      startTime: '18:00',
      endTime: '22:30',
    );

TOModel _to() => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '중앙물류센터',
      type: 'flex',
      title: '냉장 분류 단기 모집',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 4,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

BusinessModel _business(AttendanceRules rules) => BusinessModel(
      id: 'biz1',
      name: '중앙물류센터',
      ownerId: 'admin1',
      businessNumber: '0000000000',
      address: '경기도 평택시 진위면 마산8로 10',
      category: '물류',
      subCategory: '창고',
      isApproved: true,
      createdAt: DateTime(2025),
      attendanceRules: rules,
    );

JobPostingReads _postingReads(AttendanceRules rules) => JobPostingReads(
      toOrFailure: (id) async => (to: _to(), failed: false),
      workDetails: (id) async => const <WorkDetailModel>[],
      businessById: (id) async => _business(rules),
      slots: (id, {bool visibleOnly = true}) async => [
            SlotModel(
              id: 's1',
              toId: 'to1',
              date: _kstInstant(2026, 10, 10),
              workDetails: [_wdData()],
              status: SlotStatus.open,
              confirmedCount: 0,
              createdAt: DateTime(2025),
            ),
          ],
      myApplications: (uid) async => const <ApplicationModel>[],
      workTypeCatalog: (id) async => WorkTypeCatalog.empty,
      applicationOnce: (id) async => null,
    );

ContractSnapshot _snapshot({AttendanceRules? policy}) => ContractSnapshot(
      businessName: '중앙물류센터',
      businessNumber: '0000000000',
      businessAddress: '경기도 평택시 진위면 마산8로 10',
      ownerName: '박사장',
      workerName: '김근로',
      workType: '냉장 분류',
      workPlace: '경기도 평택시 진위면 마산8로 10',
      isLongTerm: false,
      contractStart: '2026-10-10',
      contractEnd: '2026-10-10',
      workDays: const ['토'],
      startTime: '18:00',
      endTime: '22:30',
      breakMinutes: 30,
      wage: 53000,
      wageType: 'daily',
      paymentMethod: '계좌이체',
      wagePaymentDay: 10,
      taxDeductionType: 'none',
      attendancePolicy: policy,
    );

EmploymentContractModel _contract({AttendanceRules? policy}) =>
    EmploymentContractModel(
      id: 'c1',
      applicationId: 'to1_s1_wd1_u1',
      businessId: 'biz1',
      workerId: 'u1',
      isLongTerm: false,
      toId: 'to1',
      workDetailId: 'wd1',
      slots: const [
        ContractSlot(
          applicationId: 'to1_s1_wd1_u1',
          workDate: '2026-10-10',
          startTime: '18:00',
          endTime: '22:30',
          wage: 53000,
          wageType: 'daily',
        ),
      ],
      applicationIds: const ['to1_s1_wd1_u1'],
      status: ContractStatus.pendingWorker,
      snapshot: _snapshot(policy: policy),
      articles: const [
        ContractArticle(title: '제1조 (근로계약기간)', content: '본 계약은 ...'),
      ],
      templateId: 'tpl1',
      createdAt: DateTime(2026, 10, 1),
    );

// ═══════════════════════════════════════════════════════════════
// pump 헬퍼
// ═══════════════════════════════════════════════════════════════

Future<void> _pumpHost(
  WidgetTester t,
  Widget home, {
  required Size size,
  required double textScale,
  UserProvider? provider,
}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.reset);
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump(const Duration(milliseconds: 50));
  await t.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<UserProvider>(
            create: (_) => provider ?? _Worker()),
        ChangeNotifierProvider<NotificationProvider>(
            create: (_) => NotificationProvider()),
      ],
      child: MaterialApp(
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: home,
      ),
    ),
  );
  await _settle(t, rounds: 20);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUpAll(() async {
    initializeDateFormatting('ko');
    FirebasePlatform.instance = _FakeCore();
    await Firebase.initializeApp();
  });

  // ═══════════════════════════════════════════════════════════
  // D. 공고 상세 — 지원 **전**, 사업장 현재 기준
  // ═══════════════════════════════════════════════════════════
  group('[D] 공고 상세', () {
    /// [.29-A1] 공고 상세를 띄우고 '근태 인정 기준' 블록까지 내린다 — 상세 시트는 없어졌다(기준을 처음부터 보인다).
    Future<void> openPostingGuide(
      WidgetTester t, {
      required AttendanceRules rules,
      required Size size,
      required double textScale,
    }) async {
      await _pumpHost(
        t,
        JobPostingScreen(
            to: _to(), workDetails: const [], reads: _postingReads(rules)),
        size: size,
        textScale: textScale,
      );
      final title = findVisibleText(kAttendanceRuleGuideTitle);
      expect(title, findsOneWidget, reason: '공고 상세에 근태 인정 기준이 없다');
      await t.ensureVisible(title);
      await _settle(t);
    }

    testWidgets('D-1 지원 전에 핵심 기준이 처음부터 보인다 — 상세 시트에 숨기지 않는다', (t) async {
      await openPostingGuide(t,
          rules: _standard(), size: const Size(360, 780), textScale: 1.0);
      expect(t.takeException(), isNull);
      expectRuleGuide(t, _standard(), '공고 상세');
      final shown = _visible(t);
      expect(shown.contains(kAttendancePolicyEffectNote), isTrue,
          reason: '인정 시간이 급여 기준이라는 영향 설명이 없다');
      expect(find.text('상세 기준'), findsNothing, reason: '같은 설명을 시트에 한 번 더 두지 않는다');
    });

    testWidgets('D-2 근무 시각을 모르면 사례 없이 설명만 — 사례를 짐작하지 않는다', (t) async {
      await openPostingGuide(t,
          rules: _standard(), size: const Size(360, 780), textScale: 1.0);
      expect(find.text('시간 예시 보기'), findsNothing);
      expect(visibleText(_visible(t)).contains('예: '), isFalse);
    });

    testWidgets('D-3 사업장 **현재** 기준을 보여준다 — snapshot 이 아니다', (t) async {
      // 경계값 사업장으로 바꾸면 화면 문장도 바뀐다.
      await openPostingGuide(t,
          rules: _boundary(), size: const Size(360, 780), textScale: 1.0);
      expectRuleGuide(t, _boundary(), '공고 상세(경계값)');
      final shown = visibleText(_visible(t));
      final boundary = _guidePoints(attendanceRuleGuide(_boundary())).toSet();
      // 기본값 사업장에만 있는 문장이 섞여 있지 않다.
      for (final p in _guidePoints(attendanceRuleGuide(_standard()))) {
        if (boundary.contains(p)) continue;
        expect(shown.contains(p), isFalse, reason: '다른 사업장의 기준이 섞였다: $p');
      }
    });

    for (final w in _widths) {
      for (final s in _scales) {
        testWidgets('D-4 ${w.toInt()}dp × 배율 $s — 공고 기준 넘침 0', (t) async {
          await openPostingGuide(t,
              rules: _longest(), size: Size(w, 820), textScale: s);
          expect(t.takeException(), isNull,
              reason: '${w.toInt()}dp × $s 에서 기준 블록이 넘친다');
          // 가장 긴 조합에서도 설명이 사라지지 않는다.
          expectRuleGuide(t, _longest(), '${w.toInt()}dp × $s');
        });
      }
    }
  });

  // ═══════════════════════════════════════════════════════════
  // E. 지원 확인 다이얼로그 — 제출할 기준
  // ═══════════════════════════════════════════════════════════
  group('[E] 지원 확인', () {
    Widget dialogHost({
      required AttendanceRules? rules,
      bool policyLoaded = true,
    }) =>
        Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ApplyConfirmDialog(
                businessName: '중앙물류센터',
                work: _wdModel(),
                isLongTerm: false,
                workDate: _kstInstant(2026, 10, 10),
                policyRules: rules,
                policyLoaded: policyLoaded,
              ),
            ),
          ),
        );

    testWidgets('E-1 제출할 7개 기준이 값까지 보인다', (t) async {
      await _pumpHost(t, dialogHost(rules: _standard()),
          size: const Size(360, 900), textScale: 1.0);
      expect(t.takeException(), isNull);
      expectAllSevenLines(t, _standard(), '지원 확인');
    });

    testWidgets('E-2 기준이 **없음** 과 **못 읽음** 을 구별한다', (t) async {
      // ABSENT — 사업장이 준비해야 한다.
      await _pumpHost(t, dialogHost(rules: null, policyLoaded: true),
          size: const Size(360, 900), textScale: 1.0);
      expect(t.takeException(), isNull);
      // [DU295 S1 — DU288 따라잡기 누락] 안내 카드 글자가 낱말 묶음 문자를 품는다 → 보이는 글자로 비교(이 파일 다른 단언과 같다).
      expect(visibleText(_visible(t)).contains(kAttendancePolicyUnavailableNote.split('\n').first),
          isTrue,
          reason: '기준 부재를 말하지 않는다');

      // ERROR — 다시 시도. 부재로 위조하지 않는다.
      await _pumpHost(t, dialogHost(rules: null, policyLoaded: false),
          size: const Size(360, 900), textScale: 1.0);
      expect(t.takeException(), isNull);
      final shown = visibleText(_visible(t)); // [DU295 S1 — DU288 따라잡기 누락] 아래 부정 단언이 빈 검사가 되지 않게
      expect(shown.contains(kAttendancePolicyLoadFailedNote.split('\n').first),
          isTrue, reason: '조회 실패를 말하지 않는다');
      expect(shown.contains(kAttendancePolicyUnavailableNote.split('\n').first),
          isFalse, reason: 'ERROR 를 ABSENT 로 위조했다');
    });

    testWidgets('E-3 지원 CTA 가 고지에 밀려 사라지지 않는다', (t) async {
      await _pumpHost(t, dialogHost(rules: _longest()),
          size: const Size(320, 760), textScale: 2.0);
      expect(t.takeException(), isNull);
      // 지원 버튼이 트리에 있고 눌릴 수 있다.
      final cta = find.textContaining('지원');
      expect(cta, findsWidgets, reason: '지원 CTA 가 없다');
    });

    for (final w in _widths) {
      for (final s in _scales) {
        testWidgets('E-4 ${w.toInt()}dp × 배율 $s — 넘침 0', (t) async {
          await _pumpHost(t, dialogHost(rules: _longest()),
              size: Size(w, 900), textScale: s);
          expect(t.takeException(), isNull,
              reason: '${w.toInt()}dp × $s 에서 지원 확인이 넘친다');
        });
      }
    }
  });

  // ═══════════════════════════════════════════════════════════
  // F. 내 지원 — 초대·제안 수락 전, Application snapshot
  //
  //   `_attendancePolicyBlock` 은 `_acceptInvite` 의 확인창 안에만 있다.
  //   이전 Phase 는 서류 문턱을 넘지 못해 이 화면을 CODE only 로 남겼다.
  //   문턱을 **우회하지 않고** 조건을 갖춘 합성 사용자로 실제로 넘는다.
  // ═══════════════════════════════════════════════════════════
  group('[F] 내 지원 (수락 확인창)', () {
    ApplicationModel invite({AttendanceRules? policy}) => ApplicationModel(
          id: 'inv1',
          uid: 'u1',
          toId: 'to1',
          slotId: 's1',
          businessId: 'biz1',
          businessName: '중앙물류센터',
          toTitle: '냉장 분류 단기 모집',
          selectedWorkType: '냉장 분류',
          wdId: 'wd1',
          startTime: '18:00',
          endTime: '22:30',
          wage: 53000,
          wageType: 'daily',
          status: 'INVITED',
          // [ISG2 시한부 fixture 정정] 예전에는 2026-10-10 고정이었다.
          //   수락 마감은 `min(초대+24h, 근무 시작)` 이라, 근무가 지난
          //   초대는 `수락하기` 가 비활성이다(서버도 거절한다). 이 그룹이
          //   묻는 것은 확인창의 **고지 내용**이므로 날짜는 늘 미래로 센다.
          workDate: _futureKstDay(3),
          appliedAt: _futureKstDay(-5),
          invitedAt: _futureKstDay(-1),
          workInstanceCapacityState: InviteCapacityState.available,
          // [INVITE-PARITY] 이 그룹은 '수락할 수 있는 초대'의 확인창 고지를 본다.
          //   준비 상태를 모르면(값 없음) 수락하기가 비활성이라 확인창에 닿지 않는다.
          inviteAcceptReadiness: InviteAcceptReadiness.ready,
          attendancePolicySnapshot: policy,
        );

    MyApplicationsReads reads(List<ApplicationModel> apps) =>
        MyApplicationsReads(
          myApplicationsPaged: (
                  {required String uid,
                  required int pageSize,
                  String? startAfterDocId}) async =>
              {'items': apps, 'lastDocId': null, 'hasMore': false},
          toOrFailure: (toId) async => (to: _to(), failed: false),
          contractsByWorker: (uid) async =>
              const <EmploymentContractModel>[],
          autoExpirePending: (uid) async {},
          // [E1-MYA] 이 테스트는 근태를 보지 않는다 — 빈 결과로 고정한다.
          monthlyAttendances: (
                  {required String userId,
                  required int year,
                  required int month}) async =>
              const [],
          // 세무 축을 **우회하지 않는다** — production 과 같은 "모름"
          //   상태를 준다. `loadFailed` 이므로 판정이 막지 않고,
          //   production 의 실패 경로와 같은 값이다.
          reviewById: (key) async => null,
          taxStatus: () async => const TaxIdentityStatus.unknown(),
        );

    /// 목록을 띄우고 '수락하기' 를 눌러 확인창까지 간다.
    Future<bool> openAcceptDialog(
      WidgetTester t, {
      required AttendanceRules? policy,
      required Size size,
      required double textScale,
    }) async {
      await _pumpHost(
        t,
        MyApplicationsScreen(reads: reads([invite(policy: policy)])),
        size: size,
        textScale: textScale,
      );
      final cta = find.text('수락하기');
      if (cta.evaluate().isEmpty) return false;
      await t.ensureVisible(cta);
      await t.pump();
      await t.tap(cta);
      await _settle(t, rounds: 30);
      // 확인창 고유 문구로 도달을 판정한다.
      return find.textContaining('확정된 다른 근무와 시간이 겹치면 수락할 수 없어요. 수락이 완료되면 근무가 확정돼요').evaluate().isNotEmpty ||
          find.text(kAttendancePolicyTitle).evaluate().isNotEmpty;
    }

    testWidgets('F-0 서류 문턱을 넘어 확인창에 도달한다', (t) async {
      final reached = await openAcceptDialog(t,
          policy: _standard(), size: const Size(390, 1200), textScale: 1.0);
      expect(reached, isTrue,
          reason: '확인창에 닿지 못했다 — 서류 문턱 또는 CTA 조건을 못 넘었다');
      expect(t.takeException(), isNull);
    });

    testWidgets('F-1 수락 전 snapshot 의 7개 기준이 값까지 보인다', (t) async {
      final reached = await openAcceptDialog(t,
          policy: _standard(), size: const Size(390, 1200), textScale: 1.0);
      expect(reached, isTrue);
      expectRuleGuide(t, _standard(), '내 지원 수락 확인창', start: '18:00', end: '22:30');
      // 그 기준이 이 약속에 묶였다는 사실도 말한다.
      expect(_visible(t).contains(kAttendancePolicyFrozenNote), isTrue,
          reason: '고정 사실을 말하지 않으면 현재 설정으로 오해한다');
    });

    testWidgets('F-1b 이 근무 시각의 사례 — 접혀 있다가 펴면 실제 계산과 같은 줄', (t) async {
      final reached = await openAcceptDialog(t,
          policy: _standard(), size: const Size(390, 1600), textScale: 1.0);
      expect(reached, isTrue);
      final g = attendanceRuleGuide(_standard(), startHHmm: '18:00', endHHmm: '22:30');
      expect(g.hasExamples, isTrue);
      // 기준 설명은 늘 보이고 사례만 접혀 있다.
      expectGuideExamples(t, g, '접힘', visible: false);
      final toggle = find.text('시간 예시 보기');
      await t.ensureVisible(toggle);
      await t.tap(toggle);
      await _settle(t);
      expectGuideExamples(t, g, '펼침');
      // 유예 5분 → 18:05 출근은 18:00 부터, 18:06 출근은 18:30 부터(30분 단위 올림).
      final shown = visibleText(_visible(t));
      expect(shown.contains('예: 18:06 출근 →') && shown.contains('인정 시작 18:30'), isTrue);
      expect(shown.contains(kAttendancePolicyEffectNote), isTrue);
    });

    testWidgets('F-1d 탭 안(중첩 Navigator)에서도 취소가 확인창을 닫는다', (t) async {
      // 실제 앱: UserRootScreen 의 탭마다 Navigator 가 있고 확인창은 루트 Navigator 에 뜬다.
      await _pumpHost(
        t,
        Navigator(
          onGenerateRoute: (s) => MaterialPageRoute(
              builder: (_) => MyApplicationsScreen(reads: reads([invite(policy: _standard())])), settings: s),
        ),
        size: const Size(390, 1600),
        textScale: 1.0,
      );
      final cta = find.text('수락하기');
      await t.ensureVisible(cta);
      await t.tap(cta);
      await _settle(t, rounds: 30);
      expect(findVisibleText('동의하고 초대 수락'), findsOneWidget);
      await t.tap(find.text('취소'));
      await _settle(t, rounds: 10);
      expect(findVisibleText('동의하고 초대 수락'), findsNothing, reason: '취소가 확인창을 닫지 못했다');
      expect(find.text('수락하기'), findsOneWidget, reason: '목록 화면은 그대로 있어야 한다');
    });

    testWidgets('F-1c 기준 기록이 없으면 예시도 없다 — 현재 기준으로 계산하지 않는다', (t) async {
      final reached = await openAcceptDialog(t,
          policy: null, size: const Size(390, 1200), textScale: 1.0);
      expect(reached, isTrue);
      expect(find.text('시간 예시 보기'), findsNothing);
      expect(visibleText(_visible(t)).contains('예: '), isFalse);
    });

    testWidgets('F-2 기록이 없으면 **없다고 말한다** — 현재 기준으로 채우지 않는다',
        (t) async {
      final reached = await openAcceptDialog(t,
          policy: null, size: const Size(390, 1200), textScale: 1.0);
      expect(reached, isTrue);
      final shown = _visible(t);
      expect(shown.contains(kAttendancePolicyUnknownNote.split('\n').first),
          isTrue, reason: '기록 없음을 말하지 않는다');
      for (final p in _guidePoints(attendanceRuleGuide(_standard()))) {
        expect(visibleText(shown).contains(p), isFalse,
            reason: '기록이 없는데 기준을 적었다: $p');
      }
    });

    // [.29-A1] 내 지원에서 연 공고 상세(초대 수락 화면)는 **그 지원서 snapshot** 을 보인다 — 사업장 현재 기준이 아니다.
    //   기기 대조: 사업장 기준(유예 10분)을 바꾼 뒤 초대 상세가 10분을 보여, 수락 확인창(snapshot 5분)과 달랐다.
    testWidgets('F-4 내 지원에서 연 공고 상세는 snapshot 기준과 그 근무 시각을 보인다', (t) async {
      await _pumpHost(
        t,
        JobPostingScreen(
            to: _to(),
            workDetails: const [],
            reads: _postingReads(_boundary()), // 사업장 현재 기준은 경계값
            myApplication: invite(policy: _standard())), // 이 초대에 고정된 기준은 표준값
        size: const Size(360, 780),
        textScale: 1.0,
      );
      // [DU466 지원 패치 · 후속114 §3] 제목은 TextLayout.keepWords 로 그려진다(보이지 않는 결합 문자 포함) — 보이는 글자 정확 일치 finder 로 찾는다.
      final title = findVisibleText(kAttendanceRuleGuideTitle);
      await t.ensureVisible(title);
      await _settle(t);
      expectRuleGuide(t, _standard(), '초대 상세(snapshot)', start: '18:00', end: '22:30');
      final shown = visibleText(_visible(t));
      final std = _guidePoints(attendanceRuleGuide(_standard())).toSet();
      for (final p in _guidePoints(attendanceRuleGuide(_boundary()))) {
        if (std.contains(p)) continue;
        expect(shown.contains(p), isFalse, reason: '사업장 현재 기준이 섞였다: $p');
      }
      expect(shown.contains('근무시간 18:00–22:30'), isTrue);
      expect(shown.contains(kAttendancePolicyFrozenNote), isTrue);
    });

    testWidgets('F-5 snapshot 없는 지원서로 연 공고 상세는 현재 기준으로 채우지 않는다', (t) async {
      await _pumpHost(
        t,
        JobPostingScreen(
            to: _to(),
            workDetails: const [],
            reads: _postingReads(_standard()),
            myApplication: invite(policy: null)),
        size: const Size(360, 780),
        textScale: 1.0,
      );
      // [DU466 지원 패치 · 후속114 §3] 제목은 TextLayout.keepWords 로 그려진다(보이지 않는 결합 문자 포함) — 보이는 글자 정확 일치 finder 로 찾는다.
      final title = findVisibleText(kAttendanceRuleGuideTitle);
      await t.ensureVisible(title);
      await _settle(t);
      final shown = visibleText(_visible(t));
      expect(shown.contains(kAttendancePolicyUnknownNote.split('\n').first), isTrue);
      for (final p in _guidePoints(attendanceRuleGuide(_standard()))) {
        expect(shown.contains(p), isFalse, reason: '기록이 없는데 현재 기준을 적었다: $p');
      }
    });

    for (final w in _widths) {
      for (final s in _scales) {
        testWidgets('F-3 ${w.toInt()}dp × 배율 $s — 넘침 0', (t) async {
          final reached = await openAcceptDialog(t,
              policy: _longest(), size: Size(w, 1200), textScale: s);
          expect(reached, isTrue, reason: '${w.toInt()}dp × $s 에서 확인창 미도달');
          expect(t.takeException(), isNull,
              reason: '${w.toInt()}dp × $s 에서 수락 확인창이 넘친다');
        });
      }
    }
  });

  // ═══════════════════════════════════════════════════════════
  // G. 계약 서명 — Application snapshot 에 기록된 기준
  // ═══════════════════════════════════════════════════════════
  group('[G] 계약 서명', () {
    testWidgets('G-1 snapshot 의 7개 기준이 값까지 보인다', (t) async {
      await _pumpHost(
        t,
        ContractSignScreen(contract: _contract(policy: _standard()), role: 'worker'),
        size: const Size(360, 900),
        textScale: 1.0,
      );
      expect(t.takeException(), isNull);
      expectRuleGuide(t, _standard(), '계약 서명', start: '18:00', end: '22:30');
      expect(find.text(kAttendanceRuleGuideTitle), findsOneWidget, reason: '임금 조항 아래 구분 제목');
    });

    // [ATTENDANCE-RULE-GUIDE.29-A1] 계약서는 사례를 접지 않는다 — 기준 바로 아래에 이 근무(18:00~22:30) 사례.
    testWidgets('G-1b 근태 인정 기준 사례가 이 근무 시각으로 기준 바로 아래 보인다', (t) async {
      await _pumpHost(
        t,
        ContractSignScreen(contract: _contract(policy: _standard()), role: 'worker'),
        size: const Size(360, 900),
        textScale: 1.0,
      );
      expect(t.takeException(), isNull);
      final g = attendanceRuleGuide(_standard(), startHHmm: '18:00', endHHmm: '22:30');
      expect(g.workTime, '18:00–22:30');
      expect(visibleText(_visible(t)).contains('근무시간 18:00–22:30'), isTrue);
      expectGuideExamples(t, g, '계약 서명');
      expect(find.text('시간 예시 보기'), findsNothing, reason: '계약서는 약속 전체가 읽혀야 한다');
    });

    // [TEXT-LAYOUT-CONSUMER.29] 근무일 표 — 기기 320dp·1.3 에서 '2026-1 / 0-29', '17:3 / 5' 로 갈렸다.
    //   들어가면 표, 아니면 근무일마다 한 덩어리. 날짜·시각·금액은 쪼개지 않는다.
    //   (판단은 실제 글자 폭으로 한다 — 시험 글꼴은 기기보다 넓어 '표' 쪽 예시는 600dp 로 둔다.)
    for (final c in [(const Size(600, 900), 1.0, true), (const Size(320, 900), 1.3, false)]) {
      testWidgets('G-5 ${c.$1.width.toInt()}dp × ${c.$2} — 근무일 ${c.$3 ? '표' : '쌓음'}, 날짜·시각·금액 한 줄', (t) async {
        await _pumpHost(
          t,
          ContractSignScreen(contract: _contract(policy: _standard()), role: 'worker'),
          size: c.$1,
          textScale: c.$2,
        );
        expect(t.takeException(), isNull);
        expect(find.byType(Table), c.$3 ? findsWidgets : findsNothing);
        final slot = _contract(policy: _standard()).slots.first;
        for (final v in [slot.workDate, slot.formattedWage]) {
          final f = find.text(v);
          await t.ensureVisible(f.first);
          final p = t.renderObject<RenderParagraph>(
              find.descendant(of: f.first, matching: find.byType(RichText), matchRoot: true).first);
          final len = p.text.toPlainText().length;
          final tops = p
              .getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: len))
              .map((b) => b.top.round())
              .toSet();
          expect(tops.length, 1, reason: '$v 이 한 줄이어야 한다');
        }
      });
    }

    testWidgets('G-2b snapshot 이 없으면 사례도 없다', (t) async {
      await _pumpHost(
        t,
        ContractSignScreen(contract: _contract(policy: null), role: 'worker'),
        size: const Size(360, 900),
        textScale: 1.0,
      );
      expect(find.text(kAttendanceRuleGuideTitle), findsNothing);
      expect(visibleText(_visible(t)).contains('예: '), isFalse);
    });

    testWidgets('G-2 snapshot 이 없으면 **적지 않는다** — 현재 기준으로 채우지 않는다',
        (t) async {
      await _pumpHost(
        t,
        ContractSignScreen(contract: _contract(policy: null), role: 'worker'),
        size: const Size(360, 900),
        textScale: 1.0,
      );
      expect(t.takeException(), isNull);
      final shown = visibleText(_visible(t));
      for (final p in _guidePoints(attendanceRuleGuide(_standard()))) {
        expect(shown.contains(p), isFalse, reason: '기록이 없는데 기준을 적었다: $p');
      }
    });

    testWidgets('G-3 snapshot 값이 사업장 현재 기준과 달라도 snapshot 을 보여준다',
        (t) async {
      // 사업장이 그 뒤에 기준을 바꾼 상황 — 계약서는 맺힌 약속을 지킨다.
      await _pumpHost(
        t,
        ContractSignScreen(contract: _contract(policy: _boundary()), role: 'worker'),
        size: const Size(360, 900),
        textScale: 1.0,
      );
      expectRuleGuide(t, _boundary(), '계약 서명(snapshot)', start: '18:00', end: '22:30');
      final shown = _visible(t);
      for (final l in attendancePolicyLines(_standard())) {
        expect(shown.contains(l.value), isFalse,
            reason: '현재 기준이 섞였다: ${l.value}');
      }
    });

    for (final w in _widths) {
      for (final s in _scales) {
        testWidgets('G-4 ${w.toInt()}dp × 배율 $s — 넘침 0', (t) async {
          await _pumpHost(
            t,
            ContractSignScreen(
                contract: _contract(policy: _longest()), role: 'worker'),
            size: Size(w, 900),
            textScale: s,
          );
          expect(t.takeException(), isNull,
              reason: '${w.toInt()}dp × $s 에서 계약 서명이 넘친다');
        });
      }
    }
  });

  // ═══════════════════════════════════════════════════════════
  // I. 확정 **후** 재조회 — 직접 지원자가 당시 기준을 다시 볼 수 있는가
  //
  //   `.1` 에서 "내 지원은 수락 시점에만 보여준다" 를 PRODUCT OPEN 으로
  //   남겼다. `.1A` 에서 다른 경로를 전수로 찾아 보니 **계약 경로가 이미
  //   있다** — 계약 목록의 '서명 완료' 탭에서 계약을 열면 그 약속의
  //   snapshot 7개 값이 그대로 있다. 직접 지원이든 초대 수락이든,
  //   단기든 장기든 같은 경로다. 그래서 UX 를 새로 만들지 않고 **증거만
  //   남긴다**(§2).
  // ═══════════════════════════════════════════════════════════
  group('[I] 확정 후 재조회 경로', () {
    testWidgets('I-1 **서명 완료** 계약을 열면 7개 값이 그대로 있다', (t) async {
      final signed = EmploymentContractModel(
        id: 'c1',
        applicationId: 'to1_s1_wd1_u1',
        businessId: 'biz1',
        workerId: 'u1',
        isLongTerm: false,
        toId: 'to1',
        workDetailId: 'wd1',
        slots: const [
          ContractSlot(
            applicationId: 'to1_s1_wd1_u1',
            workDate: '2026-10-10',
            startTime: '18:00',
            endTime: '22:30',
            wage: 53000,
            wageType: 'daily',
          ),
        ],
        applicationIds: const ['to1_s1_wd1_u1'],
        // 이미 서명이 끝난 계약이다.
        status: ContractStatus.completed,
        snapshot: _snapshot(policy: _standard()),
        articles: const [
          ContractArticle(title: '제1조 (근로계약기간)', content: '본 계약은 ...'),
        ],
        templateId: 'tpl1',
        createdAt: DateTime(2026, 10, 1),
        pdfUrl: 'https://example.invalid/contract.pdf',
      );

      await _pumpHost(
        t,
        ContractSignScreen(contract: signed, role: 'worker'),
        size: const Size(360, 900),
        textScale: 1.0,
      );
      expect(t.takeException(), isNull);
      expectRuleGuide(t, _standard(), '서명 완료 계약 재조회', start: '18:00', end: '22:30');
    });

    testWidgets('I-2 좁은 화면·큰 배율에서도 재조회가 된다', (t) async {
      final signed = _contract(policy: _longest());
      await _pumpHost(
        t,
        ContractSignScreen(contract: signed, role: 'worker'),
        size: const Size(320, 820),
        textScale: 2.0,
      );
      expect(t.takeException(), isNull);
      expectRuleGuide(t, _longest(), '재조회 320×2.0', start: '18:00', end: '22:30');
    });

    test('I-3 계약 목록이 상태와 무관하게 상세로 보낸다', () {
      final s =
          File('lib/screens/user/user_contracts_screen.dart').readAsStringSync();
      // '서명 완료' 탭이 있다.
      expect(s.contains('ContractStatus.completed'), isTrue,
          reason: '완료 계약을 고를 탭이 없으면 재조회 경로가 없다');
      expect(s.contains("'서명 완료'"), isTrue);
      // 카드 탭이 상세로 간다 — 상태별 분기로 막지 않는다.
      expect(s.contains('ContractSignScreen(contract: c, role: \'worker\')'),
          isTrue, reason: '목록에서 상세로 가는 목적지가 없다');
      expect(s.contains('onTap: () => _openContract(_items[i])'), isTrue,
          reason: '카드가 열리지 않으면 재조회할 수 없다');
    });

    test('I-4 재조회도 snapshot 을 읽는다 — 현재 사업장 설정이 아니다', () {
      final sign = File('lib/screens/contract/contract_sign_screen.dart')
          .readAsStringSync();
      expect(sign.contains('snapshot.attendancePolicy'), isTrue);
      expect(sign.contains('attendanceRules'), isFalse,
          reason: '재조회가 현재 설정을 읽으면 당시 약속과 달라진다');
      // 상태로 고지를 막지 않는다 — 완료 계약에서도 보인다.
      final i = sign.indexOf('if (snapshot.attendancePolicy case final policy?)');
      expect(i, greaterThan(-1));
      final around = sign.substring(i - 300, i);
      expect(around.contains('isCompleted'), isFalse,
          reason: '완료 상태에서 고지를 가리면 재조회가 막힌다');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // H. 지원 전 정보 위계 — 7개 기준이 날짜·임금·CTA 를 밀어내지 않는다
  // ═══════════════════════════════════════════════════════════
  group('[H] 정보 위계', () {
    // [.29-A1] 예전 결정(본문은 한 줄, 숫자는 상세 시트)을 뒤집었다 — 지원 전에 핵심 기준을 처음부터 보인다.
    //   날짜·임금이 고지보다 먼저 나오는 위계는 H-3 이 지킨다. 사례만 접는다.
    testWidgets('H-1 핵심 기준은 처음부터 보이고, 사례만 접는다', (t) async {
      await _pumpHost(
        t,
        JobPostingScreen(
            to: _to(), workDetails: const [], reads: _postingReads(_standard())),
        size: const Size(360, 780),
        textScale: 1.0,
      );
      final title = findVisibleText(kAttendanceRuleGuideTitle);
      await t.ensureVisible(title);
      await _settle(t);
      expectRuleGuide(t, _standard(), '공고 본문');
      expect(find.text('상세 기준'), findsNothing);
    });

    testWidgets('H-2 지원 CTA 는 스크롤 본문이 아니라 **하단 바**에 있다', (t) async {
      // 구조적으로 CTA 가 고지 길이에 영향받지 않는다는 뜻이다.
      await _pumpHost(
        t,
        JobPostingScreen(
            to: _to(), workDetails: const [], reads: _postingReads(_longest())),
        size: const Size(320, 760),
        textScale: 2.0,
      );
      expect(t.takeException(), isNull);
      final scaffold = t.widget<Scaffold>(find.byType(Scaffold).first);
      expect(scaffold.bottomNavigationBar, isNotNull,
          reason: 'CTA 가 하단 바에 없으면 긴 본문에 밀려 닿지 못한다');
    });

    testWidgets('H-3 날짜·임금이 고지보다 먼저 나온다', (t) async {
      await _pumpHost(
        t,
        JobPostingScreen(
            to: _to(), workDetails: const [], reads: _postingReads(_standard())),
        size: const Size(360, 1600),
        textScale: 1.0,
      );
      final texts = t
          .widgetList<Text>(find.byType(Text))
          .map((w) => visibleText(w.data ?? ''))
          .toList();
      final policyAt = texts.indexWhere((s) => s == kAttendanceRuleGuideTitle);
      expect(policyAt, greaterThan(-1), reason: '고지 섹션이 없다');
      // 업무·임금 정보가 고지 앞쪽에 있다.
      final workAt = texts.indexWhere((s) => s.contains('냉장 분류'));
      expect(workAt, greaterThan(-1), reason: '업무 정보가 없다');
      expect(workAt, lessThan(policyAt),
          reason: '고지가 업무 정보보다 앞에 있다 — 위계가 뒤집혔다');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // TRUTH. 같은 약속은 모든 화면에서 같은 값이다
  // ═══════════════════════════════════════════════════════════
  group('[TRUTH] 화면 사이 값 일치', () {
    test('T-1 네 화면이 같은 formatter 를 쓴다 — 자기 목록을 만들지 않는다', () {
      for (final p in const [
        'lib/screens/common/job_posting_screen.dart',
        'lib/widgets/dialogs/apply/apply_confirm_dialog.dart',
        'lib/screens/user/my_applications_screen.dart',
        'lib/screens/contract/contract_sign_screen.dart',
        'lib/screens/contract/contract_pdf_builder.dart',
      ]) {
        final s = File(p).readAsStringSync();
        // [.29-A1] 공고·초대·계약·PDF 는 '근태 인정 기준' 공용 생성(attendanceRuleGuide), 지원 확인은 기존 줄 목록.
        final shared = s.contains('attendancePolicyGroups(') ||
            s.contains('attendancePolicyLines(') ||
            s.contains('attendanceRuleGuide(');
        expect(shared, isTrue, reason: '$p 가 공용 formatter 를 쓰지 않는다');
        expect(s.contains("AttendanceRuleItem('"), isFalse,
            reason: '$p 가 기준 항목을 직접 만든다');
        expect(s.contains("AttendancePolicyLine('"), isFalse,
            reason: '$p 가 고지 줄을 직접 만든다');
      }
    });

    test('T-2 지원 전은 현재 기준 · 지원 후는 snapshot 을 읽는다', () {
      final posting =
          File('lib/screens/common/job_posting_screen.dart').readAsStringSync();
      expect(posting.contains('_business!.attendanceRules'), isTrue,
          reason: '공고 상세가 사업장 현재 기준을 읽지 않는다');

      final mine = File('lib/screens/user/my_applications_screen.dart')
          .readAsStringSync();
      expect(mine.contains('offerApp.attendancePolicySnapshot'), isTrue,
          reason: '내 지원이 snapshot 을 읽지 않는다');
      expect(mine.contains('attendanceRules'), isFalse,
          reason: '내 지원이 사업장 현재 기준을 읽는다 — 수락 뒤 계산과 달라진다');

      final sign = File('lib/screens/contract/contract_sign_screen.dart')
          .readAsStringSync();
      expect(sign.contains('snapshot.attendancePolicy'), isTrue);
      expect(sign.contains('attendanceRules'), isFalse,
          reason: '계약 서명이 사업장 현재 기준을 읽는다');
    });
  });
}
