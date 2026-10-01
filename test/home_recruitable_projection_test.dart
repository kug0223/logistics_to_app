// [R7-P4.4E.8A] 홈이 "그 날짜에 지원할 수 있는 공고" 를 판단하는 계약.
//
// 고친 결함 (DEVICE REPRODUCED → DEV 실측으로 확정)
//   홈의 두 곳(날짜칩 `_toDateCounts` · 추천 목록 `_getRecommendedTos`)이
//   각각 `appliedToIds.contains(to.id)` 로 **공고 전체를 버렸다**.
//   flex 공고 `Zi9UDkhZdTua5AgkG5HQ` 의 10/05 에 지원했더니 10/06~10/11 의
//   다른 날짜 모집까지 사라졌다 — **6일 × 2업무 = 12개의 실제 지원 가능한
//   근무**가 홈에서 없어졌고, 공고가 1건뿐인 DEV 에서는 모든 날짜 칩이 0 이
//   됐다. Jobs 목록·공고 상세·서버는 같은 사실을 다르게 말하고 있었다.
//
// 이 파일이 고정하는 계약
//   · 관계가 있는 **그 wdId 만** 빠진다. 형제 wdId·다른 날짜는 산다.
//   · 상태 축은 서버와 같다 — inactive 는 자격이 돌아온다.
//   · 모르는 것(슬롯 미로드·날짜 불완전)을 0 으로 바꾸지 않는다.
//   · `일자리 N개` 의 N 은 **공고 수**다(업무 수가 아니다).
import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/screens/user/home_recruitable_projection.dart';

// ── DEV 실측 fixture 를 그대로 쓴다 ────────────────────────────────
const kTo = 'Zi9UDkhZdTua5AgkG5HQ';
const kUid = 'psKpbHANvkdPU9PgJoBiPNoeIT93';

/// KST 날짜 비교 키 — production `FormatHelper.toKstDate` 와 같은 꼴(utc 정규화).
DateTime d(int day) => DateTime.utc(2026, 10, day);

/// KST 자정 instant — Firestore 에 그렇게 저장돼 있다(실측: UTC 로는 하루 전).
DateTime kstMidnight(int day) =>
    DateTime.utc(2026, 10, day).subtract(const Duration(hours: 9));

const kDates = [
  '2026-10-05', '2026-10-06', '2026-10-07', '2026-10-08',
  '2026-10-09', '2026-10-10', '2026-10-11',
];

WorkDetailData _wd({
  required String wdId,
  String type = '냉장분류',
  String start = '18:00',
  String end = '22:30',
  int required_ = 10,
  bool manualClosed = false,
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
      isManualClosed: manualClosed,
    );

TOModel _flexTo({
  List<String> dates = kDates,
  int totalSlots = 7,
}) =>
    TOModel(
      id: kTo,
      businessId: 'biz1',
      businessName: '강남 물류센터',
      type: 'flex',
      title: '단기 모집',
      creatorUID: 'admin1',
      status: TOStatus.active,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: 140,
      totalConfirmed: 0,
      totalPending: 2,
      isPublished: true,
      publishMode: 'immediate',
      slotDateKeys: dates,
      totalSlots: totalSlots,
      createdAt: DateTime(2026, 9, 1),
      statusUpdatedAt: DateTime(2026, 9, 1),
    );

SlotModel _slot({
  required String id,
  required int day,
  required List<WorkDetailData> wds,
  String status = SlotStatus.open,
  Map<String, SlotWorkTypeCount> counts = const {},
}) =>
    SlotModel(
      id: id,
      toId: kTo,
      date: kstMidnight(day),
      workDetails: wds,
      workDetailCounts: counts,
      status: status,
    );

ApplicationModel _app({
  required String status,
  required String wdId,
  required int day,
  String slotId = 'slot05',
  String type = '냉장분류',
  String? resignStatus,
  String? terminationStatus,
}) =>
    ApplicationModel(
      id: '${kTo}_${slotId}_${wdId}_$kUid',
      uid: kUid,
      toId: kTo,
      slotId: slotId,
      businessId: 'biz1',
      businessName: '강남 물류센터',
      toTitle: '단기 모집',
      selectedWorkType: type,
      wdId: wdId,
      startTime: '18:00',
      endTime: '22:30',
      wage: 12000,
      wageType: 'hourly',
      status: status,
      workDate: kstMidnight(day),
      appliedAt: DateTime(2026, 10, 1),
      resignStatus: resignStatus,
      terminationStatus: terminationStatus,
    );

/// 10/05 슬롯 — 냉장(wdA) + 냉동(wdB).
SlotModel _slot05({
  String status = SlotStatus.open,
  bool wdAClosed = false,
  bool wdBClosed = false,
  Map<String, SlotWorkTypeCount> counts = const {},
}) =>
    _slot(
      id: 'slot05',
      day: 5,
      status: status,
      counts: counts,
      wds: [
        _wd(wdId: 'wdA', type: '냉장분류', manualClosed: wdAClosed),
        _wd(wdId: 'wdB', type: '냉동분류', manualClosed: wdBClosed),
      ],
    );

HomeRecruitableProjection _build({
  required List<ApplicationModel> apps,
  TOModel? to,
  Map<String, List<SlotModel>> slots = const {},
}) =>
    HomeRecruitableProjection.build(
      publishedTos: [to ?? _flexTo()],
      myApplications: apps,
      today: d(1),
      cutoff: d(30),
      slotsByToId: slots,
    );

void main() {
  group('HRP-1x DEVICE 반례 — 다른 날짜가 살아 있다', () {
    test('HRP-10 10/05 두 wdId 모두 PENDING → 10/05 는 0, 10/06~11 은 산다', () {
      final p = _build(
        apps: [
          _app(status: AppStatus.pending, wdId: 'wdA', day: 5),
          _app(status: AppStatus.pending, wdId: 'wdB', day: 5, type: '냉동분류'),
        ],
        slots: {kTo: [_slot05()]},
      );

      expect(p.isRecruitable(kTo, d(5)), isFalse,
          reason: '그 날짜엔 신규 지원 가능한 근무가 남지 않았다 — 0 이 정상');
      expect(p.countOn(d(5)), 0);

      for (final day in [6, 7, 8, 9, 10, 11]) {
        expect(p.isRecruitable(kTo, d(day)), isTrue,
            reason: '10/$day 는 관계가 없다 — 사라지면 안 된다');
        expect(p.countOn(d(day)), 1, reason: 'N 은 공고 수다');
      }
    });

    test('HRP-11 같은 날짜 A=PENDING / B=NONE → 그 날짜도 산다', () {
      final p = _build(
        apps: [_app(status: AppStatus.pending, wdId: 'wdA', day: 5)],
        slots: {kTo: [_slot05()]},
      );
      expect(p.isRecruitable(kTo, d(5)), isTrue,
          reason: '형제 근무(냉동분류)가 남아 있다');
      expect(p.countOn(d(5)), 1);
    });

    test('HRP-12 지원 하나로 공고가 통째로 사라지지 않는다', () {
      final p = _build(
        apps: [_app(status: AppStatus.pending, wdId: 'wdA', day: 5)],
        slots: {kTo: [_slot05()]},
      );
      expect(p.hasAnyDate(kTo), isTrue);
      // 7일 전부 노출 — 10/05 는 형제가 남아서, 나머지는 관계가 없어서.
      expect(p.byDate.keys.length, 7);
    });
  });

  group('HRP-2x 상태 축 — 서버와 같다', () {
    for (final s in [AppStatus.pending, AppStatus.confirmed,
      AppStatus.contractPending, AppStatus.invited]) {
      test('HRP-20 $s 는 그 wdId 만 막는다 (형제 유지)', () {
        final p = _build(
          apps: [_app(status: s, wdId: 'wdA', day: 5)],
          slots: {kTo: [_slot05()]},
        );
        expect(p.isRecruitable(kTo, d(5)), isTrue,
            reason: '형제 wdB 가 남아 있다');
      });

      test('HRP-21 $s 가 두 wdId 전부면 그 날짜는 0', () {
        final p = _build(
          apps: [
            _app(status: s, wdId: 'wdA', day: 5),
            _app(status: s, wdId: 'wdB', day: 5, type: '냉동분류'),
          ],
          slots: {kTo: [_slot05()]},
        );
        expect(p.isRecruitable(kTo, d(5)), isFalse);
      });
    }

    for (final s in [AppStatus.rejected, AppStatus.canceled,
      AppStatus.autoCanceled, AppStatus.expired]) {
      test('HRP-22 $s → 자격이 돌아온다 (서버가 재지원을 허용한다)', () {
        final p = _build(
          apps: [
            _app(status: s, wdId: 'wdA', day: 5),
            _app(status: s, wdId: 'wdB', day: 5, type: '냉동분류'),
          ],
          slots: {kTo: [_slot05()]},
        );
        expect(p.isRecruitable(kTo, d(5)), isTrue);
      });
    }

    test('HRP-23 퇴사·해지 승인 완료 → 관계로 보지 않는다', () {
      final p = _build(
        apps: [
          _app(
              status: AppStatus.confirmed,
              wdId: 'wdA',
              day: 5,
              terminationStatus: AppStatus.approved),
          _app(
              status: AppStatus.confirmed,
              wdId: 'wdB',
              day: 5,
              type: '냉동분류',
              terminationStatus: AppStatus.approved),
        ],
        slots: {kTo: [_slot05()]},
      );
      expect(p.isRecruitable(kTo, d(5)), isTrue);
    });
  });

  group('HRP-3x 근무 식별 — wdId 축', () {
    test('HRP-30 같은 시간·같은 workType·다른 wdId → 형제가 산다', () {
      // 서버는 (uid, toId, slotId, wdId) 로 본다. 업무명·시간이 같아도
      // wdId 가 다르면 다른 근무다 — 여기서 막으면 정당한 지원이 사라진다.
      final slot = _slot(
        id: 'slot05',
        day: 5,
        wds: [
          _wd(wdId: 'wdA', type: '냉장분류'),
          _wd(wdId: 'wdB', type: '냉장분류'), // 같은 이름·같은 시간
        ],
      );
      final p = _build(
        apps: [_app(status: AppStatus.pending, wdId: 'wdA', day: 5)],
        slots: {kTo: [slot]},
      );
      expect(p.isRecruitable(kTo, d(5)), isTrue);
    });

    test('HRP-31 다른 slot 의 지원서는 그 날짜를 막지 않는다', () {
      final p = _build(
        apps: [
          _app(
              status: AppStatus.pending,
              wdId: 'wdA',
              day: 6, // 다른 날짜
              slotId: 'slot06'),
        ],
        slots: {kTo: [_slot05()]},
      );
      expect(p.isRecruitable(kTo, d(5)), isTrue);
    });
  });

  group('HRP-4x FULL · CLOSED', () {
    test('HRP-40 한 wdId FULL · 형제 OPEN → 0 금지', () {
      final p = _build(
        apps: [_app(status: AppStatus.pending, wdId: 'wdA', day: 5)],
        slots: {
          kTo: [
            _slot05(counts: const {
              'wdB': SlotWorkTypeCount(confirmedCount: 10),
            }),
          ],
        },
      );
      // wdA 는 관계로 막히고 wdB 는 정원이 찼다 → 그 날짜는 0 이 맞다.
      expect(p.isRecruitable(kTo, d(5)), isFalse);

      // 그러나 관계가 없는 쪽이 FULL 이어도 형제가 열려 있으면 살아야 한다.
      final q = _build(
        apps: const [],
        slots: {
          kTo: [
            _slot05(counts: const {
              'wdA': SlotWorkTypeCount(confirmedCount: 10),
            }),
          ],
        },
      );
      expect(q.isRecruitable(kTo, d(5)), isTrue,
          reason: '관계가 없으면 그 날짜는 그대로 모집 중이다 — 0 금지');
    });

    test('HRP-41 한 wdId CLOSED · 형제 OPEN → 0 금지', () {
      final p = _build(
        apps: [_app(status: AppStatus.pending, wdId: 'wdA', day: 5)],
        slots: {kTo: [_slot05(wdBClosed: false)]},
      );
      expect(p.isRecruitable(kTo, d(5)), isTrue);
    });

    test('HRP-42 모든 wdId unavailable → 0 허용', () {
      final p = _build(
        apps: [_app(status: AppStatus.pending, wdId: 'wdA', day: 5)],
        slots: {kTo: [_slot05(wdBClosed: true)]},
      );
      expect(p.isRecruitable(kTo, d(5)), isFalse);
    });

    test('HRP-43 슬롯 자체가 closed → 그 날짜만 제외', () {
      final p = _build(
        apps: [_app(status: AppStatus.pending, wdId: 'wdA', day: 5)],
        slots: {kTo: [_slot05(status: SlotStatus.closed)]},
      );
      expect(p.isRecruitable(kTo, d(5)), isFalse);
      expect(p.isRecruitable(kTo, d(6)), isTrue,
          reason: '다른 날짜는 유지된다');
    });
  });

  group('HRP-5x 모르는 것을 0 으로 바꾸지 않는다', () {
    test('HRP-50 슬롯을 읽지 못했다 → 그 날짜를 지우지 않는다', () {
      final p = _build(
        apps: [
          _app(status: AppStatus.pending, wdId: 'wdA', day: 5),
          _app(status: AppStatus.pending, wdId: 'wdB', day: 5, type: '냉동분류'),
        ],
        slots: const {}, // 로드 실패 / 아직 안 옴
      );
      expect(p.isRecruitable(kTo, d(5)), isTrue,
          reason: '못 읽은 것을 모집 없음으로 바꾸지 않는다 — 서버가 판정한다');
    });

    test('HRP-51 날짜 목록이 불완전하면 어느 날짜에서도 지우지 않는다', () {
      final p = _build(
        apps: [_app(status: AppStatus.pending, wdId: 'wdA', day: 5)],
        // totalSlots > dates.length → 기록되지 않은 슬롯이 있다
        to: _flexTo(totalSlots: 20),
      );
      expect(p.unknownDateToIds, contains(kTo));
      expect(p.isRecruitable(kTo, d(5)), isTrue);
      expect(p.isRecruitable(kTo, d(20)), isTrue);
    });

    test('HRP-52 dates 가 비어 있어도 지우지 않는다', () {
      final p = _build(
        apps: const [],
        to: _flexTo(dates: const [], totalSlots: 0),
      );
      expect(p.unknownDateToIds, contains(kTo));
    });
  });

  group('HRP-6x 공고 후보 관문', () {
    test('HRP-60 삭제·마감·만료 공고는 후보가 아니다', () {
      for (final s in [TOStatus.closed, TOStatus.expired, TOStatus.scheduled]) {
        final p = HomeRecruitableProjection.build(
          publishedTos: [
            TOModel(
              id: kTo,
              businessId: 'biz1',
              businessName: 'b',
              type: 'flex',
              title: 't',
              creatorUID: 'a',
              status: s,
              deadlineType: 'NONE',
              hoursBeforeStart: 0,
              workDetails: const [],
              totalRequired: 1,
              totalConfirmed: 0,
              totalPending: 0,
              isPublished: true,
              publishMode: 'immediate',
              slotDateKeys: kDates,
              totalSlots: 7,
              createdAt: DateTime(2026, 9, 1),
              statusUpdatedAt: DateTime(2026, 9, 1),
            ),
          ],
          myApplications: const [],
          today: d(1),
          cutoff: d(30),
        );
        expect(p.hasAnyDate(kTo), isFalse, reason: '$s 는 후보가 아니다');
      }
    });

    test('HRP-61 flex 는 공고 전체 정원으로 닫지 않는다', () {
      // 한 날짜가 찼다고 다른 날짜 모집까지 사라지면 안 된다 — R8-P9D.
      final p = HomeRecruitableProjection.build(
        publishedTos: [
          TOModel(
            id: kTo,
            businessId: 'biz1',
            businessName: 'b',
            type: 'flex',
            title: 't',
            creatorUID: 'a',
            status: TOStatus.active,
            deadlineType: 'NONE',
            hoursBeforeStart: 0,
            workDetails: const [],
            totalRequired: 10,
            totalConfirmed: 10, // 전체로는 꽉 찼다
            totalPending: 0,
            isPublished: true,
            publishMode: 'immediate',
            slotDateKeys: kDates,
            totalSlots: 7,
            createdAt: DateTime(2026, 9, 1),
            statusUpdatedAt: DateTime(2026, 9, 1),
          ),
        ],
        myApplications: const [],
        today: d(1),
        cutoff: d(30),
      );
      expect(p.hasAnyDate(kTo), isTrue);
    });
  });
}
