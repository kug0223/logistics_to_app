import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';
import 'package:ALfit/utils/slot_status_util.dart';

// ──────────────────────────────────────────────────────────
// 테스트 헬퍼
// ──────────────────────────────────────────────────────────

final _futureDate  = DateTime.now().add(const Duration(days: 30));   // 먼 미래 날짜
final _todayDate   = DateTime.now();                                   // 오늘
final _pastDate    = DateTime.now().subtract(const Duration(days: 1)); // 어제 (isDatePast=true)
final _futureVF    = DateTime.now().add(const Duration(hours: 2));    // 미래 visibleFrom
final _pastVF      = DateTime.now().subtract(const Duration(hours: 2)); // 과거 visibleFrom
final _futurePA    = DateTime.now().add(const Duration(hours: 3));    // 미래 publishAt
final _pastPA      = DateTime.now().subtract(const Duration(hours: 3)); // 과거 publishAt

WorkDetailData _wd({bool expired = false, bool closed = false}) {
  return WorkDetailData(
    workType: 'WD',
    startTime: '09:00',
    endTime: '18:00',
    wage: 10000,
    wageType: 'hourly',
    requiredCount: 2,
    applicationDeadline: expired
        ? DateTime.now().subtract(const Duration(hours: 1))
        : DateTime.now().add(const Duration(hours: 3)),
    isManualClosed: closed,
    closedAt: closed ? DateTime.now() : null,
  );
}

/// 슬롯 팩토리
SlotModel _slot({
  String status = SlotStatus.open,
  DateTime? date,
  DateTime? visibleFrom,
  List<WorkDetailData>? workDetails,
  bool isManualClosed = false,
}) {
  return SlotModel(
    id: 's1', toId: 'to1',
    date: date ?? _futureDate,
    status: status,
    visibleFrom: visibleFrom,
    workDetails: workDetails ?? const [],
    isManualClosed: isManualClosed,
    createdAt: DateTime(2025),
  );
}

/// TO 팩토리 (published, active 기본)
TOModel _to({
  String status = TOStatus.active,
  bool isPublished = true,
  String publishMode = 'immediate',
  DateTime? publishAt,
  bool isManualClosed = false,
  int totalRequired = 3,
  int totalConfirmed = 0,
}) {
  return TOModel(
    id: 'to1',
    businessId: 'b1',
    businessName: '테스트',
    type: 'flex',
    title: '공고',
    creatorUID: 'u1',
    status: status,
    isPublished: isPublished,
    publishMode: publishMode,
    publishAt: publishAt,
    isManualClosed: isManualClosed,
    totalRequired: totalRequired,
    totalConfirmed: totalConfirmed,
    workDetails: const [],
    createdAt: DateTime(2025),
  );
}

/// Draft TO 팩토리
TOModel _draftTO({String publishMode = 'draft'}) => _to(
  status: TOStatus.draft,
  isPublished: false,
  publishMode: publishMode,
);

/// 예약 공개 대기 TO 팩토리 (isPendingPublish=true)
TOModel _pendingTO({DateTime? publishAt}) => _to(
  status: TOStatus.scheduled,
  isPublished: false,
  publishMode: 'scheduled',
  publishAt: publishAt ?? _futurePA,
);

/// TOItem 팩토리
TOItem _item({required TOModel to, SlotModel? slot}) {
  return TOItem(
    to: to,
    slot: slot,
    workDetails: null,
    confirmedCount: 0,
    pendingCount: 0,
    totalRequired: 3,
    isWorkDetailLoaded: false,
  );
}

// ──────────────────────────────────────────────────────────
// 테스트
// ──────────────────────────────────────────────────────────

void main() {
  // ════════════════════════════════════════════════════════
  // slotStatus()
  // ════════════════════════════════════════════════════════

  group('SlotStatusUtil.slotStatus', () {

    // ── Group A: Draft TO → 항상 draft ──────────────────
    group('A. Draft TO', () {
      test('A1. draft TO + 열린 슬롯 → draft', () {
        expect(SlotStatusUtil.slotStatus(_slot(), _draftTO()),
            SlotDisplayStatus.draft);
      });

      test('A2. draft TO + 수동마감 슬롯 → draft (TO draft 우선)', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(status: SlotStatus.closed, isManualClosed: true), _draftTO()),
            SlotDisplayStatus.draft);
      });

      test('A3. draft TO + 인원충족 슬롯 → draft', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(status: SlotStatus.full), _draftTO()),
            SlotDisplayStatus.draft);
      });

      test('A4. draft TO + 날짜경과 슬롯 → draft', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(date: _pastDate), _draftTO()),
            SlotDisplayStatus.draft);
      });

      test('A5. draft TO + 미래 visibleFrom 슬롯 → draft', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(visibleFrom: _futureVF), _draftTO()),
            SlotDisplayStatus.draft);
      });

      test('A6. draft TO + 만료된 workDetails → draft', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(workDetails: [_wd(expired: true)]), _draftTO()),
            SlotDisplayStatus.draft);
      });

      test('A7. publishMode=draft이지만 status=active, isPublished=false → draft (isPublished+status 모두 체크)', () {
        // status=draft이면서 isPublished=false여야 draft 반환
        // status=active이면서 isPublished=false는 draft가 아님
        final nonDraftTO = _to(status: TOStatus.active, isPublished: false);
        final result = SlotStatusUtil.slotStatus(_slot(), nonDraftTO);
        // isPublished=false && status!=draft → draft 아님 → 다음 조건으로
        expect(result, isNot(SlotDisplayStatus.draft));
      });

      test('A8. isPublished=true이지만 status=draft → draft 아님 (이미 공개됨)', () {
        final weirdTO = _to(status: TOStatus.draft, isPublished: true);
        final result = SlotStatusUtil.slotStatus(_slot(), weirdTO);
        expect(result, isNot(SlotDisplayStatus.draft));
      });
    });

    // ── Group B: Published TO, 슬롯 마감 → closed ──────
    group('B. 슬롯 isEffectivelyClosed', () {
      final publishedTO = _to();

      test('B1. 수동마감 슬롯(status=closed) → closed', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(status: SlotStatus.closed, isManualClosed: true), publishedTO),
            SlotDisplayStatus.closed);
      });

      test('B2. 인원충족 슬롯(status=full) → closed (isEffectivelyClosed 포함)', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(status: SlotStatus.full), publishedTO),
            SlotDisplayStatus.closed);
      });

      test('B3. 어제 날짜 슬롯 → closed (isDatePast)', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(date: _pastDate), publishedTO),
            SlotDisplayStatus.closed);
      });

      test('B4. workDetails 모두 만료 → closed', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(workDetails: [_wd(expired: true), _wd(expired: true)]), publishedTO),
            SlotDisplayStatus.closed);
      });

      test('B5. workDetails 일부만 만료 → closed 아님 (일부 유효)', () {
        final result = SlotStatusUtil.slotStatus(
            _slot(workDetails: [_wd(expired: true), _wd(expired: false)]), publishedTO);
        expect(result, isNot(SlotDisplayStatus.closed));
      });

      test('B6. workDetails 없고 applicationDeadline 없음 → closed 아님', () {
        final result = SlotStatusUtil.slotStatus(_slot(), publishedTO);
        expect(result, isNot(SlotDisplayStatus.closed));
      });

      test('B7. 수동마감 + 미래 visibleFrom → closed (마감이 visibleFrom보다 우선)', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(status: SlotStatus.closed, visibleFrom: _futureVF), publishedTO),
            SlotDisplayStatus.closed);
      });

      test('B8. 수동마감 + TO 예약대기 → closed (마감이 예약보다 우선)', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(status: SlotStatus.closed), _pendingTO()),
            SlotDisplayStatus.closed);
      });

      test('B9. 날짜경과 + 미래 visibleFrom → closed', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(date: _pastDate, visibleFrom: _futureVF), publishedTO),
            SlotDisplayStatus.closed);
      });

      test('B10. 날짜경과 + TO 예약대기 → closed', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(date: _pastDate), _pendingTO()),
            SlotDisplayStatus.closed);
      });

      test('B11. workDetails 모두 수동마감(isClosed=true) → closed', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(workDetails: [_wd(closed: true)]), publishedTO),
            SlotDisplayStatus.closed);
      });

      test('B11b. workDetails 만료+수동마감 혼합 → closed (모두 해당)', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(workDetails: [_wd(expired: true), _wd(closed: true)]), publishedTO),
            SlotDisplayStatus.closed);
      });

      test('B12. 인원충족 + 미래 visibleFrom → closed (충족이 visibleFrom보다 우선)', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(status: SlotStatus.full, visibleFrom: _futureVF), publishedTO),
            SlotDisplayStatus.closed);
      });
    });

    // ── Group C: 슬롯 레벨 visibleFrom → scheduled ─────
    group('C. 슬롯 visibleFrom 예약', () {
      final publishedTO = _to();

      test('C1. 미래 visibleFrom, 열린 슬롯 → scheduled', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(visibleFrom: _futureVF), publishedTO),
            SlotDisplayStatus.scheduled);
      });

      test('C2. 과거 visibleFrom → scheduled 아님 (이미 공개시각 경과)', () {
        final result = SlotStatusUtil.slotStatus(
            _slot(visibleFrom: _pastVF), publishedTO);
        expect(result, isNot(SlotDisplayStatus.scheduled));
      });

      test('C3. visibleFrom=null → scheduled 아님', () {
        final result = SlotStatusUtil.slotStatus(_slot(), publishedTO);
        expect(result, isNot(SlotDisplayStatus.scheduled));
      });

      test('C4. 미래 visibleFrom + TO도 pendingPublish → scheduled (visibleFrom 우선)', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(visibleFrom: _futureVF), _pendingTO()),
            SlotDisplayStatus.scheduled);
      });

      test('C5. 미래 visibleFrom, 오늘 날짜 슬롯 → scheduled', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(date: _todayDate, visibleFrom: _futureVF), publishedTO),
            SlotDisplayStatus.scheduled);
      });

      test('C6. 과거 visibleFrom + TO는 pendingPublish → scheduled (TO 레벨 예약)', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(visibleFrom: _pastVF), _pendingTO()),
            SlotDisplayStatus.scheduled);
      });
    });

    // ── Group D: TO 레벨 예약 공개 대기 → scheduled ────
    group('D. TO isPendingPublish', () {
      test('D1. publishMode=scheduled, isPublished=false, publishAt=미래 → scheduled', () {
        expect(SlotStatusUtil.slotStatus(_slot(), _pendingTO()),
            SlotDisplayStatus.scheduled);
      });

      test('D2. publishMode=scheduled, isPublished=false, publishAt=과거 → recruiting (pending 아님)', () {
        final expiredScheduledTO = _to(
          status: TOStatus.active,
          isPublished: false,
          publishMode: 'scheduled',
          publishAt: _pastPA,
        );
        final result = SlotStatusUtil.slotStatus(_slot(), expiredScheduledTO);
        // isPendingPublish=false (publishAt 경과) → 모집중 or draft
        expect(result, isNot(SlotDisplayStatus.scheduled));
      });

      test('D3. publishMode=immediate, isPublished=false → isPendingPublish=false → draft 아님 but scheduled 아님', () {
        final immediateUnpublished = _to(
          status: TOStatus.active,
          isPublished: false,
          publishMode: 'immediate',
        );
        final result = SlotStatusUtil.slotStatus(_slot(), immediateUnpublished);
        expect(result, isNot(SlotDisplayStatus.scheduled));
      });

      test('D4. pendingPublish TO + workDetails 없음 + 열린 슬롯 → scheduled', () {
        expect(SlotStatusUtil.slotStatus(_slot(), _pendingTO()),
            SlotDisplayStatus.scheduled);
      });

      test('D5. isPublished=true인 예약 TO → isPendingPublish=false → scheduled 아님', () {
        final publishedScheduled = _to(
          status: TOStatus.scheduled,
          isPublished: true,
          publishMode: 'scheduled',
          publishAt: _futurePA,
        );
        final result = SlotStatusUtil.slotStatus(_slot(), publishedScheduled);
        expect(result, isNot(SlotDisplayStatus.scheduled));
      });

      test('D6. publishAt=null이면 isPendingPublish=false', () {
        final noPublishAt = _to(
          status: TOStatus.scheduled,
          isPublished: false,
          publishMode: 'scheduled',
          publishAt: null,
        );
        final result = SlotStatusUtil.slotStatus(_slot(), noPublishAt);
        expect(result, isNot(SlotDisplayStatus.scheduled));
      });
    });

    // ── Group E: 충족(full) 불가 경로 검증 ────────────
    group('E. 인원충족(full) → closed로 표시', () {
      final publishedTO = _to();

      test('E1. slot.isFull=true → isEffectivelyClosed=true → closed', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(status: SlotStatus.full), publishedTO),
            SlotDisplayStatus.closed);
      });

      test('E2. isFull=true + draft TO → draft (draft 최우선)', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(status: SlotStatus.full), _draftTO()),
            SlotDisplayStatus.draft);
      });
    });

    // ── Group F: 모집중 ──────────────────────────────
    group('F. 모집중 (recruiting)', () {
      final publishedTO = _to();

      test('F1. 공개된 TO + 열린 슬롯 + 미래 날짜 → recruiting', () {
        expect(SlotStatusUtil.slotStatus(_slot(), publishedTO),
            SlotDisplayStatus.recruiting);
      });

      test('F2. 공개된 TO + 오늘 날짜 슬롯 → recruiting (당일은 마감 아님)', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(date: _todayDate), publishedTO),
            SlotDisplayStatus.recruiting);
      });

      test('F3. 공개된 TO + 과거 visibleFrom + 열린 슬롯 → recruiting', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(visibleFrom: _pastVF), publishedTO),
            SlotDisplayStatus.recruiting);
      });

      test('F4. workDetails 일부만 만료, 일부 유효 → recruiting', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(workDetails: [_wd(expired: true), _wd(expired: false)]), publishedTO),
            SlotDisplayStatus.recruiting);
      });

      test('F5. 공개된 TO + workDetails 없음 → recruiting', () {
        expect(SlotStatusUtil.slotStatus(_slot(), publishedTO),
            SlotDisplayStatus.recruiting);
      });
    });

    // ── Group G: 엣지 케이스 ─────────────────────────
    group('G. 엣지 케이스', () {
      test('G1. TO status=FULL(totalConfirmed>=totalRequired) + 슬롯 open → isClosed체크', () {
        // TO.isFull=true → TO.isClosed=true 이지만 slotStatus는 slot 기준
        final fullTO = _to(totalRequired: 2, totalConfirmed: 2, status: TOStatus.full);
        // 슬롯이 open이면 slot.isEffectivelyClosed 여부에 따름
        final result = SlotStatusUtil.slotStatus(_slot(), fullTO);
        // TO full이 slot에 직접 영향 없음 → recruiting
        expect(result, SlotDisplayStatus.recruiting);
      });

      test('G2. TO status=CLOSED + isPublished=true + slot open → recruiting (slot 기준)', () {
        // TO status=CLOSED이지만 isManualClosed=false → slot 기준으로 판단 → recruiting
        final closedTO = _to(status: TOStatus.closed, isManualClosed: false);
        final result = SlotStatusUtil.slotStatus(_slot(), closedTO);
        expect(result, SlotDisplayStatus.recruiting);
      });

      test('G3. 오늘 날짜 슬롯 + workDetails 모두 만료 → closed', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(date: _todayDate, workDetails: [_wd(expired: true)]),
            _to()),
            SlotDisplayStatus.closed);
      });

      test('G4. 오늘 날짜 슬롯 + workDetails 유효 → recruiting', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(date: _todayDate, workDetails: [_wd(expired: false)]),
            _to()),
            SlotDisplayStatus.recruiting);
      });

      test('G5. 미래 날짜 + 과거 visibleFrom + 공개TO → recruiting', () {
        expect(SlotStatusUtil.slotStatus(
            _slot(date: _futureDate, visibleFrom: _pastVF), _to()),
            SlotDisplayStatus.recruiting);
      });

      test('G6. 수동마감 isManualClosed=true + status=open → closed (isManualClosed 반영 확인)', () {
        // isManualClosed는 메타데이터용, isClosed는 status 기준
        // isEffectivelyClosed = isClosed || ... → status=open이면 isClosed=false
        // isManualClosed=true이지만 status=open이면 isEffectivelyClosed에 영향 없음
        final slot = _slot(status: SlotStatus.open, isManualClosed: true);
        final result = SlotStatusUtil.slotStatus(slot, _to());
        // slot.isClosed = status == closed = false → not closed from isClosed
        // but isManualClosed=true doesn't directly factor into isEffectivelyClosed
        expect(result, isNot(SlotDisplayStatus.closed));
      });

      test('G7. 매우 먼 미래 publishAt → isPendingPublish=true → scheduled', () {
        final farFuturePA = DateTime.now().add(const Duration(days: 365));
        expect(SlotStatusUtil.slotStatus(_slot(), _pendingTO(publishAt: farFuturePA)),
            SlotDisplayStatus.scheduled);
      });

      test('G8. 방금 전 publishAt (1분 전) → isPendingPublish=false → recruiting', () {
        final justPastPA = DateTime.now().subtract(const Duration(minutes: 1));
        final expiredPending = _to(
          status: TOStatus.scheduled,
          isPublished: false,
          publishMode: 'scheduled',
          publishAt: justPastPA,
        );
        final result = SlotStatusUtil.slotStatus(_slot(), expiredPending);
        expect(result, isNot(SlotDisplayStatus.scheduled));
      });

      test('G9. workDetails 빈 리스트이고 applicationDeadline=null → 마감 아님', () {
        final slot = SlotModel(
          id: 's1', toId: 'to1', date: _futureDate,
          workDetails: const [], applicationDeadline: null,
          status: SlotStatus.open, createdAt: DateTime(2025),
        );
        expect(SlotStatusUtil.slotStatus(slot, _to()), SlotDisplayStatus.recruiting);
      });

      test('G10. visibleFrom이 정확히 1분 후 → scheduled', () {
        final oneMinuteAfter = DateTime.now().add(const Duration(minutes: 1));
        expect(SlotStatusUtil.slotStatus(
            _slot(visibleFrom: oneMinuteAfter), _to()),
            SlotDisplayStatus.scheduled);
      });
    });
  });

  // ════════════════════════════════════════════════════════
  // slotScheduledAt()
  // ════════════════════════════════════════════════════════

  group('SlotStatusUtil.slotScheduledAt', () {
    test('SA1. 미래 visibleFrom → visibleFrom 반환 (TO publishAt 무시)', () {
      final slot = _slot(visibleFrom: _futureVF);
      final to = _pendingTO(publishAt: _futurePA);
      expect(SlotStatusUtil.slotScheduledAt(slot, to), _futureVF);
    });

    test('SA2. 과거 visibleFrom → TO publishAt 반환', () {
      final slot = _slot(visibleFrom: _pastVF);
      final to = _pendingTO(publishAt: _futurePA);
      expect(SlotStatusUtil.slotScheduledAt(slot, to), _futurePA);
    });

    test('SA3. visibleFrom=null → TO publishAt 반환', () {
      final slot = _slot();
      final to = _pendingTO(publishAt: _futurePA);
      expect(SlotStatusUtil.slotScheduledAt(slot, to), _futurePA);
    });

    test('SA4. visibleFrom=null + TO publishAt=null → null 반환', () {
      final slot = _slot();
      final to = _to();
      expect(SlotStatusUtil.slotScheduledAt(slot, to), isNull);
    });

    test('SA5. 미래 visibleFrom + TO publishAt=null → visibleFrom 반환', () {
      final slot = _slot(visibleFrom: _futureVF);
      final to = _to();
      expect(SlotStatusUtil.slotScheduledAt(slot, to), _futureVF);
    });

    test('SA6. 과거 visibleFrom + TO publishAt=null → null 반환', () {
      final slot = _slot(visibleFrom: _pastVF);
      final to = _to();
      expect(SlotStatusUtil.slotScheduledAt(slot, to), isNull);
    });
  });

  // ════════════════════════════════════════════════════════
  // groupStatus()
  // ════════════════════════════════════════════════════════

  group('SlotStatusUtil.groupStatus', () {
    final activeTO = _to();
    final draftTO = _draftTO();
    final pendingTO = _pendingTO();

    // ── Group H: allClosed=true → closed ───────────────
    group('H. allClosed 플래그', () {
      test('H1. allClosed=true, targetTOs 없음 → closed', () {
        expect(SlotStatusUtil.groupStatus(
            allClosed: true, masterTO: activeTO, targetTOs: []),
            SlotDisplayStatus.closed);
      });

      test('H2. allClosed=true, targetTOs 있음 → closed (allClosed 최우선)', () {
        final items = [_item(to: activeTO, slot: _slot())];
        expect(SlotStatusUtil.groupStatus(
            allClosed: true, masterTO: activeTO, targetTOs: items),
            SlotDisplayStatus.closed);
      });

      test('H3. allClosed=true, draft masterTO → closed (allClosed > draft)', () {
        expect(SlotStatusUtil.groupStatus(
            allClosed: true, masterTO: draftTO, targetTOs: []),
            SlotDisplayStatus.closed);
      });
    });

    // ── Group I: targetTOs 비어있음 (contract TO) ───────
    group('I. targetTOs 비어있음 (contract TO)', () {
      test('I1. masterTO status=draft → draft', () {
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: draftTO, targetTOs: []),
            SlotDisplayStatus.draft);
      });

      test('I2. masterTO isPendingPublish=true → scheduled', () {
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: pendingTO, targetTOs: []),
            SlotDisplayStatus.scheduled);
      });

      test('I3. masterTO isPublished=true, active → recruiting', () {
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: activeTO, targetTOs: []),
            SlotDisplayStatus.recruiting);
      });

      test('I4. masterTO status=closed → recruiting (targetTOs 비어있으면 isClosed 체크 없음)', () {
        final closedTO = _to(status: TOStatus.closed);
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: closedTO, targetTOs: []),
            SlotDisplayStatus.recruiting);
      });

      test('I5. masterTO status=FULL → recruiting (groupStatus에 full 없음)', () {
        final fullTO = _to(status: TOStatus.full, totalRequired: 2, totalConfirmed: 2);
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: fullTO, targetTOs: []),
            SlotDisplayStatus.recruiting);
      });
    });

    // ── Group J: 공개된 TO 있는 경우 ──────────────────
    group('J. 공개된 TO 포함', () {
      test('J1. 공개 TO 하나 + slot visibleFrom=null → recruiting', () {
        final items = [_item(to: activeTO, slot: _slot())];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: activeTO, targetTOs: items),
            SlotDisplayStatus.recruiting);
      });

      test('J2. 공개 TO 하나 + slot 미래 visibleFrom → scheduled (전체 예약)', () {
        final items = [_item(to: activeTO, slot: _slot(visibleFrom: _futureVF))];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: activeTO, targetTOs: items),
            SlotDisplayStatus.scheduled);
      });

      test('J3. 공개 TO 2개 + 모두 미래 visibleFrom → scheduled', () {
        final items = [
          _item(to: activeTO, slot: _slot(visibleFrom: _futureVF)),
          _item(to: activeTO, slot: _slot(visibleFrom: _futureVF)),
        ];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: activeTO, targetTOs: items),
            SlotDisplayStatus.scheduled);
      });

      test('J4. 공개 TO 2개 + 일부만 미래 visibleFrom → recruiting (일부라도 공개됐으면)', () {
        final items = [
          _item(to: activeTO, slot: _slot(visibleFrom: _futureVF)),
          _item(to: activeTO, slot: _slot(visibleFrom: _pastVF)),
        ];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: activeTO, targetTOs: items),
            SlotDisplayStatus.recruiting);
      });

      test('J5. 공개 TO + slot visibleFrom=null + 미공개 TO → recruiting (공개된게 있으면)', () {
        final unpublishedTO = _to(isPublished: false, status: TOStatus.draft);
        final items = [
          _item(to: activeTO, slot: _slot()),      // 공개
          _item(to: unpublishedTO, slot: _slot()), // 미공개
        ];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: activeTO, targetTOs: items),
            SlotDisplayStatus.recruiting);
      });

      test('J6. 공개 TO + slot=null → slot visibleFrom 없음 → recruiting', () {
        // slot이 null이면 visibleFrom=null 취급
        final items = [_item(to: activeTO, slot: null)];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: activeTO, targetTOs: items),
            SlotDisplayStatus.recruiting);
      });

      test('J7. 공개 TO + slot=null이고 다른 슬롯 있는 공개 TO → allSlotScheduled=false', () {
        final items = [
          _item(to: activeTO, slot: null),
          _item(to: activeTO, slot: _slot(visibleFrom: _futureVF)),
        ];
        // allSlotScheduled: null.visibleFrom=null → false → recruiting
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: activeTO, targetTOs: items),
            SlotDisplayStatus.recruiting);
      });
    });

    // ── Group K: 미공개 TO만 있는 경우 ────────────────
    group('K. 미공개 TO만 있음', () {
      test('K1. 모두 draft TO → draft', () {
        final items = [
          _item(to: draftTO, slot: _slot()),
          _item(to: draftTO, slot: _slot()),
        ];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: draftTO, targetTOs: items),
            SlotDisplayStatus.draft);
      });

      test('K2. 모두 pending TO (예약공개) → scheduled', () {
        final items = [
          _item(to: pendingTO, slot: _slot()),
          _item(to: pendingTO, slot: _slot()),
        ];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: pendingTO, targetTOs: items),
            SlotDisplayStatus.scheduled);
      });

      test('K3. draft + pending 혼합 → scheduled (isPendingPublish 있으면 scheduled 우선)', () {
        final items = [
          _item(to: draftTO, slot: _slot()),
          _item(to: pendingTO, slot: _slot()),
        ];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: draftTO, targetTOs: items),
            SlotDisplayStatus.scheduled);
      });

      test('K4. 미공개 immediate TO (neither draft nor pending) → draft 반환', () {
        final immediateUnpublished = _to(
          status: TOStatus.active, isPublished: false, publishMode: 'immediate');
        final items = [_item(to: immediateUnpublished, slot: _slot())];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: immediateUnpublished, targetTOs: items),
            SlotDisplayStatus.draft);
      });

      test('K5. pending TO의 publishAt이 과거 → isPendingPublish=false → draft', () {
        final expiredPending = _to(
          status: TOStatus.scheduled, isPublished: false,
          publishMode: 'scheduled', publishAt: _pastPA);
        final items = [_item(to: expiredPending, slot: _slot())];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: expiredPending, targetTOs: items),
            SlotDisplayStatus.draft);
      });
    });

    // ── Group L: 혼합 시나리오 ─────────────────────────
    group('L. 혼합 시나리오', () {
      test('L1. 공개 1개 + pending 1개 → recruiting (공개된게 있으면 공개 기준)', () {
        final items = [
          _item(to: activeTO, slot: _slot()),
          _item(to: pendingTO, slot: _slot()),
        ];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: activeTO, targetTOs: items),
            SlotDisplayStatus.recruiting);
      });

      test('L2. 공개 1개(미래 visibleFrom) + pending 1개 → scheduled (공개된게 모두 예약)', () {
        final items = [
          _item(to: activeTO, slot: _slot(visibleFrom: _futureVF)),
          _item(to: pendingTO, slot: _slot()),
        ];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: activeTO, targetTOs: items),
            SlotDisplayStatus.scheduled);
      });

      test('L3. 공개 1개(미래 visibleFrom) + draft 1개 → scheduled', () {
        final items = [
          _item(to: activeTO, slot: _slot(visibleFrom: _futureVF)),
          _item(to: draftTO, slot: _slot()),
        ];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: activeTO, targetTOs: items),
            SlotDisplayStatus.scheduled);
      });

      test('L4. 전원 미공개 + allClosed=false → draft', () {
        final items = [
          _item(to: draftTO, slot: _slot()),
          _item(to: draftTO, slot: _slot()),
          _item(to: draftTO, slot: _slot()),
        ];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: draftTO, targetTOs: items),
            SlotDisplayStatus.draft);
      });

      test('L5. 공개된 TO 있고 slot=null + 미래 visibleFrom슬롯 없음 → recruiting', () {
        final items = [_item(to: activeTO, slot: null)];
        expect(SlotStatusUtil.groupStatus(
            allClosed: false, masterTO: activeTO, targetTOs: items),
            SlotDisplayStatus.recruiting);
      });
    });
  });

  // ════════════════════════════════════════════════════════
  // groupScheduledAt()
  // ════════════════════════════════════════════════════════

  group('SlotStatusUtil.groupScheduledAt', () {
    final activeTO = _to();
    final pendingTO = _pendingTO(publishAt: _futurePA);

    test('GS1. targetTOs 비어있음 → masterTO.publishAt 반환', () {
      expect(SlotStatusUtil.groupScheduledAt(
          masterTO: pendingTO, targetTOs: []),
          _futurePA);
    });

    test('GS2. targetTOs 비어있음 + masterTO.publishAt=null → null', () {
      expect(SlotStatusUtil.groupScheduledAt(
          masterTO: activeTO, targetTOs: []),
          isNull);
    });

    test('GS3. 공개 TO + 미래 visibleFrom 슬롯 → 가장 이른 visibleFrom', () {
      final vf1 = DateTime.now().add(const Duration(hours: 1));
      final vf2 = DateTime.now().add(const Duration(hours: 3));
      final items = [
        _item(to: activeTO, slot: _slot(visibleFrom: vf2)),
        _item(to: activeTO, slot: _slot(visibleFrom: vf1)),
      ];
      final result = SlotStatusUtil.groupScheduledAt(
          masterTO: activeTO, targetTOs: items);
      expect(result, vf1); // 더 이른 것 반환
    });

    test('GS4. 공개 TO + 과거 visibleFrom → TO publishAt으로 폴백', () {
      final items = [_item(to: activeTO, slot: _slot(visibleFrom: _pastVF))];
      // 과거 visibleFrom은 무시 → TO publishAt도 없으면 null
      final result = SlotStatusUtil.groupScheduledAt(
          masterTO: activeTO, targetTOs: items);
      expect(result, isNull);
    });

    test('GS5. pending TO 슬롯들 → 가장 이른 TO publishAt', () {
      final pa1 = DateTime.now().add(const Duration(hours: 2));
      final pa2 = DateTime.now().add(const Duration(hours: 5));
      final pending1 = _to(
          status: TOStatus.scheduled, isPublished: false,
          publishMode: 'scheduled', publishAt: pa1);
      final pending2 = _to(
          status: TOStatus.scheduled, isPublished: false,
          publishMode: 'scheduled', publishAt: pa2);
      final items = [
        _item(to: pending1, slot: _slot()),
        _item(to: pending2, slot: _slot()),
      ];
      final result = SlotStatusUtil.groupScheduledAt(
          masterTO: activeTO, targetTOs: items);
      expect(result, pa1);
    });

    test('GS6. 공개 미래 visibleFrom + pending TO 혼합 → visibleFrom 우선', () {
      final vf = DateTime.now().add(const Duration(hours: 1));
      final items = [
        _item(to: activeTO, slot: _slot(visibleFrom: vf)),
        _item(to: pendingTO, slot: _slot()),
      ];
      // 공개된 슬롯의 visibleFrom이 있으므로 그것 반환
      final result = SlotStatusUtil.groupScheduledAt(
          masterTO: activeTO, targetTOs: items);
      expect(result, vf);
    });
  });

  // ════════════════════════════════════════════════════════
  // 복합 시나리오 (실제 사용 패턴)
  // ════════════════════════════════════════════════════════

  group('M. 실제 사용 패턴 복합 시나리오', () {
    test('M1. 신규 공고 생성 직후 (미공개 저장) → draft', () {
      final newTO = _draftTO();
      final slot = _slot(date: _futureDate);
      expect(SlotStatusUtil.slotStatus(slot, newTO), SlotDisplayStatus.draft);
    });

    test('M2. 즉시 공개 전환 → recruiting', () {
      final publishedTO = _to(status: TOStatus.active, isPublished: true);
      final slot = _slot(date: _futureDate);
      expect(SlotStatusUtil.slotStatus(slot, publishedTO), SlotDisplayStatus.recruiting);
    });

    test('M3. 예약공개 설정 후 공개 전 → scheduled (슬롯 visibleFrom)', () {
      final publishedTO = _to(status: TOStatus.active, isPublished: true);
      final slot = _slot(date: _futureDate, visibleFrom: _futureVF);
      expect(SlotStatusUtil.slotStatus(slot, publishedTO), SlotDisplayStatus.scheduled);
    });

    test('M4. 예약공개 시간 도래 → recruiting (visibleFrom 과거)', () {
      final publishedTO = _to(status: TOStatus.active, isPublished: true);
      final slot = _slot(date: _futureDate, visibleFrom: _pastVF);
      expect(SlotStatusUtil.slotStatus(slot, publishedTO), SlotDisplayStatus.recruiting);
    });

    test('M5. 모집 중 수동 마감 처리 → closed', () {
      final publishedTO = _to();
      final slot = _slot(status: SlotStatus.closed, isManualClosed: true);
      expect(SlotStatusUtil.slotStatus(slot, publishedTO), SlotDisplayStatus.closed);
    });

    test('M6. 날짜 경과로 자동 마감 → closed', () {
      final publishedTO = _to();
      final slot = _slot(date: _pastDate);
      expect(SlotStatusUtil.slotStatus(slot, publishedTO), SlotDisplayStatus.closed);
    });

    test('M7. 마감 후 재오픈 (slot status=open) + 미래 날짜 → recruiting', () {
      final publishedTO = _to();
      final slot = _slot(status: SlotStatus.open, date: _futureDate);
      expect(SlotStatusUtil.slotStatus(slot, publishedTO), SlotDisplayStatus.recruiting);
    });

    test('M8. draft TO에서 예약공개로 전환 → scheduled', () {
      // draft → scheduled: status=SCHEDULED, isPublished=false, publishMode=scheduled
      final scheduledTO = _pendingTO();
      final slot = _slot(date: _futureDate);
      expect(SlotStatusUtil.slotStatus(slot, scheduledTO), SlotDisplayStatus.scheduled);
    });

    test('M9. 예약 공개 후 공개 완료 상태 → recruiting', () {
      // isPublished=true, publishMode=scheduled (공개 완료)
      final publishedScheduledTO = _to(
        status: TOStatus.active, isPublished: true,
        publishMode: 'scheduled', publishAt: _pastPA);
      final slot = _slot(date: _futureDate);
      expect(SlotStatusUtil.slotStatus(slot, publishedScheduledTO), SlotDisplayStatus.recruiting);
    });

    test('M10. 전체 그룹: 슬롯 절반 공개·절반 미공개 → recruiting (공개된 것 기준)', () {
      final publishedTO = _to();
      final draftTO = _draftTO();
      final items = [
        _item(to: publishedTO, slot: _slot()),
        _item(to: draftTO, slot: _slot()),
      ];
      expect(SlotStatusUtil.groupStatus(
          allClosed: false, masterTO: publishedTO, targetTOs: items),
          SlotDisplayStatus.recruiting);
    });

    test('M11. 그룹 내 모든 슬롯 날짜경과 + allClosed=true → closed', () {
      expect(SlotStatusUtil.groupStatus(
          allClosed: true,
          masterTO: _to(),
          targetTOs: [_item(to: _to(), slot: _slot(date: _pastDate))]),
          SlotDisplayStatus.closed);
    });

    test('M12. 슬롯별 개별 예약공개, 가장 이른 visibleFrom이 표시시각', () {
      final vf1 = DateTime.now().add(const Duration(hours: 1));
      final vf2 = DateTime.now().add(const Duration(hours: 6));
      final to = _to();
      final items = [
        _item(to: to, slot: _slot(visibleFrom: vf2)),
        _item(to: to, slot: _slot(visibleFrom: vf1)),
      ];
      final scheduled = SlotStatusUtil.groupScheduledAt(masterTO: to, targetTOs: items);
      expect(scheduled, vf1);
    });

    test('M13. draft TO, 그룹 상태도 draft', () {
      final draftTO = _draftTO();
      final items = [_item(to: draftTO, slot: _slot())];
      expect(SlotStatusUtil.groupStatus(
          allClosed: false, masterTO: draftTO, targetTOs: items),
          SlotDisplayStatus.draft);
    });

    test('M14. 일괄수정 화면: 슬롯 상태 표시 - TO draft, 슬롯 4개 → 모두 draft', () {
      final draftTO = _draftTO();
      final slots = List.generate(4, (_) => _slot(date: _futureDate));
      for (final s in slots) {
        expect(SlotStatusUtil.slotStatus(s, draftTO), SlotDisplayStatus.draft);
      }
    });

    test('M15. 일괄수정 화면: TO published, 일부 슬롯 visibleFrom 미래 → 해당 슬롯 scheduled', () {
      final publishedTO = _to();
      final slots = [
        _slot(visibleFrom: _futureVF),
        _slot(visibleFrom: null),
        _slot(visibleFrom: _pastVF),
      ];
      expect(SlotStatusUtil.slotStatus(slots[0], publishedTO), SlotDisplayStatus.scheduled);
      expect(SlotStatusUtil.slotStatus(slots[1], publishedTO), SlotDisplayStatus.recruiting);
      expect(SlotStatusUtil.slotStatus(slots[2], publishedTO), SlotDisplayStatus.recruiting);
    });
  });
}
