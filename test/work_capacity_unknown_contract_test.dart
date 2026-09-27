import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/work_detail_data.dart';
import 'package:ALfit/models/ui/work_capacity_reading.dart';

/// [R7-4 C3~C7] 정원을 **모르는 것**과 **0인 것**을 구분한다.
///
///   서버는 이미 같은 규칙으로 산다 — `getWorkDetailCount` 는 wdId 는 있는데
///   카운터 항목이 없으면 `failed-precondition` 으로 막고, 주석에 이유를
///   적어 두었다: *"fail-open(0/0)은 '정원 여유 있음'으로 오판 → 정원 초과
///   지원 허용하는 보안 버그."*
///
///   클라이언트는 같은 miss 를 `?? 0` 으로 접고 있었다. 그래서 자리가 다 찬
///   업무가 `잔여 5명`이 되고, 정원이 찬 업무에서 승인 버튼이 열렸다.

String _src(String p) {
  final f = File(p);
  if (!f.existsSync()) throw StateError('source not found: $p');
  return f.readAsStringSync();
}

/// 주석을 걷어낸 코드 본문 — 설명 문장이 계약 증거로 잘못 잡히지 않게 한다.
String _codeOf(String body) => body
    .split('\n')
    .where((l) => !l.trimLeft().startsWith('//'))
    .join('\n');

WorkDetailData _wd({
  String? wdId,
  String workType = '홀서빙',
  String startTime = '09:00',
  String endTime = '18:00',
  int requiredCount = 2,
}) =>
    WorkDetailData(
      wdId: wdId,
      workType: workType,
      startTime: startTime,
      endTime: endTime,
      requiredCount: requiredCount,
      wage: 12000,
      wageType: 'hourly',
    );

void main() {
  // ═══════════════════════════════════════════════════════════════
  // A. 판독기 — UNKNOWN / canonical zero / known positive
  // ═══════════════════════════════════════════════════════════════
  group('WCR-A 정원 판독', () {
    test('A-1 canonical 0 은 아는 0 이다 — 모른다가 아니다', () {
      final w = _wd(wdId: 'wd-1');
      final r = WorkCapacityReading.read(w, {
        'wd-1': {'confirmed': 0, 'pending': 0},
      });
      expect(r.isKnown, isTrue);
      expect(r.confirmed, 0);
      expect(r.remaining, 2);
      expect(r.isFull, isFalse);
    });

    test('A-2 known positive — 정원에 닿으면 FULL', () {
      final w = _wd(wdId: 'wd-1');
      final r = WorkCapacityReading.read(w, {
        'wd-1': {'confirmed': 2, 'pending': 3},
      });
      expect(r.confirmed, 2);
      expect(r.pending, 3);
      expect(r.remaining, 0);
      expect(r.isFull, isTrue);
    });

    test('A-3 identity miss 는 0 이 아니라 UNKNOWN', () {
      // 원장은 wdId 로 집계하는데 화면이 **다른 wdId 의 업무 정의**를 들고 있다.
      final w = _wd(wdId: 'wd-master-다른값');
      final r = WorkCapacityReading.read(w, {
        'wd-slot-001': {'confirmed': 2, 'pending': 0},
      });
      expect(r.isKnown, isFalse);
      expect(r.confirmed, isNull);
      expect(r.remaining, isNull, reason: '잔여를 말할 수 없다');
      expect(r.isFull, isFalse, reason: '모르는 것을 마감이라 하지 않는다');
      expect(r.canAdmit(1), isNull, reason: '판단할 수 없다고 답해야 한다');
    });

    test('A-4 map 자체가 없으면 UNKNOWN', () {
      expect(WorkCapacityReading.read(_wd(wdId: 'wd-1'), null).isKnown, isFalse);
    });

    test('A-5 statsFailed 면 map 이 있어도 UNKNOWN', () {
      final w = _wd(wdId: 'wd-1');
      final r = WorkCapacityReading.read(
        w,
        {
          'wd-1': {'confirmed': 2, 'pending': 0}
        },
        statsFailed: true,
      );
      expect(r.isKnown, isFalse);
    });

    test('A-6 wdId 가 없으면 composite 로 찾는다 (legacy)', () {
      final w = _wd();
      final r = WorkCapacityReading.read(w, {
        '홀서빙_09:00_18:00': {'confirmed': 1, 'pending': 0},
      });
      expect(r.isKnown, isTrue);
      expect(r.confirmed, 1);
    });

    test('A-7 canonical 우선, composite 폴백 — 둘 다 있으면 canonical', () {
      final w = _wd(wdId: 'wd-1');
      final r = WorkCapacityReading.read(w, {
        'wd-1': {'confirmed': 2, 'pending': 0},
        '홀서빙_09:00_18:00': {'confirmed': 99, 'pending': 0},
      });
      expect(r.confirmed, 2);
    });

    test('A-8 필요 인원은 통계와 무관하게 안다', () {
      final r = WorkCapacityReading.read(_wd(wdId: 'x', requiredCount: 5), null);
      expect(r.isKnown, isFalse);
      expect(r.requiredCount, 5, reason: '업무 정의에서 오는 값이다');
    });

    test('A-9 정원 0 은 제한 없음 — 아는 경우에만', () {
      final w = _wd(wdId: 'wd-1', requiredCount: 0);
      final r = WorkCapacityReading.read(w, {
        'wd-1': {'confirmed': 3, 'pending': 0},
      });
      expect(r.isFull, isFalse);
      expect(r.canAdmit(10), isTrue);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // B. 승인 관문 — C5(단건) / C6(일괄) 이 같은 판정을 쓴다
  // ═══════════════════════════════════════════════════════════════
  group('WCR-B 승인 전 정원 관문', () {
    test('B-1 모르면 막고, 그 이유를 "충족"이라 말하지 않는다', () {
      final reason =
          capacityBlockReason(confirmed: null, requiredCount: 2, addCount: 1);
      expect(reason, isNotNull);
      expect(reason, contains('확인하지 못했'));
      expect(reason, isNot(contains('충족')),
          reason: 'UNKNOWN 을 FULL 로 바꿔 말하지 않는다');
      expect(reason, contains('새로고침'), reason: '복구 경로를 안내한다');
    });

    test('B-2 아는 0 은 막지 않는다 — 자리가 있다', () {
      expect(
          capacityBlockReason(confirmed: 0, requiredCount: 2, addCount: 1),
          isNull);
    });

    test('B-3 정원이 찼으면 충족으로 막는다', () {
      final reason =
          capacityBlockReason(confirmed: 2, requiredCount: 2, addCount: 1);
      expect(reason, contains('이미 충족'));
    });

    test('B-4 일괄이 남은 자리를 넘으면 실제 수치로 막는다', () {
      final reason =
          capacityBlockReason(confirmed: 1, requiredCount: 3, addCount: 3);
      expect(reason, contains('초과'));
      expect(reason, contains('현재 1명 확정'));
      expect(reason, contains('2명 추가 가능'));
    });

    test('B-5 남은 자리와 정확히 같으면 통과한다', () {
      expect(
          capacityBlockReason(confirmed: 1, requiredCount: 3, addCount: 2),
          isNull);
    });

    test('B-6 단건과 일괄이 같은 함수를 쓴다', () {
      final d = _codeOf(_src(
          'lib/screens/business_admin/dialogs/work_applicants_dialog.dart'));
      // 두 호출부가 모두 공통 관문을 거친다.
      expect('_capacityBlockReason('.allMatches(d).length, greaterThanOrEqualTo(3),
          reason: '정의 1 + 단건 1 + 일괄 1');
      // 옛 지역 산술이 남아 있지 않다.
      expect(d.contains("stats?['confirmed'] ?? 0"), isFalse);
      expect(d.contains("(stats?['confirmed'] as int?) ?? 0"), isFalse);
    });
  });

  // ═══════════════════════════════════════════════════════════════
  // C. 각 consumer 가 판독기로 전환됐다
  // ═══════════════════════════════════════════════════════════════
  group('WCR-C consumer 전환', () {
    test('C3 업무별 마감 관리 — UNKNOWN 을 진행중으로 내려앉히지 않는다', () {
      final d = _codeOf(_src(
          'lib/screens/business_admin/dialogs/work_detail_management_dialog.dart'));
      expect(d.contains("static const String unknown     = 'UNKNOWN';"), isTrue);
      expect(d.contains('if (!reading.isKnown) return _WDS.unknown;'), isTrue);
      // 정원에 기대는 action 을 UNKNOWN 에서 열지 않는다.
      expect(d.contains('case _WDS.unknown:'), isTrue);
      expect(d.contains("text: '정원 확인 필요'"), isTrue);
      expect(d.contains("'label': '확인 필요'"), isTrue);
      // 옛 fail-open 산술이 사라졌다.
      expect(d.contains("stats?['confirmed'] ?? 0"), isFalse);
      expect(d.contains("stats?['pending'] ?? 0"), isFalse);
    });

    test('C3 라벨이 마감·시간만료와 겹치지 않는다', () {
      final d = _codeOf(_src(
          'lib/screens/business_admin/dialogs/work_detail_management_dialog.dart'));
      // 이미 있는 상태들을 UNKNOWN 이 덮어쓰지 않는다 — 정의만으로 정해지는
      // 판정은 통계와 무관하게 그대로 답한다.
      final unknownAt = d.indexOf('if (!reading.isKnown) return _WDS.unknown;');
      final expiredAt = d.indexOf('if (work.isTimeExpired) return _WDS.timeExpired;');
      final closedAt = d.indexOf('if (work.isClosed) return _WDS.closed;');
      expect(expiredAt, greaterThan(0));
      expect(closedAt, greaterThan(0));
      expect(unknownAt, greaterThan(expiredAt));
      expect(unknownAt, greaterThan(closedAt));
    });

    test('C4 공고 상세 — map 존재를 known 으로 쓰지 않는다', () {
      final jp = _codeOf(_src('lib/screens/common/job_posting_screen.dart'));
      expect(jp.contains('widget.workDetailStats != null'), isFalse);
      expect(jp.contains('final reading = WorkCapacityReading.read('), isTrue);
      expect(jp.contains('final workAvailable = reading.remaining;'), isTrue);
    });

    test('C4 master 정의에 slot stats 를 짝지어 넘기지 않는다', () {
      final g = _codeOf(
          _src('lib/widgets/admin/cards/admin_to_group_card.dart'));
      // 정의가 master 로 떨어지는 분기에서는 slot stats 를 붙이지 않는다.
      // (저장소가 CRLF 이므로 줄바꿈·들여쓰기에 기대지 않고 공백을 접어 본다.)
      final flat = g.replaceAll(RegExp(r'\s+'), ' ');
      expect(
          flat.contains(
              'workDetailStats: calSlot.workDetails.isNotEmpty '
              '? calSlot.workDetailStats : null,'),
          isTrue);
      expect(flat.contains('workDetailStats: calSlot.workDetailStats, '), isFalse,
          reason: '무조건 slot stats 를 넘기던 자리가 남아 있으면 안 된다');
    });

    test('C7 초대 시트 — 확정 수를 모르면 숫자를 적지 않는다', () {
      final s = _codeOf(_src(
          'lib/screens/business_admin/dialogs/available_workers_bottom_sheet.dart'));
      expect(s.contains('final int? confirmedCount;'), isTrue);
      expect(s.contains("'정원 \${widget.requiredCount}명 · 확정 인원 확인 불가'"),
          isTrue);
      final d = _codeOf(_src(
          'lib/screens/business_admin/dialogs/work_applicants_dialog.dart'));
      expect(d.contains('confirmedCount: _canonicalConfirmed,'), isTrue);
      expect(d.contains('confirmedCount: _canonicalConfirmed ?? 0,'), isFalse);
    });

    test('C7 workDetailId 는 composite 그대로 둔다 — 서버가 그렇게 매칭한다', () {
      final d = _codeOf(_src(
          'lib/screens/business_admin/dialogs/work_applicants_dialog.dart'));
      // 서버 `callableGetAvailableWorkers` 는 workDetailId 를
      // `workType_startTime_endTime` 또는 workType 으로 맞춘 뒤 wdId 를 역산한다.
      // canonicalId(wdId) 를 넘기면 매칭에 실패해 첫 업무로 폴백한다.
      expect(d.contains('workDetailId: work.id,'), isTrue);
      expect(d.contains('workDetailId: work.canonicalId,'), isFalse);
    });
  });
}
