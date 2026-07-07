import 'package:flutter_test/flutter_test.dart';
import 'package:ALfit/utils/format_helper.dart';

void main() {
  // ────────────────────────────────────────────────
  // formatPhone
  // ────────────────────────────────────────────────
  group('FormatHelper.formatPhone', () {
    test('11자리 휴대폰 → 010-XXXX-XXXX', () {
      expect(FormatHelper.formatPhone('01012345678'), '010-1234-5678');
    });

    test('하이픈 포함 입력도 정상 파싱', () {
      expect(FormatHelper.formatPhone('010-1234-5678'), '010-1234-5678');
    });

    test('10자리 서울 02 번호 → 02-XXXX-XXXX', () {
      expect(FormatHelper.formatPhone('0212345678'), '02-1234-5678');
    });

    test('10자리 일반 지역번호 → XXX-XXX-XXXX', () {
      expect(FormatHelper.formatPhone('0311234567'), '031-123-4567');
    });

    test('9자리 서울 단축 → 02-XXX-XXXX', () {
      expect(FormatHelper.formatPhone('021234567'), '02-123-4567');
    });

    test('인식 불가 번호 → 원본 반환', () {
      expect(FormatHelper.formatPhone('12345'), '12345');
    });
  });

  // ────────────────────────────────────────────────
  // formatBusinessNumber
  // ────────────────────────────────────────────────
  group('FormatHelper.formatBusinessNumber', () {
    test('10자리 숫자 → XXX-XX-XXXXX', () {
      expect(FormatHelper.formatBusinessNumber('1234567890'), '123-45-67890');
    });

    test('하이픈 포함 입력도 동일하게 포맷', () {
      expect(FormatHelper.formatBusinessNumber('123-45-67890'), '123-45-67890');
    });

    test('5자리 이상 → 부분 포맷 적용', () {
      expect(FormatHelper.formatBusinessNumber('123456'), '123-45-6');
    });

    test('3자리 미만 → 원본 반환', () {
      expect(FormatHelper.formatBusinessNumber('12'), '12');
    });
  });

  // ────────────────────────────────────────────────
  // formatWage / formatNumber
  // ────────────────────────────────────────────────
  group('FormatHelper.formatWage', () {
    test('10,000원', () {
      expect(FormatHelper.formatWage(10000), '10,000원');
    });

    test('1,500,000원', () {
      expect(FormatHelper.formatWage(1500000), '1,500,000원');
    });

    test('999원 (천단위 없음)', () {
      expect(FormatHelper.formatWage(999), '999원');
    });
  });

  group('FormatHelper.formatNumber', () {
    test('10,000', () {
      expect(FormatHelper.formatNumber(10000), '10,000');
    });

    test('1,500,000', () {
      expect(FormatHelper.formatNumber(1500000), '1,500,000');
    });

    test('999 (콤마 없음)', () {
      expect(FormatHelper.formatNumber(999), '999');
    });
  });

  // ────────────────────────────────────────────────
  // compareTime
  // ────────────────────────────────────────────────
  group('FormatHelper.compareTime', () {
    test('같은 시간 → 0', () {
      expect(FormatHelper.compareTime('09:00', '09:00'), 0);
    });

    test('time1이 이르면 음수', () {
      expect(FormatHelper.compareTime('08:00', '09:00'), isNegative);
    });

    test('time1이 늦으면 양수', () {
      expect(FormatHelper.compareTime('18:30', '09:00'), isPositive);
    });

    test('시간 같고 분만 다를 때', () {
      expect(FormatHelper.compareTime('09:00', '09:30'), isNegative);
      expect(FormatHelper.compareTime('09:30', '09:00'), isPositive);
    });

    test('잘못된 형식 → 0 반환 (예외 삼킴)', () {
      expect(FormatHelper.compareTime('invalid', '09:00'), 0);
    });
  });

  // ────────────────────────────────────────────────
  // isEmoji
  // ────────────────────────────────────────────────
  group('FormatHelper.isEmoji', () {
    test('빈 문자열 → false', () {
      expect(FormatHelper.isEmoji(''), isFalse);
    });

    test('이모지(이모티콘 범위) → true', () {
      expect(FormatHelper.isEmoji('😀'), isTrue); // 0x1F600 (이모티콘)
      expect(FormatHelper.isEmoji('🚀'), isTrue); // 0x1F680 (교통/지도)
      expect(FormatHelper.isEmoji('🎉'), isTrue); // 0x1F389 (기타 심볼)
    });

    test('범위 밖 특수문자(⭐ U+2B50) → false', () {
      expect(FormatHelper.isEmoji('⭐'), isFalse); // 검사 범위 미포함
    });

    test('한글 → false', () {
      expect(FormatHelper.isEmoji('가'), isFalse);
    });

    test('영문 → false', () {
      expect(FormatHelper.isEmoji('A'), isFalse);
    });

    test('이모지+텍스트 혼합 → 첫 글자 기준 true', () {
      expect(FormatHelper.isEmoji('😀텍스트'), isTrue);
    });
  });

  // ────────────────────────────────────────────────
  // formatWage 음수
  // ────────────────────────────────────────────────
  group('FormatHelper.formatWage 음수', () {
    test('-10,000원', () {
      expect(FormatHelper.formatWage(-10000), '-10,000원');
    });

    test('-1,500,000원', () {
      expect(FormatHelper.formatWage(-1500000), '-1,500,000원');
    });

    test('0원', () {
      expect(FormatHelper.formatWage(0), '0원');
    });
  });

  // ────────────────────────────────────────────────
  // 날짜 포맷팅
  // ────────────────────────────────────────────────
  group('FormatHelper 날짜 포맷', () {
    final d = DateTime(2026, 6, 1); // 월요일

    test('formatDateISO → "2026-06-01"', () {
      expect(FormatHelper.formatDateISO(d), '2026-06-01');
    });

    test('formatDateDot → "2026.06.01"', () {
      expect(FormatHelper.formatDateDot(d), '2026.06.01');
    });

    test('formatDateStamp → "20260601"', () {
      expect(FormatHelper.formatDateStamp(d), '20260601');
    });

    test('formatDateCompact → "6/1(월)"', () {
      expect(FormatHelper.formatDateCompact(d), '6/1(월)');
    });

    test('formatDate → "6/1 (월)"', () {
      expect(FormatHelper.formatDate(d), '6/1 (월)');
    });

    test('formatDateShort → "6/1"', () {
      expect(FormatHelper.formatDateShort(d), '6/1');
    });

    test('formatDateLong → "2026년 6월 1일 (월)"', () {
      expect(FormatHelper.formatDateLong(d), '2026년 6월 1일 (월)');
    });

    test('formatDateKorean → "6월 1일 (월)"', () {
      expect(FormatHelper.formatDateKorean(d), '6월 1일 (월)');
    });

    test('formatYearMonth → "2026년 6월"', () {
      expect(FormatHelper.formatYearMonth(d), '2026년 6월');
    });

    test('formatYearMonthISO → "2026-06"', () {
      expect(FormatHelper.formatYearMonthISO(d), '2026-06');
    });

    test('formatDateRange → "6/1 ~ 6/30"', () {
      final end = DateTime(2026, 6, 30);
      expect(FormatHelper.formatDateRange(d, end), '6/1 ~ 6/30');
    });

    test('formatDateTime → "6/1 09:05"', () {
      final dt = DateTime(2026, 6, 1, 9, 5);
      expect(FormatHelper.formatDateTime(dt), '6/1 09:05');
    });

    test('formatTime → "09:05"', () {
      final dt = DateTime(2026, 6, 1, 9, 5);
      expect(FormatHelper.formatTime(dt), '09:05');
    });

    test('formatHourMinute(9, 5) → "09:05"', () {
      expect(FormatHelper.formatHourMinute(9, 5), '09:05');
    });

    test('formatTimeWithSeconds → "18:30:05"', () {
      final dt = DateTime(2026, 6, 1, 18, 30, 5);
      expect(FormatHelper.formatTimeWithSeconds(dt), '18:30:05');
    });
  });

  // ────────────────────────────────────────────────
  // formatWorkPeriod
  // ────────────────────────────────────────────────
  group('FormatHelper.formatWorkPeriod', () {
    final d0 = DateTime(2026, 6, 1); // 월요일
    final d5 = DateTime(2026, 6, 6); // 토요일

    test('단기 1일 (endDate null) → startStr만', () {
      expect(
        FormatHelper.formatWorkPeriod(startDate: d0, isLongTerm: false),
        '6/1(월)',
      );
    });

    test('단기 같은 날 (start==end) → startStr만', () {
      expect(
        FormatHelper.formatWorkPeriod(startDate: d0, endDate: d0, isLongTerm: false),
        '6/1(월)',
      );
    });

    test('단기 여러일, dayCount 직접 전달', () {
      expect(
        FormatHelper.formatWorkPeriod(
          startDate: d0, endDate: d5, isLongTerm: false, dayCount: 5,
        ),
        '6/1(월)~6/6(토) · 5일',
      );
    });

    test('장기, workDays 있음 → "start~ · 요일나열"', () {
      expect(
        FormatHelper.formatWorkPeriod(
          startDate: d0, isLongTerm: true, workDays: ['월', '수', '금'],
        ),
        '6/1(월)~ · 월,수,금',
      );
    });

    test('장기, endDate 있음 + workDays', () {
      expect(
        FormatHelper.formatWorkPeriod(
          startDate: d0, endDate: d5, isLongTerm: true, workDays: ['월', '화'],
        ),
        '6/1(월) ~ 6/6(토) · 월,화',
      );
    });

    test('장기, workDays 없음 → "start~"', () {
      expect(
        FormatHelper.formatWorkPeriod(startDate: d0, isLongTerm: true),
        '6/1(월)~',
      );
    });
  });

  // ────────────────────────────────────────────────
  // formatWorkDays — 7가지 분기
  // ────────────────────────────────────────────────
  group('FormatHelper.formatWorkDays', () {
    test('null → ""', () {
      expect(FormatHelper.formatWorkDays(null), '');
    });

    test('빈 리스트 → ""', () {
      expect(FormatHelper.formatWorkDays([]), '');
    });

    test('7일 → "매일"', () {
      expect(
        FormatHelper.formatWorkDays(['월','화','수','목','금','토','일']),
        '매일',
      );
    });

    test('평일 5일 → "평일(월~금)"', () {
      expect(
        FormatHelper.formatWorkDays(['월','화','수','목','금']),
        '평일(월~금)',
      );
    });

    test('주말 2일 → "주말(토,일)"', () {
      expect(FormatHelper.formatWorkDays(['토','일']), '주말(토,일)');
    });

    test('주6일(일 휴무) → "주6일(일 휴무)"', () {
      expect(
        FormatHelper.formatWorkDays(['월','화','수','목','금','토']),
        '주6일(일 휴무)',
      );
    });

    test('주5일 비평일(월~목+토) → "주5일(금,일 휴무)"', () {
      // 금,일 없음
      expect(
        FormatHelper.formatWorkDays(['월','화','수','목','토']),
        '주5일(금,일 휴무)',
      );
    });

    test('주3일 → "주3일(월,수,금)"', () {
      expect(
        FormatHelper.formatWorkDays(['월','수','금']),
        '주3일(월,수,금)',
      );
    });

    test('입력 순서 무관하게 월~일 정렬', () {
      // 역순 입력해도 동일 결과
      expect(
        FormatHelper.formatWorkDays(['일','토','월','화','수','목','금']),
        '매일',
      );
    });
  });

  // ────────────────────────────────────────────────
  // parseAddressCity / parseAddressDistrict / formatLocation
  // ────────────────────────────────────────────────
  group('FormatHelper 주소 파싱', () {
    test('parseAddressCity: 경기도 → 오산시', () {
      expect(FormatHelper.parseAddressCity('경기도 오산시 세교동 123-45'), '오산시');
    });

    test('parseAddressCity: 서울특별시 → 강남구', () {
      expect(FormatHelper.parseAddressCity('서울특별시 강남구 역삼동 123'), '강남구');
    });

    test('parseAddressCity: 부산광역시 → 해운대구', () {
      expect(FormatHelper.parseAddressCity('부산광역시 해운대구 우동 456'), '해운대구');
    });

    test('parseAddressCity: null → null', () {
      expect(FormatHelper.parseAddressCity(null), isNull);
    });

    test('parseAddressCity: 빈 문자열 → null', () {
      expect(FormatHelper.parseAddressCity(''), isNull);
    });

    test('parseAddressDistrict: 세교동 추출', () {
      expect(FormatHelper.parseAddressDistrict('경기도 오산시 세교동 123-45'), '세교동');
    });

    test('parseAddressDistrict: 역삼동 추출', () {
      expect(FormatHelper.parseAddressDistrict('서울특별시 강남구 역삼동 123'), '역삼동');
    });

    test('parseAddressDistrict: null → null', () {
      expect(FormatHelper.parseAddressDistrict(null), isNull);
    });

    test('formatLocation: address에서 시+동 조합', () {
      expect(
        FormatHelper.formatLocation(address: '경기도 오산시 세교동 123-45'),
        '오산시 세교동',
      );
    });

    test('formatLocation: city/district 직접 전달 (address 무시)', () {
      expect(
        FormatHelper.formatLocation(city: '강남구', district: '역삼동'),
        '강남구 역삼동',
      );
    });

    test('formatLocation: city만 있음', () {
      expect(FormatHelper.formatLocation(city: '오산시'), '오산시');
    });

    test('formatLocation: 모두 null → ""', () {
      expect(FormatHelper.formatLocation(), '');
    });
  });

  // ────────────────────────────────────────────────
  // formatCompactHours / calcNetWorkTime
  // ────────────────────────────────────────────────
  group('FormatHelper.formatCompactHours', () {
    test('0분 → "0h"', () => expect(FormatHelper.formatCompactHours(0), '0h'));
    test('음수 → "0h"', () => expect(FormatHelper.formatCompactHours(-10), '0h'));
    test('60분 → "1h"', () => expect(FormatHelper.formatCompactHours(60), '1h'));
    test('90분 → "1.5h"', () => expect(FormatHelper.formatCompactHours(90), '1.5h'));
    test('480분 → "8h"', () => expect(FormatHelper.formatCompactHours(480), '8h'));
    test('30분 → "0.5h"', () => expect(FormatHelper.formatCompactHours(30), '0.5h'));
  });

  group('FormatHelper.calcNetWorkTime', () {
    test('09:00~18:00 break 60 → "7h"', () {
      expect(FormatHelper.calcNetWorkTime('09:00', '18:00', breakMinutes: 60), '8h');
    });

    test('09:00~17:00 break 60 → "7h"', () {
      expect(FormatHelper.calcNetWorkTime('09:00', '17:00', breakMinutes: 60), '7h');
    });

    test('자정 넘김 22:00~06:00 break 0 → "8h"', () {
      expect(FormatHelper.calcNetWorkTime('22:00', '06:00'), '8h');
    });

    test('휴게가 근무보다 많으면 ""', () {
      expect(FormatHelper.calcNetWorkTime('09:00', '09:30', breakMinutes: 60), '');
    });
  });

  // ────────────────────────────────────────────────
  // formatWageWithType / formatWageRange / getWageTypeLabel
  // ────────────────────────────────────────────────
  group('FormatHelper 급여 포맷', () {
    test('getWageTypeLabel: hourly → 시급', () {
      expect(FormatHelper.getWageTypeLabel('hourly'), '시급');
    });

    test('getWageTypeLabel: daily → 일급', () {
      expect(FormatHelper.getWageTypeLabel('daily'), '일급');
    });

    test('getWageTypeLabel: monthly → 월급', () {
      expect(FormatHelper.getWageTypeLabel('monthly'), '월급');
    });

    test('getWageTypeLabel: per_case → 건당', () {
      expect(FormatHelper.getWageTypeLabel('per_case'), '건당');
    });

    test('getWageTypeLabel: 알 수 없음 → 급여', () {
      expect(FormatHelper.getWageTypeLabel('unknown'), '급여');
    });

    test('formatWageWithType: 시급 11,000원', () {
      expect(FormatHelper.formatWageWithType(11000, 'hourly'), '시급 11,000원');
    });

    test('formatWageRange: 동일 금액 → 단일 표시', () {
      expect(FormatHelper.formatWageRange(10320, 10320, 'hourly'), '시급 10,320원');
    });

    test('formatWageRange: 범위 → minWage~maxWage', () {
      expect(FormatHelper.formatWageRange(10000, 12000, 'hourly'), '시급 10,000~12,000원');
    });
  });
}
