import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/wage_calculator.dart';

/// [SA-MINWAGE.51] 앱의 최저임금 판정이 서버(지원·초대 writer)와 같은 결과를 내는가.
///   기대값은 하네스에서 DEV 배포 원본 ApplyToTO(00105)를 실제로 돌린 결과다 — perf-20261028/c51/mw51-cases.json.
///   서버 식: 시급 wage < M 거절 · 일급 wage < ceil(M × 소정분 / 60) 거절(소정분 = 시작~종료(자정 넘김 +24h) − 휴게).
///   예전 앱 식(환산시급 반올림 ≥ M)은 450분·77,399원을 통과시켰고 서버는 거절했다.
String _src(String p) => File(p).readAsStringSync().replaceAll('\r\n', '\n');

void main() {
  const m = 10320;
  // tag, wageType, wage, start, end, break, 서버 결과(true = 거절)
  const cases = [
    ['H-1', 'hourly', 10319, '09:00', '18:00', 60, true],
    ['H0', 'hourly', 10320, '09:00', '18:00', 60, false],
    ['H+1', 'hourly', 10321, '09:00', '18:00', 60, false],
    ['D480-1', 'daily', 82559, '09:00', '18:00', 60, true],
    ['D480', 'daily', 82560, '09:00', '18:00', 60, false],
    ['D300-1', 'daily', 51599, '09:00', '14:30', 30, true],
    ['D300', 'daily', 51600, '09:00', '14:30', 30, false],
    ['D450-1', 'daily', 77399, '09:00', '17:00', 30, true],
    ['Dnight', 'daily', 82560, '22:00', '07:00', 60, false],
  ];

  group('SA51-1 앱 판정 = 서버(DEV 원본) 판정', () {
    for (final c in cases) {
      test('${c[0]} ${c[1]} ${c[2]}원 ${c[3]}-${c[4]} 휴게${c[5]}', () {
        final v = WageCalculator.minimumWageViolation(
          wageType: c[1] as String, wage: c[2] as int, minimumWage: m,
          startTime: c[3] as String, endTime: c[4] as String, breakMinutes: c[5] as int);
        expect(v != null, c[6], reason: v ?? '통과');
      });
    }
    test('최저일급은 올림 — 450분 기준 77,400원', () {
      expect(WageCalculator.minimumDailyWage(m, 450), 77400);
      expect(WageCalculator.minimumDailyWage(m, 480), 82560);
    });
  });

  test('SA51-2 업무 입력 창은 등록·수정·실시간 안내 모두 같은 판정을 쓰고, 저장 직전 설정을 다시 읽는다', () {
    final d = _src('lib/widgets/pickers/create_edit_work_detail_dialog.dart');
    expect(d.contains('(wage * 60 / workMins).round()'), isFalse, reason: '반올림 환산시급 비교는 서버와 다르다');
    expect('WageCalculator.minimumWageViolation('.allMatches(d).length, greaterThanOrEqualTo(3));
    expect(d.contains("title: '최저임금 미달 경고'"), isFalse, reason: '수정 모드도 서버처럼 막는다(그래도 저장 → 아무도 지원·초대 못 받는 공고)');
    expect('await WageCalculator.loadMinimumWages();'.allMatches(d).length, 1);
  });

  test('SA51-4 로그인 뒤 최저시급을 다시 읽는다(앱 시작 때 읽기는 로그인 전이라 설정을 못 받았다)', () {
    // 기기: 관리자 등록 화면 안내 '2026년 최저시급 10,320원'(내장값) · 서버 설정 10,600 — c51/shots/c51-editor-block.png
    final u = _src('lib/providers/user_provider.dart');
    expect(u.contains('if (loaded != null) unawaited(WageCalculator.loadMinimumWages());'), isTrue);
  });

  test('SA51-3 SA 저장은 연도 삭제를 반영하고(mergeFields), 불러오기 실패 상태에서는 저장하지 않는다', () {
    // 재현: c51/merge51.json — set(merge:true) 는 지운 연도를 문서에 남긴다.
    final s = _src('lib/screens/super_admin/minimum_wage_settings_screen.dart');
    // [.52] 저장은 연도별 변경 callable 로 옮겼다(변경분 결과 시험: min_wage_52_test MW52-3). 문서 직접 쓰기는 남지 않는다.
    expect(s.contains("httpsCallable('callableSetMinimumWages')"), isTrue);
    expect(s.contains(".doc('wage_config').set("), isFalse);
    expect(s.contains('SetOptions(merge: true)'), isFalse);
    expect(s.contains('if (_loadFailed) return;'), isTrue);
    expect(s.contains("'저장 실패: \$e'"), isFalse);
    expect(s.contains("'데이터 로드 실패: \$e'"), isFalse);
    expect(s.contains('삭제하면 해당 연도는 직전 연도 값이 적용됩니다'), isFalse, reason: '서버·앱 폴백은 내장 고시값이다(c51 Y27-none)');
    expect(s.contains('가장 최근 내장 연도 값'), isFalse, reason: '[.52] 내장값이 없는 연도는 확인 불가로 막는다');
  });
}
