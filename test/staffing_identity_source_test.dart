// [R7 STAFFING AUDIT] 업무 정의의 **identity 원천**이 집계와 맞는가.
//
//   사용자 재현: `[R7FIX] 한 날짜만 마감` 9/29 tile 1/1 → 날짜 선택 후 0/1,
//   상세 `충원 0 · 미충원 1`, 상단은 `충원 1` 유지.
//
//   원장(DEV, READ ONLY)은 정확했다.
//     toId EKICbhyyNlGtLRrEMLwc  type=flex
//     slot N2UxClha (2026-09-29) status=full confirmedCount=1
//       slot.workDetails  = [{wdId: "xyhBqRBwnNRuLovGIYsL", req: 1}]
//       workDetailCounts  = {"xyhBqRBwnNRuLovGIYsL": {confirmedCount: 1}}
//     application         status=CONTRACT_PENDING wdId="xyhBqRBwnNRuLovGIYsL"
//     master to.workDetails = [{사무업무 10:00~16:00, req 1}]   ← **wdId 없음**
//
//   즉 FLEX 는 업무 정의 원천이 둘이고 서로 다른 identity 를 갖는다. master
//   정의로 조회하면 `workDetailCounts`/지원서의 wdId 와 절대 만나지 못한다.
//
//   DEV 전수 대조(businessId fLmSOHVKUwmBHcbwQE0I, TO 93 · slot 172):
//     slot 정의에 wdId 있음            172/172
//     master 정의에 wdId 전혀 없음      25 TO
//     원천에 따라 값이 갈리는 자리      17  (slot=원장값, master=0)
//   `[R6.1] Clean Golden Path` 는 **양쪽 다 wdId 가 있는데 값이 다르다**
//   (slot `xw87EbAh…` vs master `rBnNxCMg…`) — slot 생성 시 새로 만들기 때문이다.
//
//   기대값은 계산식 복제가 아니라 **원장 사례**에서 온다: 확정 1건이 그 slot 의
//   그 업무에 붙어 있으므로 1/1 이다.

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/admin_to_list_ui_models.dart';

DateTime _kst(int y, int m, int d) =>
    DateTime.utc(y, m, d).subtract(const Duration(hours: 9));

/// 원장 그대로: slot 정의는 wdId 를 갖고, master 정의는 갖지 않는다.
const _slotWdId = 'xyhBqRBwnNRuLovGIYsL';

WorkDetailData _def({String? wdId}) => WorkDetailData(
      workType: '사무업무',
      startTime: '10:00',
      endTime: '16:00',
      requiredCount: 1,
      wage: 12000,
      wdId: wdId,
    );

TOModel _flexMaster() => TOModel(
      id: 'EKICbhyyNlGtLRrEMLwc',
      businessId: 'biz1',
      businessName: '위워커',
      type: 'flex',
      title: '[R7FIX] 한 날짜만 마감',
      creatorUID: 'uid1',
      status: TOStatus.active,
      deadlineType: 'HOURS_BEFORE',
      hoursBeforeStart: 2,
      // master 에는 wdId 가 없다 — 원장 그대로.
      workDetails: [_def()],
      totalRequired: 2,
      totalConfirmed: 1,
      totalPending: 0,
      createdAt: _kst(2026, 9, 1),
      statusUpdatedAt: _kst(2026, 9, 1),
    );

SlotModel _slot0929() => SlotModel(
      id: 'N2UxClhaBW7zhc6ThXKs',
      toId: 'EKICbhyyNlGtLRrEMLwc',
      date: _kst(2026, 9, 29),
      status: 'full',
      confirmedCount: 1,
      pendingCount: 0,
      workDetails: [_def(wdId: _slotWdId)],
      createdAt: _kst(2026, 9, 1),
    );

/// `loadTOWorkDetails` 가 만드는 집계.
///
///   [R7 STAFFING AUDIT] seed 와 지원서 키가 모두 **canonicalId** 다.
///   이 slot 의 정의는 wdId 를 가지므로 seed 도 wdId 이고, 지원서(`app.wdId`)와
///   같은 자리에서 만난다 → `{confirmed: 1}`.
///   예전에는 seed 가 composite 여서 `사무업무_10:00_16:00: {0,0}` 라는 유령
///   항목이 함께 있었고, `lookupByIdentity` 의 composite 폴백이 그것을 집어
///   조회 실패를 `0` 으로 바꿨다.
Map<String, Map<String, int>> _statsFromLedger() => {
      _slotWdId: {'confirmed': 1, 'pending': 0},
    };

void main() {
  group('IDS-A 원장 사례 — 9/29 는 1/1 이다', () {
    test('IDS-A1 slot 정의를 가진 TOItem 은 1 을 본다', () {
      final item = TOItem(
        to: _flexMaster(),
        slot: _slot0929(),
        workDetails: [_def(wdId: _slotWdId)],
        confirmedCount: 1,
        pendingCount: 0,
        totalRequired: 1,
        workDetailStats: _statsFromLedger(),
        isWorkDetailLoaded: true,
      );
      final s = item.resolveStats();
      expect((s.confirmed, s.required, s.shortage), (1, 1, 0));
      expect(item.hasLoadedStats, isTrue);
      expect(item.resolvedIsFull, isTrue);
    });

    test('IDS-A2 정의가 비어 있어도 **0 이라고 말하지 않는다**', () {
      // 이것이 재현된 결함이다. 정의가 아직 없으면 예전 코드는 master 로
      // 폴백했고, master 의 identity 는 이 집계와 만나지 못해 `충원 0` 이
      // 됐다. 지금은 카운터(slot.confirmedCount = 1)로 내려간다.
      final item = TOItem(
        to: _flexMaster(),
        slot: _slot0929(),
        confirmedCount: 1, // slot 카운터 — 원장값
        pendingCount: 0,
        totalRequired: 1,
        workDetailStats: _statsFromLedger(),
        isWorkDetailLoaded: true,
      );
      expect(item.statsAlignedWorkDetails, isEmpty,
          reason: 'slot 이 있으면 master 정의는 이 집계의 identity 가 아니다');
      expect(item.hasLoadedStats, isFalse,
          reason: '집계를 쓸 수 없다 — 화면은 모름/카운터로 내려간다');
      final s = item.resolveStats();
      expect(s.confirmed, 1, reason: '거짓 0 이 아니라 원장 카운터를 말한다');
      expect(s.shortage, 0);
    });

    test('IDS-A3 master 정의(다른 identity)로 조회해도 0 이 되지 않는다', () {
      // slot 생성 시 새 wdId 를 만들므로 master 의 wdId 가 있어도 다르다.
      final item = TOItem(
        to: _flexMaster(),
        slot: _slot0929(),
        workDetails: [_def(wdId: 'rBnNxCMgHfQadU1kRN9K')], // 다른 wdId
        confirmedCount: 1,
        pendingCount: 0,
        totalRequired: 1,
        workDetailStats: _statsFromLedger(),
        isWorkDetailLoaded: true,
      );
      final s = item.resolveStats();
      expect(s.confirmed, 1,
          reason: '조회가 빗나가면 집계를 버리고 카운터를 쓴다 — 0 을 만들지 않는다');
    });
  });

  group('IDS-B 장기(slot 없음) 는 master 가 유일한 원천이다', () {
    TOModel contract() => TOModel(
          id: 'to_contract',
          businessId: 'biz1',
          businessName: '위워커',
          type: 'contract',
          title: '[R7FIX] 장기 근무 공고',
          creatorUID: 'uid1',
          status: TOStatus.active,
          deadlineType: 'HOURS_BEFORE',
          hoursBeforeStart: 2,
          workDetails: [
            WorkDetailData(
                workType: '사무업무',
                startTime: '06:00',
                endTime: '08:00',
                requiredCount: 2,
                wage: 12000),
          ],
          totalRequired: 2,
          totalConfirmed: 0,
          totalPending: 0,
          createdAt: _kst(2026, 9, 1),
          statusUpdatedAt: _kst(2026, 9, 1),
        );

    test('IDS-B1 DEVICE.1D 의 master 폴백이 그대로 살아 있다', () {
      // slot 이 없으므로 master 정의가 집계의 identity 와 같다(composite).
      final item = TOItem(
        to: contract(),
        confirmedCount: 9, // 낡은 카운터
        pendingCount: 9,
        totalRequired: 2,
        workDetailStats: const {
          '사무업무_06:00_08:00': {'confirmed': 0, 'pending': 0}
        },
        isWorkDetailLoaded: true,
      );
      expect(item.statsAlignedWorkDetails, hasLength(1));
      expect(item.hasLoadedStats, isTrue);
      final s = item.resolveStats();
      expect((s.confirmed, s.required, s.shortage), (0, 2, 2),
          reason: '집계가 있으면 카운터를 쓰지 않는다');
    });

    test('IDS-B2 실패한 집계는 여전히 카운터로 내려간다', () {
      final item = TOItem(
        to: contract(),
        confirmedCount: 1,
        pendingCount: 0,
        totalRequired: 2,
        workDetailStats: const {
          '사무업무_06:00_08:00': {'confirmed': 0, 'pending': 0}
        },
        isWorkDetailLoaded: true,
        workDetailStatsFailed: true,
      );
      expect(item.hasLoadedStats, isFalse);
      expect(item.resolveStats().confirmed, 1);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // IDS-E §2A — 상태별 authoritative definition
  //
  //   `slot 존재만으로 loaded 를 가정하지 않는다.` 각 상태에서 무엇이 권위이고
  //   **최종적으로 known 으로 회복하는지**를 고정한다.
  //   (수정으로 문제를 UNKNOWN 에만 옮겨 영구 로딩으로 만들지 않는다)
  // ══════════════════════════════════════════════════════════════

  group('IDS-E 정의 원천 상태표', () {
    TOItem item({
      SlotModel? slot,
      List<WorkDetailData>? defs,
      Map<String, Map<String, int>>? stats,
      bool failed = false,
      int counterConfirmed = 1,
    }) {
      final i = TOItem(
        to: _flexMaster(),
        slot: slot,
        workDetails: defs,
        confirmedCount: counterConfirmed,
        pendingCount: 0,
        totalRequired: 1,
        workDetailStats: stats,
        isWorkDetailLoaded: defs != null,
        workDetailStatsFailed: failed,
      );
      return i;
    }

    test('IDS-E1 slot + 정의 로드 성공 → slot 정의가 권위, known', () {
      final i = item(
          slot: _slot0929(),
          defs: [_def(wdId: _slotWdId)],
          stats: _statsFromLedger());
      expect(i.statsAlignedWorkDetails.single.canonicalId, _slotWdId);
      expect(i.hasLoadedStats, isTrue);
      expect(i.resolveStats().confirmed, 1);
    });

    test('IDS-E2 slot + 정의 미로드 → 권위 없음, 카운터로 말하고 provenance 정직', () {
      // 이 상태에서는 `workDetailStats` 도 아직 없다(둘은 `setWorkDetails` 가
      // 함께 세운다). 그래서 영구 UNKNOWN 이 아니라 카운터 구간이다.
      final i = item(slot: _slot0929(), defs: null, stats: null);
      expect(i.statsAlignedWorkDetails, isEmpty);
      expect(i.hasLoadedStats, isFalse, reason: 'provenance = 카운터');
      expect(i.resolveStats().confirmed, 1, reason: 'slot 카운터 = 원장값');
    });

    test('IDS-E3 정의가 로드되면 같은 item 이 known 으로 회복한다', () {
      // `setWorkDetails` 는 정의와 집계를 **함께** 세운다 — 둘의 identity 가
      // 같은 호출에서 나오므로 어긋날 수 없다.
      final i = item(slot: _slot0929(), defs: null, stats: null);
      expect(i.hasLoadedStats, isFalse);
      i.setWorkDetails([_def(wdId: _slotWdId)], _statsFromLedger());
      expect(i.hasLoadedStats, isTrue, reason: 'UNKNOWN 에 갇히지 않는다');
      expect(i.resolveStats().confirmed, 1);
    });

    test('IDS-E4 slot 정의가 문서에 없으면 loader 가 master 로 정의·집계를 함께 만든다', () {
      // `loadTOWorkDetails` 는 `slotWorkDetails` 가 비면 `to.workDetails` 로
      // 정의와 seed 를 **둘 다** 만든다. 그래서 identity 가 어긋나지 않는다.
      final masterDefs = _flexMaster().workDetails;
      final seededFromMaster = {
        for (final w in masterDefs) w.canonicalId: {'confirmed': 0, 'pending': 0},
      };
      final i = item(
          slot: _slot0929(), defs: masterDefs, stats: seededFromMaster);
      expect(i.hasLoadedStats, isTrue);
      expect(i.resolveStats().confirmed, 0,
          reason: '이 경로의 집계는 지원서를 만나지 못했을 뿐 known 0 이다');
    });

    test('IDS-E5 정의 조회 실패 → 카운터, provenance false', () {
      final i = item(
          slot: _slot0929(),
          defs: [_def(wdId: _slotWdId)],
          stats: _statsFromLedger(),
          failed: true);
      expect(i.hasLoadedStats, isFalse);
      expect(i.resolveStats().confirmed, 1);
    });

    test('IDS-E6 slot 없음(장기) → master 가 권위', () {
      final i = item(slot: null, defs: null, stats: null);
      expect(i.statsAlignedWorkDetails, hasLength(1),
          reason: 'slot 이 없으면 master 정의가 유일한 원천이다');
    });

    test('IDS-E7 같은 type/time 이지만 다른 wdId 는 다른 업무다', () {
      final a = _def(wdId: 'wd_A');
      final b = _def(wdId: 'wd_B');
      expect(a.canonicalId, isNot(b.canonicalId));
      expect(a.id, b.id, reason: 'composite 는 같다 — 그래서 composite 로는 구분 못 한다');
      final stats = {'wd_A': {'confirmed': 1, 'pending': 0}};
      expect(a.lookupByIdentity(stats), isNotNull);
      expect(b.lookupByIdentity(stats), isNull,
          reason: 'composite 폴백이 A 의 값을 B 에 주면 안 된다');
    });

    test('IDS-E8 required 와 confirmed 가 같은 identity 를 쓴다', () {
      // 정의의 requiredCount 와 집계의 confirmed 가 같은 업무에서 와야 한다.
      final defs = [_def(wdId: _slotWdId)];
      final i = item(
          slot: _slot0929(), defs: defs, stats: _statsFromLedger());
      final s = i.resolveStats();
      expect(s.required, defs.single.requiredCount);
      expect(s.confirmed, _statsFromLedger()[_slotWdId]!['confirmed']);
      expect(s.shortage, 0);
    });
  });

  group('IDS-D producer seed 키', () {
    test('IDS-D1 wdId 가 있으면 canonicalId(=wdId) 로 seed 된다', () {
      // `loadTOWorkDetails` 의 seed 식과 같은 표현을 실행한다.
      final defs = [_def(wdId: _slotWdId)];
      final seeded = {
        for (final w in defs) w.canonicalId: const {'confirmed': 0, 'pending': 0},
      };
      expect(seeded.keys, [_slotWdId]);
      expect(seeded.containsKey('사무업무_10:00_16:00'), isFalse,
          reason: 'composite 유령 항목이 생기면 조회 실패가 0 으로 바뀐다');
    });

    test('IDS-D2 wdId 가 없으면 composite 로 seed 된다', () {
      final defs = [_def()];
      final seeded = {
        for (final w in defs) w.canonicalId: const {'confirmed': 0, 'pending': 0},
      };
      expect(seeded.keys, ['사무업무_10:00_16:00']);
    });

    test('IDS-D3 identity 가 다른 정의는 아무것도 찾지 못한다', () {
      final stats = _statsFromLedger();
      expect(_def(wdId: 'rBnNxCMgHfQadU1kRN9K').lookupByIdentity(stats), isNull);
      expect(_def().lookupByIdentity(stats), isNull);
      expect(_def(wdId: _slotWdId).lookupByIdentity(stats), isNotNull);
    });
  });

  group('IDS-C 부분 miss', () {
    test('IDS-C1 업무 둘 중 하나만 맞으면 집계를 쓰지 않는다', () {
      final to = _flexMaster();
      final item = TOItem(
        to: to,
        slot: _slot0929(),
        workDetails: [
          _def(wdId: _slotWdId), // 맞음
          WorkDetailData(
              workType: '조리',
              startTime: '10:00',
              endTime: '16:00',
              requiredCount: 2,
              wage: 12000,
              wdId: 'unknown_wd'), // 집계에 없음
        ],
        confirmedCount: 1,
        pendingCount: 0,
        totalRequired: 3,
        workDetailStats: _statsFromLedger(),
        isWorkDetailLoaded: true,
      );
      final s = item.resolveStats();
      expect(s.confirmed, 1, reason: '카운터로 내려간다');
      expect(s.required, 3, reason: 'totalRequired 를 쓴다');
      // 부분 집계로 `충원 1 / 필요 3 · 부족 2` 를 주장하지 않는다.
      // [2차] provenance 도 사실대로다 — 이 수치는 집계가 아니라 카운터에서
      //   나왔으므로 `hasLoadedStats` 는 false 여야 한다.
      //   (§2C: summary 가 counter 로 알려진 것이 child 별 분배의 증거는 아니다)
      expect(item.hasLoadedStats, isFalse,
          reason: '카운터로 말하면서 "집계에서 나왔다" 고 보고하면 안 된다');
    });
  });
}
