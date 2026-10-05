// [R7-APPLICATION-LIFECYCLE.1C] 확정 약속과 겹치는 관계를
// **지원 가능이라고 광고하지 않는다** — reader/writer actionability parity.
//
// 고친 결함 `[CONFIRMED-CONFLICT-ADVERTISED-AS-APPLICABLE]`
//   서버 `callableApplyToTO` 는 같은 시간에 이미 약속(CONFIRMED ·
//   CONTRACT_PENDING)이 있으면 신규 지원을 **결정적으로 거부**한다.
//   그런데 그 사실을 아는 화면이 제각각이었다.
//     · 홈   `지원 가능한 일자리 N개` 가 지원할 수 없는 공고를 세고 있었다
//     · 상세 겹치는 업무에도 `선택` 을 그리고 CTA 의 N 에 셌다
//     · 지원 시트 쪽은 막고 있었지만, 그 판정의 출처가
//       `workEndDate >= workDate` 로 걸러진 CF 였다 — **단기 지원서에는 그
//       필드가 없어서**(서버가 `FieldValue.delete()` 한다) 단기 확정 근무를
//       아예 보지 못했다. 같은 날 같은 시간의 단기 확정이 있어도
//       `지원 가능` 이라고 말하고 서버가 거부했다.
//
// 이 파일이 고정하는 계약
//   · 판정은 **한 owner**(`CommitmentConflictResolver`)다 — 화면마다 만들지 않는다.
//   · 약속 = CONFIRMED + CONTRACT_PENDING. 관심(PENDING·INVITED)은 막지 않는다.
//   · 비활성(CANCELED·AUTO_CANCELED·REJECTED·EXPIRED)은 막지 않는다.
//   · 사업장을 가리지 않는다 — worker-global 이다.
//   · 인접(09~12 다음 12~15)은 현재 canonical 상 겹침이 아니다 — 유지.
//   · 읽지 못한 것(`unknown`)을 `지원 가능` 으로도 `지원 불가` 로도 바꾸지 않는다.
//   · 보이는 것 ≠ 지원할 수 있는 것 — 공고를 숨기지 않는다.
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/screens/user/home_recruitable_projection.dart';
import 'package:ALfit/widgets/dialogs/apply/commitment_conflict.dart';

// ── fixture ────────────────────────────────────────────────────────────────
const kTo = 'to_candidate';
const kOtherTo = 'to_other';
const kUid = 'worker1';

/// KST 날짜 키 — production `FormatHelper.toKstDate` 와 같은 꼴.
DateTime d(int day) => DateTime.utc(2026, 10, day);

/// KST 자정 instant — Firestore 저장 규약(UTC 로는 하루 전 15:00).
DateTime kstMidnight(int day) =>
    DateTime.utc(2026, 10, day).subtract(const Duration(hours: 9));

ApplicationModel _commitment({
  String status = AppStatus.confirmed,
  int day = 10,
  String start = '09:00',
  String end = '18:00',
  String? type,
  List<String>? workDays,
  int? endDay,
  int? desiredStartDay,
  int? actualResignDay,
  int? confirmedAtMs,
  List<DateTime>? extraWorkDates,
  List<DateTime>? leaveDates,
  String businessId = 'bizOther',
  String businessName = '다른 사업장',
}) =>
    ApplicationModel(
      id: 'app_${status}_$day',
      uid: kUid,
      toId: kOtherTo,
      slotId: 'slotX',
      businessId: businessId,
      businessName: businessName,
      toTitle: '다른 공고',
      selectedWorkType: '홀서빙',
      wdId: 'wdOther',
      startTime: start,
      endTime: end,
      wage: 12000,
      wageType: 'hourly',
      status: status,
      applicationType: type,
      workDays: workDays,
      workDate: kstMidnight(day),
      desiredStartDate:
          desiredStartDay == null ? null : kstMidnight(desiredStartDay),
      workEndDate: endDay == null ? null : kstMidnight(endDay),
      actualResignDate:
          actualResignDay == null ? null : kstMidnight(actualResignDay),
      appliedAt: DateTime(2026, 10, 1),
      confirmedAt: confirmedAtMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(confirmedAtMs, isUtc: true),
      extraWorkDates: extraWorkDates,
      leaveDates: leaveDates,
    );

CommitmentConflictDecision _short({
  required List<ApplicationModel> commitments,
  int day = 10,
  String start = '09:00',
  String end = '18:00',
  bool known = true,
}) =>
    CommitmentConflictResolver.forShortTerm(
      commitments: CommitmentConflictResolver.commitmentsOf(commitments),
      commitmentsKnown: known,
      workDate: kstMidnight(day),
      startTime: start,
      endTime: end,
    );

CommitmentConflictDecision _long({
  required List<ApplicationModel> commitments,
  int startDay = 10,
  int? endDay = 40,
  List<String> workDays = const ['월', '화', '수', '목', '금', '토', '일'],
  String start = '09:00',
  String end = '18:00',
  bool known = true,
}) =>
    CommitmentConflictResolver.forLongTerm(
      commitments: CommitmentConflictResolver.commitmentsOf(commitments),
      commitmentsKnown: known,
      startDate: kstMidnight(startDay),
      endDate: endDay == null ? null : kstMidnight(endDay),
      workDays: workDays,
      startTime: start,
      endTime: end,
    );

WorkDetailData _wd({
  required String wdId,
  String type = '홀서빙',
  String start = '09:00',
  String end = '18:00',
  int required_ = 5,
}) =>
    WorkDetailData(
      wdId: wdId,
      workType: type,
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: required_,
      startTime: start,
      endTime: end,
    );

TOModel _flexTo({
  List<String> dates = const ['2026-10-10', '2026-10-11'],
  List<WorkDetailData> workDetails = const [],
}) =>
    TOModel(
      id: kTo,
      businessId: 'bizCandidate',
      businessName: '후보 사업장',
      type: 'flex',
      title: '단기 모집',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: workDetails,
      totalRequired: 10,
      totalConfirmed: 0,
      totalPending: 0,
      isPublished: true,
      publishMode: 'immediate',
      slotDateKeys: dates,
      totalSlots: dates.length,
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

SlotModel _slot({
  required int day,
  required List<WorkDetailData> wds,
  String status = SlotStatus.open,
  Map<String, SlotWorkTypeCount> counts = const {},
}) =>
    SlotModel(
      id: 'slot$day',
      toId: kTo,
      date: kstMidnight(day),
      workDetails: wds,
      workDetailCounts: counts,
      status: status,
    );

HomeRecruitableProjection _home({
  required List<ApplicationModel> apps,
  TOModel? to,
  Map<String, List<SlotModel>> slots = const {},
  bool known = true,
}) =>
    HomeRecruitableProjection.build(
      publishedTos: [to ?? _flexTo()],
      myApplications: apps,
      today: d(1),
      cutoff: d(31),
      slotsByToId: slots,
      commitmentsKnown: known,
    );

// 소스 계약 — 파일을 읽어 고정한다.
String _read(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('없는 파일: $p');
  return f.readAsStringSync();
}

const _kResolver = 'lib/widgets/dialogs/apply/commitment_conflict.dart';
const _kProjection = 'lib/screens/user/home_recruitable_projection.dart';
const _kDetail = 'lib/screens/common/job_posting_screen.dart';
const _kService = 'lib/services/schedule_conflict_service.dart';
const _kDialog = 'lib/widgets/dialogs/apply/apply_work_dialog.dart';
const _kSheet = 'lib/widgets/dialogs/apply/multi_apply_confirm_sheet.dart';
const _kJobTab = 'lib/screens/user/tabs/user_job_tab.dart';
const _kFn = 'functions/src/index.ts';

void main() {
  // ══ C1~C12 — 판정 의미(서버 Policy X parity) ════════════════════════════
  group('CC-C 판정 의미', () {
    test('C1 겹치지 않는 시간 → 지원 가능', () {
      final r = _short(
          commitments: [_commitment(start: '19:00', end: '22:00')],
          start: '09:00',
          end: '18:00');
      expect(r.outcome, CommitmentConflictOutcome.none);
      expect(r.blocksNewApplication, isFalse);
    });

    test('C2 CONFIRMED 와 부분 겹침 → 충돌', () {
      final r = _short(
          commitments: [_commitment(start: '13:00', end: '22:00')],
          start: '09:00',
          end: '18:00');
      expect(r.blocksNewApplication, isTrue);
      expect(r.conflictTime, '13:00~22:00');
      expect(r.conflictBusinessName, '다른 사업장');
    });

    test('C3 CONTRACT_PENDING 과 완전 겹침 → 충돌', () {
      final r = _short(commitments: [
        _commitment(status: AppStatus.contractPending),
      ]);
      expect(r.blocksNewApplication, isTrue);
    });

    test('C4 인접(09~12 다음 12~15)은 겹침이 아니다 — 현재 canonical 유지', () {
      final r = _short(
          commitments: [_commitment(start: '09:00', end: '12:00')],
          start: '12:00',
          end: '15:00');
      expect(r.blocksNewApplication, isFalse,
          reason: '90분 buffer 같은 분리 규칙을 도입하지 않는다');
    });

    test('C5 다른 날짜 → 지원 가능', () {
      final r = _short(commitments: [_commitment(day: 10)], day: 11);
      expect(r.blocksNewApplication, isFalse);
    });

    test('C6 다른 사업장이어도 시간이 겹치면 충돌 (worker-global)', () {
      final r = _short(commitments: [
        _commitment(businessId: 'bizZ', businessName: 'Z 사업장'),
      ]);
      expect(r.blocksNewApplication, isTrue);
      expect(r.conflictBusinessName, 'Z 사업장');
    });

    test('C7 PENDING 만 겹침 → 지원 가능 (지원 = 관심)', () {
      final r = _short(commitments: [
        _commitment(status: AppStatus.pending),
      ]);
      expect(r.blocksNewApplication, isFalse);
    });

    test('C8 INVITED 만 겹침 → 지원 가능', () {
      final r = _short(commitments: [
        _commitment(status: AppStatus.invited),
      ]);
      expect(r.blocksNewApplication, isFalse);
    });

    for (final s in [
      AppStatus.canceled,
      AppStatus.autoCanceled,
      AppStatus.rejected,
      AppStatus.expired,
    ]) {
      test('C9 비활성($s) 겹침 → 지원 가능', () {
        final r = _short(commitments: [_commitment(status: s)]);
        expect(r.blocksNewApplication, isFalse);
      });
    }

    test('C10 단기 후보 ↔ 장기 약속 — 기간 안 + 근무요일이면 충돌', () {
      // 10/10 은 토요일. 약속은 토요일 근무.
      final c = _commitment(
          day: 5, endDay: 30, workDays: const ['토'], type: 'long_term');
      expect(_short(commitments: [c], day: 10).blocksNewApplication, isTrue);
      // 10/11 은 일요일 — 그 약속의 근무요일이 아니다.
      expect(_short(commitments: [c], day: 11).blocksNewApplication, isFalse);
      // 기간 밖.
      expect(_short(commitments: [c], day: 31).blocksNewApplication, isFalse);
    });

    test('C10b 장기 후보 ↔ 단기 약속 — 그 하루가 내 기간·요일이면 충돌', () {
      final c = _commitment(day: 15);
      expect(_long(commitments: [c]).blocksNewApplication, isTrue);
      // 내 근무요일에서 그 날(10/15 목) 을 빼면 충돌하지 않는다.
      expect(
          _long(commitments: [c], workDays: const ['월', '화']).blocksNewApplication,
          isFalse);
      // 내 기간 밖.
      expect(_long(commitments: [c], startDay: 20).blocksNewApplication,
          isFalse);
    });

    test('C11 장기 ↔ 장기 — 기간은 겹치지만 요일이 서로 다르면 충돌 아님', () {
      final c = _commitment(
          day: 5, endDay: 40, workDays: const ['월', '화'], type: 'long_term');
      expect(
          _long(commitments: [c], workDays: const ['수', '목'])
              .blocksNewApplication,
          isFalse);
      expect(
          _long(commitments: [c], workDays: const ['화', '수'])
              .blocksNewApplication,
          isTrue);
    });

    test('C11b 장기 ↔ 장기 — 기간이 아예 떨어져 있으면 충돌 아님', () {
      final c = _commitment(
          day: 1, endDay: 5, workDays: const ['월', '화', '수', '목', '금'],
          type: 'long_term');
      expect(_long(commitments: [c], startDay: 10).blocksNewApplication,
          isFalse);
    });

    test('C12 자정 넘김(22:00~06:00) — 다음 날 02:00~08:00 과 겹친다', () {
      final c = _commitment(day: 10, start: '22:00', end: '06:00');
      expect(
          _short(commitments: [c], day: 10, start: '02:00', end: '08:00')
              .blocksNewApplication,
          isTrue);
      expect(
          _short(commitments: [c], day: 10, start: '10:00', end: '14:00')
              .blocksNewApplication,
          isFalse);
    });
  });

  // ══ 약속 경계 ═══════════════════════════════════════════════════════════
  group('CC-B 약속 경계', () {
    test('B1 약속 집합은 AppStatus.confirmedStatuses 그대로다', () {
      final all = [
        _commitment(status: AppStatus.confirmed),
        _commitment(status: AppStatus.contractPending),
        _commitment(status: AppStatus.pending),
        _commitment(status: AppStatus.invited),
        _commitment(status: AppStatus.canceled),
        _commitment(status: AppStatus.autoCanceled),
        _commitment(status: AppStatus.rejected),
        _commitment(status: AppStatus.expired),
      ];
      final kept = CommitmentConflictResolver.commitmentsOf(all)
          .map((a) => a.status)
          .toSet();
      expect(kept, AppStatus.confirmedStatuses.toSet());
    });

    test('B2 퇴사일(actualResignDate) 이후는 자리를 차지하지 않는다', () {
      final c = _commitment(
          day: 5,
          endDay: 40,
          actualResignDay: 12,
          workDays: const ['토', '일', '월', '화', '수', '목', '금'],
          type: 'long_term');
      expect(_short(commitments: [c], day: 11).blocksNewApplication, isTrue);
      expect(_short(commitments: [c], day: 13).blocksNewApplication, isFalse);
    });

    test('B3 종료일을 모르는 장기 약속은 무한으로 본다 (서버와 같다)', () {
      final c = _commitment(
          day: 5, workDays: const ['토'], type: 'long_term');
      expect(_short(commitments: [c], day: 10).blocksNewApplication, isTrue);
      expect(_short(commitments: [c], day: 31).blocksNewApplication, isTrue);
    });

    test('B4 약속 시작은 canonical — desiredStartDate ?? workDate', () {
      // workDate(=anchor) 10/05, desiredStartDate 10/20 → 실제 약속은 10/20 부터.
      //
      // [R7-APPLICATION-LIFECYCLE.1C.2] 1C 에서는 서버 `callableApplyToTO` 가
      //   `workDate` 를 보고 있었으므로 화면도 **이른 쪽**을 쓰는 것이 안전했다
      //   (서버가 거부하는 것을 화면이 가능하다고 광고하지 않기 위해).
      //   1C.1 이 서버를 canonical 로 고쳤다 — 이제 10/10 은 서버가 **허용**한다.
      //   화면이 계속 이른 쪽을 쓰면 가능한 지원을 과잉 차단한다.
      final c = _commitment(
          day: 5,
          desiredStartDay: 20,
          endDay: 40,
          workDays: const ['토'],
          type: 'long_term');
      expect(_short(commitments: [c], day: 10).blocksNewApplication, isFalse,
          reason: '10/10 은 효력 시작(10/20) 이전이다 — 서버도 허용한다');
      // 효력 시작 이후의 토요일은 그대로 막는다.
      expect(_short(commitments: [c], day: 24).blocksNewApplication, isTrue);
    });

    test('B4b 희망 시작일이 없으면 확정일(KST)로 밀린다', () {
      // workDate 10/05, confirmedAt 10/12 02:00 KST → 효력 시작 10/12.
      final c = _commitment(
          day: 5,
          endDay: 40,
          workDays: const ['토'],
          confirmedAtMs: DateTime.utc(2026, 10, 11, 17).millisecondsSinceEpoch,
          type: 'long_term');
      expect(_short(commitments: [c], day: 10).blocksNewApplication, isFalse);
      expect(_short(commitments: [c], day: 17).blocksNewApplication, isTrue);
    });

    test('B5 요일을 모르는 장기 약속은 아무 날도 막지 않는다 (서버 parity)', () {
      final c = _commitment(day: 5, endDay: 40, type: 'long_term');
      expect(_short(commitments: [c], day: 10).blocksNewApplication, isFalse);
    });
  });

  // ══ ERROR ≠ eligible ════════════════════════════════════════════════════
  group('CC-U 모르는 것', () {
    test('U1 목록을 못 읽으면 unknown — none 이 아니다', () {
      final r = _short(commitments: [], known: false);
      expect(r.outcome, CommitmentConflictOutcome.unknown);
      expect(r.isUnknown, isTrue);
      expect(r.blocksNewApplication, isFalse,
          reason: '읽기 실패로 전부 지원 불가가 되어서도 안 된다');
    });

    test('U2 후보의 시간을 모르면 unknown', () {
      expect(_short(commitments: [], start: '', end: '').isUnknown, isTrue);
      expect(_long(commitments: [], start: '09:00', end: '').isUnknown, isTrue);
    });

    test('U3 장기 판정도 같은 계약', () {
      expect(_long(commitments: [], known: false).outcome,
          CommitmentConflictOutcome.unknown);
    });
  });

  // ══ H1~H6 — 홈 ═════════════════════════════════════════════════════════
  group('CC-H 홈 수치', () {
    final flexWithWds = _flexTo(workDetails: [
      _wd(wdId: 'wdA'),
      _wd(wdId: 'wdB', type: '주방', start: '19:00', end: '22:00'),
    ]);

    test('H1 약속이 없으면 전부 지원 가능', () {
      final p = _home(apps: const [], to: flexWithWds);
      expect(p.countOn(d(10)), 1);
      expect(p.countOn(d(11)), 1);
    });

    test('H2 하루만 겹치면 그 하루만 빠진다', () {
      final p = _home(
          apps: [_commitment(day: 10, start: '09:00', end: '18:00')],
          to: _flexTo(workDetails: [_wd(wdId: 'wdA')]));
      expect(p.countOn(d(10)), 0, reason: '서버가 거부하는 날짜는 세지 않는다');
      expect(p.countOn(d(11)), 1);
      expect(p.hasAnyDate(kTo), isTrue, reason: '공고를 숨기지 않는다');
    });

    test('H3 모든 날짜가 겹치면 그 공고는 어디에도 없다 (true zero)', () {
      final p = _home(
          apps: [
            _commitment(day: 10, start: '09:00', end: '18:00'),
            _commitment(day: 11, start: '09:00', end: '18:00'),
          ],
          to: _flexTo(workDetails: [_wd(wdId: 'wdA')]));
      expect(p.countOn(d(10)), 0);
      expect(p.countOn(d(11)), 0);
      expect(p.hasAnyDate(kTo), isFalse);
    });

    test('H4 겹치지 않는 형제 업무가 하나라도 있으면 그 날짜는 1', () {
      final p = _home(
          apps: [_commitment(day: 10, start: '09:00', end: '18:00')],
          to: flexWithWds);
      expect(p.countOn(d(10)), 1,
          reason: '19:00~22:00 주방은 지원할 수 있다 — 공고 단위 수치는 1');
    });

    test('H5 정원이 찬 업무는 형제로 세지 않는다 (마감 ≠ 일정 겹침)', () {
      final p = _home(
        apps: [_commitment(day: 10, start: '09:00', end: '18:00')],
        to: flexWithWds,
        slots: {
          kTo: [
            _slot(day: 10, wds: [
              _wd(wdId: 'wdA'),
              _wd(wdId: 'wdB', type: '주방', start: '19:00', end: '22:00',
                  required_: 1),
            ], counts: const {
              'wdB': SlotWorkTypeCount(confirmedCount: 1, pendingCount: 0),
            }),
          ],
        },
      );
      expect(p.countOn(d(10)), 0,
          reason: 'wdA 는 일정 겹침, wdB 는 정원 충족 — 지원할 수 있는 것이 없다');
    });

    test('H6 목록을 못 읽었으면 후보를 지우지 않는다', () {
      final p = _home(
          apps: const [],
          to: _flexTo(workDetails: [_wd(wdId: 'wdA')]),
          known: false);
      expect(p.countOn(d(10)), 1);
      expect(p.countOn(d(11)), 1);
    });

    test('H7 업무 시간을 모르는 공고는 남긴다', () {
      final p = _home(
          apps: [_commitment(day: 10, start: '09:00', end: '18:00')],
          to: _flexTo()); // workDetails 비어 있음
      expect(p.countOn(d(10)), 1, reason: '모르는 것을 0 으로 바꾸지 않는다');
    });

    test('H8 슬롯 시간이 공고 템플릿과 다르면 슬롯이 canonical 이다', () {
      final p = _home(
        apps: [_commitment(day: 10, start: '09:00', end: '18:00')],
        to: _flexTo(workDetails: [_wd(wdId: 'wdA')]), // 템플릿 09~18
        slots: {
          kTo: [
            // 그 날짜 슬롯은 19~22 로 운영된다 — 겹치지 않는다.
            _slot(day: 10,
                wds: [_wd(wdId: 'wdA', start: '19:00', end: '22:00')]),
          ],
        },
      );
      expect(p.countOn(d(10)), 1);
    });

    test('H10 두 공고 중 하나만 겹치면 수치는 2 가 아니라 1 이다', () {
      final conflicting = _flexTo(
          dates: const ['2026-10-10'], workDetails: [_wd(wdId: 'wdA')]);
      final eligible = TOModel(
        id: 'to_eligible',
        businessId: 'bizB',
        businessName: '다른 후보',
        type: 'flex',
        title: '단기 모집 B',
        creatorUID: 'admin2',
        status: TOStatus.active,
        deadlineType: 'NONE',
        hoursBeforeStart: 0,
        workDetails: [_wd(wdId: 'wdB', start: '19:00', end: '22:00')],
        totalRequired: 5,
        totalConfirmed: 0,
        totalPending: 0,
        isPublished: true,
        publishMode: 'immediate',
        slotDateKeys: const ['2026-10-10'],
        totalSlots: 1,
        createdAt: DateTime(2026, 9, 1),
        statusUpdatedAt: DateTime(2026, 9, 1),
      );
      final p = HomeRecruitableProjection.build(
        publishedTos: [conflicting, eligible],
        myApplications: [_commitment(day: 10, start: '09:00', end: '18:00')],
        today: d(1),
        cutoff: d(31),
      );
      expect(p.countOn(d(10)), 1);
      // 추천 후보도 같은 projection 을 지난다 — 겹치는 쪽이 빠진다.
      expect(p.hasAnyDate(kTo), isFalse);
      expect(p.hasAnyDate('to_eligible'), isTrue);
    });

    test('H9 관심(PENDING)만 겹쳐도 홈 수치는 줄지 않는다', () {
      final p = _home(
          apps: [
            _commitment(
                day: 10, start: '09:00', end: '18:00',
                status: AppStatus.pending),
          ],
          to: _flexTo(workDetails: [_wd(wdId: 'wdA')]));
      expect(p.countOn(d(10)), 1);
    });
  });

  // ══ 소스 계약 ═══════════════════════════════════════════════════════════
  group('CC-S 소스 계약', () {
    test('S1 판정 owner 는 하나다 — 화면별 충돌 함수를 만들지 않았다', () {
      // 홈·상세는 owner 를 직접 쓰고, 지원 dialog·확인 시트는
      //   `ScheduleConflictService` 를 거쳐 **같은** owner 에 닿는다.
      for (final p in [_kProjection, _kDetail, _kService]) {
        expect(_read(p).contains('CommitmentConflictResolver'), isTrue,
            reason: '$p 가 공용 owner 를 쓴다');
      }
      for (final p in [_kDialog, _kSheet]) {
        expect(_read(p).contains('ScheduleConflictService'), isTrue,
            reason: '$p 는 서비스를 거쳐 같은 owner 에 닿는다');
      }
      // 화면이 자기 겹침 식을 따로 갖고 있지 않다.
      final own = RegExp(r'bool\s+_?\w*[Oo]verlaps?\s*\(');
      for (final p in [_kProjection, _kDetail]) {
        expect(own.hasMatch(_read(p)), isFalse, reason: '$p 에 자체 겹침 식 없음');
      }
    });

    test('S2 약속 상태 집합을 손으로 다시 적지 않는다', () {
      final src = _read(_kResolver);
      expect(src.contains('AppStatus.confirmedStatuses'), isTrue);
      // PENDING·INVITED 를 blocker 로 쓰지 않는다.
      expect(src.contains('AppStatus.pending'), isFalse);
      expect(src.contains('AppStatus.invited'), isFalse);
    });

    test('S3 겹침 식은 ApplicationModel.hasTimeOverlap 하나다', () {
      expect(_read(_kResolver).contains('ApplicationModel.hasTimeOverlap'),
          isTrue);
      final svc = _read(_kService);
      expect(svc.contains('ApplicationModel.hasTimeOverlap'), isTrue);
      // 서비스가 자체 겹침 판정을 다시 쓰지 않는다.
      expect(svc.contains('final noOverlap ='), isFalse);
    });

    test('S4 충돌 출처는 workEndDate 로 걸러진 CF 가 아니다', () {
      final svc = _read(_kService);
      // 호출 자리에 없어야 한다(주석에서 **왜** 버렸는지는 설명한다).
      expect(
          svc.contains("httpsCallable('callableGetApplicationsForConflictCheck'"),
          isFalse,
          reason: '그 쿼리는 workEndDate 가 없는 단기 약속을 보지 못한다');
      expect(svc.contains("httpsCallable('callableGetMyApplications'"), isTrue);
      expect(svc.contains('AppStatus.confirmedStatuses'), isTrue);
    });

    test('S5 서버 Policy X 는 그대로다 (클라이언트 gating 이 대체하지 않는다)', () {
      final fn = _read(_kFn);
      expect(fn.contains('// ── 6. 시간 충돌 체크 (확정 지원서 조회) ──'), isTrue);
      expect(
          fn.contains('const confirmedStatuses = ["CONFIRMED", "CONTRACT_PENDING"];'),
          isTrue);
      expect(fn.contains('확정된 근무가 있어 지원할 수 없습니다.'), isTrue);
      expect(fn.contains('이미 \${appStartTime}~\${appEndTime}에 확정된 근무가 있습니다.'),
          isTrue);
    });

    test('S6 홈은 이미 읽은 목록을 쓴다 — 새 쿼리·listener 0', () {
      final proj = _read(_kProjection);
      expect(proj.contains('FirebaseFirestore'), isFalse);
      expect(proj.contains('httpsCallable'), isFalse);
      expect(proj.contains('snapshots('), isFalse);
      expect(proj.contains('await '), isFalse, reason: '순수 계산이다');
      // 홈 화면이 projection 에 읽기 상태를 넘긴다.
      final home = _read('lib/screens/user/user_home_screen.dart');
      expect(home.contains('commitmentsKnown: !_homeLoadFailed'), isTrue);
    });

    test('S7 Jobs 의 공개 노출은 그대로다 (visibility ≠ eligibility)', () {
      final tab = _read(_kJobTab);
      expect(tab.contains('CommitmentConflict'), isFalse,
          reason: '발견 목록에서 공고를 걸러내지 않는다 — pagination hole 금지');
    });

    test('S8 상세는 선택·집계·탭 세 자리 모두 같은 판정을 지난다', () {
      final src = _read(_kDetail);
      final hits = RegExp(r'_commitmentConflictFor\(').allMatches(src).length;
      expect(hits, greaterThanOrEqualTo(4),
          reason: '정의 + canSelect + _newApplyTargets + _toggleWork');
      expect(src.contains('확정된 일정과 시간이 겹쳐 지원할 수 없어요'), isTrue);
    });

    test('S9 상세는 장기(계약형)를 이 자리에서 막지 않는다', () {
      final src = _read(_kDetail);
      expect(src.contains("if (!(_to?.isFlexType ?? false)) return CommitmentConflictDecision.none;"),
          isTrue,
          reason: '희망 시작일을 고르기 전에 막으면 더 늦은 시작일을 막는다');
    });

    test('S10 지원 dialog 는 제출 직전 그 날짜를 확인한다', () {
      final src = _read(_kDialog);
      expect(src.contains('if (!_conflictCache.containsKey(cacheKey))'), isTrue);
      expect(src.contains('info.level == ConflictLevel.blocked'), isTrue);
    });

    test('S11 확인 시트는 읽기 실패를 available 로 바꾸지 않는다', () {
      final src = _read(_kSheet);
      expect(src.contains('에러 시 available로 폴백'), isFalse);
      expect(
          src.contains('확정 일정과 겹치는지 확인할 수 없어요'), isTrue);
    });

    test('S12 90분 buffer 같은 분리 규칙을 도입하지 않았다', () {
      final src = _read(_kResolver);
      expect(src.contains('90'), isFalse);
      expect(src.contains('buffer'), isFalse);
    });
  });
}
