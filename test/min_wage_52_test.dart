import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/screens/super_admin/minimum_wage_settings_screen.dart';
import 'package:ALfit/utils/format_helper.dart';
import 'package:ALfit/utils/wage_calculator.dart';

/// [MW-52] 연도별 기준 선택·판정식·SA 저장 변경분 — 서버 후보(perf-20261028/c52/cand)와 같은 규칙인지 결과로 본다.
///   서버 쪽 근거: c52/s52.json(DEV 원본 ↔ 후보, 같은 fixture).
void main() {
  tearDown(() => WageCalculator.debugSetMinimumWageCache(null));

  group('MW52-1 연도별 기준 선택 — 다른 연도 값으로 대신하지 않는다', () {
    test('문서 값이 있으면 그 값', () {
      WageCalculator.debugSetMinimumWageCache({2026: 10500});
      expect(WageCalculator.minimumWageForYear(2026), 10500);
    });
    test('문서 값이 그 연도 법정 내장값보다 낮으면 내장값(법정 하한은 설정으로 내려가지 않는다)', () {
      WageCalculator.debugSetMinimumWageCache({2026: 9000});
      expect(WageCalculator.minimumWageForYear(2026), 10320);
    });
    test('손상 값(문자열·소수·0 이하)이면 확인 불가', () {
      WageCalculator.debugSetMinimumWageCache({}, corrupt: {2026});
      expect(WageCalculator.minimumWageForYear(2026), isNull);
    });
    test('문서에 없고 내장값도 없는 연도(2028)는 확인 불가 — 다른 연도 값으로 대신하지 않는다', () {
      WageCalculator.debugSetMinimumWageCache({2026: 10500, 2027: 10700});
      expect(WageCalculator.minimumWageForYear(2028), isNull);
    });
    test('[.73] 2027 은 고시 제2026-60호 내장값 10,700 — 문서가 없어도 2026 값을 쓰지 않는다', () {
      WageCalculator.debugSetMinimumWageCache({2026: 10320});
      expect(WageCalculator.minimumWageForYear(2027), 10700);
      expect(WageCalculator.minimumWageForYear(2026), 10320);
    });
    test('[.73] KST 연도 경계 — 2026-12-31 23:59 KST 는 2026, 2027-01-01 00:00 KST 는 2027(기기 시간대 무관)', () {
      WageCalculator.debugSetMinimumWageCache(null);
      final lastOf2026 = FormatHelper.toKstDate(DateTime.utc(2026, 12, 31, 14, 59)); // KST 23:59
      final firstOf2027 = FormatHelper.toKstDate(DateTime.utc(2026, 12, 31, 15, 0)); // KST 00:00
      expect(lastOf2026.year, 2026);
      expect(firstOf2027.year, 2027);
      expect(WageCalculator.minimumWageForYear(lastOf2026.year), 10320);
      expect(WageCalculator.minimumWageForYear(firstOf2027.year), 10700);
      // 같은 instant 를 기기 로컬 값으로 넘겨도 KST 달력 연도는 같다
      expect(FormatHelper.toKstDate(DateTime.utc(2026, 12, 31, 15, 0).toLocal()).year, 2027);
    });
    test('문서에 없으면 그 연도 내장값', () {
      WageCalculator.debugSetMinimumWageCache(null);
      expect(WageCalculator.minimumWageForYear(2025), 10030);
    });
  });

  group('MW52-2 일급 판정 — 정수 비교, 소정시간 0 이하는 판정 불가', () {
    String? v(int wage, String s, String e, int br) => WageCalculator.minimumWageViolation(
        wageType: 'daily', wage: wage, minimumWage: 10320, startTime: s, endTime: e, breakMinutes: br);
    test('450분: 77,399 미달 · 77,400 충족(독립 계산 10,320 × 7.5 = 77,400)', () {
      expect(v(77399, '09:00', '17:00', 30), isNotNull);
      expect(v(77400, '09:00', '17:00', 30), isNull);
    });
    test('소정 7시간 10분(430분): 경계 73,960(=10,320 × 430 / 60) — 1원 아래 미달', () {
      expect(v(73959, '09:00', '16:40', 30), isNotNull);
      expect(v(73960, '09:00', '16:40', 30), isNull);
    });
    test('휴게가 근무시간 이상이면 통과가 아니라 판정 불가', () {
      expect(v(50000, '09:00', '10:00', 60), contains('판정할 수 없습니다'));
    });
  });

  group('MW52-3 SA 저장은 바뀐 연도만, 불러온 값을 expected 로 보낸다', () {
    test('수정·추가·삭제', () {
      final c = minimumWageChanges({2025: 10030, 2026: 10320, 2027: 10800}, {2025: 10030, 2026: 10500, 2028: 11000});
      expect(c, [
        {'year': 2026, 'op': 'set', 'wage': 10500, 'expected': 10320},
        {'year': 2027, 'op': 'delete', 'expected': 10800},
        {'year': 2028, 'op': 'set', 'wage': 11000, 'expected': null},
      ]);
    });
    test('바뀐 것이 없으면 빈 목록(쓰기 없음)', () {
      expect(minimumWageChanges({2026: 10320}, {2026: 10320}), isEmpty);
    });
    test('서버 문서가 없을 때 화면 기본표는 expected null 로 추가된다', () {
      final c = minimumWageChanges({}, {2026: 10320});
      expect(c.single, {'year': 2026, 'op': 'set', 'wage': 10320, 'expected': null});
    });
  });
}
