// [R7-P1-2 DEVICE.1A] 같은 공고가 두 숫자를 말했다.
//
//   실기기에서 같은 장기공고 한 장에:
//
//     요약        확정 1 / 필요 2 / 부족 1
//     업무 상세    확정 0 / 미충원 2 / 0-2
//
//   DEV 의 실제 지원서를 세어 보니 canonical 은 **1** 이었다.
//   (CANCELED 1건 제외, CONTRACT_PENDING 1건 · staffingReleased 아님,
//    identity `사무업무_06:00_08:00` 이 workDetail 과 정확히 일치)
//
//   원인은 identity 도, 갱신 이력도, 기간 필터도 아니었다.
//
//     업무별 집계를 **아무도 불러오지 않았고**,
//     행은 그 null 을 `?? 0` 으로 받아 0명이라고 단정했다.
//     같은 상황에서 요약은 TO 카운터로 폴백해 1이라고 말했다.
//
//   즉 UNKNOWN 이 한쪽에서는 0, 다른 쪽에서는 실제값이 됐다.
//   숫자를 맞추려고 한쪽을 복사하지 않는다 — 모르는 것을 모른다고 말하게 하고,
//   실제로 불러와서 둘 다 canonical 을 보게 한다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

String _codeOf(String dart) => dart
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  expect(i, greaterThan(-1), reason: '구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  expect(j, greaterThan(i), reason: '구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

// ── 집계 복제 — `FirestoreService.loadTOWorkDetails` 와 같은 규칙 ────

class App {
  const App({
    required this.status,
    required this.workType,
    required this.start,
    required this.end,
    this.wdId,
    this.workDetailId,
    this.staffingReleased = false,
  });
  final String status;
  final String workType;
  final String start;
  final String end;
  final String? wdId;
  final String? workDetailId;
  final bool staffingReleased;
}

class WorkDetail {
  const WorkDetail({
    required this.workType,
    required this.start,
    required this.end,
    required this.required,
    this.wdId,
  });
  final String workType;
  final String start;
  final String end;
  final int required;
  final String? wdId;

  String get id => '${workType}_${start}_$end';
  String get canonicalId => wdId ?? id;
}

const _activeStatuses = {'PENDING', 'CONFIRMED', 'CONTRACT_PENDING'};
const _confirmedStatuses = {'CONFIRMED', 'CONTRACT_PENDING'};

/// 업무별 집계. **업무마다 0으로 미리 채운다** — 그래서 진짜 0명은 `{0,0}` 이고
/// null 은 오직 "아직 모른다" 뿐이다. 이 구분이 이번 결함의 핵심이다.
Map<String, Map<String, int>> aggregate(
    List<WorkDetail> details, List<App> apps) {
  final stats = <String, Map<String, int>>{
    for (final w in details) w.id: {'confirmed': 0, 'pending': 0},
  };
  for (final a in apps) {
    if (!_activeStatuses.contains(a.status) || a.staffingReleased) continue;
    final legacy = a.workDetailId;
    final key = (a.wdId != null && a.wdId!.isNotEmpty)
        ? a.wdId!
        : (legacy != null && legacy.isNotEmpty && legacy != a.workType)
            ? legacy
            : '${a.workType}_${a.start}_${a.end}';
    stats[key] ??= {'confirmed': 0, 'pending': 0};
    if (_confirmedStatuses.contains(a.status)) {
      stats[key]!['confirmed'] = stats[key]!['confirmed']! + 1;
    } else {
      stats[key]!['pending'] = stats[key]!['pending']! + 1;
    }
  }
  return stats;
}

Map<String, int>? lookup(WorkDetail w, Map<String, Map<String, int>>? m) =>
    m == null ? null : (m[w.canonicalId] ?? m[w.id]);

int _clamp(int n) => n > 0 ? n : 0;

/// 요약 — `TOItem.resolveStats()` 의 업무별 경로.
({int confirmed, int pending, int required, int shortage}) summaryOf(
    List<WorkDetail> details, Map<String, Map<String, int>> stats) {
  var c = 0, p = 0, r = 0, s = 0;
  for (final w in details) {
    final st = lookup(w, stats);
    final wc = st?['confirmed'] ?? 0;
    c += wc;
    p += st?['pending'] ?? 0;
    r += w.required;
    s += _clamp(w.required - wc); // clamp-before-sum
  }
  return (confirmed: c, pending: p, required: r, shortage: s);
}

/// 업무 상세 행 — 같은 집계를 같은 helper 로 본다.
({int confirmed, int pending, int unfilled, bool unknown}) rowOf(
    WorkDetail w, Map<String, Map<String, int>>? stats) {
  final st = lookup(w, stats);
  if (st == null) {
    // 모르면 숫자를 주장하지 않는다.
    return (confirmed: 0, pending: 0, unfilled: 0, unknown: true);
  }
  final c = st['confirmed']!;
  return (
    confirmed: c,
    pending: st['pending']!,
    unfilled: _clamp(w.required - c),
    unknown: false,
  );
}

void main() {
  // DEV 의 실제 공고 zqaJEjUVPA6O1FWajlTX 를 그대로 옮긴 것.
  const devWork = WorkDetail(
      workType: '사무업무', start: '06:00', end: '08:00', required: 2);
  const devApps = [
    App(status: 'CANCELED', workType: '사무업무', start: '06:00', end: '08:00'),
    App(
        status: 'CONTRACT_PENDING',
        workType: '사무업무',
        start: '06:00',
        end: '08:00'),
  ];

  // ══════════════════════════════════════════════════════════════
  // A·B·C. 단일 업무 장기공고 parity (§9)
  // ══════════════════════════════════════════════════════════════

  group('LSP-A 단일 업무 parity', () {
    test('LSP-A 실기기 공고 그대로 — required=2 confirmed=1', () {
      final stats = aggregate([devWork], devApps);
      final s = summaryOf([devWork], stats);
      final r = rowOf(devWork, stats);

      expect(s.confirmed, 1, reason: 'CANCELED 는 세지 않는다');
      expect(r.confirmed, 1);
      expect(s.confirmed, r.confirmed, reason: '요약 == 업무 상세');
      expect(s.required, r.unfilled + r.confirmed);
      expect(s.shortage, 1);
      expect(r.unfilled, 1);
      expect(r.unknown, isFalse);
    });

    test('LSP-B confirmed=0 이면 둘 다 0 · shortage=2', () {
      final stats = aggregate([devWork], const [
        App(status: 'CANCELED', workType: '사무업무', start: '06:00', end: '08:00'),
      ]);
      final s = summaryOf([devWork], stats);
      final r = rowOf(devWork, stats);
      expect(s.confirmed, 0);
      expect(r.confirmed, 0);
      expect(r.unknown, isFalse, reason: '불러온 결과가 0명인 것은 아는 상태다');
      expect(s.shortage, 2);
      expect(r.unfilled, 2);
    });

    test('LSP-C 대기(PENDING) parity', () {
      final stats = aggregate([devWork], const [
        App(status: 'PENDING', workType: '사무업무', start: '06:00', end: '08:00'),
        App(
            status: 'CONTRACT_PENDING',
            workType: '사무업무',
            start: '06:00',
            end: '08:00'),
      ]);
      final s = summaryOf([devWork], stats);
      final r = rowOf(devWork, stats);
      expect(s.pending, 1);
      expect(r.pending, 1);
      expect(s.confirmed, 1);
      expect(r.confirmed, 1);
      // 확정과 대기를 더해 자리를 채운 것처럼 말하지 않는다.
      expect(r.unfilled, 1);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // D·E·F. identity
  // ══════════════════════════════════════════════════════════════

  group('LSP-D identity', () {
    test('LSP-E CONTRACT 지원서에 wdId 가 없어도 composite 로 만난다', () {
      // 실제 DEV 값: wdId · workDetailId 둘 다 없음.
      expect(devApps[1].wdId, isNull);
      expect(devApps[1].workDetailId, isNull);
      final stats = aggregate([devWork], devApps);
      expect(stats.keys, contains('사무업무_06:00_08:00'));
      expect(devWork.canonicalId, '사무업무_06:00_08:00');
      expect(lookup(devWork, stats)?['confirmed'], 1);
    });

    test('LSP-F FLEX wdId 경로 회귀 없음', () {
      const flex = WorkDetail(
          workType: '홀서빙',
          start: '09:00',
          end: '18:00',
          required: 3,
          wdId: 'wd_abc123');
      final stats = aggregate([flex], const [
        App(
            status: 'CONFIRMED',
            workType: '홀서빙',
            start: '09:00',
            end: '18:00',
            wdId: 'wd_abc123'),
      ]);
      // canonicalId(wdId) 로 먼저 찾는다.
      expect(lookup(flex, stats)?['confirmed'], 1);
      expect(flex.canonicalId, 'wd_abc123');
    });

    test('LSP-D 여러 업무 — 각자의 자리로 간다', () {
      const a = WorkDetail(
          workType: '사무업무', start: '06:00', end: '08:00', required: 2);
      const b = WorkDetail(
          workType: '사무업무', start: '13:00', end: '18:00', required: 1);
      final stats = aggregate([a, b], const [
        App(
            status: 'CONFIRMED',
            workType: '사무업무',
            start: '06:00',
            end: '08:00'),
        App(
            status: 'CONFIRMED',
            workType: '사무업무',
            start: '13:00',
            end: '18:00'),
        App(
            status: 'CONFIRMED',
            workType: '사무업무',
            start: '13:00',
            end: '18:00'),
      ]);
      expect(rowOf(a, stats).confirmed, 1);
      expect(rowOf(b, stats).confirmed, 2);
      // 같은 업무명이라도 시간이 다르면 다른 자리다.
      expect(rowOf(a, stats).unfilled, 1);
      expect(rowOf(b, stats).unfilled, 0);
    });

    test('LSP-D2 초과 확정이 다른 업무의 부족을 상쇄하지 않는다 (§10)', () {
      const a = WorkDetail(
          workType: '사무업무', start: '06:00', end: '08:00', required: 2);
      const b = WorkDetail(
          workType: '사무업무', start: '13:00', end: '18:00', required: 1);
      final stats = aggregate([a, b], const [
        App(
            status: 'CONFIRMED',
            workType: '사무업무',
            start: '13:00',
            end: '18:00'),
        App(
            status: 'CONFIRMED',
            workType: '사무업무',
            start: '13:00',
            end: '18:00'),
        App(
            status: 'CONFIRMED',
            workType: '사무업무',
            start: '13:00',
            end: '18:00'),
      ]);
      final s = summaryOf([a, b], stats);
      // b 가 1명 정원에 3명 — 그 초과가 a 의 부족 2를 지우면 안 된다.
      expect(s.shortage, 2, reason: 'clamp-before-sum');
      expect(rowOf(a, stats).unfilled, 2);
      expect(rowOf(b, stats).unfilled, 0);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // G·H·I. 제외 규칙
  // ══════════════════════════════════════════════════════════════

  group('LSP-G 제외', () {
    test('LSP-H CANCELED / AUTO_CANCELED 는 세지 않는다', () {
      for (final st in ['CANCELED', 'AUTO_CANCELED', 'REJECTED', 'EXPIRED']) {
        final stats = aggregate([devWork],
            [App(status: st, workType: '사무업무', start: '06:00', end: '08:00')]);
        expect(rowOf(devWork, stats).confirmed, 0, reason: st);
        expect(rowOf(devWork, stats).pending, 0, reason: st);
      }
    });

    test('LSP-I 좌석 반납(staffingReleased)은 정원을 소모하지 않는다', () {
      final stats = aggregate([devWork], const [
        App(
            status: 'CONFIRMED',
            workType: '사무업무',
            start: '06:00',
            end: '08:00',
            staffingReleased: true),
      ]);
      expect(rowOf(devWork, stats).confirmed, 0);
      expect(rowOf(devWork, stats).unfilled, 2);
    });

    test('LSP-G 갱신 OLD/NEW 이중 계상 없음', () {
      // OLD 는 종료(EXPIRED), NEW 만 살아 있다 — 한 자리로 센다.
      final stats = aggregate([devWork], const [
        App(status: 'EXPIRED', workType: '사무업무', start: '06:00', end: '08:00'),
        App(
            status: 'CONTRACT_PENDING',
            workType: '사무업무',
            start: '06:00',
            end: '08:00'),
      ]);
      expect(rowOf(devWork, stats).confirmed, 1);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // UNKNOWN != ZERO — 이번 결함의 본체
  // ══════════════════════════════════════════════════════════════

  group('LSP-U UNKNOWN', () {
    test('LSP-U1 미로드는 0명이 아니다', () {
      final r = rowOf(devWork, null);
      expect(r.unknown, isTrue);
      expect(r.unfilled, 0,
          reason: '모르면서 미충원 2 라고 말하는 것이 결함이었다');
    });

    test('LSP-U2 불러온 0 과 모르는 것은 다른 상태다', () {
      final loaded = aggregate([devWork], const []);
      expect(lookup(devWork, loaded), isNotNull, reason: '업무마다 0으로 미리 채운다');
      expect(rowOf(devWork, loaded).unknown, isFalse);
      expect(rowOf(devWork, null).unknown, isTrue);
    });

    test('LSP-U3 화면이 null 을 0 으로 단정하지 않는다', () {
      for (final path in [
        'lib/widgets/admin/cards/admin_to_group_card.dart',
        'lib/widgets/admin/cards/admin_to_item_card.dart',
      ]) {
        final code = _codeOf(_read(path));
        // WorkDetailRow 에 넘기는 statsFailed 가 null 을 함께 본다.
        expect(code, contains('stats == null'),
            reason: '$path — 미로드를 0명으로 말한다');
      }
    });

    test('LSP-U4 집계를 실제로 불러온다', () {
      final card =
          _codeOf(_read('lib/widgets/admin/cards/admin_to_group_card.dart'));
      expect(card, contains('_ensureSingleTOStats()'));
      final fn = _slice(card, 'void _ensureSingleTOStats() {',
          'Future<void> _retrySingleTOStats()');
      // 한 번만, 그리고 기존 경로를 재사용한다.
      expect(fn, contains('_singleStatsRequested'));
      expect(fn, contains('_retrySingleTOStats()'));
      expect(fn, contains('g.isWorkDetailLoaded'));
      // 슬롯 카드는 건드리지 않는다.
      expect(fn, contains('widget.calendarSlot != null'));
      expect(fn, contains('widget.groupItem.groupTOs.isNotEmpty'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // J. 같은 helper 재사용 / 가짜 수정 금지
  // ══════════════════════════════════════════════════════════════

  group('LSP-J 가짜 수정 금지 (§11)', () {
    late String card;
    setUpAll(() {
      card = _codeOf(_read('lib/widgets/admin/cards/admin_to_group_card.dart'));
    });

    test('LSP-J1 요약값을 업무 행에 복사하지 않았다', () {
      // `TOItem(...)` 합성부의 `confirmedCount: groupItem.totalConfirmed` 는
      //   요약 폴백의 정당한 source 다 — 여기서 보는 것은 **WorkDetailRow** 뿐이다.
      final sites = <String>[];
      var from = 0;
      while (true) {
        final i = card.indexOf('WorkDetailRow(', from);
        if (i < 0) break;
        sites.add(card.substring(i, (i + 600).clamp(0, card.length)));
        from = i + 1;
      }
      expect(sites.length, greaterThanOrEqualTo(2),
          reason: 'WorkDetailRow 생성부를 읽지 못했다');
      for (final s in sites) {
        final v = RegExp(r'confirmedCount:\s*([^,\n]+)').firstMatch(s)?.group(1);
        expect(v, isNotNull);
        expect(v!, isNot(contains('totalConfirmed')),
            reason: 'TO 카운터를 업무 행에 복사했다: $v');
        expect(v, contains('stats'),
            reason: '업무 행은 업무별 집계에서만 숫자를 가져온다: $v');
      }
    });

    test('LSP-J2 +1 보정이나 fixture 예외가 없다', () {
      for (final banned in ['R7FIX', 'confirmed + 1', '+ 1;  //']) {
        expect(card, isNot(contains(banned)), reason: '가짜 보정: $banned');
      }
    });

    test('LSP-J3 identity helper 를 그대로 쓴다 — 새 매칭 규칙 없음', () {
      expect(card, contains('lookupByIdentity'));
      final wd = _codeOf(_read('lib/models/core/work_detail_data.dart'));
      expect(wd, contains('String get canonicalId => wdId ?? id;'));
      expect(wd, contains("String get id => '\${workType}_\${startTime}_\$endTime';"));
    });

    test('LSP-J4 집계 규칙을 새로 만들지 않았다', () {
      final svc = _codeOf(_read('lib/services/firestore_service.dart'));
      expect(svc, contains("const activeStatuses = {'PENDING', 'CONFIRMED', 'CONTRACT_PENDING'}"));
      expect(svc, contains('!a.isStaffingReleased'));
      // 업무마다 0으로 미리 채우는 계약 — null 과 0 의 구분이 여기서 나온다.
      expect(svc,
          contains("for (final w in workDetails) w.id: {'confirmed': 0, 'pending': 0}"));
    });
  });
}
