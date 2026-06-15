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
}
