// [R7-P4.4D] 첫 공고 writer → projection 계약.
//
//   이 파일의 규칙: **reader 를 통과시키기 위한 임의 fixture 를 만들지 않는다.**
//   공고 하나를 만드는 서버 writer(`callableCreateFlexSlots`)가 실제로 쓰는
//   형상을 한 곳(`_canonicalFirstPosting`)에서 만들고, 모든 reader 가 그
//   하나의 진실을 같게 계산하는지 본다. 각 test 가 자기 모양을 만들면
//   reader 끼리 어긋나도 전부 초록이 된다 — 그게 지금까지 놓친 방식이다.
//
//   writer 축은 소스를 직접 읽어 규칙으로 확인한다(CF 를 실행할 수 없으므로).
//   고정 길이 창(substring window)은 쓰지 않는다 — 코드가 옮겨가면 규칙과
//   무관하게 깨진다.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';

// ── 오늘을 고정하지 않는다. 날짜가 지나면 깨지는 fixture 를 만들지 않기 위해
//    모든 날짜는 기준일에 대한 상대값으로 만든다.
final DateTime _base = DateTime(2026, 1, 15);
String _key(int offsetDays) {
  final d = _base.add(Duration(days: offsetDays));
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

final String _today = _key(0);

// ───────────────────────────────────────────────────────────────
// 공유 canonical factory — 서버 writer 의 형상 하나
// ───────────────────────────────────────────────────────────────

/// 서버가 슬롯을 만들 때 업무 하나에 넣는 형상.
///
/// `wdId` 는 서버가 슬롯별로 새로 만들고 클라이언트 전달값을 무시한다
/// (`callableCreateFlexSlots`). 그래서 여기서도 wdId 를 반드시 준다 —
/// wdId 없는 workDetail 은 서버가 만든 슬롯에 존재하지 않는 모양이다.
WorkDetailData _canonicalWorkDetail({
  required String wdId,
  String workType = '홀서빙',
  int requiredCount = 10,
  String startTime = '09:00',
  String endTime = '18:00',
}) {
  return WorkDetailData(
    wdId: wdId,
    workType: workType,
    wage: 12000,
    requiredCount: requiredCount,
    startTime: startTime,
    endTime: endTime,
  );
}

/// 첫 공고 하나의 canonical 형상.
///
///   §15 초기 의미: 서버는 `workDetailCounts[wdId] = {confirmedCount: 0,
///   pendingCount: 0}` 를 **명시적으로** 넣는다. 0 은 "모름" 이 아니라 0 이다.
class _FirstPosting {
  _FirstPosting({
    required this.to,
    required this.slotWorkDetails,
    required this.workDetailCounts,
  });

  final TOModel to;
  final List<WorkDetailData> slotWorkDetails;
  final Map<String, Map<String, int>> workDetailCounts;
}

/// [§55] 한 factory 로 만든다. required = 10 / pending = 0 / confirmed = 0.
_FirstPosting _canonicalFirstPosting({
  List<String>? dates,
  int requiredCount = 10,
  int confirmed = 0,
  int pending = 0,
  int? totalSlotsOverride,
  String status = TOStatus.active,
  bool isPublished = true,
  bool isManualClosed = false,
  bool isDeleted = false,
}) {
  final slotDates = dates ?? [_key(1), _key(2)];
  // 서버 생성 ID 모양 — 클라이언트가 만든 composite 가 아니다.
  const wdId = 'wd_srv_0001';
  final wd = _canonicalWorkDetail(wdId: wdId, requiredCount: requiredCount);

  return _FirstPosting(
    to: TOModel(
      id: 'to-first',
      businessId: 'biz-1',
      businessName: '첫 사업장',
      title: '첫 공고',
      creatorUID: 'admin-1',
      type: TOType.flex,
      status: status,
      isPublished: isPublished,
      isManualClosed: isManualClosed,
      isDeleted: isDeleted,
      slotDateKeys: slotDates,
      // 서버가 슬롯을 만들 때 날짜 1건당 1 증가한다 → 날짜 수와 같다.
      totalSlots: totalSlotsOverride ?? slotDates.length,
      totalRequired: requiredCount * slotDates.length,
      totalConfirmed: confirmed,
      workDetails: [wd],
      createdAt: _base,
    ),
    slotWorkDetails: [wd],
    workDetailCounts: {
      wdId: {'confirmedCount': confirmed, 'pendingCount': pending},
    },
  );
}

String _cfSource() =>
    File('functions/src/index.ts').readAsStringSync();

void main() {
  // ═══════════════════════════════════════════════════════════
  // CP8 — writer 계약 (소스 규칙 확인)
  // ═══════════════════════════════════════════════════════════
  group('[R7-P4.4D] CP8 writer — 하나의 canonical writer', () {
    test('CP8-W01 슬롯 단위는 날짜 1건이다', () {
      final src = _cfSource();
      expect(src.contains('for (const dateStr of uniqueDates)'), isTrue,
          reason: '슬롯 루프가 날짜 단위여야 totalSlots 가 날짜 수와 같다');
      expect(src.contains('totalNewSlots++'), isTrue);
    });

    test('CP8-W02 wdId 는 서버가 만들고 클라이언트 전달값을 무시한다', () {
      final src = _cfSource();
      expect(src.contains('wdId: generateWdId()'), isTrue,
          reason: 'identity writer 가 하나여야 원장과 화면이 같은 키를 쓴다');
    });

    test('CP8-W03 초기 counts 는 명시적 0 이다 (모름 아님)', () {
      final src = _cfSource();
      expect(
        src.contains('{confirmedCount: 0, pendingCount: 0}'),
        isTrue,
        reason: '§15 — 0 을 쓰지 않고 비워두면 화면이 "모름" 과 구별할 수 없다',
      );
    });

    test('CP8-W04 생성 시 파생 집계는 0 으로 강제된다', () {
      final src = _cfSource();
      final flexBlock = RegExp(
        r'if \(finalData\.type === "flex"\) \{([^}]*)\}',
      ).firstMatch(src);
      expect(flexBlock, isNotNull);
      final body = flexBlock!.group(1)!;
      expect(body.contains('finalData.totalRequired = 0'), isTrue);
      expect(body.contains('finalData.totalSlots = 0'), isTrue,
          reason: '클라이언트가 보낸 값 + 슬롯 increment = 정확히 2배였다');
    });

    test('CP8-W05 날짜 목록도 클라이언트 씨앗을 지운다', () {
      final src = _cfSource();
      expect(src.contains('delete finalData.dates;'), isTrue,
          reason: 'dates 가 주입되면 slotDatesLookComplete 판정이 흔들린다');
      // 순서 계약: 카운터 강제와 같은 구간에 있어야 한다(분기 뒤로 새지 않게).
      expect(
        src.indexOf('delete finalData.dates;') <
            src.indexOf('finalData.editRevision = 0'),
        isTrue,
      );
    });

    test('CP8-W06 슬롯 커밋이 dates 를 같은 커밋에 싣는다', () {
      final src = _cfSource();
      final commit = RegExp(
        r'batch\.update\(toRef, \{([\s\S]{0,400}?)\}\);',
      ).firstMatch(src);
      expect(commit, isNotNull, reason: '슬롯 커밋의 TO 업데이트를 찾지 못했다');
      final body = commit!.group(1)!;
      expect(body.contains('totalSlots: admin.firestore.FieldValue.increment'),
          isTrue);
      expect(body.contains('dates: admin.firestore.FieldValue.arrayUnion'),
          isTrue,
          reason: 'dates 를 쓰는 writer 가 없어서 노출 판정이 항상 "모름" 이었다');
    });

    test('CP8-W07 슬롯 삭제가 dates 를 남은 문서에서 다시 센다', () {
      final src = _cfSource();
      expect(src.contains('const remainingDateKeys'), isTrue);
      expect(src.contains('dates: remainingDateKeys'), isTrue,
          reason: '카운터만 줄이면 지운 날짜가 목록에 남는다');
      // 추가 읽기 없이 이미 읽은 슬롯 집합을 쓴다.
      expect(
        src.contains('allSlotSnap.docs\n          .filter((d) => !uniqueSlotIdSet.has(d.id))'),
        isTrue,
        reason: '같은 read-set 에서 파생돼야 카운터와 어긋나지 않는다',
      );
    });

    test('CP8-W08 soft delete 는 노출 축까지 함께 닫는다', () {
      final src = _cfSource();
      final block = RegExp(
        r'isDeleted: true,([\s\S]{0,300}?)\}\)',
      ).firstMatch(src);
      expect(block, isNotNull);
      expect(block!.group(1)!.contains('isPublished: false'), isTrue,
          reason: '노출 쿼리는 isPublished 만 본다 — 여기서 같이 닫지 않으면 남는다');
    });
  });

  // ═══════════════════════════════════════════════════════════
  // CP9 — reader projection (하나의 factory, 같은 진실)
  // ═══════════════════════════════════════════════════════════
  group('[R7-P4.4D] CP9 projection — 모든 reader 가 같은 진실', () {
    test('CP9-R01 원장 키는 서버 wdId 다 — composite 로 되돌아가지 않는다', () {
      final p = _canonicalFirstPosting();
      final wd = p.slotWorkDetails.single;
      expect(wd.canonicalId, 'wd_srv_0001');
      expect(wd.canonicalId, isNot(wd.id),
          reason: 'composite id 와 달라야 정규화 지점이 실제로 동작한 것이다');
    });

    test('CP9-R02 required 10 / pending 0 / confirmed 0 — 같은 값을 읽는다', () {
      final p = _canonicalFirstPosting();
      final wd = p.slotWorkDetails.single;
      final counts = wd.lookupByIdentity(p.workDetailCounts);

      expect(wd.requiredCount, 10);
      expect(counts, isNotNull, reason: '서버가 만든 키로 찾지 못하면 화면이 빈다');
      expect(counts!['confirmedCount'], 0);
      expect(counts['pendingCount'], 0);
    });

    test('CP9-R03 0 과 모름을 구별한다', () {
      final p = _canonicalFirstPosting();
      final wd = p.slotWorkDetails.single;

      // 원장에 키가 있고 값이 0 → 0 명이다.
      expect(wd.lookupByIdentity(p.workDetailCounts), isNotNull);
      // 원장 자체가 없으면 null 이어야 한다 — 0 으로 꾸미지 않는다.
      expect(wd.lookupByIdentity<Map<String, int>>(null), isNull);
      expect(wd.lookupByIdentity(const <String, Map<String, int>>{}), isNull,
          reason: '비어 있는 원장을 0 명으로 읽으면 "아직 모름" 이 사라진다');
    });

    test('CP9-R04 legacy composite 원장도 같은 reader 로 찾는다', () {
      final p = _canonicalFirstPosting();
      final wd = p.slotWorkDetails.single;
      // wdId 가 없던 시절 문서는 composite 키로 기록돼 있다.
      final legacy = {wd.id: {'confirmedCount': 3, 'pendingCount': 1}};
      final found = wd.lookupByIdentity(legacy);
      expect(found, isNotNull,
          reason: 'fallback 이 없으면 옛 공고의 확정 인원이 화면에서 0 이 된다');
      expect(found!['confirmedCount'], 3);
    });

    test('CP9-R05 wdId 우선 — 두 키가 같이 있으면 canonical 을 읽는다', () {
      final p = _canonicalFirstPosting();
      final wd = p.slotWorkDetails.single;
      final mixed = {
        wd.canonicalId: {'confirmedCount': 2, 'pendingCount': 0},
        wd.id: {'confirmedCount': 99, 'pendingCount': 99},
      };
      expect(wd.lookupByIdentity(mixed)!['confirmedCount'], 2,
          reason: 'DEV 에서 양쪽 값이 갈렸다 — canonical 이 이긴다');
    });

    test('CP9-R06 날짜가 완비되고 전부 지났으면 숨긴다', () {
      final p = _canonicalFirstPosting(dates: [_key(-3), _key(-1)]);
      expect(p.to.slotDatesLookComplete, isTrue,
          reason: 'writer 가 dates 를 쓰므로 이제 판정이 가능하다');
      expect(p.to.isVisibleToWorkerFlex(_today), isFalse);
    });

    test('CP9-R07 하루라도 남아 있으면 보인다', () {
      final p = _canonicalFirstPosting(dates: [_key(-3), _key(2)]);
      expect(p.to.isVisibleToWorkerFlex(_today), isTrue);
    });

    test('CP9-R08 날짜가 뒤처져 있으면 숨기지 않는다 (fail-open)', () {
      // 슬롯이 3건인데 dates 에 1건만 기록된 상태(옛 문서).
      final p = _canonicalFirstPosting(
        dates: [_key(-5)],
        totalSlotsOverride: 3,
      );
      expect(p.to.slotDatesLookComplete, isFalse);
      expect(p.to.isVisibleToWorkerFlex(_today), isTrue,
          reason: '못 믿을 값으로 살아 있는 일자리를 지우지 않는다');
    });

    test('CP9-R09 첫 공고는 슬롯이 생기기 전까지 노출되지 않는다', () {
      final p = _canonicalFirstPosting(
        dates: const [],
        totalSlotsOverride: 0,
      );
      expect(p.to.hasNoSlotsAtAll, isTrue);
      expect(p.to.isVisibleToWorkerFlex(_today), isFalse,
          reason: '지원할 슬롯이 없으면 지원 자체가 불가능하다');
    });

    test('CP9-R10 soft delete 된 공고는 노출 축에서 빠진다', () {
      final p = _canonicalFirstPosting(isDeleted: true, isPublished: false);
      expect(p.to.isSoftDeleted, isTrue);
      expect(p.to.isVisibleToWorkerFlex(_today), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════
  // 소비자 keying 규칙 — 정규화 지점을 우회하는 reader 가 없다
  // ═══════════════════════════════════════════════════════════
  group('[R7-P4.4D] 소비자 keying — 우회 reader 없음', () {
    test('CP9-R11 슬롯 원장 seed 는 canonicalId 로 만든다', () {
      final src = File('lib/services/firestore_service.dart').readAsStringSync();
      expect(src.contains('for (final w in workDetails) w.canonicalId:'), isTrue,
          reason: 'seed 키가 composite 면 서버 원장과 한 칸도 만나지 못한다');
    });

    test('CP9-R12 정규화는 한 곳에서만 한다', () {
      final src =
          File('lib/models/core/work_detail_data.dart').readAsStringSync();
      expect(src.contains('map[canonicalId] ?? map[id]'), isTrue,
          reason: 'fallback 규칙이 여러 곳에 흩어지면 화면마다 달라진다');
    });

    test('CP9-R13 노출 판정은 TOModel 하나가 소유한다', () {
      final jobTab =
          File('lib/screens/user/tabs/user_job_tab.dart').readAsStringSync();
      expect(jobTab.contains('to.isVisibleToWorkerFlex(todayKey)'), isTrue,
          reason: '화면이 자기 규칙을 다시 쓰면 서버 게이트와 어긋난다');
    });
  });
}
