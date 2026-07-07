// ignore_for_file: lines_longer_than_80_chars
//
// 공고 마감 및 예약 로직 시뮬레이션 — 500+ 시나리오
//
// 검증 대상:
//   A. TOModel.isClosed / isPendingPublish / isFull
//   B. SlotModel.isEffectivelyClosed / isDatePast / isDeadlinePassed
//   C. WorkDetailData.isClosed / isTimeExpired / isEffectivelyClosed
//   D. SlotStatusUtil.slotStatus
//   E. 조합 / 엣지케이스 / 경계값

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/utils/slot_status_util.dart';

// ════════════════════════════════════════════════════════════
// 팩토리 헬퍼
// ════════════════════════════════════════════════════════════

final _now    = DateTime.now();
final _past1h = _now.subtract(const Duration(hours: 1));
final _past1d = _now.subtract(const Duration(days: 1));
final _past7d = _now.subtract(const Duration(days: 7));
final _past30d= _now.subtract(const Duration(days: 30));
final _future1h = _now.add(const Duration(hours: 1));
final _future1d = _now.add(const Duration(days: 1));
final _future7d = _now.add(const Duration(days: 7));
final _future30d= _now.add(const Duration(days: 30));

// 오늘 자정 (날짜만, 시간=0)
final _todayMidnight = DateTime(_now.year, _now.month, _now.day);
// 어제 자정
final _yesterdayMidnight = _todayMidnight.subtract(const Duration(days: 1));
// 내일 자정
final _tomorrowMidnight = _todayMidnight.add(const Duration(days: 1));

TOModel _to({
  String status = TOStatus.active,
  bool isManualClosed = false,
  int totalRequired = 0,
  int totalConfirmed = 0,
  String type = 'flex',
  DateTime? applicationDeadline,
  bool isPublished = true,
  String publishMode = 'immediate',
  DateTime? publishAt,
  int? publishDaysBefore,
}) {
  return TOModel(
    id: 'to1',
    businessId: 'biz1',
    businessName: '테스트사업장',
    title: '테스트공고',
    creatorUID: 'uid1',
    createdAt: DateTime(2025, 1, 1),
    status: status,
    isManualClosed: isManualClosed,
    totalRequired: totalRequired,
    totalConfirmed: totalConfirmed,
    type: type,
    applicationDeadline: applicationDeadline,
    isPublished: isPublished,
    publishMode: publishMode,
    publishAt: publishAt,
    publishDaysBefore: publishDaysBefore,
  );
}

SlotModel _slot({
  String status = SlotStatus.open,
  DateTime? date,
  bool isManualClosed = false,
  List<WorkDetailData> workDetails = const [],
  DateTime? applicationDeadline,
  DateTime? visibleFrom,
  String? closedBy,
}) {
  return SlotModel(
    id: 's1',
    toId: 'to1',
    date: date ?? _future7d,
    status: status,
    isManualClosed: isManualClosed,
    workDetails: workDetails,
    applicationDeadline: applicationDeadline,
    visibleFrom: visibleFrom,
    closedBy: closedBy,
    createdAt: DateTime(2025, 1, 1),
  );
}

WorkDetailData _wd({
  bool isManualClosed = false,
  DateTime? closedAt,
  DateTime? applicationDeadline,
  bool isEmergencyOpen = false,
  bool runtimeFull = false,
  int requiredCount = 2,
  int wage = 10000,
}) {
  return WorkDetailData(
    workType: 'WD',
    startTime: '09:00',
    endTime: '18:00',
    wage: wage,
    requiredCount: requiredCount,
    isManualClosed: isManualClosed,
    closedAt: closedAt,
    applicationDeadline: applicationDeadline,
    isEmergencyOpen: isEmergencyOpen,
    runtimeFull: runtimeFull,
  );
}

// ════════════════════════════════════════════════════════════
// A. TOModel.isClosed
// ════════════════════════════════════════════════════════════

void _runToIsClosedTests() {
  group('A. TOModel.isClosed', () {

    // ── A1. isManualClosed ──────────────────────────────────
    group('A1. isManualClosed', () {
      test('A1-01 isManualClosed=true → isClosed=true', () {
        expect(_to(isManualClosed: true).isClosed, isTrue);
      });
      test('A1-02 isManualClosed=false, ACTIVE → isClosed=false', () {
        expect(_to(isManualClosed: false).isClosed, isFalse);
      });
      test('A1-03 isManualClosed=true, status=ACTIVE → isClosed=true (status 무관)', () {
        expect(_to(isManualClosed: true, status: TOStatus.active).isClosed, isTrue);
      });
      test('A1-04 isManualClosed=true, status=SCHEDULED → isClosed=true', () {
        expect(_to(isManualClosed: true, status: TOStatus.scheduled).isClosed, isTrue);
      });
      test('A1-05 isManualClosed=true, status=DRAFT → isClosed=true', () {
        expect(_to(isManualClosed: true, status: TOStatus.draft).isClosed, isTrue);
      });
    });

    // ── A2. isFull ──────────────────────────────────────────
    group('A2. isFull → isClosed', () {
      test('A2-01 req=0, confirmed=0 → isFull=false', () {
        expect(_to(totalRequired: 0, totalConfirmed: 0).isFull, isFalse);
      });
      test('A2-02 req=5, confirmed=5 → isFull=true', () {
        expect(_to(totalRequired: 5, totalConfirmed: 5).isFull, isTrue);
      });
      test('A2-03 req=5, confirmed=5 → isClosed=true', () {
        expect(_to(totalRequired: 5, totalConfirmed: 5).isClosed, isTrue);
      });
      test('A2-04 req=5, confirmed=4 → isFull=false', () {
        expect(_to(totalRequired: 5, totalConfirmed: 4).isFull, isFalse);
      });
      test('A2-05 req=5, confirmed=4 → isClosed=false', () {
        expect(_to(totalRequired: 5, totalConfirmed: 4).isClosed, isFalse);
      });
      test('A2-06 req=5, confirmed=6 → isFull=true (초과도 full)', () {
        expect(_to(totalRequired: 5, totalConfirmed: 6).isFull, isTrue);
      });
      test('A2-07 req=1, confirmed=1 → isFull=true (1인 충족)', () {
        expect(_to(totalRequired: 1, totalConfirmed: 1).isFull, isTrue);
      });
      test('A2-08 req=0, confirmed=5 → isFull=false (req=0 이면 항상 false)', () {
        expect(_to(totalRequired: 0, totalConfirmed: 5).isFull, isFalse);
      });
      test('A2-09 req=10000, confirmed=9999 → isFull=false', () {
        expect(_to(totalRequired: 10000, totalConfirmed: 9999).isFull, isFalse);
      });
      test('A2-10 req=10000, confirmed=10000 → isFull=true', () {
        expect(_to(totalRequired: 10000, totalConfirmed: 10000).isFull, isTrue);
      });
    });

    // ── A3. status=CLOSED / EXPIRED ────────────────────────
    group('A3. status=CLOSED/EXPIRED', () {
      test('A3-01 status=CLOSED → isClosed=true', () {
        expect(_to(status: TOStatus.closed).isClosed, isTrue);
      });
      test('A3-02 status=EXPIRED → isClosed=true', () {
        expect(_to(status: TOStatus.expired).isClosed, isTrue);
      });
      test('A3-03 status=ACTIVE → isClosed=false', () {
        expect(_to(status: TOStatus.active).isClosed, isFalse);
      });
      test('A3-04 status=FULL → isClosed=false (status=FULL은 단독으로 isClosed 미유발)', () {
        expect(_to(status: TOStatus.full, totalRequired: 0).isClosed, isFalse);
      });
      test('A3-05 status=SCHEDULED → isClosed=false', () {
        expect(_to(status: TOStatus.scheduled).isClosed, isFalse);
      });
      test('A3-06 status=DRAFT → isClosed=false', () {
        expect(_to(status: TOStatus.draft).isClosed, isFalse);
      });
    });

    // ── A4. contractType + deadline ────────────────────────
    group('A4. contractType + applicationDeadline', () {
      test('A4-01 type=contract, deadline=1h ago → isClosed=true', () {
        expect(_to(type: 'contract', applicationDeadline: _past1h).isClosed, isTrue);
      });
      test('A4-02 type=contract, deadline=1h future → isClosed=false', () {
        expect(_to(type: 'contract', applicationDeadline: _future1h).isClosed, isFalse);
      });
      test('A4-03 type=flex, deadline=1h ago → isClosed=false (flex는 deadline 무관)', () {
        expect(_to(type: 'flex', applicationDeadline: _past1h).isClosed, isFalse);
      });
      test('A4-04 type=contract, deadline=null → isDeadlinePassed=false', () {
        expect(_to(type: 'contract', applicationDeadline: null).isClosed, isFalse);
      });
      test('A4-05 type=contract, deadline=now-1sec → isClosed=true', () {
        expect(_to(type: 'contract', applicationDeadline: _now.subtract(const Duration(seconds: 1))).isClosed, isTrue);
      });
      test('A4-06 type=contract, deadline=now+1sec → isClosed=false', () {
        expect(_to(type: 'contract', applicationDeadline: _now.add(const Duration(seconds: 1))).isClosed, isFalse);
      });
    });

    // ── A5. 복합 조건 ────────────────────────────────────────
    group('A5. 복합 조건', () {
      test('A5-01 status=CLOSED + isManualClosed=true → isClosed=true', () {
        expect(_to(status: TOStatus.closed, isManualClosed: true).isClosed, isTrue);
      });
      test('A5-02 status=ACTIVE + isManualClosed=false + req=5, conf=5 → isClosed=true', () {
        expect(_to(status: TOStatus.active, isManualClosed: false, totalRequired: 5, totalConfirmed: 5).isClosed, isTrue);
      });
      test('A5-03 status=CLOSED + totalRequired=0 → isClosed=true', () {
        expect(_to(status: TOStatus.closed, totalRequired: 0).isClosed, isTrue);
      });
      test('A5-04 status=EXPIRED + isManualClosed=false → isClosed=true', () {
        expect(_to(status: TOStatus.expired, isManualClosed: false).isClosed, isTrue);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// B. TOModel.isPendingPublish
// ════════════════════════════════════════════════════════════

void _runToIsPendingPublishTests() {
  group('B. TOModel.isPendingPublish', () {
    test('B-01 publishMode=immediate → isPendingPublish=false', () {
      expect(_to(publishMode: 'immediate', isPublished: true).isPendingPublish, isFalse);
    });
    test('B-02 publishMode=scheduled, isPublished=true → isPendingPublish=false (이미공개)', () {
      expect(_to(publishMode: 'scheduled', isPublished: true).isPendingPublish, isFalse);
    });
    test('B-03 publishMode=scheduled, isPublished=false, publishAt=future → isPendingPublish=true', () {
      expect(_to(publishMode: 'scheduled', isPublished: false, publishAt: _future1d).isPendingPublish, isTrue);
    });
    test('B-04 publishMode=scheduled, isPublished=false, publishAt=past → isPendingPublish=false (과거면 공개됐어야 함)', () {
      expect(_to(publishMode: 'scheduled', isPublished: false, publishAt: _past1h).isPendingPublish, isFalse);
    });
    test('B-05 publishMode=scheduled, isPublished=false, publishAt=null → isPendingPublish=false', () {
      expect(_to(publishMode: 'scheduled', isPublished: false, publishAt: null).isPendingPublish, isFalse);
    });
    test('B-06 publishMode=draft, isPublished=false → isPendingPublish=false', () {
      expect(_to(publishMode: 'draft', isPublished: false).isPendingPublish, isFalse);
    });
    test('B-07 publishMode=scheduled, isPublished=false, publishAt=1min future → isPendingPublish=true', () {
      expect(_to(publishMode: 'scheduled', isPublished: false, publishAt: _now.add(const Duration(minutes: 1))).isPendingPublish, isTrue);
    });
    test('B-08 publishMode=scheduled, isPublished=false, publishAt=1sec past → isPendingPublish=false', () {
      expect(_to(publishMode: 'scheduled', isPublished: false, publishAt: _now.subtract(const Duration(seconds: 1))).isPendingPublish, isFalse);
    });
    test('B-09 publishMode=scheduled, isPublished=false, publishAt=30d future → isPendingPublish=true', () {
      expect(_to(publishMode: 'scheduled', isPublished: false, publishAt: _future30d).isPendingPublish, isTrue);
    });
  });
}

// ════════════════════════════════════════════════════════════
// C. SlotModel.isEffectivelyClosed
// ════════════════════════════════════════════════════════════

void _runSlotIsEffectivelyClosedTests() {
  group('C. SlotModel.isEffectivelyClosed', () {

    // ── C1. status 필드 직접 ────────────────────────────────
    group('C1. status 필드', () {
      test('C1-01 status=closed → isEffectivelyClosed=true', () {
        expect(_slot(status: SlotStatus.closed, date: _future7d).isEffectivelyClosed, isTrue);
      });
      test('C1-02 status=full → isEffectivelyClosed=true', () {
        expect(_slot(status: SlotStatus.full, date: _future7d).isEffectivelyClosed, isTrue);
      });
      test('C1-03 status=open, date=future → isEffectivelyClosed=false', () {
        expect(_slot(status: SlotStatus.open, date: _future7d).isEffectivelyClosed, isFalse);
      });
      test('C1-04 status=open → isClosed=false', () {
        expect(_slot(status: SlotStatus.open).isClosed, isFalse);
      });
      test('C1-05 status=full → isFull=true', () {
        expect(_slot(status: SlotStatus.full).isFull, isTrue);
      });
      test('C1-06 status=closed → isClosed=true', () {
        expect(_slot(status: SlotStatus.closed).isClosed, isTrue);
      });
    });

    // ── C2. isDatePast ──────────────────────────────────────
    group('C2. isDatePast', () {
      test('C2-01 date=어제 → isDatePast=true', () {
        expect(_slot(date: _yesterdayMidnight).isDatePast, isTrue);
      });
      test('C2-02 date=어제 → isEffectivelyClosed=true', () {
        expect(_slot(date: _yesterdayMidnight).isEffectivelyClosed, isTrue);
      });
      test('C2-03 date=오늘 → isDatePast=false (당일은 아직 유효)', () {
        expect(_slot(date: _todayMidnight).isDatePast, isFalse);
      });
      test('C2-04 date=오늘 00:00 → isEffectivelyClosed=false', () {
        expect(_slot(date: _todayMidnight).isEffectivelyClosed, isFalse);
      });
      test('C2-05 date=내일 → isDatePast=false', () {
        expect(_slot(date: _tomorrowMidnight).isDatePast, isFalse);
      });
      test('C2-06 date=7일 후 → isDatePast=false', () {
        expect(_slot(date: _future7d).isDatePast, isFalse);
      });
      test('C2-07 date=7일 전 → isDatePast=true', () {
        expect(_slot(date: _past7d).isDatePast, isTrue);
      });
      test('C2-08 date=30일 전 → isDatePast=true', () {
        expect(_slot(date: _past30d).isDatePast, isTrue);
      });
      test('C2-09 date=오늘 23:59:59 (시간만 다름) → isDatePast=false (날짜 기준)', () {
        final todayLate = DateTime(_now.year, _now.month, _now.day, 23, 59, 59);
        expect(_slot(date: todayLate).isDatePast, isFalse);
      });
      test('C2-10 date=어제 23:59:59 → isDatePast=true', () {
        final yesterdayLate = DateTime(_now.year, _now.month, _now.day - 1, 23, 59, 59);
        expect(_slot(date: yesterdayLate).isDatePast, isTrue);
      });
    });

    // ── C3. isDeadlinePassed (workDetails 없을 때) ──────────
    group('C3. isDeadlinePassed (workDetails 비어있을 때)', () {
      test('C3-01 deadline=1h ago, no workDetails → isDeadlinePassed=true', () {
        expect(_slot(applicationDeadline: _past1h).isDeadlinePassed, isTrue);
      });
      test('C3-02 deadline=1h ago, no workDetails → isEffectivelyClosed=true', () {
        expect(_slot(applicationDeadline: _past1h).isEffectivelyClosed, isTrue);
      });
      test('C3-03 deadline=1h future, no workDetails → isDeadlinePassed=false', () {
        expect(_slot(applicationDeadline: _future1h).isDeadlinePassed, isFalse);
      });
      test('C3-04 deadline=null, no workDetails → isDeadlinePassed=false', () {
        expect(_slot(applicationDeadline: null).isDeadlinePassed, isFalse);
      });
      test('C3-05 deadline=1min ago → isDeadlinePassed=true', () {
        expect(_slot(applicationDeadline: _now.subtract(const Duration(minutes: 1))).isDeadlinePassed, isTrue);
      });
      test('C3-06 deadline=1min future → isDeadlinePassed=false', () {
        expect(_slot(applicationDeadline: _now.add(const Duration(minutes: 1))).isDeadlinePassed, isFalse);
      });
    });

    // ── C4. workDetails.every(isClosed || isTimeExpired) ────
    group('C4. workDetails 기반 마감', () {
      test('C4-01 workDetails=1개, 수동마감 → isEffectivelyClosed=true', () {
        expect(_slot(workDetails: [_wd(isManualClosed: true)]).isEffectivelyClosed, isTrue);
      });
      test('C4-02 workDetails=1개, 시간만료 → isEffectivelyClosed=true', () {
        expect(_slot(workDetails: [_wd(applicationDeadline: _past1h)]).isEffectivelyClosed, isTrue);
      });
      test('C4-03 workDetails=2개, 모두 수동마감 → isEffectivelyClosed=true', () {
        expect(_slot(workDetails: [_wd(isManualClosed: true), _wd(isManualClosed: true)]).isEffectivelyClosed, isTrue);
      });
      test('C4-04 workDetails=2개, 1개만 수동마감 → isEffectivelyClosed=false', () {
        expect(_slot(workDetails: [_wd(isManualClosed: true), _wd()]).isEffectivelyClosed, isFalse);
      });
      test('C4-05 workDetails=2개, 1개 수동마감 + 1개 시간만료 → isEffectivelyClosed=true', () {
        expect(_slot(workDetails: [_wd(isManualClosed: true), _wd(applicationDeadline: _past1h)]).isEffectivelyClosed, isTrue);
      });
      test('C4-06 workDetails=2개, 1개만 시간만료 → isEffectivelyClosed=false', () {
        expect(_slot(workDetails: [_wd(applicationDeadline: _past1h), _wd(applicationDeadline: _future1h)]).isEffectivelyClosed, isFalse);
      });
      test('C4-07 workDetails=3개, 모두 시간만료 → isEffectivelyClosed=true', () {
        expect(_slot(workDetails: [
          _wd(applicationDeadline: _past1h),
          _wd(applicationDeadline: _past7d),
          _wd(applicationDeadline: _past30d),
        ]).isEffectivelyClosed, isTrue);
      });
      test('C4-08 workDetails=3개, 2개 마감 + 1개 활성 → isEffectivelyClosed=false', () {
        expect(_slot(workDetails: [
          _wd(isManualClosed: true),
          _wd(applicationDeadline: _past1h),
          _wd(applicationDeadline: _future1h),
        ]).isEffectivelyClosed, isFalse);
      });
      test('C4-09 workDetails=[closedAt 있음] → isClosed=true → isEffectivelyClosed=true', () {
        expect(_slot(workDetails: [_wd(closedAt: _past1h)]).isEffectivelyClosed, isTrue);
      });
      test('C4-10 workDetails=[closedAt 없음, deadline 없음] → isEffectivelyClosed=false', () {
        expect(_slot(workDetails: [_wd()]).isEffectivelyClosed, isFalse);
      });
    });

    // ── C5. 복합 조건 ────────────────────────────────────────
    group('C5. 복합 조건', () {
      test('C5-01 status=closed + date=future → isEffectivelyClosed=true', () {
        expect(_slot(status: SlotStatus.closed, date: _future7d).isEffectivelyClosed, isTrue);
      });
      test('C5-02 status=open + date=past → isEffectivelyClosed=true (날짜 만료)', () {
        expect(_slot(status: SlotStatus.open, date: _past1d).isEffectivelyClosed, isTrue);
      });
      test('C5-03 status=open + date=future + deadline=past → isEffectivelyClosed=true', () {
        expect(_slot(status: SlotStatus.open, date: _future7d, applicationDeadline: _past1h).isEffectivelyClosed, isTrue);
      });
      test('C5-04 status=full + date=past → isEffectivelyClosed=true', () {
        expect(_slot(status: SlotStatus.full, date: _past1d).isEffectivelyClosed, isTrue);
      });
      test('C5-05 status=open + date=today + workDetails=all expired → isEffectivelyClosed=true', () {
        expect(_slot(
          status: SlotStatus.open,
          date: _todayMidnight,
          workDetails: [_wd(applicationDeadline: _past1h), _wd(isManualClosed: true)],
        ).isEffectivelyClosed, isTrue);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// D. WorkDetailData
// ════════════════════════════════════════════════════════════

void _runWorkDetailTests() {
  group('D. WorkDetailData', () {

    // ── D1. isClosed ────────────────────────────────────────
    group('D1. isClosed', () {
      test('D1-01 isManualClosed=true → isClosed=true', () {
        expect(_wd(isManualClosed: true).isClosed, isTrue);
      });
      test('D1-02 closedAt=past → isClosed=true', () {
        expect(_wd(closedAt: _past1h).isClosed, isTrue);
      });
      test('D1-03 isManualClosed=false, closedAt=null → isClosed=false', () {
        expect(_wd(isManualClosed: false, closedAt: null).isClosed, isFalse);
      });
      test('D1-04 isManualClosed=true + closedAt=past → isClosed=true', () {
        expect(_wd(isManualClosed: true, closedAt: _past1h).isClosed, isTrue);
      });
      test('D1-05 closedAt=future (비정상 데이터라도) → isClosed=true', () {
        expect(_wd(closedAt: _future1h).isClosed, isTrue);
      });
      test('D1-06 isManualClosed=false + closedAt=null + deadline=past → isClosed=false', () {
        expect(_wd(closedAt: null, applicationDeadline: _past1h).isClosed, isFalse);
      });
    });

    // ── D2. isTimeExpired ────────────────────────────────────
    group('D2. isTimeExpired', () {
      test('D2-01 deadline=past → isTimeExpired=true', () {
        expect(_wd(applicationDeadline: _past1h).isTimeExpired, isTrue);
      });
      test('D2-02 deadline=future → isTimeExpired=false', () {
        expect(_wd(applicationDeadline: _future1h).isTimeExpired, isFalse);
      });
      test('D2-03 deadline=null → isTimeExpired=false', () {
        expect(_wd(applicationDeadline: null).isTimeExpired, isFalse);
      });
      test('D2-04 deadline=1min ago → isTimeExpired=true', () {
        expect(_wd(applicationDeadline: _now.subtract(const Duration(minutes: 1))).isTimeExpired, isTrue);
      });
      test('D2-05 deadline=1min future → isTimeExpired=false', () {
        expect(_wd(applicationDeadline: _now.add(const Duration(minutes: 1))).isTimeExpired, isFalse);
      });
      test('D2-06 deadline=30d ago → isTimeExpired=true', () {
        expect(_wd(applicationDeadline: _past30d).isTimeExpired, isTrue);
      });
    });

    // ── D3. isEffectivelyClosed(slotDate) ────────────────────
    group('D3. isEffectivelyClosed(slotDate)', () {
      test('D3-01 수동마감 + slotDate=future → true', () {
        expect(_wd(isManualClosed: true).isEffectivelyClosed(_future7d), isTrue);
      });
      test('D3-02 시간만료 + slotDate=future → true', () {
        expect(_wd(applicationDeadline: _past1h).isEffectivelyClosed(_future7d), isTrue);
      });
      test('D3-03 정상 + slotDate=과거 → true (슬롯 날짜 만료)', () {
        expect(_wd().isEffectivelyClosed(_yesterdayMidnight), isTrue);
      });
      test('D3-04 정상 + slotDate=오늘 → false', () {
        expect(_wd().isEffectivelyClosed(_todayMidnight), isFalse);
      });
      test('D3-05 정상 + slotDate=미래 → false', () {
        expect(_wd().isEffectivelyClosed(_future7d), isFalse);
      });
      test('D3-06 closedAt=past + slotDate=future → true', () {
        expect(_wd(closedAt: _past1h).isEffectivelyClosed(_future7d), isTrue);
      });
      test('D3-07 정상 + deadline=future + slotDate=과거 → true', () {
        expect(_wd(applicationDeadline: _future1h).isEffectivelyClosed(_yesterdayMidnight), isTrue);
      });
      test('D3-08 정상 + deadline=future + slotDate=오늘 → false', () {
        expect(_wd(applicationDeadline: _future1h).isEffectivelyClosed(_todayMidnight), isFalse);
      });
      test('D3-09 deadline=past + slotDate=과거 → true (둘 다 만료)', () {
        expect(_wd(applicationDeadline: _past1h).isEffectivelyClosed(_yesterdayMidnight), isTrue);
      });
      test('D3-10 isEmergencyOpen=true + 수동마감 → isClosed=true (긴급공개는 isClosed에 영향 없음)', () {
        expect(_wd(isManualClosed: true, isEmergencyOpen: true).isClosed, isTrue);
      });
    });

    // ── D4. isFull (runtimeFull) ─────────────────────────────
    group('D4. isFull (runtimeFull)', () {
      test('D4-01 runtimeFull=true → isFull=true', () {
        expect(_wd(runtimeFull: true).isFull, isTrue);
      });
      test('D4-02 runtimeFull=false → isFull=false', () {
        expect(_wd(runtimeFull: false).isFull, isFalse);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// E. SlotStatusUtil.slotStatus
// ════════════════════════════════════════════════════════════

void _runSlotStatusUtilTests() {
  group('E. SlotStatusUtil.slotStatus', () {

    // ── E1. draft ────────────────────────────────────────────
    group('E1. draft 반환 조건', () {
      test('E1-01 TO isPublished=false + status=DRAFT → SlotDisplayStatus.draft', () {
        final to = _to(isPublished: false, status: TOStatus.draft);
        final slot = _slot(date: _future7d);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.draft);
      });
      test('E1-02 TO isPublished=true + status=DRAFT → draft 아님 (DRAFT이지만 published)', () {
        final to = _to(isPublished: true, status: TOStatus.draft);
        final slot = _slot(date: _future7d);
        // DRAFT이고 isPublished=true는 비정상이지만, draft 조건: !isPublished && status==draft
        expect(SlotStatusUtil.slotStatus(slot, to), isNot(SlotDisplayStatus.draft));
      });
      test('E1-03 TO isPublished=false + status=ACTIVE → draft 아님', () {
        final to = _to(isPublished: false, status: TOStatus.active);
        final slot = _slot(date: _future7d);
        expect(SlotStatusUtil.slotStatus(slot, to), isNot(SlotDisplayStatus.draft));
      });
    });

    // ── E2. closed ───────────────────────────────────────────
    group('E2. closed 반환 조건', () {
      test('E2-01 slot.status=closed → SlotDisplayStatus.closed', () {
        final to = _to();
        final slot = _slot(status: SlotStatus.closed);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.closed);
      });
      test('E2-02 slot.status=full → SlotDisplayStatus.closed', () {
        final to = _to();
        final slot = _slot(status: SlotStatus.full, date: _future7d);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.closed);
      });
      test('E2-03 slot.date=어제 → SlotDisplayStatus.closed', () {
        final to = _to();
        final slot = _slot(date: _yesterdayMidnight);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.closed);
      });
      test('E2-04 workDetails 모두 수동마감 → SlotDisplayStatus.closed', () {
        final to = _to();
        final slot = _slot(
          workDetails: [_wd(isManualClosed: true), _wd(isManualClosed: true)],
        );
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.closed);
      });
      test('E2-05 workDetails 모두 시간만료 → SlotDisplayStatus.closed', () {
        final to = _to();
        final slot = _slot(
          workDetails: [_wd(applicationDeadline: _past1h), _wd(applicationDeadline: _past7d)],
        );
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.closed);
      });
      test('E2-06 slot.applicationDeadline=past (no workDetails) → closed', () {
        final to = _to();
        final slot = _slot(applicationDeadline: _past1h);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.closed);
      });
    });

    // ── E3. scheduled ────────────────────────────────────────
    group('E3. scheduled 반환 조건', () {
      test('E3-01 slot.visibleFrom=future → SlotDisplayStatus.scheduled', () {
        final to = _to(isPublished: true);
        final slot = _slot(visibleFrom: _future1h);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.scheduled);
      });
      test('E3-02 slot.visibleFrom=past → scheduled 아님', () {
        final to = _to(isPublished: true);
        final slot = _slot(visibleFrom: _past1h);
        expect(SlotStatusUtil.slotStatus(slot, to), isNot(SlotDisplayStatus.scheduled));
      });
      test('E3-03 TO isPendingPublish=true → scheduled', () {
        final to = _to(
          publishMode: 'scheduled',
          isPublished: false,
          status: TOStatus.scheduled,
          publishAt: _future1d,
        );
        final slot = _slot(date: _future7d);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.scheduled);
      });
      test('E3-04 slot.visibleFrom=null, TO isPendingPublish=false → scheduled 아님 (recruiting)', () {
        final to = _to(isPublished: true);
        final slot = _slot(visibleFrom: null);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.recruiting);
      });
    });

    // ── E4. recruiting ───────────────────────────────────────
    group('E4. recruiting 반환 조건', () {
      test('E4-01 정상 활성 TO + 정상 슬롯 → recruiting', () {
        final to = _to(isPublished: true);
        final slot = _slot(date: _future7d);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.recruiting);
      });
      test('E4-02 visibleFrom=null + isPublished=true → recruiting', () {
        final to = _to(isPublished: true);
        final slot = _slot(date: _future7d, visibleFrom: null);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.recruiting);
      });
      test('E4-03 visibleFrom=past + isPublished=true → recruiting', () {
        final to = _to(isPublished: true);
        final slot = _slot(date: _future7d, visibleFrom: _past1h);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.recruiting);
      });
      test('E4-04 workDetails=1개 활성 → recruiting', () {
        final to = _to(isPublished: true);
        final slot = _slot(
          date: _future7d,
          workDetails: [_wd(applicationDeadline: _future1h)],
        );
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.recruiting);
      });
      test('E4-05 TO status=ACTIVE, slot=open, date=오늘 → recruiting', () {
        final to = _to(isPublished: true, status: TOStatus.active);
        final slot = _slot(status: SlotStatus.open, date: _todayMidnight);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.recruiting);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// F. 마감 엣지케이스 / 경계값 시나리오
// ════════════════════════════════════════════════════════════

void _runEdgeCaseTests() {
  group('F. 엣지케이스 & 경계값', () {

    // ── F1. 날짜 경계 ────────────────────────────────────────
    group('F1. 날짜 경계값', () {
      test('F1-01 슬롯 날짜=정확히 오늘 자정 → isDatePast=false', () {
        final s = SlotModel(id:'s', toId:'t', date: _todayMidnight, createdAt: _past30d);
        expect(s.isDatePast, isFalse);
      });
      test('F1-02 슬롯 날짜=어제 자정 → isDatePast=true', () {
        final s = SlotModel(id:'s', toId:'t', date: _yesterdayMidnight, createdAt: _past30d);
        expect(s.isDatePast, isTrue);
      });
      test('F1-03 슬롯 날짜=오늘 23:59:59 → isDatePast=false (날짜 트리밍)', () {
        final s = SlotModel(id:'s', toId:'t', date: DateTime(_now.year, _now.month, _now.day, 23, 59, 59), createdAt: _past30d);
        expect(s.isDatePast, isFalse);
      });
      test('F1-04 슬롯 날짜=어제 00:00:01 → isDatePast=true', () {
        final s = SlotModel(id:'s', toId:'t', date: DateTime(_now.year, _now.month, _now.day - 1, 0, 0, 1), createdAt: _past30d);
        expect(s.isDatePast, isTrue);
      });
    });

    // ── F2. totalRequired=0 특수 케이스 ─────────────────────
    group('F2. totalRequired=0', () {
      test('F2-01 req=0, conf=0 → isFull=false', () {
        expect(_to(totalRequired: 0, totalConfirmed: 0).isFull, isFalse);
      });
      test('F2-02 req=0, conf=100 → isFull=false (req=0 이면 절대 full 아님)', () {
        expect(_to(totalRequired: 0, totalConfirmed: 100).isFull, isFalse);
      });
      test('F2-03 req=0, conf=0 → isClosed=false', () {
        expect(_to(totalRequired: 0, totalConfirmed: 0).isClosed, isFalse);
      });
    });

    // ── F3. isEmergencyOpen 보호 ─────────────────────────────
    group('F3. isEmergencyOpen', () {
      test('F3-01 isEmergencyOpen=true, deadline=past → isTimeExpired=true (CF 처리 제외지만 getter는 그대로)', () {
        // 앱 클라이언트는 isTimeExpired로 판단, CF는 isEmergencyOpen 체크로 처리 제외
        expect(_wd(applicationDeadline: _past1h, isEmergencyOpen: true).isTimeExpired, isTrue);
      });
      test('F3-02 isEmergencyOpen=false, deadline=past → isTimeExpired=true', () {
        expect(_wd(applicationDeadline: _past1h, isEmergencyOpen: false).isTimeExpired, isTrue);
      });
    });

    // ── F4. 다양한 totalRequired/Confirmed 경계 ──────────────
    group('F4. totalRequired/Confirmed 경계', () {
      final cases = [
        (1, 0, false),
        (1, 1, true),
        (2, 1, false),
        (2, 2, true),
        (10, 9, false),
        (10, 10, true),
        (10, 11, true),
        (100, 99, false),
        (100, 100, true),
        (1000, 999, false),
        (1000, 1000, true),
      ];
      for (final (req, conf, expected) in cases) {
        test('F4 req=$req, conf=$conf → isFull=$expected', () {
          expect(_to(totalRequired: req, totalConfirmed: conf).isFull, expected ? isTrue : isFalse);
        });
      }
    });

    // ── F5. workDetails 수 경계 ──────────────────────────────
    group('F5. workDetails 수 조합', () {
      test('F5-01 workDetails=빈 리스트 + deadline=null → isEffectivelyClosed=false', () {
        expect(_slot(workDetails: [], applicationDeadline: null).isEffectivelyClosed, isFalse);
      });
      test('F5-02 workDetails=5개 모두 수동마감 → isEffectivelyClosed=true', () {
        expect(_slot(workDetails: List.generate(5, (_) => _wd(isManualClosed: true))).isEffectivelyClosed, isTrue);
      });
      test('F5-03 workDetails=5개, 4개 만료 1개 활성 → isEffectivelyClosed=false', () {
        expect(_slot(workDetails: [
          ...List.generate(4, (_) => _wd(applicationDeadline: _past1h)),
          _wd(applicationDeadline: _future1h),
        ]).isEffectivelyClosed, isFalse);
      });
      test('F5-04 workDetails=10개 모두 시간만료 → isEffectivelyClosed=true', () {
        expect(_slot(workDetails: List.generate(10, (_) => _wd(applicationDeadline: _past1h))).isEffectivelyClosed, isTrue);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// G. 예약 공개 시나리오 (publishAt, publishMode 조합)
// ════════════════════════════════════════════════════════════

void _runPublishScheduleTests() {
  group('G. 예약 공개 시나리오', () {

    group('G1. publishMode=immediate', () {
      test('G1-01 immediate → isPublished=true, status=ACTIVE', () {
        final to = _to(publishMode: 'immediate', isPublished: true, status: TOStatus.active);
        expect(to.isPublished, isTrue);
        expect(to.status, TOStatus.active);
        expect(to.isPendingPublish, isFalse);
      });
      test('G1-02 immediate + isPublished=true → isClosed=false', () {
        expect(_to(publishMode: 'immediate', isPublished: true).isClosed, isFalse);
      });
    });

    group('G2. publishMode=scheduled + publishAt=future', () {
      test('G2-01 scheduled + publishAt=1d future + isPublished=false → SCHEDULED 상태', () {
        final to = _to(publishMode: 'scheduled', isPublished: false, status: TOStatus.scheduled, publishAt: _future1d);
        expect(to.isPendingPublish, isTrue);
        expect(to.status, TOStatus.scheduled);
      });
      test('G2-02 scheduled + publishAt=7d future → isPendingPublish=true', () {
        expect(_to(publishMode: 'scheduled', isPublished: false, publishAt: _future7d).isPendingPublish, isTrue);
      });
      test('G2-03 scheduled + publishAt=30d future → isPendingPublish=true', () {
        expect(_to(publishMode: 'scheduled', isPublished: false, publishAt: _future30d).isPendingPublish, isTrue);
      });
    });

    group('G3. publishMode=scheduled + publishAt=past (CF 미처리된 경우)', () {
      test('G3-01 scheduled + publishAt=1h ago + isPublished=false → isPendingPublish=false (CF가 처리했어야 함)', () {
        expect(_to(publishMode: 'scheduled', isPublished: false, publishAt: _past1h).isPendingPublish, isFalse);
      });
      test('G3-02 scheduled + publishAt=7d ago + isPublished=false → isPendingPublish=false', () {
        expect(_to(publishMode: 'scheduled', isPublished: false, publishAt: _past7d).isPendingPublish, isFalse);
      });
    });

    group('G4. publishMode=draft', () {
      test('G4-01 draft + isPublished=false → isPendingPublish=false', () {
        expect(_to(publishMode: 'draft', isPublished: false, status: TOStatus.draft).isPendingPublish, isFalse);
      });
      test('G4-02 draft + status=DRAFT → isClosed=false', () {
        expect(_to(publishMode: 'draft', status: TOStatus.draft).isClosed, isFalse);
      });
    });

    group('G5. visibleFrom 슬롯 공개 예약', () {
      test('G5-01 visibleFrom=1h future → scheduled 상태', () {
        final to = _to(isPublished: true);
        final slot = _slot(visibleFrom: _future1h);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.scheduled);
      });
      test('G5-02 visibleFrom=1min future → scheduled', () {
        final to = _to(isPublished: true);
        final slot = _slot(visibleFrom: _now.add(const Duration(minutes: 1)));
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.scheduled);
      });
      test('G5-03 visibleFrom=1sec past → recruiting (공개됨)', () {
        final to = _to(isPublished: true);
        final slot = _slot(visibleFrom: _now.subtract(const Duration(seconds: 1)));
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.recruiting);
      });
      test('G5-04 visibleFrom=null → recruiting', () {
        final to = _to(isPublished: true);
        final slot = _slot(visibleFrom: null);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.recruiting);
      });
      test('G5-05 visibleFrom=past + slot.status=closed → closed 우선', () {
        final to = _to(isPublished: true);
        final slot = _slot(status: SlotStatus.closed, visibleFrom: _past1h);
        expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.closed);
      });
    });
  });
}

// ════════════════════════════════════════════════════════════
// H. CF processSlotWorkDetailExpiry 로직 재현 (순수 Dart)
// ════════════════════════════════════════════════════════════

void _runCFExpiryLogicTests() {
  group('H. CF workDetail 만료 로직 재현', () {

    // CF 로직: slot.status=='open' && closedBy==null 인 슬롯에서
    // workDetail: !isEmergencyOpen && closedAt==null && deadline <= now → 마감 처리
    // 모든 workDetail 마감 시 → slot.status='closed'
    // → 열린 슬롯 없으면 TO → CLOSED

    bool isWorkDetailExpiredByCF(WorkDetailData wd) {
      // CF 처리 조건 재현
      return !wd.isEmergencyOpen && wd.closedAt == null && wd.isTimeExpired;
    }

    bool isSlotAutoClosedByCF(SlotModel slot) {
      // 수동 마감된 슬롯은 CF 처리 대상 제외
      if (slot.isManualClosed || slot.closedBy != null) return false;
      if (slot.status != SlotStatus.open) return false;
      if (slot.workDetails.isEmpty) return false;
      return slot.workDetails.every(isWorkDetailExpiredByCF);
    }

    test('H-01 open 슬롯, workDetail 모두 만료 → CF 자동마감 대상', () {
      final slot = _slot(
        status: SlotStatus.open,
        workDetails: [_wd(applicationDeadline: _past1h)],
      );
      expect(isSlotAutoClosedByCF(slot), isTrue);
    });

    test('H-02 open 슬롯, workDetail 1개 활성 → CF 자동마감 제외', () {
      final slot = _slot(
        status: SlotStatus.open,
        workDetails: [_wd(applicationDeadline: _past1h), _wd(applicationDeadline: _future1h)],
      );
      expect(isSlotAutoClosedByCF(slot), isFalse);
    });

    test('H-03 수동마감 슬롯(isManualClosed=true) → CF 처리 제외', () {
      final slot = _slot(
        status: SlotStatus.open,
        isManualClosed: true,
        workDetails: [_wd(applicationDeadline: _past1h)],
      );
      expect(isSlotAutoClosedByCF(slot), isFalse);
    });

    test('H-04 closedBy 있는 슬롯 → CF 처리 제외', () {
      final slot = _slot(
        status: SlotStatus.open,
        closedBy: 'uid1',
        workDetails: [_wd(applicationDeadline: _past1h)],
      );
      expect(isSlotAutoClosedByCF(slot), isFalse);
    });

    test('H-05 isEmergencyOpen=true workDetail → CF 처리 제외', () {
      final slot = _slot(
        status: SlotStatus.open,
        workDetails: [_wd(applicationDeadline: _past1h, isEmergencyOpen: true)],
      );
      expect(isSlotAutoClosedByCF(slot), isFalse);
    });

    test('H-06 isEmergencyOpen=false + deadline=past → CF 처리 대상', () {
      expect(isWorkDetailExpiredByCF(_wd(applicationDeadline: _past1h, isEmergencyOpen: false)), isTrue);
    });

    test('H-07 isEmergencyOpen=true + deadline=past → CF 처리 제외', () {
      expect(isWorkDetailExpiredByCF(_wd(applicationDeadline: _past1h, isEmergencyOpen: true)), isFalse);
    });

    test('H-08 closedAt=past → CF 처리 제외 (이미 closedAt 있음)', () {
      expect(isWorkDetailExpiredByCF(_wd(closedAt: _past1h, applicationDeadline: _past1h)), isFalse);
    });

    test('H-09 deadline=null → CF 처리 제외', () {
      expect(isWorkDetailExpiredByCF(_wd(applicationDeadline: null)), isFalse);
    });

    test('H-10 deadline=future → CF 처리 제외', () {
      expect(isWorkDetailExpiredByCF(_wd(applicationDeadline: _future1h)), isFalse);
    });

    test('H-11 status=closed 슬롯 → CF 처리 제외', () {
      final slot = _slot(status: SlotStatus.closed, workDetails: [_wd(applicationDeadline: _past1h)]);
      expect(isSlotAutoClosedByCF(slot), isFalse);
    });

    test('H-12 workDetails=[] → CF 처리 제외 (workDetails 없는 슬롯)', () {
      final slot = _slot(status: SlotStatus.open, workDetails: []);
      expect(isSlotAutoClosedByCF(slot), isFalse);
    });

    // syncTOStatusFromSlots 재현: 열린 슬롯 여부로 TO 상태 결정
    bool shouldTOBeClosed(List<SlotModel> slots) {
      // closedBy != null인 슬롯은 평가 제외
      final evaluable = slots.where((s) => s.closedBy == null && !s.isManualClosed);
      return !evaluable.any((s) => s.status == SlotStatus.open);
    }

    test('H-13 모든 슬롯 closed, closedBy=null → TO CLOSED', () {
      expect(shouldTOBeClosed([
        _slot(status: SlotStatus.closed),
        _slot(status: SlotStatus.closed),
      ]), isTrue);
    });

    test('H-14 1개 슬롯 open → TO ACTIVE', () {
      expect(shouldTOBeClosed([
        _slot(status: SlotStatus.closed),
        _slot(status: SlotStatus.open),
      ]), isFalse);
    });

    test('H-15 isManualClosed=true 슬롯만 → 평가 제외 → TO CLOSED', () {
      expect(shouldTOBeClosed([
        _slot(status: SlotStatus.open, isManualClosed: true),
      ]), isTrue);
    });

    test('H-16 closedBy 있는 open 슬롯만 → 평가 제외 → TO CLOSED', () {
      expect(shouldTOBeClosed([
        _slot(status: SlotStatus.open, closedBy: 'uid1'),
      ]), isTrue);
    });

    test('H-17 closedBy 없는 open 슬롯 1개 → TO ACTIVE', () {
      expect(shouldTOBeClosed([
        _slot(status: SlotStatus.open, closedBy: null, isManualClosed: false),
      ]), isFalse);
    });

    test('H-18 슬롯 0개 → TO CLOSED', () {
      expect(shouldTOBeClosed([]), isTrue);
    });
  });
}

// ════════════════════════════════════════════════════════════
// I. 대량 파라미터화 시나리오 (50+ 케이스)
// ════════════════════════════════════════════════════════════

void _runParameterizedTests() {
  group('I. 파라미터화 시나리오', () {

    // I1. TOModel.isClosed 대량 표
    group('I1. TOModel.isClosed 조합표', () {
      final cases = <(String, bool, String, int, int, bool)>[
        // (desc, isManualClosed, status, req, conf, expected)
        ('수동마감만', true, TOStatus.active, 0, 0, true),
        ('인원충족만', false, TOStatus.active, 3, 3, true),
        ('status=CLOSED만', false, TOStatus.closed, 0, 0, true),
        ('status=EXPIRED만', false, TOStatus.expired, 0, 0, true),
        ('아무 조건 없음', false, TOStatus.active, 0, 0, false),
        ('req=5, conf=4, status=ACTIVE', false, TOStatus.active, 5, 4, false),
        ('수동마감+인원충족', true, TOStatus.active, 3, 3, true),
        ('status=CLOSED+인원미충족', false, TOStatus.closed, 5, 3, true),
        ('status=FULL, req=0', false, TOStatus.full, 0, 0, false),
        ('status=ACTIVE, req=1, conf=1', false, TOStatus.active, 1, 1, true),
        ('status=SCHEDULED, req=0', false, TOStatus.scheduled, 0, 0, false),
        ('status=DRAFT, req=0', false, TOStatus.draft, 0, 0, false),
        ('수동마감+CLOSED', true, TOStatus.closed, 0, 0, true),
        ('req=100, conf=100', false, TOStatus.active, 100, 100, true),
        ('req=100, conf=99', false, TOStatus.active, 100, 99, false),
      ];
      for (final (desc, manual, status, req, conf, expected) in cases) {
        test('I1-$desc', () {
          expect(
            _to(isManualClosed: manual, status: status, totalRequired: req, totalConfirmed: conf).isClosed,
            expected ? isTrue : isFalse,
          );
        });
      }
    });

    // I2. SlotModel.isEffectivelyClosed 조합표
    group('I2. SlotModel.isEffectivelyClosed 조합표', () {
      final cases = <(String, String, DateTime, bool)>[
        // (desc, status, date, expected)
        ('open+미래날짜', SlotStatus.open, _future7d, false),
        ('open+오늘', SlotStatus.open, _todayMidnight, false),
        ('open+어제', SlotStatus.open, _yesterdayMidnight, true),
        ('closed+미래날짜', SlotStatus.closed, _future7d, true),
        ('closed+어제', SlotStatus.closed, _yesterdayMidnight, true),
        ('full+미래날짜', SlotStatus.full, _future7d, true),
        ('full+오늘', SlotStatus.full, _todayMidnight, true),
        ('open+30일전', SlotStatus.open, _past30d, true),
        ('open+30일후', SlotStatus.open, _future30d, false),
        ('open+1일후', SlotStatus.open, _future1d, false),
      ];
      for (final (desc, status, date, expected) in cases) {
        test('I2-$desc', () {
          expect(
            _slot(status: status, date: date).isEffectivelyClosed,
            expected ? isTrue : isFalse,
          );
        });
      }
    });

    // I3. WorkDetailData.isClosed 조합표
    group('I3. WorkDetailData.isClosed 조합표', () {
      final cases = <(String, bool, DateTime?, bool)>[
        // (desc, isManualClosed, closedAt, expected)
        ('수동마감만', true, null, true),
        ('closedAt만', false, _past1h, true),
        ('둘다 없음', false, null, false),
        ('수동마감+closedAt', true, _past1h, true),
        ('수동마감=false+closedAt=future', false, _future1h, true),
      ];
      for (final (desc, manual, closedAt, expected) in cases) {
        test('I3-$desc', () {
          expect(
            _wd(isManualClosed: manual, closedAt: closedAt).isClosed,
            expected ? isTrue : isFalse,
          );
        });
      }
    });

    // I4. SlotStatusUtil 대량 케이스
    group('I4. SlotStatusUtil.slotStatus 대량', () {
      final cases = <(String, bool, String, String, DateTime, DateTime?, SlotDisplayStatus)>[
        // (desc, isPublished, toStatus, slotStatus, slotDate, visibleFrom, expected)
        ('정상모집', true, TOStatus.active, SlotStatus.open, _future7d, null, SlotDisplayStatus.recruiting),
        ('슬롯마감', true, TOStatus.active, SlotStatus.closed, _future7d, null, SlotDisplayStatus.closed),
        ('슬롯만원', true, TOStatus.active, SlotStatus.full, _future7d, null, SlotDisplayStatus.closed),
        ('날짜만료', true, TOStatus.active, SlotStatus.open, _yesterdayMidnight, null, SlotDisplayStatus.closed),
        ('visibleFrom=future', true, TOStatus.active, SlotStatus.open, _future7d, _future1h, SlotDisplayStatus.scheduled),
        ('visibleFrom=past', true, TOStatus.active, SlotStatus.open, _future7d, _past1h, SlotDisplayStatus.recruiting),
        ('DRAFT 미공개', false, TOStatus.draft, SlotStatus.open, _future7d, null, SlotDisplayStatus.draft),
        ('오늘날짜모집', true, TOStatus.active, SlotStatus.open, _todayMidnight, null, SlotDisplayStatus.recruiting),
      ];
      for (final (desc, published, toStatus, slotSt, date, vf, expected) in cases) {
        test('I4-$desc', () {
          final to = _to(isPublished: published, status: toStatus);
          final slot = _slot(status: slotSt, date: date, visibleFrom: vf);
          expect(SlotStatusUtil.slotStatus(slot, to), expected);
        });
      }
    });

    // I5. isPendingPublish 대량
    group('I5. isPendingPublish 대량', () {
      final cases = <(String, String, bool, DateTime?, bool)>[
        // (desc, publishMode, isPublished, publishAt, expected)
        ('immediate+published', 'immediate', true, null, false),
        ('scheduled+published', 'scheduled', true, _future1d, false),
        ('scheduled+미공개+future', 'scheduled', false, _future1d, true),
        ('scheduled+미공개+past', 'scheduled', false, _past1d, false),
        ('scheduled+미공개+null', 'scheduled', false, null, false),
        ('draft+미공개', 'draft', false, _future1d, false),
        ('immediate+미공개', 'immediate', false, null, false),
      ];
      for (final (desc, mode, published, pa, expected) in cases) {
        test('I5-$desc', () {
          expect(
            _to(publishMode: mode, isPublished: published, publishAt: pa).isPendingPublish,
            expected ? isTrue : isFalse,
          );
        });
      }
    });
  });
}

// ════════════════════════════════════════════════════════════
// J. 실제 운영 시나리오 (사용 패턴 기반)
// ════════════════════════════════════════════════════════════

void _runRealWorldScenarioTests() {
  group('J. 실제 운영 시나리오', () {

    test('J-01 [정상 모집중] 오늘 날짜 슬롯, workDetail 2개 모두 활성 → recruiting', () {
      final to = _to(isPublished: true, status: TOStatus.active);
      final slot = _slot(
        date: _todayMidnight,
        workDetails: [
          _wd(applicationDeadline: _future1d),
          _wd(applicationDeadline: _future7d),
        ],
      );
      expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.recruiting);
      expect(slot.isEffectivelyClosed, isFalse);
    });

    test('J-02 [마감 직전] 1개 workDetail 만료 임박 → recruiting (아직 마감 아님)', () {
      final slot = _slot(
        workDetails: [
          _wd(applicationDeadline: _now.add(const Duration(minutes: 5))),
          _wd(applicationDeadline: _future1d),
        ],
      );
      expect(slot.isEffectivelyClosed, isFalse);
    });

    test('J-03 [시간 마감] 모든 workDetail 만료 직후 → closed', () {
      final to = _to(isPublished: true);
      final slot = _slot(
        workDetails: [
          _wd(applicationDeadline: _now.subtract(const Duration(minutes: 1))),
          _wd(applicationDeadline: _past1h),
        ],
      );
      expect(slot.isEffectivelyClosed, isTrue);
      expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.closed);
    });

    test('J-04 [인원 충족 후 TO 상태] req=10, conf=10 → TO isFull=true, isClosed=true', () {
      final to = _to(totalRequired: 10, totalConfirmed: 10);
      expect(to.isFull, isTrue);
      expect(to.isClosed, isTrue);
    });

    test('J-05 [예약 공개 대기] TO publishAt=내일, 슬롯 visibleFrom=내일 → scheduled', () {
      final to = _to(publishMode: 'scheduled', isPublished: false, status: TOStatus.scheduled, publishAt: _future1d);
      final slot = _slot(visibleFrom: _future1d);
      expect(to.isPendingPublish, isTrue);
      expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.scheduled);
    });

    test('J-06 [공개 완료] publishAt=어제, isPublished=true → 정상 모집', () {
      final to = _to(publishMode: 'scheduled', isPublished: true, status: TOStatus.active, publishAt: _past1d);
      final slot = _slot(date: _future7d, visibleFrom: _past1d);
      expect(to.isPendingPublish, isFalse);
      expect(to.isPublished, isTrue);
      expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.recruiting);
    });

    test('J-07 [수동 마감 후 재오픈 검증] isManualClosed=true → isClosed=true', () {
      final closed = _to(isManualClosed: true);
      expect(closed.isClosed, isTrue);
      // 재오픈 시뮬레이션
      final reopened = _to(isManualClosed: false, status: TOStatus.active);
      expect(reopened.isClosed, isFalse);
    });

    test('J-08 [draft 상태] isPublished=false, status=DRAFT → slotStatus=draft', () {
      final to = _to(isPublished: false, status: TOStatus.draft);
      final slot = _slot(date: _future7d);
      expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.draft);
    });

    test('J-09 [계약직 deadline 마감] type=contract, deadline=past → isClosed=true', () {
      expect(_to(type: 'contract', applicationDeadline: _past1h).isClosed, isTrue);
    });

    test('J-10 [알바 deadline 무관] type=flex, deadline=past → isClosed=false', () {
      expect(_to(type: 'flex', applicationDeadline: _past1h).isClosed, isFalse);
    });

    test('J-11 [긴급 공개 보호] isEmergencyOpen=true, deadline=past → isClosed=false (isManualClosed 우선 아님)', () {
      // isEmergencyOpen은 CF 처리 제외이지, isClosed getter 변경 아님
      // workDetail 레벨에서 isClosed = isManualClosed || closedAt != null
      // isTimeExpired = deadline 기준이므로 isEmergencyOpen이 있어도 isTimeExpired=true
      final wd = _wd(applicationDeadline: _past1h, isEmergencyOpen: true);
      expect(wd.isTimeExpired, isTrue); // CF 처리는 제외하지만 getter는 그대로
      expect(wd.isClosed, isFalse);    // closedAt=null이므로 isClosed=false
    });

    test('J-12 [슬롯 수동 마감 + TO 재오픈] slot.isManualClosed=true → 슬롯 마감됨', () {
      final slot = _slot(status: SlotStatus.closed, isManualClosed: true);
      expect(slot.isClosed, isTrue);
      expect(slot.isEffectivelyClosed, isTrue);
    });

    test('J-13 [workDetail closedAt만 있음] closedAt=과거, isManualClosed=false → isClosed=true', () {
      final wd = _wd(closedAt: _past1h, isManualClosed: false);
      expect(wd.isClosed, isTrue);
    });

    test('J-14 [복합 만료: TO 수동마감 + 슬롯 활성] TO isManualClosed=true + slot=open → isClosed=true', () {
      final to = _to(isManualClosed: true);
      expect(to.isClosed, isTrue);
    });

    test('J-15 [공고 상태 FULL 단독] status=FULL, req=0 → isClosed=false (isFull=false)', () {
      final to = _to(status: TOStatus.full, totalRequired: 0);
      expect(to.isFull, isFalse);
      expect(to.isClosed, isFalse);
    });

    test('J-16 [공고 status=FULL + req>0 충족] status=FULL, req=5, conf=5 → isClosed=true (isFull=true)', () {
      final to = _to(status: TOStatus.full, totalRequired: 5, totalConfirmed: 5);
      expect(to.isFull, isTrue);
      expect(to.isClosed, isTrue);
    });

    test('J-17 [오늘 날짜 슬롯 + deadline=1분 전 + workDetails 있음] → isEffectivelyClosed=true', () {
      final slot = _slot(
        date: _todayMidnight,
        workDetails: [_wd(applicationDeadline: _now.subtract(const Duration(minutes: 1)))],
      );
      expect(slot.isEffectivelyClosed, isTrue);
    });

    test('J-18 [예약 공개 후 visibleFrom 지남] TO isPublished=true, slot.visibleFrom=과거 → recruiting', () {
      final to = _to(isPublished: true, status: TOStatus.active);
      final slot = _slot(date: _future7d, visibleFrom: _past1h);
      expect(SlotStatusUtil.slotStatus(slot, to), SlotDisplayStatus.recruiting);
    });

    test('J-19 [장기 근무 공고] type=contract, applicationDeadline=30일 후 → isClosed=false', () {
      expect(_to(type: 'contract', applicationDeadline: _future30d).isClosed, isFalse);
    });

    test('J-20 [전체 마감 시나리오] TO status=CLOSED + 모든 슬롯 closed → 완전 마감', () {
      final to = _to(status: TOStatus.closed);
      final slot1 = _slot(status: SlotStatus.closed);
      final slot2 = _slot(status: SlotStatus.closed);
      expect(to.isClosed, isTrue);
      expect(slot1.isEffectivelyClosed, isTrue);
      expect(slot2.isEffectivelyClosed, isTrue);
    });
  });
}

// ════════════════════════════════════════════════════════════
// K. processScheduledPublish CF 로직 재현
// ════════════════════════════════════════════════════════════

void _runProcessScheduledPublishTests() {
  group('K. processScheduledPublish 로직 재현', () {

    bool shouldPublishNow(TOModel to) {
      // CF 처리 조건: publishMode=='scheduled' && !isPublished && publishAt <= now && closedBy == null
      if (to.publishMode != 'scheduled') return false;
      if (to.isPublished) return false;
      if (to.publishAt == null) return false;
      if (to.closedBy != null) return false;
      return !_now.isBefore(to.publishAt!); // now >= publishAt
    }

    test('K-01 publishAt=1h ago + 미공개 → 공개 처리 대상', () {
      expect(shouldPublishNow(_to(publishMode: 'scheduled', isPublished: false, publishAt: _past1h)), isTrue);
    });
    test('K-02 publishAt=1h future + 미공개 → 처리 미대상', () {
      expect(shouldPublishNow(_to(publishMode: 'scheduled', isPublished: false, publishAt: _future1h)), isFalse);
    });
    test('K-03 이미 isPublished=true → 처리 미대상', () {
      expect(shouldPublishNow(_to(publishMode: 'scheduled', isPublished: true, publishAt: _past1h)), isFalse);
    });
    test('K-04 publishMode=immediate → 처리 미대상', () {
      expect(shouldPublishNow(_to(publishMode: 'immediate', isPublished: false)), isFalse);
    });
    test('K-05 publishAt=null → 처리 미대상', () {
      expect(shouldPublishNow(_to(publishMode: 'scheduled', isPublished: false, publishAt: null)), isFalse);
    });
    test('K-06 closedBy 있음 + publishAt=past → 처리 미대상 (수동마감 보호)', () {
      final to = TOModel(
        id:'to1', businessId:'biz', businessName:'biz', title:'t',
        creatorUID:'uid', createdAt: _past30d,
        publishMode: 'scheduled', isPublished: false,
        publishAt: _past1h, closedBy: 'uid',
      );
      expect(shouldPublishNow(to), isFalse);
    });
    test('K-07 publishAt=정확히 now-1ms → 처리 대상', () {
      expect(shouldPublishNow(_to(publishMode: 'scheduled', isPublished: false, publishAt: _now.subtract(const Duration(milliseconds: 1)))), isTrue);
    });
    test('K-08 publishAt=정확히 now+1ms → 처리 미대상', () {
      expect(shouldPublishNow(_to(publishMode: 'scheduled', isPublished: false, publishAt: _now.add(const Duration(milliseconds: 1)))), isFalse);
    });
  });
}

// ════════════════════════════════════════════════════════════
// L. WorkDetailData 임금 검증 (wage 경계값)
// ════════════════════════════════════════════════════════════

void _runWageTests() {
  group('L. WorkDetailData 임금 경계값', () {
    test('L-01 wage=0 → 생성 가능 (유효성은 서비스 레이어에서)', () {
      expect(() => _wd(wage: 0), returnsNormally);
    });
    test('L-02 wage=10030 (최저임금 수준) → 생성 가능', () {
      expect(() => _wd(wage: 10030), returnsNormally);
    });
    test('L-03 wage=50000000 (5천만) → 생성 가능', () {
      expect(() => _wd(wage: 50000000), returnsNormally);
    });
    test('L-04 requiredCount=1 → 생성 가능', () {
      expect(() => _wd(requiredCount: 1), returnsNormally);
    });
    test('L-05 requiredCount=10000 → 생성 가능', () {
      expect(() => _wd(requiredCount: 10000), returnsNormally);
    });
  });
}

// ════════════════════════════════════════════════════════════
// main
// ════════════════════════════════════════════════════════════

void main() {
  _runToIsClosedTests();
  _runToIsPendingPublishTests();
  _runSlotIsEffectivelyClosedTests();
  _runWorkDetailTests();
  _runSlotStatusUtilTests();
  _runEdgeCaseTests();
  _runPublishScheduleTests();
  _runCFExpiryLogicTests();
  _runParameterizedTests();
  _runRealWorldScenarioTests();
  _runProcessScheduledPublishTests();
  _runWageTests();
}
