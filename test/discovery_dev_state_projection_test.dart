// [R7-APPLICATION-LIFECYCLE.1D] DEV 의 canonical 상태를 **production
// projection** 에 먹여, 지원자 화면이 말할 모집 truth 를 고정한다.
//
// ── 증거 등급 ───────────────────────────────────────────────────
//   입력은 DEV(alfit-89567)에서 **실제 writer** 로 만든 문서를 그대로 export
//   한 것이다(`test/fixtures/d1_discovery_state.json`).
//     callableCreateTO → callableCreateFlexSlots → callablePublishTO
//     → callableApplyToTO/callableConfirmApplication(정원 채움)
//     → callableCloseSlots / callableReopenSlots
//   판정은 화면이 쓰는 그 함수(`HomeRecruitableProjection.build`)다.
//
//   Flutter 화면을 기기에 띄운 것이 아니므로 이 파일은
//   **DEV STATE VERIFIED + CODE PROJECTION VERIFIED** 등급이다 —
//   RENDER/PRODUCT 라고 쓰지 않는다.
//
// ── 고정하는 불변식 ─────────────────────────────────────────────
//   · FLEX 의 날짜는 서로 독립이다 — FULL 한 날짜가 OPEN 날짜를 지우지 않고,
//     CLOSED 한 날짜도 다른 날짜를 닫지 않는다.
//   · 한 날짜 안에서도 업무는 독립이다 — 정원이 찬 업무가 형제 업무를
//     지우지 않는다.
//   · 닫힌 날짜는 모집에서 빠지고, 재오픈하면 돌아온다.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ALfit/models/core/application_model.dart';
import 'package:ALfit/models/core/slot_model.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/screens/user/home_recruitable_projection.dart';
import 'package:ALfit/utils/format_helper.dart';

const _fixture = 'test/fixtures/d1_discovery_state.json';

Map<String, dynamic> _load() {
  final f = File(_fixture);
  expect(f.existsSync(), isTrue, reason: '$_fixture 를 찾지 못함');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

/// KST 달력일 문자열 → projection 이 쓰는 키(utc 정규화).
DateTime _day(String s) {
  final p = s.split('-').map(int.parse).toList();
  return DateTime.utc(p[0], p[1], p[2]);
}

/// KST 자정 instant — Firestore 저장 규약과 같은 값.
DateTime _kstMidnight(String s) =>
    _day(s).subtract(const Duration(hours: 9));

WorkDetailData _wd(Map<String, dynamic> w) => WorkDetailData(
      wdId: w['wdId'] as String,
      workType: (w['startTime'] as String) == '09:00' ? '홀서빙' : '주방',
      workTypeIcon: 'box',
      workTypeColor: '#000000',
      workTypeBackgroundColor: '#FFFFFF',
      wage: 12000,
      wageType: 'hourly',
      requiredCount: (w['requiredCount'] as num).toInt(),
      startTime: w['startTime'] as String,
      endTime: w['endTime'] as String,
    );

/// DEV 문서 → `TOModel`. 공개 술어가 보는 필드를 그대로 옮긴다.
TOModel _toModel(String toId, Map<String, dynamic> st) => TOModel(
      id: toId,
      businessId: 'bizDev',
      businessName: '런타임사업장',
      type: st['type'] as String,
      title: '런타임 공고',
      creatorUID: 'adminDev',
      status: st['status'] as String,
      deadlineType: 'NONE',
      hoursBeforeStart: 0,
      workDetails: const [],
      totalRequired: ((st['totalRequired'] ?? 0) as num).toInt(),
      totalConfirmed: ((st['totalConfirmed'] ?? 0) as num).toInt(),
      totalPending: 0,
      isPublished: st['isPublished'] as bool,
      publishMode: 'immediate',
      slotDateKeys:
          ((st['slotDates'] ?? const []) as List).cast<String>(),
      totalSlots: (st['slots'] as List).length,
      createdAt: DateTime(2027, 10, 1),
      statusUpdatedAt: DateTime(2027, 10, 1),
    );

/// DEV 슬롯 문서 → `SlotModel`.
List<SlotModel> _slots(String toId, Map<String, dynamic> st,
    {Map<String, Map<String, int>> confirmedOverride = const {}}) {
  return (st['slots'] as List).map((raw) {
    final s = raw as Map<String, dynamic>;
    final counts = <String, SlotWorkTypeCount>{};
    final rawCounts = (s['workDetailCounts'] ?? {}) as Map<String, dynamic>;
    for (final e in rawCounts.entries) {
      final v = e.value as Map<String, dynamic>;
      final over = confirmedOverride[s['date'] as String]?[e.key];
      counts[e.key] = SlotWorkTypeCount(
        confirmedCount: over ?? ((v['confirmedCount'] ?? 0) as num).toInt(),
        pendingCount: ((v['pendingCount'] ?? 0) as num).toInt(),
      );
    }
    return SlotModel(
      id: s['id'] as String,
      toId: toId,
      date: _kstMidnight(s['date'] as String),
      workDetails:
          ((s['workDetails'] ?? const []) as List).map((w) =>
              _wd(w as Map<String, dynamic>)).toList(),
      workDetailCounts: counts,
      status: s['status'] as String,
    );
  }).toList();
}

HomeRecruitableProjection _project(
  String toId,
  Map<String, dynamic> st, {
  List<ApplicationModel> apps = const [],
  Map<String, Map<String, int>> confirmedOverride = const {},
}) {
  final to = _toModel(toId, st);
  return HomeRecruitableProjection.build(
    publishedTos: [to],
    myApplications: apps,
    today: _day('2027-11-01'),
    cutoff: _day('2027-12-31'),
    slotsByToId: {
      toId: _slots(toId, st, confirmedOverride: confirmedOverride),
    },
  );
}

void main() {
  late Map<String, dynamic> fx;
  late String toId;
  late String dFull;
  late String dOpen;
  late String dClosed;

  setUpAll(() {
    fx = _load();
    toId = fx['toId'] as String;
    final dates = fx['dates'] as Map<String, dynamic>;
    dFull = dates['full'] as String;
    dOpen = dates['open'] as String;
    dClosed = dates['closed'] as String;
  });

  group('D1-R1 Create → 공개 상태', () {
    test('R1-1 DEV 가 공개 canonical 상태를 만들었다', () {
      final st = fx['r1'] as Map<String, dynamic>;
      expect(st['isPublished'], isTrue);
      expect(st['status'], anyOf('ACTIVE', 'FULL'));
      expect(st['isDeleted'], anyOf(isNull, isFalse));
      final slotDates = (st['slots'] as List)
          .map((s) => (s as Map<String, dynamic>)['date'])
          .toSet();
      expect(slotDates, {dFull, dOpen, dClosed});
      for (final s in st['slots'] as List) {
        expect((s as Map<String, dynamic>)['status'], 'open');
      }
    });

    test('R1-2 홈 projection 이 세 날짜 모두 모집으로 본다', () {
      final p = _project(toId, fx['r1'] as Map<String, dynamic>);
      for (final d in [dFull, dOpen, dClosed]) {
        expect(p.isRecruitable(toId, _day(d)), isTrue, reason: d);
      }
      expect(p.hasAnyDate(toId), isTrue);
    });
  });

  group('D1-R2 FLEX 날짜·업무 독립', () {
    test('R2-1 DEV 상태 — FULL 날짜의 한 업무만 찼고 다른 날짜는 그대로다', () {
      final st = fx['r2'] as Map<String, dynamic>;
      final byDate = {
        for (final s in st['slots'] as List)
          (s as Map<String, dynamic>)['date'] as String: s,
      };
      final wdByDate = fx['wdByDate'] as Map<String, dynamic>;
      final fullA = (wdByDate['full'] as Map<String, dynamic>)['a'] as String;
      final fullB = (wdByDate['full'] as Map<String, dynamic>)['b'] as String;

      final full = byDate[dFull]!;
      final counts = full['workDetailCounts'] as Map<String, dynamic>;
      expect((counts[fullA] as Map)['confirmedCount'], 1,
          reason: '정원 1인 업무가 찼다');
      expect((counts[fullB] as Map)['confirmedCount'], 0,
          reason: '형제 업무는 그대로다');
      expect(full['status'], 'open', reason: '한 업무가 찼다고 날짜가 닫히지 않는다');
      expect(byDate[dOpen]!['status'], 'open');
      expect(byDate[dClosed]!['status'], 'closed');
    });

    test('R2-2 FULL 날짜는 형제 업무 때문에 여전히 모집이다', () {
      final p = _project(toId, fx['r2'] as Map<String, dynamic>);
      expect(p.isRecruitable(toId, _day(dFull)), isTrue,
          reason: '정원이 찬 업무가 형제 업무를 지우지 않는다');
    });

    test('R2-3 그 날짜의 **모든** 업무가 차면 그 날짜만 빠진다', () {
      // 파생 입력 — DEV 상태가 아니라 projection 입력 한 축을 바꾼 것이다.
      //   (형제 업무까지 정원을 채운 경우를 보기 위함)
      final wdByDate = fx['wdByDate'] as Map<String, dynamic>;
      final fullB = (wdByDate['full'] as Map<String, dynamic>)['b'] as String;
      final p = _project(
        toId,
        fx['r2'] as Map<String, dynamic>,
        confirmedOverride: {dFull: {fullB: 5}},
      );
      expect(p.isRecruitable(toId, _day(dFull)), isFalse);
      // 다른 날짜는 그대로다 — 이것이 이 셀의 핵심이다.
      expect(p.isRecruitable(toId, _day(dOpen)), isTrue);
    });

    test('R2-4 OPEN 날짜는 모집, CLOSED 날짜는 아니다', () {
      final p = _project(toId, fx['r2'] as Map<String, dynamic>);
      expect(p.isRecruitable(toId, _day(dOpen)), isTrue);
      expect(p.isRecruitable(toId, _day(dClosed)), isFalse);
    });

    test('R2-5 CLOSED 날짜가 다른 날짜를 닫지 않는다', () {
      final p = _project(toId, fx['r2'] as Map<String, dynamic>);
      expect(p.hasAnyDate(toId), isTrue);
      expect(p.countOn(_day(dOpen)), 1);
      expect(p.countOn(_day(dClosed)), 0);
    });
  });

  group('D1-R3 Close → Reopen', () {
    test('R3-1 닫으면 그 날짜가 모집에서 빠진다', () {
      final st = fx['r3_closed'] as Map<String, dynamic>;
      final byDate = {
        for (final s in st['slots'] as List)
          (s as Map<String, dynamic>)['date'] as String: s,
      };
      expect(byDate[dOpen]!['status'], 'closed', reason: 'DEV 상태');
      final p = _project(toId, st);
      expect(p.isRecruitable(toId, _day(dOpen)), isFalse);
    });

    test('R3-2 재오픈하면 돌아온다', () {
      final st = fx['r3_reopened'] as Map<String, dynamic>;
      final byDate = {
        for (final s in st['slots'] as List)
          (s as Map<String, dynamic>)['date'] as String: s,
      };
      expect(byDate[dOpen]!['status'], 'open', reason: 'DEV 상태');
      final p = _project(toId, st);
      expect(p.isRecruitable(toId, _day(dOpen)), isTrue);
    });

    test('R3-3 닫기·재오픈이 다른 날짜를 건드리지 않는다', () {
      final closed = _project(toId, fx['r3_closed'] as Map<String, dynamic>);
      final reopened =
          _project(toId, fx['r3_reopened'] as Map<String, dynamic>);
      // FULL 날짜는 형제 업무 덕에 두 상태 모두 모집이다.
      expect(closed.isRecruitable(toId, _day(dFull)), isTrue);
      expect(reopened.isRecruitable(toId, _day(dFull)), isTrue);
      // CLOSED 날짜는 두 상태 모두 아니다.
      expect(closed.isRecruitable(toId, _day(dClosed)), isFalse);
      expect(reopened.isRecruitable(toId, _day(dClosed)), isFalse);
    });
  });

  group('D1-E 읽기 실패 ≠ 0', () {
    test('E1 슬롯을 못 읽은 날짜는 0 으로 바뀌지 않는다', () {
      // 슬롯을 전달하지 않는다 = 읽지 못한 상태.
      final st = fx['r2'] as Map<String, dynamic>;
      final p = HomeRecruitableProjection.build(
        publishedTos: [_toModel(toId, st)],
        myApplications: const [],
        today: _day('2027-11-01'),
        cutoff: _day('2027-12-31'),
      );
      for (final d in [dFull, dOpen, dClosed]) {
        expect(p.isRecruitable(toId, _day(d)), isTrue,
            reason: '$d — 모르는 것을 "모집 없음" 으로 바꾸지 않는다');
      }
    });

    test('E2 날짜 목록이 불완전하면 공고를 지우지 않는다', () {
      final st = Map<String, dynamic>.from(fx['r2'] as Map<String, dynamic>);
      st['slotDates'] = const <String>[]; // dates 를 모른다
      final p = _project(toId, st);
      expect(p.hasAnyDate(toId), isTrue);
    });
  });

  group('D1-S 입력 출처', () {
    test('S1 fixture 는 DEV 실제 writer 산출물이다', () {
      // 서버가 슬롯·날짜별로 **새 wdId** 를 발급한다는 사실이 그 증거다 —
      //   harness 가 넣은 상수(`rt_disc1d_wdA`)는 어디에도 없다.
      final raw = File(_fixture).readAsStringSync();
      expect(raw.contains('rt_disc1d_wd'), isFalse);
      final wdByDate = fx['wdByDate'] as Map<String, dynamic>;
      final ids = <String>{};
      for (final v in wdByDate.values) {
        final m = v as Map<String, dynamic>;
        ids.addAll([m['a'] as String, m['b'] as String]);
      }
      expect(ids.length, 6, reason: '날짜 3 × 업무 2 = 서로 다른 6개');
    });

    test('S2 projection 은 화면이 쓰는 그 함수다', () {
      final src = File('lib/screens/user/user_home_screen.dart')
          .readAsStringSync();
      expect(src.contains('HomeRecruitableProjection.build('), isTrue);
      // 이 테스트가 같은 입력 축을 쓴다.
      expect(src.contains('slotsByToId: _slotsByToId'), isTrue);
      expect(src.contains('publishedTos: _publishedTos'), isTrue);
    });
  });

  group('D1-K KST 규약', () {
    test('K1 DEV 슬롯 날짜는 KST 자정 instant 로 저장된다', () {
      // export 는 KST 달력일 문자열로 담았고, 모델은 instant 로 되돌린다.
      //   그 instant 를 다시 KST 로 읽으면 같은 날짜가 나와야 한다.
      for (final d in [dFull, dOpen, dClosed]) {
        expect(FormatHelper.toKstDate(_kstMidnight(d)), _day(d), reason: d);
      }
    });
  });
}
