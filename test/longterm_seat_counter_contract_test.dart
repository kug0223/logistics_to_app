// [R7-P1-2 DEVICE.1C] 끝난 관계가 서버 정원까지 막고 있었다.
//
//   DEVICE.1B 는 화면의 좌석 투영을 고쳤다. 그런데 서버는 그대로였다.
//
//     required = 2
//     현재 좌석 = 0        (9/22 에 끝난 약속 하나)
//     workTypeConfirmedCounts.사무업무 = 1
//     → 확정 가드가 1명만 허용
//
//   2명이 필요한 자리의 한 칸이 5일 전 끝난 관계에 영구 점유돼 있었다.
//   정원과 같은 수가 끝나 있으면 대체 확정이 아예 막히고, 막히면 status
//   변경이 없어 재계산도 일어나지 않는다 — 스스로 풀리지 않는 상태다.
//
//   ── 어느 모델인가 (§11) ────────────────────────────────────────
//
//   가드는 `totalConfirmed` 가 아니라 `workTypeConfirmedCounts` 를 읽고,
//   그 값은 재계산이 절대값으로 덮어쓴다. 즉 이 카운터들은 **현재 좌석
//   카운터**다(OPTION A). 결함은 그 재계산이 좌석 반납은 보면서 기간
//   종료는 보지 않았다는 것이다.
//
//   그래서 status 를 바꾸지 않는다. 이력은 이력대로 두고 좌석만 비운다.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

String _read(String p) => File(p).readAsStringSync();

// [R7-APPLICATION-LIFECYCLE.1C.1] 장기 약속 날짜 규칙의 canonical 위치.
const _cdPath = 'functions/src/commitment_dates.ts';

String _slice(String src, String start, String end) {
  final i = src.indexOf(start);
  expect(i, greaterThan(-1), reason: '구간 시작을 찾지 못했다: $start');
  final j = src.indexOf(end, i + start.length);
  expect(j, greaterThan(i), reason: '구간 끝을 찾지 못했다: $end');
  return src.substring(i, j);
}

void main() {
  late String cf;

  setUpAll(() => cf = _read('functions/src/index.ts'));

  // ══════════════════════════════════════════════════════════════
  // B·C. 좌석 재계산이 기간 종료를 본다
  // ══════════════════════════════════════════════════════════════

  group('SEAT-B 재계산', () {
    late String counter;
    setUpAll(() {
      counter = _slice(cf, 'function srvOccupiesSeatToday(',
          '[.6-P3] 근무 한 건의 canonical 달력 값');
    });

    test('SEAT-B1 effectiveEnd 식이 클라이언트·서버와 같다', () {
      expect(counter, contains('d.get("actualResignDate") ??'));
      expect(counter, contains('d.get("workEndDate")'));
      // 기존 canonical 판정도 그대로 살아 있다.
      expect(_read(_cdPath),
          contains('const end = resign ?? asDate(appData["workEndDate"]);'));
      final model = _read('lib/models/core/application_model.dart');
      expect(model,
          contains('DateTime? get effectiveEndDate => actualResignDate ?? workEndDate;'));
    });

    test('SEAT-B2 단기는 날짜 축이 없다', () {
      expect(counter, contains('if (d.get("type") !== "long_term") return true;'));
    });

    test('SEAT-B3 기간을 모르면 좌석을 빼앗지 않는다', () {
      expect(counter, contains('if (!end || typeof end.toDate !== "function") return true;'));
    });

    test('SEAT-B4 좌석 반납 축은 그대로다', () {
      // [R7-7] 반납 축은 좌석 판정 함수가 아니라 **세는 쪽**에 있다.
      //   판정 함수는 기간만 본다 — 두 축이 분리된 것이 계약이다.
      expect(cf, contains('if (d.get("staffingReleasedAt") != null) continue;'),
          reason: '공고 단위 집계');
      expect(cf, contains('if (d.get("staffingReleasedAt") != null) return;'),
          reason: '슬롯 범위 transactional writer');
      expect(cf, contains('if (!occupiesSeatToday(d)) continue;'));
      expect(cf, contains('if (!occupiesSeatToday(d)) return;'));
    });

    test('SEAT-C 업무별 카운터가 같은 좌석 정의를 쓴다', () {
      // 가드가 직접 읽는 값이다 — 여기서 갈라지면 정원이 틀어진다.
      expect(cf, contains('seats.byWorkType.get(wt) ?? 0'));
      // status 만 세던 count() 질의는 사라졌다.
      expect(cf,
          isNot(contains('.where("selectedWorkType", "==", wt)\n          .where("status", "in", CONFIRMED_STATUSES)\n          .count()')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // I·J. 확정 가드
  // ══════════════════════════════════════════════════════════════

  group('SEAT-I 확정 가드', () {
    test('SEAT-I 가드가 읽는 값이 현재 좌석 카운터다', () {
      final guard = _slice(cf, '// 비-슬롯 TO capacity', '정원이 초과되었습니다');
      expect(guard, contains('workTypeConfirmedCounts'));
      expect(guard, isNot(contains('totalConfirmed')),
          reason: 'TO 합계는 가드 기준이 아니다 — 기존 계약 유지');
    });

    test('SEAT-J FULL 은 실제 정원에서만 난다', () {
      expect(cf, contains('if (req > 0 && conf >= req)'));
      // conf 가 현재 좌석이 됐으므로 FULL 시점이 실제 정원과 일치한다.
      expect(cf, contains('seats.byWorkType.get(wt) ?? 0'));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // 시간 축 — 트리거만으로는 풀리지 않는다
  // ══════════════════════════════════════════════════════════════

  group('SEAT-T 시간 축', () {
    test('SEAT-T1 트리거는 문서 변화에만 반응한다', () {
      // 이 사실이 스케줄러가 필요한 이유다 — 날짜가 지나는 것만으로는
      // 아무 문서도 바뀌지 않으니 트리거가 깨어나지 않는다.
      //
      // [R7-FS-1 E2] 앵커를 옮겼다. 조건이 **넓어졌다**: status 말고
      //   좌석 표식(seatMark)이 바뀌어도 깨운다. "반납도 재계산을
      //   깨운다" 는 뒤의 수정이다. 성질(문서가 안 바뀌면 안 깨어난다)은
      //   그대로이므로 그것을 확인한다.
      expect(cf,
          contains('if (beforeStatus === afterStatus && !seatMarkChanged) '
              'return;'));
    });

    test('SEAT-T2 D+1 좌석 재조정이 자정 작업에 있다', () {
      expect(cf, contains('processExpiredSeatReconciliation(timestamp),'));
      expect(cf, contains('"좌석 재조정"'));
      final fn = _slice(cf,
          'async function processExpiredSeatReconciliation(',
          '// 🔥 통합 마스터 스케줄러');
      // 카운터만 만진다 — 상태·이력은 건드리지 않는다.
      expect(fn, contains('_syncTOCounters(toId)'));
      for (final banned in [
        '.delete()',
        'status: "CANCELED"',
        'attendance',
        'wageStatus',
      ]) {
        expect(fn, isNot(contains(banned)),
            reason: '좌석 재조정이 이력을 건드린다: $banned');
      }
    });

    test('SEAT-T3 D 당일은 아직 좌석이다', () {
      final fn = _slice(cf,
          'async function processExpiredSeatReconciliation(',
          '// 🔥 통합 마스터 스케줄러');
      expect(fn, contains('if (nowDateNum <= srvKstDateNum(end.toDate())) continue;'));
    });

    test('SEAT-T4 복합 인덱스를 요구하지 않는다', () {
      final fn = _slice(cf,
          'async function processExpiredSeatReconciliation(',
          '// 🔥 통합 마스터 스케줄러');
      // 범위 조건은 workEndDate 한 필드뿐 — 나머지는 메모리에서 거른다.
      expect(fn, contains('.where("workEndDate", ">="'));
      expect(fn, contains('.where("workEndDate", "<", now)'));
      expect(fn, isNot(contains('.where("status", "in"')),
          reason: '범위 + equality 복합은 인덱스를 요구한다');
      expect(fn, contains('if (!CONFIRMED_STATUSES.includes('));
    });

    test('SEAT-E 재계산은 멱등이다 — 이중 차감이 없다', () {
      // increment(-1) 이 아니라 절대값 대입이다.
      expect(cf, contains('totalConfirmed: confirmedCnt,'));
      expect(cf, contains('const confirmedCnt = seats.to;'));
      final fn = _slice(cf,
          'async function processExpiredSeatReconciliation(',
          '// 🔥 통합 마스터 스케줄러');
      expect(fn, isNot(contains('increment(-1)')));
    });
  });

  // ══════════════════════════════════════════════════════════════
  // A·D·M. 이력 보존
  // ══════════════════════════════════════════════════════════════

  group('SEAT-H 이력', () {
    test('SEAT-M 이번 변경이 아무것도 지우지 않는다', () {
      final counter = _slice(cf,
          'function srvOccupiesSeatToday(', '[.6-P3] 근무 한 건의 canonical 달력 값');
      for (final banned in ['delete()', 'FieldValue.delete']) {
        expect(counter, isNot(contains(banned)));
      }
    });

    test('SEAT-A 확정 상태 자체를 바꾸지 않는다', () {
      // 좌석에서 빠지는 것과 status 가 바뀌는 것은 다른 축이다.
      final counter = _slice(cf,
          'function srvOccupiesSeatToday(', '[.6-P3] 근무 한 건의 canonical 달력 값');
      expect(counter, isNot(contains('CANCELED')));
      // 종료 전환(퇴사·해지)은 여전히 별도 경로다.
      expect(cf, contains('async function processExitEffectiveTransition('));
    });

    test('SEAT-L UNKNOWN != ZERO 계약 유지', () {
      for (final path in [
        'lib/widgets/admin/cards/admin_to_group_card.dart',
        'lib/widgets/admin/cards/admin_to_item_card.dart',
      ]) {
        expect(_read(path), contains('stats == null'),
            reason: '$path — DEVICE.1A 계약이 풀렸다');
      }
    });

    test('SEAT-K OLD 종료 + NEW 활성 → 좌석 하나', () {
      // 좌석 판정이 문서별이므로 끝난 쪽만 빠진다.
      final counter = _slice(cf,
          'function srvOccupiesSeatToday(', '[.6-P3] 근무 한 건의 canonical 달력 값');
      // [R7-7] 이름이 공유 함수로 바뀌었다. 판정 내용은 그대로다.
      expect(counter, contains('d.get("actualResignDate") ??'));
      expect(cf, contains('const occupiesSeatToday = srvOccupiesSeatToday;'));
      expect(cf, contains('byWorkType.set(wt, (byWorkType.get(wt) ?? 0) + 1)'));
    });
  });
}
