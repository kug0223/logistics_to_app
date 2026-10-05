// [R7-APPLICATION-LIFECYCLE.1C.2] 장기 custom 지원도 같은 약속 충돌 진실을 쓴다.
//
// ── 고친 결함 ───────────────────────────────────────────────────
//   `LongTermApplySheet._loadConflicts` 는 custom 공고에서 그냥 돌아갔다.
//
//     if (_isCustom) { setState(() => _isLoadingConflicts = false); return; }
//     // "custom: 날짜 선택 없음 — 캘린더 표시 안 함. 충돌 체크 생략."
//
//   custom 은 기간이 고정(`rangeStart`~`rangeEnd`)이라 **고를 날짜가 없다**.
//   그것을 "판정할 것이 없다" 로 바꿔 읽은 것이 결함이다. 기간이 정해져
//   있다는 건 오히려 **열자마자 판정할 수 있다**는 뜻이다. 그래서
//   `UI = 제출 가능 / Server = 일정 충돌 거부` 가 남았다.
//
//   preset 쪽에도 반대 방향의 거짓이 있었다. 충돌 날짜를 모아 두고
//   `!conflictDate.isBefore(day)` 로 **그 날 이전의 모든 시작일**을 막았다 —
//   11/20 에 충돌 하나가 있으면 10/05 시작(10/19 종료) 계약까지 선택 불가였다.
//
// ── 이 파일이 고정하는 계약 ─────────────────────────────────────
//   · 판정은 공용 owner 하나(`CommitmentConflictResolver`)다.
//   · 약속의 효력 시작은 canonical — `desiredStartDate ?? workDate`,
//     희망일이 없을 때만 `confirmedAt`(KST)으로 밀린다.
//   · 승인된 추가근무는 약속을 **만들고** 휴무는 **지운다**(서버와 parity).
//   · 휴무 하루가 반복 일정 전체를 지우지 않는다.
//   · 선택이 끝나지 않았거나 목록을 못 읽었으면 `unknown` — "가능" 이 아니다.
//   · payload 와 판정값이 같은 기간을 본다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/user_model.dart';
import 'package:ALfit/models/core/work_detail_model.dart';
import 'package:ALfit/providers/user_provider.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/widgets/dialogs/apply/commitment_conflict.dart';
import 'package:ALfit/widgets/dialogs/apply/longterm_apply_sheet.dart';

const kUid = 'worker1';

/// KST 자정 instant — Firestore 저장 규약.
DateTime kst(int y, int m, int d) =>
    DateTime.utc(y, m, d).subtract(const Duration(hours: 9));
DateTime kstAt(int y, int m, int d, int hh) =>
    DateTime.utc(y, m, d, hh).subtract(const Duration(hours: 9));
const _wk = ['일', '월', '화', '수', '목', '금', '토'];
String wkd(int y, int m, int d) => _wk[DateTime.utc(y, m, d).weekday % 7];

/// 기존 **장기** 약속 — 기본은 월~금 09:00~18:00, 10/01~11/30.
ApplicationModel commitment({
  String status = AppStatus.confirmed,
  List<String> workDays = const ['월', '화', '수', '목', '금'],
  String start = '09:00',
  String end = '18:00',
  DateTime? workDate,
  DateTime? desiredStartDate,
  DateTime? workEndDate,
  /// 종료일을 **모르는** 약속 — 기본값이 명시적 null 을 덮지 않게 분리한다.
  bool openEnded = false,
  DateTime? actualResignDate,
  DateTime? confirmedAt,
  List<DateTime>? extraWorkDates,
  List<DateTime>? leaveDates,
  String businessId = 'bizOther',
  String businessName = '다른 사업장',
}) =>
    ApplicationModel(
      id: 'c_$status',
      uid: kUid,
      toId: 'toOther',
      businessId: businessId,
      businessName: businessName,
      toTitle: '다른 공고',
      selectedWorkType: '상하차',
      wdId: 'wdOther',
      startTime: start,
      endTime: end,
      wage: 12000,
      wageType: 'hourly',
      status: status,
      applicationType: AppType.longTerm,
      workDays: workDays,
      workDate: workDate ?? kst(2026, 10, 1),
      desiredStartDate: desiredStartDate,
      workEndDate: openEnded ? null : (workEndDate ?? kst(2026, 11, 30)),
      actualResignDate: actualResignDate,
      confirmedAt: confirmedAt,
      extraWorkDates: extraWorkDates,
      leaveDates: leaveDates,
      appliedAt: DateTime(2026, 9, 25),
    );

/// 장기 custom 후보 — 선택(또는 고정)된 기간·요일·시간.
CommitmentConflictDecision candidate({
  required List<ApplicationModel> commitments,
  required DateTime startDate,
  DateTime? endDate,
  List<String> workDays = const ['토'],
  String start = '13:00',
  String end = '22:00',
  bool known = true,
}) =>
    CommitmentConflictResolver.forLongTerm(
      commitments: CommitmentConflictResolver.commitmentsOf(commitments),
      commitmentsKnown: known,
      startDate: startDate,
      endDate: endDate,
      workDays: workDays,
      startTime: start,
      endTime: end,
    );

String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('없는 파일: $p');
  return f.readAsStringSync();
}

const _kSheet = 'lib/widgets/dialogs/apply/longterm_apply_sheet.dart';
const _kResolver = 'lib/widgets/dialogs/apply/commitment_conflict.dart';
const _kModel = 'lib/models/core/application_model.dart';
const _kFn = 'functions/src/index.ts';
const _kMod = 'functions/src/commitment_dates.ts';

// ── 렌더 하네스 ───────────────────────────────────────────────────────────
class _FakeApp extends Fake
    with MockPlatformInterfaceMixin
    implements FirebaseAppPlatform {
  @override
  String get name => defaultFirebaseAppName;
  @override
  FirebaseOptions get options => const FirebaseOptions(
      apiKey: 'k', appId: 'a', messagingSenderId: 's',
      projectId: 'p', storageBucket: 'b');
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

class _Applicant extends UserProvider {
  @override
  UserModel? get currentUser => UserModel(
        uid: kUid,
        username: kUid,
        name: '김근로',
        email: 'u1@alfit.local',
        role: UserRole.USER,
        accountStatus: 'active',
        passVerifiedAt: DateTime(2026, 2, 1),
        isIdVerified: true,
        idCardImagePath: 'users/u1/id.png',
        bankName: '국민은행',
        accountNumber: '1234',
        accountHolder: '김근로',
        bankbookImagePath: 'users/u1/bb.png',
        createdAt: DateTime(2026, 1, 1),
      );
  @override
  bool get permissionsLoaded => true;
}

/// custom 장기 공고 — 기간이 고정이고 달력이 없다.
TOModel _customTo({
  List<String> workDays = const ['월', '화', '수', '목', '금'],
}) =>
    TOModel(
      id: 'toCustom',
      businessId: 'bizA',
      businessName: '후보 사업장',
      type: 'contract',
      title: '장기 모집(custom)',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      workDays: workDays,
      contractPeriodType: 'custom',
      rangeStart: kst(2026, 10, 5),
      rangeEnd: kst(2026, 10, 30),
      totalRequired: 5,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

WorkDetailModel _work({String start = '13:00', String end = '22:00'}) =>
    WorkDetailModel(
      wdId: 'wdCand',
      workType: '홀서빙',
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: 5,
      startTime: start,
      endTime: end,
    );

Future<void> _pumpSheet(
  WidgetTester tester, {
  required Future<List<ApplicationModel>> Function() source,
  TOModel? to,
  WorkDetailModel? work,
  Size size = const Size(390, 1400),
  double textScale = 1.0,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(
    ChangeNotifierProvider<UserProvider>(
      create: (_) => _Applicant(),
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
              size: size, textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: LongTermApplySheet(
              to: to ?? _customTo(),
              selectedWorks: [work ?? _work()],
              businessName: '후보 사업장',
              myApplications: const [],
              commitmentsSource: source,
            ),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    FirebasePlatform.instance = _FakeCore();
  });

  // ══ C1~C18 — 장기 custom 후보의 판정 ═══════════════════════════════════
  group('LCA-C 장기 후보 판정', () {
    test('C1 요일이 겹치지 않으면 지원 가능', () {
      final r = candidate(
          commitments: [commitment()],
          startDate: kst(2026, 10, 3), // 토
          endDate: kst(2026, 10, 31),
          workDays: const ['토'],
          start: '09:00',
          end: '18:00');
      expect(r.outcome, CommitmentConflictOutcome.none);
    });

    test('C2 반복 근무요일이 겹치면 지원 불가', () {
      final r = candidate(
          commitments: [commitment()],
          startDate: kst(2026, 10, 5),
          endDate: kst(2026, 10, 31),
          workDays: const ['월', '토']);
      expect(r.blocksNewApplication, isTrue);
      expect(r.conflictDate, isNotNull);
      expect(FormatHelper.weekday(r.conflictDate!), '월');
    });

    test('C3 인접 시간은 겹침이 아니다', () {
      final r = candidate(
          commitments: [commitment(start: '09:00', end: '12:00')],
          startDate: kst(2026, 10, 5),
          endDate: kst(2026, 10, 31),
          workDays: const ['월'],
          start: '12:00',
          end: '18:00');
      expect(r.blocksNewApplication, isFalse);
    });

    test('C4 희망 시작일 이전은 약속이 아니다 — 과잉 차단 금지', () {
      final c = commitment(
          workDate: kst(2026, 10, 1),
          desiredStartDate: kst(2026, 10, 15));
      // 10/05~10/09 한 주(월~금) 후보 — 효력 시작 이전이다.
      final r = candidate(
          commitments: [c],
          startDate: kst(2026, 10, 5),
          endDate: kst(2026, 10, 9),
          workDays: const ['월', '화', '수', '목', '금']);
      expect(r.blocksNewApplication, isFalse);
    });

    test('C5 희망 시작일 이후의 겹침은 막는다', () {
      final c = commitment(
          workDate: kst(2026, 10, 1),
          desiredStartDate: kst(2026, 10, 15));
      final r = candidate(
          commitments: [c],
          startDate: kst(2026, 10, 19),
          endDate: kst(2026, 10, 23),
          workDays: const ['월']);
      expect(r.blocksNewApplication, isTrue);
    });

    test('C6 희망일이 없으면 확정일(KST)로 밀린다', () {
      // 확정 10/12 02:00 KST = 10/11 17:00 UTC — 로컬로 읽으면 10/11 이 된다.
      final c = commitment(confirmedAt: kstAt(2026, 10, 12, 2));
      expect(
          candidate(
                  commitments: [c],
                  startDate: kst(2026, 10, 5),
                  endDate: kst(2026, 10, 9),
                  workDays: const ['월', '화', '수', '목', '금'])
              .blocksNewApplication,
          isFalse,
          reason: '확정 이전 주는 약속이 아니다');
      expect(
          candidate(
                  commitments: [c],
                  startDate: kst(2026, 10, 12),
                  endDate: kst(2026, 10, 16),
                  workDays: const ['월'])
              .blocksNewApplication,
          isTrue);
    });

    test('C7 퇴사일 D 는 포함, D+1 은 제외', () {
      final c = commitment(actualResignDate: kst(2026, 10, 12));
      expect(
          candidate(
                  commitments: [c],
                  startDate: kst(2026, 10, 12),
                  endDate: kst(2026, 10, 12),
                  workDays: const ['월'])
              .blocksNewApplication,
          isTrue);
      expect(
          candidate(
                  commitments: [c],
                  startDate: kst(2026, 10, 13),
                  endDate: kst(2026, 10, 16),
                  workDays: const ['화', '수', '목', '금'])
              .blocksNewApplication,
          isFalse);
    });

    test('C8 추가근무 하루만으로도 충돌이다 (요일 교집합 0)', () {
      expect(wkd(2026, 10, 10), '토');
      final c = commitment(extraWorkDates: [kst(2026, 10, 10)]);
      final r = candidate(
          commitments: [c],
          startDate: kst(2026, 10, 3),
          endDate: kst(2026, 10, 31),
          workDays: const ['토']);
      expect(r.blocksNewApplication, isTrue);
      expect(r.conflictDate, kst(2026, 10, 10).toUtc().add(
          const Duration(hours: 9)));
    });

    test('C9 휴무가 유일한 겹침일을 지우면 지원 가능', () {
      final c = commitment(leaveDates: [kst(2026, 10, 12)]);
      final r = candidate(
          commitments: [c],
          startDate: kst(2026, 10, 12),
          endDate: kst(2026, 10, 16),
          workDays: const ['월']);
      expect(r.blocksNewApplication, isFalse);
    });

    test('C10 휴무 하루가 반복 일정 전체를 지우지 않는다', () {
      final c = commitment(leaveDates: [kst(2026, 10, 12)]);
      final r = candidate(
          commitments: [c],
          startDate: kst(2026, 10, 12),
          endDate: kst(2026, 11, 30),
          workDays: const ['월']);
      expect(r.blocksNewApplication, isTrue, reason: '10/19 등 다른 월요일이 남는다');
      expect(r.conflictDate, isNot(kst(2026, 10, 12)));
    });

    test('C11 사업장이 달라도 막는다', () {
      final r = candidate(
          commitments: [commitment(businessId: 'bizZ', businessName: 'Z')],
          startDate: kst(2026, 10, 5),
          endDate: kst(2026, 10, 9),
          workDays: const ['월']);
      expect(r.blocksNewApplication, isTrue);
      expect(r.conflictBusinessName, 'Z');
    });

    test('C12 CONTRACT_PENDING 도 약속이다', () {
      final r = candidate(
          commitments: [commitment(status: AppStatus.contractPending)],
          startDate: kst(2026, 10, 5),
          endDate: kst(2026, 10, 9),
          workDays: const ['월']);
      expect(r.blocksNewApplication, isTrue);
    });

    for (final s in [AppStatus.pending, AppStatus.invited]) {
      test('C13/C14 $s 은 약속이 아니다 — 막지 않는다', () {
        final r = candidate(
            commitments: [commitment(status: s)],
            startDate: kst(2026, 10, 5),
            endDate: kst(2026, 10, 9),
            workDays: const ['월']);
        expect(r.blocksNewApplication, isFalse);
      });
    }

    for (final s in [
      AppStatus.canceled,
      AppStatus.autoCanceled,
      AppStatus.rejected,
      AppStatus.expired,
    ]) {
      test('C15 비활성($s) 은 막지 않는다', () {
        final r = candidate(
            commitments: [commitment(status: s)],
            startDate: kst(2026, 10, 5),
            endDate: kst(2026, 10, 9),
            workDays: const ['월']);
        expect(r.blocksNewApplication, isFalse);
      });
    }

    test('C16 자정 넘김 — 22:00~06:00 과 02:00~08:00 은 겹친다', () {
      final c = commitment(start: '22:00', end: '06:00');
      expect(
          candidate(
                  commitments: [c],
                  startDate: kst(2026, 10, 5),
                  endDate: kst(2026, 10, 9),
                  workDays: const ['월'],
                  start: '02:00',
                  end: '08:00')
              .blocksNewApplication,
          isTrue);
      expect(
          candidate(
                  commitments: [c],
                  startDate: kst(2026, 10, 5),
                  endDate: kst(2026, 10, 9),
                  workDays: const ['월'],
                  start: '10:00',
                  end: '14:00')
              .blocksNewApplication,
          isFalse);
    });

    test('C17 선택이 완성되지 않았으면 unknown — 가능이 아니다', () {
      // 요일을 아직 모른다.
      expect(
          candidate(
                  commitments: [commitment()],
                  startDate: kst(2026, 10, 5),
                  endDate: kst(2026, 10, 9),
                  workDays: const [])
              .outcome,
          CommitmentConflictOutcome.unknown);
      // 시간을 아직 모른다.
      expect(
          candidate(
                  commitments: [commitment()],
                  startDate: kst(2026, 10, 5),
                  endDate: kst(2026, 10, 9),
                  start: '',
                  end: '')
              .outcome,
          CommitmentConflictOutcome.unknown);
    });

    test('C18 목록을 못 읽었으면 unknown', () {
      final r = candidate(
          commitments: const [],
          startDate: kst(2026, 10, 5),
          endDate: kst(2026, 10, 9),
          known: false);
      expect(r.outcome, CommitmentConflictOutcome.unknown);
      expect(r.blocksNewApplication, isFalse);
      expect(r.isUnknown, isTrue);
    });

    test('C19 종료를 모르는 약속은 끝났다고 단정하지 않는다', () {
      final c = commitment(openEnded: true);
      // 근무일 판정은 그대로 false 다 — canonical 을 바꾸지 않았다.
      expect(c.isWorkingOnDate(DateTime.utc(2026, 10, 12)), isFalse);
      // 겹침 판정에서는 열린 구간으로 본다.
      final r = candidate(
          commitments: [c],
          startDate: kst(2026, 10, 5),
          endDate: kst(2026, 10, 9),
          workDays: const ['월']);
      expect(r.blocksNewApplication, isTrue);
    });

    test('C20 custom/preset parity — 같은 기간·요일·시간이면 같은 답', () {
      final c = commitment();
      final a = candidate(
          commitments: [c],
          startDate: kst(2026, 10, 5),
          endDate: kst(2026, 10, 9),
          workDays: const ['월']);
      final b = candidate(
          commitments: [c],
          startDate: kst(2026, 10, 5),
          endDate: kst(2026, 10, 9),
          workDays: const ['월']);
      expect(a.outcome, b.outcome);
      expect(a.conflictDate, b.conflictDate);
    });
  });

  // ══ 소스 계약 ═══════════════════════════════════════════════════════════
  group('LCA-S 소스 계약', () {
    test('S1 custom 우회가 사라졌다', () {
      final s = _read(_kSheet);
      expect(s.contains('if (_isCustom) {\n      if (mounted) setState(() => _isLoadingConflicts = false);\n      return;'),
          isFalse);
      expect(s.contains('충돌 체크 생략'), isFalse);
      // 목록은 한 번 읽고 판정은 메모리에서 한다.
      expect(s.contains('getMyConfirmedApplicationsForConflictCheck'), isTrue);
      expect(s.contains('CommitmentConflictResolver.commitmentsOf('), isTrue);
    });

    test('S2 판정 owner 는 하나다 — 화면 전용 충돌 함수 0', () {
      final s = _read(_kSheet);
      expect(s.contains('CommitmentConflictResolver.forLongTerm('), isTrue);
      // 예전의 날짜 집합·일일 루프가 남아 있지 않다.
      expect(s.contains('_confirmedDatesInRange'), isFalse);
      expect(s.contains('while (!cursor.isAfter(endDate))'), isFalse);
      expect(s.contains('hasTimeOverlap'), isFalse,
          reason: '시트가 겹침 식을 직접 쓰지 않는다');
    });

    test('S3 preset 의 과잉 차단 규칙이 사라졌다', () {
      final s = _read(_kSheet);
      expect(s.contains('if (!conflictDate.isBefore(dayOnly)) return false;'),
          isFalse);
      // 그 날을 **시작일로 하는 계약**으로 판정한다.
      expect(s.contains('return !_conflictFor(dayOnly).blocksNewApplication;'),
          isTrue);
    });

    test('S4 판정값과 payload 가 같은 기간을 본다', () {
      final s = _read(_kSheet);
      expect(s.contains('_conflictForPayload('), isTrue);
      // 제출 직전 **게이트**가 있다. 호출만 남기고 막지 않으면 낡은 화면에서
      //   눌리는 경로가 그대로 통과한다 — 그 경로는 위젯 테스트로 몰 수
      //   없으므로(CTA 가 비활성) 구조로 고정한다.
      expect(s.contains('if (submitConflict.blocksNewApplication) {'), isTrue);
      final guardAt = s.indexOf('if (submitConflict.blocksNewApplication) {');
      final submitAt = s.indexOf('setState(() => _isSubmitting = true);');
      expect(guardAt, greaterThan(-1));
      expect(submitAt, greaterThan(-1));
      expect(guardAt, lessThan(submitAt),
          reason: '게이트가 제출 시작보다 앞이어야 한다');
      expect(
          s.contains('workDate: effectiveWorkDate,\n      desiredStartDate: effectiveDesiredStart,\n      workEndDate: effectiveWorkEndDate,'),
          isTrue);
      expect(s.contains('startDate: desiredStartDate ?? workDate,'), isTrue);
    });

    test('S5 resolver 가 canonical 근무일 소유자에 위임한다', () {
      final r = _read(_kResolver);
      expect(r.contains('commitment.isWorkingOnDate(d)'), isTrue);
      // 구간·요일만 보는 사본이 남아 있지 않다.
      expect(r.contains('_commitmentStart('), isFalse);
      expect(r.contains('_commitmentCoversDay('), isFalse);
      // 그 소유자가 추가근무·휴무를 본다.
      final m = _read(_kModel);
      expect(m.contains('if (isExtraWorkDateOn(targetOnly)) return true;'), isTrue);
      expect(m.contains('if (isLeaveDateOn(targetOnly)) return false;'), isTrue);
    });

    test('S6 장기↔장기도 추가근무·휴무를 본다', () {
      final r = _read(_kResolver);
      expect(r.contains('commitment.extraWorkDates'), isTrue);
      expect(r.contains('commitment.leaveDates?.length'), isTrue);
      // 기간 전체를 하루씩 훑지 않는다 — 휴무 수로 상계한다.
      expect(r.contains('seen < budget'), isTrue);
    });

    test('S7 새 네트워크 읽기·listener 0', () {
      final s = _read(_kSheet);
      expect(s.contains('snapshots('), isFalse);
      expect(s.contains('httpsCallable'), isFalse);
      // production 기본값은 기존 서비스 메서드 하나다(테스트 seam 은 optional).
      expect(
          s.contains('widget.commitmentsSource ??'), isTrue,
          reason: '출처를 끼울 자리 하나만 둔다');
      final calls = RegExp(r'getMyConfirmedApplicationsForConflictCheck')
          .allMatches(s)
          .length;
      expect(calls, 1, reason: '약속 목록을 읽는 자리는 하나다');
      expect(s.contains('callableGetApplicationsForConflictCheck'), isFalse);
    });

    test('S8 서버 guard 와 정책은 그대로다', () {
      final fn = _read(_kFn);
      expect(fn.contains('// ── 6. 시간 충돌 체크 (확정 지원서 조회) ──'), isTrue);
      expect(
          fn.contains('const confirmedStatuses = ["CONFIRMED", "CONTRACT_PENDING"];'),
          isTrue);
      final mod = _read(_kMod);
      expect(mod.contains('export function longTermConflictDay('), isTrue);
    });

    test('S9 이유가 글자로 보인다 — 색만으로 말하지 않는다', () {
      final s = _read(_kSheet);
      expect(s.contains('확정된 일정과 시간이 겹쳐 지원할 수 없어요'), isTrue);
      expect(s.contains('확정 일정과 겹쳐 지원할 수 없어요'), isTrue);
      expect(s.contains('내 일정을 확인할 수 없어요'), isTrue);
      // `마감` 과 다른 상태다.
      expect(s.contains('마감되어 지원할 수 없어요'), isFalse);
    });
  });

  // ══ 렌더 — custom 시트가 실제로 그렇게 보이는가 ═══════════════════════
  group('LCA-R custom 시트 렌더', () {
    /// CTA 버튼의 활성 여부 — `onPressed == null` 이면 누를 수 없다.
    bool ctaEnabled(WidgetTester tester, String label) {
      final btn = tester.widget<ElevatedButton>(find.ancestor(
        of: find.text(label),
        matching: find.byType(ElevatedButton),
      ));
      return btn.onPressed != null;
    }

    testWidgets('R1 겹치면 이유가 보이고 제출할 수 없다', (tester) async {
      // 기존 약속 월~금 09:00~18:00 ↔ custom 후보 월~금 13:00~22:00.
      await _pumpSheet(tester, source: () async => [commitment()]);

      expect(find.textContaining('확정된 일정'), findsOneWidget,
          reason: '색만으로 말하지 않는다');
      expect(find.text('확정 일정과 겹쳐 지원할 수 없어요'), findsOneWidget);
      expect(ctaEnabled(tester, '확정 일정과 겹쳐 지원할 수 없어요'), isFalse);
      expect(find.text('이 조건으로 지원하기'), findsNothing);
    });

    testWidgets('R2 겹치지 않으면 제출할 수 있다', (tester) async {
      // 후보가 토요일만 — 기존 월~금 과 겹치는 날이 없다.
      await _pumpSheet(
        tester,
        source: () async => [commitment()],
        to: _customTo(workDays: const ['토']),
      );

      expect(find.text('이 조건으로 지원하기'), findsOneWidget);
      expect(ctaEnabled(tester, '이 조건으로 지원하기'), isTrue);
      expect(find.textContaining('확정된 일정'), findsNothing);
    });

    testWidgets('R3 추가근무 하루 때문에 막히면 그 날짜를 말한다', (tester) async {
      // 후보는 토요일만. 기존 약속에 10/10(토) 추가근무가 승인돼 있다.
      await _pumpSheet(
        tester,
        source: () async => [
          commitment(extraWorkDates: [kst(2026, 10, 10)]),
        ],
        to: _customTo(workDays: const ['토']),
      );

      expect(find.textContaining('10/10'), findsOneWidget);
      expect(ctaEnabled(tester, '확정 일정과 겹쳐 지원할 수 없어요'), isFalse);
    });

    testWidgets('R4 휴무로 비워진 기간은 지원할 수 있다', (tester) async {
      // custom 기간 10/5~10/30 · 후보 월요일만 → 10/5·12·19·26 이 겹칠 수 있다.
      //   그 네 날짜가 모두 휴무면 겹치는 날이 없다.
      await _pumpSheet(
        tester,
        source: () async => [
          commitment(leaveDates: [
            kst(2026, 10, 5), kst(2026, 10, 12),
            kst(2026, 10, 19), kst(2026, 10, 26),
          ]),
        ],
        to: _customTo(workDays: const ['월']),
      );
      expect(ctaEnabled(tester, '이 조건으로 지원하기'), isTrue);
    });

    testWidgets('R5 목록을 못 읽으면 사실을 말하고 서버에 맡긴다', (tester) async {
      await _pumpSheet(tester,
          source: () async => throw StateError('읽기 실패'));

      expect(find.textContaining('내 일정을 확인할 수 없어요'), findsOneWidget);
      // 조용히 "가능" 으로 광고하지 않지만, 제출 자체는 서버가 최종 판정한다.
      expect(ctaEnabled(tester, '이 조건으로 지원하기'), isTrue);
    });

    testWidgets('R6 좁은 폭·큰 배율 — 이유 박스 없이도 넘치는가(원인 분리)', (tester) async {
      // 겹치지 않는 fixture → 이번 phase 가 추가한 이유 박스가 **없는** 상태.
      await _pumpSheet(
        tester,
        source: () async => [commitment()],
        to: _customTo(workDays: const ['토']),
        size: const Size(320, 1600),
        textScale: 2.0,
      );
      // 이 셀이 원인을 분리했다 — 이유 박스가 없는데도 68px 넘쳤다. 원인은
      //    헤더 Row(라벨+배지, 둘 다 flex 없음)였고 같은
      //   phase 에서 CORRECTION 으로 고쳤다.
      expect(tester.takeException(), isNull);
    });

    testWidgets('R7 좁은 폭·큰 배율 + 이유 박스', (tester) async {
      await _pumpSheet(
        tester,
        source: () async => [commitment()],
        size: const Size(320, 1600),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
