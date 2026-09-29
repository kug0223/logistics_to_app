// [CONTRACT-PERIOD-RULE] 계약 기간 종료일 — 한 규칙, 두 구현, 공유 벡터.
//
// 이 파일은 세 묶음이다.
//
//   **CPP-R (신규 계약 규칙)** — 선택한 규칙 v2 를 공유 벡터로 검증한다.
//     벡터 파일 하나(`test/fixtures/contract_period_vectors.json`)가
//     Dart(`lib/utils/contract_period.dart`)와
//     TypeScript(`functions/src/contract_period.ts`)를 묶는다.
//
//   **CPP-D (진단 · 예전 식과의 차이)** — 고친 것이 무엇인지 남긴다.
//     v1 클라이언트 식과 v1 서버 식을 그대로 옮겨 놓고, 새 규칙과 어떻게
//     달랐는지 표로 고정한다. **기대값은 예전 결함이고 바람직한 값이 아니다.**
//     지우지 않는 이유: 어느 날 누가 "왜 이렇게 계산하나" 를 물을 때,
//     무엇을 왜 버렸는지가 코드 안에 남아 있어야 한다.
//
//   **CPP-L (기존 계약 보호)** — 서명된 계약서가 소급 변경되지 않는다는
//     경계를 고정한다.
//
// ── 감사 경위 ───────────────────────────────────────────────────
//   종료일을 만드는 식이 두 벌이었다. 지원자는 `1/31 + 1개월` 을 2/27 까지로
//   보고 지원했는데, 확정 서버가 3/3 으로 덮어썼고 그 값이 계약서·근무 효력에
//   쓰였다. 1일 시작 사례도 15days·1month·1year 모두 하루씩 달랐다.
//   자세한 경위·연결표는 `docs/r7-contract-monthend-audit.md`.
//
//   `workEndDate` 의 의미는 **마지막 근무 가능일(inclusive)** 이다
//   (`effectiveEndDate` · `occupiesSeatOn` · `isWorkingOnDate` 세 곳 일치).
//   그 의미 위에서 규칙 v2 를 골랐다 — 초일산입(민법 157 단서) +
//   월·연 단위는 민법 160②③(해당일의 전일, 해당일 없으면 그 월의 말일).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/models/core/to_model.dart';
import 'package:ALfit/utils/contract_period.dart';
import 'package:ALfit/utils/format_helper.dart';

// ── 공유 벡터 ─────────────────────────────────────────────────────
const _vectorPath = 'test/fixtures/contract_period_vectors.json';

Map<String, dynamic> _loadVectors() {
  final f = File(_vectorPath);
  expect(f.existsSync(), isTrue, reason: '$_vectorPath 를 찾지 못함');
  return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
}

String _src(String p) {
  final f = File(p);
  expect(f.existsSync(), isTrue, reason: '$p 를 찾지 못함');
  return f.readAsStringSync().replaceAll('\r\n', '\n');
}

/// KST 달력일 문자열. 저장된 instant 든 키든 같은 자로 읽는다.
String _kst(DateTime v) => FormatHelper.formatDateISO(v);

DateTime _day(String iso) => FormatHelper.parseKstDateKey(iso)!;

TOModel _to(String periodType) => TOModel(
      id: 'to1',
      businessId: 'biz1',
      businessName: '테스트 사업장',
      title: '테스트 공고',
      type: TOType.contract,
      contractPeriodType: periodType,
      creatorUID: 'uid-001',
      createdAt: DateTime(2026, 1, 1),
    );

int _dayGap(DateTime a, DateTime b) =>
    FormatHelper.toKstDate(b).difference(FormatHelper.toKstDate(a)).inDays;

// ── 예전 식들 (진단 전용, 되살리지 않는다) ─────────────────────────

/// v1 클라이언트: `(start + N개월, 월말 clamp) - 1일`.
DateTime _v1Client(DateTime start, String periodType) {
  DateTime addMonths(int months) {
    final rawMonth = start.month + months;
    final y = start.year + (rawMonth - 1) ~/ 12;
    final m = ((rawMonth - 1) % 12) + 1;
    final last = DateTime.utc(y, m + 1, 0).day;
    return DateTime.utc(y, m, start.day.clamp(1, last));
  }

  switch (periodType) {
    case '15days':
      return start.add(const Duration(days: 14));
    case '1month':
      return addMonths(1).subtract(const Duration(days: 1));
    case '3months':
      return addMonths(3).subtract(const Duration(days: 1));
    case '6months':
      return addMonths(6).subtract(const Duration(days: 1));
    case '1year':
      return addMonths(12).subtract(const Duration(days: 1));
  }
  throw ArgumentError(periodType);
}

/// v1 서버: `setMonth(+N)` — `- 1일` 도 clamp 도 없다.
DateTime _v1Server(DateTime start, String periodType) {
  switch (periodType) {
    case '15days':
      return DateTime.utc(start.year, start.month, start.day + 15);
    case '1month':
      return DateTime.utc(start.year, start.month + 1, start.day);
    case '3months':
      return DateTime.utc(start.year, start.month + 3, start.day);
    case '6months':
      return DateTime.utc(start.year, start.month + 6, start.day);
    case '1year':
      return DateTime.utc(start.year + 1, start.month, start.day);
  }
  throw ArgumentError(periodType);
}

void main() {
  // ══════════════════════════════════════════════════════════════
  // CPP-R. 신규 계약 규칙 v2 — 공유 벡터
  // ══════════════════════════════════════════════════════════════
  group('CPP-R. 규칙 v2 (공유 벡터)', () {
    late final Map<String, dynamic> spec;
    late final List<Map<String, dynamic>> vectors;

    setUpAll(() {
      spec = _loadVectors();
      vectors = (spec['vectors'] as List)
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    });

    test('CPP-R0 벡터 파일과 두 구현이 같은 규칙 버전을 쓴다', () {
      expect(spec['ruleVersion'], kContractPeriodRuleVersion,
          reason: 'Dart 구현과 벡터 파일');
      final ts = _src('functions/src/contract_period.ts');
      expect(
          ts.contains('export const CONTRACT_PERIOD_RULE_VERSION = '
              '"$kContractPeriodRuleVersion";'),
          isTrue,
          reason: 'TypeScript 구현도 같은 버전이어야 한다');
      expect(vectors, isNotEmpty);
    });

    for (final periodType in kContractPresetPeriodTypes) {
      test('CPP-R1 $periodType 벡터가 존재한다', () {
        expect(vectors.any((v) => v['periodType'] == periodType), isTrue,
            reason: '규칙이 다루는 유형은 벡터로 덮여 있어야 한다');
      });
    }

    test('CPP-R2 Dart 구현이 모든 벡터를 통과한다', () {
      for (final v in vectors) {
        final start = _day(v['start'] as String);
        final got = contractPeriodEndKstDay(start, v['periodType'] as String);
        expect(got, isNotNull, reason: '${v['start']} ${v['periodType']}');
        expect(_kst(got!), v['end'],
            reason: '${v['start']} + ${v['periodType']} → ${v['why']}');
      }
    });

    test('CPP-R3 TOModel 이 같은 규칙을 지난다 — 식을 따로 갖지 않는다', () {
      for (final v in vectors) {
        final start = _day(v['start'] as String);
        final got = _to(v['periodType'] as String).computeContractEndDate(start);
        expect(_kst(got), v['end'],
            reason: '${v['start']} + ${v['periodType']}');
      }
      // 규칙이 모델 안에 복제돼 있지 않은지 소스로 확인한다.
      final model = _src('lib/models/core/to_model.dart');
      expect(model.contains('contractPeriodEndInstant('), isTrue);
      expect(model.contains('_addMonths'), isFalse,
          reason: '예전 식 헬퍼가 남아 있지 않다');
    });

    test('CPP-R4 저장값은 KST 자정 instant 다 — DATE_ONLY 관례', () {
      // `slot.date`·`workDate` 와 같은 꼴이어야 서버가 같은 값을 만든다.
      final end = contractPeriodEndInstant(_day('2026-01-31'), '1month')!;
      expect(_kst(end), '2026-02-28');
      expect(end.millisecondsSinceEpoch,
          FormatHelper.kstDayRange(end).$1.millisecondsSinceEpoch,
          reason: 'KST 그 날 00:00 이어야 한다');
    });

    test('CPP-R5 규칙 밖의 유형에는 날짜를 지어내지 않는다', () {
      expect(contractPeriodEndKstDay(_day('2026-01-01'), 'custom'), isNull);
      expect(contractPeriodEndKstDay(_day('2026-01-01'), null), isNull);
      expect(contractPeriodEndKstDay(_day('2026-01-01'), '2weeks'), isNull);
    });

    test('CPP-R6 초일산입 — 실효 기간이 약정과 같다', () {
      int span(String iso, String type) {
        final s = _day(iso);
        return _dayGap(s, contractPeriodEndKstDay(s, type)!) + 1;
      }

      expect(span('2026-01-01', '15days'), 15);
      expect(span('2026-05-15', '15days'), 15);
      expect(span('2026-01-01', '1month'), 31, reason: '1월 전체');
      expect(span('2026-01-01', '1year'), 365, reason: '2026 전체');
      expect(span('2028-01-01', '1year'), 366, reason: '윤년 전체');
    });

    test('CPP-R7 시간대 독립 — 같은 KST 날짜는 같은 답을 낸다', () {
      // 달력에서 고른 날짜는 성분으로 읽는다(`kstDayKeyOfCivil`).
      // 기기 오프셋이 무엇이든 같은 civil 날짜면 같은 종료일이다.
      final to = _to('1month');
      final expected = '2026-02-28';
      for (final civil in [
        DateTime(2026, 1, 31), // 기기 로컬 자정
        DateTime.utc(2026, 1, 31), // UTC 자정
        DateTime(2026, 1, 31, 23, 59), // 그 날 늦은 시각
      ]) {
        expect(_kst(to.computeContractEndDate(civil)), expected,
            reason: '$civil');
      }
    });

    test('CPP-R8 TypeScript 구현이 같은 규칙을 적고 있다 (앵커)', () {
      final ts = _src('functions/src/contract_period.ts');
      // ③ 해당일 없음 → 그 월의 말일
      expect(ts.contains('if (start.day > lastDay) {'), isTrue);
      expect(ts.contains('return {year: targetYear, month: targetMonth, '
          'day: lastDay};'), isTrue);
      // ② 해당일의 전일
      expect(ts.contains('Date.UTC(targetYear, targetMonth - 1, start.day) - '
          '24 * 60 * 60 * 1000'), isTrue);
      // 일 단위 초일산입
      expect(ts.contains('start.day + days - 1'), isTrue);
      // KST 달력일로 읽고 KST 자정으로 돌려준다
      expect(ts.contains('export function kstDayOfMs('), isTrue);
      expect(ts.contains('Date.UTC(d.year, d.month - 1, d.day) - '
          'KST_OFFSET_MS'), isTrue);
    });

    test('CPP-R9 확정 핸들러가 그 규칙만 쓴다 — 인라인 식이 남지 않았다', () {
      final cf = _src('functions/src/index.ts');
      expect(cf.contains('contractPeriodEndMs(startTs.toMillis(), periodType)'),
          isTrue);
      for (final gone in const [
        'd.setMonth(d.getMonth() + 1)',
        'd.setMonth(d.getMonth() + 3)',
        'd.setMonth(d.getMonth() + 6)',
        'd.setFullYear(d.getFullYear() + 1)',
        'd.setDate(d.getDate() + 15)',
      ]) {
        expect(cf.contains(gone), isFalse, reason: '예전 서버 식 잔존: $gone');
      }
      // 서버 재검증 자체는 유지한다 — 클라이언트 값을 신뢰하지 않는다.
      expect(cf.contains('[M2-FIX] !appDataPre.workEndDate 조건 제거'), isTrue);
      expect(
          cf.contains('if (computedWorkEndDate) '
              'batchUpdate.workEndDate = computedWorkEndDate;'),
          isTrue);
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CPP-P. 지원 때 본 날짜가 조용히 바뀌지 않는다
  // ══════════════════════════════════════════════════════════════
  group('CPP-P. PENDING → 확정 시 종료일 변경 고지', () {
    test('CPP-P1 서버가 차이를 기록하고 반환한다', () {
      final cf = _src('functions/src/index.ts');
      // 같은 KST 날짜의 다른 시각은 변경으로 세지 않는다.
      expect(
          cf.contains('if (presented && '
              'srvKstDayStartMs(presented.toMillis()) !== endMs) {'),
          isTrue);
      // 제시된 값을 지우지 않고 함께 보관한다.
      expect(cf.contains('batchUpdate.workEndDatePresentedAtApply ='), isTrue);
      expect(cf.contains('batchUpdate.workEndDateRevisedAt ='), isTrue);
      // 어느 규칙으로 계산했는지도 남긴다.
      expect(
          cf.contains('batchUpdate.workEndDateRuleVersion = '
              'CONTRACT_PERIOD_RULE_VERSION;'),
          isTrue);
      // 호출자가 그 자리에서 알 수 있게 응답에 담는다.
      expect(cf.contains('periodRevision: periodRevision'), isTrue);
    });

    test('CPP-P2 클라이언트가 그 응답을 사람이 읽는 문구로 띄운다', () {
      final svc = _src('lib/services/firestore/application_firestore.dart');
      expect(svc.contains("data['periodRevision']"), isTrue);
      expect(svc.contains('계약 종료일이 \$from → \$to 로 정정되었습니다.'), isTrue);
      expect(svc.contains('지원자에게 안내가 필요할 수 있습니다.'), isTrue);
    });

    test('CPP-P3 예전 식으로 만들어진 PENDING 값은 실제로 달라진다', () {
      // 수정 전 PENDING 지원서가 들고 있는 값(= v1 클라이언트 식)과
      // 확정 시 적용되는 v2 값이 다르다는 것을 수치로 고정한다.
      //   → CPP-P1/P2 의 고지 경로가 실제로 발동하는 입력이다.
      for (final iso in const ['2026-01-31', '2026-01-30', '2026-01-29']) {
        final start = _day(iso);
        final v1 = _v1Client(start, '1month');
        final v2 = contractPeriodEndKstDay(start, '1month')!;
        expect(_kst(v1) == _kst(v2), isFalse, reason: '$iso 은 달라야 한다');
      }
      // 월중 기산은 v1·v2 가 같다 → 고지가 뜨지 않는다(정상 대조).
      final mid = _day('2026-05-15');
      expect(_kst(_v1Client(mid, '1month')),
          _kst(contractPeriodEndKstDay(mid, '1month')!));
    });

    test('CPP-P4 희망 시작일도 KST 자정으로 보낸다 — 기산일이 기기에 안 흔들린다', () {
      final svc = _src('lib/services/firestore/application_firestore.dart');
      expect(
          svc.contains('FormatHelper.kstMidnightOfKstDay(\n'
              '                  FormatHelper.kstDayKeyOfCivil(desiredStartDate))'),
          isTrue,
          reason: '달력에서 고른 날짜의 성분을 KST 자정 instant 로');
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CPP-L. 기존 계약 보호
  // ══════════════════════════════════════════════════════════════
  group('CPP-L. 서명된 계약은 소급 변경되지 않는다', () {
    test('CPP-L1 contractEnd 는 스냅샷 문자열로 동결된다', () {
      final model = _src('lib/models/core/employment_contract_model.dart');
      expect(model.contains("final String? contractEnd;"), isTrue);
      expect(model.contains("'contractEnd': contractEnd,"), isTrue,
          reason: '스냅샷에 그대로 저장된다 — 읽을 때 재계산하지 않는다');
      expect(model.contains("contractEnd: m['contractEnd'],"), isTrue);
    });

    test('CPP-L2 계약서는 저장된 지원서 값을 찍는다 — 규칙을 다시 돌리지 않는다', () {
      final svc = _src('lib/services/contract_service.dart');
      expect(
          svc.contains('contractEnd: isLong && application.workEndDate != null'),
          isTrue);
      expect(svc.contains('computeContractEndDate'), isFalse,
          reason: '계약서 생성 경로는 종료일을 계산하지 않는다');
      expect(svc.contains('contractPeriodEnd'), isFalse);
    });

    test('CPP-L3 이 변경으로 기존 계약을 보정하는 코드는 없다', () {
      final cf = _src('functions/src/index.ts');
      // 확정 경로 밖에서 workEndDate 를 다시 쓰는 migration 이 없다.
      expect(cf.contains('migrateWorkEndDate'), isFalse);
      expect(cf.contains('recomputeContractEnd'), isFalse);
      for (final f in Directory('functions/src').listSync().whereType<File>()) {
        final s = f.readAsStringSync();
        expect(s.contains('snapshot.contractEnd ='), isFalse,
            reason: '${f.path} 가 서명된 스냅샷을 다시 쓴다');
      }
    });
  });

  // ══════════════════════════════════════════════════════════════
  // CPP-D. 진단 — 무엇을 고쳤는가 (기대값은 예전 결함이다)
  // ══════════════════════════════════════════════════════════════
  group('CPP-D. 예전 식과의 차이 (진단)', () {
    // [start, periodType, v1 클라이언트, v1 서버, v2(현재)]
    const table = <List<String>>[
      ['2026-01-01', '15days', '2026-01-15', '2026-01-16', '2026-01-15'],
      ['2026-01-01', '1month', '2026-01-31', '2026-02-01', '2026-01-31'],
      ['2026-01-01', '3months', '2026-03-31', '2026-04-01', '2026-03-31'],
      ['2026-01-01', '6months', '2026-06-30', '2026-07-01', '2026-06-30'],
      ['2026-01-01', '1year', '2026-12-31', '2027-01-01', '2026-12-31'],
      ['2026-01-31', '1month', '2026-02-27', '2026-03-03', '2026-02-28'],
      ['2028-01-31', '1month', '2028-02-28', '2028-03-02', '2028-02-29'],
      ['2026-01-30', '1month', '2026-02-27', '2026-03-02', '2026-02-28'],
      ['2026-01-29', '1month', '2026-02-27', '2026-03-01', '2026-02-28'],
      ['2026-03-31', '1month', '2026-04-29', '2026-05-01', '2026-04-30'],
      ['2026-08-31', '6months', '2027-02-27', '2027-03-03', '2027-02-28'],
      ['2028-02-29', '1year', '2029-02-27', '2029-03-01', '2029-02-28'],
      ['2026-05-15', '1month', '2026-06-14', '2026-06-15', '2026-06-14'],
    ];

    for (final row in table) {
      test('CPP-D ${row[0]} + ${row[1]}', () {
        final start = _day(row[0]);
        // 예전 두 식은 이렇게 갈렸다 — 이것이 고친 대상이다.
        expect(_kst(_v1Client(start, row[1])), row[2],
            reason: 'v1 클라이언트(지원 화면이 보여 준 값)');
        expect(_kst(_v1Server(start, row[1])), row[3],
            reason: 'v1 서버(계약서에 찍힌 값)');
        // 지금은 한 값이다.
        expect(_kst(contractPeriodEndKstDay(start, row[1])!), row[4],
            reason: 'v2 — 규칙 하나');
      });
    }

    test('CPP-D0 예전에는 두 식이 한 번도 일치하지 않았다', () {
      for (final row in table) {
        final start = _day(row[0]);
        expect(_kst(_v1Client(start, row[1])) == _kst(_v1Server(start, row[1])),
            isFalse,
            reason: '${row[0]} ${row[1]} — 최소 하루 차이가 있었다');
      }
    });

    test('CPP-D1 v2 는 월중 기산에서 v1 클라이언트와 같다 (좁은 수정)', () {
      // 규칙을 통째로 바꾼 것이 아니다. 월중 기산은 예전 클라이언트 식이
      // 이미 민법 160② 와 일치했고 그대로 뒀다. 달라진 것은
      //   · 해당일이 없는 달(160③) — clamp 후 또 하루 빼던 것을 말일로
      //   · 계산의 자 — 기기 로컬 성분 → KST 달력일
      //   · 서버 — 아예 다른 식이던 것을 같은 규칙으로
      for (final iso in const [
        '2026-05-15',
        '2026-01-01',
        '2026-02-28',
        '2026-12-31'
      ]) {
        final s = _day(iso);
        expect(_kst(contractPeriodEndKstDay(s, '1month')!),
            _kst(_v1Client(s, '1month')),
            reason: '$iso 은 바뀌지 않았다');
      }
    });
  });
}
